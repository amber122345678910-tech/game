--!strict
-- Юта Оккоцу (арка «Игра смерти», колония Сэндай).
-- Белая куртка магической школы: высокий воротник-стойка до челюсти, косая застёжка к его левому боку
-- с двумя золотыми пуговицами, свободный «блузон» с собранным поясом на бёдрах, пышные рукава подтянуты
-- чуть ниже локтя (предплечья открыты). Чёрные узкие брюки с белым шнурком, белые кеды с тёмной подошвой
-- и шнурками. Пятна крови: левое плечо у воротника, горизонтальный мазок по животу, правая ладонь.
-- Серебряное кольцо на безымянном пальце левой руки. Катаны в кадре нет — кость Katana остаётся пустой.
-- Все координаты — в осях кости в позе покоя (X вправо от персонажа, Y вверх, −Z вперёд).

local Sculpt = require(script.Parent.Sculpt)
local Skeletons = require(script.Parent.Parent.Skeletons)
local MathX = require(script.Parent.Parent.Math)

local Yuta = {}

type Ctx = Sculpt.Ctx
type Opts = Sculpt.Opts

local P = Skeletons.YutaProportions
local V = Vector3.new
local hex = Sculpt.hex
local rad = math.rad

local COL = {
	jacket = hex("#EDEEF4"),
	jacketShade = hex("#C6C8D8"),
	jacketLine = hex("#9FA3BC"), -- швы
	jacketInner = hex("#8E92AC"), -- тень внутри воротника и манжет
	button = hex("#AFAC95"),
	blood = hex("#621D1F"),
	bloodDark = hex("#2F070A"),
	pants = hex("#1E1F2B"),
	pantsShade = hex("#15151E"),
	pantsLine = hex("#0B0B11"),
	string = hex("#E6E7EE"),
	shoe = hex("#EDEDEC"),
	shoeShade = hex("#C9CAD2"),
	shoeSole = hex("#2E2E36"),
	lace = hex("#2A2A32"),
	skin = hex("#F2D2B8"),
	skinShade = hex("#D6AE90"),
	skinLine = hex("#B4836C"),
	lip = hex("#A0645C"),
	eyeWhite = hex("#F7F4F1"),
	iris = hex("#3A3A40"),
	pupil = hex("#121116"),
	lash = hex("#17131B"),
	bag = hex("#A87A72"), -- мешки под глазами
	hair = hex("#15151F"),
	hairSheen = hex("#2C3540"), -- холодный зеленовато-серый отлив
	ring = hex("#D4D8E0"),
}

local OUTLINE = Color3.fromRGB(16, 16, 24)
local HAIR_OUTLINE = Color3.fromRGB(10, 10, 16)
local MIN = 0.05 -- минимальный размер детали
-- тонкие наклейки (черты лица, швы, кровь) не отбрасывают тень — без «ряби» теней на коже и ткани
local THIN: Opts = { castShadow = false }

------------------------------------------------------------------------------------------
-- Помощники
------------------------------------------------------------------------------------------

-- Эллипсоид любой толщины: деталь не меньше MIN, а тоньше делает SpecialMesh.Scale
local function ellS(ctx: Ctx, bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?): Part
	local real = V(math.max(size.X, MIN), math.max(size.Y, MIN), math.max(size.Z, MIN))
	local p = Sculpt.ellipsoid(ctx, bone, cf, real, color, opts)
	if real ~= size then
		local m = p:FindFirstChildOfClass("SpecialMesh")
		if m then
			m.Scale = size / real
		end
	end
	return p
end

-- Вытянутый эллипсоид от a до b (как Sculpt.segment, но может быть тоньше MIN)
local function seg(ctx: Ctx, bone: string, a: Vector3, b: Vector3, w: number, d: number, color: Color3, extend: number?): Part
	local dir = b - a
	local len = dir.Magnitude
	local y = if len > 1e-6 then dir.Unit else V(0, 1, 0)
	local refZ = V(0, 0, 1)
	if math.abs(y:Dot(refZ)) > 0.95 then
		refZ = V(1, 0, 0)
	end
	local x = y:Cross(refZ).Unit
	local z = x:Cross(y).Unit
	return ellS(ctx, bone, CFrame.fromMatrix((a + b) / 2, x, y, z), V(w, len * (extend or 1), d), color)
end

-- Тонкий эллипсоид-«лента» от a до b, плоскостью вдоль поверхности с нормалью n
local function band(ctx: Ctx, bone: string, a: Vector3, b: Vector3, n: Vector3, w: number, color: Color3, extend: number?): Part
	local dir = b - a
	local len = dir.Magnitude
	local y = if len > 1e-6 then dir.Unit else V(0, 1, 0)
	local z = (n - y * n:Dot(y)).Unit
	local x = y:Cross(z)
	return ellS(ctx, bone, CFrame.fromMatrix((a + b) / 2, x, y, z), V(w, len * (extend or 1.25), 0.012), color, THIN)
end

type Ell = { c: Vector3, h: Vector3 } -- центр и полуоси (оси кости)

local function ell(ctx: Ctx, bone: string, c: Vector3, size: Vector3, color: Color3, opts: Opts?): Ell
	Sculpt.ellipsoid(ctx, bone, CFrame.new(c), size, color, opts)
	return { c = c, h = size / 2 }
end

local function ellNormal(e: Ell, p: Vector3): Vector3
	local d = p - e.c
	return V(d.X / (e.h.X * e.h.X), d.Y / (e.h.Y * e.h.Y), d.Z / (e.h.Z * e.h.Z)).Unit
end

-- Передняя (side = -1) или задняя (side = 1) поверхность в точке (x, y)
local function ellZ(e: Ell, x: number, y: number, side: number): number
	local u = (x - e.c.X) / e.h.X
	local v = (y - e.c.Y) / e.h.Y
	return e.c.Z + side * e.h.Z * math.sqrt(math.max(0, 1 - u * u - v * v))
end

