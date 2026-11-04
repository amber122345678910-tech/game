--!strict
-- Rika (Queen of Curses), after the user's reference drawing, built in detail:
-- a gaunt skeletal white body (ribs arching round a dark chest cavity, a
-- knobbed spine, collarbones, shoulder blades, hip bones), a long skull-like
-- head (brow ridge, cheekbones, deep eye sockets, nostril slits) whose lower
-- half is one huge grin with two rows of long fangs and gums, thick white
-- hair strands swept back, long bony arms (two forearm bones, knobbly elbows
-- and wrists) with long clawed fingers, and no legs: the body trails off into
-- a black smoky tail. Two tones of bone for shading. Hair and smoke sway.
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
	local function E(bone: string, size: Vector3, cf: CFrame, col: string, name: string): Builder.PartSpec
		return k.add(bone, "Ellipsoid", size, cf, col, "body", name)
	end
	local function B(bone: string, size: Vector3, cf: CFrame, col: string, name: string): Builder.PartSpec
		return k.add(bone, "Ball", size, cf, col, "body", name)
	end
	-- a bone between two points (local to a bone), as a stretched ellipsoid
	local function bar(bone: string, a: Vector3, b: Vector3, w: number, col: string, name: string)
		local d = b - a
		local len = d.Magnitude
		local y = d / len
		local x = if math.abs(y.X) < 0.9 then V(1, 0, 0) else V(0, 0, 1)
		local z = x:Cross(y).Unit
		x = y:Cross(z).Unit
		local m = (a + b) / 2
		E(bone, V(w, len + w * 0.6, w), CFrame.fromMatrix(m, x, y, z), col, name)
	end

	-- Chest: a dark cavity with ribs arching round it --------------------------
	-- gaunt white flesh under the ribs (shaded), so the ribcage reads as bones
	-- pressing through skin; dark grooves only deep between the lower ribs
	E("UpperTorso", V(2.2, 3.1, 1.55), C(0, 1.95, 0.15), "kBodyShade", "Chest")
	E("UpperTorso", V(1.5, 1.2, 1.05), C(0, 0.6, 0.2), "kDark", "Belly")
	for side = -1, 1, 2 do
		for i = 0, 8 do
			local f = i / 8
			local y0 = 3.2 - f * 2.6
			local rw = 1.25 - math.abs(f - 0.35) * 0.55 -- ribs widest at the middle
			local rd = 0.85 - math.abs(f - 0.35) * 0.3
			local drop = 0.25 + f * 0.15
			-- each rib: spine -> side -> front, four segments, sloping down to the front
			local pts = {
				V(side * 0.15, y0, 0.85),
				V(side * rw * 0.85, y0 - drop * 0.2, 0.55),
				V(side * rw, y0 - drop * 0.55, 0.0),
				V(side * rw * 0.8, y0 - drop * 0.85, -0.6),
				V(side * 0.22, y0 - drop, -rd),
			}
			for s = 1, 4 do
				bar("UpperTorso", pts[s], pts[s + 1], 0.2 - f * 0.03, if s == 2 then "kBodyShade" else "kBody", "Rib")
			end
		end
	end
	for i = 0, 4 do
		E("UpperTorso", V(0.34, 0.5, 0.3), C(0, 3.0 - i * 0.55, -0.92 + i * 0.03), "kBody", "Sternum")
	end
	-- spine: vertebrae with spiny processes down the back
	for i = 0, 10 do
		local f = i / 10
		local z = 0.95 + math.sin(f * math.pi) * 0.35
		B("UpperTorso", V(0.5, 0.42, 0.5), C(0, 0.2 + f * 3.6, z), "kBody", "Vertebra")
		E("UpperTorso", V(0.16, 0.3, 0.34), C(0, 0.2 + f * 3.6, z + 0.32) * R(-30, 0, 0), "kBodyShade", "Process")
	end
	-- collarbones, shoulder balls, shoulder blades
	for _, sx in { -1, 1 } do
		bar("UpperTorso", V(sx * 0.15, 3.45, -0.75), V(sx * 1.55, 3.6, -0.1), 0.24, "kBody", "Collarbone")
		B("UpperTorso", V(1.0, 0.95, 0.95), C(sx * 1.75, 3.55, 0.1), "kBody", "Shoulder")
		E("UpperTorso", V(1.1, 1.5, 0.22), C(sx * 0.85, 2.7, 1.05) * R(-10, sx * 20, sx * 8), "kBodyShade", "Blade")
	end
	-- waist and hip bones above the tail
	E("LowerTorso", V(1.2, 1.4, 1.0), C(0, 0.45, 0.2), "kDark", "Waist")
	for i = 0, 2 do
		B("LowerTorso", V(0.5, 0.42, 0.5), C(0, 0.2 + i * 0.45, 0.75), "kBody", "Vertebra")
	end
	for _, sx in { -1, 1 } do
		E("LowerTorso", V(0.9, 1.0, 1.3), C(sx * 0.7, -0.25, 0.15) * R(0, 0, sx * -18), "kBody", "HipBone")
		E("LowerTorso", V(0.5, 0.6, 0.9), C(sx * 0.55, -0.45, 0.2) * R(0, 0, sx * -18), "kDark", "HipHollow")
	end
	E("LowerTorso", V(1.8, 0.9, 1.3), C(0, -0.55, 0.15), "kDark", "Pelvis")
	-- long thin neck leaning forward: vertebrae and two tendons
	for i = 0, 4 do
		B("UpperTorso", V(0.46, 0.4, 0.46), C(0, 3.75 + i * 0.32, -0.15 - i * 0.12), "kBody", "NeckBone")
	end
	for _, sx in { -1, 1 } do
		bar("UpperTorso", V(sx * 0.4, 3.5, -0.55), V(sx * 0.18, 5.1, -0.75), 0.16, "kBodyShade", "Tendon")
	end

	-- Head: a long skull ---------------------------------------------------------
	E("Head", V(1.85, 2.0, 2.6), C(0, 1.75, -0.05) * R(-10, 0, 0), "kBody", "Cranium")
	E("Head", V(1.7, 1.6, 1.4), C(0, 1.5, 0.7), "kBody", "Occiput")
	E("Head", V(1.75, 0.34, 0.55), C(0, 1.84, -1.32) * R(-8, 0, 0), "kBody", "BrowRidge")
	E("Head", V(1.6, 2.0, 1.4), C(0, 0.85, -0.95) * R(-6, 0, 0), "kBody", "Face")
	E("Head", V(1.5, 0.85, 1.25), C(0, -0.2, -0.8) * R(10, 0, 0), "kBody", "Jaw")
	E("Head", V(0.8, 0.5, 0.6), C(0, -0.42, -1.25), "kBodyShade", "Chin")
	for _, sx in { -1, 1 } do
		E("Head", V(0.42, 0.9, 0.9), C(sx * 0.8, 1.5, -0.8), "kBodyShade", "Temple")
		E("Head", V(0.55, 0.42, 0.8), C(sx * 0.7, 1.15, -1.25) * R(0, sx * 20, 0), "kBody", "Cheekbone")
		-- deep eye sockets with a faint glint far inside
		E("Head", V(0.52, 0.2, 0.3), C(sx * 0.48, 1.54, -1.62) * R(0, 0, sx * -22), "kEye", "Socket")
		B("Head", V(0.09, 0.09, 0.05), C(sx * 0.45, 1.5, -1.77), "kTeeth", "Glint")
		E("Head", V(0.1, 0.24, 0.1), C(sx * 0.12, 1.12, -1.78) * R(0, 0, sx * 12), "kEye", "Nostril")
		-- the grin cuts up into the cheeks
		bar("Head", V(sx * 0.7, 0.6, -1.52), V(sx * 0.86, 1.02, -1.26), 0.07, "kStripe", "GrinLine")
		bar("Head", V(sx * 0.62, 1.0, -1.64), V(sx * 0.7, 1.4, -1.58), 0.05, "kStripe", "Crease")
	end
	-- the mouth: a huge open grin, gums, two rows of long fangs, a tongue
	-- set back so the fangs stand in front of the dark mouth
	E("Head", V(1.5, 1.25, 0.6), C(0, 0.45, -1.42) * R(-6, 0, 0), "kMouth", "Mouth")
	E("Head", V(1.42, 0.16, 0.42), C(0, 0.98, -1.7), "kMouth", "Gum")
	E("Head", V(1.36, 0.16, 0.4), C(0, -0.07, -1.62), "kMouth", "Gum")
	E("Head", V(0.7, 0.2, 0.9), C(0, 0.06, -1.36), "kStripe", "Tongue")
	local nT = 15
	for i = 0, nT - 1 do
		local f = (i - (nT - 1) / 2) / ((nT - 1) / 2) -- -1..1 across the mouth
		local a = math.rad(f * 52)
		local fang = if math.abs(math.abs(f) - 0.5) < 0.1 then 1.35 else 1.0 -- longer canines
		local mid = (1 - math.abs(f) * 0.4) * fang
		local x, z = math.sin(a) * 0.7, -1.86 + (1 - math.cos(a)) * 0.55
		local turn = if i % 2 == 0 then 90 else -90
		local up = 0.72 * mid
		k.add("Head", "Wedge", V(0.06, up, 0.16), C(x, 1.0 - up / 2, z) * R(0, -math.deg(a), 0) * R(0, 0, 180) * R(0, turn, 0), "kTeeth", "body", "Fang")
		local low = 0.62 * mid
		k.add("Head", "Wedge", V(0.06, low, 0.15), C(x * 0.94, -0.12 + low / 2, z + 0.04) * R(0, -math.deg(a), 0) * R(0, turn, 0), "kTeeth", "body", "Fang")
	end

	-- Hair: 24 thick strands swept back from the brow and crown, curling down,
	-- in two tones; every segment sways a little more than the one above it
	for row = 0, 2 do
		for i = 0, 7 do
			local u = (i - 3.5) / 3.5
			local x = u * (0.95 - row * 0.12)
			local z = -1.25 + row * 0.62
			local y = 2.3 - math.abs(u) * 0.38 - row * 0.05
			local pitch = 114 + row * 12 + math.abs(u) * 10
			local roll = -u * 24
			local len = 6.6 - math.abs(u) * 1.5 - row * 0.5
			local w = 0.84 - math.abs(u) * 0.18
			local col = if (i + row) % 3 == 0 then "kBodyShade" else "kHair"
			local cf = C(x, y, z) * R(pitch, 0, roll)
			for si, seg in { { 0.36, 1.0, 0 }, { 0.3, 0.8, 16 }, { 0.2, 0.6, 18 }, { 0.14, 0.42, 22 } } do
				local segLen, ww = len * seg[1], w * seg[2]
				cf = cf * R(seg[3], 0, 0)
				Builder.flex(k.add("Head", "Ellipsoid", V(ww, segLen * 1.25, ww * 0.85), cf * C(0, segLen * 0.5, 0), col, "body", "Hair"), si * 2.5, V(0, -segLen * 0.5, 0))
				cf = cf * C(0, segLen, 0)
			end
		end
	end

	-- Arms: long bony arms, two forearm bones, knobbly joints ------------------
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local ua, la, hand = side .. "UpperArm", side .. "LowerArm", side .. "Hand"
		bar(ua, V(0, -0.2, 0), V(0, -3.4, 0), 0.74, "kBody", "Humerus")
		B(ua, V(0.78, 0.7, 0.78), C(0, -0.35, 0), "kBody", "ShoulderKnob")
		B(ua, V(0.72, 0.6, 0.66), C(0, -3.35, 0), "kBodyShade", "Condyle")
		B(la, V(0.85, 0.85, 0.85), C(0, 0, 0), "kBody", "Elbow")
		E(la, V(0.4, 0.6, 0.5), C(0, 0.05, 0.36), "kBodyShade", "Olecranon")
		bar(la, V(sx * 0.16, -0.3, -0.05), V(sx * 0.12, -3.3, -0.08), 0.46, "kBody", "Radius")
		bar(la, V(-sx * 0.14, -0.3, 0.08), V(-sx * 0.1, -3.3, 0.06), 0.38, "kBodyShade", "Ulna")
		E(la, V(0.72, 0.12, 0.74), C(0, -2.6, 0) * R(18, 0, 0), "kStripe", "ForearmLine")
		B(la, V(0.62, 0.55, 0.6), C(0, -3.45, 0), "kBody", "Wrist")
		-- the hand: palm, metacarpal ridges, knuckles, long fingers, claws
		E(hand, V(1.25, 1.1, 0.46), C(0, -0.55, 0), "kBody", "Palm")
		for fi = 0, 3 do
			local fx = (fi - 1.5) * 0.25
			bar(hand, V(fx * 0.6, -0.1, 0.18), V(fx, -0.9, 0.16), 0.12, "kBodyShade", "Metacarpal")
			B(hand, V(0.26, 0.24, 0.26), C(fx, -0.95, 0), "kBody", "Knuckle")
			local cf = C(fx, -0.95, 0) * R(-8, 0, (fi - 1.5) * -6)
			local lens = { 1.15, 1.0, 0.85 }
			for si, len in lens do
				E(hand, V(0.17, len + 0.08, 0.17), cf * C(0, -len / 2, 0), "kBody", "Finger")
				B(hand, V(0.22, 0.2, 0.22), cf, "kBodyShade", "Joint")
				cf = cf * C(0, -len, 0) * R(-16, 0, 0)
				if si == #lens then
					k.add(hand, "Wedge", V(0.13, 0.62, 0.22), cf * R(180, 0, 0) * C(0, 0.1, 0) * R(-12, 0, 0), "kStripe", "body", "Claw")
				end
			end
		end
		local tcf = C(sx * -0.5, -0.55, -0.15) * R(-15, 0, sx * -40)
		for si, len in { 0.8, 0.65 } do
			E(hand, V(0.2, len + 0.08, 0.2), tcf * C(0, -len / 2, 0), "kBody", "Thumb")
			B(hand, V(0.24, 0.22, 0.24), tcf, "kBodyShade", "Joint")
			tcf = tcf * C(0, -len, 0) * R(-14, 0, 0)
			if si == 2 then
				k.add(hand, "Wedge", V(0.14, 0.52, 0.22), tcf * R(180, 0, 0), "kStripe", "body", "Claw")
			end
		end
	end

	-- Black smoky tail instead of legs: overlapping tapered blobs, a haze of
	-- half-transparent smoke puffs, wisps peeling off and swaying
	local tail = {
		{ bone = "LeftUpperLeg", len = 2.6, w0 = 2.0, w1 = 1.55 },
		{ bone = "LeftLowerLeg", len = 2.4, w0 = 1.55, w1 = 1.05 },
		{ bone = "LeftFoot", len = 2.6, w0 = 1.05, w1 = 0.25 },
	}
	for ti, seg in tail do
		local bone, len, w0, w1 = seg.bone, seg.len, seg.w0, seg.w1
		for j = 0, 3 do
			local f = (j + 0.5) / 4
			local w = w0 + (w1 - w0) * f
			E(bone, V(w, len * 0.6, w * 0.85), C(math.sin(j * 1.9 + ti) * 0.08, -len * f, 0), "kDark", "Tail")
		end
		for j = 0, 2 do
			local p = E(bone, V(w0 * 1.25, len * 0.45, w0 * 1.1), C(math.sin(j * 2.3 + ti) * w0 * 0.3, -len * (0.2 + j * 0.3), math.cos(j * 1.7) * 0.2), "kStripe", "Smoke")
			p.transparency = 0.45
			Builder.flex(p, 4)
		end
		Builder.flex(E(bone, V(0.16, len * 0.8, 0.2), C(w0 * 0.45, -len * 0.55, 0.15) * R(0, 0, 14 + ti * 4), "kStripe", "Wisp"), 10, V(0, len * 0.4, 0))
		Builder.flex(E(bone, V(0.12, len * 0.6, 0.16), C(-w0 * 0.4, -len * 0.6, -0.1) * R(0, 0, -12), "kStripe", "Wisp"), 10, V(0, len * 0.3, 0))
		Builder.flex(E(bone, V(0.1, len * 0.7, 0.14), C(0, -len * 0.5, w0 * 0.4) * R(18, 0, 0), "kStripe", "Wisp"), 12, V(0, len * 0.35, 0))
	end
	return def
