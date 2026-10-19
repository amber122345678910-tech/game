--!nocheck
-- Декорация Throne (S11): чёрная пустота, круглый подиум, золотой резной трон с красным бархатом,
-- корона на гребне спинки, прожектор сверху с видимым конусом света (Beam), пылинки и золотые искры.
--
-- Контракт (AGENTS.md): трон в (0,0,0) лицом в −Z; верх подиума Y=0.8 (вперёд до z≈−3.5, x±4);
-- верх сиденья Y=2.2, сиденье z∈[−1.3,0.6], ширина 3.2; спинка от z≈0.6, до Y≈8.4; корона до Y≈10.4;
-- подлокотники x=±1.92, верх Y≈3.4. Прожектор (0,30,−4) — чуть впереди, чтобы золото ловило свет фасадами.
--
-- Форма по кадрам S11: спинка-«баллон» (лёгкая талия, широкий эллиптический купол) в тонком резном багете;
-- орнамент собран в гребне (C-завитки, круглые волюты, розетки, картуш с рубином, корона) и в «ушах» на
-- высоте плеч; подлокотники — резные стойки: шапка-свиток (валик со спиралью на торце, верх Y=3.43,
-- z∈[−1.45,−0.79] — на неё кладёт руки анимация S11), под ней манжета и панель-лира; ниже — кабриоли с
-- лапой на шаре. Капитоне сиденья, кисти на передних углах подушки.
-- Золото — настоящие Part (Ball/Cylinder/Block, Metal/Foil); эллипсоиды (SpecialMesh) — только бархат.
--
-- Имена для эффектов планов (shot.effects):
--   ParticleEmitter: "ThroneSparkles" (золотые искры), "Dust" (пылинки), "ThroneGlints" / "ThroneGlintsL" / "ThroneGlintsR" (блики на золоте)
--   SpotLight "KeyLight" (+ мягкий ореол "KeySoft") в детали "SpotLamp"; слабые "FillFrontLight", "RimBackLight"
--   Beam "LightShaftBack01..24" (конус за троном), "LightShaftFront06..24" (дымка перед сценой) — в детали "ShaftTop"
--   Атрибуты модели: SeatTopY, DaisTopY, ArmX, ArmTopY, ArmFrontZ, BackTopY, CrownTopY

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
	gold = rgb(224, 205, 158), -- основное золото, бледное «шампанское» как в клипе (Metal)
	goldHi = rgb(246, 236, 206), -- рельеф/орнамент (Foil)
	goldDeep = rgb(150, 126, 80), -- фон резьбы, торцы
	velvet = rgb(176, 38, 48), -- бархат спинки (малиновый: под тёплым светом даёт коралловый, как в клипе)
	velvetSeat = rgb(124, 6, 20), -- бархат сиденья (глубже, как в клипе)
	velvetDark = rgb(72, 2, 10), -- пуговицы, складки
	ruby = rgb(226, 18, 52),
	rubyCore = rgb(150, 0, 22),
	sapphire = rgb(40, 92, 236),
	sapphireCore = rgb(10, 30, 150),
	emerald = rgb(24, 196, 110),
	emeraldCore = rgb(0, 96, 44),
	pearl = rgb(244, 238, 224),
	void = rgb(0, 0, 0),
	floor = rgb(5, 5, 6),
	dais = rgb(15, 13, 14),
	light = rgb(255, 241, 224), -- почти нейтральный тёплый: золото остаётся бледным, как в клипе
}

local M = { gold = "Metal", foil = "Foil", velvet = "Fabric", glass = "Glass", neon = "Neon" }

-- ===== Геометрия =====

-- CFrame с осью X вдоль (b − a), центр посередине (без NaN на вертикали).
local function along(a, b)
	local d = b - a
	local len = d.Magnitude
	local x = if len > 1e-6 then d / len else Vector3.xAxis
	local up = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y, z), len
end

