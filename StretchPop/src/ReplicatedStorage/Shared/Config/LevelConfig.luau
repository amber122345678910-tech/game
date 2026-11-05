--!strict
-- STRETCH-POP · Конфиг полос, тиров перерождения и визуальных тем.

export type MaterialColor = {
	Color: Color3,
	Material: Enum.Material,
}

export type Theme = {
	Name: string,
	Floor: MaterialColor,
	Stripe: MaterialColor,
	Rail: MaterialColor,
	Post: MaterialColor,
	Ring: MaterialColor,
	Bumper: MaterialColor,
	Island: MaterialColor,
	ChestBody: MaterialColor,
	ChestTrim: MaterialColor,
	Gong: MaterialColor,
	GongFrame: MaterialColor,
	Walls: { [string]: MaterialColor },
	Wave: Color3,
	Tint: Color3,
	SignText: Color3,
	SignStroke: Color3,
}

export type WallStrength = {
	Name: string,
	RequiredSpeed: number, -- скорость пробития при базовой ударной массе (m = 1) на тире 0
	Loot: number,
	Thickness: number,
}

export type TierCurve = {
	Base: number,
	PerTier: number,
	Max: number,
}

local function mc(r: number, g: number, b: number, material: Enum.Material): MaterialColor
	return { Color = Color3.fromRGB(r, g, b), Material = material }
end

local SP = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local FOIL = Enum.Material.Foil
local GLASS = Enum.Material.Glass
local WOOD = Enum.Material.WoodPlanks
local METAL = Enum.Material.Metal
local SLATE = Enum.Material.Slate

local Themes: { Theme } = {
	{
		Name = "Classic",
		Floor = mc(122, 214, 96, SP),
		Stripe = mc(255, 255, 255, SP),
		Rail = mc(255, 120, 180, SP),
		Post = mc(245, 246, 255, SP),
		Ring = mc(80, 220, 255, NEON),
		Bumper = mc(255, 160, 60, SP),
		Island = mc(255, 236, 170, SP),
		ChestBody = mc(176, 108, 58, WOOD),
		ChestTrim = mc(255, 206, 64, SP),
		Gong = mc(232, 160, 64, METAL),
		GongFrame = mc(122, 72, 44, WOOD),
		Walls = {
			Soft = mc(255, 214, 120, WOOD),
			Medium = mc(236, 120, 92, SP),
			Hard = mc(150, 160, 180, METAL),
			Titan = mc(132, 98, 255, SP),
		},
		Wave = Color3.fromRGB(255, 255, 255),
		Tint = Color3.fromRGB(255, 255, 255),
		SignText = Color3.fromRGB(255, 255, 255),
		SignStroke = Color3.fromRGB(40, 60, 120),
	},
	{
		Name = "Golden",
		Floor = mc(255, 222, 128, SP),
		Stripe = mc(255, 180, 60, SP),
		Rail = mc(255, 196, 40, FOIL),
		Post = mc(255, 242, 206, SP),
		Ring = mc(255, 228, 90, NEON),
		Bumper = mc(255, 150, 40, FOIL),
		Island = mc(255, 246, 214, SP),
		ChestBody = mc(255, 194, 40, FOIL),
		ChestTrim = mc(255, 255, 214, NEON),
		Gong = mc(255, 214, 70, FOIL),
		GongFrame = mc(180, 120, 30, FOIL),
		Walls = {
			Soft = mc(255, 232, 156, SP),
			Medium = mc(255, 204, 86, FOIL),
			Hard = mc(222, 166, 40, FOIL),
			Titan = mc(255, 246, 190, NEON),
		},
		Wave = Color3.fromRGB(255, 220, 80),
		Tint = Color3.fromRGB(255, 244, 222),
		SignText = Color3.fromRGB(255, 248, 220),
		SignStroke = Color3.fromRGB(140, 86, 10),
	},
	{
		Name = "Cyber-Slime",
		Floor = mc(30, 34, 50, SP),
		Stripe = mc(60, 255, 160, NEON),
		Rail = mc(90, 255, 190, GLASS),
		Post = mc(44, 48, 66, SP),
		Ring = mc(60, 255, 140, NEON),
		Bumper = mc(180, 255, 60, GLASS),
		Island = mc(52, 60, 84, SP),
		ChestBody = mc(40, 200, 140, GLASS),
		ChestTrim = mc(60, 255, 200, NEON),
		Gong = mc(60, 255, 170, GLASS),
		GongFrame = mc(24, 26, 38, METAL),
		Walls = {
			Soft = mc(140, 255, 120, GLASS),
			Medium = mc(60, 220, 160, GLASS),
			Hard = mc(36, 150, 132, SP),
			Titan = mc(220, 255, 60, NEON),
		},
		Wave = Color3.fromRGB(60, 255, 160),
		Tint = Color3.fromRGB(224, 255, 240),
		SignText = Color3.fromRGB(200, 255, 220),
		SignStroke = Color3.fromRGB(10, 90, 60),
	},
	{
		Name = "Void",
		Floor = mc(26, 18, 44, SP),
		Stripe = mc(170, 60, 255, NEON),
		Rail = mc(118, 46, 200, GLASS),
		Post = mc(40, 26, 62, SP),
		Ring = mc(214, 92, 255, NEON),
		Bumper = mc(255, 64, 200, GLASS),
		Island = mc(48, 32, 76, SLATE),
		ChestBody = mc(62, 30, 94, SLATE),
		ChestTrim = mc(222, 112, 255, NEON),
		Gong = mc(140, 60, 255, GLASS),
		GongFrame = mc(18, 10, 30, METAL),
		Walls = {
			Soft = mc(96, 64, 156, SP),
			Medium = mc(72, 42, 124, SLATE),
			Hard = mc(50, 30, 92, SLATE),
			Titan = mc(255, 80, 220, NEON),
		},
		Wave = Color3.fromRGB(200, 80, 255),
		Tint = Color3.fromRGB(236, 224, 255),
		SignText = Color3.fromRGB(240, 210, 255),
		SignStroke = Color3.fromRGB(60, 10, 90),
	},
}

