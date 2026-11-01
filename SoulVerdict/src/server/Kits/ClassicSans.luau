--!strict
-- Server kit: Classic Sans — "The Judge" (control / zoning). Numbers come from Shared/Kits/Monsters/ClassicSans.
--
-- Abilities (AbilityFx phases sent with ctx:Fx, after the automatic "Start"):
--   BoneJab (M1)       Common.ComboStrike: Damage1..3, KR, Range, Knockback on hit 3.            Fx "Strike"
--   GasterBlaster (Q)  hold: blasters = clamp(1 + floor(charge * MaxBlasters), 1, MaxBlasters) placed in an
--                      arc behind/around Sans (layout below), each a BlasterBeam hazard aimed at the aim point
--                      (chest height), firing at Delay + (i-1)*0.12 for BeamTime, Length, Width, Damage, KR.
--                      Fx "Summon" {count, hazards = {ids}, origins = {CFrame}} at once.
--   BlueSoul (E)       target lift (ForceMove Lift LiftHeight over 0.45 s) -> hold 0.15 s -> Slam -> Damage + KR,
--                      Stun, then Blue (heavy gravity) for BlueTime. Fx "Grab"{target} "Lift" "Slam" "Release".
--   BoneZone (R)       BoneSpikes (white, Radius, Delay) then an orange ring (radius Radius+1.5, width 4) at
--                      OrangeDelay (telegraph shown for the last 0.6 s). Fx "Zone" {center, radius, hazards}.
--   BoneWall (T)       BoneLine of blue bones (Width/2 + 1 bones, 2 studs apart, Height, Speed, Distance) from
--                      2.5 studs in front of Sans. Fx "Wall" {hazard}.
--   Shortcut (Shift)   teleport toward the aim (max Distance), validated by ctx:Teleport.
--                      Fx "Vanish" {from} then "Teleport" {from, to} (sent by ctx:Teleport).
--   BadTime (G, ult)   KRBoost x2 on Sans for Duration + 1.5; Blasters BlasterBeams on a ring (Radius + 6)
--                      around the ground aim firing in sequence across the area (first at Windup, spread over
--                      Duration); bone Rain (RainDamage, KR/2) over the area. Fx "Blaze" {center, radius,
--                      duration, hazards}.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local Rng = require(Shared.Util.Rng) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any
local DamageMath = require(Shared.Combat.DamageMath) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Common = require(script.Parent.Common) :: any

local Kit = {}
local Abilities: { [string]: (any) -> () } = {}
Kit.Abilities = Abilities

local LookAlong = HazardDefs.LookAlong

-- Blaster slots in caster space: {right, up, back} (studs)
local BLASTER_LAYOUTS: { [number]: { { number } } } = {
	[1] = { { 2.8, 4.2, 2.5 } },
	[2] = { { -3.6, 3.6, 2.2 }, { 3.6, 3.6, 2.2 } },
	[3] = { { -4.6, 3.0, 1.4 }, { 0, 5.6, 2.8 }, { 4.6, 3.0, 1.4 } },
}

local function blasterSlots(count: number): { { number } }
	local layout = BLASTER_LAYOUTS[count]
	if layout then
		return layout
	end
	-- generic arc behind the caster for larger counts
	local out = {}
	for i = 1, count do
		local frac = (i - 1) / math.max(1, count - 1)
		local a = math.rad(-70 + 140 * frac)
		table.insert(out, { math.sin(a) * 5, 3 + math.cos(a) * 2.5, 1.5 + math.cos(a) * 1.5 })
	end
	return out
end

-- Point the beams at chest height when the aim is on the ground.
local function aimPoint(ctx: any): Vector3
	local aim: Vector3 = ctx.Aim
	local ground = Validation.GroundBelow(aim + Vector3.new(0, 0.5, 0), 3.5)
	if ground then
		return ground + Vector3.new(0, 2.5, 0)
	end
	return aim
end

Abilities.BoneJab = function(ctx: any)
	Common.ComboStrike(ctx)
end

