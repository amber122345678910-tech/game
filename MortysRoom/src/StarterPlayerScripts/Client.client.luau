--[[
	Client flow:
	  MENU   -> camera floats around sleeping Morty, you pick Play / Settings / ...
	  WAKING -> camera dives into Morty's head, alarm rings, eyes open
	  LYING  -> look around from the pillow, SPACE to get up
	  PLAYING-> first person as Morty. E = use, P = pause, G = next graphics preset
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameFolder = ReplicatedStorage:WaitForChild("Game")
local Config = require(GameFolder:WaitForChild("Config"))
local UI = require(GameFolder:WaitForChild("UI"))
local Settings = require(GameFolder:WaitForChild("Settings"))
local Audio = require(GameFolder:WaitForChild("Audio"))
local Graphics = require(GameFolder:WaitForChild("Graphics"))
local MenuController = require(GameFolder:WaitForChild("MenuController"))
local StylesFolder = GameFolder:WaitForChild("MenuStyles")
local Remotes = GameFolder:WaitForChild("Remotes")

local house = workspace:WaitForChild("MortysHouse")
local spawns = house:WaitForChild("Spawns")
local wakePoint = spawns:WaitForChild("WakeUpPoint") :: BasePart
local npc = house:WaitForChild("MortySleeping")
local npcHead = npc:WaitForChild("Head")
local headCore = npcHead:WaitForChild("HeadCore") :: BasePart
local bed = house:WaitForChild("Bed")
local alarmClock = house:WaitForChild("AlarmClock")
local clockFace = alarmClock:WaitForChild("Face") :: BasePart
local clockText = alarmClock:FindFirstChild("ClockText", true) :: TextLabel

local camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
end)

local rgb = Color3.fromRGB
local controls = nil
task.spawn(function()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and module then
		controls = module:GetControls()
		controls:Disable()
	end
end)

local function setControls(on: boolean)
	if controls then
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

-- Hide Roblox UI we don't need -----------------------------------------------------
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

-- Preload sounds in the background ----------------------------------------------------
task.spawn(function()
	local list = {}
	for _, def in Config.Sounds do
		local s = Instance.new("Sound")
		s.SoundId = def.Id
		table.insert(list, s)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end)

---------------------------------------------------------------------------------------
-- Overlay UI (fade, eyelids, crosshair, hints, subtitles, picker)
---------------------------------------------------------------------------------------
local overlay = UI.new("ScreenGui", {
	Name = "Overlay",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
local overlayCanvas = UI.canvas(overlay)

local lidTop = UI.new("Frame", {
	Name = "LidTop",
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, -0.62),
	ZIndex = 20,
	Parent = overlay,
}, { UI.gradient(nil, { 0, 0, 0, 1 }, 90) })
local lidBottom = UI.new("Frame", {
	Name = "LidBottom",
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, 1.62),
	ZIndex = 20,
	Parent = overlay,
}, { UI.gradient(nil, { 1, 0, 0, 0 }, 90) })

local fade = UI.new("Frame", {
	Name = "Fade",
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 30,
	Parent = overlay,
})

local crosshair = UI.new("Frame", {
	Name = "Crosshair",
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.25,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(6, 6),
	Visible = false,
	ZIndex = 10,
	Parent = overlay,
}, { UI.round(), UI.stroke(1, Color3.new(0, 0, 0), 0.5, true) })

local interactHint = UI.label({
	Name = "InteractHint",
	Font = Enum.Font.GothamMedium,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 26),
	Size = UDim2.fromOffset(600, 30),
	Visible = false,
	ZIndex = 10,
	Parent = overlayCanvas,
})
UI.stroke(1.5, Color3.new(0, 0, 0), 0.3).Parent = interactHint

local promptLabel = UI.label({
	Name = "Prompt",
	Font = Enum.Font.GothamMedium,
	TextSize = 24,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -70),
	Size = UDim2.fromOffset(1200, 34),
	ZIndex = 10,
	Parent = overlayCanvas,
})
local promptStroke = UI.stroke(1.5, Color3.new(0, 0, 0), 1)
promptStroke.Parent = promptLabel

local subtitle = UI.label({
	Name = "Subtitle",
	Font = Enum.Font.GothamMedium,
	TextSize = 26,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = true,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -130),
	Size = UDim2.fromOffset(1100, 70),
	ZIndex = 10,
	Parent = overlayCanvas,
})
local subtitleStroke = UI.stroke(2, Color3.new(0, 0, 0), 1)
subtitleStroke.Parent = subtitle

