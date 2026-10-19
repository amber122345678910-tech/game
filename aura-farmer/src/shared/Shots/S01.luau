--!strict
-- S01 (0.000–1.433 с): Парень сидит на песке и спускает авиаторы на кончик носа левой рукой.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

-- Камера смотрит на город (+Z): +X мира — СЛЕВА в кадре. pan > 0 — поворот вправо по кадру (к -X),
-- pitch > 0 — вверх.
local function camKey(t: number, x: number, y: number, z: number, pan: number, pitch: number, roll: number, fov: number, ease: string?): any
	local pos = Config.at("Beach", x, y, z)
	local p, w = math.rad(pitch), math.rad(pan)
	local dir = Vector3.new(-math.sin(w) * math.cos(p), math.sin(p), math.cos(w) * math.cos(p))
	return { t = t, pos = pos, look = pos + dir * 10, fov = fov, roll = roll, ease = ease }
end

return {
	id = "S01",
	start = 0.0,
	finish = 1.4333,
	set = "Beach",
	preset = "Beach",
	actors = {
		Man = { char = "Man", place = Config.place("Beach", 0, 0, 25) },
	},
	camera = {
		keys = {
			camKey(0.0, -0.15, 2.85, -4.55, 0, 2, 0, 34),
			camKey(1.4333, -0.15, 2.85, -4.1, 1.5, 5, 0, 34),
		},
		shake = { rot = 0.2, pos = 0.012, freq = 1.6, seed = 11 },
		focus = { actor = "Man", part = "Head" },
	},
	effects = {},
}
