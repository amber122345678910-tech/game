--!strict
-- События сервера по расписанию от серверного времени (workspace:GetServerTimeNow()):
--  * Суперячейка — каждые Period с от старта сервера + Offset, Duration с: удары чаще и дороже, больше золотых
--    (модификаторы StrikeService.setModifiers);
--  * Шаровая молния — плывёт над островом, где больше всего игроков, и роняет общие кольца каждые HitInterval;
--    каждая поимка (ИДЕАЛЬНО/ХОРОШО) отнимает 1 HP; HP = игроки × HpPerPlayer; награда — по вкладу;
--  * Радужная молния — объявление за Announce с (Effect rainbowWarn), потом огромное общее кольцо;
--    награду получает каждый поймавший (доход за RewardMinutes + гарантированный радужный фульгурит);
--  * Чёрная молния Перуна — StrikeService.onPerun: баннер и Effect perun всем; когда её ловят — «Я видел!»
--    всем, кто был в WitnessRadius от поймавшего.
-- События не накладываются: если одно идёт, следующее ждёт его конца. За WarnBefore с — предупреждение.
-- Атрибуты GameState: Event, EventEnds, NextSupercell, NextBall, NextRainbow, Ball*.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Zones = require(Shared:WaitForChild("Zones"))

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FulguriteService = require(script.Parent.FulguriteService)
local PlayerService = require(script.Parent.PlayerService)
local StrikeService = require(script.Parent.StrikeService)

export type Kind = "supercell" | "ball" | "rainbow"

local EventService = {}

-- (игрок, "rainbow" | "perun") — поймал Радужную или Чёрную молнию (для Зала Славы)
EventService.HallEntry = Signal.new() :: Signal.Signal<Player, string>
-- (вид события) — событие началось / закончилось
EventService.Started = Signal.new() :: Signal.Signal<Kind>
EventService.Ended = Signal.new() :: Signal.Signal<Kind>

local TICK = 0.25
local EV = Config.Events
local BALL = EV.BallLightning
local RAIN = EV.Rainbow
local PERUN = EV.Perun

-- Награды Шаровой молнии (вклад = доля поимок её колец)
local BALL_MINUTES = 2 -- минут дохода каждому участнику
local BALL_SHARE_MINUTES = 2 -- + столько × доля вклада
local BALL_SHARDS = 20
local BALL_CONSOLATION_MINUTES = 1 -- если улетела: утешительный приз участникам
local BALL_MIN_PATH = 50 -- концы пути шара не ближе этого
local BALL_PATH_TRIES = 24
local BALL_JITTER = 0.8 -- кольцо падает в пределах доли радиуса кольца от точки под шаром
local SUPERCELL_EXTRA_RINGS = 1
local RAINBOW_SPOT_TRIES = 12
local RAINBOW_SPOT_SPREAD = 0.35 -- доля игрового радиуса вокруг центра острова
local NAMES_IN_BANNER = 4

type Plan = { Period: number, Offset: number, Attr: string, Name: string }

local PLANS: { [Kind]: Plan } = {
	supercell = { Period = EV.Supercell.Period, Offset = EV.Supercell.Offset, Attr = "NextSupercell", Name = "⚡ Суперячейка" },
	ball = { Period = BALL.Period, Offset = BALL.Offset, Attr = "NextBall", Name = "🔮 Шаровая молния" },
	rainbow = { Period = RAIN.Period, Offset = RAIN.Offset, Attr = "NextRainbow", Name = "🌈 Радужная молния" },
}
-- при одинаковом времени: сначала самое редкое
local PRIORITY: { Kind } = { "rainbow", "ball", "supercell" }

local gameState: Instance? = nil
local notifyRemote: RemoteEvent? = nil
local bannerRemote: RemoteEvent? = nil
local effectRemote: RemoteEvent? = nil

local startTime = 0
local nextAt: { [Kind]: number } = {}
local warnedFor: { [Kind]: number } = {}
local current: Kind? = nil
local currentEnds = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

----------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------

local function setAttr(name: string, value: any)
	local gs = gameState
	if gs and gs:GetAttribute(name) ~= value then
		gs:SetAttribute(name, value)
	end
end

local function notify(player: Player, text: string, kind: string)
	local r = notifyRemote
	if r then
		r:FireClient(player, text, kind)
	end
end

