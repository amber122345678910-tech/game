--!strict
-- Clips/Human: animation clips of the human family (fallen children; SPEC §8 format, see Anim/AnimMath
-- header for interpolation rules and the extension fields FullBody/Hold/FadeIn/FadeOut/Stride/Aim). [Lune-safe]
--
-- Personality: energetic child fighters. Idle is a springy, weapon-ready fighting stance (left foot
-- forward, weapon low in the RIGHT hand with the blade pointing at the enemy, left hand up as a guard).
-- Attacks: fast anticipation -> Back-eased snap -> short hold -> recover into the next combo start.
-- M1 chains alternate sides: Slash1 forehand R->L, Slash2 backhand L->R, Slash3 high diagonal R->L,
-- Slash4 overhead two-handed chop (finisher). Punch1 jab (L), Punch2 cross (R), Punch3 hook (L),
-- Punch4 uppercut (R). Kick1 front kick (R), Kick2 roundhouse (L), Kick3 turning high kick (R).
-- Locomotion cycles plant the LEFT foot at t = 0 and the RIGHT foot at Length/2 ("Step" markers).
-- Weapons extend along the hand axis, so the forearm/wrist direction is the blade direction.
--
-- Clips: Idle Walk Run WalkBack StrafeL StrafeR Jump Fall Land Dash Stunned Downed Block Parry Dodge Hit
--   Death Victory Emote_Wave Emote_Shrug Emote_Sit Emote_Laugh Cast CastUp CastForward Summon Point Slam
--   Throw Spin Leap Charge Slash1-4 Punch1-4 Kick1-3 Shoot Reload Heal Guard Taunt
--   extras: BlueHeavy Idle_Look Idle_Fidget

local A = require(script.Parent.Parent.AnimMath)

type Pose = A.Pose
type ClipKey = A.ClipKey

local Clip, Merge, MirrorPose, Limb = A.Clip, A.Merge, A.MirrorPose, A.Limb
local V3 = Vector3.new

local function ST(spec: A.StanceSpec): Pose
	return A.Stance("Human", spec)
end

local function reach(side: string, target: Vector3, wrist: { number }?, pole: Vector3?, spine: Pose?): Pose
	return A.Reach("Human", side, target, { Spine = spine, Pole = pole, Wrist = wrist })
end

local function K(t: number, pose: Pose, ease: string?, dir: string?): ClipKey
	return { t = t, Pose = pose, Ease = ease, Dir = dir }
end

