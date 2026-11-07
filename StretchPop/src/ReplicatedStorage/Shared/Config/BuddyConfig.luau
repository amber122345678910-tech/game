--!strict
-- STRETCH-POP · Пружинные компаньоны (Bouncy Buddies) и гача-капсулы.
-- Один источник правды для сервера (ролл, крафт, бонусы к луту/физике) и клиента (витрина, шансы,
-- 3D-модельки). Бонусы бадди входят в StretchPhysics.Derive, поэтому предсказание клиента и
-- валидация сервера считают одну и ту же ударную массу и жёсткость.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type Mutation = "Normal" | "Golden" | "CyberSlime" | "Void"
export type BodyShape = "Cube" | "Ball" | "Egg"
export type EarStyle = "None" | "Cat" | "Floppy" | "Fox" | "Horns"
export type WingStyle = "None" | "Chick" | "Bee" | "Dragon"
export type TailStyle = "None" | "Fluffy" | "Dragon"
export type ExtraStyle = "None" | "Beak" | "Rocket" | "Stripes" | "Visor" | "Tentacles" | "Drip"

export type BuddyForm = {
	Body: BodyShape,
	BodyColor: Color3,
	AccentColor: Color3,
	Ears: EarStyle,
	Wings: WingStyle,
	Tail: TailStyle,
	Extra: ExtraStyle,
	Scale: number,
}

export type BuddyDef = {
	Id: string,
	DisplayName: string,
	Rarity: Rarity,
	CoinBonus: number, -- +доля к монетам (0.10 = +10%)
	ImpactBonus: number, -- +доля к ударной массе
	SpringBonus: number, -- +доля к жёсткости резинки (Spring Power)
	Form: BuddyForm,
}

export type RarityDef = {
	Id: Rarity,
	DisplayName: string,
	Order: number,
	Color: Color3,
}

export type MutationDef = {
	Id: Mutation,
	DisplayName: string,
	Order: number,
	Multiplier: number, -- множитель всех бонусов бадди
	Material: Enum.Material,
	Tint: Color3?, -- во что «перекрашивается» тело (nil = родной цвет)
	TintAlpha: number,
	AuraColor: Color3,
	Next: Mutation?,
}

export type CapsuleDef = {
	Id: string,
	DisplayName: string,
	Price: number,
	RarityWeights: { [Rarity]: number },
	MutationBoost: number,
	TopColor: Color3,
	BottomColor: Color3,
	GlowColor: Color3,
}

export type EquippedBuddy = {
	BuddyId: string,
	Mutation: Mutation,
}

local function form(
	body: BodyShape,
	bodyColor: Color3,
	accent: Color3,
	ears: EarStyle,
	wings: WingStyle,
	tail: TailStyle,
	extra: ExtraStyle,
	scale: number
): BuddyForm
	return {
		Body = body,
		BodyColor = bodyColor,
		AccentColor = accent,
		Ears = ears,
		Wings = wings,
		Tail = tail,
		Extra = extra,
		Scale = scale,
	}
end

local RGB = Color3.fromRGB

