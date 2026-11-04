--!strict
-- Part 2 flashbacks (Ryu remembering Yuta's fight with Uro on the rooftops),
-- tinted purple / blue and drawn over with white line art:
--  31.300 wide: the rooftops, a huge line-art eye, Yuta vs Uro
--  33.833 Yuta, bloodied (b/w)          34.000 the eye in the dark
--  34.333 Uro leaps over Yuta           35.033 Uro through the dust (dark)
--  35.633 Yuta's hand reaching up at her
--  36.667 Rika snatches Uro             37.333 Ryu's eye wide (painted close-up)
--  42.900 Yuta's arm (blue line art)    43.600 Rika's bloody mouth
--  44.700 "Thin Ice Breaker!"
local Timeline = require(script.Parent.Parent.Parent.Timeline)
local CloseupSet = require(script.Parent.Parent.Parent.Art.Sets.CloseupSet)
local FX = require(script.Parent.Parent.Parent.FX)
local Util = require(script.Parent.Parent.Parent.Util)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Cast = require(script.Parent.Parent.Cast)
local Clash = require(script.Parent.Parent.Clash)
local Common = require(script.Parent.Common)
local Uro = require(script.Parent.Parent.Parent.Art.Characters.Uro)

local Flashback = {}

local V = Vector3.new
local C = CFrame.new
local R = Rig.R

local O = Common.FB
local WHITE = Color3.new(1, 1, 1)

local function h(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end

local function purple(ctx: Timeline.Ctx, bright: number?)
	Common.grade(ctx, bright or 0, 0.18, -0.65, Color3.fromRGB(205, 190, 255))
	ctx:fog(0.25)
end

local function mono(ctx: Timeline.Ctx, bright: number?)
	Common.grade(ctx, bright or 0, 0.35, -1, Color3.fromRGB(235, 235, 245))
	ctx:fog(0.25)
end

-- Yuta on the roof facing +X, Uro attacking from the +X side
local function yutaRoot(): CFrame
	return C(O + V(-3, 0, 0)) * CFrame.Angles(0, math.rad(-90), 0)
end

local blockPose: Rig.Pose = {
	UpperTorso = R(6, 10, 0),
	Head = R(-10, -6, 0),
	RightUpperArm = R(70, 0, 20),
	RightLowerArm = R(90, 0, 0),
	LeftUpperArm = R(40, 0, -20),
	LeftLowerArm = R(60, 0, 0),
	LeftUpperLeg = R(20, 0, -8),
	LeftLowerLeg = R(-30, 0, 0),
	RightUpperLeg = R(-14, 0, 8),
}

local reachUp: Rig.Pose = {
	UpperTorso = R(-14, 0, 0),
	Head = R(-30, 0, 0),
	RightUpperArm = R(160, 0, -6),
	RightLowerArm = R(6, 0, 0),
	RightHand = R(-20, 0, 0),
	LeftUpperArm = R(10, 0, -30),
	LeftLowerArm = R(40, 0, 0),
}

local function fbWide(ctx: Timeline.Ctx)
	-- Yuta flies at Uro and kicks her in the stomach; she doubles over
	local u = ctx.u
	local hit = Util.smoothstep(0.45, 0.6, u)
	local yp = O + V(-7 + u * 8, 2.6 + math.sin(math.min(1, u * 1.4) * math.pi) * 2.5, 0)
	ctx:rig("Yuta", C(yp) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(math.rad(-20), 0, 0), Uro.poses.kick)
	Cast.expr(ctx, "yuta", "glare")
	local doubled: Rig.Pose = {
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(40, 0, 0),
		Head = R(20, 0, 0),
		LeftUpperArm = R(60, 0, -10),
		LeftLowerArm = R(40, 0, 0),
		RightUpperArm = R(60, 0, 10),
		RightLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(30, 0, 0),
		LeftLowerLeg = R(-40, 0, 0),
		RightUpperLeg = R(10, 0, 0),
	}
	local up = O + V(4 + hit * 2.5, hit * 1.5, 0)
	ctx:rig("Uro", C(up) * CFrame.Angles(0, math.rad(90), 0), Cast.mix(Uro.poses.leap, doubled, hit))
	ctx:camera(Util.lookAt(O + V(1, 16, 40), O + V(1, 3, 0)), 40)
	ctx:focus(40, 0)
	ctx:alpha("fbLines", 0.95)
	purple(ctx)
end

local function fbYuta(ctx: Timeline.Ctx)
	-- a claw tears Uro's left arm off: blood flies past Yuta (black and white)
	local hh = h(ctx)
	local yb = ctx:rig("Yuta", yutaRoot(), blockPose)
	Cast.expr(ctx, "yuta", "glare")
	local chest = yb.UpperTorso * C(0, 0.9, 0)
	ctx:camera(Util.lookAt(chest:PointToWorldSpace(V(1.4, 0.4, -2.6)), chest.Position), 50)
	ctx:focus(3, 1)
	FX.placeBurst(ctx, hh.blood, chest:PointToWorldSpace(V(1.2, 0.6, -0.8)), ctx.lt + 0.05, 10, 0.2, 0.5, V(-0.6, 0.4, -1), 0.8, 10)
	ctx:alpha("fbLines", 0.4)
	mono(ctx, 0.1)
end

local function fbDark(ctx: Timeline.Ctx)
	ctx:rig("Yuta", yutaRoot(), blockPose)
	ctx:rig("Uro", C(O + V(4, 3, 0)) * CFrame.Angles(0, math.rad(90), 0), Uro.poses.kick)
	ctx:camera(Util.lookAt(O + V(0, 6, 18), O + V(1, 3, 0)), 50)
	ctx:focus(18, 0)
	ctx:alpha("fbLines", 1)
	mono(ctx, -0.5)
end

local function fbLeap(ctx: Timeline.Ctx)
	local u = ctx.u
	ctx:rig("Yuta", yutaRoot(), Cast.mix(blockPose, reachUp, u))
	Cast.expr(ctx, "yuta", "glare")
	local p = O + V(6 - u * 9, 6 + math.sin(u * math.pi) * 6, 0)
	ctx:rig("Uro", C(p) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(u * 120), 0, 0), Uro.poses.leap)
	ctx:camera(Util.lookAt(O + V(-2, 1.5, 22), O + V(0, 6, 0)), 50)
	ctx:focus(22, 0)
	ctx:alpha("fbLines", 0.9)
	purple(ctx)
end

local function fbDust(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local u = ctx.u
	local p = O + V(4 - u * 6, 4 + u * 3, 2)
	ctx:rig("Uro", C(p) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-30), 0, 0), Uro.poses.leap)
	FX.placeBurst(ctx, hh.dust, O + V(2, 1, 2), ctx.lt + 0.2, 12, 2.6, 1.4, V(0, 0.6, 0.4), 1, 2)
	ctx:camera(Util.lookAt(O + V(-4, 3, 16), O + V(1, 4, 1)), 55)
	ctx:focus(16, 0)
	ctx:alpha("fbLines", 0.8)
	mono(ctx, -0.35)
