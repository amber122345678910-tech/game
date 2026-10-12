--!strict
-- Единое клиентское состояние: принимает события сервера и раздаёт их модулям через сигналы.
-- UI и контроллеры читают отсюда и никогда не слушают Remotes напрямую (кроме Noise для звука).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))

local ClientState = {}

export type StateSnapshot = Remotes.StateSnapshot
export type ProfileSnapshot = Remotes.ProfileSnapshot
export type InventorySlot = Remotes.InventorySlot

ClientState.Snapshot = {
	Phase = "Lobby",
	Night = 0,
	Nights = 0,
	Difficulty = Config.DefaultDifficulty,
	PhaseEnds = 0,
	PhaseLength = 0,
	Cash = 0,
	Apples = 0,
	Trees = 0,
	Inmates = {},
	Alive = 0,
	Players = 0,
	Ready = 0,
	Votes = {},
	SkipVotes = 0,
	Upgrades = {},
	Prices = {},
} :: StateSnapshot

ClientState.Profile = {
	Amber = 0,
	Xp = 0,
	Level = 0,
	Title = "Newcomer",
	Perks = {},
	NightsSurvived = 0,
	Wins = 0,
	BestNights = 0,
	Settings = {},
} :: ProfileSnapshot

ClientState.Inventory = {} :: { InventorySlot? }
ClientState.Battery = Config.Flashlight.Battery
ClientState.Status = "Lobby" -- Alive | Downed | Taken | Hiding | Spectating | Lobby
ClientState.HideId = nil :: string?
ClientState.Breath = Config.Hiding.BreathMax
ClientState.SelectedSlot = 1
ClientState.FlashlightOn = false
ClientState.Crouching = false
ClientState.Settings = {
	Brightness = 0.5,
	Music = 0.8,
	Sfx = 1,
	HeadBob = true,
	Vhs = true,
} :: { [string]: any }

ClientState.StateChanged = Signal.new() :: Signal.Signal<StateSnapshot>
ClientState.ProfileChanged = Signal.new() :: Signal.Signal<ProfileSnapshot>
ClientState.InventoryChanged = Signal.new() :: Signal.Signal<{ InventorySlot? }, number>
ClientState.StatusChanged = Signal.new() :: Signal.Signal<string, string?>
ClientState.BreathChanged = Signal.new() :: Signal.Signal<number>
ClientState.Notified = Signal.new() :: Signal.Signal<string, string, { any }?>
ClientState.AlertReceived = Signal.new() :: Signal.Signal<{ string }>
ClientState.InmateEvent = Signal.new() :: Signal.Signal<string, string, Vector3>
ClientState.FXEvent = Signal.new() :: Signal.Signal<string, { [string]: any }?>
ClientState.LightsChanged = Signal.new() :: Signal.Signal<string, boolean>
ClientState.ResultReceived = Signal.new() :: Signal.Signal<Remotes.ResultSummary>
ClientState.LeaderboardChanged = Signal.new() :: Signal.Signal<{ { Name: string, Nights: number } }>
ClientState.SelectedChanged = Signal.new() :: Signal.Signal<number>
ClientState.FlashlightChanged = Signal.new() :: Signal.Signal<boolean>
ClientState.CrouchChanged = Signal.new() :: Signal.Signal<boolean>
ClientState.SettingsChanged = Signal.new() :: Signal.Signal<{ [string]: any }>

-- Сколько секунд осталось до конца текущей фазы (по серверному времени).
function ClientState.phaseRemaining(): number
	return math.max(0, ClientState.Snapshot.PhaseEnds - workspace:GetServerTimeNow())
end

-- Игровые часы для HUD: день 07:00→21:00, ночь 21:00→06:00, рассвет 06:00→07:00.
function ClientState.clockHour(): number
	local s = ClientState.Snapshot
	local len = math.max(1, s.PhaseLength)
	local progress = 1 - math.clamp(ClientState.phaseRemaining() / len, 0, 1)
	if s.Phase == "Day" then
		return Config.Clock.DayStartHour + progress * (Config.Clock.NightStartHour - Config.Clock.DayStartHour)
	elseif s.Phase == "Alert" then
		return Config.Clock.NightStartHour
	elseif s.Phase == "Night" then
		return (Config.Clock.NightStartHour + progress * (24 - Config.Clock.NightStartHour + Config.Clock.DawnHour)) % 24
	elseif s.Phase == "Dawn" then
		return Config.Clock.DawnHour + progress
	end
	return Config.Clock.DayStartHour
end

