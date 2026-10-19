--!nocheck
-- Торс: приталенный атласный пиджак 70-х (подплечники, широкие пиковые лацканы, распахнутые полы,
-- расклёшенная баска с клапанами карманов), ржаво-красная рубашка в горох с огромным воротником,
-- мех в вырезе, кубинская цепь (настоящие звенья-кольца, Foil), ремень из крокодиловой кожи,
-- пряжка «A» (Futura Bold), эмиттеры ChainSparkles / BuckleGlint / AuraSparkles и деталь BuckleFlare.
local roblox = require("@lune/roblox")
local lookAtFixed = require("../../lib/LookAt") -- CFrame.lookAt в Lune неверен
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local Drape = require("./Drape")
local P = require("./Palette")

local Body = {}

-- ===== Объёмы торса (UpperTorso), char space покоя =====
Body.E = {
	chest = { c = V(0, 4.15, 0.16), r = V(1.08, 0.85, 0.5) },
	yoke = { c = V(0, 4.48, 0.14), r = V(1.14, 0.45, 0.52) },
	neck = { c = V(0, 4.9, 0.12), r = V(0.62, 0.24, 0.56) },
	waist = { c = V(0, 3.38, 0.14), r = V(0.8, 0.58, 0.44) },
	shirt = { c = V(0, 3.8, -0.02), r = V(0.55, 1.0, 0.44) },
	fur = { c = V(0, 4.35, -0.1), r = V(0.38, 0.72, 0.38) },
	fur2 = { c = V(0, 4.88, -0.1), r = V(0.42, 0.26, 0.34) },
}
-- контуры (вид спереди, x — для правой стороны), общие для лацканов, воротника и выреза
Body.LAPEL_IN = { { 0.28, 3.5 }, { 0.33, 3.86 }, { 0.4, 4.22 }, { 0.46, 4.56 }, { 0.5, 4.84 } }
Body.LAPEL_OUT = { { 0.28, 3.5 }, { 0.55, 3.86 }, { 0.76, 4.22 }, { 0.93, 4.56 }, { 0.7, 4.74 } }
Body.COLLAR_IN = { { 0.38, 4.95 }, { 0.3, 4.7 }, { 0.22, 4.48 }, { 0.16, 4.3 } }
Body.COLLAR_OUT = { { 0.5, 4.97 }, { 0.68, 4.75 }, { 0.83, 4.45 }, { 0.34, 4.18 } }
Body.V_IN = { { 0.38, 4.95 }, { 0.29, 4.62 }, { 0.18, 4.25 }, { 0.07, 3.9 }, { 0.0, 3.72 } }
Body.V_OUT = { { 0.5, 4.97 }, { 0.43, 4.62 }, { 0.34, 4.25 }, { 0.25, 3.9 }, { 0.2, 3.72 } }
Body.BELT_Y = 2.96
Body.BELT_R = { 0.82, 0.52, 0.06 } -- rx, rz, центр z
Body.SATIN = { reflectance = 0.04 }

-- Плоскость с нормалью n (лицо смотрит по n), u ≈ вправо, v ≈ вверх.
local function planeFrame(origin, n)
	local z = -n.Unit
	local x = V(0, 1, 0):Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(origin, x, y, z)
end
Body.planeFrame = planeFrame

