--!strict
-- Эффекты. Освещение по фазе (день — тёплые сумерки 17:30, оповещение/ночь — полночь, рассвет — 6:30,
-- лобби — ночь), экспозиция от настройки яркости и перка Night Owl, насыщенность; VHS-зерно и виньетка
-- (настройка Vhs); «радиус ужаса» (дрон → сердце → сердце+дыхание по дистанции до ближайшего опасного
-- пациента), музыка погони, стингер (не чаще раза в 25 с), тряска, мигание ламп, обесточивание, рассвет,
-- затемнение при падении, тряска рядом с Hollow Man, звуки событий пациентов и выключателей.
-- Все твины — только на клиенте.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Inmates = require(Shared:WaitForChild("Inmates"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Camera = require(script.Parent:WaitForChild("Camera"))

local FX = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Пресеты освещения
----------------------------------------------------------------------

type Preset = {
	ClockTime: number,
	Brightness: number,
	Exposure: number,
	Saturation: number,
	Ambient: Color3,
	Outdoor: Color3,
	Night: boolean, -- применять ночной подъём экспозиции (настройка яркости ×1.2, Night Owl)
}

local PRESETS: { [string]: Preset } = {
	Day = {
		ClockTime = 17.5,
		Brightness = 1.6,
		Exposure = 0.05,
		Saturation = -0.1,
		Ambient = Color3.fromRGB(78, 74, 86),
		Outdoor = Color3.fromRGB(120, 108, 100),
		Night = false,
	},
	Night = {
		ClockTime = 0,
		Brightness = 0.35,
		Exposure = -0.3,
		Saturation = -0.3,
		Ambient = Color3.fromRGB(18, 20, 34),
		Outdoor = Color3.fromRGB(14, 16, 30),
		Night = true,
	},
	Dawn = {
		ClockTime = 6.5,
		Brightness = 1.1,
		Exposure = 0.05,
		Saturation = -0.15,
		Ambient = Color3.fromRGB(64, 58, 72),
		Outdoor = Color3.fromRGB(125, 100, 92),
		Night = false,
	},
	Lobby = {
		ClockTime = 0,
		Brightness = 0.5,
		Exposure = -0.15,
		Saturation = -0.25,
		Ambient = Color3.fromRGB(24, 26, 40),
		Outdoor = Color3.fromRGB(20, 22, 38),
		Night = true,
	},
}

local function presetFor(phase: string): Preset
	if phase == "Day" then
		return PRESETS.Day
	elseif phase == "Alert" or phase == "Night" then
		return PRESETS.Night
	elseif phase == "Dawn" then
		return PRESETS.Dawn
	end
	return PRESETS.Lobby
end

local STINGER_COOLDOWN = 25
local TERROR_INTERVAL = 0.2
local TERROR_FAR, TERROR_MID, TERROR_NEAR = 60, 40, 20
local CHASE_NEAR = 25
local BLACKOUT_EXPOSURE = -0.6
local GRAIN_COUNT = 40
local GRAIN_INTERVAL = 0.045

local fxColor: ColorCorrectionEffect? = nil
local lastPhase = ""
local blackout = false
local fadedOut = false
local lastStinger = -math.huge
local flickerTokens: { [string]: number } = {}
local lastKnockAt = -math.huge
local lastKnockPos = Vector3.zero

local terrorTimer = 0
local loops: { [string]: Sound? } = {}
local loopTargets: { [string]: number } = {}

local vhsGui: ScreenGui? = nil
local grains: { Frame } = {}
local trackingLine: Frame? = nil
local grainTimer = 0
local trackingPhase = 0

----------------------------------------------------------------------
-- Освещение
----------------------------------------------------------------------

local function baseColorCorrection(): ColorCorrectionEffect?
	local cc = Lighting:FindFirstChild("BaseColorCorrection")
	if cc and cc:IsA("ColorCorrectionEffect") then
		return cc
	end
	return nil
end

local function getFxColor(): ColorCorrectionEffect
	local existing = fxColor
	if existing and existing.Parent then
		return existing
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "FXColor"
	cc.Brightness = 0
	cc.Contrast = 0
	cc.Saturation = 0
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Parent = Lighting
	fxColor = cc
	return cc
end

local function nightOwlLift(): number
	local perks = ClientState.Profile.Perks
	local level = if typeof(perks) == "table" then perks["NightOwl"] else nil
	if typeof(level) ~= "number" then
		return 0
	end
	return 0.1 * math.clamp(level, 0, 3)
end

local function exposureFor(preset: Preset): number
	local brightness = ClientState.Settings.Brightness
	if typeof(brightness) ~= "number" then
		brightness = 0.5
	end
	local lift = (brightness - 0.5) * (if preset.Night then 1.2 else 0.6)
	local exposure = preset.Exposure + lift
	if preset.Night then
		exposure += nightOwlLift()
	end
	if blackout then
		exposure += BLACKOUT_EXPOSURE
	end
	return exposure
end

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props)
	t:Play()
	return t
end

local function applyLighting(seconds: number, override: Preset?)
	local preset = override or presetFor(ClientState.Snapshot.Phase)
	tween(Lighting, seconds, {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		ExposureCompensation = exposureFor(preset),
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.Outdoor,
	})
	local cc = baseColorCorrection()
	if cc then
		tween(cc, seconds, { Saturation = preset.Saturation })
	end
end

-- Только экспозиция (смена яркости в настройках, обесточивание)
local function applyExposure(seconds: number)
	local preset = presetFor(ClientState.Snapshot.Phase)
	tween(Lighting, seconds, { ExposureCompensation = exposureFor(preset) })
end

----------------------------------------------------------------------
-- VHS-оверлей
----------------------------------------------------------------------

local function makeVignetteEdge(parent: Instance, name: string, position: UDim2, size: UDim2, rotation: number)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Position = position
	f.Size = size
	f.ZIndex = 1
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	f.Parent = parent
end

local function buildVhs(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "VhsOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -5
	gui.Enabled = ClientState.Settings.Vhs ~= false

	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.Parent = gui
	makeVignetteEdge(vignette, "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.26), 90)
	makeVignetteEdge(vignette, "Bottom", UDim2.fromScale(0, 0.74), UDim2.fromScale(1, 0.26), 270)
	makeVignetteEdge(vignette, "Left", UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0)
	makeVignetteEdge(vignette, "Right", UDim2.fromScale(0.82, 0), UDim2.fromScale(0.18, 1), 180)

	local grain = Instance.new("Frame")
	grain.Name = "Grain"
	grain.BackgroundTransparency = 1
	grain.BorderSizePixel = 0
	grain.Size = UDim2.fromScale(1, 1)
	grain.ZIndex = 2
	grain.Parent = gui
	table.clear(grains)
	for i = 1, GRAIN_COUNT do
		local speck = Instance.new("Frame")
		speck.Name = "G" .. tostring(i)
		local shade = 170 + math.random(0, 85)
		speck.BackgroundColor3 = Color3.fromRGB(shade, shade, shade)
		speck.BackgroundTransparency = 0.9 + math.random() * 0.06
		speck.BorderSizePixel = 0
		speck.Size = UDim2.fromOffset(2 + math.random(0, 2), 2 + math.random(0, 2))
		speck.Position = UDim2.fromScale(math.random(), math.random())
		speck.ZIndex = 2
		speck.Parent = grain
		table.insert(grains, speck)
	end

	local line = Instance.new("Frame")
	line.Name = "Tracking"
	line.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
	line.BackgroundTransparency = 0.94
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 2)
	line.Position = UDim2.fromScale(0, 0)
	line.ZIndex = 2
	line.Parent = grain
	trackingLine = line

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function updateVhs(dt: number)
	local gui = vhsGui
	if not gui or not gui.Enabled then
		return
	end
	grainTimer += dt
	if grainTimer < GRAIN_INTERVAL then
		return
	end
	grainTimer = 0
	for _, speck in grains do
		speck.Position = UDim2.fromScale(math.random(), math.random())
	end
	trackingPhase = (trackingPhase + GRAIN_INTERVAL / 7) % 1
	local line = trackingLine
	if line then
		line.Position = UDim2.fromScale(0, trackingPhase)
	end
end

----------------------------------------------------------------------
-- Радиус ужаса, музыка погони, босс
----------------------------------------------------------------------

local function setLoop(name: string, scale: number, seconds: number, playbackSpeed: number?)
	local target = Sounds.baseVolume(name) * math.clamp(scale, 0, 1)
	local s = loops[name]
	if target <= 0.001 then
		if s then
			loops[name] = nil
			loopTargets[name] = 0
			Sounds.fadeOut(s, seconds)
		end
		return
	end
	local sound = s or Sounds.loop(name, nil, 0)
	if not sound then
		return
	end
	loops[name] = sound
	if playbackSpeed and math.abs(sound.PlaybackSpeed - playbackSpeed) > 0.01 then
		sound.PlaybackSpeed = playbackSpeed
	end
	if math.abs((loopTargets[name] or -1) - target) > 0.005 then
		loopTargets[name] = target
		Sounds.fadeTo(sound, target, seconds)
	end
end

local function updateTerror()
	local status = ClientState.Status
	local cam = workspace.CurrentCamera
	local inmates = workspace:FindFirstChild("Inmates")
	local listening = (status == "Alive" or status == "Hiding" or status == "Downed") and ClientState.isNight()
	local nearest = math.huge
	local bossDist = math.huge
	local bossRange = 25
	local chase = false
	if listening and cam and inmates then
		local pos = cam.CFrame.Position
		local myId = player.UserId
		for _, model in inmates:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				continue
			end
			local d = (root.Position - pos).Magnitude
			local state = model:GetAttribute("State")
			if model:GetAttribute("Lethal") == true and state ~= "Retreat" and state ~= "Stunned" then
				nearest = math.min(nearest, d)
			end
			if state == "Chase" and (model:GetAttribute("TargetUserId") == myId or d < CHASE_NEAR) then
				chase = true
			end
			if model:GetAttribute("Kind") == "Boss" then
				bossDist = math.min(bossDist, d)
				local idAttr = model:GetAttribute("InmateId")
				local def = if typeof(idAttr) == "string" then Inmates.get(idAttr) else nil
				if def and def.ShakeRange > 0 then
					bossRange = def.ShakeRange
				end
			end
		end
	end

	-- зоны: 60 — дрон, 40 — сердце, 20 — сердце + дыхание
	local drone = if nearest < TERROR_FAR then math.clamp((TERROR_FAR - nearest) / 30, 0.15, 1) else 0
	local heart = if nearest < TERROR_MID then math.clamp((TERROR_MID - nearest) / 20, 0.2, 1) else 0
	local breath = if nearest < TERROR_NEAR then math.clamp((TERROR_NEAR - nearest) / 10, 0.2, 1) else 0
	local heartSpeed = if nearest < TERROR_MID then 1 + (1 - nearest / TERROR_MID) * 0.45 else 1
	setLoop("Drone", drone, 0.4)
	setLoop("Heartbeat", heart, 0.3, heartSpeed)
	setLoop("Breathing", breath, 0.3)

	if chase then
		setLoop("ChaseMusic", 1, 1)
	else
		setLoop("ChaseMusic", 0, 2.5)
	end

	if bossDist < bossRange then
		Camera.setSustainedShake((1 - bossDist / bossRange) * 0.7)
	else
		Camera.setSustainedShake(0)
	end
end

----------------------------------------------------------------------
-- Разовые эффекты
----------------------------------------------------------------------

local function flash(brightness: number, seconds: number, tint: Color3?)
	local cc = getFxColor()
	cc.Brightness = brightness
	if tint then
		cc.TintColor = tint
	end
	tween(cc, seconds, { Brightness = if fadedOut then -1 else 0, TintColor = Color3.new(1, 1, 1) }, Enum.EasingStyle.Quad)
end

local function stinger(params: { [string]: any }?)
	local now = os.clock()
	if now - lastStinger < STINGER_COOLDOWN then
		return
	end
	lastStinger = now
	local idAttr = if params then params.InmateId else nil
	local def = if typeof(idAttr) == "string" then Inmates.get(idAttr) else nil
	Sounds.playUI(if def and def.Kind == "Boss" then "StingerOrch" else "Stinger")
	flash(0.45, 0.25, Color3.new(1, 1, 1))
	Camera.shake(0.6, 0.45)
end

local function flickerRoom(room: string, duration: number)
	local house = workspace:FindFirstChild("House")
	local lights = if house then house:FindFirstChild("Lights") else nil
	local model = if lights then lights:FindFirstChild(room) else nil
	if not model then
		return
	end
	local bulb = model:FindFirstChild("Bulb")
	if not bulb or not bulb:IsA("BasePart") then
		return
	end
	local light = bulb:FindFirstChildWhichIsA("PointLight")
	local token = (flickerTokens[room] or 0) + 1
	flickerTokens[room] = token
	Sounds.playAt("Arc", bulb.Position, 0.35)
	local function setBulb(on: boolean)
		bulb.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local l = light
		if l then
			l.Enabled = on
		end
	end
	task.spawn(function()
		local steps = 6
		local slot = math.max(0.05, duration) / (steps * 2)
		for _ = 1, steps do
			if flickerTokens[room] ~= token or bulb.Parent == nil then
				return
			end
			setBulb(false)
			task.wait(slot * (0.5 + math.random()))
			if flickerTokens[room] ~= token or bulb.Parent == nil then
				return
			end
			setBulb(true)
			task.wait(slot)
		end
		if flickerTokens[room] ~= token or bulb.Parent == nil then
			return
		end
		-- возвращаем состояние, которое держит сервер
		setBulb(model:GetAttribute("On") ~= false)
	end)
end

local function dawn()
	applyLighting(6, PRESETS.Dawn)
	local cc = getFxColor()
	local warm = tween(cc, 3, { TintColor = Color3.fromRGB(255, 236, 214) })
	warm.Completed:Once(function()
		tween(cc, 3, { TintColor = Color3.new(1, 1, 1) })
	end)
	Sounds.playUI("SunriseSting")
end

local function caught()
	fadedOut = true
	local cc = getFxColor()
	tween(cc, 1.5, { Brightness = -1, Saturation = -0.6 }, Enum.EasingStyle.Quad)
	Camera.shake(1.2, 0.8)
	Sounds.playUI("FearHit")
end

local function fadeBack(seconds: number)
	if not fadedOut then
		return
	end
	fadedOut = false
	local cc = getFxColor()
	tween(cc, seconds, { Brightness = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }, Enum.EasingStyle.Quad)
end

local function revived()
	if fadedOut then
		fadeBack(0.6)
	else
		flash(0.25, 0.5)
	end
	Sounds.playUI("Success", 0.6)
end

local function knockAt(position: Vector3, name: string)
	-- Knock приходит и как InmateEvent, и как FX — не дублируем
	local now = os.clock()
	if now - lastKnockAt < 0.3 and (position - lastKnockPos).Magnitude < 4 then
		return
	end
	lastKnockAt = now
	lastKnockPos = position
	Sounds.playAt(name, position)
end

local function onFX(kind: string, params: { [string]: any }?)
	local p = params or {}
	if kind == "Stinger" then
		stinger(p)
	elseif kind == "Shake" then
		local mag = if typeof(p.Magnitude) == "number" then p.Magnitude else 1
		local dur = if typeof(p.Duration) == "number" then p.Duration else 0.5
		Camera.shake(mag, dur)
	elseif kind == "Flicker" then
		local room = if typeof(p.Room) == "string" then p.Room else nil
		local dur = if typeof(p.Duration) == "number" then p.Duration else 1.2
		if room then
			flickerRoom(room, dur)
		end
	elseif kind == "Blackout" then
		blackout = p.On == true
		applyExposure(0.5)
		Sounds.playUI(if blackout then "BassDrop" else "Switch", 0.7)
	elseif kind == "Dawn" then
		dawn()
	elseif kind == "Caught" then
		caught()
	elseif kind == "Revived" then
		revived()
	elseif kind == "NightStart" then
		Sounds.playUI("Riser")
	elseif kind == "DayStart" then
		Sounds.playUI("Paper", 0.4)
	elseif kind == "Knock" then
		if typeof(p.Position) == "Vector3" then
			knockAt(p.Position, "Knock")
		end
	elseif kind == "Click" then
		if typeof(p.Position) == "Vector3" then
			Sounds.playAt("Click", p.Position)
		end
	end
end

-- Звуки событий пациентов (телеграфы)
local function onInmateEvent(kind: string, inmateId: string, position: Vector3)
	if typeof(position) ~= "Vector3" then
		return
	end
	local def = Inmates.get(inmateId)
	if kind == "Knock" then
		knockAt(position, "Knock")
	elseif kind == "Chase" then
		if def and def.Kind == "Blind" then
			Sounds.playAt("Whistle", position, 1.2)
		elseif def and def.Kind == "Boss" then
			Sounds.playAt("Growl", position, 1.2)
		elseif def and def.Kind ~= "StillOne" and def.Kind ~= "Sentinel" then
			Sounds.playAt("Growl", position)
		end
	elseif kind == "Stun" then
		Sounds.playAt("StunZap", position, 0.8)
		Sounds.playAt("Snarl", position)
	elseif kind == "Enter" then
		Sounds.playAt("DoorSlam", position)
	elseif kind == "Look" then
		Sounds.playAt("Click", position)
	elseif kind == "Caught" then
		Sounds.playAt("ScreamShort", position)
	elseif kind == "Retreat" then
		Sounds.playAt("DoorClose", position, 0.7)
	end
end

local function onLightsChanged(room: string, _on: boolean)
	local house = workspace:FindFirstChild("House")
	local lights = if house then house:FindFirstChild("Lights") else nil
	local model = if lights then lights:FindFirstChild(room) else nil
	local switch = if model then model:FindFirstChild("Switch") else nil
	if switch and switch:IsA("BasePart") then
		Sounds.playAt("Switch", switch.Position)
	else
		Sounds.playUI("Switch", 0.5)
	end
	-- серверное состояние важнее местного мигания
	flickerTokens[room] = (flickerTokens[room] or 0) + 1
end

----------------------------------------------------------------------

function FX.init()
	getFxColor()
	vhsGui = buildVhs()
	applyLighting(0.1)

	lastPhase = ClientState.Snapshot.Phase
	ClientState.StateChanged:Connect(function(snapshot: ClientState.StateSnapshot)
		-- снимки приходят часто (таймер), освещение меняем только при смене фазы
		if snapshot.Phase ~= lastPhase then
			lastPhase = snapshot.Phase
			applyLighting(if snapshot.Phase == "Dawn" then 6 else 2)
		end
	end)
	ClientState.SettingsChanged:Connect(function(settings: { [string]: any })
		local gui = vhsGui
		if gui then
			gui.Enabled = settings.Vhs ~= false
		end
		applyExposure(0.3)
	end)
	ClientState.ProfileChanged:Connect(function()
		applyExposure(0.3)
	end)
	ClientState.StatusChanged:Connect(function(status: string)
		if status ~= "Downed" then
			fadeBack(1)
		end
		if status == "Taken" or status == "Spectating" then
			Camera.setSustainedShake(0)
		end
	end)
	ClientState.FXEvent:Connect(onFX)
	ClientState.InmateEvent:Connect(onInmateEvent)
	ClientState.LightsChanged:Connect(onLightsChanged)

	RunService.Heartbeat:Connect(function(dt: number)
		updateVhs(dt)
		terrorTimer += dt
		if terrorTimer >= TERROR_INTERVAL then
			terrorTimer = 0
			updateTerror()
		end
	end)
end

return FX
