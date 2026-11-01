--!strict
-- HitTest: exact intersection tests between a character CAPSULE and hazard / hitbox VOLUMES.
-- Pure math, Lune-safe, deterministic (server hit tests + client "would this hit me" previews).
--
-- Capsule = { A: Vector3, B: Vector3, R: number }  -- segment A..B (sphere centres), radius R.
-- Volume  = { Shape, CFrame, Size, Key? }  (see Types.Volume):
--   "Box"      CFrame = centre/orientation, Size = full extents.
--   "Ball"     CFrame.Position = centre, Size.X = diameter.
--   "Capsule"  CFrame.Position = centre, axis = CFrame.UpVector, Size.X = diameter,
--              Size.Y = total length tip-to-tip (a value <= Size.X is a ball).
--   "Cylinder" CFrame.Position = centre, axis = CFrame.UpVector, Size.X = diameter, Size.Y = height (flat caps).
--   "Ring"     annulus: like Cylinder (Size.X = OUTER diameter, Size.Y = height) with a hole;
--              Size.Z = band thickness, inner radius = max(0, Size.X/2 - Size.Z).
-- Character capsules are vertical (axis = world Y). Every test is exact except Ring vs a NON-parallel
-- capsule (dense sampling, error < 1 % of the segment length) — characters are always vertical so the
-- runtime path is exact.
--
-- API
--   HitTest.CharacterCapsule(rootPos, scale?, groundOffset?, radius?, height?) -> Capsule
--       radius/height default to Config.Combat.CharacterRadius/CharacterHeight; all are multiplied by scale.
--       groundOffset = distance from rootPos down to the feet (default 0.6 * height * scale);
--       the capsule spans [feet, feet + height*scale].
--   HitTest.MakeCapsule(a, b, radius) -> Capsule              (e.g. a swept sphere / dash path)
--   HitTest.Shrink(volume, forgiveness, maxMargin?) -> Volume  "favour the dodger": the thinnest dimension is
--       scaled by `forgiveness` (0..1, e.g. Config.Combat.HazardForgiveness) and every other dimension loses
--       the same absolute margin; the margin is capped at maxMargin (default 1 stud) so big zones keep
--       their visual edge within a stud.
--   HitTest.Grow(volume, extra) -> Volume                      "favour the attacker": +extra on every dimension
--   HitTest.CapsuleVsVolume(cap, volume) -> boolean
--   HitTest.Hits(cap, volume, forgiveness?, maxMargin?) -> boolean   Shrink (if forgiveness < 1) then test
--   HitTest.CapsuleVsBall(cap, centre, radius) -> boolean
--   HitTest.CapsuleVsCapsule(cap, a, b, radius) -> boolean
--   HitTest.CapsuleVsBox(cap, boxCFrame, boxSize) -> boolean
--   HitTest.CapsuleVsCylinder(cap, cframe, diameter, height) -> boolean
--   HitTest.CapsuleVsRing(cap, cframe, outerDiameter, height, thickness) -> boolean
--   HitTest.SegmentDistanceSq(cap.A, cap.B, volume) -> number  squared distance from the segment to the solid
--   HitTest.PointDistance(point, volume) -> number             distance from a point to the solid (0 inside)
--   HitTest.ContainsPoint(volume, point) -> boolean
--   HitTest.ClosestSegmentPoints(p1, q1, p2, q2) -> (distSq, c1, c2)
--   HitTest.BoundingRadius(volume) -> number                   bounding-sphere radius around CFrame.Position
--   HitTest.MayOverlap(cap, volume) -> boolean                 cheap bounding-sphere broadphase

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

export type Volume = Types.Volume
export type Capsule = { A: Vector3, B: Vector3, R: number }

local HitTest = {}

local EPS = 1e-9
local DEFAULT_MAX_MARGIN = 1.0

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

---------------------------------------------------------------------------------------------------
-- Construction

function HitTest.MakeCapsule(a: Vector3, b: Vector3, radius: number): Capsule
	return { A = a, B = b, R = radius }
end

function HitTest.CharacterCapsule(
	rootPos: Vector3,
	scale: number?,
	groundOffset: number?,
	radius: number?,
	height: number?
): Capsule
	local s = scale or 1
	if s <= 0 then
		s = 1
	end
	local r = (radius or Config.Combat.CharacterRadius) * s
	local h = (height or Config.Combat.CharacterHeight) * s
	local feet = rootPos.Y - (groundOffset or 0.6 * h)
	local lowY = feet + r
	local highY = math.max(lowY, feet + h - r)
	return {
		A = Vector3.new(rootPos.X, lowY, rootPos.Z),
		B = Vector3.new(rootPos.X, highY, rootPos.Z),
		R = r,
	}
end

---------------------------------------------------------------------------------------------------
-- Volume size adjustments

