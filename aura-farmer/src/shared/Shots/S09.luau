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
		Horse = { char = "Horse", place = Config.place("Park", 0, 0, 0), opts = { glasses = "yellow" } },
	},
	camera = {
		keys = {
			{ t = 9.5333, pos = Config.at("Park", 0, 0.95, -7.2), look = Config.at("Park", 0, 2.05, 0), fov = 40 },
			{ t = 11.1333, pos = Config.at("Park", 0, 0.95, -7.2), look = Config.at("Park", 0, 2.05, 0), fov = 41.3 },
		},
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
