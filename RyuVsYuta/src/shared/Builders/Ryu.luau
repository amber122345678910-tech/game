--!strict
-- Рю Исигори (Сэндай, «Магическая битва»): строитель модели из простых деталей.
--
-- Геометрия задаётся в координатах модели в позе покоя (начало — на земле между стоп, -Z — вперёд),
-- привязанных к позициям костей; функция put() переводит их в оси кости (в покое кости не повёрнуты).
-- Мелкие детали лица и торса (глаза, брови, рот, линии мышц, цепочка) ставятся «на поверхность»:
-- frontOf() находит переднюю точку и нормаль по списку эллипсоидов, из которых слеплена эта часть тела.
--
-- Крупный план (лицо, кисти, помпадур с ~3 стадов) — главный приоритет:
--   * помпадур-«пушка»: ствол, перехват перед кончиком, тёмное «дуло», шов с зазубринами (кость Pompadour);
--   * кисти: ладонь, костяшки, 3 фаланги + ногти на костях пальцев;
--   * лицо: длинное, тяжёлая квадратная челюсть, узкие глаза, оскал с зубами, жилистая шея.

local Sculpt = require(script.Parent.Sculpt)
local Skeletons = require(script.Parent.Parent.Skeletons)
local Rig = require(script.Parent.Parent.Rig)
local MathX = require(script.Parent.Parent.Math)

local Ryu = {}

local V = Vector3.new
local hex = Sculpt.hex
local rad = math.rad

-- Палитра (визуальный справочник 3.9 + бриф)
local C = {
	skin = hex("#F2CBAC"),
	skinMid = hex("#E2B898"),
	skinShade = hex("#C99A82"), -- рельеф мышц
	skinLine = hex("#9D837F"), -- складки, ноздри
	skinDeep = hex("#624B53"), -- самые глубокие тени
	lip = hex("#D59A8A"),
	stubble = hex("#C19D8F"),
	nail = hex("#F6DACA"),
	sclera = hex("#F5E8EF"),
	iris = hex("#8FA3C8"),
	pupil = hex("#20202C"),
	lash = hex("#16141C"),
	brow = hex("#1A1A22"),
	teeth = hex("#F6DCCC"),
	mouthIn = hex("#7E5F64"),
	hair = hex("#2E2D3A"),
	hairShadow = hex("#16181D"),
	hairSheen = hex("#4A4A68"),
	muzzle = hex("#161821"),
	crease = hex("#191A25"),
	jacket = hex("#1C1C22"),
	jacketHi = hex("#2C2C36"),
	jacketSheen = hex("#3B4260"),
	zipper = hex("#9A9CA6"),
	fur = hex("#F2F2F4"),
	furShade = hex("#DFDEE5"),
	furShadow = hex("#9491B8"),
	furDeep = hex("#5E5D69"),
	furTip = hex("#2B2B35"),
	tag = hex("#B0B1AE"),
	chain = hex("#C6C3BA"),
	belt = hex("#5A2328"),
	beltEdge = hex("#3C2325"),
	buckle = hex("#6A6D74"),
	buckleHi = hex("#8E929B"),
	star = hex("#B8B048"),
	pants = hex("#28272F"),
	pantsSeam = hex("#1A1A20"),
	shoe = hex("#1C1B1A"),
	sole = hex("#0E0E10"),
}
local FUR_LINE = Color3.fromRGB(40, 40, 52)

local def: Rig.RigDef = Skeletons.Ryu
local ctx: Sculpt.Ctx = (nil :: any)

------------------------------------------------------------------------------------------
-- Базовые помощники
------------------------------------------------------------------------------------------

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- Позиция кости в покое (координаты модели)
local function bp(bone: string): Vector3
	return Rig.restOf(def, bone).Position
end

-- Координаты модели -> оси кости (в покое кости не повёрнуты, поэтому достаточно сдвига)
local function put(bone: string, cf: CFrame): CFrame
	return CFrame.new(-bp(bone)) * cf
end

-- Зеркало по X: s = 1 — правая сторона (+X), s = -1 — левая
local function mx(p: Vector3, s: number): Vector3
	return V(p.X * s, p.Y, p.Z)
end

local function at(p: Vector3, x: number?, y: number?, z: number?): CFrame
	return CFrame.new(p) * rot(x or 0, y or 0, z or 0)
end

-- Зеркальная версия at(): углы рыскания и крена меняют знак
local function atS(p: Vector3, s: number, x: number?, y: number?, z: number?): CFrame
	return CFrame.new(mx(p, s)) * rot(x or 0, (y or 0) * s, (z or 0) * s)
end

local function E(bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Sculpt.Opts?): Part
	return Sculpt.ellipsoid(ctx, bone, put(bone, cf), size, color, opts)
end

local function B(bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Sculpt.Opts?): Part
	return Sculpt.box(ctx, bone, put(bone, cf), size, color, opts)
end

local function Wd(bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Sculpt.Opts?): WedgePart
	return Sculpt.wedge(ctx, bone, put(bone, cf), size, color, opts)
end

local function Cyl(bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Sculpt.Opts?): Part
	return Sculpt.cylinder(ctx, bone, put(bone, cf), size, color, opts)
end

local function Seg(
	bone: string,
	a: Vector3,
	b: Vector3,
	w: number,
	d: number,
	color: Color3,
	opts: Sculpt.Opts?,
	roll: number?,
	extend: number?
): Part
	local o = bp(bone)
	return Sculpt.segment(ctx, bone, a - o, b - o, w, d, color, opts, roll, extend)
end

local function Ball(bone: string, p: Vector3, d: number, color: Color3, opts: Sculpt.Opts?): Part
	return Sculpt.ball(ctx, bone, p - bp(bone), d, color, opts)
end

local function Strand(bone: string, pts: { Vector3 }, o: Sculpt.StrandOpts?)
	local base = bp(bone)
	local loc = {}
	for i, p in pts do
		loc[i] = p - base
	end
	Sculpt.strand(ctx, bone, loc, o)
end

-- CFrame с осью Y вдоль dir и осью Z как можно ближе к zHint
local function frameY(pos: Vector3, dir: Vector3, zHint: Vector3): CFrame
	local y = dir.Unit
	local z = zHint - y * y:Dot(zHint)
	if z.Magnitude < 1e-4 then
		z = V(0, 0, 1) - y * y.Z
		if z.Magnitude < 1e-4 then
			z = V(1, 0, 0) - y * y.X
		end
	end
	z = z.Unit
	local x = y:Cross(z)
	return CFrame.fromMatrix(pos, x, y, z)
end

-- CFrame, чья ось -Z смотрит вдоль n (наружу), X — горизонтально; roll — поворот вокруг нормали (градусы)
local function frameOut(pos: Vector3, n: Vector3, roll: number?): CFrame
	local nn = n.Unit
	local x = nn:Cross(V(0, 1, 0))
	if x.Magnitude < 1e-4 then
		x = V(1, 0, 0)
	end
	x = x.Unit
	local z = -nn
	local y = z:Cross(x).Unit
	local cf = CFrame.fromMatrix(pos, x, y, z)
	if roll and roll ~= 0 then
		cf = cf * CFrame.Angles(0, 0, rad(roll))
	end
	return cf
