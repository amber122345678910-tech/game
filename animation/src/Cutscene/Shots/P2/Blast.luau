--!strict
-- Part 2, 5.267-20.300: the Granite Blast fires and swallows Yuta; inside it
-- Yuta reaches out and folds space with Uro's technique, bending the blast
-- up into the sky. Ryu's eyes go wide.
--   5.267 star flash      5.400 energy swirl     5.633 launch (high angle)
--   6.133 Ryu, side       6.233 blast front      6.267 the blast hits Yuta
--   8.033 dome of light   9.633 Yuta reaches     11.500 the open hand
--  12.767 Yuta's face    15.800 comet           15.933 bending arc
--  16.300 Ryu's glare    16.467 Ryu's eyes wide  17.033 the sky folds
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

-- where Ryu's blast leaves his head
local function blastStart(bones: { [string]: CFrame }): Vector3
	return (bones.Head * C(0, 1.74, -0.72)).Position
end

-- Yuta bracing behind Rika's arms; the point the blast hits in front of him
local function impactPoint(): Vector3
	return Common.YUTA + V(0, 3.2, 3.2)
end

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
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.add(Cast.ryu.spread, "Head", R(14, 0, 0)))
	Cast.expr(ctx, "ryu", "shout")
	ctx:rig("Yuta", Common.yutaRoot(), Cast.yuta.brace)
	local a = blastStart(bones)
	local k = Util.smoothstep(0, 0.4, ctx.lt)
	local front = a:Lerp(impactPoint(), k)
	FX.placeBeam(ctx, hh.blast, a, front, 2.6 + k * 3, 1)
	FX.placeCore(ctx, hh.blastCore, front, 2.4 + k * 1.2, 1)
	FX.placeCore(ctx, hh.blastHalo, front, 5 + k * 2, 0.35)
	FX.placeBurst(ctx, hh.debris, Common.RYU + V(0, 0.5, -6), ctx.lt, 26, 1.1, 0.8, V(0, 0.5, -1), 0.9, 30)
	local cam = Util.lookAt(Common.RYU + V(10, 30, 16), Common.RYU + V(0, 0, -12))
	ctx:camera(Clash.shake(cam, ctx.t, 0.4, 16), 55)
	ctx:focus(40, 0)
	Cast.ryuAura(ctx, bones, 1, 5)
	ctx:bloom(2.2)
	Common.grade(ctx, -0.12, 0.25, 0.1, Color3.fromRGB(190, 215, 255))
	Common.sky(ctx, "wisps", 40)
end

local function side(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.add(Cast.ryu.spread, "Head", R(14, 0, 0)))
	Cast.expr(ctx, "ryu", "shout")
	local a = blastStart(bones)
	FX.placeBeam(ctx, hh.blast, a, a + V(0, -1, -30), 5, 1)
	local cam = Util.lookAt(root:PointToWorldSpace(V(-9, 3.6, -1)), root:PointToWorldSpace(V(0, 4.2, -1.5)))
	ctx:camera(cam, 50)
	ctx:focus(9, 1)
	ctx:bloom(2.4)
	Common.grade(ctx, -0.45, 0.35, 0.1, Color3.fromRGB(170, 200, 255))
end

