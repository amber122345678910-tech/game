--!strict
-- S05 (4.967–5.900 с): Крупно: золотая цепь сверкает на груди.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера неподвижна (locked-off), фронтально по оси груди. Кадр — «инсерт» по клипу: цепь дугой в верхней трети
-- (x 0.28–0.71, верх 0.06, низ дуги ≈0.44; в клипе x 0.28–0.69, 0.08–0.36), острые воротники из верхних углов
-- к центру, «V» меха по центру почти до низа кадра, атлас пиджака по краям. У нашей цепи дуга глубже, звенья крупнее,
-- а вырез рубашки короче, чем в клипе, поэтому камера ниже груди и смотрит вверх (~22°): дальние концы дуги
-- опускаются (дуга площе), цепь поднимается к кончикам воротников, а «V» меха вытягивается к низу кадра
-- (подбор по совпадению цветовых зон с кадром клипа). Расстояние до цепи ≈2.0, vFOV 22.
-- «Грув» (наезд/отъезд 1–2.3 %) делает сам конь (tools/anims/S05.luau).
local CAM = Config.at("Beach", 0, 3.25, -2.4)
local LOOK = Config.at("Beach", 0, 4.2, 0)
local FOV = 22
local FOCUS = 2.0 -- дистанция до цепи (плоскость фокуса — цепь и внутренние края воротника)

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
			{ t = 4.9667, pos = CAM, look = LOOK, fov = FOV, focus = FOCUS, blur = 0 },
			{ t = 5.367, pos = CAM, look = LOOK, fov = FOV, focus = FOCUS, blur = 0 },
			{ t = 5.4, pos = CAM, look = LOOK, fov = FOV, focus = FOCUS, blur = 1.5 },
			{ t = 5.45, pos = CAM, look = LOOK, fov = FOV, focus = FOCUS, blur = 0 },
			{ t = 5.9, pos = CAM, look = LOOK, fov = FOV, focus = FOCUS, blur = 0 },
		},
	},
	-- Низкий ключ, как в клипе: тёплое солнце сзади-сверху слева по кадру (+X — правая сторона коня = левая сторона
	-- кадра; ≈125° от оси камеры, ≈30° над горизонтом) — контровой: левый конец цепи и левый воротник на свету,
	-- правая половина груди в тени. Заполнение — холодное небо спереди (OutdoorAmbient) даёт атласу королевскую
	-- синеву; насыщенность +, контраст давит черноту меха, тёплый «грейд» светов.
	lighting = {
		sunDir = Vector3.new(0.72, 0.55, 0.2),
		lighting = {
			Brightness = 5,
			ExposureCompensation = -0.2,
			EnvironmentDiffuseScale = 0.35,
			EnvironmentSpecularScale = 0.6,
			Ambient = Color3.fromRGB(30, 32, 56),
			OutdoorAmbient = Color3.fromRGB(80, 88, 130),
		},
		bloom = { Intensity = 1.2, Size = 36, Threshold = 0.9 },
		sunRays = { Intensity = 0.03, Spread = 0.5 },
		cc = { Brightness = -0.02, Contrast = 0.3, Saturation = -0.2, TintColor = Color3.fromRGB(255, 246, 238) },
		dof = { Enabled = true, FocusDistance = FOCUS, InFocusRadius = 0.6, NearIntensity = 0.5, FarIntensity = 0.25 },
	},
	-- Блеск цепи: постоянные мелкие «звёздочки» (эмиттер ChainSparkles на груди коня), всплеск на долю 10,
	-- вспышка на «качке» 5.40, провал числа бликов, пока цепь «переезжает» (5.43–5.53), и восстановление к 5.6.
	effects = {
		-- объём эмиттера — тонкий слой прямо по видимой дуге цепи (хост в (0, 4.30, −0.53))
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkleHost", prop = "Size", to = Vector3.new(0.9, 0.42, 0.12) },
		-- перенастройка эмиттера под крупный план: мелкие короткоживущие четырёхлучевые блики (0.02–0.06 студа), их много
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Size", to = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 0.06),
			NumberSequenceKeypoint.new(1, 0),
		}) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Lifetime", to = NumberRange.new(0.1, 0.25) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Color", to = ColorSequence.new(
			Color3.fromRGB(255, 248, 222),
			Color3.fromRGB(255, 222, 150)
		) },
		{ t = 4.9667, dur = 0.001, kind = "tween", name = "ChainSparkles", prop = "Rate", from = 80, to = 80 },
		{ t = 4.9667, stop = 5.9, kind = "enable", name = "ChainSparkles", on = true },
		-- доля 10 (5.041): всплеск бликов (+40 %), затухает к 5.2
		{ t = 5.035, kind = "emit", name = "ChainSparkles", count = 9 },
		-- «качок» на шестнадцатую перед долей 11: цепь ловит солнце
		{ t = 5.395, kind = "emit", name = "ChainSparkles", count = 6 },
		-- цепь «переезжает» — бликов меньше (−30 %), к 5.6 снова полный блеск
		{ t = 5.43, dur = 0.03, kind = "tween", name = "ChainSparkles", prop = "Rate", from = 80, to = 45 },
		{ t = 5.53, dur = 0.08, kind = "tween", name = "ChainSparkles", prop = "Rate", from = 45, to = 80 },
		{ t = 5.6, kind = "emit", name = "ChainSparkles", count = 3 },
	},
}