local LOWER = { "Root", "Waist", "Neck", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local function lower(p: Pose): Pose
	local out: Pose = {}
	for _, n in LOWER do
		if p[n] then
			out[n] = table.clone(p[n])
		end
	end
	return out
end
-- mirror legs + spine only (arms are asymmetric: the right hand holds the weapon)
local function mirrorLower(p: Pose): Pose
	return MirrorPose(lower(p))
end

local Clips = {}

---------------------------------------------------------------------------------------------------
-- Stances & arms
---------------------------------------------------------------------------------------------------

local function readyLegs(drop: number, pitch: number?, roll: number?, shiftX: number?): Pose
	return ST({
		Drop = drop,
		Pitch = pitch or -4,
		Roll = roll or 0,
		Yaw = -14,
		Shift = V3(shiftX or 0, 0, 0),
		Left = { X = -0.06, Z = -0.22, Out = 6 },
		Right = { X = 0.1, Z = 0.22, Out = 28 },
	})
end
local function squareLegs(drop: number, pitch: number?): Pose
	return ST({ Drop = drop, Pitch = pitch or -2, Left = { X = -0.08, Out = 10 }, Right = { X = 0.08, Out = 10 } })
end

local WEAPON_LOW = reach("Right", V3(0.52, 2.6, -0.74), { -22, 0, 0 })
local GUARD_L = reach("Left", V3(-0.26, 2.95, -0.84), { -8, 0, 0 })
local READY_SPINE = { Waist = { -4, 12, 0 }, Neck = { 2, 4, 0 } }
local READY = Merge(readyLegs(0.16), READY_SPINE, WEAPON_LOW, GUARD_L)
local NEUTRAL = Merge(squareLegs(0.04), { Waist = { -2, 0, 0 }, Neck = { 1, 0, 0 } }, WEAPON_LOW, {
	LeftShoulder = { 4, 0, -6 },
	LeftElbow = { 18, 0, 0 },
	LeftWrist = { 0, 0, 0 },
})

---------------------------------------------------------------------------------------------------
-- Idle / locomotion
---------------------------------------------------------------------------------------------------

local function idleKey(drop: number, bob: number): Pose
	return Merge(readyLegs(drop, -4 - bob), {
		Waist = { -4 + bob * 1.5, 12, 0 },
		Neck = { 2 + bob * 0.5, 4, 0 },
	}, reach("Right", V3(0.52, 2.6 + bob * 0.03, -0.74), { -22 - bob * 4, 0, 0 }), reach("Left", V3(-0.26, 2.95 + bob * 0.03, -0.84), { -8, 0, 0 }))
end
-- Springy ready stance: two light bounces per cycle, the weapon tip bobbing with them.
Clips.Idle = Clip({
	Length = 1.6,
	Loop = true,
	Priority = 1,
	Keys = { K(0, idleKey(0.13, 0)), K(0.4, idleKey(0.19, 1)), K(0.8, idleKey(0.14, 0.1)), K(1.2, idleKey(0.2, 0.9)) },
})

-- Walk: arms swing against the legs; the weapon arm swings less and keeps the blade forward.
local W_CONTACT = ST({ Drop = 0.07, Pitch = -3, Yaw = -6, Left = { Z = -0.36, Toe = 14 }, Right = { Z = 0.32, Y = 0.02, Toe = -18 } })
local W_PASS = ST({
	Drop = -0.01,
	Pitch = -2,
	Roll = -2.5,
	Shift = V3(-0.05, 0, 0),
	Left = { Z = 0.02 },
	Right = { Z = -0.02, Y = 0.24, Toe = 4 },
})
local function walkArms(swing: number): Pose
	-- swing = +1: left arm back / weapon arm forward (left foot forward)
	return {
		LeftShoulder = { -16 * swing + 2, 0, -6 },
		LeftElbow = { 18 + 8 * math.max(0, -swing), 0, 0 },
		LeftWrist = { 0, 0, 0 },
		RightShoulder = { 26 + 10 * swing, 0, 8 },
		RightElbow = { 58 + 6 * swing, 0, 0 },
		RightWrist = { -14, 0, 0 },
	}
end
Clips.Walk = Clip({
	Length = 1,
	Loop = true,
	Priority = 1,
	Stride = 7.5,
	Keys = {
		K(0, Merge(W_CONTACT, { Waist = { -2, 9, 0 }, Neck = { 2, -3, 0 } }, walkArms(1))),
		K(0.25, Merge(W_PASS, { Waist = { -2, 2, 2.5 }, Neck = { 2, 0, -1 } }, walkArms(0))),
		K(0.5, Merge(mirrorLower(Merge(W_CONTACT, { Waist = { -2, 9, 0 }, Neck = { 2, -3, 0 } })), walkArms(-1))),
		K(0.75, Merge(mirrorLower(Merge(W_PASS, { Waist = { -2, 2, 2.5 }, Neck = { 2, 0, -1 } })), walkArms(0))),
	},
	Events = { { t = 0, Name = "Step" }, { t = 0.5, Name = "Step" } },
})

-- Run: athletic sprint, forward lean, pumping arms (weapon arm too), high knees.
local R_CONTACT = ST({ Drop = 0.14, Pitch = -12, Yaw = -9, Left = { Z = -0.48, Toe = 10 }, Right = { Z = 0.5, Y = 0.14, Toe = -32 } })
local R_FLIGHT = ST({
	Drop = -0.06,
	Pitch = -11,
	Yaw = -2,
	Roll = -2,
	Shift = V3(-0.04, 0, 0),
	Left = { Z = 0.18, Y = 0.12, Toe = -25 },
	Right = { Z = -0.22, Y = 0.5, Toe = 8 },
})
local function runArms(swing: number): Pose
	return {
		LeftShoulder = { -36 * swing + 6, 0, -8 },
		LeftElbow = { 82 - 10 * swing, 0, 0 },
		LeftWrist = { 0, 0, 0 },
		RightShoulder = { 36 * swing + 10, 0, 8 },
		RightElbow = { 86 + 6 * swing, 0, 0 },
		RightWrist = { -12, 0, 0 },
	}
end
local R_SPINE_C = { Waist = { -4, 12, 0 }, Neck = { 13, -4, 0 } }
local R_SPINE_F = { Waist = { -5, 4, 2 }, Neck = { 12, -1, 0 } }
Clips.Run = Clip({
	Length = 0.66,
	Loop = true,
	Priority = 1,
	Stride = 11.5,
	Keys = {
		K(0, Merge(R_CONTACT, R_SPINE_C, runArms(1))),
		K(0.165, Merge(R_FLIGHT, R_SPINE_F, runArms(0.1))),
		K(0.33, Merge(mirrorLower(Merge(R_CONTACT, R_SPINE_C)), runArms(-1))),
		K(0.495, Merge(mirrorLower(Merge(R_FLIGHT, R_SPINE_F)), runArms(-0.1))),
	},
	Events = { { t = 0, Name = "Step" }, { t = 0.33, Name = "Step" } },
})

local B_CONTACT = ST({ Drop = 0.08, Pitch = 2, Yaw = 5, Left = { Z = 0.32, Toe = -10 }, Right = { Z = -0.26, Toe = 8 } })
local B_PASS = ST({ Drop = 0.01, Pitch = 2, Roll = -2.5, Shift = V3(-0.05, 0, 0), Left = { Z = 0.02 }, Right = { Z = 0.06, Y = 0.18, Toe = -4 } })
local B_ARMS = Merge(WEAPON_LOW, GUARD_L)
Clips.WalkBack = Clip({
	Length = 1.05,
	Loop = true,
	Priority = 1,
	Stride = 6.5,
	Keys = {
		K(0, Merge(B_CONTACT, { Waist = { -3, -4, 0 }, Neck = { 2, 2, 0 } }, B_ARMS)),
		K(0.2625, Merge(B_PASS, { Waist = { -3, 0, 2 }, Neck = { 2, 0, -1 } }, B_ARMS)),
		K(0.525, Merge(mirrorLower(Merge(B_CONTACT, { Waist = { -3, -4, 0 }, Neck = { 2, 2, 0 } })), B_ARMS)),
		K(0.7875, Merge(mirrorLower(Merge(B_PASS, { Waist = { -3, 0, 2 }, Neck = { 2, 0, -1 } })), B_ARMS)),
	},
	Events = { { t = 0, Name = "Step" }, { t = 0.525, Name = "Step" } },
})

local function strafePose(drop: number, roll: number, shiftX: number, l: A.FootSpec, r: A.FootSpec, arms: Pose): Pose
	return Merge(
		ST({ Drop = drop, Roll = roll, Pitch = -3, Shift = V3(shiftX, 0, 0), Left = l, Right = r }),
		{ Waist = { -3, 0, -roll * 0.6 }, Neck = { 2, 0, roll * 0.3 } },
		arms
	)
end
local function strafeClip(dirSign: number): A.Clip
	-- dirSign = 1: moving left (left foot leads). Arms stay in the ready guard for both directions.
	local s = dirSign
	local function foot(x: number, extra: A.FootSpec?): A.FootSpec
		local f: A.FootSpec = { X = x * s, Out = 8 }
		if extra then
			for k, v in extra :: any do
				(f :: any)[k] = v
			end
		end
		return f
	end
	local keys: { ClipKey }
	if s > 0 then
		keys = {
			K(0, strafePose(0.1, 3, -0.05, foot(-0.3), foot(0.18, { Toe = -12 }), B_ARMS)),
			K(0.2, strafePose(0.02, 2, -0.03, foot(-0.06), foot(-0.02, { Y = 0.2, Toe = 2 }), B_ARMS)),
			K(0.4, strafePose(0.08, 1.5, 0, foot(0.14, { Toe = -8 }), foot(-0.22), B_ARMS)),
			K(0.6, strafePose(0.02, 2.5, -0.02, foot(-0.14, { Y = 0.2 }), foot(0), B_ARMS)),
		}
	else
		-- moving right: right foot leads, but the LEFT foot (trailing) still plants at t = 0
		keys = {
			K(0, strafePose(0.08, -1.5, 0, foot(-0.22), foot(0.14, { Toe = -8 }), B_ARMS)),
			K(0.2, strafePose(0.02, -2.5, 0.02, foot(0), foot(-0.14, { Y = 0.2 }), B_ARMS)),
			K(0.4, strafePose(0.1, -3, 0.05, foot(0.18, { Toe = -12 }), foot(-0.3), B_ARMS)),
			K(0.6, strafePose(0.02, -2, 0.03, foot(-0.02, { Y = 0.2, Toe = 2 }), foot(-0.06), B_ARMS)),
		}
	end
	return Clip({
		Length = 0.8,
		Loop = true,
		Priority = 1,
		Stride = 6,
		Keys = keys,
		Events = { { t = 0, Name = "Step" }, { t = 0.4, Name = "Step" } },
	})
end
Clips.StrafeL = strafeClip(1)
Clips.StrafeR = strafeClip(-1)

---------------------------------------------------------------------------------------------------
-- Air
---------------------------------------------------------------------------------------------------

Clips.Jump = Clip({
	Length = 0.5,
	Priority = 2,
	FullBody = true,
	Keys = {
		K(0, Merge(ST({ Drop = -0.03, Pitch = -6, Left = { Y = 0.05, Toe = -30 }, Right = { Y = 0.05, Toe = -30 } }), {
			Waist = { -2, 0, 0 },
			Neck = { 4, 0, 0 },
			LeftShoulder = Limb(V3(-0.2, -0.7, 0.68)),
			LeftElbow = { 20, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = Limb(V3(0.2, -0.7, 0.68)),
			RightElbow = { 30, 0, 0 },
			RightWrist = { -10, 0, 0 },
		})),
		K(0.16, Merge(ST({ Drop = -0.08, Pitch = -4, Left = { Y = 0.55, Z = -0.22, Toe = 6 }, Right = { Y = 0.38, Z = 0.04, Toe = -10 } }), {
			Waist = { -8, 0, 0 },
			Neck = { 6, 0, 0 },
			LeftShoulder = Limb(V3(-0.45, 0.55, -0.7)),
			LeftElbow = { 30, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = Limb(V3(0.45, 0.5, -0.74)),
			RightElbow = { 45, 0, 0 },
			RightWrist = { -10, 0, 0 },
		}), "Back", "Out"),
		K(0.5, Merge(ST({ Drop = -0.06, Pitch = -2, Left = { Y = 0.36, Z = -0.12, Toe = -4 }, Right = { Y = 0.26, Z = 0.06, Toe = -12 } }), {
			Waist = { -5, 0, 0 },
			Neck = { 3, 0, 0 },
			LeftShoulder = Limb(V3(-0.75, 0.05, -0.66)),
			LeftElbow = { 30, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = Limb(V3(0.7, 0.0, -0.7)),
			RightElbow = { 45, 0, 0 },
			RightWrist = { -10, 0, 0 },
		})),
	},
	Events = { { t = 0, Name = "Step" } },
})

local function fallPose(k: number): Pose
	return Merge(ST({ Drop = -0.03, Left = { Y = 0.26 - k * 0.1, Z = -0.15 + k * 0.1, Toe = -10 }, Right = { Y = 0.14 + k * 0.1, Z = 0.1 - k * 0.1, Toe = -18 } }), {
		Waist = { -3, 0, 0 },
		Neck = { -10, 0, 0 },
		LeftShoulder = Limb(V3(-0.9, 0.2 + k * 0.1, -0.35)),
		LeftElbow = { 30 - k * 8, 0, 0 },
		LeftWrist = { 0, 0, 0 },
		RightShoulder = Limb(V3(0.88, 0.28 - k * 0.1, -0.38)),
		RightElbow = { 38 + k * 8, 0, 0 },
		RightWrist = { -10, 0, 0 },
	})
end
Clips.Fall = Clip({
	Length = 0.7,
	Loop = true,
	Priority = 2,
	FullBody = true,
	Keys = { K(0, fallPose(0)), K(0.35, fallPose(1)) },
})

local LAND_LOW = Merge(squareLegs(0.42, -12), {
	Waist = { -12, 0, 0 },
	Neck = { 14, 0, 0 },
	LeftShoulder = Limb(V3(-0.55, -0.35, -0.76)),
	LeftElbow = { 25, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.55, -0.3, -0.78)),
	RightElbow = { 40, 0, 0 },
	RightWrist = { -15, 0, 0 },
})
Clips.Land = Clip({
	Length = 0.42,
	Priority = 2,
	FadeIn = 0.02,
	FadeOut = 0.12,
	Keys = {
		K(0, Merge(LAND_LOW, squareLegs(0.25, -8))),
		K(0.07, LAND_LOW, "Quad", "Out"),
		K(0.22, Merge(NEUTRAL, squareLegs(-0.01, -1)), "Back", "Out"),
		K(0.42, READY, "Sine", "InOut"),
	},
	Events = { { t = 0, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Movement actions
---------------------------------------------------------------------------------------------------

local DASH_POSE = Merge(ST({ Drop = 0.36, Pitch = -22, Left = { Z = -0.5, Toe = 12 }, Right = { Z = 0.6, Toe = -40 } }), {
	Waist = { -10, 6, 0 },
	Neck = { 26, -4, 0 },
	LeftShoulder = Limb(V3(-0.3, -0.25, 0.92)),
	LeftElbow = { 12, 0, 0 },
	LeftWrist = { 10, 0, 0 },
	RightShoulder = Limb(V3(0.3, -0.2, 0.93)),
	RightElbow = { 14, 0, 0 },
	RightWrist = { 10, 0, 0 },
})
Clips.Dash = Clip({
	Length = 0.42,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.03,
	Keys = {
		K(0, READY),
		K(0.05, Merge(READY, readyLegs(0.26, -8)), "Quad", "Out"),
		K(0.1, DASH_POSE, "Back", "Out"),
		K(0.26, Merge(DASH_POSE, ST({ Drop = 0.3, Pitch = -18, Left = { Z = -0.44, Toe = 8 }, Right = { Z = 0.5, Toe = -32 } }))),
		K(0.42, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.05, Name = "Release" }, { t = 0.1, Name = "Step" } },
})

-- Quick sidestep to the LEFT (the root itself is moved by the ability / server): crouch, lean, cross.
local DODGE_POSE = Merge(ST({
	Drop = 0.34,
	Pitch = -6,
	Roll = 10,
	Shift = V3(-0.12, 0, 0),
	Left = { X = -0.38, Z = -0.05, Out = 10 },
	Right = { X = 0.02, Z = 0.1, Toe = -20, Out = 12 },
}), {
	Waist = { -8, 6, 6 },
	Neck = { 6, -6, -8 },
	LeftShoulder = Limb(V3(-0.85, -0.35, -0.4)),
	LeftElbow = { 30, 0, 0 },
	LeftWrist = { 0, 0, 0 },
}, reach("Right", V3(0.3, 2.85, -0.8), { -20, 0, 0 }))
Clips.Dodge = Clip({
	Length = 0.45,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.03,
	FadeOut = 0.1,
	Keys = {
		K(0, READY),
		K(0.08, DODGE_POSE, "Back", "Out"),
		K(0.24, Merge(DODGE_POSE, ST({ Drop = 0.3, Pitch = -5, Roll = 8, Shift = V3(-0.1, 0, 0), Left = { X = -0.34, Out = 10 }, Right = { X = 0.04, Z = 0.08, Toe = -16, Out = 12 } }))),
		K(0.45, READY, "Sine", "InOut"),
	},
	Events = { { t = 0, Name = "Release" }, { t = 0.08, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Reactions & states
---------------------------------------------------------------------------------------------------

local function stunnedKey(k: number): Pose
	local th = math.rad(k * 90)
	local rx, rz = -3 + 3 * math.cos(th), 3.5 * math.sin(th)
	local sway = 6 * math.sin(th + math.rad(120))
	return Merge(ST({ Drop = 0.14, Pitch = rx, Roll = rz, Yaw = 5 * math.sin(th), Left = { X = -0.08, Out = 12 }, Right = { X = 0.08, Out = 12 } }), {
		Waist = { -8 + 2 * math.cos(th + math.rad(45)), 0, -2.5 * math.sin(th + math.rad(45)) },
		Neck = { -8 + 7 * math.cos(th + math.rad(90)), 10 * math.cos(th + math.rad(90)), -12 * math.sin(th + math.rad(90)) },
		LeftShoulder = { 6, 0, -8 + sway },
		LeftElbow = { 16, 0, 0 },
		LeftWrist = { 12, 0, 0 },
		RightShoulder = { 6, 0, 8 + sway },
		RightElbow = { 22, 0, 0 },
		RightWrist = { 18, 0, 0 },
	})
end
Clips.Stunned = Clip({
	Length = 1.3,
	Loop = true,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.1,
	Keys = { K(0, stunnedKey(0)), K(0.325, stunnedKey(1)), K(0.65, stunnedKey(2)), K(0.975, stunnedKey(3)) },
})

local function heavy(k: number): Pose
	return Merge(squareLegs(0.5 + k * 0.05, -14), {
		Waist = { -18 - k * 3, 0, k * 1.5 },
		Neck = { 20 + k * 3, 0, -k * 2 },
		LeftShoulder = { 16, 0, -14 + k * 3 },
		LeftElbow = { 30, 0, 0 },
		LeftWrist = { -10, 0, 0 },
		RightShoulder = { 16, 0, 14 - k * 2 },
		RightElbow = { 40, 0, 0 },
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

local function crawl(k: number): Pose
	return {
		Root = { -74, 3 * k, -4 * k, 0, -0.98, 0.3 },
		Waist = { -10, -5 * k, 2 * k },
		Neck = { 60, 4 * k, 0 },
		LeftShoulder = { 98 + 16 * k, 0, -6 },
		LeftElbow = { 8 + 10 * math.max(0, -k), 0, 0 },
		LeftWrist = { -60, 0, 0 },
		RightShoulder = { 98 - 16 * k, 0, 6 },
		RightElbow = { 8 + 10 * math.max(0, k), 0, 0 },
		RightWrist = { -60, 0, 0 },
		LeftHip = { 80 - 10 * k, 0, -8 },
		LeftKnee = { -96, 0, 0 },
		LeftAnkle = { -35, 0, 0 },
		RightHip = { 80 + 10 * k, 0, 8 },
		RightKnee = { -96, 0, 0 },
		RightAnkle = { -35, 0, 0 },
	}
end
Clips.Downed = Clip({
	Length = 1.6,
	Loop = true,
	Priority = 3,
	FullBody = true,
	FadeIn = 0.25,
	Stride = 2.6,
	Keys = { K(0, crawl(1)), K(0.4, crawl(0)), K(0.8, crawl(-1)), K(1.2, crawl(0)) },
	Events = { { t = 0, Name = "Step" }, { t = 0.8, Name = "Step" } },
})

-- Guard: the weapon held across the chest, the left hand braces it; knees bent.
local BLOCK = Merge(
	{ Waist = { -6, 4, 0 }, Neck = { 4, -2, 0 } },
	reach("Right", V3(0.32, 3.02, -0.84), { 0, 0, -20 }, V3(1, -0.2, 0.2)),
	reach("Left", V3(-0.26, 3.0, -0.8), { -20, 0, 0 }, V3(-1, -0.4, 0.2))
)
Clips.Block = Clip({
	Length = 1.2,
	Loop = true,
	Priority = 2,
	Mask = "Upper",
	FadeIn = 0.06,
	Keys = { K(0, BLOCK), K(0.6, Merge(BLOCK, { Waist = { -7, 4, 0 } }, reach("Right", V3(0.32, 3.0, -0.84), { 0, 0, -20 }, V3(1, -0.2, 0.2)))) },
})

Clips.Parry = Clip({
	Length = 0.42,
	Priority = 3,
	Mask = "Upper",
	FadeIn = 0.02,
	Keys = {
		K(0, BLOCK),
		K(0.06, Merge({ Waist = { -4, -22, 0 }, Neck = { 4, 16, 0 } }, reach("Right", V3(1.15, 3.15, -0.55), { -10, 0, -30 }, V3(0.4, -1, 0.4)), reach("Left", V3(-0.6, 2.8, -0.6))), "Back", "Out"),
		K(0.18, Merge({ Waist = { -4, -20, 0 }, Neck = { 4, 14, 0 } }, reach("Right", V3(1.18, 3.2, -0.5), { -12, 0, -30 }, V3(0.4, -1, 0.4)), reach("Left", V3(-0.6, 2.8, -0.6)))),
		K(0.42, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.06, Name = "Hit" } },
})

Clips.Hit = Clip({
	Length = 0.4,
	Priority = 3,
	FadeIn = 0.02,
	FadeOut = 0.14,
	Keys = {
		K(0, READY),
		K(0.05, Merge(ST({ Drop = 0.1, Pitch = 8, Shift = V3(0, 0, 0.12), Left = { X = -0.06 }, Right = { X = 0.06 } }), {
			Waist = { 12, 0, 3 },
			Neck = { 18, 0, -6 },
			LeftShoulder = Limb(V3(-0.75, -0.2, -0.6)),
			LeftElbow = { 50, 0, 0 },
			LeftWrist = { 15, 0, 0 },
			RightShoulder = Limb(V3(0.75, -0.25, -0.6)),
			RightElbow = { 55, 0, 0 },
			RightWrist = { 15, 0, 0 },
		}), "Quad", "Out"),
		K(0.16, Merge(READY, readyLegs(0.2, -6), { Waist = { -8, 8, -1 }, Neck = { -4, 4, 2 } }), "Sine", "Out"),
		K(0.4, READY, "Sine", "InOut"),
	},
})

Clips.Death = Clip({
	Length = 1.4,
	Priority = 4,
	Hold = true,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.12, Merge(ST({ Drop = 0.12, Pitch = 10, Shift = V3(0, 0, 0.1), Left = { X = -0.08 }, Right = { X = 0.08, Z = 0.1 } }), {
			Waist = { 14, 0, 4 },
			Neck = { 22, 0, -8 },
			LeftShoulder = Limb(V3(-0.9, 0.1, -0.4)),
			LeftElbow = { 30, 0, 0 },
			LeftWrist = { 10, 0, 0 },
			RightShoulder = Limb(V3(0.9, 0.15, -0.4)),
			RightElbow = { 30, 0, 0 },
			RightWrist = { 10, 0, 0 },
		}), "Quad", "Out"),
		K(0.45, Merge(ST({ Drop = 0.5, Pitch = 6, Shift = V3(0, 0, 0.15), Left = { X = -0.1, Z = -0.1 }, Right = { X = 0.12, Z = 0.12 } }), {
			Waist = { 10, 0, 5 },
			Neck = { 10, 0, -6 },
			LeftShoulder = Limb(V3(-0.8, -0.3, -0.5)),
			LeftElbow = { 20, 0, 0 },
			LeftWrist = { 10, 0, 0 },
			RightShoulder = Limb(V3(0.8, -0.25, -0.5)),
			RightElbow = { 20, 0, 0 },
			RightWrist = { 10, 0, 0 },
		}), "Quad", "In"),
		K(0.9, {
			Root = { 84, 0, -6, 0, -1.62, 0.8 },
			Waist = { 4, 0, 0 },
			Neck = { -14, -40, 0 },
			LeftShoulder = { 0, 0, -100 },
			LeftElbow = { 20, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 0, 0, 80 },
			RightElbow = { 34, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftHip = { -70, 0, -10 },
			LeftKnee = { -30, 0, 0 },
			LeftAnkle = { 20, 0, 0 },
			RightHip = { -86, 0, 14 },
			RightKnee = { -8, 0, 0 },
			RightAnkle = { 25, 0, 0 },
		}, "Quad", "In"),
		K(1.15, {
			Root = { 88, 0, -6, 0, -1.56, 0.8 },
			Waist = { 2, 0, 0 },
			Neck = { -10, -46, 0 },
			LeftShoulder = { 0, 0, -104 },
			LeftElbow = { 16, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 0, 0, 86 },
			RightElbow = { 30, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftHip = { -74, 0, -10 },
			LeftKnee = { -26, 0, 0 },
			LeftAnkle = { 20, 0, 0 },
			RightHip = { -88, 0, 14 },
			RightKnee = { -6, 0, 0 },
			RightAnkle = { 25, 0, 0 },
		}, "Quad", "Out"),
		K(1.4, {
			Root = { 88, 0, -6, 0, -1.62, 0.8 },
			Waist = { 2, 0, 0 },
			Neck = { -12, -48, 0 },
			LeftShoulder = { 0, 0, -106 },
			LeftElbow = { 14, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = { 0, 0, 88 },
			RightElbow = { 28, 0, 0 },
			RightWrist = { 0, 0, 0 },
			LeftHip = { -76, 0, -10 },
			LeftKnee = { -24, 0, 0 },
			LeftAnkle = { 20, 0, 0 },
			RightHip = { -88, 0, 14 },
			RightKnee = { -6, 0, 0 },
			RightAnkle = { 25, 0, 0 },
		}, "Bounce", "Out"),
	},
	Events = { { t = 0.9, Name = "Hit" } },
})

---------------------------------------------------------------------------------------------------
-- Social
---------------------------------------------------------------------------------------------------

local function victoryKey(up: number): Pose
	return Merge(squareLegs(0.05 + (1 - up) * 0.12, -2), {
		Waist = { 2 + up * 3, -6, 0 },
		Neck = { 8 + up * 6, -4, 0 },
		RightShoulder = Limb(V3(0.25, 1, -0.15 + up * 0.05)),
		RightElbow = { 10 + (1 - up) * 50, 0, 0 },
		RightWrist = { -10, 0, 0 },
	}, reach("Left", V3(-0.42, 2.45 + up * 0.05, -0.55), { 0, 0, 0 }))
end
Clips.Victory = Clip({
	Length = 1.2,
	Loop = true,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.2,
	Keys = { K(0, victoryKey(0)), K(0.3, victoryKey(1), "Back", "Out"), K(0.6, victoryKey(0.05), "Sine", "InOut"), K(0.9, victoryKey(1), "Back", "Out") },
	Events = { { t = 0.3, Name = "Step" }, { t = 0.9, Name = "Step" } },
})

local WAVE = Merge(squareLegs(0.04), { Waist = { -2, 6, 3 }, Neck = { 4, -6, 6 } }, WEAPON_LOW, {
	LeftShoulder = { 8, 0, -150 },
	LeftElbow = { 0, 0, -26 },
	LeftWrist = { 0, 0, -10 },
})
local WAVE2 = Merge(WAVE, { LeftShoulder = { 8, 0, -144 }, LeftElbow = { 0, 0, 20 }, LeftWrist = { 0, 0, 12 } })
Clips.Emote_Wave = Clip({
	Length = 1.1,
	Loop = true,
	Priority = 2,
	FadeIn = 0.2,
	Keys = { K(0, WAVE), K(0.275, WAVE2), K(0.55, WAVE), K(0.825, WAVE2) },
})

local SHRUG = Merge(squareLegs(0.02), {
	Waist = { 3, 0, 0 },
	Neck = { -4, 0, 12 },
	LeftShoulder = Limb(V3(-0.65, -0.72, -0.2), V3(0, 0.4, -1)),
	LeftElbow = { 85, 0, 0 },
	LeftWrist = { 0, 0, 25 },
	RightShoulder = Limb(V3(0.65, -0.72, -0.2), V3(0, 0.4, -1)),
	RightElbow = { 85, 0, 0 },
	RightWrist = { 0, 0, -25 },
})
Clips.Emote_Shrug = Clip({
	Length = 1.8,
	Priority = 2,
	FadeIn = 0.1,
	Keys = {
		K(0, NEUTRAL),
		K(0.25, Merge(SHRUG, squareLegs(-0.02)), "Back", "Out"),
		K(1.2, Merge(SHRUG, { Neck = { -3, 0, 14 } })),
		K(1.8, READY, "Sine", "InOut"),
	},
})

-- Cross-legged on the floor, hands resting on the knees.
local function sit(k: number): Pose
	return {
		Root = { 4 + k, 0, 0, 0, -1.52, 0.1 },
		Waist = { -6 + k * 2, 0, 0 },
		Neck = { 6 - k, 0, 4 },
		LeftHip = { 78, 34, -42 },
		LeftKnee = { -118, 0, 0 },
		LeftAnkle = { -10, -20, 0 },
		RightHip = { 78, -34, 42 },
		RightKnee = { -118, 0, 0 },
		RightAnkle = { -10, 20, 0 },
		LeftShoulder = Limb(V3(-0.45, -0.8, -0.4)),
		LeftElbow = { 30, 0, 0 },
		LeftWrist = { 10, 0, 0 },
		RightShoulder = Limb(V3(0.45, -0.8, -0.4)),
		RightElbow = { 30, 0, 0 },
		RightWrist = { 10, 0, 0 },
	}
end
Clips.Emote_Sit = Clip({
	Length = 3,
	Loop = true,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.4,
	FadeOut = 0.35,
	Keys = { K(0, sit(0)), K(1.5, sit(1)) },
})

local function laugh(k: number): Pose
	return Merge(squareLegs(0.06 + k * 0.04, -6 - k * 4), {
		Waist = { -14 - k * 6, 0, 0 },
		Neck = { 18 + k * 4, 0, 0 },
	}, WEAPON_LOW, reach("Left", V3(-0.15, 2.35, -0.48), { 0, 0, 0 }))
end
Clips.Emote_Laugh = Clip({
	Length = 0.8,
	Loop = true,
	Priority = 2,
	FadeIn = 0.15,
	Keys = { K(0, laugh(0)), K(0.13, laugh(1)), K(0.27, laugh(0.1)), K(0.4, laugh(0.9)), K(0.53, laugh(0)), K(0.67, laugh(0.8)) },
})

Clips.Idle_Look = Clip({
	Length = 2.4,
	Priority = 1,
	Mask = "Torso",
	FadeIn = 0.3,
	FadeOut = 0.4,
	Keys = {
		K(0, READY_SPINE),
		K(0.45, { Waist = { -4, 18, 0 }, Neck = { 4, 30, 0 } }, "Sine", "InOut"),
		K(1.0, { Waist = { -4, 18, 0 }, Neck = { 3, 28, 2 } }),
		K(1.5, { Waist = { -4, 2, 0 }, Neck = { 4, -28, 0 } }, "Sine", "InOut"),
		K(2.0, { Waist = { -4, 2, 0 }, Neck = { 3, -26, -2 } }),
		K(2.4, READY_SPINE, "Sine", "InOut"),
	},
})

-- Restless kid: bounces on the toes and flips the weapon hand.
Clips.Idle_Fidget = Clip({
	Length = 1.6,
	Priority = 1,
	FadeIn = 0.2,
	FadeOut = 0.3,
	Keys = {
		K(0, READY),
		K(0.25, Merge(READY, readyLegs(0.06, -2), reach("Right", V3(0.55, 2.9, -0.7), { -40, 0, 0 })), "Quad", "Out"),
		K(0.5, Merge(READY, readyLegs(0.2, -5), reach("Right", V3(0.5, 2.65, -0.76), { 20, 0, 0 })), "Quad", "In"),
		K(0.75, Merge(READY, readyLegs(0.06, -2), reach("Right", V3(0.55, 2.9, -0.7), { -40, 0, 0 })), "Quad", "Out"),
		K(1.0, Merge(READY, readyLegs(0.2, -5)), "Quad", "In"),
		K(1.6, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.5, Name = "Step" }, { t = 1.0, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Casting (left hand casts: the right hand keeps the weapon)
---------------------------------------------------------------------------------------------------

local CAST_LEGS = ST({ Drop = 0.18, Pitch = -6, Yaw = -18, Left = { X = -0.05, Z = -0.34, Toe = 4 }, Right = { X = 0.1, Z = 0.24, Toe = -6, Out = 30 } })
Clips.Cast = Clip({
	Length = 0.75,
	Priority = 2,
	FadeIn = 0.04,
	FadeOut = 0.15,
	Keys = {
		K(0, READY),
		K(0.09, Merge(READY, { Waist = { -4, 30, 0 }, Neck = { 2, -12, 0 } }, reach("Left", V3(-0.75, 2.75, 0.1), { 20, 0, 0 })), "Quad", "Out"),
		K(0.2, Merge(CAST_LEGS, { Waist = { -8, -4, 0 }, Neck = { 6, 16, 0 } }, WEAPON_LOW, {
			LeftShoulder = Limb(V3(-0.18, 0.12, -0.98)),
			LeftElbow = { 6, 0, 0 },
			LeftWrist = { -45, 0, 0 },
		}), "Back", "Out"),
		K(0.42, Merge(CAST_LEGS, { Waist = { -8, -2, 0 }, Neck = { 6, 14, 0 } }, WEAPON_LOW, {
			LeftShoulder = Limb(V3(-0.2, 0.1, -0.97)),
			LeftElbow = { 10, 0, 0 },
			LeftWrist = { -40, 0, 0 },
		})),
		K(0.75, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.2, Name = "Release" } },
})

Clips.CastUp = Clip({
	Length = 0.9,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.13, Merge(squareLegs(0.36, -10), {
			Waist = { -12, 0, 0 },
			Neck = { -4, 0, 0 },
			LeftShoulder = Limb(V3(-0.3, -0.7, 0.65)),
			LeftElbow = { 30, 0, 0 },
			LeftWrist = { 0, 0, 0 },
			RightShoulder = Limb(V3(0.3, -0.7, 0.65)),
			RightElbow = { 40, 0, 0 },
			RightWrist = { 0, 0, 0 },
		}), "Quad", "Out"),
		K(0.28, Merge(ST({ Drop = -0.04, Pitch = 4, Left = { X = -0.08, Y = 0.05, Toe = -20 }, Right = { X = 0.08, Y = 0.05, Toe = -20 } }), {
			Waist = { 10, 0, 0 },
			Neck = { 26, 0, 0 },
			LeftShoulder = Limb(V3(-0.32, 0.95, -0.05)),
			LeftElbow = { 8, 0, 0 },
			LeftWrist = { -20, 0, 0 },
			RightShoulder = Limb(V3(0.28, 0.96, -0.05)),
			RightElbow = { 8, 0, 0 },
			RightWrist = { -10, 0, 0 },
		}), "Back", "Out"),
		K(0.55, Merge(squareLegs(0.02, 3), {
			Waist = { 8, 0, 0 },
			Neck = { 22, 0, 0 },
			LeftShoulder = Limb(V3(-0.36, 0.93, -0.06)),
			LeftElbow = { 12, 0, 0 },
			LeftWrist = { -20, 0, 0 },
			RightShoulder = Limb(V3(0.32, 0.94, -0.06)),
			RightElbow = { 12, 0, 0 },
			RightWrist = { -10, 0, 0 },
		})),
		K(0.9, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.28, Name = "Release" } },
})

local PUSH = Merge(ST({ Drop = 0.24, Pitch = -8, Yaw = -10, Left = { Z = -0.46, Toe = 6 }, Right = { Z = 0.3, Toe = -14, Out = 26 } }), {
	Waist = { -8, -6, 0 },
	Neck = { 8, 14, 0 },
	LeftShoulder = Limb(V3(-0.05, 0.02, -1)),
	LeftElbow = { 4, 0, 0 },
	LeftWrist = { -60, 0, 0 },
}, reach("Right", V3(0.75, 2.6, 0.1), { -10, 0, 0 }))
Clips.CastForward = Clip({
	Length = 0.8,
	Priority = 2,
	Aim = "Left",
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.1, Merge(READY, { Waist = { -4, 26, 0 }, Neck = { 2, -10, 0 } }, reach("Left", V3(-0.5, 3.0, 0.15), { 30, 0, 0 })), "Quad", "Out"),
		K(0.22, PUSH, "Back", "Out"),
		K(0.48, Merge(PUSH, { LeftShoulder = Limb(V3(-0.06, 0.0, -1)), LeftElbow = { 8, 0, 0 } })),
		K(0.8, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.22, Name = "Release" }, { t = 0.22, Name = "Step" } },
})

Clips.Summon = Clip({
	Length = 1,
	Priority = 2,
	FadeIn = 0.05,
	Keys = {
		K(0, READY),
		K(0.18, Merge(squareLegs(0.3, -8), { Waist = { -10, 0, 0 }, Neck = { 0, 0, 0 } }, reach("Left", V3(-0.3, 1.9, -0.7)), reach("Right", V3(0.3, 1.95, -0.7), { -10, 0, 0 })), "Quad", "Out"),
		K(0.45, Merge(squareLegs(0.04, 2), { Waist = { 6, 0, 0 }, Neck = { 16, 0, 0 } }, {
			LeftShoulder = Limb(V3(-0.55, 0.6, -0.58)),
			LeftElbow = { 12, 0, 0 },
			LeftWrist = { -30, 0, 0 },
			RightShoulder = Limb(V3(0.55, 0.6, -0.58)),
			RightElbow = { 16, 0, 0 },
			RightWrist = { -20, 0, 0 },
		}), "Back", "Out"),
		K(0.7, Merge(squareLegs(0.04, 2), { Waist = { 6, 0, 0 }, Neck = { 15, 0, 0 } }, {
			LeftShoulder = Limb(V3(-0.6, 0.58, -0.55)),
			LeftElbow = { 14, 0, 0 },
			LeftWrist = { -30, 0, 0 },
			RightShoulder = Limb(V3(0.6, 0.58, -0.55)),
			RightElbow = { 18, 0, 0 },
			RightWrist = { -20, 0, 0 },
		})),
		K(1, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.45, Name = "Release" } },
})

local POINT = Merge(readyLegs(0.14, -4), { Waist = { -5, -6, 0 }, Neck = { 4, 6, 0 } }, {
	RightShoulder = Limb(V3(0.04, 0.02, -1)),
	RightElbow = { 4, 0, 0 },
	RightWrist = { 0, 0, 0 },
}, GUARD_L)
Clips.Point = Clip({
	Length = 0.85,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.1, Merge(READY, reach("Right", V3(0.62, 2.95, -0.25), { -30, 0, 0 })), "Quad", "Out"),
		K(0.24, POINT, "Back", "Out"),
		K(0.55, Merge(POINT, { RightShoulder = Limb(V3(0.05, 0.04, -1)) })),
		K(0.85, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.24, Name = "Release" } },
})

-- Two-handed overhead slam into the ground (weapon or fists).
local SLAM_UP = Merge(ST({ Drop = -0.03, Pitch = 6, Left = { X = -0.1, Toe = -10 }, Right = { X = 0.1, Toe = -10 } }), {
	Waist = { 10, 0, 0 },
	Neck = { 10, 0, 0 },
	LeftShoulder = Limb(V3(-0.1, 0.9, 0.42), V3(0, 0, 1)),
	LeftElbow = { 50, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.1, 0.9, 0.42), V3(0, 0, 1)),
	RightElbow = { 50, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
local SLAM_DOWN = Merge(squareLegs(0.55, -20), {
	Waist = { -24, 0, 0 },
	Neck = { 16, 0, 0 },
	LeftShoulder = Limb(V3(-0.12, -0.25, -0.96)),
	LeftElbow = { 8, 0, 0 },
	LeftWrist = { -20, 0, 0 },
	RightShoulder = Limb(V3(0.12, -0.25, -0.96)),
	RightElbow = { 8, 0, 0 },
	RightWrist = { -20, 0, 0 },
})
Clips.Slam = Clip({
	Length = 0.95,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.3, SLAM_UP, "Back", "Out"),
		K(0.5, Merge(SLAM_UP, { Neck = { 12, 0, 0 } })),
		K(0.6, SLAM_DOWN, "Expo", "In"),
		K(0.75, Merge(SLAM_DOWN, squareLegs(0.46, -16)), "Sine", "Out"),
		K(0.95, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.6, Name = "Hit" } },
})

local THROW_COCK = Merge(ST({ Drop = 0.1, Pitch = 2, Yaw = -10, Left = { Z = -0.34 }, Right = { Z = 0.24, Out = 24 } }), {
	Waist = { 4, -26, 4 },
	Neck = { 4, 22, 0 },
	LeftShoulder = Limb(V3(-0.5, 0.1, -0.86)),
	LeftElbow = { 20, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.95, 0.15, 0.25), V3(0, 1, 0.4)),
	RightElbow = { 105, 0, 0 },
	RightWrist = { 10, 0, 0 },
})
local THROW_REL = Merge(ST({ Drop = 0.18, Pitch = -8, Yaw = -6, Left = { Z = -0.42, Toe = 6 }, Right = { Z = 0.26, Toe = -20, Out = 24 } }), {
	Waist = { -12, 24, 0 },
	Neck = { 8, -14, 0 },
	LeftShoulder = Limb(V3(-0.4, -0.5, 0.75)),
	LeftElbow = { 40, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.15, 0.35, -0.92)),
	RightElbow = { 10, 0, 0 },
	RightWrist = { -30, 0, 0 },
})
Clips.Throw = Clip({
	Length = 0.7,
	Priority = 2,
	Aim = "Right",
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.14, THROW_COCK, "Quad", "Out"),
		K(0.24, THROW_REL, "Back", "Out"),
		K(0.4, Merge(THROW_REL, { RightShoulder = Limb(V3(-0.25, -0.5, -0.83)), RightElbow = { 30, 0, 0 }, Waist = { -14, 30, 0 } }), "Sine", "Out"),
		K(0.7, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.24, Name = "Release" }, { t = 0.24, Name = "Step" } },
})

-- Spinning slash: winds right, turns LEFT 360 deg with the weapon held out so the blade leads.
local function spinKey(angle: number, drop: number, armOut: number): Pose
	local p = Merge(ST({ Drop = drop, Pitch = -6, Left = { X = -0.12, Out = 10 }, Right = { X = 0.12, Toe = -10, Out = 10 } }), {
		Waist = { -6, 0, 0 },
		Neck = { 4, 0, 0 },
		RightShoulder = Limb(V3(0.98 * armOut + 0.3 * (1 - armOut), -0.15, -0.2 * armOut - 0.9 * (1 - armOut))),
		RightElbow = { 6 + (1 - armOut) * 60, 0, 0 },
		RightWrist = { 0, 0, 0 },
		LeftShoulder = Limb(V3(-0.85, -0.3, -0.4)),
		LeftElbow = { 40, 0, 0 },
		LeftWrist = { 0, 0, 0 },
	})
	p.Root[2] = angle
	return p
end
Clips.Spin = Clip({
	Length = 0.75,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, Merge(READY)),
		K(0.1, spinKey(-30, 0.3, 0.3), "Quad", "Out"),
		K(0.3, spinKey(170, 0.22, 1), "Quad", "In"),
		K(0.5, spinKey(360, 0.28, 1), "Quad", "Out"),
		K(0.75, Merge(READY, { Root = { READY.Root[1], READY.Root[2] + 360, READY.Root[3], READY.Root[4], READY.Root[5], READY.Root[6] } }), "Sine", "InOut"),
	},
	Events = { { t = 0.3, Name = "Hit" } },
})

local LEAP_CROUCH = Merge(squareLegs(0.6, -18), {
	Waist = { -14, 0, 0 },
	Neck = { 22, 0, 0 },
	LeftShoulder = Limb(V3(-0.25, -0.6, 0.76)),
	LeftElbow = { 20, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.25, -0.6, 0.76)),
	RightElbow = { 30, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
local LEAP_UP = Merge(ST({ Drop = -0.06, Pitch = -6, Left = { Y = 0.1, Toe = -40 }, Right = { Y = 0.12, Toe = -40 } }), {
	Waist = { 4, 0, 0 },
	Neck = { 12, 0, 0 },
	LeftShoulder = Limb(V3(-0.3, 0.92, -0.25)),
	LeftElbow = { 12, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.28, 0.93, -0.25)),
	RightElbow = { 20, 0, 0 },
	RightWrist = { -20, 0, 0 },
})
local LEAP_TUCK = Merge(ST({ Drop = -0.1, Pitch = -8, Left = { Y = 0.65, Z = -0.2, Toe = 0 }, Right = { Y = 0.5, Z = 0.05, Toe = -10 } }), {
	Waist = { -12, 0, 0 },
	Neck = { 12, 0, 0 },
	LeftShoulder = Limb(V3(-0.2, 0.85, 0.45), V3(0, 0, 1)),
	LeftElbow = { 60, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.2, 0.85, 0.45), V3(0, 0, 1)),
	RightElbow = { 60, 0, 0 },
	RightWrist = { 0, 0, 0 },
})
Clips.Leap = Clip({
	Length = 1.05,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.18, LEAP_CROUCH, "Quad", "Out"),
		K(0.3, LEAP_UP, "Back", "Out"),
		K(0.6, LEAP_TUCK, "Sine", "InOut"),
		K(0.82, SLAM_DOWN, "Expo", "In"),
		K(1.05, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.3, Name = "Release" }, { t = 0.82, Name = "Hit" } },
})

-- Lunge: body low and forward, weapon thrust ahead, left arm trailing.
local CHARGE_POSE = Merge(ST({ Drop = 0.4, Pitch = -20, Yaw = -12, Left = { Z = -0.55, Toe = 10 }, Right = { Z = 0.62, Toe = -40, Out = 20 } }), {
	Waist = { -10, 14, 0 },
	Neck = { 26, -6, 0 },
	RightShoulder = Limb(V3(0.06, -0.15, -0.99)),
	RightElbow = { 6, 0, 0 },
	RightWrist = { -6, 0, 0 },
	LeftShoulder = Limb(V3(-0.35, -0.3, 0.88)),
	LeftElbow = { 12, 0, 0 },
	LeftWrist = { 10, 0, 0 },
})
Clips.Charge = Clip({
	Length = 0.7,
	Priority = 2,
	FullBody = true,
	Aim = "Right",
	FadeIn = 0.03,
	Keys = {
		K(0, READY),
		K(0.09, Merge(READY, readyLegs(0.3, -10), { Waist = { -6, 24, 0 }, Neck = { 6, -10, 0 } }, reach("Right", V3(0.75, 2.7, 0.2), { -10, 0, 0 })), "Quad", "Out"),
		K(0.16, CHARGE_POSE, "Back", "Out"),
		K(0.48, Merge(CHARGE_POSE, { Waist = { -9, 12, 0 } })),
		K(0.7, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.16, Name = "Release" }, { t = 0.16, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Weapon combo (right hand)
---------------------------------------------------------------------------------------------------

local LUNGE_L = ST({ Drop = 0.26, Pitch = -8, Yaw = -8, Left = { X = -0.04, Z = -0.4, Toe = 6 }, Right = { X = 0.1, Z = 0.3, Toe = -18, Out = 26 } })
local LUNGE_R = ST({ Drop = 0.26, Pitch = -8, Yaw = 8, Left = { X = -0.1, Z = 0.28, Toe = -16, Out = 24 }, Right = { X = 0.04, Z = -0.4, Toe = 6 } })
local GUARD_BACK = reach("Left", V3(-0.75, 2.75, 0.05), { 0, 0, 0 })

-- Slash1: forehand, right -> left at chest height.
local S1_END = Merge(LUNGE_L, { Waist = { -6, 26, 0 }, Neck = { 4, -18, 0 } }, reach("Right", V3(-0.45, 2.95, -0.75), { 0, 0, 20 }, V3(0.4, -1, 0.2)), GUARD_BACK)
Clips.Slash1 = Clip({
	Length = 0.42,
	Priority = 2,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, READY),
		K(0.07, Merge(readyLegs(0.2, -5), { Waist = { -4, -22, 0 }, Neck = { 2, 18, 0 } }, reach("Right", V3(1.1, 3.05, 0.0), { 0, 0, -30 }, V3(0.3, -1, 0.5)), GUARD_L), "Quad", "Out"),
		K(0.13, Merge(LUNGE_L, { Waist = { -6, 28, 0 }, Neck = { 4, -20, 0 } }, reach("Right", V3(-0.5, 3.0, -0.95), { 0, 0, 30 }, V3(0.4, -1, 0.1)), GUARD_BACK), "Back", "Out"),
		K(0.24, Merge(LUNGE_L, { Waist = { -6, 30, 0 }, Neck = { 4, -21, 0 } }, reach("Right", V3(-0.6, 2.95, -0.85), { 0, 0, 28 }, V3(0.4, -1, 0.1)), GUARD_BACK)),
		K(0.42, S1_END, "Sine", "InOut"),
	},
	Events = { { t = 0.12, Name = "Hit" } },
})

-- Slash2: backhand, left -> right.
local S2_END = Merge(LUNGE_R, { Waist = { -6, -20, 0 }, Neck = { 4, 14, 0 } }, reach("Right", V3(1.15, 3.1, -0.45), { 0, 0, -20 }, V3(0.2, -1, 0.4)), GUARD_L)
Clips.Slash2 = Clip({
	Length = 0.42,
	Priority = 2,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, S1_END),
		K(0.06, Merge(LUNGE_L, { Waist = { -6, 34, 0 }, Neck = { 4, -24, 0 } }, reach("Right", V3(-0.45, 3.15, -0.4), { 0, 0, 40 }, V3(1, -0.3, 0)), GUARD_BACK), "Quad", "Out"),
		K(0.12, Merge(LUNGE_R, { Waist = { -6, -26, 0 }, Neck = { 4, 18, 0 } }, reach("Right", V3(1.2, 3.05, -0.55), { 0, 0, -36 }, V3(0.2, -1, 0.4)), GUARD_L), "Back", "Out"),
		K(0.22, Merge(LUNGE_R, { Waist = { -6, -28, 0 }, Neck = { 4, 19, 0 } }, reach("Right", V3(1.25, 3.05, -0.4), { 0, 0, -34 }, V3(0.2, -1, 0.4)), GUARD_L)),
		K(0.42, S2_END, "Sine", "InOut"),
	},
	Events = { { t = 0.11, Name = "Hit" } },
})

-- Slash3: high right -> low left diagonal.
local S3_END = Merge(LUNGE_L, { Waist = { -14, 20, 0 }, Neck = { 12, -14, 0 } }, reach("Right", V3(-0.35, 2.15, -0.9), { 0, 0, 20 }), GUARD_BACK)
Clips.Slash3 = Clip({
	Length = 0.45,
	Priority = 2,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, S2_END),
		K(0.07, Merge(readyLegs(0.08, -1), { Waist = { 6, -16, 0 }, Neck = { 6, 12, 0 } }, reach("Right", V3(0.85, 4.05, 0.15), { -20, 0, 0 }, V3(1, 0, 0.3)), GUARD_L), "Quad", "Out"),
		K(0.13, Merge(LUNGE_L, { Waist = { -16, 22, 0 }, Neck = { 14, -16, 0 } }, reach("Right", V3(-0.3, 2.2, -1.05), { 10, 0, 20 }), GUARD_BACK), "Back", "Out"),
		K(0.25, Merge(LUNGE_L, { Waist = { -16, 23, 0 }, Neck = { 14, -16, 0 } }, reach("Right", V3(-0.4, 2.1, -0.95), { 10, 0, 22 }), GUARD_BACK)),
		K(0.45, S3_END, "Sine", "InOut"),
	},
	Events = { { t = 0.12, Name = "Hit" } },
})

-- Slash4 (finisher): both hands lift the weapon overhead, small hop, CHOP down with a stomp.
local CHOP_UP = Merge(ST({ Drop = -0.05, Pitch = 6, Left = { X = -0.08, Y = 0.05, Toe = -12 }, Right = { X = 0.08, Y = 0.05, Toe = -12 } }), {
	Waist = { 10, 0, 0 },
	Neck = { 6, 0, 0 },
}, reach("Right", V3(0.12, 4.45, 0.35), { 0, 0, 0 }, V3(1, 0, -0.3)), reach("Left", V3(-0.08, 4.42, 0.3), { 0, 0, 0 }, V3(-1, 0, -0.3)))
local CHOP_DOWN = Merge(ST({ Drop = 0.48, Pitch = -16, Left = { X = -0.06, Z = -0.4, Toe = 6 }, Right = { X = 0.1, Z = 0.3, Toe = -16, Out = 20 } }), {
	Waist = { -20, 0, 0 },
	Neck = { 18, 0, 0 },
}, reach("Right", V3(0.08, 2.2, -1.2), { -20, 0, 0 }, V3(1, -0.5, 0)), reach("Left", V3(-0.04, 2.3, -1.12), { -20, 0, 0 }, V3(-1, -0.5, 0)))
Clips.Slash4 = Clip({
	Length = 0.62,
	Priority = 2,
	FullBody = true,
	Aim = "Torso",
	FadeIn = 0.04,
	FadeOut = 0.15,
	Keys = {
		K(0, S3_END),
		K(0.14, CHOP_UP, "Quad", "Out"),
		K(0.22, CHOP_DOWN, "Expo", "In"),
		K(0.36, Merge(CHOP_DOWN, ST({ Drop = 0.42, Pitch = -13, Left = { X = -0.06, Z = -0.4, Toe = 6 }, Right = { X = 0.1, Z = 0.3, Toe = -14, Out = 20 } })), "Sine", "Out"),
		K(0.62, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.22, Name = "Hit" }, { t = 0.22, Name = "Step" } },
})

---------------------------------------------------------------------------------------------------
-- Boxing (Bravery): fists up, jab / cross / hook / uppercut
---------------------------------------------------------------------------------------------------

local BOX_LEGS = ST({ Drop = 0.2, Pitch = -6, Yaw = -18, Left = { X = -0.06, Z = -0.26, Out = 6 }, Right = { X = 0.1, Z = 0.24, Toe = -8, Out = 30 } })
local FIST_L = reach("Left", V3(-0.3, 3.3, -0.85), { 0, 0, 0 })
local FIST_R = reach("Right", V3(0.28, 3.25, -0.6), { 0, 0, 0 })
local BOX = Merge(BOX_LEGS, { Waist = { -6, 14, 0 }, Neck = { -2, 4, 0 } }, FIST_L, FIST_R)
local function box(extra: Pose): Pose
	return Merge(BOX, extra)
end
Clips.Punch1 = Clip({
	Length = 0.32,
	Priority = 2,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.1,
	Keys = {
		K(0, BOX),
		K(0.03, box({ Waist = { -6, 18, 0 } }), "Quad", "Out"),
		K(0.08, box(Merge({ Waist = { -8, -6, 0 }, Neck = { -2, 16, 0 } }, reach("Left", V3(-0.08, 3.3, -1.75), { 0, 0, 0 }))), "Back", "Out"),
		K(0.16, box(Merge({ Waist = { -8, -6, 0 }, Neck = { -2, 16, 0 } }, reach("Left", V3(-0.1, 3.3, -1.7), { 0, 0, 0 })))),
		K(0.32, BOX, "Sine", "InOut"),
	},
	Events = { { t = 0.08, Name = "Hit" } },
})
Clips.Punch2 = Clip({
	Length = 0.4,
	Priority = 2,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, BOX),
		K(0.05, box({ Waist = { -6, 20, 0 } }), "Quad", "Out"),
		K(0.11, Merge(ST({ Drop = 0.22, Pitch = -9, Yaw = 6, Left = { X = -0.06, Z = -0.26, Out = 6 }, Right = { X = 0.1, Z = 0.24, Toe = -30, Out = 10 } }), {
			Waist = { -8, 24, 0 },
			Neck = { -2, -26, 0 },
		}, reach("Right", V3(0.05, 3.25, -1.75), { 0, 0, 0 }), FIST_L), "Back", "Out"),
		K(0.2, Merge(ST({ Drop = 0.22, Pitch = -9, Yaw = 6, Left = { X = -0.06, Z = -0.26, Out = 6 }, Right = { X = 0.1, Z = 0.24, Toe = -28, Out = 10 } }), {
			Waist = { -8, 24, 0 },
			Neck = { -2, -26, 0 },
		}, reach("Right", V3(0.06, 3.25, -1.7), { 0, 0, 0 }), FIST_L)),
		K(0.4, BOX, "Sine", "InOut"),
	},
	Events = { { t = 0.11, Name = "Hit" } },
})
Clips.Punch3 = Clip({
	Length = 0.42,
	Priority = 2,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.12,
	Keys = {
		K(0, BOX),
		K(0.06, box(Merge({ Waist = { -6, 30, 0 }, Neck = { -2, -10, 0 } }, reach("Left", V3(-1.05, 3.25, -0.6), { 0, 0, 0 }, V3(-0.6, 0.6, 0.4))))),
		K(0.12, Merge(BOX_LEGS, { Waist = { -8, -14, 0 }, Neck = { -2, 22, 0 } }, reach("Left", V3(0.15, 3.3, -1.3), { 0, 0, 0 }, V3(-0.5, 0.7, 0.3)), FIST_R), "Back", "Out"),
		K(0.22, Merge(BOX_LEGS, { Waist = { -8, -16, 0 }, Neck = { -2, 23, 0 } }, reach("Left", V3(0.2, 3.3, -1.25), { 0, 0, 0 }, V3(-0.5, 0.7, 0.3)), FIST_R)),
		K(0.42, BOX, "Sine", "InOut"),
	},
	Events = { { t = 0.12, Name = "Hit" } },
})
Clips.Punch4 = Clip({
	Length = 0.55,
	Priority = 2,
	FullBody = true,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.15,
	Keys = {
		K(0, BOX),
		K(0.1, Merge(ST({ Drop = 0.42, Pitch = -12, Yaw = -18, Roll = -6, Left = { X = -0.06, Z = -0.26, Out = 6 }, Right = { X = 0.1, Z = 0.24, Toe = -8, Out = 30 } }), {
			Waist = { -10, 8, -6 },
			Neck = { 8, 6, 0 },
		}, FIST_L, reach("Right", V3(0.45, 2.4, -0.5), { 0, 0, 0 })), "Quad", "Out"),
		K(0.17, Merge(ST({ Drop = -0.04, Pitch = 2, Yaw = 4, Left = { X = -0.06, Z = -0.26, Toe = -10, Out = 6 }, Right = { X = 0.1, Z = 0.24, Toe = -35, Out = 10 } }), {
			Waist = { 8, 26, 4 },
			Neck = { 10, -20, 0 },
		}, FIST_L, reach("Right", V3(0.1, 4.25, -1.0), { 0, 0, 0 }, V3(0.5, -1, 0.5))), "Back", "Out"),
		K(0.3, Merge(ST({ Drop = -0.02, Pitch = 2, Yaw = 4, Left = { X = -0.06, Z = -0.26, Toe = -6, Out = 6 }, Right = { X = 0.1, Z = 0.24, Toe = -30, Out = 10 } }), {
			Waist = { 7, 25, 4 },
			Neck = { 10, -19, 0 },
		}, FIST_L, reach("Right", V3(0.12, 4.2, -0.98), { 0, 0, 0 }, V3(0.5, -1, 0.5)))),
		K(0.55, BOX, "Sine", "InOut"),
	},
	Events = { { t = 0.17, Name = "Hit" } },
})

