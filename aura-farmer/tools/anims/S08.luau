--!nocheck
local function K(t, o)
	local k = {
		t = t,
		root = { y = -2.2, bend = 88 },
		waist = o.waist or { bend = -45 },
		neck = o.neck or { nod = -38 },
		face = { jaw = 0.45, grin = 0 },
		joints = { Glasses = { y = 0.1, f = 0.06 } },
		rArm = { ik = { 2.15, 1.95, -0.3 }, pole = { 1, 0.9, 0.4 } },
		lArm = { ik = { -2.15, 2.05, -0.3 }, pole = { -1, 1.1, 0.4 } },
		rHand = "fist", lHand = "fist",
		rLeg = { ik = { 2.0, 1.75, -0.45 }, pole = { 0.7, -0.6, -0.4 } },
		lLeg = { ik = { -2.0, 1.85, -0.45 }, pole = { -0.7, -0.6, -0.4 } },
		ease = "hold",
	}
	return k
end
return {
	Horse = { keys = {
		K(7.9, {}),
		K(8.1, { neck = { nod = -48 } }),
		K(8.3, { waist = { bend = -50 } }),
		K(8.5, { waist = { bend = -45, turn = 5 } }),
		K(8.7, { waist = { bend = -45, tilt = 5 } }),
		K(8.9, { neck = { nod = -38, tilt = 5 } }),
		K(9.1, { neck = { nod = -38, turn = 5 } }),
		K(9.3, { root = { y = -2.2, bend = 88 } }),
	} },
}
