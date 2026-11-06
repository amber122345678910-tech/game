-- Интеграционная симуляция КЛИЕНТА: настоящий ElasticSlingshotController + KineticVFX в мок-движке.
-- Ввод идёт через те же ContextActionService-обработчики, что и в игре; кадры — через BindToRenderStep.
-- Запуск: lune run tests/client_sim.luau
local process = require("@lune/process")
local task = require("@lune/task")
local Engine = require("./engine")
local H = Engine.H
local roblox = H.roblox
local Instance, Vector3, CFrame, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Enum

local PhysicsConfig = H.require("ReplicatedStorage.Shared.Config.PhysicsConfig")
local SoundConfig = H.require("ReplicatedStorage.Shared.Config.SoundConfig")
local StretchPhysics = H.require("ReplicatedStorage.Shared.Physics.StretchPhysics")
local KineticVFX = H.require("StarterPlayer.StarterPlayerScripts.Client.Effects.KineticVFX")
local Controller = H.require("StarterPlayer.StarterPlayerScripts.Client.Controllers.ElasticSlingshotController")

local game = Engine.game
local workspace = Engine.workspace
local players = game:GetService("Players")
local Tags = PhysicsConfig.Tags
local DT = 1 / 60

local player = Instance.new("Player")
player.Name = "Pilot"
player.UserId = 9001
player.Parent = players
players.LocalPlayer = player
player:SetAttribute("Stat_Elasticity", 0)
player:SetAttribute("Stat_SpringPower", 0)
player:SetAttribute("Stat_SmashMass", 0)
player:SetAttribute("Glove", "Rubber")

-- ── Тестовый мир ────────────────────────────────────────────────────────────
local world = Instance.new("Folder")
world.Name = "TestWorld"
world.Parent = workspace
Engine.newPart("Ground", Vector3.new(800, 6, 1600), CFrame.new(0, -3, -500), world)

local function post(x: number, z: number, height: number): any
	Engine.newPart("Post", Vector3.new(3, height, 3), CFrame.new(x, height / 2, z), world)
	local ring = Engine.newPart("Ring", Vector3.new(4.6, 4.6, 4.6), CFrame.new(x, height + 1.8, z), world)
	ring:AddTag(Tags.GrabPoint)
	return ring
end
local leftRing = post(-16, -50, 30)
local rightRing = post(16, -50, 30)

local function wall(name: string, z: number, requiredSpeed: number, owner: number): any
	local part = Engine.newPart(name, Vector3.new(400, 160, 4), CFrame.new(0, 80, z), world)
	part:AddTag(Tags.Smashable)
	part:SetAttribute("ObstacleId", name)
	part:SetAttribute("ObstacleKind", "Wall")
	part:SetAttribute("Durability", StretchPhysics.DurabilityFromSpeed(requiredSpeed, 1))
	part:SetAttribute("OwnerUserId", owner)
	return part
end
local softWall = wall("T0-Soft", -400, 60, 9001)
local titanWall = wall("T0-Titan", -700, 185, 9001)

local gong = Engine.newPart("GongDisc", Vector3.new(4, 60, 60), CFrame.new(0, 24, -1000), world)
gong:AddTag(Tags.Gong)
gong:SetAttribute("GongLaneSlot", 1)
gong:SetAttribute("OwnerUserId", 9001)

local character, root, humanoid = Engine.buildCharacter(player, CFrame.new(0, 3, 0))

-- ── Фейковая камера (интерфейс ShoulderCamera) ─────────────────────────────
local camera = {
	Origin = Vector3.new(0, 6, 12),
	Direction = Vector3.new(0, 0, -1),
	Flat = Vector3.new(0, 0, -1),
	Free = false,
	Trauma = 0,
	Speed = 0,
}
function camera:GetAimRay()
	return camera.Origin, camera.Direction
end
function camera:GetFlatLook()
	return camera.Flat
end
function camera:AddTrauma(amount)
	camera.Trauma += amount
end
function camera:Kick(_degrees) end
function camera:SetSpeed(speed)
	camera.Speed = speed
end
function camera:IsMouseFree()
	return camera.Free
end
function camera:SnapBehind(_look) end
function camera:SetMouseFree(free)
	camera.Free = free
end
local function aimAt(point: any)
	camera.Origin = root.CFrame.Position + Vector3.new(1.5, 3, 10)
	camera.Direction = (point - camera.Origin).Unit
end

-- ── Запуск контроллера ─────────────────────────────────────────────────────
KineticVFX.Init()
local slingshot = Controller.new(camera :: any)
local events = { Launched = 0, Bounced = 0, Smashed = 0, Tension = 0, Gong = 0, State = {} }
slingshot.Signals.Launched:Connect(function()
	events.Launched += 1
end)
slingshot.Signals.Bounced:Connect(function()
	events.Bounced += 1
end)
slingshot.Signals.Smashed:Connect(function()
	events.Smashed += 1
end)
slingshot.Signals.TensionChanged:Connect(function(value)
	events.Tension = math.max(events.Tension, value)
end)
slingshot.Signals.GongStruck:Connect(function()
	events.Gong += 1
end)
slingshot.Signals.StateChanged:Connect(function(state)
	table.insert(events.State, state)
end)
slingshot:Start()
for _ = 1, 4 do
	task.wait(0.01)
end

local function frames(count: number)
	for _ = 1, count do
		Engine.clientStep(DT)
	end
