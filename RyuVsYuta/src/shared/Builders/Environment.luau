--!strict
-- Окружение катсцены «Рю против Юты»: колония Сэндай, район стадиона после «Гранитного взрыва».
-- Собирается кодом (Lune при сборке места): Environment.build() -> Model "Environment".
--
-- Что внутри (папки модели):
--   Ground      — пустошь вокруг, растрескавшаяся асфальтовая парковка/площадь, улицы, бордюры, разметка;
--   RyuMound    — обрушенное здание-курган на краю площадки, на его плите "RyuSlab" стоит Рю;
--   Buildings   — разрушенные дома 4–14 этажей «коробками»: перекрытия, колонны, пояса с проёмами окон,
--                 висящие плиты, арматура; дальние — упрощённые; за спиной Рю всё срыто до 1–2 этажей;
--   Props       — фонари парковки, столбы с провисшими проводами (Beam), разбитые машины, знаки, деревья;
--   Debris      — воронки (кольца вздыбленных плит), поля обломков, трещины;
--   Clouds      — кучевые облака кольцом вдали; за спиной Рю (-Z) — огромный клубящийся столб дыма;
--   FogEmitters — невидимые детали с ParticleEmitter (атрибуты BaseRate и Layer: bank/ground/high/sky).
--
-- Раскладка (студы, Y вверх, земля Y=0) — на неё опирается хореография, не менять:
--   * коридор ходьбы X[-14,14], Z[-10,130]: ничего выше 0.6 (только разметка, трещины, мелкая крошка);
--   * плита Рю "RyuSlab": верх ровно Y=30, X[-20,20], Z[-134,-108]; Рю стоит в (0,30,-120) лицом к +Z;
--   * из низкой камеры кадра B (0,31.2,-111) за Рю (на -Z, вверх) видно только небо и облака:
--     всё, что в этом конусе дальше плиты, ниже линии её края (см. skyLimit).
-- Всё случайное — из детерминированного ГПСЧ (MathX.rng), сборка воспроизводима.

local MathX = require(script.Parent.Parent.Math)
local Textures = require(script.Parent.Parent.Textures)

type Rng = MathX.Rng

type Ctx = {
	rng: Rng,
	parts: number,
	layerEmitters: { [string]: number }, -- эмиттеров тумана по слоям
	layerLive: { [string]: number }, -- живых частиц по слоям (Rate * средняя жизнь)
}

local Environment = {}

local STOREY = 10 -- высота этажа (персонаж ~6 студов)
local MAXP = 2048 -- предел размера детали по оси
local SLAB_TOP = 30
local RYU_CAM = Vector3.new(0, 31.2, -111) -- низкая камера кадра B

-- Публичные числа раскладки (для интегратора / проверок)
Environment.layout = {
	slabTop = SLAB_TOP,
	slabCenter = Vector3.new(0, SLAB_TOP - 0.8, -121),
	slabSize = Vector3.new(40, 1.6, 26),
	corridor = { x0 = -14, x1 = 14, z0 = -10, z1 = 130, maxHeight = 0.6 },
	ryuStand = Vector3.new(0, SLAB_TOP, -120),
}

------------------------------------------------------------------------------------------
-- Цвета
------------------------------------------------------------------------------------------

