--!strict
-- Rika (Queen of Curses), after the user's reference drawing: a gaunt,
-- skeletal white body with a visible ribcage, a long skull-like head with a
-- huge grin full of teeth, thick white hair-tendrils swept back from the
-- head, long bony arms with long clawed fingers, and no legs: the lower body
-- trails off into a black smoky tail.
-- Rig: R15 topology; the left leg chain is used as the tail (3 segments).
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)

local R = Rig.R
local V = Vector3.new
local C = CFrame.new

local Rika = {}

Rika.dims = {
	hip = 5.2, -- floats: the tail reaches the ground
	hipX = 0,
	waist = 1.0,
	neck = 4.2,
	shoulderY = 3.5,
	shoulderX = 1.9,
	upperArm = 3.7,
	lowerArm = 3.5,
	upperLeg = 2.6, -- tail segment 1
	lowerLeg = 2.4, -- tail segment 2
}

function Rika.build(scene: Builder.Scene, rigName: string): Rig.RigDef
	local def = Rig.humanoid(Rika.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)
	local function E(bone: string, size: Vector3, cf: CFrame, col: string, name: string)
		k.add(bone, "Ellipsoid", size, cf, col, "body", name)
	end

	-- Ribcage: dark core with white rib hoops (bones with dark gaps) ----------
	E("UpperTorso", V(2.3, 3.4, 1.6), C(0, 1.9, 0.1), "kDark", "Core")
	for i = 0, 6 do
		local f = i / 6
		local y = 3.2 - f * 2.5
		local w = 2.6 - math.abs(f - 0.35) * 1.2
		local d = 1.85 - math.abs(f - 0.35) * 0.7
		E("UpperTorso", V(w, 0.26, d), C(0, y, 0.1) * R(-14 + f * 6, 0, 0), "kBody", "Rib")
	end
	E("UpperTorso", V(0.32, 3.0, 0.4), C(0, 1.9, -0.82), "kBody", "Sternum")
	-- hunched spine with vertebra bumps
	for i = 0, 7 do
		local f = i / 7
		E("UpperTorso", V(0.5, 0.45, 0.55), C(0, 0.4 + f * 3.4, 0.9 + math.sin(f * math.pi) * 0.35), "kBody", "Vertebra")
	end
	-- bony shoulders / collarbones
	for _, sx in { -1, 1 } do
		E("UpperTorso", V(1.0, 0.95, 0.95), C(sx * 1.75, 3.55, 0.1), "kBody", "Shoulder")
		E("UpperTorso", V(1.25, 0.26, 0.3), C(sx * 0.95, 3.42, -0.55) * R(0, 0, sx * -14), "kBody", "Collarbone")
	end
	-- thin waist and pelvis
	E("LowerTorso", V(1.5, 1.6, 1.2), C(0, 0.4, 0.15), "kBody", "Waist")
	E("LowerTorso", V(1.6, 0.22, 1.3), C(0, 0.75, 0.15), "kDark", "WaistLine")
	E("LowerTorso", V(2.0, 1.1, 1.4), C(0, -0.35, 0.1), "kDark", "Hips")
	-- long thin neck leaning forward
	E("UpperTorso", V(0.85, 2.2, 0.9), C(0, 4.15, -0.35) * R(-30, 0, 0), "kBody", "Neck")
	E("UpperTorso", V(0.9, 0.16, 0.95), C(0, 4.0, -0.3) * R(-30, 0, 0), "kDark", "NeckLine")

	-- Head: long skull, huge grin, shadowed eyes ------------------------------
	E("Head", V(1.85, 2.2, 3.4), C(0, 1.3, -0.35) * R(-10, 0, 0), "kBody", "Skull")
	E("Head", V(1.65, 1.25, 2.3), C(0, 0.35, -1.05) * R(-6, 0, 0), "kBody", "Jaw")
	-- dark red mouth slit from ear to ear, with rows of teeth
	E("Head", V(1.95, 0.55, 1.5), C(0, 0.68, -1.15), "kMouth", "Mouth")
	local nT = 12
	for i = 0, nT - 1 do
		local a = math.rad(-60 + i * (120 / (nT - 1)))
		local x, z = math.sin(a) * 0.92, -math.cos(a) * 0.72 - 0.98
		k.add("Head", "Wedge", V(0.12, 0.28, 0.16), C(x, 0.84, z) * R(180, -math.deg(a), 0), "kTeeth", "body", "Tooth")
		k.add("Head", "Wedge", V(0.12, 0.24, 0.16), C(x * 0.96, 0.53, z * 0.98 + 0.02) * R(0, -math.deg(a), 0), "kTeeth", "body", "Tooth")
	end
	-- eye shadows under the hair hood
	for _, sx in { -1, 1 } do
		E("Head", V(0.55, 0.3, 0.3), C(sx * 0.48, 1.55, -1.55) * R(0, 0, sx * -15), "kEye", "Socket")
	end
	-- hair: thick white dreadlock-like strands growing from the forehead and
	-- crown, lying along the skull, then sweeping back and drooping (hood)
	local strands = {
		-- {x, y, z, pitch, roll, length, width}
		{ 0.0, 2.25, -1.35, 116, 0, 6.6, 0.86 },
		{ -0.5, 2.2, -1.25, 120, 9, 6.9, 0.8 },
		{ 0.5, 2.2, -1.25, 120, -9, 6.9, 0.8 },
		{ -0.88, 1.95, -0.95, 126, 20, 6.2, 0.72 },
		{ 0.88, 1.95, -0.95, 126, -20, 6.2, 0.72 },
		{ -0.3, 2.38, -0.7, 130, 5, 7.3, 0.84 },
		{ 0.3, 2.38, -0.7, 130, -5, 7.3, 0.84 },
		{ -1.02, 1.62, -0.45, 138, 28, 5.6, 0.66 },
		{ 1.02, 1.62, -0.45, 138, -28, 5.6, 0.66 },
		{ 0.0, 2.3, -0.1, 142, 0, 6.8, 0.8 },
		{ -0.62, 2.0, 0.25, 148, 14, 5.4, 0.62 },
		{ 0.62, 2.0, 0.25, 148, -14, 5.4, 0.62 },
	}
	for i, t in strands do
		local len, w = t[6], t[7]
		local cf = C(t[1], t[2], t[3]) * R(t[4], 0, t[5])
		for si, part in { { 0.42, 1.0, 0 }, { 0.34, 0.78, 18 }, { 0.3, 0.52, 22 } } do
			local segLen, ww = len * part[1], w * part[2]
			cf = cf * R(part[3], 0, 0)
			E("Head", V(ww, segLen * 1.25, ww * 0.9), cf * C(0, segLen * 0.5, 0), "kHair", if si == 1 then "Hair" else "HairTip")
			if si == 1 and i % 2 == 1 then
				E("Head", V(0.1, segLen * 1.1, ww * 0.92 + 0.03), cf * C(0, segLen * 0.5, 0), "kStripe", "HairLine")
			end
			cf = cf * C(0, segLen, 0)
		end
	end

	-- Arms: long and bony, giant clawed hands ---------------------------------
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		E(side .. "UpperArm", V(0.8, 4.1, 0.8), C(0, -1.85, 0), "kBody", "UpperArm")
		k.add(side .. "LowerArm", "Ball", V(0.85, 0.85, 0.85), C(0, 0, 0), "kBody", "body", "Elbow")
		E(side .. "LowerArm", V(0.7, 3.9, 0.7), C(0, -1.75, 0), "kBody", "Forearm")
		E(side .. "LowerArm", V(0.72, 0.12, 0.74), C(0, -2.6, 0) * R(18, 0, 0), "kStripe", "ForearmLine")
		local hand = side .. "Hand"
		E(hand, V(1.05, 1.0, 0.45), C(0, -0.5, 0), "kBody", "Palm")
		for fi = 0, 3 do
			local fx = (fi - 1.5) * 0.25
			local cf = C(fx, -0.95, 0) * R(-8, 0, (fi - 1.5) * -6)
			for si, len in { 0.95, 0.85, 0.7 } do
				E(hand, V(0.17, len + 0.08, 0.17), cf * C(0, -len / 2, 0), "kBody", "Finger")
				E(hand, V(0.22, 0.2, 0.22), cf, "kBodyShade", "Knuckle")
				cf = cf * C(0, -len, 0) * R(-16, 0, 0)
				if si == 3 then
					k.add(hand, "Wedge", V(0.12, 0.38, 0.18), cf * R(180, 0, 0), "kStripe", "body", "Claw")
				end
			end
		end
		local tcf = C(sx * -0.5, -0.55, -0.15) * R(-15, 0, sx * -40)
		for si, len in { 0.8, 0.65 } do
			E(hand, V(0.2, len + 0.08, 0.2), tcf * C(0, -len / 2, 0), "kBody", "Thumb")
			tcf = tcf * C(0, -len, 0) * R(-14, 0, 0)
			if si == 2 then
				k.add(hand, "Wedge", V(0.13, 0.34, 0.18), tcf * R(180, 0, 0), "kStripe", "body", "Claw")
			end
		end
	end

	-- Black smoky tail instead of legs (on the left leg chain): long
	-- overlapping tapered segments and a few wisps peeling off
	local tail = {
		{ bone = "LeftUpperLeg", len = 2.6, w0 = 2.0, w1 = 1.55 },
		{ bone = "LeftLowerLeg", len = 2.4, w0 = 1.55, w1 = 1.05 },
		{ bone = "LeftFoot", len = 2.6, w0 = 1.05, w1 = 0.25 },
	}
	for ti, seg in tail do
		local bone, len, w0, w1 = seg.bone, seg.len, seg.w0, seg.w1
		for j = 0, 2 do
			local f = (j + 0.5) / 3
			local w = w0 + (w1 - w0) * f
			E(bone, V(w, len * 0.75, w * 0.85), C(math.sin(j * 1.9 + ti) * 0.06, -len * f, 0), "kDark", "Tail")
		end
		E(bone, V(0.16, len * 0.8, 0.2), C(w0 * 0.45, -len * 0.55, 0.15) * R(0, 0, 14 + ti * 4), "kStripe", "Wisp")
		E(bone, V(0.12, len * 0.6, 0.16), C(-w0 * 0.4, -len * 0.6, -0.1) * R(0, 0, -12), "kStripe", "Wisp")
	end
	return def
