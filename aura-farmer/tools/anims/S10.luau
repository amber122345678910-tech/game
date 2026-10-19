--!nocheck
-- Ключи анимации плана S10 (см. tools/lib/Pose.luau — формат ключей).
local ROOT = { y = -0.72, f = 0, bend = 8 }
local LEGS = {
	rLeg = { ik = { 1.3, 0.62, 1.0 }, pole = { 0.6, 0.2, 1 } },
	lLeg = { ik = { -1.3, 0.62, 1.0 }, pole = { -0.6, 0.2, 1 } },
}
local DOWN = {
	root = ROOT,
	rLeg = LEGS.rLeg,
	lLeg = LEGS.lLeg,
	waist = { bend = 30, turn = 10, tilt = 18 },
	neck = { nod = -8, turn = -35, tilt = 8 },
	rArm = { ik = { 2.4, 1.7, 1.4 }, pole = { 1, 0, -0.6 }, wrist = { palm = { -0.7, 0, -0.7 }, fingers = { 0, -1, 0 } } },
	lArm = { ik = { -1.25, 2.25, 0.9 }, pole = { -1, 0.5, -0.3 }, wrist = { palm = { 0, -1, 0 }, fingers = { 0.2, -0.5, 1 } } },
	rHand = "fist",
	lHand = { curl = 0.4, thumb = 0.2, thumbOut = 0.5, spread = 0.1 },
	face = { jaw = 0.05, grin = 1 },
}
local function key(t, base, extra)
	local k = { t = t }
	for g, v in base do
		k[g] = v
	end
	for g, v in extra or {} do
		k[g] = v
	end
	return k
end
return {
	Horse = { keys = {
		key(11.1333, DOWN),
		key(13.1333, DOWN),
	} },
}
