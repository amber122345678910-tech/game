--!strict
-- Ryu's shots on the frozen field.
--   7 10.867-12.100 low angle, arm raised, shards      9 15.233-19.933 close-up, talks
--  17 22.567-25.067 on the cracked ice by the crater  18 25.067-27.467 grins, wind
--  19 27.467-29.833 seen from behind, pink glow ahead 20 29.833-31.400 "That's right!"
--  21 31.400-33.867 "Let's keep going!"               26 35.600-36.867 top view: trench
--  27 36.867-39.933 lightning claw, Yuta runs behind  28 39.933-41.300 "But..."
--  30 42.200-43.867 Granite Blast at dashing Yuta     34 50.400-53.967 push-in, lightning
--  36 54.100-55.867 extreme close-up                  37 55.867-56.733 dark silhouette
--  38 56.733-58.533 "Granite Blast!", arms spread
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local Rig = require(script.Parent.Parent.Rig)
local FX = require(script.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Util)
local Cast = require(script.Parent.Cast)
local Field = require(script.Parent.Field)
local Clash = require(script.Parent.Clash)

local RyuShots = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

type H = {
	beam: FX.Beam,
	pinkBeam: FX.Beam,
	pinkCore: Builder.PartSpec,
	shards: FX.Burst,
	bolts: FX.Bolt,
	headGlow: Builder.PartSpec,
}

function RyuShots.build(scene: Builder.Scene)
	local pal = scene.style.color
	local h: H = {
		beam = FX.beam(scene, "GraniteBlast", pal.eCyan, true),
		pinkBeam = FX.beam(scene, "RikaBeamFar", pal.ePink, false),
		pinkCore = FX.core(scene, "PinkGlow", pal.ePink),
		shards = FX.burst(scene, "RyuShards", pal.eCyan, 26, "Wedge", 21),
		bolts = FX.bolts(scene, "RyuYellowBolts", pal.eYellow, 24),
		headGlow = FX.core(scene, "RyuHeadGlow", pal.eCyan),
	}
	scene.data.ryu = h
end

-- Ryu standing at `pos` facing `yaw` degrees (0 = -Z, -90 = +X)
local function rootAt(pos: Vector3, yaw: number): CFrame
	return C(pos) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function sky(ctx: Timeline.Ctx, mistName: string?, depth: number?)
	Field.snow(ctx, 120)
	if mistName then
		Field.mist(ctx, mistName, depth or 30, 0.4)
	end
end

local function grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	ctx:grade({ brightness = b, contrast = c, saturation = s, tint = tint or Color3.fromRGB(232, 238, 255) })
end

-- 7: low angle from the front, arm thrown up, cyan shards and pink lines
-- left arm thrown up (mirror of Cast.ryu.raise), seen from the front
local raiseLeft: Rig.Pose = {
	UpperTorso = R(-10, -10, 0),
	Head = R(-14, 8, 0),
	LeftUpperArm = R(165, 0, -18),
	LeftLowerArm = R(14, 0, 0),
	RightUpperArm = R(12, 0, 38),
	RightLowerArm = R(34, 0, 0),
}

local function raise(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.mix(Cast.ryu.point, raiseLeft, ctx.u * 3), ctx.t))
	-- very low in front of him, looking up past his face at the raised hand
	local cam = Util.lookAt(root:PointToWorldSpace(V(-1.4, 0.9, -5.4)), root:PointToWorldSpace(V(-0.9, 6.0, 0)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.35), 62)
	ctx:focus(5.6, 1)
	Cast.expr(ctx, "ryu", "grin")
	Cast.ryuAura(ctx, bones, 1, 6)
	local hand = (bones.LeftHand * C(0, -0.6, 0)).Position
	FX.placeBurst(ctx, h.shards, hand, ctx.lt % 0.8, 26, 0.7, 0.7, V(-0.4, 1, -0.2), 1.2, 6)
	FX.placeCore(ctx, h.headGlow, hand, 0.7 + math.sin(ctx.t * 24) * 0.1, 0.9)
	ctx:light("RyuHand", 5, nil, 18)
	ctx:alpha("streaks", 0.55)
	ctx:bloom(1.8)
	-- deep night blue like the reference
	grade(ctx, -0.12, 0.25, 0.3, Color3.fromRGB(160, 190, 255))
	sky(ctx)
end

