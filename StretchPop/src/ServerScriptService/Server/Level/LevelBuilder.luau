--!strict
-- STRETCH-POP · Процедурная полоса препятствий.
-- GenerateLayout — чистая детерминированная функция (seed локации + тир → одинаковая трасса),
-- Build* — превращение описания в анкерные детали с атрибутами и тегами для клиента и сервера.
-- Локальные координаты полосы: старт в (0,0,0), верх пола на Y = 0, полоса уходит в −Z,
-- +Z смотрит на хаб Sky Plaza (туда ведёт мост от стартовой площадки).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local LevelConfig = require(Shared.Config.LevelConfig)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local PinataMotion = require(Shared.Physics.PinataMotion)
local ToyModels = require(Shared.Visual.ToyModels)

local Tags = PhysicsConfig.Tags

export type PieceKind =
	"Floor"
	| "Stripe"
	| "Rail"
	| "Post"
	| "Ring"
	| "Arch"
	| "Bumper"
	| "BumperBall"
	| "Island"
	| "GongBase"
	| "GongFrame"
	| "GongDisc"
	| "GongSign"
	| "Foundation"
	| "FoundationDeep"
	| "RockSpike"
	| "Girder"
	| "Chevron"
	| "BoostRing"
	| "DecorIsland"
	| "Cloud"
	| "DecorRing"

export type PieceSpec = {
	Kind: PieceKind,
	LocalCFrame: CFrame,
	Size: Vector3,
	Shape: Enum.PartType,
	Seed: number?,
	Scale: number?,
}

export type ObstacleSpec = {
	Id: string,
	Kind: "Wall" | "Chest" | "Pinata",
	Strength: string,
	LocalCFrame: CFrame,
	Size: Vector3,
	RequiredSpeed: number, -- для подсказок: скорость пробития при m = 1
	Durability: number, -- энергия ½mv², нужная для пробития
	Loot: number,
	Motion: PinataMotion.MotionSpec?, -- только у пиньят
}

export type RingSpec = {
	Id: string,
	LocalCFrame: CFrame,
	Radius: number,
}

export type Gap = {
	From: number, -- ближняя к старту граница (больше, т.к. ось −Z)
	To: number,
}

export type LaneLayout = {
	LocationId: string,
	Tier: number,
	Seed: number,
	Length: number,
	Pieces: { PieceSpec },
	Obstacles: { ObstacleSpec },
	Rings: { RingSpec },
	Gaps: { Gap },
	GongLocalCFrame: CFrame,
}

export type BuildContext = {
	Origin: CFrame,
	Theme: LevelConfig.Theme,
	Slot: number,
	Tier: number,
	OwnerUserId: number,
	OwnerName: string,
	BestSpeed: number,
}

export type LaneHandles = {
	Model: Model,
	Static: Folder,
	Mutable: Folder,
	ObstacleFolder: Folder,
	StartPad: BasePart,
	StartSign: BasePart,
	GateSign: BasePart,
	Gong: BasePart?,
	Obstacles: { [string]: BasePart },
}

type BeatKind = "Wall" | "Chests" | "Bumpers" | "Anchors" | "Island"

type Bounds = {
	Min: Vector3,
	Max: Vector3,
}

local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local WEDGE = Enum.PartType.Wedge
local NEON = Enum.Material.Neon

-- «Мешок» тактов (как 7-bag в тетрисе): на каждые 8 тактов гарантированно 3 стены,
-- 2 россыпи сундуков, бамперы, якоря и остров — трасса разнообразна при любом seed.
local BEAT_BAG: { BeatKind } = { "Wall", "Wall", "Wall", "Chests", "Chests", "Bumpers", "Anchors", "Island" }

local LevelBuilder = {}

local function isOverGap(gaps: { Gap }, z: number, margin: number): boolean
	for _, gap in gaps do
		if z <= gap.From + margin and z >= gap.To - margin then
			return true
		end
	end
	return false
end

local function shuffle<T>(list: { T }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Мировой AABB повернутого бокса
local function boundsOf(cframe: CFrame, size: Vector3): Bounds
	local half = size * 0.5
	local right, up, look = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local extent = Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
	)
	return { Min = cframe.Position - extent, Max = cframe.Position + extent }
end

local function boundsOverlap(a: Bounds, b: Bounds, margin: number): boolean
	return a.Min.X - margin < b.Max.X
		and a.Max.X + margin > b.Min.X
		and a.Min.Y - margin < b.Max.Y
		and a.Max.Y + margin > b.Min.Y
		and a.Min.Z - margin < b.Max.Z
		and a.Max.Z + margin > b.Min.Z
end

