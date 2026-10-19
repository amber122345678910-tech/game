--!nocheck
-- Библиотека для генерации карты в Lune: детали, «кирпичики» стиля (docs/STYLE.md §6.1), таблички, метки.
-- Все детали якорные; декор без коллизий, запросов и касаний (дёшево для телефонов).
-- ВАЖНО: в Lune CFrame.lookAt работает неверно, поэтому везде используем B.lookAt / B.axis (через CFrame.fromMatrix).
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim = roblox.UDim
local UDim2 = roblox.UDim2
local Font = roblox.Font
local ColorSequence = roblox.ColorSequence
local ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
local NumberSequence = roblox.NumberSequence

local B = {}
B.count = 0 -- сколько деталей создано (бюджет карты для телефонов)
B.balls = 0 -- сколько из них шаров (STYLE §2.1: на всю карту ≤ 300)

-- Единый ветер мира (STYLE §2.1, п. 4): стволы, кроны, травинки, наковальни туч и флаги тянутся по W
B.W = Vector3.new(1, 0, 0.35).Unit

----------------------------------------------------------------------
-- Детерминированный генератор случайных чисел (xorshift32)
----------------------------------------------------------------------
local RNG = {}
RNG.__index = RNG

function B.rng(seed: number)
	local self = setmetatable({ s = bit32.bor(math.floor(seed) % 4294967296, 1) }, RNG)
	for _ = 1, 8 do
		self:next()
	end
	return self
end

function RNG:next(): number
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x / 4294967296
end

function RNG:range(a: number, b: number): number
	return a + (b - a) * self:next()
end

function RNG:int(a: number, b: number): number
	return math.min(b, a + math.floor((b - a + 1) * self:next()))
end

