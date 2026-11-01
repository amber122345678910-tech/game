--!strict
-- Rewards: pure payout math (SPEC §1.6, Config.Rewards). Lune-safe, no services, no profile writes.
--
--   Rewards.ShouldReward(result) -> boolean      false for reason "Aborted" (Style Lab stop) / malformed results
--   Rewards.Context(result, row, extras?) -> RoundContext
--        result = RoundService.RoundEnded payload {winner, reason, rows, mvpUserId, practice, durations, ...}
--        row    = this player's RoundStatRow; extras = {finalPhase?, boxesSurvived?, boxHits?, firstWinAvailable?}
--        (a win by reason "Left" counts only when durations.round >= MinLeftWinTime)
--   Rewards.Compute(ctx) -> Breakdown            per-player EXP/G breakdown:
--        Participation, Win, Damage x PerDamage, Healing x PerHealing, Kill, Save, Revive, Parry, MVP
--        (each stat capped, then x PracticeMult in practice; floors per item) + FirstWinOfDay (real rounds only)
--   Breakdown = { exp, gold, items = {{key, exp, gold, count?}}, won, firstWin, practice }
--        item.key is a Strings key ("prog.reward.*"); count is the stat value shown as {1}
--   Rewards.Day(unixTime) -> number              UTC day index (floor(t / 86400))
--   Rewards.LoginStreak(lastDay, streak, today) -> (newStreak, isNewDay)
--        same day: unchanged; next day: +1; first login: 1; after a gap the streak decays softly
--        (STREAK_DECAY per missed day, never below 0) and then today's login counts (+1)
--   Rewards.StreakGold(streak) -> number         min(25 + 15*(streak-1), 100) + 100 on every 7th day
--   Rewards.FirstWinAvailable(profile, today) -> boolean      profile.Login.FirstWinDay ~= today
--   Rewards.Grant(profile, exp, gold) -> GrantResult        mutates: EXP with level-ups (+ LevelUpGold), G,
--        Stats.ExpEarned / GoldEarned; GrantResult = { LevelsGained, NewLevel, LevelGold }

local Config = require(script.Parent.Parent.Config)
local Levels = require(script.Parent.Levels)

local MAX_GOLD = 1e9

export type Row = {
	userId: number,
	name: string,
	team: string,
	kitId: string,
	damage: number,
	healing: number,
	kills: number,
	downs: number,
	parries: number,
	dodgesForced: number,
	saves: number,
	revives: number,
	survived: boolean,
}

export type RoundContext = {
	userId: number,
	row: Row,
	role: string, -- "Human" | "Monster"
	kitId: string,
	winner: string,
	reason: string,
	won: boolean,
	practice: boolean,
	mvp: boolean,
	finalPhase: boolean, -- the monster reached its Final Phase this round
	collapse: boolean, -- the round went into Collapse overtime
	humans: number, -- human rows in the round
	humanSurvivors: number,
	lastStanding: boolean, -- won as the only surviving human of a team of 2+
	boxesSurvived: number,
	boxHits: number,
	firstWinAvailable: boolean,
	exp: number, -- filled in by RewardService after Compute (quests like "earn N EXP")
}

export type Item = { key: string, exp: number, gold: number, count: number? }
export type Breakdown = {
	exp: number,
	gold: number,
	items: { Item },
	won: boolean,
	firstWin: boolean,
	practice: boolean,
}

local Rewards = {}

local R = Config.Rewards
local DAY = 86400
Rewards.STREAK_DECAY = 2 -- streak days lost per missed day (soft decay instead of a hard reset)
Rewards.MinLeftWinTime = 60 -- a win by the other side leaving counts only after this much fighting (anti-farm)

-- Per-round caps so a freak round (or a bug) cannot mint huge payouts.
Rewards.Caps = {
	damage = 6000,
	healing = 4000,
	kills = 12,
	saves = 6,
	revives = 8,
	parries = 40,
}

local function num(v: any): number
	if type(v) == "number" and v == v and v < math.huge and v > -math.huge then
		return v
	end
	return 0
end

function Rewards.ShouldReward(result: any): boolean
	return type(result) == "table" and result.reason ~= "Aborted" and type(result.rows) == "table"
end

function Rewards.Context(result: any, row: Row, extras: { [string]: any }?): RoundContext
	local ex = extras or {}
	local winner = if type(result.winner) == "string" then result.winner else ""
	local reason = if type(result.reason) == "string" then result.reason else ""
	local role = if row.team == "Monster" then "Monster" else "Human"
	local durations = if type(result.durations) == "table" then result.durations else {}
	local won = winner ~= "" and reason ~= "Aborted" and winner == row.team
	if won and reason == "Left" and num(durations.round) < Rewards.MinLeftWinTime then
		won = false -- the monster (or every human) quit right away: participation only, no free win
	end
	local humans, survivors = 0, 0
	if type(result.rows) == "table" then
		for _, other in result.rows do
			if type(other) == "table" and other.team == "Humans" then
				humans += 1
				if other.survived then
					survivors += 1
				end
			end
		end
	end
	return {
		userId = row.userId,
		row = row,
		role = role,
		kitId = row.kitId,
		winner = winner,
		reason = reason,
		won = won,
		practice = result.practice == true,
		mvp = type(result.mvpUserId) == "number" and result.mvpUserId == row.userId,
		finalPhase = ex.finalPhase == true,
		collapse = num(durations.collapse) > 0 or reason == "Survived",
		humans = humans,
		humanSurvivors = survivors,
		lastStanding = won and role == "Human" and row.survived == true and survivors == 1 and humans >= 2,
		boxesSurvived = num(ex.boxesSurvived),
		boxHits = num(ex.boxHits),
		firstWinAvailable = ex.firstWinAvailable == true,
		exp = 0,
	}
