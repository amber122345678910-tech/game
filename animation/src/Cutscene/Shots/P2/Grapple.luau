--!strict
-- Part 2, 45.800-59.167: Yuta's "Thin Ice Breaker" punch into Ryu's chest;
-- Ryu knocks him back; Rika flies in and drives her fist down onto Ryu's
-- head; Yuta catches Ryu with both palms on his stomach while the countdown
-- runs out and Rika's shell cracks and crumbles. "Five minutes."
--  45.800 impact (blur)       46.133 the punch into the chest  47.767 negative
--  48.267 Ryu hits Yuta back  48.900 radial burst              49.167 Rika flies in
--  50.067 Ryu skids back      51.533 her fist comes down       51.867 fist on his head
--  52.533 Rika's head, red eye 53.400 Yuta catches Ryu         54.500 the hands, cracks
--  55.833 countdown           56.000 0:00:00                   57.100 the hands, shards fall
--  58.833 wide: Rika's fist on Ryu, Yuta holding him
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

-- Ryu doubled over the fist in his chest, eyes white
local ryuHit: Rig.Pose = {
	LowerTorso = R(-6, 0, 0),
	UpperTorso = R(26, 0, 0),
	Head = R(12, 0, 0),
	RightUpperArm = R(30, 0, 50),
	RightLowerArm = R(30, 0, 0),
	LeftUpperArm = R(30, 0, -50),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(16, 0, -6),
	LeftLowerLeg = R(-20, 0, 0),
	RightUpperLeg = R(-12, 0, 6),
}

-- Yuta's right fist driven forward, the whole body behind it
local yutaPunch: Rig.Pose = {
	LowerTorso = R(-10, 20, 0),
	UpperTorso = R(16, 26, 0),
	Head = R(-6, -26, 0),
	RightUpperArm = R(92, 0, 2),
	RightLowerArm = R(0, 0, 0),
	RightHand = R(-80, 0, 0),
	LeftUpperArm = R(-30, 0, -30),
	LeftLowerArm = R(60, 0, 0),
	LeftUpperLeg = R(40, 0, -8),
	LeftLowerLeg = R(-40, 0, 0),
	RightUpperLeg = R(-30, 0, 8),
	RightLowerLeg = R(-10, 0, 0),
}

local ryuStrike: Rig.Pose = {
	LowerTorso = R(-4, -10, 0),
	UpperTorso = R(10, -14, 0),
	Head = R(-6, 10, 0),
	RightUpperArm = R(92, 0, -4),
	RightLowerArm = R(0, 0, 0),
	RightHand = R(-80, 0, 0),
	LeftUpperArm = R(-30, 0, -30),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(24, 0, -8),
	LeftLowerLeg = R(-20, 0, 0),
	RightUpperLeg = R(-20, 0, 8),
}

