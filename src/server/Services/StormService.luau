--!strict
-- Шторм на участке игрока: Подготовка -> Град -> [Ураган] -> [Метеориты] -> Затишье ->
-- Кислотный дождь -> [Землетрясение] -> Шторм уходит. Дополнительные бедствия выбираются
-- случайно, их число растёт с уровнем (Config.extraDisasterCount).
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
	meteor: boolean,
}

-- Участник шторма: хозяин участка и друзья-гости, которые были на участке при старте.
type Participant = {
	Player: Player,
	OutOfZone: number,
	WarnedZone: boolean,
	Done: boolean,
}

export type Session = {
	Plot: Plot,
	Player: Player, -- хозяин участка
	Participants: { Participant },
	Level: number,
	Params: Config.StormParams,
	Phase: string,
	PhaseOrder: { string },
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
	InteriorBottom: number,
	HailBudget: number,
	MeteorBudget: number,
	WindX: number,
	WindZ: number,
	DisasterTick: number,
	Pending: { PendingHail },
	AcidTick: number,
	LastOutside: number,
	LastInside: number,
	AttrTimer: number,
	LastLeakCount: number,
	LastLeakKey: string,
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

local PHASE_DURATION: { [string]: number } = {
	[PHASES.Prep] = S.PrepTime,
	[PHASES.Hail] = S.HailTime,
	[PHASES.Wind] = S.WindTime,
	[PHASES.Meteor] = S.MeteorTime,
	[PHASES.Calm] = S.CalmTime,
	[PHASES.Acid] = S.AcidTime,
	[PHASES.Quake] = S.QuakeTime,
	[PHASES.Clear] = S.ClearTime,
}
local WIND_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local MAX_LEAK_POINTS = 4
local HAIL_FX_RANGE = 260 -- кому отправлять визуал града (стады от центра участка)

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

local function damagePlayer(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local hum = getHumanoid(player)
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

-- С какой стороны двери внутренность бункера: (dx, dz) по сетке или nil.
local function doorInteriorDir(session: Session, rec: BlockRecord): (number?, number?)
	-- сначала по оси прохода двери, затем по другой (если дверь повёрнута не по стене)
	local candidates = if rec.rot % 2 == 0
		then { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
		else { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	local function isInterior(nx: number, nz: number): boolean
		return Grid.inBounds(nx, rec.y, nz) and session.Interior[Grid.index(nx, rec.y, nz)] == true
	end
	for _, c in candidates do
		-- внутренность с этой стороны и НЕ внутренность с противоположной
		if isInterior(rec.x + c[1], rec.z + c[2]) and not isInterior(rec.x - c[1], rec.z - c[2]) then
			return c[1], c[2]
		end
	end
	return nil, nil
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
	local inside: { string } = {}
	-- Клетка двери делится плоскостью двери: снаружи — уличная кислота, внутри — уровень бункера.
	local half = 0.5 -- половина толщины полотна двери
	for _, rec in session.BoundaryDoors do
		local dx, dz = doorInteriorDir(session, rec)
		local column = Grid.index2(rec.x, rec.z)
		if dx and dz and outsideCols[column] then
			outsideCols[column] = nil
			local cx, _, cz = Grid.cellCenterLocal(rec.x, 0, rec.z)
			local x0, x1, z0, z1 = cx - CELL / 2, cx + CELL / 2, cz - CELL / 2, cz + CELL / 2
			if dz ~= 0 then
				if dz > 0 then
					table.insert(outside, rectString(x0, x1, z0, cz - half))
					table.insert(inside, rectString(x0, x1, cz + half, z1))
				else
					table.insert(outside, rectString(x0, x1, cz + half, z1))
					table.insert(inside, rectString(x0, x1, z0, cz - half))
				end
			else
				if dx > 0 then
					table.insert(outside, rectString(x0, cx - half, z0, z1))
					table.insert(inside, rectString(cx + half, x1, z0, z1))
				else
					table.insert(outside, rectString(cx + half, x1, z0, z1))
					table.insert(inside, rectString(x0, cx - half, z0, z1))
				end
			end
		end
	end
	for _, r in Grid.greedyRects(outsideCols) do
		table.insert(outside, rectString(gx0 + r.x0 * CELL, gx0 + (r.x1 + 1) * CELL, gz0 + r.z0 * CELL, gz0 + (r.z1 + 1) * CELL))
	end
	-- поля котлована вокруг сетки
	table.insert(outside, rectString(-PIT, PIT, -PIT, gz0))
	table.insert(outside, rectString(-PIT, PIT, gz1, PIT))
	table.insert(outside, rectString(-PIT, gx0, gz0, gz1))
	table.insert(outside, rectString(gx1, PIT, gz0, gz1))
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
		model:SetAttribute("InsideDepth", round1(math.max(session.InsideLevel - session.InteriorBottom, 0)))
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
		local _, y = StormSim.hailHit(plot.Cells, cx, cz)
		return y
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
	local dx, dz = doorInteriorDir(session, rec)
	if not dx or not dz then
		return nil
	end
	local lx, _, lz = Grid.cellCenterLocal(rec.x, rec.y, rec.z)
	local dir = Vector3.new(dx, 0, dz)
	local localPos = Vector3.new(lx, Grid.layerBottom(rec.y) + 0.3, lz) + dir * 0.6
	local worldPos = session.Plot.Origin:PointToWorldSpace(localPos)
	local worldDir = session.Plot.Origin:VectorToWorldSpace(dir)
	return CFrame.lookAt(worldPos, worldPos + worldDir)
end

----------------------------------------------------------------------
-- Град
----------------------------------------------------------------------
local function playerLocal(session: Session, player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return (session.Plot.Origin:PointToObjectSpace(root.Position))
	end
	return nil
end

-- Для каждого ещё играющего участника (с позицией в координатах участка).
local function eachActive(session: Session, fn: (Player, Vector3) -> ())
	for _, part in session.Participants do
		if not part.Done then
			local lp = playerLocal(session, part.Player)
			if lp then
				fn(part.Player, lp)
			end
		end
	end
end

local function notifyAll(session: Session, text: string, kind: string)
	for _, part in session.Participants do
		if not part.Done and part.Player.Parent == Players then
			notify(part.Player, text, kind)
		end
	end
end

local function spawnHail(session: Session, dt: number, meteor: boolean)
	local p = session.Params
	local batch: { number } = {}
	local now = os.clock()
	if meteor then
		session.MeteorBudget += p.MeteorRate * dt
	else
		session.HailBudget += p.HailRate * dt
	end
	while (if meteor then session.MeteorBudget else session.HailBudget) >= 1 do
		local lx, lz, big
		if meteor then
			session.MeteorBudget -= 1
			-- метеориты целятся в сетку участка (с небольшим разбросом)
			local half = -Grid.ORIGIN_X + 4
			lx = round1(session.Rng:NextNumber(-half, half))
			lz = round1(session.Rng:NextNumber(-half, half))
			big = true
		else
			session.HailBudget -= 1
			lx = round1(session.Rng:NextNumber(-PIT + 1, PIT - 1))
			lz = round1(session.Rng:NextNumber(-PIT + 1, PIT - 1))
			big = session.Rng:NextNumber() < p.HailBigChance
		end
		local impactY = surfaceHeight(session, lx, lz)
		table.insert(batch, lx)
		table.insert(batch, lz)
		table.insert(batch, round1(impactY))
		table.insert(batch, if meteor then 2 elseif big then 1 else 0)
		local fall = if meteor then S.MeteorFallTime else S.FallTime
		table.insert(session.Pending, { t = now + fall, lx = lx, lz = lz, big = big, meteor = meteor })
	end
	if #batch > 0 then
		-- только визуал: ненадёжный канал и только тем, кто рядом с участком
		local center = session.Plot.Origin.Position
		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - center).Magnitude < HAIL_FX_RANGE then
				Remotes.HailBatch:FireClient(other, session.Plot.Id, batch)
			end
		end
	end
end

local function applyMeteor(session: Session, h: PendingHail)
	local p = session.Params
	local plot = session.Plot
	local cx, _, cz = Grid.localToCell(h.lx, 0, h.lz)
	local impactY: number
	if Grid.inBounds(cx, 0, cz) then
		local hits
		hits, impactY = StormSim.meteorHits(plot.Cells, cx, cz)
		for _, hit in hits do
			PlotService.damage(plot, hit.rec, p.MeteorDamage * hit.mult, "hail")
		end
	else
		impactY = surfaceHeight(session, h.lx, h.lz)
	end
	eachActive(session, function(player, lp)
		damagePlayer(player, StormSim.meteorPlayerDamage(p, plot.Cells, h.lx, h.lz, impactY, lp.X, lp.Y, lp.Z))
	end)
end

local function applyHail(session: Session, h: PendingHail)
	if h.meteor then
		applyMeteor(session, h)
		return
	end
	local p = session.Params
	local plot = session.Plot
	local damage = p.HailDamage * (if h.big then p.HailBigMult else 1)
	local hitRec: BlockRecord? = nil
	local cx, _, cz = Grid.localToCell(h.lx, 0, h.lz)
	local impactY = Grid.layerBottom(Grid.SURFACE)
	if Grid.inBounds(cx, 0, cz) then
		local rec, y = StormSim.hailHit(plot.Cells, cx, cz)
		impactY = y
		if rec then
			hitRec = rec
			PlotService.damage(plot, rec, damage, "hail")
		end
	end
	eachActive(session, function(player, lp)
		damagePlayer(player, StormSim.hailPlayerDamage(p, plot.Cells, hitRec, impactY, h.lx, h.lz, h.big, lp.X, lp.Y, lp.Z))
	end)
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

----------------------------------------------------------------------
-- Ураган и землетрясение (урон раз в секунду)
----------------------------------------------------------------------
local function windTick(session: Session)
	local plot = session.Plot
	local p = session.Params
	for _, rec in StormSim.windTargets(plot.Records, plot.Cells, session.Interior, session.WindX, session.WindZ) do
		PlotService.damage(plot, rec, p.WindDps * StormSim.windFactor(rec.def), "hail")
	end
end

local function quakeTick(session: Session)
	local plot = session.Plot
	local p = session.Params
	local list = table.clone(plot.Records)
	for _, rec in list do
		if rec.alive then
			PlotService.damage(plot, rec, StormSim.quakeDamage(p, rec), "hail")
		end
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
		session.Params.PoolMax,
		session.InteriorBottom
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
		notifyAll(
			session,
			string.format("☣ Кислота просачивается через дверь! «%s» держит только %g ст. Купи дверь прочнее.", door.Name, door.Seal),
			"warning"
		)
	end
	if result.breach and not session.FloodWarned then
		session.FloodWarned = true
		notifyAll(session, "☣ Пробоина в стене! Бункер затапливает — ставь стены прочнее.", "error")
	end

	-- атрибуты для визуала протечки (только при изменении)
	local model = session.Plot.Model
	local leak = math.clamp(rate / 0.6, 0, 1)
	local leakRounded = math.floor(leak * 20 + 0.5) / 20
	if model:GetAttribute("Leak") ~= leakRounded then
		model:SetAttribute("Leak", leakRounded)
	end
	-- точки протечки пересобираем, когда меняется сам набор текущих дверей
	local keyParts = table.create(#leakRecs)
	for _, rec in leakRecs do
		table.insert(keyParts, tostring(rec.cells[1]))
	end
	local leakKey = table.concat(keyParts, ",")
	if leakKey ~= session.LastLeakKey then
		session.LastLeakKey = leakKey
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
	local acidRaining = session.Phase == PHASES.Acid
	eachActive(session, function(player, lp)
		local amount = StormSim.playerAcidDamage(
			session.Params,
			acidRaining,
			session.Plot.Cells,
			session.Interior,
			lp.X,
			lp.Y,
			lp.Z,
			session.PoolLevel,
			session.InsideLevel,
			dt
		)
		damagePlayer(player, amount)
	end)
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
		notifyAll(session, "Начался град! Держись в бункере!", "warning")
	elseif phase == PHASES.Wind then
		local d = WIND_DIRS[session.Rng:NextInteger(1, #WIND_DIRS)]
		session.WindX, session.WindZ = d[1], d[2]
		model:SetAttribute("WindDir", Vector3.new(d[1], 0, d[2]))
		notifyAll(session, "🌪 Ураган! Ветер ломает стены с наветренной стороны — дерево и стекло сдувает!", "warning")
	elseif phase == PHASES.Meteor then
		notifyAll(session, "☄ Метеоритный дождь! Метеориты пробивают крыши — прячься глубже!", "warning")
	elseif phase == PHASES.Quake then
		notifyAll(session, "🌍 Землетрясение! Высокие постройки трясёт сильнее всего, под землёй безопаснее.", "warning")
	elseif phase == PHASES.Acid then
		notifyAll(session, "Кислотный дождь! Кислота разъедает металл и собирается в лужу!", "warning")
	elseif phase == PHASES.Clear then
		notifyAll(session, "Шторм уходит...", "info")
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
	model:SetAttribute("InsideDepth", 0)
	model:SetAttribute("WindDir", nil)
	model:SetAttribute("Leak", 0)
	model:SetAttribute("LeakCount", 0)
	for i = 1, MAX_LEAK_POINTS do
		model:SetAttribute("LeakCF" .. i, nil)
	end
	model:SetAttribute("SessionOwner", 0)
	model:SetAttribute("AcidLayout", "")
end

-- Если восстановленный блок появился там, где стоит игрок, — переносим его внутрь бункера.
local function unstickPlayer(session: Session, player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player.Parent ~= Players or not character or not root or not root:IsA("BasePart") then
		return
	end
	local plot = session.Plot
	local lp = plot.Origin:PointToObjectSpace(root.Position)
	local cx, cy, cz = StormSim.playerCell(lp.X, lp.Y, lp.Z)
	local stuck = false
	for dy = 0, 1 do
		local y = math.max(cy, 0) + dy
		if Grid.inBounds(cx, y, cz) then
			local rec = plot.Cells[Grid.index(cx, y, cz)]
			if rec and not rec.def.IsDoor then
				stuck = true
			end
		end
	end
	if not stuck then
		return
	end
	-- ближайшая внутренняя клетка на нижнем слое бункера
	local best: Vector3? = nil
	local bestDist = math.huge
	for cell in session.Interior do
		local x, y, z = Grid.coords(cell)
		local above = Grid.index(x, y + 1, z)
		if (y == 0 or plot.Cells[Grid.index(x, y - 1, z)]) and y + 1 < Grid.H and session.Interior[above] then
			local lx, _, lz = Grid.cellCenterLocal(x, y, z)
			local pos = Vector3.new(lx, Grid.layerBottom(y) + 3, lz)
			-- расстояние с учётом этажа (иначе можно попасть в чужую комнату на другом уровне)
			local d = (pos - lp).Magnitude
			if d < bestDist then
				bestDist = d
				best = pos
			end
		end
	end
	local target = best or Vector3.new(0, 4, -29) -- иначе — к входу на участок
	character:PivotTo(plot.Origin * CFrame.new(target))
end

local function bunkerFrac(session: Session): number
	local hpNow = 0
	for _, rec in session.Plot.Records do
		hpNow += math.max(rec.hp, 0)
	end
	return if session.StartHP > 0 then hpNow / session.StartHP else 0
end

local function anyActive(session: Session): boolean
	for _, part in session.Participants do
		if not part.Done then
			return true
		end
	end
	return false
end

-- Участник закончил шторм (выжил, погиб, ушёл): награда и результат только ему.
local function endParticipant(session: Session, part: Participant, reason: string)
	if part.Done then
		return
	end
	part.Done = true
	local player = part.Player
	if sessions[player] == session then
		sessions[player] = nil
	end
	local survived = reason == "survived"
	local frac = bunkerFrac(session)
	local progress = math.clamp(session.Elapsed / session.TotalDuration, 0, 1)
	local data = DataService.get(player)
	local reward = 0
	if reason ~= "quit" and data then
		reward = Config.computeReward(session.Level, survived, frac, progress)
		data.StormsPlayed += 1
		if survived then
			data.StormsSurvived += 1
			-- гость, переживший шторм уровнем выше своего, тоже поднимается
			data.StormLevel = math.max(data.StormLevel, math.min(Config.Economy.MaxLevel, session.Level + 1))
			data.BestLevel = math.max(data.BestLevel, data.StormLevel)
		end
		if reward > 0 then
			data.Coins += reward
		end
		DataService.replicate(player)
	end
	if player.Parent ~= Players then
		return
	end
	cooldowns[player] = os.clock()
	player:SetAttribute("InStorm", false)
	if reason == "quit" then
		return
	end
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

local function finish(session: Session, reason: string)
	if session.Ended then
		return
	end
	session.Ended = true
	for _, c in session.Connections do
		c:Disconnect()
	end
	table.clear(session.Connections)

	for _, part in session.Participants do
		endParticipant(session, part, reason)
	end
	local plot = session.Plot
	cleanupPlot(session)
	-- восстанавливаем бункер как был до шторма — всегда, даже если игрок вышел из игры:
	-- сразу после этого раскладка сохраняется в профиль, и в ней не должно быть разрушений
	PlotService.restoreLayout(plot, session.Snapshot)
	for _, part in session.Participants do
		if part.Player.Parent == Players then
			unstickPlayer(session, part.Player)
		end
	end
	plot.Session = nil
end

-- Участник выбыл; если не осталось никого — шторм заканчивается.
local function dropParticipant(session: Session, part: Participant, reason: string)
	if session.Ended or part.Done then
		return
	end
	endParticipant(session, part, reason)
	if not anyActive(session) then
		finish(session, reason)
	elseif reason == "died" then
		notifyAll(session, part.Player.DisplayName .. " выбыл! Держитесь до конца шторма!", "warning")
	end
end

local function step(session: Session, dt: number)
	-- хозяин вышел из игры: бункер восстанавливается, шторм прекращается для всех
	if session.Player.Parent ~= Players then
		finish(session, "quit")
		return
	end
	session.Elapsed += dt

	for _, part in session.Participants do
		if not part.Done then
			local player = part.Player
			if player.Parent ~= Players then
				dropParticipant(session, part, "quit")
			elseif not getHumanoid(player) then
				dropParticipant(session, part, "died")
			else
				-- игрок должен оставаться на участке
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and not PlotService.isInZone(session.Plot, root.Position) then
					part.OutOfZone += dt
					if not part.WarnedZone then
						part.WarnedZone = true
						notify(player, string.format("Вернись на участок! Иначе через %d сек. ты выбудешь из шторма.", S.LeaveGrace), "error")
					end
					if part.OutOfZone >= S.LeaveGrace then
						dropParticipant(session, part, "left")
					end
				else
					part.OutOfZone = 0
					part.WarnedZone = false
				end
			end
			if session.Ended then
				return
			end
		end
	end

	-- смена фаз
	session.PhaseTime += dt
	local duration = PHASE_DURATION[session.Phase] or 0
	if session.PhaseTime >= duration then
		local order = session.PhaseOrder
		local index = table.find(order, session.Phase) or #order
		if index >= #order then
			finish(session, "survived")
			return
		end
		setPhase(session, order[index + 1])
	end

	local phase = session.Phase
	if phase == PHASES.Hail then
		spawnHail(session, dt, false)
	elseif phase == PHASES.Meteor then
		spawnHail(session, dt, true)
	end
	if phase == PHASES.Wind or phase == PHASES.Quake then
		session.DisasterTick += dt
		if session.DisasterTick >= 1 then
			session.DisasterTick -= 1
			if phase == PHASES.Wind then
				windTick(session)
			else
				quakeTick(session)
			end
		end
	end
	if phase == PHASES.Wind then
		eachActive(session, function(player, lp)
			damagePlayer(player, StormSim.windPlayerDamage(session.Params, session.Plot.Cells, session.Interior, lp.X, lp.Y, lp.Z, dt))
		end)
	end
	if #session.Pending > 0 then
		processPending(session)
	end

	if phase == PHASES.Acid then
		session.PoolLevel = session.Params.PoolMax * math.clamp(session.PhaseTime / session.Params.PoolRiseTime, 0, 1)
	elseif phase == PHASES.Quake then
		session.PoolLevel = math.max(0, session.PoolLevel - S.QuakeDrainRate * dt)
	elseif phase == PHASES.Clear then
		session.PoolLevel = math.max(0, session.PoolLevel - S.DrainRate * dt)
		session.InsideLevel = math.max(session.InteriorBottom, session.InsideLevel - S.DrainRate * dt)
	end

	-- во время землетрясения лужа медленно уходит, но продолжает затекать в бункер
	if phase == PHASES.Acid or phase == PHASES.Quake then
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
	if PlotService.getHostPlot(player) then
		return nil, "Ты в бункере друга — шторм запускает хозяин"
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
	-- Колонка "внутренняя", если её нижняя пустая клетка — внутри бункера (бункер на фундаменте,
	-- предметы на полу). Если нижняя пустая клетка — улица (под комнатой на сваях), туда
	-- доходит уличная лужа, и колонка остаётся внешней.
	local interiorColumns: { [number]: boolean } = {}
	for x = 0, Grid.W - 1 do
		for z = 0, Grid.D - 1 do
			for y = 0, Grid.H - 1 do
				local index = Grid.index(x, y, z)
				if not plot.Cells[index] then
					if interior[index] then
						interiorColumns[Grid.index2(x, z)] = true
					end
					break
				end
			end
		end
	end
	local startHP = 0
	for _, rec in plot.Records do
		startHP += rec.maxHp
	end
	-- низ бункера (локальная Y): может быть под землёй
	local interiorBottom = 0
	if next(interior) ~= nil then
		interiorBottom = math.huge
		for cell in interior do
			local _, y = Grid.coords(cell)
			interiorBottom = math.min(interiorBottom, Grid.layerBottom(y))
		end
	end
	local rng = Random.new()
	-- порядок фаз с дополнительными бедствиями
	local pool = table.clone(Config.ExtraDisasters)
	local picked: { [string]: boolean } = {}
	for _ = 1, Config.extraDisasterCount(level) do
		if #pool == 0 then
			break
		end
		picked[table.remove(pool, rng:NextInteger(1, #pool)) :: string] = true
	end
	local order = { PHASES.Prep, PHASES.Hail }
	if picked.Wind then
		table.insert(order, PHASES.Wind)
	end
	if picked.Meteor then
		table.insert(order, PHASES.Meteor)
	end
	table.insert(order, PHASES.Calm)
	table.insert(order, PHASES.Acid)
	if picked.Quake then
		table.insert(order, PHASES.Quake)
	end
	table.insert(order, PHASES.Clear)
	local total = 0
	for _, ph in order do
		total += PHASE_DURATION[ph] or 0
	end

	local session: Session = {
		Plot = plot,
		Player = player,
		Level = level,
		Params = Config.stormParams(level),
		Phase = "",
		PhaseOrder = order,
		PhaseTime = 0,
		Elapsed = 0,
		TotalDuration = total,
		Snapshot = PlotService.getEntries(plot),
		StartHP = startHP,
		Interior = interior,
		InteriorColumns = interiorColumns,
		BoundaryDoors = StormSim.boundaryDoors(plot.Records, interior, plot.Cells),
		Submerged = {},
		SubmergedKey = "",
		PoolLevel = 0,
		InsideLevel = interiorBottom,
		InteriorBottom = interiorBottom,
		HailBudget = 0,
		MeteorBudget = 0,
		WindX = 1,
		WindZ = 0,
		DisasterTick = 0,
		Pending = {},
		AcidTick = 0,
		LastOutside = 0,
		LastInside = interiorBottom,
		Participants = {},
		AttrTimer = 0,
		LastLeakCount = 0,
		LastLeakKey = "",
		LeakWarned = false,
		FloodWarned = false,
		Ended = false,
		Connections = {},
		Rng = rng,
	}
	plot.Session = session

	-- участники: хозяин и друзья-гости, которые сейчас на участке
	local players = { player }
	for member in plot.Members do
		local character = member.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			member.Parent == Players
			and sessions[member] == nil
			and getHumanoid(member)
			and root
			and root:IsA("BasePart")
			and PlotService.isInZone(plot, root.Position)
		then
			table.insert(players, member)
		end
	end
	for _, pl in players do
		local part: Participant = { Player = pl, OutOfZone = 0, WarnedZone = false, Done = false }
		table.insert(session.Participants, part)
		sessions[pl] = session
		pl:SetAttribute("InStorm", true)
		local hum = getHumanoid(pl)
		if hum then
			hum.Health = hum.MaxHealth
			table.insert(
				session.Connections,
				hum.Died:Connect(function()
					task.defer(dropParticipant, session, part, "died")
				end)
			)
		end
	end
	if #players > 1 then
		notifyAll(session, string.format("👥 Шторм для команды из %d игроков! Выживайте вместе.", #players), "info")
	end

	local model = plot.Model
	model:SetAttribute("SessionOwner", player.UserId)
	model:SetAttribute("StormLevel", level)
	model:SetAttribute("OutsideAcid", 0)
	model:SetAttribute("InsideAcid", interiorBottom)
	model:SetAttribute("InsideDepth", 0)
	model:SetAttribute("Leak", 0)
	model:SetAttribute("LeakCount", 0)
	model:SetAttribute("AcidLayout", buildAcidLayout(session))
	updateHPAttributes(session)
	setPhase(session, PHASES.Prep)

	if Grid.countSet(interior) == 0 then
		notifyAll(session, "Внимание: нет закрытого бункера! Град и кислота достанут вас.", "warning")
	else
		notifyAll(session, "Быстрее заходи в бункер и закрой дверь!", "warning")
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
				finish(session, "error")
			end
		end
	end)
end

-- Игрок вышел из игры: хозяин — шторм прекращается (бункер восстанавливается), гость — выбывает.
function StormService.abort(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	if session.Player == player then
		finish(session, "quit")
		return
	end
	for _, part in session.Participants do
		if part.Player == player then
			dropParticipant(session, part, "quit")
		end
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
