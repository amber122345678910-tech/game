--!strict
-- RoundRules: pure rules of the round loop (SPEC §1.1-§1.4). Lune-safe, no services, no randomness
-- of its own (callers pass rolls). RoundService/ObjectiveService/StatsService call these so the
-- rules are unit-tested offline (tools/lune/tests/round.spec.luau).
--
-- API
--   RoundRules.PHASES                                   ordered phase names
--   RoundRules.PhaseDuration(phase, practice?) -> number seconds (0 = untimed)
--   RoundRules.Next(phase, info) -> string              next phase (see NextInfo)
--   RoundRules.Evaluate(snapshot) -> (winner?, reason?) "Humans"|"Monster", "Defeated"|"Survived"|"Eliminated"|"Left"
--   RoundRules.ShouldWipeDowned(up, downed) -> boolean  nobody is up -> downed humans can never be revived
--   RoundRules.ShouldTriggerFinalPhase(health, maxHealth, alreadyTriggered) -> boolean
--   RoundRules.ShouldSecondWind(humansAtStart, humansUp, alreadyTriggered) -> boolean
--   RoundRules.HarmonyMultiplier(kitIds) -> number      1 + 4 % per distinct class beyond the first (cap +20 %)
--   RoundRules.MonsterMaxHealth(stats, humans) -> number
--   RoundRules.CollapseRadius(elapsed, startRadius) -> number   linear shrink to CollapseMinRadius
--   RoundRules.IsOutside(position, center, radius) -> boolean   horizontal (XZ) distance test
--   RoundRules.SaveChannelRate(humans, monsterNear) -> number   progress per second (0..1 scale)
--   RoundRules.Score(row) -> number                     MVP score of a RoundStatRow
--   RoundRules.Mvp(rows) -> number?                     userId of the best row (nil if nobody scored)
--   RoundRules.VoteWinner(options, votes, roll) -> string?      most voted option, ties/no votes by roll
--   RoundRules.VoteCounts(options, votes) -> {[string]: number}

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type RoundStatRow = Types.RoundStatRow
type KitStats = Types.KitStats

local RoundRules = {}

RoundRules.PHASES = { "Waiting", "Intermission", "Intro", "Round", "Collapse", "Ending" }

RoundRules.WINNER_HUMANS = "Humans"
RoundRules.WINNER_MONSTER = "Monster"

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function RoundRules.PhaseDuration(phase: string, practice: boolean?): number
	local r = Config.Round
	if phase == "Intermission" then
		return r.IntermissionTime
	elseif phase == "Intro" then
		-- practice skips most of the cinematic so solo testing is snappy
		return if practice then math.min(r.IntroTime, 4) else r.IntroTime
	elseif phase == "Round" then
		return r.RoundTime
	elseif phase == "Collapse" then
		return r.CollapseTime
	elseif phase == "Ending" then
		return if practice then math.min(r.EndingTime, 7) else r.EndingTime
	end
	return 0
end

export type NextInfo = {
	Players: number, -- eligible players in the server
	TimerDone: boolean, -- the current phase's timer ran out (or was skipped)
	Winner: string?, -- a winner was decided during Intro/Round/Collapse
	PracticeRequested: boolean?, -- a solo practice was requested while Waiting
}

-- Phase transition table (SPEC §1.1). Pure: decides only, never acts.
function RoundRules.Next(phase: string, info: NextInfo): string
	local enough = info.Players >= Config.Round.MinPlayers
	if phase == "Waiting" then
		if enough then
			return "Intermission"
		end
		if info.PracticeRequested then
			return "Intro"
		end
		return "Waiting"
	elseif phase == "Intermission" then
		if not enough then
			return "Waiting"
		end
		return if info.TimerDone then "Intro" else "Intermission"
	elseif phase == "Intro" or phase == "Round" or phase == "Collapse" then
		if info.Winner ~= nil then
			return "Ending"
		end
		if not info.TimerDone then
			return phase
		end
		if phase == "Intro" then
			return "Round"
		elseif phase == "Round" then
			return "Collapse"
		end
		return "Ending" -- Collapse timer ran out: survivors win (see Evaluate with TimeUp)
	elseif phase == "Ending" then
		if not info.TimerDone then
			return "Ending"
		end
		return if enough then "Intermission" else "Waiting"
	end
	return "Waiting"
end

export type Snapshot = {
	MonsterAlive: boolean, -- the monster character exists and is not dead
	MonsterLeft: boolean, -- the monster's player left the game
	HumansUp: number, -- humans alive and not downed
	HumansDowned: number, -- humans downed (still alive)
	HumansLeft: boolean?, -- the last human removal was a player leaving (reason "Left")
	TimeUp: boolean?, -- the Collapse timer ran out
	PracticeHumanDead: boolean?, -- practice as Human: the real player died
}

