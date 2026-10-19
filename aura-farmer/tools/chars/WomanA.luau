--!nocheck
-- Девушка слева (S03, S07): светло-русое каре с чёлкой, белый кроп-топ, тёмные штаны.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

return function(opts)
	local o = {
		skin = Color3.fromRGB(238, 200, 172),
		hair = Color3.fromRGB(150, 116, 82),
		hairStyle = "bob",
		top = Color3.fromRGB(248, 248, 246),
		topStyle = "crop",
		bottom = Color3.fromRGB(26, 26, 30),
		bottomLong = true,
		bottomStripe = Color3.fromRGB(200, 40, 40),
		glasses = "round",
		glassesFrame = Color3.fromRGB(200, 40, 40),
		glassesLens = Color3.fromRGB(150, 30, 30),
		female = true,
		build = 0.9,
		height = 0.97,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
