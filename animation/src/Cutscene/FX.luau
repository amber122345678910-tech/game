--!strict
-- Energy effects built from Neon parts (bloom makes them glow) and placed
-- by the timeline each frame: beams, lightning bolts, shard bursts, splash
-- blobs, shockwave rings, glowing cores and radial rays.
local Builder = require(script.Parent.Builder)
local Timeline = require(script.Parent.Timeline)
local Util = require(script.Parent.Util)

local FX = {}

type Part = Builder.PartSpec

-- CFrame for a Cylinder/Block whose X axis runs from a to b
local function along(a: Vector3, b: Vector3, roll: number?): CFrame
	local d = b - a
	local len = d.Magnitude
	if len < 1e-4 then
		return CFrame.new(a)
	end
	local x = d / len
	local up = if math.abs(x.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	local mid = (a + b) / 2
	local cf = CFrame.new(mid.X, mid.Y, mid.Z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
	if roll then
		cf = cf * CFrame.Angles(roll, 0, 0)
	end
	return cf
end
FX.along = along

------------------------------------------------------------------------------
-- Beam: white-hot core, coloured glow, soft outer halo (+ optional light)
------------------------------------------------------------------------------
export type Beam = { core: Part, glow: Part, halo: Part, tip: Part, light: string? }

function FX.beam(scene: Builder.Scene, name: string, color: Color3, withLight: boolean?): Beam
	local core = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, Util.mix(color, Color3.new(1, 1, 1), 0.75), "Neon", 0, name .. "Core")
	local glow = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, color, "Neon", 0.35, name .. "Glow")
	local halo = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, color, "Neon", 0.78, name .. "Halo")
	local tip = Builder.fx(scene, "FX_" .. name, "Ball", Vector3.one, Util.mix(color, Color3.new(1, 1, 1), 0.6), "Neon", 0.1, name .. "Tip")
	local b: Beam = { core = core, glow = glow, halo = halo, tip = tip, light = nil }
	if withLight then
		Builder.light(scene, name .. "Light", "Point", tip, color, 40)
		b.light = name .. "Light"
	end
	return b
end

-- width = beam diameter, k = intensity 0..1 (fades transparency)
function FX.placeBeam(ctx: Timeline.Ctx, b: Beam, a: Vector3, c: Vector3, width: number, k: number, wobble: number?)
	if k <= 0.001 then
		return
	end
	local len = (c - a).Magnitude
	local w = width * (1 + math.sin(ctx.t * 60) * 0.06 * (wobble or 1))
	local cf = along(a, c, ctx.t * 9)
	ctx:place(b.core, cf)
	ctx:prop(b.core, { s = Vector3.new(len, w * 0.38, w * 0.38), t = 1 - k })
	ctx:place(b.glow, cf)
	ctx:prop(b.glow, { s = Vector3.new(len, w * 0.75, w * 0.75), t = 1 - k * 0.65 })
	ctx:place(b.halo, cf)
	ctx:prop(b.halo, { s = Vector3.new(len * 1.02, w * 1.5, w * 1.5), t = 1 - k * 0.22 })
	ctx:place(b.tip, CFrame.new(c))
	local tw = w * (1.6 + math.sin(ctx.t * 47) * 0.2)
	ctx:prop(b.tip, { s = Vector3.new(tw, tw, tw), t = 1 - k * 0.9 })
	if b.light then
		ctx:light(b.light, 6 * k, nil, 30 + width * 4)
	end
end

------------------------------------------------------------------------------
-- Lightning: a pool of thin neon segments forming jagged bolts
------------------------------------------------------------------------------
export type Bolt = { segs: { Part }, color: Color3 }

function FX.bolts(scene: Builder.Scene, name: string, color: Color3, n: number): Bolt
	local segs = {}
	for i = 1, n do
		segs[i] = Builder.fx(scene, "FX_" .. name, "Block", Vector3.one, if i % 4 == 0 then Color3.new(1, 1, 1) else color, "Neon", 0, name)
	end
	return { segs = segs, color = color }
end

-- Draw `count` bolts with `nPer` segments each from the pool, starting at
-- `first`. Points are generated from a seed that changes `rate` times a second.
function FX.placeBolt(ctx: Timeline.Ctx, bolt: Bolt, first: number, a: Vector3, b: Vector3, nPer: number, jitter: number, width: number, seed: number, rate: number?): number
	local step = math.floor(ctx.t * (rate or 14))
	local r = Util.rng(seed * 7919 + step * 104729)
	local d = b - a
	local len = d.Magnitude
	if len < 1e-3 then
		return first
	end
	local side1 = d:Cross(Vector3.new(0, 1, 0))
	if side1.Magnitude < 1e-3 then
		side1 = d:Cross(Vector3.new(1, 0, 0))
	end
	side1 = side1.Unit
	local side2 = d.Unit:Cross(side1).Unit
	local prev = a
	local idx = first
	for i = 1, nPer do
		if idx > #bolt.segs then
			break
		end
		local f = i / nPer
		local p = a + d * f
		if i < nPer then
			local amp = jitter * len * math.sin(f * math.pi)
			p += side1 * Util.randRange(r, -amp, amp) + side2 * Util.randRange(r, -amp, amp)
		end
		local seg = bolt.segs[idx]
		local sl = (p - prev).Magnitude
		ctx:place(seg, along(prev, p))
		ctx:prop(seg, { s = Vector3.new(sl + width, width, width), t = 0 })
		prev = p
		idx += 1
	end
	return idx
end

