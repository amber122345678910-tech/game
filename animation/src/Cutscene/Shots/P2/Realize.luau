--!strict
-- Part 2: Ryu keeps firing while his blast bends away, and works out Yuta's
-- technique; then Yuta shoves the blast away into the sky.
--  20.300 Ryu from below and behind, the beam from his head bent up and right
--  23.000 Ryu's head in profile, blue energy flaring round his face and neck
--  27.667 Yuta from behind and below, his right hand raised, energy swirling
--  38.700 another angle: the bent blast slams into the concrete deck
--  39.433 Yuta shoves the blast off with his raised hand; it flies off as a comet
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
	ctx:wind(1.8)
	ctx:gust(0.3 + 0.3 * math.max(0, math.sin(ctx.t * 2.1)))
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
	-- teeth bared, mouth open, the head slowly lifting and turning towards
	-- the bent blast; the wind of it tears at his fur and hair
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local u = ctx.u
	local trem = Util.noise1(ctx.t * 9, 3) * 1.5
	local head = R(-14 - u * 7 + trem, -10 + u * 9, Util.noise1(ctx.t * 6, 4) * 1.2)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", head), ctx.t))
	-- the profile close-up: keep the big collar out of his face
	Cast.furLow(ctx, "Ryu", 0.7)
	Cast.expr(ctx, "ryu", "strain")
	local hd = bones.Head * C(0, 0.75, 0)
	local eye = hd:PointToWorldSpace(V(2.3 - u * 0.25, 0.1, -1.7))
	ctx:camera(Clash.shake(Util.lookAt(eye, hd.Position + V(0, -0.15, 0)), ctx.t, 0.07, 9), 42)
	ctx:focus((hd.Position - eye).Magnitude, 1)
	local a = Blast.blastStart(bones)
	FX.placeBeam(ctx, hh.blast, a, Blast.bandPoint(3, 0), 2.6, 0.8, 2)
	local fl = 0.8 + 0.2 * math.sin(ctx.t * 11) * math.sin(ctx.t * 5.3)
	ctx:light("RyuFace", 2.0 * fl, CYAN, 9)
	local idx = 1
	for i = 1, 6 do
		local pnt = hd:PointToWorldSpace(V(math.sin(i * 2.1) * 0.5, -0.6 - (i % 3) * 0.35, 0.2 + math.cos(i * 1.7) * 0.4))
		idx = FX.placeBolt(ctx, hh.bolts, idx, pnt, pnt + V(math.sin(i + ctx.t * 4) * 0.8, 1.2 + (i % 2) * 0.6, math.cos(i * 3.1) * 0.8), 6, 0.16, 0.035, 40 + i, 14)
	end
	ctx:emit("RyuGlints", 60)
	ctx:wind(1.8)
	ctx:gust(0.4 + 0.4 * math.max(0, math.sin(ctx.t * 2.3)))
	Cast.ryuAura(ctx, bones, 0.8, 3)
	ctx:bloom(1.5)
	Common.grade(ctx, -0.04, 0.22, 0.05, Color3.fromRGB(200, 222, 255))
	Common.sky(ctx, "wisps", 30)
end

