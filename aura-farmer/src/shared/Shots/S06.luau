--!strict
-- S06 (5.900–6.600 с): Сверхкрупно: улыбка с огромными зубами на фоне солнца.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S06",
	start = 5.9,
	finish = 6.6,
	set = "Beach",
	preset = "Beach",
	lighting = {
		sunDir = Vector3.new(-0.334, 0.52, -0.786),
	},
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 180) },
	},
	camera = {
		keys = {
			{ t = 5.9, pos = Config.at("Beach", -1.596, 5.227, 3.216), look = Config.at("Beach", -0.642, 5.828, 0.235), fov = 24 },
			{ t = 6.0, pos = Config.at("Beach", -1.779, 5.212, 2.48), look = Config.at("Beach", -0.742, 5.828, 0.205), fov = 30 },
			{ t = 6.1, pos = Config.at("Beach", -0.132, 5.2, 2.751), look = Config.at("Beach", -0.487, 5.719, 1.18), fov = 38 },
		},


		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
