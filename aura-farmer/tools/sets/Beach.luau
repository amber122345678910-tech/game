--!nocheck
-- Декорация «Beach»: пляж Схевенинген (Нидерланды).
-- Локальные координаты декорации: Y=0 — верх песка, +Z — юг (бульвар и город), -Z — море, пирс у x≈+160.
-- Зона постановки вокруг (0,0,0) свободна (только плоские следы шин/вмятины на песке высотой < 0.1).
-- Если камера смотрит на город (+Z), то +X — СЛЕВА в кадре; если на море (-Z) — +X справа.

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

local V = Vector3.new

local function hex(h: number)
	return Color3.fromRGB(bit32.rshift(h, 16) % 256, bit32.rshift(h, 8) % 256, h % 256)
end

local function mix(a, b, t)
	return a:Lerp(b, t)
end

-- Детерминированный ГПСЧ (Park–Miller)
local seed = 20251019
local function rnd()
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function rr(a, b)
	return a + (b - a) * rnd()
end
local function pick(t)
	return t[1 + math.floor(rnd() * #t) % #t]
end

-- ===== Палитра (по кадрам клипа) =====
local C = {
	sand = hex(0xC8B48E),
	sandPacked = hex(0xBCA885),
	tread = hex(0x9A8466),
	dent = hex(0xAE9A78),
	wet = hex(0xA08D6E),
	wetter = hex(0x8A7A62),
	foam = hex(0xF2F4F3),
	white = hex(0xE8E5DE),
	offWhite = hex(0xD9D4C9),
	beige = hex(0xD3C3A6),
	sandstone = hex(0xC9B08C),
	concrete = hex(0xA9A7A0),
	grey = hex(0x8E918F),
	darkGrey = hex(0x4A4F4E),
	glassGreen = hex(0x3C5552),
	glassTeal = hex(0x4E6D70),
	glassBlue = hex(0x5D7C8E),
	glassDark = hex(0x2C3A3C),
	pierTeal = hex(0x2E4643),
	pierLeg = hex(0xC2C0BB),
	lamp = hex(0x3A403E),
	clubBlue = hex(0x2F86AE),
	clubTeal = hex(0x37A0A8),
	clubNavy = hex(0x234E78),
	wood = hex(0x9C7A55),
	woodDark = hex(0x6E5640),
	red = hex(0xC8282E),
	nlRed = hex(0xAE1C28),
	nlBlue = hex(0x21468B),
	orange = hex(0xF07D1E),
	yellow = hex(0xF2C230),
}

return function(B)
	local root = B.model

	local function folder(name)
		return B:folder(name, root)
	end

	-- Простая коробка. rot — градусы (X, Y, Z).
	local function box(parent, pos, size, color, material, rot, extra)
		local spec = { pos = pos, size = size, color = color, material = material or "SmoothPlastic", rot = rot, parent = parent }
		for k, v in extra or {} do
			spec[k] = v
		end
		return B:part(spec)
	end
	local function wedge(parent, pos, size, color, material, rot, extra)
		local spec = { pos = pos, size = size, color = color, material = material or "SmoothPlastic", rot = rot, parent = parent, shape = "Wedge" }
		for k, v in extra or {} do
			spec[k] = v
		end
		return B:part(spec)
	end
	local function ell(parent, pos, size, color, material, rot, extra)
		local spec = { pos = pos, size = size, color = color, material = material or "SmoothPlastic", rot = rot, parent = parent, mesh = "Sphere" }
		for k, v in extra or {} do
			spec[k] = v
		end
		return B:part(spec)
	end
	-- Вертикальный цилиндр (ось Y): низ в y0, высота h, диаметр d
	local function post(parent, x, y0, z, h, d, color, material, extra)
		local e = { parent = parent }
		for k, v in extra or {} do
			e[k] = v
		end
		return B:cyl(V(x, y0 + h / 2, z), h, d, color, material or "Metal", "Y", nil, e)
	end
	-- Деталь, натянутая между двумя точками (балка/трос)
	local function beam(parent, a, b, w, t, color, material, extra)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local up = if math.abs(dir.Y) > 0.98 then V(1, 0, 0) else V(0, 1, 0)
		local cf = CFrame.lookAt(mid, b, up) -- -Z смотрит на b
		local spec = { cf = cf, size = V(w, t, len), color = color, material = material or "Metal", parent = parent }
		for k, v in extra or {} do
			spec[k] = v
		end
		return B:part(spec)
	end
	local NOSH = { castShadow = false }

	-- =====================================================================
	-- 1) Terrain: море, дно, пляж, дюны, бульвар
	-- =====================================================================
	-- Порядок важен: позже залитое перекрывает раньше залитое.
	B:terrain("Block", V(0, -3.3, -1950), V(7000, 5.4, 3620), "Water") -- y -6 … -0.6, z -3760 … -140
	B:terrain("Block", V(0, -8, -1980), V(7000, 4, 3560), "Sand") -- дно y -10 … -6, z -3760 … -200
	B:terrain("Wedge", V(0, -3, -215), V(5600, 6, 130), "Sand") -- откос под воду: y=0 при z=-150 … y=-6 при z=-280
	B:terrain("Block", V(0, -5, 75), V(5600, 10, 450), "Sand") -- пляж: верх y=0, z -150 … +300
	-- лёгкие пологие бугры песка к бульвару (до ~2 студов)
	for _, b in {
		{ -160, 170, 90, 2.2 }, { 40, 205, 110, 2.8 }, { 230, 175, 90, 1.8 }, { -330, 215, 100, 2.6 },
		{ 420, 210, 120, 3.0 }, { -520, 190, 90, 1.6 }, { 620, 230, 140, 4.0 }, { -760, 230, 120, 3.0 },
	} do
		local r = b[3]
		B:terrain("Ball", V(b[1], b[4] - r, b[2]), V(2 * r, 2 * r, 2 * r), "Sand")
	end
	-- насыпь к бульвару: от y=0 (z=+240) до y=+4 (z=+300)
	B:terrain("Wedge", V(0, 2, 270), V(5600, 4, 60), "Sand")
	-- бульвар (набережная) y=+6, z +300 … +760
	B:terrain("Block", V(0, 1, 530), V(5600, 10, 460), "Pavement")
	-- дюны далеко на востоке и западе (вне города)
	for i = 0, 9 do
		local x = 1000 + i * 170 + rr(-40, 40)
		local r = rr(70, 120)
		B:terrain("Ball", V(x, rr(6, 14) - r, rr(230, 300)), V(2 * r, 2 * r, 2 * r), "Sand")
		local x2 = -1250 - i * 140 + rr(-30, 30)
		local r2 = rr(60, 100)
		B:terrain("Ball", V(x2, rr(5, 11) - r2, rr(230, 300)), V(2 * r2, 2 * r2, 2 * r2), "Sand")
	end

	-- =====================================================================
	-- 2) Кромка воды: мокрый песок, пена, буруны
	-- =====================================================================
	local shore = folder("Shoreline")
	do
		-- мокрая полоса (несколько неровных кусков на разной высоте, чтобы не было z-fighting)
		local x = -1800
		local k = 0
		while x < 1800 do
			local w = rr(140, 260)
			local depth = rr(26, 44)
			k += 1
			local top = 0.02 + (k % 3) * 0.012
			box(shore, V(x + w / 2, top - 0.1, -150 + depth / 2), V(w + 30, 0.2, depth), mix(C.wet, C.sand, rr(0.1, 0.35)), "Sand", nil, NOSH)
			x += w
		end
		-- влажный откос до воды (наклон как у клина terrain: 6 на 130)
		local slope = math.deg(math.atan(6 / 130))
		for i = 0, 5 do
			local w = 600
			local cx = -1500 + i * w + w / 2
			box(shore, V(cx, -0.42, -159), V(w, 0.2, 19), C.wetter, "Sand", V(-slope, 0, 0), { castShadow = false, reflectance = 0.12 })
		end
		-- пена у кромки и буруны дальше в море
		local lines = { { z = -163.5, w = 1.6, tr = 0.15 }, { z = -168, w = 0.9, tr = 0.45 }, { z = -186, w = 1.2, tr = 0.4 }, { z = -214, w = 1.6, tr = 0.5 }, { z = -262, w = 1.4, tr = 0.6 } }
		for li, L in lines do
			local xx = -1300
			while xx < 1300 do
				local len = rr(60, 150)
				if rnd() > 0.18 or li == 1 then
					box(shore, V(xx + len / 2, -0.5, L.z + rr(-2.5, 2.5)), V(len, 0.08, L.w * rr(0.7, 1.3)), C.foam, "SmoothPlastic", V(0, rr(-1.2, 1.2), 0), { castShadow = false, transparency = L.tr })
				end
				xx += len + rr(0, 20)
			end
		end
	end

	-- =====================================================================
	-- 3) Следы шин и вмятины у зоны постановки
	-- =====================================================================
	local tracks = folder("TireTracks")
	do
		-- Безье по точкам (x, z) -> равномерные отсчёты по длине
		local function bezier(p0, p1, p2, p3, t)
			local u = 1 - t
			return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
		end
		local function samplePath(ctrl, step)
			local dense = {}
			for i = 0, 400 do
				table.insert(dense, bezier(ctrl[1], ctrl[2], ctrl[3], ctrl[4], i / 400))
			end
			local out = { dense[1] }
			local acc = 0
			for i = 2, #dense do
				local d = (dense[i] - dense[i - 1]).Magnitude
				acc += d
				while acc >= step do
					acc -= step
					local f = 1 - acc / d
					table.insert(out, dense[i - 1]:Lerp(dense[i], f))
				end
			end
			return out
		end
		local V2 = function(x, z)
			return V(x, 0, z)
		end
		-- Каждый трек: контрольные точки (x,z), колея (между колёсами), ширина колеса, шаг протектора.
		-- Протектор (поперечные грунтозацепы) рисуется только в зоне, видимой камерами у центра.
		local list = {
			{ ctrl = { V2(-110, 30), V2(-30, 13), V2(30, 9), V2(115, 22) }, gauge = 4.6, tyre = 1.5, lug = 0.85 },
			{ ctrl = { V2(-95, -20), V2(-25, -8), V2(25, -7.5), V2(100, -24) }, gauge = 4.6, tyre = 1.5, lug = 0.85 },
			{ ctrl = { V2(-75, 75), V2(-22, 34), V2(12, 2), V2(36, -70) }, gauge = 5.2, tyre = 1.8, lug = 1.0 },
			{ ctrl = { V2(-130, 46), V2(-40, 50), V2(40, 36), V2(130, 54) }, gauge = 4.6, tyre = 1.4, lug = 0.85 },
			{ ctrl = { V2(75, -75), V2(36, -30), V2(52, 22), V2(18, 95) }, gauge = 4.8, tyre = 1.5, lug = 0.9 },
			{ ctrl = { V2(-150, 88), V2(-50, 78), V2(30, 96), V2(150, 80) }, gauge = 4.6, tyre = 1.4, lug = 0.85 },
			{ ctrl = { V2(-160, 130), V2(-60, 118), V2(60, 140), V2(170, 124) }, gauge = 4.6, tyre = 1.4, lug = 0.85 },
			{ ctrl = { V2(-40, -80), V2(-30, -40), V2(-48, 10), V2(-90, 60) }, gauge = 4.6, tyre = 1.4, lug = 0.85 },
			{ ctrl = { V2(-170, -50), V2(-60, -40), V2(60, -52), V2(170, -38) }, gauge = 4.6, tyre = 1.4, lug = 0.85 },
		}
		local function clearZone(p)
			-- не класть рельеф прямо под стопы актёров (x -3..3, z≈0)
			return math.abs(p.X) < 4.8 and math.abs(p.Z) < 1.6
		end
		local function lugZone(p)
			-- видимая камерами у центра полоса: |z| < 34, по x — расширяющийся клин
			local az = math.abs(p.Z)
			return az < 34 and math.abs(p.X) < 10 + az * 0.95
		end
		for ti, tr in list do
			local pts = samplePath(tr.ctrl, 0.25)
			local top = 0.02 + ((ti - 1) % 3) * 0.02
			for side = -1, 1, 2 do
				-- колея: стыкующиеся отрезки (без перекрытий), короче вблизи
				local i = 1
				while i < #pts do
					local near = pts[i].Magnitude < 45
					local j = math.min(#pts, i + (if near then 24 else 56))
					local a, b = pts[i], pts[j]
					local dir = (b - a).Unit
					local n = V(-dir.Z, 0, dir.X)
					local mid = (a + b) / 2 + n * (side * tr.gauge / 2)
					local yaw = math.deg(math.atan2(-dir.X, -dir.Z))
					box(tracks, V(mid.X, top - 0.05, mid.Z), V(tr.tyre, 0.1, (b - a).Magnitude), mix(C.sandPacked, C.sand, if near then 0 else 0.35), "Sand", V(0, yaw, 0), NOSH)
					i = j
				end
				-- протектор: косые грунтозацепы
				local every = math.max(1, math.floor(tr.lug / 0.25 + 0.5))
				for k = 1, #pts - 1, every do
					local p = pts[k]
					local q = pts[k + 1]
					local dir = (q - p).Unit
					local n = V(-dir.Z, 0, dir.X)
					local c = p + n * (side * tr.gauge / 2)
					if lugZone(c) and not clearZone(c) then
						local yaw = math.deg(math.atan2(-dir.X, -dir.Z))
						box(tracks, V(c.X, top + 0.012, c.Z), V(tr.tyre * 0.92, 0.06, 0.26), C.tread, "Sand", V(0, yaw + side * 18, 0), NOSH)
					end
				end
			end
		end
		-- вмятины/следы ног: пары тёмных овалов (по видимым зонам)
		for _ = 1, 90 do
			local z = rr(-30, 34)
			local x = rr(-1, 1) * (8 + math.abs(z) * 0.9)
			local c = V(x, 0, z)
			if not clearZone(c) and c.Magnitude > 2.5 then
				local yaw = rr(0, 360)
				local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
				for s = -1, 1, 2 do
					local p = (cf * CFrame.new(s * 0.32, 0, s * rr(0.3, 0.7))).Position
					ell(tracks, V(p.X, 0.01, p.Z), V(0.48, 0.045, 0.95), mix(C.dent, C.tread, rr(0, 0.4)), "Sand", V(0, yaw + rr(-10, 10), 0), NOSH)
				end
			end
		end
		-- истоптанные пятна подальше (средний план)
		for _ = 1, 40 do
			local z = if rnd() < 0.7 then rr(36, 160) else rr(-140, -36)
			local x = rr(-1, 1) * (20 + math.abs(z) * 0.9)
			ell(tracks, V(x, 0.006, z), V(rr(3, 9), 0.03, rr(3, 9)), mix(C.sand, C.dent, rr(0.4, 0.9)), "Sand", V(0, rr(0, 180), 0), NOSH)
		end
		-- ракушки и камешки у зоны постановки
		for _ = 1, 30 do
			local z = rr(-16, 20)
			local x = rr(-1, 1) * (6 + math.abs(z) * 0.9)
			if not clearZone(V(x, 0, z)) then
				ell(tracks, V(x, 0.03, z), V(rr(0.12, 0.3), 0.08, rr(0.12, 0.25)), pick({ hex(0xF1ECE2), hex(0xE2D6C4), hex(0x8E8A84), hex(0xD9C7B0) }), "SmoothPlastic", V(0, rr(0, 180), 0), NOSH)
			end
		end
	end

	-- =====================================================================
	-- 4) Набережная: подпорная стенка, перила, фонари, флаги
	-- =====================================================================
	local blvd = folder("Boulevard")
	do
		-- подпорная стенка и парапет
		for i = 0, 2 do
			local cx = -1500 + i * 1000 + 500
			box(blvd, V(cx, 4.6, 301), V(1000, 3.4, 2.4), C.concrete, "Concrete", nil, NOSH)
			box(blvd, V(cx, 6.6, 301.6), V(1000, 1.0, 1.2), C.offWhite, "Concrete", nil, NOSH)
			box(blvd, V(cx, 7.7, 302.2), V(1000, 0.25, 0.25), C.lamp, "Metal", nil, NOSH)
		end
		-- фонари вдоль бульвара
		for x = -620, 620, 40 do
			local z = 306
			post(blvd, x, 6, z, 17, 0.55, C.lamp, "Metal", NOSH)
			box(blvd, V(x, 22.8, z - 1.4), V(0.35, 0.35, 3.0), C.lamp, "Metal", nil, NOSH)
			box(blvd, V(x, 22.5, z - 2.8), V(1.0, 0.45, 1.6), C.lamp, "Metal", nil, NOSH)
		end
	end

	-- =====================================================================
	-- 5) Город: жилые дома и отели вдоль бульвара (z ≈ +330 … +650)
	-- =====================================================================
	local city = folder("City")
	-- Жилой блок 70-х: тёмное зелёное стекло + горизонтальные балконные пояса + вертикальные пилоны.
	-- x — центр по X, zf — передняя грань (к морю, -Z), w/d/h — размеры, base — уровень земли (бульвар y=6).
	local function slabBlock(x, zf, w, d, h, opt)
		opt = opt or {}
		local base = opt.base or 6
		local fh = opt.fh or 8.6
		local core = opt.core or C.glassGreen
		local band = opt.band or C.offWhite
		local side = opt.side or C.beige
		local g = B:folder("Block", city)
		box(g, V(x, base + h / 2, zf + d / 2), V(w, h, d), side, "Concrete", nil, NOSH)
		box(g, V(x, base + h / 2, zf - 0.15), V(w - 1.2, h - 1, 0.3), core, "Glass", nil, { castShadow = false, reflectance = opt.refl or 0.12 })
		local floors = math.floor(h / fh)
		for f = 1, floors do
			local y = base + f * fh - 0.7
			if y < base + h - 1.5 then
				box(g, V(x, y, zf - 1.0), V(w + 0.3, opt.bandH or 1.5, 2.0), band, "Concrete", nil, NOSH)
			end
		end
		local bays = opt.bays or math.max(2, math.floor(w / 14))
		for i = 0, bays do
			local px = x - w / 2 + 0.6 + i * (w - 1.2) / bays
			box(g, V(px, base + h / 2, zf - 1.15), V(opt.pierW or 1.1, h, 2.3), opt.pier or band, "Concrete", nil, NOSH)
		end
		-- окна на торцах
		for s = -1, 1, 2 do
			box(g, V(x + s * (w / 2 + 0.1), base + h / 2, zf + d * 0.35), V(0.3, h - 4, 2.2), core, "Glass", nil, NOSH)
		end
		box(g, V(x, base + h + 0.5, zf + d / 2), V(w + 0.6, 1.0, d + 0.6), opt.roof or C.offWhite, "Concrete", nil, NOSH)
		box(g, V(x + rr(-w * 0.25, w * 0.25), base + h + 3, zf + d * 0.5), V(rr(7, 11), 5, rr(7, 10)), C.offWhite, "Concrete", nil, NOSH)
		if opt.step then
			-- пониженное крыло сбоку
			local sw, sh, sd = opt.step[1], opt.step[2], opt.step[3]
			local sx = x + opt.step[4] * (w / 2 + sw / 2 - 0.5)
			box(g, V(sx, base + sh / 2, zf + 4 + sd / 2), V(sw, sh, sd), side, "Concrete", nil, NOSH)
			box(g, V(sx, base + sh / 2, zf + 3.85), V(sw - 1, sh - 1, 0.3), core, "Glass", nil, NOSH)
			for f = 1, math.floor(sh / fh) do
				box(g, V(sx, base + f * fh - 0.7, zf + 3), V(sw + 0.2, 1.4, 1.8), band, "Concrete", nil, NOSH)
			end
			box(g, V(sx, base + sh + 0.5, zf + 4 + sd / 2), V(sw + 0.4, 1.0, sd + 0.4), C.offWhite, "Concrete", nil, NOSH)
		end
		if opt.antenna then
			post(g, x + w * 0.3, base + h + 1, zf + d * 0.4, 14, 0.35, C.grey, "Metal", NOSH)
		end
		return g
	end
	-- Белая башня-пластина: сетка вертикальных окон и межэтажных поясов.
	local function tower(x, zf, w, d, h, opt)
		opt = opt or {}
		local base = opt.base or 6
		local fh = opt.fh or 8.6
		local col = opt.color or C.white
		local g = B:folder("Tower", city)
		box(g, V(x, base + h / 2, zf + d / 2), V(w, h, d), col, "Concrete", nil, NOSH)
		local cols = opt.cols or math.floor(w / 4.5)
		for i = 0, cols - 1 do
			local px = x - w / 2 + (i + 0.5) * w / cols
			box(g, V(px, base + h / 2 + 1, zf - 0.1), V(w / cols * 0.5, h - 6, 0.3), opt.glass or C.glassDark, "Glass", nil, { castShadow = false, reflectance = 0.15 })
		end
		local floors = math.floor((h - 4) / fh)
		for f = 1, floors do
			box(g, V(x, base + 2 + f * fh, zf - 0.3), V(w - 0.2, 0.9, 0.5), col, "Concrete", nil, NOSH)
		end
		-- торцевые окна
		box(g, V(x - w / 2 - 0.1, base + h / 2, zf + d / 2), V(0.3, h - 6, d * 0.3), opt.glass or C.glassDark, "Glass", nil, NOSH)
		box(g, V(x + w / 2 + 0.1, base + h / 2, zf + d / 2), V(0.3, h - 6, d * 0.3), opt.glass or C.glassDark, "Glass", nil, NOSH)
		box(g, V(x, base + h + 0.6, zf + d / 2), V(w + 0.8, 1.2, d + 0.8), col, "Concrete", nil, NOSH)
		box(g, V(x, base + h + 3.5, zf + d / 2), V(w * 0.5, 5, d * 0.5), C.offWhite, "Concrete", nil, NOSH)
		return g
	end
	-- Стеклянный корпус с сеткой импостов.
	local function glassBox(x, zf, w, d, h, opt)
		opt = opt or {}
		local base = opt.base or 6
		local g = B:folder("Glass", city)
		box(g, V(x, base + h / 2, zf + d / 2), V(w, h, d), opt.glass or C.glassTeal, "Glass", nil, { castShadow = false, reflectance = 0.15 })
		local nx = math.max(2, math.floor(w / 6))
		for i = 1, nx - 1 do
			box(g, V(x - w / 2 + i * w / nx, base + h / 2, zf - 0.15), V(0.35, h, 0.3), opt.mullion or C.offWhite, "Metal", nil, NOSH)
		end
		local ny = math.max(2, math.floor(h / (opt.fh or 8)))
		for f = 1, ny - 1 do
			box(g, V(x, base + f * h / ny, zf - 0.2), V(w + 0.1, 0.6, 0.4), opt.mullion or C.offWhite, "Metal", nil, NOSH)
		end
		box(g, V(x, base + h + 0.5, zf + d / 2), V(w + 0.6, 1.0, d + 0.6), opt.roof or C.white, "Concrete", nil, NOSH)
		return g
	end
	-- Простой дальний объём с полосами окон
	local function farBlock(x, zf, w, d, h, color, glass)
		local g = B:folder("Far", city)
		box(g, V(x, 6 + h / 2, zf + d / 2), V(w, h, d), color, "Concrete", nil, NOSH)
		if glass then
			local floors = math.max(1, math.floor(h / 9))
			for f = 1, floors do
				box(g, V(x, 6 + (f - 0.5) * h / floors, zf - 0.2), V(w - 1, h / floors * 0.42, 0.4), glass, "Glass", nil, NOSH)
			end
		end
		return g
	end

	-- Справа в кадре при взгляде на город (x < 0): высокие жилые блоки
	glassBox(-64, 392, 40, 26, 68, { glass = hex(0x3D5A55), mullion = hex(0xD8D6CE) })
	tower(-99, 396, 27, 22, 94, { cols = 6 })
	slabBlock(-150, 412, 62, 28, 46, { core = hex(0x3A4D4B), band = hex(0xD9D5CA), bays = 4 })
	slabBlock(-245, 424, 104, 30, 70, { core = hex(0x3B514D), band = hex(0xE0DCD2), bays = 7, step = { 40, 44, 26, -1 }, antenna = true })
	slabBlock(-372, 446, 104, 30, 60, { core = hex(0x44575A), band = hex(0xD6D0C3), bays = 7 })
	tower(-462, 432, 28, 24, 86, { cols = 6, color = hex(0xE2DDD3) })
	slabBlock(-560, 456, 118, 30, 54, { core = hex(0x47595B), band = hex(0xE3DED4), bays = 8, step = { 36, 34, 26, -1 } })
	slabBlock(-740, 470, 130, 30, 46, { core = hex(0x4F6061), band = hex(0xDAD4C8), bays = 8 })
	slabBlock(-900, 482, 140, 30, 40, { core = hex(0x56676A), band = hex(0xDDD7CB), bays = 8 })
	-- центр: тёмный корпус с белым карнизом, зелёный стеклянный корпус, белая мачта
	local dark = B:folder("Dark", city)
	box(dark, V(-14, 6 + 13, 352 + 13), V(40, 26, 26), hex(0x34414A), "Concrete", nil, NOSH)
	box(dark, V(-14, 6 + 26.6, 352 + 13), V(42, 1.4, 28), C.white, "Concrete", nil, NOSH)
	for f = 1, 2 do
		box(dark, V(-14, 6 + f * 8.6, 351.8), V(40.4, 0.8, 0.6), C.offWhite, "Concrete", nil, NOSH)
	end
	glassBox(26, 398, 36, 26, 40, { glass = hex(0x2F4C46), mullion = hex(0x9FB0AA) })
	post(city, 40, 6, 318, 40, 0.6, C.white, "Metal", NOSH)
	box(city, V(41.8, 43, 318), V(3.4, 2.2, 0.06), C.nlBlue, "Fabric", nil, NOSH)
	-- слева (x > 0): низко, отели и Курхаус
	slabBlock(78, 420, 48, 26, 30, { core = hex(0x56676B), band = C.beige, side = C.sandstone, bays = 3 })
	do
		-- «Курхаус»: длинный бежевый корпус, купол и угловые павильоны
		local g = B:folder("Kurhaus", city)
		local kx, kz = 232, 432
		box(g, V(kx, 6 + 11, kz + 15), V(120, 22, 30), hex(0xD9C9AC), "Concrete", nil, NOSH)
		for f = 1, 3 do
			box(g, V(kx, 6 + f * 6.2 - 2, kz - 0.15), V(116, 2.4, 0.4), hex(0x4F5B60), "Glass", nil, NOSH)
		end
		wedge(g, V(kx, 6 + 24.5, kz + 7.5), V(120, 5, 15), hex(0x5B6466), "Slate", V(0, 180, 0), NOSH)
		wedge(g, V(kx, 6 + 24.5, kz + 22.5), V(120, 5, 15), hex(0x5B6466), "Slate", nil, NOSH)
		B:cyl(V(kx, 6 + 28, kz + 15), 10, 22, hex(0xD9C9AC), "Concrete", "Y", nil, { parent = g, castShadow = false })
		ell(g, V(kx, 6 + 33, kz + 15), V(24, 20, 24), hex(0x55625F), "Slate", nil, NOSH)
		post(g, kx, 6 + 42, kz + 15, 8, 1.2, hex(0x55625F), "Slate", NOSH)
		for s = -1, 1, 2 do
			box(g, V(kx + s * 56, 6 + 14, kz + 15), V(14, 28, 32), hex(0xDCCDB2), "Concrete", nil, NOSH)
			ell(g, V(kx + s * 56, 6 + 28, kz + 15), V(12, 10, 12), hex(0x55625F), "Slate", nil, NOSH)
		end
	end
	slabBlock(345, 446, 82, 28, 26, { core = hex(0x5E6E70), band = hex(0xE6E1D6), bays = 5 })
	farBlock(450, 460, 70, 30, 22, hex(0xCFC6B6), hex(0x5E6E72))
	farBlock(540, 470, 60, 30, 18, hex(0xD8D0C2), hex(0x60707A))
	farBlock(640, 480, 80, 30, 20, hex(0xBFB8AC), hex(0x5A6A70))
	farBlock(760, 490, 90, 30, 16, hex(0xD3CBBE), hex(0x5E6C70))
	-- нижний ряд у бульвара: кафе, отели, киоски
	for i = 0, 15 do
		local x = -520 + i * 62 + rr(-8, 8)
		if math.abs(x - 100) > 50 then
			local h = rr(8, 15)
			local w = rr(26, 44)
			local g = B:folder("Low", city)
			local col = pick({ C.white, hex(0xE9E4D8), hex(0x6E8C9E), hex(0xCFC2A8), hex(0x4C6274) })
			box(g, V(x, 6 + h / 2, 330 + 9), V(w, h, 18), col, "Concrete", nil, NOSH)
			box(g, V(x, 6 + h * 0.45, 329.85), V(w - 2, h * 0.5, 0.3), hex(0x5A707A), "Glass", nil, NOSH)
			wedge(g, V(x, 6 + h * 0.78, 328.6), V(w - 1, 1.2, 2.4), pick({ C.clubBlue, C.white, C.red, hex(0x2E6B4A) }), "Fabric", nil, NOSH)
		end
	end
	-- второй ряд и дальний город (сильная дымка)
	for i = 0, 24 do
		local x = -1000 + i * 85 + rr(-20, 20)
		local h = rr(30, 80) * (1 - math.abs(x) / 1700)
		farBlock(x, rr(580, 740), rr(40, 80), 40, math.max(16, h), pick({ hex(0xC9C2B6), hex(0xB7B4AE), hex(0xD6CFC2), hex(0x9EA6A6) }), nil)
	end
	-- высотки центра Гааги далеко за горизонтом
	for _, t in { { -420, 1700, 34, 150 }, { -330, 1900, 28, 175 }, { -250, 1650, 40, 120 }, { -560, 2000, 30, 135 }, { 120, 2100, 30, 110 } } do
		box(city, V(t[1], 6 + t[4] / 2, t[2]), V(t[3], t[4], t[3]), hex(0xAEB8BE), "Concrete", nil, NOSH)
	end

	-- =====================================================================
	-- 6) Белый павильон-«шатёр» на пляже
	-- =====================================================================
	local pav = folder("Pavilion")
	do
		local cx, cz = 100, 262
		local W, D = 74, 40
		-- настил на сваях
		box(pav, V(cx, 1.4, cz), V(W + 6, 1.0, D + 4), C.offWhite, "Concrete")
		for i = -3, 3 do
			post(pav, cx + i * 11.5, -1, cz - D / 2 - 1, 2.4, 0.8, C.grey, "Concrete", NOSH)
		end
		-- остеклённый первый этаж
		box(pav, V(cx, 4.7, cz + 2), V(W - 6, 5.6, D - 8), hex(0x5E7A86), "Glass", nil, { reflectance = 0.25 })
		-- белые колонны по фасаду
		for i = 0, 9 do
			post(pav, cx - W / 2 + 2 + i * (W - 4) / 9, 1.9, cz - D / 2 + 2.5, 6.2, 0.5, C.white, "SmoothPlastic", NOSH)
		end
		-- плоский свес крыши
		box(pav, V(cx, 8.4, cz), V(W + 2, 0.7, D + 2), C.white, "SmoothPlastic")
		-- мембранная кровля: ряд белых «шатров» (пики растут к -X, как в кадре S03)
		local peaks = { { 30, 3.6 }, { 15, 5.2 }, { 0, 6.6 }, { -15, 8.4 }, { -30, 10.2 } }
		for _, pk in peaks do
			local x0, h = cx + pk[1], pk[2]
			local hw = 7.4
			-- левая и правая половины: клинья, сходящиеся к гребню вдоль Z
			wedge(pav, V(x0 - hw / 2, 8.75 + h / 2, cz), V(D - 2, h, hw), hex(0xF5F4F0), "Fabric", V(0, 90, 0))
			wedge(pav, V(x0 + hw / 2, 8.75 + h / 2, cz), V(D - 2, h, hw), hex(0xEDEBE6), "Fabric", V(0, -90, 0))
			-- мачта над пиком
			post(pav, x0, 8.75 + h - 0.5, cz, 5, 0.3, C.white, "Metal", NOSH)
		end
		-- флажки на крайних мачтах
		box(pav, V(cx - 30 + 1.4, 8.75 + 10.2 + 3.7, cz), V(2.6, 1.5, 0.06), C.clubBlue, "Fabric", nil, NOSH)
		box(pav, V(cx + 1.4, 8.75 + 6.6 + 3.7, cz), V(2.6, 1.5, 0.06), C.yellow, "Fabric", nil, NOSH)
		-- круглый навес-«тарелка» на западном краю
		B:cyl(V(cx - W / 2 - 9, 7.6, cz - 4), 0.8, 20, C.white, "SmoothPlastic", "Y", nil, { parent = pav })
		post(pav, cx - W / 2 - 9, 1.9, cz - 4, 5.4, 0.7, C.white, "SmoothPlastic", NOSH)
	end

	-- =====================================================================
	-- 7) Пляжные клубы (сине-бирюзовые павильоны на деревянных помостах), зонты, ветрозащиты
	-- =====================================================================
	local clubs = folder("BeachClubs")
	local function club(x, z, w, wallColor, accent, flags)
		local g = B:folder("Club", clubs)
		local d = 22
		box(g, V(x, 1.5, z), V(w + 8, 0.8, d + 8), C.wood, "WoodPlanks")
		for i = -1, 1, 2 do
			post(g, x + i * (w / 2 + 3), -1, z - d / 2 - 3.5, 2.2, 0.6, C.woodDark, "Wood", NOSH)
		end
		box(g, V(x, 5.4, z + 3), V(w, 7, d - 6), wallColor, "SmoothPlastic")
		-- остеклённая веранда
		box(g, V(x, 4.2, z - d / 2 + 4), V(w - 0.8, 4.6, 0.25), hex(0x9DB8C4), "Glass", nil, { transparency = 0.35, reflectance = 0.2 })
		-- крыша с козырьком
		box(g, V(x, 9.2, z + 1), V(w + 3, 0.8, d), C.white, "SmoothPlastic")
		-- маркиза
		wedge(g, V(x, 7.6, z - d / 2 - 0.5), V(w, 1.6, 4), accent, "Fabric", V(0, 0, 0), NOSH)
		-- ветрозащитные стёкла по краю помоста
		box(g, V(x, 2.8, z - d / 2 - 3.6), V(w + 7, 1.8, 0.2), hex(0xB8CCD4), "Glass", nil, { transparency = 0.5 })
		-- флагштоки
		for k = 1, flags do
			local fx = x - w / 2 + k * w / (flags + 1)
			post(g, fx, 9.6, z - d / 2 + 1, 12, 0.25, C.white, "Metal", NOSH)
			box(g, V(fx + 1.5, 20.4, z - d / 2 + 1), V(3, 2, 0.06), pick({ C.clubBlue, C.yellow, C.nlRed, C.white, C.orange }), "Fabric", nil, NOSH)
		end
		return g
	end
	club(-30, 250, 34, C.clubBlue, C.white, 2)
	club(18, 246, 26, C.white, C.clubTeal, 1)
	club(-78, 255, 30, C.clubTeal, C.white, 2)
	club(-125, 250, 28, C.white, C.clubBlue, 1)
	club(-175, 258, 32, C.clubNavy, C.white, 2)
	club(170, 250, 30, C.clubBlue, C.white, 1)
	club(225, 256, 26, C.white, C.clubBlue, 2)
	club(-235, 255, 30, C.clubBlue, C.white, 1)
	club(-290, 262, 26, C.white, C.clubTeal, 1)
	-- дальние павильоны (упрощённые)
	for i = 0, 11 do
		local x = 290 + i * 55 + rr(-10, 10)
		local g = B:folder("ClubFar", clubs)
		box(g, V(x, 4.5, 262), V(rr(18, 28), 7, 14), pick({ C.white, C.clubBlue, C.clubTeal, C.offWhite }), "SmoothPlastic", nil, NOSH)
		box(g, V(x, 8.4, 262), V(30, 0.8, 18), C.white, "SmoothPlastic", nil, NOSH)
		local x2 = -350 - i * 60 + rr(-10, 10)
		box(g, V(x2, 4.5, 266), V(rr(18, 28), 7, 14), pick({ C.white, C.clubBlue, C.offWhite, C.clubNavy }), "SmoothPlastic", nil, NOSH)
		box(g, V(x2, 8.4, 266), V(30, 0.8, 18), C.white, "SmoothPlastic", nil, NOSH)
	end
	-- зонты перед клубами
	local props = folder("BeachProps")
	local function umbrella(x, z, color)
		post(props, x, 0, z, 6.6, 0.18, C.white, "Metal", NOSH)
		ell(props, V(x, 6.4, z), V(6.5, 1.5, 6.5), color, "Fabric")
	end
	for i = 0, 15 do
		local x = -200 + i * 22 + rr(-4, 4)
		umbrella(x, 218 + rr(-6, 6), pick({ C.white, C.white, C.clubBlue, hex(0xF0EEE8), C.yellow }))
	end
	-- шезлонги
	for i = 0, 13 do
		local x = -190 + i * 24 + rr(-4, 4)
		local z = 212 + rr(-4, 4)
		wedge(props, V(x, 0.7, z), V(1.8, 1.4, 4.5), pick({ C.white, C.clubBlue, hex(0xD9D2C0) }), "Fabric", V(0, 180, 0), NOSH)
	end

	-- =====================================================================
	-- 8) Пирс (Pier Scheveningen): от берега у x=+160 в море до z≈-700
	-- =====================================================================
	local pier = folder("Pier")
	do
		local px = 160
		local z0, z1 = -40, -600 -- основной настил
		local L = z0 - z1
		local zc = (z0 + z1) / 2
		local gy0, gy1 = 7, 11.5 -- закрытая нижняя галерея
		local half = 6.5
		-- галерея: низ, верхний настил, остекление по бокам, тёмно-бирюзовые фасции
		box(pier, V(px, gy0 + 0.4, zc), V(2 * half, 0.8, L), C.pierTeal, "Metal")
		box(pier, V(px, gy1 + 0.5, zc), V(2 * half + 2, 1.0, L), C.pierTeal, "Metal")
		for s = -1, 1, 2 do
			box(pier, V(px + s * (half - 0.2), (gy0 + gy1) / 2 + 0.4, zc), V(0.3, gy1 - gy0 - 0.8, L), hex(0x88A2A8), "Glass", nil, { reflectance = 0.3 })
			box(pier, V(px + s * (half + 0.5), gy1 + 0.5, zc), V(1.0, 1.6, L), hex(0x3A5652), "Metal", nil, NOSH)
			box(pier, V(px + s * (half + 0.4), gy0 + 0.2, zc), V(0.8, 1.2, L), hex(0x3A5652), "Metal", nil, NOSH)
			-- перила верхней палубы
			box(pier, V(px + s * (half + 0.8), gy1 + 2.9, zc), V(0.25, 0.25, L), C.white, "Metal", nil, NOSH)
			box(pier, V(px + s * (half + 0.8), gy1 + 2.0, zc), V(0.08, 1.6, L), hex(0xA8BCC2), "Glass", nil, { transparency = 0.55, castShadow = false })
		end
		-- опоры: пары ног + распорки, каждые 20 студов
		local zz = z0 - 6
		while zz > z1 - 70 do
			for s = -1, 1, 2 do
				post(pier, px + s * (half - 1), -7, zz, gy0 + 7, 1.2, C.pierLeg, "Metal")
				-- стойки остекления галереи над опорой
				box(pier, V(px + s * (half - 0.05), (gy0 + gy1) / 2 + 0.4, zz), V(0.45, gy1 - gy0, 0.5), C.pierTeal, "Metal", nil, NOSH)
			end
			box(pier, V(px, gy0 - 0.6, zz), V(2 * half, 0.8, 0.8), C.pierLeg, "Metal", nil, NOSH)
			beam(pier, V(px - half + 1, -0.5, zz), V(px + half - 1, gy0 - 1, zz), 0.35, 0.35, C.pierLeg, "Metal", NOSH)
			zz -= 20
		end
		-- вход на пляже: лестничная башня и пандус
		box(pier, V(px, 6.5, z0 + 6), V(16, 13, 12), C.pierTeal, "Metal")
		box(pier, V(px, 13.2, z0 + 6), V(17, 0.6, 13), C.white, "Metal")
		box(pier, V(px - 8.2, 6.5, z0 + 6), V(0.3, 10, 9), hex(0x88A2A8), "Glass", nil, { reflectance = 0.3 })
		-- первый «остров» с колесом обозрения
		local iz = -230
		box(pier, V(px + 14, gy1 + 0.5, iz), V(30, 1.0, 40), C.pierTeal, "Metal")
		for _, o in { { 8, -16 }, { 26, -16 }, { 8, 16 }, { 26, 16 } } do
			post(pier, px + o[1], -7, iz + o[2], gy1 + 7, 1.4, C.pierLeg, "Metal")
		end
		-- голова пирса: платформа и павильоны
		local hz = z1 - 40
		box(pier, V(px, gy1 + 0.5, hz), V(64, 1.0, 80), C.pierTeal, "Metal")
		box(pier, V(px, gy0 + 0.4, hz), V(60, 0.8, 76), C.pierTeal, "Metal", nil, NOSH)
		for ox = -26, 26, 13 do
			for oz = -34, 34, 17 do
				post(pier, px + ox, -7, hz + oz, gy0 + 7, 1.3, C.pierLeg, "Metal")
			end
		end
		box(pier, V(px - 6, gy1 + 5, hz - 4), V(40, 8, 34), hex(0x5D7A84), "Glass", nil, { reflectance = 0.3 })
		box(pier, V(px - 6, gy1 + 9.3, hz - 4), V(43, 0.8, 37), C.white, "Metal")
		box(pier, V(px + 18, gy1 + 4, hz + 22), V(18, 6, 16), C.white, "SmoothPlastic")
		-- смотровая башня
		post(pier, px + 20, gy1 + 1, hz - 22, 40, 3.2, C.white, "Metal")
		box(pier, V(px + 20, gy1 + 42, hz - 22), V(9, 4, 9), hex(0x5D7A84), "Glass", nil, { reflectance = 0.3 })
		box(pier, V(px + 20, gy1 + 44.4, hz - 22), V(10, 0.8, 10), C.white, "Metal")
		post(pier, px + 20, gy1 + 44.8, hz - 22, 8, 0.3, C.grey, "Metal", NOSH)
	end

	-- Колесо обозрения на первом острове пирса (ось вдоль X — видно «кругом» с пляжа)
	local wheel = folder("FerrisWheel")
	do
		local hub = V(185, 40, -230)
		local R = 26
		local nSeg = 28
		for s = -1, 1, 2 do
			local x = hub.X + s * 1.2
			for i = 0, nSeg - 1 do
				local a0 = (i / nSeg) * math.pi * 2
				local a1 = ((i + 1) / nSeg) * math.pi * 2
				local p0 = V(x, hub.Y + R * math.cos(a0), hub.Z + R * math.sin(a0))
				local p1 = V(x, hub.Y + R * math.cos(a1), hub.Z + R * math.sin(a1))
				beam(wheel, p0, p1, 0.5, 0.5, C.white, "Metal", NOSH)
			end
		end
		for i = 0, 13 do
			local a = (i / 14) * math.pi * 2
			local p = V(hub.X, hub.Y + R * math.cos(a), hub.Z + R * math.sin(a))
			beam(wheel, V(hub.X, hub.Y, hub.Z), p, 0.22, 0.22, C.white, "Metal", NOSH)
		end
		B:cyl(hub, 3.4, 2.2, C.grey, "Metal", "X", nil, { parent = wheel })
		-- опорные ноги (А-образные)
		for s = -1, 1, 2 do
			beam(wheel, V(hub.X + s * 2, 12, hub.Z - 16), V(hub.X + s * 1.5, hub.Y, hub.Z), 1.0, 1.0, C.white, "Metal")
			beam(wheel, V(hub.X + s * 2, 12, hub.Z + 16), V(hub.X + s * 1.5, hub.Y, hub.Z), 1.0, 1.0, C.white, "Metal")
		end
		-- кабинки
		for i = 0, 13 do
			local a = (i / 14) * math.pi * 2 + 0.11
			local p = V(hub.X, hub.Y + R * math.cos(a) - 1.8, hub.Z + R * math.sin(a))
			box(wheel, p, V(2.6, 2.8, 2.6), pick({ hex(0xD8E4EA), hex(0xB8CCD8) }), "Glass", nil, { reflectance = 0.2, castShadow = false })
		end
	end

	-- =====================================================================
	-- 9) Гавань далеко на западе (видна при взгляде на море слева)
	-- =====================================================================
	local harbor = folder("Harbor")
	do
		for i = 0, 7 do
			local x = -1350 - i * 110 + rr(-20, 20)
			local h = rr(12, 30)
			box(harbor, V(x, h / 2, rr(-40, 40)), V(rr(40, 80), h, rr(30, 50)), pick({ hex(0x41575A), hex(0x5E6E6E), hex(0x8C918C), hex(0xC9C3B6) }), "Concrete", nil, NOSH)
		end
		-- волнорезы
		box(harbor, V(-1500, 1.0, -260), V(14, 4, 240), hex(0x6F6E68), "Rock", V(0, 18, 0), NOSH)
		box(harbor, V(-1700, 1.0, -250), V(14, 4, 230), hex(0x6F6E68), "Rock", V(0, -12, 0), NOSH)
		post(harbor, -1460, 2, -370, 16, 3, C.nlRed, "SmoothPlastic", NOSH)
		post(harbor, -1740, 2, -360, 16, 3, hex(0x2F7A3A), "SmoothPlastic", NOSH)
		-- краны
		for _, x in { -1600, -1880 } do
			post(harbor, x, 0, 30, 46, 1.6, hex(0x6F7B80), "Metal", NOSH)
			box(harbor, V(x + 10, 46, 30), V(36, 2, 2), hex(0x6F7B80), "Metal", nil, NOSH)
		end
	end

	-- =====================================================================
	-- 10) Люди вдали (маленькие фигурки)
	-- =====================================================================
	local people = folder("People")
	local skin = { hex(0xE3B999), hex(0xC99572), hex(0x8D5B3E), hex(0xF0CCB0) }
	local cloth = { C.white, hex(0x2C3E66), hex(0xD24B3E), hex(0x1E1E22), hex(0x5E8FB8), hex(0xE9C34A), hex(0x6B8E5A) }
	local function person(x, z, pose, yaw)
		local g = B:folder("Person", people)
		local sk, top, bottom = pick(skin), pick(cloth), pick({ hex(0x2B3240), hex(0x3B5B8A), hex(0xC9B9A0), hex(0x1E1E22) })
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
		local function at(dx, dy, dz)
			return (cf * CFrame.new(dx, dy, dz)).Position
		end
		if pose == "sit" then
			box(g, at(0, 0.5, 0.8), V(1.0, 0.9, 2.2), bottom, "Fabric", V(0, yaw or 0, 0), NOSH)
			box(g, at(0, 1.9, 0), V(1.2, 2.0, 0.7), top, "Fabric", V(0, yaw or 0, 0), NOSH)
			B:ball(at(0, 3.4, 0), 0.95, sk, "SmoothPlastic", { parent = g, castShadow = false })
		elseif pose == "lie" then
			box(g, at(0, 0.3, 0), V(1.2, 0.55, 4.6), top, "Fabric", V(0, yaw or 0, 0), NOSH)
			B:ball(at(0, 0.45, -2.8), 0.9, sk, "SmoothPlastic", { parent = g, castShadow = false })
			box(g, at(0, 0.06, 0), V(2.4, 0.08, 6.4), pick({ C.yellow, C.clubBlue, C.red, C.white }), "Fabric", V(0, yaw or 0, 0), NOSH)
		else
			box(g, at(0, 1.3, 0), V(1.0, 2.6, 0.6), bottom, "Fabric", nil, NOSH)
			box(g, at(0, 3.5, 0), V(1.3, 2.0, 0.7), top, "Fabric", V(0, yaw or 0, 0), NOSH)
			B:ball(at(0, 5.0, 0), 0.95, sk, "SmoothPlastic", { parent = g, castShadow = false })
		end
	end
	-- дальний план за актёрами (вид на город)
	for _ = 1, 30 do
		local x, z = rr(-330, 330), rr(70, 230)
		person(x, z, pick({ "stand", "stand", "stand", "sit", "lie" }), rr(0, 360))
	end
	-- пара, сидящая на песке ближе (как в S03)
	person(46, 62, "sit", 200)
	person(48.4, 62.5, "sit", 160)
	-- у кромки воды (вид на море)
	for _ = 1, 16 do
		local x, z = rr(-260, 300), rr(-158, -100)
		person(x, z, pick({ "stand", "stand", "sit" }), rr(0, 360))
	end

	-- =====================================================================
	-- 11) Чайки
	-- =====================================================================
	local birds = folder("Gulls")
	for _ = 1, 6 do
		local p = V(rr(-120, 120), rr(28, 60), rr(60, 160))
		local yaw = rr(0, 360)
		for s = -1, 1, 2 do
			local cf = CFrame.new(p) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(s * 0.9, 0, 0) * CFrame.Angles(0, 0, math.rad(s * 18))
			B:part({ cf = cf, size = V(1.8, 0.12, 0.5), color = C.white, material = "SmoothPlastic", parent = birds, castShadow = false })
		end
	end

	-- Пожелание цвета материалов Terrain (Terrain:SetMaterialColor) для координатора.
	root:SetAttribute("TerrainColor_Sand", C.sand)
	root:SetAttribute("TerrainColor_Pavement", hex(0xB9B5AC))
end
