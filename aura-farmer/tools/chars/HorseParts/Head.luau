--!nocheck
-- Голова коня: длинная «реалистичная» лошадиная морда.
--   лоб и темя — тёмный шоколад; вокруг глаз и переносица — тёплый рыже-коричневый (светлая проточина);
--   по бокам морды — седые лохматые щёки; нос — мягкая угольно-серая бархатная «подушка» с двумя
--   большими ноздрями-полумесяцами; мясистые розово-бежевые губы, крупные «человеческие» зубы цвета
--   слоновой кости; тёмная нижняя челюсть-«борода»; уши торчком; чёрный кок-помпадур.
--
-- ПРОЕКТНОЕ ПРОСТРАНСТВО. Голова моделируется в «проекте» (крупный масштаб, числа ниже) и переносится
-- в char space подобием Head.map: p' = T + (p - C)·K (C — опора очков в проекте, T — опора Glasses
-- из HorseSkeleton). Опоры суставов в проекте — Head.DP(имя) = обратное отображение опор скелета,
-- поэтому уши/брови/кок/очки точно сидят на суставах скелета. Шея строится прямо в char space.
--
-- «Лицевые» координаты fl(s, h, x): s — вниз по линии морды от переносицы между глазами (проект),
-- h — от передней поверхности наружу (+) / внутрь головы (−), x — вправо. Морда наклонена на TILT
-- от вертикали; детали низа морды, заданные абсолютными точками при TILT0, поворачиваются вокруг FO (Head.RM).
-- Рот описывается в «системе рта» MF: начало — середина линии смыкания передних зубов (B0),
-- ось −Z — куда смотрят передние зубы, +Y — «вверх» от линии смыкания.
local roblox = require("@lune/roblox")
local lookAtFixed = require("../../lib/LookAt") -- CFrame.lookAt в Lune неверен
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local V = Vector3.new
local rad = math.rad

local P = require("./Palette")
local Skel = require("../HorseSkeleton")

local Head = {}

-- ===== Проект -> char space =====
local function pv(name)
	local p = Skel.EXTRA[name].pivot
	return V(p[1], p[2], p[3])
end
Head.K = 0.76 -- масштаб головы
Head.C = V(0, 6.62, -1.04) -- опора очков в проекте
Head.T = pv("Glasses") -- опора очков в char space
function Head.map(p)
	return Head.T + (p - Head.C) * Head.K
end
function Head.unmap(p)
	return Head.C + (p - Head.T) / Head.K
end
-- опора сустава скелета в проектных координатах
function Head.DP(name)
	return Head.unmap(pv(name))
end
function Head.setMap(g)
	g:setMap(Head.C, Head.T, Head.K)
end

-- ===== Линия морды =====
Head.TILT0 = 30 -- наклон, при котором заданы абсолютные точки низа морды (рот, подбородок)
Head.TILT = 48 -- наклон линии морды от вертикали (лоб назад, нос вперёд)
Head.FO = V(0, 6.62, -0.98) -- передняя поверхность переносицы между глазами (= опора Glasses + 0.06)
Head.FA = V(0, -math.cos(rad(Head.TILT)), -math.sin(rad(Head.TILT))) -- вниз по морде
Head.FN = V(0, math.sin(rad(Head.TILT)), -math.cos(rad(Head.TILT))) -- наружу из морды
-- Удлинение морды: нос и всё ниже него сдвинуты вниз по морде на SL (проект)
Head.SL = 0.16
-- поворот низа морды вокруг FO (с TILT0 на TILT) + сдвиг рта вдоль морды (SL) и чуть внутрь (под нос)
Head.RM = CFrame.new(Head.FO)
	* CFrame.Angles(rad(Head.TILT - Head.TILT0), 0, 0)
	* CFrame.new(-Head.FO)
	* CFrame.new(V(0, -math.cos(rad(Head.TILT0)), -math.sin(rad(Head.TILT0))) * 0.08 + V(0, math.sin(rad(Head.TILT0)), -math.cos(rad(Head.TILT0))) * -0.1)
