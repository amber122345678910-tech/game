--!strict
-- Part 2: Ryu watches his blast bend away and works out Yuta's technique.
--  20.300 Ryu from behind, the blast bending up into the sky
--  23.000 Ryu's head in profile, cyan light, wind
--  27.667 Yuta from behind and below, hand raised to the sky
--  38.700 cyan slashes of folded space     39.433 the blast flies off (comet)
--  40.700 Ryu's face, red-orange light from above
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
local ORANGE = Color3.fromRGB(255, 120, 60)

local function h(ctx: Timeline.Ctx): Common.H
	return ctx.scene.data.p2
end

-- the bent blast spreading up into the sky above Yuta (seen from afar)
local function skyBands(ctx: Timeline.Ctx, lt: number, k: number)
	local hh = h(ctx)
	local bend = Common.YUTA + V(0, 4.2, 5.2)
	for i, b in hh.bands do
		local off = V((i - 3) * 2.4, (i - 3) * 0.8, 0)
		local p0 = bend + off
		local p1 = bend + V(0, 6, 12) + off * 2
		local p2 = bend + V((i - 3) * 9, 70, 30)
		local function pt(f: number): Vector3
			local w = 1 - f
			return p0 * (w * w) + p1 * (2 * w * f) + p2 * (f * f)
		end
		local head = math.clamp(0.6 + lt * 0.12, 0, 1)
		FX.placeCurvedBeam(ctx, b, pt, math.clamp(head - 0.7, 0, 1), head, if i % 2 == 0 then 1.3 else 2.6, 0.8 * k)
	end
	FX.placeCore(ctx, hh.blastCore, bend, 1.8, k)
	FX.placeCore(ctx, hh.blastHalo, bend, 3.8, 0.25 * k)
end

local function ryuBack(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(-10, -26, 0)), ctx.t))
	Cast.expr(ctx, "ryu", "shock")
	ctx:rig("Yuta", Common.yutaRoot(), Cast.alive(Blast.reachPose(1), ctx.t))
	skyBands(ctx, ctx.lt + 3, 1)
	FX.placeRays(ctx, hh.rays, Common.YUTA + V(0, 9, 6), C(), 16, 0.25, 0.55, 10, V(0, 0.6, 0))
	local eye = root:PointToWorldSpace(V(-2.4, 5.1, 4.2 - ctx.u * 0.4))
	local look = root:PointToWorldSpace(V(5, 9.5, -22))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.06, 8), 52)
	ctx:focus((bones.Head.Position - eye).Magnitude, 1)
	Cast.ryuAura(ctx, bones, 0.7, 4)
	ctx:bloom(1.3)
	Common.grade(ctx, -0.04, 0.24, 0.1, Color3.fromRGB(205, 230, 255))
	Common.sky(ctx, "wisps", 40)
end

local function ryuProfile(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(-14, -10, 0)), ctx.t))
	Cast.expr(ctx, "ryu", "glare")
	local head = bones.Head * C(0, 0.75, 0)
	local eye = head:PointToWorldSpace(V(2.3 - ctx.u * 0.25, 0.1, -1.7))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.15, 0)), ctx.t, 0.05, 6), 42)
	ctx:focus((head.Position - eye).Magnitude, 1)
	-- cyan glare of the bending blast and sparks blowing past
	local fl = 0.8 + 0.2 * math.sin(ctx.t * 11) * math.sin(ctx.t * 5.3)
	ctx:light("RyuFace", 2.2 * fl, CYAN, 9)
	Common.streamers(ctx, hh.streamers, head.Position + root.LookVector * 1.2, V(0, 0.4, 1), 1.8, 1.4, 60, 0.45)
	local idx = 1
	local a = head:PointToWorldSpace(V(-1.4, 1.2, -1.8))
	idx = FX.placeBolt(ctx, hh.bolts, idx, a, a + V(0, -0.8, 3.5), 7, 0.12, 0.03, 31, 10)
	Cast.ryuAura(ctx, bones, 0.6, 3)
	ctx:bloom(1.6)
	Common.grade(ctx, 0, 0.2, 0.05, Color3.fromRGB(205, 228, 255))
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

