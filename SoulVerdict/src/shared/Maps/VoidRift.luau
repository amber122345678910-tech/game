--!strict
-- Maps/VoidRift: "Void Rift" — a dream rift of fractured stone islands hanging over an endless abyss. [Lune-safe]
-- Layout (top view, forward = -Z = north): a big irregular duel platform ("the Verdict Shard", Ø ~72) in the
-- middle, six satellite islands on a ring (~80 studs out) and one stepping stone:
--   N  Rift Gate (+7)      monster spawn before a glowing tear in space, flanked by giant bones; a colossal
--                          cracked skull statue floats above and behind it (backdrop).
--   NE Shattered Crown (+12) high ring of broken standing stones — SAVE 3 (closest to the monster).
--   SE Fallen Watcher (-3)  a skull statue's head toppled off its plinth (cover) — SAVE 2.
--   S  Shore of Waking (0)  human spawns (12), joined to the centre by "the Ribway": a stone causeway under
--                          giant rib arches, a fossil spine hanging beneath it.
--   SW Drifting Isle (+4)   rocks and bones (cover).
--   W  Crystal Scar (-1)    void crystals, a broken obelisk — SAVE 1.
-- Stone ramps join the centre to N (grand stair with glowing nosings), S (Ribway), W (broken causeway whose
-- cracks are filled with light) and SE; translucent Neon "bridges of light" (low glowing rails) link the
-- satellites into an outer loop (W -> stepping stone -> N). Platform edges are open and dangerous except
-- for low rims (with invisible guards) at the spawns, behind the SAVE points and along the Ribway.
-- Underneath every island: faceted rock roots with glowing cyan veins; floating debris at every depth and
-- distant drifting islands in the haze. Duel floors stay calm dark slate (cracks only near the edges) so
-- attacks and telegraphs read. Invisible 16-sided boundary at r = 118, KillY = -48.
-- Built around the origin (centre floor top y = 0, forward = -Z); MapService offsets it.
--
-- API (Types.MapDef): VoidRift.Id/Name/Desc/Preset/FinalPreset/Music
--   VoidRift.Build(seed?, opts?) -> MapInfo  island SHAPES are fixed (layout rng); only decor varies by seed
--        opts = { Overview: boolean? } (skips the far scenery: tight framing for overview renders)
--   VoidRift.Layout                         layout constants (islands, KillY, radius) for tests/tools

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Util.Rng)
local MapKit = require(script.Parent.MapKit)

type MapInfo = Types.MapInfo
type Builder = MapKit.Builder

local VoidRift = {}

VoidRift.Id = "VoidRift"
VoidRift.Name = { en = "Void Rift", ru = "Разлом Пустоты" }
VoidRift.Desc = {
	en = "Broken platforms drifting between timelines. Mind the edges.",
	ru = "Обломки платформ, дрейфующие между временными линиями. Осторожно с краями.",
}
VoidRift.Preset = "VoidAbyss"
VoidRift.FinalPreset = "VoidAbyssFinal"
VoidRift.Music = "Map_VoidRift"

local V = Vector3.new
local M = Enum.Material
local UP = Vector3.new(0, 1, 0)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local C = {
	Stone = rgb(46, 50, 78), -- walk surfaces
	StoneLight = rgb(64, 70, 104), -- rims, monoliths, stairs
	StoneSide = rgb(32, 34, 56),
	Under = rgb(26, 27, 46), -- island roots
	Deep = rgb(15, 16, 30),
	Inlay = rgb(70, 82, 134),
	Crack = rgb(70, 226, 255), -- cyan neon
	CrackDeep = rgb(56, 128, 255), -- blue neon
	Violet = rgb(150, 92, 255),
	RiftCore = rgb(236, 250, 255),
	Bridge = rgb(34, 104, 226),
	BridgeEdge = rgb(84, 198, 255),
	Bone = rgb(226, 230, 240),
	BoneShade = rgb(178, 184, 204),
	Crystal = rgb(96, 230, 255),
	CrystalViolet = rgb(170, 110, 255),
	Light = rgb(120, 214, 255),
	LightViolet = rgb(160, 120, 255),
}

-- Layout (studs) --------------------------------------------------------------------------------------------
export type IslandSpec = {
	Name: string,
	Center: Vector3, -- walk-surface centre (top)
	RX: number, -- ellipse radii of the outline
	RZ: number,
	Verts: number,
	Jitter: { number }, -- radius factor range
	Phase: number, -- deg
	Depth: number, -- root depth factor
}

local ISLANDS: { IslandSpec } = {
	{ Name = "Core", Center = V(0, 0, 0), RX = 37, RZ = 35, Verts = 13, Jitter = { 0.93, 1.04 }, Phase = 8, Depth = 1 },
	{
		Name = "Gate",
		Center = V(0, 7, -84),
		RX = 24,
		RZ = 14,
		Verts = 10,
		Jitter = { 0.94, 1.03 },
		Phase = 0,
		Depth = 0.9,
	},
	{
		Name = "Crown",
		Center = V(70, 12, -38),
		RX = 14,
		RZ = 14,
		Verts = 8,
		Jitter = { 0.93, 1.05 },
		Phase = 12,
		Depth = 1.4,
	},
	{
		Name = "Skull",
		Center = V(68, -3, 42),
		RX = 20,
		RZ = 17,
		Verts = 10,
		Jitter = { 0.93, 1.04 },
		Phase = 5,
		Depth = 1,
	},
	{
		Name = "Landing",
		Center = V(0, 0, 84),
		RX = 25,
		RZ = 14,
		Verts = 12,
		Jitter = { 0.97, 1.03 },
		Phase = 0,
		Depth = 0.8,
	},
	{
		Name = "Drift",
		Center = V(-66, 4, 40),
		RX = 14,
		RZ = 13,
		Verts = 8,
		Jitter = { 0.92, 1.05 },
		Phase = 20,
		Depth = 1.3,
	},
	{
		Name = "Shards",
		Center = V(-74, -1, -34),
		RX = 17,
		RZ = 20,
		Verts = 10,
		Jitter = { 0.93, 1.04 },
		Phase = 0,
		Depth = 1,
	},
	{
		Name = "Step",
		Center = V(-38, 3, -60),
		RX = 6.5,
		RZ = 6,
		Verts = 7,
		Jitter = { 0.92, 1.05 },
		Phase = 0,
		Depth = 1.8,
	},
}

local L = {
	Islands = ISLANDS,
	Slab = 4, -- thickness of every island's walkable slab
	KillY = -48,
	Radius = 104, -- Collapse start radius (covers every island)
	BoundaryR = 118,
	BoundaryBottom = -64,
	BoundaryHeight = 180,
	SkullRock = V(-40, 12, -104), -- the giant skull's floating rock (top centre), north-west of the Gate
	SkullScale = 3.6,
	Saves = { V(-76, -1, -36), V(61, -3, 46), V(70, 12, -38) },
	MonsterSpawn = V(0, 7, -78),
}
VoidRift.Layout = L

-- Geometry helpers ------------------------------------------------------------------------------------------
type Island = {
	Name: string,
	Center: Vector3,
	Top: number,
	Verts: { Vector3 }, -- outline on the walk surface (y = Top), counter-clockwise from +X
	Mean: number,
	Depth: number,
	Openings: { Vector3 }, -- where ramps/bridges attach (rims never close them); Y = clearance radius
}

local function flat(v: Vector3): Vector3
	return V(v.X, 0, v.Z)
end

local function polar(deg: number, r: number, y: number?): Vector3
	local a = math.rad(deg)
	return V(math.cos(a) * r, y or 0, math.sin(a) * r)
end

local function makeIsland(spec: IslandSpec, rng: Rng.Rng): Island
	local verts: { Vector3 } = {}
	local n = spec.Verts
	local step = 360 / n
	local sum = 0
	for i = 0, n - 1 do
		local deg = spec.Phase + i * step + rng:Number(-0.2, 0.2) * step
		local f = rng:Number(spec.Jitter[1], spec.Jitter[2])
		local a = math.rad(deg)
		local off = V(math.cos(a) * spec.RX * f, 0, math.sin(a) * spec.RZ * f)
		sum += off.Magnitude
		table.insert(verts, spec.Center + off)
	end
	return {
		Name = spec.Name,
		Center = spec.Center,
		Top = spec.Center.Y,
		Verts = verts,
		Mean = sum / n,
		Depth = spec.Depth,
		Openings = {},
	}
end

local function cross2(ax: number, az: number, bx: number, bz: number): number
	return ax * bz - az * bx
end

-- Distance from the island centre to its outline along the horizontal direction `dir` (unit).
local function edgeDistance(isl: Island, dir: Vector3): number
	local c = isl.Center
	local best = math.huge
	local n = #isl.Verts
	for i = 1, n do
		local p, q = isl.Verts[i], isl.Verts[i % n + 1]
		local ex, ez = q.X - p.X, q.Z - p.Z
		local wx, wz = p.X - c.X, p.Z - c.Z
		local den = cross2(dir.X, dir.Z, ex, ez)
		if math.abs(den) > 1e-9 then
			local t = cross2(wx, wz, ex, ez) / den
			local s = cross2(wx, wz, dir.X, dir.Z) / den
			if t > 0 and s >= -1e-6 and s <= 1 + 1e-6 and t < best then
				best = t
			end
		end
	end
	return if best == math.huge then isl.Mean else best
