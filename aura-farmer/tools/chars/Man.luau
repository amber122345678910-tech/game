--!nocheck
-- Парень с пляжа (S01, S03): тёмный зачёс-кок (помпадур) с короткими висками, короткая густая борода-щетина
-- по челюсти и щекам + усы, густые тёмные брови, светлая кожа с солнечным румянцем, худощавые руки,
-- белая майка с глубокими проймами, тонкий красно-оранжевый шнурок на шее, золотые авиаторы с тёмно-зелёными стёклами.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		skin = rgb(238, 196, 176),
		rosy = 0.55,
		eyes = rgb(92, 120, 134),
		lips = rgb(184, 112, 104),
		hair = rgb(56, 38, 28),
		brows = rgb(38, 26, 20),
		browThick = 1.25,
		hairStyle = "quiff",
		beard = rgb(56, 38, 30),
		beardAmount = 0.72,
		top = rgb(244, 243, 239),
		topStyle = "tank",
		scoop = 0.55,
		bottom = rgb(44, 52, 72),
		bottomStyle = "shorts",
		shoes = "sneakers",
		shoeColor = rgb(240, 240, 238),
		necklaces = { { kind = "cord", color = rgb(196, 70, 40), len = 0.5, thin = true } },
		glasses = "aviator",
		glassesFrame = rgb(206, 170, 96),
		glassesLens = rgb(20, 38, 28),
		glassesLensTransparency = 0,
		build = 1.04,
		armW = 0.46, -- худощавые руки (как в клипе)
		torsoW = 1.75, -- узкая грудь (×build ≈ 1.82)
		legW = 0.76,
		height = 1.04,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
