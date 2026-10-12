--!strict
-- Конфиг игры: тайминги фаз, сложности, движение, укрытия, шум, экономика, предметы, перки, прогрессия.
-- Все балансные числа — здесь, чтобы менять в одном месте. Подробное обоснование — docs/GDD.md.

local Config = {}

Config.Version = "0.1.0"
Config.DataVersion = 1
Config.DataStoreName = "AmberAlert_HollowCreek_v1"
Config.LeaderboardStoreName = "AmberAlert_BestNights_v1"
Config.MaxPlayers = 8

----------------------------------------------------------------------
-- Сложности
----------------------------------------------------------------------
export type DifficultyDef = {
	Id: string,
	Order: number,
	Nights: number,
	-- количество пациентов за ночь: Base до ночи ExtraFrom, затем Base + 1
	InmatesBase: number,
	ExtraFrom: number, -- 0 = никогда
	PriceMult: number,
	HpMult: number,
	SpeedMult: number,
	ReturnTakenAtDawn: boolean,
	AmberPerNight: number,
	Color: Color3,
}

Config.Difficulties = {
	Easy = { Id = "Easy", Order = 1, Nights = 5, InmatesBase = 1, ExtraFrom = 0, PriceMult = 0.8, HpMult = 0.85, SpeedMult = 0.95, ReturnTakenAtDawn = true, AmberPerNight = 6, Color = Color3.fromRGB(90, 180, 100) },
	Normal = { Id = "Normal", Order = 2, Nights = 8, InmatesBase = 1, ExtraFrom = 6, PriceMult = 1, HpMult = 1, SpeedMult = 1, ReturnTakenAtDawn = true, AmberPerNight = 10, Color = Color3.fromRGB(255, 170, 40) },
	Hard = { Id = "Hard", Order = 3, Nights = 12, InmatesBase = 1, ExtraFrom = 5, PriceMult = 1.25, HpMult = 1.3, SpeedMult = 1.08, ReturnTakenAtDawn = false, AmberPerNight = 16, Color = Color3.fromRGB(230, 100, 40) },
	Nightmare = { Id = "Nightmare", Order = 4, Nights = 15, InmatesBase = 2, ExtraFrom = 8, PriceMult = 1.5, HpMult = 1.6, SpeedMult = 1.15, ReturnTakenAtDawn = false, AmberPerNight = 25, Color = Color3.fromRGB(205, 42, 42) },
} :: { [string]: DifficultyDef }

Config.DefaultDifficulty = "Normal"

function Config.getDifficulty(id: string?): DifficultyDef
	return Config.Difficulties[id or ""] or Config.Difficulties[Config.DefaultDifficulty]
end

function Config.difficultyList(): { DifficultyDef }
	local list: { DifficultyDef } = {}
	for _, d in Config.Difficulties do
		table.insert(list, d)
	end
	table.sort(list, function(a: DifficultyDef, b: DifficultyDef)
		return a.Order < b.Order
	end)
	return list
end

-- Сколько пациентов выходит в ночь night
function Config.inmatesForNight(diff: DifficultyDef, night: number): number
	local n = diff.InmatesBase
	if diff.ExtraFrom > 0 and night >= diff.ExtraFrom then
		n += 1
	end
	return n
end

----------------------------------------------------------------------
-- Фазы матча (секунды)
----------------------------------------------------------------------
Config.Phases = {
	LobbyCountdown = 30,
	LobbyMinPlayers = 1,
	Day = 60,
	FirstDay = 75,
	Alert = 18,
	NightBase = 100,
	NightPerNight = 8,
	NightMax = 180,
	Dawn = 8,
	Results = 20,
}

-- Игровые часы: день 07:00 → 21:00, ночь 21:00 → 06:00 (фаза Dawn — 06:00 → 07:00)
Config.Clock = {
	DayStartHour = 7,
	NightStartHour = 21,
	DawnHour = 6,
}

function Config.nightDuration(night: number): number
	return math.min(Config.Phases.NightMax, Config.Phases.NightBase + Config.Phases.NightPerNight * (night - 1))
end

