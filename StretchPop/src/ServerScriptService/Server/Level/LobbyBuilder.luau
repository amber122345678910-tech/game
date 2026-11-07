--!strict
-- STRETCH-POP · LobbyBuilder: хаб Sky Plaza в центре веера полос.
-- Полосы уходят от хаба наружу (углы −80°…+80° в −Z половине мира), их мосты причаливают
-- к краю острова. Задняя (+Z) половина — площадь отдыха: Капсульная площадь с тремя
-- автоматами-гачей и Подиум чемпионов с кубками и тремя табло лидеров.
--
-- Уровни: травяной диск-остров (верх Y = 0) → кольцевые ступени → центральная терраса
-- (Y = 6) с фонтаном и гигантской рогаткой-монументом. Снизу — многоярусное скальное
-- основание с валунами, вокруг — парящие островки с деревьями, облака и неоновые кольца.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local LevelConfig = require(Shared.Config.LevelConfig)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local BuddyConfig = require(Shared.Config.BuddyConfig)
local ToyModels = require(Shared.Visual.ToyModels)

export type BoardKind = "Speed" | "Combo" | "Rebirths"

export type SlotGate = {
	Barrier: BasePart, -- светящаяся завеса: закрыта, пока у слота нет полосы
	Sign: BasePart, -- табличка над входом «ПОЛОСА • Ник» / «СВОБОДНО»
}

export type LobbyHandles = {
	Model: Model,
	Machines: { [string]: BasePart }, -- capsuleId → корпус автомата (ProximityPrompt + тег)
	Boards: { [BoardKind]: BasePart }, -- экраны табло (SurfaceGui вешает LeaderboardService)
	PodiumTops: { CFrame }, -- верх ступеней подиума: 1-е, 2-е, 3-е место
	SlotGates: { [number]: SlotGate },
}

local RGB = Color3.fromRGB
local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local WEDGE = Enum.PartType.Wedge
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local FONT = Enum.Font.FredokaOne

local Palette = {
	Grass = RGB(118, 214, 104),
	GrassDark = RGB(84, 178, 86),
	Dirt = RGB(176, 124, 86),
	Rock = RGB(150, 128, 114),
	RockDark = RGB(102, 86, 84),
	TileA = RGB(252, 238, 210),
	TileB = RGB(234, 206, 166),
	PathBed = RGB(206, 176, 136),
	Curb = RGB(248, 250, 255),
	Ink = RGB(28, 32, 56),
	LampPost = RGB(62, 68, 108),
	LampLight = RGB(255, 236, 170),
	Blue = RGB(66, 136, 255),
	Gold = RGB(255, 196, 40),
	Silver = RGB(206, 218, 236),
	Bronze = RGB(214, 132, 72),
	Water = RGB(110, 198, 255),
	Trunk = RGB(150, 98, 60),
	Leaves = RGB(96, 206, 110),
	Cloud = RGB(250, 252, 255),
}

local Plaza = {
	CapsuleAngle = 150, -- градусы в системе LevelConfig.SlotDirection (0 = вдоль первой полосы)
	PodiumAngle = 210,
	PlazaRadius = 98, -- центр площадки от центра хаба
	PlazaSize = 31,
	PathWidth = 16,
	StepHeight = 1.5,
	TerraceTop = 6,
}

local LobbyBuilder = {}

-- ── Примитивы ───────────────────────────────────────────────────────────────

local function direction(angleDegrees: number): Vector3
	local angle = math.rad(angleDegrees)
	return Vector3.new(math.sin(angle), 0, -math.cos(angle))
end

-- Кадр на земле хаба: позиция по полярным координатам, LookVector — к центру хаба
local function facingCenter(angleDegrees: number, radius: number, y: number): CFrame
	local position = LevelConfig.Hub.Center + direction(angleDegrees) * radius + Vector3.new(0, y, 0)
	local center = Vector3.new(LevelConfig.Hub.Center.X, position.Y, LevelConfig.Hub.Center.Z)
	return CFrame.lookAt(position, center)
end

