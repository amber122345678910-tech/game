--!strict
-- "Лепка" персонажей и окружения из простых деталей.
-- Работает и в Roblox, и в Lune при сборке (там Instance/Color3/CFrame подставляет загрузчик).
--
-- Все функции, принимающие bone + cf, задают положение в осях кости в позе покоя
-- (X — вправо от персонажа, Y — вверх, -Z — вперёд). Деталь получает атрибут Bone и потом
-- двигается вместе с костью (см. Rig.bind).

local Rig = require(script.Parent.Parent.Rig)
local MathX = require(script.Parent.Parent.Math)

local Sculpt = {}

export type Opts = {
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	castShadow: boolean?,
	name: string?,
	flutter: { amp: number, freq: number?, hinge: Vector3?, axis: Vector3? }?,
	parent: Instance?,
}

export type StrandOpts = {
	widths: { number }?, -- ширина в каждой точке (по умолчанию сужение от width0 к 0.05)
	width0: number?,
	color0: Color3?, -- цвет у корня
	color1: Color3?, -- цвет на кончике
	transparency: number?,
	lightInfluence: number?,
	lightEmission: number?,
	segments: number?, -- сегментов на каждый Beam (гладкость)
	faceCamera: boolean?,
	outline: Color3?, -- контур пряди (второй, более широкий тёмный Beam позади)
	outlineScale: number?,
	stiffness: number?, -- 0..1 насколько прядь сопротивляется ветру (вес точек = (i/n)^(1+stiffness*2))
	seed: number?,
	zOffset: number?,
	name: string?,
}

export type Ctx = {
	model: Model,
	def: Rig.RigDef,
	origin: CFrame,
	carrier: { [string]: BasePart }, -- невидимые детали-носители для Attachment (по одной на кость)
	count: number,
	strandCount: number,
	folder: { [string]: Instance },
}