-- Самая выступающая вперёд точка набора эллипсоидов (лицо) и нормаль в ней
local function frontOf(list: { Ell }, x: number, y: number): (Vector3, Vector3)
	local bestZ = math.huge
	local best: Ell = list[1]
	for _, e in list do
		local u = (x - e.c.X) / e.h.X
		local v = (y - e.c.Y) / e.h.Y
		if u * u + v * v < 1 then
			local z = ellZ(e, x, y, -1)
			if z < bestZ then
				bestZ = z
				best = e
			end
		end
	end
	if bestZ == math.huge then
		bestZ = 0
	end
	local p = V(x, y, bestZ)
	return p, ellNormal(best, p)
end

-- Выход луча o + t·d из эллипсоида (дальнее пересечение) или nil
local function rayExit(e: Ell, o: Vector3, d: Vector3): number?
	local oo = (o - e.c) / e.h
	local dd = d / e.h
	local a = dd:Dot(dd)
	local b = 2 * oo:Dot(dd)
	local c = oo:Dot(oo) - 1
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	return (-b + math.sqrt(disc)) / (2 * a)
end

-- Внешняя оболочка объединения эллипсоидов: точка на луче из o в направлении dir и нормаль в ней
local function hull(list: { Ell }, o: Vector3, dir: Vector3): (Vector3, Vector3)
	local d = dir.Unit
	local bestT = -math.huge
	local best: Ell = list[1]
	for _, e in list do
		local t = rayExit(e, o, d)
		if t and t > bestT then
			bestT = t
			best = e
		end
	end
	if bestT == -math.huge then
		bestT = 0
	end
	local p = o + d * bestT
	return p, ellNormal(best, p)
end

-- CFrame «наклейки»: −Z детали смотрит наружу по нормали n, roll — поворот в плоскости (градусы)
local function decal(p: Vector3, n: Vector3, out: number, roll: number?): CFrame
	local pos = p + n * out
	local cf = MathX.lookAt(pos, pos + n, V(0, 1, 0))
	if roll and roll ~= 0 then
		cf = cf * CFrame.Angles(0, 0, rad(roll))
	end
	return cf
end

-- Направление из центра по азимуту a (градусы, 0 — вперёд, +90 — вправо) и наклону к вертикали dy
local function az(aDeg: number, dy: number): Vector3
	local a = rad(aDeg)
	return V(math.sin(a), dy, -math.cos(a))
end

-- «Стадион»: коробка + два вертикальных цилиндра по бокам — плоский перед и спина, круглые бока.
-- Так выглядит свободная куртка (не бочка и не «грудные мышцы»).
type Stadium = { c: Vector3, bw: number, r: number, h: number }

local function stadium(ctx: Ctx, bone: string, st: Stadium, color: Color3)
	Sculpt.box(ctx, bone, CFrame.new(st.c), V(st.bw * 2, st.h * 2, st.r * 2), color)
	for _, s in { -1, 1 } do
		Sculpt.cylinder(ctx, bone, CFrame.new(st.c + V(s * st.bw, 0, 0)) * CFrame.Angles(0, 0, math.pi / 2), V(st.h * 2, st.r * 2, st.r * 2), color)
	end
end

-- Точка на боковой поверхности стадиона по азимуту и высоте y; возвращает точку и нормаль
local function stPoint(st: Stadium, aDeg: number, y: number): (Vector3, Vector3)
	local a = rad(aDeg)
	local d = V(math.sin(a), 0, -math.cos(a))
	local o = V(st.c.X, y, st.c.Z)
	local ca = math.abs(d.Z)
	if ca > 1e-6 then
		local tf = st.r / ca
		if math.abs(d.X) * tf <= st.bw then
			return o + d * tf, V(0, 0, if d.Z < 0 then -1 else 1)
		end
	end
	local sgn = if d.X < 0 then -1 else 1
	local C = V(sgn * st.bw, 0, 0)
	local dc = d:Dot(C)
	local t = dc + math.sqrt(math.max(0, dc * dc - C:Dot(C) + st.r * st.r))
	local p = o + d * t
	local n = (p - (o + C)).Unit
	return p, n
end

-- Линия по набору точек и нормалей (тонкая лента, приподнятая на out)
local function ribbon(ctx: Ctx, bone: string, pts: { Vector3 }, nrm: { Vector3 }, w: number, color: Color3, out: number?)
	local o = out or 0.004
	for i = 1, #pts - 1 do
		local n = (nrm[i] + nrm[i + 1]).Unit
		band(ctx, bone, pts[i] + nrm[i] * o, pts[i + 1] + nrm[i + 1] * o, n, w, color)
	end
end

-- Линия по стадиону: список {азимут, y}
local function stLine(ctx: Ctx, bone: string, st: Stadium, path: { { number } }, w: number, color: Color3)
	local pts, nrm = {}, {}
	for i, q in path do
		pts[i], nrm[i] = stPoint(st, q[1], q[2])
	end
	ribbon(ctx, bone, pts, nrm, w, color)
end

-- Линия по оболочке эллипсоидов: направления из центра o
local function hullLine(ctx: Ctx, bone: string, list: { Ell }, o: Vector3, dirs: { Vector3 }, w: number, color: Color3)
	local pts, nrm = {}, {}
	for i, d in dirs do
		pts[i], nrm[i] = hull(list, o, d)
	end
	ribbon(ctx, bone, pts, nrm, w, color)
end

-- Линия по вертикальному цилиндру (рукав): центр c, радиус r, список {азимут, dy}
local function sleeveLine(ctx: Ctx, bone: string, c: Vector3, r: number, path: { { number } }, w: number, color: Color3)
	local pts, nrm = {}, {}
	for i, q in path do
		local n = az(q[1], 0)
		nrm[i] = n
		pts[i] = c + n * r + V(0, q[2], 0)
	end
	ribbon(ctx, bone, pts, nrm, w, color)
end