-- Yuta from behind in the glare, right hand raised; pink and blue energy
-- and black shards swirling round him
local function yutaRaise(ctx: Timeline.Ctx)
	-- Yuta holding the blast up: the whole body works against it, weight
	-- shifting between the legs, the torso straining and swaying, the raised
	-- arm trembling, hair and jacket whipped by the energy
	local hh = h(ctx)
	local t = ctx.t
	local yroot = Common.yutaRoot()
	local k = Util.smoothstep(0, 0.5, ctx.lt)
	local sway = math.sin(t * 1.7)
	local shift = math.sin(t * 1.1 + 0.6)
	local trem = Util.noise1(t * 11, 7)
	local live: Rig.Pose = {
		HumanoidRootPart = C(shift * 0.12, math.abs(math.sin(t * 2.2)) * -0.06, 0),
		LowerTorso = R(-4 + sway * 2, shift * 6, 0),
		UpperTorso = R(-6 + sway * 3, -10 + shift * 5, sway * 2),
		Head = R(-22 + math.sin(t * 1.5) * 3, 10 + math.sin(t * 0.9) * 6, 0),
		RightUpperArm = R(150 + trem * 3, 0, -14 + trem * 2),
		RightLowerArm = R(14 + trem * 4, 0, 0),
		RightHand = R(-30 + trem * 6, 0, 0),
		LeftUpperArm = R(-6 + sway * 6, 0, -26 - shift * 4),
		LeftLowerArm = R(30 + sway * 8, 0, 0),
		LeftUpperLeg = R(12 + shift * 6, 0, -8),
		LeftLowerLeg = R(-14 - math.max(0, shift) * 10, 0, 0),
		RightUpperLeg = R(-10 - shift * 6, 0, 8),
		RightLowerLeg = R(-6 - math.max(0, -shift) * 10, 0, 0),
	}
	local yb = ctx:rig("Yuta", yroot, Cast.mix(Blast.reachPose(1), live, k))
	Cast.expr(ctx, "yuta", "glare")
	local eye = yroot:PointToWorldSpace(V(1.4, 1.3, 3.8 + ctx.u * 0.8))
	local look = yroot:PointToWorldSpace(V(-1.5, 7, -8))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), t, 0.07, 8), 60)
	ctx:focus(4, 1)
	local src = yroot:PointToWorldSpace(V(-6, 16, -14))
	FX.placeCore(ctx, hh.blastCore, src, 2.6, 1)
	FX.placeCore(ctx, hh.blastHalo, src, 5.5, 0.28)
	FX.placeRays(ctx, hh.rays, src, Util.lookAt(src, eye), 34, 0.45, 0.8, 12, (eye - src).Unit)
	local hand = (yb.RightHand * C(0, -0.4, 0)).Position
	FX.placeCore(ctx, hh.palmGlow, hand, 0.3, 0.7)
	-- energy and shards circling him
	local c = Common.YUTA + V(0, 3, 0)
	for i, part in hh.shell.parts do
		local a = t * (1.2 + (i % 3) * 0.3) + i * 0.7
		local rr = 3 + (i % 5) * 0.8
		local pos = c + V(math.cos(a) * rr, math.sin(i * 1.3 + t) * 2.5, math.sin(a) * rr)
		ctx:place(part, CFrame.new(pos) * CFrame.Angles(a, i, a * 0.5))
		local sz = 0.25 + (i % 4) * 0.1
		ctx:prop(part, { s = V(sz, sz * 1.4, sz * 0.3) })
	end
	Common.streamers(ctx, hh.streamers, c, V(1, 0.6, 0.2), 4, 3, 50, 0.6)
	ctx:wind(2.2)
	ctx:gust(0.5 + 0.5 * math.max(0, math.sin(t * 3.1)))
	ctx:light("YutaAura", 1.8, PINK, 14)
	ctx:bloom(1.4)
	Common.grade(ctx, -0.02, 0.25, 0.2, Color3.fromRGB(230, 225, 255))
end

-- from above: the bent blast arching over the cracked deck, Yuta darting
-- through it towards Ryu
local function overBeam(ctx: Timeline.Ctx)
	-- from another angle: the bent blast slams down into the concrete and
	-- skids along it, tearing the deck up (nobody in the shot)
	local hh = h(ctx)
	local u = ctx.u
	local hit = Common.YUTA:Lerp(Common.RYU, 0.3) + V(9, 0, -4)
	local function pt(f: number): Vector3
		local a = hit + V(-14, 18, 10)
		local b = hit + V(-4, 2, 3)
		local c = hit + V(10, 0.6, -6)
		local w = 1 - f
		return a * (w * w) + b * (2 * w * f) + c * (f * f)
	end
	for i, b in hh.bands do
		local off = V(0, (i - 3) * 0.5, (i - 3) * 0.8)
		FX.placeCurvedBeam(ctx, b, function(f: number): Vector3
			return pt(f) + off
		end, 0, math.clamp(0.55 + u * 0.6, 0, 1), if i % 2 == 0 then 1.2 else 2.4, 0.85)
	end
	local skid = pt(math.clamp(0.55 + u * 0.6, 0, 1))
	FX.placeCore(ctx, hh.blastCore, skid, 1.6, 1)
	FX.placeBurst(ctx, hh.debris, skid, ctx.lt % 0.5, 24, 1.0, 0.5, V(0.2, 1, -0.4), 0.9, 30)
	FX.placeBurst(ctx, hh.shards, skid, (ctx.lt + 0.2) % 0.5, 26, 0.7, 0.5, V(0.3, 1, -0.3), 1, 10)
	local cam = Util.lookAt(hit + V(-8, 26, -14), hit + V(0, 0, 2))
	ctx:camera(Clash.shake(cam * CFrame.Angles(0, 0, math.rad(-18)), ctx.t, 0.35, 14), 56)
	ctx:focus(30, 0)
	ctx:bloom(1.5)
	Common.grade(ctx, -0.06, 0.3, 0.2, Color3.fromRGB(195, 220, 255))
