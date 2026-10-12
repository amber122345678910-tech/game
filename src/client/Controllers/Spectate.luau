--!strict
-- Спектатор: когда статус Taken / Spectating (или Lobby во время идущего матча) камера орбитой (дистанция 8)
-- следует за живым игроком (атрибут Status == "Alive" на Player; иначе — любой другой игрок).
-- Переключение Q / E (L1 / R1) или из интерфейса через Spectate.next() / Spectate.prev();
-- сигнал Spectate.TargetChanged(имя) для подписи. Вращение: ПКМ с перетаскиванием, палец, правый стик.
-- При возврате статуса Alive (или Lobby вне матча) камера возвращается в первое лицо.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Camera = require(script.Parent:WaitForChild("Camera"))

local Spectate = {}

Spectate.Active = false
Spectate.TargetChanged = Signal.new() :: Signal.Signal<string>

local RENDER_NAME = "AA_Spectate"
local ACTION_PREV = "SpectatePrev"
local ACTION_NEXT = "SpectateNext"
local DISTANCE = 8
local FOCUS_HEIGHT = 2
local MOUSE_SENS = 0.005
local TOUCH_SENS = 0.006
local PAD_YAW = 2.2
local PAD_PITCH = 1.6
local PITCH_MIN, PITCH_MAX = -1.3, 0.5
local RECHECK = 1

local player = Players.LocalPlayer
local target: Player? = nil
local yaw, pitch = 0, -0.25
local padLook = Vector2.zero
local dragging = false
local recheckTimer = 0
local conns: { RBXScriptConnection } = {}

-- Пока смотрим за другим, своего персонажа (в лобби) двигать нельзя
local function setControlsEnabled(on: boolean)
	pcall(function()
		local scripts = player:FindFirstChildOfClass("PlayerScripts")
		local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
		if not module or not module:IsA("ModuleScript") then
			return
		end
		local playerModule = (require :: any)(module)
		local controls = playerModule:GetControls()
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function rootOf(p: Player?): BasePart?
	if not p or p.Parent ~= Players then
		return nil
	end
	local char = p.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isAlive(p: Player): boolean
	return p:GetAttribute("Status") == "Alive"
end

local function candidates(): { Player }
	local alive: { Player } = {}
	local others: { Player } = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and rootOf(p) then
			if isAlive(p) then
				table.insert(alive, p)
			else
				table.insert(others, p)
			end
		end
	end
	local list = if #alive > 0 then alive else others
	table.sort(list, function(a: Player, b: Player): boolean
		return a.Name < b.Name
	end)
	return list
end

local function shouldSpectate(): boolean
	local s = ClientState.Status
	if s == "Taken" or s == "Spectating" then
		return true
	end
	return s == "Lobby" and ClientState.inMatch()
end

local function setTarget(p: Player?)
	if target == p then
		return
	end
	target = p
	Spectate.TargetChanged:Fire(if p then p.Name else "")
end

local function pickTarget(delta: number)
	local list = candidates()
	if #list == 0 then
		setTarget(nil)
		return
	end
	local current = target
	local idx = if current then table.find(list, current) else nil
	if not idx then
		idx = 1
	else
		idx = ((idx - 1 + delta) % #list) + 1
	end
	setTarget(list[idx])
end

function Spectate.next()
	if Spectate.Active then
		pickTarget(1)
	end
end

function Spectate.prev()
	if Spectate.Active then
		pickTarget(-1)
	end
end

function Spectate.target(): Player?
	return target
end

local function renderStep(dt: number)
	recheckTimer += dt
	local root = rootOf(target)
	if not root or recheckTimer >= RECHECK then
		recheckTimer = 0
		local current = target
		if not root or (current and not isAlive(current)) then
			-- цель пропала или выбыла: предпочитаем живых
			local list = candidates()
			if #list > 0 and (not current or not table.find(list, current)) then
				setTarget(list[1])
			end
		end
		root = rootOf(target)
	end
	local activeRoot = root
	if not activeRoot then
		return
	end

	if padLook.Magnitude > 0.15 then
		yaw -= padLook.X * PAD_YAW * dt
		pitch += padLook.Y * PAD_PITCH * dt
		pitch = math.clamp(pitch, PITCH_MIN, PITCH_MAX)
	end

	local focus = activeRoot.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local desired = focus + rot:VectorToWorldSpace(Vector3.new(0, 0, DISTANCE))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local filter: { Instance } = {}
	local tChar = if target then target.Character else nil
	if tChar then
		table.insert(filter, tChar)
	end
	if player.Character then
		table.insert(filter, player.Character)
	end
	local fx = workspace:FindFirstChild("ClientFX")
	if fx then
		table.insert(filter, fx)
	end
	local inmates = workspace:FindFirstChild("Inmates")
	if inmates then
		table.insert(filter, inmates)
	end
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(focus, desired - focus, params)
	if hit then
		desired = hit.Position + hit.Normal * 0.4
	end
	Camera.setScriptable(CFrame.lookAt(desired, focus))

	if UserInputService.MouseEnabled then
		local wanted = if dragging then Enum.MouseBehavior.LockCurrentPosition else Enum.MouseBehavior.Default
		if UserInputService.MouseBehavior ~= wanted then
			UserInputService.MouseBehavior = wanted
		end
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		dragging = true
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		dragging = false
	end
end

local function onInputChanged(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if dragging then
			yaw -= input.Delta.X * MOUSE_SENS
			pitch = math.clamp(pitch - input.Delta.Y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if not gameProcessed then
			yaw -= input.Delta.X * TOUCH_SENS
			pitch = math.clamp(pitch - input.Delta.Y * TOUCH_SENS, PITCH_MIN, PITCH_MAX)
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		padLook = Vector2.new(input.Position.X, input.Position.Y)
	end
end

local function onPrev(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		Spectate.prev()
	end
	return Enum.ContextActionResult.Sink
end

local function onNext(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		Spectate.next()
	end
	return Enum.ContextActionResult.Sink
end

local function start()
	if Spectate.Active then
		return
	end
	Spectate.Active = true
	yaw, pitch = 0, -0.25
	padLook = Vector2.zero
	dragging = false
	recheckTimer = RECHECK
	pickTarget(0)
	setControlsEnabled(false)
	table.insert(conns, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(conns, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(conns, UserInputService.InputChanged:Connect(onInputChanged))
	ContextActionService:BindAction(ACTION_PREV, onPrev, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction(ACTION_NEXT, onNext, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, renderStep)
end

local function stop()
	if not Spectate.Active then
		return
	end
	Spectate.Active = false
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	ContextActionService:UnbindAction(ACTION_PREV)
	ContextActionService:UnbindAction(ACTION_NEXT)
	RunService:UnbindFromRenderStep(RENDER_NAME)
	dragging = false
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	Camera.setScriptable(nil)
	setControlsEnabled(true)
	setTarget(nil)
end

local function evaluate()
	if shouldSpectate() then
		start()
	else
		stop()
	end
end

function Spectate.init()
	ClientState.StatusChanged:Connect(evaluate)
	ClientState.StateChanged:Connect(evaluate)
	Players.PlayerRemoving:Connect(function(p: Player)
		if p == target then
			setTarget(nil)
			if Spectate.Active then
				pickTarget(0)
			end
		end
	end)
	evaluate()
end

return Spectate
