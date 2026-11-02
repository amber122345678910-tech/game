--!strict
-- StateController (client, SPEC §20, Priority 8): the single source of replicated game state for UI and controllers.
-- Wraps ReplicatedStorage.RoundState attributes, the local Player's attributes, Net "RoundEvent" / "Notify" /
-- "Profile" (+ "GetProfile" once on Start), ReplicatedStorage.Leaderboards (if present), the local character,
-- and player settings (profile Settings -> Config.Defaults fallback, with optimistic local SetSetting).
--
-- API (SPEC §20)
--   StateController.Round() -> {[attr]: any}          live RoundState snapshot (read-only by convention)
--   StateController.RoundChanged: Signal(attr, value) (fired for every attribute once when RoundState binds)
--   StateController.Phase() -> string ; TimeLeft() -> number (s, >= 0) ; Now() -> number (server time)
--   StateController.Profile() -> ProfileView? ; ProfileChanged: Signal(profile)
--   StateController.OnRoundEvent(name, fn(data)) -> Connection ; RoundEvent: Signal(name, data)
--   StateController.Notify: Signal(key, args, style)
--   StateController.LocalCharacter() -> Model? ; CharacterChanged: Signal(model?)
--   StateController.Role() -> "Lobby"|"Human"|"Monster"|"Spectator" ; RoleChanged: Signal(role)
--   StateController.Request(action, data)              Net "Request"
--   StateController.Leaderboards() -> { Wins: {{name, value}}, Level: {{name, value}} } ; LeaderboardsChanged: Signal()
--   StateController.KitOf(model) -> KitDef? ; IsEnemy(model) -> boolean ; IsAlly(model) -> boolean
-- Extras
--   StateController.PlayerAttr(name) -> any ; PlayerChanged: Signal(attr, value)
--   StateController.LocalTeam() -> string ("" if none) ; LocalKit() -> KitDef? ; IsAlive(model?) -> boolean
--   StateController.Setting(key, default?) -> any      profile.Settings[key] ?? local pending value ?? Config.Defaults[key] ?? default
--   StateController.SetSetting(key, value)              optimistic + Request("SetSetting", {key = key, value = value})
--   StateController.SettingChanged: Signal(key, value)
--   StateController.RoundStateInstance() -> Instance?
--   StateController.LastCombatRole() -> string?        "Human"/"Monster" of the last round the player fought in
-- Leaderboards contract: ReplicatedStorage.Leaderboards (any Instance) with either
--   * child StringValue "<Board>" whose Value = JSON [{rank, userId, name, value}] (LeaderboardService), or
--   * attribute "<Board>" = JSON string of [{name, value}] / [{Name, Value}], or
--   * child "<Board>" whose children carry attributes Name (string) and Value (number), sorted by attribute Rank
--     (else by Value descending).  Boards read: "Wins", "Level".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Kits = require(Shared:WaitForChild("Kits"))
local Types = require(Shared:WaitForChild("Types"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams"))

type KitDef = Types.KitDef
type ProfileView = Types.ProfileView

local StateController = {}
StateController.Priority = 8

StateController.RoundChanged = Signal.new()
StateController.ProfileChanged = Signal.new()
StateController.RoundEvent = Signal.new()
StateController.Notify = Signal.new()
StateController.CharacterChanged = Signal.new()
StateController.RoleChanged = Signal.new()
StateController.PlayerChanged = Signal.new()
StateController.SettingChanged = Signal.new()
StateController.LeaderboardsChanged = Signal.new()

StateController.BOARDS = { "Wins", "Level" }

local round: { [string]: any } = {}
local roundState: Instance? = nil
local profile: ProfileView? = nil
local pendingSettings: { [string]: any } = {}
local character: Model? = nil
local roundEventSignals: { [string]: any } = {}
local leaderboards: { [string]: { { name: string, value: number } } } = { Wins = {}, Level = {} }
local lastCombatRole: string? = nil
local started = false

------------------------------------------------------------------------------------------------ time

function StateController.Now(): number
	return workspace:GetServerTimeNow()
end

------------------------------------------------------------------------------------------- round state

function StateController.Round(): { [string]: any }
	return round
end

function StateController.RoundStateInstance(): Instance?
	return roundState
end

function StateController.Phase(): string
	local phase = round.Phase
	return if type(phase) == "string" and phase ~= "" then phase else "Waiting"
end

function StateController.TimeLeft(): number
	local endsAt = round.PhaseEndsAt
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - StateController.Now())
end

local function bindRoundState(instance: Instance)
	if roundState == instance then
		return
	end
	roundState = instance
	table.clear(round)
	for name, value in instance:GetAttributes() do
		round[name] = value
	end
	instance.AttributeChanged:Connect(function(name: string)
		local value = instance:GetAttribute(name)
		round[name] = value
		StateController.RoundChanged:Fire(name, value)
	end)
	for name, value in round do
		StateController.RoundChanged:Fire(name, value)
	end
end

local function watchRoundState()
	local existing = ReplicatedStorage:FindFirstChild("RoundState")
	if existing then
		bindRoundState(existing)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "RoundState" then
			bindRoundState(child)
		end
	end)
