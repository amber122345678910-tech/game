--!nocheck
-- Девушка справа (S03, S07, S10): тёмные короткие кудри, белая майка в рубчик с круглым вырезом,
-- чёрные спортивные шорты с тремя белыми лампасами, белые носки, оранжевые кроссовки с белой полосой;
-- золотая цепочка с подвеской, серебряный браслет, маленькие серьги; красные прямоугольные очки.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		female = true,
		skin = rgb(206, 146, 116),
		eyes = rgb(66, 44, 32),
		lips = rgb(170, 94, 84),
		lashes = true,
		browThick = 0.95,
		brows = rgb(30, 22, 18),
		nose = 0.95,
		hair = rgb(34, 25, 22),
		hairStyle = "curls",
		top = rgb(244, 243, 240),
		topStyle = "tank",
		scoop = 0.5,
		bottom = rgb(20, 20, 24),
		bottomStyle = "track",
		stripe = rgb(242, 242, 240),
		shoes = "sneakers",
		shoeColor = rgb(226, 84, 30),
		shoeAccent = rgb(246, 244, 240),
		sole = rgb(240, 236, 228),
		socks = rgb(242, 240, 236),
		earrings = "stud",
		earringColor = rgb(222, 184, 96),
		necklaces = { { kind = "chain", color = rgb(222, 184, 96), len = 0.52, pendant = "drop" } },
		bracelets = { left = { rgb(206, 206, 212) } },
		glasses = "rect",
		glassesFrame = rgb(220, 38, 36),
		glassesLens = rgb(232, 46, 46),
		glassesLensTransparency = 0.3,
		build = 0.96,
		height = 0.98,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
