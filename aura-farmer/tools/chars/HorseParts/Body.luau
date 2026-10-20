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
	chest = { c = V(0, 4.12, 0.14), r = V(0.97, 0.84, 0.5) },
	yoke = { c = V(0, 4.48, 0.15), r = V(1.0, 0.44, 0.5) },
	neck = { c = V(0, 4.9, 0.12), r = V(0.62, 0.24, 0.56) },
	waist = { c = V(0, 3.36, 0.14), r = V(0.74, 0.56, 0.42) },
	shirt = { c = V(0, 3.78, -0.02), r = V(0.52, 1.0, 0.42) },
	fur = { c = V(0, 4.36, -0.1), r = V(0.36, 0.7, 0.38) },
	fur2 = { c = V(0, 4.86, -0.1), r = V(0.42, 0.26, 0.34) },
}
-- контуры (вид спереди, x — для правой стороны), общие для лацканов, воротника и выреза
-- лацкан: внутренний край (линия раскепа) и наружный (с пиком у плеча); пары точек сверху вниз
Body.LAPEL_IN = { { 0.5, 4.93 }, { 0.45, 4.64 }, { 0.39, 4.28 }, { 0.33, 3.9 }, { 0.28, 3.5 } }
Body.LAPEL_OUT = { { 0.62, 4.88 }, { 0.82, 4.74 }, { 0.8, 4.36 }, { 0.6, 3.94 }, { 0.29, 3.5 } }
-- воротник рубашки: длинные острые «листья» поверх лацканов
Body.COLLAR = { { 0.36, 4.99 }, { 0.52, 5.0 }, { 0.68, 4.8 }, { 0.73, 4.56 }, { 0.3, 4.02 }, { 0.25, 4.3 }, { 0.29, 4.7 } }
Body.V_IN = { { 0.36, 4.95 }, { 0.28, 4.62 }, { 0.18, 4.25 }, { 0.08, 3.92 }, { 0.0, 3.76 } }
Body.V_OUT = { { 0.48, 4.97 }, { 0.41, 4.62 }, { 0.32, 4.25 }, { 0.22, 3.92 }, { 0.16, 3.76 } }
Body.BELT_Y = 2.96
Body.BELT_R = { 0.81, 0.51, 0.06 } -- rx, rz, центр z
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

