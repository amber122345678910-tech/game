--!strict
-- Yuta: slim, dark spiky hair with bangs, white high-collar uniform, katana
-- in a dark sheath across the back. R15 skeleton.
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
	shoulderX = 0.92,
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

	-- Hips and jacket hem
	k.add("LowerTorso", "Block", V(1.5, 0.7, 0.88), C(0, 0.12, 0), "yPants", "cloth")
	k.add("LowerTorso", "Block", V(1.56, 0.14, 0.92), C(0, 0.42, 0), "ySheath", "cloth", "Belt")
	k.add("LowerTorso", "Block", V(1.66, 1.25, 0.2), C(0, -0.3, 0.44) * R(-5, 0, 0), "yUniform", "cloth", "HemBack")
	for _, sx in { -1, 1 } do
		k.add("LowerTorso", "Block", V(0.2, 1.2, 0.95), C(sx * 0.8, -0.28, 0) * R(0, 0, sx * 4), "yUniform", "cloth", "HemSide")
		k.add("LowerTorso", "Block", V(0.74, 1.18, 0.18), C(sx * 0.4, -0.26, -0.46) * R(3, sx * 4, 0), "yUniform", "cloth", "HemFront")
	end

	-- Jacket, high collar, katana on the back
	k.add("UpperTorso", "Block", V(1.66, 1.44, 0.95), C(0, 0.72, 0), "yUniform", "cloth", "Torso")
	k.add("UpperTorso", "Block", V(0.06, 1.3, 0.02), C(-0.12, 0.7, -0.48), "yUniformShade", "cloth", "Placket")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.62, 0.4, 0.98), C(sx * 0.72, 1.3, 0) * R(0, 0, sx * -10), "yUniform", "cloth", "Shoulder")
	end
	-- katana across the back: sheath from the right hip up to the left shoulder
	local back = C(0, 0.72, 0.6) * R(0, 0, 38)
	k.add("UpperTorso", "Block", V(0.17, 3.2, 0.17), back, "ySheath", "metal", "Sheath")
	k.add("UpperTorso", "Block", V(0.4, 0.07, 0.4), back * C(0, 1.62, 0), "rTag", "metal", "Guard")
	k.add("UpperTorso", "Block", V(0.13, 0.9, 0.13), back * C(0, 2.1, 0), "yHair", "metal", "Hilt")

	-- blood soaked into the right shoulder and chest
	k.add("UpperTorso", "Ellipsoid", V(0.75, 0.8, 1.02), C(0.55, 1.2, -0.05) * R(0, 0, 20), "yBlood", "cloth", "Blood")
	k.add("UpperTorso", "Ellipsoid", V(0.35, 0.6, 0.12), C(0.3, 0.9, -0.48) * R(0, 0, -15), "yBloodDark", "cloth", "BloodDrip")
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
	k.add("Head", "Ellipsoid", V(1.18, 0.66, 1.22), C(0, 1.18, 0.04), "yHair", "hair", "HairTop")
	k.add("Head", "Block", V(1.08, 0.92, 0.28), C(0, 0.86, 0.5), "yHair", "hair", "HairBack")
	for _, sx in { -1, 1 } do
		k.add("Head", "Block", V(0.16, 0.86, 0.74), C(sx * 0.55, 0.8, 0.06), "yHair", "hair", "HairSide")
		k.add("Head", "Block", V(0.08, 0.28, 0.18), C(sx * 0.53, 0.62, 0.06), "skin", "skin", "Ear")
	end
	-- bangs: thin wedges hanging over the forehead (above the painted brows)
	local bangs = { { -0.36, 14, 0.5 }, { -0.16, -6, 0.58 }, { 0.06, 8, 0.52 }, { 0.26, -12, 0.56 }, { 0.42, 18, 0.42 } }
	for _, b in bangs do
		k.add("Head", "Wedge", V(0.1, b[3], 0.22), C(b[1], 1.0, -0.53) * R(0, 0, 180 + b[2]) * R(0, 90, 0), "yHair", "hair", "Bang")
	end
	-- spikes on top / back
	local spikes = { { -0.4, 1.35, 0.25, -40, 0, 30 }, { 0.35, 1.38, 0.3, -45, 0, -28 }, { 0, 1.4, 0.45, -60, 0, 0 }, { -0.2, 1.3, 0.55, -80, 0, 15 } }
	for _, sp in spikes do
		k.add("Head", "Wedge", V(0.34, 0.6, 0.3), C(sp[1], sp[2], sp[3]) * R(sp[4], sp[5], sp[6]) * C(0, 0.3, 0), "yHair", "hair", "Spike")
	end

	-- Arms
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperArm", "Block", V(0.56, 1.1, 0.6), C(0, -0.48, 0), "yUniform", "cloth")
		k.add(side .. "LowerArm", "Block", V(0.52, 1.0, 0.56), C(0, -0.45, 0), "yUniform", "cloth")
		k.add(side .. "Hand", "Block", V(0.4, 0.36, 0.22), C(0, -0.2, 0), "skin", "skin", "Palm")
		for fi = 0, 3 do
			k.add(side .. "Hand", "Block", V(0.085, 0.3, 0.1), C((fi - 1.5) * 0.095, -0.5, -0.01) * R(-10, 0, 0), "skin", "skin", "Finger")
		end
	end
	-- Legs
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperLeg", "Block", V(0.62, 1.2, 0.66), C(0, -0.56, 0), "yPants", "cloth")
		k.add(side .. "LowerLeg", "Block", V(0.56, 1.16, 0.6), C(0, -0.55, 0), "yPants", "cloth")
		k.add(side .. "Foot", "Block", V(0.58, 0.28, 0.98), C(0, -0.04, -0.16), "ySheath", "cloth")
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
