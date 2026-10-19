--!nocheck
-- Голова коня: шея, череп, длинная морда (лоб — тёмный шоколад, вокруг глаз и переносица — рыже-коричневые,
-- седые лохматые щёки, угольная бархатная морда с ноздрями-полумесяцами), глаза с тяжёлыми веками, уши,
-- чёрный кок, рот (крупные «человеческие» зубы, дёсны, мясистые губы, язык), нижняя челюсть.
--
-- Всё строится прямо в char space (поза покоя) вокруг опор суставов из HorseSkeleton.EXTRA:
-- Jaw, UpperLip, Glasses, Brow, Ear, Mane. Здесь же создаётся доп. сустав LowerLip (на Jaw):
-- канал grin двигает обе губы (верхнюю вверх, нижнюю вниз), см. Head.LOWER_LIP_GRIN.
--
-- Морда — «лофт»: эллипсоиды-сечения вдоль оси головы C0 -> C1 (STATIONS), поверх — цветовые накладки.
-- Рот описывается в «системе рта» MF: начало — середина линии смыкания передних зубов (B0),
-- ось -Z — куда смотрят передние зубы, +Y — «вверх» от линии смыкания.
local roblox = require("@lune/roblox")
local lookAtFixed = require("../../lib/LookAt") -- CFrame.lookAt в Lune неверен
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local V = Vector3.new
local rad = math.rad

local P = require("./Palette")

local Head = {}

-- ===== Ориентиры (char space, поза покоя) =====
Head.C0 = V(0, 6.86, -0.08) -- центр черепа
Head.C1 = V(0, 5.6, -0.85) -- центр морды (носа)
-- Лофт морды: сечения { t, W (полуширина), F (передняя точка от оси), цвет }.
-- BRIDGE — узкая передняя часть (переносица, нос), CHEEK — широкая задняя (щёки, скулы).
Head.BRIDGE = {
	{ 0.1, 0.44, 0.42, P.forehead },
	{ 0.3, 0.42, 0.4, P.forehead:Lerp(P.warm, 0.55) },
	{ 0.5, 0.35, 0.39, P.warm },
	{ 0.7, 0.29, 0.375, P.warm:Lerp(P.bridgeLow, 0.45) },
	{ 0.84, 0.29, 0.38, P.bridgeLow:Lerp(P.muzzle, 0.5) },
}
Head.BRIDGE_D, Head.BRIDGE_L = 0.24, 0.62
Head.CHEEK = {
	{ 0.05, 0.5, 0.33, P.forehead, 0.72 },
	{ 0.25, 0.54, 0.31, P.forehead:Lerp(P.cheek, 0.35), 0.72 },
	{ 0.45, 0.56, 0.28, P.warm:Lerp(P.cheek, 0.6), 0.72 },
	{ 0.62, 0.53, 0.27, P.cheek, 0.62 },
	{ 0.78, 0.47, 0.26, P.cheek, 0.5 },
}
Head.CHEEK_D, Head.CHEEK_L = 0.42, 0.72
Head.NOSTRIL = V(0, 5.85, -1.18) -- середина между ноздрями (на переднем торце носа)
Head.EYE = V(0.36, 6.37, -0.6) -- правый глаз (левый — зеркально)
Head.B0 = V(0, 5.42, -1.08) -- середина смыкания передних зубов
Head.MOUTH_TILT = 15 -- передние зубы смотрят вперёд-вниз на этот угол
Head.MF = CFrame.new(Head.B0) * CFrame.Angles(rad(-Head.MOUTH_TILT), 0, 0)
Head.LOWER_LIP_PIVOT = V(0, 5.31, -1.02)
-- канал grin для нижней губы (при grin = 1): вниз и наружу, кромка выворачивается
Head.LOWER_LIP_GRIN = { pos = V(0, -0.07, -0.02), rot = V(-9, 0, 0) }
-- зубная дуга (верхняя): полуширина, глубина, центр (в MF)
Head.AX, Head.AZ, Head.Z0 = 0.28, 0.42, 0.42

