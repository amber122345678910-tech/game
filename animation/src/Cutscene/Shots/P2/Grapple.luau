--!strict
-- Part 2, 45.800-59.167: Yuta closes in; they grapple, Ryu shoves him off,
-- Rika lunges and clamps her jaws on Ryu's head, Yuta presses his palm to
-- Ryu's chest; the countdown hits zero. "Five minutes."
--  45.800 impact (blur)       46.133 grappling           47.767 negative flash
--  48.267 Ryu shoves Yuta     48.900 radial burst        49.167 Rika lunges
--  50.067 Ryu skids back      51.533 Rika grabs him      51.867 his face, bitten
--  52.533 Rika's head         53.400 Yuta's palm, from behind Ryu
--  54.500 the palm, cracks    55.833 countdown           56.000 0:00:00
--  57.100 the palm again      58.833 wide: Rika holds Ryu up
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local FX = require(script.Parent.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Parent.Util)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Cast = require(script.Parent.Parent.Cast)
local Clash = require(script.Parent.Parent.Clash)
local Common = require(script.Parent.Common)

local Grapple = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local WHITE = Color3.new(1, 1, 1)
local CYAN = Color3.fromRGB(120, 230, 255)

local function h(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end

local ryuGrapple: Rig.Pose = {
	LowerTorso = R(-6, 0, 0),
	UpperTorso = R(16, 10, 0),
	Head = R(-12, -8, 0),
	RightUpperArm = R(60, 0, 10),
	RightLowerArm = R(20, 0, 0),
	LeftUpperArm = R(-20, 0, -40),
	LeftLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(20, 0, -8),
	LeftLowerLeg = R(-24, 0, 0),
	RightUpperLeg = R(-16, 0, 8),
}

local yutaGrip: Rig.Pose = {
	LowerTorso = R(-10, 0, 0),
	UpperTorso = R(20, 0, 0),
	Head = R(-8, 12, 0),
	RightUpperArm = R(75, 0, 18),
	RightLowerArm = R(40, 0, 0),
	LeftUpperArm = R(75, 0, -18),
	LeftLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(30, 0, -6),
	LeftLowerLeg = R(-40, 0, 0),
	RightUpperLeg = R(-20, 0, 6),
}

local ryuShove: Rig.Pose = {
	LowerTorso = R(-4, -10, 0),
	UpperTorso = R(10, -14, 0),
	Head = R(-6, 10, 0),
	RightUpperArm = R(92, 0, -4),
	RightLowerArm = R(0, 0, 0),
	RightHand = R(-60, 0, 0),
	LeftUpperArm = R(-30, 0, -30),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(24, 0, -8),
	LeftLowerLeg = R(-20, 0, 0),
	RightUpperLeg = R(-20, 0, 8),
}

local yutaHit: Rig.Pose = {
	LowerTorso = R(20, 0, 0),
	UpperTorso = R(-30, 0, 0),
	Head = R(-30, 0, 0),
	RightUpperArm = R(70, 0, 40),
	RightLowerArm = R(30, 0, 0),
	LeftUpperArm = R(80, 0, -40),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(50, 0, -10),
	LeftLowerLeg = R(-60, 0, 0),
	RightUpperLeg = R(20, 0, 10),
	RightLowerLeg = R(-30, 0, 0),
}

local ryuSlide: Rig.Pose = {
	HumanoidRootPart = C(0, -0.5, 0),
	LowerTorso = R(-8, 0, 0),
	UpperTorso = R(18, 0, 0),
	Head = R(-14, 0, 0),
	RightUpperArm = R(30, 0, 40),
	RightLowerArm = R(40, 0, 0),
	LeftUpperArm = R(30, 0, -40),
	LeftLowerArm = R(40, 0, 0),
	LeftUpperLeg = R(10, 0, -32),
	LeftLowerLeg = R(-20, 0, 8),
	RightUpperLeg = R(-10, 0, 32),
	RightLowerLeg = R(-14, 0, -8),
}

local ryuBitten: Rig.Pose = {
	LowerTorso = R(0, 0, 0),
	UpperTorso = R(10, 0, 0),
	Head = R(18, 0, 0),
	RightUpperArm = R(40, 0, 72),
	RightLowerArm = R(70, 0, 0),
	LeftUpperArm = R(40, 0, -72),
	LeftLowerArm = R(70, 0, 0),
}

local rikaBite: Rig.Pose = {
	HumanoidRootPart = C(0, 1.2, 0),
	LowerTorso = R(-14, 0, 0),
	UpperTorso = R(-44, 0, 0),
	Head = R(40, 0, 0),
	LeftUpperArm = R(70, 0, -30),
	LeftLowerArm = R(70, 0, 0),
	LeftHand = R(20, 0, 0),
	RightUpperArm = R(70, 0, 30),
	RightLowerArm = R(70, 0, 0),
	RightHand = R(20, 0, 0),
	LeftUpperLeg = R(30, 0, 10),
	LeftLowerLeg = R(-40, 0, -30),
	LeftFoot = R(-40, 0, -40),
}

local rikaLungePose: Rig.Pose = {
	HumanoidRootPart = C(0, 1.4, 0),
	LowerTorso = R(-20, 0, 0),
	UpperTorso = R(-30, 0, 0),
	Head = R(8, 0, 0),
	LeftUpperArm = R(70, 0, -70),
	LeftLowerArm = R(30, 0, 0),
	RightUpperArm = R(70, 0, 70),
	RightLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(40, 0, 10),
	LeftLowerLeg = R(-30, 0, -30),
	LeftFoot = R(-30, 0, -40),
}

local yutaPalm: Rig.Pose = {
	LowerTorso = R(-6, 0, 0),
	UpperTorso = R(10, 0, 0),
	Head = R(-14, 0, 0),
	RightUpperArm = R(100, 0, 6),
	RightLowerArm = R(14, 0, 0),
	RightHand = R(-70, 0, 0),
	LeftUpperArm = R(10, 0, -20),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(24, 0, -6),
	LeftLowerLeg = R(-30, 0, 0),
	RightUpperLeg = R(-18, 0, 6),
}

-- the grapple: Ryu at his mark facing -Z, Yuta pressed against him
local function grappleStage(ctx: Timeline.Ctx, k: number): ({ [string]: CFrame }, { [string]: CFrame })
	local rb = ctx:rig("Ryu", Common.ryuRoot(0), Cast.alive(Cast.mix(Cast.ryu.spread, ryuGrapple, k), ctx.t))
	local yr = C(Common.RYU + V(0.3, 0, -2.5)) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", yr, Cast.alive(yutaGrip, ctx.t))
	return rb, yb
end

local function impact(ctx: Timeline.Ctx)
	local rb = grappleStage(ctx, 1)
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "glare")
	local c = rb.UpperTorso * C(0, 1.4, 0)
	local cam = Util.lookAt(c.Position + V(4.5, 0.6, -1.5), c.Position + V(0, 0.2, -1.2))
	ctx:camera(Clash.shake(cam, ctx.t, 1.2, 24), 60)
	ctx:focus(4.6, 1)
	ctx:flash(WHITE, 0.75 * (1 - ctx.u))
	Common.grade(ctx, 0.05, 0.2, 0.05)
	Common.sky(ctx, "wisps", 22)
