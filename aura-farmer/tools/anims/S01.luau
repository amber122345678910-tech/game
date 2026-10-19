--!nocheck
-- Ключи анимации плана S01 (см. tools/lib/Pose.luau — формат ключей).
-- Парень сидит на песке, голова повёрнута влево (к правому краю кадра), левой рукой берёт авиаторы
-- за левую петлю (доля 0 = 0.163) и с доли 1 (0.651) до доли 2 (1.139) спускает их на кончик носа.

-- ===== Геометрия очков (Man: height 1.04, R головы 0.6) =====
local H = 1.04
local HC = (4.05 + 0.74) * H -- центр головы (поза покоя)
local G_HOME = { 0, HC, 0.6 + 0.075 } -- переносица {x, y, f}
local HINGE = { -0.42, 0.05, -0.03 } -- левая петля относительно переносицы {x, y, f}

-- Точка петли (в осях головы, поза покоя) при смещении очков g = { y, f, rx }.
local function hinge(g)
	local a = math.rad(g.rx or 0)
	local y0, f0 = HINGE[2], HINGE[3]
	-- поворот вокруг X: (y, z) -> (y cos - z sin, y sin + z cos), z = -f
	local z0 = -f0
	local y1 = y0 * math.cos(a) - z0 * math.sin(a)
	local z1 = y0 * math.sin(a) + z0 * math.cos(a)
	return { G_HOME[1] + HINGE[1], G_HOME[2] + y1 + (g.y or 0), G_HOME[3] - z1 + (g.f or 0) }
end

-- Кисть: ладонь к лицу, пальцы вверх и через верх оправы. WRIST — запястье относительно точки щипка.
local WRIST = { -0.167, -0.43, 0.369 }
local PALM = { 0.0, -0.2, -1 }
local FING = { 0.85, 0.5, -0.1 }
local POLE = { -0.6, -1, 0.5 }

local function grip(g, d)
	d = d or {}
	local p = hinge(g)
	return {
		ik = { p[1] + WRIST[1] + (d[1] or 0), p[2] + WRIST[2] + (d[2] or 0), p[3] + WRIST[3] + (d[3] or 0) },
		space = "head",
		pole = POLE,
		wrist = { palm = PALM, fingers = FING },
	}
end

local function glasses(g)
	return { Glasses = { y = g.y or 0, f = g.f or 0, rx = g.rx or 0 } }
end

-- Сидит на песке: таз опущен, колени согнуты, правая рука опирается о песок сзади-сбоку.
local function seat(bend)
	return { y = -1.66, bend = bend }
end
local R_ARM = { ik = { 1.75, 0.4, -0.35 }, pole = { 1, 0, -0.3 } }
local R_LEG = { ik = { 0.7, 0.28, 1.55 }, pole = { 0.4, 1, 1 } }
local L_LEG = { ik = { -0.75, 0.28, 1.45 }, pole = { -0.4, 1, 1 } }

local PINCH = { index = 0.5, middle = 0.62, ring = 0.8, pinky = 0.88, thumb = 0.55, thumbOut = 0.55, spread = 0.08 }
local G0 = { y = 0, f = 0, rx = 0 }
local G_END = { y = -0.17, f = 0.06, rx = -14 }

return {
	Man = { keys = {
		{
			t = 0.0,
			root = seat(-5),
			waist = { turn = 3 },
			neck = { turn = 17, nod = -15, tilt = 5 },
			rArm = R_ARM,
			lArm = grip(G0),
			rLeg = R_LEG,
			lLeg = L_LEG,
			lHand = PINCH,
			joints = glasses(G0),
			face = { jaw = 0.35, oh = 0.8 },
		},
		{
			t = 1.4333,
			root = seat(3),
			waist = { turn = 3 },
			neck = { turn = 17, nod = 0, tilt = 5 },
			rArm = R_ARM,
			lArm = grip(G_END),
			rLeg = R_LEG,
			lLeg = L_LEG,
			lHand = PINCH,
			joints = glasses(G_END),
			face = { jaw = 0.35, oh = 0.8, frown = 0.6 },
		},
	} },
}
