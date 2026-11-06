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
	chargeHalo: Builder.PartSpec,
	motes: FX.Burst,
	chargeRays: FX.Rays,
	crown: FX.Bolt,
	arc: FX.CurvedBeam,
	spiral: FX.Burst,
	debris: FX.Burst,
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
		chargeHalo = FX.core(scene, "RyuChargeHalo", Util.mix(pal.eCyan, Color3.new(1, 1, 1), 0.35)),
		motes = FX.burst(scene, "RyuChargeMotes", pal.eCyan, 28, "Block", 41),
		chargeRays = FX.rays(scene, "RyuChargeRays", { pal.eCyan, Color3.new(1, 1, 1) }, 10, 43),
		crown = FX.bolts(scene, "RyuCrownBolts", Util.mix(pal.eCyan, Color3.new(1, 1, 1), 0.55), 56),
		arc = FX.curvedBeam(scene, "RikaArc", pal.ePink, 18),
		spiral = FX.burst(scene, "RikaArcSpiral", Util.mix(pal.ePink, Color3.new(1, 1, 1), 0.4), 40, "Block", 51),
		debris = FX.burst(scene, "TrenchDebris", pal.rubble, 24, "Block", 53),
	}
	-- the debris is rock, not light
	for _, p in h.debris.parts do
		p.material = "Slate"
	end
	Builder.light(scene, "RyuCharge", "Point", h.chargeHalo, pal.eCyan, 18)
	Builder.light(scene, "PinkHead", "Point", h.pinkCore, pal.ePink, 40)
	scene.data.ryu = h
end

-- Where the Granite Blast gathers: on top of his head, at the front of the
-- pompadour (not on the face)
local function chargePoint(bones: { [string]: CFrame }): Vector3
	return (bones.Head * C(0, 1.74, -0.72)).Position
end

-- The Granite Blast gathering on his head: motes of energy stream in from
-- all around, the glow swells and flickers, short rays crackle off it and
-- light the face. k = 0..1 charge level.
local function charge(ctx: Timeline.Ctx, center: Vector3, k: number, basis: CFrame, scale: number?)
	if k <= 0.01 then
		return
	end
	local sc = scale or 1
	local h: H = ctx.scene.data.ryu
	local t = ctx.t
	local flick = 0.86 + 0.14 * math.sin(t * 37) * math.sin(t * 23 + 1)
	FX.placeCore(ctx, h.headGlow, center, (0.12 + 0.17 * k) * flick * sc, 1)
	FX.placeCore(ctx, h.chargeHalo, center, (0.2 + 0.26 * k) * flick * sc, 0.16 * k)
	for i, p in h.motes.parts do
		local r = Util.rng(500 + i * 13)
		local dir = V(Util.randRange(r, -1, 1), Util.randRange(r, -0.5, 1), Util.randRange(r, -1, 1)).Unit
		local ph = (t * (1.0 + Util.rand(r) * 0.9) + Util.rand(r)) % 1
		local dist = ((0.6 + 2.4 * k) * (1 - ph) ^ 1.6 + 0.12) * sc
		local pos = center + dir * dist
		local len = (0.12 + 0.4 * (1 - ph)) * sc
		ctx:place(p, FX.along(pos + dir * len, pos))
		ctx:prop(p, { s = V(len, 0.035 * sc, 0.035 * sc), t = 1 - 0.85 * k * math.min(1, ph * 4) })
	end
	FX.placeRays(ctx, h.chargeRays, center, basis, (0.45 + 0.7 * k) * sc, 0.025 * sc, 0.6 * k, 14)
	ctx:light("RyuCharge", (0.8 + 1.4 * k) * flick, nil, 6 + 4 * k)
end

-- Ryu standing at `pos` facing `yaw` degrees (0 = -Z, -90 = +X)
local function rootAt(pos: Vector3, yaw: number): CFrame
	return C(pos) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function sky(ctx: Timeline.Ctx, mistName: string?, depth: number?)
	Field.snow(ctx, 120)
	-- fog banks behind the characters in every shot on the field
	Field.mist(ctx, mistName or "low", depth or 34, 0.4)
	if mistName ~= "wisps" then
		Field.mist(ctx, "wisps", 70, -0.3, -0.08)
	end
