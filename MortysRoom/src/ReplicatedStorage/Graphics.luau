-- Graphics presets: lighting, colour grading, lamps, outlines.
-- Everything here runs on the client, so each player sees their own choice.
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Graphics = {}

local rgb = Color3.fromRGB

--[[
	Lights you can switch per preset (names of Light objects inside MortysHouse):
	MoonBeam, SunBeam, DeskLamp, NightLamp, CeilingLight, StreetLamp, PortalLight, MonitorGlow, ClockGlow
	true / false = on / off, or a table of properties to override.
]]
Graphics.Presets = {
	Moonlight = {
		Description = "Night. Cold moonlight through the window, warm desk lamp.",
		Lighting = {
			ClockTime = 0.4,
			Brightness = 1.6,
			Ambient = rgb(24, 27, 40),
			OutdoorAmbient = rgb(60, 70, 100),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.35,
			EnvironmentSpecularScale = 0.5,
			ExposureCompensation = 0.15,
			ShadowSoftness = 0.25,
		},
		Atmosphere = { Density = 0.3, Color = rgb(100, 120, 170), Decay = rgb(40, 50, 80), Glare = 0, Haze = 1 },
		Grade = { Saturation = -0.05, Contrast = 0.1, Brightness = 0, TintColor = rgb(225, 232, 255) },
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.3 },
		SunRays = nil,
		Lights = {
			MoonBeam = { Brightness = 3, Color = rgb(140, 165, 255) },
			SunBeam = false,
			DeskLamp = true,
			NightLamp = false,
			CeilingLight = false,
			StreetLamp = true,
			PortalLight = false,
			MonitorGlow = { Color = rgb(120, 170, 255) },
			ClockGlow = true,
		},
		NightWindows = true,
		Portal = false,
		Outlines = false,
		Dust = true,
		Clock = "3:14",
		Ambience = "Crickets",
	},
	Sunrise = {
		Description = "Early morning. Low orange sun on the wall, floating dust.",
		Lighting = {
			ClockTime = 6.5,
			Brightness = 2.4,
			Ambient = rgb(70, 56, 52),
			OutdoorAmbient = rgb(150, 122, 110),
			ColorShift_Top = rgb(255, 196, 150),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.1,
			ShadowSoftness = 0.15,
		},
		Atmosphere = { Density = 0.35, Color = rgb(255, 190, 150), Decay = rgb(180, 110, 90), Glare = 0.6, Haze = 1.6 },
		Grade = { Saturation = 0.12, Contrast = 0.06, Brightness = 0, TintColor = rgb(255, 240, 226) },
		Bloom = { Intensity = 0.8, Size = 30, Threshold = 1.1 },
		SunRays = { Intensity = 0.06, Spread = 0.7 },
		Lights = {
			MoonBeam = false,
			SunBeam = { Brightness = 5.5, Color = rgb(255, 168, 96) },
			DeskLamp = false,
			NightLamp = false,
			CeilingLight = false,
			StreetLamp = false,
			PortalLight = false,
			MonitorGlow = { Color = rgb(120, 170, 255), Brightness = 0.4 },
			ClockGlow = true,
		},
		NightWindows = false,
		Portal = false,
		Outlines = false,
		Dust = true,
		Clock = "6:58",
		Ambience = "Birds",
	},
	Cartoon = {
		Description = "Bright, flat colours and black outlines, like the show.",
		Lighting = {
			ClockTime = 10,
			Brightness = 2.2,
			Ambient = rgb(150, 150, 162),
			OutdoorAmbient = rgb(170, 170, 182),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0,
			ExposureCompensation = 0,
			ShadowSoftness = 0.6,
		},
		Atmosphere = { Density = 0.2, Color = rgb(190, 220, 255), Decay = rgb(150, 180, 220), Glare = 0, Haze = 0 },
		Grade = { Saturation = 0.35, Contrast = 0.12, Brightness = 0.02, TintColor = rgb(255, 255, 255) },
		Bloom = { Intensity = 0.25, Size = 20, Threshold = 1.6 },
		SunRays = nil,
		Lights = {
			MoonBeam = false,
			SunBeam = false,
			DeskLamp = true,
			NightLamp = false,
			CeilingLight = { Brightness = 1.2 },
			StreetLamp = false,
			PortalLight = false,
			MonitorGlow = { Color = rgb(120, 255, 150), Brightness = 0.5 },
			ClockGlow = true,
		},
		NightWindows = false,
		Portal = false,
		Outlines = true,
		Dust = false,
		Clock = "8:15",
		Ambience = "Birds",
	},
	Portal = {
		Description = "Night. Rick opened a portal in the yard. Green glow everywhere.",
		Lighting = {
			ClockTime = 0.2,
			Brightness = 1,
			Ambient = rgb(18, 34, 24),
			OutdoorAmbient = rgb(40, 80, 50),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.35,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.2,
			ShadowSoftness = 0.2,
		},
		Atmosphere = { Density = 0.35, Color = rgb(90, 160, 100), Decay = rgb(30, 70, 40), Glare = 0, Haze = 1.2 },
		Grade = { Saturation = 0.15, Contrast = 0.14, Brightness = 0, TintColor = rgb(222, 255, 226) },
		Bloom = { Intensity = 1.2, Size = 40, Threshold = 0.95 },
		SunRays = nil,
		Lights = {
			MoonBeam = false,
			SunBeam = false,
			DeskLamp = false,
			NightLamp = false,
			CeilingLight = false,
			StreetLamp = false,
			PortalLight = true,
			MonitorGlow = { Color = rgb(120, 255, 140) },
			ClockGlow = true,
		},
		NightWindows = true,
		Portal = true,
		Outlines = false,
		Dust = true,
		Clock = "3:14",
		Ambience = "PortalHum",
	},
	Noir = {
		Description = "Black and white, hard moonlight shadows. Spooky.",
		Lighting = {
			ClockTime = 0.5,
			Brightness = 2,
			Ambient = rgb(14, 14, 14),
			OutdoorAmbient = rgb(60, 60, 60),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.25,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.3,
			ShadowSoftness = 0.05,
		},
		Atmosphere = { Density = 0.32, Color = rgb(150, 150, 150), Decay = rgb(60, 60, 60), Glare = 0, Haze = 1.4 },
		Grade = { Saturation = -1, Contrast = 0.38, Brightness = 0.02, TintColor = rgb(255, 255, 255) },
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.2 },
		SunRays = nil,
		Lights = {
			MoonBeam = { Brightness = 4.5, Color = rgb(235, 240, 255), Angle = 38 },
			SunBeam = false,
			DeskLamp = false,
			NightLamp = false,
			CeilingLight = false,
			StreetLamp = true,
			PortalLight = false,
			MonitorGlow = { Color = rgb(200, 210, 255) },
			ClockGlow = true,
		},
		NightWindows = true,
		Portal = false,
		Outlines = false,
		Dust = true,
		Clock = "3:14",
		Ambience = "Crickets",
	},
}

