--!strict
-- QuestService (P73): 3 quests per 12-hour UTC window (pure rules: Shared/Progression/Quests).
-- * Window rollover on load, every CHECK_INTERVAL s and before every claim/reroll: completed-but-unclaimed
--   quests of the old window are auto-claimed (never lost), then a new deterministic list is generated
--   (no monster quests when RolePreference == "Human"). Notify "prog.notify.questsNew" / "questAutoClaimed".
-- * StatsService.StatEvent(player, stat, amount, practice) progress is buffered per player and flushed at most
--   every FLUSH_INTERVAL s (one profile update instead of one per hit). Role = Player attribute "Role"
--   (fallback: character Team). Completing a quest -> Notify "prog.notify.questComplete" {quest text}.
-- * Round-end progress: RewardService calls Flush(player) and ApplyRound(profile, player, ctx) inside its
--   update, so the "Rewards" packet carries every quest change of the round.
--
-- API: Claim(player, index?, questId?) -> (ok, errKey?)     RequestService "ClaimQuest"
--      Reroll(player, index?, questId?) -> (ok, errKey?)    RequestService "RerollQuest" (once per window)
--      Flush(player) -> {Change}                            apply buffered stat progress now
--      ApplyRound(profile, player, ctx) -> {Change}          mutates (call inside DataService.Update)
--      Announce(player, changes)                            completion toasts
--      Refresh(player) -> boolean                           roll the window over if needed
--      Summary(changes) -> {{id, key, progress, goal, param, completed}}   for RoundEvent "Rewards"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Quests = require(Shared:WaitForChild("Progression"):WaitForChild("Quests")) :: any
local Rewards = require(Shared:WaitForChild("Progression"):WaitForChild("Rewards")) :: any

local QuestService = {}
QuestService.Priority = 73

local FLUSH_INTERVAL = 1.5
local CHECK_INTERVAL = 30

local DataService: any = nil
local StatsService: any = nil
local CharacterService: any = nil
local RequestService: any = nil

type Pending = {
	Role: string,
	Practice: boolean,
	Stats: { [string]: number },
	Events: { { Stat: string, Amount: number } },
}

local pending: { [Player]: Pending } = {}
local flushQueued: { [Player]: boolean } = {}

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

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

local function textFor(player: Player, key: string, ...: any): string
	local args = table.pack(...)
	local base = key
	if RequestService and type(RequestService.TextFor) == "function" then
		local ok, s = pcall(RequestService.TextFor, player, key)
		if ok and type(s) == "string" then
			base = s
		end
	end
	return (
		string.gsub(base, "{(%d+)}", function(index: string): string?
			local i = tonumber(index)
			if i and i <= args.n then
				return tostring(args[i])
			end
			return nil
		end)
	)
end

local function questText(player: Player, state: any): string
	local t = Quests.Get(state.Id)
	return textFor(player, Quests.TextKey(state.Id), state.Goal, if t and t.Param then t.Param else "")
end

local function opts(profile: any): { [string]: any }
	return { NoMonster = profile.RolePreference == "Human" }
end

local function roleOf(player: Player): string
	local role = player:GetAttribute("Role")
	if role == "Human" or role == "Monster" then
		return role
	end
	if CharacterService and type(CharacterService.GetModel) == "function" then
		local ok, model = pcall(CharacterService.GetModel, player)
		if ok and model then
			local team = model:GetAttribute("Team")
			if team == "Monster" then
				return "Monster"
			elseif team == "Humans" then
				return "Human"
			end
		end
	end
	return "Human"
end

local function window(): number
	return Quests.Window(os.time())
end

-- Grants the rewards of a list of quest states (mutates the profile). Returns total exp, gold.
local function grantStates(profile: any, states: { any }): (number, number)
	local exp, gold = 0, 0
	for _, state in states do
		local e, g = Quests.Claim(state)
		if e and g then
			exp += e
			gold += g
			profile.Stats.QuestsDone = (profile.Stats.QuestsDone or 0) + 1
		end
	end
	if exp > 0 or gold > 0 then
		Rewards.Grant(profile, exp, gold)
	end
	return exp, gold
end

