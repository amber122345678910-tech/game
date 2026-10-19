--!strict
-- "Сочность": всплывающие числа, лёгкая тряска и "удар" камеры, вспышки экрана.
-- Всё рисуется только у этого игрока и не влияет на логику.
-- Настройки игрока соблюдаются здесь, для всех вызовов сразу: «Тряска» выключена — нет ни тряски, ни удара FOV;
-- «Мягкие вспышки» — вспышка экрана не ярче SOFT_FLASH_MAX.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Parent.UI.Theme)
local Loc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loc"))

local Juice = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Всплывающий текст над точкой мира («+12 ⚡», «Цепная молния!»): §8.4 — D3 (Oswald) с градиентом цвета,
-- обводкой 3 Ink и случайным наклоном ±5°; слова (русские или английские) — Montserrat Black Italic.
-- Детали берутся из пула (без создания и удаления на каждое событие)
----------------------------------------------------------------------
local popupFolder = Instance.new("Folder")
popupFolder.Name = "Popups"
popupFolder.Parent = Workspace

local MAX_POPUPS = 14
local HIDDEN = CFrame.new(0, 3000, 0) -- свободные детали пула стоят высоко над картой (ниже FallenPartsDestroyHeight нельзя)
local WHITE = Color3.new(1, 1, 1)

type Popup = {
	anchor: Part,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	grad: UIGradient,
	scale: UIScale,
	busy: boolean,
	token: number,
}
local popups: { Popup } = {}

local function makePopup(): Popup
	local anchor = Instance.new("Part")
	anchor.Name = "PopupAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = HIDDEN
	anchor.Parent = popupFolder
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Enabled = false
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.FontFace = Theme.FontNumber
	label.TextColor3 = WHITE
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Theme.Ink
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return { anchor = anchor, gui = gui, label = label, stroke = stroke, grad = grad, scale = scale, busy = false, token = 0 }
end

-- Слова, а не число: русские буквы (UTF-8: ведущие байты 0xD0/0xD1) или три латинские буквы подряд
-- (суффиксы чисел K, M, Qa — короче: «+1.2K ⚡» остаётся числом)
local function hasWords(text: string): boolean
	return string.find(text, "[\208\209]") ~= nil or string.find(text, "%a%a%a") ~= nil
end

