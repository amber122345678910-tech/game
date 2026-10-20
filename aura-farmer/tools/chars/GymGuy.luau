--!nocheck
-- Статист в спортзале (S10, на заднем плане за конём / у зеркала): короткие тёмные кудри, белая майка,
-- чёрные спортивные шорты с белыми лампасами, белые носки и кроссовки. Собран на Human.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		skin = rgb(204, 140, 104),
		rosy = 0.2,
		eyes = rgb(64, 46, 34),
		lips = rgb(170, 100, 92),
		hair = rgb(34, 24, 20),
		brows = rgb(32, 22, 18),
		browThick = 1.1,
		hairStyle = "curls",
		beard = rgb(70, 50, 40),
		beardAmount = 0.3,
		top = rgb(240, 239, 236),
		topStyle = "tank",
		scoop = 0.45,
		bottom = rgb(20, 20, 24),
		bottomStyle = "track",
		stripe = rgb(242, 242, 240),
		shoes = "sneakers",
		shoeColor = rgb(240, 240, 238),
		socks = rgb(240, 240, 238),
		build = 1.0,
		height = 1.02,
		armW = 0.58,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
