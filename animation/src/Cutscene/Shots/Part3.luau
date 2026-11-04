--!strict
-- Part 3 ("Yuta vs. Ryu end fight scene pt. 3", 56.87 s). 0-2.633 replays the
-- end of part 2 (see Scene.build). Then: Rika's black shell crumbles to smoke
-- and Ryu tears free, bloody and grinning; a brawl of bare fists with a black
-- flash, intercut with a table of desserts that vanish one by one; Yuta grabs
-- Ryu by the collar: "Now we're done." Shot list: docs/part3_shots.md.
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Util)
local Rig = require(script.Parent.Parent.Rig)
local Cast = require(script.Parent.Cast)
local Clash = require(script.Parent.Clash)
local Common = require(script.Parent.P2.Common)

local Part3 = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local WHITE = Color3.new(1, 1, 1)

local RYU = Common.RYU
local YUTA = Common.RYU + V(0.3, 0, -3.2) -- close quarters
local DESSERT = V(0, 3000, -900) -- the dessert table, far above the field

type P3 = {
	blackBolts: FX.Bolt,
	redBolts: FX.Bolt,
	bigSmoke: FX.Burst,
	vanish: { [string]: { Builder.PartSpec } },
}

local function h2(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end
local function h3(ctx: Timeline.Ctx): P3
	return ctx.scene.data.p3
end

---------------------------------------------------------------------------
-- The dessert table: cakes, a strawberry tart, tea, a parfait, cupcakes
---------------------------------------------------------------------------
local function dessertSet(scene: Builder.Scene): { [string]: { Builder.PartSpec } }
	Builder.model(scene, "P3Desserts", false)
	local cream = Color3.fromRGB(250, 244, 232)
	local china = Color3.fromRGB(248, 248, 252)
	local gold = Color3.fromRGB(214, 176, 92)
	local silver = Color3.fromRGB(196, 200, 210)
	local sponge = Color3.fromRGB(244, 210, 146)
	local biscuit = Color3.fromRGB(206, 150, 86)
	local pink = Color3.fromRGB(244, 128, 170)
	local pinkDeep = Color3.fromRGB(220, 70, 120)
	local berry = Color3.fromRGB(214, 28, 50)
	local choc = Color3.fromRGB(92, 52, 34)
	local tea = Color3.fromRGB(128, 26, 22)
	local lime = Color3.fromRGB(186, 222, 120)
	local vanish: { [string]: { Builder.PartSpec } } = { slice = {}, parfait = {}, pink = {} }
	local up = CFrame.Angles(0, 0, math.pi / 2) -- cylinders stand upright
	local function part(name: string, shape: string, size: Vector3, cf: CFrame, col: Color3, mat: string?, group: string?): Builder.PartSpec
		local p = Builder.part(scene, "P3Desserts", size, C(DESSERT) * cf, col, { shape = shape, material = mat or "SmoothPlastic", castShadow = size.Magnitude > 1.2, name = name })
		if group then
			table.insert(vanish[group], p)
		end
		return p
	end
	local function disc(name: string, x: number, y: number, z: number, d: number, h: number, col: Color3, mat: string?, group: string?)
		return part(name, "Cylinder", V(h, d, d), C(x, y, z) * up, col, mat, group)
	end
	-- tablecloth and a soft back wall
	part("Cloth", "Block", V(80, 1, 60), C(0, -0.5, 0), Color3.fromRGB(244, 238, 226), "Fabric")
	part("Wall", "Block", V(80, 40, 1), C(0, 18, 22), Color3.fromRGB(248, 240, 214))
	-- a round plate with a gold rim
	local function plate(x: number, z: number, r: number)
		disc("PlateRim", x, 0.05, z, r * 2.12, 0.1, gold)
		disc("Plate", x, 0.12, z, r * 2, 0.14, china)
		disc("PlateWell", x, 0.17, z, r * 1.4, 0.06, Color3.fromRGB(240, 240, 246))
	end
	local function squarePlate(x: number, z: number, w: number, rot: number)
		part("Napkin", "Block", V(w * 1.3, 0.04, w * 1.3), C(x, 0.02, z) * CFrame.Angles(0, math.rad(rot + 20), 0), lime, "Fabric")
		part("SquarePlate", "Block", V(w, 0.14, w), C(x, 0.1, z) * CFrame.Angles(0, math.rad(rot), 0), china)
	end
	local function berryCluster(x: number, y: number, z: number, col: Color3, r: number)
		for i = 0, 6 do
			local a = i * 0.9
			part("Drupe", "Ball", V(r, r, r), C(x + math.cos(a) * r * 0.5, y + (i % 2) * r * 0.4, z + math.sin(a) * r * 0.5), col)
		end
	end
	local function cup(x: number, z: number)
		disc("SaucerRim", x, 0.05, z, 3.2, 0.08, gold)
		disc("Saucer", x, 0.1, z, 3.0, 0.12, china)
		disc("CupFoot", x, 0.3, z, 1.3, 0.3, china)
		disc("Cup", x, 0.95, z, 2.3, 1.0, china)
		disc("CupLip", x, 1.47, z, 2.42, 0.06, gold)
		disc("Tea", x, 1.4, z, 2.1, 0.06, tea)
		part("Handle", "Ellipsoid", V(0.3, 0.8, 0.6), C(x + 1.25, 1.0, z), china)
	end
	local function petitFour(x: number, y: number, z: number, top: Color3, i: number)
		part("PetitFour", "Block", V(0.7, 0.45, 0.7), C(x, y + 0.22, z) * CFrame.Angles(0, i * 0.7, 0), if i % 2 == 0 then sponge else choc)
		part("Icing", "Block", V(0.72, 0.1, 0.72), C(x, y + 0.48, z) * CFrame.Angles(0, i * 0.7, 0), top)
		part("Dot", "Ball", V(0.2, 0.2, 0.2), C(x, y + 0.6, z), if i % 3 == 0 then berry else gold)
	end

	-- 1. the pink cake slice (centre): biscuit, sponge, jelly, mousse, glaze,
	-- a macaron, raspberries, blueberries, a chocolate plaque, a mint leaf
	plate(0, 0, 3.6)
	type Layer = { h: number, col: Color3 }
	local pinkLayers: { Layer } = { { h = 0.3, col = biscuit }, { h = 0.5, col = sponge }, { h = 0.2, col = berry }, { h = 0.7, col = pink }, { h = 0.12, col = pinkDeep } }
	local y = 0.2
	for _, l in pinkLayers do
		part("Slice", "Block", V(2.2, l.h, 3.4), C(0, y + l.h / 2, 0) * CFrame.Angles(0, math.rad(30), 0), l.col, nil, "pink")
		y += l.h
	end
	disc("MacaronA", -0.3, y + 0.15, 0.4, 1.1, 0.26, pink, nil, "pink")
	disc("MacaronCream", -0.3, y + 0.33, 0.4, 0.95, 0.12, cream, nil, "pink")
	disc("MacaronB", -0.3, y + 0.5, 0.4, 1.1, 0.24, pink, nil, "pink")
	berryCluster(0.5, y + 0.25, -0.5, berry, 0.26)
	berryCluster(0.3, y + 0.25, 0.9, berry, 0.24)
	part("Blueberry", "Ball", V(0.38, 0.36, 0.38), C(0.75, y + 0.2, 0.2), Color3.fromRGB(52, 40, 110))
	part("Blueberry", "Ball", V(0.36, 0.34, 0.36), C(-0.7, y + 0.2, -0.6), Color3.fromRGB(70, 50, 130))
	part("Plaque", "Block", V(0.05, 0.7, 0.9), C(-0.9, y + 0.4, -0.2) * CFrame.Angles(0, math.rad(30), math.rad(-15)), Color3.fromRGB(250, 246, 236))
	part("Mint", "Ellipsoid", V(0.5, 0.06, 0.25), C(0.1, y + 0.35, -0.2) * CFrame.Angles(0, 0.6, 0.2), Color3.fromRGB(90, 170, 80))
	for i = 1, 6 do
		part("GoldFlake", "Ball", V(0.08, 0.04, 0.08), C(-0.6 + i * 0.22, y + 0.06, -1.0 + (i % 3) * 0.7), gold)
	end

	-- 2. the strawberry tart (right): crust, cream, glazed strawberries, piping
	plate(10, 2, 4.4)
	disc("TartCrust", 10, 0.65, 2, 7.0, 0.9, biscuit)
	disc("TartRim", 10, 1.08, 2, 7.2, 0.14, Color3.fromRGB(196, 136, 74))
	disc("TartCream", 10, 1.15, 2, 6.4, 0.2, cream)
	local rr = Util.rng(31)
	for i = 1, 30 do
		local a = i * 2.4
		local d = math.sqrt(i / 30) * 2.7
		local px, pz = 10 + math.cos(a) * d, 2 + math.sin(a) * d
		part("Strawberry", "Ellipsoid", V(0.85, 0.75, 0.75), C(px, 1.55, pz) * CFrame.Angles(0, Util.randRange(rr, 0, 6), 0.3), berry)
		part("Shine", "Ball", V(0.18, 0.1, 0.12), C(px - 0.15, 1.88, pz - 0.15), Color3.fromRGB(255, 200, 200))
	end
	for i = 0, 19 do
		local a = i / 20 * math.pi * 2
		part("Piping", "Ball", V(0.55, 0.5, 0.55), C(10 + math.cos(a) * 3.2, 1.4, 2 + math.sin(a) * 3.2), cream)
	end

	-- 3. a three-tier cake stand (upper left) with petit fours
	part("StandPole", "Cylinder", V(6.4, 0.3, 0.3), C(-12, 3.2, -6) * up, silver, "Metal")
	for t, tier in { { y = 0.4, r = 4.0 }, { y = 2.6, r = 3.2 }, { y = 4.8, r = 2.4 } } do
		disc("TierRim", -12, tier.y - 0.04, -6, tier.r * 2.06, 0.08, gold)
		disc("Tier", -12, tier.y, -6, tier.r * 2, 0.12, china)
		local n = 7 - t
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2 + t
			petitFour(-12 + math.cos(a) * tier.r * 0.62, tier.y + 0.06, -6 + math.sin(a) * tier.r * 0.62, ({ pink, cream, choc, lime })[(i + t) % 4 + 1], i + t)
		end
	end
	part("StandTop", "Ball", V(0.6, 0.6, 0.6), C(-12, 6.5, -6), silver, "Metal")

	-- 4. tea service: cups, a teapot, a creamer, sugar
	cup(-7, 6)
	cup(5, -9)
	cup(-3, 11)
	part("TeapotBody", "Ellipsoid", V(4.2, 3.2, 3.6), C(-16, 1.8, 6), china)
	part("TeapotLid", "Ellipsoid", V(2, 0.8, 2), C(-16, 3.4, 6), china)
	part("TeapotKnob", "Ball", V(0.5, 0.5, 0.5), C(-16, 3.9, 6), silver, "Metal")
	part("TeapotSpout", "Cylinder", V(2.2, 0.5, 0.5), C(-13.6, 2.2, 6) * CFrame.Angles(0, 0, math.rad(35)), china)
	part("TeapotHandle", "Ellipsoid", V(0.4, 1.8, 1.0), C(-18.2, 2.0, 6), china)
	part("Creamer", "Cylinder", V(1.6, 1.4, 1.4), C(-2, 0.8, 7.5) * up, china)
	disc("SugarBowl", 3, 0.6, 9, 1.8, 1.0, china)
	for i = 0, 3 do
		part("Sugar", "Block", V(0.35, 0.35, 0.35), C(2.7 + (i % 2) * 0.4, 1.25, 8.8 + (i // 2) * 0.4), Color3.fromRGB(252, 252, 252))
	end

	-- 5. square plates on lime napkins: a chocolate cupcake, a mousse cup
	squarePlate(7, -3.5, 3.4, 15)
	disc("Cupcake", 6.3, 0.75, -3.8, 1.5, 1.1, choc)
	part("CupcakeCream", "Ball", V(1.7, 1.2, 1.7), C(6.3, 1.6, -3.8), Color3.fromRGB(250, 222, 120))
	part("CupcakeBerry", "Ball", V(0.4, 0.4, 0.4), C(6.3, 2.25, -3.8), berry)
	disc("MousseCup", 7.8, 0.75, -3.0, 1.3, 1.1, Color3.fromRGB(230, 236, 246), "Glass")
	disc("Mousse", 7.8, 0.9, -3.0, 1.2, 1.0, Color3.fromRGB(180, 110, 70))

	-- 6. cutlery on a napkin
	part("Napkin2", "Block", V(2.2, 0.04, 5), C(-4, 0.02, -8), lime, "Fabric")
	part("Fork", "Block", V(0.22, 0.06, 3.6), C(-4.4, 0.08, -8), silver, "Metal")
	for i = -1, 1 do
		part("Prong", "Block", V(0.06, 0.05, 0.8), C(-4.4 + i * 0.1, 0.08, -10.1), silver, "Metal")
	end
	part("Spoon", "Block", V(0.2, 0.06, 3.0), C(-3.6, 0.08, -7.8), silver, "Metal")
	part("SpoonBowl", "Ellipsoid", V(0.6, 0.12, 0.9), C(-3.6, 0.1, -9.6), silver, "Metal")

	-- 7. the shortcake slice that disappears (front left)
	plate(-7, -2, 3.0)
	local shortLayers: { Layer } = { { h = 0.6, col = sponge }, { h = 0.3, col = cream }, { h = 0.6, col = sponge }, { h = 0.35, col = cream } }
	y = 0.2
	for _, l in shortLayers do
		part("Shortcake", "Wedge", V(2.4, l.h, 3.0), C(-7, y + l.h / 2, -2) * CFrame.Angles(0, math.rad(-20), 0), l.col, nil, "slice")
		y += l.h
	end
	part("ShortCream", "Ball", V(0.7, 0.5, 0.7), C(-7, y + 0.15, -2.6), cream, nil, "slice")
	part("ShortBerry", "Ellipsoid", V(0.7, 0.9, 0.7), C(-7, y + 0.6, -2.6), berry, nil, "slice")

	-- 8. the parfait glass that empties (back)
	plate(1, 6, 2.2)
	disc("GlassFoot", 1, 0.3, 6, 1.6, 0.2, Color3.fromRGB(226, 236, 246), "Glass")
	part("GlassStem", "Cylinder", V(1.2, 0.3, 0.3), C(1, 0.9, 6) * up, Color3.fromRGB(226, 236, 246), "Glass")
	disc("Glass", 1, 3.1, 6, 2.3, 3.4, Color3.fromRGB(220, 234, 246), "Glass")
	for i, col in { Color3.fromRGB(250, 236, 200), Color3.fromRGB(160, 100, 50), cream, berry, Color3.fromRGB(250, 236, 200) } do
		disc("ParfaitLayer", 1, 1.6 + i * 0.6, 6, 2.0, 0.6, col, nil, "parfait")
	end
	part("ParfaitTop", "Ball", V(1.6, 0.9, 1.6), C(1, 5.0, 6), cream, nil, "parfait")
	part("ParfaitCherry", "Ball", V(0.5, 0.5, 0.5), C(1, 5.6, 6), berry, nil, "parfait")

	-- 9. cupcakes and macarons (around)
	for i, c in { { 14, -8 }, { 16.5, -10 }, { -15, -9 }, { -17, 11 } } do
		disc("Cupcake", c[1], 0.6, c[2], 1.8, 1.1, if i % 2 == 0 then choc else biscuit)
		part("Frosting", "Ball", V(1.9, 1.3, 1.9), C(c[1], 1.5, c[2]), if i % 2 == 0 then Color3.fromRGB(250, 220, 110) else Color3.fromRGB(250, 190, 210))
		part("Sprinkle", "Ball", V(0.3, 0.3, 0.3), C(c[1], 2.15, c[2]), berry)
	end
	for i = 0, 5 do
		local col = ({ pink, Color3.fromRGB(170, 220, 160), Color3.fromRGB(250, 220, 110) })[i % 3 + 1]
		disc("Macaron", 15 + (i % 3) * 1.3, 0.35, 4 + (i // 3) * 1.4, 1.1, 0.6, col)
	end
	return vanish
end

function Part3.build(scene: Builder.Scene)
	local pal = scene.style.color
	local h: P3 = {
		blackBolts = FX.bolts(scene, "P3BlackBolts", Color3.fromRGB(20, 6, 14), 40),
		redBolts = FX.bolts(scene, "P3RedBolts", pal.eRed, 40),
		bigSmoke = FX.burst(scene, "P3Smoke", Color3.fromRGB(16, 14, 22), 30, "Ball", 81),
		vanish = dessertSet(scene),
	}
	for _, p in h.bigSmoke.parts do
		p.material = "SmoothPlastic"
	end
	for _, p in h.blackBolts.segs do
		p.material = "SmoothPlastic"
	end
	scene.data.p3 = h
end

---------------------------------------------------------------------------
-- poses and helpers
---------------------------------------------------------------------------
local guard: Rig.Pose = {
	LowerTorso = R(-4, 0, 0),
	UpperTorso = R(10, 0, 0),
	Head = R(-6, 0, 0),
	RightUpperArm = R(40, 0, 20),
	RightLowerArm = R(100, 0, 0),
	LeftUpperArm = R(50, 0, -20),
	LeftLowerArm = R(100, 0, 0),
	LeftUpperLeg = R(24, 0, -8),
	LeftLowerLeg = R(-24, 0, 0),
	RightUpperLeg = R(-18, 0, 8),
	RightLowerLeg = R(-6, 0, 0),
}

local punchR: Rig.Pose = {
	LowerTorso = R(-6, 22, 0),
	UpperTorso = R(14, 28, 0),
	Head = R(-6, -26, 0),
	RightUpperArm = R(92, 0, 2),
	RightLowerArm = R(0, 0, 0),
	RightHand = R(-80, 0, 0),
	LeftUpperArm = R(-20, 0, -30),
	LeftLowerArm = R(80, 0, 0),
	LeftUpperLeg = R(40, 0, -8),
	LeftLowerLeg = R(-40, 0, 0),
	RightUpperLeg = R(-30, 0, 8),
	RightLowerLeg = R(-10, 0, 0),
}

local recoil: Rig.Pose = {
	LowerTorso = R(10, 0, 0),
	UpperTorso = R(-24, -20, 0),
	Head = R(-28, -30, 10),
	RightUpperArm = R(10, 0, 60),
	RightLowerArm = R(40, 0, 0),
	LeftUpperArm = R(20, 0, -60),
	LeftLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(10, 0, -10),
	RightUpperLeg = R(-20, 0, 10),
	RightLowerLeg = R(-20, 0, 0),
}

-- a punch: wind-up, a fast strike that overshoots, then settles back a little
local function punchK(t: number, t0: number, dur: number): number
	local u = (t - t0) / dur
	if u < 0 then
		return 0
	elseif u < 0.35 then
		return -0.25 * Util.smoothstep(0, 0.35, u) -- wind-up (pull back)
	elseif u < 0.55 then
		return -0.25 + 1.4 * Util.smoothstep(0.35, 0.55, u) -- strike, overshoot
	end
	local s = u - 0.55
	return 1 + 0.15 * math.exp(-s * 10) * math.cos(s * 30) - 0.15 * Util.smoothstep(0.55, 1.2, u)
end

local function punchPose(k: number): Rig.Pose
	if k < 0 then
		return Cast.mix(guard, Cast.add(guard, "RightUpperArm", R(-30, 0, 20)), -k * 4)
	end
	return Cast.mix(guard, punchR, k)
end

local function bloodFace(ctx: Timeline.Ctx, head: CFrame, k: number)
	local hh = h2(ctx)
	local spots = { V(-0.12, 1.1, -0.6), V(0.18, 1.0, -0.62), V(0.05, 0.86, -0.64), V(-0.3, 0.95, -0.58), V(0.32, 0.8, -0.6), V(0.0, 0.7, -0.64), V(-0.16, 0.62, -0.63) }
	for i, p in hh.rikaBlood do
		ctx:place(p, head * C(spots[i]))
		local sz = (0.1 + (i % 3) * 0.05) * k
		ctx:prop(p, { s = V(sz, sz * 2.8, sz * 0.5) })
	end
end

local function field(ctx: Timeline.Ctx, mist: string?)
	Common.sky(ctx, mist or "wisps", 30)
end

local function grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	Common.grade(ctx, b, c, s, tint)
end

-- Rika over Ryu with her fist on his head, Yuta holding him (end of part 2)
local function pinned(ctx: Timeline.Ctx): ({ [string]: CFrame }, { [string]: CFrame })
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(10, 0, 0), Head = R(30, 0, 0), RightUpperArm = R(40, 0, 72), RightLowerArm = R(70, 0, 0), LeftUpperArm = R(40, 0, -72), LeftLowerArm = R(70, 0, 0) }, ctx.t))
	local top = (rb.Head * C(0, 2.2, 0)).Position
	local pound: Rig.Pose = {
		HumanoidRootPart = C(0, 1.6, 0),
		LowerTorso = R(-14, 0, 0),
		UpperTorso = R(-36, 0, 0),
		Head = R(20, 0, 0),
		RightUpperArm = R(60, 0, 12),
		RightLowerArm = R(40, 0, 0),
		RightHand = R(70, 0, 0),
		LeftUpperArm = R(30, 0, -60),
		LeftLowerArm = R(50, 0, 0),
		LeftUpperLeg = R(30, 0, 10),
		LeftLowerLeg = R(-40, 0, -30),
		LeftFoot = R(-40, 0, -40),
	}
	local kb = Common.rigAt(ctx, "Rika", C(RYU + V(1.5, 0, 4.5)), pound, "RightHand", C(0, -0.9, 0), top)
	return rb, kb
end

---------------------------------------------------------------------------
-- shots
---------------------------------------------------------------------------

-- 2.633: wide from low in front: Rika's black shell crumbles into smoke
local function dissolve(ctx: Timeline.Ctx)
	local hh, h = h2(ctx), h3(ctx)
	local _, kb = pinned(ctx)
	ctx:rig("Yuta", C(RYU + V(0.2, 0, -2.6)) * CFrame.Angles(0, math.rad(180), 0), guard)
	local u = ctx.u
	local c = kb.UpperTorso.Position + V(0, -1, 0)
	for i, p in h.bigSmoke.parts do
		local rr = Util.rng(700 + i)
		local ph = (ctx.lt * (0.18 + Util.rand(rr) * 0.12) + Util.rand(rr)) % 1
		local d = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -0.4, 1), Util.randRange(rr, -1, 1)).Unit
		local pos = c + d * (1 + ph * 6 * (0.4 + u)) + V(0, ph * 3, 0)
		local sz = (1.2 + ph * 3.5) * math.min(1, 0.3 + u * 1.5)
		ctx:place(p, C(pos))
		ctx:prop(p, { s = V(sz, sz * 0.8, sz), t = 0.15 + ph * 0.75 })
	end
	FX.placeBurst(ctx, hh.shell, c, (ctx.lt * 0.6) % 1.4, 6, 0.6, 1.4, V(0, -0.3, 0), 1, 4)
	Common.rikaEye(ctx, kb, 1 - u)
	local eye = RYU + V(3, 1.2, -16)
	ctx:camera(Util.lookAt(eye, kb.Head.Position:Lerp(RYU + V(0, 3, 0), 0.5)), 50)
	ctx:focus(16, 0.8)
	ctx:wind(1.6)
	grade(ctx, -0.04, 0.2, 0.05)
	field(ctx, "low")
end

-- 6.533: Ryu's bowed head lifts: dark hair, then the bloody face, white eyes
local function headUp(ctx: Timeline.Ctx)
	local k = Util.smoothstep(0.15, 0.85, ctx.u)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(16 - k * 10, 0, 0), Head = R(40 - k * 46, Util.noise1(ctx.t * 3, 2) * 5, 0) }, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodFace(ctx, rb.Head, 1)
	local head = rb.Head * C(0, 0.7, 0)
	local eye = (C(RYU) * C(0, 6.0, -2.9)).Position
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, 0.2, 0)), ctx.t, 0.05, 6), 46)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:gust(0.3)
	grade(ctx, -0.1, 0.28, -0.05)
	field(ctx)
