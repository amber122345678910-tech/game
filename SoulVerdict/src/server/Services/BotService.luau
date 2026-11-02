--!strict
-- BotService (P60): practice bots (real characters from CharacterService.SpawnBot driven by a server brain)
-- and lobby training dummies. Bots only act while RoundState.Phase is "Round" or "Collapse".
--   Human bots: dodge incoming hazards (dash), revive downed allies, channel SAVE stars when safe, keep a
--     per-kit distance from the monster (ranged ~25 studs, melee ~M1 range), M1 in range, Q/E/R heuristics,
--     occasional blocks, strafing; crawl away when downed.
--   Monster bots: chase the nearest up human (finish downed ones nearby), mobility to close gaps, M1, kit
--     abilities in range, ultimate when charged, Verdict Box with line of sight. Invisible humans (attribute
--     Invisible / an active Status_Invisible) are never targeted or aimed at: the bot searches where it last saw
--     its target for a few seconds instead (BotService.IsInvisible(model) -> boolean).
--   Movement: Humanoid:MoveTo + strafing + unstick (jump + sidestep); facing via an AlignOrientation.
-- Every brain tick is pcall-wrapped: a broken kit or service can never crash the server.
-- Training dummies: blueprint "Dummy", KitId "Dummy", Team "Dummy", 5000 HP, full heal 3 s after the last
-- hit, respawn 3 s after death (lobby ones). Lobby dummies spawn at MapInfo.DummySpawns of the lobby.
--
-- API (SPEC §17)
--   SpawnPracticeBots(side "Human"|"Monster", count, opts?) -> {Model}
--       opts = { Spawns: {CFrame}?, ExcludeKits: {string}?, KitIds: {string}?, MaxHealth: number?,
--                HumanCount: number? (monster HP formula), Team: string? }
--   SpawnDummies(cframes, opts? {Temporary: boolean?}) -> {Model}
--   Clear()            removes practice bots + temporary dummies (lobby dummies stay)
--   ClearDummies()     removes every dummy        Bots() -> {Model}
-- Uses (when present): AbilityService.CastAs(model, abilityId, payload) [+ GetCooldowns, DashAs, BlockAs],
--   HazardService.Get(id)/Count() (active hazard probing), MovementService.Dash, StatusService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local RoundRules = require(Shared:WaitForChild("Round"):WaitForChild("RoundRules")) :: any

local function optionalShared(folder: string, name: string): any
	local f = Shared:FindFirstChild(folder)
	local m = f and f:FindFirstChild(name)
	if m then
		local ok, result = pcall(require, m)
		if ok then
			return result
		end
	end
	return nil
end

local HitTest = optionalShared("Combat", "HitTest")
local Teams = optionalShared("Combat", "Teams")

local BotService = {}
BotService.Priority = 60

local DUMMY_HEALTH = 5000
local DUMMY_REGEN_DELAY = 3
local DUMMY_RESPAWN = 3
local MELEE_FALLBACK_RANGE = 5.5
local RANGED_PREFERRED = 25

type Bot = {
	Model: Model,
	Kind: string, -- "Human" | "Monster"
	Kit: any,
	KitId: string,
	Humanoid: Humanoid,
	Root: BasePart,
	Align: AlignOrientation?,
	Cooldowns: { [string]: number },
	CastId: number,
	StrafeDir: number,
	StrafeUntil: number,
	LastPos: Vector3,
	LastProgressAt: number,
	UnstickUntil: number,
	UnstickTarget: Vector3?,
	BlockUntil: number,
	ReviveTarget: Model?,
	ReviveStarted: number,
	Ranged: boolean,
	PreferredRange: number,
	M1: any,
	M1Range: number,
	Abilities: { any },
	VerdictReadyAt: number,
	LastDashAt: number,
	NextCooldownSync: number,
	Personality: number, -- 0..1: higher = more objective-minded / careful
	LastSeenPos: Vector3?, -- monster: where its target was last visible (searched after it turns invisible)
	LastSeenAt: number,
}

type Dummy = {
	Model: Model,
	CFrame: CFrame,
	LastHit: number,
	Temporary: boolean,
}

local CharacterService: any = nil
local MapService: any = nil
local AbilityService: any = nil
local HazardService: any = nil
local MovementService: any = nil
local StatusService: any = nil
local DamageService: any = nil
local DifficultyService: any = nil

local bots: { [Model]: Bot } = {}
local dummies: { [Model]: Dummy } = {}
local random = Random.new()
local hazardScanHigh = 0

