--!strict
-- S07 (6.600–7.867 с): Две девушки, селфи-ракурс снизу, «He's such a charmer».
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Локальная «сцена» плана: начало — между стоп девушки A, девушки смотрят в −Z сцены (к камере),
-- камера стоит в −Z и смотрит в +Z сцены — на город, повернув на YAW° к +X мира, чтобы высотки
-- (x < 0) оказались справа в кадре, а слева — пустой пляж до горизонта.
local YAW = 15
local FOV = 72
local STAGE = Config.place("Beach", 0, 0, YAW)
local function W(x: number, y: number, z: number): Vector3
	return (STAGE * CFrame.new(x, y, z)).Position
end
-- Ключ камеры в координатах сцены: позиция, курс yaw (от оси +Z сцены) и тангаж pitch вверх (градусы).
-- yaw < 0 — объектив повёрнут к B (−X сцены, вправо в кадре). Крен −13° — «голландский угол»: горизонт поднимается вправо.
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
	-- фронтально, тени под подбородками вниз-вправо. Небо без облаков, густо-синее; дымка у горизонта;
	-- глубокая резкость (DOF выкл.), контраст и насыщенность выше, мягкое свечение белых маек.
	lighting = {
		sunDir = STAGE:VectorToWorldSpace(Vector3.new(0.32, 0.84, -0.44)),
		lighting = {
			Brightness = 3.1,
			ExposureCompensation = -0.4,
			Ambient = Color3.fromRGB(62, 74, 85),
			OutdoorAmbient = Color3.fromRGB(154, 166, 176),
			ShadowSoftness = 0.08,
			ColorShift_Top = Color3.fromRGB(255, 246, 234),
		},
		atmosphere = { Density = 0.28, Offset = 0.15, Color = Color3.fromRGB(198, 211, 220), Decay = Color3.fromRGB(110, 138, 160), Glare = 0, Haze = 1.2 },
		bloom = { Intensity = 0.4, Size = 24, Threshold = 1.05 },
		sunRays = { Intensity = 0 },
		cc = { Brightness = 0, Contrast = 0.22, Saturation = 0.25, TintColor = Color3.fromRGB(246, 248, 255) },
		dof = { Enabled = false },
		clouds = { Enabled = false },
	},
	actors = {
		-- A повёрнута к B (влево) на 25°, B — на 8° влево (корпус B смотрит чуть правее камеры, как в клипе)
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
			place = STAGE * CFrame.new(-1.8, 0, 0.85) * CFrame.Angles(0, math.rad(0), 0),
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
		keys = {
			-- 6.6–7.0: быстрый наезд с подъёмом (Sine Out, приходит на долю 6.992), дальше — медленный дрейф вперёд-вправо
			camKey(6.6, { -0.78, 3.85, -2.25 }, 8, 13.5, "Sine_Out"),
			camKey(7.0, { -1.02, 4.42, -2.12 }, 8, 15, "linear"),
			camKey(7.4, { -1.06, 4.47, -2.16 }, 8, 15.5, "linear"),
			camKey(7.8667, { -1.1, 4.52, -2.24 }, 8, 16.0),
		},
		shake = { rot = 0.1, pos = 0.005, freq = 1.5, seed = 7 },
		focus = { actor = "WomanA", part = "Head" },
	},
	effects = {},
}
