--!strict
-- Part 4 ("Yuta vs. Ryu end fight scene pt. 4", 44.7 s; the CapCut end card
-- of the reference is left out). The first 5.567 s replay the end of part 3
-- (Scene.build, t4 = t3 - 51.3) and its last close-up holds to 6.533. Then:
-- Yuta holds Ryu in place while the Granite Blast he sent into the sky in
-- part 2 comes back down on Ryu as a pillar of light; the light fades, Yuta
-- lets go (his right forearm charred), the scorched Ryu asks "Was this
-- mine?", a flashback to the deflection, the beam over the evening city,
-- the open sky, and Ryu's grin: "Thank you."
-- Compositions and cut times (read off the frames): docs/part4_frames.md.
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Util)
local Paint = require(script.Parent.Parent.Paint)
local Rig = require(script.Parent.Parent.Rig)
local Cast = require(script.Parent.Cast)
local Clash = require(script.Parent.Clash)
local Common = require(script.Parent.P2.Common)
local Part2 = require(script.Parent.Part2)

local Part4 = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local WHITE = Color3.new(1, 1, 1)
local CYAN = Color3.fromRGB(120, 236, 232)
local BURNT = Color3.fromRGB(96, 58, 42)
local BURNT_DEEP = Color3.fromRGB(54, 32, 24)
local CHAR = Color3.fromRGB(56, 36, 28)
local NAVY = Color3.fromRGB(30, 36, 70)

local RYU = Common.RYU
local YUTA = Common.RYU + V(0.3, 0, -3.2) -- close quarters, as at the end of part 3
local CITY = V(5200, 0, 0) -- the evening city seen from afar
local SKY = V(-5200, 0, 0) -- open ground for the shot straight up into the sky

type Group = { Builder.PartSpec }
type H = {
	core: Builder.PartSpec,
	glow: Builder.PartSpec,
	haze: Builder.PartSpec,
	backdrop: Builder.PartSpec,
	lamp: Builder.PartSpec,
	skyBeam: Builder.PartSpec,
	skyPaint: Builder.PartSpec,
	rocks: Group,
	drops: Group,
	puffs: Group,
	clouds: Group,
	wisps: FX.Burst,
	steam: FX.Burst,
	ryuSkin: Group,
	ryuDeep: Group,
	ryuFur: Group,
	ryuAll: Group,
	ryuLocks: Group,
	yutaArm: Group,
}

local function h4(ctx: Timeline.Ctx): H
	return ctx.scene.data.p4
end

-- a random sequence per item: Park-Miller's first value barely changes
-- between nearby small seeds, so the seed is spread and two values skipped
local function rng(seed: number): Util.Rng
	local r = Util.rng(seed * 7919 + 101)
	Util.rand(r)
	Util.rand(r)
	return r
end

---------------------------------------------------------------------------
-- sets: the evening city with the beam going up, the sky plate
---------------------------------------------------------------------------
local function cityView(scene: Builder.Scene)
	Builder.model(scene, "P4City", false)
	local r = Util.rng(4040)
	local function part(size: Vector3, cf: CFrame, col: Color3, mat: string?, shape: string?, name: string?, transparency: number?)
		Builder.part(scene, "P4City", size, C(CITY) * cf, col, { shape = shape or "Block", material = mat or "Concrete", castShadow = false, name = name or "City", transparency = transparency })
	end
	part(V(5000, 1, 5000), C(0, -0.5, 1200), Color3.fromRGB(24, 28, 44), "SmoothPlastic", nil, "Ground")
	-- low blocks spreading to the horizon (+Z is away from the camera)
	for _ = 1, 280 do
		local z = 80 + (Util.rand(r) ^ 0.75) * 1700
		local x = Util.randRange(r, -1, 1) * (260 + z * 0.95)
		local w = Util.randRange(r, 10, 26) * (0.7 + z / 1800)
		local hgt = Util.randRange(r, 5, 26) * (if Util.rand(r) > 0.93 then 2.6 else 1)
		local col = Util.mix(Color3.fromRGB(30, 36, 58), Color3.fromRGB(66, 76, 108), Util.rand(r))
		part(V(w, hgt, w * Util.randRange(r, 0.6, 1.2)), C(x, hgt / 2, z) * CFrame.Angles(0, Util.randRange(r, -0.3, 0.3), 0), col)
		if Util.rand(r) > 0.4 then
			part(V(w * 0.35, math.max(1.5, hgt * 0.12), 0.4), C(x + Util.randRange(r, -0.2, 0.2) * w, hgt * Util.randRange(r, 0.3, 0.8), z - w * 0.5 - 0.3), Color3.fromRGB(255, 216, 150), "Neon", nil, "Window")
		end
	end
	-- dark hills on the horizon
	for i = 0, 9 do
		local x = -2200 + i * 480 + Util.randRange(r, -90, 90)
		part(V(760, 150 + Util.rand(r) * 90, 380), C(x, 0, 2100), Color3.fromRGB(20, 24, 42), "SmoothPlastic", "Ellipsoid", "Hill")
	end
	-- a band of dusky clouds the beam pierces
	for i = 0, 13 do
		local x = -1500 + i * 230 + Util.randRange(r, -60, 60)
		part(V(420, 34, 260), C(x, 330 + Util.randRange(r, -30, 30), 1500 + Util.randRange(r, -200, 200)), Color3.fromRGB(58, 74, 128), "SmoothPlastic", "Ellipsoid", "Cloud", 0.35)
	end
	-- the beam: a thin line of light straight up, broken near the ground
	local up = CFrame.Angles(0, 0, math.pi / 2)
	local function seg(y0: number, y1: number)
		part(V(y1 - y0, 16, 16), C(140, (y0 + y1) / 2, 1250) * up, Color3.fromRGB(200, 255, 255), "Neon", "Cylinder", "Beam")
		part(V(y1 - y0 + 20, 44, 44), C(140, (y0 + y1) / 2, 1250) * up, CYAN, "Neon", "Cylinder", "BeamGlow", 0.55)
	end
	seg(70, 110)
	seg(130, 175)
	seg(245, 1600)
end

