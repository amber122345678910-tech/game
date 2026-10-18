--!strict
-- Питомцы-искрята: виды, коконы, шансы, бонусы. Чистая логика (без инстансов).

local Rng = require(script.Parent.Rng)

export type Rarity = "common" | "rare" | "epic" | "legendary" | "mythic"
export type BonusKind = "volts" | "luck" | "window" | "shards"
export type Shape = "ball" | "cloud" | "star" | "drop" | "crystal"

export type PetDef = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Bonus: BonusKind,
	Value: number, -- volts/luck/shards: доля (0.2 = +20%), window: миллисекунды
	Color: Color3,
	Accent: Color3,
	Shape: Shape,
}

export type CocoonDef = {
	Id: string,
	Name: string,
	Cost: number, -- осколки
	Zone: number, -- с какого острова доступен
	PityAt: number, -- легендарный или лучше гарантирован не позже
	Color: Color3,
	Pool: { { kind: string, weight: number } },
}

local Pets = {}

Pets.RarityOrder = { "common", "rare", "epic", "legendary", "mythic" } :: { Rarity }

Pets.Rarities = {
	common = { Name = "Обычный", Color = Color3.fromRGB(200, 205, 215), Rank = 1 },
	rare = { Name = "Редкий", Color = Color3.fromRGB(80, 170, 255), Rank = 2 },
	epic = { Name = "Эпический", Color = Color3.fromRGB(190, 100, 255), Rank = 3 },
	legendary = { Name = "Легендарный", Color = Color3.fromRGB(255, 190, 40), Rank = 4 },
	mythic = { Name = "Мифический", Color = Color3.fromRGB(255, 70, 160), Rank = 5 },
} :: { [Rarity]: { Name: string, Color: Color3, Rank: number } }

Pets.BonusNames = {
	volts = "⚡ Вольты",
	luck = "🍀 Удача",
	window = "🎯 Окно ИДЕАЛЬНО",
	shards = "💎 Осколки",
} :: { [BonusKind]: string }

local function def(id: string, name: string, rarity: Rarity, bonus: BonusKind, value: number, color: Color3, accent: Color3, shape: Shape): PetDef
	return { Id = id, Name = name, Rarity = rarity, Bonus = bonus, Value = value, Color = color, Accent = accent, Shape = shape }
end

local rgb = Color3.fromRGB

Pets.Kinds = {
	-- Луговой кокон
	iskorka = def("iskorka", "Искорка", "common", "volts", 0.08, rgb(120, 210, 255), rgb(255, 255, 255), "ball"),
	kapelka = def("kapelka", "Капелька", "common", "shards", 0.15, rgb(90, 160, 255), rgb(200, 240, 255), "drop"),
	luchik = def("luchik", "Лучик", "rare", "volts", 0.2, rgb(255, 230, 110), rgb(255, 255, 220), "star"),
	tuchka = def("tuchka", "Тучка", "rare", "luck", 0.1, rgb(170, 180, 205), rgb(120, 220, 255), "cloud"),
	sharovik = def("sharovik", "Шаровик", "epic", "volts", 0.45, rgb(255, 150, 60), rgb(255, 240, 160), "ball"),
	zarnitsa = def("zarnitsa", "Зарница", "legendary", "volts", 1.0, rgb(255, 110, 200), rgb(255, 230, 120), "star"),
	-- особые (награды)
	gromik = def("gromik", "Громик", "epic", "volts", 0.6, rgb(150, 110, 255), rgb(255, 230, 90), "cloud"),
	-- Ледяной кокон
	snezhok = def("snezhok", "Снежок", "common", "volts", 0.25, rgb(235, 245, 255), rgb(150, 210, 255), "ball"),
	iney = def("iney", "Иней", "common", "shards", 0.3, rgb(170, 230, 255), rgb(255, 255, 255), "crystal"),
	severok = def("severok", "Северок", "rare", "luck", 0.2, rgb(110, 255, 200), rgb(190, 130, 255), "star"),
	sosulka = def("sosulka", "Сосулька", "rare", "window", 15, rgb(160, 220, 255), rgb(255, 255, 255), "crystal"),
	buran = def("buran", "Буран", "epic", "volts", 0.9, rgb(200, 215, 255), rgb(120, 140, 255), "cloud"),
	siyanie = def("siyanie", "Сияние", "legendary", "volts", 2.0, rgb(90, 255, 180), rgb(200, 120, 255), "star"),
	polyarnik = def("polyarnik", "Полярник", "mythic", "volts", 5.0, rgb(255, 255, 255), rgb(120, 255, 255), "crystal"),
	-- Грозовой кокон
	grozik = def("grozik", "Грозик", "common", "volts", 0.6, rgb(130, 120, 255), rgb(220, 220, 255), "cloud"),
	vihr = def("vihr", "Вихрь", "common", "luck", 0.25, rgb(170, 255, 230), rgb(255, 255, 255), "drop"),
	tesla = def("tesla", "Тесла", "rare", "volts", 1.2, rgb(90, 200, 255), rgb(255, 255, 255), "crystal"),
	strelka = def("strelka", "Стрелка", "rare", "window", 22, rgb(255, 235, 120), rgb(255, 255, 255), "star"),
	gromovik = def("gromovik", "Громовик", "epic", "volts", 2.4, rgb(110, 70, 200), rgb(255, 210, 70), "cloud"),
	carmolniya = def("carmolniya", "Царь-Молния", "legendary", "volts", 5.0, rgb(255, 215, 60), rgb(255, 255, 255), "star"),
	perunchik = def("perunchik", "Перунчик", "mythic", "volts", 12.0, rgb(40, 30, 60), rgb(255, 200, 60), "ball"),
} :: { [string]: PetDef }