function QuestService.Refresh(player: Player): boolean
	if DataService == nil then
		return false
	end
	local profile = DataService.Get(player)
	if profile == nil then
		return false
	end
	local w = window()
	if profile.Quests.Window == w and #profile.Quests.List > 0 then
		return false
	end
	local hadQuests = #profile.Quests.List > 0
	local autoExp, autoGold = 0, 0
	DataService.Update(player, function(p: any)
		local leftovers = Quests.Refresh(p.Quests, player.UserId, w, opts(p))
		if leftovers and #leftovers > 0 then
			autoExp, autoGold = grantStates(p, leftovers)
		end
	end)
	if autoExp > 0 or autoGold > 0 then
		notify(player, "prog.notify.questAutoClaimed", { autoExp, autoGold }, "Reward")
	end
	if hadQuests then
		notify(player, "prog.notify.questsNew", nil, "Info")
	end
	return true
end

function QuestService.Summary(changes: { any }): { any }
	local out = {}
	local seen: { [string]: number } = {}
	for _, change in changes do
		local t = Quests.Get(change.Id)
		local entry = {
			id = change.Id,
			key = Quests.TextKey(change.Id),
			progress = change.Progress,
			goal = change.Goal,
			param = if t then t.Param else nil,
			completed = change.Completed,
		}
		local at = seen[change.Id]
		if at then
			entry.completed = entry.completed or out[at].completed
			out[at] = entry
		else
			table.insert(out, entry)
			seen[change.Id] = #out
		end
	end
	return out
end

function QuestService.Announce(player: Player, changes: { any })
	local profile = if DataService then DataService.Get(player) else nil
	for _, change in changes do
		if change.Completed then
			local state = { Id = change.Id, Goal = change.Goal }
			if profile then
				for _, s in profile.Quests.List do
					if s.Id == change.Id then
						state = s
					end
				end
			end
			notify(player, "prog.notify.questComplete", { questText(player, state) }, "Reward")
		end
	end
end

local function hasStatQuest(profile: any, stat: string): boolean
	for _, state in profile.Quests.List do
		local t = Quests.Get(state.Id)
		if t and t.Stat == stat and not state.Claimed and state.Progress < state.Goal then
			return true
		end
	end
	return false
end

function QuestService.Flush(player: Player): { any }
	local buffer = pending[player]
	pending[player] = nil
	if buffer == nil or DataService == nil or DataService.Get(player) == nil then
		return {}
	end
	local changes: { any } = {}
	DataService.Update(player, function(p: any)
		for _, event in buffer.Events do
			for _, change in Quests.TrackStat(p.Quests.List, event.Stat, event.Amount, buffer.Role, buffer.Practice) do
				table.insert(changes, change)
			end
		end
		for stat, amount in buffer.Stats do
			for _, change in Quests.TrackStat(p.Quests.List, stat, amount, buffer.Role, buffer.Practice) do
				table.insert(changes, change)
			end
		end
	end)
	return changes
end

local function scheduleFlush(player: Player)
	if flushQueued[player] then
		return
	end
	flushQueued[player] = true
	task.delay(FLUSH_INTERVAL, function()
		flushQueued[player] = nil
		if player.Parent then
			QuestService.Announce(player, QuestService.Flush(player))
		end
	end)
end

local function onStatEvent(player: Player, stat: string, amount: number, practice: boolean?)
	if DataService == nil or type(stat) ~= "string" or type(amount) ~= "number" then
		return
	end
	local profile = DataService.Get(player)
	if profile == nil then
		return
	end
	if profile.Quests.Window ~= window() then
		QuestService.Refresh(player)
		profile = DataService.Get(player)
	end
	if profile == nil or not hasStatQuest(profile, stat) then
		return
	end
	local role = roleOf(player)
	local isPractice = practice == true
	local buffer = pending[player]
	if buffer and (buffer.Role ~= role or buffer.Practice ~= isPractice) then
		QuestService.Announce(player, QuestService.Flush(player))
		buffer = nil
	end
	if buffer == nil then
		buffer = { Role = role, Practice = isPractice, Stats = {}, Events = {} }
		pending[player] = buffer
	end
	local t = nil
	for _, state in profile.Quests.List do
		local def = Quests.Get(state.Id)
		if def and def.Stat == stat and def.PerEvent then
			t = def
		end
	end
	if t then
		-- per-event quests need every event separately (amount threshold per event)
		table.insert(buffer.Events, { Stat = stat, Amount = amount })
	else
		buffer.Stats[stat] = (buffer.Stats[stat] or 0) + amount
	end
	scheduleFlush(player)
