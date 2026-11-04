--!strict
-- Yuta's (and Rika's) shots.
--   6  9.600-10.867 Yuta inside Rika's embrace, pink energy, cyan streaks
--  13 21.367-21.533 Yuta fires, Rika's head looming behind
--  14 21.533-21.867 Yuta's face, Rika's fingers beside it
--  15 21.867-22.333 ...blurs out to white
--  22 33.867-34.100 grey smoke, a pink point of light
--  23 34.100-34.600 Rika fires her beam
--  24 34.600-35.100 Yuta's feet race over the cracked ice
--  31 43.867-44.800 Yuta charges through the mist and sparks
--  32 44.800-49.300 Yuta close-up (blood on the shoulder)
--  33 49.300-50.400 behind Yuta as he runs at Ryu through flying debris
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local Rig = require(script.Parent.Parent.Rig)
local FX = require(script.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Util)
local Cast = require(script.Parent.Cast)
local Field = require(script.Parent.Field)
local Clash = require(script.Parent.Clash)

local YutaShots = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

type H = {
	cyan: FX.Beam,
	cyan2: FX.Beam,
	pink: FX.Beam,
	pinkCore: Builder.PartSpec,
	whiteCore: Builder.PartSpec,
	debris: FX.Burst,
	sparks: FX.Burst,
}

function YutaShots.build(scene: Builder.Scene)
	local pal = scene.style.color
	scene.data.yuta = {
		cyan = FX.beam(scene, "YutaCyan", pal.eCyan, true),
		cyan2 = FX.beam(scene, "YutaCyan2", pal.eCyan, false),
		pink = FX.beam(scene, "RikaBeam", pal.ePink, false),
		pinkCore = FX.core(scene, "RikaGlow", pal.ePink),
		whiteCore = FX.core(scene, "YutaChargeCore", Color3.fromRGB(255, 240, 250)),
		debris = FX.burst(scene, "Debris", pal.rubble, 26, "Block", 61),
		sparks = FX.burst(scene, "PurpleSparks", pal.ePurple, 26, "Wedge", 62),
	} :: H
	-- debris is rock, not glowing
	for _, p in (scene.data.yuta :: H).debris.parts do
		p.material = "Slate"
	end
end

local YUTA = Field.YUTA + V(-6, 0, 4)

local function grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	ctx:grade({ brightness = b, contrast = c, saturation = s, tint = tint or Color3.fromRGB(236, 240, 255) })
end

-- 6: Yuta inside Rika's embrace, pink light, cyan streaks slicing past
-- Yuta reaching up with his left hand (the ring hand) to the charge of his
-- beam, his right hand open by his hip, leaning back a little in Rika's arms
local reachLeft: Rig.Pose = {
	LowerTorso = R(4, 8, 0),
	UpperTorso = R(8, 22, 0),
	Head = R(-8, 26, 0),
	LeftUpperArm = R(138, 0, 8),
	LeftLowerArm = R(4, 0, 0),
	LeftHand = R(-24, 0, 0),
	RightUpperArm = R(-8, 0, 20),
	RightLowerArm = R(26, 0, 0),
	RightHand = R(12, 0, 0),
	LeftUpperLeg = R(20, 0, 0),
	LeftLowerLeg = R(-30, 0, 0),
	RightUpperLeg = R(-20, 0, 0),
}