-- Who won, if anyone (priority: monster leaving, monster dead, humans gone, practice player dead, time up).
function RoundRules.Evaluate(s: Snapshot): (string?, string?)
	if s.MonsterLeft then
		return RoundRules.WINNER_HUMANS, "Left"
	end
	if not s.MonsterAlive then
		return RoundRules.WINNER_HUMANS, "Defeated"
	end
	local alive = math.max(0, s.HumansUp) + math.max(0, s.HumansDowned)
	if alive <= 0 then
		return RoundRules.WINNER_MONSTER, if s.HumansLeft then "Left" else "Eliminated"
	end
	if s.PracticeHumanDead then
		return RoundRules.WINNER_MONSTER, "Eliminated"
	end
	if s.TimeUp then
		return RoundRules.WINNER_HUMANS, "Survived"
	end
	return nil, nil
end

-- When no human is up, nobody can revive the downed ones: they all fall (Monster wins).
function RoundRules.ShouldWipeDowned(up: number, downed: number): boolean
	return up <= 0 and downed > 0
end

function RoundRules.ShouldTriggerFinalPhase(health: number, maxHealth: number, alreadyTriggered: boolean): boolean
	if alreadyTriggered or not finite(health) or not finite(maxHealth) or maxHealth <= 0 or health <= 0 then
		return false
	end
	return health / maxHealth <= Config.Round.FinalPhaseHpFraction
end

function RoundRules.ShouldSecondWind(humansAtStart: number, humansUp: number, alreadyTriggered: boolean): boolean
	return not alreadyTriggered and humansAtStart >= 2 and humansUp == 1
end

-- +HarmonyPerClass for every distinct SOUL class beyond the first, capped at HarmonyMax.
function RoundRules.HarmonyMultiplier(kitIds: { string }): number
	local seen: { [string]: boolean } = {}
	local distinct = 0
	for _, id in kitIds do
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			distinct += 1
		end
	end
	local bonus = math.min(Config.Human.HarmonyMax, Config.Human.HarmonyPerClass * math.max(0, distinct - 1))
	-- round to 4 decimals so 1 + 0.04 * 3 is exactly 1.12 when shown
	return math.floor((1 + bonus) * 10000 + 0.5) / 10000
end

function RoundRules.MonsterMaxHealth(stats: KitStats, humans: number): number
	local base = if finite(stats.MaxHP) then stats.MaxHP else 1000
	local per = if finite(stats.HPPerHuman) then stats.HPPerHuman :: number else 0
	local n = if finite(humans) then math.max(0, math.floor(humans)) else 0
	return math.max(1, base + per * n)
end

-- Safe radius during Collapse: linear from startRadius to CollapseMinRadius over CollapseTime.
function RoundRules.CollapseRadius(elapsed: number, startRadius: number): number
	local minR = Config.Round.CollapseMinRadius
	local total = Config.Round.CollapseTime
	if not finite(startRadius) or startRadius <= minR then
		return if finite(startRadius) then math.max(0, startRadius) else minR
	end
	local t = if finite(elapsed) and total > 0 then math.clamp(elapsed / total, 0, 1) else 1
	return startRadius + (minR - startRadius) * t
end

function RoundRules.IsOutside(position: Vector3, center: Vector3, radius: number): boolean
	local dx = position.X - center.X
	local dz = position.Z - center.Z
	return dx * dx + dz * dz > radius * radius
end

-- SAVE point channel speed (progress per second, 1 = lit). Paused while the monster is inside.
function RoundRules.SaveChannelRate(humans: number, monsterNear: boolean): number
	local o = Config.Objectives
	if monsterNear or humans <= 0 or o.SaveChannelTime <= 0 then
		return 0
	end
	return (1 + o.SaveExtraPlayerSpeed * (humans - 1)) / o.SaveChannelTime
end

function RoundRules.Score(row: RoundStatRow): number
	return (row.damage or 0)
		+ (row.healing or 0) * 1.2
		+ (row.kills or 0) * 150
		+ (row.saves or 0) * 120
		+ (row.revives or 0) * 120
		+ (row.parries or 0) * 25
		+ (row.dodgesForced or 0) * 10
		+ (if row.survived then 100 else 0)
end

-- Best row's userId. Ties: more damage wins, then the earlier row. nil when nobody scored.
function RoundRules.Mvp(rows: { RoundStatRow }): number?
	local best: RoundStatRow? = nil
	local bestScore = 0
	for _, row in rows do
		local score = RoundRules.Score(row)
		if score > 0 then
			if best == nil or score > bestScore or (score == bestScore and (row.damage or 0) > (best.damage or 0)) then
				best = row
				bestScore = score
			end
		end
	end
	return if best then best.userId else nil
end

function RoundRules.VoteCounts(options: { string }, votes: { [any]: string }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, id in options do
		counts[id] = 0
	end
	for _, choice in votes do
		if counts[choice] ~= nil then
			counts[choice] += 1
		end
	end
	return counts
end

-- Most voted option; ties (and "no votes at all") are broken by roll in [0, 1).
function RoundRules.VoteWinner(options: { string }, votes: { [any]: string }, roll: number): string?
	if #options == 0 then
		return nil
	end
	local counts = RoundRules.VoteCounts(options, votes)
	local best = -1
	local tied: { string } = {}
	for _, id in options do
		local c = counts[id]
		if c > best then
			best = c
			tied = { id }
		elseif c == best then
			table.insert(tied, id)
		end
	end
	local r = if finite(roll) then math.clamp(roll, 0, 0.999999999) else 0
	return tied[math.floor(r * #tied) + 1]
end

return RoundRules
