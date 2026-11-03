--!strict
-- The cast (one rig each, moved from shot to shot) plus helpers shots use:
-- expressions, idle/laugh/run motion, Ryu's blue aura (light + glints).
local Builder = require(script.Parent.Parent.Builder)
local Timeline = require(script.Parent.Parent.Timeline)
local Rig = require(script.Parent.Parent.Rig)
local FX = require(script.Parent.Parent.FX)
local FaceRig = require(script.Parent.Parent.Art.Faces.FaceRig)
local Ryu = require(script.Parent.Parent.Art.Characters.Ryu)
local Yuta = require(script.Parent.Parent.Art.Characters.Yuta)
local Rika = require(script.Parent.Parent.Art.Characters.Rika)

local R = Rig.R
local Cast = {}

export type Handles = {
	ryuAura: FX.Bolt,
	yutaAura: FX.Bolt,
}

function Cast.build(scene: Builder.Scene)
	Ryu.build(scene, "Ryu")
	Yuta.build(scene, "Yuta")
	Rika.build(scene, "Rika")
	local pal = scene.style.color
	-- invisible anchors riding on the bones: lights and particles of the auras
	local function anchor(rig: string, bone: string, size: Vector3, cf: CFrame, name: string): Builder.PartSpec
		return Builder.part(scene, rig, size, cf, Color3.new(1, 1, 1), { rig = rig, bone = bone, transparency = 1, castShadow = false, name = name })
	end
	local ryuChest = anchor("Ryu", "UpperTorso", Vector3.new(2.6, 2.4, 1.6), CFrame.new(0, 1.0, 0), "AuraAnchor")
	Builder.light(scene, "RyuAura", "Point", ryuChest, pal.eCyan, 18)
	Builder.emitter(scene, "RyuGlints", "embers", ryuChest, pal.eCyan, 1.0, 1.0)
	Builder.emitter(scene, "RyuSparks", "sparks", ryuChest, pal.eIce, 0.8, 0.8)
	local ryuHead = anchor("Ryu", "Head", Vector3.new(1.4, 1.2, 1.2), CFrame.new(0, 1.0, 0), "HeadAnchor")
	Builder.light(scene, "RyuFace", "Point", ryuHead, pal.eCyan, 10)
	local ryuHand = anchor("Ryu", "RightHand", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, -0.6, 0), "HandAnchor")
	Builder.light(scene, "RyuHand", "Point", ryuHand, pal.eCyan, 16)
	Builder.emitter(scene, "RyuHandSparks", "sparks", ryuHand, pal.eIce, 0.7, 0.7)
	local yutaChest = anchor("Yuta", "UpperTorso", Vector3.new(2, 2, 1.2), CFrame.new(0, 0.8, 0), "AuraAnchor")
	Builder.light(scene, "YutaAura", "Point", yutaChest, pal.ePink, 16)
	Builder.emitter(scene, "YutaGlints", "embers", yutaChest, pal.ePink, 0.9, 1.0)
	local rikaMouth = anchor("Rika", "Head", Vector3.new(1.5, 1, 1.5), CFrame.new(0, 0.7, -1.6), "MouthAnchor")
	Builder.light(scene, "RikaMouth", "Point", rikaMouth, pal.ePink, 30)
	scene.data.cast = {
		ryuAura = FX.bolts(scene, "RyuBolts", pal.eCyan, 36),
		yutaAura = FX.bolts(scene, "YutaBolts", pal.ePink, 16),
	} :: Handles
end

function Cast.expr(ctx: Timeline.Ctx, who: string, name: string)
	local list = (FaceRig.expr :: any)[who][name]
	assert(list, "unknown expression " .. who .. "." .. name)
	for _, g in list do
		ctx:show(g)
	end
end

-- mouth flaps for speech (talk/closed alternating ~8 times a second)
function Cast.talk(ctx: Timeline.Ctx, who: string, base: string, open: string)
	local phase = math.floor(ctx.t * 8.5) % 3
	Cast.expr(ctx, who, if phase == 0 then base else open)
end

-- pose helpers ----------------------------------------------------------------
function Cast.mix(a: Rig.Pose, b: Rig.Pose, t: number): Rig.Pose
	return Rig.blend(a, b, math.clamp(t, 0, 1))
end

-- add a rotation on top of a pose bone
function Cast.add(p: Rig.Pose, bone: string, rot: CFrame): Rig.Pose
	local q = table.clone(p)
	q[bone] = (q[bone] or CFrame.new()) * rot
	return q
end

-- breathing / shaking with laughter
function Cast.alive(p: Rig.Pose, t: number, laugh: number?): Rig.Pose
	local q = table.clone(p)
	local b = math.sin(t * math.pi * 2 * 0.5) * 1.2
	local l = (laugh or 0) * math.sin(t * math.pi * 2 * 6) * 2.5
	q.UpperTorso = (q.UpperTorso or CFrame.new()) * R(b + l, 0, 0)
	q.Head = (q.Head or CFrame.new()) * R(-b * 0.5 - l * 0.6, 0, 0)
	return q
end

-- running cycle (phase in cycles)
function Cast.run(phase: number, lean: number?): Rig.Pose
	local s = math.sin(phase * math.pi * 2)
	local c = math.cos(phase * math.pi * 2)
	return {
		HumanoidRootPart = CFrame.new(0, -0.15 + math.abs(c) * 0.25, 0),
		LowerTorso = R(-(lean or 18), s * 8, 0),
		UpperTorso = R(-4, -s * 12, 0),
		Head = R((lean or 18) * 0.6, s * 6, 0),
		LeftUpperArm = R(-s * 55, 0, -8),
		LeftLowerArm = R(60, 0, 0),
		RightUpperArm = R(s * 55, 0, 8),
		RightLowerArm = R(60, 0, 0),
		LeftUpperLeg = R(s * 55, 0, 0),
		LeftLowerLeg = R(-math.max(0, -c) * 80 - 15, 0, 0),
		LeftFoot = R(10, 0, 0),
		RightUpperLeg = R(-s * 55, 0, 0),
		RightLowerLeg = R(-math.max(0, c) * 80 - 15, 0, 0),
		RightFoot = R(10, 0, 0),
	}