-- Пряжка «A» (Futura Bold): 4 многоугольника (две ноги, перекладина, верхний треугольник) с общими рёбрами.
-- H — высота, W — ширина основания, e > 0 — сужение контура (лицо), e < 0 — расширение (полированный кант).
local function aPolys(H, W, e)
	e = e or 0
	local ia = 0.66 * H -- вершина внутреннего треугольника (просвета)
	local ib = 0.22 * W -- внутренний край ноги у основания
	local cb, ct = 0.2 * H, 0.41 * H -- перекладина
	local dxo = e / math.cos(math.atan((W / 2) / H))
	local dxi = e / math.cos(math.atan(ib / ia))
	local function oL(y)
		return -W / 2 * (1 - y / H) + dxo
	end
	local function oR(y)
		return W / 2 * (1 - y / H) - dxo
	end
	local function iL(y)
		return -ib * (1 - y / ia) - dxi
	end
	local function iR(y)
		return ib * (1 - y / ia) + dxi
	end
	local Hn = H * (1 - 2 * dxo / W)
	local ian = ia * (1 + dxi / ib)
	local v0 = e
	return {
		{ { oL(v0), v0 }, { iL(v0), v0 }, { 0, ian }, { oL(ian), ian } },
		{ { iR(v0), v0 }, { oR(v0), v0 }, { oR(ian), ian }, { 0, ian } },
		{ { iL(cb + e), cb + e }, { iR(cb + e), cb + e }, { iR(ct - e), ct - e }, { iL(ct - e), ct - e } },
		{ { oL(ian), ian }, { oR(ian), ian }, { 0, Hn } },
	}, Hn
end
Body.aPolys = aPolys

-- та же «A» горизонтальными ломтиками (для подложки): { v0, v1, левый край(v), правый край(v) }
local function aPieces(H, W, e)
	e = e or 0
	local ia, ib = 0.66 * H, 0.22 * W
	local cb, ct = 0.2 * H, 0.41 * H
	local dxo = e / math.cos(math.atan((W / 2) / H))
	local dxi = e / math.cos(math.atan(ib / ia))
	local function oL(y)
		return -W / 2 * (1 - y / H) + dxo
	end
	local function oR(y)
		return W / 2 * (1 - y / H) - dxo
	end
	local function iL(y)
		return -ib * (1 - y / ia) - dxi
	end
	local function iR(y)
		return ib * (1 - y / ia) + dxi
	end
	local Hn = H * (1 - 2 * dxo / W)
	local ian = ia * (1 + dxi / ib)
	return {
		{ e, cb + e, oL, iL },
		{ e, cb + e, iR, oR },
		{ cb + e, ct - e, oL, oR },
		{ ct - e, ian, oL, iL },
		{ ct - e, ian, iR, oR },
		{ ian, Hn, oL, oR },
	}
end
Body.aPieces = aPieces

local function buildA(g, bone, frame, H, W, thick, color, mat, zoff, extra, e)
	local polys, Hn = aPolys(H, W, e)
	for _, pts in polys do
		g:poly(bone, frame, pts, thick, color, mat, zoff, extra)
	end
	return Hn
end
Body.buildA = buildA