-- The sky straight up (reference 37.0-41.0): a deep saturated blue, darker
-- in the middle, ringed by soft swirling streaks of white cloud, like
-- looking up out of a funnel (canvas px = 1/10 stud, square so it can turn)
local SKY_PX = 1600
local function skyView(scene: Builder.Scene): Builder.PartSpec
	local c = Paint.canvas(1, 0, 0)
	local r = Util.rng(5150)
	Util.rand(r)
	local S = SKY_PX
	local cx, cy = S / 2, S / 2
	c:box(-10, -10, S + 10, S + 10, Color3.fromRGB(44, 98, 214))
	-- lighter towards the edges, darker deep blue in the middle
	for i = 0, 9 do
		local f = i / 9
		c:blob(cx, cy, S * (1.5 - f * 1.1), S * (1.5 - f * 1.1), Util.mix(Color3.fromRGB(110, 156, 236), Color3.fromRGB(28, 70, 190), f), 0.55, 2)
	end
	-- soft streaks of cloud swirling round the opening, three layers each
	-- a streak bends along the ring: four short soft pills following the arc
	local function wisp(a: number, rad: number, len: number, thick: number, alpha: number)
		local span = len / rad
		local drift = Util.randRange(r, -0.08, 0.08)
		for k = 0, 3 do
			local f = (k + 0.5) / 4
			local aa = a + (f - 0.5) * span
			local rr = rad * (1 + drift * (f - 0.5))
			local x, y = cx + math.cos(aa) * rr, cy + math.sin(aa) * rr
			local rot = math.deg(aa) + 90
			local taper = math.sin(f * math.pi)
			local l = len / 4 * 1.5
			c:pill(x, y, l * 1.2, thick * 3.2 * taper + 4, rot, Color3.fromRGB(190, 210, 246), 1 - alpha * 0.18)
			c:pill(x, y, l, thick * 1.6 * taper + 2, rot, Color3.fromRGB(220, 231, 252), 1 - alpha * 0.32)
			c:pill(x, y, l * 0.8, thick * 0.6 * taper + 1, rot, Color3.fromRGB(246, 249, 255), 1 - alpha * 0.5)
		end
	end
	for _ = 1, 70 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local rad = Util.randRange(r, 520, 800)
		wisp(a, rad, Util.randRange(r, 160, 420), Util.randRange(r, 10, 26), Util.randRange(r, 0.5, 1))
	end
	for _ = 1, 26 do
		local a = Util.randRange(r, 0, math.pi * 2)
		local rad = Util.randRange(r, 380, 520)
		wisp(a, rad, Util.randRange(r, 80, 200), Util.randRange(r, 5, 12), Util.randRange(r, 0.3, 0.6))
	end
	Builder.model(scene, "P4Sky", false)
	return Builder.part(scene, "P4Sky", V(S / 10, S / 10, 0.05), C(), Color3.new(1, 1, 1), {
		fx = true,
		castShadow = false,
		name = "SkyPaint",
		gui = { face = "Front", canvas = Vector2.new(S, S), lightInfluence = 0, elems = c.elems },
	})
end

function Part4.build(scene: Builder.Scene)
	local pal = scene.style.color
	local function fx(model: string, shape: string, col: Color3, mat: string, tr: number, name: string): Builder.PartSpec
		return Builder.fx(scene, model, shape, V(1, 1, 1), col, mat, tr, name)
	end
	local skyPaint = skyView(scene)
	local h: H = {
		core = fx("P4Pillar", "Cylinder", Color3.fromRGB(246, 255, 255), "Neon", 0, "PillarCore"),
		glow = fx("P4Pillar", "Cylinder", CYAN, "Neon", 0.4, "PillarGlow"),
		haze = fx("P4Pillar", "Cylinder", CYAN, "Neon", 0.75, "PillarHaze"),
		backdrop = fx("P4Backdrop", "Block", CYAN, "Neon", 0, "Backdrop"),
		lamp = fx("P4Lamp", "Ball", WHITE, "SmoothPlastic", 1, "Lamp"),
		skyBeam = fx("P4SkyBeam", "Cylinder", CYAN, "Neon", 0, "SkyBeam"),
		skyPaint = skyPaint,
		rocks = {},
		drops = {},
		puffs = {},
		clouds = {},
		wisps = FX.burst(scene, "P4Wisps", Color3.fromRGB(46, 36, 32), 14, "Ball", 91),
		steam = FX.burst(scene, "P4Steam", Color3.fromRGB(236, 238, 242), 12, "Ball", 92),
		ryuSkin = {},
		ryuDeep = {},
		ryuFur = {},
		ryuAll = {},
		ryuLocks = {},
		yutaArm = {},
	}
	Builder.light(scene, "P4Lamp", "Point", h.lamp, WHITE, 40)
	for _, p in h.wisps.parts do
		p.material = "SmoothPlastic"
		p.color = Color3.fromRGB(46, 36, 32)
	end
	for _, p in h.steam.parts do
		p.material = "SmoothPlastic"
	end
	for i = 1, 24 do
		h.rocks[i] = fx("P4Rocks", "Block", Color3.fromRGB(30, 32, 46), "Concrete", 0, "Rock")
	end
	for i = 1, 18 do
		h.drops[i] = fx("P4Drops", "Ball", Color3.fromRGB(240, 252, 255), "Neon", 0, "Drop")
	end
	for i = 1, 30 do
		h.puffs[i] = fx("P4Puffs", "Ellipsoid", Color3.fromRGB(220, 206, 184), "SmoothPlastic", 0.3, "Puff")
	end
	for i = 1, 30 do
		h.clouds[i] = fx("P4Clouds", "Ellipsoid", Color3.fromRGB(236, 242, 252), "Neon", 0.2, "Cloud")
	end
	cityView(scene)
	for _, p in scene.parts do
		if p.rig == "RyuLoose" then
			table.insert(h.ryuAll, p)
			if p.color == pal.rSkin then
				table.insert(h.ryuSkin, p)
			elseif p.color == pal.rSkinDeep then
				table.insert(h.ryuDeep, p)
			elseif p.color == pal.rFur or p.color == pal.rFurShade then
				table.insert(h.ryuFur, p)
			end
			if p.bone == "Head" and p.name == "Lock" and p.cf.Position.Z < -0.3 then
				table.insert(h.ryuLocks, p)
			end
		elseif p.rig == "Yuta" and (p.bone == "RightLowerArm" or p.bone == "RightHand") then
			table.insert(h.yutaArm, p)
		end
	end
	scene.data.p4 = h
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function field(ctx: Timeline.Ctx, mist: string?)
	Common.sky(ctx, mist or "wisps", 30)
