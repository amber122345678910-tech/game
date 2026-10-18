--!nocheck
-- Природа и декор из примитивов: деревья, ели, камни, кусты, цветы, трава, грибы, фонари, заборы.
-- Каждый объект слегка случайный (размер, наклон, оттенок), поэтому лес не выглядит копипастой.
local roblox = require("@lune/roblox")
local B = require("./builder")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material

local P = {}

local WOOD = B.rgb(110, 76, 52)
local WOOD_DARK = B.rgb(84, 58, 40)

-- Лиственное дерево: ствол-цилиндр, 2-3 ветки, крона из 4-6 шаров разного оттенка
function P.tree(parent, pos, rng, palette, scale)
	local s = scale or rng:range(0.85, 1.25)
	local m = B.model(parent, "Tree")
	local trunkH = 9 * s
	local trunkD = 1.6 * s
	local lean = CFrame.Angles(rng:range(-0.05, 0.05), 0, rng:range(-0.05, 0.05))
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0) * lean
	B.cyl(m, base * CFrame.new(0, trunkH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), trunkH, trunkD, B.vary(WOOD, rng, 0.04), { Material = M.Wood })
	-- корни
	for i = 1, 3 do
		local a = i * 2.1 + rng:range(-0.3, 0.3)
		local root = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.5 * s, trunkD * 0.55) * CFrame.Angles(-0.6, 0, 0)
		B.block(m, root, Vector3.new(0.7 * s, 0.8 * s, 1.8 * s), WOOD_DARK, B.deco({ Material = M.Wood, Shadow = false }))
	end
	-- ветки
	local leaves = palette.leaves
	local top = base * CFrame.new(0, trunkH, 0)
	for i = 1, 2 do
		local a = rng:range(0, math.pi * 2)
		local br = base * CFrame.new(0, trunkH * rng:range(0.55, 0.75), 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, 0.9)
		B.cyl(m, br * CFrame.new(1.6 * s, 0, 0), 3.2 * s, 0.7 * s, WOOD, B.deco({ Material = M.Wood }))
		local tip = br * CFrame.new(3.2 * s, 0, 0)
		B.ball(m, tip.Position + Vector3.new(0, 0.8 * s, 0), rng:range(3.5, 4.5) * s, B.vary(rng:pick(leaves), rng, 0.05), B.deco({ Material = M.Grass, Shadow = true }))
	end
	-- крона
	local n = rng:int(4, 6)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:range(-0.4, 0.4)
		local r = rng:range(1.5, 2.8) * s
		local off = Vector3.new(math.cos(a) * r, rng:range(-0.5, 2.2) * s, math.sin(a) * r)
		B.ball(m, top.Position + off, rng:range(5, 7) * s, B.vary(rng:pick(leaves), rng, 0.06), B.deco({ Material = M.Grass, Shadow = true }))
	end
	B.ball(m, top.Position + Vector3.new(0, 2.8 * s, 0), 6.5 * s, B.vary(leaves[1], rng, 0.04), B.deco({ Material = M.Grass, Shadow = true }))
	-- ствол с коллизией (чтобы не проходить сквозь)
	return m
end

