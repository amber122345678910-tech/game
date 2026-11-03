--!strict
-- Plays "Yuta vs Ryu — part 1" (Cinema look) when you press Play in Studio.
--   R          - restart              Space - pause / resume
--   Left/Right - step one frame (1/30 s) while paused
--   J / K      - previous / next shot  L     - loop on/off
--   S          - subtitles on/off      H     - hide/show the info panel
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Cutscene = ReplicatedStorage:WaitForChild("Cutscene")
local Realizer = require(Cutscene:WaitForChild("Realizer"))
local Scene = require(Cutscene:WaitForChild("Scene"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local HOLD = 1.0 -- seconds the last frame is held before looping

-- clean screen for recording ---------------------------------------------------
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		if ok then
			break
		end
		task.wait(0.25)
	end
end)

-- UI -----------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CutsceneUI"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local safe = Instance.new("Frame") -- the 16:9 picture area
safe.Name = "Safe"
safe.BackgroundTransparency = 1
safe.ClipsDescendants = true
safe.Parent = gui

local bars = {}
for i = 1, 4 do
	local b = Instance.new("Frame")
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(0, 0, 0)
	b.ZIndex = 100
	b.Parent = gui
	bars[i] = b
end

-- vignette: four edge gradients inside the picture
local vignette = {}
for i, rot in { 0, 90, 180, 270 } do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(5, 8, 18)
	f.ZIndex = 5
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	if rot == 0 then
		f.Size = UDim2.fromScale(0.22, 1)
		f.Position = UDim2.fromScale(0, 0)
	elseif rot == 90 then
		f.Size = UDim2.fromScale(1, 0.3)
		f.Position = UDim2.fromScale(0, 0)
	elseif rot == 180 then
		f.Size = UDim2.fromScale(0.22, 1)
		f.Position = UDim2.fromScale(0.78, 0)
	else
		f.Size = UDim2.fromScale(1, 0.3)
		f.Position = UDim2.fromScale(0, 0.7)
	end
	f.Parent = safe
	vignette[i] = f
end

-- full-screen flash (white-outs, impact flashes)
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BorderSizePixel = 0
flash.BackgroundTransparency = 1
flash.ZIndex = 80
flash.Parent = safe

-- subtitles (English, as in the reference edit)
local sub = Instance.new("TextLabel")
sub.Name = "Subtitle"
sub.AnchorPoint = Vector2.new(0.5, 1)
sub.Position = UDim2.fromScale(0.5, 0.955)
sub.Size = UDim2.fromScale(0.8, 0.09)
sub.BackgroundTransparency = 1
sub.TextColor3 = Color3.new(1, 1, 1)
sub.TextStrokeColor3 = Color3.new(0, 0, 0)
sub.TextStrokeTransparency = 0.1
sub.Font = Enum.Font.GothamBold
sub.TextScaled = true
sub.TextWrapped = true
sub.TextYAlignment = Enum.TextYAlignment.Bottom
sub.ZIndex = 85
sub.Text = ""
sub.Parent = safe
local subSize = Instance.new("UITextSizeConstraint")
subSize.MaxTextSize = 48
subSize.Parent = sub

local card = Instance.new("TextLabel")
card.Name = "Loading"
card.Size = UDim2.fromScale(1, 1)
card.BackgroundColor3 = Color3.new(0, 0, 0)
card.TextColor3 = Color3.new(1, 1, 1)
card.Font = Enum.Font.GothamBold
card.TextSize = 28
card.Text = "Сборка сцены…"
card.ZIndex = 90
card.Parent = safe

local hud = Instance.new("TextLabel")
hud.Name = "Info"
hud.Position = UDim2.fromOffset(14, 14)
hud.Size = UDim2.fromOffset(500, 100)
hud.BackgroundColor3 = Color3.new(0, 0, 0)
hud.BackgroundTransparency = 0.35
hud.TextColor3 = Color3.new(1, 1, 1)
hud.Font = Enum.Font.Gotham
hud.TextSize = 15
hud.TextXAlignment = Enum.TextXAlignment.Left
hud.TextYAlignment = Enum.TextYAlignment.Top
hud.RichText = true
hud.ZIndex = 200
hud.Parent = gui
local hudPad = Instance.new("UIPadding")
hudPad.PaddingLeft = UDim.new(0, 10)
hudPad.PaddingTop = UDim.new(0, 8)
hudPad.Parent = hud
Instance.new("UICorner").Parent = hud

-- state ----------------------------------------------------------------------------
local t = 0
local playing = true
local looping = true
local subsOn = true
local holdTimer = 0
local fovScale = 1

local function layout()
	local vp = camera.ViewportSize
	local w, h = vp.X, vp.Y
	local sw, sh = w, w * 9 / 16
	if sh > h then
		sh = h
		sw = h * 16 / 9
	end
	local x0, y0 = math.floor((w - sw) / 2), math.floor((h - sh) / 2)
	safe.Position = UDim2.fromOffset(x0, y0)
	safe.Size = UDim2.fromOffset(math.ceil(sw), math.ceil(sh))
	bars[1].Position, bars[1].Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, y0)
	bars[2].Position, bars[2].Size = UDim2.new(0, 0, 0, y0 + math.ceil(sh)), UDim2.new(1, 0, 1, 0)
	bars[3].Position, bars[3].Size = UDim2.fromOffset(0, 0), UDim2.new(0, x0, 1, 0)
	bars[4].Position, bars[4].Size = UDim2.new(0, x0 + math.ceil(sw), 0, 0), UDim2.new(1, 0, 1, 0)
	fovScale = h / sh