end

local function grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	Common.grade(ctx, b, c, s, tint)
end

local function cam(ctx: Timeline.Ctx, eye: Vector3, target: Vector3, fov: number, amp: number?, dof: number?, up: Vector3?)
	local cf = Util.lookAt(eye, target, up)
	if amp and amp > 0 then
		cf = Clash.shake(cf, ctx.t, amp, 16)
	end
	ctx:camera(cf, fov)
	ctx:focus((target - eye).Magnitude, dof or 1)
end

local function yutaRoot(): CFrame
	return C(YUTA) * CFrame.Angles(0, math.pi, 0)
end

local function recolor(ctx: Timeline.Ctx, list: Group, col: Color3)
	for _, p in list do
		ctx:prop(p, { c = col })
	end
end

-- Ryu scorched by his own blast (skin, soot on the face, singed fur)
local function scorched(ctx: Timeline.Ctx)
	local h = h4(ctx)
	recolor(ctx, h.ryuSkin, BURNT)
	recolor(ctx, h.ryuDeep, BURNT_DEEP)
	for _, p in h.ryuFur do
		ctx:prop(p, { c = Util.mix(p.color, Color3.fromRGB(150, 134, 112), 0.5) })
	end
	ctx:show("ryu:burnt")
end

-- Yuta's right forearm and hand burnt black-brown (held Ryu in the beam)
local function charredArm(ctx: Timeline.Ctx)
	for i, p in h4(ctx).yutaArm do
		ctx:prop(p, { c = Util.mix(CHAR, Color3.fromRGB(110, 66, 46), (i % 3) * 0.2) })
	end
end

-- a dark figure against the light
local function silhouette(ctx: Timeline.Ctx, col: Color3)
	recolor(ctx, h4(ctx).ryuAll, col)
end

-- the pillar of light from the sky onto Ryu, its lower end at height `bottom`
local function pillar(ctx: Timeline.Ctx, bottom: number, k: number, axis: Vector3?)
	local h = h4(ctx)
	local top = 1200
	local base = axis or RYU
	local function column(p: Builder.PartSpec, radius: number)
		local hgt = top - bottom
		ctx:place(p, C(base + V(0, bottom + hgt / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2))
		ctx:prop(p, { s = V(hgt, radius * 2 * k, radius * 2 * k) })
	end
	column(h.core, 3.4)
	column(h.glow, 6)
	column(h.haze, 10)
end

-- a big glowing wall behind a subject (the light filling the background)
local function backdrop(ctx: Timeline.Ctx, at: Vector3, facing: Vector3, col: Color3)
	local h = h4(ctx)
	ctx:place(h.backdrop, Util.lookAt(at, at + facing))
	ctx:prop(h.backdrop, { s = V(400, 400, 1), c = col })
end

-- dark lumps of concrete floating slowly up round a point
local function rocksRise(ctx: Timeline.Ctx, center: Vector3, t0: number, radius: number, speed: number, size: number)
	for i, p in h4(ctx).rocks do
		local rr = rng(4100 + i * 7)
		local a = Util.randRange(rr, 0, math.pi * 2)
		local d = Util.randRange(rr, 2.5, radius)
		local y = Util.randRange(rr, 0, 2) + math.max(0, ctx.t - t0) * speed * Util.randRange(rr, 0.5, 1.4)
		local s = size * Util.randRange(rr, 0.4, 1.6)
		ctx:place(p, C(center + V(math.cos(a) * d, y, math.sin(a) * d)) * CFrame.Angles(ctx.t * Util.randRange(rr, -1, 1) + i, i, ctx.t * 0.4))
		ctx:prop(p, { s = V(s, s * 0.6, s * 0.9) })
	end
end

-- glowing droplets / sparks hanging or rising round a point
local function drops(ctx: Timeline.Ctx, center: Vector3, spread: number, rise: number, size: number)
	for i, p in h4(ctx).drops do
		local rr = rng(4200 + i * 11)
		local ph = (ctx.lt * rise * Util.randRange(rr, 0.6, 1.4) + Util.rand(rr)) % 1
		local off = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1), Util.randRange(rr, -1, 1)) * spread
		ctx:place(p, C(center + off + V(0, (ph - 0.5) * spread * 1.4, 0)))
		local s = size * Util.randRange(rr, 0.5, 1.3)
		ctx:prop(p, { s = V(s, s * (1 + rise * 2), s) })
	end
end

-- soft clouds of smoke / steam drifting along `flow`
local function puffs(ctx: Timeline.Ctx, center: Vector3, spread: Vector3, flow: Vector3, size: number, col: Color3, alpha: number, seed: number)
	for i, p in h4(ctx).puffs do
		local rr = rng(seed + i * 13)
		local ph = (ctx.lt * Util.randRange(rr, 0.08, 0.16) + Util.rand(rr)) % 1
		local off = V(Util.randRange(rr, -1, 1) * spread.X, Util.randRange(rr, -1, 1) * spread.Y, Util.randRange(rr, -1, 1) * spread.Z)
		local s = size * Util.randRange(rr, 0.6, 1.5)
		ctx:place(p, C(center + off + flow * (ph - 0.5)) * CFrame.Angles(0, i, 0))
		ctx:prop(p, { s = V(s * 1.6, s * 0.8, s * 1.2), c = col, t = alpha + (1 - alpha) * (math.abs(ph - 0.5) * 2) ^ 3 })
	end
end