end


-- Узкий «замок»/лента: эллипсоид от a до b, ширина w (по X), толщина t (по zHint)
local function lock(bone: string, a: Vector3, b: Vector3, w: number, t: number, zHint: Vector3, color: Color3, opts: Sculpt.Opts?): Part
	return E(bone, frameY((a + b) / 2, b - a, zHint), V(w, (b - a).Magnitude, t), color, opts)
end

------------------------------------------------------------------------------------------
-- «Поверхность» из эллипсоидов (без поворота) в локальных координатах o: передняя точка и нормаль
------------------------------------------------------------------------------------------

type Ell = { c: Vector3, r: Vector3 }
type Surf = { bone: string, o: Vector3, list: { Ell } }

local function frontOf(list: { Ell }, x: number, y: number): (number, Vector3)
	local bestZ = math.huge
	local bestN = V(0, 0, -1)
	for _, e in list do
		local dx = (x - e.c.X) / e.r.X
		local dy = (y - e.c.Y) / e.r.Y
		local q = 1 - dx * dx - dy * dy
		if q > 0 then
			local z = e.c.Z - e.r.Z * math.sqrt(q)
			if z < bestZ then
				bestZ = z
				local n = V((x - e.c.X) / (e.r.X * e.r.X), (y - e.c.Y) / (e.r.Y * e.r.Y), (z - e.c.Z) / (e.r.Z * e.r.Z))
				bestN = n.Unit
			end
		end
	end
	assert(bestZ < math.huge, "frontOf: точка вне поверхности")
	return bestZ, bestN
end

-- Точка поверхности (в координатах модели) и нормаль
local function sPoint(S: Surf, x: number, y: number): (Vector3, Vector3)
	local z, n = frontOf(S.list, x, y)
	return S.o + V(x, y, z), n
end

-- Пятно: эллипсоид size (X поперёк, Y вдоль, Z по нормали), центр на h от поверхности
local function sDecal(S: Surf, x: number, y: number, size: Vector3, h: number, color: Color3, roll: number?, opts: Sculpt.Opts?): Part
	local p, n = sPoint(S, x, y)
	return E(S.bone, frameOut(p + n * h, n, roll), size, color, opts)
end

-- Линия по поверхности от (x1,y1) до (x2,y2): ширина w, толщина d, центр на h от поверхности
local function sLine(S: Surf, x1: number, y1: number, x2: number, y2: number, w: number, d: number, h: number, color: Color3, opts: Sculpt.Opts?): Part
	local p1 = sPoint(S, x1, y1)
	local p2 = sPoint(S, x2, y2)
	local pm, n = sPoint(S, (x1 + x2) / 2, (y1 + y2) / 2)
	return E(S.bone, frameY(pm + n * h, p2 - p1, -n), V(w, (p2 - p1).Magnitude, d), color, opts)
end

local function ellParts(bone: string, o: Vector3, list: { Ell }, color: Color3)
	for _, e in list do
		E(bone, CFrame.new(o + e.c), e.r * 2, color)
	end
end

------------------------------------------------------------------------------------------
-- Мех: шипы (сужающиеся эллипсоиды) с тёмными кончиками и пряди-Beam
------------------------------------------------------------------------------------------

local function furSpike(bone: string, base: Vector3, dir: Vector3, len: number, w: number, color: Color3, dark: boolean, amp: number)
	local d = dir.Unit
	-- эллипсоид от a до b: центр чуть впереди корня, видимая часть сужается к кончику
	local back = len * 0.55
	local a = base - d * back
	local b = base + d * len
	local total = len + back
	local hingeY = -total / 2 + back -- корень шипа в осях детали (ось Y вдоль шипа)
	local fl = if amp > 0 then { amp = amp, freq = 2.3, hinge = V(0, hingeY, 0), axis = V(1, 0, 0) } else nil
	lock(bone, a, b, w, w * 0.8, d:Cross(V(0, 1, 0)) + V(0, 0, 0.001), color, { flutter = fl })
	if dark then
		-- крошечный тёмный кончик (у четверти шипов)
		local ta = base + d * (len * 0.8)
		local tb = base + d * (len * 1.02)
		local tfl = if amp > 0 then { amp = amp, freq = 2.3, hinge = V(0, -(len * 0.91), 0), axis = V(1, 0, 0) } else nil
		lock(bone, ta, tb, 0.05, 0.05, d:Cross(V(0, 1, 0)) + V(0, 0, 0.001), C.furTip, { flutter = tfl })
	end
end

local function furStrand(bone: string, root: Vector3, dir: Vector3, len: number, w: number, bend: Vector3, seed: number)
	local d = dir.Unit
	local p2 = root + d * (len * 0.5) + bend * (len * 0.12)
	local p3 = root + d * len + bend * (len * 0.35)
	Strand(bone, { root, p2, p3 }, {
		widths = { w, w * 0.7, w * 0.36 },
		color0 = C.fur,
		color1 = C.furShade,
		outline = FUR_LINE,
		-- Sculpt добавляет к контуру +0.08: при масштабе 0.6 у корня контур почти скрыт, к кончику — тонкая тёмная кайма
		outlineScale = 0.6,
		stiffness = 0.55,
		lightInfluence = 0.35,
		seed = seed,
		segments = 8,
	})
end

------------------------------------------------------------------------------------------
-- ГОЛОВА И ЛИЦО (кость Head). Координаты — от кости головы (основание черепа).
------------------------------------------------------------------------------------------

local function faceSurf(): Surf
	return {
		bone = "Head",
		o = bp("Head"),
		list = {
			{ c = V(0, 0.47, -0.04), r = V(0.31, 0.33, 0.37) }, -- лоб и глаза
			{ c = V(0, 0.15, -0.08), r = V(0.27, 0.3, 0.33) }, -- нижняя часть лица (длинная)
			{ c = V(0, -0.05, -0.245), r = V(0.125, 0.12, 0.14) }, -- подбородок
			{ c = V(0, 0.478, -0.31), r = V(0.26, 0.065, 0.1) }, -- надбровье
			{ c = V(0.18, 0.335, -0.2), r = V(0.11, 0.08, 0.1) }, -- скулы
			{ c = V(-0.18, 0.335, -0.2), r = V(0.11, 0.08, 0.1) },
		},
	}
end