-- source — строка (исходник или уже Loc.t) или Loc.Msg: рисуется на языке игрока
function Juice.popup(position: Vector3, source: string | Loc.Msg, color: Color3?, big: boolean?)
	local text = Loc.render(source)
	local p: Popup? = nil
	for _, q in popups do
		if not q.busy then
			p = q
			break
		end
	end
	if not p then
		if #popups >= MAX_POPUPS then
			return
		end
		p = makePopup()
		table.insert(popups, p)
	end
	local pop = p :: Popup
	pop.busy = true
	pop.token += 1
	local token = pop.token

	local base = color or Theme.Cream
	local h, sat, v = base:ToHSV()
	if v < 0.45 then
		base = Color3.fromHSV(h, sat * 0.8, 0.75) -- тёмный цвет (Чёрная Перуна) не читается на обводке Ink
	end
	local size = if big then 3.2 else 2.2
	local words = hasWords(text)
	pop.gui.Size = UDim2.fromScale(size * (if words then 3.2 else 2.5), size)
	pop.label.FontFace = if words then Theme.FontDisplay else Theme.FontNumber
	pop.label.Text = text
	pop.label.TextTransparency = 0
	pop.label.Rotation = math.random(-5, 5)
	pop.stroke.Transparency = 0
	pop.grad.Color = ColorSequence.new(base:Lerp(WHITE, 0.55), base)
	pop.scale.Scale = 0.3
	pop.anchor.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * 1.5, 1.5, (math.random() - 0.5) * 1.5))
	pop.gui.Enabled = true

	TweenService:Create(pop.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(pop.anchor, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = pop.anchor.CFrame + Vector3.new(0, 4, 0),
	}):Play()
	task.delay(0.65, function()
		if pop.token ~= token then
			return
		end
		TweenService:Create(pop.label, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
		TweenService:Create(pop.stroke, TweenInfo.new(0.45), { Transparency = 1 }):Play()
	end)
	task.delay(1.15, function()
		if pop.token ~= token then
			return
		end
		pop.gui.Enabled = false
		pop.anchor.CFrame = HIDDEN
		pop.busy = false
	end)
end

----------------------------------------------------------------------
-- Настройки игрока
----------------------------------------------------------------------
local SOFT_FLASH_MAX = 0.3 -- «Мягкие вспышки»: вспышка экрана не ярче (доля непрозрачности)

local function shakeAllowed(): boolean
	local d = ClientState.data
	return d == nil or d.Settings.Shake
end

local function softFlash(): boolean
	local d = ClientState.data
	return d == nil or d.Settings.SoftFlash
end

----------------------------------------------------------------------
-- Камера: тряска и "удар" FOV (поверх стандартной камеры Roblox)
-- Стандартная камера строит следующий кадр из текущего camera.CFrame, поэтому поворот тряски
-- нельзя просто оставить в нём — он бы копился и камера «уплывала». Каждый кадр: до модуля камеры
-- (Camera − 1) снимаем поворот прошлого кадра, после него (Camera + 1) добавляем новый.
----------------------------------------------------------------------
local shakeAmount = 0
local fovKick = 0
local baseFov = 70
local lastOffset = CFrame.identity -- поворот тряски, добавленный в прошлом кадре
local offsetCamera: Camera? = nil -- к какой камере он добавлен

-- amount: 0.1 — лёгкая, 0.5 — сильная. Затухает сама.
function Juice.shake(amount: number)
	if not shakeAllowed() then
		return
	end
	shakeAmount = math.min(1, math.max(shakeAmount, amount))
end

-- Резкое расширение обзора, которое плавно возвращается (ощущение скорости/удара)
function Juice.fovPunch(degrees: number)
	if not shakeAllowed() then
		return
	end
	fovKick = math.min(12, fovKick + degrees)
end

RunService:BindToRenderStep("JuiceCameraUndo", Enum.RenderPriority.Camera.Value - 1, function()
	local camera = offsetCamera
	offsetCamera = nil
	if camera and camera == Workspace.CurrentCamera then
		camera.CFrame = camera.CFrame * lastOffset:Inverse()
	end
	lastOffset = CFrame.identity
end)

RunService:BindToRenderStep("JuiceCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if shakeAmount > 0.001 then
		if shakeAllowed() then
			local t = os.clock() * 40
			local s = shakeAmount * shakeAmount * 0.35
			local offset = CFrame.Angles(math.noise(t, 0.3) * s * 0.06, math.noise(0.7, t) * s * 0.06, 0)
			camera.CFrame = camera.CFrame * offset
			lastOffset = offset
			offsetCamera = camera
			shakeAmount = math.max(0, shakeAmount - dt * 2.2)
		else
			shakeAmount = 0 -- тряску выключили посреди эффекта
		end
	end
	if fovKick > 0.01 then
		camera.FieldOfView = baseFov + fovKick
		fovKick = fovKick * math.exp(-dt * 7)
		if fovKick <= 0.01 then
			fovKick = 0
			camera.FieldOfView = baseFov
		end
	end
end)

----------------------------------------------------------------------
-- Камера за спину, когда сервер переставил персонажа лицом к центру острова (Effect "face":
-- появление, телепорт, возврат с обрыва). Стандартная камера берёт направление из текущего
-- camera.CFrame — достаточно один раз повернуть его по взгляду персонажа (наклон и приближение прежние).
----------------------------------------------------------------------
local FACE_RADIUS = 12 -- игрок уже ушёл дальше от точки (сообщение запоздало) — камеру не трогаем

ClientState.Effect:Connect(function(msg)
	if msg.Kind ~= "face" or (msg.UserId ~= nil and msg.UserId ~= player.UserId) then
		return
	end
	local at = msg.Pos
	task.defer(function()
		local camera = Workspace.CurrentCamera
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if not camera or camera.CameraType ~= Enum.CameraType.Custom or not root or not root:IsA("BasePart") then
			return
		end
		if typeof(at) == "Vector3" and (root.Position - at).Magnitude > FACE_RADIUS then
			return
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			return
		end
		local pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -0.99, 0.99))
		local dir = flat.Unit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
		local pos = camera.CFrame.Position
		-- поворот тряски прошлого кадра уже не снимать: кадр камеры строится заново
		lastOffset = CFrame.identity
		offsetCamera = nil
		camera.CFrame = CFrame.lookAt(pos, pos + dir)
	end)
end)

----------------------------------------------------------------------
-- Вспышка экрана цветом (редкая находка, покупка)
----------------------------------------------------------------------
local flashGui: ScreenGui? = nil
local flashFrame: Frame? = nil

local function ensureFlash(): Frame
	if flashFrame and flashFrame.Parent then
		return flashFrame
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Flash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.Parent = gui
	flashGui = gui
	flashFrame = f
	return f
end

function Juice.flash(color: Color3, strength: number?)
	local f = ensureFlash()
	local k = strength or 0.35
	if softFlash() then
		k = math.min(k, SOFT_FLASH_MAX)
	end
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - k
	TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

function Juice.destroy()
	RunService:UnbindFromRenderStep("JuiceCamera")
	RunService:UnbindFromRenderStep("JuiceCameraUndo")
	if flashGui then
		flashGui:Destroy()
	end
end

return Juice