local function hex(h: string): Color3
	local s = string.gsub(h, "#", "")
	local r = tonumber(string.sub(s, 1, 2), 16) or 0
	local g = tonumber(string.sub(s, 3, 4), 16) or 0
	local b = tonumber(string.sub(s, 5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

local function mix(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local C = {
	concrete = hex("#8A8C96"),
	concreteLight = hex("#9EA0AA"),
	concreteDark = hex("#74767F"),
	concreteViolet = hex("#8B8898"), -- сиреневатый бетон парковочных палуб
	asphalt = hex("#4A4C55"),
	asphaltLot = hex("#4D5264"), -- сине-серый асфальт площадки
	asphaltPatch = hex("#585C6C"),
	dust = hex("#B9B6C4"),
	rust = hex("#6B4A3A"),
	crack = hex("#26272E"),
	scorch = hex("#34353F"),
	paint = hex("#D3C8A8"), -- бежевая разметка парковки
	paintWhite = hex("#D4D5DC"),
	interior = hex("#4C4E59"), -- тёмное нутро: проёмы окон читаются тёмными
	waste = hex("#7E7C88"), -- пустошь: пыль и щебень
	cable = hex("#15161B"),
	metal = hex("#5C5F68"),
	metalLight = hex("#8E929C"),
	glass = hex("#2A2D37"),
	tire = hex("#1E1F24"),
	leaf0 = hex("#3E5249"),
	leaf1 = hex("#4D6357"),
	trunk = hex("#4A4040"),
	-- облака / дым (палитра кадра B + бриф)
	cloudLit = hex("#F4F6FF"),
	cloudHi = hex("#E0EDF7"),
	cloudMid = hex("#C9D2E6"),
	cloudMid2 = hex("#B4BEDE"),
	cloudShade = hex("#8E9BC0"),
	cloudDeep = hex("#6E7AA0"),
}

local CONCRETES = { C.concrete, C.concreteLight, C.concreteDark, C.concrete, C.dust }

------------------------------------------------------------------------------------------
-- Детали
------------------------------------------------------------------------------------------

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function setup(ctx: Ctx, p: BasePart, parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material)
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = Vector3.new(math.clamp(size.X, 0.05, MAXP), math.clamp(size.Y, 0.05, MAXP), math.clamp(size.Z, 0.05, MAXP))
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	ctx.parts += 1
end

local function box(ctx: Ctx, parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	setup(ctx, p, parent, name or "Block", cf, size, color, mat or Enum.Material.Concrete)
	return p
end

-- Клин: скат поднимается к +Z (высокая сторона сзади)
local function wedge(ctx: Ctx, parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, name: string?): WedgePart
	local p = Instance.new("WedgePart")
	setup(ctx, p, parent, name or "Wedge", cf, size, color, mat or Enum.Material.Concrete)
	return p
end

-- Цилиндр: ось — локальная X детали
local function cylinder(ctx: Ctx, parent: Instance, cf: CFrame, length: number, diameter: number, color: Color3, mat: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	setup(ctx, p, parent, name or "Cylinder", cf, Vector3.new(length, diameter, diameter), color, mat or Enum.Material.Concrete)
	return p
end

-- Стержень/столб от точки a до точки b
local function rod(ctx: Ctx, parent: Instance, a: Vector3, b: Vector3, diameter: number, color: Color3, mat: Enum.Material?, name: string?): Part
	return cylinder(ctx, parent, MathX.axisX((a + b) / 2, b - a), (b - a).Magnitude, diameter, color, mat, name)
end

-- Эллипсоид, вписанный в коробку size
local function ellipsoid(ctx: Ctx, parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	setup(ctx, p, parent, name or "Ellipsoid", cf, size, color, mat or Enum.Material.SmoothPlastic)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Плоский диск на земле (вертикальный цилиндр)
local function disk(ctx: Ctx, parent: Instance, pos: Vector3, diameter: number, thick: number, color: Color3, mat: Enum.Material?, name: string?): Part
	local p = cylinder(ctx, parent, CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), thick, diameter, color, mat, name)
	p.CastShadow = false
	return p
end

local function pick<T>(rng: Rng, list: { T }): T
	return list[math.clamp(rng:int(1, #list), 1, #list)]
end

local function randomRot(rng: Rng, tilt: number): CFrame
	return CFrame.Angles(rng:range(-tilt, tilt), rng:range(0, math.pi * 2), rng:range(-tilt, tilt))
end

------------------------------------------------------------------------------------------
-- Ограничение высоты за спиной Рю
------------------------------------------------------------------------------------------

-- Предельная высота построек в точке (x, z): из камеры кадра B (смотрит на -Z, низ кадра ~ -5°) всё,
-- что дальше плиты Рю и попадает в кадр (с запасом по углу), должно быть ниже линии края плиты.
local function skyLimit(x: number, z: number): number
	local dz = RYU_CAM.Z - z
	if z > -126 or dz <= 0 then
		return math.huge
	end
	if math.abs(x) > dz * 1.3 + 14 then
		return math.huge -- вне кадра B / sky_minusZ
	end
	local d = math.sqrt(x * x + dz * dz)
	return math.max(0, 29.5 - d * 0.05)
end

-- Минимум skyLimit по углам и центру прямоугольника (в осях cf)
local function areaLimit(cf: CFrame, x0: number, x1: number, z0: number, z1: number): number
	local lim = math.huge
	local pts = { { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 }, { (x0 + x1) / 2, (z0 + z1) / 2 } }
	for _, q in pts do
		local p = cf * Vector3.new(q[1], 0, q[2])
		lim = math.min(lim, skyLimit(p.X, p.Z))
	end
	return lim
end

-- Свободен ли коридор ходьбы в точке (с запасом)
local function inCorridor(x: number, z: number, margin: number): boolean
	return math.abs(x) < 14 + margin and z > -10 - margin and z < 130 + margin
end

------------------------------------------------------------------------------------------
-- Обломки, арматура
------------------------------------------------------------------------------------------

-- Случайный обломок бетона (блок или клин), повёрнут и утоплен в землю/кучу
local function chunk(ctx: Ctx, parent: Instance, pos: Vector3, s: number, tilt: number?): BasePart
	local rng = ctx.rng
	local size = Vector3.new(s * rng:range(0.6, 1.4), s * rng:range(0.3, 0.8), s * rng:range(0.6, 1.4))
	local cf = CFrame.new(pos) * randomRot(rng, tilt or 0.6)
	local col = mix(pick(rng, CONCRETES), C.concreteDark, rng:range(0, 0.3))
	local mat = if rng:next() < 0.7 then Enum.Material.Concrete else Enum.Material.Slate
	if rng:next() < 0.35 then
		return wedge(ctx, parent, cf, size, col, mat, "Chunk")
	end
	return box(ctx, parent, cf, size, col, mat, "Chunk")
end

-- Плоская крошка (для коридора: верх не выше maxTop)
local function chip(ctx: Ctx, parent: Instance, x: number, z: number, maxTop: number)
	local rng = ctx.rng
	local sx, sz = rng:range(0.4, 1.6), rng:range(0.4, 1.4)
	local sy = rng:range(0.15, math.min(0.4, maxTop))
	local tilt = math.rad(rng:range(-6, 6))
	-- верхняя точка наклонённой плитки ~ sy/2 + sx/2*sin(tilt)
	local top = sy / 2 + math.abs(math.sin(tilt)) * sx / 2
	local y = math.min(sy / 2 - 0.05, maxTop - top)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, rng:range(0, math.pi * 2), tilt)
	local p = box(ctx, parent, cf, Vector3.new(sx, sy, sz), mix(pick(ctx.rng, CONCRETES), C.dust, rng:range(0, 0.4)), Enum.Material.Concrete, "Chip")
	p.CastShadow = false
end

-- Пучок арматуры, торчащей из точки p в направлении dir (ржавые прутки, слегка разведённые)
local function rebarFan(ctx: Ctx, parent: Instance, p: Vector3, dir: Vector3, n: number, len: number, spread: Vector3?)
	local rng = ctx.rng
	local side = spread or Vector3.new(0, 0, 1)
	for i = 1, n do
		local off = side * rng:range(-1, 1) + Vector3.new(0, rng:range(-0.25, 0.25), 0)
		local d = (dir.Unit + Vector3.new(rng:range(-0.35, 0.35), rng:range(-0.45, 0.25), rng:range(-0.35, 0.35))).Unit
		local a = p + off
		local l = len * rng:range(0.5, 1.2)
		local mid = a + d * l * 0.6
		-- прут с изгибом: два отрезка
		local bend = (d + Vector3.new(rng:range(-0.4, 0.4), rng:range(-0.6, 0.1), rng:range(-0.4, 0.4))).Unit
		rod(ctx, parent, a - d * 0.3, mid, 0.18, C.rust, Enum.Material.CorrodedMetal, "Rebar")
		if i % 2 == 1 then
			rod(ctx, parent, mid, mid + bend * l * 0.5, 0.16, C.rust, Enum.Material.CorrodedMetal, "Rebar")
		end
	end
end

------------------------------------------------------------------------------------------
-- Земля, площадка, разметка, трещины
------------------------------------------------------------------------------------------

local LOT = { x0 = -80, x1 = 80, z0 = -200, z1 = 240 }

local function buildGround(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "Ground")
	-- пустошь 3x3 плиты по 2048 (облака стоят до ~2600 от центра)
	for i = -1, 1 do
		for j = -1, 1 do
			local p = box(ctx, f, CFrame.new(i * 2040, -1.07, 40 + j * 2040), Vector3.new(2048, 2, 2048), C.waste, Enum.Material.Concrete, "Wasteland")
			p.CastShadow = false
			p.CanCollide = true
		end
	end
	-- площадка (парковка): сине-серый асфальт, верх ровно Y=0
	local lot = box(
		ctx,
		f,
		CFrame.new((LOT.x0 + LOT.x1) / 2, -0.5, (LOT.z0 + LOT.z1) / 2),
		Vector3.new(LOT.x1 - LOT.x0, 1, LOT.z1 - LOT.z0),
		C.asphaltLot,
		Enum.Material.Asphalt,
		"ParkingLot"
	)
	lot.CastShadow = false
	lot.CanCollide = true
	-- улицы по краям площадки (вдоль Z) и поперечные (вдоль X)
	for _, sx in { -1, 1 } do
		local road = box(ctx, f, CFrame.new(sx * 91, -0.52, 50), Vector3.new(22, 1, 940), C.asphalt, Enum.Material.Asphalt, "Street")
		road.CastShadow = false
		-- тротуар вдоль домов
		local walk = box(ctx, f, CFrame.new(sx * 104, -0.3, 50), Vector3.new(4.4, 1, 940), C.concreteLight, Enum.Material.Pavement, "Sidewalk")
		walk.CastShadow = false
		-- бордюр площадки, местами выбит
		local z = LOT.z0
		while z < LOT.z1 do
			local len = rng:range(30, 90)
			local z1 = math.min(LOT.z1, z + len)
			if z1 - z > 4 then
				box(ctx, f, CFrame.new(sx * 80.4, 0.25, (z + z1) / 2), Vector3.new(0.9, 0.7, z1 - z), C.concreteLight, Enum.Material.Concrete, "Kerb")
			end
			z = z1 + rng:range(4, 14)
		end
		-- осевая разметка улицы (выцветшая)
		local zz = -380
		while zz < 500 do
			local len = rng:range(40, 120)
			local m = box(ctx, f, CFrame.new(sx * 91, 0.0, zz + len / 2), Vector3.new(0.35, 0.05, len), C.paintWhite, Enum.Material.SmoothPlastic, "LaneLine")
			m.Transparency = 0.45
			m.CastShadow = false
			zz += len + rng:range(15, 50)
		end
	end
	for _, zc in { 251, -232 } do
		local road = box(ctx, f, CFrame.new(0, -0.51, zc), Vector3.new(840, 1, 22), C.asphalt, Enum.Material.Asphalt, "CrossStreet")
		road.CastShadow = false
		local m = box(ctx, f, CFrame.new(0, 0.0, zc), Vector3.new(700, 0.05, 0.35), C.paintWhite, Enum.Material.SmoothPlastic, "LaneLine")
		m.Transparency = 0.5
		m.CastShadow = false
	end
	-- заплатки асфальта и пыльные наносы
	for _ = 1, 9 do
		local x = rng:range(-70, 70)
		local z = rng:range(-60, 230)
		local p = box(
			ctx,
			f,
			CFrame.new(x, 0.005, z) * CFrame.Angles(0, rng:range(-0.2, 0.2), 0),
			Vector3.new(rng:range(6, 22), 0.05, rng:range(6, 26)),
			C.asphaltPatch,
			Enum.Material.Asphalt,
			"Patch"
		)
		p.CastShadow = false
	end
	for _ = 1, 10 do
		local x = rng:range(-75, 75)
		local z = rng:range(-90, 235)
		local p = box(
			ctx,
			f,
			CFrame.new(x, 0.015, z) * CFrame.Angles(0, rng:range(0, math.pi), 0),
			Vector3.new(rng:range(8, 26), 0.05, rng:range(5, 14)),
			C.dust,
			Enum.Material.Concrete,
			"DustDrift"
		)
		p.Transparency = 0.45
		p.CastShadow = false
	end
end

-- Разметка парковки: бежевые двойные линии с закруглённым (U) концом у проезда
local function buildParkingLines(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "ParkingLines")
	local function paint(cf: CFrame, size: Vector3, tr: number)
		local p = box(ctx, f, cf, size, C.paint, Enum.Material.SmoothPlastic, "Paint")
		p.Transparency = tr
		p.CastShadow = false
	end
	for _, sx in { -1, 1 } do
		-- внутренний ряд: места поперёк, от проезда |x|=16 до |x|=33
		local x0, x1 = 16.5, 33
		local z = -22 + (if sx > 0 then 0 else 4.2)
		while z < 168 do
			if rng:next() > 0.18 then
				local tr = rng:range(0.2, 0.5)
				local len = (x1 - x0) * rng:range(0.75, 1)
				local xc = sx * (x0 + len / 2)
				for _, dz in { -0.4, 0.4 } do
					paint(CFrame.new(xc, 0.01, z + dz), Vector3.new(len, 0.05, 0.2), tr)
				end
				local cap = disk(ctx, f, Vector3.new(sx * x0, 0.01, z), 1.0, 0.05, C.paint, Enum.Material.SmoothPlastic, "PaintCap")
				cap.Transparency = tr
			end
			z += 8.5
		end
		-- задняя линия ряда
		paint(CFrame.new(sx * 33.2, 0.01, 72), Vector3.new(0.25, 0.05, 186), 0.35)
		-- внешний ряд (|x| 50..67): одиночные линии
		z = -10
		while z < 200 do
			if rng:next() > 0.3 then
				paint(CFrame.new(sx * 58.5, 0.01, z), Vector3.new(17 * rng:range(0.7, 1), 0.05, 0.28), rng:range(0.3, 0.55))
			end
			z += 8.5
		end
	end
	-- стрелки направления в проезде (выцветшие), плоские
	for _, z in { 20, 96 } do
		paint(CFrame.new(-7, 0.01, z), Vector3.new(0.5, 0.05, 7), 0.5)
		local tip = wedge(ctx, f, CFrame.new(-7, 0.01, z - 4.6) * CFrame.Angles(0, 0, 0), Vector3.new(2.2, 0.05, 2.2), C.paint, Enum.Material.SmoothPlastic, "Paint")
		tip.Transparency = 0.5
		tip.CastShadow = false
	end
end

-- Трещины: цепочки тонких тёмных полос с ветвлением
local function buildCracks(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "Cracks")
	local function chain(p: Vector3, ang: number, n: number, w: number)
		local pos = p
		local a = ang
		for i = 1, n do
			local len = rng:range(3, 9)
			a += rng:range(-0.6, 0.6)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local q = pos + dir * len
			local ww = w * (1 - (i - 1) / (n + 1))
			local part = box(ctx, f, MathX.axisX(Vector3.new((pos.X + q.X) / 2, 0.01, (pos.Z + q.Z) / 2), dir), Vector3.new(len + ww, 0.06, ww), C.crack, Enum.Material.Slate, "Crack")
			part.CastShadow = false
			if rng:next() < 0.25 and i < n - 1 then
				local b = a + (if rng:next() < 0.5 then 1 else -1) * rng:range(0.6, 1.2)
				local bl = rng:range(2, 6)
				local bq = q + Vector3.new(math.cos(b), 0, math.sin(b)) * bl
				local bp = box(ctx, f, MathX.axisX(Vector3.new((q.X + bq.X) / 2, 0.01, (q.Z + bq.Z) / 2), bq - q), Vector3.new(bl, 0.06, ww * 0.5), C.crack, Enum.Material.Slate, "Crack")
				bp.CastShadow = false
			end
			pos = q
		end
	end
	-- длинные трещины, пересекающие площадку (в том числе коридор — они плоские)
	local starts = {
		{ -40, 20, 0.3 },
		{ 30, 60, 2.6 },
		{ -10, 110, 0.9 },
		{ 5, 0, 1.8 },
		{ -60, 150, -0.4 },
		{ 55, 190, 3.6 },
		{ -20, -40, 0.1 },
		{ 25, -70, 2.2 },
		{ -5, 175, 1.4 },
		{ 40, 120, 3.0 },
		{ -50, 80, 0.7 },
		{ 12, 40, 2.0 },
	}
	for _, s in starts do
		chain(Vector3.new(s[1], 0, s[2]), s[3], rng:int(4, 7), rng:range(0.35, 0.8))
	end
end

-- Воронка: кольцо вздыбленных плит асфальта, обугленное дно, обломки внутри и вокруг.
-- low = true — низкий вариант (кромка не выше 0.6), можно ставить в коридоре.
local function crater(ctx: Ctx, parent: Instance, c: Vector3, r: number, low: boolean)
	local rng = ctx.rng
	local f = folder(parent, "Crater")
	disk(ctx, f, Vector3.new(c.X, 0.012, c.Z), r * 1.9, 0.06, C.scorch, Enum.Material.Slate, "CraterFloor")
	disk(ctx, f, Vector3.new(c.X, 0.02, c.Z), r * 1.1, 0.06, mix(C.scorch, C.crack, 0.5), Enum.Material.Slate, "CraterCore")
	local n = math.max(7, math.floor(2 * math.pi * r / 4.8))
	local a0 = rng:range(0, math.pi * 2)
	for i = 1, n do
		if rng:next() < 0.85 then
			local a = a0 + (i - 1) / n * math.pi * 2 + rng:range(-0.12, 0.12)
			local u = Vector3.new(math.cos(a), 0, math.sin(a))
			local rr = r * rng:range(0.85, 1.08)
			local L = if low then rng:range(1.6, 2.6) else rng:range(3, 5.5)
			local t = if low then rng:range(0.3, 0.45) else rng:range(0.7, 1.3)
			local th = if low then math.rad(rng:range(4, 9)) else math.rad(rng:range(18, 42))
			local y = L / 2 * math.sin(th) - (if low then 0.15 else 0.45)
			local pos = Vector3.new(c.X, 0, c.Z) + u * rr + Vector3.new(0, y, 0)
			local cf = MathX.lookAt(pos, pos + u) * CFrame.Angles(th, 0, rng:range(-0.12, 0.12))
			local w = 2 * math.pi * r / n * rng:range(0.85, 1.2)
			box(ctx, f, cf, Vector3.new(w, t, L), mix(C.asphaltLot, C.asphalt, rng:next()), Enum.Material.Asphalt, "RimSlab")
		end
	end
	if not low then
		for _ = 1, 3 do
			local a = rng:range(0, math.pi * 2)
			local rr = rng:range(0, r * 0.6)
			chunk(ctx, f, Vector3.new(c.X + math.cos(a) * rr, 0.3, c.Z + math.sin(a) * rr), rng:range(1.5, 3.2))
		end
		for _ = 1, 5 do
			local a = rng:range(0, math.pi * 2)
			local rr = r * rng:range(1.25, 2.1)
			local x, z = c.X + math.cos(a) * rr, c.Z + math.sin(a) * rr
			if not inCorridor(x, z, 1.5) then
				chunk(ctx, f, Vector3.new(x, 0.2, z), rng:range(0.8, 2.2))
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Здания
------------------------------------------------------------------------------------------

type BuildingSpec = {
	pos: Vector3, -- центр основания (Y=0)
	face: Vector3, -- куда смотрит главный фасад (к площади), горизонтальный вектор
	w: number, -- ширина фасада
	d: number, -- глубина
	floors: number,
	near: boolean, -- подробная оболочка (близко к площадке) или упрощённая
	lean: number?, -- крен коробки вперёд/назад, градусы
}

local function buildingColor(rng: Rng): Color3
	local base = pick(rng, { C.concrete, C.concreteLight, C.concreteDark, C.concreteViolet, C.concrete })
	return mix(base, C.dust, rng:range(0, 0.25))
end

-- Груда обломков в прямоугольнике (оси cf), не выше maxH
local function rubblePile(ctx: Ctx, parent: Instance, cf: CFrame, x0: number, x1: number, z0: number, z1: number, n: number, smax: number, maxH: number)
	local rng = ctx.rng
	for _ = 1, n do
		local s = rng:range(smax * 0.4, smax)
		local p = cf * Vector3.new(rng:range(x0, x1), 0, rng:range(z0, z1))
		if not inCorridor(p.X, p.Z, s) then
			local y = math.min(rng:range(0.1, 0.45) * s, math.max(0.2, maxH - s * 0.5))
			chunk(ctx, parent, Vector3.new(p.X, y, p.Z), s)
		end
	end
end

-- Подробная разрушенная коробка: пролёты разной высоты, перекрытия, пояса (проёмы окон между ними),
-- колонны, торцевые стены, висящие плиты и арматура на изломах, груды у подножия обрушенных пролётов.
local function nearBuilding(ctx: Ctx, f: Instance, spec: BuildingSpec)
	local rng = ctx.rng
	local base = MathX.lookAt(spec.pos, spec.pos + spec.face)
	if spec.lean then
		base = base * CFrame.Angles(math.rad(spec.lean), 0, 0)
	end
	local W, D, F = spec.w, spec.d, spec.floors
	local col = buildingColor(rng)
	local colBand = mix(col, C.concreteLight, 0.35)
	local colSlab = mix(col, C.concreteDark, 0.4)
	local nb = math.max(2, math.floor(W / 9 + 0.5))
	local bw = W / nb
	-- профиль высот (сколько этажей уцелело в каждом пролёте)
	local hf: { number } = {}
	local mode = rng:int(1, 3)
	local c = rng:range(1, nb)
	local spreadB = rng:range(1.0, 2.2)
	local depthB = rng:range(0.5, 0.95)
	local fromLeft = rng:next() < 0.5
	for i = 1, nb do
		local h = F
		if mode == 1 then -- выкушенный кусок
			local k = math.max(0, 1 - math.abs(i - c) / spreadB)
			h = F - math.floor(k * F * depthB + 0.5)
		elseif mode == 2 then -- скат на одну сторону
			local t = (if fromLeft then i - 1 else nb - i) / math.max(1, nb - 1)
			h = math.floor(F * (1 - 0.7 * t) + rng:range(-0.4, 0.8))
		else -- рваный верх
			h = F - rng:int(0, 3)
		end
		local x0 = -W / 2 + (i - 1) * bw
		local lim = areaLimit(base, x0, x0 + bw, -D / 2, D / 2)
		h = math.min(h, math.floor((lim - 1.8) / STOREY))
		hf[i] = math.clamp(h, 0, F)
	end
	local function H(i: number): number
		if i < 1 or i > nb then
			return 0
		end
		return hf[i]
	end
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local maxH = 0
	for i = 1, nb do
		maxH = math.max(maxH, hf[i])
	end
	-- перекрытия и пояса — сливаем соседние пролёты одной высоты в одну деталь
	for k = 1, maxH + 1 do
		local i = 1
		while i <= nb do
			-- перекрытие этажа k (верх на k*STOREY) есть, если пролёт выше k-1
			if hf[i] >= k then
				local j = i
				while j < nb and hf[j + 1] >= k do
					j += 1
				end
				local xa, xb = -W / 2 + (i - 1) * bw, -W / 2 + j * bw
				local isTopRun = (j - i + 1) < nb and k == math.max(hf[i], hf[j])
				if isTopRun and rng:next() < 0.4 then
					-- обломанная плита: короче по глубине, на краю арматура
					local frac = rng:range(0.45, 0.8)
					local dd = D * frac
					local zc = -D / 2 + dd / 2
					box(ctx, f, at((xa + xb) / 2, k * STOREY - 0.5, zc) * CFrame.Angles(math.rad(rng:range(-4, 4)), 0, 0), Vector3.new(xb - xa + 0.3, 1, dd), colSlab, Enum.Material.Concrete, "Slab")
					rebarFan(ctx, f, (at((xa + xb) / 2, k * STOREY - 0.5, zc + dd / 2)).Position, base.LookVector * -1, 3, 2.2, base.RightVector * ((xb - xa) / 2.2))
				else
					box(ctx, f, at((xa + xb) / 2, k * STOREY - 0.5, 0), Vector3.new(xb - xa + 0.3, 1, D), colSlab, Enum.Material.Concrete, "Slab")
				end
				i = j + 1
			else
				i += 1
			end
		end
		-- пояса (подоконные стенки) этажа k на отметке (k-1)*STOREY: высокие, если этаж есть; парапет — если это крыша
		if k >= 2 then
			for _, zs in { -1, 1 } do
				i = 1
				while i <= nb do
					local h = hf[i]
					if h >= k - 1 then
						local tall = h >= k
						local j = i
						while j < nb and hf[j + 1] >= k - 1 and (hf[j + 1] >= k) == tall do
							j += 1
						end
						local xa, xb = -W / 2 + (i - 1) * bw, -W / 2 + j * bw
						local hh = if tall then 3.4 else 1.5
						-- выбитый кусок пояса
						if rng:next() < 0.18 and j > i then
							local cut = xa + (xb - xa) * rng:range(0.3, 0.7)
							local gap = rng:range(2, 5)
							if cut - gap / 2 - xa > 1 then
								box(ctx, f, at((xa + cut - gap / 2) / 2, (k - 1) * STOREY - 0.6 + hh / 2, zs * (D / 2 - 0.4)), Vector3.new(cut - gap / 2 - xa, hh, 0.8), colBand, Enum.Material.Concrete, "Band")
							end
							if xb - (cut + gap / 2) > 1 then
								box(ctx, f, at((cut + gap / 2 + xb) / 2, (k - 1) * STOREY - 0.6 + hh / 2, zs * (D / 2 - 0.4)), Vector3.new(xb - cut - gap / 2, hh, 0.8), colBand, Enum.Material.Concrete, "Band")
							end
						else
							box(ctx, f, at((xa + xb) / 2, (k - 1) * STOREY - 0.6 + hh / 2, zs * (D / 2 - 0.4)), Vector3.new(xb - xa + 0.2, hh, 0.8), colBand, Enum.Material.Concrete, "Band")
						end
						i = j + 1
					else
						i += 1
					end
				end
			end
		end
	end
	-- колонны по границам пролётов (спереди, сзади и посередине глубины)
	for jb = 0, nb do
		local h = math.max(H(jb), H(jb + 1))
		if h > 0 then
			local x = -W / 2 + jb * bw
			local stub = if H(jb) ~= H(jb + 1) then rng:range(0.5, 3.5) else 0
			for _, zz in { -D / 2 + 0.8, D / 2 - 0.8 } do
				local hh = h * STOREY + stub
				box(ctx, f, at(x, hh / 2, zz), Vector3.new(1.4, hh, 1.4), col, Enum.Material.Concrete, "Column")
				if stub > 0 then
					rebarFan(ctx, f, at(x, hh, zz).Position, Vector3.new(0, 1, 0), 2, 1.6, base.RightVector * 0.4)
				end
			end
			if D >= 18 and (jb == 0 or jb == nb or rng:next() < 0.5) then
				box(ctx, f, at(x, h * STOREY / 2, 0), Vector3.new(1.2, h * STOREY, 1.2), colSlab, Enum.Material.Concrete, "Column")
			end
		end
	end
	-- глухие торцевые стены (с рваным верхом)
	for _, side in { -1, 1 } do
		local i = if side < 0 then 1 else nb
		local h = hf[i]
		if h > 0 then
			local hh = h * STOREY + 1
			local x = side * (W / 2 - 0.45)
			box(ctx, f, at(x, hh / 2, 0), Vector3.new(0.9, hh, D), col, Enum.Material.Concrete, "EndWall")
			if rng:next() < 0.7 then
				local wl = D * rng:range(0.3, 0.7)
				wedge(
					ctx,
					f,
					at(x, hh + 1.6, (if rng:next() < 0.5 then -1 else 1) * (D / 2 - wl / 2)) * CFrame.Angles(0, (if rng:next() < 0.5 then 0 else math.pi), 0),
					Vector3.new(0.9, 3.2, wl),
					col,
					Enum.Material.Concrete,
					"WallShard"
				)
			end
		end
	end
	-- изломы: висящие плиты, арматура, груды у подножия
	for i = 1, nb do
		local h = hf[i]
		for _, nbSide in { -1, 1 } do
			local n = i + nbSide
			local hn = H(n)
			if hn > h then
				local xb = -W / 2 + (if nbSide < 0 then i - 1 else i) * bw -- граница с высоким соседом
				local L = h + 1 -- первый отсутствующий этаж пролёта i
				-- висящая плита: шарнир на краю соседнего перекрытия, свисает в пустой пролёт
				if rng:next() < 0.75 then
					local lp = bw * rng:range(0.55, 0.9)
					local th = math.rad(rng:range(28, 70)) * -nbSide
					local hinge = at(xb, L * STOREY - 0.5, rng:range(-D * 0.15, D * 0.15))
					box(ctx, f, hinge * CFrame.Angles(0, 0, th) * CFrame.new(-nbSide * lp / 2, 0, 0), Vector3.new(lp, 0.9, D * rng:range(0.5, 0.85)), colSlab, Enum.Material.Concrete, "HangingSlab")
				end
				for lev = L, math.min(hn, L + 2) do
					rebarFan(ctx, f, at(xb, lev * STOREY - 0.5, 0).Position, base.RightVector * -nbSide, 2, 2.6, base.LookVector * (D * 0.4))
				end
			end
		end
		if h <= F - 3 then
			local xa = -W / 2 + (i - 1) * bw
			local lim = areaLimit(base, xa, xa + bw, -D / 2, D / 2)
			rubblePile(ctx, f, base, xa, xa + bw, -D / 2 - 4, D / 2, rng:int(3, 5), math.min(7, (F - h) * 1.1 + 2), lim)
		end
	end
end

-- Упрощённая дальняя коробка: тёмное нутро (проёмы читаются тёмными), пояса этажей по фасаду, пилоны,
-- глухие торцы и задняя стена. Разрушение (режим случайный):
--   1 — ступень: верхние этажи уцелели только над частью ширины;
--   2 — диагональный срез: верхние этажи «лесенкой» сужаются к одному краю;
--   3 — верхний блок осел и накренился, смяв этажи под собой;
--   4 — почти целая, рваный парапет.
-- Плюс (часто) пробоина на несколько этажей: пояса разорваны, видно тёмное нутро, торчит арматура.
local function farBuilding(ctx: Ctx, f: Instance, spec: BuildingSpec)
	local rng = ctx.rng
	local base = MathX.lookAt(spec.pos, spec.pos + spec.face)
	if spec.lean then
		base = base * CFrame.Angles(math.rad(spec.lean), 0, 0)
	end
	local W, D = spec.w, spec.d
	local lim = areaLimit(base, -W / 2, W / 2, -D / 2, D / 2)
	local F = math.min(spec.floors, math.floor((lim - 1.8) / STOREY))
	if F < 1 then
		rubblePile(ctx, f, base, -W / 2, W / 2, -D / 2, D / 2, rng:int(4, 7), 6, lim)
		return
	end
	local col = buildingColor(rng)
	local colBand = mix(col, C.concreteLight, 0.3)
	local colSlab = mix(col, C.concreteDark, 0.4)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local side = if rng:next() < 0.5 then -1 else 1
	local roll = rng:next()
	local mode = if F < 3 then 4 elseif roll < 0.3 then 1 elseif roll < 0.62 then 2 elseif roll < 0.8 and F >= 7 then 3 else 4
	-- ширина каждого этажа (от края side)
	local widths: { number } = {}
	local F1 = F
	if mode == 1 then
		local b = rng:int(1, math.max(1, math.floor(F * 0.55)))
		F1 = F - b
		local frac = rng:range(0.3, 0.6)
		for k = 1, F do
			widths[k] = if k > F1 then W * frac else W
		end
	elseif mode == 2 then
		local b = rng:int(math.max(2, math.floor(F * 0.3)), math.max(2, math.floor(F * 0.7)))
		F1 = math.max(1, F - b)
		for k = 1, F do
			widths[k] = if k > F1 then W * math.max(0.15, (1 - (k - F1) / (F - F1 + 1)) * rng:range(0.88, 1.05)) else W
		end
	elseif mode == 3 then
		local b = rng:int(3, math.min(5, F - 3))
		F1 = F - b
		for k = 1, F1 do
			widths[k] = W
		end
	else
		for k = 1, F do
			widths[k] = W
		end
	end
	local function xc(k: number): number
		return side * (W / 2 - widths[k] / 2)
	end
	-- пробоина: этажи [h0, h1], по ширине [hx0, hx1]
	local hole = rng:next() < 0.5 and F1 >= 4
	local h0 = if hole then rng:int(2, math.max(2, F1 - 2)) else 0
	local h1 = if hole then math.min(F1, h0 + rng:int(1, 3)) else -1
	local hx = rng:range(-W * 0.3, W * 0.3)
	local hw = rng:range(W * 0.18, W * 0.38)
	-- нутро: прогонами этажей одинаковой ширины
	local k = 1
	local topK = if mode == 3 then F1 else F
	while k <= topK do
		local j = k
		while j < topK and math.abs(widths[j + 1] - widths[k]) < 0.01 do
			j += 1
		end
		local hgt = (j - k + 1) * STOREY
		box(ctx, f, at(xc(k), (k - 1) * STOREY + hgt / 2, 0.4), Vector3.new(widths[k] - 1.6, hgt, D - 1.6), C.interior, Enum.Material.Concrete, "Core")
		-- задняя стена прогона
		box(ctx, f, at(xc(k), (k - 1) * STOREY + hgt / 2 + 0.3, D / 2 - 0.4), Vector3.new(widths[k], hgt + 0.6, 0.8), col, Enum.Material.Concrete, "BackWall")
		-- торец со стороны обрушения у суженных этажей: рваная стенка
		if widths[k] < W - 0.01 then
			local xe = xc(k) - side * widths[k] / 2
			box(ctx, f, at(xe, (k - 1) * STOREY + hgt * 0.45, 0), Vector3.new(0.8, hgt * 0.9, D * rng:range(0.55, 0.95)), col, Enum.Material.Concrete, "BrokenWall")
		end
		k = j + 1
	end
	-- пояса (балконные ограждения) по фасаду
	for kk = 1, topK do
		local y = kk * STOREY - 0.6
		local hh = if kk == topK or (kk < topK and widths[kk + 1] < widths[kk] - 0.01) then 2.2 else 3.2
		local x0 = xc(kk) - widths[kk] / 2
		local x1 = xc(kk) + widths[kk] / 2
		if hole and kk >= h0 and kk <= h1 then
			local ga, gb = math.max(x0, hx - hw / 2), math.min(x1, hx + hw / 2)
			if ga - x0 > 1 then
				box(ctx, f, at((x0 + ga) / 2, y, -D / 2), Vector3.new(ga - x0, hh, 1.0), colBand, Enum.Material.Concrete, "Band")
			end
			if x1 - gb > 1 then
				box(ctx, f, at((gb + x1) / 2, y, -D / 2), Vector3.new(x1 - gb, hh, 1.0), colBand, Enum.Material.Concrete, "Band")
			end
		else
			box(ctx, f, at((x0 + x1) / 2, y, -D / 2), Vector3.new(x1 - x0 + 0.4, hh, 1.0), colBand, Enum.Material.Concrete, "Band")
		end
	end
	if hole then
		-- в пробоине: обломок перекрытия свисает, торчит арматура
		local th = math.rad(rng:range(25, 55))
		box(ctx, f, at(hx - hw / 2, h1 * STOREY - 0.5, -D / 2 + 3) * CFrame.Angles(0, 0, -th) * CFrame.new(hw * 0.3, 0, 0), Vector3.new(hw * 0.6, 0.9, 6), colSlab, Enum.Material.Concrete, "HangingSlab")
		rebarFan(ctx, f, at(hx + hw / 2, h0 * STOREY - 0.6, -D / 2).Position, base.RightVector * -1, 2, 2.2, Vector3.new(0, 1.5, 0))
	end
	-- торцы (глухие)
	local hHigh = (if mode == 3 then F1 else F) * STOREY + 0.6
	local hLow = F1 * STOREY + 0.6
	for _, sx in { -1, 1 } do
		local hh = if sx == side then hHigh else hLow
		if mode == 2 and sx == side then
			-- торец «лесенки» со стороны уцелевшего края — по высоте самого верхнего этажа
			hh = F * STOREY + 0.6
		end
		box(ctx, f, at(sx * (W / 2 - 0.4), hh / 2, 0), Vector3.new(0.8, hh, D), col, Enum.Material.Concrete, "EndWall")
	end
	-- пилоны по фасаду (сетка проёмов)
	local np = math.max(2, math.floor(W / 14))
	for i = 0, np do
		local x = -W / 2 + i * W / np
		local inHole = hole and math.abs(x - hx) < hw / 2
		-- высота пилона: верхний этаж, над которым ещё есть фасад в этой точке
		local top = 0
		for kk = 1, topK do
			if math.abs(x - xc(kk)) <= widths[kk] / 2 + 0.1 then
				top = kk
			end
		end
		if top > 0 then
			if inHole then
				local ha = (h0 - 1) * STOREY
				if ha > 1 then
					box(ctx, f, at(x, ha / 2, -D / 2 - 0.1), Vector3.new(1.2, ha, 1.2), col, Enum.Material.Concrete, "Pilaster")
				end
			else
				local hh = top * STOREY
				box(ctx, f, at(x, hh / 2, -D / 2 - 0.1), Vector3.new(1.2, hh, 1.2), col, Enum.Material.Concrete, "Pilaster")
			end
		end
	end
	-- верхний накренившийся блок
	if mode == 3 then
		local b = F - F1
		local th = math.rad(rng:range(7, 13))
		local pivot = at(-side * W / 2, F1 * STOREY, 0) * CFrame.Angles(0, 0, -side * th)
		local function blk(x: number, y: number, z: number): CFrame
			return pivot * CFrame.new(x + side * W / 2, y, z)
		end
		local hb = b * STOREY
		box(ctx, f, blk(0, hb / 2, 0.4), Vector3.new(W - 1.6, hb, D - 1.6), C.interior, Enum.Material.Concrete, "Core")
		box(ctx, f, blk(0, hb / 2 + 0.3, D / 2 - 0.4), Vector3.new(W, hb + 0.6, 0.8), col, Enum.Material.Concrete, "BackWall")
		for _, sx in { -1, 1 } do
			box(ctx, f, blk(sx * (W / 2 - 0.4), hb / 2 + 0.3, 0), Vector3.new(0.8, hb + 0.6, D), col, Enum.Material.Concrete, "EndWall")
		end
		for kk = 1, b do
			box(ctx, f, blk(0, kk * STOREY - 0.6, -D / 2), Vector3.new(W + 0.4, if kk == b then 2.2 else 3.2, 1.0), colBand, Enum.Material.Concrete, "Band")
		end
		rebarFan(ctx, f, at(side * W / 2, F1 * STOREY, -D / 2).Position, base.RightVector * side, 3, 2.4, base.LookVector * 3)
		rubblePile(ctx, f, base, side * W / 2 - side * 2, side * (W / 2 + 10), -D / 2 - 6, D / 2, 3, 5, lim)
	elseif F1 < F then
		-- висящая плита и арматура на изломе, обломки у подножия со стороны обрушения
		local xe = xc(F) - side * widths[F] / 2
		local th = math.rad(rng:range(30, 65)) * side
		box(ctx, f, at(xe, (F1 + 1) * STOREY - 0.5, -D * 0.1) * CFrame.Angles(0, 0, th) * CFrame.new(-side * 3.5, 0, 0), Vector3.new(7, 0.9, D * 0.6), colSlab, Enum.Material.Concrete, "HangingSlab")
		rebarFan(ctx, f, at(xe, (F1 + 1) * STOREY - 0.5, -D / 2 + 1).Position, base.RightVector * -side, 2, 2.5, base.LookVector * 2)
		rubblePile(ctx, f, base, -side * W / 2, -side * W / 4, -D / 2 - 7, D / 2, 3, 6, lim)
	end
end

-- Обрушенный участок: груда, пара колонн-огрызков и кусок стены с проёмами
local function ruinLot(ctx: Ctx, f: Instance, spec: BuildingSpec)
	local rng = ctx.rng
	local base = MathX.lookAt(spec.pos, spec.pos + spec.face)
	local W, D = spec.w, spec.d
	local lim = areaLimit(base, -W / 2, W / 2, -D / 2, D / 2)
	rubblePile(ctx, f, base, -W / 2, W / 2, -D / 2, D / 2, rng:int(5, 8), 7, lim)
	local col = buildingColor(rng)
	local hWall = math.min(STOREY * rng:range(1.2, 2.4), lim - 1)
	if hWall > 4 then
		-- кусок фасада: два простенка и перемычка (проём окна)
		local x = rng:range(-W * 0.3, W * 0.3)
		local z = -D / 2 + rng:range(1, D * 0.4)
		local yaw = rng:range(-0.2, 0.2)
		local cf = base * CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, math.rad(rng:range(-4, 4)))
		box(ctx, f, cf * CFrame.new(-4.5, hWall / 2, 0), Vector3.new(3, hWall, 0.9), col, Enum.Material.Concrete, "WallPier")
		box(ctx, f, cf * CFrame.new(4.5, hWall * 0.4, 0), Vector3.new(3, hWall * 0.8, 0.9), col, Enum.Material.Concrete, "WallPier")
		box(ctx, f, cf * CFrame.new(0, hWall * 0.55, 0), Vector3.new(12, 2.2, 0.9), col, Enum.Material.Concrete, "WallBeam")
		rebarFan(ctx, f, (cf * CFrame.new(6, hWall * 0.55, 0)).Position, base.RightVector, 2, 2, nil)
	end
	for _ = 1, rng:int(1, 2) do
		local hc = math.min(rng:range(5, 16), lim - 0.5)
		if hc > 2 then
			local p = base * Vector3.new(rng:range(-W / 2, W / 2), 0, rng:range(-D / 2, D / 2))
			local tilt = CFrame.Angles(math.rad(rng:range(-10, 10)), 0, math.rad(rng:range(-10, 10)))
			local cfc = CFrame.new(p) * tilt * CFrame.new(0, hc / 2, 0)
			box(ctx, f, cfc, Vector3.new(1.4, hc, 1.4), col, Enum.Material.Concrete, "ColumnStub")
			rebarFan(ctx, f, (cfc * CFrame.new(0, hc / 2, 0)).Position, Vector3.new(0, 1, 0), 2, 1.8, Vector3.new(0.4, 0, 0))
		end
	end
end

-- Разрушенная многоуровневая парковка (палубы на колоннах, одна палуба рухнула пандусом)
local function parkingDeck(ctx: Ctx, f: Instance, center: Vector3, w: number, d: number)
	local rng = ctx.rng
	local col = C.concreteViolet
	for lev = 1, 3 do
		local y = lev * 9
		if lev == 2 then
			-- половина палубы рухнула на нижнюю: наклонная плита
			box(ctx, f, CFrame.new(center + Vector3.new(-w / 4, y - 0.6, 0)), Vector3.new(w / 2, 1.2, d), col, Enum.Material.Concrete, "Deck")
			local th = math.rad(16)
			box(ctx, f, CFrame.new(center + Vector3.new(w / 4, y - 4.6, 0)) * CFrame.Angles(0, 0, -th), Vector3.new(w / 2 + 2, 1.2, d * 0.92), mix(col, C.concreteDark, 0.3), Enum.Material.Concrete, "FallenDeck")
		elseif lev == 3 then
			box(ctx, f, CFrame.new(center + Vector3.new(-w / 4 - 2, y - 0.6, -d / 6)), Vector3.new(w / 2 - 4, 1.2, d * 0.66), col, Enum.Material.Concrete, "Deck")
		else
			box(ctx, f, CFrame.new(center + Vector3.new(0, y - 0.6, 0)), Vector3.new(w, 1.2, d), col, Enum.Material.Concrete, "Deck")
		end
		-- ограждение палубы (низкая стенка) по длинной стороне
		if lev ~= 2 then
			local ww = if lev == 3 then w / 2 - 4 else w
			local xo = if lev == 3 then -w / 4 - 2 else 0
			box(ctx, f, CFrame.new(center + Vector3.new(xo, y + 0.8, -d / 2 + 0.3)), Vector3.new(ww, 1.8, 0.6), mix(col, C.concreteLight, 0.3), Enum.Material.Concrete, "Parapet")
		else
			box(ctx, f, CFrame.new(center + Vector3.new(-w / 4, y + 0.8, -d / 2 + 0.3)), Vector3.new(w / 2, 1.8, 0.6), mix(col, C.concreteLight, 0.3), Enum.Material.Concrete, "Parapet")
		end
	end
	-- колонны
	for ix = 0, 3 do
		for iz = 0, 2 do
			local x = -w / 2 + 1 + ix * (w - 2) / 3
			local z = -d / 2 + 1 + iz * (d - 2) / 2
			local hTop = if x > 0 then 9 else (if x < -w / 4 then 27 else 18)
			box(ctx, f, CFrame.new(center + Vector3.new(x, hTop / 2, z)), Vector3.new(1.6, hTop, 1.6), col, Enum.Material.Concrete, "Column")
		end
	end
	-- бежевая разметка на верхней палубе
	for i = 0, 3 do
		local p = box(ctx, f, CFrame.new(center + Vector3.new(-w / 2 + 4 + i * 4.2, 26.43, -d / 6)), Vector3.new(0.25, 0.05, 8), C.paint, Enum.Material.SmoothPlastic, "Paint")
		p.Transparency = 0.3
	end
	rebarFan(ctx, f, center + Vector3.new(0, 17.4, -d / 2 + 1), Vector3.new(1, -0.2, 0), 3, 2.5, Vector3.new(0, 0, d / 2.5))
	rubblePile(ctx, f, CFrame.new(center), 0, w / 2 + 6, -d / 2 - 4, d / 2, 4, 5, math.huge)
	local _ = rng
end

-- Трибуны стадиона: дуга наклонных секторов с козырьком (силуэт района стадиона вдали)
local function stadium(ctx: Ctx, f: Instance, center: Vector3, radius: number, a0: number, a1: number)
	local rng = ctx.rng
	local n = 12
	for i = 0, n - 1 do
		local a = a0 + (i + 0.5) / n * (a1 - a0)
		local u = Vector3.new(math.cos(a), 0, math.sin(a))
		local seg = radius * (a1 - a0) / n * 1.04
		local broken = rng:next() < 0.25
		local hs = if broken then rng:range(8, 14) else 24
		-- наклонные ряды трибуны: клин, высокая сторона наружу
		local pos = center + u * (radius + 14)
		local cf = MathX.lookAt(pos, pos - u)
		wedge(ctx, f, cf * CFrame.new(0, hs / 2, 0), Vector3.new(seg, hs, 28), mix(C.concreteLight, C.dust, 0.3), Enum.Material.Concrete, "Stand")
		-- задняя стена и козырёк
		if not broken then
			box(ctx, f, cf * CFrame.new(0, 17, 14.5), Vector3.new(seg, 34, 1.2), C.concrete, Enum.Material.Concrete, "StandWall")
			local roof = box(ctx, f, cf * CFrame.new(0, 34, 2) * CFrame.Angles(math.rad(-6), 0, 0), Vector3.new(seg, 0.8, 26), C.metalLight, Enum.Material.Metal, "Canopy")
			roof.CastShadow = true
		else
			box(ctx, f, cf * CFrame.new(0, hs * 0.6, 14.5), Vector3.new(seg * 0.7, hs * 1.2, 1.2), C.concrete, Enum.Material.Concrete, "StandWall")
		end
	end
	-- поле (зелёное, выцветшее)
	local pitch = box(ctx, f, CFrame.new(center + Vector3.new(0, 0.02, 0)), Vector3.new(radius * 1.3, 0.05, radius * 1.7), hex("#5E7362"), Enum.Material.Grass, "Pitch")
	pitch.CastShadow = false
end

local function buildCity(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "Buildings")
	local idx = 0
	local function place(spec: BuildingSpec, kind: string)
		idx += 1
		local bf = folder(f, string.format("%s_%02d", kind, idx))
		if kind == "Near" then
			nearBuilding(ctx, bf, spec)
		elseif kind == "Far" then
			farBuilding(ctx, bf, spec)
		else
			ruinLot(ctx, bf, spec)
		end
	end
	-- Ряд 1: дома вдоль улиц по краям площадки, фасадом к площадке (|X| ~ 108..150)
	for _, sx in { -1, 1 } do
		local z = -400 + rng:range(0, 20)
		while z < 500 do
			local w = rng:range(32, 56)
			local zc = z + w / 2
			-- поперечные улицы
			if math.abs(zc - 251) < w / 2 + 12 or math.abs(zc + 232) < w / 2 + 12 then
				z += 30
				continue
			end
			local d = rng:range(20, 30)
			local x = sx * (108 + d / 2 + rng:range(0, 4))
			local face = Vector3.new(-sx, 0, 0)
			local nearZone = zc > -40 and zc < 230
			local roll = rng:next()
			local spec: BuildingSpec = {
				pos = Vector3.new(x, 0, zc),
				face = face,
				w = w,
				d = d,
				floors = if nearZone then rng:int(5, 10) else rng:int(4, 12),
				near = nearZone,
				lean = if rng:next() < 0.2 then rng:range(-2.5, 2.5) else nil,
			}
			if roll < 0.2 then
				place(spec, "Ruin")
			elseif nearZone and roll < 0.62 then
				place(spec, "Near")
			else
				place(spec, "Far")
			end
			z += w + rng:range(8, 18)
		end
	end
	-- Ряд 2: выше и реже (|X| ~ 165..215)
	for _, sx in { -1, 1 } do
		local z = -380 + rng:range(0, 40)
		while z < 480 do
			local w = rng:range(36, 60)
			local zc = z + w / 2
			if math.abs(zc - 251) < w / 2 + 12 or math.abs(zc + 232) < w / 2 + 12 then
				z += 30
				continue
			end
			local d = rng:range(22, 32)
			if rng:next() < 0.8 then
				local spec: BuildingSpec = {
					pos = Vector3.new(sx * (170 + d / 2 + rng:range(0, 20)), 0, zc),
					face = Vector3.new(-sx, 0, 0),
					w = w,
					d = d,
					floors = rng:int(7, 14),
					near = false,
					lean = if rng:next() < 0.25 then rng:range(-3, 3) else nil,
				}
				place(spec, if rng:next() < 0.12 then "Ruin" else "Far")
			end
			z += w + rng:range(18, 40)
		end
	end
	-- Торец площадки (+Z): дома за поперечной улицей, фасадом на -Z
	local x = -96
	while x < 96 do
		local w = rng:range(34, 50)
		local d = rng:range(20, 28)
		local spec: BuildingSpec = {
			pos = Vector3.new(x + w / 2, 0, 268 + d / 2),
			face = Vector3.new(0, 0, -1),
			w = w,
			d = d,
			floors = rng:int(5, 12),
			near = false,
			lean = nil,
		}
		place(spec, if rng:next() < 0.25 then "Ruin" else "Far")
		x += w + rng:range(6, 14)
	end
	-- За спиной Рю (-Z): выжженная зона — только руины не выше линии края плиты
	for _, p in { { -40, -250 }, { 35, -270 }, { -10, -320 }, { 60, -350 }, { -70, -370 } } do
		local spec: BuildingSpec = {
			pos = Vector3.new(p[1], 0, p[2]),
			face = Vector3.new(0, 0, 1),
			w = rng:range(30, 45),
			d = rng:range(20, 28),
			floors = 2,
			near = false,
			lean = nil,
		}
		place(spec, "Ruin")
	end
	-- парковочная палуба стадиона (восток) и трибуны (запад, вдали)
	parkingDeck(ctx, folder(f, "ParkingDeck"), Vector3.new(58, 0, 200), 34, 24)
	stadium(ctx, folder(f, "Stadium"), Vector3.new(-330, 0, 40), 95, math.rad(-70), math.rad(70))
end

------------------------------------------------------------------------------------------
-- Курган Рю: обрушенное здание на краю площадки
------------------------------------------------------------------------------------------

local function buildMound(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "RyuMound")
	local cz = -121
	local colA = C.concrete
	local colD = mix(C.concrete, C.concreteDark, 0.5)
	-- 1) плита Рю: верх ровно Y=30, X[-20,20], Z[-134,-108]
	local slab = box(ctx, f, CFrame.new(0, SLAB_TOP - 0.8, cz), Vector3.new(40, 1.6, 26), colA, Enum.Material.Concrete, "RyuSlab")
	slab.CanCollide = true
	slab.CanQuery = true
	slab:SetAttribute("TopY", SLAB_TOP)
	-- трещины и пыль на плите (плоские); площадка под ногами Рю X[-3,3] Z[-123,-116] чистая
	for _, c in { { -12, -126, 0.4 }, { 9, -114, 2.1 }, { 14, -129, 1.2 }, { -8, -112, -0.5 }, { 4, -131, 0.2 } } do
		local cr = box(ctx, f, CFrame.new(c[1], SLAB_TOP + 0.005, c[2]) * CFrame.Angles(0, c[3], 0), Vector3.new(rng:range(5, 9), 0.05, 0.25), C.crack, Enum.Material.Slate, "SlabCrack")
		cr.CastShadow = false
	end
	for _, d in { { -9, -125, 9, 6 }, { 11, -112, 7, 5 } } do
		local dust = box(ctx, f, CFrame.new(d[1], SLAB_TOP + 0.01, d[2]), Vector3.new(d[3], 0.05, d[4]), C.dust, Enum.Material.Concrete, "SlabDust")
		dust.Transparency = 0.5
		dust.CastShadow = false
	end
	for _ = 1, 10 do
		local x = rng:range(-18, 18)
		local z = rng:range(-131, -110)
		if math.abs(x) > 5 then
			local s = rng:range(0.3, 0.9)
			local cf = CFrame.new(x, SLAB_TOP + s * 0.25, z) * CFrame.Angles(rng:range(-0.3, 0.3), rng:range(0, 3), rng:range(-0.3, 0.3))
			box(ctx, f, cf, Vector3.new(s * 1.3, s * 0.5, s), mix(C.concreteLight, C.dust, 0.3), Enum.Material.Concrete, "SlabChip")
		end
	end
	-- 2) задний рваный край плиты: низкий обломанный парапет и пара прутьев
	--    (единственный силуэт внизу кадра B)
	local x = -20
	while x < 20 do
		local w = rng:range(2.5, 6)
		local h = rng:range(0.2, 0.6)
		if rng:next() < 0.75 then
			local cf = CFrame.new(math.min(x + w / 2, 19.5), SLAB_TOP + h / 2 - 0.05, -133.3)
				* CFrame.Angles(math.rad(rng:range(-6, 6)), math.rad(rng:range(-6, 6)), math.rad(rng:range(-5, 5)))
			box(ctx, f, cf, Vector3.new(w, h, 1.2), colD, Enum.Material.Concrete, "BrokenParapet")
		end
		x += w + rng:range(0.5, 2.5)
	end
	for _, rx in { -13.5, 8.5, 15 } do
		local a = Vector3.new(rx, SLAB_TOP - 0.2, -133.7)
		local top = a + Vector3.new(rng:range(-0.9, 0.9), rng:range(1.0, 1.7), rng:range(-1.6, -0.8))
		rod(ctx, f, a, top, 0.15, C.rust, Enum.Material.CorrodedMetal, "Rebar")
	end
	-- арматура, торчащая из рваных краёв плиты вбок и вниз (ниже края — в кадр B не попадает)
	rebarFan(ctx, f, Vector3.new(-12, SLAB_TOP - 0.8, -107.8), Vector3.new(0, -0.3, 1), 4, 2.6, Vector3.new(6, 0, 0))
	rebarFan(ctx, f, Vector3.new(10, SLAB_TOP - 0.8, -107.8), Vector3.new(0, -0.4, 1), 3, 2.4, Vector3.new(5, 0, 0))
	rebarFan(ctx, f, Vector3.new(20.2, SLAB_TOP - 0.8, -114), Vector3.new(1, -0.4, 0), 3, 2.2, Vector3.new(0, 0, 4))
	rebarFan(ctx, f, Vector3.new(-20.2, SLAB_TOP - 0.8, -127), Vector3.new(-1, -0.4, 0), 3, 2.2, Vector3.new(0, 0, 4))
	-- 3) остов под плитой: тёмное плотное нутро завала, угловые колонны, перекрытия и пояса этажей
	box(ctx, f, CFrame.new(0, 13, cz), Vector3.new(37, 26, 23), C.interior, Enum.Material.Concrete, "CoreFill")
	for _, cx in { -18.8, 0, 18.8 } do
		for _, czz in { -132.8, -109.2 } do
			box(ctx, f, CFrame.new(cx, (SLAB_TOP - 1.6) / 2, czz), Vector3.new(1.6, SLAB_TOP - 1.6, 1.6), colD, Enum.Material.Concrete, "Column")
		end
	end
	for _, y in { 10, 20 } do
		box(ctx, f, CFrame.new(0, y - 0.5, cz), Vector3.new(39, 1.2, 25), colD, Enum.Material.Concrete, "Floor")
		box(ctx, f, CFrame.new(-4, y + 0.9, -133.6), Vector3.new(30, 3.0, 0.8), C.concreteLight, Enum.Material.Concrete, "Band")
		box(ctx, f, CFrame.new(-19.6, y + 0.9, cz - 3), Vector3.new(0.8, 3.0, 16), C.concreteLight, Enum.Material.Concrete, "Band")
		box(ctx, f, CFrame.new(19.6, y + 0.9, cz + 2), Vector3.new(0.8, 3.0, 14), C.concreteLight, Enum.Material.Concrete, "Band")
	end
	-- 4) «блины»: перекрытия обрушенной части съехали и легли скатами вокруг остова
	local function slabTo(a: Vector3, b: Vector3, width: number, thick: number, roll: number, name: string)
		local dir = b - a
		local mid = (a + b) / 2
		local flat = Vector3.new(dir.X, 0, dir.Z)
		local look = MathX.lookAt(mid, mid + flat)
		local pitch = math.atan2(dir.Y, flat.Magnitude)
		local cf = look * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, roll)
		local col = mix(C.concrete, pick(rng, CONCRETES), rng:range(0.2, 0.5))
		box(ctx, f, cf, Vector3.new(width, thick, dir.Magnitude), col, Enum.Material.Concrete, name)
	end
	-- со стороны площадки — длинные пологие (видны из кадров behind_ryu / overview)
	slabTo(Vector3.new(-2, 22, -107), Vector3.new(-4, 2.5, -76), 34, 1.6, math.rad(3), "PancakeSlab")
	slabTo(Vector3.new(7, 14, -103), Vector3.new(10, 0.8, -68), 28, 1.4, math.rad(-5), "PancakeSlab")
	slabTo(Vector3.new(-7, 28.6, -108.5), Vector3.new(-9, 15.5, -90), 22, 1.3, math.rad(-6), "HangingRoof")
	slabTo(Vector3.new(14, 28.4, -108.5), Vector3.new(17, 19, -96), 10, 1.2, math.rad(8), "HangingRoof")
	slabTo(Vector3.new(-16, 12, -104), Vector3.new(-24, 1, -80), 16, 1.4, math.rad(-12), "PancakeSlab")
	-- по кругу: скаты от края остова к подножию (за спиной Рю — ниже линии края плиты)
	local nSkin = 13
	for i = 1, nSkin do
		local a = (i - 0.5) / nSkin * math.pi * 2 + rng:range(-0.12, 0.12)
		local u = Vector3.new(math.sin(a), 0, math.cos(a)) -- 0 = +Z (к площадке)
		if u.Z < 0.55 then
			local sx = if math.abs(u.X) > 1e-3 then 20.5 / math.abs(u.X) else math.huge
			local szz = if math.abs(u.Z) > 1e-3 then 13.5 / math.abs(u.Z) else math.huge
			local edge = Vector3.new(0, 0, cz) + u * math.min(sx, szz)
			local hTop = rng:range(17, 25)
			local spread = rng:range(22, 32)
			local top = edge + Vector3.new(0, hTop, 0) - u * 1.5
			local foot = edge + u * spread + Vector3.new(0, rng:range(0.3, 2), 0)
			slabTo(top, foot, rng:range(14, 22), rng:range(1.4, 2.2), math.rad(rng:range(-10, 10)), "HeapSlab")
			-- второй слой: короче и выше по склону
			if rng:next() < 0.7 then
				local top2 = edge + Vector3.new(0, hTop + rng:range(1, 4), 0) - u * 1
				local foot2 = edge + u * (spread * rng:range(0.45, 0.65)) + Vector3.new(0, hTop * rng:range(0.3, 0.45), 0)
				slabTo(top2, foot2, rng:range(9, 15), rng:range(1.2, 1.8), math.rad(rng:range(-16, 16)), "HeapSlab")
			end
		end
	end
	-- 5) обломки по склону конуса (крупнее у подножия), за спиной Рю — ниже линии края плиты
	for _ = 1, 92 do
		local a = rng:range(0, math.pi * 2)
		local u = Vector3.new(math.sin(a), 0, math.cos(a))
		local sx = if math.abs(u.X) > 1e-3 then 21 / math.abs(u.X) else math.huge
		local szz = if math.abs(u.Z) > 1e-3 then 14 / math.abs(u.Z) else math.huge
		local edge = Vector3.new(0, 0, cz) + u * math.min(sx, szz)
		local front = u.Z > 0.4
		local spread = if front then rng:range(30, 44) else rng:range(22, 32)
		local h0 = if front then 21 else 23
		local t = rng:next() ^ 0.85
		local h = h0 * (1 - t) ^ 1.15 * rng:range(0.8, 1.0)
		local p = edge + u * (t * spread)
		local s = rng:range(2.5, 5.5) * (0.65 + 0.8 * t)
		local y = math.max(0.2, h - s * 0.2)
		local lim = skyLimit(p.X, p.Z)
		if y + s * 0.5 > lim then
			y = math.max(0.2, lim - s * 0.6)
		end
		chunk(ctx, f, Vector3.new(p.X, y, p.Z), s, 0.9)
	end
	-- осыпь под самыми стенами остова (закрывает низ колонн)
	for _ = 1, 16 do
		local side = rng:int(1, 4)
		local px, pz
		if side == 1 then
			px, pz = rng:range(-20, 20), -106 + rng:range(0, 3)
		elseif side == 2 then
			px, pz = rng:range(-20, 20), -136 - rng:range(0, 3)
		elseif side == 3 then
			px, pz = -21 - rng:range(0, 3), rng:range(-134, -108)
		else
			px, pz = 21 + rng:range(0, 3), rng:range(-134, -108)
		end
		chunk(ctx, f, Vector3.new(px, rng:range(3, 12), pz), rng:range(4, 8), 0.8)
	end
	-- 6) торчащие из кучи сломанные колонны с арматурой
	for _, c in { { 27, -100, 0.5 }, { -28, -104, -0.6 }, { 31, -140, 0.9 }, { -29, -143, -0.8 }, { 8, -84, 0.3 }, { -14, -92, -0.2 } } do
		local base = Vector3.new(c[1], rng:range(3, 8), c[2])
		local dir = Vector3.new(math.sin(c[3]), rng:range(0.8, 1.6), math.cos(c[3]) * 0.6).Unit
		local L = rng:range(8, 14)
		local top = base + dir * L
		if top.Y < skyLimit(top.X, top.Z) then
			box(ctx, f, MathX.lookAt((base + top) / 2, top) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(1.5, L, 1.5), colD, Enum.Material.Concrete, "BrokenColumn")
			rebarFan(ctx, f, top, dir, 3, 1.6, Vector3.new(0.4, 0, 0.4))
		end
	end
	rebarFan(ctx, f, Vector3.new(0, 20, -106.5), Vector3.new(0, 0.1, 1), 3, 3, Vector3.new(8, 0, 0))