----------------------------------------------------------------------
-- Движение, фонарик, укрытия, шум, зрение
----------------------------------------------------------------------
Config.Movement = {
	WalkSpeed = 12,
	SprintSpeed = 22,
	CrouchSpeed = 7,
	HidingSpeed = 0,
	StaminaMax = 100,
	SprintDrain = 18, -- в секунду
	RegenWalk = 12,
	RegenIdle = 18,
	ExhaustLock = 3, -- секунд нельзя бежать после нуля
	CrouchCameraDrop = 1.6,
	MaxLegalSpeed = 30, -- античит: выше — возврат на место
	CrouchHeadDrop = 1.8, -- насколько ниже "голова" для проверки видимости
}

Config.Flashlight = {
	Angle = 50,
	Range = 45,
	Brightness = 1.7,
	Battery = 150, -- секунд непрерывной работы
	RevealDistance = 25, -- луч, направленный на пациента ближе этого, выдаёт игрока
	LowBattery = 20,
}

Config.Hiding = {
	BreathMax = 100,
	BreathDrainNear = 12, -- в секунду, когда пациент ближе NearDistance
	BreathRegen = 10,
	NearDistance = 15,
	HoldSeconds = 6, -- сколько можно задерживать дыхание
	HoldCooldown = 4,
	ReenterLock = 6, -- секунд после выхода нельзя прятаться снова
	SearchChanceSeen = 1, -- пациент видел, как игрок спрятался
	SearchChanceIdle = 0.12, -- проходит мимо без цели
	SearchChanceAfterEscapes = 0.5, -- после двух побегов из этого укрытия
	SearchRadius = 10,
	BossWaitSeconds = 8,
}

Config.Noise = {
	Sprint = 22,
	Door = 18,
	Window = 45,
	Shot = 120,
	Apple = 8,
	Trap = 30,
	Phone = 40,
	Fall = 15,
	Switch = 6,
	Gasp = 25,
	Breaking = 35,
	Revive = 10,
} :: { [string]: number }

Config.Vision = {
	SightLit = 40,
	SightDark = 14,
	CrouchMult = 0.6,
	CatchDistance = 3.2,
	EyeHeight = 4.5,
	ChaseBoostAfter = 2, -- секунд непрерывной видимости
	ChaseBoost = 1.25,
	LoseSightAfter = 2.5, -- секунд без видимости → Search
	FovCos = -0.2, -- косинус половины угла обзора (~100°); пациент "видит" и чуть сзади
}

Config.Downed = {
	Duration = 60,
	ReviveHold = 4,
	InmateCooldownAfterCatch = 3,
	DefibrillatorRange = 7,
}

Config.InventorySlots = 4

----------------------------------------------------------------------
-- Экономика
----------------------------------------------------------------------
Config.Economy = {
	AppleValue = 25,
	AppleInterval = 60,
	StartingTrees = 3,
	StartingApples = 3,
	MaxTrees = 8,
	MaxApplesPerTree = 3,
	SprinklerBonus = 0.15,
	MaxSprinklers = 3,
	RakeInterval = 40,
	TreePrices = { 400, 1250, 2500, 5000, 7500 },
	StartingCash = 0,
	StudioStartingCash = 3000,
	ApplePickRange = 9,
}

export type ItemCategory = "Defense" | "Offense" | "Utility" | "Farm"
export type ItemKind = "Placeable" | "Consumable" | "Weapon" | "Upgrade" | "Ammo"

export type ItemDef = {
	Id: string,
	Category: ItemCategory,
	Kind: ItemKind,
	Order: number,
	Price: number,
	PriceStep: number, -- рост цены после каждой покупки
	Stack: number, -- максимум в одном слоте
	GiveCount: number, -- сколько единиц даёт покупка
	Once: boolean, -- апгрейд покупается один раз на отряд
	MaxOwned: number, -- 0 = без лимита (для Upgrade: сколько раз можно купить)
	Charges: number, -- заряды (StunGun), патроны (Shotgun) — хранятся в слоте
	Color: Color3,
	-- боевые параметры
	Stun: number,
	Damage: number,
	Range: number,
	Slow: number, -- доля замедления
	SlowTime: number,
}