local Buddies: { [string]: BuddyDef } = {
	SlimeCube = {
		Id = "SlimeCube",
		DisplayName = "Slime Cube",
		Rarity = "Common",
		CoinBonus = 0.1,
		ImpactBonus = 0,
		SpringBonus = 0,
		Form = form("Cube", RGB(110, 236, 120), RGB(60, 190, 90), "None", "None", "None", "Drip", 1),
	},
	SpringChick = {
		Id = "SpringChick",
		DisplayName = "Spring Chick",
		Rarity = "Common",
		CoinBonus = 0.04,
		ImpactBonus = 0,
		SpringBonus = 0.04,
		Form = form("Egg", RGB(255, 226, 90), RGB(255, 150, 40), "None", "Chick", "None", "Beak", 0.95),
	},
	RocketPup = {
		Id = "RocketPup",
		DisplayName = "Rocket Pup",
		Rarity = "Rare",
		CoinBonus = 0.05,
		ImpactBonus = 0.06,
		SpringBonus = 0,
		Form = form("Ball", RGB(230, 170, 110), RGB(120, 80, 50), "Floppy", "None", "None", "Rocket", 1),
	},
	HoneyBee = {
		Id = "HoneyBee",
		DisplayName = "Honey Bee",
		Rarity = "Rare",
		CoinBonus = 0.15,
		ImpactBonus = 0,
		SpringBonus = 0,
		Form = form("Egg", RGB(255, 206, 50), RGB(40, 30, 30), "None", "Bee", "None", "Stripes", 0.9),
	},
	CyberCat = {
		Id = "CyberCat",
		DisplayName = "Cyber Cat",
		Rarity = "Epic",
		CoinBonus = 0.08,
		ImpactBonus = 0.1,
		SpringBonus = 0.05,
		Form = form("Ball", RGB(170, 180, 205), RGB(60, 240, 255), "Cat", "None", "Fluffy", "Visor", 1),
	},
	GoldDragon = {
		Id = "GoldDragon",
		DisplayName = "Gold Dragon",
		Rarity = "Epic",
		CoinBonus = 0.35,
		ImpactBonus = 0.08,
		SpringBonus = 0,
		Form = form("Egg", RGB(255, 196, 60), RGB(255, 120, 40), "Horns", "Dragon", "Dragon", "None", 1.1),
	},
	PlasmaFox = {
		Id = "PlasmaFox",
		DisplayName = "Plasma Fox",
		Rarity = "Legendary",
		CoinBonus = 0.2,
		ImpactBonus = 0.12,
		SpringBonus = 0.12,
		Form = form("Ball", RGB(255, 110, 60), RGB(120, 240, 255), "Fox", "None", "Fluffy", "None", 1.05),
	},
	VoidKraken = {
		Id = "VoidKraken",
		DisplayName = "Void Kraken",
		Rarity = "Legendary",
		CoinBonus = 0.5,
		ImpactBonus = 0.15,
		SpringBonus = 0.1,
		Form = form("Egg", RGB(120, 70, 200), RGB(230, 120, 255), "None", "None", "None", "Tentacles", 1.15),
	},
}

local Rarities: { [Rarity]: RarityDef } = {
	Common = { Id = "Common", DisplayName = "ОБЫЧНЫЙ", Order = 1, Color = RGB(150, 205, 120) },
	Rare = { Id = "Rare", DisplayName = "РЕДКИЙ", Order = 2, Color = RGB(70, 170, 255) },
	Epic = { Id = "Epic", DisplayName = "ЭПИК", Order = 3, Color = RGB(190, 90, 255) },
	Legendary = { Id = "Legendary", DisplayName = "ЛЕГЕНДА", Order = 4, Color = RGB(255, 176, 30) },
}

local Mutations: { [Mutation]: MutationDef } = {
	Normal = {
		Id = "Normal",
		DisplayName = "Normal",
		Order = 1,
		Multiplier = 1,
		Material = Enum.Material.SmoothPlastic,
		Tint = nil,
		TintAlpha = 0,
		AuraColor = RGB(255, 255, 255),
		Next = "Golden",
	},
	Golden = {
		Id = "Golden",
		DisplayName = "Golden",
		Order = 2,
		Multiplier = 1.5,
		Material = Enum.Material.Foil,
		Tint = RGB(255, 206, 60),
		TintAlpha = 0.65,
		AuraColor = RGB(255, 220, 90),
		Next = "CyberSlime",
	},
	CyberSlime = {
		Id = "CyberSlime",
		DisplayName = "Cyber-Slime",
		Order = 3,
		Multiplier = 2.2,
		Material = Enum.Material.Glass,
		Tint = RGB(80, 255, 170),
		TintAlpha = 0.55,
		AuraColor = RGB(80, 255, 170),
		Next = "Void",
	},
	Void = {
		Id = "Void",
		DisplayName = "Void",
		Order = 4,
		Multiplier = 3.5,
		Material = Enum.Material.SmoothPlastic,
		Tint = RGB(36, 16, 60),
		TintAlpha = 0.75,
		AuraColor = RGB(200, 90, 255),
		Next = nil,
	},
}

