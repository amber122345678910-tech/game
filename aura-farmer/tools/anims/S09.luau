--!nocheck
return {
	Horse = { keys = {
		{ t = 9.5333,
			root = { y = -2.2, f = -0.25, bend = 88 },
			waist = { bend = -96 },
			neck = { nod = 40 },
			rArm = { ik = { 2.25, 1.8, -1.05 }, pole = { 1, 0.2, 0.6 } },
			lArm = { ik = { -2.25, 1.8, -1.05 }, pole = { -1, 0.2, 0.6 } },
			rLeg = { ik = { 2.3, 1.9, -1.15 }, pole = { 0.4, -1, -0.2 }, foot = { fingers = { 0.5, 0.85, 0 }, palm = { 0.85, -0.5, 0 } } },
			lLeg = { ik = { -2.3, 1.9, -1.15 }, pole = { -0.4, -1, -0.2 }, foot = { fingers = { -0.5, 0.85, 0 }, palm = { -0.85, -0.5, 0 } } },
			rHand = "fist", lHand = "fist",
			face = { jaw = 0.5, grin = 1 },
		},
	} },
}
