--!strict
-- S08 (7.867–9.533 с): Парк: конь снимает селфи, жёлтые авиаторы, поёт.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S08",
	start = 7.8667,
	finish = 9.5333,
	set = "Park",
	preset = "Park",
	actors = {
		Horse = { char = "Horse", place = Config.place("Park", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 7.8667, pos = Config.at("Park", 0, 6.0, -3.5), look = Config.at("Park", 0, 6.0, 0), fov = 55 },
			{ t = 9.5333, pos = Config.at("Park", 0, 6.0, -4.0), look = Config.at("Park", 0, 6.0, 0), fov = 55 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 8 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
