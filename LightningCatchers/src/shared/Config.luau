--!strict
-- Все настройки игры в одном месте: баланс, острова, молнии, улучшения, события.
-- Меняешь числа здесь — меняется игра (и тесты/симуляция баланса берут их отсюда же).

local Config = {}

Config.Version = "1.0"
Config.DataVersion = 1

----------------------------------------------------------------------
-- Цвета (редкости) молний
----------------------------------------------------------------------
export type ColorId = "blue" | "purple" | "green" | "red" | "gold" | "rainbow" | "black"

export type ColorDef = {
	Id: ColorId,
	Name: string, -- "Голубая"
	Mult: number, -- множитель заряда
	Color: Color3,
	Icon: string, -- значок в кольце и в интерфейсе
	Order: number, -- 1 = самая частая
	FulgChance: number, -- шанс фульгурита при ИДЕАЛЬНО
}

Config.ColorOrder = { "blue", "purple", "green", "red", "gold", "rainbow", "black" } :: { ColorId }

Config.Colors = {
	blue = { Id = "blue", Name = "Голубая", Mult = 1, Color = Color3.fromRGB(110, 200, 255), Icon = "●", Order = 1, FulgChance = 0.01 },
	purple = { Id = "purple", Name = "Фиолетовая", Mult = 2.5, Color = Color3.fromRGB(190, 120, 255), Icon = "◆", Order = 2, FulgChance = 0.025 },
	green = { Id = "green", Name = "Изумрудная", Mult = 6, Color = Color3.fromRGB(80, 255, 150), Icon = "▲", Order = 3, FulgChance = 0.06 },
	red = { Id = "red", Name = "Алая", Mult = 15, Color = Color3.fromRGB(255, 80, 90), Icon = "★", Order = 4, FulgChance = 0.14 },
	gold = { Id = "gold", Name = "Золотая", Mult = 40, Color = Color3.fromRGB(255, 210, 60), Icon = "✦", Order = 5, FulgChance = 0.35 },
	rainbow = { Id = "rainbow", Name = "Радужная", Mult = 120, Color = Color3.fromRGB(255, 140, 220), Icon = "✺", Order = 6, FulgChance = 1 },
	black = { Id = "black", Name = "Чёрная Перуна", Mult = 600, Color = Color3.fromRGB(40, 20, 60), Icon = "☯", Order = 7, FulgChance = 1 },
} :: { [ColorId]: ColorDef }

-- Обычные цвета (выпадают в потоке ударов). Радужная и Чёрная — особые.
Config.NormalColors = { "blue", "purple", "green", "red", "gold" } :: { ColorId }

----------------------------------------------------------------------
-- Типы ударов
----------------------------------------------------------------------
export type KindId = "single" | "double" | "fork" | "fake" | "runner"

Config.Kinds = {
	single = { Name = "Обычный", FromZone = 1, Hits = { 0 } },
	double = { Name = "Двойной", FromZone = 2, Hits = { 0, 0.45 } },
	fork = { Name = "Вилка", FromZone = 3, Hits = { 0, 0.5, 0.85 } },
	fake = { Name = "Обманка", FromZone = 4, Hits = { 0 } },
	runner = { Name = "Бегущий", FromZone = 5, Hits = { 0 } },
} :: { [KindId]: { Name: string, FromZone: number, Hits: { number } } }