local function embrace(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.yuta
	local root = C(YUTA) * CFrame.Angles(0, math.rad(90), 0)
	-- the arm comes up into the charge, then trembles holding it
	local up = Util.smoothstep(9.6, 9.85, ctx.t)
	local tremble = math.sin(ctx.t * 31) * 1.5
	local pose = Cast.add(Cast.mix(Cast.yuta.fire, reachLeft, up), "LeftUpperArm", R(tremble, 0, tremble * 0.5))
	local yb = ctx:rig("Yuta", root, Cast.alive(pose, ctx.t))
	ctx:rig("Rika", root * C(0.4, 0, 3.4), Cast.alive(Cast.rika.embrace, ctx.t))
	Cast.expr(ctx, "yuta", "focus")
	local head = yb.Head * C(0, 0.6, 0)
	local hand0 = (yb.LeftHand * C(0, -0.55, -0.15)).Position
	local cam = Util.lookAt(yb.UpperTorso:PointToWorldSpace(V(-4.6, 1.2, -2.6)), head.Position:Lerp(hand0, 0.35) + V(0, -0.6, 0))
	ctx:camera(Clash.shake(cam * CFrame.Angles(0, 0, math.rad(-18)), ctx.t, 0.15), 56)
	ctx:focus(5, 1)
	-- the charge: a pink-white star of energy in his raised left hand
	local hand = (yb.LeftHand * C(0, -0.55, -0.15)).Position
	local flick = 1 + math.sin(ctx.t * 29) * 0.1 + math.sin(ctx.t * 17 + 1) * 0.06
	FX.placeCore(ctx, h.pinkCore, hand, 0.36 * flick * up, 0.8)
	FX.placeCore(ctx, h.whiteCore, hand, 0.18 * flick * up, 1)
	FX.placeBurst(ctx, h.sparks, hand, (ctx.lt * 0.9) % 0.7, 9, 0.18, 0.7, nil, nil, 0)
	ctx:light("YutaAura", 2, nil, 14)
	ctx:light("RikaMouth", 1.5, nil, 20)
	ctx:emit("YutaGlints", 40)
	local a = head:PointToWorldSpace(V(-9, 6, -3))
	local b = head:PointToWorldSpace(V(8, -6, -4))
	FX.placeBeam(ctx, h.cyan, a, b, 0.35, 1)
	FX.placeBeam(ctx, h.cyan2, a + V(0, -2.5, 1), b + V(0, -3, 1), 0.22, 0.8)
	ctx:bloom(1.4)
	grade(ctx, 0, 0.2, 0.05, Color3.fromRGB(255, 232, 248))
	Field.mist(ctx, "pink", 24, 0.6)
end

-- 13: Yuta fires a cyan blast, Rika's skull over his shoulder
local function fire(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.yuta
	local root = C(YUTA) * CFrame.Angles(0, math.rad(90), 0)
	local yb = ctx:rig("Yuta", root, Cast.yuta.fire)
	ctx:rig("Rika", root * C(1.2, -1.5, 5), Cast.add(Cast.rika.embrace, "Head", R(42, -18, 0)))
	Cast.expr(ctx, "yuta", "shout")
	local hand = (yb.RightHand * C(0, -0.5, 0)).Position
	local cam = Util.lookAt(root:PointToWorldSpace(V(-5.2, 4.6, -8.2)), root:PointToWorldSpace(V(0, 6.2, 0.6)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.3, 20), 62)
	ctx:focus(7, 1)
	FX.placeBeam(ctx, h.cyan, hand, hand + root.LookVector * 40, 1.6, 1)
	ctx:light("RikaMouth", 3, nil, 20)
	ctx:bloom(2.2)
	grade(ctx, 0.03, 0.2, 0.05)
	Field.mist(ctx, "wisps", 12)
end

-- 14 / 15: Yuta's face with Rika's long fingers beside it, then a white-out
local function face(ctx: Timeline.Ctx)
	local root = C(YUTA) * CFrame.Angles(0, math.rad(90), 0)
	local yb = ctx:rig("Yuta", root, Cast.add(Cast.yuta.fire, "Head", R(-4, -18, 0)))
	ctx:rig("Rika", root * C(2.6, -2.2, 3.2), Cast.add(Cast.add(Cast.rika.embrace, "RightUpperArm", R(20, 0, -20)), "Head", R(10, -25, 0)))
	Cast.expr(ctx, "yuta", "focus")
	local head = yb.Head * C(0, 0.6, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(-0.9, -0.1, -2.6 + ctx.u * 0.15)), head.Position + V(0.2, -0.05, 0))
	ctx:camera(cam, 45)
	ctx:focus(2.6, 1)
	ctx:light("YutaAura", 2, Color3.fromRGB(150, 220, 255), 10)
	grade(ctx, 0.02, 0.18, -0.05, Color3.fromRGB(225, 240, 255))
	Field.mist(ctx, "wisps", 10)
end

local function whiteout(ctx: Timeline.Ctx)
	face(ctx)
	ctx:flash(Color3.new(1, 1, 1), math.clamp(ctx.u * 1.4, 0, 1))
	ctx:bloom(1 + ctx.u * 3)
end

-- 22: inside a grey cloud of smoke, a pink point of light grows
local function smoke(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.yuta
	local cam = Util.lookAt(Field.RYU + V(4, 4, -10), Field.RIKA + V(0, 6, 0))
	ctx:camera(cam, 55)
	ctx:focus(30, 0)
	FX.placeCore(ctx, h.pinkCore, Field.RIKA + V(-2, 7, 0), 0.6 + ctx.u * 0.8, 1)
	ctx:fog(2.5)
	grade(ctx, 0, 0.05, -0.4)
	Field.mist(ctx, "heavy", 8)
end

-- 23: Rika fires her beam across the frame
local function rikaFires(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.yuta
	local root = C(Field.RIKA + V(4, 0, 0)) * CFrame.Angles(0, math.rad(84), 0)
	local bones = ctx:rig("Rika", root, Cast.rika.roar)
	local mouth = (bones.Head * C(0, 0.7, -1.9)).Position
	-- her skull in the upper right, the beam sweeping out to the left
	local cam = Util.lookAt(mouth + V(-6.5, -3.2, 12), mouth + V(-6.5, -1.6, 0))
	ctx:camera(Clash.shake(cam, ctx.t, 0.5, 22), 62)
	ctx:focus(14, 0)
	FX.placeBeam(ctx, h.pink, mouth, mouth + root.LookVector * 90 + V(0, -3, 0), 4.5 + ctx.u * 2, 1, 2)
	ctx:light("RikaMouth", 8, nil, 40)
	ctx:bloom(2.4)
	grade(ctx, 0.04, 0.2, 0.05, Color3.fromRGB(255, 232, 248))
	Field.mist(ctx, "pink", 16, 1)
end

-- 24: running feet over the cracked ice
local function feet(ctx: Timeline.Ctx)
	local p0 = Field.RYU + V(10, 0, -4)
	local pos = p0 + V(-8 + ctx.u * 16, 0, 0)
	ctx:rig("Yuta", C(pos) * CFrame.Angles(0, math.rad(-90), 0), Cast.run(ctx.t * 2.8, 24))
	Cast.expr(ctx, "yuta", "focus")
	local cam = Util.lookAt(p0 + V(0, 5.5, 6), p0 + V(0, 0, 0))
	ctx:camera(cam, 55)
	ctx:focus(7, 1)
	grade(ctx, 0, 0.15, -0.1, Color3.fromRGB(215, 230, 255))
	Field.snow(ctx, 90)
end

-- 31: charging straight at the camera through mist and purple sparks
local function charge(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.yuta
	-- slow motion: the stride and the ground covered slow down together
	-- (1 run cycle a second = ~5 studs a second, no sliding feet), the camera
	-- holds still so he comes out of the mist towards it; sparks drift slowly
	local start = Field.RYU + V(0, 0, -30)
	local lt = ctx.t - 43.867
	local pos = start + V(0, 0, lt * 4.8)
	local yb = ctx:rig("Yuta", C(pos) * CFrame.Angles(0, math.rad(180), 0), Cast.run(0.15 + lt * 1.0, 28))
	Cast.expr(ctx, "yuta", "focus")
	local head = yb.Head * C(0, 0.6, 0)
	local camPos = start + V(0.7, 4.0, 13.5)
	local cam = Util.lookAt(camPos, start + V(0, 3.3, lt * 4.8))
	ctx:camera(Clash.shake(cam, ctx.t, 0.04, 3), 50)
	ctx:focus((head.Position - camPos).Magnitude, 1)
	FX.placeBurst(ctx, h.sparks, head.Position + V(4, 0, 2), lt % 1.3, 12, 0.22, 1.3, V(-1, 0.1, 0.4), 0.5, 0)
	ctx:alpha("streaks", 0.85)
	grade(ctx, -0.02, 0.15, -0.05, Color3.fromRGB(230, 225, 255))
	Field.mist(ctx, "heavy", 12)
end

-- 32: close-up, determined, blood soaked shoulder
local function closeUp(ctx: Timeline.Ctx)
	local root = C(Field.RYU + V(0, 0, -24)) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", root, Cast.alive(Cast.add(Cast.run(ctx.t * 1.4, 10), "Head", R(-10, 0, 0)), ctx.t))
	local head = yb.Head * C(0, 0.6, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(0.2, 0.9, -2.6)), head.Position + V(0, -0.35, 0))
	ctx:camera(Clash.shake(cam, ctx.t, 0.05, 6), 50)
	ctx:focus(2.8, 1)
	-- Ryu's lines here are voice-over: Yuta keeps his mouth shut
	Cast.expr(ctx, "yuta", "focus")
	ctx:alpha("streaks", math.clamp(1 - (ctx.t - 45.4) / 0.8, 0, 0.9))
	grade(ctx, 0, 0.16, -0.08, Color3.fromRGB(228, 236, 255))
	Field.mist(ctx, "wisps", 14)
end

-- 33: behind Yuta, running at Ryu through flying debris; the camera overtakes him
local function behind(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.yuta
	local start = Field.RYU + V(0, 0, -36)
	local pos = start + V(0, 0, ctx.u * 7)
	ctx:rig("Yuta", C(pos) * CFrame.Angles(0, math.rad(180), 0), Cast.run(ctx.t * 2.8, 24))
	local ryu = ctx:rig("Ryu", C(Field.RYU) * CFrame.Angles(0, math.rad(0), 0), Cast.ryu.spread)
	-- low behind him, catching up until his back fills the right of the frame
	-- and Ryu shows up past his arm (focus pulls from Yuta to Ryu)
	local k = Util.smoothstep(0, 1, ctx.u)
	local camPos = pos + V(-0.6 + k * 2.3, 1.9 - k * 0.4, -6.8 + k * 4.4)
	local target = (pos + V(0, 3.6, 0)):Lerp(Field.RYU + V(0, 3.4, 0), k)
	local cam = Util.lookAt(camPos, target)
	ctx:camera(Clash.shake(cam, ctx.t, 0.15, 12), 55)
	ctx:focus(Util.lerp(6.8, (Field.RYU - camPos).Magnitude, k), 1)
	Cast.expr(ctx, "ryu", "grin")
	Cast.ryuAura(ctx, ryu, 1, 6)
	FX.placeBurst(ctx, h.debris, pos + V(0, 2, 6), ctx.lt % 1.1, 22, 0.7, 1.1, V(0, 0.6, -1), 1.2, 14)
	ctx:fog(1.6)
	grade(ctx, 0.04, 0.12, -0.15)
	Field.mist(ctx, "heavy", 16)
end

YutaShots.shots = {
	{ id = "06 embrace", t0 = 9.6, t1 = 10.867, run = embrace },
	{ id = "13 fire", t0 = 21.367, t1 = 21.533, run = fire },
	{ id = "14 face", t0 = 21.533, t1 = 21.867, run = face },
	{ id = "15 whiteout", t0 = 21.867, t1 = 22.333, run = whiteout },
	{ id = "22 smoke", t0 = 33.867, t1 = 34.1, run = smoke },
	{ id = "23 rika fires", t0 = 34.1, t1 = 34.6, run = rikaFires },
	{ id = "24 feet", t0 = 34.6, t1 = 35.1, run = feet },
	{ id = "31 charge", t0 = 43.867, t1 = 44.8, run = charge },
	{ id = "32 close-up", t0 = 44.8, t1 = 49.3, run = closeUp },
	{ id = "33 behind", t0 = 49.3, t1 = 50.4, run = behind },
} :: { Timeline.Shot }

return YutaShots
