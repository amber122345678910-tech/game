--!strict
-- Шаги. Свои: звук по Humanoid.FloorMaterial с интервалом по режиму (ходьба 0.5 с, бег 0.32 с, присед 0.8 с),
-- случайная высота 0.9–1.1, тише при приседе; штатные шаги Roblox у своего персонажа глушим.
-- Пациенты: StepHeavy у HumanoidRootPart каждого Model в workspace.Inmates, только когда он реально
-- движется (каждые 0.55 с, в погоне 0.4 с) — «слышимые шаги всегда настоящие».

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Movement = require(script.Parent:WaitForChild("Movement"))

local Footsteps = {}

local STEP_WALK = 0.5
local STEP_SPRINT = 0.32
local STEP_CROUCH = 0.8
local INMATE_STEP = 0.55
local INMATE_STEP_CHASE = 0.4
-- Пациент считается движущимся при скорости выше этой (≈ 0.1 стада за кадр при 30 fps)
local INMATE_MOVE_SPEED = 3
local INMATE_HEAR_RANGE = 95

local MATERIAL_SOUND: { [Enum.Material]: string } = {
	[Enum.Material.Wood] = "StepWood",
	[Enum.Material.WoodPlanks] = "StepWood",
	[Enum.Material.Grass] = "StepGrass",
	[Enum.Material.Ground] = "StepGrass",
	[Enum.Material.LeafyGrass] = "StepGrass",
	[Enum.Material.Mud] = "StepGrass",
	[Enum.Material.Sand] = "StepGrass",
	[Enum.Material.Concrete] = "StepConcrete",
	[Enum.Material.Asphalt] = "StepConcrete",
	[Enum.Material.Slate] = "StepConcrete",
	[Enum.Material.Pavement] = "StepConcrete",
	[Enum.Material.Brick] = "StepConcrete",
	[Enum.Material.Cobblestone] = "StepConcrete",
	[Enum.Material.Metal] = "StepConcrete",
	[Enum.Material.DiamondPlate] = "StepConcrete",
	[Enum.Material.Marble] = "StepConcrete",
	[Enum.Material.Basalt] = "StepConcrete",
	[Enum.Material.Rock] = "StepConcrete",
}

-- Шаги по виду пациента: {звук, громкость}
local KIND_STEP: { [string]: { string | number } } = {
	Boss = { "StepHeavy", 1.5 },
	StillOne = { "Creak", 0.6 },
	Twins = { "StepHeavy", 0.75 },
	Collector = { "StepHeavy", 0.7 },
	Sentinel = { "", 0 },
}

local player = Players.LocalPlayer
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local charConns: { RBXScriptConnection } = {}
local stepTimer = 0

type Track = {
	Model: Model,
	LastPos: Vector3?,
	Timer: number,
}
local tracks: { [Model]: Track } = {}
local inmateConns: { RBXScriptConnection } = {}

local function clearCharConns()
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
end

-- Штатный звук шагов Roblox у своего персонажа выключаем (шаги играем сами).
local function muteDefaultSteps(root: BasePart)
	local function mute(child: Instance)
		if child:IsA("Sound") and (child.Name == "Running" or child.Name == "Landing") then
			child.Volume = 0
		end
	end
	for _, child in root:GetChildren() do
		mute(child)
	end
	table.insert(charConns, root.ChildAdded:Connect(mute))
end

local function bindCharacter(char: Model)
	clearCharConns()
	humanoid = nil
	rootPart = nil
	stepTimer = 0
	local h = char:WaitForChild("Humanoid", 10)
	local r = char:WaitForChild("HumanoidRootPart", 10)
	if h and h:IsA("Humanoid") and h.Parent == char then
		humanoid = h
	end
	if r and r:IsA("BasePart") and r.Parent == char then
		rootPart = r
		muteDefaultSteps(r)
	end
end

local function stepName(material: Enum.Material): string
	return MATERIAL_SOUND[material] or "StepWood"
end

local function stepLocal(dt: number)
	local hum, root = humanoid, rootPart
	if not hum or not root or not hum.Parent or hum.Health <= 0 then
		return
	end
	local status = ClientState.Status
	if status ~= "Alive" and status ~= "Lobby" then
		stepTimer = 0
		return
	end
	local onFloor = hum.FloorMaterial ~= Enum.Material.Air
	local velocity = root.AssemblyLinearVelocity
	local planar = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = onFloor and hum.MoveDirection.Magnitude > 0.05 and planar > 1
	if not moving then
		-- первый шаг после остановки выходит быстрее
		stepTimer = math.min(stepTimer, STEP_WALK * 0.35)
		return
	end
	local interval, volume
	if Movement.Sprinting then
		interval, volume = STEP_SPRINT, 1
	elseif ClientState.Crouching then
		interval, volume = STEP_CROUCH, 0.4
	else
		interval, volume = STEP_WALK, 0.75
	end
	stepTimer += dt
	if stepTimer >= interval then
		stepTimer = 0
		Sounds.playAt(stepName(hum.FloorMaterial), root.Position - Vector3.new(0, 2.6, 0), volume)
	end
end

local function trackInmate(model: Instance)
	if not model:IsA("Model") or tracks[model] then
		return
	end
	tracks[model] = { Model = model, LastPos = nil, Timer = 0 }
end

local function untrackInmate(model: Instance)
	if model:IsA("Model") then
		tracks[model] = nil
	end
end

local function bindInmatesFolder(folder: Instance)
	for _, c in inmateConns do
		c:Disconnect()
	end
	table.clear(inmateConns)
	table.clear(tracks)
	for _, child in folder:GetChildren() do
		trackInmate(child)
	end
	table.insert(inmateConns, folder.ChildAdded:Connect(trackInmate))
	table.insert(inmateConns, folder.ChildRemoved:Connect(untrackInmate))
end

local function stepInmates(dt: number)
	local cam = workspace.CurrentCamera
	local listener = if cam then cam.CFrame.Position else Vector3.zero
	for model, track in tracks do
		if model.Parent == nil then
			tracks[model] = nil
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local pos = root.Position
		local last = track.LastPos
		track.LastPos = pos
		if not last then
			continue
		end
		local speed = (pos - last).Magnitude / math.max(dt, 1 / 240)
		if speed < INMATE_MOVE_SPEED or speed > Config.Movement.MaxLegalSpeed * 3 then
			-- стоит (или телепорт при появлении) — шагов нет
			track.Timer = math.min(track.Timer, 0.2)
			continue
		end
		local chasing = model:GetAttribute("State") == "Chase"
		track.Timer += dt
		local interval = if chasing then INMATE_STEP_CHASE else INMATE_STEP
		if track.Timer < interval then
			continue
		end
		track.Timer = 0
		if (pos - listener).Magnitude > INMATE_HEAR_RANGE then
			continue
		end
		local kind = model:GetAttribute("Kind")
		local entry = if typeof(kind) == "string" then KIND_STEP[kind] else nil
		local name = if entry then entry[1] :: string else "StepHeavy"
		local volume = if entry then entry[2] :: number else 1
		if name ~= "" and volume > 0 then
			Sounds.playAt(name, pos - Vector3.new(0, 2.5, 0), volume)
		end
	end
end

function Footsteps.init()
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		clearCharConns()
		humanoid = nil
		rootPart = nil
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	local existing = workspace:FindFirstChild("Inmates")
	if existing then
		bindInmatesFolder(existing)
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Inmates" then
			bindInmatesFolder(child)
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		stepLocal(dt)
		stepInmates(dt)
	end)
end

return Footsteps
