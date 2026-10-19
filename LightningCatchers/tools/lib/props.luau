--!nocheck
-- Природа и декор из «кирпичиков» стиля (docs/STYLE.md §6.6–6.15): гранёные деревья трёх типов, тополя,
-- ели из настоящих пирамид, кусты, валуны, плитняк, жильные камни, базальт, кристаллы, стеклянные шипы,
-- травинки и цветы по ветру, кактусы, пальмы, изоляторные фонари, скамейки, клумбы, заборы.
-- Правила: одна главная масса и меньшие (60/30/10), шаров нет (кроме снеговика), всё клонится по ветру B.W,
-- плоское тёмное «брюхо» снизу и светлый верх, материал SmoothPlastic, тени только у ствола и главной массы.
local roblox = require("@lune/roblox")
local B = require("./builder")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material
local rgb = B.rgb

local P = {}

local W = B.W
local UP = Vector3.yAxis
local PERP = Vector3.new(-W.Z, 0, W.X) -- поперёк ветра

-- Общие цвета
P.WOOD = rgb(124, 84, 58) -- ствол Луга
P.WOOD_DARK = B.shade(P.WOOD, 1)
P.IRON = rgb(70, 64, 96) -- отделка, железо (хаб)
P.PORCELAIN = rgb(236, 226, 206) -- изоляторы
P.COPPER = rgb(204, 116, 64)

local TAU = math.pi * 2
local YAW_X_ALONG_W = math.atan2(-W.Z, W.X) -- поворот, при котором локальная X смотрит по ветру

local function deg(a: number): number
	return math.rad(a)
end

-- Наклон по ветру вокруг точки pos
local function leanAt(pos, angle: number)
	return CFrame.new(pos) * B.windLean(angle)
end

----------------------------------------------------------------------
-- Деревья
----------------------------------------------------------------------

-- Наборы углов крон (главная и вторая масса): три варианта, чтобы деревья не были клонами
-- Крупный наклон (ближе к «кубу на вершине») даёт гранёную округлую крону, а не коробку
local CROWN_SETS = {
	{ main = { 30, -36 }, second = { -32, 24 } },
	{ main = { -28, 38 }, second = { 34, -22 } },
	{ main = { 34, 30 }, second = { -26, -30 } },
}

-- A. Луговое дерево (7 деталей + фрукты): ствол, корни, три гранёные массы и тёмное брюхо.
-- pal: trunk, leafA, leafB, fruit?
function P.tree(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.85, 1.25)
	local m = B.model(parent, "Tree")
	local useB = pal.leafB ~= nil and rng:chance(0.35)
	local leaf = if useB then pal.leafB else pal.leafA
	local leaf2 = if useB then pal.leafA else (pal.leafB or pal.leafA)
	local trunk = B.vary(pal.trunk or P.WOOD, rng, 0.03)
	local yaw = rng:range(0, TAU)
	local set = rng:pick(CROWN_SETS)
	local trunkH = 6.5 * s
	local base = leanAt(pos, rng:range(3, 5)) * CFrame.Angles(0, yaw, 0)
	-- ствол (с коллизией — сквозь дерево не пройти)
	B.block(m, base * CFrame.new(0, trunkH / 2 - 0.4, 0), Vector3.new(1.6, trunkH, 1.6) * s, trunk, { Shadow = true })
	-- корни: клинья скосом наружу
	for _, a in { rng:range(0, TAU), 0 } do
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		if a == 0 then
			d = -d -- второй корень с другой стороны
		end
		B.wedge(m, B.facing(pos + d * (0.75 * s + 0.45 * s) + Vector3.new(0, 0.55 * s, 0), d), Vector3.new(1.2, 1.4, 1.0) * s, B.shade(trunk, 1), B.deco({ Shadow = false }))
	end
	local top = (base * CFrame.new(0, trunkH - 0.4, 0)).Position
	-- главная масса: смещена по ветру
	local mainC = top + Vector3.new(0, 2.3 * s, 0) + W * 1 * s
	B.tiltBox(m, mainC, Vector3.new(8.5, 6.5, 8) * s, deg(set.main[1]), yaw, deg(set.main[2]), B.vary(leaf, rng, 0.03), B.deco({ Shadow = true }))
	-- вторая масса: сбоку и ниже, светлее
	local side = Vector3.new(math.cos(yaw + 0.6), 0, math.sin(yaw + 0.6))
	B.tiltBox(m, mainC + side * 3.2 * s - Vector3.new(0, 1.2 * s, 0), Vector3.new(6, 5, 5.5) * s, deg(set.second[1]), yaw + deg(40), deg(set.second[2]), B.vary(B.tint(leaf, 1), rng, 0.03), B.deco({ Shadow = false }))
	-- третья масса: с другой стороны и выше (второй оттенок листвы)
	B.tiltBox(m, mainC - side * 2.6 * s + W * 0.6 * s + Vector3.new(0, 1.5 * s, 0), Vector3.new(4, 3.5, 4) * s, deg(rng:range(-20, 20)), yaw - deg(30), deg(rng:range(-20, 20)), B.vary(B.tint(leaf2, 0.4), rng, 0.03), B.deco({ Shadow = false }))
	-- брюхо кроны: плоское и тёмное
	B.block(m, CFrame.new(mainC - Vector3.new(0, 3.1 * s, 0)) * CFrame.Angles(0, yaw, 0), Vector3.new(7, 1.2, 6.5) * s, B.shade(leaf, 1.6), B.deco({ Shadow = false }))
	if pal.fruit and rng:chance(0.5) then
		for k = 1, rng:int(2, 3) do
			local a = yaw + k * 2.1 + rng:range(-0.3, 0.3)
			local p = mainC + Vector3.new(math.cos(a) * 3.9 * s, rng:range(-1.6, 0.4) * s, math.sin(a) * 3.9 * s)
			B.gem(m, p, 0.6 * s, rng:range(0, TAU), pal.fruit, B.deco({ Shadow = false }))
		end
	end
	return m
end

-- B. Тополь-колонна (7 деталей): вертикальный акцент у домов и оград. pal: trunk, leafB (или leafA)
function P.poplar(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.85, 1.2)
	local m = B.model(parent, "Poplar")
	local leaf = B.vary(pal.leafB or pal.leafA, rng, 0.03)
	local base = leanAt(pos, rng:range(1.5, 3)) * CFrame.Angles(0, deg(45) + rng:range(-0.1, 0.1), 0)
	B.block(m, base * CFrame.new(0, 1.75 * s, 0), Vector3.new(1.2, 3.5, 1.2) * s, B.vary(pal.trunk or P.WOOD, rng, 0.03), { Shadow = true })
	B.block(m, base * CFrame.new(0, 3 * s + 4.5 * s, 0), Vector3.new(4.5, 9, 4.5) * s, leaf, B.deco({ Shadow = true }))
	B.block(m, base * CFrame.new(0, 3 * s - 0.4 * s, 0), Vector3.new(4, 1, 4) * s, B.shade(leaf, 1.6), B.deco({ Shadow = false }))
	local tp = (base * CFrame.new(0, 12 * s, 0)).Position
	B.pyramid4(m, tp, 4.5 * s, 3.5 * s, B.yawOf(base.LookVector), B.tint(leaf, 1), B.deco({ Shadow = false }))
	return m