-- Helpers ---------------------------------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function call(service: any, method: string, ...: any): (boolean, any)
	if service == nil then
		return false, nil
	end
	local fn = service[method]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(("[BotService] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = flat(v)
	if f.Magnitude < 1e-3 then
		return fallback
	end
	return f.Unit
end

local function rootOf(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function phaseActive(): boolean
	local rs = ReplicatedStorage:FindFirstChild("RoundState")
	local phase = if rs then rs:GetAttribute("Phase") else nil
	return phase == "Round" or phase == "Collapse"
end

local function hasStatus(model: Model, name: string): boolean
	local ok, result = call(StatusService, "Has", model, name)
	if ok then
		return result == true
	end
	local endsAt = model:GetAttribute("Status_" .. name)
	return type(endsAt) == "number" and endsAt > now()
end

local function canAct(model: Model): boolean
	if StatusService and type(StatusService.CanAct) == "function" then
		local ok, result = pcall(StatusService.CanAct, model)
		if ok then
			return result == true
		end
	end
	return not hasStatus(model, "Stunned") and not hasStatus(model, "Boxed")
end

local function characterFilter(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	local bf = workspace:FindFirstChild("Bots")
	if bf then
		table.insert(ignore, bf)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local objectives = workspace:FindFirstChild("Objectives")
	if objectives then
		table.insert(ignore, objectives)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

local function groundAt(pos: Vector3): Vector3
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), characterFilter())
	if hit then
		return hit.Position
	end
	return pos - Vector3.new(0, 3, 0)
end

local function lineOfSight(from: Vector3, to: Vector3): boolean
	local delta = to - from
	if delta.Magnitude < 1 then
		return true
	end
	return workspace:Raycast(from, delta, characterFilter()) == nil
end

local function aliveModels(team: string): { Model }
	if CharacterService == nil then
		return {}
	end
	local ok, list = call(CharacterService, "GetAll", team)
	if not ok or type(list) ~= "table" then
		return {}
	end
	return list
end

local function healthFraction(model: Model): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.MaxHealth <= 0 then
		return 0
	end
	return humanoid.Health / humanoid.MaxHealth
end

-- Kit analysis ------------------------------------------------------------------------------------------------

local function analyseKit(bot: Bot)
	local kit = bot.Kit
	bot.Abilities = {}
	bot.M1 = nil
	if kit == nil then
		return
	end
	for _, ability in kit.Abilities do
		if ability.Slot == "M1" then
			bot.M1 = ability
		else
			table.insert(bot.Abilities, ability)
		end
	end
	local m1 = bot.M1
	local m1Range = MELEE_FALLBACK_RANGE
	if m1 then
		local n = m1.Numbers or {}
		if type(m1.Range) == "number" and m1.Range > 20 then
			bot.Ranged = true
			m1Range = math.min(m1.Range, 90)
		elseif type(n.Range) == "number" then
			m1Range = n.Range
		end
	end
	bot.M1Range = m1Range
	if bot.Kind == "Monster" then
		bot.PreferredRange = math.max(3.5, m1Range * 0.7)
	elseif bot.Ranged then
		bot.PreferredRange = RANGED_PREFERRED
	else
		bot.PreferredRange = math.max(3.5, m1Range * 0.8)
	end
end

local function ensureAlign(bot: Bot)
	if bot.Align and bot.Align.Parent ~= nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "BotFacing"
	attachment.Parent = bot.Root
	local align = Instance.new("AlignOrientation")
	align.Name = "BotFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.AlignType = Enum.AlignType.AllAxes
	align.RigidityEnabled = false
	align.Responsiveness = 28
	align.MaxTorque = 1e7
	align.CFrame = bot.Root.CFrame - bot.Root.Position
	align.Parent = bot.Root
	bot.Align = align
	bot.Humanoid.AutoRotate = false
end

local function face(bot: Bot, pos: Vector3)
	local root = bot.Root
	local dir = flatUnit(pos - root.Position, root.CFrame.LookVector)
	local align = bot.Align
	if align then
		align.CFrame = CFrame.lookAt(Vector3.zero, dir)
	end
end

local function faceNow(bot: Bot, pos: Vector3)
	-- snap facing right before a cast so melee hitboxes (root relative) line up
	local root = bot.Root
	local dir = flatUnit(pos - root.Position, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	face(bot, pos)
end

local function moveTo(bot: Bot, pos: Vector3)
	bot.Humanoid:MoveTo(pos)
end

local function stop(bot: Bot)
	bot.Humanoid:MoveTo(bot.Root.Position)
end

-- Abilities -----------------------------------------------------------------------------------------------------

local function isReady(bot: Bot, abilityId: string, t: number): boolean
	local readyAt = bot.Cooldowns[abilityId]
	return readyAt == nil or t >= readyAt
end

local function syncCooldowns(bot: Bot)
	local ok, list = call(AbilityService, "GetCooldowns", bot.Model)
	if ok and type(list) == "table" then
		for id, endsAt in list do
			if type(id) == "string" and type(endsAt) == "number" then
				bot.Cooldowns[id] = math.max(bot.Cooldowns[id] or 0, endsAt)
			end
		end
	end
end

local function cast(bot: Bot, ability: any, target: Model?, targetPos: Vector3): boolean
	if AbilityService == nil or type(AbilityService.CastAs) ~= "function" then
		return false
	end
	local root = bot.Root
	local origin = root.Position
	local aim = targetPos
	if ability.Aim == "Ground" then
		aim = groundAt(targetPos)
	elseif ability.Aim == "Self" then
		aim = origin
	end
	local range = ability.Range
	if type(range) == "number" and range > 0 and (aim - origin).Magnitude > range then
		aim = origin + (aim - origin).Unit * range
	end
	local dir = aim - (origin + Vector3.new(0, 1.5, 0))
	dir = if dir.Magnitude > 1e-3 then dir.Unit else root.CFrame.LookVector
	bot.CastId += 1
	local payload = {
		aim = aim,
		dir = dir,
		charge = if ability.Hold then random:NextNumber(0.6, 1) else nil,
		target = target,
		castId = bot.CastId,
	}
	if ability.Aim ~= "Self" and ability.Aim ~= "Ally" then
		faceNow(bot, aim)
	end
	local ok, success = pcall(AbilityService.CastAs, bot.Model, ability.Id, payload)
	local t = now()
	if ok and success == true then
		local cooldown = if type(ability.Cooldown) == "number" then ability.Cooldown else 1
		-- difficulty: practice bots against an Easy player wait longer between their abilities
		local okPace, pace = call(DifficultyService, "BotPace")
		local mult = if okPace and type(pace) == "number" and pace > 0 then pace else 1
		bot.Cooldowns[ability.Id] = t + (cooldown + (ability.Windup or 0)) * mult
		return true
	end
	-- rejected (cooldown/state): back off a little instead of spamming the service
	bot.Cooldowns[ability.Id] = t + 0.6
	return false
end

local function castVerdictBox(bot: Bot, target: Model, targetPos: Vector3): boolean
	if AbilityService == nil or type(AbilityService.CastAs) ~= "function" then
		return false
	end
	local origin = bot.Root.Position
	bot.CastId += 1
	faceNow(bot, targetPos)
	local ok, success = pcall(AbilityService.CastAs, bot.Model, "VerdictBox", {
		aim = targetPos,
		dir = flatUnit(targetPos - origin, bot.Root.CFrame.LookVector),
		target = target,
		castId = bot.CastId,
	})
	local t = now()
	if ok and success == true then
		bot.VerdictReadyAt = t + Config.VerdictBox.Cooldown
		return true
	end
	bot.VerdictReadyAt = t + 2
	return false
end

local function dash(bot: Bot, dir: Vector3): boolean
	local t = now()
	if t - bot.LastDashAt < 0.9 then
		return false
	end
	local model = bot.Model
	local d = flatUnit(dir, bot.Root.CFrame.RightVector)
	if AbilityService and type(AbilityService.DashAs) == "function" then
		local ok, success = pcall(AbilityService.DashAs, model, d)
		if ok and success then
			bot.LastDashAt = t
			return true
		end
		return false
	end
	local charges = model:GetAttribute("DashCharges")
	if type(charges) ~= "number" or charges < 1 or MovementService == nil then
		return false
	end
	model:SetAttribute("DashCharges", charges - 1)
	call(StatusService, "Apply", model, "IFrames", Config.Human.DashIFrames)
	call(MovementService, "Dash", model, d, Config.Human.DashDistance, Config.Human.DashTime)
	bot.LastDashAt = t
	return true
end

local function setBlocking(bot: Bot, on: boolean)
	local model = bot.Model
	local blockFn = AbilityService and (AbilityService.BlockAs or AbilityService.SetBlocking)
	if type(blockFn) == "function" then
		pcall(blockFn, model, on)
	else
		model:SetAttribute("Blocking", on)
		model:SetAttribute("BlockStart", if on then now() else 0)
		call(StatusService, "RecomputeMovement", model)
	end
end

-- Hazard awareness ------------------------------------------------------------------------------------------------

local function activeHazards(): { any }
	if HazardService == nil then
		return {}
	end
	for _, name in { "GetActive", "Active", "List" } do
		local fn = HazardService[name]
		if type(fn) == "function" then
			local ok, list = pcall(fn)
			if ok and type(list) == "table" then
				return list
			end
		end
	end
	if type(HazardService.Get) ~= "function" then
		return {}
	end
	if type(HazardService.Count) == "function" then
		local ok, count = pcall(HazardService.Count)
		if ok and count == 0 then
			return {}
		end
	end
	-- ids are sequential: probe a window around the highest id seen so far
	local out: { any } = {}
	local found = false
	local lo = math.max(1, hazardScanHigh - 80)
	for id = lo, hazardScanHigh + 40 do
		local rec = HazardService.Get(id)
		if rec then
			found = true
			table.insert(out, rec)
			if id > hazardScanHigh then
				hazardScanHigh = id
			end
		end
	end
	if not found then
		-- we fell behind (hazards were spawned while no bot was looking): jump ahead
		for id = hazardScanHigh + 41, hazardScanHigh + 4000, 20 do
			if HazardService.Get(id) then
				hazardScanHigh = id
				break
			end
		end
	end
	return out
end

-- Direction to escape the first enemy hazard whose (slightly grown) volume will touch the bot soon.
local function dangerDirection(bot: Bot, hazards: { any }, t: number): Vector3?
	if HitTest == nil or #hazards == 0 then
		return nil
	end
	local root = bot.Root
	local team = bot.Model:GetAttribute("Team")
	local scale = bot.Model:GetAttribute("RigScale")
	local okCap, capsule = pcall(HitTest.CharacterCapsule, root.Position, if type(scale) == "number" then scale else 1)
	if not okCap then
		return nil
	end
	for _, rec in hazards do
		if type(rec) ~= "table" or rec.Def == nil or rec.Params == nil then
			continue
		end
		if
			Teams
			and type(rec.Team) == "string"
			and type(team) == "string"
			and not Teams.AreEnemyTeams(rec.Team, team)
		then
			continue
		end
		local elapsed = t - (rec.T0 or t)
		local activeEnd = if type(rec.ActiveEnd) == "number" then rec.ActiveEnd else (rec.Duration or 0)
		if elapsed > activeEnd then
			continue
		end
		local sampleT = math.min(activeEnd, math.max(elapsed + 0.3, (rec.Params.delay or 0) + 0.02))
		local okVol, volumes = pcall(rec.Def.Volumes, rec.Params, sampleT)
		if okVol and type(volumes) == "table" then
			for _, volume in volumes do
				local okHit, hit = pcall(HitTest.CapsuleVsVolume, capsule, HitTest.Grow(volume, 2.5))
				if okHit and hit then
					local center = volume.CFrame.Position
					local away: Vector3
					if volume.Shape == "Box" then
						-- step out along the volume's thinner horizontal axis
						local localPos = volume.CFrame:PointToObjectSpace(root.Position)
						if volume.Size.X <= volume.Size.Z then
							away = volume.CFrame.RightVector * (if localPos.X >= 0 then 1 else -1)
						else
							away = volume.CFrame.LookVector * (if localPos.Z <= 0 then 1 else -1)
						end
					else
						away = root.Position - center
					end
					return flatUnit(away, root.CFrame.RightVector * (if random:NextNumber() < 0.5 then 1 else -1))
				end
			end
		end
	end
	return nil
end

-- Brains ------------------------------------------------------------------------------------------------------------

local function nearest(from: Vector3, models: { Model }, filter: ((Model) -> boolean)?): (Model?, number)
	local best: Model? = nil
	local bestDist = math.huge
	for _, model in models do
		if filter == nil or filter(model) then
			local root = rootOf(model)
			if root then
				local d = (root.Position - from).Magnitude
				if d < bestDist then
					best = model
					bestDist = d
				end
			end
		end
	end
	return best, bestDist
end

local function isUp(model: Model): boolean
	return CharacterService ~= nil and CharacterService.IsUp(model)
end

-- Invisible humans (Patience stealth, ...): attribute Invisible, or a Status_Invisible end time still ahead.
local function isInvisible(model: Model): boolean
	if model:GetAttribute("Invisible") == true then
		return true
	end
	local endsAt = model:GetAttribute("Status_Invisible")
	return type(endsAt) == "number" and endsAt > now()
end
BotService.IsInvisible = isInvisible

local SEARCH_TIME = 3 -- monster bots search a vanished target's last seen spot this long

local function strafeTarget(bot: Bot, center: Vector3, t: number): Vector3
	if t >= bot.StrafeUntil then
		bot.StrafeDir = if random:NextNumber() < 0.5 then -1 else 1
		bot.StrafeUntil = t + random:NextNumber(0.8, 2.2)
	end
	local root = bot.Root
	local toCenter = flatUnit(center - root.Position, root.CFrame.LookVector)
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X) * bot.StrafeDir
	return root.Position + side * 8
end

local function updateUnstick(bot: Bot, wantsToMove: boolean, t: number): boolean
	local pos = bot.Root.Position
	if not wantsToMove or (pos - bot.LastPos).Magnitude > 1.2 then
		bot.LastPos = pos
		bot.LastProgressAt = t
		return false
	end
	if t < bot.UnstickUntil and bot.UnstickTarget then
		moveTo(bot, bot.UnstickTarget :: Vector3)
		return true
	end
	if t - bot.LastProgressAt > 1.3 then
		bot.Humanoid.Jump = true
		local side = bot.Root.CFrame.RightVector * (if random:NextNumber() < 0.5 then -1 else 1)
		bot.UnstickTarget = pos + side * 7 - bot.Root.CFrame.LookVector * 3
		bot.UnstickUntil = t + 0.9
		bot.LastProgressAt = t
		moveTo(bot, bot.UnstickTarget :: Vector3)
		return true
	end
	return false
end

local function unlitStars(): { BasePart }
	local out: { BasePart } = {}
	local folder = workspace:FindFirstChild("Objectives")
	if folder == nil then
		return out
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Index") ~= nil and d:GetAttribute("Lit") == false then
			local primary = d.PrimaryPart
			if primary then
				table.insert(out, primary)
			end
		end
	end
	return out
end

local function tryAbilities(bot: Bot, target: Model, targetPos: Vector3, dist: number, t: number, allies: { Model })
	for _, ability in bot.Abilities do
		if not isReady(bot, ability.Id, t) then
			continue
		end
		if ability.Ult then
			local ult = bot.Model:GetAttribute("Ult")
			if type(ult) ~= "number" or ult < 100 then
				continue
			end
		end
		local range = if type(ability.Range) == "number" and ability.Range > 0 then ability.Range else 14
		local aim = ability.Aim
		local wants = false
		local castTarget: Model? = target
		local castPos = targetPos
		if aim == "Self" then
			wants = dist <= 16 or healthFraction(bot.Model) < 0.45
		elseif aim == "Ally" then
			-- support the most hurt ally in range (self included)
			local bestAlly: Model? = nil
			local bestFrac = 0.75
			for _, ally in allies do
				local r = rootOf(ally)
				if r and isUp(ally) and (r.Position - bot.Root.Position).Magnitude <= range then
					local frac = healthFraction(ally)
					if frac < bestFrac then
						bestFrac = frac
						bestAlly = ally
					end
				end
			end
			if bestAlly then
				wants = true
				castTarget = bestAlly
				castPos = (rootOf(bestAlly) :: BasePart).Position
			end
		elseif ability.Slot == "Shift" then
			-- monster mobility: close big gaps
			wants = dist > 26 and dist <= range + 30
		else
			wants = dist <= range * 0.92
		end
		local chance = if ability.Ult then 0.6 else 0.35
		if wants and random:NextNumber() < chance then
			if cast(bot, ability, castTarget, castPos) then
				return -- one ability per think
			end
		end
	end
end

local function thinkDowned(bot: Bot)
	-- crawl away from the monster toward the nearest standing ally
	local root = bot.Root
	local monster = nearest(root.Position, aliveModels("Monster"))
	local ally = nearest(root.Position, aliveModels("Humans"), function(m: Model): boolean
		return m ~= bot.Model and isUp(m)
	end)
	local goal = root.Position
	local allyRoot = rootOf(ally)
	local monsterRoot = rootOf(monster)
	if allyRoot then
		goal = allyRoot.Position
	elseif monsterRoot then
		goal = root.Position + flatUnit(root.Position - monsterRoot.Position, root.CFrame.LookVector) * 10
	end
	face(bot, goal)
	moveTo(bot, goal)
end

local function thinkHuman(bot: Bot, t: number, hazards: { any })
	local model = bot.Model
	local root = bot.Root
	local pos = root.Position
	local monsters = aliveModels("Monster")
	local allies = aliveModels("Humans")
	local monster, dist = nearest(pos, monsters)

	-- 1) dodge
	local danger = dangerDirection(bot, hazards, t)
	if danger then
		bot.ReviveTarget = nil
		if not dash(bot, danger) then
			moveTo(bot, pos + danger * 10)
		end
		return
	end
	if monster == nil then
		stop(bot)
		return
	end
	local monsterPos = (rootOf(monster) :: BasePart).Position

	-- 2) revive a downed ally when the monster is not on top of them
	local downedAlly = nearest(pos, allies, function(m: Model): boolean
		return m ~= model and m:GetAttribute("Downed") == true
	end)
	local revives = ReplicatedStorage:FindFirstChild("RoundState")
	local revivesLeft = if revives then revives:GetAttribute("TeamRevives") else 0
	if downedAlly and type(revivesLeft) == "number" and revivesLeft > 0 then
		local allyRoot = rootOf(downedAlly) :: BasePart
		local allyDist = (allyRoot.Position - pos).Magnitude
		local monsterToAlly = (monsterPos - allyRoot.Position).Magnitude
		if allyDist < 40 and monsterToAlly > 12 then
			face(bot, allyRoot.Position)
			if allyDist > 4.5 then
				bot.ReviveTarget = nil
				moveTo(bot, allyRoot.Position)
				updateUnstick(bot, true, t)
			else
				stop(bot)
				if bot.ReviveTarget ~= downedAlly then
					bot.ReviveTarget = downedAlly
					bot.ReviveStarted = t
				elseif t - bot.ReviveStarted >= Config.Human.ReviveHoldTime then
					bot.ReviveTarget = nil
					call(CharacterService, "Revive", downedAlly, model)
				end
			end
			return
		end
	end
	bot.ReviveTarget = nil

	-- 3) channel a SAVE star when the monster is far away
	if dist > 24 then
		local stars = unlitStars()
		local star, starDist = nil :: BasePart?, math.huge
		for _, s in stars do
			local d = (s.Position - pos).Magnitude
			if d < starDist then
				star, starDist = s, d
			end
		end
		if star and (monsterPos - star.Position).Magnitude > 22 and (starDist < dist or bot.Personality > 0.5) then
			local target = star.Position
			if flat(target - pos).Magnitude > Config.Objectives.SaveRadius * 0.6 then
				face(bot, target)
				moveTo(bot, target)
				updateUnstick(bot, true, t)
			else
				face(bot, monsterPos)
				stop(bot)
			end
			return
		end
	end

	-- 4) fight
	face(bot, monsterPos)
	local preferred = bot.PreferredRange
	local wantsMove = true
	if dist > preferred + 3 then
		local approach = monsterPos + flatUnit(pos - monsterPos, root.CFrame.LookVector) * preferred
		moveTo(bot, approach)
	elseif bot.Ranged and dist < preferred - 7 then
		moveTo(bot, pos + flatUnit(pos - monsterPos, -root.CFrame.LookVector) * 10)
	else
		moveTo(bot, strafeTarget(bot, monsterPos, t))
		wantsMove = false
	end
	updateUnstick(bot, wantsMove, t)

	-- block when a melee monster is close (and guard allows)
	if t >= bot.BlockUntil and model:GetAttribute("Blocking") == true then
		setBlocking(bot, false)
	end
	local guard = model:GetAttribute("Guard")
	if
		dist < 9
		and not bot.Ranged
		and t >= bot.BlockUntil
		and type(guard) == "number"
		and guard > 35
		and random:NextNumber() < 0.06
	then
		bot.BlockUntil = t + random:NextNumber(0.45, 0.9)
		setBlocking(bot, true)
		return
	end
	if model:GetAttribute("Blocking") == true then
		return
	end

	if bot.M1 and isReady(bot, bot.M1.Id, t) and dist <= bot.M1Range + 1.2 then
		if cast(bot, bot.M1, monster, monsterPos) then
			return
		end
	end
	tryAbilities(bot, monster :: Model, monsterPos, dist, t, allies)
