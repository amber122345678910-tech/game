--!nocheck
-- Декорация PARK (S08, S09): лужайка в городском парке, весна, яркое солнце.
-- Камера обычно в -Z и смотрит на +Z, поэтому +X — СЛЕВА в кадре, -X — справа.
--   * Terrain Grass 800x800 (верх Y=0), дорожка (Terrain Pavement) z∈[20,24] вдоль изгороди.
--   * Стриженая живая изгородь z∈[24.6,28.2], высота ≈2.8, x∈[-130,130].
--   * Деревья: слева в кадре (+X) тёмная большая липа и светлое молодое деревце, в центре редкие
--     светлые ранневесенние кроны, справа (-X) жёлто-зелёное деревце и фонарь; дальше ряды деревьев.
--   * Справа за деревьями (-X, z 140…186) — современный офис: тёмное стекло, светлые пояса, импосты,
--     нависающая чёрная кровля; слева вдали — белое здание с ленточными окнами.
--   * Фонари вдоль дорожки, скамейка и урна у изгороди (x≈+24).
-- Зона постановки вокруг (0,0,0) свободна (ближе z=+20 нет ничего, кроме травы).

local roblox = require("@lune/roblox")
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
			cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
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
	-- Боковая дорожка влево-назад к белому зданию.
	B:terrain("Block", V(140, -3.99, 90), V(4, 8.02, 132), "Pavement")
	-- Рекомендуемые цвета материалов Terrain (Terrain:SetMaterialColor) — сочная весенняя трава как в клипе.
	root:SetAttribute("TerrainColor_Grass", hex("7da83c"))
	root:SetAttribute("TerrainColor_LeafyGrass", hex("4f6a2a"))
	root:SetAttribute("TerrainColor_Pavement", hex("b9b7ae"))

	---------------------------------------------------------------------------
	-- ДЕРЕВЬЯ
	---------------------------------------------------------------------------
	local treesFolder = group("Trees")

	-- Палитры листвы (глубокая тень -> тень -> свет -> блик). По кадрам S08/S09.
	local PAL = {
		dark = { hex("182419"), hex("233424"), hex("354b35"), hex("52684a") }, -- тёмная липа/бук
		fresh = { hex("384c26"), hex("536a32"), hex("738946"), hex("94a468") }, -- молодая весенняя листва
		lime = { hex("434d24"), hex("5f6a34"), hex("7e8846"), hex("9fa466") }, -- жёлто-зелёное деревце
		mid = { hex("223620"), hex("33502a"), hex("4b6a38"), hex("6a874f") }, -- обычная зелень
		pale = { hex("737c48"), hex("959a60"), hex("b2b27e"), hex("cac79c") }, -- ранневесенняя (ясень/берёза)
	}

	local HAZE = hex("b4c2c0") -- цвет воздушной дымки для дальнего плана
	local BARK = {
		dark = hex("3a342f"),
		brown = hex("564a3f"),
		grey = hex("5e574f"),
		light = hex("4f4943"),
	}

	-- Лиственное дерево.
	-- Плотная крона («dense»): на оболочке эллипсоида кроны — равномерно (по спирали Фибоначчи) центры
	-- «масс» листвы; каждая масса — 4–6 перекрывающихся шаров/эллипсоидов (сверху светлее, снизу темнее);
	-- скелетные ветви идут от развилки и заканчиваются ВНУТРИ масс (ничего не торчит). Внутри — тёмные ядра.
	-- Сквозная крона («sparse»): видимое рекурсивное ветвление, мелкие пучки листвы на концах.
	-- o: x, z, crown = {rx, ry, rz}, cy, fork, trunkD, bark, pal, flat (срез низа 0..1), lean = {x,z}
	--    dense: masses (число масс), massR (радиус массы), balls ({min,max} шаров в массе), limbs, core, sparkle
	--    sparse: limbs, depth, limbLen, limbMin/limbMax, minD, tuft (диаметр пучка), extra (доп. пучки по оболочке)
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
			local idx = math.clamp(t * 3.0, 0, 2.999)
			local lo = math.floor(idx)
			return lerpC(pal[lo + 1], pal[lo + 2], idx - lo)
		end
		local leafFx = { parent = f, transparency = o.leafTr or 0 }
		local function blob(p: Vector3, d: number, c: Color3, name: string)
			if p.Y - d * 0.4 < 1.5 then
				return
			end
			leafFx.name = name
			if rnd() < 0.55 then
				B:ellipsoid(p, V(d * rr(1.05, 1.3), d * rr(0.72, 0.9), d * rr(1.0, 1.2)), c, leafMat, V(rr(-12, 12), rr(0, 180), rr(-12, 12)), leafFx)
			else
				B:ball(p, d, c, leafMat, leafFx)
			end
		end

		-- корневой наплыв + ствол (3 сегмента с изломом и сужением; шары скрывают стыки)
		B:ellipsoid(V(o.x, 0.15, o.z), V(td * 1.9, 1.4, td * 1.9), barkC, barkMat, V(0, rr(0, 90), 0), { parent = f, name = "Flare" })
		local p0 = V(o.x, -0.3, o.z)
		local k1 = V(o.x + lean[1] * 0.3 + rr(-0.2, 0.2), o.fork * 0.42, o.z + lean[2] * 0.3 + rr(-0.2, 0.2))
		local k2 = V(o.x + lean[1] * 0.7 + rr(-0.25, 0.25), o.fork * 0.76, o.z + lean[2] * 0.7 + rr(-0.25, 0.25))
		cylAB(p0, k1, td, barkC, barkMat, f, { name = "Trunk" })
		B:ball(k1, td * 0.97, barkC, barkMat, { parent = f, name = "TrunkJoint" })
		cylAB(k1, k2, td * 0.9, barkC, barkMat, f, { name = "Trunk" })
		B:ball(k2, td * 0.88, barkC, barkMat, { parent = f, name = "TrunkJoint" })
		cylAB(k2, F, td * 0.8, barkC, barkMat, f, { name = "Trunk" })
		B:ball(F, td * 0.82, barkC, barkMat, { parent = f, name = "Fork" })

		if not o.sparse then
			-- центры масс по спирали Фибоначчи на оболочке
			local N = o.masses
			local centers = {}
			local ga = math.pi * (3 - math.sqrt(5))
			local off = rr(0, 6.28)
			for i = 0, N - 1 do
				local y = 1 - (i + 0.5) / N * 2
				local r = math.sqrt(1 - y * y)
				local a = i * ga + off
				local u = V(math.cos(a) * r, y, math.sin(a) * r)
				if u.Y < -flat then
					u = V(u.X, -flat + rr(0, 0.1), u.Z).Unit
				end
				u = (u + randUnit() * 0.12).Unit
				table.insert(centers, { crownPt(u, rr(0.66, 0.78)), u })
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
				B:ball(M, td * 0.56, barkC, barkMat, { parent = f, name = "LimbJoint" })
				cylAB(M, T, td * 0.42, bark(), barkMat, f, { name = "Limb" })
			end
			cylAB(F, crownPt(V(0, 1, 0), 0.45), td * 0.5, barkC, barkMat, f, { name = "Leader" })
			-- тёмные ядра
			for _ = 1, (o.core or 0) do
				local u = randUnit()
				local p = crownPt(V(u.X, u.Y * 0.6, u.Z), rr(0.05, 0.3))
				local d = math.min(rx, rz) * rr(0.9, 1.1)
				B:ellipsoid(p, V(d * 1.1, d * 1.05, d * 1.05), jitter(lerpC(pal[1], pal[2], 0.35), 0.4), leafMat, V(0, rr(0, 180), 0), { parent = f, name = "LeafCore" })
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
					local p = if j == 1 then mc else mc + (u + mu * 0.5 + V(0, 0.25, 0)).Unit * mR * rr(0.35, 0.6)
					local up = math.clamp((p - mc).Y / mR, -1, 1)
					local c = jitter(palColor(math.clamp(base + up * 0.16 + rr(-0.05, 0.05), 0, 1)), 0.5)
					blob(p, mR * (if j == 1 then rr(1.15, 1.35) else rr(0.75, 1.05)), c, "Leaves")
				end
			end
			-- кружевной солнечный край
			for _ = 1, (o.sparkle or 0) do
				local u = (randUnit() + SUN * 0.5 + V(0, 0.5, 0)).Unit
				local p = crownPt(u, rr(0.95, 1.06))
				blob(p, mR * rr(0.35, 0.55), jitter(palColor(math.clamp(shade(p) + 0.2, 0, 1)), 0.5), "LeafTip")
			end
			return
		end

		-- сквозная крона: рекурсивное ветвление
		local tips = {}
		local segs = {} -- верхние сегменты ветвей (для дополнительных пучков вдоль них)
		local depthMax = o.depth or 3
		local function grow(p: Vector3, dir: Vector3, len: number, d: number, depth: number)
			local e = p + dir * len
			if depth >= depthMax - 1 then
				table.insert(segs, { p, e })
			end
			cylAB(p, e, d, bark(), barkMat, f, { name = if depth == 0 then "Limb" elseif depth < depthMax then "Branch" else "Twig" })
			if d > 0.4 then
				B:ball(e, d * 0.96, barkC, barkMat, { parent = f, name = "BranchJoint" })
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
				local th = math.rad(rr(18, 34))
				local side = p1 * math.cos(ang) + p2 * math.sin(ang)
				local nd = (dir * math.cos(th) + side * math.sin(th) + V(0, 0.1, 0)).Unit
				grow(e, nd, len * rr(0.66, 0.8), math.max(d * 0.66, o.minD or 0.1), depth + 1)
			end
			if o.nodeTufts then
				table.insert(tips, e)
			end
		end
		local n = o.limbs
		local phase = rr(0, math.pi * 2)
		for i = 1, n do
			local a = phase + (i - 1) / n * math.pi * 2 + rr(-0.3, 0.3)
			local phi = math.rad(rr(o.limbMin or 22, o.limbMax or 45))
			local dir = V(math.cos(a) * math.sin(phi), math.cos(phi), math.sin(a) * math.sin(phi))
			grow(F, dir, (o.limbLen or 0.5) * (rx + ry) * 0.5 * rr(0.85, 1.1), td * 0.5, 0)
		end
		grow(F, V(rr(-0.1, 0.1), 1, rr(-0.1, 0.1)).Unit, (C.Y - F.Y) * 0.8, td * 0.45, 1)
		-- пучки листвы на концах и узлах ветвей + редкие пучки по оболочке
		local tuft = o.tuft or 2.4
		for _, e in tips do
			blob(e + randUnit() * tuft * 0.2, tuft * rr(0.7, 1.2), jitter(palColor(math.clamp(shade(e) + rr(-0.1, 0.1), 0, 1)), 0.5), "Leaves")
		end
		for _ = 1, (o.extra or 0) do
			local sg = segs[math.floor(rnd() * #segs) + 1]
			local p = sg[1]:Lerp(sg[2], rr(0.35, 0.9)) + randUnit() * tuft * 0.25
			blob(p, tuft * rr(0.55, 1.0), jitter(palColor(math.clamp(shade(p) + rr(-0.1, 0.1), 0, 1)), 0.5), "Leaves")
		end
	end

	-- Дальнее дерево (фон): короткий ствол + крупные массы почти до земли (сливаются в сплошную полосу), без теней.
	local farFolder = B:folder("FarTrees", treesFolder)
	local function farTree(x: number, z: number, h: number, r: number, pal, n: number?)
		cylAB(V(x, -0.3, z), V(x, h * 0.35, z), r * 0.16, BARK.dark, "Wood", farFolder, { name = "FarTrunk", castShadow = false })
		local haze = math.clamp((z - 120) / 600, 0.08, 0.35)
		local base = lerpC(jitter(lerpC(pal[2], pal[3], rr(0.1, 0.5)), 0.8), HAZE, haze)
		B:ellipsoid(V(x, h * 0.55, z), V(r * 2.1, h * 0.72, r * 1.9), base, "LeafyGrass", V(0, rr(0, 180), 0), { parent = farFolder, name = "FarLeaves", castShadow = false })
		for _ = 1, (n or 3) - 1 do
			local u = randUnit()
			local p = V(x + u.X * r * 0.6, h * 0.62 + math.abs(u.Y) * h * 0.18, z + u.Z * r * 0.5)
			local c = lerpC(jitter(lerpC(pal[2], pal[4], rr(0.2, 0.6)), 0.6), HAZE, haze)
			B:ellipsoid(p, V(r * 1.3, r * rr(1.1, 1.5), r * 1.2), c, "LeafyGrass", V(0, rr(0, 180), 0), { parent = farFolder, name = "FarLeaves", castShadow = false })
		end
	end

	-- Кусты за изгородью (между стволами) — сочный нижний ярус.
	local bushFolder = B:folder("Bushes", treesFolder)
	local function bush(x: number, z: number, r: number, pal)
		local base = rr(0.25, 0.6)
		for i = 1, 3 do
			local u = randUnit()
			local p = V(x + u.X * r * 0.6, r * 0.55 + math.abs(u.Y) * r * 0.35 + (if i == 1 then r * 0.15 else 0), z + u.Z * r * 0.5)
			local t = math.clamp(base + (p.Y / (r * 1.5)) * 0.3 + rr(-0.08, 0.08), 0, 1)
			local idx = math.clamp(t * 3, 0, 2.999)
			local lo = math.floor(idx)
			B:ellipsoid(p, V(r * rr(1.3, 1.7), r * rr(1.0, 1.25), r * rr(1.2, 1.5)), jitter(lerpC(pal[lo + 1], pal[lo + 2], idx - lo), 0.5), "LeafyGrass", V(0, rr(0, 180), 0), { parent = bushFolder, name = "Bush" })
		end
	end

	-- Слева в кадре (+X): тёмная большая липа (низкая плотная крона до изгороди) и светлое деревце перед ней.
	tree({ name = "DarkLime", x = 31, z = 37, crown = { 15, 21, 13 }, cy = 28, fork = 12, trunkD = 2.3, bark = BARK.dark, pal = PAL.dark, flat = 0.95, masses = 30, massR = 5.2, balls = { 4, 5 }, limbs = 6, core = 4, sparkle = 8 })
	tree({ name = "FreshAiry", x = 17, z = 47, crown = { 10, 11, 9 }, cy = 21, fork = 9, trunkD = 1.1, bark = BARK.grey, pal = PAL.fresh, sparse = true, limbs = 5, depth = 3, fork3 = 0, limbLen = 0.55, minD = 0.1, tuft = 2.6, extra = 40, leafTr = 0.1 })
	-- Центр (за конём): крупные светлые ранневесенние кроны со сквозными ветвями.
	tree({ name = "PaleAsh1", x = 6, z = 58, crown = { 15, 18, 12 }, cy = 32, fork = 12, trunkD = 1.6, bark = BARK.light, pal = PAL.pale, sparse = true, limbs = 5, depth = 3, fork3 = 0, limbLen = 0.55, minD = 0.1, tuft = 2.3, extra = 36, leafTr = 0.15 })
	tree({ name = "PaleAsh2", x = -12, z = 76, crown = { 14, 17, 12 }, cy = 31, fork = 12, trunkD = 1.5, bark = BARK.grey, pal = PAL.pale, sparse = true, limbs = 5, depth = 2, fork3 = 0.4, limbLen = 0.7, minD = 0.12, tuft = 2.5, extra = 32, leafTr = 0.15 })
	-- Справа в кадре (-X): жёлто-зелёное деревце (рядом фонарь), за ним офис.
	tree({ name = "LimeYoung", x = -27, z = 40, crown = { 11, 13, 10 }, cy = 22, fork = 12, trunkD = 1.3, bark = BARK.grey, pal = PAL.lime, flat = 0.7, masses = 24, massR = 3.8, balls = { 4, 5 }, limbs = 6, core = 2, sparkle = 8 })
	-- второй ряд
	tree({ name = "Dark2", x = 56, z = 60, crown = { 14, 16, 12 }, cy = 28, fork = 15, flat = 0.85, trunkD = 2.1, bark = BARK.dark, pal = PAL.dark, masses = 16, massR = 6, balls = { 2, 3 }, limbs = 4, core = 3 })
	tree({ name = "Mid3", x = 80, z = 32, crown = { 13, 14, 11 }, cy = 25, fork = 14, flat = 0.85, trunkD = 1.9, bark = BARK.brown, pal = PAL.mid, masses = 14, massR = 6, balls = { 2, 3 }, limbs = 4, core = 3 })
	tree({ name = "Fresh2", x = -50, z = 64, crown = { 12, 13, 11 }, cy = 25, fork = 15, flat = 0.85, trunkD = 1.6, bark = BARK.brown, pal = PAL.fresh, masses = 14, massR = 5.5, balls = { 2, 3 }, limbs = 4, core = 3 })
	tree({ name = "Mid4", x = -76, z = 36, crown = { 13, 14, 12 }, cy = 26, fork = 15, flat = 0.85, trunkD = 1.9, bark = BARK.brown, pal = PAL.mid, masses = 14, massR = 6, balls = { 2, 3 }, limbs = 4, core = 3 })
	tree({ name = "Back1", x = 26, z = 104, crown = { 15, 17, 13 }, cy = 30, fork = 17, flat = 0.85, trunkD = 2.0, bark = BARK.dark, pal = PAL.mid, masses = 12, massR = 7, balls = { 2, 2 }, limbs = 3, core = 3 })
	tree({ name = "Back2", x = -36, z = 108, crown = { 12, 13, 11 }, cy = 26, fork = 15, flat = 0.85, trunkD = 1.5, bark = BARK.grey, pal = PAL.lime, masses = 12, massR = 6, balls = { 2, 2 }, limbs = 3, core = 2 })
	-- по бокам (для более широких ракурсов)
	tree({ name = "SideL", x = 100, z = 4, crown = { 14, 15, 12 }, cy = 28, fork = 16, flat = 0.85, trunkD = 2.0, bark = BARK.dark, pal = PAL.dark, masses = 12, massR = 7, balls = { 2, 2 }, limbs = 3, core = 3 })
	tree({ name = "SideR", x = -100, z = 10, crown = { 13, 14, 12 }, cy = 26, fork = 15, flat = 0.85, trunkD = 1.8, bark = BARK.brown, pal = PAL.fresh, masses = 12, massR = 7, balls = { 2, 2 }, limbs = 3, core = 3 })

	-- дальний фон: деревья закрывают горизонт (кроме места, где стоит офис)
	for i = 0, 11 do
		local x = 250 - i * 24 + rr(-6, 6)
		if x > -30 then
			farTree(x, rr(150, 200), rr(34, 46), rr(9, 12), if rnd() < 0.5 then PAL.dark else PAL.mid)
		end
	end
	for i = 0, 16 do
		farTree(-330 + i * 40 + rr(-8, 8), rr(275, 320), rr(40, 54), rr(13, 17), if rnd() < 0.5 then PAL.dark else PAL.mid, 2)
	end
	for i = 0, 4 do
		farTree(rr(130, 200), 30 + i * 26 + rr(-5, 5), rr(36, 46), rr(9, 12), PAL.mid, 3)
		farTree(rr(-200, -130), 0 + i * 24 + rr(-5, 5), rr(36, 46), rr(9, 12), PAL.fresh, 3)
	end
	-- кусты за изгородью
	for _, b in { { 40, 46, 3.2, PAL.dark }, { 22, 52, 2.6, PAL.mid }, { 64, 44, 3.4, PAL.dark }, { 92, 50, 3.0, PAL.mid }, { -8, 46, 2.4, PAL.fresh }, { -40, 50, 2.8, PAL.fresh }, { -62, 46, 3.2, PAL.mid }, { -90, 52, 3.0, PAL.fresh }, { 8, 96, 3.6, PAL.mid }, { 48, 92, 3.4, PAL.dark }, { -20, 120, 3.4, PAL.mid }, { 74, 78, 3.6, PAL.mid } } do
		bush(b[1] + rr(-2, 2), b[2] + rr(-2, 2), b[3], b[4])
	end

	---------------------------------------------------------------------------
	-- ЖИВАЯ ИЗГОРОДЬ
	---------------------------------------------------------------------------
	local hedgeFolder = group("Hedge")
	local HZ0, HZ1, HH = 24.6, 28.2, 2.8
	local hedgeBody = hex("2d3a19")
	local hedgeTop = hex("435222")
	local hedgeDark = hex("1a2312")
	local hx = -130
	local segI = 0
	while hx < 130 do
		segI += 1
		local len = rr(5.0, 6.8)
		local cx = hx + len / 2
		local h = HH + (if segI % 2 == 0 then 0.05 else -0.05) + rr(-0.08, 0.08)
		local dz = (if segI % 2 == 0 then 0.03 else -0.03) + rr(-0.05, 0.05)
		local yaw = rr(-0.4, 0.4)
		local zc = (HZ0 + HZ1) / 2 + dz
		-- тело (низ утоплен и темнее — «стебли» в тени), скруглённый верх-«подушка»
		B:box(V(cx, 0.4 + (h - 0.4) / 2, zc), V(len, h - 0.4, HZ1 - HZ0), jitter(hedgeBody, 0.5), "LeafyGrass", V(0, yaw, 0), { parent = hedgeFolder, name = "HedgeBody" })
		B:box(V(cx, 0.25, zc + 0.12), V(len, 0.5, HZ1 - HZ0 - 0.5), jitter(hedgeDark, 0.6), "LeafyGrass", V(0, yaw, 0), { parent = hedgeFolder, name = "HedgeBase", castShadow = false })
		B:ellipsoid(V(cx, h, zc), V(len * 1.14, 0.7, HZ1 - HZ0 + 0.12), jitter(hedgeTop, 0.5), "LeafyGrass", V(0, yaw, 0), { parent = hedgeFolder, name = "HedgeTop" })
		-- пологие «подушки» листвы на лицевой стороне и на верху (неровность стрижки)
		local nb = if rnd() < 0.5 then 1 else 2
		for b = 1, nb do
			local bx = hx + (b - 0.5) * len / nb + rr(-0.8, 0.8)
			local by = rr(1.1, h - 0.8)
			local w = rr(2.4, 3.6)
			local cb = lerpC(hedgeBody, hedgeTop, math.clamp(by / h * 0.6 + rr(-0.1, 0.1), 0, 1))
			B:ellipsoid(V(bx, by, HZ0 + dz + 0.3), V(w, w * rr(0.55, 0.75), 1.0), jitter(cb, 0.35), "LeafyGrass", V(0, 0, rr(-20, 20)), { parent = hedgeFolder, name = "HedgeLump" })
		end
		if rnd() < 0.6 then
			local w = rr(1.6, 2.8)
			B:ellipsoid(V(cx + rr(-1.5, 1.5), h + 0.18, zc + rr(-0.6, 0.6)), V(w, 0.55, w * 0.8), jitter(hedgeTop, 0.4), "LeafyGrass", V(0, rr(0, 180), 0), { parent = hedgeFolder, name = "HedgeLump" })
		end
		hx += len
	end

	---------------------------------------------------------------------------
	-- ФОНАРИ, СКАМЕЙКА, УРНА
	---------------------------------------------------------------------------
	local props = group("Props")
	local poleC = hex("27332b")
	local function lamp(lx: number, lz: number)
		local f = B:folder("LampPost", props)
		B:cyl(V(lx, 0.4, lz), 0.8, 0.75, poleC, "Metal", "Y", nil, { parent = f, name = "LampBase" })
		B:cyl(V(lx, 0.95, lz), 0.3, 0.55, poleC, "Metal", "Y", nil, { parent = f, name = "LampCollar" })
		B:cyl(V(lx, 7.0, lz), 12.0, 0.36, poleC, "Metal", "Y", nil, { parent = f, name = "LampPole" })
		B:cyl(V(lx, 13.1, lz), 0.4, 0.5, poleC, "Metal", "Y", nil, { parent = f, name = "LampCollar" })
		-- фонарь-«цилиндр»: матовое стекло + тёмная шляпка
		B:cyl(V(lx, 13.95, lz), 1.3, 1.0, hex("e9ebe4"), "Glass", "Y", nil, { parent = f, name = "LampGlass", transparency = 0.15 })
		B:cyl(V(lx, 14.75, lz), 0.3, 1.5, poleC, "Metal", "Y", nil, { parent = f, name = "LampCap" })
		B:cyl(V(lx, 14.98, lz), 0.18, 0.9, poleC, "Metal", "Y", nil, { parent = f, name = "LampCap" })
		local bulb = B:ball(V(lx, 13.9, lz), 0.5, hex("fff6dc"), "SmoothPlastic", { parent = f, name = "LampBulb", castShadow = false })
		B:light(bulb, "PointLight", { Brightness = 0.6, Range = 10, Color = hex("ffe8c0"), Enabled = false, Shadows = false })
	end
	lamp(-17.5, 24.25)
	lamp(44, 24.25)
	lamp(-78, 24.25)
	lamp(104, 24.25)

	-- Скамейка спинкой к изгороди, лицом в -Z. Центр сиденья (24, 1.45, 22.9).
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
		B:cyl(V(bx - 4.3, 1.1, bz + 0.2), 2.2, 1.1, hex("2c3a30"), "Metal", "Y", nil, { parent = f, name = "Bin" })
		B:cyl(V(bx - 4.3, 2.25, bz + 0.2), 0.1, 1.2, hex("1e2620"), "Metal", "Y", nil, { parent = f, name = "BinRim" })
	end

	---------------------------------------------------------------------------
	-- ОФИС (справа в кадре): тёмное стекло, светлые междуэтажные пояса, импосты, чёрная кровля-козырёк
	---------------------------------------------------------------------------
	local office = group("Office")
	do
		local X0, X1, Z0, Z1 = -236, -36, 140, 186 -- X1 — торец, обращённый к камере
		local FLOORS, FH = 4, 11
		local H = FLOORS * FH
		local glassC = hex("1f2b2c")
		local bandC = hex("c9ccc6")
		local mullC = hex("34393b")
		local lightC = hex("dfe6e6")
		local cx, cz = (X0 + X1) / 2, (Z0 + Z1) / 2
		local glassFx = { transparency = 0.3, reflectance = 0.28 }
		B:box(V(cx, H / 2, cz), V(X1 - X0 - 2.4, H - 0.4, Z1 - Z0 - 2.4), hex("161b1d"), "SmoothPlastic", nil, { parent = office, name = "Interior" })
		B:box(V(cx, H / 2, Z0), V(X1 - X0, H, 0.2), glassC, "Glass", nil, { parent = office, name = "GlassFront", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		B:box(V(X1, H / 2, cz), V(0.2, H, Z1 - Z0 - 0.4), glassC, "Glass", nil, { parent = office, name = "GlassEnd", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		B:box(V(X0, H / 2, cz), V(0.2, H, Z1 - Z0 - 0.4), glassC, "Glass", nil, { parent = office, name = "GlassEnd", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		B:box(V(cx, H / 2, Z1), V(X1 - X0 - 0.4, H, 0.2), glassC, "Glass", nil, { parent = office, name = "GlassBack", transparency = glassFx.transparency, reflectance = glassFx.reflectance })
		-- светильники под потолком каждого этажа (видны сквозь стекло) и пояса перекрытий
		for k = 1, FLOORS do
			local y = k * FH
			for i = 0, 21 do
				local lx = X0 + 5 + i * ((X1 - X0 - 10) / 21)
				B:box(V(lx, y - 0.8, Z0 + 1.8), V(2.6, 0.12, 0.9), lightC, "Neon", nil, { parent = office, name = "CeilingLight", castShadow = false })
			end
			for i = 0, 4 do
				B:box(V(X1 - 1.8, y - 0.8, Z0 + 6 + i * 8), V(0.9, 0.12, 2.6), lightC, "Neon", nil, { parent = office, name = "CeilingLight", castShadow = false })
			end
			if k < FLOORS then
				B:box(V(cx, y, Z0 - 0.05), V(X1 - X0 + 0.9, 1.1, 0.8), bandC, "Concrete", nil, { parent = office, name = "Band" })
				B:box(V(X1 + 0.05, y + 0.02, cz), V(0.8, 1.1, Z1 - Z0 + 0.6), bandC, "Concrete", nil, { parent = office, name = "Band" })
				B:box(V(X0 - 0.05, y + 0.02, cz), V(0.8, 1.1, Z1 - Z0 + 0.6), bandC, "Concrete", nil, { parent = office, name = "Band" })
			end
		end
		B:box(V(cx, 0.4, Z0 - 0.1), V(X1 - X0 + 0.6, 0.8, 0.8), hex("8d8f8b"), "Concrete", nil, { parent = office, name = "Plinth" })
		-- импосты: фасад (шаг ≈4) и торец к камере
		local nm = math.floor((X1 - X0) / 4)
		for i = 1, nm - 1 do
			B:box(V(X0 + i * (X1 - X0) / nm, H / 2, Z0 - 0.2), V(0.28, H, 0.3), mullC, "Metal", nil, { parent = office, name = "Mullion" })
		end
		local ns = math.floor((Z1 - Z0) / 4)
		for i = 1, ns - 1 do
			B:box(V(X1 + 0.2, H / 2, Z0 + i * (Z1 - Z0) / ns), V(0.3, H, 0.28), mullC, "Metal", nil, { parent = office, name = "Mullion" })
		end
		B:box(V(X1 + 0.1, H / 2, Z0 - 0.1), V(0.9, H, 0.9), hex("2c3033"), "Metal", nil, { parent = office, name = "Corner" })
		B:box(V(X0 - 0.1, H / 2, Z0 - 0.1), V(0.9, H, 0.9), hex("2c3033"), "Metal", nil, { parent = office, name = "Corner" })
		-- плоская кровля с козырьком
		B:box(V(cx, H + 0.75, cz - 1.5), V(X1 - X0 + 6, 1.5, Z1 - Z0 + 3), hex("17191b"), "SmoothPlastic", nil, { parent = office, name = "Roof" })
		B:box(V(cx, H + 1.7, cz - 1.5), V(X1 - X0 + 5.4, 0.4, Z1 - Z0 + 2.4), hex("2b2e30"), "Concrete", nil, { parent = office, name = "Parapet" })
		B:box(V(cx + 30, H + 3.6, cz + 4), V(22, 3.6, 12), hex("9fa3a3"), "Metal", nil, { parent = office, name = "RoofUnit" })
		B:box(V(cx - 40, H + 3.1, cz + 2), V(14, 2.6, 10), hex("8e9292"), "Metal", nil, { parent = office, name = "RoofUnit" })
		-- изгородь у основания
		B:box(V(cx, 1.6, Z0 - 4), V(X1 - X0, 3.2, 2.6), hex("3c4c24"), "LeafyGrass", nil, { parent = office, name = "BuildingHedge" })
	end

	-- Белое здание вдали слева (ленточные окна)
	do
		local f = group("WhiteBuilding")
		local X0, X1, Z0, Z1 = 110, 280, 220, 262
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
