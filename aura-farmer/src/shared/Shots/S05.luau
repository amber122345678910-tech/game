--!strict
-- S05 (4.967–5.900 с): Крупно: золотая цепь сверкает на груди.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S05",
	start = 4.9667,
	finish = 5.9,
	set = "Beach",
	preset = "Beach",
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 4.9667, pos = Config.at("Beach", 0, 4.5, -3), look = Config.at("Beach", 0, 4.5, 0), fov = 40 },
			{ t = 5.9, pos = Config.at("Beach", 0, 4.5, -3.5), look = Config.at("Beach", 0, 4.5, 0), fov = 40 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 5 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