end

local function grade(ctx: Timeline.Ctx, b: number, c: number, s: number, tint: Color3?)
	ctx:grade({ brightness = b, contrast = c, saturation = s, tint = tint or Color3.fromRGB(232, 238, 255) })
end

-- 7: low angle from the front: Ryu points at Yuta, his left arm thrown out
-- up and to the side with the index finger out (aiming the blast), the
-- Granite Blast gathering in a blinding star on top of his head; cyan
-- shards and pink streaks fly off it (reference 10.87-12.1)
local pointAt: Rig.Pose = {
	LowerTorso = R(0, -6, 0),
	UpperTorso = R(4, 10, 0),
	Head = R(-10, 14, 0),
	LeftUpperArm = R(-14, 0, -146),
	LeftLowerArm = R(0, 0, 0),
	LeftHand = R(0, 0, 0),
	RightUpperArm = R(-4, 0, 14),
	RightLowerArm = R(26, 0, 0),
	LeftUpperLeg = R(-6, 0, -6),
	RightUpperLeg = R(8, 0, 6),
}

local function raise(ctx: Timeline.Ctx)
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -90)
	local thrust = Util.smoothstep(10.867, 11.05, ctx.t)
	-- the arm snaps out and recoils a little, then holds with small jolts
	local jolt = math.exp(-math.max(0, ctx.t - 11.05) * 6) * math.sin(math.max(0, ctx.t - 11.05) * 30) * 6
	local pose = Cast.add(Cast.mix(Cast.ryu.point, pointAt, thrust), "LeftUpperArm", R(0, 0, jolt))
	local bones = ctx:rig("Ryu", root, Cast.alive(pose, ctx.t))
	Cast.point(ctx, "Ryu", "Left")
	-- very low in front of him, looking up past his face
	local cam = Util.lookAt(root:PointToWorldSpace(V(-1.0, 1.0, -5.6)), root:PointToWorldSpace(V(-0.6, 6.2, 0)))
	ctx:camera(Clash.shake(cam, ctx.t, 0.35), 62)
	ctx:focus(5.6, 1)
	Cast.expr(ctx, "ryu", "grin")
	Cast.ryuAura(ctx, bones, 1, 6)
	-- the charge on his head: a big flickering star with shards flying off
	local top = chargePoint(bones) + bones.Head.UpVector * 0.5
	charge(ctx, top, 1, bones.Head.Rotation, 4.2)
	FX.placeBurst(ctx, h.shards, top, ctx.lt % 0.8, 26, 0.7, 0.7, V(0.4, 0.6, -0.2), 1.2, 6)
	FX.placeCore(ctx, h.headGlow, top, 0.55 + math.sin(ctx.t * 24) * 0.08, 0.95)
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
	-- closed smirk until he speaks, a toothy grin once he has finished
	Cast.talk(ctx, "ryu", if ctx.t < 16.1 then "smirk" else "grin", "laugh")
	Cast.ryuAura(ctx, bones, 1, 7)
	ctx:light("RyuFace", 1.6, nil, 9)
	ctx:bloom(1.6)
	grade(ctx, 0, 0.18, -0.12)
	sky(ctx, "wisps", 26)
end

-- 17: standing on the cracked ice, crater ahead, arm out
-- 17 (22.57-25.07): Ryu on the cracked ice facing the crater, seen from
-- his right and a little behind (he stands at the left third facing right,
-- the crater at the right): a loose, slightly hunched stance, knees a little
-- bent, the near (right) hand bent forward at the waist, the other hanging,
-- the head turned to the crater; fog and smoke drifting, wind streaks; it
-- opens on a white blur shot through with cyan streaks
local iceStance: Rig.Pose = {
	HumanoidRootPart = C(0, -0.18, 0),
	LowerTorso = R(-6, -6, 0),
	UpperTorso = R(-10, -10, 0),
	Head = R(2, 10, 0),
	RightUpperArm = R(26, 0, 12),
	RightLowerArm = R(72, 0, 0),
	RightHand = R(-10, 0, 0),
	LeftUpperArm = R(10, 0, -12),
	LeftLowerArm = R(28, 0, 0),
	LeftUpperLeg = R(-14, 0, -4),
	LeftLowerLeg = R(-22, 0, 0),
	LeftFoot = R(12, 0, 0),
	RightUpperLeg = R(18, 0, 5),
	RightLowerLeg = R(-14, 0, 0),
}

