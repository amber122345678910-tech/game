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
			{ t = 7.8667, pos = Config.at("Park", 0.145, 2.623, -5.318), look = Config.at("Park", 0.145, 2.78, -2.322), fov = 34 },
			{ t = 9.5333, pos = Config.at("Park", 0.145, 2.623, -5.318), look = Config.at("Park", 0.145, 2.78, -2.322), fov = 34 },
		},
		focus = { actor = "Horse", part = "Glasses" },
	},
	effects = {},
}
