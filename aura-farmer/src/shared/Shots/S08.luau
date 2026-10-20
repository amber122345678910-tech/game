--!strict
-- S08 (7.867–9.533 с): Парк: селфи-ECU коня в жёлтых авиаторах, поёт «WAKE UP IN THE MORNING».
-- Камера неподвижна (штатив, без тряски), всё движение — от коня (tools/anims/S08.luau).
-- Конь лежит на животе с поднятой грудью (поза S09), голова втянута между высоко поднятыми плечами.
-- Кадр по клипу: очки ≈42% ширины кадра (x 0.33–0.75), верх очков ≈0.15 кадра (≈10% чистого фона/лба
-- над очками в начале), переносица ≈(0.545, 0.28); синие плечи по бокам от середины кадра вниз,
-- воротник рубашки по бокам челюсти; горизонт (изгородь) чуть ниже центра.
-- Камера ≈2.25 студа от очков, на ≈0.5 студа ниже глаз, взгляд на +3° вверх, FOV 42 (≈28 мм).
-- Конец плана: «зум-блюр» (9.467–9.533) — размытие + лёгкий рывок FOV, подводит к рывку-отъезду S09.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local CX, CY, CZ = 0.09, 2.17, -3.70
local PITCH = math.rad(3)
local CAM = Config.at("Park", CX, CY, CZ)
local LOOK = Config.at("Park", CX, CY + 3 * math.sin(PITCH), CZ + 3 * math.cos(PITCH))
local FOV = 42

return {
	id = "S08",
	start = 7.8667,
	finish = 9.5333,
	set = "Park",
	preset = "Park",
	lighting = {
		-- солнце высоко (≈56°) за спиной коня, чуть слева в кадре: контровой свет по шерсти и верхам плеч,
		-- лицо в мягкой тени неба/отражённом от травы свете
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
		-- малая глубина резкости: фокус на очках (≈2.3 студа), лицо резкое, плечи чуть мягче, фон сильно размыт
		dof = { Enabled = true, FarIntensity = 0.8, NearIntensity = 0, InFocusRadius = 1.1, FocusDistance = 2.3 },
	},
	actors = {
		Horse = { char = "Horse", opts = { glasses = "yellow" }, place = Config.place("Park", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 7.8667, pos = CAM, look = LOOK, fov = FOV, blur = 0 },
			-- доля 19 (9.432): камера всё ещё неподвижна; к 9.467 — «зум-блюр» (в клипе радиальный, только фон)
			-- и лёгкий рывок FOV наружу — разгон перед рывком-отъездом S09
			{ t = 9.4333, pos = CAM, look = LOOK, fov = FOV, blur = 0, ease = "linear" },
			{ t = 9.4667, pos = CAM, look = LOOK, fov = FOV + 0.6, blur = 5, ease = "linear" },
			{ t = 9.5333, pos = CAM, look = LOOK, fov = FOV + 2.5, blur = 9 },
		},
		focus = { actor = "Horse", part = "Glasses" },
	},
	effects = {},
}
