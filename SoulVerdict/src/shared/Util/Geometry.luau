--!strict
-- Geometry: exact distance / intersection tests (server hazard hit tests, SPEC §7.6) and ellipsoid
-- surface placement (rig building). Lune-safe: pure math on Vector3/CFrame.
--
-- ELLIPSOID PLACEMENT ------------------------------------------------------------------------------
--   radii = SEMI-axes in the ellipsoid's local frame (= ellipsoid Part.Size / 2), all > 0.
--   Angles are DEGREES, measured in the local frame of centerCF:
--     yaw   0 = front (-Z, centerCF.LookVector)   +90 = right (+X)   -90 = left (-X)   180 = back (+Z)
--     pitch 0 = horizontal                        +90 = top (+Y)     -90 = bottom (-Y)
--     local direction d(yaw, pitch) = (sin(yaw)*cos(pitch), sin(pitch), -cos(yaw)*cos(pitch))
--   !! Positive yaw turns toward +X (the model's RIGHT). That is the OPPOSITE sense of
--   !! CFrame.Angles(0, a, 0), where positive a turns LEFT. Mirror left/right features with -yaw.
--   Geometry.direction(yawDeg, pitchDeg) -> Vector3            local unit direction d
--   Geometry.ellipsoidPoint(centerCF, radii, yawDeg, pitchDeg) -> (position, normal)
--       Surface point hit by the ray from the centre along d (radial projection, so the angles are the
--       real angles seen from the centre) and the outward unit normal there. Both in WORLD space.
--   Geometry.surfaceCFrame(centerCF, radii, yawDeg, pitchDeg, offset?, rollDeg?) -> CFrame
--       At that point (moved `offset` studs along the normal; negative = sink into the surface).
--       LookVector (-Z) = outward normal. UpVector = centerCF.UpVector projected onto the tangent plane
--       (at the exact poles: continuous limit, pointing away from the yaw direction on top).
--       RightVector = Up x Back. A point at yaw 0, pitch 0 gets centerCF's own orientation.
--       rollDeg spins the frame around its LookVector (positive turns Right toward Up).
--
-- SEGMENTS / DISTANCES -----------------------------------------------------------------------------
--   closestPointOnSegment(p, a, b) -> (point, t)                    t in [0, 1]
--   closestPointsSegmentSegment(p1, q1, p2, q2) -> (c1, c2, s, t)   exact (Ericson, RTCD 5.1.9)
--   segmentSegmentDistance(p1, q1, p2, q2) -> number
--   pointBoxDistance(p, boxCF, boxSize) -> number                   0 inside
--   segmentBoxDistance(a, b, boxCF, boxSize) -> number              exact (piecewise-quadratic minimum)
--   pointInBox(p, boxCF, boxSize) -> boolean
--   flatDistance(a, b) / flatDistanceSq(a, b)                       XZ-plane distance (ignores Y)
--   pointInCone(point, apex, direction, halfAngleDeg, range?) -> boolean   apex itself counts as inside
--   pointInConeDot(point, apex, direction, minDot, range?) -> boolean      same with cos threshold
--
-- CAPSULE TESTS (a capsule = segment a..b inflated by radius r; touching counts as a hit) -----------
--   capsuleVsBall(a, b, r, center, radius) -> boolean
--   capsuleVsCapsule(a1, b1, r1, a2, b2, r2) -> boolean     (a swept ball p0->p1 is such a capsule)
--   capsuleVsBox(a, b, r, boxCF, boxSize) -> boolean        oriented box, exact
--   verticalCapsule(center, height, radius) -> (a, b, r)    character capsule: total height incl. caps
--   volumeCapsule(cf, size, scale?) -> (a, b, r)            SPEC Volume "Capsule": Size.X = diameter,
--                                                           Size.Y = TOTAL length incl. the round caps,
--                                                           axis = cf.UpVector
--   capsuleVsVolume(a, b, r, volume, scale?) -> boolean     volume = {Shape="Box"|"Ball"|"Capsule",
--                                                           CFrame, Size}; Ball diameter = Size.X;
--                                                           scale (e.g. Config.Combat.HazardForgiveness)
--                                                           shrinks/grows the volume about its centre
-- All tests are exact up to float precision (Roblox Vector3/CFrame are float32: ~1e-6 relative).

local Types = require(script.Parent.Parent.Types)

local Geometry = {}

local EPS = 1e-12
local RAD = math.pi / 180

export type Volume = Types.Volume

local function clamp01(x: number): number
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- Ellipsoid ---------------------------------------------------------------------------------------

function Geometry.direction(yawDeg: number, pitchDeg: number): Vector3
	local yaw, pitch = yawDeg * RAD, pitchDeg * RAD
	local cp = math.cos(pitch)
	return Vector3.new(math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp)
end

-- Local-space point and (non-normalised) gradient normal.
local function ellipsoidLocal(radii: Vector3, yawDeg: number, pitchDeg: number): (Vector3, Vector3)
	local d = Geometry.direction(yawDeg, pitchDeg)
	local rx = math.max(radii.X, 1e-6)
	local ry = math.max(radii.Y, 1e-6)
	local rz = math.max(radii.Z, 1e-6)
	local qx, qy, qz = d.X / rx, d.Y / ry, d.Z / rz
	local k = 1 / math.sqrt(qx * qx + qy * qy + qz * qz)
	local px, py, pz = d.X * k, d.Y * k, d.Z * k
	local normal = Vector3.new(px / (rx * rx), py / (ry * ry), pz / (rz * rz))
	return Vector3.new(px, py, pz), normal
end

function Geometry.ellipsoidPoint(centerCF: CFrame, radii: Vector3, yawDeg: number, pitchDeg: number): (Vector3, Vector3)
	local p, n = ellipsoidLocal(radii, yawDeg, pitchDeg)
	return centerCF:PointToWorldSpace(p), centerCF:VectorToWorldSpace(n.Unit)
end

function Geometry.surfaceCFrame(
	centerCF: CFrame,
	radii: Vector3,
	yawDeg: number,
	pitchDeg: number,
	offset: number?,
	rollDeg: number?
): CFrame
	local p, gradient = ellipsoidLocal(radii, yawDeg, pitchDeg)
	local n = gradient.Unit
	-- Up = local +Y projected onto the tangent plane.
	local up = Vector3.yAxis - n * n.Y
	if up.Magnitude < 1e-5 then
		-- Exactly at a pole: use the continuous limit (away from the yaw direction on top, toward it below).
		local yaw = yawDeg * RAD
		local s = if n.Y >= 0 then 1 else -1
		up = Vector3.new(-math.sin(yaw) * s, 0, math.cos(yaw) * s)
	end
	up = up.Unit
	local back = -n
	local right = up:Cross(back)
	local position = p + n * (offset or 0)
	local localCF = CFrame.fromMatrix(position, right, up, back)
	if rollDeg ~= nil and rollDeg ~= 0 then
		localCF = localCF * CFrame.Angles(0, 0, rollDeg * RAD)
	end
	return centerCF * localCF
end

-- Points & segments -------------------------------------------------------------------------------

function Geometry.closestPointOnSegment(p: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 <= EPS then
		return a, 0
	end
	local t = clamp01((p - a):Dot(ab) / len2)
	return a + ab * t, t
end

-- Closest points c1 = p1 + (q1-p1)*s and c2 = p2 + (q2-p2)*t between two segments (s, t in [0, 1]).
-- Degenerate (zero-length) segments and parallel segments are handled.
function Geometry.closestPointsSegmentSegment(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): (Vector3, Vector3, number, number)
	local d1 = q1 - p1
	local d2 = q2 - p2
	local r = p1 - p2
	local a = d1:Dot(d1)
	local e = d2:Dot(d2)
	local f = d2:Dot(r)
	local s: number, t: number
	if a <= EPS and e <= EPS then
		return p1, p2, 0, 0
	end
	if a <= EPS then
		s = 0
		t = clamp01(f / e)
	else
		local c = d1:Dot(r)
		if e <= EPS then
			t = 0
			s = clamp01(-c / a)
		else
			local b = d1:Dot(d2)
			local denom = a * e - b * b
			if denom > EPS * a * e then
				s = clamp01((b * f - c * e) / denom)
			else
				s = 0 -- parallel: any s works, t below picks the matching point
			end
			t = (b * s + f) / e
			if t < 0 then
				t = 0
				s = clamp01(-c / a)
			elseif t > 1 then
				t = 1
				s = clamp01((b - c) / a)
			end
		end
	end
	return p1 + d1 * s, p2 + d2 * t, s, t
end

function Geometry.segmentSegmentDistance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): number
	local c1, c2 = Geometry.closestPointsSegmentSegment(p1, q1, p2, q2)
	return (c1 - c2).Magnitude
end

-- Boxes -------------------------------------------------------------------------------------------

-- Squared distance from local point (x, y, z) to the AABB [-h, h].
local function pointAabbDistSq(x: number, y: number, z: number, hx: number, hy: number, hz: number): number
	local dx = math.max(math.abs(x) - hx, 0)
	local dy = math.max(math.abs(y) - hy, 0)
	local dz = math.max(math.abs(z) - hz, 0)
	return dx * dx + dy * dy + dz * dz
end

function Geometry.pointBoxDistance(p: Vector3, boxCF: CFrame, boxSize: Vector3): number
	local l = boxCF:PointToObjectSpace(p)
	return math.sqrt(pointAabbDistSq(l.X, l.Y, l.Z, boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2))
end

function Geometry.pointInBox(p: Vector3, boxCF: CFrame, boxSize: Vector3): boolean
	local l = boxCF:PointToObjectSpace(p)
	return math.abs(l.X) <= boxSize.X / 2 and math.abs(l.Y) <= boxSize.Y / 2 and math.abs(l.Z) <= boxSize.Z / 2
end

-- Scratch buffer for breakpoints (Luau runs one thread at a time per VM and nothing below yields).
local breakpoints: { number } = table.create(8, 0)

-- Appends the parameters s in (0, 1) where A + s*D crosses the planes +-h. Returns the new count.
local function addCrossings(count: number, a: number, d: number, h: number): number
	if math.abs(d) > EPS then
		local s1 = (h - a) / d
		local s2 = (-h - a) / d
		if s1 > 0 and s1 < 1 then
			count += 1
			breakpoints[count] = s1
		end
		if s2 > 0 and s2 < 1 then
			count += 1
			breakpoints[count] = s2
		end
	end
	return count
end

-- Adds the quadratic coefficients of the active face term of one axis at parameter m.
local function axisTerm(m: number, a: number, d: number, h: number): (number, number, number)
	local x = a + m * d
	local c0: number
	if x > h then
		c0 = a - h
	elseif x < -h then
		c0 = a + h
	else
		return 0, 0, 0
	end
	-- (c0 + s*d)^2 = d^2 s^2 + 2 d c0 s + c0^2
	return d * d, 2 * d * c0, c0 * c0
end

-- Exact squared distance between the local segment A + s*D (s in [0,1]) and the AABB [-h, h].
-- dist^2(s) is convex and piecewise quadratic; the pieces change only where a coordinate crosses a
-- face plane (A_i + s*D_i = +-h_i). The quadratic of every piece is minimised in closed form.
local function segmentAabbDistSq(
	ax: number,
	ay: number,
	az: number,
	dx: number,
	dy: number,
	dz: number,
	hx: number,
	hy: number,
	hz: number
): number
	breakpoints[1] = 0
	breakpoints[2] = 1
	local count = addCrossings(2, ax, dx, hx)
	count = addCrossings(count, ay, dy, hy)
	count = addCrossings(count, az, dz, hz)
	-- insertion sort (<= 8 items)
	for i = 2, count do
		local v = breakpoints[i]
		local j = i - 1
		while j >= 1 and breakpoints[j] > v do
			breakpoints[j + 1] = breakpoints[j]
			j -= 1
		end
		breakpoints[j + 1] = v
	end
	local best = math.huge
	for i = 1, count - 1 do
		local l, r = breakpoints[i], breakpoints[i + 1]
		if r > l then
			local m = (l + r) * 0.5
			local qa1, qb1, qc1 = axisTerm(m, ax, dx, hx)
			local qa2, qb2, qc2 = axisTerm(m, ay, dy, hy)
			local qa3, qb3, qc3 = axisTerm(m, az, dz, hz)
			local qa, qb, qc = qa1 + qa2 + qa3, qb1 + qb2 + qb3, qc1 + qc2 + qc3
			local s: number
			if qa > EPS then
				s = math.clamp(-qb / (2 * qa), l, r)
			elseif qb > 0 then
				s = l -- (nearly) linear piece: minimum at an end
			else
				s = r
			end
			local value = (qa * s + qb) * s + qc
			if value < best then
				best = value
			end
		end
	end
	if best == math.huge then
		best = pointAabbDistSq(ax, ay, az, hx, hy, hz)
	end
	return math.max(best, 0)
end

local function segmentBoxDistSq(a: Vector3, b: Vector3, boxCF: CFrame, boxSize: Vector3): number
	local la = boxCF:PointToObjectSpace(a)
	local lb = boxCF:PointToObjectSpace(b)
	return segmentAabbDistSq(la.X, la.Y, la.Z, lb.X - la.X, lb.Y - la.Y, lb.Z - la.Z, boxSize.X / 2, boxSize.Y / 2, boxSize.Z / 2)
end

function Geometry.segmentBoxDistance(a: Vector3, b: Vector3, boxCF: CFrame, boxSize: Vector3): number
	return math.sqrt(segmentBoxDistSq(a, b, boxCF, boxSize))
end

-- Misc distances ----------------------------------------------------------------------------------

function Geometry.flatDistanceSq(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz
end

function Geometry.flatDistance(a: Vector3, b: Vector3): number
	return math.sqrt(Geometry.flatDistanceSq(a, b))
end

function Geometry.pointInConeDot(point: Vector3, apex: Vector3, direction: Vector3, minDot: number, range: number?): boolean
	local v = point - apex
	local dist = v.Magnitude
	if range ~= nil and dist > range then
		return false
	end
	if dist < 1e-9 then
		return true
	end
	local dirLen = direction.Magnitude
	if dirLen < 1e-9 then
		return false
	end
	return v:Dot(direction) / (dist * dirLen) >= minDot
end

function Geometry.pointInCone(point: Vector3, apex: Vector3, direction: Vector3, halfAngleDeg: number, range: number?): boolean
	return Geometry.pointInConeDot(point, apex, direction, math.cos(halfAngleDeg * RAD), range)
end

-- Capsules ----------------------------------------------------------------------------------------

function Geometry.capsuleVsBall(a: Vector3, b: Vector3, r: number, center: Vector3, radius: number): boolean
	local c = Geometry.closestPointOnSegment(center, a, b)
	local reach = r + radius
	local d = c - center
	return d:Dot(d) <= reach * reach
end

function Geometry.capsuleVsCapsule(a1: Vector3, b1: Vector3, r1: number, a2: Vector3, b2: Vector3, r2: number): boolean
	local c1, c2 = Geometry.closestPointsSegmentSegment(a1, b1, a2, b2)
	local reach = r1 + r2
	local d = c1 - c2
	return d:Dot(d) <= reach * reach
end

function Geometry.capsuleVsBox(a: Vector3, b: Vector3, r: number, boxCF: CFrame, boxSize: Vector3): boolean
	return segmentBoxDistSq(a, b, boxCF, boxSize) <= r * r
end

function Geometry.verticalCapsule(center: Vector3, height: number, radius: number): (Vector3, Vector3, number)
	local half = math.max(height / 2 - radius, 0)
	local offset = Vector3.new(0, half, 0)
	return center - offset, center + offset, radius
end

function Geometry.volumeCapsule(cf: CFrame, size: Vector3, scale: number?): (Vector3, Vector3, number)
	local k = scale or 1
	local r = size.X / 2 * k
	local half = math.max(size.Y * k / 2 - r, 0)
	local axis = cf.UpVector * half
	return cf.Position - axis, cf.Position + axis, r
end

function Geometry.capsuleVsVolume(a: Vector3, b: Vector3, r: number, volume: Volume, scale: number?): boolean
	local k = scale or 1
	local shape = volume.Shape
	if shape == "Box" then
		return Geometry.capsuleVsBox(a, b, r, volume.CFrame, volume.Size * k)
	elseif shape == "Ball" then
		return Geometry.capsuleVsBall(a, b, r, volume.CFrame.Position, volume.Size.X / 2 * k)
	elseif shape == "Capsule" then
		local a2, b2, r2 = Geometry.volumeCapsule(volume.CFrame, volume.Size, k)
		return Geometry.capsuleVsCapsule(a, b, r, a2, b2, r2)
	end
	error("Geometry.capsuleVsVolume: unknown volume shape " .. tostring(shape))
end

return Geometry
