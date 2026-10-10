--!strict
-- Конфиг игры: блоки, сетка участка, параметры шторма, экономика.
-- Все балансные числа живут здесь, чтобы их было легко менять в одном месте.

export type BlockCategory = "Blocks" | "Doors" | "Terrain"

export type BlockDef = {
	Id: string,
	Name: string,
	Description: string,
	Category: BlockCategory,
	Order: number,
	HP: number,
	Price: number,
	-- Множитель урона от кислоты (дождь + лужа). Металл разъедается сильнее.
	AcidMult: number,
	-- Доля урона от града, которая передаётся игроку, стоящему под этим блоком.
	HailTransfer: number,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	Reflectance: number,
	-- Двери: высота 2 клетки, Seal = сколько стадов кислоты дверь сдерживает.
	IsDoor: boolean,
	Seal: number,
	HeightCells: number,
	-- Земля под участком: не ломается бедствиями, копается в режиме удаления.
	Indestructible: boolean?,
}

export type StormParams = {
	Level: number,
	HailRate: number, -- градин в секунду над всем участком
	HailDamage: number, -- урон блоку от одной градины
	HailBigChance: number,
	HailBigMult: number,
	HailPlayerDamage: number, -- урон игроку при прямом попадании
	HailHitRadius: number, -- радиус попадания по игроку (стады)
	AcidRainDps: number, -- урон в секунду верхним открытым блокам (умножается на AcidMult)
	AcidRainPlayerDps: number, -- урон игроку под открытым небом во время кислотного дождя
	PoolMax: number, -- максимальный уровень кислоты снаружи (стады от пола участка)
	PoolRiseTime: number, -- за сколько секунд лужа достигает максимума
	PoolDps: number, -- урон в секунду затопленным внешним блокам (умножается на AcidMult)
	PoolPlayerDps: number, -- урон игроку в кислоте снаружи
	InsidePlayerDps: number, -- урон игроку в кислоте внутри бункера
	WindDps: number, -- ураган: урон блокам с наветренной стороны (лёгкие материалы — больше)
	WindPlayerDps: number, -- ураган: урон игроку под открытым небом
	MeteorRate: number, -- метеоритов в секунду
	MeteorDamage: number, -- урон верхнему блоку (ниже и вокруг — меньше)
	MeteorPlayerDamage: number,
	QuakeDps: number, -- землетрясение: урон наземным блокам (высокие — больше)
	BaseReward: number,
}

local Config = {}

Config.DataVersion = 1
Config.DataStoreName = "BunkerSimulator_v1"

-- Сетка постройки (локальные координаты участка). Клетка = куб 4x4x4.
Config.Grid = {
	CellSize = 4,
	Width = 12, -- X
	Depth = 12, -- Z (индекс 0 = передняя сторона, обращённая к лобби)
	Height = 13, -- Y: 3 слоя под землёй + 10 над землёй
	Underground = 3, -- слоёв земли под поверхностью участка (можно копать)
}

-- Геометрия участка-котлована (локальные координаты, начало = центр пола котлована).
-- Локальная -Z = "перед" участка (смотрит на лобби).
Config.Plot = {
	PitHalfSize = 32, -- котлован 64x64 стадов
	PitDepth = 14, -- глубина котлована (кислота поднимается максимум почти до края)
	ZoneTop = 60, -- высота зоны участка над полом
	ZoneMargin = 2, -- небольшой допуск зоны по краям
}

Config.MaxPlayers = 8

Config.Build = {
	MaxActionsPerSecond = 14,
	BurstActions = 20,
	MaxPlaceDistance = 300, -- от персонажа до клетки (стады)
	SaveDebounce = 3, -- через сколько секунд после изменения постройки записываем раскладку в профиль
}

Config.Economy = {
	StartingCoins = 100,
	-- Для тестов в Roblox Studio: столько монет у нового игрока, чтобы сразу проверить магазин.
	-- Поставь 100, чтобы проверить экономику как у обычного игрока.
	StudioStartingCoins = 5000,
	PrefabDiscount = 0.85,
	MaxBuyAmount = 100,
	MaxLevel = 100,
}

