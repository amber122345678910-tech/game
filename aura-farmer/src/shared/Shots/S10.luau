--!strict
-- S10 (11.133–13.133 с): Спортзал с фиолетовым неоном: конь качает гантель 500 кг.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local HZ = -1.25 -- таз коня на переднем конце скамьи (сиденье z∈[-1.4,-0.18], верх Y=1.55)

return {
	id = "S10",
	start = 11.1333,
	finish = 13.1333,
	set = "Gym",
	preset = "Gym",
	actors = {
		Horse = { char = "Horse", place = Config.place("Gym", 0, HZ, 0), opts = { props = { "dumbbell" } } },
		-- рыжая (слева в кадре): у стойки +X, в профиль лицом к центру (−X), махи правой (ближней) ногой влево в кадре
		Ginger = { char = "GymWoman", place = Config.place("Gym", 6.3, 1.5, 92) },
		-- кудрявая (справа в кадре): у стойки −X, вполоборота к коню и к камере, махи правой ногой вправо в кадре
		Curly = { char = "GymGuy", place = Config.place("Gym", -6.0, 1.4, -65) },
		-- тёмноволосая за +X стойкой (видна между рыжей и конём, пояс скрыт стойкой)
		Rack = {
			char = "Human",
			place = Config.place("Gym", 5.0, 6.8, 160),
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
			{ t = 11.1333, pos = Config.at("Gym", 0.53, 2.1, -9.0), look = Config.at("Gym", 0.53, 3.43, -1.11), fov = 58, ease = "linear" },
			{ t = 13.1333, pos = Config.at("Gym", 0.53, 2.1, -9.0), look = Config.at("Gym", 0.53, 3.43, -1.11), fov = 56.6 },
		},
		path = "linear",
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
