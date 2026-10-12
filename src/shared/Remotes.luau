--!strict
-- Сетевые события (созданы заранее в default.project.json → ReplicatedStorage/Remotes).
--
-- Клиент → сервер:
--   Ready(ready: boolean)                      — готовность в лобби
--   VoteDifficulty(id: string)                 — голос за сложность
--   VoteSkipAlert()                            — пропустить оповещение
--   Interact(kind: string, id: string)         — Door | Window | Light | Hide | Unhide | Tree | Shop | Fusebox | Phone | Revive | Lock
--   SellApples()                               — продать все яблоки отряда
--   UseItem(slot: number, aim: CFrame?)        — применить предмет из слота (aim: куда/откуда — для ловушек и оружия)
--   DropItem(slot: number)                     — выбросить предмет на пол
--   SetFlashlight(on: boolean)
--   SetCrouch(on: boolean)
--   SetSprint(on: boolean)                     — сервер валидирует скорость сам, это подсказка для шума/выносливости
--   HoldBreath(on: boolean)
--   LookingAt(inmateId: string, looking: boolean) — для «Still One»
--   SaveSettings(settings: table)
--   BuyItem(itemId: string) → (ok, message)   RemoteFunction
--   BuyPerk(perkId: string) → (ok, message)   RemoteFunction
-- Сервер → клиент:
--   State(snapshot: StateSnapshot)
--   Alert(inmateIds: {string})
--   Inventory(slots: {InventorySlot?}, flashlightBattery: number)
--   PlayerState(status: string, hideId: string?)  — Alive | Downed | Taken | Hiding | Spectating | Lobby
--   Breath(value: number)
--   InmateEvent(kind: string, inmateId: string, position: Vector3)  — Spotted | Lost | Knock | Chase | Retreat | Stun | Enter | Look | Caught
--   Noise(position: Vector3, radius: number)  — UnreliableRemoteEvent, только для звука/визуала
--   Notify(key: string, kind: string, args: table?)
--   Data(profile: ProfileSnapshot)
--   Result(summary: ResultSummary)
--   FX(kind: string, params: table?)           — Stinger | Shake | Flicker | Blackout | Dawn | Caught | Revived
--   LightsChanged(room: string, on: boolean)
--   Leaderboard(rows: {{Name: string, Nights: number}})

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type InventorySlot = {
	ItemId: string,
	Count: number,
	Charges: number,
}

export type StateSnapshot = {
	Phase: string, -- Lobby | Countdown | Day | Alert | Night | Dawn | Results
	Night: number,
	Nights: number,
	Difficulty: string,
	PhaseEnds: number, -- workspace:GetServerTimeNow() момент конца фазы
	PhaseLength: number,
	Cash: number,
	Apples: number, -- яблок в карманах отряда (непроданных)
	Trees: number,
	Inmates: { string },
	Alive: number,
	Players: number,
	Ready: number,
	Votes: { [string]: number },
	SkipVotes: number,
	Upgrades: { [string]: number },
	Prices: { [string]: number },
}

export type ProfileSnapshot = {
	Amber: number,
	Xp: number,
	Level: number,
	Title: string,
	Perks: { [string]: number },
	NightsSurvived: number,
	Wins: number,
	BestNights: number,
	Settings: { [string]: any },
}

export type ResultSummary = {
	Won: boolean,
	Night: number,
	Nights: number,
	Difficulty: string,
	AmberEarned: number,
	XpEarned: number,
	Survivors: { string },
}

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

local Remotes = {
	Ready = event("Ready"),
	VoteDifficulty = event("VoteDifficulty"),
	VoteSkipAlert = event("VoteSkipAlert"),
	Interact = event("Interact"),
	SellApples = event("SellApples"),
	UseItem = event("UseItem"),
	DropItem = event("DropItem"),
	SetFlashlight = event("SetFlashlight"),
	SetCrouch = event("SetCrouch"),
	SetSprint = event("SetSprint"),
	HoldBreath = event("HoldBreath"),
	LookingAt = event("LookingAt"),
	SaveSettings = event("SaveSettings"),
	BuyItem = folder:WaitForChild("BuyItem") :: RemoteFunction,
	BuyPerk = folder:WaitForChild("BuyPerk") :: RemoteFunction,
	State = event("State"),
	Alert = event("Alert"),
	Inventory = event("Inventory"),
	PlayerState = event("PlayerState"),
	Breath = event("Breath"),
	InmateEvent = event("InmateEvent"),
	Noise = folder:WaitForChild("Noise") :: UnreliableRemoteEvent,
	Notify = event("Notify"),
	Data = event("Data"),
	Result = event("Result"),
	FX = event("FX"),
	LightsChanged = event("LightsChanged"),
	Leaderboard = event("Leaderboard"),
}

return Remotes
