--!strict
-- Joints: the 15 animated joints (SPEC §5.1), rig families, per-joint layer masks and mirroring tables
-- for the procedural animation system (Anim/AnimMath, Anim/Clips/*, client AnimController). [Lune-safe]
--
-- API
--   Joints.ALL -> {string}                 the 15 Motor6D names, SPEC order (index = joint index 1..15)
--   Joints.COUNT = 15
--   Joints.Index[name] -> number?          joint index (1..15)
--   Joints.Valid[name] -> true?            name is an animated joint
--   Joints.Part0[name], Joints.Part1[name] -> string   limb names the joint connects
--   Joints.MirrorOf[name] -> string        Left* <-> Right*, centre joints map to themselves
--   Joints.MirrorIndex[i] -> number        same, by index
--   Joints.Side[name] -> "Left"|"Right"|"Centre"
--   Joints.Group[name] -> "Spine"|"Head"|"Shoulder"|"Elbow"|"Wrist"|"Hip"|"Knee"|"Ankle"   (spring tuning)
--   Joints.FAMILIES -> {"Skeleton","Human"}
--   Joints.MASK_NAMES -> {string}          Full, Upper, Lower, Arms, Head, LeftArm, RightArm, Legs, Torso,
--                                          UpperMove (Upper with a softer waist: one-shots while moving),
--                                          Spine (Root+Waist+Neck)
--   Joints.IsMask(name) -> boolean
--   Joints.MaskWeights(name?) -> {[jointName]: number}   0..1 per joint (unknown/nil -> Full); a copy
--   Joints.MaskArray(name?) -> {number}                  same, indexed by joint index (cached, read-only)
--
-- Pose channel convention (shared with clips, SPEC §3/§8): { rxDeg, ryDeg, rzDeg, px?, py?, pz? }
--   +rx swings a hanging limb forward (head: look up; spine: lean BACK), +ry turns left, +rz raises the
--   right arm / right leg sideways (left limbs: -rz), spine +rz rolls the top to the LEFT.
--   Mirroring left<->right swaps Left*/Right* and negates ry, rz and px.

local Joints = {}

Joints.ALL = table.freeze({
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
})

Joints.COUNT = #Joints.ALL

Joints.FAMILIES = table.freeze({ "Skeleton", "Human" })

Joints.Part0 = table.freeze({
	Root = "HumanoidRootPart",
	Waist = "LowerTorso",
	Neck = "UpperTorso",
	LeftShoulder = "UpperTorso",
	LeftElbow = "LeftUpperArm",
	LeftWrist = "LeftLowerArm",
	RightShoulder = "UpperTorso",
	RightElbow = "RightUpperArm",
	RightWrist = "RightLowerArm",
	LeftHip = "LowerTorso",
	LeftKnee = "LeftUpperLeg",
	LeftAnkle = "LeftLowerLeg",
	RightHip = "LowerTorso",
	RightKnee = "RightUpperLeg",
	RightAnkle = "RightLowerLeg",
})

Joints.Part1 = table.freeze({
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
})

Joints.Group = table.freeze({
	Root = "Spine",
	Waist = "Spine",
	Neck = "Head",
	LeftShoulder = "Shoulder",
	RightShoulder = "Shoulder",
	LeftElbow = "Elbow",
	RightElbow = "Elbow",
	LeftWrist = "Wrist",
	RightWrist = "Wrist",
	LeftHip = "Hip",
	RightHip = "Hip",
	LeftKnee = "Knee",
	RightKnee = "Knee",
	LeftAnkle = "Ankle",
	RightAnkle = "Ankle",
})

local index: { [string]: number } = {}
local valid: { [string]: boolean } = {}
local mirrorOf: { [string]: string } = {}
local side: { [string]: string } = {}
for i, name in Joints.ALL do
	index[name] = i
	valid[name] = true
	if string.sub(name, 1, 4) == "Left" then
		mirrorOf[name] = "Right" .. string.sub(name, 5)
		side[name] = "Left"
	elseif string.sub(name, 1, 5) == "Right" then
		mirrorOf[name] = "Left" .. string.sub(name, 6)
		side[name] = "Right"
	else
		mirrorOf[name] = name
		side[name] = "Centre"
	end
end
local mirrorIndex: { number } = {}
for i, name in Joints.ALL do
	mirrorIndex[i] = index[mirrorOf[name]]
end

Joints.Index = table.freeze(index)
Joints.Valid = table.freeze(valid)
Joints.MirrorOf = table.freeze(mirrorOf)
Joints.MirrorIndex = table.freeze(mirrorIndex)
Joints.Side = table.freeze(side)

-- Masks -------------------------------------------------------------------------------------------
local ARM_L = { "LeftShoulder", "LeftElbow", "LeftWrist" }
local ARM_R = { "RightShoulder", "RightElbow", "RightWrist" }
local LEGS = { "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

local function weights(list: { { any } }): { [string]: number }
	local out: { [string]: number } = {}
	for _, entry in list do
		local names = entry[1] :: { string }
		local w = entry[2] :: number
		for _, n in names do
			out[n] = w
		end
	end
	return out
end

local MASKS: { [string]: { [string]: number } } = {
	Full = weights({ { Joints.ALL, 1 } }),
	Upper = weights({ { { "Waist", "Neck" }, 1 }, { ARM_L, 1 }, { ARM_R, 1 } }),
	-- One-shot full-body clips while moving: legs and root stay with locomotion, the waist keeps most of
	-- the twist (AnimController also transfers some of the clip's Root yaw/pitch onto the waist).
	UpperMove = weights({ { { "Waist" }, 0.85 }, { { "Neck" }, 1 }, { ARM_L, 1 }, { ARM_R, 1 } }),
	Lower = weights({ { { "Root" }, 1 }, { LEGS, 1 } }),
	Legs = weights({ { LEGS, 1 } }),
	Arms = weights({ { ARM_L, 1 }, { ARM_R, 1 } }),
	LeftArm = weights({ { ARM_L, 1 } }),
	RightArm = weights({ { ARM_R, 1 } }),
	Head = weights({ { { "Neck" }, 1 } }),
	Torso = weights({ { { "Waist", "Neck" }, 1 } }),
	Spine = weights({ { { "Root", "Waist", "Neck" }, 1 } }),
}

local maskNames: { string } = {}
for name in MASKS do
	table.insert(maskNames, name)
end
table.sort(maskNames)
Joints.MASK_NAMES = table.freeze(maskNames)

local maskArrays: { [string]: { number } } = {}
for name, w in MASKS do
	local arr: { number } = {}
	for i, joint in Joints.ALL do
		arr[i] = w[joint] or 0
	end
	maskArrays[name] = table.freeze(arr)
end

function Joints.IsMask(name: any): boolean
	return type(name) == "string" and MASKS[name] ~= nil
end

function Joints.MaskWeights(name: string?): { [string]: number }
	local w = MASKS[name or "Full"] or MASKS.Full
	return table.clone(w)
end

function Joints.MaskArray(name: string?): { number }
	return maskArrays[name or "Full"] or maskArrays.Full
end

return Joints
