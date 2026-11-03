--!strict
-- Yuta: slim, dark spiky hair with a split fringe, a loose white jacket that
-- ends at the hips (sleeves rolled up to the elbows, blood on the left
-- shoulder and the belly), dark navy trousers, white sneakers, a silver ring
-- on the left ring finger. No coat, no sword. R15 skeleton.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)
local Paint = require(script.Parent.Parent.Parent.Paint)
local FaceRig = require(script.Parent.Parent.Faces.FaceRig)

local R = Rig.R
local V = Vector3.new
local C = CFrame.new

local Yuta = {}

Yuta.dims = {
	hip = 2.45,
	hipX = 0.42,
	waist = 0.5,
	neck = 1.38,
	shoulderY = 1.22,
	shoulderX = 1.0, -- broad shoulders (V-shaped torso)
	upperArm = 1.02,
	lowerArm = 0.92,
	upperLeg = 1.15,
	lowerLeg = 1.12,
}

function Yuta.build(scene: Builder.Scene, rigName: string): Rig.RigDef
	local def = Rig.humanoid(Yuta.dims)
	Builder.rig(scene, rigName, def, rigName)
	Builder.model(scene, rigName, scene.style.outline ~= nil)
	local k = Builder.kit(scene, rigName, rigName)

	-- Hips: trousers, and the jacket's hem just over the hips
	k.add("LowerTorso", "Block", V(1.34, 0.7, 0.82), C(0, 0.12, 0), "yPants", "cloth")
	k.add("LowerTorso", "Block", V(1.46, 0.42, 0.92), C(0, 0.3, 0), "yUniform", "cloth", "Hem")
	k.add("LowerTorso", "Ellipsoid", V(0.5, 0.36, 0.1), C(-0.32, 0.3, -0.49) * R(0, 0, 12), "yBlood", "cloth", "BloodHem")

	-- Jacket, high collar, katana on the back
	-- V-shaped torso: broad at the shoulders, narrow at the waist
	k.add("UpperTorso", "Block", V(1.3, 1.44, 0.93), C(0, 0.72, 0), "yUniform", "cloth", "Torso")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.5, 1.46, 0.9), C(sx * 0.72, 0.77, 0.01) * R(0, 0, -sx * 12), "yUniform", "cloth", "TorsoSide")
	end
	k.add("UpperTorso", "Block", V(0.06, 1.3, 0.02), C(-0.12, 0.7, -0.48), "yUniformShade", "cloth", "Placket")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.66, 0.4, 0.96), C(sx * 0.84, 1.32, 0) * R(0, 0, sx * -10), "yUniform", "cloth", "Shoulder")
	end
	-- blood soaked into the left shoulder, running down the chest, and on the belly
	k.add("UpperTorso", "Ellipsoid", V(0.75, 0.8, 1.02), C(-0.55, 1.2, -0.05) * R(0, 0, -20), "yBlood", "cloth", "Blood")
	k.add("UpperTorso", "Ellipsoid", V(0.35, 0.6, 0.12), C(-0.3, 0.9, -0.48) * R(0, 0, 15), "yBloodDark", "cloth", "BloodDrip")
	k.add("UpperTorso", "Ellipsoid", V(0.7, 0.5, 0.12), C(-0.15, 0.2, -0.48) * R(0, 0, -10), "yBlood", "cloth", "BloodBelly")
	k.add("UpperTorso", "Ellipsoid", V(0.3, 0.24, 0.1), C(0.25, 0.32, -0.49), "yBloodDark", "cloth", "BloodBelly")
	-- tall rounded collar of the jujutsu uniform, opened a little at the front
	for i = 0, 7 do
		local a = math.rad(-150 + i * (300 / 7))
		k.add("UpperTorso", "Block", V(0.36, 0.62, 0.12), C(math.sin(a) * 0.5, 1.62, math.cos(a) * 0.48) * R(0, math.deg(a), 0) * R(-8, 0, 0), "yUniform", "cloth", "CollarPanel")
	end
	k.add("UpperTorso", "Block", V(0.12, 0.12, 0.05), C(0.12, 1.45, -0.5), "rTag", "metal", "Button")

	-- Head (face painted on the front) and hair
	local face = Paint.canvas(4.0, 0, 0)
	FaceRig.yuta(face, scene.style.color)
	Builder.part(scene, rigName, V(1.0, 1.08, 1.0), C(0, 0.64, 0), scene.style.color.skin, {
		shape = "Block",
		material = scene.style.material.skin,
		rig = rigName,
		bone = "Head",
		name = "Head",
		gui = { face = "Front", canvas = Vector2.new(400, 432), lightInfluence = scene.style.face.lightInfluence, elems = face.elems },
	})
	k.add("Head", "Block", V(0.86, 0.26, 0.9), C(0, 0.1, -0.02), "skin", "skin", "Jaw")
	-- Hair: dark, messy and spiky like the reference. A rounded mass over the
	-- skull, then many thin tapered locks: bangs falling over the forehead
	-- (one between the eyes), locks over the temples and ears, a shaggy nape
	-- and a few spiky ends sticking out at the crown and back.
	k.add("Head", "Ellipsoid", V(1.2, 0.74, 1.26), C(0, 1.16, 0.05), "yHair", "hair", "HairTop")
	k.add("Head", "Ellipsoid", V(1.16, 1.0, 0.62), C(0, 0.86, 0.36), "yHair", "hair", "HairBack")
	for _, sx in { -1, 1 } do
		k.add("Head", "Ellipsoid", V(0.24, 0.8, 0.8), C(sx * 0.54, 0.86, 0.08), "yHair", "hair", "HairSide")
		k.add("Head", "Block", V(0.08, 0.26, 0.18), C(sx * 0.53, 0.58, 0.08), "skin", "skin", "Ear")
	end
	local function lock(x: number, y: number, z: number, pitch: number, roll: number, yaw: number, len: number, w: number, col: string, name: string)
		-- hangs along -Y from (x, y, z); pitch > 0 swings the tip forward
		k.add("Head", "Ellipsoid", V(w, len, w * 0.8), C(x, y, z) * R(pitch, yaw, roll) * C(0, -len * 0.45, 0), col, "hair", name)
	end
	-- bangs over the forehead: pointed locks (wedge triangles turned to face
	-- forward, tip down) ending above the painted brows, one longer lock
	-- between the eyes; alternate sides of the right angle make them jagged
	local bangs = {
		-- x, top y, z, length, width, roll
		{ -0.4, 1.16, -0.47, 0.34, 0.26, -14 },
		{ -0.22, 1.18, -0.51, 0.4, 0.24, -6 },
		{ -0.04, 1.18, -0.53, 0.52, 0.2, 2 },
		{ 0.13, 1.18, -0.52, 0.38, 0.24, 8 },
		{ 0.3, 1.17, -0.49, 0.36, 0.24, 14 },
		{ 0.45, 1.13, -0.42, 0.3, 0.2, 24 },
	}
	for i, b in bangs do
		local turn = if i % 2 == 0 then 90 else -90
		k.add("Head", "Wedge", V(0.06, b[4], b[5]), C(b[1], b[2], b[3]) * R(8, 0, b[6]) * C(0, -b[4] / 2, 0) * R(0, 0, 180) * R(0, turn, 0), if i == 3 then "yHairHi" else "yHair", "hair", "Bang")
	end
	-- locks over the temples and ears
	for _, sx in { -1, 1 } do
		lock(sx * 0.52, 1.02, -0.22, 8, sx * -10, 0, 0.62, 0.17, "yHair", "SideLock")
		lock(sx * 0.56, 0.98, 0.06, 2, sx * -14, 0, 0.66, 0.18, "yHair", "SideLock")
		lock(sx * 0.5, 0.96, 0.32, -10, sx * -18, 0, 0.58, 0.18, "yHair", "SideLock")
	end
	-- shaggy nape
	for i = 0, 5 do
		local x = -0.4 + i * 0.16
		lock(x, 0.86, 0.5, -22 - (i % 2) * 8, x * -30, 0, 0.5 + (i % 3) * 0.08, 0.18, "yHair", "NapeLock")
	end
	-- spiky ends at the crown and the back of the head
	local spikes = {
		{ -0.34, 1.42, 0.12, -150, 30, 0.5 },
		{ -0.12, 1.5, 0.2, -160, 12, 0.56 },
		{ 0.12, 1.5, 0.18, -158, -10, 0.54 },
		{ 0.34, 1.42, 0.1, -148, -28, 0.48 },
		{ -0.24, 1.36, 0.42, -130, 22, 0.5 },
		{ 0.22, 1.38, 0.44, -128, -20, 0.5 },
		{ 0, 1.3, 0.56, -112, 0, 0.48 },
		{ -0.46, 1.22, 0.36, -120, 48, 0.42 },
		{ 0.46, 1.22, 0.34, -122, -46, 0.42 },
	}
	for i, sp in spikes do
		lock(sp[1], sp[2], sp[3], sp[4], sp[5], 0, sp[6] * 1.15, 0.15, if i % 4 == 1 then "yHairHi" else "yHair", "Spike")
	end

	-- Arms
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperArm", "Block", V(0.56, 1.1, 0.6), C(0, -0.48, 0), "yUniform", "cloth")
		-- sleeves rolled up to the elbows: a thick roll of cloth, bare forearms
		k.add(side .. "LowerArm", "Ellipsoid", V(0.62, 0.32, 0.66), C(0, -0.04, 0), "yUniform", "cloth", "SleeveRoll")
		k.add(side .. "LowerArm", "Block", V(0.4, 0.96, 0.42), C(0, -0.48, 0), "skin", "skin", "Forearm")
		k.add(side .. "Hand", "Block", V(0.4, 0.36, 0.22), C(0, -0.2, 0), "skin", "skin", "Palm")
		for fi = 0, 3 do
			k.add(side .. "Hand", "Block", V(0.085, 0.3, 0.1), C((fi - 1.5) * 0.095, -0.5, -0.01) * R(-10, 0, 0), "skin", "skin", "Finger")
		end
		if side == "Left" then
			-- silver ring on the ring finger
			k.add(side .. "Hand", "Block", V(0.11, 0.06, 0.13), C(-0.5 * 0.095, -0.46, -0.01) * R(-10, 0, 0), "rTag", "metal", "Ring")
		end
	end
	-- Legs
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperLeg", "Block", V(0.62, 1.2, 0.66), C(0, -0.56, 0), "yPants", "cloth")
		k.add(side .. "LowerLeg", "Block", V(0.56, 1.16, 0.6), C(0, -0.55, 0), "yPants", "cloth")
		k.add(side .. "Foot", "Block", V(0.58, 0.28, 0.98), C(0, -0.04, -0.16), "yShoe", "cloth", "Shoe")
		k.add(side .. "Foot", "Block", V(0.6, 0.08, 1.0), C(0, -0.16, -0.16), "yShoeSole", "cloth", "Sole")
	end
	return def
end

Yuta.poses = {
	-- calm stance, arms loose
	stand = {
		LowerTorso = R(0, -6, 0),
		UpperTorso = R(3, 8, 0),
		Head = R(-4, 4, 0),
		LeftUpperArm = R(4, 0, -8),
		LeftLowerArm = R(16, 0, 0),
		RightUpperArm = R(-4, 0, 9),
		RightLowerArm = R(12, 0, 0),
		LeftUpperLeg = R(-6, 0, -4),
		LeftFoot = R(6, 0, 0),
		RightUpperLeg = R(6, 0, 4),
		RightLowerLeg = R(4, 0, 0),
		RightFoot = R(-10, 0, 0),
	} :: Rig.Pose,
}

return Yuta