end
local function input(action: string, state: any)
	local handler = Engine.actions[action]
	assert(handler, "action not bound: " .. action)
	return handler(action, state, nil)
end
local function press(action: string)
	return input(action, Enum.UserInputState.Begin)
end
local function release(action: string)
	return input(action, Enum.UserInputState.End)
end
local function teleport(position: any)
	root.CFrame = CFrame.new(position)
	root.Position = position
end
local function launchFrom(position: any, velocity: any)
	teleport(position)
	humanoid.FloorMaterial = Enum.Material.Air
	frames(1)
	slingshot:EnterCustom("Air", velocity)
end
local function waitForState(state: string, maxFrames: number): boolean
	for _ = 1, maxFrames do
		frames(1)
		if slingshot:GetState() == state then
			return true
		end
	end
	return false
end

-- ── Сценарии ────────────────────────────────────────────────────────────────
H.suite("Client · boot")
H.test("binds character, idles in Walk, input actions bound", function()
	H.check(slingshot.Character == character, "character bound")
	H.check(slingshot:GetState() == "Walk", "walk state")
	H.check(Engine.actions.StretchPop_LeftArm and Engine.actions.StretchPop_RightArm and Engine.actions.StretchPop_Ball, "CAS actions")
	H.check(Engine.renderSteps.StretchPop_Slingshot ~= nil, "render step bound")
	frames(5)
end)

H.suite("Client · slingshot (ground)")
H.test("LMB at the ring: hand flies, attaches, Charge state", function()
	aimAt(leftRing.Position)
	frames(1)
	H.check(slingshot.Aim.Valid and slingshot.Aim.Part == leftRing, "aim must lock onto the ring")
	local result = press("StretchPop_LeftArm")
	H.check(result == Enum.ContextActionResult.Sink, "LMB must be sunk")
	frames(20)
	H.check(slingshot.Hands.Left.Phase == "Attached", "left hand attached, phase=" .. slingshot.Hands.Left.Phase)
	H.check(slingshot:GetState() == "Charge", "charge state, got " .. slingshot:GetState())
	local log = Engine.findLog("ArmVisual")
	H.check(log and log.Args[1] == "Left" and log.Args[2] == true, "arm visual replicated")
	H.check(slingshot.Hands.Left.Rig.MainA.Enabled, "rubber arm beam visible")
end)
H.test("RMB adds the second band while charging", function()
	aimAt(rightRing.Position)
	frames(1)
	press("StretchPop_RightArm")
	frames(20)
	H.check(slingshot.Hands.Right.Phase == "Attached", "right attached")
	H.check(slingshot:GetState() == "Charge", "still charging")
end)
H.test("holding draws the character back; tension (½kx²) rises; arc preview drawn", function()
	local startZ = root.CFrame.Position.Z
	frames(90)
	local drawn = root.CFrame.Position.Z - startZ
	H.check(drawn > 5, "should be pulled back, moved " .. drawn)
	H.check(slingshot:GetTension() > 0.3, "tension " .. slingshot:GetTension())
	H.check(events.Tension > 0.3, "TensionChanged signal")
	local enabled = 0
	for _, beam in slingshot.TrajectoryBeams do
		if beam.Enabled then
			enabled += 1
		end
	end
	H.check(enabled >= 3, "trajectory arc segments visible: " .. enabled)
	local width = slingshot.Hands.Left.Rig.MainA.Width1
	H.check(width < PhysicsConfig.ArmBaseWidth * 0.8, "stretched arm must thin out, width=" .. width)
end)
H.test("release → launch along the bands with v = √(2E/m)", function()
	local bands = slingshot:CollectBands()
	local expected = StretchPhysics.SlingshotLaunch(slingshot.SimPosition, bands, slingshot:GetParams())
	release("StretchPop_LeftArm")
	release("StretchPop_RightArm")
	H.check(slingshot:GetState() == "Air", "air after release")
	H.check(events.Launched == 1, "Launched signal")
	H.near(slingshot.SimVelocity.Magnitude, expected.Magnitude, 0.5, "launch speed")
	H.check(slingshot.SimVelocity.Z < -20 and slingshot.SimVelocity.Y > 0, "forward + up")
	frames(10)
	H.check(root.CFrame.Position.Z < 30, "flying forward")
	H.check(slingshot.Hands.Left.Phase ~= "Attached" and slingshot.Hands.Right.Phase ~= "Attached", "hands released")
end)
H.test("flight lands back into Walk (skid friction)", function()
	H.check(waitForState("Walk", 900), "should land, state=" .. slingshot:GetState())
	humanoid.FloorMaterial = Enum.Material.Plastic
	frames(30)
	H.check(slingshot.Hands.Left.Phase == "Idle" and not slingshot.Hands.Left.Rig.MainA.Enabled, "arm retracted")
end)

H.test("anchor behind the camera: charging never slides the player toward it", function()
	slingshot:HardReset(CFrame.new(0, 3, -120))
	humanoid.FloorMaterial = Enum.Material.Plastic
	frames(2)
	aimAt(leftRing.Position) -- кольцо сзади (z = -50), камера смотрит вперёд (−Z)
	frames(1)
	press("StretchPop_LeftArm")
	frames(20)
	H.check(slingshot:GetState() == "Charge", "charging")
	local before = (root.CFrame.Position - leftRing.Position).Magnitude
	frames(60)
	local after = (root.CFrame.Position - leftRing.Position).Magnitude
	H.check(after >= before - 0.01, string.format("must not approach the anchor: %.2f → %.2f", before, after))
	release("StretchPop_LeftArm")
	frames(30)
	H.check(slingshot:GetState() == "Walk", "weak release just stands")
end)