end

-- C. Ветреное дерево (6 деталей): штормовой акцент на краях, ствол изогнут по ветру, крона — две «подушки»
function P.windyTree(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.9, 1.2)
	local m = B.model(parent, "WindyTree")
	local trunk = B.vary(pal.trunk or P.WOOD, rng, 0.03)
	local leaf = B.vary(pal.leafA, rng, 0.03)
	local seg = 4 * s
	local cf1 = leanAt(pos, 8) * CFrame.new(0, seg / 2 - 0.3, 0)
	B.block(m, cf1, Vector3.new(1.4, seg, 1.4) * s, trunk, { Shadow = true })
	local p1 = (leanAt(pos, 8) * CFrame.new(0, seg - 0.5, 0)).Position
	local cf2 = leanAt(p1, 25) * CFrame.new(0, seg / 2, 0)
	B.block(m, cf2, Vector3.new(1.2, seg, 1.2) * s, B.shade(trunk, 0.4), B.deco({ Shadow = true }))
	local top = (leanAt(p1, 25) * CFrame.new(0, seg, 0)).Position
	local c1 = top + W * 2.5 * s + Vector3.new(0, 0.6 * s, 0)
	B.tiltBox(m, c1, Vector3.new(9, 3.2, 6.5) * s, deg(rng:range(8, 14)), YAW_X_ALONG_W + rng:range(-0.15, 0.15), deg(-rng:range(8, 14)), leaf, B.deco({ Shadow = true }))
	B.tiltBox(m, c1 + W * 2 * s + Vector3.new(0, 2.4 * s, 0), Vector3.new(6, 2.8, 4.5) * s, deg(-8), YAW_X_ALONG_W + rng:range(-0.25, 0.25), deg(-10), B.tint(leaf, 1), B.deco({ Shadow = false }))
	B.block(m, CFrame.new(c1 - Vector3.new(0, 1.95 * s, 0)) * CFrame.Angles(0, YAW_X_ALONG_W, 0), Vector3.new(8, 0.8, 5.5) * s, B.shade(leaf, 1.6), B.deco({ Shadow = false }))
	return m
end

-- D. Сухое дерево (≤ 7): ствол и ветки — бруски ромбовидного сечения, ветки изломаны зигзагом, клок ржавой листвы
function P.deadTree(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.85, 1.2)
	local m = B.model(parent, "DeadTree")
	local wood = B.vary(pal.trunk or rgb(110, 74, 58), rng, 0.04)
	local a = pos - Vector3.new(0, 0.3, 0)
	local b = pos + Vector3.new(0, 4.6 * s, 0) + W * 0.8 * s + PERP * rng:range(-0.6, 0.6) * s
	local c = b + Vector3.new(0, 3.4 * s, 0) + W * 1.3 * s + PERP * rng:range(-0.8, 0.8) * s
	B.diamondBar(m, a, b, 1.3 * s, wood, { Shadow = true }, 0.4 * s)
	B.diamondBar(m, b, c, 0.95 * s, B.tint(wood, 0.3), B.deco({ Shadow = true }), 0.35 * s)
	-- две ветки: каждая — два отрезка с изломом 30–50°
	local ang = rng:range(0, TAU)
	for k = 0, 1 do
		local from = if k == 0 then b:Lerp(c, 0.2) else b:Lerp(c, 0.75)
		local th = ang + k * math.pi + rng:range(-0.5, 0.5)
		local d1 = Vector3.new(math.cos(th), rng:range(0.5, 0.9), math.sin(th)).Unit
		local p1 = from + d1 * rng:range(2, 2.8) * s
		local th2 = th + rng:sign() * deg(rng:range(30, 50))
		local d2 = (Vector3.new(math.cos(th2), rng:range(0.6, 1.1), math.sin(th2)) + W * 0.3).Unit
		local p2 = p1 + d2 * rng:range(1.4, 2.2) * s
		B.diamondBar(m, from, p1, 0.55 * s, wood, B.deco({ Shadow = false }), 0.3 * s)
		B.diamondBar(m, p1, p2, 0.4 * s, B.tint(wood, 0.3), B.deco({ Shadow = false }), 0.2 * s)
		if k == 1 and pal.leafA and rng:chance(0.75) then
			B.tiltBox(m, p2 + W * 0.5 * s, Vector3.new(2.6, 1.9, 2.2) * s, deg(rng:range(28, 38)), rng:range(0, TAU), deg(rng:sign() * rng:range(30, 42)), B.vary(pal.leafA, rng, 0.04), B.deco({ Shadow = false }))
		end
	end
	return m
end

-- Ель (13 деталей): ствол и три яруса-пирамиды, каждый следующий повёрнут на 45°.
-- pal: needles, trunk?, snow? (на Пике верхний ярус белый)
function P.pine(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.85, 1.3)
	local m = B.model(parent, "Pine")
	local needles = B.vary(pal.needles, rng, 0.03)
	local base = leanAt(pos, rng:range(2, 4))
	local yaw = rng:range(0, math.pi / 2)
	B.block(m, base * CFrame.new(0, 1.0 * s, 0) * CFrame.Angles(0, yaw, 0), Vector3.new(1.1, 2.4, 1.1) * s, B.shade(pal.trunk or P.WOOD, 1), { Shadow = true })
	local tiers = {
		{ w = 7.5, h = 5.2, y = 1.6, col = needles, shadow = true },
		{ w = 5.6, h = 4.8, y = 4.6, col = B.tint(needles, 0.6), shadow = false },
		{ w = 3.6, h = 4.4, y = 7.4, col = pal.snow or B.tint(needles, 1), shadow = false },
	}
	for t, tier in tiers do
		local p = (base * CFrame.new(0, tier.y * s, 0)).Position
		local tyaw = yaw + (t - 1) * deg(45) + rng:range(-0.12, 0.12)
		B.pyramid4(m, p, tier.w * s, tier.h * s, tyaw, tier.col, B.deco({ Shadow = tier.shadow }))
	end
	return m
end

