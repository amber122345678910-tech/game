--!strict
-- Clips/Skeleton: animation clips of the Sans family (SPEC §8 format; see Anim/AnimMath header for the
-- interpolation rules and the extension fields FullBody/Hold/FadeIn/FadeOut/Stride/Aim). [Lune-safe]
--
-- Personality: a lazy, relaxed skeleton. Hands live in the hoodie pockets (Skeletons pose "Pockets"),
-- the idle is a slow bob with a weight shift and a cocky head tilt, the walk is a waddling shuffle.
-- Effort only shows in sudden, sharp casts: a hand whips out of the pocket in a fast arc (anticipation ->
-- Back-eased snap -> hold -> lazy return to the pocket). The left hand usually stays in its pocket.
-- Locomotion cycles plant the LEFT foot at t = 0 and the RIGHT foot at Length/2 ("Step" markers) so the
-- AnimController can phase-sync Walk/Run/WalkBack/StrafeL/StrafeR.
-- Markers: "Hit" (impact frame), "Release" (projectile / effect leaves the hand), "Step" (foot plant).
--
-- Clips: Idle Walk Run WalkBack StrafeL StrafeR Jump Fall Land Dash Stunned Downed Block Parry Dodge Hit
--   Death Victory Emote_Wave Emote_Shrug Emote_Sit Emote_Laugh Cast CastUp CastForward Summon Point Slam
--   Throw Spin Leap Charge Slash1-4 Punch1-4 Kick1-3 Shoot Reload Heal Guard Taunt
--   extras: Pockets Tired IdleMenace BlueHeavy Wink Verdict Idle_Look Idle_Stretch

local A = require(script.Parent.Parent.AnimMath)
local Skeletons = require(script.Parent.Parent.Parent.Rigs.Skeletons)

type Pose = A.Pose
type ClipKey = A.ClipKey

local Clip, Merge, MirrorPose = A.Clip, A.Merge, A.MirrorPose
local V3 = Vector3.new

local function ST(spec: A.StanceSpec): Pose
	return A.Stance("Skeleton", spec)
end

-- palm centre -> target (character rest space); spine = Root/Waist the target is NOT attached to
local function reach(side: string, target: Vector3, spine: Pose?, pole: Vector3?, wrist: { number }?): Pose
	return A.Reach("Skeleton", side, target, { Spine = spine, Pole = pole, Wrist = wrist })
end
local Limb = A.Limb

local function K(t: number, pose: Pose, ease: string?, dir: string?): ClipKey
	return { t = t, Pose = pose, Ease = ease, Dir = dir }
end

local POCKETS: Pose = Skeletons.Pose("Skeleton", "Pockets") or {}
local function pick(src: Pose, names: { string }): Pose
	local out: Pose = {}
	for _, n in names do
		if src[n] then
			out[n] = table.clone(src[n])
		end
	end
	return out
end
local ARMS = pick(POCKETS, { "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist" })
local L_POCKET = pick(ARMS, { "LeftShoulder", "LeftElbow", "LeftWrist" })
local SHRUG = Skeletons.Pose("Skeleton", "Shrug") or {}

-- Rotates the pocket arms a little (walk swing) without pulling the hands out of the pockets.
local function pocketSwing(left: number, right: number): Pose
	local p = Merge(ARMS)
	p.LeftShoulder[1] += left
	p.RightShoulder[1] += right
	return p
end

local FEET_L = { X = -0.05, Out = 10 }
local FEET_R = { X = 0.05, Out = 10 }
local function stance(drop: number, pitch: number?, roll: number?, shiftX: number?, shiftZ: number?): Pose
	return ST({
		Drop = drop,
		Pitch = pitch or 2,
		Roll = roll or 0,
		Shift = V3(shiftX or 0, 0, shiftZ or 0),
		Left = FEET_L,
		Right = FEET_R,
	})
end

local LEGS = stance(0.03)
local TORSO = { Waist = { -5, 0, 0 }, Neck = { 4, 0, 3 } }
local STAND = Merge(LEGS, ARMS, TORSO)

local function stand(extra: Pose?): Pose
	return Merge(STAND, extra)
end

local Clips = {}

---------------------------------------------------------------------------------------------------
-- Base / locomotion
---------------------------------------------------------------------------------------------------

Clips.Pockets = Clip({ Length = 2, Loop = true, Priority = 1, Keys = { K(0, STAND) } })

-- Lazy idle: two slow bobs per cycle and a weight shift from leg to leg (contrapposto); the head lags.
local function idlePose(drop: number, roll: number, shiftX: number, waist: { number }, neck: { number }): Pose
	return Merge(stance(drop, 2.5, roll, shiftX), ARMS, { Waist = waist, Neck = neck })
end
Clips.Idle = Clip({
	Length = 3.2,
	Loop = true,
	Priority = 1,
	Keys = {
		K(0, idlePose(0.03, 0, 0, { -5, 0, 0 }, { 4, 0, 3 })),
		K(0.8, idlePose(0.075, 1.8, 0.05, { -6.5, -1.5, -2.2 }, { 5.5, 1.5, 5 })),
		K(1.6, idlePose(0.03, 0, 0, { -4.5, 0, 0 }, { 3.5, 0, 2.5 })),
		K(2.4, idlePose(0.075, -1.8, -0.05, { -6.5, 1.5, 2.2 }, { 5.5, -1.5, 1.5 })),
	},
})

-- Final form: no bob. Head low, eyes up, shoulders squared, right hand out of the pocket, slow deep breaths.
local MENACE_LEGS = ST({ Drop = 0.06, Pitch = 1, Left = { X = -0.14, Out = 14 }, Right = { X = 0.14, Out = 14 } })
local function menace(breath: number): Pose
	return Merge(MENACE_LEGS, L_POCKET, {
		Waist = { -7 + breath * 2, 0, 0 },
		Neck = { -9 + breath, 0, 0 },
		RightShoulder = { 8 + breath * 2, 0, 9 },
		RightElbow = { 14, 0, 0 },
		RightWrist = { -6, 0, -4 },
	})
end
Clips.IdleMenace = Clip({
	Length = 4,
	Loop = true,
	Priority = 1,
	Keys = { K(0, menace(0)), K(1.7, menace(1)), K(2.4, menace(0.85)), K(3.4, menace(0.1)) },
})

-- Exhausted (0 dodges): hunched with the hands on the thighs, heavy uneven breathing.
local function tired(breath: number): Pose
	local legs = ST({ Drop = 0.24, Pitch = -14 + breath, Left = { X = -0.1, Out = 12 }, Right = { X = 0.1, Out = 12 } })
	local spine = { Root = legs.Root, Waist = { -24 + breath * 3, 0, 0 } }
	return Merge(
		legs,
		spine,
		{ Neck = { 30 - breath * 2, 0, 4 } },
		reach("Left", V3(-0.5, 1.12 + breath * 0.02, -0.42), spine, V3(-1, 0, 0.3), { 30, 0, 0 }),
		reach("Right", V3(0.5, 1.12 + breath * 0.02, -0.42), spine, V3(1, 0, 0.3), { 30, 0, 0 })
	)
end
Clips.Tired = Clip({
	Length = 2.2,
	Loop = true,
	Priority = 1,
	Keys = { K(0, tired(0)), K(0.45, tired(1)), K(1.05, tired(0.1)), K(1.45, tired(0.75)), K(1.9, tired(0.05)) },
})

-- Walk: hands-in-pockets shuffle with a lazy waddle. t = 0 left contact, 0.25 left passing (right foot
-- swings), 0.5 right contact, 0.75 right passing.
local W_CONTACT = Merge(
	ST({
		Drop = 0.07,
		Pitch = 1,
		Yaw = -5,
		Left = { X = -0.03, Z = -0.32, Toe = 14 },
		Right = { X = 0.03, Z = 0.3, Y = 0.02, Toe = -16 },
	}),
	pocketSwing(-2, 2),
	{ Waist = { -5, 8, 0 }, Neck = { 5, -3, 3 } }
)
local W_PASS = Merge(
	ST({
		Drop = -0.005,
		Pitch = 2,
		Roll = -3,
		Shift = V3(-0.07, 0, 0),
		Left = { X = -0.02, Z = 0.02 },
		Right = { X = 0.04, Z = -0.02, Y = 0.2, Toe = 4 },
	}),
	ARMS,
	{ Waist = { -5.5, 2, 3 }, Neck = { 4.5, 0, 1.5 } }
)
Clips.Walk = Clip({
	Length = 1,
	Loop = true,
	Priority = 1,
	Stride = 7,
	Keys = { K(0, W_CONTACT), K(0.25, W_PASS), K(0.5, MirrorPose(W_CONTACT)), K(0.75, MirrorPose(W_PASS)) },
	Events = { { t = 0, Name = "Step" }, { t = 0.5, Name = "Step" } },
})