---------------------------------------------------------------------------------------------------
-- Kicks (balletic): arms in second position, pointed toes
---------------------------------------------------------------------------------------------------

local ARMS_SECOND = {
	LeftShoulder = Limb(V3(-0.92, 0.05, -0.38)),
	LeftElbow = { 20, 0, 0 },
	LeftWrist = { 0, 0, 0 },
	RightShoulder = Limb(V3(0.92, 0.05, -0.38)),
	RightElbow = { 20, 0, 0 },
	RightWrist = { 0, 0, 0 },
}
local function kickClip(chamber: Pose, strike: Pose, hitT: number, length: number): A.Clip
	return Clip({
		Length = length,
		Priority = 2,
		FullBody = true,
		Aim = "Torso",
		FadeIn = 0.03,
		FadeOut = 0.14,
		Keys = {
			K(0, READY),
			K(hitT * 0.55, chamber, "Quad", "Out"),
			K(hitT, strike, "Back", "Out"),
			K(hitT + 0.12, strike),
			K(length, READY, "Sine", "InOut"),
		},
		Events = { { t = hitT, Name = "Hit" } },
	})
end
Clips.Kick1 = kickClip(
	Merge(ST({ Drop = 0.08, Pitch = 4, Left = { X = -0.02, Out = 14 }, Right = { Y = 0.55, Z = -0.15, Toe = -20 } }), { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } }, ARMS_SECOND),
	Merge(ST({ Drop = 0.02, Pitch = 12, Left = { X = -0.02, Toe = -10, Out = 14 } }), {
		Waist = { -4, 0, 0 },
		Neck = { -6, 0, 0 },
		RightHip = { 96, 0, 2 },
		RightKnee = { -4, 0, 0 },
		RightAnkle = { -40, 0, 0 },
	}, ARMS_SECOND),
	0.13,
	0.45
)
Clips.Kick2 = kickClip(
	Merge(ST({ Drop = 0.1, Pitch = 2, Yaw = 20, Right = { X = 0.04, Out = 30 }, Left = { Y = 0.5, X = -0.35, Z = 0.1, Toe = -20 } }), { Waist = { -2, -20, 0 }, Neck = { 0, 6, 0 } }, ARMS_SECOND),
	Merge(ST({ Drop = 0.06, Pitch = 8, Roll = -10, Yaw = -10, Right = { X = 0.04, Toe = -10, Out = 30 } }), {
		Waist = { -2, 4, 10 },
		Neck = { 0, 8, -6 },
		LeftHip = { 74, 0, -42 },
		LeftKnee = { -6, 0, 0 },
		LeftAnkle = { -40, 0, 0 },
	}, ARMS_SECOND),
	0.14,
	0.48
)
local function turnKick(angle: number, k: number): Pose
	local p = Merge(ST({ Drop = 0.08 - k * 0.05, Pitch = 4 + k * 10, Left = { X = -0.02, Toe = -14, Out = 10 }, Right = { Y = 0.5 * (1 - k), Z = -0.1, Toe = -20 } }), {
		Waist = { -2, 0, 0 },
		Neck = { -4 * k, 0, 0 },
	}, ARMS_SECOND)
	if k >= 1 then
		p.RightHip = { 112, 0, 4 }
		p.RightKnee = { -2, 0, 0 }
		p.RightAnkle = { -40, 0, 0 }
	end
	p.Root[2] = angle
	return p
