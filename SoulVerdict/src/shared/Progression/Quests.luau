--!strict
-- Quests: 3 quests per 12-hour UTC window, deterministic from (userId, window) via Util/Rng (SPEC §1.6,
-- genre idea 17). Pure + Lune-safe. Slots: 1 = any role, 2 = human, 3 = monster (60 %) or human
-- (opts.NoMonster -> never a monster quest); at most one hard (Difficulty 3) quest per window.
-- Progress comes from StatsService.StatEvent stats (Stat templates) and from the round result
-- (Round templates, Rewards.RoundContext). Practice rounds only advance templates flagged Practice.
-- Text: "prog.quest.<Id>" with {1} = goal, {2} = Param.
--
--   Quests.Templates() -> {Template}            Quests.Get(id) -> Template?
--   Quests.Window(unixTime) -> number           Quests.WindowEndsAt(window) -> unix time
--   Quests.Generate(userId, window, opts?) -> {QuestState}      opts = {NoMonster: boolean?}
--   Quests.Refresh(quests, userId, window, opts?) -> {QuestState}?
--        rolls quests = profile.Quests over to `window` (new list, Rerolled = false); returns the old
--        completed-but-unclaimed quests (to auto-claim) or nil when the window did not change
--   Quests.Reroll(quests, index, userId, window, opts?) -> (boolean, string?)   once per window
--   Quests.TrackStat(list, stat, amount, role, practice) -> {Change}
--   Quests.TrackRound(list, ctx) -> {Change}
--   Quests.Claim(state) -> (exp, gold)?         marks Claimed; nil when not complete / already claimed
--   Quests.RewardFor(state) -> (exp, gold)      Quests.IsComplete(state) -> boolean
--   Quests.SanitizeList(list) -> {QuestState}   Quests.TextKey(id) -> string
-- Change = { Index, Id, Progress, Goal, Completed (true only when it just reached the goal) }

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Util.Rng)
local Rewards = require(script.Parent.Rewards)

type RoundContext = Rewards.RoundContext
type QuestState = Types.QuestState

export type Template = {
	Id: string,
	Role: string, -- "Any" | "Human" | "Monster"
	Difficulty: number, -- 1 easy, 2 medium, 3 hard
	Goals: { number },
	Param: number?,
	Stat: string?,
	PerEvent: boolean?,
	MinAmount: number?,
	Round: ((ctx: RoundContext, t: Template) -> number)?,
	Practice: boolean?,
	Weight: number,
}

export type Change = { Index: number, Id: string, Progress: number, Goal: number, Completed: boolean }

local Quests = {}

Quests.RewardsByDifficulty = {
	[1] = { Exp = 60, Gold = 40 },
	[2] = { Exp = 90, Gold = 65 },
	[3] = { Exp = 130, Gold = 100 },
} :: { [number]: { Exp: number, Gold: number } }
Quests.GoalStepBonus = 0.25 -- reward bonus per goal step above the smallest goal
Quests.MonsterSlotChance = 0.6

local WINDOW_SECONDS = Config.Quests.WindowHours * 3600

local templates: { Template } = {}
local byId: { [string]: Template } = {}

local function def(t: { [string]: any })
	local entry: Template = {
		Id = t.Id,
		Role = t.Role,
		Difficulty = t.Difficulty,
		Goals = t.Goals,
		Param = t.Param,
		Stat = t.Stat,
		PerEvent = t.PerEvent,
		MinAmount = t.MinAmount,
		Round = t.Round,
		Practice = t.Practice,
		Weight = t.Weight or 1,
	}
	assert(byId[entry.Id] == nil, "duplicate quest " .. entry.Id)
	table.insert(templates, entry)
	byId[entry.Id] = entry
end