end

local function grapple(ctx: Timeline.Ctx)
	local rb = grappleStage(ctx, 1)
	Cast.expr(ctx, "ryu", "grit")
	Cast.expr(ctx, "yuta", "glare")
	local c = rb.UpperTorso * C(0, 1.6, 0)
	local cam = Util.lookAt(c.Position + V(5.4 - ctx.u * 0.6, 0.4, -1.2), c.Position + V(0, 0.4, -1.3))
	ctx:camera(Clash.shake(cam, ctx.t, 0.18, 10), 52)
	ctx:focus(5.2, 1)
	Cast.ryuAura(ctx, rb, 0.5, 3)
	ctx:alpha("wind", 0.6)
	Common.grade(ctx, 0.02, 0.2, 0.05)
	Common.sky(ctx, "low", 24)
end

local function invert(ctx: Timeline.Ctx)
	local rb = grappleStage(ctx, 1)
	Cast.expr(ctx, "ryu", "grit")
	local head = rb.Head * C(0, 0.7, 0)
	ctx:camera(Clash.shake(Util.lookAt(head:PointToWorldSpace(V(-1.2, -0.4, -3.4)), head.Position), ctx.t, 0.5, 20), 50)
	ctx:focus(3.4, 1)
	ctx:flash(WHITE, 0.55 * (1 - ctx.u))
	Common.grade(ctx, 0.15, 0.6, -1, WHITE)
end

