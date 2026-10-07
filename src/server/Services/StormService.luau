--!strict
-- Шторм на участке игрока: Подготовка -> Град -> Затишье -> Кислотный дождь -> Шторм уходит.
-- Сервер считает весь урон по данным сетки (без физики), клиент только рисует эффекты.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StormSim = require(Shared:WaitForChild("StormSim"))

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

type Plot = PlotService.Plot
type BlockRecord = PlotService.BlockRecord

type PendingHail = {
	t: number,
	lx: number,
	lz: number,
	big: boolean,
}

export type Session = {
	Plot: Plot,
	Player: Player,
	Level: number,
	Params: Config.StormParams,
	Phase: string,
	PhaseTime: number,
	Elapsed: number,
	TotalDuration: number,
	Snapshot: { Grid.Entry },
	StartHP: number,
	Interior: { [number]: boolean },
	InteriorColumns: { [number]: boolean },
	BoundaryDoors: { BlockRecord },
	Submerged: { [number]: boolean },
	SubmergedKey: string,
	PoolLevel: number,
	InsideLevel: number,
	HailBudget: number,
	Pending: { PendingHail },
	AcidTick: number,
	LastOutside: number,
	LastInside: number,
	OutOfZone: number,
	WarnedZone: boolean,
	AttrTimer: number,
	LastLeakCount: number,
	LeakWarned: boolean,
	FloodWarned: boolean,
	Ended: boolean,
	Connections: { RBXScriptConnection },
	Rng: Random,
}

local StormService = {}

local CELL = Grid.CELL
local PIT = Config.Plot.PitHalfSize
local S = Config.Storm
local PHASES = Config.Phases

local PHASE_ORDER = { PHASES.Prep, PHASES.Hail, PHASES.Calm, PHASES.Acid, PHASES.Clear }
local PHASE_DURATION: { [string]: number } = {
	[PHASES.Prep] = S.PrepTime,
	[PHASES.Hail] = S.HailTime,
	[PHASES.Calm] = S.CalmTime,
	[PHASES.Acid] = S.AcidTime,
	[PHASES.Clear] = S.ClearTime,
}
local TOTAL_DURATION = S.PrepTime + S.HailTime + S.CalmTime + S.AcidTime + S.ClearTime
local MAX_LEAK_POINTS = 4

local sessions: { [Player]: Session } = {}
local cooldowns: { [Player]: number } = {}

local function round1(v: number): number
	return math.floor(v * 10 + 0.5) / 10
end

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, text, kind)
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function damagePlayer(session: Session, amount: number)
	if amount <= 0 then
		return
	end
	local hum = getHumanoid(session.Player)
	if hum then
		hum:TakeDamage(amount)
	end
end

----------------------------------------------------------------------
-- Кислота: раскладка луж для клиента (прямоугольники по колонкам сетки + поля котлована).
-- Сами детали кислоты создаёт и плавно двигает клиент (StormFX) по атрибутам уровня.
----------------------------------------------------------------------
local function rectString(x0: number, x1: number, z0: number, z1: number): string
	return string.format("%g,%g,%g,%g", x0, x1, z0, z1)
end

local function buildAcidLayout(session: Session): string
	local outsideCols: { [number]: boolean } = {}
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			local i = Grid.index2(x, z)
			if not session.InteriorColumns[i] then
				outsideCols[i] = true
			end
		end
	end
	local gx0, gz0 = Grid.ORIGIN_X, Grid.ORIGIN_Z
	local gx1, gz1 = -Grid.ORIGIN_X, -Grid.ORIGIN_Z
	local outside: { string } = {}
	for _, r in Grid.greedyRects(outsideCols) do
		table.insert(outside, rectString(gx0 + r.x0 * CELL, gx0 + (r.x1 + 1) * CELL, gz0 + r.z0 * CELL, gz0 + (r.z1 + 1) * CELL))
	end
	-- поля котлована вокруг сетки
	table.insert(outside, rectString(-PIT, PIT, -PIT, gz0))
	table.insert(outside, rectString(-PIT, PIT, gz1, PIT))
	table.insert(outside, rectString(-PIT, gx0, gz0, gz1))
	table.insert(outside, rectString(gx1, PIT, gz0, gz1))
	local inside: { string } = {}
	for _, r in Grid.greedyRects(session.InteriorColumns) do
		table.insert(inside, rectString(gx0 + r.x0 * CELL, gx0 + (r.x1 + 1) * CELL, gz0 + r.z0 * CELL, gz0 + (r.z1 + 1) * CELL))
	end
	return "O:" .. table.concat(outside, ";") .. "|I:" .. table.concat(inside, ";")
