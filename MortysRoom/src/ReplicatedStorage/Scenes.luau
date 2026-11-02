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
	-- the Silent dimension: white void, no sound at all
	Silent = {
		Lighting = {
			ClockTime = 12,
			Brightness = 2.2,
			Ambient = rgb(150, 154, 166),
			OutdoorAmbient = rgb(200, 204, 214),
			ColorShift_Top = rgb(230, 236, 255),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.3,
			ShadowSoftness = 0.6,
		},
		Atmosphere = { Density = 0.5, Offset = 0, Color = rgb(236, 240, 250), Decay = rgb(200, 206, 222), Glare = 0, Haze = 3 },
		Grade = { Saturation = -0.55, Contrast = 0.05, Brightness = 0.02, TintColor = rgb(236, 242, 255) },
		Bloom = { Intensity = 0.4, Size = 30, Threshold = 1.4 },
		SunRays = { Intensity = 0, Spread = 0.5 },
		Ambience = nil,
	},
	SilentCrack = {
		Lighting = {
			ClockTime = 12,
			Brightness = 1.4,
			Ambient = rgb(110, 116, 140),
			OutdoorAmbient = rgb(150, 160, 190),
			ColorShift_Top = rgb(200, 230, 255),
			EnvironmentDiffuseScale = 0.8,
			EnvironmentSpecularScale = 0.8,
			ExposureCompensation = 0.1,
			ShadowSoftness = 0.4,
		},
		Atmosphere = { Density = 0.45, Offset = 0, Color = rgb(190, 205, 235), Decay = rgb(90, 100, 140), Glare = 0, Haze = 2.4 },
		Grade = { Saturation = -0.35, Contrast = 0.2, Brightness = 0, TintColor = rgb(220, 232, 255) },
		Bloom = { Intensity = 1, Size = 34, Threshold = 0.95 },
		SunRays = { Intensity = 0, Spread = 0.5 },
		Ambience = "Drone",
	},
	-- J-22: a sunny suburb (upside down)
	Upside = {
		Lighting = {
			ClockTime = 14,
			Brightness = 3,
			Ambient = rgb(100, 100, 110),
			OutdoorAmbient = rgb(150, 150, 165),
			ColorShift_Top = rgb(255, 245, 225),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0,
			ShadowSoftness = 0.2,
		},
		Atmosphere = { Density = 0.4, Offset = 0.1, Color = rgb(200, 215, 255), Decay = rgb(130, 150, 200), Glare = 0.3, Haze = 2 },
		Grade = { Saturation = 0.1, Contrast = 0.08, Brightness = 0, TintColor = rgb(250, 250, 255) },
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.3 },
		SunRays = { Intensity = 0.06, Spread = 0.5 },
		Ambience = "Birds",
	},
	-- D-716: bright cube noon
	Cube = {
		Lighting = {
			ClockTime = 12.5,
			Brightness = 3.4,
			Ambient = rgb(110, 116, 110),
			OutdoorAmbient = rgb(170, 180, 170),
			ColorShift_Top = rgb(255, 250, 230),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.4,
			ExposureCompensation = 0,
			ShadowSoftness = 0,
		},
		Atmosphere = { Density = 0.42, Offset = 0.1, Color = rgb(190, 225, 255), Decay = rgb(120, 170, 220), Glare = 0, Haze = 1.8 },
		Grade = { Saturation = 0.25, Contrast = 0.12, Brightness = 0, TintColor = rgb(255, 255, 250) },
		Bloom = { Intensity = 0.4, Size = 20, Threshold = 1.4 },
		SunRays = { Intensity = 0.04, Spread = 0.5 },
		Ambience = "Wind",
	},
	-- K-9: night forest of glowing mushrooms
	Mushroom = {
		Lighting = {
			ClockTime = 0.2,
			Brightness = 0.6,
			Ambient = rgb(60, 40, 80),
			OutdoorAmbient = rgb(80, 60, 110),
			ColorShift_Top = rgb(0, 0, 0),
			EnvironmentDiffuseScale = 0.4,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.4,
			ShadowSoftness = 0.3,
		},
		Atmosphere = { Density = 0.5, Offset = 0, Color = rgb(110, 70, 150), Decay = rgb(40, 20, 70), Glare = 0, Haze = 2.6 },
		Grade = { Saturation = 0.3, Contrast = 0.14, Brightness = 0, TintColor = rgb(240, 225, 255) },
		Bloom = { Intensity = 1.3, Size = 36, Threshold = 0.85 },
		SunRays = { Intensity = 0, Spread = 0.5 },
		Ambience = "Crickets",
	},
	-- B137 at sunset (the hunt ends here)
	DesertDusk = {
		Lighting = {
			ClockTime = 17.8,
			Brightness = 1.8,
			Ambient = rgb(96, 56, 52),
			OutdoorAmbient = rgb(160, 90, 74),
			ColorShift_Top = rgb(255, 110, 60),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.5,
			ExposureCompensation = 0.1,
			ShadowSoftness = 0.15,
		},
		Atmosphere = { Density = 0.5, Offset = 0.2, Color = rgb(255, 110, 70), Decay = rgb(140, 50, 60), Glare = 1.2, Haze = 2.8 },
		Grade = { Saturation = 0.05, Contrast = 0.16, Brightness = 0, TintColor = rgb(255, 222, 205) },
		Bloom = { Intensity = 0.8, Size = 28, Threshold = 1.1 },
		SunRays = { Intensity = 0.1, Spread = 0.5 },
		Ambience = "Wind",
	},
	-- the ruined Skibidi city around the camera base
	City = {
		Lighting = {
			ClockTime = 17.3,
			Brightness = 1.6,
			Ambient = rgb(80, 72, 70),
			OutdoorAmbient = rgb(140, 124, 116),
			ColorShift_Top = rgb(255, 170, 110),
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0.6,
			ExposureCompensation = 0.1,
			ShadowSoftness = 0.2,
		},
		Atmosphere = { Density = 0.48, Offset = 0.15, Color = rgb(200, 150, 120), Decay = rgb(110, 80, 70), Glare = 0.6, Haze = 2.4 },
		Grade = { Saturation = -0.15, Contrast = 0.16, Brightness = 0, TintColor = rgb(255, 236, 220) },
		Bloom = { Intensity = 0.7, Size = 26, Threshold = 1.15 },
		SunRays = { Intensity = 0.06, Spread = 0.5 },
		Ambience = "Wind",
	},
	CityAlarm = {
		Lighting = {
			ClockTime = 18.2,
			Brightness = 0.9,
			Ambient = rgb(90, 40, 60),
			OutdoorAmbient = rgb(120, 60, 90),
			ColorShift_Top = rgb(200, 90, 255),
			EnvironmentDiffuseScale = 0.5,
			EnvironmentSpecularScale = 0.7,
			ExposureCompensation = 0.15,
			ShadowSoftness = 0.3,
		},
		Atmosphere = { Density = 0.5, Offset = 0.1, Color = rgb(150, 80, 150), Decay = rgb(60, 20, 60), Glare = 0, Haze = 2.6 },
		Grade = { Saturation = 0, Contrast = 0.24, Brightness = 0, TintColor = rgb(255, 214, 236) },
		Bloom = { Intensity = 1.2, Size = 34, Threshold = 0.9 },
		SunRays = { Intensity = 0, Spread = 0.5 },
		Ambience = "Rumble",
	},
	-- back home, late at night
	HomeNight = {
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
		SunRays = { Intensity = 0, Spread = 0.5 },
		Lights = {
			MoonBeam = { Brightness = 3, Color = rgb(140, 165, 255) },
			SunBeam = false,
			DeskLamp = true,
			NightLamp = true,
			CeilingLight = false,
			StreetLamp = true,
			PortalLight = false,
			KitchenSun = false,
			KitchenLight = false,
			HallLight = false,
			PorchLight = true,
			GarageLight = true,
		},
		NightWindows = true,
		Portal = false,
		Ambience = "Crickets",
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
