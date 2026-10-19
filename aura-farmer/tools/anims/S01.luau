--!nocheck
-- Ключи анимации плана S01 (см. tools/lib/Pose.luau — формат ключей).
-- Парень сидит на песке, голова повёрнута влево (к правому краю кадра), подбородок поднят.
-- Фазы по долям (123 BPM): 0.000–0.163 рука долетает до очков (ease-out), контакт на доле 0;
-- 0.163–0.651 держит оправу, подбородок медленно опускается, брови сходятся;
-- 0.651–1.139 спускает очки на кончик носа (пик скорости ≈0.75–0.8) с наклоном оправы, глаза
-- выглядывают поверх; доля 2 (1.139) — дожим с маленьким перелётом; дальше — «залипший» взгляд.

-- ===== Геометрия очков (Man: height 1.04, R головы 0.6; см. tools/chars/Human.luau) =====
local H = 1.04
local HC = (4.05 + 0.74) * H -- центр головы (поза покоя)
local G_HOME = { 0, HC, 0.6 + 0.075 } -- переносица {x, y, f}
local HINGE = { -0.42, 0.05, -0.03 } -- левая петля относительно переносицы {x, y, f}

-- Точка петли (в осях головы, поза покоя) при смещении очков g = { y, f, rx }.
local function hinge(g)
	local a = math.rad(g.rx or 0)
	local y0, z0 = HINGE[2], -HINGE[3]
	-- поворот вокруг X: (y, z) -> (y cos - z sin, y sin + z cos)
	local y1 = y0 * math.cos(a) - z0 * math.sin(a)
	local z1 = y0 * math.sin(a) + z0 * math.cos(a)
	return { G_HOME[1] + HINGE[1], G_HOME[2] + y1 + (g.y or 0), G_HOME[3] - z1 + (g.f or 0) }
end

-- Кисть щипком держит оправу у левой петли: ладонь к стеклу, пальцы вдоль верха оправы к переносице,
-- большой палец снизу. WRIST — запястье относительно точки щипка (середина кончиков указательного и большого),
-- посчитано по геометрии рига для PALM/FING (оси головы).
local WRIST = { -0.15, -0.516, 0.42 }
local PALM = { 0.0, -0.2, -1 }
local FING = { 0.55, 0.8, -0.15 }
local POLE = { -0.3, -1, 0.25 }

-- d — смещение запястья от позиции хвата (оси головы).
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

-- Доп. суставы: очки + верхняя губа чуть опущена (рот «О» без зубов, как в клипе).
local function glasses(g)
	return { Glasses = { y = g.y or 0, f = g.f or 0, rx = g.rx or 0 }, UpperLip = { y = -0.018, f = 0.008 }, Mouth = { y = 0.036, f = -0.004 } }
end

-- Сидит на песке: таз опущен, колени согнуты, правая рука опирается о песок сбоку-сзади.
local function seat(bend, dy)
	return { y = -1.66 + (dy or 0), bend = bend }
end
local R_ARM = { ik = { 1.75, 0.4, -0.35 }, pole = { 1, 0, -0.3 } }
local R_LEG = { ik = { 0.7, 0.28, 1.55 }, pole = { 0.4, 1, 1 } }
local L_LEG = { ik = { -0.75, 0.28, 1.45 }, pole = { -0.4, 1, 1 } }

-- Пальцы: «когти» на подлёте, щипок на оправе, дожим (squash) в момент контакта.
local CLAW = { index = 0.32, middle = 0.38, ring = 0.55, pinky = 0.62, thumb = 0.2, thumbOut = 0.75, spread = 0.25 }
local PINCH = { index = 0.38, middle = 0.5, ring = 0.75, pinky = 0.85, thumb = 0.55, thumbOut = 0.6, spread = 0.1 }
local PRESS = { index = 0.44, middle = 0.56, ring = 0.78, pinky = 0.88, thumb = 0.62, thumbOut = 0.56, spread = 0.08 }

-- Очки: на месте -> на кончике носа (вниз, чуть вперёд, верх оправы наклонён от лица).
local G0 = { y = 0, f = 0, rx = 0 }
local function gl(k)
	-- k: доля пути (0..1, допускает перелёт)
	return { y = -0.132 * k, f = 0.052 * k, rx = -13 * k }
end

-- Голова: поворот шеи (к его левому плечу), кивок (+ вниз), наклон к правому плечу.
local TURN = 22
local function neck(nod, turn, tilt)
	return { nod = nod, turn = TURN + (turn or 0), tilt = tilt or 5 }
end

-- Лицо: «О»-рот, брови сводятся и опускаются (knit 0..0.6), прищур, взгляд влево (к правому краю кадра).
local function face(jaw, knit, squint, look)
	return { jaw = jaw, oh = 1, frown = math.min(1, knit * 1.5), brows = 0, squint = squint * 0.5, lookX = look or -0.45, lookY = 0.05 }
end

