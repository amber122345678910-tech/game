--!nocheck
-- Парень с пляжа (S01, S03): короткие тёмные волосы, щетина, белая майка, авиаторы.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

return function(opts)
	local o = {
		skin = Color3.fromRGB(232, 186, 156),
		hair = Color3.fromRGB(58, 40, 30),
		hairStyle = "short",
		beard = Color3.fromRGB(120, 90, 72),
		top = Color3.fromRGB(246, 246, 244),
		bottom = Color3.fromRGB(32, 34, 40),
		glasses = "aviator",
		build = 1.05,
		height = 1.04,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