function RNG:pick(list)
	return list[self:int(1, #list)]
end

function RNG:chance(p: number): boolean
	return self:next() < p
end

function RNG:sign(): number
	return if self:next() < 0.5 then -1 else 1
end

-- Случайная точка в круге радиуса r (равномерно по площади)
function RNG:disc(r: number)
	local a = self:range(0, math.pi * 2)
	local d = r * math.sqrt(self:next())
	return Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
end

-- Перемешать список на месте (Фишер — Йетс)
function RNG:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

----------------------------------------------------------------------
-- Цвета (STYLE §3.1): тень холоднее и темнее, свет теплее и светлее
----------------------------------------------------------------------
function B.rgb(r: number, g: number, b: number)
	return Color3.fromRGB(r, g, b)
end

-- Разброс оттенка/насыщенности/яркости (HSV), чтобы одинаковые детали не выглядели клонами
function B.vary(c, rng, amount: number?)
	local a = amount or 0.06
	local h, s, v = c:ToHSV()
	h = (h + rng:range(-a, a) * 0.25) % 1
	s = math.clamp(s + rng:range(-a, a), 0, 1)
	v = math.clamp(v + rng:range(-a, a), 0, 1)
	return Color3.fromHSV(h, s, v)
end

-- Сдвиг оттенка h (градусы) к target не больше чем на deg по кратчайшей дуге
local function hueToward(h: number, target: number, deg: number): number
	local d = ((target - h + 540) % 360) - 180
	if math.abs(d) <= deg then
		return target % 360
	end
	return (h + (if d > 0 then deg else -deg)) % 360
end

-- Тень: k = 1 — «тень», k = 1.6 — «глубокая тень» (формула STYLE §3.1)
function B.shade(c, k: number)
	local h, s, v = c:ToHSV()
	h = hueToward(h * 360, 255, 16 * k) / 360
	return Color3.fromHSV(h, math.min(1, s * (1 + 0.06 * k) + 0.02 * k), math.max(0, v * (1 - 0.33 * k)))
end

-- Свет: k = 1 — «свет» (теплее и светлее)
function B.tint(c, k: number)
	local h, s, v = c:ToHSV()
	h = hueToward(h * 360, 52, 14 * k) / 360
	return Color3.fromHSV(h, math.max(0, s * (1 - 0.18 * k)), math.min(1, v * (1 + 0.16 * k) + 0.04 * k))
end

function B.mix(a, b, t: number)
	return a:Lerp(b, t)
end

----------------------------------------------------------------------
-- Геометрия
----------------------------------------------------------------------
-- CFrame в точке pos, смотрящий на target (замена сломанного в Lune CFrame.lookAt)
function B.lookAt(pos, target, up)
	local look = target - pos
	if look.Magnitude < 1e-6 then
		return CFrame.new(pos)
	end
	look = look.Unit
	local u = up or Vector3.yAxis
	if math.abs(look:Dot(u)) > 0.999 then
		u = if math.abs(look.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
	end
	local right = look:Cross(u).Unit
	local up2 = right:Cross(look).Unit
	return CFrame.fromMatrix(pos, right, up2, -look)
end

-- Горизонтальный поворот: смотреть по направлению dir (только XZ), стоя в pos
function B.facing(pos, dir)
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-6 then
		return CFrame.new(pos)
	end
	return B.lookAt(pos, pos + d.Unit)
end

-- CFrame с осью X вдоль отрезка a→b (для цилиндров), и длина
function B.axis(a, b)
	local d = b - a
	local len = d.Magnitude
	local mid = (a + b) / 2
	if len < 1e-6 then
		return CFrame.new(mid), 0
	end
	local x = d / len
	local up = if math.abs(x.Y) < 0.99 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(mid, x, y, z), len
end

-- Направление по углу (градусы), как Zones: 0° = -Z, 90° = +X
function B.dir(angleDeg: number)
	local a = math.rad(angleDeg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

function B.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Угол поворота вокруг Y, при котором −Z (LookVector) смотрит по направлению dir
function B.yawOf(dir): number
	return math.atan2(-dir.X, -dir.Z)
end

-- Наклон «верхом по ветру» на deg градусов (поворот вокруг горизонтальной оси Y × W)
function B.windLean(deg: number)
	return CFrame.fromAxisAngle(Vector3.yAxis:Cross(B.W).Unit, math.rad(deg))
end

----------------------------------------------------------------------
-- Детали
----------------------------------------------------------------------
-- opts: Material, Collide (по умолчанию true), Shadow (по умолчанию: только крупные), Transparency,
-- Name, Query (по умолчанию = Collide), Touch (по умолчанию false), Reflectance
local function finish(p, size, color, opts, parent)
	opts = opts or {}
	p.Anchored = true
	p.Size = size
	p.Color = color
	p.Material = opts.Material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local collide = opts.Collide ~= false
	p.CanCollide = collide
	p.CanQuery = if opts.Query ~= nil then opts.Query else collide
	p.CanTouch = opts.Touch == true
	local maxDim = math.max(size.X, size.Y, size.Z)
	local isNeon = p.Material == Enum.Material.Neon
	p.CastShadow = if opts.Shadow ~= nil then opts.Shadow else (maxDim >= 6 and not isNeon)
	if opts.Transparency then
		p.Transparency = opts.Transparency
	end
	if opts.Reflectance then
		p.Reflectance = opts.Reflectance
	end
	if opts.Name then
		p.Name = opts.Name
	end
	p.Parent = parent
	B.count += 1
	return p
end

function B.block(parent, cf, size, color, opts)
	local p = Instance.new("Part")
	p.Name = "Part"
	p.CFrame = cf
	return finish(p, size, color, opts, parent)
end

function B.wedge(parent, cf, size, color, opts)
	local p = Instance.new("WedgePart")
	p.Name = "Wedge"
	p.CFrame = cf
	return finish(p, size, color, opts, parent)
end

function B.cornerWedge(parent, cf, size, color, opts)
	local p = Instance.new("CornerWedgePart")
	p.Name = "CornerWedge"
	p.CFrame = cf
	return finish(p, size, color, opts, parent)
end

-- Цилиндр с осью вдоль Y (вертикальный): length — высота, d — диаметр
function B.cylY(parent, pos, length: number, d: number, color, opts)
	local p = Instance.new("Part")
	p.Name = "Cylinder"
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	return finish(p, Vector3.new(length, d, d), color, opts, parent)
end

-- Цилиндр по произвольному CFrame (ось = X этого CFrame)
function B.cyl(parent, cf, length: number, d: number, color, opts)
	local p = Instance.new("Part")
	p.Name = "Cylinder"
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = cf
	return finish(p, Vector3.new(length, d, d), color, opts, parent)
end

-- Цилиндр между двумя точками
function B.rod(parent, a, b, d: number, color, opts)
	local cf, len = B.axis(a, b)
	return B.cyl(parent, cf, len, d, color, opts)
end

-- Брус между двумя точками (сечение w × h), ось Z вдоль отрезка
function B.bar(parent, a, b, w: number, h: number, color, opts, up)
	local len = (b - a).Magnitude
	local cf = B.lookAt((a + b) / 2, b, up)
	return B.block(parent, cf, Vector3.new(w, h, len), color, opts)
end

-- Брус ромбовидного сечения (повёрнут на 45° вокруг своей оси): стволы сухих деревьев, стеклянные шипы
function B.diamondBar(parent, a, b, w: number, color, opts, overlap: number?)
	local len = (b - a).Magnitude + (overlap or 0)
	local cf = B.lookAt((a + b) / 2, b) * CFrame.Angles(0, 0, math.pi / 4)
	return B.block(parent, cf, Vector3.new(w, w, len), color, opts)
end

-- Шар. По стилю это форма, а не кирпич: в объекте не больше одного (кроме облаков Lobe и снеговика)
function B.ball(parent, pos, d: number, color, opts)
	local p = Instance.new("Part")
	p.Name = "Ball"
	p.Shape = Enum.PartType.Ball
	p.CFrame = CFrame.new(pos)
	B.balls += 1
	return finish(p, Vector3.new(d, d, d), color, opts, parent)
end

-- Треугольник (a, b, c) из двух клиньев: верхняя грань лежит в плоскости треугольника,
-- толщина уходит вниз (против нормали, смотрящей вверх). Возвращает две детали.
function B.triangle(parent, a, b, c, thickness: number, color, opts)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-6 then
		return nil, nil
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	-- сдвиг вниз на половину толщины (форма клина симметрична вдоль X)
	local shift = if right.Y > 0 then -right * thickness / 2 else right * thickness / 2
	local w1 = B.wedge(parent, CFrame.fromMatrix((a + b) / 2 + shift, right, up, back), Vector3.new(thickness, height, math.abs(ab:Dot(back))), color, opts)
	local w2 = B.wedge(parent, CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back), Vector3.new(thickness, height, math.abs(ac:Dot(back))), color, opts)
	return w1, w2
end

function B.folder(parent, name: string)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function B.model(parent, name: string)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function B.light(part, color, range: number, brightness: number, shadows: boolean?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = shadows == true
	l.Parent = part
	return l
end

-- Декор (без коллизий): короткая форма
function B.deco(opts)
	opts = opts or {}
	opts.Collide = false
	opts.Query = false
	return opts
end

-- Неоновый акцент (без коллизий и тени). Неон — только энергия (STYLE §4)
function B.neon(opts)
	opts = B.deco(opts)
	opts.Material = Enum.Material.Neon
	opts.Shadow = false
	return opts
end

-- Копия таблицы опций (примитивы из нескольких деталей не должны делить одну таблицу)
local function copy(opts)
	local o = {}
	if opts then
		for k, v in opts do
			o[k] = v
		end
	end
	return o
end

----------------------------------------------------------------------
-- «Кирпичики» стиля (STYLE §6.1)
----------------------------------------------------------------------
-- GemCube: куб на вершине, три грани вверх (камешки, бутоны, искры, кончики, ягоды). 1 деталь
function B.gem(parent, pos, S: number, yaw: number, color, opts)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(35.264), 0, math.rad(45))
	return B.block(parent, cf, Vector3.new(S, S, S), color, opts)
end

-- TiltBox: брусок, наклонённый по двум осям (массы крон, кусты, клубы грозы). Углы в радианах. 1 деталь
function B.tiltBox(parent, pos, size, pitch: number, yaw: number, roll: number, color, opts)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
	return B.block(parent, cf, size, color, opts)
end

-- HexPrism: правильная шестигранная призма из 3 брусков (R — описанный радиус, h — высота, pos — центр). 3 детали
function B.hexPrism(parent, pos, R: number, h: number, yaw: number, color, opts)
	local parts = {}
	for q = 0, 2 do
		local cf = CFrame.new(pos) * CFrame.Angles(0, yaw + q * math.pi / 3, 0)
		table.insert(parts, B.block(parent, cf, Vector3.new(R, h, R * math.sqrt(3)), color, copy(opts)))
	end
	return parts
end

-- HexPlate: плоская HexPrism. jitter = 1 — неровный край по рецепту (длина Z ×(1 ± 0.18), yaw ±6°). 3 детали
function B.hexPlate(parent, pos, R: number, t: number, yaw: number, jitter: number?, rng, color, opts)
	local parts = {}
	local j = jitter or 0
	for q = 0, 2 do
		local zk, dy = 1, 0
		if j > 0 and rng then
			zk = 1 + rng:range(-0.18, 0.18) * j
			dy = math.rad(rng:range(-6, 6) * j)
		end
		local cf = CFrame.new(pos) * CFrame.Angles(0, yaw + q * math.pi / 3 + dy, 0)
		table.insert(parts, B.block(parent, cf, Vector3.new(R, t, R * math.sqrt(3) * zk), color, copy(opts)))
	end
	return parts
end

-- Pyramid4: настоящая четырёхгранная пирамида из 4 CornerWedge (base — центр основания).
-- У CornerWedgePart высокий угол — локальный (+X, +Y, −Z): ставим каждую четверть так, чтобы он смотрел в центр.
-- down = true — пирамида остриём вниз (сосульки, кончики под парящими камнями). 4 детали
B.CORNER_YAW = 0 -- поправка, если на листе превью высокий угол CornerWedge окажется другим (кратно π/2)
function B.pyramid4(parent, base, w: number, h: number, yaw: number, color, opts, down: boolean?)
	local parts = {}
	local flip = if down then CFrame.Angles(0, 0, math.pi) else CFrame.new()
	for q = 0, 3 do
		local cf = CFrame.new(base) * flip * CFrame.Angles(0, yaw + q * math.pi / 2 + B.CORNER_YAW, 0) * CFrame.new(-w / 4, h / 2, w / 4)
		table.insert(parts, B.cornerWedge(parent, cf, Vector3.new(w / 2, h, w / 2), color, copy(opts)))
	end
	return parts
end

-- Lobe: гранёный купол с плоским дном (облака моря). Шестигранный «барабан» тёмный, крышка — GemCube
-- (куб на вершине, три грани вверх) светлая и чуть уже барабана: по кромке виден мультяшный уступ-терминатор.
-- Шаров нет. base — центр плоского дна; поворот выводится из позиции (соседние купола не одинаковые). 4 детали
function B.lobe(parent, base, D: number, h: number, sideColor, topColor, opts)
	local hh = math.max(h, D / 2 + 0.1)
	local yaw = (base.X * 0.37 + base.Z * 0.11) % (math.pi * 2)
	local drum = B.hexPrism(parent, base + Vector3.new(0, hh / 2, 0), D / 2, hh, yaw, sideColor, opts)
	local cap = B.gem(parent, base + Vector3.new(0, hh, 0), D * 0.66, yaw + math.rad(30), topColor, copy(opts))
	return drum[1], cap
end

-- SkewPlate: параллелограмм (брусок и два клина на торцах) — вывески и таблички цены.
-- Лицо — −Z рамки cf (как у Front), верхний край сдвинут вправо на slant. Возвращает центральный брусок. 3 детали
function B.skewPlate(parent, cf, w: number, h: number, t: number, slant: number, color, opts)
	local mid = B.block(parent, cf, Vector3.new(w, h, t), color, copy(opts))
	local X, Y, Z = cf.RightVector, cf.UpVector, -cf.LookVector -- Z смотрит назад (как локальная +Z)
	-- правый клин: прямой угол сверху у бруска, скос уходит вправо-вниз
	local pr = cf.Position + X * (w / 2 + slant / 2)
	B.wedge(parent, CFrame.fromMatrix(pr, -Z, -Y, -X), Vector3.new(t, h, slant), color, copy(opts))
	-- левый клин: прямой угол снизу у бруска
	local pl = cf.Position - X * (w / 2 + slant / 2)
	B.wedge(parent, CFrame.fromMatrix(pl, -Z, Y, X), Vector3.new(t, h, slant), color, copy(opts))
	return mid
end

-- Zigzag: n брусков (сечение w × t), поочерёдно отклонённых на ±30° от линии a→b.
-- normal — нормаль плоскости зигзага (для дорожной инкрустации — вверх, для вывески — к зрителю). n деталей
function B.zigzag(parent, a, b, n: number, w: number, color, opts, normal, t: number?)
	local nrm = normal or Vector3.yAxis
	local d = b - a
	local dir = d.Unit
	local side = nrm:Cross(dir).Unit
	local L = d.Magnitude / (n * math.cos(math.rad(30)))
	local step = L * math.sin(math.rad(30))
	local p = a
	-- при нечётном n конец уходит вбок: сдвигаем старт на половину отклонения
	if n % 2 == 1 then
		p = a - side * step / 2
	end
	local parts = {}
	for k = 1, n do
		local s = if k % 2 == 1 then 1 else -1
		local q = p + dir * (L * math.cos(math.rad(30))) + side * step * s
		local cf = B.lookAt((p + q) / 2, q, nrm)
		table.insert(parts, B.block(parent, cf, Vector3.new(w, t or w, L + w * 0.9), color, copy(opts)))
		p = q
	end
	return parts
end

----------------------------------------------------------------------
-- Наклонная плита между двумя точками (дорожки, мостики)
----------------------------------------------------------------------
function B.slab(parent, a, b, width: number, thickness: number, color, opts)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = B.lookAt(mid, b)
	return B.block(parent, cf, Vector3.new(width, thickness, len), color, opts)
end

-- Кольцо из сегментов-брусков вокруг вертикальной оси (center — центр, y — низ кольца)
function B.ring(parent, center, radius: number, width: number, height: number, segments: number, color, opts)
	local parts = {}
	local seg = 2 * math.pi * radius / segments * 1.04
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = center + dir * radius + Vector3.new(0, height / 2, 0)
		table.insert(parts, B.block(parent, B.facing(pos, dir), Vector3.new(seg, height, width), color, copy(opts)))
	end
	return parts
end

----------------------------------------------------------------------
-- Провода и гирлянды: Beam без текстуры (0 деталей), провис — через CurveSize
----------------------------------------------------------------------
local function attach(part, pos, name)
	local a = Instance.new("Attachment")
	a.Name = name
	-- ось X вложения смотрит вниз: CurveSize даёт провис
	a.CFrame = part.CFrame:Inverse() * CFrame.fromMatrix(pos, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
	a.Parent = part
	return a
end

-- Провод от точки pa (на детали partA) до pb (на partB) с провисом sag. Возвращает функцию точки на кривой (t∈[0,1])
function B.wire(partA, pa, partB, pb, color, width: number, sag: number)
	local a0 = attach(partA, pa, "WireA")
	local a1 = attach(partB, pb, "WireB")
	local beam = Instance.new("Beam")
	beam.Name = "Wire"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission = 0
	beam.LightInfluence = 1
	beam.Width0 = width
	beam.Width1 = width
	beam.Segments = 10
	beam.FaceCamera = true
	-- кубическая кривая Безье: P1 = A0 + вниз·c, P2 = A1 + вниз·c (CurveSize1 со знаком минус)
	local c = sag * 4 / 3
	beam.CurveSize0 = c
	beam.CurveSize1 = -c
	beam.Parent = partA
	local down = Vector3.new(0, -c, 0)
	local p0, p1, p2, p3 = pa, pa + down, pb + down, pb
	return function(t: number)
		local u = 1 - t
		return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
	end
end

----------------------------------------------------------------------
-- Метки и надписи
----------------------------------------------------------------------
-- Невидимая метка для кода (без коллизий, запросов и касаний)
function B.marker(parent, name: string, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.CFrame = cf
	p.Size = size or Vector3.new(1, 1, 1)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = parent
	B.count += 1
	return p
end

-- Шрифты (STYLE §8.3.2): у всех трёх семейств полная кириллица (у прежнего шрифта Builder её не было).
-- 900 в Roblox называется Enum.FontWeight.Heavy (значения «Black» у FontWeight нет).
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local OSWALD = "rbxasset://fonts/families/Oswald.json"
local NUNITO = "rbxasset://fonts/families/Nunito.json"
B.FontDisplay = Font.new(MONTSERRAT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic) -- строка 1 вывесок, заголовки
B.FontDisplayFlat = Font.new(MONTSERRAT, Enum.FontWeight.Heavy) -- названия, глифы ◆ ▲ ▼
B.FontNumber = Font.new(OSWALD, Enum.FontWeight.Bold) -- цены, числа
B.FontBody = Font.new(NUNITO, Enum.FontWeight.Bold) -- строки табло, подписи
B.FontBodyHeavy = Font.new(NUNITO, Enum.FontWeight.ExtraBold) -- строка 2 вывесок, теги
-- старые имена (STYLE §9)
B.FontHeavy = B.FontDisplay
B.FontBold = B.FontBodyHeavy
B.FontMedium = B.FontBody

B.INK = Color3.fromRGB(18, 14, 40)
B.CREAM = Color3.fromRGB(255, 248, 232)
B.TEXT_DIM = Color3.fromRGB(170, 174, 220)
B.SIGN = Color3.fromRGB(28, 24, 56) -- основа вывесок (STYLE §9)
B.VOLT = Color3.fromRGB(255, 210, 60)
B.VOLT_HI = Color3.fromRGB(255, 240, 150)

-- SurfaceGui на грани детали. opts: Face (по умолчанию Front), PixelsPerStud, Light (влияние света 0..1), Name
function B.surface(part, opts)
	opts = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Name = opts.Name or "Sign"
	g.Face = opts.Face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = math.max(40, opts.PixelsPerStud or 40)
	g.LightInfluence = opts.Light or 0
	g.Brightness = opts.Brightness or 1.6
	g.MaxDistance = opts.MaxDistance or 250
	g.ClipsDescendants = true
	g.ResetOnSpawn = false
	g.Parent = part
	return g
end

-- ЗАГЛАВНЫЕ для русского текста (string.upper меняет только латиницу)
function B.upper(s: string): string
	local out = {}
	for _, c in utf8.codes(s) do
		if c >= 0x430 and c <= 0x44F then
			c -= 0x20
		elseif c == 0x451 then
			c = 0x401
		elseif c >= 97 and c <= 122 then
			c -= 32
		end
		table.insert(out, utf8.char(c))
	end
	return table.concat(out)
end

-- Обводка текста (UIStroke вместо TextStroke): у вывесок и надписей поверх мира
local function stroke(label, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = B.INK
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = label
	return s
end
B.stroke = stroke

-- Вертикальный градиент букв (от светлого сверху к основе)
local function gradient(label, top, bottom)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(1, bottom) })
	g.Parent = label
	return g
end
B.gradient = gradient

-- Табличка: строки одна под другой. lines = { {Text, Color, Size (доля высоты), Font, Rotation, Gradient = {верх, низ}, Stroke} }
-- По умолчанию (STYLE §9): строка 1 — FontDisplay ЗАГЛАВНЫМИ, Cream, обводка Ink, наклон −3°;
-- строка 2 — FontBodyHeavy, TextDim, 60% высоты, без наклона. opts: Face, PixelsPerStud, Name, Brightness
function B.text(part, lines, opts)
	opts = opts or {}
	local g = B.surface(part, opts)
	local total = 0
	for i, l in lines do
		total += l.Size or (if i == 1 then 1 else 0.6)
	end
	local pps = g.PixelsPerStud
	local y = 0
	for i, l in lines do
		local first = i == 1
		local h = (l.Size or (if first then 1 else 0.6)) / total
		local t = Instance.new("TextLabel")
		t.Name = "Line" .. i
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.86, h * 0.84)
		t.Position = UDim2.fromScale(0.07, y + h * 0.08)
		t.FontFace = l.Font or (if first then B.FontDisplay else B.FontBodyHeavy)
		t.Text = if first and l.Upper ~= false then B.upper(l.Text) else l.Text
		t.TextColor3 = l.Color or (if first then B.CREAM else B.TEXT_DIM)
		t.TextScaled = true
		t.TextWrapped = false
		t.Rotation = l.Rotation or (if first then -3 else 0)
		if l.Gradient then
			t.TextColor3 = Color3.new(1, 1, 1)
			gradient(t, l.Gradient[1], l.Gradient[2])
		end
		if l.Stroke ~= false and (first or l.Stroke) then
			stroke(t, math.max(2, math.floor(pps * 0.075 + 0.5)))
		end
		-- курсив и обводка выступают за рамку лейбла: поля слева и справа
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.Parent = t
		t.Parent = g
		y += h
	end
	return g
end

-- Вывеска по STYLE §9: SkewPlate цвета 28,24,56, текст на лицевой грани центрального бруска,
-- под текстом Neon-подчёркивание цвета энергии. cf — центр таблички, лицо −Z (к зрителю).
-- opts: Back = true — та же надпись и на задней грани; Underline = Color3 | false; Slant; Thickness; PixelsPerStud
function B.sign(parent, cf, w: number, h: number, lines, opts)
	opts = opts or {}
	local t = opts.Thickness or 0.4
	local slant = opts.Slant or math.min(h * 0.45, 1.4)
	local board = B.skewPlate(parent, cf, w, h, t, slant, opts.Color or B.SIGN, B.deco({ Shadow = false, Name = opts.Name or "Sign" }))
	B.text(board, lines, { Face = Enum.NormalId.Front, PixelsPerStud = opts.PixelsPerStud or 40 })
	if opts.Back then
		B.text(board, opts.BackLines or lines, { Face = Enum.NormalId.Back, PixelsPerStud = opts.PixelsPerStud or 40, Name = "SignBack" })
	end
	if opts.Underline ~= false then
		local col = opts.Underline or Color3.fromRGB(90, 210, 255)
		local yLine = -h / 2 + math.max(0.14, h * 0.1)
		B.block(parent, cf * CFrame.new(0, yLine, -t / 2 - 0.04), Vector3.new(w * 0.8, 0.2, 0.1), col, B.neon())
		if opts.Back then
			B.block(parent, cf * CFrame.new(0, yLine, t / 2 + 0.04), Vector3.new(w * 0.8, 0.2, 0.1), col, B.neon())
		end
	end
	return board
end

return B
