--!strict
-- Server kit: Eclipse Sans — "The Void Wanderer" (traps, portals, space control). Every tunable comes from
-- Shared/Kits/Monsters/EclipseSans (ctx.N for casts; TotalEclipse.Numbers / RiftTrap.Numbers for the passives).
--
-- Abilities (AbilityFx phases sent with ctx:Fx, after the automatic "Start"):
--   VoidLash (M1)      3-hit long whip: box Range long in front (hits 1-2 wide sweeps, hit 3 a narrow crack that
--                      Slows SlowMult for SlowTime). Purple-tinted hits.           Fx "Lash" {combo, last, hits, reach}
--   RiftBlaster (Q)    a rift opens Offset studs to the SIDE of the aim point (the side with more room; alternates
--                      when both are open), a void-wolf skull (BlasterBeam style "Eclipse") emerges from it and
--                      fires ACROSS the aim point after Delay (Length, Width, BeamTime, Damage, KR).
--                      Fx "Rift" {pos, dir, hazard, delay, beamTime, width, length}
--   GravityWell (E)    after Windup the black star is thrown (Fx "Throw" {from, to, time}); on landing an Orb hazard
--                      (visual "EclipseWell", own telegraph) pulls humans within Radius at Pull studs/s for Duration,
--                      then implodes (ImplodeRadius, Damage, KR). Fx "Land" {pos, hazard, radius, implodeRadius,
--                      delay, duration}; Eclipse falling while it flies -> Fx "Fizzle" {pos}
--   Starfall (R)       Rain of Count star-bones (visual "EclipseStar") over Radius around the ground aim, one every
--                      Interval s, ImpactRadius each; every impact is marked on the ground before it lands.
--                      Fx "Starfall" {center, radius, hazard, delay, interval, count, fallHeight}
--   RiftTrap (T)       a nearly invisible rift on the ground (max MaxTraps per Eclipse, the oldest collapses), armed
--                      after ArmTime, lasting Lifetime. A human whose root crosses into Radius (swept test, 10 Hz,
--                      kit-owned StatusService.OnTick) is pulled through to Eclipse (teleported in front of him) and
--                      Rooted for Root s. IFrames / Boxed / Invulnerable humans pass safely.
--                      Fx "Trap" {id, pos, radius, reveal, arm, lifetime}, "Spring" {id, pos, victim, to},
--                      "Collapse" {id, pos}
--   VoidStep (Shift)   portal step toward the aim (max Distance, validated by ctx:Teleport), Invisible for
--                      Invisible s. Fx "Enter" {from, to} then "Teleport" {from, to} (sent by ctx:Teleport)
--   TotalEclipse (G)   after Windup: statuses "TotalEclipse" + Hasted (SpeedMult) for Duration; clients darken the
--                      world for humans. Meanwhile every hit Eclipse lands (and the impact points of his abilities)
--                      leaves a void-fire Zone (FireRadius, FireTime, FireDamage per FireTick, colour Purple,
--                      visual "EclipseVoidFire"). Fx "Eclipse" {duration, vision, ends, aura} ... "End" {}
-- Passives
--   Lazy Dodge   framework (DamageService).
--   Void Karma   every hit carries KR (Numbers.KR, purple); humans within TotalEclipse.AuraRadius of him lose
--                AuraDrain Ult/s, within VisionRadius during the eclipse DarkDrain Ult/s (Round/Collapse only).
-- Lifecycle: OnSpawn(model, ctxFactory?) registers the caster (passive loop + void-fire hook); OnDespawn(model)
--   collapses his traps, puts out his void fire and ends the eclipse.
-- Test hooks: Kit._State(model) -> per-caster state?   Kit._Tick(dt, now) (the OnTick body)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Kits = require(Shared.Kits) :: any
local Rng = require(Shared.Util.Rng) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any
local Teams = require(Shared.Combat.Teams) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local KIT_ID = "EclipseSans"
local LookAlong = HazardDefs.LookAlong