local RM = Head.RM
local function fl(s, h, x)
	return Head.FO + Head.FA * s + Head.FN * (h or 0) + V(x or 0, 0, 0)
end
Head.fl = fl
-- CFrame «вдоль морды»: Y — вверх по морде (к лбу), −Z — наружу
local function flCF(s, h, x, rx, ry, rz)
	local cf = CFrame.fromMatrix(fl(s, h, x), V(1, 0, 0), -Head.FA, -Head.FN)
	if rx or ry or rz then
		cf = cf * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
	end
	return cf
end
Head.flCF = flCF

-- ===== Ориентиры (проект) =====
Head.EYE = V(0.46, 6.63, -0.8) -- правый глаз (левый — зеркально)
Head.NOSE = fl(1.03 + Head.SL, -0.22) -- центр носовой «подушки»
Head.B0 = RM * V(0, 5.2, -1.52) -- середина смыкания передних зубов
Head.MOUTH_TILT = 14 -- (при TILT0) передние зубы смотрят вперёд-вниз на этот угол
Head.MF = RM * CFrame.new(V(0, 5.2, -1.52)) * CFrame.Angles(rad(-Head.MOUTH_TILT), 0, 0)
Head.LOWER_LIP_PIVOT = RM * V(0, 5.08, -1.46)
-- канал grin для нижней губы (при grin = 1, char space): вниз и наружу, кромка выворачивается
Head.LOWER_LIP_GRIN = { pos = V(0, -0.06, -0.012), rot = V(-8, 0, 0) }
-- зубная дуга (верхняя): полуширина, глубина, центр (в MF)
Head.AX, Head.AZ, Head.Z0 = 0.31, 0.44, 0.44

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
	return 0.075 * k * k
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

-- Губа — лента из сплющенных эллипсоидов вдоль дуги: высота hf(k) (вертикально в системе рта), толщина wf(k);
-- k = 0 в центре, 1 — в уголке. Концы сегментов перекрываются.
local function lipBand(g, bone, pts, hf, wf, color)
	local n = #pts
	local up = (Head.MF - Head.MF.Position) * V(0, 1, 0)
	for i = 1, n - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = b - a
		local l = d.Magnitude
		if l > 1e-4 then
			local u = d / l
			local km = math.abs((i + 0.5) - (n + 1) / 2) / ((n - 1) / 2)
			local h, w = hf(km), wf(km)
			local ext = l * 1.0
			g:ellSeg(bone, a - u * ext, b + u * ext, w, h, color, "SmoothPlastic", up, { name = "Lip" })
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

-- Прядь шерсти: вытянутый эллипсоид от base в направлении dir (длина len, толщина w у корня).
local function tuft(g, bone, base, dir, len, w, color, extra)
	local d = dir.Unit
	return g:ellSeg(bone, base - d * (len * 0.25), base + d * len, w, w * 0.7, color, "SmoothPlastic", nil, extra or { castShadow = false })
end
Head.tuft = tuft

