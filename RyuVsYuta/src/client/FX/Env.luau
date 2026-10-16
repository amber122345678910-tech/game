--!strict
-- Свет, атмосфера (туман), цветокоррекция, свечение, глубина резкости — из состояния кадра.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Cutscene"):WaitForChild("Sequence"):WaitForChild("Types"))
local Layout = require(ReplicatedStorage:WaitForChild("Cutscene"):WaitForChild("Sequence"):WaitForChild("Layout"))

local Env = {}

local atmosphere: Atmosphere
local cc: ColorCorrectionEffect
local bloom: BloomEffect
local dof: DepthOfFieldEffect
local sunRays: SunRaysEffect
local blur: BlurEffect

local function ensure(className: string, name: string): any
	local inst = Lighting:FindFirstChild(name)
	if inst and inst.ClassName == className then
		return inst
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

-- Солнце: ClockTime/широта в месте подобраны по формуле; здесь проверяем настоящим GetSunDirection()
-- и, если направление не совпало (формула неофициальная), подбираем ClockTime/широту перебором.
local function solveSun(want: Vector3)
	local ok = pcall(function()
		local cur = Lighting:GetSunDirection()
		if cur:Dot(want) > 0.97 then
			return
		end
		local bestT, bestLat, bestDot = Lighting.ClockTime, Lighting.GeographicLatitude, cur:Dot(want)
		for lat = -60, 80, 5 do
			Lighting.GeographicLatitude = lat
			for i = 0, 72 do
				local clock = 6 + i * (12 / 72)
				Lighting.ClockTime = clock
				local d = Lighting:GetSunDirection():Dot(want)
				if d > bestDot then
					bestT, bestLat, bestDot = clock, lat, d
				end
			end
		end
		Lighting.ClockTime = bestT
		Lighting.GeographicLatitude = bestLat
	end)
	if not ok then
		warn("[Cutscene] sun solve skipped")
	end
end

-- Объёмные облака Roblox (видны в кадрах с Рю, где камера смотрит в небо)
local function ensureClouds()
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		local cl = Instance.new("Clouds")
		cl.Parent = terrain
		clouds = cl
	end
	if clouds then
		clouds.Cover = 0.62
		clouds.Density = 0.72
		clouds.Color = Color3.fromRGB(236, 240, 252)
	end
end

function Env.init()
	solveSun(Layout.sunDirection)
	ensureClouds()
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	atmosphere = if existing then existing else ensure("Atmosphere", "Atmosphere")
	cc = ensure("ColorCorrectionEffect", "CutsceneColor")
	bloom = ensure("BloomEffect", "CutsceneBloom")
	dof = ensure("DepthOfFieldEffect", "CutsceneDepthOfField")
	sunRays = ensure("SunRaysEffect", "CutsceneSunRays")
	blur = ensure("BlurEffect", "CutsceneBlur")
end

function Env.apply(frame: Types.Frame)
	local e = frame.env
	atmosphere.Density = e.fogDensity
	atmosphere.Offset = e.fogOffset
	atmosphere.Haze = e.fogHaze
	atmosphere.Glare = e.fogGlare
	atmosphere.Color = e.fogColor
	atmosphere.Decay = e.fogDecay

	Lighting.ExposureCompensation = e.exposure
	Lighting.Brightness = e.brightness
	Lighting.Ambient = e.ambient
	Lighting.OutdoorAmbient = e.outdoorAmbient

	cc.TintColor = e.tint
	cc.Saturation = e.saturation
	cc.Contrast = e.contrast
	cc.Brightness = e.ccBrightness

	bloom.Intensity = e.bloomIntensity
	bloom.Size = e.bloomSize
	bloom.Threshold = e.bloomThreshold

	sunRays.Intensity = e.sunRays
	sunRays.Spread = 0.6
	sunRays.Enabled = e.sunRays > 0.001

	blur.Size = e.blur
	blur.Enabled = e.blur > 0.05

	local c = frame.camera
	dof.FocusDistance = c.focusDist
	dof.InFocusRadius = c.inFocus
	dof.FarIntensity = c.farBlur
	dof.NearIntensity = c.nearBlur
	dof.Enabled = c.farBlur > 0.001 or c.nearBlur > 0.001

	Workspace.GlobalWind = e.wind
end

return Env
