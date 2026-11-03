--!strict
-- Ryu: big man, black pompadour, long dark coat with a huge white fur collar,
-- open chest with dog tags. R15 skeleton, parts built from primitives.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)

local R = Rig.R
local V = Vector3.new
local C = CFrame.new

local Ryu = {}

Ryu.dims = {
	hip = 2.75,
	hipX = 0.5,
	waist = 0.55,
	neck = 1.6,
	shoulderY = 1.42,
	shoulderX = 1.18,
	upperArm = 1.15,
	lowerArm = 1.05,
	upperLeg = 1.3,
	lowerLeg = 1.25,
}

function Ryu.build(scene: Builder.Scene, rigName: string): Rig.RigDef
	local def = Rig.humanoid(Ryu.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)

	-- Pelvis, belt, coat tails ------------------------------------------------
	k.add("LowerTorso", "Block", V(1.9, 0.75, 1.05), C(0, 0.12, 0), "rPants", "cloth")
	k.add("LowerTorso", "Block", V(1.96, 0.18, 1.1), C(0, 0.46, 0), "rShoe", "cloth", "Belt")
	k.add("LowerTorso", "Block", V(2.15, 1.75, 0.22), C(0, -0.5, 0.52) * R(-6, 0, 0), "rCoat", "cloth", "CoatBack")
	for _, sx in { -1, 1 } do
		k.add("LowerTorso", "Block", V(0.22, 1.7, 1.12), C(sx * 1.02, -0.46, 0.0) * R(0, 0, sx * 5), "rCoat", "cloth", "CoatSide")
		k.add("LowerTorso", "Block", V(0.82, 1.62, 0.2), C(sx * 0.6, -0.42, -0.55) * R(4, sx * 14, sx * 3), "rCoat", "cloth", "CoatFront")
	end

	-- Chest and coat ------------------------------------------------------------
	k.add("UpperTorso", "Block", V(2.05, 1.62, 1.15), C(0, 0.8, 0), "rCoat", "cloth", "Torso")
	k.add("UpperTorso", "Block", V(0.8, 1.35, 0.1), C(0, 0.9, -0.57), "skin", "skin", "Chest")
	k.add("UpperTorso", "Block", V(0.05, 0.55, 0.02), C(0, 0.55, -0.625), "skinShade", "skin", "Abs")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.66, 1.62, 0.12), C(sx * 0.7, 0.8, -0.6) * R(0, sx * 12, 0), "rCoat", "cloth", "Lapel")
		-- dog tags
		k.add("UpperTorso", "Block", V(0.13, 0.21, 0.03), C(sx * 0.07, 0.72, -0.64) * R(0, 0, sx * 8), "rTag", "metal", "Tag")
	end
	k.add("UpperTorso", "Block", V(0.03, 0.42, 0.02), C(-0.12, 0.98, -0.635) * R(0, 0, -16), "rTag", "metal", "Chain")
	k.add("UpperTorso", "Block", V(0.03, 0.42, 0.02), C(0.12, 0.98, -0.635) * R(0, 0, 16), "rTag", "metal", "Chain")
	k.add("UpperTorso", "Block", V(0.5, 0.4, 0.5), C(0, 1.66, 0), "skin", "skin", "Neck")

	-- Fur collar: big fluffy ring over the shoulders plus spiky tufts ---------
	k.add("UpperTorso", "Ellipsoid", V(2.7, 1.25, 1.05), C(0, 1.78, 0.42) * R(-12, 0, 0), "rFur", "fur", "FurBack")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Ellipsoid", V(1.35, 0.95, 1.55), C(sx * 1.02, 1.55, 0.05) * R(0, 0, sx * -12), "rFur", "fur", "FurShoulder")
		k.add("UpperTorso", "Ellipsoid", V(0.6, 1.5, 0.55), C(sx * 0.52, 1.2, -0.55) * R(0, 0, sx * 28), "rFur", "fur", "FurFront")
		k.add("UpperTorso", "Ellipsoid", V(1.0, 0.7, 1.1), C(sx * 1.35, 1.3, 0.25) * R(0, 0, sx * -30), "rFurShade", "fur", "FurUnder")
	end
	-- spiky tufts radiating from the collar
	local tufts = {
		-- {x, y, z, rotX, rotY, rotZ, length}
		{ -1.55, 1.75, 0.0, 0, 0, 62, 0.9 },
		{ 1.55, 1.75, 0.0, 0, 0, -62, 0.9 },
		{ -1.25, 2.05, 0.35, -20, 0, 35, 0.85 },
		{ 1.25, 2.05, 0.35, -20, 0, -35, 0.85 },
		{ -0.7, 2.25, 0.55, -30, 0, 18, 0.8 },
		{ 0.7, 2.25, 0.55, -30, 0, -18, 0.8 },
		{ 0.0, 2.3, 0.7, -35, 0, 0, 0.75 },
		{ -1.7, 1.35, 0.3, 0, 0, 85, 0.7 },
		{ 1.7, 1.35, 0.3, 0, 0, -85, 0.7 },
		{ -0.9, 1.15, -0.75, 70, 0, 25, 0.6 },
		{ 0.9, 1.15, -0.75, 70, 0, -25, 0.6 },
	}
	for i, t in tufts do
		local len = t[7]
		k.add(
			"UpperTorso",
			"Wedge",
			V(0.42, len, 0.42),
			C(t[1], t[2], t[3]) * R(t[4], t[5], t[6]) * C(0, len / 2, 0),
			if i % 3 == 0 then "rFurShade" else "rFur",
			"fur",
			"FurTuft"
		)
	end

	-- Head and pompadour --------------------------------------------------------
	k.add("Head", "Block", V(1.1, 1.18, 1.1), C(0, 0.72, 0), "skin", "skin", "Head")
	k.add("Head", "Block", V(0.98, 0.3, 1.0), C(0, 0.2, -0.03), "skin", "skin", "Jaw")
	k.add("Head", "Ellipsoid", V(1.24, 0.72, 1.32), C(0, 1.36, 0.06), "rHair", "hair", "HairTop")
	k.add("Head", "Ellipsoid", V(1.16, 0.72, 0.95), C(0, 1.42, -0.48) * R(22, 0, 0), "rHair", "hair", "Pompadour")
	k.add("Head", "Wedge", V(0.95, 0.42, 0.7), C(0, 1.6, -0.92) * R(-18, 180, 0), "rHair", "hair", "PompTip")
	k.add("Head", "Block", V(1.14, 0.88, 0.22), C(0, 0.95, 0.58), "rHair", "hair", "HairBack")
	for _, sx in { -1, 1 } do
		k.add("Head", "Block", V(0.16, 0.72, 0.95), C(sx * 0.6, 0.98, 0.08), "rHair", "hair", "HairSide")
		k.add("Head", "Block", V(0.1, 0.34, 0.16), C(sx * 0.57, 0.55, -0.12), "rHair", "hair", "Sideburn")
		-- tiny face marks (read as eyes/brows from afar)
		k.add("Head", "Block", V(0.36, 0.08, 0.03), C(sx * 0.25, 0.86, -0.56) * R(0, 0, sx * -12), "rHair", "hair", "Brow")
		k.add("Head", "Block", V(0.2, 0.06, 0.03), C(sx * 0.25, 0.73, -0.56), "line", "hair", "Eye")
	end

	-- Arms --------------------------------------------------------------------
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		k.add(side .. "UpperArm", "Block", V(0.74, 1.28, 0.8), C(0, -0.55, 0), "rCoat", "cloth")
		k.add(side .. "LowerArm", "Block", V(0.68, 1.12, 0.72), C(0, -0.5, 0), "rCoat", "cloth")
		k.add(side .. "LowerArm", "Ellipsoid", V(0.86, 0.26, 0.9), C(0, -1.0, 0), "rFur", "fur", "Cuff")
		k.add(side .. "Hand", "Block", V(0.48, 0.48, 0.42), C(0, -0.26, 0), "skin", "skin")
		if side == "Right" then
			-- pointing index finger + thumb
			k.add(side .. "Hand", "Block", V(0.12, 0.42, 0.12), C(-0.1 * sx, -0.66, -0.12), "skin", "skin", "Finger")
			k.add(side .. "Hand", "Block", V(0.12, 0.26, 0.12), C(0.2 * sx, -0.3, -0.2) * R(-30, 0, 0), "skin", "skin", "Thumb")
		end
	end

	-- Legs --------------------------------------------------------------------
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperLeg", "Block", V(0.8, 1.36, 0.84), C(0, -0.62, 0), "rPants", "cloth")
		k.add(side .. "LowerLeg", "Block", V(0.72, 1.3, 0.76), C(0, -0.6, 0), "rPants", "cloth")
		k.add(side .. "Foot", "Block", V(0.74, 0.32, 1.12), C(0, -0.04, -0.18), "rShoe", "cloth")
	end
	return def
end

-- Poses ---------------------------------------------------------------------
Ryu.poses = {
	-- standing in profile, right arm straight out, finger pointing at the enemy
	point = {
		LowerTorso = R(0, 8, 0),
		UpperTorso = R(2, -14, 0),
		Head = R(0, 6, 0),
		RightUpperArm = R(90, 0, -4),
		RightLowerArm = R(4, 0, 0),
		RightHand = R(0, 0, 0),
		LeftUpperArm = R(-6, 0, -7),
		LeftLowerArm = R(14, 0, 0),
		LeftUpperLeg = R(-8, 0, -3),
		LeftLowerLeg = R(4, 0, 0),
		LeftFoot = R(4, 0, 0),
		RightUpperLeg = R(9, 0, 3),
		RightLowerLeg = R(2, 0, 0),
		RightFoot = R(-11, 0, 0),
	} :: Rig.Pose,
}

return Ryu