end

-- 8.033: a blur of his arm, a white flash, his face with the fur
local function flashes(ctx: Timeline.Ctx)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ RightUpperArm = R(120, 0, 30), RightLowerArm = R(40, 0, 0), Head = R(-6, 14, 0) }, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodFace(ctx, rb.Head, 1)
	local head = rb.Head * C(0, 0.7, 0)
	local eye = head:PointToWorldSpace(V(1.0, -0.4, -2.6))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position), ctx.t, 0.6, 22), 50)
	ctx:focus(2.8, 1)
	if ctx.t >= 8.2 and ctx.t < 8.267 then
		ctx:flash(WHITE, 0.9)
	end
	ctx:gust(1.5)
	grade(ctx, 0, 0.3, 0)
end

-- 8.533: wide: he tears free; the shell bursts apart, blood sprays
local function breakFree(ctx: Timeline.Ctx)
	local hh, h = h2(ctx), h3(ctx)
	local k = Util.smoothstep(0, 0.35, ctx.u)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.mix(guard, Cast.ryu.spread, k), ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	local caught: Rig.Pose = { HumanoidRootPart = C(0, 1.4, 0), UpperTorso = R(-30, 0, 0), Head = R(10, 0, 0), RightUpperArm = R(100, 0, 70), RightLowerArm = R(20, 0, 0), LeftUpperArm = R(100, 0, -70), LeftLowerArm = R(20, 0, 0), LeftUpperLeg = R(30, 0, 10), LeftLowerLeg = R(-40, 0, -30) }
	local kb = ctx:rig("Rika", C(RYU + V(0, 1 + k * 2, 4.5)) * CFrame.Angles(math.rad(-k * 15), 0, 0), caught)
	Common.rikaEye(ctx, kb, 0.6)
	local c = (rb.UpperTorso * C(0, 1.2, 0)).Position
	FX.placeBurst(ctx, hh.shell, c, ctx.lt, 18, 0.9, 2.0, V(0, 0.6, 0), 1, 8)
	FX.placeBurst(ctx, hh.blood, c, ctx.lt % 0.9, 10, 0.25, 0.9, V(0, 0.8, 0), 1, 12)
	for i, p in h.bigSmoke.parts do
		local rr = Util.rng(900 + i)
		local d = V(Util.randRange(rr, -1, 1), Util.randRange(rr, -0.2, 1), Util.randRange(rr, -1, 1)).Unit
		local pos = c + d * (2 + ctx.lt * 8 * Util.randRange(rr, 0.5, 1))
		local sz = 1.5 + ctx.lt * 2
		ctx:place(p, C(pos))
		ctx:prop(p, { s = V(sz, sz, sz), t = math.min(0.95, 0.3 + ctx.lt * 0.35) })
	end
	local eye = RYU + V(-2, 2.5, -15)
	ctx:camera(Clash.shake(Util.lookAt(eye, RYU + V(0, 4, 2)), ctx.t, 0.4, 14), 55)
	ctx:focus(15, 0.8)
	ctx:gust(2 * math.exp(-ctx.lt * 1.5))
	grade(ctx, -0.02, 0.25, 0.05)
	field(ctx, "low")
