--!strict
-- Kits/Common: reusable building blocks for server kit modules (not a kit itself).
-- Every tunable comes from the caller (normally ctx.N = AbilityDef.Numbers).
--
-- API
--   Common.Services() -> { StatusService, DamageService, HazardService, MovementService, AbilityService }
--   Common.ComboStrike(ctx, opts?) -> ({Model}, {[Model]: DamageResult})
--       standard M1: waits Ability.Windup, then a melee box in front of the caster.
--       Numbers: Damage<i> (falls back to Damage1 / Damage), Range [6], KR, ComboWindow (AbilityService),
--       last combo hit only: Knockback, Stagger | Daze (stun seconds), SlowMult + SlowTime (Slowed).
--       opts: { Width: number?, Height: number?, MaxTargets: number?, Kind: string? }
--   Common.DashStrike(ctx, opts) -> {Model}
--       dash along ctx.FlatDir and hit every enemy once along the swept path (segment capsule test, sub-stepped
--       with the dash). opts: { Distance, Time? [0.22], Damage, Radius? [2.5], KR?, Stun?, Knockback?,
--       Windup? [Ability.Windup], Undodgeable?, OnHit?: (Model, DamageResult) -> () }
--   Common.GroundAim(ctx, point?) -> Vector3       ground point under ctx.Aim (or point); falls back to the
--                                                  caster's feet height
--   Common.Feet(ctx) -> Vector3                    ground point under the caster
--   Common.ClampPath(origin, dir, distance, extraIgnore?) -> number   distance before the first wall (- 1.5)
--   Common.SafePosition(ctx, to) -> Vector3?       root position reachable toward `to` (walls, ground <= 20 below)
--   Common.ConeTargets(ctx, origin, dir, range, coneDot, includeDowned?) -> {Model}
--   Common.ArcPositions(center, forward, radius, count, arcDegrees, height?) -> {Vector3}
--       points on a horizontal arc centred on `forward` (arcDegrees total spread)
--   Common.Right(dir) -> Vector3                   horizontal right vector of a facing direction
--   Common.InstallHook(key, stage, fn)             DamageService.AddHook once per server (kit passives)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any

local Combat = script.Parent.Parent:WaitForChild("Combat") :: any
local Validation = require(Combat.Validation) :: any
local Melee = require(Combat.Melee) :: any

local Common = {}

local services: any = nil

function Common.Services(): any
	if services == nil then
		local folder = script.Parent.Parent:WaitForChild("Services") :: any
		services = {
			StatusService = require(folder.StatusService),
			DamageService = require(folder.DamageService),
			HazardService = require(folder.HazardService),
			MovementService = require(folder.MovementService),
			AbilityService = require(folder.AbilityService),
		}
	end
	return services
end

local installed: { [string]: boolean } = {}

function Common.InstallHook(key: string, stage: string, fn: (any, any, any) -> boolean?)
	if installed[key] then
		return
	end
	installed[key] = true
	Common.Services().DamageService.AddHook(stage, fn)
end

---------------------------------------------------------------------------------------------------
-- Geometry helpers

function Common.Right(dir: Vector3): Vector3
	local f = Validation.FlatUnit(dir, Vector3.new(0, 0, -1))
	return f:Cross(Vector3.yAxis).Unit
end

function Common.ArcPositions(
	center: Vector3,
	forward: Vector3,
	radius: number,
	count: number,
	arcDegrees: number,
	height: number?
): { Vector3 }
	local out: { Vector3 } = {}
	local f = Validation.FlatUnit(forward, Vector3.new(0, 0, -1))
	local base = math.atan2(f.Z, f.X)
	local spread = math.rad(arcDegrees)
	local h = height or 0
	for i = 1, count do
		local frac = if count == 1 then 0.5 else (i - 1) / (count - 1)
		local a = base + (frac - 0.5) * spread
		table.insert(out, center + Vector3.new(math.cos(a) * radius, h, math.sin(a) * radius))
	end
	return out
end

function Common.ClampPath(origin: Vector3, dir: Vector3, distance: number, extraIgnore: { Instance }?): number
	if distance <= 0 or dir.Magnitude < 1e-4 then
		return 0
	end
	local hit = Validation.Raycast(origin, dir.Unit * distance, extraIgnore)
	if hit then
		return math.max(0, (hit.Position - origin).Magnitude - 1.5)
	end
	return distance
end

function Common.Feet(ctx: any): Vector3
	local root = ctx:RootPosition()
	local ground = Validation.GroundBelow(root, ctx:RootHeight() + 6)
	return ground or (root - Vector3.new(0, ctx:RootHeight(), 0))
end

function Common.GroundAim(ctx: any, point: Vector3?): Vector3
	local p = point or ctx.Aim
	local ground = Validation.GroundBelow(p + Vector3.new(0, 4, 0), 64)
	if ground then
		return ground
	end
	local feet = Common.Feet(ctx)
	return Vector3.new(p.X, feet.Y, p.Z)
end