end

Rika.poses = {
	-- hunched forward like the reference drawing, long arms hanging down
	crouch = {
		HumanoidRootPart = CFrame.new(0, -0.4, 0),
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(-28, 4, 0),
		Head = R(-8, -8, 4),
		LeftUpperArm = R(26, 0, -14),
		LeftLowerArm = R(-12, 0, 0),
		LeftHand = R(-18, 0, 0),
		RightUpperArm = R(34, 0, 20),
		RightLowerArm = R(30, 0, 0),
		RightHand = R(-10, 0, 0),
		LeftUpperLeg = R(24, 0, 16),
		LeftLowerLeg = R(-26, 0, -34),
		LeftFoot = R(-30, 0, -40),
	} :: Rig.Pose,
	-- looming over Yuta, wrapping both arms forward around him
	embrace = {
		HumanoidRootPart = CFrame.new(0, 0.6, 0),
		LowerTorso = R(-8, 0, 0),
		UpperTorso = R(-34, 0, 0),
		Head = R(-14, 10, -8),
		LeftUpperArm = R(70, 0, -26),
		LeftLowerArm = R(60, 0, 0),
		LeftHand = R(10, 0, 0),
		RightUpperArm = R(76, 0, 24),
		RightLowerArm = R(64, 0, 0),
		RightHand = R(12, 0, 0),
		LeftUpperLeg = R(20, 0, -14),
		LeftLowerLeg = R(-24, 0, 30),
		LeftFoot = R(-26, 0, 36),
	} :: Rig.Pose,
	-- head thrust forward, jaw aimed at the target (fires the beam)
	roar = {
		HumanoidRootPart = CFrame.new(0, 0.8, 0),
		LowerTorso = R(-12, 0, 0),
		UpperTorso = R(-30, 0, 0),
		Head = R(4, 0, 0),
		LeftUpperArm = R(26, 0, -40),
		LeftLowerArm = R(40, 0, 0),
		RightUpperArm = R(26, 0, 40),
		RightLowerArm = R(40, 0, 0),
		LeftUpperLeg = R(30, 0, 12),
		LeftLowerLeg = R(-34, 0, -28),
		LeftFoot = R(-30, 0, -34),
	} :: Rig.Pose,
}

return Rika