end

function QuestService.ApplyRound(profile: any, player: Player, ctx: any): { any }
	if profile.Quests.Window ~= window() then
		local leftovers = Quests.Refresh(profile.Quests, player.UserId, window(), opts(profile))
		if leftovers and #leftovers > 0 then
			grantStates(profile, leftovers)
		end
	end
	return Quests.TrackRound(profile.Quests.List, ctx)
end

local function findIndex(profile: any, index: number?, questId: string?): number?
	if index then
		return if profile.Quests.List[index] then index else nil
	end
	for i, state in profile.Quests.List do
		if state.Id == questId then
			return i
		end
	end
	return nil
end

function QuestService.Claim(player: Player, index: number?, questId: string?): (boolean, string?)
	if DataService == nil or DataService.Get(player) == nil then
		return false, "prog.err.notReady"
	end
	if QuestService.Refresh(player) then
		return false, "prog.err.questExpired"
	end
	QuestService.Flush(player)
	local profile = DataService.Get(player)
	local i = findIndex(profile, index, questId)
	if i == nil then
		return false, "prog.err.questInvalid"
	end
	local state = profile.Quests.List[i]
	if state.Claimed then
		return false, "prog.err.questClaimed"
	end
	if not Quests.IsComplete(state) then
		return false, "prog.err.questNotDone"
	end
	local exp, gold = 0, 0
	local grant: any = nil
	DataService.Update(player, function(p: any)
		local s = p.Quests.List[i]
		local e, g = Quests.Claim(s)
		if e and g then
			exp, gold = e, g
			p.Stats.QuestsDone = (p.Stats.QuestsDone or 0) + 1
			grant = Rewards.Grant(p, e, g)
		end
	end)
	notify(player, "prog.notify.questClaimed", { exp, gold }, "Reward")
	if grant and grant.LevelsGained > 0 then
		notify(player, "prog.notify.levelUp", { grant.NewLevel, grant.LevelGold }, "Reward")
	end
	return true
end

function QuestService.Reroll(player: Player, index: number?, questId: string?): (boolean, string?)
	if DataService == nil or DataService.Get(player) == nil then
		return false, "prog.err.notReady"
	end
	if QuestService.Refresh(player) then
		return false, "prog.err.questExpired"
	end
	QuestService.Flush(player)
	local profile = DataService.Get(player)
	local i = findIndex(profile, index, questId)
	if i == nil then
		return false, "prog.err.questInvalid"
	end
	local ok, errKey = false, nil
	DataService.Update(player, function(p: any)
		ok, errKey = Quests.Reroll(p.Quests, i, player.UserId, window(), opts(p))
	end)
	if not ok then
		return false, errKey
	end
	notify(player, "prog.notify.rerolled", nil, "Info")
	return true
end

function QuestService.Init()
	DataService = tryService("DataService")
	StatsService = tryService("StatsService")
	CharacterService = tryService("CharacterService")
	RequestService = tryService("RequestService")
end

function QuestService.Start()
	if DataService then
		DataService.Loaded:Connect(function(player: Player)
			QuestService.Refresh(player)
		end)
		-- keep the progress of the last seconds: Releasing fires right before the final save
		DataService.Releasing:Connect(function(player: Player)
			pcall(QuestService.Flush, player)
		end)
	end
	if StatsService and type(StatsService.StatEvent) == "table" then
		StatsService.StatEvent:Connect(function(player: Player, stat: string, amount: number, practice: boolean?)
			local ok, err = pcall(onStatEvent, player, stat, amount, practice)
			if not ok then
				warn("[QuestService] stat event: " .. tostring(err))
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			pending[player] = nil
			flushQueued[player] = nil
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(QuestService.Refresh, player)
				if not ok then
					warn("[QuestService] refresh: " .. tostring(err))
				end
			end
		end
	end)
end

return QuestService
