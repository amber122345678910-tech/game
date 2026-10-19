--!strict
-- S04 (3.867–4.967 с): Нижний ракурс, солнце сзади: конь поворачивает голову и показывает большим пальцем назад.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S04",
	start = 3.8667,
	finish = 4.9667,
	set = "Beach",
	preset = "Beach",
	actors = {
		Horse = { char = "Horse", place = Config.place("Beach", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 3.8667, pos = Config.at("Beach", 0, 2.5, -7), look = Config.at("Beach", 0, 5.5, 0), fov = 50 },
			{ t = 4.9667, pos = Config.at("Beach", 0, 2.5, -7.5), look = Config.at("Beach", 0, 5.5, 0), fov = 50 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 4 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