end

local function updateAcidVisuals(session: Session)
	local model = session.Plot.Model
	local outside = round1(session.PoolLevel)
	if outside ~= session.LastOutside then
		session.LastOutside = outside
		model:SetAttribute("OutsideAcid", outside)
	end
	local inside = round1(session.InsideLevel)
	if inside ~= session.LastInside then
		session.LastInside = inside
		model:SetAttribute("InsideAcid", inside)
	end
end

----------------------------------------------------------------------
-- Геометрия
----------------------------------------------------------------------
-- Внешние клетки, куда дотекает лужа (кэш по версии участка и числу затопленных слоёв).
local function currentSubmerged(session: Session): { [number]: boolean }
	local layers = Grid.submergedLayers(session.PoolLevel)
	local key = session.Plot.Version .. ":" .. layers
	if key ~= session.SubmergedKey then
		session.Submerged = Grid.computeExteriorBelow(session.Plot.Cells, layers)
		session.SubmergedKey = key
	end
	return session.Submerged
end

-- Высота поверхности (локальная Y), куда упадёт градина.
local envParams = RaycastParams.new()
envParams.FilterType = Enum.RaycastFilterType.Include

local function surfaceHeight(session: Session, lx: number, lz: number): number
	local plot = session.Plot
	local cx, _, cz = Grid.localToCell(lx, 0, lz)
	if Grid.inBounds(cx, 0, cz) then
		local top = Grid.columnTop(plot.Cells, cx, cz)
		return if top then (top + 1) * CELL else 0
	end
	-- вне сетки: пандус / пол
	local env = plot.Model:FindFirstChild("Environment")
	if env then
		envParams.FilterDescendantsInstances = { env }
		local origin = plot.Origin:PointToWorldSpace(Vector3.new(lx, Config.Plot.PitDepth + 2, lz))
		local result = workspace:Raycast(origin, plot.Origin.UpVector * -(Config.Plot.PitDepth + 4), envParams)
		if result then
			return math.max(plot.Origin:PointToObjectSpace(result.Position).Y, 0)
		end
	end
	return 0
end

-- Точка протечки двери: низ двери со стороны бункера, взгляд внутрь.
local function leakCFrame(session: Session, rec: BlockRecord): CFrame?
	local x, y, z = rec.x, rec.y, rec.z
	local candidates = if rec.rot % 2 == 0 then { { 0, 1 }, { 0, -1 } } else { { 1, 0 }, { -1, 0 } }
	for _, c in candidates do
		local nx, nz = x + c[1], z + c[2]
		if Grid.inBounds(nx, y, nz) and session.Interior[Grid.index(nx, y, nz)] then
			local lx, _, lz = Grid.cellCenterLocal(x, y, z)
			local dir = Vector3.new(c[1], 0, c[2])
			local localPos = Vector3.new(lx, y * CELL + 0.3, lz) + dir * 0.6
			local worldPos = session.Plot.Origin:PointToWorldSpace(localPos)
			local worldDir = session.Plot.Origin:VectorToWorldSpace(dir)
			return CFrame.lookAt(worldPos, worldPos + worldDir)
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Град
----------------------------------------------------------------------
local function playerLocal(session: Session): Vector3?
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return (session.Plot.Origin:PointToObjectSpace(root.Position))
	end
	return nil
