--!strict
-- Рика — полностью проявленное проклятие (аниме JJK, 3 сезон, «Колония Сендай»).
-- Маска-«луковица» (узким концом вниз) с 5 тёмными полосами и одним глазом-щелью, оскал из 7+7 тупых
-- зубов, белая грива языками пламени, огромный V-образный торс, длинные руки с короткими чёрными когтями,
-- ниже пояса — чёрная дымная масса, переходящая в хвост на земле.
--
-- Всё ниже задаётся в осях МОДЕЛИ в позе покоя (X — вправо от персонажа, Y — вверх, -Z — вперёд);
-- в позе покоя оси всех костей совпадают с осями модели, поэтому в оси кости переводим простым сдвигом.
-- Детали туловища задаём смещениями от «своей» кости, голову — от верхней точки маски T.

local Sculpt = require(script.Parent.Sculpt)
local Skeletons = require(script.Parent.Parent.Skeletons)
local Rig = require(script.Parent.Parent.Rig)
local MathX = require(script.Parent.Parent.Math)

local Rika = {}

local V = Vector3.new
local hex = Sculpt.hex

-- Палитра (базовые аниме-цвета; туман сцены сам сделает их «как в клипе»)
local COL = {
	skinLit = hex("#ECECEA"), -- фарфоровый свет
	skin = hex("#D3D1DE"), -- основной тон кожи
	skinMid = hex("#A7A4BF"), -- полутень (внутренняя сторона рук, под грудью)
	skinShade = hex("#6E6A88"), -- тень, линии мышц
	skinCore = hex("#2E2B3C"), -- глубокая тень (горло)
	mask = hex("#F1F0F2"),
	stripe = hex("#3D4157"),
	sclera = hex("#C7CCD2"),
	irisRing = hex("#6E1A1A"),
	eye = hex("#E2242F"),
	pupil = hex("#1A1214"),
	tooth = hex("#E9DFC4"),
	toothShade = hex("#CFC3A3"),
	gum = hex("#3A1A22"),
	mouth = hex("#1E1719"),
	claw = hex("#221F2C"),
	mass = hex("#333739"),
	massLight = hex("#404449"),
	massDeep = hex("#1B1A1B"),
	mane = hex("#F2F3F8"),
	maneSoft = hex("#E2E1EE"),
	maneShade = hex("#A9A8C2"),
	maneDeep = hex("#8D89A6"),
	strandLine = Color3.fromRGB(38, 34, 52),
	outline = Color3.fromRGB(20, 18, 28),
}

-- Эллипсоид-объём (для расчёта поверхности маски/тела): мировой CFrame центра и полуоси
type Vol = { cf: CFrame, r: Vector3 }

local function deg(a: number): number
	return math.rad(a)
end

local function R(x: number, y: number, z: number): CFrame
	return CFrame.Angles(deg(x), deg(y), deg(z))
end

-- Пересечение луча o + d*t с эллипсоидом: (t входа, t выхода) или nil
local function hitVol(v: Vol, o: Vector3, d: Vector3): (number?, number?)
	local lo = v.cf:Inverse() * o
	local ld = v.cf:VectorToObjectSpace(d)
	local oo = V(lo.X / v.r.X, lo.Y / v.r.Y, lo.Z / v.r.Z)
	local dd = V(ld.X / v.r.X, ld.Y / v.r.Y, ld.Z / v.r.Z)
	local a = dd:Dot(dd)
	local b = 2 * oo:Dot(dd)
	local c = oo:Dot(oo) - 1
	local disc = b * b - 4 * a * c
	if disc < 0 or a < 1e-9 then
		return nil, nil
	end
	local sq = math.sqrt(disc)
	return (-b - sq) / (2 * a), (-b + sq) / (2 * a)
end

local function normalOf(v: Vol, p: Vector3): Vector3
	local lp = v.cf:Inverse() * p
	local ln = V(lp.X / (v.r.X * v.r.X), lp.Y / (v.r.Y * v.r.Y), lp.Z / (v.r.Z * v.r.Z))
	return v.cf:VectorToWorldSpace(ln).Unit
end

-- Внешняя поверхность объединения объёмов вдоль луча из внутренней точки o (самый дальний выход)
local function castOut(vols: { Vol }, o: Vector3, d: Vector3): (Vector3, Vector3)
	local best = -1
	local bv: Vol? = nil
	for _, v in vols do
		local _, t1 = hitVol(v, o, d)
		if t1 and t1 > best then
			best = t1
			bv = v
		end
	end
	if bv == nil then
		return o, d
	end
	local p = o + d * best
	return p, normalOf(bv, p)
end

-- Первая встреча луча снаружи с объединением объёмов
local function castIn(vols: { Vol }, o: Vector3, d: Vector3): (Vector3?, Vector3?)
	local best = math.huge
	local bv: Vol? = nil
	for _, v in vols do
		local t0, _ = hitVol(v, o, d)
		if t0 and t0 > 0 and t0 < best then
			best = t0
			bv = v
		end
	end
	if bv == nil then
		return nil, nil
	end
	local p = o + d * best
	return p, normalOf(bv, p)
end

-- CFrame с осью Z по нормали n и осью Y вдоль касательной t (ортогонализуется)
local function surfFrame(p: Vector3, n: Vector3, t: Vector3): CFrame
	local z = n.Unit
	local y = t - z * t:Dot(z)
	if y.Magnitude < 1e-5 then
		y = V(0, 1, 0) - z * z.Y
	end
	y = y.Unit
	local x = y:Cross(z).Unit
	return CFrame.fromMatrix(p, x, y, z)
end

