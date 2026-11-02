--!strict
-- Server kit: Integrity (blue SOUL) — "The Dancer", mobility / disruption. Numbers come from
-- Shared/Kits/Humans/Integrity (ctx.N); the constants below only shape feel (timings, hit sizes).
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   BalletKicks (M1)   three kicks: Common.ComboStrike with a wide sweeping box; kick 3 = Knockback.
--                                                                                     Fx "Strike" {combo, last, hits}
--   GrandJete (Q)      leap to the ground aim (<= Distance, AirTime s; Bravery.Leap, whose Impulse arc uses
--                      Config.Human.LeapArcFactor like the client's MovementController) and land with a kick shockwave:
--                      enemies within Radius take Damage (Area, dodgeable) + Knockback outward.
--                      Fx "Leap" {from, to, time, radius}, "Land" {center, radius}
--   Pirouette (E)      spin for Duration: enemy Melee and Projectile hits on the dancer are negated (DamageService
--                      Before hook, DamageFx.negated = "Pirouette"; projectiles end on that hit), enemy projectile
--                      hazards (BoneProjectile / Projectile) within DEFLECT_RADIUS are destroyed (HazardService.Remove),
--                      and Ticks pulses hit enemies within Radius for TickDamage (Melee).
--                      Fx "Spin" {duration, radius, ticks}, "Tick" {index, hits}, "Deflect" {pos}
--   Encore (R)         Dashes passes (Distance in DASH_TIME each, IFrames while dashing): the first along the aim, the
--                      next ones re-aimed through the nearest enemy (zig-zag when none); every enemy crossed takes
--                      DashDamage and loses DodgeDrain dodges; then a bow: FinalDamage to enemies within Radius.
--                      Attribute UltActiveUntil (client SOUL heart).
--                      Fx "Dash" {from, to, time} (x Dashes, Common.DashStrike), "Bow" {pos, radius}
-- Passive "Grace": double jump (kit Stats.DoubleJump -> client MovementController); visuals in the client kit.
--
-- Kit.IsSpinning(model) -> boolean   (tests / bots)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any
local Teams = require(Shared.Combat.Teams) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any
local Bravery = require(script.Parent.Bravery) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local DEFLECT_RADIUS = 3.6 -- studs from the root: a projectile this close touches the spinning dancer
local SPIN_STEP = 0.05
local JETE_APEX = 8
local DASH_TIME = 0.2
local DASH_GAP = 0.12
local DASH_RADIUS = 3
local BOW_DELAY = 0.28
local ZIGZAG = math.rad(140) -- turn when no enemy is left to pass through

local spinning: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

function Kit.IsSpinning(model: Model): boolean
	local untilT = spinning[model]
	return untilT ~= nil and untilT > Validation.Now() and Validation.IsUp(model)
end

---------------------------------------------------------------------------------------------------
-- Hooks (installed once per server)

local hooksInstalled = false

local function installHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	-- Pirouette: melee and projectiles slide off the spinning dancer
	Common.InstallHook("Integrity.Pirouette", "Before", function(info: any, _result: any, state: any)
		local target = info.Target
		if target == nil or (info.Kind ~= "Melee" and info.Kind ~= "Projectile") or not Kit.IsSpinning(target) then
			return nil
		end
		state.CancelReason = "Pirouette"
		return true
	end)
end
Kit.InstallHooks = installHooks

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	installHooks()
	spinning[model] = nil
	model:SetAttribute("UltActiveUntil", 0)
end

function Kit.OnDespawn(model: Model)
	spinning[model] = nil
end

---------------------------------------------------------------------------------------------------
-- Abilities

Abilities.BalletKicks = function(ctx: any)
	Common.ComboStrike(ctx, { Width = 5.2 })
end

Abilities.GrandJete = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.15
	if not ctx:Wait(windup) then
		return
	end
	local radius = N.Radius or 7
	local airTime = N.AirTime or 0.6
	local rootTarget, landing = Bravery.LeapTarget(ctx, N.Distance or 30)
	ctx:Fx("Leap", { from = ctx:RootPosition(), to = landing, time = airTime, radius = radius })
	if not Bravery.Leap(ctx, rootTarget, airTime, JETE_APEX) then
		return
	end
	local center = Bravery.LandingCenter(ctx, landing)
	local probe = center + Vector3.new(0, ctx:RootHeight(), 0)
	local knockback = N.Knockback or 30
	for _, m in ctx:EnemiesInRadius(probe, radius, true) do
		local p = Validation.RootPosition(m) or probe
		local out = Validation.FlatUnit(p - probe, ctx.FlatDir)
		ctx:Damage(m, {
			Amount = N.Damage or 14,
			Kind = "Area",
			Knockback = out * knockback + Vector3.new(0, knockback * 0.35, 0),
			Position = center,
		})
	end
	ctx:Fx("Land", { center = center, radius = radius })
end

-- Destroys enemy projectile hazards touching the dancer; returns how many.
local function deflect(ctx: any, at: Vector3): number
	local HazardService = Common.Services().HazardService
	local now = ctx:Now()
	local n = 0
	for _, rec in HazardService.GetActive() do
		if
			(rec.Type == "BoneProjectile" or rec.Type == "Projectile")
			and not rec.Ended
			and Teams.AreEnemyTeams(rec.Team, ctx.Team)
		then
			local frame = HazardDefs.ProjectileFrame(rec.Type, rec.Params, now - rec.T0)
			if frame and (frame.Position - at).Magnitude <= DEFLECT_RADIUS then
				HazardService.Remove(rec.Id)
				ctx:Fx("Deflect", { pos = frame.Position })
				n += 1
			end
		end
	end
	return n
end
Kit.Deflect = deflect

Abilities.Pirouette = function(ctx: any)
	installHooks()
	local N = ctx.N
	local duration = N.Duration or 1.2
	local radius = N.Radius or 6
	local ticks = math.max(1, math.floor(N.Ticks or 4))
	local tickDamage = N.TickDamage or 5
	local interval = duration / ticks
	local caster = ctx.Caster
	local startT = ctx:Now()
	spinning[caster] = startT + duration
	ctx:Fx("Spin", { duration = duration, radius = radius, ticks = ticks })
	local done = 0
	local elapsed = 0
	while elapsed < duration do
		local pos = ctx:RootPosition()
		deflect(ctx, pos)
		-- tick k (1..ticks) lands at (k - 0.5) x interval
		while done < ticks and elapsed >= (done + 0.5) * interval do
			done += 1
			local hits = 0
			for _, m in ctx:EnemiesInRadius(pos, radius, true) do
				local p = Validation.RootPosition(m) or pos
				local r = ctx:Damage(m, {
					Amount = tickDamage,
					Kind = "Melee",
					Knockback = Validation.FlatUnit(p - pos, ctx.FlatDir) * 8,
					Position = pos,
				})
				if r.Reason == nil then
					hits += 1
				end
			end
			ctx:Fx("Tick", { index = done, hits = hits })
		end
		if not ctx:Wait(SPIN_STEP) then
			break
		end
		elapsed = ctx:Now() - startT
	end
	if spinning[caster] == startT + duration then
		spinning[caster] = nil
	end
end

local function rotateY(v: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

Abilities.Encore = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.2
	if not ctx:Wait(windup) then
		return
	end
	local dashes = math.clamp(math.floor(N.Dashes or 3), 1, 6)
	local distance = N.Distance or 20
	local drain = N.DodgeDrain or 1
	local DamageService = Common.Services().DamageService
	local total = dashes * (DASH_TIME + DASH_GAP) + BOW_DELAY + 0.5
	ctx.Caster:SetAttribute("UltActiveUntil", ctx:Now() + total)
	local dir = ctx.FlatDir
	local turn = 1
	for i = 1, dashes do
		if i > 1 then
			-- re-aim the next pass through the nearest enemy; zig-zag when nobody is left
			local here = ctx:RootPosition()
			local foe = ctx:NearestEnemy(here, distance * 1.25)
			local fp = if foe then Validation.RootPosition(foe) else nil
			if fp and Vector3.new(fp.X - here.X, 0, fp.Z - here.Z).Magnitude > 1.5 then
				dir = Validation.FlatUnit(fp - here, dir)
			else
				dir = rotateY(dir, ZIGZAG * turn)
				turn = -turn
			end
		end
		ctx.FlatDir = dir
		ctx:Status(ctx.Caster, "IFrames", DASH_TIME + 0.08)
		Common.DashStrike(ctx, {
			Distance = distance,
			Time = DASH_TIME,
			Damage = N.DashDamage or 12,
			Radius = DASH_RADIUS,
			Windup = 0,
			OnHit = function(m: Model, _result: any)
				if drain > 0 then
					DamageService.DrainDodges(m, drain, ctx.Caster)
				end
			end,
		})
		if not ctx:Alive() then
			return
		end
		if i < dashes and not ctx:Wait(DASH_GAP) then
			return
		end
	end
	if not ctx:Wait(BOW_DELAY) then
		return
	end
	local pos = ctx:RootPosition()
	local radius = N.Radius or 9
	for _, m in ctx:EnemiesInRadius(pos, radius, true) do
		local p = Validation.RootPosition(m) or pos
		ctx:Damage(m, {
			Amount = N.FinalDamage or 20,
			Kind = "Area",
			Blockable = false,
			Knockback = Validation.FlatUnit(p - pos, ctx.FlatDir) * 32 + Vector3.new(0, 14, 0),
			Position = pos,
		})
	end
	ctx:Fx("Bow", { pos = pos, radius = radius })
end

return Kit
