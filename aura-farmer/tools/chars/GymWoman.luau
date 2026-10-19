--!nocheck
-- Статистка в спортзале (S10, на заднем плане у стойки с гантелями): тёмные волосы в пучке,
-- белый кроп-топ, чёрные леггинсы, белые кроссовки, маленькие серьги.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		female = true,
		skin = rgb(220, 166, 138),
		eyes = rgb(70, 50, 36),
		lips = rgb(186, 104, 98),
		lashes = true,
		browThick = 0.8,
		brows = rgb(48, 32, 26),
		nose = 0.9,
		hair = rgb(54, 36, 28),
		hairStyle = "bun",
		top = rgb(242, 241, 238),
		topStyle = "crop",
		bottom = rgb(26, 26, 30),
		bottomStyle = "leggings",
		shoes = "sneakers",
		shoeColor = rgb(236, 236, 234),
		earrings = "stud",
		earringColor = rgb(214, 214, 220),
		build = 0.92,
		height = 0.96,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
