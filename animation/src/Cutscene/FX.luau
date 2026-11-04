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
-- Beam: a white-hot core, a coloured glow, a soft halo and a wide haze, all
-- with round caps (capsule ends); bright bands spiral along it, sparks fly
-- off it and thin lightning crackles round it (+ optional light)
------------------------------------------------------------------------------
export type Beam = {
	core: Part,
	glow: Part,
	halo: Part,
	haze: Part,
	tip: Part,
	caps: { Part },
	streaks: { Part },
	sparks: { Part },
	bolt: Bolt,
	light: string?,
}

local STREAKS, SPARKS = 8, 10

function FX.beam(scene: Builder.Scene, name: string, color: Color3, withLight: boolean?): Beam
	local model = "FX_" .. name
	local hot = Util.mix(color, Color3.new(1, 1, 1), 0.75)
	local function p(shape: string, col: Color3, tr: number, n: string): Part
		return Builder.fx(scene, model, shape, Vector3.one, col, "Neon", tr, name .. n)
	end
	local b: Beam = {
		core = p("Cylinder", hot, 0, "Core"),
		glow = p("Cylinder", color, 0.3, "Glow"),
		halo = p("Cylinder", color, 0.72, "Halo"),
		haze = p("Cylinder", color, 0.9, "Haze"),
		tip = p("Ball", Util.mix(color, Color3.new(1, 1, 1), 0.6), 0.1, "Tip"),
		caps = {},
		streaks = {},
		sparks = {},
		bolt = FX.bolts(scene, name .. "Crackle", Util.mix(color, Color3.new(1, 1, 1), 0.4), 12),
		light = nil,
	}
	for i = 1, 6 do
		local layer = (i - 1) % 3
		b.caps[i] = p("Ball", if layer == 0 then hot else color, ({ 0, 0.3, 0.72 })[layer + 1], "Cap")
	end
	for i = 1, STREAKS do
		b.streaks[i] = p("Ellipsoid", Util.mix(color, Color3.new(1, 1, 1), if i % 2 == 0 then 0.85 else 0.45), 0.15, "Streak")
	end
	for i = 1, SPARKS do
		b.sparks[i] = p("Ball", Util.mix(color, Color3.new(1, 1, 1), 0.55), 0, "Spark")
	end
	if withLight then
		Builder.light(scene, name .. "Light", "Point", b.tip, color, 40)
		b.light = name .. "Light"
	end
	return b
end

