--!strict
-- S01 (0.000–1.433 с): Парень на пляже опускает авиаторы.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S01",
	start = 0.0,
	finish = 1.4333,
	set = "Beach",
	preset = "Beach",
	actors = {
		Man = { char = "Man", place = Config.place("Beach", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 0.0, pos = Config.at("Beach", 0, 4.6, -5), look = Config.at("Beach", 0, 4.6, 0), fov = 40 },
			{ t = 1.4333, pos = Config.at("Beach", 0, 4.6, -5.5), look = Config.at("Beach", 0, 4.6, 0), fov = 40 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 1 },
		focus = { actor = "Man", part = "Head" },
	},
	effects = {},
}
