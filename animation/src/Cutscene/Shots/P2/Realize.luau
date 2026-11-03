--!strict
-- Part 2: Ryu keeps firing while his blast bends away, and works out Yuta's
-- technique; then Yuta lets the blast go and dashes at him.
--  20.300 Ryu from below and behind, the beam from his head bent up and right
--  23.000 Ryu's head in profile, blue energy flaring round his face and neck
--  27.667 Yuta from behind and below, his right hand raised, energy swirling
--  38.700 from above: the bent blast over the cracked deck, Yuta darts through
--  39.433 Yuta dashes at the camera through blue fog
--  40.700 Ryu's face frozen, red light growing over his head
--  42.300 his eye alone in the dark, orange streaks
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Parent.Util)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Cast = require(script.Parent.Parent.Cast)
local Clash = require(script.Parent.Parent.Clash)
local Common = require(script.Parent.Common)
local Blast = require(script.Parent.Blast)

local Realize = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local CYAN = Color3.fromRGB(120, 230, 255)
local ORANGE = Color3.fromRGB(255, 110, 60)
local PINK = Color3.fromRGB(255, 120, 220)

local function h(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end

-- Ryu's blast leaving his head and the bands it bends into above Yuta
local function bentBlast(ctx: Timeline.Ctx, ryuBones: { [string]: CFrame }, k: number)
	local hh = h(ctx)
	local bend = Blast.bandPoint(3, 0)
	FX.placeBeam(ctx, hh.blast, Blast.blastStart(ryuBones), bend, 3.2, 0.9 * k, 2)
	for i, b in hh.bands do
		FX.placeCurvedBeam(ctx, b, function(f: number): Vector3
			return Blast.bandPoint(i, f)
		end, 0.25, 1, if i % 2 == 0 then 1.3 else 2.6, 0.8 * k)
	end
	FX.placeCore(ctx, hh.blastCore, bend, 1.6, k)
	FX.placeCore(ctx, hh.blastHalo, bend, 3.4, 0.25 * k)
end

-- rings of shock travelling along the beam near Ryu's head
local function beamRings(ctx: Timeline.Ctx, from: Vector3, to: Vector3)
	local hh = h(ctx)
	local d = (to - from).Unit
	for i, ring in hh.rings do
		local ph = (ctx.t * 1.6 + i / 3) % 1
		FX.placeRing(ctx, ring, from + d * (2 + ph * 14), d, 1.4 + ph * 2.2, 0.06, 0.55 * (1 - ph))
	end
end

local function ryuBack(ctx: Timeline.Ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(-16, -10, 0)), ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	ctx:rig("Yuta", Common.yutaRoot(), Cast.alive(Blast.reachPose(1), ctx.t))
	bentBlast(ctx, bones, 1)
	beamRings(ctx, Blast.blastStart(bones), Blast.bandPoint(3, 0))
	local eye = root:PointToWorldSpace(V(-2.6, 2.4, 5.2 - ctx.u * 0.8))
	local look = root:PointToWorldSpace(V(3, 9.5, -16))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.06, 8), 54)
	ctx:focus((bones.Head.Position - eye).Magnitude, 1)
	Cast.ryuAura(ctx, bones, 0.8, 4)
	ctx:bloom(1.3)
	Common.grade(ctx, -0.06, 0.24, 0.1, Color3.fromRGB(205, 225, 255))
	Common.sky(ctx, "wisps", 40)
end

