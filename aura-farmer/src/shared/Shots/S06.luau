--!strict
-- S06 (5.900–6.600 с): Сверхкрупно: улыбка с огромными зубами на фоне солнца.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local CAM = Config.at("Beach", 0.193, 5.203, 2.561)
local LOOK = Config.at("Beach", -0.465, 5.714, 1.121)

return {
	id = "S06",
	start = 5.9,
	finish = 6.6,
	set = "Beach",
	preset = "Beach",
	lighting = {
		sunDir = Vector3.new(-0.488, 0.521, -0.7),
		lighting = {
			ExposureCompensation = -0.25,
			Ambient = Color3.fromRGB(96, 84, 78),
			OutdoorAmbient = Color3.fromRGB(170, 166, 168),
		},
		atmosphere = { Density = 0.3, Offset = 0.1, Color = Color3.fromRGB(205, 211, 211), Decay = Color3.fromRGB(155, 174, 191), Glare = 0.6, Haze = 1.6 },
		bloom = { Intensity = 1.0, Size = 48, Threshold = 1.0 },
		sunRays = { Intensity = 0.12, Spread = 0.7 },
		cc = { Brightness = 0.02, Contrast = 0.2, Saturation = 0.05, TintColor = Color3.fromRGB(255, 250, 242) },
		dof = { Enabled = true, FarIntensity = 0.7, NearIntensity = 0, InFocusRadius = 1.2, FocusDistance = 1.4 },
		clouds = { Enabled = false },
	},
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 180) },
	},
	camera = {
		keys = {
			{ t = 5.9, pos = CAM, look = LOOK, fov = 38 },
			{ t = 6.6, pos = CAM, look = LOOK, fov = 38 },
		},
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
