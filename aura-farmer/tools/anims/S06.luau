--!nocheck
local F = { jaw = 0.15, grin = 0 }
local J = { UpperLip = { y = 0, f = 0.06, rx = -3 } }
return {
	Horse = { keys = {
		{ t = 5.9, neck = { turn = -20.1, nod = 2.0, tilt = 1.9 }, face = F, joints = J },
		{ t = 6.0, neck = { turn = -29.9, nod = 3.0, tilt = 1.5 }, face = F, joints = J },
		{ t = 6.1, neck = { turn = -9.8, nod = -13.8, tilt = -0.4 }, face = F, joints = J },
	} },
}
