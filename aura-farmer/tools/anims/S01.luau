--!nocheck
-- Ключи анимации плана S01 (см. tools/lib/Pose.luau — формат ключей).
-- Парень сидит на песке, голова повёрнута влево (к правому краю кадра, ≈58° от камеры), подбородок поднят.
-- Фазы по долям (123 BPM): 0.000–0.163 рука долетает до очков (ease-out), контакт на доле 0;
-- 0.163–0.651 держит оправу, подбородок медленно опускается, брови сходятся;
-- 0.651–1.139 спускает очки на кончик носа (пик скорости ≈0.8) с наклоном оправы и подбородок поджимается —
-- глаза выглядывают поверх; доля 2 (1.139) — дожим с маленьким перелётом; дальше — «залипший» взгляд.

-- ===== Геометрия очков (Man: height 1.04, R головы 0.6; см. tools/chars/Human.luau) =====
local H = 1.04
local HC = (4.62 + 0.92) * H -- центр головы (поза покоя) = rig.headCenter.Y
local G_HOME = { 0, HC, 0.6 + 0.075 } -- переносица {x, y, f} = опора сустава Glasses (= rig.glassesHome)

-- поворот вокруг X (как CFrame.Angles(rx, 0, 0)) точки {x, y, f}: (y, z) -> (y cos - z sin, y sin + z cos), z = -f
local function rotX(v, deg)
	local a = math.rad(deg)
	local y0, z0 = v[2], -v[3]
	return { v[1], y0 * math.cos(a) - z0 * math.sin(a), -(y0 * math.sin(a) + z0 * math.cos(a)) }
end
-- Точка оправы (локально от переносицы {x, y, f}) в осях головы при смещении очков g = { y, f, rx }.
local function onGlasses(loc, g)
	local r = rotX(loc, g.rx or 0)
	return { G_HOME[1] + r[1], G_HOME[2] + r[2] + (g.y or 0), G_HOME[3] + r[3] + (g.f or 0) }
end

-- ===== Хват левой рукой за дальнее (левое) стекло =====
-- Кисть стоит снаружи от стекла: тыльная сторона к камере / вправо по кадру, ладонь к виску, пальцы
-- (указательный сверху) ложатся на внешний край оправы у петли, большой — под стеклом. Запястье ниже и
-- правее хвата по кадру, предплечье уходит вниз-вправо. Направления — в осях головы (IK space = "head").
local PALM = { 0.3, -0.25, -0.92 }
local FING = { 0.3, 0.85, -0.43 }
-- смещение «запястье -> подушечка указательного» при PALM/FING и PINCH (замерено на риге)
local TIPS = { 0.028, 0.422, -0.564 }
local GRIP = { -0.42, 0.07, 0.01 } -- точка хвата на оправе (от переносицы): верх внешнего угла стекла у петли
local POLE = { 0.6, -0.8, 0.6 } -- локоть вниз, вперёд и наружу: из кадра справа снизу

-- Цель IK запястья: хват на оправе (едет с очками) минус смещение кончиков (поворачивается с оправой).
-- d — смещение запястья от позиции хвата (оси головы), для подлёта; hp — доворот кисти вокруг оси X головы
-- (пока голова запрокинута, кисть остаётся вертикальной в мире, а не «ложится» вместе с головой).
-- palm/fing — другая ориентация кисти (на подлёте: тыльная сторона развёрнута к камере, пальцы веером вверх).
local function grip(g, d, hp, palm, fing)
	d = d or {}
	local p = onGlasses(GRIP, g)
	local a = (g.rx or 0) + (hp or 0)
	local off = rotX(TIPS, a)
	return {
		ik = { p[1] - off[1] + (d[1] or 0), p[2] - off[2] + (d[2] or 0), p[3] - off[3] + (d[3] or 0) },
		space = "head",
		pole = POLE,
		wrist = { palm = rotX(palm or PALM, a), fingers = rotX(fing or FING, a) },
	}
end
local P_REACH = { -0.55, -0.2, -0.8 }
local F_REACH = { 0.35, 0.8, -0.5 }
local P_MID = { 0.05, -0.23, -0.97 } -- промежуточный разворот кисти перед захватом
local F_MID = { 0.33, 0.83, -0.46 }

-- Доп. суставы: только очки (рот «О» — лицевым каналом oh).
local function glasses(g)
	return { Glasses = { y = g.y or 0, f = g.f or 0, rx = g.rx or 0 } }
end

-- Сидит на песке: таз опущен (−2.08 при новых пропорциях), колени согнуты; bend — наклон корпуса (+ вперёд).
local function seat(bend, dy, f)
	return { y = -2.08 + (dy or 0), bend = bend, f = f or 0 }