end

local function thinkMonster(bot: Bot, t: number)
	local root = bot.Root
	local pos = root.Position
	local humans = aliveModels("Humans")
	local target, dist = nearest(pos, humans, function(m: Model): boolean
		return isUp(m) and not isInvisible(m)
	end)
	local downed, downedDist = nearest(pos, humans, function(m: Model): boolean
		return m:GetAttribute("Downed") == true and not isInvisible(m)
	end)
	if downed and downedDist < 10 and (target == nil or dist > 8) then
		target, dist = downed, downedDist
	end
	if target == nil then
		-- everyone left is invisible (or gone): search the last seen spot for a moment, never aim at the hidden
		local seen = bot.LastSeenPos
		if seen and t - bot.LastSeenAt < SEARCH_TIME and (seen - pos).Magnitude > 3 then
			face(bot, seen)
			moveTo(bot, seen)
			updateUnstick(bot, true, t)
		else
			bot.LastSeenPos = nil
			stop(bot)
		end
		return
	end
	local targetPos = (rootOf(target) :: BasePart).Position
	bot.LastSeenPos = targetPos
	bot.LastSeenAt = t
	face(bot, targetPos)
	if dist > bot.PreferredRange + 1.5 then
		moveTo(bot, targetPos)
		updateUnstick(bot, true, t)
	else
		moveTo(bot, strafeTarget(bot, targetPos, t))
		updateUnstick(bot, false, t)
	end

	if bot.M1 and isReady(bot, bot.M1.Id, t) and dist <= bot.M1Range + 1.5 then
		if cast(bot, bot.M1, target, targetPos) then
			return
		end
	end
	-- Verdict Box: single target, needs line of sight
	if
		t >= bot.VerdictReadyAt
		and dist <= Config.VerdictBox.Range
		and target:GetAttribute("Downed") ~= true
		and random:NextNumber() < 0.2
		and lineOfSight(pos + Vector3.new(0, 2, 0), targetPos)
	then
		if castVerdictBox(bot, target, targetPos) then
			return
		end
	end
	tryAbilities(bot, target, targetPos, dist, t, {})
