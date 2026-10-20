--!strict
-- S07 (6.600–7.867 с): Две девушки, селфи-ракурс снизу, «He's such a charmer».
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Локальная «сцена» плана: начало — между стоп девушки A, девушки смотрят в −Z сцены (к камере),
-- камера стоит в −Z и смотрит в +Z сцены — на город, повернув на YAW° к +X мира, чтобы высотки
-- (x < 0) оказались справа в кадре, а слева — пустой пляж до горизонта.
-- Пропорции людей новые (центр головы ≈5.4 над землёй): камера-«селфи» ≈1.2–1.5 ниже лиц и ≈2.2–2.5 от них,
-- FOV 72 (≈104° по горизонтали, как широкоугольник клипа), голландский крен −13°.
local YAW = 15
local FOV = 72
local STAGE = Config.place("Beach", 0, 0, YAW)
local function W(x: number, y: number, z: number): Vector3
	return (STAGE * CFrame.new(x, y, z)).Position
end
-- Ключ камеры в координатах сцены: позиция, курс yaw (от оси +Z сцены) и тангаж pitch вверх (градусы).
-- yaw > 0 — объектив повёрнут к A (+X сцены, влево в кадре). Крен −13° — «голландский угол»: горизонт поднимается вправо.
local function camKey(t: number, p: { number }, yaw: number, pitch: number, ease: string?): any
	local y, pt = math.rad(yaw), math.rad(pitch)
	local dir = Vector3.new(math.sin(y) * math.cos(pt), math.sin(pt), math.cos(y) * math.cos(pt))
	local pos = W(p[1], p[2], p[3])
	local look = (STAGE * CFrame.new(Vector3.new(p[1], p[2], p[3]) + dir * 3)).Position
	return { t = t, pos = pos, look = look, fov = FOV, roll = -13, ease = ease }
end

return {
	id = "S07",
	start = 6.6,
	finish = 7.8667,
	set = "Beach",
	preset = "Beach",
	-- Жёсткий полуденный свет: солнце сзади-слева от камеры (≈45° от оси, высота ≈57°) — лица залиты почти
	-- фронтально, тени под подбородками вниз-вправо. Небо без облаков, густо-синее (яркое солнце + отрицательная
	-- экспозиция: лица и белые майки светлые, небо темнее); тёплый ColorShift — тёплая кожа; дымка у горизонта;
	-- глубокая резкость (DOF выкл.), контраст и насыщенность выше, мягкое свечение белых маек.
	lighting = {
		sunDir = STAGE:VectorToWorldSpace(Vector3.new(0.32, 0.84, -0.44)),
		lighting = {
			Brightness = 3.6,
			ExposureCompensation = -1.0,
			Ambient = Color3.fromRGB(56, 62, 74),
			OutdoorAmbient = Color3.fromRGB(122, 132, 148),
			ShadowSoftness = 0.08,
			ColorShift_Top = Color3.fromRGB(255, 232, 206),
		},
		atmosphere = { Density = 0.26, Offset = 0.1, Color = Color3.fromRGB(176, 200, 220), Decay = Color3.fromRGB(70, 110, 150), Glare = 0, Haze = 0.9 },
		bloom = { Intensity = 0.45, Size = 24, Threshold = 1.0 },
		sunRays = { Intensity = 0 },
		cc = { Brightness = 0, Contrast = 0.3, Saturation = 0.38, TintColor = Color3.fromRGB(255, 250, 244) },
		dof = { Enabled = false },
		clouds = { Enabled = false },
	},
	actors = {
		-- A у начала сцены, повёрнута к B (влево) на 25° (+ ещё ≈10° корпусом в ключах); B — слева от A и чуть дальше
		-- от объектива (её корпус в ключах повёрнут на ≈17° влево — к правому краю кадра)
		WomanA = {
			char = "WomanA",
			place = STAGE * CFrame.Angles(0, math.rad(25), 0),
			-- в этом плане: кремовая майка в рубчик с высоким круглым вырезом, очки в правой руке
			-- (низ — в цвет майки: в начале плана пояс шорт мелькает под поднятой рукой, в клипе там майка)
			opts = {
				glassesOn = "RightHand",
				topStyle = "tank",
				scoop = 0.2,
				top = Color3.fromRGB(238, 230, 222),
				bottom = Color3.fromRGB(234, 226, 218),
				stitch = Color3.fromRGB(234, 226, 218),
				roses = Color3.fromRGB(234, 226, 218),
			},
		},
		WomanB = {
			char = "WomanB",
			place = STAGE * CFrame.new(-1.79, 0, 0.38),
			opts = {
				glassesOn = "RightHand",
				-- шорты B в этом плане видны только краем в правом нижнем углу (в клипе там белая майка):
				-- красим их в цвет майки, чтобы низ читался как продолжение майки
				bottom = Color3.fromRGB(240, 239, 236),
				stripe = Color3.fromRGB(240, 239, 236),
			},
		},
	},
	camera = {
		-- кусочно-линейный путь (без сплайнового «перелёта» после быстрого подъёма)
		path = "linear",
		keys = {
			-- 6.6–7.0: наезд с подъёмом камеры на ≈0.5 (Sine InOut — плавно трогается после склейки и «садится» на долю 6.992),
			-- дальше до склейки — медленный дрейф вперёд и наклон вверх ещё на ≈1° (дальний план чуть уходит вниз)
			camKey(6.6, { -0.86, 3.8, -2.18 }, 5, 15.0, "Sine_InOut"),
			camKey(7.0, { -0.82, 4.4, -2.2 }, 4, 17.4, "linear"),
			camKey(7.8667, { -0.83, 4.45, -2.15 }, 4, 18.6),
		},
		shake = { rot = 0.1, pos = 0.005, freq = 1.5, seed = 7 },
		focus = { actor = "WomanA", part = "Head" },
	},
	effects = {},
}
