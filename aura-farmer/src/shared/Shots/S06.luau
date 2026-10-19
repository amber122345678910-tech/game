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
			{ t = 5.9, pos = Config.at("Beach", -0.227, 5.2, 2.608), look = Config.at("Beach", -0.506, 5.719, 1.02), fov = 38 },
			{ t = 6.0, pos = Config.at("Beach", -0.23, 5.199, 2.473), look = Config.at("Beach", -0.538, 5.719, 0.886), fov = 38 },
			{ t = 6.1, pos = Config.at("Beach", 0.042, 5.202, 2.64), look = Config.at("Beach", -0.49, 5.719, 1.128), fov = 38 },
			{ t = 6.2, pos = Config.at("Beach", 0.317, 5.205, 2.643), look = Config.at("Beach", -0.44, 5.719, 1.242), fov = 38 },
		},




		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