function ClientState.clockText(): string
	local h = ClientState.clockHour()
	local hour = math.floor(h) % 24
	local minute = math.floor((h - math.floor(h)) * 60)
	local suffix = if hour >= 12 then "PM" else "AM"
	local h12 = hour % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, minute, suffix)
end

function ClientState.isNight(): boolean
	local p = ClientState.Snapshot.Phase
	return p == "Night" or p == "Alert"
end

function ClientState.inMatch(): boolean
	local p = ClientState.Snapshot.Phase
	return p == "Day" or p == "Alert" or p == "Night" or p == "Dawn"
end

function ClientState.selectSlot(slot: number)
	slot = math.clamp(slot, 1, Config.InventorySlots)
	if ClientState.SelectedSlot ~= slot then
		ClientState.SelectedSlot = slot
		ClientState.SelectedChanged:Fire(slot)
	end
end

function ClientState.selectedItem(): InventorySlot?
	return ClientState.Inventory[ClientState.SelectedSlot]
end

function ClientState.setFlashlight(on: boolean)
	if ClientState.FlashlightOn ~= on then
		ClientState.FlashlightOn = on
		ClientState.FlashlightChanged:Fire(on)
		Remotes.SetFlashlight:FireServer(on)
	end
end

function ClientState.setCrouch(on: boolean)
	if ClientState.Crouching ~= on then
		ClientState.Crouching = on
		ClientState.CrouchChanged:Fire(on)
		Remotes.SetCrouch:FireServer(on)
	end
end

function ClientState.setSetting(key: string, value: any)
	ClientState.Settings[key] = value
	ClientState.SettingsChanged:Fire(ClientState.Settings)
end

function ClientState.saveSettings()
	Remotes.SaveSettings:FireServer(ClientState.Settings)
end

function ClientState.init()
	Locale.setLanguage(Players.LocalPlayer.LocaleId)

	Remotes.State.OnClientEvent:Connect(function(snapshot: StateSnapshot)
		ClientState.Snapshot = snapshot
		ClientState.StateChanged:Fire(snapshot)
	end)
	Remotes.Data.OnClientEvent:Connect(function(profile: ProfileSnapshot)
		ClientState.Profile = profile
		if typeof(profile.Settings) == "table" then
			for k, v in profile.Settings do
				ClientState.Settings[k] = v
			end
			ClientState.SettingsChanged:Fire(ClientState.Settings)
		end
		ClientState.ProfileChanged:Fire(profile)
	end)
	Remotes.Inventory.OnClientEvent:Connect(function(slots: { InventorySlot? }, battery: number)
		ClientState.Inventory = slots
		ClientState.Battery = battery
		ClientState.InventoryChanged:Fire(slots, battery)
	end)
	Remotes.PlayerState.OnClientEvent:Connect(function(status: string, hideId: string?)
		ClientState.Status = status
		ClientState.HideId = hideId
		if status ~= "Alive" then
			ClientState.FlashlightOn = false
			ClientState.FlashlightChanged:Fire(false)
			ClientState.Crouching = false
			ClientState.CrouchChanged:Fire(false)
		end
		ClientState.StatusChanged:Fire(status, hideId)
	end)
	Remotes.Breath.OnClientEvent:Connect(function(value: number)
		ClientState.Breath = value
		ClientState.BreathChanged:Fire(value)
	end)
	Remotes.Notify.OnClientEvent:Connect(function(key: string, kind: string, args: { any }?)
		ClientState.Notified:Fire(key, kind, args)
	end)
	Remotes.Alert.OnClientEvent:Connect(function(ids: { string })
		ClientState.AlertReceived:Fire(ids)
	end)
	Remotes.InmateEvent.OnClientEvent:Connect(function(kind: string, inmateId: string, position: Vector3)
		ClientState.InmateEvent:Fire(kind, inmateId, position)
	end)
	Remotes.FX.OnClientEvent:Connect(function(kind: string, params: { [string]: any }?)
		ClientState.FXEvent:Fire(kind, params)
	end)
	Remotes.LightsChanged.OnClientEvent:Connect(function(room: string, on: boolean)
		ClientState.LightsChanged:Fire(room, on)
	end)
	Remotes.Result.OnClientEvent:Connect(function(summary: Remotes.ResultSummary)
		ClientState.ResultReceived:Fire(summary)
	end)
	Remotes.Leaderboard.OnClientEvent:Connect(function(rows: { { Name: string, Nights: number } })
		ClientState.LeaderboardChanged:Fire(rows)
	end)
end

return ClientState