end

-- 10.5: from the fur collar up to his bloody, grinning face
local function grin(ctx: Timeline.Ctx)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(-8 + Util.noise1(ctx.t * 2, 5) * 4, 20 - ctx.u * 14, 0)), ctx.t, 0.6))
	Cast.expr(ctx, "ryu", "grin")
	bloodFace(ctx, rb.Head, 1)
	local head = rb.Head * C(0, 0.7, 0)
	local k = Util.smoothstep(0.2, 0.7, ctx.u)
	local look = (rb.UpperTorso * C(0.6, 1.6, 0)).Position:Lerp(head.Position, k)
	local eye = head:PointToWorldSpace(V(-1.2, -0.6, -2.8))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.06, 8), 48)
	ctx:focus((look - eye).Magnitude, 1)
	ctx:wind(1.6)
	grade(ctx, -0.08, 0.26, -0.02)
	field(ctx)
end

-- 12.0: dark blue smoke fills the frame: what is left of Rika
local function smoke(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local o = RYU + V(0, 4, 6)
	for i, p in h.bigSmoke.parts do
		local rr = Util.rng(1100 + i)
		local pos = o + V(Util.randRange(rr, -8, 8) + ctx.lt * Util.randRange(rr, -1, 1), Util.randRange(rr, -3, 6) + ctx.lt * 0.6, Util.randRange(rr, -4, 4))
		local sz = Util.randRange(rr, 3, 7)
		ctx:place(p, C(pos))
		ctx:prop(p, { s = V(sz, sz * 0.8, sz), c = Color3.fromRGB(28, 40, 74), t = Util.randRange(rr, 0.2, 0.6) })
	end
	ctx:camera(Util.lookAt(RYU + V(0, 4, -8), o), 50)
	ctx:focus(14, 0)
	grade(ctx, -0.25, 0.2, -0.2, Color3.fromRGB(150, 170, 230))
	ctx:fog(2.2)
end

-- 14.1: Yuta in shock, his raised hand in the foreground, fingers spread
local function yutaShock(ctx: Timeline.Ctx)
	local yr = C(YUTA) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", yr, Cast.alive({ RightUpperArm = R(150, 0, 10), RightLowerArm = R(30, 0, 0), RightHand = R(-20, 0, 0), Head = R(-6, 6 + Util.noise1(ctx.t * 4, 9) * 3, 0) }, ctx.t))
	Cast.expr(ctx, "yuta", "shout")
	local head = yb.Head * C(0, 0.6, 0)
	local eye = head:PointToWorldSpace(V(-0.6, -0.1, -3.0))
	ctx:camera(Util.lookAt(eye, head.Position + V(0.4, 0, 0)), 46)
	ctx:focus(3, 1)
	ctx:wind(1.4)
	grade(ctx, -0.02, 0.22, 0.05)
	field(ctx)
end

-- 15.433: Ryu punches Yuta, who twists away
local function grapple(ctx: Timeline.Ctx)
	local k = punchK(ctx.t, 15.6, 1.2)
	local rb = ctx:rig("RyuLoose", C(RYU) * CFrame.Angles(0, math.rad(10), 0), Cast.alive(punchPose(k), ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodFace(ctx, rb.Head, 1)
	local hit = Util.smoothstep(0.45, 0.6, (ctx.t - 15.6) / 1.2)
	ctx:rig("Yuta", C(YUTA + V(0.4 * hit, 0, -0.6 * hit)) * CFrame.Angles(0, math.rad(180 - 30 * hit), 0), Cast.mix(guard, recoil, hit))
	Cast.expr(ctx, "yuta", "glare")
	local eye = RYU + V(7.5, 4.0, -1.8)
	ctx:camera(Clash.shake(Util.lookAt(eye, RYU + V(0, 3.8, -1.6)), ctx.t, 0.25 + hit * 0.4, 14), 50)
	ctx:focus(7.5, 1)
	ctx:gust(hit * 1.5)
	grade(ctx, -0.02, 0.24, 0.05)
	field(ctx)
end

-- 17.633: his arm reaching out, the open hand closing into a fist
local function hand(ctx: Timeline.Ctx)
	local k = Util.smoothstep(0.25, 0.75, ctx.u)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ RightUpperArm = R(88, 0, 4), RightLowerArm = R(6, 0, 0), RightHand = R(-40 * k, 0, 0) }, ctx.t))
	local wrist = (rb.RightHand * C(0, -0.3, 0)).Position
	local eye = wrist + V(1.3, 0.45, 0.9)
	ctx:camera(Clash.shake(Util.lookAt(eye, wrist + V(0, 0, -0.6)), ctx.t, 0.05, 6), 50)
	ctx:focus((wrist - eye).Magnitude, 1)
	if ctx.t > 19.55 then
		ctx:flash(WHITE, 0.6)
	end
	ctx:wind(1.6)
	grade(ctx, -0.04, 0.24, 0.05)
	field(ctx)
