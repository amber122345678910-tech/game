-- Lighting + ambience for every story location.
local Graphics = require(script.Parent.Graphics)
local Audio = require(script.Parent.Audio)

local Scenes = {}
local rgb = Color3.fromRGB

Scenes.Presets = {
	-- 7 AM in the Smith house
	Morning = {
		Lighting = {
			ClockTime = 7.3,
			Brightness = 2.6,
			Ambient = rgb(78, 68, 62),
			OutdoorAmbient = rgb(150, 132, 122),
			ColorShift_Top = rgb(255, 214, 170),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.15,
			ShadowSoftness = 0.15,
		},
		Atmosphere = { Density = 0.3, Color = rgb(255, 214, 180), Decay = rgb(200, 150, 120), Glare = 0.4, Haze = 1.2 },
		Grade = { Saturation = 0.1, Contrast = 0.08, Brightness = 0, TintColor = rgb(255, 244, 232) },
		Bloom = { Intensity = 0.7, Size = 26, Threshold = 1.15 },
		SunRays = { Intensity = 0.05, Spread = 0.6 },
		Lights = {
			MoonBeam = false,
			SunBeam = { Brightness = 4.5, Color = rgb(255, 176, 110) },
			KitchenSun = true,
			KitchenLight = true,
			HallLight = true,
			DeskLamp = false,
			NightLamp = false,
			CeilingLight = false,
			StreetLamp = false,
			PorchLight = false,
			PortalLight = false,
		},
		NightWindows = false,
		Portal = false,
		Dust = true,
		Ambience = "Birds",
	},
	Garage = {
		Lighting = {
			ClockTime = 9,
			Brightness = 2,
			Ambient = rgb(56, 62, 64),
			OutdoorAmbient = rgb(130, 136, 140),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.7,
			ExposureCompensation = 0.1,
			ShadowSoftness = 0.2,
		},
		Atmosphere = { Density = 0.28, Color = rgb(200, 220, 240), Decay = rgb(140, 160, 180), Glare = 0, Haze = 0.8 },
		Grade = { Saturation = 0.05, Contrast = 0.14, Brightness = 0, TintColor = rgb(236, 255, 242) },
		Bloom = { Intensity = 0.9, Size = 28, Threshold = 1.0 },
		Lights = { GarageLight = true, VatGlow = true, SurgeryLight = true, StreetLamp = false, PorchLight = false },
		NightWindows = false,
		Ambience = "LabHum",
	},
	Sky = {
		Lighting = {
			ClockTime = 9.5,
			Brightness = 3,
			Ambient = rgb(90, 90, 100),
			OutdoorAmbient = rgb(150, 150, 160),
			ColorShift_Top = rgb(255, 240, 220),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.7,
			ExposureCompensation = 0,
			ShadowSoftness = 0.2,
		},
		Atmosphere = { Density = 0.3, Color = rgb(190, 215, 255), Decay = rgb(120, 150, 210), Glare = 0.3, Haze = 1 },
		Grade = { Saturation = 0.1, Contrast = 0.08, Brightness = 0, TintColor = rgb(255, 255, 255) },
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.3 },
		SunRays = { Intensity = 0.08, Spread = 0.5 },
		Ambience = "Wind",
	},
	Space = {
		Lighting = {
			ClockTime = 0,
			Brightness = 3.5,
			Ambient = rgb(26, 26, 36),
			OutdoorAmbient = rgb(36, 36, 52),
			ColorShift_Top = rgb(255, 245, 230),
			EnvironmentDiffuseScale = 0.2,
			EnvironmentSpecularScale = 0.8,
			ExposureCompensation = 0.2,
			ShadowSoftness = 0.05,
		},
		Atmosphere = { Density = 0, Color = rgb(0, 0, 0), Decay = rgb(0, 0, 0), Glare = 0, Haze = 0 },
		Grade = { Saturation = 0.1, Contrast = 0.18, Brightness = 0, TintColor = rgb(235, 240, 255) },
		Bloom = { Intensity = 1.2, Size = 40, Threshold = 0.9 },
		Ambience = nil,
		ShowSpace = true,
	},
	Desert = {
		Lighting = {
			ClockTime = 16.2,
			Brightness = 3.2,
			Ambient = rgb(124, 84, 62),
			OutdoorAmbient = rgb(204, 146, 106),
			ColorShift_Top = rgb(255, 192, 132),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.5,
			ExposureCompensation = 0.05,
			ShadowSoftness = 0.1,
		},
		Atmosphere = { Density = 0.42, Offset = 0.25, Color = rgb(255, 150, 80), Decay = rgb(190, 90, 50), Glare = 1.4, Haze = 2.6 },
		Grade = { Saturation = 0.15, Contrast = 0.1, Brightness = 0, TintColor = rgb(255, 232, 210) },
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.2 },
		SunRays = { Intensity = 0.12, Spread = 0.5 },
		Ambience = "Wind",
	},
	DesertDark = {
		Lighting = {
			ClockTime = 16.8,
			Brightness = 1.6,
			Ambient = rgb(70, 40, 34),
			OutdoorAmbient = rgb(130, 76, 60),
			ColorShift_Top = rgb(255, 120, 80),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.5,
			ExposureCompensation = 0,
			ShadowSoftness = 0.2,
		},
		Atmosphere = { Density = 0.55, Offset = 0.2, Color = rgb(150, 70, 50), Decay = rgb(60, 20, 20), Glare = 0.5, Haze = 3 },
		Grade = { Saturation = -0.1, Contrast = 0.28, Brightness = 0, TintColor = rgb(255, 214, 196) },
		Bloom = { Intensity = 1, Size = 32, Threshold = 1.0 },
		SunRays = { Intensity = 0.05, Spread = 0.4 },
		Ambience = "Rumble",
	},
	Bunker = {
		Lighting = {
			ClockTime = 0,
			Brightness = 0.4,
			Ambient = rgb(44, 40, 38),
			OutdoorAmbient = rgb(30, 30, 30),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.3,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.25,
			ShadowSoftness = 0.15,
		},
		Atmosphere = { Density = 0.25, Color = rgb(60, 56, 54), Decay = rgb(30, 30, 30), Glare = 0, Haze = 0.5 },
		Grade = { Saturation = -0.08, Contrast = 0.18, Brightness = 0, TintColor = rgb(255, 236, 220) },
		Bloom = { Intensity = 0.9, Size = 24, Threshold = 1.05 },
		Lights = { BunkerLamp = true },
		Ambience = "Rumble",
	},
}

local ambience: Sound? = nil
local ambienceKey: string? = nil
local current: string? = nil

function Scenes.setAmbience(key: string?)
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

local function setSpaceVisible(on: boolean)
	local space = workspace:FindFirstChild("Space")
	if space then
		for _, d in space:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if on then 0 else 1
			end
		end
	end
end
setSpaceVisible(false)
Scenes.setSpaceVisible = setSpaceVisible

function Scenes.apply(name: string, instant: boolean?)
	local p = Scenes.Presets[name]
	if not p then
		warn("Unknown scene", name)
		return
	end
	current = name
	Graphics.ApplyTable(p, instant, true)
	setSpaceVisible(p.ShowSpace == true)
	Scenes.setAmbience(p.Ambience)
end

function Scenes.current(): string?
	return current
end

return Scenes