end
Clips.Kick3 = Clip({
	Length = 0.66,
	Priority = 2,
	FullBody = true,
	Aim = "Torso",
	FadeIn = 0.03,
	FadeOut = 0.15,
	Keys = {
		K(0, READY),
		K(0.08, turnKick(-20, 0.2), "Quad", "Out"),
		K(0.2, turnKick(200, 0.4), "Quad", "In"),
		K(0.3, turnKick(360, 1), "Back", "Out"),
		K(0.44, turnKick(360, 1)),
		K(0.66, Merge(READY, { Root = { READY.Root[1], READY.Root[2] + 360, READY.Root[3], READY.Root[4], READY.Root[5], READY.Root[6] } }), "Sine", "InOut"),
	},
	Events = { { t = 0.3, Name = "Hit" } },
})

---------------------------------------------------------------------------------------------------
-- Ranged & support
---------------------------------------------------------------------------------------------------

-- One-handed revolver shot: arm locked at the aim, recoil kicks the wrist and elbow up.
local GUN = Merge(readyLegs(0.12, -3), { Waist = { -4, -8, 0 }, Neck = { 2, 8, 0 } }, {
	RightShoulder = Limb(V3(0.02, 0.0, -1)),
	RightElbow = { 4, 0, 0 },
	RightWrist = { 0, 0, 0 },
}, reach("Left", V3(-0.45, 2.55, -0.55), { 0, 0, 0 }))
Clips.Shoot = Clip({
	Length = 0.38,
	Priority = 2,
	Aim = "Right",
	Mask = "Upper",
	FadeIn = 0.02,
	FadeOut = 0.14,
	Keys = {
		K(0, GUN),
		K(0.035, Merge(GUN, { RightShoulder = Limb(V3(0.02, 0.24, -0.97)), RightElbow = { 22, 0, 0 }, RightWrist = { 18, 0, 0 }, Waist = { -1, -8, 0 }, Neck = { 4, 8, 0 } }), "Expo", "Out"),
		K(0.15, GUN, "Back", "Out"),
		K(0.38, GUN),
	},
	Events = { { t = 0.02, Name = "Release" } },
})

