--!strict
-- DamageMath: pure formulas of the combat pipeline (SPEC §1.2, §1.3, §7.5). Lune-safe, unit-tested.
-- Services (DamageService / StatusService / AbilityService) call these so the numbers live in one place.
-- Every function takes an optional `cfg` table (defaults to the matching Config section) so tests can
-- pass custom tunables.
--
-- Multipliers
--   OutgoingMult(mults: {number}) -> number   buffs (m >= 1) stack ADDITIVELY (1 + sum(m-1)), debuffs (m < 1)
--                                             stack multiplicatively; clamped to [0, 5]
--   IncomingMult(mults: {number}) -> number   product of all factors (reductions multiply); clamped [0, 5]
--   HarmonyMult(distinctClasses, cfg?) -> number          1 + min(HarmonyMax, HarmonyPerClass*(n-1))
--   HarmonyFromAttribute(value: any, cfg?) -> number       RoundState "Harmony": a multiplier (>= 1) or a
--                                                          bonus fraction (< 1); anything else -> 1
-- Colour rule
--   ColorHurts(color, horizontalSpeed, threshold?) -> boolean   Blue: only movers; Orange: only still targets
-- Block / parry / guard
--   IsFacing(defenderPos, defenderLook, sourcePos, minDot?) -> boolean (horizontal; coincident = facing)
--   IsParry(blockStart, now, window?, kind) -> boolean     only Melee/Projectile hits can be parried
--   BlockSplit(amount, reduction?) -> (taken, blocked)
--   GuardAfterBlock(guard, blocked) -> (newGuard, broken)
--   GuardRegen(guard, maxGuard, now, lastHitAt, dt, mult?, cfg?) -> newGuard
-- Shield / health
--   AbsorbShield(amount, shield) -> (remaining, absorbed, shieldLeft)
--   ApplyHealth(hp, amount, minHp?) -> (newHp, applied)      never raises HP; floor = minHp (default 0)
--   ApplyHeal(hp, maxHp, amount) -> (newHp, healed)
-- KR (Karma)
--   KRRate(kr, cfg?) -> HP/s                    DrainBase + DrainPerStack*(kr-1) for kr > 0
--   KRStep(hp, kr, dt, cfg?) -> (newHp, newKr, drained)   KR drops by the drained amount even at the HP
--                                                         floor; HP never goes below cfg.MinHealth
--   KRAdd(kr, add, cfg?) -> number              capped at cfg.Max
--   KRCleanse(kr, amount) -> number
-- Dodges (monster)
--   DodgeState = { Dodges, Max, LastDodge, Acc, ExhaustedUntil }
--   NewDodgeState(max, now?) -> DodgeState
--   ConsumeDodge(state, now, cfg?) -> exhaustedNow: boolean     (Dodges 1 -> 0 starts exhaustion)
--   DodgeRegen(state, now, dt, regenMult?, cfg?) -> gained       (+1 per DodgeRegenInterval after
--                                                                 DodgeRegenDelay without dodging)
--   ExhaustEnd(state, now) -> refilled: boolean                  (refill to Max when exhaustion ends)
--   DodgeTick(state, now, dt, regenMult?, cfg?) -> (gained, refilled)
-- Charges / cooldowns / combos / aim
--   ChargeTick(charges, max, acc, dt, rechargeTime) -> (charges, acc)
--   ScaledCooldownEnd(now, remaining, windowLeft, mult) -> endsAt  cooldown progressing at `mult` speed
--                                                                  for the next windowLeft seconds
--   NextComboIndex(prevIndex, lastTime, now, window, comboLength) -> index (1..comboLength)
--   ClampCharge(charge, readySince, now, maxHoldTime, tolerance?) -> number in [0, 1]
--   ClampAim(origin, aim, maxDist) -> Vector3
-- Ultimate
--   RoleOfTeam(team) -> "Monster" | "Human"
--   UltForDamageDealt(role, amount, cfg?) ; UltForDamageTaken(role, amount, cfg?) ; UltForHeal(role, amount, cfg?)
--   UltPerSecond(role, cfg?) ; AddUlt(current, gain) -> number in [0, 100]

