--!strict
-- Фонарик: переключение F / ButtonY / сенсорная кнопка через ClientState.setFlashlight; SpotLight на
-- невидимой части, которая каждый кадр (RenderPriority Camera+2) повторяет CFrame камеры; тусклый
-- PointLight на голове в тёмное время, чтобы ближние объекты читались; мерцание при низком заряде.
-- Заряд принадлежит серверу (ClientState.Battery) — клиент только отражает ClientState.FlashlightOn.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Flashlight = {}

local ACTION = "Flashlight"
local RENDER_NAME = "AA_Flashlight"
local HAND_OFFSET = CFrame.new(0.35, -0.3, 0)
local DEFAULT_COLOR = Color3.fromRGB(255, 240, 205)
local HEAD_COLOR = Color3.fromRGB(215, 222, 240)

-- Косметические цвета (Settings.FlashlightColor — имя или {R,G,B} 0..255)
local PALETTE: { [string]: Color3 } = {
	Warm = DEFAULT_COLOR,
	White = Color3.fromRGB(245, 245, 255),
	Cool = Color3.fromRGB(190, 215, 255),
	Red = Color3.fromRGB(255, 120, 110),
	Green = Color3.fromRGB(150, 255, 170),
	Purple = Color3.fromRGB(210, 150, 255),
	Amber = Color3.fromRGB(255, 190, 90),
}

local player = Players.LocalPlayer
local holder: Part? = nil
local spot: SpotLight? = nil
local headLight: PointLight? = nil
local flickerTimer = 0
local flickerLevel = 1

local function parseColor(value: any): Color3
	if typeof(value) == "Color3" then
		return value
	elseif typeof(value) == "string" then
		return PALETTE[value] or DEFAULT_COLOR
	elseif typeof(value) == "table" then
		local t = value :: { [any]: any }
		local r, g, b = t.R or t[1], t.G or t[2], t.B or t[3]
		if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
			return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
		end
	end
	return DEFAULT_COLOR
end

local function isDark(): boolean
	local phase = ClientState.Snapshot.Phase
	return phase ~= "Day" and phase ~= "Dawn"
end

local function canUse(): boolean
	local s = ClientState.Status
	return s == "Alive" or s == "Lobby"
end

local function ensureHolder(): (Part, SpotLight)
	local h, l = holder, spot
	if h and h.Parent and l and l.Parent == h then
		return h, l
	end
	local part = Instance.new("Part")
	part.Name = "FlashlightHolder"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = Sounds.fxFolder()
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = Config.Flashlight.Angle
	light.Range = Config.Flashlight.Range
	light.Brightness = Config.Flashlight.Brightness
	light.Shadows = true
	light.Color = parseColor(ClientState.Settings.FlashlightColor)
	light.Enabled = false
	light.Parent = part
	holder = part
	spot = light
	return part, light
end

local function applyState()
	local _, light = ensureHolder()
	local on = ClientState.FlashlightOn and canUse() and ClientState.Battery > 0
	if light.Enabled ~= on then
		light.Enabled = on
	end
	if not on then
		flickerLevel = 1
	end
end

local function applyHeadLight()
	local l = headLight
	if l and l.Parent then
		local enabled = isDark() and (ClientState.Status ~= "Taken" and ClientState.Status ~= "Spectating")
		if l.Enabled ~= enabled then
			l.Enabled = enabled
		end
	end
end

local function bindCharacter(char: Model)
	headLight = nil
	local head = char:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") or head.Parent ~= char then
		return
	end
	local existing = head:FindFirstChild("AA_HeadLight")
	if existing then
		existing:Destroy()
	end
	local light = Instance.new("PointLight")
	light.Name = "AA_HeadLight"
	light.Range = 9
	light.Brightness = 0.35
	light.Shadows = false
	light.Color = HEAD_COLOR
	light.Enabled = false
	light.Parent = head
	headLight = light
	applyHeadLight()
end

local function toggle()
	if not canUse() then
		return
	end
	if not ClientState.FlashlightOn and ClientState.Battery <= 0 then
		-- села батарейка: только щелчок
		Sounds.playUI("FlashlightClick", 0.6)
		return
	end
	ClientState.setFlashlight(not ClientState.FlashlightOn)
end

local function onAction(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Pass
end

local function renderStep(dt: number)
	local part, light = ensureHolder()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	part.CFrame = cam.CFrame * HAND_OFFSET
	if not light.Enabled then
		return
	end
	local base = Config.Flashlight.Brightness
	if ClientState.Battery < Config.Flashlight.LowBattery then
		flickerTimer -= dt
		if flickerTimer <= 0 then
			flickerTimer = 0.04 + math.random() * 0.3
			flickerLevel = if math.random() < 0.3 then 0.1 + math.random() * 0.2 else 0.6 + math.random() * 0.4
		end
	else
		flickerLevel = 1
	end
	local target = base * flickerLevel
	if math.abs(light.Brightness - target) > 0.01 then
		light.Brightness = target
	end
end

function Flashlight.init()
	ensureHolder()

	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		headLight = nil
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	ClientState.FlashlightChanged:Connect(function(on: boolean)
		Sounds.playUI("FlashlightClick", if on then 1 else 0.8)
		applyState()
	end)
	ClientState.InventoryChanged:Connect(function()
		applyState()
	end)
	ClientState.StatusChanged:Connect(function()
		applyState()
		applyHeadLight()
	end)
	ClientState.StateChanged:Connect(function()
		applyHeadLight()
	end)
	ClientState.SettingsChanged:Connect(function(settings: { [string]: any })
		local _, light = ensureHolder()
		light.Color = parseColor(settings.FlashlightColor)
	end)

	ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle(ACTION, Locale.t("Flashlight"))
	ContextActionService:SetPosition(ACTION, UDim2.new(0.5, 0, 0.3, 0))

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, renderStep)
	applyState()
	applyHeadLight()
end

return Flashlight