-- Пятно на поверхности (точка p, нормаль n)
local function spot(ctx: Ctx, bone: string, p: Vector3, n: Vector3, w: number, h: number, color: Color3, out: number, roll: number?)
	ellS(ctx, bone, decal(p, n, out, roll), V(w, h, 0.012), color, THIN)
end

------------------------------------------------------------------------------------------
-- Голова и лицо (кость Head; начало — основание черепа, 5.04 над землёй)
------------------------------------------------------------------------------------------

local SKULL: Ell = { c = V(0, 0.53, 0.03), h = V(0.3, 0.35, 0.35) }
local MASK: Ell = { c = V(0, 0.37, -0.08), h = V(0.215, 0.32, 0.25) }
local LOWER: Ell = { c = V(0, 0.18, -0.1), h = V(0.11, 0.13, 0.165) }
local CAP: Ell = { c = V(0, 0.62, 0.05), h = V(0.32, 0.3, 0.38) } -- шапка волос
local CHIN: Ell = { c = V(0, 0.085, -0.15), h = V(0.065, 0.065, 0.07) }
local HEAD_C = V(0, 0.48, 0.03) -- центр для лучей по поверхности головы
local FACE: { Ell } = { MASK, LOWER, CHIN, SKULL }

-- Черта лица: тонкая наклейка по (x, y) спереди
local function mark(ctx: Ctx, x: number, y: number, w: number, h: number, color: Color3, out: number, roll: number?)
	local p, n = frontOf(FACE, x, y)
	spot(ctx, "Head", p, n, w, h, color, out, roll)
end

local function buildHead(ctx: Ctx)
	local H = "Head"
	-- шея (под высоким воротником видна только у подбородка)
	Sculpt.ellipsoid(ctx, "Neck", CFrame.new(0, 0.22, 0.02), V(0.24, 0.68, 0.24), COL.skin)
	-- тень под челюстью
	Sculpt.ellipsoid(ctx, H, CFrame.new(0, 0.04, -0.02), V(0.18, 0.1, 0.16), COL.skinShade)
	for _, e in FACE do
		ell(ctx, H, e.c, e.h * 2, COL.skin)
	end
	for _, s in { -1, 1 } do
		-- линия челюсти: от угла к подбородку (узкое лицо)
		Sculpt.segment(ctx, H, V(s * 0.165, 0.36, -0.03), V(s * 0.03, 0.08, -0.145), 0.08, 0.13, COL.skin)
		-- ухо
		Sculpt.ellipsoid(ctx, H, CFrame.new(s * 0.28, 0.37, 0.06) * CFrame.Angles(rad(-10), 0, rad(s * 6)), V(0.06, 0.16, 0.1), COL.skin)
		ellS(ctx, H, CFrame.new(s * 0.303, 0.37, 0.055) * CFrame.Angles(rad(-10), 0, 0), V(0.02, 0.09, 0.05), COL.skinShade)
	end

	for _, s in { -1, 1 } do
		local ex, ey = s * 0.11, 0.38
		-- белок
		mark(ctx, ex, ey - 0.002, 0.118, 0.058, COL.eyeWhite, 0.001)
		-- радужка, зрачок, блик: взгляд чуть влево (−X), верх прикрыт тяжёлым веком
		mark(ctx, ex - 0.008, ey - 0.004, 0.05, 0.058, COL.iris, 0.003)
		mark(ctx, ex - 0.008, ey - 0.006, 0.022, 0.026, COL.pupil, 0.005)
		mark(ctx, ex - 0.02, ey + 0.004, 0.012, 0.012, COL.eyeWhite, 0.007)
		-- верхнее веко: прямая усталая линия ресниц, внешний край опущен
		mark(ctx, ex + s * 0.004, ey + 0.026, 0.142, 0.024, COL.lash, 0.006, -s * 5)
		mark(ctx, ex + s * 0.066, ey + 0.01, 0.04, 0.015, COL.lash, 0.006, -s * 38)
		-- складка века
		mark(ctx, ex + s * 0.01, ey + 0.05, 0.1, 0.008, COL.skinLine, 0.002, -s * 6)
		-- нижнее веко и мешки под глазами (его примета)
		mark(ctx, ex + s * 0.012, ey - 0.034, 0.07, 0.007, COL.skinLine, 0.002, s * 5)
		mark(ctx, ex + s * 0.012, ey - 0.05, 0.08, 0.01, COL.bag, 0.002, s * 7)
		mark(ctx, ex + s * 0.02, ey - 0.064, 0.05, 0.008, COL.bag, 0.002, s * 12)
		-- бровь: спокойная, внутренний край чуть выше
		mark(ctx, ex + s * 0.005, ey + 0.098, 0.12, 0.018, COL.hair, 0.003, s * 6)
	end
	-- нос: маленький кончик, тень сбоку и снизу
	local np, nn = frontOf(FACE, 0, 0.27)
	ellS(ctx, H, decal(np, nn, -0.006), V(0.042, 0.05, 0.045), COL.skin)
	mark(ctx, -0.022, 0.31, 0.008, 0.07, COL.skinShade, 0.004, -6)
	mark(ctx, 0, 0.243, 0.04, 0.011, COL.skinShade, 0.004)
	-- рот: маленький, спокойный
	mark(ctx, 0, 0.158, 0.07, 0.01, COL.lip, 0.002)
	mark(ctx, 0, 0.138, 0.032, 0.007, COL.skinShade, 0.002)
	-- царапины и кровь на щеке и подбородке (после боя)
	mark(ctx, -0.15, 0.28, 0.065, 0.009, COL.blood, 0.002, 28)
	mark(ctx, -0.145, 0.255, 0.04, 0.008, COL.blood, 0.002, 18)
	mark(ctx, 0.035, 0.08, 0.03, 0.012, COL.blood, 0.002, -20)
end

------------------------------------------------------------------------------------------
-- Волосы: объёмы + пучки-эллипсоиды + пряди Beam с острыми кончиками
------------------------------------------------------------------------------------------