local house: Model? = nil
local lights: { [string]: { Light } } = {}
local bulbs: { [string]: { BasePart } } = {}
local nightWindows: { BasePart } = {}
local portalParts: { BasePart } = {}
local outlineModels: { Model } = {}
local highlights: { Highlight } = {}
local lightOn: { [string]: boolean } = {}
local portalConn: RBXScriptConnection? = nil
local current: string? = nil
local brightnessOffset = 0

local function scan()
	if house then
		return
	end
	house = workspace:WaitForChild("MortysHouse") :: Model
	for _, d in (house :: Model):GetDescendants() do
		if d:IsA("Light") then
			lights[d.Name] = lights[d.Name] or {}
			table.insert(lights[d.Name], d)
			d:SetAttribute("BaseBrightness", d.Brightness)
			d:SetAttribute("BaseColor", d.Color)
			if d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				d:SetAttribute("BaseAngle", (d :: any).Angle)
			end
		elseif d:IsA("BasePart") then
			local bulbFor = d:GetAttribute("BulbFor")
			if bulbFor then
				bulbs[bulbFor] = bulbs[bulbFor] or {}
				table.insert(bulbs[bulbFor], d)
				d:SetAttribute("OffMaterial", if d.Material == Enum.Material.Neon then "SmoothPlastic" else d.Material.Name)
			end
			if d:GetAttribute("NightWindow") ~= nil then
				d:SetAttribute("LitColor", d.Color)
				table.insert(nightWindows, d)
			end
			if d:GetAttribute("PortalFX") then
				table.insert(portalParts, d)
			end
		elseif d:IsA("Model") and d:GetAttribute("Outline") then
			table.insert(outlineModels, d)
		end
	end
end

-- Turn a named lamp on/off (also lights up its bulb).
function Graphics.SetLight(name: string, on: boolean, props: { [string]: any }?)
	scan()
	lightOn[name] = on
	for _, l in lights[name] or {} do
		l.Enabled = on
		l.Brightness = if props and props.Brightness then props.Brightness else l:GetAttribute("BaseBrightness")
		l.Color = if props and props.Color then props.Color else l:GetAttribute("BaseColor")
		if props and props.Angle and (l:IsA("SpotLight") or l:IsA("SurfaceLight")) then
			(l :: any).Angle = props.Angle
		elseif l:GetAttribute("BaseAngle") then
			(l :: any).Angle = l:GetAttribute("BaseAngle")
		end
	end
	for _, b in bulbs[name] or {} do
		if on then
			b.Material = Enum.Material.Neon
		else
			b.Material = (Enum.Material :: any)[b:GetAttribute("OffMaterial") or "SmoothPlastic"]
		end
	end
