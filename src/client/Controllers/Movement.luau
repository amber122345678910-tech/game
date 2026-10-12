--!strict
-- Движение: бег (LeftShift / L3 / сенсорная кнопка), выносливость по Config.Movement (трата, восстановление,
-- блок 3 с после нуля, перк Sprinter), переключение приседа (C / B / кнопка) и скорость ходьбы по состоянию.
-- В статусах Hiding / Downed / Taken / Spectating скорость задаёт сервер (0) — здесь её не трогаем.
-- Шум бега сервер считает сам по скорости персонажа, клиент ничего не шлёт кроме SetSprint.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Locale = require(Shared:WaitForChild("Locale"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local Movement = {}

Movement.Stamina = Config.Movement.StaminaMax
Movement.Sprinting = false
Movement.StaminaChanged = Signal.new() :: Signal.Signal<number>
Movement.SprintChanged = Signal.new() :: Signal.Signal<boolean>

local ACTION_SPRINT = "Sprint"
local ACTION_CROUCH = "Crouch"

-- Статусы, в которых клиент сам управляет скоростью
local FREE_STATUS: { [string]: boolean } = { Alive = true, Lobby = true }

local player = Players.LocalPlayer
local humanoid: Humanoid? = nil
local charConns: { RBXScriptConnection } = {}

local sprintHeld = false -- кнопка зажата (клавиатура) или переключена (геймпад/сенсор)
local exhaustedUntil = 0
local lastStaminaFired = -1

local function clearCharConns()
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
end

local function bindCharacter(char: Model)
	clearCharConns()
	humanoid = nil
	local h = char:WaitForChild("Humanoid", 10)
	if h and h:IsA("Humanoid") and h.Parent == char then
		humanoid = h
		table.insert(charConns, h.Died:Connect(function()
			humanoid = nil
			sprintHeld = false
		end))
	end
end

local function sprinterMultiplier(): number
	local perks = ClientState.Profile.Perks
	local level = if typeof(perks) == "table" then perks["Sprinter"] else nil
	if typeof(level) ~= "number" then
		return 1
	end
	return 1 + Config.perkValue("Sprinter", level)
end

local function canControl(): boolean
	local hum = humanoid
	return hum ~= nil and hum.Parent ~= nil and hum.Health > 0 and FREE_STATUS[ClientState.Status] == true
end

-- Внешнее управление бегом (например, из интерфейса)
function Movement.setSprintHeld(on: boolean)
	sprintHeld = on
end

function Movement.isExhausted(): boolean
	return os.clock() < exhaustedUntil
end

local function toggleCrouch()
	if not canControl() then
		return
	end
	ClientState.setCrouch(not ClientState.Crouching)
end

local function onSprintAction(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
	local isHoldInput = input.UserInputType == Enum.UserInputType.Keyboard
	if state == Enum.UserInputState.Begin then
		if isHoldInput then
			sprintHeld = true
		else
			-- геймпад (нажатие стика) и сенсорная кнопка — переключатель
			sprintHeld = not sprintHeld
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if isHoldInput or state == Enum.UserInputState.Cancel then
			sprintHeld = false
		end
	end
	return Enum.ContextActionResult.Pass
end

local function onCrouchAction(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		toggleCrouch()
	end
	return Enum.ContextActionResult.Pass
end

local function step(dt: number)
	local now = os.clock()
	local controlled = canControl()
	local hum = humanoid
	local moving = controlled and hum ~= nil and hum.MoveDirection.Magnitude > 0.05
	local stamina = Movement.Stamina

	local wantSprint = controlled and sprintHeld and moving and stamina > 0 and now >= exhaustedUntil
	if wantSprint and ClientState.Crouching then
		ClientState.setCrouch(false)
	end
	local sprinting = wantSprint and not ClientState.Crouching

	if sprinting then
		stamina -= Config.Movement.SprintDrain * dt
		if stamina <= 0 then
			stamina = 0
			exhaustedUntil = now + Config.Movement.ExhaustLock
			sprinting = false
			sprintHeld = false -- сбрасываем и переключатель на геймпаде/сенсоре
		end
	else
		local regen = if moving then Config.Movement.RegenWalk else Config.Movement.RegenIdle
		stamina = math.min(Config.Movement.StaminaMax, stamina + regen * sprinterMultiplier() * dt)
	end

	if controlled and hum then
		local speed = if sprinting
			then Config.Movement.SprintSpeed
			elseif ClientState.Crouching then Config.Movement.CrouchSpeed
			else Config.Movement.WalkSpeed
		if math.abs(hum.WalkSpeed - speed) > 0.01 then
			hum.WalkSpeed = speed
		end
	end

	if sprinting ~= Movement.Sprinting then
		Movement.Sprinting = sprinting
		Movement.SprintChanged:Fire(sprinting)
		Remotes.SetSprint:FireServer(sprinting)
	end

	if math.abs(stamina - lastStaminaFired) > 0.01 then
		lastStaminaFired = stamina
		Movement.Stamina = stamina
		Movement.StaminaChanged:Fire(stamina)
	else
		Movement.Stamina = stamina
	end
end

function Movement.init()
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		clearCharConns()
		humanoid = nil
		sprintHeld = false
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	ClientState.StatusChanged:Connect(function(status: string)
		if FREE_STATUS[status] ~= true then
			sprintHeld = false
		end
	end)

	ContextActionService:BindAction(ACTION_SPRINT, onSprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle(ACTION_SPRINT, Locale.t("Sprint"))
	ContextActionService:SetPosition(ACTION_SPRINT, UDim2.new(0.05, 0, 0.62, 0))

	ContextActionService:BindAction(ACTION_CROUCH, onCrouchAction, true, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(ACTION_CROUCH, Locale.t("Crouch"))
	ContextActionService:SetPosition(ACTION_CROUCH, UDim2.new(0.5, 0, 0.62, 0))

	RunService.Heartbeat:Connect(step)
end

return Movement