-- Куст (2–5 деталей): две гранёные массы, утопленные в землю на 30%, иногда ягоды-гранёные бусины
function P.bush(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.3)
	local m = B.model(parent, "Bush")
	local leaf = B.vary(pal.leafA, rng, 0.04)
	local yaw = rng:range(0, TAU)
	local c = pos + Vector3.new(0, 0.75 * s, 0)
	B.tiltBox(m, c, Vector3.new(3, 2.2, 2.6) * s, deg(rng:sign() * rng:range(20, 32)), yaw, deg(rng:sign() * rng:range(20, 32)), leaf, B.deco({ Shadow = false }))
	local off = Vector3.new(math.cos(yaw + 1.2), 0, math.sin(yaw + 1.2)) * 1.3 * s + W * 0.4 * s
	B.tiltBox(m, c + off + Vector3.new(0, 0.35 * s, 0), Vector3.new(2, 1.6, 1.8) * s, deg(rng:range(-25, 25)), yaw + 0.7, deg(rng:range(-25, 25)), B.tint(leaf, 1), B.deco({ Shadow = false }))
	if pal.berries and rng:chance(0.45) then
		for k = 1, rng:int(2, 3) do
			local a = yaw + k * 2.2
			B.gem(m, c + Vector3.new(math.cos(a) * 1.4 * s, rng:range(0.3, 0.9) * s, math.sin(a) * 1.25 * s), 0.45, rng:range(0, TAU), pal.berries, B.deco({ Shadow = false }))
		end
	end
	return m
end

-- Пучок травы: 2 тонких клина веером, наклон по ветру 15–25°. hero = 3 травинки. Без коллизий
function P.tuft(parent, pos, rng, color, scale, hero)
	local s = scale or 1
	local n = if hero then 3 else 2
	local yaw0 = YAW_X_ALONG_W + rng:range(-0.4, 0.4)
	for i = 1, n do
		local h = rng:range(0.8, 1.5) * s
		local col = if i == 1 then B.shade(color, 0.8) elseif i == 2 then B.tint(color, 0.8) else color
		local cf = leanAt(pos, rng:range(15, 25)) * CFrame.Angles(0, yaw0 + (i - 1) * deg(38) + rng:range(-0.2, 0.2), 0) * CFrame.new(0, h / 2, 0)
		B.wedge(parent, cf, Vector3.new(0.15, h, 0.45 * s), B.vary(col, rng, 0.03), B.deco({ Shadow = false, Name = "Grass" }))
	end
end

-- Цветок-ромашка (2 детали, в зоне героя 3): стебель и плоская головка-диск, наклон по ветру
function P.flower(parent, pos, rng, color, scale, hero)
	local s = scale or rng:range(0.85, 1.15)
	local h = rng:range(0.8, 1.3) * s
	local lean = leanAt(pos, rng:range(15, 25)) * CFrame.Angles(0, rng:range(0, TAU), 0)
	B.block(parent, lean * CFrame.new(0, h / 2, 0), Vector3.new(0.14, h, 0.14), rgb(72, 136, 60), B.deco({ Shadow = false, Name = "Stem" }))
	local head = lean * CFrame.new(0, h, 0) * CFrame.Angles(deg(rng:range(-12, 12)), 0, math.pi / 2)
	B.cyl(parent, head, 0.14, 0.75 * s, B.vary(color, rng, 0.04), B.deco({ Shadow = false, Name = "Flower" }))
	if hero then
		B.cyl(parent, head * CFrame.new(0.08, 0, 0), 0.06, 0.3 * s, rgb(255, 214, 90), B.deco({ Shadow = false, Name = "Flower" }))
	end
end

-- Бутон (2 детали): стебель и гранёная бусина
function P.bud(parent, pos, rng, color, scale)
	local s = scale or rng:range(0.85, 1.15)
	local h = rng:range(0.7, 1.2) * s
	local lean = leanAt(pos, rng:range(15, 25))
	B.block(parent, lean * CFrame.new(0, h / 2, 0), Vector3.new(0.14, h, 0.14), rgb(72, 136, 60), B.deco({ Shadow = false, Name = "Stem" }))
	B.gem(parent, (lean * CFrame.new(0, h + 0.15, 0)).Position, 0.5 * s, rng:range(0, TAU), B.vary(color, rng, 0.04), B.deco({ Shadow = false, Name = "Flower" }))
end

-- Полоса цветов вдоль ветра (6 × 2.5), 70% одного цвета: ромашки и бутоны вперемешку
function P.flowerStrip(parent, pos, rng, colors, n: number?, hero: boolean?, len: number?)
	local count = n or rng:int(5, 8)
	local L = len or 6
	local main = rng:pick(colors)
	for _ = 1, count do
		local c = if rng:chance(0.7) then main else rng:pick(colors)
		local p = pos + W * rng:range(-L / 2, L / 2) + PERP * rng:range(-1.25, 1.25)
		if rng:chance(0.7) then
			P.flower(parent, p, rng, c, nil, hero)
		else
			P.bud(parent, p, rng, c)
		end
	end
end

-- Гриб (5 деталей): ножка и низкая гранёная шляпка-пирамида; glow — светящийся (только Око Бури)
function P.mushroom(parent, pos, rng, capColor, scale, glow)
	local s = scale or rng:range(0.7, 1.3)
	local m = B.model(parent, "Mushroom")
	local lean = leanAt(pos, rng:range(4, 10))
	B.block(m, lean * CFrame.new(0, 0.6 * s, 0), Vector3.new(0.5, 1.2, 0.5) * s, rgb(240, 230, 210), B.deco({ Shadow = false }))
	local capBase = (lean * CFrame.new(0, 1.1 * s, 0)).Position
	local opts = if glow then B.neon() else B.deco({ Shadow = false })
	local cap = B.pyramid4(m, capBase, 1.9 * s, 0.9 * s, rng:range(0, TAU), capColor, opts)
	if glow then
		B.light(cap[1], capColor, 10, 0.6)
	end
	return m
end