-- 9: close-up, three-quarter, aura crackling: "That was seriously sweet, Okkotsu!"
local function talk(ctx: Timeline.Ctx)
	local root = rootAt(Field.RYU, -90)
	local laugh = if ctx.t > 16.0 then 1 else 0.3
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.point, "Head", R(4, 22, -4)), ctx.t, laugh * 0.5))
	local head = bones.Head * C(0, 0.75, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(-2.1 + ctx.u * 0.3, -0.05, -4.0 + ctx.u * 0.5)), head.Position + V(0, -0.3, 0))
	ctx:camera(Clash.shake(cam, ctx.t, 0.12, 8), 40)
	ctx:focus(3.4, 1)
	if ctx.t < 16.05 then
		Cast.expr(ctx, "ryu", "grin")
	else
		Cast.talk(ctx, "ryu", "grin", "laugh")
	end
	Cast.ryuAura(ctx, bones, 1, 7)
	ctx:light("RyuFace", 1.6, nil, 9)
	ctx:bloom(1.6)
	grade(ctx, 0, 0.18, -0.12)
	sky(ctx, "wisps", 26)
end

-- 17: standing on the cracked ice, crater ahead, arm out
local function onIce(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local dir = (Field.CRATER - Field.RYU)
	local yaw = math.deg(math.atan2(-dir.X, -dir.Z))
	local root = rootAt(Field.RYU, yaw)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.point, ctx.t))
	local cam = Util.lookAt(root:PointToWorldSpace(V(5.5 - ctx.u * 0.8, 3.2, 8.5)), root:PointToWorldSpace(V(-1.5, 2.6, -8)))
	ctx:camera(cam, 55)
	ctx:focus(10, 1)
	Cast.expr(ctx, "ryu", "glare")
	Cast.ryuAura(ctx, bones, 0.5, 3)
	local hand = (bones.RightHand * C(0, -0.7, 0)).Position
	if ctx.lt > 0.4 and ctx.lt < 0.9 then
		local k = 1 - math.abs(ctx.lt - 0.65) / 0.25
		FX.placeBeam(ctx, h.beam, hand, hand + root.LookVector * 60 + V(0, -2, 0), 0.4, k)
	end
	grade(ctx, 0, 0.12, -0.18)
	sky(ctx, "low", 22)
end

-- 18: front, low angle, grinning, lightning on the arm, wind
local function grin(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -60)
	local pose = Cast.alive(Cast.add(Cast.ryu.spread, "RightUpperArm", R(-40, 0, -30)), ctx.t)
	local bones = ctx:rig("Ryu", root, pose)
	local head = bones.Head * C(0, 0.7, 0)
	local cam = Util.lookAt(root:PointToWorldSpace(V(-1.0, 2.6, -5.2 + ctx.u * 0.6)), head.Position + V(0, -0.6, 0))
	ctx:camera(cam * CFrame.Angles(0, 0, math.rad(-6)), 48)
	ctx:focus(5, 1)
	Cast.expr(ctx, "ryu", "grin")
	local idx = 1
	local hand = (bones.RightHand * C(0, -0.4, 0)).Position
	local shoulder = (bones.RightUpperArm).Position
	for i = 1, 4 do
		idx = FX.placeBolt(ctx, h.bolts, idx, shoulder, hand + V(math.sin(i) * 0.5, math.cos(i) * 0.4, 0), 6, 0.18, 0.06, i + 30, 16)
	end
	Cast.ryuAura(ctx, bones, 0.8, 4)
	ctx:alpha("wind", 0.8)
	grade(ctx, 0.02, 0.16, -0.1)
	sky(ctx)
end

-- 19: from behind, Ryu faces a pink glow approaching through the mist
local function backView(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "LeftUpperArm", R(0, 0, 45)), ctx.t))
	local cam = Util.lookAt(root:PointToWorldSpace(V(0.6, 3.4, 12 - ctx.u * 1.5)), root:PointToWorldSpace(V(0.4, 3.2, -10)))
	ctx:camera(cam, 50)
	ctx:focus(12, 1)
	Cast.expr(ctx, "ryu", "glare")
	Cast.ryuAura(ctx, bones, 0.6, 3)
	local far = root:PointToWorldSpace(V(4, 6, -70))
	FX.placeCore(ctx, h.pinkCore, far, 6 + math.sin(ctx.t * 12) * 0.6, 0.9)
	local k = math.clamp((ctx.lt - 0.3) / 0.4, 0, 1)
	FX.placeBeam(ctx, h.pinkBeam, far, far:Lerp(root:PointToWorldSpace(V(2, 4, -12)), 0.6), 2.5, k * 0.9)
	ctx:fog(1.6)
	ctx:bloom(1.8)
	grade(ctx, 0.02, 0.1, -0.05, Color3.fromRGB(245, 232, 255))
	sky(ctx, "pink", 30)
end

