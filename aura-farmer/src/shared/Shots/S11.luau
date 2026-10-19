--!strict
-- S11 (13.133–15.633 с): Тьма, луч прожектора: конь на золотом троне, нога на ногу.
-- Камера: низкий ракурс снизу вверх, равномерная дуга ~35° вокруг трона к правому боку персонажа
-- (влево в кадре) с креном -6° -> +20° (картинка поворачивается по часовой).
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local START, FINISH = 13.1333, 15.6333

-- Параметры дуги (локальные координаты декорации Throne; трон смотрит в -Z, камера спереди).
-- az > 0 — камера уходит к правому боку персонажа (+X, слева в кадре).
local ARC = {
	center = Vector3.new(0, 0, 0.2),
	az0 = -6,
	az1 = 26,
	r0 = 7.6,
	r1 = 7.44,
	h0 = 1.68,
	h1 = 1.81,
	look0 = Vector3.new(0.04, 3.67, -1.74),
	look1 = Vector3.new(-1.25, 4.45, 0.22),
	roll0 = -11,
	roll1 = 17.1,
	fov = 55,
}

local function camKeys(): { any }
	local keys = {}
	local n = 6
	for i = 0, n do
		local a = i / n
		local t = START + (FINISH - START) * a
		local az = math.rad(ARC.az0 + (ARC.az1 - ARC.az0) * a)
		local r = ARC.r0 + (ARC.r1 - ARC.r0) * a
		local h = ARC.h0 + (ARC.h1 - ARC.h0) * a
		local p = ARC.center + Vector3.new(math.sin(az) * r, h, -math.cos(az) * r)
		local look = ARC.look0:Lerp(ARC.look1, a)
		table.insert(keys, {
			t = t,
			pos = Config.at("Throne", p.X, p.Y, p.Z),
			look = Config.at("Throne", look.X, look.Y, look.Z),
			fov = ARC.fov,
			roll = ARC.roll0 + (ARC.roll1 - ARC.roll0) * a,
			ease = "linear",
		})
	end
	return keys
end

return {
	id = "S11",
	start = START,
	finish = FINISH,
	set = "Throne",
	preset = "Throne",
	-- Клип: жёсткий тёплый верхний прожектор, всё вокруг — чистый чёрный; насыщенный фиолетовый пиджак и красный
	-- бархат, сильный ореол (bloom) на золоте; глубокая резкость (всё от колена до гребня резкое).
	lighting = {
		lighting = { Ambient = Color3.fromRGB(22, 16, 30), ExposureCompensation = 0.05 },
		bloom = { Intensity = 1.4, Size = 44, Threshold = 0.95 },
		cc = { Brightness = 0.01, Contrast = 0.22, Saturation = 0.2, TintColor = Color3.fromRGB(255, 244, 236) },
		dof = { FarIntensity = 0.08, NearIntensity = 0, InFocusRadius = 10 },
	},
	actors = {
		Horse = { char = "Horse", place = Config.place("Throne", 0, 0, 0), opts = { sparkles = true } },
	},
	camera = {
		keys = camKeys(),
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {
		-- искры на золотой цепи и бляхе «A» весь план (аура включена opts.sparkles)
		{ t = START, kind = "enable", name = "ChainSparkles", on = true },
		{ t = START, kind = "enable", name = "BuckleGlint", on = true },
		-- доля 13.334: кулаки вверх — вспышка золотых искр у трона; пик хохота 13.50 — всплеск ауры
		{ t = 13.334, kind = "emit", name = "ThroneSparkles", count = 14 },
		{ t = 13.5, kind = "emit", name = "AuraSparkles", count = 18 },
	},
}
