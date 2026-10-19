--!nocheck
-- Декорация «Beach»: пляж Схевенинген (Нидерланды). Координаты — локальные (Y=0 — верх песка).
-- Если камера смотрит на город (+Z), то +X — СЛЕВА в кадре; если на море (-Z) — +X справа.
--
-- Что где (для постановки планов):
--   * Зона постановки: в радиусе ~25 студов от (0,0,0) только плоские следы шин, вмятины и ракушки
--     (высота < 0.08); под стопами актёров (|x|<4.8, |z|<1.6) рельефа нет.
--   * Песок (Terrain Sand) y=0 при z -160 … +270, x ±3000; к z=+300 подъём до y=4.5; бульвар (Pavement) y=6, z +300 … +760.
--   * Море (Terrain Water) при z < -160, уровень -0.6, до z=-3600; мокрая полоса z -160 … ~-120; пена у кромки.
--   * Город: z +330 … +740 (высотки справа в кадре на город, x -60 … -900, высота до ~100); «Курхаус» (232, 432);
--     белый павильон с крышей-волной (100, 246), пляжные клубы z≈237…244, зонты/шезлонги z≈200…210.
--   * Пирс: ось x=160, от z=-40 (вход на пляже) до z=-600 + голова до z≈-640; пол галереи y≈10.5, верхняя палуба y≈16.5;
--     колесо обозрения: ось (185, 46, -230), R=26; смотровая башня на конце (180, ~17…62, -662).
--   * Слева при взгляде на море: спасательная вышка (-70, 0, -112), молы гавани с маяками x≈-420…-540 до z≈-650.
--   * Цвет Terrain-песка задаёт скрипт BeachTerrainColors (атрибуты TerrainColor_* модели) — детали-песок подобраны под него.

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
	sand = hex(0xC9B28A),
	sandPacked = hex(0xBDA580),
	tread = hex(0x998062),
	dent = hex(0xAD9673),
	wet = hex(0x9E896A),
	wetter = hex(0x89775F),
	foam = hex(0xF2F4F3),
	white = hex(0xE8E5DE),
	offWhite = hex(0xD9D4C9),
	beige = hex(0xD3C3A6),
	sandstone = hex(0xC9B08C),
	concrete = hex(0xA9A7A0),
	grey = hex(0x8E918F),
	glassGreen = hex(0x3C5552),
	glassTeal = hex(0x4E6D70),
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
	-- Порядок важен: позже залитое перекрывает раньше залитое. Воксели Terrain — 4 студа, поэтому
	-- граница вода/песок выровнена по сетке: в воксель не попадают два материала (иначе вода пропадает).
	-- Объём terrain по границам; режется на куски ≤ 2000 студов (у Part максимум 2048 по оси);
	-- границы кусков кратны 4 (сетка вокселей), иначе на стыках остаются бороздки.
	local function tblock(x0, x1, y0, y1, z0, z1, material)
		local nx = math.ceil((x1 - x0) / 2000)
		local nz = math.ceil((z1 - z0) / 2000)
		for i = 0, nx - 1 do
			local a0, a1 = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
			for j = 0, nz - 1 do
				local b0, b1 = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
				B:terrain("Block", V((a0 + a1) / 2, (y0 + y1) / 2, (b0 + b1) / 2), V(a1 - a0, y1 - y0, b1 - b0), material)
			end
		end
	end
	tblock(-3000, 3000, -12, -0.6, -3600, -160, "Water") -- море до горизонта, уровень -0.6
	tblock(-3000, 3000, -12, -4, -240, -160, "Sand") -- мелководье: дно y=-4
	tblock(-3000, 3000, -12, -8, -400, -240, "Sand") -- дно y=-8
	tblock(-3000, 3000, -16, -12, -3600, -400, "Sand") -- дно y=-12
	tblock(-3000, 3000, -8, 0, -160, 300, "Sand") -- пляж: верх y=0, z -160 … +300
	-- насыпь к бульвару: от y=0 (z=+270) до y=+4.5 (z=+300); всё на пляже стоит при z < 268 на ровном песке y=0
	for i = 0, 2 do
		B:terrain("Wedge", V(-2000 + i * 2000, 2.25, 285), V(2000, 4.5, 30), "Sand")
	end
	-- бульвар (набережная) y=+6, z +300 … +760
	tblock(-3000, 3000, -4, 6, 300, 760, "Pavement")
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
		-- у самой воды — очень мокрый блестящий песок (z -160 … -150)
		for i = 0, 5 do
			local w = 600
			box(shore, V(-1800 + i * w + w / 2, 0.02 - 0.1, -154.25), V(w, 0.2, 8.5), C.wetter, "Sand", nil, { castShadow = false, reflectance = 0.1 })
		end
		-- мокрая полоса неровной ширины (куски стыкуются без перекрытий)
		local x = -1800
		while x < 1800 do
			local w = rr(120, 240)
			local depth = rr(14, 36)
			box(shore, V(x + w / 2, 0.035 - 0.1, -150 + depth / 2), V(w, 0.2, depth), mix(C.wet, C.sand, rr(0.05, 0.3)), "Sand", nil, NOSH)
			x += w
		end
		-- пена у кромки: рваная полоса из коротких изогнутых кусков
		for line = 1, 2 do
			local xx = -1400
			while xx < 1400 do
				local len = rr(30, 95)
				local zc = (if line == 1 then -161.3 else -165.5) + math.sin(xx * 0.013) * 0.6 + rr(-0.3, 0.3)
				if line == 1 or rnd() > 0.45 then
					box(shore, V(xx + len / 2, -0.5 + line * 0.015, zc), V(len, 0.06, rr(0.7, 1.9) / line), C.foam, "SmoothPlastic", V(0, rr(-3, 3), 0), { castShadow = false, transparency = if line == 1 then rr(0.1, 0.3) else rr(0.45, 0.65) })
				end
				xx += len + rr(1, if line == 1 then 8 else 30)
			end
		end
		-- барашки дальше в море (короткие, редкие)
		for _ = 1, 36 do
			local z = rr(-330, -178)
			local x = rr(-900, 900)
			box(shore, V(x, -0.47, z), V(rr(5, 26), 0.06, rr(0.5, 1.3)), C.foam, "SmoothPlastic", V(0, rr(-6, 6), 0), { castShadow = false, transparency = rr(0.5, 0.75) })
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
			{ ctrl = { V2(-6, -60), V2(-10, -15), V2(-22, 25), V2(-75, 95) }, gauge = 4.6, tyre = 1.5, lug = 0.85 },
			{ ctrl = { V2(30, -90), V2(20, -35), V2(14, 30), V2(60, 110) }, gauge = 4.8, tyre = 1.5, lug = 0.9 },
			-- старые следы на среднем плане (только колея)
			{ ctrl = { V2(-220, 175), V2(-80, 160), V2(80, 185), V2(230, 165) }, gauge = 4.6, tyre = 1.3, lug = 0.85 },
			{ ctrl = { V2(-200, 105), V2(-90, 112), V2(70, 98), V2(210, 112) }, gauge = 4.6, tyre = 1.3, lug = 0.85 },
			{ ctrl = { V2(-90, 190), V2(-70, 120), V2(-110, 70), V2(-150, 20) }, gauge = 4.8, tyre = 1.4, lug = 0.85 },
			{ ctrl = { V2(-200, -118), V2(-80, -132), V2(70, -124), V2(220, -130) }, gauge = 4.6, tyre = 1.3, lug = 0.85 },
		}
		local function clearZone(p)
			-- не класть рельеф прямо под стопы актёров (x -3..3, z≈0)
			return math.abs(p.X) < 4.8 and math.abs(p.Z) < 1.6
		end
		local function lugZone(p)
			-- видимая камерами у центра полоса: |z| < 34, по x — расширяющийся клин
			local az = math.abs(p.Z)
			return az < 31 and math.abs(p.X) < 8 + az * 0.9
		end
		for ti, tr in list do
			local pts = samplePath(tr.ctrl, 0.25)
			-- у каждого трека своя высота (см. ниже), чтобы пересечения колей не мерцали (z-fighting)
			for side = -1, 1, 2 do
				-- колея: стыкующиеся отрезки (без перекрытий), короче вблизи
				-- вблизи колея почти вровень с песком (иначе торцы светятся), вдали чуть выше (против z-fighting)
				local i = 1
				while i < #pts do
					local near = pts[i].Magnitude < 45
					local j = math.min(#pts, i + (if near then 40 else 120))
					local a, b = pts[i], pts[j]
					local dir = (b - a).Unit
					local n = V(-dir.Z, 0, dir.X)
					local mid = (a + b) / 2 + n * (side * tr.gauge / 2)
					local yaw = math.deg(math.atan2(-dir.X, -dir.Z))
					local t = if near then 0.01 + (ti - 1) * 0.003 else 0.04 + (ti - 1) * 0.006
					box(tracks, V(mid.X, t - 0.05, mid.Z), V(tr.tyre, 0.1, (b - a).Magnitude), mix(C.sandPacked, C.sand, if near then 0 else 0.35), "Sand", V(0, yaw, 0), NOSH)
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
						local j = dir * rr(-0.06, 0.06)
						box(tracks, V(c.X + j.X, 0.01 + (ti - 1) * 0.003 + 0.012, c.Z + j.Z), V(tr.tyre * rr(0.8, 0.95), 0.06, rr(0.22, 0.3)), mix(C.tread, C.sandPacked, rr(0, 0.35)), "Sand", V(0, yaw + side * rr(14, 22), 0), NOSH)
					end
				end
			end
		end
		-- вмятины/следы ног: пары тёмных овалов (по видимым зонам)
		for _ = 1, 62 do
			local z = rr(-30, 34)
			local x = rr(-1, 1) * (8 + math.abs(z) * 0.9)
			local c = V(x, 0, z)
			if not clearZone(c) and c.Magnitude > 2.5 then
				local yaw = rr(0, 360)
				local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
				local close = c.Magnitude < 14
				for s = -1, 1, 2 do
					local p = (cf * CFrame.new(s * 0.32, 0, s * rr(0.3, 0.7))).Position
					local y2 = yaw + rr(-10, 10)
					ell(tracks, V(p.X, 0.01, p.Z), V(0.5, 0.045, 0.98), mix(C.sand, C.dent, rr(0.35, 0.75)), "Sand", V(0, y2, 0), NOSH)
					if close then
						-- освещённый дальний бортик вмятины (солнце со стороны -Z): тонкий светлый серп
						ell(tracks, V(p.X, 0.016, p.Z + 0.44), V(0.42, 0.05, 0.2), mix(C.sand, Color3.new(1, 1, 1), 0.05), "Sand", V(0, y2, 0), NOSH)
					end
				end
			end
		end
		-- истоптанные пятна подальше (средний план)
		for _ = 1, 24 do
			local z = if rnd() < 0.7 then rr(60, 170) else rr(-140, -60)
			local x = rr(-1, 1) * (20 + math.abs(z) * 0.9)
			ell(tracks, V(x, 0.006, z), V(rr(3, 8), 0.03, rr(3, 8)), mix(C.sand, C.dent, rr(0.12, 0.3)), "Sand", V(0, rr(0, 180), 0), NOSH)
		end
		-- ракушки и камешки у зоны постановки
		for _ = 1, 22 do
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
			post(blvd, x, 6, z, 17, 0.55, hex(0xB4B9B7), "Metal", NOSH)
			box(blvd, V(x, 22.8, z - 1.4), V(0.35, 0.35, 3.0), hex(0xB4B9B7), "Metal", nil, NOSH)
			box(blvd, V(x, 22.5, z - 2.8), V(1.0, 0.45, 1.6), hex(0x8E9492), "Metal", nil, NOSH)
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
	slabBlock(-150, 412, 62, 28, 46, { core = hex(0x33464A), band = hex(0xC8C4BA), bays = 4 })
	slabBlock(-245, 424, 104, 30, 70, { core = hex(0x34494A), band = hex(0xCFCBC1), bays = 7, step = { 40, 44, 26, -1 }, antenna = true })
	slabBlock(-372, 446, 104, 30, 60, { core = hex(0x3C4F52), band = hex(0xC9C3B6), bays = 7 })
	tower(-462, 432, 28, 24, 86, { cols = 6, color = hex(0xE2DDD3) })
	slabBlock(-560, 456, 118, 30, 54, { core = hex(0x405254), band = hex(0xD2CDC3), bays = 8, step = { 36, 34, 26, -1 } })
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
		wedge(g, V(kx, 6 + 24.5, kz + 7.5), V(120, 5, 15), hex(0x5B6466), "Slate", nil, NOSH)
		wedge(g, V(kx, 6 + 24.5, kz + 22.5), V(120, 5, 15), hex(0x5B6466), "Slate", V(0, 180, 0), NOSH)
		B:cyl(V(kx, 6 + 28.5, kz + 15), 9, 22, hex(0xD9C9AC), "Concrete", "Y", nil, { parent = g, castShadow = false })
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
		-- Павильон с белой крышей-«волной» (как в S01/S03): низко у +X, гребень ближе к -X, крутой спуск на конце.
		local cx, cz = 100, 246
		local D = 40
		local deckTop = 1.9
		box(pav, V(cx, 1.4, cz), V(90, 1.0, D + 6), C.offWhite, "Concrete")
		for i = -3, 3 do
			post(pav, cx + i * 12.5, -1, cz - D / 2 - 2, 2.4, 0.8, C.grey, "Concrete", NOSH)
		end
		-- профиль крыши (x относительно центра, высота над настилом)
		local prof = { { 44, 4.8 }, { 32, 6.6 }, { 20, 8.9 }, { 8, 11.4 }, { -4, 13.6 }, { -14, 15.1 }, { -22, 15.7 }, { -29, 15.0 }, { -35, 12.8 }, { -40, 9.4 }, { -43, 6.2 } }
		local function roofY(x)
			for i = 1, #prof - 1 do
				local a, b = prof[i], prof[i + 1]
				if x <= a[1] and x >= b[1] then
					local t = (a[1] - x) / (a[1] - b[1])
					return a[2] + (b[2] - a[2]) * t
				end
			end
			return prof[#prof][2]
		end
		for i = 1, #prof - 1 do
			local a, b = prof[i], prof[i + 1]
			local mx, my = cx + (a[1] + b[1]) / 2, deckTop + (a[2] + b[2]) / 2
			local dx, dy = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dy * dy) + 0.7
			local ang = math.deg(math.atan2(dy, dx))
			local base = CFrame.new(mx, my, cz) * CFrame.Angles(0, 0, math.rad(ang))
			-- оболочка крыши
			B:part({ cf = base, size = V(len, 0.8, D), color = hex(0xF4F3EF), material = "SmoothPlastic", parent = pav })
			-- скруглённый передний край (наклонённая полоса)
			B:part({ cf = base * CFrame.new(0, -0.1, -D / 2) * CFrame.Angles(math.rad(-38), 0, 0) * CFrame.new(0, 0, -2.4), size = V(len, 0.7, 5), color = hex(0xECEAE5), material = "SmoothPlastic", parent = pav })
			-- задний край
			B:part({ cf = base * CFrame.new(0, -0.1, D / 2) * CFrame.Angles(math.rad(38), 0, 0) * CFrame.new(0, 0, 2.4), size = V(len, 0.7, 5), color = hex(0xE4E2DC), material = "SmoothPlastic", parent = pav, castShadow = false })
		end
		-- первый этаж: стекло и белые колонны (всё строго под оболочкой)
		box(pav, V(cx - 5, deckTop + 2.9, cz + 1), V(70, 5.8, D - 10), hex(0x557380), "Glass", nil, { reflectance = 0.25 })
		box(pav, V(cx + 36, deckTop + 1.8, cz + 1), V(12, 3.6, D - 10), hex(0x557380), "Glass", nil, { reflectance = 0.25 })
		for i = 0, 12 do
			local x = cx - 41 + i * (82 / 12)
			local h = roofY(x - cx) - 0.45
			post(pav, x, deckTop, cz - D / 2 + 3.5, h, 0.55, C.white, "SmoothPlastic", NOSH)
		end
		-- второй ярус под высокой частью крыши: белая плита-терраса, стеклянный парапет и тёмное остекление
		box(pav, V(cx - 15, deckTop + 6.2, cz - 1), V(42, 0.7, D - 4), C.white, "SmoothPlastic")
		box(pav, V(cx - 15, deckTop + 7.2, cz - D / 2 + 3.1), V(42, 1.3, 0.12), hex(0xB8CCD4), "Glass", nil, { transparency = 0.45, castShadow = false })
		box(pav, V(cx - 18, deckTop + 9.42, cz + 2), V(30, 5.75, D - 14), hex(0x3E5560), "Glass", nil, { reflectance = 0.2 })
		-- мачта с флагом на гребне
		post(pav, cx - 22, deckTop + 15.6, cz, 6, 0.3, C.white, "Metal", NOSH)
		box(pav, V(cx - 20.6, deckTop + 20.6, cz), V(2.6, 1.6, 0.06), C.clubBlue, "Fabric", nil, NOSH)
	end

	-- =====================================================================
	-- 7) Пляжные клубы (сине-бирюзовые павильоны на деревянных помостах), зонты, ветрозащиты
	-- =====================================================================
	local clubs = folder("BeachClubs")
	local function club(x, z, w, wallColor, accent, flags, name)
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
		if name then
			local sg = box(g, V(x, 10.6, z - d / 2 + 0.9), V(math.min(w - 4, 16), 2.0, 0.25), accent, "SmoothPlastic", nil, NOSH)
			B:text(sg, "Front", name, { color = if accent == C.white then C.clubNavy else C.white })
		end
		-- флагштоки
		for k = 1, flags do
			local fx = x - w / 2 + k * w / (flags + 1)
			post(g, fx, 9.6, z - d / 2 + 1, 12, 0.25, C.white, "Metal", NOSH)
			box(g, V(fx + 1.5, 20.4, z - d / 2 + 1), V(3, 2, 0.06), pick({ C.clubBlue, C.yellow, C.nlRed, C.white, C.orange }), "Fabric", nil, NOSH)
		end
		return g
	end
	club(-30, 240, 34, C.clubBlue, C.white, 2, "ZEEZICHT")
	club(18, 237, 26, C.white, C.clubTeal, 1, "STRAND 7")
	club(-78, 242, 30, C.clubTeal, C.white, 2, "BEACHCLUB")
	club(-125, 238, 28, C.white, C.clubBlue, 1)
	club(-175, 243, 32, C.clubNavy, C.white, 2)
	club(170, 238, 30, C.clubBlue, C.white, 1, "DE ZON")
	club(225, 243, 26, C.white, C.clubBlue, 2)
	club(-235, 241, 30, C.clubBlue, C.white, 1)
	club(-290, 244, 26, C.white, C.clubTeal, 1)
	-- дальние павильоны (упрощённые)
	for i = 0, 11 do
		local x = 290 + i * 55 + rr(-10, 10)
		local g = B:folder("ClubFar", clubs)
		box(g, V(x, 4.5, 248), V(rr(18, 28), 7, 14), pick({ C.white, C.clubBlue, C.clubTeal, C.offWhite }), "SmoothPlastic", nil, NOSH)
		box(g, V(x, 8.4, 248), V(30, 0.8, 18), C.white, "SmoothPlastic", nil, NOSH)
		local x2 = -350 - i * 60 + rr(-10, 10)
		box(g, V(x2, 4.5, 250), V(rr(18, 28), 7, 14), pick({ C.white, C.clubBlue, C.offWhite, C.clubNavy }), "SmoothPlastic", nil, NOSH)
		box(g, V(x2, 8.4, 250), V(30, 0.8, 18), C.white, "SmoothPlastic", nil, NOSH)
	end
	-- зонты перед клубами
	local props = folder("BeachProps")
	local function umbrella(x, z, color)
		post(props, x, 0, z, 6.6, 0.18, C.white, "Metal", NOSH)
		ell(props, V(x, 6.4, z), V(6.5, 1.5, 6.5), color, "Fabric")
	end
	for i = 0, 15 do
		local x = -200 + i * 22 + rr(-4, 4)
		umbrella(x, 206 + rr(-5, 5), pick({ C.white, C.white, C.clubBlue, hex(0xF0EEE8), C.yellow }))
	end
	-- шезлонги
	for i = 0, 9 do
		local x = -190 + i * 34 + rr(-4, 4)
		local z = 199 + rr(-4, 4)
		local col = pick({ C.white, C.clubBlue, hex(0xE6E0D2) })
		for k = -1, 1, 2 do
			local bx = x + k * 1.6
			box(props, V(bx, 0.55, z + 0.4), V(1.9, 0.35, 4.2), col, "Fabric", nil, NOSH)
			box(props, V(bx, 1.25, z - 2.0), V(1.9, 1.5, 0.3), col, "Fabric", V(-35, 0, 0), NOSH)
		end
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
		local gy0, gy1 = 10.5, 15.5 -- закрытая нижняя галерея (пол ≈10.5), верхняя палуба ≈16.5
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
				post(pier, px + s * (half - 1), -13, zz, gy0 + 13, 1.4, C.pierLeg, "Metal")
				-- стойки остекления галереи над опорой
				box(pier, V(px + s * (half - 0.05), (gy0 + gy1) / 2 + 0.4, zz), V(0.45, gy1 - gy0, 0.5), C.pierTeal, "Metal", nil, NOSH)
			end
			box(pier, V(px, gy0 - 0.6, zz), V(2 * half, 0.8, 0.8), C.pierLeg, "Metal", nil, NOSH)
			beam(pier, V(px - half + 1, -0.5, zz), V(px + half - 1, gy0 - 1, zz), 0.35, 0.35, C.pierLeg, "Metal", NOSH)
			zz -= 20
		end
		-- фонари на верхней палубе
		local lz, k = z0 - 15, 0
		while lz > z1 + 10 do
			k += 1
			local sx = px + (if k % 2 == 0 then 1 else -1) * (half + 0.2)
			post(pier, sx, gy1 + 1, lz, 6.5, 0.3, hex(0x2E3A38), "Metal", NOSH)
			box(pier, V(sx, gy1 + 7.6, lz), V(1.0, 0.5, 1.0), hex(0x2E3A38), "Metal", nil, NOSH)
			lz -= 30
		end
		-- киоски на палубе
		for _, kz in { -150, -330, -470 } do
			box(pier, V(px, gy1 + 3.2, kz), V(7, 4.4, 10), C.white, "SmoothPlastic", nil, NOSH)
			box(pier, V(px, gy1 + 5.7, kz), V(8.4, 0.6, 11.4), C.pierTeal, "Metal", nil, NOSH)
		end
		-- вход на пляже: лестничная башня и пандус
		box(pier, V(px, (gy1 + 1) / 2, z0 + 6), V(16, gy1 + 1, 12), C.pierTeal, "Metal")
		box(pier, V(px, gy1 + 1.3, z0 + 6), V(17, 0.6, 13), C.white, "Metal")
		box(pier, V(px - 8.2, gy1 / 2, z0 + 6), V(0.3, gy1 - 3, 9), hex(0x88A2A8), "Glass", nil, { reflectance = 0.3 })
		local sign = box(pier, V(px, gy1 - 1.4, z0 + 12.1), V(10, 2, 0.2), C.pierTeal, "Metal", nil, NOSH)
		B:text(sign, "Back", "DE PIER", { color = C.white })
		local sign2 = box(pier, V(px - 8.3, gy1 - 1.4, z0 + 6), V(0.2, 2, 9), C.pierTeal, "Metal", nil, NOSH)
		B:text(sign2, "Left", "DE PIER", { color = C.white })
		-- флаг Нидерландов у входа
		post(pier, px - 10, 0, z0 + 14, 22, 0.25, C.white, "Metal", NOSH)
		for k, col in { C.nlRed, C.white, C.nlBlue } do
			box(pier, V(px - 8.2, 21.4 - k * 0.6, z0 + 14), V(3.4, 0.6, 0.05), col, "Fabric", nil, NOSH)
		end
		-- первый «остров» с колесом обозрения
		local iz = -230
		box(pier, V(px + 14, gy1 + 0.5, iz), V(30, 1.0, 40), C.pierTeal, "Metal")
		for _, o in { { 8, -16 }, { 26, -16 }, { 8, 16 }, { 26, 16 } } do
			post(pier, px + o[1], -13, iz + o[2], gy1 + 13, 1.4, C.pierLeg, "Metal")
		end
		-- голова пирса: платформа и павильоны
		local hz = z1 - 40
		box(pier, V(px, gy1 + 0.5, hz), V(64, 1.0, 80), C.pierTeal, "Metal")
		box(pier, V(px, gy0 + 0.4, hz), V(60, 0.8, 76), C.pierTeal, "Metal", nil, NOSH)
		for ox = -26, 26, 13 do
			for oz = -34, 34, 17 do
				post(pier, px + ox, -13, hz + oz, gy0 + 13, 1.3, C.pierLeg, "Metal")
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
		local hub = V(185, 46, -230)
		local R = 26
		local nSeg = 22
		for s = -1, 1, 2 do
			local x = hub.X + s * 1.2
			for i = 0, nSeg - 1 do
				local a0 = (i / nSeg) * math.pi * 2
				local a1 = ((i + 1) / nSeg) * math.pi * 2
				local p0 = V(x, hub.Y + R * math.cos(a0), hub.Z + R * math.sin(a0))
				local p1 = V(x, hub.Y + R * math.cos(a1), hub.Z + R * math.sin(a1))
				beam(wheel, p0, p1, 0.7, 0.7, C.white, "Metal", NOSH)
			end
		end
		for i = 0, 10 do
			local a = (i / 11) * math.pi * 2
			local p = V(hub.X, hub.Y + R * math.cos(a), hub.Z + R * math.sin(a))
			beam(wheel, V(hub.X, hub.Y, hub.Z), p, 0.3, 0.3, C.white, "Metal", NOSH)
		end
		B:cyl(hub, 3.4, 2.2, C.grey, "Metal", "X", nil, { parent = wheel })
		-- опорные ноги (А-образные)
		for s = -1, 1, 2 do
			beam(wheel, V(hub.X + s * 2, 16.5, hub.Z - 16), V(hub.X + s * 1.5, hub.Y, hub.Z), 1.0, 1.0, C.white, "Metal")
			beam(wheel, V(hub.X + s * 2, 16.5, hub.Z + 16), V(hub.X + s * 1.5, hub.Y, hub.Z), 1.0, 1.0, C.white, "Metal")
		end
		-- кабинки
		for i = 0, 10 do
			local a = (i / 11) * math.pi * 2 + 0.11
			local p = V(hub.X, hub.Y + R * math.cos(a) - 1.8, hub.Z + R * math.sin(a))
			box(wheel, p, V(2.6, 2.8, 2.6), pick({ hex(0xD8E4EA), hex(0xB8CCD8) }), "Glass", nil, { reflectance = 0.2, castShadow = false })
		end
	end

	-- =====================================================================
	-- 9) Гавань далеко на западе (видна при взгляде на море слева)
	-- =====================================================================
	local harbor = folder("Harbor")
	do
		-- два мола гавани с маяками (видны слева при взгляде на море)
		local moles = { { x0 = -420, z0 = -150, x1 = -440, z1 = -650, light = C.nlRed }, { x0 = -540, z0 = -150, x1 = -505, z1 = -610, light = hex(0x2F8A46) } }
		for _, m in moles do
			local a, b = V(m.x0, -4.75, m.z0), V(m.x1, -4.75, m.z1)
			beam(harbor, a, b, 13, 14.5, hex(0x5F5E58), "Rock", { castShadow = false })
			beam(harbor, a + V(0, 7.6, 0), b + V(0, 7.6, 0), 7, 0.7, hex(0xA9A59C), "Concrete", { castShadow = false })
			-- навал камней вдоль мола
			for k = 1, 9 do
				local t = k / 10
				local p = a:Lerp(b, t)
				local sgn = if k % 2 == 0 then 1 else -1
				box(harbor, p + V(sgn * rr(5, 7), rr(2.5, 4.2), rr(-6, 6)), V(rr(4, 7), rr(3, 5), rr(5, 9)), pick({ hex(0x55544E), hex(0x6A6862), hex(0x4A4A46) }), "Rock", V(rr(-15, 15), rr(0, 90), rr(-15, 15)), NOSH)
			end
			-- маяк на конце
			local e = b + V(0, 7.95, 0)
			post(harbor, e.X, e.Y, e.Z, 15, 3.4, m.light, "SmoothPlastic", NOSH)
			post(harbor, e.X, e.Y + 15, e.Z, 2.6, 2.2, hex(0xE8E8E2), "Glass", NOSH)
			post(harbor, e.X, e.Y + 17.6, e.Z, 0.8, 3.6, m.light, "SmoothPlastic", NOSH)
		end
		-- павильон на восточном моле
		box(harbor, V(-436, 5.5, -560), V(9, 5, 16), hex(0xE9E6DF), "SmoothPlastic", nil, NOSH)
		box(harbor, V(-436, 8.3, -560), V(10.5, 0.6, 17.5), hex(0x2F4A4E), "Metal", nil, NOSH)
		-- портовые постройки на берегу: тёмно-бирюзовые ангары и белый шатёр
		for i = 0, 6 do
			local x = -600 - i * 70 + rr(-10, 10)
			local h = rr(12, 26)
			local d = rr(30, 50)
			box(harbor, V(x, h / 2, -120 + d / 2 + rr(-10, 30)), V(rr(40, 60), h, d), pick({ hex(0x3F5A5C), hex(0x4C6466), hex(0x8C918C), hex(0xC9C3B6) }), "Concrete", nil, NOSH)
		end
		for k = 0, 2 do
			local x = -705 + k * 15
			wedge(harbor, V(x - 3.5, 13, -100), V(30, 8, 7), hex(0xF2F1EC), "Fabric", V(0, 90, 0), NOSH)
			wedge(harbor, V(x + 3.5, 13, -100), V(30, 8, 7), hex(0xE6E4DE), "Fabric", V(0, -90, 0), NOSH)
		end
		box(harbor, V(-690, 4.5, -100), V(46, 9, 28), hex(0xD8D6D0), "SmoothPlastic", nil, NOSH)
		-- портовые краны
		for _, x in { -900, -1040 } do
			post(harbor, x, 0, -60, 46, 1.6, hex(0x6F7B80), "Metal", NOSH)
			box(harbor, V(x + 10, 46, -60), V(36, 2, 2), hex(0x6F7B80), "Metal", nil, NOSH)
		end
		-- суда на горизонте
		local function ship(x, z, len, yaw, hull, sup)
			local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
			local function at(dx, dy, dz)
				return (cf * CFrame.new(dx, dy, dz)).Position
			end
			box(harbor, at(0, 2, 0), V(len * 0.16, 7, len), hull, "Metal", V(0, yaw, 0), NOSH)
			box(harbor, at(0, 8.5, len * 0.3), V(len * 0.13, 7, len * 0.16), sup, "SmoothPlastic", V(0, yaw, 0), NOSH)
			box(harbor, at(0, 6.5, -len * 0.05), V(len * 0.12, 3, len * 0.45), pick({ hex(0xA84434), hex(0x2E5F86), hex(0xC9A43A) }), "Metal", V(0, yaw, 0), NOSH)
		end
		ship(-700, -2300, 150, 80, hex(0x2C3236), C.white)
		ship(900, -2900, 190, -75, hex(0x5A2A26), C.white)
		ship(-1800, -3200, 120, 95, hex(0x30343A), hex(0xE0DED8))
	end

	-- =====================================================================
	-- 10) Люди вдали (маленькие фигурки)
	-- =====================================================================
	local people = folder("People")
	local skin = { hex(0xE3B999), hex(0xC99572), hex(0x8D5B3E), hex(0xF0CCB0) }
	local cloth = { C.white, hex(0x2C3E66), hex(0xD24B3E), hex(0x1E1E22), hex(0x5E8FB8), hex(0xE9C34A), hex(0x6B8E5A) }
	local function person(x, z, pose, yaw)
		yaw = yaw or 0
		local g = B:folder("Person", people)
		local sk, top, bottom = pick(skin), pick(cloth), pick({ hex(0x2B3240), hex(0x3B5B8A), hex(0xC9B9A0), hex(0x1E1E22), sk })
		local hair = pick({ hex(0x2A1E16), hex(0x5A3B22), hex(0xC9A86A), hex(0x111111) })
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
		local detailed = math.sqrt(x * x + z * z) < 110
		local R = V(0, yaw, 0)
		local function at(dx, dy, dz)
			return (cf * CFrame.new(dx, dy, dz)).Position
		end
		if pose == "sit" then
			box(g, at(0, 0.35, -1.0), V(1.05, 0.6, 2.2), bottom, "Fabric", R, NOSH)
			box(g, at(0, 1.55, 0), V(1.2, 2.0, 0.66), top, "Fabric", V(0, yaw, 0), NOSH)
			if detailed then
				box(g, at(-0.78, 1.25, -0.5), V(0.34, 0.34, 1.6), sk, "SmoothPlastic", R, NOSH)
				box(g, at(0.78, 1.25, -0.5), V(0.34, 0.34, 1.6), sk, "SmoothPlastic", R, NOSH)
				ell(g, at(0, 3.25, 0.08), V(1.0, 0.75, 1.0), hair, "SmoothPlastic", R, NOSH)
			end
			B:ball(at(0, 3.0, 0), 0.95, sk, "SmoothPlastic", { parent = g, castShadow = false })
		elseif pose == "lie" then
			box(g, at(0, 0.3, 0), V(1.2, 0.55, 4.6), top, "Fabric", R, NOSH)
			B:ball(at(0, 0.45, -2.8), 0.9, sk, "SmoothPlastic", { parent = g, castShadow = false })
			box(g, at(0, 0.04, -0.3), V(2.6, 0.06, 6.6), pick({ C.yellow, C.clubBlue, C.red, C.white, hex(0xE77FA8) }), "Fabric", R, NOSH)
		else
			if detailed then
				box(g, at(-0.27, 1.3, 0), V(0.45, 2.6, 0.5), bottom, "Fabric", R, NOSH)
				box(g, at(0.27, 1.3, 0), V(0.45, 2.6, 0.5), bottom, "Fabric", R, NOSH)
				box(g, at(-0.82, 3.35, 0), V(0.32, 2.0, 0.4), sk, "SmoothPlastic", R, NOSH)
				box(g, at(0.82, 3.35, 0), V(0.32, 2.0, 0.4), sk, "SmoothPlastic", R, NOSH)
				ell(g, at(0, 5.22, 0.08), V(1.0, 0.75, 1.0), hair, "SmoothPlastic", R, NOSH)
			else
				box(g, at(0, 1.3, 0), V(1.0, 2.6, 0.55), bottom, "Fabric", R, NOSH)
			end
			box(g, at(0, 3.5, 0), V(1.3, 2.0, 0.66), top, "Fabric", R, NOSH)
			B:ball(at(0, 5.0, 0), 0.95, sk, "SmoothPlastic", { parent = g, castShadow = false })
		end
	end
	-- дальний план за актёрами (вид на город)
	for _ = 1, 30 do
		local x, z = rr(-330, 330), rr(70, 230)
		person(x, z, pick({ "stand", "stand", "stand", "sit", "lie" }), rr(0, 360))
	end
	-- пара, сидящая на песке ближе (как в S03)
	box(people, V(47.2, 0.03, 62), V(5.4, 0.05, 3.6), hex(0xE9E2D2), "Fabric", V(0, 10, 0), NOSH)
	person(46, 62.6, "sit", 200)
	person(48.4, 62.9, "sit", 165)
	-- у кромки воды (вид на море)
	for _ = 1, 11 do
		local x, z = rr(-260, 300), rr(-149, -100)
		person(x, z, pick({ "stand", "stand", "sit" }), rr(0, 360))
	end

	-- синие ветрозащитные полотна перед клубами (синяя полоса в кадрах S01/S03)
	do
		local g = folder("Windscreens")
		local x = -310
		while x < 60 do
			local len = rr(18, 34)
			if rnd() > 0.25 then
				local col = pick({ C.clubBlue, C.clubBlue, C.clubTeal, hex(0x2A6FA0) })
				box(g, V(x + len / 2, 1.0, 221 + rr(-1.5, 1.5)), V(len, 2.0, 0.1), col, "Fabric", V(0, rr(-3, 3), 0), NOSH)
			end
			x += len + rr(2, 10)
		end
	end

	-- пляжный трактор-уборщик (источник следов шин)
	do
		local g = folder("Tractor")
		local cf = CFrame.new(-118, 0, 150) * CFrame.Angles(0, math.rad(64), 0)
		local function at(dx, dy, dz)
			return cf * CFrame.new(dx, dy, dz)
		end
		local col = hex(0x2F7A3E)
		B:part({ cf = at(0, 2.6, 0.6), size = V(3.2, 2.0, 6.6), color = col, material = "Metal", parent = g })
		B:part({ cf = at(0, 5.0, 1.6), size = V(3.0, 2.8, 3.0), color = hex(0x7E98A2), material = "Glass", parent = g, reflectance = 0.25 })
		B:part({ cf = at(0, 6.55, 1.6), size = V(3.4, 0.3, 3.4), color = C.white, material = "Metal", parent = g })
		B:part({ cf = at(0.9, 4.6, -2.0), size = V(0.25, 2.6, 0.25), color = hex(0x222222), material = "Metal", parent = g, castShadow = false })
		for _, w in { { -2.0, 1.6, 2.4, 3.2 }, { 2.0, 1.6, 2.4, 3.2 }, { -2.0, -1.8, 1.6, 2.2 }, { 2.0, -1.8, 1.6, 2.2 } } do
			B:part({ cf = at(w[1], w[4] / 2, w[2]) * CFrame.Angles(0, 0, 0), size = V(w[3] * 0.55, w[4], w[4]), color = hex(0x1E1E1E), material = "Rubber", shape = "Cylinder", parent = g })
		end
		-- прицепная борона-уборщик
		B:part({ cf = at(0, 0.8, 6.4), size = V(5.6, 1.2, 2.6), color = hex(0xC9A43A), material = "Metal", parent = g })
	end

	-- спасательная вышка у воды и волейбольная сетка
	do
		local g = folder("Lifeguard")
		local lx, lz = -70, -112
		for _, o in { { -1.6, -1.6 }, { 1.6, -1.6 }, { -1.6, 1.6 }, { 1.6, 1.6 } } do
			post(g, lx + o[1], -0.5, lz + o[2], 9.5, 0.45, hex(0xE8E6E0), "Wood")
		end
		box(g, V(lx, 9.4, lz), V(4.6, 0.4, 4.6), C.wood, "WoodPlanks")
		box(g, V(lx, 11.2, lz + 0.4), V(3.8, 3.4, 3.6), hex(0xE9E7E1), "SmoothPlastic")
		box(g, V(lx, 11.6, lz - 1.42), V(3.2, 1.4, 0.12), hex(0x6F8C98), "Glass", nil, NOSH)
		box(g, V(lx, 13.1, lz + 0.2), V(4.6, 0.4, 4.8), C.red, "SmoothPlastic")
		local lsign = box(g, V(lx, 9.95, lz - 2.35), V(4.4, 0.7, 0.1), C.red, "SmoothPlastic", nil, NOSH)
		B:text(lsign, "Front", "REDDINGSBRIGADE", { color = C.white })
		beam(g, V(lx + 1.2, 0, lz - 5.5), V(lx + 1.2, 9.4, lz - 2.2), 1.0, 0.2, C.wood, "WoodPlanks")
		post(g, lx - 2.2, 13.3, lz - 2.2, 5, 0.18, C.white, "Metal", NOSH)
		box(g, V(lx - 1.3, 17.6, lz - 2.2), V(1.8, 1.1, 0.05), C.red, "Fabric", nil, NOSH)
		box(g, V(lx - 1.3, 17.6, lz - 2.2 + 0.06), V(1.8, 0.37, 0.05), C.yellow, "Fabric", nil, NOSH)
		-- волейбол
		local vx, vz = 70, 128
		for s = -1, 1, 2 do
			post(g, vx + s * 9, 0, vz, 8.2, 0.3, C.white, "Metal", NOSH)
		end
		box(g, V(vx, 6.9, vz), V(18, 2.4, 0.06), hex(0x222222), "Fabric", nil, { transparency = 0.55, castShadow = false })
		box(g, V(vx, 8.1, vz), V(18, 0.18, 0.1), C.white, "Fabric", nil, NOSH)
		B:ball(V(vx + 3, 0.45, vz - 6), 0.9, C.yellow, "SmoothPlastic", { parent = g })
	end

	-- воздушные змеи над пляжем
	do
		local g = folder("Kites")
		for _, k in { { -210, 58, 120, C.red, C.yellow, -196, 92 }, { 120, 40, -60, C.clubBlue, C.white, 104, -34 } } do
			local p = V(k[1], k[2], k[3])
			-- запускающий змея человек и леер (с лёгким провисом)
			local fx, fz = k[6], k[7]
			local yaw = math.deg(math.atan2(-(k[1] - fx), -(k[3] - fz)))
			person(fx, fz, "stand", yaw)
			local hand = V(fx, 4.6, fz) + V(k[1] - fx, 0, k[3] - fz).Unit * 0.9
			local tip = p - V(0, 2.1, 0)
			local mid = hand:Lerp(tip, 0.5) - V(0, 2.5, 0)
			beam(g, hand, mid, 0.07, 0.07, hex(0xF2F2F2), "SmoothPlastic", NOSH)
			beam(g, mid, tip, 0.07, 0.07, hex(0xF2F2F2), "SmoothPlastic", NOSH)
			local cf = CFrame.new(p) * CFrame.Angles(0, math.rad(rr(-30, 30)), 0) * CFrame.Angles(0, 0, math.rad(45))
			B:part({ cf = cf, size = V(3.2, 3.2, 0.08), color = k[4], material = "Fabric", parent = g, castShadow = false })
			B:part({ cf = cf * CFrame.new(0, 0, -0.05), size = V(3.2, 0.3, 0.06), color = k[5], material = "Fabric", parent = g, castShadow = false })
			-- хвост
			local tail = p
			for i = 1, 3 do
				local nxt = tail + V(rr(-0.6, 0.6), -1.6, rr(-0.4, 0.4))
				beam(g, tail, nxt, 0.12, 0.12, if i % 2 == 0 then k[5] else k[4], "Fabric", NOSH)
				tail = nxt
			end
		end
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

	-- Цвет материалов Terrain: детали-песок (следы, мокрая полоса) подобраны под этот цвет песка,
	-- а у Terrain по умолчанию песок темнее (143,126,95). Скрипт ставит цвет при запуске (Terrain общий,
	-- Sand/Pavement используются только на пляже).
	root:SetAttribute("TerrainColor_Sand", C.sand)
	root:SetAttribute("TerrainColor_Pavement", hex(0xB9B5AC))
	local scr = roblox.Instance.new("Script")
	scr.Name = "BeachTerrainColors"
	scr.Source = [[
-- Цвета материалов Terrain для пляжа: атрибуты TerrainColor_<Material> модели Beach.
local model = script.Parent
for name, value in model:GetAttributes() do
	local m = string.match(name, "^TerrainColor_(%w+)$")
	if m and typeof(value) == "Color3" then
		pcall(function()
			workspace.Terrain:SetMaterialColor((Enum.Material :: any)[m], value)
		end)
	end
end
]]
	scr.Parent = root
end