-- 20: "That's right!" arms flung wide, laughing
local function thatsRight(ctx: Timeline.Ctx)
	local root = rootAt(Field.RYU, -70)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.mix(Cast.ryu.spread, Cast.ryu.laughBack, 0.4), ctx.t, 1))
	local head = bones.Head * C(0, 0.7, 0)
	-- head-and-shoulders close-up from slightly below, like the reference
	local cam = Util.lookAt(head:PointToWorldSpace(V(-1.5, -1.1, -4.8 + ctx.u * 0.3)), head.Position + V(0, -0.9, 0))
	ctx:camera(cam, 46)
	ctx:focus(4.8, 1)
	Cast.talk(ctx, "ryu", "laugh", "grin")
	Cast.ryuAura(ctx, bones, 0.4, 3)
	ctx:alpha("wind", 0.4)
	grade(ctx, 0.03, 0.15, -0.08)
	sky(ctx)
end

-- 21: "Let's keep going!" laughing up into a cyan glare, yellow bolt across
local function keepGoing(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -70)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.laughBack, ctx.t, 1))
	local head = bones.Head * C(0, 0.7, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(-0.6, -1.0, -3.6 + ctx.u * 0.4)), head.Position + V(0, -0.5, 0))
	ctx:camera(Clash.shake(cam, ctx.t, 0.1, 10), 44)
	ctx:focus(3.6, 1)
	Cast.talk(ctx, "ryu", "laugh", "shout")
	Cast.ryuAura(ctx, bones, 1, 6)
	ctx:light("RyuFace", 2.4, nil, 10)
	FX.placeCore(ctx, h.headGlow, head:PointToWorldSpace(V(2.2, 2.2, -0.4)), 0.9, 0.7)
	local a = head:PointToWorldSpace(V(-5, -2.2, -1))
	FX.placeBolt(ctx, h.bolts, 1, a, a + head:VectorToWorldSpace(V(10, 0.8, 0)), 10, 0.06, 0.05, 77, 12)
	ctx:bloom(1.5)
	grade(ctx, 0.02, 0.2, -0.1)
	sky(ctx, "wisps", 24)
end

-- 26: top view, the pink beam ploughs the trench towards a tiny Ryu
local function topDown(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local tr = ctx.scene.data.trench
	local root = rootAt(Field.RYU, -60)
	local bones = ctx:rig("Ryu", root, Cast.ryu.blast)
	local mid = (tr.from + tr.to) / 2
	local cam = Util.lookAt(mid + V(-6, 95 - ctx.u * 8, 18), mid, V(1, 0, 0))
	ctx:camera(cam * CFrame.Angles(0, 0, math.rad(8)), 50)
	ctx:focus(95, 0)
	local head = tr.from:Lerp(tr.to, Field.trenchProgress(ctx.t))
	FX.placeBeam(ctx, h.pinkBeam, tr.from + V(0, 3, 0), head + V(0, 1.5, 0), 4.5, 1)
	Cast.ryuAura(ctx, bones, 1, 4)
	ctx:fog(0.6)
	ctx:bloom(2)
	grade(ctx, 0, 0.15, 0)
end

-- 27: over the shoulder: lightning claw, Yuta sprinting in the distance
local function claw(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.claw, ctx.t))
	local yutaPos = root:PointToWorldSpace(V(-6 + ctx.u * 14, 0, -22))
	ctx:rig("Yuta", C(yutaPos) * CFrame.Angles(0, math.rad(-90 - 90), 0), Cast.run(ctx.t * 2.4, 22))
	Cast.expr(ctx, "yuta", "focus")
	local cam = Util.lookAt(root:PointToWorldSpace(V(1.9, 5.4, 2.6)), root:PointToWorldSpace(V(-1.2, 3.2, -14)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.08, 8), 50)
	ctx:focus(14, 1)
	Cast.expr(ctx, "ryu", "glare")
	local hand = (bones.RightHand * C(0, -0.5, 0)).Position
	local idx = 1
	for i = 1, 4 do
		idx = FX.placeBolt(ctx, h.bolts, idx, hand, hand + root:VectorToWorldSpace(V(math.sin(i * 1.3) * 4, math.cos(i) * 2, -6 - i)), 7, 0.22, 0.05, i + 50, 14)
	end
	Cast.ryuAura(ctx, bones, 1, 6)
	ctx:light("RyuHand", 4, nil, 14)
	ctx:emit("RyuHandSparks", 60)
	ctx:bloom(1.8)
	grade(ctx, -0.02, 0.18, -0.1)
	sky(ctx, "low", 26)
end

