--!strict
-- Achievements: lifetime + single-round feats, each rewards a Title (title id = achievement id) and some G.
-- Pure + Lune-safe. Text: "prog.ach.<id>" (name), "prog.ach.<id>.desc" ({1} = goal), "prog.title.<id>".
--
--   Achievements.List() -> {AchievementDef}           display order
--   Achievements.Get(id) -> AchievementDef?           Achievements.Count() -> number
--   Achievements.Check(profile, ctx?) -> {string}     ids newly satisfied (not yet in profile.Achievements);
--                                                     ctx = Rewards.RoundContext for single-round feats
--                                                     (round feats never unlock in practice rounds)
--   Achievements.Progress(profile, id) -> (value, goal)   for UI bars (round feats: 0/1)
--   Achievements.Grant(profile, id) -> boolean        marks it, grants the title + Gold; false if already had
--   Achievements.NameKey(id) / DescKey(id) -> string
-- AchievementDef = { Id, Group, Rarity, Goal, Gold, Title, Order, Hidden?, Value?(profile) -> number,
--                    Round?(ctx) -> boolean }
-- Groups: "Trials", "Victory", "Combat", "Support", "Box", "Growth", "Collection", "Feats".

local Kits = require(script.Parent.Parent.Kits)
local Mastery = require(script.Parent.Mastery)
local Rewards = require(script.Parent.Rewards)

type RoundContext = Rewards.RoundContext

export type AchievementDef = {
	Id: string,
	Group: string,
	Rarity: string,
	Goal: number,
	Gold: number,
	Title: string,
	Order: number,
	Hidden: boolean?,
	Value: ((profile: any) -> number)?,
	Round: ((ctx: RoundContext) -> boolean)?,
}

local Achievements = {}

Achievements.GoldByRarity = { Common = 50, Rare = 120, Epic = 300, Legendary = 750 } :: { [string]: number }

local function stat(name: string): (any) -> number
	return function(profile: any): number
		local v = profile.Stats and profile.Stats[name]
		return if type(v) == "number" then v else 0
	end
end

local function level(profile: any): number
	return if type(profile.Level) == "number" then profile.Level else 1
end

local function bestStreak(profile: any): number
	local login = profile.Login
	if type(login) ~= "table" then
		return 0
	end
	return math.max(tonumber(login.Best) or 0, tonumber(login.Streak) or 0)
end

local function ownedKits(profile: any): number
	local n = 0
	for _, kit in Kits.All() do
		if profile.Unlocked[kit.Id] then
			n += 1
		end
	end
	return n
end

local function ownedSkins(profile: any): number
	local n = 0
	for key, owned in profile.Unlocked do
		if owned and type(key) == "string" then
			local kitId, skinId = string.match(key, "^([%w_]+):([%w_]+)$")
			if kitId and skinId and skinId ~= "Default" and Kits.Skin(kitId, skinId) then
				n += 1
			end
		end
	end
	return n
end

local function maxMastery(profile: any): number
	local best = 1
	for _, lv in Mastery.LevelsOf(profile) do
		best = math.max(best, lv)
	end
	return best
end

local list: { AchievementDef } = {}
local byId: { [string]: AchievementDef } = {}

local function add(def: { [string]: any })
	local rarity: string = def.Rarity
	local entry: AchievementDef = {
		Id = def.Id,
		Group = def.Group,
		Rarity = rarity,
		Goal = def.Goal or 1,
		Gold = Achievements.GoldByRarity[rarity] or 0,
		Title = def.Id,
		Order = #list + 1,
		Hidden = def.Hidden,
		Value = def.Value,
		Round = def.Round,
	}
	assert(byId[entry.Id] == nil, "duplicate achievement " .. entry.Id)
	table.insert(list, entry)
	byId[entry.Id] = entry
end

local function life(group: string, id: string, rarity: string, goal: number, value: (any) -> number)
	add({ Id = id, Group = group, Rarity = rarity, Goal = goal, Value = value })
end

local function feat(id: string, rarity: string, check: (RoundContext) -> boolean, hidden: boolean?)
	add({ Id = id, Group = "Feats", Rarity = rarity, Goal = 1, Round = check, Hidden = hidden })
end

