--!strict
-- "Сочность": всплывающие числа, лёгкая тряска и "удар" камеры, вспышки экрана.
-- Всё рисуется только у этого игрока и не влияет на логику.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent.UI.Theme)

local Juice = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Всплывающий текст над точкой мира ("+12 ✨")
----------------------------------------------------------------------
local popupFolder = Instance.new("Folder")
popupFolder.Name = "Popups"
popupFolder.Parent = Workspace

local activePopups = 0
local MAX_POPUPS = 14

function Juice.popup(position: Vector3, text: string, color: Color3?, big: boolean?)
	if activePopups >= MAX_POPUPS then
		return
	end
	activePopups += 1
	local anchor = Instance.new("Part")
	anchor.Name = "PopupAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * 1.5, 1.5, (math.random() - 0.5) * 1.5))
	anchor.Parent = popupFolder

	local size = if big then 3.2 else 2.2
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(size * 2.5, size)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.FontFace = Theme.Font
	label.TextColor3 = color or Theme.Text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Theme.TextStroke
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label

	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(anchor, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = anchor.CFrame + Vector3.new(0, 4, 0),
	}):Play()
	task.delay(0.65, function()
		TweenService:Create(label, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.45), { Transparency = 1 }):Play()
	end)
	task.delay(1.15, function()
		activePopups -= 1
		anchor:Destroy()
	end)
end

----------------------------------------------------------------------
-- Камера: тряска и "удар" FOV (поверх стандартной камеры Roblox)
----------------------------------------------------------------------
local shakeAmount = 0
local fovKick = 0
local baseFov = 70

-- amount: 0.1 — лёгкая, 0.5 — сильная. Затухает сама.
function Juice.shake(amount: number)
	shakeAmount = math.min(1, math.max(shakeAmount, amount))
end

-- Резкое расширение обзора, которое плавно возвращается (ощущение скорости/удара)
function Juice.fovPunch(degrees: number)
	fovKick = math.min(12, fovKick + degrees)
end

RunService:BindToRenderStep("JuiceCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if shakeAmount > 0.001 then
		local t = os.clock() * 40
		local s = shakeAmount * shakeAmount * 0.35
		local offset = CFrame.Angles(math.noise(t, 0.3) * s * 0.06, math.noise(0.7, t) * s * 0.06, 0)
		camera.CFrame = camera.CFrame * offset
		shakeAmount = math.max(0, shakeAmount - dt * 2.2)
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
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (strength or 0.35)
	TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

function Juice.destroy()
	RunService:UnbindFromRenderStep("JuiceCamera")
	if flashGui then
		flashGui:Destroy()
	end
end

return Juice
