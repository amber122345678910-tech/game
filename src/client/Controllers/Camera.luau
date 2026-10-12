--!strict
-- Камера от первого лица: лёгкий head-bob (настройка HeadBob), опускание камеры при приседе через
-- Humanoid.CameraOffset, собственная плавная тряска (Camera.shake / Camera.setSustainedShake) и
-- Scriptable-режим для укрытий и спектатора (Camera.setScriptable). Всё применяется на RenderPriority Camera+1,
-- то есть после штатного модуля камеры Roblox. LockFirstPerson задан в StarterPlayer; тело игрока в
-- первом лице Roblox скрывает сам.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local Camera = {}

local RENDER_NAME = "AA_Camera"

local player = Players.LocalPlayer

type Shake = {
	Magnitude: number,
	Duration: number,
	Elapsed: number,
	Seed: number,
}

local shakes: { Shake } = {}
local sustainedTarget = 0
local sustainedCurrent = 0
local scriptableCFrame: CFrame? = nil

local bobPhase = 0
local bobOffset = Vector3.zero
local crouchDrop = 0

local humanoid: Humanoid? = nil
local charConns: { RBXScriptConnection } = {}

local function clearCharConns()
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
end

local function bindCharacter(char: Model)
	clearCharConns()
	humanoid = nil
	bobPhase = 0
	bobOffset = Vector3.zero
	crouchDrop = 0
	local h = char:WaitForChild("Humanoid", 10)
	if h and h:IsA("Humanoid") and h.Parent == char then
		humanoid = h
		table.insert(charConns, h.Died:Connect(function()
			-- после смерти не трогаем CameraOffset
			humanoid = nil
		end))
	end
end

----------------------------------------------------------------------
-- Тряска
----------------------------------------------------------------------

-- Разовая тряска: magnitude ~1 = заметный толчок, затухает за duration секунд.
function Camera.shake(magnitude: number, duration: number)
	if magnitude <= 0 or duration <= 0 then
		return
	end
	table.insert(shakes, {
		Magnitude = math.clamp(magnitude, 0, 6),
		Duration = math.clamp(duration, 0.05, 10),
		Elapsed = 0,
		Seed = math.random() * 100,
	})
end

-- Постоянная мелкая тряска (босс рядом). 0 — выключить. Переход плавный.
function Camera.setSustainedShake(magnitude: number)
	sustainedTarget = math.clamp(magnitude, 0, 3)
end

local function computeShake(dt: number): (CFrame, boolean)
	local px, py, rx, ry, rz = 0, 0, 0, 0, 0
	local any = false
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		s.Elapsed += dt
		if s.Elapsed >= s.Duration then
			table.remove(shakes, i)
		else
			any = true
			local p = s.Elapsed / s.Duration
			local envelope = (1 - p) * (1 - p)
			local m = s.Magnitude * envelope
			local t = s.Elapsed * 28 + s.Seed
			px += math.sin(t * 1.1) * m * 0.14
			py += math.cos(t * 1.7) * m * 0.12
			rx += math.cos(t * 0.9) * m * 0.012
			ry += math.sin(t * 0.7 + 1) * m * 0.008
			rz += math.sin(t * 1.3) * m * 0.016
		end
	end
	sustainedCurrent += (sustainedTarget - sustainedCurrent) * math.clamp(dt * 3, 0, 1)
	if sustainedCurrent > 0.002 then
		any = true
		local t = os.clock() * 9
		local m = sustainedCurrent
		px += math.cos(t * 1.9) * m * 0.05
		py += math.sin(t * 2.3) * m * 0.07
		rz += math.sin(t * 1.5) * m * 0.009
		rx += math.cos(t * 1.2) * m * 0.006
	end
	if not any then
		return CFrame.identity, false
	end
	return CFrame.new(px, py, 0) * CFrame.Angles(rx, ry, rz), true
end

----------------------------------------------------------------------
-- Head-bob и присед
----------------------------------------------------------------------

