--!strict
-- Server kit: Determination (red SOUL) — "The Fallen". Numbers come from Shared/Kits/Humans/Determination.
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   KnifeCombo (M1)        Common.ComboStrike (Damage1..4, Range, Knockback on hit 4).          Fx "Strike"
--   LungingStrike (Q)      dash Distance along the aim in 0.22 s; every enemy on the swept path is hit once
--                          (segment capsule test) for Damage.                                    Fx "Dash" {from, to, time}
--   Afterimage (E)         status "Afterimage" for Window s + a quick step (Distance, along the cast direction);
--                          a hit landing during the window is negated (DamageFx.negated = "Afterimage"), the
--                          human gets 0.35 s IFrames and counter-slashes the attacker (<= 16 studs) for
--                          CounterDamage + CounterStun.                       Fx "Step" {from, window}, "Counter" {attacker}
--   DeterminationUlt (R)   Undodgeable + DamageUp {mult = DamageMult} + Determined (HP >= 1) for Duration.
--                          Fx "Burst" {duration}
-- Passive "Hope" (Stay Determined): +12 % damage while below 35 % HP (DamageService Before hook).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Teams = require(Shared.Combat.Teams) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local KIT_ID = "Determination"
local HOPE_BONUS = 0.12 -- kit text: "+12% damage while below 35% HP"
local HOPE_THRESHOLD = 0.35
local COUNTER_RANGE = 16
local COUNTER_IFRAMES = 0.35
local STEP_TIME = 0.15

---------------------------------------------------------------------------------------------------
-- Passive hooks (installed once per server, on the first Determination spawn)

local function installHooks()
	local services = Common.Services()
	local StatusService = services.StatusService
	local AbilityService = services.AbilityService

	-- Hope: +12 % outgoing damage while the attacker is below 35 % HP
	Common.InstallHook("Determination.Hope", "Before", function(info: any, _result: any, state: any)
		local attacker = info.Attacker
		if attacker == nil or attacker:GetAttribute("KitId") ~= KIT_ID then
			return nil
		end
		local hum = Validation.Humanoid(attacker)
		if hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth < HOPE_THRESHOLD then
			state.Bonus = (state.Bonus or 0) + HOPE_BONUS
		end
		return nil
	end)

	-- Afterimage: negate the hit and counter-slash
	Common.InstallHook("Determination.Afterimage", "Before", function(info: any, _result: any, state: any)
		local target = info.Target
		if info.Kind == "True" or info.Kind == "Box" or not StatusService.Has(target, "Afterimage") then
			return nil
		end
		local _, data = StatusService.Get(target, "Afterimage")
		StatusService.Remove(target, "Afterimage")
		StatusService.Apply(target, "IFrames", COUNTER_IFRAMES)
		state.CancelReason = "Afterimage"
		local attacker: Model? = info.Attacker
		if attacker and Teams.AreEnemies(target, attacker) and Validation.IsAlive(attacker) then
			local a = Validation.RootPosition(attacker)
			local b = Validation.RootPosition(target)
			if a and b and (a - b).Magnitude <= COUNTER_RANGE then
				local counterDamage = if data and type(data.counterDamage) == "number" then data.counterDamage else 20
				local counterStun = if data and type(data.counterStun) == "number" then data.counterStun else 0.8
				-- resolve the counter after the current hit finishes
				Validation.Defer(function()
					if not Validation.IsUp(target) or not Validation.IsAlive(attacker) then
						return
					end
					local ctx = AbilityService.ContextFor(target, "Afterimage")
					if ctx == nil then
						return
					end
					ctx:Fx("Counter", { attacker = attacker })
					ctx:Damage(attacker, {
						Amount = counterDamage,
						Kind = "Melee",
						Stun = counterStun,
						Blockable = false,
						Position = Validation.RootPosition(target),
					})
				end)
			end
		end
		return true
	end)
end

local hooksInstalled = false

function Kit.OnSpawn(_model: Model, _ctxFactory: any)
	if not hooksInstalled then
		hooksInstalled = true
		installHooks()
	end
end

function Kit.OnDespawn(_model: Model) end

---------------------------------------------------------------------------------------------------
-- Abilities

Abilities.KnifeCombo = function(ctx: any)
	Common.ComboStrike(ctx)
end

Abilities.LungingStrike = function(ctx: any)
	local N = ctx.N
	Common.DashStrike(ctx, {
		Distance = N.Distance or 18,
		Time = 0.22,
		Damage = N.Damage or 16,
		Radius = 2.6,
	})
end

Abilities.Afterimage = function(ctx: any)
	if not hooksInstalled then
		hooksInstalled = true
		installHooks()
	end
	local N = ctx.N
	local window = N.Window or 0.5
	ctx:Status(ctx.Caster, "Afterimage", window, {
		counterDamage = N.CounterDamage or 20,
		counterStun = N.CounterStun or 0.8,
	})
	local from = ctx:RootPosition()
	ctx:Fx("Step", { from = from, window = window })
	local distance = Common.ClampPath(from, ctx.FlatDir, N.Distance or 8)
	if distance > 0.5 then
		ctx:ForceMove(
			ctx.Caster,
			{ kind = "Dash", velocity = ctx.FlatDir * (distance / STEP_TIME), duration = STEP_TIME }
		)
	end
end

Abilities.DeterminationUlt = function(ctx: any)
	local N = ctx.N
	local duration = N.Duration or 8
	ctx:Status(ctx.Caster, "Undodgeable", duration)
	ctx:Status(ctx.Caster, "DamageUp", duration, { mult = N.DamageMult or 1.2 })
	ctx:Status(ctx.Caster, "Determined", duration)
	ctx:Fx("Burst", { duration = duration })
end

return Kit
