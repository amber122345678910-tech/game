--!strict
-- S02 (1.433–2.700 с): Крупно: лапы коня держат ремень с золотой пряжкой «A», блик.
-- Вставка-деталь: камера на штативе (без движения), вся энергия — от бёдер (анимация в tools/anims/S02.luau).
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Конь стоит в (0,0,0) лицом к морю (yaw 180 -> смотрит в +Z), камера перед ним смотрит на море:
-- за конём горизонт, пирс (x=+160) — справа в кадре, песок — снизу слева.
local function cs(x: number, y: number, z: number): Vector3
	-- char space (yaw 180) -> мир Beach
	return Config.at("Beach", -x, y, -z)
end

-- Камера неподвижна, на оси коня, ~2.15 студа перед пряжкой и ~0.43 ниже её центра: наклон вверх 9.5°
-- (горизонт на ~81% высоты кадра, видна нижняя фаска «A»), без крена.
-- FOV 30 (длиннее «40 мм» клипа): кулаки у модели крупнее пряжки относительно клипа — длинный фокус
-- уменьшает их перспективное раздувание. «A» — 63–68% высоты кадра (в клипе 61–67%), кулаки — в левой/правой
-- трети, рукава с часами — в верхних углах. Низ «A» и центр её основания сверены покадрово с клипом
-- (все 38 кадров, расхождение ≲ ±8 px при 854×480), перстни — ±2 px в опорных кадрах.
local LOOK = cs(0, 2.817, -0.74)
local CAM = cs(0, 2.492, -2.68)