-- Прядь с собственным контуром: второй, чуть более широкий тёмный Beam позади с тем же seed
-- (колышутся одинаково), сужается до нуля — кончики остаются острыми.
local function hairStrand(ctx: Ctx, pts: { Vector3 }, w0: number, seed: number)
	local n = #pts
	local widths, outer = {}, {}
	for i = 1, n do
		local f = (i - 1) / (n - 1)
		widths[i] = w0 * (1 - f) ^ 0.9
		outer[i] = (w0 * 1.2 + 0.025) * (1 - f) ^ 0.75
	end
	Sculpt.strand(ctx, "Head", pts, {
		widths = outer,
		color0 = HAIR_OUTLINE,
		lightInfluence = 0,
		stiffness = 0.6,
		segments = 8,
		seed = seed,
		zOffset = -0.05,
		name = "HairLine",
	})
	Sculpt.strand(ctx, "Head", pts, {
		widths = widths,
		color0 = COL.hair,
		color1 = COL.hairSheen,
		stiffness = 0.6,
		segments = 8,
		seed = seed,
		name = "Hair",
	})
end

local function buildHair(ctx: Ctx)
	local H = "Head"
	local head: { Ell } = { SKULL, MASK }
	local outer: { Ell } = { SKULL, MASK, CAP }
	-- точка на поверхности головы по направлению из центра + вынос
	local function hp(dir: Vector3, off: number): Vector3
		local p, n = hull(head, HEAD_C, dir)
		return p + n * off
	end
	-- точка на лбу по (x, y), поверх шапки волос
	local function fp(x: number, y: number, off: number): Vector3
		local p, n = frontOf(outer, x, y)
		return p + n * off
	end
	-- шапка волос: наклонена (спереди выше, сзади ниже)
	ell(ctx, H, CAP.c, CAP.h * 2, COL.hair)
	-- затылок и шея сзади
	Sculpt.ellipsoid(ctx, H, CFrame.new(0, 0.43, 0.1), V(0.65, 0.58, 0.56), COL.hair)
	Sculpt.ellipsoid(ctx, H, CFrame.new(0, 0.25, 0.15), V(0.48, 0.32, 0.38), COL.hair)
	-- блик (холодный отлив) полосой по макушке
	for _, a in { -50, -20, 15, 45 } do
		seg(ctx, H, hp(az(a, 1.25), 0.0), hp(az(a + 4, 0.75), 0.006), 0.07, 0.04, COL.hairSheen)
	end
	-- пучок: корень -> середина -> острый кончик
	local function clump(a: Vector3, b: Vector3, c: Vector3, w: number)
		seg(ctx, H, a, b, w, w * 0.55, COL.hair, 1.2)
		seg(ctx, H, b, c, w * 0.62, w * 0.4, COL.hair, 1.12)
	end
	-- чёлка: пробор справа от центра (его правая сторона, +X), пряди зачёсаны через лоб к его левому
	-- виску; центральная прядь спускается до переносицы
	clump(fp(0.07, 0.8, -0.035), fp(0.0, 0.6, 0.015), fp(-0.025, 0.4, 0.012), 0.15)
	clump(fp(0.02, 0.8, -0.035), fp(-0.1, 0.62, 0.015), fp(-0.16, 0.45, 0.012), 0.15)
	clump(fp(-0.05, 0.79, -0.035), fp(-0.19, 0.61, 0.012), fp(-0.245, 0.43, 0.01), 0.14)
	clump(fp(-0.12, 0.77, -0.035), fp(-0.25, 0.6, 0.01), fp(-0.285, 0.37, 0.01), 0.12)
	clump(fp(0.12, 0.8, -0.035), fp(0.17, 0.62, 0.012), fp(0.19, 0.46, 0.012), 0.14)
	clump(fp(0.17, 0.77, -0.035), fp(0.245, 0.6, 0.01), fp(0.275, 0.41, 0.01), 0.12)
	for _, s in { -1, 1 } do
		-- пряди перед ушами до линии челюсти
		clump(hp(V(s, 0.5, -0.5), 0.02), hp(V(s, -0.1, -0.5), 0.025), hp(V(s, -0.75, -0.42), 0.012), 0.1)
		-- над ушами и за ними
		clump(hp(V(s, 0.5, -0.1), 0.03), hp(V(s, -0.2, 0.05), 0.035), hp(V(s, -0.65, 0.1), 0.012), 0.12)
		clump(hp(V(s, 0.6, 0.3), 0.03), hp(V(s, 0.0, 0.4), 0.04), hp(V(s, -0.5, 0.45), 0.015), 0.12)
	end
	-- затылок: острые пряди до воротника
	for _, x in { -0.18, -0.06, 0.06, 0.18 } do
		clump(hp(V(x * 3, 0.3, 1), 0.04), hp(V(x * 3.4, -0.4, 1), 0.04), hp(V(x * 3.6, -1.1, 0.9), 0.015), 0.13)
	end

	-- растрёпанные пряди-«шипы» после боя (Beam с контуром)
	local strands: { { Vector3 } } = {
		-- макушка
		{ hp(V(0.05, 1, 0.1), 0.0), hp(V(0.1, 1, 0.5), 0.08), hp(V(0.05, 0.8, 0.9), 0.14) },
		{ hp(V(-0.35, 1, 0.2), 0.0), hp(V(-0.6, 1, 0.45), 0.07), hp(V(-0.9, 0.7, 0.7), 0.12) },
		{ hp(V(0.35, 1, 0.15), 0.0), hp(V(0.6, 1, 0.4), 0.07), hp(V(0.95, 0.75, 0.6), 0.11) },
		{ hp(V(0.0, 1, -0.3), 0.0), hp(V(-0.15, 0.95, -0.7), 0.06), hp(V(-0.35, 0.75, -1), 0.1) },
		-- затылок
		{ hp(V(-0.3, 0.4, 1), 0.02), hp(V(-0.45, 0.0, 1), 0.08), hp(V(-0.6, -0.4, 1), 0.12) },
		{ hp(V(0.25, 0.3, 1), 0.02), hp(V(0.4, -0.1, 1), 0.08), hp(V(0.55, -0.5, 1), 0.11) },
		-- бока
		{ hp(V(-1, 0.5, 0.0), 0.02), hp(V(-1, 0.3, 0.1), 0.08), hp(V(-1, -0.05, 0.25), 0.12) },
		{ hp(V(1, 0.55, 0.05), 0.02), hp(V(1, 0.35, 0.2), 0.08), hp(V(1, 0.0, 0.35), 0.12) },
		-- тонкие пряди поперёк лба
		{ fp(0.07, 0.68, 0.04), fp(0.0, 0.55, 0.045), fp(-0.07, 0.43, 0.03) },
		{ fp(-0.15, 0.68, 0.04), fp(-0.2, 0.54, 0.042), fp(-0.205, 0.41, 0.03) },
	}
	for i, pts in strands do
		hairStrand(ctx, pts, if i >= 9 then 0.05 else 0.06, i * 1.7)
	end