local function notifyAll(text: string, kind: string)
	local r = notifyRemote
	if r then
		r:FireAllClients(text, kind)
	end
end

local function banner(text: string, kind: string, color: Color3?)
	local r = bannerRemote
	if r then
		r:FireAllClients(text, kind, color)
	end
end

local function effectTo(player: Player, msg: Net.EffectMsg)
	local r = effectRemote
	if r then
		r:FireClient(player, msg)
	end
end

local function effectAll(msg: Net.EffectMsg)
	local r = effectRemote
	if r then
		r:FireAllClients(msg)
	end
end

-- Остров, где сейчас больше всего игроков (при равенстве — меньший номер). nil — все в хабе.
local function busiestIsland(): (number?, number)
	local counts: { [number]: number } = {}
	for _, p in Players:GetPlayers() do
		local z = PlayerService.getZone(p)
		if z >= 1 and z <= #Config.Zones then
			counts[z] = (counts[z] or 0) + 1
		end
	end
	local best: number? = nil
	local bestCount = 0
	for z = 1, #Config.Zones do
		local c = counts[z] or 0
		if c > bestCount then
			best = z
			bestCount = c
		end
	end
	return best, bestCount
end

local function playersIn(zone: number): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if PlayerService.getZone(p) == zone then
			table.insert(list, p)
		end
	end
	return list
end

-- Случайная точка игровой зоны острова (на земле)
local function randomPlayPoint(zone: number, spread: number, margin: number): Vector3
	local g = Zones.Geo[zone]
	local r = Config.Zones[zone].PlayRadius * spread * math.sqrt(math.random())
	local a = math.random() * math.pi * 2
	return Zones.clampToPlay(zone, g.Center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), margin)
end