----------------------------------------------------------------------
-- Острова
----------------------------------------------------------------------
export type ZoneDef = {
	Index: number,
	Name: string,
	Short: string,
	BaseCharge: number, -- заряд голубой молнии при оценке ХОРОШО без улучшений
	Warning: number, -- секунд от появления кольца до удара
	Interval: number, -- средний интервал между новыми кольцами (с)
	MaxActive: number, -- одновременно колец (без Магнита)
	Cost: number, -- цена открытия (Вольты)
	ShardValue: number, -- осколков за осколок на земле
	ColorWeights: { [ColorId]: number },
	KindWeights: { [KindId]: number },
	Penalties: boolean, -- удар током за ошибки
	Overcharge: boolean, -- можно перегружать банку
	-- геометрия
	Angle: number, -- градусы вокруг хаба
	Distance: number, -- от центра хаба до центра острова
	Radius: number, -- радиус острова
	PlayRadius: number, -- радиус, внутри которого бьют молнии
	GroundY: number, -- высота поверхности
	-- оформление
	Grass: Color3,
	GrassMaterial: Enum.Material,
	Rock: Color3,
	Accent: Color3,
	Sky: {
		Ambient: Color3,
		OutdoorAmbient: Color3,
		AtmosphereColor: Color3,
		AtmosphereDecay: Color3,
		Density: number,
		Haze: number,
		Tint: Color3,
		Saturation: number,
		CloudColor: Color3,
	},
}

