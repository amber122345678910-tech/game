--!strict
-- Part 2, 5.267-20.300: the Granite Blast fires; Yuta catches it with his
-- left hand, grips the air like a sheet of glass and folds space with Uro's
-- technique, bending the blast up over his head. Ryu's eyes go wide.
--   5.267 star flash      5.400 energy swirl     5.633 launch (high angle)
--   6.133 Ryu, side       6.233 blast front      6.267 Yuta holds the blast
--   8.033 dome of light   9.633 Yuta reaches     11.500 the hand with the ring
--  12.767 Yuta's face    15.800 comet           15.933 bending arc
--  16.300 Ryu's glare    16.467 Ryu's eyes wide  17.033 the blast bends up
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Parent.Util)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Cast = require(script.Parent.Parent.Cast)
local Clash = require(script.Parent.Parent.Clash)
local Common = require(script.Parent.Common)

local Blast = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local WHITE = Color3.new(1, 1, 1)
local CYAN = Color3.fromRGB(120, 230, 255)

local function h(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end

-- where Ryu's blast leaves his head (the tip of the pompadour)
local function blastStart(bones: { [string]: CFrame }): Vector3
	return (bones.Head * C(0, 1.74, -0.72)).Position
end

-- the point where the blast meets Yuta's hand
local function impactPoint(): Vector3
	return Common.YUTA + V(0, 3.4, 3.4)
end

-- the blast bent up over Yuta's head, towards Ryu's right and into the sky
local function bandPoint(i: number, f: number): Vector3
	local bend = impactPoint() + V(0, 0.8, 1.6)
	local off = V((i - 3) * 2.2, (i - 3) * 0.7, 0)
	local p0 = bend + off
	local p1 = bend + V(6, 9, -2) + off * 2
	local p2 = bend + V(40 + (i - 3) * 8, 70, -20)
	local w = 1 - f
	return p0 * (w * w) + p1 * (2 * w * f) + p2 * (f * f)
end
Blast.bandPoint = bandPoint

-- Yuta braced in profile, left hand out flat against the blast
local holdBeam: Rig.Pose = {
	LowerTorso = R(-8, -10, 0),
	UpperTorso = R(14, -24, 0),
	Head = R(-8, 18, 0),
	LeftUpperArm = R(88, 0, 4),
	LeftLowerArm = R(6, 0, 0),
	LeftHand = R(-55, 0, 0),
	RightUpperArm = R(-25, 0, 35),
	RightLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(30, 0, -8),
	LeftLowerLeg = R(-34, 0, 0),
	RightUpperLeg = R(-28, 0, 10),
	RightLowerLeg = R(-6, 0, 0),
}

-- from behind: the left arm thrown up and out to the left
local leftUp: Rig.Pose = {
	UpperTorso = R(-6, 10, 0),
	Head = R(-14, 0, 0),
	LeftUpperArm = R(150, 0, -35),
	LeftLowerArm = R(10, 0, 0),
	LeftHand = R(-20, 0, 0),
	RightUpperArm = R(10, 0, 30),
	RightLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(20, 0, -10),
	LeftLowerLeg = R(-25, 0, 0),
	RightUpperLeg = R(-18, 0, 10),
}

-- the left arm reaching into the blast, fingers gripping the air
local function reachPose(k: number): Rig.Pose
	return Cast.mix(holdBeam, {
		UpperTorso = R(4, -20, 0),
		Head = R(-4, 20, 0),
		LeftUpperArm = R(86, 0, 6),
		LeftLowerArm = R(4, 0, 0),
		LeftHand = R(-20, 0, 0),
		RightUpperArm = R(10, 0, 24),
		RightLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(16, 0, -6),
		RightUpperLeg = R(-14, 0, 6),
	}, k)
end
Blast.reachPose = reachPose
Blast.blastStart = blastStart

local function star(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("p2star")
end

local function swirl(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("p2swirl")
	ctx:flash(WHITE, Util.smoothstep(0.45, 1, ctx.u) * 0.95)
end

local function launch(ctx: Timeline.Ctx)
	ctx:wind(2.2)
	ctx:gust(1.2 * math.exp(-ctx.lt * 3))
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.add(Cast.ryu.spread, "Head", R(14, 0, 0)))
	Cast.expr(ctx, "ryu", "shout")
	ctx:rig("Yuta", Common.yutaRoot(), holdBeam)
	local a = blastStart(bones)
	local k = Util.smoothstep(0, 0.4, ctx.lt)
	local front = a:Lerp(impactPoint(), k)
	FX.placeBeam(ctx, hh.blast, a, front, 2.6 + k * 2, 1)
	FX.placeCore(ctx, hh.blastCore, front, 1.8 + k * 0.8, 1)
	FX.placeCore(ctx, hh.blastHalo, front, 3.5 + k, 0.3)
	FX.placeBurst(ctx, hh.debris, Common.RYU + V(0, 0.5, -6), ctx.lt, 26, 1.1, 0.8, V(0, 0.5, -1), 0.9, 30)
	local cam = Util.lookAt(Common.RYU + V(10, 30, 16), Common.RYU + V(0, 0, -12))
	ctx:camera(Clash.shake(cam, ctx.t, 0.4, 16), 55)
	ctx:focus(40, 0)
	Cast.ryuAura(ctx, bones, 1, 5)
	ctx:bloom(1.6)
	Common.grade(ctx, -0.12, 0.25, 0.1, Color3.fromRGB(190, 215, 255))
	Common.sky(ctx, "wisps", 40)
end

local function side(ctx: Timeline.Ctx)
	ctx:wind(2.5)
	ctx:gust(1)
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.add(Cast.ryu.spread, "Head", R(14, 0, 0)))
	Cast.expr(ctx, "ryu", "shout")
	local a = blastStart(bones)
	FX.placeBeam(ctx, hh.blast, a, a + V(0, -1, -30), 4, 1)
	local cam = Util.lookAt(root:PointToWorldSpace(V(-9, 3.6, -1)), root:PointToWorldSpace(V(0, 4.2, -1.5)))
	ctx:camera(cam, 50)
	ctx:focus(9, 1)
	ctx:bloom(1.8)
	Common.grade(ctx, -0.45, 0.35, 0.1, Color3.fromRGB(170, 200, 255))
end

local function crescent(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("p2crescent")
end

-- wide, Yuta at the left in profile holding the blast back with his left
-- hand; purple-pink waves of Rika's energy around him, rock flying
local function engulf(ctx: Timeline.Ctx)
	ctx:wind(2.6)
	ctx:gust(0.6 + 0.6 * math.max(0, math.sin(ctx.t * 4.3)))
	local hh = h(ctx)
	-- the stream shoves him back, feet scraping, the whole body straining
	local push = ctx.lt * 0.7 + Util.noise1(ctx.t * 5, 21) * 0.08
	local yroot = Common.yutaRoot() * C(0, 0, push)
	local tr = Util.noise1(ctx.t * 12, 22)
	local strain = Cast.add(Cast.add(holdBeam, "UpperTorso", R(tr * 2.5, tr * 3, 0)), "LeftUpperArm", R(tr * 3, 0, tr * 2))
	strain = Cast.add(strain, "Head", R(-tr * 3, Util.noise1(ctx.t * 3, 23) * 6, 0))
	local yb = ctx:rig("Yuta", yroot, Cast.alive(strain, ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local rbones = ctx:rig("Ryu", Common.ryuRoot(0), Cast.ryu.spread)
	local palm = (yb.LeftHand * C(0, -0.35, 0)).Position
	FX.placeBurst(ctx, hh.dust, yroot:PointToWorldSpace(V(0, 0.2, -0.6)), ctx.lt % 0.4, 8, 0.4, 0.4, V(0, 0.6, -1), 0.8, 20)
	local ip = palm + V(0, 0, 1.6)
	FX.placeBeam(ctx, hh.blast, blastStart(rbones), ip, 2.4, 0.85, 2)
	local fl = 1 + math.sin(ctx.t * 41) * 0.08
	FX.placeCore(ctx, hh.blastCore, ip, 0.7 * fl, 1)
	FX.placeCore(ctx, hh.blastHalo, ip, 1.5 * fl, 0.2)
	FX.placeCore(ctx, hh.pinkGlow, Common.YUTA + V(0, 3.2, 1.6), 2.4, 0.3)
	FX.placeBurst(ctx, hh.shards, ip, ctx.lt % 0.55, 30, 0.6, 0.55, V(0.2, 0.4, -1), 0.8, 4)
	FX.placeBurst(ctx, hh.debris, ip + V(0, -2.8, 0), (ctx.lt + 0.25) % 0.7, 22, 0.9, 0.7, V(0.3, 0.7, -1), 0.9, 25)
	Common.streamers(ctx, hh.streamers, Common.YUTA + V(0, 3.4, 0), V(0, 0, -1), 6, 5, 120, 0.85)
	-- the camera pans left along the beam, Yuta stays at the left
	local eye = Common.YUTA + V(-14, 3, 4 - ctx.u * 1.5)
	local look = Common.YUTA + V(0, 3.2, 8 - ctx.u * 3)
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.35, 16), 50)
	ctx:focus(14, 1)
	ctx:light("YutaAura", 2, nil, 16)
	ctx:bloom(1.3)
	Common.grade(ctx, -0.06, 0.3, 0.2, Color3.fromRGB(205, 235, 255))
end

-- from behind Yuta: a dome of light with pink-violet edges, his silhouette
-- throwing the left arm up and out
local function dome(ctx: Timeline.Ctx)
	ctx:wind(2.6)
	ctx:gust(0.8 + 0.5 * math.max(0, math.sin(ctx.t * 3.7)))
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	ctx:rig("Yuta", yroot, Cast.alive(Cast.mix(holdBeam, leftUp, Util.smoothstep(0, 0.6, ctx.u)), ctx.t))
	local ip = impactPoint() + V(0, 0.8, 6)
	local grow = 1 + ctx.u * 0.35
	FX.placeCore(ctx, hh.blastCore, ip, 2.4 * grow, 1)
	FX.placeCore(ctx, hh.blastHalo, ip, 5 * grow, 0.3)
	FX.placeCore(ctx, hh.pinkGlow, ip + V(4, -1, -3), 2.2, 0.4)
	FX.placeRays(ctx, hh.rays, ip, C(), 18, 0.35, 0.7, 14, V(0, 0, -1))
	FX.placeBurst(ctx, hh.debris, ip, ctx.lt % 0.8, 22, 1.0, 0.8, V(0, 0.4, -1), 1, 2)
	FX.placeBurst(ctx, hh.shards, ip, (ctx.lt + 0.4) % 0.8, 26, 0.8, 0.8, V(0, 0.5, -1), 1, 2)
	local cam = Util.lookAt(yroot:PointToWorldSpace(V(0.8, 2.3, 7.5)), yroot:PointToWorldSpace(V(0, 3.8, -6)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.35, 14), 60)
	ctx:focus(7.5, 1)
	ctx:light("YutaAura", 1.5, nil, 14)
	ctx:bloom(1.5)
	ctx:flash(WHITE, Util.smoothstep(0.8, 1, ctx.u) * 0.6)
	Common.grade(ctx, -0.05, 0.25, 0.1, Color3.fromRGB(215, 240, 255))
end

-- profile: his left hand reaches into the blast and grips the air
local function reach(ctx: Timeline.Ctx)
	ctx:wind(1.8)
	ctx:gust(0.3)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local k = Util.smoothstep(10.25, 11.0, ctx.t)
	local yb = ctx:rig("Yuta", yroot, Cast.alive(reachPose(k), ctx.t))
	Cast.expr(ctx, "yuta", "smirk")
	local head = yb.Head * C(0, 0.55, 0)
	local hand = (yb.LeftHand * C(0, -0.35, 0)).Position
	local eye = yroot:PointToWorldSpace(V(4.0, 3.9, 0.6 - k * 1.4))
	local target = head.Position:Lerp(hand, k * 0.55) + V(0, -0.2, 0)
	ctx:camera(Clash.shake(Util.lookAt(eye, target), ctx.t, 0.06, 8), 48)
	ctx:focus((target - eye).Magnitude, 1)
	FX.placeRing(ctx, hh.pane, hand + yroot.LookVector * 0.6, yroot.LookVector, 0.6 + k * 3, 0.03, 0.3 * k)
	Common.streamers(ctx, hh.streamers, Common.YUTA + V(0, 3.4, 1), V(0, 0, -1), 3.4, 4, 110, 0.85)
	ctx:light("YutaAura", 2.2, CYAN, 12)
	ctx:bloom(1.4)
	Common.grade(ctx, -0.02, 0.22, 0.15, Color3.fromRGB(200, 215, 255))
end

-- the left hand with the ring: fingers clawing the air like a pane of glass
local function hand(ctx: Timeline.Ctx)
	ctx:wind(1.6)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local yb = ctx:rig("Yuta", yroot, Cast.add(reachPose(1), "LeftHand", R(-10 - ctx.u * 25, 0, 0)))
	Cast.expr(ctx, "yuta", "smirk")
	local palm = (yb.LeftHand * C(0, -0.3, 0)).Position
	local fwd = yroot.LookVector
	local eye = palm - fwd * 1.6 - yroot.RightVector * 2.4 + V(0, 0.8, 0)
	ctx:camera(Clash.shake(Util.lookAt(eye, palm + fwd * 0.9), ctx.t, 0.05, 8), 50)
	ctx:focus((palm - eye).Magnitude, 1)
	local g = Util.smoothstep(0.2, 1, ctx.u)
	for i, ring in hh.rings do
		local gi = math.clamp(g * 1.4 - (i - 1) * 0.25, 0, 1)
		FX.placeRing(ctx, ring, palm + fwd * (0.4 + i * 0.25), fwd, 0.4 + gi * (3 + i * 2), 0.025, 0.22 * gi)
	end
	FX.placeCore(ctx, hh.palmGlow, palm + fwd * 0.35, 0.12 + g * 0.1, 0.5)
	Common.streamers(ctx, hh.streamers, palm + fwd * 3, V(0, 0, -1), 2.6, 3.5, 110, 0.6)
	ctx:light("YutaAura", 1.2, CYAN, 10)
	ctx:bloom(1.2)
	Common.grade(ctx, 0, 0.22, 0.15, Color3.fromRGB(205, 210, 255))
end

-- Yuta's face from a little above: a cold look and a half-smile; he pulls
-- the sky to the side with his left hand; Ryu's thoughts over it
local function face(ctx: Timeline.Ctx)
	ctx:wind(1.6)
	ctx:gust(0.25)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local pull = Util.smoothstep(0.2, 0.9, ctx.u)
	local pose = Cast.add(reachPose(1), "Head", R(-10, -12 + ctx.u * 6, 0))
	pose = Cast.add(pose, "LeftUpperArm", R(0, 0, -30 * pull))
	local yb = ctx:rig("Yuta", yroot, Cast.alive(pose, ctx.t))
	Cast.expr(ctx, "yuta", "smirk")
	local head = yb.Head * C(0, 0.6, 0)
	local eye = head:PointToWorldSpace(V(0.35 - ctx.u * 0.15, 0.55, -2.8 + ctx.u * 0.35))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.05, 0)), ctx.t, 0.04, 6), 46)
	ctx:focus(2.8, 1)
	Common.streamers(ctx, hh.streamers, head.Position + yroot.LookVector * 2.2, V(-1, 0, -0.4), 1.6, 1.8, 70, 0.55)
	local fl = 0.75 + 0.25 * math.sin(ctx.t * 13) * math.sin(ctx.t * 7.3)
	ctx:light("YutaAura", 2.4 * fl, CYAN, 10)
	ctx:bloom(1.4)
	ctx:flash(WHITE, Util.smoothstep(0.9, 1, ctx.u) * 0.85)
	Common.grade(ctx, -0.04, 0.2, 0.1, Color3.fromRGB(210, 222, 255))