end

local function fbHand(ctx: Timeline.Ctx)
	-- Uro falls; in the foreground Rika's huge white hand closes into a fist
	local u = ctx.u
	local rr = C(O + V(-4, -2, 6)) * CFrame.Angles(0, math.rad(-150), 0)
	local rb = ctx:rig("Rika", rr, Cast.add(Cast.add(Cast.rika.roar, "RightUpperArm", R(80, 0, 10)), "RightHand", R(-40 + u * 90, 0, 0)))
	local hand = (rb.RightHand * C(0, -1.4, 0)).Position
	local p = O + V(1 - u * 2, 13 - u * 4, -2)
	ctx:rig("Uro", C(p) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-160 + u * 50), 0, 0), Uro.poses.caught)
	local eye = hand + V(1.2, -2.2, 3.2)
	ctx:camera(Util.lookAt(eye, p:Lerp(hand, 0.3)), 62)
	ctx:focus((hand - eye).Magnitude, 0.6)
	ctx:alpha("fbLines", 0.75)
	purple(ctx, -0.05)
end

local function fbGrab(ctx: Timeline.Ctx)
	local u = ctx.u
	local rb = ctx:rig("Rika", C(O + V(-6, 2, -3)) * CFrame.Angles(0, math.rad(-60), 0), Cast.add(Cast.rika.roar, "RightUpperArm", R(40 + u * 40, 0, 30)))
	local grip = (rb.RightHand * C(0, -1.2, 0)).Position
	ctx:rig("Uro", C(grip + V(0, -1.4, 0)) * CFrame.Angles(0, math.rad(90), math.rad(20)), Uro.poses.caught)
	ctx:camera(Util.lookAt(O + V(4, 5, 14), grip + V(-2, 0, 0)), 55)
	ctx:focus(14, 0)
	ctx:alpha("fbLines", 0.85)
	ctx:flash(WHITE, 0.3 * (1 - u))
	mono(ctx, 0)
end

-- Ryu's near eye, wide with shock (painted close-up panel)
local function ryuEye(ctx: Timeline.Ctx)
	Common.panelCamera(ctx, 330 + ctx.u * 6, 488, 205 - ctx.u * 14)
	CloseupSet.hair(ctx)
	ctx:show("split:ryuShock")
	ctx:flash(Color3.fromRGB(150, 225, 255), 0.18)
	Common.grade(ctx, 0.04, 0.22, 0, Color3.fromRGB(215, 240, 255))