local function yutaRaise(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local yroot = Common.yutaRoot()
	local yb = ctx:rig("Yuta", yroot, Cast.alive(Cast.mix(Blast.reachPose(1), raiseArm, Util.smoothstep(0, 0.5, ctx.lt)), ctx.t))
	Cast.expr(ctx, "yuta", "glare")
	local eye = yroot:PointToWorldSpace(V(1.4, 1.3, 3.8))
	local look = yroot:PointToWorldSpace(V(-1.5, 7, -8))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), ctx.t, 0.07, 8), 60)
	ctx:focus(4, 1)
	local src = yroot:PointToWorldSpace(V(-6, 16, -14))
	FX.placeCore(ctx, hh.blastCore, src, 2.6, 1)
	FX.placeCore(ctx, hh.blastHalo, src, 5.5, 0.28)
	FX.placeRays(ctx, hh.rays, src, Util.lookAt(src, eye), 34, 0.45, 0.8, 12, (eye - src).Unit)
	local hand = (yb.RightHand * C(0, -0.4, 0)).Position
	FX.placeCore(ctx, hh.palmGlow, hand, 0.3, 0.7)
	ctx:light("YutaAura", 1.8, CYAN, 14)
	ctx:bloom(1.4)
	Common.grade(ctx, -0.02, 0.25, 0.2, Color3.fromRGB(230, 225, 255))
end

-- folded space: cyan slashes sweeping across a dark blue sky
local function slashes(ctx: Timeline.Ctx)
	local hh = h(ctx)
	Clash.void(ctx, Color3.fromRGB(12, 22, 64))
	local o = Clash.O
	ctx:camera(C(o + V(0, 0, 34)) * CFrame.Angles(0, 0, math.rad(-20)), 62)
	ctx:focus(30, 0)
	for i, b in hh.bands do
		local y0 = (i - 3) * 7
		local function pt(f: number): Vector3
			local a = math.rad(-30 + f * 90)
			return o + V(-40 + f * 80, y0 + math.sin(a) * 10, (i - 3) * 2)
		end
		local head = math.clamp(ctx.u * 1.6 - (i - 1) * 0.1, 0, 1)
		FX.placeCurvedBeam(ctx, b, pt, math.clamp(head - 0.5, 0, 1), head, if i % 2 == 0 then 1.4 else 3, 1)
	end
	FX.placeBurst(ctx, hh.shards, o, ctx.lt, 30, 0.8, 0.8, V(1, 0.3, 0.5), 1, 0)
	ctx:bloom(2.2)
	Common.grade(ctx, 0, 0.25, 0.2, Color3.fromRGB(200, 225, 255))
end

-- the deflected blast flies off into the night like a comet
local function cometAway(ctx: Timeline.Ctx)
	local hh = h(ctx)
	local eye = Common.YUTA + V(-6, 2, -10)
	local dir = V(0.3, 0.55, 1).Unit
	local start = Common.YUTA + V(0, 30, 40)
	local headPos = start + dir * (ctx.lt * 160)
	ctx:camera(Util.lookAt(eye, start + dir * 120), 40)
	ctx:focus(100, 0)
	local k = 1 - Util.smoothstep(0.7, 1, ctx.u)
	FX.placeBeam(ctx, hh.comet, headPos - dir * 30, headPos, 4, k)
	FX.placeCore(ctx, hh.blastCore, headPos, 5, k)
	-- the sparkle where it vanishes
	local s = Util.smoothstep(0.55, 0.8, ctx.u) * (1 - Util.smoothstep(0.85, 1, ctx.u))
	FX.placeRays(ctx, hh.rays, start + dir * 190, Util.lookAt(start + dir * 190, eye), 12, 0.3, s, 8, nil)
	ctx:bloom(2.2)
	Common.grade(ctx, -0.25, 0.3, 0.25, Color3.fromRGB(150, 175, 255))
	ctx:fog(0.5)
end

local function ryuGlow(ctx: Timeline.Ctx)
	local root = Common.ryuRoot(0)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.add(Cast.ryu.spread, "Head", R(6, 0, 0)), ctx.t))
	Cast.expr(ctx, "ryu", "shock")
	local head = bones.Head * C(0, 0.7, 0)
	local eye = head:PointToWorldSpace(V(0.1, -0.35, -3.3 + ctx.u * 0.4))
	ctx:camera(Clash.shake(Util.lookAt(eye, head.Position + V(0, -0.15, 0)), ctx.t, 0.05 + ctx.u * 0.15, 10), 46)
	ctx:focus(3.2, 1)
	local k = Util.smoothstep(0, 1, ctx.u)
	ctx:light("RyuFace", 1.2 + 3 * k, ORANGE, 10)
	ctx:alpha("orangeFlare", Util.smoothstep(0.55, 1, ctx.u))
	ctx:bloom(1.6)
	Common.grade(ctx, 0.02, 0.25, 0.1, Color3.fromRGB(255, 225, 205))
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
	{ id = "P2 27 slashes", t0 = 38.7, t1 = 39.433, run = slashes },
	{ id = "P2 28 comet", t0 = 39.433, t1 = 40.7, run = cometAway },
	{ id = "P2 29 ryu glow", t0 = 40.7, t1 = 42.3, run = ryuGlow },
	{ id = "P2 30 eye black", t0 = 42.3, t1 = 42.9, run = eyeBlack },
} :: { Timeline.Shot }

return Realize