end

-- a cyan comet streaking across black
local function comet(ctx: Timeline.Ctx)
	local hh = h(ctx)
	Clash.void(ctx, Color3.fromRGB(2, 3, 8))
	local o = Clash.O
	ctx:camera(C(o + V(0, 0, 40)), 50)
	ctx:focus(40, 0)
	local x = -30 + ctx.u * 40
	FX.placeBeam(ctx, hh.comet, o + V(x - 22, -2, 0), o + V(x, 2, 0), 2.2, 1)
	FX.placeCore(ctx, hh.blastCore, o + V(x, 2, 0), 2.2, 1)
	ctx:bloom(2.0)
end

-- the blast bends: a huge white-blue arc sweeping past the lens
local function arc(ctx: Timeline.Ctx)
	local hh = h(ctx)
	Clash.void(ctx, Color3.fromRGB(120, 140, 175))
	local o = Clash.O
	ctx:camera(C(o + V(0, 0, 30)), 60)
	ctx:focus(30, 0)
	local function pt(f: number): Vector3
		local a = math.rad(200 - f * 150)
		return o + V(math.cos(a) * 26, math.sin(a) * 18 - 6, 8 - f * 6)
	end
	local u = ctx.u
	FX.placeCurvedBeam(ctx, hh.bands[1], pt, math.max(0, u * 1.2 - 0.5), math.min(1, u * 1.4 + 0.2), 7, 0.9)
	FX.placeCurvedBeam(ctx, hh.bands[2], function(f: number): Vector3
		return pt(f) + V(0, -6, 2)
	end, math.max(0, u * 1.2 - 0.6), math.min(1, u * 1.4), 3, 0.8)
	ctx:bloom(1.6)
	Common.grade(ctx, 0.05, 0.2, 0.1, Color3.fromRGB(220, 235, 255))