local function ryuProfile(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(-14, -10, 0)), ctx.t))
	Cast.expr(ctx, "ryu", "glare")
	local head = bones.Head * C(0, 0.75, 0)
	local eye = head:PointToWorldSpace(V(2.3 - ctx.u * 0.25, 0.1, -1.7))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.15, 0)), ctx.t, 0.07, 9), 42)
	ctx:focus((head.Position - eye).Magnitude, 1)
	-- the beam from his head, right and up; blue energy flaring at his face and neck
	local a = Blast.blastStart(bones)
	FX.placeBeam(ctx, hh.blast, a, Blast.bandPoint(3, 0), 2.6, 0.8, 2)
	local fl = 0.8 + 0.2 * math.sin(ctx.t * 11) * math.sin(ctx.t * 5.3)
	ctx:light("RyuFace", 2.0 * fl, CYAN, 9)
	local idx = 1
	for i = 1, 6 do
		local p = head:PointToWorldSpace(V(math.sin(i * 2.1) * 0.5, -0.6 - (i % 3) * 0.35, 0.2 + math.cos(i * 1.7) * 0.4))
		idx = FX.placeBolt(ctx, hh.bolts, idx, p, p + V(math.sin(i + ctx.t * 4) * 0.8, 1.2 + (i % 2) * 0.6, math.cos(i * 3.1) * 0.8), 6, 0.16, 0.035, 40 + i, 14)
	end
	ctx:emit("RyuGlints", 60)
	Cast.ryuAura(ctx, bones, 0.8, 3)
	ctx:bloom(1.5)
	Common.grade(ctx, -0.04, 0.22, 0.05, Color3.fromRGB(200, 222, 255))
	Common.sky(ctx, "wisps", 30)
end

local raiseArm: Rig.Pose = {
	UpperTorso = R(-6, -10, 0),
	Head = R(-22, 10, 0),
	RightUpperArm = R(150, 0, -14),
	RightLowerArm = R(14, 0, 0),
	RightHand = R(-30, 0, 0),
	LeftUpperArm = R(-6, 0, -26),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(10, 0, -6),
	RightUpperLeg = R(-8, 0, 6),
}

