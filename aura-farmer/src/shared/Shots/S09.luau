--!strict
-- S09 (9.533–11.133 с): Парк: конь лежит на траве, ноги вверх, резкий наезд.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S09",
	start = 9.5333,
	finish = 11.1333,
	set = "Park",
	preset = "Park",
	actors = {
		Horse = { char = "Horse", place = Config.place("Park", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 9.5333, pos = Config.at("Park", 0, 2.0, -9), look = Config.at("Park", 0, 1.5, 0), fov = 50 },
			{ t = 11.1333, pos = Config.at("Park", 0, 2.0, -9.5), look = Config.at("Park", 0, 1.5, 0), fov = 50 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 9 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
