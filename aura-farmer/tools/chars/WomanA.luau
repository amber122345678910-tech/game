--!nocheck
-- Девушка слева (S03, S07, S10): каштановый «шэг» до плеч с густой чёлкой до бровей и светлыми прядями у лица
-- справа и на концах; белый кроп-топ в рубчик с высоким круглым вырезом, чёрные широкие шорты до колена
-- с контрастной строчкой и красными розами, босиком; серебряные кольца-серьги, чёрный шнурок-чокер + серебряная
-- цепочка с монеткой, браслеты, кольца; красные овальные очки с красными стёклами. Тёплая светлая кожа.
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local Human = require("./Human")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		female = true,
		skin = rgb(240, 198, 176),
		rosy = 0.35,
		eyes = rgb(112, 104, 72),
		lips = rgb(196, 112, 106),
		lashes = true,
		browThick = 0.7,
		brows = rgb(122, 90, 66),
		nose = 0.88,
		hair = rgb(108, 72, 50),
		hairHighlight = rgb(214, 180, 130),
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
		glasses = "round",
		glassesFrame = rgb(214, 36, 40),
		glassesLens = rgb(200, 24, 30),
		glassesLensTransparency = 0.15,
		armW = 0.4,
		build = 0.94,
		height = 0.97,
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return Human(o)
end