end

local function spawnHail(session: Session, dt: number)
	local p = session.Params
	session.HailBudget += p.HailRate * dt
	local batch: { { number } } = {}
	local now = os.clock()
	while session.HailBudget >= 1 do
		session.HailBudget -= 1
		local lx = round1(session.Rng:NextNumber(-PIT + 1, PIT - 1))
		local lz = round1(session.Rng:NextNumber(-PIT + 1, PIT - 1))
		local big = session.Rng:NextNumber() < p.HailBigChance
		local impactY = surfaceHeight(session, lx, lz)
		table.insert(batch, { lx, lz, round1(impactY), if big then 1 else 0 })
		table.insert(session.Pending, { t = now + S.FallTime, lx = lx, lz = lz, big = big })
	end
	if #batch > 0 then
		Remotes.HailBatch:FireAllClients(session.Plot.Id, batch)
	end
end

local function applyHail(session: Session, h: PendingHail)
	local p = session.Params
	local plot = session.Plot
	local damage = p.HailDamage * (if h.big then p.HailBigMult else 1)
	local hitRec: BlockRecord? = nil
	local cx, _, cz = Grid.localToCell(h.lx, 0, h.lz)
	local impactY = 0
	if Grid.inBounds(cx, 0, cz) then
		local rec, y = StormSim.hailHit(plot.Cells, cx, cz)
		impactY = y
		if rec then
			hitRec = rec
			PlotService.damage(plot, rec, damage, "hail")
		end
	end
	local lp = playerLocal(session)
	if not lp then
		return
	end
	local amount = StormSim.hailPlayerDamage(p, plot.Cells, hitRec, impactY, h.lx, h.lz, h.big, lp.X, lp.Y, lp.Z)
	damagePlayer(session, amount)
end

local function processPending(session: Session)
	local now = os.clock()
	local pending = session.Pending
	local i = 1
	while i <= #pending do
		local h = pending[i]
		if h.t <= now then
			pending[i] = pending[#pending]
			pending[#pending] = nil
			applyHail(session, h)
		else
			i += 1
		end
	end
end

----------------------------------------------------------------------
-- Кислота
----------------------------------------------------------------------
local function acidDamageTick(session: Session)
	local plot = session.Plot
	local p = session.Params
	-- 1) кислотный дождь разъедает верхние блоки колонок
	if session.Phase == PHASES.Acid then
		for _, rec in StormSim.rainTargets(plot.Cells) do
			PlotService.damage(plot, rec, p.AcidRainDps * rec.def.AcidMult, "acid")
		end
	end
	-- 2) лужа разъедает затопленные блоки, касающиеся кислоты снаружи
	local level = session.PoolLevel
	if level <= 0 then
		return
	end
	for _, rec in StormSim.poolTargets(plot.Records, currentSubmerged(session), level) do
		PlotService.damage(plot, rec, p.PoolDps * rec.def.AcidMult, "acid")
	end
end

