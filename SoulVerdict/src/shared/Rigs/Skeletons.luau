--!strict
-- Skeletons: base skeleton definitions per rig family. [Lune-safe]
--
-- A skeleton defines the INVISIBLE physics parts of a character (R15 names, see docs/SPEC.md §5.1),
-- where every Motor6D pivot sits at rest, the default VFX attachment points and a few named
-- reference poses. Blueprints (Rigs/Blueprints/*) pick a skeleton and add visual parts on top.
--
-- FAMILIES
--   "Skeleton"  Sans family. Short and broad: big round skull (2.1 wide), chunky hoodie torso
--               (2.0 wide), short legs, slippers. Total height ~5.1 studs at scale 1 (kits usually
--               scale it by 1.05..1.15). Arms hang so the hands end at the jacket hem, which is
--               where the jacket pockets are (pose "Pockets").
--   "Human"     Fallen-children proportions: large head (1.5), slim limbs, ~4.8 studs tall.
--
-- CONVENTIONS (all numbers are studs at scale 1; RigBuilder rescales the finished model)
--   * Model space: Y up, the character faces -Z, its right hand is on +X. Feet rest on y = 0.
--   * REST POSE = every part axis-aligned (identity rotation), arms hanging straight down with a
--     small gap from the torso, legs straight and slightly apart. Because every Motor6D has
--     identity rotation in C0/C1, Motor6D.Transform rotates in world-aligned axes at rest:
--       +rx swings a hanging limb FORWARD (and tilts the head back/up), +ry turns LEFT,
--       +rz raises the RIGHT arm sideways (the LEFT arm is raised with -rz).
--     We chose a straight-down rest instead of a baked A-pose: an A-pose (shoulders +-10..14 deg)
--     is just a Transform (see Poses.APose), clips stay symmetric and IK/aim maths stay simple.
--   * Limb spec (how the tree is resolved, parents first):
--       pivot  = parent.Centre + At * parent.Size + Offset        (At is normalised: -0.5..0.5)
--       centre = pivot - Pivot * Size                              (Pivot is normalised too)
--     so resizing a parent moves its children, and moving a joint moves the whole sub-chain.
--     After resolving, everything is shifted so the lowest physics part touches y = 0.
--   * HumanoidRootPart (2 x 2 x 1) is centred on the Root pivot = centre of LowerTorso (pelvis).
--     HipHeight = bottom of HumanoidRootPart above the ground.
--   * Anchors (default attachment placements) use normalised coordinates on their limb box
--     (z = -0.5 is the FRONT face) plus an optional extra CFrame.
--
-- API
--   Skeletons.Get(id: string) -> SkeletonDef?                 raw definition ("Skeleton" | "Human")
--   Skeletons.List() -> {string}
--   Skeletons.Resolve(id: string, overrides: Overrides?, groundOffset: number?) -> Resolved
--       overrides[limbName] = { Size = Vector3?, Joint = Vector3?, At = Vector3?, Offset = Vector3?,
--                               Pivot = Vector3? }
--       Joint is a DELTA (studs) added to that limb's pivot: it moves the limb and all its children.
--       groundOffset lifts the whole skeleton (feet at y = groundOffset, HipHeight grows by it) for
--       blueprints that stand on something of their own (a base, stilts, a hover disc).
--   Skeletons.Pose(id: string, poseName: string) -> Pose?      named reference pose (degrees)
--   Skeletons.LIMBS  -> {string}   the 16 physics part names (HumanoidRootPart first)
--   Skeletons.JOINTS -> {string}   the 15 Motor6D names
--
-- Pose format (shared with Anim clips, SPEC §8): { [jointName] = { rxDeg, ryDeg, rzDeg, px?, py?, pz? } }

local Skeletons = {}

export type LimbSpec = {
	Parent: string?, -- parent limb (nil only for HumanoidRootPart)
	Joint: string?, -- Motor6D name connecting Parent -> this limb
	At: Vector3?, -- pivot location on the parent box (normalised), default (0,0,0)
	Offset: Vector3?, -- extra pivot offset (studs), default (0,0,0)
	Pivot: Vector3?, -- where the pivot lies on this limb's box (normalised), default (0,0,0)
	Size: Vector3, -- physics part size (studs)
}

export type AnchorSpec = {
	Limb: string,
	At: Vector3, -- normalised position on the limb box
	Extra: CFrame?, -- applied after the normalised position (studs / rotation)
}

export type PoseValue = { number }
export type Pose = { [string]: PoseValue }

export type SkeletonDef = {
	Id: string,
	Family: "Skeleton" | "Human",
	Description: string,
	Limbs: { [string]: LimbSpec },
	Anchors: { [string]: AnchorSpec },
	Poses: { [string]: Pose },
}

export type LimbOverride = {
	Size: Vector3?,
	Joint: Vector3?,
	At: Vector3?,
	Offset: Vector3?,
	Pivot: Vector3?,
}

export type Overrides = { [string]: LimbOverride }

export type ResolvedLimb = {
	Name: string,
	Parent: string?,
	Joint: string?,
	Size: Vector3,
	CFrame: CFrame, -- rest CFrame in model space (identity rotation)
	Pivot: Vector3, -- joint pivot (model space); for HumanoidRootPart = its centre
}

export type ResolvedJoint = {
	Name: string,
	Part0: string,
	Part1: string,
	Pivot: Vector3,
}

export type Resolved = {
	Id: string,
	Family: "Skeleton" | "Human",
	Limbs: { [string]: ResolvedLimb },
	Order: { string }, -- parents before children (HumanoidRootPart first)
	Joints: { [string]: ResolvedJoint },
	Anchors: { [string]: { Limb: string, CFrame: CFrame } }, -- CFrame relative to the limb
	RootCFrame: CFrame,
	HipHeight: number,
	Height: number, -- top of the highest physics part above the ground
}

local V = Vector3.new

Skeletons.LIMBS = {
	"HumanoidRootPart",
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

Skeletons.JOINTS = {
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
}

-- Builds the limb table of a two-armed, two-legged biped from a few measurements.
-- Mirrored limbs are generated so left/right can never drift apart.
type BipedParams = {
	Pelvis: Vector3,
	Torso: Vector3,
	Head: Vector3,
	NeckLift: number,
	HeadPivot: Vector3,
	ShoulderAt: number, -- normalised height of the shoulder on the torso
	ShoulderOut: number, -- studs outside the torso side
	UpperArm: Vector3,
	LowerArm: Vector3,
	Hand: Vector3,
	HipIn: number, -- studs inside the pelvis side
	HipLift: number,
	UpperLeg: Vector3,
	LowerLeg: Vector3,
	Foot: Vector3,
	FootPivotZ: number, -- normalised z of the ankle on the foot box (+ = towards the heel)
}

local function biped(p: BipedParams): { [string]: LimbSpec }
	local limbs: { [string]: LimbSpec } = {
		HumanoidRootPart = { Size = V(2, 2, 1) },
		LowerTorso = { Parent = "HumanoidRootPart", Joint = "Root", Size = p.Pelvis },
		UpperTorso = {
			Parent = "LowerTorso",
			Joint = "Waist",
			At = V(0, 0.5, 0),
			Pivot = V(0, -0.5, 0),
			Size = p.Torso,
		},
		Head = {
			Parent = "UpperTorso",
			Joint = "Neck",
			At = V(0, 0.5, 0),
			Offset = V(0, p.NeckLift, 0),
			Pivot = p.HeadPivot,
			Size = p.Head,
		},
	}
	for _, side in { "Left", "Right" } do
		local s = if side == "Left" then -1 else 1
		limbs[side .. "UpperArm"] = {
			Parent = "UpperTorso",
			Joint = side .. "Shoulder",
			At = V(0.5 * s, p.ShoulderAt, 0),
			Offset = V(p.ShoulderOut * s, 0, 0),
			Pivot = V(0, 0.42, 0),
			Size = p.UpperArm,
		}
		limbs[side .. "LowerArm"] = {
			Parent = side .. "UpperArm",
			Joint = side .. "Elbow",
			At = V(0, -0.5, 0),
			Offset = V(0, 0.05, 0),
			Pivot = V(0, 0.45, 0),
			Size = p.LowerArm,
		}
		limbs[side .. "Hand"] = {
			Parent = side .. "LowerArm",
			Joint = side .. "Wrist",
			At = V(0, -0.5, 0),
			Offset = V(0, 0.04, 0),
			Pivot = V(0, 0.45, 0),
			Size = p.Hand,
		}
		limbs[side .. "UpperLeg"] = {
			Parent = "LowerTorso",
			Joint = side .. "Hip",
			At = V(0.5 * s, -0.5, 0),
			Offset = V(-p.HipIn * s, p.HipLift, 0),
			Pivot = V(0, 0.45, 0),
			Size = p.UpperLeg,
		}
		limbs[side .. "LowerLeg"] = {
			Parent = side .. "UpperLeg",
			Joint = side .. "Knee",
			At = V(0, -0.5, 0),
			Offset = V(0, 0.04, 0),
			Pivot = V(0, 0.45, 0),
			Size = p.LowerLeg,
		}
		limbs[side .. "Foot"] = {
			Parent = side .. "LowerLeg",
			Joint = side .. "Ankle",
			At = V(0, -0.5, 0),
			Offset = V(0, 0.05, 0),
			Pivot = V(0, 0.5, p.FootPivotZ),
			Size = p.Foot,
		}
	end
	return limbs
end

local function standardAnchors(eyeX: number, eyeY: number, mouthY: number): { [string]: AnchorSpec }
	return {
		RootAttachment = { Limb = "HumanoidRootPart", At = V(0, 0, 0) },
		LeftEye = { Limb = "Head", At = V(-eyeX, eyeY, -0.5) },
		RightEye = { Limb = "Head", At = V(eyeX, eyeY, -0.5) },
		Mouth = { Limb = "Head", At = V(0, mouthY, -0.48) },
		HeadTop = { Limb = "Head", At = V(0, 0.5, 0), Extra = CFrame.new(0, 0.35, 0) },
		Chest = { Limb = "UpperTorso", At = V(0, 0.12, -0.5) },
		Back = { Limb = "UpperTorso", At = V(0, 0.1, 0.5) },
		LeftGrip = { Limb = "LeftHand", At = V(0, -0.3, 0) },
		RightGrip = { Limb = "RightHand", At = V(0, -0.3, 0) },
		LeftFootAttachment = { Limb = "LeftFoot", At = V(0, -0.5, 0) },
		RightFootAttachment = { Limb = "RightFoot", At = V(0, -0.5, 0) },
	}
end

-- Reference poses shared by both families (degrees; see header for axis meaning).
local COMMON_POSES: { [string]: Pose } = {
	Rest = {},
	APose = {
		LeftShoulder = { 0, 0, -12 },
		RightShoulder = { 0, 0, 12 },
		LeftElbow = { 6, 0, 0 },
		RightElbow = { 6, 0, 0 },
	},
	TPose = {
		LeftShoulder = { 0, 0, -90 },
		RightShoulder = { 0, 0, 90 },
	},
	Wave = {
		Waist = { 0, -6, 0 },
		Neck = { 4, 8, -6 },
		RightShoulder = { 0, 0, 150 },
		RightElbow = { 0, 0, 28 },
		RightWrist = { 0, 0, -10 },
		LeftShoulder = { 4, 0, -10 },
		LeftElbow = { 10, 0, 0 },
		LeftHip = { 0, 0, -3 },
		RightHip = { 0, 0, 3 },
	},
	Walk = {
		Root = { 0, 0, 0, 0, -0.06, 0 },
		Waist = { 4, 6, 0 },
		Neck = { -3, -6, 0 },
		LeftShoulder = { 28, 0, -6 },
		LeftElbow = { 22, 0, 0 },
		RightShoulder = { -26, 0, 6 },
		RightElbow = { 12, 0, 0 },
		LeftHip = { -26, 0, 0 },
		LeftKnee = { -18, 0, 0 },
		LeftAnkle = { 14, 0, 0 },
		RightHip = { 30, 0, 0 },
		RightKnee = { -12, 0, 0 },
		RightAnkle = { -8, 0, 0 },
	},
	Action = {
		Root = { 0, 18, 0, 0, -0.2, 0 },
		Waist = { 8, -24, 0 },
		Neck = { -6, 12, 0 },
		RightShoulder = { 92, 0, 12 },
		RightElbow = { 18, 0, 0 },
		RightWrist = { 0, 0, 0 },
		LeftShoulder = { -36, 0, -24 },
		LeftElbow = { 48, 0, 0 },
		LeftHip = { 28, 0, -10 },
		LeftKnee = { -38, 0, 0 },
		LeftAnkle = { 10, 0, 0 },
		RightHip = { -20, 0, 10 },
		RightKnee = { -22, 0, 0 },
		RightAnkle = { 14, 0, 0 },
	},
}

local function withCommon(extra: { [string]: Pose }): { [string]: Pose }
	local out: { [string]: Pose } = table.clone(COMMON_POSES)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local DEFS: { [string]: SkeletonDef } = {}

DEFS.Skeleton = {
	Id = "Skeleton",
	Family = "Skeleton",
	Description = "Sans family: big round skull, broad hoodie torso, short legs (~5.1 studs)",
	Limbs = biped({
		Pelvis = V(1.6, 0.56, 1.0),
		Torso = V(2.0, 1.45, 1.25),
		Head = V(2.1, 1.92, 1.86),
		NeckLift = 0.02,
		HeadPivot = V(0, -0.42, 0.04),
		ShoulderAt = 0.34,
		ShoulderOut = 0.15,
		UpperArm = V(0.62, 0.8, 0.62),
		LowerArm = V(0.54, 0.72, 0.54),
		Hand = V(0.5, 0.5, 0.36),
		HipIn = 0.35,
		HipLift = 0.08,
		UpperLeg = V(0.7, 0.62, 0.7),
		LowerLeg = V(0.46, 0.56, 0.46),
		Foot = V(0.78, 0.42, 1.05),
		FootPivotZ = 0.22,
	}),
	Anchors = standardAnchors(0.2, 0.08, -0.25),
	Poses = withCommon({
		-- Hands slid into the hoodie pockets (lazy idle). Elbows out, wrists tucked forward.
		Pockets = {
			Waist = { -3, 0, 0 },
			Neck = { 3, 0, 4 },
			LeftShoulder = { 14, 0, 12 },
			LeftElbow = { 26, 0, 0 },
			LeftWrist = { 0, 0, 10 },
			RightShoulder = { 14, 0, -12 },
			RightElbow = { 26, 0, 0 },
			RightWrist = { 0, 0, -10 },
			LeftHip = { 0, 0, -3 },
			RightHip = { 0, 0, 3 },
		},
		Shrug = {
			Neck = { -6, 0, 8 },
			LeftShoulder = { 0, 0, -38 },
			LeftElbow = { 70, 0, 0 },
			LeftWrist = { 0, 0, 20 },
			RightShoulder = { 0, 0, 38 },
			RightElbow = { 70, 0, 0 },
			RightWrist = { 0, 0, -20 },
		},
	}),
}

DEFS.Human = {
	Id = "Human",
	Family = "Human",
	Description = "Fallen-children proportions: 1.5 head, slim limbs (~4.8 studs)",
	Limbs = biped({
		Pelvis = V(1.12, 0.5, 0.66),
		Torso = V(1.24, 1.2, 0.72),
		Head = V(1.52, 1.5, 1.42),
		NeckLift = 0.04,
		HeadPivot = V(0, -0.4, 0),
		ShoulderAt = 0.36,
		ShoulderOut = 0.23,
		UpperArm = V(0.4, 0.8, 0.4),
		LowerArm = V(0.36, 0.74, 0.36),
		Hand = V(0.4, 0.42, 0.3),
		HipIn = 0.23,
		HipLift = 0.05,
		UpperLeg = V(0.48, 0.8, 0.48),
		LowerLeg = V(0.42, 0.78, 0.42),
		Foot = V(0.5, 0.34, 0.8),
		FootPivotZ = 0.25,
	}),
	Anchors = standardAnchors(0.2, 0.04, -0.22),
	Poses = withCommon({
		Ready = {
			Root = { 0, 10, 0, 0, -0.12, 0 },
			Waist = { 6, -10, 0 },
			LeftShoulder = { 40, 0, -14 },
			LeftElbow = { 70, 0, 0 },
			RightShoulder = { 30, 0, 14 },
			RightElbow = { 80, 0, 0 },
			LeftHip = { 16, 0, -6 },
			LeftKnee = { -24, 0, 0 },
			LeftAnkle = { 8, 0, 0 },
			RightHip = { -6, 0, 6 },
			RightKnee = { -18, 0, 0 },
			RightAnkle = { 18, 0, 0 },
		},
	}),
}

function Skeletons.Get(id: string): SkeletonDef?
	return DEFS[id]
end

function Skeletons.List(): { string }
	local out = {}
	for id in DEFS do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

function Skeletons.Pose(id: string, poseName: string): Pose?
	local def = DEFS[id]
	if def == nil then
		return nil
	end
	return def.Poses[poseName]
end

local ZERO = Vector3.new(0, 0, 0)

-- Resolves a skeleton (plus optional per-limb overrides) to absolute rest CFrames.
function Skeletons.Resolve(id: string, overrides: Overrides?, groundOffset: number?): Resolved
	local def = DEFS[id]
	assert(def ~= nil, "Skeletons.Resolve: unknown skeleton '" .. tostring(id) .. "'")
	local ov: Overrides = overrides or {}
	for limbName in ov do
		assert(def.Limbs[limbName] ~= nil, ("Skeletons.Resolve: override for unknown limb '%s'"):format(limbName))
	end

	-- Resolve parents before children (fixed R15 order is already topological).
	local centres: { [string]: Vector3 } = {}
	local sizes: { [string]: Vector3 } = {}
	local pivots: { [string]: Vector3 } = {}
	for _, limbName in Skeletons.LIMBS do
		local spec = def.Limbs[limbName]
		assert(spec ~= nil, ("skeleton %s lacks limb %s"):format(id, limbName))
		local o: LimbOverride = ov[limbName] or {}
		local size = o.Size or spec.Size
		assert(size.X > 0 and size.Y > 0 and size.Z > 0, "limb sizes must be positive: " .. limbName)
		local pivot: Vector3
		if spec.Parent == nil then
			pivot = ZERO
		else
			local parentName = spec.Parent :: string
			local pc, ps = centres[parentName], sizes[parentName]
			assert(pc ~= nil, ("limb %s resolved before its parent %s"):format(limbName, parentName))
			local at = o.At or spec.At or ZERO
			local offset = (o.Offset or spec.Offset or ZERO) + (o.Joint or ZERO)
			pivot = pc + at * ps + offset
		end
		local pivotOnBox = o.Pivot or spec.Pivot or ZERO
		centres[limbName] = pivot - pivotOnBox * size
		sizes[limbName] = size
		pivots[limbName] = pivot
	end

	-- Ground the skeleton: lowest physics part bottom -> y = 0.
	local minY = math.huge
	local maxY = -math.huge
	for _, limbName in Skeletons.LIMBS do
		if limbName ~= "HumanoidRootPart" then
			local c, s = centres[limbName], sizes[limbName]
			minY = math.min(minY, c.Y - s.Y / 2)
			maxY = math.max(maxY, c.Y + s.Y / 2)
		end
	end
	local lift = groundOffset or 0
	assert(lift >= 0, "Skeletons.Resolve: groundOffset must be >= 0")
	local shift = Vector3.new(0, lift - minY, 0)

	local limbs: { [string]: ResolvedLimb } = {}
	local joints: { [string]: ResolvedJoint } = {}
	for _, limbName in Skeletons.LIMBS do
		local spec = def.Limbs[limbName]
		local centre = centres[limbName] + shift
		limbs[limbName] = {
			Name = limbName,
			Parent = spec.Parent,
			Joint = spec.Joint,
			Size = sizes[limbName],
			CFrame = CFrame.new(centre),
			Pivot = pivots[limbName] + shift,
		}
		if spec.Joint ~= nil and spec.Parent ~= nil then
			joints[spec.Joint :: string] = {
				Name = spec.Joint :: string,
				Part0 = spec.Parent :: string,
				Part1 = limbName,
				Pivot = pivots[limbName] + shift,
			}
		end
	end

	local anchors: { [string]: { Limb: string, CFrame: CFrame } } = {}
	for name, a in def.Anchors do
		local size = sizes[a.Limb]
		assert(size ~= nil, "anchor on unknown limb " .. a.Limb)
		local cf = CFrame.new(a.At * size)
		if a.Extra then
			cf = cf * a.Extra
		end
		anchors[name] = { Limb = a.Limb, CFrame = cf }
	end

	local root = limbs.HumanoidRootPart
	local hipHeight = root.CFrame.Position.Y - root.Size.Y / 2
	assert(
		hipHeight > 0.05,
		("skeleton %s: HumanoidRootPart reaches the ground (HipHeight %.3f)"):format(id, hipHeight)
	)

	local order = table.clone(Skeletons.LIMBS)
	return {
		Id = def.Id,
		Family = def.Family,
		Limbs = limbs,
		Order = order,
		Joints = joints,
		Anchors = anchors,
		RootCFrame = root.CFrame,
		HipHeight = hipHeight,
		Height = maxY - minY,
	}
end

return Skeletons
