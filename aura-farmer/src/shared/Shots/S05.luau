--!strict
-- S05 (4.967–5.900 с): Крупно: золотая цепь сверкает на груди.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера неподвижна (locked-off), фронтально по оси груди, сверху (≈−11°: у нашей цепи дуга глубже, чем в клипе,
-- взгляд сверху «уплощает» её в ту же «улыбку» с концами под воротником), vFOV 30.
-- «Грув» (наезд/отъезд 1–3 %) делает сам конь (tools/anims/S05.luau), камера не двигается.
local CAM = Config.at("Beach", 0, 4.53, -2.5)
local LOOK = Config.at("Beach", 0, 4.044, 0)
local FOCUS = 1.95 -- дистанция до цепи (плоскость фокуса — цепь и внутренние края воротника)

return {
	id = "S05",
	start = 4.9667,
	finish = 5.9,
	set = "Beach",
	preset = "Beach",
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 0) },
	},
	camera = {
		-- Неподвижная камера; единственный «ход» — смаз (blur) на 1 кадр в момент «качка» цепи на 5.40.
		keys = {
			{ t = 4.9667, pos = CAM, look = LOOK, fov = 30, focus = FOCUS, blur = 0 },
			{ t = 5.367, pos = CAM, look = LOOK, fov = 30, focus = FOCUS, blur = 0 },
			{ t = 5.4, pos = CAM, look = LOOK, fov = 30, focus = FOCUS, blur = 1.2 },
			{ t = 5.45, pos = CAM, look = LOOK, fov = 30, focus = FOCUS, blur = 0 },
			{ t = 5.9, pos = CAM, look = LOOK, fov = 30, focus = FOCUS, blur = 0 },
		},
	},
	-- Контровое солнце сзади-слева по кадру (+X — правая сторона коня = левая сторона кадра), ~37° над горизонтом:
	-- грудь в тени, цепь и мех ловят контровой свет; холодное синее заполнение спереди (небо).
	lighting = {
		sunDir = Vector3.new(0.72, 0.6, 0.35),
		lighting = {
			Brightness = 3.5,
			ExposureCompensation = -0.2,
			EnvironmentDiffuseScale = 0.6,
			Ambient = Color3.fromRGB(26, 28, 44),
			OutdoorAmbient = Color3.fromRGB(78, 84, 112),
		},
		bloom = { Intensity = 1.1, Size = 36, Threshold = 0.9 },
		sunRays = { Intensity = 0.03, Spread = 0.5 },
		cc = { Brightness = -0.02, Contrast = 0.2, Saturation = 0.08, TintColor = Color3.fromRGB(255, 246, 238) },
		dof = { Enabled = true, FocusDistance = FOCUS, InFocusRadius = 0.45, NearIntensity = 0.5, FarIntensity = 0.4 },
	},
	-- Блеск цепи: постоянные мелкие «звёздочки» (эмиттер ChainSparkles на груди коня), всплеск на долю 10,
	-- вспышка на «качке» 5.40, короткий провал числа бликов, пока цепь «переезжает» (5.44–5.53), и восстановление.
	effects = {
		-- перенастройка эмиттера под крупный план: мелкие короткоживущие четырёхлучевые блики, их больше
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Size", to = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 0.085),
			NumberSequenceKeypoint.new(1, 0),
		}) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Lifetime", to = NumberRange.new(0.12, 0.26) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Rate", to = 36 },
		{ t = 4.9667, stop = 5.9, kind = "enable", name = "ChainSparkles", on = true },
		{ t = 5.44, stop = 5.53, kind = "enable", name = "ChainSparkles", on = false },
		-- доля 10 (5.041): всплеск бликов (+40 %), затухает к 5.2
		{ t = 5.035, kind = "emit", name = "ChainSparkles", count = 9 },
		-- «качок» на шестнадцатую перед долей 11: цепь ловит солнце
		{ t = 5.395, kind = "emit", name = "ChainSparkles", count = 6 },
		-- после провала на доле 11 блики «набираются» обратно
		{ t = 5.6, kind = "emit", name = "ChainSparkles", count = 4 },
	},
}