-- width = beam diameter, k = intensity 0..1 (fades transparency)
function FX.placeBeam(ctx: Timeline.Ctx, b: Beam, a: Vector3, c: Vector3, width: number, k: number, wobble: number?)
	if k <= 0.001 then
		return
	end
	local t = ctx.t
	local d = c - a
	local len = d.Magnitude
	if len < 1e-3 then
		return
	end
	local dir = d / len
	-- the width breathes and flickers
	local w = width * (1 + (math.sin(t * 60) * 0.05 + math.sin(t * 23 + 1.3) * 0.04) * (wobble or 1))
	local cf = along(a, c, t * 9)
	local layers = { { b.core, 0.36, 1 - k }, { b.glow, 0.72, 1 - k * 0.7 }, { b.halo, 1.35, 1 - k * 0.3 }, { b.haze, 2.4, 1 - k * 0.12 } }
	for li, L in layers do
		local part, f, tr = L[1] :: Part, L[2] :: number, L[3] :: number
		ctx:place(part, cf)
		ctx:prop(part, { s = Vector3.new(len, w * f, w * f), t = tr })
		-- round caps on the three inner layers, at both ends
		if li <= 3 then
			for e = 0, 1 do
				-- the start (at a hand or a mouth) is a little narrower
				local cap = b.caps[li + e * 3]
				ctx:place(cap, CFrame.new(if e == 0 then a else c))
				ctx:prop(cap, { s = Vector3.one * w * f * (if e == 0 then 0.7 else 1), t = tr })
			end
		end
	end
	-- the bright head
	ctx:place(b.tip, CFrame.new(c))
	local tw = w * (1.7 + math.sin(t * 47) * 0.2)
	ctx:prop(b.tip, { s = Vector3.new(tw, tw, tw), t = 1 - k * 0.9 })
	-- bands spiralling along the beam towards the head
	local side1 = dir:Cross(Vector3.new(0, 1, 0))
	if side1.Magnitude < 1e-3 then
		side1 = dir:Cross(Vector3.new(1, 0, 0))
	end
	side1 = side1.Unit
	local side2 = dir:Cross(side1).Unit
	local speed = math.max(30, len * 1.6)
	for i, sp in b.streaks do
		local f = (t * speed / len + i / #b.streaks) % 1
		local ang = t * 7 + i * 2.39 + f * 9
		local r = w * (0.34 + 0.08 * math.sin(i * 1.7))
		local center = a + d * f + (side1 * math.cos(ang) + side2 * math.sin(ang)) * r
		local sl = math.min(len * 0.22, w * 3.5)
		ctx:place(sp, along(center - dir * sl / 2, center + dir * sl / 2))
		local fade = math.sin(f * math.pi)
		ctx:prop(sp, { s = Vector3.new(sl, w * 0.09, w * 0.09), t = 1 - k * 0.9 * fade })
	end
	-- sparks thrown off sideways
	local rr = Util.rng(len * 13 + 7)
	for i, sp in b.sparks do
		local f0 = Util.randRange(rr, 0.05, 1)
		local a0 = Util.randRange(rr, 0, math.pi * 2)
		local ph = (t * Util.randRange(rr, 1.2, 2.4) + i * 0.37) % 1
		local out = side1 * math.cos(a0) + side2 * math.sin(a0)
		local pos = a + d * f0 + out * (w * 0.4 + ph * w * 2.6) + dir * ph * w * 1.5
		local s = w * 0.13 * (1 - ph)
		ctx:place(sp, along(pos - dir * s * 1.5, pos + dir * s * 1.5))
		ctx:prop(sp, { s = Vector3.new(s * 3, s, s), t = ph * 0.6 + (1 - k) })
	end
	-- two thin bolts crackling along the surface
	local step = math.floor(t * 18)
	local br = Util.rng(step * 31 + math.floor(len))
	local idx = 1
	for j = 1, 2 do
		local f1 = Util.randRange(br, 0, 0.7)
		local f2 = math.min(1, f1 + Util.randRange(br, 0.12, 0.3))
		local a1 = Util.randRange(br, 0, math.pi * 2)
		local o1 = (side1 * math.cos(a1) + side2 * math.sin(a1)) * w * 0.55
		idx = FX.placeBolt(ctx, b.bolt, idx, a + d * f1 + o1, a + d * f2 + o1 * 1.2, 6, 0.12, w * 0.045, j + step, 18)
	end
	if b.light then
		ctx:light(b.light, 6 * k, nil, 30 + width * 4)
	end
end

------------------------------------------------------------------------------
-- Lightning: a pool of thin neon segments forming jagged bolts
------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- Curved beam: a chain of short glowing segments (core, glow, soft halo)
-- laid along any curve, overlapping so the bends stay round
------------------------------------------------------------------------------
export type CurvedBeam = { cores: { Part }, glows: { Part }, halos: { Part }, hazes: { Part }, joints: { Part }, head: Part, n: number }

function FX.curvedBeam(scene: Builder.Scene, name: string, color: Color3, n: number): CurvedBeam
	local cores, glows, halos, hazes, joints = {}, {}, {}, {}, {}
	local hot = Util.mix(color, Color3.new(1, 1, 1), 0.75)
	for i = 1, n do
		cores[i] = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, hot, "Neon", 0, name .. "Core")
		glows[i] = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, color, "Neon", 0.35, name .. "Glow")
		halos[i] = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, color, "Neon", 0.8, name .. "Halo")
		hazes[i] = Builder.fx(scene, "FX_" .. name, "Cylinder", Vector3.one, color, "Neon", 0.92, name .. "Haze")
		-- round joints between segments (glow layer) so the bends stay round
		joints[i] = Builder.fx(scene, "FX_" .. name, "Ball", Vector3.one, color, "Neon", 0.35, name .. "Joint")
	end
	local head = Builder.fx(scene, "FX_" .. name, "Ball", Vector3.one, hot, "Neon", 0.1, name .. "Head")
	return { cores = cores, glows = glows, halos = halos, hazes = hazes, joints = joints, head = head, n = n }
end

-- point(f) gives the curve; the beam covers f0..f1 and swells near its head
function FX.placeCurvedBeam(ctx: Timeline.Ctx, cb: CurvedBeam, point: (number) -> Vector3, f0: number, f1: number, width: number, k: number)
	if k <= 0.001 or f1 <= f0 + 1e-3 then
		return
	end
	for i = 1, cb.n do
		local fa = f0 + (f1 - f0) * (i - 1) / cb.n
		local fb = f0 + (f1 - f0) * i / cb.n
		local a, b = point(fa), point(fb)
		local len = (b - a).Magnitude
		local swell = 1 + 0.35 * (i / cb.n) ^ 3
		local w = width * swell * (1 + math.sin(ctx.t * 55 + i * 1.7) * 0.07)
		local cf = along(a, b, ctx.t * 9 + i)
		ctx:place(cb.cores[i], cf)
		ctx:prop(cb.cores[i], { s = Vector3.new(len + w * 0.38, w * 0.38, w * 0.38), t = 1 - k })
		ctx:place(cb.glows[i], cf)
		ctx:prop(cb.glows[i], { s = Vector3.new(len + w * 0.75, w * 0.75, w * 0.75), t = 1 - k * 0.65 })
		ctx:place(cb.halos[i], cf)
		ctx:prop(cb.halos[i], { s = Vector3.new(len + w * 1.5, w * 1.5, w * 1.5), t = 1 - k * 0.22 })
		ctx:place(cb.hazes[i], cf)
		ctx:prop(cb.hazes[i], { s = Vector3.new(len + w * 2.4, w * 2.4, w * 2.4), t = 1 - k * 0.1 })
		ctx:place(cb.joints[i], CFrame.new(a))
		ctx:prop(cb.joints[i], { s = Vector3.one * w * 0.75, t = 1 - k * 0.65 })
		if i == cb.n then
			local hw = w * (1.5 + math.sin(ctx.t * 41) * 0.15)
			ctx:place(cb.head, CFrame.new(b))
			ctx:prop(cb.head, { s = Vector3.one * hw, t = 1 - k * 0.9 })
		end
	end
end

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
		Util.rand(r) -- the first value barely changes between nearby seeds
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