local Capsules: { [string]: CapsuleDef } = {
	Basic = {
		Id = "Basic",
		DisplayName = "Basic Capsule",
		Price = 500,
		RarityWeights = { Common = 70, Rare = 25, Epic = 4.5, Legendary = 0.5 },
		MutationBoost = 1,
		TopColor = RGB(90, 200, 255),
		BottomColor = RGB(250, 252, 255),
		GlowColor = RGB(120, 220, 255),
	},
	Golden = {
		Id = "Golden",
		DisplayName = "Golden Capsule",
		Price = 5000,
		RarityWeights = { Common = 38, Rare = 42, Epic = 16, Legendary = 4 },
		MutationBoost = 1.6,
		TopColor = RGB(255, 206, 50),
		BottomColor = RGB(255, 246, 214),
		GlowColor = RGB(255, 214, 80),
	},
	Void = {
		Id = "Void",
		DisplayName = "Void Capsule",
		Price = 50000,
		RarityWeights = { Common = 8, Rare = 38, Epic = 38, Legendary = 16 },
		MutationBoost = 2.5,
		TopColor = RGB(160, 70, 255),
		BottomColor = RGB(40, 20, 70),
		GlowColor = RGB(210, 110, 255),
	},
}

local BuddyConfig = {
	MaxEquipped = 3,
	MaxInventory = 60,
	CraftCount = 3,
	Buddies = Buddies,
	Rarities = Rarities,
	Mutations = Mutations,
	Capsules = Capsules,
	RarityOrder = { "Common", "Rare", "Epic", "Legendary" } :: { Rarity },
	MutationOrder = { "Normal", "Golden", "CyberSlime", "Void" } :: { Mutation },
	CapsuleOrder = { "Basic", "Golden", "Void" },
	BuddyOrder = { "SlimeCube", "SpringChick", "RocketPup", "HoneyBee", "CyberCat", "GoldDragon", "PlasmaFox", "VoidKraken" },
}

function BuddyConfig.Get(buddyId: string): BuddyDef?
	return Buddies[buddyId]
end

function BuddyConfig.ToMutation(value: unknown): Mutation?
	if value == "Normal" then
		return "Normal"
	elseif value == "Golden" then
		return "Golden"
	elseif value == "CyberSlime" then
		return "CyberSlime"
	elseif value == "Void" then
		return "Void"
	end
	return nil
end

-- Шансы мутаций растут с тиром локации (ребёртами) и капсулой; Normal фиксирован как опорный вес
function BuddyConfig.MutationWeights(locationTier: number, capsuleId: string): { [Mutation]: number }
	local capsule = Capsules[capsuleId] or Capsules.Basic
	local tier = math.max(math.floor(locationTier), 0)
	local boost = capsule.MutationBoost
	return {
		Normal = 100,
		Golden = (5 + 4 * tier) * boost,
		CyberSlime = (0.8 + 2.2 * tier) * boost,
		Void = (0.15 + 1.1 * math.max(tier - 1, 0)) * boost,
	}
end

-- Нормированные вероятности (для витрины шансов)
function BuddyConfig.Normalize<K>(weights: { [K]: number }): { [K]: number }
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local result: { [K]: number } = {}
	for key, weight in weights do
		result[key] = if total > 0 then weight / total else 0
	end
	return result
end

