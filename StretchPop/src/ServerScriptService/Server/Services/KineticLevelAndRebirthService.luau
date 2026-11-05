--!strict
-- STRETCH-POP · KineticLevelAndRebirthService (сервер)
--
-- 1) Полосы: каждому игроку — своя полоса (слот) на тире его профиля.
-- 2) Пробитие: клиент предсказывает разрушение, сервер проверяет
--      • наблюдаемую скорость (по собственным сэмплам позиции, а не по словам клиента),
--      • дистанцию до препятствия с поправкой на пинг,
--      • энергию E = ½·m·v² ≥ прочности (m — ударная масса из статов/перчатки),
--      • лимит частоты; затем ломает деталь для всех, начисляет лут, планирует респаун.
--    Проверка «отложенная»: если сэмплы позиции ещё не догнали RemoteEvent, запрос ждёт до 0.6 с.
-- 3) Гонг Эволюции: порог скорости + комбо (комбо сверяется с отскоками, которые сервер сам
--    видит по резким разворотам траектории, и с подтверждёнными пробитиями).
--    Успех → Rebirth локации: тир +1, волна трансформации идёт по полосе, детали
--    заменяются в момент прохода фронта (по расписанию), множители лута и сложность растут.
-- 4) Античит-минимум: детект телепортов/сверхскоростей с откатом на последнюю честную позицию,
--    респаун при падении в бездну.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local LevelConfig = require(Shared.Config.LevelConfig)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local Net = require(Shared.Net)

local Server = script.Parent.Parent
local PlayerDataService = require(Server.Services.PlayerDataService)
local LevelBuilder = require(Server.Level.LevelBuilder)

local Validation = PhysicsConfig.Validation
local GROUPS = PhysicsConfig.CollisionGroups

type Sample = {
	T: number,
	P: Vector3,
}

type Tracker = {
	Samples: { Sample },
	Head: number, -- индекс самого нового сэмпла
	Count: number,
	LastDir: Vector3,
	LastDirSpeed: number,
	LastTurnAt: number,
	Turns: number, -- серверные «отскоки» за текущий забег
	RunSmashes: number, -- подтверждённые пробития за забег
	SlowSince: number?,
	IgnoreUntil: number,
	Strikes: number,
	FirstStrikeAt: number,
	LastTrusted: CFrame?,
	LastKillRespawn: number,
	Tokens: number,
	TokensAt: number,
	LastGongAt: number,
}

type LaneState = {
	Slot: number,
	Owner: Player,
	Origin: CFrame,
	Handles: LevelBuilder.LaneHandles,
	Layout: LevelBuilder.LaneLayout,
	Tier: number,
	LocationId: string,
	Obstacles: { [string]: ObstacleRecord },
	Gong: BasePart?,
	WaveActiveUntil: number,
	Generation: number,
	Alive: boolean,
}

type ObstacleRecord = {
	Id: string,
	Part: BasePart,
	Spec: LevelBuilder.ObstacleSpec,
	Lane: LaneState,
	Broken: boolean,
}

type PendingRequest = {
	Kind: "Smash" | "Gong",
	Player: Player,
	Lane: LaneState,
	Generation: number,
	ObstacleId: string,
	ImpactVelocity: Vector3,
	ImpactPoint: Vector3,
	ClaimedSpeed: number,
	Combo: number,
	Deadline: number,
	LastReason: string,
}

type Job = {
	At: number,
	Run: () -> (),
}

type Verdict = "Accept" | "Reject" | "Wait"

local KineticLevelAndRebirthService = {}

local world: Folder
local lanesFolder: Folder
local brokenStorage: Folder

local lanesBySlot: { [number]: LaneState } = {}
local lanesByPlayer: { [Player]: LaneState } = {}
local trackers: { [Player]: Tracker } = {}
local pending: { PendingRequest } = {}
local jobs: { Job } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local initialized = false

-- ── Расписание (отсортированный список задач, разбираемый на Heartbeat) ─────

local function schedule(at: number, run: () -> ())
	local job: Job = { At = at, Run = run }
	local low, high = 1, #jobs
	while low <= high do
		local mid = (low + high) // 2
		if jobs[mid].At <= at then
			low = mid + 1
		else
			high = mid - 1
		end
	end
	table.insert(jobs, low, job)