end
-- правая рука опирается ладонью о песок у бедра (вне кадра, видно только плечо)
local R_ARM = { ik = { 1.7, 0.35, 0.25 }, pole = { 1, 0, -0.2 }, wrist = { palm = { 0.1, -1, 0 }, fingers = { 0.25, 0, 1 } } }
local R_LEG = { ik = { 0.75, 0.28, 1.95 }, pole = { 0.4, 1, 1 } }
local L_LEG = { ik = { -0.85, 0.28, 1.85 }, pole = { -0.4, 1, 1 } }

-- Пальцы: раскрытая «лапка» на подлёте, щипок на оправе, дожим (squash) в момент контакта.
local CLAW = { index = 0.18, middle = 0.26, ring = 0.36, pinky = 0.44, thumb = 0.25, thumbOut = 0.6, spread = 0.3 }
local CLOSE = { index = 0.2, middle = 0.28, ring = 0.38, pinky = 0.45, thumb = 0.4, thumbOut = 0.55, spread = 0.2 }
local PINCH = { index = 0.4, middle = 0.5, ring = 0.6, pinky = 0.65, thumb = 0.7, thumbOut = 0.5, spread = 0.05 }
local PRESS = { index = 0.45, middle = 0.55, ring = 0.64, pinky = 0.68, thumb = 0.75, thumbOut = 0.48, spread = 0.04 }

-- Очки: на месте -> на кончике носа (вниз, чуть вперёд, верх оправы наклонён от лица).
local G0 = { y = 0, f = 0, rx = 0 }
local function gl(k)
	-- k: доля пути (0..1, допускает перелёт)
	return { y = -0.135 * k, f = 0.055 * k, rx = -12 * k }
end

-- Голова: поворот шеи (к его левому плечу; грудь уже развёрнута на 25° постановкой), кивок (+ вниз),
-- наклон к правому плечу.
local TURN = 30
local function neck(nod, turn, tilt)
	return { nod = nod, turn = TURN + (turn or 0), tilt = tilt or 5 }
end

-- Лицо: «О»-рот (oh + jaw), брови сводятся и опускаются (knit 0..0.6), прищур (нижние веки), взгляд влево
-- (к правому краю кадра). jaw — раскрытие рта по разметке клипа (0.3..0.45).
local function face(jaw, knit, squint, look, up)
	return {
		jaw = 0.05 + jaw,
		oh = 1,
		frown = math.min(1, knit * 1.5),
		brows = -0.25 * knit,
		squint = squint * 0.35,
		blink = -0.15 * knit,
		lookX = look or -0.5,
		lookY = up or 0.05,
	}
end

-- подлёт (смещение запястья от хвата, оси головы): правее по кадру (= к его левому плечу и вперёд) и чуть ниже
local REACH0 = { -0.5, -0.72, 0.62 } -- за кадр до начала (задаёт скорость в первом кадре)
local REACH1 = { -0.3, -0.42, 0.4 } -- t = 0: кисть уже у лица справа, пальцы тянутся к стеклу
local HP0 = -24 -- доворот кисти, пока голова запрокинута