end

-- 19.9: Yuta, bloody, fist raised, eyes in shadow
local function yutaFist(ctx: Timeline.Ctx)
	local yr = C(YUTA) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", yr, Cast.alive(Cast.add(guard, "RightUpperArm", R(40, 0, 0)), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local eye = (yb.UpperTorso * C(0.6, 0.4, -4.2)).Position
	ctx:camera(Util.lookAt(eye, yb.Head.Position + V(0, -0.6, 0)), 50)
	ctx:focus(4.2, 1)
	ctx:wind(1.5)
	grade(ctx, -0.08, 0.26, 0)
	field(ctx)
end

local function yutaFace(ctx: Timeline.Ctx)
	local yr = C(YUTA) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", yr, Cast.alive(Cast.add(guard, "Head", R(14, 0, 0)), ctx.t))
	Cast.expr(ctx, "yuta", if ctx.t > 22.4 then "shout" else "glare")
	local head = yb.Head * C(0, 0.55, 0)
	local eye = head:PointToWorldSpace(V(0, 0.05, -1.9))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.1, 0)), ctx.t, 0.04, 6), 44)
	ctx:focus(1.9, 1)
	ctx:wind(1.2)
	grade(ctx, -0.12, 0.3, 0)
end

-- 23.033 / 38.667: from high above, two small figures trading blows
local function topView(ctx: Timeline.Ctx)
	local k = punchK(ctx.t, ctx.frame.t - ctx.lt + 0.15, 0.7)
	ctx:rig("RyuLoose", C(RYU), Cast.alive(punchPose(k), ctx.t))
	ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(punchPose(punchK(ctx.t, ctx.frame.t - ctx.lt + 0.45, 0.7)), ctx.t))
	local mid = (RYU + YUTA) / 2
	ctx:camera(Util.lookAt(mid + V(4, 46, 6), mid, V(0, 0, -1)) * CFrame.Angles(0, 0, math.rad(20)), 40)
	ctx:focus(46, 0)
	grade(ctx, -0.1, 0.24, 0.05, Color3.fromRGB(200, 215, 255))
