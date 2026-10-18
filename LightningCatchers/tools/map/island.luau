--!nocheck
-- Тело летающего острова: плоский верх (веер треугольников из клиньев — без наложений и z-fighting),
-- кромка травы с «подтёками», слой земли, скальный обрыв и перевёрнутый слоистый конус со сталактитами.
-- Используется для хаба, пяти островов и далёких скал.
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material

local Island = {}

-- Радиус кромки по углу: плавный шум из нескольких синусоид + выравнивание у мостов
local function makeOutline(rng, R: number, base: number, amp: number, openings, openHalfDeg: number)
	local ph1, ph2, ph3 = rng:range(0, 6.28), rng:range(0, 6.28), rng:range(0, 6.28)
	local f1, f2 = rng:int(2, 4), rng:int(5, 7)
	return function(theta: number): number
		local n = 0.5 + 0.5 * (0.55 * math.sin(f1 * theta + ph1) + 0.3 * math.sin(f2 * theta + ph2) + 0.15 * math.sin(11 * theta + ph3))
		local r = R + base + amp * n
		-- у мостов кромка ровная (R + 1.5), чтобы настил лёг аккуратно
		for _, d in openings do
			local a = math.atan2(d.Z, d.X)
			local diff = math.abs(((theta - a + math.pi) % (2 * math.pi)) - math.pi)
			local w = math.rad(openHalfDeg)
			if diff < w * 2.2 then
				local t = math.clamp((diff - w) / (w * 1.2), 0, 1)
				t = t * t * (3 - 2 * t)
				r = (R + 1.5) * (1 - t) + r * t
			end
		end
		return r
	end
end

