--!strict
-- S05 (4.967–5.900 с): Крупно: золотая цепь сверкает на груди.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера неподвижна (locked-off), фронтально по оси груди, чуть сверху (≈−8°: у нашей цепи дуга глубже, чем в клипе,
-- взгляд сверху «уплощает» её к «улыбке» с концами под воротником), vFOV 30. Цепь — x 0.30–0.69, низ дуги y≈0.36 кадра
-- (в клипе x 0.29–0.69, y 0.08–0.37). «Грув» (наезд/отъезд 1–2.3 %) делает сам конь (tools/anims/S05.luau).
local CAM = Config.at("Beach", 7, 4, -11)
local LOOK = Config.at("Beach", 0, 3.4, 0)
local FOCUS = 1.9 -- дистанция до цепи (плоскость фокуса — цепь и внутренние края воротника)

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
			{ t = 4.9667, pos = CAM, look = LOOK, fov = 40, focus = FOCUS, blur = 0 },
			{ t = 5.367, pos = CAM, look = LOOK, fov = 40, focus = FOCUS, blur = 0 },
			{ t = 5.4, pos = CAM, look = LOOK, fov = 40, focus = FOCUS, blur = 1.5 },
			{ t = 5.45, pos = CAM, look = LOOK, fov = 40, focus = FOCUS, blur = 0 },
			{ t = 5.9, pos = CAM, look = LOOK, fov = 40, focus = FOCUS, blur = 0 },
		},
	},
	-- Низкий ключ, как в клипе (средняя яркость кадра ≈54/255): тёплое солнце сбоку-сверху слева по кадру
	-- (+X — правая сторона коня = левая сторона кадра), чуть из-за плеча — левый воротник и левый конец цепи
	-- на свету, правая половина груди в тени; холодное синее заполнение неба спереди; тёплый «грейд» прибирает
	-- синеву атласа, контраст давит черноту меха.
	lighting = {
		sunDir = Vector3.new(0.85, 0.48, -0.12),
		lighting = {
			Brightness = 5,
			ExposureCompensation = -0.7,
			EnvironmentDiffuseScale = 0.45,
			EnvironmentSpecularScale = 0.7,
			Ambient = Color3.fromRGB(22, 24, 40),
			OutdoorAmbient = Color3.fromRGB(64, 72, 104),
		},
		bloom = { Intensity = 1.2, Size = 36, Threshold = 0.9 },
		sunRays = { Intensity = 0.03, Spread = 0.5 },
		cc = { Brightness = -0.03, Contrast = 0.3, Saturation = -0.15, TintColor = Color3.fromRGB(255, 236, 226) },
		dof = { Enabled = true, FocusDistance = FOCUS, InFocusRadius = 0.45, NearIntensity = 0.5, FarIntensity = 0.4 },
	},
	-- Блеск цепи: постоянные мелкие «звёздочки» (эмиттер ChainSparkles на груди коня), всплеск на долю 10,
	-- вспышка на «качке» 5.40, провал числа бликов, пока цепь «переезжает» (5.43–5.53), и восстановление к 5.6.
	effects = {
		-- объём эмиттера — тонкий слой прямо по нижней дуге цепи (а не коробка перед грудью)
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkleHost", prop = "Size", to = Vector3.new(0.86, 0.36, 0.1) },
		-- перенастройка эмиттера под крупный план: мелкие короткоживущие четырёхлучевые блики (0.02–0.06 студа), их много
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Size", to = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 0.07),
			NumberSequenceKeypoint.new(1, 0),
		}) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Lifetime", to = NumberRange.new(0.1, 0.25) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Color", to = ColorSequence.new(
			Color3.fromRGB(255, 248, 222),
			Color3.fromRGB(255, 222, 150)
		) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Rate", from = 70, to = 70 },
		{ t = 4.9667, stop = 5.9, kind = "enable", name = "ChainSparkles", on = true },
		-- доля 10 (5.041): всплеск бликов (+40 %), затухает к 5.2
		{ t = 5.035, kind = "emit", name = "ChainSparkles", count = 8 },
		-- «качок» на шестнадцатую перед долей 11: цепь ловит солнце
		{ t = 5.395, kind = "emit", name = "ChainSparkles", count = 6 },
		-- цепь «переезжает» — бликов меньше (−30 %), к 5.6 снова полный блеск
		{ t = 5.43, dur = 0.03, kind = "tween", name = "ChainSparkles", prop = "Rate", from = 70, to = 38 },
		{ t = 5.53, dur = 0.08, kind = "tween", name = "ChainSparkles", prop = "Rate", from = 38, to = 70 },
		{ t = 5.6, kind = "emit", name = "ChainSparkles", count = 3 },
	},
}