H.suite("Client · wall smash")
H.test("fast impact predicts a smash without slowing the player", function()
	launchFrom(Vector3.new(0, 20, -330), Vector3.new(0, 0, -240))
	local smashed = false
	for _ = 1, 60 do
		frames(1)
		if Engine.findLog("SmashRequest") then
			smashed = true
			break
		end
	end
	H.check(smashed, "SmashRequest must be sent")
	local request = Engine.findLog("SmashRequest")
	H.check(request.Args[1] == "T0-Soft", "obstacle id")
	H.check(request.Args[4] > 150, "impact speed " .. request.Args[4])
	H.check(not softWall.CanCollide and softWall.LocalTransparencyModifier == 1, "wall hidden locally")
	H.check(math.abs(slingshot.SimVelocity.Z) > 200, "kept speed after smash: " .. slingshot.SimVelocity.Z)
	H.check(events.Smashed == 1 and slingshot:GetCombo() >= 1, "smash counted into combo")
	frames(10)
	H.check(root.CFrame.Position.Z < -405, "passed through the wall")
end)
H.test("server rejection restores the wall", function()
	Engine.remote("SmashResult").OnClientEvent:Fire("T0-Soft", false, 0, "too_weak")
	H.check(softWall.CanCollide and softWall.LocalTransparencyModifier == 0, "wall restored")
end)
H.test("slow impact on a Titan wall: no smash, cartoon splat keeps only part of the tangent speed", function()
	slingshot:HardReset(nil)
	local count = #Engine.remoteLog
	launchFrom(Vector3.new(0, 40, -650), Vector3.new(30, 0, -90))
	local hitWall = false
	for _ = 1, 90 do
		frames(1)
		if slingshot.SimVelocity.Z > -5 then
			hitWall = true
			break
		end
	end
	H.check(hitWall, "should stop at the wall: v=" .. tostring(slingshot.SimVelocity) .. " p=" .. tostring(root.CFrame.Position))
	H.check(root.CFrame.Position.Z > -698 - PhysicsConfig.BodyRadius + 0.5, "must not tunnel into the wall: z=" .. root.CFrame.Position.Z)
	for index = count + 1, #Engine.remoteLog do
		H.check(Engine.remoteLog[index].Remote ~= "SmashRequest", "titan must not be smashed")
	end
	H.check(titanWall.CanCollide, "titan intact")
	H.check(math.abs(slingshot.SimVelocity.X) <= 30 * PhysicsConfig.WallSlideKeep + 15, "tangent reduced")
end)

H.suite("Client · spring ball")
H.test("Space in flight = spring ball; ground bounces build combo with momentum kept", function()
	slingshot:HardReset(nil)
	frames(2)
	launchFrom(Vector3.new(0, 40, -100), Vector3.new(0, -60, -80))
	local sunk = press("StretchPop_Ball")
	H.check(sunk == Enum.ContextActionResult.Sink, "space sunk in flight")
	local comboBefore = slingshot:GetCombo()
	frames(120)
	H.check(slingshot.BallActive, "ball active")
	H.check(slingshot.BallPart.Transparency == 0, "ball visible")
	H.check(slingshot:GetCombo() > comboBefore and events.Bounced >= 1, "bounced: combo=" .. slingshot:GetCombo())
	local log = Engine.findLog("ArmVisual", function(entry)
		return entry.Args[1] == "Ball"
	end)
	H.check(log and log.Args[2] == true, "ball replicated to peers")
	release("StretchPop_Ball")
	frames(2)
	H.check(not slingshot.BallActive, "ball off after release")
end)
H.test("Space on the ground is passed through (normal jump)", function()
	slingshot:HardReset(CFrame.new(0, 3, 0))
	humanoid.FloorMaterial = Enum.Material.Plastic
	frames(2)
	local result = press("StretchPop_Ball")
	H.check(result == Enum.ContextActionResult.Pass, "jump must pass to the default controls")
	release("StretchPop_Ball")
end)

H.suite("Client · air grapple (bungee)")
H.test("holding in the air pulls toward the anchor", function()
	launchFrom(Vector3.new(-16, 50, 10), Vector3.new(0, 0, 0))
	aimAt(leftRing.Position)
	frames(1)
	press("StretchPop_LeftArm")
	frames(12)
	H.check(slingshot.Hands.Left.Phase == "Attached", "attached in air")
	local before = (root.CFrame.Position - leftRing.Position).Magnitude
	frames(40)
	local after = (root.CFrame.Position - leftRing.Position).Magnitude
	H.check(after < before - 8, string.format("pulled in: %.1f → %.1f", before, after))
	local visible = 0
	for _, beam in slingshot.TrajectoryBeams do
		if beam.Enabled then
			visible += 1
		end
	end
	H.check(visible >= 1, "release preview visible while grappling")
	release("StretchPop_LeftArm")
	frames(2)
	H.check(slingshot.Hands.Left.Phase == "Retracting" or slingshot.Hands.Left.Phase == "Idle", "released")
end)

