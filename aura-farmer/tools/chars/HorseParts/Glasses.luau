--!nocheck
-- Золотые авиаторы на суставе Glasses (опора — центр перемычки на переносице).
-- Всё — настоящие детали Part (в Roblox материал на SpecialMesh не виден):
--   линза — горизонтальные «ломтики» Block + Wedge (Glass, полупрозрачная), каплевидный контур;
--   оправа — цилиндры по контуру (Foil), двойная перемычка (прямая верхняя планка + изогнутый мост),
--   носоупоры, шарниры, дужки до ушей.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")

local Glasses = {}

-- Контур правой линзы (u — наружу к виску, v — вверх) относительно центра линзы.
Glasses.LENS = { a = 0.35, b = 0.29, cu = 0.0, cv = -0.03, rot = -20, top = 0.2, topSlope = 0.06, e = 2.6 }
Glasses.LENS_X = 0.385 -- центр линзы от середины
Glasses.WRAP = 9 -- разворот линз по лицу (град)
Glasses.TILT = -7 -- пантоскопический наклон (низ ближе к лицу)
Glasses.Z = -0.02 -- плоскость линз относительно опоры

-- Замкнутый контур линзы: эллипс, срезанный сверху прямой (верхняя кромка авиатора).
function Glasses.outline(n)
	local L = Glasses.LENS
	local pts = {}
	local r = rad(L.rot)
	for i = 0, n - 1 do
		local t = rad(360 * i / n)
		-- суперэллипс: «квадратнее» обычного эллипса
		local c, sn = math.cos(t), math.sin(t)
		local x = L.a * math.sign(c) * math.abs(c) ^ (2 / L.e)
		local y = L.b * math.sign(sn) * math.abs(sn) ^ (2 / L.e)
		local u = L.cu + x * math.cos(r) - y * math.sin(r)
		local v = L.cv + x * math.sin(r) + y * math.cos(r)
		local top = L.top + L.topSlope * u
		table.insert(pts, { u, math.min(v, top) })
	end
	-- убрать почти совпадающие точки на срезе
	local out = {}
	for i, p in pts do
		local q = out[#out]
		if not q or (math.abs(q[1] - p[1]) + math.abs(q[2] - p[2])) > 0.02 then
			table.insert(out, p)
		end
	end
	return out
end

-- Левая/правая граница выпуклого контура на высоте v.
local function span(pts, v)
	local lo, hi = math.huge, -math.huge
	local n = #pts
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		if (a[2] - v) * (b[2] - v) <= 0 and math.abs(b[2] - a[2]) > 1e-6 then
			local t = (v - a[2]) / (b[2] - a[2])
			local u = a[1] + (b[1] - a[1]) * t
			lo = math.min(lo, u)
			hi = math.max(hi, u)
		elseif math.abs(a[2] - v) < 1e-6 then
			lo = math.min(lo, a[1])
			hi = math.max(hi, a[1])
		end
	end
	return lo, hi
end

function Glasses.build(g, opts)
	local rig = g.rig
	local G = rig:pivotOf("Glasses")
	local yellow = opts.glasses == "yellow"
	local lensColor = if yellow then P.lensYellow else P.lensAmber
	local lensT = if yellow then 0.42 else 0.32
	local frameD = 0.038
	local gold = P.frame
	local GM = "Foil"
	g.xf = nil
	local outline = Glasses.outline(28)
	local frames = {}
	for _, s in { 1, -1 } do
		-- плоскость линзы: -Z — наружу; разворот по лицу и наклон
		local frame = CFrame.new(G + V(s * Glasses.LENS_X, 0, Glasses.Z)) * CFrame.Angles(0, rad(-s * Glasses.WRAP), 0) * CFrame.Angles(rad(Glasses.TILT), 0, 0)
		frames[s] = frame
		-- контур в координатах этой линзы (для левой — зеркально)
		local pts = {}
		for i = #outline, 1, -1 do
			local p = outline[i]
			table.insert(pts, { s * p[1], p[2] })
		end
		if s == -1 then
			-- сохранить обход (зеркало меняет направление)
			local rev = {}
			for i = #pts, 1, -1 do
				table.insert(rev, pts[i])
			end
			pts = rev
		end
		-- ===== линза: горизонтальные ломтики =====
		local vmin, vmax = math.huge, -math.huge
		for _, p in pts do
			vmin = math.min(vmin, p[2])
			vmax = math.max(vmax, p[2])
		end
		local NS = 7
		local inset = 0.006
		for k = 0, NS - 1 do
			local v0 = vmin + inset + (vmax - vmin - 2 * inset) * k / NS
			local v1 = vmin + inset + (vmax - vmin - 2 * inset) * (k + 1) / NS
			local L0, R0 = span(pts, v0)
			local L1, R1 = span(pts, v1)
			g:trap("Glasses", frame, v0, v1, L0 + inset, L1 + inset, R0 - inset, R1 - inset, 0.016, lensColor, "Glass", 0, {
				transparency = lensT,
				reflectance = 0.12,
				castShadow = false,
				name = "Lens",
			})
		end
		-- ===== оправа по контуру =====
		local n = #pts
		for i = 1, n do
			local a, b = pts[i], pts[i % n + 1]
			local pa = frame * V(a[1], a[2], -0.004)
			local pb = frame * V(b[1], b[2], -0.004)
			local d = (pb - pa)
			if d.Magnitude > 1e-3 then
				local u = d.Unit
				g:cylSeg("Glasses", pa - u * frameD * 0.5, pb + u * frameD * 0.5, frameD, gold, GM, { name = "Frame" })
			end
		end
	end
	local function fp(s, u, v, z)
		return frames[s] * V(s * u, v, z or -0.004)
	end
	local L = Glasses.LENS
	-- верхняя планка: прямая от внешнего угла одной линзы до другой (поверх верхних кромок)
	local topOut = L.top + L.topSlope * 0.33
	local topIn = L.top + L.topSlope * -0.3
	local a1, a2 = fp(1, 0.335, topOut + 0.004, -0.012), fp(1, -0.3, topIn + 0.006, -0.012)
	local b1, b2 = fp(-1, -0.3, topIn + 0.006, -0.012), fp(-1, 0.335, topOut + 0.004, -0.012)
	g:cylSeg("Glasses", a1, a2, 0.042, gold, GM, { name = "BrowBar" })
	g:cylSeg("Glasses", b1, b2, 0.042, gold, GM, { name = "BrowBar" })
	g:cylSeg("Glasses", a2, b1, 0.04, gold, GM, { name = "BrowBar" })
	for _, p in { a1, a2, b1, b2 } do
		g:ball("Glasses", p, 0.046, gold, GM)
	end
	-- нижний мост: дуга между внутренними краями линз
	local ba, bb = fp(1, -0.31, 0.06), fp(-1, -0.31, 0.06)
	local bm = ba:Lerp(bb, 0.5) + V(0, 0.05, -0.012)
	local bq1, bq2 = ba:Lerp(bm, 0.55) + V(0, 0.018, -0.004), bb:Lerp(bm, 0.55) + V(0, 0.018, -0.004)
	local bridge = { ba, bq1, bm, bq2, bb }
	for i = 1, #bridge - 1 do
		local d = (bridge[i + 1] - bridge[i]).Unit
		g:cylSeg("Glasses", bridge[i] - d * 0.012, bridge[i + 1] + d * 0.012, 0.03, gold, GM, { name = "Bridge" })
	end
	-- носоупоры: прозрачные «капли» на золотых держателях
	for _, s in { 1, -1 } do
		local base = fp(s, -0.29, -0.02, 0.0)
		local pad = base + V(-s * 0.05, -0.06, 0.07)
		g:cylSeg("Glasses", base, pad, 0.014, gold, GM)
		g:box("Glasses", CFrame.new(pad) * CFrame.Angles(0, rad(s * 30), 0), V(0.035, 0.08, 0.02), P.tooth, "Glass", nil, { transparency = 0.4 })
	end
	-- шарниры и дужки (к ушам)
	for _, s in { 1, -1 } do
		local hinge = fp(s, 0.345, topOut - 0.03, 0.0)
		local back = hinge + V(s * 0.0, 0.0, 0.08)
		g:box("Glasses", Geo.axisX(hinge:Lerp(back, 0.5), back - hinge), V(0.1, 0.06, 0.035), gold, GM, nil, { name = "Hinge" })
		local mid = V(s * 0.6, G.Y + 0.17, -0.52)
		local ear = V(s * 0.56, G.Y + 0.2, -0.02)
		local tipEnd = V(s * 0.5, G.Y + 0.08, 0.14)
		g:cylSeg("Glasses", back, mid, 0.026, gold, GM, { name = "Temple" })
		g:cylSeg("Glasses", mid, ear, 0.024, gold, GM, { name = "Temple" })
		g:cylSeg("Glasses", ear, tipEnd, 0.03, P.frame:Lerp(P.goldDeep, 0.5), GM, { name = "Temple" })
		g:ball("Glasses", mid, 0.03, gold, GM)
		g:ball("Glasses", ear, 0.03, gold, GM)
	end
end

return Glasses