local function onIce(ctx: Timeline.Ctx)
	local t = ctx.t
	local dir = (Field.CRATER - Field.RYU)
	local yaw = math.deg(math.atan2(-dir.X, -dir.Z))
	local root = rootAt(Field.RYU, yaw)
	-- small living motion: weight shifting, the shoulders rising on a breath
	local sway = math.sin(t * 1.3) * 1.5
	local pose = Cast.add(Cast.add(iceStance, "LowerTorso", R(0, sway, 0)), "RightUpperArm", R(math.sin(t * 1.7) * 2, 0, 0))
	local bones = ctx:rig("Ryu", root, Cast.alive(pose, t))
	local drift = ctx.u * 0.6
	-- from further off with a long lens, so the crater behind him looms
	local eye = root:PointToWorldSpace(V(13 - drift, 4.2, 9))
	local look = root:PointToWorldSpace(V(-3.2, 3.9, -14))
	ctx:camera(Clash.shake(Util.lookAt(eye, look), t, 0.05, 4), 36)
	ctx:focus((bones.UpperTorso.Position - eye).Magnitude, 0.8)
	Cast.expr(ctx, "ryu", "glare")
	-- a few cyan sparks crackling round his head
	Cast.ryuAura(ctx, bones, 0.35, 2)
	-- the opening blur: white smoke with cyan streaks wiping across
	local blur = 1 - Util.smoothstep(22.6, 22.85, t)
	if blur > 0 then
		ctx:flash(Color3.fromRGB(226, 234, 248), 0.85 * blur)
		ctx:alpha("streaks", 0)
	end
	ctx:alpha("wind", 0.55)
	ctx:wind(1.8)
	ctx:gust(0.4 + 0.3 * math.max(0, math.sin(t * 2.3)))
	ctx:fog(2.1)
	grade(ctx, 0.1, 0.1, -0.12, Color3.fromRGB(218, 228, 252))
	-- thick fog and drifting smoke: a heavy bank behind, wisps in front
	Field.snow(ctx, 120)
	-- clouds of white smoke rolling over the crater, a low bank on the ground
	Field.mist(ctx, "low", 24, 0, -0.1)
	Field.mist(ctx, "wisps", 32, 0, 0.14)
	Field.mist(ctx, "heavy", 75, 0, 0.2)
end