end

local function fbArm(ctx: Timeline.Ctx)
	-- Uro's severed arm tumbling through the air, blood trailing (blue line art)
	local hh = h(ctx)
	local arm = hh.uroArm
	local u = ctx.u
	local base = C(O + V(-2 + u * 2.5, 6 + u * 1.2, 0)) * CFrame.Angles(0, 0, math.rad(70 + u * 70)) * CFrame.Angles(math.rad(12), math.rad(20), 0)
	ctx:place(arm.upper, base * C(0, -0.5, 0))
	ctx:place(arm.lower, base * C(0, -1.45, 0) * CFrame.Angles(math.rad(-15), 0, 0))
	ctx:place(arm.band, base * C(0, -1.88, -0.05))
	ctx:place(arm.hand, base * C(0, -2.18, -0.08) * CFrame.Angles(math.rad(-10), 0, 0))
	FX.placeBurst(ctx, hh.blood, base.Position, ctx.lt % 0.6, 6, 0.16, 0.6, V(-1, 0.2, 0), 0.6, 4)
	local mid = (base * C(0, -1.2, 0)).Position
	ctx:camera(Util.lookAt(mid + V(0.5, 0.8, 3.1), mid), 50)
	ctx:focus(3.2, 1)
	ctx:alpha("fbLines", 0.45)
	Common.grade(ctx, -0.05, 0.25, -0.5, Color3.fromRGB(170, 195, 255))
	ctx:fog(0.25)
end

-- Rika with blood round her jaws: she has just eaten Uro's arm
local function fbRika(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local rb = ctx:rig("Rika", C(O + V(-2, 0, -2)) * CFrame.Angles(0, math.rad(-30), 0), Cast.alive(Cast.add(Cast.rika.roar, "Head", R(10, 0, -8)), ctx.t))
	local head = rb.Head
	local spots = { V(-0.4, 0.3, -1.6), V(0.3, 0.2, -1.7), V(0.6, -0.1, -1.4), V(-0.1, -0.3, -1.5), V(-0.7, 0, -1.3), V(0.1, 0.55, -1.75), V(0.45, 0.5, -1.6) }
	for i, p in hh.rikaBlood do
		local o = spots[i]
		ctx:place(p, head * C(o))
		local sz = 0.22 + (i % 3) * 0.08
		ctx:prop(p, { s = V(sz, sz * 1.6, sz * 0.6) })
	end
	local cam = head:PointToWorldSpace(V(1.6, 0.6, -4.2 + ctx.u * 0.4))
	ctx:camera(Clash.shake(Util.lookAt(cam, head.Position + V(0, 0.3, 0)), ctx.t, 0.06, 8), 50)
	ctx:focus((head.Position - cam).Magnitude, 1)
	ctx:alpha("fbLines", 0.5)
	Common.grade(ctx, -0.02, 0.25, -0.7, Color3.fromRGB(215, 218, 240))
	ctx:fog(0.25)
end

local function tibEye(ctx: Timeline.Ctx)
	Clash.void(ctx, Color3.new(0, 0, 0))
	ctx:camera(C(Clash.O), 60)
	ctx:show("tibEye")
	ctx:flash(WHITE, 0.9 * (1 - Util.smoothstep(0, 0.1, ctx.u)))
end

Flashback.shots = {
	{ id = "P2 19 fb wide", t0 = 31.3, t1 = 33.833, run = fbWide },
	{ id = "P2 20 fb yuta", t0 = 33.833, t1 = 34.0, run = fbYuta },
	{ id = "P2 21 fb dark", t0 = 34.0, t1 = 34.333, run = fbDark },
	{ id = "P2 22 fb leap", t0 = 34.333, t1 = 35.033, run = fbLeap },
	{ id = "P2 23 fb dust", t0 = 35.033, t1 = 35.633, run = fbDust },
	{ id = "P2 24 fb hand", t0 = 35.633, t1 = 36.667, run = fbHand },
	{ id = "P2 25 fb grab", t0 = 36.667, t1 = 37.333, run = fbGrab },
	{ id = "P2 26 ryu eye", t0 = 37.333, t1 = 38.7, run = ryuEye },
	{ id = "P2 31 fb arm", t0 = 42.9, t1 = 43.6, run = fbArm },
	{ id = "P2 32 fb rika", t0 = 43.6, t1 = 44.7, run = fbRika },
	{ id = "P2 33 thin ice", t0 = 44.7, t1 = 45.8, run = tibEye },
} :: { Timeline.Shot }

return Flashback