end

------------------------------------------------------------------------------------------
-- Реквизит: фонари, столбы с проводами, машины, знаки, деревья
------------------------------------------------------------------------------------------

-- Провисший провод: Beam между двумя точками, провис sag (доля длины)
local function cable(parent: Instance, p0: BasePart, w0: Vector3, p1: BasePart, w1: Vector3, sag: number)
	local dir = w1 - w0
	local L = dir.Magnitude
	if L < 0.5 then
		return
	end
	local u = dir.Unit
	-- Безье: P1 = A0 + A0.X*c, P2 = A1 - A1.X*c; середина опускается на 3/4*c*k/sqrt(1+k^2)
	local c = L / 3
	local q = math.clamp(4 * sag, 0, 0.9)
	local k = q / math.sqrt(1 - q * q)
	local up = Vector3.new(0, 1, 0)
	local a0 = Instance.new("Attachment")
	a0.Name = "CableA"
	a0.CFrame = p0.CFrame:ToObjectSpace(MathX.axisX(w0, u - up * k))
	a0.Parent = p0
	local a1 = Instance.new("Attachment")
	a1.Name = "CableB"
	a1.CFrame = p1.CFrame:ToObjectSpace(MathX.axisX(w1, u + up * k))
	a1.Parent = p1
	local b = Instance.new("Beam")
	b.Name = "Cable"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.CurveSize0 = c
	b.CurveSize1 = c
	b.Width0 = 0.14
	b.Width1 = 0.14
	b.Segments = 16
	b.FaceCamera = true
	b.Texture = ""
	b.Color = ColorSequence.new(C.cable)
	b.LightInfluence = 0
	b.LightEmission = 0
	b.Transparency = NumberSequence.new(0)
	b.Parent = parent
