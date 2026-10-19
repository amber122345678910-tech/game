--!nocheck
-- Конь-Аурафармер: детальная модель вокруг замороженного скелета HorseSkeleton.
-- opts:
--   glasses  = "amber" (по умолчанию) | "yellow"     — цвет линз авиаторов
--   props    = { "dumbbell" }                          — гантель «500 KG» на суставе Dumbbell (правая кисть)
--   sparkles = true                                     — включить золотые искры ауры (эмиттер AuraSparkles)
-- Всегда есть (выключены): эмиттеры ChainSparkles (цепь), BuckleGlint (вершина «A»), AuraSparkles (тело),
-- деталь BuckleFlare (белый Neon, Transparency 1) у вершины «A» — для твинов.
local roblox = require("@lune/roblox")
local V = roblox.Vector3.new

local Skel = require("./HorseSkeleton")
local Geo = require("./HorseParts/Geo")
local Head = require("./HorseParts/Head")
local Glasses = require("./HorseParts/Glasses")
local Body = require("./HorseParts/Body")
local Limbs = require("./HorseParts/Limbs")
local Props = require("./HorseParts/Props")

return function(opts)
	opts = opts or {}
	local rig = Skel.new("Horse")
	local g = Geo.new(rig)
	Head.build(g, opts)
	Glasses.build(g, opts)
	Body.build(g, opts)
	Limbs.build(g, opts)
	for _, p in opts.props or {} do
		if p == "dumbbell" then
			local S = rig.P
			local wristY = S.shoulderY - S.upperArm - S.lowerArm
			Props.dumbbell(g, V(S.shoulderX - 0.1, wristY - S.handLen - 0.12, 0))
		end
	end
	return rig
end