end

-- Yuta dashes at the camera through blue fog, a violet streak behind him
local function dash(ctx: Timeline.Ctx)
	-- Yuta, raised hand in the stream, shoves the blast off with a jolt (his
	-- hair jerks), and stays standing, alive; the camera whips after the
	-- blast as it flies up and away into the night like a comet
	local hh = h(ctx)
	local t = ctx.t
	local yroot = Common.yutaRoot()
	local push = Util.smoothstep(39.45, 39.62, t)
	-- the arm overshoots on the shove and settles back
	local over = math.max(0, t - 39.62)
	local settle = math.exp(-over * 7) * math.sin(over * 22) * 10
	local live: Rig.Pose = {
		HumanoidRootPart = C(0, math.sin(t * 2.4) * -0.04, 0),
		LowerTorso = R(-6, 14, 0),
		UpperTorso = R(4 - push * 10 + math.sin(t * 1.9) * 2, 16, 0),
		Head = R(-26 - push * 6, -12, 0),
		LeftUpperArm = R(110 + push * 50 + settle, 0, -20),
		LeftLowerArm = R(30 - push * 26, 0, 0),
		LeftHand = R(-40 + push * 20, 0, 0),
		RightUpperArm = R(-14, 0, 34),
		RightLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(24, 0, -8),
		LeftLowerLeg = R(-30, 0, 0),
		RightUpperLeg = R(-24, 0, 10),
		RightLowerLeg = R(-8, 0, 0),
	}
	local yb = ctx:rig("Yuta", yroot, Cast.alive(live, t))
	Cast.expr(ctx, "yuta", "glare")
	local palm = (yb.LeftHand * C(0, -0.35, 0)).Position
	-- the blast: into his palm, then shoved up and away
	local rb = ctx:rig("Ryu", Common.ryuRoot(0), Cast.ryu.spread)
	local away = (V(0.35, 1, 0.55)).Unit
	local fly = math.max(0, t - 39.6)
	local head = palm + away * (fly * 90)
	if push < 1 then
		local into = palm + (Blast.blastStart(rb) - palm).Unit * 1.4
		FX.placeBeam(ctx, hh.blast, Blast.blastStart(rb), into, 2.0, 0.9, 2)
	end
	if fly > 0 then
		FX.placeBeam(ctx, hh.comet, head - away * math.min(40, 6 + fly * 60), head, 3 - math.min(2, fly), 1)
		FX.placeCore(ctx, hh.blastCore, head, 2.4 - math.min(1.6, fly * 1.4), 1)
	end
	FX.placeBurst(ctx, hh.shell, palm, math.max(0, t - 39.5), 16, 0.5, 0.7, away, 1, 6)
	ctx:gust(math.exp(-math.max(0, t - 39.55) * 4) * 2.5 * push)
	ctx:wind(1.6)
	-- camera: on Yuta at the right of the frame, then a whip up after the blast
	local whip = Util.smoothstep(39.82, 40.02, t)
	local eyeA = yroot:PointToWorldSpace(V(5.5, 2.2, -6))
	local lookA = yroot:PointToWorldSpace(V(1.8, 3.6, 0))
	local eyeB = Common.YUTA + V(-6, 2, -10)
	local lookB = palm + away * (40 + fly * 100)
	local cam = Util.lookAt(eyeA:Lerp(eyeB, whip), lookA:Lerp(lookB, whip))
	ctx:camera(Clash.shake(cam, t, 0.25 + whip * (1 - whip) * 3, 18), 52 - whip * 12)
	ctx:focus(if whip < 0.5 then 6.5 else 100, if whip < 0.5 then 1 else 0)
	local sky = Util.smoothstep(39.95, 40.15, t)
	ctx:fog(1 + sky * 0.6)
	ctx:bloom(1.5)
	Common.grade(ctx, -0.04 - sky * 0.2, 0.28, 0.2 + sky * 0.05, Color3.fromRGB(200 - sky * 50, 220 - sky * 45, 255))
	if whip < 0.6 then
		Common.sky(ctx, "wisps", 30)
	end