function Head.build(g, opts)
	local rig = g.rig
	g.xf = nil
	g:setMap(nil)
	local DP = Head.DP

	-- ===================== ШЕЯ (char space; кость Head, вращается вокруг Neck y=4.95) =====================
	-- длинная толстая шея наклонена вперёд: из воротника вверх-вперёд к затылку и ганашам
	g:ellSeg("Head", V(0, 4.42, 0.3), V(0, 6.62, -0.1), 0.9, 0.84, P.neck, "SmoothPlastic", V(0, 0, -1), { name = "Neck" })
	-- горло: от груди к подбородку (светлее, переходит в мех груди)
	g:ellSeg("Head", V(0, 4.5, -0.02), V(0, 5.45, -0.5), 0.66, 0.5, P.chestFur:Lerp(P.jowl, 0.4), "SmoothPlastic", V(0, 0, -1))
	g:ellSeg("Head", V(0, 4.72, -0.26), V(0, 5.25, -0.52), 0.34, 0.14, P.chestFur:Lerp(P.chestFrost, 0.5), "SmoothPlastic", V(0, 0, -1), { castShadow = false })
	-- короткая чёрная грива по гребню шеи (от затылка вниз к воротнику)
	g:ellSeg("Head", V(0, 6.92, 0.16), V(0, 5.95, 0.4), 0.2, 0.2, P.mane, "SmoothPlastic", V(0, 0, 1))
	g:ellSeg("Head", V(0, 6.1, 0.38), V(0, 5.05, 0.6), 0.16, 0.16, P.mane:Lerp(P.maneHi, 0.4), "SmoothPlastic", V(0, 0, 1))

	-- ===================== ЧЕРЕП, ЛОБ (проект) =====================
	Head.setMap(g)
	-- Форма морды — несколько длинных базовых объёмов вдоль линии морды (гладкие поверхности),
	-- цветовые зоны — «оболочки»: копия объёма, сдвинутая назад/вбок, выглядывает только по краям.
	g:ell("Head", V(0, 7.0, 0.0), V(1.16, 0.82, 1.04), P.forehead, "SmoothPlastic", nil, { name = "Skull" })
	g:ell("Head", V(0, 6.8, 0.18), V(0.96, 0.92, 0.8), P.neck, "SmoothPlastic") -- затылок
	g:ell("Head", flCF(-0.5, -0.34), V(1.28, 1.02, 0.72), P.forehead, "SmoothPlastic", nil, { name = "Forehead" })
	-- B1: верх морды (глаза, скулы) — тёплый рыже-коричневый
	g:ell("Head", flCF(0.08, -0.46), V(1.36, 1.2, 0.9), P.warm, "SmoothPlastic", nil, { name = "Face" })
	-- B2: длинная переносица и низ морды
	g:ell("Head", flCF(0.7, -0.36), V(0.6, 1.58, 0.72), P.warm, "SmoothPlastic", nil, { name = "Bridge" })
	-- светлая проточина по центру переносицы (узкая оболочка, чуть выступает)
	g:ell("Head", flCF(0.6, -0.31), V(0.28, 1.14, 0.6), P.warmLight, "SmoothPlastic", nil, { castShadow = false })
	-- низ переносицы темнеет к носу (пологая оболочка, без «купола»)
	g:ell("Head", flCF(0.98, -0.372), V(0.56, 0.96, 0.74), P.warm:Lerp(P.bridgeLow, 0.6), "SmoothPlastic", nil, { castShadow = false })
	-- седые щёки: оболочка B2, сдвинутая назад — выглядывает по бокам (сужается к носу)
	g:ell("Head", flCF(0.64, -0.6), V(0.98, 1.3, 0.8), P.cheek, "SmoothPlastic", nil, { name = "Cheek" })
	g:ell("Head", flCF(0.88, -0.64), V(0.88, 0.74, 0.7), P.cheek:Lerp(P.jowl, 0.35), "SmoothPlastic", nil, { castShadow = false })
	-- скулы под глазами: тёплые, переходят в седину
	for _, s in { 1, -1 } do
		g:ell("Head", flCF(0.3, -0.5, s * 0.36, 0, s * -18, 0), V(0.5, 0.74, 0.62), P.warm:Lerp(P.cheek, 0.45), "SmoothPlastic")
		-- пряди по краю щеки: лежат по поверхности, торчат только кончики (вниз-назад)
		for i, t in { 0.4, 0.62, 0.84 } do
			local base = fl(t, -0.56, s * (0.45 - t * 0.09))
			local col = if i % 2 == 0 then P.cheek:Lerp(P.frost, 0.4) else P.cheek:Lerp(P.frost, 0.15)
			tuft(g, "Head", base, V(s * 0.18, -0.85, 0.5), 0.2, 0.15, col)
		end
	end
	-- боковые плоскости головы: от глаза вниз-назад к углу челюсти (переход морда -> ганаши)
	for _, s in { 1, -1 } do
		g:ell("Head", flCF(0.5, -0.86, s * 0.3, 0, s * -6, 0), V(0.5, 1.44, 1.14), P.jowl:Lerp(P.warm, 0.3), "SmoothPlastic", nil, { name = "SidePlane" })
	end

	-- ===================== ГЛАЗА =====================
	for _, s in { 1, -1 } do
		local side = if s == 1 then "Right" else "Left"
		local c = V(s * Head.EYE.X, Head.EYE.Y, Head.EYE.Z)
		local look = V(s * 0.3, -0.06, -1).Unit
		local cf = lookAtFixed(c, c + look)
		-- глазница — тёплый мех вокруг глаза (виден сквозь линзы)
		g:ell("Head", cf * CFrame.new(0, -0.01, 0.06), V(0.48, 0.38, 0.24), P.warm:Lerp(P.warmLight, 0.3), "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, 0, 0.0), V(0.31, 0.21, 0.16), P.eyeWhite, "SmoothPlastic", nil, { name = "Eye" })
		g:ell("Head", cf * CFrame.new(0.0, -0.01, -0.07), V(0.19, 0.17, 0.03), P.iris, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0.0, -0.01, -0.085), V(0.12, 0.065, 0.016), P.pupil, "SmoothPlastic") -- зрачок горизонтальный
		g:ell("Head", cf * CFrame.new(s * -0.035, 0.03, -0.094), V(0.03, 0.026, 0.01), P.tooth, "SmoothPlastic", nil, { castShadow = false }) -- блик
		-- тяжёлое верхнее веко (прикрыто на треть: «крутой» прищур) и нижнее веко
		g:ell("Head", cf * CFrame.new(0, 0.058, -0.006) * CFrame.Angles(rad(-12), 0, 0), V(0.34, 0.12, 0.18), P.lid, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, 0.085, 0.012), V(0.4, 0.13, 0.2), P.lid:Lerp(P.warm, 0.4), "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, -0.088, 0.008), V(0.34, 0.08, 0.17), P.warm:Lerp(P.lid, 0.3), "SmoothPlastic")
		-- надбровная дуга (на голове) и бровь (сустав Brow — над оправой)
		local bp = DP(side .. "Brow")
		g:ellSeg("Head", bp + V(-s * 0.24, -0.1, 0.02), bp + V(s * 0.26, -0.1, 0.2), 0.15, 0.12, P.forehead:Lerp(P.warm, 0.25), "SmoothPlastic", Head.FN)
		-- бровь: плоский пучок тёмной шерсти по надбровной дуге (внешний конец уходит назад и чуть вверх)
		g:ellSeg(side .. "Brow", bp + V(-s * 0.18, -0.06, 0.02), bp + V(s * 0.26, -0.05, 0.22), 0.08, 0.06, P.furDark:Lerp(P.forehead, 0.55), "SmoothPlastic", Head.FN)
	end

	-- ===================== УШИ =====================
	for _, s in { 1, -1 } do
		local ear = if s == 1 then "RightEar" else "LeftEar"
		local base = DP(ear)
		local tip = base + V(s * 0.12, 0.76, 0.02)
		local outA = V(s * 0.55, 0.1, 1).Unit -- наружная (задняя) сторона уха
		g:ellSeg(ear, base + V(0, -0.14, 0.03), tip, 0.36, 0.23, P.earOut, "SmoothPlastic", outA)
		g:ellSeg(ear, base:Lerp(tip, 0.45), tip + V(s * 0.012, 0.05, 0.0), 0.21, 0.15, P.earOut:Lerp(P.earTip, 0.45), "SmoothPlastic", outA)
		g:ellSeg(ear, base:Lerp(tip, 0.8), tip + V(s * 0.006, 0.06, 0.0), 0.11, 0.09, P.earTip, "SmoothPlastic", outA)
		-- внутренняя чаша (тёмная) и светлые волоски
		local inn = V(-s * 0.4, 0, -1).Unit
		g:ellSeg(ear, base + V(0, 0.06, -0.09), base:Lerp(tip, 0.84) + V(0, 0, -0.05), 0.21, 0.07, P.earIn, "SmoothPlastic", -outA)
		g:ellSeg(ear, base + V(s * 0.01, 0.1, -0.12), base:Lerp(tip, 0.55) + V(0, 0, -0.08), 0.08, 0.045, P.frost:Lerp(P.earIn, 0.35), "SmoothPlastic", inn, { castShadow = false })
	end

	-- ===================== КОК (чёрный глянцевый помпадур между ушами, зачёсан назад) =====================
	local mp = DP("Mane")
	-- основание кока лежит на темени (наполовину внутри черепа)
	g:ell("Mane", mp + V(0, -0.04, 0.06), V(0.46, 0.3, 0.76), P.mane, "SmoothPlastic")
	-- три широкие пряди, зачёсанные назад от лба (средняя — с бликом), выгнуты дугой по темени
	for i, x in { -0.11, 0, 0.11 } do
		local h = if i == 2 then 0.2 else 0.14
		g:ellSeg("Mane", mp + V(x, 0.1, -0.42), mp + V(x * 1.3, h, 0.06), 0.24, 0.2, if i == 2 then P.maneHi else P.mane, "SmoothPlastic", V(0, 1, 0))
		g:ellSeg("Mane", mp + V(x * 1.3, h, -0.06), mp + V(x * 1.4, -0.02, 0.42), 0.22, 0.16, P.mane, "SmoothPlastic", V(0, 1, 0))
	end
	-- чёлка-завиток: валик над лбом и прядь, падающая вперёд
	g:ellSeg("Mane", mp + V(0.0, 0.16, -0.5), mp + V(0.04, 0.2, -0.18), 0.3, 0.22, P.mane, "SmoothPlastic", V(0, 1, 0))
	g:ellSeg("Mane", mp + V(0.04, 0.2, -0.46), mp + V(0.1, 0.0, -0.66), 0.14, 0.11, P.mane:Lerp(P.maneHi, 0.5), "SmoothPlastic")

	-- ===================== НОС: мягкая угольная «подушка» и ноздри-полумесяцы =====================
	g:ell("Head", flCF(1.03 + Head.SL, -0.24, 0, -8, 0, 0), V(0.72, 0.6, 0.62), P.muzzle, "SmoothPlastic", nil, { name = "Muzzle" })
	g:ell("Head", flCF(1.08 + Head.SL, -0.14, 0, -20, 0, 0), V(0.6, 0.48, 0.46), P.nosePad, "SmoothPlastic")
	-- бархатный переход переносица -> нос (размытая граница)
	g:ell("Head", flCF(0.8 + Head.SL, -0.27, 0, -6, 0, 0), V(0.68, 0.5, 0.56), P.bridgeLow:Lerp(P.muzzle, 0.5), "SmoothPlastic", nil, { castShadow = false })
	for _, s in { 1, -1 } do
		-- ноздря: центр на переднем торце носа; видимая тёмная часть — полумесяц снаружи-снизу,
		-- изнутри-сверху её прикрывает мягкая складка (крыло) того же бархатного цвета
		local c = fl(1.08 + Head.SL, 0.04, s * 0.18)
		local nrm = (Head.FN * 0.62 + Head.FA * 0.28 + V(s * 0.42, 0, 0)).Unit -- куда «смотрит» ноздря
		local up = -Head.FA
		local ncf = CFrame.fromMatrix(c, up:Cross(-nrm).Unit, up, -nrm) * CFrame.Angles(0, 0, rad(-s * 16))
		g:ell("Head", ncf * CFrame.new(0, -0.01, 0.03), V(0.16, 0.34, 0.1), P.nostril, "SmoothPlastic", nil, { name = "Nostril" })
		g:ell("Head", ncf * CFrame.new(s * 0.035, -0.12, 0.025), V(0.16, 0.14, 0.1), P.nostril, "SmoothPlastic")
		-- внутренняя складка (закрывает внутренне-верхний край — форма полумесяца)
		g:ell("Head", ncf * CFrame.new(-s * 0.055, 0.05, 0.012) * CFrame.Angles(0, 0, rad(s * 8)), V(0.11, 0.28, 0.09), P.muzzle, "SmoothPlastic")
		-- наружный валик: пологая выпуклость вокруг ноздри (почти утоплена в нос)
		g:ell("Head", ncf * CFrame.new(s * 0.095, -0.04, 0.045) * CFrame.Angles(0, 0, rad(-s * 6)), V(0.12, 0.4, 0.12), P.nosePad:Lerp(P.nostrilRim, 0.5), "SmoothPlastic")
		g:ell("Head", ncf * CFrame.new(s * 0.02, 0.17, 0.05), V(0.19, 0.1, 0.1), P.nosePad:Lerp(P.nostrilRim, 0.5), "SmoothPlastic")
	end

	-- ===================== РОТ: верх (кость Head) =====================
	local AX, AZ, Z0 = Head.AX, Head.AZ, Head.Z0
	g:ell("Head", Head.MF * CFrame.new(0, 0.09, 0.4), V(0.62, 0.36, 0.72), P.mouthIn, "SmoothPlastic", nil, { name = "MouthCavity" })
	g:ell("Head", Head.MF * CFrame.new(0, 0.0, 0.7), V(0.46, 0.26, 0.34), P.throat, "SmoothPlastic")
	-- задняя стенка рта и щёки изнутри (видны, когда челюсть открыта; при закрытом рте — внутри челюсти)
	g:ell("Head", Head.MF * CFrame.new(0, -0.18, 0.66), V(0.5, 0.6, 0.22), P.mouthIn:Lerp(P.throat, 0.5), "SmoothPlastic", nil, { castShadow = false })
	for _, s in { 1, -1 } do
		g:ell("Head", Head.MF * CFrame.new(s * 0.21, -0.14, 0.5), V(0.08, 0.38, 0.46), P.mouthIn:Lerp(P.throat, 0.25), "SmoothPlastic", nil, { castShadow = false })
	end
	g:caps("Head", archPts(AX - 0.012, AZ - 0.014, Z0, -84, 84, 14, function(phi)
		return biteY(phi) + 0.21 - 0.07 * (math.abs(phi) / 90)
	end, 0.022), 0.09, P.gum, "SmoothPlastic", nil, nil, 1.0)
	teethRow(g, "Head", AX, AZ, Z0, { 0.13, 0.115, 0.105, 0.095, 0.088, 0.08 }, { 0.24, 0.21, 0.2, 0.17, 0.15, 0.13 }, 0.07, true, 4)

	-- ===================== НИЖНЯЯ ЧЕЛЮСТЬ (Jaw) =====================
	g:ell("Jaw", Head.MF * CFrame.new(0, -0.075, 0.44), V(0.58, 0.22, 0.86), P.mouthIn, "SmoothPlastic")
	g:ell("Jaw", Head.MF * CFrame.new(0, -0.035, 0.38), V(0.4, 0.12, 0.56), P.tongue, "SmoothPlastic", nil, { name = "Tongue" })
	g:caps("Jaw", archPts(AX - 0.035, AZ - 0.04, Z0, -82, 82, 16.4, function(phi)
		return biteY(phi) - 0.15 + 0.04 * (math.abs(phi) / 90)
	end, 0.02), 0.08, P.gum, "SmoothPlastic", nil, nil, 1.0)
	teethRow(g, "Jaw", AX - 0.022, AZ - 0.03, Z0, { 0.1, 0.095, 0.09, 0.085, 0.08, 0.075 }, { 0.14, 0.13, 0.13, 0.115, 0.1, 0.09 }, 0.062, false, 4)
	-- массивная глубокая нижняя челюсть: подбородок под ртом (в системе рта), боковины и нижняя линия к горлу
	local MF = Head.MF
	g:ell("Jaw", MF * CFrame.new(0, -0.27, 0.2) * CFrame.Angles(rad(-10), 0, 0), V(0.58, 0.5, 0.56), P.jowl, "SmoothPlastic", nil, { name = "Chin" })
	-- седина на подбородке (чуть светлее, «борода»)
	g:ell("Jaw", MF * CFrame.new(0, -0.38, 0.24) * CFrame.Angles(rad(-25), 0, 0), V(0.44, 0.32, 0.44), P.jowl:Lerp(P.cheek, 0.45), "SmoothPlastic", nil, { castShadow = false })
	-- нижняя линия челюсти: от подбородка назад-вверх к горлу (один гладкий объём)
	g:ellSeg("Jaw", Head.mf(0, -0.38, 0.14), V(0, 5.28, -0.24), 0.62, 0.6, P.jowl, "SmoothPlastic", V(0, 1, 0), { name = "JawLine" })
	for _, s in { 1, -1 } do
		-- боковины нижней челюсти: от углов рта назад к ганашам
		g:ellSeg("Jaw", Head.mf(s * 0.27, -0.24, 0.22), V(s * 0.36, 5.62, -0.18), 0.4, 0.8, P.jowl, "SmoothPlastic", V(0, 1, 0))
		-- ганаши: округлые «щёки» сзади-снизу, под ушами
		g:ell("Jaw", V(s * 0.38, 5.8, -0.14), V(0.42, 0.78, 0.78), P.jowl:Lerp(P.neck, 0.3), "SmoothPlastic", V(-14, 0, 0), { name = "Ganache" })
	end

	-- уголки рта: «перепонка» на челюсти — верх спрятан за верхней губой, при открытии рта уголок не рвётся
	for _, s in { 1, -1 } do
		local x, z, n = arch(AX + 0.04, AZ + 0.04, Z0, s * 92)
		local c = Head.MF * V(x, -0.02, z)
		local rot = Head.MF - Head.MF.Position
		g:ell("Jaw", CFrame.new(c) * rot * CFrame.Angles(0, rad(s * 30), 0), V(0.07, 0.28, 0.12), P.lipDark, "SmoothPlastic", nil, { name = "MouthCorner" })
		g:ell("Jaw", CFrame.new(c + rot * V(s * 0.03, -0.02, 0.06)) * rot * CFrame.Angles(0, rad(s * 30), 0), V(0.1, 0.3, 0.16), P.jowl, "SmoothPlastic")
	end

	-- ===================== НИЖНЯЯ ГУБА (доп. сустав LowerLip на Jaw) =====================
	local llp = Head.LOWER_LIP_PIVOT
	local llpC = Head.map(llp)
	rig:joint("LowerLip", "Jaw", llpC, llpC, V(0.2, 0.2, 0.2))
	local llip = archPts(AX + 0.03, AZ + 0.035, Z0, -88, 88, 16, function(phi)
		local k = math.abs(phi) / 88
		return biteY(phi) - 0.085 + 0.06 * k * k * k
	end, 0)
	lipBand(g, "LowerLip", llip, function(k)
		return 0.13 - 0.06 * k * k
	end, function(k)
		return 0.085 - 0.03 * k * k
	end, P.lip)

	-- ===================== ВЕРХНЯЯ ГУБА (UpperLip) =====================
	local ulip = archPts(AX + 0.025, AZ + 0.03, Z0, -88, 88, 16, function(phi)
		local k = math.abs(phi) / 88
		return biteY(phi) + 0.1 - 0.1 * k * k * k
	end, 0)
	lipBand(g, "UpperLip", ulip, function(k)
		return 0.12 - 0.05 * k * k
	end, function(k)
		return 0.07 - 0.025 * k * k
	end, P.lip)
	-- бархатная угольная кожа между губой и ноздрями (едет вместе с губой); спереди не выступает за нос
	g.xf = RM
	g:ell("UpperLip", V(0, 5.5, -1.38), V(0.66, 0.3, 0.42), P.muzzle, "SmoothPlastic", V(-12, 0, 0))
	for _, s in { 1, -1 } do
		g:ell("UpperLip", V(s * 0.2, 5.46, -1.26), V(0.36, 0.32, 0.5), P.muzzle:Lerp(P.cheek, 0.25), "SmoothPlastic", V(-10, s * -25, 0))
	end
	g.xf = nil
	g:setMap(nil)
end

return Head