Abilities.GasterBlaster = function(ctx: any)
	local N = ctx.N
	local maxBlasters = math.max(1, math.floor(N.MaxBlasters or 3))
	local count = math.clamp(1 + math.floor(ctx.Charge * maxBlasters), 1, maxBlasters)
	local origin = ctx:RootPosition()
	local fwd = ctx.FlatDir
	local right = Common.Right(fwd)
	local target = aimPoint(ctx)
	local delay = N.Delay or 0.75
	local stagger = 0.12
	local ids: { number } = {}
	local origins: { CFrame } = {}
	for i, slot in blasterSlots(count) do
		local pos = origin + right * slot[1] + Vector3.yAxis * slot[2] - fwd * slot[3]
		local dir = target - pos
		if dir.Magnitude < 4 or Validation.FlatUnit(dir, fwd):Dot(fwd) < 0.1 then
			dir = fwd + Vector3.new(0, -0.05, 0) -- aim too close / behind: fire straight ahead
		end
		local cf = LookAlong(pos, dir)
		local id = ctx:Hazard("BlasterBeam", {
			origin = cf,
			length = N.Length or 90,
			width = N.Width or 5,
			delay = delay + (i - 1) * stagger,
			duration = N.BeamTime or 0.6,
			damage = N.Damage or 18,
			kr = N.KR or 0,
			color = "White",
			style = "Classic",
			spawnFrom = origin,
		})
		table.insert(ids, id)
		table.insert(origins, cf)
	end
	ctx:Fx("Summon", { count = count, hazards = ids, origins = origins })
end

Abilities.BlueSoul = function(ctx: any)
	local N = ctx.N
	local target: Model? = ctx.Target
	if target == nil then
		return
	end
	local services = Common.Services()
	local StatusService = services.StatusService
	ctx:Fx("Grab", { target = target })
	if not ctx:Wait(ctx.Ability.Windup or 0.35) then
		ctx:Fx("Release", { target = target })
		return
	end
	local maxDist = (ctx.Ability.Range or 45) + Config.Combat.AimSlack + 6
	local tpos = Validation.RootPosition(target)
	if
		tpos == nil
		or not Validation.IsUp(target)
		or (tpos - ctx:RootPosition()).Magnitude > maxDist
		or StatusService.Has(target, "Boxed")
		or StatusService.Has(target, "Invulnerable")
	then
		ctx:Fx("Release", { target = target })
		return
	end
	local lift, hold, slam = 0.45, 0.15, 0.22
	local blueTime = N.BlueTime or 4
	ctx:Status(target, "Stunned", lift + hold + slam + 0.1)
	ctx:Status(target, "Blue", lift + hold + slam + blueTime)
	ctx:ForceMove(target, { kind = "Lift", height = N.LiftHeight or 12, duration = lift })
	ctx:Fx("Lift", { target = target, height = N.LiftHeight or 12, duration = lift })
	if not ctx:Wait(lift + hold) then
		-- Sans was interrupted: drop the human (gravity is still heavy)
		StatusService.Remove(target, "Stunned")
		ctx:Fx("Release", { target = target })
		return
	end
	if not Validation.IsAlive(target) then
		return
	end
	ctx:ForceMove(target, { kind = "Slam", velocity = Vector3.new(0, -150, 0), duration = slam })
	ctx:Fx("Slam", { target = target })
	Validation.Wait(slam)
	if Validation.IsAlive(target) then
		ctx:Damage(target, {
			Amount = N.Damage or 14,
			KR = N.KR or 0,
			Kind = "Area",
			Blockable = false,
			Stun = N.Stun,
			Position = Validation.RootPosition(target),
		})
	end
end

Abilities.BoneZone = function(ctx: any)
	local N = ctx.N
	local center = Common.GroundAim(ctx)
	local radius = N.Radius or 10
	local seed = ctx.CastId + ctx.StartTime
	local white = ctx:Hazard("BoneSpikes", {
		center = center,
		radius = radius,
		count = math.floor(radius * 2.2),
		height = 5.5,
		delay = N.Delay or 0.7,
		rise = 0.12,
		hold = 0.5,
		damage = N.Damage or 16,
		kr = N.KR or 0,
		color = "White",
		seed = seed,
	})
	local orangeDelay = N.OrangeDelay or 1.4
	local ring = ctx:Hazard("BoneSpikes", {
		center = center,
		radius = radius + 1.5,
		ring = true,
		ringWidth = 4,
		count = math.floor(radius * 3),
		height = 4.5,
		delay = orangeDelay,
		warn = math.min(0.6, orangeDelay),
		rise = 0.1,
		hold = 0.6,
		damage = N.OrangeDamage or 12,
		kr = N.KR or 0,
		color = "Orange",
		seed = seed + 1,
	})
	ctx:Fx("Zone", { center = center, radius = radius, hazards = { white, ring } })