local yutaFlung: Rig.Pose = {
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

-- Yuta down on one knee, right arm raised
local yutaKneel: Rig.Pose = {
	HumanoidRootPart = C(0, -0.95, 0),
	LowerTorso = R(-6, 0, 0),
	UpperTorso = R(16, 0, 0),
	Head = R(-14, 0, 0),
	RightUpperArm = R(150, 0, 20),
	RightLowerArm = R(20, 0, 0),
	LeftUpperArm = R(20, 0, -20),
	LeftLowerArm = R(50, 0, 0),
	LeftUpperLeg = R(90, 0, -6),
	LeftLowerLeg = R(-90, 0, 0),
	RightUpperLeg = R(-20, 0, 6),
	RightLowerLeg = R(-100, 0, 0),
}

-- Ryu under Rika's fist: head pushed down, arms thrown out
local ryuPinned: Rig.Pose = {
	UpperTorso = R(10, 0, 0),
	Head = R(18, 0, 0),
	RightUpperArm = R(40, 0, 72),
	RightLowerArm = R(70, 0, 0),
	LeftUpperArm = R(40, 0, -72),
	LeftLowerArm = R(70, 0, 0),
}

-- Ryu sagging backwards into Yuta's hands (coat slipped down)
local ryuSag: Rig.Pose = {
	LowerTorso = R(6, 0, 0),
	UpperTorso = R(-14, 0, 0),
	Head = R(-22, 0, 0),
	RightUpperArm = R(-10, 0, 34),
	RightLowerArm = R(20, 0, 0),
	LeftUpperArm = R(-10, 0, -34),
	LeftLowerArm = R(20, 0, 0),
	LeftUpperLeg = R(-6, 0, -6),
	RightUpperLeg = R(-6, 0, 6),
}

-- Yuta holding him up, both palms flat on his stomach
local yutaCatch: Rig.Pose = {
	LowerTorso = R(-8, 0, 0),
	UpperTorso = R(14, 0, 0),
	Head = R(-12, 0, 0),
	RightUpperArm = R(78, 0, 14),
	RightLowerArm = R(26, 0, 0),
	RightHand = R(-70, 0, 0),
	LeftUpperArm = R(78, 0, -14),
	LeftLowerArm = R(26, 0, 0),
	LeftHand = R(-70, 0, 0),
	LeftUpperLeg = R(26, 0, -6),
	LeftLowerLeg = R(-30, 0, 0),
	RightUpperLeg = R(-18, 0, 6),
}

-- Rika flying in, right fist drawn back, jaws open
local rikaSwing: Rig.Pose = {
	HumanoidRootPart = C(0, 1.4, 0),
	LowerTorso = R(-20, 0, 0),
	UpperTorso = R(-30, 10, 0),
	Head = R(8, -10, 0),
	RightUpperArm = R(150, 0, 40),
	RightLowerArm = R(80, 0, 0),
	RightHand = R(30, 0, 0),
	LeftUpperArm = R(70, 0, -50),
	LeftLowerArm = R(30, 0, 0),
	LeftUpperLeg = R(40, 0, 10),
	LeftLowerLeg = R(-30, 0, -30),
	LeftFoot = R(-30, 0, -40),
}

-- Rika bent over, her right fist pressing down
local rikaPound: Rig.Pose = {
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

-- Rika behind Ryu with her fist on top of his head
local function rikaFistOn(ctx: Timeline.Ctx, ryuRig: string, ryuRoot: CFrame, pose: Rig.Pose, lift: number?): ({ [string]: CFrame }, { [string]: CFrame })
	local rb = ctx:rig(ryuRig, ryuRoot, pose)
	local top = (rb.Head * C(0, 2.2 + (lift or 0), 0)).Position
	local kb = Common.rigAt(ctx, "Rika", C(ryuRoot.Position + V(1.5, 0, 4.5)), rikaPound, "RightHand", C(0, -0.9, 0), top)
	Common.rikaEye(ctx, kb)
	return rb, kb
end

-- the punch: Yuta at Ryu's chest, his fist buried in it
local function punchStage(ctx: Timeline.Ctx): ({ [string]: CFrame }, { [string]: CFrame }, Vector3)
	local rb = ctx:rig("RyuLoose", Common.ryuRoot(0), Cast.alive(ryuHit, ctx.t))
	local chest = (rb.UpperTorso * C(0, 0.9, -0.62)).Position
	local y0 = C(Common.RYU + V(0.4, 0, -3)) * CFrame.Angles(0, math.rad(180), 0)
	local yb = Common.rigAt(ctx, "Yuta", y0, yutaPunch, "RightHand", C(0, -0.35, 0), chest)
	return rb, yb, chest
end

local function impact(ctx: Timeline.Ctx)
	ctx:wind(1.5)
	ctx:gust(2.2 * (1 - ctx.u))
	local hh = h(ctx)
	local _, _, chest = punchStage(ctx)
	Cast.expr(ctx, "ryu", "shock")
	-- Yuta shouts the technique's name
	Cast.expr(ctx, "yuta", if Util.noise1(ctx.t * 7, 9) > -0.3 then "shout" else "glare")
	FX.placeBurst(ctx, hh.shards, chest, ctx.lt, 24, 0.6, 0.6, nil, nil, 0)
	local cam = Util.lookAt(chest + V(4.8, 0.6, -1.4), chest + V(0, 0.2, -0.6))
	ctx:camera(Clash.shake(cam, ctx.t, 1.2, 24), 60)
	ctx:focus(5, 1)
	ctx:flash(WHITE, 0.75 * (1 - ctx.u))
	Common.grade(ctx, 0.05, 0.2, 0.05)
	Common.sky(ctx, "wisps", 22)
end

-- profile: the fist in Ryu's chest, space shattering round it like glass
local function punch(ctx: Timeline.Ctx)
	ctx:wind(1.6)
	ctx:gust(1.2 * math.exp(-ctx.lt * 2.5))
	local hh = h(ctx)
	local rb, _, chest = punchStage(ctx)
	Cast.expr(ctx, "ryu", "shock")
	if ctx.t < 46.3 then
		Cast.expr(ctx, "yuta", if Util.noise1(ctx.t * 7, 9) > -0.3 then "shout" else "glare")
	else
		Cast.expr(ctx, "yuta", "shout")
	end
	FX.placeBurst(ctx, hh.shards, chest, ctx.lt % 0.8, 20, 0.7, 0.8, nil, nil, 0)
	FX.placeBurst(ctx, hh.streamers, chest, ctx.lt % 0.5, 26, 0.5, 0.5, nil, nil, 0)
	FX.placeBurst(ctx, hh.blood, chest + V(0, 0.3, 0), ctx.lt, 8, 0.16, 0.7, V(0, 0.5, 1), 0.8, 12)
	local c = rb.UpperTorso * C(0, 1.4, 0)
	local cam = Util.lookAt(c.Position + V(5.4 - ctx.u * 0.6, 0.3, -1.4), c.Position + V(0, 0.2, -1.3))
	ctx:camera(Clash.shake(cam, ctx.t, 0.2, 12), 52)
	ctx:focus(5.2, 1)
	ctx:alpha("wind", 0.6)
	Common.grade(ctx, 0.02, 0.22, 0.05)
	Common.sky(ctx, "low", 24)
end

local function invert(ctx: Timeline.Ctx)
	local rb = punchStage(ctx)
	Cast.expr(ctx, "ryu", "grit")
	local head = rb.Head * C(0, 0.7, 0)
	ctx:camera(Clash.shake(Util.lookAt(head:PointToWorldSpace(V(-1.2, -0.4, -3.4)), head.Position), ctx.t, 0.5, 20), 50)
	ctx:focus(3.4, 1)
	ctx:flash(WHITE, 0.55 * (1 - ctx.u))
	Common.grade(ctx, 0.15, 0.6, -1, WHITE)
end

-- Ryu's fist (foreground) sends Yuta flying back across the cracked deck
local function strike(ctx: Timeline.Ctx)
	ctx:wind(1.6)
	ctx:gust(1.8 * math.exp(-ctx.lt * 3))
	local hh = h(ctx)
	local lt = ctx.lt
	local root = Common.ryuRoot(0)
	local rb = ctx:rig("RyuLoose", root, Cast.alive(ryuStrike, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	local fly = lt * 13
	local yr = C(Common.RYU + V(0.6, 0.8 + math.sin(math.min(1, lt * 1.6) * math.pi) * 1.2, -2.8 - fly)) * CFrame.Angles(0, math.rad(180), 0) * CFrame.Angles(math.rad(lt * 70), 0, 0)
	local yb = ctx:rig("Yuta", yr, yutaFlung)
	Cast.expr(ctx, "yuta", "shout")
	FX.placeBurst(ctx, hh.blood, (yb.UpperTorso * C(0, 1, -0.5)).Position, lt, 9, 0.18, 0.6, V(0, 0.3, -1), 0.8, 14)
	FX.placeBurst(ctx, hh.dust, Common.RYU + V(0.6, 0.3, -3 - fly), lt % 0.4, 10, 0.5, 0.4, V(0, 1, 0), 1, 22)
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

-- Rika flies straight at the camera, right fist drawn back, red eye blazing
local function rikaFlies(ctx: Timeline.Ctx)
	ctx:wind(2.6)
	local u = ctx.u
	local base = Common.RYU + V(8 - u * 6, 0, -10 + u * 4)
	local root = C(base) * CFrame.Angles(0, math.rad(55), 0)
	local rb = ctx:rig("Rika", root, Cast.alive(rikaSwing, ctx.t))
	Common.rikaEye(ctx, rb)
	local head = rb.Head.Position
	local eye = Common.RYU + V(-3, 1.4, -13 + u * 2)
	ctx:camera(Clash.shake(Util.lookAt(eye, head + V(0, -1.5, 0)), ctx.t, 0.35, 14), 62)
	ctx:focus((head - eye).Magnitude, 1)
	ctx:light("RikaMouth", 1.2, nil, 18)
	ctx:alpha("speed", 0.45)
	Common.grade(ctx, 0.02, 0.22, 0.05, Color3.fromRGB(220, 230, 255))
	Common.sky(ctx, "wisps", 40)
end

-- from behind, low: Ryu skids back on the deck, Yuta far off on one knee,
-- Rika's shadow falling over Ryu from above
-- Ryu skidding back on his heels: bent far forward towards Yuta, a wide
-- low stance, arms flung out to the sides (the fur cuffs)
local ryuSkidPose: Rig.Pose = {
	HumanoidRootPart = C(0, -0.9, 0),
	LowerTorso = R(-38, 0, 0),
	UpperTorso = R(-22, 0, 0),
	Head = R(44, 0, 0),
	RightUpperArm = R(34, 0, 58),
	RightLowerArm = R(34, 0, 0),
	RightHand = R(30, 0, 0),
	LeftUpperArm = R(34, 0, -58),
	LeftLowerArm = R(34, 0, 0),
	LeftHand = R(30, 0, 0),
	LeftUpperLeg = R(60, 0, -30),
	LeftLowerLeg = R(-44, 0, 6),
	LeftFoot = R(-10, 0, 0),
	RightUpperLeg = R(30, 0, 30),
	RightLowerLeg = R(-30, 0, -6),
	RightFoot = R(-10, 0, 0),
}

local function ryuSkid(ctx: Timeline.Ctx)
	ctx:wind(1.8)
	local hh = h(ctx)
	local t = ctx.t
	local lt = ctx.lt
	-- 50.067-51.133: low behind Ryu as he skids back towards us, bent far
	-- forward, arms out, concrete spraying from his heels; Yuta small in
	-- the distance on the right, down on one knee, his right arm raised.
	-- The camera swoops in low (50.07-50.35), then backs off with him.
	local slide = 7 * (1 - math.exp(-lt * 1.3))
	local root = C(Common.RYU + V(0, 0, slide))
	local wobble = math.sin(t * 17) * 2
	local rb = ctx:rig("RyuLoose", root, Cast.alive(Cast.add(ryuSkidPose, "UpperTorso", R(wobble, 0, wobble * 0.5)), t))
	Cast.expr(ctx, "ryu", "grit")
	ctx:rig("Yuta", C(Common.RYU + V(5.5, 0, -24)) * CFrame.Angles(0, math.pi, 0), Cast.alive(yutaKneel, t))
	if t < 51.133 then
		ctx:gust(0.8 * math.exp(-lt * 1.5) + 0.4)
		for i, foot in { "LeftFoot", "RightFoot" } do
			local p = (rb[foot] * C(0, -0.3, 0.2)).Position
			FX.placeBurst(ctx, if i == 1 then hh.spray else hh.dust, p, (lt + i * 0.17) % 0.45, 12, 0.5, 0.45, V(0, 0.8, 1), 0.8, 26)
		end
		local swoop = Util.smoothstep(50.067, 50.35, t)
		local base = Common.RYU + V(0, 0, slide)
		local eye = base + V(3.2 - swoop * 1.2, 4.5 - swoop * 4.0, 12 - swoop * 8.2)
		local look = base + V(1.4, 2.4 - swoop * 0.2, -14)
		ctx:camera(Clash.shake(Util.lookAt(eye, look), t, 0.12 + (if t < 50.35 then 0.6 else 0), 9), 56)
		ctx:focus((Common.RYU + V(5.5, 2, -24) - eye).Magnitude, 0.5)
		if t > 50.2 and t < 50.32 then
			ctx:alpha("speed", 0.5)
		end
	else
		-- 51.133: up past the back of Ryu's head at Rika looming over him,
		-- her fist raised
		local k = Util.smoothstep(51.133, 51.533, t)
		-- Rika in front of him, facing him, bent over him
		local kb = ctx:rig("Rika", C(Common.RYU + V(1.0, -1.5 - k * 1.5, slide - 6.5)) * CFrame.Angles(0, math.pi + math.rad(10), 0), Cast.alive(rikaSwing, t))
		Common.rikaEye(ctx, kb)
		local head = (rb.Head * C(0, 0.8, 0)).Position
		local back = rb.UpperTorso.Position
		local eye = back + V(0.9, -1.6, 4.6)
		local face = (kb.Head * C(0, 1.0, -1.2)).Position
		ctx:camera(Clash.shake(Util.lookAt(eye, face:Lerp(head, 0.3)), t, 0.1, 9), 62)
		ctx:focus((face - eye).Magnitude, 0.6)
		ctx:light("RikaMouth", 0.9, Color3.fromRGB(200, 212, 255), 22)
		ctx:gust(0.6)
	end
	Common.grade(ctx, -0.04, 0.2, 0.05)
	Common.sky(ctx, "low", 30)
end

-- low angle: the fist comes down on Ryu's head
local function fistDown(ctx: Timeline.Ctx)
	ctx:wind(1.4)
	ctx:gust(2.0 * Util.smoothstep(0.55, 0.75, ctx.u))
	local k = 1 - Util.smoothstep(0, 0.7, ctx.u)
	local rb, kb = rikaFistOn(ctx, "RyuLoose", C(Common.RYU + V(0, 0, 6)), Cast.alive(ryuPinned, ctx.t), k * 2.5)
	Cast.expr(ctx, "ryu", "grit")
	local eye = rb.UpperTorso:PointToWorldSpace(V(1.8, -0.8, -6))
	ctx:camera(Clash.shake(Util.lookAt(eye, kb.RightHand.Position:Lerp(rb.Head.Position, 0.5)), ctx.t, 0.5, 18), 62)
	ctx:focus(6.5, 0.8)
	ctx:light("RikaMouth", 0.8, nil, 14)
	Common.grade(ctx, -0.04, 0.25, 0.05)
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

-- his face: the fist on his forehead, blood, teeth bared in pain
local function fistOnHead(ctx: Timeline.Ctx)
	ctx:gust(1.4 * math.exp(-ctx.lt * 3))
	local hh = h(ctx)
	local rb = rikaFistOn(ctx, "RyuLoose", C(Common.RYU + V(0, 0, 6)), Cast.alive(ryuPinned, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodOn(ctx, rb.Head, 1)
	local head = rb.Head * C(0, 0.7, 0)
	FX.placeBurst(ctx, hh.blood, head.Position + V(0, 0.8, -0.4), ctx.lt % 0.33, 8, 0.12, 0.33, V(0, 0.6, -1), 1, 10)
	local eye = head:PointToWorldSpace(V(0.6, -0.5, -2.4))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, 0.35, 0)), ctx.t, 0.22, 16), 52)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:light("RyuFace", 0.8, Color3.fromRGB(200, 210, 255), 8)
	Common.grade(ctx, -0.04, 0.25, 0)
end

-- Rika's head looming over Ryu, her red eye, her fist on him
local function rikaHead(ctx: Timeline.Ctx)
	local rb, kb = rikaFistOn(ctx, "RyuLoose", C(Common.RYU + V(0, 0, 6)), Cast.alive(ryuPinned, ctx.t))
	Cast.expr(ctx, "ryu", "grit")
	bloodOn(ctx, rb.Head, 1)
	local head = kb.Head
	local eye = head:PointToWorldSpace(V(1.2, -1.2, -5.6 + ctx.u * 0.5))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.4, 0)), ctx.t, 0.1, 10), 54)
	ctx:focus((head.Position - eye).Magnitude, 1)
	ctx:light("RikaMouth", 0.6, nil, 10)
	Common.grade(ctx, -0.04, 0.25, 0, Color3.fromRGB(220, 225, 255))
	Common.sky(ctx, "wisps", 24)