-- Revolver to the chest, the left hand spins the cylinder, flick shut.
Clips.Reload = Clip({
	Length = 0.9,
	Priority = 2,
	Mask = "Upper",
	FadeIn = 0.05,
	Keys = {
		K(0, GUN),
		K(0.16, Merge({ Waist = { -6, 0, 0 }, Neck = { -14, 0, 0 } }, reach("Right", V3(0.18, 2.75, -0.8), { -30, 0, -40 }), reach("Left", V3(-0.05, 2.65, -0.85), { 0, 0, 0 })), "Quad", "Out"),
		K(0.3, Merge({ Waist = { -6, 0, 0 }, Neck = { -14, 0, 0 } }, reach("Right", V3(0.18, 2.75, -0.8), { -30, 0, -40 }), reach("Left", V3(0.1, 2.85, -0.85), { 0, 0, 0 }))),
		K(0.44, Merge({ Waist = { -6, 0, 0 }, Neck = { -14, 0, 0 } }, reach("Right", V3(0.18, 2.75, -0.8), { -30, 0, -40 }), reach("Left", V3(-0.05, 2.65, -0.85), { 0, 0, 0 }))),
		K(0.62, Merge({ Waist = { -6, -4, 0 }, Neck = { -6, 4, 0 } }, reach("Right", V3(0.55, 3.1, -0.6), { -40, 0, 0 }), reach("Left", V3(-0.45, 2.55, -0.55))), "Back", "Out"),
		K(0.9, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.62, Name = "Release" } },
})

