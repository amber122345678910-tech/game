--!nocheck
-- Декорация Throne (S11): чёрная пустота, круглый подиум, золотой резной трон с красным бархатом,
-- корона на спинке, прожектор сверху с видимым конусом света (Beam), пылинки и золотые искры.
--
-- Контракт (AGENTS.md): трон в (0,0,0) лицом в −Z; верх подиума Y=0.8 (вперёд до z≈−3.5, x±4);
-- верх сиденья Y=2.2, сиденье z∈[−1.3,0.6], ширина 3.2; спинка от z≈0.6, до Y≈8.5; корона до Y≈10.5;
-- подлокотники x=±1.9, верх Y≈3.4. Прожектор ≈ (0,30,−2).
--
-- Имена для эффектов планов: эмиттеры "ThroneSparkles", "Dust", "ThroneGlints" (+ "ThroneGlintsL/R"),
-- свет "KeyLight" (SpotLight в детали "SpotLamp"), лучи "LightShaft*".

local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local NumberSequence = roblox.NumberSequence
local NumberSequenceKeypoint = roblox.NumberSequenceKeypoint
local ColorSequence = roblox.ColorSequence
local ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
local NumberRange = roblox.NumberRange
local Vector2 = roblox.Vector2

local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

-- ===== Палитра =====
local C = {
	gold = rgb(214, 172, 94), -- основное золото (Metal)
	goldHi = rgb(238, 204, 128), -- орнамент (Foil)
	goldDeep = rgb(150, 110, 48), -- углубления резьбы
	velvet = rgb(178, 22, 32), -- бархат спинки
	velvetSeat = rgb(156, 10, 22), -- бархат сиденья
	velvetDark = rgb(92, 4, 12), -- пуговицы, складки
	ruby = rgb(226, 18, 52),
	rubyCore = rgb(150, 0, 20),
	sapphire = rgb(40, 92, 236),
	sapphireCore = rgb(10, 30, 140),
	emerald = rgb(24, 196, 110),
	emeraldCore = rgb(0, 90, 40),
	pearl = rgb(242, 234, 218),
	void = rgb(0, 0, 0),
	floor = rgb(6, 6, 7),
	dais = rgb(16, 14, 15),
	light = rgb(255, 228, 188),
}

local M = {
	gold = "Metal",
	foil = "Foil",
	velvet = "Fabric",
	glass = "Glass",
	neon = "Neon",
}

-- ===== Геометрические помощники =====

-- Ортонормированный CFrame: ось X вдоль (b - a), центр посередине (без NaN для вертикали).
local function along(a, b)
	local d = b - a
	local len = d.Magnitude
	local x = if len > 1e-6 then d / len else Vector3.xAxis
	local up = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y, z), len
end