H.suite("Client · gong")
H.test("hitting own gong sends GongStrike(slot, velocity, speed, combo)", function()
	slingshot:HardReset(nil)
	launchFrom(Vector3.new(0, 24, -900), Vector3.new(0, 0, -260))
	local sent = nil
	for _ = 1, 60 do
		frames(1)
		sent = Engine.findLog("GongStrike")
		if sent then
			break
		end
	end
	H.check(sent ~= nil, "GongStrike must be sent")
	H.check(sent.Args[1] == 1 and sent.Args[3] > 200, "slot/speed")
	H.check(events.Gong == 1, "GongStruck signal")
	H.check(slingshot.SimVelocity.Z > 0, "bounced back off the gong")
end)

H.suite("Client · resets & peers")
H.test("ControllerReset from server aborts custom physics and teleports", function()
	Engine.remote("ControllerReset").OnClientEvent:Fire(CFrame.new(5, 3, 5))
	frames(1)
	H.check(slingshot:GetState() == "Walk", "walk after reset")
	H.check((root.CFrame.Position - Vector3.new(5, 3, 5)).Magnitude < 0.01, "teleported")
end)
H.test("peer arm visuals render for other players", function()
	local other = Instance.new("Player")
	other.Name = "Peer"
	other.UserId = 555
	other.Parent = players
	Engine.buildCharacter(other, CFrame.new(40, 3, 0))
	Engine.remote("PeerArmVisual").OnClientEvent:Fire(other, "Right", true, Vector3.new(40, 30, -40))
	frames(2)
	local peer = slingshot.Peers[other]
	H.check(peer and peer.Hands.Right.Rig.MainA.Enabled, "peer right arm visible")
	Engine.remote("PeerArmVisual").OnClientEvent:Fire(other, "Right", false, nil)
	frames(1)
	H.check(not peer.Hands.Right.Rig.MainA.Enabled, "peer arm hidden after release")
end)
H.test("death unbinds and hides everything", function()
	humanoid.Died:Fire()
	frames(2)
	H.check(slingshot.Character == nil and slingshot:GetState() == "Walk", "unbound")
	H.check(not slingshot.Hands.Left.Rig.MainA.Enabled, "rig hidden")
end)
H.suite("Client · camera & level client (smoke)")
H.test("ShoulderCamera: locks mouse, follows character, reacts to speed, shakes", function()
	local camInstance = Instance.new("Camera")
	camInstance.Parent = workspace
	workspace.CurrentCamera = camInstance
	local UserInputService = game:GetService("UserInputService")
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIcon = ""
	game:GetService("GuiService").MenuIsOpen = false
	local character2, root2 = Engine.buildCharacter(player, CFrame.new(0, 3, 0))
	slingshot:BindCharacter(character2)
	local ShoulderCamera = H.require("StarterPlayer.StarterPlayerScripts.Client.Controllers.ShoulderCameraController")
	local shoulder = ShoulderCamera.new()
	shoulder:Start()
	shoulder:SetSpeed(300)
	shoulder:AddTrauma(0.8)
	shoulder:Kick(10)
	frames(30)
	H.check(camInstance.CameraType == Enum.CameraType.Scriptable, "scriptable camera")
	H.check(UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter, "mouse locked to center")
	local distance = (camInstance.CFrame.Position - root2.CFrame.Position).Magnitude
	H.check(distance > 6 and distance < 30, "camera behind the character: " .. distance)
	H.check(camInstance.FieldOfView > 72, "FOV widens with speed: " .. camInstance.FieldOfView)
	local origin, direction = shoulder:GetAimRay()
	H.check(origin == camInstance.CFrame.Position and math.abs(direction.Magnitude - 1) < 1e-4, "aim ray")
	shoulder:Destroy()
end)
H.test("KineticLevelClient: rebirth wave + gong verdict + others' smash VFX", function()
	local lanes = Instance.new("Folder")
	lanes.Name = "Lanes"
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "StretchPopWorld"
	lanes.Parent = worldFolder
	worldFolder.Parent = workspace
	local lane = Instance.new("Model")
	lane.Name = "Lane_1"
	lane.Parent = lanes
	local mutable = Instance.new("Folder")
	mutable.Name = "Mutable"
	mutable.Parent = lane
	local disc = Engine.newPart("GongDisc", Vector3.new(2.6, 34, 34), CFrame.new(0, 24, -768), mutable)
	player:SetAttribute("LaneSlot", 1)
	player:SetAttribute("LocationTier", 0)
	local LevelClient = H.require("StarterPlayer.StarterPlayerScripts.Client.Controllers.KineticLevelClient")
	LevelClient.Start()
	H.check(game:GetService("Lighting"):FindFirstChild("StretchPopTierTint") ~= nil, "tier tint effect")
	local fxFolder = KineticVFX.GetFolder()
	Engine.remote("RebirthWave").OnClientEvent:Fire({
		Slot = 1,
		OwnerUserId = player.UserId,
		Tier = 1,
		LaneOrigin = CFrame.new(),
		OriginZ = -800,
		EndZ = 66,
		Speed = 420,
		StartServerTime = Engine.time + 0.2,
		LaneWidth = 92,
	})
	frames(30)
	local wavePlane = nil
	for _, child in fxFolder:GetChildren() do
		if child:IsA("BasePart") and math.abs(child.Size.X - (92 + 60)) < 1e-3 then
			wavePlane = child
		end
	end
	H.check(wavePlane ~= nil, "wave plane spawned")
	H.check(wavePlane:FindFirstChildOfClass("ParticleEmitter") ~= nil, "wave sparkles")
	local localZ = wavePlane.CFrame.Position.Z
	H.check(localZ > -800 and localZ < 66, "front moves along the lane by server time: z=" .. localZ)
	Engine.remote("GongResult").OnClientEvent:Fire(false, "too_slow", 140, 2, 90, 1)
	Engine.remote("GongResult").OnClientEvent:Fire(true, "rebirth", 140, 2, 180, 3)
	Engine.remote("ObstacleSmashed").OnClientEvent:Fire(
		12345,
		2,
		"T0-5",
		{ CFrame = CFrame.new(0, 10, -20), Size = Vector3.new(30, 20, 4), Color = roblox.Color3.new(1, 0.5, 0), Material = Enum.Material.WoodPlanks, Kind = "Chest" },
		Vector3.new(0, 10, -18),
		Vector3.new(0, 0, -150)
	)
	frames(240)
	H.check(disc.Parent == mutable, "gong untouched")
end)

