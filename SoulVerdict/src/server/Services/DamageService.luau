--!strict
-- DamageService (P15): the ONLY writer of Humanoid.Health (SPEC §7.5, §17).
--
-- Apply(info) pipeline:
--   1 validity   target alive (not Dead); Downed humans: any monster damage (or environment "True")
--                kills them (CharacterService.Kill), anything else is ignored; Invulnerable / IFrames ->
--                immune (Kind "Box" passes Invulnerable; "True" passes IFrames); Boxed targets only take
--                Kind "Box"; Teams.AreEnemyTeams(attackerTeam, targetTeam) unless the source is the environment
--   2 colour     Blue hurts only if the target's horizontal speed > Config.Combat.MoveThreshold, Orange only if <=
--   3 Before hooks (kits): may cancel (negate) or modify (state.Mult / state.Bonus / state.Undodgeable ...)
--   4 monster lazy dodge: Dodges >= 1, dodgeable hit (not True/Box/Undodgeable/ultimate), monster not
--                Stunned/Exhausted/Rage, attacker without Undodgeable/StealthStrike -> consume 1 dodge,
--                regen delay restarts, 0 left -> Exhausted (Config.Monster.ExhaustTime), "MISS" DamageFx
--   5 human block/parry: Blocking + source in front (Config.Human.BlockAngleDot) + blockable kind ->
--                perfect parry if the block started <= ParryWindow ago and Kind is Melee/Projectile (negate,
--                stun melee attacker ParryStun, +Guard, +Ult), else reduce by BlockReduction and drain Guard
--                by the blocked amount; Guard <= 0 -> guard break (Stunned GuardBreakStun)
--   6 multipliers (not for True/Box): attacker StatusService.DamageMult (DamageUp/Rage/Surge/SecondWind),
--                Harmony (RoundState attribute "Harmony") for human attackers, StealthStrike (consumed),
--                hook Bonus/Mult; target StatusService.IncomingMult (DamageDown, Exhausted ...)
--   7 Shielded absorb   8 health (Determined / Box -> min HP 1; monster before FinalPhase -> min HP 1)
--   9 HP <= 0: human -> Downed (CharacterService.SetDowned) when RoundState.TeamRevives > 0 during
--                Round/Collapse and not already downed, else CharacterService.Kill; others -> Kill.
--                Monster crossing Config.Round.FinalPhaseHpFraction -> RoundService.TriggerFinalPhase()
--  10 KR: humans hit by an attacker gain info.KR (x attacker KRBoost data.mult [2], x(1-BlockReduction) when
--                blocked), cap Config.KR.Max; a human attacker landing a hit loses Config.KR.CleanseOnHit KR
--  11 stun (not when blocked) / knockback (halved when blocked) via StatusService / MovementService
--  12 ult gain (Config.Ult) for both sides, stats (StatsService.Add), After hooks, Damaged signal, DamageFx
--
-- Hooks: DamageService.AddHook("Before" | "After", fn(info, result, state) -> boolean?) -> remover()
--   Before hooks run after validity + colour rule; returning true (or setting state.Cancel = true) negates
--   the hit (state.CancelReason is sent to clients as DamageFx.negated). They may also edit:
--     state.Amount (raw amount), state.Mult (extra factor), state.Bonus (additive outgoing bonus, 0.12 = +12 %),
--     state.KRMult, state.Undodgeable, state.Unblockable, state.Silent.
--   After hooks run once the hit is resolved (also for dodged / parried / blocked hits); `result` is final.
--   state also carries: Now, Stage, AttackerTeam, TargetTeam, IsUlt, Kind. Hooks must not yield.
--
-- API
--   DamageService.Apply(info: DamageInfo) -> DamageResult
--   DamageService.Heal(target, amount, source?, opts? {Silent: boolean?}) -> number (healed)
--   DamageService.AddKR(target, amount) -> number (new KR)
--   DamageService.CleanseKR(target, amount?) -> number (removed; nil amount = all)
--   DamageService.DrainDodges(monster, count, source?) -> number (drained)
--   DamageService.SetHealth(model, hp)                     (revive / spawn helpers for other services)
--   DamageService.TickKR(model, dt)                        (called by StatusService's 10 Hz tick)
--   DamageService.AddHook(stage, fn) -> remover
--   Signals: Damaged(info, result), Healed(target, amount, source), Parried(defender, attacker),
--            Dodged(monster, attacker)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Net = require(Shared.Net) :: any
local Signal = require(Shared.Util.Signal) :: any
local Kits = require(Shared.Kits) :: any
local Teams = require(Shared.Combat.Teams) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any

local Validation = require(script.Parent.Parent.Combat.Validation) :: any

local DamageService = {}
DamageService.Priority = 15
DamageService.Damaged = Signal.new()
DamageService.Healed = Signal.new()
DamageService.Parried = Signal.new()
DamageService.Dodged = Signal.new()

local StatusService: any = nil
local MovementService: any = nil

local MAX_AMOUNT = 10000
local PARRY_GRACE = 0.05 -- latency allowance on top of Config.Human.ParryWindow

local KINDS = { Melee = true, Projectile = true, Beam = true, Area = true, True = true, Box = true }
local BLOCKABLE_BY_DEFAULT = { Melee = true, Projectile = true, Beam = true }

type Hook = (any, any, any) -> boolean?
local beforeHooks: { Hook } = {}
local afterHooks: { Hook } = {}

---------------------------------------------------------------------------------------------------
-- Helpers

local function numAttr(model: Instance, name: string, default: number): number
	local v = model:GetAttribute(name)
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local function round1(x: number): number
	return math.floor(x * 10 + 0.5) / 10
end

local function addStat(model: Model?, stat: string, amount: number)
	if model == nil or amount == 0 then
		return
	end
	local stats = Validation.Service("StatsService")
	if stats and type(stats.Add) == "function" then
		pcall(stats.Add, model, stat, amount)
	end
end

local function addUlt(model: Model?, amount: number)
	if model == nil or amount <= 0 or model.Parent == nil then
		return
	end
	local cur = model:GetAttribute("Ult")
	if type(cur) ~= "number" then
		return
	end
	model:SetAttribute("Ult", DamageMath.AddUlt(cur, amount))
end

local function isUltAbility(attacker: Model?, abilityId: string?): boolean
	if attacker == nil or abilityId == nil then
		return false
	end
	local kitId = attacker:GetAttribute("KitId")
	if type(kitId) ~= "string" then
		return false
	end
	local def = Kits.Ability(kitId, abilityId)
	return def ~= nil and def.Ult == true
end

local function killModel(target: Model, attacker: Model?, ability: string?)
	local cs = Validation.Service("CharacterService")
	if cs and type(cs.Kill) == "function" then
		local ok, err = pcall(cs.Kill, target, attacker, ability)
		if ok then
			return
		end
		warn("[DamageService] CharacterService.Kill failed: " .. tostring(err))
	end
	-- fallback: mark dead ourselves
	target:SetAttribute("Dead", true)
	local hum = Validation.Humanoid(target)
	if hum then
		hum.Health = 0
	end
end

local function downModel(target: Model, attacker: Model?): boolean
	local cs = Validation.Service("CharacterService")
	if cs and type(cs.SetDowned) == "function" then
		local ok, err = pcall(cs.SetDowned, target, attacker)
		if ok then
			return true
		end
		warn("[DamageService] CharacterService.SetDowned failed: " .. tostring(err))
	end
	return false
end

local function canBeDowned(target: Model): boolean
	if target:GetAttribute("Downed") == true then
		return false
	end
	if not Validation.InCombatPhase() then
		return false
	end
	local revives = Validation.RoundAttr("TeamRevives")
	return type(revives) == "number" and revives > 0
end

-- True while `monster` is the round's monster and its desperation phase has not started yet: it cannot die
-- before RoundService.TriggerFinalPhase (HP floor 1).
local function finalPhasePending(monster: Model): boolean
	if not Validation.InCombatPhase() or Validation.RoundAttr("FinalPhase") ~= false then
		return false
	end
	local rs = Validation.Service("RoundService")
	if rs and type(rs.GetMonster) == "function" then
		local ok, current = pcall(rs.GetMonster)
		if ok and current ~= nil and current ~= monster then
			return false
		end
	end
	return true
end

local function broadcastFx(packet: { [string]: any })
	Net.Server.FireAll("DamageFx", packet)
end

local function fxPosition(target: Model, info: any): Vector3
	local pos = Validation.RootPosition(target)
	if pos then
		return pos + Vector3.new(0, 1.5, 0)
	end
	if typeof(info.Position) == "Vector3" then
		return info.Position
	end
	return Vector3.zero
end

local function runHooks(list: { Hook }, info: any, result: any, state: any, stage: string)
	state.Stage = stage
	for _, fn in table.clone(list) do
		local ok, ret = pcall(fn, info, result, state)
		if not ok then
			warn(("[DamageService] %s hook failed: %s"):format(stage, tostring(ret)))
		elseif ret == true and stage == "Before" then
			state.Cancel = true
		end
		if state.Cancel and stage == "Before" then
			return
		end
	end
end

local function newResult(): any
	return {
		Applied = 0,
		Dodged = false,
		Blocked = false,
		Parried = false,
		Killed = false,
		Downed = false,
		Absorbed = 0,
		Reason = nil,
		KR = 0,
		GuardBroken = false,
	}
end

local function sourcePosition(info: any): Vector3?
	if info.Attacker then
		local p = Validation.RootPosition(info.Attacker)
		if p then
			return p
		end
	end
	if typeof(info.Position) == "Vector3" then
		return info.Position
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Hooks

function DamageService.AddHook(stage: string, fn: Hook): () -> ()
	assert(stage == "Before" or stage == "After", "DamageService.AddHook: stage must be Before or After")
	assert(type(fn) == "function", "DamageService.AddHook: fn must be a function")
	local list = if stage == "Before" then beforeHooks else afterHooks
	table.insert(list, fn)
	return function()
		local i = table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Apply

local function finish(info: any, result: any, state: any, fx: { [string]: any }?)
	runHooks(afterHooks, info, result, state, "After")
	DamageService.Damaged:Fire(info, result)
	if fx and not info.Silent and not state.Silent then
		broadcastFx(fx)
	end
	return result
end

function DamageService.Apply(info: any): any
	local result = newResult()
	if type(info) ~= "table" then
		result.Reason = "Invalid"
		return result
	end
	local target = info.Target
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not Validation.IsAlive(target) then
		result.Reason = "Invalid"
		return result
	end
	local kind = info.Kind
	if not KINDS[kind] then
		kind = "Melee"
		info.Kind = kind
	end
	local amount = info.Amount
	if type(amount) ~= "number" or amount ~= amount then
		amount = 0
	end
	amount = math.clamp(amount, 0, MAX_AMOUNT)

	local attacker: Model? = nil
	if typeof(info.Attacker) == "Instance" and info.Attacker:IsA("Model") then
		attacker = info.Attacker
	else
		info.Attacker = nil
	end
	local attackerTeam: string = if type(info.AttackerTeam) == "string"
		then info.AttackerTeam
		else Teams.TeamOf(attacker)
	local targetTeam: string = Teams.TeamOf(target)
	local environment = attacker == nil and attackerTeam == ""
	local now = Validation.Now()

	-- 1. validity ---------------------------------------------------------------------------------
	if not environment and attacker ~= target then
		if not Teams.AreEnemyTeams(attackerTeam, targetTeam) then
			result.Reason = "Team"
			return result
		end
	end
	if target:GetAttribute("Downed") == true then
		if attackerTeam == "Monster" or (environment and kind == "True") then
			local downedHum = Validation.Humanoid(target)
			if downedHum then
				downedHum.Health = 0
			end
			killModel(target, attacker, info.Ability)
			result.Killed = true
			local state = { Now = now, AttackerTeam = attackerTeam, TargetTeam = targetTeam, Kind = kind }
			return finish(info, result, state, {
				target = target,
				attacker = attacker,
				amount = 0,
				kind = kind,
				color = info.Color,
				pos = fxPosition(target, info),
				killed = true,
				ability = info.Ability,
			})
		end
		result.Reason = "Immune"
		return result
	end
	-- Verdict Box damage passes Invulnerable (the box makes its victim invulnerable to everything else)
	if kind ~= "Box" then
		if StatusService.Has(target, "Invulnerable") or StatusService.Has(target, "Boxed") then
			result.Reason = "Immune"
			return result
		end
		if kind ~= "True" and StatusService.Has(target, "IFrames") then
			result.Reason = "Immune"
			return result
		end
	end

	-- 2. colour rule --------------------------------------------------------------------------------
	local color = info.Color
	if color == "Blue" or color == "Orange" then
		if not DamageMath.ColorHurts(color, Validation.HorizontalSpeed(target), Config.Combat.MoveThreshold) then
			result.Reason = "Color"
			return result
		end
	end

	local isUlt = isUltAbility(attacker, info.Ability)
	local state = {
		Now = now,
		Stage = "Before",
		AttackerTeam = attackerTeam,
		TargetTeam = targetTeam,
		Kind = kind,
		IsUlt = isUlt,
		Amount = amount,
		Mult = 1,
		Bonus = 0,
		KRMult = 1,
		Undodgeable = info.Undodgeable == true,
		Unblockable = false,
		Cancel = false,
		CancelReason = nil :: string?,
		Silent = false,
	}

	-- 3. Before hooks -------------------------------------------------------------------------------
	runHooks(beforeHooks, info, result, state, "Before")
	if state.Cancel then
		result.Reason = "Cancelled"
		return finish(info, result, state, {
			target = target,
			attacker = attacker,
			amount = 0,
			kind = kind,
			color = color,
			pos = fxPosition(target, info),
			negated = state.CancelReason or "Negated",
			ability = info.Ability,
		})
	end
	amount = math.clamp(
		if type(state.Amount) == "number" and state.Amount == state.Amount then state.Amount else amount,
		0,
		MAX_AMOUNT
	)

	-- 4. monster lazy dodge -------------------------------------------------------------------------
	if targetTeam == "Monster" and kind ~= "True" and kind ~= "Box" then
		local dodges = numAttr(target, "Dodges", 0)
		local dodgeable = info.Dodgeable ~= false
			and not state.Undodgeable
			and not isUlt
			and not (attacker ~= nil and (StatusService.Has(attacker, "Undodgeable") or StatusService.Has(
				attacker,
				"StealthStrike"
			)))
			and not StatusService.Has(target, "Stunned")
			and not StatusService.Has(target, "Exhausted")
			and not StatusService.Has(target, "Rage")
		if dodgeable and dodges >= 1 then
			local dstate = {
				Dodges = dodges,
				Max = numAttr(target, "MaxDodges", dodges),
				LastDodge = now,
				Acc = 0,
				ExhaustedUntil = 0,
			}
			local exhausted = DamageMath.ConsumeDodge(dstate, now)
			target:SetAttribute("Dodges", dstate.Dodges)
			StatusService.NoteDodge(target)
			if exhausted then
				StatusService.Apply(target, "Exhausted", Config.Monster.ExhaustTime)
			end
			result.Dodged = true
			DamageService.Dodged:Fire(target, attacker)
			addStat(attacker, "DodgesForced", 1)
			return finish(info, result, state, {
				target = target,
				attacker = attacker,
				amount = 0,
				kind = kind,
				color = color,
				dodged = true,
				pos = fxPosition(target, info),
				ability = info.Ability,
			})
		end
	end

	-- 5. human block / parry ------------------------------------------------------------------------
	local blocked = false
	if (targetTeam == "Humans" or targetTeam == "Lobby") and target:GetAttribute("Blocking") == true then
		local blockable = info.Blockable
		if blockable == nil then
			blockable = BLOCKABLE_BY_DEFAULT[kind] == true
		end
		if blockable and not state.Unblockable then
			local src = sourcePosition(info)
			local root = Validation.Root(target)
			local facing = true
			if src and root then
				facing =
					DamageMath.IsFacing(root.CFrame.Position, root.CFrame.LookVector, src, Config.Human.BlockAngleDot)
			end
			if facing then
				local blockStart = target:GetAttribute("BlockStart")
				local bs = if type(blockStart) == "number" then blockStart else 0
				if DamageMath.IsParry(bs, now, Config.Human.ParryWindow + PARRY_GRACE, kind) then
					result.Parried = true
					if kind == "Melee" and attacker and Validation.IsAlive(attacker) then
						StatusService.Apply(attacker, "Stunned", Config.Human.ParryStun)
					end
					local maxGuard = numAttr(target, "MaxGuard", Config.Human.MaxGuard)
					local guard = numAttr(target, "Guard", maxGuard)
					target:SetAttribute("Guard", math.min(maxGuard, guard + Config.Human.ParryGuardGain))
					addUlt(target, Config.Human.ParryUltGain)
					DamageService.Parried:Fire(target, attacker)
					addStat(target, "Parries", 1)
					return finish(info, result, state, {
						target = target,
						attacker = attacker,
						amount = 0,
						kind = kind,
						color = color,
						parried = true,
						pos = fxPosition(target, info),
						ability = info.Ability,
					})
				end
				local taken, blockedAmount = DamageMath.BlockSplit(amount, Config.Human.BlockReduction)
				local maxGuard = numAttr(target, "MaxGuard", Config.Human.MaxGuard)
				local guard = numAttr(target, "Guard", maxGuard)
				local newGuard, broken = DamageMath.GuardAfterBlock(guard, blockedAmount)
				target:SetAttribute("Guard", round1(newGuard))
				StatusService.NoteGuardHit(target)
				amount = taken
				blocked = true
				result.Blocked = true
				if broken then
					result.GuardBroken = true
					target:SetAttribute("Blocking", false)
					target:SetAttribute("BlockStart", 0)
					StatusService.Apply(target, "Stunned", Config.Human.GuardBreakStun)
				end
			end
		end
	end

	-- 6. multipliers --------------------------------------------------------------------------------
	if kind ~= "True" and kind ~= "Box" then
		local outs = { StatusService.DamageMult(attacker) }
		if attackerTeam == "Humans" then
			table.insert(outs, DamageMath.HarmonyFromAttribute(Validation.RoundAttr("Harmony")))
		end
		if attacker and StatusService.Has(attacker, "StealthStrike") then
			local _, data = StatusService.Get(attacker, "StealthStrike")
			local m = if data and type(data.mult) == "number" then data.mult else 1.6
			table.insert(outs, m)
			StatusService.Remove(attacker, "StealthStrike")
		end
		if type(state.Bonus) == "number" and state.Bonus ~= 0 then
			table.insert(outs, 1 + state.Bonus)
		end
		local outMult = DamageMath.OutgoingMult(outs)
		local extra = if type(state.Mult) == "number" and state.Mult == state.Mult then math.max(0, state.Mult) else 1
		amount = amount * outMult * extra * StatusService.IncomingMult(target)
	end

	-- 7. shield -------------------------------------------------------------------------------------
	if amount > 0 and StatusService.Has(target, "Shielded") then
		local _, data = StatusService.Get(target, "Shielded")
		local shield = if data and type(data.amount) == "number" then data.amount else 0
		local remaining, absorbed, left = DamageMath.AbsorbShield(amount, shield)
		amount = remaining
		result.Absorbed = absorbed
		if left <= 0 then
			StatusService.Remove(target, "Shielded")
		else
			local newData = table.clone(data or {})
			newData.amount = left
			StatusService.SetData(target, "Shielded", newData)
		end
	end

	-- 8. health ---------------------------------------------------------------------------------------
	local hum = Validation.Humanoid(target) :: Humanoid
	local hp = hum.Health
	local minHp = 0
	if kind == "Box" or StatusService.Has(target, "Determined") then
		minHp = 1
	end
	if targetTeam == "Monster" and finalPhasePending(target) then
		minHp = math.max(minHp, 1)
	end
	local newHp, applied = DamageMath.ApplyHealth(hp, amount, minHp)
	result.Applied = applied

	-- 9. downed / death / final phase ------------------------------------------------------------------
	-- NOTE: Health 0 kills a Humanoid irrevocably, so the downed path goes straight to 1 HP.
	if applied > 0 and newHp <= 0 then
		if targetTeam == "Dummy" then
			hum.Health = hum.MaxHealth -- training dummies never die: they refill
			result.Killed = true
		elseif targetTeam == "Humans" and canBeDowned(target) then
			hum.Health = 1
			if downModel(target, attacker) then
				result.Downed = true
			else
				hum.Health = 0
				killModel(target, attacker, info.Ability)
				result.Killed = true
			end
		else
			hum.Health = 0
			killModel(target, attacker, info.Ability)
			result.Killed = true
		end
	elseif applied > 0 then
		hum.Health = newHp
	end
	if targetTeam == "Monster" and applied > 0 and not result.Killed and finalPhasePending(target) then
		if newHp <= hum.MaxHealth * Config.Round.FinalPhaseHpFraction then
			local rs = Validation.Service("RoundService")
			if rs and type(rs.TriggerFinalPhase) == "function" then
				task.spawn(function()
					local ok, err = pcall(rs.TriggerFinalPhase)
					if not ok then
						warn("[DamageService] TriggerFinalPhase failed: " .. tostring(err))
					end
				end)
			end
		end
	end

	-- 10. KR ------------------------------------------------------------------------------------------
	local landed = applied > 0 or result.Absorbed > 0
	if landed and not result.Killed and targetTeam == "Humans" and not result.Downed then
		local kr = info.KR
		if type(kr) == "number" and kr > 0 and kr == kr then
			local mult = if type(state.KRMult) == "number" then state.KRMult else 1
			if attacker and StatusService.Has(attacker, "KRBoost") then
				local _, data = StatusService.Get(attacker, "KRBoost")
				mult *= if data and type(data.mult) == "number" then data.mult else 2
			end
			if blocked then
				mult *= 1 - Config.Human.BlockReduction
			end
			if result.Absorbed > 0 and applied <= 0 then
				mult = 0 -- fully absorbed by a shield: no KR
			end
			local add = kr * mult
			if add > 0 then
				local before = numAttr(target, "KR", 0)
				local after = DamageMath.KRAdd(before, add)
				target:SetAttribute("KR", round1(after))
				result.KR = after - before
			end
		end
	end
	if landed and attackerTeam == "Humans" and attacker and attacker ~= target then
		local akr = numAttr(attacker, "KR", 0)
		if akr > 0 then
			attacker:SetAttribute("KR", round1(DamageMath.KRCleanse(akr, Config.KR.CleanseOnHit)))
		end
	end

	-- 11. stun / knockback ------------------------------------------------------------------------------
	if landed and not result.Killed then
		local stun = info.Stun
		if type(stun) == "number" and stun > 0 and not blocked and not result.Downed then
			StatusService.Apply(target, "Stunned", math.min(stun, 10))
		end
		local kb = info.Knockback
		if Validation.IsVector(kb, 500) and (kb :: Vector3).Magnitude > 0.5 and not result.Downed then
			local v = kb :: Vector3
			if blocked then
				v *= 0.5
			end
			MovementService.Send(target, { kind = "Impulse", velocity = v, duration = 0.2 })
		end
	end

	-- 12. ult / stats ------------------------------------------------------------------------------------
	if applied > 0 then
		if attacker and attacker ~= target then
			addUlt(attacker, DamageMath.UltForDamageDealt(Validation.Role(attacker), applied))
			addStat(attacker, "Damage", applied)
		end
		addUlt(target, DamageMath.UltForDamageTaken(Validation.Role(target), applied))
	end

	return finish(info, result, state, {
		target = target,
		attacker = attacker,
		amount = round1(applied),
		kind = kind,
		color = color,
		blocked = if result.Blocked then true else nil,
		pos = fxPosition(target, info),
		kr = if result.KR > 0 then round1(result.KR) else nil,
		ability = info.Ability,
		absorbed = if result.Absorbed > 0 then round1(result.Absorbed) else nil,
		killed = if result.Killed then true else nil,
		downed = if result.Downed then true else nil,
		guardBreak = if result.GuardBroken then true else nil,
	})
end

---------------------------------------------------------------------------------------------------
-- Heal / KR / dodges / health

function DamageService.Heal(target: Model, amount: number, source: Model?, opts: { Silent: boolean? }?): number
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not Validation.IsAlive(target) then
		return 0
	end
	if target:GetAttribute("Downed") == true then
		return 0 -- downed humans are only brought back by a revive
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	local hum = Validation.Humanoid(target) :: Humanoid
	local newHp, healed = DamageMath.ApplyHeal(hum.Health, hum.MaxHealth, math.min(amount, MAX_AMOUNT))
	if healed <= 0 then
		return 0
	end
	hum.Health = newHp
	if source and source ~= target and typeof(source) == "Instance" then
		addUlt(source, DamageMath.UltForHeal(Validation.Role(source), healed))
		addStat(source, "Healing", healed)
	end
	DamageService.Healed:Fire(target, healed, source)
	local silent = opts ~= nil and opts.Silent == true
	if not silent and healed >= 0.5 then
		broadcastFx({
			target = target,
			attacker = source,
			amount = round1(healed),
			kind = "Heal",
			color = "Green",
			pos = fxPosition(target, {}),
		})
	end
	return healed
end

function DamageService.AddKR(target: Model, amount: number): number
	local before = numAttr(target, "KR", 0)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or not Validation.IsAlive(target) then
		return before
	end
	local after = DamageMath.KRAdd(before, amount)
	target:SetAttribute("KR", round1(after))
	return after
end

function DamageService.CleanseKR(target: Model, amount: number?): number
	local before = numAttr(target, "KR", 0)
	if before <= 0 then
		return 0
	end
	local after = if amount == nil then 0 else DamageMath.KRCleanse(before, amount)
	target:SetAttribute("KR", round1(after))
	return before - after
end

function DamageService.DrainDodges(monster: Model, count: number, source: Model?): number
	local dodges = numAttr(monster, "Dodges", 0)
	if dodges <= 0 or count <= 0 or StatusService.Has(monster, "Exhausted") then
		return 0
	end
	local drained = math.min(dodges, math.floor(count))
	local left = dodges - drained
	monster:SetAttribute("Dodges", left)
	StatusService.NoteDodge(monster)
	if left <= 0 then
		StatusService.Apply(monster, "Exhausted", Config.Monster.ExhaustTime)
	end
	broadcastFx({
		target = monster,
		attacker = source,
		amount = drained,
		kind = "DodgeDrain",
		pos = fxPosition(monster, {}),
	})
	return drained
end

function DamageService.SetHealth(model: Model, hp: number)
	local hum = Validation.Humanoid(model)
	if hum == nil or type(hp) ~= "number" or hp ~= hp then
		return
	end
	hum.Health = math.clamp(hp, 0, hum.MaxHealth)
end

function DamageService.TickKR(model: Model, dt: number)
	local kr = numAttr(model, "KR", 0)
	if kr <= 0 then
		return
	end
	local hum = Validation.Humanoid(model)
	if hum == nil or hum.Health <= 0 then
		return
	end
	local newHp, newKr = DamageMath.KRStep(hum.Health, kr, dt)
	if newHp < hum.Health then
		hum.Health = newHp
	end
	model:SetAttribute("KR", if newKr <= 0 then 0 else math.floor(newKr * 100 + 0.5) / 100)
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

function DamageService.Init()
	StatusService = require(script.Parent.StatusService) :: any
	MovementService = require(script.Parent.MovementService) :: any
end

function DamageService.Start() end

return DamageService
