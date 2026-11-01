--!strict
-- QueueMath: pure maths of the fair monster queue (SPEC §1.5). Lune-safe, no services, no randomness
-- of its own (callers pass a roll in [0, 1) so selection is deterministic and testable).
--
-- Rules implemented:
--   * Each player has a weight (Profile.MonsterChance, starts at Config.Queue.BaseWeight = 1).
--   * Preference "Monster" multiplies the weight by Config.Queue.MonsterPreferenceMult (1.5);
--     preference "Human" removes the player from the draw (effective weight 0) unless NOBODY else
--     can be drawn, in which case everyone is drawn with plain weights ("Fallback" mode).
--   * Pity: eligible players with RoundsSinceMonster >= Config.Queue.PityRounds are drawn FIRST.
--     Only the longest-waiting of them form the pool (ties -> weighted draw among the tied).
--   * After a round: the monster resets to BaseWeight / 0 rounds; every human participant gets
--     +WeightPerRound (+1 more if they dealt >= ActiveBonusDamage and were not the MVP) and +1 round.
--
-- API
--   QueueMath.Sanitize(entry) -> Entry                       clean weight / rounds / preference
--   QueueMath.Pool(entries) -> ({Entry}, {number}, Mode)     the entries actually drawn from, their
--                                                            effective weights (same order) and the mode
--   QueueMath.Shares(entries) -> {[any]: number}             Id -> probability (0..1) of being chosen
--   QueueMath.Choose(entries, roll) -> any?                  Id of the chosen entry (roll in [0, 1))
--   QueueMath.NextWeight(weight, result) -> number           weight after a round
--   QueueMath.NextRounds(rounds, result) -> number           RoundsSinceMonster after a round
--   QueueMath.PreferenceMult(pref, fallback) -> number
-- Entry = { Id: any, Weight: number, RoundsSinceMonster: number, Preference: "Either"|"Monster"|"Human" }
-- RoundResult = { WasMonster: boolean, Participated: boolean, Damage: number?, WasMvp: boolean? }
-- Mode = "None" | "Pity" | "Weighted" | "Fallback"

local Config = require(script.Parent.Parent.Config)

local QueueMath = {}

export type Preference = "Either" | "Monster" | "Human"
export type Mode = "None" | "Pity" | "Weighted" | "Fallback"

export type Entry = {
	Id: any,
	Weight: number,
	RoundsSinceMonster: number,
	Preference: Preference,
}

export type RoundResult = {
	WasMonster: boolean,
	Participated: boolean,
	Damage: number?,
	WasMvp: boolean?,
}

local MAX_WEIGHT = 1000 -- safety cap (pity guarantees a pick long before this is reachable)

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function QueueMath.Sanitize(entry: Entry): Entry
	local q = Config.Queue
	local weight = entry.Weight
	if not finite(weight) or weight < 0.01 then
		weight = q.BaseWeight
	end
	local rounds = entry.RoundsSinceMonster
	if not finite(rounds) or rounds < 0 then
		rounds = 0
	end
	local pref: Preference = "Either"
	if entry.Preference == "Monster" or entry.Preference == "Human" then
		pref = entry.Preference
	end
	return {
		Id = entry.Id,
		Weight = math.min(weight, MAX_WEIGHT),
		RoundsSinceMonster = math.floor(rounds),
		Preference = pref,
	}
end

-- Multiplier applied to a player's weight because of their role preference.
-- In fallback mode (nobody wants to be the monster) preferences are ignored.
function QueueMath.PreferenceMult(pref: Preference, fallback: boolean): number
	if fallback then
		return 1
	end
	if pref == "Monster" then
		return Config.Queue.MonsterPreferenceMult
	elseif pref == "Human" then
		return 0
	end
	return 1
end

-- Returns the entries that take part in the draw, their effective weights and the selection mode.
function QueueMath.Pool(entries: { Entry }): ({ Entry }, { number }, Mode)
	local clean: { Entry } = {}
	for _, e in entries do
		table.insert(clean, QueueMath.Sanitize(e))
	end
	if #clean == 0 then
		return {}, {}, "None"
	end

	local eligible: { Entry } = {}
	for _, e in clean do
		if e.Preference ~= "Human" then
			table.insert(eligible, e)
		end
	end
	local fallback = #eligible == 0
	if fallback then
		eligible = clean
	end

	-- Pity: the longest-waiting players at or above the threshold are drawn first.
	local pity = Config.Queue.PityRounds
	local longest = -1
	for _, e in eligible do
		if e.RoundsSinceMonster >= pity and e.RoundsSinceMonster > longest then
			longest = e.RoundsSinceMonster
		end
	end
	local pool: { Entry } = {}
	local mode: Mode
	if longest >= 0 then
		for _, e in eligible do
			if e.RoundsSinceMonster == longest then
				table.insert(pool, e)
			end
		end
		mode = "Pity"
	else
		pool = eligible
		mode = if fallback then "Fallback" else "Weighted"
	end

	local weights: { number } = {}
	for _, e in pool do
		table.insert(weights, e.Weight * QueueMath.PreferenceMult(e.Preference, fallback))
	end
	return pool, weights, mode
end

-- Probability of each entry being chosen (Id -> 0..1). Entries outside the pool get 0.
function QueueMath.Shares(entries: { Entry }): { [any]: number }
	local shares: { [any]: number } = {}
	for _, e in entries do
		shares[e.Id] = 0
	end
	local pool, weights = QueueMath.Pool(entries)
	local total = 0
	for _, w in weights do
		total += w
	end
	if total <= 0 then
		-- every weight is zero (cannot normally happen): uniform over the pool
		for _, e in pool do
			shares[e.Id] = 1 / #pool
		end
		return shares
	end
	for i, e in pool do
		shares[e.Id] = (shares[e.Id] or 0) + weights[i] / total
	end
	return shares
end

-- Deterministic weighted draw. roll must be in [0, 1) (values outside are clamped).
function QueueMath.Choose(entries: { Entry }, roll: number): any?
	local pool, weights = QueueMath.Pool(entries)
	if #pool == 0 then
		return nil
	end
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = if finite(roll) then math.clamp(roll, 0, 0.999999999) else 0
	if total <= 0 then
		return pool[math.floor(r * #pool) + 1].Id
	end
	local target = r * total
	local acc = 0
	for i, e in pool do
		acc += weights[i]
		if target < acc then
			return e.Id
		end
	end
	return pool[#pool].Id
end

function QueueMath.NextWeight(weight: number, result: RoundResult): number
	local q = Config.Queue
	local w = if finite(weight) and weight >= 0.01 then weight else q.BaseWeight
	if result.WasMonster then
		return q.BaseWeight
	end
	if not result.Participated then
		return math.min(w, MAX_WEIGHT)
	end
	local gain = q.WeightPerRound
	local damage = result.Damage or 0
	if damage >= q.ActiveBonusDamage and not result.WasMvp then
		gain += 1
	end
	return math.min(w + gain, MAX_WEIGHT)
end

function QueueMath.NextRounds(rounds: number, result: RoundResult): number
	local r = if finite(rounds) and rounds >= 0 then math.floor(rounds) else 0
	if result.WasMonster then
		return 0
	end
	if result.Participated then
		return r + 1
	end
	return r
end

return QueueMath