-- ── Шаг 3: HUD и звук ──────────────────────────────────────────────────────
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(1600, 900)
local UserInputService = game:GetService("UserInputService")
UserInputService.MouseIconEnabled = false
UserInputService.GamepadEnabled = false
character, root, humanoid = Engine.buildCharacter(player, CFrame.new(0, 3, 0))
slingshot:BindCharacter(character)
local HUD = H.require("StarterPlayer.StarterPlayerScripts.Client.Controllers.StretchHUDController")
local Audio = H.require("StarterPlayer.StarterPlayerScripts.Client.Controllers.StretchAudioController")
local hud = HUD.new(slingshot, camera :: any)
hud:Start()
local audio = Audio.new(slingshot, camera :: any, hud)
audio:Start()
frames(2)

local function countLit(): number
	local lit = 0
	for _, segment in hud.Segments do
		if segment.Lit then
			lit += 1
		end
	end
	return lit
end

H.suite("Client · spring cartoon HUD")
H.test("whole UI is built in code: FredokaOne, thick UIStroke, juicy UIGradient", function()
	local gui = playerGui:FindFirstChild("StretchPopHUD")
	H.check(gui and gui:IsA("ScreenGui") and gui.ResetOnSpawn == false and gui.IgnoreGuiInset, "screen gui")
	H.check(#hud.Segments == 32, "tension ring segments")
	local strokes, gradients, texts = 0, 0, 0
	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("UIStroke") then
			strokes += 1
		elseif descendant:IsA("UIGradient") then
			gradients += 1
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			texts += 1
			H.check(descendant.Font == Enum.Font.FredokaOne, "font of " .. descendant:GetFullName())
		end
	end
	H.check(strokes > 40 and gradients > 20 and texts > 20, string.format("strokes=%d gradients=%d texts=%d", strokes, gradients, texts))
	H.near(hud.RootScale.Scale, 1, 1e-6, "UIScale at 900px")
	workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(1280, 720)
	frames(1)
	H.near(hud.RootScale.Scale, 0.8, 1e-6, "UIScale at 720px")
	workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(1600, 900)
	frames(1)
end)
H.test("tension ring fills from TensionChanged, jitters at 100%, empties on release", function()
	slingshot.Signals.TensionChanged:Fire(1)
	frames(45)
	H.check(countLit() == 32, "all lit: " .. countLit())
	local jitter = 0
	for _ = 1, 20 do
		frames(1)
		local position = hud.Reticle.Position
		jitter = math.max(jitter, math.abs(position.X.Offset), math.abs(position.Y.Offset))
	end
	H.check(jitter > 0.3, "reticle shakes at full tension: " .. jitter)
	slingshot.Signals.TensionChanged:Fire(0.5)
	frames(45)
	H.check(countLit() >= 14 and countLit() <= 18, "half tension ≈ half ring: " .. countLit())
	slingshot.Signals.TensionChanged:Fire(0)
	frames(60)
	H.check(countLit() == 0, "ring empty: " .. countLit())
end)
H.test("speedometer springs to the real speed; 260+ turns on neon and flames", function()
	launchFrom(Vector3.new(0, 150, 100), Vector3.new(320, 0, 0))
	frames(30)
	local shown = tonumber(hud.SpeedText.Text) or 0
	H.check(shown > PhysicsConfig.SupersonicSpeed, "speed shown: " .. hud.SpeedText.Text)
	H.check(hud.Neon and hud.SupersonicLabel.Visible and hud.FlameHolder.Visible, "neon + SUPERSONIC + flames")
	H.check(hud.NeedlePivot.Rotation > 300, "needle swung: " .. hud.NeedlePivot.Rotation)
	slingshot:HardReset(CFrame.new(0, 3, 0))
	frames(120)
	H.check(not hud.Neon and not hud.FlameHolder.Visible, "neon off when stopped")
	H.check(hud.NeedlePivot.Rotation < 200, "needle back: " .. hud.NeedlePivot.Rotation)
end)
H.test("combo counter pops on every hit and hides after reset", function()
	slingshot.Combo = 3
	frames(90)
	H.check(hud.ComboText.Text == "x3" and hud.Combo.Visible, "combo x3 visible")
	local settled = hud.ComboScale.Scale
	H.check(math.abs(settled - 1) < 0.05, "settled scale " .. settled)
	slingshot.Combo = 4
	local peak = settled
	for _ = 1, 12 do
		frames(1)
		peak = math.max(peak, hud.ComboScale.Scale)
	end
	H.check(hud.ComboText.Text == "x4" and peak > settled + 0.08, string.format("pop on hit: %.3f → %.3f", settled, peak))
	frames(90)
	H.check(math.abs(hud.ComboScale.Scale - 1) < 0.05, "spring settles back")
	slingshot.Combo = 0
	frames(90)
	H.check(not hud.Combo.Visible, "hidden after reset")
end)
H.test("3D popups of speed and loot fly on a parabola and expire", function()
	local folder = playerGui:FindFirstChild("StretchPopPopups")
	slingshot.Signals.Smashed:Fire("Wall", 187.4, Vector3.new(0, 10, -50))
	slingshot.Signals.LootGained:Fire(40)
	frames(1)
	local texts = {}
	for _, gui in folder:GetChildren() do
		table.insert(texts, gui:FindFirstChild("Text").Text)
	end
	H.check(table.find(texts, "187!") ~= nil and table.find(texts, "+40") ~= nil, "popups: " .. table.concat(texts, ", "))
	local popup = nil
	for _, candidate in hud.Popups do
		if candidate.Label.Text == "187!" then
			popup = candidate
		end
	end
	H.check(popup ~= nil, "speed popup tracked")
	local y0 = popup.Attachment.WorldCFrame.Position.Y
	frames(15)
	local y1 = popup.Attachment.WorldCFrame.Position.Y
	frames(15)
	local y2 = popup.Attachment.WorldCFrame.Position.Y
	H.check(y1 > y0 and (y2 - y1) < (y1 - y0), "rises, then gravity bends the path")
	frames(90)
	H.check(#folder:GetChildren() == 0 and #hud.Popups == 0, "expired")
end)
H.test("gong failure banner says exactly what was missing", function()
	Engine.remote("GongResult").OnClientEvent:Fire(false, "too_slow", 140, 2, 112, 1)
	frames(20)
	local subtitle = hud.Banner.Subtitle.Text
	H.check(hud.Banner.Root.Visible, "banner visible")
	H.check(string.find(subtitle, "+28", 1, true) ~= nil and string.find(subtitle, "+1 комбо", 1, true) ~= nil, "deficits: " .. subtitle)
	frames(260)
	H.check(not hud.Banner.Root.Visible, "banner hides")
end)
H.test("rebirth banner celebrates the new tier", function()
	Engine.remote("RebirthWave").OnClientEvent:Fire({
		Slot = 1,
		OwnerUserId = player.UserId,
		Tier = 1,
		LaneOrigin = CFrame.new(),
		OriginZ = -800,
		EndZ = 66,
		Speed = 420,
		StartServerTime = Engine.time + 0.2,
		LaneWidth = 92,
	})
	frames(10)
	H.check(hud.Banner.Title.Text == "REBIRTH!", "title")
	H.check(string.find(hud.Banner.Subtitle.Text, "Golden", 1, true) ~= nil, "subtitle: " .. hud.Banner.Subtitle.Text)
	H.check(hud.Banner.Rays.Visible, "celebration rays")
	frames(300)
end)
H.test("Tab opens the springy panel, frees the cursor, asks for ProfileSync", function()
	local count = #Engine.remoteLog
	H.check(input("StretchPop_TogglePanel", Enum.UserInputState.Begin) == Enum.ContextActionResult.Sink, "Tab sunk")
	frames(5)
	local early = hud.PanelScale.Scale
	frames(40)
	H.check(hud.PanelOpen and hud.Panel.Visible and camera.Free, "open + cursor free")
	H.check(early < hud.PanelScale.Scale + 0.3 and math.abs(hud.PanelScale.Scale - 1) < 0.05, "spring settles at 1")
	H.check(UserInputService.MouseIconEnabled, "system cursor visible for clicking")
	local requested = false
	for index = count + 1, #Engine.remoteLog do
		if Engine.remoteLog[index].Remote == "ProfileSync" then
			requested = true
		end
	end
	H.check(requested, "ProfileSync requested")
	H.check(input("StretchPop_LeftArm", Enum.UserInputState.Begin) == Enum.ContextActionResult.Pass, "LMB goes to UI, not the arm")
	input("StretchPop_LeftArm", Enum.UserInputState.End)
end)
H.test("stat card: Derive preview, poor click refused locally, rich click upgrades via server", function()
	player:SetAttribute("Coins", 0)
	player:SetAttribute("Stat_Elasticity", 0)
	frames(2)
	local card = hud.StatCards.Elasticity
	H.check(string.find(card.Preview.Text, "→", 1, true) ~= nil, "preview: " .. card.Preview.Text)
	local count = #Engine.remoteLog
	Engine.signalFor(card.Button, "Activated"):Fire()
	H.check(#Engine.remoteLog == count, "no request without coins")
	H.check(card.Message.Visible and string.find(card.Message.Text, "монет", 1, true) ~= nil, "refusal: " .. card.Message.Text)
	player:SetAttribute("Coins", 1000)
	frames(2)
	Engine.signalFor(card.Button, "Activated"):Fire()
	local request = Engine.findLog("UpgradeStat", function(entry)
		return entry.Kind == "FireServer"
	end)
	H.check(request ~= nil and request.Args[1] == "Elasticity", "UpgradeStat sent")
	H.check(card.Cost.Text == "...", "pending state")
	player:SetAttribute("Stat_Elasticity", 1)
	player:SetAttribute("Coins", 970)
	Engine.remote("UpgradeStat").OnClientEvent:Fire("Elasticity", true, "upgraded", 1, 970)
	frames(3)
	H.check(string.find(card.Message.Text, "1", 1, true) ~= nil and card.Level.Text == "Lv 1", "upgraded: " .. card.Level.Text)
end)
H.test("glove shop: expensive refused, buy request, confirmed purchase shows equipped", function()
	local card = hud.GloveCards.VoidFist
	player:SetAttribute("Coins", 10)
	frames(2)
	Engine.signalFor(card.Button, "Activated"):Fire()
	H.check(card.Message.Visible, "too expensive locally")
	player:SetAttribute("Coins", 300000)
	frames(2)
	Engine.signalFor(card.Button, "Activated"):Fire()
	local request = Engine.findLog("GloveAction", function(entry)
		return entry.Kind == "FireServer"
	end)
	H.check(request ~= nil and request.Args[1] == "Buy" and request.Args[2] == "VoidFist", "buy request")
	Engine.remote("GloveAction").OnClientEvent:Fire("Buy", "VoidFist", true, "bought")
	player:SetAttribute("Glove", "VoidFist")
	hud.PanelDirty = true
	frames(3)
	H.check(card.Button.Text == "НАДЕТО", "equipped: " .. card.Button.Text)
	H.check(hud.GloveCards.Rubber.Button.Text == "НАДЕТЬ", "owned classic offers equip: " .. hud.GloveCards.Rubber.Button.Text)
	Engine.signalFor(hud.GloveCards.Rubber.Button, "Activated"):Fire()
	local equip = Engine.findLog("GloveAction", function(entry)
		return entry.Kind == "FireServer"
	end)
	H.check(equip.Args[1] == "Equip" and equip.Args[2] == "Rubber", "equip request")
end)
H.test("records arrive via ProfileSync; Tab closes the panel and relocks the cursor", function()
	Engine.remote("ProfileSync").OnClientEvent:Fire({
		Coins = 300000,
		Stats = { Elasticity = 1, SpringPower = 0, SmashMass = 0 },
		OwnedGloves = { "Rubber", "VoidFist" },
		EquippedGlove = "VoidFist",
		Records = { TopSpeed = 312.4, LongestCombo = 14, WallsSmashed = 120, ChestsOpened = 33, LootEarned = 9999 },
		Locations = {},
		ActiveLocation = "Meadows",
		TotalRebirths = 2,
		DataOffline = true,
		ServerTime = 0,
	})
	frames(2)
	H.check(string.find(hud.RecordsText.Text, "312", 1, true) ~= nil and string.find(hud.RecordsText.Text, "14", 1, true) ~= nil, "records: " .. hud.RecordsText.Text)
	H.check(hud.OfflineText.Text ~= "", "offline notice")
	input("StretchPop_TogglePanel", Enum.UserInputState.Begin)
	frames(120)
	H.check(not hud.PanelOpen and not hud.Panel.Visible and not camera.Free, "closed + cursor locked")
	H.check(UserInputService.MouseIconEnabled == false, "own reticle instead of system cursor")
end)

H.suite("Client · procedural audio")
H.test("audio graph: voices per SoundConfig slot, groups, Reverb + Echo on resonance", function()
	local soundService = game:GetService("SoundService")
	local folder = soundService:FindFirstChild("StretchPopAudio")
	local voices = 0
	for _, def in SoundConfig.Sounds do
		voices += if def.Looped then 1 else def.Voices
	end
	H.check(folder and #folder:GetChildren() == voices, "voices: " .. (if folder then #folder:GetChildren() else -1) .. " / " .. voices)
	local resonance = soundService:FindFirstChild("StretchPop_Resonance")
	H.check(resonance and resonance:FindFirstChildOfClass("ReverbSoundEffect") and resonance:FindFirstChildOfClass("EchoSoundEffect"), "reverb + echo")
	H.check(audio.StretchLoop.Sound.Looped and audio.StretchLoop.Equalizer ~= nil, "stretch loop with EQ filter")
	for _, sound in folder:GetChildren() do
		H.check(string.sub(sound.SoundId, 1, 9) == "rbxasset:" or string.sub(sound.SoundId, 1, 13) == "rbxassetid://", "asset id " .. sound.SoundId)
	end
end)
H.test("tension drives rubber loop pitch / volume / EQ and granular creaks", function()
	slingshot:HardReset(CFrame.new(0, 3, 0))
	humanoid.FloorMaterial = Enum.Material.Plastic
	frames(2)
	slingshot:EnterCustom("Charge", Vector3.zero)
	local logIndex = #Engine.soundLog
	slingshot.Signals.TensionChanged:Fire(1)
	frames(60)
	local loop = audio.StretchLoop
	H.check(loop.Playing and Engine.isPlaying(loop.Sound), "loop playing")
	H.near(loop.Sound.PlaybackSpeed, SoundConfig.Sounds.StretchLoop.Pitch * SoundConfig.Tension.PitchMax, 0.03, "pitch at full tension")
	H.check(loop.Equalizer.HighGain > -2, "filter opened: " .. loop.Equalizer.HighGain)
	H.check(#Engine.soundsSince(logIndex, "Creak") >= 12, "granular creaks: " .. #Engine.soundsSince(logIndex, "Creak"))
	slingshot.Signals.TensionChanged:Fire(0.3)
	frames(60)
	H.check(loop.Sound.PlaybackSpeed < SoundConfig.Tension.PitchMax * 0.9, "pitch drops with tension")
	slingshot.Signals.TensionChanged:Fire(0)
	frames(90)
	H.check(not loop.Playing and not Engine.isPlaying(loop.Sound), "loop stops")
	slingshot:HardReset(CFrame.new(0, 3, 0))
end)
H.test("launch snap, then wind louder and higher with speed", function()
	local logIndex = #Engine.soundLog
	slingshot.Signals.Launched:Fire(220, Vector3.new(0, 0, -220))
	H.check(#Engine.soundsSince(logIndex, "Snap") == 1, "snap")
	launchFrom(Vector3.new(0, 300, 100), Vector3.new(150, 0, 0))
	frames(40)
	local slowPitch = audio.WindLoop.Sound.PlaybackSpeed
	local slowVolume = audio.WindLoop.Sound.Volume
	H.check(audio.WindLoop.Playing and slowVolume > 0, "wind on in flight")
	slingshot:HardReset(CFrame.new(0, 3, 0))
	frames(2)
	launchFrom(Vector3.new(0, 300, 100), Vector3.new(400, 0, 0))
	frames(40)
	H.check(audio.WindLoop.Sound.PlaybackSpeed > slowPitch * 1.3, "higher pitch")
	H.check(audio.WindLoop.Sound.Volume > slowVolume * 1.5, "louder")
	slingshot:HardReset(CFrame.new(0, 3, 0))
	frames(150)
	H.check(not audio.WindLoop.Playing, "wind fades out on the ground")
end)
H.test("bounce notes climb the major pentatonic with the combo", function()
	local logIndex = #Engine.soundLog
	for combo = 1, 6 do
		slingshot.Signals.Bounced:Fire(combo, 260, Vector3.zero)
	end
	local notes = Engine.soundsSince(logIndex, "Bounce")
	H.check(#notes == 6, "notes: " .. #notes)
	local semitones = { 0, 2, 4, 7, 9, 12 }
	local base = notes[1].Speed
	for index, entry in notes do
		local expected = 2 ^ (semitones[index] / 12)
		H.check(math.abs(entry.Speed / base / expected - 1) < 0.045, string.format("note %d ratio %.3f vs %.3f", index, entry.Speed / base, expected))
	end
end)
H.test("gong: deep hit in the reverb group, success strums a major chord", function()
	local logIndex = #Engine.soundLog
	slingshot.Signals.GongStruck:Fire(220, 3)
	local hits = Engine.soundsSince(logIndex, "Gong")
	H.check(#hits == 2 and hits[1].Group == "StretchPop_Resonance", "gong + layer through resonance")
	H.check(hits[1].Speed < 0.6, "deep: " .. hits[1].Speed)
	Engine.remote("GongResult").OnClientEvent:Fire(true, "rebirth", 140, 2, 220, 3)
	frames(20)
	local all = Engine.soundsSince(logIndex, "Gong")
	H.check(#all >= 2 + #SoundConfig.GongChord, "chord notes: " .. #all)
end)
H.test("rebirth wave: pitch sweep rises across the whole wave, finale arpeggio", function()
	local logIndex = #Engine.soundLog
	Engine.remote("RebirthWave").OnClientEvent:Fire({
		Slot = 1,
		OwnerUserId = player.UserId,
		Tier = 2,
		LaneOrigin = CFrame.new(),
		OriginZ = -800,
		EndZ = 66,
		Speed = 420,
		StartServerTime = Engine.time + 0.3,
		LaneWidth = 92,
	})
	frames(30)
	local sweep = audio.Sweeps[1]
	H.check(sweep ~= nil and sweep.Started, "sweep started")
	local first = sweep.Voice.Sound.PlaybackSpeed
	frames(60)
	H.check(sweep.Voice.Sound.PlaybackSpeed > first, "pitch rises")
	frames(200)
	H.check(#audio.Sweeps == 0, "sweep finished")
	H.check(#Engine.soundsSince(logIndex, "Coin") >= 8, "finale arpeggio")
end)
H.test("UI sounds follow HUD signals (click, purchase arpeggio, error)", function()
	local logIndex = #Engine.soundLog
	hud.Signals.UiClick:Fire()
	hud.Signals.Purchase:Fire(true, "upgraded")
	hud.Signals.Purchase:Fire(false, "not_enough_coins")
	frames(30)
	H.check(#Engine.soundsSince(logIndex, "UiClick") == 1, "click")
	H.check(#Engine.soundsSince(logIndex, "Coin") >= #SoundConfig.Arpeggio, "arpeggio")
	H.check(#Engine.soundsSince(logIndex, "UiError") == 1, "error buzz")
end)

H.test("no runtime errors inside VFX effects or signals", function()
	for _, warning in H.warnings do
		H.check(not string.find(warning, "error"), "warning: " .. warning)
	end
end)

local ok = H.summary()
process.exit(if ok then 0 else 1)