local function buildHead()
	local H = bp("Head")
	local S = faceSurf()
	E("Head", at(H + V(0, 0.47, 0.06)), V(0.7, 0.84, 0.88), C.skin) -- череп
	ellParts("Head", H, S.list, C.skin)
	for _, s in { 1, -1 } do
		-- углы тяжёлой квадратной челюсти + линия нижней челюсти
		E("Head", atS(H + V(0.19, 0.05, 0.02), s), V(0.15, 0.3, 0.3), C.skin)
		Seg("Head", H + mx(V(0.215, 0.06, 0.07), s), H + mx(V(0.085, -0.13, -0.23), s), 0.1, 0.11, C.skin)
		-- уши
		E("Head", atS(H + V(0.335, 0.35, 0.05), s, 0, -14, 4), V(0.075, 0.235, 0.15), C.skin)
		E("Head", atS(H + V(0.353, 0.345, 0.045), s, 0, -14, 4), V(0.05, 0.15, 0.095), C.skinShade)
	end

	-- НОС: длинная прямая спинка, кончик, крылья, ноздри (видны снизу), тень сбоку
	Seg("Head", H + V(0, 0.45, -0.395), H + V(0, 0.235, -0.455), 0.058, 0.07, C.skin)
	E("Head", at(H + V(0, 0.215, -0.442)), V(0.08, 0.066, 0.08), C.skin)
	for _, s in { 1, -1 } do
		E("Head", atS(H + V(0.04, 0.2, -0.41), s, 0, -20, 0), V(0.054, 0.05, 0.064), C.skin)
		E("Head", atS(H + V(0.023, 0.188, -0.422), s), V(0.05, 0.05, 0.05), C.skinLine)
	end
	sLine(S, -0.04, 0.41, -0.05, 0.26, 0.05, 0.05, -0.021, C.skinShade)

	-- ГЛАЗА: узкий миндаль, тяжёлая линия ресниц, светлая серо-голубая радужка, маленький зрачок
	for _, s in { 1, -1 } do
		sDecal(S, 0.128 * s, 0.405, V(0.15, 0.06, 0.04), 0.002, C.sclera, 7 * s)
		sDecal(S, 0.121 * s, 0.405, V(0.062, 0.062, 0.03), 0.012, C.iris)
		sDecal(S, 0.121 * s, 0.406, V(0.05, 0.05, 0.05), 0.006, C.pupil)
		-- верхнее веко: две дуги + «хвостик» у внешнего угла
		sLine(S, 0.055 * s, 0.4, 0.125 * s, 0.43, 0.05, 0.05, 0.0, C.lash)
		sLine(S, 0.12 * s, 0.43, 0.205 * s, 0.419, 0.05, 0.05, -0.002, C.lash)
		sLine(S, 0.198 * s, 0.42, 0.232 * s, 0.404, 0.05, 0.05, -0.01, C.lash)
		-- нижнее веко и складка над веком
		sLine(S, 0.08 * s, 0.383, 0.19 * s, 0.391, 0.05, 0.05, -0.022, C.skinLine)
		sLine(S, 0.075 * s, 0.452, 0.2 * s, 0.449, 0.05, 0.05, -0.022, C.skinShade)
		-- брови: тонкие тёмные, лёгкий излом
		sLine(S, 0.035 * s, 0.488, 0.13 * s, 0.5, 0.05, 0.05, -0.014, C.brow)
		sLine(S, 0.125 * s, 0.5, 0.25 * s, 0.477, 0.05, 0.05, -0.016, C.brow)
		-- скуловая тень от скулы к уголку рта
		sLine(S, 0.225 * s, 0.29, 0.18 * s, 0.13, 0.05, 0.05, -0.022, C.skinShade)
		-- носогубная складка (короткая, от крыла носа)
		sLine(S, 0.075 * s, 0.195, 0.14 * s, 0.11, 0.05, 0.05, -0.022, C.skinShade)
	end
	-- морщинки между бровей
	sLine(S, 0.02, 0.475, 0.026, 0.53, 0.05, 0.05, -0.022, C.skinShade)
	sLine(S, -0.02, 0.475, -0.026, 0.53, 0.05, 0.05, -0.022, C.skinShade)

	-- РОТ: широкий оскал с верхними зубами, уголки вверх
	local my = 0.075
	sLine(S, -0.14, my, 0.14, my, 0.07, 0.05, -0.013, C.mouthIn)
	for _, s in { 1, -1 } do
		sLine(S, 0.1 * s, my - 0.006, 0.165 * s, my + 0.022, 0.05, 0.05, -0.012, C.mouthIn)
	end
	sLine(S, -0.115, my + 0.006, 0.115, my + 0.006, 0.05, 0.05, -0.008, C.teeth)
	for _, s in { 1, -1 } do
		sLine(S, 0.085 * s, my + 0.002, 0.14 * s, my + 0.016, 0.05, 0.05, -0.012, C.teeth)
	end
	sLine(S, -0.075, my - 0.024, 0.075, my - 0.024, 0.05, 0.05, -0.018, Sculpt.mix(C.teeth, C.mouthIn, 0.25))
	-- тень под нижней губой, ямочки уголков
	sLine(S, -0.065, my - 0.06, 0.065, my - 0.06, 0.05, 0.05, -0.021, C.skinShade)
	for _, s in { 1, -1 } do
		sLine(S, 0.16 * s, my + 0.02, 0.18 * s, my + 0.045, 0.05, 0.05, -0.018, C.skinLine)
	end
	-- штрихи щетины/ссадин: правая челюсть и левая щека
	for i = 0, 1 do
		sLine(S, 0.16 + i * 0.025, 0.0 + i * 0.012, 0.172 + i * 0.025, -0.04 + i * 0.012, 0.05, 0.05, -0.022, C.stubble)
		sLine(S, -0.17 - i * 0.022, 0.24 - i * 0.012, -0.182 - i * 0.022, 0.205 - i * 0.012, 0.05, 0.05, -0.022, C.stubble)
	end
	sLine(S, 0, -0.04, 0, -0.1, 0.05, 0.05, -0.022, C.skinShade) -- ямка подбородка
end

------------------------------------------------------------------------------------------
-- ШЕЯ (кость Neck): колонна, жилы, кадык
------------------------------------------------------------------------------------------

local function buildNeck()
	local N = bp("Neck")
	local H = bp("Head")
	E("Neck", at(N + V(0, 0.22, 0.04)), V(0.42, 0.74, 0.42), C.skinMid)
	E("Neck", at(N + V(0, 0.25, -0.06)), V(0.32, 0.12, 0.26), C.skinShade) -- тень под челюстью
	for _, s in { 1, -1 } do
		Seg("Neck", H + mx(V(0.155, 0.1, 0.06), s), N + mx(V(0.045, -0.1, -0.2), s), 0.085, 0.075, C.skin)
		Seg("Neck", H + mx(V(0.11, -0.03, -0.05), s), N + mx(V(0.1, 0.0, -0.16), s), 0.05, 0.05, C.skinShade)
	end
	E("Neck", at(N + V(0, 0.2, -0.185)), V(0.07, 0.1, 0.07), C.skin) -- кадык
	E("Neck", at(N + V(0, -0.04, -0.2)), V(0.08, 0.06, 0.05), C.skinShade) -- яремная ямка
end

------------------------------------------------------------------------------------------
-- ВОЛОСЫ: зализанные бока и затылок (Head) + помпадур-«пушка» (кость Pompadour)
------------------------------------------------------------------------------------------

