--!strict
-- Rika: Yuta's giant white curse. Hunched body, long arms with claw fingers,
-- wide toothy mouth and a crown of dark spikes. Same R15 topology, giant scale.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)

local R = Rig.R
local V = Vector3.new
local C = CFrame.new

local Rika = {}

Rika.dims = {
	hip = 4.4,
	hipX = 1.05,
	waist = 1.1,
	neck = 3.6,
	shoulderY = 3.0,
	shoulderX = 2.3,
	upperArm = 3.0,
	lowerArm = 2.9,
	upperLeg = 2.2,
	lowerLeg = 2.0,
}

function Rika.build(scene: Builder.Scene, rigName: string): Rig.RigDef
	local def = Rig.humanoid(Rika.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)

	-- Body ----------------------------------------------------------------------
	k.add("LowerTorso", "Ellipsoid", V(3.1, 2.0, 2.5), C(0, 0.25, 0.1), "kBody", "body", "Hips")
	k.add("UpperTorso", "Ellipsoid", V(4.3, 3.8, 3.1), C(0, 1.75, 0.25), "kBody", "body", "Chest")
	k.add("UpperTorso", "Ellipsoid", V(3.6, 2.8, 2.6), C(0, 2.6, 0.95), "kBody", "body", "Hump")
	k.add("UpperTorso", "Ellipsoid", V(2.6, 2.2, 1.4), C(0, 1.3, -1.0), "kBodyShade", "body", "Belly")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Ellipsoid", V(2.0, 2.0, 2.0), C(sx * 2.1, 2.9, 0.1), "kBody", "body", "Shoulder")
		-- dark tendril markings over the shoulders
		k.add("UpperTorso", "Block", V(0.16, 1.9, 0.14), C(sx * 1.6, 2.6, -0.95) * R(0, 0, sx * 25), "kDark", "body", "Mark")
		k.add("UpperTorso", "Block", V(0.14, 1.4, 0.14), C(sx * 2.45, 2.2, -0.6) * R(0, 0, sx * -15), "kDark", "body", "Mark")
	end
	k.add("UpperTorso", "Block", V(1.5, 1.4, 1.5), C(0, 3.55, -0.2), "kBody", "body", "Neck")

	-- Head ----------------------------------------------------------------------
	k.add("Head", "Block", V(2.7, 2.5, 2.6), C(0, 1.45, -0.3), "kBody", "body", "Skull")
	k.add("Head", "Block", V(2.4, 1.0, 2.3), C(0, 0.4, -0.5), "kBody", "body", "Jaw")
	k.add("Head", "Block", V(2.1, 0.95, 0.12), C(0, 0.8, -1.66), "kMouth", "body", "Mouth")
	k.add("Head", "Block", V(2.0, 0.22, 0.14), C(0, 1.14, -1.69), "kTeeth", "body", "TeethTop")
	k.add("Head", "Block", V(1.9, 0.22, 0.14), C(0, 0.47, -1.69), "kTeeth", "body", "TeethBottom")
	for i = -3, 3 do
		k.add("Head", "Block", V(0.06, 0.85, 0.15), C(i * 0.28, 0.8, -1.7), "kMouth", "body", "ToothGap")
	end
	for _, sx in { -1, 1 } do
		k.add("Head", "Ellipsoid", V(0.7, 0.42, 0.14), C(sx * 0.68, 2.0, -1.62) * R(0, 0, sx * -14), "kDark", "body", "Eye")
	end
	-- mane: spikes fanning from the forehead over the crown to the nape,
	-- white with dark ones mixed in (reads as the spiky crown in the wide shot)
	local n = 15
	for i = 0, n - 1 do
		local f = i / (n - 1)
		local pitch = -20 + f * 165 -- up and slightly forward ... back and down
		local roll = math.sin(i * 2.4) * 24
		local len = 2.4 + math.sin(f * math.pi) * 1.4
		local base = C(math.sin(i * 1.7) * 0.7, 2.25 - f * 0.4, -0.9 + f * 1.9) * R(pitch, 0, roll)
		local dark = i % 3 ~= 1
		k.add("Head", "Wedge", V(0.34, len, 0.58), base * C(0, len / 2, 0), if dark then "kDark" else "kBody", "body", "Spike")
		if i % 2 == 0 then
			k.add("Head", "Ellipsoid", V(0.7, 1.0, 0.7), base * C(0, 0.35, 0), "kBody", "body", "SpikeRoot")
		end
	end

	-- Arms: long, thin, big hands with claw fingers ------------------------------
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperArm", "Ellipsoid", V(1.35, 3.3, 1.35), C(0, -1.45, 0), "kBody", "body")
		k.add(side .. "LowerArm", "Ellipsoid", V(1.1, 3.1, 1.1), C(0, -1.4, 0), "kBody", "body")
		k.add(side .. "LowerArm", "Block", V(0.12, 1.6, 0.1), C(0, -1.3, -0.55), "kDark", "body", "Mark")
		k.add(side .. "Hand", "Block", V(1.15, 0.95, 0.55), C(0, -0.45, 0), "kBody", "body", "Palm")
		for f = -1.5, 1.5 do
			k.add(side .. "Hand", "Block", V(0.2, 1.45, 0.22), C(f * 0.3, -1.55, -0.05) * R(-8, 0, f * 6), "kBody", "body", "Claw")
			k.add(side .. "Hand", "Wedge", V(0.2, 0.45, 0.24), C(f * 0.3 - f * 0.12, -2.45, -0.15) * R(180, 0, f * 6), "kDark", "body", "ClawTip")
		end
	end
	-- Legs
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperLeg", "Ellipsoid", V(1.75, 2.7, 1.85), C(0, -1.0, 0), "kBody", "body")
		k.add(side .. "LowerLeg", "Ellipsoid", V(1.25, 2.5, 1.35), C(0, -1.0, 0), "kBody", "body")
		k.add(side .. "Foot", "Block", V(1.2, 0.5, 1.9), C(0, -0.15, -0.4), "kBody", "body")
	end
	return def
end

Rika.poses = {
	-- hunched forward, near (left) arm reaching down to the ground
	crouch = {
		HumanoidRootPart = CFrame.new(0, -1.55, 0),
		LowerTorso = R(-18, 0, 0),
		UpperTorso = R(-26, 6, 0),
		Head = R(26, -6, 4),
		LeftUpperArm = R(40, 0, -8),
		LeftLowerArm = R(12, 0, 0),
		LeftHand = R(22, 0, 0),
		RightUpperArm = R(24, 0, 24),
		RightLowerArm = R(62, 0, 0),
		RightHand = R(10, 0, 0),
		LeftUpperLeg = R(48, 0, -10),
		LeftLowerLeg = R(-70, 0, 0),
		LeftFoot = R(40, 0, 0),
		RightUpperLeg = R(62, 0, 12),
		RightLowerLeg = R(-88, 0, 0),
		RightFoot = R(44, 0, 0),
	} :: Rig.Pose,
}

return Rika
