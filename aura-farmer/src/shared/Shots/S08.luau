--!strict
-- S08 (7.867–9.533 с): Парк: селфи-ECU коня в жёлтых авиаторах, поёт «WAKE UP IN THE MORNING».
-- Камера неподвижна (штатив), всё движение — от коня. Конь в той же позе, что в S09 (лежит на животе,
-- грудь почти вертикально), камера у лица чуть ниже глаз, смотрит на +3° вверх, широкий объектив (FOV 42).
-- Конец плана: радиальный «зум-блюр» (9.467–9.533) — размытие + лёгкий рывок FOV, подводит к наезду-отъезду S09.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local CX, CY, CZ = 0.09, 1.7, -4.3
local PITCH = math.rad(3)
local CAM = Config.at("Park", CX, CY, CZ)
local LOOK = Config.at("Park", CX, CY + 3 * math.sin(PITCH), CZ + 3 * math.cos(PITCH))
local FOV = 42
local DEBUG_SIDE = true
if DEBUG_SIDE then
	CAM = Config.at("Park", -7, 1.6, -1.6)
	LOOK = Config.at("Park", 0, 1.4, -1.0)
	FOV = 40
end

return {
	id = "S08",
	start = 7.8667,
	finish = 9.5333,
	set = "Park",
	preset = "Park",
	lighting = {
		-- солнце высоко за спиной коня, чуть слева в кадре (контровой свет, лицо в мягкой тени неба)
		sunDir = Vector3.new(0.25, 0.83, 0.5),
		lighting = {
			Brightness = 3.2,
			ExposureCompensation = 0.3,
			Ambient = Color3.fromRGB(84, 88, 84),
			OutdoorAmbient = Color3.fromRGB(160, 170, 166),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,
			ShadowSoftness = 0.35,
		},
		atmosphere = {
			Density = 0.3,
			Offset = 0.15,
			Color = Color3.fromRGB(205, 214, 210),
			Decay = Color3.fromRGB(163, 180, 126),
			Glare = 0.3,
			Haze = 1.5,
		},
		bloom = { Intensity = 0.7, Size = 30, Threshold = 0.95 },
		sunRays = { Intensity = 0.04, Spread = 0.6 },
		cc = { Brightness = 0.02, Contrast = 0.15, Saturation = 0.28, TintColor = Color3.fromRGB(255, 248, 236) },
		-- малая глубина резкости: лицо резкое (фокус — очки), плечи чуть мягче, фон сильно размыт
		dof = { Enabled = true, FarIntensity = 0.8, NearIntensity = 0, InFocusRadius = 1.4, FocusDistance = 2.6 },
	},
	actors = {
		Horse = { char = "Horse", opts = { glasses = "yellow" }, place = Config.place("Park", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 7.8667, pos = CAM, look = LOOK, fov = FOV },
			{ t = 9.4667, pos = CAM, look = LOOK, fov = FOV, blur = 0, ease = "in" },
			{ t = 9.5333, pos = CAM, look = LOOK, fov = FOV + 2.5, blur = 9 },
		},
		focus = { actor = "Horse", part = "Glasses" },
	},
	effects = {},
}