-- the two of them on the deck: Yuta gripping Ryu's collar with both hands
local function holdPair(ctx: Timeline.Ctx, lookUp: number, blood: boolean): ({ [string]: CFrame }, { [string]: CFrame })
	local t = ctx.t
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		LowerTorso = R(-4, 0, 0),
		UpperTorso = R(-10 + lookUp * 10, 0, 0),
		Head = R(-12 + lookUp * 52, 0, 0),
		RightUpperArm = R(30, 0, 24),
		RightLowerArm = R(60, 0, 0),
		LeftUpperArm = R(34, 0, -24),
		LeftLowerArm = R(64, 0, 0),
		LeftUpperLeg = R(10, 0, -6),
		LeftLowerLeg = R(-10, 0, 0),
		RightUpperLeg = R(-6, 0, 6),
	}, t))
	local collar = (rb.UpperTorso * C(0, 1.35, -0.62)).Position
	local yb = Common.rigAt(ctx, "Yuta", yutaRoot(), Cast.alive({
		LowerTorso = R(-6, 0, 0),
		UpperTorso = R(-14 + lookUp * 8, 0, 0),
		Head = R(-8 + lookUp * 52, 0, 0),
		RightUpperArm = R(84, 0, 8),
		RightLowerArm = R(26, 0, 0),
		LeftUpperArm = R(84, 0, -8),
		LeftLowerArm = R(26, 0, 0),
		LeftUpperLeg = R(26, 0, -6),
		LeftLowerLeg = R(-22, 0, 0),
		RightUpperLeg = R(-16, 0, 6),
	}, t), "RightHand", C(0, -0.35, 0), collar + V(-0.25, 0, -0.1))
	Cast.expr(ctx, "ryu", if lookUp > 0.5 then "shock" else "grit")
	Cast.expr(ctx, "yuta", "cold")
	if blood then
		ctx:show("ryu:blood")
	end
	ctx:show("yuta:blood")
	return rb, yb
end

---------------------------------------------------------------------------
-- shots
---------------------------------------------------------------------------

-- 6.533: from above, the two of them on the cracked deck, Yuta gripping
-- Ryu; 6.667 a burst of mist, wider: lumps of concrete float up round them;
-- 7.2 both look straight up
local function holdWide(ctx: Timeline.Ctx)
	local t = ctx.t
	local look = Util.smoothstep(7.15, 7.6, t)
	holdPair(ctx, look, true)
	local mid = (RYU + YUTA) / 2
	if t < 6.667 then
		cam(ctx, mid + V(-14, 21, -14), mid + V(0, 1.6, 0), 40, 0.05, 0.3)
	else
		rocksRise(ctx, mid, 6.667, 12, 0.9, 0.9)
		cam(ctx, mid + V(-17, 8.5, -14), mid + V(0, 2.6, 0), 38, 0.05, 0.3)
		local mist = 1 - Util.smoothstep(6.667, 6.95, t)
		if mist > 0 then
			ctx:flash(Color3.fromRGB(196, 212, 240), 0.75 * mist)
		end
	end
	ctx:wind(1.4)
	grade(ctx, -0.04, 0.16, -0.1, Color3.fromRGB(196, 210, 250))
	field(ctx, "low")
end

-- straight down from far above, through blue haze: the deck, the city, the
-- two of them a dark speck in the middle; `h0` -> `h1` the camera height
local function topView(ctx: Timeline.Ctx, h0: number, h1: number, dive: number)
	local t = ctx.t
	holdPair(ctx, 1, true)
	local hgt = h0 + (h1 - h0) * (if dive > 0 then ctx.u ^ 2 else Util.smoothstep(0, 1, ctx.u))
	local up = V(math.sin(0.5), 0, math.cos(0.5))
	cam(ctx, RYU + V(0, hgt, 0.01), RYU, 42, 0, 0, up)
	-- haze drifting between the camera and the ground
	puffs(ctx, RYU + V(0, hgt * 0.4, 0), V(hgt * 0.55, hgt * 0.2, hgt * 0.55), V(hgt * 0.2, 0, 0), hgt * 0.16, Color3.fromRGB(150, 172, 236), 0.7, 4300)
	if dive > 0 then
		-- the light coming down round them
		ctx:alpha("speed", 0.08 * dive)
		ctx:place(h4(ctx).lamp, C(RYU + V(0, 20, 0)))
		ctx:light("P4Lamp", 6 * dive, CYAN, 80)
	end
	ctx:fog(0.45)
	ctx:wind(1.2)
	grade(ctx, -0.02, 0.14, -0.05, Color3.fromRGB(160, 182, 255))
	local _ = t
end

local function top1(ctx: Timeline.Ctx)
	topView(ctx, 360, 310, 0)
end
local function top2(ctx: Timeline.Ctx)
	topView(ctx, 230, 190, 0)
end
local function top3(ctx: Timeline.Ctx)
	topView(ctx, 150, 26, 1)
end

-- 8.933: Ryu's profile, facing left, looking up: blood down his face, glowing
-- droplets hanging round him; "What?!" (his eye widens, his lips part)
local function ryuProfile(ctx: Timeline.Ctx)
	local t = ctx.t
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(2, 0, 0), Head = R(16, 4, 0) }, t))
	Cast.expr(ctx, "ryu", if t < 9.3 then "shock" else "gasp")
	ctx:show("ryu:blood")
	local head = (rb.Head * C(0, 0.75, -0.2)).Position
	drops(ctx, head + V(0, 0.2, -0.8), 1.4, 0.06, 0.06)
	ctx:place(h4(ctx).lamp, C(head + V(-1.5, 3, -1)))
	ctx:light("P4Lamp", 2.5, Color3.fromRGB(200, 240, 255), 14)
	cam(ctx, head + V(-1.9, -0.15, -1.55), head + V(-0.1, 0.05, -0.3), 36, 0.02, 1)
	ctx:wind(1.2)
	grade(ctx, -0.16, 0.3, 0.05, Color3.fromRGB(176, 196, 255))
	ctx:fog(0.6)
end