end

local function lampPost(ctx: Ctx, f: Instance, pos: Vector3, state: string)
	local rng = ctx.rng
	box(ctx, f, CFrame.new(pos + Vector3.new(0, 0.6, 0)), Vector3.new(1.5, 1.2, 1.5), C.concreteLight, Enum.Material.Concrete, "LampBase")
	local H = 26
	if state == "snapped" then
		-- сломан на середине: обрубок стоит, верх лежит рядом
		local h1 = rng:range(8, 13)
		rod(ctx, f, pos, pos + Vector3.new(0.3, h1, 0.2), 0.7, C.metalLight, Enum.Material.Metal, "LampPole")
		local dirOut = Vector3.new(if pos.X > 0 then 1 else -1, 0, rng:range(-0.6, 0.6)).Unit
		local a = pos + dirOut * 2 + Vector3.new(0, 0.35, 0)
		local b = a + dirOut * (H - h1) + Vector3.new(0, 0.3, 0)
		rod(ctx, f, a, b, 0.7, C.metalLight, Enum.Material.Metal, "LampPoleFallen")
		box(ctx, f, CFrame.new(b + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:range(0, 3), 0.4), Vector3.new(1.3, 0.6, 2.6), C.metal, Enum.Material.Metal, "LampHead")
		return
	end
	local lean = if state == "leaning" then CFrame.Angles(math.rad(rng:range(-14, 14)), 0, math.rad(rng:range(8, 18)) * (if pos.X > 0 then -1 else 1)) else CFrame.new()
	local root = CFrame.new(pos) * lean
	cylinder(ctx, f, root * CFrame.new(0, H / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), H, 0.7, C.metalLight, Enum.Material.Metal, "LampPole")
	box(ctx, f, root * CFrame.new(0, H, 0), Vector3.new(0.4, 0.4, 7), C.metalLight, Enum.Material.Metal, "LampArm")
	for _, dz in { -3.4, 3.4 } do
		box(ctx, f, root * CFrame.new(0, H - 0.35, dz), Vector3.new(1.3, 0.5, 2.4), C.metal, Enum.Material.Metal, "LampHead")
	end