function LevelBuilder.GenerateLayout(locationId: string, tier: number): LaneLayout
	local location = LevelConfig.Locations[locationId] or LevelConfig.Locations[LevelConfig.DefaultLocation]
	local seed = location.Seed * 31 + tier * 7919
	local rng = Random.new(seed)
	local length = LevelConfig.LaneLength(tier)
	local width = LevelConfig.LaneWidth
	local halfWidth = width / 2
	local durabilityMultiplier = LevelConfig.DurabilityMultiplier(tier)
	local lootMultiplier = LevelConfig.LootMultiplier(tier)
	local chestSize = LevelConfig.Chest.Size
	local strengths = LevelConfig.WallStrengths

	local pieces: { PieceSpec } = {}
	local obstacles: { ObstacleSpec } = {}
	local rings: { RingSpec } = {}
	local gaps: { Gap } = {}
	local occupied: { Bounds } = {}
	local obstacleIndex = 0

	local function claim(cframe: CFrame, size: Vector3, margin: number): boolean
		local bounds = boundsOf(cframe, size)
		for _, other in occupied do
			if boundsOverlap(bounds, other, margin) then
				return false
			end
		end
		table.insert(occupied, bounds)
		return true
	end

	local function addPiece(kind: PieceKind, cframe: CFrame, size: Vector3, shape: Enum.PartType)
		table.insert(pieces, { Kind = kind, LocalCFrame = cframe, Size = size, Shape = shape })
	end

	local function addDecor(kind: PieceKind, cframe: CFrame, scale: number)
		table.insert(pieces, {
			Kind = kind,
			LocalCFrame = cframe,
			Size = Vector3.one * scale,
			Shape = BLOCK,
			Seed = rng:NextInteger(1, 2 ^ 20),
			Scale = scale,
		})
	end

	local function addFloorSegment(zStart: number, zEnd: number)
		local segmentLength = zStart - zEnd
		local zCenter = (zStart + zEnd) * 0.5
		addPiece("Floor", CFrame.new(0, -3, zCenter), Vector3.new(width, 6, segmentLength), BLOCK)
		-- Бортики-пружины по краям: цилиндр вдоль Z (ось цилиндра = локальная X → поворот на 90° вокруг Y)
		for _, side in { -1, 1 } do
			addPiece(
				"Rail",
				CFrame.new(side * (halfWidth + 2.5), 2.2, zCenter) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(segmentLength, 5, 5),
				CYLINDER
			)
		end
		-- Массивное основание: скальный пласт, глубинная порода, стальные балки и сталактиты
		addPiece("Foundation", CFrame.new(0, -13, zCenter), Vector3.new(width + 6, 14, segmentLength), BLOCK)
		addPiece("FoundationDeep", CFrame.new(0, -27, zCenter), Vector3.new(width - 16, 14, math.max(segmentLength - 12, 6)), BLOCK)
		for _, side in { -1, 1 } do
			addPiece("Girder", CFrame.new(side * (halfWidth - 9), -7.5, zCenter), Vector3.new(2.6, 3, segmentLength), BLOCK)
		end
		local beamZ = zStart - 12
		while beamZ > zEnd + 6 do
			addPiece("Girder", CFrame.new(0, -7.2, beamZ), Vector3.new(width - 14, 2.2, 2.6), BLOCK)
			beamZ -= 40
		end
		for _ = 1, math.max(1, math.floor(segmentLength / 45)) do
			local spikeHeight = rng:NextNumber(10, 18)
			addPiece(
				"RockSpike",
				CFrame.new(rng:NextNumber(-halfWidth + 14, halfWidth - 14), -34 - spikeHeight * 0.5, rng:NextNumber(zEnd + 6, zStart - 6))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.pi),
				Vector3.new(rng:NextNumber(7, 12), spikeHeight, rng:NextNumber(7, 12)),
				WEDGE
			)
		end
		-- Разметка: белые полосы и неоновые шевроны «>>>» по центру
		local stripeZ = zStart - 20
		while stripeZ > zEnd + 4 do
			for _, side in { -1, 1 } do
				addPiece("Stripe", CFrame.new(side * (halfWidth - 3), 0.1, stripeZ), Vector3.new(2, 0.2, 14), BLOCK)
			end
			stripeZ -= 40
		end
		local chevronZ = zStart - 30
		while chevronZ > zEnd + 10 do
			for index = 0, 2 do
				local tip = chevronZ - index * 3.4
				for _, side in { -1, 1 } do
					addPiece(
						"Chevron",
						CFrame.new(side * 1.72, 0.09, tip + 2.46) * CFrame.Angles(0, side * math.rad(35), 0),
						Vector3.new(1.1, 0.14, 6),
						BLOCK
					)
				end
			end
			chevronZ -= 48
		end
	end

	local function addPost(x: number, z: number, height: number)
		addPiece("Post", CFrame.new(x, height * 0.5, z) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, 3.2, 3.2), CYLINDER)
		addPiece("Ring", CFrame.new(x, height + 1.8, z), Vector3.new(4.6, 4.6, 4.6), BALL)
	end

	local function addArch(z: number, y: number)
		addPiece("Arch", CFrame.new(0, y, z), Vector3.new(width - 12, 2.4, 2.4), BLOCK)
		for _, x in { -width * 0.25, 0, width * 0.25 } do
			addPiece("Ring", CFrame.new(x, y - 3, z), Vector3.new(4.2, 4.2, 4.2), BALL)
		end
	end

	local function addWall(strengthIndex: number, x: number, z: number, wallWidth: number, height: number)
		local strength = strengths[strengthIndex]
		local cframe = CFrame.new(x, height * 0.5, z)
		local size = Vector3.new(wallWidth, height, strength.Thickness)
		if not claim(cframe, size, 0.1) then
			return
		end
		obstacleIndex += 1
		table.insert(obstacles, {
			Id = string.format("T%d-%d", tier, obstacleIndex),
			Kind = "Wall",
			Strength = strength.Name,
			LocalCFrame = cframe,
			Size = size,
			RequiredSpeed = strength.RequiredSpeed * math.sqrt(durabilityMultiplier),
			Durability = StretchPhysics.DurabilityFromSpeed(strength.RequiredSpeed, durabilityMultiplier),
			Loot = math.max(1, math.floor(strength.Loot * lootMultiplier * math.sqrt(wallWidth / (width - 2)) + 0.5)),
			Motion = nil,
		})
	end

	local function addChest(x: number, y: number, z: number, yaw: number): boolean
		local cframe = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		-- запас под крышку/обручи сундука
		if not claim(cframe, chestSize + Vector3.new(1.2, 2.2, 1.2), 1.5) then
			return false
		end
		obstacleIndex += 1
		table.insert(obstacles, {
			Id = string.format("T%d-%d", tier, obstacleIndex),
			Kind = "Chest",
			Strength = "Chest",
			LocalCFrame = cframe,
			Size = chestSize,
			RequiredSpeed = LevelConfig.Chest.RequiredSpeed * math.sqrt(durabilityMultiplier),
			Durability = StretchPhysics.DurabilityFromSpeed(LevelConfig.Chest.RequiredSpeed, durabilityMultiplier),
			Loot = math.floor(LevelConfig.Chest.Loot * lootMultiplier + 0.5),
			Motion = nil,
		})
		return true
	end

	local function strengthFor(progress: number): number
		local raw = progress * 3.1 + rng:NextNumber() * 1.3 + math.min(tier, 6) * 0.3
		return math.clamp(math.floor(raw) + 1, 1, #strengths)
	end

	-- 1) Взлётная полоса (с провалами начиная с Cyber-Slime)
	local runwayStart = -LevelConfig.StartPadSize.Z * 0.5
	local runwayEnd = -(length - 40)
	local gapChance = if tier >= 2 then math.min(0.14 * (tier - 1), 0.42) else 0
	local z = runwayStart
	while z > runwayEnd + 1 do
		local segmentEnd = math.max(z - rng:NextInteger(90, 150), runwayEnd)
		addFloorSegment(z, segmentEnd)
		z = segmentEnd
		if gapChance > 0 and z > runwayEnd + 170 and rng:NextNumber() < gapChance then
			local gapLength = rng:NextInteger(40, 60 + 8 * math.min(tier, 6))
			table.insert(gaps, { From = z, To = z - gapLength })
			addPost(-halfWidth + 6, z - 3, 40)
			addPost(halfWidth - 6, z - 3, 40)
			addArch(z - gapLength * 0.5, 48)
			z -= gapLength
		end
	end

	-- 2) «Вилка» рогатки сразу за стартом
	addPost(-16, -50, 30)
	addPost(16, -50, 30)

	-- 3) Такты препятствий
	local cursor = -110
	local beatLimit = runwayEnd + 60
	local bag: { BeatKind } = {}
	while cursor > beatLimit do
		local progress = math.clamp(-cursor / length, 0, 1)
		local beat: BeatKind
		if isOverGap(gaps, cursor, 14) then
			beat = "Island" -- над провалом — только парящие острова-ступеньки (мешок не тратится)
		else
			if #bag == 0 then
				bag = table.clone(BEAT_BAG)
				shuffle(bag, rng)
			end
			beat = table.remove(bag) :: BeatKind
		end

		if beat == "Wall" then
			local height = rng:NextInteger(24, 32)
			if rng:NextNumber() < 0.38 then
				-- Три панели разной прочности: игрок выбирает, куда бить
				local center = strengthFor(progress)
				local order = { math.max(center - 1, 1), center, math.min(center + 1, #strengths) }
				shuffle(order, rng)
				local panelWidth = (width - 2) / 3
				for i, strengthIndex in order do
					addWall(strengthIndex, -halfWidth + 1 + panelWidth * (i - 0.5), cursor, panelWidth - 0.4, height)
				end
			else
				addWall(strengthFor(progress), 0, cursor, width - 2, height)
			end
		elseif beat == "Chests" then
			for _ = 1, rng:NextInteger(2, 4) do
				for _ = 1, 10 do
					local x = rng:NextNumber(-halfWidth + 10, halfWidth - 10)
					local yaw = math.rad(rng:NextNumber(-25, 25))
					if addChest(x, chestSize.Y * 0.5, cursor + rng:NextNumber(-12, 12), yaw) then
						break
					end
				end
			end
		elseif beat == "Bumpers" then
			local placed: { Vector3 } = {}
			for _ = 1, rng:NextInteger(3, 6) do
				for _ = 1, 8 do
					local x = rng:NextNumber(-halfWidth + 9, halfWidth - 9)
					local bz = cursor + rng:NextNumber(-16, 16)
					local candidate = Vector3.new(x, 0, bz)
					local free = true
					for _, other in placed do
						if (other - candidate).Magnitude < 13 then
							free = false
							break
						end
					end
					if free and not claim(CFrame.new(x, 12, bz), Vector3.new(12, 30, 12), 0.5) then
						free = false
					end
					if free then
						table.insert(placed, candidate)
						if rng:NextNumber() < 0.6 then
							local height = rng:NextInteger(9, 15)
							local diameter = rng:NextInteger(6, 9)
							addPiece(
								"Bumper",
								CFrame.new(x, height * 0.5, bz) * CFrame.Angles(0, 0, math.rad(90)),
								Vector3.new(height, diameter, diameter),
								CYLINDER
							)
						else
							local diameter = rng:NextInteger(7, 11)
							addPiece("BumperBall", CFrame.new(x, rng:NextInteger(9, 26), bz), Vector3.new(diameter, diameter, diameter), BALL)
						end
						break
					end
				end
			end
		elseif beat == "Anchors" then
			local height = rng:NextInteger(34, 48)
			addPost(-halfWidth + 6, cursor, height)
			addPost(halfWidth - 6, cursor, height)
			if rng:NextNumber() < 0.55 then
				addArch(cursor, height + 2)
			end
		else -- Island
			local x = rng:NextNumber(-halfWidth + 16, halfWidth - 16)
			local y = rng:NextInteger(18, 30)
			addPiece("Island", CFrame.new(x, y, cursor), Vector3.new(24, 4, 24), BLOCK)
			addChest(x + rng:NextNumber(-5, 5), y + 2 + chestSize.Y * 0.5, cursor + rng:NextNumber(-5, 5), math.rad(rng:NextNumber(-30, 30)))
			addPiece("Ring", CFrame.new(x, y + 16, cursor), Vector3.new(4.6, 4.6, 4.6), BALL)
		end
		cursor -= rng:NextInteger(58, 86)
	end

	-- 4) Кольца ускорения в воздухе (не внутри стен и прочих препятствий)
	local ringConfig = LevelConfig.BoostRing
	local ringZ = -160 - rng:NextNumber(0, 30)
	local ringIndex = 0
	while ringZ > runwayEnd + 110 do
		for _ = 1, 8 do
			local cframe = CFrame.new(rng:NextNumber(-halfWidth + 18, halfWidth - 18), rng:NextNumber(18, 34), ringZ)
			if claim(cframe, Vector3.new(ringConfig.Radius * 2 + 2, ringConfig.Radius * 2 + 2, 4), 1) then
				ringIndex += 1
				local id = string.format("R%d-%d", tier, ringIndex)
				table.insert(rings, { Id = id, LocalCFrame = cframe, Radius = ringConfig.Radius })
				table.insert(pieces, {
					Kind = "BoostRing",
					LocalCFrame = cframe,
					Size = Vector3.new(0.6, ringConfig.Radius * 2, ringConfig.Radius * 2),
					Shape = CYLINDER,
					Seed = ringIndex,
					Scale = ringConfig.Radius,
				})
				break
			end
			ringZ -= 6
		end
		ringZ -= ringConfig.Spacing + rng:NextNumber(-20, 20)
	end

	-- 5) Золотые пиньяты: плывут поперёк полосы, коридор движения резервируется целиком
	local pinataConfig = LevelConfig.Pinata
	local pinataCount = math.min(1 + tier // 2, 3)
	for index = 1, pinataCount do
		local fraction = (index - 0.5) / pinataCount
		for _ = 1, 10 do
			local pz = -(length * (0.32 + 0.52 * fraction)) + rng:NextNumber(-20, 20)
			local amplitude = math.min(rng:NextNumber(pinataConfig.AmplitudeMin, pinataConfig.AmplitudeMax), halfWidth - pinataConfig.Size.X)
			local motion: PinataMotion.MotionSpec = {
				Amplitude = amplitude,
				Frequency = rng:NextNumber(pinataConfig.FrequencyMin, pinataConfig.FrequencyMax),
				Phase = rng:NextNumber(0, math.pi * 2),
			}
			local cframe = CFrame.new(0, rng:NextNumber(14, 24), pz)
			if pz > runwayEnd + 60 and claim(cframe, PinataMotion.SweepSize(pinataConfig.Size, motion), 1) then
				obstacleIndex += 1
				table.insert(obstacles, {
					Id = string.format("T%d-%d", tier, obstacleIndex),
					Kind = "Pinata",
					Strength = "Pinata",
					LocalCFrame = cframe,
					Size = pinataConfig.Size,
					RequiredSpeed = pinataConfig.RequiredSpeed * math.sqrt(durabilityMultiplier),
					Durability = StretchPhysics.DurabilityFromSpeed(pinataConfig.RequiredSpeed, durabilityMultiplier),
					Loot = math.floor(pinataConfig.Loot * lootMultiplier + 0.5),
					Motion = motion,
				})
				break
			end
		end
	end

	-- 6) Окружение вдоль трассы: парящие островки с деревьями, облака, декоративные кольца.
	--    Начинаем дальше от старта, где веер полос уже разошёлся и соседям не тесно.
	local decorZ = -360 - rng:NextNumber(0, 40)
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	while decorZ > -length + 20 do
		addDecor(
			"DecorIsland",
			CFrame.new(side * (halfWidth + 36 + rng:NextNumber(0, 14)), rng:NextNumber(-24, 16), decorZ) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			rng:NextNumber(0.8, 1.25)
		)
		if rng:NextNumber() < 0.35 then
			addDecor("DecorRing", CFrame.new(-side * (halfWidth + 30), rng:NextNumber(40, 62), decorZ - 40) * CFrame.Angles(0, math.pi / 2, 0), rng:NextNumber(7, 10))
		end
		side = -side
		decorZ -= rng:NextNumber(110, 160)
	end
	local cloudZ = -120 - rng:NextNumber(0, 60)
	while cloudZ > -length - 80 do
		local cloudSide = if rng:NextNumber() < 0.5 then -1 else 1
		addDecor("Cloud", CFrame.new(cloudSide * rng:NextNumber(halfWidth + 40, halfWidth + 130), rng:NextNumber(60, 130), cloudZ), rng:NextNumber(0.8, 1.6))
		if rng:NextNumber() < 0.4 then
			addDecor("Cloud", CFrame.new(-cloudSide * rng:NextNumber(halfWidth + 30, halfWidth + 90), rng:NextNumber(-80, -50), cloudZ - 60), rng:NextNumber(1, 1.8))
		end
		cloudZ -= rng:NextNumber(150, 230)
	end

	-- 7) Гонг Эволюции (диск смотрит на старт: ось цилиндра вдоль Z)
	local gongZ = -length
	addPiece("GongBase", CFrame.new(0, -3, gongZ + 10), Vector3.new(76, 6, 60), BLOCK)
	addPiece("Foundation", CFrame.new(0, -13, gongZ + 10), Vector3.new(80, 14, 64), BLOCK)
	addPiece("FoundationDeep", CFrame.new(0, -27, gongZ + 10), Vector3.new(56, 14, 44), BLOCK)
	addPiece("GongFrame", CFrame.new(-21, 24, gongZ - 8), Vector3.new(4, 48, 4), BLOCK)
	addPiece("GongFrame", CFrame.new(21, 24, gongZ - 8), Vector3.new(4, 48, 4), BLOCK)
	addPiece("GongFrame", CFrame.new(0, 49, gongZ - 8), Vector3.new(46, 4, 4), BLOCK)
	local gongCFrame = CFrame.new(0, 24, gongZ - 8) * CFrame.Angles(0, math.rad(90), 0)
	addPiece("GongDisc", gongCFrame, Vector3.new(2.6, 34, 34), CYLINDER)
	addPiece("GongSign", CFrame.new(0, 58, gongZ - 8), Vector3.new(46, 10, 1), BLOCK)

	return {
		LocationId = locationId,
		Tier = tier,
		Seed = seed,
		Length = length,
		Pieces = pieces,
		Obstacles = obstacles,
		Rings = rings,
		Gaps = gaps,
		GongLocalCFrame = gongCFrame,
	}