end

local function think(bot: Bot, t: number, hazards: { any })
	local model = bot.Model
	if bot.Root.Parent == nil or not CharacterService.IsAlive(model) then
		return
	end
	ensureAlign(bot)
	if not phaseActive() then
		stop(bot)
		if model:GetAttribute("Blocking") == true then
			setBlocking(bot, false)
		end
		return
	end
	if model:GetAttribute("Downed") == true then
		thinkDowned(bot)
		return
	end
	if not canAct(model) then
		return
	end
	if bot.Kind == "Monster" then
		thinkMonster(bot, t)
	else
		thinkHuman(bot, t, hazards)
	end
end

-- Registration ---------------------------------------------------------------------------------------------------------

local function addBot(model: Model, kind: string, kit: any)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = rootOf(model)
	if humanoid == nil or root == nil then
		return
	end
	local bot: Bot = {
		Model = model,
		Kind = kind,
		Kit = kit,
		KitId = kit and kit.Id or "",
		Humanoid = humanoid,
		Root = root,
		Align = nil,
		Cooldowns = {},
		CastId = 0,
		StrafeDir = 1,
		StrafeUntil = 0,
		LastPos = root.Position,
		LastProgressAt = now(),
		UnstickUntil = 0,
		UnstickTarget = nil,
		BlockUntil = 0,
		ReviveTarget = nil,
		ReviveStarted = 0,
		Ranged = false,
		PreferredRange = 5,
		M1 = nil,
		M1Range = MELEE_FALLBACK_RANGE,
		Abilities = {},
		-- the Verdict Box is not available right away (gives the human side time to engage)
		VerdictReadyAt = now() + 12,
		LastDashAt = 0,
		NextCooldownSync = 0,
		Personality = random:NextNumber(),
		LastSeenPos = nil,
		LastSeenAt = 0,
	}
	analyseKit(bot)
	-- stagger first casts a little so all bots don't open with their whole kit at once
	for _, ability in bot.Abilities do
		bot.Cooldowns[ability.Id] = now() + random:NextNumber(1, 5)
	end
	bots[model] = bot
