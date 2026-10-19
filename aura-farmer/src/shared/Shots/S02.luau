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

-- Камера неподвижна, на оси коня, ~1.9 студа перед пряжкой и на 0.35 ниже точки взгляда:
-- наклон вверх ~10° (горизонт на ~79% высоты кадра, видна нижняя фаска «A»), без крена.
-- FOV 28 (чуть длиннее «40 мм» клипа): кулаки у модели крупнее пряжки относительно клипа — длинный фокус
-- уменьшает их перспективное раздувание, а чуть более широкий кадр, чем «пряжка в 66% высоты», не даёт
-- кулакам съесть углы кадра (рукава пиджака видны сверху по углам, как в клипе).
-- Положение «A» в кадре сверено покадрово с клипом (центр основания ±7 px по X при 854×480, высота ~61% кадра).
local LOOK = cs(0, 2.885, -0.74)
local CAM = cs(0, 2.535, -2.68)

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
			{ t = 1.4333, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 1.56, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 1.625, pos = CAM, look = LOOK, fov = 28, blur = 1.6 },
			{ t = 1.68, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 1.92, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 1.97, pos = CAM, look = LOOK, fov = 28, blur = 1.2 },
			{ t = 2.05, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 2.38, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 2.43, pos = CAM, look = LOOK, fov = 28, blur = 1.3 },
			{ t = 2.49, pos = CAM, look = LOOK, fov = 28, blur = 0 },
			{ t = 2.7, pos = CAM, look = LOOK, fov = 28, blur = 0 },
		},
		-- штатив: лишь едва заметный медленный дрейф
		shake = { rot = 0.04, pos = 0.002, freq = 0.5, seed = 2 },
		-- фокус на пряжке (кулаки в зоне резкости, пирс и пляж мягко размыты)
		focus = { actor = "Horse", part = "BuckleGlintHost" },
	},
	lighting = {
		-- солнце высоко (~57°) за конём и чуть левее в кадре: контровой свет по верхам кулаков, рукавам, лацканам
		sunDir = Vector3.new(-0.25, 0.84, -0.48),
		lighting = {
			Brightness = 3.5,
			ExposureCompensation = 0.3, -- небо пересвечено, как в клипе
			Ambient = Color3.fromRGB(70, 60, 64),
			-- заливка спереди тёплая (свет отражён от песка за камерой), ~1.5 ступени под контровым
			OutdoorAmbient = Color3.fromRGB(168, 150, 140),
			ColorShift_Top = Color3.fromRGB(255, 226, 196), -- тёплый контровой ободок на мехе и рукавах
		},
		bloom = { Intensity = 0.85, Size = 28, Threshold = 1.15 },
		-- клип: насыщенно, но фиолет пиджака уходит в пурпур, а не в синеву; чёрные слегка приподняты
		cc = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.08, TintColor = Color3.fromRGB(255, 240, 236) },
		dof = { Enabled = true, FarIntensity = 0.42, NearIntensity = 0.12, InFocusRadius = 0.9, FocusDistance = 1.9 },
	},
	effects = {
		-- Блик на вершине «A» (1.900–2.233), как в клипе: тёплое нарастание 1 кадр, удар 1.933,
		-- пик 1.967–2.133 (на доле 2.114), спад 2–3 кадра. BuckleFlare — шар Neon на вершине (ядро; ореол
		-- даёт Bloom), BuckleGlint — одна «звезда» на удар и вторая на долю 4, чтобы звезда держалась весь пик.
		-- Размеры — под масштаб кадра (~0.002 студа/пиксель при 854×480): ядро ~60 px, ореол — блумом.
		{ t = 1.900, dur = 0.001, kind = "tween", name = "BuckleFlare", prop = "Color", from = WARM, to = WARM },
		{ t = 1.900, dur = 0.001, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.06), to = ball(0.06) },
		{ t = 1.900, dur = 0.033, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 1, to = 0.55, ease = "out" },
		-- удар (рывок кистями в 1.933 «ловит солнце»)
		{ t = 1.925, kind = "emit", name = "BuckleGlint", count = 1 },
		{ t = 1.933, dur = 0.033, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 0.55, to = 0, ease = "out" },
		{ t = 1.933, dur = 0.05, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.06), to = ball(0.11), ease = "out" },
		{ t = 1.933, dur = 0.05, kind = "tween", name = "BuckleFlare", prop = "Color", from = WARM, to = HOT, ease = "out" },
		-- пик: ядро чуть растёт и «дышит» к доле 4
		{ t = 1.983, dur = 0.13, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.11), to = ball(0.135), ease = "inout" },
		{ t = 2.060, kind = "emit", name = "BuckleGlint", count = 1 },
		-- спад: к 2.233 всё погасло
		{ t = 2.133, dur = 0.1, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 0, to = 1, ease = "in" },
		{ t = 2.133, dur = 0.1, kind = "tween", name = "BuckleFlare", prop = "Size", from = ball(0.135), to = ball(0.05), ease = "in" },
		{ t = 2.133, dur = 0.08, kind = "tween", name = "BuckleFlare", prop = "Color", from = HOT, to = WARM, ease = "in" },
	},
}
