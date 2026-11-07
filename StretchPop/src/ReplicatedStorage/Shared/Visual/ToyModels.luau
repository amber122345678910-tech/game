--!strict
-- STRETCH-POP · Генератор мультяшных 3D-моделек из примитивов (без ассетов).
-- Используется клиентом (иконки ViewportFrame, бадди за плечами, анимация капсулы) и сервером
-- (капсулы в куполах автоматов, кубки на подиуме, деревья и облака вокруг хаба и полос).
-- Все детали — Anchored, без коллизий и запросов: это чистая декорация.

local Shared = script.Parent.Parent
local BuddyConfig = require(Shared.Config.BuddyConfig)
local GloveConfig = require(Shared.Config.GloveConfig)

export type Toy = {
	Model: Model,
	Radius: number, -- радиус описывающей сферы (для кадрирования камеры)
	Aura: Part?,
}

local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(28, 32, 56)
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local BALL = Enum.PartType.Ball
local BLOCK = Enum.PartType.Block
local CYLINDER = Enum.PartType.Cylinder
local WEDGE = Enum.PartType.Wedge

local ToyModels = {}

local function axisFrame(position: Vector3, direction: Vector3): CFrame
	local x = if direction.Magnitude > 1e-5 then direction.Unit else Vector3.xAxis
	local helper = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(helper).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(position, x, y, z)
end
ToyModels.AxisFrame = axisFrame

local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	return model
end

