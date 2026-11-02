--[[
	Client core:
	  * main menu (5 styles, style picker, settings, chapters) + pause menu
	  * first person gameplay helpers: interactions, body / head bob, lying in bed, getting up
	  * an `api` table that the Story module uses to run the chapters
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
local Lang = require(GameFolder:WaitForChild("Lang"))
local Fx = require(GameFolder:WaitForChild("Fx"))
local Director = require(GameFolder:WaitForChild("Director"))
local Dialogue = require(GameFolder:WaitForChild("Dialogue"))
local Scenes = require(GameFolder:WaitForChild("Scenes"))
local MenuController = require(GameFolder:WaitForChild("MenuController"))
local Story = require(GameFolder:WaitForChild("Story"))
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
task.spawn(function()
	local list = {}
	for _, def in Config.Sounds do
		if def.Id and def.Id ~= "" then
			local s = Instance.new("Sound")
			s.SoundId = def.Id
			table.insert(list, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end)
Fx.init()

---------------------------------------------------------------------------------------
-- Overlay UI
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
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, -0.62),
	ZIndex = 20,
	Parent = overlay,
}, { UI.gradient(nil, { 0, 0, 0, 1 }, 90) })
local lidBottom = UI.new("Frame", {
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, 1.62),
	ZIndex = 20,
	Parent = overlay,
}, { UI.gradient(nil, { 1, 0, 0, 0 }, 90) })

local crosshair = UI.new("Frame", {
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
	Font = Enum.Font.GothamMedium,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 26),
	Size = UDim2.fromOffset(700, 30),
	Visible = false,
	ZIndex = 10,
	Parent = overlayCanvas,
})
UI.stroke(1.5, Color3.new(0, 0, 0), 0.3).Parent = interactHint

local function fadingLabel(name: string, size: number, pos: UDim2, anchorY: number, width: number, height: number)
	local l = UI.label({
		Name = name,
		Font = Enum.Font.GothamMedium,
		TextSize = size,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, anchorY),
		Position = pos,
		Size = UDim2.fromOffset(width, height),
		ZIndex = 10,
		Parent = overlayCanvas,
	})
	local s = UI.stroke(1.8, Color3.new(0, 0, 0), 1)
	s.Parent = l
	return l, s
end
local promptLabel, promptStroke = fadingLabel("Prompt", 24, UDim2.new(0.5, 0, 1, -70), 1, 1300, 34)
local subtitle, subtitleStroke = fadingLabel("Subtitle", 26, UDim2.new(0.5, 0, 1, -130), 1, 1100, 70)
local toast, toastStroke = fadingLabel("Toast", 20, UDim2.new(0.5, 0, 0, 60), 0, 1200, 28)