local function pickWeighted<K>(order: { K }, weights: { [K]: number }, rng: Random): K
	local total = 0
	for _, key in order do
		total += weights[key] or 0
	end
	local roll = rng:NextNumber() * total
	for _, key in order do
		roll -= weights[key] or 0
		if roll <= 0 then
			return key
		end
	end
	return order[#order]
end

function BuddyConfig.RollBuddy(capsuleId: string, rng: Random): string
	local capsule = Capsules[capsuleId] or Capsules.Basic
	local rarity = pickWeighted(BuddyConfig.RarityOrder, capsule.RarityWeights, rng)
	local pool: { string } = {}
	for _, buddyId in BuddyConfig.BuddyOrder do
		if Buddies[buddyId].Rarity == rarity then
			table.insert(pool, buddyId)
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

function BuddyConfig.RollMutation(locationTier: number, capsuleId: string, rng: Random): Mutation
	return pickWeighted(BuddyConfig.MutationOrder, BuddyConfig.MutationWeights(locationTier, capsuleId), rng)
end

-- Суммарные множители экипированных бадди: (монеты, ударная масса, жёсткость). Аддитивно, как в топ-симуляторах.
function BuddyConfig.Multipliers(equipped: { EquippedBuddy }?): (number, number, number)
	local coins, impact, spring = 1, 1, 1
	if equipped == nil then
		return coins, impact, spring
	end
	for index, buddy in equipped do
		if index > BuddyConfig.MaxEquipped then
			break
		end
		local def = Buddies[buddy.BuddyId]
		local mutation = Mutations[buddy.Mutation]
		if def and mutation then
			coins += def.CoinBonus * mutation.Multiplier
			impact += def.ImpactBonus * mutation.Multiplier
			spring += def.SpringBonus * mutation.Multiplier
		end
	end
	return coins, impact, spring
end

-- Атрибут Player «EquippedBuddies»: "SlimeCube:Golden;RocketPup:Normal" (реплицируется всем клиентам)
function BuddyConfig.EncodeEquipped(equipped: { EquippedBuddy }): string
	local parts: { string } = {}
	for index, buddy in equipped do
		if index > BuddyConfig.MaxEquipped then
			break
		end
		table.insert(parts, buddy.BuddyId .. ":" .. buddy.Mutation)
	end
	return table.concat(parts, ";")
end

function BuddyConfig.DecodeEquipped(value: unknown): { EquippedBuddy }
	local result: { EquippedBuddy } = {}
	if typeof(value) ~= "string" then
		return result
	end
	for entry in string.gmatch(value, "[^;]+") do
		local buddyId, rawMutation = string.match(entry, "^(%w+):(%w+)$")
		local mutation = BuddyConfig.ToMutation(rawMutation)
		if buddyId and Buddies[buddyId] and mutation and #result < BuddyConfig.MaxEquipped then
			table.insert(result, { BuddyId = buddyId, Mutation = mutation })
		end
	end
	return result
end

function BuddyConfig.NextMutation(mutation: Mutation): Mutation?
	return Mutations[mutation].Next
end

-- Монеты за отпущенного бадди: растут с редкостью (×3 за ступень) и мутацией
function BuddyConfig.ReleaseValue(buddyId: string, mutation: Mutation): number
	local def = Buddies[buddyId]
	if def == nil then
		return 0
	end
	return math.floor(40 * 3 ^ (Rarities[def.Rarity].Order - 1) * Mutations[mutation].Multiplier + 0.5)
end

function BuddyConfig.BonusText(buddyId: string, mutation: Mutation): string
	local def = Buddies[buddyId]
	local multiplier = Mutations[mutation].Multiplier
	local parts: { string } = {}
	if def.CoinBonus > 0 then
		table.insert(parts, string.format("+%d%% монет", math.floor(def.CoinBonus * multiplier * 100 + 0.5)))
	end
	if def.ImpactBonus > 0 then
		table.insert(parts, string.format("+%d%% удар", math.floor(def.ImpactBonus * multiplier * 100 + 0.5)))
	end
	if def.SpringBonus > 0 then
		table.insert(parts, string.format("+%d%% пружина", math.floor(def.SpringBonus * multiplier * 100 + 0.5)))
	end
	return table.concat(parts, " · ")
end

return BuddyConfig