-- 28: "But..." low angle close-up, arm drawn back
local function but(ctx: Timeline.Ctx)
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.mix(Cast.ryu.claw, Cast.ryu.windup, ctx.u), ctx.t))
	local head = bones.Head * C(0, 0.7, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(-2.0, -1.6, -3.4)), head.Position + V(0, -0.4, 0))
	ctx:camera(cam * CFrame.Angles(0, 0, math.rad(8)), 46)
	ctx:focus(4, 1)
	if ctx.t < 41.1 then
		Cast.talk(ctx, "ryu", "smirk", "talk")
	else
		Cast.expr(ctx, "ryu", "smirk")
	end
	Cast.ryuAura(ctx, bones, 1, 6)
	ctx:light("RyuFace", 1.8, nil, 9)
	ctx:bloom(1.7)
	grade(ctx, -0.02, 0.2, -0.12)
	sky(ctx, "wisps", 24)
end

-- 30: Granite Blast fired at Yuta, who dashes through the mist
local function blast(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.blast, ctx.t))
	local yutaPos = root:PointToWorldSpace(V(-2.5 + ctx.u * 2, 0, -16 + ctx.u * 5))
	ctx:rig("Yuta", C(yutaPos) * CFrame.Angles(0, math.rad(-90 + 180), 0), Cast.run(ctx.t * 2.6, 26))
	Cast.expr(ctx, "yuta", "focus")
	local cam = Util.lookAt(root:PointToWorldSpace(V(-9, 3.4, -3)), root:PointToWorldSpace(V(-1, 3, -9)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.15, 14), 55)
	ctx:focus(9, 1)
	Cast.expr(ctx, "ryu", "grin")
	local hand = (bones.RightHand * C(0, -0.6, 0)).Position
	local pulse = 0.6 + 0.4 * math.abs(math.sin(ctx.t * 9))
	FX.placeBeam(ctx, h.beam, hand, hand + root.LookVector * 22 + root.RightVector * -2, 1.2, pulse)
	Cast.ryuAura(ctx, bones, 1, 5)
	ctx:alpha("streaks", 0.7)
	ctx:bloom(2)
	grade(ctx, -0.02, 0.16, -0.08, Color3.fromRGB(238, 230, 255))
	sky(ctx, "low", 24)
end

-- 34: lightning bursts out of him while the camera rushes into his face
local function pushIn(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.spread, ctx.t, 0.4))
	local head = bones.Head * C(0, 0.7, 0)
	local u = ctx.u
	local e = u * u * (3 - 2 * u)
	local far = root:PointToWorldSpace(V(0, 3.4, -13))
	local near = head:PointToWorldSpace(V(-0.3, -0.1, -2.6))
	local cam = Util.lookAt(far:Lerp(near, e), head.Position:Lerp(root:PointToWorldSpace(V(0, 3.3, 0)), 1 - e))
	ctx:camera(Clash.shake(cam, ctx.t, 0.1 + e * 0.25, 12), 50 - e * 8)
	ctx:focus((far - near).Magnitude * (1 - e) + 2.6, 1)
	if ctx.t < 53.7 then
		Cast.talk(ctx, "ryu", "grin", "talk")
	else
		Cast.expr(ctx, "ryu", "grin")
	end
	Cast.ryuAura(ctx, bones, 1, 8)
	local idx = 1
	local c = (bones.UpperTorso * C(0, 1.2, 0)).Position
	for i = 1, 3 do
		local a = math.rad(i * 120 + ctx.t * 40)
		idx = FX.placeBolt(ctx, h.bolts, idx, c, c + V(math.cos(a) * 9, 3 + math.sin(i) * 3, math.sin(a) * 9), 7, 0.2, 0.08, i + 90, 14)
	end
	if u > 0.45 then
		FX.placeBurst(ctx, h.shards, head.Position, (ctx.lt - 1.6) % 0.9, 20, 0.5, 0.8, nil, nil, 2)
	end
	ctx:light("RyuFace", 1.2 + e * 1.4, nil, 10)
	ctx:bloom(1.4 + e * 0.3)
	ctx:flash(Color3.new(1, 1, 1), math.max(0, 0.5 - ctx.lt * 2))
	grade(ctx, 0, 0.2, -0.05)
	sky(ctx, "low", 26)
end