local HEAL_GATHER = Merge(squareLegs(0.1), { Waist = { -6, 0, 0 }, Neck = { -6, 0, 0 } }, reach("Left", V3(-0.1, 2.85, -0.7)), reach("Right", V3(0.12, 2.82, -0.72), { -10, 0, 0 }))
local HEAL_OPEN = Merge(squareLegs(0.02, 2), {
	Waist = { 5, 0, 0 },
	Neck = { 10, 0, 0 },
	LeftShoulder = Limb(V3(-0.7, 0.3, -0.65)),
	LeftElbow = { 15, 0, 0 },
	LeftWrist = { -30, 0, 0 },
	RightShoulder = Limb(V3(0.7, 0.3, -0.65)),
	RightElbow = { 20, 0, 0 },
	RightWrist = { -20, 0, 0 },
})
Clips.Heal = Clip({
	Length = 0.95,
	Priority = 2,
	FadeIn = 0.05,
	Keys = {
		K(0, READY),
		K(0.2, HEAL_GATHER, "Sine", "Out"),
		K(0.34, HEAL_OPEN, "Back", "Out"),
		K(0.62, Merge(HEAL_OPEN, { LeftShoulder = Limb(V3(-0.72, 0.32, -0.62)), RightShoulder = Limb(V3(0.72, 0.32, -0.62)) })),
		K(0.95, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.34, Name = "Release" } },
})

