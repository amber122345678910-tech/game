--!nocheck
-- Торс: пиджак (широкие лацканы), рубашка в горох с огромным воротником, мех в вырезе,
-- кубинская цепь, ремень из крокодиловой кожи с пряжкой «A», таз в джинсах, эмиттеры.
local roblox = require("@lune/roblox")
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

-- Плоскость с нормалью n (лицо смотрит по n), u ≈ вправо, v ≈ вверх.
local function planeFrame(origin, n)
	local z = -n.Unit
	local x = V(0, 1, 0):Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(origin, x, y, z)
end
Body.planeFrame = planeFrame

-- Пряжка «A» (Futura Bold): трапеции между прямыми; H — высота, W — ширина, e — сужение контура внутрь.
local function aPieces(H, W, e)
	e = e or 0
	local ia = 0.64 * H -- вершина внутреннего треугольника
	local ib = 0.2 * W -- внутренний край ноги у основания
	local cb, ct = 0.18 * H, 0.37 * H
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

local function buildA(g, bone, frame, H, W, thick, color, mat, zoff, extra, e)
	for _, pc in aPieces(H, W, e) do
		local v0, v1, L, R = pc[1], pc[2], pc[3], pc[4]
		g:trap(bone, frame, v0, v1, L(v0), L(v1), R(v0), R(v1), thick, color, mat, zoff, extra)
	end
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

