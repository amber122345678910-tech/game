--!strict
-- S02 (1.433–2.700 с): Крупно: лапы коня держат ремень с золотой пряжкой «A», блик.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S02",
	start = 1.4333,
	finish = 2.7,
	set = "Beach",
	preset = "Beach",
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 1.4333, pos = Config.at("Beach", 0, 2.6, -3), look = Config.at("Beach", 0, 2.9, 0), fov = 40 },
			{ t = 2.7, pos = Config.at("Beach", 0, 2.6, -3.5), look = Config.at("Beach", 0, 2.9, 0), fov = 40 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 2 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