local GUARD = Merge(ST({ Drop = 0.42, Pitch = -8, Left = { X = -0.22, Out = 18 }, Right = { X = 0.22, Out = 18 } }), {
	Waist = { -8, 0, 0 },
	Neck = { 8, 0, 0 },
}, reach("Left", V3(0.3, 3.15, -0.75), { 0, 0, 0 }, V3(-1, -0.2, 0)), reach("Right", V3(-0.3, 3.0, -0.82), { 0, 0, 0 }, V3(1, -0.2, 0)))
Clips.Guard = Clip({
	Length = 0.8,
	Priority = 2,
	FullBody = true,
	FadeIn = 0.04,
	Keys = {
		K(0, READY),
		K(0.15, GUARD, "Back", "Out"),
		K(0.5, Merge(GUARD, { Waist = { -9, 0, 0 } })),
		K(0.8, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.15, Name = "Release" } },
})

-- Weapon raised at the enemy, left hand beckons: "come on!"
local TAUNT = Merge(readyLegs(0.14, -2), { Waist = { 2, 6, 0 }, Neck = { 6, -2, 6 } }, reach("Right", V3(0.75, 3.4, -0.6), { -30, 0, 0 }))
local function beckon(curl: number): Pose
	return Merge(TAUNT, {
		LeftShoulder = Limb(V3(-0.35, -0.25, -0.9), V3(0, 1, 0)),
		LeftElbow = { 20 + curl * 50, 0, 0 },
		LeftWrist = { -20 + curl * 50, 0, 0 },
	})
end
Clips.Taunt = Clip({
	Length = 1.25,
	Priority = 2,
	FadeIn = 0.05,
	Keys = {
		K(0, READY),
		K(0.25, beckon(0), "Back", "Out"),
		K(0.42, beckon(1), "Quad", "InOut"),
		K(0.58, beckon(0), "Quad", "InOut"),
		K(0.74, beckon(1), "Quad", "InOut"),
		K(0.9, beckon(0), "Quad", "InOut"),
		K(1.25, READY, "Sine", "InOut"),
	},
	Events = { { t = 0.3, Name = "Release" } },
})

return Clips