local function buildHair()
	local H = bp("Head")
	E("Head", at(H + V(0, 0.54, 0.15)), V(0.77, 0.8, 0.82), C.hair) -- шапка (отодвинута назад: лоб и уши открыты)
	E("Head", at(H + V(0, 0.36, 0.29), 8, 0, 0), V(0.64, 0.6, 0.36), C.hair) -- затылок до шеи
	-- «утиный хвост» на затылке
	lock("Head", H + V(0, 0.24, 0.38), H + V(0, 0.08, 0.52), 0.16, 0.08, V(0, 0, 1), C.hair)
	for _, s in { 1, -1 } do
		lock("Head", H + mx(V(0.07, 0.22, 0.37), s), H + mx(V(0.12, 0.08, 0.5), s), 0.12, 0.07, V(0, 0, 1), C.hair)
		-- виски и бакенбарды, зализанные назад
		E("Head", atS(H + V(0.3, 0.58, -0.04), s, 0, -18, 0), V(0.15, 0.32, 0.42), C.hair)
		E("Head", atS(H + V(0.33, 0.41, -0.02), s, 0, -14, 0), V(0.07, 0.2, 0.1), C.hair)
		-- бороздка и блик зачёса на боку
		lock("Head", H + mx(V(0.34, 0.63, -0.16), s), H + mx(V(0.35, 0.52, 0.3), s), 0.05, 0.05, V(s, 0, 0), C.hairShadow)
		lock("Head", H + mx(V(0.36, 0.5, -0.04), s), H + mx(V(0.33, 0.37, 0.33), s), 0.05, 0.05, V(s, 0, 0), C.hairSheen)
	end

	-- ПОМПАДУР: корпус у макушки, «ствол» со вздутием, перехват, круглый торец с тёмным «дулом»
	local P = "Pompadour"
	E(P, at(H + V(0, 0.76, 0.12), -4, 0, 0), V(0.75, 0.34, 0.68), C.hair)
	E(P, at(H + V(0, 0.79, -0.3), 10, 0, 0), V(0.6, 0.38, 0.8), C.hair)
	E(P, at(H + V(0, 0.83, -0.58), 12, 0, 0), V(0.47, 0.34, 0.4), C.hair)
	E(P, at(H + V(0, 0.85, -0.74), 12, 0, 0), V(0.45, 0.32, 0.32), C.hair)
	E(P, at(H + V(0, 0.72, -0.6), 12, 0, 0), V(0.36, 0.12, 0.3), C.hairShadow) -- нижняя сторона валика
	-- «дуло»: тёмный приплюснутый диск с ободком на торце
	E(P, at(H + V(0, 0.892, -0.872), 18, 0, 0), V(0.18, 0.1, 0.05), C.muzzle)
	-- два плоских «зачёса» сверху, сходящихся к шву
	for _, s in { 1, -1 } do
		lock(P, H + mx(V(0.1, 0.985, -0.64), s), H + mx(V(0.17, 0.915, 0.14), s), 0.24, 0.1, V(0.25 * s, 1, 0), C.hair)
		-- блики вдоль верхнего бока
		lock(P, H + mx(V(0.17, 0.99, -0.55), s), H + mx(V(0.24, 0.94, -0.05), s), 0.05, 0.05, V(0.5 * s, 1, 0), C.hairSheen)
		lock(P, H + mx(V(0.235, 0.89, -0.66), s), H + mx(V(0.3, 0.85, -0.25), s), 0.05, 0.05, V(s, 0.6, 0), C.hairSheen)
	end
	-- шов по центру (ломаная) с 4 зазубринами «ёлочкой»
	local seam = {
		H + V(0.0, 0.98, 0.04),
		H + V(0.006, 1.0, -0.1),
		H + V(-0.005, 1.016, -0.24),
		H + V(0.005, 1.03, -0.38),
		H + V(0.0, 1.035, -0.5),
	}
	for i = 1, #seam - 1 do
		lock(P, seam[i], seam[i + 1], 0.05, 0.05, V(0, 1, 0), C.crease)
	end
	local barbs = { { 2, 1 }, { 3, -1 }, { 4, 1 }, { 4, -1 } }
	for _, bb in barbs do
		local p = seam[bb[1]]
		local s = bb[2]
		lock(P, p, p + V(0.055 * s, -0.012, 0.05), 0.05, 0.05, V(0, 1, 0), C.crease)
	end
	-- невидимый якорь энергии у «дула» (-Z вперёд)
	B(P, at(H + V(0, 0.883, -0.92)), V(0.3, 0.3, 0.3), C.muzzle, { transparency = 1, name = "EnergyAnchor", castShadow = false })

	-- выбившиеся пряди: из-под валика на лоб и пара торчащих сзади
	local function hairStrand(pts: { Vector3 }, w: number, seed: number)
		Strand(P, pts, { widths = { w, w * 0.75, w * 0.5, 0.012 }, color0 = C.hair, color1 = C.hairSheen, stiffness = 0.35, seed = seed, lightInfluence = 0.4, segments = 10 })
	end
	hairStrand({ H + V(0.035, 0.74, -0.74), H + V(0.06, 0.66, -0.71), H + V(0.02, 0.58, -0.6), H + V(0.045, 0.5, -0.47) }, 0.032, 3.1)
	hairStrand({ H + V(-0.045, 0.74, -0.72), H + V(-0.075, 0.65, -0.68), H + V(-0.035, 0.57, -0.57), H + V(-0.06, 0.52, -0.46) }, 0.028, 4.7)
	hairStrand({ H + V(0.12, 0.97, -0.1), H + V(0.16, 1.07, -0.02), H + V(0.24, 1.1, 0.06), H + V(0.3, 1.06, 0.1) }, 0.03, 6.3)
	hairStrand({ H + V(-0.1, 0.96, 0.05), H + V(-0.14, 1.04, 0.15), H + V(-0.2, 1.05, 0.25), H + V(-0.25, 1.0, 0.3) }, 0.028, 7.7)
end

------------------------------------------------------------------------------------------
-- ТОРС: грудь, пресс, косые, талия (кожа)
------------------------------------------------------------------------------------------

-- Передняя поверхность торса в координатах модели
local function torsoSurf(bone: string): Surf
	local CH = bp("Chest")
	local SP = bp("Spine")
	return {
		bone = bone,
		o = V(0, 0, 0),
		list = {
			{ c = CH + V(0, 0.05, 0.04), r = V(0.62, 0.62, 0.42) }, -- грудная клетка
			{ c = CH + V(0, 0.4, 0.02), r = V(0.6, 0.26, 0.38) }, -- верх груди
			{ c = CH + V(0.24, 0.17, -0.26), r = V(0.24, 0.19, 0.13) }, -- грудные
			{ c = CH + V(-0.24, 0.17, -0.26), r = V(0.24, 0.19, 0.13) },
			{ c = SP + V(0, 0.05, 0.04), r = V(0.5, 0.58, 0.37) }, -- живот
			{ c = SP + V(0, 0.0, -0.25), r = V(0.24, 0.52, 0.09) }, -- прямая мышца
		},
	}
end

