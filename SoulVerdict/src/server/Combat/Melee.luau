--!strict
-- Melee: server hitbox queries for close-range attacks (used by CastContext:Melee and server kits).
-- Hitboxes are tested against the same vertical character capsules hazards use (Validation.Capsule +
-- Shared/Combat/HitTest), so melee and hazards agree on where a character is.
--
-- API
--   Melee.Frame(origin: Vector3, flatDir: Vector3, offset: CFrame?) -> CFrame
--       box frame: origin facing flatDir, then offset (e.g. CFrame.new(0, 0, -range/2) = in front)
--   Melee.Query(frame: CFrame, size: Vector3, candidates: {Model}, opts?) -> {Model}
--       models whose capsule overlaps the box, nearest first. opts: { Origin: Vector3?, MaxTargets: number?,
--       Grow: number? (extra studs on every box dimension, default Config.Combat.MeleeLeniency) }
--   Melee.Sweep(a: Vector3, b: Vector3, radius: number, candidates: {Model}, opts?) -> {Model}
--       models whose capsule overlaps the capsule a..b (dash paths, lunges), nearest to `a` first.
--       opts: { MaxTargets: number? }
--   Melee.Swing(ctx, spec: MeleeSpec) -> ({Model}, {[Model]: DamageResult})
--       CastContext:Melee implementation: box in front of the caster (spec.Offset relative to the caster's
--       root position facing ctx.FlatDir; spec.Size + Config.Combat.MeleeLeniency), applies spec damage to
--       every enemy hit (incl. downed humans), returns the models whose hit was processed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any
local HitTest = require(Shared.Combat.HitTest) :: any
local HazardDefs = require(Shared.Combat.HazardDefs) :: any

local Validation = require(script.Parent.Validation) :: any

local Melee = {}

function Melee.Frame(origin: Vector3, flatDir: Vector3, offset: CFrame?): CFrame
	local dir = Validation.FlatUnit(flatDir, Vector3.new(0, 0, -1))
	local base = HazardDefs.LookAlong(origin, dir)
	if offset then
		return base * offset
	end
	return base
end

type QueryOpts = { Origin: Vector3?, MaxTargets: number?, Grow: number? }

local function sortAndCap(hits: { { Model: Model, Dist: number } }, maxTargets: number?): { Model }
	table.sort(hits, function(a, b)
		return a.Dist < b.Dist
	end)
	local out: { Model } = {}
	local limit = if maxTargets and maxTargets > 0 then maxTargets else math.huge
	for _, h in hits do
		if #out >= limit then
			break
		end
		table.insert(out, h.Model)
	end
	return out
end

function Melee.Query(frame: CFrame, size: Vector3, candidates: { Model }, opts: QueryOpts?): { Model }
	local o: QueryOpts = opts or {}
	local grow = if o.Grow ~= nil then o.Grow else Config.Combat.MeleeLeniency
	local volume = HitTest.Grow({ Shape = "Box", CFrame = frame, Size = size }, grow)
	local origin = o.Origin or frame.Position
	local hits = {}
	for _, model in candidates do
		local cap = Validation.Capsule(model)
		if cap and HitTest.MayOverlap(cap, volume) and HitTest.CapsuleVsVolume(cap, volume) then
			local pos = Validation.RootPosition(model) or origin
			table.insert(hits, { Model = model, Dist = (pos - origin).Magnitude })
		end
	end
	return sortAndCap(hits, o.MaxTargets)
end

function Melee.Sweep(
	a: Vector3,
	b: Vector3,
	radius: number,
	candidates: { Model },
	opts: { MaxTargets: number? }?
): { Model }
	local hits = {}
	for _, model in candidates do
		local cap = Validation.Capsule(model)
		if cap and HitTest.CapsuleVsCapsule(cap, a, b, radius) then
			local pos = Validation.RootPosition(model) or a
			table.insert(hits, { Model = model, Dist = (pos - a).Magnitude })
		end
	end
	return sortAndCap(hits, if opts then opts.MaxTargets else nil)
end

function Melee.Swing(ctx: any, spec: any): ({ Model }, { [Model]: any })
	local results: { [Model]: any } = {}
	local root = ctx.Root
	if root == nil or root.Parent == nil or type(spec) ~= "table" then
		return {}, results
	end
	local origin = root.CFrame.Position
	local offset = if typeof(spec.Offset) == "CFrame" then spec.Offset else CFrame.new(0, 0, -3)
	local size = if typeof(spec.Size) == "Vector3" then spec.Size else Vector3.new(5, 5, 6)
	local frame = Melee.Frame(origin, ctx.FlatDir, offset)
	local targets = Melee.Query(frame, size, ctx:Enemies(true), { Origin = origin, MaxTargets = spec.MaxTargets })
	local hitList: { Model } = {}
	local kb = if type(spec.Knockback) == "number" then spec.Knockback else 0
	for _, target in targets do
		local knockback: Vector3? = nil
		if kb > 0 then
			knockback = ctx.FlatDir * kb + Vector3.new(0, math.min(kb * 0.3, 18), 0)
		end
		local result = ctx:Damage(target, {
			Amount = if type(spec.Damage) == "number" then spec.Damage else 0,
			Kind = spec.Kind or "Melee",
			KR = spec.KR,
			Stun = spec.Stun,
			Knockback = knockback,
			Dodgeable = spec.Dodgeable,
			Blockable = spec.Blockable,
			Color = spec.Color,
			Undodgeable = spec.Undodgeable,
			Position = origin,
		})
		if result.Reason == nil then
			table.insert(hitList, target)
			results[target] = result
		end
	end
	return hitList, results
end

return Melee