-- Пальма (≤ 12): ствол из 4 брусков с уменьшением, 6 листьев-клиньев разной длины (2 свисают сильнее), 2 гранёных ореха
function P.palm(parent, pos, rng)
	local m = B.model(parent, "Palm")
	local p = pos - Vector3.new(0, 0.2, 0)
	local lean = (UP + W * 0.18 + PERP * rng:range(-0.12, 0.12)).Unit
	local bark = rgb(150, 112, 74)
	for k = 1, 4 do
		local q = p + lean * 2.3
		local w = 1.15 - k * 0.13
		B.block(m, B.lookAt((p + q) / 2, q) * CFrame.Angles(0, 0, deg(45 * (k % 2))), Vector3.new(w, w, 2.6), B.vary(if k % 2 == 0 then bark else B.shade(bark, 0.4), rng, 0.03), { Collide = k == 1, Query = k == 1, Shadow = true })
		p = q
		lean = (lean + W * 0.1 + Vector3.new(rng:range(-0.06, 0.06), 0, rng:range(-0.06, 0.06))).Unit
	end
	local leafCol = rgb(84, 150, 96)
	local droop = { [2] = true, [5] = true }
	for k = 1, 6 do
		local a = k / 6 * TAU + rng:range(-0.25, 0.25)
		local L = rng:range(3, 4.5)
		local pitch = if droop[k] then deg(rng:range(48, 60)) else deg(rng:range(18, 32))
		local cf = CFrame.new(p) * CFrame.Angles(0, a, 0) * CFrame.Angles(-pitch, 0, 0) * CFrame.new(0, 0, -L / 2)
		B.wedge(m, cf, Vector3.new(1.3, 0.35, L), B.vary(if k % 2 == 0 then leafCol else B.tint(leafCol, 0.7), rng, 0.04), B.deco({ Shadow = true }))
	end
	for k = 0, 1 do
		B.gem(m, p + Vector3.new(0, -0.5, 0) + PERP * (k - 0.5) * 0.7, 0.7, rng:range(0, TAU), rgb(120, 86, 50), B.deco({ Shadow = false }))
	end
	return m
end