local function makePart(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function decor(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = makePart(parent, name, shape, size, cframe, color, material)
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Вертикальный цилиндр (ось Roblox-цилиндра — X, кладём её вверх)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function disc(parent: Instance, name: string, radius: number, height: number, center: Vector3, color: Color3, material: Enum.Material, solid: boolean): Part
	local size = Vector3.new(height, radius * 2, radius * 2)
	local cframe = CFrame.new(center) * UPRIGHT
	return if solid then makePart(parent, name, CYLINDER, size, cframe, color, material) else decor(parent, name, CYLINDER, size, cframe, color, material)
end

local function addLight(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

local function addSurfaceText(part: BasePart, face: Enum.NormalId, text: string, textColor: Color3, strokeColor: Color3, pixelsPerStud: number): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui_" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = textColor
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 4
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

local function addBillboard(part: BasePart, title: string, subtitle: string, color: Color3, offsetY: number, maxDistance: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Billboard"
	billboard.Size = UDim2.fromScale(18, 6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = maxDistance
	billboard.AlwaysOnTop = false
	billboard.Parent = part
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.62)
	titleLabel.Font = FONT
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Parent = billboard
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Palette.Ink
	titleStroke.Thickness = 3
	titleStroke.Parent = titleLabel
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Position = UDim2.fromScale(0, 0.6)
	subtitleLabel.Size = UDim2.fromScale(1, 0.4)
	subtitleLabel.Font = FONT
	subtitleLabel.Text = subtitle
	subtitleLabel.TextScaled = true
	subtitleLabel.TextColor3 = color
	subtitleLabel.Parent = billboard
	local subtitleStroke = Instance.new("UIStroke")
	subtitleStroke.Color = Palette.Ink
	subtitleStroke.Thickness = 2.5
	subtitleStroke.Parent = subtitleLabel
end

local function placeToy(toy: ToyModels.Toy, cframe: CFrame, parent: Instance): Model
	ToyModels.Place(toy, cframe)
	toy.Model.Parent = parent
	return toy.Model
end

-- ── Остров и уровни ─────────────────────────────────────────────────────────

local function buildIsland(model: Model, rng: Random)
	local hub = LevelConfig.Hub
	local center = hub.Center
	local radius = hub.Radius
	local ground = disc(model, "HubGrass", radius, 4, center + Vector3.new(0, -2, 0), Palette.Grass, SMOOTH, true)
	ground:SetAttribute("PieceKind", "HubGround")
	disc(model, "HubGrassLip", radius + 1.2, 1.4, center + Vector3.new(0, -3.4, 0), Palette.GrassDark, SMOOTH, false)
	disc(model, "HubDirt", radius - 1, 6, center + Vector3.new(0, -7, 0), Palette.Dirt, Enum.Material.Slate, false)

	-- многоярусное скальное основание, сужающееся книзу
	local tiers = { { 0.94, 10, -15 }, { 0.78, 12, -26 }, { 0.6, 12, -37 }, { 0.4, 12, -48 }, { 0.22, 10, -58 } }
	for index, tierInfo in tiers do
		local color = if index % 2 == 1 then Palette.Rock else Palette.RockDark
		disc(model, "HubRock" .. index, radius * tierInfo[1], tierInfo[2], center + Vector3.new(0, tierInfo[3], 0), color, Enum.Material.Slate, false)
	end
	decor(model, "HubRockTip", BALL, Vector3.one * radius * 0.26, CFrame.new(center + Vector3.new(0, -66, 0)), Palette.RockDark, Enum.Material.Rock)

	-- валуны по краю основания — рваный «органический» силуэт
	for index = 1, 16 do
		local angle = index / 16 * 360 + rng:NextNumber(-6, 6)
		local boulderRadius = radius * rng:NextNumber(0.72, 0.9)
		local size = rng:NextNumber(14, 24)
		local position = center + direction(angle) * boulderRadius + Vector3.new(0, rng:NextNumber(-34, -14), 0)
		decor(model, "Boulder", BALL, Vector3.one * size, CFrame.new(position), if index % 3 == 0 then Palette.RockDark else Palette.Rock, Enum.Material.Rock)
	end
	-- свисающие «сталактиты»
	for index = 1, 10 do
		local angle = index / 10 * 360 + 18
		local position = center + direction(angle) * radius * rng:NextNumber(0.3, 0.55) + Vector3.new(0, -62, 0)
		local length = rng:NextNumber(12, 22)
		decor(model, "Stalactite", CYLINDER, Vector3.new(length, 5, 5), CFrame.new(position - Vector3.new(0, length * 0.5, 0)) * UPRIGHT, Palette.RockDark, Enum.Material.Rock)
		decor(model, "StalactiteTip", BALL, Vector3.one * 5, CFrame.new(position - Vector3.new(0, length, 0)), Palette.RockDark, Enum.Material.Rock)
	end

	-- кустики-кочки по траве (между дорожками)
	for index = 1, 26 do
		local angle = rng:NextNumber(0, 360)
		local distance = rng:NextNumber(72, radius - 10)
		local position = center + direction(angle) * distance
		local onLaneAxis = false
		for slot = 1, LevelConfig.MaxSlots do
			if math.abs(((angle - LevelConfig.SlotAngle(slot) + 540) % 360) - 180) < 9 then
				onLaneAxis = true
			end
		end
		local nearPlaza = math.abs(angle - Plaza.CapsuleAngle) < 26 or math.abs(angle - Plaza.PodiumAngle) < 26
		if not onLaneAxis and not nearPlaza then
			local size = rng:NextNumber(3, 5.5)
			decor(model, "Bush", BALL, Vector3.one * size, CFrame.new(position + Vector3.new(0, size * 0.25, 0)), Palette.GrassDark:Lerp(Palette.Leaves, rng:NextNumber()), SMOOTH)
			if index % 4 == 0 then
				decor(model, "Flower", BALL, Vector3.one * 0.9, CFrame.new(position + Vector3.new(0, size * 0.62, 0)), RGB(255, 120, 170), NEON)
			end
		end
	end
end

local function buildTerrace(model: Model)
	local hub = LevelConfig.Hub
	local center = hub.Center
	local stepCount = math.floor(Plaza.TerraceTop / Plaza.StepHeight + 0.5)
	-- круговые ступени: каждая на 1.5 stud выше, гуманоид шагает без прыжка
	for step = 1, stepCount do
		local top = step * Plaza.StepHeight
		local radius = hub.TerraceRadius + (stepCount - step) * 4
		local color = if step == stepCount then Palette.TileA else Palette.Curb:Lerp(Palette.TileB, (stepCount - step) / stepCount)
		local part = disc(model, "TerraceStep" .. step, radius, Plaza.StepHeight, center + Vector3.new(0, top - Plaza.StepHeight * 0.5, 0), color, SMOOTH, true)
		part:SetAttribute("PieceKind", "Terrace")
	end
	local top = Plaza.TerraceTop
	-- узор плитки на террасе: два концентрических кольца
	disc(model, "TerraceInlay", hub.TerraceRadius - 6, 0.12, center + Vector3.new(0, top + 0.06, 0), Palette.TileB, SMOOTH, false)
	disc(model, "TerraceInlayInner", hub.TerraceRadius - 10, 0.14, center + Vector3.new(0, top + 0.07, 0), Palette.TileA, SMOOTH, false)
	disc(model, "TerraceTrim", hub.TerraceRadius + 0.3, 0.5, center + Vector3.new(0, top - 0.2, 0), Palette.Blue, NEON, false)

	-- фонтан: бортик, вода, струи
	disc(model, "FountainRim", 17, 2.2, center + Vector3.new(0, top + 1.1, 0), Palette.Curb, SMOOTH, true)
	disc(model, "FountainWater", 15.6, 0.4, center + Vector3.new(0, top + 2.05, 0), Palette.Water, Enum.Material.Glass, false).Transparency = 0.25
	disc(model, "FountainGlow", 15.8, 0.15, center + Vector3.new(0, top + 1.9, 0), Palette.Water, NEON, false).Transparency = 0.5
	for index = 1, 6 do
		local angle = index / 6 * 360
		local spout = center + direction(angle) * 11 + Vector3.new(0, top + 3.5, 0)
		decor(model, "Jet", CYLINDER, Vector3.new(3, 0.8, 0.8), CFrame.new(spout) * UPRIGHT, Palette.Water, NEON).Transparency = 0.35
		decor(model, "JetDrop", BALL, Vector3.one * 1.2, CFrame.new(spout + Vector3.new(0, 1.8, 0)), Palette.Water, NEON).Transparency = 0.2
	end

	-- монумент: гигантская рогатка с неоновым жгутом посреди фонтана
	local monument = ToyModels.Slingshot(RGB(255, 80, 160))
	ToyModels.Scale(monument, 6.5)
	local statue = placeToy(monument, CFrame.new(center + Vector3.new(0, top + 2 + 2.4 * 6.5, 0)) * CFrame.Angles(0, math.pi, 0), model)
	statue.Name = "SlingshotMonument"
	local primary = statue.PrimaryPart
	if primary then
		addBillboard(primary, "SKY PLAZA", "STRETCH-POP", Palette.Gold, 34, 900)
	end

	-- фонари по кромке террасы
	for index = 1, 8 do
		local angle = index / 8 * 360 + 22.5
		local base = center + direction(angle) * (hub.TerraceRadius - 3) + Vector3.new(0, top, 0)
		local post = decor(model, "TerraceLampPost", CYLINDER, Vector3.new(8, 0.9, 0.9), CFrame.new(base + Vector3.new(0, 4, 0)) * UPRIGHT, Palette.LampPost, SMOOTH)
		post.CanCollide = true
		local bulb = decor(model, "TerraceLamp", BALL, Vector3.one * 2.4, CFrame.new(base + Vector3.new(0, 8.8, 0)), Palette.LampLight, NEON)
		decor(model, "TerraceLampCap", CYLINDER, Vector3.new(0.5, 2.8, 2.8), CFrame.new(base + Vector3.new(0, 10.1, 0)) * UPRIGHT, Palette.LampPost, SMOOTH)
		if index % 2 == 0 then
			addLight(bulb, Palette.LampLight, 18, 1.3)
		end
	end
end

-- ── Дорожки, бордюры, фонари ────────────────────────────────────────────────

local function buildLamp(model: Model, position: Vector3, withLight: boolean)
	local post = makePart(model, "LampPost", CYLINDER, Vector3.new(9, 0.8, 0.8), CFrame.new(position + Vector3.new(0, 4.5, 0)) * UPRIGHT, Palette.LampPost, SMOOTH)
	post.CanQuery = false
	decor(model, "LampFoot", CYLINDER, Vector3.new(0.8, 2, 2), CFrame.new(position + Vector3.new(0, 0.4, 0)) * UPRIGHT, Palette.LampPost, SMOOTH)
	local bulb = decor(model, "LampBulb", BALL, Vector3.one * 2.2, CFrame.new(position + Vector3.new(0, 9.6, 0)), Palette.LampLight, NEON)
	decor(model, "LampCap", CYLINDER, Vector3.new(0.45, 2.6, 2.6), CFrame.new(position + Vector3.new(0, 10.8, 0)) * UPRIGHT, Palette.LampPost, SMOOTH)
	if withLight then
		addLight(bulb, Palette.LampLight, 16, 1.2)
	end
end

-- Плиточная дорожка от fromRadius до toRadius по лучу angle
local function buildPath(model: Model, angleDegrees: number, fromRadius: number, toRadius: number, lamps: boolean)
	local center = LevelConfig.Hub.Center
	local dir = direction(angleDegrees)
	local right = dir:Cross(Vector3.yAxis).Unit
	local length = toRadius - fromRadius
	local mid = center + dir * (fromRadius + length * 0.5)
	local frame = CFrame.lookAt(mid, mid + dir)
	local width = Plaza.PathWidth
	decor(model, "PathBed", BLOCK, Vector3.new(width + 1, 0.3, length), frame * CFrame.new(0, 0.15, 0), Palette.PathBed, SMOOTH)
	local row = 0
	local tileLength = 5.6
	local distance = fromRadius + tileLength * 0.5 + 0.4
	while distance < toRadius - tileLength * 0.5 do
		for column = 0, 1 do
			local offset = (column - 0.5) * (width * 0.5)
			local position = center + dir * distance + right * offset + Vector3.new(0, 0.34, 0)
			local color = if (row + column) % 2 == 0 then Palette.TileA else Palette.TileB
			decor(model, "Tile", BLOCK, Vector3.new(width * 0.5 - 0.5, 0.12, tileLength - 0.5), CFrame.lookAt(position, position + dir), color, SMOOTH)
		end
		row += 1
		distance += tileLength
	end
	for _, side in { -1, 1 } do
		decor(model, "Curb", BLOCK, Vector3.new(1.2, 0.8, length), frame * CFrame.new(side * (width * 0.5 + 0.6), 0.4, 0), Palette.Curb, SMOOTH)
		if lamps then
			local lampDistance = fromRadius + 12
			local index = 0
			while lampDistance < toRadius - 6 do
				index += 1
				buildLamp(model, center + dir * lampDistance + right * side * (width * 0.5 + 3), index % 2 == 1)
				lampDistance += 30
			end
		end
	end
end

-- Бордюр по кромке острова с проёмами под мосты всех слотов
local function buildRim(model: Model)
	local hub = LevelConfig.Hub
	local center = hub.Center
	local radius = hub.Radius - 1
	local gapHalf = math.deg(math.asin((Plaza.PathWidth * 0.5 + 1.5) / radius))
	local segments = 90
	for index = 0, segments - 1 do
		local a0 = index / segments * 360
		local a1 = (index + 1) / segments * 360
		local mid = (a0 + a1) * 0.5
		local blocked = false
		for slot = 1, LevelConfig.MaxSlots do
			local slotAngle = LevelConfig.SlotAngle(slot)
			if math.abs(((mid - slotAngle + 540) % 360) - 180) < gapHalf + 2 then
				blocked = true
			end
		end
		if not blocked then
			local p0 = center + direction(a0) * radius
			local p1 = center + direction(a1) * radius
			local chord = (p1 - p0).Magnitude
			local position = (p0 + p1) * 0.5
			local frame = CFrame.lookAt(position + Vector3.new(0, 1.3, 0), position + Vector3.new(0, 1.3, 0) + (p1 - p0).Unit)
			local curb = makePart(model, "RimCurb", BLOCK, Vector3.new(1.8, 2.6, chord + 0.2), frame, Palette.Curb, SMOOTH)
			curb.CanQuery = true
			decor(model, "RimNeon", BLOCK, Vector3.new(1.9, 0.35, chord + 0.25), frame * CFrame.new(0, 1.35, 0), Palette.Blue, NEON)
		end
	end
end

-- Вход на мост слота: арка с табличкой + завеса, пока полосы нет
local function buildSlotGate(model: Model, slot: number): SlotGate
	local hub = LevelConfig.Hub
	local angle = LevelConfig.SlotAngle(slot)
	local dir = direction(angle)
	local right = dir:Cross(Vector3.yAxis).Unit
	local gateCenter = hub.Center + dir * (hub.Radius - 6)
	local halfWidth = Plaza.PathWidth * 0.5 + 1.6
	for _, side in { -1, 1 } do
		local base = gateCenter + right * side * halfWidth
		local pillar = makePart(model, "GatePillar", CYLINDER, Vector3.new(14, 1.8, 1.8), CFrame.new(base + Vector3.new(0, 7, 0)) * UPRIGHT, Palette.Curb, SMOOTH)
		pillar.CanQuery = false
		decor(model, "GatePillarNeon", BALL, Vector3.one * 2.6, CFrame.new(base + Vector3.new(0, 14.6, 0)), Palette.Gold, NEON)
	end
	local beamFrame = CFrame.lookAt(gateCenter + Vector3.new(0, 13.4, 0), gateCenter + Vector3.new(0, 13.4, 0) - dir)
	decor(model, "GateBeam", BLOCK, Vector3.new(halfWidth * 2 + 2, 1.6, 1.6), beamFrame, Palette.Ink, SMOOTH)
	local sign = decor(model, "SlotSign", BLOCK, Vector3.new(halfWidth * 2 - 1, 3.6, 0.5), beamFrame * CFrame.new(0, -2.6, 0), Palette.Blue, SMOOTH)
	sign:SetAttribute("Slot", slot)
	addSurfaceText(sign, Enum.NormalId.Front, "СВОБОДНО", Color3.new(1, 1, 1), Palette.Ink, 40)
	addSurfaceText(sign, Enum.NormalId.Back, "SKY PLAZA", Color3.new(1, 1, 1), Palette.Ink, 40)

	local barrier = makePart(model, "SlotBarrier", BLOCK, Vector3.new(halfWidth * 2, 10, 0.6), CFrame.lookAt(gateCenter + Vector3.new(0, 5, 0), gateCenter + Vector3.new(0, 5, 0) - dir), Palette.Blue, Enum.Material.ForceField)
	barrier.Transparency = 0.2
	barrier.CastShadow = false
	barrier:SetAttribute("Slot", slot)
	return { Barrier = barrier, Sign = sign }
end

-- ── Капсульная площадь ──────────────────────────────────────────────────────

local function buildPlazaFloor(model: Model, angleDegrees: number, accent: Color3): CFrame
	local frame = facingCenter(angleDegrees, Plaza.PlazaRadius, 0)
	local center = frame.Position
	local floor = disc(model, "PlazaFloor", Plaza.PlazaSize, Plaza.StepHeight, center + Vector3.new(0, Plaza.StepHeight * 0.5, 0), Palette.TileA, SMOOTH, true)
	floor:SetAttribute("PieceKind", "Plaza")
	disc(model, "PlazaRing", Plaza.PlazaSize - 4, 0.12, center + Vector3.new(0, Plaza.StepHeight + 0.06, 0), Palette.TileB, SMOOTH, false)
	disc(model, "PlazaCore", Plaza.PlazaSize - 9, 0.14, center + Vector3.new(0, Plaza.StepHeight + 0.07, 0), Palette.TileA, SMOOTH, false)
	disc(model, "PlazaTrim", Plaza.PlazaSize + 0.4, 0.45, center + Vector3.new(0, Plaza.StepHeight - 0.1, 0), accent, NEON, false)
	return frame + Vector3.new(0, Plaza.StepHeight, 0)
end

local function buildMachine(model: Model, def: BuddyConfig.CapsuleDef, frame: CFrame, rng: Random): BasePart
	-- frame: точка на полу, LookVector — к игроку
	local machine = Instance.new("Model")
	machine.Name = "CapsuleMachine_" .. def.Id
	machine.Parent = model
	local glow = def.GlowColor
	local bodyColor = def.TopColor:Lerp(Palette.Ink, if def.Id == "Void" then 0.55 else 0.12)
	local trim = def.BottomColor

	decor(machine, "Pedestal", CYLINDER, Vector3.new(2, 13, 13), frame * CFrame.new(0, 1, 0) * UPRIGHT, trim, SMOOTH).CanCollide = true
	decor(machine, "PedestalNeon", CYLINDER, Vector3.new(0.4, 13.5, 13.5), frame * CFrame.new(0, 2.1, 0) * UPRIGHT, glow, NEON)
	local body = makePart(machine, "Body", BLOCK, Vector3.new(9, 9, 9), frame * CFrame.new(0, 6.5, 0), bodyColor, SMOOTH)
	body:AddTag(PhysicsConfig.Tags.CapsuleMachine)
	body:SetAttribute("CapsuleId", def.Id)
	body:SetAttribute("Price", def.Price)
	-- лицевая панель (−Z модели = LookVector = к игроку)
	decor(machine, "Panel", BLOCK, Vector3.new(7, 6.2, 0.4), frame * CFrame.new(0, 6.9, -4.6), Palette.Ink, SMOOTH)
	decor(machine, "CoinSlot", BLOCK, Vector3.new(0.5, 1.6, 0.3), frame * CFrame.new(2.2, 8.4, -4.85), glow, NEON)
	decor(machine, "Knob", CYLINDER, Vector3.new(0.6, 2.6, 2.6), frame * CFrame.new(-0.9, 8.1, -4.9) * CFrame.Angles(0, math.pi / 2, 0), trim, SMOOTH)
	decor(machine, "KnobGrip", BLOCK, Vector3.new(0.35, 2.2, 0.5), frame * CFrame.new(-0.9, 8.1, -5.3), Palette.Ink, SMOOTH)
	decor(machine, "Chute", BLOCK, Vector3.new(3.2, 2.2, 0.6), frame * CFrame.new(0, 4.4, -4.85), RGB(10, 12, 24), SMOOTH)
	decor(machine, "ChuteFlap", BLOCK, Vector3.new(3, 0.4, 0.7), frame * CFrame.new(0, 5.5, -4.9), glow, NEON)
	for _, side in { -1, 1 } do
		decor(machine, "SideStripe", BLOCK, Vector3.new(0.3, 9.2, 1.2), frame * CFrame.new(side * 4.55, 6.5, -3.4), glow, NEON)
	end
	-- купол с капсулами
	decor(machine, "DomeRim", CYLINDER, Vector3.new(1, 11, 11), frame * CFrame.new(0, 11.5, 0) * UPRIGHT, Palette.Silver, Enum.Material.Metal)
	local dome = decor(machine, "Dome", BALL, Vector3.one * 11.6, frame * CFrame.new(0, 15.4, 0), RGB(224, 242, 255), Enum.Material.Glass)
	dome.Transparency = 0.62
	for index = 1, 7 do
		local capsule = ToyModels.Capsule(def.Id)
		ToyModels.Scale(capsule, 1.05)
		local angle = index / 7 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local spread = if index == 7 then 0 else 2.6
		local local_ = CFrame.new(math.cos(angle) * spread, 13.4 + (if index == 7 then 2.4 else rng:NextNumber(0, 0.8)), math.sin(angle) * spread)
			* CFrame.Angles(rng:NextNumber(-0.8, 0.8), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.8, 0.8))
		placeToy(capsule, frame * local_, machine)
	end
	local crown = decor(machine, "Crown", BALL, Vector3.one * 3, frame * CFrame.new(0, 21.6, 0), glow, NEON)
	addLight(crown, glow, 22, 2)
	decor(machine, "CrownBase", CYLINDER, Vector3.new(0.8, 4, 4), frame * CFrame.new(0, 20.6, 0) * UPRIGHT, Palette.Silver, Enum.Material.Metal)

	addBillboard(body, def.DisplayName, string.format("%d монет", def.Price), glow, 13, 140)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HatchPrompt"
	prompt.ActionText = "Открыть капсулу"
	prompt.ObjectText = string.format("%s • %d", def.DisplayName, def.Price)
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = body
	return body
end

local function buildCapsulePlaza(model: Model, rng: Random): { [string]: BasePart }
	local plaza = Instance.new("Model")
	plaza.Name = "CapsulePlaza"
	plaza.Parent = model
	local frame = buildPlazaFloor(plaza, Plaza.CapsuleAngle, RGB(170, 110, 255))
	local machines: { [string]: BasePart } = {}
	local order = { "Basic", "Golden", "Void" }
	for index, capsuleId in order do
		local def = BuddyConfig.Capsules[capsuleId]
		if def then
			-- дуга из трёх автоматов на дальней стороне площади, все смотрят на вход
			local offset = (index - 2) * 17
			local depth = -(math.abs(index - 2) * 4) + 12
			local spot = (frame * CFrame.new(offset, 0, depth)).Position
			-- лицом (LookVector = передняя панель) ко входу на площадь со стороны террасы
			local target = frame.Position + frame.LookVector * 24
			machines[capsuleId] = buildMachine(plaza, def, CFrame.lookAt(spot, Vector3.new(target.X, spot.Y, target.Z)), rng)
		end
	end
	local signPost = frame * CFrame.new(0, 0, 26)
	local board = decor(plaza, "PlazaSign", BLOCK, Vector3.new(30, 6, 0.8), signPost * CFrame.new(0, 27, 0) * CFrame.Angles(0, math.pi, 0), RGB(150, 90, 255), SMOOTH)
	addSurfaceText(board, Enum.NormalId.Back, "КАПСУЛЬНАЯ ПЛОЩАДЬ", Color3.new(1, 1, 1), Palette.Ink, 30)
	addSurfaceText(board, Enum.NormalId.Front, "КАПСУЛЬНАЯ ПЛОЩАДЬ", Color3.new(1, 1, 1), Palette.Ink, 30)
	for _, side in { -1, 1 } do
		decor(plaza, "PlazaSignPost", CYLINDER, Vector3.new(27, 1.2, 1.2), signPost * CFrame.new(side * 13, 13.5, 0) * UPRIGHT, Palette.Ink, SMOOTH)
	end
	return machines
end

-- ── Подиум чемпионов ────────────────────────────────────────────────────────

local function buildPodium(model: Model): ({ [BoardKind]: BasePart }, { CFrame })
	local podium = Instance.new("Model")
	podium.Name = "ChampionsPodium"
	podium.Parent = model
	local frame = buildPlazaFloor(podium, Plaza.PodiumAngle, Palette.Gold)

	-- ступени: 1-е место по центру и выше всех, 2-е слева, 3-е справа (с точки зрения смотрящего)
	local steps = {
		{ Place = 1, Offset = 0, Height = 8, Color = Palette.Gold, Label = "1" },
		{ Place = 2, Offset = -9.5, Height = 5.5, Color = Palette.Silver, Label = "2" },
		{ Place = 3, Offset = 9.5, Height = 3.5, Color = Palette.Bronze, Label = "3" },
	}
	local tops: { CFrame } = {}
	for _, info in steps do
		-- frame смотрит на центр хаба; подиум «лицом» к центру → смотрящий стоит у −Z/LookVector
		local base = frame * CFrame.new(-info.Offset, 0, 2)
		local block = makePart(podium, "PodiumStep" .. info.Place, BLOCK, Vector3.new(9, info.Height, 9), base * CFrame.new(0, info.Height * 0.5, 0), Palette.Curb, SMOOTH)
		decor(podium, "PodiumTrim", BLOCK, Vector3.new(9.3, 0.6, 9.3), base * CFrame.new(0, info.Height - 0.2, 0), info.Color, NEON)
		local label = decor(podium, "PodiumNumber", BLOCK, Vector3.new(5, 4, 0.3), base * CFrame.new(0, info.Height * 0.5, -4.65), info.Color, SMOOTH)
		addSurfaceText(label, Enum.NormalId.Front, info.Label, Color3.new(1, 1, 1), Palette.Ink, 40)
		local trophy = ToyModels.Trophy(info.Color)
		ToyModels.Scale(trophy, if info.Place == 1 then 2.2 else 1.8)
		placeToy(trophy, base * CFrame.new(0, info.Height + 1.8 * (if info.Place == 1 then 2.2 else 1.8), 2.2), podium)
		local glow = decor(podium, "TrophyGlow", BALL, Vector3.one * 1.2, base * CFrame.new(0, info.Height + 9, 2.2), info.Color, NEON)
		glow.Transparency = 0.6
		addLight(glow, info.Color, 14, 1.6)
		tops[info.Place] = base * CFrame.new(0, info.Height, -1.5)
		block:SetAttribute("PodiumPlace", info.Place)
	end

	-- три табло полукругом за подиумом
	local boards: { [BoardKind]: BasePart } = {}
	local boardInfo: { { Kind: BoardKind, Offset: number, Yaw: number, Accent: Color3 } } = {
		{ Kind = "Speed", Offset = -25, Yaw = -22, Accent = Palette.Blue },
		{ Kind = "Combo", Offset = 0, Yaw = 0, Accent = RGB(255, 90, 150) },
		{ Kind = "Rebirths", Offset = 25, Yaw = 22, Accent = Palette.Gold },
	}
	for _, info in boardInfo do
		local base = frame * CFrame.new(-info.Offset, 0, 17 - math.abs(info.Offset) * 0.28) * CFrame.Angles(0, math.rad(-info.Yaw), 0)
		for _, side in { -1, 1 } do
			makePart(podium, "BoardLeg", CYLINDER, Vector3.new(8, 1.4, 1.4), base * CFrame.new(side * 8, 4, 0.6) * UPRIGHT, Palette.Ink, SMOOTH).CanQuery = false
		end
		decor(podium, "BoardUnderlay", BLOCK, Vector3.new(23.4, 27.4, 1), base * CFrame.new(0, 21.6, 1.2), RGB(195, 206, 230), SMOOTH)
		decor(podium, "BoardFrame", BLOCK, Vector3.new(22.6, 26.6, 1.1), base * CFrame.new(0, 22, 0.8), Palette.Ink, SMOOTH)
		local screen = decor(podium, "Board_" .. info.Kind, BLOCK, Vector3.new(21, 25, 0.4), base * CFrame.new(0, 22, 0.15), RGB(248, 250, 255), SMOOTH)
		screen:SetAttribute("BoardKind", info.Kind)
		local cap = decor(podium, "BoardCap", BLOCK, Vector3.new(23.6, 1, 1.6), base * CFrame.new(0, 35.4, 0.8), info.Accent, NEON)
		addLight(cap, info.Accent, 20, 1.4)
		boards[info.Kind] = screen
	end

	-- арка-баннер над входом на подиум (проход под ней свободен)
	local signFrame = frame * CFrame.new(0, 15, -20)
	local sign = decor(podium, "PodiumSign", BLOCK, Vector3.new(28, 5, 0.8), signFrame, Palette.Gold, SMOOTH)
	for _, side in { -1, 1 } do
		decor(podium, "PodiumSignPost", CYLINDER, Vector3.new(17.5, 1.2, 1.2), signFrame * CFrame.new(side * 13, -6.25, 0) * UPRIGHT, Palette.Ink, SMOOTH)
	end
	addSurfaceText(sign, Enum.NormalId.Front, "ПОДИУМ ЧЕМПИОНОВ", Color3.new(1, 1, 1), Palette.Ink, 30)
	addSurfaceText(sign, Enum.NormalId.Back, "ПОДИУМ ЧЕМПИОНОВ", Color3.new(1, 1, 1), Palette.Ink, 30)
	return boards, tops
end

-- ── Окружение ───────────────────────────────────────────────────────────────

local function buildEnvironment(model: Model, rng: Random)
	local environment = Instance.new("Folder")
	environment.Name = "Environment"
	environment.Parent = model
	local center = LevelConfig.Hub.Center

	-- Парящие острова в задней полусфере (полосы — спереди, там тесно)
	local islandAngles = { 104, 128, 163, 197, 232, 256 }
	for index, angle in islandAngles do
		local radius = rng:NextNumber(12, 19)
		local island = ToyModels.Island(radius, Palette.Grass, Palette.Rock, Palette.RockDark)
		for tree = 1, rng:NextInteger(2, 4) do
			local treeAngle = tree / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local spot = rng:NextNumber(0.2, 0.62) * radius
			local toy = ToyModels.Tree(rng:NextNumber(0.85, 1.25), Palette.Trunk, Enum.Material.Wood, Palette.Leaves:Lerp(RGB(255, 170, 210), if tree % 3 == 0 then 0.55 else 0), SMOOTH, rng)
			ToyModels.Attach(island, toy, CFrame.new(math.cos(treeAngle) * spot, 0, math.sin(treeAngle) * spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		end
		local distance = rng:NextNumber(205, 262)
		local height = if index % 2 == 0 then rng:NextNumber(14, 34) else rng:NextNumber(-30, -8)
		placeToy(island, CFrame.new(center + direction(angle) * distance + Vector3.new(0, height, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), environment)
	end

	-- Облака: высоко над полосами и глубоко под ними (не мешают полёту)
	for index = 1, 18 do
		local angle = rng:NextNumber(0, 360)
		local distance = rng:NextNumber(170, 460)
		local height = if index % 3 == 0 then rng:NextNumber(-130, -90) else rng:NextNumber(100, 160)
		local cloud = ToyModels.Cloud(rng:NextNumber(1, 2), Palette.Cloud, rng)
		placeToy(cloud, CFrame.new(center + direction(angle) * distance + Vector3.new(0, height, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), environment)
	end

	-- Неоновые кольца над задней половиной хаба
	local ringColors = { RGB(80, 220, 255), RGB(255, 110, 200), RGB(255, 210, 70), RGB(150, 255, 110), RGB(180, 120, 255) }
	for index, color in ringColors do
		local angle = 120 + index * 24
		local ring = ToyModels.Ring(rng:NextNumber(8, 13), color, 20)
		local position = center + direction(angle) * rng:NextNumber(150, 200) + Vector3.new(0, rng:NextNumber(36, 64), 0)
		placeToy(ring, CFrame.lookAt(position, center + Vector3.new(0, position.Y, 0)) * CFrame.Angles(0, 0, rng:NextNumber(-0.4, 0.4)), environment)
	end
end

-- ── Публичное API ───────────────────────────────────────────────────────────

function LobbyBuilder.Build(parent: Instance): LobbyHandles
	local rng = Random.new(20261107)
	local model = Instance.new("Model")
	model.Name = "SkyPlaza"

	buildIsland(model, rng)
	buildTerrace(model)

	local terraceFoot = LevelConfig.Hub.TerraceRadius + 13
	local hubEdge = LevelConfig.Hub.Radius - 2
	local gates: { [number]: SlotGate } = {}
	for slot = 1, LevelConfig.MaxSlots do
		buildPath(model, LevelConfig.SlotAngle(slot), terraceFoot, hubEdge, true)
		gates[slot] = buildSlotGate(model, slot)
	end
	-- площади примыкают прямо к нижней ступени террасы; к смотровой ведёт отдельная дорожка
	buildPath(model, 180, terraceFoot, hubEdge - 6, true)
	buildRim(model)

	local machines = buildCapsulePlaza(model, rng)
	local boards, tops = buildPodium(model)
	buildEnvironment(model, rng)

	-- смотровая площадка в конце задней дорожки: перила и бинокль-«пружина»
	local lookout = facingCenter(180, LevelConfig.Hub.Radius - 12, 0)
	decor(model, "LookoutDeck", CYLINDER, Vector3.new(0.3, 22, 22), lookout * CFrame.new(0, 0.3, 0) * UPRIGHT, Palette.TileB, SMOOTH)
	local spring = ToyModels.Spring(RGB(255, 90, 120))
	ToyModels.Scale(spring, 2.2)
	placeToy(spring, lookout * CFrame.new(0, 4, 4), model)

	model.Parent = parent
	return {
		Model = model,
		Machines = machines,
		Boards = boards,
		PodiumTops = tops,
		SlotGates = gates,
	}
end

-- Слот занят полосой → завеса исчезает, на табличке ник владельца
function LobbyBuilder.SetSlotOwner(handles: LobbyHandles, slot: number, ownerName: string?)
	local gate = handles.SlotGates[slot]
	if gate == nil then
		return
	end
	local open = ownerName ~= nil
	gate.Barrier.CanCollide = not open
	gate.Barrier.Transparency = if open then 1 else 0.2
	local gui = gate.Sign:FindFirstChild("Gui_Front")
	local label = if gui then gui:FindFirstChild("Text") else nil
	if label and label:IsA("TextLabel") then
		label.Text = if ownerName then "ПОЛОСА • " .. ownerName else "СВОБОДНО"
	end
	gate.Sign.Color = if open then Palette.Gold else Palette.Blue
end

LobbyBuilder.Palette = Palette

return LobbyBuilder