end

-- Walk-surface point on the outline of `isl` towards `target`, pulled `inset` studs inside.
local function edgePoint(isl: Island, target: Vector3, inset: number): Vector3
	local d = flat(target - isl.Center).Unit
	local p = isl.Center + d * (edgeDistance(isl, d) - inset)
	return V(p.X, isl.Top, p.Z)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Decorative pieces ------------------------------------------------------------------------------------------

-- A thin glowing crack (polyline) lying on a surface: points are on the surface already.
local function glowLine(B: Builder, name: string, points: { Vector3 }, w0: number, w1: number, color: Color3)
	local n = #points
	for i = 1, n - 1 do
		local t = if n > 2 then (i - 1) / (n - 2) else 0
		local w = lerp(w0, w1, t)
		B:Beam("Decor", name, points[i], points[i + 1], w, 0.07, color, M.Neon, { Shadow = false })
	end
end

-- Jagged crack on a walk surface, starting at `start` and wandering along `dir` (horizontal unit).
local function floorCrack(
	B: Builder,
	name: string,
	start: Vector3,
	dir: Vector3,
	length: number,
	width: number,
	color: Color3
)
	local rng = B.Rng
	local pts: { Vector3 } = { start }
	local p = start
	local d = dir
	local segs = 3
	for _ = 1, segs do
		local a = math.rad(rng:Number(-32, 32))
		local ca, sa = math.cos(a), math.sin(a)
		d = V(d.X * ca - d.Z * sa, 0, d.X * sa + d.Z * ca).Unit
		p = p + d * (length / segs * rng:Number(0.75, 1.2))
		table.insert(pts, p)
	end
	glowLine(B, name, pts, width, width * 0.35, color)
	-- one short branch
	if rng:Bool(0.6) then
		local b0 = pts[2]
		local a = math.rad(rng:Number(35, 60) * (if rng:Bool() then 1 else -1))
		local bd = V(dir.X * math.cos(a) - dir.Z * math.sin(a), 0, dir.X * math.sin(a) + dir.Z * math.cos(a))
		glowLine(B, name .. "_Branch", { b0, b0 + bd * (length * 0.3) }, width * 0.6, width * 0.3, color)
	end
end

-- Cartoon bone along a polyline: cylinders with ball joints, thickness d0 -> d1, knob pair at the end.
local function bonePath(
	B: Builder,
	name: string,
	points: { Vector3 },
	d0: number,
	d1: number,
	color: Color3,
	knobEnd: boolean?
)
	local n = #points
	for i = 1, n - 1 do
		local t = if n > 2 then (i - 1) / (n - 2) else 0
		local d = lerp(d0, d1, t)
		B:Rod("Decor", name, points[i], points[i + 1], d, color, M.SmoothPlastic)
		if i > 1 then
			B:Ball("Decor", name .. "_Joint", points[i], d * 1.03, color, M.SmoothPlastic, { Shadow = false })
		end
	end
	if knobEnd ~= false and n >= 2 then
		local tip = points[n]
		local axis = (tip - points[n - 1]).Unit
		local side = axis:Cross(UP)
		if side.Magnitude < 1e-3 then
			side = V(1, 0, 0)
		end
		side = side.Unit
		for _, s in { -1, 1 } do
			B:Ball("Decor", name .. "_Knob", tip + side * (s * d1 * 0.45), d1 * 1.5, color, M.SmoothPlastic)
		end
	end
end

-- Straight giant bone (shaft + two knobs at each end), like PartKit.Bone but in map scale.
local function bigBone(B: Builder, name: string, a: Vector3, b: Vector3, d: number, color: Color3, solidBase: boolean?)
	B:Rod("Decor", name, a, b, d, color, M.SmoothPlastic)
	local axis = (b - a).Unit
	local side = axis:Cross(UP)
	if side.Magnitude < 1e-3 then
		side = V(1, 0, 0)
	end
	side = side.Unit
	for k, e in { a, b } do
		for _, s in { -1, 1 } do
			local pos = e + side * (s * d * 0.42) - axis * (if k == 1 then -d * 0.2 else d * 0.2)
			if k == 1 and solidBase then
				B:Solid("Ball", name .. "_Knob", V(d * 1.5, d * 1.5, d * 1.5), CFrame.new(pos), color, M.SmoothPlastic)
			else
				B:Ball("Decor", name .. "_Knob", pos, d * 1.5, color, M.SmoothPlastic)
			end
		end
	end
end