-- Yuta from behind in the glare, right hand raised; pink and blue energy
-- and black shards swirling round him
local function yutaRaise(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local yb = ctx:rig("Yuta", yroot, Cast.alive(Cast.mix(Blast.reachPose(1), raiseArm, Util.smoothstep(0, 0.5, ctx.lt)), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local eye = yroot:PointToWorldSpace(V(1.4, 1.3, 3.8 + ctx.u * 0.8))
	local look = yroot:PointToWorldSpace(V(-1.5, 7, -8))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.07, 8), 60)
	ctx:focus(4, 1)
	local src = yroot:PointToWorldSpace(V(-6, 16, -14))
	FX.placeCore(ctx, hh.blastCore, src, 2.6, 1)
	FX.placeCore(ctx, hh.blastHalo, src, 5.5, 0.28)
	FX.placeRays(ctx, hh.rays, src, Util.lookAt(src, eye), 34, 0.45, 0.8, 12, (eye - src).Unit)
	local hand = (yb.RightHand * C(0, -0.4, 0)).Position
	FX.placeCore(ctx, hh.palmGlow, hand, 0.3, 0.7)
	-- energy and shards circling him
	local c = Common.YUTA + V(0, 3, 0)
	for i, p in hh.shell.parts do
		local a = ctx.t * (1.2 + (i % 3) * 0.3) + i * 0.7
		local rr = 3 + (i % 5) * 0.8
		local pos = c + V(math.cos(a) * rr, math.sin(i * 1.3 + ctx.t) * 2.5, math.sin(a) * rr)
		ctx:place(p, CFrame.new(pos) * CFrame.Angles(a, i, a * 0.5))
		local sz = 0.25 + (i % 4) * 0.1
		ctx:prop(p, { s = V(sz, sz * 1.4, sz * 0.3) })
	end
	Common.streamers(ctx, hh.streamers, c, V(1, 0.6, 0.2), 4, 3, 50, 0.6)
	ctx:light("YutaAura", 1.8, PINK, 14)
	ctx:bloom(1.4)
	Common.grade(ctx, -0.02, 0.25, 0.2, Color3.fromRGB(230, 225, 255))
end

-- from above: the bent blast arching over the cracked deck, Yuta darting
-- through it towards Ryu
local function overBeam(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local p = Common.YUTA:Lerp(Common.RYU, 0.2 + u * 0.35)
	ctx:rig("Yuta", C(p) * CFrame.Angles(0, math.rad(180), 0), Cast.run(ctx.t * 3.4, 34))
	local rbones = ctx:rig("Ryu", Common.ryuRoot(0), Cast.ryu.spread)
	bentBlast(ctx, rbones, 1)
	local mid = Common.YUTA:Lerp(Common.RYU, 0.4)
	local cam = Util.lookAt(mid + V(-10, 34, -6), mid + V(2, 0, 2), V(0, 0, 1))
	ctx:camera(Clash.shake(cam * CFrame.Angles(0, 0, math.rad(-25)), ctx.t, 0.3, 14), 58)
	ctx:focus(34, 0)
	Common.streamers(ctx, hh.streamers, p + V(0, 2.5, 0), V(0, 0, 1), 1.4, 6, 140, 0.8)
	ctx:bloom(1.5)
	Common.grade(ctx, -0.04, 0.28, 0.2, Color3.fromRGB(200, 225, 255))
end

-- Yuta dashes at the camera through blue fog, a violet streak behind him
local function dash(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local p = Common.YUTA:Lerp(Common.RYU, 0.45 + u * 0.4)
	local yb = ctx:rig("Yuta", C(p) * CFrame.Angles(0, math.rad(180), 0), Cast.run(ctx.t * 3.4, 38))
	Cast.expr(ctx, "yuta", "glare")
	local eye = Common.RYU + V(1.6, 2.6, -3)
	ctx:camera(Clash.shake(Util.lookAt(eye, yb.Head.Position + V(0, -1, 0)), ctx.t, 0.25, 12), 55)
	ctx:focus((yb.Head.Position - eye).Magnitude, 0.8)
	Common.streamers(ctx, hh.streamers, p + V(0, 2.6, -4), V(0, 0, 1), 1.2, 8, 160, 0.7)
	FX.placeCore(ctx, hh.pinkGlow, p + V(0, 2.6, -1.5), 0.8, 0.35)
	ctx:fog(2.2)
	ctx:bloom(1.3)
	Common.grade(ctx, -0.12, 0.25, 0.15, Color3.fromRGB(170, 190, 255))
	Common.sky(ctx, "heavy", 14)
end

local function ryuGlow(ctx: Timeline.Ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(6, 0, 0)), ctx.t))
	Cast.expr(ctx, "ryu", "gasp")
	local head = bones.Head * C(0, 0.7, 0)
	local eye = head:PointToWorldSpace(V(0.1, -0.35, -3.3 + ctx.u * 0.4))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.15, 0)), ctx.t, 0.04 + ctx.u * 0.1, 10), 46)
	ctx:focus(3.2, 1)
	local k = Util.smoothstep(0, 1, ctx.u)
	local hh = h(ctx)
	for i, p in hh.rikaBlood do
		if i <= 3 then
			local len = 0.18 + 0.22 * k
			ctx:place(p, bones.Head * C(-0.18 + i * 0.05, 1.12 - i * 0.12 - len * 0.4, -0.6))
			ctx:prop(p, { s = V(0.05, len, 0.03) })
		end
	end
	ctx:light("RyuFace", 0.8 + 1.4 * k, ORANGE, 8)
	ctx:alpha("orangeFlare", Util.smoothstep(0.55, 1, ctx.u))
	ctx:bloom(1.4)
	Common.grade(ctx, 0, 0.25, 0.1, Color3.fromRGB(255, 225, 205))
	Common.sky(ctx, "wisps", 26)
end

local function eyeBlack(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:alpha("eyeBlack", 1 - Util.smoothstep(0.45, 1, ctx.u))
end

Realize.shots = {
	{ id = "P2 16 ryu back", t0 = 20.3, t1 = 23.0, run = ryuBack },
	{ id = "P2 17 ryu profile", t0 = 23.0, t1 = 27.667, run = ryuProfile },
	{ id = "P2 18 yuta raise", t0 = 27.667, t1 = 31.3, run = yutaRaise },
	{ id = "P2 27 over the beam", t0 = 38.7, t1 = 39.433, run = overBeam },
	{ id = "P2 28 dash", t0 = 39.433, t1 = 40.7, run = dash },
	{ id = "P2 29 ryu frozen", t0 = 40.7, t1 = 42.3, run = ryuGlow },
	{ id = "P2 30 eye black", t0 = 42.3, t1 = 42.9, run = eyeBlack },
} :: { Timeline.Shot }

return Realize
