--!strict
-- S02 (1.433–2.700 с): Крупно: лапы коня держат ремень с золотой пряжкой «A», блик.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Конь стоит в (0,0,0) лицом к морю (yaw 180 -> смотрит в +Z), камера перед ним смотрит на море:
-- за конём горизонт, пирс (x=+160) — справа в кадре.
local function cs(x: number, y: number, z: number): Vector3
	-- char space (yaw 180) -> мир Beach
	return Config.at("Beach", -x, y, -z)
end

-- Камера неподвижна: на 0.31 ниже точки взгляда (наклон вверх ~10°, горизонт на ~79% высоты кадра),
-- точка взгляда чуть ниже центра пряжки, чтобы «A» стояла в кадре выше центра, как в клипе.
local LOOK = cs(0, 2.91, -0.74)
local CAM = cs(0, 2.56, -2.74)

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
		keys = {
			{ t = 1.4333, pos = CAM, look = LOOK, fov = 26 },
			{ t = 2.7, pos = CAM, look = LOOK, fov = 26 },
		},
		shake = { rot = 0.04, pos = 0.002, freq = 0.5, seed = 2 },
		focus = { actor = "Horse", part = "BuckleGlintHost" },
	},
	-- солнце высоко за конём и чуть слева в кадре (контровой свет по мехам и рукавам)
	lighting = {
		sunDir = Vector3.new(-0.25, 0.84, -0.48),
		lighting = {
			Brightness = 3.5,
			ExposureCompensation = 0.4,
			Ambient = Color3.fromRGB(64, 58, 72),
			OutdoorAmbient = Color3.fromRGB(150, 148, 160),
		},
		dof = { Enabled = true, FarIntensity = 0.4, NearIntensity = 0.1, InFocusRadius = 0.9, FocusDistance = 1.6 },
	},
	effects = {},
}