end

local function runDueJobs(now: number)
	local due = 0
	for index, job in jobs do
		if job.At > now then
			break
		end
		due = index
	end
	if due == 0 then
		return
	end
	local count = #jobs
	local ready = table.move(jobs, 1, due, 1, table.create(due))
	table.move(jobs, due + 1, count, 1)
	for index = count - due + 1, count do
		jobs[index] = nil
	end
	for _, job in ready do
		local ok, err = pcall(job.Run)
		if not ok then
			warn("[StretchPop] job failed: " .. tostring(err))
		end
	end
end

-- ── Трекер движения ─────────────────────────────────────────────────────────

local function newTracker(): Tracker
	local now = os.clock()
	return {
		Samples = table.create(Validation.TrackerCapacity),
		Head = 0,
		Count = 0,
		LastDir = Vector3.zero,
		LastDirSpeed = 0,
		LastTurnAt = 0,
		Turns = 0,
		RunSmashes = 0,
		SlowSince = nil,
		IgnoreUntil = now + 1.5,
		Strikes = 0,
		FirstStrikeAt = 0,
		LastTrusted = nil,
		LastKillRespawn = 0,
		Tokens = Validation.SmashTokenBurst,
		TokensAt = now,
		LastGongAt = 0,
	}
end

-- k-й по новизне сэмпл (0 = самый новый)
local function sampleAt(tracker: Tracker, k: number): Sample
	local capacity = Validation.TrackerCapacity
	local index = ((tracker.Head - 1 - k) % capacity) + 1
	return tracker.Samples[index]
end

local function pushSample(tracker: Tracker, t: number, position: Vector3)
	local capacity = Validation.TrackerCapacity
	tracker.Head = (tracker.Head % capacity) + 1
	tracker.Samples[tracker.Head] = { T = t, P = position }
	tracker.Count = math.min(tracker.Count + 1, capacity)
end

local function resetTracker(tracker: Tracker, position: Vector3?, ignoreFor: number)
	local now = os.clock()
	tracker.Head = 0
	tracker.Count = 0
	table.clear(tracker.Samples)
	tracker.IgnoreUntil = now + ignoreFor
	tracker.LastDir = Vector3.zero
	tracker.LastDirSpeed = 0
	tracker.SlowSince = nil
	tracker.Turns = 0
	tracker.RunSmashes = 0
	if position then
		pushSample(tracker, now, position)
	end
end

-- Максимальная скорость по сэмплам за окно (пары с шагом ≥ 1/30 с, чтобы не ловить шум).
local function recentMaxSpeed(tracker: Tracker, now: number, window: number): number
	local best = 0
	for i = 0, tracker.Count - 1 do
		local newer = sampleAt(tracker, i)
		if now - newer.T > window then
			break
		end
		for j = i + 1, tracker.Count - 1 do
			local older = sampleAt(tracker, j)
			local dt = newer.T - older.T
			if dt >= Validation.MinSampleDt then
				if dt <= 0.5 then
					local speed = (newer.P - older.P).Magnitude / dt
					if speed > best then
						best = speed
					end
				end
				break
			end
		end
	end
	return best
end

-- Расстояние от точки до OBB детали.
local function distanceToPart(point: Vector3, cframe: CFrame, size: Vector3): number
	local localPoint = cframe:PointToObjectSpace(point)
	local half = size * 0.5
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - clamped).Magnitude
end

local function minRecentDistance(tracker: Tracker, now: number, window: number, cframe: CFrame, size: Vector3): number
	local best = math.huge
	for i = 0, tracker.Count - 1 do
		local sample = sampleAt(tracker, i)
		if now - sample.T > window then
			break
		end
		local distance = distanceToPart(sample.P, cframe, size)
		if distance < best then
			best = distance
		end
	end
	return best
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function currentParams(player: Player): StretchPhysics.StretchParams?
	local profile = PlayerDataService.Get(player)
	if profile == nil then
		return nil
	end
	return StretchPhysics.Derive(profile.Stats, profile.Gloves.Equipped)
end

-- ── Телепорты (всегда через клиента-владельца физики + страховка сервером) ──