end

-- 24.233: an exchange of blows; Yuta's fist into Ryu's face
local function exchange(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local kY = punchK(ctx.t, 24.0, 0.8)
	local kR = punchK(ctx.t, 24.8, 0.9)
	local kY2 = punchK(ctx.t, 25.5, 0.8)
	local yK = math.max(kY, kY2)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.mix(punchPose(kR), recoil, math.clamp(yK, 0, 1) * 0.6), ctx.t))
	local yb = ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(Cast.mix(punchPose(yK), recoil, math.clamp(kR, 0, 1) * 0.6), ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "shout")
	bloodFace(ctx, rb.Head, 1)
	local hitP = (rb.Head * C(0, 0.6, -0.5)).Position
	if yK > 0.95 then
		FX.placeBurst(ctx, hh.blood, hitP, (ctx.t * 3) % 0.3, 8, 0.12, 0.3, V(0, 0.4, 1), 1, 10)
	end
	local close = ctx.t < 24.6 or ctx.t > 25.7
	local eye = if close then hitP + V(2.4, 0.2, -0.8) else (RYU + YUTA) / 2 + V(7, 3.6, 0)
	local look = if close then hitP else (RYU + YUTA) / 2 + V(0, 3.4, 0)
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.3, 16), 52)
	ctx:focus((look - eye).Magnitude, 1)
	ctx:gust(math.clamp(yK + kR, 0, 1.5))
	grade(ctx, -0.04, 0.26, 0.05)
	field(ctx)
	local _ = yb
