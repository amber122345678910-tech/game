--!nocheck
-- Девушка справа (S03, S07): тёмные кудри, белая майка, чёрные шорты с белыми лампасами, красные очки.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

return function(opts)
	local o = {
		skin = Color3.fromRGB(226, 182, 150),
		hair = Color3.fromRGB(40, 28, 22),
		hairStyle = "curly",
		top = Color3.fromRGB(246, 246, 244),
		bottom = Color3.fromRGB(22, 22, 26),
		bottomStripe = Color3.fromRGB(245, 245, 245),
		shoes = Color3.fromRGB(236, 90, 40),
		glasses = "aviator",
		glassesFrame = Color3.fromRGB(210, 40, 40),
		glassesLens = Color3.fromRGB(170, 30, 30),
		female = true,
		build = 0.92,
		height = 0.98,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