local function teleportPlayer(player: Player, target: CFrame)
	local tracker = trackers[player]
	if tracker then
		resetTracker(tracker, target.Position, 1.5)
	end
	Net.ControllerReset:FireClient(player, target)
	local character = player.Character
	if character then
		task.delay(0.35, function()
			local root = getRoot(player)
			if root and player.Character == character and (root.Position - target.Position).Magnitude > 25 then
				character:PivotTo(target)
			end
		end)
	end
end

local function respawnAtLaneStart(player: Player)
	local lane = lanesByPlayer[player]
	if lane == nil then
		return
	end
	teleportPlayer(player, LevelBuilder.StartCFrame(lane.Slot))
end

local function updateTracker(player: Player, tracker: Tracker, now: number)
	local root = getRoot(player)
	if root == nil then
		return
	end
	local position = root.Position

	if position.Y < PhysicsConfig.KillY and now - tracker.LastKillRespawn > 1 then
		tracker.LastKillRespawn = now
		respawnAtLaneStart(player)
		return
	end

	if tracker.Count > 0 then
		local newest = sampleAt(tracker, 0)
		if (position - newest.P).Magnitude < 0.02 and now - newest.T < 0.25 then
			return -- новых данных физики от клиента ещё нет
		end
	end
	pushSample(tracker, now, position)
	if now < tracker.IgnoreUntil then
		tracker.LastTrusted = root.CFrame
		return
	end

	local reference: Sample? = nil
	for k = 1, tracker.Count - 1 do
		local sample = sampleAt(tracker, k)
		if now - sample.T >= Validation.MinSampleDt then
			reference = sample
			break
		end
	end
	if reference == nil then
		return
	end

	local dt = now - reference.T
	local delta = position - reference.P
	local distance = delta.Magnitude
	local speed = distance / dt

	if distance > Validation.TeleportMinJump and speed > Validation.HardSpeedCap then
		if now - tracker.FirstStrikeAt > Validation.StrikeWindow then
			tracker.Strikes = 0
			tracker.FirstStrikeAt = now
		end
		tracker.Strikes += 1
		local trusted = tracker.LastTrusted
		if tracker.Strikes >= Validation.StrikesBeforePullback and trusted then
			tracker.Strikes = 0
			warn(string.format("[StretchPop] %s: подозрительное перемещение %.0f studs/s — откат", player.Name, speed))
			teleportPlayer(player, trusted)
		else
			resetTracker(tracker, position, 0)
		end
		return
	end

	tracker.LastTrusted = root.CFrame

	if speed > Validation.TurnMinSpeed then
		local direction = delta / distance
		if
			tracker.LastDirSpeed > Validation.TurnMinSpeed
			and direction:Dot(tracker.LastDir) < Validation.TurnCos
			and now - tracker.LastTurnAt > Validation.TurnCooldown
		then
			tracker.Turns += 1
			tracker.LastTurnAt = now
		end
		tracker.LastDir = direction
		tracker.LastDirSpeed = speed
	end

	if speed < Validation.RestSpeed then
		local slowSince = tracker.SlowSince
		if slowSince == nil then
			tracker.SlowSince = now
		elseif now - slowSince > Validation.RestTime then
			tracker.Turns = 0
			tracker.RunSmashes = 0
			tracker.LastDirSpeed = 0
		end
	else
		tracker.SlowSince = nil
	end
end

local function consumeToken(tracker: Tracker, now: number): boolean
	tracker.Tokens = math.min(
		Validation.SmashTokenBurst,
		tracker.Tokens + (now - tracker.TokensAt) * Validation.SmashTokensPerSecond
	)
	tracker.TokensAt = now
	if tracker.Tokens < 1 then
		return false
	end
	tracker.Tokens -= 1
	return true
end

-- ── Полосы ──────────────────────────────────────────────────────────────────

local function buildContext(lane: LaneState, tier: number): LevelBuilder.BuildContext
	return {
		Origin = lane.Origin,
		Theme = LevelConfig.GetTheme(tier),
		Slot = lane.Slot,
		Tier = tier,
		OwnerUserId = lane.Owner.UserId,
	}
end

local function registerObstacle(lane: LaneState, spec: LevelBuilder.ObstacleSpec, part: BasePart)
	lane.Obstacles[spec.Id] = {
		Id = spec.Id,
		Part = part,
		Spec = spec,
		Lane = lane,
		Broken = false,
	}
end

