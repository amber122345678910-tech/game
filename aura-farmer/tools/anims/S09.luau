--!nocheck
return {
	Horse = { keys = {
		{ t = 9.5333,
			root = { y = -2.263, f = -0.177, bend = 135 },
			waist = { bend = -149 },
			neck = { nod = 48 },
			rArm = { ik = { 2.2, 1.97, -1.0 }, pole = { 0.2, -0.3, -1 } },
			lArm = { ik = { -2.2, 1.97, -1.0 }, pole = { -0.2, -0.3, -1 } },
			rLeg = { ik = { 2.25, 2.13, -1.0 }, pole = { 0.4, -1, -0.2 }, foot = { fingers = { 1, 0.1, 0 }, palm = { 0.1, -1, 0 } } },
			lLeg = { ik = { -2.25, 2.13, -1.0 }, pole = { -0.4, -1, -0.2 }, foot = { fingers = { -0.75, 0.65, 0 }, palm = { -0.65, -0.75, 0 } } },
			rHand = "fist", lHand = "fist",
			face = { jaw = 0.5, grin = 1 },
		},
	} },
}