end

------------------------------------------------------------------------------------------
-- Куртка и брюки (корпус)
------------------------------------------------------------------------------------------

-- Корпус куртки: стадионы в осях костей
local CHEST_ST: Stadium = { c = V(0, -0.05, 0.02), bw = 0.3, r = 0.36, h = 0.3 } -- Chest (4.22)
local SPINE_ST: Stadium = { c = V(0, 0.12, 0.02), bw = 0.28, r = 0.35, h = 0.4 } -- Spine (3.60)

local function buildTorso(ctx: Ctx)
	stadium(ctx, "Chest", CHEST_ST, COL.jacket)
	-- плечевой пояс: скругляет верх, плечи покатые
	local yoke = ell(ctx, "Chest", V(0, 0.25, 0.02), V(1.5, 0.5, 0.72), COL.jacket)
	stadium(ctx, "Spine", SPINE_ST, COL.jacket)
	-- «блузон» над поясом и собранный пояс (Hips, 3.05)
	local blouse = ell(ctx, "Hips", V(0, 0.3, 0.02), V(1.36, 0.5, 0.8), COL.jacket)
	ell(ctx, "Hips", V(0, 0.07, 0.02), V(1.18, 0.16, 0.72), COL.jacketShade)
	-- брюки: таз
	local pelvis = ell(ctx, "Hips", V(0, -0.1, 0.03), V(0.94, 0.56, 0.66), COL.pants)

	-- Воротник-стойка: кольцо пластин вокруг шеи, расширяется кверху, спереди ниже
	local N = 20
	local yBot = 0.46
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		local top = 0.84 + 0.08 * (1 - math.cos(a)) / 2
		local h = top - yBot
		local yc = (top + yBot) / 2
		local rx0, rz0, rx1, rz1 = 0.235, 0.215, 0.3, 0.28
		local rx, rz = (rx0 + rx1) / 2, (rz0 + rz1) / 2
		local pos = V(rx * math.sin(a), yc, 0.02 - rz * math.cos(a))
		local nrm = V(math.sin(a) / rx, 0, -math.cos(a) / rz).Unit
		local flare = math.atan((rx1 - rx0) / h)
		local up = (V(0, 1, 0) * math.cos(flare) + nrm * math.sin(flare)).Unit
		local zA = (nrm - up * nrm:Dot(up)).Unit
		local xA = up:Cross(zA)
		local w = 2 * math.pi * (rx + 0.01) / N * 1.18
		Sculpt.box(ctx, "Chest", CFrame.fromMatrix(pos, xA, up, zA), V(w, h, 0.05), COL.jacket)
	end
	-- тень внутри воротника
	Sculpt.ellipsoid(ctx, "Chest", CFrame.new(0, 0.8, 0.03), V(0.52, 0.04, 0.49), COL.jacketInner)
	-- край клапана воротника (его левая сторона) и верхняя пуговица
	do
		local a = rad(-38)
		local nrm = V(math.sin(a), 0, -math.cos(a))
		local function onCollar(y: number): Vector3
			local t = (y - yBot) / 0.44
			local rx = 0.235 + 0.065 * t + 0.027
			local rz = 0.215 + 0.065 * t + 0.027
			return V(rx * math.sin(a), y, 0.02 - rz * math.cos(a))
		end
		ribbon(ctx, "Chest", { onCollar(0.47), onCollar(0.66), onCollar(0.84) }, { nrm, nrm, nrm }, 0.018, COL.jacketLine, 0.0)
		Sculpt.ball(ctx, "Chest", onCollar(0.75) + V(-0.03, 0, -0.01), 0.05, COL.button, { material = Enum.Material.Metal })
	end
	-- косая застёжка: от основания воротника к его левому боку, вниз до пояса
	do
		local p1, n1 = hull({ yoke }, V(0, 0.25, 0.02), az(-14, 0.9))
		local p2, n2 = hull({ yoke }, V(0, 0.25, 0.02), az(-28, 0.35))
		local p3, n3 = stPoint(CHEST_ST, -34, 0.12)
		local p4, n4 = stPoint(CHEST_ST, -34, -0.36)
		ribbon(ctx, "Chest", { p1, p2, p3, p4 }, { n1, n2, n3, n4 }, 0.02, COL.jacketLine)
		Sculpt.ball(ctx, "Chest", p2 + n2 * 0.012 + V(0.04, 0, 0), 0.05, COL.button, { material = Enum.Material.Metal })
		stLine(ctx, "Spine", SPINE_ST, { { -34, 0.5 }, { -34, -0.28 } }, 0.02, COL.jacketLine)
		hullLine(ctx, "Hips", { blouse }, V(0, 0.3, 0.02), { az(-31, 0.7), az(-31, 0.0), az(-30, -0.6) }, 0.02, COL.jacketLine)
	end
	-- складки: от подмышек к центру, на спине, на боках, над поясом
	for _, s in { -1, 1 } do
		stLine(ctx, "Chest", CHEST_ST, { { s * 75, 0.15 }, { s * 52, -0.12 }, { s * 38, -0.32 } }, 0.035, COL.jacketShade)
		stLine(ctx, "Chest", CHEST_ST, { { s * 140, 0.15 }, { s * 165, -0.25 } }, 0.035, COL.jacketShade)
		stLine(ctx, "Spine", SPINE_ST, { { s * 88, 0.45 }, { s * 70, 0.0 }, { s * 64, -0.25 } }, 0.035, COL.jacketShade)
		stLine(ctx, "Spine", SPINE_ST, { { s * 150, 0.3 }, { s * 140, -0.2 } }, 0.035, COL.jacketShade)
	end
	for _, a in { -70, -20, 25, 60, 110, 150, 180, 215, 250 } do
		hullLine(ctx, "Hips", { blouse }, V(0, 0.3, 0.02), { az(a, -0.9), az(a + 6, -0.1) }, 0.04, COL.jacketShade)
	end

	-- кровь: левое плечо у воротника (его лево = −X), мазок через живот
	local function yokeSpot(dir: Vector3, w: number, h: number, color: Color3, out: number, roll: number)
		local p, n = hull({ yoke }, V(0, 0.25, 0.02), dir)
		spot(ctx, "Chest", p, n, w, h, color, out, roll)
	end
	yokeSpot(az(-40, 0.75), 0.24, 0.16, COL.blood, 0.0, 20)
	yokeSpot(az(-56, 0.65), 0.15, 0.11, COL.blood, 0.0, -15)
	yokeSpot(az(-45, 0.7), 0.1, 0.06, COL.bloodDark, 0.003, 30)
	do
		local p, n = stPoint(CHEST_ST, -40, 0.12)
		spot(ctx, "Chest", p, n, 0.05, 0.12, COL.blood, 0.002, 10)
	end
	stLine(ctx, "Spine", SPINE_ST, { { -52, 0.12 }, { -24, 0.11 }, { 6, 0.08 }, { 36, 0.03 } }, 0.05, COL.blood)
	do
		local p, n = stPoint(SPINE_ST, -8, 0.1)
		spot(ctx, "Spine", p, n, 0.18, 0.03, COL.bloodDark, 0.006, -4)
		local q, m = stPoint(SPINE_ST, 18, 0.0)
		spot(ctx, "Spine", q, m, 0.025, 0.1, COL.blood, 0.004, 0)
	end

	-- шнурок брюк: бантик под поясом куртки
	local kz = ellZ(pelvis, 0, -0.02, -1)
	Sculpt.ellipsoid(ctx, "Hips", CFrame.new(0, -0.02, kz - 0.015), V(0.06, 0.05, 0.05), COL.string)
	for _, s in { -1, 1 } do
		ellS(ctx, "Hips", CFrame.new(s * 0.045, -0.015, kz - 0.012) * CFrame.Angles(0, 0, rad(s * 20)), V(0.075, 0.035, 0.03), COL.string)
		Sculpt.strand(ctx, "Hips", { V(s * 0.015, -0.03, kz - 0.02), V(s * 0.03, -0.17, kz - 0.025), V(s * 0.045, -0.31, kz - 0.005) }, {
			widths = { 0.032, 0.03, 0.028 },
			color0 = COL.string,
			stiffness = 0.2,
			segments = 6,
			lightInfluence = 0.4,
			name = "Drawstring",
		})
	end
	-- пояс брюк под курткой
	Sculpt.ellipsoid(ctx, "Hips", CFrame.new(0, 0.02, 0.03), V(0.98, 0.1, 0.68), COL.pantsShade)
	-- шов ширинки
	hullLine(ctx, "Hips", { pelvis }, pelvis.c, { az(0, 0.1), az(0, -0.4), az(0, -0.8) }, 0.016, COL.pantsLine)