end

Rika.poses = {
	-- low and hunched over (shot 1): shoulders up, head hanging forward,
	-- both clawed hands resting on the ice in front, tail lying behind
	crouch = {
		HumanoidRootPart = CFrame.new(0, -1.3, 0),
		LowerTorso = R(-18, 0, 0),
		UpperTorso = R(-36, 0, 0),
		Head = R(-2, 0, 0),
		RightUpperArm = R(55, 0, 14),
		RightLowerArm = R(40, 0, 0),
		RightHand = R(45, 0, 0),
		LeftUpperArm = R(36, 0, -24),
		LeftLowerArm = R(64, 0, 0),
		LeftHand = R(40, 0, 0),
		LeftUpperLeg = R(-5, 0, 10),
		LeftLowerLeg = R(-70, 0, -10),
		LeftFoot = R(-15, 0, -45),
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
	-- floating idle, as in the reference drawing: hunched, one arm reaching
	-- forward, the other bent, the tail curling underneath
	float = {
		HumanoidRootPart = CFrame.new(0, 0.6, 0),
		LowerTorso = R(-10, 0, 0),
		UpperTorso = R(-24, -10, 0),
		Head = R(4, 12, 0),
		RightUpperArm = R(42, 0, 16),
		RightLowerArm = R(28, 0, 0),
		RightHand = R(14, 0, 0),
		LeftUpperArm = R(18, 0, -28),
		LeftLowerArm = R(72, 0, 0),
		LeftHand = R(24, 0, 0),
		LeftUpperLeg = R(18, 0, 10),
		LeftLowerLeg = R(-40, 0, -32),
		LeftFoot = R(-50, 0, -52),
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