local function floodStep(session: Session, dt: number)
	local result = StormSim.flood(
		session.BoundaryDoors,
		session.Interior,
		session.Plot.Cells,
		currentSubmerged(session),
		session.PoolLevel,
		session.Phase == PHASES.Acid,
		session.Params.PoolMax
	)
	local rate = result.rate
	if rate > 0 and session.InsideLevel < result.cap then
		session.InsideLevel = math.min(result.cap, session.InsideLevel + rate * dt)
	end
	local leakRecs: { BlockRecord } = {}
	for i = 1, math.min(#result.leaking, MAX_LEAK_POINTS) do
		table.insert(leakRecs, result.leaking[i])
	end
	-- подсказки "в момент события": объясняем механику, когда игрок её впервые видит
	if #leakRecs > 0 and not session.LeakWarned then
		session.LeakWarned = true
		local door = leakRecs[1].def
		notify(
			session.Player,
			string.format("☣ Кислота просачивается через дверь! «%s» держит только %g ст. Купи дверь прочнее.", door.Name, door.Seal),
			"warning"
		)
	end
	if result.breach and not session.FloodWarned then
		session.FloodWarned = true
		notify(session.Player, "☣ Пробоина в стене! Бункер затапливает — ставь стены прочнее.", "error")
	end

	-- атрибуты для визуала протечки (только при изменении)
	local model = session.Plot.Model
	local leak = math.clamp(rate / 0.6, 0, 1)
	local leakRounded = math.floor(leak * 20 + 0.5) / 20
	if model:GetAttribute("Leak") ~= leakRounded then
		model:SetAttribute("Leak", leakRounded)
	end
	if #leakRecs ~= session.LastLeakCount then
		session.LastLeakCount = #leakRecs
		local n = 0
		for _, rec in leakRecs do
			local cf = leakCFrame(session, rec)
			if cf then
				n += 1
				model:SetAttribute("LeakCF" .. n, cf)
			end
		end
		model:SetAttribute("LeakCount", n)
	end
end

local function playerAcidDamage(session: Session, dt: number)
	local lp = playerLocal(session)
	if not lp then
		return
	end
	local amount = StormSim.playerAcidDamage(
		session.Params,
		session.Phase == PHASES.Acid,
		session.Plot.Cells,
		session.Interior,
		lp.X,
		lp.Y,
		lp.Z,
		session.PoolLevel,
		session.InsideLevel,
		dt
	)
	damagePlayer(session, amount)
end

----------------------------------------------------------------------
-- Жизненный цикл сессии
----------------------------------------------------------------------
local function setPhase(session: Session, phase: string)
	session.Phase = phase
	session.PhaseTime = 0
	local model = session.Plot.Model
	model:SetAttribute("Phase", phase)
	model:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + (PHASE_DURATION[phase] or 0))
	if phase == PHASES.Hail then
		notify(session.Player, "Начался град! Держись в бункере!", "warning")
	elseif phase == PHASES.Acid then
		notify(session.Player, "Кислотный дождь! Кислота разъедает металл и собирается в лужу!", "warning")
	elseif phase == PHASES.Clear then
		notify(session.Player, "Шторм уходит...", "info")
	end
end

local function updateHPAttributes(session: Session)
	local hp = 0
	for _, rec in session.Plot.Records do
		hp += math.max(rec.hp, 0)
	end
	local model = session.Plot.Model
	model:SetAttribute("BunkerHP", math.floor(hp))
	model:SetAttribute("BunkerMaxHP", math.floor(session.StartHP))
	return hp
end

local function cleanupPlot(session: Session)
	local model = session.Plot.Model
	session.Plot.StormFolder:ClearAllChildren()
	model:SetAttribute("Phase", "")
	model:SetAttribute("PhaseEndsAt", 0)
	model:SetAttribute("OutsideAcid", 0)
	model:SetAttribute("InsideAcid", 0)
	model:SetAttribute("Leak", 0)
	model:SetAttribute("LeakCount", 0)
	for i = 1, MAX_LEAK_POINTS do
		model:SetAttribute("LeakCF" .. i, nil)
	end
	model:SetAttribute("SessionOwner", 0)
	model:SetAttribute("AcidLayout", "")
end

