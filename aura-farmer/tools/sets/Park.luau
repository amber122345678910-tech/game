--!nocheck
-- Декорация PARK (S08, S09): лужайка в городском парке, весна, яркое солнце.
-- Камера обычно в -Z и смотрит на +Z, поэтому +X — СЛЕВА в кадре, -X — справа.
--   * Terrain Grass x∈[-400,400], z∈[-300,500] (верх Y=0), дорожка (Terrain Pavement) z∈[20,24] вдоль изгороди.
--     Цвета Grass/LeafyGrass ставит скрипт ParkTerrainColors (атрибуты TerrainColor_* модели; Pavement — за Beach).
--   * Стриженая живая изгородь z∈[24.4,28.0], высота ≈2.75, x∈[-130,130] (под ней полоса LeafyGrass).
--   * Деревья (вся листва — настоящие Ball-детали LeafyGrass, без SpecialMesh):
--       слева в кадре (+X) — тёмная плотная липа (26.5,36) и вторая тёмная за ней (24,47);
--       в центре — высокие «прозрачные» ранневесенние деревья с тонкими веточками: (16,62) и (-1,76);
--       за правым плечом коня — маленькое яркое деревце (-9,52);
--       справа (-X) — жёлто-зелёное молодое дерево на линии изгороди (-15,23.6) и фонарь (-11.5,22.8);
--       второй ряд, кусты, дальние деревья по кругу.
--   * Офис справа за деревьями: угол у камеры (-40,175), фасад уходит к камере под 45° (вправо-вперёд),
--     4 этажа по 11 + тяжёлая чёрная кровля-козырёк; тёмное стекло, ряды потолочных светильников.
--   * Фонари вдоль дорожки (x = -11.5, 44, -78, 104; z ≈ 22.8), скамейка (центр сиденья (24, 1.45, 22.9),
--     лицом в -Z) и урна (28.3, 23.1); эмиттер пыльцы "ParkPollen" (ВЫКЛЮЧЕН, включать эффектом плана).
-- Зона постановки вокруг (0,0,0) свободна (ближе z=+20 нет ничего, кроме травы; невидимый объём пыльцы z∈[3,23]).

local roblox = require("@lune/roblox")
local lookAtFixed = require("../lib/LookAt") -- CFrame.lookAt в Lune неверен
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

local V = Vector3.new
local hex = Color3.fromHex

-- Детерминированный ГСЧ (Park–Miller): декорация одинакова при каждой сборке.
local seed = 90210
local function rnd(): number
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
local function rr(a: number, b: number): number
	return a + (b - a) * rnd()
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function lerpC(a: Color3, b: Color3, t: number): Color3
	return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
end
-- Разброс цвета (тон/насыщенность/яркость), чтобы массы не были однотонными.
local function jitter(c: Color3, amt: number): Color3
	local h, s, v = c:ToHSV()
	h = (h + rr(-0.012, 0.012) * amt) % 1
	s = math.clamp(s * (1 + rr(-0.12, 0.12) * amt), 0, 1)
	v = math.clamp(v * (1 + rr(-0.14, 0.14) * amt), 0, 1)
	return Color3.fromHSV(h, s, v)
end
local function randUnit(): Vector3
	local z = rr(-1, 1)
	local a = rr(0, math.pi * 2)
	local r = math.sqrt(1 - z * z)
	return V(r * math.cos(a), z, r * math.sin(a))
end
-- Случайный единичный вектор, перпендикулярный dir.
local function perpOf(dir: Vector3): Vector3
	for _ = 1, 8 do
		local r = randUnit()
		local p = r - dir * r:Dot(dir)
		if p.Magnitude > 0.2 then
			return p.Unit
		end
	end
	return V(1, 0, 0)
end
-- Палитра из 4 цветов (глубокая тень -> блик), t ∈ [0,1].
local function palAt(pal, t: number): Color3
	local idx = math.clamp(t * 3.0, 0, 2.999)
	local lo = math.floor(idx)
	return lerpC(pal[lo + 1], pal[lo + 2], idx - lo)
end

-- Направление НА солнце (как Presets.Park.sunDir; декорация не повёрнута — локальное = мировое).
local SUN = V(0.3, 0.7, -0.65).Unit

