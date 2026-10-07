--!strict
-- Доступ к сетевым событиям. Сами объекты созданы заранее в default.project.json
-- (ReplicatedStorage/Remotes), поэтому клиент и сервер видят их сразу.
--
-- Клиент -> сервер:
--   PlaceBlock(blockId: string, x: number, y: number, z: number, rot: number)
--   RemoveBlock(x: number, y: number, z: number)
--   ClearPlot()
--   StartStorm()
--   TutorialDone()
--   Purchase (RemoteFunction): (kind: "block" | "prefab", id: string, amount: number) -> (ok: boolean, message: string)
-- Сервер -> клиент:
--   DataUpdated(snapshot: DataSnapshot)
--   Notify(text: string, kind: "info" | "success" | "error" | "warning")
--   HailBatch (UnreliableRemoteEvent, только визуал): (plotId: number, flat: { number })
--     плоский массив по 4 числа на градину: lx, lz, impactY, big(0/1) — в локальных координатах участка
--   BlockBroken(plotId: number, position: Vector3, color: Color3)
--   StormResult(result: StormResult)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type DataSnapshot = {
	Coins: number,
	Inventory: { [string]: number },
	StormLevel: number,
	BestLevel: number,
	TutorialDone: boolean,
	StarterClaimed: boolean,
	StormsSurvived: number,
	StormsPlayed: number,
}

export type StormResult = {
	Survived: boolean,
	Reward: number,
	Level: number, -- уровень, который проходили
	NewLevel: number, -- текущий уровень после шторма
	BunkerPercent: number, -- 0..100
	Duration: number, -- секунд продержался
	Reason: string, -- "survived" | "died" | "left" | "quit"
}

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

local Remotes = {
	PlaceBlock = event("PlaceBlock"),
	RemoveBlock = event("RemoveBlock"),
	ClearPlot = event("ClearPlot"),
	StartStorm = event("StartStorm"),
	TutorialDone = event("TutorialDone"),
	DataUpdated = event("DataUpdated"),
	Notify = event("Notify"),
	HailBatch = folder:WaitForChild("HailBatch") :: UnreliableRemoteEvent,
	BlockBroken = event("BlockBroken"),
	StormResult = event("StormResult"),
	Purchase = folder:WaitForChild("Purchase") :: RemoteFunction,
}

return Remotes