local function allocateSlot(): number?
	for slot = 1, LevelConfig.MaxSlots do
		if lanesBySlot[slot] == nil then
			return slot
		end
	end
	return nil
end

local function createLaneFor(player: Player, profile: Types.PlayerProfile): LaneState?
	local slot = allocateSlot()
	if slot == nil then
		return nil
	end
	local locationId = profile.ActiveLocation
	local tier = PlayerDataService.GetLocation(profile, locationId).Tier
	local layout = LevelBuilder.GenerateLayout(locationId, tier)
	local origin = LevelConfig.SlotOrigin(slot)
	local context: LevelBuilder.BuildContext = {
		Origin = origin,
		Theme = LevelConfig.GetTheme(tier),
		Slot = slot,
		Tier = tier,
		OwnerUserId = player.UserId,
	}
	local handles = LevelBuilder.CreateLane(layout, context, lanesFolder)
	local lane: LaneState = {
		Slot = slot,
		Owner = player,
		Origin = origin,
		Handles = handles,
		Layout = layout,
		Tier = tier,
		LocationId = locationId,
		Obstacles = {},
		Gong = handles.Gong,
		WaveActiveUntil = 0,
		Generation = 1,
		Alive = true,
	}
	for _, spec in layout.Obstacles do
		local part = handles.Obstacles[spec.Id]
		if part then
			registerObstacle(lane, spec, part)
		end
	end
	lanesBySlot[slot] = lane
	lanesByPlayer[player] = lane
	player:SetAttribute("LaneSlot", slot)
	return lane
end

local function destroyLane(lane: LaneState)
	lane.Alive = false
	for _, record in lane.Obstacles do
		record.Part:Destroy()
	end
	table.clear(lane.Obstacles)
	lane.Handles.Model:Destroy()
	if lanesBySlot[lane.Slot] == lane then
		lanesBySlot[lane.Slot] = nil
	end
	if lanesByPlayer[lane.Owner] == lane then
		lanesByPlayer[lane.Owner] = nil
	end
end

-- ── Пробитие ────────────────────────────────────────────────────────────────

local function snapshotOf(record: ObstacleRecord): Types.SmashSnapshot
	local part = record.Part
	return {
		CFrame = part.CFrame,
		Size = part.Size,
		Color = part.Color,
		Material = part.Material,
		Kind = record.Spec.Kind,
	}
end

local function evaluateSmash(request: PendingRequest, tracker: Tracker, now: number): (Verdict, string)
	local lane = request.Lane
	if not lane.Alive or lane.Generation ~= request.Generation then
		return "Reject", "lane_changed"
	end
	local record = lane.Obstacles[request.ObstacleId]
	if record == nil then
		return "Reject", "unknown_obstacle"
	end
	if record.Broken then
		return "Reject", "already_broken"
	end
	local params = currentParams(request.Player)
	if params == nil then
		return "Reject", "no_profile"
	end
	local claimed = math.min(request.ClaimedSpeed, request.ImpactVelocity.Magnitude + 1, PhysicsConfig.MaxFlightSpeed)
	if not StretchPhysics.CanSmash(record.Spec.Durability * 0.98, params.ImpactMass, claimed) then
		return "Reject", "too_weak"
	end
	local observed = recentMaxSpeed(tracker, now, Validation.ObservedWindow)
	if claimed > observed * Validation.SpeedSlack + Validation.SpeedFlat then
		return "Wait", "speed_unverified"
	end
	local reach = Validation.DistanceBase + observed * Validation.DistanceLatency
	local distance = minRecentDistance(tracker, now, Validation.ObservedWindow, record.Part.CFrame, record.Part.Size)
	if distance > reach then
		return "Wait", "too_far"
	end
	return "Accept", "ok"
end