-- objective (top left)
local objective = UI.new("Frame", {
	Name = "Objective",
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(40, 40),
	Size = UDim2.fromOffset(10, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	ZIndex = 10,
	Parent = overlayCanvas,
}, { UI.corner(10), UI.padding(16, 0, 18, 0) })
local objectiveDot = UI.new("Frame", {
	BackgroundColor3 = rgb(250, 222, 70),
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(10, 10),
	Parent = objective,
}, { UI.round() })
local objectiveText = UI.label({
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	Position = UDim2.fromOffset(22, 0),
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = objective,
})

local subtitleToken = 0
local function say(text: any, seconds: number?)
	subtitleToken += 1
	local my = subtitleToken
	subtitle.Text = Lang.t(text)
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

local promptKey: any = nil
local function showPrompt(key: any)
	promptKey = key
	if key then
		promptLabel.Text = Lang.t(key)
		UI.tween(promptLabel, 0.4, { TextTransparency = 0 })
		UI.tween(promptStroke, 0.4, { Transparency = 0.4 })
	else
		UI.tween(promptLabel, 0.3, { TextTransparency = 1 })
		UI.tween(promptStroke, 0.3, { Transparency = 1 })
	end
end

local objectiveKey: any = nil
local function setObjective(key: any)
	objectiveKey = key
	if key then
		objectiveText.Text = Lang.t(key)
		Audio.play("UISwoosh", 1.2)
		UI.tween(objective, 0.4, { BackgroundTransparency = 0.45 })
		UI.tween(objectiveText, 0.4, { TextTransparency = 0 })
		UI.tween(objectiveDot, 0.4, { BackgroundTransparency = 0 })
	else
		UI.tween(objective, 0.4, { BackgroundTransparency = 1 })
		UI.tween(objectiveText, 0.4, { TextTransparency = 1 })
		UI.tween(objectiveDot, 0.4, { BackgroundTransparency = 1 })
	end
end

local lidOpen = Instance.new("NumberValue")
lidOpen.Value = 1
lidOpen.Changed:Connect(function()
	local o = lidOpen.Value
	lidTop.Position = UDim2.fromScale(0, -0.62 * o)
	lidBottom.Position = UDim2.fromScale(0, 1 + 0.62 * o)
end)
local function lids(target: number, t: number)
	if t <= 0 then
		lidOpen.Value = target
		return
	end
	UI.tween(lidOpen, t, { Value = target }, Enum.EasingStyle.Sine)
	task.wait(t)
end

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local function touchButton(text: string, pos: UDim2, w: number?)
	return UI.new("TextButton", {
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(1, 1),
		Position = pos,
		Size = UDim2.fromOffset(w or 170, 70),
		Visible = false,
		ZIndex = 15,
		Parent = overlayCanvas,
	}, { UI.corner(14), UI.stroke(2, Color3.new(1, 1, 1), 0.6, true) })
end
local getUpButton = touchButton(Lang.t("touch.getup"), UDim2.new(1, -60, 1, -60))
local useButton = touchButton(Lang.t("touch.use"), UDim2.new(1, -60, 1, -150))
local pauseButton = touchButton("II", UDim2.new(1, -40, 0, 150), 70)

---------------------------------------------------------------------------------------
-- Room sounds
---------------------------------------------------------------------------------------
local snore = Audio.make("Snore", headCore)
local alarm = Audio.make("Alarm", clockFace)
local clockTick = Audio.make("ClockTick", clockFace)
if clockTick then
	clockTick:Play()
end

---------------------------------------------------------------------------------------
-- Settings -> world
---------------------------------------------------------------------------------------
local state = "menu" -- menu | story | playing | paused
local refreshPicker: () -> ()

local function applyMenuGraphics(name: string, instant: boolean?)
	Graphics.Apply(name, instant)
	local p = Graphics.Get(name)
	if p then
		Scenes.setAmbience(p.Ambience)
	end
end

Audio.setGroupVolume("Music", Settings.Get("Music"))
Audio.setGroupVolume("SFX", Settings.Get("Sound"))
Audio.setGroupVolume("Ambience", Settings.Get("Sound"))
Graphics.SetBrightnessOffset(Settings.Get("Brightness") * 0.6)
pcall(function()
	UserInputService.MouseDeltaSensitivity = Settings.Get("Sensitivity")
end)
applyMenuGraphics(Settings.Get("Graphics"), true)

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
		-- the menu preset only changes the menu / Morty's room at night
		if state == "menu" then
			applyMenuGraphics(value)
		end
		refreshPicker()
		local p = Graphics.Get(value)
		showToast("GRAPHICS: " .. string.upper(value) .. (if p then "  —  " .. p.Description else ""))
	elseif key == "Language" then
		getUpButton.Text = Lang.t("touch.getup")
		useButton.Text = Lang.t("touch.use")
		if promptKey then
			promptLabel.Text = Lang.t(promptKey)
		end
		if objectiveKey then
			objectiveText.Text = Lang.t(objectiveKey)
		end
	end
end)

---------------------------------------------------------------------------------------
-- Sleeping Morty in the bed
---------------------------------------------------------------------------------------
local function setLocalVisible(container: Instance, visible: boolean)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

local blanketOn = bed:WaitForChild("BlanketOn")
local blanketOff = bed:WaitForChild("BlanketOff")
local function setSleeping(sleeping: boolean)
	setLocalVisible(npcHead, sleeping)
	setLocalVisible(npc:WaitForChild("Arm"), sleeping)
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

