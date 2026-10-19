--!nocheck
return {
	Horse = { keys = {
		{ t = 9.5333,
			root = { y = -2.263, f = -0.177, bend = 135 },
			waist = { bend = -149 },
			neck = { nod = 26 },
			rArm = { ik = { 2.2, 2.0, -1.0 }, pole = { 0.2, -0.3, -1 } },
			lArm = { ik = { -2.2, 2.0, -1.0 }, pole = { -0.2, -0.3, -1 } },
			rLeg = { ik = { 2.25, 2.16, -1.0 }, pole = { 0.4, -1, -0.2 }, foot = { fingers = { 0.85, 0.5, -0.15 }, palm = { 0.5, -0.85, 0 } } },
			lLeg = { ik = { -2.25, 2.16, -1.0 }, pole = { -0.4, -1, -0.2 }, foot = { fingers = { -0.6, 0.8, -0.1 }, palm = { -0.8, -0.6, 0 } } },
			rHand = "fist", lHand = "fist",
			face = { jaw = 1.0, grin = 1 },
		},
	} },
}