return {
	Man = { keys = {
		{ t = -0.1, root = seat(-4), waist = { turn = 3, bend = -1 }, neck = neck(-7.5, 0.5), lArm = grip(G0, REACH0, HP0 - 6, P_REACH, F_REACH), lHand = CLAW, joints = glasses(G0), face = face(0.3, 0, 0) },
		{
			t = 0.0,
			root = seat(-3.6),
			waist = { turn = 3, bend = -1, tilt = 0 },
			neck = neck(-7, 0.5),
			rArm = R_ARM,
			lArm = grip(G0, REACH1, HP0 - 3, P_REACH, F_REACH),
			rLeg = R_LEG,
			lLeg = L_LEG,
			rHand = "relaxed",
			lHand = CLAW,
			joints = glasses(G0),
			face = face(0.38, 0, 0),
		},
		{ t = 0.1, lArm = grip(G0, { -0.07, -0.06, 0.09 }, HP0, P_MID, F_MID), lHand = CLOSE, face = face(0.44, 0.05, 0) },
		{ t = 0.133, ease = "out", lArm = grip(G0, { -0.012, 0, 0.015 }, HP0), lHand = PINCH, neck = neck(-6.5, 0.4) },
		-- доля 0: контакт + лёгкий дожим пальцев (squash 1–2 кадра)
		{ t = 0.163, root = seat(-3), waist = { turn = 3, bend = -1, tilt = 1.5 }, lArm = grip(G0, nil, HP0), lHand = PINCH, neck = neck(-6, 0.3), joints = glasses(G0) },
		{ t = 0.2, lArm = grip(G0, { 0, -0.01, 0 }, HP0), lHand = PRESS, face = face(0.36, 0.1, 0) },
		{ t = 0.25, lArm = grip({ y = -0.004 }, nil, HP0), lHand = PINCH, joints = glasses({ y = -0.004 }) },
		{ t = 0.3, root = seat(-2.2), neck = neck(-4.8, 0.2), face = face(0.33, 0.3, 0.05) },
		{ t = 0.36, face = face(0.42, 0.33, 0.06) },
		-- вдох: грудь чуть поднимается между долями
		{ t = 0.45, root = seat(-1.2, 0.012), lArm = grip({ y = -0.006 }, nil, -19) },
		{ t = 0.47, face = face(0.28, 0.37, 0.08) },
		{ t = 0.58, face = face(0.3, 0.39, 0.09) },
		-- доля 1: старт спуска очков
		{ t = 0.651, root = seat(0), waist = { turn = 3, bend = 0, tilt = 2 }, neck = neck(-3, 0), lArm = grip(gl(0.02), nil, -13), joints = glasses(gl(0.02)), face = face(0.32, 0.4, 0.1) },
		{ t = 0.7, lArm = grip(gl(0.12), nil, -10), joints = glasses(gl(0.12)) },
		{ t = 0.8, root = seat(1.6, 0, 0.015), waist = { turn = 2.5, bend = 0.8, tilt = 2 }, neck = neck(-1.2, -1), lArm = grip(gl(0.5), { 0, -0.01, 0 }, -6), joints = glasses(gl(0.5)), face = face(0.45, 0.5, 0.15, -0.7, 0.1) },
		{ t = 0.9, neck = neck(0.8, -1.5), lArm = grip(gl(0.82), nil, -3), joints = glasses(gl(0.82)), face = face(0.38, 0.55, 0.2, -0.7, 0.14) },
		{ t = 1.0, root = seat(3, 0, 0.03), waist = { turn = 2, bend = 1.5, tilt = 2 }, neck = neck(2.5, -2), lArm = grip(gl(0.97), nil, 0), joints = glasses(gl(0.97)), face = face(0.36, 0.6, 0.24, -0.7, 0.15) },
		{ t = 1.06, lArm = grip(gl(1.06), nil, 0.5), joints = glasses(gl(1.06)) },
		-- доля 2: оправа дожата, «ну-ка, кто тут?»
		{ t = 1.1, face = face(0.45, 0.6, 0.25, -0.7, 0.15) },
		{ t = 1.139, root = seat(3, 0.004, 0.03), neck = neck(3.2, -2), lArm = grip(gl(1.0), nil, 0.5), joints = glasses(gl(1.0)) },
		{ t = 1.25, face = face(0.36, 0.6, 0.25, -0.7, 0.15) },
		{ t = 1.3, root = seat(3.2, 0.008, 0.03), neck = neck(3.5, -2.4, 5.4), lArm = grip(gl(1.0), nil, 0.5), joints = glasses(gl(1.0)) },
		{
			t = 1.4333,
			root = seat(3.3, 0.006, 0.03),
			waist = { turn = 2, bend = 1.5, tilt = 2 },
			neck = neck(3.8, -2.8, 5.6),
			rArm = R_ARM,
			lArm = grip(gl(1.01), nil, 0.5),
			rLeg = R_LEG,
			lLeg = L_LEG,
			rHand = "relaxed",
			lHand = PINCH,
			joints = glasses(gl(1.01)),
			face = face(0.4, 0.6, 0.25, -0.7, 0.15),
		},
	} },
	-- Друг: полулёжа на локтях, ноги вытянуты к камере; только дыхание.
	Friend = { keys = (function()
		local function k(t, breath)
			return {
				t = t,
				root = { y = -2.12, bend = -64 + breath * 0.6 },
				waist = { bend = -2 + breath * 0.8, turn = -5 },
				neck = { nod = 52, turn = -10, tilt = -6 },
				rArm = { ik = { 1.45, 0.32, -0.55 }, pole = { 1, 0, -0.5 }, wrist = { palm = { -0.2, -1, 0 }, fingers = { 0.1, 0, 1 } } },
				lArm = { ik = { -1.45, 0.32, -0.5 }, pole = { -1, 0, -0.5 }, wrist = { palm = { 0.2, -1, 0 }, fingers = { -0.1, 0, 1 } } },
				rLeg = { ik = { 0.6, 0.24, 2.0 }, pole = { 0, 1, 0.4 } },
				lLeg = { ik = { -0.6, 0.24, 1.7 }, pole = { 0, 1, 1 } },
				rHand = { curl = 0.15, thumb = 0.2, thumbOut = 0.3, spread = 0.15 },
				lHand = { curl = 0.15, thumb = 0.2, thumbOut = 0.3, spread = 0.15 },
				face = { jaw = 0.05, smile = 0.15 },
			}
		end
		return { k(0, 0), k(0.75, 1), k(1.5, 0) }
	end)() },
}
