--!nocheck
-- Ключи анимации плана S01 (см. tools/lib/Pose.luau — формат ключей).
-- Парень сидит на песке, голова повёрнута влево (к правому краю кадра), подбородок поднят.
-- Фазы по долям (123 BPM): 0.000–0.163 рука долетает до очков (ease-out), контакт на доле 0;
-- 0.163–0.651 держит оправу, подбородок медленно опускается, брови сходятся;
-- 0.651–1.139 спускает очки на кончик носа (пик скорости ≈0.75–0.85) с наклоном оправы, глаза
-- выглядывают поверх; доля 2 (1.139) — дожим с маленьким перелётом; дальше — «залипший» взгляд.

-- ===== Геометрия очков (Man: height 1.04, R головы 0.6; см. tools/chars/Human.luau) =====
local H = 1.04
local HC = (4.05 + 0.74) * H -- центр головы (поза покоя)
local G_HOME = { 0, HC, 0.6 + 0.075 } -- переносица {x, y, f} = опора сустава Glasses

-- Точка оправы (локально от переносицы {x, y, f}) в осях головы при смещении очков g = { y, f, rx }.
local function onGlasses(loc, g)
	local a = math.rad(g.rx or 0)
	local y0, z0 = loc[2], -loc[3]
	-- поворот вокруг X (как CFrame.Angles(rx, 0, 0)): (y, z) -> (y cos - z sin, y sin + z cos)
	local y1 = y0 * math.cos(a) - z0 * math.sin(a)
	local z1 = y0 * math.sin(a) + z0 * math.cos(a)
	return { G_HOME[1] + loc[1], G_HOME[2] + y1 + (g.y or 0), G_HOME[3] - z1 + (g.f or 0) }
end
local function rotX(v, deg)
	local a = math.rad(deg)
	local y0, z0 = v[2], -v[3]
	return { v[1], y0 * math.cos(a) - z0 * math.sin(a), -(y0 * math.sin(a) + z0 * math.cos(a)) }
end

-- Хват: подушечки указательного и среднего лежат на верхнем крае левого (дальнего) стекла у петли,
-- большой палец — под внешним краем стекла. Кисть стоит почти вертикально (тыльная сторона к камере),
-- запястье ниже и правее по кадру. Направления — в осях головы (IK space = "head").
-- (ориентация подобрана по направлениям «запястье -> костяшки -> кончик» на кадрах клипа)
local PALM = { 0.526, -0.132, -0.833 }
local FING = { 0.464, 0.877, 0.157 }
-- смещение «запястье -> кончик указательного» для PINCH при PALM/FING (замерено на риге)
local TIPS = { 0.235, 0.577, -0.249 }
local GRIP = { -0.39, 0.1, 0.02 } -- точка хвата на оправе (от переносицы): верх внешнего угла стекла у петли
local POLE = { -0.1, -1, 0.35 } -- локоть вниз и вперёд (к камере), из кадра справа снизу

-- Цель IK запястья: хват на оправе (едет с очками) минус смещение кончиков (поворачивается с оправой).
-- d — смещение от позиции хвата (оси головы), для подлёта.
local function grip(g, d)
	d = d or {}
	local p = onGlasses(GRIP, g)
	local off = rotX(TIPS, g.rx or 0)
	return {
		ik = { p[1] - off[1] + (d[1] or 0), p[2] - off[2] + (d[2] or 0), p[3] - off[3] + (d[3] or 0) },
		space = "head",
		pole = POLE,
		wrist = { palm = rotX(PALM, g.rx or 0), fingers = rotX(FING, g.rx or 0) },
	}
end

-- Доп. суставы: очки + верхняя губа чуть опущена (рот «О» без зубов, как в клипе).
local function glasses(g)
	return { Glasses = { y = g.y or 0, f = g.f or 0, rx = g.rx or 0 }, UpperLip = { y = -0.018, f = 0.008 }, Mouth = { y = 0.036, f = -0.004 } }
end

-- Сидит на песке: таз опущен, колени согнуты, правая рука опирается о песок сбоку.
local function seat(bend, dy, f)
	return { y = -1.66 + (dy or 0), bend = bend, f = f or 0 }
