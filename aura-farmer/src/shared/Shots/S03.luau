--!strict
-- S03 (2.700–3.867 с): Трое на пляже снимают очки и ахают.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера смотрит на город (+Z): +X мира — СЛЕВА в кадре.
local CAM_Z = -6.1
local CAM_Y = 4.38
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
	actors = {
		-- девушка слева в кадре (+X мира)
		WomanA = { char = "WomanA", place = Config.place("Beach", 5.15, 3.5, 22) },
		Man = { char = "Man", place = Config.place("Beach", 0, 0, 0), opts = {
				-- в этом плане очки в руках: серебряные, тёмные дымчатые стёкла
				glassesOn = "RightHand",
				glassesFrame = Color3.fromRGB(200, 204, 208),
				glassesLens = Color3.fromRGB(46, 47, 52),
				glassesLensTransparency = 0.05,
			} },
		-- девушка справа в кадре (-X мира)
		WomanB = { char = "WomanB", place = Config.place("Beach", -5.3, 3.5, -24) },
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
