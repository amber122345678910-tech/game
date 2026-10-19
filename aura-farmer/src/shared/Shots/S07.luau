--!strict
-- S07 (6.600–7.867 с): Две девушки, селфи-ракурс снизу, «He's such a charmer».
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S07",
	start = 6.6,
	finish = 7.8667,
	set = "Beach",
	preset = "Beach",
	actors = {
		WomanA = { char = "WomanA", place = Config.place("Beach", -0.9, 0, 0) },
		WomanB = { char = "WomanB", place = Config.place("Beach", 1.2, 0, 0.5) },
	},
	camera = {
		keys = {
			{ t = 6.6, pos = Config.at("Beach", 0, 3.6, -3.5), look = Config.at("Beach", 0, 4.6, 0), fov = 80 },
			{ t = 7.8667, pos = Config.at("Beach", 0, 3.6, -4.0), look = Config.at("Beach", 0, 4.6, 0), fov = 80 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 7 },
		focus = { actor = "WomanA", part = "Head" },
	},
	effects = {},
}