-- Broken standing stone (solid cover) with a slanted broken top and a glowing crack on its front.
local function monolith(
	B: Builder,
	name: string,
	base: Vector3,
	size: Vector3,
	yaw: number,
	tilt: number,
	crack: Color3
)
	local frame = CFrame.new(base)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(math.rad(tilt), 0, math.rad(tilt * 0.4))
	local body = frame * CFrame.new(0, size.Y / 2 - 0.4, 0)
	B:Solid("Block", name, size, body, C.StoneLight, M.Slate)
	-- broken top: a wedge leaning one way
	local topH = size.X * 0.7
	B:Deco(
		"Wedge",
		name .. "_Break",
		V(size.X, topH, size.Z),
		frame * CFrame.new(0, size.Y - 0.4 + topH / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
		C.StoneLight,
		M.Slate
	)
	-- foot rubble ring
	B:Deco(
		"Block",
		name .. "_Foot",
		V(size.X + 1.2, 0.6, size.Z + 1.2),
		CFrame.new(base + V(0, 0.2, 0)) * CFrame.Angles(0, math.rad(yaw + 20), 0),
		C.StoneSide,
		M.Slate,
		{ Shadow = false }
	)
	-- crack zig-zag down the front face (local -Z face)
	local face = -size.Z / 2 - 0.04
	local pts: { Vector3 } = {}
	local zig = { 0.25, -0.2, 0.3, -0.1 }
	for i = 0, 3 do
		local y = size.Y - 0.8 - i * (size.Y - 1.4) / 3
		table.insert(pts, (frame * CFrame.new(zig[i + 1] * size.X, y - 0.4, face)).Position)
	end
	for i = 1, #pts - 1 do
		B:Rod("Decor", name .. "_Crack", pts[i], pts[i + 1], 0.16, crack, M.Neon, { Shadow = false })
	end
end

-- Stone pylon with a glowing tip (bridge anchors, landmarks).
local function pylon(B: Builder, name: string, base: Vector3, height: number, glow: Color3)
	B:Solid(
		"Block",
		name .. "_Base",
		V(2.4, 1, 2.4),
		CFrame.new(base + V(0, 0.5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		C.StoneSide,
		M.Slate
	)
	B:Solid(
		"Block",
		name,
		V(1.4, height, 1.4),
		CFrame.new(base + V(0, height / 2 + 1, 0)) * CFrame.Angles(0, math.rad(45), 0),
		C.StoneLight,
		M.Slate
	)
	B:Deco(
		"Block",
		name .. "_Band",
		V(1.55, 0.22, 1.55),
		CFrame.new(base + V(0, height * 0.72 + 1, 0)) * CFrame.Angles(0, math.rad(45), 0),
		glow,
		M.Neon,
		{ Shadow = false }
	)
	B:Cone(
		"Decor",
		name .. "_Cap",
		base + V(0, height + 1, 0),
		1.1,
		1.05,
		4,
		C.StoneSide,
		M.Slate,
		{ Phase = 45, Shadow = false }
	)
	B:Ball("Decor", name .. "_Gem", base + V(0, height + 2.35, 0), 0.55, glow, M.Neon, { Shadow = false })
end

-- Islands ----------------------------------------------------------------------------------------------------

-- Walkable slab (triangle fan), faceted root with glowing veins, edge cracks and crumbling debris.
local function buildIsland(B: Builder, isl: Island, opts: { [string]: any }?)
	local o = opts or {}
	local rng = B.Rng
	local c = isl.Center
	local top = isl.Top
	local n = #isl.Verts
	local slab = L.Slab
	local yMid = top - slab / 2
	local cMid = V(c.X, yMid, c.Z)
	local topColor: Color3 = o.Color or C.Stone
	for i = 1, n do
		local p, q = isl.Verts[i], isl.Verts[i % n + 1]
		B:Triangle(
			"Geometry",
			isl.Name .. "_Floor",
			cMid,
			V(p.X, yMid, p.Z),
			V(q.X, yMid, q.Z),
			slab,
			topColor,
			M.Slate
		)
	end
	-- root: outline -> inner ring -> apex (faceted inverted pyramid)
	local y0 = top - slab + 0.25
	local d1 = isl.Mean * 0.5 * isl.Depth
	local d2 = isl.Mean * 0.75 * isl.Depth
	local ring: { Vector3 } = {}
	for _, p in isl.Verts do
		local f = rng:Number(0.5, 0.66)
		local w = c + flat(p - c) * f
		table.insert(ring, V(w.X, y0 - d1 * rng:Number(0.8, 1.15), w.Z))
	end
	local apex = V(c.X + rng:Number(-0.15, 0.15) * isl.Mean, y0 - d1 - d2, c.Z + rng:Number(-0.15, 0.15) * isl.Mean)
	local outline: { Vector3 } = {}
	for _, p in isl.Verts do
		table.insert(outline, V(p.X, y0, p.Z))
	end
	for i = 1, n do
		local j = i % n + 1
		local shade = MapKit.Shade(C.Under, rng:Number(-0.3, 0.2))
		B:Triangle(
			"Decor",
			isl.Name .. "_Root",
			outline[i],
			outline[j],
			ring[j],
			0.6,
			shade,
			M.Slate,
			{ Shadow = false }
		)
		B:Triangle(
			"Decor",
			isl.Name .. "_Root",
			outline[i],
			ring[j],
			ring[i],
			0.6,
			MapKit.Shade(shade, -0.08),
			M.Slate,
			{ Shadow = false }
		)
		B:Triangle(
			"Decor",
			isl.Name .. "_Root",
			ring[i],
			ring[j],
			apex,
			0.6,
			MapKit.Shade(C.Deep, rng:Number(-0.2, 0.25)),
			M.Slate,
			{ Shadow = false }
		)
	end
	-- glowing veins down some root edges
	local veinColor: Color3 = o.Vein or C.Crack
	for i = 1, n do
		if (i + (o.VeinPhase or 0)) % 3 == 0 then
			local out0 = flat(outline[i] - c).Unit
			local out1 = flat(ring[i] - c).Unit
			local a = outline[i] + out0 * 0.4
			local b = ring[i] + out1 * 0.4
			B:Rod("Decor", isl.Name .. "_Vein", a, b, 0.32, veinColor, M.Neon, { Shadow = false })
			if i % 2 == 0 then
				B:Rod(
					"Decor",
					isl.Name .. "_Vein",
					b,
					apex + (b - apex) * 0.08,
					0.26,
					veinColor,
					M.Neon,
					{ Shadow = false }
				)
			end
		end
	end
	-- edge cracks: across the floor near the rim and down the cliff face
	local cracks = o.Cracks or math.max(2, math.floor(n / 2))
	local avoid: { number } = o.AvoidDeg or {}
	local made = 0
	local tries = 0
	while made < cracks and tries < cracks * 4 do
		tries += 1
		local i = rng:Integer(1, n)
		local p, q = isl.Verts[i], isl.Verts[i % n + 1]
		local s = rng:Number(0.25, 0.75)
		local e = p:Lerp(q, s)
		local inward = flat(c - e).Unit
		local deg = math.deg(math.atan2(-inward.Z, -inward.X)) % 360
		local blocked = false
		for _, ad in avoid do
			local diff = math.abs(((deg - ad + 180) % 360) - 180)
			if diff < 16 then
				blocked = true
			end
		end
		if not blocked then
			made += 1
			local start = e + inward * 0.25
			floorCrack(
				B,
				isl.Name .. "_Crack",
				V(start.X, top + 0.035, start.Z),
				inward,
				rng:Number(4, 8) * (o.CrackScale or 1),
				rng:Number(0.3, 0.46),
				veinColor
			)
			-- down the cliff
			local along = (q - p).Unit
			local outN = -inward
			local f0 = V(e.X, top - 0.1, e.Z) + outN * 0.08
			local f1 = f0 + along * rng:Number(-0.9, 0.9) - UP * (slab * 0.5)
			local f2 = f1 + along * rng:Number(-0.9, 0.9) - UP * (slab * 0.5 - 0.2)
			B:Rod("Decor", isl.Name .. "_CliffCrack", f0, f1, 0.3, veinColor, M.Neon, { Shadow = false })
			B:Rod("Decor", isl.Name .. "_CliffCrack", f1, f2, 0.24, veinColor, M.Neon, { Shadow = false })
		end
	end
	-- crumbling chunks just off the edge
	for _ = 1, (o.Debris or 4) do
		local i = rng:Integer(1, n)
		local p = isl.Verts[i]:Lerp(isl.Verts[i % n + 1], rng:Number(0.2, 0.8))
		local outN = flat(p - c).Unit
		local pos = p + outN * rng:Number(1.5, 5) - UP * rng:Number(3, 12)
		local s = rng:Number(1.2, 3.8)
		B:Deco(
			"Block",
			isl.Name .. "_Crumb",
			V(s, s * rng:Number(0.5, 0.9), s * rng:Number(0.6, 1)),
			CFrame.new(pos) * CFrame.Angles(rng:Number(0, 6.28), rng:Number(0, 6.28), rng:Number(0, 6.28)),
			MapKit.Shade(C.StoneSide, rng:Number(-0.2, 0.2)),
			M.Slate
		)
	end
end

-- Low stone rim (collidable, ~1.1 tall) plus an invisible guard along the outline edges whose outward
-- direction lies within [fromDeg, toDeg] (polar degrees: 0 = +X, 90 = +Z, 270 = -Z).
local function rim(B: Builder, isl: Island, fromDeg: number, toDeg: number)
	local c = isl.Center
	local n = #isl.Verts
	local span = (toDeg - fromDeg) % 360
	local function inArc(deg: number): boolean
		return ((deg - fromDeg) % 360) <= span
	end
	local function open(p: Vector3, q: Vector3): boolean
		-- an attached ramp/bridge (opening X/Z = attach point, Y = clearance) keeps this edge free
		for _, o in isl.Openings do
			local e = flat(q - p)
			local t = math.clamp(flat(V(o.X, 0, o.Z) - p):Dot(e) / e:Dot(e), 0, 1)
			local closest = flat(p) + e * t
			if (flat(V(o.X, 0, o.Z)) - closest).Magnitude < o.Y then
				return true
			end
		end
		return false
	end
	for i = 1, n do
		local p, q = isl.Verts[i], isl.Verts[i % n + 1]
		local mid = (p + q) / 2
		local dir = flat(mid - c).Unit
		local deg = math.deg(math.atan2(dir.Z, dir.X)) % 360
		if inArc(deg) and not open(p, q) then
			local pi = p + flat(c - p).Unit * 0.9
			local qi = q + flat(c - q).Unit * 0.9
			local a = V(pi.X, isl.Top + 0.55, pi.Z)
			local b = V(qi.X, isl.Top + 0.55, qi.Z)
			B:Beam("Geometry", isl.Name .. "_Rim", a, b, 1.2, 1.1, C.StoneLight, M.Slate)
			B:Beam(
				"Decor",
				isl.Name .. "_RimCap",
				a + UP * 0.6,
				b + UP * 0.6,
				1.3,
				0.12,
				C.StoneSide,
				M.Slate,
				{ Shadow = false }
			)
			for _, e in { a, b } do
				B:Solid(
					"Block",
					isl.Name .. "_RimPost",
					V(1.6, 1.6, 1.6),
					CFrame.new(e + UP * 0.25) * CFrame.Angles(0, math.rad((i * 37) % 90), 0),
					C.StoneLight,
					M.Slate
				)
			end
			B:Beam(
				"Geometry",
				isl.Name .. "_RimGuard",
				a + UP * 1.2,
				b + UP * 1.2,
				0.6,
				3.6,
				C.StoneLight,
				M.SmoothPlastic,
				{
					Transparency = 1,
					Shadow = false,
					Query = false,
				}
			)
		end
	end
end

-- Connections -----------------------------------------------------------------------------------------------

-- Stone causeway between two walk-surface points; Slabs > 1 splits it into pieces whose cracks are filled
-- with light (collidable, flush). opts = { Slabs, Width, Rims = "Both"|"Left"|"Right"|nil, Keel, Seams }
local function causeway(B: Builder, name: string, a: Vector3, b: Vector3, opts: { [string]: any })
	local rng = B.Rng
	local width: number = opts.Width or 12
	local slabs: number = opts.Slabs or 1
	local gap = 1.2
	local depth = 3
	local delta = b - a
	local len = delta.Magnitude
	local fl = flat(delta).Unit
	local side = V(-fl.Z, 0, fl.X) -- left of the walking direction
	local seg = (len - gap * (slabs - 1)) / slabs
	for k = 0, slabs - 1 do
		local d0 = k * (seg + gap)
		local d1 = d0 + seg
		local p0, p1 = a:Lerp(b, d0 / len), a:Lerp(b, d1 / len)
		local w = width * (if k % 2 == 1 then 0.94 else 1)
		local shift = side * (if k % 2 == 1 then rng:Number(-0.5, 0.5) else 0)
		B:Beam(
			"Geometry",
			name .. "_Slab",
			p0 + shift - UP * (depth / 2),
			p1 + shift - UP * (depth / 2),
			w,
			depth,
			C.Stone,
			M.Slate
		)
		if opts.Keel ~= false then
			B:Beam(
				"Decor",
				name .. "_Keel",
				p0:Lerp(p1, 0.08) - UP * (depth + 1.2),
				p1:Lerp(p0, 0.08) - UP * (depth + 1.2),
				w * 0.62,
				2.6,
				C.Under,
				M.Slate,
				{ Shadow = false }
			)
			local mid = p0:Lerp(p1, 0.5)
			B:Cone(
				"Decor",
				name .. "_Hang",
				mid - UP * (depth + 2.4),
				-rng:Number(5, 9),
				w * 0.32,
				5,
				C.Deep,
				M.Slate,
				{ Phase = rng:Number(0, 72), Shadow = false }
			)
		end
		if k < slabs - 1 then
			local g0 = a:Lerp(b, (d1 - 0.3) / len)
			local g1 = a:Lerp(b, (d1 + gap + 0.3) / len)
			B:Beam(
				"Geometry",
				name .. "_LightSeam",
				g0 - UP * 0.55,
				g1 - UP * 0.55,
				w * 0.96,
				1.1,
				C.CrackDeep,
				M.Neon,
				{ Transparency = 0.3, Shadow = false }
			)
		end
	end
	-- glowing seam lines along both side faces
	if opts.Seams ~= false then
		for _, s in { -1, 1 } do
			local off = side * (s * (width / 2 + 0.03))
			B:Beam(
				"Decor",
				name .. "_Seam",
				a + off - UP * 0.75,
				b + off - UP * 0.75,
				0.1,
				0.16,
				C.CrackDeep,
				M.Neon,
				{ Shadow = false }
			)
		end
	end
	-- rims (visible low curb + invisible guard), with short gaps every 10 studs on "Broken" rims
	local rims: string? = opts.Rims
	if rims then
		local sides: { number } = if rims == "Both" then { -1, 1 } elseif rims == "Left" then { 1 } else { -1 }
		for _, s in sides do
			local off = side * (s * (width / 2 - 0.6))
			local ra = a + off + fl * 1.5 + UP * 0.55
			local rb = b + off - fl * 1.5 + UP * 0.55
			B:Beam("Geometry", name .. "_Rim", ra, rb, 1.1, 1.1, C.StoneLight, M.Slate)
			B:Beam(
				"Geometry",
				name .. "_RimGuard",
				ra + UP * 1.2,
				rb + UP * 1.2,
				0.6,
				3.6,
				C.StoneLight,
				M.SmoothPlastic,
				{
					Transparency = 1,
					Shadow = false,
					Query = false,
				}
			)
		end
	end
end

-- Translucent Neon bridge of light: collidable deck, bright edges, chevrons pointing a -> b, glowing rails
-- (+ invisible guards), stone pylons at both ends and one light at the middle.
local function lightBridge(B: Builder, name: string, a: Vector3, b: Vector3, width: number): Light
	local delta = b - a
	local len = delta.Magnitude
	local fl = flat(delta).Unit
	local side = V(-fl.Z, 0, fl.X)
	local deckT = 0.5
	local a0, b0 = a + UP * 0.04, b + UP * 0.04
	B:Beam("Geometry", name .. "_Deck", a0 - UP * (deckT / 2), b0 - UP * (deckT / 2), width, deckT, C.Bridge, M.Neon, {
		Transparency = 0.66,
		Shadow = false,
	})
	for _, s in { -1, 1 } do
		local off = side * (s * (width / 2 - 0.12))
		B:Beam(
			"Decor",
			name .. "_Edge",
			a0 + off + UP * 0.03,
			b0 + off + UP * 0.03,
			0.22,
			0.1,
			C.BridgeEdge,
			M.Neon,
			{ Shadow = false }
		)
	end
	-- chevrons
	local count = math.max(2, math.floor(len / 6))
	for k = 1, count - 1 do
		local t = k / count
		local tip = a0:Lerp(b0, t) + UP * 0.05
		local back = a0:Lerp(b0, t - 1.6 / len) + UP * 0.05
		for _, s in { -1, 1 } do
			B:Beam(
				"Decor",
				name .. "_Chevron",
				back + side * (s * (width / 2 - 1.1)),
				tip,
				0.3,
				0.06,
				C.BridgeEdge,
				M.Neon,
				{
					Transparency = 0.55,
					Shadow = false,
				}
			)
		end
	end
	-- rails: thin glowing posts + top line + invisible guard
	local posts = math.max(1, math.floor(len / 8))
	local t0, t1 = 2.5 / len, 1 - 2.5 / len
	for _, s in { -1, 1 } do
		local off = side * (s * (width / 2 + 0.1))
		for k = 0, posts do
			local p = a0:Lerp(b0, lerp(t0, t1, k / posts)) + off
			B:Rod(
				"Decor",
				name .. "_RailPost",
				p,
				p + UP * 1.5,
				0.2,
				C.Bridge,
				M.Neon,
				{ Shadow = false, Transparency = 0.35 }
			)
		end
		local r0 = a0:Lerp(b0, t0) + off + UP * 1.5
		local r1 = a0:Lerp(b0, t1) + off + UP * 1.5
		B:Rod("Decor", name .. "_Rail", r0, r1, 0.16, C.BridgeEdge, M.Neon, { Shadow = false, Transparency = 0.2 })
		B:Beam(
			"Geometry",
			name .. "_Guard",
			a0 + off + fl * 1.2 + UP * 1.6,
			b0 + off - fl * 1.2 + UP * 1.6,
			0.5,
			3.2,
			C.Bridge,
			M.SmoothPlastic,
			{
				Transparency = 1,
				Shadow = false,
				Query = false,
			}
		)
	end
	-- anchors
	pylon(B, name .. "_Pylon", a + side * (width / 2 + 1.4) - fl * 1.2, 3.4, C.Crack)
	pylon(B, name .. "_Pylon", b - side * (width / 2 + 1.4) + fl * 1.2, 3.4, C.Crack)
	return B:Light(
		"Point",
		a0:Lerp(b0, 0.5) + UP * 2.5,
		{ Name = name .. "_Light", Brightness = 0.9, Range = 18, Color = C.Light }
	)
end

-- Pieces of scenery -------------------------------------------------------------------------------------------

-- A jagged tear in space: three nested Neon layers (violet, cyan, white core) in the XY plane of `cf`
-- (local +Z = the side it is seen from), base at cf, rising `height`.
local function rift(B: Builder, name: string, cf: CFrame, height: number, width: number)
	local n = 8
	local right: { Vector3 } = {}
	local left: { Vector3 } = {}
	for i = 0, n do
		local t = i / n
		local y = t * height
		local xc = math.sin(t * 7.3) * width * 0.11
		local half = (math.sin(t * math.pi) ^ 0.8) * width / 2
		local jr = if i % 2 == 0 then 1 else 0.58
		local jl = if i % 2 == 1 then 1 else 0.62
		table.insert(right, V(xc + half * jr, y, 0))
		table.insert(left, V(xc - half * jl, y, 0))
	end
	local poly: { Vector3 } = {}
	for i = 1, n + 1 do
		table.insert(poly, right[i])
	end
	for i = n, 2, -1 do
		table.insert(poly, left[i])
	end
	local center = V(math.sin(0.5 * 7.3) * width * 0.11, height * 0.5, 0)
	local layers = {
		{ SX = 1, SY = 1, Color = rgb(112, 60, 236), T = 0.05, Z = 0, Mat = M.Neon },
		{ SX = 0.8, SY = 0.95, Color = rgb(70, 200, 255), T = 0, Z = 0.2, Mat = M.Neon },
		{ SX = 0.62, SY = 0.88, Color = rgb(4, 5, 14), T = 0, Z = 0.4, Mat = M.SmoothPlastic },
	}
	for li, layer in layers do
		local function map(p: Vector3): Vector3
			local d = p - center
			return (cf * CFrame.new(center.X + d.X * layer.SX, center.Y + d.Y * layer.SY, layer.Z)).Position
		end
		local cw = map(center)
		for i = 1, #poly do
			local p, q = poly[i], poly[i % #poly + 1]
			B:Triangle(
				"Decor",
				name .. "_Layer" .. li,
				cw,
				map(p),
				map(q),
				0.24,
				layer.Color,
				layer.Mat,
				{ Transparency = layer.T, Shadow = false }
			)
		end
	end
	-- stars seen through the tear
	local rng = B.Rng
	for i = 1, 9 do
		local t = rng:Number(0.18, 0.82)
		local half = (math.sin(t * math.pi) ^ 0.8) * width / 2 * 0.5
		local xc = math.sin(t * 7.3) * width * 0.11
		local p = cf * CFrame.new(xc + rng:Number(-half, half), t * height, 0.62)
		B:Ball(
			"Decor",
			name .. "_Star",
			p.Position,
			if i % 3 == 0 then 0.5 else 0.28,
			if i % 4 == 0 then C.Violet else C.RiftCore,
			M.Neon,
			{ Shadow = false }
		)
	end
end

-- Points on the surface of an ellipsoid (centre frame `frame`, semi-axes `radii`) — yaw 0 = front (-Z),
-- +yaw towards +X, +pitch up (degrees).
local function onEllipsoid(frame: CFrame, radii: Vector3, yaw: number, pitch: number, push: number): Vector3
	local y, p = math.rad(yaw), math.rad(pitch)
	local dir = V(math.sin(y) * math.cos(p), math.sin(p), -math.cos(y) * math.cos(p))
	local surf = V(dir.X * radii.X, dir.Y * radii.Y, dir.Z * radii.Z)
	return (frame * CFrame.new(surf + surf.Unit * push)).Position
end

-- Broken-skull dressing for a MapKit SkullStatue head: a glowing crack across the cranium, a dark hole and
-- fragments drifting away from it. `head` = cranium centre frame (facing = LookVector), `s` = statue scale.
local function crackSkull(
	B: Builder,
	name: string,
	head: CFrame,
	s: number,
	holeSide: number,
	color: Color3,
	fragments: number
)
	local radii = V(3.1, 2.8, 2.9) * s
	local pts: { Vector3 } = {}
	local path = { { -38, 62 }, { -20, 45 }, { -28, 30 }, { -8, 18 }, { -16, 6 } }
	for _, yp in path do
		table.insert(pts, onEllipsoid(head, radii, yp[1] * -holeSide, yp[2], 0.05 * s))
	end
	for i = 1, #pts - 1 do
		B:Rod("Decor", name .. "_SkullCrack", pts[i], pts[i + 1], 0.16 * s, color, M.Neon, { Shadow = false })
	end
	-- the hole: a dark dent on the upper side (+ a glowing rim)
	local holeAt = head * CFrame.new(holeSide * 1.9 * s, 1.9 * s, 0.4 * s)
	B:Deco(
		"Ellipsoid",
		name .. "_Hole",
		V(2.6, 1.6, 2.4) * s,
		holeAt * CFrame.Angles(0, 0, math.rad(-holeSide * 38)),
		C.Deep,
		M.SmoothPlastic,
		{ Shadow = false }
	)
	local rng = B.Rng
	for i = 1, fragments do
		local off = V(holeSide * rng:Number(1.5, 4.5), rng:Number(1.2, 4.5), rng:Number(-1.6, 1.6)) * s
		local size = V(rng:Number(0.5, 1.2), rng:Number(0.3, 0.7), rng:Number(0.5, 1.1)) * s
		B:Deco(
			"Block",
			name .. "_Fragment",
			size,
			holeAt * CFrame.new(off) * CFrame.Angles(rng:Number(0, 6.28), rng:Number(0, 6.28), rng:Number(0, 6.28)),
			if i % 3 == 0 then C.BoneShade else C.Bone,
			M.Marble
		)
	end
end

-- MapKit SkullStatue builds its plinth 4*s*s tall (the height is scaled twice); restore the intended
-- 6s x 4s x 6s block (a no-op once MapKit is fixed) and dress it in the rift's dark stone.
local function fixPlinth(plinth: BasePart, base: Vector3, facing: Vector3, s: number)
	local frame = MapKit.Facing(base, base + facing)
	plinth.Size = V(6, 4, 6) * s
	plinth.CFrame = frame * CFrame.new(0, 2 * s, 0)
	plinth.Color = C.StoneSide
	plinth.Material = M.Slate
end

-- Sections ---------------------------------------------------------------------------------------------------

type Isles = { [string]: Island }

local function buildCore(B: Builder, core: Island): number
	B:Group("Core")
	local lights = 0
	-- calm duel floor: low-contrast inlay rings and ticks (no neon in the middle)
	B:Ring("Decor", "InlayOuter", V(0, 0.03, 0), 24, 0.55, 0.06, 48, C.Inlay, M.Metal, { Shadow = false })
	B:Ring("Decor", "InlayInner", V(0, 0.03, 0), 11, 0.4, 0.06, 32, C.Inlay, M.Metal, { Shadow = false })
	for k = 0, 11 do
		local a = k * 30 + 15
		local len = if k % 3 == 0 then 4 else 2.2
		B:Beam(
			"Decor",
			"InlayTick",
			polar(a, 24 - 0.6 - len, 0.035),
			polar(a, 24 - 0.6, 0.035),
			0.35,
			0.06,
			C.Inlay,
			M.Metal,
			{ Shadow = false }
		)
	end
	B:Deco(
		"Block",
		"InlayCenter",
		V(2.4, 0.06, 2.4),
		CFrame.new(0, 0.035, 0) * CFrame.Angles(0, math.rad(45), 0),
		C.Inlay,
		M.Metal,
		{ Shadow = false }
	)
	-- broken monoliths (cover) — off-centre so the middle stays open
	monolith(B, "Monolith", V(15, 0, -13), V(3.4, 9, 2.6), 28, 6, C.Crack)
	monolith(B, "Monolith", V(-18, 0, 9), V(3.8, 7.5, 2.8), -62, -8, C.Crack)
	monolith(B, "Monolith", V(-9, 0, -21), V(3, 6, 2.4), 12, 10, C.CrackDeep)
	monolith(B, "Monolith", V(19, 0, 15), V(3.2, 6.8, 2.6), 118, -5, C.CrackDeep)
	-- fallen pillar drums and a broken wall: low cover between the spokes
	for k, d in { { V(-9, 0, 17), 18 }, { V(24, 0, -19), -40 } } do
		local p: Vector3, yaw: number = d[1], d[2]
		local frame = CFrame.new(p) * CFrame.Angles(0, math.rad(yaw), 0)
		for j = -1, 1 do
			local drum = frame * CFrame.new(j * 3.7, 1.6, j * 0.4) * CFrame.Angles(0, math.rad(j * 9), 0)
			B:Solid("Cylinder", "FallenDrum", V(3.4, 3.2, 3.2), drum, MapKit.Shade(C.StoneLight, j * 0.05), M.Slate)
			B:Deco(
				"Cylinder",
				"FallenDrumRing",
				V(0.2, 3.3, 3.3),
				drum * CFrame.new(1.72, 0, 0),
				C.StoneSide,
				M.Slate,
				{ Shadow = false }
			)
		end
		if k == 1 then
			B:Rod(
				"Decor",
				"FallenDrumCrack",
				(frame * CFrame.new(-4, 3.25, 0)).Position,
				(frame * CFrame.new(3, 3.25, 0.3)).Position,
				0.14,
				C.Crack,
				M.Neon,
				{ Shadow = false }
			)
		end
	end
	B:Solid(
		"Block",
		"BrokenWall",
		V(9, 4.2, 1.6),
		CFrame.new(-26, 2.1, -14) * CFrame.Angles(0, math.rad(64), 0),
		C.StoneLight,
		M.Slate
	)
	B:Deco(
		"Wedge",
		"BrokenWallTop",
		V(1.6, 2.4, 5),
		CFrame.new(-26, 0, -14)
			* CFrame.Angles(0, math.rad(64), 0)
			* CFrame.new(2, 5.4, 0)
			* CFrame.Angles(0, math.rad(90), 0),
		C.StoneLight,
		M.Slate
	)
	B:Rock("Rubble", V(-27, 0, -2), 3.4, { Color = C.StoneSide, Material = M.Slate, Collide = true })
	B:Rock("Rubble", V(5, 0, 26), 3, { Color = C.StoneSide, Material = M.Slate, Collide = true })
	B:Rock("Rubble", V(27, 0, -2), 3.2, { Color = C.StoneSide, Material = M.Slate, Collide = true })
	-- low rims on two stretches of the rim (the rest of the duel ring's edge stays open and dangerous)
	rim(B, core, 122, 168)
	rim(B, core, 302, 346)
	-- spoke heads: pylons pairs at the four ramps
	for _, deg in { 90, 270, 31.7, 204.7 } do
		local d = polar(deg, 1)
		local e = edgePoint(core, d * 100, 3.2)
		local side = V(-d.Z, 0, d.X)
		local half = if deg == 90 then 9.6 elseif deg == 270 then 8.6 else 7.6
		for _, s in { -1, 1 } do
			pylon(B, "SpokePylon", e + side * (s * half), 4.6, if deg == 270 then C.Violet else C.Crack)
		end
	end
	-- light pools near the rim (Neon does not light its surroundings)
	for _, deg in { 0, 120, 160, 300 } do
		local d = polar(deg, 1)
		local e = edgePoint(core, d * 100, 6)
		B:Light("Point", e + UP * 3, { Name = "CoreGlow", Brightness = 1.1, Range = 20, Color = C.Light })
		lights += 1
	end
	B:Group(nil)
	return lights
end

local function buildGate(B: Builder, gate: Island): number
	B:Group("Gate")
	local lights = 0
	local base = V(0, gate.Top, -93)
	rift(B, "Rift", CFrame.new(base + V(0, 1.2, 0)), 23, 10)
	-- the rift's foot: a cracked dais
	B:Disc("Geometry", "RiftDais", base + V(0, 0.3, 1), 11, 0.6, C.StoneLight, M.Slate)
	B:Disc(
		"Decor",
		"RiftDaisGlow",
		base + V(0, 0.62, 1),
		8.4,
		0.06,
		C.Violet,
		M.Neon,
		{ Shadow = false, Transparency = 0.3 }
	)
	-- cracks spreading from the rift across the floor towards the stairs
	local rng = B.Rng
	for k = -2, 2 do
		local dir = V(k * 0.32 + rng:Number(-0.08, 0.08), 0, 1).Unit
		floorCrack(
			B,
			"RiftCrack",
			base + V(dir.X * 4, 0.035, 4),
			dir,
			rng:Number(8, 13),
			0.42,
			if k % 2 == 0 then C.Crack else C.Violet
		)
	end
	-- giant flanking bones (one broken)
	bigBone(B, "GateBone", base + V(-11, 0.8, 1), base + V(-11.6, 24, 0.4), 2.6, C.Bone, true)
	bigBone(B, "GateBoneBroken", base + V(11, 0.8, 1), base + V(12.6, 15, -0.6), 2.6, C.Bone, true)
	-- the broken end: jagged shards + a floating piece
	local brk = base + V(12.7, 16, -0.6)
	for i = 1, 4 do
		B:Deco(
			"Wedge",
			"GateBoneShard",
			V(0.7, 1.4, 1.1),
			CFrame.new(brk + V(rng:Number(-0.8, 0.8), 0.3, rng:Number(-0.8, 0.8)))
				* CFrame.Angles(0, math.rad(i * 90), 0),
			C.Bone,
			M.SmoothPlastic
		)
	end
	bigBone(B, "GateBoneFloat", base + V(14, 21, -1), base + V(15.5, 26.5, 0.5), 2.4, C.BoneShade, false)
	-- floating stone shards drawn towards the tear
	for i = 1, 10 do
		local a = rng:Number(0, 2 * math.pi)
		local r = rng:Number(9, 17)
		local pos = base + V(math.cos(a) * r, 14 + math.sin(a) * r * 0.8, rng:Number(-3, 3))
		local s = rng:Number(0.8, 2.4)
		local cf = CFrame.new(pos) * CFrame.Angles(rng:Number(0, 6.28), rng:Number(0, 6.28), rng:Number(0, 6.28))
		B:Deco("Block", "RiftShard", V(s, s * 1.6, s * 0.7), cf, C.StoneSide, M.Slate)
		if i % 3 == 0 then
			B:Deco(
				"Block",
				"RiftShardEdge",
				V(s * 1.04, 0.12, 0.12),
				cf * CFrame.new(0, s * 0.8, 0),
				C.Crack,
				M.Neon,
				{ Shadow = false }
			)
		end
	end
	local l = B:Light(
		"Point",
		base + V(0, 12, 4),
		{ Name = "RiftLight", Brightness = 1.8, Range = 44, Color = rgb(170, 226, 255), Shadows = true }
	)
	local _ = l
	lights += 1
	B:Light("Point", base + V(0, 3, 10), { Name = "RiftFloor", Brightness = 1.2, Range = 18, Color = C.LightViolet })
	lights += 1
	-- rim behind the rift (fair: nobody slides off the back while dodging)
	rim(B, gate, 210, 330)
	B:Group(nil)
	return lights
end

local function buildGiantSkull(B: Builder): number
	B:Group("GiantSkull")
	local rngLayout = Rng.new("VoidRift.SkullRock")
	local base = L.SkullRock
	local rock = makeIsland({
		Name = "SkullRock",
		Center = base,
		RX = 18,
		RZ = 15,
		Verts = 9,
		Jitter = { 0.92, 1.05 },
		Phase = 10,
		Depth = 1.7,
	}, rngLayout)
	buildIsland(B, rock, { Cracks = 4, Debris = 6, CrackScale = 1.3 })
	local s = L.SkullScale
	local facing = flat(V(0, 0, 0) - base).Unit
	local plinth = B:SkullStatue("GiantSkull", base, {
		Scale = s,
		Facing = facing,
		Color = C.Bone,
		Dark = rgb(8, 10, 24),
		Accent = rgb(44, 58, 104),
		Eye = C.Crack,
	})
	fixPlinth(plinth, base, facing, s)
	local frame = MapKit.Facing(base, base + facing)
	-- glowing fractures running down the plinth's front
	for k, x in { -2.2, 1.4 } do
		local pts: { Vector3 } = {}
		for i = 0, 3 do
			local jig = if i % 2 == 0 then 0.5 else -0.4
			table.insert(
				pts,
				(frame * CFrame.new((x + jig * k) * s * 0.4, 4 * s - 0.8 - i * (4 * s - 1.6) / 3, -3 * s - 0.06)).Position
			)
		end
		for i = 1, #pts - 1 do
			B:Rod(
				"Decor",
				"PlinthCrack",
				pts[i],
				pts[i + 1],
				0.32,
				if k == 1 then C.Crack else C.Violet,
				M.Neon,
				{ Shadow = false }
			)
		end
	end
	local head = frame * CFrame.new(0, 4 * s + 3.4 * s, 0)
	crackSkull(B, "GiantSkull", head, s, -1, C.Crack, 9)
	-- the left eye burns (Sans' eye): a translucent glow ball + a light that also catches the face
	local eye = head * CFrame.new(-1.35 * s, 0.15 * s, -2.9 * s)
	B:Ball("Decor", "GiantSkullEyeGlow", eye.Position, 1.4 * s, C.Crack, M.Neon, { Transparency = 0.6, Shadow = false })
	B:Light(
		"Point",
		(head * CFrame.new(0, -1 * s, -6 * s)).Position,
		{ Name = "SkullFace", Brightness = 1.6, Range = 34, Color = C.Light }
	)
	B:Group(nil)
	return 1
end

local function buildCrown(B: Builder, crown: Island): number
	B:Group("Crown")
	local c = crown.Center
	local stones = { { 0, 7 }, { 48, 5.2 }, { 140, 6.4 }, { 262, 4.6 }, { 314, 6 } }
	for i, st in stones do
		local p = c + polar(st[1], 10.4)
		monolith(B, "CrownStone", p, V(2.4, st[2], 2.2), -st[1] + 90, (i % 2 == 0 and 7 or -6), C.Violet)
	end
	rim(B, crown, 300, 70)
	B:Light("Point", c + V(0, 6, 0), { Name = "CrownLight", Brightness = 1.3, Range = 22, Color = C.LightViolet })
	B:Group(nil)
	return 1
end

local function buildSkullIsle(B: Builder, isle: Island): number
	B:Group("SkullIsle")
	local s = 1.8
	local top = isle.Top
	local plinthPos = V(78, top, 45)
	local toCore = flat(V(0, 0, 0) - plinthPos).Unit
	local plinth = B:SkullStatue("IsleSkull", plinthPos, {
		Scale = s,
		Facing = toCore,
		Color = C.Bone,
		Dark = rgb(8, 10, 24),
		Accent = rgb(44, 58, 104),
		Eye = C.Crack,
	})
	fixPlinth(plinth, plinthPos, toCore, s)
	-- the head has fallen off its plinth: move every head part onto the floor, rolled on its side
	local frame = MapKit.Facing(plinthPos, plinthPos + toCore)
	local oldHead = frame * CFrame.new(0, 4 * s + 3.4 * s, 0)
	local newHead = CFrame.new(V(73.5, top + 2.75 * s, 31))
		* (oldHead - oldHead.Position)
		* CFrame.Angles(math.rad(-14), math.rad(25), math.rad(34))
	local move = newHead * oldHead:Inverse()
	local keep = { ["IsleSkull_Plinth"] = true, ["IsleSkull_PlinthBand"] = true }
	for _, folderName in { "Geometry", "Decor" } do
		local folder = B.Folders[folderName]:FindFirstChild("SkullIsle")
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("BasePart") and string.sub(child.Name, 1, 10) == "IsleSkull_" and not keep[child.Name] then
					child.CFrame = move * child.CFrame
				end
			end
		end
	end
	crackSkull(B, "IsleSkull", newHead, s, 1, C.Crack, 5)
	B:Solid(
		"Ball",
		"IsleSkullCollider",
		V(5.6, 5.6, 5.6) * s,
		CFrame.new(newHead.Position),
		C.Bone,
		M.SmoothPlastic,
		{ Transparency = 1, Shadow = false }
	)
	-- bones scattered around the empty plinth
	B:Bones(
		"IsleBones",
		CFrame.new(plinthPos + V(0, 4 * s + 0.4, 0)) * CFrame.Angles(math.rad(90), math.rad(30), 0),
		{ Length = 4, Thickness = 0.5, Color = C.Bone }
	)
	B:Bones("IslePile", CFrame.new(V(66, top, 30)), { Pile = 5, Length = 3.4, Thickness = 0.42, Color = C.BoneShade })
	rim(B, isle, 20, 140)
	B:Light("Point", V(64, top + 5, 40), { Name = "SkullIsleLight", Brightness = 1.1, Range = 20, Color = C.Light })
	B:Group(nil)
	return 1
end

local function buildLanding(B: Builder, landing: Island): number
	B:Group("Landing")
	local c = landing.Center
	-- a faint SOUL-red heart inlay where the humans wake up
	B:Heart(
		"Decor",
		"WakingHeart",
		CFrame.new(c + V(0, 0.04, 0.5)) * CFrame.Angles(-math.pi / 2, 0, 0),
		5.2,
		0.05,
		rgb(120, 26, 46),
		M.Slate,
		{ Shadow = false }
	)
	B:Ring("Decor", "WakingRing", c + V(0, 0.03, 0), 8.6, 0.35, 0.05, 32, C.Inlay, M.Metal, { Shadow = false })
	-- low rim along the back (south) half
	rim(B, landing, 25, 155)
	-- rubble and bones at the sides
	B:Rock("LandingRock", c + V(-20, 0, 2), 3.2, { Color = C.StoneSide, Material = M.Slate, Collide = true })
	B:Rock("LandingRock", c + V(21, 0, -1), 2.8, { Color = C.StoneSide, Material = M.Slate, Collide = true })
	B:Bones(
		"LandingBones",
		CFrame.new(c + V(-18, 0.4, 7)) * CFrame.Angles(math.rad(90), math.rad(-20), 0),
		{ Length = 3.4, Thickness = 0.4, Color = C.BoneShade }
	)
	B:Group(nil)
	return 0
end

local function buildDrift(B: Builder, drift: Island): number
	B:Group("Drift")
	local c = drift.Center
	B:Rock("DriftRock", c + V(-4, 0, -3), 4.2, { Color = C.StoneLight, Material = M.Slate, Collide = true, Chunks = 3 })
	B:Rock("DriftRock", c + V(5, 0, 4), 3.4, { Color = C.StoneLight, Material = M.Slate, Collide = true })
	B:Bones("DriftPile", CFrame.new(c + V(3, 0, -6)), { Pile = 4, Length = 3.2, Thickness = 0.4, Color = C.Bone })
	B:Crystal("DriftCrystal", c + V(-7, 0, 5), 5, { Color = C.CrystalViolet, Count = 3, Light = false })
	rim(B, drift, 120, 220)
	B:Light("Point", c + V(0, 5, 0), { Name = "DriftLight", Brightness = 1, Range = 18, Color = C.LightViolet })
	B:Group(nil)
	return 1
end

local function buildShards(B: Builder, shards: Island): number
	B:Group("Shards")
	local c = shards.Center
	local lights = 0
	local l1 =
		B:Crystal("ScarCrystal", c + V(-11, 0, 3), 9, { Color = C.Crystal, Count = 5, Brightness = 1.5, Range = 18 })
	if l1 then
		lights += 1
	end
	B:Crystal("ScarCrystal", c + V(-8, 0, -12), 6.5, { Color = C.CrystalViolet, Count = 4, Light = false })
	local l2 =
		B:Crystal("ScarCrystal", c + V(-4, 0, 14), 6, { Color = C.Crystal, Count = 4, Brightness = 1.1, Range = 14 })
	if l2 then
		lights += 1
	end
	monolith(B, "ScarObelisk", c + V(8, 0, -10), V(3.2, 10, 3), 20, -9, C.Crack)
	B:Rock("ScarRock", c + V(9, 0, 9), 3.6, { Color = C.StoneLight, Material = M.Slate, Collide = true })
	rim(B, shards, 140, 235)
	B:Group(nil)
	return lights
end

local function buildRibway(B: Builder, a: Vector3, b: Vector3): number
	B:Group("Ribway")
	causeway(B, "Ribway", a, b, { Width = 16, Slabs = 1, Rims = "Both", Keel = false })
	-- fossil spine under the deck
	local z0, z1 = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
	local z = z0 + 1.5
	while z < z1 - 1 do
		B:Deco("Block", "Vertebra", V(3.6, 2.6, 2.8), CFrame.new(0, -4.4, z), C.BoneShade, M.SmoothPlastic)
		B:Deco(
			"Wedge",
			"VertebraSpine",
			V(1.2, 2.6, 2.4),
			CFrame.new(0, -6.9, z + 0.3) * CFrame.Angles(math.rad(180), 0, 0),
			C.BoneShade,
			M.SmoothPlastic
		)
		B:Rod("Decor", "VertebraWing", V(-3.4, -4.2, z), V(3.4, -4.2, z), 1, C.BoneShade, M.SmoothPlastic)
		B:Deco(
			"Block",
			"Disc",
			V(2.6, 2, 0.6),
			CFrame.new(0, -4.4, z + 2),
			rgb(70, 90, 140),
			M.SmoothPlastic,
			{ Shadow = false }
		)
		z += 4
	end
	-- rib arches
	local ribZ = { 39, 46, 53, 60, 66.5 }
	for k, rz in ribZ do
		local scale = 1 - math.abs(k - 3) * 0.07
		for _, s in { -1, 1 } do
			local broken = (k == 2 and s == 1) or (k == 4 and s == -1)
			local pts: { Vector3 } = {}
			local phiEnd = if broken then 36 else 80
			for i = 0, 8 do
				local phi = math.rad(-80 + (phiEnd + 80) * i / 8)
				local ry = if phi < 0 then 6.5 else 15.5 * scale
				local x = 11.5 * scale * math.cos(phi)
				local y = 2 + ry * math.sin(phi)
				local zOff = (math.sin(phi) + 1) * 1.3
				table.insert(pts, V(s * x, y, rz + zOff))
			end
			bonePath(B, "Rib", pts, 1.15, if broken then 1.4 else 0.9, C.Bone, not broken)
			if broken then
				local tip = pts[#pts]
				for i = 1, 3 do
					B:Deco(
						"Wedge",
						"RibShard",
						V(0.6, 1.2, 0.9),
						CFrame.new(tip + V(0, 0.4, 0)) * CFrame.Angles(0, math.rad(i * 120), math.rad(s * 20)),
						C.Bone,
						M.SmoothPlastic
					)
				end
				B:Rod(
					"Decor",
					"RibFragment",
					tip + V(-s * 2.5, 4.5, 0.5),
					tip + V(-s * 5, 6.4, 1),
					1.3,
					C.BoneShade,
					M.SmoothPlastic
				)
			end
			-- the rib meets the deck edge: solid knuckle (rim post)
			B:Solid(
				"Ball",
				"RibKnuckle",
				V(2.8, 2.8, 2.8),
				CFrame.new(V(s * 8.6, 0.5, rz + 0.6)),
				C.Bone,
				M.SmoothPlastic
			)
		end
	end
	local l1 = B:Light("Point", V(0, 11, 44), { Name = "RibLight", Brightness = 1.2, Range = 24, Color = C.Light })
	local l2 = B:Light("Point", V(0, 11, 61), { Name = "RibLight", Brightness = 1.2, Range = 24, Color = C.Light })
	local _, _ = l1, l2
	B:Group(nil)
	return 2
end

local function buildGateStairs(B: Builder, core: Island, gate: Island)
	B:Group("GateStairs")
	local zStart = -edgeDistance(core, V(0, 0, -1)) + 0.6
	local zEnd = gate.Center.Z + edgeDistance(gate, V(0, 0, 1)) - 1
	local run = zStart - zEnd
	local rise = gate.Top - core.Top + 0.04
	local cf = MapKit.Facing(V(0, core.Top, zStart), V(0, core.Top, zStart - 10))
	local stairParts = B:Stairs(
		"GateStairs",
		cf,
		14,
		rise,
		run,
		{ Color = C.StoneLight, Material = M.Slate, Nose = C.CrackDeep, NoseMaterial = M.Neon, Steps = 10 }
	)
	-- decor never answers queries: the invisible ramp takes over ground probes from the visual steps
	for _, part in stairParts do
		part.CanQuery = part.Name == "GateStairs_Ramp"
	end
	-- side walls (low, collidable) + guards
	for _, s in { -1, 1 } do
		local a = V(s * 7.6, core.Top + 0.6, zStart - 1)
		local b = V(s * 7.6, gate.Top + 0.6, zEnd + 1)
		B:Beam("Geometry", "StairWall", a, b, 1.2, 1.4, C.StoneSide, M.Slate)
		B:Beam(
			"Decor",
			"StairWallGlow",
			a + UP * 0.72,
			b + UP * 0.72,
			0.3,
			0.08,
			C.CrackDeep,
			M.Neon,
			{ Shadow = false }
		)
		B:Beam(
			"Geometry",
			"StairGuard",
			a + UP * 1.6,
			b + UP * 1.6,
			0.6,
			3.4,
			C.StoneSide,
			M.SmoothPlastic,
			{ Transparency = 1, Shadow = false, Query = false }
		)
	end
	-- hanging rock keel under the stair
	local mid = V(0, core.Top - 1, (zStart + zEnd) / 2)
	B:Beam(
		"Decor",
		"StairKeel",
		V(0, core.Top - 2.5, zStart - 2),
		V(0, gate.Top - 3, zEnd + 2),
		9,
		4,
		C.Under,
		M.Slate,
		{ Shadow = false }
	)
	B:Cone("Decor", "StairRoot", mid - UP * 3, -14, 6, 6, C.Deep, M.Slate, { Phase = 15, Shadow = false })
	B:Group(nil)
end

-- Far scenery: drifting islands, mid-depth debris and sky shards (all decor).
local function buildVoid(B: Builder, isles: Isles, overview: boolean)
	B:Group("Void")
	local rng = B.Rng
	-- mid-depth debris under and between the islands
	for _ = 1, 46 do
		local deg = rng:Number(0, 360)
		local r = rng:Number(14, 112)
		local pos = polar(deg, r, rng:Number(-44, -10))
		local s = rng:Number(1.4, 6.5)
		local cf = CFrame.new(pos) * CFrame.Angles(rng:Number(0, 6.28), rng:Number(0, 6.28), rng:Number(0, 6.28))
		B:Deco(
			"Block",
			"Debris",
			V(s, s * rng:Number(0.4, 0.9), s * rng:Number(0.5, 1)),
			cf,
			MapKit.Shade(C.StoneSide, rng:Number(-0.25, 0.15)),
			M.Slate,
			{ Shadow = false }
		)
		if rng:Bool(0.25) then
			B:Deco(
				"Block",
				"DebrisGlow",
				V(s * 1.02, 0.14, 0.14),
				cf * CFrame.new(0, s * 0.2, s * 0.25),
				C.Crack,
				M.Neon,
				{ Shadow = false }
			)
		end
	end
	if overview then
		B:Group(nil)
		return
	end
	-- distant drifting islands (silhouettes in the haze)
	for i = 1, 16 do
		local deg = i * 22.5 + rng:Number(-8, 8)
		local r = rng:Number(150, 250)
		local y = rng:Number(-70, 36)
		local size = rng:Number(8, 26)
		local p = polar(deg, r, y)
		local yaw = rng:Number(0, 360)
		B:Deco(
			"Block",
			"FarIsle",
			V(size, size * 0.22, size * rng:Number(0.6, 0.95)),
			CFrame.new(p) * CFrame.Angles(0, math.rad(yaw), 0),
			MapKit.Shade(C.StoneSide, rng:Number(-0.2, 0.1)),
			M.Slate,
			{ Shadow = false }
		)
		B:Cone(
			"Decor",
			"FarIsleRoot",
			p - V(0, size * 0.11, 0),
			-size * rng:Number(0.7, 1.2),
			size * 0.42,
			5,
			C.Deep,
			M.Slate,
			{ Phase = yaw, Shadow = false }
		)
		if i % 3 == 0 then
			B:Rod(
				"Decor",
				"FarIsleVein",
				p - V(size * 0.2, size * 0.11, 0),
				p - V(0, size * 0.8, 0),
				0.5,
				C.Crack,
				M.Neon,
				{ Shadow = false }
			)
		end
		if i % 4 == 1 then
			B:Rod(
				"Decor",
				"FarBone",
				p + V(-size * 0.3, size * 0.11 + 1, 0),
				p + V(size * 0.25, size * 0.11 + 2.5, size * 0.1),
				size * 0.08,
				C.BoneShade,
				M.SmoothPlastic,
				{ Shadow = false }
			)
		end
	end
	-- tall dark shards hanging in the sky beyond the boundary
	for i = 1, 7 do
		local deg = i * 51 + rng:Number(-10, 10)
		local p = polar(deg, rng:Number(128, 170), rng:Number(30, 70))
		local h = rng:Number(14, 30)
		local cf = CFrame.new(p)
			* CFrame.Angles(math.rad(rng:Number(-25, 25)), math.rad(rng:Number(0, 360)), math.rad(rng:Number(-25, 25)))
		B:Deco("Block", "SkyShard", V(h * 0.22, h, h * 0.16), cf, C.StoneSide, M.Slate, { Shadow = false })
		B:Deco(
			"Block",
			"SkyShardEdge",
			V(0.25, h * 0.96, 0.25),
			cf * CFrame.new(h * 0.11, 0, -h * 0.08),
			C.Crack,
			M.Neon,
			{ Shadow = false }
		)
	end
	local _ = isles
	B:Group(nil)
end

local function buildBoundary(B: Builder)
	local n = 16
	local r = L.BoundaryR
	local len = 2 * r * math.tan(math.pi / n) + 2
	for k = 0, n - 1 do
		local a = (k + 0.5) * 2 * math.pi / n
		local center = V(math.cos(a) * r, L.BoundaryBottom, math.sin(a) * r)
		local tangent = V(-math.sin(a), 0, math.cos(a))
		B:Boundary("Boundary" .. k, CFrame.fromMatrix(center, tangent, UP), len, L.BoundaryHeight, 2)
	end
end

-- MapInfo -------------------------------------------------------------------------------------------------------

function VoidRift.Build(seed: number?, opts: { [string]: any }?): MapInfo
	local o = opts or {}
	local B = MapKit.new("VoidRift", { Seed = seed or 1 })
	-- island outlines come from a FIXED rng: gameplay geometry never depends on the seed
	local layoutRng = Rng.new("VoidRift.Layout")
	local isles: Isles = {}
	for _, spec in ISLANDS do
		isles[spec.Name] = makeIsland(spec, layoutRng)
	end
	local core, gate, crown, skull = isles.Core, isles.Gate, isles.Crown, isles.Skull
	local landing, drift, shards, step = isles.Landing, isles.Drift, isles.Shards, isles.Step
	local bridges = {
		{ "GateCrown", gate, crown },
		{ "CrownWatcher", crown, skull },
		{ "WatcherShore", skull, landing },
		{ "ShoreDrift", landing, drift },
		{ "DriftScar", drift, shards },
		{ "ScarStep", shards, step },
		{ "StepGate", step, gate },
	}
	-- every ramp / bridge attachment is an opening that rims leave free
	local function opening(isl: Island, toward: Island, width: number)
		local p = edgePoint(isl, toward.Center, 0)
		table.insert(isl.Openings, V(p.X, width / 2 + 2.5, p.Z))
	end
	for _, spoke in { { landing, 16 }, { gate, 14 }, { shards, 11 }, { skull, 12 } } do
		local other: Island, width: number = spoke[1], spoke[2]
		opening(core, other, width)
		opening(other, core, width)
	end
	for _, link in bridges do
		local A: Island, Bi: Island = link[2], link[3]
		opening(A, Bi, 7)
		opening(Bi, A, 7)
	end

	local lights = 0
	B:Group("Islands")
	buildIsland(B, core, { Cracks = 9, Debris = 8, AvoidDeg = { 90, 270, 31.7, 204.7 } })
	buildIsland(B, gate, { Cracks = 4, Color = MapKit.Shade(C.Stone, -0.06), Vein = C.Violet })
	buildIsland(B, crown, { Cracks = 4, Vein = C.Violet, VeinPhase = 1 })
	buildIsland(B, skull, { Cracks = 5 })
	buildIsland(B, landing, { Cracks = 4, VeinPhase = 2 })
	buildIsland(B, drift, { Cracks = 3, Vein = C.Violet })
	buildIsland(B, shards, { Cracks = 5, VeinPhase = 1 })
	buildIsland(B, step, { Cracks = 2, Debris = 3 })
	B:Group(nil)

	lights += buildCore(B, core)
	lights += buildGate(B, gate)
	lights += buildGiantSkull(B)
	lights += buildCrown(B, crown)
	lights += buildSkullIsle(B, skull)
	lights += buildLanding(B, landing)
	lights += buildDrift(B, drift)
	lights += buildShards(B, shards)

	-- spokes: stone ramps from the centre
	lights += buildRibway(
		B,
		edgePoint(core, landing.Center, 1.2) + UP * 0.05,
		edgePoint(landing, core.Center, 1.2) + UP * 0.05
	)
	buildGateStairs(B, core, gate)
	B:Group("Ramps")
	causeway(
		B,
		"ScarCauseway",
		edgePoint(core, shards.Center, 1.2) + UP * 0.05,
		edgePoint(shards, core.Center, 1.2) + UP * 0.05,
		{ Width = 11, Slabs = 3 }
	)
	causeway(
		B,
		"WatcherRamp",
		edgePoint(core, skull.Center, 1.2) + UP * 0.05,
		edgePoint(skull, core.Center, 1.2) + UP * 0.05,
		{ Width = 12, Slabs = 2, Rims = "Right" }
	)
	B:Group(nil)

	-- bridges of light: the outer loop
	B:Group("Bridges")
	for _, link in bridges do
		local A: Island, Bi: Island = link[2], link[3]
		lightBridge(B, link[1], edgePoint(A, Bi.Center, 1.2), edgePoint(Bi, A.Center, 1.2), 7)
		lights += 1
	end
	B:Light("Point", step.Center + UP * 4, { Name = "StepLight", Brightness = 1, Range = 16, Color = C.Light })
	lights += 1
	B:Group(nil)

	buildVoid(B, isles, o.Overview == true)
	buildBoundary(B)

	-- objectives and spawns
	local saveStyle = { Inner = rgb(22, 26, 52), InnerMaterial = M.Slate }
	local saves = {
		B:SavePoint(1, L.Saves[1], saveStyle),
		B:SavePoint(2, L.Saves[2], saveStyle),
		B:SavePoint(3, L.Saves[3], saveStyle),
	}
	local center = V(0, 0, 0)
	local humanSpawns: { CFrame } = {}
	local i = 0
	for _, dz in { -1, 6 } do
		for _, x in { -12.5, -7.5, -2.5, 2.5, 7.5, 12.5 } do
			i += 1
			local p = V(x, landing.Top, landing.Center.Z + dz)
			table.insert(humanSpawns, B:SpawnPoint("Human", i, MapKit.SpawnFacing(p, V(x * 0.4, landing.Top, 0))))
		end
	end
	local monsterSpawn = B:SpawnPoint("Monster", 1, MapKit.SpawnFacing(L.MonsterSpawn, V(0, L.MonsterSpawn.Y, 0)))
	B:Marker("Center", CFrame.new(center + V(0, 0.5, 0)))
	B:KillFloor(L.KillY, 400)
	local _ = lights
	B:Finish(VoidRift.Id)

	return {
		Id = VoidRift.Id,
		Model = B.Model,
		HumanSpawns = humanSpawns,
		MonsterSpawn = monsterSpawn,
		SavePoints = saves,
		Center = center,
		Radius = L.Radius,
		KillY = L.KillY,
		IntroPath = {
			MapKit.LookAt(V(-150, 64, 170), V(-10, 0, 10)),
			MapKit.LookAt(V(-34, 16, 116), V(0, 8, 40)),
			MapKit.LookAt(V(0, 12, 54), V(0, 6, -10)),
			MapKit.LookAt(V(36, 22, -6), V(0, 16, -90)),
			MapKit.LookAt(V(10, 14, -46), V(0, 14, -92)),
			MapKit.LookAt(V(0, 12, -60), V(0, 10, -80)),
		},
		Preset = VoidRift.Preset,
		FinalPreset = VoidRift.FinalPreset,
		Music = VoidRift.Music,
	}
end

return VoidRift