local function piece(
	model: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end
ToyModels.Piece = piece

-- Цилиндр от a до b
local function segment(model: Instance, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material): Part
	local direction = b - a
	return piece(model, name, CYLINDER, Vector3.new(math.max(direction.Magnitude, 0.05), thickness, thickness), axisFrame((a + b) * 0.5, direction), color, material)
end
ToyModels.Segment = segment

local function ellipsoid(model: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part
	local part = piece(model, name, BLOCK, size, cframe, color, material, transparency)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end
ToyModels.Ellipsoid = ellipsoid

-- Все модельки строятся вокруг начала координат «с прямой осанкой». Опорную точку (pivot)
-- кладём ровно туда через PivotOffset — тогда Place/PivotTo/GetPivot работают в системе
-- координат модельки, а не в повёрнутой системе первой детали (цилиндры лежат на боку).
local function finish(model: Model, primary: BasePart, radius: number, aura: Part?): Toy
	model.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:Inverse()
	return { Model = model, Radius = radius, Aura = aura }
end

local function pivotOf(primary: BasePart): CFrame
	return primary.CFrame * primary.PivotOffset
end
ToyModels.PivotOf = pivotOf

-- ── Иконки статов ──────────────────────────────────────────────────────────

-- Elasticity: рогатка с растянутым неоновым жгутом
function ToyModels.Slingshot(bandColor: Color3): Toy
	local model = newModel("SlingshotToy")
	local wood = RGB(176, 112, 62)
	local handle = segment(model, "Handle", Vector3.new(0, -2.4, 0), Vector3.new(0, 0, 0), 0.75, wood, Enum.Material.Wood)
	local leftTip = Vector3.new(-1.25, 1.7, 0)
	local rightTip = Vector3.new(1.25, 1.7, 0)
	segment(model, "LeftProng", Vector3.zero, leftTip, 0.62, wood, Enum.Material.Wood)
	segment(model, "RightProng", Vector3.zero, rightTip, 0.62, wood, Enum.Material.Wood)
	piece(model, "Knot", BALL, Vector3.one * 0.9, CFrame.new(0, 0, 0), RGB(140, 84, 44), SMOOTH)
	piece(model, "LeftTip", BALL, Vector3.one * 0.62, CFrame.new(leftTip), bandColor, NEON)
	piece(model, "RightTip", BALL, Vector3.one * 0.62, CFrame.new(rightTip), bandColor, NEON)
	local pouch = Vector3.new(0, 0.85, 1.6)
	segment(model, "BandLeft", leftTip, pouch, 0.24, bandColor, NEON)
	segment(model, "BandRight", rightTip, pouch, 0.24, bandColor, NEON)
	piece(model, "Pouch", BALL, Vector3.one * 0.7, CFrame.new(pouch), RGB(90, 50, 30), SMOOTH)
	piece(model, "Grip", CYLINDER, Vector3.new(0.9, 0.85, 0.85), CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(255, 90, 120), SMOOTH)
	return finish(model, handle, 3)
end

-- SpringPower: витая пружина из сегментов-цилиндров
function ToyModels.Spring(color: Color3): Toy
	local model = newModel("SpringToy")
	local turns, steps, radius, height = 4, 44, 1.05, 3.4
	local previous = Vector3.new(radius, -height / 2, 0)
	for index = 1, steps do
		local t = index / steps
		local angle = t * turns * 2 * math.pi
		local point = Vector3.new(math.cos(angle) * radius, -height / 2 + height * t, math.sin(angle) * radius)
		segment(model, "Coil" .. index, previous, point, 0.36, color, Enum.Material.Metal)
		previous = point
	end
	local bottom = piece(model, "BottomCap", CYLINDER, Vector3.new(0.3, 2.7, 2.7), CFrame.new(0, -height / 2 - 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(60, 70, 96), SMOOTH)
	piece(model, "TopCap", CYLINDER, Vector3.new(0.3, 2.7, 2.7), CFrame.new(0, height / 2 + 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(255, 214, 64), NEON)
	return finish(model, bottom, 2.6)
end

-- SmashMass: тяжёлая шипастая гиря
function ToyModels.Kettlebell(accent: Color3): Toy
	local model = newModel("KettlebellToy")
	local iron = RGB(70, 76, 98)
	local body = piece(model, "Body", BALL, Vector3.one * 3, CFrame.new(0, -0.4, 0), iron, Enum.Material.Metal)
	piece(model, "Band", CYLINDER, Vector3.new(0.42, 3.08, 3.08), CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), accent, NEON)
	local previous = Vector3.new(1.05, 0.7, 0)
	for index = 1, 8 do
		local angle = index / 8 * math.pi
		local point = Vector3.new(math.cos(angle) * 1.05, 0.7 + math.sin(angle) * 1.15, 0)
		segment(model, "Handle" .. index, previous, point, 0.48, iron, Enum.Material.Metal)
		previous = point
	end
	for index = 1, 8 do
		local angle = index / 8 * 2 * math.pi
		local direction = Vector3.new(math.cos(angle), -0.05, math.sin(angle))
		local base = Vector3.new(0, -0.4, 0) + direction * 1.45
		local spike = piece(model, "Spike" .. index, WEDGE, Vector3.new(0.5, 0.75, 0.5), CFrame.lookAt(base, base + direction) * CFrame.Angles(-math.pi / 2, 0, 0), RGB(230, 236, 250), Enum.Material.Metal)
		spike.Name = "Spike" .. index
	end
	for _, y in { -1.95, 1.15 } do
		piece(model, "Pip", BALL, Vector3.one * 0.5, CFrame.new(0, y, 0), RGB(230, 236, 250), Enum.Material.Metal)
	end
	return finish(model, body, 2.6)
end

-- ── Перчатка ───────────────────────────────────────────────────────────────

function ToyModels.Glove(glove: GloveConfig.GloveDef): Toy
	local model = newModel("GloveToy_" .. glove.Id)
	local color, material = glove.Color, glove.Material
	local palm = ellipsoid(model, "Palm", Vector3.new(2.3, 2.1, 1.5), CFrame.new(0, 0, 0), color, material)
	for index, x in { -0.72, -0.24, 0.24, 0.72 } do
		local length = if index == 1 or index == 4 then 1.05 else 1.3
		local base = Vector3.new(x, 0.75, -0.05)
		local tip = base + Vector3.new(x * 0.12, length, -0.25)
		segment(model, "Finger" .. index, base, tip, 0.56, color, material)
		piece(model, "Tip" .. index, BALL, Vector3.one * 0.58, CFrame.new(tip), color, material)
	end
	local thumbBase = Vector3.new(-1, 0, 0)
	local thumbTip = Vector3.new(-1.55, 0.75, -0.3)
	segment(model, "Thumb", thumbBase, thumbTip, 0.62, color, material)
	piece(model, "ThumbTip", BALL, Vector3.one * 0.64, CFrame.new(thumbTip), color, material)
	piece(model, "Cuff", CYLINDER, Vector3.new(0.95, 2.1, 2.1), CFrame.new(0, -1.25, 0) * CFrame.Angles(0, 0, math.pi / 2), glove.Accent, SMOOTH)
	piece(model, "CuffStripe", CYLINDER, Vector3.new(0.22, 2.18, 2.18), CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.pi / 2), color, NEON)
	piece(model, "Shine", BALL, Vector3.one * 0.42, CFrame.new(0.55, 0.35, -0.68), WHITE, SMOOTH, 0.2)
	return finish(model, palm, 2.6)
end

-- ── Бадди ──────────────────────────────────────────────────────────────────

-- Собирает фигурку по описанию формы; мутация перекрашивает тело и даёт ауру.
function ToyModels.Buddy(buddyId: string, mutation: BuddyConfig.Mutation): Toy
	local def = BuddyConfig.Buddies[buddyId] or BuddyConfig.Buddies.SlimeCube
	local mutationDef = BuddyConfig.Mutations[mutation] or BuddyConfig.Mutations.Normal
	local shape = def.Form
	local model = newModel("Buddy_" .. def.Id)

	local tint = mutationDef.Tint
	local function tone(color: Color3): Color3
		return if tint then color:Lerp(tint, mutationDef.TintAlpha) else color
	end
	local bodyColor = tone(shape.BodyColor)
	local accentColor = if mutation == "Void" then RGB(220, 110, 255) else tone(shape.AccentColor)
	local material = mutationDef.Material

	local body: Part
	local half: Vector3
	if shape.Body == "Cube" then
		body = piece(model, "Body", BLOCK, Vector3.new(2.5, 2.3, 2.5), CFrame.new(), bodyColor, material)
		half = Vector3.new(1.25, 1.15, 1.25)
	elseif shape.Body == "Egg" then
		body = ellipsoid(model, "Body", Vector3.new(2.5, 3, 2.5), CFrame.new(), bodyColor, material)
		half = Vector3.new(1.25, 1.5, 1.25)
	else
		body = piece(model, "Body", BALL, Vector3.one * 2.7, CFrame.new(), bodyColor, material)
		half = Vector3.new(1.35, 1.35, 1.35)
	end
	local front = -half.Z + 0.12
	local top = half.Y

	-- Глазки: белок, зрачок, блик
	local pupilColor = if mutation == "Void" then RGB(230, 120, 255) else RGB(20, 20, 34)
	local pupilMaterial = if mutation == "Void" or mutation == "CyberSlime" then NEON else SMOOTH
	for _, side in { -1, 1 } do
		local eye = Vector3.new(side * 0.5, 0.28, front)
		piece(model, "EyeWhite", BALL, Vector3.one * 0.78, CFrame.new(eye), WHITE, SMOOTH)
		piece(model, "Pupil", BALL, Vector3.one * 0.42, CFrame.new(eye + Vector3.new(0, -0.02, -0.25)), pupilColor, pupilMaterial)
		piece(model, "Glint", BALL, Vector3.one * 0.14, CFrame.new(eye + Vector3.new(0.1, 0.12, -0.42)), WHITE, NEON)
		piece(model, "Cheek", BALL, Vector3.one * 0.36, CFrame.new(side * 0.85, -0.18, front + 0.12), RGB(255, 140, 170), SMOOTH, 0.35)
	end
	for index = -1, 1 do
		piece(model, "Smile", BALL, Vector3.one * 0.17, CFrame.new(index * 0.17, -0.3 - (1 - math.abs(index)) * 0.08, front - 0.02), INK, SMOOTH)
	end

	-- Уши / рога
	if shape.Ears == "Cat" or shape.Ears == "Fox" then
		local big = shape.Ears == "Fox"
		for _, side in { -1, 1 } do
			local ear = piece(model, "Ear", WEDGE, if big then Vector3.new(0.35, 1.25, 0.85) else Vector3.new(0.3, 0.85, 0.7), CFrame.new(side * 0.72, top + (if big then 0.45 else 0.3), 0.1) * CFrame.Angles(0, math.pi / 2, side * 0.18), accentColor, material)
			ear.Name = "Ear"
			if big then
				piece(model, "EarTip", BALL, Vector3.one * 0.32, CFrame.new(side * 0.78, top + 1.02, 0.1), WHITE, SMOOTH)
			end
		end
	elseif shape.Ears == "Floppy" then
		for _, side in { -1, 1 } do
			ellipsoid(model, "Ear", Vector3.new(0.5, 1.4, 0.9), CFrame.new(side * 1.3, 0.25, 0.05) * CFrame.Angles(0, 0, side * 0.35), accentColor, material)
		end
	elseif shape.Ears == "Horns" then
		for _, side in { -1, 1 } do
			local base = Vector3.new(side * 0.55, top - 0.1, 0.2)
			local tip = base + Vector3.new(side * 0.35, 0.95, 0.45)
			segment(model, "Horn", base, tip, 0.36, RGB(255, 246, 220), SMOOTH)
			piece(model, "HornTip", BALL, Vector3.one * 0.3, CFrame.new(tip), RGB(255, 246, 220), SMOOTH)
		end
	end

	-- Крылья
	if shape.Wings == "Chick" then
		for _, side in { -1, 1 } do
			ellipsoid(model, "Wing", Vector3.new(0.45, 1.1, 1.2), CFrame.new(side * (half.X + 0.12), -0.1, 0.2) * CFrame.Angles(0, 0, side * 0.4), accentColor, material)
		end
	elseif shape.Wings == "Bee" then
		for _, side in { -1, 1 } do
			ellipsoid(model, "Wing", Vector3.new(0.2, 1.3, 1.6), CFrame.new(side * 0.8, top - 0.1, 0.6) * CFrame.Angles(0.5, 0, side * 0.7), RGB(220, 245, 255), Enum.Material.Glass, 0.35)
		end
	elseif shape.Wings == "Dragon" then
		for _, side in { -1, 1 } do
			for index = 1, 3 do
				local spread = 0.35 + index * 0.32
				piece(model, "WingBlade", BLOCK, Vector3.new(0.12, 0.5, 1.9 - index * 0.25), CFrame.new(side * (0.9 + index * 0.35), 0.4 + index * 0.18, 0.85) * CFrame.Angles(0.35, side * spread, side * 0.5), accentColor, material)
			end
		end
	end

	-- Хвост
	if shape.Tail == "Fluffy" then
		piece(model, "Tail", BALL, Vector3.one * 1, CFrame.new(0, -0.35, half.Z + 0.35), accentColor, material)
		piece(model, "TailTip", BALL, Vector3.one * 0.62, CFrame.new(0, -0.05, half.Z + 0.95), WHITE, SMOOTH)
	elseif shape.Tail == "Dragon" then
		local points = { Vector3.new(0, -0.6, half.Z), Vector3.new(0, -0.8, half.Z + 0.7), Vector3.new(0, -0.6, half.Z + 1.3), Vector3.new(0, -0.2, half.Z + 1.75) }
		for index = 1, #points - 1 do
			segment(model, "Tail", points[index], points[index + 1], 0.55 - index * 0.1, bodyColor, material)
		end
		piece(model, "TailSpike", WEDGE, Vector3.new(0.2, 0.5, 0.6), CFrame.new(points[#points] + Vector3.new(0, 0.2, 0.1)), accentColor, material)
	end

	-- Особенности
	if shape.Extra == "Beak" then
		piece(model, "Beak", WEDGE, Vector3.new(0.6, 0.35, 0.5), CFrame.new(0, -0.02, front - 0.2) * CFrame.Angles(0, math.pi, 0), RGB(255, 150, 40), SMOOTH)
	elseif shape.Extra == "Rocket" then
		for _, side in { -1, 1 } do
			local x = side * 0.5
			segment(model, "Jet", Vector3.new(x, -0.7, half.Z + 0.25), Vector3.new(x, 0.6, half.Z + 0.25), 0.62, RGB(210, 216, 230), Enum.Material.Metal)
			piece(model, "Flame", BALL, Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, -0.95, half.Z + 0.25), RGB(255, 170, 40), NEON)
		end
	elseif shape.Extra == "Stripes" then
		for _, y in { -0.45, 0.25 } do
			piece(model, "Stripe", CYLINDER, Vector3.new(0.3, half.X * 2 + 0.06, half.Z * 2 + 0.06), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2), accentColor, material)
		end
		segment(model, "Stinger", Vector3.new(0, -0.9, half.Z - 0.2), Vector3.new(0, -1.1, half.Z + 0.5), 0.22, INK, SMOOTH)
	elseif shape.Extra == "Visor" then
		piece(model, "Visor", BLOCK, Vector3.new(1.7, 0.5, 0.25), CFrame.new(0, 0.3, front - 0.3), RGB(70, 240, 255), Enum.Material.Glass, 0.25)
	elseif shape.Extra == "Tentacles" then
		for index = 1, 5 do
			local angle = (index - 3) * 0.55
			local base = Vector3.new(math.sin(angle) * 0.85, -half.Y + 0.3, math.cos(angle) * 0.35)
			local previous = base
			for step = 1, 3 do
				local point = base + Vector3.new(math.sin(angle) * 0.35 * step, -0.45 * step, 0.18 * step)
				segment(model, "Tentacle", previous, point, 0.42 - step * 0.08, bodyColor, material)
				previous = point
			end
			piece(model, "Sucker", BALL, Vector3.one * 0.22, CFrame.new(previous), accentColor, NEON)
		end
	elseif shape.Extra == "Drip" then
		for index, offset in { Vector3.new(-0.9, -1.15, -0.6), Vector3.new(0.6, -1.2, -0.9), Vector3.new(1.0, -0.6, 0.7) } do
			ellipsoid(model, "Drip" .. index, Vector3.new(0.45, 0.7, 0.45), CFrame.new(offset), bodyColor, material, 0.1)
		end
	end

	local aura: Part? = nil
	if mutation ~= "Normal" then
		aura = piece(model, "Aura", BALL, Vector3.one * (math.max(half.X, half.Y) * 2 + 1.4), CFrame.new(), mutationDef.AuraColor, Enum.Material.ForceField, 0.15)
	end
	return finish(model, body, (math.max(half.X, half.Y) + 1.4) * shape.Scale, aura)
end

-- ── Капсула, монета, ракета, кубок ─────────────────────────────────────────

function ToyModels.Capsule(capsuleId: string): Toy
	local def = BuddyConfig.Capsules[capsuleId] or BuddyConfig.Capsules.Basic
	local model = newModel("Capsule_" .. def.Id)
	local glossTop = if capsuleId == "Basic" then SMOOTH else Enum.Material.Glass
	local bottom = piece(model, "Bottom", BALL, Vector3.one * 2.4, CFrame.new(0, -0.55, 0), def.BottomColor, SMOOTH)
	piece(model, "BottomBody", CYLINDER, Vector3.new(0.6, 2.4, 2.4), CFrame.new(0, -0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), def.BottomColor, SMOOTH)
	piece(model, "Top", BALL, Vector3.one * 2.4, CFrame.new(0, 0.55, 0), def.TopColor, glossTop)
	piece(model, "TopBody", CYLINDER, Vector3.new(0.6, 2.4, 2.4), CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), def.TopColor, glossTop)
	piece(model, "Band", CYLINDER, Vector3.new(0.24, 2.52, 2.52), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), WHITE, NEON)
	piece(model, "Shine", BALL, Vector3.one * 0.5, CFrame.new(-0.55, 1.05, -0.75), WHITE, SMOOTH, 0.15)
	return finish(model, bottom, 2.1)
end

function ToyModels.Coin(): Toy
	local model = newModel("CoinToy")
	local disc = piece(model, "Disc", CYLINDER, Vector3.new(0.45, 2.6, 2.6), CFrame.Angles(0, math.pi / 2, 0), RGB(255, 200, 40), Enum.Material.Foil)
	piece(model, "Inner", CYLINDER, Vector3.new(0.5, 1.8, 1.8), CFrame.Angles(0, math.pi / 2, 0), RGB(255, 236, 120), NEON)
	piece(model, "Rim", CYLINDER, Vector3.new(0.4, 2.8, 2.8), CFrame.Angles(0, math.pi / 2, 0), RGB(230, 150, 20), Enum.Material.Foil)
	return finish(model, disc, 1.6)
end

function ToyModels.Rocket(): Toy
	local model = newModel("RocketToy")
	local body = piece(model, "Body", CYLINDER, Vector3.new(2.4, 1.2, 1.2), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), RGB(248, 250, 255), SMOOTH)
	piece(model, "Nose", BALL, Vector3.one * 1.2, CFrame.new(0, 1.2, 0), RGB(255, 80, 96), SMOOTH)
	piece(model, "Window", BALL, Vector3.one * 0.55, CFrame.new(0, 0.35, -0.5), RGB(80, 220, 255), Enum.Material.Glass)
	for index = 1, 3 do
		local angle = index / 3 * 2 * math.pi
		local fin = piece(model, "Fin" .. index, WEDGE, Vector3.new(0.16, 0.9, 0.7), CFrame.Angles(0, angle, 0) * CFrame.new(0, -0.95, -0.75), RGB(255, 80, 96), SMOOTH)
		fin.Name = "Fin" .. index
	end
	piece(model, "Flame", BALL, Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, -1.55, 0), RGB(255, 170, 40), NEON)
	piece(model, "FlameCore", BALL, Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, -1.75, 0), RGB(255, 250, 200), NEON)
	return finish(model, body, 2.2)
