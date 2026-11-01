--!strict
-- QueueService (P40): fair monster selection (SPEC §1.5) on top of the pure Shared/Round/QueueMath.
-- Weights live in Profile.MonsterChance / RoundsSinceMonster / RolePreference (DataService) with an
-- in-memory mirror (used alone when DataService is missing or a profile is not loaded yet).
-- Publishes every player's chance to be picked next as the Player attribute "MonsterChance" (0..1);
-- this service is the ONLY writer of that attribute.
--
-- API (SPEC §17)
--   ChooseMonster(players) -> Player?        weighted/pity draw; the chosen player's weight resets NOW
--                                            (so leaving right after being picked cannot keep the weight)
--   Chances() -> {[userId]: number}          current share per player (0..1)
--   RecordRound(monsterPlayer?, humanPlayers, stats)   stats = {rows = {RoundStatRow}, mvpUserId = number?}
--                                            (a plain list of rows is accepted too)
--   SetPreference(player, pref) -> boolean   "Either" | "Monster" | "Human"
--   Refresh()                                recompute + publish shares
-- Requests registered: "SetRolePref" (data: pref string or {pref = string}).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local QueueMath = require(Shared:WaitForChild("Round"):WaitForChild("QueueMath")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any

local QueueService = {}
QueueService.Priority = 40

type MemoryEntry = { Weight: number, Rounds: number, Pref: string }

local DataService: any = nil
local RequestService: any = nil

local memory: { [number]: MemoryEntry } = {}
local lastShares: { [number]: number } = {}
local random = Random.new()

local VALID_PREFS: { [string]: boolean } = { Either = true, Monster = true, Human = true }

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function getProfile(player: Player): any
	if DataService and type(DataService.Get) == "function" then
		local ok, profile = pcall(DataService.Get, player)
		if ok and type(profile) == "table" then
			return profile
		end
	end
	return nil
end

local function updateProfile(player: Player, fn: (any) -> ())
	if DataService and type(DataService.Update) == "function" and getProfile(player) ~= nil then
		local ok, err = pcall(DataService.Update, player, fn)
		if not ok then
			warn("[QueueService] DataService.Update failed: " .. tostring(err))
		end
	end
end

-- Current entry of a player (profile values win over the in-memory mirror once loaded).
local function entryFor(player: Player): MemoryEntry
	local mem = memory[player.UserId]
	if mem == nil then
		mem = { Weight = Config.Queue.BaseWeight, Rounds = 0, Pref = "Either" }
		memory[player.UserId] = mem
	end
	local profile = getProfile(player)
	if profile then
		if type(profile.MonsterChance) == "number" then
			mem.Weight = profile.MonsterChance
		end
		if type(profile.RoundsSinceMonster) == "number" then
			mem.Rounds = profile.RoundsSinceMonster
		end
		if type(profile.RolePreference) == "string" and VALID_PREFS[profile.RolePreference] then
			mem.Pref = profile.RolePreference
		end
	else
		local pref = player:GetAttribute("RolePreference")
		if type(pref) == "string" and VALID_PREFS[pref] then
			mem.Pref = pref
		end
	end
	return mem
end

local function write(player: Player, weight: number, rounds: number)
	local mem = entryFor(player)
	mem.Weight = weight
	mem.Rounds = rounds
	updateProfile(player, function(profile: any)
		profile.MonsterChance = weight
		profile.RoundsSinceMonster = rounds
	end)
end

local function entries(players: { Player }): { any }
	local list = {}
	for _, player in players do
		local e = entryFor(player)
		table.insert(list, {
			Id = player.UserId,
			Weight = e.Weight,
			RoundsSinceMonster = e.Rounds,
			Preference = e.Pref,
		})
	end
	return list
end

function QueueService.Refresh()
	local players = Players:GetPlayers()
	local shares = QueueMath.Shares(entries(players))
	lastShares = {}
	for _, player in players do
		local share = shares[player.UserId] or 0
		lastShares[player.UserId] = share
		-- round to 0.1 % so the attribute does not churn
		local rounded = math.floor(share * 1000 + 0.5) / 1000
		if player:GetAttribute("MonsterChance") ~= rounded then
			player:SetAttribute("MonsterChance", rounded)
		end
	end
end

function QueueService.Chances(): { [number]: number }
	return table.clone(lastShares)
end

function QueueService.ChooseMonster(players: { Player }): Player?
	local present: { Player } = {}
	for _, p in players do
		if typeof(p) == "Instance" and p:IsA("Player") and p.Parent ~= nil then
			table.insert(present, p)
		end
	end
	if #present == 0 then
		return nil
	end
	local id = QueueMath.Choose(entries(present), random:NextNumber())
	local chosen: Player? = nil
	for _, p in present do
		if p.UserId == id then
			chosen = p
			break
		end
	end
	if chosen == nil then
		chosen = present[random:NextInteger(1, #present)]
	end
	local picked = chosen :: Player
	write(picked, Config.Queue.BaseWeight, 0)
	QueueService.Refresh()
	return picked
end

function QueueService.RecordRound(monsterPlayer: Player?, humanPlayers: { Player }, stats: any)
	local rows: { any } = {}
	local mvp: number? = nil
	if type(stats) == "table" then
		if type(stats.rows) == "table" then
			rows = stats.rows
			mvp = if type(stats.mvpUserId) == "number" then stats.mvpUserId else nil
		elseif #stats > 0 then
			rows = stats
		end
	end
	local damageBy: { [number]: number } = {}
	for _, row in rows do
		if type(row) == "table" and type(row.userId) == "number" then
			damageBy[row.userId] = (damageBy[row.userId] or 0) + (tonumber(row.damage) or 0)
		end
	end
	if monsterPlayer and monsterPlayer.Parent then
		write(monsterPlayer, Config.Queue.BaseWeight, 0)
	end
	for _, player in humanPlayers do
		if player.Parent and player ~= monsterPlayer then
			local e = entryFor(player)
			local result = {
				WasMonster = false,
				Participated = true,
				Damage = damageBy[player.UserId] or 0,
				WasMvp = mvp ~= nil and mvp == player.UserId,
			}
			write(player, QueueMath.NextWeight(e.Weight, result), QueueMath.NextRounds(e.Rounds, result))
		end
	end
	QueueService.Refresh()
end

function QueueService.SetPreference(player: Player, pref: string): boolean
	if not VALID_PREFS[pref] then
		return false
	end
	local mem = entryFor(player)
	mem.Pref = pref
	updateProfile(player, function(profile: any)
		profile.RolePreference = pref
	end)
	player:SetAttribute("RolePreference", pref)
	QueueService.Refresh()
	return true
end

local function onSetRolePref(player: Player, data: any): (boolean, string?)
	local pref: any = data
	if type(data) == "table" then
		pref = data.pref
	end
	if type(pref) ~= "string" or not VALID_PREFS[pref] then
		return false, "round.queue.prefInvalid"
	end
	QueueService.SetPreference(player, pref)
	local label = Strings.L("role." .. string.lower(pref))
	pcall(Net.Server.Fire, "Notify", player, "round.queue.prefSet", { label }, "Info")
	return true, nil
end

function QueueService.Init()
	DataService = tryService("DataService")
	RequestService = tryService("RequestService")
	if RequestService and type(RequestService.Register) == "function" then
		local ok, err = pcall(RequestService.Register, "SetRolePref", onSetRolePref)
		if not ok then
			warn("[QueueService] SetRolePref registration failed: " .. tostring(err))
		end
	end
end

function QueueService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.defer(QueueService.Refresh)
		task.spawn(function()
			if DataService and type(DataService.WaitFor) == "function" then
				pcall(DataService.WaitFor, player, 10)
			end
			QueueService.Refresh()
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		memory[player.UserId] = nil
		task.defer(QueueService.Refresh)
	end)
	if DataService and type(DataService.Loaded) == "table" and type(DataService.Loaded.Connect) == "function" then
		DataService.Loaded:Connect(function()
			QueueService.Refresh()
		end)
	end
	-- periodic refresh keeps the lobby HUD honest (profile edits, preference changes, joins)
	task.spawn(function()
		while true do
			local ok, err = pcall(QueueService.Refresh)
			if not ok then
				warn("[QueueService] refresh: " .. tostring(err))
			end
			task.wait(3)
		end
	end)
end

return QueueService