-- 10.533: right on Ryu's eye, looking up ("What is he after?!", voice-over)
local function ryuEye(ctx: Timeline.Ctx)
	local t = ctx.t
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(2, 0, 0), Head = R(14, 0, 0) }, t))
	Cast.expr(ctx, "ryu", "shock")
	ctx:show("ryu:blood")
	for _, p in h4(ctx).ryuLocks do
		ctx:prop(p, { t = 1 })
	end
	local eye = (rb.Head * C(-0.17, 0.86, -0.56)).Position
	local push = Util.smoothstep(10.533, 11.367, t)
	cam(ctx, eye + rb.Head.LookVector * (1.1 - push * 0.15) - rb.Head.UpVector * 0.05, eye, 17, 0.01, 1)
	ctx:place(h4(ctx).lamp, C(eye + V(0, 3, -2)))
	ctx:light("P4Lamp", 2, Color3.fromRGB(200, 240, 255), 10)
	grade(ctx, -0.08, 0.28, 0.05, Color3.fromRGB(196, 210, 255))
	ctx:fog(0.4)
end

-- 12.133: straight down on them, close: Ryu's face turned up at us, eyes
-- wide, mouth wide open, his hands clamped on Yuta's arm; Yuta at the bottom
-- left pushes himself off and away
local function topClose(ctx: Timeline.Ctx)
	local t = ctx.t
	local off = Util.smoothstep(12.36, 12.5, t)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(18, 0, 0),
		Head = R(52, 0, 0),
		RightUpperArm = R(80, 0, -10),
		RightLowerArm = R(50, 0, 0),
		LeftUpperArm = R(70, 0, 10),
		LeftLowerArm = R(60, 0, 0),
	}, t))
	Cast.expr(ctx, "ryu", "shout")
	ctx:show("ryu:blood")
	ctx:rig("Yuta", C(YUTA + V(0, off * 0.6, -off * 2.5)) * CFrame.Angles(0, math.pi, 0), Cast.alive({
		UpperTorso = R(-30, 0, 0),
		Head = R(-20, 0, 0),
		RightUpperArm = R(90 - off * 60, 0, 10),
		RightLowerArm = R(20, 0, 0),
		LeftUpperArm = R(80, 0, -10),
		LeftLowerArm = R(30, 0, 0),
		LeftUpperLeg = R(40, 0, 0),
		LeftLowerLeg = R(-60, 0, 0),
		RightUpperLeg = R(-10, 0, 0),
	}, t))
	ctx:show("yuta:blood")
	local face = (rb.Head * C(0, 0.75, -0.5)).Position
	cam(ctx, face + V(0.3, 4.8, -0.6), face + V(0.3, 0, -1.0), 50, 0.12, 0.5, V(-1, 0, 1))
	ctx:place(h4(ctx).lamp, C(face + V(0, 5, 0)))
	ctx:light("P4Lamp", 3, CYAN, 20)
	ctx:gust(1.5)
	grade(ctx, -0.02, 0.24, 0.08, Color3.fromRGB(176, 196, 255))
	ctx:fog(0.6)
end

-- 12.5: from the side: the deck, the two small figures, the pillar of light
-- coming down out of the sky; 12.633 it hits (a flash)
local function pillarFalls(ctx: Timeline.Ctx)
	local t = ctx.t
	local k = Util.smoothstep(12.5, 12.633, t)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ Head = R(40, 0, 0), RightUpperArm = R(150, 0, 10), RightLowerArm = R(20, 0, 0) }, t))
	local _ = rb
	ctx:rig("Yuta", C(YUTA + V(0, 1.2 * math.sin(k * math.pi), -5 * k)) * CFrame.Angles(0, math.pi, 0), Cast.run(t * 2, 30))
	pillar(ctx, 22 * (1 - k), 0.1 + 0.9 * k)
	cam(ctx, RYU + V(6, 3.0, -52), RYU + V(0, 11, 0), 40, 0, 0)
	if t >= 12.633 then
		ctx:flash(Color3.fromRGB(220, 255, 255), 0.85)
	end
	ctx:bloom(1.6)
	grade(ctx, -0.08, 0.16, -0.1, Color3.fromRGB(176, 196, 250))
	field(ctx, "low")
end

-- Ryu on one knee inside the light, arms out, head thrown back
local KNEEL: Rig.Pose = {
	HumanoidRootPart = C(0, -1.25, 0),
	LowerTorso = R(-6, 0, 0),
	UpperTorso = R(18, 0, 0),
	Head = R(36, 0, 0),
	RightUpperArm = R(30, 0, 62),
	RightLowerArm = R(70, 0, 0),
	LeftUpperArm = R(30, 0, -62),
	LeftLowerArm = R(70, 0, 0),
	LeftUpperLeg = R(90, 0, -4),
	LeftLowerLeg = R(-90, 0, 0),
	RightUpperLeg = R(8, 0, 6),
	RightLowerLeg = R(-100, 0, 0),
}

-- 12.7: low and wide: the vast white pillar, Ryu's dark figure kneeling in
-- it, black lumps of concrete floating up, the edges of the frame black
local function pillarWide(ctx: Timeline.Ctx)
	local t = ctx.t
	ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.add(KNEEL, "Head", R(math.sin(t * 9) * 4, 0, 0)), t))
	silhouette(ctx, NAVY)
	local eye = RYU + V(6, 1.4, -34)
	local away = (RYU - eye) * V(1, 0, 1)
	pillar(ctx, 0, 1, RYU + away.Unit * 4.2)
	rocksRise(ctx, RYU, 12.7, 16, 2.2, 1.3)
	ctx:alpha("p4edges", 1)
	ctx:place(h4(ctx).lamp, C(RYU + V(0, 6, 8)))
	ctx:light("P4Lamp", 8, CYAN, 90)
	cam(ctx, eye, RYU + V(0, 8.5, 0), 52, 0.12, 0)
	ctx:bloom(2.2)
	ctx:gust(2)
	grade(ctx, -0.05, 0.4, 0.1, Color3.fromRGB(196, 250, 255))
	ctx:fog(0.5)
end

