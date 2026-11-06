--!strict
-- Part 2 flashbacks: Ryu remembers Yuta's fight with Uro (docs/part2_flashback.md).
-- Drawn pale over coloured painted skies, under a huge boiling line-art eye.
--  31.300 Yuta and Uro grapple in mid-air, his left arm stretched like rubber
--  32.067 from above and behind Yuta: Uro clings round his head (push in)
--  33.233 Uro floats, both palms out, Yuta blasted away from her
--  33.833 close: her palms on his bloodied face   34.000 it goes dark, cracks
--  34.333 the sky shatters round Yuta, a ring      35.033 a burst of dust: Rika
--  35.633 Rika's huge hand catches Uro by the arm  36.667 Rika bites her shoulder
--  36.867 Rika's arm sweeps across                 37.133 glitch; the arm torn off
--  37.333 Ryu's eye wide (painted close-up)
--  42.900 Uro's severed arm tumbling, blood trailing
--  43.567 Rika's face, the arm in her jaws         44.700 "Thin Ice Breaker!"
local Builder = require(script.Parent.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local CloseupSet = require(script.Parent.Parent.Parent.Art.Sets.CloseupSet)
local FX = require(script.Parent.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Parent.Util)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Cast = require(script.Parent.Parent.Cast)
local Clash = require(script.Parent.Parent.Clash)
local Common = require(script.Parent.Common)
local FlashArt = require(script.Parent.FlashArt)
local Uro = require(script.Parent.Parent.Parent.Art.Characters.Uro)

local Flashback = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R
local rad = math.rad
local ss = Util.smoothstep

local O = Common.FB
local AIR = O + V(0, 150, 0) -- the fight in the open sky, far above the roof
local MID = 3.2 -- a character's middle above its root (roots are at the feet)
local CEN = AIR + V(0, MID, 0)
local WHITE = Color3.new(1, 1, 1)

local function h(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end
local function fl(ctx: Timeline.Ctx): FlashArt.H
	return ctx.scene.data.flash
end

-- camera from `pos` at `target`, rolled in the picture plane
local function cam(ctx: Timeline.Ctx, pos: Vector3, target: Vector3, fov: number, roll: number?, up: Vector3?)
	local cf = Util.lookAt(pos, target, up)
	if roll and roll ~= 0 then
		cf = cf * CFrame.Angles(0, 0, roll)
	end
	ctx:camera(cf, fov)
	ctx:focus((target - pos).Magnitude, 0.25)
end

-- the look of every flashback frame: no fog, pale lit characters, the eye
local function look(ctx: Timeline.Ctx, b: number, tint: Color3, eyeA: number?)
	ctx:fog(0)
	ctx:bloom(0.7)
	Common.grade(ctx, b, 0.04, -0.05, tint)
	FlashArt.key(ctx, V(1.2, 2.2, 0.6), 2.4, WHITE, 50)
	if (eyeA or 1) > 0 then
		FlashArt.lines(ctx, "fbEye", eyeA or 0.95)
	end
end

-- a whip smear: strongest at the cut, gone `len` seconds away from it
local function smear(ctx: Timeline.Ctx, tCut: number, len: number, a: number?)
	local d = math.abs(ctx.t - tCut)
	if d < len then
		ctx:alpha("fbSmear", (a or 0.85) * (1 - d / len))
	end
end

-- parts of a rig (cached), e.g. Yuta's left arm, hidden while it is stretched
local function rigParts(ctx: Timeline.Ctx, key: string, rig: string, bones: { [string]: boolean }?): { Builder.PartSpec }
	local d = ctx.scene.data
	local list = d[key]
	if list == nil then
		local l: { Builder.PartSpec } = {}
		for _, p in ctx.scene.parts do
			if p.rig == rig and (bones == nil or (p.bone ~= nil and (bones :: { [string]: boolean })[p.bone :: string])) then
				table.insert(l, p)
			end
		end
		d[key] = l
		list = l
	end
	return list
end
local LEFT_ARM = { LeftUpperArm = true, LeftLowerArm = true, LeftHand = true }
local function hideLeftArm(ctx: Timeline.Ctx)
	for _, p in rigParts(ctx, "fbYutaLeftArm", "Yuta", LEFT_ARM) do
		ctx:prop(p, { t = 1 })
	end
end
-- points of a path sampled from 0 to `e` (so a stretching arm grows along it)
local function grow(path: { Vector3 }, e: number, n: number): { Vector3 }
	local out: { Vector3 } = {}
	for i = 0, n - 1 do
		table.insert(out, FlashArt.spline(path, e * i / (n - 1)))
	end
	return out
end

-- roots: facing +X (towards Uro) / -X (towards Yuta), leaning `tilt` degrees
-- forward in the XY plane about the middle of the body (not the feet)
local function faceX(pos: Vector3, tilt: number): CFrame
	return C(pos + V(0, MID, 0)) * CFrame.Angles(0, 0, rad(-tilt)) * C(0, -MID, 0) * CFrame.Angles(0, rad(-90), 0)
end
local function faceNegX(pos: Vector3, tilt: number): CFrame
	return C(pos + V(0, MID, 0)) * CFrame.Angles(0, 0, rad(tilt)) * C(0, -MID, 0) * CFrame.Angles(0, rad(90), 0)
end

------------------------------------------------------------------------------
-- poses
------------------------------------------------------------------------------
local yutaPunch: Rig.Pose = {
	LowerTorso = R(-8, 10, 0),
	UpperTorso = R(-20, -14, 0),
	Head = R(10, 12, 0),
	RightUpperArm = R(92, 0, 10),
	RightLowerArm = R(20, 0, 0),
	LeftUpperLeg = R(96, 0, -12),
	LeftLowerLeg = R(-104, 0, 0),
	LeftFoot = R(-20, 0, 0),
	RightUpperLeg = R(34, 0, 10),
	RightLowerLeg = R(-86, 0, 0),
	RightFoot = R(-30, 0, 0),
}
local yutaHeld: Rig.Pose = {
	UpperTorso = R(-12, 8, 0),
	Head = R(-28, 14, 0),
	RightUpperArm = R(60, 0, 70),
	RightLowerArm = R(100, 0, 0),
	LeftUpperLeg = R(18, 0, -6),
	LeftLowerLeg = R(-28, 0, 0),
	LeftFoot = R(-45, 0, 0),
	RightUpperLeg = R(-4, 0, 6),
	RightLowerLeg = R(-14, 0, 0),
	RightFoot = R(-40, 0, 0),
}
local yutaRecoil: Rig.Pose = {
	LowerTorso = R(10, 0, 0),
	UpperTorso = R(22, 0, 0),
	Head = R(26, -10, 8),
	RightUpperArm = R(60, 0, 40),
	RightLowerArm = R(30, 0, 0),
	LeftUpperArm = R(50, 0, -50),
	LeftLowerArm = R(20, 0, 0),
	LeftUpperLeg = R(30, 0, -10),
	LeftLowerLeg = R(-40, 0, 0),
	RightUpperLeg = R(10, 0, 10),
	RightLowerLeg = R(-60, 0, 0),
}
local yutaFlung: Rig.Pose = {
	LowerTorso = R(8, 0, 0),
	UpperTorso = R(16, 0, 0),
	Head = R(18, 0, 0),
	RightUpperArm = R(30, 0, 110),
	RightLowerArm = R(20, 0, 0),
	LeftUpperArm = R(30, 0, -110),
	LeftLowerArm = R(20, 0, 0),
	LeftUpperLeg = R(30, 0, -18),
	LeftLowerLeg = R(-50, 0, 0),
	RightUpperLeg = R(-10, 0, 16),
	RightLowerLeg = R(-30, 0, 0),
}
local rikaBite: Rig.Pose = {
	HumanoidRootPart = C(0, 0, 0),
	LowerTorso = R(-20, 0, 0),
	UpperTorso = R(-46, 10, 0),
	Head = R(-30, -10, 10),
	RightUpperArm = R(70, 0, 30),
	RightLowerArm = R(60, 0, 0),
	LeftUpperArm = R(80, 0, -20),
	LeftLowerArm = R(70, 0, 0),
}
local rikaSweep: Rig.Pose = {
	LowerTorso = R(-14, 0, 0),
	UpperTorso = R(-26, -10, 0),
	Head = R(-10, 16, 0),
	RightUpperArm = R(14, 0, 96),
	RightLowerArm = R(10, 0, 0),
	RightHand = R(-10, 0, 0),
	LeftUpperArm = R(40, 0, -50),
	LeftLowerArm = R(60, 0, 0),
}

------------------------------------------------------------------------------
-- 31.300 Yuta and Uro grapple in mid-air; his left arm stretches out from
-- him, whips down past the lens and wraps round under them both
------------------------------------------------------------------------------
local function fbAir(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local t = ctx.t
	local close = ss(0.15, 0.9, u)
	local punch = ss(0.2, 0.6, u)
	local yb = ctx:rig("Yuta", faceX(AIR + V(0.2 * close, -0.1, 0), 10 - 6 * u), Cast.mix(Cast.add(yutaPunch, "RightUpperArm", R(-24, 0, 0)), Cast.add(yutaPunch, "RightLowerArm", R(-14, 0, 0)), punch))
	Cast.expr(ctx, "yuta", "shout")
	hideLeftArm(ctx)
	local up = AIR + V(3.7 - 0.7 * close, 0.8 + 0.1 * math.sin(t * 9), -0.3)
	local ub = ctx:rig("Uro", faceNegX(up, 14 - 4 * u), Cast.add(Uro.poses.grapple, "Head", R(-8 * close, 0, 0)))
	Cast.expr(ctx, "uro", "fierce")
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(3.6, 3.4, -0.6), 1.4, 1)
	-- the stretched arm whips round under them from the left, past the lens,
	-- to the right; the part nearer his shoulder leads, the hand trails
	local sh = yb.LeftUpperArm.Position
	local hub = yb.LowerTorso.Position + V(1.0, -0.6, 0)
	local away = V(0, 0.55, -0.83)
	local path = { sh, sh + V(-0.3, -0.9, 0.3) }
	for k = 2, 7 do
		local v = u + (7 - k) * 0.05
		local th = rad(170 + 210 * ss(0, 1, v))
		local rr = 0.9 + (k - 1) * 0.95
		table.insert(path, hub + V(math.cos(th) * rr, 0, 0) + away * (math.sin(th) * rr))
	end
	FlashArt.placeArm(ctx, grow(path, 1, 16), 0.85, 0.7, V(0, 1, 0.4), 0.4 + 0.5 * u)
	-- dark drops flying off round Uro's head
	FX.placeBurst(ctx, hh.blood, ub.Head.Position + V(-0.2, 0.4, 0.3), ctx.lt + 0.1, 3.5, 0.16, 1.4, V(0.6, 0.6, 0.3), 1.2, 0)
	local target = CEN + V(1.7, 0.3, 0)
	cam(ctx, target + V(0, -1.6, 11.2 - 0.8 * u), target, 44, rad(-26 + 24 * ss(0, 1, u)))
	FlashArt.backdrop(ctx, "teal", 80, 0, 0.05 - 0.1 * u, 0.02)
	look(ctx, 0.06, Color3.fromRGB(236, 246, 255))
	ctx:wind(3)
	ctx:gust(0.8)
	smear(ctx, 32.067, 0.07)
end

------------------------------------------------------------------------------
-- 32.067 from above and behind Yuta: Uro clings round his head, her hair
-- spread over the top of the frame, his legs hanging; the camera pushes in
------------------------------------------------------------------------------
local function fbHug(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local t = ctx.t
	local yb = ctx:rig("Yuta", faceX(AIR, -4 + 3 * math.sin(t * 2)), Cast.add(yutaHeld, "Head", R(-4 * math.sin(t * 5), 3 * math.sin(t * 3.3), 0)))
	Cast.expr(ctx, "yuta", "grit")
	ctx:show("yuta:blood")
	hideLeftArm(ctx)
	local head = yb.Head.Position
	local up = head + V(0.85, 0.55, 0.05)
	-- her body stretches away beyond his head (out of sight), her face turned
	-- up over his shoulder towards us, her arms round his head
	local cling = Cast.add(Cast.add(Uro.poses.cling, "Head", R(66, 0, 0)), "UpperTorso", R(18, 0, 0))
	local ub = Common.rigAt(ctx, "Uro", faceNegX(up, 52), cling, "Head", C(0, 0.6, 0), head + V(0.55, 0.8, -1.2))
	Cast.expr(ctx, "uro", "fierce")
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(2.2, 2.6, -1.8), 1.8, 1)
	-- blood soaking his shoulder (the back of the white jacket)
	FlashArt.placeSmears(ctx, yb.UpperTorso, {
		{ -0.5, 1.2, 0.44, 0.62, 0.46, 20 },
		{ -0.62, 0.92, 0.42, 0.5, 0.44, -30 },
		{ -0.34, 1.0, 0.46, 0.46, 0.4, 60 },
		{ -0.7, 1.24, 0.36, 0.36, 0.3, 10 },
		{ -0.46, 0.7, 0.45, 0.3, 0.4, -50 },
		{ -0.24, 1.26, 0.46, 0.3, 0.24, 0 },
	}, Color3.fromRGB(70, 10, 18))
	-- the stretched arm, far off to the left, thin, curling at the end
	local sh = yb.LeftUpperArm.Position
	local wv = math.sin(t * 6) * 0.3
	local path = { sh, sh + V(-0.4, -0.6, -1.2), sh + V(0.3, -1.6 + wv, -2.8), sh + V(1.4, -0.8, -4.0 - wv), sh + V(1.2, 0.5, -4.6), sh + V(0.6, 0.8, -4.2) }
	FlashArt.placeArm(ctx, grow(path, 1, 10), 0.34, 0.24, V(0, 1, 0), 0.85)
	-- camera: above and behind him, looking down his back; pushes in
	local push = ss(0, 1, u)
	local dist = 8.6 - 4.4 * push
	local target = head + V(0.6, -0.6 + 0.4 * push, 0)
	local dir = V(-0.78, 0.6, 0.14).Unit
	local whip = 1 - ss(0, 0.06, u)
	cam(ctx, target + dir * dist, target, 40, rad(4 + 8 * push - 40 * whip))
	FlashArt.backdrop(ctx, "teal", 60, rad(20), -0.12, 0.08)
	look(ctx, 0.06, Color3.fromRGB(236, 246, 255))
	ctx:wind(2.4)
	smear(ctx, 32.067, 0.07)
	smear(ctx, 33.233, 0.07)
end

------------------------------------------------------------------------------
-- 33.233 lavender, light streaks: Uro floats with her knees folded and both
-- palms out; Yuta is thrown away from her to the left, a blur
------------------------------------------------------------------------------
local function fbPush(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local t = ctx.t
	local ub = ctx:rig("Uro", faceNegX(AIR + V(1.7, 0.2 + 0.08 * math.sin(t * 3), 0), 4), Uro.poses.push)
	Cast.expr(ctx, "uro", "fierce")
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(2.4, 3.4, -0.5), 1.4, 1)
	local away = ss(0, 1, u)
	ctx:rig("Yuta", faceX(AIR + V(-1.4 - 2.2 * away, 0.1 - 0.4 * away, 0.4), -14 * away), yutaRecoil)
	Cast.expr(ctx, "yuta", "grit")
	local target = AIR + V(-0.3, MID + 0.5, 0)
	cam(ctx, target + V(0.2, 0.3, 14 - 1.4 * u), target, 38)
	FlashArt.backdrop(ctx, "lav", 70, 0, 0.02 * u, 0)
	look(ctx, 0.05, Color3.fromRGB(238, 240, 255))
	ctx:wind(2.5)
	smear(ctx, 33.233, 0.07)
end

------------------------------------------------------------------------------
-- 33.833 close: Yuta's bloodied face on the left, Uro's palms flat against
-- the air in front of it, bracelets on her wrists
------------------------------------------------------------------------------
local function palmsStage(ctx: Timeline.Ctx): { [string]: CFrame }
	local hh = h(ctx)
	local recoil = Cast.add(Cast.add(Cast.add(yutaRecoil, "Head", R(6, -26, 14)), "RightUpperArm", R(-80, 0, 0)), "LeftUpperArm", R(-70, 0, 0))
	local yb = ctx:rig("Yuta", faceX(AIR, -8), recoil)
	Cast.expr(ctx, "yuta", "grit")
	ctx:show("yuta:blood")
	local face = yb.Head.Position + V(0, 0.5, 0)
	-- her palms flat in front of his face, fingers up; her body off to the right
	local ub = Common.rigAt(ctx, "Uro", faceNegX(AIR + V(3, 0.4, 0), 0), Uro.poses.push, "RightHand", C(0, -0.3, 0), face + V(0.78, -0.4, 0.3))
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(2.4, 3.4, -0.5), 1.4, 1)
	return yb
end

local function palmsCam(ctx: Timeline.Ctx, yb: { [string]: CFrame }, dist: number): CFrame
	local face = yb.Head.Position + V(0, 0.5, 0)
	local target = face + V(0.35, -0.2, 0.15)
	return Util.lookAt(target + V(-0.2, -0.1, dist), target) * CFrame.Angles(0, 0, rad(-3))
end

local function fbPalms(ctx: Timeline.Ctx)
	local yb = palmsStage(ctx)
	local cf = palmsCam(ctx, yb, 6.4 - 0.3 * ctx.u)
	ctx:camera(cf, 20)
	ctx:focus(6.3, 0.25)
	FlashArt.backdrop(ctx, "lav", 50, 0, 0, 0)
	look(ctx, 0.08, Color3.fromRGB(240, 240, 255))
	ctx:wind(2.5)
end

-- 34.000 the same moment goes dark and grey, cracks run across the picture
local function fbDark(ctx: Timeline.Ctx)
	local u = ctx.u
	local yb = palmsStage(ctx)
	local cf = palmsCam(ctx, yb, 6.0)
	ctx:camera(Clash.shake(cf, ctx.t, 0.03, 14), 20)
	ctx:focus(6, 0.25)
	FlashArt.backdrop(ctx, "lav", 50, 0, 0, 0)
	ctx:fog(0)
	FlashArt.key(ctx, V(1.2, 2.2, 0.6), 2, WHITE, 50)
	Common.grade(ctx, -0.3 - 0.25 * u, 0.55, -1, Color3.fromRGB(226, 226, 236))
	FlashArt.lines(ctx, "fbEye", 1)
	ctx:show("fbCrackA1")
	if u > 0.3 then
		ctx:show("fbCrackA2")
	end
	if u > 0.55 then
		ctx:show("fbCrackA3")
	end
	ctx:flash(Color3.new(0, 0, 0), 0.6 * ss(0.45, 1, u))
end

------------------------------------------------------------------------------
-- 34.333 the evening sky shatters round Yuta, high up in the frame: cracks
-- run out from him, shards fly, a flash; 34.767 a white ring round him;
-- 34.867 something dark rushes past the lens
------------------------------------------------------------------------------
local function fbSky(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local f = fl(ctx)
	local t = ctx.t
	local u = ctx.u
	local pos = AIR + V(0.6, 1.4 * u, 0)
	local close = t >= 34.8 and t < 34.867
	local gone = t >= 34.933
	-- facing the camera (+Z), thrown back, arms flung wide
	local root = C(pos + V(0, MID, 0)) * CFrame.Angles(rad(-14), math.pi, rad(8 - 6 * u)) * C(0, -MID, 0)
	local chest = pos + V(0, MID + 0.6, 0)
	if not gone then
		local yb = ctx:rig("Yuta", root, yutaFlung)
		Cast.expr(ctx, "yuta", "shout")
		ctx:show("yuta:blood")
		if close then
			-- a gash of blood across his chest
			FlashArt.placeSmears(ctx, yb.UpperTorso, {
				{ -0.75, 0.62, -0.44, 0.6, 0.22, -24 },
				{ -0.35, 0.42, -0.46, 0.7, 0.28, -24 },
				{ 0.05, 0.24, -0.44, 0.56, 0.2, -24 },
				{ -0.9, 0.8, -0.4, 0.3, 0.14, -24 },
				{ -0.2, 0.2, -0.46, 0.2, 0.3, 70 },
				{ 0.42, 1.25, -0.42, 0.34, 0.2, 10 },
			}, Color3.fromRGB(150, 24, 34))
		end
	end
	if not close then
		FX.placeBurst(ctx, f.shards, chest, t - 34.36, 7, 0.35, 1.4, nil, 1, 0)
		local spark = 1 - ss(34.36, 34.5, t)
		if spark > 0 then
			FX.placeCore(ctx, hh.blastCore, chest + V(-0.8, 0.2, 0.4), 1.2, spark)
		end
		if t > 34.733 then
			local a = t - 34.733
			FlashArt.placeHalo(ctx, chest, V(0, 0, 1), 2.2 + a * 5, 0.32, math.max(0, 1 - a * 1.6))
		end
	end
	if close then
		cam(ctx, chest + V(0.4, -0.8, 5.2), chest + V(-0.2, -0.7, 0), 46, rad(-14))
	else
		local target = pos + V(1.5, MID - 8.5, 0)
		cam(ctx, target + V(0, -2, 26), target, 50)
	end
	FlashArt.backdrop(ctx, "clouds", 120, 0, 0, 0.02 * u)
	look(ctx, 0.06, Color3.fromRGB(238, 238, 255))
	if not close then
		ctx:show("fbCrackB1")
		if t > 34.43 then
			ctx:show("fbCrackB2")
		end
		if t > 34.55 then
			ctx:show("fbCrackB3")
		end
	end
	if t >= 34.867 and t < 34.933 then
		ctx:alpha("fbSmearDark", 1)
	end
	ctx:wind(2)
end

------------------------------------------------------------------------------
-- 35.033 a dark roof at night: a huge burst of dust explodes from the right
-- (Rika lands); Uro, crouched in the air, is knocked head over heels to the
-- left and swallowed by it
------------------------------------------------------------------------------
local function fbDust(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local t = ctx.t
	local u = ctx.u
	local flip = ss(0.15, 0.85, u)
	local pos = O + V(-2.2 - 4.5 * flip, -5.5 + 1.4 * math.sin(flip * math.pi), 0)
	local ub = ctx:rig("Uro", C(pos + V(0, MID, 0)) * CFrame.Angles(0, 0, rad(200 * flip)) * C(0, -MID, 0) * CFrame.Angles(0, rad(90), 0), Cast.mix(Uro.poses.crouch, Uro.poses.flung, flip))
	Cast.expr(ctx, "uro", "pain")
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(2.8, 1.4, 0) * (1 - flip) + V(1.6, -2.8, 0) * flip, 1.2, 1)
	-- the burst of dust rolls in from the right and swallows her
	local age = t - 34.95
	FX.placeBurst(ctx, hh.debris, O + V(6, -8, 1), age, 14, 0.3, 1.4, V(-1, 0.4, 0.3), 0.9, 2)
	local target = O + V(-0.5, -5.2 + MID, 0)
	cam(ctx, target + V(1.0, -1.2, 11), target, 46, rad(-8))
	FlashArt.backdrop(ctx, "night", 150, 0, 0, 0)
	FlashArt.backdrop(ctx, "dust", 9.5, rad(-4), 0.42 - 0.5 * ss(0, 0.85, u), 0.02 * u)
	ctx:fog(0)
	ctx:bloom(0.6)
	Common.grade(ctx, 0.06, 0.12, -0.3, Color3.fromRGB(226, 222, 236))
	FlashArt.key(ctx, V(4, 2, -3), 3.4, Color3.fromRGB(240, 240, 250), 45)
	FlashArt.rim(ctx, O + V(4, -3, 4), 2.5, Color3.fromRGB(236, 232, 240), 40)
	FlashArt.lines(ctx, "fbEye", 0.9)
	ctx:wind(3)
	ctx:gust(1)
	smear(ctx, 35.633, 0.12, 0.6)
end

------------------------------------------------------------------------------
-- 35.633 low on the roof looking up: the evening sky, an apartment block,
-- the elevated road; Uro falling high on the left; Rika's huge hand flies up
-- from the bottom left, fingers spread, and closes on her arm; she dangles
------------------------------------------------------------------------------
local CAM8 = O + V(0, -9, 12)
local LOOK8 = O + V(0.5, 3.2, -8)
local uroHeld: Rig.Pose = {
	LowerTorso = R(-10, 0, 0),
	UpperTorso = R(-14, 0, -10),
	Head = R(-20, 0, 12),
	LeftUpperArm = R(-24, 0, -42),
	LeftLowerArm = R(6, 0, 0),
	RightUpperArm = R(70, 0, 60),
	RightLowerArm = R(50, 0, 0),
	LeftUpperLeg = R(50, 0, -10),
	LeftLowerLeg = R(-70, 0, 0),
	RightUpperLeg = R(-30, 0, 12),
	RightLowerLeg = R(-60, 0, 0),
}

local function fbCatch(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local t = ctx.t
	local reach = ss(35.86, 36.12, t)
	local shut = ss(36.12, 36.28, t)
	local caught = ss(36.24, 36.4, t)
	-- Uro, falling high on the left, far from the lens; caught by her left
	-- wrist she is yanked down, kicking, above the fist
	local fall = O + V(-5.2 + 0.6 * caught, 4.8 - 1.1 * ss(35.633, 36.25, t) - 0.5 * caught, -8)
	local jerk = math.sin(math.clamp((t - 36.28) * 16, 0, math.pi)) * 12
	local root = C(fall + V(0, MID, 0)) * CFrame.Angles(0, rad(70), rad(10 + jerk)) * C(0, -MID, 0)
	local ub = ctx:rig("Uro", root, Cast.mix(Uro.poses.crouch, uroHeld, caught))
	Cast.expr(ctx, "uro", if caught > 0.5 then "pain" else "fierce")
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(1.2, 3.4, 0.8), 1.4, 1)
	-- Rika's hand, huge and close to the lens, flies up from the lower left,
	-- fingers spread, and closes where it covers Uro's wrist in the picture
	local camCF = Util.lookAt(CAM8, LOOK8)
	local up, right, fwd = camCF.UpVector, camCF.RightVector, camCF.LookVector
	local fingers = (up * 0.85 + right * 0.3 + fwd * 0.15).Unit
	local palmN = (-fwd - fingers * (-fwd):Dot(fingers)).Unit
	local sc = 2.4
	-- the fist closes just under her feet in the picture, her body above it
	local grip = fall + V(0.3, -1.6, 0)
	local onRay = CAM8 + (grip - CAM8).Unit * 8.5
	local stop = onRay - fingers * (0.85 * sc)
	local start = stop - right * 5 - up * 7 + fwd * 1
	local jolt = math.sin(math.clamp((t - 36.28) * 22, 0, math.pi)) * 0.25
	local wristPos = start:Lerp(stop, reach) - up * jolt
	local wrist = CFrame.fromMatrix(wristPos, fingers:Cross(palmN).Unit, -fingers, palmN)
	if t > 35.86 then
		FlashArt.placeClaw(ctx, wrist, sc, 1 - shut)
	end
	cam(ctx, CAM8, LOOK8, 40 - 7 * ss(36.3, 36.667, t), rad(-8))
	FlashArt.backdrop(ctx, "dusk", 220, 0, 0, 0)
	look(ctx, 0.04, Color3.fromRGB(238, 236, 255))
	ctx:wind(2.5)
	smear(ctx, 35.633, 0.12, 0.6)
	smear(ctx, 36.18, 0.05, 0.5)
end

------------------------------------------------------------------------------
-- 36.667 Rika looms over Uro and sinks her teeth into her shoulder; Uro's
-- head is thrown back, eyes screwed shut
------------------------------------------------------------------------------
local function fbBite(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local up = O + V(-4, 4, -6)
	-- Uro faces the lens, thrown back over Rika's arm, head lolling back
	local ub = ctx:rig("Uro", C(up + V(0, MID, 0)) * CFrame.Angles(rad(-20), rad(200), rad(-24)) * C(0, -MID, 0), Uro.poses.pain)
	Cast.expr(ctx, "uro", "pain")
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(2.8, -1.4, -1.4), 1.5, 1)
	-- Rika behind her, hunched over, teeth in her left shoulder
	local shoulder = ub.LeftUpperArm.Position
	Common.rigAt(ctx, "Rika", C(up + V(-1, -6, -5)) * CFrame.Angles(0, math.pi + rad(20), 0), Cast.add(rikaBite, "Head", R(-6 * u, 0, 0)), "Head", C(0, 0.8, -1.4), shoulder + V(-0.1, 0.4, -0.5))
	local chest = ub.UpperTorso.Position
	local target = chest + V(-0.8, 1.4, -0.4)
	cam(ctx, chest + V(3.2, -3.4, 7.8), target, 48, rad(-14))
	FlashArt.backdrop(ctx, "dusk", 220, 0, 0, 0)
	look(ctx, 0.04, Color3.fromRGB(238, 236, 255))
	ctx:wind(2)
end

------------------------------------------------------------------------------
-- 36.867 from below: Rika's huge arm across the frame, claws spread at the
-- top left, her torso above it; she rips
------------------------------------------------------------------------------
local function sweepStage(ctx: Timeline.Ctx, k: number): { [string]: CFrame }
	local root = C(O + V(0, -2, -8)) * CFrame.Angles(0, math.pi + rad(14), 0)
	local pose = Cast.add(Cast.add(rikaSweep, "RightUpperArm", R(36 * (1 - k), 0, 0)), "UpperTorso", R(0, 18 * k, 0))
	return ctx:rig("Rika", root, pose)
end

local function fbSweep(ctx: Timeline.Ctx)
	local u = ctx.u
	local rb = sweepStage(ctx, ss(0, 1, u))
	Common.rikaEye(ctx, rb, 0.8)
	local sh = rb.RightUpperArm.Position
	cam(ctx, sh + V(-2.5, -6, 6.2), sh + V(-3.8, 0.8, 0), 52, rad(-8))
	FlashArt.backdrop(ctx, "dusk", 220, 0, 0, 0)
	look(ctx, 0.04, Color3.fromRGB(238, 236, 255))
	ctx:wind(2)
end

-- 37.133 one frame of glitch, then the arm comes away: blood sprays to the
-- left in long streaks, a small dark figure drops
local function fbTear(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local t = ctx.t
	local rb = sweepStage(ctx, 1.15)
	Common.rikaEye(ctx, rb, 0.8)
	local sh = rb.RightUpperArm.Position
	cam(ctx, sh + V(-2.3, -6, 6.5), sh + V(-4, 0.8, 0), 52, rad(-5))
	FlashArt.backdrop(ctx, "dusk", 220, 0, 0, 0)
	look(ctx, 0.04, Color3.fromRGB(238, 236, 255))
	if t < 37.167 then
		ctx:alpha("fbGlitch", 1)
		return
	end
	local hand = (rb.RightHand * C(0, -1.4, 0)).Position
	local age = t - 37.167
	FX.placeBurst(ctx, hh.blood, hand, age + 0.05, 18, 0.55, 0.8, V(-1, 0.15, 0.3), 0.35, 4)
	local tip = hand + V(-7 - 30 * age, 1.0, 2.5)
	FlashArt.placeTrail(ctx, { hand, hand:Lerp(tip, 0.4) + V(0, 0.9, 0.6), tip }, 0.9, Color3.fromRGB(226, 96, 122))
	ctx:alpha("fbGlitch", 0.35)
	local ub = ctx:rig("Uro", C(hand + V(-3.5, -5.5 - 12 * age, 3)) * CFrame.Angles(rad(40), rad(90), rad(30)), Uro.poses.flung)
	Uro.placeHair(ctx, hh.uroHair, ub.Head, V(0, 3, 0), 1, 0.8)
	ctx:wind(2)
end

-- 37.333 Ryu's near eye, wide with shock (painted close-up panel), out of a
-- quick flash
local function ryuEye(ctx: Timeline.Ctx)
	Common.panelCamera(ctx, 330 + ctx.u * 6, 488, 205 - ctx.u * 14)
	CloseupSet.hair(ctx)
	ctx:show("split:ryuShock")
	local fade = 1 - ss(37.333, 37.5, ctx.t)
	ctx:flash(Color3.fromRGB(200, 236, 255), 0.55 * fade)
	Common.grade(ctx, -0.03, 0.32, -0.6, Color3.fromRGB(166, 226, 234))
end

------------------------------------------------------------------------------
-- 42.900 night-blue sky, close arcs of the eye: Uro's severed arm turning
-- over slowly, thin streaks of blood trailing from the torn end
------------------------------------------------------------------------------
local ARMS = O + V(0, 260, 0)

local function fbArm(ctx: Timeline.Ctx)
	local u = ctx.u
	local t = ctx.t
	local turn = rad(-30 - 40 * ss(0, 1, u))
	local sh = C(ARMS) * CFrame.Angles(0, 0, turn) * CFrame.Angles(rad(8), rad(-14), 0)
	FlashArt.placeSevered(ctx, sh, -30 + 8 * math.sin(t * 4))
	local stump = sh.Position
	local back = stump + V(1.8, 1.4, -0.6)
	FlashArt.placeTrail(ctx, { stump, stump:Lerp(back, 0.5) + V(0.3, -0.2, 0), back + V(1.6, 0.5, -0.3) }, 0.05, Color3.fromRGB(120, 18, 28))
	local mid = (sh * C(0, -1.1, 0)).Position
	local whip = 1 - ss(0, 0.08, u)
	cam(ctx, mid + V(0.3, 0.2, 2.9 - 0.3 * u), mid + V(0.1, 0.1, 0), 46, rad(4 - 40 * whip))
	FlashArt.backdrop(ctx, "navy", 60, 0, 0, 0.02 * u)
	ctx:fog(0)
	ctx:bloom(0.6)
	Common.grade(ctx, 0.02, 0.06, -0.05, Color3.fromRGB(226, 236, 255))
	FlashArt.key(ctx, V(1.5, 2, 1), 2.2, WHITE, 30)
	FlashArt.lines(ctx, "fbArcs", 0.9)
	smear(ctx, 42.9, 0.06, 0.5)
end

------------------------------------------------------------------------------
-- 43.567 close on Rika's face, tilted: blood smeared round her teeth, Uro's
-- arm in her jaws with the hand sticking out to the left, her white mane
-- streaming right; 44.0 a whip; 44.2 it holds
------------------------------------------------------------------------------
local function rikaEat(ctx: Timeline.Ctx, roll: number, chew: number)
	local hh = h(ctx)
	local root = C(ARMS + V(0, -12, 0)) * CFrame.Angles(0, rad(-70), 0)
	local rb = ctx:rig("Rika", root, Cast.add(Cast.add(Cast.rika.roar, "Head", R(8 + chew * 3, 28, 0)), "UpperTorso", R(-6, 0, 0)))
	local head = rb.Head
	-- the arm in her jaws: the torn shoulder inside, the hand out to her left
	local mouth = head * C(0, 0.7, -1.7)
	FlashArt.placeSevered(ctx, mouth * C(-0.9, -0.05, 0.35) * CFrame.Angles(0, 0, rad(84)) * CFrame.Angles(rad(10), 0, 0), -10)
	FlashArt.placeSmears(ctx, head, {
		{ -0.4, 0.3, -1.75, 0.17, 0.5, 10 },
		{ 0.3, 0.2, -1.82, 0.14, 0.56, -8 },
		{ 0.65, -0.1, -1.55, 0.18, 0.42, 20 },
		{ -0.1, -0.3, -1.7, 0.35, 0.15, 0 },
		{ -0.75, 0, -1.45, 0.14, 0.35, -20 },
		{ 0.1, 0.6, -1.85, 0.42, 0.14, 4 },
		{ 0.45, 0.55, -1.75, 0.13, 0.28, 30 },
		{ -0.5, 0.65, -1.7, 0.11, 0.25, -30 },
	}, Color3.fromRGB(150, 20, 32))
	FX.placeBurst(ctx, hh.blood, (head * C(0.4, -0.2, -1.6)).Position, ctx.t % 0.7, 3, 0.18, 0.7, V(0.3, -1, 0), 0.4, 9)
	local c = (head * C(-0.55, 0.55, -1.2)).Position
	local camPos = (head * C(0.5, 0.35, -4.6)).Position
	cam(ctx, camPos, c, 50, roll)
	FlashArt.backdrop(ctx, "navy", 60, 0, 0, 0)
	ctx:fog(0)
	ctx:bloom(0.6)
	Common.grade(ctx, 0.02, 0.1, -0.1, Color3.fromRGB(230, 232, 248))
	FlashArt.key(ctx, V(1.5, 2, 1), 2.4, WHITE, 30)
	FlashArt.lines(ctx, "fbArcs", 0.9)
	ctx:wind(2.2)
end

local function fbRika(ctx: Timeline.Ctx)
	local t = ctx.t
	rikaEat(ctx, rad(40 - 22 * ss(43.567, 44.0, t)), math.sin(t * 14))
	smear(ctx, 44.1, 0.1, 0.7)
end

local function fbRikaHold(ctx: Timeline.Ctx)
	rikaEat(ctx, rad(18), 0)
end

local function tibEye(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("tibEye2")
	ctx:flash(WHITE, 0.9 * (1 - ss(0, 0.1, ctx.u)))
end

Flashback.shots = {
	{ id = "P2 19 fb air", t0 = 31.3, t1 = 32.067, run = fbAir },
	{ id = "P2 19b fb hug", t0 = 32.067, t1 = 33.233, run = fbHug },
	{ id = "P2 20 fb push", t0 = 33.233, t1 = 33.833, run = fbPush },
	{ id = "P2 21 fb palms", t0 = 33.833, t1 = 34.0, run = fbPalms },
	{ id = "P2 22 fb dark", t0 = 34.0, t1 = 34.333, run = fbDark },
	{ id = "P2 23 fb sky", t0 = 34.333, t1 = 35.033, run = fbSky },
	{ id = "P2 24 fb dust", t0 = 35.033, t1 = 35.633, run = fbDust },
	{ id = "P2 25 fb catch", t0 = 35.633, t1 = 36.667, run = fbCatch },
	{ id = "P2 25b fb bite", t0 = 36.667, t1 = 36.867, run = fbBite },
	{ id = "P2 25c fb sweep", t0 = 36.867, t1 = 37.133, run = fbSweep },
	{ id = "P2 25d fb tear", t0 = 37.133, t1 = 37.333, run = fbTear },
	{ id = "P2 26 ryu eye", t0 = 37.333, t1 = 38.7, run = ryuEye },
	{ id = "P2 31 fb arm", t0 = 42.9, t1 = 43.567, run = fbArm },
	{ id = "P2 32 fb rika", t0 = 43.567, t1 = 44.2, run = fbRika },
	{ id = "P2 32b fb rika hold", t0 = 44.2, t1 = 44.7, run = fbRikaHold },
	{ id = "P2 33 thin ice", t0 = 44.7, t1 = 45.8, run = tibEye },
} :: { Timeline.Shot }

return Flashback