end

function ToyModels.Trophy(color: Color3): Toy
	local model = newModel("Trophy")
	local base = piece(model, "Base", BLOCK, Vector3.new(2, 0.6, 2), CFrame.new(0, -1.5, 0), RGB(54, 44, 80), SMOOTH)
	piece(model, "Plinth", BLOCK, Vector3.new(1.4, 0.4, 1.4), CFrame.new(0, -1.0, 0), color, Enum.Material.Foil)
	segment(model, "Stem", Vector3.new(0, -0.8, 0), Vector3.new(0, 0.2, 0), 0.45, color, Enum.Material.Foil)
	piece(model, "Cup", BALL, Vector3.one * 1.7, CFrame.new(0, 0.9, 0), color, Enum.Material.Foil)
	piece(model, "Rim", CYLINDER, Vector3.new(0.3, 1.85, 1.85), CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Foil)
	for _, side in { -1, 1 } do
		segment(model, "HandleTop", Vector3.new(side * 0.8, 1.35, 0), Vector3.new(side * 1.25, 1.1, 0), 0.22, color, Enum.Material.Foil)
		segment(model, "HandleBottom", Vector3.new(side * 1.25, 1.1, 0), Vector3.new(side * 0.75, 0.55, 0), 0.22, color, Enum.Material.Foil)
	end
	piece(model, "Star", BALL, Vector3.one * 0.55, CFrame.new(0, 2.0, 0), RGB(255, 250, 200), NEON)
	return finish(model, base, 2.4)