end

function Graphics.IsLightOn(name: string): boolean
	return lightOn[name] == true
end

local function tweenProps(inst: Instance?, props: { [string]: any }?, t: number)
	if inst and props then
		TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Sine), props):Play()
	end
end

local function setOutlines(on: boolean)
	for _, h in highlights do
		h:Destroy()
	end
	table.clear(highlights)
	if not on then
		return
	end
	for i, m in outlineModels do
		if i > 30 then
			break
		end
		local h = Instance.new("Highlight")
		h.Name = "CartoonOutline"
		h.FillTransparency = 1
		h.OutlineTransparency = 0
		h.OutlineColor = rgb(24, 20, 28)
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = m
		h.Parent = m
		table.insert(highlights, h)
	end
end

local function setPortal(on: boolean)
	if portalConn then
		portalConn:Disconnect()
		portalConn = nil
	end
	for _, p in portalParts do
		p.Transparency = if on then 0 else 1
		for _, d in p:GetChildren() do
			if d:IsA("ParticleEmitter") then
				d.Enabled = on
			end
		end
	end
	if on then
		local t0 = os.clock()
		portalConn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			for _, l in lights.PortalLight or {} do
				l.Brightness = 5 + math.noise(t * 2.3, 0.3) * 3 + math.sin(t * 9) * 0.4
			end
			for i, p in portalParts do
				p.CFrame = p.CFrame * CFrame.Angles(0.01 * (if i % 2 == 0 then 1 else -1), 0, 0)
			end
		end)
	end
end

local function setNightWindows(night: boolean)
	for _, w in nightWindows do
		local lit = w:GetAttribute("NightWindow") == true
		if night and lit then
			w.Material = Enum.Material.Neon
			w.Color = w:GetAttribute("LitColor") or w.Color
		else
			w.Material = Enum.Material.Glass
			w.Color = rgb(52, 60, 76)
		end
	end
end

local function setDust(on: boolean)
	local dustPart = house and (house :: Model):FindFirstChild("DustVolume", true)
	local emitter = dustPart and dustPart:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Enabled = on
	end
end

local function setClock(text: string)
	local clock = house and (house :: Model):FindFirstChild("AlarmClock")
	local label = clock and clock:FindFirstChild("ClockText", true)
	if label then
		(label :: TextLabel).Text = text
	end
end

function Graphics.Get(name: string)
	return Graphics.Presets[name]
end

function Graphics.Current(): string?
	return current
end

function Graphics.SetBrightnessOffset(v: number)
	brightnessOffset = v
	if current then
		local p = Graphics.Presets[current]
		Lighting.ExposureCompensation = p.Lighting.ExposureCompensation + brightnessOffset
	end
end

-- Apply a preset. `instant` skips the fade.
function Graphics.Apply(name: string, instant: boolean?, keepClock: boolean?)
	scan()
	local p = Graphics.Presets[name]
	if not p then
		warn("Unknown graphics preset", name)
		return
	end
	current = name
	local t = if instant then 0 else 0.8

	local lightingProps = table.clone(p.Lighting)
	lightingProps.ExposureCompensation = p.Lighting.ExposureCompensation + brightnessOffset
	local clockTime = lightingProps.ClockTime
	lightingProps.ClockTime = nil
	Lighting.ClockTime = clockTime
	local shadowSoftness = lightingProps.ShadowSoftness
	lightingProps.ShadowSoftness = nil
	pcall(function()
		Lighting.ShadowSoftness = shadowSoftness
	end)
	tweenProps(Lighting, lightingProps, t)
	tweenProps(Lighting:FindFirstChildOfClass("Atmosphere"), p.Atmosphere, t)
	tweenProps(Lighting:FindFirstChild("Grade"), p.Grade, t)
	tweenProps(Lighting:FindFirstChild("Bloom"), p.Bloom, t)
	local rays = Lighting:FindFirstChild("SunRays") :: SunRaysEffect?
	if rays then
		rays.Enabled = p.SunRays ~= nil
		if p.SunRays then
			tweenProps(rays, p.SunRays, t)
		end
	end

	for lightName, setting in p.Lights do
		if setting == false then
			Graphics.SetLight(lightName, false)
		elseif setting == true then
			Graphics.SetLight(lightName, true)
		else
			Graphics.SetLight(lightName, true, setting)
		end
	end

	setNightWindows(p.NightWindows)
	setPortal(p.Portal)
	setOutlines(p.Outlines)
	setDust(p.Dust)
	if not keepClock then
		setClock(p.Clock)
	end
end

-- Extra outline target (e.g. the player's own character in the menu)
function Graphics.OutlinesOn(): boolean
	return current ~= nil and Graphics.Presets[current].Outlines == true
end

return Graphics