-- Зубная дуга в MF: эллипс (центр z0, полуоси ax, az); phi в градусах (0 — центр спереди).
local function arch(ax, az, z0, phi)
	local p = rad(phi)
	local x = ax * math.sin(p)
	local z = z0 - az * math.cos(p)
	local n = V(math.sin(p) / ax, 0, -math.cos(p) / az).Unit -- наружная нормаль (в MF)
	return x, z, n
end
Head.arch = arch

-- Линия смыкания поднимается к уголкам рта (улыбка).
local function biteY(phi)
	local k = math.abs(phi) / 90
	return 0.06 * k * k
end
Head.biteY = biteY

-- phi по длине дуги s (от центра) для эллипса (ax, az).
local function phiAt(ax, az, s)
	local acc, phi, step = 0, 0, 0.5
	local px, pz = 0, -az
	while acc < s and phi < 120 do
		phi += step
		local x = ax * math.sin(rad(phi))
		local z = -az * math.cos(rad(phi))
		acc += math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		px, pz = x, z
	end
	return phi
end

-- CFrame детали на дуге в MF: -Z детали — наружу по нормали; tiltX наклоняет низ детали.
local function archCF(x, y, z, n, tiltX)
	local back = -n
	local up = V(0, 1, 0)
	local right = up:Cross(back).Unit
	local cf = CFrame.fromMatrix(V(x, y, z), right, up, back)
	if tiltX then
		cf = cf * CFrame.Angles(rad(tiltX), 0, 0)
	end
	return Head.MF * cf
end

local function mf(x, y, z)
	return Head.MF * V(x, y, z)
end
Head.mf = mf

-- ряд зубов: widths/heights по порядку от центра; upper — растут вверх от линии смыкания
local function teethRow(g, bone, ax, az, z0, widths, heights, thick, upper, tilt)
	local s = 0
	for i, w in widths do
		local sc = s + w / 2
		s += w - 0.004
		local phiC = phiAt(ax, az, sc)
		for _, sgn in { 1, -1 } do
			local phi = sgn * phiC
			local x, z, n = arch(ax, az, z0, phi)
			local h = heights[i]
			local c = V(x, 0, z) - n * (thick / 2)
			local y = if upper then biteY(phi) + h / 2 - 0.004 else biteY(phi) - h / 2 - 0.008
			local col = if i <= 3 then P.tooth else P.tooth:Lerp(P.toothShade, (i - 3) / 4)
			g:put(bone, {
				cf = archCF(c.X, y, c.Z, n, if upper then -tilt else tilt),
				size = V(w, h, thick),
				color = col,
				material = "SmoothPlastic",
				mesh = "Head",
				name = if upper then "ToothU" else "ToothL",
			})
		end
	end
end

-- точки дуги (для caps) в char space
local function archPts(ax, az, z0, phi0, phi1, step, yf, inset)
	local pts = {}
	local phi = phi0
	while phi <= phi1 + 1e-6 do
		local x, z, n = arch(ax, az, z0, phi)
		local c = V(x, 0, z) - n * (inset or 0)
		table.insert(pts, mf(c.X, yf(phi), c.Z))
		phi += step
	end
	return pts
end