end

-- ── Декор мира ─────────────────────────────────────────────────────────────

-- Мультяшное дерево: ствол + пышная крона из сфер
function ToyModels.Tree(scale: number, trunkColor: Color3, trunkMaterial: Enum.Material, leaves: Color3, leavesMaterial: Enum.Material, rng: Random): Toy
	local model = newModel("Tree")
	local height = (6 + rng:NextNumber() * 4) * scale
	local trunk = segment(model, "Trunk", Vector3.zero, Vector3.new(0, height, 0), 1.4 * scale, trunkColor, trunkMaterial)
	local crown = Vector3.new(0, height + 1.5 * scale, 0)
	piece(model, "Crown", BALL, Vector3.one * 6 * scale, CFrame.new(crown), leaves, leavesMaterial)
	for index = 1, 4 do
		local angle = index / 4 * 2 * math.pi + rng:NextNumber() * 0.6
		local offset = Vector3.new(math.cos(angle) * 2.4, rng:NextNumber(-0.8, 1.2), math.sin(angle) * 2.4) * scale
		piece(model, "Puff" .. index, BALL, Vector3.one * (3.6 + rng:NextNumber() * 1.4) * scale, CFrame.new(crown + offset), leaves:Lerp(WHITE, 0.08 * index), leavesMaterial)
	end
	return finish(model, trunk, height + 5 * scale)