-- Кактус (≤ 10): ствол-шестигранник, руки из брусков с вертикальными сегментами, низкая шапка или цветок
function P.cactus(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.75, 1.25)
	local m = B.model(parent, "Cactus")
	local col = B.vary(pal.cactus or rgb(84, 150, 96), rng, 0.04)
	local h = rng:range(5, 7) * s
	local R = 0.9 * s
	local yaw = rng:range(0, TAU)
	local parts = B.hexPrism(m, pos + Vector3.new(0, h / 2 - 0.2, 0), R, h, yaw, col, { Shadow = true })
	for k = 2, 3 do
		parts[k].CanCollide = false
		parts[k].CanQuery = false
		parts[k].CastShadow = false
	end
	local arms = if rng:chance(0.55) then 1 else 2
	local ang = rng:range(0, TAU)
	for i = 1, arms do
		local a = ang + (i - 1) * math.pi + rng:range(-0.3, 0.3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local y = h * rng:range(0.32, 0.55)
		local armLen = rng:range(1.6, 2.2) * s
		local up = rng:range(1.6, 2.6) * s
		local p0 = pos + Vector3.new(0, y, 0)
		local p1 = p0 + dir * (R * 0.8 + armLen)
		B.bar(m, p0, p1 + dir * 0.5 * s, 1.0 * s, 1.0 * s, B.shade(col, 0.35), B.deco({ Shadow = false }))
		B.block(m, B.facing(p1 + Vector3.new(0, up / 2 - 0.5 * s, 0), dir), Vector3.new(1.0, up + 1.0, 1.0) * Vector3.new(s, 1, s), col, B.deco({ Shadow = false }))
	end
	if arms == 1 then
		B.pyramid4(m, pos + Vector3.new(0, h - 0.2, 0), 1.6 * s, 0.6 * s, yaw + deg(30), B.tint(col, 0.6), B.deco({ Shadow = false }))
	end
	if pal.cactusFlower and rng:chance(0.5) then
		B.gem(m, pos + Vector3.new(0, h + (if arms == 1 then 0.6 * s else 0.15), 0), 0.6 * s, rng:range(0, TAU), pal.cactusFlower, B.deco({ Shadow = false }))
	end
	return m
end

----------------------------------------------------------------------
-- Камни и кристаллы
----------------------------------------------------------------------

-- Валун (3 детали): тело, скошенная светлая грань на верхнем ребре, гранёный камень сбоку.
-- pal: rock. Ширина к высоте не меньше 1.5 : 1
function P.rock(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.6)
	local m = B.model(parent, "Rock")
	local rock = B.vary(pal.rock, rng, 0.03)
	local yaw = rng:range(0, TAU)
	local size = Vector3.new(3.6 * rng:range(0.9, 1.15), 2.4 * rng:range(0.85, 1.05), 3 * rng:range(0.9, 1.1)) * s
	local cf = CFrame.new(pos + Vector3.new(0, size.Y / 2 - 0.4 * s, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(deg(rng:range(-8, 8)), 0, deg(rng:range(-8, 8)))
	B.block(m, cf, size, rock, { Shadow = s > 1.1 })
	-- скос: клин на заднем верхнем ребре, светлая грань смотрит вперёд и вверх
	B.wedge(m, cf * CFrame.new(0, size.Y / 2 + 0.45 * s, size.Z / 2 - 0.7 * s), Vector3.new(size.X, 0.9 * s, 1.4 * s), B.tint(rock, 1), B.deco({ Shadow = false }))
	local side = rng:sign()
	B.gem(m, (cf * CFrame.new(side * (size.X / 2 + 0.25 * s), -size.Y * 0.2, rng:range(-0.6, 0.6) * s)).Position, rng:range(1.2, 1.6) * s, rng:range(0, TAU), B.shade(rock, 1), B.deco({ Shadow = false }))
	return m
end

-- Плитняк (2 детали): две плоские плиты ступенькой, вторая повёрнута на 20–35°
function P.flagstone(parent, pos, rng, pal, scale, collide)
	local s = scale or rng:range(0.8, 1.3)
	local m = B.model(parent, "Flagstone")
	local rock = B.vary(pal.rock, rng, 0.03)
	local yaw = rng:range(0, TAU)
	B.block(m, CFrame.new(pos + Vector3.new(0, 0.25 * s, 0)) * CFrame.Angles(0, yaw, deg(rng:range(-3, 3))), Vector3.new(4, 0.8, 3) * s, rock, if collide then { Shadow = false } else B.deco({ Shadow = false }))
	local off = Vector3.new(math.cos(yaw), 0, -math.sin(yaw)) * 0.9 * s
	B.block(m, CFrame.new(pos + off + Vector3.new(0, 0.75 * s, 0)) * CFrame.Angles(0, yaw + rng:sign() * deg(rng:range(20, 35)), 0), Vector3.new(2.8, 0.7, 2.2) * s, B.tint(rock, 0.6), B.deco({ Shadow = false }))
	return m
end

-- Жильный камень (≤ 5): валун и не больше двух неоновых полос (поперёк главной грани и по скосу)
function P.veinRock(parent, pos, rng, pal, scale)
	local s = scale or rng:range(1, 1.7)
	local m = B.model(parent, "VeinRock")
	local rock = B.vary(pal.rock, rng, 0.03)
	local vein = pal.vein or rgb(255, 150, 70)
	local yaw = rng:range(0, TAU)
	local size = Vector3.new(3.6, 2.4, 3) * s
	local cf = CFrame.new(pos + Vector3.new(0, size.Y / 2 - 0.4 * s, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(deg(rng:range(-7, 7)), 0, deg(rng:range(-7, 7)))
	B.block(m, cf, size, rock, { Shadow = true })
	local chamfer = cf * CFrame.new(0, size.Y / 2 + 0.45 * s, size.Z / 2 - 0.7 * s)
	B.wedge(m, chamfer, Vector3.new(size.X, 0.9 * s, 1.4 * s), B.tint(rock, 1), B.deco({ Shadow = false }))
	B.gem(m, (cf * CFrame.new(-(size.X / 2 + 0.2 * s), -size.Y * 0.2, 0.3 * s)).Position, 1.4 * s, rng:range(0, TAU), B.shade(rock, 1), B.deco({ Shadow = false }))
	-- полоса поперёк передней грани (чуть выступает) и полоса вдоль скоса
	B.block(m, cf * CFrame.new(rng:range(-0.6, 0.6) * s, 0, -size.Z / 2) * CFrame.Angles(0, 0, deg(rng:range(55, 75))), Vector3.new(size.Y * 1.25, 0.22 * s, 0.12), vein, B.neon())
	B.block(m, chamfer * CFrame.Angles(math.atan2(0.9, 1.4), 0, 0) * CFrame.new(0, 0, 0), Vector3.new(size.X * 0.7, 0.06, 0.22 * s), vein, B.neon())
	return m
end

-- Базальт (≤ 15): 3–4 шестигранных столба разной высоты, на самом высоком — неоновая плитка-трещина
function P.basalt(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.85, 1.3)
	local m = B.model(parent, "Basalt")
	local n = rng:int(3, 4)
	local tallest = nil
	local yaw = rng:range(0, TAU)
	for i = 1, n do
		local off = if i == 1 then Vector3.zero else Vector3.new(math.cos(yaw + i * 1.9), 0, math.sin(yaw + i * 1.9)) * rng:range(1.6, 2.4) * s
		local R = rng:range(0.9, 1.3) * s
		local h = (if i == 1 then rng:range(5.5, 7) else rng:range(2, 4.8)) * s
		local col = B.vary(if i % 2 == 0 then B.tint(pal.rock, 0.5) else pal.rock, rng, 0.03)
		local parts = B.hexPrism(m, pos + off + Vector3.new(0, h / 2 - 0.3, 0), R, h, yaw + rng:range(-0.4, 0.4), col, { Shadow = h > 5, Collide = i <= 2 })
		if i == 1 then
			tallest = { pos + off + Vector3.new(0, h - 0.3, 0), R, parts[1].CFrame }
		end
	end
	if pal.crack and tallest then
		B.hexPlate(m, tallest[1] + Vector3.new(0, 0.07, 0), tallest[2] * 0.62, 0.12, yaw, 0, nil, pal.crack, B.neon())
	end
	return m
end

-- Парящий камень (6 деталей, Око Бури): гранёная глыба и перевёрнутая пирамида-сосулька снизу, неоновая трещина
function P.floatRock(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.8, 1.8)
	local m = B.model(parent, "FloatRock")
	local size = Vector3.new(rng:range(3, 4), rng:range(1.6, 2.2), rng:range(2.6, 3.4)) * s
	local yaw = rng:range(0, TAU)
	local pitch, roll = deg(rng:range(-12, 12)), deg(rng:range(-12, 12))
	local rock = B.vary(pal.rock, rng, 0.04)
	B.tiltBox(m, pos, size, pitch, yaw, roll, B.tint(rock, 0.5), B.deco({ Shadow = false }))
	B.pyramid4(m, pos - Vector3.new(0, size.Y * 0.35, 0), math.min(size.X, size.Z) * 0.9, size.Y * 1.6, yaw, B.shade(rock, 1.3), B.deco({ Shadow = false }), true)
	if pal.crack then
		local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
		B.block(m, cf * CFrame.Angles(0, 0, deg(25)), Vector3.new(size.X * 1.04, 0.18, size.Z * 0.18), pal.crack, B.neon())
	end
	return m
end

-- Кристаллы (≤ 9): главный с двускатным остриём и неоновой сердцевиной, два средних наклонены наружу,
-- маленький гранёный у подножия или плитняк-основание. Стекло только у главного.
function P.crystals(parent, pos, rng, color, scale, glowCore, rockColor)
	local s = scale or rng:range(0.8, 1.4)
	local m = B.model(parent, "Crystals")
	local yaw = rng:range(0, TAU)
	local H = rng:range(3.4, 4.6) * s
	local w = rng:range(1.0, 1.3) * s
	local glassOpts = B.deco({ Material = M.Glass, Transparency = 0.2, Shadow = false })
	local main = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(deg(rng:range(-6, 6)), 0, deg(rng:range(-6, 6))) * CFrame.new(0, H / 2 - 0.3, 0) * CFrame.Angles(0, deg(45), 0)
	B.block(m, main, Vector3.new(w, H, w), B.vary(color, rng, 0.03), glassOpts)
	-- двускатное остриё: два клина спина к спине
	local tipH = w * 0.9
	for k = 0, 1 do
		local cf = main * CFrame.new(0, H / 2 + tipH / 2, (k - 0.5) * w / 2) * CFrame.Angles(0, k * math.pi + math.pi, 0)
		B.wedge(m, cf, Vector3.new(w, tipH, w / 2), B.tint(color, 0.8), B.deco({ Material = M.Glass, Transparency = 0.2, Shadow = false }))
	end
	if glowCore then
		B.block(m, main, Vector3.new(w * 0.35, H * 0.8, w * 0.35), glowCore, B.neon())
	end
	-- два средних, наклонены наружу на 25–40°
	for k = 0, 1 do
		local h = H * rng:range(0.55, 0.7)
		local ww = w * 0.75
		local a = yaw + k * deg(rng:range(130, 170)) + deg(40)
		local cf = CFrame.new(pos) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, deg(rng:range(25, 40))) * CFrame.new(0, h / 2 - 0.2, 0) * CFrame.Angles(0, deg(45), 0)
		local col = B.vary(if k == 0 then B.shade(color, 0.5) else color, rng, 0.03)
		B.block(m, cf, Vector3.new(ww, h, ww), col, B.deco({ Reflectance = 0.1, Shadow = false }))
		B.wedge(m, cf * CFrame.new(0, h / 2 + ww * 0.4, 0), Vector3.new(ww, ww * 0.8, ww), B.tint(col, 0.6), B.deco({ Reflectance = 0.1, Shadow = false }))
	end
	if rockColor then
		B.block(m, CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, yaw + 0.5, 0), Vector3.new(3.4, 0.6, 2.6) * s, B.shade(rockColor, 1), B.deco({ Shadow = false }))
	elseif not glowCore then
		B.gem(m, pos + Vector3.new(math.cos(yaw + 2.5), 0.35, math.sin(yaw + 2.5)) * 1.3 * s, H * 0.3, rng:range(0, TAU), B.tint(color, 0.4), B.deco({ Reflectance = 0.1, Shadow = false }))
	end
	return m
end

-- Стеклянный шип-фульгурит (≤ 8): 2 изломанных шипа из брусков ромбовидного сечения, кончик — клин,
-- неоновая сердцевина только в нижнем сегменте
function P.glassSpike(parent, pos, rng, glass, glow, scale)
	local s = scale or rng:range(0.9, 1.5)
	local m = B.model(parent, "GlassSpike")
	local glassOpts = B.deco({ Material = M.Glass, Transparency = 0.22, Shadow = false })
	for spike = 1, 2 do
		local p = pos + (if spike == 1 then Vector3.zero else rng:disc(1.2 * s)) - Vector3.new(0, 0.3, 0)
		local d = (UP + W * rng:range(0.1, 0.4) + Vector3.new(rng:range(-0.3, 0.3), 0, rng:range(-0.3, 0.3))).Unit
		local thick = (if spike == 1 then rng:range(0.9, 1.1) else rng:range(0.6, 0.8)) * s
		for seg = 1, 2 do
			local len = (if spike == 1 then rng:range(2.6, 3.4) else rng:range(1.6, 2.2)) * s / (0.6 + seg * 0.4)
			local q = p + d * len
			B.diamondBar(m, p, q, thick, B.vary(glass, rng, 0.03), glassOpts, thick * 0.35)
			if seg == 1 and spike == 1 then
				B.diamondBar(m, p, q, thick * 0.38, glow, B.neon())
			end
			p = q
			-- излом 20–35°
			local kink = deg(rng:range(20, 35))
			local axis = d:Cross(Vector3.new(rng:range(-1, 1), 0, rng:range(-1, 1))).Unit
			d = (CFrame.fromAxisAngle(axis, kink) * d).Unit
			if d.Y < 0.35 then
				d = (d + UP * 0.6).Unit
			end
			thick *= 0.66
		end
		-- кончик-клин
		B.block(m, B.lookAt(p + d * thick * 0.7, p + d * 2) * CFrame.Angles(0, 0, deg(45)), Vector3.new(thick, thick, thick * 1.4), B.tint(glass, 0.6), glassOpts)
	end
	return m
end

----------------------------------------------------------------------
-- Тематический декор
----------------------------------------------------------------------

-- Медная труба: выходит из земли, изгибается вдоль края и уходит обратно; стыки — муфты-бруски, не шары
function P.pipe(parent, pos, rng, pal, scale, direction)
	local s = scale or rng:range(0.85, 1.25)
	local m = B.model(parent, "Pipe")
	local copper = B.vary(pal.copper or P.COPPER, rng, 0.03)
	local d = 1.3 * s
	local dir = direction or B.dir(rng:range(0, 360))
	local h = rng:range(2.6, 4.2) * s
	local span = rng:range(4.5, 7) * s
	local a = pos - Vector3.new(0, 0.5, 0)
	local b = pos + Vector3.new(0, h, 0)
	local c = b + dir * span
	local e = c - Vector3.new(0, h + 0.5, 0)
	B.rod(m, a, b, d, copper, { Material = M.Metal, Shadow = true })
	B.rod(m, b, c, d, B.tint(copper, 0.4), B.deco({ Material = M.Metal, Shadow = true }))
	B.rod(m, c, e, d, copper, { Material = M.Metal })
	local joint = B.shade(copper, 0.8)
	B.block(m, B.facing(b, dir), Vector3.new(d * 1.2, d * 1.2, d * 1.2), joint, B.deco({ Material = M.Metal }))
	B.block(m, B.facing(c, dir), Vector3.new(d * 1.2, d * 1.2, d * 1.2), joint, B.deco({ Material = M.Metal }))
	-- фланец у земли и вентиль сверху
	B.cylY(m, pos + Vector3.new(0, 0.15, 0), 0.3, d * 1.6, B.shade(copper, 1), B.deco({ Material = M.Metal }))
	local mid = (b + c) / 2
	B.cylY(m, mid + Vector3.new(0, d * 0.7, 0), 0.4, 0.3 * s, P.IRON, B.deco({ Material = M.Metal }))
	B.cylY(m, mid + Vector3.new(0, d * 0.95, 0), 0.2, 1.4 * s, rgb(200, 60, 50), B.deco({ Material = M.Metal }))
	if pal.vein then
		-- светящийся стык
		local cf, _ = B.axis(b, c)
		B.cyl(m, cf, 0.3, d * 1.25, pal.vein, B.neon())
	end
	return m
end

-- Руины арки: два столба из блоков с чередованием тона, обломок перекладины, упавшие камни
function P.ruinArch(parent, pos, rng, pal, scale)
	local s = scale or rng:range(0.9, 1.2)
	local m = B.model(parent, "Ruin")
	local stone = pal.stone or rgb(204, 160, 112)
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:range(0, TAU), 0)
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
			local cf = base * CFrame.new(side * span / 2, y + bh / 2, 0) * CFrame.Angles(0, rng:range(-0.08, 0.08), 0)
			local col = if k % 2 == 0 then B.tint(stone, 0.5) else stone
			B.block(m, cf, Vector3.new(2.2 * s, bh, 2.2 * s) * Vector3.new(rng:range(0.92, 1.05), 1, rng:range(0.92, 1.05)), B.vary(col, rng, 0.03), { Shadow = true })
			y += bh
		end
	end
	-- перекладина на высоком столбе, обломанная скосом
	local beam = base * CFrame.new(-span / 2 + 2.5 * s, hL + 0.7 * s, 0) * CFrame.Angles(0, 0, rng:range(-0.08, 0.02))
	B.block(m, beam, Vector3.new(6 * s, 1.4 * s, 2.4 * s), B.tint(stone, 0.8), B.deco({ Shadow = true }))
	B.wedge(m, base * CFrame.new(-span / 2 + 6 * s, hL + 0.7 * s, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(2.4 * s, 1.4 * s, 1.4 * s), B.tint(stone, 0.8), B.deco())
	-- упавшие блоки
	for _ = 1, 2 do
		local cf = base * CFrame.new(rng:range(-2, 4) * s, 0.6 * s, rng:range(2, 4) * rng:sign() * s) * CFrame.Angles(rng:range(-0.3, 0.3), rng:range(0, 3), rng:range(-0.3, 0.3))
		B.block(m, cf, Vector3.new(2, 1.6, 2) * s, B.vary(B.shade(stone, 0.6), rng, 0.04), B.deco())
	end
	return m
end

-- Сугроб: клин вдоль ветра (пологий склон с наветренной стороны), утоплен в землю
function P.drift(parent, pos, rng, color, scale)
	local s = scale or rng:range(0.8, 1.5)
	local L, h = 6.5 * s, 1.5 * s
	-- клин: высокий край (+Z) с подветренной стороны, скос к ветру
	local cf = B.facing(pos + Vector3.new(0, h / 2 - 0.35 * s, 0), -W) * CFrame.Angles(0, rng:range(-0.2, 0.2), 0)
	return B.wedge(parent, cf, Vector3.new(4.5 * s, h, L), B.vary(color, rng, 0.015), B.deco({ Shadow = false, Name = "Drift" }))
end

----------------------------------------------------------------------
-- Городской и бытовой декор
----------------------------------------------------------------------

-- Изоляторный фонарь (5 деталей + свет): ромбовидный столб, фарфоровый изолятор, неоновый фонарь, гранёное навершие
function P.lamp(parent, pos, rng, glowColor, height, poleColor)
	local m = B.model(parent, "Lamp")
	local h = height or 9
	local pole = poleColor or P.IRON
	local rot = CFrame.Angles(0, deg(45), 0)
	B.block(m, CFrame.new(pos + Vector3.new(0, 0.4, 0)) * rot, Vector3.new(1.4, 0.8, 1.4), B.shade(pole, 0.5), { Shadow = false })
	B.block(m, CFrame.new(pos + Vector3.new(0, h / 2, 0)) * rot, Vector3.new(0.45, h, 0.45), pole, { Shadow = true })
	B.cylY(m, pos + Vector3.new(0, h + 0.15, 0), 0.3, 1.5, P.PORCELAIN, B.deco({ Shadow = false }))
	local glow = B.block(m, CFrame.new(pos + Vector3.new(0, h + 0.9, 0)) * rot, Vector3.new(0.9, 1.2, 0.9), glowColor, B.neon())
	B.gem(m, pos + Vector3.new(0, h + 2.05, 0), 1.0, deg(45), pole, B.deco({ Shadow = false }))
	B.light(glow, glowColor, 18, 1.1, false)
	return m, glow
end

-- Скамейка: сиденье, спинка, две ножки. facingDir — куда смотрит сидящий
function P.bench(parent, pos, facingDir, rng, woodColor)
	local m = B.model(parent, "Bench")
	local cf = B.facing(pos, facingDir)
	local wood = B.vary(woodColor or rgb(154, 104, 66), rng, 0.03)
	B.block(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(5, 0.4, 1.6), wood, {})
	B.block(m, cf * CFrame.new(0, 2.6, 0.75) * CFrame.Angles(-0.15, 0, 0), Vector3.new(5, 1.1, 0.3), B.tint(wood, 0.5), B.deco())
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * 2.1, 0.75, 0.1), Vector3.new(0.45, 1.5, 1.6), P.IRON, B.deco({ Material = M.Metal }))
	end
	return m
end

-- Клумба: каменный ящик с землёй, куст из двух гранёных масс и три цветка-бусины разных цветов
function P.planter(parent, pos, rng, pal, size)
	local m = B.model(parent, "Planter")
	local w = size or rng:range(3.5, 5)
	local stone = pal.stone or rgb(150, 148, 170)
	local yaw = pal.yaw or 0
	B.block(m, CFrame.new(pos + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, yaw, 0), Vector3.new(w, 1.6, w), B.vary(stone, rng, 0.02), {})
	B.block(m, CFrame.new(pos + Vector3.new(0, 1.62, 0)) * CFrame.Angles(0, yaw, 0), Vector3.new(w - 0.6, 0.1, w - 0.6), rgb(92, 62, 48), B.deco({ Shadow = false }))
	local leaf = B.vary(pal.leafA, rng, 0.04)
	B.tiltBox(m, pos + Vector3.new(0, 2.3, 0), Vector3.new(w * 0.62, w * 0.42, w * 0.55), deg(rng:range(-12, 12)), yaw + rng:range(0, 1), deg(rng:range(-12, 12)), leaf, B.deco({ Shadow = false }))
	B.tiltBox(m, pos + Vector3.new(0, 2.9, 0) + W * 0.4, Vector3.new(w * 0.38, w * 0.3, w * 0.34), deg(rng:range(-20, 20)), yaw + 0.8, deg(rng:range(-20, 20)), B.tint(leaf, 1), B.deco({ Shadow = false }))
	local cols = rng:shuffle({ table.unpack(pal.flowers) })
	for k = 1, 3 do
		local a = yaw + k * 2.1 + rng:range(-0.3, 0.3)
		B.gem(m, pos + Vector3.new(math.cos(a) * w * 0.33, 2.55 + rng:range(0, 0.4), math.sin(a) * w * 0.33), 0.6, rng:range(0, TAU), cols[k], B.deco({ Shadow = false }))
	end
	return m
end

-- Забор между двумя точками: коренастые столбики и 2 перекладины
function P.fence(parent, a, b, color, rng)
	local m = B.model(parent, "Fence")
	local dir = (b - a)
	local len = dir.Magnitude
	local n = math.max(1, math.floor(len / 5))
	local col = color or P.WOOD
	for i = 0, n do
		local p = a + dir * (i / n)
		local tilt = if rng then CFrame.Angles(rng:range(-0.06, 0.06), 0, rng:range(-0.06, 0.06)) else CFrame.new()
		B.block(m, CFrame.new(p + Vector3.new(0, 1.5, 0)) * tilt * CFrame.Angles(0, B.yawOf(dir), 0), Vector3.new(0.8, 3, 0.8), if rng then B.vary(col, rng, 0.04) else col, {})
	end
	for _, y in { 1.1, 2.3 } do
		B.slab(m, a + Vector3.new(0, y, 0), b + Vector3.new(0, y + (if rng then rng:range(-0.15, 0.15) else 0), 0), 0.35, 0.45, B.tint(col, 0.4), {})
	end
	return m
end

-- Бочка: цилиндр с тёмными обручами
function P.barrel(parent, pos, rng, color)
	local m = B.model(parent, "Barrel")
	local c = B.vary(color or rgb(140, 92, 58), rng, 0.03)
	B.cylY(m, pos + Vector3.new(0, 1.3, 0), 2.6, 2, c, {})
	for _, y in { 0.5, 2.1 } do
		B.cylY(m, pos + Vector3.new(0, y, 0), 0.25, 2.08, P.IRON, B.deco({ Material = M.Metal }))
	end
	return m
end

-- Ящик: доски и тёмный пояс
function P.crate(parent, pos, rng, color, size)
	local s = size or rng:range(1.6, 2.4)
	local m = B.model(parent, "Crate")
	local col = color or rgb(176, 128, 80)
	local cf = CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, rng:range(0, TAU), 0)
	B.block(m, cf, Vector3.new(s, s, s), B.vary(col, rng, 0.03), { Material = M.WoodPlanks })
	B.block(m, cf, Vector3.new(s * 1.03, s * 0.18, s * 1.03), B.shade(col, 1), B.deco())
	return m