local function applySmash(request: PendingRequest, tracker: Tracker)
	local lane = request.Lane
	local record = lane.Obstacles[request.ObstacleId]
	if record == nil or record.Broken then
		return
	end
	local snapshot = snapshotOf(record)
	record.Broken = true
	record.Part.Parent = brokenStorage
	tracker.RunSmashes += 1

	local loot = record.Spec.Loot
	local isChest = record.Spec.Kind == "Chest"
	local speed = request.ClaimedSpeed
	PlayerDataService.Update(request.Player, function(profile)
		profile.Coins += loot
		profile.Records.LootEarned += loot
		if isChest then
			profile.Records.ChestsOpened += 1
		else
			profile.Records.WallsSmashed += 1
		end
		profile.Records.TopSpeed = math.max(profile.Records.TopSpeed, speed)
		local location = PlayerDataService.GetLocation(profile, lane.LocationId)
		location.BestSpeed = math.max(location.BestSpeed, speed)
	end)

	Net.SmashResult:FireClient(request.Player, record.Id, true, loot, nil)
	Net.ObstacleSmashed:FireAllClients(
		request.Player.UserId,
		lane.Slot,
		record.Id,
		snapshot,
		request.ImpactPoint,
		request.ImpactVelocity
	)

	local generation = lane.Generation
	schedule(os.clock() + LevelConfig.ObstacleRespawnTime, function()
		if lane.Alive and lane.Generation == generation and record.Broken and lane.Obstacles[record.Id] == record then
			record.Broken = false
			record.Part.Parent = lane.Handles.ObstacleFolder
		end
	end)
end

-- ── Гонг Эволюции и мутация локации ────────────────────────────────────────

local function evaluateGong(request: PendingRequest, tracker: Tracker, now: number): (Verdict, string)
	local lane = request.Lane
	if not lane.Alive or lane.Generation ~= request.Generation then
		return "Reject", "lane_changed"
	end
	if now < lane.WaveActiveUntil then
		return "Reject", "wave_in_progress"
	end
	local gong = lane.Gong
	if gong == nil or gong.Parent == nil then
		return "Reject", "no_gong"
	end
	local needSpeed, needCombo = LevelConfig.GongRequirement(lane.Tier)
	local claimed = math.min(request.ClaimedSpeed, request.ImpactVelocity.Magnitude + 1, PhysicsConfig.MaxFlightSpeed)
	if claimed < needSpeed then
		return "Reject", "too_slow"
	end
	if request.Combo < needCombo then
		return "Reject", "combo_too_low"
	end
	local observed = recentMaxSpeed(tracker, now, Validation.ObservedWindow)
	if claimed > observed * Validation.SpeedSlack + Validation.SpeedFlat then
		return "Wait", "speed_unverified"
	end
	if request.Combo > tracker.Turns + tracker.RunSmashes + Validation.ComboSlack then
		return "Wait", "combo_unverified"
	end
	local reach = Validation.DistanceBase + 10 + observed * Validation.DistanceLatency
	if minRecentDistance(tracker, now, Validation.ObservedWindow, gong.CFrame, gong.Size) > reach then
		return "Wait", "too_far"
	end
	return "Accept", "ok"
end

local function partLocalZ(lane: LaneState, part: BasePart): number
	local stored = part:GetAttribute("LocalZ")
	if typeof(stored) == "number" then
		return stored
	end
	return lane.Origin:PointToObjectSpace(part.Position).Z
end

