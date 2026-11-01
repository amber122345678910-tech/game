--!strict
-- Levels: player LV / EXP curve (SPEC §1.6). Pure + Lune-safe. Numbers come from Config.Progression.
--
--   Levels.ExpToNext(lv) -> number           EXP needed to go from lv to lv+1 = ExpBase + ExpPerLevel*(lv-1)
--                                            (100 + 60*(lv-1)); math.huge at MaxLevel
--   Levels.TotalExp(lv, exp?) -> number      lifetime EXP represented by (lv, exp) (LV 1 / 0 EXP = 0)
--   Levels.FromTotal(total) -> (lv, exp)     inverse of TotalExp (capped at MaxLevel, exp 0 there)
--   Levels.Add(lv, exp, amount) -> (lv', exp', gained)   adds EXP, carries level-ups, caps at MaxLevel
--   Levels.Progress(lv, exp) -> 0..1         fraction of the current level bar (1 at MaxLevel)
--   Levels.LevelUpGold(newLv) -> number      G granted when reaching newLv (LevelUpGold; x5 on every 10th LV)
--   Levels.GoldForLevels(fromLv, toLv) -> number   sum of LevelUpGold for fromLv+1 .. toLv
--   Levels.Clamp(lv, exp) -> (lv, exp)       sanitises stored values (integers, ranges, NaN)
--   Levels.MaxLevel                           Config.Progression.MaxLevel

local Config = require(script.Parent.Parent.Config)

local Levels = {}

local P = Config.Progression
Levels.MaxLevel = P.MaxLevel :: number

local MILESTONE_EVERY = 10
local MILESTONE_MULT = 5

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Levels.ExpToNext(lv: number): number
	if lv >= Levels.MaxLevel then
		return math.huge
	end
	local level = math.max(1, math.floor(lv))
	return P.ExpBase + P.ExpPerLevel * (level - 1)
end

-- Closed form: sum_{k=1}^{lv-1} (B + S*(k-1)) = B*(lv-1) + S*(lv-1)*(lv-2)/2
function Levels.TotalExp(lv: number, exp: number?): number
	local level = math.clamp(math.floor(lv), 1, Levels.MaxLevel)
	local n = level - 1
	return P.ExpBase * n + P.ExpPerLevel * n * (n - 1) / 2 + math.max(0, exp or 0)
end

function Levels.FromTotal(total: number): (number, number)
	if not isNumber(total) or total <= 0 then
		return 1, 0
	end
	local lv = 1
	local rest = math.floor(total)
	while lv < Levels.MaxLevel do
		local need = Levels.ExpToNext(lv)
		if rest < need then
			break
		end
		rest -= need
		lv += 1
	end
	if lv >= Levels.MaxLevel then
		return Levels.MaxLevel, 0
	end
	return lv, rest
end

function Levels.Clamp(lv: any, exp: any): (number, number)
	local level = if isNumber(lv) then math.clamp(math.floor(lv), 1, Levels.MaxLevel) else 1
	local e = if isNumber(exp) then math.max(0, math.floor(exp)) else 0
	if level >= Levels.MaxLevel then
		return Levels.MaxLevel, 0
	end
	-- an over-full bar (old data / changed curve) is carried into levels
	while level < Levels.MaxLevel and e >= Levels.ExpToNext(level) do
		e -= Levels.ExpToNext(level)
		level += 1
	end
	if level >= Levels.MaxLevel then
		return Levels.MaxLevel, 0
	end
	return level, e
end

function Levels.Add(lv: number, exp: number, amount: number): (number, number, number)
	local startLevel, e = Levels.Clamp(lv, exp)
	if not isNumber(amount) or amount <= 0 or startLevel >= Levels.MaxLevel then
		return startLevel, e, 0
	end
	local level, rest = Levels.Clamp(startLevel, e + math.floor(amount))
	return level, rest, level - startLevel
end

function Levels.Progress(lv: number, exp: number): number
	if lv >= Levels.MaxLevel then
		return 1
	end
	return math.clamp(exp / Levels.ExpToNext(lv), 0, 1)
end

function Levels.LevelUpGold(newLv: number): number
	local base = P.LevelUpGold
	if newLv % MILESTONE_EVERY == 0 then
		return base * MILESTONE_MULT
	end
	return base
end

function Levels.GoldForLevels(fromLv: number, toLv: number): number
	local total = 0
	for lv = math.floor(fromLv) + 1, math.floor(toLv) do
		total += Levels.LevelUpGold(lv)
	end
	return total
end

return Levels