-- opts:
--   center (Vector3, Y = поверхность), radius, seed, segments, base, amp, depth,
--   top, topMaterial, lip (цвет боковины верхнего слоя), dirt, dirtMaterial, rock, rockMaterial,
--   openings = { dirVector,... } (направления мостов), openHalfDeg,
--   drips (кол-во подтёков), dripColor, hang = function(parent, pos, rng) (особые «подвески» снизу),
--   walls = { radius, height } | nil, wallParent
-- Возвращает { outline = fn(theta) -> r, points = {Vector3}, model }
function Island.body(parent, opts)
	local rng = B.rng(opts.seed or 1)
	local C = opts.center
	local R = opts.radius
	local N = opts.segments or 40
	local topT = opts.topThickness or 2.2
	local outline = makeOutline(rng, R, opts.base or 2, opts.amp or 6, opts.openings or {}, opts.openHalfDeg or 10)
	local m = B.model(parent, opts.name or "Ground")

	-- точки кромки
	local pts, radii = {}, {}
	for k = 0, N - 1 do
		local th = (k / N) * math.pi * 2
		local r = outline(th)
		radii[k + 1] = r
		pts[k + 1] = C + Vector3.new(math.cos(th) * r, 0, math.sin(th) * r)
	end

	-- 1) верх: веер треугольников от центра (одна плоскость, без наложений)
	local top = opts.top
	for k = 1, N do
		local a, b = pts[k], pts[k % N + 1]
		B.triangle(m, C, a, b, topT, top, { Material = opts.topMaterial or M.Grass, Shadow = true, Name = "Top" })
	end

	-- 2) слой земли под кромкой (чуть внутрь, чтобы трава нависала козырьком)
	local dirt = opts.dirt
	local soilH = opts.soilHeight or 4
	local yTop = C.Y - topT
	local innerR = math.huge
	for _, r in radii do
		innerR = math.min(innerR, r)
	end
	B.cylY(m, Vector3.new(C.X, yTop - soilH / 2, C.Z), soilH, (innerR - 3) * 2, B.shade(dirt, 0.1), { Material = opts.dirtMaterial or M.Ground, Shadow = false, Collide = false, Query = false })
	for k = 1, N do
		local a, b = pts[k], pts[k % N + 1]
		local mid = (a + b) / 2
		local out = B.flat(mid - C).Unit
		local len = (b - a).Magnitude
		local inset = rng:range(0.5, 1.3)
		local h = soilH + rng:range(-0.5, 1.5)
		local pos = mid - out * (inset + 4) + Vector3.new(0, -topT - h / 2 + 0.01, 0)
		local cf = B.facing(pos, out) * CFrame.Angles(rng:range(-0.06, 0.1), 0, rng:range(-0.05, 0.05))
		B.block(m, cf, Vector3.new(len * 1.18, h, 8), B.vary(dirt, rng, 0.05), B.deco({ Material = opts.dirtMaterial or M.Ground, Shadow = true }))
	end

	-- 3) скальный обрыв (почти вертикальный, неровный) + 4) перевёрнутый конус слоями
	local rock = opts.rock
	local rockMat = opts.rockMaterial or M.Slate
	local depth = opts.depth or 60
	local cliffH = opts.cliffHeight or 9
	local y0 = yTop - soilH + 0.6
	local layers = opts.layers or 6
	-- профиль: доля радиуса на глубине t (0 — верх обрыва, 1 — низ конуса)
	local function profile(t: number): number
		if t <= 0 then
			return 1
		end
		return math.max(0.06, (1 - t) ^ 0.75)
	end
	local R0 = innerR - 1.2
	-- обрыв
	for k = 1, N do
		local a, b = pts[k], pts[k % N + 1]
		local mid = (a + b) / 2
		local out = B.flat(mid - C).Unit
		local rr = B.flat(mid - C).Magnitude
		local len = (b - a).Magnitude
		local h = cliffH + rng:range(-1.5, 2.5)
		local d = 10
		local pos = C + out * (rr - rng:range(1.4, 2.4) - d / 2) + Vector3.new(0, y0 - C.Y - h / 2, 0)
		local cf = B.facing(pos, out) * CFrame.Angles(rng:range(0.02, 0.14), rng:range(-0.12, 0.12), rng:range(-0.08, 0.08))
		B.block(m, cf, Vector3.new(len * 1.25, h, d), B.vary(B.shade(rock, 0.05), rng, 0.05), { Material = rockMat, Shadow = true, Collide = false, Query = false })
	end
	B.cylY(m, Vector3.new(C.X, y0 - cliffH / 2, C.Z), cliffH, (R0 - 6) * 2, B.shade(rock, 0.2), B.deco({ Material = rockMat, Shadow = false }))
	-- конус
	local coneTop = y0 - cliffH + 1
	local coneDepth = depth - cliffH - soilH - topT
	local layerH = coneDepth / layers
	for j = 1, layers do
		local t0 = (j - 1) / layers
		local t1 = j / layers
		local r0 = R0 * profile(t0) * (if j == 1 then 0.97 else 1)
		local r1 = R0 * profile(t1)
		local yMid = coneTop - (j - 0.5) * layerH
		local count = math.max(5, math.floor(N * (r0 / R0) * 0.55 + 0.5))
		local slope = math.atan2(r0 - r1, layerH)
		local col = B.shade(rock, 0.12 + 0.75 * t1)
		local rot = rng:range(0, math.pi * 2)
		for q = 1, count do
			local th = rot + (q / count) * math.pi * 2 + rng:range(-0.12, 0.12)
			local out = Vector3.new(math.cos(th), 0, math.sin(th))
			local rr = (r0 + r1) / 2
			local d = math.max(4, rr * 0.6)
			local w = 2 * math.pi * rr / count * rng:range(1.25, 1.6)
			local h = layerH * rng:range(1.25, 1.7)
			local pos = C + out * (rr - d / 2 + rng:range(-0.6, 1.2)) + Vector3.new(0, yMid - C.Y + rng:range(-1, 1), 0)
			local cf = B.facing(pos, out) * CFrame.Angles(-slope + rng:range(-0.08, 0.08), rng:range(-0.15, 0.15), rng:range(-0.12, 0.12))
			B.block(m, cf, Vector3.new(w, h, d), B.vary(col, rng, 0.05), B.deco({ Material = rockMat, Shadow = j <= 2 }))
		end
		-- заполнение середины (видно только снизу)
		if j % 2 == 0 or j == layers then
			B.cylY(m, Vector3.new(C.X, yMid, C.Z), layerH * 1.3, math.max(4, r1 * 1.4), B.shade(rock, 0.2 + 0.7 * t1), B.deco({ Material = rockMat, Shadow = false }))
		end
	end
	-- сталактиты: центральный шип и висящие камни по нижним слоям
	local bottomY = coneTop - coneDepth
	local function stalactite(pos, len: number, w: number, col)
		local p = pos
		local ww = w
		local seg = len / 3
		for s = 1, 3 do
			local cf = CFrame.new(p - Vector3.new(0, seg / 2, 0)) * CFrame.Angles(rng:range(-0.12, 0.12), rng:range(0, 3.14), rng:range(-0.12, 0.12)) * CFrame.Angles(0, math.pi / 4, 0)
			B.block(m, cf, Vector3.new(ww, seg * 1.25, ww), B.vary(B.shade(col, 0.1 * s), rng, 0.04), B.deco({ Material = rockMat, Shadow = false }))
			p = p - Vector3.new(rng:range(-0.4, 0.4), seg, rng:range(-0.4, 0.4))
			ww *= 0.58
		end
	end
	stalactite(Vector3.new(C.X, bottomY + 2, C.Z), depth * 0.35, R0 * 0.16, B.shade(rock, 0.85))
	local hangs = opts.stalactites or 7
	for _ = 1, hangs do
		local t = rng:range(0.35, 0.85)
		local rr = R0 * profile(t) * rng:range(0.45, 0.8)
		local th = rng:range(0, math.pi * 2)
		local pos = C + Vector3.new(math.cos(th) * rr, coneTop - C.Y - t * coneDepth, math.sin(th) * rr)
		stalactite(pos, rng:range(8, 16) * (R / 90), rng:range(3, 5) * (R / 90), B.shade(rock, 0.4 + 0.5 * t))
	end

	-- 5) «подтёки» травы по кромке (трава свисает с обрыва)
	local drips = opts.drips or 14
	local dripColor = opts.dripColor or B.shade(top, 0.08)
	for _ = 1, drips do
		local k = rng:int(1, N)
		local a, b = pts[k], pts[k % N + 1]
		local f = rng:range(0.15, 0.85)
		local p = a:Lerp(b, f)
		local out = B.flat(p - C).Unit
		local len = rng:range(2.5, 5.5)
		local w = rng:range(2, 4.5)
		-- клин: толстый вверху, сходит на нет вниз; наклонная грань наружу
		local pos = p + out * 0.35 + Vector3.new(0, -topT - len / 2 + 0.6, 0)
		-- после поворота на 180° вокруг Z толстая часть клина сверху, задняя грань (+Z) прижата к обрыву
		local cf = B.facing(pos, out) * CFrame.Angles(0, 0, math.pi)
		B.wedge(m, cf, Vector3.new(w, len, 0.9), B.vary(dripColor, rng, 0.04), B.deco({ Material = opts.topMaterial or M.Grass, Shadow = false }))
	end

	-- 6) особые подвески снизу (корни, сосульки, трубы, кристаллы)
	if opts.hang then
		for _ = 1, opts.hangCount or 10 do
			local k = rng:int(1, N)
			local a, b = pts[k], pts[k % N + 1]
			local p = a:Lerp(b, rng:range(0.1, 0.9))
			local out = B.flat(p - C).Unit
			opts.hang(m, p - out * rng:range(1.5, 3) - Vector3.new(0, topT + soilH * 0.6, 0), out, rng)
		end
	end

	-- 7) невидимые стены по краю (кроме проёмов мостов)
	if opts.walls then
		local wr = opts.walls.radius or (R + 0.8)
		local wh = opts.walls.height or 16
		local segs = opts.walls.segments or 36
		local wallParent = opts.wallParent or m
		local half = math.rad(opts.openHalfDeg or 10)
		for q = 0, segs - 1 do
			local th0 = (q / segs) * math.pi * 2
			local th1 = ((q + 1) / segs) * math.pi * 2
			local thm = (th0 + th1) / 2
			local open = false
			for _, d in opts.openings or {} do
				local a = math.atan2(d.Z, d.X)
				local diff = math.abs(((thm - a + math.pi) % (2 * math.pi)) - math.pi)
				if diff < half + math.pi / segs * 0.35 then
					open = true
				end
			end
			if not open then
				local p0 = C + Vector3.new(math.cos(th0) * wr, 0, math.sin(th0) * wr)
				local p1 = C + Vector3.new(math.cos(th1) * wr, 0, math.sin(th1) * wr)
				local mid = (p0 + p1) / 2 + Vector3.new(0, wh / 2 - 1, 0)
				local out = B.flat(mid - C).Unit
				local w = B.block(wallParent, B.facing(mid, out), Vector3.new((p1 - p0).Magnitude + 0.6, wh, 1), B.rgb(255, 255, 255), { Collide = true, Query = false, Shadow = false, Transparency = 1, Name = "Wall" })
				w.CanTouch = false
			end
		end
		-- стенки проёмов: короткие перпендикулярные стенки по бокам моста не нужны —
		-- мост сам огорожен перилами и невидимыми стенами
	end

	return { outline = outline, points = pts, model = m, innerR = innerR, bottomY = bottomY }
end

-- Небольшой бугор-холм: шар, утопленный в землю (только снаружи игровой зоны!)
function Island.hill(parent, pos, diameter: number, capHeight: number, color, material, rng)
	local y = pos.Y - diameter / 2 + capHeight
	return B.ball(parent, Vector3.new(pos.X, y, pos.Z), diameter, B.vary(color, rng, 0.03), { Material = material, Shadow = true })
end

return Island