-- Trials (rounds played)
life("Trials", "first_round", "Common", 1, stat("Rounds"))
life("Trials", "rounds_25", "Common", 25, stat("Rounds"))
life("Trials", "rounds_100", "Rare", 100, stat("Rounds"))
life("Trials", "rounds_500", "Legendary", 500, stat("Rounds"))
-- Victory
life("Victory", "first_win", "Common", 1, stat("Wins"))
life("Victory", "wins_25", "Rare", 25, stat("Wins"))
life("Victory", "wins_100", "Epic", 100, stat("Wins"))
life("Victory", "monster_win", "Common", 1, stat("MonsterWins"))
life("Victory", "monster_wins_25", "Epic", 25, stat("MonsterWins"))
life("Victory", "human_wins_25", "Rare", 25, stat("HumanWins"))
life("Victory", "mvp_10", "Epic", 10, stat("MVPs"))
-- Combat
life("Combat", "kills_50", "Rare", 50, stat("Kills"))
life("Combat", "kills_250", "Epic", 250, stat("Kills"))
life("Combat", "damage_25k", "Rare", 25000, stat("Damage"))
life("Combat", "damage_100k", "Epic", 100000, stat("Damage"))
life("Combat", "parries_100", "Rare", 100, stat("Parries"))
life("Combat", "parries_500", "Epic", 500, stat("Parries"))
life("Combat", "dodges_250", "Rare", 250, stat("Dodges"))
-- Support
life("Support", "saves_25", "Common", 25, stat("Saves"))
life("Support", "saves_100", "Rare", 100, stat("Saves"))
life("Support", "revives_25", "Rare", 25, stat("Revives"))
life("Support", "revives_100", "Epic", 100, stat("Revives"))
life("Support", "heal_5000", "Rare", 5000, stat("Healing"))
-- Verdict Box
life("Box", "boxes_10", "Rare", 10, stat("BoxesSurvived"))
life("Box", "boxes_50", "Epic", 50, stat("BoxesSurvived"))
life("Box", "box_hits_100", "Rare", 100, stat("BoxHits"))
-- Growth
life("Growth", "level_10", "Common", 10, level)
life("Growth", "level_25", "Rare", 25, level)
life("Growth", "level_50", "Epic", 50, level)
life("Growth", "level_100", "Legendary", 100, level)
life("Growth", "streak_7", "Rare", 7, bestStreak)
life("Growth", "streak_30", "Legendary", 30, bestStreak)
life("Growth", "quests_25", "Rare", 25, stat("QuestsDone"))
life("Growth", "gold_10k", "Rare", 10000, stat("GoldEarned"))
-- Collection
life("Collection", "all_kits", "Epic", #Kits.All(), ownedKits)
life("Collection", "skins_5", "Rare", 5, ownedSkins)
life("Collection", "mastery_5", "Rare", 5, maxMastery)
life("Collection", "mastery_10", "Legendary", Mastery.MaxLevel, maxMastery)
-- Feats (single round, real rounds only)
feat("clutch", "Epic", function(ctx)
	return ctx.lastStanding
end)
feat("collapse_survivor", "Rare", function(ctx)
	return ctx.won and ctx.role == "Human" and ctx.reason == "Survived" and ctx.row.survived == true
end)
feat("no_mercy", "Epic", function(ctx)
	return ctx.won and ctx.role == "Monster" and ctx.reason == "Eliminated" and not ctx.collapse
end)
feat("unshaken", "Rare", function(ctx)
	return ctx.won and ctx.role == "Monster" and not ctx.finalPhase
end)
feat("big_damage", "Rare", function(ctx)
	return (tonumber(ctx.row.damage) or 0) >= 1000
end)
feat("triple_save", "Epic", function(ctx)
	return (tonumber(ctx.row.saves) or 0) >= 3
end)
feat("revive_3", "Epic", function(ctx)
	return (tonumber(ctx.row.revives) or 0) >= 3
end)
feat("pacifist", "Legendary", function(ctx)
	return ctx.won and ctx.role == "Human" and ctx.row.survived == true and (tonumber(ctx.row.damage) or 0) <= 0
end, true)

function Achievements.List(): { AchievementDef }
	return list
end

function Achievements.Get(id: string): AchievementDef?
	return byId[id]
end

function Achievements.Count(): number
	return #list
end

function Achievements.NameKey(id: string): string
	return "prog.ach." .. id
end

function Achievements.DescKey(id: string): string
	return "prog.ach." .. id .. ".desc"
end

function Achievements.Progress(profile: any, id: string): (number, number)
	local def = byId[id]
	if def == nil then
		return 0, 1
	end
	if profile.Achievements and profile.Achievements[id] then
		return def.Goal, def.Goal
	end
	if def.Value then
		return math.min(def.Value(profile), def.Goal), def.Goal
	end
	return 0, def.Goal
end

function Achievements.Check(profile: any, ctx: RoundContext?): { string }
	local out: { string } = {}
	local have = profile.Achievements or {}
	for _, def in list do
		if not have[def.Id] then
			local ok = false
			if def.Value then
				ok = def.Value(profile) >= def.Goal
			elseif def.Round and ctx ~= nil and not ctx.practice then
				ok = def.Round(ctx) == true
			end
			if ok then
				table.insert(out, def.Id)
			end
		end
	end
	return out
end

function Achievements.Grant(profile: any, id: string): boolean
	local def = byId[id]
	if def == nil or profile.Achievements[id] then
		return false
	end
	profile.Achievements[id] = true
	profile.Titles[def.Title] = true
	profile.Gold = (profile.Gold or 0) + def.Gold
	return true
end

return Achievements