end

Abilities.BoneWall = function(ctx: any)
	local N = ctx.N
	local width = N.Width or 26
	local spacing = 2
	local count = math.max(3, math.floor(width / spacing) + 1)
	local start = Common.Feet(ctx) + ctx.FlatDir * 2.5
	local id = ctx:Hazard("BoneLine", {
		origin = LookAlong(start, ctx.FlatDir),
		count = count,
		spacing = spacing,
		height = N.Height or 5,
		speed = N.Speed or 34,
		distance = N.Distance or 60,
		delay = ctx.Ability.Windup or 0.45,
		boneThickness = 0.8,
		damage = N.Damage or 13,
		kr = N.KR or 0,
		color = "Blue",
	})
	ctx:Fx("Wall", { hazard = id })
end

Abilities.Shortcut = function(ctx: any)
	local N = ctx.N
	local from = ctx:RootPosition()
	local dest = DamageMath.ClampAim(from, ctx.Aim, N.Distance or 32)
	if not ctx:Wait(ctx.Ability.Windup or 0.05) then
		return
	end
	ctx:Fx("Vanish", { from = from })
	if ctx:Teleport(LookAlong(dest, ctx.FlatDir)) == nil then
		ctx:Fx("Teleport", { from = from, to = from }) -- nowhere safe to go: reappear in place
	end
end

Abilities.BadTime = function(ctx: any)
	local N = ctx.N
	local center = Common.GroundAim(ctx)
	local radius = N.Radius or 18
	local duration = N.Duration or 6
	local blasters = math.max(1, math.floor(N.Blasters or 6))
	local first = ctx.Ability.Windup or 0.8
	ctx:Status(ctx.Caster, "KRBoost", duration + 1.5, { mult = 2 })
	local rng = Rng.new(Rng.Hash("BadTime", ctx.CastId, ctx.StartTime))
	local ring = radius + 6
	local interval = math.max(0.25, (duration - first - 0.8) / math.max(1, blasters - 1))
	local base = rng:Number(0, 2 * math.pi)
	local step = 2 * math.pi / blasters
	local ids: { number } = {}
	local origin = ctx:RootPosition()
	local half = math.ceil(blasters / 2)
	for i = 1, blasters do
		-- even slots first, then odd ones: consecutive blasters come from far-apart angles
		local k = i - 1
		local slot = if k < half then 2 * k else 2 * (k - half) + 1
		local a = base + slot * step
		local pos = center + Vector3.new(math.cos(a) * ring, 6, math.sin(a) * ring)
		local lateral = rng:Number(-0.45, 0.45) * radius
		local through = center + Vector3.new(-math.sin(a) * lateral, 1.5, math.cos(a) * lateral)
		table.insert(
			ids,
			ctx:Hazard("BlasterBeam", {
				origin = LookAlong(pos, through - pos),
				length = ring * 2 + 8,
				width = 6,
				delay = first + (i - 1) * interval,
				duration = 0.5,
				damage = N.Damage or 16,
				kr = N.KR or 0,
				color = "White",
				style = "Classic",
				spawnFrom = origin,
			})
		)
	end
	local rainInterval = 0.3
	table.insert(
		ids,
		ctx:Hazard("Rain", {
			center = center,
			radius = radius,
			count = math.max(1, math.floor((duration - first) / rainInterval)),
			interval = rainInterval,
			delay = first + 0.2,
			size = 2.6,
			fallHeight = 30,
			fallTime = 0.4,
			damage = N.RainDamage or 8,
			kr = math.floor((N.KR or 8) / 2),
			color = "White",
			visual = "Bone",
			seed = rng:Integer(1, 1000000),
		})
	)
	ctx:Fx("Blaze", { center = center, radius = radius, duration = duration, hazards = ids })
end

return Kit
