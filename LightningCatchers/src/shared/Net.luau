--!strict
-- Сетевой контракт: имена удалённых событий, форматы сообщений, действия запроса.
-- Сами RemoteEvent/RemoteFunction объявлены в default.project.json (ReplicatedStorage.Remotes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local Net = {}

----------------------------------------------------------------------
-- Сообщения
----------------------------------------------------------------------

-- Сервер → клиент: новое кольцо (личное или общее)
export type StrikeMsg = {
	Id: number,
	Pos: Vector3, -- центр кольца на земле (для бегущего — начальная точка)
	To: Vector3?, -- бегущее кольцо: конечная точка (в момент первого удара)
	Radius: number,
	Color: Config.ColorId, -- итоговый цвет
	Shown: Config.ColorId?, -- цвет в начале (если кольцо "переливается")
	UpgradeAt: number?, -- доля предупреждения, когда цвет меняется на итоговый
	Kind: Config.KindId,
	Spawn: number, -- серверное время появления (workspace:GetServerTimeNow())
	Hits: { number }, -- серверное время каждого удара
	Shared: boolean?, -- общий удар (события): видят все в зоне
	Tag: string?, -- "ball" | "rainbow" | "perun" для особых
	Zone: number,
}

export type Grade = "perfect" | "good" | "miss" | "zap" | "ground" | "burst"

-- Сервер → клиент: итог одного удара
export type StrikeResultMsg = {
	Id: number,
	Hit: number, -- номер удара в кольце (1..)
	Grade: Grade,
	Charge: number, -- добавлено заряда (0, если промах)
	Combo: number,
	Jar: number, -- заряд в банке после этого
	Capacity: number,
	Color: Config.ColorId,
	Pos: Vector3,
	Chain: { number }?, -- UserId игроков, с кем случилась цепная молния
	Fulg: number?, -- Id нового фульгурита (если выпал)
	NewIndex: string?, -- "зона:цвет", если впервые
	Lost: number?, -- сколько заряда потеряно (банка лопнула)
	Final: boolean?, -- последний удар кольца (кольцо можно убрать)
	Zapped: boolean?, -- нажал мимо окна, стоя в кольце: током ударило (Grade = "miss"), это кольцо больше не бьёт
}

-- Сервер → клиенты (ненадёжно): чужая молния для красоты
export type BoltMsg = {
	Pos: Vector3,
	Color: Config.ColorId,
	Seed: number,
	Zone: number,
	Caught: boolean, -- поймана (бьёт в игрока) или в землю
	UserId: number?,
}

-- Сервер → клиент: осколок на земле
export type ShardMsg = {
	Id: number,
	Pos: Vector3,
	Amount: number,
	Expires: number, -- серверное время
}

-- Сервер → клиенты: разовые эффекты
-- Kind: "rainbowWarn" | "perun" | "witness" | "ballBurst" | "zoneUnlocked" | "levelUp" | "hatch" | "cityLit" | "chain" | "sell" | "drone"
--  | "shard" (Value = Id осколка: сервер засчитал его подбор)
--  | "openWindow" (Text = имя окна) | "face" (Pos — куда сервер поставил персонажа лицом к центру острова:
--    клиент ставит камеру за спину, если игрок ещё рядом)
-- "levelUp" и "rebirth" — для справки: празднует окно, которое сделало запрос (по ответу Request)
export type EffectMsg = {
	Kind: string,
	Pos: Vector3?,
	UserId: number?,
	Value: number?,
	Text: string?,
	Zone: number?,
	Targets: { number }?,
}

----------------------------------------------------------------------
-- Запросы клиента (RemoteFunction "Request")
-- Request:InvokeServer(action, payload) -> (ok: boolean, result: any)
-- result при ok=false — текст ошибки для игрока: строка-исходник или Loc.Msg (клиент рисует через Loc.render)
--
-- Тексты для игрока в Notify (text, kind) и Banner (text, kind, color?) — тоже строка-исходник или Loc.Msg:
-- сервер не знает языка игрока, переводит клиент (src/shared/Loc.luau)
----------------------------------------------------------------------
Net.Actions = {
	BuyUpgrade = "BuyUpgrade", -- payload: UpgradeId
	UnlockZone = "UnlockZone", -- payload: zone number
	BuyDrone = "BuyDrone", -- payload: nil
	ToggleDrone = "ToggleDrone", -- payload: boolean
	Rebirth = "Rebirth", -- payload: nil
	Hatch = "Hatch", -- payload: cocoonId -> result: { Kind: string, Id: number }
	EquipPet = "EquipPet", -- payload: pet Id
	UnequipPet = "UnequipPet", -- payload: pet Id
	DeletePet = "DeletePet", -- payload: pet Id
	EquipBest = "EquipBest", -- payload: nil
	EquipFulg = "EquipFulg", -- payload: fulg Id
	UnequipFulg = "UnequipFulg", -- payload: fulg Id
	DeleteFulg = "DeleteFulg", -- payload: fulg Id -> result: shards gained
	ClaimDaily = "ClaimDaily", -- payload: nil -> result: reward description
	ClaimQuest = "ClaimQuest", -- payload: quest index (1..3)
	RedeemCode = "RedeemCode", -- payload: string
	Teleport = "Teleport", -- payload: zone number (0 = хаб)
	SetSettings = "SetSettings", -- payload: { Music, Sfx, SoftFlash, Shake, Offset, Lang }
	ClaimWelcome = "ClaimWelcome", -- payload: nil -> result: volts
	TutorialStep = "TutorialStep", -- payload: string (имя шага)
}

----------------------------------------------------------------------
-- Доступ к объектам
----------------------------------------------------------------------
local remotes: Folder? = nil
local function folder(): Folder
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return remotes :: Folder
end

function Net.event(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return folder():WaitForChild(name) :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	return folder():WaitForChild(name) :: RemoteFunction
end

-- Папка с общим состоянием сервера (атрибуты): создаётся сервером при старте
--  CityPoints, CityTarget, CityLit (0..6), CityBoostUntil (серверное время)
--  Event ("" | "supercell" | "ball" | "rainbow"), EventEnds
--  NextSupercell, NextBall, NextRainbow (серверное время)
--  BallZone, BallHp, BallMaxHp, BallFrom (Vector3), BallTo (Vector3), BallStart, BallEnd
function Net.gameState(): Folder
	return ReplicatedStorage:WaitForChild("GameState") :: Folder
end

-- Атрибуты игрока (Player), которые ставит сервер и читают все клиенты:
--  Zone (0..5), Combo, JarFill (0..1.5), Pets ("iskorka,luchik"), ZappedUntil (серверное время),
--  BestCombo, Rebirths, Title, FriendCount, RodTier (0..5)
Net.PlayerAttrs = {
	Zone = "Zone",
	Combo = "Combo",
	JarFill = "JarFill",
	Pets = "Pets",
	ZappedUntil = "ZappedUntil",
	BestCombo = "BestCombo",
	Rebirths = "Rebirths",
	Title = "Title",
	FriendCount = "FriendCount",
	RodTier = "RodTier",
}

return Net
