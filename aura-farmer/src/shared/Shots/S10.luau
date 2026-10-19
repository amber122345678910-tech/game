--!strict
-- S10 (11.133–13.133 с): Спортзал с фиолетовым неоном: конь качает гантель 500 кг.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S10",
	start = 11.1333,
	finish = 13.1333,
	set = "Gym",
	preset = "Gym",
	actors = {
		Horse = { char = "Horse", place = Config.place("Gym", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 11.1333, pos = Config.at("Gym", 0, 3.5, -10), look = Config.at("Gym", 0, 3.5, 0), fov = 55 },
			{ t = 13.1333, pos = Config.at("Gym", 0, 3.5, -10.5), look = Config.at("Gym", 0, 3.5, 0), fov = 55 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 10 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