function Head.build(g, opts)
	local rig = g.rig
	g.xf = nil
	local C0, C1 = Head.C0, Head.C1
	local len = (C1 - C0).Magnitude
	local sd = (C1 - C0).Unit -- вниз по оси головы
	local sn = V(0, -sd.Z, sd.Y) -- вперёд-вверх (наружу от морды)
	local X = V(1, 0, 0)
	local function stationCF(t, off, side)
		local pos = C0 + sd * (t * len) + sn * (off or 0) + X * (side or 0)
		return CFrame.fromMatrix(pos, X, -sd, X:Cross(-sd))
	end
	Head.stationCF = stationCF

	-- ===================== ШЕЯ (кость Head, вращается вокруг Neck y=4.95) =====================
	g:ellSeg("Head", V(0, 4.4, 0.14), V(0, 6.7, 0.16), 1.04, 0.98, P.neck, "Carpet", V(0, 0, -1), { name = "Neck" })
	g:ellSeg("Head", V(0, 4.3, -0.12), V(0, 5.3, -0.16), 0.82, 0.62, P.neck:Lerp(P.jowl, 0.4), "Carpet", V(0, 0, -1)) -- горло
	g:ellSeg("Head", V(0, 4.7, 0.44), V(0, 6.95, 0.3), 0.68, 0.52, P.neck, "Carpet", V(0, 0, -1)) -- загривок
	for i = 0, 5 do
		local t = i / 5
		local c = V(0, 6.98 - t * 1.95, 0.46 + t * 0.14 + 0.1 * math.sin(t * math.pi))
		g:ell("Mane", c, V(0.2 - t * 0.04, 0.42, 0.2), P.mane:Lerp(P.maneHi, (i % 2) * 0.5), "Carpet", V(-20 + t * 10, 0, 0))
	end

	-- ===================== ЧЕРЕП И МОРДА (лофт) =====================
	g:ell("Head", stationCF(0), V(1.0, 0.98, 1.0), P.forehead, "Carpet", nil, { name = "Skull" })
	g:ell("Head", V(0, 6.66, 0.18), V(0.92, 0.86, 0.8), P.neck, "Carpet") -- затылок
	for _, st in Head.CHEEK do
		local D = Head.CHEEK_D
		g:ell("Head", stationCF(st[1], st[3] - D), V(2 * st[2], st[5], 2 * D), st[4], "Carpet", nil, { name = "Skull" })
	end
	for _, st in Head.BRIDGE do
		local D = Head.BRIDGE_D
		g:ell("Head", stationCF(st[1], st[3] - D), V(2 * st[2], Head.BRIDGE_L, 2 * D), st[4], "Carpet", nil, { name = "Face" })
	end
	-- светлая «проточина» по переносице
	g:ell("Head", stationCF(0.66, 0.39 - 0.16), V(0.2, 0.62, 0.34), P.warmLight, "Carpet", nil, { castShadow = false })

	-- ===================== ЩЁКИ И ГАНАШИ =====================
	for _, s in { 1, -1 } do
		-- ганаши (большие тёмные «щёки» сзади-снизу)
		g:ell("Head", V(s * 0.37, 5.6, -0.24), V(0.48, 1.0, 0.84), P.jowl, "Carpet", V(-10, 0, 0))
	end

	-- ===================== НОС =====================
	local NS = Head.NOSTRIL
	-- боковины морды между носом и уголками рта
	for _, s in { 1, -1 } do
		g:ell("Head", V(s * 0.26, 5.74, -0.7), V(0.34, 0.42, 0.52), P.cheek:Lerp(P.muzzle, 0.5), "Carpet", V(-15, s * 15, 0))
	end
	-- нос: отдельная «луковица», смотрит вперёд; низ — над верхней губой
	g:ell("Head", V(0, 5.84, -0.9), V(0.68, 0.5, 0.62), P.muzzle, "Carpet", V(-12, 0, 0), { name = "Muzzle" })
	g:ell("Head", V(0, 5.83, -1.0), V(0.62, 0.44, 0.42), P.nosePad, "Carpet", V(-8, 0, 0))
	for _, s in { 1, -1 } do
		-- ноздря: тёмная «запятая» на переднем торце, верх сходится к центру
		local c = NS + V(s * 0.18, 0, 0)
		local ncf = lookAtFixed(c, c + V(s * 0.4, 0.2, -1)) * CFrame.Angles(0, 0, rad(s * 14))
		g:ell("Head", ncf, V(0.125, 0.27, 0.07), P.nostril, "SmoothPlastic", nil, { name = "Nostril" })
		-- крыло ноздри: валик, огибающий ноздрю снаружи и сверху
		g:ellSeg("Head", c + V(s * 0.078, -0.12, 0.035), c + V(s * 0.05, 0.11, 0.0), 0.085, 0.085, P.nostrilRim, "Carpet")
		g:ellSeg("Head", c + V(s * 0.035, 0.135, 0.0), c + V(-s * 0.05, 0.09, -0.004), 0.072, 0.072, P.nostrilRim, "Carpet")
		-- внутренняя складка (закрывает верх ноздри — форма полумесяца)
		g:ellSeg("Head", c + V(-s * 0.045, 0.11, -0.012), c + V(-s * 0.02, -0.05, -0.008), 0.055, 0.05, P.nosePad, "Carpet")
	end
	g:ellSeg("Head", NS + V(0, 0.09, 0.01), NS + V(0, -0.1, 0.0), 0.11, 0.075, P.nosePad:Lerp(P.nostrilRim, 0.5), "Carpet")

	-- ===================== ГЛАЗА =====================
	for _, s in { 1, -1 } do
		local side = if s == 1 then "Right" else "Left"
		local c = V(s * Head.EYE.X, Head.EYE.Y, Head.EYE.Z)
		local look = V(s * 0.28, -0.05, -1).Unit
		local cf = lookAtFixed(c, c + look)
		-- глазница (тёплая) — фон, видимый сквозь линзы
		g:ell("Head", cf * CFrame.new(0, 0, 0.05), V(0.4, 0.32, 0.2), P.warm:Lerp(P.lid, 0.3), "Carpet")
		g:ell("Head", cf, V(0.28, 0.2, 0.16), P.eyeWhite, "SmoothPlastic", nil, { name = "Eye" })
		g:ell("Head", cf * CFrame.new(0.005, -0.012, -0.07), V(0.15, 0.15, 0.03), P.iris, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0.005, -0.012, -0.082), V(0.07, 0.08, 0.014), P.pupil, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(s * -0.024, 0.014, -0.087), V(0.026, 0.026, 0.008), P.tooth, "SmoothPlastic") -- блик
		-- тяжёлое верхнее веко (прикрыто наполовину: «крутой» взгляд) и нижнее веко
		g:ell("Head", cf * CFrame.new(0, 0.06, -0.004) * CFrame.Angles(rad(-10), 0, 0), V(0.31, 0.12, 0.18), P.lid, "Carpet")
		g:ell("Head", cf * CFrame.new(0, 0.08, 0.01), V(0.34, 0.11, 0.18), P.lid:Lerp(P.forehead, 0.4), "Carpet")
		g:ell("Head", cf * CFrame.new(0, -0.082, 0.008), V(0.3, 0.075, 0.16), P.warm, "Carpet")
		-- надбровная дуга (на голове) и бровь (сустав Brow — над оправой)
		local bp = rig:pivotOf(side .. "Brow")
		g:ellSeg("Head", bp + V(-s * 0.2, -0.02, -0.06), bp + V(s * 0.2, -0.05, 0.12), 0.14, 0.12, P.forehead:Lerp(P.warm, 0.3), "Carpet", sn)
		g:ellSeg(side .. "Brow", bp + V(-s * 0.2, 0.02, -0.075), bp + V(s * 0.21, 0.0, 0.1), 0.085, 0.07, P.furDark, "Carpet", sn)
	end

	-- ===================== УШИ =====================
	for _, s in { 1, -1 } do
		local ear = if s == 1 then "RightEar" else "LeftEar"
		local base = rig:pivotOf(ear)
		local tip = base + V(s * 0.16, 0.72, 0.06)
		local outA = V(s * 0.6, 0.15, 1).Unit -- наружная (задняя) сторона уха
		g:ellSeg(ear, base + V(0, -0.06, 0.02), tip, 0.34, 0.22, P.earOut, "Carpet", outA)
		g:ellSeg(ear, base:Lerp(tip, 0.5), tip + V(s * 0.01, 0.04, 0.0), 0.2, 0.13, P.earOut:Lerp(P.earTip, 0.5), "Carpet", outA)
		g:ellSeg(ear, base:Lerp(tip, 0.82), tip + V(s * 0.005, 0.05, 0.0), 0.1, 0.08, P.earTip, "Carpet", outA)
		local inn = V(-s * 0.35, 0, -1).Unit
		g:ellSeg(ear, base + V(0, 0.08, -0.08), base:Lerp(tip, 0.85) + V(0, 0, -0.05), 0.2, 0.07, P.earIn, "Carpet", -outA)
		g:ellSeg(ear, base + V(s * 0.01, 0.12, -0.11), base:Lerp(tip, 0.55) + V(0, 0, -0.08), 0.07, 0.04, P.frost:Lerp(P.earIn, 0.4), "Carpet", inn, { castShadow = false })
	end

	-- ===================== КОК (чёрный помпадур между ушами) =====================
	local mp = rig:pivotOf("Mane")
	g:ell("Mane", mp + V(0, 0.02, 0.02), V(0.5, 0.34, 0.74), P.mane, "Carpet")
	g:ell("Mane", mp + V(0, 0.12, -0.14), V(0.46, 0.36, 0.5), P.mane, "Carpet")
	g:ellSeg("Mane", mp + V(0, 0.08, 0.2), mp + V(0.0, 0.34, -0.22), 0.36, 0.26, P.mane, "Carpet")
	g:ellSeg("Mane", mp + V(0, 0.3, -0.12), mp + V(0.02, 0.26, -0.4), 0.26, 0.2, P.maneHi, "Carpet")
	g:ellSeg("Mane", mp + V(0.01, 0.27, -0.36), mp + V(0.02, 0.1, -0.46), 0.16, 0.14, P.mane, "Carpet")
	local spikes = {
		{ V(0.08, 0.2, 0.0), V(0.18, 0.5, -0.06), 0.13 },
		{ V(-0.08, 0.2, 0.02), V(-0.16, 0.48, -0.04), 0.13 },
		{ V(0.0, 0.25, 0.12), V(0.03, 0.52, 0.16), 0.14 },
		{ V(0.12, 0.12, 0.18), V(0.22, 0.38, 0.26), 0.11 },
		{ V(-0.12, 0.12, 0.18), V(-0.21, 0.37, 0.27), 0.11 },
		{ V(0.0, 0.1, 0.3), V(0.0, 0.3, 0.46), 0.12 },
	}
	for i, sp in spikes do
		g:ellSeg("Mane", mp + sp[1], mp + sp[2], sp[3], sp[3] * 0.8, if i % 2 == 0 then P.maneHi else P.mane, "Carpet")
	end

	-- ===================== РОТ: верх (кость Head) =====================
	local AX, AZ, Z0 = Head.AX, Head.AZ, Head.Z0
	g:ell("Head", Head.MF * CFrame.new(0, 0.06, 0.42), V(0.48, 0.26, 0.6), P.mouthIn, "SmoothPlastic", nil, { name = "MouthCavity" })
	g:ell("Head", Head.MF * CFrame.new(0, 0.0, 0.62), V(0.4, 0.22, 0.3), P.throat, "SmoothPlastic")
	g:caps("Head", archPts(AX - 0.01, AZ - 0.012, Z0, -86, 86, 14.333, function(phi)
		return biteY(phi) + 0.16 - 0.05 * (math.abs(phi) / 90)
	end, 0.02), 0.075, P.gum, "SmoothPlastic", nil, nil, 1.0)
	teethRow(g, "Head", AX, AZ, Z0, { 0.112, 0.096, 0.09, 0.084, 0.08, 0.076, 0.072 }, { 0.17, 0.148, 0.152, 0.13, 0.118, 0.106, 0.096 }, 0.06, true, 4)

	-- ===================== НИЖНЯЯ ЧЕЛЮСТЬ (Jaw) =====================
	g:ell("Jaw", Head.MF * CFrame.new(0, -0.1, 0.4), V(0.48, 0.18, 0.6), P.mouthIn, "SmoothPlastic")
	g:ell("Jaw", Head.MF * CFrame.new(0, -0.07, 0.34), V(0.36, 0.1, 0.44), P.tongue, "SmoothPlastic", nil, { name = "Tongue" })
	g:caps("Jaw", archPts(AX - 0.03, AZ - 0.035, Z0, -84, 84, 16.8, function(phi)
		return biteY(phi) - 0.12 + 0.035 * (math.abs(phi) / 90)
	end, 0.018), 0.07, P.gum, "SmoothPlastic", nil, nil, 1.0)
	teethRow(g, "Jaw", AX - 0.018, AZ - 0.026, Z0, { 0.086, 0.082, 0.08, 0.077, 0.074, 0.071, 0.068 }, { 0.11, 0.106, 0.11, 0.098, 0.09, 0.085, 0.08 }, 0.055, false, 4)
	-- подбородок, ветви челюсти, «борода» (тёмно-седая масса под ртом)
	-- нижняя челюсть одной плавной формой от подбородка к ганашам + «борода» снизу (спереди не выступает)
	g:ellSeg("Jaw", mf(0, -0.12, 0.07), V(0, 5.1, -0.3), 0.54, 0.38, P.jowl, "Carpet", V(0, 1, -0.25), { name = "Chin" })
	g:ell("Jaw", V(0, 5.02, -0.3), V(0.7, 0.42, 0.66), P.jowl:Lerp(P.cheek, 0.15), "Carpet", V(-20, 0, 0)) -- «борода»
	for _, s in { 1, -1 } do
		g:ellSeg("Jaw", mf(s * 0.2, -0.1, 0.24), V(s * 0.3, 5.28, -0.32), 0.24, 0.34, P.jowl, "Carpet", V(s, 0.3, 0))
	end

	-- ===================== НИЖНЯЯ ГУБА (доп. сустав LowerLip на Jaw) =====================
	local llp = Head.LOWER_LIP_PIVOT
	rig:joint("LowerLip", "Jaw", llp, llp, V(0.2, 0.2, 0.2))
	local llip = archPts(AX + 0.02, AZ + 0.03, Z0, -98, 98, 14, function(phi)
		local k = math.abs(phi) / 98
		return biteY(phi) - 0.07 + 0.025 * k * k
	end, 0)
	g:caps("LowerLip", llip, function(i)
		local k = math.abs(i - (#llip + 1) / 2) / ((#llip - 1) / 2)
		return 0.085 - 0.03 * k * k
	end, P.lip, "SmoothPlastic", nil, nil, 1.0)
	g:caps("LowerLip", archPts(AX, AZ + 0.012, Z0, -84, 84, 21, function(phi)
		return biteY(phi) - 0.042
	end, 0.02), 0.045, P.lipDark, "SmoothPlastic", nil, nil, 1.0)

	-- ===================== ВЕРХНЯЯ ГУБА (UpperLip) =====================
	local ulip = archPts(AX + 0.035, AZ + 0.045, Z0, -100, 100, 12.5, function(phi)
		local k = math.abs(phi) / 100
		return biteY(phi) + 0.105 - 0.04 * k * k
	end, 0)
	g:caps("UpperLip", ulip, function(i)
		local k = math.abs(i - (#ulip + 1) / 2) / ((#ulip - 1) / 2)
		return 0.08 - 0.028 * k * k
	end, P.lip, "SmoothPlastic", nil, nil, 1.0)
	g:caps("UpperLip", archPts(AX + 0.015, AZ + 0.02, Z0, -84, 84, 21, function(phi)
		return biteY(phi) + 0.07
	end, 0.025), 0.045, P.lipDark, "SmoothPlastic", nil, nil, 1.0)
	-- угольная кожа между губой и ноздрями (едет вместе с губой); спереди не выступает за нос
	g:ell("UpperLip", V(0, 5.69, -0.95), V(0.56, 0.26, 0.38), P.muzzle, "Carpet", V(-10, 0, 0))
	for _, s in { 1, -1 } do
		g:ell("UpperLip", V(s * 0.2, 5.68, -0.84), V(0.3, 0.26, 0.42), P.muzzle, "Carpet", V(-10, s * -25, 0))
	end
	g.xf = nil
end

return Head