local Config = require(script.Parent.Parent.Config)

local DamageMath = {}

DamageMath.MaxMult = 5
DamageMath.UltMax = 100

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

---------------------------------------------------------------------------------------------------
-- Multipliers

function DamageMath.OutgoingMult(mults: { number }): number
	local bonus = 0
	local factor = 1
	for _, m in mults do
		if m == m then -- skip NaN
			if m >= 1 then
				bonus += m - 1
			elseif m >= 0 then
				factor *= m
			else
				factor = 0
			end
		end
	end
	return clamp((1 + bonus) * factor, 0, DamageMath.MaxMult)
end

function DamageMath.IncomingMult(mults: { number }): number
	local product = 1
	for _, m in mults do
		if m == m then
			product *= math.max(0, m)
		end
	end
	return clamp(product, 0, DamageMath.MaxMult)
end

function DamageMath.HarmonyMult(distinctClasses: number, cfg: any?): number
	local c = cfg or Config.Human
	local n = math.max(0, math.floor(distinctClasses) - 1)
	return 1 + math.min(c.HarmonyMax, c.HarmonyPerClass * n)
end

function DamageMath.HarmonyFromAttribute(value: any, cfg: any?): number
	local c = cfg or Config.Human
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	local mult = if value >= 1 then value elseif value >= 0 then 1 + value else 1
	return clamp(mult, 1, 1 + c.HarmonyMax + 1e-9)
end

---------------------------------------------------------------------------------------------------
-- Colour rule

function DamageMath.ColorHurts(color: string?, horizontalSpeed: number, threshold: number?): boolean
	local th = threshold or Config.Combat.MoveThreshold
	if color == "Blue" then
		return horizontalSpeed > th
	elseif color == "Orange" then
		return horizontalSpeed <= th
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- Block / parry / guard

function DamageMath.IsFacing(defenderPos: Vector3, defenderLook: Vector3, sourcePos: Vector3, minDot: number?): boolean
	local to = Vector3.new(sourcePos.X - defenderPos.X, 0, sourcePos.Z - defenderPos.Z)
	if to.Magnitude < 0.05 then
		return true
	end
	local look = Vector3.new(defenderLook.X, 0, defenderLook.Z)
	if look.Magnitude < 1e-4 then
		return true
	end
	return to.Unit:Dot(look.Unit) > (minDot or Config.Human.BlockAngleDot)
end

function DamageMath.IsParry(blockStart: number?, now: number, window: number?, kind: string): boolean
	if blockStart == nil or blockStart <= 0 then
		return false
	end
	if kind ~= "Melee" and kind ~= "Projectile" then
		return false
	end
	local elapsed = now - blockStart
	return elapsed >= -0.05 and elapsed <= (window or Config.Human.ParryWindow)
end

function DamageMath.BlockSplit(amount: number, reduction: number?): (number, number)
	local r = clamp(reduction or Config.Human.BlockReduction, 0, 1)
	local taken = amount * (1 - r)
	return taken, amount - taken
end

function DamageMath.GuardAfterBlock(guard: number, blocked: number): (number, boolean)
	local g = guard - math.max(0, blocked)
	if g <= 0 then
		return 0, true
	end
	return g, false
end

function DamageMath.GuardRegen(
	guard: number,
	maxGuard: number,
	now: number,
	lastHitAt: number,
	dt: number,
	mult: number?,
	cfg: any?
): number
	local c = cfg or Config.Human
	if guard >= maxGuard then
		return maxGuard
	end
	local since = now - lastHitAt - c.GuardRegenDelay
	if since <= 0 or dt <= 0 then
		return guard
	end
	local step = math.min(dt, since)
	return math.min(maxGuard, guard + c.GuardRegenPerSecond * (mult or 1) * step)
end

---------------------------------------------------------------------------------------------------
-- Shield / health