-- 14.567: behind Ryu in the stream of light: a dark figure, arms bent out
-- to the sides, his head jerked back again and again, sparks rushing up
local function ryuBack(ctx: Timeline.Ctx)
	local t = ctx.t
	local jerk = math.max(0, math.sin(t * 7)) ^ 3 * 18
	ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(14, 0, 0),
		Head = R(30 + jerk, 0, 0),
		RightUpperArm = R(40, 0, 70),
		RightLowerArm = R(80, 0, 0),
		LeftUpperArm = R(40, 0, -70),
		LeftLowerArm = R(80, 0, 0),
	}, t))
	silhouette(ctx, Color3.fromRGB(26, 28, 66))
	backdrop(ctx, RYU + V(0, 6, -26), V(0, 0, 1), Color3.fromRGB(110, 236, 236))
	drops(ctx, RYU + V(0, 6, -1.5), 3.5, 0.9, 0.12)
	cam(ctx, RYU + V(0.5, 4.4, 4.6), RYU + V(0, 5.6, -1.5), 50, 0.15, 0.5)
	ctx:gust(3)
	ctx:wind(2.5)
	ctx:bloom(0.5)
	grade(ctx, 0, 0.3, 0.1, Color3.fromRGB(210, 255, 255))
	ctx:fog(0)
end

-- 15.9: close on Ryu in the light: head flung back, eyes screwed shut,
-- mouth wide open in a scream, hair and fur thrashing upward; 17.3 a blur
local function ryuScream(ctx: Timeline.Ctx)
	local t = ctx.t
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({
		UpperTorso = R(16, 0, 0),
		Head = R(40 + math.sin(t * 13) * 3, 8, 6),
		RightUpperArm = R(40, 0, 60),
		RightLowerArm = R(70, 0, 0),
		LeftUpperArm = R(40, 0, -60),
		LeftLowerArm = R(70, 0, 0),
	}, t))
	Cast.expr(ctx, "ryu", "scream")
	Cast.furLow(ctx, "RyuLoose", 0.8)
	local h = h4(ctx)
	recolor(ctx, h.ryuSkin, Color3.fromRGB(70, 82, 130))
	recolor(ctx, h.ryuDeep, Color3.fromRGB(44, 52, 96))
	recolor(ctx, h.ryuFur, Color3.fromRGB(176, 200, 240))
	local head = (rb.Head * C(0, 0.75, 0)).Position
	backdrop(ctx, RYU + V(0, 6, 20), V(0, 0, -1), Color3.fromRGB(110, 236, 236))
	drops(ctx, head + V(0, 0, 1.5), 3, 1.2, 0.1)
	local blur = Util.smoothstep(17.25, 17.6, t)
	cam(ctx, head + V(0.5, 1.4, -2.9), head + V(0, -0.1, 0), 46, 0.2, 1)
	if blur > 0 then
		ctx:focus(0.5, 1)
		ctx:flash(Color3.fromRGB(120, 236, 236), blur * 0.7)
	end
	ctx:gust(3.5)
	ctx:wind(3)
	ctx:bloom(0.6)
	grade(ctx, 0, 0.3, 0.05, Color3.fromRGB(200, 240, 255))
	ctx:fog(0)
end

-- 17.6: a white cone of light on cyan (2D frame)
local function cone(ctx: Timeline.Ctx)
	backdrop(ctx, RYU + V(0, 6, 20), V(0, 0, -1), CYAN)
	cam(ctx, RYU + V(0, 6, 0), RYU + V(0, 6, 10), 50, 0, 0)
	ctx:show("p4cone")
	ctx:fog(0)
end

-- 18.9: cyan glare, then wide on the deck washed in cyan light, a wall of
-- cyan smoke behind, the buildings over it against a white sky, the two
-- small figures standing in the middle
local function cyanWide(ctx: Timeline.Ctx)
	local t = ctx.t
	holdPair(ctx, 0.9, false)
	scorched(ctx)
	charredArm(ctx)
	puffs(ctx, RYU + V(0, 5, 22), V(60, 4, 6), V(10, 0, 0), 12, Color3.fromRGB(110, 230, 226), 0.05, 4400)
	cam(ctx, RYU + V(-2, 2.6, -46), RYU + V(0, 7, 0), 46, 0.02, 0)
	ctx:place(h4(ctx).lamp, C(RYU + V(0, 12, 0)))
	ctx:light("P4Lamp", 4, CYAN, 70)
	local glare = 1 - Util.smoothstep(19.1, 19.4, t)
	if glare > 0 then
		ctx:flash(Color3.fromRGB(110, 236, 236), glare)
	end
	ctx:bloom(1.6)
	grade(ctx, 0.25, 0.1, 0.25, Color3.fromRGB(150, 255, 245))
	ctx:fog(1.2)
end

-- 20.7: white haze; 20.8 the same view in daylight: beige smoke settling and
-- blowing off to the right, the city, the two of them standing
local function hazeLifts(ctx: Timeline.Ctx)
	local t = ctx.t
	holdPair(ctx, 0.9, false)
	scorched(ctx)
	charredArm(ctx)
	local thin = Util.smoothstep(20.8, 23.1, t)
	puffs(ctx, RYU + V(8 * thin, 4 - thin * 2, 18), V(60, 4, 10), V(16, 0, 0), 12 - thin * 4, Color3.fromRGB(214, 198, 172), 0.2 + thin * 0.5, 4500)
	cam(ctx, RYU + V(-2, 2.6, -46), RYU + V(0, 7, 0), 46, 0, 0)
	if t < 20.8 then
		ctx:flash(Color3.fromRGB(236, 240, 244), 0.9)
	end
	grade(ctx, 0.02, 0.14, 0, Color3.fromRGB(226, 228, 240))
	field(ctx, "low")
end