end

-- 26.2: black flash: red and black lightning, a white flash, the impact
local function blackFlash(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	local kY = punchK(t, 26.6, 0.9)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.mix(guard, recoil, math.clamp(kY, 0, 1)), t))
	local yb = ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(punchPose(kY), t))
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "shout")
	local fist = (yb.RightHand * C(0, -0.4, 0)).Position
	local idx, jdx = 1, 1
	for i = 1, 10 do
		local a = math.rad(i * 36 + t * 200)
		local d = V(math.cos(a), math.sin(a) * 0.8, math.sin(a * 1.7) * 0.5).Unit
		idx = FX.placeBolt(ctx, h.redBolts, idx, fist, fist + d * (3 + (i % 3) * 2), 7, 0.4, 0.08, i + 300, 20)
		jdx = FX.placeBolt(ctx, h.blackBolts, jdx, fist, fist + d * (2 + (i % 4)), 6, 0.35, 0.12, i + 400, 20)
	end
	local dark = t < 27.2
	if dark then
		-- a dark frame: only the red and black lightning shows
		ctx:camera(Util.lookAt(fist + V(-2.5, 0.5, -7), fist), 50)
		grade(ctx, -0.75, 0.6, -0.2, Color3.fromRGB(255, 200, 210))
		ctx:fog(0)
	else
		local eye = (rb.Head.Position + yb.Head.Position) / 2 + V(6, 0.5, 0)
		ctx:camera(Clash.shake(Util.lookAt(eye, (rb.Head.Position + yb.Head.Position) / 2), t, 0.5, 20), 52)
	end
	ctx:focus(8, 0.5)
	local w = if t >= 27.2 and t < 27.6 then 1 - (t - 27.2) / 0.4 else 0
	ctx:flash(Color3.fromRGB(255, 230, 240), w)
	ctx:gust(1.8)
	ctx:bloom(1.6)
	if not dark then
		grade(ctx, -0.05, 0.35, -0.1, Color3.fromRGB(255, 220, 228))
	end
end

-- the dessert table
-- The dessert table turns slowly under the camera (as in the reference): the
-- camera orbits the vertical axis through `at` by `spin` degrees a second
local function tableCam(ctx: Timeline.Ctx, at: Vector3, from: Vector3, fov: number, spin: number?)
	local a = math.rad((spin or 8) * ctx.lt)
	local rot = CFrame.Angles(0, a, 0)
	local rel = rot:VectorToWorldSpace(from - at)
	local topDown = math.abs(rel.Unit.Y) > 0.95
	local upv = if topDown then rot:VectorToWorldSpace(V(0, 0, 1)) else V(0, 1, 0)
	ctx:camera(Util.lookAt(DESSERT + at + rel, DESSERT + at, upv), fov)
	ctx:focus(rel.Magnitude, 1)
	ctx:fog(0)
	ctx:wind(0)
	ctx:bloom(1.2)
	grade(ctx, 0.08, 0.05, 0.1, Color3.fromRGB(255, 248, 236))
end

local function desserts(ctx: Timeline.Ctx)
	if ctx.t < 30.7 then
		-- the pink cake from above, turning
		tableCam(ctx, V(0, 1.2, 0), V(0.05, 9.5 - ctx.lt * 0.6, 0.6), 44, 7)
	else
		-- the whole table from above, turning
		tableCam(ctx, V(-1, 0, 1), V(-1, 24 - ctx.lt * 0.8, 1.2), 52, 9)
	end
end

local function intercut(ctx: Timeline.Ctx)
	local t = ctx.t
	if t < 33.9 or (t >= 35.2 and t < 35.667) then
		-- a quick blow between them
		local k = punchK(t, 33.17, 0.6)
		ctx:rig("RyuLoose", C(RYU), Cast.alive(punchPose(k), t))
		ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(Cast.mix(guard, recoil, math.clamp(k, 0, 1)), t))
		Cast.expr(ctx, "ryu", "grit")
		local eye = (RYU + YUTA) / 2 + V(5.5, 3.8, 0.6)
		ctx:camera(Clash.shake(Util.lookAt(eye, (RYU + YUTA) / 2 + V(0, 3.8, 0)), t, 0.5, 20), 52)
		ctx:focus(5.5, 1)
		ctx:gust(1.4)
		grade(ctx, -0.04, 0.26, 0.05)
		field(ctx)
	elseif t < 35.2 then
		tableCam(ctx, V(-7, 1.2, -2), V(-4, 3.2, -6), 34, 12)
	else
		tableCam(ctx, V(10, 1.4, 2), V(13, 5, -2.5), 36, 12)
	end
end

local function wideFight(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local k = punchK(ctx.t, 36.85, 0.8)
	ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.mix(guard, recoil, math.clamp(k, 0, 1)), ctx.t))
	ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(punchPose(k), ctx.t))
	FX.placeBurst(ctx, hh.debris, (RYU + YUTA) / 2, ctx.lt, 16, 0.8, 1, V(0, 1, 0), 1, 25)
	local mid = (RYU + YUTA) / 2
	ctx:camera(Clash.shake(Util.lookAt(mid + V(12, 4, -6), mid + V(0, 3, 0)), ctx.t, 0.3, 12), 50)
	ctx:focus(14, 0.8)
	ctx:gust(1)
	grade(ctx, -0.04, 0.24, 0.05)
	field(ctx, "low")
end