local toast = UI.label({
	Name = "Toast",
	Font = Enum.Font.GothamMedium,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(1100, 28),
	ZIndex = 40,
	Parent = overlayCanvas,
})
local toastStroke = UI.stroke(1.5, Color3.new(0, 0, 0), 1)
toastStroke.Parent = toast

local subtitleToken = 0
local function say(text: string, seconds: number?)
	subtitleToken += 1
	local my = subtitleToken
	subtitle.Text = text
	UI.tween(subtitle, 0.25, { TextTransparency = 0 })
	UI.tween(subtitleStroke, 0.25, { Transparency = 0.4 })
	task.delay(seconds or 3.5, function()
		if my == subtitleToken then
			UI.tween(subtitle, 0.5, { TextTransparency = 1 })
			UI.tween(subtitleStroke, 0.5, { Transparency = 1 })
		end
	end)
end

local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	UI.tween(toast, 0.2, { TextTransparency = 0 })
	UI.tween(toastStroke, 0.2, { Transparency = 0.4 })
	task.delay(2.6, function()
		if my == toastToken then
			UI.tween(toast, 0.5, { TextTransparency = 1 })
			UI.tween(toastStroke, 0.5, { Transparency = 1 })
		end
	end)
end

local function showPrompt(text: string?)
	if text then
		promptLabel.Text = text
		UI.tween(promptLabel, 0.4, { TextTransparency = 0 })
		UI.tween(promptStroke, 0.4, { Transparency = 0.4 })
	else
		UI.tween(promptLabel, 0.3, { TextTransparency = 1 })
		UI.tween(promptStroke, 0.3, { Transparency = 1 })
	end
end

local function fadeTo(alpha: number, t: number)
	UI.tween(fade, t, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine)
end

local lidOpen = Instance.new("NumberValue")
lidOpen.Value = 1
local function applyLids()
	local o = lidOpen.Value
	lidTop.Position = UDim2.fromScale(0, -0.62 * o)
	lidBottom.Position = UDim2.fromScale(0, 1 + 0.62 * o)
end
lidOpen.Changed:Connect(applyLids)
applyLids()
local function lids(target: number, t: number)
	UI.tween(lidOpen, t, { Value = target }, Enum.EasingStyle.Sine)
	task.wait(t)
end

-- touch buttons
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local function touchButton(text: string, pos: UDim2)
	local b = UI.new("TextButton", {
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = pos,
		Size = UDim2.fromOffset(150, 70),
		Visible = false,
		ZIndex = 15,
		Parent = overlayCanvas,
	}, { UI.corner(14), UI.stroke(2, Color3.new(1, 1, 1), 0.6, true) })
	return b
end
local getUpButton = touchButton("GET UP", UDim2.new(1, -60, 1, -60))
local useButton = touchButton("USE", UDim2.new(1, -60, 1, -150))
local pauseButton = touchButton("II", UDim2.new(1, -40, 0, 150))
pauseButton.Size = UDim2.fromOffset(70, 70)

---------------------------------------------------------------------------------------
-- Room sounds
---------------------------------------------------------------------------------------
local snore = Audio.make("Snore", headCore)
local alarm = Audio.make("Alarm", clockFace)
local tick = Audio.make("ClockTick", clockFace)
if tick then
	tick:Play()
end
local ambience: Sound? = nil
local ambienceKey: string? = nil
local function setAmbience(key: string?)
	if key == ambienceKey then
		return
	end
	if ambience then
		Audio.fadeOut(ambience, 1.5, true)
	end
	ambience = nil
	ambienceKey = key
	if key then
		local s = Audio.make(key, workspace.CurrentCamera)
		if s then
			Audio.fadeIn(s, 2)
			ambience = s
		end
	end
end

---------------------------------------------------------------------------------------
-- Settings -> world
---------------------------------------------------------------------------------------
local function applyGraphics(name: string, instant: boolean?)
	Graphics.Apply(name, instant)
	local p = Graphics.Get(name)
	if p then
		setAmbience(p.Ambience)
	end
end

Audio.setGroupVolume("Music", Settings.Get("Music"))
Audio.setGroupVolume("SFX", Settings.Get("Sound"))
Audio.setGroupVolume("Ambience", Settings.Get("Sound"))
Graphics.SetBrightnessOffset(Settings.Get("Brightness") * 0.6)
pcall(function()
	UserInputService.MouseDeltaSensitivity = Settings.Get("Sensitivity")
end)
applyGraphics(Settings.Get("Graphics"), true)