------------------------------------------------------------------------------
-- Shards / sparks bursting from a point
------------------------------------------------------------------------------
export type Burst = { parts: { Part }, seed: number }

function FX.burst(scene: Builder.Scene, name: string, color: Color3, n: number, shape: string?, seed: number?): Burst
	local parts = {}
	for i = 1, n do
		local c = if i % 5 == 0 then Util.mix(color, Color3.new(1, 1, 1), 0.6) else color
		parts[i] = Builder.fx(scene, "FX_" .. name, shape or "Wedge", Vector3.one, c, "Neon", 0, name)
	end
	return { parts = parts, seed = seed or 1 }
end

-- age: seconds since the burst; dir: main direction (nil = all around);
-- spread 0..1; speed studs/s; size of a shard; life seconds
function FX.placeBurst(ctx: Timeline.Ctx, bu: Burst, origin: Vector3, age: number, speed: number, size: number, life: number, dir: Vector3?, spread: number?, gravity: number?)
	if age < 0 or age > life * 1.6 then
		return
	end
	local r = Util.rng(bu.seed * 31337)
	for i, p in bu.parts do
		local v: Vector3
		local rx, ry, rz = Util.randRange(r, -1, 1), Util.randRange(r, -1, 1), Util.randRange(r, -1, 1)
		local rv = Vector3.new(rx, ry, rz)
		if rv.Magnitude < 0.05 then
			rv = Vector3.new(0, 1, 0)
		end
		rv = rv.Unit
		if dir then
			v = (dir.Unit + rv * (spread or 0.5)).Unit
		else
			v = rv
		end
		local sp = speed * Util.randRange(r, 0.45, 1.25)
		local myLife = life * Util.randRange(r, 0.6, 1.4)
		local spin = Util.randRange(r, -9, 9)
		local s0 = size * Util.randRange(r, 0.5, 1.4)
		local u = age / myLife
		if u < 1 then
			-- decelerating flight
			local dist = sp * myLife * (1 - (1 - u) ^ 2) / 2
			local pos = origin + v * dist + Vector3.new(0, -(gravity or 0) * age * age * 0.5, 0)
			local cf = along(pos, pos + v, spin * age) * CFrame.Angles(0, spin * age * 0.7, 0)
			local s = s0 * (1 - u * 0.75)
			ctx:place(p, cf)
			ctx:prop(p, { s = Vector3.new(s * 2.4, s, s * 0.5), t = math.clamp(u * u, 0, 1) })
		end
		local _ = i
	end
end

------------------------------------------------------------------------------
-- Shockwave ring and glowing core
------------------------------------------------------------------------------
function FX.ring(scene: Builder.Scene, name: string, color: Color3): Part
	return Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, color, "Neon", 0.3, name)
end

-- ring lies in the plane perpendicular to `normal`
function FX.placeRing(ctx: Timeline.Ctx, ring: Part, center: Vector3, normal: Vector3, radius: number, thickness: number, k: number)
	if k <= 0.001 then
		return
	end
	ctx:place(ring, along(center - normal.Unit * thickness / 2, center + normal.Unit * thickness / 2))
	ctx:prop(ring, { s = Vector3.new(thickness, radius * 2, radius * 2), t = 1 - k })
end

function FX.core(scene: Builder.Scene, name: string, color: Color3): Part
	return Builder.fx(scene, "FX_" .. name, "Ball", Vector3.one, color, "Neon", 0, name)
end

function FX.placeCore(ctx: Timeline.Ctx, core: Part, center: Vector3, radius: number, k: number)
	if k <= 0.001 then
		return
	end
	ctx:place(core, CFrame.new(center))
	ctx:prop(core, { s = Vector3.new(radius * 2, radius * 2, radius * 2), t = 1 - k })
end

------------------------------------------------------------------------------
-- Rays: long thin neon spikes radiating from a centre (energy clash)
------------------------------------------------------------------------------
export type Rays = { parts: { Part }, seed: number }

function FX.rays(scene: Builder.Scene, name: string, colors: { Color3 }, n: number, seed: number): Rays
	local parts = {}
	for i = 1, n do
		parts[i] = Builder.fx(scene, "FX_" .. name, "Block", Vector3.one, colors[(i - 1) % #colors + 1], "Neon", 0, name)
	end
	return { parts = parts, seed = seed }
end

-- rays flicker: each ray gets a new length/angle `rate` times per second
function FX.placeRays(ctx: Timeline.Ctx, rays: Rays, center: Vector3, basis: CFrame, len: number, width: number, k: number, rate: number?, bias: Vector3?)
	if k <= 0.001 then
		return
	end
	local step = math.floor(ctx.t * (rate or 12))
	for i, p in rays.parts do
		local r = Util.rng(rays.seed * 1000 + i * 97 + step * 7)
		local ang = Util.randRange(r, 0, math.pi * 2)
		local el = Util.randRange(r, -0.5, 0.5)
		local dir = basis:VectorToWorldSpace(Vector3.new(math.cos(ang), math.sin(ang), el)).Unit
		if bias then
			dir = (dir + bias * 0.6).Unit
		end
		local l = len * Util.randRange(r, 0.3, 1.2)
		local s0 = Util.randRange(r, 0.1, 0.5) * l
		local a = center + dir * s0
		local b = center + dir * (s0 + l)
		local w = width * Util.randRange(r, 0.4, 1.6)
		ctx:place(p, along(a, b))
		ctx:prop(p, { s = Vector3.new(l, w, w), t = 1 - k * Util.randRange(r, 0.5, 1) })
	end
end

return FX
