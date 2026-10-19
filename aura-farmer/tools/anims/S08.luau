--!nocheck
-- Ключи анимации плана S08 (см. tools/lib/Pose.luau — формат ключей).
return {
	Horse = { keys = {
		{
			t = 7.8667,
			root = { y = -2.2, bend = 88 },
			waist = { bend = -45 },
			neck = { nod = -38 },
			face = { jaw = 0.45, grin = 0 },
			joints = { Glasses = { y = 0.1, f = 0.06 } },
			rArm = { ik = { 2.15, 1.95, -0.3 }, pole = { 1, 0.9, 0.4 } },
			lArm = { ik = { -2.15, 2.05, -0.3 }, pole = { -1, 1.1, 0.4 } },
			rHand = "fist", lHand = "fist",
			rLeg = { ik = { 2.0, 1.75, -0.45 }, pole = { 0.7, -0.6, -0.4 } },
			lLeg = { ik = { -2.0, 1.85, -0.45 }, pole = { -0.7, -0.6, -0.4 } },
		},
	} },
}