local function buildTorso()
	local CH = bp("Chest")
	local SP = bp("Spine")
	local HP = bp("Hips")
	local SC = torsoSurf("Chest")
	local SS = torsoSurf("Spine")

	E("Chest", at(CH + V(0, 0.05, 0.04)), V(1.24, 1.24, 0.84), C.skin)
	E("Chest", at(CH + V(0, 0.4, 0.02)), V(1.2, 0.52, 0.76), C.skin)
	for _, s in { 1, -1 } do
		-- грудная мышца + тёмный край под ней
		E("Chest", atS(CH + V(0.24, 0.135, -0.25), s, 0, 0, -6), V(0.48, 0.38, 0.26), C.skinShade)
		E("Chest", atS(CH + V(0.24, 0.17, -0.26), s, 0, 0, -6), V(0.48, 0.38, 0.26), C.skin)
		-- ключицы
		Seg("Chest", CH + mx(V(0.06, 0.52, -0.33), s), CH + mx(V(0.46, 0.6, -0.2), s), 0.065, 0.065, C.skin)
		sLine(SC, 0.08 * s, 0.47 + CH.Y, 0.4 * s, 0.53 + CH.Y, 0.05, 0.05, -0.02, C.skinShade)
		-- зубчатая мышца
		for i = 0, 2 do
			local y = -0.1 - i * 0.13
			Seg("Chest", CH + mx(V(0.55, y + 0.04, -0.14), s), CH + mx(V(0.42, y - 0.04, -0.27), s), 0.085, 0.07, C.skin)
		end
	end
	sLine(SC, 0, CH.Y + 0.36, 0, CH.Y - 0.04, 0.05, 0.05, -0.019, C.skinShade) -- борозда грудины

	-- ЖИВОТ
	E("Spine", at(SP + V(0, 0.05, 0.04)), V(1.0, 1.16, 0.74), C.skin)
	E("Spine", at(SP + V(0, 0.0, -0.25)), V(0.48, 1.04, 0.18), C.skinShade) -- подложка пресса
	-- кубики: 3 ряда по 2 выше пупка + нижняя пара под ремень
	local rows = { CH.Y - 0.26, SP.Y + 0.25, SP.Y + 0.02, SP.Y - 0.28 }
	local hs = { 0.21, 0.21, 0.21, 0.26 }
	for ri, y in rows do
		local S = if ri == 1 then SC else SS
		for _, s in { 1, -1 } do
			sDecal(S, 0.108 * s, y, V(0.205, hs[ri], 0.09), 0.008, C.skin, 0)
		end
	end
	sDecal(SS, 0, SP.Y - 0.13, V(0.05, 0.06, 0.05), -0.012, C.skinLine) -- пупок
	for _, s in { 1, -1 } do
		E("Spine", atS(SP + V(0.37, -0.2, -0.06), s, 0, -25, -8), V(0.24, 0.64, 0.36), C.skin) -- косые
		sLine(SS, 0.27 * s, SP.Y + 0.24, 0.255 * s, SP.Y - 0.36, 0.05, 0.05, -0.019, C.skinShade)
		Seg("Hips", HP + mx(V(0.33, 0.46, -0.22), s), HP + mx(V(0.12, 0.16, -0.33), s), 0.06, 0.06, C.skinShade) -- пояс Аполлона
	end
	E("Hips", at(HP + V(0, 0.36, 0.03)), V(0.96, 0.6, 0.7), C.skin) -- талия над ремнём
end

------------------------------------------------------------------------------------------
-- ЖЕТОН НА ЦЕПОЧКЕ-ШАРИКАХ (Chest)
------------------------------------------------------------------------------------------

local function buildDogTag()
	local CH = bp("Chest")
	local S = torsoSurf("Chest")
	local tagY = CH.Y + 0.08
	for _, s in { 1, -1 } do
		local a = V(0.19 * s, CH.Y + 0.62, 0)
		local m = V(0.15 * s, CH.Y + 0.3, 0)
		local b = V(0.02 * s, tagY + 0.12, 0)
		local n = 10
		for i = 0, n do
			local t = i / n
			local p = a * (1 - t) ^ 2 + m * (2 * t * (1 - t)) + b * (t * t)
			local q, nn = sPoint(S, p.X, p.Y)
			Ball("Chest", q + nn * 0.012, 0.05, C.chain)
		end
	end
	local q, nn = sPoint(S, 0, tagY)
	local cf = frameOut(q + nn * 0.035, nn, -5)
	E("Chest", cf, V(0.125, 0.205, 0.05), C.tag)
	B("Chest", cf * CFrame.new(0, 0, -0.006), V(0.105, 0.175, 0.05), C.tag)
	B("Chest", cf * CFrame.new(0, 0, -0.011), V(0.075, 0.13, 0.05), Sculpt.mix(C.tag, Color3.new(1, 1, 1), 0.3))
	Ball("Chest", q + nn * 0.03 + V(0, 0.115, 0), 0.05, C.chain)
end

------------------------------------------------------------------------------------------
-- КУРТКА: короткая чёрная, распахнута, квадратные плечи
------------------------------------------------------------------------------------------

-- Кромка распаха (правая сторона, координаты от Chest): сверху (под мехом) до подола у пупка
local EDGE = {
	V(0.36, 0.64, -0.36),
	V(0.44, 0.1, -0.385),
	V(0.5, -0.35, -0.335),
	V(0.56, -0.98, -0.27),
}
local HEM_Y = -0.98

