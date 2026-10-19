--!nocheck
-- Тело летающего острова (docs/STYLE.md §6.13): плоский верх (веер треугольников из клиньев — без наложений
-- и z-fighting), неровная кромка с 2–3 «долями» и мысами, подтёки травы, пояс земли и три пояса скал
-- с наклоном наружу (тон сверху вниз: свет → основа → тень), гранёный низ, снесённый по ветру,
-- сосульки-сталактиты и «энергетический корень» — кристалл на нижнем кончике (острова держатся на молнии).
-- Используется для хаба и пяти островов.
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material

local Island = {}

local TAU = math.pi * 2
local W = B.W

local function angDiff(a: number, b: number): number
	return math.abs(((a - b + math.pi) % TAU) - math.pi)
end

-- Радиус кромки по углу: 2–3 крупные доли + мелкий шум + мысы, выравнивание у мостов
local function makeOutline(rng, R: number, base: number, amp: number, openings, openHalfDeg: number, capeCount: number)
	local ph1, ph2, ph3 = rng:range(0, TAU), rng:range(0, TAU), rng:range(0, TAU)
	local f1, f2 = rng:int(2, 3), rng:int(4, 5)
	-- мысы: подальше от мостов и друг от друга
	local capes = {}
	for _ = 1, 60 do
		if #capes >= capeCount then
			break
		end
		local a = rng:range(0, TAU)
		local ok = true
		for _, d in openings do
			if angDiff(a, math.atan2(d.Z, d.X)) < math.rad(55) then
				ok = false
			end
		end
		for _, c in capes do
			if angDiff(a, c.angle) < math.rad(80) then
				ok = false
			end
		end
		if ok then
			table.insert(capes, { angle = a, width = math.rad(rng:range(9, 13)), height = rng:range(9, 13) })
		end
	end
	local function outline(theta: number): number
		local n = 0.5 + 0.5 * (0.6 * math.sin(f1 * theta + ph1) + 0.28 * math.sin(f2 * theta + ph2) + 0.12 * math.sin(9 * theta + ph3))
		local r = R + base + amp * n
		for _, c in capes do
			local x = angDiff(theta, c.angle) / c.width
			r += c.height * math.exp(-x * x)
		end
		-- у мостов кромка ровная (R + 1.5), чтобы настил лёг аккуратно
		for _, d in openings do
			local diff = angDiff(theta, math.atan2(d.Z, d.X))
			local w = math.rad(openHalfDeg)
			if diff < w * 2.2 then
				local t = math.clamp((diff - w) / (w * 1.2), 0, 1)
				t = t * t * (3 - 2 * t)
				r = (R + 1.5) * (1 - t) + r * t
			end
		end
		return r
	end
	return outline, capes
end