function Common.SafePosition(ctx: any, to: Vector3): Vector3?
	local from = ctx:RootPosition()
	local rootHeight = ctx:RootHeight()
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local dist = Common.ClampPath(from, dir, dir.Magnitude)
	local target = from + (if dir.Magnitude > 1e-4 then dir.Unit * dist else Vector3.zero)
	for i = 0, 10 do
		local p = target:Lerp(from, i / 10)
		local ground = Validation.GroundBelow(p + Vector3.new(0, 2, 0), 20 + rootHeight + 2)
		if ground then
			return ground + Vector3.new(0, rootHeight, 0)
		end
	end
	return nil
end

function Common.ConeTargets(
	ctx: any,
	origin: Vector3,
	dir: Vector3,
	range: number,
	coneDot: number,
	includeDowned: boolean?
): { Model }
	local out: { Model } = {}
	local f = Validation.FlatUnit(dir, Vector3.new(0, 0, -1))
	for _, m in ctx:Enemies(includeDowned) do
		local p = Validation.RootPosition(m)
		if p and (p - origin).Magnitude <= range then
			local to = Validation.FlatUnit(p - origin, f)
			if to:Dot(f) >= coneDot then
				table.insert(out, m)
			end
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- Standard attacks

type ComboOpts = { Width: number?, Height: number?, MaxTargets: number?, Kind: string? }

function Common.ComboStrike(ctx: any, opts: ComboOpts?): ({ Model }, { [Model]: any })
	local o: ComboOpts = opts or {}
	local N = ctx.N
	local index = ctx.ComboIndex or 1
	local comboLength = if type(ctx.Ability.Combo) == "number" then ctx.Ability.Combo else 1
	local isLast = index >= comboLength
	local damage = N["Damage" .. index] or N.Damage1 or N.Damage or 0
	local range = N.Range or 6
	local windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0.1
	if not ctx:Wait(windup) then
		return {}, {}
	end
	local stun: number? = nil
	if isLast then
		stun = N.Stagger or N.Daze
	end
	local hits, results = ctx:Melee({
		Offset = CFrame.new(0, 0, -range * 0.5),
		Size = Vector3.new(o.Width or math.max(4, range * 0.8), o.Height or 5, range),
		Damage = damage,
		KR = N.KR,
		Knockback = if isLast then N.Knockback else nil,
		Stun = stun,
		Kind = o.Kind or "Melee",
		MaxTargets = o.MaxTargets,
	})
	if isLast and type(N.SlowMult) == "number" and type(N.SlowTime) == "number" then
		for _, m in hits do
			local r = results[m]
			if r and r.Applied > 0 then
				ctx:Status(m, "Slowed", N.SlowTime, { mult = N.SlowMult })
			end
		end
	end
	ctx:Fx("Strike", { combo = index, last = isLast, hits = #hits })
	return hits, results
end

type DashOpts = {
	Distance: number,
	Time: number?,
	Damage: number,
	Radius: number?,
	KR: number?,
	Stun: number?,
	Knockback: number?,
	Windup: number?,
	Undodgeable: boolean?,
	OnHit: ((Model, any) -> ())?,
}

function Common.DashStrike(ctx: any, opts: DashOpts): { Model }
	local hits: { Model } = {}
	local windup = opts.Windup
	if windup == nil then
		windup = if type(ctx.Ability.Windup) == "number" then ctx.Ability.Windup else 0
	end
	if not ctx:Wait(windup :: number) then
		return hits
	end
	local start = ctx:RootPosition()
	local dir = ctx.FlatDir
	local distance = Common.ClampPath(start, dir, math.max(0, opts.Distance))
	local time = math.max(0.05, opts.Time or 0.22)
	ctx:ForceMove(ctx.Caster, { kind = "Dash", velocity = dir * (distance / time), duration = time })
	ctx:Fx("Dash", { from = start, to = start + dir * distance, time = time })
	local radius = opts.Radius or 2.5
	local steps = math.max(2, math.ceil(time / 0.05))
	local hitSet: { [Model]: boolean } = {}
	local prev = start
	for s = 1, steps do
		if not ctx:Wait(time / steps) then
			break
		end
		local p = start + dir * (distance * s / steps)
		for _, m in Melee.Sweep(prev, p, radius, ctx:Enemies(true)) do
			if not hitSet[m] then
				hitSet[m] = true
				local kb: Vector3? = nil
				if type(opts.Knockback) == "number" and opts.Knockback > 0 then
					kb = dir * opts.Knockback + Vector3.new(0, opts.Knockback * 0.25, 0)
				end
				local result = ctx:Damage(m, {
					Amount = opts.Damage,
					Kind = "Melee",
					KR = opts.KR,
					Stun = opts.Stun,
					Knockback = kb,
					Undodgeable = opts.Undodgeable,
					Position = p,
				})
				if result.Reason == nil then
					table.insert(hits, m)
					if opts.OnHit then
						opts.OnHit(m, result)
					end
				end
			end
		end
		prev = p
	end
	return hits
end

-- Frame helper for kits (CFrame.lookAt-equivalent that also works offline).
Common.LookAlong = HazardDefs.LookAlong

return Common