function DamageMath.AbsorbShield(amount: number, shield: number): (number, number, number)
	if shield <= 0 or amount <= 0 then
		return amount, 0, math.max(0, shield)
	end
	local absorbed = math.min(amount, shield)
	return amount - absorbed, absorbed, shield - absorbed
end

function DamageMath.ApplyHealth(hp: number, amount: number, minHp: number?): (number, number)
	if amount <= 0 then
		return hp, 0
	end
	local floor = minHp or 0
	local newHp = math.max(floor, hp - amount)
	if newHp > hp then
		newHp = hp -- already below the floor: never raise HP
	end
	return newHp, hp - newHp
end

function DamageMath.ApplyHeal(hp: number, maxHp: number, amount: number): (number, number)
	if amount <= 0 or hp >= maxHp then
		return hp, 0
	end
	local newHp = math.min(maxHp, hp + amount)
	return newHp, newHp - hp
end

---------------------------------------------------------------------------------------------------
-- KR

function DamageMath.KRRate(kr: number, cfg: any?): number
	local c = cfg or Config.KR
	if kr <= 0 then
		return 0
	end
	return c.DrainBase + c.DrainPerStack * math.max(0, kr - 1)
end

function DamageMath.KRStep(hp: number, kr: number, dt: number, cfg: any?): (number, number, number)
	local c = cfg or Config.KR
	if kr <= 0 or dt <= 0 then
		return hp, math.max(0, kr), 0
	end
	local amount = math.min(DamageMath.KRRate(kr, c) * dt, kr)
	local newKr = kr - amount
	if newKr < 1e-6 then
		newKr = 0
	end
	local drained = 0
	if hp > c.MinHealth then
		drained = math.min(amount, hp - c.MinHealth)
	end
	return hp - drained, newKr, drained
end

function DamageMath.KRAdd(kr: number, add: number, cfg: any?): number
	local c = cfg or Config.KR
	if add <= 0 then
		return kr
	end
	return math.min(c.Max, math.max(0, kr) + add)
end

function DamageMath.KRCleanse(kr: number, amount: number): number
	return math.max(0, kr - math.max(0, amount))
end

---------------------------------------------------------------------------------------------------
-- Dodges

export type DodgeState = {
	Dodges: number,
	Max: number,
	LastDodge: number,
	Acc: number,
	ExhaustedUntil: number,
}

function DamageMath.NewDodgeState(max: number, now: number?): DodgeState
	return { Dodges = max, Max = max, LastDodge = now or 0, Acc = 0, ExhaustedUntil = 0 }
end

function DamageMath.ConsumeDodge(state: DodgeState, now: number, cfg: any?): boolean
	local c = cfg or Config.Monster
	if state.Dodges < 1 or state.ExhaustedUntil > 0 then
		return false
	end
	state.Dodges -= 1
	state.LastDodge = now
	state.Acc = 0
	if state.Dodges <= 0 then
		state.Dodges = 0
		state.ExhaustedUntil = now + c.ExhaustTime
		return true
	end
	return false
end

function DamageMath.DodgeRegen(state: DodgeState, now: number, dt: number, regenMult: number?, cfg: any?): number
	local c = cfg or Config.Monster
	if state.Dodges > state.Max then
		state.Dodges = state.Max
	end
	if state.ExhaustedUntil > 0 or state.Dodges >= state.Max or dt <= 0 then
		state.Acc = 0
		return 0
	end
	local regenStart = state.LastDodge + c.DodgeRegenDelay
	if now <= regenStart then
		return 0
	end
	state.Acc += math.min(dt, now - regenStart) * (regenMult or 1)
	local gained = 0
	while state.Acc >= c.DodgeRegenInterval and state.Dodges < state.Max do
		state.Acc -= c.DodgeRegenInterval
		state.Dodges += 1
		gained += 1
	end
	if state.Dodges >= state.Max then
		state.Acc = 0
	end
	return gained
end

