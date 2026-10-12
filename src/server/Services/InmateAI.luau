--!strict
-- Один пациент (одно тело): риг, анимации, восприятие (зрение/слух), путь, состояния
-- Enter → Roam → Investigate → Chase → Search → Roam; Retreat на рассвете. Особые режимы по Kind.
-- Никаких телепортов и "телепатии": без видимости и шума он знает только общую зону отряда (подсказка режиссёра).

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Inmates = require(Shared:WaitForChild("Inmates"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local World = require(script.Parent:WaitForChild("World"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local HouseService = require(script.Parent:WaitForChild("HouseService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ServerSounds = require(script.Parent:WaitForChild("ServerSounds"))
local R15Rig = require(script.Parent:WaitForChild("R15Rig"))

local InmateAI = {}
InmateAI.__index = InmateAI

export type State = "Enter" | "Roam" | "Investigate" | "Chase" | "Search" | "Stunned" | "Retreat" | "Sentinel" | "Look" | "Gone"

local ANIM_WALK = "rbxassetid://616168032"
local ANIM_RUN = "rbxassetid://616163682"
local ANIM_IDLE = "rbxassetid://616158929"

export type Inmate = typeof(setmetatable({} :: {
	Def: Inmates.InmateDef,
	Id: string,
	BodyIndex: number,
	Model: Model,
	Parts: { [string]: BasePart },
	Humanoid: Humanoid,
	Root: BasePart,
	Head: BasePart,
	State: State,
	StateSince: number,
	HP: number,
	MaxHP: number,
	SpeedMult: number,
	Target: Player?,
	TargetSeenSince: number,
	LastSeenPos: Vector3?,
	LastSeenTime: number,
	Goal: Vector3?,
	Path: Path,
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	NextPlan: number,
	StuckSince: number,
	LastPos: Vector3,
	StunUntil: number,
	SlowUntil: number,
	Entry: World.Entry?,
	EntryStage: number, -- 0 идёт к входу, 1 ломает, 2 внутри
	EntryWorkUntil: number,
	KnockedAt: number,
	Tracks: { [string]: AnimationTrack },
	Voice: Sound?,
	Rng: Random,
	RoamRoom: string?,
	Hint: Vector3?, -- подсказка режиссёра (общая зона отряда)
	HintUntil: number,
	LookedAtBy: { [number]: boolean },
	LookPhase: string, -- RedLight: "Back" | "Look"
	LookUntil: number,
	SearchSpot: Model?,
	WaitAtSpotUntil: number,
	Relax: boolean,
	Lethal: boolean,
	Carrying: number,
	Despawned: boolean,
	LastStep: number,
	LastDetect: number,
	LastEventPos: Vector3?,
	RoomNameSentinel: string?,
	OnEvent: (string, Inmate, Vector3) -> (),
}, InmateAI))

local function now(): number
	return os.clock()
end

----------------------------------------------------------------------
-- Создание
----------------------------------------------------------------------
function InmateAI.new(def: Inmates.InmateDef, bodyIndex: number, spawnPos: Vector3, difficulty: Config.DifficultyDef, rng: Random, onEvent: (string, Inmate, Vector3) -> ()): Inmate
	local look = def.Look
	local model, parts, humanoid = R15Rig.build({
		Name = def.Id .. (if def.Bodies > 1 then "_" .. bodyIndex else ""),
		Scale = look.Scale,
		Body = look.Body,
		Head = look.Head,
		Accent = look.Accent,
		Material = look.Material,
	}, CFrame.new(spawnPos + Vector3.new(0, 3 * look.Scale.Y, 0)))
	R15Rig.addAccessory(look.Accessory, parts, look.Accent, look.Scale)
	R15Rig.addEyes(parts, if look.Glow then look.Accent else Color3.fromRGB(15, 12, 12), look.Scale, look.Glow)
	World.setCollisionGroup(model, World.COLLISION_INMATES)
	model:SetAttribute("InmateId", def.Id)
	model:SetAttribute("Kind", def.Kind)
	model:SetAttribute("State", "Enter")
	model:SetAttribute("Lethal", def.Lethal)
	model:SetAttribute("TargetUserId", 0)
	model:SetAttribute("Body", bodyIndex)

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 6,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 4,
		Costs = { Glass = 3 },
	})

	local self = setmetatable({
		Def = def,
		Id = def.Id,
		BodyIndex = bodyIndex,
		Model = model,
		Parts = parts,
		Humanoid = humanoid,
		Root = parts.HumanoidRootPart,
		Head = parts.Head,
		State = "Enter" :: State,
		StateSince = now(),
		HP = def.HP * difficulty.HpMult,
		MaxHP = def.HP * difficulty.HpMult,
		SpeedMult = difficulty.SpeedMult,
		Target = nil,
		TargetSeenSince = 0,
		LastSeenPos = nil,
		LastSeenTime = 0,
		Goal = nil,
		Path = path,
		Waypoints = {},
		WaypointIndex = 0,
		NextPlan = 0,
		StuckSince = 0,
		LastPos = spawnPos,
		StunUntil = 0,
		SlowUntil = 0,
		Entry = nil,
		EntryStage = 0,
		EntryWorkUntil = 0,
		KnockedAt = 0,
		Tracks = {},
		Voice = nil,
		Rng = rng,
		RoamRoom = nil,
		Hint = nil,
		HintUntil = 0,
		LookedAtBy = {},
		LookPhase = "Back",
		LookUntil = 0,
		SearchSpot = nil,
		WaitAtSpotUntil = 0,
		Relax = false,
		Lethal = def.Lethal,
		Carrying = 0,
		Despawned = false,
		LastStep = 0,
		LastDetect = 0,
		LastEventPos = nil,
		RoomNameSentinel = nil,
		OnEvent = onEvent,
	}, InmateAI) :: Inmate

	local folder = workspace:FindFirstChild("Inmates")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Inmates"
		folder.Parent = workspace
	end
	model.Parent = folder
	self.Root:SetNetworkOwner(nil)
	self:loadAnimations()
	if def.Sounds.Voice ~= "" then
		self.Voice = ServerSounds.loopOn(def.Sounds.Voice, self.Head, 0.55, 1, 90)
	end
	humanoid.WalkSpeed = def.RoamSpeed * difficulty.SpeedMult
	return self
end

function InmateAI.loadAnimations(self: Inmate)
	local animator = self.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local anims: { [string]: string } = { Walk = ANIM_WALK, Run = ANIM_RUN, Idle = ANIM_IDLE }
	for name, id in anims do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Movement
			track.Looped = true
			self.Tracks[name] = track
		end
	end
	self:playAnim("Idle")
end

function InmateAI.playAnim(self: Inmate, name: string)
	for n, track in self.Tracks do
		if n == name then
			if not track.IsPlaying then
				track:Play(0.25)
			end
		elseif track.IsPlaying then
			track:Stop(0.25)
		end
	end
end

function InmateAI.setState(self: Inmate, state: State)
	if self.State == state then
		return
	end
	self.State = state
	self.StateSince = now()
	self.Model:SetAttribute("State", state)
	self.Waypoints = {}
	self.WaypointIndex = 0
	self.NextPlan = 0
end

function InmateAI.position(self: Inmate): Vector3
	return self.Root.Position
end

function InmateAI.event(self: Inmate, kind: string)
	self.OnEvent(kind, self, self.Root.Position)
end

----------------------------------------------------------------------
-- Восприятие
----------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- Есть ли прямая видимость от глаз пациента до точки
function InmateAI.canSeePoint(self: Inmate, point: Vector3, exclude: { Instance }): boolean
	local eye = self.Head.Position
	local dir = point - eye
	if dir.Magnitude < 0.5 then
		return true
	end
	local list = { self.Model :: Instance }
	for _, e in exclude do
		table.insert(list, e)
	end
	local traps = workspace:FindFirstChild("Traps")
	if traps then
		table.insert(list, traps)
	end
	local inmates = workspace:FindFirstChild("Inmates")
	if inmates then
		table.insert(list, inmates)
	end
	rayParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(eye, dir, rayParams)
	if not hit then
		return true
	end
	-- стекло не мешает видеть
	if hit.Instance.Name == "Glass" and hit.Instance.Transparency > 0.3 then
		local rest = workspace:Raycast(hit.Position + dir.Unit * 0.2, point - (hit.Position + dir.Unit * 0.2), rayParams)
		return rest == nil
	end
	return false
end

-- Видит ли игрока (с учётом света, приседа, фонарика, угла обзора)
function InmateAI.canSeePlayer(self: Inmate, player: Player): boolean
	local rec = PlayerService.get(player)
	if not rec or rec.Status ~= "Alive" or not rec.InHouse then
		return false
	end
	local eye = PlayerService.eyePosition(player)
	local char = player.Character
	if not eye or not char then
		return false
	end
	local def = self.Def
	local dist = (eye - self.Head.Position).Magnitude
	local lit = HouseService.isPositionLit(eye)
	local range = if lit then def.SightLit else def.SightDark
	if self.Relax then
		range *= Config.Director.RelaxSightMult
	end
	if rec.Crouching then
		range *= Config.Vision.CrouchMult
	end
	-- фонарик, направленный на пациента, выдаёт игрока
	local revealed = false
	if rec.FlashlightOn and dist < Config.Flashlight.RevealDistance then
		local root = PlayerService.rootPart(player)
		if root then
			local toInmate = (self.Head.Position - root.Position).Unit
			if root.CFrame.LookVector:Dot(toInmate) > 0.6 then
				revealed = true
			end
		end
	end
	if dist > range and not revealed then
		return false
	end
	-- угол обзора
	local toPlayer = (eye - self.Head.Position)
	if toPlayer.Magnitude > 2 then
		local facing = self.Root.CFrame.LookVector
		if facing:Dot(toPlayer.Unit) < Config.Vision.FovCos and not revealed then
			return false
		end
	end
	return self:canSeePoint(eye, { char })
end

-- Лучший видимый игрок (ближайший)
function InmateAI.findVisibleTarget(self: Inmate): Player?
	local best: Player? = nil
	local bestDist = math.huge
	for _, player in Players:GetPlayers() do
		if self:canSeePlayer(player) then
			local root = PlayerService.rootPart(player)
			if root then
				local d = (root.Position - self.Root.Position).Magnitude
				if d < bestDist then
					best = player
					bestDist = d
				end
			end
		end
	end
	return best
end

function InmateAI.nearestAlivePlayer(self: Inmate): (Player?, number)
	local best: Player? = nil
	local bestDist = math.huge
	for _, player in Players:GetPlayers() do
		local rec = PlayerService.get(player)
		local root = PlayerService.rootPart(player)
		if rec and rec.InHouse and rec.Status == "Alive" and root then
			local d = (root.Position - self.Root.Position).Magnitude
			if d < bestDist then
				best = player
				bestDist = d
			end
		end
	end
	return best, bestDist
end

----------------------------------------------------------------------
-- Движение по пути
----------------------------------------------------------------------
function InmateAI.currentSpeed(self: Inmate): number
	local def = self.Def
	local base = def.RoamSpeed
	if self.State == "Chase" then
		base = def.ChaseSpeed
		if self.Target and now() - self.TargetSeenSince > Config.Vision.ChaseBoostAfter then
			base *= Config.Vision.ChaseBoost
		end
	elseif self.State == "Investigate" or self.State == "Search" then
		base = def.RoamSpeed * 1.25
	elseif self.State == "Retreat" then
		base = def.RoamSpeed * 1.5
	end
	if def.Kind == "StillOne" then
		base = if self:isWatched() then 0 else def.UnseenSpeed
	elseif def.Kind == "RedLight" then
		base = if self.LookPhase == "Look" then (if self.State == "Chase" then def.ChaseSpeed else 0) else def.RoamSpeed
	end
	if now() < self.SlowUntil then
		base *= 0.4
	end
	return base * self.SpeedMult
end

function InmateAI.planPath(self: Inmate, goal: Vector3): boolean
	local ok = pcall(function()
		self.Path:ComputeAsync(self.Root.Position, goal)
	end)
	if ok and self.Path.Status == Enum.PathStatus.Success then
		self.Waypoints = self.Path:GetWaypoints()
		self.WaypointIndex = 2
		self.Goal = goal
		return true
	end
	-- нет пути: идём напрямую
	self.Waypoints = { PathWaypoint.new(goal, Enum.PathWaypointAction.Walk) }
	self.WaypointIndex = 1
	self.Goal = goal
	return false
end

-- Идёт к цели; true, когда пришёл
function InmateAI.moveTowards(self: Inmate, goal: Vector3, arriveDist: number): boolean
	local t = now()
	local pos = self.Root.Position
	local flatDist = ((goal - pos) * Vector3.new(1, 0, 1)).Magnitude
	if flatDist <= arriveDist and math.abs(goal.Y - pos.Y) < 6 then
		self.Humanoid:MoveTo(pos)
		return true
	end
	local needPlan = t >= self.NextPlan or #self.Waypoints == 0 or (self.Goal and (self.Goal - goal).Magnitude > 6)
	if needPlan then
		self:planPath(goal)
		self.NextPlan = t + 0.8
	end
	local wp = self.Waypoints[self.WaypointIndex]
	if not wp then
		self.Humanoid:MoveTo(goal)
		return false
	end
	local toWp = (wp.Position - pos) * Vector3.new(1, 0, 1)
	if toWp.Magnitude < 2.2 then
		self.WaypointIndex += 1
		wp = self.Waypoints[self.WaypointIndex]
		if not wp then
			self.Humanoid:MoveTo(goal)
			return false
		end
	end
	self.Humanoid:MoveTo(wp.Position)
	-- застрял?
	if (pos - self.LastPos).Magnitude < 0.3 then
		if self.StuckSince == 0 then
			self.StuckSince = t
		elseif t - self.StuckSince > 1.5 then
			self.StuckSince = 0
			self.NextPlan = 0
			-- двери на пути: открыть ближайшую
			self:openNearbyDoor()
			-- маленький толчок вбок
			self.Root.CFrame = self.Root.CFrame * CFrame.new(self.Rng:NextNumber(-1, 1), 0, 0.5)
		end
	else
		self.StuckSince = 0
	end
	self.LastPos = pos
	return false
end

-- Открывает закрытую дверь рядом (пациенты открывают двери; запертые — ломают)
function InmateAI.openNearbyDoor(self: Inmate)
	local pos = self.Root.Position
	for id, d in HouseService.Doors do
		if not d.Open and (d.Panel.Position - pos).Magnitude < 5 then
			if d.Locked then
				if self.Def.BreaksInstantly then
					HouseService.breakLock(id)
				elseif not d.Breaking then
					d.Breaking = true
					ServerSounds.playOn("Pound", d.Panel, 0.9, 0.8, 140)
					task.delay(self.Def.LockBreakTime, function()
						d.Breaking = false
						if d.Locked and not self.Despawned and (d.Panel.Position - self.Root.Position).Magnitude < 8 then
							HouseService.breakLock(id)
						end
					end)
				end
			else
				HouseService.setDoorOpen(id, true, pos)
			end
			return
		end
	end
end

----------------------------------------------------------------------
-- Вход в дом
----------------------------------------------------------------------
function InmateAI.chooseEntry(self: Inmate)
	local entries = World.Entries
	if #entries == 0 then
		self.EntryStage = 2
		return
	end
	-- предпочитаем незаколоченные окна и незапертые двери, но не всегда
	local candidates: { World.Entry } = {}
	for _, e in entries do
		local weight = 1
		if e.Kind == "Window" then
			weight = 1 + HouseService.windowBoards(e.TargetId) * 0.5
		elseif HouseService.isDoorLocked(e.TargetId) then
			weight = 2
		end
		for _ = 1, math.max(1, math.floor(4 / weight)) do
			table.insert(candidates, e)
		end
	end
	self.Entry = candidates[self.Rng:NextInteger(1, #candidates)]
	self.EntryStage = 0
end

function InmateAI.updateEnter(self: Inmate)
	if not self.Entry then
		self:chooseEntry()
		if not self.Entry then
			self:setState("Roam")
			return
		end
	end
	local e = self.Entry :: World.Entry
	local t = now()
	if self.EntryStage == 0 then
		if self:moveTowards(e.Position, 3) then
			-- Стукач стучит и ждёт
			if self.Def.Kind == "Knocker" and self.KnockedAt == 0 then
				self.KnockedAt = t
				if e.Kind == "Door" then
					HouseService.knockDoor(e.TargetId)
				else
					HouseService.knockWindow(e.TargetId)
				end
				self:event("Knock")
				self.EntryWorkUntil = t + self.Def.KnockDelay
				self.EntryStage = 1
				return
			end
			self.EntryStage = 1
			self.EntryWorkUntil = t
		end
		return
	end
	if self.EntryStage == 1 then
		if t < self.EntryWorkUntil then
			self.Humanoid:MoveTo(self.Root.Position)
			return
		end
		if e.Kind == "Window" then
			local boards = HouseService.windowBoards(e.TargetId)
			if boards > 0 then
				if self.Def.BreaksInstantly then
					while HouseService.breakBoard(e.TargetId) do
					end
				else
					HouseService.breakBoard(e.TargetId)
					self.EntryWorkUntil = t + self.Def.BoardBreakTime
					return
				end
			end
			HouseService.breakGlass(e.TargetId)
		else
			if HouseService.isDoorLocked(e.TargetId) then
				if self.Def.BreaksInstantly then
					HouseService.breakLock(e.TargetId)
				else
					ServerSounds.playOn("Pound", self.Root, 0.9, 0.8, 140)
					self.EntryWorkUntil = t + self.Def.LockBreakTime
					self.EntryStage = 3
					return
				end
			else
				HouseService.setDoorOpen(e.TargetId, true, self.Root.Position)
			end
		end
		self.EntryStage = 2
		self:event("Enter")
		-- шаг внутрь: ближайшая точка обхода в комнате входа
		local inside = World.roomCenter(e.Room) or (e.Position + (World.roomCenter("Foyer") or Vector3.zero - e.Position).Unit * 6)
		self.Goal = nil
		self.Waypoints = {}
		self.Hint = inside
		self.HintUntil = t + 6
		self:setState(if self.Def.Kind == "Sentinel" then "Sentinel" else "Roam")
		return
	end
	if self.EntryStage == 3 then
		if t >= self.EntryWorkUntil then
			HouseService.breakLock(e.TargetId)
			self.EntryStage = 2
			self:event("Enter")
			self:setState("Roam")
		else
			self.Humanoid:MoveTo(self.Root.Position)
		end
	end
end

----------------------------------------------------------------------
-- Обход / расследование / погоня / поиск
----------------------------------------------------------------------
function InmateAI.pickRoamGoal(self: Inmate)
	local t = now()
	local def = self.Def
	-- Фонарщик идёт в освещённые комнаты
	if def.Kind == "Lamplighter" then
		local lit = HouseService.litRooms()
		if #lit > 0 then
			local room = lit[self.Rng:NextInteger(1, #lit)]
			local wps = World.waypointsInRoom(room)
			if #wps > 0 then
				self.RoamRoom = room
				self.Goal = wps[self.Rng:NextInteger(1, #wps)].Position
				return
			end
		end
	end
	-- подсказка режиссёра: общая зона отряда
	if self.Hint and t < self.HintUntil and self.Rng:NextNumber() < 0.7 then
		local wp = World.nearestWaypoint(self.Hint, 40)
		if wp then
			self.RoamRoom = wp.Room
			self.Goal = wp.Position
			return
		end
	end
	local wp = World.randomWaypoint(self.Rng, self.RoamRoom)
	if wp then
		self.RoamRoom = wp.Room
		self.Goal = wp.Position
	end
end

function InmateAI.updateRoam(self: Inmate)
	local def = self.Def
	if not self.Goal then
		self:pickRoamGoal()
		if not self.Goal then
			return
		end
	end
	local goal = self.Goal :: Vector3
	if self:moveTowards(goal, 3) then
		-- Фонарщик гасит свет в комнате, куда пришёл
		if def.Kind == "Lamplighter" and self.RoamRoom and HouseService.isLit(self.RoamRoom) then
			HouseService.flicker(self.RoamRoom, 1.2)
			local room = self.RoamRoom
			task.delay(1.2, function()
				if not self.Despawned then
					HouseService.setLight(room, false, nil, true)
					ServerSounds.playOn("Switch", self.Root, 0.6, 0.7, 60)
				end
			end)
		end
		-- иногда проверяет укрытие рядом
		self:maybeSearchHidingSpot(Config.Hiding.SearchChanceIdle)
		self.Goal = nil
	end
	self:playAnim("Walk")
end

function InmateAI.startChase(self: Inmate, target: Player)
	if self.Target ~= target then
		self.Target = target
		self.TargetSeenSince = now()
		self.Model:SetAttribute("TargetUserId", target.UserId)
		self:event("Spotted")
		Remotes.FX:FireClient(target, "Stinger", { InmateId = self.Id })
		PlayerService.addIntensity(target, Config.Director.Near)
	end
	self:setState("Chase")
end

function InmateAI.updateChase(self: Inmate)
	local target = self.Target
	if not target then
		self:setState("Search")
		return
	end
	local rec = PlayerService.get(target)
	local root = PlayerService.rootPart(target)
	if not rec or not root or rec.Status ~= "Alive" then
		-- цель спряталась или упала
		if rec and rec.Status == "Hiding" and rec.HideId then
			self:goCheckHidingSpot(rec.HideId, 1)
		else
			self.Target = nil
			self.Model:SetAttribute("TargetUserId", 0)
			self:setState("Search")
		end
		return
	end
	local t = now()
	if self:canSeePlayer(target) then
		self.LastSeenPos = root.Position
		self.LastSeenTime = t
	elseif t - self.LastSeenTime > Config.Vision.LoseSightAfter then
		self:event("Lost")
		self.Model:SetAttribute("TargetUserId", 0)
		self.Target = nil
		self:setState("Search")
		return
	end
	local goal = self.LastSeenPos or root.Position
	self:playAnim("Run")
	local dist = (root.Position - self.Root.Position).Magnitude
	if dist <= Config.Vision.CatchDistance + (self.Def.Look.Scale.X - 1) * 1.5 then
		self:catch(target)
		return
	end
	self:moveTowards(goal, 1.5)
	if t - self.LastDetect > 0.5 then
		self.LastDetect = t
		PlayerService.addIntensity(target, 4)
	end
	-- открыть дверь по пути
	self:openNearbyDoor()
end

function InmateAI.updateInvestigate(self: Inmate)
	local goal = self.Goal
	if not goal then
		self:setState("Roam")
		return
	end
	self:playAnim("Walk")
	if self:moveTowards(goal, 3) then
		self:maybeSearchHidingSpot(Config.Hiding.SearchChanceIdle * 2)
		self.Goal = nil
		self:setState("Search")
	end
end

function InmateAI.updateSearch(self: Inmate)
	local t = now()
	local spot = self.SearchSpot
	if spot then
		local hp = spot:FindFirstChild("HidePoint")
		local pos = if hp and hp:IsA("BasePart") then hp.Position else spot:GetPivot().Position
		self:playAnim("Walk")
		if self:moveTowards(pos, 4) then
			if self.WaitAtSpotUntil == 0 then
				self.WaitAtSpotUntil = t + (if self.Def.WaitAtHiding > 0 then self.Def.WaitAtHiding else 1.2)
				ServerSounds.playOn("Creak", self.Root, 0.7, 0.8, 50)
			elseif t >= self.WaitAtSpotUntil then
				-- открывает укрытие
				local occupant = PlayerService.occupantOf((spot:GetAttribute("HideId") :: string?) or "")
				if occupant then
					PlayerService.unhide(occupant, true)
					self:startChase(occupant)
				end
				self.SearchSpot = nil
				self.WaitAtSpotUntil = 0
				if not occupant then
					self:setState("Roam")
				end
			end
		end
		return
	end
	if not self.Goal and self.LastSeenPos then
		self.Goal = self.LastSeenPos
		self.LastSeenPos = nil
	end
	if self.Goal then
		self:playAnim("Walk")
		if self:moveTowards(self.Goal :: Vector3, 2.5) then
			self.Goal = nil
			self:maybeSearchHidingSpot(0.35)
		end
	elseif t - self.StateSince > 10 then
		self:setState("Roam")
	else
		-- осматривается: небольшая случайная точка рядом
		local wp = World.nearestWaypoint(self.Root.Position + Vector3.new(self.Rng:NextNumber(-8, 8), 0, self.Rng:NextNumber(-8, 8)), 14)
		if wp then
			self.Goal = wp.Position
		else
			self:setState("Roam")
		end
	end
end

-- Проверить укрытие рядом с шансом
function InmateAI.maybeSearchHidingSpot(self: Inmate, chance: number)
	if not self.Def.OpensHiding then
		return
	end
	local folder = World.houseFolder("HidingSpots")
	if not folder then
		return
	end
	local pos = self.Root.Position
	for _, spot in folder:GetChildren() do
		if spot:IsA("Model") then
			local hp = spot:FindFirstChild("HidePoint")
			local spos = if hp and hp:IsA("BasePart") then hp.Position else spot:GetPivot().Position
			if (spos - pos).Magnitude <= Config.Hiding.SearchRadius then
				local occupant = PlayerService.occupantOf((spot:GetAttribute("HideId") :: string?) or "")
				local p = chance
				if occupant then
					local escapes = PlayerService.escapesFrom(occupant, (spot:GetAttribute("HideId") :: string?) or "")
					if escapes >= 2 then
						p = math.max(p, Config.Hiding.SearchChanceAfterEscapes)
					end
				end
				if self.Rng:NextNumber() < p then
					self.SearchSpot = spot
					self.WaitAtSpotUntil = 0
					self:setState("Search")
					return
				end
			end
		end
	end
end

function InmateAI.goCheckHidingSpot(self: Inmate, hideId: string, chance: number)
	if not self.Def.OpensHiding then
		self.Target = nil
		self.Model:SetAttribute("TargetUserId", 0)
		self:setState("Search")
		return
	end
	if self.Rng:NextNumber() > chance then
		self.Target = nil
		self.Model:SetAttribute("TargetUserId", 0)
		self:setState("Search")
		return
	end
	local folder = World.houseFolder("HidingSpots")
	local spot = folder and folder:FindFirstChild(hideId)
	if spot and spot:IsA("Model") then
		self.SearchSpot = spot
		self.WaitAtSpotUntil = 0
		self.Target = nil
		self.Model:SetAttribute("TargetUserId", 0)
		self:setState("Search")
	end
end

----------------------------------------------------------------------
-- Поимка / урон / стан
----------------------------------------------------------------------
function InmateAI.catch(self: Inmate, target: Player)
	if not self.Lethal then
		return
	end
	PlayerService.down(target)
	self:event("Caught")
	self.Target = nil
	self.Model:SetAttribute("TargetUserId", 0)
	self.StunUntil = now() + Config.Downed.InmateCooldownAfterCatch
	self.LastSeenPos = nil
	self:setState("Search")
	local wp = World.randomWaypoint(self.Rng, World.roomNameAt(self.Root.Position))
	self.Goal = if wp then wp.Position else nil
end

function InmateAI.stun(self: Inmate, seconds: number, forget: boolean)
	if self.Def.StunImmune then
		return
	end
	self.StunUntil = math.max(self.StunUntil, now() + seconds)
	self.Humanoid:MoveTo(self.Root.Position)
	self:playAnim("Idle")
	ServerSounds.playOn("Growl", self.Root, 0.8, 1, 80)
	self:event("Stun")
	if forget then
		self.Target = nil
		self.Model:SetAttribute("TargetUserId", 0)
		self.LastSeenPos = nil
		self:setState("Search")
		self.Goal = nil
	end
	if self.Def.Kind == "Collector" and self.Carrying > 0 then
		self.Carrying = 0
		self:event("Drop")
	end
end

function InmateAI.damage(self: Inmate, amount: number, knockback: number, from: Vector3?): boolean
	self.HP -= amount
	if knockback > 0 and from then
		local dir = (self.Root.Position - from) * Vector3.new(1, 0, 1)
		if dir.Magnitude > 0.1 then
			self.Root.CFrame = self.Root.CFrame + dir.Unit * math.min(knockback * 0.25, 4)
		end
	end
	if self.HP <= 0 then
		self:event("Defeated")
		self:despawn()
		return true
	end
	return false
end

function InmateAI.isWatched(self: Inmate): boolean
	for _, v in self.LookedAtBy do
		if v then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Особые режимы
----------------------------------------------------------------------
function InmateAI.updateSentinel(self: Inmate)
	-- Веспер: сидит в комнате, "убивает" входящих
	local room = self.RoomNameSentinel or World.roomNameAt(self.Root.Position)
	self:playAnim("Idle")
	self.Humanoid:MoveTo(self.Root.Position)
	for _, player in Players:GetPlayers() do
		local rec = PlayerService.get(player)
		local root = PlayerService.rootPart(player)
		if rec and rec.InHouse and root and World.roomNameAt(root.Position) == room then
			if rec.Status == "Alive" then
				if (root.Position - self.Root.Position).Magnitude < 14 then
					self:catch(player)
					self:setState("Sentinel")
				end
			elseif rec.Status == "Hiding" and rec.HideId then
				-- спрятался в её комнате: вытаскивает
				PlayerService.unhide(player, true)
			end
		end
	end
end

function InmateAI.updateRedLight(self: Inmate)
	local t = now()
	local def = self.Def
	if t >= self.LookUntil then
		if self.LookPhase == "Back" then
			self.LookPhase = "Look"
			self.LookUntil = t + def.LookDuration
			self.Model:SetAttribute("Look", true)
			ServerSounds.playOn("Click", self.Head, 1, 1, 120)
			self:event("Look")
			local lens = self.Model:FindFirstChild("Lens")
			local beam = lens and lens:FindFirstChildOfClass("SpotLight")
			if beam then
				beam.Enabled = true
			end
			-- разворот к ближайшему игроку
			local p = self:nearestAlivePlayer()
			local root = p and PlayerService.rootPart(p)
			if root then
				local look = (root.Position - self.Root.Position) * Vector3.new(1, 0, 1)
				if look.Magnitude > 0.1 then
					self.Root.CFrame = CFrame.lookAt(self.Root.Position, self.Root.Position + look.Unit)
				end
			end
		else
			self.LookPhase = "Back"
			self.LookUntil = t + self.Rng:NextNumber(def.CycleMin, def.CycleMax)
			self.Model:SetAttribute("Look", false)
			local lens = self.Model:FindFirstChild("Lens")
			local beam = lens and lens:FindFirstChildOfClass("SpotLight")
			if beam then
				beam.Enabled = false
			end
			self.Target = nil
			self.Model:SetAttribute("TargetUserId", 0)
			self:setState("Roam")
		end
	end
	if self.LookPhase == "Look" then
		-- кто двигается в поле зрения — преследуется
		local state: State = self.State
		if state ~= "Chase" then
			self.Humanoid:MoveTo(self.Root.Position)
			self:playAnim("Idle")
			for _, player in Players:GetPlayers() do
				local root = PlayerService.rootPart(player)
				local rec = PlayerService.get(player)
				if root and rec and rec.Status == "Alive" and rec.InHouse and root.AssemblyLinearVelocity.Magnitude > 2 and self:canSeePlayer(player) then
					self:startChase(player)
					break
				end
			end
		else
			self:updateChase()
		end
	else
		self:updateRoam()
	end
end

function InmateAI.updateCollector(self: Inmate, lootAt: (Vector3) -> Vector3?, steal: (Vector3) -> boolean)
	if not self.Goal then
		local loot = lootAt(self.Root.Position)
		if loot then
			self.Goal = loot
		else
			self:pickRoamGoal()
		end
	end
	local goal = self.Goal
	if goal then
		self:playAnim("Walk")
		if self:moveTowards(goal, 3) then
			if steal(goal) then
				self.Carrying += 1
				ServerSounds.playOn("Keys", self.Root, 0.7, 1, 60)
				self:event("Steal")
			end
			self.Goal = nil
		end
	end
end

----------------------------------------------------------------------
-- Главный тик
----------------------------------------------------------------------
function InmateAI.update(self: Inmate, dt: number, ctx: { lootAt: (Vector3) -> Vector3?, steal: (Vector3) -> boolean })
	if self.Despawned then
		return
	end
	local t = now()
	local def = self.Def
	self.Humanoid.WalkSpeed = self:currentSpeed()
	-- датчики движения снаружи
	if World.isOutdoor(self.Root.Position) then
		HouseService.checkMotionLights(self.Root.Position)
	end
	if t < self.StunUntil then
		self.Humanoid.WalkSpeed = 0
		self.Humanoid:MoveTo(self.Root.Position)
		self:playAnim("Idle")
		return
	end
	local state: State = self.State
	if state == "Retreat" then
		self:playAnim("Walk")
		local exit = World.randomInmateSpawn(self.Rng)
		if self.Goal then
			exit = self.Goal :: Vector3
		else
			self.Goal = exit
		end
		if self:moveTowards(exit, 4) or t - self.StateSince > 25 then
			self:despawn()
		end
		return
	end
	if state == "Enter" then
		self:playAnim("Walk")
		self:updateEnter()
		return
	end
	if def.Kind == "Sentinel" then
		self:updateSentinel()
		return
	end
	if def.Kind == "Collector" then
		self:updateCollector(ctx.lootAt, ctx.steal)
		return
	end
	if def.Kind == "RedLight" then
		self:updateRedLight()
		return
	end
	if def.Kind == "StillOne" then
		if self:isWatched() then
			self.Humanoid:MoveTo(self.Root.Position)
			self:playAnim("Idle")
			self.Model:SetAttribute("Frozen", true)
			return
		end
		self.Model:SetAttribute("Frozen", false)
		-- без свидетелей: идёт к ближайшему игроку и ловит
		local p, dist = self:nearestAlivePlayer()
		if p then
			local root = PlayerService.rootPart(p)
			if root then
				if dist <= Config.Vision.CatchDistance + 1 then
					self:catch(p)
				else
					self:playAnim("Walk")
					self:moveTowards(root.Position, 1.5)
				end
			end
		else
			self:updateRoam()
		end
		return
	end
	-- Близнецы и Слепой: обычная машина, но с другим восприятием
	if state == "Chase" then
		self:updateChase()
		return
	end
	-- Восприятие: вижу?
	do
		local target = self:findVisibleTarget()
		if target then
			self:startChase(target)
			return
		end
	end
	-- Близнецы всегда знают общую зону
	if def.Kind == "Twins" and state == "Roam" and (not self.Goal or t - self.StateSince > 6) then
		local p = self:nearestAlivePlayer()
		local root = p and PlayerService.rootPart(p)
		if root then
			local wp = World.nearestWaypoint(root.Position, 30)
			if wp then
				self.Goal = wp.Position
			end
		end
	end
	if state == "Roam" then
		self:updateRoam()
	elseif state == "Investigate" then
		self:updateInvestigate()
	elseif state == "Search" then
		self:updateSearch()
	end
end

-- Шум: идти проверять, если слышно
function InmateAI.onNoise(self: Inmate, noise: NoiseService.Noise)
	local state: State = self.State
	if self.Despawned or state == "Enter" or state == "Retreat" or self.Def.Kind == "Sentinel" or self.Def.Kind == "StillOne" then
		return
	end
	local hear = self.Def.HearRange
	if self.Relax then
		hear *= Config.Director.RelaxHearMult
	end
	local dist = (noise.Position - self.Root.Position).Magnitude
	if dist > noise.Radius + hear then
		return
	end
	if state == "Chase" then
		return
	end
	-- Слепой: громкий шум рядом — сразу "погоня" к точке
	if self.Def.Kind == "Blind" and noise.Player and dist < noise.Radius * 0.6 then
		local rec = PlayerService.get(noise.Player)
		if rec and rec.Status == "Alive" then
			self.LastSeenPos = noise.Position
			self.LastSeenTime = now()
			self:startChase(noise.Player)
			return
		end
	end
	self.Goal = noise.Position
	self:setState("Investigate")
	if noise.Player then
		PlayerService.addIntensity(noise.Player, Config.Director.Heard)
	end
end

function InmateAI.retreat(self: Inmate)
	if self.Despawned then
		return
	end
	self.Target = nil
	self.Model:SetAttribute("TargetUserId", 0)
	self.SearchSpot = nil
	self.Goal = nil
	self:event("Retreat")
	self:setState("Retreat")
end

function InmateAI.despawn(self: Inmate)
	if self.Despawned then
		return
	end
	self.Despawned = true
	self:setState("Gone")
	if self.Voice then
		self.Voice:Destroy()
		self.Voice = nil
	end
	self.Model:Destroy()
end

return InmateAI