-- Блик: тёплый ореол (#FFB050) -> раскалённое ядро (#FFF6E6)
local WARM = Color3.fromRGB(255, 176, 80)
local HOT = Color3.fromRGB(255, 246, 230)
local function ball(d: number): Vector3
	return Vector3.new(d, d, d)
end

return {
	id = "S02",
	start = 1.4333,
	finish = 2.7,
	set = "Beach",
	preset = "Beach",
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 180) },
	},
	camera = {
		-- позиция не меняется; blur — лёгкая «выдержка» на самых быстрых кадрах (провалы/отскоки бёдер),
		-- как смаз меха в клипе (1.567–1.633, 1.933–2.067, 2.400–2.467)
		keys = {
			{ t = 1.4333, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 1.56, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 1.625, pos = CAM, look = LOOK, fov = 30, blur = 1.6 },
			{ t = 1.68, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 1.92, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 1.97, pos = CAM, look = LOOK, fov = 30, blur = 1.2 },
			{ t = 2.05, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 2.38, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 2.43, pos = CAM, look = LOOK, fov = 30, blur = 1.3 },
			{ t = 2.49, pos = CAM, look = LOOK, fov = 30, blur = 0 },
			{ t = 2.7, pos = CAM, look = LOOK, fov = 30, blur = 0 },
		},
		-- штатив: лишь едва заметный медленный дрейф
		shake = { rot = 0.04, pos = 0.002, freq = 0.5, seed = 2 },
		-- фокус на пряжке (кулаки в зоне резкости, пирс и пляж мягко размыты)
		focus = { actor = "Horse", part = "BuckleGlintHost" },
	},
	lighting = {
		-- солнце высоко (~59°) за конём и чуть левее в кадре: контровой свет по верхам кулаков, рукавам, лацканам
		sunDir = Vector3.new(-0.25, 0.86, -0.45),
		lighting = {
			Brightness = 4.5,
			ExposureCompensation = 0.3, -- небо пересвечено, как в клипе
			Ambient = Color3.fromRGB(56, 48, 52),
			-- заливка спереди тёплая (свет отражён от песка за камерой), ~1.5 ступени под контровым
			OutdoorAmbient = Color3.fromRGB(128, 116, 112),
			EnvironmentDiffuseScale = 0.7, -- контровой свет: фронт (рубашка, брюки) в мягкой тени
			ColorShift_Top = Color3.fromRGB(255, 226, 196), -- тёплый контровой ободок на мехе и рукавах
		},
		bloom = { Intensity = 0.85, Size = 28, Threshold = 1.15 },
		-- клип: насыщенно, но фиолет пиджака уходит в пурпур, а не в синеву; чёрные слегка приподняты
		cc = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.0, TintColor = Color3.fromRGB(255, 240, 240) },
		dof = { Enabled = true, FarIntensity = 0.42, NearIntensity = 0.12, InFocusRadius = 0.9, FocusDistance = 2.15 },
	},
	effects = {
		-- Блик на вершине «A» (1.900–2.233), как в клипе: тёплое нарастание 1.900, удар 1.933, пик 1.967–2.133
		-- (на доле 2.114), спад 2–3 кадра, к 2.233 всё погасло. BuckleFlare — шар Neon на вершине (раскалённое ядро,
		-- ореол даёт Bloom); BuckleGlint — ОДНА «звезда» (sparkles_main) на весь блик: жизнь 0.32 с (1.91–2.23), кривая
		-- размера — удар за кадр, плато на пике, гаснет к 2.23; без вращения — длинный луч вертикально, в вырез
		-- рубашки, как световой «шип» над вершиной в клипе. Масштаб кадра ~0.0024 студа/px (854×480):
		-- ядро ~0.08–0.13 (35–55 px), звезда ~0.45 (лучи ±95 px).
		{ t = 1.4333, dur = 0.001, kind = "tween", name = "BuckleGlint", prop = "Lifetime", to = NumberRange.new(0.32) },
		{ t = 1.4333, dur = 0.001, kind = "tween", name = "BuckleGlint", prop = "Rotation", to = NumberRange.new(0) },
		{ t = 1.4333, dur = 0.001, kind = "tween", name = "BuckleGlint", prop = "RotSpeed", to = NumberRange.new(40) },
		{ t = 1.4333, dur = 0.001, kind = "tween", name = "BuckleGlint", prop = "Size", to = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.08, 0.4),
			NumberSequenceKeypoint.new(0.45, 0.48),
			NumberSequenceKeypoint.new(0.7, 0.44),
			NumberSequenceKeypoint.new(1, 0),
		}) },
		{ t = 1.4333, dur = 0.001, kind = "tween", name = "BuckleGlint", prop = "Transparency", to = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.08, 0),
			NumberSequenceKeypoint.new(0.7, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		}) },
		{ t = 1.4333, dur = 0.001, kind = "tween", name = "BuckleGlint", prop = "Color", to = ColorSequence.new(HOT, WARM) },
		-- нарастание (кадр 1.900): тёплая дымка у вершины
		{ t = 1.875, dur = 0.001, kind = "tween", name = "BuckleFlare", prop = "Color", from = WARM, to = WARM },
		{ t = 1.875, dur = 0.001, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.05), to = ball(0.05) },
		{ t = 1.875, dur = 0.025, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 1, to = 0.6, ease = "out" },
		-- удар (кадр 1.933; рывок кистями «ловит солнце»): атака за 1 кадр
		{ t = 1.910, kind = "emit", name = "BuckleGlint", count = 1 },
		{ t = 1.905, dur = 0.025, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 0.6, to = 0, ease = "out" },
		{ t = 1.905, dur = 0.03, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.05), to = ball(0.095), ease = "out" },
		{ t = 1.905, dur = 0.03, kind = "tween", name = "BuckleFlare", prop = "Color", from = WARM, to = HOT, ease = "out" },
		-- пик 1.967–2.133: ядро чуть растёт и «дышит» к доле 4 (2.114)
		{ t = 1.95, dur = 0.16, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.095), to = ball(0.13), ease = "inout" },
		-- спад: к 2.233 всё погасло
		{ t = 2.133, dur = 0.1, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 0, to = 1, ease = "in" },
		{ t = 2.133, dur = 0.1, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.13), to = ball(0.04), ease = "in" },
		{ t = 2.133, dur = 0.08, kind = "tween", name = "BuckleFlare", prop = "Color", from = HOT, to = WARM, ease = "in" },
	},
}
