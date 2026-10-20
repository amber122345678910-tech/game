--!nocheck
-- Статистка в спортзале (S10): девушка у стойки с гантелями / её отражение в зеркале. По кадру это та же
-- девушка, что WomanA (шэг с чёлкой, белый кроп-топ в рубчик, чёрные широкие шорты с розами, босиком),
-- в тёплом свете зала волосы кажутся рыжеватыми; без очков. opts поверх (например, hair для «отражения»).
local roblox = require("@lune/roblox")
local Color3 = roblox.Color3
local WomanA = require("./WomanA")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

return function(opts)
	local o = {
		glasses = false,
		hair = rgb(132, 78, 54),
		hairHighlight = rgb(196, 140, 96),
		earrings = "hoop",
		necklaces = {
			{ kind = "chain", color = rgb(206, 206, 212), len = 0.58, pendant = "coin" },
		},
	}
	for k, v in opts or {} do
		o[k] = v
	end
	return WomanA(o)
end