function Rika.build(origin: CFrame): Model
	local def = Skeletons.Rika
	local ctx = Sculpt.newCharacter("Rika", def, origin)
	local rng = MathX.rng(1708)

	local function J(bone: string): Vector3
		return Rig.restOf(def, bone).Position
	end
	-- мировой (модельный) CFrame -> CFrame в осях кости
	local function toBone(bone: string, cf: CFrame): CFrame
		return CFrame.new(-J(bone)) * cf
	end
	local function ellCF(bone: string, cf: CFrame, size: Vector3, col: Color3, opts: Sculpt.Opts?): Part
		return Sculpt.ellipsoid(ctx, bone, toBone(bone, cf), size, col, opts)
	end
	local function ell(bone: string, p: Vector3, size: Vector3, col: Color3, rot: CFrame?, opts: Sculpt.Opts?): Part
		return ellCF(bone, CFrame.new(p) * (rot or CFrame.new()), size, col, opts)
	end
	local function boxCF(bone: string, cf: CFrame, size: Vector3, col: Color3, opts: Sculpt.Opts?): Part
		return Sculpt.box(ctx, bone, toBone(bone, cf), size, col, opts)
	end
	local function seg(bone: string, a: Vector3, b: Vector3, w: number, d: number, col: Color3, roll: number?, ext: number?, opts: Sculpt.Opts?): Part
		local j = J(bone)
		return Sculpt.segment(ctx, bone, a - j, b - j, w, d, col, opts, roll, ext)
	end
	local function ball(bone: string, p: Vector3, dia: number, col: Color3, opts: Sculpt.Opts?): Part
		return ell(bone, p, V(dia, dia, dia), col, nil, opts)
	end
	-- эллипсоид вдоль отрезка a-b: X — горизонтально поперёк, Z — «вверх» (хвост, лоскуты)
	local function tube(bone: string, a: Vector3, b: Vector3, lat: number, vert: number, col: Color3, ext: number?, opts: Sculpt.Opts?): Part
		local dir = b - a
		local y = dir.Unit
		local x = y:Cross(V(0, 1, 0))
		if x.Magnitude < 1e-3 then
			x = y:Cross(V(0, 0, -1))
		end
		x = x.Unit
		local z = x:Cross(y).Unit
		return ellCF(bone, CFrame.fromMatrix((a + b) / 2, x, y, z), V(lat, dir.Magnitude * (ext or 1), vert), col, opts)
	end
	-- цепочка эллипсоидов-«полосок» по точкам поверхности (ось Z — нормаль)
	local function band(bone: string, pts: { Vector3 }, nrm: { Vector3 }, widths: { number }, col: Color3, thick: number, lift: number)
		for i = 1, #pts - 1 do
			local a = pts[i] + nrm[i] * lift
			local b = pts[i + 1] + nrm[i + 1] * lift
			local n = (nrm[i] + nrm[i + 1]).Unit
			local len = (b - a).Magnitude
			if len > 1e-4 then
				local w = (widths[i] + widths[i + 1]) / 2
				ellCF(bone, surfFrame((a + b) / 2, n, b - a), V(w, len * 1.45 + w * 0.3, thick), col)
			end
		end
	end

	------------------------------------------------------------------------------------------
	-- ГОЛОВА / МАСКА
	------------------------------------------------------------------------------------------
	local H = J("Head")
	-- верхняя точка маски: лицо задаём от неё (y вниз — отрицательный, z — от средней плоскости маски)
	local T = H + V(0, 2.55, -0.75)
	local function M(x: number, y: number, z: number): Vector3
		return T + V(x, y, z)
	end
	local TEETH_TOP = -2.25
	local BITE = -2.57
	local TEETH_BOTTOM = -2.87
	local ARC_Z = 0.0 -- центр дуги зубов по глубине
	local RA = 0.5 -- радиус дуги зубов
	local EYE_Y = -1.63 -- центр глаза
	local EYE_HH = 0.45 -- полувысота щели
	local EYE_HW = 0.185 -- полуширина щели

	local maskVols: { Vol } = {}
	do
		local function maskVol(bone: string, cf: CFrame, r: Vector3)
			table.insert(maskVols, { cf = cf, r = r })
			ellCF(bone, cf, r * 2, COL.mask)
		end
		-- купол: шире всего на ~38% высоты, макушка чуть нависает вперёд
		maskVol("Head", CFrame.new(M(0, -0.85, 0.0)) * R(-8, 0, 0), V(0.84, 0.85, 0.79))
		-- нижняя часть луковицы: стопка эллипсоидов по профилю, сужается в «рыло» над зубами
		for _, yc in { -1.15, -1.45, -1.75, -2.02 } do
			local s = (-0.85 - yc) / 1.4
			local k = (1 - s ^ 1.6) ^ 0.8
			local a = if yc < -1.9 then 0.36 else 0.45
			maskVol("Head", CFrame.new(M(0, yc, -0.1 * s)), V(0.38 + 0.46 * k, a, 0.5 + 0.29 * k))
		end
		-- скулы: мост от рыла к уголкам рта
		maskVol("Head", CFrame.new(M(0, -2.12, -0.02)), V(0.55, 0.2, 0.52))
	end

	-- Зубы на дуге ~150°
	local function arcCF(alpha: number, y: number, r: number): CFrame
		local a = deg(alpha)
		local out = V(math.sin(a), 0, -math.cos(a))
		local p = M(0, y, ARC_Z) + out * r
		local yv = V(0, 1, 0)
		return CFrame.fromMatrix(p, yv:Cross(out).Unit, yv, out)
	end
	local function smile(alpha: number): number
		local s = alpha / 75
		return s * s
	end
	local chinVols: { Vol } = {}
	do
		-- щёки за верхними зубами и тёмная пасть за ними
		ell("Head", M(0, -2.38, 0.03), V(0.88, 0.46, 0.88), COL.mask)
		ell("Head", M(0, -2.41, ARC_Z), V(0.95, 0.36, 0.95), COL.mouth)
		-- нижняя челюсть (кость Jaw): тёмная основа за зубами, подбородок сужается к тупому острию
		ell("Jaw", M(0, -2.72, ARC_Z), V(0.95, 0.32, 0.95), COL.mouth)
		local function chinVol(cf: CFrame, r: Vector3)
			table.insert(chinVols, { cf = cf, r = r })
			table.insert(maskVols, { cf = cf, r = r })
			ellCF("Jaw", cf, r * 2, COL.mask)
		end
		chinVol(CFrame.new(M(0, -2.86, 0.02)), V(0.45, 0.2, 0.44))
		chinVol(CFrame.new(M(0, -3.03, -0.08)), V(0.33, 0.22, 0.36))
		chinVol(CFrame.new(M(0, -3.2, -0.17)), V(0.16, 0.14, 0.2))

		-- зубы: тело-брусок + скруглённый край; крайние уходят назад в щёки
		local N_TEETH = 7
		local pitch = 150 / N_TEETH
		for row = 1, 2 do
			local upper = row == 1
			local bone = if upper then "Head" else "Jaw"
			for i = 1, N_TEETH do
				local alpha = -75 + (i - 0.5) * pitch
				local s = smile(alpha)
				local bite = BITE + 0.07 * s
				local root = if upper then TEETH_TOP + 0.035 * s + 0.05 else TEETH_BOTTOM + 0.075 * s - 0.04
				local tip = if upper then bite + 0.006 else bite - 0.006
				local h = math.abs(root - tip)
				local w = RA * deg(pitch) - 0.028
				local rc = 0.055
				local col = if math.abs(alpha) > 50 then COL.toothShade else COL.tooth
				local sgn = if upper then 1 else -1
				boxCF(bone, arcCF(alpha, (root + tip + sgn * rc) / 2, RA), V(w, h - rc, 0.1), col)
				ellCF(bone, arcCF(alpha, tip + sgn * rc, RA), V(w, rc * 2.1, 0.1), col)
			end
		end
		-- рваный край маски над верхними зубами и под нижними (кожа срезана прямо на зубы)
		for i = 0, 10 do
			local alpha = -84 + i * 16.8
			local s = smile(alpha)
			local h = 0.1 + (if i % 2 == 0 then 0.06 else 0.0) + 0.02 * rng:next()
			local cf = arcCF(alpha, TEETH_TOP + 0.035 * s + 0.06 - h * 0.3, RA + 0.04)
			ellCF("Head", cf * R(0, 0, (if i % 2 == 0 then 1 else -1) * 18), V(0.17, h + 0.08, 0.05), COL.mask)
		end
		for i = 0, 8 do
			local alpha = -78 + i * 19.5
			local s = smile(alpha)
			local h = 0.08 + (if i % 2 == 1 then 0.05 else 0.0) + 0.02 * rng:next()
			local cf = arcCF(alpha, TEETH_BOTTOM + 0.075 * s - 0.04 + h * 0.3, RA + 0.035)
			ellCF("Jaw", cf * R(0, 0, (if i % 2 == 0 then 1 else -1) * 18), V(0.17, h + 0.06, 0.05), COL.mask)
		end
		-- тёмные дёсны в уголках рта
		for _, sx in { -1, 1 } do
			ellCF("Head", arcCF(sx * 82, BITE + 0.15, RA - 0.04), V(0.13, 0.36, 0.16), COL.gum)
			ellCF("Jaw", arcCF(sx * 82, BITE - 0.08, RA - 0.04), V(0.13, 0.3, 0.16), COL.gum)
		end
		-- складка на подбородке
		local p, n = castIn(chinVols, M(0, -3.08, -3), V(0, 0, 1))
		if p and n then
			ellCF("Jaw", surfFrame(p, n, V(0, 1, 0)), V(0.05, 0.14, 0.04), COL.skinMid)
		end
	end

	-- Полосы: сечения поверхности плоскостями через общую прямую L (входит у подбородка, выходит
	-- сзади-снизу). Поэтому полосы сходятся к рылу, а на куполе расходятся веером и уходят под гриву.
	local LC = M(0, -3.0, -0.5)
	local LU = V(0, 0.55, 0.835).Unit
	local LQ = LC + LU * 0.9 -- внутренняя точка на прямой, из неё бросаем лучи
	local W0 = LU:Cross(V(1, 0, 0)).Unit -- (0, 0.835, -0.55): вверх-вперёд
	local function stripePoint(gamma: number, psi: number): (Vector3, Vector3)
		-- плоскость, повернутая вокруг L на gamma; psi от направления на подбородок (0) к затылку (180)
		local w = W0 * math.cos(deg(gamma)) + V(1, 0, 0) * math.sin(deg(gamma))
		return castOut(maskVols, LQ, (-LU * math.cos(deg(psi)) + w * math.sin(deg(psi))).Unit)
	end

	-- Глаз: на центральной плоскости
	local eyeCF: CFrame
	do
		local lo, hi = 20, 140
		for _ = 1, 40 do
			local mid = (lo + hi) / 2
			local p, _ = stripePoint(0, mid)
			if p.Y < T.Y + EYE_Y then
				lo = mid
			else
				hi = mid
			end
		end
		local psi = (lo + hi) / 2
		local p, n = stripePoint(0, psi)
		local up = (stripePoint(0, psi + 2) - stripePoint(0, psi - 2)).Unit
		eyeCF = surfFrame(p, n, up)
	end

	do
		-- x полосы на заданной высоте (по передней части кривой)
		local function stripeXAt(gamma: number, y: number): number
			local prev: Vector3? = nil
			for k = 0, 180 do
				local p, _ = stripePoint(gamma, 20 + k * 0.7)
				if prev and p.Z < T.Z + 0.1 and (prev.Y - y) * (p.Y - y) <= 0 then
					return p.X
				end
				prev = p
			end
			return 0
		end
		local function solveGamma(targetX: number, y: number): number
			local lo, hi = 0, 60
			for _ = 1, 30 do
				local mid = (lo + hi) / 2
				if stripeXAt(mid, y) < targetX then
					lo = mid
				else
					hi = mid
				end
			end
			return (lo + hi) / 2
		end
		for k = 0, 12 do
			local pp, _ = stripePoint(10, 20 + k * 10)
			print("PSI", 20 + k * 10, pp)
		end
		print("XAT", stripeXAt(10, T.Y - 0.85), T)
		local maskW = 1.68
		local STRIPES = {
			{ x = 0, w = 0.135 }, -- центральная, самая широкая, расходится вокруг глаза
			{ x = 0.22 * maskW, w = 0.085 },
			{ x = -0.22 * maskW, w = 0.085 },
			{ x = 0.40 * maskW, w = 0.075 },
			{ x = -0.40 * maskW, w = 0.075 },
		}
		local stopY = T.Y + TEETH_TOP + 0.08
		for _, st in STRIPES do
			local gamma = if st.x == 0 then 0 else math.sign(st.x) * solveGamma(math.abs(st.x), T.Y - 0.85)
			local pts: { Vector3 } = {}
			local nrm: { Vector3 } = {}
			local wid: { number } = {}
			local function flush()
				print("  run", #pts, pts[1], pts[#pts])
				if #pts >= 2 then
					band("Head", pts, nrm, wid, COL.stripe, 0.07, 0.012)
				end
				pts, nrm, wid = {}, {}, {}
			end
			local psi = 10
			while psi <= 170 do
				local p, n = stripePoint(gamma, psi)
				local rel = p - T
				local inEye = st.x == 0 and math.abs(rel.Y - EYE_Y) < EYE_HH * 0.98 and rel.Z < 0
				-- сзади полоса уходит под гриву
				local hidden = rel.Z > 0.55 and rel.Y < -0.2
				if p.Y > stopY and not inEye and not hidden then
					local taper = if rel.Z > 0 then math.max(0.35, 1 - rel.Z * 1.2) else 1
					taper *= math.clamp(0.7 + (p.Y - stopY) * 1.5, 0.7, 1)
					if st.x == 0 then
						-- у вершин щели центральная полоса сужается в острие
						local dEye = math.abs(rel.Y - EYE_Y) - EYE_HH
						if dEye < 0.25 then
							taper *= math.clamp(0.45 + dEye * 2.2, 0.45, 1)
						end
					end
					-- лёгкая «рукописная» неровность
					local wob = 1 + 0.08 * math.sin(psi * 0.31 + st.x * 7)
					table.insert(pts, p)
					table.insert(nrm, n)
					table.insert(wid, st.w * taper * wob)
				else
					flush()
				end
				psi += if psi < 60 then 3 else 4.5
			end
			flush()
			print("STRIPE", st.x, gamma)
		end
	end

	do
		-- Глаз: тёмная прорезь шва, склера, радужка (Neon "Eye"), зрачок, блик, толстые веки-кромки
		ellCF("Head", eyeCF * CFrame.new(0, 0, 0.012), V(EYE_HW * 2 + 0.1, EYE_HH * 2 * 0.92, 0.07), COL.stripe)
		ellCF("Head", eyeCF * CFrame.new(0, 0, 0.026), V(EYE_HW * 2 * 0.86, EYE_HH * 2 * 0.78, 0.07), COL.sclera)
		for _, sy in { -1, 1 } do
			ellCF("Head", eyeCF * CFrame.new(0, sy * EYE_HH * 0.55, 0.024), V(EYE_HW * 0.95, EYE_HH * 0.75, 0.06), COL.sclera)
		end
		local irisY = 0.05
		ellCF("Head", eyeCF * CFrame.new(0, irisY, 0.05), V(0.22, 0.22, 0.05), COL.irisRing)
		ellCF("Head", eyeCF * CFrame.new(0, irisY, 0.062), V(0.17, 0.17, 0.05), COL.eye, { material = Enum.Material.Neon, name = "Eye" })
		ellCF("Head", eyeCF * CFrame.new(0, irisY, 0.08), V(0.065, 0.065, 0.03), COL.pupil)
		ball("Head", (eyeCF * CFrame.new(0.045, irisY + 0.05, 0.095)).Position, 0.05, Color3.new(1, 1, 1), { material = Enum.Material.Neon })
		-- веки: две дуги-«чечевицы» с острыми концами
		for _, sx in { -1, 1 } do
			local pts: { Vector3 } = {}
			local nrm: { Vector3 } = {}
			local wid: { number } = {}
			for k = 0, 8 do
				local v = -1 + k / 4
				local q = eyeCF * V(EYE_HW * (1 - v * v) * sx, v * EYE_HH, 0)
				local p, n = castOut(maskVols, LQ, (q - LQ).Unit)
				table.insert(pts, p)
				table.insert(nrm, n)
				table.insert(wid, 0.05 + 0.025 * (1 - v * v))
			end
			band("Head", pts, nrm, wid, COL.stripe, 0.08, 0.03)
		end
		-- красный свет глаза (яркость анимирует сцена)
		Sculpt.light(ctx, "Head", (eyeCF * CFrame.new(0, irisY, 0.5)).Position - H, "PointLight", {
			Name = "EyeLight",
			Brightness = 0,
			Range = 12,
			Color = Color3.fromRGB(255, 42, 58),
			Shadows = false,
		})
	end

	------------------------------------------------------------------------------------------
	-- ШЕЯ / ТОРС (смещения от своих костей)
	------------------------------------------------------------------------------------------
	local C = J("Chest")
	local S = J("Spine")
	local HP = J("Hips")
	local torsoVols: { Vol } = {}
	local function tvol(bone: string, p: Vector3, size: Vector3, col: Color3, rot: CFrame?)
		local cf = CFrame.new(p) * (rot or CFrame.new())
		table.insert(torsoVols, { cf = cf, r = size / 2 })
		ellCF(bone, cf, size, col)
	end
	-- точка на передней поверхности торса
	local function frontAt(x: number, y: number): (Vector3, Vector3)
		local p, n = castIn(torsoVols, V(x, y, -10), V(0, 0, 1))
		if p and n then
			return p, n
		end
		return V(x, y, -1), V(0, 0, -1)
	end

	do
		-- шея: толстая, в тени; голова вынесена вперёд между буграми трапеций
		seg("Neck", C + V(0, 0.95, 0.25), H + V(0, 0.75, -0.4), 1.05, 1.05, COL.skinMid)
		ell("Neck", H + V(0, -0.15, -0.45), V(0.85, 0.85, 0.55), COL.skinCore)
		for _, sx in { -1, 1 } do
			seg("Neck", H + V(sx * 0.34, 0.55, -0.4), C + V(sx * 0.13, 1.05, -0.68), 0.18, 0.18, COL.skinShade)
		end

		-- грудная клетка, спина, талия
		tvol("Chest", C + V(0, -0.15, 0.1), V(2.75, 2.7, 2.0), COL.skin)
		tvol("Chest", C + V(0, 0.45, 0.12), V(3.3, 1.5, 2.1), COL.skin)
		tvol("Chest", C + V(0, 0.25, 0.8), V(2.5, 1.9, 0.85), COL.skin)
		tvol("Spine", S + V(0, -0.2, 0.05), V(2.0, 2.3, 1.5), COL.skin)
		for _, sx in { -1, 1 } do
			-- широчайшие (V-силуэт)
			tvol("Chest", C + V(sx * 1.17, -0.45, 0.25), V(0.95, 2.3, 1.35), COL.skin, R(0, 0, sx * 10))
			-- косые мышцы живота
			tvol("Spine", S + V(sx * 0.77, -0.45, -0.02), V(0.55, 1.6, 1.05), COL.skin, R(0, 0, -sx * 5))
		end

		for _, sx in { -1, 1 } do
			-- грудные мышцы: крупные, с тенью-складкой снизу
			ell("Chest", C + V(sx * 0.66, 0.18, -0.7), V(1.55, 1.1, 0.72), COL.skinLit, R(6, 0, sx * 14))
			ell("Chest", C + V(sx * 0.7, -0.27, -0.6), V(1.38, 0.34, 0.55), COL.skinMid, R(0, 0, sx * 10))
			-- лопатки
			ell("Chest", C + V(sx * 0.62, 0.15, 0.95), V(0.85, 1.05, 0.45), COL.skinLit, R(0, 0, sx * 12))
			-- зубчатые мышцы и рёбра на боках
			for k = 0, 2 do
				local y = C.Y - 0.35 - k * 0.26
				local p, n = castIn(torsoVols, V(sx * 3, y, -0.35 + k * 0.04), V(-sx, 0, 0))
				if p and n then
					ellCF("Chest", surfFrame(p + n * 0.02, n, V(sx * 0.6, 1, 0)), V(0.16, 0.36, 0.08), COL.skinLit)
					ellCF("Chest", surfFrame(p + n * 0.005 + V(0, -0.13, 0), n, V(sx * 0.6, 1, 0)), V(0.06, 0.34, 0.05), COL.skinShade)
				end
			end
			-- трапеции: высокие бугры по бокам головы
			seg("Chest", C + V(sx * 0.22, 1.35, 0.32), C + V(sx * 1.75, 1.02, 0.12), 0.95, 1.35, COL.skin)
			ell("Chest", C + V(sx * 0.75, 1.52, 0.38), V(1.05, 0.62, 1.05), COL.skinMid, R(0, 0, -sx * 18))
			-- ключицы
			local cl = "Clavicle" .. (if sx < 0 then "L" else "R")
			seg(cl, C + V(sx * 0.35, 1.05, -0.62), C + V(sx * 1.45, 1.02, -0.45), 0.13, 0.13, COL.skinLit)
			-- мышцы спины вдоль позвоночника
			seg("Spine", S + V(sx * 0.24, -0.75, 0.62), S + V(sx * 0.24, 0.8, 0.72), 0.36, 0.3, COL.skin)
		end
		-- грудина
		local a, _ = frontAt(0, C.Y + 0.65)
		local b, _ = frontAt(0, C.Y - 0.3)
		seg("Chest", a + V(0, 0, 0.01), b + V(0, 0, 0.01), 0.07, 0.08, COL.skinShade)
		-- пресс: 3 ряда кубиков под грудью, белая линия и поперечные перемычки
		for row = 0, 2 do
			local y = S.Y + 0.52 - row * 0.5
			for _, sx in { -1, 1 } do
				local p, n = frontAt(sx * 0.27, y)
				ellCF("Spine", surfFrame(p + n * 0.05, n, V(0, 1, 0)), V(0.44, 0.42, 0.24), COL.skinLit)
			end
			if row > 0 then
				local pa, _ = frontAt(-0.46, y + 0.25)
				local pb, _ = frontAt(0.46, y + 0.25)
				local pc, _ = frontAt(0, y + 0.25)
				seg("Spine", pa + V(0, 0, 0.03), pc + V(0, 0, -0.02), 0.05, 0.05, COL.skinShade)
				seg("Spine", pc + V(0, 0, -0.02), pb + V(0, 0, 0.03), 0.05, 0.05, COL.skinShade)
			end
		end
		local la, _ = frontAt(0, S.Y + 0.8)
		local lb, _ = frontAt(0, S.Y - 0.7)
		seg("Spine", la + V(0, 0, -0.03), lb + V(0, 0, -0.03), 0.05, 0.06, COL.skinShade)
	end

	------------------------------------------------------------------------------------------
	-- НИЖНЯЯ ЧАСТЬ: чёрная дымная масса и хвост
	------------------------------------------------------------------------------------------
	do
		-- переход кожи в черноту: рваная граница из «языков» и пятен
		for k = 0, 13 do
			local a = deg(k * (360 / 14) + rng:range(-8, 8))
			local p = HP + V(math.sin(a) * 1.0, 0.32 + rng:range(-0.12, 0.18), 0.05 - math.cos(a) * 0.75)
			ell("Hips", p, V(0.45, rng:range(0.35, 0.7), 0.35), COL.skinCore, R(0, -k * (360 / 14), rng:range(-15, 15)))
		end
		for _ = 1, 10 do
			local a = deg(rng:range(-70, 70))
			local y = S.Y + rng:range(-0.65, -0.25)
			local p, n = castIn(torsoVols, V(math.sin(a) * 3, y, -math.cos(a) * 3), V(-math.sin(a), 0, math.cos(a)))
			if p and n then
				local s = rng:range(0.08, 0.16)
				ellCF("Spine", surfFrame(p, n, V(0, 1, 0)), V(s, s * 1.2, 0.06), COL.skinCore)
			end
		end
		ell("Hips", HP + V(0, 0.25, 0.05), V(2.05, 0.75, 1.55), COL.massDeep)
		ell("Hips", HP + V(0, -0.35, 0.12), V(2.4, 1.6, 1.95), COL.mass)
		ell("Hips", HP + V(0, -0.9, 0.3), V(2.6, 1.6, 2.15), COL.massLight)
		for _, side in { "L", "R" } do
			ell("UpperLeg" .. side, J("UpperLeg" .. side) + V(0, -1.05, 0.1), V(1.2, 1.9, 1.5), COL.mass)
			ell("LowerLeg" .. side, J("LowerLeg" .. side) + V(0, -0.4, 0.25), V(1.0, 1.4, 1.2), COL.massDeep)
			-- невидимые «подошвы»: только точки для пыли от толчков
			boxCF("Foot" .. side, CFrame.new(J("Foot" .. side) + V(0, -0.2, -0.1)), V(0.6, 0.05, 0.9), COL.massDeep, {
				name = "Sole" .. side,
				transparency = 1,
				castShadow = false,
			})
		end
		-- масса стекает к земле и уходит назад хвостом (кость Root: хвост скользит по земле вместе с моделью)
		ell("Root", V(0, 1.85, 0.7), V(2.15, 2.0, 2.0), COL.mass)
		ell("Root", V(0, 0.95, 1.35), V(1.85, 1.5, 2.1), COL.massDeep)
		local tail = {
			V(0.0, 1.0, 1.9),
			V(0.35, 0.62, 2.7),
			V(0.75, 0.48, 3.6),
			V(0.95, 0.42, 4.5),
			V(0.7, 0.38, 5.35),
			V(0.1, 0.36, 6.0),
			V(-0.6, 0.38, 6.5),
			V(-1.0, 0.5, 6.95),
			V(-1.1, 0.8, 7.3),
			V(-0.95, 1.15, 7.45),
			V(-0.7, 1.4, 7.35),
		}
		local tw = { 1.7, 1.5, 1.3, 1.1, 0.92, 0.75, 0.58, 0.42, 0.28, 0.16, 0.06 }
		local th = { 1.0, 0.82, 0.68, 0.58, 0.5, 0.42, 0.34, 0.26, 0.18, 0.11, 0.05 }
		for i = 1, #tail - 1 do
			tube("Root", tail[i], tail[i + 1], (tw[i] + tw[i + 1]) / 2, (th[i] + th[i + 1]) / 2, if i % 3 == 0 then COL.massDeep else COL.mass, 1.6)
		end
		-- рваные дымные лоскуты по краям массы и хвоста
		local tatters = {
			{ a = HP + V(1.15, -0.1, 0.2), b = HP + V(1.75, -0.7, 0.6) },
			{ a = HP + V(-1.15, -0.2, 0.3), b = HP + V(-1.8, -0.85, 0.5) },
			{ a = V(1.05, 1.9, 0.9), b = V(1.6, 1.2, 1.4) },
			{ a = V(-1.05, 1.7, 1.0), b = V(-1.55, 1.0, 1.6) },
			{ a = HP + V(0.0, -0.4, 1.3), b = HP + V(0.2, -0.8, 2.2) },
			{ a = V(1.3, 0.55, 3.6), b = V(1.85, 0.4, 4.2) },
			{ a = V(-0.2, 0.5, 3.9), b = V(-0.9, 0.35, 4.3) },
			{ a = V(1.2, 0.45, 5.0), b = V(1.65, 0.3, 5.5) },
			{ a = V(-0.4, 0.45, 5.9), b = V(-0.6, 0.3, 6.6) },
			{ a = V(-0.95, 1.2, 7.4), b = V(-1.35, 1.55, 7.65) },
		}
		for i, t in tatters do
			local bone = if t.a.Y > HP.Y - 0.6 then "Hips" else "Root"
			tube(bone, t.a, t.b, 0.38 - i * 0.012, 0.12, if i % 2 == 0 then COL.massDeep else COL.mass, 1.2)
			tube(bone, t.b - (t.b - t.a) * 0.2, t.b + (t.b - t.a) * 0.35, 0.14, 0.08, COL.massDeep, 1.0)
		end
	end

	------------------------------------------------------------------------------------------
	-- РУКИ И КИСТИ
	------------------------------------------------------------------------------------------
	do
		local FINGERS = { "Index", "Middle", "Ring", "Pinky" }
		local FSCALE: { [string]: number } = { Index = 0.92, Middle = 1.0, Ring = 0.95, Pinky = 0.78 }
		for _, side in { "L", "R" } do
			local sx = if side == "L" then -1 else 1
			local JS = J("UpperArm" .. side)
			local JE = J("LowerArm" .. side)
			local JH = J("Hand" .. side)
			local UA = "UpperArm" .. side
			local LA = "LowerArm" .. side
			local HB = "Hand" .. side
			-- плечевой «шарнир» на ключице: закрывает щель при подъёме руки
			ball("Clavicle" .. side, JS + V(-sx * 0.12, 0.02, 0), 1.0, COL.skin)
			-- дельта
			ell(UA, JS + V(sx * 0.12, -0.2, 0), V(1.15, 1.45, 1.2), COL.skinLit)
			ell(UA, JS + V(sx * 0.05, -0.32, -0.33), V(0.75, 1.2, 0.6), COL.skinLit, R(8, 0, 0))
			ell(UA, JS + V(sx * 0.05, -0.32, 0.33), V(0.75, 1.2, 0.6), COL.skin, R(-8, 0, 0))
			-- плечо: основа, бицепс, трицепс, тень внутренней стороны
			seg(UA, JS + V(0, -0.2, 0), JS + V(0, -2.45, 0), 0.9, 0.9, COL.skin)
			seg(UA, JS + V(-sx * 0.03, -0.75, -0.18), JS + V(0, -2.15, -0.14), 0.78, 0.72, COL.skinLit)
			seg(UA, JS + V(sx * 0.06, -0.45, 0.2), JS + V(0, -2.1, 0.2), 0.8, 0.7, COL.skin)
			seg(UA, JS + V(-sx * 0.22, -0.7, 0.06), JS + V(-sx * 0.18, -2.0, 0.05), 0.5, 0.66, COL.skinMid)
			ball(UA, JE + V(0, 0, 0.04), 0.72, COL.skin)
			-- предплечье
			ball(LA, JE + V(0, 0, 0.04), 0.7, COL.skin)
			ell(LA, JE + V(0, -0.05, 0.3), V(0.36, 0.42, 0.3), COL.skinMid)
			seg(LA, JE + V(sx * 0.08, 0.05, -0.1), JE + V(sx * 0.05, -1.3, -0.06), 0.78, 0.74, COL.skinLit)
			seg(LA, JE + V(-sx * 0.1, 0.0, 0.08), JE + V(-sx * 0.04, -1.5, 0.03), 0.66, 0.66, COL.skinMid)
			seg(LA, JE, JE + V(0, -2.15, 0), 0.62, 0.58, COL.skin)
			seg(LA, JE + V(0, -1.2, 0), JE + V(0, -2.15, 0), 0.58, 0.48, COL.skin)
			-- кисть: ладонь смотрит к телу (-sx), тыл наружу (+sx)
			ball(HB, JH, 0.52, COL.skin)
			ell(HB, JH + V(0, -0.27, 0), V(0.3, 0.66, 0.68), COL.skin)
			ell(HB, JH + V(sx * 0.05, -0.28, 0), V(0.2, 0.6, 0.62), COL.skinLit)
			ell(HB, JH + V(-sx * 0.07, -0.2, -0.2), V(0.24, 0.4, 0.28), COL.skinMid)
			ell(HB, JH + V(-sx * 0.05, -0.33, 0.2), V(0.2, 0.42, 0.22), COL.skinMid)
			for _, f in FINGERS do
				local s = FSCALE[f]
				local j1 = J(f .. "1" .. side)
				local j2 = J(f .. "2" .. side)
				local j3 = J(f .. "3" .. side)
				local tip = j3 + V(0, -0.17 * s, 0)
				-- сухожилие на тыле кисти
				seg(HB, JH + V(sx * 0.1, -0.08, j1.Z * 0.5), j1 + V(sx * 0.1, 0.06, 0), 0.06, 0.06, COL.skinLit)
				-- узловатые фаланги
				ball(f .. "1" .. side, j1 + V(sx * 0.02, 0, 0), 0.19, COL.skinLit)
				seg(f .. "1" .. side, j1, j2, 0.155, 0.15, COL.skin)
				ball(f .. "2" .. side, j2, 0.155, COL.skin)
				seg(f .. "2" .. side, j2, j3, 0.14, 0.135, COL.skin)
				ball(f .. "3" .. side, j3, 0.14, COL.skin)
				seg(f .. "3" .. side, j3, tip, 0.125, 0.12, COL.skin)
				-- короткий чёрный коготь-колпачок
				ell(f .. "3" .. side, tip + V(sx * 0.015, -0.03, 0), V(0.13, 0.17, 0.125), COL.claw)
			end
			local t1 = J("Thumb1" .. side)
			local t2 = J("Thumb2" .. side)
			local t3 = J("Thumb3" .. side)
			local ttip = t3 + V(0, -0.17, -0.02)
			seg("Thumb1" .. side, t1 + V(0, 0.05, 0.05), t2, 0.22, 0.2, COL.skin)
			ball("Thumb2" .. side, t2, 0.17, COL.skin)
			seg("Thumb2" .. side, t2, t3, 0.165, 0.16, COL.skin)
			ball("Thumb3" .. side, t3, 0.15, COL.skin)
			seg("Thumb3" .. side, t3, ttip, 0.14, 0.135, COL.skin)
			ell("Thumb3" .. side, ttip + V(sx * 0.01, -0.03, -0.01), V(0.14, 0.17, 0.13), COL.claw)
		end
	end

	------------------------------------------------------------------------------------------
	-- ГРИВА: объёмное ядро (эллипсоиды) + пряди-«языки пламени» (Beam)
	------------------------------------------------------------------------------------------
	do
		ell("Head", T + V(0, -0.4, 0.85), V(2.5, 2.4, 1.9), COL.maneSoft)
		ell("Head", T + V(0, -1.9, 1.05), V(2.2, 2.2, 1.4), COL.maneShade)
		ell("Mane", T + V(0, 0.8, 1.05), V(2.0, 2.2, 1.9), COL.mane)
		ell("Mane", T + V(0, 1.6, 0.55), V(0.7, 1.0, 0.7), COL.maneShade)
		for _, sx in { -1, 1 } do
			ell("Mane", T + V(sx * 0.8, 1.25, 0.85), V(2.0, 2.3, 1.9), COL.mane, R(0, 0, -sx * 15))
			ell("Head", T + V(sx * 1.3, -0.3, 0.6), V(1.6, 2.2, 1.6), COL.mane, R(0, 0, sx * 12))
			ell("Head", T + V(sx * 1.05, -1.6, 0.55), V(1.1, 1.9, 1.3), COL.maneSoft, R(0, 0, -sx * 8))
		end
	end

	-- Прядь: старт root, начальное направление dir, изгиб в сторону bend; turns — поворот (градусы) на каждом
	-- отрезке, накапливается — так получаются S-изгибы и крюки на кончиках.
	-- Контур делаем отдельной прядью позади (тот же seed и жёсткость — ветер двигает их одинаково),
	-- чтобы кончик оставался острым (у встроенного контура Sculpt кончик тупой из-за прибавки ширины).
	local function lock(bone: string, root: Vector3, dir: Vector3, bend: Vector3, len: number, turns: { number }, w0: number, c0: Color3, c1: Color3, stiff: number)
		local d = dir.Unit
		local s = bend - d * bend:Dot(d)
		if s.Magnitude < 1e-4 then
			s = V(0, 1, 0) - d * d.Y
		end
		s = s.Unit
		local pts: { Vector3 } = { root - J(bone) }
		local widths: { number } = { w0 }
		local a = 0
		local p = root
		local n = #turns
		local step = len / n
		local prof = { 1.08, 0.95, 0.75, 0.5, 0.26, 0.1 }
		for i = 1, n do
			a += deg(turns[i])
			p = p + (d * math.cos(a) + s * math.sin(a)) * step
			table.insert(pts, p - J(bone))
			local k = math.floor((i / n) * (#prof - 1) + 0.5) + 1
			table.insert(widths, if i == n then 0 else w0 * prof[math.min(k, #prof)])
		end
		local lineW: { number } = {}
		for i, w in widths do
			lineW[i] = if i == #widths then 0 else w * 1.12 + 0.06
		end
		local seed = rng:range(1, 1000)
		Sculpt.strand(ctx, bone, pts, {
			widths = lineW,
			color0 = COL.strandLine,
			lightInfluence = 0,
			stiffness = stiff,
			seed = seed,
			segments = 10,
			zOffset = -0.05,
		})
		Sculpt.strand(ctx, bone, pts, {
			widths = widths,
			color0 = c0,
			color1 = c1,
			stiffness = stiff,
			seed = seed,
			segments = 10,
		})
	end

	do
		-- 1) «пламя» над головой: ленты вверх с крюками наружу, по краям — силуэт «сердца»
		for _, sx in { -1, 1 } do
			lock("Mane", T + V(sx * 1.25, 1.2, 0.6), V(sx * 0.55, 1, 0.2), V(sx, 0, 0), 1.9, { 0, 8, 25, 45, 60 }, 0.55, COL.maneSoft, COL.mane, 0.25)
			lock("Mane", T + V(sx * 0.85, 1.9, 0.75), V(sx * 0.25, 1, 0.25), V(sx, 0, 0), 1.4, { 0, 10, 25, 45, 55 }, 0.5, COL.maneSoft, COL.mane, 0.3)
			lock("Mane", T + V(sx * 0.35, 1.8, 0.9), V(sx * 0.05, 1, 0.3), V(-sx, 0, 0), 1.0, { 0, 10, 25, 40 }, 0.4, COL.maneShade, COL.mane, 0.35)
			lock("Mane", T + V(sx * 0.5, 1.2, 1.5), V(sx * 0.2, 0.75, 0.7), V(0, 1, 0), 1.9, { 0, -5, 10, 30, 45 }, 0.5, COL.maneShade, COL.maneSoft, 0.2)
			lock("Mane", T + V(sx * 1.0, 2.2, 0.8), V(sx * 0.3, 1, 0.05), V(sx, 0, 0), 0.8, { 0, 15, 35, 50 }, 0.2, COL.mane, COL.mane, 0.15)
		end
		-- 2) слева на экране (+X персонажа): 3 горизонтальные пряди на высоте маски (кончики загибаются вверх),
		--    2 спадают на плечо (кончики отгибаются наружу)
		lock("Head", T + V(0.75, -0.7, 0.3), V(1, -0.1, 0.25), V(0, 1, 0), 2.1, { -5, 0, 15, 45, 70 }, 0.5, COL.maneSoft, COL.mane, 0.3)
		lock("Head", T + V(0.8, -1.1, 0.25), V(1, -0.2, 0.2), V(0, 1, 0), 2.4, { -8, -2, 18, 50, 70 }, 0.55, COL.maneSoft, COL.mane, 0.25)
		lock("Head", T + V(0.75, -1.5, 0.3), V(1, -0.25, 0.3), V(0, 1, 0), 1.8, { -5, 5, 20, 45, 60 }, 0.45, COL.maneShade, COL.mane, 0.35)
		lock("Head", T + V(0.7, -1.9, 0.35), V(0.45, -1, 0.1), V(1, 0, 0), 1.9, { 0, 5, 15, 35, 50 }, 0.45, COL.maneShade, COL.mane, 0.4)
		lock("Head", T + V(0.55, -2.2, 0.5), V(0.35, -1, 0.2), V(1, 0, 0), 1.6, { 0, 8, 20, 40, 45 }, 0.4, COL.maneDeep, COL.maneSoft, 0.45)
		-- 3) справа на экране (-X): 4 длинные пряди веером с крюками вверх и 2 короткие завитка у щеки
		lock("Head", T + V(-0.75, -1.0, 0.3), V(-1, 0.15, 0.2), V(0, 1, 0), 2.4, { -10, -5, 10, 40, 75 }, 0.55, COL.maneSoft, COL.mane, 0.25)
		lock("Head", T + V(-0.8, -1.4, 0.3), V(-1, 0, 0.25), V(0, 1, 0), 2.7, { -10, -6, 12, 45, 75 }, 0.6, COL.maneSoft, COL.mane, 0.2)
		lock("Head", T + V(-0.75, -1.8, 0.35), V(-1, -0.15, 0.25), V(0, 1, 0), 2.4, { -12, -4, 15, 45, 70 }, 0.5, COL.maneShade, COL.mane, 0.3)
		lock("Head", T + V(-0.7, -2.1, 0.4), V(-1, -0.35, 0.3), V(0, 1, 0), 2.0, { -10, 0, 20, 45, 60 }, 0.45, COL.maneShade, COL.maneSoft, 0.35)
		lock("Head", T + V(-0.7, -1.35, -0.05), V(-0.6, -0.6, -0.2), V(0, 1, 0), 1.1, { 0, 30, 60, 70 }, 0.3, COL.maneSoft, COL.mane, 0.4)
		lock("Head", T + V(-0.65, -1.95, 0.0), V(-0.5, -0.8, -0.2), V(0, 1, 0), 1.0, { 5, 30, 55, 60 }, 0.28, COL.maneShade, COL.mane, 0.45)
		-- 4) тонкие волоски между большими прядями
		for i = 1, 6 do
			local sx = if i % 2 == 0 then 1 else -1
			local y = rng:range(-1.8, 0.8)
			lock("Head", T + V(sx * 0.8, y, 0.4), V(sx, rng:range(-0.1, 0.6), 0.3), V(0, 1, 0), rng:range(1.2, 2.0), { 0, 10, 25, 45 }, rng:range(0.07, 0.12), COL.mane, COL.mane, 0.1)
		end
		-- 5) сзади: пряди уходят назад-вверх (объём сбоку и сзади)
		for i = 1, 6 do
			local u = (i - 3.5) / 2.5
			lock("Mane", T + V(u * 0.9, rng:range(-1.6, 0.2), 1.3), V(u * 0.4, 0.45, 1), V(0, 1, 0), rng:range(1.8, 2.6), { -5, 5, 15, 30, 40 }, rng:range(0.4, 0.55), COL.maneShade, COL.maneSoft, rng:range(0.15, 0.45))
		end
		-- 6) по спине и плечам
		for _, sx in { -1, 1 } do
			lock("Head", T + V(sx * 0.5, -2.4, 0.9), V(sx * 0.4, -1, 0.6), V(sx, 0, 0), 1.8, { 0, 5, 15, 30 }, 0.45, COL.maneShade, COL.maneSoft, 0.5)
			lock("Head", T + V(sx * 0.15, -2.5, 1.1), V(sx * 0.15, -1, 0.8), V(sx, 0, 0), 2.0, { 0, 5, 12, 25 }, 0.4, COL.maneDeep, COL.maneShade, 0.55)
		end
	end

	Sculpt.outline(ctx, COL.outline)
	return ctx.model
end

return Rika
