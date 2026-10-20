--!strict
-- S01 (0.000–1.433 с): Парень сидит на песке и спускает авиаторы на кончик носа левой рукой.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера смотрит на город (+Z): +X мира — СЛЕВА в кадре. pan > 0 — поворот вправо по кадру (к -X),
-- pitch > 0 — вверх, roll < 0 — «по часовой» (горизонт поднимается к правому краю кадра).
-- Ключ: позиция камеры (локально в декорации, x/y/z) + ориентация pan/pitch/roll. Позиции решены по кадрам клипа
-- (ближний глаз, макушка, низ бороды; pitch — по высоте горизонта) и сглажены в ровный наезд.
local SX, SZ = 0, 0
local function camKey(t: number, x: number, y: number, z: number, pan: number, pitch: number, roll: number, fov: number, ease: string?): any
	local p, w = math.rad(pitch), math.rad(pan)
	local look = Vector3.new(-math.sin(w) * math.cos(p), math.sin(p), math.cos(w) * math.cos(p))
	local pos = Config.at("Beach", SX + x, y, SZ + z)
	return { t = t, pos = pos, look = pos + look * 10, fov = fov, roll = roll, ease = ease }
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
			Brightness = 2.3,
			ExposureCompensation = -0.7,
			ShadowSoftness = 0.05,
			-- тёплое солнце на коже (в клипе ≈5600K, без «бледности»), тёплый отсвет песка снизу, холодное небо
			ColorShift_Top = Color3.fromRGB(255, 226, 196),
			ColorShift_Bottom = Color3.fromRGB(96, 72, 52),
			OutdoorAmbient = Color3.fromRGB(120, 126, 140),
			Ambient = Color3.fromRGB(112, 94, 80),
		},
		atmosphere = { Density = 0.26, Offset = 0.12, Haze = 0.9, Glare = 0, Color = Color3.fromRGB(118, 156, 184), Decay = Color3.fromRGB(64, 108, 150) },
		bloom = { Intensity = 0.45, Size = 28, Threshold = 1.1 },
		sunRays = { Intensity = 0.01, Spread = 0.5 },
		cc = { Brightness = 0, Contrast = 0.24, Saturation = 0.2, TintColor = Color3.fromRGB(255, 240, 228) },
		dof = { Enabled = true, FarIntensity = 0.42, NearIntensity = 0, InFocusRadius = 1.8, FocusDistance = 4.6 },
		clouds = { Cover = 0.22, Density = 0.12 },
	},
	actors = {
		-- сидит на песке, грудь развёрнута на 25° влево от оси камеры
		Man = { char = "Man", place = Config.place("Beach", SX, SZ, 25) },
		-- друг полулёжа на локтях позади-справа по кадру (не в фокусе), ноги к камере и вправо
		Friend = {
			char = "Human",
			place = Config.place("Beach", SX - 4.8, SZ + 10.6, 40),
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
			-- наезд ~0.3 студа с подъёмом взгляда (горизонт 0.55 -> 0.65 кадра) и панорамой вправо 1.5°
			camKey(0, -0.227, 3.10, -4.945, 0, 1.75, -1, 34),
			camKey(0.3, -0.27, 3.17, -4.91, 0.35, 2.45, -1.1, 34),
			camKey(0.633, -0.33, 3.22, -4.81, 0.85, 3.15, -1.2, 34),
			camKey(0.8, -0.39, 3.20, -4.74, 1.0, 4.2, -1.25, 34),
			camKey(1.0, -0.44, 3.17, -4.66, 1.3, 4.54, -1.3, 34),
			camKey(1.4333, -0.455, 3.13, -4.59, 1.5, 5.07, -1.3, 34),
		},
		shake = { rot = 0.2, pos = 0.012, freq = 1.6, seed = 11 },
		focus = { actor = "Man", part = "Head" },
	},
	-- В клипе в этом плане нет VFX (ни бликов, ни вспышек): только субтитр (Lyrics), DOF по голове и ручная камера.
	effects = {},
}