end

function ToyModels.Cloud(scale: number, color: Color3, rng: Random): Toy
	local model = newModel("Cloud")
	local core = piece(model, "Core", BALL, Vector3.one * 10 * scale, CFrame.new(), color, SMOOTH, 0.05)
	for index = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-1.5, 2.5), rng:NextNumber(-3, 3)) * scale
		piece(model, "Puff" .. index, BALL, Vector3.one * rng:NextNumber(6, 9) * scale, CFrame.new(offset), color, SMOOTH, 0.05)
	end
	piece(model, "Base", CYLINDER, Vector3.new(4 * scale, 20 * scale, 9 * scale), CFrame.new(0, -2.5 * scale, 0) * CFrame.Angles(0, 0, math.pi / 2), color, SMOOTH, 0.05)
	return finish(model, core, 14 * scale)
end

-- Парящий островок: трава сверху, скальный «корень» снизу
function ToyModels.Island(radius: number, grass: Color3, rock: Color3, rockDark: Color3): Toy
	local model = newModel("FloatingIsland")
	local top = piece(model, "Grass", CYLINDER, Vector3.new(1.6, radius * 2, radius * 2), CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.pi / 2), grass, SMOOTH)
	piece(model, "Dirt", CYLINDER, Vector3.new(3, radius * 1.9, radius * 1.9), CFrame.new(0, -3, 0) * CFrame.Angles(0, 0, math.pi / 2), rock, Enum.Material.Slate)
	piece(model, "Root1", CYLINDER, Vector3.new(4, radius * 1.4, radius * 1.4), CFrame.new(0, -6.5, 0) * CFrame.Angles(0, 0, math.pi / 2), rockDark, Enum.Material.Rock)
	piece(model, "Root2", CYLINDER, Vector3.new(4, radius * 0.8, radius * 0.8), CFrame.new(0, -10, 0) * CFrame.Angles(0, 0, math.pi / 2), rockDark, Enum.Material.Rock)
	piece(model, "Tip", BALL, Vector3.one * radius * 0.6, CFrame.new(0, -12.5, 0), rockDark, Enum.Material.Rock)
	return finish(model, top, radius + 4)