local function tart(ctx: Timeline.Ctx)
	tableCam(ctx, V(10, 1, 2), V(10.05, 12 - ctx.lt * 1.5, 2.3), 42, 10)
end

local function fistLines(ctx: Timeline.Ctx)
	local ryuTurn = ctx.t > 40.1
	local k = punchK(ctx.t, if ryuTurn then 40.0 else 39.4, 0.6)
	local who = if ryuTurn then "RyuLoose" else "Yuta"
	local root = if ryuTurn then C(RYU) else C(YUTA) * CFrame.Angles(0, math.rad(180), 0)
	local b = ctx:rig(who, root, punchPose(k))
	local fist = (b.RightHand * C(0, -0.35, 0)).Position
	ctx:camera(Clash.shake(Util.lookAt(fist + root.RightVector * 2.4 + V(0, 0.3, 0), fist), ctx.t, 0.3, 16), 50)
	ctx:focus(2.4, 1)
	ctx:alpha("speed", 0.35)
	ctx:gust(2)
	grade(ctx, -0.02, 0.24, 0.05)
end

-- desserts vanish: the parfait empties, the shortcake slice is gone
local function vanish(ctx: Timeline.Ctx)
	local h = h3(ctx)
	local t = ctx.t
	if t < 41.5 then
		local k = Util.smoothstep(40.8, 41.4, t)
		for i, p in h.vanish.parfait do
			local gone = math.clamp(k * 4 - (4 - i), 0, 1)
			ctx:prop(p, { s = V(p.size.X * (1 - gone), p.size.Y, p.size.Z), t = gone })
		end
		tableCam(ctx, V(1, 2.8, 6), V(1, 3.6, 0.5), 36, 4)
	else
		local k = Util.smoothstep(41.6, 42.6, t)
		for _, p in h.vanish.slice do
			ctx:prop(p, { t = k })
		end
		tableCam(ctx, V(-7, 1.0, -2), V(-7, 3.0, -6.2), 36, 4)
	end
end

local function absHit(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local k = punchK(ctx.t, 42.7, 0.8)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.mix(Cast.ryu.spread, recoil, math.clamp(k, 0, 1) * 0.5), ctx.t))
	local yb = ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), punchPose(k))
	Cast.expr(ctx, "ryu", "grit")
	local belly = (rb.UpperTorso * C(0, 0.5, -0.6)).Position
	if k > 0.9 then
		FX.placeBurst(ctx, hh.debris, belly, (ctx.t * 2) % 0.5, 12, 0.3, 0.5, V(0, 0.3, 1), 1, 10)
	end
	local look = if ctx.t < 43.6 then belly else rb.Head.Position
	local eye = look + V(-2.5, 0.2, -2.4)
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.35, 18), 50)
	ctx:focus((look - eye).Magnitude, 1)
	ctx:alpha("speed", 0.25)
	ctx:gust(1.6)
	grade(ctx, -0.04, 0.26, 0.05)
	local _ = yb
end

local function yutaPunch(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local k = punchK(ctx.t, 43.85, 0.9)
	local yb = ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(punchPose(k), ctx.t))
	Cast.expr(ctx, "yuta", "shout")
	local fist = (yb.RightHand * C(0, -0.4, 0)).Position
	FX.placeBurst(ctx, hh.debris, fist, ctx.lt, 18, 0.5, 1.1, V(0, 0.3, 1), 1, 15)
	local eye = (yb.UpperTorso * C(-1.4, 1.3, -3.6)).Position
	ctx:camera(Clash.shake(Util.lookAt(eye, yb.Head.Position:Lerp(fist, 0.4)), ctx.t, 0.3, 14), 52)
	ctx:focus(4, 1)
	ctx:gust(1.4)
	grade(ctx, -0.04, 0.26, 0.05)
	field(ctx)
end

local function darkCupcakes(ctx: Timeline.Ctx)
	if ctx.t < 45.3 then
		Clash.void(ctx, Color3.new(0, 0, 0))
		ctx:camera(C(Clash.O), 50)
	else
		tableCam(ctx, V(6.3, 1.2, -3.8), V(3, 3, -8), 40, 6)
		grade(ctx, -0.45, 0.25, -0.2)
	end
end

-- 45.633: Yuta's fist into Ryu's face, from the side
local function facePunch(ctx: Timeline.Ctx)
	local hh = h2(ctx)
	local k = punchK(ctx.t, 45.7, 1.0)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(Cast.mix(guard, recoil, math.clamp(k, 0, 1)), ctx.t))
	ctx:rig("Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), Cast.alive(punchPose(k), ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "glare")
	bloodFace(ctx, rb.Head, 1)
	if k > 0.95 then
		FX.placeBurst(ctx, hh.blood, rb.Head.Position + V(0, 0.6, 0), (ctx.t * 2.5) % 0.4, 9, 0.14, 0.4, V(0, 0.5, 1), 1, 10)
	end
	local mid = (RYU + YUTA) / 2 + V(0, 4, 0)
	ctx:camera(Clash.shake(Util.lookAt(mid + V(6.5, 0, 0), mid), ctx.t, 0.3 + math.clamp(k, 0, 1) * 0.3, 16), 50)
	ctx:focus(6.5, 1)
	ctx:gust(math.clamp(k, 0, 1) * 1.6)
	grade(ctx, -0.04, 0.26, 0.05, Color3.fromRGB(205, 220, 255))
end

-- 47.833: Ryu, bloody, grinning, draws his fist back; 49.6 the fist flies
local function ryuWindup(ctx: Timeline.Ctx)
	local k = Util.smoothstep(48.6, 49.5, ctx.t)
	local pose = Cast.mix(Cast.add(guard, "Head", R(-10, 10, 0)), Cast.add(guard, "RightUpperArm", R(-40, 0, 30)), k)
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive(pose, ctx.t, 0.5))
	Cast.expr(ctx, "ryu", if ctx.t < 48.667 then "grit" else "grin")
	bloodFace(ctx, rb.Head, 1)
	local head = rb.Head * C(0, 0.7, 0)
	local eye = head:PointToWorldSpace(V(0.8, -0.3, -2.8))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position), ctx.t, 0.08, 8), 48)
	ctx:focus(2.9, 1)
	ctx:wind(1.6)
	grade(ctx, -0.06, 0.26, 0.05)
	field(ctx)
end

local function ryuFist(ctx: Timeline.Ctx)
	local k = punchK(ctx.t, 49.45, 0.8)
	local rb = ctx:rig("RyuLoose", C(RYU), punchPose(k))
	local fist = (rb.RightHand * C(0, -0.35, 0)).Position
	ctx:camera(Clash.shake(Util.lookAt(fist + V(-2.2, 0.3, -1.6), fist), ctx.t, 0.3, 16), 50)
	ctx:focus(2.6, 1)
	ctx:alpha("speed", 0.35)
	ctx:gust(2)
	grade(ctx, -0.02, 0.24, 0.05)
end