local LevelConfig = {
	DefaultLocation = "Meadows",
	Locations = {
		Meadows = { DisplayName = "Bouncy Meadows", Seed = 7341 },
	} :: { [string]: { DisplayName: string, Seed: number } },

	-- Геометрия полосы (локальные координаты: старт в (0,0,0), полоса уходит в −Z)
	LaneWidth = 92,
	SlotSpacing = 210,
	MaxSlots = 16,
	WorldOrigin = Vector3.new(0, 0, 0),
	StartPadSize = Vector3.new(72, 6, 72),
	BaseLength = 760,
	LengthPerTier = 110,
	MaxLength = 1300,
	SpawnOffset = Vector3.new(0, 5, 14),

	WallStrengths = {
		{ Name = "Soft", RequiredSpeed = 60, Loot = 3, Thickness = 3 },
		{ Name = "Medium", RequiredSpeed = 100, Loot = 6, Thickness = 4 },
		{ Name = "Hard", RequiredSpeed = 140, Loot = 12, Thickness = 5 },
		{ Name = "Titan", RequiredSpeed = 185, Loot = 25, Thickness = 6 },
	} :: { WallStrength },
	Chest = {
		RequiredSpeed = 45,
		Loot = 40,
		Size = Vector3.new(7, 5.5, 5),
	},

	-- Рост сложности/лута с каждым перерождением
	DurabilityGrowth = 1.3, -- прочность ×1.3 за тир (нужная скорость ×√1.3 ≈ ×1.14)
	LootGrowth = 2, -- лут ×2 за тир
	GongSpeed = { Base = 140, PerTier = 22, Max = 420 } :: TierCurve,
	GongCombo = { Base = 2, PerTier = 1, Max = 12 } :: TierCurve,
	RebirthBonus = 120,
	ObstacleRespawnTime = 10,

	Rebirth = {
		StartDelay = 1.1, -- пауза между ударом в Гонг и стартом волны
		TeleportDelay = 0.7, -- игрок переносится на старт, чтобы смотреть, как волна идёт на него
		WaveSpeed = 420,
		Cooldown = 6,
	},

	Themes = Themes,
}

function LevelConfig.GetTheme(tier: number): Theme
	local index = math.clamp(math.floor(tier) + 1, 1, #Themes)
	return Themes[index]
end

function LevelConfig.DurabilityMultiplier(tier: number): number
	return LevelConfig.DurabilityGrowth ^ math.max(tier, 0)
end

function LevelConfig.LootMultiplier(tier: number): number
	return LevelConfig.LootGrowth ^ math.max(tier, 0)
end

local function tierCurve(curve: TierCurve, tier: number): number
	return math.min(curve.Base + curve.PerTier * math.max(tier, 0), curve.Max)
end

-- Порог удара в Гонг: (минимальная скорость, минимальное комбо)
function LevelConfig.GongRequirement(tier: number): (number, number)
	return tierCurve(LevelConfig.GongSpeed, tier), math.floor(tierCurve(LevelConfig.GongCombo, tier))
end

function LevelConfig.LaneLength(tier: number): number
	return math.min(LevelConfig.BaseLength + LevelConfig.LengthPerTier * math.max(tier, 0), LevelConfig.MaxLength)
end

function LevelConfig.SlotOrigin(slot: number): CFrame
	return CFrame.new(LevelConfig.WorldOrigin + Vector3.new((slot - 1) * LevelConfig.SlotSpacing, 0, 0))
end

function LevelConfig.TierName(tier: number): string
	local theme = LevelConfig.GetTheme(tier)
	if tier >= #Themes then
		return string.format("%s +%d", theme.Name, tier - #Themes + 1)
	end
	return theme.Name
end

return LevelConfig