end

local readMe = Workspace:FindFirstChild("ReadMe")
if readMe then
	readMe:Destroy() -- the instruction sign is only for the editor view
end
camera.CameraType = Enum.CameraType.Scriptable
layout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
RunService.RenderStepped:Wait()

-- which part this place plays (ReplicatedStorage.CutscenePart, default 1)
local partValue = game:GetService("ReplicatedStorage"):FindFirstChild("CutscenePart")
local part = if partValue and partValue:IsA("IntValue") then partValue.Value else 1
local live = Realizer.build("cinema", Workspace, part)
local DURATION = Scene.duration(live.scene)
Realizer.buildOverlay(live, safe)
local shots = Scene.shots(live.scene)
local vig = live.scene.style.vignette
for _, v in vignette do
	v.Visible = vig > 0
	v.BackgroundTransparency = 1 - vig
end
card.Visible = false

local function shotIndex(time: number): number
	local idx = 1
	for i, s in shots do
		if time >= s.t0 then
			idx = i
		end
	end
	return idx
end

local function updateHud(shotId: string)
	hud.Text = string.format(
		"<b>Юта vs Рю — часть " .. part .. "</b> · стиль «Кино»\nt = %.2f / %.2f с · план %s %s%s\n<font transparency='0.35'>R заново · Пробел пауза · ←/→ кадр · J/K план · S субтитры · L повтор · H скрыть</font>",
		t,
		DURATION,
		shotId,
		if playing then "" else "[пауза] ",
		if looping then "[повтор]" else ""
	)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.R then
		t = 0
		holdTimer = 0
		playing = true
	elseif k == Enum.KeyCode.Space then
		playing = not playing
	elseif k == Enum.KeyCode.Right then
		playing = false
		t = math.min(DURATION, t + 1 / 30)
	elseif k == Enum.KeyCode.Left then
		playing = false
		t = math.max(0, t - 1 / 30)
	elseif k == Enum.KeyCode.K then
		local i = math.min(#shots, shotIndex(t) + 1)
		t = shots[i].t0 + 0.001
	elseif k == Enum.KeyCode.J then
		local i = shotIndex(t)
		if t - shots[i].t0 < 0.3 then
			i = math.max(1, i - 1)
		end
		t = shots[i].t0 + 0.001
	elseif k == Enum.KeyCode.L then
		looping = not looping
	elseif k == Enum.KeyCode.S then
		subsOn = not subsOn
	elseif k == Enum.KeyCode.H then
		hud.Visible = not hud.Visible
	end
end)

RunService:BindToRenderStep("Cutscene", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	camera.CameraType = Enum.CameraType.Scriptable
	if playing then
		if t < DURATION then
			t = math.min(DURATION, t + dt)
		else
			holdTimer += dt
			if holdTimer >= HOLD and looping then
				t = 0
				holdTimer = 0
			end
		end
	end
	local frame = Scene.evaluate(live.scene, math.min(t, DURATION - 0.001))
	Realizer.apply(live, frame, camera, fovScale)
	local f = frame.flash
	if f and f.alpha > 0 then
		flash.BackgroundColor3 = f.color
		flash.BackgroundTransparency = 1 - f.alpha
	else
		flash.BackgroundTransparency = 1
	end
	sub.Text = if subsOn and frame.sub then frame.sub else ""
	updateHud(frame.shot)
end)
