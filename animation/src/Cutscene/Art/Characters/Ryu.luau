--!strict
-- Ryu: big man, black pompadour, a short dark jacket worn open on his bare
-- chest (huge white fur collar, fur on the cuffs and round the hem at the
-- waist), dog tags, narrow black trousers with a burgundy belt. No coat.
-- R15 skeleton, parts built from primitives.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Paint = require(script.Parent.Parent.Parent.Paint)
local FaceRig = require(script.Parent.Parent.Faces.FaceRig)

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
	shoulderX = 1.3, -- broad shoulders (V-shaped torso)
	upperArm = 1.15,
	lowerArm = 1.05,
	upperLeg = 1.3,
	lowerLeg = 1.25,
}

-- bare = true: the coat has slipped down to his waist (part 2, Rika's grab):
-- bare muscular back and arms, the coat and its fur bunched around the hips
function Ryu.build(scene: Builder.Scene, rigName: string, bare: boolean?): Rig.RigDef
	local def = Rig.humanoid(Ryu.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)
	if bare then
		Ryu.buildBare(k)
		Ryu.buildHead(scene, k, rigName)
		return def
	end

	-- Pelvis, belt, coat tails ------------------------------------------------
	-- narrow trousers and a burgundy belt; the jacket stops at the waist
	k.add("LowerTorso", "Block", V(1.44, 0.8, 0.92), C(0, 0.1, 0), "rPants", "cloth", "Pelvis")
	k.add("LowerTorso", "Block", V(1.48, 0.16, 0.96), C(0, 0.44, 0), "rBelt", "cloth", "Belt")

	-- Chest and coat ------------------------------------------------------------
	-- V-shaped torso: broad at the shoulders, narrow at the waist
	k.add("UpperTorso", "Block", V(1.62, 1.62, 1.12), C(0, 0.8, 0), "rCoat", "cloth", "Torso")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.62, 1.66, 1.1), C(sx * 0.9, 0.86, 0.01) * R(0, 0, -sx * 13), "rCoat", "cloth", "TorsoSide")
	end
	k.add("UpperTorso", "Block", V(0.9, 1.4, 0.1), C(0, 0.88, -0.56), "rSkin", "skin", "Chest")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Ellipsoid", V(0.6, 0.42, 0.24), C(sx * 0.21, 1.2, -0.58) * R(0, 0, sx * 8), "rSkin", "skin", "Pec")
		k.add("UpperTorso", "Ellipsoid", V(0.5, 0.05, 0.05), C(sx * 0.21, 1.0, -0.655) * R(0, 0, sx * -6), "rSkinDeep", "skin", "PecLine")
		k.add("UpperTorso", "Block", V(0.66, 1.62, 0.12), C(sx * 0.72, 0.8, -0.6) * R(0, sx * 12, 0), "rCoat", "cloth", "Lapel")
		-- dog tags on a chain
		k.add("UpperTorso", "Block", V(0.13, 0.22, 0.03), C(sx * 0.075, 0.68, -0.66) * R(0, 0, sx * 8), "rTag", "metal", "Tag")
		k.add("UpperTorso", "Block", V(0.03, 0.5, 0.02), C(sx * 0.13, 1.0, -0.66) * R(0, 0, sx * 16), "rTag", "metal", "Chain")
	end
	for i = 0, 2 do
		k.add("UpperTorso", "Block", V(0.38, 0.03, 0.02), C(0, 0.78 - i * 0.2, -0.615), "rSkinDeep", "skin", "Abs")
	end
	k.add("UpperTorso", "Block", V(0.03, 0.62, 0.02), C(0, 0.6, -0.615), "rSkinDeep", "skin", "AbsMid")
	k.add("UpperTorso", "Ellipsoid", V(0.62, 0.55, 0.6), C(0, 1.62, 0), "rSkin", "skin", "Neck")

	-- Fur collar: fluffy ring over the shoulders + a crown of white spikes ------
	Builder.flex(k.add("UpperTorso", "Ellipsoid", V(2.8, 1.35, 1.15), C(0, 1.78, 0.42) * R(-12, 0, 0), "rFur", "fur", "FurBack"), 2)
	for _, sx in { -1, 1 } do
		Builder.flex(k.add("UpperTorso", "Ellipsoid", V(1.45, 1.0, 1.6), C(sx * 1.02, 1.55, 0.05) * R(0, 0, sx * -12), "rFur", "fur", "FurShoulder"), 2)
		k.add("UpperTorso", "Ellipsoid", V(0.5, 1.5, 0.5), C(sx * 0.78, 1.2, -0.5) * R(0, 0, sx * 18), "rFur", "fur", "FurFront")
		Builder.flex(k.add("UpperTorso", "Ellipsoid", V(1.0, 0.7, 1.1), C(sx * 1.38, 1.3, 0.25) * R(0, 0, sx * -30), "rFurShade", "fur", "FurUnder"), 2)
	end
	-- dense spiky fur all around the collar: thin tapered strands pointing
	-- outward and up in three rings (outer longest); the front stays open
	-- so the face shows
	local rings = {
		{ n = 46, rx = 1.32, rz = 0.82, y = 1.74, len0 = 0.8, len1 = 1.45, w = 0.15, lift = 0.9 },
		{ n = 36, rx = 1.1, rz = 0.68, y = 1.86, len0 = 0.6, len1 = 1.05, w = 0.16, lift = 1.3 },
		{ n = 26, rx = 0.86, rz = 0.55, y = 1.98, len0 = 0.42, len1 = 0.7, w = 0.17, lift = 1.8 },
	}
	for ri, rg in rings do
		for i = 0, rg.n - 1 do
			local f = (i + 0.5 * (ri - 1)) / rg.n
			local ang = math.rad(-125 + f * 250)
			local x, z = math.sin(ang) * rg.rx, math.cos(ang) * rg.rz
			local y = rg.y + math.cos(ang) * 0.2 + math.sin(i * 2.7 + ri) * 0.07
			local front = math.clamp((math.abs(math.deg(ang)) - 70) / 55, 0, 1) -- 0 at the back, 1 at the front edge
			local wob = math.sin(i * 1.37 + ri * 2.1)
			local len = (rg.len0 + math.abs(wob) * (rg.len1 - rg.len0)) * (1 - front * 0.4)
			local out = Vector3.new(x * (1 + front * 1.0), rg.lift - front * 0.5 + wob * 0.15, z * 1.1).Unit
			local rotZ = -math.deg(math.atan2(out.X, out.Y))
			local rotX = math.deg(math.atan2(out.Z, out.Y))
			local col = if (i + ri) % 6 == 3 then "rFurShade" else "rFur"
			Builder.flex(k.add("UpperTorso", "Ellipsoid", V(rg.w, len, rg.w * 0.85), C(x, y, z) * R(rotX, wob * 12, rotZ) * C(0, len * 0.42, 0), col, "fur", "FurSpike"), 7 + ri * 1.5, V(0, -len * 0.42, 0))
		end
	end
	-- fur round the jacket's hem at the waist (back and sides, open at the front)
	for i = 0, 17 do
		local ang = math.rad(-140 + i * (280 / 17))
		local x, z = math.sin(ang) * 1.04, math.cos(ang) * 0.6
		local len = 0.34 + math.abs(math.sin(i * 1.9)) * 0.22
		local out = Vector3.new(x, -0.9, z).Unit
		local rotZ = -math.deg(math.atan2(out.X, out.Y))
		local rotX = math.deg(math.atan2(out.Z, out.Y))
		Builder.flex(k.add("UpperTorso", "Ellipsoid", V(0.2, len, 0.17), C(x, 0.06, z) * R(rotX, 0, rotZ) * C(0, len * 0.4, 0), if i % 5 == 2 then "rFurShade" else "rFur", "fur", "FurHem"), 9, V(0, -len * 0.4, 0))
	end
	-- fur lining down the front edges of the coat: thin strands fanning out
	for _, sx in { -1, 1 } do
		for j = 0, 7 do
			local y = 1.42 - j * 0.2
			local len = 0.38 + (j % 3) * 0.1
			Builder.flex(k.add("UpperTorso", "Ellipsoid", V(0.1, len, 0.1), C(sx * (0.64 - j * 0.02), y, -0.64) * R(-14, 0, sx * (62 + (j % 2) * 18)) * C(0, len * 0.4, 0), if j % 3 == 1 then "rFurShade" else "rFur", "fur", "FurTrim"), 7, V(0, -len * 0.4, 0))
		end
	end

	Ryu.buildHead(scene, k, rigName)

	-- Arms --------------------------------------------------------------------
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		k.add(side .. "UpperArm", "Block", V(0.76, 1.3, 0.82), C(0, -0.55, 0), "rCoat", "cloth")
		k.add(side .. "LowerArm", "Block", V(0.7, 1.14, 0.74), C(0, -0.5, 0), "rCoat", "cloth")
		k.add(side .. "LowerArm", "Ellipsoid", V(0.9, 0.3, 0.94), C(0, -1.0, 0), "rFur", "fur", "Cuff")
		local hand = side .. "Hand"
		k.add(hand, "Block", V(0.48, 0.42, 0.24), C(0, -0.22, 0), "rSkin", "skin", "Palm")
		for fi = 0, 3 do
			local fx = (fi - 1.5) * 0.115
			k.add(hand, "Block", V(0.1, 0.36, 0.12), C(fx, -0.58, -0.02) * R(-12, 0, (fi - 1.5) * -4), "rSkin", "skin", "Finger")
		end
		k.add(hand, "Block", V(0.11, 0.3, 0.12), C(sx * -0.26, -0.3, -0.1) * R(-25, 0, sx * -30), "rSkin", "skin", "Thumb")
	end

	-- Legs --------------------------------------------------------------------
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperLeg", "Block", V(0.72, 1.36, 0.76), C(0, -0.62, 0), "rPants", "cloth")
		k.add(side .. "LowerLeg", "Block", V(0.62, 1.3, 0.66), C(0, -0.6, 0), "rPants", "cloth")
		k.add(side .. "Foot", "Block", V(0.66, 0.32, 1.08), C(0, -0.04, -0.18), "rShoe", "cloth")
	end
	return def
