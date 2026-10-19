--!strict
-- S06 (5.900–6.600 с): Сверхкрупно: улыбка с огромными зубами на фоне солнца.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S06",
	start = 5.9,
	finish = 6.6,
	set = "Beach",
	preset = "Beach",
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 5.9, pos = Config.at("Beach", 0, 5.0, -3.5), look = Config.at("Beach", 0, 5.8, 0), fov = 40 },
			{ t = 6.6, pos = Config.at("Beach", 0, 5.0, -4.0), look = Config.at("Beach", 0, 5.8, 0), fov = 40 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 6 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