-- Presentation constants (geometry only; gameplay numbers live in the kit data)
local RIFT_LIFT = 0.9 -- rift centre above chest height (beam runs nearly level through the target's chest)
local CHEST = 2.6 -- chest height above the ground
local ORB_HEIGHT = 2.4 -- the black star hovers this high above the ground
local THROW_SPEED = 60 -- studs/s of the thrown star (flight time is clamped to 0.18..0.8 s)
local ORB_UNFOLD = 0.3 -- landing -> pull starts
local STAR_FALL = 42 -- Starfall fall height
local MAX_FIRES = 8 -- live void-fire zones per Eclipse (the oldest burns out early)
local FIRE_PER_TARGET = 1.0 -- one void fire per victim per second at most
local TRAP_IMMUNE = 2.0 -- a human just pulled through cannot trip another trap for this long
local TRAP_FEET_TOLERANCE = 2.5 -- feet within this height of the trap plane (jumping high clears it)
local PULL_DISTANCE = 4.5 -- the victim lands this far in front of Eclipse

type Trap = { Id: number, Pos: Vector3, Radius: number, ArmAt: number, Expires: number }
type Fire = { Id: number, Pos: Vector3, Ends: number }
type CasterState = {
	Model: Model,
	Ctx: any?, -- context used for loop-driven RiftTrap Fx (passive ctx or the latest RiftTrap cast)
	UltCtx: any?,
	Traps: { Trap },
	Fires: { Fire },
	EclipseUntil: number,
	RiftSide: number,
	LastPos: { [Model]: Vector3 },
	TrapImmune: { [Model]: number },
	FireCooldown: { [Model]: number },
}

local states: { [Model]: CasterState } = {}
local nextTrapId = 0
local tickInstalled = false

local function numbers(abilityId: string): { [string]: number }
	local a = Kits.Ability(KIT_ID, abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function services(): any
	return Common.Services()
end

---------------------------------------------------------------------------------------------------
-- Per-caster state

local function newState(model: Model): CasterState
	return {
		Model = model,
		Ctx = nil,
		UltCtx = nil,
		Traps = {},
		Fires = {},
		EclipseUntil = 0,
		RiftSide = 1,
		LastPos = setmetatable({}, { __mode = "k" }) :: any,
		TrapImmune = setmetatable({}, { __mode = "k" }) :: any,
		FireCooldown = setmetatable({}, { __mode = "k" }) :: any,
	}
end

local ensureHooks: () -> ()

local function stateOf(model: Model): CasterState
	local st = states[model]
	if st == nil then
		st = newState(model)
		states[model] = st
	end
	ensureHooks()
	return st
end

local function trapFx(st: CasterState, phase: string, data: { [string]: any })
	local ctx = st.Ctx
	if ctx then
		ctx:Fx(phase, data)
	end
end

-- Collapses traps, puts out void fire and ends a running eclipse (death / despawn / new life).
local function cleanup(st: CasterState)
	for _, trap in st.Traps do
		trapFx(st, "Collapse", { id = trap.Id, pos = trap.Pos })
	end
	table.clear(st.Traps)
	local HS = services().HazardService
	for _, fire in st.Fires do
		HS.Remove(fire.Id)
	end
	table.clear(st.Fires)
	if st.EclipseUntil > Validation.Now() then
		st.EclipseUntil = 0
		local ctx = st.UltCtx
		if ctx then
			ctx:Fx("End", {})
		end
	end
	st.EclipseUntil = 0
end

---------------------------------------------------------------------------------------------------
-- Void fire (Total Eclipse)

local function eclipseActive(caster: Model?): boolean
	if caster == nil then
		return false
	end
	local st = states[caster]
	return st ~= nil and Validation.Now() < st.EclipseUntil
end
Kit.EclipseActive = eclipseActive

-- Leaves a void-fire Zone on the ground under `point` while the caster's eclipse lasts. Spots already burning
-- (within 0.9 x FireRadius) are not stacked; at most MAX_FIRES burn at once per Eclipse.
local function voidFire(caster: Model, point: Vector3, delay: number?): number
	local st = states[caster]
	local now = Validation.Now()
	if st == nil or now >= st.EclipseUntil then
		return 0
	end
	local N = numbers("TotalEclipse")
	local radius = N.FireRadius or 4.5
	local ground = Validation.GroundBelow(point + Vector3.new(0, 3, 0), 40) or point
	local live: { Fire } = {}
	local burning = false
	for _, f in st.Fires do
		if f.Ends > now then
			table.insert(live, f)
			local flat = Vector3.new(f.Pos.X - ground.X, 0, f.Pos.Z - ground.Z).Magnitude
			if flat < radius * 0.9 and math.abs(f.Pos.Y - ground.Y) < 4 then
				burning = true
			end
		end
	end
	st.Fires = live
	if burning then
		return 0
	end
	local HS = services().HazardService
	while #st.Fires >= MAX_FIRES do
		local oldest = table.remove(st.Fires, 1)
		if oldest then
			HS.Remove(oldest.Id)
		end
	end
	local d = math.max(0.25, delay or 0.35)
	local fireTime = N.FireTime or 3.5
	local id = HS.Spawn(caster, Teams.TeamOf(caster), "Zone", {
		center = ground,
		radius = radius,
		height = 4,
		delay = d,
		warn = math.min(d, 0.35),
		duration = fireTime,
		tick = N.FireTick or 0.5,
		effect = "Damage",
		damage = N.FireDamage or 6,
		kr = 1,
		color = "Purple",
		visual = "EclipseVoidFire",
		ability = "TotalEclipse",
		linger = 0.4,
	})
	if id > 0 then
		table.insert(st.Fires, { Id = id, Pos = ground, Ends = now + d + fireTime })
	end
	return id
end
Kit.VoidFire = voidFire

-- DamageService "After" hook: every hit an eclipsed Eclipse lands sets the victim's ground on fire.
local function afterHit(info: any, result: any, _state: any): boolean?
	local attacker = info.Attacker
	if typeof(attacker) ~= "Instance" or info.Ability == "TotalEclipse" or info.Kind == "Box" then
		return nil
	end
	if type(result) ~= "table" or type(result.Applied) ~= "number" or result.Applied <= 0 then
		return nil
	end
	local st = states[attacker]
	local now = Validation.Now()
	if st == nil or now >= st.EclipseUntil then
		return nil
	end
	local target = info.Target
	if typeof(target) ~= "Instance" or (st.FireCooldown[target] or 0) > now then
		return nil
	end
	local pos = Validation.RootPosition(target)
	if pos == nil then
		return nil
	end
	st.FireCooldown[target] = now + FIRE_PER_TARGET
	-- hooks must not yield / re-enter HazardService mid-step: spawn on the next resumption point
	Validation.Defer(function()
		if Validation.IsAlive(attacker) then
			voidFire(attacker, pos, 0.35)
		end
	end)
	return nil
end

---------------------------------------------------------------------------------------------------
-- Rift traps (kit-owned 10 Hz check)

local function rootHeight(model: Model): number
	local hum = Validation.Humanoid(model)
	local root = Validation.Root(model)
	return (if hum then hum.HipHeight else 2) + (if root then root.Size.Y * 0.5 else 1)
end

-- Horizontal distance from point c to the segment a..b.
local function flatSegmentDistance(c: Vector3, a: Vector3, b: Vector3): number
	local ax, az = a.X - c.X, a.Z - c.Z
	local dx, dz = b.X - a.X, b.Z - a.Z
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp(-(ax * dx + az * dz) / len2, 0, 1)
	end
	local px, pz = ax + dx * t, az + dz * t
	return math.sqrt(px * px + pz * pz)
end

local function touchedTrap(st: CasterState, prev: Vector3, pos: Vector3, feetY: number, now: number): Trap?
	for _, trap in st.Traps do
		if now >= trap.ArmAt and math.abs(feetY - trap.Pos.Y) <= TRAP_FEET_TOLERANCE then
			if flatSegmentDistance(trap.Pos, prev, pos) <= trap.Radius then
				return trap
			end
		end
	end
	return nil
end

-- Where a pulled victim lands: in front of Eclipse (then his sides, then behind), on the ground, in sight.
local function pullDestination(caster: Model, victim: Model): CFrame?
	local root = Validation.Root(caster)
	if root == nil then
		return nil
	end
	local center = root.CFrame.Position
	local look = Validation.Look(caster)
	local right = Common.Right(look)
	local victimHeight = rootHeight(victim)
	for _, dir in { look, right, -right, -look } do
		local p = center + dir * PULL_DISTANCE
		if Validation.LineOfSight(center, p) then
			local ground = Validation.GroundBelow(p + Vector3.new(0, 1, 0), 12)
			if ground then
				local dest = ground + Vector3.new(0, victimHeight + 0.05, 0)
				return LookAlong(dest, Validation.FlatUnit(center - dest, -dir))
			end
		end
	end
	return nil
end

local function springTrap(st: CasterState, trap: Trap, victim: Model, now: number)
	local i = table.find(st.Traps, trap)
	if i then
		table.remove(st.Traps, i)
	end
	st.TrapImmune[victim] = now + TRAP_IMMUNE
	local N = numbers("RiftTrap")
	local S = services()
	local dest = pullDestination(st.Model, victim)
	trapFx(st, "Spring", {
		id = trap.Id,
		pos = trap.Pos,
		victim = victim,
		to = if dest then dest.Position else nil,
	})
	if dest then
		S.MovementService.Teleport(victim, dest)
	end
	S.StatusService.Apply(victim, "Rooted", N.Root or 1)
end

local function checkTraps(st: CasterState, now: number)
	for i = #st.Traps, 1, -1 do
		local trap = st.Traps[i]
		if now >= trap.Expires then
			table.remove(st.Traps, i)
			trapFx(st, "Collapse", { id = trap.Id, pos = trap.Pos })
		end
	end
	if #st.Traps == 0 then
		table.clear(st.LastPos)
		return
	end
	local caster = st.Model
	local SS = services().StatusService
	for _, m in Validation.Combatants() do
		if m ~= caster and Teams.AreEnemies(caster, m) and Validation.IsUp(m) then
			local pos = Validation.RootPosition(m)
			if pos then
				local prev = st.LastPos[m] or pos
				st.LastPos[m] = pos
				local safe = (st.TrapImmune[m] or 0) > now
					or SS.Has(m, "Boxed")
					or SS.Has(m, "IFrames")
					or SS.Has(m, "Invulnerable")
				if not safe then
					local trap = touchedTrap(st, prev, pos, pos.Y - rootHeight(m), now)
					if trap then
						springTrap(st, trap, m, now)
						if #st.Traps == 0 then
							return
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Void Karma: ult drain near Eclipse (aura always, wide during the eclipse)

local function drainUlt(st: CasterState, dt: number, now: number)
	if not Validation.InCombatPhase() then
		return
	end
	local caster = st.Model
	local center = Validation.RootPosition(caster)
	if center == nil then
		return
	end
	local N = numbers("TotalEclipse")
	local dark = now < st.EclipseUntil
	local radius = if dark then (N.VisionRadius or 26) else (N.AuraRadius or 10)
	local rate = if dark then (N.DarkDrain or 2.5) else (N.AuraDrain or 0.75)
	if rate <= 0 or radius <= 0 then
		return
	end
	for _, m in Validation.Combatants() do
		if m ~= caster and Teams.TeamOf(m) == "Humans" and Teams.AreEnemies(caster, m) and Validation.IsUp(m) then
			local p = Validation.RootPosition(m)
			local ult = m:GetAttribute("Ult")
			if p and type(ult) == "number" and ult > 0 and (p - center).Magnitude <= radius then
				m:SetAttribute("Ult", DamageMath.AddUlt(ult, -rate * dt))
			end
		end
	end
end

function Kit._Tick(dt: number, now: number)
	for model, st in states do
		if model.Parent == nil or not Validation.IsAlive(model) then
			cleanup(st)
			states[model] = nil
		else
			checkTraps(st, now)
			if Validation.IsUp(model) then
				drainUlt(st, dt, now)
			end
		end
	end
end

function Kit._State(model: Model): CasterState?
	return states[model]
end

ensureHooks = function()
	Common.InstallHook("EclipseSans.VoidFire", "After", afterHit)
	if tickInstalled then
		return
	end
	local SS = services().StatusService
	if SS and type(SS.OnTick) == "function" then
		tickInstalled = true
		SS.OnTick(function(dt: number, now: number)
			Kit._Tick(dt, now)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Abilities

Abilities.VoidLash = function(ctx: any)
	local N = ctx.N
	local index = ctx.ComboIndex or 1
	local combo = if type(ctx.Ability.Combo) == "number" then ctx.Ability.Combo else 3
	local last = index >= combo
	local range = N.Range or 9
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.14
	if not ctx:Wait(windup) then
		return
	end
	-- sweeps are wide, the final crack is a narrow line at full reach
	local width = if last then 3.4 else 5.5
	local hits, results = ctx:Melee({
		Offset = CFrame.new(0, 0, -range * 0.5),
		Size = Vector3.new(width, 5, range),
		Damage = N["Damage" .. index] or N.Damage1 or 7,
		KR = N.KR,
		Kind = "Melee",
		Color = "Purple",
	})
	if last and type(N.SlowMult) == "number" and type(N.SlowTime) == "number" then
		for _, m in hits do
			local r = results[m]
			if r and r.Applied > 0 then
				ctx:Status(m, "Slowed", N.SlowTime, { mult = N.SlowMult })
			end
		end
	end
	if last then
		voidFire(ctx.Caster, ctx:RootPosition() + ctx.FlatDir * range, 0.3)
	end
	ctx:Fx("Lash", { combo = index, last = last, hits = #hits, reach = range })
end

-- Rift position + beam direction for a Rift Blaster cast (the side of the aim with more room).
local function riftPlacement(ctx: any, st: CasterState): (Vector3, Vector3, Vector3)
	local N = ctx.N
	local ground = Common.GroundAim(ctx)
	local origin = ctx:RootPosition()
	local fwd = Validation.FlatUnit(ground - origin, ctx.FlatDir)
	local right = Common.Right(fwd)
	local offset = math.max(4, N.Offset or 13)
	local chest = ground + Vector3.new(0, CHEST, 0)
	st.RiftSide = -st.RiftSide
	local first = st.RiftSide
	local bestSide, bestClear = first, -1
	for _, s in { first, -first } do
		local clear = Common.ClampPath(chest, right * s, offset)
		if clear > bestClear + 0.5 then
			bestSide, bestClear = s, clear
		end
	end
	local dist = math.max(4, bestClear)
	local pos = chest + right * (bestSide * dist) + Vector3.new(0, RIFT_LIFT, 0)
	local dir = Validation.Unit(chest - pos, right * -bestSide)
	return pos, dir, ground
end
Kit.RiftPlacement = riftPlacement

Abilities.RiftBlaster = function(ctx: any)
	local N = ctx.N
	local st = stateOf(ctx.Caster)
	local pos, dir, ground = riftPlacement(ctx, st)
	local delay = N.Delay or 1.1
	local beamTime = N.BeamTime or 0.5
	local width = N.Width or 5
	local length = N.Length or 60
	local id = ctx:Hazard("BlasterBeam", {
		origin = LookAlong(pos, dir),
		length = length,
		width = width,
		delay = delay,
		duration = beamTime,
		damage = N.Damage or 24,
		kr = N.KR or 0,
		color = "White",
		style = "Eclipse",
		-- the skull pushes out of the rift (BlasterPose flies in from spawnFrom + 1.5 up)
		spawnFrom = pos - dir * 4 - Vector3.new(0, 1.5, 0),
		linger = 0.3,
	})
	ctx:Fx("Rift", {
		pos = pos,
		dir = dir,
		hazard = id,
		delay = delay,
		beamTime = beamTime,
		width = width,
		length = length,
	})
	voidFire(ctx.Caster, ground, delay)
end

Abilities.GravityWell = function(ctx: any)
	local N = ctx.N
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.35
	if not ctx:Wait(windup) then
		return
	end
	local root = ctx:RootPosition()
	local fwd = ctx.FlatDir
	local from = root + Vector3.new(0, 1.2, 0) + fwd * 1.2 + Common.Right(fwd) * 0.9
	local ground = Common.GroundAim(ctx)
	local to = ground + Vector3.new(0, ORB_HEIGHT, 0)
	local flight = math.clamp((to - from).Magnitude / THROW_SPEED, 0.18, 0.8)
	ctx:Fx("Throw", { from = from, to = to, time = flight })
	-- the star is already flying: only Eclipse's fall (not a stun) stops it
	Validation.Wait(flight)
	if ctx:Cancelled() or not Validation.IsAlive(ctx.Caster) then
		ctx:Fx("Fizzle", { pos = to })
		return
	end
	local radius = N.Radius or 14
	local implodeRadius = math.min(N.ImplodeRadius or radius * 0.6, radius)
	local duration = N.Duration or 2.5
	local id = ctx:Hazard("Orb", {
		center = to,
		radius = radius,
		delay = ORB_UNFOLD,
		duration = duration,
		pullStrength = N.Pull or 14,
		damage = N.Damage or 18,
		implodeDamage = N.Damage or 18,
		implodeRadius = implodeRadius,
		kr = N.KR or 0,
		color = "White",
		telegraph = false, -- the EclipseWell visual draws the implosion ring (the real hitbox) as it charges
		visual = "EclipseWell",
	})
	ctx:Fx("Land", {
		pos = to,
		hazard = id,
		radius = radius,
		implodeRadius = implodeRadius,
		delay = ORB_UNFOLD,
		duration = duration,
	})
	voidFire(ctx.Caster, ground, ORB_UNFOLD + duration)
end

Abilities.Starfall = function(ctx: any)
	local N = ctx.N
	local center = Common.GroundAim(ctx)
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.6
	local delay = windup + 0.35
	local count = math.max(1, math.floor(N.Count or 10))
	local interval = N.Interval or 0.15
	local radius = N.Radius or 14
	local rng = Rng.new(Rng.Hash("Starfall", ctx.CastId, ctx.StartTime))
	local id = ctx:Hazard("Rain", {
		center = center,
		radius = radius,
		count = count,
		interval = interval,
		delay = delay,
		warn = math.min(delay, 0.8),
		fallHeight = STAR_FALL,
		fallTime = 0.42,
		size = N.ImpactRadius or 3.5,
		impactHeight = 4.5,
		impactTime = 0.12,
		damage = N.Damage or 9,
		kr = N.KR or 0,
		color = "White",
		visual = "EclipseStar",
		seed = rng:Integer(1, 1000000),
	})
	ctx:Fx("Starfall", {
		center = center,
		radius = radius,
		hazard = id,
		delay = delay,
		interval = interval,
		count = count,
		fallHeight = STAR_FALL,
	})
	voidFire(ctx.Caster, center, delay + (count - 1) * interval)
end

Abilities.RiftTrap = function(ctx: any)
	local N = ctx.N
	local st = stateOf(ctx.Caster)
	st.Ctx = ctx
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.3
	if not ctx:Wait(windup) then
		return
	end
	local origin = ctx:RootPosition()
	local range = if type(ctx.Ability.Range) == "number" then ctx.Ability.Range else 30
	local ground = Common.GroundAim(ctx, DamageMath.ClampAim(origin, ctx.Aim, range))
	local now = Validation.Now()
	local maxTraps = math.max(1, math.floor(N.MaxTraps or 2))
	while #st.Traps >= maxTraps do
		local old = table.remove(st.Traps, 1)
		if old then
			trapFx(st, "Collapse", { id = old.Id, pos = old.Pos })
		end
	end
	nextTrapId += 1
	local arm = N.ArmTime or 0.75
	local lifetime = N.Lifetime or 45
	local trap: Trap = {
		Id = nextTrapId,
		Pos = ground,
		Radius = N.Radius or 3.5,
		ArmAt = now + arm,
		Expires = now + lifetime,
	}
	table.insert(st.Traps, trap)
	ctx:Fx("Trap", {
		id = trap.Id,
		pos = ground,
		radius = trap.Radius,
		reveal = N.RevealDistance or 10,
		arm = arm,
		lifetime = lifetime,
	})
end

Abilities.VoidStep = function(ctx: any)
	local N = ctx.N
	local from = ctx:RootPosition()
	local dest = DamageMath.ClampAim(from, ctx.Aim, N.Distance or 35)
	if not ctx:Wait(if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.08) then
		return
	end
	from = ctx:RootPosition()
	local feet = from - Vector3.new(0, ctx:RootHeight(), 0)
	ctx:Fx("Enter", { from = from, to = dest })
	local invisible = N.Invisible or 0.5
	if invisible > 0 then
		ctx:Status(ctx.Caster, "Invisible", invisible)
	end
	if ctx:Teleport(LookAlong(dest, ctx.FlatDir)) == nil then
		ctx:Fx("Teleport", { from = from, to = from }) -- nowhere safe: step back out of the same portal
	end
	voidFire(ctx.Caster, feet, 0.2)
end

Abilities.TotalEclipse = function(ctx: any)
	local N = ctx.N
	local caster = ctx.Caster
	local st = stateOf(caster)
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.9
	local duration = N.Duration or 8
	-- the ult is already paid: a stun during the windup does not cancel it, only Eclipse's fall does
	Validation.Wait(windup)
	if ctx:Cancelled() or not Validation.IsUp(caster) then
		return
	end
	local now = Validation.Now()
	local endsAt = now + duration
	st.EclipseUntil = endsAt
	st.UltCtx = ctx
	table.clear(st.FireCooldown)
	ctx:Status(caster, "TotalEclipse", duration)
	ctx:Status(caster, "Hasted", duration, { mult = N.SpeedMult or 1.25 })
	ctx:Fx("Eclipse", {
		duration = duration,
		vision = N.VisionRadius or 26,
		ends = endsAt,
		aura = N.AuraRadius or 10,
	})
	-- hold the cast until the light returns (or Eclipse falls / a new eclipse replaces this one)
	while Validation.Now() < endsAt - 1e-3 do
		Validation.Wait(math.min(0.25, endsAt - Validation.Now()))
		if ctx:Cancelled() or not Validation.IsAlive(caster) or st.EclipseUntil ~= endsAt then
			break
		end
	end
	if st.EclipseUntil == endsAt then
		st.EclipseUntil = 0
		if Validation.Now() < endsAt - 1e-3 then
			services().StatusService.Remove(caster, "TotalEclipse")
			services().StatusService.Remove(caster, "Hasted")
		end
		ctx:Fx("End", {})
	end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

function Kit.OnSpawn(model: Model, factory: any?)
	local old = states[model]
	if old then
		cleanup(old)
	end
	local st = newState(model)
	states[model] = st
	if type(factory) == "function" then
		local ok, ctx = pcall(factory, "RiftTrap")
		if ok and type(ctx) == "table" then
			st.Ctx = ctx
		end
	end
	ensureHooks()
end

function Kit.OnDespawn(model: Model)
	local st = states[model]
	if st == nil then
		return
	end
	cleanup(st)
	states[model] = nil
end


return Kit