Config.Zones = {
	{
		Index = 1,
		Name = "Грозовой Луг",
		Short = "Луг",
		BaseCharge = 1,
		Warning = 2.4,
		Interval = 1.6,
		MaxActive = 3,
		Cost = 0,
		ShardValue = 1,
		ColorWeights = { blue = 82, purple = 15, green = 2.6, red = 0.35, gold = 0.05 },
		KindWeights = { single = 1 },
		Penalties = false,
		Overcharge = false,
		Angle = 0,
		Distance = 250,
		Radius = 86,
		PlayRadius = 68,
		GroundY = 0,
		Grass = Color3.fromRGB(92, 168, 82),
		GrassMaterial = Enum.Material.Grass,
		Rock = Color3.fromRGB(120, 124, 132),
		Accent = Color3.fromRGB(110, 200, 255),
		Sky = {
			Ambient = Color3.fromRGB(70, 78, 110),
			OutdoorAmbient = Color3.fromRGB(110, 120, 160),
			AtmosphereColor = Color3.fromRGB(120, 140, 190),
			AtmosphereDecay = Color3.fromRGB(60, 70, 120),
			Density = 0.33,
			Haze = 1.6,
			Tint = Color3.fromRGB(225, 232, 255),
			Saturation = 0.08,
			CloudColor = Color3.fromRGB(70, 76, 100),
		},
	},
	{
		Index = 2,
		Name = "Медные Холмы",
		Short = "Холмы",
		BaseCharge = 8,
		Warning = 2.2,
		Interval = 1.5,
		MaxActive = 3,
		Cost = 220,
		ShardValue = 2,
		ColorWeights = { blue = 66, purple = 24, green = 8, red = 1.7, gold = 0.3 },
		KindWeights = { single = 0.8, double = 0.2 },
		Penalties = true,
		Overcharge = true,
		Angle = 72,
		Distance = 250,
		Radius = 90,
		PlayRadius = 72,
		GroundY = 8,
		Grass = Color3.fromRGB(176, 124, 70),
		GrassMaterial = Enum.Material.Grass,
		Rock = Color3.fromRGB(122, 96, 84),
		Accent = Color3.fromRGB(255, 150, 70),
		Sky = {
			Ambient = Color3.fromRGB(90, 72, 96),
			OutdoorAmbient = Color3.fromRGB(150, 118, 140),
			AtmosphereColor = Color3.fromRGB(190, 140, 150),
			AtmosphereDecay = Color3.fromRGB(110, 70, 100),
			Density = 0.34,
			Haze = 1.8,
			Tint = Color3.fromRGB(255, 236, 225),
			Saturation = 0.1,
			CloudColor = Color3.fromRGB(86, 70, 90),
		},
	},
	{
		Index = 3,
		Name = "Стеклянные Дюны",
		Short = "Дюны",
		BaseCharge = 60,
		Warning = 2.0,
		Interval = 1.45,
		MaxActive = 4,
		Cost = 12000,
		ShardValue = 4,
		ColorWeights = { blue = 50, purple = 30, green = 14, red = 4.5, gold = 1.5 },
		KindWeights = { single = 0.65, double = 0.2, fork = 0.15 },
		Penalties = true,
		Overcharge = true,
		Angle = 144,
		Distance = 250,
		Radius = 94,
		PlayRadius = 76,
		GroundY = 4,
		Grass = Color3.fromRGB(232, 204, 146),
		GrassMaterial = Enum.Material.Sand,
		Rock = Color3.fromRGB(188, 150, 110),
		Accent = Color3.fromRGB(110, 240, 230),
		Sky = {
			Ambient = Color3.fromRGB(70, 96, 104),
			OutdoorAmbient = Color3.fromRGB(120, 160, 160),
			AtmosphereColor = Color3.fromRGB(140, 190, 190),
			AtmosphereDecay = Color3.fromRGB(70, 110, 120),
			Density = 0.32,
			Haze = 1.4,
			Tint = Color3.fromRGB(235, 255, 250),
			Saturation = 0.12,
			CloudColor = Color3.fromRGB(70, 90, 96),
		},
	},
	{
		Index = 4,
		Name = "Ледяной Пик",
		Short = "Пик",
		BaseCharge = 450,
		Warning = 1.85,
		Interval = 1.4,
		MaxActive = 4,
		Cost = 600000,
		ShardValue = 8,
		ColorWeights = { blue = 40, purple = 30, green = 19, red = 8, gold = 3 },
		KindWeights = { single = 0.5, double = 0.2, fork = 0.15, fake = 0.15 },
		Penalties = true,
		Overcharge = true,
		Angle = 216,
		Distance = 250,
		Radius = 94,
		PlayRadius = 76,
		GroundY = 14,
		Grass = Color3.fromRGB(236, 242, 255),
		GrassMaterial = Enum.Material.Snow,
		Rock = Color3.fromRGB(150, 170, 200),
		Accent = Color3.fromRGB(190, 120, 255),
		Sky = {
			Ambient = Color3.fromRGB(80, 80, 120),
			OutdoorAmbient = Color3.fromRGB(130, 130, 190),
			AtmosphereColor = Color3.fromRGB(150, 150, 220),
			AtmosphereDecay = Color3.fromRGB(80, 70, 150),
			Density = 0.34,
			Haze = 1.5,
			Tint = Color3.fromRGB(235, 235, 255),
			Saturation = 0.06,
			CloudColor = Color3.fromRGB(80, 80, 112),
		},
	},
	{
		Index = 5,
		Name = "Око Бури",
		Short = "Око",
		BaseCharge = 3500,
		Warning = 1.7,
		Interval = 1.35,
		MaxActive = 5,
		Cost = 15000000,
		ShardValue = 16,
		ColorWeights = { blue = 30, purple = 28, green = 22, red = 13, gold = 7 },
		KindWeights = { single = 0.4, double = 0.15, fork = 0.15, fake = 0.15, runner = 0.15 },
		Penalties = true,
		Overcharge = true,
		Angle = 288,
		Distance = 255,
		Radius = 100,
		PlayRadius = 80,
		GroundY = 22,
		Grass = Color3.fromRGB(58, 50, 70),
		GrassMaterial = Enum.Material.Basalt,
		Rock = Color3.fromRGB(44, 38, 54),
		Accent = Color3.fromRGB(255, 200, 80),
		Sky = {
			Ambient = Color3.fromRGB(80, 60, 110),
			OutdoorAmbient = Color3.fromRGB(130, 100, 170),
			AtmosphereColor = Color3.fromRGB(130, 90, 170),
			AtmosphereDecay = Color3.fromRGB(70, 40, 110),
			Density = 0.38,
			Haze = 2.0,
			Tint = Color3.fromRGB(240, 225, 255),
			Saturation = 0.14,
			CloudColor = Color3.fromRGB(60, 44, 80),
		},
	},
} :: { ZoneDef }