end

-- ── Построение деталей ─────────────────────────────────────────────────────

local function makePart(name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, look: LevelConfig.MaterialColor): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape -- форму ставим до размера: Ball принудительно делает размер равным
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Material = look.Material
	part.Color = look.Color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function makeDecor(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	look: LevelConfig.MaterialColor,
	parent: Instance
): Part
	local part = makePart(name, shape, size, cframe, look)
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function neon(color: Color3): LevelConfig.MaterialColor
	return { Color = color, Material = NEON }
end

local function lookFor(kind: string, theme: LevelConfig.Theme, strength: string?): LevelConfig.MaterialColor
	if kind == "Floor" or kind == "GongBase" or kind == "StartPad" then
		return theme.Floor
	elseif kind == "Stripe" then
		return theme.Stripe
	elseif kind == "Rail" then
		return theme.Rail
	elseif kind == "Post" or kind == "Arch" or kind == "GatePillar" then
		return theme.Post
	elseif kind == "Ring" then
		return theme.Ring
	elseif kind == "Bumper" or kind == "BumperBall" then
		return theme.Bumper
	elseif kind == "Island" then
		return theme.Island
	elseif kind == "GongFrame" or kind == "GongSign" or kind == "StartSign" or kind == "GateArch" or kind == "GateSign" then
		return theme.GongFrame
	elseif kind == "GongDisc" then
		return theme.Gong
	elseif kind == "Chest" then
		return theme.ChestBody
	elseif kind == "Wall" then
		return theme.Walls[strength or "Soft"] or theme.Walls.Soft
	elseif kind == "Foundation" then
		return theme.Rock
	elseif kind == "FoundationDeep" or kind == "RockSpike" then
		return theme.RockDark
	elseif kind == "Girder" then
		return theme.Girder
	elseif kind == "Chevron" then
		return theme.Chevron
	elseif kind == "BridgeDeck" or kind == "BridgeRail" or kind == "BridgePost" then
		return theme.Bridge
	elseif kind == "BridgePlank" then
		return { Color = theme.Bridge.Color:Lerp(Color3.new(0, 0, 0), 0.35), Material = theme.Bridge.Material }
	elseif kind == "GateNeon" or kind == "BoostRing" then
		return neon(theme.GateNeon)
	end
	return theme.Floor
