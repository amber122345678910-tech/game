--!strict
-- S11 (13.133–15.633 с): Тьма, луч прожектора: конь на золотом троне, нога на ногу.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S11",
	start = 13.1333,
	finish = 15.6333,
	set = "Throne",
	preset = "Throne",
	actors = {
		Horse = { char = "Horse", place = Config.place("Throne", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 13.1333, pos = Config.at("Throne", 0, 4, -14), look = Config.at("Throne", 0, 4, 0), fov = 40 },
			{ t = 15.6333, pos = Config.at("Throne", 0, 4, -14.5), look = Config.at("Throne", 0, 4, 0), fov = 40 },
		},
		shake = { rot = 0.25, pos = 0.01, freq = 0.9, seed = 11 },
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