-- Ель: ствол и 4-5 ярусов конусов из клиньев (по 4 клина на ярус)
function P.pine(parent, pos, rng, palette, scale)
	local s = scale or rng:range(0.8, 1.3)
	local m = B.model(parent, "Pine")
	local h = 4 * s
	B.cylY(m, pos + Vector3.new(0, h / 2, 0), h, 1.3 * s, WOOD_DARK, { Material = M.Wood })
	local tiers = rng:int(4, 5)
	local rot = rng:range(0, math.pi / 2)
	local y = h - 0.5 * s
	for t = 1, tiers do
		local k = 1 - (t - 1) / tiers
		local w = (9 * k + 2) * s
		local th = 4.2 * s
		local col = B.vary(palette.pine[((t - 1) % #palette.pine) + 1], rng, 0.04)
		for q = 0, 3 do
			local cf = CFrame.new(pos + Vector3.new(0, y + th / 2, 0)) * CFrame.Angles(0, rot + q * math.pi / 2, 0) * CFrame.new(0, 0, -w / 4)
			B.wedge(m, cf, Vector3.new(w, th, w / 2), col, B.deco({ Material = M.Grass, Shadow = true }))
		end
		y += th * 0.62
	end
	if palette.snowy then
		B.ball(m, pos + Vector3.new(0, y + 0.6 * s, 0), 1.6 * s, B.rgb(245, 248, 255), B.deco({ Material = M.Snow }))
	end
	return m
end

-- Камень: 2-4 повёрнутых блока разного размера
function P.rock(parent, pos, rng, palette, scale)
	local s = scale or rng:range(0.6, 1.6)
	local m = B.model(parent, "Rock")
	local n = rng:int(2, 4)
	local col = palette.rock or B.rgb(128, 128, 136)
	for i = 1, n do
		local size = Vector3.new(rng:range(2, 4), rng:range(1.5, 3), rng:range(2, 4)) * s * (if i == 1 then 1.2 else rng:range(0.5, 0.9))
		local off = if i == 1 then Vector3.zero else Vector3.new(rng:range(-1.5, 1.5) * s, 0, rng:range(-1.5, 1.5) * s)
		local cf = CFrame.new(pos + off + Vector3.new(0, size.Y * 0.32, 0))
			* CFrame.Angles(rng:range(-0.35, 0.35), rng:range(0, math.pi), rng:range(-0.35, 0.35))
		B.block(m, cf, size, B.vary(col, rng, 0.05), { Material = palette.rockMaterial or M.Slate, Collide = i == 1 })
	end
	-- мох сверху
	if palette.moss and rng:chance(0.5) then
		B.block(m, CFrame.new(pos + Vector3.new(0, 1.9 * s, 0)) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(2.4, 0.3, 2) * s, palette.moss, B.deco({ Material = M.Grass, Shadow = false }))
	end
	return m
end

-- Куст: 3-5 шаров
function P.bush(parent, pos, rng, palette, scale)
	local s = scale or rng:range(0.7, 1.3)
	local m = B.model(parent, "Bush")
	local n = rng:int(3, 5)
	for i = 1, n do
		local off = Vector3.new(rng:range(-1.4, 1.4), rng:range(0.6, 1.4), rng:range(-1.4, 1.4)) * s
		B.ball(m, pos + off, rng:range(2.2, 3.4) * s, B.vary(rng:pick(palette.leaves), rng, 0.07), B.deco({ Material = M.Grass, Shadow = false }))
	end
	if palette.berries and rng:chance(0.6) then
		for _ = 1, rng:int(3, 6) do
			local off = Vector3.new(rng:range(-1.6, 1.6), rng:range(1, 2.2), rng:range(-1.6, 1.6)) * s
			B.ball(m, pos + off, 0.45, palette.berries, B.deco({ Material = M.SmoothPlastic, Shadow = false }))
		end
	end
	return m
end

-- Цветок: стебель + 5 лепестков + серединка
function P.flower(parent, pos, rng, color, scale)
	local s = scale or rng:range(0.8, 1.2)
	local h = rng:range(0.9, 1.6) * s
	B.block(parent, CFrame.new(pos + Vector3.new(0, h / 2, 0)), Vector3.new(0.15, h, 0.15), B.rgb(70, 140, 60), B.deco({ Shadow = false }))
	local top = pos + Vector3.new(0, h, 0)
	local rot = rng:range(0, math.pi)
	for i = 0, 4 do
		local a = rot + i * math.pi * 2 / 5
		local cf = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.32 * s) * CFrame.Angles(0.35, 0, 0)
		B.block(parent, cf, Vector3.new(0.38, 0.1, 0.55) * s, color, B.deco({ Shadow = false }))
	end
	B.ball(parent, top + Vector3.new(0, 0.06, 0), 0.32 * s, B.rgb(255, 214, 80), B.deco({ Shadow = false }))
end

-- Пучок травы: 3 тонких наклонённых клина
function P.grass(parent, pos, rng, color)
	for i = 0, 2 do
		local h = rng:range(0.8, 1.5)
		local cf = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, i * 2.1 + rng:range(-0.3, 0.3), 0) * CFrame.Angles(rng:range(0.1, 0.35), 0, 0)
		B.wedge(parent, cf, Vector3.new(0.12, h, 0.35), B.vary(color, rng, 0.06), B.deco({ Shadow = false, Material = M.Grass }))
	end
end

-- Гриб: ножка + шляпка-полушар (шар, утопленный в диск)
function P.mushroom(parent, pos, rng, capColor, scale)
	local s = scale or rng:range(0.6, 1.4)
	local m = B.model(parent, "Mushroom")
	B.cylY(m, pos + Vector3.new(0, 0.7 * s, 0), 1.4 * s, 0.55 * s, B.rgb(240, 232, 214), B.deco({ Shadow = false }))
	B.ball(m, pos + Vector3.new(0, 1.45 * s, 0), 1.9 * s, capColor, B.deco({ Shadow = false }))
	B.cylY(m, pos + Vector3.new(0, 1.15 * s, 0), 0.5 * s, 1.95 * s, B.rgb(235, 225, 205), B.deco({ Shadow = false }))
	for _ = 1, 3 do
		local a = rng:range(0, math.pi * 2)
		B.ball(m, pos + Vector3.new(math.cos(a) * 0.55 * s, 2.15 * s, math.sin(a) * 0.55 * s), 0.35 * s, B.rgb(255, 255, 255), B.deco({ Shadow = false }))
	end
	return m
end

-- Фонарь на столбе с тёплым светом
function P.lamp(parent, pos, rng, glowColor, height)
	local m = B.model(parent, "Lamp")
	local h = height or 9
	local pole = B.rgb(45, 45, 52)
	B.cylY(m, pos + Vector3.new(0, 0.3, 0), 0.6, 1.4, pole, { Material = M.Metal })
	B.cylY(m, pos + Vector3.new(0, h / 2, 0), h, 0.45, pole, { Material = M.Metal })
	B.block(m, CFrame.new(pos + Vector3.new(0, h + 0.15, 0)), Vector3.new(1.6, 0.3, 1.6), pole, B.deco({ Material = M.Metal }))
	local glow = B.block(m, CFrame.new(pos + Vector3.new(0, h + 1, 0)), Vector3.new(1.1, 1.4, 1.1), glowColor, B.deco({ Material = M.Neon, Shadow = false }))
	B.wedge(m, CFrame.new(pos + Vector3.new(0, h + 2, 0.45)) * CFrame.Angles(0, math.pi, 0), Vector3.new(1.7, 0.6, 0.9), pole, B.deco({ Material = M.Metal }))
	B.wedge(m, CFrame.new(pos + Vector3.new(0, h + 2, -0.45)), Vector3.new(1.7, 0.6, 0.9), pole, B.deco({ Material = M.Metal }))
	B.light(glow, glowColor, 22, 1.3, false)
	return m
end

-- Забор между двумя точками: столбики и 2 перекладины
function P.fence(parent, a, b, color)
	local m = B.model(parent, "Fence")
	local dir = (b - a)
	local len = dir.Magnitude
	local n = math.max(1, math.floor(len / 6))
	for i = 0, n do
		local p = a + dir * (i / n)
		B.block(m, CFrame.new(p + Vector3.new(0, 1.6, 0)), Vector3.new(0.6, 3.2, 0.6), color, { Material = M.Wood })
		B.wedge(m, CFrame.lookAt(p + Vector3.new(0, 3.45, 0), p + Vector3.new(0, 3.45, 0) + dir.Unit), Vector3.new(0.6, 0.5, 0.6), color, B.deco({ Material = M.Wood }))
	end
	for _, y in { 1.1, 2.4 } do
		B.slab(m, a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.3, 0.45, WOOD, { Material = M.Wood })
	end
	return m
end

return P