end

local function ryuGlow(ctx: Timeline.Ctx)
	-- frozen, mouth open; from 41.3 s his overused hair overheats: it reddens,
	-- smoulders and bristles, small flames licking up, smoke rising
	local hh = h(ctx)
	local t = ctx.t
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(6, 0, 0)), t))
	Cast.expr(ctx, "ryu", "gasp")
	local head = bones.Head * C(0, 0.7, 0)
	local eye = head:PointToWorldSpace(V(0.1, -0.35, -3.3 + ctx.u * 0.4))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.15, 0)), t, 0.04 + ctx.u * 0.1, 10), 46)
	ctx:focus(3.2, 1)
	local k = Util.smoothstep(0, 1, ctx.u)
	local burn = Util.smoothstep(41.25, 41.9, t)
	-- the blood trickle from the hairline
	for i, p in hh.rikaBlood do
		if i <= 3 then
			local len = 0.18 + 0.22 * k
			ctx:place(p, bones.Head * C(-0.18 + i * 0.05, 1.12 - i * 0.12 - len * 0.4, -0.6))
			ctx:prop(p, { s = V(0.05, len, 0.03) })
		end
	end
	if burn > 0 then
		local hot = Color3.fromRGB(200, 60, 30)
		local ember = Color3.fromRGB(255, 120, 40)
		for i, p in ctx.scene.data.ryuHair do
			local c = Util.mix(p.color, if i % 3 == 0 then ember else hot, burn * (0.7 + 0.3 * math.sin(t * 13 + i)))
			ctx:prop(p, { c = c })
		end
		local top = (bones.Head * C(0, 1.55, -0.2)).Position
		for i, p in hh.flames.parts do
			local rr = Util.rng(300 + i)
			local ph = (t * (2.2 + Util.rand(rr)) + Util.rand(rr)) % 1
			local base = top + bones.Head:VectorToWorldSpace(V(Util.randRange(rr, -0.7, 0.7), 0, Util.randRange(rr, -0.8, 0.6)))
			local pos = base + V(0, ph * 1.4, 0)
			local sz = (0.35 - ph * 0.3) * burn
			ctx:place(p, CFrame.new(pos) * CFrame.Angles(0, i, math.sin(t * 9 + i) * 0.3))
			ctx:prop(p, { s = V(sz * 0.5, sz * 1.6, sz * 0.5), t = 0.1 + ph * 0.8 })
		end
		FX.placeBurst(ctx, hh.smoke, top + V(0, 0.4, 0), (t - 41.25) % 1.2, 1.4, 0.5, 1.2, V(0, 1, 0), 0.6, -1)
		ctx:gust(0.8 * burn)
	end
	ctx:light("RyuFace", 0.4 + 0.3 * k + burn * 0.3, ORANGE, 6)
	ctx:alpha("orangeFlare", Util.smoothstep(0.55, 1, ctx.u))
	ctx:bloom(1.1)
	Common.grade(ctx, -0.02, 0.24, 0.05, Color3.fromRGB(240, 232, 228))
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
	{ id = "P2 27 blast hits the deck", t0 = 38.7, t1 = 39.433, run = overBeam },
	{ id = "P2 28 deflect", t0 = 39.433, t1 = 40.7, run = dash },
	{ id = "P2 29 ryu frozen", t0 = 40.7, t1 = 42.3, run = ryuGlow },
	{ id = "P2 30 eye black", t0 = 42.3, t1 = 42.9, run = eyeBlack },
} :: { Timeline.Shot }

return Realize