end

local function attachSign(part: BasePart, text: string, theme: LevelConfig.Theme, face: Enum.NormalId, neonStyle: boolean)
	local existing = part:FindFirstChild("SignGui")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0
	gui.Brightness = if neonStyle then 2.2 else 1.4

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = if neonStyle then theme.GateNeon:Lerp(Color3.new(1, 1, 1), 0.55) else theme.SignText
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = if neonStyle then 4 else 5
	stroke.Color = if neonStyle then theme.GateNeon else theme.SignStroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	gui.Parent = part
end

function LevelBuilder.GongSignText(tier: number): string
	local speed, combo = LevelConfig.GongRequirement(tier)
	return string.format(
		"ГОНГ ЭВОЛЮЦИИ  ·  %s → %s\nСКОРОСТЬ ≥ %d   ·   КОМБО ≥ %d",
		LevelConfig.TierName(tier),
		LevelConfig.TierName(tier + 1),
		math.floor(speed),
		combo
	)
end

function LevelBuilder.GateSignText(ownerName: string, tier: number, bestSpeed: number): string
	return string.format("%s  •  %s  •  РЕКОРД %d st/s", ownerName, LevelConfig.TierName(tier), math.floor(bestSpeed + 0.5))
end

local START_SIGN_TEXT = "ЛКМ / ПКМ — выстрелить левой / правой рукой\n"
	.. "Держи на земле — натянуть рогатку, отпусти — ПОЛЁТ\n"
	.. "Держи в воздухе — резинка тянет к точке\n"
	.. "ПРОБЕЛ в полёте — пружинный шар • кольца = BOOST\n"
	.. "Бей стены, сундуки и пиньяты • TAB / ALT — меню"

