--!nocheck
local F = { jaw = 0.15, grin = 0 }
local J = { UpperLip = { y = 0, f = 0.06, rx = -3 } }
return {
	Horse = { keys = {
		{ t = 5.9, neck = { turn = -9.9, nod = -10, tilt = 0.3 }, face = F, joints = J },
		{ t = 6.0, neck = { turn = -9.9, nod = -6.8, tilt = -0.8 }, face = F, joints = J },
		{ t = 6.1, neck = { turn = -9.7, nod = -11.3, tilt = 0 }, face = F, joints = J },
		{ t = 6.2, neck = { turn = -9.7, nod = -13.1, tilt = -0.2 }, face = F, joints = J },
	} },
}
