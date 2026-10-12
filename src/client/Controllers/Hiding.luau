--!strict
-- Укрытие (статус Hiding): камера переходит в CamPoint укрытия с небольшим обзором (±25° по горизонтали,
-- ±15° по вертикали — мышь, палец, правый стик), звук приглушается EqualizerSoundEffect на группах SFX и
-- Ambience, удержание E / ButtonA / сенсорной кнопки шлёт HoldBreath(true/false). Короткое нажатие той же
-- клавиши — выход из укрытия (модуль Interaction), поэтому HoldBreath(true) уходит после 0.25 с удержания.
-- При выходе камера и эквалайзер возвращаются. Значение дыхания интерфейс читает из ClientState.Breath.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Hiding = {}

local ACTION_BREATH = "HoldBreath"
local RENDER_NAME = "AA_Hiding"
local YAW_LIMIT = math.rad(25)
local PITCH_LIMIT = math.rad(15)
local MOUSE_SENS = 0.0025
local TOUCH_SENS = 0.004
local PAD_SPEED = 1.8 -- рад/с
local HOLD_DELAY = 0.25 -- секунд удержания до начала задержки дыхания
local MUFFLE_HIGH = -35
local MUFFLE_MID = -15
local MUFFLE_TIME = 0.4
local MUFFLED_GROUPS: { Sounds.GroupName } = { "SFX", "Ambience" }

local active = false
local activeHideId: string? = nil
local useScriptable = false
local baseCFrame = CFrame.identity
local yaw, pitch = 0, 0
local padLook = Vector2.zero
local conns: { RBXScriptConnection } = {}

local pressed = false
local holdToken = 0
local holdingSent = false

local function getEq(group: Sounds.GroupName): EqualizerSoundEffect
	local g = Sounds.group(group)
	local existing = g:FindFirstChild("HideMuffle")
	if existing and existing:IsA("EqualizerSoundEffect") then
		return existing
	end
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = "HideMuffle"
	eq.HighGain = 0
	eq.MidGain = 0
	eq.LowGain = 0
	eq.Parent = g
	return eq
end

local function setMuffle(on: boolean)
	for _, group in MUFFLED_GROUPS do
		local eq = getEq(group)
		TweenService:Create(eq, TweenInfo.new(MUFFLE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			HighGain = if on then MUFFLE_HIGH else 0,
			MidGain = if on then MUFFLE_MID else 0,
		}):Play()
	end
end

local function findCamPoint(hideId: string?): CFrame?
	if not hideId then
		return nil
	end
	local house = workspace:FindFirstChild("House")
	local spots = if house then house:FindFirstChild("HidingSpots") else nil
	local spot = if spots then spots:FindFirstChild(hideId) else nil
	if not spot then
		return nil
	end
	local cam = spot:FindFirstChild("CamPoint")
	if cam and cam:IsA("BasePart") then
		return cam.CFrame
	end
	local hidePoint = spot:FindFirstChild("HidePoint")
	if hidePoint and hidePoint:IsA("BasePart") then
		return hidePoint.CFrame * CFrame.new(0, 1.5, 0)
	end
	return nil
end

local function clampLook()
	yaw = math.clamp(yaw, -YAW_LIMIT, YAW_LIMIT)
	pitch = math.clamp(pitch, -PITCH_LIMIT, PITCH_LIMIT)
end

local function renderStep(dt: number)
	if padLook.Magnitude > 0.15 then
		yaw -= padLook.X * PAD_SPEED * dt
		pitch += padLook.Y * PAD_SPEED * dt
		clampLook()
	end
	Camera.setScriptable(baseCFrame * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))
	if UserInputService.MouseEnabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

local function onInputChanged(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * MOUSE_SENS
		pitch -= input.Delta.Y * MOUSE_SENS
		clampLook()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if gameProcessed then
			return
		end
		yaw -= input.Delta.X * TOUCH_SENS
		pitch -= input.Delta.Y * TOUCH_SENS
		clampLook()
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		padLook = Vector2.new(input.Position.X, input.Position.Y)
	end
end

local function sendHold(on: boolean)
	if holdingSent == on then
		return
	end
	holdingSent = on
	Remotes.HoldBreath:FireServer(on)
end

local function onBreathAction(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		pressed = true
		holdToken += 1
		local token = holdToken
		task.delay(HOLD_DELAY, function()
			if active and pressed and token == holdToken then
				sendHold(true)
			end
		end)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		pressed = false
		holdToken += 1
		sendHold(false)
	end
	-- короткое нажатие обрабатывает Interaction (выход из укрытия)
	return Enum.ContextActionResult.Pass
end

local function leave()
	if not active then
		return
	end
	active = false
	activeHideId = nil
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	RunService:UnbindFromRenderStep(RENDER_NAME)
	ContextActionService:UnbindAction(ACTION_BREATH)
	pressed = false
	holdToken += 1
	sendHold(false)
	if useScriptable then
		Camera.setScriptable(nil)
		useScriptable = false
	end
	setMuffle(false)
	Sounds.playUI("ClosetDoor", 0.8)
end

local function enter(hideId: string?)
	if active and activeHideId == hideId then
		return
	end
	if active then
		leave()
	end
	active = true
	activeHideId = hideId
	yaw, pitch = 0, 0
	padLook = Vector2.zero

	local base = findCamPoint(hideId)
	useScriptable = base ~= nil
	if base then
		baseCFrame = base
		Camera.setScriptable(base)
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, renderStep)
		table.insert(conns, UserInputService.InputChanged:Connect(onInputChanged))
	end

	setMuffle(true)
	ContextActionService:BindAction(ACTION_BREATH, onBreathAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle(ACTION_BREATH, Locale.t("Breath"))
	ContextActionService:SetPosition(ACTION_BREATH, UDim2.new(0.05, 0, 0.3, 0))
	Sounds.playUI("ClosetDoor")
end

function Hiding.isActive(): boolean
	return active
end

function Hiding.init()
	ClientState.StatusChanged:Connect(function(status: string, hideId: string?)
		if status == "Hiding" then
			enter(hideId)
		else
			leave()
		end
	end)
	if ClientState.Status == "Hiding" then
		enter(ClientState.HideId)
	end
end

return Hiding
