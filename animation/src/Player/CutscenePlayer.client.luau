--!strict
-- Plays the cutscene when you press Play in Roblox Studio.
--   1 / 2 / 3  - style: Anime / Cinema / Classic (restarts from 0)
--   A          - showcase: all three styles one after another (for recording)
--   R          - restart          Space - pause / resume
--   Left/Right - step one frame (1/30 s) while paused
--   L          - loop on/off       H     - hide/show the info panel
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Cutscene = ReplicatedStorage:WaitForChild("Cutscene")
local Realizer = require(Cutscene:WaitForChild("Realizer"))
local Scene = require(Cutscene:WaitForChild("Scene"))
local Styles = require(Cutscene:WaitForChild("Styles"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local HOLD = 0.8 -- seconds the last frame is held before looping
local CARD = 1.1 -- title card length in showcase mode

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

local card = Instance.new("TextLabel")
card.Name = "TitleCard"
card.Size = UDim2.fromScale(1, 1)
card.BackgroundColor3 = Color3.new(0, 0, 0)
card.BackgroundTransparency = 0
card.TextColor3 = Color3.new(1, 1, 1)
card.Font = Enum.Font.GothamBold
card.TextScaled = true
card.ZIndex = 90
card.Visible = false
card.Parent = safe
local cardPad = Instance.new("UIPadding")
cardPad.PaddingTop = UDim.new(0.4, 0)
cardPad.PaddingBottom = UDim.new(0.4, 0)
cardPad.Parent = card

local hud = Instance.new("TextLabel")
hud.Name = "Info"
hud.AnchorPoint = Vector2.new(0, 0)
hud.Position = UDim2.fromOffset(14, 14)
hud.Size = UDim2.fromOffset(470, 118)
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
local live: Realizer.Live? = nil
local styleIndex = 1
local t = 0
local playing = true
local looping = true
local holdTimer = 0
local showcase = false
local cardTimer = 0
local fovScale = 1

local function styleId(): string
	return Styles.order[styleIndex]
end

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

local function updateHud()
	local st = Styles.get(styleId())
	hud.Text = string.format(
		"<b>Юта vs Рю — часть 1 · проба стиля</b>\n<b>%s</b> — %s\nt = %.2f с  %s%s\n<font transparency='0.35'>1/2/3 стиль · A все подряд · R заново · Пробел пауза · ←/→ кадр · L повтор · H скрыть</font>",
		st.title,
		st.subtitle,
		t,
		if playing then "" else "[пауза] ",
		if showcase then "[показ всех стилей]" elseif looping then "[повтор]" else ""
	)
end

local loading = false

local function load(index: number)
	if loading then
		return
	end
	loading = true
	styleIndex = index
	if live then
		Realizer.destroy(live)
		live = nil
	end
	card.Text = "Сборка сцены…"
	card.Visible = true
	RunService.RenderStepped:Wait()
	local newLive = Realizer.build(styleId(), Workspace)
	Realizer.buildOverlay(newLive, safe)
	live = newLive
	local st = Styles.get(styleId())
	for _, v in vignette do
		v.Visible = st.vignette > 0
		v.BackgroundTransparency = 1 - st.vignette
	end
	card.Visible = false
	t = 0
	holdTimer = 0
	if showcase then
		card.Text = st.title .. "  —  " .. st.subtitle
		card.Visible = true
		cardTimer = CARD
	end
	loading = false
end

-- input --------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.One or k == Enum.KeyCode.KeypadOne then
		showcase = false
		load(1)
	elseif k == Enum.KeyCode.Two or k == Enum.KeyCode.KeypadTwo then
		showcase = false
		load(2)
	elseif k == Enum.KeyCode.Three or k == Enum.KeyCode.KeypadThree then
		showcase = false
		load(3)
	elseif k == Enum.KeyCode.A then
		showcase = true
		playing = true
		load(1)
	elseif k == Enum.KeyCode.R then
		t = 0
		holdTimer = 0
		playing = true
	elseif k == Enum.KeyCode.Space then
		playing = not playing
	elseif k == Enum.KeyCode.Right then
		playing = false
		t = math.min(Scene.DURATION, t + 1 / 30)
	elseif k == Enum.KeyCode.Left then
		playing = false
		t = math.max(0, t - 1 / 30)
	elseif k == Enum.KeyCode.L then
		looping = not looping
	elseif k == Enum.KeyCode.H then
		hud.Visible = not hud.Visible
	end
end)

-- main loop -----------------------------------------------------------------------
local readMe = Workspace:FindFirstChild("ReadMe")
if readMe then
	readMe:Destroy() -- the instruction sign is only for the editor view
end
camera.CameraType = Enum.CameraType.Scriptable
layout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
load(1)

RunService:BindToRenderStep("Cutscene", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local cur = live
	if not cur then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if cardTimer > 0 then
		cardTimer -= dt
		card.Visible = cardTimer > 0
	elseif playing then
		if t < Scene.DURATION then
			t = math.min(Scene.DURATION, t + dt)
		else
			holdTimer += dt
			if holdTimer >= HOLD then
				if showcase then
					if styleIndex < #Styles.order then
						-- rebuilding yields, which is not allowed inside a render step
						task.spawn(load, styleIndex + 1)
						return
					end
					showcase = false
					playing = false
				elseif looping then
					t = 0
					holdTimer = 0
				end
			end
		end
	end
	Realizer.apply(cur, Scene.evaluate(cur.scene, t), camera, fovScale)
	updateHud()
end)