end

------------------------------------------------------------------------------------------
-- Руки
------------------------------------------------------------------------------------------

local function buildArm(ctx: Ctx, side: string)
	local sx = if side == "L" then -1 else 1
	local UA, LA = "UpperArm" .. side, "LowerArm" .. side
	-- плечо и пышный рукав (расширяется к локтю)
	Sculpt.ellipsoid(ctx, UA, CFrame.new(-sx * 0.03, -0.17, 0.01), V(0.47, 0.44, 0.47), COL.jacket)
	-- рукав-труба (висит прямо), сверху и снизу скруглён плечом и локтем
	Sculpt.cylinder(ctx, UA, CFrame.new(sx * 0.01, -0.6, 0.01) * CFrame.Angles(0, 0, math.pi / 2), V(0.78, 0.43, 0.43), COL.jacket)
	local sleeve = { { c = V(sx * 0.01, -0.56, 0.01), h = V(0.215, 0.6, 0.215) } }
	local SC = V(sx * 0.01, -0.56, 0.01)
	-- складки рукава
	sleeveLine(ctx, UA, SC, 0.215, { { sx * 60, 0.25 }, { sx * 35, -0.05 }, { sx * 20, -0.3 } }, 0.03, COL.jacketShade)
	sleeveLine(ctx, UA, SC, 0.215, { { sx * 100, 0.1 }, { sx * 115, -0.3 } }, 0.03, COL.jacketShade)
	sleeveLine(ctx, UA, SC, 0.215, { { sx * 160, -0.05 }, { sx * 195, -0.35 } }, 0.03, COL.jacketShade)
	sleeveLine(ctx, UA, SC, 0.215, { { -sx * 70, 0.2 }, { -sx * 50, -0.2 } }, 0.03, COL.jacketShade)
	-- локоть: сборка рукава (шарнир)
	local elbow = ell(ctx, LA, V(0, -0.04, 0.01), V(0.45, 0.48, 0.45), COL.jacket)
	local bunch = ell(ctx, LA, V(0, -0.25, 0.0), V(0.39, 0.34, 0.39), COL.jacket)
	-- складки-кольца сборки
	ellS(ctx, LA, CFrame.new(0, -0.16, 0.005), V(0.42, 0.02, 0.42), COL.jacketShade)
	ellS(ctx, LA, CFrame.new(0, -0.33, 0.0), V(0.355, 0.02, 0.355), COL.jacketShade)
	local EC = V(0, -0.15, 0.0)
	hullLine(ctx, LA, { elbow, bunch }, EC, { V(sx, 0.5, -0.4), V(sx * 0.6, -0.2, -1) }, 0.03, COL.jacketShade)
	hullLine(ctx, LA, { elbow, bunch }, EC, { V(-sx, 0.5, 0.3), V(-sx * 0.5, -0.4, 1) }, 0.03, COL.jacketShade)
	-- манжета (собранный край) и тень под ней
	Sculpt.ellipsoid(ctx, LA, CFrame.new(0, -0.41, 0.0), V(0.3, 0.12, 0.3), COL.jacketShade)
	Sculpt.ellipsoid(ctx, LA, CFrame.new(0, -0.45, 0.0), V(0.2, 0.06, 0.21), COL.jacketInner)
	-- открытое предплечье
	Sculpt.ellipsoid(ctx, LA, CFrame.new(0, -0.6, 0.0), V(0.2, 0.52, 0.2), COL.skin)
	Sculpt.ellipsoid(ctx, LA, CFrame.new(0, -0.83, 0.0), V(0.14, 0.32, 0.165), COL.skin)
