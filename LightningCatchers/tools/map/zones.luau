--!nocheck
-- Пять островов: тело острова, рельеф и декор вне игровой зоны, мелкая флора внутри неё,
-- входная арка с названием, ориентир (landmark) каждого острова.
-- Правила: внутри PlayRadius земля плоская (GroundY), там только мелкие цветы/травинки без коллизий
-- и плоские камешки дорожки не выше GroundY + 0.04 (кольца рисуются выше).
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Island = require("./island")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local M = Enum.Material

local ZonesMap = {}

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
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
	-- точка в кольце [minR, maxR] от центра, не ближе r к краю острова и к другим объектам
	function S.ring(minR, maxR, r, tries)
		for _ = 1, tries or 40 do
			local th = rng:range(0, math.pi * 2)
			local d = rng:range(minR, maxR)
			local pos = C + Vector3.new(math.cos(th) * d, 0, math.sin(th) * d)
			if d + r <= outline(th) - 1.2 and S.free(pos, r) then
				S.take(pos, r)
				return pos
			end
		end
		return nil
	end
	return S
end

----------------------------------------------------------------------
-- Темы островов
----------------------------------------------------------------------
local rgb = B.rgb

local THEMES = {
	-- 1. Грозовой Луг
	{
		dirt = rgb(146, 100, 66),
		rock = rgb(132, 128, 136),
		rock2 = rgb(150, 136, 126),
		rockMaterial = M.Slate,
		hill = rgb(84, 158, 76),
		leaves = { rgb(66, 146, 62), rgb(88, 166, 68), rgb(116, 184, 78) },
		flowers = { rgb(255, 120, 160), rgb(255, 214, 90), rgb(250, 248, 255), rgb(196, 146, 255), rgb(255, 156, 96) },
		tuft = rgb(76, 150, 66),
		path = rgb(168, 162, 150),
		moss = rgb(86, 150, 70),
		lamp = rgb(255, 214, 150),
		arch = rgb(112, 80, 56),
		patches = { rgb(76, 150, 70), rgb(112, 182, 92), rgb(86, 160, 96) },
	},
	-- 2. Медные Холмы
	{
		dirt = rgb(150, 90, 56),
		rock = rgb(124, 98, 86),
		rock2 = rgb(150, 112, 88),
		rockMaterial = M.Slate,
		hill = rgb(168, 116, 66),
		leaves = { rgb(176, 112, 58), rgb(150, 96, 52), rgb(204, 146, 74) },
		tuft = rgb(196, 140, 76),
		path = rgb(92, 76, 70),
		copper = rgb(198, 112, 64),
		vein = rgb(255, 150, 70),
		lamp = rgb(255, 176, 100),
		arch = rgb(150, 86, 52),
		-- рыжие пятна и зеленоватая медная патина
		patches = { rgb(156, 106, 60), rgb(192, 140, 82), rgb(120, 150, 118) },
	},
	-- 3. Стеклянные Дюны
	{
		dirt = rgb(214, 174, 122),
		rock = rgb(190, 150, 108),
		rock2 = rgb(208, 164, 116),
		rockMaterial = M.Sandstone,
		hill = rgb(236, 206, 148),
		stone = rgb(200, 162, 118),
		cactus = rgb(92, 146, 82),
		cactusFlower = rgb(255, 120, 170),
		glass = rgb(150, 245, 236),
		glow = rgb(110, 240, 230),
		tuft = rgb(176, 160, 98),
		path = rgb(204, 168, 120),
		lamp = rgb(255, 210, 150),
		arch = rgb(196, 156, 110),
		patches = { rgb(220, 188, 130), rgb(240, 216, 166), rgb(206, 176, 128) },
	},
	-- 4. Ледяной Пик
	{
		dirt = rgb(204, 222, 246),
		rock = rgb(148, 166, 198),
		rock2 = rgb(124, 140, 182),
		rockMaterial = M.Slate,
		hill = rgb(240, 245, 255),
		ice = rgb(164, 210, 248),
		pine = { rgb(58, 118, 98), rgb(72, 134, 108), rgb(92, 152, 120) },
		tuft = rgb(210, 226, 246),
		path = rgb(170, 206, 240),
		lamp = rgb(200, 170, 255),
		arch = rgb(130, 150, 186),
		-- замёрзшие лужицы
		patches = { rgb(180, 214, 246), rgb(206, 228, 252) },
		patchMaterial = M.Ice,
	},
	-- 5. Око Бури
	{
		dirt = rgb(52, 44, 64),
		rock = rgb(48, 40, 60),
		rock2 = rgb(66, 50, 84),
		rockMaterial = M.Basalt,
		hill = rgb(60, 52, 74),
		crack = rgb(176, 96, 255),
		gold = rgb(255, 200, 80),
		tuft = rgb(90, 70, 120),
		path = rgb(40, 34, 50),
		lamp = rgb(255, 200, 90),
		arch = rgb(56, 46, 70),
		patches = { rgb(72, 60, 92), rgb(48, 42, 58), rgb(82, 66, 104) },
	},
}

----------------------------------------------------------------------
-- Ориентиры
----------------------------------------------------------------------