-- 36: extreme close-up, tilted, shards flying: "I'll settle this."
local function ecu(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(-6, 10, 12)), ctx.t))
	local head = bones.Head * C(0, 0.7, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(-0.5, 0.1, -1.9 + ctx.u * 0.2)), head.Position + V(0, -0.05, 0))
	ctx:camera(Clash.shake(cam * CFrame.Angles(0, 0, math.rad(-18)), ctx.t, 0.18, 14), 46)
	ctx:focus(1.9, 1)
	if ctx.t < 55.55 then
		Cast.talk(ctx, "ryu", "grin", "talk")
	else
		Cast.expr(ctx, "ryu", "grin")
	end
	-- small shards flying off beside the head, away from the lens
	FX.placeBurst(ctx, h.shards, head:PointToWorldSpace(V(1.3, 0.6, 0.2)), ctx.lt % 0.7, 14, 0.14, 0.6, head.RightVector, 0.8, 0)
	-- the aura without its body bolts: 2 studs from the lens a bolt in front
	-- of the face covers the eyes; crackle beside the head instead
	Cast.ryuAura(ctx, bones, 1, 0)
	local idx = 1
	for i, side in { 1, -1 } do
		local a = head:PointToWorldSpace(V(side * 1.0, 0.8, 0.3))
		idx = FX.placeBolt(ctx, h.bolts, idx, a, a + head:VectorToWorldSpace(V(side * 2.6, 1.4, 0.6)), 8, 0.16, 0.04, 90 + i, 12)
	end
	ctx:light("RyuFace", 2.2, nil, 9)
	ctx:bloom(1.4)
	grade(ctx, 0, 0.22, -0.05)
	sky(ctx, "wisps", 18)
end

-- 37: dark silhouette turning, collar against a dim glow
local function dark(ctx: Timeline.Ctx)
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.mix(Cast.ryu.windup, Cast.ryu.spread, ctx.u))
	local head = bones.Head * C(0, 0.7, 0)
	local cam = Util.lookAt(head:PointToWorldSpace(V(1.4, -0.6, 2.8)), head.Position + V(0, -0.6, 0))
	ctx:camera(cam, 55)
	ctx:focus(3, 1)
	Cast.expr(ctx, "ryu", "grin")
	ctx:light("RyuFace", 2 + ctx.u * 4, nil, 8)
	grade(ctx, -0.35, 0.3, -0.3)
	ctx:fog(1.5)
end

-- 38: "Granite Blast!" — arms spread, blue light flaring at his forehead
local function finale(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.spread, ctx.t, 0.2))
	local head = bones.Head * C(0, 0.7, 0)
	-- low angle from the waist up, the shouting face clearly visible
	local cam = Util.lookAt(root:PointToWorldSpace(V(-1.0, 1.9, -5.2 - ctx.u * 1.5)), root:PointToWorldSpace(V(0, 4.7, 0)))
	ctx:camera(cam, 50)
	ctx:focus(5.6, 1)
	Cast.expr(ctx, "ryu", "shout")
	FX.placeCore(ctx, h.headGlow, head:PointToWorldSpace(V(0.15, 0.3, -0.62)), 0.2 + math.sin(ctx.t * 20) * 0.03, 1)
	ctx:light("RyuFace", 1.8, nil, 10)
	Cast.ryuAura(ctx, bones, 1, 7)
	local w = math.clamp((ctx.lt - 1.2) / 0.6, 0, 1)
	if w > 0 then
		ctx:flash(Color3.fromRGB(225, 238, 255), w * 0.85)
	end
	ctx:fog(1.3 + w)
	ctx:bloom(1.5)
	grade(ctx, 0.02, 0.15, -0.1)
	sky(ctx, "low", 18)
end

RyuShots.shots = {
	{ id = "07 raise", t0 = 10.867, t1 = 12.1, run = raise },
	{ id = "09 talk", t0 = 15.233, t1 = 19.933, run = talk },
	{ id = "17 ice", t0 = 22.567, t1 = 25.067, run = onIce },
	{ id = "18 grin", t0 = 25.067, t1 = 27.467, run = grin },
	{ id = "19 back", t0 = 27.467, t1 = 29.833, run = backView },
	{ id = "20 right", t0 = 29.833, t1 = 31.4, run = thatsRight },
	{ id = "21 going", t0 = 31.4, t1 = 33.867, run = keepGoing },
	{ id = "26 top", t0 = 35.6, t1 = 36.867, run = topDown },
	{ id = "27 claw", t0 = 36.867, t1 = 39.933, run = claw },
	{ id = "28 but", t0 = 39.933, t1 = 41.3, run = but },
	{ id = "30 blast", t0 = 42.2, t1 = 43.867, run = blast },
	{ id = "34 push", t0 = 50.4, t1 = 53.967, run = pushIn },
	{ id = "36 ecu", t0 = 54.1, t1 = 55.867, run = ecu },
	{ id = "37 dark", t0 = 55.867, t1 = 56.733, run = dark },
	{ id = "38 finale", t0 = 56.733, t1 = 58.533, run = finale },
} :: { Timeline.Shot }

return RyuShots
