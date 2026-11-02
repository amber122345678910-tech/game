--!strict
-- Server kit: Patience (cyan SOUL) — "The Quiet One", stealth assassin. Numbers come from
-- Shared/Kits/Humans/Patience (ctx.N); the constants below only shape feel (timings, hit sizes).
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   ToyKnife (M1)        three quick stabs: Common.ComboStrike with a narrow thrust box.     Fx "Strike" {combo, last, hits}
--   RibbonSnare (Q)      ribbon projectile (client visual "PatienceRibbon", Speed, Range). A snare cannot be lazily
--                        side-stepped: the contact is undodgeable, deals Damage, applies Slowed {mult = SlowMult} for
--                        SlowTime and DamageService.DrainDodges(DodgeDrain).   Fx "Throw" {id}, "Snare" {target, time}
--   Patience (E)         Invisible for Duration + StealthStrike {mult = BonusMult} (DamageService: the bearer's next
--                        hit x mult, undodgeable, consumed). Casting any other ability breaks the stealth; the
--                        StealthStrike then lingers AMBUSH_GRACE s so the attack that broke it carries the bonus.
--                        Downed -> stealth removed.  Fx "Fade" {duration}, "Reveal" {}, "Ambush" {target, pos}
--   WaitingGame (R)      Zone (visual "PatienceClock", effect "Slow", amount = SlowMult, radius Radius) at the ground
--                        aim for Duration: enemies inside are Slowed and AbilityService.ScaleCooldowns(CooldownMult)
--                        every FIELD_TICK. Sets attribute UltActiveUntil (client SOUL heart).
--                        Fx "Field" {center, radius, duration, id}
-- Passive "Calm": standing still (horizontal speed < CALM_SPEED for CALM_DELAY s) heals CALM_HPS HP/s, paid in
--   CALM_CHUNK s chunks (silent while invisible so the heal numbers never give the position away). Attribute
--   CalmActive (boolean) mirrors the state for client visuals.
-- Hooks (installed once per server): Before "Patience.AmbushMark" + After "Patience.AmbushFx" (ambush feedback),
--   AbilityService.Casted (stealth break), StatusService.OnTick (Calm, stealth cleanup when downed).

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local KIT_ID = "Patience"
local CALM_HPS = 3 -- kit text: "Standing still heals 3 HP per second"
local CALM_SPEED = 1.5 -- studs/s: below this the human counts as standing still
local CALM_DELAY = 0.5 -- seconds of stillness before the heal starts
local CALM_CHUNK = 1 -- seconds of healing paid at once (one readable "+3")
local AMBUSH_GRACE = 0.9 -- StealthStrike kept after a stealth-breaking cast (covers M1 windup / ribbon flight)
local STEALTH_TAIL = 0.25 -- StealthStrike outlives the natural end of the stealth by this much
local RIBBON_RADIUS = 0.9
local FIELD_TICK = 0.25
local FIELD_HEIGHT = 10

type CalmState = { Still: number, Acc: number, Active: boolean }
local tracked: { [Model]: CalmState } = setmetatable({}, { __mode = "k" }) :: any

Kit.Tuning = {
	CalmHps = CALM_HPS,
	CalmSpeed = CALM_SPEED,
	CalmDelay = CALM_DELAY,
	AmbushGrace = AMBUSH_GRACE,
	FieldTick = FIELD_TICK,
}

---------------------------------------------------------------------------------------------------
-- Stealth

-- Ends the stealth early (the human attacked). The StealthStrike stays for AMBUSH_GRACE s.
local function reveal(model: Model)
	local services = Common.Services()
	local SS = services.StatusService
	SS.Remove(model, "Invisible")
	if SS.Has(model, "StealthStrike") then
		local endsAt, data = SS.Get(model, "StealthStrike")
		local left = (endsAt or 0) - Validation.Now()
		if left > AMBUSH_GRACE then
			SS.Remove(model, "StealthStrike")
			SS.Apply(model, "StealthStrike", AMBUSH_GRACE, data)
		end
	end
	local ctx = services.AbilityService.ContextFor(model, "Patience")
	if ctx then
		ctx:Fx("Reveal", {})
	end
end
Kit.Reveal = reveal

---------------------------------------------------------------------------------------------------
-- Passive / hooks (installed once per server, on the first Patience spawn or cast)

local function calmTick(dt: number)
	local services = Common.Services()
	local SS = services.StatusService
	local DS = services.DamageService
	for model, st in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			continue
		end
		local up = Validation.IsUp(model)
		if not up and (SS.Has(model, "Invisible") or SS.Has(model, "StealthStrike")) then
			-- a downed / dead human never stays hidden (the monster must be able to finish or see them)
			SS.Remove(model, "Invisible")
			SS.Remove(model, "StealthStrike")
		end
		local still = up and Validation.HorizontalSpeed(model) < CALM_SPEED
		local hum = Validation.Humanoid(model)
		local hurt = hum ~= nil and hum.Health > 0 and hum.Health < hum.MaxHealth
		if still then
			st.Still += dt
		else
			st.Still = 0
		end
		local active = still and hurt and st.Still >= CALM_DELAY
		local silent = SS.Has(model, "Invisible")
		if active then
			st.Acc += CALM_HPS * dt
			if st.Acc >= CALM_HPS * CALM_CHUNK - 1e-6 then
				DS.Heal(model, st.Acc, model, { Silent = silent })
				st.Acc = 0
			end
		elseif st.Acc > 0 then
			-- moved (or got healed to full): pay what was earned
			if st.Acc >= 0.5 and up then
				DS.Heal(model, st.Acc, model, { Silent = true })
			end
			st.Acc = 0
		end
		if active ~= st.Active then
			st.Active = active
			model:SetAttribute("CalmActive", active)
		end
	end