end

local FINGERS = { "Index", "Middle", "Ring", "Pinky" }
local FSCALE: { [string]: number } = { Index = 0.92, Middle = 1.0, Ring = 0.95, Pinky = 0.76 }
local FWIDTH: { [string]: number } = { Index = 0.07, Middle = 0.072, Ring = 0.068, Pinky = 0.06 }

-- Фаланга: цилиндр от сустава до сустава и шарик на дальнем конце (сгиб без щелей)
local function phalanx(ctx: Ctx, bone: string, tip: Vector3, w: number, base: boolean?)
	local len = tip.Magnitude
	if len > 0.03 then
		Sculpt.cylinder(ctx, bone, MathX.axisX(tip / 2, tip), V(len, w, w), COL.skin)
	end
	Sculpt.ball(ctx, bone, tip, w * 0.98, COL.skin)
	if base then
		Sculpt.ball(ctx, bone, V(0, 0, 0), w * 1.04, COL.skin)
	end
end

local function buildHand(ctx: Ctx, side: string)
	local sx = if side == "L" then -1 else 1
	local HB = "Hand" .. side
	-- запястье (шарнир)
	Sculpt.ellipsoid(ctx, HB, CFrame.new(0, -0.01, 0), V(0.12, 0.14, 0.17), COL.skin)
	-- ладонь: плоская, расширяется к костяшкам; ладонь смотрит к телу (−sx), тыльная сторона — наружу
	Sculpt.ellipsoid(ctx, HB, CFrame.new(0, -0.15, 0), V(0.11, 0.38, 0.29), COL.skin)
	Sculpt.ellipsoid(ctx, HB, CFrame.new(0, -0.255, 0), V(0.095, 0.17, 0.325), COL.skin)
	-- подушка большого пальца и ребро ладони
	Sculpt.ellipsoid(ctx, HB, CFrame.new(-sx * 0.02, -0.11, -0.085), V(0.11, 0.2, 0.13), COL.skin)
	Sculpt.ellipsoid(ctx, HB, CFrame.new(-sx * 0.01, -0.15, 0.1), V(0.1, 0.24, 0.1), COL.skin)
	-- тень ладони
	local palm: Ell = { c = V(0, -0.165, 0), h = V(0.055, 0.17, 0.16) }
	do
		local p, n = hull({ palm }, palm.c, V(-sx, -0.05, 0))
		spot(ctx, HB, p, n, 0.17, 0.2, COL.skinShade, 0.0)
		if side == "R" then
			-- кровь на ладони
			local q, m = hull({ palm }, palm.c, V(-sx, -0.25, 0.2))
			spot(ctx, HB, q, m, 0.13, 0.08, COL.blood, 0.004, 30)
		end
	end
	for _, f in FINGERS do
		local s = FSCALE[f]
		local w = FWIDTH[f]
		phalanx(ctx, f .. "1" .. side, V(0, -P.fingerLen[1] * s, 0), w, true)
		phalanx(ctx, f .. "2" .. side, V(0, -P.fingerLen[2] * s, 0), w * 0.94)
		phalanx(ctx, f .. "3" .. side, V(0, -0.07 * s, 0), w * 0.88)
	end
	local t1 = P.thumbLen[1]
	phalanx(ctx, "Thumb1" .. side, V(0, -t1, -t1 * 0.35), 0.085, true)
	phalanx(ctx, "Thumb2" .. side, V(0, -P.thumbLen[2], 0), 0.078)
	phalanx(ctx, "Thumb3" .. side, V(0, -0.065, -0.005), 0.07)
	if side == "L" then
		-- кольцо Оримото: тонкий серебряный ободок на безымянном
		ellS(ctx, "Ring1L", CFrame.new(0, -0.06, 0), V(0.084, 0.026, 0.084), COL.ring, {
			material = Enum.Material.Metal,
			reflectance = 0.35,
			name = "OrimotoRing",
		})
	end
end

------------------------------------------------------------------------------------------
-- Ноги и обувь
------------------------------------------------------------------------------------------

