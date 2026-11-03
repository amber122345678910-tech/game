--!strict
-- The battlefield: the wide concrete deck of an elevated road in a ruined
-- city (no snow), cracked, with a rubble crater, the
-- trench Rika's beam carves, ruined city blocks in the distance, mist plates
-- that follow the camera and drifting dust.
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local Paint = require(script.Parent.Parent.Paint)
local Util = require(script.Parent.Parent.Util)

local Field = {}

local V = Vector3.new
local C = CFrame.new

-- reference positions (studs)
Field.RYU = V(-31, 0, -117) -- where Ryu stands for most of the fight
Field.YUTA = V(36, 0, -134)
Field.RIKA = V(25, 0, -119)
Field.CRATER = V(-6, 0, -146)

export type Handles = {
	mist: { [string]: Builder.PartSpec },
	snow: Builder.PartSpec,
}

-- the furrow Rika's beam ploughs towards Ryu (built hidden, revealed in shot 26)
export type TrenchPiece = { part: Builder.PartSpec, cf: CFrame }
export type Trench = {
	from: Vector3,
	to: Vector3,
	ctrl: Vector3,
	rows: { { f: number, pieces: { TrenchPiece } } },
	floors: { { f0: number, f1: number, part: Builder.PartSpec } },
}

-- The beam does not fly straight: it bends in a wide arc on its way to Ryu
-- (reference, top view). Quadratic Bezier on the ground, f = 0..1.
Field.TRENCH_FROM = V(70, 0, -60)
Field.TRENCH_TO = Field.RYU + V(6, 0, -4)
Field.TRENCH_CTRL = V(36, 0, -112)

function Field.trenchPoint(f: number): Vector3
	local a, b, c = Field.TRENCH_FROM, Field.TRENCH_CTRL, Field.TRENCH_TO
	local u = 1 - f
	return a * (u * u) + b * (2 * u * f) + c * (f * f)
end

function Field.trenchTangent(f: number): Vector3
	local a, b, c = Field.TRENCH_FROM, Field.TRENCH_CTRL, Field.TRENCH_TO
	return ((b - a) * (2 * (1 - f)) + (c - b) * (2 * f)).Unit
end

Field.TRENCH_T0 = 35.6
Field.TRENCH_T1 = 36.867