end

-- Yuta holding the sagging Ryu (coat slipped off), both palms on his stomach,
-- Rika's fist still on his head
local function catchStage(ctx: Timeline.Ctx): ({ [string]: CFrame }, { [string]: CFrame }, { [string]: CFrame }, Vector3)
	local rr = Common.ryuRoot(0)
	local rb, kb = rikaFistOn(ctx, "RyuBare", rr, Cast.alive(ryuSag, ctx.t))
	local belly = (rb.UpperTorso * C(0, 0.45, -0.62)).Position
	local y0 = C(Common.RYU + V(0.2, 0, -2.6)) * CFrame.Angles(0, math.rad(180), 0)
	-- 58.3-58.8: the fingers tremble and dig in (a fast small shake of both
	-- hands, the wrists bending into his stomach)
	local pose = yutaCatch
	local tr = Util.smoothstep(58.25, 58.35, ctx.t) * (1 - Util.smoothstep(58.75, 58.85, ctx.t))
	if tr > 0 then
		local a = math.sin(ctx.t * 70) * 3 * tr
		local b = math.sin(ctx.t * 83 + 1) * 3 * tr
		pose = Cast.add(Cast.add(pose, "LeftHand", R(a - 8 * tr, 0, b)), "RightHand", R(b - 8 * tr, 0, -a))
	end
	local b0 = ctx:rig("Yuta", y0, pose)
	local mid = ((b0.LeftHand * C(0, -0.35, 0)).Position + (b0.RightHand * C(0, -0.35, 0)).Position) / 2
	local yb = ctx:rig("Yuta", C(belly - mid) * y0, pose)
	return rb, yb, kb, belly
