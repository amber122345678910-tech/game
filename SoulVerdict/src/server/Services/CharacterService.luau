--!strict
-- CharacterService (P20): every character in the game goes through here (players, practice bots, dummies).
-- Players.CharacterAutoLoads is false: this service builds rigs (Rigs/RigBuilder), sets the SPEC §4.1
-- attributes, places/parents them, owns the downed -> revive / bleed-out -> death lifecycle, lobby bodies
-- (incl. TryKit) and the character collision groups. Never yields inside the public API.
--
-- API (SPEC §17)
--   SpawnPlayer(player, kitId, cframe, opts {Team, SkinId?, MaxHealth?}) -> Model
--   SpawnBot(kitId, cframe, opts {Team, Name?, SkinId?, MaxHealth?, Blueprint?}) -> Model
--   SpawnLobby(player, kitOverride?, atCFrame?) -> Model?       lobby body with the equipped human kit
--   Despawn(model), DespawnTeam(team)
--   GetPlayer(model) -> Player?, GetModel(player) -> Model?, GetKit(model) -> KitDef?, GetTeam(model) -> string?
--   IsAlive(model) (not Dead; Downed counts as alive), IsUp(model) (alive and not Downed)
--   GetAll(team?, includeDead?) -> {Model}                       dead bodies (death VFX window) excluded by default
--   SetDowned(model, attacker?), Kill(model, attacker?, ability?), Revive(model, by?) -> boolean
--   EquippedKit(player, role) -> string, EquippedSkin(player, kitId) -> string, RefreshLobby(player)
--   Signals: Spawned(model, player?), Died(model, killer?, ability?), Downed(model, attacker?),
--            Revived(model, by?), Despawning(model)  [fired just before a model is destroyed]
-- Spawn CFrames are GROUND points (feet), only their yaw is used. Kill "ability" values used by this
-- service: "Void" (fell below the map's KillY), "BleedOut" (downed timer ran out).
-- Requests registered: "TryKit" (data: kitId string or {kitId}; "" / nil clears the override).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove")) :: any

local CharacterService = {}
CharacterService.Priority = 20

CharacterService.Spawned = Signal.new()
CharacterService.Died = Signal.new()
CharacterService.Downed = Signal.new()
CharacterService.Revived = Signal.new()
CharacterService.Despawning = Signal.new()

local DEATH_BODY_TIME = 2.5 -- body stays for the SOUL shatter / dust VFX
local REVIVE_DISTANCE = 9
local REVIVE_IFRAMES = 1.5
local DEFAULT_KILL_Y = -200
local DUMMY_HEALTH = 5000
local CHARACTER_GROUP: string = Config.CollisionGroups.Characters

export type SpawnOpts = {
	Team: string?,
	SkinId: string?,
	MaxHealth: number?,
	Name: string?,
	Blueprint: string?,
}

type Record = {
	Model: Model,
	Player: Player?,
	Kit: any,
	KitId: string,
	Team: string,
	Humanoid: Humanoid,
	Root: BasePart,
	Trove: any,
	Token: number, -- bumped to cancel pending downed/bleed-out threads
	Prompt: ProximityPrompt?,
	LastAttacker: Model?,
	Dead: boolean,
	Despawning: boolean,
	IsBot: boolean,
	DisplayName: string,
	SpawnCFrame: CFrame,
}

-- Other services (resolved in Init; any of them may be missing while the game is being built)
local MapService: any = nil
local DataService: any = nil
local StatusService: any = nil
local RequestService: any = nil
local DamageService: any = nil

local records: { [Model]: Record } = {}
local byPlayer: { [Player]: Model } = {}
local tryKits: { [Player]: string } = {}
local playerTroves: { [Player]: any } = {}
local refreshPending: { [Player]: boolean } = {}
local botCounter = 0
local rigBuilder: any = nil
local rigBuilderResolved = false
local spawnRandom = Random.new()

-- Helpers ------------------------------------------------------------------------------------------

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
		warn(("[CharacterService] could not use %s: %s"):format(name, tostring(result)))
	end
	return nil
end

-- Calls service[method](...) if it exists; never throws.
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
		warn(("[CharacterService] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
end

-- DamageService is the single writer of Health during play; use its helper when it exists.
local function setHealth(model: Model, humanoid: Humanoid, hp: number)
	local ok = call(DamageService, "SetHealth", model, hp)
	if not ok then
		humanoid.Health = math.clamp(hp, 0, humanoid.MaxHealth)
	end
end

local function notify(player: Player?, key: string, args: { any }?, style: string?)
	if player and player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

local function roundState(): Instance?
	return ReplicatedStorage:FindFirstChild("RoundState")
end

local function revivesLeft(): number?
	local rs = roundState()
	if rs == nil then
		return nil
	end
	local v = rs:GetAttribute("TeamRevives")
	return if type(v) == "number" then v else nil
end

local function roleForTeam(team: string): string
	if team == "Humans" then
		return "Human"
	elseif team == "Monster" then
		return "Monster"
	end
	return "Lobby"
end

local function getRigBuilder(): any
	if not rigBuilderResolved then
		rigBuilderResolved = true
		local rigs = Shared:FindFirstChild("Rigs")
		local module = rigs and rigs:FindFirstChild("RigBuilder")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" and type((result :: any).Build) == "function" then
				rigBuilder = result
			else
				warn("[CharacterService] RigBuilder failed to load, using fallback rigs: " .. tostring(result))
			end
		else
			warn("[CharacterService] Rigs/RigBuilder missing, using fallback rigs")
		end
	end
	return rigBuilder
end

local function validRig(model: any): boolean
	return typeof(model) == "Instance"
		and model:IsA("Model")
		and model:FindFirstChild("HumanoidRootPart") ~= nil
		and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Minimal emergency rig (only used when RigBuilder is unavailable or broken).
local function buildFallbackRig(name: string, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	local function part(partName: string, size: Vector3, cf: CFrame, visible: boolean, collide: boolean): Part
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = if visible then 0 else 1
		p.CanCollide = collide
		p.Anchored = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), false, false)
	local lower = part("LowerTorso", Vector3.new(1.8, 0.8, 1), CFrame.new(0, 2.4, 0), true, true)
	local upper = part("UpperTorso", Vector3.new(2, 1.6, 1), CFrame.new(0, 3.6, 0), true, true)
	local head = part("Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 5.05, 0), true, true)
	head.Color = Color3.new(1, 1, 1)
	local legs = part("Legs", Vector3.new(1.6, 2, 0.9), CFrame.new(0, 1, 0), true, false)
	local function motor(motorName: string, p0: BasePart, p1: BasePart)
		local m = Instance.new("Motor6D")
		m.Name = motorName
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = p0.CFrame:Inverse() * p1.CFrame
		m.C1 = CFrame.new()
		m.Parent = p1
	end
	motor("Root", root, lower)
	motor("Waist", lower, upper)
	motor("Neck", upper, head)
	motor("LegsJoint", lower, legs)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("RigFamily", "Human")
	model:SetAttribute("BlueprintId", "Fallback")
	return model
end

local function buildModel(blueprintId: string, name: string, skin: string?, scale: number?, color: Color3): Model
	local builder = getRigBuilder()
	if builder then
		local ok, model = pcall(builder.Build, blueprintId, { Skin = skin, Name = name, Scale = scale })
		if ok and validRig(model) then
			return model
		end
		warn(
			("[CharacterService] RigBuilder.Build(%s) failed (%s); falling back to Dummy"):format(
				blueprintId,
				tostring(model)
			)
		)
		if ok and typeof(model) == "Instance" then
			model:Destroy()
		end
		if blueprintId ~= "Dummy" then
			local ok2, dummy = pcall(builder.Build, "Dummy", { Name = name, Scale = scale })
			if ok2 and validRig(dummy) then
				return dummy
			end
		end
	end
	return buildFallbackRig(name, color)
end

-- Keeps only the yaw of a spawn CFrame (spawns are ground points).
local function groundFrame(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(cf.Position)
	end
	return CFrame.lookAt(cf.Position, cf.Position + flat.Unit)
end

local function rootLift(humanoid: Humanoid, root: BasePart): number
	return math.max(root.Position.Y, humanoid.HipHeight + root.Size.Y / 2)
end

-- Ground CFrame under a character (used to respawn "in place").
local function groundUnder(rec: Record): CFrame
	local root = rec.Root
	local lift = rec.Humanoid.HipHeight + root.Size.Y / 2
	local pos = root.Position - Vector3.new(0, lift, 0)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + flat.Unit)
end

local function setCollisionGroup(part: BasePart)
	part.CollisionGroup = CHARACTER_GROUP
end

local function displayNameFor(kit: any, kitId: string, opts: SpawnOpts, player: Player?): string
	if player then
		return player.DisplayName
	end
	if opts.Name and opts.Name ~= "" then
		return opts.Name
	end
	if kitId == "Dummy" then
		return Strings.L("round.dummy.name")
	end
	if kit then
		return Strings.L("round.practice.bot", Strings.Pick(kit.Name))
	end
	return kitId
end

local function setAttributes(
	model: Model,
	kit: any,
	kitId: string,
	team: string,
	skin: string,
	player: Player?,
	displayName: string
)
	model:SetAttribute("KitId", kitId)
	model:SetAttribute("Team", team)
	model:SetAttribute("RigFamily", if kit then kit.Family else (model:GetAttribute("RigFamily") or "Human"))
	model:SetAttribute("SkinId", skin)
	model:SetAttribute("IsBot", player == nil)
	model:SetAttribute("OwnerUserId", if player then player.UserId else 0)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("Ult", 0)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("Downed", false)
	model:SetAttribute("DownedEndsAt", 0)
	model:SetAttribute("Dead", false)
	model:SetAttribute("SoulMode", "Red")
	model:SetAttribute("Invisible", false)
	model:SetAttribute("Buff_DamageMult", 1)
	model:SetAttribute("SpawnedAt", now())
	if kit and kit.Role == "Monster" then
		local maxDodges = kit.Stats.MaxDodges or 0
		model:SetAttribute("Dodges", maxDodges)
		model:SetAttribute("MaxDodges", maxDodges)
		model:SetAttribute("Exhausted", 0)
		model:SetAttribute("FinalForm", false)
	else
		local maxGuard = if kit then (kit.Stats.MaxGuard or Config.Human.MaxGuard) else Config.Human.MaxGuard
		model:SetAttribute("KR", 0)
		model:SetAttribute("Guard", maxGuard)
		model:SetAttribute("MaxGuard", maxGuard)
		model:SetAttribute("DashCharges", if kit then (kit.Stats.DashCharges or Config.Human.DashCharges) else 0)
	end
end

local function clearPrompt(rec: Record)
	local prompt = rec.Prompt
	rec.Prompt = nil
	if prompt then
		prompt:Destroy()
	end
end

-- Builds a configured, unparented character and its record.
local function createCharacter(kitId: string, cframe: CFrame, opts: SpawnOpts, player: Player?): Record
	local kit = Kits.Get(kitId)
	local team: string = opts.Team or (if kit then (if kit.Role == "Monster" then "Monster" else "Humans") else "Dummy")
	local displayName = displayNameFor(kit, kitId, opts, player)
	local blueprint = opts.Blueprint or (if kit then kit.Rig else "Dummy")
	local skin = opts.SkinId or "Default"
	local scale = if kit then kit.Stats.Scale else nil
	local modelName: string
	if player then
		modelName = player.Name
	else
		botCounter += 1
		modelName = ("Bot_%s_%d"):format(kitId, botCounter)
	end
	local color = if kit then kit.Color else Color3.fromRGB(200, 200, 200)
	local model = buildModel(blueprint, modelName, skin, scale, color)
	model.Name = modelName
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			setCollisionGroup(d)
		end
	end

	setAttributes(model, kit, kitId, team, skin, player, displayName)

	local maxHealth = opts.MaxHealth
	if type(maxHealth) ~= "number" or maxHealth ~= maxHealth or maxHealth <= 0 then
		maxHealth = if kit then kit.Stats.MaxHP elseif kitId == "Dummy" then DUMMY_HEALTH else 100
	end
	humanoid.MaxHealth = maxHealth :: number
	humanoid.Health = maxHealth :: number
	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = if kit then kit.Stats.WalkSpeed else 0
	humanoid.JumpPower = if kit then kit.Stats.JumpPower else 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	if player == nil then
		-- server-simulated bodies: never trip over
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end

	local spawnCF = groundFrame(cframe)
	model:PivotTo(spawnCF * CFrame.new(0, rootLift(humanoid, root) + 0.1, 0))

	local rec: Record = {
		Model = model,
		Player = player,
		Kit = kit,
		KitId = kitId,
		Team = team,
		Humanoid = humanoid,
		Root = root,
		Trove = Trove.new(),
		Token = 0,
		Prompt = nil,
		LastAttacker = nil,
		Dead = false,
		Despawning = false,
		IsBot = player == nil,
		DisplayName = displayName,
		SpawnCFrame = spawnCF,
	}
	return rec
end

local function getBotsFolder(): Folder
	local existing = workspace:FindFirstChild("Bots")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Bots"
	folder.Parent = workspace
	return folder
end

local function lobbyInfo(): any
	if MapService == nil then
		return nil
	end
	local ok, info = call(MapService, "Lobby")
	if ok and info then
		return info
	end
	local ok2, loaded = call(MapService, "LoadLobby")
	return if ok2 then loaded else nil
end

local function killYFor(rec: Record): number
	if MapService == nil then
		return DEFAULT_KILL_Y
	end
	local info: any = nil
	if rec.Team ~= "Lobby" and rec.Team ~= "Dummy" then
		local _, current = call(MapService, "Current")
		info = current
	end
	if info == nil then
		local _, lobby = call(MapService, "Lobby")
		info = lobby
	end
	if info and type(info.KillY) == "number" then
		return info.KillY
	end
	return DEFAULT_KILL_Y
end

local function pickLobbySpawn(): CFrame
	local info = lobbyInfo()
	local spawns = if info and type(info.HumanSpawns) == "table" then info.HumanSpawns else nil
	if spawns and #spawns > 0 then
		local cf: CFrame = spawns[spawnRandom:NextInteger(1, #spawns)]
		local jitter = Vector3.new(spawnRandom:NextNumber(-2.5, 2.5), 0, spawnRandom:NextNumber(-2.5, 2.5))
		return cf + jitter
	end
	return CFrame.new(0, 2, 0)
end

local function scheduleLobbyRespawn(player: Player, delaySeconds: number)
	task.delay(delaySeconds, function()
		if player.Parent == nil then
			return
		end
		local current = byPlayer[player]
		if current then
			local rec = records[current]
			if rec and not rec.Dead then
				return -- already has a living body (e.g. spawned into a round)
			end
		end
		local role = player:GetAttribute("Role")
		if role ~= nil and role ~= "Lobby" then
			return
		end
		local ok, err = pcall(CharacterService.SpawnLobby, player)
		if not ok then
			warn("[CharacterService] lobby respawn failed: " .. tostring(err))
		end
	end)
end

-- Revive prompt ------------------------------------------------------------------------------------

local function onReviveTriggered(rec: Record, player: Player)
	local victim = rec.Model
	if rec.Dead or records[victim] ~= rec or victim:GetAttribute("Downed") ~= true then
		return
	end
	local reviver = byPlayer[player]
	if reviver == nil or reviver == victim then
		return
	end
	local rrec = records[reviver]
	if rrec == nil or rrec.Dead or rrec.Team ~= "Humans" or reviver:GetAttribute("Downed") == true then
		return
	end
	if (rrec.Root.Position - rec.Root.Position).Magnitude > REVIVE_DISTANCE + 4 then
		return
	end
	CharacterService.Revive(victim, reviver)
end

local function createPrompt(rec: Record)
	clearPrompt(rec)
	local left = revivesLeft()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = Strings.L("round.revive.action")
	prompt.ObjectText = Strings.L("round.revive.object", rec.DisplayName)
	prompt.HoldDuration = Config.Human.ReviveHoldTime
	prompt.MaxActivationDistance = REVIVE_DISTANCE
	prompt.RequiresLineOfSight = false
	-- E/Q/R/F/Shift are ability keys for humans; G is free on keyboard, DPadRight on gamepads
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Enabled = left == nil or left > 0
	-- client hints: localise texts and hide the prompt for non-humans / the victim
	prompt:SetAttribute("ActionKey", "round.revive.action")
	prompt:SetAttribute("ObjectKey", "round.revive.object")
	prompt:SetAttribute("HumansOnly", true)
	prompt:SetAttribute("VictimUserId", if rec.Player then rec.Player.UserId else 0)
	prompt.Triggered:Connect(function(player: Player)
		onReviveTriggered(rec, player)
	end)
	prompt.Parent = rec.Root
	rec.Prompt = prompt
end

local function updatePromptsEnabled()
	local left = revivesLeft()
	local enabled = left == nil or left > 0
	for _, rec in records do
		if rec.Prompt then
			rec.Prompt.Enabled = enabled
		end
	end
end

-- Lifecycle hooks -----------------------------------------------------------------------------------

local function hook(rec: Record)
	local model = rec.Model
	rec.Trove:Connect(rec.Humanoid.Died, function()
		local current = records[model]
		if current and not current.Dead then
			CharacterService.Kill(model, current.LastAttacker, nil)
		end
	end)
	rec.Trove:Connect(model.DescendantAdded, function(d: Instance)
		if d:IsA("BasePart") then
			setCollisionGroup(d)
		end
	end)
	rec.Trove:Connect(model.AncestryChanged, function()
		if not rec.Despawning and not model:IsDescendantOf(workspace) then
			-- removed by something else (e.g. FallenPartsDestroyHeight): forget it cleanly
			task.defer(function()
				if records[model] == rec and not model:IsDescendantOf(workspace) then
					CharacterService.Despawn(model)
				end
			end)
		end
	end)
end

local function register(rec: Record)
	records[rec.Model] = rec
	hook(rec)
end

-- Public API ------------------------------------------------------------------------------------------

function CharacterService.EquippedKit(player: Player, role: string): string
	local id: any = nil
	if DataService then
		local ok, profile = call(DataService, "Get", player)
		if ok and type(profile) == "table" and type(profile.Equipped) == "table" then
			id = profile.Equipped[role]
		end
	end
	if type(id) ~= "string" then
		id = player:GetAttribute(if role == "Monster" then "EquippedMonster" else "EquippedHuman")
	end
	local kit = if type(id) == "string" then Kits.Get(id) else nil
	if kit and kit.Role == role then
		return id
	end
	return if role == "Monster" then Kits.DefaultMonster else Kits.DefaultHuman
end

function CharacterService.EquippedSkin(player: Player, kitId: string): string
	if DataService then
		local ok, profile = call(DataService, "Get", player)
		if
			ok
			and type(profile) == "table"
			and type(profile.Equipped) == "table"
			and type(profile.Equipped.Skins) == "table"
		then
			local skin = profile.Equipped.Skins[kitId]
			if type(skin) == "string" and skin ~= "" and Kits.Skin(kitId, skin) ~= nil then
				return skin
			end
		end
	end
	return "Default"
end

function CharacterService.SpawnPlayer(player: Player, kitId: string, cframe: CFrame, opts: SpawnOpts?): Model
	local o: SpawnOpts = opts or {}
	local existing = byPlayer[player]
	if existing then
		CharacterService.Despawn(existing)
	end
	local rec = createCharacter(kitId, cframe, o, player)
	local model = rec.Model
	model.Parent = workspace
	player.Character = model
	pcall(function()
		rec.Root:SetNetworkOwner(player)
	end)
	byPlayer[player] = model
	register(rec)
	player:SetAttribute("Role", roleForTeam(rec.Team))
	CharacterService.Spawned:Fire(model, player)
	return model
end

function CharacterService.SpawnBot(kitId: string, cframe: CFrame, opts: SpawnOpts?): Model
	local o: SpawnOpts = opts or {}
	local rec = createCharacter(kitId, cframe, o, nil)
	local model = rec.Model
	model.Parent = getBotsFolder()
	pcall(function()
		rec.Root:SetNetworkOwner(nil)
	end)
	register(rec)
	CharacterService.Spawned:Fire(model, nil)
	return model
end

function CharacterService.SpawnLobby(player: Player, kitOverride: string?, atCFrame: CFrame?): Model?
	if player.Parent == nil then
		return nil
	end
	local kitId: string
	local override = kitOverride or tryKits[player]
	if type(override) == "string" and Kits.Get(override) ~= nil then
		kitId = override
	else
		kitId = CharacterService.EquippedKit(player, "Human")
	end
	local cf = atCFrame or pickLobbySpawn()
	local model = CharacterService.SpawnPlayer(player, kitId, cf, {
		Team = "Lobby",
		SkinId = CharacterService.EquippedSkin(player, kitId),
	})
	player:SetAttribute("Role", "Lobby")
	return model
end

-- Re-spawns a lobby body in place with the current equipment / try-kit (no-op outside the lobby).
function CharacterService.RefreshLobby(player: Player)
	local model = byPlayer[player]
	local rec = if model then records[model] else nil
	if rec == nil or rec.Team ~= "Lobby" or rec.Dead then
		return
	end
	CharacterService.SpawnLobby(player, nil, groundUnder(rec))
end

function CharacterService.Despawn(model: Model)
	local rec = records[model]
	if rec == nil then
		-- only ever destroy things that look like our characters
		if typeof(model) == "Instance" and model.Parent ~= nil and model:GetAttribute("KitId") ~= nil then
			model:Destroy()
		end
		return
	end
	if rec.Despawning then
		return
	end
	rec.Despawning = true
	rec.Token += 1
	CharacterService.Despawning:Fire(model)
	records[model] = nil
	local player = rec.Player
	if player and byPlayer[player] == model then
		byPlayer[player] = nil
		if player.Character == model then
			player.Character = nil
		end
	end
	clearPrompt(rec)
	call(StatusService, "ClearAll", model)
	rec.Trove:Destroy()
	model:Destroy()
end

function CharacterService.DespawnTeam(team: string)
	local list: { Model } = {}
	for model, rec in records do
		if rec.Team == team then
			table.insert(list, model)
		end
	end
	for _, model in list do
		CharacterService.Despawn(model)
	end
end

function CharacterService.GetPlayer(model: Model?): Player?
	if model == nil then
		return nil
	end
	local rec = records[model]
	if rec then
		return rec.Player
	end
	return Players:GetPlayerFromCharacter(model)
end

function CharacterService.GetModel(player: Player): Model?
	return byPlayer[player]
end

function CharacterService.GetKit(model: Model?): any
	if model == nil then
		return nil
	end
	local rec = records[model]
	if rec then
		return rec.Kit
	end
	local id = model:GetAttribute("KitId")
	return if type(id) == "string" then Kits.Get(id) else nil
end

function CharacterService.GetTeam(model: Model?): string?
	if model == nil then
		return nil
	end
	local rec = records[model]
	if rec then
		return rec.Team
	end
	local team = model:GetAttribute("Team")
	return if type(team) == "string" then team else nil
end

function CharacterService.IsAlive(model: Model?): boolean
	if model == nil then
		return false
	end
	local rec = records[model]
	if rec then
		return not rec.Dead
	end
	if model.Parent == nil or model:GetAttribute("Dead") == true then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function CharacterService.IsUp(model: Model?): boolean
	return CharacterService.IsAlive(model) and (model :: Model):GetAttribute("Downed") ~= true
end

function CharacterService.GetAll(team: string?, includeDead: boolean?): { Model }
	local out: { Model } = {}
	for model, rec in records do
		if (team == nil or rec.Team == team) and (includeDead == true or not rec.Dead) then
			table.insert(out, model)
		end
	end
	return out
end

function CharacterService.SetDowned(model: Model, attacker: Model?)
	local rec = records[model]
	if rec == nil or rec.Dead then
		return
	end
	if attacker then
		rec.LastAttacker = attacker
	end
	local left = revivesLeft()
	-- Only round humans can be downed; downed again / no revives left -> death (SPEC §1.3, §7.5)
	if rec.Team ~= "Humans" or model:GetAttribute("Downed") == true or (left ~= nil and left <= 0) then
		CharacterService.Kill(model, attacker, nil)
		return
	end
	rec.Token += 1
	local token = rec.Token
	local downedTime: number = Config.Human.DownedTime
	model:SetAttribute("Downed", true)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("KR", 0)
	model:SetAttribute("DownedEndsAt", now() + downedTime)
	setHealth(model, rec.Humanoid, 1)
	call(StatusService, "Apply", model, "Silenced", downedTime + 1)
	call(StatusService, "RecomputeMovement", model)
	createPrompt(rec)
	task.delay(downedTime, function()
		if rec.Token == token and records[model] == rec and not rec.Dead and model:GetAttribute("Downed") == true then
			CharacterService.Kill(model, rec.LastAttacker, "BleedOut")
		end
	end)
	CharacterService.Downed:Fire(model, attacker)
end

function CharacterService.Revive(model: Model, by: Model?): boolean
	local rec = records[model]
	if rec == nil or rec.Dead or model:GetAttribute("Downed") ~= true then
		return false
	end
	local rs = roundState()
	if rs then
		local left = rs:GetAttribute("TeamRevives")
		if type(left) == "number" then
			if left <= 0 then
				notify(CharacterService.GetPlayer(by), "round.revive.none", nil, "Warning")
				return false
			end
			rs:SetAttribute("TeamRevives", left - 1)
		end
	end
	rec.Token += 1
	clearPrompt(rec)
	model:SetAttribute("Downed", false)
	model:SetAttribute("DownedEndsAt", 0)
	local humanoid = rec.Humanoid
	setHealth(model, humanoid, math.max(humanoid.Health, humanoid.MaxHealth * Config.Human.ReviveHealthFraction))
	call(StatusService, "Remove", model, "Silenced")
	call(StatusService, "Apply", model, "IFrames", REVIVE_IFRAMES)
	call(StatusService, "RecomputeMovement", model)
	CharacterService.Revived:Fire(model, by)
	return true
end

function CharacterService.Kill(model: Model, attacker: Model?, ability: string?)
	local rec = records[model]
	if rec == nil or rec.Dead then
		return
	end
	rec.Dead = true
	rec.Token += 1
	clearPrompt(rec)
	model:SetAttribute("Dead", true)
	model:SetAttribute("Downed", false)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("DownedEndsAt", 0)
	call(StatusService, "ClearAll", model)
	call(StatusService, "Apply", model, "Stunned", DEATH_BODY_TIME + 1)
	local humanoid = rec.Humanoid
	if humanoid.Health > 0 then
		setHealth(model, humanoid, 0)
	end
	local root = rec.Root
	if root.Parent ~= nil then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
	end
	local killer = attacker or rec.LastAttacker
	if killer == model then
		killer = nil
	end
	CharacterService.Died:Fire(model, killer, ability)
	local player = rec.Player
	if player and player.Parent then
		if rec.Team == "Lobby" then
			scheduleLobbyRespawn(player, math.max(Players.RespawnTime, DEATH_BODY_TIME + 0.1))
		else
			player:SetAttribute("Role", "Spectator")
			notify(player, "round.notify.spectating", nil, "Info")
		end
	end
	task.delay(DEATH_BODY_TIME, function()
		if records[model] == rec then
			CharacterService.Despawn(model)
		end
	end)
end

-- Requests ---------------------------------------------------------------------------------------------

local function onTryKit(player: Player, data: any): (boolean, string?)
	local kitId: any = data
	if type(data) == "table" then
		kitId = data.kitId
	end
	if kitId == nil or kitId == "" then
		tryKits[player] = nil
		CharacterService.RefreshLobby(player)
		return true, nil
	end
	if type(kitId) ~= "string" or #kitId > 40 or Kits.Get(kitId) == nil then
		return false, "round.trykit.invalid"
	end
	local role = player:GetAttribute("Role")
	if role ~= nil and role ~= "Lobby" then
		return false, "round.trykit.notLobby"
	end
	tryKits[player] = kitId
	local model = byPlayer[player]
	local rec = if model then records[model] else nil
	local at = if rec and not rec.Dead and rec.Team == "Lobby" then groundUnder(rec) else nil
	CharacterService.SpawnLobby(player, kitId, at)
	notify(player, "round.trykit.trying", { Strings.Pick(Kits.Get(kitId).Name) }, "Info")
	return true, nil
end

-- Players -------------------------------------------------------------------------------------------------

local function onEquippedChanged(player: Player)
	if refreshPending[player] then
		return
	end
	refreshPending[player] = true
	task.delay(0.3, function()
		refreshPending[player] = nil
		if player.Parent == nil or tryKits[player] ~= nil then
			return
		end
		local model = byPlayer[player]
		local rec = if model then records[model] else nil
		if rec == nil or rec.Team ~= "Lobby" or rec.Dead then
			return
		end
		if CharacterService.EquippedKit(player, "Human") ~= rec.KitId then
			CharacterService.RefreshLobby(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	if playerTroves[player] then
		return
	end
	player:SetAttribute("Role", "Lobby")
	local trove = Trove.new()
	playerTroves[player] = trove
	trove:Connect(player:GetAttributeChangedSignal("EquippedHuman"), function()
		onEquippedChanged(player)
	end)
	task.spawn(function()
		if DataService and type(DataService.WaitFor) == "function" then
			pcall(DataService.WaitFor, player, 8)
		end
		if player.Parent == nil or byPlayer[player] ~= nil then
			return
		end
		local role = player:GetAttribute("Role")
		if role ~= nil and role ~= "Lobby" then
			return
		end
		local ok, err = pcall(CharacterService.SpawnLobby, player)
		if not ok then
			warn("[CharacterService] lobby spawn failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local model = byPlayer[player]
	if model then
		CharacterService.Despawn(model)
	end
	byPlayer[player] = nil
	tryKits[player] = nil
	refreshPending[player] = nil
	local trove = playerTroves[player]
	playerTroves[player] = nil
	if trove then
		trove:Destroy()
	end
end

-- Fall / void watchdog: below KillY -> lobby bodies are put back on a spawn, round bodies die.
local function watchdogStep()
	local list: { Record } = {}
	for _, rec in records do
		table.insert(list, rec)
	end
	for _, rec in list do
		if records[rec.Model] ~= rec or rec.Dead then
			continue
		end
		local root = rec.Root
		if root.Parent == nil then
			continue
		end
		if root.Position.Y < killYFor(rec) then
			if rec.Team == "Lobby" then
				local target = pickLobbySpawn()
				root.AssemblyLinearVelocity = Vector3.zero
				rec.Model:PivotTo(groundFrame(target) * CFrame.new(0, rootLift(rec.Humanoid, root) + 0.1, 0))
			elseif rec.Team == "Dummy" then
				root.AssemblyLinearVelocity = Vector3.zero
				rec.Model:PivotTo(rec.SpawnCFrame * CFrame.new(0, rootLift(rec.Humanoid, root) + 0.1, 0))
			else
				CharacterService.Kill(rec.Model, rec.LastAttacker, "Void")
			end
		end
	end
end

local function setupCollisionGroups()
	local groups = Config.CollisionGroups
	for _, name in { groups.Characters, groups.Visual, groups.Hazard } do
		local ok, err = pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end)
		if not ok then
			warn("[CharacterService] collision group " .. tostring(name) .. ": " .. tostring(err))
		end
	end
	pcall(function()
		-- characters pass through each other (no body-blocking, no stacking); VFX/hazard parts never push anyone
		PhysicsService:CollisionGroupSetCollidable(groups.Characters, groups.Characters, false)
		PhysicsService:CollisionGroupSetCollidable(groups.Visual, groups.Characters, false)
		PhysicsService:CollisionGroupSetCollidable(groups.Hazard, groups.Characters, false)
		PhysicsService:CollisionGroupSetCollidable(groups.Visual, groups.Visual, false)
	end)
end

-- Lifecycle -------------------------------------------------------------------------------------------------

function CharacterService.Init()
	MapService = tryService("MapService")
	DataService = tryService("DataService")
	StatusService = tryService("StatusService")
	RequestService = tryService("RequestService")
	DamageService = tryService("DamageService")
	setupCollisionGroups()
	if RequestService and type(RequestService.Register) == "function" then
		local ok, err = pcall(RequestService.Register, "TryKit", onTryKit)
		if not ok then
			warn("[CharacterService] TryKit registration failed: " .. tostring(err))
		end
	end
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	local rs = roundState()
	if rs then
		rs:GetAttributeChangedSignal("TeamRevives"):Connect(updatePromptsEnabled)
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(watchdogStep)
			if not ok then
				warn("[CharacterService] watchdog: " .. tostring(err))
			end
		end
	end)
end

return CharacterService