Pets.CocoonOrder = { "meadow", "ice", "storm" }

Pets.Cocoons = {
	meadow = {
		Id = "meadow",
		Name = "Луговой кокон",
		Cost = 25,
		Zone = 1,
		PityAt = 40,
		Color = rgb(130, 220, 120),
		Pool = {
			{ kind = "iskorka", weight = 45 },
			{ kind = "kapelka", weight = 30 },
			{ kind = "luchik", weight = 15 },
			{ kind = "tuchka", weight = 7 },
			{ kind = "sharovik", weight = 2.6 },
			{ kind = "zarnitsa", weight = 0.4 },
		},
	},
	ice = {
		Id = "ice",
		Name = "Ледяной кокон",
		Cost = 300,
		Zone = 4,
		PityAt = 40,
		Color = rgb(170, 220, 255),
		Pool = {
			{ kind = "snezhok", weight = 45 },
			{ kind = "iney", weight = 28 },
			{ kind = "severok", weight = 16 },
			{ kind = "sosulka", weight = 8 },
			{ kind = "buran", weight = 2.6 },
			{ kind = "siyanie", weight = 0.38 },
			{ kind = "polyarnik", weight = 0.02 },
		},
	},
	storm = {
		Id = "storm",
		Name = "Грозовой кокон",
		Cost = 2500,
		Zone = 5,
		PityAt = 40,
		Color = rgb(150, 110, 255),
		Pool = {
			{ kind = "grozik", weight = 45 },
			{ kind = "vihr", weight = 28 },
			{ kind = "tesla", weight = 16 },
			{ kind = "strelka", weight = 8 },
			{ kind = "gromovik", weight = 2.6 },
			{ kind = "carmolniya", weight = 0.37 },
			{ kind = "perunchik", weight = 0.03 },
		},
	},
} :: { [string]: CocoonDef }

Pets.StarterPet = "iskorka"
Pets.MaxInventory = 60

local function rank(kind: string): number
	return Pets.Rarities[Pets.Kinds[kind].Rarity].Rank
end

-- Вылупить: roll в [0,1). pity — сколько коконов этого типа подряд без легендарного.
-- Возвращает вид питомца и новое значение pity.
function Pets.roll(cocoonId: string, roll: number, pity: number): (string, number)
	local cocoon = Pets.Cocoons[cocoonId]
	assert(cocoon, "unknown cocoon " .. cocoonId)
	local pool: { Rng.Weighted<string> } = {}
	local guaranteed = pity + 1 >= cocoon.PityAt
	for _, e in cocoon.Pool do
		if not guaranteed or rank(e.kind) >= 4 then
			table.insert(pool, { item = e.kind, weight = e.weight })
		end
	end
	local kind = Rng.pick(pool, roll)
	local newPity = if rank(kind) >= 4 then 0 else pity + 1
	return kind, newPity
end

-- Шансы для показа в интерфейсе (сумма = 1)
function Pets.chances(cocoonId: string): { { kind: string, chance: number } }
	local cocoon = Pets.Cocoons[cocoonId]
	local total = 0
	for _, e in cocoon.Pool do
		total += e.weight
	end
	local out = {}
	for _, e in cocoon.Pool do
		table.insert(out, { kind = e.kind, chance = e.weight / total })
	end
	return out
end

export type Bonuses = { volts: number, luck: number, window: number, shards: number }

function Pets.totalBonus(kinds: { string }): Bonuses
	local b: Bonuses = { volts = 0, luck = 0, window = 0, shards = 0 }
	for _, kind in kinds do
		local d = Pets.Kinds[kind]
		if d then
			if d.Bonus == "volts" then
				b.volts += d.Value
			elseif d.Bonus == "luck" then
				b.luck += d.Value
			elseif d.Bonus == "window" then
				b.window += d.Value
			else
				b.shards += d.Value
			end
		end
	end
	return b
end

function Pets.bonusText(kind: string): string
	local d = Pets.Kinds[kind]
	if not d then
		return ""
	end
	if d.Bonus == "window" then
		return string.format("%s +%d мс", Pets.BonusNames.window, d.Value)
	end
	return string.format("%s +%d%%", Pets.BonusNames[d.Bonus], math.floor(d.Value * 100 + 0.5))
end

return Pets
