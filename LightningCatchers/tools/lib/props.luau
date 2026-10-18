--!nocheck
-- Природа и декор из примитивов: деревья, ели, камни, кусты, цветы, трава, кактусы, стеклянные шипы,
-- трубы, руины, базальт, кристаллы, фонари, скамейки, клумбы, заборы.
-- Каждый объект слегка случайный (размер, наклон, оттенок), поэтому лес не выглядит копипастой.
-- Детали экономные (телефоны): дерево ~8 деталей, ель ~10, цветок 2.
local roblox = require("@lune/roblox")
local B = require("./builder")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material
local rgb = B.rgb

local P = {}

P.WOOD = B.rgb(116, 80, 54)
P.WOOD_DARK = B.rgb(86, 60, 42)
P.IRON = B.rgb(52, 54, 64)

local function yaw(rng)
	return CFrame.Angles(0, rng:range(0, math.pi * 2), 0)
end

----------------------------------------------------------------------
-- Растения
----------------------------------------------------------------------

-- Лиственное дерево: ствол, ветка, крона из 4-5 шаров разного оттенка. pal.leaves = {Color3...}
function P.tree(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.85, 1.25)
	local m = B.model(parent, "Tree")
	local trunkH = 8 * s
	local base = CFrame.new(pos) * yaw(rng) * CFrame.Angles(rng:range(-0.05, 0.05), 0, rng:range(-0.05, 0.05))
	local wood = pal.wood or P.WOOD
	-- ствол (с коллизией — сквозь дерево не пройти)
	B.cyl(m, base * CFrame.new(0, trunkH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), trunkH, 1.5 * s, B.vary(wood, rng, 0.04), { Material = M.Wood, Shadow = true })
	-- ветка
	local br = base * CFrame.new(0, trunkH * 0.6, 0) * CFrame.Angles(0, rng:range(0, 6.28), 0) * CFrame.Angles(0, 0, 0.85)
	B.cyl(m, br * CFrame.new(1.5 * s, 0, 0), 3 * s, 0.6 * s, wood, B.deco({ Material = M.Wood }))
	local tip = (br * CFrame.new(3 * s, 0, 0)).Position
	B.ball(m, tip + Vector3.new(0, 0.6 * s, 0), rng:range(3.4, 4.2) * s, B.vary(B.shade(pal.leaves[1], 0.12), rng, 0.05), B.deco({ Material = M.Grass, Shadow = true }))
	-- крона: нижние шары темнее (тень со сдвигом оттенка), верхние светлее
	local top = (base * CFrame.new(0, trunkH, 0)).Position
	local n = rng:int(3, 4)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:range(-0.4, 0.4)
		local r = rng:range(1.6, 2.6) * s
		local off = Vector3.new(math.cos(a) * r, rng:range(-0.6, 1.2) * s, math.sin(a) * r)
		local col = B.vary(B.shade(rng:pick(pal.leaves), 0.1), rng, 0.05)
		B.ball(m, top + off, rng:range(5, 6.5) * s, col, B.deco({ Material = M.Grass, Shadow = true }))
	end
	B.ball(m, top + Vector3.new(rng:range(-0.5, 0.5), 2.6 * s, rng:range(-0.5, 0.5)), 6 * s, B.vary(B.tint(pal.leaves[#pal.leaves], 0.06), rng, 0.04), B.deco({ Material = M.Grass, Shadow = true }))
	if pal.fruit and rng:chance(0.6) then
		for _ = 1, 3 do
			local a = rng:range(0, 6.28)
			B.ball(m, top + Vector3.new(math.cos(a) * 3.2 * s, rng:range(-0.8, 1.5) * s, math.sin(a) * 3.2 * s), 0.7 * s, pal.fruit, B.deco({ Shadow = false }))
		end
	end
	return m
end

-- Сухое/голое дерево (Медные Холмы): изогнутый ствол и 3-4 корявые ветки
function P.deadTree(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.2)
	local m = B.model(parent, "DeadTree")
	local wood = pal.wood or B.rgb(96, 70, 56)
	local a = pos
	local b = pos + Vector3.new(rng:range(-1, 1), 5 * s, rng:range(-1, 1))
	local c = b + Vector3.new(rng:range(-1.5, 1.5), 3.5 * s, rng:range(-1.5, 1.5))
	B.rod(m, a, b + Vector3.new(0, 0.3, 0), 1.3 * s, B.vary(wood, rng, 0.04), { Material = M.Wood, Shadow = true })
	B.rod(m, b, c, 0.9 * s, B.vary(wood, rng, 0.04), B.deco({ Material = M.Wood, Shadow = true }))
	for _ = 1, rng:int(3, 4) do
		local from = b:Lerp(c, rng:range(0, 1))
		local ang = rng:range(0, 6.28)
		local to = from + Vector3.new(math.cos(ang) * 3 * s, rng:range(1, 3) * s, math.sin(ang) * 3 * s)
		B.rod(m, from, to, 0.45 * s, B.vary(wood, rng, 0.05), B.deco({ Material = M.Wood }))
	end
	if pal.leaves and rng:chance(0.7) then
		B.ball(m, c + Vector3.new(0, 0.8, 0), 3.2 * s, B.vary(rng:pick(pal.leaves), rng, 0.05), B.deco({ Material = M.Grass }))
	end
	return m
end

-- Ель: ствол и ярусы-«пирамиды» из 4 клиньев. pal.pine = {Color3...}, pal.snowy = true — снежные шапки
function P.pine(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.3)
	local m = B.model(parent, "Pine")
	local h = 3 * s
	B.cylY(m, pos + Vector3.new(0, h / 2, 0), h, 1.2 * s, P.WOOD_DARK, { Material = M.Wood, Shadow = true })
	local tiers = if s > 1.05 then 3 else 2
	local rot = rng:range(0, math.pi / 2)
	local y = h - 0.6 * s
	for t = 1, tiers do
		local k = 1 - (t - 1) / (tiers + 0.6)
		local w = (9.5 * k + 1.5) * s
		local th = 5 * s * k + 1.5 * s
		local col = B.vary(pal.pine[((t - 1) % #pal.pine) + 1], rng, 0.035)
		if t == tiers then
			col = B.tint(col, 0.05)
		end
		for q = 0, 3 do
			local cf = CFrame.new(pos + Vector3.new(0, y + th / 2, 0)) * CFrame.Angles(0, rot + q * math.pi / 2, 0) * CFrame.new(0, 0, -w / 4)
			B.wedge(m, cf, Vector3.new(w, th, w / 2), col, B.deco({ Material = pal.pineMaterial or M.Grass, Shadow = t == 1 }))
		end
		if pal.snowy and t < tiers then
			-- снег на «полке» яруса
			B.cylY(m, pos + Vector3.new(0, y + th * 0.55, 0), 0.5 * s, w * 0.55, B.rgb(240, 245, 255), B.deco({ Material = M.Snow, Shadow = false }))
		end
		y += th * 0.62
	end
	if pal.snowy then
		B.ball(m, pos + Vector3.new(0, y + 1.1 * s, 0), 1.9 * s, B.rgb(246, 249, 255), B.deco({ Material = M.Snow }))
	end
	return m
end

-- Куст: 3 шара; pal.berries — ягоды
function P.bush(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.7, 1.3)
	local m = B.model(parent, "Bush")
	for i = 1, 3 do
		local off = Vector3.new(rng:range(-1.3, 1.3), rng:range(0.5, 1.2), rng:range(-1.3, 1.3)) * s
		local col = rng:pick(pal.leaves)
		if i == 1 then
			col = B.shade(col, 0.12)
		end
		B.ball(m, pos + off, rng:range(2.4, 3.4) * s, B.vary(col, rng, 0.06), B.deco({ Material = M.Grass, Shadow = false }))
	end
	if pal.berries and rng:chance(0.5) then
		for _ = 1, 3 do
			local off = Vector3.new(rng:range(-1.4, 1.4), rng:range(1.2, 2.2), rng:range(-1.4, 1.4)) * s
			B.ball(m, pos + off, 0.5, pal.berries, B.deco({ Shadow = false }))
		end
	end
	return m
end

-- Цветок (2 детали): стебель и головка. Без коллизий — можно ставить в игровой зоне.
function P.flower(parent, pos, rng, color, scale)
	local s = scale or rng:range(0.8, 1.2)
	local h = rng:range(0.9, 1.5) * s
	local lean = CFrame.Angles(rng:range(-0.15, 0.15), 0, rng:range(-0.15, 0.15))
	local stem = CFrame.new(pos) * lean * CFrame.new(0, h / 2, 0)
	B.block(parent, stem, Vector3.new(0.14, h, 0.14), B.rgb(72, 140, 62), B.deco({ Shadow = false }))
	local head = (CFrame.new(pos) * lean * CFrame.new(0, h, 0)).Position
	B.ball(parent, head, rng:range(0.55, 0.75) * s, B.vary(color, rng, 0.05), B.deco({ Shadow = false, Material = M.SmoothPlastic }))
end

-- Полянка цветов: n цветков в кружке радиуса r (не по сетке)
function P.flowerPatch(parent, pos, rng, colors, n: number?, r: number?)
	local count = n or rng:int(4, 7)
	local rad = r or 2.5
	local main = rng:pick(colors)
	for _ = 1, count do
		local c = if rng:chance(0.7) then main else rng:pick(colors)
		P.flower(parent, pos + rng:disc(rad), rng, c)
	end
end

-- Пучок травы: 2 тонких наклонённых клина
function P.tuft(parent, pos, rng, color, scale)
	local s = scale or 1
	for i = 0, 1 do
		local h = rng:range(0.8, 1.5) * s
		local cf = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, i * 1.9 + rng:range(-0.4, 0.4), 0) * CFrame.Angles(rng:range(0.1, 0.35), 0, 0)
		B.wedge(parent, cf, Vector3.new(0.14, h, 0.4) * Vector3.new(1, 1, s), B.vary(color, rng, 0.06), B.deco({ Shadow = false, Material = M.Grass }))
	end
end

-- Гриб: ножка + шляпка (шар, утопленный в диск); glow — светящаяся шляпка
function P.mushroom(parent, pos, rng, capColor, scale, glow)
	local s = scale or rng:range(0.6, 1.4)
	local m = B.model(parent, "Mushroom")
	B.cylY(m, pos + Vector3.new(0, 0.7 * s, 0), 1.4 * s, 0.55 * s, B.rgb(240, 232, 214), B.deco({ Shadow = false }))
	local cap = B.ball(m, pos + Vector3.new(0, 1.45 * s, 0), 1.9 * s, capColor, B.deco({ Shadow = false, Material = if glow then M.Neon else M.SmoothPlastic }))
	B.cylY(m, pos + Vector3.new(0, 1.15 * s, 0), 0.5 * s, 1.95 * s, B.rgb(235, 225, 205), B.deco({ Shadow = false }))
	if glow then
		B.light(cap, capColor, 10, 0.6)
	end
	return m
end

-- Кактус-сагуаро: ствол, верхушка-шар, 1-2 «руки»
function P.cactus(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.7, 1.3)
	local m = B.model(parent, "Cactus")
	local col = B.vary(pal.cactus or B.rgb(88, 140, 78), rng, 0.05)
	local h = rng:range(5, 7.5) * s
	local d = 1.6 * s
	B.cylY(m, pos + Vector3.new(0, h / 2, 0), h, d, col, { Material = M.Grass, Shadow = true })
	B.ball(m, pos + Vector3.new(0, h, 0), d, col, B.deco({ Material = M.Grass }))
	local ang = rng:range(0, 6.28)
	for i = 1, rng:int(1, 2) do
		local a = ang + (i - 1) * math.pi + rng:range(-0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local y = h * rng:range(0.35, 0.6)
		local armLen = rng:range(1.6, 2.4) * s
		local up = rng:range(1.6, 2.8) * s
		local p0 = pos + Vector3.new(0, y, 0)
		local p1 = p0 + dir * armLen
		B.rod(m, p0, p1, d * 0.62, col, B.deco({ Material = M.Grass }))
		B.rod(m, p1, p1 + Vector3.new(0, up, 0), d * 0.62, col, B.deco({ Material = M.Grass }))
		B.ball(m, p1 + Vector3.new(0, up, 0), d * 0.62, col, B.deco({ Material = M.Grass }))
	end
	if pal.cactusFlower and rng:chance(0.5) then
		B.ball(m, pos + Vector3.new(0, h + d * 0.45, 0), 0.6 * s, pal.cactusFlower, B.deco({ Shadow = false }))
	end
	return m
end

----------------------------------------------------------------------
-- Камни и кристаллы
----------------------------------------------------------------------

-- Камень: 2-3 повёрнутых блока разного размера
function P.rock(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.6, 1.6)
	local m = B.model(parent, "Rock")
	local n = rng:int(2, 3)
	local col = pal.rock or B.rgb(128, 128, 136)
	for i = 1, n do
		local size = Vector3.new(rng:range(2, 4), rng:range(1.5, 3), rng:range(2, 4)) * s * (if i == 1 then 1.2 else rng:range(0.5, 0.85))
		local off = if i == 1 then Vector3.zero else Vector3.new(rng:range(-1.6, 1.6) * s, 0, rng:range(-1.6, 1.6) * s)
		local cf = CFrame.new(pos + off + Vector3.new(0, size.Y * 0.3, 0)) * CFrame.Angles(rng:range(-0.35, 0.35), rng:range(0, math.pi), rng:range(-0.35, 0.35))
		local c = if i == 1 then col else B.shade(col, 0.1)
		B.block(m, cf, size, B.vary(c, rng, 0.05), { Material = pal.rockMaterial or M.Slate, Collide = i == 1, Shadow = i == 1 and s > 1 })
	end
	if pal.moss and rng:chance(0.5) then
		B.block(m, CFrame.new(pos + Vector3.new(0, 1.85 * s, 0)) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(2.2, 0.35, 1.8) * s, pal.moss, B.deco({ Material = M.Grass, Shadow = false }))
	end
	return m
end

-- Камень с неоновой медной прожилкой
function P.veinRock(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.9, 1.7)
	local m = B.model(parent, "VeinRock")
	local size = Vector3.new(rng:range(3, 4.5), rng:range(2.5, 4), rng:range(3, 4.5)) * s
	local cf = CFrame.new(pos + Vector3.new(0, size.Y * 0.32, 0)) * CFrame.Angles(rng:range(-0.25, 0.25), rng:range(0, 3.14), rng:range(-0.25, 0.25))
	B.block(m, cf, size, B.vary(pal.rock, rng, 0.05), { Material = pal.rockMaterial or M.Slate, Shadow = true })
	-- прожилки: тонкие неоновые полосы, выходящие на поверхность
	local vein = pal.vein or B.rgb(255, 150, 70)
	B.block(m, cf * CFrame.Angles(0, 0, rng:range(-0.6, 0.6)), Vector3.new(size.X * 1.02, 0.22 * s, size.Z * 0.3), vein, B.neon())
	B.block(m, cf * CFrame.Angles(rng:range(-0.5, 0.5), 0.9, 0) * CFrame.new(0, size.Y * 0.15, 0), Vector3.new(0.2 * s, size.Y * 0.7, size.Z * 1.02), vein, B.neon())
	local small = cf * CFrame.new(size.X * 0.55, -size.Y * 0.25, size.Z * 0.2) * CFrame.Angles(0.3, 0.5, 0.2)
	B.block(m, small, size * 0.45, B.vary(B.shade(pal.rock, 0.12), rng, 0.05), B.deco({ Material = pal.rockMaterial or M.Slate }))
	return m
end

-- Кристаллы: 3-4 вытянутых блока, расходящихся веером из одной точки
function P.crystals(parent, pos, rng, color, scale, material, glowCore)
	local s = scale or rng:range(0.8, 1.4)
	local m = B.model(parent, "Crystals")
	local n = rng:int(3, 4)
	local base = CFrame.new(pos) * yaw(rng)
	for i = 1, n do
		local h = rng:range(2.5, 5) * s * (if i == 1 then 1.4 else 1)
		local w = rng:range(0.7, 1.2) * s
		local tilt = if i == 1 then rng:range(-0.1, 0.1) else rng:range(0.35, 0.7)
		local cf = base * CFrame.Angles(0, (i / n) * 6.28, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, h / 2 - 0.4, 0) * CFrame.Angles(0, math.pi / 4, 0)
		B.block(m, cf, Vector3.new(w, h, w), B.vary(color, rng, 0.04), B.deco({ Material = material or M.Glass, Transparency = if (material or M.Glass) == M.Glass then 0.2 else nil, Shadow = false }))
		-- остриё
		B.wedge(m, cf * CFrame.new(0, h / 2 + w * 0.35, 0), Vector3.new(w, w * 0.7, w), B.tint(color, 0.2), B.deco({ Material = material or M.Glass, Transparency = if (material or M.Glass) == M.Glass then 0.2 else nil, Shadow = false }))
		if glowCore and i == 1 then
			B.block(m, cf, Vector3.new(w * 0.35, h * 0.8, w * 0.35), glowCore, B.neon())
		end
	end
	return m
end

-- Базальтовые столбы: 4-6 шестигранных (цилиндры) разной высоты
function P.basalt(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.4)
	local m = B.model(parent, "Basalt")
	local n = rng:int(4, 6)
	for i = 1, n do
		local off = if i == 1 then Vector3.zero else rng:disc(2.6 * s)
		local h = rng:range(2, 7) * s * (if i == 1 then 1.3 else 1)
		local d = rng:range(1.6, 2.4) * s
		local p = B.cylY(m, pos + off + Vector3.new(0, h / 2 - 0.3, 0), h, d, B.vary(pal.rock, rng, 0.05), { Material = M.Basalt, Collide = i <= 2, Shadow = h > 5 })
		p.CFrame = p.CFrame * CFrame.Angles(rng:range(0, 6.28), 0, 0)
		if pal.crack and i == 1 then
			B.cylY(m, pos + off + Vector3.new(0, h - 0.3 + 0.06, 0), 0.12, d * 0.6, pal.crack, B.neon())
		end
	end
	return m
end

----------------------------------------------------------------------
-- Тематический декор
----------------------------------------------------------------------

-- Стеклянный шип-фульгурит из земли: 2-3 изломанных отрезка стекла с неоновой сердцевиной
function P.glassSpike(parent, pos, rng, glass, glow, scale)
	local s = scale or rng:range(0.8, 1.6)
	local m = B.model(parent, "GlassSpike")
	local n = rng:int(2, 3)
	for _ = 1, n do
		local p = pos + rng:disc(1.2 * s)
		local d = Vector3.new(rng:range(-0.5, 0.5), 1, rng:range(-0.5, 0.5)).Unit
		local thick = rng:range(0.7, 1.1) * s
		for seg = 1, 2 do
			local len = rng:range(2.2, 3.6) * s / seg
			local q = p + d * len
			B.rod(m, p, q, thick, B.vary(glass, rng, 0.04), B.deco({ Material = M.Glass, Transparency = 0.25, Shadow = false }))
			if seg == 1 then
				B.rod(m, p, q, thick * 0.35, glow, B.neon())
			end
			p = q
			d = (d + Vector3.new(rng:range(-0.7, 0.7), 0.2, rng:range(-0.7, 0.7))).Unit
			thick *= 0.6
		end
	end
	return m
end

-- Медная труба: выходит из земли, изгибается и уходит обратно (или торчит с вентилем)
function P.pipe(parent, pos, rng, pal, scale, direction)
	local s = scale or rng:range(0.8, 1.3)
	local m = B.model(parent, "Pipe")
	local copper = pal.copper or B.rgb(196, 112, 66)
	local d = 1.3 * s
	local dir = direction or B.dir(rng:range(0, 360))
	local h = rng:range(2.5, 4.5) * s
	local span = rng:range(4, 7) * s
	local a = pos - Vector3.new(0, 0.5, 0)
	local b = pos + Vector3.new(0, h, 0)
	local c = b + dir * span
	local e = c - Vector3.new(0, h + 0.5, 0)
	B.rod(m, a, b, d, B.vary(copper, rng, 0.04), { Material = M.Metal, Shadow = true })
	B.rod(m, b, c, d, B.vary(copper, rng, 0.04), B.deco({ Material = M.Metal, Shadow = true }))
	B.rod(m, c, e, d, B.vary(copper, rng, 0.04), { Material = M.Metal })
	B.ball(m, b, d * 1.15, B.shade(copper, 0.15), B.deco({ Material = M.Metal }))
	B.ball(m, c, d * 1.15, B.shade(copper, 0.15), B.deco({ Material = M.Metal }))
	-- фланцы и вентиль
	B.cylY(m, pos + Vector3.new(0, 0.15, 0), 0.3, d * 1.6, B.shade(copper, 0.25), B.deco({ Material = M.Metal }))
	local mid = (b + c) / 2
	B.cylY(m, mid + Vector3.new(0, d * 0.7, 0), 0.4, 0.3 * s, P.IRON, B.deco({ Material = M.Metal }))
	B.cylY(m, mid + Vector3.new(0, d * 0.95, 0), 0.2, 1.4 * s, B.rgb(200, 60, 50), B.deco({ Material = M.Metal }))
	if pal.vein then
		-- светящееся кольцо-стык
		local cf, _ = B.axis(b, c)
		B.cyl(m, cf, 0.3, d * 1.25, pal.vein, B.neon())
	end
	return m
end

-- Руины арки: два столба из блоков, обломок перекладины, упавшие камни
function P.ruinArch(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.9, 1.2)
	local m = B.model(parent, "Ruin")
	local stone = pal.stone or B.rgb(196, 160, 118)
	local base = CFrame.new(pos) * yaw(rng)
	local span = 7 * s
	local hL = rng:range(8, 10) * s
	local hR = rng:range(4, 7) * s
	for side = -1, 1, 2 do
		local h = if side < 0 then hL else hR
		local y = 0
		local k = 0
		while y < h - 0.5 do
			k += 1
			local bh = math.min(rng:range(2, 2.8) * s, h - y)
			local cf = base * CFrame.new(side * span / 2, y + bh / 2, 0) * CFrame.Angles(0, rng:range(-0.06, 0.06), 0)
			B.block(m, cf, Vector3.new(2.2 * s, bh, 2.2 * s) * Vector3.new(rng:range(0.92, 1.05), 1, rng:range(0.92, 1.05)), B.vary(if k % 2 == 0 then stone else B.shade(stone, 0.08), rng, 0.04), { Material = M.Sandstone, Shadow = true })
			y += bh
		end
	end
	-- перекладина на левом (высоком) столбе, обломанная
	local beam = base * CFrame.new(-span / 2 + 2.5 * s, hL + 0.7 * s, 0) * CFrame.Angles(0, 0, rng:range(-0.08, 0.02))
	B.block(m, beam, Vector3.new(6 * s, 1.4 * s, 2.4 * s), B.vary(stone, rng, 0.04), B.deco({ Material = M.Sandstone, Shadow = true }))
	B.wedge(m, base * CFrame.new(-span / 2 + 6 * s, hL + 0.7 * s, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(2.4 * s, 1.4 * s, 1.4 * s), B.vary(stone, rng, 0.04), B.deco({ Material = M.Sandstone }))
	-- упавшие блоки
	for _ = 1, 2 do
		local cf = base * CFrame.new(rng:range(-2, 4) * s, 0.7 * s, rng:range(2, 4) * (if rng:chance(0.5) then 1 else -1) * s) * CFrame.Angles(rng:range(-0.3, 0.3), rng:range(0, 3), rng:range(-0.3, 0.3))
		B.block(m, cf, Vector3.new(2, 1.6, 2) * s, B.vary(B.shade(stone, 0.1), rng, 0.05), B.deco({ Material = M.Sandstone }))
	end
	return m
end

-- Сугроб: утопленный шар снега
function P.drift(parent, pos, rng, color, scale)
	local s = scale or rng:range(0.8, 1.6)
	local d = 6 * s
	return B.ball(parent, pos - Vector3.new(0, d * 0.32, 0), d, B.vary(color, rng, 0.02), B.deco({ Material = M.Snow, Shadow = false }))
end

-- Парящий камень (Око Бури): глыба с неоновой трещиной, висит в воздухе
function P.floatRock(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.8)
	local m = B.model(parent, "FloatRock")
	local cf = CFrame.new(pos) * CFrame.Angles(rng:range(-0.4, 0.4), rng:range(0, 6.28), rng:range(-0.4, 0.4))
	local size = Vector3.new(rng:range(2.5, 4), rng:range(2, 3), rng:range(2.5, 4)) * s
	B.block(m, cf, size, B.vary(pal.rock, rng, 0.05), B.deco({ Material = M.Basalt, Shadow = false }))
	B.wedge(m, cf * CFrame.new(0, -size.Y * 0.5 - size.Y * 0.4, 0) * CFrame.Angles(math.pi, 0, 0), Vector3.new(size.X * 0.8, size.Y * 0.8, size.Z * 0.8), B.shade(pal.rock, 0.2), B.deco({ Material = M.Basalt, Shadow = false }))
	if pal.crack then
		B.block(m, cf * CFrame.Angles(0, 0, 0.5), Vector3.new(size.X * 1.03, 0.18, size.Z * 0.2), pal.crack, B.neon())
	end
	return m
end

----------------------------------------------------------------------
-- Городской и бытовой декор
----------------------------------------------------------------------

-- Фонарь на столбе с тёплым светом
function P.lamp(parent, pos, rng, glowColor, height, poleColor)
	local m = B.model(parent, "Lamp")
	local h = height or 9
	local pole = poleColor or P.IRON
	B.cylY(m, pos + Vector3.new(0, 0.35, 0), 0.7, 1.5, pole, { Material = M.Metal })
	B.cylY(m, pos + Vector3.new(0, h / 2, 0), h, 0.45, pole, { Material = M.Metal })
	B.block(m, CFrame.new(pos + Vector3.new(0, h + 0.15, 0)), Vector3.new(1.6, 0.3, 1.6), pole, B.deco({ Material = M.Metal }))
	local glow = B.block(m, CFrame.new(pos + Vector3.new(0, h + 1, 0)), Vector3.new(1.05, 1.4, 1.05), glowColor, B.neon())
	B.block(m, CFrame.new(pos + Vector3.new(0, h + 1.9, 0)), Vector3.new(1.7, 0.35, 1.7), pole, B.deco({ Material = M.Metal }))
	B.ball(m, pos + Vector3.new(0, h + 2.3, 0), 0.6, pole, B.deco({ Material = M.Metal }))
	B.light(glow, glowColor, 20, 1.2, false)
	return m
end

-- Скамейка: сиденье, спинка, две ножки-опоры. facing — куда смотрит сидящий
function P.bench(parent, pos, facingDir, rng, woodColor)
	local m = B.model(parent, "Bench")
	local cf = B.facing(pos, facingDir)
	local wood = B.vary(woodColor or B.rgb(150, 98, 60), rng, 0.04)
	B.block(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(5, 0.35, 1.6), wood, { Material = M.Wood })
	B.block(m, cf * CFrame.new(0, 2.6, 0.75) * CFrame.Angles(-0.15, 0, 0), Vector3.new(5, 1.1, 0.3), wood, B.deco({ Material = M.Wood }))
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * 2.1, 0.75, 0.1), Vector3.new(0.35, 1.5, 1.6), P.IRON, B.deco({ Material = M.Metal }))
	end
	return m
end

-- Клумба: каменный ящик с землёй, кустиком и цветами
function P.planter(parent, pos, rng, pal, size)
	local m = B.model(parent, "Planter")
	local w = size or rng:range(3.5, 5)
	local stone = pal.stone or B.rgb(170, 160, 150)
	B.block(m, CFrame.new(pos + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, pal.yaw or 0, 0), Vector3.new(w, 1.6, w), B.vary(stone, rng, 0.03), { Material = M.Concrete })
	B.block(m, CFrame.new(pos + Vector3.new(0, 1.62, 0)) * CFrame.Angles(0, pal.yaw or 0, 0), Vector3.new(w - 0.6, 0.1, w - 0.6), B.rgb(92, 66, 48), B.deco({ Material = M.Ground, Shadow = false }))
	B.ball(m, pos + Vector3.new(0, 2.3, 0), w * 0.6, B.vary(rng:pick(pal.leaves), rng, 0.05), B.deco({ Material = M.Grass, Shadow = false }))
	for _ = 1, 3 do
		local a = rng:range(0, 6.28)
		B.ball(m, pos + Vector3.new(math.cos(a) * w * 0.3, 2.6 + rng:range(0, 0.5), math.sin(a) * w * 0.3), 0.7, rng:pick(pal.flowers), B.deco({ Shadow = false }))
	end
	return m
end

-- Забор между двумя точками: столбики и 2 перекладины
function P.fence(parent, a, b, color, rng)
	local m = B.model(parent, "Fence")
	local dir = (b - a)
	local len = dir.Magnitude
	local n = math.max(1, math.floor(len / 5))
	local col = color or P.WOOD
	for i = 0, n do
		local p = a + dir * (i / n)
		local tilt = if rng then CFrame.Angles(rng:range(-0.06, 0.06), 0, rng:range(-0.06, 0.06)) else CFrame.new()
		B.block(m, CFrame.new(p + Vector3.new(0, 1.6, 0)) * tilt, Vector3.new(0.55, 3.2, 0.55), if rng then B.vary(col, rng, 0.05) else col, { Material = M.Wood })
	end
	for _, y in { 1.2, 2.5 } do
		B.slab(m, a + Vector3.new(0, y, 0), b + Vector3.new(0, y + (if rng then rng:range(-0.15, 0.15) else 0), 0), 0.3, 0.4, B.shade(col, 0.05), { Material = M.Wood })
	end
	return m
end

-- Бочка
function P.barrel(parent, pos, rng, color)
	local m = B.model(parent, "Barrel")
	local c = B.vary(color or B.rgb(130, 86, 54), rng, 0.04)
	B.cylY(m, pos + Vector3.new(0, 1.3, 0), 2.6, 2, c, { Material = M.Wood })
	for _, y in { 0.5, 2.1 } do
		B.cylY(m, pos + Vector3.new(0, y, 0), 0.25, 2.08, P.IRON, B.deco({ Material = M.Metal }))
	end
	return m
end

-- Ящик
function P.crate(parent, pos, rng, color, size)
	local s = size or rng:range(1.6, 2.4)
	local m = B.model(parent, "Crate")
	local cf = CFrame.new(pos + Vector3.new(0, s / 2, 0)) * yaw(rng)
	B.block(m, cf, Vector3.new(s, s, s), B.vary(color or B.rgb(170, 124, 76), rng, 0.04), { Material = M.WoodPlanks })
	B.block(m, cf, Vector3.new(s * 1.02, s * 0.18, s * 1.02), B.shade(color or B.rgb(170, 124, 76), 0.25), B.deco({ Material = M.Wood }))
	return m
end

----------------------------------------------------------------------
-- Детали-«истории» (по одной-две на остров)
----------------------------------------------------------------------

-- Колодец с крышей-домиком (Луг)
function P.well(parent, pos, rng)
	local m = B.model(parent, "Well")
	local stone = rgb(150, 146, 140)
	B.cylY(m, pos + Vector3.new(0, 1.1, 0), 2.2, 4.4, B.vary(stone, rng, 0.03), { Material = M.Cobblestone, Shadow = true })
	B.cylY(m, pos + Vector3.new(0, 2.15, 0), 0.2, 3.4, rgb(40, 60, 90), B.deco({ Material = M.Glass, Transparency = 0.2 }))
	local base = CFrame.new(pos) * yaw(rng)
	for side = -1, 1, 2 do
		B.block(m, base * CFrame.new(side * 1.9, 3.3, 0), Vector3.new(0.4, 4.4, 0.4), P.WOOD, B.deco({ Material = M.Wood }))
	end
	B.cyl(m, base * CFrame.new(0, 4, 0), 3.8, 0.4, P.WOOD_DARK, B.deco({ Material = M.Wood }))
	B.wedge(m, base * CFrame.new(0, 5.9, -0.8), Vector3.new(4.6, 1.4, 1.6), rgb(150, 70, 56), B.deco({ Material = M.WoodPlanks, Shadow = true }))
	B.wedge(m, base * CFrame.new(0, 5.9, 0.8) * CFrame.Angles(0, math.pi, 0), Vector3.new(4.6, 1.4, 1.6), rgb(130, 60, 48), B.deco({ Material = M.WoodPlanks, Shadow = true }))
	B.block(m, base * CFrame.new(0.6, 3.2, 0), Vector3.new(0.7, 0.8, 0.7), rgb(120, 90, 60), B.deco({ Material = M.Wood }))
	return m
end

-- Вагонетка с медной рудой на обрывке рельсов (Медные Холмы)
function P.mineCart(parent, pos, dir, rng, ore)
	local m = B.model(parent, "MineCart")
	local cf = B.facing(pos, dir)
	local iron = rgb(70, 70, 78)
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * 1.1, 0.12, 0), Vector3.new(0.2, 0.24, 9), iron, B.deco({ Material = M.Metal }))
	end
	for k = -2, 2 do
		B.block(m, cf * CFrame.new(rng:range(-0.1, 0.1), 0.05, k * 1.9) * CFrame.Angles(0, rng:range(-0.08, 0.08), 0), Vector3.new(3, 0.2, 0.6), P.WOOD_DARK, B.deco({ Material = M.Wood }))
	end
	local c = cf * CFrame.new(0, 0, rng:range(-1.5, 1.5))
	B.block(m, c * CFrame.new(0, 1.35, 0), Vector3.new(2.6, 1.5, 3.4), rgb(110, 84, 70), { Material = M.CorrodedMetal })
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.1, 1.1 } do
			B.cyl(m, c * CFrame.new(x, 0.55, z), 0.3, 0.9, iron, B.deco({ Material = M.Metal }))
		end
	end
	for _ = 1, 4 do
		B.ball(m, (c * CFrame.new(rng:range(-0.7, 0.7), 2.1, rng:range(-1, 1))).Position, rng:range(0.6, 0.9), B.vary(rgb(170, 96, 60), rng, 0.05), B.deco({ Material = M.Slate }))
	end
	B.ball(m, (c * CFrame.new(0.2, 2.3, 0.3)).Position, 0.6, ore, B.neon())
	return m
end

-- Пальма: изогнутый ствол из сегментов и веер листьев-клиньев (оазис в Дюнах)
function P.palm(parent, pos, rng)
	local m = B.model(parent, "Palm")
	local p = pos
	local lean = Vector3.new(rng:range(-0.25, 0.25), 1, rng:range(-0.25, 0.25)).Unit
	for k = 1, 4 do
		local q = p + (lean + Vector3.new(0, 0, 0)).Unit * 2.2
		B.rod(m, p, q, 1.1 - k * 0.12, B.vary(rgb(150, 112, 74), rng, 0.04), { Material = M.Wood, Collide = k == 1, Shadow = true })
		p = q
		lean = (lean + Vector3.new(rng:range(-0.12, 0.12), 0.05, rng:range(-0.12, 0.12))).Unit
	end
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2 + rng:range(-0.2, 0.2)
		local cf = CFrame.new(p) * CFrame.Angles(0, a, 0) * CFrame.Angles(-0.35, 0, 0) * CFrame.new(0, 0, -2)
		B.wedge(m, cf * CFrame.Angles(0, math.pi, 0), Vector3.new(1.2, 0.4, 4), B.vary(rgb(70, 140, 70), rng, 0.05), B.deco({ Material = M.Grass, Shadow = true }))
	end
	B.ball(m, p + Vector3.new(0, -0.4, 0), 0.9, rgb(120, 86, 50), B.deco())
	return m
end

-- Снеговик: три шара, морковка, глазки-угольки, шарф (Ледяной Пик)
function P.snowman(parent, pos, facingDir, rng)
	local m = B.model(parent, "Snowman")
	local cf = B.facing(pos, facingDir)
	local snow = rgb(244, 248, 255)
	B.ball(m, pos + Vector3.new(0, 1.5, 0), 3.2, snow, { Material = M.Snow, Shadow = true })
	B.ball(m, pos + Vector3.new(0, 3.6, 0), 2.4, snow, B.deco({ Material = M.Snow }))
	B.ball(m, pos + Vector3.new(0, 5.2, 0), 1.7, snow, B.deco({ Material = M.Snow }))
	B.cyl(m, cf * CFrame.new(0, 4.6, -0.7) * CFrame.Angles(0, math.pi / 2, 0), 1.6, 1.25, rgb(220, 60, 60), B.deco({ Material = M.Fabric }))
	local nose = cf * CFrame.new(0, 5.15, -1)
	B.wedge(m, nose * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.new(0.3, 0.9, 0.3), rgb(255, 140, 40), B.deco())
	for side = -1, 1, 2 do
		B.ball(m, (cf * CFrame.new(side * 0.32, 5.45, -0.72)).Position, 0.22, rgb(20, 20, 26), B.deco())
		B.rod(m, (cf * CFrame.new(side * 1.0, 3.8, 0)).Position, (cf * CFrame.new(side * 2.4, 4.8, 0)).Position, 0.15, P.WOOD_DARK, B.deco({ Material = M.Wood }))
	end
	local _ = rng
	return m
end

return P