return function(B)
	local root = B.model
	local function group(name)
		return B:folder(name, root)
	end

	-- Цилиндр между двумя точками (локальные координаты).
	local function cylAB(a: Vector3, b: Vector3, d: number, color: Color3, material: string, parent, extra)
		local len = (b - a).Magnitude
		local mid = (a + b) * 0.5
		local dir = (b - a).Unit
		local cf
		if math.abs(dir.Y) > 0.995 then
			cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.pi / 2)
		else
			cf = lookAtFixed(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
		end
		local spec = { cf = cf, size = V(len, d, d), shape = "Cylinder", color = color, material = material, parent = parent }
		for k, v in extra or {} do
			spec[k] = v
		end
		return B:part(spec)
	end

	---------------------------------------------------------------------------
	-- ЗЕМЛЯ (Terrain)
	---------------------------------------------------------------------------
	-- Газон: верх ровно на Y=0 (границы кратны 4 — сетке вокселей).
	B:terrain("Block", V(0, -6, 100), V(800, 12, 800), "Grass")
	-- Дорожка вдоль изгороди (Pavement — без травинок декорации). Верх объёма на +0.02, чтобы в превью
	-- не мерцала с газоном; в Roblox это просто замена материала верхнего слоя вокселей.
	B:terrain("Block", V(0, -3.99, 22), V(800, 8.02, 4), "Pavement")
	-- Полоса под изгородью (тёмная, без травинок).
	B:terrain("Block", V(0, -3.98, 26), V(272, 8.04, 4), "LeafyGrass")
	-- Боковая дорожка влево-назад.
	B:terrain("Block", V(142, -3.99, 90), V(4, 8.02, 132), "Pavement")
	-- Цвета материалов Terrain — сочная весенняя трава как в клипе (у Roblox по умолчанию тускло-оливковая).
	-- Grass/LeafyGrass больше нигде не используются; Pavement задаёт Beach (почти тот же светло-серый).
	root:SetAttribute("TerrainColor_Grass", hex("7da83c"))
	root:SetAttribute("TerrainColor_LeafyGrass", hex("4f6a2a"))
	do
		local scr = roblox.Instance.new("Script")
		scr.Name = "ParkTerrainColors"
		scr.Source = [[
-- Цвета материалов Terrain для парка: атрибуты TerrainColor_<Material> модели Park.
local model = script.Parent
for name, value in model:GetAttributes() do
	local m = string.match(name, "^TerrainColor_(%w+)$")
	if m and typeof(value) == "Color3" then
		pcall(function()
			workspace.Terrain:SetMaterialColor((Enum.Material :: any)[m], value)
		end)
	end
end
]]
		scr.Parent = root
	end

	---------------------------------------------------------------------------
	-- ДЕРЕВЬЯ
	---------------------------------------------------------------------------
	local treesFolder = group("Trees")

	-- Палитры листвы (глубокая тень -> тень -> свет -> блик). По кадрам S08/S09.
	local PAL = {
		dark = { hex("1b2419"), hex("273321"), hex("3b482f"), hex("5e6a40") }, -- тёмная липа/бук
		fresh = { hex("4a6326"), hex("6c8a32"), hex("93ad48"), hex("b9cc6e") }, -- яркая молодая листва
		lime = { hex("343a11"), hex("4e541d"), hex("6a702e"), hex("8b8e46") }, -- жёлто-зелёное деревце (контровой свет)
		mid = { hex("223620"), hex("33502a"), hex("4b6a38"), hex("6a874f") }, -- обычная зелень
		pale = { hex("9a9a62"), hex("b7b47c"), hex("cfc996"), hex("e1dcb0") }, -- ранневесенняя кремовая (берёза/ясень)
	}

	local HAZE = hex("aebca8") -- цвет воздушной дымки (Atmosphere пресета добавляет основную)
	local BARK = {
		dark = hex("3a342f"),
		brown = hex("564a3f"),
		grey = hex("5e574f"),
		pale = hex("6d665d"),
		lime = hex("4b443c"),
	}
	local TWIG = hex("8b857c") -- тонкие веточки ранневесенних деревьев (светлые на фоне неба)

	-- Лиственное дерево. Вся листва — Ball LeafyGrass (на SpecialMesh Roblox не показывает текстуру).
	-- Плотная крона («dense»): на оболочке эллипсоида кроны — равномерно (по спирали Фибоначчи) центры
	-- «масс» листвы; каждая масса — 2–4 перекрывающихся шара (сверху светлее, снизу темнее); снаружи —
	-- мелкие шарики-«кончики» (рваный край). Внутри — крупные тёмные ядра (в просветах не видно неба насквозь).
	-- Скелетные ветви идут от развилки и заканчиваются ВНУТРИ масс (ничего не торчит).
	-- Сквозная крона («sparse»): видимое рекурсивное ветвление, мелкие пучки листвы на концах.
	-- o: x, z, crown = {rx, ry, rz}, cy, fork, trunkD, bark, pal, flat (срез низа 0..1), lean = {x,z}
	--    dense: masses, massR, balls ({min,max} шаров в массе), limbs, branchy, core, sparkle
	--    sparse: limbs, depth, limbLen, limbMin/limbMax, spreadMin/spreadMax, fork3, minD, tuft, clump, extra, twig
	local function tree(o)
		local f = B:folder(o.name or "Tree", treesFolder)
		local rx, ry, rz = o.crown[1], o.crown[2], o.crown[3]
		local lean = o.lean or { rr(-0.6, 0.6), rr(-0.6, 0.6) }
		local C = V(o.x + lean[1] * 2, o.cy, o.z + lean[2] * 2)
		local F = V(o.x + lean[1], o.fork, o.z + lean[2])
		local barkC = o.bark
		local td = o.trunkD
		local leafMat = "LeafyGrass"
		local barkMat = "Wood"
		local pal = o.pal
		local flat = o.flat or 0.6
		-- направление ниже среза flat переносится на кольцо среза (низ кроны плоский и открытый)
		local function clampFlat(u: Vector3, lo: number): Vector3
			if u.Y >= -lo then
				return u
			end
			local hz = V(u.X, 0, u.Z)
			hz = if hz.Magnitude > 1e-3 then hz.Unit else V(1, 0, 0)
			local ny = -lo + rr(-0.05, 0.12)
			return hz * math.sqrt(1 - ny * ny) + V(0, ny, 0)
		end
		local function crownPt(u: Vector3, s: number): Vector3
			return C + V(u.X * rx * s, u.Y * ry * s, u.Z * rz * s)
		end
		local function bark()
			return jitter(barkC, 0.3)
		end
		-- оттенок по положению в кроне: 0 — глубокая тень, 1 — блик
		local function shade(p: Vector3): number
			local d = p - C
			local nrm = V(d.X / rx, d.Y / ry, d.Z / rz)
			local m = nrm.Magnitude
			nrm = if m > 1e-3 then nrm / m else V(0, 1, 0)
			local hf = math.clamp((p.Y - (C.Y - ry)) / (2 * ry), 0, 1)
			return 0.12 + 0.38 * hf + 0.38 * math.max(0, nrm:Dot(SUN)) + 0.25 * math.clamp(m - 0.5, 0, 0.5)
		end
		local function palColor(t: number): Color3
			return palAt(pal, t)
		end
		local function leaf(p: Vector3, d: number, c: Color3, name: string, noShadow: boolean?)
			if p.Y - d * 0.4 < 1.5 then
				return
			end
			B:ball(p, d * rr(0.9, 1.1), c, leafMat, { parent = f, name = name, castShadow = not noShadow })
		end

		-- корни-наплывы (4 наклонных цилиндра расходятся от ствола в землю) + ствол из 3 сегментов с изломом
		-- и сужением; шары в стыках не толще более толстого из соседних цилиндров (без «бамбуковых» узлов)
		local nr = o.roots or 4
		local ra = rr(0, math.pi * 2)
		for i = 1, nr do
			local a = ra + (i - 1) / nr * math.pi * 2 + rr(-0.35, 0.35)
			local dir = V(math.cos(a), 0, math.sin(a))
			local top = V(o.x, td * rr(0.6, 0.8), o.z) + dir * td * 0.15
			local foot = V(o.x, -0.45, o.z) + dir * td * rr(1.0, 1.25)
			cylAB(top, foot, td * 0.34, bark(), barkMat, f, { name = "Root" })
		end
		local p0 = V(o.x, -0.3, o.z)
		local k1 = V(o.x + lean[1] * 0.3 + rr(-0.2, 0.2), o.fork * 0.42, o.z + lean[2] * 0.3 + rr(-0.2, 0.2))
		local k2 = V(o.x + lean[1] * 0.7 + rr(-0.25, 0.25), o.fork * 0.76, o.z + lean[2] * 0.7 + rr(-0.25, 0.25))
		cylAB(p0, k1, td, barkC, barkMat, f, { name = "Trunk" })
		B:ball(k1, td * 0.93, barkC, barkMat, { parent = f, name = "TrunkJoint" })
		cylAB(k1, k2, td * 0.9, barkC, barkMat, f, { name = "Trunk" })
		B:ball(k2, td * 0.83, barkC, barkMat, { parent = f, name = "TrunkJoint" })
		cylAB(k2, F, td * 0.8, barkC, barkMat, f, { name = "Trunk" })
		B:ball(F, td * 0.8, barkC, barkMat, { parent = f, name = "Fork" })

		if not o.sparse then
			-- центры масс по спирали Фибоначчи на оболочке; ниже среза flat — кольцом по краю среза
			-- (низ кроны плоский и открытый: снизу видны тёмные ядра и ветви, а не шар до земли)
			local N = o.masses
			local centers = {}
			local ga = math.pi * (3 - math.sqrt(5))
			local off = rr(0, 6.28)
			for i = 0, N - 1 do
				local y = 1 - (i + 0.5) / N * 2
				local r = math.sqrt(1 - y * y)
				local a = i * ga + off
				local u = V(math.cos(a) * r, y, math.sin(a) * r)
				u = clampFlat(u, flat)
				u = (u + randUnit() * 0.12).Unit
				table.insert(centers, { crownPt(u, rr(0.66, 0.8)), u })
			end
			-- скелетные ветви к нижним/средним массам (заканчиваются внутри массы)
			local cand = {}
			for _, cpt in centers do
				if cpt[2].Y > -0.25 and cpt[2].Y < 0.6 then
					table.insert(cand, cpt)
				end
			end
			local limbs = math.min(o.limbs or 5, #cand)
			local step = #cand / limbs
			for i = 1, limbs do
				local cpt = cand[math.floor((i - 1) * step + rr(0, step * 0.8)) + 1]
				local T = F:Lerp(cpt[1], 0.86)
				-- сначала вверх (внутри кроны), потом наружу к массе — снизу видны только ствол и развилка
				local M = V(F.X, 0, F.Z):Lerp(V(T.X, 0, T.Z), rr(0.12, 0.25)) + V(0, F.Y + (C.Y - F.Y) * rr(0.55, 0.8), 0)
				cylAB(F, M, td * 0.58, bark(), barkMat, f, { name = "Limb" })
				B:ball(M, td * 0.5, barkC, barkMat, { parent = f, name = "LimbJoint" })
				cylAB(M, T, td * 0.42, bark(), barkMat, f, { name = "Limb" })
				-- открытая крона: от середины ветви тонкие веточки к соседним массам (видны в просветах)
				for _ = 1, (o.branchy or 0) do
					local other = centers[math.floor(rnd() * #centers) + 1]
					if other[2].Y > -0.3 and (other[1] - T).Magnitude < (rx + ry) * 0.9 then
						local P = M:Lerp(T, rr(0.3, 0.7))
						cylAB(P, P:Lerp(other[1], 0.85), td * 0.2, bark(), barkMat, f, { name = "Branch" })
					end
				end
			end
			cylAB(F, crownPt(V(0, 1, 0), 0.45), td * 0.5, barkC, barkMat, f, { name = "Leader" })
			-- тёмные ядра (внутри кроны — без теней)
			for _ = 1, (o.core or 0) do
				local u = randUnit()
				local p = crownPt(V(u.X, u.Y * 0.5 + 0.1, u.Z), rr(0.05, 0.3))
				local d = math.min(rx, rz) * rr(0.9, 1.1)
				leaf(p, d, jitter(lerpC(pal[1], pal[2], 0.35), 0.4), "LeafCore", true)
			end
			-- массы листвы
			local mR = o.massR
			local bmin, bmax = o.balls[1], o.balls[2]
			for _, cpt in centers do
				local mc, mu = cpt[1], cpt[2]
				local base = shade(mc) + rr(-0.08, 0.08)
				local nb = math.floor(rr(bmin, bmax + 0.999))
				for j = 1, nb do
					local u = randUnit()
					-- первый шар — центральный, остальные вокруг, чуть наружу и вверх
					local p = if j == 1 then mc else mc + (u + mu * 0.5 + V(0, 0.25, 0)).Unit * mR * rr(0.4, 0.65)
					local up = math.clamp((p - mc).Y / mR, -1, 1)
					local c = jitter(palColor(math.clamp(base + up * 0.16 + rr(-0.05, 0.05), 0, 1)), 0.5)
					leaf(p, mR * (if j == 1 then rr(1.15, 1.35) else rr(0.7, 1.0)), c, "Leaves")
				end
			end
			-- рваный солнечный край: мелкие шарики снаружи оболочки
			for _ = 1, (o.sparkle or 0) do
				local u = clampFlat((randUnit() + SUN * 0.4 + V(0, 0.3, 0)).Unit, flat * 0.85)
				local p = crownPt(u, rr(0.86, 0.98))
				leaf(p, mR * rr(0.32, 0.5), jitter(palColor(math.clamp(shade(p) + 0.15, 0, 1)), 0.5), "LeafTip", true)
			end
			return
		end

		-- сквозная крона: рекурсивное ветвление
		local tips = {}
		local segs = {} -- верхние сегменты ветвей (для дополнительных пучков вдоль них)
		local depthMax = o.depth or 3
		local twigC = o.twig
		local function grow(p: Vector3, dir: Vector3, len: number, d: number, depth: number)
			local e = p + dir * len
			if depth >= depthMax - 1 then
				table.insert(segs, { p, e })
			end
			local col = if twigC and depth >= 2 then jitter(twigC, 0.3) else bark()
			cylAB(p, e, d, col, barkMat, f, { name = if depth == 0 then "Limb" elseif depth < depthMax then "Branch" else "Twig", castShadow = d > 0.15 })
			if d > 0.4 then
				B:ball(e, d * 0.98, barkC, barkMat, { parent = f, name = "BranchJoint" })
			end
			if depth >= depthMax then
				table.insert(tips, e)
				return
			end
			local k = if rnd() < (o.fork3 or 0.3) then 3 else 2
			local p1 = perpOf(dir)
			local p2 = dir:Cross(p1).Unit
			local ph = rr(0, math.pi * 2)
			for c = 1, k do
				local ang = ph + (c - 1) / k * math.pi * 2 + rr(-0.4, 0.4)
				local th = math.rad(rr(o.spreadMin or 16, o.spreadMax or 30))
				local side = p1 * math.cos(ang) + p2 * math.sin(ang)
				local nd = (dir * math.cos(th) + side * math.sin(th) + V(0, 0.1, 0)).Unit
				grow(e, nd, len * rr(0.66, 0.8), math.max(d * (o.taper or 0.62), o.minD or 0.1), depth + 1)
			end
			if o.nodeTufts then
				table.insert(tips, e)
			end
		end
		-- ствол продолжается лидером, скелетные ветви отходят на разной высоте (не «взрыв» из одной точки)
		local LT = F:Lerp(C, 0.7) + V(rr(-0.5, 0.5), 0, rr(-0.5, 0.5))
		cylAB(F, LT, td * 0.62, barkC, barkMat, f, { name = "Leader" })
		local n = o.limbs
		local phase = rr(0, math.pi * 2)
		for i = 1, n do
			local a = phase + (i - 1) * 2.4 + rr(-0.3, 0.3) -- золотой угол
			local phi = math.rad(rr(o.limbMin or 22, o.limbMax or 45))
			local dir = V(math.cos(a) * math.sin(phi), math.cos(phi), math.sin(a) * math.sin(phi))
			local start = F:Lerp(LT, (i - 1) / n * 0.85)
			grow(start, dir, (o.limbLen or 0.5) * (rx + ry) * 0.5 * rr(0.85, 1.1) * (1 - 0.25 * (i - 1) / n), td * 0.46 * (1 - 0.3 * (i - 1) / n), 0)
		end
		grow(LT, V(rr(-0.15, 0.15), 1, rr(-0.15, 0.15)).Unit, (C.Y - LT.Y) + ry * 0.35, td * 0.4, 1)
		-- пучки листвы на концах и узлах ветвей + пучки вдоль верхних веточек
		local tuft = o.tuft or 2.4
		for _, e in tips do
			-- пучок: 1 шар (редкая крона) или «клумпа» из нескольких
			local base = shade(e) + rr(-0.1, 0.1)
			for j = 1, (o.clump or 1) do
				local q = if j == 1 then e + randUnit() * tuft * 0.2 else e + (randUnit() + V(0, 0.35, 0)).Unit * tuft * rr(0.45, 0.75)
				local up = math.clamp((q - e).Y / tuft, -1, 1)
				leaf(q, tuft * rr(0.7, 1.15) * (if j == 1 then 1 else 0.85), jitter(palColor(math.clamp(base + up * 0.15, 0, 1)), 0.5), "Leaves")
			end
		end
		-- пучки по оболочке кроны (спираль Фибоначчи, низ открыт срезом flat): связный силуэт, а внутри — ветви
		local NS = o.shell or 0
		if NS > 0 then
			local ga = math.pi * (3 - math.sqrt(5))
			local off = rr(0, 6.28)
			for i = 0, NS - 1 do
				local y = 1 - (i + 0.5) / NS * 2
				local r = math.sqrt(1 - y * y)
				local u = V(math.cos(i * ga + off) * r, y, math.sin(i * ga + off) * r)
				if u.Y > -(o.flat or 0.5) then
					u = (u + randUnit() * 0.15).Unit
					local p = crownPt(u, rr(0.72, 0.92))
					leaf(p, tuft * rr(0.8, 1.2), jitter(palColor(math.clamp(shade(p) + rr(-0.08, 0.08), 0, 1)), 0.5), "Leaves")
				end
			end
		end
		for _ = 1, (o.extra or 0) do
			local sg = segs[math.floor(rnd() * #segs) + 1]
			local p = sg[1]:Lerp(sg[2], rr(0.35, 0.95)) + randUnit() * tuft * 0.3
			leaf(p, tuft * rr(0.55, 1.0), jitter(palColor(math.clamp(shade(p) + rr(-0.1, 0.1), 0, 1)), 0.5), "Leaves", true)
		end
	end

	-- Дальнее дерево (фон): ствол + 7–9 шаров по полусфере кроны (вверху мельче и светлее), без теней.
	-- Дымку даёт Atmosphere пресета; здесь только лёгкий (≤5%) сдвиг к HAZE для самых дальних.
	local farFolder = B:folder("FarTrees", treesFolder)
	local function farTree(x: number, z: number, h: number, r: number, pal, n: number?, cyk: number?)
		local cy = h * (cyk or 0.58)
		cylAB(V(x, -0.3, z), V(x, cy, z), r * 0.13, BARK.dark, "Wood", farFolder, { name = "FarTrunk", castShadow = false })
		local haze = math.clamp((math.sqrt(x * x + z * z) - 200) / 2000, 0, 0.05)
		local tone = rr(0.05, 0.35)
		local k = n or 8
		-- центральная масса (крона без сквозных дыр)
		B:ball(V(x, cy, z), r * 1.35, lerpC(jitter(palAt(pal, tone), 0.4), HAZE, haze), "LeafyGrass", { parent = farFolder, name = "FarLeaves", castShadow = false })
		for _ = 2, k do
			local u = randUnit()
			u = V(u.X, math.abs(u.Y) * 1.3 - 0.4, u.Z)
			local up = math.clamp((u.Y + 0.4) / 1.3, 0, 1)
			local p = V(x + u.X * r * 0.72, cy + u.Y * r * 0.8, z + u.Z * r * 0.72)
			local d = r * rr(0.8, 1.2) * (1 - 0.3 * up)
			local c = lerpC(jitter(palAt(pal, math.clamp(tone + 0.45 * up + rr(-0.06, 0.06), 0, 1)), 0.5), HAZE, haze)
			B:ball(p, d, c, "LeafyGrass", { parent = farFolder, name = "FarLeaves", castShadow = false })
		end
	end

	-- Куст (нижний ярус за изгородью): 4–5 шаров.
	local bushFolder = B:folder("Bushes", treesFolder)
	local function bush(x: number, z: number, r: number, pal)
		local base = rr(0.25, 0.55)
		local nb = if rnd() < 0.5 then 4 else 5
		for i = 1, nb do
			local u = randUnit()
			local p = V(x + u.X * r * 0.7, r * 0.6 + math.abs(u.Y) * r * 0.35 + (if i == 1 then r * 0.2 else 0), z + u.Z * r * 0.6)
			local t = math.clamp(base + (p.Y / (r * 1.5)) * 0.3 + rr(-0.08, 0.08), 0, 1)
			B:ball(p, r * rr(1.1, 1.4) * (if i == 1 then 1.15 else 1), jitter(palAt(pal, t), 0.5), "LeafyGrass", { parent = bushFolder, name = "Bush" })
		end
	end

	-- Слева в кадре (+X): тёмная большая липа (крона до изгороди, два ствола видны под ней) и вторая за ней.
	tree({ name = "DarkLime", x = 26.5, z = 36, lean = { -0.4, 0.2 }, crown = { 14, 15, 12 }, cy = 19, fork = 8, trunkD = 2.0, bark = BARK.dark, pal = PAL.dark, flat = 0.64, masses = 85, massR = 2.4, balls = { 3, 4 }, limbs = 6, core = 5, sparkle = 36 })
	tree({ name = "DarkLime2", x = 25, z = 48, lean = { -0.3, 0.3 }, crown = { 9, 12, 8 }, cy = 16, fork = 6, trunkD = 1.4, bark = BARK.dark, pal = PAL.dark, flat = 0.7, masses = 40, massR = 2.4, balls = { 3, 4 }, limbs = 4, core = 2, sparkle = 16 })
	-- Центр (за конём): высокие ранневесенние деревья — тонкие веточки, редкие кремовые листочки, много неба.
	tree({ name = "PaleAsh1", x = 16, z = 62, crown = { 9, 11, 8 }, cy = 23, fork = 11, trunkD = 1.0, bark = BARK.pale, twig = TWIG, pal = PAL.pale, sparse = true, limbs = 4, depth = 4, fork3 = 0, limbLen = 0.62, limbMin = 12, limbMax = 32, spreadMin = 20, spreadMax = 38, taper = 0.7, minD = 0.06, tuft = 0.9, clump = 1, extra = 50 })
	tree({ name = "PaleAsh2", x = -1, z = 76, crown = { 17, 15, 13 }, cy = 35, fork = 15, trunkD = 1.4, bark = BARK.pale, twig = TWIG, pal = PAL.pale, sparse = true, limbs = 5, depth = 4, fork3 = 0, limbLen = 0.62, limbMin = 18, limbMax = 40, spreadMin = 20, spreadMax = 38, taper = 0.7, minD = 0.06, tuft = 1.1, clump = 1, extra = 110 })
	-- за правым плечом коня: маленькое яркое деревце
	tree({ name = "FreshAiry", x = -9, z = 52, crown = { 6, 6.5, 5 }, cy = 10.2, fork = 4, trunkD = 0.7, bark = BARK.grey, pal = PAL.fresh, flat = 0.7, masses = 34, massR = 1.5, balls = { 2, 3 }, limbs = 4, branchy = 2, core = 1, sparkle = 15 })
	-- Справа в кадре (-X): жёлто-зелёное молодое дерево перед изгородью (ствол виден до травы), рядом фонарь.
	tree({ name = "LimeYoung", x = -14.7, z = 23.6, lean = { 0.15, 0.25 }, crown = { 5.1, 4.8, 4.0 }, cy = 8.4, fork = 3.6, trunkD = 0.8, bark = BARK.lime, pal = PAL.lime, sparse = true, flat = 0.62, limbs = 6, depth = 3, fork3 = 0.2, limbLen = 0.6, limbMin = 30, limbMax = 64, spreadMin = 18, spreadMax = 34, minD = 0.08, tuft = 1.0, clump = 2, extra = 60, shell = 130 })
	-- второй ряд
	tree({ name = "Dark2", x = 56, z = 60, crown = { 14, 16, 12 }, cy = 28, fork = 15, flat = 0.8, trunkD = 2.1, bark = BARK.dark, pal = PAL.dark, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 4, core = 3, sparkle = 10 })
	tree({ name = "Mid3", x = 80, z = 32, crown = { 13, 14, 11 }, cy = 25, fork = 14, flat = 0.8, trunkD = 1.9, bark = BARK.brown, pal = PAL.mid, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 4, core = 3, sparkle = 10 })
	tree({ name = "Fresh2", x = -66, z = 60, crown = { 12, 13, 11 }, cy = 25, fork = 15, flat = 0.8, trunkD = 1.6, bark = BARK.brown, pal = PAL.fresh, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 4, core = 3, sparkle = 10 })
	tree({ name = "Mid4", x = -76, z = 36, crown = { 13, 14, 12 }, cy = 26, fork = 15, flat = 0.8, trunkD = 1.9, bark = BARK.brown, pal = PAL.mid, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 4, core = 3, sparkle = 10 })
	tree({ name = "Back1", x = 48, z = 100, crown = { 15, 17, 13 }, cy = 30, fork = 17, flat = 0.8, trunkD = 2.0, bark = BARK.dark, pal = PAL.mid, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 3, core = 3, sparkle = 10 })
	tree({ name = "Back2", x = -92, z = 98, crown = { 12, 13, 11 }, cy = 26, fork = 15, flat = 0.8, trunkD = 1.5, bark = BARK.grey, pal = PAL.lime, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 3, core = 2, sparkle = 10 })
	-- по бокам (для более широких ракурсов)
	tree({ name = "SideL", x = 100, z = 4, crown = { 14, 15, 12 }, cy = 28, fork = 16, flat = 0.8, trunkD = 2.0, bark = BARK.dark, pal = PAL.dark, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 3, core = 3, sparkle = 10 })
	tree({ name = "SideR", x = -100, z = 10, crown = { 13, 14, 12 }, cy = 26, fork = 15, flat = 0.8, trunkD = 1.8, bark = BARK.brown, pal = PAL.fresh, masses = 18, massR = 3.4, balls = { 2, 3 }, limbs = 3, core = 3, sparkle = 10 })

	-- дальний фон: слева — ряд деревьев, совсем далеко — сплошная полоса леса
	for i = 0, 8 do
		farTree(250 - i * 24 + rr(-6, 6), rr(150, 200), rr(34, 46), rr(9, 12), if rnd() < 0.5 then PAL.dark else PAL.mid, 8)
	end
	for i = 0, 16 do
		farTree(-330 + i * 40 + rr(-8, 8), rr(275, 320), rr(40, 54), rr(13, 17), if rnd() < 0.5 then PAL.dark else PAL.mid, 7)
	end
	for i = 0, 4 do
		farTree(rr(130, 200), 30 + i * 26 + rr(-5, 5), rr(36, 46), rr(9, 12), PAL.mid, 7)
		farTree(rr(-210, -160), -10 + i * 16 + rr(-4, 4), rr(36, 46), rr(9, 12), PAL.fresh, 7)
	end
	-- кольцо деревьев за спиной камеры (два ряда в шахматном порядке) и по бокам: горизонт закрыт
	for i = 0, 18 do
		farTree(-240 + i * 26 + rr(-5, 5), rr(-185, -165), rr(38, 50), rr(12, 16), if rnd() < 0.5 then PAL.dark else PAL.mid, 4, 0.5)
		farTree(-227 + i * 26 + rr(-5, 5), rr(-205, -190), rr(40, 52), rr(12, 16), if rnd() < 0.5 then PAL.dark else PAL.mid, 4, 0.52)
	end
	for i = 0, 8 do
		farTree(rr(250, 290), -150 + i * 35 + rr(-6, 6), rr(38, 50), rr(11, 15), PAL.mid, 6)
		farTree(rr(-290, -250), -150 + i * 35 + rr(-6, 6), rr(38, 50), rr(11, 15), PAL.dark, 6)
	end
	-- кусты за изгородью
	for _, b in { { 42, 46, 3.2, PAL.dark }, { 64, 44, 3.4, PAL.dark }, { 92, 50, 3.0, PAL.mid }, { -40, 50, 2.8, PAL.mid }, { -62, 46, 3.2, PAL.mid }, { -90, 52, 3.0, PAL.fresh }, { 48, 92, 3.4, PAL.dark }, { 74, 78, 3.6, PAL.mid } } do
		bush(b[1] + rr(-2, 2), b[2] + rr(-2, 2), b[3], b[4])
	end

	---------------------------------------------------------------------------
	-- ЖИВАЯ ИЗГОРОДЬ (стриженая, сплошная: тело LeafyGrass + скруглённые кромки, утопленные «подушки»
	-- на лицевой стороне, светлые побеги по верху, тёмные стебли у земли)
	---------------------------------------------------------------------------
	local hedgeFolder = group("Hedge")
	local HZ0, HZ1, HH = 24.4, 28.0, 2.75
	local hedgeBody = hex("3d401b")
	local hedgeTop = hex("666c2e")
	local hedgeDark = hex("20280f")
	local sprigC = hex("8d9a45")
	local stemC = hex("2a2418")
	local hx = -130
	local segI = 0
	while hx < 130 do
		segI += 1
		local len = rr(8.0, 11.0)
		local cx = hx + len / 2
		local near = math.abs(cx) < 50 -- в кадре S08/S09: детальнее
		-- соседние сегменты различаются высотой (±0.03) и выносом (±0.03) — нет совпадающих граней
		local odd = segI % 2 == 1
		local h = HH + (if odd then -0.03 else 0.03)
		local dz = (if odd then -0.03 else 0.03)
		local zc = (HZ0 + HZ1) / 2 + dz
		local f0 = HZ0 + dz -- лицевая плоскость сегмента
		local y0 = 0.4 + (if odd then 0.03 else 0) -- низ тела (под ним — тёмные стебли)
		local bh = 0.5 + (if odd then 0.04 else 0)
		B:box(V(cx, y0 + (h - y0) / 2, zc), V(len + 0.12, h - y0, HZ1 - HZ0), jitter(hedgeBody, 0.15), "LeafyGrass", nil, { parent = hedgeFolder, name = "HedgeBody" })
		B:box(V(cx, bh / 2 - 0.02 - (if odd then 0.03 else 0), zc + 0.15), V(len + 0.04, bh, HZ1 - HZ0 - 0.6), jitter(hedgeDark, 0.4), "LeafyGrass", nil, { parent = hedgeFolder, name = "HedgeBase", castShadow = false })
		-- скруглённые верхние кромки (спереди и сзади) — светлее, это солнечная «шапка»
		local ct = jitter(lerpC(hedgeBody, hedgeTop, 0.15), 0.12)
		local cd = if odd then 0.9 else 0.94
		B:cyl(V(cx, h - 0.32, f0 + 0.45), len + 0.1, cd, ct, "LeafyGrass", "X", nil, { parent = hedgeFolder, name = "HedgeEdge" })
		B:cyl(V(cx, h - 0.32, HZ1 + dz - 0.45), len + 0.1, cd, ct, "LeafyGrass", "X", nil, { parent = hedgeFolder, name = "HedgeEdge" })
		-- светлая «шапка» верха между кромками (солнечная стриженая поверхность; видна с высоких ракурсов)
		B:box(V(cx, h + 0.04, zc), V(len + 0.06 + (if odd then 0.02 else 0), 0.1, HZ1 - HZ0 - 0.9), jitter(lerpC(hedgeBody, hedgeTop, 0.65), 0.12), "LeafyGrass", nil, { parent = hedgeFolder, name = "HedgeCap", castShadow = false })
		-- шов между сегментами закрыт двумя «подушками» поверх стыка (сплошная изгородь без вертикальных линий)
		if hx > -129 then
			B:ball(V(hx + rr(-0.15, 0.15), rr(1.1, 1.5), f0 + 0.6), rr(1.35, 1.6), jitter(hedgeBody, 0.15), "LeafyGrass", { parent = hedgeFolder, name = "HedgeLump" })
			B:ball(V(hx + rr(-0.15, 0.15), rr(h - 0.75, h - 0.5), f0 + 0.6), rr(1.3, 1.5), jitter(lerpC(hedgeBody, hedgeTop, 0.15), 0.15), "LeafyGrass", { parent = hedgeFolder, name = "HedgeLump" })
		end
		-- «подушки» листвы: утоплены в лицевую сторону на 60–70%, цвет тела (вверху чуть светлее)
		local nl = if near then math.floor(len / 1.6) else math.floor(len / 3.2)
		for b = 1, nl do
			local bx = hx + (b - 0.5) * len / nl + rr(-0.4, 0.4)
			local by = rr(1.5, h - 0.7)
			local cb = lerpC(hedgeBody, hedgeTop, math.clamp((by - 1.2) / (h - 1.2) * 0.2 + rr(-0.08, 0.08), 0, 1))
			B:ball(V(bx, by, f0 + 0.6), rr(1.25, 1.6), jitter(cb, 0.2), "LeafyGrass", { parent = hedgeFolder, name = "HedgeLump" })
		end
		-- светлые побеги по верху (ближе к лицевой кромке — их видно снизу на силуэте)
		local ns = if near then math.floor(rr(4, 6.99)) else 2
		for _ = 1, ns do
			B:ball(V(rr(hx + 0.3, hx + len - 0.3), h + rr(-0.12, 0.08), rr(HZ0 + 0.3, HZ0 + 1.6)), rr(0.5, 0.8), jitter(lerpC(hedgeTop, sprigC, rr(0.1, 0.55)), 0.25), "LeafyGrass", { parent = hedgeFolder, name = "HedgeSprig", castShadow = false })
		end
		if rnd() < 0.5 then
			B:ball(V(rr(hx + 0.5, hx + len - 0.5), h + rr(-0.1, 0.1), rr(HZ0 + 1.6, HZ1 - 0.3)), rr(0.6, 0.9), jitter(lerpC(hedgeTop, sprigC, 0.5), 0.3), "LeafyGrass", { parent = hedgeFolder, name = "HedgeSprig", castShadow = false })
		end
		-- тёмные одревесневшие стебли у земли (видны под телом)
		if near then
			local nst = math.floor(rr(4, 6.99))
			for _ = 1, nst do
				B:box(V(rr(hx + 0.3, hx + len - 0.3), 0.35, HZ0 + 0.25 + rr(-0.05, 0.05)), V(0.12, 0.7, 0.12), jitter(stemC, 0.3), "Wood", V(rr(-8, 8), rr(0, 90), rr(-8, 8)), { parent = hedgeFolder, name = "HedgeStem", castShadow = false })
			end
		end
		hx += len
	end

	---------------------------------------------------------------------------
	-- ФОНАРИ, СКАМЕЙКА, УРНА
	---------------------------------------------------------------------------
	local props = group("Props")
	local poleC = hex("2f4f35")
	-- Тонкий зелёный фонарный столб высотой ≈10.6 (в S09 его верх теряется в кроне жёлто-зелёного дерева).
	local function lamp(lx: number, lz: number)
		local f = B:folder("LampPost", props)
		B:cyl(V(lx, 0.4, lz), 0.8, 0.7, poleC, "Metal", "Y", nil, { parent = f, name = "LampBase" })
		B:cyl(V(lx, 0.95, lz), 0.3, 0.5, poleC, "Metal", "Y", nil, { parent = f, name = "LampCollar" })
		B:cyl(V(lx, 5.0, lz), 8.0, 0.3, poleC, "Metal", "Y", nil, { parent = f, name = "LampPole" })
		B:cyl(V(lx, 9.09, lz), 0.38, 0.44, poleC, "Metal", "Y", nil, { parent = f, name = "LampCollar" })
		-- фонарь-«цилиндр»: матовое стекло + тёмная шляпка
		B:cyl(V(lx, 9.7, lz), 0.8, 0.8, hex("e9ebe4"), "Glass", "Y", nil, { parent = f, name = "LampGlass", transparency = 0.4 })
		B:cyl(V(lx, 10.26, lz), 0.3, 1.2, poleC, "Metal", "Y", nil, { parent = f, name = "LampCap" })
		B:cyl(V(lx, 10.49, lz), 0.16, 0.7, poleC, "Metal", "Y", nil, { parent = f, name = "LampCap" })
		local bulb = B:ball(V(lx, 9.7, lz), 0.4, hex("fff6dc"), "SmoothPlastic", { parent = f, name = "LampBulb", castShadow = false })
		B:light(bulb, "PointLight", { Brightness = 0.6, Range = 10, Color = hex("ffe8c0"), Enabled = false, Shadows = false })
	end
	lamp(-11.5, 22.8)
	lamp(44, 22.8)
	lamp(-78, 22.8)
	lamp(104, 22.8)

	-- Скамейка спинкой к изгороди, лицом в -Z. Центр сиденья (24, 1.45, 22.9). Урна — за дальним (+X) краем.
	do
		local f = B:folder("Bench", props)
		local bx, bz = 24, 22.9
		local wood = hex("8a5a36")
		local iron = hex("1d1f1f")
		for i = 0, 3 do
			B:box(V(bx, 1.42, bz - 0.75 + i * 0.5), V(5.6, 0.14, 0.4), jitter(wood, 0.4), "Wood", nil, { parent = f, name = "SeatSlat" })
		end
		for i = 0, 2 do
			B:box(V(bx, 2.0 + i * 0.48, bz + 0.98 + i * 0.07), V(5.6, 0.36, 0.13), jitter(wood, 0.4), "Wood", V(-12, 0, 0), { parent = f, name = "BackSlat" })
		end
		for _, sx in { -2.4, 2.4 } do
			B:box(V(bx + sx, 0.65, bz - 0.7), V(0.16, 1.3, 0.16), iron, "Metal", nil, { parent = f, name = "LegFront" })
			B:box(V(bx + sx, 1.25, bz + 0.85), V(0.16, 2.5, 0.16), iron, "Metal", V(-10, 0, 0), { parent = f, name = "LegBack" })
			B:box(V(bx + sx, 1.29, bz + 0.05), V(0.14, 0.14, 1.75), iron, "Metal", nil, { parent = f, name = "SeatRail" })
			B:box(V(bx + sx * 1.05, 2.05, bz - 0.1), V(0.14, 0.12, 1.6), iron, "Metal", nil, { parent = f, name = "Armrest" })
			B:box(V(bx + sx * 1.05, 1.72, bz - 0.78), V(0.12, 0.62, 0.12), iron, "Metal", nil, { parent = f, name = "ArmPost" })
		end
		B:cyl(V(bx + 4.3, 1.1, bz + 0.2), 2.2, 1.1, hex("2c3a30"), "Metal", "Y", nil, { parent = f, name = "Bin" })
		B:cyl(V(bx + 4.3, 2.25, bz + 0.2), 0.1, 1.2, hex("1e2620"), "Metal", "Y", nil, { parent = f, name = "BinRim" })
	end

	-- Пыльца/пух в солнечном воздухе над лужайкой (мягкие кружочки). В клипе её нет — эмиттер "ParkPollen"
	-- по умолчанию ВЫКЛЮЧЕН; план может включить/«выбросить» его эффектом (kind = "enable"/"emit").
	do
		-- объём начинается за зоной постановки (z ≥ 3), чтобы пылинки не пролетали у самого объектива
		local holder = B:part({ name = "PollenVolume", pos = V(0, 5.5, 13), size = V(50, 9, 20), transparency = 1, castShadow = false, canQuery = false, parent = props })
		local e = roblox.Instance.new("ParticleEmitter")
		e.Name = "ParkPollen"
		e.Enabled = false
		e.Texture = "rbxasset://textures/whiteCircle.png"
		e.Shape = roblox.Enum.ParticleEmitterShape.Box
		e.ShapeStyle = roblox.Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 4
		e.Lifetime = roblox.NumberRange.new(7, 10)
		e.Speed = roblox.NumberRange.new(0.15, 0.5)
		e.SpreadAngle = roblox.Vector2.new(180, 180)
		e.Acceleration = V(0.06, 0.015, 0.03)
		e.Drag = 0.4
		e.Size = roblox.NumberSequence.new({ roblox.NumberSequenceKeypoint.new(0, 0), roblox.NumberSequenceKeypoint.new(0.15, 0.06), roblox.NumberSequenceKeypoint.new(0.85, 0.05), roblox.NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = roblox.NumberSequence.new({ roblox.NumberSequenceKeypoint.new(0, 1), roblox.NumberSequenceKeypoint.new(0.2, 0.35), roblox.NumberSequenceKeypoint.new(0.8, 0.5), roblox.NumberSequenceKeypoint.new(1, 1) })
		e.Color = roblox.ColorSequence.new(hex("fffbe8"))
		e.LightEmission = 0.2
		e.LightInfluence = 1
		e.Parent = holder
	end

	---------------------------------------------------------------------------
	-- ОФИС (справа в кадре): почти чёрное стекло, ряды потолочных светильников, тонкие светлые пояса,
	-- тяжёлая чёрная кровля-козырёк. Строится в локальной системе ocf: X ∈ [-L, 0] (X=0 — торец к камере),
	-- Z ∈ [0, W] (Z=0 — главный фасад). Здание повёрнуто: фасад уходит вправо (-X) и К КАМЕРЕ, поэтому
	-- линия крыши в S09 поднимается к правому краю кадра.
	---------------------------------------------------------------------------
	local office = group("Office")
	do
		local L, W = 130, 40
		local ocf = CFrame.new(-40, 0, 175) * CFrame.Angles(0, math.rad(-45), 0)
		local function obox(p: Vector3, size: Vector3, color: Color3, mat: string, extra)
			local spec = { cf = ocf * CFrame.new(p), size = size, color = color, material = mat, parent = office }
			for k, v in extra or {} do
				spec[k] = v
			end
			return B:part(spec)
		end
		local FLOORS, FH = 4, 11
		local H = FLOORS * FH
		local glassC = hex("0f1412")
		local bandC = hex("7c807c")
		local mullC = hex("1c2022")
		local lightC = hex("dfe6e6")
		local cx, cz = -L / 2, W / 2
		local glassFx = { transparency = 0.3, reflectance = 0.05 }
		-- тёмный внутренний объём отступает от стекла на 3.2: в зазоре видны перекрытия и потолочные светильники
		obox(V((-L + 1.2 - 3.2) / 2, H / 2, (3.2 + W - 1.2) / 2), V(L - 4.4, H - 0.4, W - 4.4), hex("0a0c0b"), "SmoothPlastic", { name = "Interior" })
		obox(V(cx, (H - 0.05) / 2, 0), V(L, H - 0.05, 0.2), glassC, "Glass", { name = "GlassFront", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		obox(V(0, (H - 0.05) / 2, cz), V(0.2, H - 0.05, W - 0.4), glassC, "Glass", { name = "GlassEnd", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		obox(V(-L, (H - 0.05) / 2, cz), V(0.2, H - 0.05, W - 0.4), glassC, "Glass", { name = "GlassEnd", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		obox(V(cx, (H - 0.05) / 2, W), V(L - 0.4, H - 0.05, 0.2), glassC, "Glass", { name = "GlassBack", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		-- светильники под потолком каждого этажа (видны сквозь стекло) и пояса перекрытий
		local nlx = math.floor((L - 10) / 6)
		for k = 1, FLOORS do
			local y = k * FH
			for i = 0, nlx do
				obox(V(-L + 5 + i * ((L - 10) / nlx), y - 0.8, 1.8), V(2.6, 0.12, 0.9), lightC, "Neon", { name = "CeilingLight", castShadow = false })
			end
			for i = 0, 4 do
				obox(V(-1.8, y - 0.8, 4 + i * 8), V(0.9, 0.12, 2.6), lightC, "Neon", { name = "CeilingLight", castShadow = false })
			end
			if k < FLOORS then
				-- перекрытие (видно сквозь стекло) и тонкий светлый пояс снаружи
				obox(V((-L + 0.2 - 0.15) / 2, y, 1.75), V(L - 0.35, 0.7, 3.3), hex("2c3032"), "Concrete", { name = "Slab" })
				obox(V(-1.75, y + 0.01, cz + 1.6), V(3.3, 0.7, W - 3.6), hex("2c3032"), "Concrete", { name = "Slab" })
				obox(V(cx, y, -0.05), V(L + 0.8, 0.6, 0.8), bandC, "Concrete", { name = "Band" })
				obox(V(0.05, y + 0.02, cz), V(0.8, 0.6, W + 0.6), bandC, "Concrete", { name = "Band" })
				obox(V(-L - 0.05, y + 0.02, cz), V(0.8, 0.6, W + 0.6), bandC, "Concrete", { name = "Band" })
			end
		end
		obox(V(cx, 0.38, -0.1), V(L + 0.6, 0.8, 0.8), hex("8d8f8b"), "Concrete", { name = "Plinth" })
		-- импосты: фасад (шаг ≈8) и торец к камере
		local nm = math.floor(L / 8)
		for i = 1, nm - 1 do
			obox(V(-L + i * L / nm, H / 2 - 0.02, -0.2), V(0.3, H - 0.14, 0.3), mullC, "Metal", { name = "Mullion" })
		end
		local ns = math.floor(W / 8)
		for i = 1, ns - 1 do
			obox(V(0.2, H / 2 - 0.02, i * W / ns), V(0.3, H - 0.14, 0.3), mullC, "Metal", { name = "Mullion" })
		end
		obox(V(0.1, H / 2, -0.1), V(0.96, H - 0.12, 0.96), hex("1c2022"), "Metal", { name = "Corner" })
		obox(V(-L - 0.1, H / 2, -0.1), V(0.96, H - 0.12, 0.96), hex("1c2022"), "Metal", { name = "Corner" })
		-- тяжёлая чёрная кровля-козырёк: толщина 3, вынос 12 над фасадом и над торцом к камере; светлый софит снизу
		obox(V((-L - 1 + 12) / 2, H + 1.5, (-12 + W + 1) / 2), V(L + 13, 3.0, W + 13), hex("141617"), "SmoothPlastic", { name = "Roof" })
		obox(V((-L - 1 + 12) / 2, H - 0.12, -6), V(L + 12.6, 0.2, 11.6), hex("6a6d6b"), "Concrete", { name = "Soffit" })
		obox(V(6, H - 0.12 + 0.01, (W + 1) / 2), V(11.6, 0.2, W - 0.4), hex("6a6d6b"), "Concrete", { name = "Soffit" })
		obox(V(cx - 20, H + 4.55, cz + 4), V(22, 3.2, 12), hex("7f8383"), "Metal", { name = "RoofUnit" })
		obox(V(cx + 30, H + 4.15, cz + 2), V(14, 2.4, 10), hex("767a7a"), "Metal", { name = "RoofUnit" })
		-- изгородь у основания
		obox(V(cx, 1.6, -4), V(L, 3.2, 2.6), hex("3c4c24"), "LeafyGrass", { name = "BuildingHedge" })
	end

	-- Белое здание вдали слева (ленточные окна) — вне кадров S08/S09, для широких ракурсов.
	do
		local f = group("WhiteBuilding")
		local X0, X1, Z0, Z1 = 210, 380, 220, 262
		local FL, FH = 3, 10
		local H = FL * FH
		local cx, cz = (X0 + X1) / 2, (Z0 + Z1) / 2
		B:box(V(cx, H / 2, cz), V(X1 - X0, H, Z1 - Z0), hex("e3e2db"), "Concrete", nil, { parent = f, name = "Body" })
		for k = 0, FL - 1 do
			B:box(V(cx, k * FH + 5.2, Z0 - 0.1), V(X1 - X0 - 4, 4.2, 0.3), hex("2f3a40"), "Glass", nil, { parent = f, name = "Ribbon", reflectance = 0.2 })
			B:box(V(X0 - 0.1, k * FH + 5.2, cz), V(0.3, 4.2, Z1 - Z0 - 4), hex("2f3a40"), "Glass", nil, { parent = f, name = "Ribbon", reflectance = 0.2 })
		end
		for i = 0, 17 do
			B:box(V(X0 + 2 + i * (X1 - X0 - 4) / 17, H / 2, Z0 - 0.3), V(0.7, H, 0.5), hex("eeede6"), "Concrete", nil, { parent = f, name = "Pilaster" })
		end
		B:box(V(cx, H + 0.5, cz), V(X1 - X0 + 1.5, 1.0, Z1 - Z0 + 1.5), hex("cfcdc4"), "Concrete", nil, { parent = f, name = "Cornice" })
	end
end