end

-- Декоративное парящее кольцо из сегментов
function ToyModels.Ring(radius: number, color: Color3, segments: number): Toy
	local model = newModel("Ring")
	local first: Part? = nil
	for index = 1, segments do
		local a0 = (index - 1) / segments * 2 * math.pi
		local a1 = index / segments * 2 * math.pi
		local p0 = Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, 0)
		local p1 = Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, 0)
		local part = segment(model, "Segment" .. index, p0, p1, 1.1, color, NEON)
		if first == nil then
			first = part
		end
	end
	local primary = first or piece(model, "Center", BALL, Vector3.one, CFrame.new(), color, NEON, 1)
	return finish(model, primary, radius + 1)
end

-- Сдвигает/поворачивает всю модельку так, что её опорная точка встаёт в cframe
-- (без Model:PivotTo — работает и вне Workspace, и в тестовом движке)
function ToyModels.Place(toy: Toy, cframe: CFrame)
	local model = toy.Model
	local primary = model.PrimaryPart
	if primary == nil then
		return
	end
	local inverse = pivotOf(primary):Inverse()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = cframe * (inverse * descendant.CFrame)
		end
	end
end

-- Равномерно масштабирует модельку вокруг её опорной точки (Ball/Sphere-меши остаются круглыми)
function ToyModels.Scale(toy: Toy, factor: number)
	local primary = toy.Model.PrimaryPart
	if primary == nil or factor <= 0 then
		return
	end
	local pivot = pivotOf(primary)
	for _, descendant in toy.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local relative = pivot:ToObjectSpace(descendant.CFrame)
			descendant.Size *= factor
			descendant.CFrame = pivot * (relative - relative.Position + relative.Position * factor)
		end
	end
	primary.PivotOffset = primary.CFrame:ToObjectSpace(pivot)
	toy.Radius *= factor
end

-- Вклеивает модельку guest в host: ставит её в localCFrame относительно опоры host
-- и переносит детали внутрь host.Model (дерево на острове, капсулы в куполе и т.п.)
function ToyModels.Attach(host: Toy, guest: Toy, localCFrame: CFrame)
	local hostPrimary = host.Model.PrimaryPart
	if hostPrimary == nil then
		return
	end
	ToyModels.Place(guest, pivotOf(hostPrimary) * localCFrame)
	for _, child in guest.Model:GetChildren() do
		child.Parent = host.Model
	end
	guest.Model:Destroy()
end

-- Запоминает смещения деталей от опорной точки (для покадрового переноса через BulkMoveTo:
-- part[i].CFrame = pivot * offsets[i])
function ToyModels.Offsets(toy: Toy): ({ BasePart }, { CFrame })
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local primary = toy.Model.PrimaryPart
	if primary == nil then
		return parts, offsets
	end
	local inverse = pivotOf(primary):Inverse()
	for _, descendant in toy.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			table.insert(offsets, inverse * descendant.CFrame)
		end
	end
	return parts, offsets
end

return ToyModels