local function rubble(scene: Builder.Scene, r: Util.Rng, center: Vector3, radius: number, n: number, size: number, cols: { Color3 }, mat: string)
	for i = 1, n do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d = radius * math.sqrt(Util.rand(r))
		local s = size * Util.randRange(r, 0.4, 1.5)
		local p = center + V(math.cos(a) * d, s * 0.25, math.sin(a) * d)
		local shape = if i % 3 == 0 then "Wedge" else "Block"
		Builder.part(scene, "Field", V(s * Util.randRange(r, 0.7, 1.6), s * Util.randRange(r, 0.4, 1.0), s * Util.randRange(r, 0.7, 1.4)), C(p) * CFrame.Angles(Util.randRange(r, -0.6, 0.6), Util.randRange(r, 0, 6.28), Util.randRange(r, -0.6, 0.6)), cols[(i % #cols) + 1], { shape = shape, material = mat, name = "Rubble" })
	end
end

local function cracks(scene: Builder.Scene, r: Util.Rng, center: Vector3, n: number, len: number, col: Color3)
	for _ = 1, n do
		local a = Util.randRange(r, 0, math.pi * 2)
		local p = center + V(Util.randRange(r, -20, 20), 0.06, Util.randRange(r, -20, 20))
		local segs = math.floor(Util.randRange(r, 3, 7))
		for _ = 1, segs do
			a += Util.randRange(r, -0.7, 0.7)
			local l = len * Util.randRange(r, 0.4, 1.0)
			local q = p + V(math.cos(a) * l, 0, math.sin(a) * l)
			local mid = (p + q) / 2
			Builder.part(scene, "Field", V(l, 0.05, Util.randRange(r, 0.08, 0.22)), C(mid) * CFrame.Angles(0, -a, 0), col, { material = "SmoothPlastic", castShadow = false, name = "Crack" })
			p = q
		end
	end
end

-- soft mist painting for a camera plate (canvas units = 1/10 stud)
local function mistPlate(scene: Builder.Scene, name: string, w: number, h: number, seed: number, paint: (Paint.Canvas, Util.Rng) -> ()): Builder.PartSpec
	local c = Paint.canvas(1, 0, 0)
	paint(c, Util.rng(seed))
	local p = Builder.part(scene, "Mist", V(w / 10, h / 10, 0.05), C(), Color3.new(1, 1, 1), {
		transparency = 1,
		castShadow = false,
		fx = true,
		name = name,
		gui = { face = "Front", canvas = Vector2.new(w, h), lightInfluence = 0, elems = c.elems },
	})
	return p
end

-- The battlefield is a wide elevated road in the city (reference: the top
-- view shows lanes with yellow markings). Lanes cross the deck,
-- ruined blocks stand around it at a distance (silhouettes in the fog),
-- with bent lamp posts, abandoned cars and broken concrete.
local function city(scene: Builder.Scene)
	local pal = scene.style.color
	local r = Util.rng(7171)
	local asphalt = Util.mix(pal.concreteDark, pal.ground, 0.45)
	local curb = Util.mix(pal.concrete, pal.ground, 0.5)
	local yellow = Color3.fromRGB(196, 164, 84)
	local white = Color3.fromRGB(214, 220, 230)
	local function road(a: Vector3, b: Vector3, w: number)
		local d = b - a
		local len = d.Magnitude
		local yaw = -math.atan2(d.Z, d.X)
		local mid = (a + b) / 2
		local frame = C(mid) * CFrame.Angles(0, yaw, 0)
		Builder.part(scene, "Field", V(len, 0.1, w), frame * C(0, 0.05, 0), asphalt, { material = "Asphalt", castShadow = false, name = "Road" })
		for _, sz in { -1, 1 } do
			Builder.part(scene, "Field", V(len, 0.45, 1.2), frame * C(0, 0.22, sz * (w / 2 + 0.6)), curb, { material = "Concrete", castShadow = false, name = "Curb" })
			Builder.part(scene, "Field", V(len, 0.03, 0.25), frame * C(0, 0.11, sz * (w / 2 - 0.9)), white, { material = "SmoothPlastic", castShadow = false, name = "EdgeLine" })
		end
		-- dashed yellow centre line, worn away in places
		local n = math.floor(len / 6)
		for i = 0, n - 1 do
			if Util.rand(r) > 0.18 then
				local x = -len / 2 + (i + 0.5) * (len / n)
				Builder.part(scene, "Field", V(3.2, 0.03, 0.4), frame * C(x, 0.11, 0), yellow, { material = "SmoothPlastic", castShadow = false, name = "LaneMark" })
			end
		end
	end
	road(V(-200, 0, -96), V(180, 0, -96), 16)
	road(V(-200, 0, -160), V(180, 0, -160), 16)
	road(V(-64, 0, 10), V(-64, 0, -340), 16)
	road(V(16, 0, 10), V(16, 0, -340), 16)

	-- ruined blocks around the field (at least ~80 studs from the fight).
	-- They sit on the "cityBlocks" channel so a shot can lower them out of
	-- sight (the establishing shot shows nothing but fog).
	type Block = { x: number, z: number, w: number, h: number, d: number, broken: boolean }
	local blocks: { Block } = {
		{ x = -150, z = -60, w = 34, h = 46, d = 28, broken = true },
		{ x = -140, z = -128, w = 30, h = 30, d = 34, broken = false },
		{ x = -152, z = -200, w = 36, h = 58, d = 30, broken = true },
		{ x = -100, z = -255, w = 32, h = 38, d = 28, broken = true },
		{ x = -24, z = -262, w = 40, h = 64, d = 30, broken = false },
		{ x = 52, z = -258, w = 34, h = 42, d = 30, broken = true },
		{ x = 118, z = -232, w = 30, h = 54, d = 34, broken = true },
		{ x = 140, z = -160, w = 32, h = 34, d = 30, broken = false },
		{ x = 136, z = -78, w = 30, h = 48, d = 28, broken = true },
		{ x = 104, z = -20, w = 34, h = 30, d = 28, broken = false },
		{ x = -112, z = 10, w = 30, h = 40, d = 26, broken = true },
		{ x = -200, z = -112, w = 34, h = 70, d = 34, broken = false },
		{ x = 200, z = -120, w = 34, h = 62, d = 34, broken = true },
		{ x = -70, z = -330, w = 46, h = 80, d = 36, broken = false },
		{ x = 60, z = -340, w = 46, h = 90, d = 40, broken = true },
	}
	local center = V(-5, 0, -125)
	local function blockPart(size: Vector3, cf: CFrame, col: Color3, shape: string?, name: string, shadow: boolean?)
		Builder.part(scene, "Field", size, cf, col, { channel = "cityBlocks", shape = shape or "Block", material = if name == "Windows" then "SmoothPlastic" else "Concrete", castShadow = shadow ~= false, name = name })
	end
	for _, b in blocks do
		local col = Util.mix(pal.concrete, pal.concreteDark, Util.randRange(r, 0, 0.7))
		-- face the field: the window side looks at the fight
		local toC = center - V(b.x, 0, b.z)
		local yaw = math.atan2(-toC.X, -toC.Z) + Util.randRange(r, -0.1, 0.1)
		local base = C(b.x, 0, b.z) * CFrame.Angles(0, yaw, 0)
		local top = if b.broken then b.h * 0.72 else b.h
		blockPart(V(b.w, top, b.d), base * C(0, top / 2, 0), col, nil, "Building")
		if b.broken then
			-- the broken upper floors: a jagged stump and a slab hanging off
			blockPart(V(b.w * 0.55, b.h - top, b.d * 0.7), base * C(-b.w * 0.2, top + (b.h - top) / 2, b.d * 0.1), col, nil, "BuildingStump")
			blockPart(V(b.w * 0.5, 1.6, b.d * 0.9), base * C(b.w * 0.3, top + 1.5, 0) * CFrame.Angles(0, 0, math.rad(-24)), pal.concreteDark, nil, "Slab")
		end
		-- glassless window bands on the side facing the field
		for floor = 1, math.floor((top - 4) / 5) do
			blockPart(V(b.w * 0.86, 1.8, 0.2), base * C(0, 2 + floor * 5, -b.d / 2 - 0.05), pal.crack, nil, "Windows", false)
		end
		-- a heap of rubble at the foot
		blockPart(V(b.w * 0.7, 5, 9), base * C(Util.randRange(r, -b.w * 0.2, b.w * 0.2), 0.8, -b.d / 2 - 3) * CFrame.Angles(math.rad(16), math.rad(180), 0), Util.mix(pal.rubble, pal.concrete, 0.3), "Wedge", "RubbleHeap")
	end

	-- bent lamp posts along the roads
	local lamps = { { -56, -80 }, { -72, -170 }, { 24, -84 }, { 8, -176 }, { -110, -104 }, { 70, -104 }, { -120, -152 }, { 92, -168 }, { -56, -230 }, { 24, -240 } }
	for i, l in lamps do
		local lean = Util.randRange(r, -22, 22) * (if i % 3 == 0 then 1.8 else 1)
		local base = C(l[1], 0, l[2]) * CFrame.Angles(math.rad(lean), Util.randRange(r, 0, 6.28), 0)
		Builder.part(scene, "Field", V(0.5, 12, 0.5), base * C(0, 6, 0), pal.concreteDark, { channel = "cityBlocks", shape = "Block", material = "Metal", name = "LampPost" })
		Builder.part(scene, "Field", V(3.2, 0.4, 0.6), base * C(1.3, 12, 0), pal.concreteDark, { channel = "cityBlocks", material = "Metal", name = "LampArm" })
		Builder.part(scene, "Field", V(1.2, 0.35, 0.8), base * C(2.6, 11.7, 0), pal.ice, { channel = "cityBlocks", material = "Glass", name = "Lamp" })
	end

	-- abandoned cars
	local cars = { { -76, -104, 20 }, { 30, -150, -70 }, { -48, -168, 95 }, { -118, -92, 84 }, { 96, -92, -12 } }
	for _, cdef in cars do
		local base = C(cdef[1], 0, cdef[2]) * CFrame.Angles(0, math.rad(cdef[3]), 0)
		local body = Util.mix(pal.rubble, pal.concrete, Util.randRange(r, 0, 1))
		Builder.part(scene, "Field", V(4.4, 1.5, 9.5), base * C(0, 1.25, 0), body, { material = "Metal", name = "Car" })
		Builder.part(scene, "Field", V(4.0, 1.4, 5.0), base * C(0, 2.6, 0.6), body, { material = "Metal", name = "CarCabin" })
		Builder.part(scene, "Field", V(3.9, 0.9, 4.8), base * C(0, 2.7, 0.6), pal.crack, { material = "Glass", name = "CarGlass" })
	end

	-- broken concrete scattered over the deck
	for _ = 1, 34 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local d = Util.randRange(r, 40, 120)
		local p = V(-5 + math.cos(a) * d, 0, -125 + math.sin(a) * d)
		local sz = Util.randRange(r, 1.2, 4)
		Builder.part(scene, "Field", V(sz * 1.5, sz * 0.7, sz), C(p + V(0, sz * 0.25, 0)) * CFrame.Angles(Util.randRange(r, -0.4, 0.4), Util.randRange(r, 0, 6.28), Util.randRange(r, -0.4, 0.4)), Util.mix(pal.concrete, pal.concreteDark, Util.randRange(r, 0, 0.6)), { shape = if math.floor(sz * 10) % 3 == 0 then "Wedge" else "Block", material = "Concrete", name = "Debris" })
	end
end

function Field.build(scene: Builder.Scene)
	local st = scene.style
	local pal = st.color
	Builder.model(scene, "Field", false)
	Builder.model(scene, "Mist", false)
	local r = Util.rng(4242)

	-- concrete deck and patches of newer concrete
	Builder.part(scene, "Field", V(3000, 4, 3000), C(0, -2, -600), pal.ground, { material = st.material.ground, castShadow = false, name = "Ground" })
	for i = 1, 14 do
		local p = V(Util.randRange(r, -90, 80), 0.02, Util.randRange(r, -220, -100))
		local s = V(Util.randRange(r, 20, 60), 0.06, Util.randRange(r, 14, 40))
		Builder.part(scene, "Field", s, C(p) * CFrame.Angles(0, Util.randRange(r, 0, 6.28), 0), Util.mix(pal.ground, pal.concrete, Util.randRange(r, 0.1, 0.45)), { material = "Concrete", castShadow = false, name = "Slab" })
	end
	cracks(scene, r, V(-15, 0, -125), 26, 5, pal.crack)
	cracks(scene, r, V(20, 0, -140), 16, 6, pal.crack)
	-- crater of broken ice and rock in front of Ryu
	local cr = Field.CRATER
	Builder.part(scene, "Field", V(1, 26, 26), C(cr + V(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), pal.rubble, { shape = "Cylinder", material = "Slate", castShadow = false, name = "CraterFloor" })
	rubble(scene, r, cr, 13, 70, 2.2, { pal.rubble, pal.rubbleLight, pal.iceDark }, "Slate")
	rubble(scene, r, cr, 15, 30, 1.6, { pal.concrete, pal.rubbleLight }, "Concrete")
	-- trench carved by Rika's beam (seen from above), curving towards Ryu;
	-- hidden until the beam ploughs it (Field.aftermath)
	local rows = {}
	local floors = {}
	local N = 30
	for i = 0, N do
		local f = i / N
		local p = Field.trenchPoint(f)
		local side = Field.trenchTangent(f):Cross(V(0, 1, 0)).Unit
		local pieces: { TrenchPiece } = {}
		for sgn = -1, 1, 2 do
			local q = p + side * sgn * Util.randRange(r, 2.4, 3.4)
			local sz = Util.randRange(r, 1.0, 2.3)
			local cf = C(q + V(0, sz * 0.25, 0)) * CFrame.Angles(Util.randRange(r, -0.5, 0.5), Util.randRange(r, 0, 6.28), Util.randRange(r, -0.5, 0.5))
			local part = Builder.part(scene, "Field", V(sz * 1.4, sz * 0.7, sz), cf, if i % 2 == 0 then pal.rubble else pal.iceDark, { material = "Slate", fx = true, name = "TrenchRubble" })
			table.insert(pieces, { part = part, cf = cf })
		end
		table.insert(rows, { f = f, pieces = pieces })
		if i < N then
			local part = Builder.part(scene, "Field", V(1, 0.1, 4.4), C(), pal.crack, { material = "Slate", castShadow = false, fx = true, name = "TrenchFloor" })
			table.insert(floors, { f0 = f, f1 = (i + 1) / N, part = part })
		end
	end
	scene.data.trench = { from = Field.TRENCH_FROM, to = Field.TRENCH_TO, ctrl = Field.TRENCH_CTRL, rows = rows, floors = floors } :: Trench

	city(scene)

	-- low concrete parapets along the edges of the deck, fading into the fog
	for _, e in { { V(-104, 0, -130), V(2, 2.4, 300) }, { V(92, 0, -130), V(2, 2.4, 300) }, { V(-6, 0, -282), V(196, 2.4, 2) }, { V(-6, 0, 22), V(196, 2.4, 2) } } do
		Builder.part(scene, "Field", e[2], C(e[1] + V(0, 1.2, 0)), pal.concrete, { channel = "cityBlocks", material = "Concrete", name = "Parapet" })
		Builder.part(scene, "Field", e[2] + V(0.4, -2.2, 0.4), C(e[1] + V(0, 2.5, 0)), pal.concreteDark, { channel = "cityBlocks", material = "Concrete", name = "ParapetCap" })
	end

	-- broken building west of Ryu (behind him in the finale), outside the wide shot
	local b0 = Field.RYU + V(-46, 0, 0)
	for i = 0, 5 do
		local z = -16 + i * 7
		local h = 18 + (i % 3) * 5
		Builder.part(scene, "Field", V(4, h, 5.6), C(b0 + V(0, h / 2, z)), pal.concrete, { material = "Concrete", name = "Ruin" })
		Builder.part(scene, "Field", V(4.4, h * 0.42, 1.4), C(b0 + V(0, h * 0.6, z + 3.5)), pal.concreteDark, { material = "Concrete", name = "RuinWindow" })
	end
	Builder.part(scene, "Field", V(5, 3, 46), C(b0 + V(0, 22, 1.5)) * CFrame.Angles(math.rad(4), 0, 0), pal.concreteDark, { material = "Concrete", name = "RuinBeam" })

	-- mist plates (placed in front of the camera by the shots)
	local mist: { [string]: Builder.PartSpec } = {}
	mist.wisps = mistPlate(scene, "MistWisps", 1600, 900, 11, function(c, rr)
		for _ = 1, 22 do
			local w = Util.randRange(rr, 300, 700)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 80, 880), w, w * Util.randRange(rr, 0.12, 0.25), pal.fogLight, Util.randRange(rr, 0.25, 0.45))
		end
	end)
	mist.low = mistPlate(scene, "MistLow", 1600, 900, 12, function(c, rr)
		for _ = 1, 26 do
			local w = Util.randRange(rr, 320, 760)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 560, 920), w, w * Util.randRange(rr, 0.15, 0.3), pal.fogLight, Util.randRange(rr, 0.4, 0.65))
		end
	end)
	mist.heavy = mistPlate(scene, "MistHeavy", 1600, 900, 13, function(c, rr)
		c:box(0, 0, 1600, 900, pal.fogLight, 0.55)
		for _ = 1, 30 do
			local w = Util.randRange(rr, 300, 800)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 0, 900), w, w * Util.randRange(rr, 0.2, 0.4), Color3.new(1, 1, 1), Util.randRange(rr, 0.3, 0.6))
		end
	end)
	mist.pink = mistPlate(scene, "MistPink", 1600, 900, 14, function(c, rr)
		for _ = 1, 22 do
			local w = Util.randRange(rr, 300, 700)
			c:blob(Util.randRange(rr, 400, 1600), Util.randRange(rr, 100, 800), w, w * Util.randRange(rr, 0.2, 0.4), pal.ePink, Util.randRange(rr, 0.2, 0.4))
		end
		for _ = 1, 14 do
			local w = Util.randRange(rr, 300, 700)
			c:blob(Util.randRange(rr, 0, 1600), Util.randRange(rr, 300, 900), w, w * Util.randRange(rr, 0.15, 0.3), pal.fogLight, Util.randRange(rr, 0.3, 0.5))
		end
	end)
	local snow = Builder.part(scene, "Mist", V(60, 2, 60), C(), Color3.new(1, 1, 1), { transparency = 1, castShadow = false, fx = true, name = "SnowBox" })
	Builder.emitter(scene, "Snow", "snow", snow, Color3.fromRGB(235, 240, 250), 1, 1)
	scene.data.field = { mist = mist, snow = snow } :: Handles