-- 18: front, low angle, grinning, lightning on the arm, wind
local function grin(ctx: Timeline.Ctx)
	-- 25.07-26.30 grinning into the camera while cyan energy whips past;
	-- 26.30-26.60 he spins away; then walks off, looking back over his right
	-- shoulder with the same grin (reference 25-27.5 s)
	local h: H = ctx.scene.data.ryu
	local t = ctx.t
	local turn = Util.smoothstep(26.3, 26.62, t)
	local walkT = math.max(0, t - 26.42)
	local yaw0 = -60
	local yaw = yaw0 + turn * 150
	local fwd = CFrame.Angles(0, math.rad(yaw), 0).LookVector
	local pos = Field.RYU + fwd * (walkT * 3.2)
	local root = C(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	local pose = Cast.alive(Cast.add(Cast.ryu.spread, "RightUpperArm", R(-40, 0, -30)), t)
	if walkT > 0 then
		local w = Cast.walk(walkT * 1.25)
		w.UpperTorso = (w.UpperTorso or CFrame.new()) * R(0, -38 * turn, 0)
		w.Head = R(-4, -84 * turn, 4)
		pose = Cast.mix(pose, w, Util.smoothstep(26.42, 26.62, t))
	end
	local bones = ctx:rig("Ryu", root, pose)
	-- once he looks back over his shoulder, keep the big collar out of his face
	Cast.furLow(ctx, "Ryu", turn)
	local head = bones.Head * C(0, 0.7, 0)
	-- front-left and slightly low while he grins; as he turns away the camera
	-- swings up behind his right shoulder, at head height, to catch the look back
	local base = rootAt(Field.RYU, yaw0)
	local eyeA = base:PointToWorldSpace(V(-1.2, 2.7, -5.0 + (t - 25.067) * 0.2))
	local eyeC = root:PointToWorldSpace(V(2.4, 7.8, 2.6))
	local eye = eyeA:Lerp(eyeC, turn)
	local cam = Util.lookAt(eye, head.Position + V(0, -0.7 + turn * 0.3, 0))
	ctx:camera(Clash.shake(cam * CFrame.Angles(0, 0, math.rad(-6)), t, 0.06 + turn * (1 - turn) * 0.8, 10), 46)
	ctx:focus((head.Position - eye).Magnitude, 1)
	Cast.expr(ctx, "ryu", "grin")
	if turn < 0.5 then
		local idx = 1
		local hand = (bones.RightHand * C(0, -0.4, 0)).Position
		local shoulder = (bones.RightUpperArm).Position
		for i = 1, 4 do
			idx = FX.placeBolt(ctx, h.bolts, idx, shoulder, hand + V(math.sin(i) * 0.5, math.cos(i) * 0.4, 0), 6, 0.18, 0.06, i + 30, 16)
		end
	end
	Cast.ryuAura(ctx, bones, 0.8 * (1 - turn * 0.6), 4)
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
	Cast.talk(ctx, "ryu", "grin", "laugh")
	Cast.ryuAura(ctx, bones, 0.4, 3)
	ctx:alpha("wind", 0.4)
	grade(ctx, 0.03, 0.15, -0.08)
	sky(ctx)
end

-- 21: "Let's keep going!" laughing up into a cyan glare, yellow bolt across
local function keepGoing(ctx: Timeline.Ctx)
	-- laughing with his head thrown back while the Granite Blast gathers on
	-- top of his head (reference 31.4-33.9 s): front, chest height
	local h: H = ctx.scene.data.ryu
	local root = rootAt(Field.RYU, -70)
	local pose = Cast.add(Cast.alive(Cast.ryu.laughBack, ctx.t, 1), "Head", R(-12, 10, 6))
	local bones = ctx:rig("Ryu", root, pose)
	local head = bones.Head * C(0, 0.7, 0)
	local eye = root:PointToWorldSpace(V(-1.1, 4.3, -5.4 + ctx.u * 0.5))
	local cam = Util.lookAt(eye, head.Position + V(0, -0.3, 0))
	ctx:camera(Clash.shake(cam * CFrame.Angles(0, 0, math.rad(6)), ctx.t, 0.1, 10), 46)
	ctx:focus((head.Position - eye).Magnitude, 1)
	Cast.talk(ctx, "ryu", "laugh", "shout")
	Cast.ryuAura(ctx, bones, 1, 5)
	charge(ctx, chargePoint(bones), 0.35 + 0.65 * Util.smoothstep(31.4, 33.4, ctx.t), bones.Head.Rotation)
	ctx:light("RyuFace", 1.0, nil, 8)
	local a = head:PointToWorldSpace(V(-5, -2.2, -1))
	FX.placeBolt(ctx, h.bolts, 1, a, a + head:VectorToWorldSpace(V(10, 0.8, 0)), 10, 0.06, 0.05, 77, 12)
	ctx:bloom(1.15)
	grade(ctx, 0.02, 0.2, -0.1)
	sky(ctx, "wisps", 24)
end

-- 26: top view, the pink beam ploughs the trench towards a tiny Ryu
local function topDown(ctx: Timeline.Ctx)
	-- top view: Rika's beam bends in a wide pink arc towards a tiny Ryu,
	-- ploughing the trench; energy spirals around it, rock and ice spray up
	-- at its head (reference 35.6-36.9 s)
	local h: H = ctx.scene.data.ryu
	local t = ctx.t
	local root = rootAt(Field.RYU, -60)
	local bones = ctx:rig("Ryu", root, Cast.ryu.blast)
	-- straight down, the beam coming up the frame at Ryu near the top edge
	local mid = Field.trenchPoint(0.62)
	local upDir = (Field.TRENCH_TO - Field.TRENCH_FROM).Unit
	local cam = Util.lookAt(mid + V(0, 100 - ctx.u * 10, 0) - upDir * 6, mid + upDir * 4, upDir)
	ctx:camera(cam * CFrame.Angles(0, 0, math.rad(10)), 52)
	ctx:focus(95, 0)
	local p = Field.trenchProgress(t)
	local function beamPoint(f: number): Vector3
		-- leaves Rika high up and skims the ground towards its head
		return Field.trenchPoint(f) + V(0, 1.4 + 5 * (1 - f) ^ 2, 0)
	end
	FX.placeCurvedBeam(ctx, h.arc, beamPoint, 0, p, 4.2, 1)
	local head = beamPoint(p)
	local flick = 1 + math.sin(t * 43) * 0.12
	FX.placeCore(ctx, h.pinkCore, head, 2.6 * flick, 0.95)
	-- spiralling energy along the beam
	local tan = Field.trenchTangent(p)
	for i, part in h.spiral.parts do
		local ph = (t * 0.8 + i / #h.spiral.parts) % 1
		local f = p * (1 - ph * 0.85)
		local c = beamPoint(f)
		local tg = Field.trenchTangent(f)
		local side = tg:Cross(V(0, 1, 0)).Unit
		local up = side:Cross(tg).Unit
		local a = t * 11 + i * 0.9
		local rr = 2.4 + math.sin(i * 1.7) * 0.7
		local pos = c + (side * math.cos(a) + up * math.sin(a)) * rr
		ctx:place(part, FX.along(pos, pos + tg * 2.6))
		ctx:prop(part, { s = V(2.6, 0.32, 0.32), t = 0.1 + ph * 0.6 })
	end
	-- rock and ice thrown up at the head, in pulses
	local ground = Field.trenchPoint(p)
	FX.placeBurst(ctx, h.debris, ground, (t * 1.6) % 0.62, 26, 1.6, 0.62, V(0, 1, 0) - tan * 0.6, 0.9, 30)
	ctx:light("PinkHead", 6, nil, 40)
	Cast.ryuAura(ctx, bones, 1, 4)
	ctx:fog(0.6)
	ctx:bloom(1.8)
	grade(ctx, 0, 0.18, 0)
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
	Cast.ryuAura(ctx, bones, 1, 6)
	-- a crown of long lightning bolts radiating from the charge on his head
	local top = chargePoint(bones)
	charge(ctx, top, 0.6 + 0.4 * e, bones.Head.Rotation)
	local idx = 1
	for i = 1, 7 do
		local a = math.rad(i * (360 / 7) + math.sin(ctx.t * 1.3 + i) * 12)
		local up = 0.6 + math.sin(i * 2.3) * 0.5
		local dir = V(math.cos(a), up, math.sin(a)).Unit
		idx = FX.placeBolt(ctx, h.crown, idx, top, top + dir * (7 + (i % 3) * 2.5), 8, 0.16, 0.05, i + 90, 16)
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
	local root = rootAt(Field.RYU, -90)
	local bones = ctx:rig("Ryu", root, Cast.alive(Cast.ryu.spread, ctx.t, 0.2))
	-- low angle from the waist up, the shouting face clearly visible
	-- from below, then a fast pull back until he stands small in the fog
	local back = Util.smoothstep(0, 1, ctx.u) ^ 0.8
	local eye = root:PointToWorldSpace(V(-1.0 - back * 1.5, 1.9 + back * 0.6, -5.2 - back * 10))
	local cam = Util.lookAt(eye, root:PointToWorldSpace(V(0, 4.7 - back * 1.2, 0)))
	ctx:camera(cam, 50)
	ctx:focus((root.Position + Vector3.new(0, 4, 0) - eye).Magnitude, 1)
	Cast.expr(ctx, "ryu", "shout")
	-- the Granite Blast fully charged on top of his head
	charge(ctx, chargePoint(bones), 0.75 + 0.25 * ctx.u, bones.Head.Rotation, 1.9 + ctx.u * 1.6)
	ctx:light("RyuFace", 1.0, nil, 8)
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