-- Хаб (Электроград) — в центре, без молний
Config.Hub = {
	Name = "Электроград",
	Radius = 96,
	GroundY = 0,
	Sky = {
		Ambient = Color3.fromRGB(80, 80, 110),
		OutdoorAmbient = Color3.fromRGB(125, 125, 165),
		AtmosphereColor = Color3.fromRGB(130, 140, 190),
		AtmosphereDecay = Color3.fromRGB(70, 70, 120),
		Density = 0.3,
		Haze = 1.4,
		Tint = Color3.fromRGB(240, 238, 255),
		Saturation = 0.1,
		CloudColor = Color3.fromRGB(74, 76, 104),
	},
}

Config.BridgeWidth = 18
Config.CloudHeight = 95 -- высота потолка туч над землёй острова
Config.VoidY = -60 -- ниже этой высоты игрок возвращается на остров

----------------------------------------------------------------------
-- Поимка
----------------------------------------------------------------------
Config.Catch = {
	PerfectWindow = 0.12, -- ±секунд
	GoodWindow = 0.26,
	RodWindowStepPerfect = 0.01, -- за каждые 5 уровней громоотвода
	RodWindowStepGood = 0.012,
	MaxPerfectWindow = 0.17,
	MaxGoodWindow = 0.32,
	PerfectMult = 2,
	GoodMult = 1,
	RingRadius = 7, -- радиус кольца (стадов)
	PositionTolerance = 4.5, -- допуск сервера на позицию
	LatencyGrace = 0.6, -- сколько ждать нажатие после удара (пинг)
	MaxTapAge = 1.2, -- нажатие старше этого (по серверному времени) отбрасывается
	MaxCalibration = 0.15, -- поправка задержки касания в настройках, ±с
	ComboStep = 0.08,
	ComboCap = 25,
	ComboTimeout = 7,
	ZapStun = 0.6, -- оглушение при «Шарахнуло»
	ZapVisual = 1.2,
	ShimmerChance = 0.05, -- кольцо "переливается" в более редкий цвет
	ChainWindow = 0.6, -- цепная молния: поимки в пределах этого времени
	ChainDistance = 30,
	ChainBonus = 0.25,
	MinSpawnDistance = 6,
	MaxSpawnDistance = 34,
	MinRingGap = 3, -- между краями колец
	FirstStrikeDelay = 2,
	FirstStrikeWarning = 3.2,
	RunnerSpeed = 7, -- стадов/с (базовая скорость бега 18)
	MaxCatchRequestsPerSecond = 8,
	ShardPickupRadius = 7,
	ShardLifetime = 25,
}

----------------------------------------------------------------------
-- Перегрузка банки
----------------------------------------------------------------------
Config.Overcharge = {
	MaxFill = 1.5,
	BaseRisk = 0.05,
	ExtraRisk = 0.30, -- добавляется линейно от 100% до 150%
	BurstKeep = 0.5, -- сколько заряда остаётся после "лопнула"
	SellBonus = 1.5, -- заряд сверх 100% при сдаче
}

----------------------------------------------------------------------
-- Улучшения
----------------------------------------------------------------------
export type UpgradeId = "Rod" | "Jar" | "Boots" | "Insulation" | "Magnet"

export type UpgradeDef = {
	Id: UpgradeId,
	Name: string,
	Icon: string,
	Desc: string,
	MaxLevel: number,
	BaseCost: number,
	Growth: number,
	Order: number,
}

Config.UpgradeOrder = { "Rod", "Jar", "Boots", "Magnet", "Insulation" } :: { UpgradeId }