local function shove(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local lt = ctx.lt
	local root = Common.ryuRoot(0)
	local rb = ctx:rig("Ryu", root, Cast.alive(ryuShove, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	local fly = lt * 13
	local yr = C(Common.RYU + V(0.6, 0.8 + math.sin(math.min(1, lt * 1.6) * math.pi) * 1.2, -2.8 - fly)) * CFrame.Angles(0, math.rad(180), 0) * CFrame.Angles(math.rad(lt * 70), 0, 0)
	local yb = ctx:rig("Yuta", yr, yutaHit)
	Cast.expr(ctx, "yuta", "shout")
	FX.placeBurst(ctx, hh.blood, (yb.UpperTorso * C(0, 1, -0.5)).Position, lt, 9, 0.18, 0.6, V(0, 0.3, -1), 0.8, 14)
	FX.placeBurst(ctx, hh.spray, Common.RYU + V(0.6, 0.3, -3 - fly), lt % 0.4, 10, 0.5, 0.4, V(0, 1, 0), 1, 22)
	local hand = (rb.RightHand * C(0, -0.5, 0)).Position
	local eye = root:PointToWorldSpace(V(2.2, 3.6, 2.6))
	ctx:camera(Clash.shake(Util.lookAt(eye, hand:Lerp((yb.Head).Position, 0.6)), ctx.t, 0.35, 16), 60)
	ctx:focus((hand - eye).Magnitude, 0.6)
	Common.grade(ctx, 0.02, 0.2, 0.05)
	Common.sky(ctx, "low", 26)
end

local function burst(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.fromRGB(30, 60, 160))
	ctx:camera(C(Clash.O), 60)
	ctx:alpha("speed", 1)
	ctx:flash(WHITE, 0.5 + 0.3 * math.sin(ctx.u * math.pi))
end

local function rikaLunge(ctx: Timeline.Ctx)
	local u = ctx.u
	local base = Common.RYU + V(9 - u * 7, 0, -9 + u * 3)
	local root = C(base) * CFrame.Angles(0, math.rad(60), 0)
	local rb = ctx:rig("Rika", root, Cast.alive(rikaLungePose, ctx.t))
	local head = rb.Head.Position
	local eye = Common.RYU + V(-3, 1.4, -13)
	ctx:camera(Clash.shake(Util.lookAt(eye, head + V(0, -1.5, 0)), ctx.t, 0.35, 14), 62)
	ctx:focus((head - eye).Magnitude, 1)
	ctx:light("RikaMouth", 1.5, nil, 18)
	ctx:alpha("speed", 0.45)
	Common.grade(ctx, 0.02, 0.22, 0.05, Color3.fromRGB(220, 230, 255))
	Common.sky(ctx, "wisps", 40)
end

local function ryuSkid(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local lt = ctx.lt
	local slide = 6 * (1 - math.exp(-lt * 1.6))
	local root = C(Common.RYU + V(0, 0, slide)) * CFrame.Angles(0, 0, 0)
	ctx:rig("Ryu", root, Cast.alive(ryuSlide, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	ctx:rig("Yuta", Common.yutaRoot() * C(0, 0, 6), Cast.yuta.brace)
	for i, foot in { V(-1.2, 0.3, 0.6), V(1.2, 0.3, 0.6) } do
		FX.placeBurst(ctx, if i == 1 then hh.spray else hh.dust, root:PointToWorldSpace(foot), (lt + i * 0.17) % 0.45, 12, 0.5, 0.45, V(0, 0.8, 1), 0.8, 26)
	end
	local eye = Common.RYU + V(1.4, 1.3, 13)
	ctx:camera(Clash.shake(Util.lookAt(eye, Common.RYU + V(0, 3.2, -8)), ctx.t, 0.12, 9), 50)
	ctx:focus(13 - slide, 0.8)
	-- Rika drops in from above at the very end
	if ctx.u > 0.8 then
		local k = (ctx.u - 0.8) / 0.2
		ctx:rig("Rika", C(Common.RYU + V(0, 12 - k * 6, slide - 2)) * CFrame.Angles(0, math.rad(180), 0), rikaBite)
	end
	Cast.ryuAura(ctx, (ctx.frame.rigs :: any).Ryu, 0.4, 2)
	Common.grade(ctx, 0, 0.2, 0.05)
	Common.sky(ctx, "low", 30)
end

-- Rika's jaws closing over Ryu's head: place her so her head sits on his
local function rikaOnRyu(ctx: Timeline.Ctx, ryuRoot: CFrame, pose: Rig.Pose): ({ [string]: CFrame }, { [string]: CFrame })
	local rb = ctx:rig("Ryu", ryuRoot, pose)
	local target = (rb.Head * C(0, 1.9, 0.5)).Position
	local r0 = C(ryuRoot.Position + V(0, 0, 4)) * CFrame.Angles(0, math.rad(180), 0)
	local kb = ctx:rig("Rika", r0, rikaBite)
	local delta = target - kb.Head.Position
	kb = ctx:rig("Rika", C(delta) * r0, rikaBite)
	return rb, kb
end

local function grab(ctx: Timeline.Ctx)
	local rb, kb = rikaOnRyu(ctx, C(Common.RYU + V(0, 0, 6)), Cast.alive(ryuBitten, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	local eye = rb.UpperTorso:PointToWorldSpace(V(1.5, -0.6, -5.5))
	ctx:camera(Clash.shake(Util.lookAt(eye, kb.Head.Position:Lerp(rb.Head.Position, 0.5)), ctx.t, 0.5, 18), 62)
	ctx:focus(6, 0.8)
	ctx:light("RikaMouth", 1.6, nil, 16)
	Common.grade(ctx, 0, 0.25, 0.05)
	Common.sky(ctx, "wisps", 30)
end

local function bloodOn(ctx: Timeline.Ctx, head: CFrame, k: number)
	local hh = h(ctx)
	local spots = { V(-0.12, 1.1, -0.6), V(0.18, 1.0, -0.62), V(0.05, 0.86, -0.64), V(-0.3, 0.95, -0.58), V(0.32, 0.8, -0.6), V(0.0, 0.7, -0.64), V(-0.16, 0.62, -0.63) }
	for i, p in hh.rikaBlood do
		ctx:place(p, head * C(spots[i]))
		local sz = (0.1 + (i % 3) * 0.05) * k
		ctx:prop(p, { s = V(sz, sz * 2.6, sz * 0.5) })
	end
end

local function bitten(ctx: Timeline.Ctx)
	local rb = rikaOnRyu(ctx, C(Common.RYU + V(0, 0, 6)), Cast.alive(ryuBitten, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodOn(ctx, rb.Head, 1)
	local head = rb.Head * C(0, 0.7, 0)
	local eye = head:PointToWorldSpace(V(1.0, -0.7, -2.7))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, 0.3, 0)), ctx.t, 0.18, 14), 52)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:light("RyuFace", 0.8, Color3.fromRGB(200, 210, 255), 8)
	Common.grade(ctx, -0.04, 0.25, 0)
end

local function rikaHead(ctx: Timeline.Ctx)
	local rb, kb = rikaOnRyu(ctx, C(Common.RYU + V(0, 0, 6)), Cast.alive(ryuBitten, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodOn(ctx, rb.Head, 1)
	local head = kb.Head
	local eye = head:PointToWorldSpace(V(5.2, 0.6, -3.6 + ctx.u * 0.4))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.8, 0)), ctx.t, 0.12, 10), 52)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:light("RikaMouth", 0.5, nil, 10)
	Common.grade(ctx, -0.02, 0.25, 0, Color3.fromRGB(220, 225, 255))
	Common.sky(ctx, "wisps", 24)
end

-- Yuta's palm pressed flat on Ryu's bare chest (two-step: put the palm on
-- the chest point)
local function palmStage(ctx: Timeline.Ctx): ({ [string]: CFrame }, { [string]: CFrame }, Vector3)
	local rr = Common.ryuRoot(0)
	local rb = ctx:rig("RyuBare", rr, Cast.alive(ryuBitten, ctx.t))
	local chest = (rb.UpperTorso * C(0.15, 1.05, -0.72)).Position
	local y0 = C(Common.RYU + V(0, 0, -3)) * CFrame.Angles(0, math.rad(180), 0)
	local yb = ctx:rig("Yuta", y0, yutaPalm)
	local palm = (yb.RightHand * C(0, -0.3, 0)).Position
	yb = ctx:rig("Yuta", C(chest - palm) * y0, yutaPalm)
	return rb, yb, chest
end

local function chest(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local rb, yb, pt = palmStage(ctx)
	Cast.expr(ctx, "yuta", "glare")
	Cast.expr(ctx, "ryu", "grit")
	local eye = rb.UpperTorso:PointToWorldSpace(V(-1.6, 1.4, 2.6))
	ctx:camera(Clash.shake(Util.lookAt(eye, yb.Head.Position:Lerp(pt, 0.4)), ctx.t, 0.06, 8), 55)
	ctx:focus((yb.Head.Position - eye).Magnitude, 1)
	FX.placeCore(ctx, hh.palmGlow, pt, 0.35 + math.sin(ctx.t * 30) * 0.05, 0.9)
	ctx:light("YutaAura", 2.4, CYAN, 10)
	Common.grade(ctx, -0.02, 0.22, 0.05, Color3.fromRGB(220, 230, 255))
	Common.sky(ctx, "wisps", 22)
end

local function palmClose(ctx: Timeline.Ctx, stage: number, push: number)
	local hh = h(ctx)
	local _, _, pt = palmStage(ctx)
	Cast.expr(ctx, "ryu", "grit")
	local eye = pt + V(2.3 - push * 0.35, 0.45, -0.7)
	ctx:camera(Clash.shake(Util.lookAt(eye, pt), ctx.t, 0.04, 6), 50)
	ctx:focus((pt - eye).Magnitude, 1)
	FX.placeCore(ctx, hh.palmGlow, pt + V(0, 0, -0.1), 0.3 + math.sin(ctx.t * 30) * 0.04, 0.9)
	ctx:show("crack" .. stage)
	ctx:light("YutaAura", 2.4, CYAN, 8)
	Common.grade(ctx, -0.04, 0.24, 0, Color3.fromRGB(225, 232, 255))
end

local function palm(ctx: Timeline.Ctx)
	palmClose(ctx, 1 + math.min(2, math.floor(ctx.u * 3)), ctx.u)
end

local function palm2(ctx: Timeline.Ctx)
	palmClose(ctx, 3, 1 + ctx.u * 0.5)
end

local function timer(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show(if ctx.t < 55.9 then "timer17" else "timer09")
end

local function timerZero(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("timer00")
end

local function wide(ctx: Timeline.Ctx)
	local rb, kb = rikaOnRyu(ctx, C(Common.RYU + V(0, 2.5, 0)), ryuBitten)
	local _ = rb
	ctx:rig("Yuta", C(Common.RYU + V(6, 0, -5)) * CFrame.Angles(0, math.rad(150), 0), Cast.yuta.stand)
	local eye = Common.RYU + V(4, 1.2, -26)
	ctx:camera(Util.lookAt(eye, kb.Head.Position:Lerp(Common.RYU, 0.6)), 50)
	ctx:focus(26, 0.8)
	Common.grade(ctx, 0, 0.2, 0.05)
	Common.sky(ctx, "low", 30)
end

Grapple.shots = {
	{ id = "P2 34 impact", t0 = 45.8, t1 = 46.133, run = impact },
	{ id = "P2 35 grapple", t0 = 46.133, t1 = 47.767, run = grapple },
	{ id = "P2 36 negative", t0 = 47.767, t1 = 48.267, run = invert },
	{ id = "P2 37 shove", t0 = 48.267, t1 = 48.9, run = shove },
	{ id = "P2 38 burst", t0 = 48.9, t1 = 49.167, run = burst },
	{ id = "P2 39 rika lunges", t0 = 49.167, t1 = 50.067, run = rikaLunge },
	{ id = "P2 40 ryu skids", t0 = 50.067, t1 = 51.533, run = ryuSkid },
	{ id = "P2 41 grab", t0 = 51.533, t1 = 51.867, run = grab },
	{ id = "P2 42 bitten", t0 = 51.867, t1 = 52.533, run = bitten },
	{ id = "P2 43 rika head", t0 = 52.533, t1 = 53.4, run = rikaHead },
	{ id = "P2 44 chest", t0 = 53.4, t1 = 54.5, run = chest },
	{ id = "P2 45 palm", t0 = 54.5, t1 = 55.833, run = palm },
	{ id = "P2 46 timer", t0 = 55.833, t1 = 56.0, run = timer },
	{ id = "P2 47 zero", t0 = 56.0, t1 = 57.1, run = timerZero },
	{ id = "P2 48 palm", t0 = 57.1, t1 = 58.833, run = palm2 },
	{ id = "P2 49 wide", t0 = 58.833, t1 = 59.167, run = wide },
} :: { Timeline.Shot }

return Grapple