end

------------------------------------------------------------------------------------------- round events

function StateController.OnRoundEvent(name: string, fn: (any) -> ()): any
	local signal = roundEventSignals[name]
	if signal == nil then
		signal = Signal.new()
		roundEventSignals[name] = signal
	end
	return signal:Connect(fn)
end

local function onRoundEvent(name: any, data: any)
	if type(name) ~= "string" then
		return
	end
	if name == "PhaseChanged" and type(data) == "table" then
		-- keep the snapshot fresh even before the attribute replicates
		if type(data.phase) == "string" then
			round.Phase = data.phase
		end
		if type(data.endsAt) == "number" then
			round.PhaseEndsAt = data.endsAt
		end
	end
	StateController.RoundEvent:Fire(name, data)
	local signal = roundEventSignals[name]
	if signal then
		signal:Fire(data)
	end
end

----------------------------------------------------------------------------------------------- profile

function StateController.Profile(): ProfileView?
	return profile
end

local function settingsOf(p: ProfileView?): { [string]: any }
	if p and type(p.Settings) == "table" then
		return p.Settings
	end
	return {}
end

local function setProfile(newProfile: any)
	if type(newProfile) ~= "table" then
		return
	end
	local oldSettings = settingsOf(profile)
	profile = newProfile :: ProfileView
	local newSettings = settingsOf(profile)
	-- drop pending values the server confirmed (or overrode)
	for key in pendingSettings do
		if newSettings[key] ~= nil then
			pendingSettings[key] = nil
		end
	end
	StateController.ProfileChanged:Fire(profile)
	local changed: { [string]: boolean } = {}
	for key, value in newSettings do
		if oldSettings[key] ~= value then
			changed[key] = true
		end
	end
	for key in oldSettings do
		if newSettings[key] == nil then
			changed[key] = true
		end
	end
	for key in changed do
		StateController.SettingChanged:Fire(key, StateController.Setting(key))
	end
end

function StateController.Setting(key: string, default: any?): any
	local value = settingsOf(profile)[key]
	if value ~= nil then
		return value
	end
	value = pendingSettings[key]
	if value ~= nil then
		return value
	end
	value = (Config.Defaults :: any)[key]
	if value ~= nil then
		return value
	end
	return default
end

function StateController.SetSetting(key: string, value: any)
	if type(key) ~= "string" then
		return
	end
	pendingSettings[key] = value
	-- reflect locally right away (the server answers with a full "Profile")
	local p = profile
	if p and type(p.Settings) == "table" then
		p.Settings[key] = value
	end
	StateController.SettingChanged:Fire(key, value)
	StateController.Request("SetSetting", { key = key, value = value })
end

------------------------------------------------------------------------------------------- local player

local function localPlayer(): Player?
	return Players.LocalPlayer
end

function StateController.LocalCharacter(): Model?
	if character and character.Parent == nil then
		return nil
	end
	return character
end

function StateController.PlayerAttr(name: string): any
	local player = localPlayer()
	return if player then player:GetAttribute(name) else nil
end

function StateController.Role(): string
	local role = StateController.PlayerAttr("Role")
	return if type(role) == "string" and role ~= "" then role else "Lobby"
end

function StateController.LastCombatRole(): string?
	return lastCombatRole
end

function StateController.LocalTeam(): string
	return Teams.TeamOf(StateController.LocalCharacter())
end

function StateController.KitOf(model: Instance?): KitDef?
	if model == nil then
		return nil
	end
	local kitId = model:GetAttribute("KitId")
	if type(kitId) ~= "string" or kitId == "" then
		return nil
	end
	return Kits.Get(kitId)
end

function StateController.LocalKit(): KitDef?
	return StateController.KitOf(StateController.LocalCharacter())
end

function StateController.IsEnemy(model: Instance?): boolean
	return Teams.AreEnemies(StateController.LocalCharacter(), model)
end

function StateController.IsAlly(model: Instance?): boolean
	return Teams.AreAllies(StateController.LocalCharacter(), model)
end

function StateController.IsAlive(model: Instance?): boolean
	local m = if model ~= nil then model else StateController.LocalCharacter()
	if m == nil or m.Parent == nil then
		return false
	end
	if m:GetAttribute("Dead") == true then
		return false
	end
	local humanoid = m:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function StateController.Request(action: string, data: any?)
	local ok, err = pcall(Net.Client.Fire, "Request", action, data)
	if not ok then
		warn("[StateController] Request " .. tostring(action) .. " failed: " .. tostring(err))
	end
