--!strict
-- R15-shaped skeleton with our own forward kinematics.
--
-- Bones carry the standard R15 part names (HumanoidRootPart, LowerTorso,
-- UpperTorso, Head, Left/Right Upper/Lower Arm, Hand, Upper/Lower Leg, Foot).
-- Each bone frame sits at its joint pivot (shoulder, elbow, knee...) in the
-- rest pose: X = character's right, Y = up, -Z = forward (Roblox convention).
-- Parts are attached to bones with a local CFrame. We compute every part's
-- world CFrame ourselves, so the exact same math runs in Roblox and in the
-- offline preview.
local Rig = {}

export type Bone = { name: string, parent: string?, joint: CFrame }
export type RigDef = { bones: { Bone }, index: { [string]: Bone } }
export type Pose = { [string]: CFrame }

export type HumanDims = {
	hip: number, -- hip pivot height above the ground (rest pose)
	hipX: number, -- half distance between hip pivots
	waist: number, -- waist pivot above hip center
	neck: number, -- neck pivot above waist pivot
	shoulderY: number, -- shoulder pivot above waist pivot
	shoulderX: number, -- half distance between shoulder pivots
	upperArm: number,
	lowerArm: number,
	upperLeg: number,
	lowerLeg: number,
}

local function def(bones: { Bone }): RigDef
	local index = {}
	for _, b in bones do
		index[b.name] = b
	end
	return { bones = bones, index = index }
end

Rig.define = def

-- Standard humanoid (R15 topology). The root (HumanoidRootPart) is placed at
-- the hip center; the character's root CFrame is the point on the ground
-- under the hips, so "root * CFrame.new(0, hip, 0)" is the pelvis.
function Rig.humanoid(d: HumanDims): RigDef
	return def({
		{ name = "HumanoidRootPart", parent = nil, joint = CFrame.new(0, d.hip, 0) },
		{ name = "LowerTorso", parent = "HumanoidRootPart", joint = CFrame.new() },
		{ name = "UpperTorso", parent = "LowerTorso", joint = CFrame.new(0, d.waist, 0) },
		{ name = "Head", parent = "UpperTorso", joint = CFrame.new(0, d.neck, 0) },
		{ name = "LeftUpperArm", parent = "UpperTorso", joint = CFrame.new(-d.shoulderX, d.shoulderY, 0) },
		{ name = "LeftLowerArm", parent = "LeftUpperArm", joint = CFrame.new(0, -d.upperArm, 0) },
		{ name = "LeftHand", parent = "LeftLowerArm", joint = CFrame.new(0, -d.lowerArm, 0) },
		{ name = "RightUpperArm", parent = "UpperTorso", joint = CFrame.new(d.shoulderX, d.shoulderY, 0) },
		{ name = "RightLowerArm", parent = "RightUpperArm", joint = CFrame.new(0, -d.upperArm, 0) },
		{ name = "RightHand", parent = "RightLowerArm", joint = CFrame.new(0, -d.lowerArm, 0) },
		{ name = "LeftUpperLeg", parent = "LowerTorso", joint = CFrame.new(-d.hipX, 0, 0) },
		{ name = "LeftLowerLeg", parent = "LeftUpperLeg", joint = CFrame.new(0, -d.upperLeg, 0) },
		{ name = "LeftFoot", parent = "LeftLowerLeg", joint = CFrame.new(0, -d.lowerLeg, 0) },
		{ name = "RightUpperLeg", parent = "LowerTorso", joint = CFrame.new(d.hipX, 0, 0) },
		{ name = "RightLowerLeg", parent = "RightUpperLeg", joint = CFrame.new(0, -d.upperLeg, 0) },
		{ name = "RightFoot", parent = "RightLowerLeg", joint = CFrame.new(0, -d.lowerLeg, 0) },
	})
end

local IDENTITY = CFrame.new()

-- World CFrame of every bone. Bones are listed parent-first.
function Rig.solve(rig: RigDef, root: CFrame, pose: Pose?): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	for _, b in rig.bones do
		local parentCF = if b.parent then out[b.parent] else root
		local r = if pose then (pose[b.name] or IDENTITY) else IDENTITY
		out[b.name] = parentCF * b.joint * r
	end
	return out
end

-- Rotation from degrees (X, Y, Z), applied in the joint's local frame.
function Rig.R(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Blend two poses (slerp per bone).
function Rig.blend(a: Pose, b: Pose, t: number): Pose
	local out: Pose = {}
	for k, v in a do
		out[k] = v:Lerp(b[k] or IDENTITY, t)
	end
	for k, v in b do
		if out[k] == nil then
			out[k] = IDENTITY:Lerp(v, t)
		end
	end
	return out
end

return Rig