function DamageMath.ExhaustEnd(state: DodgeState, now: number): boolean
	if state.ExhaustedUntil > 0 and now >= state.ExhaustedUntil then
		state.ExhaustedUntil = 0
		state.Dodges = state.Max
		state.Acc = 0
		state.LastDodge = now
		return true
	end
	return false
end

function DamageMath.DodgeTick(
	state: DodgeState,
	now: number,
	dt: number,
	regenMult: number?,
	cfg: any?
): (number, boolean)
	local refilled = DamageMath.ExhaustEnd(state, now)
	if refilled then
		return 0, true
	end
	return DamageMath.DodgeRegen(state, now, dt, regenMult, cfg), false
end

---------------------------------------------------------------------------------------------------
-- Charges / cooldowns / combos / aim

function DamageMath.ChargeTick(
	charges: number,
	max: number,
	acc: number,
	dt: number,
	rechargeTime: number
): (number, number)
	if charges >= max then
		return max, 0
	end
	if rechargeTime <= 0 then
		return max, 0
	end
	acc += math.max(0, dt)
	while acc >= rechargeTime and charges < max do
		acc -= rechargeTime
		charges += 1
	end
	if charges >= max then
		acc = 0
	end
	return charges, acc
end

function DamageMath.ScaledCooldownEnd(now: number, remaining: number, windowLeft: number, mult: number): number
	if remaining <= 0 then
		return now
	end
	if windowLeft <= 0 or mult == 1 then
		return now + remaining
	end
	local m = math.max(mult, 0.01)
	if remaining <= windowLeft * m then
		return now + remaining / m
	end
	return now + windowLeft + (remaining - windowLeft * m)
end

function DamageMath.NextComboIndex(
	prevIndex: number,
	lastTime: number?,
	now: number,
	window: number,
	comboLength: number
): number
	if comboLength <= 1 then
		return 1
	end
	if lastTime ~= nil and now - lastTime <= window and prevIndex >= 1 and prevIndex < comboLength then
		return prevIndex + 1
	end
	return 1
end

function DamageMath.ClampCharge(
	charge: any,
	readySince: number,
	now: number,
	maxHoldTime: number,
	tolerance: number?
): number
	if type(charge) ~= "number" or charge ~= charge then
		return 0
	end
	local c = clamp(charge, 0, 1)
	if maxHoldTime <= 0 then
		return c
	end
	local held = (now - readySince) / maxHoldTime + (tolerance or 0.15)
	return math.min(c, clamp(held, 0, 1))
end

function DamageMath.ClampAim(origin: Vector3, aim: Vector3, maxDist: number): Vector3
	local d = aim - origin
	local m = d.Magnitude
	if m > maxDist and m > 1e-6 then
		return origin + d * (maxDist / m)
	end
	return aim
end

---------------------------------------------------------------------------------------------------
-- Ultimate

function DamageMath.RoleOfTeam(team: string): "Monster" | "Human"
	if team == "Monster" then
		return "Monster"
	end
	return "Human"
end

function DamageMath.UltForDamageDealt(role: string, amount: number, cfg: any?): number
	local c = cfg or Config.Ult
	if amount <= 0 then
		return 0
	end
	return amount * (if role == "Monster" then c.MonsterPerDamage else c.HumanPerDamage)
end

function DamageMath.UltForDamageTaken(role: string, amount: number, cfg: any?): number
	local c = cfg or Config.Ult
	if amount <= 0 or role == "Monster" then
		return 0
	end
	return amount * c.HumanOnHitTaken
end

function DamageMath.UltForHeal(role: string, amount: number, cfg: any?): number
	local c = cfg or Config.Ult
	if amount <= 0 or role == "Monster" then
		return 0
	end
	return amount * c.HumanPerHeal
end

function DamageMath.UltPerSecond(role: string, cfg: any?): number
	local c = cfg or Config.Ult
	return if role == "Monster" then c.MonsterPerSecond else c.HumanPerSecond
end

function DamageMath.AddUlt(current: number, gain: number): number
	return clamp(current + gain, 0, DamageMath.UltMax)
end

return DamageMath
