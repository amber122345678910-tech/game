--!strict
-- S10 (11.133–13.133 с): Спортзал с фиолетовым неоном: конь качает гантель 500 кг.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local HZ = -0.7 -- таз коня на переднем конце скамьи (сиденье z∈[-1.4,-0.18], верх Y=1.55)

return {
	id = "S10",
	start = 11.1333,
	finish = 13.1333,
	set = "Gym",
	preset = "Gym",
	actors = {
		Horse = { char = "Horse", place = Config.place("Gym", 0, HZ, 0), opts = { props = { "dumbbell" } } },
		Ginger = {
			char = "Human",
			place = Config.place("Gym", 3.8, 1.6, 90),
			opts = {
				female = true,
				height = 0.98,
				build = 0.9,
				skin = Color3.fromRGB(232, 188, 168),
				hair = Color3.fromRGB(160, 88, 58),
				hairStyle = "shag",
				lashes = true,
				top = Color3.fromRGB(236, 230, 234),
				topStyle = "crop",
				bottom = Color3.fromRGB(26, 26, 30),
				bottomStyle = "baggy",
				roses = Color3.fromRGB(192, 40, 58),
				stitch = Color3.fromRGB(220, 220, 224),
				shoes = "barefoot",
			},
		},
		Curly = {
			char = "Human",
			place = Config.place("Gym", -4.8, 1.8, -55),
			opts = {
				height = 1.0,
				build = 0.95,
				skin = Color3.fromRGB(216, 168, 144),
				hair = Color3.fromRGB(42, 30, 24),
				hairStyle = "curls",
				top = Color3.fromRGB(240, 238, 238),
				topStyle = "tank",
				bottom = Color3.fromRGB(12, 13, 18),
				bottomStyle = "track",
				stripe = Color3.fromRGB(255, 255, 255),
				socks = Color3.fromRGB(240, 240, 240),
				shoeColor = Color3.fromRGB(224, 80, 42),
				shoeAccent = Color3.fromRGB(250, 250, 250),
			},
		},
		Rack = {
			char = "Human",
			place = Config.place("Gym", 2.7, 4.6, 90),
			opts = {
				female = true,
				height = 0.97,
				build = 0.9,
				skin = Color3.fromRGB(234, 196, 176),
				hair = Color3.fromRGB(48, 32, 32),
				hairStyle = "bun",
				top = Color3.fromRGB(238, 232, 232),
				topStyle = "tee",
				bottom = Color3.fromRGB(24, 24, 28),
				bottomStyle = "leggings",
				shoes = "sneakers",
				shoeColor = Color3.fromRGB(30, 30, 34),
			},
		},
	},
	camera = {
		keys = {
			{ t = 11.1333, pos = Config.at("Gym", 0.25, 2.5, -8.6), look = Config.at("Gym", 0.53, 3.06, -0.6), fov = 58, ease = "linear" },
			{ t = 13.1333, pos = Config.at("Gym", 0.25, 2.5, -8.6), look = Config.at("Gym", 0.53, 3.06, -0.6), fov = 56.6 },
		},
		path = "linear",
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
