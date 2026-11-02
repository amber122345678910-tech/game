--!strict
-- Server kit: Kindness (green SOUL) — "The Cook". Healer / support. Numbers come from
-- Shared/Kits/Humans/Kindness (ctx.N); the constants below only shape hitboxes and timing.
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   PanBonk (M1)              Common.ComboStrike (Damage1..3, Range; the 3rd swing stuns for Daze s).
--                             Fx "Strike" {combo, last, hits}; on a landed 3rd swing "Bonk" {targets, daze}
--   HomeCooking (Q)           tosses a dish to the ground under the aim (arc time from the distance); it becomes a
--                             Zone hazard (effect Heal, affects Allies incl. self, visual "HomeCooking"): heals
--                             HealPerSecond (ticks of ZONE_TICK s) and removes ALL KR every tick for Duration s.
--                             The zone telegraph is the dish's flight (delay = flight time).
--                             Fx "Throw" {from, to, time, radius}
--   KindShield (E)            Shielded {amount = Amount} for Duration s on the aimed ally (Aim "Ally": the server
--                             validated ctx.Target; self when none). Fx "Shield" {target, duration, amount}
--   ButterscotchFeast (R,ult) after Windup: every up ally within Radius (incl. self) is healed Heal, loses all KR and
--                             debuffs (StatusService.Cleanse) and gets Hasted {mult = SpeedMult} for SpeedTime; the
--                             nearest DOWNED ally in range is revived through CharacterService.Revive (uses the team
--                             revive budget like a manual revive) and fed too. Caster status "Feast" (SOUL glow).
--                             Fx "Feast" {radius, allies, revived?, heal}
-- Passive "Nurturing": every NURTURE_PERIOD s (StatusService tick) each up Kindness heals every OTHER up ally within
--   NURTURE_RADIUS for NURTURE_HPS x period (silent heals; the client draws the regen motes itself).

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Teams = require(Shared.Combat.Teams) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local NURTURE_RADIUS = 8 -- kit text: "Allies within 8 studs regenerate 1 HP per second"
local NURTURE_HPS = 1
local NURTURE_PERIOD = 1
local ZONE_TICK = 0.5
local ZONE_HEIGHT = 7
local THROW_SPEED = 48 -- studs/s (horizontal) of the tossed dish
local THROW_MIN, THROW_MAX = 0.3, 0.75
local KR_CLEANSE_PER_TICK = 1000 -- "removes KR": everything, every tick

local function windupOf(ctx: any, default: number): number
	local w = ctx.Ability.Windup
	return if type(w) == "number" then w else default
end

---------------------------------------------------------------------------------------------------
-- Passive: Nurturing (one StatusService tick hook for every Kindness on the server)

local nurturers: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- model -> accumulated seconds
local tickInstalled = false

local function nurture(model: Model)
	local pos = Validation.RootPosition(model)
	if pos == nil then
		return
	end
	local DamageService = Common.Services().DamageService
	for _, m in Validation.Combatants() do
		if m ~= model and Validation.IsUp(m) and Teams.AreAllies(model, m) then
			local p = Validation.RootPosition(m)
			if p and (p - pos).Magnitude <= NURTURE_RADIUS then
				DamageService.Heal(m, NURTURE_HPS * NURTURE_PERIOD, model, { Silent = true })
			end
		end
	end
end

local function installTick()
	if tickInstalled then
		return
	end
	tickInstalled = true
	Common.Services().StatusService.OnTick(function(dt: number, _now: number)
		for model, acc in nurturers do
			if model.Parent == nil then
				nurturers[model] = nil
			elseif not Validation.IsUp(model) then
				nurturers[model] = 0
			else
				local total = acc + dt
				if total >= NURTURE_PERIOD - 1e-6 then
					total = math.max(0, total - NURTURE_PERIOD)
					nurture(model)
				end
				nurturers[model] = math.min(total, NURTURE_PERIOD)
			end
		end
	end)
end

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	installTick()
	nurturers[model] = 0
end

function Kit.OnDespawn(model: Model)
	nurturers[model] = nil
end

---------------------------------------------------------------------------------------------------
-- PanBonk (M1)

Abilities.PanBonk = function(ctx: any)
	local hits, results = Common.ComboStrike(ctx)
	local comboLength = if type(ctx.Ability.Combo) == "number" then ctx.Ability.Combo else 3
	if (ctx.ComboIndex or 1) >= comboLength then
		local bonked: { Model } = {}
		for _, m in hits do
			local r = results[m]
			if r and not r.Blocked and ((r.Applied or 0) > 0 or (r.Absorbed or 0) > 0) then
				table.insert(bonked, m)
			end
		end
		if #bonked > 0 then
			ctx:Fx("Bonk", { targets = bonked, daze = ctx.N.Daze or 0.4 })
		end
	end