local zzz = UI.new("BillboardGui", {
	Name = "Zzz",
	Adornee = headCore,
	Size = UDim2.fromOffset(120, 140),
	StudsOffset = Vector3.new(0.6, 1.6, 0),
	LightInfluence = 0,
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
-- Character helpers
---------------------------------------------------------------------------------------
local character: Model? = nil
local humanoid: Humanoid? = nil
local bodyParts: { BasePart } = {}
local characterHidden = true

local function onCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	table.clear(bodyParts)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(bodyParts, d)
		end
	end
end
player.CharacterAdded:Connect(onCharacter)
player.CharacterRemoving:Connect(function()
	character = nil
	humanoid = nil
	table.clear(bodyParts)
end)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

local function rootPart(): BasePart?
	return humanoid and humanoid.RootPart or nil
end

---------------------------------------------------------------------------------------
-- Interactions
---------------------------------------------------------------------------------------
local interactEnabled = false
local allowOnly: { [string]: boolean }? = nil
local handlers: { [string]: (Instance) -> () } = {}
local alarmRinging = false
local curtainsOpen = false

local function setAlarm(on: boolean)
	alarmRinging = on
	if alarm then
		if on then
			alarm:Play()
		else
			alarm:Stop()
		end
	end
	clockText.Visible = true
	if on then
		clockText.Text = "7:00"
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
					local a = Director.ease((os.clock() - start) / 0.7)
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

handlers.AlarmClock = function()
	if alarmRinging then
		setAlarm(false)
		Audio.play("Click")
		say({ ru = "Морти: ...семь утра. Ох, божечки.", en = "Morty: ...seven AM. Aw jeez." })
	else
		Audio.play("Click")
		say({ ru = "Сейчас " .. clockText.Text .. ".", en = "It's " .. clockText.Text .. "." })
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
	say({ ru = "Морти: Домашка, домашка... и 38 непрочитанных от Рика. Не-а.", en = "Morty: Homework, homework... and 38 unread messages from Rick. Nope." })
end
handlers.FrontDoor = function()
	Audio.play("Click", 0.7)
	say({ ru = "Морти: Сначала завтрак. Мама убьёт.", en = "Morty: Breakfast first. Mom will kill me." })
end
handlers.SummerDoor = function()
	Audio.play("Click", 0.7)
	say({ ru = "Саммер (за дверью): Даже не думай, Морти!", en = "Summer (behind the door): Don't even think about it, Morty!" })
end

local function interactText(model: Instance): string
	local id = model:GetAttribute("Interact")
	if id == "Curtains" and curtainsOpen then
		return Lang.t("interact.Curtains.open")
	elseif id == "AlarmClock" and not alarmRinging then
		return Lang.t("interact.AlarmClock.idle")
	elseif id == "Door" and model:GetAttribute("Open") then
		return Lang.t("interact.Door.open")
	end
	local key = "interact." .. tostring(id)
	if Lang.strings[key] then
		return Lang.t(key)
	end
	return model:GetAttribute("InteractText") or "Use"
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function findTarget(maxDist: number): Instance?
	local filter: { Instance } = { npcHead }
	local arm = npc:FindFirstChild("Arm")
	if arm then
		table.insert(filter, arm)
	end
	if character then
		table.insert(filter, character :: Model)
	end
	local cast = workspace:FindFirstChild("Cast")
	if cast then
		table.insert(filter, cast)
	end
	local fxf = workspace:FindFirstChild("ClientFx")
	if fxf then
		table.insert(filter, fxf)
	end
	rayParams.FilterDescendantsInstances = filter
	local cf = camera.CFrame
	local result = workspace:Raycast(cf.Position, cf.LookVector * maxDist, rayParams)
	if not result then
		return nil
	end
	local inst: Instance? = result.Instance
	while inst and inst ~= workspace do
		if inst:GetAttribute("Interact") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local currentTarget: Instance? = nil
local function updateInteraction(maxDist: number)
	local target = if interactEnabled then findTarget(maxDist) else nil
	if target and allowOnly and not allowOnly[target:GetAttribute("Interact")] then
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
		local h = handlers[target:GetAttribute("Interact")]
		if h then
			h(target)
		end
	end
end

---------------------------------------------------------------------------------------
-- Per-frame gameplay (first person body, head bob, interaction)
---------------------------------------------------------------------------------------
local bobTime, bobAmount = 0, 0
RunService:BindToRenderStep("PlayingStep", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if characterHidden then
		for _, p in bodyParts do
			p.LocalTransparencyModifier = 1
		end
	end
	if alarmRinging then
		clockText.Visible = math.floor(os.clock() * 2) % 2 == 0
	end
	if state ~= "playing" then
		return
	end
	local showBody = Settings.Get("ShowBody")
	if not characterHidden then
		for _, p in bodyParts do
			local group = p:GetAttribute("BodyGroup")
			if group then
				p.LocalTransparencyModifier = if group == "Head" or not showBody then 1 else 0
			end
		end
	end
	local hum = humanoid
	if hum then
		local root = hum.RootPart
		local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
		local moving = speed > 1 and hum.FloorMaterial ~= Enum.Material.Air
		bobAmount += ((if moving and Settings.Get("HeadBob") then 1 else 0) - bobAmount) * math.min(dt * 8, 1)
		bobTime += dt * speed
		hum.CameraOffset = Vector3.new(math.cos(bobTime * 0.5) * 0.05 * bobAmount, math.sin(bobTime) * 0.08 * bobAmount, if showBody then -0.35 else 0)
	end
	camera.FieldOfView = Settings.Get("FOV")
	UserInputService.MouseIconEnabled = false
	crosshair.Visible = true
	updateInteraction(9)
end)

---------------------------------------------------------------------------------------
-- Lying down (bed / operating table) + getting up
---------------------------------------------------------------------------------------
local lyingActive = false
local getUpPressed = false

local function lie(eyeCF: CFrame, opts: { [string]: any }?)
	local o = opts or {}
	state = "story"
	setControls(false)
	Director.cut(eyeCF, Settings.Get("FOV"))
	Director.freeLook(true, { yaw = o.yaw or 1.75, pitchUp = 0.9, pitchDown = 1.1 })
	Director.resetLook()
	lyingActive = true
	getUpPressed = false
	interactEnabled = o.interact ~= false
	allowOnly = o.allowOnly
	crosshair.Visible = interactEnabled
	if o.blink then
		lidOpen.Value = 0
		task.wait(o.closedTime or 1.2)
		lids(0.18, 0.5)
		task.wait(0.25)
		lids(0, 0.2)
		task.wait(0.5)
		Audio.play("Gasp")
		lids(0.45, 0.55)
		task.wait(0.2)
		lids(0.05, 0.18)
		task.wait(0.15)
		lids(1, 1.1)
	end
end

local function waitGetUp(promptK: any)
	showPrompt(promptK or (if isTouch then "hint.lying.touch" else "hint.lying.simple"))
	getUpButton.Visible = isTouch
	getUpPressed = false
	while not getUpPressed do
		RunService.RenderStepped:Wait()
		if interactEnabled then
			updateInteraction(7)
			crosshair.Visible = true
		end
	end
	showPrompt(nil)
	getUpButton.Visible = false
	lyingActive = false
	interactEnabled = false
	allowOnly = nil
	interactHint.Visible = false
	useButton.Visible = false
	crosshair.Visible = false
	Director.freeLook(false)
end

---------------------------------------------------------------------------------------
-- Spawning / releasing / teleporting the player's character
---------------------------------------------------------------------------------------
local function spawnCharacter()
	local ok = pcall(function()
		Remotes.RequestSpawn:InvokeServer()
	end)
	local t0 = os.clock()
	while not (character and humanoid and humanoid.RootPart) and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	return ok
end

local function release(cf: CFrame)
	pcall(function()
		Remotes.ReleaseCharacter:FireServer(cf)
	end)
	local t0 = os.clock()
	repeat
		RunService.RenderStepped:Wait()
		local r = rootPart()
	until (r and (r.Position - cf.Position).Magnitude < 3 and not r.Anchored) or os.clock() - t0 > 4
end

local function teleport(cf: CFrame)
	local char = character
	if char then
		local r = rootPart()
		if r then
			r.AssemblyLinearVelocity = Vector3.zero
		end
		char:PivotTo(cf)
	end
end

local function freeze(on: boolean)
	local r = rootPart()
	if r then
		if on then
			r.Anchored = true
			r:SetAttribute("ClientFrozen", true)
		elseif r:GetAttribute("ClientFrozen") then
			r.Anchored = false
			r:SetAttribute("ClientFrozen", nil)
		end
	end
end

-- hand control to the player (first person) looking along `lookCF` if given
local function gameplay(on: boolean, lookCF: CFrame?)
	if on then
		Director.stop()
		freeze(false)
		characterHidden = false
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if lookCF then
			camera.CFrame = lookCF
		end
		camera.CameraType = Enum.CameraType.Custom
		setControls(true)
		interactEnabled = true
		allowOnly = nil
		state = "playing"
		pauseButton.Visible = isTouch
	else
		setControls(false)
		interactEnabled = false
		interactHint.Visible = false
		useButton.Visible = false
		crosshair.Visible = false
		pauseButton.Visible = false
		state = "story"
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
		local a = Director.ease((os.clock() - blendStart) / 1.6)
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

do
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
	end, function()
		Settings.Set("Graphics", cycle(Config.GraphicsPresets, Settings.Get("Graphics"), 1))
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
	if mode == "pause" and styleName == "Monitor" then
		-- the Monitor menu lives on Morty's computer, which you can't see from everywhere
		styleName = "Cinematic"
	end
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

local function pauseCameraStep()
	-- pause: keep the current view, blurred, with a free mouse
	camera.CameraType = Enum.CameraType.Scriptable
	if pausedCameraCFrame then
		camera.CFrame = pausedCameraCFrame
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

local function openMenu(mode: string)
	state = if mode == "pause" then "paused" else "menu"
	Director.stop()
	menuStartTime = os.clock()
	blendFrom = camera.CFrame
	blendStart = os.clock()
	RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, if mode == "pause" then pauseCameraStep else menuCameraStep)
	buildMenu(mode)
	if mode == "pause" and blur then
		blur.Size = 14
		blur.Enabled = true
	end
	setPickerVisible(mode == "main")
	crosshair.Visible = false
	interactHint.Visible = false
	pauseButton.Visible = false
	useButton.Visible = false
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

---------------------------------------------------------------------------------------
-- The api handed to the Story module
---------------------------------------------------------------------------------------
local api = {}
api.house = house
api.headCore = headCore
api.npcHead = npcHead
api.wakePoint = wakePoint
api.isTouch = isTouch
api.handlers = handlers
function api.character()
	return character
end
function api.humanoid()
	return humanoid
end
function api.root()
	return rootPart()
end
function api.camera()
	return camera
end
api.spawn = spawnCharacter
api.release = release
api.teleport = teleport
api.freeze = freeze
api.gameplay = gameplay
api.lie = lie
api.waitGetUp = waitGetUp
api.lids = lids
api.say = say
api.prompt = showPrompt
api.objective = setObjective
api.toast = showToast
api.setSleeping = setSleeping
api.setAlarm = setAlarm
function api.alarmRinging()
	return alarmRinging
end
function api.snore(on: boolean)
	if snore then
		if on then
			snore:Play()
		else
			snore:Stop()
		end
	end
end
function api.hideCharacter(hidden: boolean)
	characterHidden = hidden
	if not hidden then
		for _, p in bodyParts do
			p.LocalTransparencyModifier = 0
		end
	end
end
function api.state(s: string?)
	if s then
		state = s
	end
	return state
end
function api.interact(on: boolean, only: { [string]: boolean }?)
	interactEnabled = on
	allowOnly = only
end
-- yields until the player uses an object with this Interact id
function api.waitInteract(id: string): Instance
	local done: Instance? = nil
	local old = handlers[id]
	handlers[id] = function(model)
		done = model
	end
	while not done do
		task.wait()
	end
	handlers[id] = old
	return done :: Instance
end
function api.waitNear(pos: Vector3, radius: number)
	while true do
		local r = rootPart()
		if r and (r.Position - pos).Magnitude <= radius then
			return
		end
		task.wait(0.1)
	end
end
function api.stopMenuCamera()
	stopMenuCamera()
end
function api.toMenu()
	actions.MainMenu()
end

---------------------------------------------------------------------------------------
-- Pause / resume / menu actions
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
		gameplay(true, pausedCameraCFrame)
	end)
