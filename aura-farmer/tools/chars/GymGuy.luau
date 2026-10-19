--!nocheck
-- Статист в спортзале (S10, на скамье/у зеркала на заднем плане): короткая тёмная стрижка, лёгкая щетина,
-- чёрная футболка, серые шорты, белые носки и кроссовки.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		skin = rgb(204, 148, 118),
		eyes = rgb(64, 46, 34),
		lips = rgb(170, 100, 92),
		hair = rgb(30, 22, 18),
		brows = rgb(32, 22, 18),
		browThick = 1.1,
		hairStyle = "crop",
		beard = rgb(120, 86, 70),
		top = rgb(30, 30, 34),
		topStyle = "tee",
		bottom = rgb(112, 114, 120),
		bottomStyle = "shorts",
		shoes = "sneakers",
		shoeColor = rgb(240, 240, 238),
		socks = rgb(240, 240, 238),
		build = 1.06,
		height = 1.03,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
