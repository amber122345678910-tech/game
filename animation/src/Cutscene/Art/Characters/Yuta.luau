--!strict
-- Yuta: slim, dark spiky hair with bangs, white high-collar uniform, katana
-- in a dark sheath across the back. R15 skeleton.
local Builder = require(script.Parent.Parent.Parent.Builder)
local Rig = require(script.Parent.Parent.Parent.Rig)

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
	k.add("UpperTorso", "Block", V(0.84, 0.46, 0.84), C(0, 1.56, 0.02), "yUniform", "cloth", "Collar")
	k.add("UpperTorso", "Block", V(0.86, 0.06, 0.86), C(0, 1.79, 0.02), "yUniformShade", "cloth", "CollarEdge")
	for _, sx in { -1, 1 } do
		k.add("UpperTorso", "Block", V(0.62, 0.4, 0.98), C(sx * 0.72, 1.3, 0) * R(0, 0, sx * -10), "yUniform", "cloth", "Shoulder")
	end
	-- katana across the back: sheath from the right hip up to the left shoulder
	local back = C(0, 0.72, 0.6) * R(0, 0, 38)
	k.add("UpperTorso", "Block", V(0.17, 3.2, 0.17), back, "ySheath", "metal", "Sheath")
	k.add("UpperTorso", "Block", V(0.4, 0.07, 0.4), back * C(0, 1.62, 0), "rTag", "metal", "Guard")
	k.add("UpperTorso", "Block", V(0.13, 0.9, 0.13), back * C(0, 2.1, 0), "yHair", "metal", "Hilt")

	-- Head and hair
	k.add("Head", "Block", V(1.0, 1.08, 1.0), C(0, 0.64, 0), "skin", "skin", "Head")
	k.add("Head", "Ellipsoid", V(1.16, 0.62, 1.2), C(0, 1.18, 0.04), "yHair", "hair", "HairTop")
	k.add("Head", "Block", V(1.08, 0.9, 0.28), C(0, 0.86, 0.5), "yHair", "hair", "HairBack")
	for _, sx in { -1, 1 } do
		k.add("Head", "Block", V(0.16, 0.86, 0.72), C(sx * 0.55, 0.78, 0.06), "yHair", "hair", "HairSide")
		k.add("Head", "Block", V(0.3, 0.06, 0.03), C(sx * 0.22, 0.8, -0.505) * R(0, 0, sx * 6), "yHair", "hair", "Brow")
		k.add("Head", "Block", V(0.17, 0.08, 0.03), C(sx * 0.22, 0.68, -0.505), "line", "hair", "Eye")
	end
	-- bangs: thin wedges hanging over the forehead
	local bangs = { { -0.36, 14 }, { -0.14, -6 }, { 0.1, 8 }, { 0.32, -12 } }
	for _, b in bangs do
		-- triangle facing forward, tip pointing down
		k.add("Head", "Wedge", V(0.14, 0.62, 0.24), C(b[1], 0.98, -0.53) * R(0, 0, 180 + b[2]) * R(0, 90, 0), "yHair", "hair", "Bang")
	end
	-- spikes on top / back
	local spikes = { { -0.4, 1.35, 0.25, -40, 0, 30 }, { 0.35, 1.38, 0.3, -45, 0, -28 }, { 0, 1.4, 0.45, -60, 0, 0 } }
	for _, s in spikes do
		k.add("Head", "Wedge", V(0.34, 0.6, 0.3), C(s[1], s[2], s[3]) * R(s[4], s[5], s[6]) * C(0, 0.3, 0), "yHair", "hair", "Spike")
	end

	-- Arms
	for _, side in { "Left", "Right" } do
		k.add(side .. "UpperArm", "Block", V(0.56, 1.1, 0.6), C(0, -0.48, 0), "yUniform", "cloth")
		k.add(side .. "LowerArm", "Block", V(0.52, 1.0, 0.56), C(0, -0.45, 0), "yUniform", "cloth")
		k.add(side .. "Hand", "Block", V(0.42, 0.44, 0.38), C(0, -0.24, 0), "skin", "skin")
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