local function buildToy(toy: ToyModels.Toy, cframe: CFrame, parent: Instance, localZ: number): BasePart
	ToyModels.Place(toy, cframe)
	toy.Model:SetAttribute("LocalZ", localZ)
	toy.Model.Parent = parent
	local primary = toy.Model.PrimaryPart
	if primary == nil then
		error("ToyModels вернул модель без PrimaryPart")
	end
	return primary
end

function LevelBuilder.BuildPiece(spec: PieceSpec, context: BuildContext, parent: Instance): BasePart
	local kind = spec.Kind
	local theme = context.Theme
	local world = context.Origin * spec.LocalCFrame
	local localZ = spec.LocalCFrame.Position.Z

	-- Составной декор окружения — модельки ToyModels (без коллизий)
	if kind == "DecorIsland" or kind == "Cloud" or kind == "DecorRing" then
		local rng = Random.new(spec.Seed or 1)
		local scale = spec.Scale or 1
		if kind == "Cloud" then
			return buildToy(ToyModels.Cloud(scale, theme.Cloud.Color, rng), world, parent, localZ)
		elseif kind == "DecorRing" then
			return buildToy(ToyModels.Ring(scale, theme.GateNeon, 16), world, parent, localZ)
		end
		local island = ToyModels.Island(9 * scale, theme.Floor.Color, theme.Rock.Color, theme.RockDark.Color)
		for index = 1, rng:NextInteger(1, 3) do
			local tree = ToyModels.Tree(0.7 * scale, theme.Trunk.Color, theme.Trunk.Material, theme.Leaves.Color, theme.Leaves.Material, rng)
			local angle = index * 2.1 + rng:NextNumber()
			ToyModels.Attach(island, tree, CFrame.new(math.cos(angle) * 4 * scale, 0, math.sin(angle) * 4 * scale))
		end
		return buildToy(island, world, parent, localZ)
	end

	local part = makePart(kind, spec.Shape, spec.Size, world, lookFor(kind, theme, nil))
	part:SetAttribute("PieceKind", kind)
	part:SetAttribute("LocalZ", localZ)
	if kind == "Stripe" or kind == "Chevron" then
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
	elseif kind == "Foundation" or kind == "FoundationDeep" or kind == "RockSpike" or kind == "Girder" then
		-- основание под полом — визуальная масса, не мешает запросам и физике
		part.CanCollide = false
		part.CanQuery = false
	elseif kind == "Rail" or kind == "Bumper" or kind == "BumperBall" then
		part:AddTag(Tags.Bouncy)
	elseif kind == "Ring" then
		part:AddTag(Tags.GrabPoint)
		part.CastShadow = false
	elseif kind == "Arch" then
		part:AddTag(Tags.GrabPoint)
	elseif kind == "BoostRing" then
		-- невидимый «диск-триггер» + светящийся обод из сегментов; пролёт считают клиент и сервер геометрически
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.CFrame = world * CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра (X) вдоль оси полосы
		part:AddTag(Tags.BoostRing)
		part:SetAttribute("RingId", string.format("R%d-%d", context.Tier, spec.Seed or 0))
		part:SetAttribute("Radius", spec.Scale or LevelConfig.BoostRing.Radius)
		part:SetAttribute("OwnerUserId", context.OwnerUserId)
		local radius = spec.Scale or LevelConfig.BoostRing.Radius
		local ring = ToyModels.Ring(radius, theme.GateNeon, 18)
		ToyModels.Place(ring, world)
		for _, segment in ring.Model:GetChildren() do
			segment.Parent = part
		end
		ring.Model:Destroy()
		makeDecor("Glow", CYLINDER, Vector3.new(0.3, radius * 2 - 1, radius * 2 - 1), world * CFrame.Angles(0, math.rad(90), 0), neon(theme.GateNeon), part).Transparency = 0.82
	elseif kind == "GongDisc" then
		part:AddTag(Tags.Gong)
		part:SetAttribute("GongLaneSlot", context.Slot)
		part:SetAttribute("OwnerUserId", context.OwnerUserId)
		-- Локальная −X диска смотрит на старт: туда кладём светящееся «яблочко»
		makeDecor("Bullseye", CYLINDER, Vector3.new(0.6, 22, 22), part.CFrame * CFrame.new(-1.4, 0, 0), theme.Ring, part)
	elseif kind == "GongSign" then
		part.CanQuery = false
		attachSign(part, LevelBuilder.GongSignText(context.Tier), theme, Enum.NormalId.Back, false)
	end
	part.Parent = parent
	return part