end

-- Тюки сена (2–3 бруска): уютная деталь Луга вместо «шара на цилиндре»
function P.hayBales(parent, pos, rng)
	local m = B.model(parent, "Hay")
	local hay = rgb(226, 188, 98)
	local yaw = rng:range(0, TAU)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	B.block(m, cf * CFrame.new(-1.1, 0.8, 0), Vector3.new(2.1, 1.6, 3.4), B.vary(hay, rng, 0.03), { Shadow = true })
	B.block(m, cf * CFrame.new(1.1, 0.8, 0.2) * CFrame.Angles(0, 0.08, 0), Vector3.new(2.1, 1.6, 3.4), B.vary(B.shade(hay, 0.3), rng, 0.03), {})
	if rng:chance(0.7) then
		B.block(m, cf * CFrame.new(0.1, 2.4, 0.1) * CFrame.Angles(0, 1.45, 0), Vector3.new(2.1, 1.6, 3.4), B.vary(B.tint(hay, 0.6), rng, 0.03), B.deco({ Shadow = true }))
	end
	return m
end

----------------------------------------------------------------------
-- Детали-«истории» (по одной-две на остров)
----------------------------------------------------------------------

-- Колодец с крышей-домиком (Луг): каменный сруб с полосой другого тона, ворот, красная крыша
function P.well(parent, pos, rng)
	local m = B.model(parent, "Well")
	local stone = rgb(150, 146, 158)
	B.cylY(m, pos + Vector3.new(0, 0.8, 0), 1.6, 4.4, B.vary(stone, rng, 0.02), { Shadow = true })
	B.cylY(m, pos + Vector3.new(0, 1.85, 0), 0.5, 4.6, B.tint(stone, 0.8), B.deco())
	B.cylY(m, pos + Vector3.new(0, 2.05, 0), 0.2, 3.4, rgb(40, 60, 96), B.deco({ Material = M.Glass, Transparency = 0.2 }))
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:range(0, TAU), 0)
	for side = -1, 1, 2 do
		B.block(m, base * CFrame.new(side * 1.9, 3.3, 0), Vector3.new(0.5, 4.4, 0.5), P.WOOD, B.deco())
	end
	B.cyl(m, base * CFrame.new(0, 4, 0), 3.8, 0.45, P.WOOD_DARK, B.deco())
	local roof = rgb(176, 76, 62)
	B.wedge(m, base * CFrame.new(0, 5.9, -0.85), Vector3.new(4.8, 1.4, 1.7), roof, B.deco({ Shadow = true }))
	B.wedge(m, base * CFrame.new(0, 5.9, 0.85) * CFrame.Angles(0, math.pi, 0), Vector3.new(4.8, 1.4, 1.7), B.shade(roof, 1), B.deco({ Shadow = true }))
	B.block(m, base * CFrame.new(0, 6.65, 0), Vector3.new(5.0, 0.3, 0.4), P.COPPER, B.deco({ Material = M.Metal }))
	B.block(m, base * CFrame.new(0.6, 3.2, 0), Vector3.new(0.7, 0.8, 0.7), rgb(124, 92, 60), B.deco())
	return m