local function buildJacket()
	local CH = bp("Chest")
	local J = C.jacket
	E("Chest", at(CH + V(0, 0.2, 0.16)), V(1.64, 1.2, 1.0), J) -- спинка/бока вверху
	E("Chest", at(CH + V(0, -0.5, 0.18)), V(1.24, 0.9, 0.7), J) -- спина ниже
	-- «юбка» до пупка: кольцо панелей сзади и с боков (спереди распах)
	local a, b, zc = 0.66, 0.46, 0.08
	local y0, y1 = CH.Y + HEM_Y, CH.Y - 0.3
	local step = 24
	local phi = 60
	while phi < 300 - 1 do
		local p1 = V(a * math.sin(rad(phi)), 0, zc - b * math.cos(rad(phi)))
		local p2 = V(a * math.sin(rad(phi + step)), 0, zc - b * math.cos(rad(phi + step)))
		local mid = (p1 + p2) / 2
		local outN = V(mid.X / (a * a), 0, (mid.Z - zc) / (b * b)).Unit
		local cf = frameY(V(mid.X, (y0 + y1) / 2, mid.Z), V(0, 1, 0) + outN * 0.08, outN)
		B("Chest", cf, V((p2 - p1).Magnitude + 0.05, y1 - y0, 0.07), J)
		phi += step
	end
	for _, s in { 1, -1 } do
		-- полы: панели от кромки распаха к бокам
		for i = 1, #EDGE - 1 do
			local e1, e2 = CH + mx(EDGE[i], s), CH + mx(EDGE[i + 1], s)
			local o1 = CH + V(0.8 * s, EDGE[i].Y, 0.0)
			local o2 = CH + V((if i == #EDGE - 1 then 0.66 else 0.74) * s, EDGE[i + 1].Y, 0.0)
			local center = (e1 + e2 + o1 + o2) / 4
			local across = (o1 + o2) / 2 - (e1 + e2) / 2
			local down = (e2 + o2) / 2 - (e1 + o1) / 2
			local nrm = across:Cross(down).Unit
			if nrm.Z > 0 then
				nrm = -nrm
			end
			local cf = frameY(center + nrm * 0.0, -down, -nrm)
			B("Chest", cf, V(across.Magnitude + 0.12, down.Magnitude + 0.06, 0.08), J)
			-- жёсткая кромка и молния-кант
			local dir = e2 - e1
			local inward = V(-s, 0, 0)
			local fcf = frameY((e1 + e2) / 2 - nrm * 0.0 - inward * 0.035, dir, -nrm)
			B("Chest", fcf, V(0.1, dir.Magnitude + 0.04, 0.09), J)
			local zcf = frameY((e1 + e2) / 2 + inward * 0.01 - nrm * 0.02, dir, -nrm)
			B("Chest", zcf, V(0.05, dir.Magnitude + 0.02, 0.05), C.zipper)
		end
		-- кокетка плеча (квадратное плечо) на ключице + блик
		local cl = "Clavicle" .. (if s > 0 then "R" else "L")
		local CL = bp(cl)
		E(cl, at(CL + V(0.5 * s, 0.13, 0.08)), V(1.02, 0.34, 0.86), J)
		lock(cl, CL + V(0.3 * s, 0.29, -0.1), CL + V(0.85 * s, 0.25, -0.05), 0.07, 0.05, V(0, 1, 0), C.jacketSheen)
	end
end

------------------------------------------------------------------------------------------
-- МЕХОВОЙ ВОРОТНИК (Chest): огромная белая шаль — до ушей за шеей, по плечам и вниз по лацканам
------------------------------------------------------------------------------------------

type FurNode = { p: Vector3, n: Vector3, s: Vector3 }

local function buildCollar()
	local CH = bp("Chest")
	local rng = MathX.rng(1771)
	local nodes: { FurNode } = {
		{ p = V(0.0, 1.04, 0.38), n = V(0, 0.6, 1), s = V(0.52, 0.7, 0.36) },
		{ p = V(0.32, 1.0, 0.3), n = V(0.6, 0.55, 0.7), s = V(0.48, 0.66, 0.4) },
		{ p = V(0.56, 0.9, 0.06), n = V(1, 0.45, 0.2), s = V(0.5, 0.56, 0.46) },
		{ p = V(0.52, 0.78, -0.22), n = V(0.9, 0.35, -0.5), s = V(0.44, 0.5, 0.4) },
		{ p = V(0.38, 0.57, -0.38), n = V(0.6, 0.1, -0.85), s = V(0.34, 0.4, 0.26) },
		{ p = V(0.36, 0.35, -0.43), n = V(0.5, -0.1, -0.86), s = V(0.28, 0.32, 0.2) },
		{ p = V(0.39, 0.15, -0.44), n = V(0.4, -0.4, -0.85), s = V(0.22, 0.26, 0.16) },
	}
	local nStrand = 0
	for _, s in { 1, -1 } do
		for ni, node in nodes do
			if not (s < 0 and ni == 1) then
				local p = CH + mx(node.p, s)
				local n = mx(node.n, s).Unit
				-- ядро: белый сгусток, сиреневая тень снизу
				E("Chest", frameOut(p - V(0, node.s.Y * 0.16, 0) - n * 0.03, n, 0), node.s * V(0.95, 0.75, 0.9), C.furShadow)
				E("Chest", frameOut(p + n * 0.03 + V(0, node.s.Y * 0.06, 0), n, 0), node.s, C.fur)
				local up = V(0, 1, 0)
				local side = n:Cross(up)
				if side.Magnitude < 1e-3 then
					side = V(1, 0, 0)
				end
				side = side.Unit
				local count = if ni <= 4 then 11 else 6
				for _ = 1, count do
					local u = rng:range(-1, 1)
					local v = rng:range(-1, 1)
					local base = p + n * (node.s.Z * 0.32) + side * (u * node.s.X * 0.42) + up * (v * node.s.Y * 0.38)
					local dir = n + side * (u * 0.7 + rng:range(-0.25, 0.25)) + up * (v * 0.8 + rng:range(-0.1, 0.35))
					if ni <= 3 then
						dir += up * 0.4 -- стоячая часть тянется вверх
					end
					local len = rng:range(0.2, 0.34) * (if ni >= 6 then 0.7 else 1)
					local w = rng:range(0.075, 0.11)
					local col = if rng:next() < 0.3 then C.furShade else C.fur
					furSpike("Chest", base, dir, len, w, col, rng:next() < 0.25, 5)
				end
				if ni <= 5 then
					for k = 1, 2 do
						local u = (k - 1.5) * 1.1
						local root = p + n * (node.s.Z * 0.22) + side * (u * node.s.X * 0.3) + V(0, node.s.Y * 0.12, 0)
						local dir = n + V(0, if ni <= 3 then 0.6 else 0.1, 0) + side * (u * 0.4)
						nStrand += 1
						furStrand("Chest", root, dir, rng:range(0.26, 0.36), 0.2, V(0, -0.2, 0) + side * (u * 0.3), 20 + nStrand)
					end
				end
			end
		end
		-- сгустки между узлами (сплошная полоса)
		for ni = 1, #nodes - 1 do
			local n1, n2 = nodes[ni], nodes[ni + 1]
			local p = CH + mx((n1.p + n2.p) / 2, s)
			local n = mx(n1.n + n2.n, s).Unit
			E("Chest", frameOut(p + n * 0.03, n, 0), (n1.s + n2.s) / 2 * V(0.9, 0.85, 0.9), if ni % 2 == 0 then C.furShade else C.fur)
		end
	end
end

------------------------------------------------------------------------------------------
-- РУКИ: рукава, меховые манжеты, кисти (ладонь, костяшки, 3 фаланги, ногти)
------------------------------------------------------------------------------------------

local FINGERS = { "Index", "Middle", "Ring", "Pinky" }
local FSCALE: { [string]: number } = { Index = 0.92, Middle = 1.0, Ring = 0.95, Pinky = 0.78 }
local FWIDTH: { [string]: number } = { Index = 0.098, Middle = 0.1, Ring = 0.094, Pinky = 0.082 }

local function buildArm(side: string, s: number)
	local UA, LA, HA = "UpperArm" .. side, "LowerArm" .. side, "Hand" .. side
	local U, L, Hd = bp(UA), bp(LA), bp(HA)
	local J = C.jacket
	local rng = MathX.rng(if s > 0 then 4242 else 2424)

	-- рукав: квадратное плечо (плоский «погон»), ровная труба плеча, локоть
	E(UA, at(U + V(0.07 * s, 0.02, 0.02), 0, 0, -6 * s), V(0.62, 0.4, 0.62), J)
	E(UA, at(U + V(0.03 * s, -0.16, 0.02)), V(0.56, 0.42, 0.58), J)
	Seg(UA, U + V(0.015 * s, -0.25, 0.015), U + V(0, -1.15, 0.025), 0.5, 0.52, J, nil, 0, 1.3)
	E(UA, at(U + V(0, -1.18, 0.03)), V(0.44, 0.36, 0.46), J)
	lock(UA, U + V(0.22 * s, -0.25, -0.12), U + V(0.19 * s, -0.95, -0.13), 0.06, 0.05, V(s, 0, -1), C.jacketSheen)
	lock(UA, U + V(0.0, -0.98, -0.23), U + V(0.18 * s, -1.05, -0.16), 0.05, 0.05, V(0, 0, -1), C.jacketHi)

	-- предплечье: слегка объёмный рукав
	E(LA, at(L + V(0, -0.02, 0.03)), V(0.44, 0.36, 0.46), J)
	Seg(LA, L + V(0, -0.1, 0.015), L + V(0, -0.74, 0), 0.5, 0.51, J, nil, 0, 1.3)
	lock(LA, L + V(0.21 * s, -0.12, -0.1), L + V(0.22 * s, -0.62, -0.1), 0.06, 0.05, V(s, 0, -1), C.jacketSheen)
	lock(LA, L + V(-0.05 * s, -0.4, -0.24), L + V(0.17 * s, -0.48, -0.19), 0.05, 0.05, V(0, 0, -1), C.jacketHi)

	-- МЕХОВАЯ МАНЖЕТА: кольцо сгустков + шипы наружу и к кисти
	local cy = L.Y - 0.88
	local cc = V(L.X, cy, L.Z)
	E(LA, at(cc), V(0.5, 0.34, 0.5), C.furShade)
	for k = 0, 8 do
		local th = rad(k * 40 + 10)
		local r = V(math.sin(th), 0, math.cos(th))
		local col = if k % 3 == 0 then C.furShade else C.fur
		E(LA, frameOut(cc + r * 0.2 + V(0, rng:range(-0.03, 0.03), 0), r, 0), V(0.25, 0.4, 0.22), col)
		E(LA, frameOut(cc + V(0, -0.12, 0) + r * 0.16, r, 0), V(0.22, 0.2, 0.2), C.furShadow)
	end
	for k = 1, 30 do
		local th = rad(rng:range(0, 360))
		local r = V(math.sin(th), 0, math.cos(th))
		local yy = rng:range(-0.17, 0.15)
		local base = cc + V(0, yy, 0) + r * 0.27
		local dir = r + V(0, rng:range(-0.55, 0.35) - (if yy < -0.08 then 0.4 else 0), 0)
		furSpike(LA, base, dir, rng:range(0.13, 0.24), rng:range(0.07, 0.1), if k % 4 == 0 then C.furShade else C.fur, rng:next() < 0.25, 6)
	end
	for k = 0, 3 do
		local th = rad(k * 90 + 45)
		local r = V(math.sin(th), 0, math.cos(th))
		furStrand(LA, cc + r * 0.28, r + V(0, -0.3, 0), 0.28, 0.18, V(0, -0.4, 0), 60 + k + (if s > 0 then 0 else 10))
	end

	-- КИСТЬ (для правой: ладонь -X, тыльная сторона +X; указательный спереди, -Z)
	E(HA, at(Hd + V(0, -0.01, 0)), V(0.17, 0.15, 0.27), C.skin) -- запястье
	E(HA, at(Hd + V(-0.005 * s, -0.22, 0)), V(0.15, 0.44, 0.42), C.skin) -- ладонь
	E(HA, at(Hd + V(0.03 * s, -0.27, 0.0)), V(0.1, 0.34, 0.41), C.skin) -- тыл
	E(HA, at(Hd + V(-0.04 * s, -0.17, -0.12)), V(0.13, 0.25, 0.15), C.skin) -- тенар
	E(HA, at(Hd + V(-0.035 * s, -0.25, 0.14)), V(0.11, 0.3, 0.12), C.skin) -- гипотенар
	for _, f in FINGERS do
		local b1, b2, b3 = f .. "1" .. side, f .. "2" .. side, f .. "3" .. side
		local K, K2, K3 = bp(b1), bp(b2), bp(b3)
		local w = FWIDTH[f]
		local L3 = 0.125 * FSCALE[f]
		-- костяшка и сухожилие на тыльной стороне
		E(HA, at(K + V(0.04 * s, 0.025, 0)), V(0.08, 0.09, 0.1), C.skin)
		lock(HA, Hd + V(0.055 * s, -0.08, (K.Z - Hd.Z) * 0.35), K + V(0.05 * s, 0.07, 0), 0.05, 0.05, V(s, 0, 0), C.skinShade)
		-- фаланги с шарнирами-шарами
		Seg(b1, K + V(0, 0.03, 0), K2, w, w * 0.92, C.skin, nil, 0, 1.08)
		Ball(b2, K2, w * 0.95, C.skin)
		Seg(b2, K2, K3, w * 0.93, w * 0.86, C.skin, nil, 0, 1.06)
		Ball(b3, K3, w * 0.88, C.skin)
		Seg(b3, K3, K3 - V(0, L3, 0), w * 0.86, w * 0.8, C.skin)
		-- ноготь и складка сустава на тыльной стороне
		E(b3, at(K3 + V(w * 0.3 * s, -L3 * 0.66, 0)), V(0.05, L3 * 0.52, w * 0.66), C.nail)
		E(b2, at(K2 + V(w * 0.3 * s, 0.0, 0)), V(0.05, 0.05, w * 0.7), C.skinShade)
	end
	-- большой палец
	local t1, t2, t3 = "Thumb1" .. side, "Thumb2" .. side, "Thumb3" .. side
	local T1, T2, T3 = bp(t1), bp(t2), bp(t3)
	Seg(t1, T1 + V(0, 0.05, 0.02), T2, 0.13, 0.12, C.skin, nil, 0, 1.05)
	Ball(t2, T2, 0.11, C.skin)
	Seg(t2, T2, T3, 0.105, 0.1, C.skin, nil, 0, 1.05)
	Ball(t3, T3, 0.098, C.skin)
	Seg(t3, T3, T3 - V(0, 0.12, 0), 0.095, 0.09, C.skin)
	E(t3, atS(T3 + V(0.022, -0.078, -0.03), s, 0, -40, 0), V(0.062, 0.06, 0.05), C.nail)
end

------------------------------------------------------------------------------------------
-- РЕМЕНЬ, БРЮКИ, ОБУВЬ
------------------------------------------------------------------------------------------

local function buildBelt()
	local HP = bp("Hips")
	local y = HP.Y + 0.15
	local a, b, zc = 0.57, 0.41, 0.03
	local n = 16
	for i = 0, n - 1 do
		local t1 = rad(i * 360 / n)
		local t2 = rad((i + 1) * 360 / n)
		local p1 = V(a * math.sin(t1), 0, zc - b * math.cos(t1))
		local p2 = V(a * math.sin(t2), 0, zc - b * math.cos(t2))
		local mid = (p1 + p2) / 2
		local outN = V(mid.X / (a * a), 0, (mid.Z - zc) / (b * b)).Unit
		B("Hips", frameY(V(mid.X, y, mid.Z), V(0, 1, 0), outN), V((p2 - p1).Magnitude + 0.02, 0.12, 0.06), C.belt)
	end
	for _, ang in { 35, -35, 75, -75, 140, -140 } do -- шлёвки
		local t = rad(ang)
		local p = V(a * math.sin(t), y, zc - b * math.cos(t))
		local outN = V(p.X / (a * a), 0, (p.Z - zc) / (b * b)).Unit
		B("Hips", frameY(p + outN * 0.03, V(0, 1, 0), outN), V(0.05, 0.17, 0.05), C.pants)
	end
	-- пряжка: прямоугольная пластина со скруглёнными углами и золотой четырёхконечной звездой
	local bc = at(V(0, y, zc - b - 0.03))
	B("Hips", bc, V(0.31, 0.17, 0.05), C.buckle)
	B("Hips", bc, V(0.35, 0.13, 0.05), C.buckle)
	for _, sx in { 1, -1 } do
		for _, sy in { 1, -1 } do
			Cyl("Hips", bc * CFrame.new(0.155 * sx, 0.065 * sy, 0) * rot(0, 90, 0), V(0.05, 0.04, 0.04), C.buckle)
		end
	end
	B("Hips", bc * CFrame.new(0, 0, -0.012), V(0.28, 0.12, 0.05), C.buckleHi)
	E("Hips", bc * CFrame.new(0, 0, -0.03), V(0.2, 0.05, 0.05), C.star)
	E("Hips", bc * CFrame.new(0, 0, -0.03), V(0.05, 0.15, 0.05), C.star)
	E("Hips", bc * CFrame.new(0, 0, -0.036) * rot(0, 0, 45), V(0.06, 0.06, 0.05), Sculpt.mix(C.star, Color3.new(1, 1, 1), 0.2))
end

local function buildLegs()
	local HP = bp("Hips")
	local Pn = C.pants
	E("Hips", at(HP + V(0, -0.04, 0.03)), V(1.12, 0.64, 0.8), Pn) -- таз
	E("Hips", at(HP + V(0, -0.3, -0.01)), V(0.48, 0.34, 0.52), Pn)
	for _, s in { 1, -1 } do
		E("Hips", atS(HP + V(0.22, -0.16, 0.2), s), V(0.5, 0.52, 0.42), Pn)
		Seg("Hips", HP + mx(V(0.3, 0.07, -0.35), s), HP + mx(V(0.46, -0.17, -0.21), s), 0.05, 0.05, C.pantsSeam) -- карман
	end
	Seg("Hips", HP + V(0.02, 0.06, -0.4), HP + V(0.03, -0.3, -0.31), 0.05, 0.05, C.pantsSeam) -- гульфик

	for _, side in { "L", "R" } do
		local s = if side == "R" then 1 else -1
		local UL, LL, FT, TO = "UpperLeg" .. side, "LowerLeg" .. side, "Foot" .. side, "Toe" .. side
		local U, L, F, T = bp(UL), bp(LL), bp(FT), bp(TO)
		Seg(UL, U + V(0, 0.0, 0.01), U + V(0, -0.85, -0.01), 0.57, 0.59, Pn, nil, 0, 1.3)
		Seg(UL, U + V(0, -0.75, 0), U + V(0, -1.5, -0.01), 0.46, 0.48, Pn, nil, 0, 1.3)
		Seg(UL, U + V(0.05 * s, -0.25, -0.285), U + V(0.02 * s, -1.4, -0.225), 0.05, 0.05, C.pantsSeam)
		E(LL, at(L + V(0, 0.0, -0.01)), V(0.42, 0.38, 0.44), Pn)
		Seg(LL, L + V(0, -0.1, 0), L + V(0, -1.25, 0.0), 0.41, 0.43, Pn, nil, 0, 1.2)
		E(LL, at(L + V(0, -0.45, 0.05)), V(0.4, 0.72, 0.44), Pn)
		E(LL, at(L + V(0, -1.32, 0.0)), V(0.46, 0.24, 0.5), Pn) -- низ штанины
		-- ботинок
		E(FT, at(F + V(0, -0.03, 0.02)), V(0.37, 0.3, 0.41), C.shoe)
		E(FT, at(F + V(0, -0.1, -0.24)), V(0.39, 0.22, 0.8), C.shoe)
		B(FT, at(F + V(0, -0.165, 0.1)), V(0.33, 0.1, 0.24), C.shoe)
		B(FT, at(F + V(0, -0.2, -0.22)), V(0.39, 0.05, 0.78), C.sole, { name = "Sole" .. side })
		E(TO, at(T + V(0, 0.035, -0.1)), V(0.38, 0.18, 0.42), C.shoe)
		B(TO, at(T + V(0, -0.03, -0.1)), V(0.37, 0.05, 0.36), C.sole)
	end
end

------------------------------------------------------------------------------------------
-- МЕХ ПО НИЗУ КУРТКИ (пучки у бёдер)
------------------------------------------------------------------------------------------

local function buildHemFur()
	local CH = bp("Chest")
	local rng = MathX.rng(909)
	local y = CH.Y + HEM_Y
	for _, s in { 1, -1 } do
		-- от угла полы по боку назад
		local pts = {
			CH + V(0.6 * s, HEM_Y, -0.26),
			CH + V(0.68 * s, HEM_Y, -0.1),
			CH + V(0.72 * s, HEM_Y, 0.08),
			CH + V(0.66 * s, HEM_Y, 0.26),
		}
		for k, p in pts do
			local n = V(p.X - 0.0, 0, p.Z - (CH.Z + 0.08)).Unit
			E("Chest", frameOut(p + V(0, 0.02, 0), n, 0), V(0.26, 0.16, 0.18), if k % 2 == 0 then C.furShade else C.fur)
			for _ = 1, 3 do
				local dir = n * 0.7 + V(0, -1, 0) + n:Cross(V(0, 1, 0)) * rng:range(-0.5, 0.5)
				furSpike("Chest", p + n * 0.04 + V(0, -0.03, 0), dir, rng:range(0.1, 0.17), rng:range(0.065, 0.09), C.fur, rng:next() < 0.25, 6)
			end
		end
		furStrand("Chest", V(0.62 * s, y, -0.2), V(0.4 * s, -1, -0.3), 0.22, 0.17, V(0.3 * s, 0, 0), 90 + s)
	end
end

------------------------------------------------------------------------------------------

function Ryu.build(origin: CFrame): Model
	def = Skeletons.Ryu
	ctx = Sculpt.newCharacter("Ryu", def, origin)
	buildHead()
	buildNeck()
	buildHair()
	buildTorso()
	buildDogTag()
	buildJacket()
	buildCollar()
	buildArm("R", 1)
	buildArm("L", -1)
	buildBelt()
	buildLegs()
	buildHemFur()
	Sculpt.outline(ctx, Color3.fromRGB(20, 18, 26))
	ctx.model:SetAttribute("PartCount", ctx.count)
	ctx.model:SetAttribute("StrandCount", ctx.strandCount)
	return ctx.model
end

return Ryu