end

local function startStory(chapter: number)
	closeMenu(function()
		stopMenuCamera()
		Audio.music(nil, 2)
		state = "story"
		Story.run(api, chapter)
	end)
end

actions.Play = function()
	startStory(1)
end

actions.Chapter = function(n: number)
	startStory(n)
end

actions.Quit = function()
	player:Kick("See you later, Morty!")
end

actions.MainMenu = function()
	closeMenu(function()
		Fx.fade(1, 0.5, true)
		Story.stop()
		Director.stop()
		Dialogue.hide()
		stopMenuCamera()
		pcall(function()
			Remotes.ReturnToMenu:FireServer()
		end)
		character = nil
		humanoid = nil
		gameplay(false)
		setAlarm(false)
		setObjective(nil)
		showPrompt(nil)
		if curtainsOpen then
			slideCurtains(false)
		end
		Story.reset(api)
		lidOpen.Value = 1
		setSleeping(true)
		applyMenuGraphics(Settings.Get("Graphics"), true)
		api.snore(true)
		openMenu("main")
		Fx.fade(0, 1.2)
	end)
end

---------------------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	local key = input.KeyCode
	if lyingActive and (key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA) then
		getUpPressed = true
		return
	end
	if (state == "playing" or lyingActive) and interactEnabled then
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
	elseif key == Enum.KeyCode.G and state == "menu" then
		Settings.Set("Graphics", cycle(Config.GraphicsPresets, Settings.Get("Graphics"), 1))
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
	getUpPressed = true
end)
useButton.Activated:Connect(useTarget)
pauseButton.Activated:Connect(pause)

---------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------
if not game:IsLoaded() then
	game.Loaded:Wait()
end
Fx.black(1)
setSleeping(true)
api.snore(true)
Story.init(api)
camera.CameraType = Enum.CameraType.Scriptable
openMenu("main")
blendFrom = nil
task.wait(0.4)
Fx.fade(0, 1.6)
