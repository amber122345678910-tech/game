--!nocheck
-- Парень с пляжа (S01, S03): тёмный зачёс-кок с короткими висками, щетина и усы, густые тёмные брови,
-- белая майка с глубокими проймами, тонкий красно-оранжевый шнурок на шее, золотые авиаторы с тёмно-зелёными стёклами.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		skin = rgb(232, 180, 156),
		eyes = rgb(92, 120, 134),
		lips = rgb(184, 112, 104),
		hair = rgb(34, 24, 20),
		brows = rgb(40, 28, 22),
		browThick = 1.25,
		hairStyle = "quiff",
		beard = rgb(112, 82, 68),
		top = rgb(244, 243, 239),
		topStyle = "tank",
		scoop = 0.55,
		bottom = rgb(44, 52, 72),
		bottomStyle = "shorts",
		shoes = "sneakers",
		shoeColor = rgb(240, 240, 238),
		necklaces = { { kind = "cord", color = rgb(204, 74, 40), len = 0.62 } },
		glasses = "aviator",
		glassesFrame = rgb(206, 170, 96),
		glassesLens = rgb(28, 50, 38),
		glassesLensTransparency = 0.08,
		build = 1.04,
		height = 1.04,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
