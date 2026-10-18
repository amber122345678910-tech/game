--!nocheck
-- Библиотека для генерации карты в Lune: детали, клинья-треугольники, таблички, метки.
-- Все детали якорные; декор без коллизий, запросов и касаний (дёшево для телефонов).
-- ВАЖНО: в Lune CFrame.lookAt работает неверно, поэтому везде используем B.lookAt / B.axis (через CFrame.fromMatrix).
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local Font = roblox.Font

local B = {}
B.count = 0 -- сколько деталей создано (бюджет карты для телефонов)

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

-- Случайная точка в круге радиуса r (равномерно по площади)
function RNG:disc(r: number)
	local a = self:range(0, math.pi * 2)
	local d = r * math.sqrt(self:next())
	return Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
end

----------------------------------------------------------------------
-- Цвета
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

-- Тень со сдвигом оттенка: темнее и холоднее (к сине-фиолетовому), как в стилизованной графике.
-- k = 0..1 — сила затемнения
function B.shade(c, k: number, toward)
	local cool = toward or Color3.fromRGB(52, 46, 96)
	local h, s, v = c:ToHSV()
	local dark = Color3.fromHSV(h, math.clamp(s * (1 + 0.25 * k), 0, 1), v * (1 - 0.55 * k))
	return dark:Lerp(cool, 0.35 * k)
end

-- Подсветка: светлее и теплее
function B.tint(c, k: number, toward)
	local warm = toward or Color3.fromRGB(255, 244, 214)
	return c:Lerp(warm, k)
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

function B.ball(parent, pos, d: number, color, opts)
	local p = Instance.new("Part")
	p.Name = "Ball"
	p.Shape = Enum.PartType.Ball
	p.CFrame = CFrame.new(pos)
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

-- Неоновый акцент (без коллизий и тени)
function B.neon(opts)
	opts = B.deco(opts)
	opts.Material = Enum.Material.Neon
	opts.Shadow = false
	return opts
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
		table.insert(parts, B.block(parent, B.facing(pos, dir), Vector3.new(seg, height, width), color, opts))
	end
	return parts
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

B.FontBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
B.FontHeavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
B.FontMedium = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

-- SurfaceGui на грани детали. opts: Face (по умолчанию Front), PixelsPerStud, Light (влияние света 0..1), Name
function B.surface(part, opts)
	opts = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Name = opts.Name or "Sign"
	g.Face = opts.Face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = opts.PixelsPerStud or 40
	g.LightInfluence = opts.Light or 0
	g.Brightness = opts.Brightness or 1.4
	g.MaxDistance = opts.MaxDistance or 400
	g.ClipsDescendants = true
	g.ResetOnSpawn = false
	g.Parent = part
	return g
end

-- Табличка: строки текста одна под другой. lines = { {Text, Color, Size(доля высоты)}, ... }
-- opts: Face, Stroke (обводка), Font, PixelsPerStud, Light
function B.text(part, lines, opts)
	opts = opts or {}
	local g = B.surface(part, opts)
	local total = 0
	for _, l in lines do
		total += l.Size or 1
	end
	local y = 0
	for i, l in lines do
		local h = (l.Size or 1) / total
		local t = Instance.new("TextLabel")
		t.Name = "Line" .. i
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.92, h * 0.9)
		t.Position = UDim2.fromScale(0.04, y + h * 0.05)
		t.FontFace = l.Font or opts.Font or B.FontHeavy
		t.Text = l.Text
		t.TextColor3 = l.Color or Color3.fromRGB(255, 255, 255)
		t.TextScaled = true
		t.TextWrapped = true
		t.TextStrokeTransparency = if opts.Stroke == false then 1 else 0.55
		t.TextStrokeColor3 = Color3.fromRGB(10, 10, 24)
		t.Parent = g
		y += h
	end
	return g
end

return B
