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
		-- ===== Тело (черновик): лежит, грудь почти вертикально =====
		{ t = 7.8667, root = { y = -2.2, bend = 88 }, waist = { bend = -50 }, neck = { nod = -24 },
			rArm = { ik = { 2.15, 1.75, 3.35 }, pole = { 1, 0.2, 0 } }, lArm = { ik = { -2.2, 2.45, 3.3 }, pole = { -1, 0.6, 0 } },
			rLeg = { ik = { 0.8, 1.4, -1.6 }, pole = { 1, -1, 0 } }, lLeg = { ik = { -0.8, 1.4, -1.6 }, pole = { -1, -1, 0 } },
			rHand = "fist", lHand = "fist" },
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
	} },
}