local function item(def: { [string]: any }): ItemDef
	return {
		Id = def.Id,
		Category = def.Category,
		Kind = def.Kind,
		Order = def.Order or 0,
		Price = def.Price or 0,
		PriceStep = def.PriceStep or 0,
		Stack = def.Stack or 1,
		GiveCount = def.GiveCount or 1,
		Once = def.Once == true,
		MaxOwned = def.MaxOwned or 0,
		Charges = def.Charges or 0,
		Color = def.Color or Color3.fromRGB(200, 200, 200),
		Stun = def.Stun or 0,
		Damage = def.Damage or 0,
		Range = def.Range or 0,
		Slow = def.Slow or 0,
		SlowTime = def.SlowTime or 0,
	}
end

Config.Items = {
	Batteries = item({ Id = "Batteries", Category = "Utility", Kind = "Consumable", Order = 1, Price = 60, Stack = 3, Color = Color3.fromRGB(230, 200, 60) }),
	Planks = item({ Id = "Planks", Category = "Defense", Kind = "Placeable", Order = 1, Price = 100, Stack = 9, GiveCount = 3, Color = Color3.fromRGB(150, 110, 70) }),
	BearTrap = item({ Id = "BearTrap", Category = "Defense", Kind = "Placeable", Order = 2, Price = 250, PriceStep = 50, Stack = 3, Stun = 3, Damage = 35, Color = Color3.fromRGB(120, 120, 130) }),
	GlueTrap = item({ Id = "GlueTrap", Category = "Defense", Kind = "Placeable", Order = 3, Price = 200, PriceStep = 50, Stack = 3, Slow = 0.6, SlowTime = 4, Color = Color3.fromRGB(230, 230, 120) }),
	PepperSpray = item({ Id = "PepperSpray", Category = "Offense", Kind = "Weapon", Order = 1, Price = 300, Stack = 1, Charges = 1, Stun = 4, Range = 6, Color = Color3.fromRGB(220, 60, 50) }),
	StunGun = item({ Id = "StunGun", Category = "Offense", Kind = "Weapon", Order = 2, Price = 600, Stack = 1, Charges = 3, Stun = 5, Range = 8, Color = Color3.fromRGB(80, 160, 230) }),
	Shotgun = item({ Id = "Shotgun", Category = "Offense", Kind = "Weapon", Order = 3, Price = 1500, PriceStep = 100, Stack = 1, Charges = 1, Damage = 100, Stun = 1.5, Range = 60, Color = Color3.fromRGB(70, 60, 50) }),
	Shells = item({ Id = "Shells", Category = "Offense", Kind = "Ammo", Order = 4, Price = 150, Stack = 5, GiveCount = 2, Color = Color3.fromRGB(200, 60, 40) }),
	Defibrillator = item({ Id = "Defibrillator", Category = "Utility", Kind = "Consumable", Order = 2, Price = 500, Stack = 1, Range = 7, Color = Color3.fromRGB(240, 240, 240) }),
	MotionLight = item({ Id = "MotionLight", Category = "Utility", Kind = "Upgrade", Order = 3, Price = 500, Once = true, MaxOwned = 1, Color = Color3.fromRGB(255, 240, 180) }),
	Candles = item({ Id = "Candles", Category = "Utility", Kind = "Upgrade", Order = 4, Price = 200, Once = true, MaxOwned = 1, Color = Color3.fromRGB(255, 200, 120) }),
	AppleTree = item({ Id = "AppleTree", Category = "Farm", Kind = "Upgrade", Order = 1, Price = 400, MaxOwned = 5, Color = Color3.fromRGB(110, 190, 90) }),
	Sprinkler = item({ Id = "Sprinkler", Category = "Farm", Kind = "Upgrade", Order = 2, Price = 250, MaxOwned = 3, Color = Color3.fromRGB(90, 170, 230) }),
	Rake = item({ Id = "Rake", Category = "Farm", Kind = "Upgrade", Order = 3, Price = 1300, Once = true, MaxOwned = 1, Color = Color3.fromRGB(170, 130, 80) }),
} :: { [string]: ItemDef }

function Config.getItem(id: string): ItemDef?
	return Config.Items[id]
end

function Config.itemList(): { ItemDef }
	local list: { ItemDef } = {}
	for _, def in Config.Items do
		table.insert(list, def)
	end
	table.sort(list, function(a: ItemDef, b: ItemDef)
		if a.Category ~= b.Category then
			return a.Category < b.Category
		end
		return a.Order < b.Order
	end)
	return list
