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
-- FOV 26 (чуть длиннее «40 мм» клипа): кулаки у модели крупнее пряжки, длинный фокус уменьшает их перспективное раздувание.
-- Положение/размер «A» в кадре сверены покадрово с клипом (центр, высота ~62% кадра, ширина ~31%).
local LOOK = cs(0, 2.865, -0.74)
local CAM = cs(0, 2.515, -2.68)

local WARM = Color3.fromRGB(255, 226, 170)

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
			{ t = 1.4333, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 1.56, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 1.625, pos = CAM, look = LOOK, fov = 26, blur = 1.6 },
			{ t = 1.68, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 1.92, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 1.97, pos = CAM, look = LOOK, fov = 26, blur = 1.2 },
			{ t = 2.05, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 2.38, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 2.43, pos = CAM, look = LOOK, fov = 26, blur = 1.3 },
			{ t = 2.49, pos = CAM, look = LOOK, fov = 26, blur = 0 },
			{ t = 2.7, pos = CAM, look = LOOK, fov = 26, blur = 0 },
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
			ExposureCompensation = 0.4, -- небо пересвечено, как в клипе
			Ambient = Color3.fromRGB(64, 58, 72),
			OutdoorAmbient = Color3.fromRGB(150, 148, 160), -- мягкая заливка спереди (песок/небо за камерой)
		},
		bloom = { Intensity = 0.85, Size = 28, Threshold = 1.15 },
		cc = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.2, TintColor = Color3.fromRGB(255, 248, 240) },
		dof = { Enabled = true, FarIntensity = 0.42, NearIntensity = 0.12, InFocusRadius = 0.9, FocusDistance = 1.9 },
	},
	effects = {
		-- Блик на вершине «A» (1.90–2.233): быстрая атака (1 кадр), удержание на доле 2.114, спад 2–3 кадра.
		-- нарастание: тёплое свечение у вершины
		{ t = 1.9, dur = 0.033, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 1, to = 0.6, ease = "out" },
		{ t = 1.9, dur = 0.001, kind = "tween", name = "BuckleFlare", prop = "Color", from = WARM, to = WARM },
		-- удар: вспышка и звезда
		{ t = 1.92, kind = "emit", name = "BuckleGlint", count = 1 },
		{ t = 1.933, dur = 0.034, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 0.6, to = 0.05, ease = "out" },
		{ t = 1.933, dur = 0.12, kind = "tween", name = "BuckleFlare", prop = "Size", from = Vector3.new(0.12, 0.12, 0.12), to = Vector3.new(0.26, 0.26, 0.26), ease = "out" },
		{ t = 1.95, dur = 0.08, kind = "tween", name = "BuckleFlare", prop = "Color", from = WARM, to = Color3.fromRGB(255, 246, 230), ease = "out" },
		-- спад
		{ t = 2.14, dur = 0.093, kind = "tween", name = "BuckleFlare", prop = "Transparency", from = 0.05, to = 1, ease = "in" },
		{ t = 2.14, dur = 0.093, kind = "tween", name = "BuckleFlare", prop = "Size", from = Vector3.new(0.26, 0.26, 0.26), to = Vector3.new(0.1, 0.1, 0.1), ease = "in" },
	},
}
