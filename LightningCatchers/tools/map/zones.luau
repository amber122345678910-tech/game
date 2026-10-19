--!nocheck
-- Пять островов (docs/STYLE.md §3.2, §6.6–6.13, §6.17): тело острова, гребни-«чаша» и холмы вне игровой зоны,
-- рощи и одиночные деревья, кусты у подножий, цветы полосами по ветру, входная арка с гербом зоны,
-- ориентир (landmark) каждого острова.
-- Правила: внутри PlayRadius земля плоская (GroundY), там только мелкие цветы/травинки без коллизий
-- и плоские камешки дорожки не выше GroundY + 0.04 (кольца рисуются выше).
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Island = require("./island")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material

local ZonesMap = {}

local W = B.W
local TAU = math.pi * 2

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function angDiff(a: number, b: number): number
	return math.abs(((a - b + math.pi) % TAU) - math.pi)
end

----------------------------------------------------------------------
-- Размещение без сетки: случайные точки с минимальными зазорами и запретными областями
----------------------------------------------------------------------
local function newSampler(C, rng, outline)
	local S = { placed = {}, reserved = {} }
	function S.reserve(pos, r)
		table.insert(S.reserved, { pos, r })
	end
	function S.free(pos, r)
		for _, e in S.reserved do
			if flatDist(pos, e[1]) < r + e[2] then
				return false
			end
		end
		for _, e in S.placed do
			if flatDist(pos, e[1]) < r + e[2] then
				return false
			end
		end
		return true
	end
	function S.take(pos, r)
		table.insert(S.placed, { pos, r })
	end
	-- годится ли точка: в кольце [minR, maxR], не ближе r к краю острова и к другим объектам
	function S.ok(pos, minR, maxR, r)
		local d = flatDist(pos, C)
		local th = math.atan2(pos.Z - C.Z, pos.X - C.X)
		return d >= minR and d <= maxR and d + r <= outline(th) - 1.2 and S.free(pos, r)
	end
	-- точка в кольце [minR, maxR]; bias = {angle, spread} — предпочесть сектор (дальняя от моста сторона)
	function S.ring(minR, maxR, r, tries, bias)
		for _ = 1, tries or 40 do
			local th = if bias then bias[1] + rng:range(-bias[2], bias[2]) else rng:range(0, TAU)
			local d = rng:range(minR, maxR)
			local pos = C + Vector3.new(math.cos(th) * d, 0, math.sin(th) * d)
			if S.ok(pos, minR, maxR, r) then
				S.take(pos, r)
				return pos
			end
		end
		return nil
	end
	-- точка рядом с center на расстоянии [d0, d1] (рощи, кусты у подножия)
	function S.near(center, d0, d1, minR, maxR, r, tries)
		for _ = 1, tries or 24 do
			local a = rng:range(0, TAU)
			local pos = center + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:range(d0, d1)
			if S.ok(pos, minR, maxR, r) then
				S.take(pos, r)
				return pos
			end
		end
		return nil
	end
	return S
end

----------------------------------------------------------------------
-- Темы островов: палитры STYLE §3.2 (основа; тень и свет считают B.shade / B.tint)
----------------------------------------------------------------------
local rgb = B.rgb

local THEMES = {
	-- 1. Грозовой Луг: дружелюбный, зелёный с циановой молнией
	{
		ground = rgb(96, 170, 74),
		groundMat = M.Grass,
		dirt = rgb(150, 100, 66),
		rock = rgb(132, 128, 144),
		trunk = rgb(124, 84, 58),
		leafA = rgb(78, 158, 70),
		leafB = rgb(122, 186, 72),
		flowers = { rgb(255, 120, 160), rgb(255, 214, 90), rgb(250, 248, 255), rgb(196, 146, 255) },
		path = rgb(184, 170, 150),
		lamp = rgb(255, 206, 140),
		arch = rgb(124, 84, 58),
		patches = { rgb(84, 156, 68), rgb(118, 186, 88), rgb(102, 176, 92) },
	},
	-- 2. Медные Холмы: тёплые сумерки, ржавчина и медь, бирюзовая патина
	{
		ground = rgb(196, 128, 66),
		groundMat = M.Grass,
		dirt = rgb(150, 88, 56),
		rock = rgb(128, 98, 90),
		trunk = rgb(110, 74, 58),
		leafA = rgb(214, 140, 60),
		copper = rgb(204, 116, 64),
		patina = rgb(96, 164, 138),
		path = rgb(112, 86, 78),
		lamp = rgb(255, 176, 100),
		arch = rgb(204, 116, 64),
		patches = { rgb(182, 116, 60), rgb(214, 152, 84), rgb(120, 156, 120) },
	},
	-- 3. Стеклянные Дюны: бирюзовый вечер, песок и стекло
	{
		ground = rgb(232, 198, 140),
		groundMat = M.Sand,
		dirt = rgb(206, 160, 108),
		rock = rgb(204, 160, 112),
		stone = rgb(204, 160, 112),
		cactus = rgb(84, 150, 96),
		cactusFlower = rgb(255, 120, 170),
		glass = rgb(140, 240, 228),
		path = rgb(214, 176, 126),
		lamp = rgb(255, 210, 150),
		arch = rgb(204, 160, 112),
		patches = { rgb(220, 184, 128), rgb(244, 216, 162), rgb(214, 180, 130) },
	},
	-- 4. Ледяной Пик: холодное сияние, тени снега сине-лиловые
	{
		ground = rgb(232, 238, 252),
		groundMat = M.Snow,
		dirt = rgb(200, 210, 240),
		rock = rgb(140, 156, 196),
		ice = rgb(156, 206, 246),
		needles = rgb(52, 120, 104),
		snow = rgb(246, 250, 255),
		trunk = rgb(124, 84, 58),
		path = rgb(178, 210, 242),
		lamp = rgb(200, 170, 255),
		arch = rgb(140, 156, 196),
		patches = { rgb(186, 216, 246), rgb(206, 228, 252) },
		patchMaterial = M.Ice,
	},
	-- 5. Око Бури: зловещее, фиолет и золото на чёрном
	{
		ground = rgb(62, 52, 82),
		groundMat = M.Basalt,
		dirt = rgb(52, 44, 70),
		rock = rgb(50, 42, 64),
		crack = rgb(186, 104, 255),
		gold = rgb(255, 200, 80),
		path = rgb(44, 38, 56),
		lamp = rgb(255, 200, 90),
		arch = rgb(56, 46, 72),
		patches = { rgb(72, 60, 94), rgb(52, 44, 66), rgb(84, 68, 106) },
	},
}

----------------------------------------------------------------------
-- Ориентиры
----------------------------------------------------------------------