local function runMutationWave(lane: LaneState, newTier: number)
	local player = lane.Owner
	local oldLayout = lane.Layout
	local newLayout = LevelBuilder.GenerateLayout(lane.LocationId, newTier)
	lane.Generation += 1
	local generation = lane.Generation
	lane.Tier = newTier
	lane.Layout = newLayout

	local rebirth = LevelConfig.Rebirth
	local now = os.clock()
	local waveStart = now + rebirth.StartDelay
	local originZ = -math.max(oldLayout.Length, newLayout.Length) - 40
	local endZ = LevelConfig.StartPadSize.Z * 0.5 + 30
	local speed = rebirth.WaveSpeed
	local duration = (endZ - originZ) / speed
	lane.WaveActiveUntil = waveStart + duration + 0.5

	local function timeAt(localZ: number): number
		return waveStart + math.max(localZ - originZ, 0) / speed
	end

	local waveInfo: Types.RebirthWaveInfo = {
		Slot = lane.Slot,
		OwnerUserId = player.UserId,
		Tier = newTier,
		LaneOrigin = lane.Origin,
		OriginZ = originZ,
		EndZ = endZ,
		Speed = speed,
		StartServerTime = workspace:GetServerTimeNow() + rebirth.StartDelay,
		LaneWidth = LevelConfig.LaneWidth,
	}
	Net.RebirthWave:FireAllClients(waveInfo)

	-- Игрок смотрит со старта, как волна идёт на него
	schedule(now + rebirth.TeleportDelay, function()
		if lane.Alive and lane.Generation == generation and player.Parent == Players then
			teleportPlayer(player, LevelBuilder.StartCFrame(lane.Slot))
		end
	end)

	-- Снос старых деталей в момент прохода фронта
	for _, child in lane.Handles.Mutable:GetChildren() do
		if child:IsA("BasePart") then
			local part = child
			schedule(timeAt(partLocalZ(lane, part)), function()
				if lane.Alive and lane.Generation == generation then
					part:Destroy()
				end
			end)
		end
	end
	local oldRecords = lane.Obstacles
	lane.Obstacles = {}
	for _, record in oldRecords do
		local part = record.Part
		schedule(timeAt(record.Spec.LocalCFrame.Position.Z), function()
			if lane.Alive and lane.Generation == generation then
				part:Destroy()
			end
		end)
	end
	lane.Gong = nil

	-- Новые детали появляются сразу за фронтом
	local context = buildContext(lane, newTier)
	for _, spec in newLayout.Pieces do
		schedule(timeAt(spec.LocalCFrame.Position.Z) + 0.05, function()
			if lane.Alive and lane.Generation == generation then
				local part = LevelBuilder.BuildPiece(spec, context, lane.Handles.Mutable)
				if spec.Kind == "GongDisc" then
					lane.Gong = part
				end
			end
		end)
	end
	for _, spec in newLayout.Obstacles do
		schedule(timeAt(spec.LocalCFrame.Position.Z) + 0.05, function()
			if lane.Alive and lane.Generation == generation then
				local part = LevelBuilder.BuildObstacle(spec, context, lane.Handles.ObstacleFolder)
				registerObstacle(lane, spec, part)
			end
		end)
	end

	-- Финал волны: перекраска старта, атрибут тира полосы
	schedule(waveStart + duration, function()
		if lane.Alive and lane.Generation == generation then
			LevelBuilder.ApplyTheme(lane.Handles.StartPad, context.Theme)
			LevelBuilder.ApplyTheme(lane.Handles.StartSign, context.Theme)
			lane.Handles.Model:SetAttribute("Tier", newTier)
		end
	end)
end

local function applyGong(request: PendingRequest, tracker: Tracker)
	local lane = request.Lane
	local player = request.Player
	local newTier = lane.Tier + 1
	local bonus = math.floor(LevelConfig.RebirthBonus * LevelConfig.LootMultiplier(newTier) + 0.5)
	local speed = request.ClaimedSpeed
	local combo = request.Combo
	tracker.LastGongAt = os.clock()

	PlayerDataService.Update(player, function(profile)
		local location = PlayerDataService.GetLocation(profile, lane.LocationId)
		location.Tier = newTier
		location.Rebirths += 1
		location.BestSpeed = math.max(location.BestSpeed, speed)
		location.BestCombo = math.max(location.BestCombo, combo)
		profile.TotalRebirths += 1
		profile.Coins += bonus
		profile.Records.LootEarned += bonus
		profile.Records.TopSpeed = math.max(profile.Records.TopSpeed, speed)
		profile.Records.LongestCombo = math.max(profile.Records.LongestCombo, combo)
	end)

	local needSpeed, needCombo = LevelConfig.GongRequirement(newTier - 1)
	Net.GongResult:FireClient(player, true, "rebirth", needSpeed, needCombo, speed, combo)
	runMutationWave(lane, newTier)
end

local function rejectRequest(request: PendingRequest, reason: string)
	if request.Kind == "Smash" then
		Net.SmashResult:FireClient(request.Player, request.ObstacleId, false, 0, reason)
	else
		local lane = request.Lane
		local needSpeed, needCombo = LevelConfig.GongRequirement(lane.Tier)
		Net.GongResult:FireClient(request.Player, false, reason, needSpeed, needCombo, request.ClaimedSpeed, request.Combo)
	end
end