end

local function buildPinataDecor(part: BasePart, theme: LevelConfig.Theme)
	local cframe = part.CFrame
	local radius = part.Size.X * 0.5
	local gold: LevelConfig.MaterialColor = { Color = Color3.fromRGB(255, 206, 50), Material = Enum.Material.Foil }
	-- пять лучей звезды в плоскости, обращённой к старту
	for index = 1, 5 do
		local angle = index / 5 * math.pi * 2
		local direction = Vector3.new(math.sin(angle), math.cos(angle), 0)
		local tipCFrame = cframe * ToyModels.AxisFrame(direction * (radius + 1.2), direction)
		makeDecor("Point", Enum.PartType.Wedge, Vector3.new(3, 1.2, 2.2), tipCFrame, gold, part)
	end
	-- бумажные «оборки»: три неоновых пояса
	for index, color in { Color3.fromRGB(255, 90, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(150, 255, 90) } do
		makeDecor("Frill", CYLINDER, Vector3.new(0.5, radius * 2 + 0.5, radius * 2 + 0.5), cframe * CFrame.new(0, (index - 2) * 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), neon(color), part)
	end
	-- мордочка
	for _, side in { -1, 1 } do
		makeDecor("Eye", BALL, Vector3.one * 1.1, cframe * CFrame.new(side * 0.9, 0.6, radius - 0.2), { Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic }, part)
		makeDecor("Pupil", BALL, Vector3.one * 0.55, cframe * CFrame.new(side * 0.9, 0.55, radius + 0.25), { Color = Color3.fromRGB(28, 32, 56), Material = Enum.Material.SmoothPlastic }, part)
	end
	makeDecor("Glow", BALL, Vector3.one * (radius * 2 + 2.4), cframe, { Color = theme.GateNeon, Material = Enum.Material.ForceField }, part).Transparency = 0.3
end

function LevelBuilder.BuildObstacle(spec: ObstacleSpec, context: BuildContext, parent: Instance): BasePart
	local look = if spec.Kind == "Pinata" then { Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Foil } else lookFor(spec.Kind, context.Theme, spec.Strength)
	local shape = if spec.Kind == "Pinata" then BALL else BLOCK
	local part = makePart(spec.Kind, shape, spec.Size, context.Origin * spec.LocalCFrame, look)
	part:AddTag(Tags.Smashable)
	part:SetAttribute("ObstacleId", spec.Id)
	part:SetAttribute("ObstacleKind", spec.Kind)
	part:SetAttribute("Strength", spec.Strength)
	part:SetAttribute("Durability", spec.Durability)
	part:SetAttribute("RequiredSpeed", spec.RequiredSpeed)
	part:SetAttribute("Loot", spec.Loot)
	part:SetAttribute("LaneSlot", context.Slot)
	part:SetAttribute("OwnerUserId", context.OwnerUserId)
	part:SetAttribute("LocalZ", spec.LocalCFrame.Position.Z)

	if spec.Kind == "Chest" then
		local size = spec.Size
		local trim = context.Theme.ChestTrim
		makeDecor("Lid", BLOCK, Vector3.new(size.X + 0.4, 1.4, size.Z + 0.4), part.CFrame * CFrame.new(0, size.Y * 0.5 + 0.7, 0), look, part)
		for _, x in { -size.X * 0.32, size.X * 0.32 } do
			makeDecor("Band", BLOCK, Vector3.new(0.7, size.Y + 1.6, size.Z + 0.25), part.CFrame * CFrame.new(x, 0.7, 0), trim, part)
		end
		makeDecor("Lock", BLOCK, Vector3.new(1.4, 1.6, 0.6), part.CFrame * CFrame.new(0, size.Y * 0.2, -size.Z * 0.5 - 0.3), trim, part)
		makeDecor("Lock", BLOCK, Vector3.new(1.4, 1.6, 0.6), part.CFrame * CFrame.new(0, size.Y * 0.2, size.Z * 0.5 + 0.3), trim, part)
	elseif spec.Kind == "Pinata" then
		local motion = spec.Motion
		if motion then
			part:AddTag(Tags.Pinata)
			part:SetAttribute("BaseCFrame", part.CFrame)
			part:SetAttribute("Amplitude", motion.Amplitude)
			part:SetAttribute("Frequency", motion.Frequency)
			part:SetAttribute("Phase", motion.Phase)
		end
		buildPinataDecor(part, context.Theme)
	end

	part.Parent = parent
	return part
end

local function buildGate(context: BuildContext, static: Folder): BasePart
	local origin = context.Origin
	local theme = context.Theme
	local halfWidth = LevelConfig.LaneWidth / 2
	local gateZ = -30
	for _, side in { -1, 1 } do
		local pillar = makeDecor("GatePillar", CYLINDER, Vector3.new(40, 4.6, 4.6), origin * CFrame.new(side * (halfWidth + 5), 20, gateZ) * CFrame.Angles(0, 0, math.pi / 2), lookFor("GatePillar", theme, nil), static)
		pillar:SetAttribute("PieceKind", "GatePillar")
		local cap = makeDecor("GateNeon", BALL, Vector3.one * 5.6, origin * CFrame.new(side * (halfWidth + 5), 41.5, gateZ), lookFor("GateNeon", theme, nil), static)
		cap:SetAttribute("PieceKind", "GateNeon")
	end
	local arch = makeDecor("GateArch", BLOCK, Vector3.new(LevelConfig.LaneWidth + 16, 5, 5), origin * CFrame.new(0, 43, gateZ), lookFor("GateArch", theme, nil), static)
	arch:SetAttribute("PieceKind", "GateArch")
	for _, y in { 40.2, 45.8 } do
		local strip = makeDecor("GateNeon", BLOCK, Vector3.new(LevelConfig.LaneWidth + 12, 0.7, 5.4), origin * CFrame.new(0, y, gateZ), lookFor("GateNeon", theme, nil), static)
		strip:SetAttribute("PieceKind", "GateNeon")
	end
	local sign = makeDecor("GateSign", BLOCK, Vector3.new(LevelConfig.LaneWidth - 18, 8, 0.8), origin * CFrame.new(0, 34.5, gateZ), lookFor("GateSign", theme, nil), static)
	sign:SetAttribute("PieceKind", "GateSign")
	attachSign(sign, LevelBuilder.GateSignText(context.OwnerName, context.Tier, context.BestSpeed), theme, Enum.NormalId.Back, true)
	return sign
end

-- Мост от стартовой площадки к краю хаба (локальная +Z полосы смотрит на хаб)
local function buildBridge(context: BuildContext, static: Folder)
	local origin = context.Origin
	local theme = context.Theme
	local hub = LevelConfig.Hub
	local startZ = LevelConfig.StartPadSize.Z * 0.5 - 1
	local endZ = hub.LaneStartRadius - hub.Radius + 4
	local length = endZ - startZ
	local centerZ = (startZ + endZ) * 0.5
	local deck = makePart("BridgeDeck", BLOCK, Vector3.new(16, 2, length), origin * CFrame.new(0, -1, centerZ), lookFor("BridgeDeck", theme, nil))
	deck:SetAttribute("PieceKind", "BridgeDeck")
	deck.Parent = static
	local plankZ = startZ + 4
	while plankZ < endZ - 2 do
		local plank = makeDecor("BridgePlank", BLOCK, Vector3.new(16.4, 0.3, 0.6), origin * CFrame.new(0, 0.05, plankZ), lookFor("BridgePlank", theme, nil), static)
		plank:SetAttribute("PieceKind", "BridgePlank")
		plankZ += 6
	end
	for _, side in { -1, 1 } do
		local postZ = startZ + 2
		while postZ <= endZ do
			local post = makeDecor("BridgePost", CYLINDER, Vector3.new(5, 0.9, 0.9), origin * CFrame.new(side * 8, 2.5, postZ) * CFrame.Angles(0, 0, math.pi / 2), lookFor("BridgePost", theme, nil), static)
			post:SetAttribute("PieceKind", "BridgePost")
			postZ += 12
		end
		local rope = makePart("BridgeRail", CYLINDER, Vector3.new(length, 0.7, 0.7), origin * CFrame.new(side * 8, 4.6, centerZ) * CFrame.Angles(0, math.rad(90), 0), lookFor("BridgeRail", theme, nil))
		rope:SetAttribute("PieceKind", "BridgeRail")
		rope:AddTag(Tags.GrabPoint)
		rope.Parent = static
	end
end

function LevelBuilder.CreateLane(layout: LaneLayout, context: BuildContext, parent: Instance): LaneHandles
	local model = Instance.new("Model")
	model.Name = "Lane_" .. context.Slot
	model:SetAttribute("LaneSlot", context.Slot)
	model:SetAttribute("OwnerUserId", context.OwnerUserId)
	model:SetAttribute("Tier", layout.Tier)

	local static = Instance.new("Folder")
	static.Name = "Static"
	static.Parent = model
	local mutable = Instance.new("Folder")
	mutable.Name = "Mutable"
	mutable.Parent = model
	local obstacleFolder = Instance.new("Folder")
	obstacleFolder.Name = "Obstacles"
	obstacleFolder.Parent = model

	local padSize = LevelConfig.StartPadSize
	local startPad = makePart("StartPad", BLOCK, padSize, context.Origin * CFrame.new(0, -padSize.Y * 0.5, 0), context.Theme.Floor)
	startPad:SetAttribute("PieceKind", "StartPad")
	startPad.Parent = static
	local padRock = makeDecor("Foundation", BLOCK, padSize + Vector3.new(4, 10, 4), context.Origin * CFrame.new(0, -padSize.Y - 5, 0), context.Theme.Rock, static)
	padRock:SetAttribute("PieceKind", "Foundation")

	local startSign = makePart(
		"StartSign",
		BLOCK,
		Vector3.new(26, 14, 1),
		context.Origin * CFrame.new(-24, 11, -14) * CFrame.Angles(0, math.rad(40), 0),
		context.Theme.GongFrame
	)
	startSign:SetAttribute("PieceKind", "StartSign")
	startSign.CanQuery = false
	attachSign(startSign, START_SIGN_TEXT, context.Theme, Enum.NormalId.Back, false)
	startSign.Parent = static

	local gateSign = buildGate(context, static)
	buildBridge(context, static)

	local gong: BasePart? = nil
	for _, spec in layout.Pieces do
		local part = LevelBuilder.BuildPiece(spec, context, mutable)
		if spec.Kind == "GongDisc" then
			gong = part
		end
	end

	local obstacles: { [string]: BasePart } = {}
	for _, spec in layout.Obstacles do
		obstacles[spec.Id] = LevelBuilder.BuildObstacle(spec, context, obstacleFolder)
	end

	model.Parent = parent
	return {
		Model = model,
		Static = static,
		Mutable = mutable,
		ObstacleFolder = obstacleFolder,
		StartPad = startPad,
		StartSign = startSign,
		GateSign = gateSign,
		Gong = gong,
		Obstacles = obstacles,
	}
end

-- Перекраска статичных деталей (старт, ворота, мост) под новый тир.
function LevelBuilder.ApplyTheme(part: BasePart, theme: LevelConfig.Theme)
	local kind = part:GetAttribute("PieceKind")
	if typeof(kind) ~= "string" then
		return
	end
	local look = lookFor(kind, theme, nil)
	part.Color = look.Color
	part.Material = look.Material
	if kind == "StartSign" then
		attachSign(part, START_SIGN_TEXT, theme, Enum.NormalId.Back, false)
	end
end

-- Пересоздать вывеску в стиле нового тира (после волны перерождения)
function LevelBuilder.RefreshGateSign(sign: BasePart, text: string, theme: LevelConfig.Theme)
	attachSign(sign, text, theme, Enum.NormalId.Back, true)
end

function LevelBuilder.UpdateGateSign(sign: BasePart, text: string)
	local gui = sign:FindFirstChild("SignGui")
	local label = if gui then gui:FindFirstChild("Text") else nil
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
	end
end

function LevelBuilder.StartCFrame(slot: number): CFrame
	local origin = LevelConfig.SlotOrigin(slot)
	local position = origin:PointToWorldSpace(LevelConfig.SpawnOffset)
	return CFrame.lookAt(position, position + origin.LookVector)
end

function LevelBuilder.HubSpawnCFrame(slot: number): CFrame
	return LevelConfig.HubSpawn(slot)
end

return LevelBuilder
