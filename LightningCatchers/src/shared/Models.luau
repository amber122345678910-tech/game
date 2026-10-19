--!strict
-- Строители моделей из примитивов: громоотвод (Tool), банка, питомцы-искрята, коконы, фульгуриты, подстанция,
-- шаровая молния (босс события) и рецепты тучки удара и осколков (их пул держит StrikeController).
-- Стиль — docs/STYLE.md §6.18 и §7: у питомцев одна мягкая главная масса и плоские детали (глаза-диски, щёки-диски),
-- острое, гранёное и неоновое — только у энергии (кончики, гребни, трещины, кристаллы).
-- Работают на сервере, клиенте и в Lune-превью (tools/preview/models_sheet.luau).
-- Каждая функция возвращает НОВЫЙ экземпляр без родителя. Все детали: Anchored = false, сварены с PrimaryPart
-- (WeldConstraint), Massless, без коллизий/запросов/касаний и без теней — их цепляют к персонажу или двигают кодом.
-- Исключение — шаровая молния: детали якорные и не сварены, их по отдельности крутит EventFX.
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
	neon: number, -- сколько неоновых деталей ещё можно (у питомца всего не больше 3)
}

local MAT = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(28, 22, 48) -- черты лица: не чистый чёрный
local CREAM = Color3.fromRGB(255, 250, 240) -- блики
local BLUSH = Color3.fromRGB(255, 120, 150) -- румянец (смешивается с цветом тела)
local TONGUE = Color3.fromRGB(255, 120, 140)
local CROWN_GOLD = Color3.fromRGB(255, 196, 40)
local PORCELAIN = Color3.fromRGB(236, 226, 206) -- изоляторы
local COPPER = Color3.fromRGB(204, 116, 64)
local RAD = math.rad
local SQRT3 = math.sqrt(3)
local GEM_TILT = CFrame.Angles(RAD(35.264), 0, RAD(45)) -- GemCube: куб на вершине, три грани вверх
-- Высокий угол CornerWedge считаем локальным (+X, +Y, −Z), как tools/lib/builder.luau (B.CORNER_YAW)
-- и офлайн-рендер. Если в Studio пирамиды выйдут «звёздами» — довернуть здесь (кратно π/2).
local CORNER_YAW = 0

local function newCtx(root: Instance): Ctx
	return { root = root, parts = {}, neon = math.huge }
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