end

-- Ryu's eyes in the painted close-up: a glare, then wide with shock
local function ryuGlare(ctx: Timeline.Ctx)
	Common.panelCamera(ctx, 430, 470, 300)
	ctx:show("split:ryuGlare")
	ctx:flash(CYAN, 0.45)
	Common.grade(ctx, 0.05, 0.2, 0.1, Color3.fromRGB(210, 240, 255))
end

local function ryuEyes(ctx: Timeline.Ctx)
	Common.panelCamera(ctx, 430, 470, 300 - ctx.u * 40)
	ctx:show("split:ryuShock")
	ctx:flash(CYAN, 0.2 * (1 - ctx.u))
	Common.grade(ctx, 0.05, 0.22, 0.05, Color3.fromRGB(215, 240, 255))
end

-- wide from low at the side: Yuta (lower right) bends the blast in an arc
-- up and over, from lower left to upper right; violet flashes, black shards
local function fold(ctx: Timeline.Ctx)
	ctx:wind(2.4)
	ctx:gust(0.6 + 0.4 * math.max(0, math.sin(ctx.t * 2.9)))
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	ctx:rig("Yuta", yroot, Cast.alive(Cast.add(reachPose(1), "LeftUpperArm", R(40, 0, -20)), ctx.t))
	Cast.expr(ctx, "yuta", "smirk")
	local rbones = ctx:rig("Ryu", Common.ryuRoot(0), Cast.alive(Cast.ryu.spread, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	local bend = impactPoint() + V(0, 0.8, 1.6)
	FX.placeBeam(ctx, hh.blast, blastStart(rbones), bend, 3.6, 0.9, 2)
	FX.placeCore(ctx, hh.blastCore, bend, 1.6, 1)
	FX.placeCore(ctx, hh.blastHalo, bend, 3.4, 0.25)
	FX.placeCore(ctx, hh.pinkGlow, Common.YUTA + V(0.5, 3.6, 1.2), 1.6, 0.45)
	for i, b in hh.bands do
		local head = math.clamp((ctx.lt - (i - 1) * 0.12) / 1.4, 0, 1)
		local tail = math.clamp(head - 0.6, 0, 1)
		FX.placeCurvedBeam(ctx, b, function(f: number): Vector3
			return bandPoint(i, f)
		end, tail, head, if i % 2 == 0 then 1.3 else 2.6, 0.8)
	end
	FX.placeBurst(ctx, hh.debris, bend + V(0, -2, 0), ctx.lt % 0.9, 22, 1.0, 0.9, V(0.4, 1, -0.2), 0.9, 20)
	FX.placeBurst(ctx, hh.shards, bend, (ctx.lt + 0.45) % 0.9, 26, 0.7, 0.9, V(0.5, 1, -0.3), 1, 2)
	local eye = Common.YUTA + V(16, 1.5, 6)
	local look = Util.lookAt(eye, Common.YUTA + V(0, 10, 4))
	ctx:camera(Clash.shake(look, ctx.t, 0.2, 10), 62)
	ctx:focus(17, 0.6)
	ctx:bloom(1.4)
	Common.grade(ctx, -0.12, 0.3, 0.25, Color3.fromRGB(190, 210, 255))
	Common.sky(ctx, "wisps", 50)
end

Blast.shots = {
	{ id = "P2 01 star", t0 = 5.267, t1 = 5.4, run = star },
	{ id = "P2 02 swirl", t0 = 5.4, t1 = 5.633, run = swirl },
	{ id = "P2 03 launch", t0 = 5.633, t1 = 6.133, run = launch },
	{ id = "P2 04 side", t0 = 6.133, t1 = 6.233, run = side },
	{ id = "P2 05 crescent", t0 = 6.233, t1 = 6.267, run = crescent },
	{ id = "P2 06 hold", t0 = 6.267, t1 = 8.033, run = engulf },
	{ id = "P2 07 dome", t0 = 8.033, t1 = 9.633, run = dome },
	{ id = "P2 08 reach", t0 = 9.633, t1 = 11.5, run = reach },
	{ id = "P2 09 hand", t0 = 11.5, t1 = 12.767, run = hand },
	{ id = "P2 10 face", t0 = 12.767, t1 = 15.8, run = face },
	{ id = "P2 11 comet", t0 = 15.8, t1 = 15.933, run = comet },
	{ id = "P2 12 arc", t0 = 15.933, t1 = 16.3, run = arc },
	{ id = "P2 13 glare", t0 = 16.3, t1 = 16.467, run = ryuGlare },
	{ id = "P2 14 eyes", t0 = 16.467, t1 = 17.033, run = ryuEyes },
	{ id = "P2 15 bend", t0 = 17.033, t1 = 20.3, run = fold },
} :: { Timeline.Shot }

return Blast
