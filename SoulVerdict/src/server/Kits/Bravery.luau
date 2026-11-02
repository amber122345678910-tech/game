--!strict
-- Server kit: Bravery (orange SOUL) — "The Brawler", bruiser / tank. Numbers come from
-- Shared/Kits/Humans/Bravery (ctx.N); the constants below only shape feel (speeds, hit sizes, timings).
--
-- Abilities (AbilityFx phases after the automatic "Start"):
--   ToughPunches (M1)    four heavy punches: Common.ComboStrike with a wide glove box; punch 4 = Knockback + Stagger
--                        (stun).                                                        Fx "Strike" {combo, last, hits}
--   GutsCharge (Q)       shoulder charge along the aim (Distance at CHARGE_SPEED). It stops on the first enemy it
--                        meets: Damage + Stun (undodgeable — a freight train cannot be lazily side-stepped, and a
--                        stunned monster cannot dodge the follow-ups) + a short knockback.
--                        Fx "Charge" {from, to, time}, then "Impact" {target, pos, landed} or "Skid" {pos}
--   BraveStand (E)       DamageDown {mult = 1 - Reduction} for Duration on self + allies within Radius (a stronger
--                        DamageDown already present is kept).                 Fx "Stand" {duration, radius, allies}
--   BurningCourage (R)   leap to the ground aim (<= Range) and slam: every enemy within Radius loses DodgeDrain dodges,
--                        takes Damage (Area, unblockable) + Stun + knockback; self + allies within 2 x Radius gain
--                        DamageUp {mult = AllyBuff} for BuffTime (a stronger DamageUp already present is kept).
--                        Attribute UltActiveUntil (client SOUL heart).
--                        Fx "Leap" {from, to, time, radius}, "Slam" {center, radius, allies, buffTime}
-- Passive "Unbreakable" (on spawn): MaxGuard >= (1 + GUARD_BONUS) x Config.Human.MaxGuard (the kit data already carries
--   150 = +50 %, so it is not applied twice), Guard refilled, attribute GuardRegenMult = GUARD_REGEN_MULT (read by
--   StatusService's guard regen).
--
-- Shared helpers (also used by the Integrity kit):
--   Kit.Leap(ctx, rootTarget, airTime, apex, slamFrac?) -> boolean   leap arc to a ROOT position; false if the caster
--       died / was stunned meanwhile. Players: one Impulse (vertical pop + decaying horizontal mover, client
--       MovementController; IMPULSE_DECAY mirrors MovementController.Tuning.ImpulseDecay) and an optional Slam at
--       slamFrac x airTime; bots (server movers): two straight Dash segments (up, then down).
--   Kit.LandingCenter(ctx, landing) -> Vector3   ground point of the impact: the planned landing point when the
--       caster is near it (replication lag), else the ground under the caster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Melee = require(Combat.Melee) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local GUARD_BONUS = 0.5 -- kit text: "+50% Guard"
local GUARD_REGEN_MULT = 1.6 -- kit text: "faster Guard recovery"
local CHARGE_SPEED = 62 -- studs/s (22 studs in ~0.35 s: heavier than a knife lunge)
local CHARGE_RADIUS = 2.8
local CHARGE_KNOCKBACK = 26
local LEAP_TIME = 0.62
local LEAP_APEX = 9
local SLAM_FRAC = 0.75 -- the descent turns into a slam at this fraction of the arc
local SLAM_SPEED = 160
local LAND_TOLERANCE = 9
local GRAVITY = 196.2 -- Workspace.Gravity (default.project.json)
local IMPULSE_DECAY = 1.6 -- MovementController.Tuning.ImpulseDecay (horizontal mover (1 - x)^k)

---------------------------------------------------------------------------------------------------
-- Leap helpers (shared with Integrity)

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function Kit.Leap(ctx: any, rootTarget: Vector3, airTime: number, apex: number, slamFrac: number?): boolean
	local from = ctx:RootPosition()
	local flat = Vector3.new(rootTarget.X - from.X, 0, rootTarget.Z - from.Z)
	local dist = flat.Magnitude
	local dir = if dist > 1e-3 then flat.Unit else ctx.FlatDir
	local rise = rootTarget.Y - from.Y
	local T = math.max(0.2, airTime)
	if ctx.Player then
		local s = math.clamp(slamFrac or 1, 0.3, 1)
		local k = IMPULSE_DECAY + 1
		-- horizontal distance covered by the decaying mover after s x T: vh x T x (1 - (1 - s)^k) / k
		local covered = 1 - (1 - s) ^ k
		local vh = k * dist / (T * math.max(0.2, covered))
		local vy = math.max(20, GRAVITY * T * 0.5 + rise / T)
		ctx:ForceMove(ctx.Caster, { kind = "Impulse", velocity = dir * vh + Vector3.new(0, vy, 0), duration = T })
		if s < 1 then
			if not ctx:Wait(T * s) then
				return false
			end
			ctx:ForceMove(ctx.Caster, { kind = "Slam", velocity = Vector3.new(0, -SLAM_SPEED, 0), duration = 0.5 })
			return ctx:Wait(0.06)
		end
		return ctx:Wait(T)
	end
	-- bots: server movers hold the full velocity vector, so draw the arc as two straight segments
	local up = T * (if slamFrac then math.clamp(slamFrac, 0.3, 0.9) else 0.5)
	local down = T - up
	local vh = dir * (dist / T)
	ctx:ForceMove(ctx.Caster, { kind = "Dash", velocity = vh + Vector3.new(0, apex / up, 0), duration = up })
	if not ctx:Wait(up) then
		return false
	end
	ctx:ForceMove(
		ctx.Caster,
		{ kind = "Dash", velocity = vh + Vector3.new(0, (rise - apex) / down, 0), duration = down }
	)
	return ctx:Wait(down)
end

function Kit.LandingCenter(ctx: any, landing: Vector3): Vector3
	local feet = Common.Feet(ctx)
	if flatDistance(feet, landing) <= LAND_TOLERANCE then
		return landing
	end
	return feet
end

-- Root target + feet landing point for a ground-aimed leap of at most maxDistance studs.
function Kit.LeapTarget(ctx: any, maxDistance: number): (Vector3, Vector3)
	local from = ctx:RootPosition()
	local aim = Common.GroundAim(ctx)
	local flat = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if flat.Magnitude > maxDistance then
		aim = Common.GroundAim(ctx, Vector3.new(from.X, aim.Y, from.Z) + flat.Unit * maxDistance)
	end
	local rootTarget = Common.SafePosition(ctx, aim) or from
	return rootTarget, rootTarget - Vector3.new(0, ctx:RootHeight(), 0)
end

-- Applies `status` {mult} unless the target already carries a stronger version of it.
local function applyMult(
	ctx: any,
	model: Model,
	status: string,
	duration: number,
	mult: number,
	stronger: (number, number) -> boolean
)
	local _, data = Common.Services().StatusService.Get(model, status)
	local current = if data and type(data.mult) == "number" then data.mult else nil
	if current ~= nil and stronger(current, mult) then
		return
	end
	ctx:Status(model, status, duration, { mult = mult })
end

---------------------------------------------------------------------------------------------------
-- Passive: Unbreakable

function Kit.OnSpawn(model: Model, _ctxFactory: any)
	local base = Config.Human.MaxGuard
	local current = model:GetAttribute("MaxGuard")
	local maxGuard = math.max(if type(current) == "number" then current else base, base * (1 + GUARD_BONUS))
	model:SetAttribute("MaxGuard", maxGuard)
	model:SetAttribute("Guard", maxGuard)
	model:SetAttribute("GuardRegenMult", GUARD_REGEN_MULT)
	model:SetAttribute("UltActiveUntil", 0)
end

function Kit.OnDespawn(_model: Model) end

---------------------------------------------------------------------------------------------------
-- Abilities

Abilities.ToughPunches = function(ctx: any)
	Common.ComboStrike(ctx, { Width = 4.6 })
end

Abilities.GutsCharge = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.15
	if not ctx:Wait(windup) then
		return
	end
	local start = ctx:RootPosition()
	local dir = ctx.FlatDir
	local distance = Common.ClampPath(start, dir, N.Distance or 22)
	local time = math.max(0.12, distance / CHARGE_SPEED)
	if distance > 0.5 then
		ctx:ForceMove(ctx.Caster, { kind = "Dash", velocity = dir * (distance / time), duration = time })
	end
	ctx:Fx("Charge", { from = start, to = start + dir * distance, time = time })
	local steps = math.max(2, math.ceil(time / 0.05))
	local prev = start
	for s = 1, steps do
		if not ctx:Wait(time / steps) then
			return
		end
		local p = start + dir * (distance * s / steps)
		local hit = Melee.Sweep(prev, p, CHARGE_RADIUS, ctx:Enemies(true), { MaxTargets = 1 })[1]
		if hit then
			-- shoulder check: the charge stops on contact
			ctx:ForceMove(ctx.Caster, { kind = "Root", duration = 0.2 })
			local result = ctx:Damage(hit, {
				Amount = N.Damage or 18,
				Kind = "Melee",
				Stun = N.Stun or 0.8,
				Undodgeable = true,
				Knockback = dir * CHARGE_KNOCKBACK + Vector3.new(0, 10, 0),
				Position = p,
			})
			ctx:Fx("Impact", {
				target = hit,
				pos = Validation.RootPosition(hit) or p,
				landed = result.Reason == nil and not result.Parried,
			})
			return
		end
		prev = p
	end
	ctx:Fx("Skid", { pos = start + dir * distance })
end

Abilities.BraveStand = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.15
	if not ctx:Wait(windup) then
		return
	end
	local duration = N.Duration or 3
	local radius = N.Radius or 10
	local mult = math.clamp(1 - (N.Reduction or 0.4), 0, 1)
	local center = ctx:RootPosition()
	local buffed: { Model } = {}
	for _, ally in ctx:Allies(true) do
		local p = Validation.RootPosition(ally)
		if p and (p - center).Magnitude <= radius then
			applyMult(ctx, ally, "DamageDown", duration, mult, function(current, new)
				return current < new -- a lower incoming multiplier is a stronger reduction
			end)
			table.insert(buffed, ally)
		end
	end
	ctx:Fx("Stand", { duration = duration, radius = radius, allies = buffed })
end

Abilities.BurningCourage = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.6
	if not ctx:Wait(windup) then
		return
	end
	local radius = N.Radius or 14
	local rootTarget, landing = Kit.LeapTarget(ctx, ctx.Ability.Range or 24)
	ctx:Fx("Leap", { from = ctx:RootPosition(), to = landing, time = LEAP_TIME * SLAM_FRAC + 0.06, radius = radius })
	if not Kit.Leap(ctx, rootTarget, LEAP_TIME, LEAP_APEX, SLAM_FRAC) then
		return
	end
	local center = Kit.LandingCenter(ctx, landing)
	local rootHeight = ctx:RootHeight()
	local probe = center + Vector3.new(0, rootHeight, 0)
	local DamageService = Common.Services().DamageService
	for _, m in ctx:EnemiesInRadius(probe, radius, true) do
		local p = Validation.RootPosition(m) or probe
		local out = Validation.FlatUnit(p - probe, ctx.FlatDir)
		DamageService.DrainDodges(m, N.DodgeDrain or 2, ctx.Caster)
		ctx:Damage(m, {
			Amount = N.Damage or 30,
			Kind = "Area",
			Stun = N.Stun or 1.2,
			Blockable = false,
			Knockback = out * 30 + Vector3.new(0, 24, 0),
			Position = center,
		})
	end
	local buffMult = N.AllyBuff or 1.15
	local buffTime = N.BuffTime or 6
	local rally: { Model } = {}
	for _, ally in ctx:Allies(true) do
		local p = Validation.RootPosition(ally)
		if p and (p - probe).Magnitude <= radius * 2 then
			applyMult(ctx, ally, "DamageUp", buffTime, buffMult, function(current, new)
				return current > new
			end)
			table.insert(rally, ally)
		end
	end
	ctx.Caster:SetAttribute("UltActiveUntil", ctx:Now() + buffTime)
	ctx:Fx("Slam", { center = center, radius = radius, allies = rally, buffTime = buffTime })
end

return Kit
