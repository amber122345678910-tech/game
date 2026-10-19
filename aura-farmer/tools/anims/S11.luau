--!nocheck
-- Ключи анимации плана S11 (см. tools/lib/Pose.luau — формат ключей).
-- Конь-король на троне: левая нога закинута на правую; руки на подлокотниках -> на доле 13.334
-- кулаки вверх + голова запрокинута в хохоте -> руки широко в стороны ладонями вверх («я лучший»).

-- ===== Ноги (неподвижны весь план) =====
-- Правая (нижняя) нога: бедро чуть вниз-внутрь, голень почти вертикально, стопа на носке до подиума (Y=0.8).
local R_LEG = { ik = { 0.1, 1.35, 1.55 }, pole = { -0.3, 0.2, 1 }, foot = { palm = { 0, 0.92, 0.38 }, fingers = { -0.05, -0.38, 0.92 } } }
-- Левая (верхняя) нога: колено поверх правого бедра по центру, голень по диагонали вниз к правому боку перед правым коленом.
local L_LEG = { ik = { 0.25, 2.55, 2.3 }, pole = { -0.3, 1, 0.3 }, foot = { palm = { 0.45, 0.45, 0.77 }, fingers = { 0.4, -0.8, 0.45 } } }

-- ===== Руки =====
-- На подлокотниках (передний завиток x=±1.92, верх ≈3.4, торец z=-1.48)
local function rArmRest(lift)
	lift = lift or 0
	return { ik = { 1.9, 3.68 + lift, 0.92 + lift * 0.3 }, pole = { 0.5, -0.4, -1 }, wrist = { palm = { -0.05, -1, 0.1 }, fingers = { -0.05, -0.35, 1 } } }
end
local function lArmRest()
	return { ik = { -1.9, 3.7, 0.95 }, pole = { -0.5, -0.4, -1 }, wrist = { palm = { 0.1, -1, 0.35 }, fingers = { 0.05, -0.75, 1 } } }
end
-- Кулаки вверх (дабл-флекс)
local function rArmFist()
	return { ik = { 2.5, 4.15, 1.0 }, pole = { 0.6, -0.8, -0.3 }, wrist = { palm = { -1, 0.1, 0.2 }, fingers = { 0.1, 0.6, 1 } } }
end
local function lArmFist()
	return { ik = { -2.55, 4.6, 0.85 }, pole = { -0.7, -0.8, -0.2 }, wrist = { palm = { 1, 0.1, 0.2 }, fingers = { -0.1, 0.8, 0.9 } } }
end
-- Руки в стороны ладонями вверх (dx/dy — небольшой дрейф)
local function rArmSpread(dx, dy)
	dx, dy = dx or 0, dy or 0
	return { ik = { 2.95 + dx, 3.85 + dy, 1.0 }, pole = { 0.4, -1, -0.4 }, wrist = { palm = { 0.15, 1, 0.35 }, fingers = { 1, 0.15, 0.55 } } }
end
local function lArmSpread(dx, dy)
	dx, dy = dx or 0, dy or 0
	return { ik = { -2.95 - dx, 4.05 + dy, 1.0 }, pole = { -0.4, -1, -0.4 }, wrist = { palm = { -0.15, 1, 0.35 }, fingers = { -1, 0.15, 0.55 } } }
end

local ROOT = { y = 0.2, f = 0.5, turn = -18, bend = -14 }