-- 23.167: side on (Yuta left, Ryu right): Yuta's hand lets go of the collar
-- and drops, he steps back; Ryu stays standing, head thrown back, arms
-- hanging; pale smoke curls past
local function letGo(ctx: Timeline.Ctx)
	local t = ctx.t
	local release = Util.smoothstep(23.75, 24.25, t)
	local step = Util.smoothstep(24.0, 24.7, t)
	local sway = math.sin(t * 1.3) * 2
	local rb = ctx:rig("RyuLoose", C(RYU) * CFrame.Angles(0, math.rad(15), 0), Cast.alive({
		UpperTorso = R(8 + sway, 0, 0),
		Head = R(38, 6, 0),
		RightUpperArm = R(4, 0, 8),
		RightLowerArm = R(10, 0, 0),
		LeftUpperArm = R(4, 0, -8),
		LeftLowerArm = R(10, 0, 0),
	}, t))
	scorched(ctx)
	Cast.furLow(ctx, "RyuLoose", 0.6)
	Cast.expr(ctx, "ryu", "dazed")
	local collar = (rb.UpperTorso * C(0, 1.35, -0.62)).Position
	local yp: Rig.Pose = {
		UpperTorso = R(-4 + step * 4, 0, 0),
		Head = R(-6, 0, 0),
		LeftUpperArm = R(80 * (1 - release), 0, -6),
		LeftLowerArm = R(20 * (1 - release), 0, 0),
		RightUpperArm = R(6, 0, 8),
		RightLowerArm = R(30, 0, 0),
		RightHand = R(20, 0, 0),
		LeftUpperLeg = R(-16 * step, 0, 0),
		RightUpperLeg = R(10 * step, 0, 0),
	}
	local yroot = C(YUTA + V(0, 0, -0.8 * step)) * CFrame.Angles(0, math.pi, 0)
	if release < 0.05 then
		Common.rigAt(ctx, "Yuta", yroot, Cast.alive(yp, t), "LeftHand", C(0, -0.35, 0), collar)
	else
		ctx:rig("Yuta", yroot, Cast.alive(yp, t))
	end
	Cast.expr(ctx, "yuta", "cold")
	ctx:show("yuta:blood")
	charredArm(ctx)
	local mid = (RYU + YUTA) / 2 + V(0, 3.3, 0)
	puffs(ctx, mid + V(-2.5, -2.2, 0), V(1, 1, 6), V(0, 0, 14), 0.8, Color3.fromRGB(226, 216, 196), 0.8, 4600)
	cam(ctx, mid + V(-9, 0.2, 0.3), mid + V(0, 0, 0.3), 44, 0, 0.6)
	ctx:wind(1.4)
	grade(ctx, 0.02, 0.16, 0, Color3.fromRGB(220, 226, 245))
	field(ctx, "low")
end

-- 25.6: Yuta's right forearm and hand, charred from the elbow down, fingers
-- half curled, a thin dark smoke rising off them
local function burntArm(ctx: Timeline.Ctx)
	local t = ctx.t
	local yb = ctx:rig("Yuta", C(YUTA + V(0, 0, -0.8)) * CFrame.Angles(0, math.pi, 0), Cast.alive({
		RightUpperArm = R(6, 0, 8),
		RightLowerArm = R(28, 0, 0),
		RightHand = R(24, 0, 0),
	}, t))
	ctx:show("yuta:blood")
	charredArm(ctx)
	local arm = (yb.RightLowerArm * C(0, -0.45, 0)).Position
	FX.placeBurst(ctx, h4(ctx).wisps, arm + V(0, 0.3, 0), (t * 0.7) % 1.4, 0.9, 0.22, 1.4, V(0, 1, 0), 0.35, -0.8)
	cam(ctx, arm + V(-2.3, 0.6, 0.5), arm + V(0, 0.45, 0), 44, 0, 1)
	ctx:wind(1.1)
	grade(ctx, -0.02, 0.18, -0.05, Color3.fromRGB(226, 220, 214))
	field(ctx, "low")
end

-- 27.833: Ryu's head thrown back, in profile facing left, his face burnt
-- dark, white steam drifting from his mouth; "Was this mine?" (his lips
-- barely move)
local function wasThisMine(ctx: Timeline.Ctx)
	local t = ctx.t
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(12, 0, 0), Head = R(58, -6, 0) }, t))
	scorched(ctx)
	Cast.furLow(ctx, "RyuLoose", 1)
	local speaking = t >= 28.833 and t < 31.433
	Cast.expr(ctx, "ryu", if speaking and Util.noise1(t * 5, 3) > 0.25 then "dazedTalk" else "dazed")
	local head = rb.Head * C(0, 0.75, 0)
	local mouth = (rb.Head * C(0, 0.42, -0.62)).Position
	-- his breath: soft white puffs of steam rising from his open mouth
	puffs(ctx, mouth + V(0, 0.4, 0) + rb.Head.LookVector * 0.15, V(0.14, 0.26, 0.14), V(0, 0.8, 0), 0.2, Color3.fromRGB(248, 248, 252), 0.3, 4900)
	-- three-quarter from his left, the collar (pressed down) below the chin
	cam(ctx, head.Position + V(-2.1, 0.9, -2.3), head.Position + V(0, 0.35, -0.3), 38, 0, 1)
	ctx:wind(1.2)
	grade(ctx, -0.02, 0.18, -0.05, Color3.fromRGB(222, 226, 240))
	field(ctx, "low")
end