-- та же «A» горизонтальными ломтиками: { v0, v1, левый край(v), правый край(v) }.
-- eo — сдвиг наружного контура (> 0 — внутрь), ei — сдвиг контуров просветов (> 0 — просвет больше).
local function aPieces(H, W, eo, ei)
	eo = eo or 0
	ei = ei or eo
	local ia, ib = 0.66 * H, 0.22 * W
	local cb, ct = 0.2 * H, 0.41 * H
	local dxo = eo / math.cos(math.atan((W / 2) / H))
	local dxi = ei / math.cos(math.atan(ib / ia))
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
		{ eo, cb + ei, oL, iL },
		{ eo, cb + ei, iR, oR },
		{ cb + ei, ct - ei, oL, oR },
		{ ct - ei, ian, oL, iL },
		{ ct - ei, ian, iR, oR },
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
	-- подплечники: широкая квадратная линия плеч с лёгким скатом наружу, чёткий край над рукавом
	for _, s in { 1, -1 } do
		g:ell("UpperTorso", V(s * 0.98, 4.66, 0.1), V(1.02, 0.34, 0.94), P.suit, "SmoothPlastic", V(0, 0, s * -6), { name = "ShoulderPad" })
		g:ell("UpperTorso", V(s * 0.62, 4.74, 0.1), V(0.72, 0.34, 0.92), P.suit, "SmoothPlastic", V(0, 0, s * -14))
		-- подмышка (закрывает щель между боком и рукавом при подъёме руки)
		g:ell("UpperTorso", V(s * 1.0, 4.28, 0.1), V(0.5, 0.72, 0.74), P.suit:Lerp(P.suitDark, 0.25), "SmoothPlastic")
	end

	-- рубашка спереди (видна в распахе) и мех в вырезе
	g:ell("UpperTorso", E.shirt.c, E.shirt.r * 2, P.shirt, "SmoothPlastic", nil, { name = "Shirt" })
	g:ell("UpperTorso", E.fur.c, E.fur.r * 2, P.chestFur, "SmoothPlastic")
	g:ell("UpperTorso", E.fur2.c, E.fur2.r * 2, P.chestFur, "SmoothPlastic")

	local D = Drape.new(g, { E.chest, E.yoke, E.waist, E.shirt, E.fur, E.fur2, E.neck })
	-- седые пряди на груди (ломают ровную поверхность)
	for _, t in { { 0.0, 4.7, 0.12, 0.25 }, { 0.12, 4.5, 0.1, 0.6 }, { -0.1, 4.56, 0.11, 0.45 }, { 0.05, 4.28, 0.09, 0.8 }, { -0.08, 4.3, 0.08, 0.35 }, { 0.17, 4.78, 0.09, 0.5 }, { -0.18, 4.8, 0.09, 0.7 }, { 0.0, 4.05, 0.07, 0.5 } } do
		g:ell("UpperTorso", D:cf(t[1], t[2], -0.012, t[1] * 80), V(t[3], t[3] * 2.4, 0.04), P.chestFur:Lerp(P.chestFrost, t[4]), "SmoothPlastic", nil, { castShadow = false })
	end

	-- ===== Рубашка: пуговицы, горошек =====
	for _, y in { 3.62, 3.34 } do
		g:ball("UpperTorso", (D:at(0.0, y, 0.012)), 0.05, P.shirtDark:Lerp(P.dot, 0.3), "SmoothPlastic")
	end
	g:ellSeg("UpperTorso", (D:at(0.0, 3.74, 0.0)), (D:at(0.0, 3.05, 0.0)), 0.025, 0.02, P.shirtDark, "SmoothPlastic", V(0, 0, -1), { castShadow = false })
	for _, d in { { 0.14, 3.7 }, { -0.14, 3.7 }, { 0.07, 3.5 }, { -0.21, 3.52 }, { 0.2, 3.32 }, { -0.08, 3.3 }, { 0.12, 3.12 }, { -0.16, 3.12 } } do
		g:ell("UpperTorso", D:cf(d[1], d[2], 0.008, if d[1] > 0 then 20 else -20), V(0.06, 0.075, 0.012), P.dot, "SmoothPlastic", nil, { castShadow = false })
	end

	-- ===================== ВЫРЕЗ: края рубашки вдоль «V» (поверх меха) =====================
	for _, s in { 1, -1 } do
		local vin, vout = mirror(Body.V_IN, s), mirror(Body.V_OUT, s)
		D:strip("UpperTorso", vin, vout, 0.022, 0.024, P.shirt, "Fabric", { castShadow = true, name = "ShirtEdge" })
		D:rod("UpperTorso", vin, 0.026, 0.035, P.shirt:Lerp(P.shirtDark, 0.35), "Fabric", 0.34)
		for _, d in { { 0.42, 4.84 }, { 0.3, 4.4 }, { 0.2, 4.06 } } do
			g:ell("UpperTorso", D:cf(s * (d[1] + 0.02), d[2], 0.04, s * 20), V(0.055, 0.07, 0.012), P.dot, "SmoothPlastic", nil, { castShadow = false })
		end
	end

	-- ===================== ЛАЦКАНЫ (широкие, пиковые) и борта =====================
	-- атласная лента по поверхности груди (внутренний край — линия раскепа, наружный — с пиком у плеча)
	local LAPEL = { reflectance = 0.06, castShadow = true, name = "Lapel" }
	for _, s in { 1, -1 } do
		local inner, outer = mirror(Body.LAPEL_IN, s), mirror(Body.LAPEL_OUT, s)
		D:strip("UpperTorso", inner, outer, 0.045, 0.03, P.suitLight, "SmoothPlastic", LAPEL)
		-- кант по наружному краю (чёткая кромка) и мягкий перегиб по линии раскепа
		D:rod("UpperTorso", outer, 0.048, 0.034, P.suitLight:Lerp(P.suit, 0.45), "SmoothPlastic", 0.34, false, LAPEL)
		D:rod("UpperTorso", inner, 0.042, 0.05, P.suit:Lerp(P.suitLight, 0.5), "SmoothPlastic", 0.4, false, LAPEL)
		-- петлица на лацкане
		g:ellSeg("UpperTorso", D:at(s * 0.6, 4.42, 0.075), D:at(s * 0.69, 4.47, 0.075), 0.028, 0.02, P.suitDark, "SmoothPlastic", nil, { castShadow = false })
		-- полы ниже точки перегиба: ровный борт поверх рубашки
		local fIn = mirror({ { 0.27, 3.52 }, { 0.3, 3.3 }, { 0.33, 3.06 } }, s)
		local fOut = mirror({ { 0.6, 3.52 }, { 0.62, 3.3 }, { 0.64, 3.06 } }, s)
		D:strip("UpperTorso", fIn, fOut, 0.03, 0.026, P.suit, "SmoothPlastic", { reflectance = 0.04, castShadow = true })
		D:rod("UpperTorso", fIn, 0.032, 0.04, P.suit:Lerp(P.suitLight, 0.25), "SmoothPlastic", 0.3, false, { reflectance = 0.04 })
		-- пуговица у точки перегиба
		g:cylSeg("UpperTorso", D:at(s * 0.4, 3.46, 0.04), D:at(s * 0.4, 3.46, 0.075), 0.09, P.suitDark, "SmoothPlastic")
	end

	-- ===================== ОГРОМНЫЙ ВОРОТНИК РУБАШКИ (поверх лацканов) =====================
	-- длинный острый «лист» — одна плоская панель (Fabric), кант, горошек
	local Dc = Drape.new(g, { E.chest, E.yoke, E.waist, E.shirt, E.fur })
	for _, s in { 1, -1 } do
		local pts = mirror(Body.COLLAR, s)
		if s < 0 then
			local r = {}
			for i = #pts, 1, -1 do
				table.insert(r, pts[i])
			end
			pts = r
		end
		-- верх «листа» уходит за шею (не поднимает плоскость): подъём считаем только по нижним точкам
		local f, p2 = Dc:flat("UpperTorso", pts, 0.075, 0.03, P.shirt, "Fabric", { castShadow = true, name = "Collar" }, "center", if s > 0 then { true, true } else { [6] = true, [7] = true })
		g:outline("UpperTorso", f, p2, 0.026, P.shirt:Lerp(P.shirtDark, 0.35), "Fabric", -0.03)
		-- горошек: сетка в плоскости воротника, только внутри контура
		local inset = Geo.inset(p2, 0.05)
		local function inside(u, v)
			local n = #inset
			local sgn = 0
			for i = 1, n do
				local a, b = inset[i], inset[i % n + 1]
				local cr = (b[1] - a[1]) * (v - a[2]) - (b[2] - a[2]) * (u - a[1])
				local sc = if cr > 0 then 1 else -1
				if sgn == 0 then
					sgn = sc
				elseif sc ~= sgn then
					return false
				end
			end
			return true
		end
		for iy = -6, 6 do
			for ix = -6, 6 do
				local u = ix * 0.15 + (iy % 2) * 0.075
				local v = iy * 0.13
				if inside(u, v) then
					g:ell("UpperTorso", f * CFrame.new(u, v, -0.034) * CFrame.Angles(0, 0, rad(s * 25)), V(0.058, 0.074, 0.012), P.dot, "SmoothPlastic", nil, { castShadow = false })
				end
			end
		end
	end
	-- стойка воротника рубашки вокруг шеи сзади и воротник пиджака
	-- сзади: стойка воротника рубашки чуть выглядывает над воротником пиджака (гладкие полудиски вокруг шеи)
	g:ell("UpperTorso", V(0, 5.0, 0.3), V(1.08, 0.24, 0.84), P.shirt, "SmoothPlastic", nil, { name = "ShirtCollarBack" })
	g:ell("UpperTorso", V(0, 4.9, 0.33), V(1.26, 0.26, 0.98), P.suit, "SmoothPlastic", nil, { name = "JacketCollarBack" })

	-- ===================== КУБИНСКАЯ ЦЕПЬ (звенья — скруглённые прямоугольники из 4 цилиндров, Foil) =====================
	local Df = Drape.new(g, { E.fur, E.fur2, E.shirt, E.chest, E.yoke, E.neck })
	local function chainXY(th)
		local c = math.cos(th)
		return 0.44 * math.sin(th), 4.98 - 0.54 * (c * c) ^ 0.62
	end
	-- равномерный шаг по длине дуги
	local samples = {}
	local acc = 0
	local prev
	local th0, th1 = rad(-70), rad(70)
	for k = 0, 400 do
		local th = th0 + (th1 - th0) * k / 400
		local x, y = chainXY(th)
		local p = Df:at(x, y, 0.05)
		if prev then
			acc += (p - prev).Magnitude
		end
		table.insert(samples, { acc, th })
		prev = p
	end
	local N = 20
	local idx = 1
	for i = 0, N - 1 do
		local target = acc * (i + 0.5) / N
		while idx < #samples and samples[idx + 1][1] < target do
			idx += 1
		end
		local th = samples[idx][2]
		local x, y = chainXY(th)
		local x1, y1 = chainXY(th - 0.01)
		local x2, y2 = chainXY(th + 0.01)
		local p, n = Df:at(x, y, 0.05)
		local tng = (Df:at(x2, y2, 0.05) - Df:at(x1, y1, 0.05)).Unit
		local bin = (-n):Cross(tng).Unit
		local nrm = tng:Cross(bin).Unit
		local base = CFrame.fromMatrix(p + n * (if i % 2 == 0 then 0.016 else -0.006), tng, bin, nrm)
		-- звенья лежат плашмя, повёрнуты по диагонали (рисунок «ёлочкой») и чередуют наклон — сцепляются
		local cf = base * CFrame.Angles(0, 0, rad(-35)) * CFrame.Angles(rad(if i % 2 == 0 then 6 else -6), 0, 0)
		local col = if i % 3 == 0 then P.gold else P.gold:Lerp(P.goldDeep, if i % 3 == 1 then 0.18 else 0.08)
		g:link("UpperTorso", cf, 0.2, 0.125, 0.048, col, "Foil", { name = "ChainLink" }) -- скруглённый прямоугольник из 4 цилиндров
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
	g:ell("LowerTorso", V(0, 2.6, 0.06), V(1.84, 0.9, 1.06), P.jeans, "SmoothPlastic", nil, { name = "Jeans" })
	g:ell("LowerTorso", V(0, 2.95, 0.06), V(1.6, 0.6, 1.0), P.jeans, "SmoothPlastic")
	g:ellSeg("LowerTorso", V(0.06, 2.8, -0.5), V(0.03, 2.36, -0.47), 0.03, 0.02, P.jeansDark, "SmoothPlastic", nil, { castShadow = false }) -- шов ширинки
	g:ellSeg("LowerTorso", V(-0.02, 2.82, -0.505), V(0.1, 2.34, -0.48), 0.02, 0.016, P.seam, "SmoothPlastic", nil, { castShadow = false })

	-- ===================== ПОЛЫ ПИДЖАКА: гладкие панели с чётким подолом (LowerTorso) =====================
	local yTop, yHem = 3.34, 2.34
	local topR, hemR = { 0.76, 0.46, 0.12 }, { 1.04, 0.7, 0.1 }
	local function thFront(k) -- угол борта: спереди полы расходятся (cutaway)
		return rad(24 + 18 * k)
	end
	local NP = 16
	local function topP(th)
		return ellPt(topR[1], topR[2], topR[3], yTop, th)
	end
	local function hemP(th)
		local k = math.max(0, math.cos(th))
		return ellPt(hemR[1], hemR[2], hemR[3], yHem + 0.1 * k * k, th)
	end
	for i = 0, NP - 1 do
		local a0 = thFront(0) + (rad(360) - 2 * thFront(0)) * i / NP
		local a1 = thFront(0) + (rad(360) - 2 * thFront(0)) * (i + 1) / NP
		local b0 = thFront(1) + (rad(360) - 2 * thFront(1)) * i / NP
		local b1 = thFront(1) + (rad(360) - 2 * thFront(1)) * (i + 1) / NP
		local p1, p2, p3, p4 = topP(a0), topP(a1), hemP(b1), hemP(b0)
		local top, hem = (p1 + p2) / 2, (p3 + p4) / 2
		local xdir = ((p2 - p1) + (p3 - p4)).Unit
		local dn = (hem - top).Unit
		local outn = xdir:Cross(dn).Unit
		local ydir = (-outn):Cross(xdir).Unit
		local cf = CFrame.fromMatrix((top + hem) / 2, xdir, ydir, -outn)
		local w = math.max((p3 - p4).Magnitude, (p2 - p1).Magnitude) + 0.035
		g:box("LowerTorso", cf, V(w, (hem - top).Magnitude + 0.02, 0.045), P.suit, "SmoothPlastic", nil, { reflectance = 0.04, name = "JacketSkirt" })
	end
	-- борта пол (кант) и подол
	for _, sgn in { 1, -1 } do
		local a, b = topP(sgn * thFront(0)) + V(0, 0.08, 0), hemP(sgn * thFront(1))
		local dv = (b - a).Unit
		local outn = V(sgn * 0.3, 0, -1).Unit
		g:cylSeg("LowerTorso", a + outn * 0.012, b + outn * 0.012 + dv * 0.02, 0.055, P.suit:Lerp(P.suitLight, 0.25), "SmoothPlastic", SAT)
	end
	-- клапаны карманов (лежат на полах)
	for _, s in { 1, -1 } do
		local th = s * rad(66)
		local t = 0.55
		local c = topP(th):Lerp(hemP(th), t)
		local cl = topP(th - 0.14):Lerp(hemP(th - 0.14), t)
		local cr = topP(th + 0.14):Lerp(hemP(th + 0.14), t)
		local tng = (cr - cl).Unit
		local outn = V(math.sin(th) / hemR[1], 0, -math.cos(th) / hemR[2]).Unit
		local up = (-outn):Cross(tng).Unit
		if up.Y < 0 then
			up = -up
			tng = -tng
		end
		local cf = CFrame.fromMatrix(c + outn * 0.04, tng, up, -tng:Cross(up).Unit)
		cf = CFrame.fromMatrix(c + outn * 0.045, tng, up, tng:Cross(up))
		g:box("LowerTorso", cf * CFrame.new(0, -0.05, 0), V(0.42, 0.13, 0.03), P.suit:Lerp(P.suitLight, 0.15), "SmoothPlastic", nil, SAT)
		g:box("LowerTorso", cf * CFrame.new(0, 0.017, 0.006), V(0.44, 0.02, 0.026), P.suitDark, "SmoothPlastic")
	end

	-- ===================== РЕМЕНЬ (крокодил) =====================
	local by = Body.BELT_Y
	local BR = Body.BELT_R
	local belt = {}
	for deg = -180, 180, 15 do
		table.insert(belt, ellPt(BR[1], BR[2], BR[3], by, rad(deg)))
	end
	for i = 1, #belt - 1 do
		local a, b = belt[i], belt[i + 1]
		local d = b - a
		g:box("LowerTorso", Geo.axisX((a + b) / 2, d), V(d.Magnitude + 0.035, 0.24, 0.05), P.belt, "Leather", nil, { reflectance = 0.04, name = "Belt" })
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
	for _, x in { -0.52, 0.52 } do
		local a = math.asin(x / BR[1])
		local p = ellPt(BR[1] + 0.035, BR[2] + 0.035, BR[3], by, a)
		local nrm = V(math.sin(a) / BR[1], 0, -math.cos(a) / BR[2]).Unit
		g:box("LowerTorso", lookAtFixed(p, p + nrm), V(0.06, 0.3, 0.022), P.jeans:Lerp(P.jeansDark, 0.5), "Fabric")
	end

	-- ===================== ПРЯЖКА «A» =====================
	-- горизонтальные ломтики (Block + Wedge): лицо — сатиновое шампанское, за ним полированный кант (чуть больше)
	local AH, AW = 0.64, 0.58
	local zA = BR[3] - BR[2] - 0.07
	local aFrame = CFrame.new(0, by - 0.26, zA)
	for _, pc in aPieces(AH, AW, -0.02, 0.004) do
		g:trap("LowerTorso", aFrame, pc[1], pc[2], pc[3](pc[1]), pc[3](pc[2]), pc[4](pc[1]), pc[4](pc[2]), 0.05, P.buckleSide, "Foil", 0.012, { name = "Buckle" })
	end
	for _, pc in aPieces(AH, AW, 0.0) do
		g:trap("LowerTorso", aFrame, pc[1], pc[2], pc[3](pc[1]), pc[3](pc[2]), pc[4](pc[1]), pc[4](pc[2]), 0.026, P.champagne, "Metal", -0.024, { name = "Buckle" })
	end
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