-- CFrame в pos, у которого Front (−Z) смотрит на target.
local function aim(pos, target)
	local f = (target - pos).Unit
	local up = if math.abs(f.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local x = f:Cross(up).Unit
	local y = x:Cross(f).Unit
	return CFrame.fromMatrix(pos, x, y, -f)
end

-- Catmull-Rom через точки (Vector3), n отрезков на участок.
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
			table.insert(out, (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
		end
	end
	table.insert(out, pts[count])
	return out
end

-- Равномерная (по длине) выборка ломаной: { {pos, s 0..1}, ... }
local function resample(pts, step)
	local L = 0
	for i = 2, #pts do
		L += (pts[i] - pts[i - 1]).Magnitude
	end
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
	local function with(spec, extra)
		for k, v in extra or {} do
			spec[k] = v
		end
		return part(spec)
	end
	local function rod(parent, a, b, d, color, mat, extra)
		local cf, len = along(a, b)
		return with({ parent = parent, cf = cf, size = V(len, d, d), shape = "Cylinder", color = color, material = mat }, extra)
	end
	local function ball(parent, p, d, color, mat, extra)
		return with({ parent = parent, pos = p, size = V(d, d, d), shape = "Ball", color = color, material = mat }, extra)
	end
	local function ell(parent, cf, size, color, mat, extra)
		return with({ parent = parent, cf = cf, size = size, mesh = "Sphere", color = color, material = mat }, extra)
	end
	local function box(parent, cf, size, color, mat, extra)
		return with({ parent = parent, cf = cf, size = size, color = color, material = mat }, extra)
	end
	-- ВАЖНО: на SpecialMesh Roblox не показывает Material, поэтому всё золото/стекло/неон — настоящие Part
	-- (Ball, Cylinder, Block); эллипсоиды (SpecialMesh) — только для бархата, где важен цвет.

	-- Камень-кабошон: стеклянный шар + неоновое ядро
	local function gem(parent, pos, d, color, core)
		ball(parent, pos, d, color, M.glass, { transparency = 0.2 })
		ball(parent, pos, d * 0.58, core, M.neon, { castShadow = false })
	end
	-- Огранённый камень: стеклянный куб, повёрнутый вершиной к зрителю (грани ловят блики) + неоновое ядро.
	-- cf — центр, −Z cf — «наружу».
	local function cutGem(parent, cf, edge, color, core)
		box(parent, cf * CFrame.Angles(0, 0, rad(45)) * CFrame.Angles(rad(35.26), 0, 0) * CFrame.Angles(0, rad(45), 0), V(edge, edge, edge), color, M.glass, { transparency = 0.2 })
		ball(parent, cf.Position, edge * 0.9, core, M.neon, { castShadow = false })
	end
	-- Лепесток/лист «капсулой»: цилиндр от a к b + шарик на кончике
	local function petal(parent, a, b, d, color, mat)
		rod(parent, a, b, d, color, mat)
		ball(parent, b, d * 1.03, color, mat)
	end

	-- Гладкая трубка: pts = { {pos, d}, ... }. Шарики только на концах и на заметных изгибах,
	-- на плавных изгибах цилиндры чуть удлиняются, чтобы не было щелей.
	local function tube(parent, pts, color, mat, closed)
		local n = #pts
		if n < 2 then
			return
		end
		local function idx(i)
			return ((i - 1) % n) + 1
		end
		local ballAt, extAt = {}, {}
		for i = 1, n do
			if not closed and (i == 1 or i == n) then
				ballAt[i], extAt[i] = true, 0
			else
				local p = pts[i][1]
				local a = p - pts[idx(i - 1)][1]
				local b = pts[idx(i + 1)][1] - p
				local ang = 0
				if a.Magnitude > 1e-4 and b.Magnitude > 1e-4 then
					ang = math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
				end
				if ang > rad(40) then
					ballAt[i], extAt[i] = true, 0
				else
					extAt[i] = pts[i][2] * 0.5 * math.tan(ang / 2) + 0.004
				end
			end
		end
		for i = 1, n do
			if ballAt[i] then
				ball(parent, pts[i][1], pts[i][2] * 1.03, color, mat)
			end
		end
		for i = 1, (if closed then n else n - 1) do
			local j = idx(i + 1)
			local p, q = pts[i][1], pts[j][1]
			local L = (q - p).Magnitude
			if L > 0.004 then
				local u = (q - p) / L
				rod(parent, p - u * extAt[i], q + u * extAt[j], math.min(pts[i][2], pts[j][2]), color, mat)
			end
		end
	end

	-- skip — точки, где бусина уже есть (не дублировать); замкнутое кольцо не повторяет первую бусину
	local function beads(parent, pts, d, step, color, mat, skip)
		local list = resample(pts, step)
		if #list > 2 and (list[1][1] - list[#list][1]).Magnitude < step * 0.5 then
			table.remove(list)
		end
		for _, it in list do
			local ok = true
			for _, q in skip or {} do
				if (q - it[1]).Magnitude < d * 0.6 then
					ok = false
				end
			end
			if ok then
				ball(parent, it[1], d, color, mat)
			end
		end
	end

	-- ===================================================================
	-- КОМНАТА: чёрная коробка (небо не видно ни в кадре, ни в отражениях)
	-- ===================================================================
	local room = B:folder("Room")
	part({ parent = room, name = "Floor", pos = V(0, -0.5, 0), size = V(140, 1, 140), color = C.floor, material = "SmoothPlastic" })
	local function wall(name, pos, size)
		part({ parent = room, name = name, pos = pos, size = size, color = C.void, material = "SmoothPlastic", castShadow = false })
	end
	wall("WallN", V(0, 25, -70.5), V(139.9, 51.9, 1))
	wall("WallS", V(0, 25, 70.5), V(139.9, 51.9, 1))
	wall("WallW", V(-70.5, 25, 0), V(1, 52, 142))
	wall("WallE", V(70.5, 25, 0), V(1, 52, 142))
	wall("Ceiling", V(0, 51.52, 0), V(142.2, 1, 142.2))

	-- ===================================================================
	-- ПОДИУМ: две круглые ступени чёрного мрамора с золотыми кантами
	-- ===================================================================
	local dais = B:folder("Dais")
	local DZ = 0.5 -- центр подиума по Z (фронт верхней ступени: 0.5 − 4.0 = −3.5)
	local function disc(name, y0, y1, r, color, mat)
		return part({ parent = dais, name = name, cf = CFrame.new(0, (y0 + y1) / 2, DZ) * CFrame.Angles(0, 0, math.pi / 2), size = V(y1 - y0, r * 2, r * 2), shape = "Cylinder", color = color, material = mat })
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
	local FLOOR_Y = 0.8
	local ARM_X = 1.92 -- ось подлокотников
	local POST_Z = -1.12 -- ось передних стоек (шапка-свиток z∈[−1.45,−0.79])
	local R0, R1 = 1.6, 1.95 -- царга сиденья
	local RY = (R0 + R1) / 2

	-- Волюта в произвольной плоскости: центр c, оси плоскости ex, ey, отступ «к зрителю» nrm
	local function spiral(parent, c, ex, ey, nrm, r0, r1, a0, turns, d0, d1, color, mat, lift)
		local n = math.max(6, math.ceil(math.abs(turns) * (if r0 > 0.14 then 12 else 10)))
		local pts = {}
		for i = 0, n do
			local t = i / n
			local a = a0 + turns * t * math.pi * 2
			local r = r0 * (r1 / r0) ^ t
			table.insert(pts, { c + ex * (math.cos(a) * r) + ey * (math.sin(a) * r) + nrm * ((lift or 0.04) * t), d0 + (d1 - d0) * t })
		end
		tube(parent, pts, color or C.goldHi, mat or M.foil)
	end
	-- Кривая-трубка через контрольные точки (Vector3), толщина d0→d1
	local function sweepW(parent, ctl, d0, d1, color, mat, step)
		local out = {}
		for _, it in resample(spline(ctl, 6), step or 0.12) do
			table.insert(out, { it[1], d0 + (d1 - d0) * it[2] })
		end
		tube(parent, out, color or C.goldHi, mat or M.foil)
		return out
	end

	-- «Запятая» аканта: цепочка шаров убывающего диаметра, загибающаяся к концу (curl ±1 — в сторону side)
	local LOBE_TURN = { 0.1, 0.3, 0.6, 0.9, 1.1 }
	local function lobe(parent, o, dir, side, len, d0, curl, color, mat)
		local n = #LOBE_TURN + 1
		local sum = 0
		for i = 1, n - 1 do
			sum += 1 - 0.5 * (i - 1) / (n - 2)
		end
		local step0 = len / sum
		local pos, phi = o, 0
		for i = 0, n - 1 do
			local t = i / (n - 1)
			ball(parent, pos, d0 * (1 - 0.55 * t), color or C.goldHi, mat or M.foil)
			if i < n - 1 then
				pos = pos + (dir * math.cos(phi) + side * math.sin(phi)) * (step0 * (1 - 0.5 * i / (n - 2)))
				phi += curl * LOBE_TURN[i + 1]
			end
		end
	end

	---------------------------------------------------------------- ножки-кабриоли с когтистыми лапами
	local legs = B:folder("Legs", throne)
	local function clawFoot(parent, ballC, out, side, ankle, s)
		ball(parent, ballC, 0.25 * s, C.goldHi, M.foil)
		for k = -1, 1 do
			local ang = k * rad(58)
			local dir = out * math.cos(ang) + side * math.sin(ang)
			local knuck = ballC + dir * (0.12 * s) + V(0, 0.1 * s, 0)
			local tip = ballC + dir * (0.135 * s) + V(0, -0.06 * s, 0)
			rod(parent, ankle, knuck, 0.08 * s, C.gold, M.gold)
			ball(parent, knuck, 0.085 * s, C.gold, M.gold)
			rod(parent, knuck, tip, 0.06 * s, C.gold, M.gold)
			ball(parent, tip, 0.055 * s, C.goldHi, M.foil)
		end
		rod(parent, ankle, ballC - out * (0.12 * s) + V(0, 0.02, 0), 0.07 * s, C.gold, M.gold) -- задний коготь
	end
	local function cabriole(top, out, s, plain)
		local side = out:Cross(Vector3.yAxis).Unit
		local h = top.Y - FLOOR_Y
		local function at(o, y)
			return top + out * (o * s) + V(0, y * h - h, 0)
		end
		-- профиль: {вынос наружу, доля высоты, толщина}: колено, тонкая лодыжка
		local prof = { { 0.0, 1.0, 0.34 }, { 0.14, 0.86, 0.36 }, { 0.21, 0.72, 0.29 }, { 0.14, 0.58, 0.2 }, { 0.05, 0.47, 0.145 }, { 0.02, 0.37, 0.13 } }
		local raw, ds = {}, {}
		for _, q in prof do
			table.insert(raw, at(q[1], q[2]))
			table.insert(ds, q[3] * s)
		end
		local smooth = spline(raw, 2)
		local pts = {}
		for i, p in smooth do
			local t = (i - 1) / (#smooth - 1) * (#raw - 1) + 1
			local a = math.floor(t)
			local b = math.min(#raw, a + 1)
			table.insert(pts, { p, ds[a] + (ds[b] - ds[a]) * (t - a) })
		end
		tube(legs, pts, C.gold, M.gold)
		local ballC = V(top.X, FLOOR_Y + 0.125 * s, top.Z) + out * (0.08 * s)
		if plain then
			-- задние ножки из кадра не видны: лапа без когтей
			ball(legs, ballC, 0.25 * s, C.goldHi, M.foil)
			rod(legs, at(0.02, 0.37), ballC, 0.11 * s, C.gold, M.gold)
			return
		end
		clawFoot(legs, ballC, out, side, at(0.03, 0.36), s)
		-- завиток-«колено» и лист аканта вниз по колену; манжета над лапой
		spiral(legs, at(0.31, 0.86), out, Vector3.yAxis, side * 0, 0.15 * s, 0.035 * s, math.pi * 0.5, 0.85, 0.11 * s, 0.06 * s, C.goldHi, M.foil, 0)
		ball(legs, at(0.31, 0.86), 0.1 * s, C.goldHi, M.foil)
		petal(legs, at(0.25, 0.78), at(0.21, 0.6), 0.09 * s, C.goldHi, M.foil)
		petal(legs, at(0.23, 0.8) + side * 0.07, at(0.18, 0.64) + side * 0.1, 0.06 * s, C.gold, M.gold)
		petal(legs, at(0.23, 0.8) - side * 0.07, at(0.18, 0.64) - side * 0.1, 0.06 * s, C.gold, M.gold)
		rod(legs, at(0.04, 0.43) - V(0, 0.02, 0), at(0.04, 0.43) + V(0, 0.04, 0), 0.19 * s, C.goldHi, M.foil)
	end
	local FRONT_LEG = V(ARM_X, R0 + 0.02, POST_Z)
	local BACK_LEG = V(1.8, R0 + 0.02, 0.76)
	for _, s in { 1, -1 } do
		cabriole(V(FRONT_LEG.X * s, FRONT_LEG.Y, FRONT_LEG.Z), V(0.72 * s, 0, -0.69).Unit, 1)
		cabriole(V(BACK_LEG.X * s, BACK_LEG.Y, BACK_LEG.Z), V(0.6 * s, 0, 0.8).Unit, 0.85, true)
	end

	---------------------------------------------------------------- царга сиденья
	local seat = B:folder("Seat", throne)
	local AZ = -1.29 -- ось передней царги
	local AF = AZ - 0.12 -- её лицо (на 0.01 позади лица передних стоек)
	box(seat, CFrame.new(0, RY, AZ), V(3.5, R1 - R0, 0.24), C.gold, M.gold)
	box(seat, CFrame.new(0, (R0 - 0.01 + 2.15) / 2, 0.84), V(3.44, 2.16 - R0, 0.3), C.goldDeep, M.gold)
	box(seat, CFrame.new(0, RY, AF - 0.008), V(2.86, 0.22, 0.016), C.goldDeep, M.gold) -- филёнка
	rod(seat, V(-1.7, R1, AF - 0.01), V(1.7, R1, AF - 0.01), 0.12, C.gold, M.gold)
	rod(seat, V(-1.7, R0 + 0.035, AF - 0.005), V(1.7, R0 + 0.035, AF - 0.005), 0.06, C.goldHi, M.foil)
	for _, s in { 1, -1 } do
		box(seat, CFrame.new(1.83 * s, RY, -0.24), V(0.24, R1 - R0 - 0.03, 2.0), C.gold, M.gold)
		rod(seat, V(1.955 * s, R1 - 0.02, -0.8), V(1.955 * s, R1 - 0.02, 0.74), 0.09, C.goldHi, M.foil)
		rod(seat, V(1.955 * s, R0 + 0.04, -0.8), V(1.955 * s, R0 + 0.04, 0.74), 0.06, C.goldHi, M.foil)
	end
	do
		-- фестон: волна по низу передней царги + раковина посередине
		local pts = {}
		for i = 0, 16 do
			local x = -1.62 + 3.24 * i / 16
			local u = math.abs(x) / 1.62
			table.insert(pts, V(x, R0 - 0.03 - 0.1 * math.sin(u * math.pi) - 0.14 * math.max(0, 1 - u * 3.5) ^ 2, AZ - 0.06))
		end
		local sm = {}
		for _, p in pts do
			table.insert(sm, { p, 0.08 })
		end
		tube(seat, sm, C.gold, M.gold)
		for k = -3, 3 do
			local a = rad(k * 22)
			local o = V(0, R0 - 0.04, AF + 0.01)
			petal(seat, o, o + V(math.sin(a) * 0.22, -math.cos(a) * 0.22, -0.01), 0.075, if k % 2 == 0 then C.goldHi else C.gold, if k % 2 == 0 then M.foil else M.gold)
		end
		ball(seat, V(0, R0, AF - 0.04), 0.12, C.goldHi, M.foil)
		cutGem(seat, CFrame.new(0, RY + 0.02, AF - 0.02), 0.12, C.ruby, C.rubyCore)
		-- S-завитки по лицу царги
		for _, s in { 1, -1 } do
			local zf = AF - 0.03
			sweepW(seat, { V(0.2 * s, RY - 0.02, zf), V(0.5 * s, RY + 0.08, zf), V(0.92 * s, RY - 0.05, zf), V(1.3 * s, RY + 0.04, zf) }, 0.075, 0.05, C.goldHi, M.foil, 0.1)
			spiral(seat, V(0.22 * s, RY + 0.03, zf), V(s, 0, 0), V(0, 1, 0), V(0, 0, -1), 0.06, 0.02, -math.pi * 0.5, -0.9 * s, 0.06, 0.04)
			spiral(seat, V(1.36 * s, RY - 0.01, zf), V(s, 0, 0), V(0, 1, 0), V(0, 0, -1), 0.065, 0.02, math.pi, -1.0 * s, 0.05, 0.035)
			ball(seat, V(1.52 * s, RY, zf), 0.1, C.goldHi, M.foil)
		end
	end

	---------------------------------------------------------------- подушка сиденья (капитоне)
	local cushion = B:folder("Cushion", throne)
	box(cushion, CFrame.new(0, 1.99, -0.32), V(3.22, 0.2, 1.98), C.velvetSeat, M.velvet)
	-- передний валик из пухлых секций (как у стёганой подушки)
	for i = 0, 3 do
		ell(cushion, CFrame.new(-1.17 + i * 0.78, 2.01, -1.22), V(0.9, 0.36, 0.44), C.velvetSeat, M.velvet)
	end
	for _, s in { 1, -1 } do
		for j = 0, 2 do
			ell(cushion, CFrame.new(1.5 * s, 2.01, -0.88 + j * 0.56), V(0.4, 0.34, 0.66), C.velvetSeat, M.velvet)
		end
	end
	for i = 0, 3 do
		for j = 0, 2 do
			ell(cushion, CFrame.new(-1.17 + i * 0.78, 2.05, -0.9 + j * 0.56), V(0.86, 0.3, 0.64), C.velvetSeat, M.velvet)
		end
	end
	for i = 0, 2 do
		for j = 0, 1 do
			ball(cushion, V(-0.78 + i * 0.78, 2.15, -0.62 + j * 0.56), 0.085, C.velvetDark, M.velvet)
		end
	end
	-- шнур по кромке и кисти на передних углах
	for _, s in { 1, -1 } do
		local a = V(1.5 * s, 1.92, -1.42)
		local b = V(1.53 * s, 1.68, -1.47)
		rod(cushion, a, b, 0.035, C.goldHi, M.foil)
		ball(cushion, b, 0.1, C.goldHi, M.foil)
		rod(cushion, b - V(0, 0.04, 0), b - V(0, 0.24, 0), 0.11, C.gold, M.foil)
		ball(cushion, b - V(0, 0.25, 0), 0.08, C.goldHi, M.foil)
	end

	---------------------------------------------------------------- подлокотники
	local arms = B:folder("Arms", throne)
	local REAR_Z = 0.74 -- задняя стойка подлокотника
	local function armSide(s)
		local x = ARM_X * s
		local zf = POST_Z
		local fz = zf - 0.3 -- лицо нижнего блока
		local ox = x + 0.24 * s -- наружная грань
		local front, up, outN = V(0, 0, -1), V(0, 1, 0), V(s, 0, 0)
		-- нижний резной блок
		box(arms, CFrame.new(x, (R0 - 0.02 + 2.62) / 2, zf), V(0.48, 2.64 - R0, 0.6), C.gold, M.gold)
		box(arms, CFrame.new(x, 2.1, fz - 0.006), V(0.34, 0.82, 0.016), C.goldDeep, M.gold)
		for _, cx in { -0.235, 0.235 } do
			rod(arms, V(x + cx, R0 + 0.02, fz + 0.01), V(x + cx, 2.6, fz + 0.01), 0.07, C.goldHi, M.foil)
		end
		-- лира из двух C-завитков навстречу, кабошон в центре, листья-запятые сверху
		local pz = fz - 0.03
		for _, sx in { -1, 1 } do
			sweepW(arms, { V(x + sx * 0.03, 1.74, pz), V(x + sx * 0.15, 1.86, pz), V(x + sx * 0.165, 2.1, pz), V(x + sx * 0.12, 2.3, pz) }, 0.08, 0.06, C.goldHi, M.foil, 0.09)
			spiral(arms, V(x + sx * 0.068, 2.3, pz), V(sx, 0, 0), up, front, 0.065, 0.018, 0, 1.0, 0.06, 0.035)
			ball(arms, V(x + sx * 0.04, 1.74, pz - 0.01), 0.1, C.goldHi, M.foil)
			lobe(arms, V(x + sx * 0.02, 2.44, pz), V(sx * 0.5, 0.87, 0), V(sx * 0.87, -0.5, 0), 0.17, 0.085, 1)
		end
		ball(arms, V(x, 2.44, pz), 0.09, C.goldHi, M.foil)
		gem(arms, V(x, 2.04, fz - 0.06), 0.13, C.ruby, C.rubyCore)
		-- наружная грань: большой S-завиток
		sweepW(arms, { V(ox + 0.02 * s, 2.5, zf - 0.18), V(ox + 0.03 * s, 2.25, zf - 0.02), V(ox + 0.03 * s, 1.98, zf + 0.05), V(ox + 0.02 * s, 1.75, zf + 0.16) }, 0.1, 0.07, C.goldHi, M.foil, 0.1)
		spiral(arms, V(ox + 0.02 * s, 2.47, zf - 0.08), V(0, 0, -1), up, outN, 0.1, 0.025, -math.pi * 0.5, 0.9, 0.08, 0.04)
		spiral(arms, V(ox + 0.02 * s, 1.78, zf + 0.06), V(0, 0, -1), up, outN, 0.09, 0.02, math.pi * 0.5, 0.9, 0.07, 0.035)
		-- шейка-манжета
		box(arms, CFrame.new(x, 2.665, zf), V(0.56, 0.1, 0.68), C.goldHi, M.foil)
		beads(arms, { V(x - 0.21, 2.67, zf - 0.345), V(x + 0.21, 2.67, zf - 0.345) }, 0.065, 0.105, C.gold, M.gold)
		-- шапка-свиток: блок + валик вдоль Z (спереди — полукруглый верх) + спираль на торце
		local TOP = 3.43
		local RR = 0.26
		box(arms, CFrame.new(x, (2.7 + TOP - RR + 0.02) / 2, zf), V(0.49, TOP - RR + 0.02 - 2.7, 0.62), C.gold, M.gold)
		part({ parent = arms, cf = CFrame.new(x, TOP - RR, zf) * CFrame.Angles(0, math.pi / 2, 0), size = V(0.66, RR * 2, RR * 2), shape = "Cylinder", color = C.gold, material = M.gold })
		local capZ = zf - 0.33
		spiral(arms, V(x, TOP - RR, capZ - 0.01), V(-s, 0, 0), up, front, 0.2, 0.04, math.pi * 0.5, 1.45, 0.075, 0.05, C.goldHi, M.foil, 0.03)
		ball(arms, V(x, TOP - RR, capZ - 0.03), 0.1, C.goldHi, M.foil)
		-- торец сзади — простая розетка
		ball(arms, V(x, TOP - RR, zf + 0.33), 0.16, C.goldHi, M.foil)
		-- борозды на лице под валиком и заклёпка-шишечка сверху
		for _, dx in { -0.16, 0, 0.16 } do
			rod(arms, V(x + dx, 2.75, zf - 0.312), V(x + dx, 2.92, zf - 0.312), 0.045, C.goldHi, M.foil)
		end
		ball(arms, V(x, TOP + 0.02, zf - 0.12), 0.11, C.goldHi, M.foil)
		-- лист на наружном боку шапки
		local lo = V(ox + 0.01 * s, 2.82, zf + 0.12)
		petal(arms, lo, lo + V(0, 0.32, -0.16), 0.08, C.goldHi, M.foil)
		petal(arms, lo, lo + V(0, 0.18, -0.3), 0.06, C.gold, M.gold)
		-- брус подлокотника + бархатная подушка
		local z0, z1 = zf + 0.3, REAR_Z
		local zm, L = (z0 + z1) / 2, z1 - z0
		box(arms, CFrame.new(x, 3.08, zm - 0.02), V(0.36, 0.2, L + 0.04), C.gold, M.gold)
		rod(arms, V(x + s * 0.18, 2.99, z0 - 0.01), V(x + s * 0.18, 2.99, z1 + 0.01), 0.08, C.goldHi, M.foil)
		rod(arms, V(x - s * 0.18, 2.99, z0 - 0.01), V(x - s * 0.18, 2.99, z1 + 0.01), 0.08, C.goldHi, M.foil)
		ell(arms, CFrame.new(x, 3.22, zm + 0.02), V(0.4, 0.32, L - 0.04), C.velvet, M.velvet)
		-- задняя стойка (из задней ножки) и бархатная боковина с медальоном
		rod(arms, V(x, R0 + 0.04, REAR_Z), V(x, 3.12, REAR_Z), 0.2, C.gold, M.gold)
		ball(arms, V(x, 3.2, REAR_Z), 0.24, C.goldHi, M.foil)
		box(arms, CFrame.new(x - 0.06 * s, (1.9 + 3.0) / 2, zm - 0.005), V(0.12, 1.1, L - 0.01), C.velvet, M.velvet)
		local mc = V(x + 0.02 * s, 2.5, zm)
		local ring = {}
		for i = 0, 24 do
			local a = i / 24 * math.pi * 2
			table.insert(ring, mc + V(0, math.sin(a) * 0.24, math.cos(a) * 0.17))
		end
		beads(arms, ring, 0.065, 0.085, C.goldHi, M.foil)
		gem(arms, mc + V(0.02 * s, 0, 0), 0.13, C.sapphire, C.sapphireCore)
	end
	armSide(1)
	armSide(-1)

	---------------------------------------------------------------- спинка
	local back = B:folder("Back", throne)
	local TILT = 5 -- спинка чуть откинута назад: лучше ловит верхний свет
	local BACK = CFrame.new(0, SEAT_Y, 0.7) * CFrame.Angles(rad(TILT), 0, 0)
	local function bp(x, v, w)
		return BACK:PointToWorldSpace(V(x, v, w))
	end
	local BX = BACK:VectorToWorldSpace(V(1, 0, 0))
	local BV = BACK:VectorToWorldSpace(V(0, 1, 0))
	local BF = BACK:VectorToWorldSpace(V(0, 0, -1)) -- к зрителю

	-- Силуэт «баллон»: лёгкая талия у сиденья, широкие плечи, эллиптический купол сверху.
	local TOPC, TOPA, TOPB = 5.35, 1.78, 0.88 -- центр купола (высота), полуоси
	local sideCtl = { V(1.52, -0.1, 0), V(1.47, 0.8, 0), V(1.44, 1.6, 0), V(1.48, 2.4, 0), V(1.57, 3.2, 0), V(1.68, 4.0, 0), V(1.76, 4.8, 0), V(1.78, TOPC, 0) }
	local outlineR = {}
	for _, p in spline(sideCtl, 4) do
		table.insert(outlineR, p)
	end
	for i = 1, 16 do
		local th = i / 16 * math.pi / 2
		table.insert(outlineR, V(TOPA * math.cos(th), TOPC + TOPB * math.sin(th), 0))
	end
	local TOPV = TOPC + TOPB
	local function halfWidth(v)
		if v <= outlineR[1].Y then
			return outlineR[1].X
		end
		for i = 2, #outlineR do
			local a, b = outlineR[i - 1], outlineR[i]
			if v <= b.Y then
				return a.X + (b.X - a.X) * (v - a.Y) / math.max(1e-6, b.Y - a.Y)
			end
		end
		return 0
	end
	local function domeV(x) -- верх контура над точкой x
		local u = math.clamp(math.abs(x) / TOPA, 0, 1)
		return TOPC + TOPB * math.sqrt(1 - u * u)
	end
	local outline = {}
	for i = 1, #outlineR do
		table.insert(outline, outlineR[i])
	end
	for i = #outlineR - 1, 1, -1 do
		table.insert(outline, V(-outlineR[i].X, outlineR[i].Y, 0))
	end
	local function outNormal(i, pts)
		local a = pts[math.max(1, i - 1)]
		local b = pts[math.min(#pts, i + 1)]
		local t = (b - a).Unit
		return V(t.Y, -t.X, 0)
	end
	local function nAt(sv)
		return outNormal(math.clamp(math.floor(sv * (#outline - 1) + 0.5) + 1, 1, #outline), outline)
	end

	-- панель: горизонтальные полосы по контуру
	local PANEL_D = 0.46
	do
		local v = -0.1
		local k = 0
		while v < TOPV do
			local step = if v < TOPC - 0.3 then 0.5 elseif v < TOPC + 0.5 then 0.14 else 0.07
			local v1 = math.min(TOPV, v + step)
			local w = math.min(halfWidth(v), halfWidth(v1))
			if w > 0.05 then
				k += 1
				local dd = PANEL_D - 0.02 - (k % 2) * 0.024 -- соседние полосы разной толщины: грани не совпадают
				box(back, BACK * CFrame.new(0, (v + v1) / 2, PANEL_D / 2 + 0.01), V(w * 2 - (k % 2) * 0.02, v1 - v + 0.002, dd), C.velvet, M.velvet)
			end
			v = v1
		end
	end
	-- набивка: стопка сильно перекрытых эллипсоидов, ширина каждого — по контуру; выпуклость
	-- сильнее вверху (как у пухлой спинки в клипе), края уходят под раму
	do
		local function fits(vc, w, H)
			for k = -12, 12 do
				local t = k / 12
				local y = vc + t * H / 2
				local lim = if y > TOPV - 0.01 or y < -0.35 then -1 else halfWidth(y) + 0.06
				if w * math.sqrt(math.max(0, 1 - t * t)) > lim then
					return false
				end
			end
			return true
		end
		local v = 0.2
		while v <= TOPC - 0.2 do
			local w = halfWidth(v) - 0.03
			local H = 0.2
			while H < 4.2 and fits(v, w, H + 0.05) do
				H += 0.05
			end
			local bulge = 0.12 + 0.08 * math.clamp(v / 5, 0, 1)
			ell(back, BACK * CFrame.new(0, v, 0), V(w * 2, H, bulge * 2), C.velvet, M.velvet)
			v += 0.12
		end
		-- купол — один большой эллипсоид точно по контуру (без ряби от коротких эллипсоидов)
		ell(back, BACK * CFrame.new(0, TOPC, 0), V((TOPA - 0.02) * 2, (TOPB - 0.015) * 2, 0.43), C.velvet, M.velvet)
	end

	-- рама: тонкий резной багет (валик + наружный кант + торец + задний валик) и гвоздики обивки
	do
		local front, outer = {}, {}
		for _, it in resample(outline, 0.25) do
			local p, nrm = it[1], nAt(it[2])
			table.insert(front, { bp(p.X + nrm.X * 0.05, p.Y + nrm.Y * 0.05, -0.07), 0.22 })
		end
		for _, it in resample(outline, 0.48) do
			local p, nrm = it[1], nAt(it[2])
			table.insert(outer, { bp(p.X + nrm.X * 0.2, p.Y + nrm.Y * 0.2, 0.0), 0.1 })
		end
		tube(back, front, C.gold, M.gold)
		tube(back, outer, C.goldHi, M.foil)
		local edge = resample(outline, 0.6)
		for i = 1, #edge - 1 do
			local a, b = edge[i][1], edge[i + 1][1]
			local na, nb = nAt(edge[i][2]), nAt(edge[i + 1][2])
			local pa, pb = a + na * 0.12, b + nb * 0.12
			local cf, len = along(bp(pa.X, pa.Y, PANEL_D / 2 + 0.02), bp(pb.X, pb.Y, PANEL_D / 2 + 0.02))
			box(back, cf, V(len + 0.06, 0.18 + (i % 2) * 0.012, PANEL_D + 0.06 + (i % 2) * 0.012), C.goldDeep, M.gold)
		end
		local backT = {}
		for _, it in resample(outline, 0.8) do
			local p = it[1]
			table.insert(backT, { bp(p.X, p.Y, PANEL_D + 0.04), 0.16 })
		end
		tube(back, backT, C.gold, M.gold)
		-- гвоздики обивки вдоль рамы (редкие, мелкие)
		local inner = {}
		for i, p in outline do
			local nrm = outNormal(i, outline)
			table.insert(inner, bp(p.X - nrm.X * 0.17, p.Y - nrm.Y * 0.17, -0.07))
		end
		beads(back, inner, 0.065, 0.34, C.goldHi, M.foil)
		-- тыльная сторона: стёжка ромбом — золотые гвоздики в шахматном порядке
		for row = 0, 5 do
			local v = 0.9 + row * 0.8
			local hw = halfWidth(v) - 0.45
			local off = if row % 2 == 0 then 0 else 0.35
			local x = -math.floor((hw + off) / 0.7) * 0.7 + off
			while x <= hw + 1e-3 do
				ball(back, bp(x, v, PANEL_D + 0.012), 0.08, C.goldHi, M.foil)
				x += 0.7
			end
		end
	end

	-- Точки и орнамент в плоскости спинки (x, v, w): w<0 — к зрителю
	local function sweepB(parent, ctl, d0, d1, color, mat, step)
		local pv = {}
		for _, q in ctl do
			table.insert(pv, bp(q[1], q[2], q[3] or -0.08))
		end
		return sweepW(parent, pv, d0, d1, color, mat, step)
	end
	local function voluteB(parent, cx, cv, w, r0, r1, a0, turns, d0, d1, color, mat)
		spiral(parent, bp(cx, cv, w), BX, BV, BF, r0, r1, a0, turns, d0, d1, color, mat, 0.05)
	end
	local function rosette(parent, cx, cv, w, r, petals, jewel)
		for k = 0, petals - 1 do
			local a = k / petals * math.pi * 2
			ball(parent, bp(cx + math.cos(a) * r * 0.62, cv + math.sin(a) * r * 0.62, w), r * 0.62, C.gold, M.gold)
		end
		if jewel then
			ball(parent, bp(cx, cv, w - 0.02), r * 0.85, C.goldHi, M.foil)
			gem(parent, bp(cx, cv, w - r * 0.3), r * 0.6, jewel[1], jewel[2])
		else
			ball(parent, bp(cx, cv, w - r * 0.12), r * 0.8, C.goldHi, M.foil)
		end
	end
	-- лист аканта: веер капсул (ang — от вертикали, против часовой; single — одна капсула)
	local function leaf(parent, cx, cv, w, ang, len, single)
		local o = bp(cx, cv, w)
		for k = -1, 1 do
			if not single or k == 0 then
				local a = rad(ang + k * 30)
				local L = len * (if k == 0 then 0.85 else 0.62)
				local tip = bp(cx - math.sin(a) * L, cv + math.cos(a) * L, w - 0.02)
				petal(parent, o, tip, len * (if k == 0 then 0.3 else 0.24), if k == 0 then C.goldHi else C.gold, if k == 0 then M.foil else M.gold)
			end
		end
		if not single then
			ball(parent, o, len * 0.38, C.goldHi, M.foil)
		end
	end

	-- то же в плоскости спинки: ang — от вертикали (0 — вверх, >0 — влево), curl>0 — по часовой
	local function lobeB(parent, cx, cv, w, ang, len, d0, curl, color, mat)
		local a = rad(ang)
		local dir = BX * -math.sin(a) + BV * math.cos(a)
		local side = BX * math.cos(a) + BV * math.sin(a)
		lobe(parent, bp(cx, cv, w), dir, side, len, d0, curl, color, mat)
	end

	-- «Уши» на высоте плеч: C-завиток наружу вокруг розетки, листья-запятые; внизу — завиток к стойке подлокотника
	local orn = B:folder("Ornament", back)
	for _, s in { 1, -1 } do
		local v0 = 2.9
		local ex = halfWidth(v0) + 0.16
		sweepB(orn, { { ex * s, v0 - 0.5 }, { (ex + 0.3) * s, v0 - 0.3 }, { (ex + 0.5) * s, v0 + 0.06 }, { (ex + 0.4) * s, v0 + 0.42 }, { (ex + 0.12) * s, v0 + 0.56 } }, 0.26, 0.14, C.gold, M.gold, 0.13)
		voluteB(orn, (ex + 0.14) * s, v0 + 0.38, -0.1, 0.13, 0.03, -math.pi * 0.5 + (if s > 0 then 0 else math.pi), 1.1 * s, 0.12, 0.05)
		rosette(orn, (ex + 0.28) * s, v0 + 0.04, -0.15, 0.18, 7)
		lobeB(orn, (ex + 0.36) * s, v0 - 0.36, -0.14, 180 + 40 * s, 0.4, 0.14, -s)
		lobeB(orn, (ex + 0.44) * s, v0 + 0.32, -0.12, -55 * s, 0.34, 0.12, s)
		lobeB(orn, (ex + 0.05) * s, v0 - 0.52, -0.12, 180 - 10 * s, 0.32, 0.12, s)
		-- нижний завиток: от рамы к задней стойке подлокотника
		local lx = halfWidth(1.3) + 0.14
		sweepB(orn, { { lx * s, 1.75 }, { (lx + 0.18) * s, 1.45 }, { (lx + 0.26) * s, 1.15 } }, 0.18, 0.13, C.goldHi, M.foil, 0.12)
		voluteB(orn, (lx + 0.16) * s, 1.12, -0.08, 0.11, 0.025, (if s > 0 then 0 else math.pi), -1.1 * s, 0.12, 0.05)
	end

	---------------------------------------------------------------- гребень
	local crest = B:folder("Crest", back)
	local CW = -0.12
	-- главный C-завиток (правая половина, в плоскости спинки): от картуша вверх-наружу и вниз по плечу купола
	local MAIN = { { 0.36, 6.42 }, { 0.55, 6.88 }, { 1.0, 7.02 }, { 1.45, 6.84 }, { 1.82, 6.44 }, { 2.02, 5.95 }, { 2.04, 5.4 }, { 1.98, 4.95 } }
	local mainPts = {}
	do
		local ctl = {}
		for _, q in MAIN do
			table.insert(ctl, V(q[1], q[2], 0))
		end
		mainPts = spline(ctl, 8)
	end
	-- верхний край задника: чуть ниже главного завитка (ступеньки полос прячутся под ним)
	local function upV(x)
		local ax = math.abs(x)
		if ax < 0.55 then
			return 7.0
		end
		for i = 2, #mainPts do
			local a, b = mainPts[i - 1], mainPts[i]
			if a.X <= ax and ax <= b.X and b.X > a.X then
				return a.Y + (b.Y - a.Y) * (ax - a.X) / (b.X - a.X) - 0.07
			end
		end
		return 0
	end
	do
		-- задник гребня (тёмное золото): вертикальные полосы между куполом и верхним краем
		local NX = 30
		local dx = 4.0 / NX
		for i = 0, NX - 1 do
			local x = -2.0 + (i + 0.5) * dx
			local lo = if math.abs(x) > TOPA - 0.02 then 5.5 else domeV(x) - 0.123
			local hi = upV(x) + (i % 2) * 0.012
			lo -= (i % 2) * 0.012
			if hi > lo + 0.1 then
				box(crest, BACK * CFrame.new(x, (lo + hi) / 2, 0.14), V(dx + 0.004, hi - lo, 0.14 + (i % 2) * 0.03), C.goldDeep, M.gold)
			end
		end
		-- основание — массивный валик по куполу
		local base = {}
		for i = 0, 22 do
			local th = rad(14 + 152 * i / 22)
			table.insert(base, { bp((TOPA + 0.1) * math.cos(th), TOPC + (TOPB + 0.1) * math.sin(th), CW + 0.02), 0.28 })
		end
		tube(crest, base, C.gold, M.gold)
	end
	for _, s in { 1, -1 } do
		local function X(x)
			return x * s
		end
		local ctl = {}
		for _, q in MAIN do
			table.insert(ctl, { X(q[1]), q[2], CW })
		end
		sweepB(crest, ctl, 0.32, 0.17, C.goldHi, M.foil, 0.17)
		-- волюты на концах главного завитка (с шишкой в центре)
		voluteB(crest, X(2.14), 4.92, CW - 0.04, 0.2, 0.04, (if s > 0 then math.pi else 0), 1.25 * s, 0.17, 0.07)
		ball(crest, bp(X(2.14), 4.92, CW - 0.1), 0.12, C.goldHi, M.foil)
		voluteB(crest, X(0.47), 6.3, CW - 0.06, 0.15, 0.035, (if s > 0 then 0.2 else math.pi - 0.2), -1.1 * s, 0.15, 0.06)
		-- внутренний S-завиток вдоль основания между розетками
		sweepB(crest, { { X(0.62), 6.12, CW - 0.02 }, { X(0.9), 6.24, CW - 0.02 }, { X(1.15), 6.12, CW - 0.02 }, { X(1.42), 5.92, CW - 0.02 } }, 0.16, 0.11, C.goldHi, M.foil, 0.12)
		voluteB(crest, X(1.5), 6.04, CW - 0.06, 0.12, 0.03, -math.pi * 0.5, -1.1 * s, 0.11, 0.05)
		-- малый завиток к короне
		sweepB(crest, { { X(0.5), 6.86, CW }, { X(0.6), 7.12, CW }, { X(0.82), 7.28, CW } }, 0.16, 0.11, C.goldHi, M.foil, 0.12)
		voluteB(crest, X(0.9), 7.18, CW - 0.04, 0.12, 0.03, (if s > 0 then 0.6 else math.pi - 0.6), 1.1 * s, 0.11, 0.05)
		-- розетки в ряд
		rosette(crest, X(0.86), 6.56, CW - 0.12, 0.21, 8, { C.emerald, C.emeraldCore })
		rosette(crest, X(1.44), 6.38, CW - 0.08, 0.15, 6)
		-- листья-запятые по внешней кромке главного завитка (закручиваются наружу-вниз)
		for _, q in { { 2.13, 5.95, -100, 0.3 }, { 2.15, 5.42, -118, 0.26 } } do
			lobeB(crest, X(q[1]), q[2], CW - 0.04, q[3] * s, q[4], 0.17, s)
		end
		lobeB(crest, X(0.66), 7.02, CW - 0.04, 25 * s, 0.24, 0.15, -s)
		-- круглые волюты на верхней кромке (силуэт гребня — из «катушек», как в клипе)
		voluteB(crest, X(1.08), 7.16, CW - 0.08, 0.2, 0.045, (if s > 0 then math.pi * 0.85 else math.pi * 0.15), -1.15 * s, 0.17, 0.08)
		ball(crest, bp(X(1.08), 7.16, CW - 0.12), 0.13, C.goldHi, M.foil)
		voluteB(crest, X(1.74), 6.7, CW - 0.08, 0.16, 0.04, (if s > 0 then math.pi * 0.75 else math.pi * 0.25), -1.15 * s, 0.15, 0.07)
		ball(crest, bp(X(1.74), 6.7, CW - 0.12), 0.11, C.goldHi, M.foil)
		ball(crest, bp(X(1.3), 6.02, CW - 0.1), 0.09, C.goldHi, M.foil)
	end
	-- раковина-веер позади короны
	for k = -3, 3 do
		local a = rad(k * 22)
		petal(crest, bp(0, 7.0, 0.16), bp(-math.sin(a) * 0.62, 7.0 + math.cos(a) * 0.62, 0.16), 0.13, if k % 2 == 0 then C.goldHi else C.gold, M.foil)
	end
	-- картуш: овальный медальон с большим рубином, под ним лист
	do
		local cx, cv = 0, 6.5
		local ring = {}
		for i = 0, 32 do
			local a = i / 32 * math.pi * 2
			table.insert(ring, bp(cx + math.cos(a) * 0.33, cv + math.sin(a) * 0.42, CW - 0.16))
		end
		beads(crest, ring, 0.1, 0.095, C.goldHi, M.foil)
		part({ parent = crest, cf = BACK * CFrame.new(cx, cv, CW - 0.06) * CFrame.Angles(0, math.pi / 2, 0), size = V(0.14, 0.72, 0.72), shape = "Cylinder", color = C.gold, material = M.gold })
		cutGem(crest, BACK * CFrame.new(cx, cv, CW - 0.14), 0.24, C.ruby, C.rubyCore)
		leaf(crest, 0, 6.0, CW - 0.14, 180, 0.4)
		ball(crest, bp(0, 6.04, CW - 0.18), 0.13, C.goldHi, M.foil)
	end

	---------------------------------------------------------------- корона
	local crown = B:folder("Crown", throne)
	do
		local base = bp(0, 7.08, 0.06)
		local cy, cz = base.Y, base.Z
		local R = 0.54
		local function cp(a, r, y)
			return V(math.sin(a) * r, y, cz - math.cos(a) * r) -- a=0 — к зрителю (−Z)
		end
		local function vdisc(name, y0, y1, r, color, mat)
			part({ parent = crown, name = name, cf = CFrame.new(0, (y0 + y1) / 2, cz) * CFrame.Angles(0, 0, math.pi / 2), size = V(y1 - y0, r * 2, r * 2), shape = "Cylinder", color = color, material = mat })
		end
		vdisc("CrownPlinth", cy - 0.14, cy + 0.02, R * 0.8, C.gold, M.gold)
		vdisc("CrownRim", cy + 0.0, cy + 0.07, R + 0.05, C.gold, M.gold)
		vdisc("CrownBand", cy + 0.05, cy + 0.32, R, C.goldHi, M.foil)
		vdisc("CrownRim2", cy + 0.3, cy + 0.36, R + 0.04, C.gold, M.gold)
		ell(crown, CFrame.new(0, cy + 0.34, cz), V(R * 1.86, 0.62, R * 1.86), C.velvet, M.velvet)
		local gems = { { C.ruby, C.rubyCore }, { C.emerald, C.emeraldCore }, { C.sapphire, C.sapphireCore }, { C.emerald, C.emeraldCore } }
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local g = gems[k % 4 + 1]
			gem(crown, cp(a, R, cy + 0.185), 0.14, g[1], g[2])
			ball(crown, cp(a + math.pi / 8, R + 0.01, cy + 0.185), 0.065, C.pearl, "SmoothPlastic")
		end
		-- зубцы: кресты и лилии по кругу
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local p = cp(a, R - 0.03, cy + 0.46)
			local cf = CFrame.new(p) * CFrame.Angles(0, -a, 0)
			if k % 2 == 0 then
				box(crown, cf * CFrame.new(0, 0.02, 0), V(0.085, 0.27, 0.05), C.goldHi, M.foil)
				box(crown, cf * CFrame.new(0, 0.06, 0), V(0.22, 0.075, 0.075), C.goldHi, M.foil)
				ball(crown, (cf * CFrame.new(0, 0.06, -0.02)).Position, 0.065, C.ruby, M.glass, { transparency = 0.1 })
				ball(crown, p + V(0, 0.19, 0), 0.065, C.pearl, "SmoothPlastic")
			else
				local o = (cf * CFrame.new(0, -0.1, 0)).Position
				petal(crown, o, (cf * CFrame.new(0, 0.12, 0)).Position, 0.07, C.goldHi, M.foil)
				petal(crown, o, (cf * CFrame.new(0.1, 0.035, 0)).Position, 0.05, C.goldHi, M.foil)
				petal(crown, o, (cf * CFrame.new(-0.1, 0.035, 0)).Position, 0.05, C.goldHi, M.foil)
				ball(crown, p + V(0, 0.17, 0), 0.065, C.pearl, "SmoothPlastic")
			end
		end
		-- две дуги крест-накрест (бусины)
		for _, rot in { math.pi / 4, -math.pi / 4 } do
			local arc = {}
			for i = 0, 20 do
				local t = i / 20 * math.pi
				local xx = math.cos(t) * (R - 0.05)
				table.insert(arc, V(xx * math.cos(rot), cy + 0.34 + math.sin(t) * 0.38, cz + xx * math.sin(rot)))
			end
			beads(crown, arc, 0.085, 0.078, C.goldHi, M.foil, if rot < 0 then { V(0, cy + 0.72, cz) } else nil)
		end
		-- держава с крестом
		ball(crown, V(0, cy + 0.82, cz), 0.21, C.goldHi, M.foil)
		rod(crown, V(-0.115, cy + 0.82, cz), V(0.115, cy + 0.82, cz), 0.035, C.gold, M.gold)
		box(crown, CFrame.new(0, cy + 1.02, cz), V(0.055, 0.23, 0.055), C.goldHi, M.foil)
		box(crown, CFrame.new(0, cy + 1.05, cz), V(0.165, 0.055, 0.08), C.goldHi, M.foil)
		gem(crown, V(0, cy + 1.05, cz - 0.03), 0.06, C.ruby, C.rubyCore)
		root:SetAttribute("CrownTopY", math.floor((cy + 1.0775) * 100 + 0.5) / 100)
	end

	-- ===================================================================
	-- СВЕТ
	-- ===================================================================
	local lights = B:folder("Lights")
	local LAMP = V(0, 30, -4)
	local TARGET = V(0, 3.6, 0.35)
	local lampCf = aim(LAMP, TARGET)
	local lamp = part({ parent = lights, name = "SpotLamp", cf = lampCf, size = V(1.6, 1.6, 1.2), color = C.void, castShadow = false, canQuery = false })
	lamp.Transparency = 1
	part({ parent = lights, name = "LampHousing", cf = lampCf * CFrame.new(0, 0, 0.9) * CFrame.Angles(0, math.pi / 2, 0), size = V(1.8, 1.5, 1.5), shape = "Cylinder", color = rgb(10, 10, 12), material = "Metal", castShadow = false })
	part({ parent = lights, name = "LampLens", cf = lampCf * CFrame.new(0, 0, 0.02) * CFrame.Angles(0, math.pi / 2, 0), size = V(0.06, 1.3, 1.3), shape = "Cylinder", color = C.light, material = M.neon, castShadow = false })
	-- Range 42 (а не максимум): свет затухает к полу — корона и спинка ярче ножек и подиума, как в клипе
	B:light(lamp, "SpotLight", { Name = "KeyLight", Brightness = 12, Range = 42, Angle = 20, Face = "Front", Shadows = true, Color = C.light })
	B:light(lamp, "SpotLight", { Name = "KeySoft", Brightness = 2, Range = 42, Angle = 32, Face = "Front", Shadows = false, Color = C.light })

	local function spot(name, pos, target, kind, props)
		local p = part({ parent = lights, name = name, cf = aim(pos, target), size = V(0.4, 0.4, 0.4), color = C.void, castShadow = false, canQuery = false })
		p.Transparency = 1
		local l = B:light(p, kind, props)
		l.Name = name .. "Light"
		return p
	end
	spot("FillFront", V(0, 5, -11), V(0, 3.5, 0), "SpotLight", { Brightness = 0.4, Range = 24, Angle = 46, Face = "Front", Shadows = false, Color = rgb(255, 228, 196) })
	spot("RimBack", V(0, 17, 7.5), V(0, 7.5, 0.8), "SpotLight", { Brightness = 1.2, Range = 22, Angle = 38, Face = "Front", Shadows = false, Color = rgb(255, 220, 170) })

	-- ===================================================================
	-- ОБЪЁМНЫЙ ЛУЧ: ленты Beam лицом к камере (мягкий край — сумма лент разной ширины).
	-- Задний слой: ось от лампы к полу далеко за троном — весь позади трона/коня (основной конус).
	-- Передний слой: ось к полу перед подиумом — лёгкая дымка поверх сцены. Ни один слой не режет трон.
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
	local function beam(name, a0, a1, w0, w1, alphaTop, color)
		local bm = Instance.new("Beam")
		bm.Name = name
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.Width0 = w0
		bm.Width1 = w1
		bm.FaceCamera = true
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Segments = 24
		bm.Color = ColorSequence.new(color)
		-- почти линейный спад к полу (превью интерполирует только крайние точки — так они совпадают)
		bm.Transparency = ns({ { 0, 1 - alphaTop }, { 0.5, 1 - alphaTop * 0.5 }, { 0.8, 1 - alphaTop * 0.16 }, { 1, 1 } })
		bm.Parent = a0.Parent
		return bm
	end
	local TOP_P = LAMP + (TARGET - LAMP).Unit * 0.9
	local BACK_P = V(0, 0.02, 6.6)
	local FRONT_P = V(0, 0.02, -4.65)
	local top = anchor("ShaftTop", TOP_P)
	local backEnd = anchor("ShaftBackEnd", BACK_P)
	local frontEnd = anchor("ShaftFrontEnd", FRONT_P)
	local coneTan = math.tan(rad(8.5))
	local Lb = (BACK_P - TOP_P).Magnitude
	local Lf = (FRONT_P - TOP_P).Magnitude
	-- Ленты стоят не на оси конуса: из камеры плана S11 (≈9 студов перед троном, облёт ±30°) задняя
	-- кажется меньше, передняя — больше. Поправка ширины, чтобы обе проецировались на силуэт конуса.
	local CAM_Z = -9
	local axisZ0 = LAMP.Z + (TARGET.Z - LAMP.Z) * (LAMP.Y / (LAMP.Y - TARGET.Y)) -- ось конуса на высоте пола
	local kBack = (BACK_P.Z - CAM_Z) / (axisZ0 - CAM_Z)
	local kFront = (FRONT_P.Z - CAM_Z) / (axisZ0 - CAM_Z)
	local Lc = (V(0, 0, axisZ0) - TOP_P).Magnitude
	local warm = rgb(242, 236, 228) -- дымка в клипе почти нейтрально-серая
	-- Профиль яркости поперёк конуса P(r) (r — доля радиуса): плотная середина, мягкое плечо к краю.
	-- Ленты шириной f_i, непрозрачность каждой = P(f_{i−1}) − P(f_i): сумма лент даёт P без ступенек.
	local function profile(r)
		local e = math.clamp((r - 0.55) / (1.12 - 0.55), 0, 1)
		return (1 - e * e * (3 - 2 * e)) * (0.8 + 0.2 * (1 - math.min(1, r * r)))
	end
	local N = 24
	local prev = profile(0)
	for i = 1, N do
		local f = 0.1 + (1.12 - 0.1) * (i - 1) / (N - 1)
		local p = profile(f)
		local a = prev - p
		prev = p
		beam(string.format("LightShaftBack%02d", i), top, backEnd, 0.35 + f * 0.5, 2 * Lc * coneTan * f * kBack, math.min(1, a * 0.68), warm)
		if f > 0.3 then
			beam(string.format("LightShaftFront%02d", i), top, frontEnd, 0.35 + f * 0.5, 2 * Lc * coneTan * f * kFront, math.min(1, a * 0.2), warm)
		end
	end

	-- ===================================================================
	-- ЧАСТИЦЫ
	-- ===================================================================
	local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
	local function volume(name, pos, size, cf)
		local p = part({ parent = fx, name = name, pos = pos, cf = cf, size = size, color = C.void, castShadow = false, canQuery = false })
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
	-- золотые искры в воздухе вокруг трона (мерцают)
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
	-- пылинки в конусе света
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
	-- блики-звёздочки на золоте (гребень+корона, шапки подлокотников)
	local glint = {
		Rate = 3.5,
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(0, 0),
		Rotation = NumberRange.new(-15, 15),
		RotSpeed = NumberRange.new(-30, 30),
		Size = ns({ { 0, 0 }, { 0.4, 0.55, 0.15 }, { 1, 0 } }),
		Transparency = ns({ { 0, 0.3 }, { 0.5, 0 }, { 1, 1 } }),
		Color = ColorSequence.new(rgb(255, 236, 190)),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 2.5,
		ZOffset = 1,
	}
	emitter(volume("GlintCrest", nil, V(4.2, 1.6, 0.2), BACK * CFrame.new(0, 6.7, -0.3)), "ThroneGlints", glint)
	local gl = table.clone(glint)
	gl.Rate = 1.5
	emitter(volume("GlintArmL", V(-1.92, 3.0, -1.52), V(0.6, 0.6, 0.1)), "ThroneGlintsL", gl)
	emitter(volume("GlintArmR", V(1.92, 3.0, -1.52), V(0.6, 0.6, 0.1)), "ThroneGlintsR", gl)

	root:SetAttribute("SeatTopY", SEAT_Y)
	root:SetAttribute("DaisTopY", FLOOR_Y)
	root:SetAttribute("ArmX", ARM_X)
	root:SetAttribute("ArmTopY", 3.43)
	root:SetAttribute("ArmFrontZ", -1.45)
	root:SetAttribute("BackTopY", math.floor(bp(0, TOPV, 0).Y * 100 + 0.5) / 100)
end