function Body.build(g, opts)
	local rig = g.rig

	-- ===== Корпус (UpperTorso): пиджак, рубашка, мех =====
	local E = {
		chest = { c = V(0, 3.98, 0.1), r = V(1.12, 1.3, 0.58) },
		waist = { c = V(0, 3.32, 0.1), r = V(1.01, 0.65, 0.54) },
		shirt = { c = V(0, 3.8, -0.2), r = V(0.525, 1.0, 0.38) },
		fur = { c = V(0, 4.48, -0.3), r = V(0.36, 0.58, 0.255) },
		fur2 = { c = V(0, 4.86, -0.2), r = V(0.4, 0.26, 0.31) },
		shoulder = { c = V(0, 4.6, 0.06), r = V(1.42, 0.29, 0.29) },
	}
	g:ell("UpperTorso", E.chest.c, E.chest.r * 2, P.suit, "SmoothPlastic")
	g:ell("UpperTorso", E.waist.c, E.waist.r * 2, P.suit, "SmoothPlastic")
	g:tube("UpperTorso", { V(-1.12, 4.6, 0.06), V(1.12, 4.6, 0.06) }, 0.58, P.suit, "SmoothPlastic") -- линия плеч
	for _, s in { 1, -1 } do
		g:tube("UpperTorso", { V(s * 0.36, 4.88, 0.14), V(s * 1.08, 4.66, 0.08) }, 0.5, P.suit, "SmoothPlastic") -- скат плеч
	end
	g:ell("UpperTorso", E.shirt.c, E.shirt.r * 2, P.shirt, "Fabric")
	g:ell("UpperTorso", E.fur.c, E.fur.r * 2, P.chestFur, "Carpet")
	g:ell("UpperTorso", E.fur2.c, E.fur2.r * 2, P.chestFur, "Carpet")
	-- пучки шерсти на груди (ломают ровную поверхность)
	for _, t in { { 0.0, 4.66, 0.16 }, { 0.1, 4.32, 0.12 }, { -0.1, 4.4, 0.13 }, { 0.04, 4.05, 0.1 } } do
		local dr = Drape.new(g, { E.fur, E.fur2 })
		g:ell("UpperTorso", dr:cf(t[1], t[2], -0.015, 0), V(t[3], t[3] * 1.6, 0.06), P.chestFur:Lerp(P.furGrey, 0.35), "Carpet")
	end

	local D = Drape.new(g, { E.chest, E.waist, E.shirt, E.fur, E.fur2, E.shoulder })

	-- ===== Планки рубашки: внутренние края образуют глубокий V =====
	for _, s in { 1, -1 } do
		local inner = { { s * 0.37, 4.98 }, { s * 0.25, 4.5 }, { s * 0.12, 4.02 }, { 0.0, 3.54 } }
		local outer = { { s * 0.5, 4.98 }, { s * 0.5, 4.5 }, { s * 0.5, 4.02 }, { s * 0.5, 3.54 } }
		D:strip("UpperTorso", inner, outer, 0.012, 0.012, P.shirt, "Fabric")
		D:tube("UpperTorso", { { s * 0.012, 3.56 }, { s * 0.37, 4.96 } }, 0.02, 0.03, P.shirtDark, "Fabric", 0.4)
	end
	-- горошек на рубашке (видимая часть)
	for _, d in { { 0.2, 4.42 }, { 0.3, 4.75 }, { 0.12, 3.95 }, { -0.2, 4.42 }, { -0.3, 4.75 }, { -0.12, 3.95 }, { 0.0, 3.4 }, { 0.22, 3.62 }, { -0.22, 3.62 }, { 0.12, 3.2 }, { -0.12, 3.2 }, { 0.3, 3.3 }, { -0.3, 3.3 }, { 0.25, 4.1 }, { -0.25, 4.1 } } do
		local x, y = d[1], d[2]
		local vEdge = 3.55 + math.abs(x) / 0.37 * 1.43 -- над этой высотой — вырез (мех)
		if y < vEdge - 0.06 then
			g:ell("UpperTorso", D:cf(x, y, 0.024, if x > 0 then 25 else -25), V(0.05, 0.072, 0.014), P.dot, "SmoothPlastic")
		end
	end

	-- ===== Лацканы пиджака =====
	for _, s in { 1, -1 } do
		local function m(t)
			for _, p in t do
				p[1] *= s
			end
			return t
		end
		local inner = m({ { 0.34, 4.9 }, { 0.31, 4.45 }, { 0.28, 3.95 }, { 0.25, 3.42 } })
		local outer = m({ { 0.66, 4.86 }, { 0.88, 4.5 }, { 0.6, 3.92 }, { 0.25, 3.42 } })
		D:strip("UpperTorso", inner, outer, 0.04, 0.014, P.suitLight, "SmoothPlastic")
		-- верхняя кромка до пика лацкана
		D:strip("UpperTorso", m({ { 0.62, 4.88 }, { 0.66, 4.86 } }), m({ { 0.9, 4.66 }, { 0.88, 4.5 } }), 0.04, 0.014, P.suitLight, "SmoothPlastic")
		-- закатанная кромка лацкана
		D:tube("UpperTorso", m({ { 0.62, 4.88 }, { 0.9, 4.66 }, { 0.88, 4.5 }, { 0.75, 4.2 }, { 0.6, 3.92 }, { 0.42, 3.66 }, { 0.25, 3.42 }, { 0.28, 3.95 }, { 0.31, 4.45 }, { 0.34, 4.9 } }), 0.045, 0.055, P.suitLight, "SmoothPlastic", 0.3)
	end

	-- ===== Огромный воротник рубашки (поверх лацканов) =====
	for _, s in { 1, -1 } do
		local function m(t)
			for _, p in t do
				p[1] *= s
			end
			return t
		end
		local top = m({ { 0.13, 4.9 }, { 0.38, 5.02 }, { 0.6, 4.8 }, { 0.76, 4.42 }, { 0.84, 4.12 } })
		local bot = m({ { 0.13, 4.9 }, { 0.2, 4.68 }, { 0.38, 4.52 }, { 0.58, 4.34 }, { 0.84, 4.12 } })
		D:strip("UpperTorso", top, bot, 0.08, 0.014, P.shirt, "Fabric")
		local rim = {}
		for i = 1, #top do
			table.insert(rim, top[i])
		end
		for i = #bot - 1, 2, -1 do
			table.insert(rim, bot[i])
		end
		D:tube("UpperTorso", rim, 0.082, 0.034, P.shirtDark, "Fabric", 0.3, true)
		for _, d in { { 0.3, 4.86 }, { 0.48, 4.78 }, { 0.36, 4.66 }, { 0.58, 4.6 }, { 0.5, 4.46 }, { 0.7, 4.38 }, { 0.24, 4.78 }, { 0.74, 4.22 }, { 0.42, 4.62 }, { 0.62, 4.5 } } do
			g:ell("UpperTorso", D:cf(s * d[1], d[2], 0.092, s * 25), V(0.05, 0.072, 0.012), P.dot, "SmoothPlastic")
		end
	end
	-- стойка воротника вокруг шеи сзади + воротник пиджака
	local back = {}
	for i = 0, 8 do
		local a = rad(-112 + i * 28)
		table.insert(back, V(0.48 * math.sin(a), 5.0, 0.1 + 0.5 * math.cos(a)))
	end
	g:tube("UpperTorso", back, 0.2, P.shirt, "Fabric")
	local jback = {}
	for i = 0, 8 do
		local a = rad(-118 + i * 29.5)
		table.insert(jback, V(0.58 * math.sin(a), 4.9, 0.12 + 0.58 * math.cos(a)))
	end
	g:tube("UpperTorso", jback, 0.2, P.suit, "SmoothPlastic")

	-- ===== Кубинская цепь (передняя дуга лежит на мехе, концы уходят под воротник) =====
	local N = 22
	local Df = Drape.new(g, { E.fur, E.fur2, E.shirt, E.chest })
	local function chainXY(th)
		return 0.43 * math.sin(th), 5.0 - 0.6 * math.cos(th) ^ 1.25
	end
	for i = 0, N - 1 do
		local th = rad(-84 + 168 * (i + 0.5) / N)
		local x, y = chainXY(th)
		local x2, y2 = chainXY(th + 0.01)
		local x1, y1 = chainXY(th - 0.01)
		local p, n = Df:at(x, y, 0.035)
		local pa = Df:at(x1, y1, 0.035)
		local pb = Df:at(x2, y2, 0.035)
		local tng = (pb - pa).Unit
		local bin = tng:Cross(-n).Unit
		local nrm = bin:Cross(tng).Unit
		local base = CFrame.fromMatrix(p, tng, bin, nrm)
		g:rbox("UpperTorso", base * CFrame.Angles(0, 0, rad(36)), V(0.17, 0.078, 0.05), P.gold, "Foil")
		g:rbox("UpperTorso", base * CFrame.new(0.048, 0, 0.018) * CFrame.Angles(0, 0, rad(-36)), V(0.13, 0.06, 0.035), P.goldDeep, "Foil")
	end
	-- эмиттер блеска цепи
	local chainHost = g:box("UpperTorso", V(0, 4.55, -0.6), V(0.9, 0.4, 0.3), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "ChainSparkleHost" })
	chainHost.CanQuery = false
	emitter(chainHost, "ChainSparkles", {
		Rate = 14,
		Lifetime = roblox.NumberRange.new(0.25, 0.5),
		Speed = roblox.NumberRange.new(0),
		Size = seq({ { 0, 0 }, { 0.35, 0.28 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 244, 200), Color3.fromRGB(255, 205, 90)),
		Transparency = seq({ { 0, 0 }, { 1, 0.2 } }),
	})

	-- ===== Таз в джинсах (LowerTorso) =====
	g:ell("LowerTorso", V(0, 2.74, 0.06), V(1.96, 1.2, 1.1), P.jeans, "Fabric")
	g:ell("LowerTorso", V(0, 2.95, 0.04), V(1.94, 0.5, 1.2), P.jeans, "Fabric") -- пояс
	g:ellSeg("LowerTorso", V(0.05, 2.82, -0.6), V(0.03, 2.4, -0.5), 0.03, 0.02, P.jeansDark, "Fabric") -- шов ширинки

	-- пиджак ниже талии: два вертикальных цилиндра (прямые бока, ровный подол); спереди между ними
	-- «долина» — там видны ремень и джинсы (полы распахнуты)
	for _, s in { 1, -1 } do
		g:cylSeg("LowerTorso", V(s * 0.5, 3.16, 0.08), V(s * 0.5, 2.12, 0.08), 1.2, P.suit, "SmoothPlastic")
		g:cylSeg("LowerTorso", V(s * 0.5, 2.135, 0.08), V(s * 0.5, 2.11, 0.08), 1.12, P.suitDark, "SmoothPlastic")
	end
	g:ell("LowerTorso", V(0, 2.72, 0.3), V(1.6, 1.2, 0.9), P.suit, "SmoothPlastic")

	-- ===== Ремень (крокодил) =====
	local belt = {}
	local NB = 28
	local by = 2.96
	for i = 0, NB do
		local a = i / NB * 2 * math.pi
		table.insert(belt, V(1.02 * math.sin(a), by, 0.04 - 0.655 * math.cos(a)))
	end
	for i = 1, NB do
		local a, b = belt[i], belt[i + 1]
		local mid = (a + b) / 2
		local d = b - a
		local cf = Geo.axisX(mid, d)
		g:box("LowerTorso", cf, V(d.Magnitude + 0.02, 0.24, 0.05), P.belt, "Leather")
	end
	-- чешуя крокодила спереди (2 ряда скруглённых плиток)
	for i = -6, 6 do
		for row = 0, 1 do
			local a = (i + (row * 0.5)) * 0.11
			local x = 1.04 * math.sin(a)
			local z = 0.04 - 0.675 * math.cos(a)
			local nrm = V(math.sin(a) / 1.04, 0, -math.cos(a) / 0.675).Unit
			local y = by + (if row == 0 then 0.055 else -0.055)
			local cf = CFrame.lookAt(V(x, y, z), V(x, y, z) + nrm)
			local shade = if (i + row) % 3 == 0 then P.croc else P.belt:Lerp(P.croc, 0.6)
			g:rbox("LowerTorso", cf, V(0.085, 0.07, 0.012), shade, "Leather", nil, { reflectance = 0.04 })
		end
	end
	-- шлёвки
	for _, x in { -0.4, 0.4 } do
		local a = math.asin(x / 1.04)
		local z = 0.04 - 0.69 * math.cos(a)
		local nrm = V(math.sin(a), 0, -math.cos(a)).Unit
		g:box("LowerTorso", CFrame.lookAt(V(x, by, z), V(x, by, z) + nrm), V(0.07, 0.32, 0.03), P.jeansDark, "Fabric")
	end

	-- ===== Пряжка «A» =====
	local AH, AW = 0.62, 0.52
	local aFrame = CFrame.new(0, by - 0.24, -0.7)
	-- полированный кант (задняя, чуть бо́льшая пластина)
	buildA(g, "LowerTorso", aFrame, AH, AW, 0.06, P.buckleSide, "Foil", 0.0, nil, 0)
	-- сатиновое лицо (суженный контур, выступает вперёд)
	buildA(g, "LowerTorso", aFrame, AH, AW, 0.03, P.champagne, "Metal", -0.022, nil, 0.016)
	local apex = aFrame * V(0, AH, -0.04)
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

	-- ===== Аура (трон) =====
	local auraHost = g:box("UpperTorso", V(0, 3.6, 0), V(3.4, 5.6, 2.2), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "AuraHost" })
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