function HitTest.Shrink(volume: Volume, forgiveness: number, maxMargin: number?): Volume
	local f = clamp(forgiveness, 0.05, 1)
	if f >= 1 then
		return volume
	end
	local cap = maxMargin or DEFAULT_MAX_MARGIN
	local s = volume.Size
	local k = 1 - f
	local newSize: Vector3
	local shape = volume.Shape
	if shape == "Box" then
		local m = math.min(k * math.min(s.X, s.Y, s.Z) * 0.5, cap)
		newSize = Vector3.new(math.max(0, s.X - 2 * m), math.max(0, s.Y - 2 * m), math.max(0, s.Z - 2 * m))
	elseif shape == "Ball" then
		local r = s.X * 0.5
		local m = math.min(k * r, cap)
		newSize = Vector3.new(2 * (r - m), 2 * (r - m), 2 * (r - m))
	elseif shape == "Capsule" then
		local r = s.X * 0.5
		local m = math.min(k * r, cap)
		newSize = Vector3.new(2 * (r - m), math.max(0, s.Y - 2 * m), 2 * (r - m))
	elseif shape == "Cylinder" then
		local r = s.X * 0.5
		local m = math.min(k * math.min(r, s.Y * 0.5), cap)
		newSize = Vector3.new(2 * (r - m), math.max(0, s.Y - 2 * m), 2 * (r - m))
	elseif shape == "Ring" then
		local r = s.X * 0.5
		local band = math.min(s.Z, r)
		local m = math.min(k * math.min(band * 0.5, s.Y * 0.5), cap)
		newSize = Vector3.new(2 * (r - m), math.max(0, s.Y - 2 * m), math.max(0, band - 2 * m))
	else
		return volume
	end
	return { Shape = volume.Shape, CFrame = volume.CFrame, Size = newSize, Key = volume.Key }
end

function HitTest.Grow(volume: Volume, extra: number): Volume
	if extra == 0 then
		return volume
	end
	local s = volume.Size
	local shape = volume.Shape
	local newSize: Vector3
	if shape == "Ring" then
		-- grow the band outward and inward, and the height
		newSize = Vector3.new(s.X + extra, s.Y + extra, s.Z + extra)
	else
		newSize = Vector3.new(math.max(0, s.X + extra), math.max(0, s.Y + extra), math.max(0, s.Z + extra))
	end
	return { Shape = volume.Shape, CFrame = volume.CFrame, Size = newSize, Key = volume.Key }
end

---------------------------------------------------------------------------------------------------
-- Segment primitives

-- Closest points between segments p1q1 and p2q2 (Ericson, Real-Time Collision Detection 5.1.9).
function HitTest.ClosestSegmentPoints(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): (number, Vector3, Vector3)
	local d1 = q1 - p1
	local d2 = q2 - p2
	local r = p1 - p2
	local a = d1:Dot(d1)
	local e = d2:Dot(d2)
	local f = d2:Dot(r)
	local s, t = 0, 0
	if a <= EPS and e <= EPS then
		return r:Dot(r), p1, p2
	end
	if a <= EPS then
		s = 0
		t = clamp(f / e, 0, 1)
	else
		local c = d1:Dot(r)
		if e <= EPS then
			t = 0
			s = clamp(-c / a, 0, 1)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			if denom > EPS then
				s = clamp((b * f - c * e) / denom, 0, 1)
			else
				s = 0
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = clamp(-c / a, 0, 1)
			elseif t > 1 then
				t = 1
				s = clamp((b - c) / a, 0, 1)
			end
		end
	end
	local c1 = p1 + d1 * s
	local c2 = p2 + d2 * t
	local diff = c1 - c2
	return diff:Dot(diff), c1, c2
end