end

local function car(ctx: Ctx, f: Instance, pos: Vector3, yaw: number, state: string)
	local rng = ctx.rng
	local paint = mix(pick(rng, { hex("#C9C9CF"), hex("#3A4560"), hex("#8F939C"), hex("#5A4038"), hex("#8C4A48"), hex("#2E3038") }), C.dust, rng:range(0.15, 0.4))
	local root = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	if state == "flipped" then
		root = root * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.pi + rng:range(-0.15, 0.15))
	elseif state == "side" then
		root = root * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(88))
	else
		root = root * CFrame.Angles(math.rad(rng:range(-4, 4)), 0, math.rad(rng:range(-5, 5)))
	end
	local crushed = state == "crushed"
	local cabH = if crushed then 0.8 else 1.9
	box(ctx, f, root * CFrame.new(0, 1.75, 0), Vector3.new(6, 2.3, 15.5), paint, Enum.Material.Metal, "CarBody")
	box(ctx, f, root * CFrame.new(0, 2.9 + cabH / 2, 1.2), Vector3.new(5.4, cabH, 6.8), C.glass, Enum.Material.Metal, "CarCabin")
	wedge(ctx, f, root * CFrame.new(0, 2.9 + cabH / 2, -3.3), Vector3.new(5.4, cabH, 2.2), C.glass, Enum.Material.Metal, "CarGlass")
	box(ctx, f, root * CFrame.new(0, 2.95 + cabH, 1.2), Vector3.new(5.5, 0.25, 6.6), paint, Enum.Material.Metal, "CarRoof")
	for _, wx in { -2.7, 2.7 } do
		for _, wz in { -4.8, 4.8 } do
			if rng:next() < 0.85 then
				cylinder(ctx, f, root * CFrame.new(wx, 1.1, wz), 0.9, 2.2, C.tire, Enum.Material.SmoothPlastic, "Wheel")
			end
		end
	end