local function updateBob(dt: number)
	local hum = humanoid
	if not hum or not hum.Parent then
		return
	end
	local status = ClientState.Status
	local free = status == "Alive" or status == "Lobby"
	local bobEnabled = free and scriptableCFrame == nil and ClientState.Settings.HeadBob ~= false
	local target = Vector3.zero
	if bobEnabled then
		local speed = hum.MoveDirection.Magnitude * hum.WalkSpeed
		if speed > 0.5 and hum.FloorMaterial ~= Enum.Material.Air then
			local sprinting = speed > Config.Movement.WalkSpeed + 1
			local freq = if sprinting then 11 elseif ClientState.Crouching then 6 else 8
			local amp = math.clamp(speed / Config.Movement.WalkSpeed, 0.4, 1.6)
			if sprinting then
				amp *= 1.2
			end
			bobPhase += dt * freq
			target = Vector3.new(math.sin(bobPhase) * 0.04 * amp, math.abs(math.cos(bobPhase)) * 0.07 * amp, 0)
		else
			bobPhase = 0
		end
	end
	bobOffset = bobOffset:Lerp(target, math.clamp(dt * 10, 0, 1))
	local dropTarget = if ClientState.Crouching and free then Config.Movement.CrouchCameraDrop else 0
	crouchDrop += (dropTarget - crouchDrop) * math.clamp(dt * 9, 0, 1)
	local offset = bobOffset + Vector3.new(0, -crouchDrop, 0)
	if (hum.CameraOffset - offset).Magnitude > 0.0005 then
		hum.CameraOffset = offset
	end
end

----------------------------------------------------------------------
-- Scriptable-режим (укрытие, спектатор)
----------------------------------------------------------------------

-- cframe: включить ручное управление камерой (вызывать можно каждый кадр); nil — вернуть первое лицо.
function Camera.setScriptable(cframe: CFrame?)
	local cam = workspace.CurrentCamera
	scriptableCFrame = cframe
	if not cam then
		return
	end
	if cframe then
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		cam.CFrame = cframe
	else
		if cam.CameraType ~= Enum.CameraType.Custom then
			cam.CameraType = Enum.CameraType.Custom
		end
		local hum = humanoid
		if hum and hum.Parent then
			cam.CameraSubject = hum
		end
		Camera.applyMode()
	end
end

----------------------------------------------------------------------
-- Режим камеры и курсора
-- В матче (жив / повален / в укрытии) — строго первое лицо. В лобби, итогах и спектаторе — обычная
-- камера, курсор свободен. Пока открыто модальное окно, идёт оповещение или зажат Alt — курсор свободен.
----------------------------------------------------------------------
local altHeld = false

local function wantsFirstPerson(): boolean
	if not ClientState.inMatch() then
		return false
	end
	local status = ClientState.Status
	return status == "Alive" or status == "Downed" or status == "Hiding"
end

function Camera.cursorFree(): boolean
	return ClientState.isModalOpen() or altHeld or ClientState.Snapshot.Phase == "Alert" or not wantsFirstPerson()
end

function Camera.applyMode()
	if scriptableCFrame then
		return
	end
	if wantsFirstPerson() then
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	else
		player.CameraMaxZoomDistance = 14
		player.CameraMinZoomDistance = 4
		if player.CameraMode ~= Enum.CameraMode.Classic then
			player.CameraMode = Enum.CameraMode.Classic
		end
	end
end

function Camera.isScriptable(): boolean
	return scriptableCFrame ~= nil
end

----------------------------------------------------------------------

function Camera.init()
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		clearCharConns()
		humanoid = nil
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	ClientState.StatusChanged:Connect(function()
		Camera.applyMode()
	end)
	ClientState.StateChanged:Connect(function()
		Camera.applyMode()
	end)
	ClientState.ModalChanged:Connect(function()
		Camera.applyMode()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = false
		end
	end)
	Camera.applyMode()

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		-- Свободный курсор поверх штатной камеры (она каждый кадр захватывает мышь в первом лице)
		if scriptableCFrame == nil and wantsFirstPerson() and Camera.cursorFree() then
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			UserInputService.MouseIconEnabled = true
		end
		local shakeCf, hasShake = computeShake(dt)
		local base = scriptableCFrame
		if base then
			if cam.CameraType ~= Enum.CameraType.Scriptable then
				cam.CameraType = Enum.CameraType.Scriptable
			end
			cam.CFrame = if hasShake then base * shakeCf else base
		elseif hasShake then
			-- штатная камера уже записала CFrame в этом кадре, поэтому тряска не накапливается
			cam.CFrame = cam.CFrame * shakeCf
		end
		updateBob(dt)
	end)
end

return Camera
