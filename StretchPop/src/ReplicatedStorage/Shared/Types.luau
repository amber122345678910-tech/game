--!strict
-- STRETCH-POP · Общие типы клиента и сервера.
-- Профиль игрока хранится в DataStore целиком (см. Shared/Data/ProfileTemplate.luau).

local BuddyConfig = require(script.Parent.Config.BuddyConfig)

export type StatName = "Elasticity" | "SpringPower" | "SmashMass"

-- Уровни физических статов (0 = базовый). Формулы перевода в физику — Shared/Physics/StretchPhysics.
export type PhysicalStats = {
	Elasticity: number, -- дальность захвата + максимальное натяжение резинки (x_max)
	SpringPower: number, -- жёсткость резинки k + упругость пружинного шара
	SmashMass: number, -- ударная масса m в E = ½·m·v² при пробитии
}

-- Прогресс одной локации (у каждого игрока своя полоса и свой тир).
export type LocationProgress = {
	Tier: number, -- 0 Classic → 1 Golden → 2 Cyber-Slime → 3+ Void (множители растут бесконечно)
	Rebirths: number, -- сколько раз в этой локации засчитан удар в Гонг Эволюции
	BestSpeed: number,
	BestCombo: number,
}

export type GloveInventory = {
	Owned: { [string]: boolean }, -- id перчатки → открыта
	Equipped: string,
}

export type LifetimeRecords = {
	TopSpeed: number,
	LongestCombo: number,
	WallsSmashed: number,
	ChestsOpened: number,
	LootEarned: number,
	CapsulesOpened: number,
	PinatasPopped: number,
}

-- Бадди в инвентаре: uid → экземпляр. Equipped — до BuddyConfig.MaxEquipped uid'ов.
export type BuddyInstance = {
	BuddyId: string,
	Mutation: BuddyConfig.Mutation,
	Obtained: number,
}

export type BuddyInventory = {
	Inventory: { [string]: BuddyInstance },
	Equipped: { string },
	NextUid: number,
}

export type PlayerProfile = {
	DataVersion: number,
	Coins: number,
	Stats: PhysicalStats,
	Gloves: GloveInventory,
	Buddies: BuddyInventory,
	Locations: { [string]: LocationProgress },
	ActiveLocation: string,
	TotalRebirths: number,
	Records: LifetimeRecords,
	FirstJoinUnix: number,
	LastJoinUnix: number,
	PlaySeconds: number,
}

export type HandSide = "Left" | "Right"
export type ObstacleKind = "Wall" | "Chest" | "Pinata"

-- Снимок разрушенного препятствия: отправляется всем клиентам для VFX,
-- потому что сама деталь в этот момент уже убрана сервером из Workspace.
export type SmashSnapshot = {
	CFrame: CFrame,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Kind: string,
}

-- Снимок профиля для клиента (ProfileSync): то, чего нет в атрибутах Player —
-- список купленных перчаток, рекорды и прогресс всех локаций.
export type BuddySnapshot = {
	Uid: string,
	BuddyId: string,
	Mutation: BuddyConfig.Mutation,
	Equipped: boolean,
}

export type ProfileSnapshot = {
	Coins: number,
	Stats: PhysicalStats,
	OwnedGloves: { string },
	EquippedGlove: string,
	Buddies: { BuddySnapshot },
	Records: LifetimeRecords,
	Locations: { [string]: LocationProgress },
	ActiveLocation: string,
	TotalRebirths: number,
	DataOffline: boolean,
	ServerTime: number,
}

export type GloveActionKind = "Buy" | "Equip"
export type BuddyActionKind = "Equip" | "Unequip" | "Release" | "Craft"

-- Описание волны перерождения, рассылаемое всем клиентам.
export type RebirthWaveInfo = {
	Slot: number,
	OwnerUserId: number,
	Tier: number,
	LaneOrigin: CFrame,
	OriginZ: number, -- локальная Z полосы, откуда стартует фронт волны (дальний конец)
	EndZ: number, -- локальная Z, где волна гаснет (за стартовой площадкой)
	Speed: number, -- studs/s вдоль полосы
	StartServerTime: number, -- workspace:GetServerTimeNow() момента старта фронта
	LaneWidth: number,
}

return {}