end

local function utilityPoles(ctx: Ctx, f: Instance, sx: number)
	local rng = ctx.rng
	local prevArm: BasePart? = nil
	local prevCF: CFrame? = nil
	local z = -70 + rng:range(0, 10)
	local i = 0
	while z < 250 do
		i += 1
		local pos = Vector3.new(sx * 104, 0, z)
		local lean = CFrame.Angles(math.rad(rng:range(-4, 4)), 0, math.rad(rng:range(-3, 3)))
		if i % 3 == 2 then
			lean = CFrame.Angles(math.rad(rng:range(-12, 12)), 0, math.rad(rng:range(6, 14)) * sx)
		end
		local root = CFrame.new(pos) * lean
		local H = 30
		cylinder(ctx, f, root * CFrame.new(0, H / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), H, 1.0, C.concreteLight, Enum.Material.Concrete, "UtilityPole")
		local armCF = root * CFrame.new(0, H - 2.5, 0)
		local arm = box(ctx, f, armCF, Vector3.new(7, 0.45, 0.45), C.metal, Enum.Material.Metal, "CrossArm")
		if i % 2 == 0 then
			cylinder(ctx, f, root * CFrame.new(0.9 * -sx, H - 7, 0) * CFrame.Angles(0, 0, math.pi / 2), 2.6, 1.6, C.metalLight, Enum.Material.Metal, "Transformer")
		end
		if prevArm and prevCF then
			for _, ox in { -3.3, 0, 3.3 } do
				local w0 = (prevCF * CFrame.new(ox, 0.3, 0)).Position
				local w1 = (armCF * CFrame.new(ox, 0.3, 0)).Position
				cable(f, prevArm, w0, arm, w1, rng:range(0.035, 0.07))
			end
		end
		prevArm = arm
		prevCF = armCF
		z += rng:range(52, 64)
	end
	-- оборванный провод, свисающий до земли с последнего столба
	if prevArm and prevCF then
		local w0 = (prevCF * CFrame.new(3.3, 0.3, 0)).Position
		local anchor = box(ctx, f, CFrame.new(w0.X - sx * 3, 0.2, w0.Z + 9), Vector3.new(0.4, 0.4, 0.4), C.cable, Enum.Material.Metal, "CableEnd")
		cable(f, prevArm, w0, anchor, anchor.CFrame.Position, 0.12)
	end