end

----------------------------------------------------------------------
-- Перки (мета, покупаются за Амбер в лобби)
----------------------------------------------------------------------
export type PerkDef = {
	Id: string,
	Order: number,
	Costs: { number },
	Values: { number },
	Color: Color3,
}

Config.Perks = {
	Sprinter = { Id = "Sprinter", Order = 1, Costs = { 40, 80, 140 }, Values = { 0.15, 0.3, 0.45 }, Color = Color3.fromRGB(80, 200, 120) },
	Scavenger = { Id = "Scavenger", Order = 2, Costs = { 40, 90, 160 }, Values = { 0.1, 0.2, 0.3 }, Color = Color3.fromRGB(120, 220, 130) },
	Trapper = { Id = "Trapper", Order = 3, Costs = { 60, 120, 200 }, Values = { 1, 2, 3 }, Color = Color3.fromRGB(150, 150, 160) },
	Medic = { Id = "Medic", Order = 4, Costs = { 50, 100, 170 }, Values = { 3, 2.5, 2 }, Color = Color3.fromRGB(240, 240, 240) },
	NightOwl = { Id = "NightOwl", Order = 5, Costs = { 50, 110, 190 }, Values = { 0.15, 0.25, 0.35 }, Color = Color3.fromRGB(120, 130, 220) },
	LuckyStart = { Id = "LuckyStart", Order = 6, Costs = { 40, 100, 180 }, Values = { 150, 300, 500 }, Color = Color3.fromRGB(255, 170, 40) },
} :: { [string]: PerkDef }

function Config.perkList(): { PerkDef }
	local list: { PerkDef } = {}
	for _, p in Config.Perks do
		table.insert(list, p)
	end
	table.sort(list, function(a: PerkDef, b: PerkDef)
		return a.Order < b.Order
	end)
	return list
end

function Config.perkValue(id: string, level: number): number
	local def = Config.Perks[id]
	if not def or level <= 0 then
		return 0
	end
	return def.Values[math.clamp(level, 1, #def.Values)]
end

----------------------------------------------------------------------
-- Режиссёр напряжения
----------------------------------------------------------------------
Config.Director = {
	Downed = 40,
	Near = 25, -- пациент ближе NearDistance
	NearDistance = 15,
	Heard = 10,
	Decay = 3, -- в секунду без контакта
	PeakThreshold = 70,
	SustainSeconds = 4,
	RelaxMin = 30,
	RelaxMax = 45,
	RelaxHearMult = 0.5,
	RelaxSightMult = 0.7,
}

----------------------------------------------------------------------
-- Прогрессия
----------------------------------------------------------------------
Config.Progression = {
	AmberWinBase = 50,
	XpPerNight = 10,
	XpWin = 100,
	Titles = {
		{ 0, "Newcomer" },
		{ 5, "Resident" },
		{ 10, "Night Owl" },
		{ 20, "Warden" },
		{ 35, "Hollow" },
	} :: { { any } },
}

function Config.levelFromXp(xp: number): number
	return math.floor(math.sqrt(math.max(0, xp) / 50))
end

function Config.xpForLevel(level: number): number
	return level * level * 50
end

function Config.titleForLevel(level: number): string
	local title = "Newcomer"
	for _, entry in Config.Progression.Titles do
		if level >= (entry[1] :: number) then
			title = entry[2] :: string
		end
	end
	return title
end

-- Бейджи и геймпассы: 0 = выключено. После публикации впиши ID из Creator Hub.
Config.Badges = {
	FirstNight = 0,
	FirstWin = 0,
	WinHard = 0,
	WinNightmare = 0,
	MetHollowMan = 0,
	Survived10 = 0,
} :: { [string]: number }

Config.Passes = {
	FlashlightColors = 0,
	DoubleAmber = 0,
	KeepItems = 0,
	VIP = 0,
} :: { [string]: number }

----------------------------------------------------------------------
-- Карта
----------------------------------------------------------------------
Config.Map = {
	LobbyOrigin = Vector3.new(0, 0, 400),
	HouseOrigin = Vector3.new(0, 0, 0),
	FloorHeight = 11,
	-- Если игрок ниже этой высоты — вернуть на спавн (провалился сквозь карту).
	KillY = -60,
}

return Config