end

-- Poses ---------------------------------------------------------------------
function Ryu.buildHead(scene: Builder.Scene, k: Builder.Kit, rigName: string)
	-- Head (face painted on the front) and pompadour --------------------------
	local face = Paint.canvas(4.4, 0, 0)
	FaceRig.ryu(face, scene.style.color)
	Builder.part(scene, rigName, V(1.1, 1.18, 1.1), C(0, 0.72, 0), scene.style.color.rSkin, {
		shape = "Block",
		material = scene.style.material.skin,
		rig = rigName,
		bone = "Head",
		name = "Head",
		gui = { face = "Front", canvas = Vector2.new(440, 472), lightInfluence = scene.style.face.lightInfluence, elems = face.elems },
	})
	k.add("Head", "Block", V(0.98, 0.3, 1.0), C(0, 0.18, -0.02), "rSkin", "skin", "Jaw")
	k.add("Head", "Ellipsoid", V(1.3, 0.78, 1.42), C(0, 1.38, 0.08), "rHair", "hair", "HairTop")
	k.add("Head", "Ellipsoid", V(1.22, 0.88, 1.05), C(0, 1.5, -0.5) * R(25, 0, 0), "rHair", "hair", "Pompadour")
	k.add("Head", "Wedge", V(1.05, 0.5, 0.82), C(0, 1.72, -0.98) * R(-14, 180, 0), "rHair", "hair", "PompTip")
	k.add("Head", "Block", V(1.16, 0.95, 0.24), C(0, 0.98, 0.6), "rHair", "hair", "HairBack")
	for _, sx in { -1, 1 } do
		k.add("Head", "Block", V(0.16, 0.78, 1.0), C(sx * 0.6, 0.98, 0.08), "rHair", "hair", "HairSide")
		k.add("Head", "Block", V(0.1, 0.36, 0.16), C(sx * 0.57, 0.52, -0.12), "rHair", "hair", "Sideburn")
		k.add("Head", "Block", V(0.08, 0.3, 0.2), C(sx * 0.58, 0.7, 0.08), "rSkin", "skin", "Ear")
		k.add("Head", "Ellipsoid", V(0.1, 0.08, 1.0), C(sx * 0.26, 1.86, -0.52) * R(25, 0, 0), "rCoatHi", "hair", "HairShine")
	end
	-- loose strands falling over the forehead
	for _, st in { { -0.22, 12 }, { 0.05, -6 }, { 0.28, -16 } } do
		Builder.flex(k.add("Head", "Wedge", V(0.06, 0.5, 0.12), C(st[1], 1.06, -0.58) * R(0, 0, 180 + st[2]) * R(0, 90, 0), "rHair", "hair", "Strand"), 9, V(0, -0.25, 0))
	end