local function pointSegmentDistSq(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local denom = ab:Dot(ab)
	local t = 0
	if denom > EPS then
		t = clamp((p - a):Dot(ab) / denom, 0, 1)
	end
	local c = a + ab * t
	local d = p - c
	return d:Dot(d)
end

-- Squared distance from segment (p0 + t*d, t in [0,1]) to an axis-aligned box centred at the origin with
-- half extents (hx, hy, hz). Exact: the function is piecewise quadratic between the breakpoints where a
-- coordinate crosses a face plane; each piece is minimised analytically.
local function segmentAabbDistSq(p0: Vector3, d: Vector3, hx: number, hy: number, hz: number): number
	local ps = { p0.X, p0.Y, p0.Z }
	local ds = { d.X, d.Y, d.Z }
	local hs = { hx, hy, hz }

	local function distSqAt(t: number): number
		local sum = 0
		for i = 1, 3 do
			local x = ps[i] + ds[i] * t
			local h = hs[i]
			if x > h then
				sum += (x - h) * (x - h)
			elseif x < -h then
				sum += (x + h) * (x + h)
			end
		end
		return sum
	end

	local breaks = { 0, 1 }
	for i = 1, 3 do
		local di = ds[i]
		if math.abs(di) > EPS then
			local t1 = (hs[i] - ps[i]) / di
			local t2 = (-hs[i] - ps[i]) / di
			if t1 > 0 and t1 < 1 then
				table.insert(breaks, t1)
			end
			if t2 > 0 and t2 < 1 then
				table.insert(breaks, t2)
			end
		end
	end
	table.sort(breaks)

	local best = math.min(distSqAt(0), distSqAt(1))
	for k = 1, #breaks - 1 do
		local lo, hi = breaks[k], breaks[k + 1]
		if hi - lo > EPS then
			local mid = (lo + hi) * 0.5
			-- On this piece every axis is consistently below, inside or above its slab.
			local A, B = 0, 0
			for i = 1, 3 do
				local x = ps[i] + ds[i] * mid
				local h = hs[i]
				local bound: number? = nil
				if x > h then
					bound = h
				elseif x < -h then
					bound = -h
				end
				if bound then
					local off = ps[i] - bound
					A += ds[i] * ds[i]
					B += 2 * ds[i] * off
				end
			end
			local t = lo
			if A > EPS then
				t = clamp(-B / (2 * A), lo, hi)
			end
			local v = distSqAt(t)
			if v < best then
				best = v
			end
		end
	end
	return best
end

-- Distance (squared) from a point to a solid cylinder/annulus in its local frame (axis = Y).
local function pointCylDistSq(x: number, y: number, z: number, outerR: number, innerR: number, halfH: number): number
	local r = math.sqrt(x * x + z * z)
	local dr = 0
	if r > outerR then
		dr = r - outerR
	elseif r < innerR then
		dr = innerR - r
	end
	local dy = math.max(0, math.abs(y) - halfH)
	return dr * dr + dy * dy
end

-- Segment vs solid cylinder (innerR = 0) or annulus (innerR > 0), local frame (axis = Y).
local function segmentCylDistSq(p0: Vector3, d: Vector3, outerR: number, innerR: number, halfH: number): number
	local horiz = d.X * d.X + d.Z * d.Z
	if horiz <= 1e-12 then
		-- Segment parallel to the axis (vertical character vs vertical zone): exact decomposition.
		local r = math.sqrt(p0.X * p0.X + p0.Z * p0.Z)
		local dr = 0
		if r > outerR then
			dr = r - outerR
		elseif r < innerR then
			dr = innerR - r
		end
		local y0 = math.min(p0.Y, p0.Y + d.Y)
		local y1 = math.max(p0.Y, p0.Y + d.Y)
		local dy = 0
		if y0 > halfH then
			dy = y0 - halfH
		elseif y1 < -halfH then
			dy = -halfH - y1
		end
		return dr * dr + dy * dy
	end
	local function f(t: number): number
		return pointCylDistSq(p0.X + d.X * t, p0.Y + d.Y * t, p0.Z + d.Z * t, outerR, innerR, halfH)
	end
	if innerR <= 0 then
		-- Distance to a convex solid is convex along a line: golden-section search is exact to tolerance.
		local lo, hi = 0, 1
		local g = 0.6180339887498949
		local x1 = hi - g * (hi - lo)
		local x2 = lo + g * (hi - lo)
		local f1, f2 = f(x1), f(x2)
		for _ = 1, 48 do
			if f1 < f2 then
				hi = x2
				x2, f2 = x1, f1
				x1 = hi - g * (hi - lo)
				f1 = f(x1)
			else
				lo = x1
				x1, f1 = x2, f2
				x2 = lo + g * (hi - lo)
				f2 = f(x2)
			end
		end
		return math.min(f(0), f(1), f1, f2)
	end
	-- Annulus is not convex: dense sampling plus local refinement around the best sample.
	local n = 64
	local bestT, best = 0, f(0)
	for i = 1, n do
		local t = i / n
		local v = f(t)
		if v < best then
			best, bestT = v, t
		end
	end
	local lo, hi = math.max(0, bestT - 1 / n), math.min(1, bestT + 1 / n)
	for _ = 1, 24 do
		local m1 = lo + (hi - lo) / 3
		local m2 = hi - (hi - lo) / 3
		if f(m1) < f(m2) then
			hi = m2
		else
			lo = m1
		end
	end
	return math.min(best, f((lo + hi) * 0.5))
end

---------------------------------------------------------------------------------------------------
-- Volume distance

local function localSegment(a: Vector3, b: Vector3, cf: CFrame): (Vector3, Vector3)
	local la = cf:PointToObjectSpace(a)
	local lb = cf:PointToObjectSpace(b)
	return la, lb - la
end

-- Squared distance from segment a..b to the solid described by `volume`.
function HitTest.SegmentDistanceSq(a: Vector3, b: Vector3, volume: Volume): number
	local shape = volume.Shape
	local cf = volume.CFrame
	local s = volume.Size
	if shape == "Ball" then
		local r = s.X * 0.5
		local d = math.sqrt(pointSegmentDistSq(cf.Position, a, b)) - r
		return if d > 0 then d * d else 0
	elseif shape == "Capsule" then
		local r = s.X * 0.5
		local half = math.max(0, s.Y * 0.5 - r)
		local up = cf.UpVector
		local c = cf.Position
		local d2 = HitTest.ClosestSegmentPoints(a, b, c - up * half, c + up * half)
		local d = math.sqrt(d2) - r
		return if d > 0 then d * d else 0
	elseif shape == "Box" then
		local p0, d = localSegment(a, b, cf)
		return segmentAabbDistSq(p0, d, s.X * 0.5, s.Y * 0.5, s.Z * 0.5)
	elseif shape == "Cylinder" then
		local p0, d = localSegment(a, b, cf)
		return segmentCylDistSq(p0, d, s.X * 0.5, 0, s.Y * 0.5)
	elseif shape == "Ring" then
		local p0, d = localSegment(a, b, cf)
		local outer = s.X * 0.5
		local inner = math.max(0, outer - s.Z)
		return segmentCylDistSq(p0, d, outer, inner, s.Y * 0.5)
	end
	return math.huge
end

function HitTest.PointDistance(point: Vector3, volume: Volume): number
	return math.sqrt(HitTest.SegmentDistanceSq(point, point, volume))
end

function HitTest.ContainsPoint(volume: Volume, point: Vector3): boolean
	return HitTest.SegmentDistanceSq(point, point, volume) <= 1e-12
end

---------------------------------------------------------------------------------------------------
-- Capsule tests

function HitTest.CapsuleVsVolume(cap: Capsule, volume: Volume): boolean
	return HitTest.SegmentDistanceSq(cap.A, cap.B, volume) <= cap.R * cap.R + 1e-9
end

function HitTest.Hits(cap: Capsule, volume: Volume, forgiveness: number?, maxMargin: number?): boolean
	local v = volume
	if forgiveness and forgiveness < 1 then
		v = HitTest.Shrink(volume, forgiveness, maxMargin)
	end
	return HitTest.CapsuleVsVolume(cap, v)
end

function HitTest.CapsuleVsBall(cap: Capsule, centre: Vector3, radius: number): boolean
	local rr = cap.R + radius
	return pointSegmentDistSq(centre, cap.A, cap.B) <= rr * rr + 1e-9
end

function HitTest.CapsuleVsCapsule(cap: Capsule, a: Vector3, b: Vector3, radius: number): boolean
	local d2 = HitTest.ClosestSegmentPoints(cap.A, cap.B, a, b)
	local rr = cap.R + radius
	return d2 <= rr * rr + 1e-9
end

function HitTest.CapsuleVsBox(cap: Capsule, boxCFrame: CFrame, boxSize: Vector3): boolean
	return HitTest.CapsuleVsVolume(cap, { Shape = "Box", CFrame = boxCFrame, Size = boxSize })
end

function HitTest.CapsuleVsCylinder(cap: Capsule, cframe: CFrame, diameter: number, height: number): boolean
	return HitTest.CapsuleVsVolume(
		cap,
		{ Shape = "Cylinder", CFrame = cframe, Size = Vector3.new(diameter, height, diameter) }
	)
end

function HitTest.CapsuleVsRing(
	cap: Capsule,
	cframe: CFrame,
	outerDiameter: number,
	height: number,
	thickness: number
): boolean
	return HitTest.CapsuleVsVolume(
		cap,
		{ Shape = "Ring", CFrame = cframe, Size = Vector3.new(outerDiameter, height, thickness) }
	)
end

---------------------------------------------------------------------------------------------------
-- Broadphase

function HitTest.BoundingRadius(volume: Volume): number
	local s = volume.Size
	local shape = volume.Shape
	if shape == "Ball" then
		return s.X * 0.5
	elseif shape == "Capsule" then
		return math.max(s.X, s.Y) * 0.5
	elseif shape == "Cylinder" or shape == "Ring" then
		local r = s.X * 0.5
		local h = s.Y * 0.5
		return math.sqrt(r * r + h * h)
	end
	return s.Magnitude * 0.5
end

function HitTest.MayOverlap(cap: Capsule, volume: Volume): boolean
	local mid = (cap.A + cap.B) * 0.5
	local half = (cap.B - cap.A).Magnitude * 0.5
	local reach = HitTest.BoundingRadius(volume) + half + cap.R
	local d = mid - volume.CFrame.Position
	return d:Dot(d) <= reach * reach
end

return HitTest
