--!strict
-- S01 (0.000–1.433 с): Парень сидит на песке и спускает авиаторы на кончик носа левой рукой.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера смотрит на город (+Z): +X мира — СЛЕВА в кадре. pan > 0 — поворот вправо по кадру (к -X),
-- pitch > 0 — вверх, roll < 0 — «по часовой» (горизонт поднимается к правому краю кадра).
-- Ключ задаётся кадрированием: точка AIM (центр головы) должна оказаться в точке кадра (sx, sy)
-- (доли ширины/высоты, 0,0 — левый верх) на расстоянии dist по лучу; ориентация — pan/pitch/roll.
-- Точка постановки: ближе к морю, чтобы павильон и город за спиной были дальше и мельче (как в клипе).
local SX, SZ = 0, -70
local AIM = Config.at("Beach", SX + 0.1, 3.3, SZ)
local ASPECT = 16 / 9
local function camKey(t: number, sx: number, sy: number, dist: number, pan: number, pitch: number, roll: number, fov: number, ease: string?): any
	local p, w, r = math.rad(pitch), math.rad(pan), math.rad(roll)
	local look = Vector3.new(-math.sin(w) * math.cos(p), math.sin(p), math.cos(w) * math.cos(p))
	local right = look:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(look).Unit
	-- крен как в CameraTrack: lookAt(...) * CFrame.Angles(0, 0, roll)
	local rx = right * math.cos(r) + up * math.sin(r)
	local ry = up * math.cos(r) - right * math.sin(r)
	local th = math.tan(math.rad(fov) / 2)
	local ray = (look + rx * ((2 * sx - 1) * th * ASPECT) + ry * ((1 - 2 * sy) * th)).Unit
	local pos = AIM - ray * dist
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
			Brightness = 2.9,
			ExposureCompensation = -0.05,
			ShadowSoftness = 0.05,
			OutdoorAmbient = Color3.fromRGB(138, 146, 160),
			Ambient = Color3.fromRGB(94, 100, 112),
		},
		atmosphere = { Density = 0.28, Offset = 0.15, Haze = 1.1, Glare = 0, Color = Color3.fromRGB(199, 214, 224), Decay = Color3.fromRGB(84, 124, 168) },
		bloom = { Intensity = 0.45, Size = 28, Threshold = 1.1 },
		sunRays = { Intensity = 0.01, Spread = 0.5 },
		cc = { Brightness = 0.01, Contrast = 0.2, Saturation = 0.22, TintColor = Color3.fromRGB(255, 246, 236) },
		dof = { Enabled = true, FarIntensity = 0.42, NearIntensity = 0, InFocusRadius = 1.8, FocusDistance = 4.6 },
		clouds = { Cover = 0.22, Density = 0.12 },
	},
	actors = {
		-- сидит на песке, грудь развёрнута на 25° влево от оси камеры
		Man = { char = "Man", place = Config.place("Beach", SX, SZ, 25) },
		-- друг полулёжа на локтях позади-справа по кадру (не в фокусе), ноги к камере и вправо
		Friend = {
			char = "Human",
			place = Config.place("Beach", SX - 6.75, SZ + 8.9, 80),
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
			-- кадрирование сверено с клипом: макушка/подбородок/горизонт; наезд ~12%, подъём взгляда 2.6° -> 5.9°
			camKey(0, 0.447, 0.35, 4.90, 0, 2.6, -1, 34, "linear"),
			camKey(0.3, 0.437, 0.38, 4.80, 0.35, 3.2, -1.1, 34, "linear"),
			camKey(0.633, 0.405, 0.44, 4.65, 0.85, 4.2, -1.2, 34, "linear"),
			camKey(0.8, 0.39, 0.455, 4.55, 1.0, 5.0, -1.25, 34, "linear"),
			camKey(1.0, 0.38, 0.47, 4.52, 1.3, 5.6, -1.3, 34, "linear"),
			camKey(1.4333, 0.375, 0.465, 4.48, 1.5, 5.9, -1.3, 34, "linear"),
		},
		shake = { rot = 0.2, pos = 0.012, freq = 1.6, seed = 11 },
		focus = { actor = "Man", part = "Head" },
	},
	effects = {},
}
