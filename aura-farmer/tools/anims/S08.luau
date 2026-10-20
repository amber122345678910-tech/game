--!nocheck
-- S08 experiment
local B = 45 -- torso forward from vertical (root.bend + waist.bend)
local ROOT = { y = -2.2, bend = 88 }

local function head(dx, up, fwd, pitch, roll)
	local b = math.rad(B)
	return {
		x = dx,
		y = up * math.cos(b) + fwd * math.sin(b),
		f = fwd * math.cos(b) - up * math.sin(b),
		rx = B + pitch,
		rz = roll,
	}
end

return {
	Horse = { keys = {
		{ t = 7.8667, root = ROOT, waist = { bend = B - 88 },
			joints = { Head = head(0, -1.3, -0.25, 6, 2) },
			rArm = { ik = { 3.3, 1.8, 0 }, pole = { 0, -0.5, 1 } }, lArm = { ik = { -3.3, 1.95, 0 }, pole = { 0, -0.5, 1 } },
			rLeg = { ik = { 2.0, 1.7, -0.9 }, pole = { 1, -0.3, 0 } }, lLeg = { ik = { -2.0, 1.7, -0.9 }, pole = { -1, -0.3, 0 } },
			rHand = "fist", lHand = "fist", face = { jaw = 0.3 } },
	} },
}