local state = "menu"
local refreshPicker: () -> () -- defined further down

Settings.Changed:Connect(function(key, value)
	if key == "Music" then
		Audio.setGroupVolume("Music", value)
	elseif key == "Sound" then
		Audio.setGroupVolume("SFX", value)
		Audio.setGroupVolume("Ambience", value)
	elseif key == "Sensitivity" then
		pcall(function()
			UserInputService.MouseDeltaSensitivity = value
		end)
	elseif key == "Brightness" then
		Graphics.SetBrightnessOffset(value * 0.6)
	elseif key == "Graphics" then
		applyGraphics(value)
		refreshPicker()
		local p = Graphics.Get(value)
		showToast("GRAPHICS: " .. string.upper(value) .. (if p then "  —  " .. p.Description else ""))
	elseif key == "FOV" then
		if state == "playing" or state == "lying" then
			camera.FieldOfView = value
		end
	end
end)

---------------------------------------------------------------------------------------
-- Sleeping Morty visuals
---------------------------------------------------------------------------------------
local function setVisible(container: Instance, visible: boolean)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

local blanketOn = bed:WaitForChild("BlanketOn")
local blanketOff = bed:WaitForChild("BlanketOff")
local function setSleeping(sleeping: boolean)
	setVisible(npcHead, sleeping)
	setVisible(npc:WaitForChild("Arm"), sleeping)
	for _, d in blanketOn:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if sleeping then 0 else 1
			d.CanQuery = sleeping
		end
	end
	for _, d in blanketOff:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if sleeping then 1 else 0
			d.CanQuery = not sleeping
		end
	end
end

-- floating "Z z z"
local zzz = UI.new("BillboardGui", {
	Name = "Zzz",
	Adornee = headCore,
	Size = UDim2.fromOffset(120, 140),
	StudsOffset = Vector3.new(0.6, 1.6, 0),
	LightInfluence = 0,
	AlwaysOnTop = false,
	ResetOnSpawn = false,
	Parent = playerGui,
})
local zLetters = {}
for i = 1, 3 do
	zLetters[i] = UI.label({
		Text = if i == 3 then "Z" else "z",
		Font = Enum.Font.FredokaOne,
		TextSize = 18 + i * 8,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(40, 40),
		Parent = zzz,
	})
end
local function updateZzz(t: number, visible: boolean)
	for i, z in zLetters do
		local phase = (t * 0.45 + i / 3) % 1
		z.Position = UDim2.fromOffset(20 + i * 18 + math.sin(t * 2 + i) * 6, 100 - phase * 100)
		z.TextTransparency = if visible then 0.15 + 0.85 * math.abs(phase * 2 - 1) ^ 2 else 1
		z.Rotation = math.sin(t * 1.5 + i) * 12
	end
end

---------------------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------------------
local menuGui: ScreenGui? = nil
local menu = nil
local menuStyle = nil
local menuStartTime = os.clock()
local blendFrom: CFrame? = nil
local blendStart = 0
local menuMode = "main"
local pausedCameraCFrame: CFrame? = nil

local function keyCF(k): CFrame
	local cf = CFrame.lookAt(k.Pos, k.Look)
	if k.Yaw then
		cf = cf * CFrame.Angles(0, math.rad(k.Yaw), 0)
	end
	return cf
end

local function shotCFrame(shot, t: number): CFrame
	local d = shot.Duration or 20
	local a = (1 - math.cos(math.pi * ((t / d) % 2))) / 2
	local cf = keyCF(shot.From):Lerp(keyCF(shot.To), a)
	local s = shot.Sway or 0
	if s > 0 then
		local nx = math.noise(t * 0.25, 1.3) * s
		local ny = math.noise(t * 0.21, 7.1) * s
		cf = cf * CFrame.new(nx * 0.3, ny * 0.3, 0) * CFrame.Angles(ny * 0.03, nx * 0.03, 0)
	end
	if shot.Shake then
		cf = cf * CFrame.Angles((math.random() - 0.5) * shot.Shake, (math.random() - 0.5) * shot.Shake, 0)
	end
	return cf
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local focus = Lighting:FindFirstChild("Focus") :: DepthOfFieldEffect?
local blur = Lighting:FindFirstChild("Blur") :: BlurEffect?

