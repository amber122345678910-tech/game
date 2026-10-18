--!strict
-- Строители моделей из примитивов: громоотвод (Tool), банка, питомцы-искрята, коконы, фульгуриты, подстанция.
-- Работают на сервере, клиенте и в Lune-превью (tools/preview/models_sheet.luau).
-- Каждая функция возвращает НОВЫЙ экземпляр без родителя. Все детали: Anchored = false, сварены с PrimaryPart
-- (WeldConstraint), Massless, без коллизий/запросов/касаний и без теней — их цепляют к персонажу или двигают кодом.
-- Ориентация: «перёд» модели смотрит в −Z (LookVector), верх — +Y. PrimaryPart всегда без поворота,
-- поэтому Model:PivotTo(cf) ставит модель ровно так, как ожидается.
-- (В Lune CFrame.lookAt работает неверно — здесь используется только Geom.axisCFrame и CFrame.fromMatrix.)

local Pets = require(script.Parent.Pets)
local Fulgurite = require(script.Parent.Fulgurite)
local Geom = require(script.Parent.Geom)

local Models = {}

type PartKind = "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"

type Ctx = {
	root: Instance,
	parts: { BasePart },
}

local MAT = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(18, 16, 24)

local function newCtx(root: Instance): Ctx
	return { root = root, parts = {} }
end

local function newPart(kind: PartKind): BasePart
	if kind == "Wedge" then
		return Instance.new("WedgePart")
	elseif kind == "CornerWedge" then
		return Instance.new("CornerWedgePart")
	end
	local p = Instance.new("Part")
	if kind == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif kind == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	return p
end