end

function Ryu.buildBare(k: Builder.Kit)
	-- trousers, belt and the coat bunched around the hips
	k.add("LowerTorso", "Block", V(1.6, 0.8, 0.98), C(0, 0.1, 0), "rPants", "cloth", "Pelvis")
	k.add("LowerTorso", "Block", V(1.64, 0.15, 1.02), C(0, 0.44, 0), "rShoe", "cloth", "Belt")
	k.add("LowerTorso", "Ellipsoid", V(2.3, 0.7, 1.5), C(0, 0.32, 0.08), "rCoat", "cloth", "CoatBunch")
	k.add("LowerTorso", "Ellipsoid", V(2.1, 0.5, 1.4), C(0, 0.62, 0.1), "rFur", "fur", "FurBunch")
	k.add("LowerTorso", "Block", V(1.9, 1.5, 0.2), C(0, -0.45, 0.55) * R(-8, 0, 0), "rCoat", "cloth", "CoatBack")
	for _, sx in { -1, 1 } do
		k.add("LowerTorso", "Block", V(0.2, 1.5, 0.9), C(sx * 1.0, -0.4, 0.05) * R(0, 0, sx * 8), "rCoat", "cloth", "CoatSide")
		k.add("LowerTorso", "Ellipsoid", V(0.5, 0.9, 0.5), C(sx * 1.05, 0.5, 0.3) * R(0, 0, sx * 30), "rFur", "fur", "FurTuft")
	end
	-- bare muscular torso: chest and abs at the front, a broad back
	k.add("UpperTorso", "Block", V(1.5, 1.58, 1.04), C(0, 0.8, 0), "rSkin", "skin", "Torso")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.6, 1.62, 1.0), C(sx * 0.84, 0.86, 0.01) * R(0, 0, -sx * 13), "rSkin", "skin", "TorsoSide")
	end
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Ellipsoid", V(0.95, 0.62, 0.34), C(sx * 0.46, 1.16, -0.48) * R(0, 0, sx * 8), "rSkin", "skin", "Pec")
		k.add("UpperTorso", "Ellipsoid", V(0.8, 0.05, 0.05), C(sx * 0.45, 0.9, -0.64) * R(0, 0, sx * -6), "rSkinDeep", "skin", "PecLine")
		-- back: shoulder blades, lats and the trapezius
		k.add("UpperTorso", "Ellipsoid", V(0.8, 0.9, 0.36), C(sx * 0.48, 1.08, 0.46) * R(0, 0, sx * -10), "rSkin", "skin", "Blade")
		k.add("UpperTorso", "Ellipsoid", V(0.6, 1.2, 0.3), C(sx * 0.7, 0.55, 0.42) * R(0, 0, sx * 12), "rSkin", "skin", "Lat")
		k.add("UpperTorso", "Ellipsoid", V(0.7, 0.05, 0.05), C(sx * 0.5, 0.62, 0.58) * R(0, 0, sx * 30), "rSkinDeep", "skin", "BackLine")
		k.add("UpperTorso", "Ellipsoid", V(0.7, 0.42, 0.5), C(sx * 0.42, 1.55, 0.1) * R(0, 0, sx * -20), "rSkin", "skin", "Trap")
		k.add("UpperTorso", "Block", V(0.13, 0.22, 0.03), C(sx * 0.075, 0.66, -0.56) * R(0, 0, sx * 8), "rTag", "metal", "Tag")
		k.add("UpperTorso", "Block", V(0.03, 0.5, 0.02), C(sx * 0.13, 0.98, -0.6) * R(0, 0, sx * 16), "rTag", "metal", "Chain")
	end
	k.add("UpperTorso", "Block", V(0.05, 1.3, 0.04), C(0, 0.85, 0.54), "rSkinDeep", "skin", "Spine")
	for i = 0, 2 do
		k.add("UpperTorso", "Block", V(0.42, 0.03, 0.02), C(0, 0.72 - i * 0.2, -0.535), "rSkinDeep", "skin", "Abs")
	end
	k.add("UpperTorso", "Block", V(0.03, 0.62, 0.02), C(0, 0.56, -0.535), "rSkinDeep", "skin", "AbsMid")
	k.add("UpperTorso", "Ellipsoid", V(0.62, 0.55, 0.6), C(0, 1.62, 0), "rSkin", "skin", "Neck")
	-- bare arms
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		k.add(side .. "UpperArm", "Ellipsoid", V(0.82, 1.4, 0.86), C(0, -0.52, 0), "rSkin", "skin", "Biceps")
		k.add(side .. "UpperArm", "Ellipsoid", V(0.95, 0.7, 0.95), C(0, -0.05, 0), "rSkin", "skin", "Shoulder")
		k.add(side .. "LowerArm", "Ellipsoid", V(0.7, 1.2, 0.72), C(0, -0.48, 0), "rSkin", "skin", "Forearm")
		local hand = side .. "Hand"
		k.add(hand, "Block", V(0.48, 0.42, 0.24), C(0, -0.22, 0), "rSkin", "skin", "Palm")
		for fi = 0, 3 do
			local fx = (fi - 1.5) * 0.115
			k.add(hand, "Block", V(0.1, 0.36, 0.12), C(fx, -0.58, -0.02) * R(-12, 0, (fi - 1.5) * -4), "rSkin", "skin", "Finger")
		end
		k.add(hand, "Block", V(0.11, 0.3, 0.12), C(sx * -0.26, -0.3, -0.1) * R(-25, 0, sx * -30), "rSkin", "skin", "Thumb")
	end
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperLeg", "Block", V(0.8, 1.36, 0.84), C(0, -0.62, 0), "rPants", "cloth")
		k.add(side .. "LowerLeg", "Block", V(0.72, 1.3, 0.76), C(0, -0.6, 0), "rPants", "cloth")
		k.add(side .. "Foot", "Block", V(0.74, 0.32, 1.12), C(0, -0.04, -0.18), "rShoe", "cloth")
	end
end

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