function Sculpt.hex(h: string): Color3
	local s = string.gsub(h, "#", "")
	local r = tonumber(string.sub(s, 1, 2), 16) or 0
	local g = tonumber(string.sub(s, 3, 4), 16) or 0
	local b = tonumber(string.sub(s, 5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

function Sculpt.mix(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- Создаёт пустую модель персонажа с невидимой деталью Root в точке origin.
function Sculpt.newCharacter(name: string, def: Rig.RigDef, origin: CFrame): Ctx
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = origin
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("Rig", def.name)
	return {
		model = model,
		def = def,
		origin = origin,
		carrier = {},
		count = 0,
		strandCount = 0,
		folder = {},
	}
end

local function folderFor(ctx: Ctx, bone: string): Instance
	-- Детали раскладываем по папкам костей — так в Studio легко найти, что к чему относится
	local f = ctx.folder[bone]
	if f then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = bone
	nf.Parent = ctx.model
	ctx.folder[bone] = nf
	return nf
end

-- Мировой CFrame точки cf в осях кости bone (в позе покоя)
function Sculpt.world(ctx: Ctx, bone: string, cf: CFrame): CFrame
	return ctx.origin * Rig.restOf(ctx.def, bone) * cf
end

local function applyCommon(ctx: Ctx, p: BasePart, bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?)
	local o: Opts = opts or {}
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	p.CastShadow = if o.castShadow == nil then true else o.castShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = Sculpt.world(ctx, bone, cf)
	ctx.count += 1
	p.Name = o.name or (bone .. "_" .. ctx.count)
	p:SetAttribute("Bone", bone)
	local fl = o.flutter
	if fl then
		p:SetAttribute("FlutterAmp", fl.amp)
		p:SetAttribute("FlutterFreq", fl.freq or 1.5)
		p:SetAttribute("FlutterHinge", fl.hinge or Vector3.new(0, size.Y / 2, 0))
		p:SetAttribute("FlutterAxis", fl.axis or Vector3.new(1, 0, 0))
	end
	p.Parent = o.parent or folderFor(ctx, bone)
end

-- Эллипсоид, вписанный в коробку size (SpecialMesh Sphere растягивается по размеру детали)
function Sculpt.ellipsoid(ctx: Ctx, bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?): Part
	local p = Instance.new("Part")
	applyCommon(ctx, p, bone, cf, size, color, opts)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

function Sculpt.box(ctx: Ctx, bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?): Part
	local p = Instance.new("Part")
	applyCommon(ctx, p, bone, cf, size, color, opts)
	return p
end

-- Клин: высокая сторона сзади (+Z), скат смотрит вперёд-вверх (-Z, +Y)
function Sculpt.wedge(ctx: Ctx, bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?): WedgePart
	local p = Instance.new("WedgePart")
	applyCommon(ctx, p, bone, cf, size, color, opts)
	return p
end

-- Цилиндр: ось вдоль локального X детали, size = (длина, диаметр, диаметр)
function Sculpt.cylinder(ctx: Ctx, bone: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	applyCommon(ctx, p, bone, cf, size, color, opts)
	return p
end

function Sculpt.ball(ctx: Ctx, bone: string, pos: Vector3, diameter: number, color: Color3, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	applyCommon(ctx, p, bone, CFrame.new(pos), Vector3.new(diameter, diameter, diameter), color, opts)
	return p
end

-- Вытянутый эллипсоид от точки a до точки b (в осях кости) с полуосями rx (по X сечения), rz.
-- roll — поворот сечения вокруг оси сегмента (градусы). Удобно для мышц, пальцев, прядей-объёмов.
function Sculpt.segment(
	ctx: Ctx,
	bone: string,
	a: Vector3,
	b: Vector3,
	width: number,
	depth: number,
	color: Color3,
	opts: Opts?,
	roll: number?,
	extend: number?
): Part
	local dir = b - a
	local len = dir.Magnitude
	local mid = (a + b) / 2
	-- ось Y детали вдоль сегмента
	local y = if len > 1e-6 then dir.Unit else Vector3.new(0, 1, 0)
	local refZ = Vector3.new(0, 0, 1)
	if math.abs(y:Dot(refZ)) > 0.95 then
		refZ = Vector3.new(1, 0, 0)
	end
	local x = y:Cross(refZ).Unit
	local z = x:Cross(y).Unit
	local cf = CFrame.fromMatrix(mid, x, y, z)
	if roll and roll ~= 0 then
		cf = cf * CFrame.Angles(0, math.rad(roll), 0)
	end
	local e = extend or 1.0
	return Sculpt.ellipsoid(ctx, bone, cf, Vector3.new(width, len * e, depth), color, opts)
end

-- Цилиндрическая "кость" с закруглёнными концами (капсула) между a и b
function Sculpt.capsule(ctx: Ctx, bone: string, a: Vector3, b: Vector3, diameter: number, color: Color3, opts: Opts?): { BasePart }
	local dir = b - a
	local len = dir.Magnitude
	local out = {}
	if len > 1e-4 then
		local x = dir.Unit
		local cf = MathX.axisX((a + b) / 2, x)
		table.insert(out, Sculpt.cylinder(ctx, bone, cf, Vector3.new(len, diameter, diameter), color, opts))
	end
	table.insert(out, Sculpt.ball(ctx, bone, a, diameter, color, opts))
	table.insert(out, Sculpt.ball(ctx, bone, b, diameter, color, opts))
	return out
end

-- Невидимая деталь-носитель для Attachment (одна на кость)
function Sculpt.carrier(ctx: Ctx, bone: string): BasePart
	local c = ctx.carrier[bone]
	if c then
		return c
	end
	local p = Instance.new("Part")
	p.Name = "Carrier_" .. bone
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = Sculpt.world(ctx, bone, CFrame.new())
	p:SetAttribute("Bone", bone)
	p.Parent = folderFor(ctx, bone)
	ctx.carrier[bone] = p
	return p
end

-- Прядь волос/меха/дыма из цепочки Beam через точки (в осях кости, поза покоя).
-- Касательные считаются по соседним точкам, CurveSize = треть длины отрезка — получается гладкий сплайн.
-- Каждой точке ставится атрибут Weight (0 у корня .. 1 на кончике) — по нему аниматор колышет прядь.
function Sculpt.strand(ctx: Ctx, bone: string, points: { Vector3 }, opts: StrandOpts?): { Beam }
	local o: StrandOpts = opts or {}
	local n = #points
	assert(n >= 2, "strand needs 2+ points")
	ctx.strandCount += 1
	local sid = ctx.strandCount
	local carrier = Sculpt.carrier(ctx, bone)
	local folder = Instance.new("Folder")
	folder.Name = o.name or ("Strand_" .. sid)
	folder.Parent = folderFor(ctx, bone)
	local stiff = o.stiffness or 0.3
	local seed = o.seed or sid * 1.37
	local atts: { Attachment } = {}
	local tangents: { Vector3 } = {}
	for i = 1, n do
		local prev = points[math.max(1, i - 1)]
		local nxt = points[math.min(n, i + 1)]
		local tdir = nxt - prev
		if tdir.Magnitude < 1e-6 then
			tdir = Vector3.new(0, 1, 0)
		end
		tangents[i] = tdir.Unit
	end
	for i = 1, n do
		local a = Instance.new("Attachment")
		a.Name = "P" .. i
		-- точка в осях носителя (носитель стоит в начале кости, без поворота)
		a.CFrame = MathX.axisX(points[i], tangents[i])
		local w = (i - 1) / (n - 1)
		a:SetAttribute("Weight", w ^ (1 + stiff * 2))
		a:SetAttribute("Seed", seed + i * 0.11)
		a.Parent = carrier
		atts[i] = a
	end
	local w0 = o.width0 or 0.5
	local widths = o.widths
	local function widthAt(i: number): number
		if widths then
			return widths[math.min(i, #widths)]
		end
		local f = (i - 1) / (n - 1)
		return w0 * (1 - f) + 0.04 * f
	end
	local c0 = o.color0 or Color3.new(1, 1, 1)
	local c1 = o.color1 or c0
	local beams: { Beam } = {}
	local function makeBeam(i: number, isOutline: boolean)
		local b = Instance.new("Beam")
		b.Name = (if isOutline then "Line" else "Seg") .. i
		b.Attachment0 = atts[i]
		b.Attachment1 = atts[i + 1]
		local seglen = (points[i + 1] - points[i]).Magnitude
		b.CurveSize0 = seglen / 3
		b.CurveSize1 = seglen / 3 -- P2 = A1 - A1.X * CurveSize1 (документация Beam)
		b.Segments = o.segments or 12
		b.FaceCamera = if o.faceCamera == nil then true else o.faceCamera
		local f0 = (i - 1) / (n - 1)
		local f1 = i / (n - 1)
		local scale = if isOutline then (o.outlineScale or 1.35) else 1
		local pad = if isOutline then 0.08 else 0
		b.Width0 = widthAt(i) * scale + pad
		b.Width1 = widthAt(i + 1) * scale + pad
		if isOutline then
			local oc = o.outline :: Color3
			b.Color = ColorSequence.new(oc)
			b.ZOffset = (o.zOffset or 0) - 0.05
			b.LightInfluence = 0
		else
			b.Color = ColorSequence.new(Sculpt.mix(c0, c1, f0), Sculpt.mix(c0, c1, f1))
			b.ZOffset = o.zOffset or 0
			b.LightInfluence = o.lightInfluence or 0.6
		end
		b.LightEmission = if isOutline then 0 else (o.lightEmission or 0)
		b.Transparency = NumberSequence.new(o.transparency or 0)
		b.Parent = folder
		table.insert(beams, b)
	end
	for i = 1, n - 1 do
		if o.outline then
			makeBeam(i, true)
		end
		makeBeam(i, false)
	end
	return beams
end

-- Контур в стиле аниме для всей модели (Highlight рисует силуэт). Видимость меняется по ходу сцены.
function Sculpt.outline(ctx: Ctx, color: Color3, transparency: number?): Highlight
	local h = Instance.new("Highlight")
	h.Name = "AnimeOutline"
	h.FillTransparency = 1
	h.OutlineColor = color
	h.OutlineTransparency = transparency or 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = ctx.model
	return h
end

-- Источник света, привязанный к кости (через носитель)
function Sculpt.light(ctx: Ctx, bone: string, pos: Vector3, className: string, props: { [string]: any }): Instance
	local carrier = Sculpt.carrier(ctx, bone)
	local a = Instance.new("Attachment")
	a.Name = "LightAt"
	a.CFrame = CFrame.new(pos) -- в Lune у Attachment есть только CFrame
	a.Parent = carrier
	local l = Instance.new(className)
	for k, val in props do
		(l :: any)[k] = val
	end
	l.Parent = a
	return l
end

return Sculpt