local function processPending(now: number)
	local index = 1
	while index <= #pending do
		local request = pending[index]
		local tracker = trackers[request.Player]
		local verdict: Verdict
		local reason: string
		if tracker == nil or request.Player.Parent ~= Players then
			verdict, reason = "Reject", "left"
		elseif request.Kind == "Smash" then
			verdict, reason = evaluateSmash(request, tracker, now)
		else
			verdict, reason = evaluateGong(request, tracker, now)
		end
		request.LastReason = reason
		if verdict == "Wait" and now < request.Deadline then
			index += 1
		else
			pending[index] = pending[#pending]
			pending[#pending] = nil
			if verdict == "Accept" and tracker then
				if request.Kind == "Smash" then
					applySmash(request, tracker)
				else
					applyGong(request, tracker)
				end
			elseif request.Player.Parent == Players then
				rejectRequest(request, reason)
			end
		end
	end
end

-- ── Сетевые обработчики (все аргументы клиента — недоверенные) ─────────────

local function isSaneNumber(value: unknown, minValue: number, maxValue: number): boolean
	return typeof(value) == "number" and value == value and value >= minValue and value <= maxValue
end

local function onSmashRequest(player: Player, obstacleId: unknown, impactVelocity: unknown, impactPoint: unknown, impactSpeed: unknown, combo: unknown)
	if typeof(obstacleId) ~= "string" or #obstacleId == 0 or #obstacleId > 48 then
		return
	end
	if typeof(impactVelocity) ~= "Vector3" or not StretchPhysics.IsFiniteVector(impactVelocity, 1e4) then
		return
	end
	if typeof(impactPoint) ~= "Vector3" or not StretchPhysics.IsFiniteVector(impactPoint, 1e6) then
		return
	end
	if not isSaneNumber(impactSpeed, 0, 1e4) or not isSaneNumber(combo, 0, 1e4) then
		return
	end
	local tracker = trackers[player]
	local lane = lanesByPlayer[player]
	if tracker == nil or lane == nil then
		return
	end
	local now = os.clock()
	if not consumeToken(tracker, now) then
		Net.SmashResult:FireClient(player, obstacleId, false, 0, "rate_limited")
		return
	end
	local record = lane.Obstacles[obstacleId]
	if record == nil or record.Broken then
		Net.SmashResult:FireClient(player, obstacleId, false, 0, if record then "already_broken" else "unknown_obstacle")
		return
	end
	for _, request in pending do
		if request.Player == player and request.Kind == "Smash" and request.ObstacleId == obstacleId then
			return -- дубликат уже в очереди
		end
	end
	table.insert(pending, {
		Kind = "Smash",
		Player = player,
		Lane = lane,
		Generation = lane.Generation,
		ObstacleId = obstacleId,
		ImpactVelocity = impactVelocity,
		ImpactPoint = impactPoint,
		ClaimedSpeed = impactSpeed :: number,
		Combo = math.floor(combo :: number),
		Deadline = now + Validation.PendingTimeout,
		LastReason = "queued",
	})
end

local function onGongStrike(player: Player, slot: unknown, impactVelocity: unknown, impactSpeed: unknown, combo: unknown)
	if not isSaneNumber(slot, 1, LevelConfig.MaxSlots) then
		return
	end
	if typeof(impactVelocity) ~= "Vector3" or not StretchPhysics.IsFiniteVector(impactVelocity, 1e4) then
		return
	end
	if not isSaneNumber(impactSpeed, 0, 1e4) or not isSaneNumber(combo, 0, 1e4) then
		return
	end
	local tracker = trackers[player]
	local lane = lanesByPlayer[player]
	if tracker == nil or lane == nil then
		return
	end
	local now = os.clock()
	local claimedSpeed = impactSpeed :: number
	local claimedCombo = math.floor(combo :: number)
	if lane.Slot ~= slot then
		local needSpeed, needCombo = LevelConfig.GongRequirement(lane.Tier)
		Net.GongResult:FireClient(player, false, "not_your_lane", needSpeed, needCombo, claimedSpeed, claimedCombo)
		return
	end
	if now - tracker.LastGongAt < LevelConfig.Rebirth.Cooldown then
		local needSpeed, needCombo = LevelConfig.GongRequirement(lane.Tier)
		Net.GongResult:FireClient(player, false, "cooldown", needSpeed, needCombo, claimedSpeed, claimedCombo)
		return
	end
	for _, request in pending do
		if request.Player == player and request.Kind == "Gong" then
			return
		end
	end
	tracker.LastGongAt = now - LevelConfig.Rebirth.Cooldown + 1 -- антиспам: следующая попытка не раньше чем через 1 с
	table.insert(pending, {
		Kind = "Gong",
		Player = player,
		Lane = lane,
		Generation = lane.Generation,
		ObstacleId = "",
		ImpactVelocity = impactVelocity,
		ImpactPoint = Vector3.zero,
		ClaimedSpeed = claimedSpeed,
		Combo = claimedCombo,
		Deadline = now + Validation.PendingTimeout,
		LastReason = "queued",
	})
end

-- ── Персонажи ───────────────────────────────────────────────────────────────

local function assignCollisionGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = GROUPS.Characters
	end
end

local function disconnectCharacter(player: Player)
	local connections = characterConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
end

local function onCharacterAdded(player: Player, character: Model)
	disconnectCharacter(player)
	local connections: { RBXScriptConnection } = {}
	characterConnections[player] = connections

	for _, descendant in character:GetDescendants() do
		assignCollisionGroup(descendant)
	end
	table.insert(connections, character.DescendantAdded:Connect(assignCollisionGroup))

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(
			connections,
			humanoid.Died:Connect(function()
				task.delay(Players.RespawnTime, function()
					if player.Parent == Players and player.Character == character then
						player:LoadCharacter()
					end
				end)
			end)
		)
	end

	local root = character:WaitForChild("HumanoidRootPart", 10)
	local lane = lanesByPlayer[player]
	if root and lane and player.Character == character then
		local start = LevelBuilder.StartCFrame(lane.Slot)
		character:PivotTo(start)
		-- Клиент-владелец физики ставит персонажа сам; сервер перепроверит через 0.35 с
		teleportPlayer(player, start)
	end
end

local function onPlayerAdded(player: Player)
	local profile = PlayerDataService.WaitFor(player, 60)
	if profile == nil or player.Parent ~= Players then
		return
	end
	if lanesByPlayer[player] then
		return
	end
	trackers[player] = newTracker()
	local lane = createLaneFor(player, profile)
	if lane == nil then
		player:Kick("STRETCH-POP: на сервере нет свободных полос, зайди на другой сервер.")
		return
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	else
		player:LoadCharacter()
	end
end

local function onPlayerRemoving(player: Player)
	disconnectCharacter(player)
	local lane = lanesByPlayer[player]
	if lane then
		destroyLane(lane)
	end
	trackers[player] = nil
	for index = #pending, 1, -1 do
		if pending[index].Player == player then
			table.remove(pending, index)
		end
	end
end

local function setupCollisionGroups()
	for _, name in { GROUPS.Characters, GROUPS.Debris } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Characters, GROUPS.Characters, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Characters, GROUPS.Debris, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Debris, GROUPS.Debris, false)
end

-- ── Публичное API ───────────────────────────────────────────────────────────

function KineticLevelAndRebirthService.GetLaneSlot(player: Player): number?
	local lane = lanesByPlayer[player]
	return if lane then lane.Slot else nil
end

function KineticLevelAndRebirthService.GetObservedSpeed(player: Player): number
	local tracker = trackers[player]
	if tracker == nil then
		return 0
	end
	return recentMaxSpeed(tracker, os.clock(), 0.3)
end

function KineticLevelAndRebirthService.GetLaneTier(player: Player): number?
	local lane = lanesByPlayer[player]
	return if lane then lane.Tier else nil
end

function KineticLevelAndRebirthService.Init()
	if initialized then
		return
	end
	initialized = true
	setupCollisionGroups()

	local existingWorld = workspace:FindFirstChild("StretchPopWorld")
	if existingWorld then
		existingWorld:Destroy()
	end
	world = Instance.new("Folder")
	world.Name = "StretchPopWorld"
	lanesFolder = Instance.new("Folder")
	lanesFolder.Name = "Lanes"
	lanesFolder.Parent = world
	world.Parent = workspace

	brokenStorage = Instance.new("Folder")
	brokenStorage.Name = "StretchPopBroken"
	brokenStorage.Parent = ServerStorage

	Net.SmashRequest.OnServerEvent:Connect(onSmashRequest)
	Net.GongStrike.OnServerEvent:Connect(onGongStrike)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, tracker in trackers do
			updateTracker(player, tracker, now)
		end
		processPending(now)
		runDueJobs(now)
	end)
end

return KineticLevelAndRebirthService
