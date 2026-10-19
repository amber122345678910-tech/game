--!strict
-- S01 (0.000–1.433 с): Парень сидит на песке и спускает авиаторы на кончик носа левой рукой.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера смотрит на город (+Z): +X мира — СЛЕВА в кадре. pan > 0 — поворот вправо по кадру (к -X),
-- pitch > 0 — вверх.
local function camKey(t: number, x: number, y: number, z: number, pan: number, pitch: number, roll: number, fov: number, ease: string?): any
	local pos = Config.at("Beach", x, y, z)
	local p, w = math.rad(pitch), math.rad(pan)
	local dir = Vector3.new(-math.sin(w) * math.cos(p), math.sin(p), math.cos(w) * math.cos(p))
	return { t = t, pos = pos, look = pos + dir * 10, fov = fov, roll = roll, ease = ease }
end

return {
	id = "S01",
	start = 0.0,
	finish = 1.4333,
	set = "Beach",
	preset = "Beach",
	-- Жёсткое полуденное солнце сверху-слева из-за камеры (60° над горизонтом), глубокое синее небо,
	-- контраст «тил-оранж», малая глубина резкости (друг и город мягкие).
	lighting = {
		sunDir = Vector3.new(0.42, 0.85, -0.32),
		lighting = {
			Brightness = 2.9,
			ExposureCompensation = -0.05,
			ShadowSoftness = 0.05,
			OutdoorAmbient = Color3.fromRGB(138, 146, 160),
			Ambient = Color3.fromRGB(94, 100, 112),
		},
		atmosphere = { Density = 0.24, Offset = 0.15, Haze = 0.9, Glare = 0.05, Color = Color3.fromRGB(190, 210, 226), Decay = Color3.fromRGB(110, 140, 170) },
		bloom = { Intensity = 0.45, Size = 28, Threshold = 1.1 },
		sunRays = { Intensity = 0.01, Spread = 0.5 },
		cc = { Brightness = 0.01, Contrast = 0.2, Saturation = 0.22, TintColor = Color3.fromRGB(255, 246, 236) },
		dof = { Enabled = true, FarIntensity = 0.38, NearIntensity = 0, InFocusRadius = 2.6, FocusDistance = 4.4 },
		clouds = { Cover = 0.22, Density = 0.12 },
	},
	actors = {
		-- сидит на песке, грудь развёрнута на 25° влево от оси камеры
		Man = { char = "Man", place = Config.place("Beach", 0, 0, 25) },
		-- друг полулёжа на локтях позади-справа по кадру (не в фокусе), ноги к камере и вправо
		Friend = {
			char = "Human",
			place = Config.place("Beach", -4.5, 11.0, 38),
			opts = {
				skin = Color3.fromRGB(214, 162, 140),
				hair = Color3.fromRGB(42, 26, 20),
				hairStyle = "curls",
				eyes = Color3.fromRGB(70, 52, 40),
				top = Color3.fromRGB(234, 234, 236),
				topStyle = "tee",
				bottom = Color3.fromRGB(59, 91, 176),
				bottomStyle = "shorts",
				shoes = "barefoot",
				glasses = "aviator",
				glassesFrame = Color3.fromRGB(196, 150, 56),
				glassesLens = Color3.fromRGB(224, 160, 32),
				glassesLensTransparency = 0.2,
			},
		},
	},
	camera = {
		keys = {
			-- подобрано по кадрам клипа: глаз, макушка и горизонт в тех же местах кадра
			camKey(0, -0.068, 2.874, -4.625, 0, 1.75, -1, 34),
			camKey(0.3, -0.131, 2.988, -4.580, 0.35, 2.45, -1.1, 34),
			camKey(0.633, -0.195, 3.085, -4.469, 0.85, 3.15, -1.2, 34),
			camKey(0.8, -0.302, 2.962, -4.569, 1, 4.20, -1.25, 34),
			camKey(1, -0.374, 2.843, -4.583, 1.3, 4.54, -1.3, 34),
			camKey(1.4333, -0.320, 2.773, -4.575, 1.5, 5.07, -1.3, 34),
		},
		shake = { rot = 0.2, pos = 0.012, freq = 1.6, seed = 11 },
		focus = { actor = "Man", part = "Head" },
	},
	effects = {},
}