-- Run: a lazy jog, still in the pockets: forward lean, bouncy flight phase, head bobbing.
local R_CONTACT = Merge(
	ST({
		Drop = 0.12,
		Pitch = -9,
		Yaw = -7,
		Left = { Z = -0.42, Toe = 10 },
		Right = { Z = 0.45, Y = 0.12, Toe = -30 },
	}),
	pocketSwing(-3, 3),
	{ Waist = { -3, 9, 0 }, Neck = { 11, -3, 2 } }
)
local R_FLIGHT = Merge(
	ST({
		Drop = -0.05,
		Pitch = -8,
		Yaw = -2,
		Roll = -2,
		Shift = V3(-0.04, 0, 0),
		Left = { Z = 0.15, Y = 0.1, Toe = -22 },
		Right = { Z = -0.2, Y = 0.4, Toe = 8 },
	}),
	ARMS,
	{ Waist = { -4, 3, 2 }, Neck = { 9, -1, 2 } }
)
Clips.Run = Clip({
	Length = 0.72,
	Loop = true,
	Priority = 1,
	Stride = 11,
	Keys = { K(0, R_CONTACT), K(0.18, R_FLIGHT), K(0.36, MirrorPose(R_CONTACT)), K(0.54, MirrorPose(R_FLIGHT)) },
	Events = { { t = 0, Name = "Step" }, { t = 0.36, Name = "Step" } },
})

-- Backwards: careful steps, a slight lean back. t = 0 left foot plants BEHIND.
local B_CONTACT = Merge(
	ST({ Drop = 0.06, Pitch = 3, Yaw = 4, Left = { Z = 0.3, Toe = -10 }, Right = { Z = -0.24, Toe = 6 } }),
	ARMS,
	{ Waist = { -3, -5, 0 }, Neck = { 3, 2, 3 } }
)
local B_PASS = Merge(
	ST({
		Drop = 0,
		Pitch = 3,
		Roll = -2.5,
		Shift = V3(-0.06, 0, 0),
		Left = { Z = 0.02 },
		Right = { Z = 0.05, Y = 0.16, Toe = -4 },
	}),
	ARMS,
	{ Waist = { -3.5, -1, 2.5 }, Neck = { 3, 0, 2 } }
)
Clips.WalkBack = Clip({
	Length = 1.1,
	Loop = true,
	Priority = 1,
	Stride = 6,
	Keys = { K(0, B_CONTACT), K(0.275, B_PASS), K(0.55, MirrorPose(B_CONTACT)), K(0.825, MirrorPose(B_PASS)) },
	Events = { { t = 0, Name = "Step" }, { t = 0.55, Name = "Step" } },
})

-- Side-steps (moving left): the left foot leads wide, the right closes in. StrafeR = mirror, re-phased so
-- the LEFT foot still plants at t = 0.
local function strafePose(drop: number, roll: number, shiftX: number, l: A.FootSpec, r: A.FootSpec): Pose
	return Merge(
		ST({ Drop = drop, Roll = roll, Pitch = 2, Shift = V3(shiftX, 0, 0), Left = l, Right = r }),
		ARMS,
		{ Waist = { -5, 0, -roll * 0.6 }, Neck = { 4, 0, 2 + roll * 0.3 } }
	)
end
Clips.StrafeL = Clip({
	Length = 0.9,
	Loop = true,
	Priority = 1,
	Stride = 5.5,
	Keys = {
		K(0, strafePose(0.08, 2.5, -0.05, { X = -0.3, Out = 8 }, { X = 0.18, Toe = -12, Out = 8 })),
		K(0.225, strafePose(0, 1.5, -0.03, { X = -0.06, Out = 8 }, { X = -0.02, Y = 0.17, Toe = 2, Out = 8 })),
		K(0.45, strafePose(0.06, 1, 0, { X = 0.14, Toe = -8, Out = 8 }, { X = -0.22, Out = 8 })),
		K(0.675, strafePose(0, 2, -0.02, { X = -0.14, Y = 0.17, Out = 8 }, { X = 0, Out = 8 })),
	},
	Events = { { t = 0, Name = "Step" }, { t = 0.45, Name = "Step" } },
})
Clips.StrafeR = A.PhaseShift(A.MirrorClip(Clips.StrafeL), 0.5)

---------------------------------------------------------------------------------------------------
-- Air
---------------------------------------------------------------------------------------------------

Clips.Jump = Clip({
	Length = 0.5,
	Priority = 2,
	FullBody = true,
	Keys = {
		K(0, Merge(ST({ Drop = -0.03, Pitch = -4, Left = { Y = 0.05, Toe = -28 }, Right = { Y = 0.05, Toe = -28 } }), ARMS, {
			Waist = { -3, 0, 0 },
			Neck = { 2, 0, 3 },
		})),
		K(
			0.15,
			Merge(ST({ Drop = -0.06, Pitch = -2, Left = { Y = 0.42, Z = -0.18, Toe = 4 }, Right = { Y = 0.3, Z = 0.02, Toe = -6 } }), ARMS, {
				Waist = { -8, 0, 0 },
				Neck = { 7, 0, 4 },
			}),
			"Back",
			"Out"
		),
		K(0.5, Merge(ST({ Drop = -0.05, Left = { Y = 0.3, Z = -0.1, Toe = -4 }, Right = { Y = 0.22, Z = 0.05, Toe = -10 } }), ARMS, {
			Waist = { -6, 0, 0 },
			Neck = { 4, 0, 4 },
		})),
	},
	Events = { { t = 0, Name = "Step" } },
})

local function fallPose(k: number): Pose
	return Merge(
		ST({ Drop = -0.02, Left = { Y = 0.2 - k * 0.06, Z = -0.12 + k * 0.07, Toe = -10 }, Right = { Y = 0.1 + k * 0.06, Z = 0.08 - k * 0.08, Toe = -18 } }),
		{
			Waist = { -4, 0, 0 },
			Neck = { -8, 0, 3 },
			LeftShoulder = { 12 - k * 6, 0, -38 + k * 8 },
			LeftElbow = { 38 - k * 8, 0, 0 },
			LeftWrist = { 0, 0, 12 },
			RightShoulder = { 6 + k * 8, 0, 34 + k * 8 },
			RightElbow = { 32 + k * 8, 0, 0 },
			RightWrist = { 0, 0, -10 },
		}
	)
end
Clips.Fall = Clip({
	Length = 0.8,
	Loop = true,
	Priority = 2,
	FullBody = true,
	Keys = { K(0, fallPose(0)), K(0.4, fallPose(1)) },
})

