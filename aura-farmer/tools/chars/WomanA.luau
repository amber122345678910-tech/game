--!nocheck
-- Девушка слева (S03, S07, S10): светло-русая «рваная» стрижка (шэг) с шторкой-чёлкой и осветлёнными прядями у лица,
-- белый кроп-топ в рубчик с высоким вырезом, чёрные широкие шорты до колена с контрастной строчкой и красными розами,
-- босиком; серебряные кольца-серьги, чёрный шнурок-чокер + серебряная цепочка с монеткой, браслеты, кольца;
-- красные «шестиугольные» очки с красными стёклами.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		female = true,
		skin = rgb(234, 170, 140),
		eyes = rgb(112, 104, 72),
		lips = rgb(196, 112, 106),
		lashes = true,
		browThick = 0.7,
		brows = rgb(122, 90, 66),
		nose = 0.88,
		hair = rgb(124, 90, 64),
		hairHighlight = rgb(222, 192, 142),
		hairStyle = "shag",
		top = rgb(244, 242, 238),
		topStyle = "crop",
		bottom = rgb(22, 22, 28),
		bottomStyle = "baggy",
		stitch = rgb(214, 212, 206),
		roses = rgb(176, 26, 32),
		shoes = "barefoot",
		earrings = "hoop",
		earringColor = rgb(214, 214, 220),
		necklaces = {
			{ kind = "cord", color = rgb(26, 24, 24), choker = true, pendant = true, pendantColor = rgb(200, 200, 206) },
			{ kind = "chain", color = rgb(206, 206, 212), len = 0.62, pendant = "coin" },
		},
		bracelets = { right = { rgb(210, 210, 216), rgb(196, 196, 204) }, left = { rgb(40, 32, 30) } },
		rings = rgb(210, 210, 216),
		glasses = "hex",
		glassesFrame = rgb(214, 36, 40),
		glassesLens = rgb(228, 40, 44),
		glassesLensTransparency = 0.3,
		build = 0.94,
		height = 0.97,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