local function finish(session: Session, reason: string)
	if session.Ended then
		return
	end
	session.Ended = true
	for _, c in session.Connections do
		c:Disconnect()
	end
	table.clear(session.Connections)

	local player = session.Player
	local plot = session.Plot
	local survived = reason == "survived"
	local hpNow = 0
	for _, rec in plot.Records do
		hpNow += math.max(rec.hp, 0)
	end
	local frac = if session.StartHP > 0 then hpNow / session.StartHP else 0
	local progress = math.clamp(session.Elapsed / session.TotalDuration, 0, 1)

	local data = DataService.get(player)
	local reward = 0
	if reason ~= "quit" and data then
		reward = Config.computeReward(session.Level, survived, frac, progress)
		data.StormsPlayed += 1
		if survived then
			data.StormsSurvived += 1
			data.StormLevel = math.min(Config.Economy.MaxLevel, session.Level + 1)
			data.BestLevel = math.max(data.BestLevel, data.StormLevel)
		end
		if reward > 0 then
			data.Coins += reward
		end
		DataService.replicate(player)
	end

	cleanupPlot(session)
	-- восстанавливаем бункер как был до шторма
	PlotService.clear(plot)
	PlotService.loadEntries(plot, session.Snapshot)
	plot.Session = nil
	sessions[player] = nil
	cooldowns[player] = os.clock()
	if player.Parent == Players then
		player:SetAttribute("InStorm", false)
	end

	if reason ~= "quit" and player.Parent == Players then
		if survived then
			local hum = getHumanoid(player)
			if hum then
				hum.Health = hum.MaxHealth
			end
		end
		local result: Remotes.StormResult = {
			Survived = survived,
			Reward = reward,
			Level = session.Level,
			NewLevel = if data then data.StormLevel else session.Level,
			BunkerPercent = math.floor(math.clamp(frac, 0, 1) * 100 + 0.5),
			Duration = math.floor(session.Elapsed),
			Reason = reason,
		}
		Remotes.StormResult:FireClient(player, result)
	end
end

local function step(session: Session, dt: number)
	local player = session.Player
	if player.Parent ~= Players then
		finish(session, "quit")
		return
	end
	if not getHumanoid(player) then
		finish(session, "died")
		return
	end
	session.Elapsed += dt

	-- игрок должен оставаться на участке
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not PlotService.isInZone(session.Plot, root.Position) then
		session.OutOfZone += dt
		if not session.WarnedZone then
			session.WarnedZone = true
			notify(player, string.format("Вернись на свой участок! Иначе шторм закончится через %d сек.", S.LeaveGrace), "error")
		end
		if session.OutOfZone >= S.LeaveGrace then
			finish(session, "left")
			return
		end
	else
		session.OutOfZone = 0
		session.WarnedZone = false
	end

	-- смена фаз
	session.PhaseTime += dt
	local duration = PHASE_DURATION[session.Phase] or 0
	if session.PhaseTime >= duration then
		local index = table.find(PHASE_ORDER, session.Phase) or #PHASE_ORDER
		if index >= #PHASE_ORDER then
			finish(session, "survived")
			return
		end
		setPhase(session, PHASE_ORDER[index + 1])
	end

	local phase = session.Phase
	if phase == PHASES.Hail then
		spawnHail(session, dt)
	end
	if #session.Pending > 0 then
		processPending(session)
	end

	if phase == PHASES.Acid then
		session.PoolLevel = session.Params.PoolMax * math.clamp(session.PhaseTime / session.Params.PoolRiseTime, 0, 1)
	elseif phase == PHASES.Clear then
		session.PoolLevel = math.max(0, session.PoolLevel - S.DrainRate * dt)
		session.InsideLevel = math.max(0, session.InsideLevel - S.DrainRate * dt)
	end

	if phase == PHASES.Acid then
		session.AcidTick += dt
		if session.AcidTick >= 1 then
			session.AcidTick -= 1
			acidDamageTick(session)
		end
		floodStep(session, dt)
		playerAcidDamage(session, dt)
	elseif phase == PHASES.Clear then
		floodStep(session, 0) -- обновить визуал протечки (уровень уже падает)
	end
	if session.Ended then
		return
	end

	updateAcidVisuals(session)
	session.AttrTimer += dt
	if session.AttrTimer >= 0.5 then
		session.AttrTimer = 0
		updateHPAttributes(session)
	end
end