end

function Rewards.Compute(ctx: RoundContext): Breakdown
	local row = ctx.row
	local mult = if ctx.practice then R.PracticeMult else 1
	local items: { Item } = {}
	local function add(key: string, exp: number, gold: number, count: number?)
		local e = math.floor(exp * mult + 1e-6)
		local g = math.floor(gold * mult + 1e-6)
		if e > 0 or g > 0 then
			table.insert(items, { key = key, exp = e, gold = g, count = count })
		end
	end
	local function stat(value: any, cap: number): number
		return math.clamp(math.floor(num(value)), 0, cap)
	end

	add("prog.reward.participation", R.Participation.Exp, R.Participation.Gold)
	if ctx.won then
		add("prog.reward.win", R.Win.Exp, R.Win.Gold)
	end
	local damage = stat(row.damage, Rewards.Caps.damage)
	add("prog.reward.damage", damage * R.PerDamage.Exp, damage * R.PerDamage.Gold, damage)
	local healing = stat(row.healing, Rewards.Caps.healing)
	add("prog.reward.healing", healing * R.PerHealing.Exp, healing * R.PerHealing.Gold, healing)
	local kills = stat(row.kills, Rewards.Caps.kills)
	add("prog.reward.kills", kills * R.Kill.Exp, kills * R.Kill.Gold, kills)
	local saves = stat(row.saves, Rewards.Caps.saves)
	add("prog.reward.saves", saves * R.Save.Exp, saves * R.Save.Gold, saves)
	local revives = stat(row.revives, Rewards.Caps.revives)
	add("prog.reward.revives", revives * R.Revive.Exp, revives * R.Revive.Gold, revives)
	local parries = stat(row.parries, Rewards.Caps.parries)
	add("prog.reward.parries", parries * R.Parry.Exp, parries * R.Parry.Gold, parries)
	if ctx.mvp then
		add("prog.reward.mvp", R.MVP.Exp, R.MVP.Gold)
	end

	local firstWin = ctx.won and not ctx.practice and ctx.firstWinAvailable
	if firstWin then
		table.insert(items, { key = "prog.reward.firstWin", exp = R.FirstWinOfDay.Exp, gold = R.FirstWinOfDay.Gold })
	end

	local exp, gold = 0, 0
	for _, item in items do
		exp += item.exp
		gold += item.gold
	end
	return { exp = exp, gold = gold, items = items, won = ctx.won, firstWin = firstWin, practice = ctx.practice }
end

export type GrantResult = { LevelsGained: number, NewLevel: number, LevelGold: number }

-- Adds EXP + G to a profile (mutates): carries level-ups (+ Levels.LevelUpGold for each new LV) and the
-- lifetime counters Stats.ExpEarned / Stats.GoldEarned. Used for rounds, quests, login and achievements.
function Rewards.Grant(profile: any, exp: number, gold: number): GrantResult
	local e = math.max(0, math.floor(num(exp)))
	local g = math.max(0, math.floor(num(gold)))
	local fromLevel = profile.Level
	local level, rest, gained = Levels.Add(profile.Level, profile.Exp, e)
	profile.Level = level
	profile.Exp = rest
	local levelGold = if gained > 0 then Levels.GoldForLevels(fromLevel, level) else 0
	profile.Gold = math.min((profile.Gold or 0) + g + levelGold, MAX_GOLD)
	local stats = profile.Stats
	if type(stats) == "table" then
		stats.ExpEarned = (stats.ExpEarned or 0) + e
		stats.GoldEarned = (stats.GoldEarned or 0) + g + levelGold
	end
	return { LevelsGained = gained, NewLevel = level, LevelGold = levelGold }
end

function Rewards.Day(unixTime: number): number
	return math.floor(unixTime / DAY)
end

function Rewards.LoginStreak(lastDay: number, streak: number, today: number): (number, boolean)
	local last = math.floor(num(lastDay))
	local s = math.max(0, math.floor(num(streak)))
	if last <= 0 then
		return 1, true
	end
	if today <= last then
		return math.max(s, 1), false -- same day (or a clock that went backwards): nothing new
	end
	if today == last + 1 then
		return s + 1, true
	end
	local missed = today - last - 1
	return math.max(0, s - Rewards.STREAK_DECAY * missed) + 1, true
end

function Rewards.StreakGold(streak: number): number
	local s = math.max(1, math.floor(num(streak)))
	local gold = math.min(25 + 15 * (s - 1), 100)
	if s % 7 == 0 then
		gold += 100
	end
	return gold
end

function Rewards.FirstWinAvailable(profile: any, today: number): boolean
	local login = if type(profile) == "table" then profile.Login else nil
	return type(login) ~= "table" or login.FirstWinDay ~= today
end

return Rewards
