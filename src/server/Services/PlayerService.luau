--!strict
-- Состояние игроков в матче: жив / повален / забран / в укрытии / наблюдает / в лобби.
-- Падение и реанимация, укрытия и дыхание, фонарик (заряд), присед, античит по скорости, спавн в лобби и в доме.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local World = require(script.Parent:WaitForChild("World"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ServerSounds = require(script.Parent:WaitForChild("ServerSounds"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local PlayerService = {}

export type Status = "Alive" | "Downed" | "Taken" | "Hiding" | "Spectating" | "Lobby"

export type Record = {
	Player: Player,
	Status: Status,
	InHouse: boolean,
	Crouching: boolean,
	Sprinting: boolean,
	FlashlightOn: boolean,
	Battery: number,
	HideId: string?,
	HideEnteredAt: number,
	HideLockUntil: number,
	Breath: number,
	HoldingBreath: boolean,
	HoldStartedAt: number,
	HoldCooldownUntil: number,
	DownedUntil: number,
	RevivePrompt: ProximityPrompt?,
	LastPos: Vector3?,
	LastPosTime: number,
	TeleportGraceUntil: number,
	EscapesFromHide: { [string]: number },
	Intensity: number,
	LastBreathSent: number,
	Light: SpotLight?,
}

PlayerService.StatusChanged = Signal.new() :: Signal.Signal<Player, Status, Status>
PlayerService.Downed = Signal.new() :: Signal.Signal<Player>
PlayerService.Taken = Signal.new() :: Signal.Signal<Player>
PlayerService.Revived = Signal.new() :: Signal.Signal<Player, Player?>
PlayerService.Hid = Signal.new() :: Signal.Signal<Player, string, boolean> -- player, hideId, seenByInmate (заполняет InmateService через флаг)
PlayerService.Unhid = Signal.new() :: Signal.Signal<Player, string, boolean> -- forced

local records: { [Player]: Record } = {}
-- Точки укрытий/спавнов лежат на полу; центр персонажа (HumanoidRootPart) — на ~3 стада выше.
local CHAR_LIFT = Vector3.new(0, 3, 0)
-- Заполняется InmateService: расстояние до ближайшего смертельного пациента для дыхания
PlayerService.nearestLethalDistance = function(_position: Vector3): number
	return math.huge
end :: (Vector3) -> number
-- Заполняется InmateService: видел ли кто-то из пациентов игрока в момент пряток
PlayerService.isWatched = function(_player: Player): boolean
	return false
end :: (Player) -> boolean
-- Заполняется RoundService: идёт ли матч и ночь ли сейчас
PlayerService.isMatchRunning = function(): boolean
	return false
end :: () -> boolean
PlayerService.isNight = function(): boolean
	return false
end :: () -> boolean

local function newRecord(player: Player): Record
	return {
		Player = player,
		Status = "Lobby",
		InHouse = false,
		Crouching = false,
		Sprinting = false,
		FlashlightOn = false,
		Battery = Config.Flashlight.Battery,
		HideId = nil,
		HideEnteredAt = 0,
		HideLockUntil = 0,
		Breath = Config.Hiding.BreathMax,
		HoldingBreath = false,
		HoldStartedAt = 0,
		HoldCooldownUntil = 0,
		DownedUntil = 0,
		RevivePrompt = nil,
		LastPos = nil,
		LastPosTime = 0,
		TeleportGraceUntil = 0,
		EscapesFromHide = {},
		Intensity = 0,
		LastBreathSent = 0,
		Light = nil,
	}
end

function PlayerService.get(player: Player): Record?
	return records[player]
end

function PlayerService.all(): { Record }
	local list = {}
	for _, r in records do
		table.insert(list, r)
	end
	return list
end

-- Живые = Alive или Hiding
function PlayerService.isAlive(r: Record): boolean
	return r.Status == "Alive" or r.Status == "Hiding"
end

function PlayerService.aliveCount(): number
	local n = 0
	for _, r in records do
		if PlayerService.isAlive(r) then
			n += 1
		end
	end
	return n
end

function PlayerService.inHouseCount(): number
	local n = 0
	for _, r in records do
		if r.InHouse and (PlayerService.isAlive(r) or r.Status == "Downed") then
			n += 1
		end
	end
	return n
end

local function character(player: Player): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return char, hum, if root and root:IsA("BasePart") then root else nil
end

function PlayerService.rootPart(player: Player): BasePart?
	local _, _, root = character(player)
	return root
end

-- Позиция "головы" для проверки видимости (ниже при приседе)
function PlayerService.eyePosition(player: Player): Vector3?
	local char, _, root = character(player)
	if not char or not root then
		return nil
	end
	local head = char:FindFirstChild("Head")
	local pos = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local r = records[player]
	if r and r.Crouching then
		pos -= Vector3.new(0, Config.Movement.CrouchHeadDrop, 0)
	end
	return pos
end

local function applySpeed(r: Record)
	local _, hum = character(r.Player)
	if not hum then
		return
	end
	if r.Status == "Hiding" or r.Status == "Downed" then
		hum.WalkSpeed = 0
	elseif r.Crouching then
		hum.WalkSpeed = Config.Movement.CrouchSpeed
	elseif r.Sprinting then
		hum.WalkSpeed = Config.Movement.SprintSpeed
	else
		hum.WalkSpeed = Config.Movement.WalkSpeed
	end
end

local function replicateState(r: Record)
	Remotes.PlayerState:FireClient(r.Player, r.Status, r.HideId)
end

function PlayerService.setStatus(player: Player, status: Status, hideId: string?)
	local r = records[player]
	if not r then
		return
	end
	local old = r.Status
	r.Status = status
	r.HideId = hideId
	player:SetAttribute("Status", status)
	if status ~= "Alive" then
		if r.FlashlightOn then
			PlayerService.setFlashlight(player, false)
		end
		r.Crouching = false
		r.Sprinting = false
		r.HoldingBreath = false
	end
	applySpeed(r)
	replicateState(r)
	if old ~= status then
		PlayerService.StatusChanged:Fire(player, old, status)
	end
end

local function replicateInventoryBattery(r: Record)
	-- Инвентарь шлёт ItemService; здесь только заряд через тот же канал — ItemService подписан на этот сигнал
	PlayerService.BatteryChanged:Fire(r.Player, r.Battery)
end
PlayerService.BatteryChanged = Signal.new() :: Signal.Signal<Player, number>

local function ensureLight(r: Record): SpotLight?
	local char = r.Player.Character
	if not char then
		return nil
	end
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local light = head:FindFirstChild("Flashlight")
	if light and light:IsA("SpotLight") then
		r.Light = light
		return light
	end
	local l = Instance.new("SpotLight")
	l.Name = "Flashlight"
	l.Face = Enum.NormalId.Front
	l.Angle = Config.Flashlight.Angle
	l.Range = Config.Flashlight.Range * 0.8
	l.Brightness = Config.Flashlight.Brightness * 0.8
	l.Shadows = false
	l.Enabled = false
	l.Color = Color3.fromRGB(255, 240, 205)
	l.Parent = head
	r.Light = l
	return l
end

function PlayerService.setFlashlight(player: Player, on: boolean)
	local r = records[player]
	if not r then
		return
	end
	if on and (r.Status ~= "Alive" or r.Battery <= 0) then
		on = false
	end
	r.FlashlightOn = on
	local light = ensureLight(r)
	if light then
		light.Enabled = on
	end
	local char = player.Character
	if char then
		char:SetAttribute("Flashlight", on)
	end
end

function PlayerService.setCrouch(player: Player, on: boolean)
	local r = records[player]
	if not r then
		return
	end
	r.Crouching = on and r.Status == "Alive"
	local char = player.Character
	if char then
		char:SetAttribute("Crouching", r.Crouching)
	end
	applySpeed(r)
end

function PlayerService.setSprint(player: Player, on: boolean)
	local r = records[player]
	if not r then
		return
	end
	r.Sprinting = on and r.Status == "Alive"
	applySpeed(r)
end

----------------------------------------------------------------------
-- Спавн и телепорт
----------------------------------------------------------------------
local function teleport(r: Record, cframe: CFrame)
	local char = r.Player.Character
	if not char then
		return
	end
	r.TeleportGraceUntil = os.clock() + 2
	r.LastPos = nil
	char:PivotTo(cframe)
end

function PlayerService.spawnInLobby(player: Player, index: number?)
	local r = records[player]
	if not r then
		return
	end
	r.InHouse = false
	r.HideId = nil
	teleport(r, World.lobbySpawn(index or 1))
	PlayerService.setStatus(player, "Lobby")
end

function PlayerService.spawnInHouse(player: Player, index: number)
	local r = records[player]
	if not r then
		return
	end
	r.InHouse = true
	r.Battery = Config.Flashlight.Battery
	r.Breath = Config.Hiding.BreathMax
	r.HideLockUntil = 0
	r.EscapesFromHide = {}
	r.Intensity = 0
	teleport(r, World.playerSpawn(index))
	PlayerService.setStatus(player, "Alive")
	replicateInventoryBattery(r)
end

-- Забранный/опоздавший наблюдает из лобби
function PlayerService.spectate(player: Player)
	local r = records[player]
	if not r then
		return
	end
	r.InHouse = false
	teleport(r, World.lobbySpawn(1))
	PlayerService.setStatus(player, "Spectating")
end

----------------------------------------------------------------------
-- Падение / реанимация / забран
----------------------------------------------------------------------
local function removeRevivePrompt(r: Record)
	if r.RevivePrompt then
		r.RevivePrompt:Destroy()
		r.RevivePrompt = nil
	end
end

local function teamMedicBonus(): number
	local best = 0
	for _, other in records do
		if PlayerService.isAlive(other) then
			local v = DataService.perkValue(other.Player, "Medic")
			if v > 0 then
				-- Values = секунды реанимации (3 / 2.5 / 2)
				best = math.max(best, Config.Downed.ReviveHold - v)
			end
		end
	end
	return best
end

local function createRevivePrompt(r: Record)
	removeRevivePrompt(r)
	local _, _, root = character(r.Player)
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive"
	prompt.ObjectText = r.Player.DisplayName
	prompt.HoldDuration = math.max(1, Config.Downed.ReviveHold - teamMedicBonus())
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = root
	prompt.Triggered:Connect(function(by: Player)
		if by == r.Player then
			return
		end
		local byRec = records[by]
		if not byRec or byRec.Status ~= "Alive" then
			return
		end
		PlayerService.revive(r.Player, by)
	end)
	r.RevivePrompt = prompt
end

function PlayerService.down(player: Player)
	local r = records[player]
	if not r or not PlayerService.isAlive(r) then
		return
	end
	if r.Status == "Hiding" and r.HideId then
		PlayerService.unhide(player, true, true)
	end
	r.DownedUntil = os.clock() + Config.Downed.Duration
	r.Intensity = math.min(100, r.Intensity + Config.Director.Downed)
	PlayerService.setStatus(player, "Downed")
	local _, hum = character(player)
	if hum then
		hum.Sit = true
	end
	createRevivePrompt(r)
	Remotes.FX:FireClient(player, "Caught", nil)
	NoiseService.emit(PlayerService.rootPart(player) and (PlayerService.rootPart(player) :: BasePart).Position or Vector3.zero, "Fall", player)
	PlayerService.Downed:Fire(player)
end

function PlayerService.revive(player: Player, by: Player?)
	local r = records[player]
	if not r or r.Status ~= "Downed" then
		return
	end
	removeRevivePrompt(r)
	local _, hum = character(player)
	if hum then
		hum.Sit = false
	end
	PlayerService.setStatus(player, "Alive")
	Remotes.FX:FireClient(player, "Revived", nil)
	if by then
		Remotes.Notify:FireClient(player, "N_Revived", "success", { by.DisplayName })
		Remotes.Notify:FireClient(by, "N_YouRevived", "success", { player.DisplayName })
	end
	local root = PlayerService.rootPart(player)
	if root then
		NoiseService.emit(root.Position, "Revive", player)
	end
	PlayerService.Revived:Fire(player, by)
end

function PlayerService.take(player: Player)
	local r = records[player]
	if not r or r.Status ~= "Downed" then
		return
	end
	removeRevivePrompt(r)
	local _, hum = character(player)
	if hum then
		hum.Sit = false
	end
	r.InHouse = false
	teleport(r, World.lobbySpawn(1))
	PlayerService.setStatus(player, "Taken")
	PlayerService.Taken:Fire(player)
end

----------------------------------------------------------------------
-- Укрытия
----------------------------------------------------------------------
local function hidingSpot(hideId: string): Model?
	local folder = World.houseFolder("HidingSpots")
	if not folder then
		return nil
	end
	local m = folder:FindFirstChild(hideId)
	return if m and m:IsA("Model") then m else nil
end

function PlayerService.hidingSpotOf(player: Player): Model?
	local r = records[player]
	if not r or not r.HideId then
		return nil
	end
	return hidingSpot(r.HideId)
end

function PlayerService.occupantOf(hideId: string): Player?
	for _, r in records do
		if r.Status == "Hiding" and r.HideId == hideId then
			return r.Player
		end
	end
	return nil
end

function PlayerService.hide(player: Player, hideId: string): boolean
	local r = records[player]
	if not r or r.Status ~= "Alive" then
		return false
	end
	local now = os.clock()
	if now < r.HideLockUntil then
		Remotes.Notify:FireClient(player, "N_HideBlocked", "warning")
		return false
	end
	local spot = hidingSpot(hideId)
	if not spot then
		return false
	end
	if PlayerService.occupantOf(hideId) then
		return false
	end
	local hidePoint = spot:FindFirstChild("HidePoint")
	local root = PlayerService.rootPart(player)
	if not hidePoint or not hidePoint:IsA("BasePart") or not root then
		return false
	end
	if (hidePoint.Position - root.Position).Magnitude > 14 then
		Remotes.Notify:FireClient(player, "N_TooFar", "warning")
		return false
	end
	local watched = PlayerService.isWatched(player)
	r.HideEnteredAt = now
	r.Breath = Config.Hiding.BreathMax
	r.HoldingBreath = false
	r.HoldCooldownUntil = 0
	teleport(r, hidePoint.CFrame + CHAR_LIFT)
	spot:SetAttribute("Occupied", player.Name)
	PlayerService.setStatus(player, "Hiding", hideId)
	Remotes.Breath:FireClient(player, r.Breath)
	ServerSounds.playOn("DoorClose", hidePoint, 0.5, 1.1)
	PlayerService.Hid:Fire(player, hideId, watched)
	return true
end

function PlayerService.unhide(player: Player, forced: boolean, silent: boolean?): boolean
	local r = records[player]
	if not r or r.Status ~= "Hiding" or not r.HideId then
		return false
	end
	local hideId = r.HideId
	local spot = hidingSpot(hideId)
	if spot then
		spot:SetAttribute("Occupied", "")
		local hidePoint = spot:FindFirstChild("HidePoint")
		local cam = spot:FindFirstChild("CamPoint")
		if hidePoint and hidePoint:IsA("BasePart") then
			local look = if cam and cam:IsA("BasePart") then cam.CFrame.LookVector else hidePoint.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude < 0.01 then
				flat = Vector3.new(0, 0, -1)
			end
			flat = flat.Unit
			local exit = CFrame.lookAt(hidePoint.Position + flat * 3 + CHAR_LIFT, hidePoint.Position + flat * 6 + CHAR_LIFT)
			teleport(r, exit)
		end
		if not silent then
			ServerSounds.playOn("DoorOpen", spot, 0.5, 1.1)
		end
	end
	r.HideLockUntil = os.clock() + Config.Hiding.ReenterLock
	if forced then
		r.EscapesFromHide[hideId] = (r.EscapesFromHide[hideId] or 0) + 1
	end
	PlayerService.setStatus(player, "Alive")
	if forced and not silent then
		local root = PlayerService.rootPart(player)
		if root then
			NoiseService.emit(root.Position, "Gasp", player)
			ServerSounds.playOn("Gasp", root, 0.8)
		end
	end
	PlayerService.Unhid:Fire(player, hideId, forced)
	return true
end

function PlayerService.escapesFrom(player: Player, hideId: string): number
	local r = records[player]
	return if r then (r.EscapesFromHide[hideId] or 0) else 0
end

----------------------------------------------------------------------
-- Тик: батарея, дыхание, повал, античит
----------------------------------------------------------------------
local function tick(dt: number)
	local now = os.clock()
	for player, r in records do
		local char, hum, root = character(player)
		if not char or not hum or not root then
			continue
		end
		-- Падение сквозь карту
		if root.Position.Y < Config.Map.KillY then
			teleport(r, if r.InHouse then World.playerSpawn(1) else World.lobbySpawn(1))
		end
		-- Батарея
		if r.FlashlightOn then
			r.Battery = math.max(0, r.Battery - dt)
			if r.Battery <= 0 then
				PlayerService.setFlashlight(player, false)
				replicateInventoryBattery(r)
			end
		end
		-- Повал
		if r.Status == "Downed" and now >= r.DownedUntil then
			PlayerService.take(player)
		end
		-- Дыхание в укрытии
		if r.Status == "Hiding" then
			local near = PlayerService.nearestLethalDistance(root.Position) <= Config.Hiding.NearDistance
			if r.HoldingBreath and now - r.HoldStartedAt > Config.Hiding.HoldSeconds then
				r.HoldingBreath = false
				r.HoldCooldownUntil = now + Config.Hiding.HoldCooldown
			end
			if near and not r.HoldingBreath then
				r.Breath -= Config.Hiding.BreathDrainNear * dt
			elseif not near then
				r.Breath = math.min(Config.Hiding.BreathMax, r.Breath + Config.Hiding.BreathRegen * dt)
			end
			if r.Breath <= 0 then
				r.Breath = 0
				PlayerService.unhide(player, true)
			elseif now - r.LastBreathSent > 0.2 then
				r.LastBreathSent = now
				Remotes.Breath:FireClient(player, r.Breath)
			end
		end
		-- Античит по скорости (только в доме)
		if r.InHouse and r.Status == "Alive" and now > r.TeleportGraceUntil then
			local last = r.LastPos
			if last and r.LastPosTime > 0 then
				local elapsed = now - r.LastPosTime
				if elapsed > 0.2 then
					local flat = (root.Position - last) * Vector3.new(1, 0, 1)
					local speed = flat.Magnitude / elapsed
					if speed > Config.Movement.MaxLegalSpeed then
						root.CFrame = CFrame.new(last) * (root.CFrame - root.CFrame.Position)
						root.AssemblyLinearVelocity = Vector3.zero
					else
						r.LastPos = root.Position
					end
					r.LastPosTime = now
				end
			else
				r.LastPos = root.Position
				r.LastPosTime = now
			end
		else
			r.LastPos = root.Position
			r.LastPosTime = now
		end
		-- Интенсивность (режиссёр) спадает без контакта
		if r.Intensity > 0 then
			r.Intensity = math.max(0, r.Intensity - Config.Director.Decay * dt)
		end
	end
end

----------------------------------------------------------------------
-- Персонажи
----------------------------------------------------------------------
local function onCharacter(player: Player, char: Model)
	local r = records[player]
	if not r then
		return
	end
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.AutoRotate = true
	World.setCollisionGroup(char, World.COLLISION_PLAYERS)
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = World.COLLISION_PLAYERS
		end
	end)
	ensureLight(r)
	r.Light = nil
	r.FlashlightOn = false
	r.Crouching = false
	r.Sprinting = false
	r.LastPos = nil
	-- Куда поставить персонажа после (ре)спавна
	task.defer(function()
		if r.InHouse and PlayerService.isMatchRunning() then
			r.TeleportGraceUntil = os.clock() + 2
			char:PivotTo(World.playerSpawn(1))
			if r.Status == "Hiding" then
				PlayerService.setStatus(player, "Alive")
			end
		else
			r.TeleportGraceUntil = os.clock() + 2
			char:PivotTo(World.lobbySpawn(1))
			if r.Status ~= "Spectating" and r.Status ~= "Taken" then
				PlayerService.setStatus(player, "Lobby")
			end
		end
		applySpeed(r)
		replicateState(r)
	end)
	hum.Died:Connect(function()
		-- Смерть персонажа (например, застрял): повал не нужен, просто респавн
		if r.Status == "Hiding" and r.HideId then
			PlayerService.unhide(player, false, true)
		end
		if r.Status == "Downed" then
			removeRevivePrompt(r)
			r.Status = "Alive"
		end
	end)
end

local function onPlayerAdded(player: Player)
	records[player] = newRecord(player)
	player:SetAttribute("Status", "Lobby")
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local r = records[player]
	if r then
		if r.Status == "Hiding" and r.HideId then
			local spot = hidingSpot(r.HideId)
			if spot then
				spot:SetAttribute("Occupied", "")
			end
		end
		removeRevivePrompt(r)
	end
	records[player] = nil
end

function PlayerService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	Remotes.SetFlashlight.OnServerEvent:Connect(function(player, on)
		if typeof(on) == "boolean" then
			PlayerService.setFlashlight(player, on)
		end
	end)
	Remotes.SetCrouch.OnServerEvent:Connect(function(player, on)
		if typeof(on) == "boolean" then
			PlayerService.setCrouch(player, on)
		end
	end)
	Remotes.SetSprint.OnServerEvent:Connect(function(player, on)
		if typeof(on) == "boolean" then
			PlayerService.setSprint(player, on)
		end
	end)
	Remotes.HoldBreath.OnServerEvent:Connect(function(player, on)
		local r = records[player]
		if not r or r.Status ~= "Hiding" or typeof(on) ~= "boolean" then
			return
		end
		local now = os.clock()
		if on then
			if now >= r.HoldCooldownUntil and not r.HoldingBreath then
				r.HoldingBreath = true
				r.HoldStartedAt = now
			end
		elseif r.HoldingBreath then
			r.HoldingBreath = false
			r.HoldCooldownUntil = now + Config.Hiding.HoldCooldown * 0.5
		end
	end)
	Remotes.Interact.OnServerEvent:Connect(function(player, kind, _id)
		if kind == "Unhide" then
			PlayerService.unhide(player, false)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			local step = acc
			acc = 0
			tick(step)
		end
	end)
end

-- Сброс к лобби (конец матча)
function PlayerService.resetAllToLobby()
	local i = 0
	for player, r in records do
		i += 1
		removeRevivePrompt(r)
		if r.Status == "Hiding" and r.HideId then
			PlayerService.unhide(player, false, true)
		end
		local _, hum = character(player)
		if hum then
			hum.Sit = false
		end
		PlayerService.spawnInLobby(player, i)
	end
end

function PlayerService.battery(player: Player): number
	local r = records[player]
	return if r then r.Battery else 0
end

function PlayerService.setBattery(player: Player, value: number)
	local r = records[player]
	if r then
		r.Battery = math.clamp(value, 0, Config.Flashlight.Battery)
		replicateInventoryBattery(r)
	end
end

function PlayerService.addIntensity(player: Player, amount: number)
	local r = records[player]
	if r then
		r.Intensity = math.clamp(r.Intensity + amount, 0, 100)
	end
end

function PlayerService.maxIntensity(): number
	local m = 0
	for _, r in records do
		if r.InHouse then
			m = math.max(m, r.Intensity)
		end
	end
	return m
end

return PlayerService