local function canStart(player: Player): (PlotService.Plot?, string?)
	local plot = PlotService.getPlot(player)
	if not plot then
		return nil, "У тебя нет участка"
	end
	if not DataService.get(player) then
		return nil, "Данные ещё загружаются"
	end
	if plot.Session ~= nil or sessions[player] then
		return nil, "Шторм уже идёт"
	end
	if os.clock() - (cooldowns[player] or 0) < 3 then
		return nil, "Подожди пару секунд"
	end
	local hum = getHumanoid(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then
		return nil, "Персонаж не готов"
	end
	if not PlotService.isInZone(plot, root.Position) then
		return nil, "Зайди на свой участок, чтобы начать шторм"
	end
	return plot, nil
end

function StormService.start(player: Player)
	local plot, err = canStart(player)
	if not plot then
		notify(player, err or "Нельзя начать шторм", "error")
		return
	end
	local data = DataService.get(player)
	local level = if data then data.StormLevel else 1

	local exterior = Grid.computeExterior(plot.Cells)
	local interior = Grid.computeInterior(plot.Cells, exterior)
	local interiorColumns: { [number]: boolean } = {}
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			if interior[Grid.index(x, 0, z)] then
				interiorColumns[Grid.index2(x, z)] = true
			end
		end
	end
	local startHP = 0
	for _, rec in plot.Records do
		startHP += rec.maxHp
	end

	local session: Session = {
		Plot = plot,
		Player = player,
		Level = level,
		Params = Config.stormParams(level),
		Phase = "",
		PhaseTime = 0,
		Elapsed = 0,
		TotalDuration = TOTAL_DURATION,
		Snapshot = PlotService.getEntries(plot),
		StartHP = startHP,
		Interior = interior,
		InteriorColumns = interiorColumns,
		BoundaryDoors = StormSim.boundaryDoors(plot.Records, interior),
		Submerged = {},
		SubmergedKey = "",
		PoolLevel = 0,
		InsideLevel = 0,
		HailBudget = 0,
		Pending = {},
		AcidTick = 0,
		LastOutside = 0,
		LastInside = 0,
		OutOfZone = 0,
		WarnedZone = false,
		AttrTimer = 0,
		LastLeakCount = 0,
		LeakWarned = false,
		FloodWarned = false,
		Ended = false,
		Connections = {},
		Rng = Random.new(),
	}
	plot.Session = session
	sessions[player] = session
	player:SetAttribute("InStorm", true)

	local hum = getHumanoid(player)
	if hum then
		hum.Health = hum.MaxHealth
		table.insert(
			session.Connections,
			hum.Died:Connect(function()
				task.defer(finish, session, "died")
			end)
		)
	end

	local model = plot.Model
	model:SetAttribute("SessionOwner", player.UserId)
	model:SetAttribute("StormLevel", level)
	model:SetAttribute("OutsideAcid", 0)
	model:SetAttribute("InsideAcid", 0)
	model:SetAttribute("Leak", 0)
	model:SetAttribute("LeakCount", 0)
	model:SetAttribute("AcidLayout", buildAcidLayout(session))
	updateHPAttributes(session)
	setPhase(session, PHASES.Prep)

	if Grid.countSet(interior) == 0 then
		notify(player, "Внимание: у тебя нет закрытого бункера! Град и кислота достанут тебя.", "warning")
	elseif not player:GetAttribute("InBunker") then
		notify(player, "Быстрее заходи в бункер и закрой дверь!", "warning")
	end

	task.spawn(function()
		local last = os.clock()
		while not session.Ended do
			task.wait(S.SimStep)
			local now = os.clock()
			local dt = math.min(now - last, 0.5)
			last = now
			local ok, err2 = pcall(step, session, dt)
			if not ok then
				warn("[StormService] step error: " .. tostring(err2))
				finish(session, "quit")
			end
		end
	end)
end

-- Прервать шторм игрока (выход из игры). Бункер восстанавливается.
function StormService.abort(player: Player)
	local session = sessions[player]
	if session then
		finish(session, "quit")
	end
end

function StormService.isActive(player: Player): boolean
	return sessions[player] ~= nil
end

function StormService.init()
	Remotes.StartStorm.OnServerEvent:Connect(function(player)
		StormService.start(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return StormService