-- 50.6: Yuta sees the fist coming and turns
local function yutaSees(ctx: Timeline.Ctx)
	local turn = Util.smoothstep(51.5, 52.2, ctx.t)
	local yr = C(YUTA) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", yr, Cast.alive(Cast.add(guard, "Head", R(-4, -20 * turn, 6 * turn)), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local head = yb.Head * C(0, 0.55, 0)
	local eye = head:PointToWorldSpace(V(0.3 - turn * 0.6, -0.1, -2.6))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position), ctx.t, 0.05, 6), 46)
	ctx:focus(2.6, 1)
	ctx:wind(1.4)
	grade(ctx, -0.06, 0.26, 0.05)
	field(ctx)
end

local function darkEye(ctx: Timeline.Ctx)
	local yr = C(YUTA) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", yr, guard)
	Cast.expr(ctx, "yuta", "glare")
	local head = yb.Head * C(0.2, 0.6, 0)
	ctx:camera(Util.lookAt(head:PointToWorldSpace(V(0, 0, -1.2)), head.Position), 40)
	ctx:focus(1.2, 1)
	grade(ctx, -0.6 - ctx.u * 0.4, 0.2, -0.3)
end

-- 52.867: Yuta's hands seize Ryu's jacket; 55.0 "Now we're done."
local function seizePoses(ctx: Timeline.Ctx): ({ [string]: CFrame }, { [string]: CFrame })
	local rb = ctx:rig("RyuLoose", C(RYU), Cast.alive({ UpperTorso = R(16, 0, 0), Head = R(20, 0, 0), RightUpperArm = R(10, 0, 20), LeftUpperArm = R(10, 0, -20) }, ctx.t))
	local collar = (rb.UpperTorso * C(0, 1.4, -0.7)).Position
	local grab: Rig.Pose = {
		UpperTorso = R(10, 0, 0),
		Head = R(-10, 0, 0),
		RightUpperArm = R(80, 0, 10),
		RightLowerArm = R(40, 0, 0),
		RightHand = R(-40, 0, 0),
		LeftUpperArm = R(80, 0, -10),
		LeftLowerArm = R(40, 0, 0),
		LeftHand = R(-40, 0, 0),
	}
	local yb = Common.rigAt(ctx, "Yuta", C(YUTA) * CFrame.Angles(0, math.rad(180), 0), grab, "RightHand", C(0, -0.35, 0), collar + V(0.3, 0, 0))
	return rb, yb
end

local function seize(ctx: Timeline.Ctx)
	local rb, yb = seizePoses(ctx)
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "glare")
	bloodFace(ctx, rb.Head, 1)
	local look = if ctx.t < 54.0 then (yb.RightHand.Position + yb.LeftHand.Position) / 2 else rb.Head.Position
	local eye = look + V(1.6, 0.4, -2.4)
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.06, 8), 48)
	ctx:focus((look - eye).Magnitude, 1)
	ctx:gust(0.6 * math.exp(-ctx.lt * 2))
	grade(ctx, -0.06, 0.26, 0.05)
	field(ctx)
end

local function done(ctx: Timeline.Ctx)
	local _, yb = seizePoses(ctx)
	-- Yuta says it ("Now we're done.", 55.07-56.53)
	local speaking = ctx.t >= 55.07 and ctx.t < 56.53
	Cast.expr(ctx, "yuta", if speaking and Util.noise1(ctx.t * 7.5, 5) > -0.2 then "talk" else "glare")
	local head = yb.Head * C(0, 0.55, 0)
	local eye = head:PointToWorldSpace(V(0.4, -0.5, -2.4))
	ctx:camera(Util.lookAt(eye, head.Position + V(0, -0.4, 0)), 48)
	ctx:focus(2.5, 1)
	ctx:wind(1.2)
	grade(ctx, -0.06, 0.26, 0.05)
	field(ctx)
end

Part3.shots = {
	{ id = "P3 01 rika dissolves", t0 = 2.633, t1 = 6.533, run = dissolve },
	{ id = "P3 02 head up", t0 = 6.533, t1 = 8.033, run = headUp },
	{ id = "P3 03 flashes", t0 = 8.033, t1 = 8.533, run = flashes },
	{ id = "P3 04 breaks free", t0 = 8.533, t1 = 10.5, run = breakFree },
	{ id = "P3 05 grin", t0 = 10.5, t1 = 12.0, run = grin },
	{ id = "P3 06 smoke", t0 = 12.0, t1 = 14.1, run = smoke },
	{ id = "P3 07 yuta shock", t0 = 14.1, t1 = 15.433, run = yutaShock },
	{ id = "P3 08 grapple", t0 = 15.433, t1 = 17.633, run = grapple },
	{ id = "P3 09 hand", t0 = 17.633, t1 = 19.9, run = hand },
	{ id = "P3 10 yuta fist", t0 = 19.9, t1 = 21.267, run = yutaFist },
	{ id = "P3 11 yuta face", t0 = 21.267, t1 = 23.033, run = yutaFace },
	{ id = "P3 12 top", t0 = 23.033, t1 = 24.233, run = topView },
	{ id = "P3 13 exchange", t0 = 24.233, t1 = 26.2, run = exchange },
	{ id = "P3 14 black flash", t0 = 26.2, t1 = 29.167, run = blackFlash },
	{ id = "P3 15 desserts", t0 = 29.167, t1 = 33.167, run = desserts },
	{ id = "P3 16 intercut", t0 = 33.167, t1 = 36.8, run = intercut },
	{ id = "P3 17 wide fight", t0 = 36.8, t1 = 37.8, run = wideFight },
	{ id = "P3 18 tart", t0 = 37.8, t1 = 38.667, run = tart },
	{ id = "P3 19 top", t0 = 38.667, t1 = 39.5, run = topView },
	{ id = "P3 20 fists", t0 = 39.5, t1 = 40.733, run = fistLines },
	{ id = "P3 21 vanish", t0 = 40.733, t1 = 42.867, run = vanish },
	{ id = "P3 22 abs", t0 = 42.867, t1 = 44.0, run = absHit },
	{ id = "P3 23 yuta punch", t0 = 44.0, t1 = 45.133, run = yutaPunch },
	{ id = "P3 24 dark", t0 = 45.133, t1 = 45.633, run = darkCupcakes },
	{ id = "P3 25 face punch", t0 = 45.633, t1 = 47.833, run = facePunch },
	{ id = "P3 26 ryu windup", t0 = 47.833, t1 = 49.6, run = ryuWindup },
	{ id = "P3 27 ryu fist", t0 = 49.6, t1 = 50.6, run = ryuFist },
	{ id = "P3 28 yuta sees", t0 = 50.6, t1 = 52.267, run = yutaSees },
	{ id = "P3 29 dark eye", t0 = 52.267, t1 = 52.867, run = darkEye },
	{ id = "P3 30 seize", t0 = 52.867, t1 = 55.0, run = seize },
	{ id = "P3 31 done", t0 = 55.0, t1 = 56.867, run = done },
} :: { Timeline.Shot }

return Part3
