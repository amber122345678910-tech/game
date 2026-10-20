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
	-- зал в клипе светлый (стены почти «в белое»), конь читается тёплым мех-коричневым: чуть больше
	-- заполняющего света (сиреневый «отскок» от стен) и экспозиции
	lighting = {
		lighting = {
			Ambient = Color3.fromRGB(62, 50, 78),
			OutdoorAmbient = Color3.fromRGB(54, 44, 70),
			ExposureCompensation = 0.4,
		},
		-- грейд клипа: фиолетово-маджентовый оттенок в светах и полутонах
		cc = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.18, TintColor = Color3.fromRGB(244, 228, 255) },
		-- глубокая резкость: статисты в 8–15 студах лишь чуть мягче коня
		dof = { FarIntensity = 0.12, InFocusRadius = 10 },
	},
	actors = {
		Horse = { char = "Horse", place = Config.place("Gym", 0, HZ, 0), opts = { props = { "dumbbell" } } },
		-- рыжая (слева в кадре): у стойки +X, в профиль лицом к центру (−X), махи правой (ближней) ногой влево в кадре
		Ginger = { char = "GymWoman", place = Config.place("Gym", 4.9, 0.6, 92) },
		-- кудрявая (справа в кадре): у стойки −X, почти в профиль лицом к коню, махи левой (ближней) ногой вправо в кадре
		Curly = { char = "GymGuy", place = Config.place("Gym", -5.6, 0.8, -80) },
		-- тёмноволосая за +X стойкой (видна между рыжей и конём, пояс скрыт стойкой)
		Rack = {
			char = "Human",
			place = Config.place("Gym", 6.6, 7.2, 30),
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
			{ t = 11.1333, pos = Config.at("Gym", 0.75, 2.1, -9.0), look = Config.at("Gym", 0.75, 3.45, -1.11), fov = 58, ease = "linear" },
			{ t = 13.1333, pos = Config.at("Gym", 0.75, 2.1, -9.0), look = Config.at("Gym", 0.75, 3.45, -1.11), fov = 56.6 },
		},
		path = "linear",
		focus = { actor = "Horse", part = "Head" },
	},
	-- В клипе нет вспышек/тряски/переходов; размытие движения только на гантели и ногах (полноэкранный Blur
	-- размыл бы и морду — не используем). Золото ловит блики ключевого света, когда корпус выпрямляется
	-- на верх подъёма: короткие искры на цепи в верхних стоп-позах (доли 23 и 25).
	-- (одиночные emit, а не enable: два enable-события одного эмиттера перебивают друг друга)
	effects = {
		{ t = 11.64, kind = "emit", name = "ChainSparkles", count = 1 },
		{ t = 11.71, kind = "emit", name = "ChainSparkles", count = 1 },
		{ t = 11.78, kind = "emit", name = "ChainSparkles", count = 1 },
		{ t = 12.62, kind = "emit", name = "ChainSparkles", count = 1 },
		{ t = 12.69, kind = "emit", name = "ChainSparkles", count = 1 },
		{ t = 12.76, kind = "emit", name = "ChainSparkles", count = 1 },
	},
}