end

local function catch(ctx: Timeline.Ctx)
	ctx:wind(1.2)
	ctx:gust(0.5 * math.exp(-ctx.lt * 2))
	local hh = h(ctx)
	local rb, yb, _, belly = catchStage(ctx)
	Cast.expr(ctx, "yuta", "glare")
	Cast.expr(ctx, "ryu", "grit")
	local eye = rb.UpperTorso:PointToWorldSpace(V(3.6, 1.3, 1.0))
	ctx:camera(Clash.shake(Util.lookAt(eye, yb.Head.Position:Lerp(belly, 0.5)), ctx.t, 0.06, 8), 55)
	ctx:focus((yb.Head.Position - eye).Magnitude, 1)
	FX.placeBolt(ctx, hh.bolts, 1, belly + V(-0.4, 0, -0.2), belly + V(0.4, 0.2, -0.2), 5, 0.1, 0.02, 3, 16)
	ctx:light("YutaAura", 1.0, CYAN, 8)
	Common.grade(ctx, -0.04, 0.22, 0.05, Color3.fromRGB(220, 230, 255))
	Common.sky(ctx, "wisps", 22)
end

-- the hands on his stomach; behind them Rika's eye cracks like glass and
-- her black shell crumbles away
local function hands(ctx: Timeline.Ctx, stage: number, push: number, fall: number)
	local hh = h(ctx)
	local _, _, kb, belly = catchStage(ctx)
	Cast.expr(ctx, "ryu", "grit")
	local eye = belly + V(2.8 - push * 0.4, 0.5, -0.9)
	ctx:camera(Clash.shake(Util.lookAt(eye, belly + V(0, 0.3, -0.5)), ctx.t, 0.04, 6), 52)
	ctx:focus((belly - eye).Magnitude, 1)
	ctx:alpha("crack" .. stage, 0.7)
	-- black shards of Rika's shell drifting down behind them
	if fall > 0 then
		local top = kb.Head.Position
		for i, p in hh.shell.parts do
			local rr = Util.rng(900 + i)
			local ph = (ctx.t * (0.35 + Util.rand(rr) * 0.3) + Util.rand(rr)) % 1
			local pos = top + V(Util.randRange(rr, -5, 5), 2 - ph * 9, Util.randRange(rr, -2, 3))
			ctx:place(p, CFrame.new(pos) * CFrame.Angles(ph * 6 + i, i, ph * 4))
			local sz = (0.3 + (i % 4) * 0.12) * fall
			ctx:prop(p, { s = V(sz, sz * 1.5, sz * 0.25) })
		end
	end
	ctx:light("YutaAura", 0.8, CYAN, 6)
	ctx:bloom(1.1)
	Common.grade(ctx, -0.1, 0.26, 0, Color3.fromRGB(225, 232, 255))