end

local function tree(ctx: Ctx, f: Instance, pos: Vector3, s: number)
	local rng = ctx.rng
	local h = 8 * s
	rod(ctx, f, pos, pos + Vector3.new(rng:range(-0.5, 0.5), h, rng:range(-0.5, 0.5)), 0.9 * s, C.trunk, Enum.Material.SmoothPlastic, "Trunk")
	for j = 1, 3 do
		local d = rng:range(7, 11) * s
		local p = pos + Vector3.new(rng:range(-2.5, 2.5) * s, h + rng:range(-1, 2.5) * s, rng:range(-2.5, 2.5) * s)
		ellipsoid(ctx, f, CFrame.new(p), Vector3.new(d, d * 0.8, d), if j == 1 then C.leaf0 else C.leaf1, Enum.Material.SmoothPlastic, "Canopy")
	end
end

local function buildProps(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "Props")
	-- фонари парковки вдоль центрального проезда (силуэты в тумане дают глубину)
	local lamps = folder(f, "LampPosts")
	local states = { "ok", "ok", "leaning", "ok", "snapped", "ok", "ok", "leaning", "ok", "snapped", "ok", "ok" }
	local si = 0
	for _, z in { -40, 10, 60, 110, 160, 210 } do
		for _, sx in { -1, 1 } do
			si += 1
			lampPost(ctx, lamps, Vector3.new(sx * 19 + rng:range(-0.5, 0.5), 0, z + rng:range(-3, 3)), states[si])
		end
	end
	-- столбы с проводами вдоль боковых улиц
	local poles = folder(f, "UtilityPoles")
	utilityPoles(ctx, poles, -1)
	utilityPoles(ctx, poles, 1)
	-- машины
	local cars = folder(f, "Cars")
	car(ctx, cars, Vector3.new(24, 0, 34), math.rad(90 + rng:range(-8, 8)), "ok")
	car(ctx, cars, Vector3.new(-25, 0, 86), math.rad(-90 + rng:range(-10, 10)), "crushed")
	car(ctx, cars, Vector3.new(59, 0, 62), math.rad(92), "ok")
	car(ctx, cars, Vector3.new(-58, 0, 140), math.rad(-75), "side")
	car(ctx, cars, Vector3.new(26, 0, 178), math.rad(80), "crushed")
	car(ctx, cars, Vector3.new(44, 0, -12), math.rad(30), "flipped")
	car(ctx, cars, Vector3.new(-26, 0, -30), math.rad(-95), "ok")
	car(ctx, cars, Vector3.new(-62, 0, 20), math.rad(-100), "flipped")
	-- поваленные знаки
	local signs = folder(f, "Signs")
	for _, s in { { 30, 98, 0.4, "round" }, { -34, 6, 2.0, "guide" }, { 22, -48, 1.1, "round" }, { -45, 196, 2.8, "guide" } } do
		local p = Vector3.new(s[1] :: number, 0.2, s[2] :: number)
		local a = s[3] :: number
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local tilt = Vector3.new(0, rng:range(0.05, 0.3), 0)
		local tip = p + (dir + tilt).Unit * 10
		rod(ctx, signs, p, tip, 0.35, C.metalLight, Enum.Material.Metal, "SignPole")
		local look = MathX.lookAt(tip, tip + Vector3.new(0, 1, 0))
		if s[4] == "round" then
			cylinder(ctx, signs, CFrame.new(tip + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), 0.15, 2.6, hex("#B23A3A"), Enum.Material.Metal, "SignPlate")
		else
			box(ctx, signs, look * CFrame.new(0, 0, 0) * CFrame.Angles(0, a, 0), Vector3.new(6.5, 3.6, 0.2), hex("#2F5C9A"), Enum.Material.Metal, "SignPlate")
		end
	end
	-- деревья по краям площадки (густые купы)
	local trees = folder(f, "Trees")
	for _, t in { { -72, -60 }, { -70, -48 }, { 73, 118 }, { 70, 130 }, { -74, 214 }, { -66, 222 }, { 74, -80 } } do
		tree(ctx, trees, Vector3.new(t[1], 0, t[2]), rng:range(0.9, 1.25))
	end
end

------------------------------------------------------------------------------------------
-- Поля обломков, воронки, трещины
------------------------------------------------------------------------------------------