end

-- Вагонетка с медной рудой на обрывке рельсов (Медные Холмы): руда — гранёные камни, один светится
function P.mineCart(parent, pos, dir, rng, ore)
	local m = B.model(parent, "MineCart")
	local cf = B.facing(pos, dir)
	local iron = rgb(70, 66, 86)
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * 1.1, 0.12, 0), Vector3.new(0.2, 0.24, 9), iron, B.deco({ Material = M.Metal }))
	end
	for k = -2, 2 do
		B.block(m, cf * CFrame.new(rng:range(-0.1, 0.1), 0.05, k * 1.9) * CFrame.Angles(0, rng:range(-0.08, 0.08), 0), Vector3.new(3, 0.2, 0.6), P.WOOD_DARK, B.deco())
	end
	local c = cf * CFrame.new(0, 0, rng:range(-1.5, 1.5))
	B.block(m, c * CFrame.new(0, 1.35, 0), Vector3.new(2.6, 1.5, 3.4), rgb(118, 86, 72), { Material = M.Metal })
	B.block(m, c * CFrame.new(0, 2.15, 0), Vector3.new(2.8, 0.2, 3.6), B.shade(rgb(118, 86, 72), 1), B.deco({ Material = M.Metal }))
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.1, 1.1 } do
			B.cyl(m, c * CFrame.new(x, 0.55, z), 0.3, 0.9, iron, B.deco({ Material = M.Metal }))
		end
	end
	for k = 1, 3 do
		B.gem(m, (c * CFrame.new(rng:range(-0.6, 0.6), 2.25, -1.2 + k * 0.7)).Position, rng:range(0.8, 1.1), rng:range(0, TAU), B.vary(rgb(170, 96, 60), rng, 0.05), B.deco())
	end
	B.gem(m, (c * CFrame.new(0.2, 2.5, 0.3)).Position, 0.7, 0.4, ore, B.neon())
	return m
