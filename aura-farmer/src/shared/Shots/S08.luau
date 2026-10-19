--!strict
-- S08 (7.867–9.533 с): Парк: селфи-ECU коня в жёлтых авиаторах, поёт «WAKE UP IN THE MORNING».
local Config = require(script.Parent.Parent:WaitForChild("Config"))

return {
	id = "S08",
	start = 7.8667,
	finish = 9.5333,
	set = "Park",
	preset = "Park",
	actors = {
		Horse = { char = "Horse", opts = { glasses = "yellow" }, place = Config.place("Park", 0, 0, 0) },
	},
	camera = {
		keys = {
			{ t = 7.8667, pos = Config.at("Park", 0.133, 2.450, -4.808), look = Config.at("Park", 0.133, 2.607, -1.812), fov = 40 },
			{ t = 9.5333, pos = Config.at("Park", 0.133, 2.450, -4.808), look = Config.at("Park", 0.133, 2.607, -1.812), fov = 40 },
		},
		focus = { actor = "Horse", part = "Glasses" },
	},
	effects = {},
}
