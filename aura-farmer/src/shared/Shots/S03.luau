--!strict
-- S03 (2.700–3.867 с): Трое на пляже снимают очки и ахают.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S03",
	start = 2.7,
	finish = 3.8667,
	set = "Beach",
	preset = "Beach",
	actors = {
		WomanA = { char = "WomanA", place = Config.place("Beach", -3, 0, 0) },
		Man = { char = "Man", place = Config.place("Beach", 0, 0, 0) },
		WomanB = { char = "WomanB", place = Config.place("Beach", 3, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 2.7, pos = Config.at("Beach", 0, 3.8, -11), look = Config.at("Beach", 0, 3.6, 0), fov = 45 },
			{ t = 3.8667, pos = Config.at("Beach", 0, 3.8, -11.5), look = Config.at("Beach", 0, 3.6, 0), fov = 45 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 3 },
		focus = { actor = "WomanA", part = "Head" },
	},
	effects = {},
}