end

local hooksInstalled = false

local function installHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	local services = Common.Services()
	local StatusService = services.StatusService
	local AbilityService = services.AbilityService

	-- Ambush feedback: remember that the hit left stealth (StealthStrike is consumed later in the pipeline) ...
	Common.InstallHook("Patience.AmbushMark", "Before", function(info: any, _result: any, state: any)
		local attacker = info.Attacker
		if attacker and attacker:GetAttribute("KitId") == KIT_ID and StatusService.Has(attacker, "StealthStrike") then
			state.PatienceAmbush = true
		end
		return nil
	end)
	-- ... and announce it once the hit resolved
	Common.InstallHook("Patience.AmbushFx", "After", function(info: any, result: any, state: any)
		if not state.PatienceAmbush or (result.Applied or 0) + (result.Absorbed or 0) <= 0 then
			return nil
		end
		local attacker: Model = info.Attacker
		local target: Model = info.Target
		Validation.Defer(function()
			if attacker.Parent == nil then
				return
			end
			local ctx = AbilityService.ContextFor(attacker, "Patience")
			if ctx then
				ctx:Fx("Ambush", {
					target = target,
					pos = Validation.RootPosition(target) or info.Position,
					amount = result.Applied,
				})
			end
		end)
		return nil
	end)

	-- the stealth breaks on attack (any cast but the stealth itself; blocking / dashing keep it)
	AbilityService.Casted:Connect(function(model: Model, abilityId: string)
		if
			abilityId ~= "Patience"
			and model:GetAttribute("KitId") == KIT_ID
			and StatusService.Has(model, "Invisible")
		then
			reveal(model)
		end
	end)

	StatusService.OnTick(function(dt: number, _now: number)
		calmTick(dt)
	end)
end
Kit.InstallHooks = installHooks

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	installHooks()
	tracked[model] = { Still = 0, Acc = 0, Active = false }
	model:SetAttribute("CalmActive", false)
	model:SetAttribute("UltActiveUntil", 0)
end

function Kit.OnDespawn(model: Model)
	tracked[model] = nil
end

---------------------------------------------------------------------------------------------------
-- Abilities

Abilities.ToyKnife = function(ctx: any)
	-- a stab is a thrust: narrower than a slash, same reach
	Common.ComboStrike(ctx, { Width = 3.2 })
end

Abilities.RibbonSnare = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.18
	if not ctx:Wait(windup) then
		return
	end
	local damage = N.Damage or 6
	local slowMult = N.SlowMult or 0.6
	local slowTime = N.SlowTime or 2.5
	local drain = N.DodgeDrain or 1
	local DamageService = Common.Services().DamageService
	local id = ctx:Projectile({
		Speed = N.Speed or 80,
		Radius = RIBBON_RADIUS,
		Range = ctx.Ability.Range or 45,
		Damage = damage,
		Color = "Cyan",
		Visual = "PatienceRibbon",
		Undodgeable = true,
		Hooks = {
			OnHit = function(target: Model, _hazardId: number): boolean?
				local result = ctx:Damage(target, {
					Amount = damage,
					Kind = "Projectile",
					Color = "Cyan",
					Undodgeable = true,
					Position = Validation.RootPosition(target),
				})
				if result.Reason == nil then
					ctx:Status(target, "Slowed", slowTime, { mult = slowMult })
					if drain > 0 then
						DamageService.DrainDodges(target, drain, ctx.Caster)
					end
					ctx:Fx("Snare", { target = target, time = slowTime })
				end
				return true -- damage handled here (the projectile still ends on this hit)
			end,
		},
	})
	ctx:Fx("Throw", { id = id })
end

Abilities.Patience = function(ctx: any)
	installHooks()
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.2
	if not ctx:Wait(windup) then
		return
	end
	local duration = N.Duration or 6
	ctx:Status(ctx.Caster, "Invisible", duration)
	ctx:Status(ctx.Caster, "StealthStrike", duration + STEALTH_TAIL, { mult = N.BonusMult or 1.6 })
	ctx:Fx("Fade", { duration = duration })
end

Abilities.WaitingGame = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.4
	if not ctx:Wait(windup) then
		return
	end
	local AbilityService = Common.Services().AbilityService
	local center = Common.GroundAim(ctx)
	local radius = N.Radius or 16
	local duration = N.Duration or 6
	local cdMult = N.CooldownMult or 0.5
	local delay = 0.25
	local id = ctx:Hazard("Zone", {
		center = center,
		radius = radius,
		height = FIELD_HEIGHT,
		delay = delay,
		duration = duration,
		tick = FIELD_TICK,
		effect = "Slow",
		amount = N.SlowMult or 0.5,
		affects = "Enemies",
		visual = "PatienceClock",
		color = "Cyan",
		damage = 0,
		linger = 0.6,
	}, {
		OnHit = function(target: Model, _hazardId: number): boolean?
			-- time itself drags for the monster: its cooldowns tick at CooldownMult speed while inside
			AbilityService.ScaleCooldowns(target, cdMult, FIELD_TICK + 0.15)
			return nil -- keep the default Slow effect
		end,
	})
	ctx.Caster:SetAttribute("UltActiveUntil", ctx:Now() + delay + duration)
	ctx:Fx("Field", { center = center, radius = radius, duration = duration, delay = delay, id = id })
end

return Kit