-- 1. Старая мельница-громоотвод: шестигранная каменная башня ярусами, шатёр-пирамида, 4 крыла,
-- медный громоотвод с неоновым гранёным остриём
local function windmill(parent, pos, facing, rng, accent)
	local m = B.model(parent, "Landmark_Windmill")
	local stone = rgb(182, 172, 160)
	local base = B.facing(pos, facing)
	local yaw = B.yawOf(facing)
	local y = 0
	local R = 5.2
	for t = 1, 4 do
		local h = 5
		local col = if t % 2 == 0 then B.tint(stone, 0.4) else B.shade(stone, 0.25)
		B.hexPrism(m, pos + Vector3.new(0, y + h / 2, 0), R, h, yaw + math.pi / 6, B.vary(col, rng, 0.02), { Shadow = true, Collide = t <= 2 })
		y += h
		R -= 0.65
		if t == 2 or t == 4 then
			-- карниз-пояс: тёмное дерево
			B.hexPlate(m, pos + Vector3.new(0, y, 0), R + 1.05, 0.6, yaw + math.pi / 6, 0, nil, rgb(110, 78, 60), B.deco())
		end
	end
	-- дверь и окошки (тёплый свет внутри)
	B.block(m, base * CFrame.new(0, 2.2, -4.6), Vector3.new(2.6, 4.4, 0.4), P.WOOD_DARK, B.deco())
	local win = B.block(m, base * CFrame.new(0, 12, -3.95), Vector3.new(1.4, 1.8, 0.3), rgb(255, 200, 120), B.neon())
	B.light(win, rgb(255, 190, 110), 14, 0.8)
	B.block(m, base * CFrame.new(2.6, 7, -3.3) * CFrame.Angles(0, math.rad(30), 0), Vector3.new(1.2, 1.6, 0.3), rgb(255, 200, 120), B.neon())
	-- шатровая крыша: настоящая пирамида
	local roof = rgb(176, 76, 62)
	B.pyramid4(m, pos + Vector3.new(0, y + 0.3, 0), (R + 1.5) * 2, 6.5, yaw + math.rad(45), roof, B.deco({ Shadow = true }))
	local top = y + 6.8
	-- громоотвод: медный шпиль, изоляторы и гранёное неоновое остриё
	local copper = P.COPPER
	B.block(m, CFrame.new(pos + Vector3.new(0, top + 3, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.45, 8, 0.45), copper, B.deco({ Material = M.Metal }))
	for k = 0, 1 do
		B.cylY(m, pos + Vector3.new(0, top + 1.6 + k * 1.8, 0), 0.3, 1.3 - k * 0.3, P.PORCELAIN, B.deco())
	end
	local tip = B.gem(m, pos + Vector3.new(0, top + 7.6, 0), 1.2, 0.4, accent, B.neon())
	B.light(tip, accent, 30, 2)
	-- провод громоотвода по стене вниз
	B.bar(m, (base * CFrame.new(1.6, top - 2, -1.6)).Position, (base * CFrame.new(4.2, 0.5, -3.4)).Position, 0.25, 0.25, copper, B.deco({ Material = M.Metal }))
	-- ступица и 4 крыла: брус, полотно и две рейки (крылья развёрнуты с разбросом, не ровным крестом)
	local hubPos = base * CFrame.new(0, 15.5, -4.4)
	B.cyl(m, hubPos * CFrame.Angles(0, math.pi / 2, 0), 2, 1.6, P.WOOD_DARK, B.deco())
	local rot = rng:range(0, 1)
	for k = 0, 3 do
		local arm = hubPos * CFrame.new(0, 0, -1.1) * CFrame.Angles(0, 0, rot + k * math.pi / 2 + rng:range(-0.06, 0.06))
		B.block(m, arm * CFrame.new(0, 7, 0), Vector3.new(0.7, 14, 0.5), P.WOOD, B.deco({ Shadow = true }))
		B.block(m, arm * CFrame.new(1.75, 8, -0.05), Vector3.new(2.8, 11, 0.2), B.vary(rgb(240, 228, 206), rng, 0.02), B.deco({ Material = M.Fabric, Shadow = true }))
		for r = 0, 1 do
			B.block(m, arm * CFrame.new(1.75, 4.5 + r * 6, -0.2), Vector3.new(3.1, 0.3, 0.2), P.WOOD_DARK, B.deco())
		end
	end
	return m
end

-- 2. Медная вышка: решётчатая башня из 4 сужающихся ног, раскосы, площадка, гранёный неоновый маяк
local function copperTower(parent, pos, facing, rng, accent, copper, patina)
	local m = B.model(parent, "Landmark_CopperTower")
	local H = 44
	local base = B.facing(pos, facing)
	local function leg(sx, sz, t)
		local w = 6.5 * (1 - t) + 1.6 * t
		return (base * CFrame.new(sx * w, t * H, sz * w)).Position
	end
	local levels = { 0, 0.22, 0.42, 0.6, 0.76, 0.9 }
	local corners = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
	for _, s in corners do
		for li = 1, #levels - 1 do
			B.bar(m, leg(s[1], s[2], levels[li]), leg(s[1], s[2], levels[li + 1]), 1.0, 1.0, B.vary(copper, rng, 0.03), { Material = M.Metal, Shadow = true, Collide = li == 1 })
		end
	end
	-- пояса и раскосы (раскосы — бирюзовая патина)
	for li = 2, #levels do
		for c = 1, 4 do
			local a, b = corners[c], corners[c % 4 + 1]
			B.bar(m, leg(a[1], a[2], levels[li]), leg(b[1], b[2], levels[li]), 0.5, 0.5, B.shade(copper, 0.6), B.deco({ Material = M.Metal }))
			if li <= #levels - 1 and (li + c) % 2 == 0 then
				B.bar(m, leg(a[1], a[2], levels[li - 1]), leg(b[1], b[2], levels[li]), 0.35, 0.35, patina, B.deco({ Material = M.Metal }))
			end
		end
	end
	-- светящиеся пояса-изоляторы
	for li = 3, #levels - 1, 2 do
		local y = levels[li] * H
		local cf = base * CFrame.new(0, y + 0.6, 0)
		local w = 6.5 * (1 - levels[li]) + 1.6 * levels[li]
		B.block(m, cf, Vector3.new(w * 2 + 0.6, 0.3, 0.3), accent, B.neon())
		B.block(m, cf, Vector3.new(0.3, 0.3, w * 2 + 0.6), accent, B.neon())
	end
	-- площадка, шпиль, изоляторы и маяк
	local topY = levels[#levels] * H
	B.block(m, base * CFrame.new(0, topY + 0.3, 0), Vector3.new(5, 0.6, 5), B.shade(copper, 1), B.deco({ Material = M.Metal }))
	B.block(m, base * CFrame.new(0, (topY + H + 6) / 2, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.6, H + 6 - topY, 0.6), copper, B.deco({ Material = M.Metal }))
	for k = 0, 2 do
		B.cylY(m, (base * CFrame.new(0, topY + 2 + k * 1.4, 0)).Position, 0.3, 2.2 - k * 0.5, P.PORCELAIN, B.deco())
	end
	local beacon = B.gem(m, (base * CFrame.new(0, H + 7, 0)).Position, 2.2, 0.3, accent, B.neon())
	B.light(beacon, accent, 34, 2)
	-- бетонные опоры под ногами
	for _, s in corners do
		B.block(m, CFrame.new(leg(s[1], s[2], 0) + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, B.yawOf(facing), 0), Vector3.new(2.6, 1.4, 2.6), rgb(128, 112, 108), {})
	end
	-- трансформаторная будка у подножия с зигзагом-«осторожно»
	B.block(m, base * CFrame.new(0, 2, 0), Vector3.new(4, 4, 3.5), B.shade(copper, 1.2), { Material = M.Metal })
	B.zigzag(m, (base * CFrame.new(0, 3.4, -1.8)).Position, (base * CFrame.new(0.2, 1.0, -1.8)).Position, 3, 0.3, accent, B.neon(), base.LookVector * -1)
	return m
end

-- 3. Гигантский стеклянный фульгурит (из того же генератора, что и коллекционные) на гранёном постаменте
local function giantFulgurite(parent, pos, rng, glass, glow, Fulgurite, stone, outside)
	local m = B.model(parent, "Landmark_Fulgurite")
	local spec = Fulgurite.generate(1010, "gold", nil) -- «Корона»: пышная и симметричная
	local scale = 5.4
	-- стебли начинаются прямо на постаменте (верх 1.2), каменные глыбы основания не строим;
	-- разворот выбираем так, чтобы ни одна ветка не заходила в игровую зону
	local bestYaw, bestScore = 0, -math.huge
	for k = 0, 11 do
		local yaw = k * math.pi / 6 + rng:range(-0.1, 0.1)
		local cf0 = CFrame.new(pos + Vector3.new(0, 1.2 - 0.55 * scale, 0)) * CFrame.Angles(0, yaw, 0)
		local score = math.huge
		for _, ps in spec.Parts do
			if ps.Kind ~= "base" then
				score = math.min(score, outside((cf0 * CFrame.new(ps.CFrame.Position * scale)).Position))
			end
		end
		if score > bestScore then
			bestYaw, bestScore = yaw, score
		end
	end
	local base = CFrame.new(pos + Vector3.new(0, 1.2 - 0.55 * scale, 0)) * CFrame.Angles(0, bestYaw, 0)
	B.hexPlate(m, pos + Vector3.new(0, 0.6, 0), 7.4, 1.2, rng:range(0, 1), 0, nil, B.shade(stone, 0.6), { Shadow = true })
	B.hexPlate(m, pos + Vector3.new(0, 1.25, 0), 6.2, 0.3, rng:range(0, 1), 0, nil, B.mix(glass, rgb(60, 50, 60), 0.35), B.deco({ Reflectance = 0.15 }))
	for _, ps in spec.Parts do
		local cf = base * (CFrame.new(ps.CFrame.Position * scale) * (ps.CFrame - ps.CFrame.Position))
		local size = ps.Size * scale
		if ps.Kind ~= "base" then
			local col, opts
			if ps.Kind == "glass" then
				col = B.vary(glass, rng, 0.03)
				opts = B.deco({ Material = M.Glass, Transparency = 0.3, Shadow = false })
			elseif ps.Kind == "core" then
				col = B.tint(glow, 0.6)
				opts = B.neon()
			else -- tip
				col = B.tint(glow, 1)
				opts = B.neon()
			end
			-- форма детали — как в генераторе (Block / Cylinder / Ball)
			if ps.Shape == "Cylinder" then
				B.cyl(m, cf, size.X, math.min(size.Y, size.Z), col, opts)
			elseif ps.Shape == "Ball" then
				B.ball(m, cf.Position, math.min(size.X, size.Y, size.Z), col, opts)
			else
				B.block(m, cf, size, col, opts)
			end
		end
	end
	local light = B.block(m, CFrame.new(pos + Vector3.new(0, 12, 0)), Vector3.new(1, 1, 1), glow, B.deco({ Transparency = 1, Shadow = false }))
	B.light(light, glow, 40, 2.2)
	return m, spec.Height * scale
end

-- 4. Ледяной шпиль: витая колонна из повёрнутых брусков с зазорами, сквозь которые видна неоновая жила;
-- остриё-пирамида и гранёная звезда, ступенчатый снежный холм и кристаллы у подножия
local function iceSpire(parent, pos, rng, ice, accent, snow, outside)
	local m = B.model(parent, "Landmark_IceSpire")
	local H = 46
	local n = 8
	local y = 0.4
	for k = 1, n do
		local t = (k - 1) / n
		local w = 8.2 * (1 - t) ^ 0.85 + 1.4
		local h = H / n - 0.55
		local cf = CFrame.new(pos + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, k * 0.42, 0) * CFrame.Angles(rng:range(-0.04, 0.04), 0, rng:range(-0.04, 0.04))
		-- низ холоднее и темнее, верх светлее и теплее (тон по высоте)
		local col = if t < 0.3 then B.shade(ice, 0.5) elseif t > 0.7 then B.tint(ice, 1) else ice
		B.block(m, cf, Vector3.new(w, h, w), B.vary(col, rng, 0.02), { Shadow = k <= 3, Collide = k <= 2, Reflectance = 0.08 })
		y += H / n
	end
	B.pyramid4(m, pos + Vector3.new(0, y - 0.2, 0), 2.4, 6, n * 0.42, B.tint(ice, 1.2), B.deco())
	-- неоновая жила по всей высоте (видна в зазорах) и гранёная звезда сверху
	B.block(m, CFrame.new(pos + Vector3.new(0, H * 0.5, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.3, H * 0.95, 1.3), accent, B.neon())
	local star = B.gem(m, pos + Vector3.new(0, y + 7.4, 0), 2.2, 0.3, accent, B.neon())
	B.light(star, accent, 36, 2)
	-- кристаллы у подножия (не по кругу: разные углы и размеры)
	local placed = 0
	for k = 1, 12 do
		local a = k / 5 * TAU + rng:range(-0.5, 0.5)
		local p = pos + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:range(6.5, 8.5)
		if placed < 4 and outside(p) > 2.5 then
			placed += 1
			P.crystals(m, p, rng, ice, rng:range(1.2, 1.9), if placed % 2 == 0 then accent else nil, nil)
		end
	end
	-- ступенчатый снежный холмик у подножия (без коллизий: шпиль у края игровой зоны)
	for k = 1, 2 do
		B.hexPlate(m, pos + Vector3.new(0, -0.35 + k * 0.4, 0), 9.5 - k * 2.6, 0.8, 0.3 * k, 0.5, rng, if k == 1 then B.shade(snow, 0.2) else snow, B.deco({ Material = M.Snow, Shadow = false }))
	end
	return m
end

-- 5. Золотой столб света: гранёный алтарь, 4 обелиска с рунами и сияющий столб до туч
local function lightPillar(parent, pos, rng, gold, crack, cloudY, outward)
	local m = B.model(parent, "Landmark_LightPillar")
	local dark = rgb(40, 34, 52)
	B.hexPlate(m, pos + Vector3.new(0, 0.6, 0), 7.4, 1.2, 0, 0, nil, dark, { Shadow = true })
	B.hexPlate(m, pos + Vector3.new(0, 1.35, 0), 6.6, 0.3, math.rad(30), 0, nil, gold, B.deco({ Material = M.Metal }))
	B.hexPlate(m, pos + Vector3.new(0, 1.6, 0), 5.8, 0.4, 0, 0, nil, rgb(56, 46, 72), B.deco())
	-- светящаяся «ступица»
	local coreBase = B.cylY(m, pos + Vector3.new(0, 1.95, 0), 0.5, 6, gold, B.neon())
	B.light(coreBase, gold, 40, 3)
	-- столб: яркое ядро и мягкое свечение вокруг (уходит в тучи)
	local h = cloudY - pos.Y + 10
	B.cylY(m, pos + Vector3.new(0, 2 + h / 2, 0), h, 2.6, B.tint(gold, 1), B.neon())
	B.cylY(m, pos + Vector3.new(0, 2 + h / 2, 0), h, 5.5, gold, B.neon({ Transparency = 0.82 }))
	B.cylY(m, pos + Vector3.new(0, 2 + h / 2, 0), h, 9, gold, B.neon({ Transparency = 0.93 }))
	-- обелиски с фиолетовыми рунами по диагоналям относительно «наружу» (к центру острова не выступают)
	local baseA = math.atan2(outward.Z, outward.X)
	for k = 0, 3 do
		local a = baseA + ({ -1, 1, -2, 2 })[k + 1] * math.rad(55)
		local p = pos + Vector3.new(math.cos(a) * 9.5, 0, math.sin(a) * 9.5)
		local hh = 9 + rng:range(-1, 1.5)
		local cf = CFrame.new(p + Vector3.new(0, hh / 2, 0)) * CFrame.Angles(0, -a, 0) * CFrame.Angles(rng:range(-0.03, 0.03), 0, rng:range(-0.03, 0.03))
		B.block(m, cf, Vector3.new(1.8, hh, 1.8), B.vary(dark, rng, 0.03), { Shadow = true })
		B.pyramid4(m, (cf * CFrame.new(0, hh / 2, 0)).Position, 1.8, 1.6, -a, B.tint(dark, 0.5), B.deco())
		B.zigzag(m, (cf * CFrame.new(0, hh / 2 - 1.5, -0.92)).Position, (cf * CFrame.new(0, -hh / 2 + 2.2, -0.92)).Position, 3, 0.32, crack, B.neon(), cf.LookVector * -1, 0.1)
		B.gem(m, p + Vector3.new(0, hh + 2.6, 0), 1, a, gold, B.neon())
	end
	return m
end

----------------------------------------------------------------------
-- Входная арка острова (≤ 16): столбы на цоколях, перекладина-вывеска SkewPlate, фонари, герб зоны из неона
----------------------------------------------------------------------
local function emblem(m, i, cf, col)
	local opts = B.neon()
	if i == 1 then
		-- лист: два клина
		B.wedge(m, cf * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.rad(-25)), Vector3.new(0.3, 2.2, 1.0), col, opts)
		B.wedge(m, cf * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, math.pi, math.rad(25)), Vector3.new(0.3, 2.2, 1.0), col, opts)
	elseif i == 2 then
		-- шестерня: диск и два скрещённых бруска-зубца
		B.cyl(m, cf * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 1.8, col, opts)
		B.block(m, cf * CFrame.new(0, 1.3, 0), Vector3.new(2.5, 0.5, 0.25), col, opts)
		B.block(m, cf * CFrame.new(0, 1.3, 0), Vector3.new(0.5, 2.5, 0.25), col, opts)
	elseif i == 3 then
		-- шип фульгурита: два ромбовых бруска с изломом
		B.block(m, cf * CFrame.new(-0.2, 0.9, 0) * CFrame.Angles(0, 0, math.rad(-12)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.5, 1.8, 0.5), col, opts)
		B.block(m, cf * CFrame.new(0.15, 2.2, 0) * CFrame.Angles(0, 0, math.rad(18)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.4, 1.4, 0.4), col, opts)
	elseif i == 4 then
		-- снежинка: три скрещённых тонких бруска
		for k = 0, 2 do
			B.block(m, cf * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, k * math.pi / 3), Vector3.new(0.25, 2.6, 0.25), col, opts)
		end
	else
		-- глаз: два диска (белок-кольцо и зрачок)
		B.cyl(m, cf * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.2, 2.2, col, opts)
		B.cyl(m, cf * CFrame.new(0, 1.3, -0.12) * CFrame.Angles(0, math.pi / 2, 0), 0.2, 0.9, rgb(30, 20, 46), B.deco())
	end