Config.Blocks = {
	wood = {
		Id = "wood",
		Name = "Деревянные доски",
		Description = "Дёшево, но слабо. Кислота разъедает средне.",
		Category = "Blocks",
		Order = 1,
		HP = 60,
		Price = 3,
		AcidMult = 1.0,
		HailTransfer = 0.3,
		Color = Color3.fromRGB(163, 112, 67),
		Material = Enum.Material.WoodPlanks,
		Transparency = 0,
		Reflectance = 0,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	glass = {
		Id = "glass",
		Name = "Бронестекло",
		Description = "Хрупкое, зато кислота его не берёт.",
		Category = "Blocks",
		Order = 2,
		HP = 45,
		Price = 6,
		AcidMult = 0,
		HailTransfer = 0.35,
		Color = Color3.fromRGB(170, 222, 255),
		-- не Glass: за материалом Glass не рисуются частицы и прозрачные детали
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.45,
		Reflectance = 0.15,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	stone = {
		Id = "stone",
		Name = "Каменный кирпич",
		Description = "Надёжный и устойчивый к кислоте.",
		Category = "Blocks",
		Order = 3,
		HP = 150,
		Price = 8,
		AcidMult = 0.6,
		HailTransfer = 0.15,
		Color = Color3.fromRGB(138, 138, 142),
		Material = Enum.Material.Cobblestone,
		Transparency = 0,
		Reflectance = 0,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	metal = {
		Id = "metal",
		Name = "Листовой металл",
		Description = "Крепкий против града, но кислота его разъедает!",
		Category = "Blocks",
		Order = 4,
		HP = 240,
		Price = 18,
		AcidMult = 2.5,
		HailTransfer = 0.1,
		Color = Color3.fromRGB(168, 172, 178),
		Material = Enum.Material.DiamondPlate,
		Transparency = 0,
		Reflectance = 0.05,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	concrete = {
		Id = "concrete",
		Name = "Бетон",
		Description = "Тяжёлый бетон. Отлично держит кислоту.",
		Category = "Blocks",
		Order = 5,
		HP = 360,
		Price = 30,
		AcidMult = 0.45,
		HailTransfer = 0.06,
		Color = Color3.fromRGB(196, 196, 190),
		Material = Enum.Material.Concrete,
		Transparency = 0,
		Reflectance = 0,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	steel = {
		Id = "steel",
		Name = "Армированная сталь",
		Description = "Очень прочная, но кислота её подтачивает.",
		Category = "Blocks",
		Order = 6,
		HP = 600,
		Price = 70,
		AcidMult = 1.8,
		HailTransfer = 0.03,
		Color = Color3.fromRGB(92, 98, 108),
		Material = Enum.Material.Metal,
		Transparency = 0,
		Reflectance = 0.1,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	titan = {
		Id = "titan",
		Name = "Титановый сплав",
		Description = "Лучший материал: прочный и почти не боится кислоты.",
		Category = "Blocks",
		Order = 7,
		HP = 1000,
		Price = 160,
		AcidMult = 0.25,
		HailTransfer = 0,
		Color = Color3.fromRGB(118, 150, 196),
		Material = Enum.Material.Metal,
		Transparency = 0,
		Reflectance = 0.15,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
	},
	door_wood = {
		Id = "door_wood",
		Name = "Деревянная дверь",
		Description = "Держит до 3 стадов кислоты, потом начинает течь.",
		Category = "Doors",
		Order = 10,
		HP = 90,
		Price = 15,
		AcidMult = 1.0,
		HailTransfer = 0.2,
		Color = Color3.fromRGB(124, 84, 52),
		Material = Enum.Material.Wood,
		Transparency = 0,
		Reflectance = 0,
		IsDoor = true,
		Seal = 3.5,
		HeightCells = 2,
	},
	door_iron = {
		Id = "door_iron",
		Name = "Железная дверь",
		Description = "Держит до 7 стадов кислоты.",
		Category = "Doors",
		Order = 11,
		HP = 300,
		Price = 90,
		AcidMult = 1.5,
		HailTransfer = 0.08,
		Color = Color3.fromRGB(110, 114, 122),
		Material = Enum.Material.DiamondPlate,
		Transparency = 0,
		Reflectance = 0.05,
		IsDoor = true,
		Seal = 7,
		HeightCells = 2,
	},
	door_blast = {
		Id = "door_blast",
		Name = "Гермодверь",
		Description = "Герметичная дверь бункера. Держит 13.5 стадов кислоты.",
		Category = "Doors",
		Order = 12,
		HP = 900,
		Price = 400,
		AcidMult = 0.3,
		HailTransfer = 0,
		Color = Color3.fromRGB(214, 170, 52),
		Material = Enum.Material.Metal,
		Transparency = 0,
		Reflectance = 0.1,
		IsDoor = true,
		Seal = 13.5,
		HeightCells = 2,
	},
	-- Земля под участком (не продаётся, не в инвентаре)
	dirt = {
		Id = "dirt",
		Name = "Земля",
		Description = "Копается в режиме удаления.",
		Category = "Terrain",
		Order = 100,
		HP = 1e6,
		Price = 0,
		AcidMult = 0,
		HailTransfer = 0,
		Color = Color3.fromRGB(110, 82, 56),
		Material = Enum.Material.Ground,
		Transparency = 0,
		Reflectance = 0,
		IsDoor = false,
		Seal = 0,
		HeightCells = 1,
		Indestructible = true,
	},
} :: { [string]: BlockDef }

-- Порядок отображения в магазине и в хотбаре (без земли).
Config.BlockOrder = {} :: { string }
do
	local ids = {}
	for id, def in Config.Blocks do
		if def.Category ~= "Terrain" then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return Config.Blocks[a].Order < Config.Blocks[b].Order
	end)
	Config.BlockOrder = ids
end

function Config.getBlock(id: any): BlockDef?
	if typeof(id) ~= "string" then
		return nil
	end
	return Config.Blocks[id]
end

-- Тайминги фаз шторма (секунды).
Config.Storm = {
	PrepTime = 5,
	HailTime = 30,
	WindTime = 18,
	MeteorTime = 15,
	CalmTime = 4,
	AcidTime = 50,
	QuakeTime = 14,
	ClearTime = 6,
	FallTime = 0.6, -- время падения градины (визуал и задержка урона совпадают)
	MeteorFallTime = 1.4,
	MeteorRadius = 7, -- радиус поражения игрока метеоритом
	HailSpawnHeight = 80, -- над полом котлована (визуал)
	SimStep = 0.25, -- шаг симуляции кислоты
	LeaveGrace = 5, -- сколько секунд можно быть вне участка до провала
	DoorLeakFactor = 0.06, -- стадов/сек на каждый стад превышения Seal
	BreachRate = 1.6, -- стадов/сек, если в затопленной части бункера дыра
	RoofLeakRate = 0.05, -- стадов/сек, если в крыше дыра во время кислотного дождя
	RoofLeakCap = 0.2, -- через крышу натечёт не больше PoolMax * RoofLeakCap
	InsideDamageDepth = 1.5, -- урон внутри начинается, когда кислоты по колено
	HailTremorRadius = 7, -- удары града по крыше в этом радиусе частично достаются игроку
	DrainRate = 2.5, -- стадов/сек, скорость ухода кислоты в фазе Clear
	QuakeDrainRate = 0.5, -- во время землетрясения лужа уходит медленно (и продолжает затекать)
}

-- Фазы шторма (значения атрибута Phase у участка).
Config.Phases = {
	None = "",
	Prep = "Prep",
	Hail = "Hail",
	Calm = "Calm",
	Acid = "Acid",
	Clear = "Clear",
	Wind = "Wind",
	Meteor = "Meteor",
	Quake = "Quake",
}

-- Дополнительные бедствия: чем выше уровень, тем больше их в одном шторме.
Config.ExtraDisasters = { "Wind", "Meteor", "Quake" }
function Config.extraDisasterCount(level: number): number
	return math.clamp(1 + (math.floor(level) - 1) // 3, 1, 3)
end

Config.PhaseNames = {
	Prep = "Шторм приближается",
	Hail = "Град!",
	Calm = "Затишье...",
	Acid = "Кислотный дождь!",
	Clear = "Шторм уходит",
	Wind = "Ураган!",
	Meteor = "Метеоритный дождь!",
	Quake = "Землетрясение!",
} :: { [string]: string }

function Config.stormParams(level: number): StormParams
	local n = math.clamp(math.floor(level), 1, Config.Economy.MaxLevel)
	return {
		Level = n,
		HailRate = math.min(10 + n * 1.6, 45),
		HailDamage = 5 + n * 1.4,
		HailBigChance = math.min(0.1 + n * 0.012, 0.3),
		HailBigMult = 3,
		HailPlayerDamage = 8 + n,
		HailHitRadius = 2.5,
		AcidRainDps = 0.35 + n * 0.16,
		AcidRainPlayerDps = 6 + n * 0.6,
		PoolMax = math.min(1.4 + n * 1.2, Config.Plot.PitDepth - 1),
		PoolRiseTime = 32,
		PoolDps = 0.35 + n * 0.13,
		PoolPlayerDps = 15 + n,
		InsidePlayerDps = 8 + n * 0.6,
		WindDps = 0.5 + n * 0.45,
		WindPlayerDps = 4 + n * 0.6,
		MeteorRate = 0.2 + n * 0.06,
		MeteorDamage = 15 + n * 9,
		MeteorPlayerDamage = 30 + n * 3,
		QuakeDps = 0.6 + n * 0.45,
		BaseReward = 80 + n * 35,
	}
end

-- Награда за шторм.
-- survived: выжил ли игрок; bunkerFrac: доля оставшегося HP бункера (0..1);
-- progress: доля пройденного шторма (0..1), используется при поражении.
function Config.computeReward(level: number, survived: boolean, bunkerFrac: number, progress: number): number
	local p = Config.stormParams(level)
	if survived then
		return math.floor(p.BaseReward * (0.6 + 0.4 * math.clamp(bunkerFrac, 0, 1)))
	end
	return math.floor(p.BaseReward * 0.4 * math.clamp(progress, 0, 1))
end

-- Цвет кислоты (клиентские детали луж и эффекты).
Config.AcidColor = Color3.fromRGB(105, 225, 50)
Config.AcidTransparency = 0.3

return Config