end

-- Снеговик (исключение стиля: три шара). Глазки и пуговицы — плоские, нос-морковка — клин, шарф
function P.snowman(parent, pos, facingDir, rng)
	local m = B.model(parent, "Snowman")
	local cf = B.facing(pos, facingDir)
	local snow = rgb(244, 248, 255)
	B.ball(m, pos + Vector3.new(0, 1.5, 0), 3.2, snow, { Shadow = true })
	B.ball(m, pos + Vector3.new(0, 3.6, 0), 2.4, B.shade(snow, 0.12), B.deco())
	B.ball(m, pos + Vector3.new(0, 5.2, 0), 1.7, snow, B.deco())
	B.cyl(m, cf * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.5, 2.15, rgb(220, 60, 60), B.deco({ Material = M.Fabric }))
	B.block(m, cf * CFrame.new(0.55, 4.0, -0.95) * CFrame.Angles(0.3, 0, 0.2), Vector3.new(0.45, 1.1, 0.12), rgb(200, 50, 56), B.deco({ Material = M.Fabric }))
	local nose = cf * CFrame.new(0, 5.15, -1.15)
	B.wedge(m, nose * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.new(0.3, 0.9, 0.3), rgb(255, 140, 40), B.deco())
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * 0.32, 5.45, -0.78), Vector3.new(0.2, 0.2, 0.08), rgb(28, 22, 48), B.deco())
		B.diamondBar(m, (cf * CFrame.new(side * 1.0, 3.8, 0)).Position, (cf * CFrame.new(side * 2.4, 4.8, 0)).Position, 0.18, P.WOOD_DARK, B.deco())
	end
	local _ = rng
	return m
end

return P