end

---------------------------------------------------------------------------------------------------
-- HomeCooking (Q)

Abilities.HomeCooking = function(ctx: any)
	local N = ctx.N
	if not ctx:Wait(windupOf(ctx, 0.2)) then
		return
	end
	local center = Common.GroundAim(ctx)
	local from = ctx:RootPosition() + ctx.FlatDir * 1.2 + Vector3.new(0, 1.2, 0)
	local flat = Vector3.new(center.X - from.X, 0, center.Z - from.Z).Magnitude
	local flight = math.clamp(flat / THROW_SPEED, THROW_MIN, THROW_MAX)
	local radius = N.Radius or 9
	local duration = N.Duration or 5
	ctx:Fx("Throw", { from = from, to = center, time = flight, radius = radius })
	ctx:Hazard("Zone", {
		center = center,
		radius = radius,
		height = ZONE_HEIGHT,
		delay = flight,
		duration = duration,
		tick = ZONE_TICK,
		effect = "Heal",
		amount = (N.HealPerSecond or 6) * ZONE_TICK,
		affects = "Allies",
		cleanseKR = KR_CLEANSE_PER_TICK,
		color = "Green",
		visual = "HomeCooking",
		damage = 0,
	})
end

---------------------------------------------------------------------------------------------------
-- KindShield (E)

Abilities.KindShield = function(ctx: any)
	local N = ctx.N
	local target: Model = ctx.Caster
	local t = ctx.Target
	if t and t ~= ctx.Caster and Validation.IsUp(t) and Teams.AreAllies(ctx.Caster, t) then
		target = t
	end
	if not ctx:Wait(windupOf(ctx, 0.1)) then
		return
	end
	if not Validation.IsUp(target) then
		target = ctx.Caster
	end
	local amount = N.Amount or 40
	local duration = N.Duration or 5
	ctx:Status(target, "Shielded", duration, { amount = amount })
	ctx:Fx("Shield", { target = target, duration = duration, amount = amount })
end

---------------------------------------------------------------------------------------------------
-- ButterscotchFeast (R, ultimate)

local function downedAllyNear(ctx: any, pos: Vector3, radius: number): Model?
	local best: Model? = nil
	local bestDist = radius
	for _, m in Validation.Combatants() do
		if
			m ~= ctx.Caster
			and m:GetAttribute("Downed") == true
			and Validation.IsAlive(m)
			and Teams.AreAllies(ctx.Caster, m)
		then
			local p = Validation.RootPosition(m)
			if p then
				local d = (p - pos).Magnitude
				if d <= bestDist then
					best = m
					bestDist = d
				end
			end
		end
	end
	return best
end

local function feed(ctx: any, m: Model, N: any)
	local services = Common.Services()
	ctx:Heal(m, N.Heal or 45)
	services.DamageService.CleanseKR(m)
	services.StatusService.Cleanse(m)
	ctx:Status(m, "Hasted", N.SpeedTime or 4, { mult = N.SpeedMult or 1.3 })
end

Abilities.ButterscotchFeast = function(ctx: any)
	local N = ctx.N
	local radius = N.Radius or 30
	ctx:Status(ctx.Caster, "Feast", windupOf(ctx, 0.4) + (N.SpeedTime or 4))
	if not ctx:Wait(windupOf(ctx, 0.4)) then
		return
	end
	local pos = ctx:RootPosition()
	local fed: { Model } = {}
	for _, m in ctx:Allies(true) do
		local p = Validation.RootPosition(m)
		if p and (p - pos).Magnitude <= radius then
			feed(ctx, m, N)
			table.insert(fed, m)
		end
	end
	local revived: Model? = nil
	local downed = downedAllyNear(ctx, pos, radius)
	local CharacterService = Validation.Service("CharacterService")
	if downed and CharacterService and type(CharacterService.Revive) == "function" then
		local ok, result = pcall(CharacterService.Revive, downed, ctx.Caster)
		if ok and result == true and Validation.IsUp(downed) then
			revived = downed
			feed(ctx, downed, N)
			table.insert(fed, downed)
		end
	end
	ctx:Fx("Feast", { radius = radius, allies = fed, revived = revived, heal = N.Heal or 45 })
end

return Kit
