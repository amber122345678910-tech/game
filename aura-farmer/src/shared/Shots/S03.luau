--!strict
-- S03 (2.700–3.867 с): Трое на пляже снимают очки и ахают.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера смотрит на город (+Z): +X мира — СЛЕВА в кадре.
local CAM_Z = -5.95
local CAM_Y = 5.12
local PITCH = math.rad(-5)

local function camKey(t: number, dz: number, fov: number, ease: string?): any
	local pos = Config.at("Beach", 0, CAM_Y, CAM_Z + dz)
	local look = pos + Vector3.new(0, math.sin(PITCH), math.cos(PITCH)) * 10
	return { t = t, pos = pos, look = look, fov = fov, ease = ease or "inout" }
end

return {
	id = "S03",
	start = 2.7,
	finish = 3.8667,
	set = "Beach",
	preset = "Beach",
	-- солнце сзади-справа от камеры (≈35° от оси, высота ≈47°): фронтальный жёсткий свет, левая щека парня
	-- (справа в кадре) в свету. Как в S01 (тот же пляж): тёплое солнце на коже, тёплый отсвет песка, холодное небо;
	-- глубокая резкость (телефон), без бликов; контраст выше, «киношная» насыщенность, чёрные штаны «в ноль»
	lighting = {
		sunDir = Vector3.new(-0.4, 0.72, -0.57),
		lighting = {
			Brightness = 3,
			ExposureCompensation = -0.4,
			ShadowSoftness = 0.08,
			ColorShift_Top = Color3.fromRGB(255, 226, 196),
			ColorShift_Bottom = Color3.fromRGB(96, 72, 52),
			OutdoorAmbient = Color3.fromRGB(122, 128, 142),
			Ambient = Color3.fromRGB(104, 90, 80),
		},
		atmosphere = { Density = 0.26, Offset = 0.12, Haze = 0.9, Glare = 0, Color = Color3.fromRGB(140, 170, 196), Decay = Color3.fromRGB(64, 108, 150) },
		bloom = { Intensity = 0.4, Size = 24, Threshold = 1.1 },
		sunRays = { Intensity = 0.01, Spread = 0.5 },
		cc = { Brightness = 0, Contrast = 0.26, Saturation = 0.22, TintColor = Color3.fromRGB(255, 242, 230) },
		dof = { FarIntensity = 0.04, InFocusRadius = 40 },
		clouds = { Cover = 0.2, Density = 0.1 },
	},
	actors = {
		-- девушка слева в кадре (+X мира)
		WomanA = { char = "WomanA", place = Config.place("Beach", 4.25, 1.8, 34, -0.5) },
		Man = { char = "Man", place = Config.place("Beach", 0, 0, 0), opts = {
				-- в этом плане очки в руках: серебряные, тёмные дымчатые стёкла
				glassesOn = "RightHand",
				glassesFrame = Color3.fromRGB(200, 204, 208),
				glassesLens = Color3.fromRGB(46, 47, 52),
				glassesLensTransparency = 0.05,
			} },
		-- девушка справа в кадре (-X мира)
		WomanB = { char = "WomanB", place = Config.place("Beach", -4.35, 1.8, -29, -0.4) },
	},
	camera = {
		keys = {
			camKey(2.7, 0, 48),
			camKey(3.8667, 0, 48),
		},
		shake = { rot = 0.05, pos = 0.005, freq = 1.2, seed = 3 },
		focus = { actor = "Man", part = "Head" },
	},
	effects = {},
}