end

local function pickHumanKits(count: number, exclude: { string }?, wanted: { string }?): { any }
	local pool: { any } = {}
	if wanted then
		for _, id in wanted do
			local kit = Kits.Get(id)
			if kit and kit.Role == "Human" then
				table.insert(pool, kit)
			end
		end
	end
	if #pool == 0 then
		for _, kit in Kits.ForRole("Human") do
			if exclude == nil or table.find(exclude, kit.Id) == nil then
				table.insert(pool, kit)
			end
		end
		if #pool == 0 then
			pool = Kits.ForRole("Human")
		end
		for i = #pool, 2, -1 do
			local j = random:NextInteger(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
	end
	local out: { any } = {}
	for i = 1, count do
		table.insert(out, pool[((i - 1) % #pool) + 1])
	end
	return out
end

local function spawnFrame(spawns: { CFrame }?, index: number, fallback: CFrame): CFrame
	if spawns and #spawns > 0 then
		local base = spawns[((index - 1) % #spawns) + 1]
		local ring = math.floor((index - 1) / #spawns)
		return base * CFrame.new(ring * 3, 0, 0)
	end
	return fallback * CFrame.new((index - 1) * 4, 0, 0)
end

-- Public API -------------------------------------------------------------------------------------------------------------

function BotService.SpawnPracticeBots(side: string, count: number, opts: any?): { Model }
	local o = if type(opts) == "table" then opts else {}
	local out: { Model } = {}
	if CharacterService == nil then
		return out
	end
	local n = math.clamp(math.floor(tonumber(count) or 1), 0, 11)
	local current: any = nil
	if MapService then
		local _, info = call(MapService, "Current")
		current = info
	end
	if side == "Monster" then
		for i = 1, math.max(1, n) do
			local kit: any = nil
			if type(o.KitIds) == "table" and o.KitIds[i] then
				kit = Kits.Get(o.KitIds[i])
			end
			if kit == nil or kit.Role ~= "Monster" then
				local monsters = Kits.ForRole("Monster")
				kit = monsters[random:NextInteger(1, #monsters)]
			end
			local fallback = if current then current.MonsterSpawn else CFrame.new(0, 0, -40)
			local cf = spawnFrame(o.Spawns, i, fallback)
			local maxHealth = o.MaxHealth
			if type(maxHealth) ~= "number" then
				maxHealth = RoundRules.MonsterMaxHealth(kit.Stats, o.HumanCount or Config.Practice.BotHumans)
			end
			local okSpawn, model = call(CharacterService, "SpawnBot", kit.Id, cf, {
				Team = o.Team or "Monster",
				MaxHealth = maxHealth,
			})
			if okSpawn and model then
				addBot(model, "Monster", kit)
				table.insert(out, model)
			end
		end
	else
		local kits = pickHumanKits(n, o.ExcludeKits, o.KitIds)
		local fallback = if current
				and current.HumanSpawns
				and current.HumanSpawns[1]
			then current.HumanSpawns[1]
			else CFrame.new(0, 0, 40)
		for i, kit in kits do
			local cf = spawnFrame(o.Spawns, i, fallback)
			local okSpawn, model = call(CharacterService, "SpawnBot", kit.Id, cf, { Team = o.Team or "Humans" })
			if okSpawn and model then
				addBot(model, "Human", kit)
				table.insert(out, model)
			end
		end
	end
	return out
end

function BotService.SpawnDummies(cframes: { CFrame }, opts: any?): { Model }
	local out: { Model } = {}
	if CharacterService == nil or type(cframes) ~= "table" then
		return out
	end
	local temporary = type(opts) == "table" and opts.Temporary == true
	for _, cf in cframes do
		if typeof(cf) == "CFrame" then
			local ok, model = call(CharacterService, "SpawnBot", "Dummy", cf, {
				Team = "Dummy",
				MaxHealth = DUMMY_HEALTH,
				Blueprint = "Dummy",
			})
			if ok and model then
				dummies[model] = { Model = model, CFrame = cf, LastHit = 0, Temporary = temporary }
				table.insert(out, model)
			end
		end
	end
	return out
end

function BotService.Bots(): { Model }
	local out: { Model } = {}
	for model in bots do
		table.insert(out, model)
	end
	return out
end

function BotService.Clear()
	local list: { Model } = {}
	for model in bots do
		table.insert(list, model)
	end
	for model, d in dummies do
		if d.Temporary then
			table.insert(list, model)
		end
	end
	for _, model in list do
		bots[model] = nil
		dummies[model] = nil
		call(CharacterService, "Despawn", model)
	end
end

function BotService.ClearDummies()
	local list: { Model } = {}
	for model in dummies do
		table.insert(list, model)
	end
	for _, model in list do
		dummies[model] = nil
		call(CharacterService, "Despawn", model)
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

local function spawnLobbyDummies()
	local lobby: any = nil
	for _ = 1, 40 do
		local ok, info = call(MapService, "Lobby")
		if ok and info then
			lobby = info
			break
		end
		task.wait(0.5)
	end
	if lobby == nil then
		return
	end
	local spots: { CFrame } = {}
	if type(lobby.DummySpawns) == "table" and #lobby.DummySpawns > 0 then
		spots = lobby.DummySpawns
	else
		-- no training area defined: a short row facing the lobby centre
		local center: Vector3 = lobby.Center
		local radius: number = lobby.Radius or 40
		for i = -1, 1 do
			local pos = center + Vector3.new(radius * 0.45, 0, i * 6)
			table.insert(spots, CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
		end
	end
	BotService.SpawnDummies(spots)
end

function BotService.Init()
	CharacterService = tryService("CharacterService")
	MapService = tryService("MapService")
	AbilityService = tryService("AbilityService")
	HazardService = tryService("HazardService")
	MovementService = tryService("MovementService")
	StatusService = tryService("StatusService")
	DamageService = tryService("DamageService")
	DifficultyService = tryService("DifficultyService")
end

function BotService.Start()
	if CharacterService == nil then
		warn("[BotService] CharacterService missing — bots disabled")
		return
	end
	CharacterService.Despawning:Connect(function(model: Model)
		bots[model] = nil
		-- dummies are respawned from their Died handler; a plain despawn just forgets them
		if dummies[model] and dummies[model].Temporary then
			dummies[model] = nil
		end
	end)
	CharacterService.Died:Connect(function(model: Model)
		local d = dummies[model]
		if d == nil then
			return
		end
		dummies[model] = nil
		if d.Temporary then
			return
		end
		task.delay(DUMMY_RESPAWN, function()
			local ok, lobby = call(MapService, "Lobby")
			if ok and lobby then
				BotService.SpawnDummies({ d.CFrame })
			end
		end)
	end)
	if DamageService and DamageService.Damaged then
		DamageService.Damaged:Connect(function(info: any)
			if type(info) == "table" and info.Target and dummies[info.Target] then
				dummies[info.Target].LastHit = now()
			end
		end)
	end
	-- brains
	task.spawn(function()
		while true do
			task.wait(Config.Practice.BotThinkRate)
			local okLoop, loopErr = pcall(function()
				if next(bots) == nil then
					return
				end
				local t = now()
				local hazards = activeHazards()
				local list: { Bot } = {}
				for _, bot in bots do
					table.insert(list, bot)
				end
				for _, bot in list do
					if bots[bot.Model] == bot then
						if t >= bot.NextCooldownSync then
							bot.NextCooldownSync = t + 1
							syncCooldowns(bot)
						end
						local ok, err = pcall(think, bot, t, hazards)
						if not ok then
							warn("[BotService] brain error (" .. bot.KitId .. "): " .. tostring(err))
						end
					end
				end
			end)
			if not okLoop then
				warn("[BotService] loop: " .. tostring(loopErr))
			end
		end
	end)
	-- dummy regeneration
	task.spawn(function()
		while true do
			task.wait(0.5)
			local t = now()
			for model, d in dummies do
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if
					humanoid
					and humanoid.Health > 0
					and humanoid.Health < humanoid.MaxHealth
					and t - d.LastHit >= DUMMY_REGEN_DELAY
				then
					local ok = call(DamageService, "SetHealth", model, humanoid.MaxHealth)
					if not ok then
						humanoid.Health = humanoid.MaxHealth
					end
					model:SetAttribute("KR", 0)
				end
			end
		end
	end)
	task.spawn(spawnLobbyDummies)
end

return BotService
