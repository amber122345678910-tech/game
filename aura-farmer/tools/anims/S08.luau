--!nocheck
-- S08 (7.867–9.533 с): ECU-«селфи» коня в жёлтых авиаторах, поёт «WAKE UP IN THE MORNING».
-- Поза как в S09: лежит на животе, грудь поднята (лук): таз на траве, руки в стороны-назад,
-- кулаки держат поднятые щиколотки. Камера неподвижна, всё движение — от коня:
--   голова подлетает на доли 16/17 (7.968, 8.456) и оседает на слабых долях; губы смыкаются на «p»
--   (8.27–8.33) и «m» (8.63–8.67); большой акцент «MOR-» на доле 18 (8.944): грудь и голова вверх,
--   подбородок назад, челюсть до упора; «-NING» — широкий оскал до конца плана.
-- Ключи головы/груди подобраны численно по трекингу очков в референсе (смещение в кадре, наклон, крен).
local ROOT = { y = -2.2, bend = 88 }
local GLASSES = { y = 0.1, f = 0.06 } -- очки сидят выше на переносице (иначе спинка носа закрывает линзы)

return {
	Horse = { keys = {
		-- ===== Тело и голова: таз лежит, грудь (waist) и шея ведут голову =====
		{ t = 7.867, ease = "out", root = ROOT, waist = { bend = -45.08, turn = 1.89 }, neck = { nod = -39.92, tilt = -3.74, turn = -0.21 } },
		{ t = 7.967, root = ROOT, waist = { bend = -48.41, turn = 2.07 }, neck = { nod = -38.09, tilt = -3.97, turn = -0.16 } },
		{ t = 8.033, root = ROOT, waist = { bend = -48.84, turn = 2.42 }, neck = { nod = -37.99, tilt = -4.32, turn = -0.17 } },
		{ t = 8.133, root = ROOT, waist = { bend = -47.4, turn = 4.01 }, neck = { nod = -39.28, tilt = -5.81, turn = -0.3 } },
		{ t = 8.2, root = ROOT, waist = { bend = -46.61, turn = 3.83 }, neck = { nod = -39.73, tilt = -5.62, turn = -0.32 } },
		{ t = 8.267, root = ROOT, waist = { bend = -45.96, turn = 2.7 }, neck = { nod = -40.05, tilt = -4.54, turn = -0.25 } },
		{ t = 8.333, root = ROOT, waist = { bend = -46.11, turn = 2.68 }, neck = { nod = -40.22, tilt = -4.53, turn = -0.22 } },
		{ t = 8.433, root = ROOT, waist = { bend = -47.24, turn = 3.48 }, neck = { nod = -39.93, tilt = -5.33, turn = -0.22 } },
		{ t = 8.5, root = ROOT, waist = { bend = -46.95, turn = 3.63 }, neck = { nod = -40.39, tilt = -5.49, turn = -0.22 } },
		{ t = 8.567, root = ROOT, waist = { bend = -46.7, turn = 3 }, neck = { nod = -40.3, tilt = -4.86, turn = -0.21 } },
		{ t = 8.65, root = ROOT, waist = { bend = -45.93, turn = 2.66 }, neck = { nod = -40.66, tilt = -3.77, turn = -0.21 } },
		{ t = 8.7, ease = "out", root = ROOT, waist = { bend = -45.94, turn = 2.72 }, neck = { nod = -41.55, tilt = -2.95, turn = -0.16 } },
		{ t = 8.767, root = ROOT, waist = { bend = -48.13, turn = 3.58 }, neck = { nod = -41.38, tilt = -2.55, turn = -0.04 } },
		{ t = 8.833, root = ROOT, waist = { bend = -49.57, turn = 3.53 }, neck = { nod = -40.59, tilt = -2.29, turn = 0.01 } },
		{ t = 8.9, root = ROOT, waist = { bend = -51.53, turn = 3.32 }, neck = { nod = -39.14, tilt = -1.85, turn = 0.05 } },
		{ t = 9, root = ROOT, waist = { bend = -53.27, turn = 3.23 }, neck = { nod = -37.73, tilt = -1.77, turn = 0.07 } },
		{ t = 9.067, root = ROOT, waist = { bend = -51.08, turn = 3.48 }, neck = { nod = -39.92, tilt = -2.03, turn = 0.08 } },
		{ t = 9.133, root = ROOT, waist = { bend = -48.22, turn = 3.01 }, neck = { nod = -41.79, tilt = -1.84, turn = 0 } },
		{ t = 9.2, root = ROOT, waist = { bend = -46.59, turn = 3.15 }, neck = { nod = -42.58, tilt = -2.11, turn = -0.06 } },
		{ t = 9.267, root = ROOT, waist = { bend = -45.61, turn = 3.37 }, neck = { nod = -42.89, tilt = -2.29, turn = -0.12 } },
		{ t = 9.333, root = ROOT, waist = { bend = -45.6, turn = 3.37 }, neck = { nod = -42.57, tilt = -2.27, turn = -0.15 } },
		{ t = 9.433, root = ROOT, waist = { bend = -46.69, turn = 3.29 }, neck = { nod = -41.64, tilt = -2.21, turn = -0.13 } },
		{ t = 9.533, root = ROOT, waist = { bend = -47.81, turn = 3.21 }, neck = { nod = -40.69, tilt = -2.14, turn = -0.11 } },
		-- ===== Руки и ноги: кулаки держат щиколотки; «пожимание» левым плечом на долях =====
		{ t = 7.8667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.35, 1.6, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.35, 1.35, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 7.9667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.333, 1.642, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.333, 1.392, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.0667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.312, 1.69, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.312, 1.44, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.1667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.33, 1.648, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.33, 1.398, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.2667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.35, 1.6, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.35, 1.35, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.3667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.31, 1.696, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.31, 1.446, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.4667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.3, 1.72, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.3, 1.47, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.5667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.31, 1.696, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.31, 1.446, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.6667, rArm = { ik = { 2.35, 1.5, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.343, 1.618, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.35, 1.25, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.343, 1.368, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.7667, rArm = { ik = { 2.368, 1.458, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.343, 1.618, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.368, 1.208, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.343, 1.368, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.8667, rArm = { ik = { 2.337, 1.53, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.315, 1.684, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.337, 1.28, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.315, 1.434, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 8.9667, rArm = { ik = { 2.323, 1.566, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.303, 1.714, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.323, 1.316, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.303, 1.464, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 9.0333, rArm = { ik = { 2.312, 1.59, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.303, 1.714, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.312, 1.34, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.303, 1.464, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 9.1667, rArm = { ik = { 2.323, 1.566, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.32, 1.672, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.323, 1.316, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.32, 1.422, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 9.2667, rArm = { ik = { 2.348, 1.506, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.348, 1.606, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.348, 1.256, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.348, 1.356, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 9.3667, rArm = { ik = { 2.34, 1.524, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.335, 1.636, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.34, 1.274, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.335, 1.386, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 9.4667, rArm = { ik = { 2.325, 1.56, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.312, 1.69, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.325, 1.31, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.312, 1.44, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		{ t = 9.5333, rArm = { ik = { 2.325, 1.56, 0.75 }, pole = { 1, 1.5, -0.3 } }, lArm = { ik = { -2.312, 1.69, 0.75 }, pole = { -0.8, 1.8, -0.3 } }, rLeg = { ik = { 2.325, 1.31, 0.7 }, pole = { 0.5, -1, 0 } }, lLeg = { ik = { -2.312, 1.44, 0.7 }, pole = { -0.5, -1, 0 } }, rHand = "fist", lHand = "fist" },
		-- ===== Лицо: «WAKE UP IN THE MOR-NING» (jaw — челюсть, grin — верхняя губа/зубы) =====
		{ t = 7.8667, face = { jaw = 0.17, grin = 0, brows = -0.2, ears = 0, mane = 0 } },  -- «WA-»: округлый гласный, чуть видны верхние зубы
		{ t = 7.9, face = { jaw = 0.2, grin = 0, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 7.9333, face = { jaw = 0.22, grin = 0, brows = -0.2, ears = 0, mane = 0 } },  -- «WAKE»: пик гласной
		{ t = 8.0333, face = { jaw = 0.22, grin = 0.1, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.0667, face = { jaw = 0.21, grin = 0.2, brows = -0.2, ears = 0, mane = 0 } },  -- «-AKE»: край верхних зубов
		{ t = 8.1, face = { jaw = 0.19, grin = 0.1, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.1667, face = { jaw = 0.17, grin = 0.05, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.2, face = { jaw = 0.12, grin = 0.25, brows = -0.2, ears = 0, mane = 0 } },  -- закрывается, видны оба ряда зубов
		{ t = 8.2333, face = { jaw = 0.03, grin = -0.1, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.2667, face = { jaw = -0.1, grin = -0.4, brows = -0.2, ears = 0, mane = 0 } },  -- «P» в «UP»: губы сомкнуты
		{ t = 8.3333, face = { jaw = -0.1, grin = -0.4, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.3667, face = { jaw = 0.14, grin = 0, brows = -0.2, ears = 0, mane = 0 } },  -- «IN»: щелчок за 1 кадр
		{ t = 8.4, face = { jaw = 0.17, grin = 0.1, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.4333, face = { jaw = 0.12, grin = 0.7, brows = -0.2, ears = 0, mane = 0 } },  -- «IN / THE»: оскал, зубы оголены
		{ t = 8.5, face = { jaw = 0.12, grin = 0.7, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.5333, face = { jaw = 0.17, grin = 0.3, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.5667, face = { jaw = 0.2, grin = 0, brows = -0.2, ears = 0, mane = 0 } },  -- «THE»: круглее
		{ t = 8.6, face = { jaw = 0.09, grin = -0.1, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.6333, face = { jaw = -0.08, grin = -0.35, brows = -0.2, ears = 0, mane = 0 } },  -- «M» в «MORNING»: губы сомкнуты
		{ t = 8.6667, face = { jaw = -0.08, grin = -0.35, brows = -0.2, ears = 0, mane = 0 } },
		{ t = 8.7, face = { jaw = 0.12, grin = 0.4, brows = -0.1, ears = 0, mane = 0 } },  -- упреждение: верхние зубы
		{ t = 8.7333, face = { jaw = 0.5, grin = 0.35, brows = 0.1, ears = 0, mane = 0.1 } },  -- «MOR-»: челюсть падает
		{ t = 8.7667, face = { jaw = 0.62, grin = 0.35, brows = 0.2, ears = 0, mane = 0.25 } },
		{ t = 8.8, face = { jaw = 0.72, grin = 0.4, brows = 0.25, ears = 0, mane = 0.35 } },
		{ t = 8.8667, face = { jaw = 0.8, grin = 0.4, brows = 0.3, ears = 0, mane = 0.3 } },  -- максимум: вытянутое «O», верхние зубы
		{ t = 9, face = { jaw = 0.8, grin = 0.45, brows = 0.3, ears = 0, mane = 0.15 } },
		{ t = 9.0333, face = { jaw = 0.72, grin = 0.65, brows = 0.25, ears = 0, mane = 0.1 } },  -- расширяется в «-NING»
		{ t = 9.0667, face = { jaw = 0.42, grin = 1, brows = 0.15, ears = 0, mane = 0.05 } },  -- «-NING»: широкий оскал, оба ряда зубов
		{ t = 9.1, face = { jaw = 0.58, grin = 1, brows = 0.1, ears = 0, mane = 0 } },  -- язык виден
		{ t = 9.1667, face = { jaw = 0.58, grin = 1, brows = 0.1, ears = 0, mane = 0 } },
		{ t = 9.2, face = { jaw = 0.52, grin = 1, brows = 0.05, ears = 0, mane = 0 } },
		{ t = 9.2333, face = { jaw = 0.46, grin = 1, brows = 0, ears = 0, mane = 0 } },
		{ t = 9.2667, face = { jaw = 0.42, grin = 1, brows = 0, ears = 0, mane = 0 } },  -- оскал держится
		{ t = 9.4333, face = { jaw = 0.42, grin = 1, brows = 0, ears = 0, mane = 0 } },
		{ t = 9.4667, face = { jaw = 0.46, grin = 1, brows = 0.05, ears = 0, mane = 0 } },
		{ t = 9.5333, face = { jaw = 0.46, grin = 1, brows = 0.05, ears = 0, mane = 0 } },
		-- ===== Очки: сидят на переносице, лёгкое запаздывание на рывке «MOR-» =====
		{ t = 7.8667, joints = { Glasses = { y = 0.1, f = 0.06, rx = 0 } } },
		{ t = 8.7, joints = { Glasses = { y = 0.1, f = 0.06, rx = 0 } } },
		{ t = 8.7667, joints = { Glasses = { y = 0.088, f = 0.06, rx = 1.5 } } },
		{ t = 8.8667, joints = { Glasses = { y = 0.104, f = 0.06, rx = -0.5 } } },
		{ t = 8.9667, joints = { Glasses = { y = 0.1, f = 0.06, rx = 0 } } },
		{ t = 9.5333, joints = { Glasses = { y = 0.1, f = 0.06, rx = 0 } } },
	} },
}