local function buildLeg(ctx: Ctx, side: string)
	local sx = if side == "L" then -1 else 1
	local UL, LL, FT, TO = "UpperLeg" .. side, "LowerLeg" .. side, "Foot" .. side, "Toe" .. side
	-- бедро: объём сверху, ниже — прямая «труба» брючины до колена
	local thigh = ell(ctx, UL, V(sx * 0.01, -0.42, 0.0), V(0.5, 1.1, 0.52), COL.pants)
	Sculpt.cylinder(ctx, UL, CFrame.new(0, -1.035, -0.005) * CFrame.Angles(0, 0, math.pi / 2), V(0.77, 0.39, 0.39), COL.pants)
	local legU: { Ell } = { thigh, { c = V(0, -1.035, -0.005), h = V(0.195, 0.6, 0.195) } }
	local TC = V(0, -0.75, 0)
	-- складки брюк
	hullLine(ctx, UL, legU, TC, { V(-sx * 0.4, 0.9, -1), V(-sx * 0.2, 0.3, -1) }, 0.02, COL.pantsLine)
	hullLine(ctx, UL, legU, TC, { V(sx * 0.6, -0.3, -1), V(sx * 0.1, -0.9, -1) }, 0.02, COL.pantsLine)
	hullLine(ctx, UL, legU, TC, { V(-sx * 0.8, -0.9, 1), V(sx * 0.3, -1.3, 1) }, 0.02, COL.pantsLine)
	-- колено (шарнир-шар того же диаметра, что и брючина) и голень
	Sculpt.ball(ctx, LL, V(0, 0, -0.005), 0.39, COL.pants)
	Sculpt.cylinder(ctx, LL, CFrame.new(0, -0.225, 0.0) * CFrame.Angles(0, 0, math.pi / 2), V(0.45, 0.375, 0.375), COL.pants)
	local calf = ell(ctx, LL, V(0, -0.45, 0.02), V(0.37, 0.9, 0.4), COL.pants)
	Sculpt.ellipsoid(ctx, LL, CFrame.new(0, -0.88, 0.0), V(0.3, 0.8, 0.32), COL.pants)
	local legL: { Ell } = { { c = V(0, -0.1, 0), h = V(0.19, 0.4, 0.19) }, calf }
	local KC = V(0, -0.2, 0.01)
	hullLine(ctx, LL, legL, KC, { V(sx * 0.7, 0.6, -1), V(-sx * 0.3, 0.3, -1) }, 0.02, COL.pantsLine)
	hullLine(ctx, LL, legL, KC, { V(-sx * 0.5, 0.5, 1), V(sx * 0.4, 0.35, 1) }, 0.02, COL.pantsLine)
	-- край брючины: лёгкая сборка над кедами
	Sculpt.ellipsoid(ctx, LL, CFrame.new(0, -1.13, 0.0), V(0.32, 0.16, 0.34), COL.pantsShade)
	ellS(ctx, LL, CFrame.new(0, -1.05, 0.0), V(0.31, 0.02, 0.33), COL.pantsLine)

	-- Кеды (белые, тёмная подошва и шнурки). Стопа: начало в лодыжке (0.2 над землёй)
	local heel = ell(ctx, FT, V(0, -0.075, 0.075), V(0.32, 0.27, 0.33), COL.shoe)
	local instep = ell(ctx, FT, V(0, -0.075, -0.2), V(0.33, 0.26, 0.6), COL.shoe)
	Sculpt.ellipsoid(ctx, FT, CFrame.new(0, 0.015, 0.03), V(0.29, 0.17, 0.32), COL.shoe)
	-- язычок
	Sculpt.ellipsoid(ctx, FT, CFrame.new(0, 0.02, -0.12) * CFrame.Angles(rad(-20), 0, 0), V(0.17, 0.08, 0.22), COL.shoeShade)
	-- шнурки поперёк подъёма
	for _, z in { -0.1, -0.17, -0.24, -0.31 } do
		local p, n = hull({ instep }, instep.c, V(0, instep.h.Y, z - instep.c.Z))
		local t = V(1, 0, 0)
		band(ctx, FT, p - t * 0.07 + n * 0.006, p + t * 0.07 + n * 0.006, n, 0.022, COL.lace, 1.0)
	end
	-- полоски по бокам и на пятке
	local SH = V(0, -0.075, -0.1)
	hullLine(ctx, FT, { heel, instep }, SH, { V(sx, 0.0, 0.8), V(sx, 0.2, -0.1), V(sx, 0.0, -0.8) }, 0.03, COL.shoeShade)
	hullLine(ctx, FT, { heel, instep }, SH, { V(0, 0.5, 1), V(0, -0.4, 1) }, 0.035, COL.shoeShade)
	-- подошва (SoleL/SoleR — для пыли от шагов)
	Sculpt.box(ctx, FT, CFrame.new(0, -0.168, -0.14), V(0.34, 0.064, 0.6), COL.shoeSole, { name = "Sole" .. side })
	Sculpt.cylinder(ctx, FT, CFrame.new(0, -0.168, 0.12) * CFrame.Angles(0, 0, math.pi / 2), V(0.064, 0.34, 0.34), COL.shoeSole)
	ellS(ctx, FT, CFrame.new(0, -0.13, -0.12), V(0.345, 0.03, 0.82), COL.shoeShade)
	-- носок (кость Toe: 0.05 над землёй)
	Sculpt.ellipsoid(ctx, TO, CFrame.new(0, 0.06, -0.01), V(0.32, 0.19, 0.26), COL.shoe)
	Sculpt.ellipsoid(ctx, TO, CFrame.new(0, 0.02, -0.02), V(0.335, 0.05, 0.3), COL.shoeShade)
	Sculpt.ellipsoid(ctx, TO, CFrame.new(0, -0.017, 0.0), V(0.34, 0.066, 0.32), COL.shoeSole)
end

------------------------------------------------------------------------------------------

function Yuta.build(origin: CFrame): Model
	local def = Skeletons.Yuta
	local ctx = Sculpt.newCharacter("Yuta", def, origin)
	buildHead(ctx)
	buildHair(ctx)
	buildTorso(ctx)
	for _, side in { "L", "R" } do
		buildArm(ctx, side)
		buildHand(ctx, side)
		buildLeg(ctx, side)
	end
	-- Катаны в этой сцене нет: кость Katana остаётся без деталей (её можно использовать позже)
	Sculpt.outline(ctx, OUTLINE)
	return ctx.model
end

return Yuta