local function buildDebris(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "Debris")
	-- воронки от «Гранитного взрыва»
	crater(ctx, f, Vector3.new(-40, 0, 52), 11, false)
	crater(ctx, f, Vector3.new(36, 0, 146), 9, false)
	crater(ctx, f, Vector3.new(-14, 0, -54), 10, false)
	crater(ctx, f, Vector3.new(46, 0, -14), 13, false)
	crater(ctx, f, Vector3.new(-3, 0, 104), 8, true) -- низкая, в коридоре за спиной Рики
	-- вздыбленные плиты асфальта
	for _ = 1, 10 do
		local x = rng:range(-74, 74)
		local z = rng:range(-70, 230)
		if not inCorridor(x, z, 6) then
			local L = rng:range(4, 9)
			local th = math.rad(rng:range(10, 28))
			local yaw = rng:range(0, math.pi * 2)
			local cf = CFrame.new(x, L / 2 * math.sin(th) - 0.4, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(th, 0, 0)
			box(ctx, f, cf, Vector3.new(rng:range(4, 8), 0.9, L), mix(C.asphaltLot, C.asphalt, rng:next()), Enum.Material.Asphalt, "UpheavedSlab")
		end
	end
	-- редкие обломки по площадке
	local n = 0
	while n < 70 do
		local x = rng:range(-78, 78)
		local z = rng:range(-80, 236)
		if not inCorridor(x, z, 3) then
			chunk(ctx, f, Vector3.new(x, 0.15, z), rng:range(0.6, 3.0))
			n += 1
		end
	end
	-- крошка в коридоре (плоская, не выше 0.6)
	for _ = 1, 26 do
		chip(ctx, f, rng:range(-13, 13), rng:range(-8, 128), 0.55)
	end
	-- осыпи вдоль фасадов (у подножия домов по краям площадки)
	for _, sx in { -1, 1 } do
		for _ = 1, 16 do
			local x = sx * rng:range(100, 108)
			local z = rng:range(-90, 240)
			chunk(ctx, f, Vector3.new(x, 0.3, z), rng:range(1.2, 4))
		end
	end
end

------------------------------------------------------------------------------------------
-- Облака: кучевые громады из перекрывающихся эллипсоидов (аниме-ступени света)
------------------------------------------------------------------------------------------

-- Цвет комка по «тону» 0..1: глубокая тень -> тень -> середина -> свет -> блик
local function cloudTone(t: number): Color3
	local v = math.clamp(t, 0, 1)
	if v < 0.15 then
		return mix(C.cloudDeep, C.cloudShade, v / 0.15)
	elseif v < 0.4 then
		return mix(C.cloudShade, C.cloudMid2, (v - 0.15) / 0.25)
	elseif v < 0.65 then
		return mix(C.cloudMid2, C.cloudMid, (v - 0.4) / 0.25)
	elseif v < 0.85 then
		return mix(C.cloudMid, C.cloudHi, (v - 0.65) / 0.2)
	end
	return mix(C.cloudHi, C.cloudLit, (v - 0.85) / 0.15)
end

type CloudSpec = {
	pos: Vector3, -- точка основания (X, базовая высота, Z)
	width: number,
	top: number, -- высота верхушки
	towers: number,
	lumps: number?, -- светлых комков на каждом комке верхней кромки (детализация)
	lobe: number?, -- размер комка основания (доля ширины)
}

type CloudCore = { p: Vector3, r: number, fr: number }

-- Кучевая громада. В каждой башне — стопка больших шаров-«ядер» (средний тон); на их верхней и
-- обращённой к зрителю стороне — комки поменьше и светлее, они вылезают за силуэт («цветная капуста»);
-- на макушке — самые яркие. Снизу — сплющенные тёмные подушки основания.
local function cumulus(ctx: Ctx, f: Instance, spec: CloudSpec)
	local rng = ctx.rng
	local base = spec.pos
	local toward = Vector3.new(-base.X, 0, -40 - base.Z) -- к центру сцены
	local fwd = toward.Unit
	local up = Vector3.new(0, 1, 0)
	local right = up:Cross(fwd).Unit
	local W = spec.width
	local Hc = spec.top - base.Y
	local nl = spec.lumps or 3
	local function lump(p: Vector3, d: number, flat: number, tone: number, name: string)
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi), 0)
		local size = Vector3.new(d * rng:range(1.0, 1.18), d * flat, d * rng:range(0.9, 1.05))
		local e = ellipsoid(ctx, f, cf, size, cloudTone(tone), Enum.Material.SmoothPlastic, name)
		e.CastShadow = false
	end
	-- силуэт: объединение «куполов» башен; полуширина купола на высоте y: hw * sqrt(1 - (y/h)^1.6)
	type Dome = { x: number, h: number, hw: number }
	local domes: { Dome } = {}
	for k = 1, spec.towers do
		local main = k == math.ceil(spec.towers / 2)
		local x = if spec.towers == 1 then 0 else ((k - 1) / (spec.towers - 1) - 0.5) * W * 0.62
		x += rng:range(-0.06, 0.06) * W
		local h = if main then Hc else Hc * rng:range(0.5, 0.82)
		local hw = W * (if main then rng:range(0.3, 0.36) else rng:range(0.22, 0.3))
		table.insert(domes, { x = x, h = h, hw = hw })
	end
	-- широкое тёмное основание
	table.insert(domes, { x = 0, h = Hc * 0.3, hw = W * 0.5 })
	local function intervals(y: number): { { number } }
		local list: { { number } } = {}
		for _, d in domes do
			if y < d.h then
				local t = 1 - (y / d.h) ^ 1.6
				local hw = d.hw * math.sqrt(math.max(0, t))
				table.insert(list, { d.x - hw, d.x + hw })
			end
		end
		table.sort(list, function(a, b)
			return a[1] < b[1]
		end)
		local merged: { { number } } = {}
		for _, iv in list do
			local last = merged[#merged]
			if last and iv[1] <= last[2] then
				last[2] = math.max(last[2], iv[2])
			else
				table.insert(merged, { iv[1], iv[2] })
			end
		end
		return merged
	end
	-- ряды комков снизу вверх; комок у верхней кромки силуэта — светлее и получает «капусту» сверху
	local rBase = W * (spec.lobe or 0.19)
	local y = rBase * 0.45
	local rows = 0
	while y < Hc and rows < 12 do
		rows += 1
		local fr = y / Hc
		local r = rBase * (1 - 0.5 * fr) * rng:range(0.92, 1.08)
		local ivs = intervals(y)
		local above = intervals(y + r * 1.2)
		for _, iv in ivs do
			local a, b = iv[1] + r * 0.55, iv[2] - r * 0.55
			local n = math.max(1, math.floor((b - a) / (r * 1.25)) + 1)
			for i = 1, n do
				local x = if n == 1 then (a + b) / 2 else a + (b - a) * (i - 1) / (n - 1)
				x += rng:range(-0.2, 0.2) * r
				-- есть ли масса над этим комком (если нет — это верхняя кромка силуэта)
				local covered = false
				for _, av in above do
					if x > av[1] + r * 0.3 and x < av[2] - r * 0.3 then
						covered = true
					end
				end
				local edge = math.min(x - iv[1], iv[2] - x) / r -- близость к боковой кромке
				local depth = rng:range(-0.25, 0.3) * r + (if covered then -0.15 * r else 0.2 * r)
				local p = base + right * x + fwd * depth + up * (y + rng:range(-0.12, 0.12) * r)
				local tone = 0.12 + 0.5 * fr + (if covered then 0 else 0.2) - (if edge < 1 then 0.05 else 0) + rng:range(-0.07, 0.07)
				lump(p, r * 2 * rng:range(0.95, 1.15), rng:range(0.82, 0.95), tone, "CloudLobe")
				if not covered then
					-- «цветная капуста»: светлые комки на верхней стороне кромки
					for _ = 1, nl do
						local dir = (up * rng:range(0.45, 1.0) + right * rng:range(-0.9, 0.9) + fwd * rng:range(0.1, 0.6)).Unit
						local rr = r * rng:range(0.38, 0.58)
						local q = p + dir * (r * rng:range(0.62, 0.82))
						local tn = 0.55 + 0.35 * fr + 0.25 * dir:Dot(up) + rng:range(-0.05, 0.05)
						lump(q, rr * 2, rng:range(0.85, 0.97), tn, "CloudLump")
					end
				end
			end
		end
		y += r * rng:range(0.78, 0.92)
	end
end

local function buildClouds(ctx: Ctx, root: Instance)
	local rng = ctx.rng
	local f = folder(root, "Clouds")
	local function polar(angDeg: number, R: number, baseY: number): Vector3
		-- угол 0 = -Z (за спиной Рю), +90 = +X; отсчёт от Рю (0, -120)
		local a = math.rad(angDeg)
		return Vector3.new(math.sin(a) * R, baseY, -120 - math.cos(a) * R)
	end
	-- главный клубящийся столб дыма за спиной Рю и громады по бокам (кадры B, C)
	local hero: { CloudSpec } = {
		{ pos = polar(2, 1050, 40), width = 940, top = 830, towers = 3, lumps = 2, lobe = 0.17 },
		{ pos = polar(-31, 1100, 70), width = 720, top = 650, towers = 2, lumps = 2 },
		{ pos = polar(32, 1080, 60), width = 740, top = 720, towers = 3, lumps = 2 },
		{ pos = polar(-14, 1560, 90), width = 700, top = 770, towers = 2, lumps = 1, lobe = 0.22 },
		{ pos = polar(17, 1620, 90), width = 660, top = 700, towers = 2, lumps = 1, lobe = 0.22 },
		{ pos = polar(-53, 1300, 100), width = 660, top = 560, towers = 2, lumps = 1, lobe = 0.22 },
		{ pos = polar(54, 1260, 90), width = 660, top = 600, towers = 2, lumps = 1, lobe = 0.22 },
	}
	for _, s in hero do
		cumulus(ctx, f, s)
	end
	-- низкая гряда у горизонта на -Z: прячет полосу дальней земли под облаками
	for i = 1, 14 do
		local ang = -75 + (i - 0.5) * (150 / 14) + rng:range(-3, 3)
		local R = rng:range(640, 820)
		local p = polar(ang, R, rng:range(0, 40))
		local s = rng:range(280, 400)
		local size = Vector3.new(s * 1.25, s * rng:range(0.42, 0.55), s * 0.85)
		local e = ellipsoid(ctx, f, CFrame.new(p) * CFrame.Angles(0, math.rad(ang), 0), size, cloudTone(rng:range(0.12, 0.45)), Enum.Material.SmoothPlastic, "BankPuff")
		e.CastShadow = false
	end
	-- кольцо громад в остальных сторонах (дальше и ниже)
	local ring = { 78, 102, 128, 150, 172, 196, 220, 244, 266, 290 }
	for _, ang in ring do
		local R = rng:range(1500, 2500)
		cumulus(ctx, f, {
			pos = polar(ang + rng:range(-6, 6), R, rng:range(60, 150)),
			width = rng:range(520, 850),
			top = rng:range(380, 640),
			towers = rng:int(1, 2),
			lumps = 1,
			lobe = 0.24,
		})
	end
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CastShadow = false
		end
	end
end

------------------------------------------------------------------------------------------
-- Туман: невидимые детали с ParticleEmitter
------------------------------------------------------------------------------------------

type FogStyle = {
	rate: number,
	life: { number }, -- {мин, макс}
	size: { number }, -- {начало, конец}
	speed: { number },
	alpha: { number }, -- {пик, удержание} прозрачности
	color: { Color3 }, -- {начало, конец}
	light: number, -- LightInfluence
	accel: Vector3?,
}

local FOG_BANK: FogStyle = {
	rate = 1.8,
	life = { 10, 16 },
	size = { 16, 42 },
	speed = { 0.4, 1.6 },
	alpha = { 0.5, 0.6 },
	color = { hex("#D9DDF0"), hex("#B7BDDF") },
	light = 0.8,
}

local FOG_BILLOW: FogStyle = {
	rate = 3.0,
	life = { 9, 14 },
	size = { 20, 45 },
	speed = { 0.6, 2.0 },
	alpha = { 0.45, 0.55 },
	color = { hex("#DCE0F2"), hex("#B9BFE0") },
	light = 0.8,
	accel = Vector3.new(0, 0.06, 0),
}

local FOG_GROUND: FogStyle = {
	rate = 1.4,
	life = { 12, 16 },
	size = { 12, 26 },
	speed = { 0.3, 0.9 },
	alpha = { 0.55, 0.62 },
	color = { hex("#CDD2EA"), hex("#A9B1D8") },
	light = 0.85,
	accel = Vector3.new(0, -0.03, 0),
}

local FOG_HIGH: FogStyle = {
	rate = 2.2,
	life = { 12, 16 },
	size = { 18, 40 },
	speed = { 0.3, 1.2 },
	alpha = { 0.58, 0.65 },
	color = { hex("#DDE1F2"), hex("#BCC2E0") },
	light = 0.75,
}

local FOG_SKY: FogStyle = {
	rate = 0.3,
	life = { 14, 19 },
	size = { 55, 110 },
	speed = { 0.3, 0.8 },
	alpha = { 0.6, 0.7 },
	color = { hex("#E2E6F5"), hex("#C2C8E4") },
	light = 0.7,
}

local function fogEmitter(ctx: Ctx, f: Instance, layer: string, name: string, center: Vector3, size: Vector3, style: FogStyle, rateMul: number?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = CFrame.new(center)
	p.Parent = f
	ctx.parts += 1
	local rate = style.rate * (rateMul or 1)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Fog"
	e.Texture = Textures.smoke
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = rate
	e.Lifetime = NumberRange.new(style.life[1], style.life[2])
	e.Speed = NumberRange.new(style.speed[1], style.speed[2])
	local s0, s1 = style.size[1], style.size[2]
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, s0, s0 * 0.25),
		NumberSequenceKeypoint.new(0.5, (s0 + s1) * 0.55, s1 * 0.15),
		NumberSequenceKeypoint.new(1, s1, s1 * 0.2),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, style.alpha[1], 0.04),
		NumberSequenceKeypoint.new(0.72, style.alpha[2], 0.04),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(style.color[1], style.color[2])
	e.LightInfluence = style.light
	e.LightEmission = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-6, 6)
	e.Drag = 0.4
	e.WindAffectsDrag = true
	e.Acceleration = style.accel or Vector3.new(0, 0, 0)
	e.LockedToPart = false
	e.VelocityInheritance = 0
	e.ZOffset = 0
	e.Enabled = true
	e:SetAttribute("BaseRate", rate)
	e:SetAttribute("Layer", layer)
	e.Parent = p
	ctx.layerEmitters[layer] = (ctx.layerEmitters[layer] or 0) + 1
	local live = rate * (style.life[1] + style.life[2]) / 2
	ctx.layerLive[layer] = (ctx.layerLive[layer] or 0) + live
end

local function buildFog(ctx: Ctx, root: Instance)
	local f = folder(root, "FogEmitters")
	local n = 0
	local function nm(prefix: string): string
		n += 1
		return string.format("%s_%02d", prefix, n)
	end
	-- 1) «клубы»: плотная стена тумана вокруг коридора, из неё выходит Рика (Z 40..135)
	for _, z in { 62, 78, 94, 111, 128 } do
		fogEmitter(ctx, f, "bank", nm("Billow"), Vector3.new(-1, 7, z), Vector3.new(26, 10, 15), FOG_BILLOW, if z == 62 then 0.85 else 1)
	end
	for _, sx in { -1, 1 } do
		fogEmitter(ctx, f, "bank", nm("Billow"), Vector3.new(sx * 21, 7, 44), Vector3.new(14, 10, 26), FOG_BILLOW, 0.9)
	end
	-- 2) банк: плотный катящийся туман X[-80,80], Z[-40,180], до ~Y 25. Карман у камеры (X[-12,12], Z<56) пуст.
	for _, x in { -66, -40, 40, 66 } do
		for _, z in { -22, 14, 50, 86, 122, 158 } do
			fogEmitter(ctx, f, "bank", nm("Bank"), Vector3.new(x, 11, z), Vector3.new(26, 18, 36), FOG_BANK, if math.abs(x) > 50 then 0.85 else 1)
		end
	end
	for _, z in { 86, 122, 158 } do
		for _, sx in { -1, 1 } do
			fogEmitter(ctx, f, "bank", nm("Bank"), Vector3.new(sx * 20, 11, z), Vector3.new(14, 18, 36), FOG_BANK, 0.9)
		end
	end
	fogEmitter(ctx, f, "bank", nm("Bank"), Vector3.new(0, 12, 166), Vector3.new(26, 18, 28), FOG_BANK, 1.2)
	-- 3) приземный слой Y 0..6 на всю видимую площадь ±250 (ближе к площадке гуще)
	for ix = 0, 3 do
		for iz = 0, 3 do
			local x = -250 + 62.5 + ix * 125
			local z = -220 + 62.5 + iz * 125
			local inner = (ix == 1 or ix == 2) and (iz == 1 or iz == 2)
			fogEmitter(ctx, f, "ground", nm("Ground"), Vector3.new(x, 2.2, z), Vector3.new(125, 3.6, 125), FOG_GROUND, if inner then 1.6 else 0.9)
		end
	end
	-- вдоль самого коридора (ноги персонажей тонут в дымке)
	fogEmitter(ctx, f, "ground", nm("Ground"), Vector3.new(0, 1.8, 90), Vector3.new(40, 2.8, 90), FOG_GROUND, 1.4)
	fogEmitter(ctx, f, "ground", nm("Ground"), Vector3.new(0, 1.8, 10), Vector3.new(60, 2.8, 60), FOG_GROUND, 0.8)
	-- 4) высокая дымка Y 10..28 вокруг кургана Рю: его ноги — над морем тумана
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = Vector3.new(math.sin(a) * 58, 17, -121 + math.cos(a) * 52)
		fogEmitter(ctx, f, "high", nm("High"), p, Vector3.new(44, 12, 40), FOG_HIGH, if math.cos(a) < -0.3 then 1.15 else 1)
	end
	-- 5) редкие огромные клубы вдали (глубина)
	for _, p in {
		Vector3.new(0, 62, -290),
		Vector3.new(-120, 55, -250),
		Vector3.new(125, 58, -240),
		Vector3.new(-170, 48, 60),
		Vector3.new(170, 50, 90),
		Vector3.new(-120, 60, 250),
		Vector3.new(110, 56, 260),
		Vector3.new(0, 70, 330),
	} do
		fogEmitter(ctx, f, "sky", nm("Sky"), p, Vector3.new(70, 30, 70), FOG_SKY)
	end
end

------------------------------------------------------------------------------------------

function Environment.build(): Model
	local model = Instance.new("Model")
	model.Name = "Environment"
	local ctx: Ctx = {
		rng = MathX.rng(20181112), -- 12.11.2018 — день боя в Сэндае
		parts = 0,
		layerEmitters = {},
		layerLive = {},
	}
	-- у каждого раздела свой поток ГПСЧ: правка одного раздела не перетасовывает остальные
	local sections: { (Ctx, Instance) -> () } = {
		buildGround,
		buildParkingLines,
		buildCracks,
		buildMound,
		buildCity,
		buildProps,
		buildDebris,
		buildClouds,
		buildFog,
	}
	for i, fn in sections do
		ctx.rng = MathX.rng(20181112 + (10 + i) * 7919)
		fn(ctx, model)
	end
	model:SetAttribute("PartCount", ctx.parts)
	for layer, cnt in ctx.layerEmitters do
		model:SetAttribute("FogEmitters_" .. layer, cnt)
		model:SetAttribute("FogLive_" .. layer, math.floor(ctx.layerLive[layer] or 0))
	end
	model:SetAttribute("SlabTopY", SLAB_TOP)
	return model
end

return Environment