local keys = {
	-- 13.133 «Cuz…»: взгляд вниз с оскалом, руки на подлокотниках
	{
		t = 13.1,
		root = ROOT,
		waist = { bend = 2, turn = 23 },
		neck = { nod = 28, turn = 18, tilt = 14 },
		rArm = rArmRest(),
		lArm = lArmRest(),
		rLeg = R_LEG,
		lLeg = L_LEG,
		rHand = "grip",
		lHand = { curl = 0.45, thumb = 0.3, thumbOut = 0.3, spread = 0.25 },
		face = { jaw = 0.5, grin = 1, brows = -0.6 },
	},
	{ t = 13.1333, neck = { nod = 28, turn = 18, tilt = 14 }, rArm = rArmRest(), lArm = lArmRest(), face = { jaw = 0.5, grin = 1, brows = -0.6 } },
	{ t = 13.2, neck = { nod = 22, turn = 15, tilt = 14 }, rArm = rArmRest(0.05), lArm = lArmRest(), rHand = "grip", face = { jaw = 0.4, grin = 1, brows = -0.5 } },
	-- 13.267 предвкушение: голова поднимается, правая кисть отрывается
	{ t = 13.267, neck = { nod = 8, turn = 10, tilt = 14 }, rArm = rArmRest(0.3), lArm = lArmRest(), rHand = { curl = 0.8, thumb = 0.6, thumbOut = 0.2 }, face = { jaw = 0.25, grin = 1, brows = -0.2 } },
	-- 13.334 доля: руки пошли вверх, голова откидывается
	{ t = 13.334, ease = "in", root = ROOT, waist = { bend = 0, turn = 23 }, neck = { nod = -12, turn = 10, tilt = 14 }, rArm = { ik = { 2.15, 4.0, 1.05 }, pole = { 0.6, -0.7, -0.5 }, wrist = { palm = { -0.6, -0.4, 0.4 }, fingers = { 0.2, 0.2, 1 } } }, lArm = { ik = { -2.2, 4.1, 1.0 }, pole = { -0.6, -0.7, -0.5 }, wrist = { palm = { 0.6, -0.4, 0.4 }, fingers = { -0.2, 0.3, 1 } } }, rHand = { curl = 0.9, thumb = 0.7 }, lHand = { curl = 0.8, thumb = 0.6 }, face = { jaw = 0.3, grin = 1, brows = 0.2 } },
	-- 13.40 кулаки вверх, голова назад 45
	{ t = 13.4, root = { y = 0.2, f = 0.5, turn = -18, bend = -16 }, waist = { bend = -3, turn = 23 }, neck = { nod = -38, turn = 10, tilt = 14 }, rArm = rArmFist(), lArm = lArmFist(), rHand = "fist", lHand = "fist", face = { jaw = 0.45, grin = 1, brows = 0.5 } },
	-- 13.467 бросок: кисти раскрываются, перелёт наружу
	{ t = 13.467, rArm = { ik = { 3.15, 4.0, 1.05 }, pole = { 0.5, -1, -0.4 }, wrist = { palm = { 0.1, 1, 0.5 }, fingers = { 1, 0.3, 0.6 } } }, lArm = { ik = { -3.15, 4.25, 1.0 }, pole = { -0.5, -1, -0.4 }, wrist = { palm = { -0.1, 1, 0.5 }, fingers = { -1, 0.3, 0.6 } } }, rHand = "spread", lHand = "spread" },
	-- 13.50 пик хохота: голова назад 55, рот настежь
	{ t = 13.5, root = { y = 0.2, f = 0.5, turn = -18, bend = -20 }, waist = { bend = -4, turn = 23 }, neck = { nod = -48, turn = 14, tilt = 10 }, face = { jaw = 1.25, grin = 1, brows = 0.8, ears = 0.4 } },
	{ t = 13.533, rArm = rArmSpread(0.15, 0.05), lArm = lArmSpread(0.15, 0.05), rHand = { curl = 0.08, thumb = 0.05, thumbOut = 0.7, spread = 0.8 }, lHand = { curl = 0.08, thumb = 0.05, thumbOut = 0.7, spread = 0.8 } },
	-- 13.633 руки в стороны, рот прикрылся в улыбку
	{ t = 13.633, rArm = rArmSpread(), lArm = lArmSpread(), rHand = { curl = 0.18, thumb = 0.1, thumbOut = 0.6, spread = 0.6 }, lHand = { curl = 0.18, thumb = 0.1, thumbOut = 0.6, spread = 0.6 }, root = { y = 0.2, f = 0.5, turn = -18, bend = -18 }, waist = { bend = -3, turn = 23 }, neck = { nod = -40, turn = 15, tilt = 10 }, face = { jaw = 0.3, grin = 1, brows = 0.6, ears = 0.3 } },
	-- 13.733 второй импульс смеха
	{ t = 13.733, ease = "out", neck = { nod = -26, turn = 15, tilt = 8 }, root = { y = 0.2, f = 0.5, turn = -18, bend = -16 }, waist = { bend = -1, turn = 23 }, face = { jaw = 1.05, grin = 1, brows = 0.6, ears = 0.25 } },
	{ t = 13.833, neck = { nod = -10, turn = 12, tilt = 4 }, rArm = rArmSpread(0, -0.06), lArm = lArmSpread(0, -0.06), face = { jaw = 0.9, grin = 1, brows = 0.5, ears = 0.15 } },
	-- 13.967 голова ровно, широкая улыбка
	{ t = 13.967, root = ROOT, waist = { bend = 2, turn = 23 }, neck = { nod = 2, turn = 10, tilt = -5 }, face = { jaw = 0.25, grin = 1, brows = 0.3 } },
	{ t = 14.133, neck = { nod = -5, turn = 20, tilt = -4 }, rArm = rArmSpread(0, -0.04), lArm = lArmSpread(0, -0.04), rHand = { curl = 0.24, thumb = 0.12, thumbOut = 0.6, spread = 0.55 }, lHand = { curl = 0.24, thumb = 0.12, thumbOut = 0.6, spread = 0.55 }, face = { jaw = 0.6, grin = 1, brows = 0.4 } },
	{ t = 14.233, neck = { nod = -8, turn = 22, tilt = -4 }, face = { jaw = 0.8, grin = 1, brows = 0.5 } },
	{ t = 14.333, neck = { nod = -5, turn = 22, tilt = -4 }, face = { jaw = 0.6, grin = 1, brows = 0.4 } },
	{ t = 14.467, neck = { nod = 0, turn = 20, tilt = -5 }, face = { jaw = 0.15, grin = 1, brows = 0.2 } },
	{ t = 14.667, root = { y = 0.21, f = 0.5, turn = -18, bend = -12.5 }, waist = { bend = 1.5, turn = 23 }, rArm = rArmSpread(0, 0.02), lArm = lArmSpread(0, 0.02), face = { jaw = 0.15, grin = 1, brows = 0.2 } },
	{ t = 14.8, neck = { nod = -3, turn = 20, tilt = -5 }, face = { jaw = 0.55, grin = 1, brows = 0.4 } },
	{ t = 15.067, neck = { nod = -5, turn = 20, tilt = -5 }, face = { jaw = 0.6, grin = 1, brows = 0.5 } },
	{ t = 15.2, face = { jaw = 0.5, grin = 1, brows = 0.4 } },
	{ t = 15.333, root = ROOT, waist = { bend = 2, turn = 23 }, neck = { nod = 5, turn = 20, tilt = -5 }, rArm = rArmSpread(0, 0), lArm = lArmSpread(0, 0), face = { jaw = 0.22, grin = 1, brows = 0.2 } },
	{ t = 15.65, root = { y = 0.2, f = 0.5, turn = -18, bend = -12.5 }, waist = { bend = 2, turn = 23 }, neck = { nod = 5, turn = 20, tilt = -5 }, rArm = rArmSpread(0, 0.02), lArm = lArmSpread(0, 0.02), rHand = { curl = 0.24, thumb = 0.12, thumbOut = 0.6, spread = 0.55 }, lHand = { curl = 0.24, thumb = 0.12, thumbOut = 0.6, spread = 0.55 }, face = { jaw = 0.22, grin = 1, brows = 0.2 } },
}

return {
	Horse = { keys = keys },
}