end

-- Put a mist plate in front of the camera so it fills the frame.
-- depth: distance from the camera; drift: sideways motion in studs/s
function Field.mist(ctx: Timeline.Ctx, name: string, depth: number, drift: number?, yShift: number?)
	local h: Handles = ctx.scene.data.field
	local p = h.mist[name]
	local cam = ctx.frame.camera
	local fov = ctx.frame.fov
	local need = 2 * depth * math.tan(math.rad(fov) / 2) * 1.15 -- frame height to cover
	local scale = need / p.size.Y
	local x = (drift or 0) * ctx.t
	ctx:place(p, cam * C(x, (yShift or 0) * need, -depth) * CFrame.Angles(0, math.pi, 0))
	ctx:prop(p, { s = V(p.size.X * scale, p.size.Y * scale, 0.05) })
end

-- How far along the trench Rika's beam has ploughed at time t (0..1)
function Field.trenchProgress(t: number): number
	if t < Field.TRENCH_T0 then
		return 0
	end
	return math.clamp(0.35 + (t - Field.TRENCH_T0) / (Field.TRENCH_T1 - Field.TRENCH_T0) * 0.75, 0, 1)
end

-- Damage to the field that stays once it has happened (runs after every shot)
function Field.aftermath(ctx: Timeline.Ctx)
	-- in part 2 the trench has long been carved
	local p = if ctx.scene.data.part == 2 then 1 else Field.trenchProgress(ctx.t)
	if p <= 0 then
		return
	end
	local tr: Trench = ctx.scene.data.trench
	for _, row in tr.rows do
		if row.f <= p then
			for _, piece in row.pieces do
				ctx:place(piece.part, piece.cf)
			end
		end
	end
	-- the scorched floor follows the curve, segment by segment
	for _, fl in tr.floors do
		if fl.f0 < p then
			local a = Field.trenchPoint(fl.f0)
			local b = Field.trenchPoint(math.min(fl.f1, p))
			local d = b - a
			if d.Magnitude > 0.05 then
				ctx:place(fl.part, C((a + b) / 2 + V(0, 0.05, 0)) * CFrame.Angles(0, -math.atan2(d.Z, d.X), 0))
				ctx:prop(fl.part, { s = V(d.Magnitude + 0.6, 0.1, 4.4) })
			end
		end
	end
end

-- Fine dust drifting around the camera (the reference has no snowfall; the
-- particles stay sparse and slow)
function Field.snow(ctx: Timeline.Ctx, rate: number?)
	local h: Handles = ctx.scene.data.field
	local cam = ctx.frame.camera
	ctx:place(h.snow, C(cam.Position + cam.LookVector * 24 + V(0, 16, 0)))
	ctx:emit("Snow", (rate or 120) * 0.12)
end

return Field