Config.Upgrades = {
	Rod = { Id = "Rod", Name = "Громоотвод", Icon = "🔱", Desc = "Больше заряда за молнию, шире окно ИДЕАЛЬНО", MaxLevel = 30, BaseCost = 10, Growth = 1.62, Order = 1 },
	Jar = { Id = "Jar", Name = "Банка", Icon = "🫙", Desc = "Больше заряда помещается в банку", MaxLevel = 30, BaseCost = 14, Growth = 1.6, Order = 2 },
	Boots = { Id = "Boots", Name = "Сапоги-скороходы", Icon = "👟", Desc = "Быстрее бегаешь между кольцами", MaxLevel = 12, BaseCost = 40, Growth = 2.35, Order = 3 },
	Magnet = { Id = "Magnet", Name = "Грозовой магнит", Icon = "🧲", Desc = "Молнии бьют чаще; больше колец сразу", MaxLevel = 15, BaseCost = 90, Growth = 2.05, Order = 4 },
	Insulation = { Id = "Insulation", Name = "Изоляция", Icon = "🧤", Desc = "Меньше риск перегрузки и короче удар током", MaxLevel = 8, BaseCost = 2500, Growth = 3.1, Order = 5 },
} :: { [UpgradeId]: UpgradeDef }

Config.UpgradeEffects = {
	RodAddPerLevel = 0.3, -- заряд ×(1 + 0.3 × уровень)
	JarBase = 25,
	JarGrowth = 1.5,
	BootsBase = 18,
	BootsPerLevel = 1,
	MagnetRatePerLevel = 0.06,
	MagnetExtraRingLevels = { 5, 10, 15 },
	InsulationRiskPerLevel = 0.07,
	InsulationStunPerLevel = 0.05,
}

Config.Drone = { Cost = 30000, FromZone = 3, TripTime = 5, Name = "Тесла-дрон", Desc = "Сам сдаёт банку, когда она полная" }

----------------------------------------------------------------------
-- Перезапуск генератора (перерождение)
----------------------------------------------------------------------
Config.Rebirth = {
	RequiredZone = 4,
	BaseCost = 8000000,
	CostGrowth = 4,
	MultPerRebirth = 0.5,
	PetSlotsAt = { 2, 5 },
	BasePetSlots = 3,
}

----------------------------------------------------------------------
-- Множители
----------------------------------------------------------------------
Config.Multipliers = {
	FriendBonus = 0.1,
	FriendBonusMax = 0.3,
	IndexRowBonus = 0.1,
	CityBoost = 2,
	CityBoostDuration = 300,
	SupercellCharge = 2,
	SupercellRate = 2,
}

----------------------------------------------------------------------
-- События сервера
----------------------------------------------------------------------
Config.Events = {
	Supercell = { Period = 540, Offset = 240, Duration = 60, GoldBoost = 3 },
	BallLightning = { Period = 960, Offset = 600, Duration = 90, HitInterval = 2.4, HpPerPlayer = 6, RingRadius = 10, Warning = 2.4 },
	Rainbow = { Period = 2400, Offset = 1500, Announce = 10, Warning = 6, RingRadius = 18, RewardMinutes = 6 },
	Perun = { Zone = 5, Chance = 1 / 6000, Warning = 3.0, WitnessMinutes = 1, WitnessRadius = 140 },
	WarnBefore = 30, -- за сколько секунд предупреждать о событии
}

Config.City = {
	PointsBase = 12,
	PointsPerPlayer = 6,
	Districts = 6,
	DecayDelay = 60, -- после буста город гаснет постепенно
}

----------------------------------------------------------------------
-- Удержание
----------------------------------------------------------------------
Config.Offline = { Share = 0.25, MaxSeconds = 8 * 3600, MinSeconds = 120 }

-- Календарь: Kind = "volts" (минут дохода), "shards", "cocoon", "boost" (минут ×2), "pet"
Config.DailyRewards = {
	{ Kind = "volts", Amount = 3, Shards = 20 },
	{ Kind = "volts", Amount = 5, Shards = 30 },
	{ Kind = "cocoon", Cocoon = "meadow" },
	{ Kind = "volts", Amount = 8, Shards = 60 },
	{ Kind = "boost", Amount = 15 },
	{ Kind = "volts", Amount = 12, Shards = 120 },
	{ Kind = "pet", Pet = "gromik" },
} :: { { Kind: string, Amount: number?, Shards: number?, Cocoon: string?, Pet: string? } }