end
local R_ARM = { ik = { 1.72, 0.36, 0.05 }, pole = { 1, 0, -0.2 } }
local R_LEG = { ik = { 0.7, 0.28, 1.55 }, pole = { 0.4, 1, 1 } }
local L_LEG = { ik = { -0.75, 0.28, 1.45 }, pole = { -0.4, 1, 1 } }

-- Пальцы: «когти» на подлёте, щипок на оправе, дожим (squash) в момент контакта.
local CLAW = { index = 0.3, middle = 0.36, ring = 0.52, pinky = 0.6, thumb = 0.5, thumbOut = 0.45, spread = 0.25 }
local PINCH = { index = 0.45, middle = 0.5, ring = 0.7, pinky = 0.8, thumb = 0.85, thumbOut = 0.25, spread = 0.1 }
local PRESS = { index = 0.5, middle = 0.55, ring = 0.73, pinky = 0.83, thumb = 0.9, thumbOut = 0.22, spread = 0.08 }

-- Очки: на месте -> на кончике носа (вниз, чуть вперёд, верх оправы наклонён от лица).
local G0 = { y = 0, f = 0, rx = 0 }
local function gl(k)
	-- k: доля пути (0..1, допускает перелёт)
	return { y = -0.135 * k, f = 0.055 * k, rx = -12 * k }
end

-- Голова: поворот шеи (к его левому плечу), кивок (+ вниз), наклон к правому плечу.
local TURN = 18
local function neck(nod, turn, tilt)
	return { nod = nod, turn = TURN + (turn or 0), tilt = tilt or 5 }
end

-- Лицо: «О»-рот, брови сводятся и опускаются (knit 0..0.6), прищур, взгляд влево (к правому краю кадра).
-- jaw — раскрытие рта по разметке клипа (0.3..0.45); на риге «О» читается при jaw ≈ 0.5..0.7 (тёмный рот без зубов).
-- Веки чуть приоткрыты (blink < 0): в клипе глаза над оправой широко открыты.
local function face(jaw, knit, squint, look, up)
	return {
		jaw = 0.15 + jaw * 1.2,
		oh = 1,
		frown = math.min(1, knit * 1.5),
		brows = -0.25 * knit,
		squint = squint * 0.35,
		blink = -0.15 * knit,
		lookX = look or -0.45,
		lookY = up or 0.05,
	}
end

-- смещение подлёта (оси головы): вправо по кадру = к его левому плечу и вперёд
local REACH = { -0.45, -0.59, 0.335 }
local function reach(k)
	return { REACH[1] * k, REACH[2] * k, REACH[3] * k }
end