end

local function handsA(ctx: Timeline.Ctx)
	hands(ctx, 1 + math.min(2, math.floor(ctx.u * 3)), ctx.u, 0.4 * ctx.u)
end

local function handsB(ctx: Timeline.Ctx)
	hands(ctx, 3, 1 + ctx.u * 0.5, 1)
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

-- wide: Rika's fist on Ryu's head, Yuta holding Ryu up by the waist
local function wide(ctx: Timeline.Ctx)
	local _, _, kb, _ = catchStage(ctx)
	Cast.expr(ctx, "ryu", "grit")
	local eye = Common.RYU + V(4, 1.4, -17)
	ctx:camera(Util.lookAt(eye, kb.Head.Position:Lerp(Common.RYU + V(0, 3, 0), 0.6)), 52)
	ctx:focus(17, 0.8)
	Common.grade(ctx, -0.02, 0.2, 0.05)
	Common.sky(ctx, "low", 30)
end

Grapple.shots = {
	{ id = "P2 34 impact", t0 = 45.8, t1 = 46.133, run = impact },
	{ id = "P2 35 punch", t0 = 46.133, t1 = 47.767, run = punch },
	{ id = "P2 36 negative", t0 = 47.767, t1 = 48.267, run = invert },
	{ id = "P2 37 strike", t0 = 48.267, t1 = 48.9, run = strike },
	{ id = "P2 38 burst", t0 = 48.9, t1 = 49.167, run = burst },
	{ id = "P2 39 rika flies", t0 = 49.167, t1 = 50.067, run = rikaFlies },
	{ id = "P2 40 ryu skids", t0 = 50.067, t1 = 51.533, run = ryuSkid },
	{ id = "P2 41 fist down", t0 = 51.533, t1 = 51.867, run = fistDown },
	{ id = "P2 42 fist on head", t0 = 51.867, t1 = 52.533, run = fistOnHead },
	{ id = "P2 43 rika head", t0 = 52.533, t1 = 53.4, run = rikaHead },
	{ id = "P2 44 catch", t0 = 53.4, t1 = 54.5, run = catch },
	{ id = "P2 45 hands", t0 = 54.5, t1 = 55.833, run = handsA },
	{ id = "P2 46 timer", t0 = 55.833, t1 = 56.0, run = timer },
	{ id = "P2 47 zero", t0 = 56.0, t1 = 57.1, run = timerZero },
	{ id = "P2 48 hands", t0 = 57.1, t1 = 58.833, run = handsB },
	{ id = "P2 49 wide", t0 = 58.833, t1 = 59.167, run = wide },
} :: { Timeline.Shot }

return Grapple