local function n(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function real(ctx: RoundContext): boolean
	return not ctx.practice
end

-- Any role ------------------------------------------------------------------------------------------
def({ Id = "PlayRounds", Role = "Any", Difficulty = 1, Goals = { 2, 3, 4 }, Round = function(ctx)
	return if real(ctx) then 1 else 0
end })
def({ Id = "WinRounds", Role = "Any", Difficulty = 2, Goals = { 1, 2, 3 }, Stat = "Win" })
def({ Id = "DealDamage", Role = "Any", Difficulty = 1, Goals = { 800, 1200, 1600 }, Stat = "Damage", Practice = true })
def({ Id = "BeMvp", Role = "Any", Difficulty = 3, Goals = { 1 }, Round = function(ctx)
	return if real(ctx) and ctx.mvp then 1 else 0
end })
def({ Id = "BigRound", Role = "Any", Difficulty = 2, Goals = { 1, 2 }, Param = 500, Round = function(ctx, t)
	return if real(ctx) and n(ctx.row.damage) >= (t.Param or 0) then 1 else 0
end })
def({ Id = "EarnExp", Role = "Any", Difficulty = 1, Goals = { 250, 400, 600 }, Practice = true, Round = function(ctx)
	return n(ctx.exp)
end })
def({ Id = "PracticeRound", Role = "Any", Difficulty = 1, Goals = { 1 }, Practice = true, Weight = 0.6, Round = function(ctx)
	return if ctx.practice then 1 else 0
end })
-- Human ---------------------------------------------------------------------------------------------
def({ Id = "HumanWin", Role = "Human", Difficulty = 2, Goals = { 1, 2, 3 }, Stat = "Win" })
def({ Id = "HumanSurvive", Role = "Human", Difficulty = 1, Goals = { 1, 2, 3 }, Stat = "Survived" })
def({ Id = "Parries", Role = "Human", Difficulty = 1, Goals = { 5, 8, 12 }, Stat = "Parries", Practice = true })
def({ Id = "Saves", Role = "Human", Difficulty = 1, Goals = { 2, 3, 4 }, Stat = "Saves", Practice = true })
def({ Id = "Revives", Role = "Human", Difficulty = 2, Goals = { 2, 3 }, Stat = "Revives", Practice = true })
def({ Id = "Healing", Role = "Human", Difficulty = 1, Goals = { 250, 400, 600 }, Stat = "Healing", Practice = true })
def({ Id = "ForceDodges", Role = "Human", Difficulty = 1, Goals = { 15, 25, 40 }, Stat = "DodgesForced", Practice = true })
def({ Id = "BoxSurvivor", Role = "Human", Difficulty = 2, Goals = { 1, 2, 3 }, Stat = "BoxesSurvived", Practice = true })
def({ Id = "HumanDamage", Role = "Human", Difficulty = 1, Goals = { 400, 700, 1000 }, Stat = "Damage", Practice = true })
def({ Id = "DefeatMonster", Role = "Human", Difficulty = 3, Goals = { 1 }, Round = function(ctx)
	return if real(ctx) and ctx.won and ctx.reason == "Defeated" then 1 else 0
end })
def({ Id = "FinalBlow", Role = "Human", Difficulty = 3, Goals = { 1 }, Stat = "Kills" })
def({ Id = "SurviveCollapse", Role = "Human", Difficulty = 2, Goals = { 1 }, Round = function(ctx)
	return if real(ctx) and ctx.won and ctx.reason == "Survived" and ctx.row.survived then 1 else 0
end })
def({ Id = "ParryRound", Role = "Human", Difficulty = 2, Goals = { 1, 2 }, Param = 3, Practice = true, Round = function(ctx, t)
	return if n(ctx.row.parries) >= (t.Param or 0) then 1 else 0
end })
def({ Id = "TeamPlayer", Role = "Human", Difficulty = 2, Goals = { 1 }, Practice = true, Round = function(ctx)
	return if n(ctx.row.revives) >= 1 and n(ctx.row.saves) >= 1 then 1 else 0
end })
def({ Id = "HealerRound", Role = "Human", Difficulty = 2, Goals = { 1 }, Param = 200, Practice = true, Round = function(ctx, t)
	return if n(ctx.row.healing) >= (t.Param or 0) then 1 else 0
end })
-- Monster -------------------------------------------------------------------------------------------
def({ Id = "MonsterPlay", Role = "Monster", Difficulty = 1, Goals = { 1, 2 }, Round = function(ctx)
	return if real(ctx) then 1 else 0
end })
def({ Id = "MonsterWin", Role = "Monster", Difficulty = 3, Goals = { 1 }, Stat = "Win" })
def({ Id = "MonsterKills", Role = "Monster", Difficulty = 2, Goals = { 3, 5, 8 }, Stat = "Kills", Practice = true })
def({ Id = "MonsterDowns", Role = "Monster", Difficulty = 1, Goals = { 4, 6, 10 }, Stat = "Downs", Practice = true })
def({ Id = "MonsterDamage", Role = "Monster", Difficulty = 1, Goals = { 1000, 1500, 2500 }, Stat = "Damage", Practice = true })
def({ Id = "BoxHits", Role = "Monster", Difficulty = 1, Goals = { 6, 10, 15 }, Stat = "BoxHits", Practice = true })
def({ Id = "BoxCombo", Role = "Monster", Difficulty = 2, Goals = { 1, 2 }, Param = 3, Stat = "BoxHits", PerEvent = true, MinAmount = 3, Practice = true })
def({ Id = "Rampage", Role = "Monster", Difficulty = 2, Goals = { 1 }, Param = 3, Practice = true, Round = function(ctx, t)
	return if n(ctx.row.kills) >= (t.Param or 0) then 1 else 0
end })
def({ Id = "SwiftVerdict", Role = "Monster", Difficulty = 3, Goals = { 1 }, Round = function(ctx)
	return if real(ctx) and ctx.won and ctx.reason == "Eliminated" and not ctx.collapse then 1 else 0
end })
def({ Id = "Unshaken", Role = "Monster", Difficulty = 3, Goals = { 1 }, Round = function(ctx)
	return if real(ctx) and ctx.won and not ctx.finalPhase then 1 else 0
end })

-- API -----------------------------------------------------------------------------------------------

function Quests.Templates(): { Template }
	return templates
end

function Quests.Get(id: string): Template?
	return byId[id]
end

function Quests.TextKey(id: string): string
	return "prog.quest." .. id
end

function Quests.Window(unixTime: number): number
	return math.floor(unixTime / WINDOW_SECONDS)
end

function Quests.WindowEndsAt(window: number): number
	return (window + 1) * WINDOW_SECONDS
end

local function goalIndex(t: Template, goal: number): number
	return table.find(t.Goals, goal) or 1
end

function Quests.RewardFor(state: QuestState): (number, number)
	local t = byId[state.Id]
	if t == nil then
		return 0, 0
	end
	local base = Quests.RewardsByDifficulty[t.Difficulty] or Quests.RewardsByDifficulty[1]
	local mult = 1 + Quests.GoalStepBonus * (goalIndex(t, state.Goal) - 1)
	return math.floor(base.Exp * mult + 0.5), math.floor(base.Gold * mult + 0.5)
end

function Quests.IsComplete(state: QuestState): boolean
	return state.Progress >= state.Goal
end

-- Picks one template for `role` that is not in `taken` (deterministic order + weights).
local function pick(rng: any, role: string, taken: { [string]: boolean }, allowHard: boolean, noMonster: boolean): Template?
	local candidates: { Template } = {}
	local weights: { number } = {}
	for _, t in templates do
		local roleOk = (role == "*" and not (noMonster and t.Role == "Monster")) or t.Role == role
		if roleOk and not taken[t.Id] and (allowHard or t.Difficulty < 3) then
			table.insert(candidates, t)
			table.insert(weights, t.Weight)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local index = rng:WeightedIndex(weights) or 1
	return candidates[index]
end

local function newState(rng: any, t: Template): QuestState
	return { Id = t.Id, Progress = 0, Goal = t.Goals[rng:Integer(1, #t.Goals)], Claimed = false }
end

function Quests.Generate(userId: number, window: number, opts: { [string]: any }?): { QuestState }
	local noMonster = opts ~= nil and opts.NoMonster == true
	local rng = Rng.new(Rng.Hash("SV_Quests", userId, window))
	local slots = { "Any", "Human", "Human" }
	if not noMonster and rng:Bool(Quests.MonsterSlotChance) then
		slots[3] = "Monster"
	end
	local list: { QuestState } = {}
	local taken: { [string]: boolean } = {}
	local hard = false
	for i = 1, math.min(Config.Quests.PerWindow, 8) do
		local role = slots[i] or "*"
		local t = pick(rng, role, taken, not hard, noMonster) or pick(rng, "*", taken, not hard, noMonster)
		if t then
			taken[t.Id] = true
			hard = hard or t.Difficulty >= 3
			table.insert(list, newState(rng, t))
		end
	end
	return list
end

function Quests.Refresh(quests: any, userId: number, window: number, opts: { [string]: any }?): { QuestState }?
	if quests.Window == window and type(quests.List) == "table" and #quests.List > 0 then
		return nil
	end
	local unclaimed: { QuestState } = {}
	if type(quests.List) == "table" and quests.Window ~= window then
		for _, state in quests.List do
			if Quests.IsComplete(state) and not state.Claimed then
				table.insert(unclaimed, state)
			end
		end
	end
	quests.Window = window
	quests.List = Quests.Generate(userId, window, opts)
	quests.Rerolled = false
	return unclaimed
end

function Quests.Reroll(quests: any, index: number, userId: number, window: number, opts: { [string]: any }?): (boolean, string?)
	if quests.Window ~= window then
		return false, "prog.err.questExpired"
	end
	if quests.Rerolled then
		return false, "prog.err.rerollUsed"
	end
	local state = quests.List[index]
	if state == nil then
		return false, "prog.err.questInvalid"
	end
	if state.Claimed or Quests.IsComplete(state) then
		return false, "prog.err.questDone"
	end
	local old = byId[state.Id]
	local noMonster = opts ~= nil and opts.NoMonster == true
	local taken: { [string]: boolean } = {}
	local hardElsewhere = false
	for i, other in quests.List do
		taken[other.Id] = true
		local t = byId[other.Id]
		if i ~= index and t and t.Difficulty >= 3 then
			hardElsewhere = true
		end
	end
	local rng = Rng.new(Rng.Hash("SV_QuestReroll", userId, window, index))
	-- a monster quest is swapped for a non-monster one (the usual reason to reroll); others keep their role
	local role = if old == nil or old.Role == "Monster" then "Human" else old.Role
	local t = pick(rng, role, taken, not hardElsewhere, noMonster) or pick(rng, "*", taken, not hardElsewhere, true)
	if t == nil then
		return false, "prog.err.questInvalid"
	end
	quests.List[index] = newState(rng, t)
	quests.Rerolled = true
	return true, nil
end

local function bump(list: { QuestState }, index: number, amount: number, changes: { Change })
	local state = list[index]
	if state.Claimed or amount <= 0 or state.Progress >= state.Goal then
		return
	end
	local before = state.Progress
	local value = math.min(state.Goal, before + amount)
	state.Progress = math.floor(value * 10 + 0.5) / 10
	table.insert(changes, {
		Index = index,
		Id = state.Id,
		Progress = state.Progress,
		Goal = state.Goal,
		Completed = before < state.Goal and state.Progress >= state.Goal,
	})
end

local function roleMatches(t: Template, role: string): boolean
	return t.Role == "Any" or t.Role == role
end

function Quests.TrackStat(list: { QuestState }, stat: string, amount: number, role: string, practice: boolean): { Change }
	local changes: { Change } = {}
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return changes
	end
	for i, state in list do
		local t = byId[state.Id]
		if t and t.Stat == stat and roleMatches(t, role) and (not practice or t.Practice) then
			if t.PerEvent then
				if amount >= (t.MinAmount or 1) then
					bump(list, i, 1, changes)
				end
			else
				bump(list, i, amount, changes)
			end
		end
	end
	return changes
end

function Quests.TrackRound(list: { QuestState }, ctx: RoundContext): { Change }
	local changes: { Change } = {}
	for i, state in list do
		local t = byId[state.Id]
		if t and t.Round and roleMatches(t, ctx.role) and (not ctx.practice or t.Practice) then
			bump(list, i, t.Round(ctx, t), changes)
		end
	end
	return changes
end

function Quests.Claim(state: QuestState): (number?, number?)
	if state.Claimed or not Quests.IsComplete(state) then
		return nil, nil
	end
	state.Claimed = true
	return Quests.RewardFor(state)
end

function Quests.SanitizeList(list: any): { QuestState }
	local out: { QuestState } = {}
	if type(list) ~= "table" then
		return out
	end
	for _, state in list do
		if type(state) == "table" and type(state.Id) == "string" then
			local t = byId[state.Id]
			if t then
				local goal = if table.find(t.Goals, state.Goal) then state.Goal else t.Goals[1]
				local progress = if type(state.Progress) == "number" and state.Progress == state.Progress
					then math.clamp(state.Progress, 0, goal)
					else 0
				table.insert(out, { Id = t.Id, Progress = progress, Goal = goal, Claimed = state.Claimed == true })
			end
		end
		if #out >= 8 then
			break
		end
	end
	return out
end

return Quests
