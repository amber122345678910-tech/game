--!strict
-- STRETCH-POP · Камера «из-за плеча» с захваченной мышью.
-- Нужна потому, что ПКМ занята правой рукой: стандартная камера Roblox вращается по ПКМ.
-- • Мышь в центре (крестик рисует HUD). SetMouseFree освобождает курсор — так HUD открывает
--   панель прокачки по Tab / Alt / кнопке, не споря с камерой за клавиши.
-- • Дистанция и FOV пружинят от скорости полёта (Hooke-пружины), тряска по модели trauma².
-- • Столкновение камеры со стенами через Spherecast; другие игроки и обломки игнорируются группой.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Spring = require(Shared.Math.Spring)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local RENDER_STEP_NAME = "StretchPop_ShoulderCamera"
local LOCKED_MOUSE_ICON = "rbxasset://textures/MouseLockedCursor.png"

local BASE_FOV = 70
local FOV_SPEED_BOOST = 24
local BASE_DISTANCE = 12
local SPEED_DISTANCE = 8
local SPEED_FOR_MAX_EFFECT = 420
local SHOULDER_OFFSET = 2.1
local HEIGHT_OFFSET = 1.1
local FOCUS_HEIGHT = 2.2
local MOUSE_RADIANS_PER_PIXEL = 0.0042
local GAMEPAD_YAW_RATE = 3.4
local GAMEPAD_PITCH_RATE = 2.4
local GAMEPAD_DEADZONE = 0.15
local PITCH_MIN = math.rad(-72)
local PITCH_MAX = math.rad(68)
local MAX_FOCUS_LAG = 9
local COLLISION_RADIUS = 0.7
local MIN_CAMERA_DISTANCE = 1.2
local TRAUMA_DECAY = 1.7
local SHAKE_MAX_ANGLE = math.rad(3.2)
local SHAKE_MAX_OFFSET = 0.45
local SHAKE_FREQUENCY = 22
local FOV_KICK_GAIN = 18

type CameraFields = {
	Player: Player,
	Yaw: number,
	Pitch: number,
	Distance: Spring.NumberSpring,
	Fov: Spring.NumberSpring,
	Focus: Spring.VectorSpring,
	LastFocus: Vector3,
	NeedsSnap: boolean,
	SpeedHint: number,
	Trauma: number,
	Seed: number,
	MouseFree: boolean,
	GamepadLook: Vector2,
	CastParams: RaycastParams,
	FilteredCharacter: Model?,
	Connections: { RBXScriptConnection },
	Started: boolean,
}

local ShoulderCamera = {}
ShoulderCamera.__index = ShoulderCamera

export type ShoulderCamera = typeof(setmetatable({} :: CameraFields, ShoulderCamera))

function ShoulderCamera.new(): ShoulderCamera
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.IgnoreWater = true
	castParams.RespectCanCollide = true
	castParams.CollisionGroup = PhysicsConfig.CollisionGroups.Characters

	local fields: CameraFields = {
		Player = Players.LocalPlayer,
		Yaw = 0,
		Pitch = math.rad(-12),
		Distance = Spring.Number.new(BASE_DISTANCE, 2.2, 0.9),
		Fov = Spring.Number.new(BASE_FOV, 3, 0.55),
		Focus = Spring.Vector.new(Vector3.zero, 9, 1),
		LastFocus = Vector3.zero,
		NeedsSnap = true,
		SpeedHint = 0,
		Trauma = 0,
		Seed = math.random() * 100,
		MouseFree = false,
		GamepadLook = Vector2.zero,
		CastParams = castParams,
		FilteredCharacter = nil,
		Connections = {},
		Started = false,
	}
	return setmetatable(fields, ShoulderCamera)
end

function ShoulderCamera.SetSpeed(self: ShoulderCamera, speed: number)
	self.SpeedHint = speed
end

-- Тряска: trauma ∈ [0,1], визуально — trauma² (мелкие удары почти не трясут, крупные — сильно)
function ShoulderCamera.AddTrauma(self: ShoulderCamera, amount: number)
	self.Trauma = math.clamp(self.Trauma + amount, 0, 1)
end

-- Импульс FOV в градусах (пружина сама вернёт обратно с мультяшным перелётом)
function ShoulderCamera.Kick(self: ShoulderCamera, degrees: number)
	self.Fov:Impulse(degrees * FOV_KICK_GAIN)
end

function ShoulderCamera.GetAimRay(self: ShoulderCamera): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	local cframe = camera.CFrame
	return cframe.Position, cframe.LookVector
end

function ShoulderCamera.GetFlatLook(self: ShoulderCamera): Vector3
	return Vector3.new(-math.sin(self.Yaw), 0, -math.cos(self.Yaw))
end

function ShoulderCamera.IsMouseFree(self: ShoulderCamera): boolean
	return self.MouseFree
end

-- Освободить (true) или снова захватить (false) курсор. Пока курсор свободен, камера не крутится,
-- а клики ЛКМ/ПКМ уходят в интерфейс (контроллер рогатки пропускает их).
function ShoulderCamera.SetMouseFree(self: ShoulderCamera, free: boolean)
	self.MouseFree = free
