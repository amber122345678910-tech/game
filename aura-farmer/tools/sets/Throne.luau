--!nocheck
-- Декорация Throne (S11): чёрная пустота, круглый подиум, золотой резной трон с красным бархатом,
-- корона на гребне спинки, прожектор сверху с видимым конусом света (Beam), пылинки и золотые искры.
--
-- Контракт (AGENTS.md): трон в (0,0,0) лицом в −Z; верх подиума Y=0.8 (вперёд до z≈−3.5, x±4);
-- верх сиденья Y=2.2, сиденье z∈[−1.3,0.6], ширина 3.2; спинка от z≈0.6, до Y≈8.5; корона до Y≈10.5;
-- подлокотники x=±1.9, верх Y≈3.4. Прожектор (0,30,−4) — чуть впереди, чтобы золото ловило свет фасадами.
--
-- Имена для эффектов планов (shot.effects):
--   ParticleEmitter: "ThroneSparkles" (золотые искры), "Dust" (пылинки), "ThroneGlints" / "ThroneGlintsL" / "ThroneGlintsR" (блики на золоте)
--   SpotLight "KeyLight" (+ мягкий ореол "KeySoft") в детали "SpotLamp"; слабые "FillFrontLight", "RimBackLight"
--   Beam "LightShaftBack1..N" (конус за троном), "LightShaftFront1..N" (дымка перед сценой)

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
	gold = rgb(220, 188, 126), -- основное золото, бледное «шампанское» как в клипе (Metal)
	goldHi = rgb(242, 222, 172), -- рельеф/орнамент (Foil)
	goldDeep = rgb(138, 104, 52), -- фон резьбы, торцы
	velvet = rgb(150, 12, 34), -- бархат спинки (малиновый: под тёплым светом даёт коралловый, как в клипе)
	velvetSeat = rgb(138, 6, 20), -- бархат сиденья
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
	light = rgb(255, 230, 192),
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
				if ang > rad(30) then
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

	local function beads(parent, pts, d, step, color, mat)
		for _, it in resample(pts, step) do
			ball(parent, it[1], d, color, mat)
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

	---------------------------------------------------------------- ножки-кабриоли с лапами
	local legs = B:folder("Legs", throne)
	local function cabriole(top, out, s, plain)
		local side = out:Cross(Vector3.yAxis).Unit
		local h = top.Y - FLOOR_Y
		local function at(o, y)
			return top + out * (o * s) + V(0, y * h - h, 0)
		end
		-- профиль: {вынос наружу, доля высоты, толщина}
		local prof = { { 0.0, 1.0, 0.36 }, { 0.12, 0.87, 0.37 }, { 0.16, 0.74, 0.31 }, { 0.09, 0.6, 0.22 }, { -0.01, 0.47, 0.16 }, { -0.03, 0.36, 0.14 } }
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
		if plain then
			-- задние ножки почти не видны: только лапа
			local ballC = V(top.X, FLOOR_Y + 0.13, top.Z) + out * (0.03 * s)
			ball(legs, ballC, 0.24, C.goldHi, M.foil)
			ball(legs, ballC + V(0, 0.12, 0) + out * 0.03, 0.17, C.gold, M.gold)
			return
		end
		-- завиток-«колено» снаружи
		local kc = at(0.24, 0.86)
		local vol = {}
		for i = 0, 10 do
			local a = i / 10 * math.pi * 1.7 + math.pi * 0.5
			local r = 0.15 * s * (1 - i / 15)
			table.insert(vol, { kc + out * (math.cos(a) * r) + V(0, math.sin(a) * r, 0), 0.11 * s * (1 - i / 18) })
		end
		tube(legs, vol, C.goldHi, M.foil)
		-- листок аканта вниз по колену
		petal(legs, at(0.2, 0.8), at(0.17, 0.58), 0.09 * s, C.goldHi, M.foil)
		-- лапа, сжимающая шар
		local ballC = V(top.X, FLOOR_Y + 0.13, top.Z) + out * (0.03 * s)
		ball(legs, ballC, 0.26, C.goldHi, M.foil)
		local ankle = at(0.0, 0.33)
		for k = 0, 2 do
			local ang = (k - 1) * rad(62)
			local dir = out * math.cos(ang) + side * math.sin(ang)
			local mid = ballC + dir * 0.14 + V(0, 0.08, 0)
			local tip = ballC + dir * 0.12 + V(0, -0.09, 0)
			rod(legs, ankle, mid, 0.075, C.gold, M.gold)
			rod(legs, mid, tip, 0.065, C.gold, M.gold)
			ball(legs, mid, 0.08, C.gold, M.gold)
			ball(legs, tip, 0.07, C.goldHi, M.foil)
		end
		rod(legs, ankle, ballC - out * 0.13 + V(0, -0.02, 0), 0.07, C.gold, M.gold) -- задний коготь
	end
	local FRONT_LEG = V(1.92, 1.62, -1.12)
	local BACK_LEG = V(1.62, 1.62, 0.86)
	cabriole(FRONT_LEG, V(0.75, 0, -0.66).Unit, 1)
	cabriole(V(-FRONT_LEG.X, FRONT_LEG.Y, FRONT_LEG.Z), V(-0.75, 0, -0.66).Unit, 1)
	cabriole(BACK_LEG, V(0.6, 0, 0.8).Unit, 0.85, true)
	cabriole(V(-BACK_LEG.X, BACK_LEG.Y, BACK_LEG.Z), V(-0.6, 0, 0.8).Unit, 0.85, true)

	---------------------------------------------------------------- царга сиденья
	local seat = B:folder("Seat", throne)
	local R0, R1 = 1.6, 1.95
	local RY = (R0 + R1) / 2
	box(seat, CFrame.new(0, RY, -1.3), V(3.5, R1 - R0, 0.24), C.gold, M.gold)
	box(seat, CFrame.new(1.75, RY, -0.22), V(0.24, R1 - R0 - 0.012, 2.3), C.gold, M.gold)
	box(seat, CFrame.new(-1.75, RY, -0.22), V(0.24, R1 - R0 - 0.012, 2.3), C.gold, M.gold)
	box(seat, CFrame.new(0, (R0 - 0.01 + 2.15) / 2, 0.82), V(3.5, 2.16 - R0, 0.3), C.goldDeep, M.gold)
	box(seat, CFrame.new(0, RY, -1.425), V(2.9, 0.26, 0.02), C.goldDeep, M.gold) -- филёнка
	rod(seat, V(-1.66, R1, -1.43), V(1.66, R1, -1.43), 0.12, C.goldHi, M.foil)
	rod(seat, V(1.88, R1, -1.2), V(1.88, R1, 0.75), 0.12, C.goldHi, M.foil)
	rod(seat, V(-1.88, R1, -1.2), V(-1.88, R1, 0.75), 0.12, C.goldHi, M.foil)
	beads(seat, { V(-1.6, R0 + 0.05, -1.435), V(1.6, R0 + 0.05, -1.435) }, 0.075, 0.1, C.goldHi, M.foil)
	do
		-- фестон: волна по низу передней царги + раковина
		local pts = {}
		for i = 0, 16 do
			local x = -1.62 + 3.24 * i / 16
			local u = math.abs(x) / 1.62
			table.insert(pts, V(x, R0 - 0.03 - 0.1 * math.sin(u * math.pi) - 0.14 * math.max(0, 1 - u * 3.5) ^ 2, -1.36))
		end
		local sm = {}
		for _, p in spline(pts, 2) do
			table.insert(sm, { p, 0.08 })
		end
		tube(seat, sm, C.gold, M.gold)
		for k = -3, 3 do
			local a = rad(k * 22)
			local o = V(0, R0 - 0.04, -1.41)
			petal(seat, o, o + V(math.sin(a) * 0.22, -math.cos(a) * 0.22, -0.01), 0.075, if k % 2 == 0 then C.goldHi else C.gold, if k % 2 == 0 then M.foil else M.gold)
		end
		ball(seat, V(0, R0, -1.46), 0.12, C.goldHi, M.foil)
		cutGem(seat, CFrame.new(0, RY + 0.02, -1.42), 0.12, C.ruby, C.rubyCore)
		for _, sx in { 1, -1 } do
			local vol = {}
			for i = 0, 12 do
				local a = i / 12 * math.pi * 1.6 + math.pi
				local r = 0.11 * (1 - i / 18)
				table.insert(vol, { V(sx * (0.44 - math.cos(a) * r * 1.4), RY - math.sin(a) * r, -1.445), 0.065 * (1 - i / 22) })
			end
			tube(seat, vol, C.goldHi, M.foil)
			rod(seat, V(sx * 0.5, RY - 0.03, -1.445), V(sx * 1.35, RY - 0.03, -1.445), 0.05, C.goldHi, M.foil)
			ball(seat, V(sx * 1.38, RY - 0.03, -1.445), 0.1, C.goldHi, M.foil)
		end
	end

	---------------------------------------------------------------- подушка сиденья (капитоне)
	local cushion = B:folder("Cushion", throne)
	box(cushion, CFrame.new(0, 2.0, -0.36), V(3.24, 0.2, 1.96), C.velvetSeat, M.velvet)
	rod(cushion, V(-1.5, 2.02, -1.22), V(1.5, 2.02, -1.22), 0.34, C.velvetSeat, M.velvet)
	rod(cushion, V(1.5, 2.02, -1.22), V(1.5, 2.02, 0.5), 0.34, C.velvetSeat, M.velvet)
	rod(cushion, V(-1.5, 2.02, -1.22), V(-1.5, 2.02, 0.5), 0.34, C.velvetSeat, M.velvet)
	ball(cushion, V(1.5, 2.02, -1.22), 0.345, C.velvetSeat, M.velvet)
	ball(cushion, V(-1.5, 2.02, -1.22), 0.345, C.velvetSeat, M.velvet)
	rod(cushion, V(-1.56, 1.9, -1.4), V(1.56, 1.9, -1.4), 0.05, C.goldHi, M.foil) -- шнур
	for i = 0, 3 do
		for j = 0, 2 do
			ell(cushion, CFrame.new(-1.2 + i * 0.8, 2.06, -0.95 + j * 0.62), V(0.86, 0.28, 0.7), C.velvetSeat, M.velvet)
		end
	end
	for i = 0, 4 do
		for j = 0, 3 do
			local x, z = -1.6 + i * 0.8, -1.26 + j * 0.62
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
		local fz = zf - 0.36 -- лицо тумбы
		-- резная тумба с угловыми колонками
		box(arms, CFrame.new(x, 2.065, zf), V(0.6, 0.95, 0.72), C.gold, M.gold)
		for _, cx in { -0.3, 0.3 } do
			for _, cz in { -0.36, 0.36 } do
				rod(arms, V(x + cx, 1.62, zf + cz), V(x + cx, 2.52, zf + cz), 0.12, C.goldHi, M.foil)
			end
		end
		box(arms, CFrame.new(x, 2.08, fz - 0.005), V(0.44, 0.78, 0.02), C.goldDeep, M.gold)
		-- рельеф: веер листьев сверху, камень в бусинной оправе, пара завитков-волют внизу
		for k = -2, 2 do
			local a = rad(k * 24)
			local o = V(x, 2.2, fz - 0.03)
			petal(arms, o, o + V(math.sin(a) * 0.2, math.cos(a) * 0.2, 0), 0.06, if k % 2 == 0 then C.goldHi else C.gold, M.foil)
		end
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			ball(arms, V(x + math.cos(a) * 0.1, 2.02 + math.sin(a) * 0.12, fz - 0.04), 0.045, C.goldHi, M.foil)
		end
		for _, k in { -1, 1 } do
			local vol = {}
			for i = 0, 11 do
				local a = math.pi * 0.5 + k * (i / 11 * math.pi * 1.6)
				local r = 0.1 * (1 - i / 16)
				table.insert(vol, { V(x + k * 0.1 + math.cos(a) * r, 1.79 + math.sin(a) * r, fz - 0.035), 0.06 * (1 - i / 24) })
			end
			tube(arms, vol, C.goldHi, M.foil)
		end
		rod(arms, V(x - 0.1, 1.89, fz - 0.035), V(x + 0.1, 1.89, fz - 0.035), 0.06, C.goldHi, M.foil)
		-- карниз, шейка с бусинами, карниз
		box(arms, CFrame.new(x, 2.57, zf), V(0.7, 0.1, 0.84), C.goldHi, M.foil)
		box(arms, CFrame.new(x, 2.69, zf), V(0.5, 0.16, 0.62), C.goldDeep, M.gold)
		beads(arms, { V(x - 0.2, 2.69, fz + 0.04), V(x + 0.2, 2.69, fz + 0.04) }, 0.07, 0.1, C.goldHi, M.foil)
		box(arms, CFrame.new(x, 2.8, zf), V(0.64, 0.07, 0.78), C.goldHi, M.foil)
		-- шапка: «свиток» — брусок со скруглёнными передним и задним верхними рёбрами
		local CAP0, CAP1, RR = 2.83, 3.43, 0.2
		box(arms, CFrame.new(x, (CAP0 + CAP1 - RR) / 2, zf), V(0.64, CAP1 - CAP0 - RR, 0.8), C.gold, M.gold)
		box(arms, CFrame.new(x, CAP1 - RR / 2, zf), V(0.64, RR, 0.8 - 2 * RR), C.gold, M.gold)
		rod(arms, V(x - 0.31, CAP1 - RR, zf - 0.4 + RR), V(x + 0.31, CAP1 - RR, zf - 0.4 + RR), RR * 2, C.gold, M.gold)
		rod(arms, V(x - 0.31, CAP1 - RR, zf + 0.4 - RR), V(x + 0.31, CAP1 - RR, zf + 0.4 - RR), RR * 2, C.gold, M.gold)
		-- торцы свитка: спирали на боковых гранях у переднего края
		for _, k in { -1, 1 } do
			local vol = {}
			for i = 0, 16 do
				local a = i / 16 * math.pi * 2.2 + math.pi * 0.5
				local r = 0.2 * (1 - i / 20)
				table.insert(vol, { V(x + k * 0.335, CAP1 - 0.23 + math.sin(a) * r, zf - 0.18 + math.cos(a) * r), 0.075 * (1 - i / 30) })
			end
			tube(arms, vol, C.goldHi, M.foil)
			ball(arms, V(x + k * 0.335, CAP1 - 0.23, zf - 0.18), 0.09, C.goldHi, M.foil)
		end
		-- лицо шапки: розетка и заклёпки по верхнему ребру
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			ball(arms, V(x + math.cos(a) * 0.075, 3.08 + math.sin(a) * 0.075, fz - 0.02), 0.07, C.goldHi, M.foil)
		end
		ball(arms, V(x, 3.08, fz - 0.07), 0.09, C.goldHi, M.foil)
		for _, dx in { -0.2, 0, 0.2 } do
			ball(arms, V(x + dx, CAP1 - 0.06, zf - 0.32), 0.065, C.goldHi, M.foil)
		end
		gem(arms, V(x, 2.02, fz - 0.03), 0.14, C.ruby, C.rubyCore)
		-- подлокотник: золотой брус + бархатный валик
		-- (брус и боковина заходят в раму спинки — без щели между подлокотником и спинкой)
		box(arms, CFrame.new(x, 3.08, 0.09), V(0.38, 0.2, 1.74), C.gold, M.gold)
		rod(arms, V(x + s * 0.19, 2.99, -0.76), V(x + s * 0.19, 2.99, 0.92), 0.08, C.goldHi, M.foil)
		rod(arms, V(x - s * 0.19, 2.99, -0.76), V(x - s * 0.19, 2.99, 0.92), 0.08, C.goldHi, M.foil)
		ell(arms, CFrame.new(x, 3.22, 0.0), V(0.42, 0.32, 1.46), C.velvet, M.velvet)
		-- бархатная боковина под подлокотником и стойка у спинки
		box(arms, CFrame.new(x, 2.47, 0.09), V(0.16, 1.04, 1.74), C.velvet, M.velvet)
		rod(arms, V(x, 1.9, 0.8), V(x, 3.0, 0.8), 0.17, C.gold, M.gold)
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
	local function bcf(x, v, w, rz)
		return BACK * CFrame.new(x, v, w) * CFrame.Angles(0, 0, rad(rz or 0))
	end

	-- контур панели (правая половина): {полуширина x, высота v над сиденьем}
	local outlineR = {
		{ 1.50, -0.05 },
		{ 1.48, 0.7 },
		{ 1.52, 1.5 },
		{ 1.60, 2.3 },
		{ 1.70, 3.1 },
		{ 1.78, 3.9 },
		{ 1.83, 4.6 },
		{ 1.84, 5.08 },
		{ 1.79, 5.44 },
		{ 1.66, 5.69 },
		{ 1.42, 5.86 },
		{ 1.02, 5.96 },
		{ 0.52, 6.03 },
		{ 0.0, 6.06 },
	}
	local function halfWidth(v)
		if v <= outlineR[1][2] then
			return outlineR[1][1]
		end
		for i = 2, #outlineR do
			local a, b = outlineR[i - 1], outlineR[i]
			if v <= b[2] then
				return a[1] + (b[1] - a[1]) * (v - a[2]) / (b[2] - a[2])
			end
		end
		return 0
	end
	local ctrl = {}
	for i = 1, #outlineR do
		table.insert(ctrl, V(outlineR[i][1], outlineR[i][2], 0))
	end
	for i = #outlineR - 1, 1, -1 do
		table.insert(ctrl, V(-outlineR[i][1], outlineR[i][2], 0))
	end
	local outline = spline(ctrl, 3)
	local function outNormal(i, pts)
		local a = pts[math.max(1, i - 1)]
		local b = pts[math.min(#pts, i + 1)]
		local t = (b - a).Unit
		return V(t.Y, -t.X, 0)
	end

	-- панель: горизонтальные полосы по контуру
	local PANEL_D = 0.46
	do
		local v = -0.1
		while v < 6.06 do
			local step = if v < 4.6 then 0.45 elseif v < 5.4 then 0.14 else 0.07
			local v1 = math.min(6.06, v + step)
			local w = math.min(halfWidth(v), halfWidth(v1))
			if w > 0.05 then
				box(back, BACK * CFrame.new(0, (v + v1) / 2, PANEL_D / 2 + 0.01), V(w * 2, v1 - v + 0.002, PANEL_D - 0.02), C.velvet, M.velvet)
			end
			v = v1
		end
	end
	-- набивка: стопка сильно перекрытых эллипсоидов, ширина каждого — по контуру; поперечная
	-- выпуклость повторяет силуэт спинки, края уходят под раму, вертикальной ряби нет
	do
		-- высота каждого эллипсоида — максимальная, при которой он не вылезает за контур (+запас под раму)
		local function fits(vc, w, H)
			for k = -12, 12 do
				local t = k / 12
				local y = vc + t * H / 2
				local lim = if y > 6.05 or y < -0.35 then -1 else halfWidth(y) + 0.07
				if w * math.sqrt(math.max(0, 1 - t * t)) > lim then
					return false
				end
			end
			return true
		end
		local v = 0.2
		while v < 5.92 do
			local w = halfWidth(v) - 0.03
			local H = 0.2
			while H < 4.2 and fits(v, w, H + 0.05) do
				H += 0.05
			end
			local bulge = 0.13 + 0.05 * math.sin(math.clamp(v / 6, 0, 1) * math.pi)
			ell(back, BACK * CFrame.new(0, v, 0), V(w * 2, H, bulge * 2), C.velvet, M.velvet)
			v += if v < 4.6 then 0.3 elseif v < 5.4 then 0.16 else 0.1
		end
	end

	-- рама: внешний валик, наружный тонкий валик, торец, бусины изнутри, задний валик
	do
		local front, outer = {}, {}
		local function nAt(sv)
			return outNormal(math.clamp(math.floor(sv * (#outline - 1) + 0.5) + 1, 1, #outline), outline)
		end
		for _, it in resample(outline, 0.24) do
			local p, nrm = it[1], nAt(it[2])
			table.insert(front, { bp(p.X + nrm.X * 0.04, p.Y + nrm.Y * 0.04, -0.05), 0.3 })
		end
		for _, it in resample(outline, 0.3) do
			local p, nrm = it[1], nAt(it[2])
			table.insert(outer, { bp(p.X + nrm.X * 0.24, p.Y + nrm.Y * 0.24, 0.02), 0.12 })
		end
		tube(back, front, C.gold, M.gold)
		tube(back, outer, C.goldHi, M.foil)
		-- торец рамы
		local edge = resample(outline, 0.5)
		for i = 1, #edge - 1 do
			local a, b = edge[i][1], edge[i + 1][1]
			local na = outNormal(math.max(1, math.floor(edge[i][2] * (#outline - 1)) + 1), outline)
			local nb = outNormal(math.max(1, math.floor(edge[i + 1][2] * (#outline - 1)) + 1), outline)
			local pa, pb = a + na * 0.14, b + nb * 0.14
			local cf, len = along(bp(pa.X, pa.Y, PANEL_D / 2 + 0.02), bp(pb.X, pb.Y, PANEL_D / 2 + 0.02))
			box(back, cf, V(len + 0.06, 0.2 + (i % 2) * 0.012, PANEL_D + 0.08 + (i % 2) * 0.012), C.goldDeep, M.gold)
		end
		-- задний валик
		local backT = {}
		for _, it in resample(outline, 0.55) do
			local p = it[1]
			table.insert(backT, { bp(p.X, p.Y, PANEL_D + 0.04), 0.16 })
		end
		tube(back, backT, C.gold, M.gold)
		-- бусины внутри контура
		local inner = {}
		for i, p in outline do
			local nrm = outNormal(i, outline)
			table.insert(inner, bp(p.X - nrm.X * 0.24, p.Y - nrm.Y * 0.24, -0.06))
		end
		beads(back, inner, 0.09, 0.135, C.goldHi, M.foil)
	end

	-- Волюта (спираль-трубка) в плоскости спинки
	local function volute(parent, cx, cv, w, r0, r1, a0, turns, d0, d1, color, mat)
		local n = math.max(6, math.floor(math.abs(turns) * 14))
		local pts = {}
		for i = 0, n do
			local t = i / n
			local a = a0 + turns * t * math.pi * 2
			local r = r0 * (r1 / r0) ^ t
			table.insert(pts, { bp(cx + math.cos(a) * r, cv + math.sin(a) * r, w - 0.05 * t), d0 + (d1 - d0) * t })
		end
		tube(parent, pts, color or C.goldHi, mat or M.foil)
	end
	-- Кривая-трубка по контрольным точкам {x, v, [w]} с толщиной d0→d1
	local function sweep(parent, ctl, d0, d1, color, mat, step)
		local pv = {}
		for _, q in ctl do
			table.insert(pv, V(q[1], q[2], q[3] or -0.08))
		end
		local out = {}
		for _, it in resample(spline(pv, 6), step or 0.13) do
			local p = it[1]
			table.insert(out, { bp(p.X, p.Y, p.Z), d0 + (d1 - d0) * it[2] })
		end
		tube(parent, out, color or C.goldHi, mat or M.foil)
	end
	-- Розетка: венчик лепестков + сердцевина (или камень)
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
	-- Лист аканта: веер из капсул от общей «почки» (single — одна капсула)
	local function leaf(parent, cx, cv, w, ang, len, single)
		local o = bp(cx, cv, w)
		for k = -1, 1 do
			if not single or k == 0 then
				local a = rad(ang + k * 30)
				local L = len * (if k == 0 then 0.85 else 0.62)
				local tip = bp(cx - math.sin(a) * L, cv + math.cos(a) * L, w - 0.02)
				petal(parent, o, tip, len * (if k == 0 then 0.32 else 0.25), if k == 0 then C.goldHi else C.gold, if k == 0 then M.foil else M.gold)
			end
		end
		if not single then
			ball(parent, o, len * 0.4, C.goldHi, M.foil)
		end
	end

	-- «Уши» по бокам спинки: C-завитки с розетками на уровне плеч, над подлокотником и под гребнем
	local orn = B:folder("Ornament", back)
	for _, s in { 1, -1 } do
		local ex = halfWidth(3.3) * s
		sweep(orn, { { ex + 0.05 * s, 2.55 }, { ex + 0.38 * s, 2.85 }, { ex + 0.58 * s, 3.3 }, { ex + 0.52 * s, 3.72 } }, 0.3, 0.22, nil, nil, 0.12)
		volute(orn, ex + 0.3 * s, 3.7, -0.1, 0.24, 0.05, 0, 1.25 * s, 0.22, 0.09)
		rosette(orn, ex + 0.3 * s, 3.7, -0.16, 0.16, 7)
		leaf(orn, ex + 0.34 * s, 2.5, -0.08, 180 + 25 * s, 0.5)
		leaf(orn, ex + 0.1 * s, 4.0, -0.1, -15 * s, 0.4)
		local lx = halfWidth(1.2) * s
		sweep(orn, { { lx + 0.05 * s, 1.0 }, { lx + 0.3 * s, 1.15 }, { lx + 0.38 * s, 1.45 } }, 0.2, 0.15, nil, nil, 0.12)
		volute(orn, lx + 0.24 * s, 1.47, -0.1, 0.15, 0.04, 0, 1.2 * s, 0.15, 0.06)
		local ux = halfWidth(5.0) * s
		sweep(orn, { { ux - 0.05 * s, 4.7 }, { ux + 0.26 * s, 4.92 }, { ux + 0.34 * s, 5.25 } }, 0.2, 0.15, nil, nil, 0.12)
		volute(orn, ux + 0.2 * s, 5.27, -0.1, 0.15, 0.04, 0, 1.2 * s, 0.15, 0.06)
	end

	---------------------------------------------------------------- гребень
	local crest = B:folder("Crest", back)
	local CW = -0.1
	do
		-- основание — массивный изогнутый валик поверх верхней кромки панели
		local base = {}
		for i = 0, 18 do
			local x = -1.8 + 3.6 * i / 18
			table.insert(base, V(x, 5.88 + 0.2 * (1 - (x / 1.8) ^ 2) - 0.12 * math.max(0, math.abs(x) - 1.25), CW))
		end
		local bt = {}
		for _, p in spline(base, 2) do
			table.insert(bt, { bp(p.X, p.Y + 0.02, p.Z - 0.02), 0.34 })
		end
		tube(crest, bt, C.gold, M.gold)
		-- сплошной задник гребня (тёмное золото)
		local v = 5.85
		while v < 7.15 do
			local v1 = v + 0.11
			local t = (v1 - 5.85) / 1.3
			local w = 1.9 * math.sqrt(math.max(0, 1 - t ^ 1.6)) * (1 - 0.25 * t)
			if w > 0.08 then
				box(crest, BACK * CFrame.new(0, (v + v1) / 2, 0.12), V(w * 2, 0.112, 0.16), C.goldDeep, M.gold)
			end
			v = v1
		end
	end
	for _, s in { 1, -1 } do
		-- большой C-завиток: от картуша вверх-наружу и вниз, закручивается у угла
		sweep(crest, { { 0.42 * s, 6.4 }, { 0.85 * s, 6.98 }, { 1.38 * s, 7.06 }, { 1.84 * s, 6.72 }, { 2.04 * s, 6.22 } }, 0.3, 0.22, nil, nil, 0.13)
		volute(crest, 1.84 * s, 6.12, CW - 0.04, 0.2, 0.05, (if s > 0 then 0.1 else math.pi - 0.1), -1.35 * s, 0.22, 0.08)
		-- нижний завиток вдоль основания, закручен вверх
		sweep(crest, { { 0.45 * s, 6.08 }, { 0.9 * s, 6.16 }, { 1.28 * s, 6.1 } }, 0.2, 0.16, nil, nil, 0.12)
		volute(crest, 1.32 * s, 6.3, CW - 0.06, 0.17, 0.04, -0.5 * math.pi, 1.15 * s, 0.16, 0.06)
		-- верхний завиток к короне
		sweep(crest, { { 0.5 * s, 6.85 }, { 0.62 * s, 7.15 }, { 0.82 * s, 7.32 } }, 0.16, 0.12, nil, nil, 0.11)
		volute(crest, 0.9 * s, 7.2, CW - 0.06, 0.13, 0.035, (if s > 0 then 0.6 else math.pi - 0.6), 1.1 * s, 0.12, 0.05)
		-- розетки
		rosette(crest, 0.9 * s, 6.52, CW - 0.12, 0.22, 8, { C.emerald, C.emeraldCore })
		rosette(crest, 1.58 * s, 6.62, CW - 0.08, 0.13, 6)
		-- листья
		leaf(crest, 1.32 * s, 7.06, CW - 0.06, -35 * s, 0.48)
		leaf(crest, 2.08 * s, 6.55, CW - 0.04, -80 * s, 0.4)
		leaf(crest, 0.6 * s, 5.95, CW - 0.1, -95 * s, 0.38)
		ball(crest, bp(2.12 * s, 5.78, CW - 0.04), 0.12, C.goldHi, M.foil)
		-- листья аканта по внешней кромке большого завитка
		for _, q in { { 0.62, 6.83, 40 }, { 1.1, 7.12, 10 }, { 1.62, 7.0, -30 }, { 1.98, 6.6, -60 } } do
			leaf(crest, q[1] * s, q[2], CW - 0.02, -q[3] * s, 0.3, true)
		end
	end
	-- раковина-веер позади короны
	for k = -3, 3 do
		local a = rad(k * 22)
		petal(crest, bp(0, 7.0, 0.2), bp(-math.sin(a) * 0.6, 7.0 + math.cos(a) * 0.6, 0.2), 0.13, if k % 2 == 0 then C.goldHi else C.gold, M.foil)
	end
	-- картуш: овальный медальон с большим рубином
	do
		local cx, cv = 0, 6.55
		local ring = {}
		for i = 0, 32 do
			local a = i / 32 * math.pi * 2
			table.insert(ring, bp(cx + math.cos(a) * 0.34, cv + math.sin(a) * 0.44, CW - 0.16))
		end
		beads(crest, ring, 0.09, 0.08, C.goldHi, M.foil)
		part({ parent = crest, cf = BACK * CFrame.new(cx, cv, CW - 0.06) * CFrame.Angles(0, math.pi / 2, 0), size = V(0.14, 0.74, 0.74), shape = "Cylinder", color = C.gold, material = M.gold })
		cutGem(crest, BACK * CFrame.new(cx, cv, CW - 0.14), 0.24, C.ruby, C.rubyCore)
		leaf(crest, 0, 6.02, CW - 0.14, 180, 0.42)
		ball(crest, bp(0, 6.06, CW - 0.18), 0.13, C.goldHi, M.foil)
	end

	---------------------------------------------------------------- корона
	local crown = B:folder("Crown", throne)
	do
		local base = bp(0, 7.12, 0.08)
		local cy, cz = base.Y, base.Z
		local R = 0.6
		local function cp(a, r, y)
			return V(math.sin(a) * r, y, cz - math.cos(a) * r) -- a=0 — к зрителю (−Z)
		end
		local function vdisc(name, y0, y1, r, color, mat)
			part({ parent = crown, name = name, cf = CFrame.new(0, (y0 + y1) / 2, cz) * CFrame.Angles(0, 0, math.pi / 2), size = V(y1 - y0, r * 2, r * 2), shape = "Cylinder", color = color, material = mat })
		end
		vdisc("CrownPlinth", cy - 0.12, cy + 0.02, R * 0.78, C.gold, M.gold)
		vdisc("CrownRim", cy + 0.0, cy + 0.07, R + 0.05, C.gold, M.gold)
		vdisc("CrownBand", cy + 0.05, cy + 0.33, R, C.goldHi, M.foil)
		vdisc("CrownRim2", cy + 0.31, cy + 0.37, R + 0.04, C.gold, M.gold)
		ell(crown, CFrame.new(0, cy + 0.36, cz), V(R * 1.86, 0.66, R * 1.86), C.velvet, M.velvet)
		local gems = { { C.ruby, C.rubyCore }, { C.emerald, C.emeraldCore }, { C.sapphire, C.sapphireCore }, { C.emerald, C.emeraldCore } }
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local g = gems[k % 4 + 1]
			gem(crown, cp(a, R + 0.0, cy + 0.19), 0.15, g[1], g[2])
			ball(crown, cp(a + math.pi / 8, R + 0.01, cy + 0.19), 0.07, C.pearl, "SmoothPlastic")
		end
		-- зубцы: кресты и лилии по кругу
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local p = cp(a, R - 0.03, cy + 0.47)
			local cf = CFrame.new(p) * CFrame.Angles(0, -a, 0)
			if k % 2 == 0 then
				box(crown, cf * CFrame.new(0, 0.02, 0), V(0.09, 0.28, 0.05), C.goldHi, M.foil)
				box(crown, cf * CFrame.new(0, 0.06, 0), V(0.24, 0.08, 0.035), C.goldHi, M.foil)
				ball(crown, (cf * CFrame.new(0, 0.06, -0.02)).Position, 0.07, C.ruby, M.glass, { transparency = 0.1 })
				ball(crown, p + V(0, 0.2, 0), 0.07, C.pearl, "SmoothPlastic")
			else
				local o = (cf * CFrame.new(0, -0.1, 0)).Position
				petal(crown, o, (cf * CFrame.new(0, 0.13, 0)).Position, 0.075, C.goldHi, M.foil)
				petal(crown, o, (cf * CFrame.new(0.11, 0.04, 0)).Position, 0.055, C.goldHi, M.foil)
				petal(crown, o, (cf * CFrame.new(-0.11, 0.04, 0)).Position, 0.055, C.goldHi, M.foil)
				ball(crown, p + V(0, 0.18, 0), 0.07, C.pearl, "SmoothPlastic")
			end
		end
		-- две дуги крест-накрест (бусины)
		for _, rot in { math.pi / 4, -math.pi / 4 } do
			local arc = {}
			for i = 0, 20 do
				local t = i / 20 * math.pi
				local x = math.cos(t) * (R - 0.05)
				table.insert(arc, V(x * math.cos(rot), cy + 0.36 + math.sin(t) * 0.4, cz + x * math.sin(rot)))
			end
			beads(crown, arc, 0.085, 0.07, C.goldHi, M.foil)
		end
		-- держава с крестом
		ball(crown, V(0, cy + 0.86, cz), 0.22, C.goldHi, M.foil)
		rod(crown, V(-0.12, cy + 0.86, cz), V(0.12, cy + 0.86, cz), 0.035, C.gold, M.gold)
		box(crown, CFrame.new(0, cy + 1.06, cz), V(0.055, 0.24, 0.055), C.goldHi, M.foil)
		box(crown, CFrame.new(0, cy + 1.09, cz), V(0.17, 0.055, 0.04), C.goldHi, M.foil)
		gem(crown, V(0, cy + 1.09, cz - 0.03), 0.06, C.ruby, C.rubyCore)
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
	spot("FillFront", V(0, 5, -11), V(0, 3.5, 0), "SpotLight", { Brightness = 0.35, Range = 24, Angle = 46, Face = "Front", Shadows = false, Color = rgb(255, 214, 160) })
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
	local FRONT_P = V(0, 0.02, -5.6)
	local top = anchor("ShaftTop", TOP_P)
	local backEnd = anchor("ShaftBackEnd", BACK_P)
	local frontEnd = anchor("ShaftFrontEnd", FRONT_P)
	local coneTan = math.tan(rad(8.5))
	local Lb = (BACK_P - TOP_P).Magnitude
	local Lf = (FRONT_P - TOP_P).Magnitude
	-- Ленты стоят не на оси конуса: из камеры плана (0,4,−14) задняя кажется меньше, передняя — больше.
	-- Поправка ширины у пола, чтобы обе проецировались на настоящий силуэт конуса.
	local CAM_Z = -14
	local axisZ0 = LAMP.Z + (TARGET.Z - LAMP.Z) * (LAMP.Y / (LAMP.Y - TARGET.Y)) -- ось конуса на высоте пола
	local kBack = (BACK_P.Z - CAM_Z) / (axisZ0 - CAM_Z)
	local kFront = (FRONT_P.Z - CAM_Z) / (axisZ0 - CAM_Z)
	local Lc = (V(0, 0, axisZ0) - TOP_P).Magnitude
	local warm = rgb(246, 238, 224)
	-- Профиль яркости поперёк конуса P(r) (r — доля радиуса): плотная середина, мягкое плечо к краю.
	-- Ленты шириной f_i, непрозрачность каждой = P(f_{i−1}) − P(f_i): сумма лент даёт P без ступенек.
	local function profile(r)
		local e = math.clamp((r - 0.55) / (1.12 - 0.55), 0, 1)
		return (1 - e * e * (3 - 2 * e)) * (0.8 + 0.2 * (1 - math.min(1, r * r)))
	end
	local N = 14
	local prev = profile(0)
	for i = 1, N do
		local f = 0.1 + (1.12 - 0.1) * (i - 1) / (N - 1)
		local p = profile(f)
		local a = prev - p
		prev = p
		beam(string.format("LightShaftBack%02d", i), top, backEnd, 0.35 + f * 0.5, 2 * Lc * coneTan * f * kBack, math.min(1, a * 0.45), warm)
		if f > 0.3 then
			beam(string.format("LightShaftFront%02d", i), top, frontEnd, 0.35 + f * 0.5, 2 * Lc * coneTan * f * kFront, math.min(1, a * 0.18), warm)
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
		Size = ns({ { 0, 0 }, { 0.4, 0.75, 0.2 }, { 1, 0 } }),
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
end