-- Создать деталь в контексте (координаты — локальные, относительно центра модели)
local function add(ctx: Ctx, kind: PartKind, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local p = newPart(kind)
	p.Name = name
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or MAT.SmoothPlastic
	if transparency then
		p.Transparency = transparency
	end
	p.Parent = ctx.root
	table.insert(ctx.parts, p)
	return p
end

local function ball(ctx: Ctx, name: string, pos: Vector3, d: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	return add(ctx, "Ball", name, CFrame.new(pos), Vector3.new(d, d, d), color, material, transparency)
end

-- Цилиндр между точками a и b
local function rod(ctx: Ctx, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local cf, len = Geom.axisCFrame(a, b)
	return add(ctx, "Cylinder", name, cf, Vector3.new(math.max(len, 0.05), d, d), color, material, transparency)
end

-- Вертикальный цилиндр (ось Y): центр pos, высота h, диаметр d
local function cylY(ctx: Ctx, name: string, pos: Vector3, h: number, d: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	return add(ctx, "Cylinder", name, CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(h, d, d), color, material, transparency)
end

-- Сварить все детали с главной и назначить PrimaryPart (для Model)
local function weldAll(ctx: Ctx, primary: BasePart)
	for _, p in ctx.parts do
		if p ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Name = "Weld"
			w.Part0 = primary
			w.Part1 = p
			w.Parent = p
		end
	end
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(WHITE, k)
end

local function darker(c: Color3, k: number): Color3
	return c:Lerp(BLACK, k)
end

local function luminance(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- Кольцо из n сегментов в горизонтальной плоскости (нимб, обода)
local function ring(ctx: Ctx, name: string, center: Vector3, radius: number, thick: number, n: number, color: Color3, material: Enum.Material?)
	local seg = 2 * math.pi * radius / n * 1.08
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		-- брусок вдоль касательной: ось X детали = касательная
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local cf = CFrame.fromMatrix(pos, tangent, Vector3.yAxis, tangent:Cross(Vector3.yAxis))
		add(ctx, "Block", name, cf, Vector3.new(seg, thick, thick), color, material)
	end
end

-- Включить/выключить «якорь» у всех деталей модели (для превью и статичных витрин)
function Models.setAnchored(inst: Instance, anchored: boolean)
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
	if inst:IsA("BasePart") then
		inst.Anchored = anchored
	end
end

----------------------------------------------------------------------
-- Громоотвод: Tool с деталью Handle (держится вертикально: ось стержня = +Y ручки) и неоновым "Tip"
----------------------------------------------------------------------
export type RodStyle = {
	Name: string,
	Shaft: Color3,
	ShaftMaterial: Enum.Material,
	Trim: Color3,
	Grip: Color3,
	Glow: Color3,
}

Models.RodStyles = {
	[0] = { Name = "Медный", Shaft = Color3.fromRGB(196, 112, 66), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(150, 84, 50), Grip = Color3.fromRGB(96, 64, 44), Glow = Color3.fromRGB(120, 210, 255) },
	[1] = { Name = "Серебряный", Shaft = Color3.fromRGB(200, 206, 216), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(150, 160, 176), Grip = Color3.fromRGB(50, 56, 70), Glow = Color3.fromRGB(150, 220, 255) },
	[2] = { Name = "Золотой", Shaft = Color3.fromRGB(240, 196, 70), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(255, 232, 140), Grip = Color3.fromRGB(120, 40, 40), Glow = Color3.fromRGB(255, 225, 120) },
	[3] = { Name = "Тесла", Shaft = Color3.fromRGB(70, 80, 100), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(196, 112, 66), Grip = Color3.fromRGB(30, 34, 44), Glow = Color3.fromRGB(90, 200, 255) },
	[4] = { Name = "Грозовой", Shaft = Color3.fromRGB(60, 44, 96), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(180, 130, 255), Grip = Color3.fromRGB(30, 22, 48), Glow = Color3.fromRGB(190, 120, 255) },
	[5] = { Name = "Перунов", Shaft = Color3.fromRGB(30, 26, 36), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(255, 196, 60), Grip = Color3.fromRGB(110, 20, 24), Glow = Color3.fromRGB(255, 190, 60) },
} :: { [number]: RodStyle }

function Models.rod(tier: number): Tool
	local t = math.clamp(math.floor(tier), 0, 5)
	local st = Models.RodStyles[t]
	local tool = Instance.new("Tool")
	tool.Name = "Громоотвод"
	tool.ToolTip = st.Name .. " громоотвод"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	-- хват: ручка в ладони, стержень вверх (ось +Y ручки = «вверх» кисти)
	tool.Grip = CFrame.new(0, -0.4, 0)
	tool:SetAttribute("Tier", t)
	local ctx = newCtx(tool)

	-- ручка (обмотка) и стержень
	local handle = add(ctx, "Block", "Handle", CFrame.new(), Vector3.new(0.42, 2.2, 0.42), st.Grip, MAT.Fabric)
	cylY(ctx, "Wrap", Vector3.new(0, 0.55, 0), 0.25, 0.5, st.Trim, MAT.Metal)
	cylY(ctx, "Wrap", Vector3.new(0, -0.55, 0), 0.25, 0.5, st.Trim, MAT.Metal)
	ball(ctx, "Pommel", Vector3.new(0, -1.25, 0), 0.55, st.Trim, MAT.Metal)
	local shaftTop = 5.6 + t * 0.15
	cylY(ctx, "Shaft", Vector3.new(0, (1.1 + shaftTop) / 2, 0), shaftTop - 1.1, 0.3, st.Shaft, st.ShaftMaterial)
	-- гарда / воротник
	cylY(ctx, "Collar", Vector3.new(0, 1.2, 0), 0.3, 0.75, st.Trim, MAT.Metal)

	local tipPos: Vector3
	if t == 0 then
		-- медный: простой шпиль с шаром и витком проволоки
		for i = 0, 2 do
			cylY(ctx, "Coil", Vector3.new(0, 3 + i * 0.45, 0), 0.14, 0.5, st.Trim, MAT.Metal)
		end
		ball(ctx, "Knob", Vector3.new(0, shaftTop, 0), 0.6, st.Shaft, MAT.Metal)
		rod(ctx, "Spike", Vector3.new(0, shaftTop, 0), Vector3.new(0, shaftTop + 1, 0), 0.16, st.Trim, MAT.Metal)
		tipPos = Vector3.new(0, shaftTop + 1.1, 0)
	elseif t == 1 then
		-- серебряный: два кольца-изолятора и острый шпиль
		for i = 0, 1 do
			cylY(ctx, "Ring", Vector3.new(0, 3.6 + i * 0.9, 0), 0.22, 0.95, st.Trim, MAT.Metal)
		end
		cylY(ctx, "GlowBand", Vector3.new(0, 4.05, 0), 0.12, 0.42, st.Glow, MAT.Neon)
		rod(ctx, "Spike", Vector3.new(0, shaftTop, 0), Vector3.new(0, shaftTop + 1.4, 0), 0.22, st.Shaft, MAT.Metal)
		tipPos = Vector3.new(0, shaftTop + 1.5, 0)
	elseif t == 2 then
		-- золотой: трезубец
		cylY(ctx, "Cross", Vector3.new(0, shaftTop, 0), 0.3, 0.7, st.Trim, MAT.Metal)
		add(ctx, "Block", "Bar", CFrame.new(0, shaftTop + 0.1, 0), Vector3.new(1.8, 0.25, 0.25), st.Shaft, MAT.Metal)
		for side = -1, 1, 2 do
			rod(ctx, "Prong", Vector3.new(side * 0.85, shaftTop, 0), Vector3.new(side * 0.95, shaftTop + 1.0, 0), 0.2, st.Shaft, MAT.Metal)
			ball(ctx, "ProngTip", Vector3.new(side * 0.95, shaftTop + 1.05, 0), 0.26, st.Glow, MAT.Neon)
		end
		rod(ctx, "Spike", Vector3.new(0, shaftTop, 0), Vector3.new(0, shaftTop + 1.5, 0), 0.24, st.Shaft, MAT.Metal)
		tipPos = Vector3.new(0, shaftTop + 1.6, 0)
	elseif t == 3 then
		-- тесла: медная катушка, неоновые обмотки и тороид-шар
		cylY(ctx, "Coil", Vector3.new(0, shaftTop - 1.2, 0), 1.6, 0.7, st.Trim, MAT.Metal)
		for i = 0, 2 do
			cylY(ctx, "CoilGlow", Vector3.new(0, shaftTop - 1.8 + i * 0.6, 0), 0.1, 0.76, st.Glow, MAT.Neon)
		end
		ring(ctx, "Torus", Vector3.new(0, shaftTop + 0.2, 0), 0.55, 0.28, 8, Color3.fromRGB(190, 196, 210), MAT.Metal)
		tipPos = Vector3.new(0, shaftTop + 0.55, 0)
	elseif t == 4 then
		-- грозовой: парящий кристалл в кольце
		ring(ctx, "Halo", Vector3.new(0, shaftTop + 0.6, 0), 0.75, 0.16, 10, st.Trim, MAT.Neon)
		add(ctx, "Block", "Crystal", CFrame.new(0, shaftTop + 0.7, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.45, 1.2, 0.45), lighter(st.Glow, 0.3), MAT.Glass, 0.15)
		add(ctx, "Wedge", "CrystalTop", CFrame.new(0, shaftTop + 1.55, 0) * CFrame.Angles(0, math.pi / 4, 0), Vector3.new(0.45, 0.5, 0.45), lighter(st.Glow, 0.3), MAT.Glass, 0.15)
		tipPos = Vector3.new(0, shaftTop + 0.7, 0)
	else
		-- Перунов: чёрный с золотом, «корона» из пяти зубцов и молния-навершие
		cylY(ctx, "Crown", Vector3.new(0, shaftTop, 0), 0.45, 1.1, st.Trim, MAT.Metal)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			local base = Vector3.new(math.cos(a) * 0.5, shaftTop + 0.2, math.sin(a) * 0.5)
			rod(ctx, "Spire", base, base + Vector3.new(math.cos(a) * 0.25, 0.9, math.sin(a) * 0.25), 0.16, st.Trim, MAT.Metal)
		end
		-- зигзаг-молния
		local z1 = Vector3.new(0, shaftTop + 0.3, 0)
		local z2 = Vector3.new(0.3, shaftTop + 1.0, 0)
		local z3 = Vector3.new(-0.2, shaftTop + 1.3, 0)
		local z4 = Vector3.new(0.1, shaftTop + 2.1, 0)
		rod(ctx, "Bolt", z1, z2, 0.2, st.Glow, MAT.Neon)
		rod(ctx, "Bolt", z2, z3, 0.2, st.Glow, MAT.Neon)
		rod(ctx, "Bolt", z3, z4, 0.2, st.Glow, MAT.Neon)
		cylY(ctx, "Band", Vector3.new(0, 2.6, 0), 0.2, 0.42, st.Trim, MAT.Metal)
		cylY(ctx, "Band", Vector3.new(0, 4.0, 0), 0.2, 0.42, st.Trim, MAT.Metal)
		tipPos = z4 + Vector3.new(0, 0.2, 0)
	end
	-- неоновый кончик: его свечение меняет CharacterFX
	ball(ctx, "Tip", tipPos, 0.45 + t * 0.03, st.Glow, MAT.Neon)
	weldAll(ctx, handle)
	return tool
end

----------------------------------------------------------------------
-- Банка: стекло, металлические крышки, неоновое ядро "Core" (с выключенным PointLight)
-- Атрибуты модели: CoreHeight (полная высота ядра), CoreBottom (низ ядра по Y в локальных координатах)
----------------------------------------------------------------------
function Models.jar(): Model
	local m = Instance.new("Model")
	m.Name = "Jar"
	local ctx = newCtx(m)
	local root = add(ctx, "Block", "Root", CFrame.new(), Vector3.new(0.2, 0.2, 0.2), WHITE, MAT.SmoothPlastic, 1)
	local h, d = 2.3, 1.55
	local metal = Color3.fromRGB(120, 126, 140)
	cylY(ctx, "Glass", Vector3.zero, h, d, Color3.fromRGB(200, 230, 255), MAT.Glass, 0.55)
	local coreH = h - 0.35
	local core = cylY(ctx, "Core", Vector3.new(0, 0, 0), coreH, d - 0.32, Color3.fromRGB(110, 200, 255), MAT.Neon)
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Enabled = false
	light.Range = 10
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(110, 200, 255)
	light.Parent = core
	cylY(ctx, "CapTop", Vector3.new(0, h / 2 + 0.12, 0), 0.3, d + 0.12, metal, MAT.Metal)
	cylY(ctx, "CapBottom", Vector3.new(0, -h / 2 - 0.12, 0), 0.3, d + 0.12, metal, MAT.Metal)
	-- электроды: штырь сверху с шариком
	rod(ctx, "Electrode", Vector3.new(0, h / 2 + 0.25, 0), Vector3.new(0, h / 2 + 0.8, 0), 0.14, Color3.fromRGB(196, 112, 66), MAT.Metal)
	ball(ctx, "ElectrodeBall", Vector3.new(0, h / 2 + 0.85, 0), 0.3, Color3.fromRGB(196, 112, 66), MAT.Metal)
	-- обручи и ремень (сзади, к спине)
	for _, y in { -0.55, 0.55 } do
		cylY(ctx, "Hoop", Vector3.new(0, y, 0), 0.12, d + 0.06, metal, MAT.Metal)
	end
	add(ctx, "Block", "Strap", CFrame.new(0, 0, d / 2 + 0.05), Vector3.new(0.5, h + 0.4, 0.12), Color3.fromRGB(80, 56, 40), MAT.Fabric)
	m:SetAttribute("CoreHeight", coreH)
	m:SetAttribute("CoreBottom", -coreH / 2)
	m.PrimaryPart = root
	weldAll(ctx, root)
	return m
end

----------------------------------------------------------------------
-- Питомцы-искрята: тело-форма, большие глазки с бликом, щёчки, искорки-ушки, хвостик-след
----------------------------------------------------------------------
local CHEEK = Color3.fromRGB(255, 140, 170)

-- Глаз на поверхности шара радиуса r с центром c, в направлении dir (−Z — вперёд)
local function eye(ctx: Ctx, c: Vector3, r: number, dir: Vector3, size: number, darkBody: boolean)
	local u = dir.Unit
	local pos = c + u * (r - size * 0.18)
	if darkBody then
		ball(ctx, "EyeWhite", pos - u * 0.02, size * 1.25, Color3.fromRGB(245, 245, 255))
	end
	ball(ctx, "Eye", pos + u * 0.03, size, BLACK)
	-- блики: крупный вверху и крошечный внизу (как в мультфильмах)
	ball(ctx, "Shine", pos + u * (size * 0.4) + Vector3.new(size * 0.17, size * 0.19, 0), size * 0.34, WHITE)
	ball(ctx, "Shine2", pos + u * (size * 0.44) + Vector3.new(-size * 0.13, -size * 0.15, 0), size * 0.15, WHITE)
end

local function cheek(ctx: Ctx, c: Vector3, r: number, dir: Vector3, d: number)
	local u = dir.Unit
	local a = c + u * (r - 0.02)
	add(ctx, "Cylinder", "Cheek", (Geom.axisCFrame(a, a + u * 0.06)), Vector3.new(0.06, d, d), CHEEK)
end

-- Лицо на шаре: два глаза, щёчки, ротик
local function face(ctx: Ctx, c: Vector3, r: number, darkBody: boolean, eyeSize: number?)
	local es = eyeSize or r * 0.58
	eye(ctx, c, r, Vector3.new(-0.38, 0.12, -0.92), es, darkBody)
	eye(ctx, c, r, Vector3.new(0.38, 0.12, -0.92), es, darkBody)
	cheek(ctx, c, r, Vector3.new(-0.62, -0.22, -0.76), r * 0.34)
	cheek(ctx, c, r, Vector3.new(0.62, -0.22, -0.76), r * 0.34)
	-- ротик: крошечная тёмная «улыбка» из двух брусочков
	local m0 = c + Vector3.new(0, -0.28, -0.96).Unit * (r - 0.01)
	local dark = if darkBody then Color3.fromRGB(255, 220, 200) else Color3.fromRGB(60, 30, 40)
	add(ctx, "Block", "Mouth", CFrame.new(m0 + Vector3.new(-0.06, 0.012, 0)) * CFrame.Angles(0, 0, -0.45), Vector3.new(0.14, 0.05, 0.05), dark)
	add(ctx, "Block", "Mouth", CFrame.new(m0 + Vector3.new(0.06, 0.012, 0)) * CFrame.Angles(0, 0, 0.45), Vector3.new(0.14, 0.05, 0.05), dark)
end

-- Искорки-ушки: ромбики цвета тела с неоновой искоркой на кончике
local function sparkEars(ctx: Ctx, top: Vector3, spread: number, bodyColor: Color3, color: Color3)
	for side = -1, 1, 2 do
		local base = top + Vector3.new(side * spread, 0, 0)
		local tilt = CFrame.Angles(0, 0, -side * 0.42)
		local cf = CFrame.new(base) * tilt * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.pi / 4, 0)
		add(ctx, "Block", "Ear", cf, Vector3.new(0.3, 0.55, 0.3), lighter(bodyColor, 0.15))
		ball(ctx, "EarSpark", (CFrame.new(base) * tilt * CFrame.new(0, 0.55, 0)).Position, 0.2, color, MAT.Neon)
	end
end

-- Хвостик-след: 3 неоновых шарика, уменьшающихся назад
local function tail(ctx: Ctx, back: Vector3, color: Color3)
	for i = 1, 3 do
		ball(ctx, "Tail", back + Vector3.new(0, -0.05 * i, 0.22 * i), 0.36 - i * 0.08, color, MAT.Neon, (i - 1) * 0.2)
	end
end

function Models.pet(kind: string): Model
	local def = Pets.Kinds[kind] or Pets.Kinds[Pets.StarterPet]
	local m = Instance.new("Model")
	m.Name = def.Id
	m:SetAttribute("Kind", def.Id)
	m:SetAttribute("Rarity", def.Rarity)
	local ctx = newCtx(m)
	local col, acc = def.Color, def.Accent
	local dark = luminance(col) < 0.3
	local body: BasePart
	local r = 0.85 -- радиус «лица»
	local faceC = Vector3.zero
	local topY = r

	if def.Shape == "cloud" then
		body = ball(ctx, "Body", Vector3.zero, 1.7, col)
		ball(ctx, "Puff", Vector3.new(-0.8, -0.25, 0.1), 1.1, darker(col, 0.06))
		ball(ctx, "Puff", Vector3.new(0.8, -0.25, 0.1), 1.1, darker(col, 0.06))
		ball(ctx, "Puff", Vector3.new(-0.35, 0.6, 0.25), 1.05, lighter(col, 0.12))
		ball(ctx, "Puff", Vector3.new(0.4, 0.55, 0.3), 0.9, lighter(col, 0.08))
		-- маленькая молния снизу
		rod(ctx, "Zap", Vector3.new(0.05, -0.75, 0.1), Vector3.new(-0.15, -1.1, 0.1), 0.12, acc, MAT.Neon)
		rod(ctx, "Zap", Vector3.new(-0.15, -1.1, 0.1), Vector3.new(0.1, -1.4, 0.1), 0.12, acc, MAT.Neon)
		topY = 1.05
		sparkEars(ctx, Vector3.new(0, topY, 0.1), 0.55, col, acc)
	elseif def.Shape == "star" then
		body = ball(ctx, "Body", Vector3.zero, 1.6, col)
		r = 0.8
		-- пять лучей в плоскости лица (клин + клин = треугольный луч)
		for i = 0, 4 do
			local a = math.pi / 2 + i * (math.pi * 2 / 5)
			local dir = Vector3.new(math.cos(a), math.sin(a), 0)
			local pos = dir * 0.95
			local right = Vector3.new(-dir.Y, dir.X, 0)
			-- ось Y детали = направление луча, ось X — поперёк, Z — толщина
			local cf = CFrame.fromMatrix(pos, right, dir, Vector3.zAxis)
			add(ctx, "Wedge", "Ray", cf * CFrame.new(0, 0, -0.18), Vector3.new(0.75, 0.8, 0.36), col)
			add(ctx, "Wedge", "Ray", cf * CFrame.new(0, 0, 0.18) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.75, 0.8, 0.36), darker(col, 0.08))
			ball(ctx, "RayTip", dir * 1.38, 0.2, acc, MAT.Neon)
		end
		topY = 0.9
	elseif def.Shape == "drop" then
		body = ball(ctx, "Body", Vector3.zero, 1.7, col)
		ball(ctx, "Drop2", Vector3.new(0, 0.42, 0.06), 1.36, col)
		ball(ctx, "Drop3", Vector3.new(0, 0.8, 0.12), 0.96, col)
		ball(ctx, "Drop4", Vector3.new(0, 1.12, 0.17), 0.6, col)
		ball(ctx, "Drop5", Vector3.new(0, 1.36, 0.21), 0.32, col)
		ball(ctx, "DropTip", Vector3.new(0, 1.52, 0.23), 0.16, acc, MAT.Neon)
		-- блик-«капелька» на боку
		ball(ctx, "Gloss", Vector3.new(0.45, 0.45, -0.45), 0.28, lighter(col, 0.7), MAT.Neon, 0.3)
		topY = 1.2
	elseif def.Shape == "crystal" then
		body = add(ctx, "Block", "Body", CFrame.new(), Vector3.new(1.45, 1.35, 1.45), col, MAT.SmoothPlastic)
		body.Reflectance = 0.15
		-- верхний и нижний «шатёр» (огранка)
		add(ctx, "Wedge", "Facet", CFrame.new(0, 0.95, -0.36), Vector3.new(1.45, 0.55, 0.73), lighter(col, 0.12))
		add(ctx, "Wedge", "Facet", CFrame.new(0, 0.95, 0.36) * CFrame.Angles(0, math.pi, 0), Vector3.new(1.45, 0.55, 0.73), lighter(col, 0.05))
		add(ctx, "Wedge", "Facet", CFrame.new(0, -0.95, -0.36) * CFrame.Angles(0, 0, math.pi), Vector3.new(1.45, 0.55, 0.73), darker(col, 0.1))
		add(ctx, "Wedge", "Facet", CFrame.new(0, -0.95, 0.36) * CFrame.Angles(0, math.pi, math.pi), Vector3.new(1.45, 0.55, 0.73), darker(col, 0.15))
		-- осколки-кристаллики по бокам
		for side = -1, 1, 2 do
			local cf = CFrame.new(side * 0.85, 0.35, 0.2) * CFrame.Angles(0, 0, -side * 0.5) * CFrame.Angles(0, math.pi / 4, 0)
			add(ctx, "Block", "Shard", cf, Vector3.new(0.3, 0.8, 0.3), acc, MAT.Neon)
		end
		-- лицо на плоской передней грани
		local fz = -0.725
		for side = -1, 1, 2 do
			local p = Vector3.new(side * 0.33, 0.12, fz)
			if dark then
				ball(ctx, "EyeWhite", p, 0.56, Color3.fromRGB(245, 245, 255))
			end
			ball(ctx, "Eye", p + Vector3.new(0, 0, -0.02), 0.46, BLACK)
			ball(ctx, "Shine", p + Vector3.new(0.08, 0.1, -0.2), 0.16, WHITE, MAT.Neon)
			add(ctx, "Cylinder", "Cheek", CFrame.new(side * 0.5, -0.22, fz - 0.02) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.05, 0.26, 0.26), CHEEK)
		end
		add(ctx, "Block", "Mouth", CFrame.new(0, -0.22, fz - 0.03), Vector3.new(0.2, 0.05, 0.05), Color3.fromRGB(60, 30, 40))
		topY = 1.2
	else -- ball
		body = ball(ctx, "Body", Vector3.zero, 1.7, col)
		-- светлое «брюшко»-блик сверху
		ball(ctx, "Gloss", Vector3.new(-0.38, 0.5, -0.38), 0.34, lighter(col, 0.75), MAT.Neon, 0.35)
		topY = 0.85
		sparkEars(ctx, Vector3.new(0, topY - 0.12, 0), 0.42, col, acc)
	end

	if def.Shape ~= "crystal" then
		face(ctx, faceC, r, dark)
	end
	if def.Shape == "drop" or def.Shape == "star" then
		-- антенка с искоркой
		local a0 = Vector3.new(0, topY, 0.1)
		rod(ctx, "Antenna", a0, a0 + Vector3.new(0.15, 0.45, 0), 0.08, darker(col, 0.3), MAT.SmoothPlastic)
		ball(ctx, "AntennaTip", a0 + Vector3.new(0.17, 0.52, 0), 0.24, acc, MAT.Neon)
	end
	tail(ctx, Vector3.new(0, -0.2, 0.75), acc)

	-- эпические: искорка-звёздочка над головой; легендарные и мифические: нимб
	local rank = Pets.Rarities[def.Rarity].Rank
	if rank >= 4 then
		ring(ctx, "Halo", Vector3.new(0, topY + 0.55, 0.05), 0.55, 0.11, 10, Pets.Rarities[def.Rarity].Color, MAT.Neon)
	elseif rank == 3 then
		add(ctx, "Block", "Sparkle", CFrame.new(0.55, topY + 0.35, 0) * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(0.2, 0.2, 0.08), acc, MAT.Neon)
	end
	if rank >= 5 then
		-- мифические: второе, наклонённое кольцо-орбита
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			ball(ctx, "Orbit", Vector3.new(math.cos(a) * 1.25, math.sin(a) * 0.35, math.sin(a) * 1.25), 0.16, acc, MAT.Neon)
		end
	end

	m.PrimaryPart = body
	weldAll(ctx, body)
	return m
end

----------------------------------------------------------------------
-- Кокон: яйцо из трёх шаров, светящиеся прожилки, тематическое украшение
----------------------------------------------------------------------
function Models.cocoon(id: string): Model
	local def = Pets.Cocoons[id] or Pets.Cocoons.meadow
	local m = Instance.new("Model")
	m.Name = "Cocoon_" .. def.Id
	m:SetAttribute("Cocoon", def.Id)
	local ctx = newCtx(m)
	local col = def.Color
	local glow = lighter(col, 0.55)
	if def.Id == "storm" then
		glow = Color3.fromRGB(255, 215, 90)
	elseif def.Id == "ice" then
		glow = Color3.fromRGB(200, 240, 255)
	end
	-- низ кокона в (0,0,0), центр масс выше
	local body = ball(ctx, "Body", Vector3.new(0, 1.25, 0), 2.5, col)
	ball(ctx, "Upper", Vector3.new(0, 1.95, 0), 2.05, lighter(col, 0.05))
	ball(ctx, "Top", Vector3.new(0, 2.6, 0), 1.35, lighter(col, 0.1))
	ball(ctx, "Peak", Vector3.new(0, 3.05, 0), 0.6, lighter(col, 0.15))
	-- прожилки: изогнутые неоновые меридианы
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.3
		local function at(y: number, rr: number, twist: number): Vector3
			return Vector3.new(math.cos(a + twist) * rr, y, math.sin(a + twist) * rr)
		end
		local p1, p2, p3, p4 = at(0.45, 1.05, 0), at(1.25, 1.27, 0.2), at(2.1, 1.05, 0.38), at(2.85, 0.55, 0.5)
		rod(ctx, "Vein", p1, p2, 0.12, glow, MAT.Neon)
		rod(ctx, "Vein", p2, p3, 0.12, glow, MAT.Neon)
		rod(ctx, "Vein", p3, p4, 0.1, glow, MAT.Neon)
	end
	-- гнёздышко-подставка
	cylY(ctx, "Nest", Vector3.new(0, 0.18, 0), 0.36, 2.2, darker(col, 0.55), MAT.Fabric)
	if def.Id == "meadow" then
		for side = -1, 1, 2 do
			local cf = CFrame.new(side * 0.35, 3.25, 0) * CFrame.Angles(0, 0, -side * 0.7)
			add(ctx, "Wedge", "Leaf", cf, Vector3.new(0.1, 0.7, 0.45), Color3.fromRGB(90, 190, 80))
		end
	elseif def.Id == "ice" then
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			local cf = CFrame.new(math.cos(a) * 0.95, 0.5, math.sin(a) * 0.95) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5) * CFrame.Angles(0, math.pi / 4, 0)
			add(ctx, "Block", "Icicle", cf, Vector3.new(0.35, 1.0, 0.35), Color3.fromRGB(200, 235, 255), MAT.Glass, 0.2)
		end
	else
		-- грозовой: маленькая молния-навершие
		rod(ctx, "Bolt", Vector3.new(0, 3.3, 0), Vector3.new(0.25, 3.7, 0), 0.14, glow, MAT.Neon)
		rod(ctx, "Bolt", Vector3.new(0.25, 3.7, 0), Vector3.new(-0.1, 3.9, 0), 0.14, glow, MAT.Neon)
		rod(ctx, "Bolt", Vector3.new(-0.1, 3.9, 0), Vector3.new(0.15, 4.3, 0), 0.12, glow, MAT.Neon)
	end
	-- корень модели — низ кокона (без поворота)
	local root = add(ctx, "Block", "Root", CFrame.new(), Vector3.new(0.2, 0.2, 0.2), WHITE, MAT.SmoothPlastic, 1)
	m.PrimaryPart = root
	weldAll(ctx, root)
	local _ = body
	return m
end

----------------------------------------------------------------------
-- Фульгурит по спецификации Fulgurite.generate: стекло, сердцевина, основание, кончики
----------------------------------------------------------------------
function Models.fulgurite(spec: Fulgurite.Spec, glassColor: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Fulgurite"
	m:SetAttribute("Shape", spec.Shape)
	m:SetAttribute("Rarity", spec.Rarity)
	local ctx = newCtx(m)
	local root = add(ctx, "Block", "Root", CFrame.new(), Vector3.new(0.2, 0.2, 0.2), WHITE, MAT.SmoothPlastic, 1)
	local coreColor = lighter(glassColor, 0.45)
	local baseColor = Color3.fromRGB(46, 40, 50)
	for _, ps in spec.Parts do
		local kind: PartKind = if ps.Shape == "Ball" then "Ball" elseif ps.Shape == "Cylinder" then "Cylinder" else "Block"
		if ps.Kind == "glass" then
			add(ctx, kind, "Glass", ps.CFrame, ps.Size, glassColor, MAT.Glass, 0.25)
		elseif ps.Kind == "core" then
			add(ctx, kind, "Core", ps.CFrame, ps.Size, coreColor, MAT.Neon)
		elseif ps.Kind == "base" then
			add(ctx, kind, "Base", ps.CFrame, ps.Size, baseColor, MAT.Basalt)
		else
			add(ctx, kind, "Tip", ps.CFrame, ps.Size, lighter(glassColor, 0.6), MAT.Neon)
		end
	end
	m.PrimaryPart = root
	weldAll(ctx, root)
	return m
end

----------------------------------------------------------------------
-- Маленькая подстанция (для витрин и ViewportFrame; на карте стоит большая из генератора)
----------------------------------------------------------------------
function Models.station(): Model
	local m = Instance.new("Model")
	m.Name = "Station"
	local ctx = newCtx(m)
	local root = add(ctx, "Block", "Root", CFrame.new(), Vector3.new(0.2, 0.2, 0.2), WHITE, MAT.SmoothPlastic, 1)
	local metal = Color3.fromRGB(96, 110, 120)
	local glow = Color3.fromRGB(110, 200, 255)
	cylY(ctx, "Pad", Vector3.new(0, 0.15, 0), 0.3, 6, Color3.fromRGB(60, 64, 76), MAT.Metal)
	cylY(ctx, "PadGlow", Vector3.new(0, 0.12, 0), 0.26, 6.3, glow, MAT.Neon)
	add(ctx, "Block", "Box", CFrame.new(0, 1.6, 3.6), Vector3.new(3, 2.6, 2), metal, MAT.Metal)
	for i = -1, 1 do
		local x = i * 0.9
		for k = 0, 2 do
			cylY(ctx, "Insulator", Vector3.new(x, 3.05 + k * 0.3, 3.6), 0.18, 0.55 - k * 0.08, Color3.fromRGB(230, 220, 200), MAT.SmoothPlastic)
		end
		ball(ctx, "Spark", Vector3.new(x, 3.95, 3.6), 0.3, glow, MAT.Neon)
	end
	add(ctx, "Block", "Stripe", CFrame.new(0, 1.6, 2.58), Vector3.new(3.02, 0.25, 0.05), glow, MAT.Neon)
	m.PrimaryPart = root
	weldAll(ctx, root)
	return m
end

return Models