-- 1. Старая мельница-громоотвод: каменная башня, шатровая крыша, 4 крыла, громоотвод с неоновым остриём
local function windmill(parent, pos, facing, rng, accent)
	local m = B.model(parent, "Landmark_Windmill")
	local stone = rgb(176, 168, 156)
	local base = B.facing(pos, facing)
	-- башня: 4 сужающихся яруса (восьмигранник ≈ два повёрнутых бруска)
	local y = 0
	local w = 9
	for t = 1, 4 do
		local h = 5
		local col = B.vary(if t % 2 == 0 then stone else B.shade(stone, 0.06), rng, 0.03)
		for k = 0, 1 do
			B.block(m, base * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, k * math.pi / 4, 0), Vector3.new(w, h, w), col, { Material = M.Cobblestone, Shadow = true })
		end
		-- пояс-карниз
		B.block(m, base * CFrame.new(0, y + h, 0), Vector3.new(w + 0.8, 0.6, w + 0.8), rgb(120, 96, 76), B.deco({ Material = M.Wood }))
		y += h
		w -= 1.3
	end
	-- дверь и окошки (тёплый свет внутри)
	B.block(m, base * CFrame.new(0, 2.2, -4.55), Vector3.new(2.6, 4.4, 0.4), P.WOOD_DARK, B.deco({ Material = M.Wood }))
	local win = B.block(m, base * CFrame.new(0, 12, -3.85), Vector3.new(1.4, 1.8, 0.3), rgb(255, 200, 120), B.neon())
	B.light(win, rgb(255, 190, 110), 14, 0.8)
	B.block(m, base * CFrame.new(2.9, 7, -2.9) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(1.2, 1.6, 0.3), rgb(255, 200, 120), B.neon())
	-- шатровая крыша из 4 клиньев
	local roofW = w + 2.4
	local roofH = 6
	for q = 0, 3 do
		local cf = base * CFrame.new(0, y + roofH / 2, 0) * CFrame.Angles(0, q * math.pi / 2, 0) * CFrame.new(0, 0, -roofW / 4)
		B.wedge(m, cf, Vector3.new(roofW, roofH, roofW / 2), B.vary(rgb(150, 70, 56), rng, 0.03), B.deco({ Material = M.WoodPlanks, Shadow = true }))
	end
	local top = y + roofH
	-- громоотвод: шпиль, кольца и неоновое остриё
	B.rod(m, base * Vector3.new(0, top - 1, 0), base * Vector3.new(0, top + 7, 0), 0.5, rgb(196, 112, 66), B.deco({ Material = M.Metal }))
	for k = 0, 2 do
		B.cylY(m, (base * CFrame.new(0, top + 1 + k * 1.6, 0)).Position, 0.25, 1.3 - k * 0.25, rgb(220, 140, 80), B.deco({ Material = M.Metal }))
	end
	local tip = B.ball(m, (base * CFrame.new(0, top + 7.4, 0)).Position, 1.1, accent, B.neon())
	B.light(tip, accent, 30, 2)
	-- провод громоотвода по стене вниз
	B.rod(m, (base * CFrame.new(1.6, top - 1, -1.6)).Position, (base * CFrame.new(4.5, 0.5, -4.5)).Position, 0.25, rgb(196, 112, 66), B.deco({ Material = M.Metal }))
	-- ступица и 4 крыла (решётчатые полотна), смотрят к центру острова
	local hubPos = base * CFrame.new(0, 15.5, -4.2)
	B.cyl(m, hubPos * CFrame.Angles(0, math.pi / 2, 0), 2, 1.6, P.WOOD_DARK, B.deco({ Material = M.Wood }))
	local rot = rng:range(0, 1)
	for k = 0, 3 do
		local arm = hubPos * CFrame.new(0, 0, -1.1) * CFrame.Angles(0, 0, rot + k * math.pi / 2)
		B.block(m, arm * CFrame.new(0, 7, 0), Vector3.new(0.6, 14, 0.5), P.WOOD, B.deco({ Material = M.Wood, Shadow = true }))
		B.block(m, arm * CFrame.new(1.7, 8, -0.05), Vector3.new(2.8, 11, 0.2), B.vary(rgb(236, 226, 206), rng, 0.03), B.deco({ Material = M.Fabric, Shadow = true }))
		for r = 0, 3 do
			B.block(m, arm * CFrame.new(1.7, 3.5 + r * 3, -0.2), Vector3.new(3, 0.25, 0.2), P.WOOD_DARK, B.deco({ Material = M.Wood }))
		end
	end
	return m
end