local function namesText(list: { string }): string
	local shown = {}
	for i = 1, math.min(#list, NAMES_IN_BANNER) do
		table.insert(shown, list[i])
	end
	local text = table.concat(shown, ", ")
	if #list > NAMES_IN_BANNER then
		text ..= string.format(" и ещё %d", #list - NAMES_IN_BANNER)
	end
	return text
end

----------------------------------------------------------------------
-- Модификаторы (для StrikeService)
----------------------------------------------------------------------

function EventService.current(): string
	return current or ""
end

function EventService.rateMult(): number
	return if current == "supercell" then Config.Multipliers.SupercellRate else 1
end

function EventService.chargeMult(): number
	return if current == "supercell" then Config.Multipliers.SupercellCharge else 1
end

function EventService.goldBoost(): number
	return if current == "supercell" then EV.Supercell.GoldBoost else 1
end

local function extraRings(): number
	return if current == "supercell" then SUPERCELL_EXTRA_RINGS else 0
end

----------------------------------------------------------------------
-- Расписание
----------------------------------------------------------------------

-- Первое плановое время события строго позже t (от старта сервера: старт + Offset + k × Period)
local function occurrenceAfter(kind: Kind, t: number): number
	local plan = PLANS[kind]
	local base = startTime + plan.Offset
	if t < base then
		return base
	end
	return base + (math.floor((t - base) / plan.Period) + 1) * plan.Period
end

-- Сколько длится событие (для прогноза; шаровую могут победить раньше)
local function durationOf(kind: Kind): number
	if kind == "supercell" then
		return EV.Supercell.Duration
	elseif kind == "ball" then
		return BALL.Duration
	end
	return RAIN.Announce + RAIN.Warning + Config.Catch.LatencyGrace
end

-- Когда начнётся каждое событие с учётом того, что они не накладываются
local function predict(t: number): { [Kind]: number }
	local order: { Kind } = table.clone(PRIORITY)
	table.sort(order, function(a: Kind, b: Kind): boolean
		if nextAt[a] ~= nextAt[b] then
			return nextAt[a] < nextAt[b]
		end
		return (table.find(PRIORITY, a) or 0) < (table.find(PRIORITY, b) or 0)
	end)
	local out: { [Kind]: number } = {}
	local cursor = if current then currentEnds else t
	for _, kind in order do
		local s = math.max(nextAt[kind], cursor)
		out[kind] = s
		cursor = s + durationOf(kind)
	end
	return out
end

----------------------------------------------------------------------
-- Суперячейка
----------------------------------------------------------------------

local function runSupercell(t0: number)
	local ends = t0 + EV.Supercell.Duration
	currentEnds = ends
	setAttr("EventEnds", ends)
	setAttr("Event", "supercell")
	banner("⚡ СУПЕРЯЧЕЙКА! Молнии чаще и дороже!", "event")
	while now() < ends do
		task.wait(TICK)
	end
	notifyAll("Суперячейка закончилась — до следующей!", "info")
end

----------------------------------------------------------------------
-- Шаровая молния
----------------------------------------------------------------------

local function ballPath(zone: number): (Vector3, Vector3)
	local margin = BALL.RingRadius
	for _ = 1, BALL_PATH_TRIES do
		local a = randomPlayPoint(zone, 1, margin)
		local b = randomPlayPoint(zone, 1, margin)
		if Zones.flatDist(a, b) >= BALL_MIN_PATH then
			return a, b
		end
	end
	-- запасной путь: через центр поперёк моста
	local g = Zones.Geo[zone]
	local half = BALL_MIN_PATH / 2
	return Zones.clampToPlay(zone, g.Center - g.Right * half, margin), Zones.clampToPlay(zone, g.Center + g.Right * half, margin)
end

local function runBall(t0: number): boolean
	local zone, count = busiestIsland()
	if not zone then
		return false -- все успели уйти в хаб
	end
	local from, to = ballPath(zone)
	local ends = t0 + BALL.Duration
	local maxHp = math.max(1, count) * BALL.HpPerPlayer
	local hp = maxHp
	local dead = false
	local contrib: { [Player]: number } = {}
	local total = 0

	currentEnds = ends
	setAttr("BallZone", zone)
	setAttr("BallFrom", from)
	setAttr("BallTo", to)
	setAttr("BallStart", t0)
	setAttr("BallEnd", ends)
	setAttr("BallMaxHp", maxHp)
	setAttr("BallHp", hp)
	setAttr("EventEnds", ends)
	setAttr("Event", "ball")
	banner(string.format("🔮 ШАРОВАЯ МОЛНИЯ над островом «%s»! Ловите её кольца вместе!", Config.Zones[zone].Name), "event", Config.Colors.gold.Color)

	local function posAt(t: number): Vector3
		local k = math.clamp((t - t0) / math.max(1e-3, ends - t0), 0, 1)
		return from:Lerp(to, k)
	end

	local function defeat()
		local pos = posAt(now())
		for _, p in playersIn(zone) do
			effectTo(p, { Kind = "ballBurst", Pos = pos, Zone = zone })
		end
		banner("🔮 Шаровая молния повержена!", "event", Config.Colors.gold.Color)
		for p, n in contrib do
			local d = DataService.get(p)
			if d and p.Parent == Players then
				local share = if total > 0 then n / total else 0
				local volts = EconomyService.grantVolts(p, Economy.incomeMinutes(d, BALL_MINUTES + BALL_SHARE_MINUTES * share), "ball")
				local shards = EconomyService.grantShards(p, BALL_SHARDS)
				notify(p, string.format("🔮 Шаровая молния повержена! +%s ⚡ +%s 💎", Format.short(volts), Format.short(shards)), "good")
			end
		end
	end

	local function onCatch(player: Player, _grade: StrikeService.CatchGrade)
		if dead then
			return
		end
		hp -= 1
		contrib[player] = (contrib[player] or 0) + 1
		total += 1
		setAttr("BallHp", math.max(0, hp))
		if hp <= 0 then
			dead = true
			defeat()
		end
	end

	while not dead and now() < ends do
		local t = now()
		-- кольцо, которое ударит уже после ухода шара, не роняем
		if t + BALL.Warning <= ends then
			-- кольцо падает туда, где шар будет в момент удара (с разбросом вокруг)
			local under = posAt(t + BALL.Warning)
			local a = math.random() * math.pi * 2
			local r = BALL.RingRadius * BALL_JITTER * math.sqrt(math.random())
			local spot = Zones.clampToPlay(zone, under + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), BALL.RingRadius)
			local opts: StrikeService.SharedOpts = {
				radius = BALL.RingRadius,
				warning = BALL.Warning,
				tag = "ball",
				onCatch = onCatch,
			}
			local ok, err = pcall(StrikeService.spawnShared, zone, spot, "gold", opts)
			if not ok then
				warn("[EventService] кольцо шаровой: " .. tostring(err))
			end
		end
		local nextRing = t + BALL.HitInterval
		while not dead and now() < nextRing and now() < ends do
			task.wait(0.1)
		end
	end

	if not dead then
		dead = true
		banner("🔮 Шаровая молния ушла...", "info")
		for p in contrib do
			local d = DataService.get(p)
			if d and p.Parent == Players then
				local volts = EconomyService.grantVolts(p, Economy.incomeMinutes(d, BALL_CONSOLATION_MINUTES), "ball")
				notify(p, string.format("Шаровая молния ушла… Утешительный приз: +%s ⚡", Format.short(volts)), "info")
			end
		end
	end
	setAttr("BallHp", 0)
	setAttr("BallZone", 0)
	setAttr("BallEnd", now())
	return true
end

----------------------------------------------------------------------
-- Радужная молния
----------------------------------------------------------------------

local function rainbowSpot(zone: number): Vector3
	local radius = RAIN.RingRadius
	for _ = 1, RAINBOW_SPOT_TRIES do
		local p = randomPlayPoint(zone, RAINBOW_SPOT_SPREAD, radius)
		if Zones.inPlayArea(zone, p, radius) then
			return p
		end
	end
	return Zones.clampToPlay(zone, Zones.Geo[zone].Center, radius)
end

local function runRainbow(t0: number)
	local zone = busiestIsland() or 1 -- все в хабе — на Грозовой Луг (он открыт у всех)
	local ends = t0 + durationOf("rainbow")
	currentEnds = ends
	setAttr("EventEnds", ends)
	setAttr("Event", "rainbow")
	effectAll({ Kind = "rainbowWarn", Zone = zone })
	banner(string.format("🌈 РАДУЖНАЯ МОЛНИЯ НАДВИГАЕТСЯ! Остров «%s»", Config.Zones[zone].Name), "rainbow")

	local spawnAt = t0 + RAIN.Announce
	while now() < spawnAt do
		task.wait(0.1)
	end

	local caught: { [Player]: boolean } = {}
	local names: { string } = {}
	local function onCatch(player: Player, grade: StrikeService.CatchGrade)
		if caught[player] then
			return
		end
		caught[player] = true
		table.insert(names, player.DisplayName)
		local d = DataService.get(player)
		if not d then
			return
		end
		local volts = EconomyService.grantVolts(player, Economy.incomeMinutes(d, RAIN.RewardMinutes), "rainbow")
		-- ИДЕАЛЬНО уже дал радужный фульгурит через dropHook (шанс 100%), ХОРОШО — даём здесь
		if grade ~= "perfect" then
			FulguriteService.grant(player, "rainbow", zone, "rainbow")
		end
		notify(player, string.format("🌈 Радужная молния твоя! +%s ⚡", Format.short(volts)), "rare")
		EventService.HallEntry:Fire(player, "rainbow")
	end

	local opts: StrikeService.SharedOpts = {
		radius = RAIN.RingRadius,
		warning = RAIN.Warning,
		tag = "rainbow",
		onCatch = onCatch,
	}
	local ok, err = pcall(StrikeService.spawnShared, zone, rainbowSpot(zone), "rainbow", opts)
	if not ok then
		warn("[EventService] радужное кольцо: " .. tostring(err))
	end
	-- итог — когда все нажатия уже оценены (удар + время на пинг)
	local resultAt = math.max(ends, now() + RAIN.Warning + Config.Catch.LatencyGrace)
	while now() < resultAt do
		task.wait(0.1)
	end
	if #names > 0 then
		banner("🌈 Радужную молнию поймали: " .. namesText(names) .. "!", "rainbow")
	else
		banner("🌈 Радужная молния ушла... В следующий раз!", "info")
	end
end

----------------------------------------------------------------------
-- Чёрная молния Перуна
----------------------------------------------------------------------

local function onPerun(player: Player, msg: Net.StrikeMsg)
	banner(string.format("☠ ЧЁРНАЯ МОЛНИЯ ПЕРУНА! Ловец: %s", player.DisplayName), "perun")
	effectAll({ Kind = "perun", Pos = msg.Pos, UserId = player.UserId, Zone = msg.Zone })
end

local function onPerunCaught(player: Player, zone: number, grade: string)
	banner(string.format("☠ Чёрная молния Перуна поймана! Ловец: %s", player.DisplayName), "perun")
	-- ИДЕАЛЬНО — Перунов фульгурит уже выпал через dropHook (шанс 100%), ХОРОШО — даём здесь
	if grade ~= "perfect" then
		FulguriteService.grant(player, "black", zone, "perun")
	end
	EventService.HallEntry:Fire(player, "perun")
	local root = PlayerService.getRoot(player)
	if not root then
		return
	end
	local center = root.Position
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local r = PlayerService.getRoot(other)
			local d = DataService.get(other)
			if r and d and (r.Position - center).Magnitude <= PERUN.WitnessRadius then
				local volts = EconomyService.grantVolts(other, Economy.incomeMinutes(d, PERUN.WitnessMinutes), "witness")
				effectTo(other, { Kind = "witness", Value = volts, UserId = player.UserId, Pos = center, Zone = zone })
				notify(other, string.format("☠ Я видел Чёрную молнию! +%s ⚡", Format.short(volts)), "rare")
			end
		end
	end
end

----------------------------------------------------------------------
-- Запуск событий
----------------------------------------------------------------------

local function finish(kind: Kind)
	current = nil
	currentEnds = 0
	setAttr("Event", "")
	setAttr("EventEnds", 0)
	EventService.Ended:Fire(kind)
end

local function startEvent(kind: Kind, t0: number)
	current = kind
	currentEnds = t0 + durationOf(kind)
	EventService.Started:Fire(kind)
	task.spawn(function()
		local ok, err = pcall(function()
			if kind == "supercell" then
				runSupercell(t0)
			elseif kind == "ball" then
				runBall(t0)
			else
				runRainbow(t0)
			end
		end)
		if not ok then
			warn("[EventService] " .. kind .. ": " .. tostring(err))
			setAttr("BallHp", 0)
			setAttr("BallZone", 0)
		end
		finish(kind)
	end)
end

local function tick()
	local t = now()
	if not current then
		local due: Kind? = nil
		for _, kind in PRIORITY do
			local d = due
			if nextAt[kind] <= t and (d == nil or nextAt[kind] < nextAt[d]) then
				due = kind
			end
		end
		if due then
			nextAt[due] = occurrenceAfter(due, t)
			if due == "ball" and busiestIsland() == nil then
				-- шару некуда лететь: пропускаем до следующего раза
				notifyAll("🔮 Шаровая молния не нашла ловцов — все в городе", "info")
			else
				startEvent(due, t)
			end
		end
	end
	-- прогноз и предупреждения
	local predicted = predict(t)
	for kind, plan in PLANS do
		local at = predicted[kind]
		setAttr(plan.Attr, math.floor(at * 10 + 0.5) / 10)
		local left = at - t
		if kind ~= current and left > 0 and left <= EV.WarnBefore and warnedFor[kind] ~= nextAt[kind] then
			warnedFor[kind] = nextAt[kind]
			notifyAll(string.format("%s через %d с!", plan.Name, math.ceil(left)), "info")
		end
	end
end

-- Запустить событие как можно скорее (Studio, отладка): встанет в очередь, если идёт другое
function EventService.trigger(kind: string)
	if kind == "supercell" or kind == "ball" or kind == "rainbow" then
		local k: Kind = kind
		nextAt[k] = now()
		warnedFor[k] = nextAt[k]
	end
end

function EventService.start()
	gameState = ReplicatedStorage:FindFirstChild("GameState") or Net.gameState()
	notifyRemote = Net.event("Notify")
	bannerRemote = Net.event("Banner")
	effectRemote = Net.event("Effect")

	startTime = now()
	for kind in PLANS do
		nextAt[kind] = occurrenceAfter(kind, startTime - 1)
	end
	setAttr("Event", "")
	setAttr("EventEnds", 0)

	StrikeService.setModifiers({
		rateMult = EventService.rateMult,
		chargeMult = EventService.chargeMult,
		goldBoost = EventService.goldBoost,
		extraRings = extraRings,
	})
	StrikeService.onPerun = onPerun
	StrikeService.CatchResolved:Connect(function(player, info)
		if info.color == "black" and (info.grade == "perfect" or info.grade == "good") then
			onPerunCaught(player, info.zone, info.grade)
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[EventService] расписание: " .. tostring(err))
			end
			task.wait(TICK)
		end
	end)
end

return EventService