-- Вертикальный цилиндр (ось Y): центр pos, высота h, диаметр d
local function cylY(ctx: Ctx, name: string, pos: Vector3, h: number, d: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	return add(ctx, "Cylinder", name, CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(h, d, d), color, material, transparency)
end

-- Единичный вектор, перпендикулярный x, как можно ближе к hint
local function perpTo(x: Vector3, hint: Vector3): Vector3
	local z = hint - x * hint:Dot(x)
	if z.Magnitude < 1e-4 then
		local alt = if math.abs(x.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
		z = alt - x * alt:Dot(x)
	end
	return z.Unit
end

-- Рамка по двум осям (третья — X × Y, правая тройка)
local function frame(pos: Vector3, x: Vector3, y: Vector3): CFrame
	return CFrame.fromMatrix(pos, x, y, x:Cross(y))
end

-- Брусок от a до b: длина по X, ширина w, толщина t; facing — куда смотрит грань толщины (по умолчанию к −Z)
local function bar(ctx: Ctx, name: string, a: Vector3, b: Vector3, w: number, t: number, color: Color3, material: Enum.Material?, facing: Vector3?): BasePart
	local d = b - a
	local len = d.Magnitude
	local x = if len > 1e-6 then d / len else Vector3.xAxis
	local z = perpTo(x, facing or Vector3.new(0, 0, -1))
	local y = z:Cross(x)
	return add(ctx, "Block", name, CFrame.fromMatrix((a + b) / 2, x, y, z), Vector3.new(math.max(len, 0.02), w, t), color, material)
end

-- Плоский диск (цилиндр с осью по нормали n): центр pos, диаметр d, толщина thick
local function disc(ctx: Ctx, name: string, pos: Vector3, n: Vector3, d: number, thick: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local u = n.Unit
	local cf = Geom.axisCFrame(pos - u * (thick / 2), pos + u * (thick / 2))
	return add(ctx, "Cylinder", name, cf, Vector3.new(thick, d, d), color, material, transparency)
end

-- GemCube: куб на вершине (искры, кончики, камешки)
local function gem(ctx: Ctx, name: string, pos: Vector3, s: number, color: Color3, material: Enum.Material?, yaw: number?): BasePart
	return add(ctx, "Block", name, CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0) * GEM_TILT, Vector3.new(s, s, s), color, material)
end

-- Pyramid4: четырёхгранная пирамида из 4 CornerWedge. base — центр основания, ось Y рамки смотрит к вершине
local function pyramid4(ctx: Ctx, name: string, base: CFrame, w: number, h: number, color: Color3, material: Enum.Material?, transparency: number?): { BasePart }
	local out = {}
	for q = 0, 3 do
		local cf = base * CFrame.Angles(0, q * math.pi / 2 + CORNER_YAW, 0) * CFrame.new(-w / 4, h / 2, w / 4)
		table.insert(out, add(ctx, "CornerWedge", name, cf, Vector3.new(w / 2, h, w / 2), color, material, transparency))
	end
	return out
end

-- HexPlate: шестиугольная плита из 3 брусков (R — описанный радиус, t — толщина), cf — центр
local function hexPlate(ctx: Ctx, name: string, cf: CFrame, R: number, t: number, color: Color3, material: Enum.Material?, transparency: number?): { BasePart }
	local out = {}
	for q = 0, 2 do
		table.insert(out, add(ctx, "Block", name, cf * CFrame.Angles(0, q * math.pi / 3, 0), Vector3.new(R, t, R * SQRT3), color, material, transparency))
	end
	return out
end

-- Ломаная из брусков по точкам (зигзаги: хвосты, трещины, молнии)
local function chain(ctx: Ctx, name: string, pts: { Vector3 }, w: number, color: Color3, material: Enum.Material?, facing: Vector3?, lastColor: Color3?, lastMaterial: Enum.Material?): { BasePart }
	local out = {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dir = (b - a).Unit
		-- небольшой нахлёст, чтобы на изломе не было щели
		local isLast = i == #pts - 1
		local p = bar(ctx, name, a - dir * w * 0.45, b + dir * (if isLast then 0 else w * 0.45), w, w, if isLast and lastColor then lastColor else color, if isLast and lastMaterial then lastMaterial else material, facing)
		table.insert(out, p)
	end
	return out
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

local function luminance(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(WHITE, k)
end

-- Сдвиг оттенка h (градусы) к target не больше чем на deg по кратчайшей дуге
local function hueToward(h: number, target: number, deg: number): number
	local d = ((target - h + 540) % 360) - 180
	if math.abs(d) <= deg then
		return target % 360
	end
	return (h + (if d > 0 then deg else -deg)) % 360
end

-- Тень и свет со сдвигом оттенка (формула STYLE §3.1): тень холоднее и темнее, свет теплее и светлее
local function shade(c: Color3, k: number): Color3
	local h, s, v = c:ToHSV()
	h = hueToward(h * 360, 255, 16 * k) / 360
	return Color3.fromHSV(h, math.min(1, s * (1 + 0.06 * k) + 0.02 * k), math.max(0, v * (1 - 0.33 * k)))
end

local function tint(c: Color3, k: number): Color3
	local h, s, v = c:ToHSV()
	h = hueToward(h * 360, 52, 14 * k) / 360
	return Color3.fromHSV(h, math.max(0, s * (1 - 0.18 * k)), math.min(1, v * (1 + 0.16 * k) + 0.04 * k))
end

-- Неон по бюджету: n деталей сразу (пара ушек — 2). Не хватает — та же деталь без свечения.
local function glow(ctx: Ctx, n: number): Enum.Material
	if ctx.neon >= n then
		ctx.neon -= n
		return MAT.Neon
	end
	return MAT.SmoothPlastic
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
-- Громоотвод: Tool с деталью Handle (держится вертикально: ось стержня = +Y ручки) и неоновым "Tip".
-- У каждого уровня свой силуэт «головы» в треугольной стилистике (STYLE §6.18): крюк-шип, двойной изолятор,
-- трезубец, тор-шестиугольник, парящий кристалл, корона с молнией. Голова в 1.3 раза крупнее прежней.
-- Неоновые детали сервер перекрашивает в цвет перезапуска (PlayerService), Tip подсвечивает CharacterFX.
----------------------------------------------------------------------
export type RodStyle = {
	Name: string, -- исходник для Loc.t (переводы — в Strings/Shared.luau)
	Shaft: Color3,
	ShaftMaterial: Enum.Material,
	Trim: Color3,
	Grip: Color3,
	Glow: Color3,
}

Models.RodStyles = {
	[0] = { Name = "Медный", Shaft = Color3.fromRGB(204, 116, 64), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(150, 76, 48), Grip = Color3.fromRGB(96, 64, 44), Glow = Color3.fromRGB(120, 210, 255) },
	[1] = { Name = "Серебряный", Shaft = Color3.fromRGB(200, 206, 216), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(150, 160, 176), Grip = Color3.fromRGB(50, 56, 70), Glow = Color3.fromRGB(150, 220, 255) },
	[2] = { Name = "Золотой", Shaft = Color3.fromRGB(240, 196, 70), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(255, 232, 140), Grip = Color3.fromRGB(120, 40, 40), Glow = Color3.fromRGB(255, 225, 120) },
	[3] = { Name = "Тесла", Shaft = Color3.fromRGB(70, 80, 100), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(204, 116, 64), Grip = Color3.fromRGB(30, 34, 44), Glow = Color3.fromRGB(90, 200, 255) },
	[4] = { Name = "Грозовой", Shaft = Color3.fromRGB(60, 44, 96), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(180, 130, 255), Grip = Color3.fromRGB(30, 22, 48), Glow = Color3.fromRGB(190, 120, 255) },
	[5] = { Name = "Перунов", Shaft = Color3.fromRGB(30, 26, 36), ShaftMaterial = MAT.Metal, Trim = Color3.fromRGB(255, 196, 60), Grip = Color3.fromRGB(110, 20, 24), Glow = Color3.fromRGB(255, 190, 60) },
} :: { [number]: RodStyle }

-- Зубец короны: квадрат, повёрнутый на 45° (наружу торчит равнобедренный треугольник).
-- center — центр квадрата, out — наружу (горизонталь), lean — наклон наружу (рад)
local function crownTooth(ctx: Ctx, name: string, center: Vector3, out: Vector3, side: number, thick: number, lean: number, color: Color3, material: Enum.Material?): BasePart
	local o = Vector3.new(out.X, 0, out.Z).Unit
	local tg = Vector3.new(-o.Z, 0, o.X)
	local up = Vector3.yAxis * math.cos(lean) + o * math.sin(lean)
	local c45 = math.cos(math.pi / 4)
	local x = tg * c45 + up * c45
	local y = -tg * c45 + up * c45
	return add(ctx, "Block", name, frame(center, x, y), Vector3.new(side, side, thick), color, material)
end

function Models.rod(tier: number): Tool
	local t = math.clamp(math.floor(tier), 0, 5)
	local st = Models.RodStyles[t]
	local tool = Instance.new("Tool")
	-- имя — для поиска (PlayerService.RodName); подсказку никто не видит: свой Backpack выключен (Main.client)
	tool.Name = "Громоотвод" -- noloc
	tool.ToolTip = st.Name .. " громоотвод" -- noloc
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	-- хват: ручка в ладони, стержень вверх (ось +Y ручки = «вверх» кисти)
	tool.Grip = CFrame.new(0, -0.4, 0)
	tool:SetAttribute("Tier", t)
	local ctx = newCtx(tool)
	local H = 1.3 -- масштаб головы

	-- ручка (обмотка), гранёное навершие и стержень
	local handle = add(ctx, "Block", "Handle", CFrame.new(), Vector3.new(0.42, 2.2, 0.42), st.Grip, MAT.Fabric)
	cylY(ctx, "Wrap", Vector3.new(0, 0.55, 0), 0.25, 0.52, st.Trim, MAT.Metal)
	cylY(ctx, "Wrap", Vector3.new(0, -0.55, 0), 0.25, 0.52, st.Trim, MAT.Metal)
	gem(ctx, "Pommel", Vector3.new(0, -1.32, 0), 0.4, st.Trim, MAT.Metal, RAD(45))
	local top = 5.6 + t * 0.15
	cylY(ctx, "Shaft", Vector3.new(0, (1.1 + top) / 2, 0), top - 1.1, 0.34, st.Shaft, st.ShaftMaterial)
	cylY(ctx, "Collar", Vector3.new(0, 1.2, 0), 0.3, 0.8, st.Trim, MAT.Metal)

	local tipPos: Vector3
	local tipSize = (0.36 + t * 0.03) * H
	if t == 0 then
		-- медный «крюк-шип»: виток проволоки, гранёный шип и загнутый крюк сбоку
		cylY(ctx, "Coil", Vector3.new(0, top - 2.1, 0), 0.16, 0.52, st.Trim, MAT.Metal)
		cylY(ctx, "Coil", Vector3.new(0, top - 1.75, 0), 0.16, 0.52, st.Trim, MAT.Metal)
		cylY(ctx, "Socket", Vector3.new(0, top + 0.05, 0), 0.3, 0.52, st.Trim, MAT.Metal)
		local spikeH = 1.0 * H
		pyramid4(ctx, "Spike", CFrame.new(0, top + 0.2, 0) * CFrame.Angles(0, RAD(45), 0), 0.46 * H, spikeH, st.Shaft, MAT.Metal)
		chain(ctx, "Hook", {
			Vector3.new(0, top + 0.3, 0),
			Vector3.new(0.42 * H, top + 0.62 * H, 0),
			Vector3.new(0.3 * H, top + 1.0 * H, 0),
		}, 0.15, st.Trim, MAT.Metal)
		tipPos = Vector3.new(0, top + 0.2 + spikeH + 0.05, 0)
	elseif t == 1 then
		-- серебряный «двойной изолятор»: две фарфоровые юбки, светящийся поясок и тонкий шпиль
		cylY(ctx, "Insulator", Vector3.new(0, top - 0.95, 0), 0.24, 0.92 * H, PORCELAIN, MAT.SmoothPlastic)
		cylY(ctx, "GlowBand", Vector3.new(0, top - 0.62, 0), 0.14, 0.44, st.Glow, MAT.Neon)
		cylY(ctx, "Insulator", Vector3.new(0, top - 0.3, 0), 0.24, 0.72 * H, PORCELAIN, MAT.SmoothPlastic)
		local spikeH = 1.35 * H
		pyramid4(ctx, "Spike", CFrame.new(0, top - 0.15, 0) * CFrame.Angles(0, RAD(45), 0), 0.36 * H, spikeH, st.Shaft, MAT.Metal)
		tipPos = Vector3.new(0, top - 0.15 + spikeH + 0.04, 0)
	elseif t == 2 then
		-- золотой «трезубец»: V-образная перекладина, два боковых зубца с огоньками и высокий средний шип
		cylY(ctx, "Cross", Vector3.new(0, top, 0), 0.3, 0.7, st.Trim, MAT.Metal)
		for _, s in { -1, 1 } do
			local shoulder = Vector3.new(s * 0.72 * H, top + 0.32 * H, 0)
			bar(ctx, "Bar", Vector3.new(0, top + 0.02, 0), shoulder, 0.22, 0.22, st.Shaft, MAT.Metal)
			local prongTop = Vector3.new(s * 0.8 * H, top + 1.15 * H, 0)
			bar(ctx, "Prong", shoulder - Vector3.new(0, 0.1, 0), prongTop, 0.2, 0.2, st.Shaft, MAT.Metal)
			gem(ctx, "ProngTip", prongTop + Vector3.new(0, 0.12, 0), 0.26 * H, st.Glow, MAT.Neon, RAD(45))
		end
		local spikeH = 1.25 * H
		pyramid4(ctx, "Spike", CFrame.new(0, top + 0.15, 0) * CFrame.Angles(0, RAD(45), 0), 0.42 * H, spikeH, st.Shaft, MAT.Metal)
		tipPos = Vector3.new(0, top + 0.15 + spikeH + 0.04, 0)
	elseif t == 3 then
		-- тесла: медная катушка с двумя светящимися обмотками и тор-шестиугольник с огоньком в центре
		cylY(ctx, "Coil", Vector3.new(0, top - 1.2, 0), 1.6, 0.74, st.Trim, MAT.Metal)
		cylY(ctx, "CoilGlow", Vector3.new(0, top - 1.55, 0), 0.12, 0.8, st.Glow, MAT.Neon)
		cylY(ctx, "CoilGlow", Vector3.new(0, top - 0.85, 0), 0.12, 0.8, st.Glow, MAT.Neon)
		local R = 0.72 * H
		local y = top + 0.32
		for k = 0, 5 do
			local a0, a1 = k * math.pi / 3, (k + 1) * math.pi / 3
			bar(ctx, "Torus", Vector3.new(math.cos(a0) * R, y, math.sin(a0) * R), Vector3.new(math.cos(a1) * R, y, math.sin(a1) * R), 0.3, 0.3, Color3.fromRGB(196, 202, 216), MAT.Metal, Vector3.yAxis)
		end
		-- три спицы к центру
		for k = 0, 2 do
			local a = k * 2 * math.pi / 3 + math.pi / 6
			bar(ctx, "Spoke", Vector3.new(0, top + 0.05, 0), Vector3.new(math.cos(a) * R * 0.92, y, math.sin(a) * R * 0.92), 0.12, 0.12, st.Trim, MAT.Metal)
		end
		tipPos = Vector3.new(0, y + 0.42, 0)
	elseif t == 4 then
		-- грозовой: когти-ухват и парящий над ними гранёный кристалл с огоньком внутри
		for _, s in { -1, 1 } do
			chain(ctx, "Claw", {
				Vector3.new(0, top - 0.05, 0),
				Vector3.new(s * 0.5 * H, top + 0.42 * H, 0),
				Vector3.new(s * 0.3 * H, top + 0.9 * H, 0),
			}, 0.16, st.Trim, MAT.Metal)
		end
		local cy = top + 1.45 * H
		local crystal = lighter(st.Glow, 0.35)
		pyramid4(ctx, "Crystal", CFrame.new(0, cy, 0) * CFrame.Angles(0, RAD(45), 0), 0.56 * H, 0.75 * H, crystal, MAT.Glass, 0.2)
		pyramid4(ctx, "Crystal", CFrame.new(0, cy, 0) * CFrame.Angles(0, 0, math.pi) * CFrame.Angles(0, RAD(45), 0), 0.56 * H, 0.55 * H, crystal, MAT.Glass, 0.2)
		tipPos = Vector3.new(0, cy + 0.05, 0)
		tipSize = 0.32 * H
	else
		-- Перунов: золотая корона из зубцов на шестигранном ободе и зигзаг-молния, бьющая вверх
		cylY(ctx, "Band", Vector3.new(0, 2.6, 0), 0.2, 0.44, st.Trim, MAT.Metal)
		cylY(ctx, "Band", Vector3.new(0, 4.0, 0), 0.2, 0.44, st.Trim, MAT.Metal)
		local R = 0.5 * H
		hexPlate(ctx, "Crown", CFrame.new(0, top + 0.1, 0), R, 0.32, st.Trim, MAT.Metal)
		for k = 0, 4 do
			local a = k * 2 * math.pi / 5 + RAD(9)
			local o = Vector3.new(math.sin(a), 0, -math.cos(a))
			crownTooth(ctx, "Spire", Vector3.new(0, top + 0.3, 0) + o * (R * 0.82), o, 0.42 * H, 0.12, RAD(10), st.Trim, MAT.Metal)
		end
		local z1 = Vector3.new(0, top + 0.25, 0)
		local z2 = Vector3.new(0.34 * H, top + 0.95 * H, 0)
		local z3 = Vector3.new(-0.22 * H, top + 1.25 * H, 0)
		local z4 = Vector3.new(0.12 * H, top + 2.0 * H, 0)
		chain(ctx, "Bolt", { z1, z2, z3, z4 }, 0.2, st.Glow, MAT.Neon)
		tipPos = z4 + Vector3.new(0, 0.18, 0)
	end
	-- неоновый кончик-кристалл: его свечение меняет CharacterFX
	gem(ctx, "Tip", tipPos, tipSize, st.Glow, MAT.Neon, RAD(45))
	weldAll(ctx, handle)
	return tool
end

----------------------------------------------------------------------
-- Банка: стекло, металлические крышки, неоновое ядро "Core" (с выключенным PointLight) и зигзаг-нить
-- перед ядром (видна на светящемся заряде). Атрибуты модели: CoreHeight (полная высота ядра),
-- CoreBottom (низ ядра по Y в локальных координатах)
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
	local coreD = d - 0.32
	local core = cylY(ctx, "Core", Vector3.new(0, 0, 0), coreH, coreD, Color3.fromRGB(110, 200, 255), MAT.Neon)
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Enabled = false
	light.Range = 10
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(110, 200, 255)
	light.Parent = core
	-- зигзаг-нить: между ядром и стеклом на внешней стороне (ремень — сзади, +Z)
	local fz = -(coreD / 2 + 0.07)
	chain(ctx, "Filament", {
		Vector3.new(0.18, -coreH / 2 + 0.2, fz),
		Vector3.new(-0.16, 0.05, fz),
		Vector3.new(0.12, coreH / 2 - 0.15, fz),
	}, 0.09, Color3.fromRGB(235, 248, 255), MAT.Neon, Vector3.new(0, 0, -1))
	cylY(ctx, "CapTop", Vector3.new(0, h / 2 + 0.12, 0), 0.3, d + 0.12, metal, MAT.Metal)
	cylY(ctx, "CapBottom", Vector3.new(0, -h / 2 - 0.12, 0), 0.3, d + 0.12, metal, MAT.Metal)
	-- электрод: медный штырь с гранёным наконечником
	cylY(ctx, "Electrode", Vector3.new(0, h / 2 + 0.52, 0), 0.55, 0.14, COPPER, MAT.Metal)
	gem(ctx, "ElectrodeTip", Vector3.new(0, h / 2 + 0.86, 0), 0.26, COPPER, MAT.Metal, RAD(45))
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
-- Питомцы-искрята (STYLE §7). Пять силуэтов по Pets.Shape:
--   ball — «мочи-искра»: шар на плоском донышке, ушки-молнии с огоньками, хвост-зигзаг;
--   cloud — «тучка»: гранёный шестигранник с лицом и три клуба-шестигранника за ним, плоское тёмное брюхо, дождик-молния;
--   star — «звезда-печенька»: толстая сердцевина с плоским лицом, пять лучей из двух клиньев (светлая и тёмная грань);
--   drop — «капелька»: шар и гранёный кончик, загнутый назад, блик-наклейка;
--   crystal — «самоцвет»: бипирамида, глаза-бруски.
-- Общий набор лица FaceKit: глаза-диски цвета INK с двумя кремовыми бликами (у обоих глаз в одну сторону),
-- маленький рот, щёки-диски своего оттенка. Шаров на лице нет. Неона не больше 3 деталей на питомца.
-- Знаки редкости — треугольным языком: редкий — искра у уха, эпический — гребешок-молния,
-- легендарный — корона-зигзаг, мифический — корона и три искры на наклонной орбите.
----------------------------------------------------------------------

-- Черты вида (только вид; игровые данные — в Pets.Kinds)
type Look = {
	ears: string?, -- "spark" (ушки-молнии) | "none"
	eyes: string?, -- "disc" | "happy" (^ ^) | "wink"
	mouth: string?, -- "v" | "open" | "o"
	brows: boolean?, -- решительные бровки
	tail: boolean?,
	roll: number?, -- крен (градусы)
	tip: number?, -- изгиб кончика капли назад (градусы)
	twist: number?, -- закрутка кончика капли (градусы)
	low: number?, -- высота нижней пирамиды самоцвета
}

local LOOKS: { [string]: Look } = {
	iskorka = {},
	kapelka = { mouth = "open" },
	luchik = { mouth = "open" },
	tuchka = { eyes = "happy" },
	sharovik = { ears = "none", mouth = "open", brows = true },
	zarnitsa = { mouth = "open", roll = -8 },
	gromik = { mouth = "open" },
	snezhok = { ears = "none", eyes = "happy", mouth = "o" },
	iney = {},
	severok = { eyes = "happy", roll = -6 },
	sosulka = { low = 1.2, mouth = "o" },
	buran = { mouth = "o", brows = true },
	siyanie = { eyes = "happy", mouth = "open" },
	polyarnik = { mouth = "open" },
	grozik = {},
	vihr = { eyes = "happy", tip = 24, twist = 25 },
	tesla = { brows = true },
	strelka = { eyes = "wink", roll = 16 },
	gromovik = { brows = true },
	carmolniya = { mouth = "open", eyes = "wink" },
	perunchik = { ears = "none", tail = false },
}

local SHAPE_LOOK: { [string]: Look } = {
	ball = { ears = "spark", eyes = "disc", mouth = "v", tail = true },
	cloud = { eyes = "disc", mouth = "v" },
	star = { eyes = "disc", mouth = "v", roll = 8 },
	drop = { eyes = "disc", mouth = "v", tip = 12 },
	crystal = { eyes = "disc", mouth = "v" },
}

local function lookOf(def: Pets.PetDef): Look
	local base = SHAPE_LOOK[def.Shape] or SHAPE_LOOK.ball
	local own = LOOKS[def.Id] or {}
	local out: Look = {}
	for k, v in base :: any do
		(out :: any)[k] = v
	end
	for k, v in own :: any do
		(out :: any)[k] = v
	end
	return out
end

-- Поверхность лица: для направления n (перёд −Z) — точка на поверхности и наружная нормаль
type Surface = (Vector3) -> (Vector3, Vector3)

local function sphereSurface(c: Vector3, r: number): Surface
	return function(n: Vector3): (Vector3, Vector3)
		local u = n.Unit
		return c + u * r, u
	end
end

-- Плоское лицо (звезда): направления проецируются на плоскость z = frontZ, s — «радиус» лица
local function planeSurface(c: Vector3, s: number, frontZ: number): Surface
	return function(n: Vector3): (Vector3, Vector3)
		return Vector3.new(c.X + n.X * s, c.Y + n.Y * s, frontZ), Vector3.new(0, 0, -1)
	end
end

-- Касательные в точке лица: «вверх» и «влево от зрителя» (зритель смотрит питомцу в лицо)
local function faceAxes(nn: Vector3): (Vector3, Vector3)
	local up = perpTo(nn, Vector3.yAxis)
	return up, nn:Cross(up)
end

type FaceOpts = {
	eyes: string,
	mouth: string,
	brows: boolean,
	dark: boolean, -- тёмное тело: ободок за глазом и светлые рот и бровки
	col: Color3,
	ring: Color3, -- цвет ободка (тёмное тело)
}

-- Глаз-диск с двумя бликами (большой вверх-влево от зрителя, малый напротив)
local function eyeDisc(ctx: Ctx, surf: Surface, r: number, side: number, o: FaceOpts)
	local p, nn = surf(Vector3.new(0.40 * side, -0.06, -0.92))
	local D = 0.62 * r
	local up, left = faceAxes(nn)
	local c = p - nn * 0.01
	if o.dark then
		disc(ctx, "EyeRing", c - nn * 0.012, nn, D * 1.22, 0.07, o.ring)
	end
	disc(ctx, "Eye", c, nn, D, 0.07, INK)
	disc(ctx, "Shine", c + nn * 0.045 + left * (0.2 * D) + up * (0.22 * D), nn, 0.4 * D, 0.03, CREAM)
	disc(ctx, "Shine", c + nn * 0.045 - left * (0.22 * D) - up * (0.2 * D), nn, 0.18 * D, 0.03, CREAM)
end

-- Зажмуренный глаз «^» из двух брусочков
local function eyeHappy(ctx: Ctx, surf: Surface, r: number, side: number, color: Color3)
	local p, nn = surf(Vector3.new(0.40 * side, -0.04, -0.92))
	local up, left = faceAxes(nn)
	local k = r / 0.85
	local apex = p + nn * 0.015 + up * (0.07 * k)
	local L = 0.2 * k
	for _, s in { 1, -1 } do
		local dir = left * (s * math.cos(RAD(38))) - up * math.sin(RAD(38))
		bar(ctx, "Eye", apex - dir * 0.025, apex + dir * L, 0.065 * k, 0.045, color, nil, nn)
	end
end

local function faceKit(ctx: Ctx, surf: Surface, r: number, o: FaceOpts)
	local feature = if o.dark then CREAM else INK
	local k = r / 0.85
	for _, side in { 1, -1 } do
		local happy = o.eyes == "happy" or (o.eyes == "wink" and side == -1)
		if happy then
			eyeHappy(ctx, surf, r, side, if o.dark then CREAM else INK)
		else
			eyeDisc(ctx, surf, r, side, o)
		end
		if o.brows then
			-- бровка: внутренний конец ниже — решительный вид
			local p, nn = surf(Vector3.new(0.40 * side, 0.3, -0.87))
			local up, left = faceAxes(nn)
			local inner = -left * side
			local c = p + nn * 0.012
			bar(ctx, "Brow", c + inner * (0.13 * k) - up * (0.04 * k), c - inner * (0.12 * k) + up * (0.03 * k), 0.06 * k, 0.04, feature, nil, nn)
		end
	end
	-- рот
	local mp, mn = surf(Vector3.new(0, -0.32, -0.95))
	local up, left = faceAxes(mn)
	local mc = mp + mn * 0.005
	if o.mouth == "open" then
		disc(ctx, "Mouth", mc, mn, 0.21 * k, 0.04, feature)
		disc(ctx, "Tongue", mc + mn * 0.012 - up * (0.04 * k), mn, 0.11 * k, 0.03, TONGUE)
	elseif o.mouth == "o" then
		disc(ctx, "Mouth", mc, mn, 0.13 * k, 0.04, feature)
	else
		local bottom = mc - up * (0.03 * k)
		for _, s in { 1, -1 } do
			local dir = left * (s * math.cos(RAD(30))) + up * math.sin(RAD(30))
			bar(ctx, "Mouth", bottom - dir * 0.02, bottom + dir * (0.15 * k), 0.05 * k, 0.04, feature, nil, mn)
		end
	end
	-- щёки: свой оттенок румянца у каждого вида
	local blush = o.col:Lerp(BLUSH, 0.55)
	for _, side in { 1, -1 } do
		local p, nn = surf(Vector3.new(0.62 * side, -0.24, -0.75))
		disc(ctx, "Cheek", p - nn * 0.005, nn, 0.33 * r, 0.03, blush)
	end
end

local function faceOpts(def: Pets.PetDef, look: Look): FaceOpts
	return {
		eyes = look.eyes or "disc",
		mouth = look.mouth or "v",
		brows = look.brows == true,
		dark = luminance(def.Color) < 0.3,
		col = def.Color,
		-- у совсем тёмного тела tint почти не светлеет: ободок — цветом акцента
		ring = if luminance(def.Color) < 0.15 then lighter(def.Color, 0.32) else tint(def.Color, 0.6),
	}
end

-- Где у питомца знаки редкости
type Anchors = {
	head: Vector3, -- центр «головы» (сфера головы для гребешка)
	headR: number,
	crown: Vector3, -- центр кольца короны
	crownR: number,
	ear: Vector3, -- где парит искра редкого (у правого уха)
	orbit: Vector3, -- центр наклонной орбиты мифических
	orbitR: number,
}

-- Сколько неона забирают знаки редкости (остальное — телу, всего не больше 3)
local function marksNeon(rank: number): number
	if rank == 2 or rank == 4 then
		return 1
	elseif rank >= 5 then
		return 2
	end
	return 0
end

-- Гребешок-молния: три клина-зубца на макушке «пилой» (вертикальная грань у всех с одной стороны),
-- средний выше; треугольники смотрят вперёд, весь гребешок чуть зачёсан назад
local function crest(ctx: Ctx, a: Anchors, color: Color3)
	local teeth = {
		{ x = -0.2, w = 0.24, h = 0.36 },
		{ x = 0.02, w = 0.28, h = 0.52 },
		{ x = 0.24, w = 0.24, h = 0.38 },
	}
	local back = RAD(14)
	for _, tt in teeth do
		local dir = Vector3.new(tt.x * 0.9, 1, 0.12).Unit
		local base = a.head + dir * (a.headR - 0.08)
		-- Y — вверх с наклоном назад и чуть наружу, Z — вбок (вертикальная грань клина), X — толщина вперёд-назад
		local y = (Vector3.new(tt.x * 0.6, math.cos(back), math.sin(back))).Unit
		local z = perpTo(y, Vector3.new(-1, 0, 0))
		add(ctx, "Wedge", "Crest", CFrame.fromMatrix(base + y * (tt.h / 2) - z * (tt.w / 2), y:Cross(z), y, z), Vector3.new(0.14, tt.h, tt.w), color)
	end
end

-- Корона-зигзаг: пять квадратных зубцов внахлёст, на переднем — неоновая искра
local function crown(ctx: Ctx, a: Anchors)
	local side = 0.36
	for k = 0, 4 do
		local ang = k * 2 * math.pi / 5
		local o = Vector3.new(math.sin(ang), 0, -math.cos(ang))
		crownTooth(ctx, "Crown", a.crown + o * a.crownR, o, side, 0.08, RAD(14), CROWN_GOLD, MAT.Metal)
	end
	gem(ctx, "CrownGem", a.crown + Vector3.new(0, -0.02, -(a.crownR + 0.07)), 0.18, Color3.fromRGB(255, 120, 160), MAT.Neon)
end

local function rarityMarks(ctx: Ctx, def: Pets.PetDef, rank: number, a: Anchors)
	local rcol = Pets.Rarities[def.Rarity].Color
	if rank == 2 then
		gem(ctx, "RareSpark", a.ear, 0.24, rcol, MAT.Neon, RAD(20))
	elseif rank == 3 then
		crest(ctx, a, def.Accent)
	elseif rank >= 4 then
		crown(ctx, a)
		if rank >= 5 then
			-- три искры на наклонной орбите: большая светится, две другие — блестящие
			local tilt = CFrame.new(a.orbit) * CFrame.Angles(RAD(-18), 0, RAD(22))
			-- углы на орбите — по бокам и сзади, чтобы искры не заслоняли мордочку
			local list = { { 20, 0.3 }, { 150, 0.22 }, { 85, 0.16 } }
			for i, e in list do
				local ang = RAD(e[1])
				local pos = (tilt * CFrame.new(math.cos(ang) * a.orbitR, 0, math.sin(ang) * a.orbitR)).Position
				local p = gem(ctx, "Orbit", pos, e[2], if i == 1 then def.Accent else tint(def.Accent, 0.3), if i == 1 then MAT.Neon else MAT.SmoothPlastic, ang)
				if i > 1 then
					p.Reflectance = 0.25
				end
			end
		end
	end
end

-- «Мочи-искра»
local function buildBall(ctx: Ctx, def: Pets.PetDef, look: Look): (BasePart, Anchors)
	local col, acc = def.Color, def.Accent
	local c = Vector3.new(0, 0.12, 0)
	local r = 0.85
	local body = ball(ctx, "Body", c, 2 * r, col)
	if look.ears == "spark" then
		local mat = glow(ctx, 2)
		local tilt = RAD(20)
		for _, s in { 1, -1 } do
			local dir = Vector3.new(0.44 * s, 0.86, 0.06).Unit
			local base = c + dir * (r - 0.13)
			local up = Vector3.new(math.sin(tilt) * s, math.cos(tilt), 0)
			local inward = Vector3.new(-math.cos(tilt) * s, math.sin(tilt), 0)
			local h, d = 0.62, 0.4
			-- клин: вертикальная грань внутри, скос наружу — острое ушко
			add(ctx, "Wedge", "Ear", CFrame.fromMatrix(base + up * (h / 2), up:Cross(inward), up, inward), Vector3.new(0.22, h, d), tint(col, 0.18))
			gem(ctx, "EarSpark", base + up * h + inward * (d / 2) - up * 0.03, 0.15, acc:Lerp(col, 0.35), mat)
		end
	end
	if look.tail ~= false then
		local mat = glow(ctx, 1)
		-- хвост-молния: три звена зигзагом назад-вверх, последнее светится
		local p0 = c + Vector3.new(0, -0.3, 0.7)
		local p1 = p0 + Vector3.new(0.22, 0.16, 0.34)
		local p2 = p1 + Vector3.new(-0.2, 0.26, 0.2)
		local p3 = p2 + Vector3.new(0.16, 0.32, 0.12)
		chain(ctx, "Tail", { p0, p1, p2, p3 }, 0.15, tint(col, 0.18), MAT.SmoothPlastic, Vector3.xAxis, acc:Lerp(col, 0.25), mat)
	end
	faceKit(ctx, sphereSurface(c, r), r, faceOpts(def, look))
	local rc = 0.34
	return body, {
		head = c,
		headR = r,
		crown = c + Vector3.new(0, math.sqrt(r * r - rc * rc) - 0.04, 0),
		crownR = rc,
		ear = c + Vector3.new(0.78, 0.82, -0.05),
		orbit = c + Vector3.new(0, 0.2, 0),
		orbitR = r + 0.38,
	}
end

-- Шестигранник «печенькой» (ось по Z, к зрителю): три бруска, повёрнутые на 60° вокруг Z. R — описанный радиус,
-- depth — толщина; при roll = 0 верхняя и нижняя грани плоские. Возвращает первый брусок.
local function hexCookie(ctx: Ctx, name: string, pos: Vector3, R: number, depth: number, roll: number, color: Color3): BasePart
	local first: BasePart? = nil
	for q = 0, 2 do
		local p = add(ctx, "Block", name, CFrame.new(pos) * CFrame.Angles(0, 0, roll + q * math.pi / 3), Vector3.new(R, R * SQRT3, depth), color)
		first = first or p
	end
	return first :: BasePart
end

-- «Тучка»: гранёная, как грозовые тучи мира (STYLE §6.3) — большой шестигранник с лицом спереди,
-- три клуба-шестигранника поменьше за ним (повёрнуты, разной высоты), плоское тёмное брюхо и дождик-молния
local function buildCloud(ctx: Ctx, def: Pets.PetDef, look: Look): (BasePart, Anchors)
	local col, acc = def.Color, def.Accent
	local c = Vector3.new(0.04, 0.12, -0.1)
	local R, depth = 0.96, 0.9
	local apo = R * SQRT3 / 2 -- половина высоты шестигранника (до плоской грани)
	local body = hexCookie(ctx, "Body", c, R, depth, 0, col) -- без крена: первый брусок — PrimaryPart (по нему ставится модель)
	-- клубы: левый крупнее и выше, правый ниже; повёрнуты, чтобы край тучи был рваным
	hexCookie(ctx, "Puff", c + Vector3.new(-0.86, -0.2, 0.26), 0.64, 0.74, RAD(17), tint(col, 0.14))
	hexCookie(ctx, "Puff", c + Vector3.new(0.86, -0.33, 0.24), 0.52, 0.7, RAD(-12), tint(col, 0.07))
	-- малый клуб выглядывает из-за макушки справа: верх тучи не плоский
	hexCookie(ctx, "Puff", c + Vector3.new(0.42, 0.66, 0.32), 0.46, 0.6, RAD(9), tint(col, 0.2))
	-- плоское брюхо: туча «стоит» на ровном тёмном основании
	local bellyY = c.Y - apo + 0.06
	add(ctx, "Block", "Belly", CFrame.new(c.X - 0.04, bellyY, c.Z + 0.2), Vector3.new(2.3, 0.22, 0.78), shade(col, 0.3))
	-- дождик-молния под брюхом
	local mat = glow(ctx, 2)
	local z0 = Vector3.new(0.14, bellyY - 0.1, c.Z + 0.12)
	chain(ctx, "Rain", { z0, z0 + Vector3.new(-0.24, -0.28, 0), z0 + Vector3.new(0.02, -0.56, 0) }, 0.11, acc, mat, Vector3.new(0, 0, -1))
	local s = 0.78
	faceKit(ctx, planeSurface(c + Vector3.new(0, -0.04, 0), s, c.Z - depth / 2), s, faceOpts(def, look))
	return body, {
		head = c,
		headR = apo + 0.06,
		crown = c + Vector3.new(0, apo, 0),
		crownR = 0.32,
		ear = c + Vector3.new(0.82, apo + 0.05, 0.05),
		orbit = c + Vector3.new(0, 0.1, 0.12),
		orbitR = 1.5,
	}
end

-- «Звезда-печенька» (строится без крена; крен даёт xform в Models.pet)
local function buildStar(ctx: Ctx, def: Pets.PetDef, look: Look, rank: number): (BasePart, Anchors)
	local col, acc = def.Color, def.Accent
	-- сердцевина повёрнута (ось цилиндра по Z), поэтому корень — невидимый
	local body = add(ctx, "Block", "Body", CFrame.new(), Vector3.new(0.2, 0.2, 0.2), col, MAT.SmoothPlastic, 1)
	add(ctx, "Cylinder", "Core", CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.9, 1.55, 1.55), col)
	local lit, low = tint(col, 0.14), shade(col, 0.42)
	local light = Vector3.new(1, 1, 0).Unit -- свет сверху-слева от зрителя
	local rb, hw, th = 0.5, 0.43, 0.52
	local topTip = Vector3.zero
	-- у коронованных (легендарные и выше) верхний луч заменяет корона: звезда-король с ручками и ножками
	local crowned = rank >= 4
	for k = if crowned then 1 else 0, 4 do
		local ang = RAD(90 + 72 * k)
		local dir = Vector3.new(math.cos(ang), math.sin(ang), 0)
		local across = Vector3.new(-dir.Y, dir.X, 0)
		-- поза «сидит»: верхний луч длиннее, нижние короче
		local L = 0.98 * (if k == 0 then 1.15 elseif k == 2 or k == 3 then 0.88 else 1)
		local baseMid = dir * rb
		for _, s in { 1, -1 } do
			local sideV = across * s
			local z = -sideV
			add(ctx, "Wedge", "Ray", CFrame.fromMatrix(baseMid + dir * (L / 2) + sideV * (hw / 2), dir:Cross(z), dir, z), Vector3.new(th, L, hw), if sideV:Dot(light) > 0 then lit else low)
		end
		if k == 0 then
			topTip = dir * (rb + L)
		end
	end
	if rank < 2 then
		-- искра на макушке (у редких её место занимает знак редкости рядом)
		gem(ctx, "TipSpark", topTip + Vector3.new(0, 0.02, 0), 0.2, acc, glow(ctx, 1))
	end
	faceKit(ctx, planeSurface(Vector3.new(0, -0.05, 0), 0.74, -0.45), 0.74, faceOpts(def, look))
	return body, {
		head = Vector3.new(0, 0.3, 0),
		headR = 0.6,
		crown = Vector3.new(0, 0.78, 0),
		crownR = 0.34,
		ear = Vector3.new(1.05, 1.0, -0.1),
		orbit = Vector3.new(0, 0.3, 0.05),
		orbitR = 1.55,
	}
end

-- «Капелька»
local function buildDrop(ctx: Ctx, def: Pets.PetDef, look: Look): (BasePart, Anchors)
	local col, acc = def.Color, def.Accent
	local c = Vector3.zero
	local r = 0.85
	local body = ball(ctx, "Body", c, 2 * r, col)
	local bend = RAD(look.tip or 12)
	local base = CFrame.new(0, 0.3, 0.03) * CFrame.Angles(bend, 0, 0) * CFrame.Angles(0, RAD(look.twist or 0), 0)
	local h = 1.26
	pyramid4(ctx, "Cone", base, 1.16, h, tint(col, 0.1))
	gem(ctx, "TipSpark", (base * CFrame.new(0, h + 0.02, 0)).Position, 0.15, acc, glow(ctx, 1))
	-- блик-наклейка на верхнем-левом склоне (от зрителя)
	local gn = Vector3.new(0.5, 0.5, -0.7).Unit
	disc(ctx, "Gloss", c + gn * (r + 0.004), gn, 0.36, 0.03, CREAM, nil, 0.2)
	faceKit(ctx, sphereSurface(c, r), r, faceOpts(def, look))
	return body, {
		head = c,
		headR = r,
		crown = Vector3.new(0, 0.8, 0.12),
		crownR = 0.42,
		ear = Vector3.new(0.85, 0.8, 0),
		orbit = Vector3.new(0, 0.3, 0),
		orbitR = 1.25,
	}
end

-- «Самоцвет»: бипирамида с глазами-брусками
local function buildCrystal(ctx: Ctx, def: Pets.PetDef, look: Look): (BasePart, Anchors)
	local col, acc = def.Color, def.Accent
	local w, hb, upH = 1.3, 0.9, 0.85
	local lowH = look.low or 0.7
	local body = add(ctx, "Block", "Body", CFrame.new(), Vector3.new(w, hb, w), col)
	body.Reflectance = 0.1
	for _, p in pyramid4(ctx, "Facet", CFrame.new(0, hb / 2, 0), w, upH, tint(col, 0.16)) do
		p.Reflectance = 0.1
	end
	for _, p in pyramid4(ctx, "Facet", CFrame.new(0, -hb / 2, 0) * CFrame.Angles(0, 0, math.pi), w, lowH, shade(col, 0.5)) do
		p.Reflectance = 0.1
	end
	-- по бокам — светящиеся осколки (у мифического их роль играют искры на орбите)
	local mat = glow(ctx, 2)
	for _, s in (if Pets.Rarities[def.Rarity].Rank >= 5 then {} else { 1, -1 }) :: { number } do
		gem(ctx, "Shard", Vector3.new(0.86 * s, 0.12 + 0.08 * s, 0.14), 0.22, acc:Lerp(col, 0.5), mat, RAD(20 * s))
	end
	-- лицо на плоской передней грани: глаза-бруски с квадратным бликом
	local o = faceOpts(def, look)
	local feature = if o.dark then CREAM else INK
	local fz = -w / 2
	for _, s in { 1, -1 } do
		local ex = 0.27 * s
		if o.eyes == "happy" or (o.eyes == "wink" and s == -1) then
			for _, q in { 1, -1 } do
				local a = Vector3.new(ex, 0.13, fz - 0.02)
				bar(ctx, "Eye", a, a + Vector3.new(0.13 * q, -0.1, 0), 0.07, 0.05, feature)
			end
		else
			add(ctx, "Block", "Eye", CFrame.new(ex, 0.04, fz - 0.02), Vector3.new(0.13, 0.36, 0.05), INK)
			add(ctx, "Block", "Shine", CFrame.new(ex + 0.025, 0.14, fz - 0.05), Vector3.new(0.06, 0.08, 0.02), CREAM)
		end
		add(ctx, "Block", "Cheek", CFrame.new(0.47 * s, -0.2, fz - 0.012), Vector3.new(0.16, 0.1, 0.03), def.Color:Lerp(BLUSH, 0.55))
	end
	if o.mouth == "open" then
		add(ctx, "Block", "Mouth", CFrame.new(0, -0.21, fz - 0.015), Vector3.new(0.18, 0.1, 0.03), feature)
		add(ctx, "Block", "Tongue", CFrame.new(0, -0.235, fz - 0.03), Vector3.new(0.1, 0.04, 0.02), TONGUE)
	elseif o.mouth == "o" then
		add(ctx, "Block", "Mouth", CFrame.new(0, -0.21, fz - 0.015), Vector3.new(0.1, 0.1, 0.03), feature)
	else
		add(ctx, "Block", "Mouth", CFrame.new(0, -0.2, fz - 0.015), Vector3.new(0.18, 0.04, 0.03), feature)
	end
	return body, {
		head = Vector3.new(0, hb / 2, 0),
		headR = 0.75,
		crown = Vector3.new(0, hb / 2 + 0.28, 0),
		crownR = 0.5,
		ear = Vector3.new(0.82, 0.95, 0),
		orbit = Vector3.new(0, 0.3, 0),
		orbitR = 1.25,
	}
end

function Models.pet(kind: string): Model
	local def = Pets.Kinds[kind] or Pets.Kinds[Pets.StarterPet]
	local m = Instance.new("Model")
	m.Name = def.Id
	m:SetAttribute("Kind", def.Id)
	m:SetAttribute("Rarity", def.Rarity)
	local ctx = newCtx(m)
	local rank = Pets.Rarities[def.Rarity].Rank
	ctx.neon = 3 - marksNeon(rank)
	local look = lookOf(def)
	local body: BasePart
	local anchors: Anchors
	if def.Shape == "cloud" then
		body, anchors = buildCloud(ctx, def, look)
	elseif def.Shape == "star" then
		body, anchors = buildStar(ctx, def, look, rank)
	elseif def.Shape == "drop" then
		body, anchors = buildDrop(ctx, def, look)
	elseif def.Shape == "crystal" then
		body, anchors = buildCrystal(ctx, def, look)
	else
		body, anchors = buildBall(ctx, def, look)
	end
	rarityMarks(ctx, def, rank, anchors)
	-- крен всего питомца (кроме невидимого корня звезды) — живая асимметричная поза
	local roll = look.roll or 0
	if roll ~= 0 and def.Shape == "star" then
		local xf = CFrame.Angles(0, 0, RAD(roll))
		for _, p in ctx.parts do
			if p ~= body then
				p.CFrame = xf * p.CFrame
			end
		end
	end
	m.PrimaryPart = body
	weldAll(ctx, body)
	return m
end

----------------------------------------------------------------------
-- Кокон (STYLE §7.5): капсула-«таблетка» (цилиндр и два шара одного диаметра, низ темнее, верх светлее),
-- гнездо из пяти клиньев-лепестков, две светящиеся трещины-зигзага, тематическое навершие. ≤ 16 деталей.
----------------------------------------------------------------------
function Models.cocoon(id: string): Model
	local def = Pets.Cocoons[id] or Pets.Cocoons.meadow
	local m = Instance.new("Model")
	m.Name = "Cocoon_" .. def.Id
	m:SetAttribute("Cocoon", def.Id)
	local ctx = newCtx(m)
	local col = def.Color
	local glowCol = lighter(col, 0.6)
	if def.Id == "storm" then
		glowCol = Color3.fromRGB(255, 215, 90)
	elseif def.Id == "ice" then
		glowCol = Color3.fromRGB(200, 245, 255)
	end
	-- корень модели — низ кокона (без поворота)
	local root = add(ctx, "Block", "Root", CFrame.new(), Vector3.new(0.2, 0.2, 0.2), WHITE, MAT.SmoothPlastic, 1)
	local D, R = 2.3, 1.15
	local y0 = 0.12 + R -- центр нижнего шара
	local y1 = y0 + 1.0 -- центр верхнего шара
	-- капсула слегка наклонена (живее, чем строго вертикальная)
	local lean = CFrame.new(0, 0.12, 0) * CFrame.Angles(RAD(-4), 0, RAD(5)) * CFrame.new(0, -0.12, 0)
	add(ctx, "Ball", "Shell", lean * CFrame.new(0, y0, 0), Vector3.new(D, D, D), shade(col, 0.1))
	add(ctx, "Cylinder", "Shell", lean * CFrame.new(0, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(1.0, D, D), col)
	add(ctx, "Ball", "Shell", lean * CFrame.new(0, y1, 0), Vector3.new(D, D, D), tint(col, 0.1))
	-- гнездо: пять толстых «прутьев» по кругу у основания, соседние наклонены в разные стороны и
	-- перекрещиваются (плетёное гнездо); длина и высота с разбросом
	local twig = col:Lerp(Color3.fromRGB(150, 104, 70), 0.62)
	local jitter = { 6, -9, 4, -6, 10 }
	for k = 0, 4 do
		local ang = RAD(k * 72 + jitter[k + 1] + 10)
		local o = Vector3.new(math.sin(ang), 0, -math.cos(ang))
		local tg = Vector3.new(-o.Z, 0, o.X)
		local roll = RAD(if k % 2 == 0 then 17 else -15)
		local dir = tg * math.cos(roll) + Vector3.yAxis * math.sin(roll)
		local len = 1.85 + 0.12 * ((k * 7) % 3)
		local c = o * 0.98 + Vector3.new(0, 0.44 + 0.06 * (k % 2), 0)
		bar(ctx, "Nest", c - dir * (len / 2), c + dir * (len / 2), 0.34, 0.34, if k % 2 == 0 then twig else shade(twig, 0.3), nil, o)
	end
	-- трещины: зигзаги по поверхности капсулы (у ледяного первая короче: сосульки сверху дороже)
	local function onShell(a: number, y: number): Vector3
		local r = RAD(a)
		return (lean * CFrame.new(math.sin(r) * (R + 0.012), y, -math.cos(r) * (R + 0.012))).Position
	end
	local crack1 = if def.Id == "ice"
		then { onShell(-38, y0 + 0.12), onShell(-24, y1 + 0.12), onShell(-35, y1 + 0.46) }
		else { onShell(-44, y0 + 0.08), onShell(-27, y0 + 0.56), onShell(-41, y0 + 0.9), onShell(-26, y1 + 0.34) }
	chain(ctx, "Crack", crack1, 0.1, glowCol, MAT.Neon)
	chain(ctx, "Crack", { onShell(126, y0 + 0.3), onShell(140, y1 + 0.02), onShell(129, y1 + 0.32) }, 0.1, glowCol, MAT.Neon)
	-- тематическое навершие
	local crownPt = (lean * CFrame.new(0, y1 + R - 0.08, 0)).Position
	if def.Id == "meadow" then
		-- росток: два листа-клина
		for _, s in { 1, -1 } do
			local up = Vector3.new(0.55 * s, 0.84, 0).Unit
			local side = Vector3.new(0, 0, s) -- вертикальная грань листа — внутрь
			local h = if s > 0 then 0.75 else 0.6
			add(ctx, "Wedge", "Leaf", CFrame.fromMatrix(crownPt + up * (h / 2), side, up, side:Cross(up)), Vector3.new(0.1, h, 0.42), Color3.fromRGB(96, 186, 84))
		end
	elseif def.Id == "ice" then
		-- три ледяных шипа разной длины (острые уголки), торчат из макушки веером
		local list = { { -0.36, 0.8, -16, 30 }, { 0.04, 1.15, 3, 200 }, { 0.38, 0.62, 19, 110 } }
		for _, e in list do
			local p = crownPt + Vector3.new(e[1], -0.08 - math.abs(e[1]) * 0.3, 0)
			add(ctx, "CornerWedge", "Icicle", CFrame.new(p) * CFrame.Angles(0, 0, RAD(-e[3])) * CFrame.Angles(0, RAD(e[4]), 0) * CFrame.new(0, e[2] / 2, 0), Vector3.new(0.4, e[2], 0.4), Color3.fromRGB(210, 240, 255), MAT.Glass, 0.15)
		end
	else
		-- грозовой: молния-навершие
		chain(ctx, "Bolt", { crownPt, crownPt + Vector3.new(0.3, 0.45, 0), crownPt + Vector3.new(-0.08, 0.62, 0), crownPt + Vector3.new(0.2, 1.1, 0) }, 0.15, glowCol, MAT.Neon)
	end
	m.PrimaryPart = root
	weldAll(ctx, root)
	return m
end

----------------------------------------------------------------------
-- Фульгурит по спецификации Fulgurite.generate: стекло (ромбовидные бруски), сердцевина, основание, кончики
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
			add(ctx, kind, "Tip", ps.CFrame, ps.Size, lighter(glassColor, 0.4), MAT.Neon)
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
	local glowCol = Color3.fromRGB(110, 200, 255)
	cylY(ctx, "Pad", Vector3.new(0, 0.15, 0), 0.3, 6, Color3.fromRGB(60, 64, 76), MAT.Metal)
	cylY(ctx, "PadGlow", Vector3.new(0, 0.12, 0), 0.26, 6.3, glowCol, MAT.Neon)
	add(ctx, "Block", "Box", CFrame.new(0, 1.6, 3.6), Vector3.new(3, 2.6, 2), metal, MAT.Metal)
	for i = -1, 1 do
		local x = i * 0.9
		for k = 0, 2 do
			cylY(ctx, "Insulator", Vector3.new(x, 3.05 + k * 0.3, 3.6), 0.18, 0.55 - k * 0.08, PORCELAIN, MAT.SmoothPlastic)
		end
		gem(ctx, "Spark", Vector3.new(x, 3.95, 3.6), 0.3, glowCol, MAT.Neon, RAD(45))
	end
	chain(ctx, "Stripe", { Vector3.new(-1.3, 1.45, 2.58), Vector3.new(-0.4, 1.8, 2.58), Vector3.new(0.4, 1.4, 2.58), Vector3.new(1.3, 1.75, 2.58) }, 0.2, glowCol, MAT.Neon, Vector3.new(0, 0, -1))
	m.PrimaryPart = root
	weldAll(ctx, root)
	return m
end

----------------------------------------------------------------------
-- Шаровая молния (событие): яркое ядро-шар (это и есть «шаровая»), вокруг — две полупрозрачные колючие
-- оболочки (кубы на вершине, повёрнутые друг к другу: вместе — звёздчатый многогранник), шесть игл-ромбов
-- и четыре искры-ромба на орбите. Детали якорные и не сварены: EventFX крутит группы по отдельности
-- (имена: Core, ShellA, ShellB, Spike*, Orbiter*). Центр — (0, 0, 0).
----------------------------------------------------------------------
Models.BallColors = {
	Core = Color3.fromRGB(255, 248, 225),
	Gold = Color3.fromRGB(255, 196, 70),
	Shell = Color3.fromRGB(255, 160, 40),
	Arc = Color3.fromRGB(255, 236, 150),
}

function Models.ballLightning(): Model
	local m = Instance.new("Model")
	m.Name = "BallLightning"
	local ctx = newCtx(m)
	local bc = Models.BallColors
	local core = ball(ctx, "Core", Vector3.zero, 4.4, bc.Core, MAT.Neon)
	add(ctx, "Block", "ShellA", GEM_TILT, Vector3.new(6.4, 6.4, 6.4), bc.Shell, MAT.Neon, 0.8)
	add(ctx, "Block", "ShellB", CFrame.Angles(0, RAD(45), 0) * CFrame.Angles(RAD(45), 0, 0), Vector3.new(5.8, 5.8, 5.8), bc.Gold, MAT.Neon, 0.82)
	-- иглы: ромбовидные бруски по шести неравным направлениям (не «через равные углы»)
	local dirs = {
		Vector3.new(0.2, 1, 0.1),
		Vector3.new(-0.9, -0.25, 0.4),
		Vector3.new(0.8, -0.5, -0.3),
		Vector3.new(-0.3, 0.35, -0.95),
		Vector3.new(0.45, 0.2, 0.9),
		Vector3.new(-0.15, -1, -0.2),
	}
	local lens = { 4.2, 3.4, 3.8, 3.1, 3.6, 3.0 }
	for i, d in dirs do
		local u = d.Unit
		local cf = Geom.axisCFrame(u * 1.6, u * (1.6 + lens[i]))
		add(ctx, "Block", "Spike" .. i, cf * CFrame.Angles(math.pi / 4, 0, 0), Vector3.new(lens[i] + 0.4, 0.42, 0.42), bc.Gold, MAT.Neon)
	end
	for i = 1, 4 do
		gem(ctx, "Orbiter" .. i, Vector3.new(6.4, 0, 0), 1.1 - (i % 2) * 0.3, bc.Arc, MAT.Neon)
	end
	for _, p in ctx.parts do
		p.Anchored = true
	end
	m.PrimaryPart = core
	return m
end

----------------------------------------------------------------------
-- Рецепты для пулов StrikeController (одни и те же для игры и листа превью)
----------------------------------------------------------------------
export type RecipePart = {
	Name: string,
	Kind: string, -- "Block" | "CornerWedge"
	CFrame: CFrame, -- относительно центра (низ тучи / основание осколка)
	Size: Vector3,
	Tone: string, -- тучка: "core" | "belly" | "edge" | "glow"; осколок: "glass" | "glow"
}

-- Тучка удара (STYLE §6.3, R-STRIKE-CLOUD): плита-шестиугольник (ядро) и два наклонных «клуба» сверху,
-- свисающих за край; внутри снизу — неоновый кристалл CloudCore. Центр — середина низа плиты. 6 деталей.
function Models.strikeCloudRecipe(): { RecipePart }
	local out: { RecipePart } = {}
	local R, t = 6, 1.6
	-- плита-шестиугольник с неровным краем
	local zk = { 0.9, 1.06, 1.0 }
	local dy = { 0, RAD(5), RAD(-4) }
	for q = 0, 2 do
		table.insert(out, {
			Name = "Cloud",
			Kind = "Block",
			CFrame = CFrame.new(0, t / 2, 0) * CFrame.Angles(0, RAD(12) + q * math.pi / 3 + dy[q + 1], 0),
			Size = Vector3.new(R, t, R * SQRT3 * zk[q + 1]),
			Tone = "core",
		})
	end
	-- клубы: большой свисает за один край, малый выше и за другой (наружу-вниз, как рваный край грозы)
	table.insert(out, {
		Name = "Cloud",
		Kind = "Block",
		CFrame = CFrame.new(1.6, t + 1.0, 0.9) * CFrame.Angles(0, RAD(24), 0) * CFrame.Angles(RAD(10), 0, RAD(-16)),
		Size = Vector3.new(9, 3.2, 7),
		Tone = "belly",
	})
	table.insert(out, {
		Name = "Cloud",
		Kind = "Block",
		CFrame = CFrame.new(-3.6, t + 1.9, -1.5) * CFrame.Angles(0, RAD(-32), 0) * CFrame.Angles(RAD(-18), 0, RAD(22)),
		Size = Vector3.new(6, 2.6, 5),
		Tone = "edge",
	})
	table.insert(out, {
		Name = "CloudCore",
		Kind = "Block",
		CFrame = CFrame.new(0, 0.15, 0) * GEM_TILT,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Tone = "glow",
	})
	return out
end

-- Осколок на земле: три стеклянных шипа-уголка разной высоты, наклонены наружу, и неоновая сердцевина-ромб.
-- Центр — точка на земле. 4 детали.
function Models.shardRecipe(): { RecipePart }
	local function spike(x: number, z: number, h: number, w: number, yaw: number, lean: number): RecipePart
		-- CornerWedge: высокий угол (+X, +Y, −Z); наклон наружу от центра
		local out = Vector3.new(x, 0, z)
		local tiltAxis = if out.Magnitude > 1e-3 then Vector3.new(-out.Z, 0, out.X).Unit else Vector3.xAxis
		local cf = CFrame.new(x, 0, z) * CFrame.fromAxisAngle(tiltAxis, -lean) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, h / 2, 0)
		return { Name = "Shard", Kind = "CornerWedge", CFrame = cf, Size = Vector3.new(w, h, w), Tone = "glass" }
	end
	return {
		spike(0.05, -0.05, 1.7, 0.62, RAD(20), RAD(6)),
		spike(0.42, 0.22, 1.1, 0.5, RAD(150), RAD(26)),
		spike(-0.36, 0.28, 0.85, 0.44, RAD(-100), RAD(34)),
		{ Name = "Shard", Kind = "Block", CFrame = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, RAD(10), 0) * GEM_TILT, Size = Vector3.new(0.5, 0.5, 0.5), Tone = "glow" },
	}
end

return Models