end

-- Развернуть камеру за спину по направлению взгляда персонажа (спавн, телепорт).
function ShoulderCamera.SnapBehind(self: ShoulderCamera, lookVector: Vector3)
	local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flat.Magnitude > 1e-3 then
		flat = flat.Unit
		self.Yaw = math.atan2(-flat.X, -flat.Z)
	end
	self.Pitch = math.rad(-12)
	self.NeedsSnap = true
end

function ShoulderCamera.Update(self: ShoulderCamera, dt: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Ввод: мышь (захвачена в центре) и правый стик геймпада
	local free = self.MouseFree or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil
	if free then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if UserInputService.MouseIcon ~= "" then
			UserInputService.MouseIcon = ""
		end
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		if UserInputService.MouseIcon ~= LOCKED_MOUSE_ICON then
			UserInputService.MouseIcon = LOCKED_MOUSE_ICON
		end
		local delta = UserInputService:GetMouseDelta()
		local sensitivity = UserGameSettings.MouseSensitivity
		self.Yaw -= delta.X * MOUSE_RADIANS_PER_PIXEL * sensitivity
		self.Pitch -= delta.Y * MOUSE_RADIANS_PER_PIXEL * sensitivity
	end
	local stick = self.GamepadLook
	if not free and stick.Magnitude > GAMEPAD_DEADZONE then
		self.Yaw -= stick.X * GAMEPAD_YAW_RATE * dt
		self.Pitch += stick.Y * GAMEPAD_PITCH_RATE * dt
	end
	self.Pitch = math.clamp(self.Pitch, PITCH_MIN, PITCH_MAX)
	self.Yaw %= 2 * math.pi

	-- Фокус: пружинное следование за корнем персонажа с ограничением отставания
	local character = self.Player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character and root and root:IsA("BasePart") then
		if self.FilteredCharacter ~= character then
			self.FilteredCharacter = character
			self.CastParams.FilterDescendantsInstances = { character }
		end
		local target = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
		if self.NeedsSnap then
			self.NeedsSnap = false
			self.Focus:Snap(target)
		end
		self.Focus.Target = target
		self.Focus:Update(dt)
		local lag = self.Focus.Position - target
		if lag.Magnitude > MAX_FOCUS_LAG then
			self.Focus.Position = target + lag.Unit * MAX_FOCUS_LAG
		end
		self.LastFocus = self.Focus.Position
	end
	local focus = self.LastFocus

	-- Скорость → дальше и шире (ощущение разгона)
	local speedAlpha = math.clamp(self.SpeedHint / SPEED_FOR_MAX_EFFECT, 0, 1)
	self.Distance.Target = BASE_DISTANCE + SPEED_DISTANCE * speedAlpha
	self.Fov.Target = BASE_FOV + FOV_SPEED_BOOST * speedAlpha ^ 0.8
	local distance = self.Distance:Update(dt)
	local fov = self.Fov:Update(dt)

	local rotation = CFrame.fromEulerAnglesYXZ(self.Pitch, self.Yaw, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(SHOULDER_OFFSET, HEIGHT_OFFSET, distance))
	local position = focus + offset
	local hit = workspace:Spherecast(focus, COLLISION_RADIUS, offset, self.CastParams)
	if hit then
		position = focus + offset.Unit * math.max(hit.Distance - 0.2, MIN_CAMERA_DISTANCE)
	end

	-- Тряска (шум Перлина, затухание trauma)
	local shake = self.Trauma * self.Trauma
	local cframe = CFrame.new(position) * rotation
	if shake > 1e-4 then
		local t = os.clock() * SHAKE_FREQUENCY
		local seed = self.Seed
		local shakeRotation = CFrame.Angles(
			SHAKE_MAX_ANGLE * shake * math.noise(t, 1.3, seed),
			SHAKE_MAX_ANGLE * shake * math.noise(t, 7.1, seed),
			SHAKE_MAX_ANGLE * 0.6 * shake * math.noise(t, 13.7, seed)
		)
		local shakeOffset = Vector3.new(math.noise(t, 21.3, seed), math.noise(t, 31.9, seed), 0) * (SHAKE_MAX_OFFSET * shake)
		cframe = cframe * CFrame.new(shakeOffset) * shakeRotation
	end
	self.Trauma = math.max(0, self.Trauma - TRAUMA_DECAY * dt)

	camera.CFrame = cframe
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = math.clamp(fov, 40, 115)
end

function ShoulderCamera.Start(self: ShoulderCamera)
	if self.Started then
		return
	end
	self.Started = true

	table.insert(
		self.Connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				self.GamepadLook = Vector2.new(input.Position.X, input.Position.Y)
			end
		end)
	)
	table.insert(
		self.Connections,
		self.Player.CharacterAdded:Connect(function(character: Model)
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if root and root:IsA("BasePart") then
				self:SnapBehind(root.CFrame.LookVector)
			end
		end)
	)

	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		self:Update(dt)
	end)
end

function ShoulderCamera.Destroy(self: ShoulderCamera)
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIcon = ""
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	self.Started = false
end

return ShoulderCamera
