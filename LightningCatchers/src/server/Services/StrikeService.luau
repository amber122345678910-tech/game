--!strict
-- Сердце игры — удары молний.
--  * Личный поток колец для каждого игрока на острове 1..5 (не в хабе и не на мосту):
--    интервал Interval / (магнит × событие) ±разброс, лимит MaxActive + кольца магнита (+ событие),
--    место — рядом, в игровой зоне, с зазором от других колец и достижимое бегом.
--  * Общие удары событий (spawnShared): видят все на острове, поймать может каждый — по разу.
--  * Проверка Catch: удар есть и этот удар ещё не оценён, время нажатия правдоподобно,
--    игрок в кольце (+допуск), оценка Strikes.judge. Заряд, комбо, цепная молния, Молниедекс,
--    фульгурит (dropHook), «Шарахнуло».
--  * Удар без нажатия: игрок стоял в кольце — «Шарахнуло» (с острова 2) / подсказка;
--    был вне кольца — осколок на земле (ShardSpawn, сбор — ShardCollect).
--  * BoltFX — чужие молнии игрокам той же зоны (только для красоты).
-- Время везде серверное: workspace:GetServerTimeNow().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Net = require(Shared:WaitForChild("Net"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Prng = require(Shared:WaitForChild("Prng"))
local Signal = require(Shared:WaitForChild("Signal"))
local Strikes = require(Shared:WaitForChild("Strikes"))
local Zones = require(Shared:WaitForChild("Zones"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerService = require(script.Parent.PlayerService)

type Data = PlayerData.Data
type ColorId = Config.ColorId
type KindId = Config.KindId

export type CatchGrade = "perfect" | "good" | "miss"

-- Итог одного удара для одного игрока (сигнал CatchResolved)
export type CatchInfo = {
	grade: Net.Grade, -- "perfect" | "good" | "miss" | "zap" | "ground" (лопнувшая банка: оценка поимки + burst = true)
	color: ColorId,
	zone: number,
	combo: number, -- комбо после этого удара
	tag: string?, -- "perun" | теги событий
	shared: boolean,
	charge: number, -- сколько заряда попало в банку
	burst: boolean,
	strikeId: number,
	hit: number,
}

export type SharedOpts = {
	radius: number?, -- радиус кольца (по умолчанию Config.Catch.RingRadius)
	warning: number?, -- предупреждение (по умолчанию как у острова)
	tag: string?,
	onCatch: ((Player, CatchGrade) -> ())?, -- вызывается при ИДЕАЛЬНО/ХОРОШО
}

-- Модификаторы событий (EventService): функции без аргументов
export type Modifiers = {
	rateMult: (() -> number)?, -- частота колец ×
	chargeMult: (() -> number)?, -- заряд ×
	goldBoost: (() -> number)?, -- вес золотых ×
	extraRings: (() -> number)?, -- + колец одновременно
}

-- Фульгурит при ИДЕАЛЬНО: (игрок, цвет, остров, тег) -> Id нового фульгурита (или его запись), nil — не выпал
export type DropHook = (Player, ColorId, number, string?) -> (number | PlayerData.FulgRecord)?

type Ring = {
	Id: number,
	Owner: Player?, -- nil — общий удар
	Zone: number,
	Pos: Vector3, -- центр (у бегущего — начальная точка)
	To: Vector3?, -- бегущее кольцо: где оно будет в момент удара
	Radius: number,
	Color: ColorId,
	Kind: KindId,
	Tag: string?,
	Spawn: number,
	Hits: { number }, -- серверное время ударов (по возрастанию)
	Shared: boolean,
	Done: boolean, -- снято: все удары оценены или кольцо отменено
	Viewers: { [Player]: boolean }, -- кому отправлено общее кольцо
	Judged: { [Player]: { [number]: boolean } },
	Samples: { [number]: { [Player]: Vector3 } }, -- где стоял игрок в момент удара k
	OnCatch: ((Player, CatchGrade) -> ())?,
}

type Shard = { Id: number, Pos: Vector3, Amount: number, Expires: number }

-- Последняя удачная поимка игрока (для цепной молнии)
type ChainMark = { Time: number, Pos: Vector3, Charge: number, Zone: number, Linked: { [Player]: boolean } }

type PState = {
	Player: Player,
	Rings: { [number]: Ring }, -- свои активные кольца
	Count: number,
	NextSpawn: number, -- серверное время следующего кольца
	Combo: number,
	LastCatch: number, -- серверное время последней удачной поимки (таймаут комбо)
	FirstDone: boolean, -- первое кольцо новичка уже было в этой сессии
	CatchBucket: ServerLogic.Bucket,
	ShardBucket: ServerLogic.Bucket,
	Shards: { [number]: Shard },
	ShardCount: number,
	Chain: ChainMark?,
}

local StrikeService = {}

-- (игрок, CatchInfo) — каждый оценённый удар (личный или общий)
StrikeService.CatchResolved = Signal.new() :: Signal.Signal<Player, CatchInfo>
-- (игрок, осколков) — подобрал осколок с земли
StrikeService.ShardCollected = Signal.new() :: Signal.Signal<Player, number>

local StrikeSpawn = Net.event("StrikeSpawn")
local StrikeResult = Net.event("StrikeResult")
local CatchRemote = Net.event("Catch")
local ShardSpawn = Net.event("ShardSpawn")
local ShardCollect = Net.event("ShardCollect")
local NotifyRemote = Net.event("Notify")
local BannerRemote = Net.event("Banner")
local EffectRemote = Net.event("Effect")
local BoltFX = Net.unreliable("BoltFX")

local function defaultOnPerun(player: Player, _msg: Net.StrikeMsg)
	BannerRemote:FireAllClients(string.format("☠ Чёрная молния Перуна бьёт рядом с %s!", player.DisplayName), "rare", Config.Colors.gold.Color)
end

-- Ставит FulguriteService
StrikeService.dropHook = nil :: DropHook?
-- Появилась Чёрная молния Перуна (EventService может заменить). По умолчанию — баннер всем.
StrikeService.onPerun = defaultOnPerun :: (Player, Net.StrikeMsg) -> ()

local pstates: { [Player]: PState } = {}
local sharedRings: { [number]: Ring } = {}
local lastStrikeId = 0
local lastShardId = 0
local groundParams: RaycastParams? = nil
local modifiers: Modifiers = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

----------------------------------------------------------------------
-- Модификаторы событий
----------------------------------------------------------------------

local function modValue(fn: (() -> number)?, default: number, min: number): number
	if not fn then
		return default
	end
	local ok, v = pcall(fn)
	if ok and ServerLogic.isFinite(v) then
		return math.max(min, v)
	end
	return default
end

local function rateMult(): number
	return modValue(modifiers.rateMult, 1, 0.05)
end

local function chargeMult(): number
	return modValue(modifiers.chargeMult, 1, 0)
end

local function goldBoost(): number
	return modValue(modifiers.goldBoost, 1, 0)
end

local function extraRings(): number
	return math.floor(modValue(modifiers.extraRings, 0, 0))
end

-- Заменить модификаторы (отсутствующие — по умолчанию 1/1/1/0)
function StrikeService.setModifiers(m: Modifiers)
	modifiers = {
		rateMult = m.rateMult,
		chargeMult = m.chargeMult,
		goldBoost = m.goldBoost,
		extraRings = m.extraRings,
	}
end

----------------------------------------------------------------------
-- Геометрия колец
----------------------------------------------------------------------

-- Земля под точкой: высота поверхности острова, уточнённая лучом по карте.
-- nil — там уступ, камень или крутой склон (кольцо туда не ставим).
local function groundAt(zone: number, pos: Vector3): Vector3?
	local surface = Config.Zones[zone].GroundY
	local params = groundParams
	if not params then
		return Vector3.new(pos.X, surface, pos.Z)
	end
	local probe = Config.Server.GroundProbe
	local hit = Workspace:Raycast(Vector3.new(pos.X, surface + probe, pos.Z), Vector3.new(0, -2 * probe, 0), params)
	if not hit then
		return Vector3.new(pos.X, surface, pos.Z)
	end
	if math.abs(hit.Position.Y - surface) > Config.Server.GroundStep or hit.Normal.Y < Config.Server.GroundMinNormalY then
		return nil
	end
	return Vector3.new(pos.X, hit.Position.Y, pos.Z)
end

-- Центр кольца в момент t (бегущее ползёт от Pos к To до первого удара)
local function ringPosAt(ring: Ring, t: number): Vector3
	local to = ring.To
	if to then
		return Strikes.runnerPosition(ring.Pos, to, ServerLogic.runnerShare(ring.Spawn, ring.Hits[1], t))
	end
	return ring.Pos
end

local function farFromRings(rings: { [number]: Ring }, zone: number, pos: Vector3, radius: number): boolean
	for _, ring in rings do
		if not ring.Done and ring.Zone == zone then
			local need = radius + ring.Radius + Config.Catch.MinRingGap
			if ServerLogic.flatDist(pos, ring.Pos) < need then
				return false
			end
			local to = ring.To
			if to and ServerLogic.flatDist(pos, to) < need then
				return false
			end
		end
	end
	return true
end

local function spotFree(ps: PState, zone: number, pos: Vector3, radius: number): boolean
	return farFromRings(ps.Rings, zone, pos, radius) and farFromRings(sharedRings, zone, pos, radius)
end

-- Случайное место рядом с игроком: в игровой зоне, не впритык к другим кольцам, успеть добежать
local function findSpot(ps: PState, zone: number, around: Vector3, radius: number, speed: number, warning: number): Vector3?
	local c = Config.Catch
	local reach = speed * warning * Config.Server.ReachShare
	-- дальше, чем можно добежать, не ищем: плотность кандидатов линейна по расстоянию,
	-- так что это то же распределение, что и отбрасывание недостижимых, только без пустых попыток
	local maxD = math.max(c.MinSpawnDistance, math.min(c.MaxSpawnDistance, reach))
	for _ = 1, Config.Server.SpawnTries do
		local p = Zones.candidate(zone, around, c.MinSpawnDistance, maxD, math.random(), math.random())
		if ServerLogic.flatDist(around, p) <= reach and Zones.inPlayArea(zone, p, radius) and spotFree(ps, zone, p, radius) then
			local ground = groundAt(zone, p)
			if ground then
				return ground
			end
		end
	end
	return nil
end

-- Первое кольцо новичка: прямо перед ним (мягче обычной проверки — можно ближе к подстанции,
-- точка появления рядом с ней)
local function placeAhead(ps: PState, zone: number, root: BasePart, radius: number): Vector3?
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	-- у края острова кольцо чуть сдвигается внутрь игровой зоны
	local spot = Zones.clampToPlay(zone, root.Position + flat.Unit * Config.Server.FirstStrikeAhead, radius)
	if ServerLogic.flatDist(spot, root.Position) > Config.Server.FirstStrikeAhead + radius then
		return nil -- игрок далеко от игровой зоны: обычный поиск места
	end
	local g = Zones.Geo[zone]
	if ServerLogic.flatDist(spot, g.SellPad) < Zones.SellPadRadius + radius + Config.Catch.MinRingGap then
		return nil
	end
	if not spotFree(ps, zone, spot, radius) then
		return nil
	end
	return groundAt(zone, spot)
end

-- Куда приползёт бегущее кольцо: не дальше RunnerSpeed × предупреждение, в игровой зоне, достижимо
local function runnerTarget(ps: PState, zone: number, around: Vector3, from: Vector3, radius: number, speed: number, warning: number): Vector3?
	local maxPath = Config.Catch.RunnerSpeed * warning
	local reach = speed * warning * Config.Server.ReachShare
	local minShare = Config.Server.RunnerMinShare
	for _ = 1, Config.Server.SpawnTries do
		local angle = math.random() * math.pi * 2
		local dist = maxPath * (minShare + (1 - minShare) * math.random())
		local raw = from + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local to = Zones.clampToPlay(zone, raw, radius)
		if
			ServerLogic.flatDist(from, to) <= maxPath + 1e-3
			and ServerLogic.flatDist(around, to) <= reach
			and Zones.inPlayArea(zone, to, radius)
			and spotFree(ps, zone, to, radius)
		then
			local ground = groundAt(zone, to)
			if ground then
				return ground
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Кольца
----------------------------------------------------------------------

local function newRing(
	owner: Player?,
	zone: number,
	pos: Vector3,
	to: Vector3?,
	radius: number,
	color: ColorId,
	kind: KindId,
	tag: string?,
	spawn: number,
	hits: { number }
): Ring
	lastStrikeId += 1
	return {
		Id = lastStrikeId,
		Owner = owner,
		Zone = zone,
		Pos = pos,
		To = to,
		Radius = radius,
		Color = color,
		Kind = kind,
		Tag = tag,
		Spawn = spawn,
		Hits = hits,
		Shared = owner == nil,
		Done = false,
		Viewers = {},
		Judged = {},
		Samples = {},
		OnCatch = nil,
	}
end

local function toMsg(ring: Ring, shown: ColorId?, upgradeAt: number?): Net.StrikeMsg
	return {
		Id = ring.Id,
		Pos = ring.Pos,
		To = ring.To,
		Radius = ring.Radius,
		Color = ring.Color,
		Shown = shown,
		UpgradeAt = upgradeAt,
		Kind = ring.Kind,
		Spawn = ring.Spawn,
		Hits = table.clone(ring.Hits),
		Shared = if ring.Shared then true else nil,
		Tag = ring.Tag,
		Zone = ring.Zone,
	}
end

local function isJudged(ring: Ring, player: Player, k: number): boolean
	local j = ring.Judged[player]
	return j ~= nil and j[k] == true
end

-- Отметить удар k оценённым. true — все удары кольца для этого игрока оценены.
local function markJudged(ring: Ring, player: Player, k: number): boolean
	local j = ring.Judged[player]
	if not j then
		j = {}
		ring.Judged[player] = j
	end
	j[k] = true
	for i = 1, #ring.Hits do
		if not j[i] then
			return false
		end
	end
	return true
end

-- Снять личное кольцо
local function dropRing(ps: PState, ring: Ring)
	ring.Done = true
	if ps.Rings[ring.Id] == ring then
		ps.Rings[ring.Id] = nil
		ps.Count -= 1
	end
end

-- Кто сейчас "участвует" в кольце: владелец или зрители общего кольца, всё ещё на этом острове
local function participants(ring: Ring): { Player }
	local list = {}
	local owner = ring.Owner
	if owner then
		if pstates[owner] then
			table.insert(list, owner)
		end
	else
		for player in ring.Viewers do
			if pstates[player] and PlayerService.getZone(player) == ring.Zone then
				table.insert(list, player)
			end
		end
	end
	return list
end

----------------------------------------------------------------------
-- Результаты
----------------------------------------------------------------------

local function setCombo(ps: PState, combo: number)
	if ps.Combo == combo then
		return
	end
	ps.Combo = combo
	ps.Player:SetAttribute(Net.PlayerAttrs.Combo, combo)
end

local function resultMsg(ring: Ring, k: number, player: Player, ps: PState, grade: Net.Grade, center: Vector3, final: boolean): Net.StrikeResultMsg
	return {
		Id = ring.Id,
		Hit = k,
		Grade = grade,
		Charge = 0,
		Combo = ps.Combo,
		Jar = EconomyService.charge(player),
		Capacity = EconomyService.capacity(player),
		Color = ring.Color,
		Pos = center,
		Final = final,
	}
end

local function info(ring: Ring, k: number, ps: PState, grade: Net.Grade, charge: number, burst: boolean): CatchInfo
	return {
		grade = grade,
		color = ring.Color,
		zone = ring.Zone,
		combo = ps.Combo,
		tag = ring.Tag,
		shared = ring.Shared,
		charge = charge,
		burst = burst,
		strikeId = ring.Id,
		hit = k,
	}
end

-- Чужая молния — остальным на этом острове (ненадёжно, только для красоты)
local function sendBolt(ring: Ring, k: number, owner: Player, center: Vector3, caught: boolean)
	local msg: Net.BoltMsg = {
		Pos = center,
		Color = ring.Color,
		Seed = Prng.hash(ring.Id, k),
		Zone = ring.Zone,
		Caught = caught,
		UserId = owner.UserId,
	}
	for _, other in Players:GetPlayers() do
		if other ~= owner and PlayerService.getZone(other) == ring.Zone then
			BoltFX:FireClient(other, msg)
		end
	end
end

local function spawnShard(ps: PState, d: Data, ring: Ring, center: Vector3)
	if ps.ShardCount >= Config.Server.MaxShards then
		return
	end
	local raw = Config.Zones[ring.Zone].ShardValue * (1 + Economy.petBonuses(d).shards)
	local amount = ServerLogic.stochasticRound(raw, math.random())
	if amount <= 0 then
		return
	end
	local pos = center
	if #ring.Hits > 1 then
		-- у двойного/вилки осколки не ложатся друг на друга
		local a = math.random() * math.pi * 2
		local r = Config.Server.ShardScatter * math.random()
		pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end
	lastShardId += 1
	local shard: Shard = { Id = lastShardId, Pos = pos, Amount = amount, Expires = now() + Config.Catch.ShardLifetime }
	ps.Shards[shard.Id] = shard
	ps.ShardCount += 1
	local msg: Net.ShardMsg = { Id = shard.Id, Pos = shard.Pos, Amount = shard.Amount, Expires = shard.Expires }
	ShardSpawn:FireClient(ps.Player, msg)
end

-- Кто поймал свой удар рядом и почти одновременно — цепная молния
local function chainPartners(ps: PState, zone: number, hitTime: number, pos: Vector3): { PState }
	local list = {}
	local c = Config.Catch
	for other, qs in pstates do
		local mark = qs.Chain
		if
			qs ~= ps
			and mark
			and mark.Zone == zone
			and not mark.Linked[ps.Player]
			and math.abs(mark.Time - hitTime) <= c.ChainWindow
			and ServerLogic.flatDist(mark.Pos, pos) <= c.ChainDistance
			and PlayerService.getZone(other) == zone
		then
			table.insert(list, qs)
		end
	end
	return list
end

-- Удачная поимка: заряд, комбо, цепь, статистика, Молниедекс, фульгурит
local function applyCatch(player: Player, ps: PState, d: Data, ring: Ring, k: number, grade: "perfect" | "good", center: Vector3, msg: Net.StrikeResultMsg): CatchInfo
	local zone = ring.Zone
	local t = now()
	local hitTime = ring.Hits[k]

	local combo = if t - ps.LastCatch > Config.Catch.ComboTimeout then 0 else ps.Combo
	combo = ServerLogic.nextCombo(combo, grade)
	setCombo(ps, combo)
	ps.LastCatch = t

	local charge = Economy.catchCharge(zone, ring.Color, grade, combo, d.Upgrades.Rod, chargeMult())
	local partners = chainPartners(ps, zone, hitTime, center)
	local bonus = if #partners > 0 then charge * Config.Catch.ChainBonus else 0
	local added, burst, lost = EconomyService.addCharge(player, charge + bonus, zone)

	local mark: ChainMark = { Time = hitTime, Pos = center, Charge = charge, Zone = zone, Linked = {} }
	ps.Chain = mark
	if #partners > 0 then
		local ids = {}
		for _, qs in partners do
			local q = qs.Player
			local qmark = qs.Chain
			if qmark then
				qmark.Linked[player] = true
				EconomyService.addCharge(q, qmark.Charge * Config.Catch.ChainBonus, zone, true)
			end
			mark.Linked[q] = true
			table.insert(ids, q.UserId)
			local pair: Net.EffectMsg = { Kind = "chain", Targets = { player.UserId, q.UserId }, Pos = center, Zone = zone }
			EffectRemote:FireClient(q, pair)
		end
		local all = { player.UserId }
		for _, id in ids do
			table.insert(all, id)
		end
		local mine: Net.EffectMsg = { Kind = "chain", Targets = all, Pos = center, Zone = zone }
		EffectRemote:FireClient(player, mine)
		msg.Chain = ids
	end

	-- статистика и Молниедекс
	local color = ring.Color
	local bestBefore = d.Stats.BestCombo
	local key = zone .. ":" .. color
	local isNew = d.Index[key] ~= true
	DataService.update(player, function(data)
		local s = data.Stats
		s.Catches += 1
		if grade == "perfect" then
			s.Perfects += 1
		end
		if combo > s.BestCombo then
			s.BestCombo = combo
		end
		if color == "gold" then
			s.Golds += 1
		elseif color == "rainbow" then
			s.Rainbows += 1
		elseif color == "black" then
			s.Blacks += 1
		end
		data.Index[key] = true
	end)
	if combo > bestBefore then
		player:SetAttribute(Net.PlayerAttrs.BestCombo, combo)
	end
	if isNew then
		msg.NewIndex = key
		NotifyRemote:FireClient(player, string.format("Молниедекс: %s — %s!", Config.Colors[color].Name, Config.Zones[zone].Name), "rare")
	end

	-- фульгурит
	local hook = StrikeService.dropHook
	if grade == "perfect" and hook then
		local ok, result = pcall(hook, player, color, zone, ring.Tag)
		if not ok then
			warn("[StrikeService] dropHook: " .. tostring(result))
		elseif typeof(result) == "number" then
			msg.Fulg = result
		elseif typeof(result) == "table" then
			msg.Fulg = result.Id
		end
	end

	msg.Grade = if burst then "burst" else grade
	msg.Charge = added
	msg.Lost = if lost > 0 then lost else nil
	return info(ring, k, ps, grade, added, burst)
end

-- Игрок нажал и удар оценён (grade уже посчитан). outside — нажал, стоя вне кольца.
local function judgeTap(player: Player, ps: PState, d: Data, ring: Ring, k: number, grade: CatchGrade, center: Vector3, outside: boolean)
	local final = markJudged(ring, player, k)
	local msg = resultMsg(ring, k, player, ps, grade, center, final)
	local caught = grade == "perfect" or grade == "good"
	local result: CatchInfo
	if grade == "perfect" or grade == "good" then
		result = applyCatch(player, ps, d, ring, k, grade, center, msg)
	else
		setCombo(ps, 0)
		-- током бьёт, только если молния попала в игрока (он в кольце, но не попал в окно)
		if not outside and Config.Zones[ring.Zone].Penalties then
			PlayerService.zap(player, Economy.zapStun(d.Upgrades.Insulation))
		end
		result = info(ring, k, ps, grade, 0, false)
	end
	msg.Combo = ps.Combo
	msg.Jar = EconomyService.charge(player)
	msg.Capacity = EconomyService.capacity(player)
	StrikeResult:FireClient(player, msg)
	if not ring.Shared or caught then
		sendBolt(ring, k, player, center, caught)
	end
	if final and not ring.Shared then
		dropRing(ps, ring)
	end
	StrikeService.CatchResolved:Fire(player, result)
	local onCatch = ring.OnCatch
	if onCatch and (grade == "perfect" or grade == "good") then
		local ok, err = pcall(onCatch, player, grade)
		if not ok then
			warn("[StrikeService] onCatch: " .. tostring(err))
		end
	end
end

-- Удар прошёл, а нажатия не было
local function resolveMissed(player: Player, ring: Ring, k: number, center: Vector3, sample: Vector3?)
	local ps = pstates[player]
	local d = DataService.get(player)
	if not ps or not d or isJudged(ring, player, k) then
		return
	end
	local inside = sample ~= nil and ServerLogic.inRing(sample, center, ring.Radius, Config.Server.CatchHeight)
	local grade: Net.Grade
	if inside then
		-- молния попала в игрока, который не нажал
		setCombo(ps, 0)
		if Config.Zones[ring.Zone].Penalties then
			grade = "zap"
			PlayerService.zap(player, Economy.zapStun(d.Upgrades.Insulation))
		else
			grade = "miss" -- на первом острове — только подсказка у клиента
		end
	else
		grade = "ground"
		if not ring.Shared then
			spawnShard(ps, d, ring, center)
		end
	end
	local final = markJudged(ring, player, k)
	StrikeResult:FireClient(player, resultMsg(ring, k, player, ps, grade, center, final))
	if not ring.Shared then
		sendBolt(ring, k, player, center, false)
	end
	if final and not ring.Shared then
		dropRing(ps, ring)
	end
	StrikeService.CatchResolved:Fire(player, info(ring, k, ps, grade, 0, false))
end

----------------------------------------------------------------------
-- Расписание ударов
----------------------------------------------------------------------

-- Запомнить, где стоят участники в момент удара k
local function sampleHit(ring: Ring, k: number)
	if ring.Done then
		return
	end
	local samples: { [Player]: Vector3 } = {}
	for _, player in participants(ring) do
		local root = PlayerService.getRoot(player)
		if root then
			samples[player] = root.Position
		end
	end
	ring.Samples[k] = samples
end

-- Через LatencyGrace после удара: всё, что не оценено нажатием, решается по позиции
local function resolveHit(ring: Ring, k: number)
	if ring.Done then
		return
	end
	local center = ringPosAt(ring, ring.Hits[k])
	local samples = ring.Samples[k]
	for _, player in participants(ring) do
		if not isJudged(ring, player, k) then
			local ok, err = pcall(resolveMissed, player, ring, k, center, if samples then samples[player] else nil)
			if not ok then
				warn("[StrikeService] удар без нажатия: " .. tostring(err))
			end
		end
	end
	if k == #ring.Hits then
		-- последний удар: кольцо снимается в любом случае (на случай ушедшего игрока)
		if ring.Shared then
			ring.Done = true
			sharedRings[ring.Id] = nil
		else
			local owner = ring.Owner
			local ps = if owner then pstates[owner] else nil
			if ps then
				dropRing(ps, ring)
			else
				ring.Done = true
			end
		end
	end
end

local function scheduleHits(ring: Ring)
	local t = now()
	for k, hitTime in ring.Hits do
		task.delay(math.max(0, hitTime - t), sampleHit, ring, k)
		task.delay(math.max(0, hitTime + Config.Catch.LatencyGrace - t), resolveHit, ring, k)
	end
end

----------------------------------------------------------------------
-- Личный поток
----------------------------------------------------------------------

local function isNewbie(d: Data): boolean
	return d.Tutorial.catch ~= true
end

-- Пауза перед первым кольцом (появление, вход на остров)
local function entryDelay(ps: PState): number
	local d = DataService.get(ps.Player)
	if d and not ps.FirstDone and isNewbie(d) then
		return Config.Catch.FirstStrikeDelay
	end
	return Config.Server.ZoneEnterDelay
end

local function nextInterval(zone: number, d: Data): number
	local base = Config.Zones[zone].Interval / math.max(0.05, Economy.rateMult(d.Upgrades.Magnet) * rateMult())
	return ServerLogic.jitter(base, Config.Server.SpawnJitter, math.random())
end

local function spawnPersonal(ps: PState, d: Data, zone: number, root: BasePart, t: number): boolean
	local player = ps.Player
	local zdef = Config.Zones[zone]
	local bonuses = Economy.petBonuses(d)
	local speed = Economy.walkSpeed(d.Upgrades.Boots)
	local radius = Config.Catch.RingRadius
	local first = not ps.FirstDone and isNewbie(d)
	local warning = if first then Config.Catch.FirstStrikeWarning else zdef.Warning

	-- цвет и тип
	local color: ColorId
	local shown: ColorId? = nil
	local upgradeAt: number? = nil
	local tag: string? = nil
	local kind: KindId = "single"
	local perun = Config.Events.Perun
	if not first and zone == perun.Zone and math.random() < perun.Chance * (1 + bonuses.luck) then
		color = "black"
		tag = "perun"
		warning = perun.Warning
	else
		color = Strikes.rollColor(zone, bonuses.luck, math.random(), goldBoost())
		if not first then
			kind = Strikes.rollKind(zone, math.random())
			if color ~= "gold" and math.random() < Config.Catch.ShimmerChance then
				local better = Strikes.upgradedColor(color)
				if better ~= color then
					shown = color
					color = better
					upgradeAt = Config.Server.ShimmerAt
				end
			end
		end
	end

	-- место
	local pos = if first then placeAhead(ps, zone, root, radius) else nil
	if not pos then
		pos = findSpot(ps, zone, root.Position, radius, speed, warning)
	end
	if not pos then
		return false
	end
	local to: Vector3? = nil
	if kind == "runner" then
		to = runnerTarget(ps, zone, root.Position, pos, radius, speed, warning)
		if not to then
			kind = "single" -- некуда ползти — обычный удар
		end
	end

	local hits = {}
	for _, offset in Strikes.hitOffsets(kind) do
		table.insert(hits, t + warning + offset)
	end
	local ring = newRing(player, zone, pos, to, radius, color, kind, tag, t, hits)
	ps.Rings[ring.Id] = ring
	ps.Count += 1
	if first then
		ps.FirstDone = true
	end
	local msg = toMsg(ring, shown, upgradeAt)
	StrikeSpawn:FireClient(player, msg)
	scheduleHits(ring)
	if tag == "perun" then
		local hook = StrikeService.onPerun
		task.spawn(function()
			local ok, err = pcall(hook, player, msg)
			if not ok then
				warn("[StrikeService] onPerun: " .. tostring(err))
			end
		end)
	end
	return true
end

local function trySpawn(ps: PState, t: number)
	if t < ps.NextSpawn then
		return
	end
	local player = ps.Player
	local zone = PlayerService.getZone(player)
	if zone < 1 or zone > #Config.Zones or PlayerService.getArea(player) ~= zone then
		return -- хаб, мост или пустота
	end
	local root = PlayerService.getRoot(player)
	local d = DataService.get(player)
	if not root or not d or zone > d.Zone then
		return
	end
	local limit = Config.Zones[zone].MaxActive + Economy.extraRings(d.Upgrades.Magnet) + extraRings()
	if ps.Count >= limit then
		return -- место освободится — кольцо появится сразу
	end
	if spawnPersonal(ps, d, zone, root, t) then
		ps.NextSpawn = t + nextInterval(zone, d)
	else
		ps.NextSpawn = t + Config.Server.SpawnRetry
	end
end

local function tickPlayer(ps: PState, t: number)
	if ps.Combo > 0 and t - ps.LastCatch > Config.Catch.ComboTimeout then
		setCombo(ps, 0)
	end
	if ps.ShardCount > 0 then
		for id, shard in ps.Shards do
			if t > shard.Expires then
				ps.Shards[id] = nil
				ps.ShardCount -= 1
			end
		end
	end
	trySpawn(ps, t)
end

----------------------------------------------------------------------
-- Нажатия
----------------------------------------------------------------------

local function onCatch(player: Player, strikeId: any, hit: any, tapTime: any)
	local ps = pstates[player]
	if not ps then
		return
	end
	local rate = Config.Catch.MaxCatchRequestsPerSecond
	if not ServerLogic.take(ps.CatchBucket, rate, rate, now()) then
		return
	end
	if not ServerLogic.isInteger(strikeId) or not ServerLogic.isInteger(hit) or not ServerLogic.isFinite(tapTime) then
		return
	end
	local ring = ps.Rings[strikeId] or sharedRings[strikeId]
	if not ring or ring.Done then
		return
	end
	if ring.Shared and PlayerService.getZone(player) ~= ring.Zone then
		return
	end
	local k: number = hit
	if k < 1 or k > #ring.Hits or isJudged(ring, player, k) then
		return
	end
	local t = now()
	if not ServerLogic.tapPlausible(tapTime, t, ring.Spawn, Config.Catch.MaxTapAge, Config.Catch.MaxCalibration) then
		return
	end
	local d = DataService.get(player)
	local root = PlayerService.getRoot(player)
	if not d or not root then
		return
	end

	local hitTime = ring.Hits[k]
	local center = ringPosAt(ring, hitTime)
	-- допуск: радиус + пинг/рывок + сколько успел пробежать за время в пути пакета
	local reach = ring.Radius + Config.Catch.PositionTolerance + Economy.walkSpeed(d.Upgrades.Boots) * Config.Server.MoveSlack
	local height = Config.Server.CatchHeight
	local samples = ring.Samples[k]
	local sample = if samples then samples[player] else nil
	local inside = ServerLogic.inRing(root.Position, center, reach, height) or (sample ~= nil and ServerLogic.inRing(sample, center, reach, height))

	local grade: CatchGrade = "miss"
	if inside then
		local perfect, good = Strikes.windows(d.Upgrades.Rod, Economy.petBonuses(d).window)
		grade = Strikes.judge(tapTime - hitTime, perfect, good)
	end
	judgeTap(player, ps, d, ring, k, grade, center, not inside)
end

local function onShardCollect(player: Player, shardId: any)
	local ps = pstates[player]
	if not ps then
		return
	end
	local rate = Config.Server.ShardCollectRate
	if not ServerLogic.take(ps.ShardBucket, rate, rate, now()) or not ServerLogic.isInteger(shardId) then
		return
	end
	local shard = ps.Shards[shardId]
	if not shard then
		return
	end
	if now() > shard.Expires then
		ps.Shards[shardId] = nil
		ps.ShardCount -= 1
		return
	end
	local root = PlayerService.getRoot(player)
	local reach = Config.Catch.ShardPickupRadius + Config.Server.ShardPickupSlack
	if not root or not ServerLogic.inRing(root.Position, shard.Pos, reach, Config.Server.CatchHeight) then
		return
	end
	ps.Shards[shardId] = nil
	ps.ShardCount -= 1
	local granted = EconomyService.grantShards(player, shard.Amount)
	if granted > 0 then
		StrikeService.ShardCollected:Fire(player, granted)
	end
end

----------------------------------------------------------------------
-- Общие удары (события)
----------------------------------------------------------------------

-- Общее кольцо на острове zone: его получают все, кто сейчас на острове; поймать может каждый (по разу).
-- Возвращает Id удара.
function StrikeService.spawnShared(zone: number, pos: Vector3, color: ColorId, opts: SharedOpts?): number
	assert(ServerLogic.isInteger(zone) and zone >= 1 and zone <= #Config.Zones, "StrikeService.spawnShared: неверный остров")
	local o: SharedOpts = opts or {}
	local t = now()
	local warning = o.warning or Config.Zones[zone].Warning
	local radius = o.radius or Config.Catch.RingRadius
	local center = groundAt(zone, pos) or Vector3.new(pos.X, Config.Zones[zone].GroundY, pos.Z)
	local ring = newRing(nil, zone, center, nil, radius, color, "single", o.tag, t, { t + warning })
	ring.OnCatch = o.onCatch
	sharedRings[ring.Id] = ring
	local msg = toMsg(ring, nil, nil)
	for player in pstates do
		if PlayerService.getZone(player) == zone then
			ring.Viewers[player] = true
			StrikeSpawn:FireClient(player, msg)
		end
	end
	scheduleHits(ring)
	return ring.Id
end

----------------------------------------------------------------------
-- Состояние игроков
----------------------------------------------------------------------

local function ensureState(player: Player): PState?
	local ps = pstates[player]
	if ps then
		return ps
	end
	if player.Parent ~= Players or not DataService.get(player) then
		return nil
	end
	local clock = now()
	local rate = Config.Catch.MaxCatchRequestsPerSecond
	local fresh: PState = {
		Player = player,
		Rings = {},
		Count = 0,
		NextSpawn = math.huge, -- поток начнётся, когда персонаж появится
		Combo = 0,
		LastCatch = 0,
		FirstDone = false,
		CatchBucket = ServerLogic.newBucket(rate, clock),
		ShardBucket = ServerLogic.newBucket(Config.Server.ShardCollectRate, clock),
		Shards = {},
		ShardCount = 0,
	}
	pstates[player] = fresh
	ps = fresh
	player:SetAttribute(Net.PlayerAttrs.Combo, 0)
	if PlayerService.getRoot(player) then
		ps.NextSpawn = now() + entryDelay(ps)
	end
	return ps
end

-- Снять все кольца игрока молча (клиент сам убирает кольца при смене зоны/смерти)
local function cancelRings(ps: PState)
	for _, ring in ps.Rings do
		ring.Done = true
	end
	table.clear(ps.Rings)
	ps.Count = 0
	for _, ring in sharedRings do
		ring.Viewers[ps.Player] = nil
	end
	ps.Chain = nil
end

local function clearShards(ps: PState)
	table.clear(ps.Shards)
	ps.ShardCount = 0
end

function StrikeService.start()
	local map = Workspace:FindFirstChild("Map")
	if map then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { map }
		params.IgnoreWater = true
		groundParams = params
	end

	CatchRemote.OnServerEvent:Connect(function(player: Player, strikeId: any, hit: any, tapTime: any)
		local ok, err = pcall(onCatch, player, strikeId, hit, tapTime)
		if not ok then
			warn("[StrikeService] Catch от " .. player.Name .. ": " .. tostring(err))
		end
	end)
	ShardCollect.OnServerEvent:Connect(function(player: Player, shardId: any)
		local ok, err = pcall(onShardCollect, player, shardId)
		if not ok then
			warn("[StrikeService] ShardCollect от " .. player.Name .. ": " .. tostring(err))
		end
	end)

	DataService.Loaded:Connect(function(player)
		ensureState(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		ensureState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local ps = pstates[player]
		if ps then
			cancelRings(ps)
			clearShards(ps)
		end
		pstates[player] = nil
	end)
	PlayerService.ZoneChanged:Connect(function(player)
		local ps = ensureState(player)
		if ps then
			cancelRings(ps)
			clearShards(ps)
			ps.NextSpawn = now() + entryDelay(ps)
		end
	end)
	PlayerService.Died:Connect(function(player)
		local ps = pstates[player]
		if ps then
			cancelRings(ps)
			setCombo(ps, 0)
			ps.NextSpawn = math.huge
		end
	end)
	PlayerService.Spawned:Connect(function(player)
		local ps = ensureState(player)
		if ps then
			cancelRings(ps)
			ps.NextSpawn = now() + entryDelay(ps)
		end
	end)
	for _, player in Players:GetPlayers() do
		ensureState(player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Server.StrikeTick)
			local t = now()
			for player, ps in pstates do
				local ok, err = pcall(tickPlayer, ps, t)
				if not ok then
					warn("[StrikeService] поток " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return StrikeService