local function crescent(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("p2crescent")
end

-- Yuta braced, Rika's arms around him, the blast pouring in from the right
local function engulf(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	ctx:rig("Yuta", yroot, Cast.alive(Cast.yuta.brace, ctx.t))
	ctx:rig("Rika", yroot * C(0.4, 0, 3.4), Cast.alive(Cast.rika.embrace, ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local rbones = ctx:rig("Ryu", Common.ryuRoot(0), Cast.ryu.spread)
	local ip = impactPoint()
	FX.placeBeam(ctx, hh.blast, blastStart(rbones), ip, 3.6, 0.85, 2)
	local fl = 1 + math.sin(ctx.t * 41) * 0.08
	FX.placeCore(ctx, hh.blastCore, ip, 1.7 * fl, 1)
	FX.placeCore(ctx, hh.blastHalo, ip, 3.4 * fl, 0.22)
	FX.placeCore(ctx, hh.pinkGlow, Common.YUTA + V(0, 3.2, 1.8), 1.9, 0.35)
	FX.placeBurst(ctx, hh.shards, ip, ctx.lt % 0.55, 34, 0.7, 0.55, V(-0.5, 0.3, -1), 0.8, 4)
	FX.placeBurst(ctx, hh.debris, ip + V(0, -2.4, 0), (ctx.lt + 0.25) % 0.7, 24, 0.9, 0.7, V(-0.3, 0.6, -1), 0.9, 25)
	Common.streamers(ctx, hh.streamers, Common.YUTA + V(0, 3.4, 0), V(0, 0, -1), 6, 5, 120, 0.9)
	local cam = Util.lookAt(Common.YUTA + V(-13, 2.8, -3), Common.YUTA + V(2, 3.2, 4))
	ctx:camera(Clash.shake(cam, ctx.t, 0.45, 18), 50)
	ctx:focus(13, 1)
	ctx:light("YutaAura", 2, nil, 16)
	ctx:bloom(1.3)
	Common.grade(ctx, -0.06, 0.3, 0.2, Color3.fromRGB(205, 235, 255))
end

-- from behind Yuta: a blinding dome of the blast, pink at its left edge
local function dome(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	ctx:rig("Yuta", yroot, Cast.alive(Cast.yuta.brace, ctx.t))
	local ip = impactPoint() + V(0, 0.8, 6)
	local grow = 1 + ctx.u * 0.35
	FX.placeCore(ctx, hh.blastCore, ip, 2.4 * grow, 1)
	FX.placeCore(ctx, hh.blastHalo, ip, 5 * grow, 0.3)
	FX.placeCore(ctx, hh.pinkGlow, ip + V(4, -1, -3), 2.2, 0.4)
	FX.placeRays(ctx, hh.rays, ip, C(), 18, 0.35, 0.7, 14, V(0, 0, -1))
	FX.placeBurst(ctx, hh.debris, ip, ctx.lt % 0.8, 26, 1.0, 0.8, V(0, 0.2, -1), 1, 6)
	FX.placeBurst(ctx, hh.shards, ip, (ctx.lt + 0.4) % 0.8, 30, 0.8, 0.8, V(0, 0.3, -1), 1, 4)
	local cam = Util.lookAt(yroot:PointToWorldSpace(V(0.8, 2.3, 7.5)), yroot:PointToWorldSpace(V(0, 3.4, -6)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.35, 14), 60)
	ctx:focus(7.5, 1)
	ctx:light("YutaAura", 1.5, nil, 14)
	ctx:bloom(1.5)
	-- the debris turns to white blobs as the light peaks
	ctx:flash(WHITE, Util.smoothstep(0.75, 1, ctx.u) * 0.7)
	Common.grade(ctx, -0.05, 0.25, 0.1, Color3.fromRGB(215, 240, 255))
end

-- arm reaching forward into the blast (profile), right hand opening
local function reachPose(k: number): Rig.Pose
	local p = Cast.mix(Cast.yuta.brace, {
		UpperTorso = R(4, 20, 0),
		Head = R(-4, -20, 0),
		RightUpperArm = R(86, 0, -6),
		RightLowerArm = R(4, 0, 0),
		RightHand = R(-20, 0, 0),
		LeftUpperArm = R(10, 0, -24),
		LeftLowerArm = R(40, 0, 0),
	}, k)
	return p
end

local function reach(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local k = Util.smoothstep(10.25, 11.0, ctx.t)
	local yb = ctx:rig("Yuta", yroot, Cast.alive(reachPose(k), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local head = yb.Head * C(0, 0.55, 0)
	local hand = (yb.RightHand * C(0, -0.35, 0)).Position
	local eye = yroot:PointToWorldSpace(V(4.0, 3.9, 0.6 - k * 1.4))
	local target = head.Position:Lerp(hand, k * 0.55) + V(0, -0.2, 0)
	ctx:camera(Clash.shake(Util.lookAt(eye, target), ctx.t, 0.06, 8), 48)
	ctx:focus((target - eye).Magnitude, 1)
	Common.streamers(ctx, hh.streamers, Common.YUTA + V(0, 3.4, 1), V(0, 0, -1), 3.4, 4, 110, 0.85)
	ctx:light("YutaAura", 2.4, CYAN, 12)
	ctx:bloom(1.6)
	Common.grade(ctx, 0, 0.22, 0.15, Color3.fromRGB(200, 222, 255))
end

-- close on the open hand; a glassy pane of folded space spreads from it
local function hand(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local yb = ctx:rig("Yuta", yroot, Cast.add(reachPose(1), "RightHand", R(-10 - ctx.u * 25, 0, 0)))
	Cast.expr(ctx, "yuta", "glare")
	local palm = (yb.RightHand * C(0, -0.3, 0)).Position
	local fwd = yroot.LookVector
	local eye = palm - fwd * 1.3 + yroot.RightVector * 1.9 + V(0, 0.7, 0)
	ctx:camera(Clash.shake(Util.lookAt(eye, palm + fwd * 0.9), ctx.t, 0.05, 8), 50)
	ctx:focus((palm - eye).Magnitude, 1)
	local g = Util.smoothstep(0.25, 1, ctx.u)
	FX.placeRing(ctx, hh.pane, palm + fwd * 0.5, fwd, 0.4 + g * 7, 0.04, 0.32 * g)
	FX.placeCore(ctx, hh.palmGlow, palm + fwd * 0.35, 0.25 + g * 0.35, 0.8)
	Common.streamers(ctx, hh.streamers, palm + fwd * 2, V(0, 0, -1), 2.6, 3.5, 110, 0.85)
	ctx:light("YutaAura", 2.4, CYAN, 12)
	ctx:bloom(1.8)
	Common.grade(ctx, 0.04, 0.22, 0.15, Color3.fromRGB(205, 225, 255))
end

-- Yuta's face, blue light flickering over it; Ryu's thoughts over it
local function face(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local yb = ctx:rig("Yuta", yroot, Cast.alive(Cast.add(reachPose(1), "Head", R(-6, -14 + ctx.u * 8, 0)), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local head = yb.Head * C(0, 0.6, 0)
	local eye = head:PointToWorldSpace(V(0.5 - ctx.u * 0.2, -0.25, -2.7 + ctx.u * 0.35))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.1, 0)), ctx.t, 0.04, 6), 46)
	ctx:focus(2.6, 1)
	Common.streamers(ctx, hh.streamers, head.Position + yroot.LookVector * 2.2, V(0, 0, -1), 1.6, 1.8, 70, 0.6)
	local fl = 0.75 + 0.25 * math.sin(ctx.t * 13) * math.sin(ctx.t * 7.3)
	ctx:light("YutaAura", 2.6 * fl, CYAN, 10)
	ctx:bloom(1.5)
	ctx:flash(WHITE, Util.smoothstep(0.9, 1, ctx.u) * 0.85)
	Common.grade(ctx, 0, 0.2, 0.1, Color3.fromRGB(210, 228, 255))
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
	ctx:bloom(2.4)
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
	FX.placeCurvedBeam(ctx, hh.bands[1], pt, math.max(0, u * 1.2 - 0.5), math.min(1, u * 1.4 + 0.2), 9, 1)
	FX.placeCurvedBeam(ctx, hh.bands[2], function(f: number): Vector3
		return pt(f) + V(0, -6, 2)
	end, math.max(0, u * 1.2 - 0.6), math.min(1, u * 1.4), 4, 0.8)
	ctx:bloom(2)
	Common.grade(ctx, 0.1, 0.2, 0.1, Color3.fromRGB(220, 235, 255))
end

-- Ryu's eyes in the painted close-up: a glare, then wide with shock
local function ryuGlare(ctx: Timeline.Ctx)
	Common.panelCamera(ctx, 430, 470, 300)
	ctx:show("split:ryuGlare")
	ctx:flash(CYAN, 0.45)
	Common.grade(ctx, 0.05, 0.2, 0.1, Color3.fromRGB(210, 240, 255))
end

local function ryuEyes(ctx: Timeline.Ctx)
	local z = 300 - ctx.u * 30
	Common.panelCamera(ctx, 430, 470, z)
	ctx:show("split:ryuShock")
	ctx:flash(CYAN, 0.2 * (1 - ctx.u))
	Common.grade(ctx, 0.05, 0.22, 0.05, Color3.fromRGB(215, 240, 255))
end

-- Uro's technique: the sky folds like a sheet and bends the Granite Blast
-- up and away in broad bands of cyan and white
local function fold(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	ctx:rig("Yuta", yroot, Cast.alive(reachPose(1), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local rbones = ctx:rig("Ryu", Common.ryuRoot(0), Cast.alive(Cast.ryu.spread, ctx.t))
	Cast.expr(ctx, "ryu", "shock")
	local bend = impactPoint() + V(0, 1, 2)
	FX.placeBeam(ctx, hh.blast, blastStart(rbones), bend, 4, 0.9, 2)
	FX.placeCore(ctx, hh.blastCore, bend, 1.8, 1)
	FX.placeCore(ctx, hh.blastHalo, bend, 3.6, 0.25)
	FX.placeCore(ctx, hh.pinkGlow, Common.YUTA + V(0.5, 3.6, 1.2), 1.8, 0.5)
	for i, b in hh.bands do
		local off = V((i - 3) * 2.4, (i - 3) * 0.8, 0)
		local p0 = bend + off
		local p1 = bend + V(0, 6, 12) + off * 2
		local p2 = bend + V((i - 3) * 9, 70, 30)
		local function pt(f: number): Vector3
			local w = 1 - f
			return p0 * (w * w) + p1 * (2 * w * f) + p2 * (f * f)
		end
		local head = math.clamp((ctx.lt - (i - 1) * 0.12) / 1.4, 0, 1)
		local tail = math.clamp(head - 0.55, 0, 1)
		FX.placeCurvedBeam(ctx, b, pt, tail, head, if i % 2 == 0 then 1.3 else 2.6, 0.8)
	end
	FX.placeRays(ctx, hh.rays, bend, C(), 16, 0.4, 0.8, 12, V(0, 1, 0))
	FX.placeBurst(ctx, hh.debris, bend + V(0, -2, 0), ctx.lt % 0.9, 22, 1.0, 0.9, V(0, 1, 0.3), 0.9, 20)
	FX.placeBurst(ctx, hh.shards, bend, (ctx.lt + 0.45) % 0.9, 26, 0.7, 0.9, V(0, 1, 0.5), 1, 2)
	local eye = Common.YUTA + V(-15, 1.6, -9)
	local look = Util.lookAt(eye, Common.YUTA + V(4, 12, 16))
	ctx:camera(Clash.shake(look * CFrame.Angles(0, 0, math.rad(-10)), ctx.t, 0.2, 10), 62)
	ctx:focus(20, 0.6)
	ctx:bloom(1.4)
	Common.grade(ctx, -0.04, 0.28, 0.25, Color3.fromRGB(205, 240, 255))
	Common.sky(ctx, "wisps", 50)
end

Blast.shots = {
	{ id = "P2 01 star", t0 = 5.267, t1 = 5.4, run = star },
	{ id = "P2 02 swirl", t0 = 5.4, t1 = 5.633, run = swirl },
	{ id = "P2 03 launch", t0 = 5.633, t1 = 6.133, run = launch },
	{ id = "P2 04 side", t0 = 6.133, t1 = 6.233, run = side },
	{ id = "P2 05 crescent", t0 = 6.233, t1 = 6.267, run = crescent },
	{ id = "P2 06 engulf", t0 = 6.267, t1 = 8.033, run = engulf },
	{ id = "P2 07 dome", t0 = 8.033, t1 = 9.633, run = dome },
	{ id = "P2 08 reach", t0 = 9.633, t1 = 11.5, run = reach },
	{ id = "P2 09 hand", t0 = 11.5, t1 = 12.767, run = hand },
	{ id = "P2 10 face", t0 = 12.767, t1 = 15.8, run = face },
	{ id = "P2 11 comet", t0 = 15.8, t1 = 15.933, run = comet },
	{ id = "P2 12 arc", t0 = 15.933, t1 = 16.3, run = arc },
	{ id = "P2 13 glare", t0 = 16.3, t1 = 16.467, run = ryuGlare },
	{ id = "P2 14 eyes", t0 = 16.467, t1 = 17.033, run = ryuEyes },
	{ id = "P2 15 fold", t0 = 17.033, t1 = 20.3, run = fold },
} :: { Timeline.Shot }

Blast.reachPose = reachPose
Blast.blastStart = blastStart

return Blast