end

local function entranceArch(ctx, i, decor, ground)
	local Config, Zones = ctx.Config, ctx.Zones
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local th = THEMES[i]
	local C = g.Center
	local a = C + g.ToHub * (z.Radius - 3)
	local half = Config.BridgeWidth / 2 + 1.8
	local col = th.arch
	local metal = i == 2
	local arch = B.model(decor, "EntranceArch")
	for side = -1, 1, 2 do
		local p = ground(a + g.Right * side * half)
		B.block(arch, CFrame.new(p + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, B.yawOf(g.ToHub), 0), Vector3.new(2.8, 1.2, 2.8), B.shade(th.rock, 1), {})
		B.block(arch, CFrame.new(p + Vector3.new(0, 5.7, 0)) * CFrame.Angles(0, B.yawOf(g.ToHub), 0), Vector3.new(2, 9, 2), col, { Material = if metal then M.Metal else M.SmoothPlastic, Shadow = true })
		local lampTop = B.block(arch, CFrame.new(p + Vector3.new(0, 10.9, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.1, 1.3, 1.1), th.lamp, B.neon())
		B.light(lampTop, th.lamp, 18, 1.1)
		B.gem(arch, p + Vector3.new(0, 12.3, 0), 1.3, math.rad(45), B.shade(col, 0.8), B.deco())
	end
	-- перекладина-вывеска: SkewPlate с названием острова (лицом к мосту и с обратной стороны)
	local cf = B.facing(ground(a) + Vector3.new(0, 9.2, 0), g.ToHub)
	B.sign(arch, cf, half * 2 - 1.2, 2.8, { { Text = z.Name } }, { Back = true, Underline = z.Accent, Slant = 1.2, Thickness = 0.6, PixelsPerStud = 40 })
	emblem(arch, i, cf * CFrame.new(0, 1.4, 0), B.tint(z.Accent, 0.2))
	return arch
end

----------------------------------------------------------------------
-- Остров целиком
----------------------------------------------------------------------
function ZonesMap.build(ctx, i, parent)
	local Config, Zones = ctx.Config, ctx.Zones
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local th = THEMES[i]
	local C = g.Center
	local R, PR = z.Radius, z.PlayRadius
	local GY = z.GroundY
	local rng = B.rng(1000 + i * 977)
	local model = B.model(parent, "Island_" .. i)
	local decor = B.model(model, "Decor")
	local flora = B.model(model, "Flora")
	local accent = z.Accent

	-- подвески снизу по теме
	local hang
	if i == 1 then
		hang = function(m, p, out, r)
			local len = r:range(4, 8)
			local q = p - Vector3.new(0, len, 0) + out * 0.8 + W * 0.8
			B.diamondBar(m, p, q, r:range(0.35, 0.55), B.vary(B.shade(th.trunk, 0.6), r, 0.04), B.deco({ Shadow = false }))
			if r:chance(0.5) then
				B.diamondBar(m, q, q + Vector3.new(r:range(-0.6, 0.6), -r:range(1.5, 3), r:range(-0.6, 0.6)), 0.3, B.shade(th.trunk, 1), B.deco({ Shadow = false }))
			end
		end
	elseif i == 2 then
		hang = function(m, p, out, r)
			local q = p + out * 2.5 - Vector3.new(0, 1, 0)
			local col = if r:chance(0.35) then th.patina else B.vary(th.copper, r, 0.04)
			B.rod(m, p - out, q, 1, col, B.deco({ Material = M.Metal }))
			B.rod(m, q, q - Vector3.new(0, r:range(2, 5), 0), 1, col, B.deco({ Material = M.Metal }))
			B.block(m, B.facing(q, out), Vector3.new(1.25, 1.25, 1.25), B.shade(th.copper, 1), B.deco({ Material = M.Metal }))
		end
	elseif i == 3 then
		hang = function(m, p, out, r)
			local len = r:range(3, 6)
			local q = p - Vector3.new(0, len, 0) + out * 0.5 + W * 0.5
			B.diamondBar(m, p, q, 1.2, th.glass, B.deco({ Material = M.Glass, Transparency = 0.25, Shadow = false }))
			B.diamondBar(m, p, q, 0.42, accent, B.neon())
		end
	elseif i == 4 then
		hang = function(m, p, out, r)
			for k = 0, r:int(0, 1) do
				local len = r:range(3, 7)
				local q = p + out * (0.5 + k * 0.9) + Vector3.new(r:range(-1, 1), 0, r:range(-1, 1))
				local cf = CFrame.new(q - Vector3.new(0, len / 2, 0)) * CFrame.Angles(0, r:range(0, 3), 0)
				B.wedge(m, cf * CFrame.Angles(math.pi, 0, 0), Vector3.new(r:range(0.8, 1.4), len, r:range(0.8, 1.4)), B.vary(B.tint(th.ice, 0.4), r, 0.03), B.deco({ Reflectance = 0.1, Shadow = false }))
			end
		end
	else
		hang = function(m, p, out, r)
			local len = r:range(3, 6)
			local q = p - Vector3.new(0, len, 0) + out * 0.6
			B.diamondBar(m, p, q, 1.3, B.vary(rgb(120, 70, 200), r, 0.04), B.deco({ Material = M.Glass, Transparency = 0.15, Shadow = false }))
			B.diamondBar(m, p, q, 0.45, th.crack, B.neon())
		end
	end

	local body = Island.body(model, {
		name = "Ground",
		center = C,
		radius = R,
		seed = 100 + i * 31,
		segments = 28,
		base = 2.2,
		amp = R * 0.1,
		capes = 2,
		top = th.ground,
		topMaterial = th.groundMat,
		dirt = th.dirt,
		rock = th.rock,
		depth = 62 + i * 3,
		openings = { g.ToHub },
		openHalfDeg = 9,
		drips = if i == 5 then 0 else 10,
		dripColor = if i == 4 then rgb(244, 248, 255) else nil,
		hang = hang,
		hangCount = if i == 4 then 10 else 8,
		energy = accent,
		walls = { radius = R + 0.8, height = 18 },
		wallParent = ctx.Walls,
	})
	local outline = body.outline
	local S = newSampler(C, rng, outline)

	-- запретные области: коридор от моста, подстанция, ориентир
	for k = 0, 6 do
		S.reserve(C + g.ToHub * (R + 2 - k * 6), 10)
	end
	local stationOut = B.flat(g.SellPad - C).Unit
	S.reserve(g.SellPad, 9)
	S.reserve(g.SellPad + stationOut * 12, 9)
	S.reserve(g.Landmark, 12)
	-- игровая зона: всё с коллизией и крупное — только снаружи
	local rimMin = PR + 2.5
	local far = math.atan2(g.Dir.Z, g.Dir.X) -- дальняя от моста сторона
	local farBias = { far, math.rad(110) }

	local function ground(pos)
		return Vector3.new(pos.X, GY, pos.Z)
	end
	-- насколько точка дальше границы игровой зоны (отрицательно — внутри)
	local function outsideBy(p)
		return flatDist(p, C) - PR
	end

	-- годится ли деталь с коллизией: все её углы выше земли — снаружи игровой зоны и внутри кромки
	local function fitsOutside(cf, size)
		local s = size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, zz in { -1, 1 } do
					local c = cf:PointToWorldSpace(Vector3.new(s.X * x, s.Y * y, s.Z * zz))
					local d = flatDist(c, C)
					if c.Y > GY + 0.05 and d < PR + 0.6 then
						return false
					end
					if d > outline(math.atan2(c.Z - C.Z, c.X - C.X)) - 0.8 then
						return false
					end
				end
			end
		end
		return true
	end

	-- 1) «чаша»: гребни вне игровой зоны на дальней стороне — пологий скат-клин к поляне (верх +3…+7)
	-- и гранёный «гребешок» сверху; рамка игровой зоны без стен
	local ridges = 0
	for _ = 1, 50 do
		if ridges >= 4 then
			break
		end
		local a = far + rng:range(-1.7, 1.7)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local len = rng:range(14, 20)
		local d = rng:range(9, 12)
		local top = rng:range(3, 6.5)
		local rr = PR + 1.5 + d / 2 + rng:range(0, 2.5)
		local pos = ground(C + out * rr) + Vector3.new(0, top / 2 - 0.3, 0)
		-- клин: высокая грань (+Z) снаружи, скат смотрит на поляну
		local cf = B.facing(pos, out) * CFrame.Angles(0, math.pi + rng:range(-0.12, 0.12), 0)
		local size = Vector3.new(len, top, d)
		local capCf = B.facing(pos + out * (d / 2 - 1.8) + Vector3.new(0, top / 2 + 0.2, 0), out) * CFrame.Angles(math.rad(rng:range(-16, -8)), rng:range(-0.2, 0.2), math.rad(rng:range(-6, 6)))
		local capSize = Vector3.new(len * rng:range(0.55, 0.8), 2.2, 4)
		if fitsOutside(cf, size) and fitsOutside(capCf, capSize) and S.free(pos, len * 0.42) then
			B.wedge(decor, cf, size, B.vary(B.tint(th.ground, 0.25), rng, 0.02), { Material = th.groundMat, Shadow = true, Name = "Ridge" })
			B.block(decor, capCf, capSize, B.vary(B.shade(th.ground, 0.2), rng, 0.02), { Material = th.groundMat, Shadow = true, Name = "Ridge" })
			S.take(pos, len * 0.42)
			ridges += 1
		end
	end
	-- мысы: приподнятая терраса за пределом игровой зоны
	for _, cape in body.capes do
		local out = Vector3.new(math.cos(cape.angle), 0, math.sin(cape.angle))
		local rr = math.max(PR + 9, outline(cape.angle) - 8)
		local pos = ground(C + out * rr) + Vector3.new(0, rng:range(1, 2) - 2, 0)
		local cf = B.facing(pos, out) * CFrame.Angles(0, rng:range(-0.3, 0.3), 0)
		if fitsOutside(cf, Vector3.new(12, 4, 10)) and S.free(pos, 6) then
			B.block(decor, cf, Vector3.new(12, 4, 10), B.vary(B.tint(th.ground, 0.2), rng, 0.02), { Material = th.groundMat, Shadow = true, Name = "Terrace" })
			B.block(decor, cf * CFrame.new(0, -1.2, 0) * CFrame.Angles(0, 0.2, 0), Vector3.new(11, 3.2, 10.6), th.dirt, B.deco({ Shadow = false }))
			S.take(pos, 6)
		end
	end
	-- холмы: ступенчатые шестигранные плиты (только снаружи игровой зоны)
	local hillCount = if i == 3 then 4 elseif i == 5 then 2 else 3
	for _ = 1, hillCount do
		local Rh = rng:range(6.5, 9)
		local pos = S.ring(PR + Rh + 1.5, R + 2, Rh, 40)
		if pos then
			Island.hill(decor, ground(pos), Rh, if Rh > 7.5 then 3 else 2, th.ground, th.groundMat, rng, rng:range(1.4, 2.2))
		end
	end

	-- 2) входная арка с названием острова (на краю у моста)
	entranceArch(ctx, i, decor, ground)

	-- 3) дорожка из плоских камней: от моста к точке появления и к подстанции (не выше GroundY + 0.04)
	local function pathStones(a, b, count, color)
		for k = 0, count do
			local t = k / count
			local p = a:Lerp(b, t) + g.Right * rng:range(-2.2, 2.2) + g.ToHub * rng:range(-0.6, 0.6)
			local w, d = rng:range(2, 3.4), rng:range(1.8, 3)
			B.block(flora, CFrame.new(ground(p) + Vector3.new(0, -0.035, 0)) * CFrame.Angles(0, rng:range(0, 3.14), 0), Vector3.new(w, 0.15, d), B.vary(color, rng, 0.04), B.deco({ Shadow = false, Name = "PathStone" }))
		end
	end
	pathStones(C + g.ToHub * (R - 1), g.Spawn - Vector3.new(0, 3, 0) - g.ToHub * 4, 8, th.path)
	pathStones(g.Spawn - Vector3.new(0, 3, 0), g.SellPad - stationOut * 1 + g.ToHub * 5, 5, th.path)

	-- 4) пятна другого оттенка на земле (оживляют плоскую игровую зону): 2 перекрывающихся диска,
	-- каждый на своей высоте (+0.012 / +0.027), без коллизий — кольца рисуются выше (+0.05 и больше)
	local function groundPatch(pos, size)
		local col = rng:pick(th.patches)
		for k = 1, 2 do
			local off = if k == 1 then Vector3.zero else rng:disc(size * 0.4) + W * size * 0.25
			local d = size * rng:range(0.55, 1)
			local top = if k == 1 then 0.012 else 0.027
			B.cylY(flora, ground(pos + off) + Vector3.new(0, top - 0.05, 0), 0.1, d, B.vary(col, rng, 0.012), B.deco({ Material = th.patchMaterial or th.groundMat, Shadow = false, Name = "Patch" }))
		end
	end
	for _ = 1, 7 do
		local p = C + rng:disc(PR - 6)
		if flatDist(p, g.SellPad) > 10 then
			groundPatch(p, rng:range(10, 20))
		end
	end

	-- мелкая флора внутри игровой зоны (без коллизий)
	local function insideSpot(minGap)
		for _ = 1, 30 do
			local p = C + rng:disc(PR - 3)
			if flatDist(p, g.SellPad) > 9 and flatDist(p, g.Spawn) > minGap then
				return ground(p)
			end
		end
		return nil
	end
	local function isHero(p)
		return flatDist(p, g.Spawn) < 25
	end

	-- рощи: одно большое дерево и меньшие вокруг; bigFn/smallFn(pos, scale)
	local function grove(minR, maxR, n, bigFn, smallFn, bias)
		local c = S.ring(minR, maxR, 4.5, 50, bias)
		if not c then
			return 0
		end
		bigFn(ground(c), rng:range(1.15, 1.3))
		local placed = 1
		for _ = 1, n - 1 do
			local p = S.near(c, 6, 10, minR, maxR, 3.6)
			if p then
				smallFn(ground(p), rng:range(0.8, 1.0))
				placed += 1
			end
		end
		return placed
	end
	-- куст у подножия дерева или камня
	local function anchorBush(at, pal, scale)
		local p = S.near(at, 3.2, 5, rimMin, R + 4, 1.6)
		if p then
			P.bush(decor, ground(p), rng, pal, scale)
		end
	end

	local landmarkFacing = -g.Dir -- ориентир «смотрит» к центру острова

	if i == 1 then
		----------------------------------------------------------------
		-- Грозовой Луг
		----------------------------------------------------------------
		local pal = { trunk = th.trunk, leafA = th.leafA, leafB = th.leafB, rock = th.rock, fruit = rgb(230, 70, 70), berries = rgb(220, 60, 80) }
		windmill(decor, ground(g.Landmark), landmarkFacing, rng, accent)
		local treeAt = {}
		local function bigTree(p, s)
			P.tree(decor, p, rng, pal, s)
			table.insert(treeAt, p)
		end
		local function smallTree(p, s)
			if rng:chance(0.35) then
				P.poplar(decor, p, rng, pal, s)
			else
				P.tree(decor, p, rng, pal, s * 0.9)
			end
			table.insert(treeAt, p)
		end
		for k = 1, 4 do
			grove(rimMin + 2, R + 3, rng:int(3, 4), bigTree, smallTree, if k <= 2 then farBias else nil)
		end
		for _ = 1, 3 do
			local p = S.ring(rimMin + 2, R + 3, 4.5)
			if p then
				bigTree(ground(p), rng:range(0.9, 1.1))
			end
		end
		-- ветреные деревья на наветренном краю (штормовой акцент)
		local windward = math.atan2(-W.Z, -W.X)
		for _ = 1, 3 do
			local p = S.ring(rimMin + 3, R + 3, 4.5, 40, { windward, math.rad(70) })
			if p then
				P.windyTree(decor, ground(p), rng, pal)
			end
		end
		for k = 1, math.min(#treeAt, 8) do
			anchorBush(treeAt[k], pal)
		end
		local rockAt = {}
		for _ = 1, 5 do
			local p = S.ring(rimMin, R + 4, 2.8)
			if p then
				P.rock(decor, ground(p), rng, pal)
				table.insert(rockAt, p)
			end
		end
		for k = 1, math.min(#rockAt, 3) do
			anchorBush(rockAt[k], pal, 0.85)
		end
		-- цветочные полосы у подножий деревьев (снаружи игровой зоны)
		for k = 1, math.min(#treeAt, 4) do
			local p = S.near(treeAt[k], 4, 7, rimMin, R + 2, 2)
			if p then
				P.flowerStrip(flora, ground(p), rng, th.flowers, 5, false, 5)
			end
		end
		for _ = 1, 3 do
			local p = S.ring(rimMin, R + 4, 2.4)
			if p then
				P.flagstone(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 3 do
			local p = S.ring(rimMin, R + 4, 1.2)
			if p then
				P.mushroom(decor, ground(p), rng, rng:pick({ rgb(220, 64, 60), rgb(240, 150, 60) }))
			end
		end
		-- заборчики вдоль дуги края (ломаная с разными углами) и тополь у каждого
		for _ = 1, 3 do
			local a0 = rng:range(0, TAU)
			local pts = {}
			local rr = PR + rng:range(4, 7)
			for k = 0, 3 do
				local a = a0 + k * rng:range(0.07, 0.11)
				table.insert(pts, C + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr))
				rr += rng:range(-1.2, 1.2)
			end
			local ok = true
			for _, p in pts do
				if not S.free(p, 1) or flatDist(p, C) < PR + 1.5 then
					ok = false
				end
			end
			if ok then
				for k = 1, #pts - 1 do
					if rng:chance(0.85) then
						P.fence(decor, ground(pts[k]), ground(pts[k + 1]), th.trunk, rng)
					end
				end
				for _, p in pts do
					S.take(p, 1.5)
				end
				local pp = S.near(pts[#pts], 3, 5, rimMin + 1, R + 2, 2.6)
				if pp then
					P.poplar(decor, ground(pp), rng, pal)
				end
			end
		end
		-- колодец у края и тюки сена
		do
			local p = S.ring(rimMin + 3, R - 3, 4)
			if p then
				P.well(decor, ground(p), rng)
			end
		end
		for _ = 1, 2 do
			local p = S.ring(rimMin + 2, R, 3)
			if p then
				P.hayBales(decor, ground(p), rng)
			end
		end
		-- цветы полосами вдоль ветра и травинки внутри
		for _ = 1, 6 do
			local p = insideSpot(4)
			if p then
				P.flowerStrip(flora, p, rng, th.flowers, rng:int(5, 6), isHero(p))
			end
		end
		for _ = 1, 18 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, th.ground, nil, isHero(p))
			end
		end
	elseif i == 2 then
		----------------------------------------------------------------
		-- Медные Холмы
		----------------------------------------------------------------
		local pal = { trunk = th.trunk, leafA = th.leafA, rock = th.rock, vein = accent, copper = th.copper }
		copperTower(decor, ground(g.Landmark), landmarkFacing, rng, accent, th.copper, th.patina)
		local rockAt = {}
		for _ = 1, 10 do
			local p = S.ring(rimMin + 1, R + 3, 3.5)
			if p then
				P.veinRock(decor, ground(p), rng, pal)
				table.insert(rockAt, p)
			end
		end
		for _ = 1, 5 do
			local p = S.ring(rimMin + 3, R, 5)
			if p then
				-- труба идёт вдоль края (по касательной), а не в игровую зону; часть — в бирюзовой патине
				local out = B.flat(p - C).Unit
				local tangent = Vector3.new(-out.Z, 0, out.X) * rng:sign()
				local ppal = if rng:chance(0.35) then { copper = th.patina, vein = accent } else pal
				P.pipe(decor, ground(p), rng, ppal, nil, (tangent + out * 0.25).Unit)
			end
		end
		-- сухие деревья: две маленькие рощицы и одиночки
		local function dead(p, s)
			P.deadTree(decor, p, rng, pal, s)
		end
		grove(rimMin + 1, R + 3, 3, dead, dead, farBias)
		grove(rimMin + 1, R + 3, 2, dead, dead)
		for _ = 1, 3 do
			local p = S.ring(rimMin + 1, R + 3, 3.5)
			if p then
				P.deadTree(decor, ground(p), rng, pal)
			end
		end
		for k = 1, math.min(#rockAt, 6) do
			anchorBush(rockAt[k], pal, rng:range(0.6, 0.9))
		end
		for _ = 1, 5 do
			local p = S.ring(rimMin, R + 4, 2.8)
			if p then
				P.rock(decor, ground(p), rng, pal)
			end
		end
		-- вагонетки с рудой на рельсах (вдоль края)
		for _ = 1, 2 do
			local p = S.ring(rimMin + 4, R - 4, 5)
			if p then
				local out = B.flat(p - C).Unit
				P.mineCart(decor, ground(p), Vector3.new(-out.Z, 0, out.X), rng, accent)
			end
		end
		-- бочки и ящики шахтёров
		for _ = 1, 3 do
			local p = S.ring(rimMin + 2, R, 3)
			if p then
				P.barrel(decor, ground(p), rng)
				P.crate(decor, ground(p + Vector3.new(rng:range(1.8, 2.4), 0, rng:range(-1, 1))), rng)
			end
		end
		for _ = 1, 22 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, B.tint(th.ground, 0.3), nil, isHero(p))
			end
		end
		-- рыжие цветы-«медянки» полосами по ветру
		for _ = 1, 5 do
			local p = insideSpot(5)
			if p then
				P.flowerStrip(flora, p, rng, { rgb(255, 196, 90), rgb(255, 130, 70), rgb(240, 230, 200) }, 4, isHero(p))
			end
		end
	elseif i == 3 then
		----------------------------------------------------------------
		-- Стеклянные Дюны
		----------------------------------------------------------------
		local pal = { cactus = th.cactus, cactusFlower = th.cactusFlower, stone = th.stone, rock = th.rock }
		giantFulgurite(decor, ground(g.Landmark), rng, th.glass, accent, ctx.Fulgurite, th.stone, outsideBy)
		for _ = 1, 4 do
			local p = S.ring(rimMin + 4, R - 2, 6)
			if p then
				P.ruinArch(decor, ground(p), rng, pal)
			end
		end
		-- оазис: прудик, пальмы, камыши
		do
			local p = S.ring(rimMin + 7, R - 6, 8)
			if p then
				local o = B.model(decor, "Oasis")
				B.cylY(o, ground(p) + Vector3.new(0, -0.02, 0), 0.12, 9, rgb(70, 170, 190), B.deco({ Reflectance = 0.2, Shadow = false, Name = "Water" }))
				B.cylY(o, ground(p) + Vector3.new(0, -0.05, 0), 0.12, 10.5, B.shade(th.ground, 0.3), B.deco({ Shadow = false }))
				for _ = 1, 2 do
					local a = rng:range(0, TAU)
					P.palm(o, ground(p + Vector3.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6)), rng)
				end
				for _ = 1, 4 do
					local a = rng:range(0, TAU)
					P.tuft(o, ground(p + Vector3.new(math.cos(a) * 4.6, 0, math.sin(a) * 4.6)), rng, rgb(90, 150, 80), 1.6, true)
				end
			end
		end
		-- кактусы: группками по 2–3 и одиночками
		local function cact(p, s)
			P.cactus(decor, p, rng, pal, s)
		end
		for _ = 1, 3 do
			grove(rimMin + 1, R + 3, rng:int(2, 3), cact, cact)
		end
		for _ = 1, 3 do
			local p = S.ring(rimMin + 1, R + 3, 3)
			if p then
				cact(ground(p))
			end
		end
		for _ = 1, 9 do
			local p = S.ring(rimMin, R + 3, 2.8)
			if p then
				P.glassSpike(decor, ground(p), rng, th.glass, accent)
			end
		end
		for _ = 1, 5 do
			local p = S.ring(rimMin, R + 4, 2.8)
			if p then
				if rng:chance(0.5) then
					P.rock(decor, ground(p), rng, pal)
				else
					P.flagstone(decor, ground(p), rng, pal)
				end
			end
		end
		-- осколки стекла внутри (блёстки без коллизий)
		for _ = 1, 16 do
			local p = insideSpot(4)
			if p then
				local cf = CFrame.new(p + Vector3.new(0, 0.25, 0)) * B.windLean(rng:range(10, 30)) * CFrame.Angles(0, rng:range(0, 3), 0) * CFrame.Angles(0, math.rad(45), 0)
				B.block(flora, cf, Vector3.new(0.35, rng:range(0.6, 1.2), 0.35), th.glass, B.deco({ Material = M.Glass, Transparency = 0.2, Shadow = false, Name = "Shard" }))
			end
		end
		for _ = 1, 20 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, rgb(176, 160, 98), 0.8, isHero(p))
			end
		end
	elseif i == 4 then
		----------------------------------------------------------------
		-- Ледяной Пик
		----------------------------------------------------------------
		local pal = { needles = th.needles, snow = th.snow, trunk = th.trunk, rock = th.rock }
		iceSpire(decor, ground(g.Landmark), rng, th.ice, accent, th.snow, outsideBy)
		-- ели рощами по 3–4 разной высоты (меньше штук, но крупнее)
		local function pine(p, s)
			P.pine(decor, p, rng, pal, s)
		end
		local function pineSmall(p, s)
			P.pine(decor, p, rng, pal, rng:pick({ 0.85, 1.0 }) * (s + 0.1))
		end
		for k = 1, 3 do
			grove(rimMin + 2, R + 3, rng:int(3, 4), pine, pineSmall, if k <= 2 then farBias else nil)
		end
		for _ = 1, 2 do
			local p = S.ring(rimMin + 2, R + 3, 4.5)
			if p then
				pine(ground(p), rng:range(0.95, 1.2))
			end
		end
		for _ = 1, 6 do
			local p = S.ring(rimMin, R + 3, 2.5)
			if p then
				P.crystals(decor, ground(p), rng, th.ice, rng:range(0.9, 1.5), if rng:chance(0.4) then accent else nil, th.rock)
			end
		end
		for _ = 1, 5 do
			local p = S.ring(rimMin, R + 4, 2.8)
			if p then
				local r = P.rock(decor, ground(p), rng, pal)
				-- снежная шапка: плоская плита сверху
				B.block(r, CFrame.new(ground(p) + Vector3.new(0, 2.15 * 1.1, 0)) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(2.8, 0.45, 2.2), th.snow, B.deco({ Material = M.Snow, Shadow = false }))
			end
		end
		for _ = 1, 8 do
			local p = S.ring(rimMin, R + 2, 3)
			if p then
				P.drift(decor, ground(p), rng, th.snow)
			end
		end
		-- снеговик смотрит на игровую поляну
		do
			local p = S.ring(rimMin + 2, R - 3, 3)
			if p then
				P.snowman(decor, ground(p), C - p, rng)
			end
		end
		for _ = 1, 20 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, rgb(196, 214, 240), 0.9, isHero(p))
			end
		end
		for _ = 1, 10 do
			local p = insideSpot(4)
			if p then
				local cf = CFrame.new(p + Vector3.new(0, 0.3, 0)) * B.windLean(rng:range(8, 22)) * CFrame.Angles(0, rng:range(0, 3), 0) * CFrame.Angles(0, math.pi / 4, 0)
				B.block(flora, cf, Vector3.new(0.4, rng:range(0.7, 1.3), 0.4), B.tint(th.ice, 0.3), B.deco({ Reflectance = 0.1, Shadow = false, Name = "Shard" }))
			end
		end
	else
		----------------------------------------------------------------
		-- Око Бури
		----------------------------------------------------------------
		local pal = { rock = th.rock, crack = th.crack }
		lightPillar(decor, ground(g.Landmark), rng, th.gold, th.crack, GY + Config.CloudHeight, g.Dir)
		for _ = 1, 8 do
			local p = S.ring(rimMin + 1, R + 3, 3.5)
			if p then
				P.basalt(decor, ground(p), rng, pal)
			end
		end
		for k = 1, 8 do
			local p = S.ring(rimMin, R + 3, 2.8)
			if p then
				local cr = P.crystals(decor, ground(p), rng, rgb(130, 80, 220), rng:range(1, 1.6), th.crack, th.rock)
				if k % 3 == 1 then
					local lp = B.block(cr, CFrame.new(ground(p) + Vector3.new(0, 2.5, 0)), Vector3.new(0.5, 0.5, 0.5), th.crack, B.deco({ Transparency = 1, Shadow = false }))
					B.light(lp, th.crack, 18, 1.2)
				end
			end
		end
		-- светящиеся грибы (единственное исключение «неон на природе»)
		for _ = 1, 4 do
			local p = S.ring(rimMin, R + 3, 1.4)
			if p then
				P.mushroom(decor, ground(p), rng, th.crack, rng:range(0.8, 1.3), true)
			end
		end
		-- парящие камни над краем и над обрывом (без коллизий)
		for _ = 1, 12 do
			local a = rng:range(0, TAU)
			local d = rng:range(PR + 6, R + 14)
			local p = C + Vector3.new(math.cos(a) * d, rng:range(7, 24), math.sin(a) * d)
			if flatDist(p, C + g.ToHub * R) > 22 then
				P.floatRock(decor, p, rng, pal)
			end
		end
		-- неоновые трещины по земле у края (ломаные из тонких полосок)
		for _ = 1, 8 do
			local p = S.ring(rimMin, R - 2, 2)
			if p then
				local q = ground(p)
				local dir = B.dir(rng:range(0, 360))
				for _ = 1, rng:int(3, 4) do
					local nextQ = q + (dir + Vector3.new(rng:range(-0.6, 0.6), 0, rng:range(-0.6, 0.6))).Unit * rng:range(2, 4)
					if flatDist(nextQ, C) > PR + 1 and flatDist(nextQ, C) < outline(math.atan2(nextQ.Z - C.Z, nextQ.X - C.X)) - 1 then
						B.bar(flora, q + Vector3.new(0, 0.02, 0), nextQ + Vector3.new(0, 0.02, 0), rng:range(0.25, 0.45), 0.1, th.crack, B.neon())
						q = nextQ
					end
				end
			end
		end
		-- тёмные гранёные камешки внутри (плоские) и травинки
		for _ = 1, 20 do
			local p = insideSpot(3)
			if p then
				B.block(flora, CFrame.new(p + Vector3.new(0, -0.02, 0)) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(rng:range(0.6, 1.2), 0.1, rng:range(0.5, 1)), rgb(74, 62, 96), B.deco({ Shadow = false }))
			end
		end
		for _ = 1, 10 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, rgb(120, 90, 170), 0.7, isHero(p))
			end
		end
	end

	return model, body
end

ZonesMap.THEMES = THEMES

return ZonesMap