-- 31.567: flashback to part 2: the deflection, from behind Ryu's legs, in
-- the dark: Yuta low at the right with his hand up in the stream, the blast
-- flung up into the sky (part 2's own shot replayed slower, new camera)
local deflect: Timeline.Shot? = nil
for _, s in Part2.shots do
	if s.id == "P2 28 deflect" then
		deflect = s
	end
end
local function flashback(ctx: Timeline.Ctx)
	local t = ctx.t
	local s = deflect
	if s then
		local p2t = 39.4 + (t - 31.567) / (33.9 - 31.567) * 0.62
		local inner = Timeline.context(ctx.scene, p2t, s)
		inner.frame = ctx.frame
		s.run(inner)
	end
	cam(ctx, Common.RYU + V(2.4, 1.1, 3.4), Common.YUTA + V(-0.6, 2.4, 0), 28, 0.05, 1)
	ctx:focus(26, 1)
	grade(ctx, -0.24, 0.32, -0.2, Color3.fromRGB(150, 168, 230))
	local fade = Util.smoothstep(33.3, 33.9, t)
	if fade > 0 then
		ctx:flash(Color3.fromRGB(150, 220, 236), fade * 0.55)
	end
end

-- 33.9: the evening city from afar, a thin line of cyan light going
-- straight up through the clouds ("In that instant...")
local function cityBeam(ctx: Timeline.Ctx)
	local t = ctx.t
	local drift = (t - 33.9) * 1.5
	cam(ctx, CITY + V(drift, 120, -120), CITY + V(130 + drift * 0.5, 260, 1250), 46, 0, 0)
	ctx:fog(0.12)
	ctx:wind(0)
	ctx:bloom(1.8)
	grade(ctx, -0.16, 0.28, 0.15, Color3.fromRGB(140, 168, 255))
	local fade = 1 - Util.smoothstep(33.9, 34.3, t)
	if fade > 0 then
		ctx:flash(Color3.fromRGB(150, 220, 236), fade * 0.5)
	end
end

-- 37.0: straight up into the sky: a round window of blue among drifting
-- clouds; the line of light fades away
local function skyWindow(ctx: Timeline.Ctx)
	local h = h4(ctx)
	local t = ctx.t
	local eye = SKY + V(0, 2, 0)
	-- the painted sky above, the swirl turning slowly
	ctx:place(h.skyPaint, Util.lookAt(SKY + V(0, 52, 0), eye, V(0, 0, 1)) * CFrame.Angles(0, 0, (t - 37) * 0.06))
	-- the thin line of light fading out of the middle
	local beam = Util.smoothstep(37.0, 38.2, t)
	if beam < 1 then
		ctx:place(h.skyBeam, C(SKY + V(1.5, 26, 3)) * CFrame.Angles(0, 0, math.pi / 2))
		ctx:prop(h.skyBeam, { s = V(48, 0.35, 0.35), t = 0.3 + beam * 0.7 })
	end
	cam(ctx, eye, SKY + V(0, 100, 0), 72, 0, 0, V(0, 0, 1))
	ctx:fog(0)
	ctx:wind(0)
	ctx:bloom(0.3)
	grade(ctx, 0, 0.08, 0.12, Color3.fromRGB(236, 240, 255))
end

-- 41.0: Ryu from the front, scorched, jacket hanging open: his head comes
-- down from looking at the sky to look at us, a wide grin, "Thank you.";
-- then he starts to topple backwards into the smoke
local function thankYou(ctx: Timeline.Ctx)
	local t = ctx.t
	local down = Util.smoothstep(41.35, 42.0, t)
	local fall = Util.smoothstep(44.0, 44.7, t)
	local root = C(RYU) * CFrame.Angles(math.rad(10 * fall), 0, 0)
	ctx:rig("RyuLoose", root, Cast.alive({
		UpperTorso = R(6 - down * 4, 0, 0),
		Head = R(44 - down * 48, 0, 0),
		RightUpperArm = R(4, 0, 8),
		RightLowerArm = R(8, 0, 0),
		LeftUpperArm = R(4, 0, -8),
		LeftLowerArm = R(8, 0, 0),
	}, t))
	scorched(ctx)
	Cast.furLow(ctx, "RyuLoose", 0.8 * (1 - down))
	local speaking = t >= 42.667 and t < 44.45
	local face = if down < 0.6 then "dazed" elseif speaking and Util.noise1(t * 7, 4) > 0 then "dazedTalk" else "content"
	Cast.expr(ctx, "ryu", face)
	puffs(ctx, RYU + V(0, 0.8, 0), V(6, 0.8, 4), V(6, 0, 0), 2, Color3.fromRGB(222, 206, 180), 0.45, 4800)
	ctx:place(h4(ctx).lamp, C(RYU + V(0, 7, -5)))
	ctx:light("P4Lamp", 1.6, Color3.fromRGB(255, 244, 230), 16)
	cam(ctx, RYU + V(0.2, 4.7, -6.4), RYU + V(0, 4.5, 0), 40, 0, 0.6)
	ctx:wind(1.2)
	grade(ctx, 0.08, 0.16, -0.05, Color3.fromRGB(232, 230, 240))
	field(ctx, "low")
end

Part4.shots = {
	{ id = "P4 01 hold", t0 = 6.533, t1 = 7.933, run = holdWide },
	{ id = "P4 02 from above", t0 = 7.933, t1 = 8.933, run = top1 },
	{ id = "P4 03 ryu profile", t0 = 8.933, t1 = 9.8, run = ryuProfile },
	{ id = "P4 04 from above", t0 = 9.8, t1 = 10.533, run = top2 },
	{ id = "P4 05 ryu eye", t0 = 10.533, t1 = 11.367, run = ryuEye },
	{ id = "P4 06 dive", t0 = 11.367, t1 = 12.133, run = top3 },
	{ id = "P4 07 top close", t0 = 12.133, t1 = 12.5, run = topClose },
	{ id = "P4 08 pillar falls", t0 = 12.5, t1 = 12.7, run = pillarFalls },
	{ id = "P4 09 pillar", t0 = 12.7, t1 = 14.567, run = pillarWide },
	{ id = "P4 10 ryu from behind", t0 = 14.567, t1 = 15.9, run = ryuBack },
	{ id = "P4 11 scream", t0 = 15.9, t1 = 17.6, run = ryuScream },
	{ id = "P4 12 cone", t0 = 17.6, t1 = 18.9, run = cone },
	{ id = "P4 13 cyan wide", t0 = 18.9, t1 = 20.7, run = cyanWide },
	{ id = "P4 14 haze lifts", t0 = 20.7, t1 = 23.167, run = hazeLifts },
	{ id = "P4 15 lets go", t0 = 23.167, t1 = 25.6, run = letGo },
	{ id = "P4 16 burnt arm", t0 = 25.6, t1 = 27.833, run = burntArm },
	{ id = "P4 17 was this mine", t0 = 27.833, t1 = 31.567, run = wasThisMine },
	{ id = "P4 18 flashback", t0 = 31.567, t1 = 33.9, run = flashback },
	{ id = "P4 19 city", t0 = 33.9, t1 = 37.0, run = cityBeam },
	{ id = "P4 20 sky", t0 = 37.0, t1 = 41.0, run = skyWindow },
	{ id = "P4 21 thank you", t0 = 41.0, t1 = 44.7, run = thankYou },
} :: { Timeline.Shot }

return Part4