end

-- Ryu poses ---------------------------------------------------------------------
Cast.ryu = {
	point = Ryu.poses.point,
	spread = {
		UpperTorso = R(-6, 0, 0),
		Head = R(10, 0, 0),
		LeftUpperArm = R(10, 0, -72),
		LeftLowerArm = R(10, 0, -10),
		RightUpperArm = R(10, 0, 72),
		RightLowerArm = R(10, 0, 10),
		LeftUpperLeg = R(0, 0, -8),
		RightUpperLeg = R(0, 0, 8),
	} :: Rig.Pose,
	laughBack = {
		UpperTorso = R(-14, 0, 0),
		Head = R(-22, 0, 0),
		LeftUpperArm = R(8, 0, -50),
		LeftLowerArm = R(30, 0, 0),
		RightUpperArm = R(8, 0, 50),
		RightLowerArm = R(30, 0, 0),
	} :: Rig.Pose,
	raise = {
		UpperTorso = R(-10, 10, 0),
		Head = R(-12, 0, 0),
		RightUpperArm = R(170, 0, 15),
		RightLowerArm = R(10, 0, 0),
		LeftUpperArm = R(10, 0, -35),
		LeftLowerArm = R(30, 0, 0),
	} :: Rig.Pose,
	claw = {
		LowerTorso = R(0, -20, 0),
		UpperTorso = R(10, -25, 0),
		Head = R(-5, 20, 0),
		RightUpperArm = R(80, -20, 20),
		RightLowerArm = R(30, 0, 0),
		RightHand = R(-30, 0, 0),
		LeftUpperArm = R(-20, 0, -20),
		LeftLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(20, 0, -10),
		LeftLowerLeg = R(-25, 0, 0),
		RightUpperLeg = R(-15, 0, 10),
		RightLowerLeg = R(-10, 0, 0),
	} :: Rig.Pose,
	windup = {
		LowerTorso = R(0, 25, 0),
		UpperTorso = R(5, 30, 0),
		Head = R(5, -40, 0),
		RightUpperArm = R(20, 0, 60),
		RightLowerArm = R(80, 0, 0),
		LeftUpperArm = R(70, 0, -20),
		LeftLowerArm = R(10, 0, 0),
	} :: Rig.Pose,
	blast = {
		LowerTorso = R(0, -15, 0),
		UpperTorso = R(4, -20, 0),
		Head = R(0, 25, 0),
		RightUpperArm = R(92, 0, -6),
		RightLowerArm = R(0, 0, 0),
		LeftUpperArm = R(-10, 0, -30),
		LeftLowerArm = R(30, 0, 0),
		LeftUpperLeg = R(20, 0, -6),
		LeftLowerLeg = R(-20, 0, 0),
		RightUpperLeg = R(-12, 0, 6),
	} :: Rig.Pose,
}

Cast.yuta = {
	stand = Yuta.poses.stand,
	fire = {
		UpperTorso = R(0, 20, 0),
		Head = R(0, -10, 0),
		RightUpperArm = R(90, 0, -10),
		RightLowerArm = R(0, 0, 0),
		LeftUpperArm = R(30, 0, -20),
		LeftLowerArm = R(60, 0, 0),
		LeftUpperLeg = R(20, 0, 0),
		LeftLowerLeg = R(-30, 0, 0),
		RightUpperLeg = R(-20, 0, 0),
	} :: Rig.Pose,
	brace = {
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(8, 0, 0),
		Head = R(-14, 0, 0),
		RightUpperArm = R(50, 0, 30),
		RightLowerArm = R(70, 0, 0),
		LeftUpperArm = R(20, 0, -30),
		LeftLowerArm = R(50, 0, 0),
	} :: Rig.Pose,
}

Cast.rika = {
	crouch = Rika.poses.crouch,
	embrace = Rika.poses.embrace,
	roar = Rika.poses.roar,
}

-- Ryu's crackling blue aura: lightning around the body + light + glints
function Cast.ryuAura(ctx: Timeline.Ctx, bones: { [string]: CFrame }, k: number, nBolts: number?)
	if k <= 0 then
		return
	end
	local h: Handles = ctx.scene.data.cast
	local chest = bones.UpperTorso * CFrame.new(0, 1.0, 0)
	local idx = 1
	for i = 1, (nBolts or 5) do
		local a = chest.Position + chest:VectorToWorldSpace(Vector3.new(math.sin(i * 2.1) * 1.3, math.cos(i * 1.7) * 1.2, math.sin(i * 3.3) * 0.6))
		local dir = Vector3.new(math.sin(i * 4.1 + ctx.t * 3), math.cos(i * 2.9) * 0.8 + 0.3, math.cos(i * 1.3 + ctx.t * 2))
		local b = a + dir.Unit * (1.5 + (i % 3) * 0.8)
		idx = FX.placeBolt(ctx, h.ryuAura, idx, a, b, 6, 0.28, 0.07, i, 16)
	end
	ctx:light("RyuAura", 3.5 * k, nil, 16)
	ctx:emit("RyuGlints", 40 * k)
	ctx:emit("RyuSparks", 25 * k)
end

return Cast