local function emitter(part, name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rotation = roblox.NumberRange.new(0, 360)
	e.RotSpeed = roblox.NumberRange.new(-120, 120)
	e.SpreadAngle = roblox.Vector2.new(180, 180)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = true
	e.ZOffset = 0.6
	e.Enabled = false
	for k, v in props do
		e[k] = v
	end
	e.Parent = part
	return e
end
Body.emitter = emitter

local function seq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, roblox.NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return roblox.NumberSequence.new(kps)
end
Body.seq = seq

local function mirror(t, s)
	local out = {}
	for i, p in t do
		out[i] = { p[1] * s, p[2] }
	end
	return out
end

-- точка на горизонтальном эллипсе (rx, rz, центр cz) по углу th (0 — спереди, + — к +X)
local function ellPt(rx, rz, cz, y, th)
	return V(rx * math.sin(th), y, cz - rz * math.cos(th))
end

function Body.build(g, opts)
	local E = Body.E
	local SAT = Body.SATIN

	-- ===================== ПИДЖАК: корпус (UpperTorso) =====================
	g:ell("UpperTorso", E.chest.c, E.chest.r * 2, P.suit, "SmoothPlastic", nil, { name = "Jacket" })
	g:ell("UpperTorso", E.yoke.c, E.yoke.r * 2, P.suit, "SmoothPlastic")
	g:ell("UpperTorso", E.waist.c, E.waist.r * 2, P.suit, "SmoothPlastic")
	-- подплечники: квадратная линия плеч с лёгким скатом наружу
	for _, s in { 1, -1 } do
		g:ell("UpperTorso", V(s * 1.06, 4.6, 0.08), V(0.8, 0.4, 0.86), P.suit, "SmoothPlastic", V(0, 0, s * -9))
		g:ell("UpperTorso", V(s * 0.7, 4.7, 0.1), V(0.7, 0.36, 0.9), P.suit, "SmoothPlastic", V(0, 0, s * -14))
		-- проймы: мягкие складки к подмышке (тень)
		g:ellSeg("UpperTorso", V(s * 0.9, 4.05, -0.3), V(s * 1.0, 4.42, -0.22), 0.06, 0.04, P.suitDark, "SmoothPlastic", V(s, 0, -1))
		g:ellSeg("UpperTorso", V(s * 0.9, 4.05, 0.5), V(s * 1.0, 4.42, 0.44), 0.06, 0.04, P.suitDark, "SmoothPlastic", V(s, 0, 1))
	end
	-- шов по спине и вытачки (атласные блики ломаются)
	g:ellSeg("UpperTorso", V(0, 3.0, 0.565), V(0, 4.75, 0.61), 0.035, 0.03, P.suitDark, "SmoothPlastic", V(0, 0, 1))

	-- рубашка спереди (видна в распахе) и мех в вырезе
	g:ell("UpperTorso", E.shirt.c, E.shirt.r * 2, P.shirt, "Fabric", nil, { name = "Shirt" })
	g:ell("UpperTorso", E.fur.c, E.fur.r * 2, P.chestFur, "Carpet")
	g:ell("UpperTorso", E.fur2.c, E.fur2.r * 2, P.chestFur, "Carpet")

	local D = Drape.new(g, { E.chest, E.yoke, E.waist, E.shirt, E.fur, E.fur2, E.neck })
	local Dj = Drape.new(g, { E.chest, E.yoke, E.waist })
	-- седые пряди на груди (ломают ровную поверхность)
	for _, t in { { 0.0, 4.72, 0.12, 0.2 }, { 0.12, 4.5, 0.1, 0.6 }, { -0.1, 4.56, 0.11, 0.4 }, { 0.05, 4.28, 0.09, 0.8 }, { -0.08, 4.3, 0.08, 0.3 }, { 0.16, 4.78, 0.09, 0.5 }, { -0.17, 4.8, 0.09, 0.7 } } do
		g:ell("UpperTorso", D:cf(t[1], t[2], -0.01, (t[1] * 80)), V(t[3], t[3] * 2.2, 0.04), P.chestFur:Lerp(P.chestFrost, t[4]), "Carpet", nil, { castShadow = false })
	end

	-- ===== Планка рубашки: пуговицы, мягкий край выреза =====
	for i, y in { 3.92, 3.64, 3.36 } do
		g:ball("UpperTorso", (D:at(0.0, y, 0.01)), 0.05, P.shirtDark:Lerp(P.dot, 0.3), "SmoothPlastic")
	end
	g:ellSeg("UpperTorso", (D:at(0.0, 4.08, 0.0)), (D:at(0.0, 3.05, 0.0)), 0.025, 0.02, P.shirtDark, "Fabric", V(0, 0, -1))
	-- горошек на видимой части рубашки
	for _, d in { { 0.13, 3.98 }, { -0.13, 3.98 }, { 0.0, 3.82 }, { 0.15, 3.66 }, { -0.15, 3.66 }, { 0.0, 3.5 }, { 0.14, 3.34 }, { -0.14, 3.34 }, { 0.0, 3.18 }, { 0.15, 3.05 }, { -0.15, 3.05 } } do
		g:ell("UpperTorso", D:cf(d[1], d[2], 0.008, if d[1] > 0 then 20 else -20), V(0.05, 0.07, 0.012), P.dot, "SmoothPlastic", nil, { castShadow = false })
	end

	-- ===================== ВЫРЕЗ: края рубашки вдоль «V» (поверх меха) =====================
	for _, s in { 1, -1 } do
		local vin, vout = mirror(Body.V_IN, s), mirror(Body.V_OUT, s)
		D:strip("UpperTorso", vin, vout, 0.022, 0.024, P.shirt, "Fabric", { castShadow = true, name = "ShirtEdge" })
		D:rod("UpperTorso", vin, 0.026, 0.035, P.shirt:Lerp(P.shirtDark, 0.35), "Fabric", 0.16)
		for _, d in { { 0.42, 4.84 }, { 0.34, 4.56 }, { 0.25, 4.3 }, { 0.16, 4.02 }, { 0.09, 3.8 } } do
			g:ell("UpperTorso", D:cf(s * (d[1] + 0.02), d[2], 0.04, s * 20), V(0.05, 0.07, 0.012), P.dot, "SmoothPlastic", nil, { castShadow = false })
		end
	end

	-- ===================== ЛАЦКАНЫ (широкие, пиковые) и борта =====================
	local LAPEL = { reflectance = 0.06, castShadow = true, name = "Lapel" }
	for _, s in { 1, -1 } do
		-- внутренний край = линия раскепа (от точки перегиба к шее); наружный — к пику у плеча
		local inner, outer = mirror(Body.LAPEL_IN, s), mirror(Body.LAPEL_OUT, s)
		D:strip("UpperTorso", inner, outer, 0.042, 0.026, P.suitLight, "SmoothPlastic", LAPEL)
		local rim = table.clone(outer)
		table.insert(rim, inner[#inner])
		D:rod("UpperTorso", rim, 0.045, 0.034, P.suitLight:Lerp(P.suit, 0.35), "SmoothPlastic", 0.16, false, LAPEL)
		D:rod("UpperTorso", inner, 0.04, 0.05, P.suit:Lerp(P.suitLight, 0.3), "SmoothPlastic", 0.16, false, LAPEL)
		-- полы ниже перегиба: лежат поверх рубашки, ровный борт
		local fIn = mirror({ { 0.28, 3.52 }, { 0.28, 3.3 }, { 0.29, 3.06 } }, s)
		local fOut = mirror({ { 0.66, 3.52 }, { 0.66, 3.3 }, { 0.66, 3.06 } }, s)
		D:strip("UpperTorso", fIn, fOut, 0.03, 0.026, P.suit, "SmoothPlastic", { reflectance = 0.04, castShadow = true })
		D:rod("UpperTorso", fIn, 0.032, 0.038, P.suit, "SmoothPlastic", 0.16, false, { reflectance = 0.04 })
	end

	-- ===================== ОГРОМНЫЙ ВОРОТНИК РУБАШКИ (поверх лацканов) =====================
	for _, s in { 1, -1 } do
		local inner, outer = mirror(Body.COLLAR_IN, s), mirror(Body.COLLAR_OUT, s)
		D:strip("UpperTorso", inner, outer, 0.09, 0.03, P.shirt, "Fabric", { castShadow = true, name = "Collar" })
		local rim = table.clone(outer)
		table.insert(rim, inner[#inner])
		D:rod("UpperTorso", rim, 0.092, 0.032, P.shirtDark, "Fabric", 0.16)
		D:rod("UpperTorso", inner, 0.09, 0.04, P.shirt:Lerp(P.shirtDark, 0.25), "Fabric", 0.16)
		-- горошек на воротнике (сетка; только внутри контура)
		for _, d in { { 0.45, 4.88 }, { 0.42, 4.7 }, { 0.58, 4.72 }, { 0.36, 4.52 }, { 0.52, 4.54 }, { 0.68, 4.52 }, { 0.44, 4.36 }, { 0.6, 4.36 }, { 0.76, 4.42 }, { 0.36, 4.26 } } do
			g:ell("UpperTorso", D:cf(s * d[1], d[2], 0.108, s * 22), V(0.055, 0.075, 0.012), P.dot, "SmoothPlastic", nil, { castShadow = false })
		end
	end
	-- стойка воротника рубашки вокруг шеи сзади и воротник пиджака
	local back = {}
	for i = 0, 8 do
		local a = rad(-118 + i * 29.5)
		table.insert(back, V(0.52 * math.sin(a), 5.02 + 0.06 * math.cos(a) ^ 2, 0.12 + 0.52 * math.cos(a)))
	end
	g:caps("UpperTorso", back, 0.22, P.shirt, "SmoothPlastic", nil, nil, 0.5)
	local jback = {}
	for i = 0, 8 do
		local a = rad(-120 + i * 30)
		table.insert(jback, V(0.62 * math.sin(a), 4.88, 0.14 + 0.6 * math.cos(a)))
	end
	g:caps("UpperTorso", jback, 0.24, P.suit, "SmoothPlastic", nil, nil, 0.5)

	-- ===================== КУБИНСКАЯ ЦЕПЬ (настоящие звенья, Foil) =====================
	local Df = Drape.new(g, { E.fur, E.fur2, E.shirt, E.chest, E.yoke, E.neck })
	local function chainXY(th)
		local c = math.cos(th)
		return 0.47 * math.sin(th), 4.98 - 0.56 * (c * c) ^ 0.62
	end
	local N = 26
	local th0, th1 = rad(-80), rad(80)
	for i = 0, N - 1 do
		local th = th0 + (th1 - th0) * (i + 0.5) / N
		local x, y = chainXY(th)
		local x1, y1 = chainXY(th - 0.01)
		local x2, y2 = chainXY(th + 0.01)
		local p, n = Df:at(x, y, 0.045)
		local pa = Df:at(x1, y1, 0.045)
		local pb = Df:at(x2, y2, 0.045)
		local tng = (pb - pa).Unit
		local bin = (-n):Cross(tng).Unit
		local nrm = tng:Cross(bin).Unit
		local base = CFrame.fromMatrix(p + n * (if i % 2 == 0 then 0.012 else -0.006), tng, bin, nrm)
		-- звено наклонено в плоскости груди (рисунок «ёлочкой») и чуть повёрнуто вокруг длинной оси
		local cf = base * CFrame.Angles(0, 0, rad(-35)) * CFrame.Angles(rad(if i % 2 == 0 then 6 else -6), 0, 0)
		g:link("UpperTorso", cf, 0.19, 0.12, 0.045, if i % 2 == 0 then P.gold else P.gold:Lerp(P.goldDeep, 0.2), "Foil", { name = "ChainLink" })
	end
	-- эмиттер блеска цепи
	local chainHost = g:box("UpperTorso", V(0, 4.62, -0.5), V(0.9, 0.36, 0.25), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "ChainSparkleHost" })
	chainHost.CanQuery = false
	emitter(chainHost, "ChainSparkles", {
		Rate = 14,
		Lifetime = roblox.NumberRange.new(0.25, 0.5),
		Speed = roblox.NumberRange.new(0),
		Size = seq({ { 0, 0 }, { 0.35, 0.28 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 244, 200), Color3.fromRGB(255, 205, 90)),
		Transparency = seq({ { 0, 0 }, { 1, 0.2 } }),
	})

	-- ===================== ТАЗ В ДЖИНСАХ (LowerTorso) =====================
	g:ell("LowerTorso", V(0, 2.6, 0.06), V(1.96, 0.9, 1.12), P.jeans, "Fabric", nil, { name = "Jeans" })
	g:ell("LowerTorso", V(0, 2.95, 0.06), V(1.6, 0.6, 1.0), P.jeans, "Fabric")
	g:ellSeg("LowerTorso", V(0.06, 2.82, -0.5), V(0.03, 2.36, -0.47), 0.03, 0.02, P.jeansDark, "Fabric") -- шов ширинки
	g:ellSeg("LowerTorso", V(-0.02, 2.84, -0.5), V(0.1, 2.34, -0.475), 0.02, 0.016, P.seam, "Fabric", nil, { castShadow = false })

	-- ===================== БАСКА ПИДЖАКА: панели с чётким подолом (LowerTorso) =====================
	local yTop, yHem = 3.18, 2.32
	local topR, hemR = { 0.77, 0.48, 0.09 }, { 1.05, 0.68, 0.08 }
	local thA, thB = rad(22), rad(338)
	local NP = 12
	local function topP(th)
		return ellPt(topR[1], topR[2], topR[3], yTop, th)
	end
	local function hemP(th)
		-- спереди подол скошен (cutaway): полы короче у борта
		local k = math.max(0, math.cos(th))
		return ellPt(hemR[1], hemR[2], hemR[3], yHem + 0.12 * k * k, th)
	end
	for i = 0, NP - 1 do
		local a = thA + (thB - thA) * i / NP
		local b = thA + (thB - thA) * (i + 1) / NP
		local p1, p2, p3, p4 = topP(a), topP(b), hemP(b), hemP(a)
		local top, hem = (p1 + p2) / 2, (p3 + p4) / 2
		local xdir = ((p2 - p1) + (p3 - p4)).Unit
		local dn = (hem - top).Unit
		local outn = xdir:Cross(dn).Unit -- наружу (обход против часовой, если смотреть сверху)
		local zax = -outn
		local ydir = zax:Cross(xdir).Unit
		local cf = CFrame.fromMatrix((top + hem) / 2 + outn * 0.0, xdir, ydir, zax)
		local w = math.max((p3 - p4).Magnitude, (p2 - p1).Magnitude) + 0.03
		local col = if i % 2 == 0 then P.suit else P.suit:Lerp(P.suitLight, 0.1)
		g:box("LowerTorso", cf, V(w, (hem - top).Magnitude + 0.02, 0.045), col, "SmoothPlastic", nil, { reflectance = 0.04, name = "JacketSkirt" })
	end
	-- борт (торец полы) спереди и подол — тёмная кромка
	for _, th in { thA, thB } do
		g:cylSeg("LowerTorso", topP(th) + V(0, 0.04, 0), hemP(th), 0.05, P.suit, "SmoothPlastic")
	end
	-- клапаны карманов
	for _, s in { 1, -1 } do
		local th = if s == 1 then rad(62) else rad(298)
		local t = 0.62
		local c = topP(th):Lerp(hemP(th), t)
		local cl = topP(th - 0.12):Lerp(hemP(th - 0.12), t)
		local cr = topP(th + 0.12):Lerp(hemP(th + 0.12), t)
		local tng = (cr - cl).Unit
		local dn = (hemP(th) - topP(th)).Unit
		local out = dn:Cross(tng).Unit
		if out.Z > 0.2 or (out:Dot(V(c.X, 0, c.Z - 0.08)) < 0) then
			out = -out
		end
		local cf = CFrame.fromMatrix(c + out * 0.045, tng, -dn, -out)
		g:box("LowerTorso", cf * CFrame.new(0, -0.05, 0), V(0.4, 0.12, 0.035), P.suit:Lerp(P.suitLight, 0.2), "SmoothPlastic", nil, SAT)
		g:box("LowerTorso", cf * CFrame.new(0, 0.012, 0.004), V(0.42, 0.02, 0.03), P.suitDark, "SmoothPlastic")
	end

	-- ===================== РЕМЕНЬ (крокодил) =====================
	local by = Body.BELT_Y
	local BR = Body.BELT_R
	local belt = {}
	for deg = -110, 110, 10 do
		local a = rad(deg)
		table.insert(belt, ellPt(BR[1], BR[2], BR[3], by, a))
	end
	for i = 1, #belt - 1 do
		local a, b = belt[i], belt[i + 1]
		local d = b - a
		g:box("LowerTorso", Geo.axisX((a + b) / 2, d), V(d.Magnitude + 0.02, 0.24, 0.05), P.belt, "Leather", nil, { reflectance = 0.04, name = "Belt" })
	end
	-- чешуя крокодила спереди (2 ряда плиток), видна в распахе
	for i = -6, 6 do
		for row = 0, 1 do
			local a = (i + row * 0.5) * 0.085
			local p = ellPt(BR[1] + 0.028, BR[2] + 0.028, BR[3], by + (if row == 0 then 0.055 else -0.055), a)
			local nrm = V(math.sin(a) / BR[1], 0, -math.cos(a) / BR[2]).Unit
			local cf = lookAtFixed(p, p + nrm)
			local shade = if (i + row) % 3 == 0 then P.croc else P.belt:Lerp(P.croc, 0.55)
			g:box("LowerTorso", cf, V(0.075, 0.075, 0.012), shade, "Leather", nil, { reflectance = 0.06, castShadow = false })
		end
	end
	-- шлёвки джинсов
	for _, x in { -0.4, 0.4 } do
		local a = math.asin(x / BR[1])
		local p = ellPt(BR[1] + 0.04, BR[2] + 0.04, BR[3], by, a)
		local nrm = V(math.sin(a) / BR[1], 0, -math.cos(a) / BR[2]).Unit
		g:box("LowerTorso", lookAtFixed(p, p + nrm), V(0.07, 0.32, 0.025), P.jeansDark, "Fabric")
	end

	-- ===================== ПРЯЖКА «A» =====================
	local AH, AW = 0.64, 0.58
	local zA = BR[3] - BR[2] - 0.06
	local aFrame = CFrame.new(0, by - 0.26, zA)
	-- полированный кант (задняя пластина чуть больше), подложка цвета лица (другая разбивка — закрывает
	-- волосяные щели между клиньями) и сатиновое лицо (точный контур, выступает вперёд)
	buildA(g, "LowerTorso", aFrame, AH, AW, 0.05, P.buckleSide, "Foil", 0.012, { name = "Buckle" }, -0.016)
	for _, pc in aPieces(AH, AW, 0.002) do
		g:trap("LowerTorso", aFrame, pc[1], pc[2], pc[3](pc[1]), pc[3](pc[2]), pc[4](pc[1]), pc[4](pc[2]), 0.02, P.champagne, "Metal", -0.022, { name = "Buckle" })
	end
	buildA(g, "LowerTorso", aFrame, AH, AW, 0.022, P.champagne, "Metal", -0.044, { name = "Buckle" }, 0)
	local apex = aFrame * V(0, AH - 0.01, -0.06)
	local flare = g:ball("LowerTorso", apex, 0.16, Color3.new(1, 1, 1), "Neon", { transparency = 1, castShadow = false, name = "BuckleFlare" })
	flare.CanQuery = false
	local glintHost = g:box("LowerTorso", apex, V(0.06, 0.06, 0.06), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "BuckleGlintHost" })
	glintHost.CanQuery = false
	emitter(glintHost, "BuckleGlint", {
		Rate = 4,
		Lifetime = roblox.NumberRange.new(0.3, 0.45),
		Speed = roblox.NumberRange.new(0),
		Size = seq({ { 0, 0 }, { 0.3, 0.9 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 250, 225)),
		RotSpeed = roblox.NumberRange.new(-40, 40),
		ZOffset = 1.5,
	})

	-- ===================== Аура (трон) =====================
	local auraHost = g:box("UpperTorso", V(0, 3.8, 0), V(3.4, 5.6, 2.2), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "AuraHost" })
	auraHost.CanQuery = false
	emitter(auraHost, "AuraSparkles", {
		Enabled = opts.sparkles == true,
		Rate = 26,
		Lifetime = roblox.NumberRange.new(0.8, 1.6),
		Speed = roblox.NumberRange.new(0.2, 0.6),
		Acceleration = V(0, 0.6, 0),
		Drag = 1,
		Size = seq({ { 0, 0 }, { 0.25, 0.22 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 190, 70)),
		Transparency = seq({ { 0, 0.1 }, { 1, 0.6 } }),
		LockedToPart = false,
	})
end

return Body