-- CFrame в точке pos, у которого −Z (Front) смотрит на target.
local function aim(pos, target)
	local f = (target - pos).Unit
	local up = if math.abs(f.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local x = f:Cross(up).Unit
	local y = x:Cross(f).Unit
	return CFrame.fromMatrix(pos, x, y, -f)
end

-- Catmull-Rom по списку точек (Vector3), n — отрезков на участок.
local function spline(pts, n)
	local out = {}
	local count = #pts
	for i = 1, count - 1 do
		local p0 = pts[math.max(1, i - 1)]
		local p1 = pts[i]
		local p2 = pts[i + 1]
		local p3 = pts[math.min(count, i + 2)]
		for k = 0, n - 1 do
			local t = k / n
			local t2, t3 = t * t, t * t * t
			local p = (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
			table.insert(out, p)
		end
	end
	table.insert(out, pts[count])
	return out
end

-- Длина ломаной
local function polyLength(pts)
	local L = 0
	for i = 2, #pts do
		L += (pts[i] - pts[i - 1]).Magnitude
	end
	return L
end

-- Равномерная выборка ломаной по длине: возвращает {pos, s(0..1)}
local function resample(pts, step)
	local L = polyLength(pts)
	local n = math.max(1, math.floor(L / step + 0.5))
	local out = {}
	local seg, segStart = 2, 0
	local segLen = (pts[2] - pts[1]).Magnitude
	for k = 0, n do
		local s = L * k / n
		while seg < #pts and s > segStart + segLen do
			segStart += segLen
			seg += 1
			segLen = (pts[seg] - pts[seg - 1]).Magnitude
		end
		local t = if segLen > 1e-9 then math.clamp((s - segStart) / segLen, 0, 1) else 0
		table.insert(out, { pts[seg - 1]:Lerp(pts[seg], t), k / n })
	end
	return out
end

return function(B)
	local root = B.model

	local function part(spec)
		return B:part(spec)
	end

	-- Цилиндр от a до b
	local function rod(parent, a, b, d, color, mat, extra)
		local cf, len = along(a, b)
		local spec = { parent = parent, cf = cf, size = V(len, d, d), shape = "Cylinder", color = color, material = mat }
		for k, v in extra or {} do
			spec[k] = v
		end
		return part(spec)
	end

	local function ball(parent, p, d, color, mat, extra)
		local spec = { parent = parent, pos = p, size = V(d, d, d), shape = "Ball", color = color, material = mat }
		for k, v in extra or {} do
			spec[k] = v
		end
		return part(spec)
	end

	local function ell(parent, cf, size, color, mat, extra)
		local spec = { parent = parent, cf = cf, size = size, mesh = "Sphere", color = color, material = mat }
		for k, v in extra or {} do
			spec[k] = v
		end
		return part(spec)
	end

	local function box(parent, cf, size, color, mat, extra)
		local spec = { parent = parent, cf = cf, size = size, color = color, material = mat }
		for k, v in extra or {} do
			spec[k] = v
		end
		return part(spec)
	end

	-- Гладкая трубка по точкам с диаметрами: pts = { {pos, d}, ... } — цилиндры + шарики в узлах.
	local function tube(parent, pts, color, mat, closed)
		local n = #pts
		for i = 1, n do
			local p, d = pts[i][1], pts[i][2]
			ball(parent, p, d * 1.02, color, mat)
			local j = i + 1
			if j > n then
				if not closed then
					break
				end
				j = 1
			end
			local q, e = pts[j][1], pts[j][2]
			if (q - p).Magnitude > 0.01 then
				rod(parent, p, q, math.min(d, e), color, mat)
			end
		end
	end

	-- Цепочка шариков (бусины) вдоль ломаной.
	local function beads(parent, pts, d, step, color, mat)
		for _, it in resample(pts, step) do
			ball(parent, it[1], d, color, mat)
		end
	end

	-- ===================================================================
	-- КОМНАТА: чёрная коробка
	-- ===================================================================
	local room = B:folder("Room")
	part({ parent = room, name = "Floor", pos = V(0, -0.5, 0), size = V(140, 1, 140), color = C.floor, material = "SmoothPlastic", reflectance = 0.03 })
	local wallSpec = { color = C.void, material = "SmoothPlastic", castShadow = false }
	local function wall(name, pos, size)
		local s = table.clone(wallSpec)
		s.parent, s.name, s.pos, s.size = room, name, pos, size
		part(s)
	end
	wall("WallN", V(0, 25, -70.5), V(142, 52, 1))
	wall("WallS", V(0, 25, 70.5), V(142, 52, 1))
	wall("WallW", V(-70.5, 25, 0), V(1, 52, 142))
	wall("WallE", V(70.5, 25, 0), V(1, 52, 142))
	wall("Ceiling", V(0, 51.5, 0), V(142, 1, 142))

	-- ===================================================================
	-- ПОДИУМ: две круглые ступени чёрного мрамора с золотыми кантами
	-- ===================================================================
	local dais = B:folder("Dais")
	local DZ = 0.5 -- центр подиума по Z (фронт верхней ступени: 0.5 − 4.0 = −3.5)
	local function disc(name, y0, y1, r, color, mat, extra)
		local spec = { parent = dais, name = name, cf = CFrame.new(0, (y0 + y1) / 2, DZ) * CFrame.Angles(0, 0, math.pi / 2), size = V(y1 - y0, r * 2, r * 2), shape = "Cylinder", color = color, material = mat }
		for k, v in extra or {} do
			spec[k] = v
		end
		return part(spec)
	end
	disc("StepLow", 0, 0.4, 4.8, C.dais, "Marble")
	disc("StepLowTrim", 0.31, 0.38, 4.83, C.gold, M.gold)
	disc("StepLowBase", -0.02, 0.05, 4.86, C.goldDeep, M.gold)
	disc("StepTop", 0.38, 0.8, 4.0, C.dais, "Marble")
	disc("StepTopTrim", 0.71, 0.78, 4.03, C.gold, M.gold)
	disc("StepTopTrim2", 0.44, 0.48, 4.02, C.goldDeep, M.gold)

	-- ===================================================================
	-- ТРОН
	-- ===================================================================
	local throne = B:folder("Throne")
	local SEAT_Y = 2.2

	---------------------------------------------------------------- ножки
	local legs = B:folder("Legs", throne)
	-- Ножка-кабриоль с лапой, сжимающей шар. top — точка под рамой, out — направление «наружу» (горизонт.)
	local function cabriole(top, out, scale)
		scale = scale or 1
		local floorY = 0.8
		local h = top.Y - floorY
		local function at(o, y)
			return V(top.X + out.X * o, y, top.Z + out.Z * o)
		end
		-- колено → щиколотка
		local prof = {
			{ 0.02, 1.00, 0.34 },
			{ 0.10, 0.86, 0.36 },
			{ 0.12, 0.72, 0.31 },
			{ 0.07, 0.58, 0.24 },
			{ 0.00, 0.46, 0.18 },
			{ -0.02, 0.36, 0.15 },
			{ 0.01, 0.28, 0.14 },
		}
		local pts = {}
		for _, q in prof do
			table.insert(pts, { at(q[1] * scale, floorY + h * q[2]), q[3] * scale })
		end
		tube(legs, pts, C.gold, M.gold)
		-- завиток-«колено» снаружи
		local kneeP = at(0.2 * scale, floorY + h * 0.9)
		local side = out:Cross(Vector3.yAxis).Unit
		for i = 0, 9 do
			local a = i / 9 * math.pi * 1.6
			local r = 0.13 * (1 - i / 14)
			local p = kneeP + out * (math.cos(a) * r) + Vector3.yAxis * (math.sin(a) * r)
			ball(legs, p + side * 0.0, 0.11 * (1 - i / 16), C.goldHi, M.foil)
		end
		-- листок аканта вниз по ноге
		local leafCf = CFrame.new(at(0.16 * scale, floorY + h * 0.68)) * CFrame.fromMatrix(Vector3.zero, side, Vector3.yAxis, side:Cross(Vector3.yAxis)) * CFrame.Angles(0, 0, 0)
		ell(legs, leafCf * CFrame.Angles(0, 0, 0), V(0.12, 0.34, 0.12), C.goldHi, M.foil)
		-- лапа с шаром
		local ballC = V(top.X + out.X * 0.06, floorY + 0.125, top.Z + out.Z * 0.06)
		ball(legs, ballC, 0.25, C.goldHi, M.foil)
		local ankle = at(0.01 * scale, floorY + h * 0.28)
		local fwd = out
		for k = 0, 3 do
			local ang = (k / 4) * math.pi * 2 + math.pi / 4
			local dir = (fwd * math.cos(ang) + side * math.sin(ang))
			local mid = ballC + dir * 0.13 + Vector3.yAxis * 0.07
			local tip = ballC + dir * 0.12 + Vector3.yAxis * -0.08
			rod(legs, ankle, mid, 0.07, C.gold, M.gold)
			rod(legs, mid, tip, 0.06, C.gold, M.gold)
			ball(legs, mid, 0.075, C.gold, M.gold)
			ball(legs, tip, 0.065, C.goldHi, M.foil)
		end
	end
	local FL = V(1.92, 1.52, -1.12)
	cabriole(FL, V(0.7, 0, -0.7).Unit)
	cabriole(V(-FL.X, FL.Y, FL.Z), V(-0.7, 0, -0.7).Unit)
	cabriole(V(1.64, 1.52, 0.86), V(0.6, 0, 0.8).Unit, 0.85)
	cabriole(V(-1.64, 1.52, 0.86), V(-0.6, 0, 0.8).Unit, 0.85)

	---------------------------------------------------------------- рама сиденья (царга)
	local seat = B:folder("Seat", throne)
	local RAIL_Y0, RAIL_Y1 = 1.5, 1.95
	box(seat, CFrame.new(0, (RAIL_Y0 + RAIL_Y1) / 2, -1.3), V(3.5, RAIL_Y1 - RAIL_Y0, 0.24), C.gold, M.gold) -- перед
	box(seat, CFrame.new(1.75, (RAIL_Y0 + RAIL_Y1) / 2, -0.22), V(0.24, RAIL_Y1 - RAIL_Y0, 2.3), C.gold, M.gold) -- бока
	box(seat, CFrame.new(-1.75, (RAIL_Y0 + RAIL_Y1) / 2, -0.22), V(0.24, RAIL_Y1 - RAIL_Y0, 2.3), C.gold, M.gold)
	box(seat, CFrame.new(0, (RAIL_Y0 + 2.15) / 2, 0.82), V(3.5, 2.15 - RAIL_Y0, 0.3), C.goldDeep, M.gold) -- зад
	-- верхний валик царги
	rod(seat, V(-1.66, RAIL_Y1, -1.43), V(1.66, RAIL_Y1, -1.43), 0.12, C.goldHi, M.foil)
	rod(seat, V(1.88, RAIL_Y1, -1.2), V(1.88, RAIL_Y1, 0.75), 0.12, C.goldHi, M.foil)
	rod(seat, V(-1.88, RAIL_Y1, -1.2), V(-1.88, RAIL_Y1, 0.75), 0.12, C.goldHi, M.foil)
	-- бусины по низу царги
	beads(seat, { V(-1.62, RAIL_Y0 + 0.06, -1.43), V(1.62, RAIL_Y0 + 0.06, -1.43) }, 0.07, 0.075, C.goldHi, M.foil)
	-- фестон по низу передней царги: волна + раковина в центре
	do
		local pts = {}
		for i = 0, 40 do
			local x = -1.6 + 3.2 * i / 40
			local u = math.abs(x) / 1.6
			local y = RAIL_Y0 - 0.02 - 0.10 * math.sin(u * math.pi) - 0.16 * math.max(0, 1 - u * 4) ^ 2
			table.insert(pts, { V(x, y, -1.36), 0.075 })
		end
		tube(seat, pts, C.gold, M.gold)
		-- раковина (веер лепестков)
		for k = -3, 3 do
			local a = rad(k * 22)
			local cf = CFrame.new(0, RAIL_Y0 - 0.05, -1.42) * CFrame.Angles(0, 0, a) * CFrame.new(0, -0.12, 0)
			ell(seat, cf, V(0.1, 0.3, 0.08), C.goldHi, M.foil)
		end
		ball(seat, V(0, RAIL_Y0 + 0.02, -1.46), 0.12, C.goldHi, M.foil)
		-- рубин-кабошон в центре царги
		ell(seat, CFrame.new(0, (RAIL_Y0 + RAIL_Y1) / 2 + 0.02, -1.43), V(0.2, 0.15, 0.08), C.ruby, M.glass, { transparency = 0.2 })
		ell(seat, CFrame.new(0, (RAIL_Y0 + RAIL_Y1) / 2 + 0.02, -1.42), V(0.13, 0.09, 0.05), C.rubyCore, M.neon)
		-- завитки по бокам от рубина
		for s = -1, 1, 2 do
			for i = 0, 11 do
				local a = i / 11 * math.pi * 1.5
				local r = 0.12 * (1 - i / 18)
				local p = V(s * (0.32 + math.cos(a) * r * 1.6), (RAIL_Y0 + RAIL_Y1) / 2 + math.sin(a) * r, -1.44)
				ball(seat, p, 0.07 * (1 - i / 20), C.goldHi, M.foil)
			end
			rod(seat, V(s * 0.55, (RAIL_Y0 + RAIL_Y1) / 2, -1.44), V(s * 1.3, (RAIL_Y0 + RAIL_Y1) / 2, -1.44), 0.05, C.goldHi, M.foil)
		end
	end

	---------------------------------------------------------------- подушка сиденья (капитоне)
	local cushion = B:folder("Cushion", throne)
	box(cushion, CFrame.new(0, 2.0, -0.36), V(3.24, 0.2, 1.96), C.velvetSeat, M.velvet)
	-- валик спереди и по бокам
	rod(cushion, V(-1.5, 2.02, -1.22), V(1.5, 2.02, -1.22), 0.34, C.velvetSeat, M.velvet)
	rod(cushion, V(1.5, 2.02, -1.22), V(1.5, 2.02, 0.5), 0.34, C.velvetSeat, M.velvet)
	rod(cushion, V(-1.5, 2.02, -1.22), V(-1.5, 2.02, 0.5), 0.34, C.velvetSeat, M.velvet)
	ball(cushion, V(1.5, 2.02, -1.22), 0.345, C.velvetSeat, M.velvet)
	ball(cushion, V(-1.5, 2.02, -1.22), 0.345, C.velvetSeat, M.velvet)
	-- золотой шнур по низу подушки
	rod(cushion, V(-1.55, 1.9, -1.4), V(1.55, 1.9, -1.4), 0.05, C.goldHi, M.foil)
	-- пуфы
	local cols, rows = 4, 3
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local x = -1.2 + i * 0.8 + (j % 2) * 0.0
			local z = -0.95 + j * 0.62
			ell(cushion, CFrame.new(x, 2.06, z), V(0.86, 0.28, 0.7), C.velvetSeat, M.velvet)
		end
	end
	-- пуговицы между пуфами
	for i = 0, cols do
		for j = 0, rows do
			local x = -1.6 + i * 0.8
			local z = -1.26 + j * 0.62
			if math.abs(x) < 1.45 and z > -1.2 and z < 0.45 then
				ball(cushion, V(x, 2.11, z), 0.09, C.velvetDark, M.velvet)
			end
		end
	end

	---------------------------------------------------------------- подлокотники
	local arms = B:folder("Arms", throne)
	local function armSide(s)
		local x = 1.92 * s
		local zf = -1.12
		-- тумба: резной блок
		box(arms, CFrame.new(x, 2.0, zf), V(0.58, 1.0, 0.7), C.gold, M.gold)
		-- карниз и шейка
		box(arms, CFrame.new(x, 2.55, zf), V(0.68, 0.1, 0.8), C.goldHi, M.foil)
		box(arms, CFrame.new(x, 2.68, zf), V(0.5, 0.18, 0.6), C.goldDeep, M.gold)
		box(arms, CFrame.new(x, 2.8, zf), V(0.62, 0.08, 0.74), C.goldHi, M.foil)
		-- шапка-подушка
		box(arms, CFrame.new(x, 2.98, zf), V(0.62, 0.3, 0.76), C.gold, M.gold)
		rod(arms, V(x, 3.13, zf - 0.38), V(x, 3.13, zf + 0.38), 0.62, C.gold, M.gold)
		-- волюта спереди шапки (свиток)
		for i = 0, 14 do
			local a = i / 14 * math.pi * 1.7 - math.pi * 0.5
			local r = 0.2 * (1 - i / 22)
			local p = V(x, 3.1 + math.sin(a) * r, zf - 0.38 - 0.02 + -math.cos(a) * r * 0.25)
			ball(arms, p + V(s * 0.27, 0, 0), 0.1 * (1 - i / 26), C.goldHi, M.foil)
			ball(arms, p + V(-s * 0.27, 0, 0), 0.1 * (1 - i / 26), C.goldHi, M.foil)
		end
		-- заклёпки на лице шапки
		for _, q in { { -0.16, 3.25 }, { 0.16, 3.25 }, { 0, 2.95 } } do
			ball(arms, V(x + q[1], q[2], zf - 0.4), 0.07, C.goldHi, M.foil)
		end
		-- кабошон
		ell(arms, CFrame.new(x, 3.1, zf - 0.4), V(0.14, 0.17, 0.08), C.ruby, M.glass, { transparency = 0.2 })
		ell(arms, CFrame.new(x, 3.1, zf - 0.39), V(0.09, 0.11, 0.05), C.rubyCore, M.neon)
		-- резьба на лице тумбы: стебель-лист + завитки + розетка
		local fz = zf - 0.36
		ell(arms, CFrame.new(x, 2.05, fz), V(0.14, 0.62, 0.08), C.goldHi, M.foil)
		for k = -1, 1, 2 do
			ell(arms, CFrame.new(x + k * 0.08, 2.18, fz) * CFrame.Angles(0, 0, rad(-k * 35)), V(0.09, 0.36, 0.07), C.goldHi, M.foil)
			for i = 0, 10 do
				local a = i / 10 * math.pi * 1.6 + (if k > 0 then 0 else math.pi)
				local r = 0.1 * (1 - i / 16)
				ball(arms, V(x + k * 0.15 + math.cos(a) * r * k, 1.72 + math.sin(a) * r, fz - 0.01), 0.06, C.goldHi, M.foil)
			end
		end
		-- рамка вокруг резного поля
		local fr = { V(x - 0.25, 1.55, fz - 0.005), V(x + 0.25, 1.55, fz - 0.005), V(x + 0.25, 2.45, fz - 0.005), V(x - 0.25, 2.45, fz - 0.005) }
		for i = 1, 4 do
			rod(arms, fr[i], fr[i % 4 + 1], 0.05, C.goldHi, M.foil)
		end
		-- подлокотник: брус + бархатный валик
		box(arms, CFrame.new(x, 3.1, -0.12), V(0.4, 0.2, 1.4), C.gold, M.gold)
		rod(arms, V(x + s * 0.2, 3.0, -0.8), V(x + s * 0.2, 3.0, 0.6), 0.08, C.goldHi, M.foil)
		rod(arms, V(x - s * 0.2, 3.0, -0.8), V(x - s * 0.2, 3.0, 0.6), 0.08, C.goldHi, M.foil)
		ell(arms, CFrame.new(x, 3.25, -0.12), V(0.44, 0.3, 1.42), C.velvet, M.velvet)
		-- бархатная боковина под подлокотником
		box(arms, CFrame.new(x, 2.47, -0.12), V(0.16, 1.06, 1.4), C.velvet, M.velvet)
		-- золотая стойка в боковине
		rod(arms, V(x, 1.95, 0.5), V(x, 3.0, 0.5), 0.14, C.gold, M.gold)
	end
	armSide(1)
	armSide(-1)

	---------------------------------------------------------------- спинка
	local back = B:folder("Back", throne)
	local TILT = 5
	local BACK = CFrame.new(0, SEAT_Y, 0.62) * CFrame.Angles(rad(TILT), 0, 0)
	local function bp(x, v, w)
		return BACK:PointToWorldSpace(V(x, v, w))
	end
	local function bcf(x, v, w, rz)
		return BACK * CFrame.new(x, v, w) * CFrame.Angles(0, 0, rad(rz or 0))
	end

	-- контур панели (правая половина, снизу вверх), x — полуширина, v — высота над сиденьем
	local outlineR = {
		{ 1.50, -0.05 },
		{ 1.48, 0.7 },
		{ 1.52, 1.5 },
		{ 1.60, 2.3 },
		{ 1.70, 3.1 },
		{ 1.78, 3.9 },
		{ 1.82, 4.6 },
		{ 1.80, 5.05 },
		{ 1.70, 5.42 },
		{ 1.50, 5.70 },
		{ 1.18, 5.88 },
		{ 0.78, 5.98 },
		{ 0.38, 6.04 },
		{ 0.0, 6.06 },
	}
	local function halfWidth(v)
		-- полуширина панели на высоте v (по контуру)
		if v <= outlineR[1][2] then
			return outlineR[1][1]
		end
		for i = 2, #outlineR do
			local a, b = outlineR[i - 1], outlineR[i]
			if v <= b[2] then
				local t = (v - a[2]) / (b[2] - a[2])
				return a[1] + (b[1] - a[1]) * t
			end
		end
		return 0
	end
	-- гладкий контур (вся дуга: справа снизу → верх → слева снизу), в плоскости спинки
	local ctrl = {}
	for i = 1, #outlineR do
		table.insert(ctrl, V(outlineR[i][1], outlineR[i][2], 0))
	end
	for i = #outlineR - 1, 1, -1 do
		table.insert(ctrl, V(-outlineR[i][1], outlineR[i][2], 0))
	end
	local outline = spline(ctrl, 3)

	-- панель горизонтальными полосами
	local PANEL_D = 0.36
	do
		local v = -0.1
		while v < 6.06 do
			local step = if v < 4.6 then 0.4 elseif v < 5.4 then 0.12 else 0.06
			local v1 = math.min(6.06, v + step)
			local w = math.min(halfWidth(v), halfWidth(v1))
			if w > 0.05 then
				box(back, BACK * CFrame.new(0, (v + v1) / 2, PANEL_D / 2), V(w * 2, v1 - v + 0.002, PANEL_D), C.velvet, M.velvet)
			end
			v = v1
		end
	end
	-- мягкая набивка спинки
	ell(back, BACK * CFrame.new(0, 2.75, 0.17), V(2.95, 5.7, 0.64), C.velvet, M.velvet)
	ell(back, BACK * CFrame.new(0, 0.55, 0.13), V(2.7, 1.4, 0.5), C.velvet, M.velvet)

	-- рама: внешний валик, ребро, бусины изнутри, задняя трубка
	do
		local front = {}
		local edgePts = {}
		for i, p in outline do
			-- нормаль наружу (в плоскости)
			local a = outline[math.max(1, i - 1)]
			local b = outline[math.min(#outline, i + 1)]
			local t = (b - a).Unit
			local nrm = V(t.Y, -t.X, 0) -- поворот касательной на −90°: снаружи для обхода по часовой
			if p.X < 0 then
				-- для левой половины обход идёт вниз — нормаль та же формула работает
			end
			local q = p + nrm * 0.03
			table.insert(front, { bp(q.X, q.Y, -0.04), 0.22 })
			table.insert(edgePts, { p + nrm * 0.1, nrm })
		end
		tube(back, front, C.gold, M.gold)
		-- ребро (торец рамы) — бруски вдоль контура
		for i = 1, #edgePts - 1 do
			local a, b = edgePts[i][1], edgePts[i + 1][1]
			local cf, len = along(bp(a.X, a.Y, PANEL_D / 2), bp(b.X, b.Y, PANEL_D / 2))
			box(back, cf, V(len + 0.03, 0.18, PANEL_D + 0.1), C.goldDeep, M.gold)
		end
		-- задняя трубка
		local backT = {}
		for i = 1, #outline, 2 do
			local p = outline[i]
			table.insert(backT, { bp(p.X * 1.0, p.Y, PANEL_D + 0.04), 0.16 })
		end
		tube(back, backT, C.gold, M.gold)
		-- бусины внутри контура
		local inner = {}
		for _, p in outline do
			local w = halfWidth(p.Y)
			local sx = if math.abs(p.X) > 1e-3 then p.X / math.abs(p.X) else 0
			-- сдвиг внутрь: к центру по x и вниз у верха
			local q = V(p.X - sx * 0.2 * math.min(1, math.abs(p.X) / math.max(w, 0.1)), p.Y - (if p.Y > 5.3 then 0.2 * math.clamp((p.Y - 5.3) / 0.7, 0, 1) else 0), 0)
			table.insert(inner, bp(q.X, q.Y, -0.035))
		end
		beads(back, inner, 0.085, 0.09, C.goldHi, M.foil)
	end

	-- Волюта (спираль из шариков-трубки) в плоскости спинки.
	-- c — центр (x,v), r0→r1 радиус, a0 — начальный угол, turns — обороты (знак = направление), d0→d1 толщина
	local function volute(parent, cx, cv, w, r0, r1, a0, turns, d0, d1, color, mat)
		local n = math.max(6, math.floor(math.abs(turns) * 22))
		local pts = {}
		for i = 0, n do
			local t = i / n
			local a = a0 + turns * t * math.pi * 2
			local r = r0 * (r1 / r0) ^ t
			table.insert(pts, { bp(cx + math.cos(a) * r, cv + math.sin(a) * r, w - 0.02 * t), d0 + (d1 - d0) * t })
		end
		tube(parent, pts, color or C.goldHi, mat or M.foil)
	end

	-- Кривая-трубка по контрольным точкам спинки {x,v,w} с толщиной d0→d1
	local function sweep(parent, ctl, d0, d1, color, mat, n)
		local pv = {}
		for _, q in ctl do
			table.insert(pv, V(q[1], q[2], q[3] or -0.06))
		end
		local pts = spline(pv, n or 4)
		local out = {}
		for i, p in pts do
			local t = (i - 1) / math.max(1, #pts - 1)
			table.insert(out, { bp(p.X, p.Y, p.Z), d0 + (d1 - d0) * t })
		end
		tube(parent, out, color or C.goldHi, mat or M.foil)
	end

	-- Розетка: центр + венчик лепестков
	local function rosette(parent, cx, cv, w, r, petals, jewel)
		ball(parent, bp(cx, cv, w - 0.02), r * 0.9, C.goldHi, M.foil)
		for k = 0, petals - 1 do
			local a = k / petals * math.pi * 2
			ell(parent, BACK * CFrame.new(cx + math.cos(a) * r * 0.75, cv + math.sin(a) * r * 0.75, w) * CFrame.Angles(0, 0, a), V(r * 0.85, r * 0.5, r * 0.4), C.gold, M.gold)
		end
		if jewel then
			ell(parent, BACK * CFrame.new(cx, cv, w - r * 0.42), V(r * 0.5, r * 0.5, r * 0.3), jewel[1], M.glass, { transparency = 0.15 })
			ell(parent, BACK * CFrame.new(cx, cv, w - r * 0.38), V(r * 0.32, r * 0.32, r * 0.2), jewel[2], M.neon)
		end
	end

	-- Лист аканта: веер эллипсоидов
	local function leaf(parent, cx, cv, w, ang, len)
		for k = -1, 1 do
			local a = ang + k * 28
			ell(parent, bcf(cx, cv, w, a) * CFrame.new(0, len * 0.45, 0), V(len * 0.32, len, 0.08), if k == 0 then C.goldHi else C.gold, if k == 0 then M.foil else M.gold)
		end
	end

	local orn = B:folder("Ornament", back)
	-- «уши» по бокам спинки: C-завиток с розеткой (на уровне плеч) и малый завиток выше
	for _, s in { 1, -1 } do
		local ex = halfWidth(3.2) * s
		sweep(orn, { { ex - 0.05 * s, 2.6 }, { ex + 0.25 * s, 2.9 }, { ex + 0.42 * s, 3.3 }, { ex + 0.38 * s, 3.62 } }, 0.2, 0.15)
		volute(orn, ex + 0.22 * s, 3.62, -0.08, 0.17, 0.05, 0, 1.3 * s, 0.15, 0.07)
		rosette(orn, ex + 0.22 * s, 3.62, -0.12, 0.13, 7)
		leaf(orn, ex + 0.25 * s, 2.55, -0.06, 180 + 20 * s, 0.42)
		-- верхний угол
		local ux = halfWidth(5.1) * s
		sweep(orn, { { ux - 0.1 * s, 4.75 }, { ux + 0.22 * s, 4.95 }, { ux + 0.3 * s, 5.3 } }, 0.17, 0.13)
		volute(orn, ux + 0.17 * s, 5.32, -0.08, 0.13, 0.04, -0.2 * s, 1.2 * s, 0.13, 0.06)
	end

	-- ГРЕБЕНЬ (кресло-«корона» над спинкой)
	local crest = B:folder("Crest", back)
	local CW = -0.08 -- глубина гребня (чуть впереди плоскости спинки)
	-- основание гребня — массивная фигурная планка поверх верхней кромки панели
	do
		local base = {}
		for i = 0, 30 do
			local x = -1.75 + 3.5 * i / 30
			local v = 5.85 + 0.22 * (1 - (x / 1.75) ^ 2) - 0.1 * math.max(0, math.abs(x) - 1.3)
			table.insert(base, { bp(x, v, CW), 0.26 })
		end
		tube(crest, base, C.gold, M.gold)
		-- задник гребня (сплошная золотая пластина)
		local v = 5.9
		while v < 7.0 do
			local v1 = v + 0.1
			local w = 1.65 * math.sqrt(math.max(0, 1 - ((v1 - 5.9) / 1.15) ^ 2)) * (0.6 + 0.4 * (1 - (v1 - 5.9) / 1.1))
			if w > 0.05 then
				box(crest, BACK * CFrame.new(0, (v + v1) / 2, 0.12), V(w * 2, 0.102, 0.18), C.goldDeep, M.gold)
			end
			v = v1
		end
	end
	for _, s in { 1, -1 } do
		-- большой C-завиток: от центра наружу и вниз, закручивается у угла
		sweep(crest, { { 0.25 * s, 6.55 }, { 0.75 * s, 6.85 }, { 1.3 * s, 6.75 }, { 1.72 * s, 6.4 }, { 1.92 * s, 5.95 } }, 0.24, 0.17)
		volute(crest, 1.78 * s, 5.95, CW - 0.02, 0.16, 0.04, 0, -1.4 * s, 0.17, 0.07)
		-- внутренний S-завиток вверх к короне
		sweep(crest, { { 0.18 * s, 6.25 }, { 0.5 * s, 6.35 }, { 0.62 * s, 6.65 }, { 0.48 * s, 6.95 } }, 0.15, 0.11)
		volute(crest, 0.36 * s, 6.92, CW - 0.04, 0.12, 0.035, 0, 1.2 * s, 0.11, 0.05)
		-- розетки
		rosette(crest, 1.05 * s, 6.28, CW - 0.06, 0.17, 8)
		rosette(crest, 1.62 * s, 6.85, CW - 0.04, 0.1, 6)
		-- листья
		leaf(crest, 1.35 * s, 6.95, CW - 0.02, -40 * s, 0.4)
		leaf(crest, 0.72 * s, 6.05, CW - 0.06, -70 * s, 0.34)
		-- бусины по нижней кромке гребня
	end
	-- картуш в центре: овальный медальон с большим рубином
	do
		local cx, cv = 0, 6.5
		local ring = {}
		for i = 0, 28 do
			local a = i / 28 * math.pi * 2
			table.insert(ring, bp(cx + math.cos(a) * 0.3, cv + math.sin(a) * 0.38, CW - 0.12))
		end
		beads(crest, ring, 0.08, 0.075, C.goldHi, M.foil)
		ell(crest, BACK * CFrame.new(cx, cv, CW - 0.06), V(0.6, 0.76, 0.16), C.gold, M.gold)
		ell(crest, BACK * CFrame.new(cx, cv, CW - 0.13), V(0.3, 0.38, 0.16), C.ruby, M.glass, { transparency = 0.15 })
		ell(crest, BACK * CFrame.new(cx, cv, CW - 0.11), V(0.2, 0.26, 0.1), C.rubyCore, M.neon)
		leaf(crest, 0, 6.0, CW - 0.1, 180, 0.4)
	end

	-- КОРОНА (вертикальная, на вершине гребня): основание Y≈9.5, верх креста Y≈10.5
	local crown = B:folder("Crown", throne)
	do
		local base = bp(0, 7.12, 0.1)
		local cy = base.Y
		local cz = base.Z
		local R = 0.46
		local function cp(a, r, y)
			-- точка на окружности короны: a=0 — к зрителю (−Z)
			return V(math.sin(a) * r, y, cz - math.cos(a) * r)
		end
		-- обод
		part({ parent = crown, name = "CrownBand", cf = CFrame.new(0, cy + 0.12, cz) * CFrame.Angles(0, 0, math.pi / 2), size = V(0.26, R * 2, R * 2), shape = "Cylinder", color = C.goldHi, material = M.foil })
		part({ parent = crown, name = "CrownRim", cf = CFrame.new(0, cy + 0.01, cz) * CFrame.Angles(0, 0, math.pi / 2), size = V(0.06, R * 2 + 0.08, R * 2 + 0.08), shape = "Cylinder", color = C.gold, material = M.gold })
		part({ parent = crown, name = "CrownRim2", cf = CFrame.new(0, cy + 0.255, cz) * CFrame.Angles(0, 0, math.pi / 2), size = V(0.05, R * 2 + 0.06, R * 2 + 0.06), shape = "Cylinder", color = C.gold, material = M.gold })
		-- бархатная шапка
		ell(crown, CFrame.new(0, cy + 0.32, cz), V(R * 1.9, 0.62, R * 1.9), C.velvet, M.velvet)
		-- камни на ободе и жемчуг
		local gems = { { C.ruby, C.rubyCore }, { C.emerald, C.emeraldCore }, { C.sapphire, C.sapphireCore }, { C.emerald, C.emeraldCore } }
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local g = gems[k % 4 + 1]
			local p = cp(a, R + 0.02, cy + 0.13)
			local cf = CFrame.new(p) * CFrame.Angles(0, -a, 0)
			ell(crown, cf, V(0.13, 0.14, 0.07), g[1], M.glass, { transparency = 0.15 })
			ell(crown, cf * CFrame.new(0, 0, 0.005), V(0.08, 0.09, 0.05), g[2], M.neon)
			ball(crown, cp(a + math.pi / 8, R + 0.015, cy + 0.13), 0.06, C.pearl, "SmoothPlastic")
		end
		-- зубцы: крест-пате и «лилии» по кругу + жемчужины
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local p = cp(a, R - 0.02, cy + 0.36)
			local cf = CFrame.new(p) * CFrame.Angles(0, -a, 0)
			if k % 2 == 0 then
				-- крест
				box(crown, cf, V(0.08, 0.22, 0.04), C.goldHi, M.foil)
				box(crown, cf * CFrame.new(0, 0.03, 0), V(0.2, 0.07, 0.04), C.goldHi, M.foil)
				ell(crown, cf * CFrame.new(0, 0.02, -0.025), V(0.06, 0.06, 0.03), C.ruby, M.glass, { transparency = 0.1 })
			else
				-- лилия
				ell(crown, cf, V(0.08, 0.24, 0.05), C.goldHi, M.foil)
				ell(crown, cf * CFrame.new(0.06, -0.02, 0) * CFrame.Angles(0, 0, rad(-35)), V(0.05, 0.16, 0.04), C.goldHi, M.foil)
				ell(crown, cf * CFrame.new(-0.06, -0.02, 0) * CFrame.Angles(0, 0, rad(35)), V(0.05, 0.16, 0.04), C.goldHi, M.foil)
				ball(crown, p + V(0, 0.15, 0), 0.06, C.pearl, "SmoothPlastic")
			end
		end
		-- дуги (2 крест-накрест) из бусин
		for _, rot in { 0, math.pi / 2 } do
			local arc = {}
			for i = 0, 24 do
				local t = i / 24 * math.pi
				local x = math.cos(t) * (R - 0.04)
				local y = cy + 0.27 + math.sin(t) * 0.42
				table.insert(arc, V(x * math.cos(rot), y, cz + x * math.sin(rot)))
			end
			beads(crown, arc, 0.075, 0.06, C.goldHi, M.foil)
		end
		-- держава с крестом
		ball(crown, V(0, cy + 0.78, cz), 0.2, C.goldHi, M.foil)
		rod(crown, V(-0.11, cy + 0.78, cz), V(0.11, cy + 0.78, cz), 0.03, C.gold, M.gold)
		box(crown, CFrame.new(0, cy + 0.97, cz), V(0.05, 0.2, 0.05), C.goldHi, M.foil)
		box(crown, CFrame.new(0, cy + 0.99, cz), V(0.15, 0.05, 0.05), C.goldHi, M.foil)
		ball(crown, V(0, cy + 0.99, cz - 0.03), 0.05, C.ruby, M.glass)
	end

	-- ===================================================================
	-- СВЕТ
	-- ===================================================================
	local lights = B:folder("Lights")
	local LAMP = V(0, 30, -2)
	local TARGET = V(0, 3.6, 0.35)
	local lampCf = aim(LAMP, TARGET)
	local lamp = part({ parent = lights, name = "SpotLamp", cf = lampCf, size = V(1.6, 1.6, 1.2), shape = "Block", color = C.void, material = "SmoothPlastic", castShadow = false })
	lamp.Transparency = 1
	-- корпус и линза (видны, если камера посмотрит вверх)
	part({ parent = lights, name = "LampHousing", cf = lampCf * CFrame.new(0, 0, 0.9) * CFrame.Angles(0, math.pi / 2, 0), size = V(1.8, 1.5, 1.5), shape = "Cylinder", color = rgb(10, 10, 12), material = "Metal", castShadow = false })
	part({ parent = lights, name = "LampLens", cf = lampCf * CFrame.new(0, 0, 0.02) * CFrame.Angles(0, math.pi / 2, 0), size = V(0.06, 1.3, 1.3), shape = "Cylinder", color = C.light, material = M.neon, castShadow = false })
	B:light(lamp, "SpotLight", { Name = "KeyLight", Brightness = 14, Range = 60, Angle = 20, Face = "Front", Shadows = true, Color = C.light })
	B:light(lamp, "SpotLight", { Name = "KeySoft", Brightness = 3, Range = 60, Angle = 34, Face = "Front", Shadows = false, Color = C.light })

	-- заполняющие (очень слабые): спереди на уровне камеры, контровой сзади-сверху, золотой отсвет снизу
	local function spot(name, pos, target, props)
		local p = part({ parent = lights, name = name, cf = aim(pos, target), size = V(0.4, 0.4, 0.4), color = C.void, castShadow = false, canQuery = false })
		p.Transparency = 1
		local kind = props.kind or "SpotLight"
		props.kind = nil
		local l = B:light(p, kind, props)
		l.Name = name .. "Light"
		return p
	end
	spot("FillFront", V(0, 6.5, -12), V(0, 5, 0.5), { Brightness = 0.7, Range = 24, Angle = 40, Face = "Front", Shadows = false, Color = rgb(255, 214, 160) })
	spot("RimBack", V(0, 17, 7.5), V(0, 7.5, 0.8), { Brightness = 1.4, Range = 22, Angle = 38, Face = "Front", Shadows = false, Color = rgb(255, 220, 170) })
	spot("GoldBounce", V(0, 1.3, -3.2), V(0, 2.4, 0), { kind = "PointLight", Brightness = 0.5, Range = 6, Shadows = false, Color = rgb(255, 190, 110) })

	-- ===================================================================
	-- ОБЪЁМНЫЙ ЛУЧ (Beam, лицом к камере)
	-- ===================================================================
	local fx = B:folder("FX")
	local function anchor(name, pos)
		local p = part({ parent = fx, name = name, pos = pos, size = V(0.2, 0.2, 0.2), color = C.void, castShadow = false, canQuery = false })
		p.Transparency = 1
		local a = Instance.new("Attachment")
		a.Name = name .. "Att"
		a.Parent = p
		return a
	end
	local function ns(list)
		local kps = {}
		for _, q in list do
			table.insert(kps, NumberSequenceKeypoint.new(q[1], q[2], q[3] or 0))
		end
		return NumberSequence.new(kps)
	end
	local function beam(name, a0, a1, w0, w1, trans, color, z)
		local bm = Instance.new("Beam")
		bm.Name = name
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.Width0 = w0
		bm.Width1 = w1
		bm.FaceCamera = true
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Segments = 20
		bm.Color = ColorSequence.new(color)
		bm.Transparency = trans
		bm.ZOffset = z or 0
		bm.Parent = a0.Parent
		return bm
	end
	-- Задний слой: ось от лампы к полу за троном (весь позади трона/коня) — основной видимый конус.
	-- Передний слой: ось от лампы к полу перед подиумом — лёгкая дымка поверх сцены.
	local TOP_P = LAMP + (TARGET - LAMP).Unit * 0.8
	local BACK_P = V(0, 0.02, 6.5)
	local FRONT_P = V(0, 0.02, -5.6)
	local top = anchor("ShaftTop", TOP_P)
	local backEnd = anchor("ShaftBackEnd", BACK_P)
	local frontEnd = anchor("ShaftFrontEnd", FRONT_P)
	local coneTan = math.tan(rad(10.5))
	local Lb = (BACK_P - TOP_P).Magnitude
	local Lf = (FRONT_P - TOP_P).Magnitude
	local warm = rgb(255, 232, 196)
	local layers = {
		{ f = 0.35, t0 = 0.55, tm = 0.8 },
		{ f = 0.6, t0 = 0.7, tm = 0.88 },
		{ f = 0.85, t0 = 0.8, tm = 0.93 },
		{ f = 1.05, t0 = 0.88, tm = 0.96 },
	}
	for i, ly in layers do
		beam("LightShaftBack" .. i, top, backEnd, 0.5 + ly.f * 0.4, 2 * Lb * coneTan * ly.f, ns({ { 0, ly.t0 }, { 0.45, ly.tm }, { 0.8, 0.97 }, { 1, 1 } }), warm, 0)
	end
	for i, ly in layers do
		if i >= 2 then
			beam("LightShaftFront" .. i, top, frontEnd, 0.5 + ly.f * 0.4, 2 * Lf * coneTan * ly.f, ns({ { 0, math.min(0.97, ly.t0 + 0.12) }, { 0.45, math.min(0.98, ly.tm + 0.04) }, { 0.8, 0.985 }, { 1, 1 } }), warm, 0)
		end
	end

	-- ===================================================================
	-- ЧАСТИЦЫ
	-- ===================================================================
	local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
	local function volume(name, pos, size)
		local p = part({ parent = fx, name = name, pos = pos, size = size, color = C.void, castShadow = false, canQuery = false })
		p.Transparency = 1
		return p
	end
	local function emitter(parent, name, props)
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = SPARK_TEX
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Top
		for k, v in props do
			e[k] = v
		end
		e.Parent = parent
		return e
	end
	-- золотые искры в воздухе вокруг трона (мерцают: размер/прозрачность пульсируют)
	emitter(volume("SparkleVolume", V(0, 6, -0.6), V(8, 9, 5)), "ThroneSparkles", {
		Rate = 28,
		Lifetime = NumberRange.new(1.6, 3.2),
		Speed = NumberRange.new(0.1, 0.45),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = V(0, -0.12, 0),
		Drag = 0.8,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-45, 45),
		Size = ns({ { 0, 0 }, { 0.12, 0.16, 0.04 }, { 0.3, 0.07 }, { 0.5, 0.18, 0.05 }, { 0.7, 0.06 }, { 0.85, 0.14 }, { 1, 0 } }),
		Transparency = ns({ { 0, 1 }, { 0.1, 0.05 }, { 0.3, 0.55 }, { 0.5, 0 }, { 0.7, 0.6 }, { 0.85, 0.1 }, { 1, 1 } }),
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 226, 140)), ColorSequenceKeypoint.new(0.5, rgb(255, 200, 90)), ColorSequenceKeypoint.new(1, rgb(255, 238, 190)) }),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		ZOffset = 0.5,
	})
	-- пылинки в конусе света (освещаются прожектором)
	emitter(volume("DustVolume", V(0, 8.5, -0.4), V(9, 15, 7)), "Dust", {
		Rate = 70,
		Lifetime = NumberRange.new(6, 10),
		Speed = NumberRange.new(0.03, 0.15),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = V(0, -0.015, 0),
		Drag = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		Size = ns({ { 0, 0.035, 0.015 }, { 1, 0.03, 0.015 } }),
		Transparency = ns({ { 0, 1 }, { 0.2, 0.45 }, { 0.8, 0.5 }, { 1, 1 } }),
		Color = ColorSequence.new(rgb(255, 240, 214)),
		LightEmission = 0.4,
		LightInfluence = 0.6,
		Brightness = 2,
	})
	-- блики-звёздочки на золоте (гребень, корона, тумбы подлокотников)
	local glint = {
		Rate = 3.5,
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(0, 0),
		Rotation = NumberRange.new(-15, 15),
		RotSpeed = NumberRange.new(-30, 30),
		Size = ns({ { 0, 0 }, { 0.4, 0.75, 0.2 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.3 }, { 0.5, 0 }, { 1, 1 } }),
		Color = ColorSequence.new(rgb(255, 236, 190)),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 2.5,
		ZOffset = 1,
	}
	emitter(volume("GlintCrest", bp(0, 6.6, -0.25), V(3.8, 1.4, 0.2)), "ThroneGlints", glint)
	local gl = table.clone(glint)
	gl.Rate = 1.5
	emitter(volume("GlintArmL", V(-1.92, 3.0, -1.5), V(0.6, 0.6, 0.1)), "ThroneGlintsL", gl)
	emitter(volume("GlintArmR", V(1.92, 3.0, -1.5), V(0.6, 0.6, 0.1)), "ThroneGlintsR", gl)

	root:SetAttribute("SeatTopY", SEAT_Y)
	root:SetAttribute("DaisTopY", 0.8)
end