Config.Codes = {
	["МОЛНИЯ"] = { Kind = "shards", Amount = 50 },
	["ПЕРУН"] = { Kind = "boost", Amount = 10 },
	["ГРОЗА"] = { Kind = "cocoon", Cocoon = "meadow" },
} :: { [string]: { Kind: string, Amount: number?, Cocoon: string? } }

Config.MinIncomePerMinute = 30 -- нижняя граница "дохода в минуту" для наград

----------------------------------------------------------------------
-- Сервер: частоты проверок, лимиты и допуски (сам баланс — выше)
----------------------------------------------------------------------
Config.Server = {
	SyncInterval = 0.15, -- DataSync не чаще раза в столько секунд (частые изменения склеиваются)
	RequestRate = 10, -- запросов Request в секунду на игрока
	RequestBurst = 12, -- столько запросов можно подряд, дальше — по RequestRate
	ZoneTick = 0.25, -- как часто проверять зону, барьеры и падение
	GatePushBack = 8, -- на сколько стадов отбросить назад от барьера закрытого острова
	GateSideSlack = 6, -- запас к ширине моста при проверке барьера
	GateNotifyEvery = 2, -- не чаще этого напоминать «Остров закрыт»
	NametagDistance = 60, -- с какого расстояния видна табличка над головой
	SellTick = 0.25, -- как часто проверять игроков на подстанциях
	SellCooldown = 1, -- пауза между сдачами банки
	SellPadSlack = 1.5, -- допуск к радиусу подстанции
	SellPadHeight = 10, -- допуск по высоте над подстанцией
	DroneIdle = 2, -- на островах с перегрузкой дрон вылетает, если столько секунд не было поимок
	IncomeWindow = 60, -- доход в минуту считаем окнами по столько секунд
	JarFullNotifyEvery = 6, -- не чаще этого напоминать «Банка полна!»
	StrikeTick = 0.1, -- шаг цикла ударов
	SpawnTries = 14, -- попыток найти место для кольца
	SpawnJitter = 0.25, -- разброс интервала между кольцами (±доля)
	SpawnRetry = 0.3, -- через сколько секунд повторить, если место не нашлось
	ZoneEnterDelay = 1, -- пауза перед первым кольцом после входа на остров или появления
	ReachShare = 0.85, -- кольцо должно быть достижимо бегом за эту долю предупреждения
	MoveSlack = 0.15, -- допуск позиции при поимке: скорость бега × столько секунд
	CatchHeight = 16, -- допуск по высоте между игроком и кольцом
	GroundProbe = 40, -- луч ищет землю, начиная с этой высоты над поверхностью острова
	GroundStep = 12, -- кольцо не ставим, если земля выше/ниже поверхности острова больше чем на столько
	GroundMinNormalY = 0.7, -- и если склон круче (нормаль.Y меньше)
	FirstStrikeAhead = 6, -- первое кольцо новичка — столько стадов перед ним
	ShimmerAt = 0.5, -- на какой доле предупреждения «переливающееся» кольцо меняет цвет
	RunnerMinShare = 0.6, -- бегущее кольцо проходит 60–100% максимального пути
	MaxShards = 40, -- осколков на земле у одного игрока одновременно
	ShardPickupSlack = 3, -- допуск к радиусу сбора осколка
	ShardCollectRate = 20, -- ShardCollect в секунду на игрока
	ShardScatter = 2, -- осколки нескольких ударов одного кольца раскладываются в этом радиусе
}

----------------------------------------------------------------------
-- Студия
----------------------------------------------------------------------
Config.StudioStartingVolts = 0 -- можно поставить больше для тестов в Studio

return Config