-- opts:
--   center (Vector3, Y = поверхность), radius, seed, segments, base, amp, depth,
--   top, topMaterial, dirt, rock (основа скал), openings = { dirVector,... } (направления мостов), openHalfDeg,
--   capes (число мысов), drips, dripColor, hang = function(parent, pos, out, rng), hangCount,
--   energy (цвет «энергетического корня»), walls = { radius, height } | nil, wallParent
-- Возвращает { outline = fn(theta) -> r, points = {Vector3}, model, innerR, bottomY, capes = { {angle, height} } }
function Island.body(parent, opts)
	local rng = B.rng(opts.seed or 1)
	local C = opts.center
	local R = opts.radius
	local N = opts.segments or 28
	local topT = opts.topThickness or 2.2
	-- амплитуда кромки не меньше 0.08·R (STYLE §6.13); хаб-плато может задать свою (ampExact)
	local amp = if opts.ampExact then opts.amp else math.max(opts.amp or 0, R * 0.1)
	local outline, capes = makeOutline(rng, R, opts.base or 2, amp, opts.openings or {}, opts.openHalfDeg or 10, opts.capes or 0)
	local m = B.model(parent, opts.name or "Ground")
	local rock = opts.rock
	local rockLight, rockShade, rockDeep = B.tint(rock, 1), B.shade(rock, 1), B.shade(rock, 1.6)

	-- точки кромки
	local pts, radii = {}, {}
	for k = 0, N - 1 do
		local th = (k / N) * TAU
		local r = outline(th)
		radii[k + 1] = r
		pts[k + 1] = C + Vector3.new(math.cos(th) * r, 0, math.sin(th) * r)
	end
	local innerR = math.huge
	for _, r in radii do
		innerR = math.min(innerR, r)
	end

	-- 1) верх: веер треугольников от центра (одна плоскость, без наложений)
	for k = 1, N do
		B.triangle(m, C, pts[k], pts[k % N + 1], topT, opts.top, { Material = opts.topMaterial or M.Grass, Shadow = true, Name = "Top" })
	end

	-- 2) пояс земли под кромкой: трава нависает козырьком, блоки наклонены наружу
	local yTop = C.Y - topT
	local soilH = opts.soilHeight or 4.5
	local dirt = opts.dirt
	for k = 1, N do
		local a, b = pts[k], pts[k % N + 1]
		local mid = (a + b) / 2
		local out = B.flat(mid - C).Unit
		local len = (b - a).Magnitude
		local h = soilH + rng:range(-0.4, 1.2)
		local d = 7
		local pos = mid - out * (d / 2 + rng:range(0.5, 1.1)) + Vector3.new(0, -topT + 0.5 - h / 2, 0)
		-- отрицательный угол вокруг касательной: верх блока наружу, низ внутрь (остров сужается книзу)
		local cf = B.facing(pos, out) * CFrame.Angles(-math.rad(rng:range(14, 20)), 0, math.rad(rng:range(-3, 3)))
		local col = if k % 3 == 0 then B.tint(dirt, 0.5) else dirt
		B.block(m, cf, Vector3.new(len * 1.16, h, d), B.vary(col, rng, 0.025), B.deco({ Shadow = true }))
	end

	-- 3) три пояса скал: каждый уже и ниже, наклон наружу 15–25°, низ сносит по ветру
	local belts = {
		{ scale = 0.94, h = 8, count = math.floor(N * 0.8), col = rockLight, d = 9 },
		{ scale = 0.8, h = 10, count = math.floor(N * 0.62), col = rock, d = 11 },
		{ scale = 0.6, h = 12, count = math.floor(N * 0.46), col = rockShade, d = 12 },
	}
	local depth = opts.depth or 62
	local y = yTop - soilH + 1.0
	local maxTop = yTop - 1.5 -- ни один камень не должен торчать сквозь верх
	for j, belt in belts do
		local drift = W * (j * 2.5)
		local rot = rng:range(0, TAU)
		local rMin = math.huge
		for q = 1, belt.count do
			local th = rot + (q / belt.count) * TAU + rng:range(-0.08, 0.08)
			local rr = outline(th) * belt.scale
			rMin = math.min(rMin, rr)
			local out = Vector3.new(math.cos(th), 0, math.sin(th))
			local w = TAU * rr / belt.count * rng:range(1.25, 1.5)
			local h = belt.h * rng:range(0.9, 1.25)
			local tilt = math.rad(rng:range(15, 25))
			local hv = (h / 2) * math.cos(tilt) + (belt.d / 2) * math.sin(tilt) + 0.3
			local yy = math.min(y - h / 2 + rng:range(-0.8, 0.8), maxTop - hv)
			local pos = C + drift + out * (rr - belt.d / 2) + Vector3.new(0, yy - C.Y, 0)
			local cf = B.facing(pos, out) * CFrame.Angles(-tilt, rng:range(-0.12, 0.12), rng:range(-0.08, 0.08))
			B.block(m, cf, Vector3.new(w, h, belt.d), B.vary(belt.col, rng, 0.03), B.deco({ Shadow = j == 1 }))
		end
		-- заполнение середины пояса (видно только снизу): шестигранник
		B.hexPrism(m, Vector3.new(C.X, y - belt.h * 0.55, C.Z) + drift, math.max(4, (rMin - belt.d * 0.55)), belt.h * 1.15, rot, B.shade(belt.col, 0.6), B.deco({ Shadow = false }))
		y -= belt.h * 0.92
	end

	-- 4) гранёный низ: перевёрнутые пирамиды разной высоты, главный кончик снесён по ветру
	local bottomTop = y + 1
	local coneR = innerR * 0.42
	local tipDrift = W * 10
	local remaining = math.max(14, depth - (C.Y - bottomTop))
	B.pyramid4(m, Vector3.new(C.X, bottomTop, C.Z) + W * 7.5, coneR * 2, remaining, rng:range(0, 1), rockDeep, B.deco({ Shadow = false }), true)
	local tip = Vector3.new(C.X, bottomTop - remaining, C.Z) + tipDrift
	-- боковые «сосульки»: меньшие пирамиды вокруг
	local hangs = opts.stalactites or 4
	for k = 1, hangs do
		local th = (k + rng:range(-0.3, 0.3)) / hangs * TAU
		local rr = innerR * rng:range(0.42, 0.62)
		local p = Vector3.new(C.X + math.cos(th) * rr, bottomTop + 6, C.Z + math.sin(th) * rr) + W * 5
		local w = rng:range(9, 14) * (R / 90)
		B.pyramid4(m, p, w, rng:range(10, 20) * (R / 90), rng:range(0, 1), B.shade(rock, rng:range(1.1, 1.5)), B.deco({ Shadow = false }), true)
	end
	-- «энергетический корень»: стеклянный кристалл с неоновой сердцевиной на нижнем кончике
	local energy = opts.energy
	if energy then
		local rootPos = tip + Vector3.new(0, 1.2, 0) - W * 1.5
		B.gem(m, rootPos, 5, rng:range(0, 1), B.mix(energy, B.rgb(255, 255, 255), 0.35), B.deco({ Material = M.Glass, Transparency = 0.25, Shadow = false, Name = "EnergyRoot" }))
		B.gem(m, rootPos, 1.6, rng:range(0, 1), energy, B.neon({ Name = "EnergyRoot" }))
	end
	local bottomY = tip.Y

	-- 5) обломки, парящие под островом: гранёные камни убывающих размеров
	local sizes = { 4, 2.8, 2, 1.4, 1, 0.7 }
	for k = 1, math.min(opts.floaters or 6, #sizes) do
		local th = rng:range(0, TAU)
		local rr = innerR * rng:range(0.5, 1.0)
		local pos = Vector3.new(C.X + math.cos(th) * rr, bottomTop - rng:range(4, 24), C.Z + math.sin(th) * rr) + W * rng:range(4, 14)
		B.gem(m, pos, sizes[k] * (R / 90) * 1.6, rng:range(0, TAU), B.shade(rock, rng:range(0.6, 1.4)), B.deco({ Shadow = false, Name = "Floater" }))
	end

	-- 6) «подтёки» травы по кромке (трава свисает с обрыва), длиннее с подветренной стороны
	local drips = opts.drips or 12
	local dripColor = opts.dripColor or B.shade(opts.top, 1)
	for _ = 1, drips do
		local k = rng:int(1, N)
		local a, b = pts[k], pts[k % N + 1]
		local p = a:Lerp(b, rng:range(0.15, 0.85))
		local out = B.flat(p - C).Unit
		local lee = math.max(0, out:Dot(W))
		local len = rng:range(1.5, 3) + lee * 1.5
		local w = rng:range(2, 4)
		local pos = p + out * 0.3 + Vector3.new(0, -topT - len / 2 + 0.6, 0)
		-- после поворота на 180° вокруг Z толстая часть клина сверху, задняя грань (+Z) прижата к обрыву
		local cf = B.facing(pos, out) * CFrame.Angles(0, 0, math.pi)
		B.wedge(m, cf, Vector3.new(w, len, 0.9), B.vary(dripColor, rng, 0.03), B.deco({ Material = opts.topMaterial or M.Grass, Shadow = false }))
	end

	-- 7) особые подвески снизу (корни, сосульки, трубы, кристаллы)
	if opts.hang then
		for _ = 1, opts.hangCount or 8 do
			local k = rng:int(1, N)
			local a, b = pts[k], pts[k % N + 1]
			local p = a:Lerp(b, rng:range(0.1, 0.9))
			local out = B.flat(p - C).Unit
			opts.hang(m, p - out * rng:range(1.5, 3) - Vector3.new(0, topT + soilH * 0.6, 0), out, rng)
		end
	end

	-- 8) невидимые стены по краю (кроме проёмов мостов)
	if opts.walls then
		local wr = opts.walls.radius or (R + 0.8)
		local wh = opts.walls.height or 16
		local segs = opts.walls.segments or 28
		local wallParent = opts.wallParent or m
		local half = math.rad(opts.openHalfDeg or 10)
		for q = 0, segs - 1 do
			local th0 = (q / segs) * TAU
			local th1 = ((q + 1) / segs) * TAU
			local thm = (th0 + th1) / 2
			local open = false
			for _, d in opts.openings or {} do
				if angDiff(thm, math.atan2(d.Z, d.X)) < half + math.pi / segs * 0.35 then
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
	end

	return { outline = outline, points = pts, model = m, innerR = innerR, bottomY = bottomY, capes = capes }
end

-- Холм: 2–3 ступенчатые шестигранные плиты (R → 0.64R → 0.36R), верхняя ступень светлее.
-- pos — точка на земле. Только снаружи игровой зоны! Возвращает список деталей
function Island.hill(parent, pos, R: number, steps: number, color, material, rng, stepH: number?)
	local parts = {}
	local t = stepH or 2.5
	local yaw = rng:range(0, TAU)
	local scales = { 1, 0.64, 0.36 }
	for k = 1, steps do
		local col = if k == steps then B.tint(color, 1) elseif k == 1 then color else B.tint(color, 0.5)
		local c = pos + Vector3.new(0, t * (k - 1) + t / 2 - 0.3, 0) + W * (k - 1) * 0.8
		for _, p in B.hexPlate(parent, c, R * scales[k], t, yaw + k * 0.35, 0.5, rng, B.vary(col, rng, 0.02), { Material = material, Shadow = k == 1, Name = "Hill" }) do
			table.insert(parts, p)
		end
	end
	return parts
end

return Island
