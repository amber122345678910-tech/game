--!nocheck
-- Библиотека для генерации карты в Lune: детали, природа, декор.
-- Все детали якорные; декор без коллизий и без запросов (дёшево для телефонов).
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local B = {}
B.count = 0

----------------------------------------------------------------------
-- Детерминированный генератор случайных чисел (xorshift32)
----------------------------------------------------------------------
local RNG = {}
RNG.__index = RNG

function B.rng(seed: number)
	local self = setmetatable({ s = bit32.bor(seed % 4294967296, 1) }, RNG)
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

----------------------------------------------------------------------
-- Цвета
----------------------------------------------------------------------
function B.rgb(r: number, g: number, b: number)
	return Color3.fromRGB(r, g, b)
end

-- Сдвиг цвета: яркость (dv) и небольшой разброс оттенка — чтобы одинаковые детали не выглядели клонами
function B.vary(c, rng, amount: number?)
	local a = amount or 0.06
	local h, s, v = c:ToHSV()
	h = (h + rng:range(-a, a) * 0.25) % 1
	s = math.clamp(s + rng:range(-a, a), 0, 1)
	v = math.clamp(v + rng:range(-a, a), 0, 1)
	return Color3.fromHSV(h, s, v)
end

----------------------------------------------------------------------
-- Детали
----------------------------------------------------------------------
-- opts: Material, Collide (по умолчанию true), Shadow (по умолчанию по размеру),
-- Transparency, Name, Query (по умолчанию = Collide), Reflectance
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
	p.CastShadow = if opts.Shadow ~= nil then opts.Shadow else maxDim >= 3
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

function B.ball(parent, pos, d: number, color, opts)
	local p = Instance.new("Part")
	p.Name = "Ball"
	p.Shape = Enum.PartType.Ball
	p.CFrame = CFrame.new(pos)
	return finish(p, Vector3.new(d, d, d), color, opts, parent)
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

----------------------------------------------------------------------
-- Наклонная плита между двумя точками (дорожки, мостики)
----------------------------------------------------------------------
function B.slab(parent, a, b, width: number, thickness: number, color, opts)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b)
	return B.block(parent, cf, Vector3.new(width, thickness, len), color, opts)
end

return B