end

local function setCharacter(model: Model?)
	if character == model then
		return
	end
	character = model
	StateController.CharacterChanged:Fire(model)
end

local function watchPlayer()
	local player = localPlayer()
	if player == nil then
		return
	end
	if player.Character then
		setCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(model: Model)
		setCharacter(model)
	end)
	player.CharacterRemoving:Connect(function(model: Model)
		if character == model then
			setCharacter(nil)
		end
	end)
	local role = StateController.Role()
	if role == "Human" or role == "Monster" then
		lastCombatRole = role
	end
	player.AttributeChanged:Connect(function(name: string)
		local value = player:GetAttribute(name)
		StateController.PlayerChanged:Fire(name, value)
		if name == "Role" then
			local newRole = StateController.Role()
			if newRole == "Human" or newRole == "Monster" then
				lastCombatRole = newRole
			end
			StateController.RoleChanged:Fire(newRole)
		end
	end)
end

------------------------------------------------------------------------------------------- leaderboards

type Row = { name: string, value: number }

local function rowsFromJson(text: string): { Row }?
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local rows: { Row } = {}
	for _, entry in decoded do
		if type(entry) == "table" then
			local name = entry.name or entry.Name
			local value = tonumber(entry.value or entry.Value)
			if type(name) == "string" and value then
				table.insert(rows, { name = name, value = value })
			end
		end
	end
	return rows
end

local function rowsFromChildren(folder: Instance): { Row }
	local entries = {}
	for _, child in folder:GetChildren() do
		local name = child:GetAttribute("Name")
		local value = tonumber(child:GetAttribute("Value"))
		if type(name) == "string" and value then
			local rank = tonumber(child:GetAttribute("Rank")) or math.huge
			table.insert(entries, { name = name, value = value, rank = rank })
		end
	end
	table.sort(entries, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.value > b.value
	end)
	local rows: { Row } = {}
	for _, e in entries do
		table.insert(rows, { name = e.name, value = e.value })
	end
	return rows
end

local function readLeaderboards()
	local root = ReplicatedStorage:FindFirstChild("Leaderboards")
	if root == nil then
		return
	end
	for _, board in StateController.BOARDS do
		local rows: { Row }? = nil
		local attr = root:GetAttribute(board)
		if type(attr) == "string" and attr ~= "" then
			rows = rowsFromJson(attr)
		end
		if rows == nil then
			local child = root:FindFirstChild(board)
			if child and child:IsA("StringValue") then
				-- LeaderboardService format: StringValue "<Board>".Value = JSON [{rank, userId, name, value}]
				rows = rowsFromJson(child.Value)
			elseif child then
				rows = rowsFromChildren(child)
			end
		end
		leaderboards[board] = rows or {}
	end
	StateController.LeaderboardsChanged:Fire()
end

function StateController.Leaderboards(): { [string]: { { name: string, value: number } } }
	return leaderboards
end

local function watchLeaderboards()
	local scheduled = false
	local function schedule()
		if scheduled then
			return
		end
		scheduled = true
		task.delay(0.25, function()
			scheduled = false
			readLeaderboards()
		end)
	end
	local function bind(root: Instance)
		readLeaderboards()
		root.AttributeChanged:Connect(schedule)
		root.DescendantAdded:Connect(schedule)
		root.DescendantRemoving:Connect(schedule)
		-- entry attribute edits (Value/Rank) do not fire DescendantAdded: poll lightly as a safety net
		task.spawn(function()
			while root.Parent ~= nil do
				task.wait(15)
				schedule()
			end
		end)
	end
	local existing = ReplicatedStorage:FindFirstChild("Leaderboards")
	if existing then
		bind(existing)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Leaderboards" then
			bind(child)
		end
	end)
end

------------------------------------------------------------------------------------------------ lifecycle

function StateController.Init() end

function StateController.Start()
	if started then
		return
	end
	started = true
	watchRoundState()
	watchPlayer()
	watchLeaderboards()
	-- remotes: WaitForChild may yield until the server created them; keep it off the main Start path
	task.spawn(function()
		Net.Client.On("RoundEvent", onRoundEvent)
		Net.Client.On("Notify", function(key: any, args: any, style: any)
			if type(key) == "string" then
				StateController.Notify:Fire(key, if type(args) == "table" then args else nil, style)
			end
		end)
		Net.Client.On("Profile", setProfile)
	end)
	task.spawn(function()
		local ok, result = pcall(Net.Client.Invoke, "GetProfile")
		if ok and type(result) == "table" and profile == nil then
			setProfile(result)
		elseif not ok then
			warn("[StateController] GetProfile failed: " .. tostring(result))
		end
	end)
end

return StateController