return {
	Man = { keys = {
		-- подлёт руки (ключ до начала плана задаёт скорость в первом кадре)
		{ t = -0.1, root = seat(-4), waist = { turn = 3, bend = -1 }, neck = neck(-7.5, 0.5), lArm = grip(G0, reach(1.9)), lHand = CLAW, joints = glasses(G0), face = face(0.3, 0, 0) },
		{
			t = 0.0,
			root = seat(-3.6),
			waist = { turn = 3, bend = -1 },
			neck = neck(-7, 0.5),
			rArm = R_ARM,
			lArm = grip(G0, reach(1)),
			rLeg = R_LEG,
			lLeg = L_LEG,
			rHand = "relaxed",
			lHand = CLAW,
			joints = glasses(G0),
			face = face(0.36, 0, 0),
		},
		{ t = 0.1, face = face(0.44, 0.05, 0) },
		{ t = 0.133, ease = "out", lArm = grip(G0, reach(0.08)), lHand = { index = 0.42, middle = 0.48, ring = 0.66, pinky = 0.75, thumb = 0.75, thumbOut = 0.3, spread = 0.12 }, neck = neck(-6.5, 0.4) },
		-- доля 0: контакт + лёгкий дожим пальцев
		{ t = 0.163, root = seat(-3), lArm = grip(G0), lHand = PINCH, neck = neck(-6, 0.3), joints = glasses(G0) },
		{ t = 0.2, lArm = grip(G0, { 0, -0.012, 0 }), lHand = PRESS, face = face(0.33, 0.1, 0) },
		{ t = 0.25, lArm = grip({ y = -0.004 }), lHand = PINCH, joints = glasses({ y = -0.004 }) },
		{ t = 0.3, root = seat(-2.2), neck = neck(-4.5, 0.2), face = face(0.32, 0.3, 0.05) },
		{ t = 0.36, face = face(0.42, 0.33, 0.06) },
		{ t = 0.47, face = face(0.3, 0.37, 0.08) },
		-- доля 1: старт спуска
		{ t = 0.651, root = seat(0), waist = { turn = 3, bend = 0 }, neck = neck(-2.5, 0), lArm = grip(gl(0.03)), joints = glasses(gl(0.03)), face = face(0.3, 0.4, 0.1) },
		{ t = 0.7, lArm = grip(gl(0.15)), joints = glasses(gl(0.15)) },
		{ t = 0.8, root = seat(2, 0, 0.02), waist = { turn = 2.5, bend = 1 }, neck = neck(0, -1), lArm = grip(gl(0.55), { 0, -0.01, 0 }), joints = glasses(gl(0.55)), face = face(0.45, 0.5, 0.15, -0.55, 0.12) },
		{ t = 0.9, lArm = grip(gl(0.83)), joints = glasses(gl(0.83)), face = face(0.38, 0.55, 0.2, -0.55, 0.18) },
		{ t = 1.0, root = seat(3, 0, 0.03), waist = { turn = 2, bend = 1.5 }, neck = neck(2.5, -2), lArm = grip(gl(0.97)), joints = glasses(gl(0.97)), face = face(0.36, 0.6, 0.24, -0.55, 0.2) },
		{ t = 1.05, lArm = grip(gl(1.05)), joints = glasses(gl(1.05)) },
		-- доля 2: оправа дожата, «ну-ка, кто тут?»
		{ t = 1.1, face = face(0.45, 0.6, 0.25, -0.55, 0.2) },
		{ t = 1.139, root = seat(3, 0.004, 0.03), neck = neck(3.2, -2), lArm = grip(gl(1.0)), joints = glasses(gl(1.0)) },
		{ t = 1.25, face = face(0.36, 0.6, 0.25, -0.55, 0.2) },
		{ t = 1.3, root = seat(3.2, 0.008, 0.03), neck = neck(3.5, -2.4, 5.4), lArm = grip(gl(1.0)), joints = glasses(gl(1.0)) },
		{
			t = 1.4333,
			root = seat(3.3, 0.006, 0.03),
			waist = { turn = 2, bend = 1.5 },
			neck = neck(3.8, -2.8, 5.6),
			rArm = R_ARM,
			lArm = grip(gl(1.01)),
			rLeg = R_LEG,
			lLeg = L_LEG,
			rHand = "relaxed",
			lHand = PINCH,
			joints = glasses(gl(1.01)),
			face = face(0.4, 0.6, 0.25, -0.55, 0.2),
		},
	} },
	-- Друг: полулёжа на локтях, ноги вытянуты; только дыхание.
	Friend = { keys = (function()
		local function k(t, breath)
			return {
				t = t,
				root = { y = -1.72, bend = -62 + breath * 0.6 },
				waist = { bend = -2 + breath * 0.8, turn = -22 },
				neck = { nod = 50, turn = -62, tilt = -6 },
				rArm = { ik = { 1.45, 0.28, -0.55 }, pole = { 0.3, -1, -1 } },
				lArm = { ik = { -1.45, 0.28, -0.5 }, pole = { -0.3, -1, -1 } },
				rLeg = { ik = { 0.6, 0.24, 2.0 }, pole = { 0, 1, 0.4 } },
				lLeg = { ik = { -0.6, 0.24, 1.7 }, pole = { 0, 1, 1 } },
				rHand = "relaxed",
				lHand = "relaxed",
				face = { jaw = 0.05, smile = 0.15 },
			}
		end
		return { k(0, 0), k(0.75, 1), k(1.5, 0) }
	end)() },
}