Clips.Land = Clip({
	Length = 0.45,
	Priority = 2,
	FadeIn = 0.02,
	FadeOut = 0.12,
	Keys = {
		K(0, Merge(stance(0.2, -6), ARMS, { Waist = { -8, 0, 0 }, Neck = { 8, 0, 3 } })),
		K(0.07, Merge(stance(0.34, -10), ARMS, { Waist = { -10, 0, 0 }, Neck = { 12, 0, 3 } }), "Quad", "Out"),
		K(0.22, Merge(stance(0, 2), ARMS, { Waist = { -3, 0, 0 }, Neck = { 3, 0, 3 } }), "Back", "Out"),
		K(0.45, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Movement actions
---------------------------------------------------------------------------------------------------

local DASH_POSE = Merge(
	ST({ Drop = 0.26, Pitch = -16, Left = { Z = -0.42, Toe = 12 }, Right = { Z = 0.5, Toe = -35 } }),
	ARMS,
	{ Waist = { -10, 8, 0 }, Neck = { 18, -6, 0 } }
)
Clips.Dash = Clip({
	Length = 0.5,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, STAND),
		K(0.06, Merge(stance(0.12, -6), ARMS, { Waist = { -6, 0, 0 }, Neck = { 6, 0, 3 } }), "Quad", "Out"),
		K(0.13, DASH_POSE, "Back", "Out"),
		K(0.34, Merge(DASH_POSE, ST({ Drop = 0.22, Pitch = -13, Left = { Z = -0.38, Toe = 8 }, Right = { Z = 0.42, Toe = -30 } }))),
		K(0.5, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.06, Name = "Release" }, { t = 0.13, Name = "Step" } },
})

-- Lazy side-step dodge ("MISS"): the whole body slides ~1.6 studs left (Root translation; the
-- HumanoidRootPart does not move), smug head tilt, then strolls back. AnimController mirrors it so he
-- slides away from the attacker.
local DODGE_OUT = Merge(
	ST({
		Drop = 0.08,
		Pitch = 1,
		Roll = 4,
		Shift = V3(-1.6, 0, 0.1),
		Left = { X = -1.68, Z = 0.1, Out = 12 },
		Right = { X = -1.45, Z = 0.1, Toe = -12, Out = 8 },
	}),
	ARMS,
	{ Waist = { -3, 6, -4 }, Neck = { 2, -10, 9 } }
)
Clips.Dodge = Clip({
	Length = 0.7,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, STAND),
		K(0.1, DODGE_OUT, "Quad", "Out"),
		K(0.45, Merge(DODGE_OUT, { Neck = { 2, -8, 11 }, Waist = { -3, 5, -3 } })),
		K(0.7, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0, Name = "Release" }, { t = 0.1, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Reactions & states
---------------------------------------------------------------------------------------------------

local function stunnedKey(k: number): Pose
	local th = math.rad(k * 90)
	local rx, rz = -3 + 2.5 * math.cos(th), 3 * math.sin(th)
	local sway = 5 * math.sin(th + math.rad(120))
	return Merge(
		ST({ Drop = 0.1, Pitch = rx, Roll = rz, Yaw = 4 * math.sin(th), Left = { X = -0.08, Out = 10 }, Right = { X = 0.08, Out = 10 } }),
		{
			Waist = { -6 + 2 * math.cos(th + math.rad(45)), 0, -2 * math.sin(th + math.rad(45)) },
			Neck = { -6 + 6 * math.cos(th + math.rad(90)), 8 * math.cos(th + math.rad(90)), -10 * math.sin(th + math.rad(90)) },
			LeftShoulder = { 5, 0, -9 + sway },
			LeftElbow = { 14, 0, 0 },
			LeftWrist = { 10, 0, 0 },
			RightShoulder = { 5, 0, 9 + sway },
			RightElbow = { 14, 0, 0 },
			RightWrist = { 10, 0, 0 },
		}
	)
end
Clips.Stunned = Clip({
	Length = 1.4,
	Loop = true,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.1,
	Keys = { K(0, stunnedKey(0)), K(0.35, stunnedKey(1)), K(0.7, stunnedKey(2)), K(1.05, stunnedKey(3)) },
})

-- Under heavy (blue) gravity: crushed low, knees buckling, arms pressed down, trembling.
local function heavy(k: number): Pose
	return Merge(ST({ Drop = 0.36 + k * 0.05, Pitch = -12, Left = { X = -0.12, Out = 16 }, Right = { X = 0.12, Out = 16 } }), {
		Waist = { -16 - k * 3, 0, k * 1.5 },
		Neck = { 18 + k * 3, 0, -k * 2 },
		LeftShoulder = { 18, 0, -16 + k * 3 },
		LeftElbow = { 28, 0, 0 },
		LeftWrist = { -10, 0, 0 },
		RightShoulder = { 18, 0, 16 - k * 2 },
		RightElbow = { 28, 0, 0 },
		RightWrist = { -10, 0, 0 },
	})
end
Clips.BlueHeavy = Clip({
	Length = 0.6,
	Loop = true,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.12,
	Keys = { K(0, heavy(0)), K(0.15, heavy(1)), K(0.3, heavy(0.2)), K(0.45, heavy(0.9)) },
})

-- Crawl on hands and knees (downed). Phase advances with crawl speed; frozen when still.
local function crawl(k: number): Pose
	-- k = -1..1: left arm / right knee forward at k = 1
	return {
		Root = { -72, 3 * k, -4 * k, 0, -0.84, 0.22 },
		Waist = { -12, -5 * k, 2 * k },
		Neck = { 58, 4 * k, 0 },
		LeftShoulder = { 96 + 16 * k, 0, -8 },
		LeftElbow = { 10 + 8 * math.max(0, -k), 0, 0 },
		LeftWrist = { -55, 0, 0 },
		RightShoulder = { 96 - 16 * k, 0, 8 },
		RightElbow = { 10 + 8 * math.max(0, k), 0, 0 },
		RightWrist = { -55, 0, 0 },
		LeftHip = { 78 - 10 * k, 0, -8 },
		LeftKnee = { -94, 0, 0 },
		LeftAnkle = { -30, 0, 0 },
		RightHip = { 78 + 10 * k, 0, 8 },
		RightKnee = { -94, 0, 0 },
		RightAnkle = { -30, 0, 0 },
	}
end
Clips.Downed = Clip({
	Length = 1.8,
	Loop = true,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.25,
	Stride = 2.5,
	Keys = { K(0, crawl(1)), K(0.45, crawl(0)), K(0.9, crawl(-1)), K(1.35, crawl(0)) },
	Events = { { t = 0, Name = "Step" }, { t = 0.9, Name = "Step" } },
})

-- Lazy block: right palm up in front of the face, left hand stays in the pocket.
local BLOCK = Merge(L_POCKET, {
	Waist = { -2, -8, 0 },
	Neck = { 2, 6, 2 },
}, reach("Right", V3(0.25, 3.55, -1.45), nil, V3(1, -0.6, 0), { -25, 0, 0 }))
Clips.Block = Clip({
	Length = 1.2,
	Loop = true,
	Priority = 2,
	Mask = "Upper",
	FadeIn = 0.07,
	Keys = {
		K(0, BLOCK),
		K(0.6, Merge(BLOCK, reach("Right", V3(0.27, 3.5, -1.43), nil, V3(1, -0.6, 0), { -22, 0, 0 }), { Waist = { -2.5, -7, 0 } })),
	},
})

Clips.Parry = Clip({
	Length = 0.45,
	Priority = 3,
	Mask = "Upper",
	FadeIn = 0.02,
	Keys = {
		K(0, BLOCK),
		K(0.07, Merge(BLOCK, { RightShoulder = { 70, 0, 48 }, RightElbow = { 38, 0, 0 }, RightWrist = { 0, 0, -22 }, Waist = { -2, -18, 0 } }), "Back", "Out"),
		K(0.2, Merge(BLOCK, { RightShoulder = { 66, 0, 52 }, RightElbow = { 42, 0, 0 }, RightWrist = { 0, 0, -18 }, Waist = { -2, -16, 0 } })),
		K(0.45, stand(), "Sine", "InOut"),
	},
	Events = { { t = 0.07, Name = "Hit" } },
})

Clips.Hit = Clip({
	Length = 0.42,
	Priority = 3,
	FadeIn = 0.02,
	FadeOut = 0.15,
	Keys = {
		K(0, STAND),
		K(0.05, Merge(stance(0.06, 7, 0, 0, 0.1), {
			Waist = { 10, 0, 3 },
			Neck = { 15, 0, -5 },
			LeftShoulder = { -10, 0, -22 },
			LeftElbow = { 35, 0, 0 },
			LeftWrist = { 15, 0, 0 },
			RightShoulder = { -10, 0, 22 },
			RightElbow = { 35, 0, 0 },
			RightWrist = { 15, 0, 0 },
		}), "Quad", "Out"),
		K(0.17, Merge(stance(0.05, -3), {
			Waist = { -6, 0, -1 },
			Neck = { -4, 0, 2 },
			LeftShoulder = { 6, 0, -8 },
			LeftElbow = { 20, 0, 0 },
			RightShoulder = { 6, 0, 8 },
			RightElbow = { 20, 0, 0 },
		}), "Sine", "Out"),
		K(0.42, STAND, "Sine", "InOut"),
	},
})

local KNEEL = {
	Root = { -8, 0, 0, 0, -0.66, 0.12 },
	LeftHip = { 8, 0, -6 },
	LeftKnee = { -92, 0, 0 },
	LeftAnkle = { -55, 0, 0 },
	RightHip = { 8, 0, 6 },
	RightKnee = { -92, 0, 0 },
	RightAnkle = { -55, 0, 0 },
}
Clips.Death = Clip({
	Length = 1.6,
	Priority = 4,
	Hold = true,
	FullBody = true,
	FadeIn = 0.05,
	Keys = {
		K(0, STAND),
		K(0.12, Merge(stance(0.05, 6), {
			Waist = { 8, 0, 4 },
			Neck = { 16, 0, -6 },
			LeftShoulder = { -5, 0, -25 },
			LeftElbow = { 30, 0, 0 },
			RightShoulder = { -5, 0, 25 },
			RightElbow = { 30, 0, 0 },
		}), "Quad", "Out"),
		K(0.45, Merge(ST({ Drop = 0.45, Pitch = -8, Left = { X = -0.1, Z = -0.05 }, Right = { X = 0.1, Z = 0.05 } }), {
			Waist = { -16, 0, 3 },
			Neck = { -14, 0, 6 },
			LeftShoulder = { 10, 0, -6 },
			LeftElbow = { 10, 0, 0 },
			RightShoulder = { 10, 0, 6 },
			RightElbow = { 10, 0, 0 },
		}), "Quad", "In"),
		K(0.75, Merge(KNEEL, {
			Waist = { -20, 0, 4 },
			Neck = { -20, 0, 8 },
			LeftShoulder = { 14, 0, -4 },
			LeftElbow = { 8, 0, 0 },
			RightShoulder = { 14, 0, 4 },
			RightElbow = { 8, 0, 0 },
		}), "Bounce", "Out"),
		K(1.25, {
			Root = { -80, 0, 6, 0, -1.12, -0.3 },
			Waist = { -6, 0, 0 },
			Neck = { 12, 60, 0 },
			LeftShoulder = { 165, 0, -24 },
			LeftElbow = { 20, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 30, 0, 28 },
			RightElbow = { 12, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftHip = { 76, 0, -8 },
			LeftKnee = { -24, 0, 0 },
			LeftAnkle = { -40, 0, 0 },
			RightHip = { 80, 0, 10 },
			RightKnee = { -12, 0, 0 },
			RightAnkle = { -40, 0, 0 },
		}, "Quad", "In"),
		K(1.6, {
			Root = { -84, 0, 6, 0, -1.16, -0.3 },
			Waist = { -4, 0, 0 },
			Neck = { 10, 64, 0 },
			LeftShoulder = { 168, 0, -26 },
			LeftElbow = { 16, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 26, 0, 30 },
			RightElbow = { 10, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftHip = { 80, 0, -8 },
			LeftKnee = { -20, 0, 0 },
			LeftAnkle = { -42, 0, 0 },
			RightHip = { 84, 0, 10 },
			RightKnee = { -10, 0, 0 },
			RightAnkle = { -42, 0, 0 },
		}, "Bounce", "Out"),
	},
	Events = { { t = 0.75, Name = "Step" }, { t = 1.25, Name = "Hit" } },
})

---------------------------------------------------------------------------------------------------
-- Social
---------------------------------------------------------------------------------------------------

local THUMB = Merge(LEGS, L_POCKET, {
	Waist = { -3, 6, 0 },
	Neck = { 6, -6, 8 },
	RightShoulder = Limb(V3(0.75, -0.35, -0.55), V3(0, 1, 0)),
	RightElbow = { 100, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
local THUMB_UP = Merge(THUMB, stance(0.06), {
	RightShoulder = Limb(V3(0.75, -0.25, -0.6), V3(0, 1, 0)),
	RightElbow = { 112, 0, 0 },
	Neck = { 7, -6, 10 },
	Waist = { -2, 7, 0 },
})
Clips.Victory = Clip({
	Length = 2.4,
	Loop = true,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.25,
	Keys = { K(0, THUMB), K(0.6, THUMB_UP), K(1.2, THUMB), K(1.8, THUMB_UP) },
	Events = { { t = 0.6, Name = "Wink" } },
})

local WAVE = Merge(LEGS, L_POCKET, {
	Waist = { -2, -4, -3 },
	Neck = { 6, 6, -4 },
	RightShoulder = { 10, 0, 150 },
	RightElbow = { 0, 0, 28 },
	RightWrist = { 0, 0, 12 },
})
local WAVE2 = Merge(WAVE, { RightShoulder = { 10, 0, 144 }, RightElbow = { 0, 0, -18 }, RightWrist = { 0, 0, -10 } })
Clips.Emote_Wave = Clip({
	Length = 1.4,
	Loop = true,
	Priority = 2,
	FadeIn = 0.2,
	Keys = { K(0, WAVE), K(0.35, WAVE2), K(0.7, WAVE), K(1.05, WAVE2) },
})

local SHRUG_POSE = Merge(LEGS, pick(SHRUG, { "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist" }), {
	Waist = { 2, 0, 0 },
	Neck = { -6, 0, 12 },
})
Clips.Emote_Shrug = Clip({
	Length = 2,
	Priority = 2,
	FadeIn = 0.1,
	Keys = {
		K(0, STAND),
		K(0.25, Merge(SHRUG_POSE, stance(-0.02)), "Back", "Out"),
		K(0.8, Merge(SHRUG_POSE, { Neck = { -5, 0, 14 } })),
		K(1.4, Merge(SHRUG_POSE, { Neck = { -6, 0, 13 } })),
		K(2, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.25, Name = "Wink" } },
})

-- Sits on the floor, legs out, hands clasped behind the skull. Root drops to the ground.
local function sit(k: number): Pose
	return {
		Root = { 12 + k, 0, 0, 0, -1.28, 0.25 },
		Waist = { 10 + k * 2, 0, 0 },
		Neck = { -6 - k, 0, 6 },
		LeftHip = { 80, 0, -10 },
		LeftKnee = { -16, 0, 0 },
		LeftAnkle = { 10, 14, 0 },
		RightHip = { 76, 0, 12 },
		RightKnee = { -34, 0, 0 },
		RightAnkle = { 6, -14, 0 },
		LeftShoulder = Limb(V3(-0.32, -0.72, 0.62)),
		LeftElbow = { 4, 0, 0 },
		LeftWrist = { -60, 0, 0 },
		RightShoulder = Limb(V3(0.32, -0.72, 0.62)),
		RightElbow = { 4, 0, 0 },
		RightWrist = { -60, 0, 0 },
	}
end
Clips.Emote_Sit = Clip({
	Length = 3.2,
	Loop = true,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.4,
	FadeOut = 0.35,
	Keys = { K(0, sit(0)), K(1.6, sit(1)) },
})

local function laugh(k: number): Pose
	return Merge(stance(0.03 + k * 0.03), L_POCKET, {
		Waist = { 6 + k * 3, 0, 0 },
		Neck = { 16 + k * 4, 0, 4 - k * 2 },
	}, reach("Right", V3(0.28, 2.32 - k * 0.04, -0.82), nil, nil, { -10, 0, 0 }))
end
Clips.Emote_Laugh = Clip({
	Length = 0.9,
	Loop = true,
	Priority = 2,
	FadeIn = 0.15,
	Keys = { K(0, laugh(0)), K(0.15, laugh(1)), K(0.3, laugh(0.1)), K(0.45, laugh(0.9)), K(0.6, laugh(0)), K(0.75, laugh(0.8)) },
})

Clips.Wink = Clip({
	Length = 0.8,
	Priority = 2,
	Mask = "Torso",
	FadeIn = 0.06,
	Keys = {
		K(0, { Waist = { -5, 0, 0 }, Neck = { 4, 0, 3 } }),
		K(0.12, { Waist = { -5, 3, -1 }, Neck = { 6, 8, 12 } }, "Back", "Out"),
		K(0.55, { Waist = { -5, 3, -1 }, Neck = { 6, 7, 11 } }),
		K(0.8, { Waist = { -5, 0, 0 }, Neck = { 4, 0, 3 } }, "Sine", "InOut"),
	},
	Events = { { t = 0.12, Name = "Wink" } },
})

-- Idle fidgets (AnimController plays one now and then while idle)
Clips.Idle_Look = Clip({
	Length = 2.6,
	Priority = 1,
	Mask = "Torso",
	FadeIn = 0.3,
	FadeOut = 0.4,
	Keys = {
		K(0, TORSO),
		K(0.5, { Waist = { -5, 8, 0 }, Neck = { 5, 32, 4 } }, "Sine", "InOut"),
		K(1.1, { Waist = { -5, 8, 0 }, Neck = { 4, 30, 5 } }),
		K(1.7, { Waist = { -5, -6, 0 }, Neck = { 6, -26, 1 } }, "Sine", "InOut"),
		K(2.2, { Waist = { -5, -6, 0 }, Neck = { 5, -24, 2 } }),
		K(2.6, TORSO, "Sine", "InOut"),
	},
})

Clips.Idle_Stretch = Clip({
	Length = 2.6,
	Priority = 1,
	FadeIn = 0.25,
	FadeOut = 0.3,
	Keys = {
		K(0, STAND),
		K(0.6, Merge(stance(-0.03, 4), {
			Waist = { 8, 0, 0 },
			Neck = { 18, 0, -4 },
			LeftShoulder = { 168, 0, 14 },
			LeftElbow = { 40, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 168, 0, -14 },
			RightElbow = { 40, 0, 0 },
			RightWrist = { 0, 0, 0 },
		}), "Sine", "InOut"),
		K(1.4, Merge(stance(-0.05, 5), {
			Waist = { 10, 0, 2 },
			Neck = { 20, 0, -6 },
			LeftShoulder = { 172, 0, 8 },
			LeftElbow = { 30, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 172, 0, -8 },
			RightElbow = { 30, 0, 0 },
			RightWrist = { 0, 0, 0 },
		})),
		K(2.6, STAND, "Sine", "InOut"),
	},
})

---------------------------------------------------------------------------------------------------
-- Casting: hand whips out of the pocket (anticipation -> Back snap -> hold -> lazy return)
---------------------------------------------------------------------------------------------------

Clips.Cast = Clip({
	Length = 0.8,
	Priority = 2,
	FadeIn = 0.04,
	FadeOut = 0.15,
	Keys = {
		K(0, STAND),
		K(0.08, stand({ RightShoulder = { -20, 0, -4 }, RightElbow = { 62, 0, 0 }, RightWrist = { 10, 0, 0 }, Waist = { -5, -10, 0 }, Neck = { 4, 8, 3 } }), "Quad", "Out"),
		K(0.19, stand({ RightShoulder = Limb(V3(0.62, 0.28, -0.73)), RightElbow = { 8, 0, 0 }, RightWrist = { -22, 0, -10 }, Waist = { -6, 14, 0 }, Neck = { 6, -10, 2 } }), "Back", "Out"),
		K(0.42, stand({ RightShoulder = Limb(V3(0.66, 0.24, -0.71)), RightElbow = { 12, 0, 0 }, RightWrist = { -18, 0, -10 }, Waist = { -6, 12, 0 }, Neck = { 6, -9, 3 } })),
		K(0.8, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.19, Name = "Release" } },
})

Clips.CastUp = Clip({
	Length = 0.95,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.05,
	Keys = {
		K(0, STAND),
		K(0.13, Merge(stance(0.16, -6), {
			Waist = { -12, 0, 0 },
			Neck = { -6, 0, 0 },
			LeftShoulder = { -24, 0, -10 },
			LeftElbow = { 40, 0, 0 },
			LeftWrist = { 10, 0, 0 },
			RightShoulder = { -24, 0, 10 },
			RightElbow = { 40, 0, 0 },
			RightWrist = { 10, 0, 0 },
		}), "Quad", "Out"),
		K(0.28, Merge(ST({ Drop = -0.05, Pitch = 3, Left = { X = -0.08, Toe = -12, Y = 0.04 }, Right = { X = 0.08, Toe = -12, Y = 0.04 } }), {
			Waist = { 8, 0, 0 },
			Neck = { 22, 0, 0 },
			LeftShoulder = { 165, 0, -25 },
			LeftElbow = { 8, 0, 0 },
			LeftWrist = { -10, 0, 0 },
			RightShoulder = { 165, 0, 25 },
			RightElbow = { 8, 0, 0 },
			RightWrist = { -10, 0, 0 },
		}), "Back", "Out"),
		K(0.58, Merge(stance(0, 3), {
			Waist = { 7, 0, 0 },
			Neck = { 20, 0, 0 },
			LeftShoulder = { 160, 0, -28 },
			LeftElbow = { 12, 0, 0 },
			LeftWrist = { -8, 0, 0 },
			RightShoulder = { 160, 0, 28 },
			RightElbow = { 12, 0, 0 },
			RightWrist = { -8, 0, 0 },
		})),
		K(0.95, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.28, Name = "Release" } },
})

local PUSH = Merge(ST({ Drop = 0.1, Pitch = -5, Left = { Z = -0.34, Toe = 4 }, Right = { Z = 0.14, Toe = -8, Out = 14 } }), L_POCKET, {
	Waist = { -8, -12, 0 },
	Neck = { 8, 10, 2 },
	RightShoulder = { 88, 0, 2 },
	RightElbow = { 6, 0, 0 },
	RightWrist = { -28, 0, 0 },
})
Clips.CastForward = Clip({
	Length = 0.85,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.04,
	Keys = {
		K(0, STAND),
		K(0.1, stand({ RightShoulder = { -28, 0, 14 }, RightElbow = { 92, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { -4, 16, 0 }, Neck = { 4, -10, 3 } }), "Quad", "Out"),
		K(0.24, PUSH, "Back", "Out"),
		K(0.5, Merge(PUSH, { RightShoulder = { 86, 0, 4 }, RightElbow = { 10, 0, 0 } })),
		K(0.85, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.24, Name = "Release" }, { t = 0.24, Name = "Step" } },
})

-- Gaster Blaster: the arm rises out to the side (the skull forms), holds while it charges, then sweeps
-- forward at the aim to fire.
local SUMMON_UP = Merge(LEGS, L_POCKET, {
	Waist = { -4, 8, 4 },
	Neck = { 3, -6, 0 },
	RightShoulder = { 20, 0, 96 },
	RightElbow = { 14, 0, 0 },
	RightWrist = { 0, 0, -12 },
})
Clips.Summon = Clip({
	Length = 1.15,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.05,
	Keys = {
		K(0, STAND),
		K(0.14, stand({ RightShoulder = { 8, 0, 20 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 } }), "Quad", "Out"),
		K(0.34, SUMMON_UP, "Back", "Out"),
		K(0.68, Merge(SUMMON_UP, { RightShoulder = { 26, 0, 106 }, Neck = { 4, -8, -2 } })),
		K(0.78, Merge(LEGS, L_POCKET, {
			Waist = { -7, -10, 0 },
			Neck = { 5, 8, 2 },
			RightShoulder = { 86, 0, 8 },
			RightElbow = { 6, 0, 0 },
			RightWrist = { -20, 0, 0 },
		}), "Back", "Out"),
		K(1.15, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.34, Name = "Summon" }, { t = 0.78, Name = "Release" } },
})

local POINT = Merge(LEGS, L_POCKET, {
	Waist = { -5, -10, 0 },
	Neck = { 5, 8, 2 },
	RightShoulder = { 90, 0, 0 },
	RightElbow = { 2, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
Clips.Point = Clip({
	Length = 0.95,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.04,
	Keys = {
		K(0, STAND),
		K(0.12, stand({ RightShoulder = { 30, 0, -6 }, RightElbow = { 90, 0, 0 }, Waist = { -5, 6, 0 } }), "Quad", "Out"),
		K(0.3, POINT, "Back", "Out"),
		K(0.62, Merge(POINT, { RightShoulder = { 92, 0, 1 } })),
		K(0.95, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.3, Name = "Release" } },
})

-- Hand rises high, trembles, then SLAMS down (HandDown): bones erupt on "Hit".
local SLAM_UP = Merge(stance(-0.03, 3), L_POCKET, {
	Waist = { 6, 0, -4 },
	Neck = { 14, -4, 0 },
	RightShoulder = { 150, 0, 30 },
	RightElbow = { 28, 0, 0 },
	RightWrist = { -10, 0, 0 },
})
local SLAM_DOWN = Merge(ST({ Drop = 0.3, Pitch = -8, Left = { Z = -0.18, X = -0.06 }, Right = { Z = 0.18, X = 0.08, Toe = -6 } }), L_POCKET, {
	Waist = { -16, -6, 0 },
	Neck = { -4, 4, 0 },
	RightShoulder = { 34, 0, 26 },
	RightElbow = { 8, 0, 0 },
	RightWrist = { -24, 0, 0 },
})
Clips.Slam = Clip({
	Length = 1.05,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.05,
	Keys = {
		K(0, STAND),
		K(0.25, SLAM_UP, "Back", "Out"),
		K(0.62, Merge(SLAM_UP, { RightShoulder = { 154, 0, 28 }, Neck = { 15, -4, 0 } })),
		K(0.72, SLAM_DOWN, "Expo", "In"),
		K(0.84, Merge(SLAM_DOWN, ST({ Drop = 0.24, Pitch = -6 })), "Sine", "Out"),
		K(1.05, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.72, Name = "Hit" } },
})

local THROW_COCK = Merge(ST({ Drop = 0.08, Pitch = 2, Left = { Z = -0.3 }, Right = { Z = 0.18, Out = 18 } }), L_POCKET, {
	Waist = { 2, -24, 4 },
	Neck = { 4, 18, 0 },
	RightShoulder = Limb(V3(0.95, 0.12, 0.28), V3(0, 1, 0.4)),
	RightElbow = { 105, 0, 0 },
	RightWrist = { 10, 0, 0 },
})
local THROW_REL = Merge(ST({ Drop = 0.14, Pitch = -6, Left = { Z = -0.34, Toe = 4 }, Right = { Z = 0.2, Toe = -16, Out = 18 } }), L_POCKET, {
	Waist = { -10, 22, 0 },
	Neck = { 6, -12, 0 },
	RightShoulder = { 108, 0, 20 },
	RightElbow = { 10, 0, 0 },
	RightWrist = { -30, 0, 0 },
})
Clips.Throw = Clip({
	Length = 0.75,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.04,
	Keys = {
		K(0, STAND),
		K(0.15, THROW_COCK, "Quad", "Out"),
		K(0.26, THROW_REL, "Back", "Out"),
		K(0.42, Merge(THROW_REL, { RightShoulder = { 62, 0, -22 }, RightElbow = { 30, 0, 0 }, Waist = { -12, 28, 0 } }), "Sine", "Out"),
		K(0.75, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.26, Name = "Release" }, { t = 0.26, Name = "Step" } },
})

-- Spins on his heel, hands in the pockets (lazy), one foot lifted.
local function spin(angle: number, lift: number): Pose
	local p = Merge(ST({ Drop = 0.05, Pitch = 1, Left = { Y = lift, Z = -0.05, X = 0.12 }, Right = { X = 0.02, Toe = -6 } }), ARMS, {
		Waist = { -5, 0, 0 },
		Neck = { 4, 0, 3 },
	})
	p.Root[2] = angle
	return p
end
Clips.Spin = Clip({
	Length = 0.85,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.05,
	Keys = {
		K(0, spin(0, 0)),
		K(0.1, spin(-14, 0.08), "Quad", "Out"),
		K(0.33, spin(180, 0.3), "Quad", "In"),
		K(0.56, spin(360, 0.2), "Quad", "Out"),
		K(0.85, spin(360, 0), "Sine", "InOut"),
	},
	Events = { { t = 0.33, Name = "Hit" } },
})

local LEAP_CROUCH = Merge(ST({ Drop = 0.38, Pitch = -14, Left = { X = -0.08 }, Right = { X = 0.08 } }), {
	Waist = { -14, 0, 0 },
	Neck = { 18, 0, 0 },
	LeftShoulder = { -30, 0, -14 },
	LeftElbow = { 30, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = { -30, 0, 14 },
	RightElbow = { 30, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
local LEAP_UP = Merge(ST({ Drop = -0.06, Pitch = -4, Left = { Y = 0.1, Toe = -35 }, Right = { Y = 0.1, Toe = -35 } }), {
	Waist = { 4, 0, 0 },
	Neck = { 8, 0, 0 },
	LeftShoulder = { 150, 0, -20 },
	LeftElbow = { 14, 0, 0 },
	RightShoulder = { 150, 0, 20 },
	RightElbow = { 14, 0, 0 },
})
local LEAP_TUCK = Merge(ST({ Drop = -0.08, Pitch = -6, Left = { Y = 0.5, Z = -0.15, Toe = 0 }, Right = { Y = 0.38, Z = 0.05, Toe = -8 } }), {
	Waist = { -10, 0, 0 },
	Neck = { 10, 0, 0 },
	LeftShoulder = { 40, 0, -40 },
	LeftElbow = { 50, 0, 0 },
	RightShoulder = { 40, 0, 40 },
	RightElbow = { 50, 0, 0 },
})
Clips.Leap = Clip({
	Length = 1.05,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.05,
	Keys = {
		K(0, STAND),
		K(0.2, LEAP_CROUCH, "Quad", "Out"),
		K(0.32, LEAP_UP, "Back", "Out"),
		K(0.62, LEAP_TUCK, "Sine", "InOut"),
		K(0.86, Merge(LEAP_CROUCH, ST({ Drop = 0.28, Pitch = -10 })), "Quad", "In"),
		K(1.05, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.32, Name = "Release" }, { t = 0.86, Name = "Hit" } },
})

-- Shoulder barge, hands in the pockets (Sans can't be bothered to use them).
local CHARGE_POSE = Merge(ST({ Drop = 0.2, Pitch = -18, Left = { Z = -0.4, Toe = 8 }, Right = { Z = 0.48, Toe = -30 } }), ARMS, {
	Waist = { -12, -22, 0 },
	Neck = { 22, 18, 0 },
})
Clips.Charge = Clip({
	Length = 0.75,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, STAND),
		K(0.1, Merge(stance(0.14, -4), ARMS, { Waist = { -4, 12, 0 }, Neck = { 6, -8, 0 } }), "Quad", "Out"),
		K(0.18, CHARGE_POSE, "Back", "Out"),
		K(0.52, Merge(CHARGE_POSE, { Waist = { -12, -20, 0 } })),
		K(0.75, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.18, Name = "Release" }, { t = 0.18, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Melee (a conjured bone in the right hand). Chain: Slash1 jab -> Slash2 backhand -> Slash3 rising swing
-- -> Slash4 overhead smash (finisher). Each clip starts where the previous one ended.
---------------------------------------------------------------------------------------------------

local SLASH_LEGS_A = ST({ Drop = 0.08, Pitch = -3, Left = { Z = -0.22, X = -0.04, Out = 8 }, Right = { Z = 0.12, X = 0.06, Out = 16 } })
local SLASH_LEGS_B = ST({ Drop = 0.1, Pitch = -4, Left = { Z = 0.1, X = -0.08, Out = 12 }, Right = { Z = -0.16, X = 0.04, Out = 8 } })

local JAB_END = Merge(SLASH_LEGS_A, L_POCKET, {
	Waist = { -6, 12, 0 },
	Neck = { 5, -8, 2 },
	RightShoulder = { 70, 0, -12 },
	RightElbow = { 40, 0, 0 },
	RightWrist = { -10, 0, 0 },
})
Clips.Slash1 = Clip({
	Length = 0.42,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, STAND),
		K(0.06, stand({ RightShoulder = { -24, 0, 10 }, RightElbow = { 96, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { -5, -14, 0 }, Neck = { 4, 10, 3 } }), "Quad", "Out"),
		K(0.12, Merge(SLASH_LEGS_A, L_POCKET, {
			Waist = { -7, 16, 0 },
			Neck = { 6, -11, 2 },
			RightShoulder = { 88, 0, -4 },
			RightElbow = { 4, 0, 0 },
			RightWrist = { -8, 0, 0 },
		}), "Back", "Out"),
		K(0.22, Merge(SLASH_LEGS_A, L_POCKET, {
			Waist = { -7, 15, 0 },
			Neck = { 6, -10, 2 },
			RightShoulder = { 84, 0, -6 },
			RightElbow = { 10, 0, 0 },
			RightWrist = { -8, 0, 0 },
		})),
		K(0.42, JAB_END, "Sine", "InOut"),
	},
	Events = { { t = 0.12, Name = "Hit" } },
})

local BACKHAND_END = Merge(SLASH_LEGS_B, L_POCKET, {
	Waist = { -6, -16, 0 },
	Neck = { 5, 12, 2 },
	RightShoulder = { 64, 0, 62 },
	RightElbow = { 30, 0, 0 },
	RightWrist = { 0, 0, -10 },
})
Clips.Slash2 = Clip({
	Length = 0.42,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, JAB_END),
		K(0.06, Merge(SLASH_LEGS_A, L_POCKET, {
			Waist = { -6, 24, 0 },
			Neck = { 5, -16, 2 },
			RightShoulder = { 60, 0, -58 },
			RightElbow = { 92, 0, 0 },
			RightWrist = { 0, 0, 12 },
		}), "Quad", "Out"),
		K(0.12, Merge(SLASH_LEGS_B, L_POCKET, {
			Waist = { -7, -22, 0 },
			Neck = { 6, 16, 2 },
			RightShoulder = { 80, 0, 74 },
			RightElbow = { 10, 0, 0 },
			RightWrist = { 0, 0, -18 },
		}), "Back", "Out"),
		K(0.22, Merge(SLASH_LEGS_B, L_POCKET, {
			Waist = { -7, -21, 0 },
			Neck = { 6, 15, 2 },
			RightShoulder = { 76, 0, 80 },
			RightElbow = { 14, 0, 0 },
			RightWrist = { 0, 0, -16 },
		})),
		K(0.42, BACKHAND_END, "Sine", "InOut"),
	},
	Events = { { t = 0.12, Name = "Hit" } },
})

local RISE_END = Merge(SLASH_LEGS_A, L_POCKET, {
	Waist = { -2, 10, 0 },
	Neck = { 8, -6, 2 },
	RightShoulder = { 130, 0, 30 },
	RightElbow = { 40, 0, 0 },
	RightWrist = { -10, 0, 0 },
})
Clips.Slash3 = Clip({
	Length = 0.45,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, BACKHAND_END),
		K(0.07, Merge(ST({ Drop = 0.2, Pitch = -10, Left = { Z = -0.1 }, Right = { Z = 0.1 } }), L_POCKET, {
			Waist = { -12, 14, 0 },
			Neck = { 12, -8, 2 },
			RightShoulder = { 10, 0, -30 },
			RightElbow = { 30, 0, 0 },
			RightWrist = { 10, 0, 0 },
		}), "Quad", "Out"),
		K(0.13, Merge(ST({ Drop = 0.02, Pitch = 2, Left = { Z = -0.22, Toe = 2 }, Right = { Z = 0.12, Toe = -14 } }), L_POCKET, {
			Waist = { 2, -12, 0 },
			Neck = { 10, 8, 2 },
			RightShoulder = { 140, 0, 34 },
			RightElbow = { 10, 0, 0 },
			RightWrist = { -12, 0, 0 },
		}), "Back", "Out"),
		K(0.25, Merge(SLASH_LEGS_A, L_POCKET, {
			Waist = { 1, -10, 0 },
			Neck = { 9, 7, 2 },
			RightShoulder = { 138, 0, 36 },
			RightElbow = { 16, 0, 0 },
			RightWrist = { -12, 0, 0 },
		})),
		K(0.45, RISE_END, "Sine", "InOut"),
	},
	Events = { { t = 0.13, Name = "Hit" } },
})

Clips.Slash4 = Clip({
	Length = 0.62,
	Priority = 2,
	FullBody = true,
	Aim = "Right",
	FadeIn = 0.04,
	FadeOut = 0.15,
	Keys = {
		K(0, RISE_END),
		K(0.13, Merge(ST({ Drop = -0.04, Pitch = 4, Left = { Z = -0.1, Toe = -6 }, Right = { Z = 0.1, Toe = -10 } }), L_POCKET, {
			Waist = { 8, 6, 0 },
			Neck = { 12, -4, 0 },
			RightShoulder = { 168, 0, 10 },
			RightElbow = { 70, 0, 0 },
			RightWrist = { 10, 0, 0 },
		}), "Quad", "Out"),
		K(0.21, Merge(ST({ Drop = 0.32, Pitch = -12, Left = { Z = -0.3, Toe = 4 }, Right = { Z = 0.22, Toe = -14 } }), L_POCKET, {
			Waist = { -18, -6, 0 },
			Neck = { 14, 4, 0 },
			RightShoulder = { 40, 0, 6 },
			RightElbow = { 6, 0, 0 },
			RightWrist = { -24, 0, 0 },
		}), "Expo", "In"),
		K(0.36, Merge(ST({ Drop = 0.26, Pitch = -9, Left = { Z = -0.3, Toe = 4 }, Right = { Z = 0.22, Toe = -12 } }), L_POCKET, {
			Waist = { -15, -5, 0 },
			Neck = { 12, 4, 0 },
			RightShoulder = { 44, 0, 8 },
			RightElbow = { 10, 0, 0 },
			RightWrist = { -20, 0, 0 },
		}), "Sine", "Out"),
		K(0.62, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.21, Name = "Hit" }, { t = 0.21, Name = "Step" } },
})

-- Punches: lazy pokes, alternating hands; Punch4 a two-handed shove.
local function punch(side: string, wind: Pose, strike: Pose, hitT: number, length: number): A.Clip
	local p = Clip({
		Length = length,
		Priority = 2,
		FadeIn = 0.03,
		FadeOut = 0.12,
		Keys = { K(0, STAND), K(hitT * 0.5, wind, "Quad", "Out"), K(hitT, strike, "Back", "Out"), K(hitT + 0.1, strike), K(length, STAND, "Sine", "InOut") },
		Events = { { t = hitT, Name = "Hit" } },
	})
	return if side == "Left" then A.MirrorClip(p) else p
end
local POKE_WIND = stand({ RightShoulder = { -10, 0, 8 }, RightElbow = { 100, 0, 0 }, Waist = { -5, -10, 0 }, Neck = { 4, 8, 3 } })
local POKE = Merge(SLASH_LEGS_A, L_POCKET, {
	Waist = { -7, 14, 0 },
	Neck = { 5, -10, 3 },
	RightShoulder = { 86, 0, -6 },
	RightElbow = { 6, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
local HOOK_WIND = stand({ RightShoulder = { 50, 0, 70 }, RightElbow = { 90, 0, 0 }, Waist = { -5, -16, 0 } })
local HOOK = Merge(SLASH_LEGS_A, L_POCKET, {
	Waist = { -7, 24, 0 },
	Neck = { 5, -14, 3 },
	RightShoulder = { 84, 0, -8 },
	RightElbow = { 92, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
Clips.Punch1 = punch("Right", POKE_WIND, POKE, 0.1, 0.38)
Clips.Punch2 = punch("Left", POKE_WIND, POKE, 0.1, 0.38)
Clips.Punch3 = punch("Right", HOOK_WIND, HOOK, 0.12, 0.42)
Clips.Punch4 = Clip({
	Length = 0.6,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	FadeOut = 0.15,
	Keys = {
		K(0, STAND),
		K(0.1, Merge(stance(0.14, 0), {
			Waist = { -2, 0, 0 },
			Neck = { 6, 0, 0 },
			LeftShoulder = { 30, 0, -10 },
			LeftElbow = { 110, 0, 0 },
			LeftWrist = { -20, 0, 0 },
			RightShoulder = { 30, 0, 10 },
			RightElbow = { 110, 0, 0 },
			RightWrist = { -20, 0, 0 },
		}), "Quad", "Out"),
		K(0.17, Merge(ST({ Drop = 0.16, Pitch = -10, Left = { Z = -0.34, Toe = 4 }, Right = { Z = 0.2, Toe = -16 } }), {
			Waist = { -10, 0, 0 },
			Neck = { 10, 0, 0 },
			LeftShoulder = { 84, 0, 8 },
			LeftElbow = { 8, 0, 0 },
			LeftWrist = { -40, 0, 0 },
			RightShoulder = { 84, 0, -8 },
			RightElbow = { 8, 0, 0 },
			RightWrist = { -40, 0, 0 },
		}), "Back", "Out"),
		K(0.32, Merge(ST({ Drop = 0.14, Pitch = -8, Left = { Z = -0.34, Toe = 4 }, Right = { Z = 0.2, Toe = -14 } }), {
			Waist = { -9, 0, 0 },
			Neck = { 9, 0, 0 },
			LeftShoulder = { 80, 0, 8 },
			LeftElbow = { 14, 0, 0 },
			LeftWrist = { -36, 0, 0 },
			RightShoulder = { 80, 0, -8 },
			RightElbow = { 14, 0, 0 },
			RightWrist = { -36, 0, 0 },
		})),
		K(0.6, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.17, Name = "Hit" } },
})

-- Kicks: hands stay in the pockets. Kick1 front poke, Kick2 sweep, Kick3 big sole kick.
local function kickClip(legs: Pose, hitT: number, length: number, torso: Pose, wind: Pose): A.Clip
	return Clip({
		Length = length,
		Priority = 2,
		FullBody = true,
		FadeIn = 0.03,
		FadeOut = 0.14,
		Keys = {
			K(0, STAND),
			K(hitT * 0.55, Merge(wind, ARMS), "Quad", "Out"),
			K(hitT, Merge(legs, ARMS, torso), "Back", "Out"),
			K(hitT + 0.12, Merge(legs, ARMS, torso)),
			K(length, STAND, "Sine", "InOut"),
		},
		Events = { { t = hitT, Name = "Hit" } },
	})
end
local KICK_WIND = Merge(ST({ Drop = 0.08, Pitch = 4, Left = { X = -0.04 }, Right = { Y = 0.3, Z = 0.1, Toe = -10 } }), TORSO)
Clips.Kick1 = kickClip(
	Merge(ST({ Drop = 0.04, Pitch = 10, Left = { X = -0.02, Out = 10 } }), {
		RightHip = { 82, 0, 4 },
		RightKnee = { -8, 0, 0 },
		RightAnkle = { 10, 0, 0 },
	}),
	0.13,
	0.45,
	{ Waist = { -2, 0, 0 }, Neck = { -4, 0, 4 } },
	KICK_WIND
)
Clips.Kick2 = kickClip(
	Merge(ST({ Drop = 0.06, Pitch = 6, Roll = -8, Right = { X = 0.04, Out = 14 } }), {
		LeftHip = { 60, 0, -30 },
		LeftKnee = { -6, 0, 0 },
		LeftAnkle = { -20, 0, 0 },
	}),
	0.14,
	0.48,
	{ Waist = { -3, -16, 6 }, Neck = { -2, 14, 2 } },
	Merge(ST({ Drop = 0.08, Pitch = 2, Right = { X = 0.04 }, Left = { Y = 0.25, Z = 0.12, X = -0.1, Toe = -10 } }), TORSO)
)
Clips.Kick3 = kickClip(
	Merge(ST({ Drop = 0.02, Pitch = 16, Left = { X = -0.02, Toe = -8, Out = 12 } }), {
		RightHip = { 96, 0, 2 },
		RightKnee = { -4, 0, 0 },
		RightAnkle = { 30, 0, 0 },
	}),
	0.17,
	0.6,
	{ Waist = { -4, 4, 0 }, Neck = { -8, -2, 4 } },
	Merge(ST({ Drop = 0.14, Pitch = 2, Left = { X = -0.04 }, Right = { Y = 0.5, Z = -0.05, Toe = 0 } }), TORSO)
)

---------------------------------------------------------------------------------------------------
-- Misc actions
---------------------------------------------------------------------------------------------------

-- Finger gun.
local FINGER_GUN = Merge(LEGS, L_POCKET, {
	Waist = { -5, -8, 0 },
	Neck = { 5, 6, 3 },
	RightShoulder = { 90, 0, -2 },
	RightElbow = { 2, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
Clips.Shoot = Clip({
	Length = 0.42,
	Priority = 2,
	Aim = "Right",
	Mask = "Upper",
	FadeIn = 0.02,
	FadeOut = 0.15,
	Keys = {
		K(0, FINGER_GUN),
		K(0.04, Merge(FINGER_GUN, { RightShoulder = { 104, 0, -2 }, RightElbow = { 16, 0, 0 }, RightWrist = { 10, 0, 0 }, Waist = { -2, -8, 0 }, Neck = { 7, 6, 3 } }), "Expo", "Out"),
		K(0.16, FINGER_GUN, "Back", "Out"),
		K(0.42, FINGER_GUN),
	},
	Events = { { t = 0.02, Name = "Release" } },
})

-- Blows the "smoke" off the finger gun, back into the pocket.
Clips.Reload = Clip({
	Length = 1,
	Priority = 2,
	Mask = "Upper",
	FadeIn = 0.06,
	Keys = {
		K(0, FINGER_GUN),
		K(0.2, Merge(LEGS, L_POCKET, {
			Waist = { -5, -4, 0 },
			Neck = { -6, -4, 2 },
		}, reach("Right", V3(0.3, 3.62, -1.45), nil, V3(1, -1, 0), { -20, 0, 0 })), "Sine", "InOut"),
		K(0.62, Merge(LEGS, L_POCKET, {
			Waist = { -5, -4, 0 },
			Neck = { -7, -4, 3 },
		}, reach("Right", V3(0.28, 3.64, -1.42), nil, V3(1, -1, 0), { -20, 0, 0 }))),
		K(1, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.45, Name = "Release" } },
})

local HEAL_GATHER = Merge(stance(0.06), {
	Waist = { -6, 0, 0 },
	Neck = { -4, 0, 0 },
}, reach("Left", V3(-0.14, 2.75, -1.05), nil, nil, { -10, 0, 0 }), reach("Right", V3(0.14, 2.75, -1.05), nil, nil, { -10, 0, 0 }))
local HEAL_OPEN = Merge(stance(0), {
	Waist = { 4, 0, 0 },
	Neck = { 8, 0, 0 },
	LeftShoulder = { 60, 0, -50 },
	LeftElbow = { 20, 0, 0 },
	LeftWrist = { -20, 0, 0 },
	RightShoulder = { 60, 0, 50 },
	RightElbow = { 20, 0, 0 },
	RightWrist = { -20, 0, 0 },
})
Clips.Heal = Clip({
	Length = 1,
	Priority = 2,
	FadeIn = 0.06,
	Keys = {
		K(0, STAND),
		K(0.22, HEAL_GATHER, "Sine", "Out"),
		K(0.36, HEAL_OPEN, "Back", "Out"),
		K(0.66, Merge(HEAL_OPEN, { LeftShoulder = { 58, 0, -54 }, RightShoulder = { 58, 0, 54 } })),
		K(1, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.36, Name = "Release" } },
})

local GUARD = Merge(ST({ Drop = 0.18, Pitch = -4, Left = { X = -0.14, Out = 16 }, Right = { X = 0.14, Out = 16 } }), {
	Waist = { -6, 0, 0 },
	Neck = { 6, 0, 0 },
}, reach("Left", V3(0.62, 3.05, -1.0), nil, V3(-1, -0.3, 0)), reach("Right", V3(-0.62, 2.85, -1.08), nil, V3(1, -0.3, 0)))
Clips.Guard = Clip({
	Length = 0.85,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, STAND),
		K(0.15, GUARD, "Back", "Out"),
		K(0.55, Merge(GUARD, { Waist = { -7, 0, 0 } })),
		K(0.85, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.15, Name = "Release" } },
})

-- "C'mere." Lazy beckon with two finger curls and a head tilt.
local BECKON = Merge(LEGS, L_POCKET, {
	Waist = { -4, -6, 0 },
	Neck = { 4, 6, 10 },
	RightShoulder = { 54, 0, 8 },
	RightElbow = { 70, 0, 0 },
	RightWrist = { -20, 0, 0 },
})
local BECKON2 = Merge(BECKON, { RightElbow = { 96, 0, 0 }, RightWrist = { 30, 0, 0 } })
Clips.Taunt = Clip({
	Length = 1.3,
	Priority = 2,
	FadeIn = 0.06,
	Keys = {
		K(0, STAND),
		K(0.25, BECKON, "Back", "Out"),
		K(0.42, BECKON2, "Quad", "InOut"),
		K(0.58, BECKON, "Quad", "InOut"),
		K(0.75, BECKON2, "Quad", "InOut"),
		K(0.92, BECKON, "Quad", "InOut"),
		K(1.3, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.3, Name = "Release" } },
})

-- Verdict Box: the hand reaches out, palm open... and closes around the SOUL.
local VERDICT_REACH = Merge(stance(0.04, -2), L_POCKET, {
	Waist = { -8, -8, 0 },
	Neck = { 4, 6, 0 },
	RightShoulder = { 84, 0, 4 },
	RightElbow = { 10, 0, 0 },
	RightWrist = { -30, 0, 0 },
})
Clips.Verdict = Clip({
	Length = 1.25,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.05,
	Keys = {
		K(0, STAND),
		K(0.18, stand({ RightShoulder = { 30, 0, -8 }, RightElbow = { 80, 0, 0 } }), "Quad", "Out"),
		K(0.36, VERDICT_REACH, "Back", "Out"),
		K(0.48, Merge(VERDICT_REACH, { RightWrist = { 10, 0, 0 }, RightElbow = { 30, 0, 0 } }), "Expo", "Out"),
		K(0.8, Merge(VERDICT_REACH, { RightShoulder = { 70, 0, 0 }, RightElbow = { 60, 0, 0 }, RightWrist = { 10, 0, 0 }, Waist = { -4, -4, 0 } }), "Sine", "InOut"),
		K(1.25, STAND, "Sine", "InOut"),
	},
	Events = { { t = 0.48, Name = "Release" } },
})

return Clips