-- 2. Медная вышка: решётчатая башня из 4 сужающихся ног, раскосы, площадка, неоновый маяк
local function copperTower(parent, pos, facing, rng, accent, copper)
	local m = B.model(parent, "Landmark_CopperTower")
	local H = 44
	local base = B.facing(pos, facing)
	local function leg(sx, sz, t)
		local w = 6.5 * (1 - t) + 1.6 * t
		return (base * CFrame.new(sx * w, t * H, sz * w)).Position
	end
	local levels = { 0, 0.22, 0.42, 0.6, 0.76, 0.9 }
	-- ноги
	for _, s in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		for li = 1, #levels - 1 do
			B.rod(m, leg(s[1], s[2], levels[li]), leg(s[1], s[2], levels[li + 1]), 1.1, B.vary(copper, rng, 0.03), { Material = M.Metal, Shadow = true, Collide = li == 1 })
		end
	end
	-- пояса и раскосы
	local corners = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
	for li = 2, #levels do
		for c = 1, 4 do
			local a, b = corners[c], corners[c % 4 + 1]
			B.rod(m, leg(a[1], a[2], levels[li]), leg(b[1], b[2], levels[li]), 0.5, B.shade(copper, 0.15), B.deco({ Material = M.Metal }))
			if li <= #levels - 1 then
				B.rod(m, leg(a[1], a[2], levels[li - 1]), leg(b[1], b[2], levels[li]), 0.35, B.shade(copper, 0.25), B.deco({ Material = M.Metal }))
			end
		end
	end
	-- светящиеся кольца-изоляторы на поясах
	for li = 3, #levels - 1, 2 do
		local y = levels[li] * H
		local cf = base * CFrame.new(0, y + 0.6, 0)
		local w = 6.5 * (1 - levels[li]) + 1.6 * levels[li]
		B.block(m, cf, Vector3.new(w * 2 + 0.6, 0.3, 0.3), accent, B.neon())
		B.block(m, cf, Vector3.new(0.3, 0.3, w * 2 + 0.6), accent, B.neon())
	end
	-- площадка, шпиль и маяк
	local topY = levels[#levels] * H
	B.block(m, base * CFrame.new(0, topY + 0.3, 0), Vector3.new(5, 0.6, 5), B.shade(copper, 0.2), B.deco({ Material = M.DiamondPlate }))
	B.rod(m, (base * CFrame.new(0, topY, 0)).Position, (base * CFrame.new(0, H + 6, 0)).Position, 0.6, copper, B.deco({ Material = M.Metal }))
	local beacon = B.ball(m, (base * CFrame.new(0, H + 6.6, 0)).Position, 2, accent, B.neon())
	B.light(beacon, accent, 34, 2)
	for k = 0, 2 do
		B.cylY(m, (base * CFrame.new(0, topY + 2 + k * 1.4, 0)).Position, 0.3, 2.2 - k * 0.5, rgb(230, 220, 200), B.deco({ Material = M.SmoothPlastic }))
	end
	-- бетонные опоры под ногами
	for _, s in corners do
		B.block(m, CFrame.new(leg(s[1], s[2], 0) + Vector3.new(0, 0.5, 0)), Vector3.new(2.6, 1.4, 2.6), rgb(120, 112, 108), { Material = M.Concrete })
	end
	-- трансформаторная будка у подножия
	B.block(m, base * CFrame.new(0, 2, 0), Vector3.new(4, 4, 3.5), B.shade(copper, 0.35), { Material = M.CorrodedMetal })
	B.block(m, base * CFrame.new(0, 2.6, -1.8), Vector3.new(2.6, 0.4, 0.1), accent, B.neon())
	return m
end

-- 3. Гигантский стеклянный фульгурит (из того же генератора, что и коллекционные), на каменном постаменте
local function giantFulgurite(parent, pos, rng, glass, glow, Fulgurite)
	local m = B.model(parent, "Landmark_Fulgurite")
	local spec = Fulgurite.generate(1010, "gold", nil) -- «Корона»: пышная и симметричная
	local scale = 5.4
	-- стебли начинаются прямо на постаменте (верх 1.2), каменные глыбы основания не строим
	local base = CFrame.new(pos + Vector3.new(0, 1.2 - 0.55 * scale, 0)) * CFrame.Angles(0, rng:range(0, 6.28), 0)
	-- постамент: оплавленная песчаная плита и кольцо камней
	B.cylY(m, pos + Vector3.new(0, 0.6, 0), 1.2, 15, rgb(150, 120, 92), { Material = M.Sandstone, Shadow = true })
	B.cylY(m, pos + Vector3.new(0, 1.3, 0), 0.3, 13, B.mix(glass, rgb(60, 50, 50), 0.4), B.deco({ Material = M.Glass, Transparency = 0.2 }))
	for _, ps in spec.Parts do
		local cf = base * (CFrame.new(ps.CFrame.Position * scale) * (ps.CFrame - ps.CFrame.Position))
		local size = ps.Size * scale
		if ps.Kind ~= "base" then
			local p
			local opts
			if ps.Kind == "glass" then
				opts = B.deco({ Material = M.Glass, Transparency = 0.3, Shadow = false })
				if ps.Shape == "Cylinder" then
					p = B.cyl(m, cf, size.X, size.Y, B.vary(glass, rng, 0.03), opts)
				elseif ps.Shape == "Ball" then
					p = B.ball(m, cf.Position, size.X, glass, opts)
				else
					p = B.block(m, cf, size, glass, opts)
				end
			elseif ps.Kind == "core" then
				p = B.cyl(m, cf, size.X, size.Y, B.tint(glow, 0.35), B.neon())
			else -- tip
				p = B.ball(m, cf.Position, size.X, B.tint(glow, 0.5), B.neon())
			end
		end
	end
	local light = B.block(m, CFrame.new(pos + Vector3.new(0, 12, 0)), Vector3.new(1, 1, 1), glow, B.deco({ Transparency = 1, Shadow = false }))
	B.light(light, glow, 40, 2.2)
	return m, spec.Height * scale
end

-- 4. Ледяной шпиль: витая колонна из повёрнутых ледяных брусков, светящееся ядро, кристаллы у основания
local function iceSpire(parent, pos, rng, ice, accent)
	local m = B.model(parent, "Landmark_IceSpire")
	local H = 46
	local n = 9
	local y = 0
	for k = 1, n do
		local t = (k - 1) / n
		local w = 8.5 * (1 - t) ^ 0.9 + 1.2
		local h = H / n * 1.25
		local cf = CFrame.new(pos + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, k * 0.42, 0) * CFrame.Angles(rng:range(-0.04, 0.04), 0, rng:range(-0.04, 0.04))
		local col = B.vary(B.mix(ice, rgb(240, 248, 255), t * 0.5), rng, 0.03)
		B.block(m, cf, Vector3.new(w, h, w), col, { Material = M.Ice, Shadow = k <= 3, Collide = k <= 2, Transparency = 0.05 })
		y += H / n
	end
	-- остриё
	for q = 0, 3 do
		local cf = CFrame.new(pos + Vector3.new(0, y + 3, 0)) * CFrame.Angles(0, n * 0.42 + q * math.pi / 2, 0) * CFrame.new(0, 0, -0.7)
		B.wedge(m, cf, Vector3.new(1.4, 6, 1.4), rgb(236, 246, 255), B.deco({ Material = M.Ice }))
	end
	-- светящееся ядро (виден сквозь лёд) и навершие
	B.block(m, CFrame.new(pos + Vector3.new(0, H * 0.5, 0)), Vector3.new(1.2, H * 0.9, 1.2), accent, B.neon({ Transparency = 0.15 }))
	local star = B.ball(m, pos + Vector3.new(0, y + 6.5, 0), 2, accent, B.neon())
	B.light(star, accent, 36, 2)
	-- кольцо кристаллов у основания
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2 + rng:range(-0.2, 0.2)
		P.crystals(m, pos + Vector3.new(math.cos(a) * 7.5, 0, math.sin(a) * 7.5), rng, ice, rng:range(1.4, 2.2), M.Ice, if k % 2 == 0 then accent else nil)
	end
	-- снежный холмик у подножия
	B.ball(m, pos - Vector3.new(0, 7.5, 0), 19, rgb(240, 245, 255), { Material = M.Snow, Shadow = false })
	return m
end

-- 5. Золотой столб света: круглый алтарь с ободом, 4 обелиска и сияющий столб до туч
local function lightPillar(parent, pos, rng, gold, crack, cloudY, outward)
	local m = B.model(parent, "Landmark_LightPillar")
	local dark = rgb(40, 34, 50)
	B.cylY(m, pos + Vector3.new(0, 0.6, 0), 1.2, 14.6, dark, { Material = M.Basalt, Shadow = true })
	B.cylY(m, pos + Vector3.new(0, 1.3, 0), 0.3, 12.5, gold, { Material = M.Metal, Collide = false, Query = false })
	B.cylY(m, pos + Vector3.new(0, 1.5, 0), 0.4, 11, rgb(56, 46, 70), B.deco({ Material = M.Basalt }))
	-- светящаяся «ступица»
	local coreBase = B.cylY(m, pos + Vector3.new(0, 1.9, 0), 0.5, 6, gold, B.neon())
	B.light(coreBase, gold, 40, 3)
	-- столб: яркое ядро и мягкое свечение вокруг (уходит в тучи)
	local h = cloudY - pos.Y + 10
	B.cylY(m, pos + Vector3.new(0, 2 + h / 2, 0), h, 2.6, B.tint(gold, 0.4), B.neon())
	B.cylY(m, pos + Vector3.new(0, 2 + h / 2, 0), h, 5.5, gold, B.neon({ Transparency = 0.82 }))
	B.cylY(m, pos + Vector3.new(0, 2 + h / 2, 0), h, 9, gold, B.neon({ Transparency = 0.93 }))
	-- обелиски с фиолетовыми рунами
	local baseA = math.atan2(outward.Z, outward.X)
	for k = 0, 3 do
		-- обелиски по диагоналям относительно направления «наружу»: к центру острова не выступают
		local a = baseA + ({ -1, 1, -2, 2 })[k + 1] * math.rad(55)
		local p = pos + Vector3.new(math.cos(a) * 9.5, 0, math.sin(a) * 9.5)
		local hh = 9 + rng:range(-1, 1.5)
		local cf = CFrame.new(p + Vector3.new(0, hh / 2, 0)) * CFrame.Angles(0, -a, 0)
		B.block(m, cf, Vector3.new(1.8, hh, 1.8), B.vary(dark, rng, 0.03), { Material = M.Basalt, Shadow = true })
		B.wedge(m, cf * CFrame.new(0, hh / 2 + 0.6, 0.45), Vector3.new(1.8, 1.2, 0.9), dark, B.deco({ Material = M.Basalt }))
		B.wedge(m, cf * CFrame.new(0, hh / 2 + 0.6, -0.45) * CFrame.Angles(0, math.pi, 0), Vector3.new(1.8, 1.2, 0.9), dark, B.deco({ Material = M.Basalt }))
		for r = 0, 2 do
			B.block(m, cf * CFrame.new(0, -hh / 2 + 2.5 + r * 2.2, -0.92), Vector3.new(0.7, 0.9, 0.1), crack, B.neon())
		end
		B.ball(m, p + Vector3.new(0, hh + 2.6, 0), 1, gold, B.neon())
	end
	return m
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

	-- подвески снизу по теме
	local hang
	if i == 1 then
		hang = function(m, p, out, r)
			local len = r:range(4, 9)
			B.rod(m, p, p - Vector3.new(r:range(-0.6, 0.6), len, r:range(-0.6, 0.6)) + out * 0.8, r:range(0.3, 0.5), B.vary(rgb(98, 72, 52), r, 0.05), B.deco({ Material = M.Wood }))
			if r:chance(0.5) then
				B.rod(m, p + out * 0.4, p + out * 1.2 - Vector3.new(0, len * 0.7, 0), 0.35, B.vary(rgb(70, 140, 62), r, 0.05), B.deco({ Material = M.Grass }))
			end
		end
	elseif i == 2 then
		hang = function(m, p, out, r)
			local q = p + out * 2.5 - Vector3.new(0, 1, 0)
			B.rod(m, p - out, q, 1, B.vary(th.copper, r, 0.04), B.deco({ Material = M.Metal }))
			B.rod(m, q, q - Vector3.new(0, r:range(2, 5), 0), 1, B.vary(th.copper, r, 0.04), B.deco({ Material = M.Metal }))
			B.ball(m, q, 1.15, B.shade(th.copper, 0.2), B.deco({ Material = M.Metal }))
		end
	elseif i == 3 then
		hang = function(m, p, out, r)
			local len = r:range(3, 7)
			local cf = CFrame.new(p - Vector3.new(0, len / 2, 0) + out * 0.5) * CFrame.Angles(r:range(-0.2, 0.2), r:range(0, 3), r:range(-0.2, 0.2)) * CFrame.Angles(0, math.pi / 4, 0)
			B.block(m, cf, Vector3.new(1.2, len, 1.2), th.glass, B.deco({ Material = M.Glass, Transparency = 0.25 }))
			B.block(m, cf, Vector3.new(0.4, len * 0.8, 0.4), th.glow, B.neon())
		end
	elseif i == 4 then
		hang = function(m, p, out, r)
			for k = 0, r:int(1, 2) do
				local len = r:range(3, 8)
				local q = p + out * (0.5 + k * 0.8) + Vector3.new(r:range(-1, 1), 0, r:range(-1, 1))
				local cf = CFrame.new(q - Vector3.new(0, len / 2, 0)) * CFrame.Angles(0, r:range(0, 3), 0)
				B.wedge(m, cf * CFrame.Angles(math.pi, 0, 0), Vector3.new(r:range(0.8, 1.4), len, r:range(0.8, 1.4)), B.vary(th.ice, r, 0.03), B.deco({ Material = M.Ice }))
			end
		end
	else
		hang = function(m, p, out, r)
			local len = r:range(3, 6)
			local cf = CFrame.new(p - Vector3.new(0, len / 2, 0) + out * 0.6) * CFrame.Angles(r:range(-0.25, 0.25), r:range(0, 3), r:range(-0.25, 0.25)) * CFrame.Angles(0, math.pi / 4, 0)
			B.block(m, cf, Vector3.new(1.3, len, 1.3), B.vary(rgb(120, 70, 200), r, 0.04), B.deco({ Material = M.Glass, Transparency = 0.15 }))
			B.block(m, cf, Vector3.new(0.45, len * 0.85, 0.45), th.crack, B.neon())
		end
	end

	local body = Island.body(model, {
		name = "Ground",
		center = C,
		radius = R,
		seed = 100 + i * 31,
		segments = 34,
		base = 2.2,
		amp = 7,
		top = z.Grass,
		topMaterial = z.GrassMaterial,
		dirt = th.dirt,
		dirtMaterial = if i == 3 then M.Sandstone elseif i == 4 then M.Glacier elseif i == 5 then M.Basalt else M.Ground,
		rock = th.rock,
		rock2 = th.rock2,
		rockMaterial = th.rockMaterial,
		depth = 62 + i * 3,
		openings = { g.ToHub },
		openHalfDeg = 9,
		drips = if i == 5 then 0 else 16,
		dripColor = if i == 4 then rgb(244, 248, 255) else nil,
		hang = hang,
		hangCount = if i == 4 then 16 else 10,
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
	-- игровая зона: колонны и деревья только снаружи
	local rimMin = PR + 2.5

	local function ground(pos)
		return Vector3.new(pos.X, GY, pos.Z)
	end

	-- холмы-бугры по краю (только снаружи игровой зоны и не свисают с обрыва)
	local hillCount = if i == 3 then 9 elseif i == 5 then 4 else 6
	for _ = 1, hillCount do
		local s = rng:range(9, 13)
		local cap = rng:range(2.5, 4.8)
		local foot = math.sqrt(s * s - (s - cap) * (s - cap))
		local pos = S.ring(PR + foot + 1, R - foot + 4, foot * 0.8, 50)
		if pos then
			Island.hill(decor, ground(pos), s * 2, cap, th.hill, z.GrassMaterial, rng)
		end
	end

	-- входная арка с названием острова (на краю у моста)
	do
		local a = C + g.ToHub * (R - 3)
		local half = Config.BridgeWidth / 2 + 1.8
		local col = th.arch
		local arch = B.model(decor, "EntranceArch")
		for side = -1, 1, 2 do
			local p = ground(a + g.Right * side * half)
			B.block(arch, CFrame.new(p + Vector3.new(0, 0.6, 0)), Vector3.new(2.8, 1.2, 2.8), B.shade(col, 0.15), { Material = M.Cobblestone })
			B.block(arch, CFrame.new(p + Vector3.new(0, 6, 0)), Vector3.new(1.9, 10, 1.9), col, { Material = if i == 2 then M.Metal else M.Wood, Shadow = true })
			local lampTop = B.block(arch, CFrame.new(p + Vector3.new(0, 11.6, 0)), Vector3.new(1.2, 1.2, 1.2), th.lamp, B.neon())
			B.light(lampTop, th.lamp, 18, 1.1)
			B.block(arch, CFrame.new(p + Vector3.new(0, 12.4, 0)), Vector3.new(1.8, 0.4, 1.8), B.shade(col, 0.25), B.deco({ Material = M.Metal }))
		end
		local beamCf = B.facing(ground(a) + Vector3.new(0, 10.4, 0), g.ToHub)
		B.block(arch, beamCf, Vector3.new(half * 2 + 2.6, 1.1, 1.3), B.shade(col, 0.05), B.deco({ Material = if i == 2 then M.Metal else M.Wood, Shadow = true }))
		local sign = B.block(arch, beamCf * CFrame.new(0, -1.9, 0), Vector3.new(16, 2.6, 0.4), rgb(36, 34, 48), B.deco({ Material = M.Wood }))
		B.text(sign, { { Text = z.Name, Color = z.Accent:Lerp(Color3.new(1, 1, 1), 0.45) } }, { Face = Enum.NormalId.Front, PixelsPerStud = 30 })
		B.text(sign, { { Text = z.Name, Color = z.Accent:Lerp(Color3.new(1, 1, 1), 0.45) } }, { Face = Enum.NormalId.Back, PixelsPerStud = 30, Name = "SignBack" })
		for side = -1, 1, 2 do
			B.block(arch, beamCf * CFrame.new(side * 6, -0.55, 0), Vector3.new(0.2, 1.2, 0.2), P.IRON, B.deco({ Material = M.Metal }))
		end
	end

	-- дорожка из плоских камней: от моста к точке появления и к подстанции (не выше GroundY + 0.04)
	local function pathStones(a, b, count, color)
		for k = 0, count do
			local t = k / count
			local p = a:Lerp(b, t) + g.Right * rng:range(-2.2, 2.2) + g.ToHub * rng:range(-0.6, 0.6)
			local w, d = rng:range(2, 3.4), rng:range(1.8, 3)
			B.block(flora, CFrame.new(ground(p) + Vector3.new(0, -0.035, 0)) * CFrame.Angles(0, rng:range(0, 3.14), 0), Vector3.new(w, 0.15, d), B.vary(color, rng, 0.05), B.deco({ Material = if i == 4 then M.Ice elseif i == 5 then M.Basalt else M.Slate, Shadow = false, Name = "PathStone" }))
		end
	end
	pathStones(C + g.ToHub * (R - 1), g.Spawn - Vector3.new(0, 3, 0) - g.ToHub * 4, 9, th.path)
	pathStones(g.Spawn - Vector3.new(0, 3, 0), g.SellPad - stationOut * 1 + g.ToHub * 5, 6, th.path)

	-- пятна другого оттенка на земле (оживляют плоскую игровую зону): 2-3 перекрывающихся диска,
	-- каждый на своей высоте (+0.012 / +0.027), без коллизий — кольца рисуются выше (+0.05 и больше)
	local patchColors = th.patches or { B.shade(z.Grass, 0.1), B.tint(z.Grass, 0.07) }
	local function groundPatch(pos, size)
		local col = rng:pick(patchColors)
		for k = 1, rng:int(2, 3) do
			local off = if k == 1 then Vector3.zero else rng:disc(size * 0.45)
			local d = size * rng:range(0.55, 1)
			local top = if k == 1 then 0.012 else 0.027
			B.cylY(flora, ground(pos + off) + Vector3.new(0, top - 0.05, 0), 0.1, d, B.vary(col, rng, 0.015), B.deco({ Material = th.patchMaterial or z.GrassMaterial, Shadow = false, Name = "Patch" }))
		end
	end
	for _ = 1, th.patchCount or 9 do
		local p = C + rng:disc(PR - 6)
		if flatDist(p, g.SellPad) > 10 then
			groundPatch(p, rng:range(10, 20))
		end
	end

	-- мелкая флора внутри игровой зоны (без коллизий): цветы/травинки/блёстки
	local function insideSpot(minGap)
		for _ = 1, 30 do
			local p = C + rng:disc(PR - 3)
			if flatDist(p, g.SellPad) > 9 and flatDist(p, g.Spawn) > minGap then
				return ground(p)
			end
		end
		return nil
	end

	local landmarkFacing = -g.Dir -- ориентир «смотрит» к центру острова

	if i == 1 then
		----------------------------------------------------------------
		-- Грозовой Луг
		----------------------------------------------------------------
		local pal = { leaves = th.leaves, wood = P.WOOD, rock = th.rock, moss = th.moss, berries = rgb(220, 60, 80), fruit = rgb(230, 70, 60) }
		windmill(decor, ground(g.Landmark), landmarkFacing, rng, z.Accent)
		for _ = 1, 15 do
			local p = S.ring(rimMin + 2, R + 3, 4.5)
			if p then
				P.tree(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 12 do
			local p = S.ring(rimMin, R + 4, 2.5)
			if p then
				P.bush(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 8 do
			local p = S.ring(rimMin, R + 4, 2.5)
			if p then
				P.rock(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 7 do
			local p = S.ring(rimMin, R + 4, 1.2)
			if p then
				P.mushroom(decor, ground(p), rng, rng:pick({ rgb(220, 60, 60), rgb(240, 150, 60) }))
			end
		end
		-- заборчики вдоль дуги края (не по сетке: ломаная с разными углами)
		for _ = 1, 4 do
			local a0 = rng:range(0, math.pi * 2)
			local pts = {}
			local rr = PR + rng:range(4, 8)
			for k = 0, 3 do
				local a = a0 + k * rng:range(0.07, 0.11)
				local p = C + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr)
				rr += rng:range(-1.5, 1.5)
				table.insert(pts, p)
			end
			local ok = true
			for _, p in pts do
				if not S.free(p, 1) then
					ok = false
				end
			end
			if ok then
				for k = 1, #pts - 1 do
					if rng:chance(0.85) then
						P.fence(decor, ground(pts[k]), ground(pts[k + 1]), P.WOOD, rng)
					end
				end
				for _, p in pts do
					S.take(p, 1.5)
				end
			end
		end
		-- колодец у края
		do
			local p = S.ring(rimMin + 3, R - 3, 4)
			if p then
				P.well(decor, ground(p), rng)
			end
		end
		-- стожки сена
		for _ = 1, 3 do
			local p = S.ring(rimMin + 2, R, 3)
			if p then
				local hay = B.model(decor, "Hay")
				B.cylY(hay, ground(p) + Vector3.new(0, 1.6, 0), 3.2, 5, B.vary(rgb(222, 186, 96), rng, 0.04), { Material = M.Grass })
				B.ball(hay, ground(p) + Vector3.new(0, 3.1, 0), 4.6, B.vary(rgb(230, 196, 104), rng, 0.04), B.deco({ Material = M.Grass }))
			end
		end
		for _ = 1, 13 do
			local p = insideSpot(5)
			if p then
				P.flowerPatch(flora, p, rng, th.flowers, rng:int(4, 6), rng:range(1.8, 3.2))
			end
		end
		for _ = 1, 26 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, th.tuft)
			end
		end
		-- цветы и трава у края (снаружи)
		for _ = 1, 6 do
			local p = S.ring(rimMin, R + 3, 1.5)
			if p then
				P.flowerPatch(flora, ground(p), rng, th.flowers, 5, 2.4)
			end
		end
	elseif i == 2 then
		----------------------------------------------------------------
		-- Медные Холмы
		----------------------------------------------------------------
		local pal = { leaves = th.leaves, rock = th.rock, vein = th.vein, copper = th.copper, wood = rgb(98, 70, 56) }
		copperTower(decor, ground(g.Landmark), landmarkFacing, rng, z.Accent, th.copper)
		for _ = 1, 14 do
			local p = S.ring(rimMin + 1, R + 3, 3.5)
			if p then
				P.veinRock(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 7 do
			local p = S.ring(rimMin + 3, R, 5)
			if p then
				-- труба идёт вдоль края (по касательной), а не в игровую зону
				local out = B.flat(p - C).Unit
				local tangent = Vector3.new(-out.Z, 0, out.X) * (if rng:chance(0.5) then 1 else -1)
				P.pipe(decor, ground(p), rng, pal, nil, (tangent + out * 0.25).Unit)
			end
		end
		for _ = 1, 9 do
			local p = S.ring(rimMin + 1, R + 3, 3.5)
			if p then
				P.deadTree(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 10 do
			local p = S.ring(rimMin, R + 4, 2.5)
			if p then
				P.bush(decor, ground(p), rng, pal, rng:range(0.6, 1))
			end
		end
		for _ = 1, 7 do
			local p = S.ring(rimMin, R + 4, 2.5)
			if p then
				P.rock(decor, ground(p), rng, pal)
			end
		end
		-- вагонетки с рудой на рельсах (вдоль края)
		for _ = 1, 2 do
			local p = S.ring(rimMin + 4, R - 4, 5)
			if p then
				local out = B.flat(p - C).Unit
				P.mineCart(decor, ground(p), Vector3.new(-out.Z, 0, out.X), rng, th.vein)
			end
		end
		-- бочки и ящики шахтёров
		for _ = 1, 4 do
			local p = S.ring(rimMin + 2, R, 3)
			if p then
				P.barrel(decor, ground(p), rng)
				P.crate(decor, ground(p + Vector3.new(rng:range(1.8, 2.4), 0, rng:range(-1, 1))), rng)
			end
		end
		for _ = 1, 30 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, B.vary(th.tuft, rng, 0.05))
			end
		end
		-- рыжие цветы-«медянки» внутри (редко)
		for _ = 1, 8 do
			local p = insideSpot(5)
			if p then
				P.flowerPatch(flora, p, rng, { rgb(255, 196, 90), rgb(255, 130, 70), rgb(240, 230, 200) }, 4, 2)
			end
		end
	elseif i == 3 then
		----------------------------------------------------------------
		-- Стеклянные Дюны
		----------------------------------------------------------------
		local pal = { cactus = th.cactus, cactusFlower = th.cactusFlower, stone = th.stone, rock = th.rock, rockMaterial = M.Sandstone }
		giantFulgurite(decor, ground(g.Landmark), rng, th.glass, th.glow, ctx.Fulgurite)
		for _ = 1, 5 do
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
				B.cylY(o, ground(p) + Vector3.new(0, -0.02, 0), 0.12, 9, rgb(70, 170, 190), B.deco({ Material = M.Glass, Transparency = 0.15, Shadow = false, Name = "Water" }))
				B.cylY(o, ground(p) + Vector3.new(0, -0.05, 0), 0.12, 10.5, rgb(200, 176, 120), B.deco({ Material = M.Sand, Shadow = false }))
				for k = 1, 2 do
					local a = rng:range(0, 6.28)
					P.palm(o, ground(p + Vector3.new(math.cos(a) * 5.6, 0, math.sin(a) * 5.6)), rng)
				end
				for _ = 1, 4 do
					local a = rng:range(0, 6.28)
					P.tuft(o, ground(p + Vector3.new(math.cos(a) * 4.6, 0, math.sin(a) * 4.6)), rng, rgb(90, 150, 80), 1.6)
				end
			end
		end
		for _ = 1, 15 do
			local p = S.ring(rimMin + 1, R + 3, 3)
			if p then
				P.cactus(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 15 do
			local p = S.ring(rimMin, R + 3, 2.8)
			if p then
				P.glassSpike(decor, ground(p), rng, th.glass, th.glow)
			end
		end
		for _ = 1, 7 do
			local p = S.ring(rimMin, R + 4, 2.5)
			if p then
				P.rock(decor, ground(p), rng, pal)
			end
		end
		-- осколки стекла внутри (блёстки без коллизий)
		for _ = 1, 22 do
			local p = insideSpot(4)
			if p then
				local cf = CFrame.new(p + Vector3.new(0, 0.25, 0)) * CFrame.Angles(rng:range(-0.5, 0.5), rng:range(0, 3), rng:range(-0.5, 0.5))
				B.block(flora, cf, Vector3.new(0.35, rng:range(0.6, 1.2), 0.35), th.glass, B.deco({ Material = M.Glass, Transparency = 0.2, Shadow = false }))
			end
		end
		for _ = 1, 26 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, th.tuft, 0.8)
			end
		end
	elseif i == 4 then
		----------------------------------------------------------------
		-- Ледяной Пик
		----------------------------------------------------------------
		local pal = { pine = th.pine, snowy = true, rock = th.rock }
		iceSpire(decor, ground(g.Landmark), rng, th.ice, z.Accent)
		for _ = 1, 17 do
			local p = S.ring(rimMin + 2, R + 3, 4.5)
			if p then
				P.pine(decor, ground(p), rng, pal)
			end
		end
		for _ = 1, 9 do
			local p = S.ring(rimMin, R + 3, 2.5)
			if p then
				P.crystals(decor, ground(p), rng, th.ice, rng:range(0.9, 1.6), M.Ice, if rng:chance(0.4) then z.Accent else nil)
			end
		end
		for _ = 1, 8 do
			local p = S.ring(rimMin, R + 4, 2.5)
			if p then
				local r = P.rock(decor, ground(p), rng, pal)
				-- снежная шапка
				B.ball(r, ground(p) + Vector3.new(0, 2.2, 0), 2.4, rgb(244, 248, 255), B.deco({ Material = M.Snow, Shadow = false }))
			end
		end
		for _ = 1, 10 do
			local p = S.ring(rimMin, R + 2, 3)
			if p then
				P.drift(decor, ground(p), rng, rgb(240, 245, 255))
			end
		end
		-- снеговик смотрит на игровую поляну
		do
			local p = S.ring(rimMin + 2, R - 3, 3)
			if p then
				P.snowman(decor, ground(p), C - p, rng)
			end
		end
		-- ледяные «блюдца» и снежные травинки внутри
		for _ = 1, 30 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, th.tuft, 0.9)
			end
		end
		for _ = 1, 10 do
			local p = insideSpot(4)
			if p then
				local cf = CFrame.new(p + Vector3.new(0, 0.3, 0)) * CFrame.Angles(rng:range(-0.4, 0.4), rng:range(0, 3), rng:range(-0.4, 0.4)) * CFrame.Angles(0, math.pi / 4, 0)
				B.block(flora, cf, Vector3.new(0.4, rng:range(0.7, 1.3), 0.4), th.ice, B.deco({ Material = M.Ice, Shadow = false }))
			end
		end
	else
		----------------------------------------------------------------
		-- Око Бури
		----------------------------------------------------------------
		local pal = { rock = th.rock, crack = th.crack }
		lightPillar(decor, ground(g.Landmark), rng, th.gold, th.crack, GY + Config.CloudHeight, g.Dir)
		for _ = 1, 12 do
			local p = S.ring(rimMin + 1, R + 3, 3.5)
			if p then
				P.basalt(decor, ground(p), rng, pal)
			end
		end
		for k = 1, 10 do
			local p = S.ring(rimMin, R + 3, 2.8)
			if p then
				local cr = P.crystals(decor, ground(p), rng, rgb(130, 80, 220), rng:range(1, 1.7), M.Glass, th.crack)
				if k % 3 == 1 then
					local lp = B.block(cr, CFrame.new(ground(p) + Vector3.new(0, 2.5, 0)), Vector3.new(0.5, 0.5, 0.5), th.crack, B.deco({ Transparency = 1, Shadow = false }))
					B.light(lp, th.crack, 18, 1.2)
				end
			end
		end
		-- парящие камни над краем и над обрывом (без коллизий)
		for _ = 1, 14 do
			local a = rng:range(0, math.pi * 2)
			local d = rng:range(PR + 6, R + 14)
			local p = C + Vector3.new(math.cos(a) * d, rng:range(7, 24), math.sin(a) * d)
			if flatDist(p, C + g.ToHub * R) > 22 then
				P.floatRock(decor, p, rng, pal)
			end
		end
		-- неоновые трещины по земле у края (ломаные из тонких полосок)
		for _ = 1, 9 do
			local p = S.ring(rimMin, R - 2, 2)
			if p then
				local q = ground(p)
				local dir = B.dir(rng:range(0, 360))
				for _ = 1, rng:int(3, 5) do
					local nextQ = q + (dir + Vector3.new(rng:range(-0.6, 0.6), 0, rng:range(-0.6, 0.6))).Unit * rng:range(2, 4)
					if flatDist(nextQ, C) > PR + 1 and flatDist(nextQ, C) < outline(math.atan2(nextQ.Z - C.Z, nextQ.X - C.X)) - 1 then
						B.bar(flora, q + Vector3.new(0, 0.02, 0), nextQ + Vector3.new(0, 0.02, 0), rng:range(0.25, 0.45), 0.1, th.crack, B.neon())
						q = nextQ
					end
				end
			end
		end
		-- фиолетовые искорки-камешки внутри (тусклые, плоские)
		for _ = 1, 24 do
			local p = insideSpot(3)
			if p then
				B.block(flora, CFrame.new(p + Vector3.new(0, -0.02, 0)) * CFrame.Angles(0, rng:range(0, 3), 0), Vector3.new(rng:range(0.6, 1.2), 0.1, rng:range(0.5, 1)), rgb(64, 54, 80), B.deco({ Material = M.Basalt, Shadow = false }))
			end
		end
		for _ = 1, 10 do
			local p = insideSpot(3)
			if p then
				P.tuft(flora, p, rng, B.rgb(120, 90, 170), 0.7)
			end
		end
	end

	return model, body
end

ZonesMap.THEMES = THEMES

return ZonesMap