return {
	Man = { keys = {
		-- подлёт руки (ключ до начала плана задаёт скорость в первом кадре)
		{ t = -0.1, root = seat(-5.5), waist = { turn = 3, bend = -1 }, neck = neck(-15.5, 0.5), lArm = grip(G0, { -0.7, -0.7, 0.65 }), lHand = CLAW, joints = glasses(G0), face = face(0.3, 0, 0) },
		{
			t = 0.0,
			root = seat(-5),
			waist = { turn = 3, bend = -1 },
			neck = neck(-15, 0.5),
			rArm = R_ARM,
			lArm = grip(G0, { -0.42, -0.42, 0.42 }),
			rLeg = R_LEG,
			lLeg = L_LEG,
			lHand = CLAW,
			joints = glasses(G0),
			face = face(0.36, 0, 0),
		},
		{ t = 0.1, face = face(0.44, 0.05, 0) },
		{ t = 0.133, ease = "out", lArm = grip(G0, { -0.06, -0.01, 0.06 }), lHand = { index = 0.45, middle = 0.55, ring = 0.72, pinky = 0.8, thumb = 0.45, thumbOut = 0.6, spread = 0.12 }, neck = neck(-14, 0.4) },
		-- доля 0: контакт + лёгкий дожим пальцев
		{ t = 0.163, root = seat(-4), lArm = grip(G0), lHand = PINCH, neck = neck(-13, 0.3), joints = glasses(G0) },
		{ t = 0.2, lArm = grip(G0, { 0, -0.012, 0 }), lHand = PRESS, face = face(0.33, 0.1, 0) },
		{ t = 0.25, lArm = grip({ y = -0.004 }), lHand = PINCH, joints = glasses({ y = -0.004 }) },
		{ t = 0.3, root = seat(-3), neck = neck(-11, 0.2), face = face(0.32, 0.3, 0.05) },
		{ t = 0.36, face = face(0.42, 0.33, 0.06) },
		{ t = 0.47, face = face(0.3, 0.37, 0.08) },
		-- доля 1: старт спуска
		{ t = 0.651, root = seat(0), waist = { turn = 3, bend = 0 }, neck = neck(-8, 0), lArm = grip(gl(0.03)), joints = glasses(gl(0.03)), face = face(0.3, 0.4, 0.1) },
		{ t = 0.7, lArm = grip(gl(0.17)), joints = glasses(gl(0.17)) },
		{ t = 0.8, root = seat(2), waist = { turn = 2.5, bend = 1 }, neck = neck(-4, -1), lArm = grip(gl(0.58), { 0, -0.01, 0 }), joints = glasses(gl(0.58)), face = face(0.45, 0.5, 0.15, -0.55) },
		{ t = 0.9, lArm = grip(gl(0.83)), joints = glasses(gl(0.83)), face = face(0.38, 0.55, 0.2, -0.55) },
		{ t = 1.0, root = seat(3), waist = { turn = 2, bend = 1.5 }, neck = neck(-1, -2), lArm = grip(gl(0.96)), joints = glasses(gl(0.96)), face = face(0.36, 0.6, 0.24, -0.55) },
		{ t = 1.05, lArm = grip(gl(1.04)), joints = glasses(gl(1.04)) },
		-- доля 2: оправа дожата, «ну-ка, кто тут?»
		{ t = 1.1, face = face(0.45, 0.6, 0.25, -0.55) },
		{ t = 1.139, root = seat(3, 0.004), neck = neck(0, -2), lArm = grip(gl(1.0)), joints = glasses(gl(1.0)) },
		{ t = 1.25, face = face(0.36, 0.6, 0.25, -0.55) },
		{ t = 1.3, root = seat(3.2, 0.008), neck = neck(0.5, -2.4, 5.4), lArm = grip(gl(1.0)), joints = glasses(gl(1.0)) },
		{
			t = 1.4333,
			root = seat(3.3, 0.006),
			waist = { turn = 2, bend = 1.5 },
			neck = neck(1, -2.8, 5.6),
			rArm = R_ARM,
			lArm = grip(gl(1.01)),
			rLeg = R_LEG,
			lLeg = L_LEG,
			lHand = PINCH,
			joints = glasses(gl(1.01)),
			face = face(0.4, 0.6, 0.25, -0.55),
		},
	} },
	-- Друг: полулёжа на локтях, ноги вытянуты; только дыхание.
	Friend = { keys = (function()
		local function k(t, breath)
			return {
				t = t,
				root = { y = -1.7, bend = -60 + breath * 0.6 },
				waist = { bend = -2 + breath * 0.8, turn = -8 },
				neck = { nod = 46, turn = -40, tilt = -4 },
				rArm = { ik = { 1.45, 0.28, -0.55 }, pole = { 0.3, -1, -1 } },
				lArm = { ik = { -1.45, 0.28, -0.5 }, pole = { -0.3, -1, -1 } },
				rLeg = { ik = { 0.6, 0.26, 1.75 }, pole = { 0, 1, 0.4 } },
				lLeg = { ik = { -0.55, 0.26, 1.2 }, pole = { 0, 1, 1 } },
				rHand = "relaxed",
				lHand = "relaxed",
				face = { jaw = 0.05, smile = 0.15 },
			}
		end
		return { k(0, 0), k(0.75, 1), k(1.5, 0) }
	end)() },
}