local function menuCameraStep()
	if not menuStyle then
		return
	end
	local shot = menuStyle.Camera
	local t = os.clock() - menuStartTime
	local target = shotCFrame(shot, t)
	if blendFrom then
		local a = smooth((os.clock() - blendStart) / 1.6)
		target = (blendFrom :: CFrame):Lerp(target, a)
		if a >= 1 then
			blendFrom = nil
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = target
	camera.FieldOfView = shot.FOV or 50
	if focus then
		if shot.Focus then
			focus.Enabled = true
			focus.FocusDistance = (target.Position - shot.Focus).Magnitude
			focus.InFocusRadius = 3
			focus.FarIntensity = 0.4
			focus.NearIntensity = 0.6
		else
			focus.Enabled = false
		end
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	updateZzz(t, menuMode == "main")
end

local picker: Frame? = nil
local pickerMenuLabel: TextLabel? = nil
local pickerGfxLabel: TextLabel? = nil

refreshPicker = function()
	local ms = Settings.Get("MenuStyle")
	local gs = Settings.Get("Graphics")
	if pickerMenuLabel then
		pickerMenuLabel.Text = string.format("%s  %d/%d", ms, table.find(Config.MenuStyles, ms) or 1, #Config.MenuStyles)
	end
	if pickerGfxLabel then
		pickerGfxLabel.Text = string.format("%s  %d/%d", gs, table.find(Config.GraphicsPresets, gs) or 1, #Config.GraphicsPresets)
	end
end

local buildMenu: (string) -> ()
local actions = {}

local function setMenuStyle(name: string)
	if name == Settings.Get("MenuStyle") and menu then
		return
	end
	Settings.Set("MenuStyle", name)
	refreshPicker()
	if menu then
		blendFrom = camera.CFrame
		blendStart = os.clock()
		buildMenu(menuMode)
	end
end

local function cycle(list: { string }, current: string, d: number): string
	local i = table.find(list, current) or 1
	return list[(i - 1 + d) % #list + 1]
end

local function buildPicker()
	local holder = UI.new("Frame", {
		Name = "StylePicker",
		BackgroundColor3 = rgb(10, 10, 14),
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(860, 58),
		ZIndex = 45,
		Visible = false,
		Parent = overlayCanvas,
	}, { UI.corner(29), UI.stroke(1, Color3.new(1, 1, 1), 0.85, true) })
	local function group(x: number, caption: string, onLeft, onRight): TextLabel
		UI.label({
			Text = caption,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = rgb(140, 146, 160),
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(90, 58),
			ZIndex = 46,
			Parent = holder,
		})
		local function arrow(text: string, ax: number, fn)
			local b = UI.new("TextButton", {
				Text = text,
				Font = Enum.Font.GothamBold,
				TextSize = 26,
				TextColor3 = Color3.new(1, 1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.9,
				AutoButtonColor = true,
				Position = UDim2.fromOffset(ax, 11),
				Size = UDim2.fromOffset(36, 36),
				ZIndex = 46,
				Parent = holder,
			}, { UI.round() })
			b.Activated:Connect(function()
				Audio.play("UIClick")
				fn()
			end)
		end
		arrow("‹", x + 88, onLeft)
		local value = UI.label({
			Font = Enum.Font.GothamMedium,
			TextSize = 18,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(x + 128, 0),
			Size = UDim2.fromOffset(180, 58),
			ZIndex = 46,
			Parent = holder,
		})
		arrow("›", x + 312, onRight)
		return value
	end
	pickerMenuLabel = group(26, "MENU [1-5]", function()
		setMenuStyle(cycle(Config.MenuStyles, Settings.Get("MenuStyle"), -1))
	end, function()
		setMenuStyle(cycle(Config.MenuStyles, Settings.Get("MenuStyle"), 1))
	end)
	pickerGfxLabel = group(432, "GRAPHICS [G]", function()
		Settings.Set("Graphics", cycle(Config.GraphicsPresets, Settings.Get("Graphics"), -1))
		refreshPicker()
	end, function()
		Settings.Set("Graphics", cycle(Config.GraphicsPresets, Settings.Get("Graphics"), 1))
		refreshPicker()
	end)
	local close = UI.new("TextButton", {
		Text = "×",
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextColor3 = rgb(160, 160, 170),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -44, 0, 11),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 46,
		Parent = holder,
	})
	close.Activated:Connect(function()
		holder.Visible = false
	end)
	picker = holder
	refreshPicker()
end
buildPicker()

local function setPickerVisible(on: boolean)
	if picker then
		(picker :: Frame).Visible = on and Config.ShowStylePicker
	end
end

buildMenu = function(mode: string)
	menuMode = mode
	if menu then
		menu:Destroy()
		menu = nil
	end
	if menuGui then
		(menuGui :: ScreenGui):Destroy()
	end
	local styleName = Settings.Get("MenuStyle")
	local module = StylesFolder:FindFirstChild(styleName) or StylesFolder:FindFirstChild("Cinematic")
	menuStyle = require(module :: ModuleScript)
	local gui = UI.new("ScreenGui", {
		Name = "Menu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	menuGui = gui
	local full = UI.full(gui, "Full")
	local canvas = UI.canvas(gui)
	-- keeps the mouse free in first person while the menu is open
	UI.new("TextButton", {
		Name = "MouseUnlock",
		Modal = true,
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Parent = gui,
	})
	menu = MenuController.new(menuStyle, {
		Gui = gui,
		Canvas = canvas,
		Full = full,
		Mode = mode,
		Actions = actions,
	})
	if blur then
		blur.Size = menuStyle.MenuBlur or 0
		blur.Enabled = (menuStyle.MenuBlur or 0) > 0
	end
	Audio.music(menuStyle.Music, 1.2)
	refreshPicker()
end

local function openMenu(mode: string)
	state = if mode == "pause" then "paused" else "menu"
	menuStartTime = os.clock()
	blendFrom = camera.CFrame
	blendStart = os.clock()
	RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, menuCameraStep)
	buildMenu(mode)
	setPickerVisible(mode == "main")
	crosshair.Visible = false
	interactHint.Visible = false
	pauseButton.Visible = false
end

local function closeMenu(done: () -> ())
	setPickerVisible(false)
	if menu then
		local m = menu
		menu = nil
		m:Close(function()
			if menuGui then
				(menuGui :: ScreenGui):Destroy()
				menuGui = nil
			end
			done()
		end)
	else
		done()
	end
end

local function stopMenuCamera()
	RunService:UnbindFromRenderStep("MenuCamera")
	if focus then
		focus.Enabled = false
	end
	if blur then
		blur.Enabled = false
	end
	updateZzz(0, false)
end

---------------------------------------------------------------------------------------
-- Camera tween helper (Scriptable camera)
---------------------------------------------------------------------------------------
local function cameraTween(from: CFrame, to: CFrame, duration: number, fovTo: number?)
	local fov0 = camera.FieldOfView
	local start = os.clock()
	while true do
		local a = smooth((os.clock() - start) / duration)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = from:Lerp(to, a)
		if fovTo then
			camera.FieldOfView = fov0 + (fovTo - fov0) * a
		end
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

---------------------------------------------------------------------------------------
-- Interactions
---------------------------------------------------------------------------------------
local alarmRinging = false
local curtainsOpen = false
local character: Model? = nil
local humanoid: Humanoid? = nil

local function stopAlarm()
	if alarmRinging then
		alarmRinging = false
		if alarm then
			alarm:Stop()
		end
		clockText.Visible = true
		clockText.Text = "7:00"
		Audio.play("Click")
		say("Morty: ...seven AM. Aw jeez.")
	end
end

local function slideCurtains(open: boolean)
	curtainsOpen = open
	Audio.play("Cloth", 1.1)
	for _, name in { "CurtainLeft", "CurtainRight" } do
		local m = house:FindFirstChild(name) :: Model?
		if m then
			local dir = m:GetAttribute("SlideDir") or 1
			if m:GetAttribute("ClosedPivot") == nil then
				m:SetAttribute("ClosedPivot", m:GetPivot())
			end
			local closed = m:GetAttribute("ClosedPivot") :: CFrame
			local target = if open then closed + Vector3.new(dir * 1.25, 0, 0) else closed
			local from = m:GetPivot()
			task.spawn(function()
				local start = os.clock()
				while true do
					local a = smooth((os.clock() - start) / 0.7)
					m:PivotTo(from:Lerp(target, a))
					if a >= 1 then
						break
					end
					RunService.Heartbeat:Wait()
				end
			end)
		end
	end
end

local handlers = {}
handlers.AlarmClock = function()
	if alarmRinging then
		stopAlarm()
	else
		Audio.play("Click")
		say("It's " .. clockText.Text .. ".")
	end
end
handlers.NightLamp = function()
	Graphics.SetLight("NightLamp", not Graphics.IsLightOn("NightLamp"))
	Audio.play("Click")
end
handlers.DeskLamp = function()
	Graphics.SetLight("DeskLamp", not Graphics.IsLightOn("DeskLamp"))
	Audio.play("Click")
end
handlers.LightSwitch = function(model: Instance)
	local on = not Graphics.IsLightOn("CeilingLight")
	Graphics.SetLight("CeilingLight", on)
	Audio.play("Switch")
	local toggle = model:FindFirstChild("Toggle") :: BasePart?
	if toggle then
		if toggle:GetAttribute("BaseCF") == nil then
			toggle:SetAttribute("BaseCF", toggle.CFrame)
		end
		toggle.CFrame = (toggle:GetAttribute("BaseCF") :: CFrame) * CFrame.new(0, if on then 0.06 else 0, 0)
	end
end
handlers.Curtains = function()
	slideCurtains(not curtainsOpen)
end
handlers.Monitor = function()
	Audio.play("Click")
	say("Morty: Homework, homework... and 38 unread messages from Rick. Nope.")
end
local doorLines = {
	"Rick (behind the door): Not now, Morty! I'm in the middle of something! *burp*",
	"Rick: Morty, I swear, if you open that door I'll turn you into a pickle.",
	"The door is locked. From the outside. Weird.",
}
local doorIndex = 0
handlers.Door = function()
	Audio.play("Click", 0.7)
	doorIndex = doorIndex % #doorLines + 1
	say(doorLines[doorIndex], 4.5)
end

local function interactText(model: Instance): string
	local text = model:GetAttribute("InteractText") or "Use"
	local id = model:GetAttribute("Interact")
	if id == "Curtains" then
		text = if curtainsOpen then "Close curtains" else "Open curtains"
	elseif id == "AlarmClock" and not alarmRinging then
		text = "Check the time"
	end
	return text
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function findTarget(maxDist: number): Instance?
	local filter: { Instance } = { npcHead, npc:FindFirstChild("Arm") :: Instance }
	if character then
		table.insert(filter, character :: Model)
	end
	rayParams.FilterDescendantsInstances = filter
	local cf = camera.CFrame
	local result = workspace:Raycast(cf.Position, cf.LookVector * maxDist, rayParams)
	if not result then
		return nil
	end
	local inst: Instance? = result.Instance
	while inst and inst ~= house and inst ~= workspace do
		if inst:GetAttribute("Interact") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local currentTarget: Instance? = nil
local function updateInteraction()
	local target = findTarget(if state == "lying" then 7 else 9)
	if state == "lying" and target and target:GetAttribute("Interact") ~= "AlarmClock" then
		target = nil
	end
	currentTarget = target
	if target then
		interactHint.Text = (if isTouch then "" else "[E]  ") .. interactText(target)
		interactHint.Visible = true
		crosshair.Size = UDim2.fromOffset(10, 10)
	else
		interactHint.Visible = false
		crosshair.Size = UDim2.fromOffset(6, 6)
	end
	useButton.Visible = isTouch and target ~= nil
end

local function useTarget()
	local target = currentTarget
	if target then
		local id = target:GetAttribute("Interact")
		local h = handlers[id]
		if h then
			h(target)
		end
	end
end

---------------------------------------------------------------------------------------
-- Character (first person body, head bob)
---------------------------------------------------------------------------------------
local bodyParts: { BasePart } = {}
local function onCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	table.clear(bodyParts)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("BodyGroup") then
			table.insert(bodyParts, d)
		end
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

local bobTime = 0
local bobAmount = 0
local function playingStep(dt: number)
	if state ~= "playing" then
		return
	end
	local showBody = Settings.Get("ShowBody")
	for _, p in bodyParts do
		local group = p:GetAttribute("BodyGroup")
		if group == "Head" then
			p.LocalTransparencyModifier = 1
		else
			p.LocalTransparencyModifier = if showBody then 0 else 1
		end
	end
	local hum = humanoid
	if hum then
		local root = hum.RootPart
		local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
		local moving = speed > 1 and hum.FloorMaterial ~= Enum.Material.Air
		bobAmount += ((if moving and Settings.Get("HeadBob") then 1 else 0) - bobAmount) * math.min(dt * 8, 1)
		bobTime += dt * (speed / 9) * 9
		local y = math.sin(bobTime) * 0.08 * bobAmount
		local x = math.cos(bobTime * 0.5) * 0.05 * bobAmount
		hum.CameraOffset = Vector3.new(x, y, if showBody then -0.35 else 0)
	end
	camera.FieldOfView = Settings.Get("FOV")
	UserInputService.MouseIconEnabled = false
	crosshair.Visible = true
	if alarmRinging then
		clockText.Visible = math.floor(os.clock() * 2) % 2 == 0
	end
	updateInteraction()
end
RunService:BindToRenderStep("PlayingStep", Enum.RenderPriority.Camera.Value + 2, playingStep)

---------------------------------------------------------------------------------------
-- Waking up
---------------------------------------------------------------------------------------
local lieYaw, liePitch = 0, 0
local lieBase: CFrame = CFrame.new()
local spawnReady = false
local canGetUp = false
local touchLook: Vector2 = Vector2.zero

local function lyingEye(): CFrame
	local offset = npcHead:GetAttribute("EyeOffset") or Vector3.new(0, 0.05, -0.55)
	local cf = headCore.CFrame * CFrame.new(offset)
	-- look straight out of the face, keep "up" towards the top of the head
	return CFrame.lookAt(cf.Position, cf.Position + headCore.CFrame.LookVector, headCore.CFrame.UpVector)
end

local function lyingStep(_dt: number)
	if state ~= "lying" then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	local delta = UserInputService:GetMouseDelta() + touchLook
	touchLook = Vector2.zero
	local k = 0.0045
	lieYaw = math.clamp(lieYaw - delta.X * k, -1.75, 1.75)
	liePitch = math.clamp(liePitch - delta.Y * k, -1.1, 0.9)
	local breathe = math.sin(os.clock() * 1.6) * 0.02
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = lieBase * CFrame.new(0, 0, breathe) * CFrame.Angles(0, lieYaw, 0) * CFrame.Angles(liePitch, 0, 0)
	camera.FieldOfView = Settings.Get("FOV")
	crosshair.Visible = true
	updateInteraction()
	if alarmRinging then
		clockText.Visible = math.floor(os.clock() * 2) % 2 == 0
	end
end
RunService:BindToRenderStep("LyingStep", Enum.RenderPriority.Camera.Value + 2, lyingStep)

UserInputService.InputChanged:Connect(function(input, processed)
	if state == "lying" and input.UserInputType == Enum.UserInputType.Touch and not processed then
		touchLook += Vector2.new(input.Delta.X, input.Delta.Y)
	end
end)

local function wakeUp()
	state = "waking"
	stopMenuCamera()
	Audio.music(nil, 2.5)
	Audio.play("Whoosh")
	local face = headCore.CFrame
	local approach = CFrame.lookAt(face.Position + face.LookVector * 2.4 + Vector3.new(0.9, 0.5, 0.9), face.Position)
	cameraTween(camera.CFrame, approach, 2.0, 50)
	fadeTo(1, 0.6)
	task.wait(0.7)

	-- (black screen) become Morty
	if snore then
		snore:Stop()
	end
	setSleeping(false)
	lidOpen.Value = 0
	spawnReady = false
	canGetUp = false
	task.spawn(function()
		pcall(function()
			Remotes.RequestSpawn:InvokeServer()
		end)
		spawnReady = true
	end)
	lieBase = lyingEye()
	lieYaw, liePitch = 0.15, 0
	camera.CFrame = lieBase
	camera.FieldOfView = Settings.Get("FOV")
	if blur then
		blur.Size = 20
		blur.Enabled = true
	end
	fade.BackgroundTransparency = 1
	clockText.Text = "7:00"
	alarmRinging = true
	if alarm then
		alarm:Play()
	end
	state = "lying"
	task.wait(1.4)

	-- eyes open... close... open
	lids(0.18, 0.5)
	task.wait(0.25)
	lids(0, 0.2)
	task.wait(0.5)
	Audio.play("Gasp")
	lids(0.45, 0.55)
	task.wait(0.2)
	lids(0.05, 0.18)
	task.wait(0.15)
	if blur then
		UI.tween(blur, 1.8, { Size = 0 }, Enum.EasingStyle.Sine)
	end
	lids(1, 1.1)
	if blur then
		task.delay(1.8, function()
			if state ~= "menu" then
				blur.Enabled = false
			end
		end)
	end
	canGetUp = true
	if state == "lying" then
		showPrompt(if isTouch then "Look around. Tap GET UP when ready." else "Look around with the mouse.   [SPACE] get up   ·   [E] on the alarm clock to turn it off")
		getUpButton.Visible = isTouch
	end
end

local function getUp()
	if state ~= "lying" or not canGetUp then
		return
	end
	state = "gettingup"
	-- make sure the server has created the character before we hand over
	local waitStart = os.clock()
	while not spawnReady and os.clock() - waitStart < 10 do
		task.wait(0.1)
	end
	showPrompt(nil)
	getUpButton.Visible = false
	crosshair.Visible = false
	interactHint.Visible = false
	useButton.Visible = false
	Audio.play("Cloth")
	task.delay(0.5, function()
		Audio.play("GetUp")
	end)

	local sitPos = Vector3.new(-6.95, 4.55, -4.9)
	local sitCF = CFrame.lookAt(sitPos, sitPos + Vector3.new(1, -0.28, 0.35))
	local standPos = wakePoint.Position + Vector3.new(0, 1.5, 0)
	local standCF = CFrame.lookAt(standPos, standPos + wakePoint.CFrame.LookVector * 10 + Vector3.new(0, -0.8, 0))
	cameraTween(camera.CFrame, sitCF, 1.4)
	task.wait(0.15)
	cameraTween(sitCF, standCF, 1.1)

	-- hand over to the real character
	pcall(function()
		Remotes.ReleaseCharacter:FireServer()
	end)
	local t0 = os.clock()
	repeat
		RunService.RenderStepped:Wait()
	until (humanoid and humanoid.RootPart and (humanoid.RootPart.Position - wakePoint.Position).Magnitude < 3) or os.clock() - t0 > 3
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CFrame = standCF
	setControls(true)
	state = "playing"
	pauseButton.Visible = isTouch
	if alarmRinging then
		showPrompt("Walk with WASD. Turn off that alarm: look at it and press [E].")
	else
		showPrompt(if isTouch then "Explore Morty's room." else "WASD walk  ·  [E] use  ·  [P] pause  ·  [G] graphics")
	end
	task.delay(7, function()
		if state == "playing" then
			showPrompt(nil)
		end
	end)
end

---------------------------------------------------------------------------------------
-- Pause / resume / back to menu
---------------------------------------------------------------------------------------
local function pause()
	if state ~= "playing" then
		return
	end
	pausedCameraCFrame = camera.CFrame
	setControls(false)
	showPrompt(nil)
	if character then
		for _, d in (character :: Model):GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
	end
	openMenu("pause")
end

actions.Resume = function()
	closeMenu(function()
		stopMenuCamera()
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if pausedCameraCFrame then
			camera.CFrame = pausedCameraCFrame
		end
		camera.CameraType = Enum.CameraType.Custom
		setControls(true)
		state = "playing"
		pauseButton.Visible = isTouch
	end)
end

actions.Play = function()
	closeMenu(function()
		task.spawn(wakeUp)
	end)
end

actions.Quit = function()
	player:Kick("See you later, Morty!")
end

actions.MainMenu = function()
	closeMenu(function()
		fadeTo(1, 0.5)
		task.wait(0.55)
		stopMenuCamera()
		pcall(function()
			Remotes.ReturnToMenu:FireServer()
		end)
		character = nil
		humanoid = nil
		setControls(false)
		if alarm then
			alarm:Stop()
		end
		alarmRinging = false
		clockText.Visible = true
		if curtainsOpen then
			slideCurtains(false)
		end
		setSleeping(true)
		applyGraphics(Settings.Get("Graphics"), true)
		if snore then
			snore:Play()
		end
		openMenu("main")
		fadeTo(0, 1.2)
	end)
end

---------------------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	local key = input.KeyCode
	if state == "lying" then
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA then
			task.spawn(getUp)
			return
		end
	end
	if state == "lying" or state == "playing" then
		if key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonX or (input.UserInputType == Enum.UserInputType.MouseButton1 and not processed) then
			useTarget()
			return
		end
	end
	if processed then
		return
	end
	if state == "playing" and (key == Enum.KeyCode.P or key == Enum.KeyCode.M or key == Enum.KeyCode.ButtonStart) then
		pause()
	elseif key == Enum.KeyCode.G then
		Settings.Set("Graphics", cycle(Config.GraphicsPresets, Settings.Get("Graphics"), 1))
		refreshPicker()
	elseif state == "menu" and menuMode == "main" then
		local n = ({
			[Enum.KeyCode.One] = 1,
			[Enum.KeyCode.Two] = 2,
			[Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5,
		})[key]
		if n and Config.MenuStyles[n] then
			setMenuStyle(Config.MenuStyles[n])
		end
	end
end)

getUpButton.Activated:Connect(function()
	task.spawn(getUp)
end)
useButton.Activated:Connect(useTarget)
pauseButton.Activated:Connect(pause)

---------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------
if not game:IsLoaded() then
	game.Loaded:Wait()
end
setSleeping(true)
if snore then
	snore:Play()
end
camera.CameraType = Enum.CameraType.Scriptable
openMenu("main")
blendFrom = nil
task.wait(0.4)
fadeTo(0, 1.6)
