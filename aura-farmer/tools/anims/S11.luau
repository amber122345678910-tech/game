--!nocheck
-- Ключи анимации плана S11 (см. tools/lib/Pose.luau — формат ключей).
-- Конь-король на троне, левая нога закинута на правую. 13.133 «Cuz…» — взгляд вниз с оскалом, руки на
-- подлокотниках; на доле 13.334 кулаки вверх + голова запрокинута в хохоте (пик 13.50) -> руки широко в
-- стороны ладонями вверх («я лучший», с 13.63 почти неподвижно), голова выпрямляется к 13.95, дальше —
-- липсинк и самодовольная зубастая ухмылка. Камера низко, поэтому «голова прямо» = морда наклонена к камере.

-- ===== Ноги (неподвижны весь план, IK в мире) =====
-- Правая (нижняя): колено почти по центру, голень вертикально, стопа на носке упирается в подиум (Y=0.8).
local R_LEG = { ik = { 0.1, 1.35, 1.55 }, pole = { -0.3, 0.2, 1 }, foot = { palm = { 0, 0.92, 0.38 }, fingers = { -0.05, -0.38, 0.92 } } }
-- Левая (верхняя): колено поверх правого (самая высокая точка), голень по диагонали к правому боку перед правым коленом.
local L_LEG = { ik = { 0.25, 2.55, 2.3 }, pole = { -0.3, 1, 0.3 }, foot = { palm = { 0.45, 0.45, 0.77 }, fingers = { 0.4, -0.8, 0.45 } } }

-- ===== Руки (IK в мире, ориентация кисти — ладонь/пальцы) =====
local function arm(side, x, y, f, pole, palm, fingers)
	local s = if side == "r" then 1 else -1
	return {
		ik = { s * x, y, f },
		pole = { s * pole[1], pole[2], pole[3] },
		wrist = { palm = { s * palm[1], palm[2], palm[3] }, fingers = { s * fingers[1], fingers[2], fingers[3] } },
	}
end
-- на подлокотнике (шапка-свиток x=±1.92, верх 3.43, f 0.72…1.52)
local function rest(side, lift)
	lift = lift or 0
	if side == "r" then
		-- правая: кулак обхватывает передний завиток, пальцы через передний край
		return arm("r", 1.9 + lift * 0.15, 3.66 + lift, 0.95 + lift * 0.2, { 0.5, -0.4, -1 }, { -0.05, -1, 0.1 + lift }, { -0.05, -0.35 + lift, 1 })
	end
	-- левая: свободно свисает через край, пальцы вниз
	return arm("l", 1.9, 3.68, 0.98, { 0.5, -0.4, -1 }, { -0.1, -1, 0.35 }, { -0.05, -0.75, 1 })
end
-- кулак (костяшки вверх, ладонь к телу)
local function fist(side, x, y, f)
	return arm(side, x, y, f, { 0.6, -0.8, -0.3 }, { -1, -0.1, 0.25 }, { 0.15, 1, 0.35 })
end
-- раскрытые руки ладонями вверх; o — «раскрытость» 0..1 (поворот ладони вверх)
local function open(side, x, y, f, o)
	o = o or 1
	local palm = { -1 + 1.15 * o, 0.1 + 0.9 * o, 0.25 + 0.15 * o }
	local fingers = { 0.15 + 0.85 * o, 1 - 0.8 * o, 0.35 + 0.25 * o }
	return arm(side, x, y, f, { 0.35, -1, -0.25 }, palm, fingers)
end
-- поза «я лучший» (dy — дыхание/дрейф кистей)
local function spreadR(dy)
	return open("r", 2.8, 3.85 + (dy or 0), 1.15)
end
local function spreadL(dy)
	return open("l", 2.8, 4.05 + (dy or 0), 1.1)
end

local SPREAD_HAND = { curl = 0.2, thumb = 0.1, thumbOut = 0.6, spread = 0.6 }
local SPREAD_HAND2 = { curl = 0.26, thumb = 0.14, thumbOut = 0.55, spread = 0.55 }

-- ===== Корпус =====
-- таз сидит глубоко, сдвинут вперёд и развёрнут к правому боку (из-за закинутой ноги); грудь откинута и
-- повёрнута на ~5° влево; waist.bend < 0 — дополнительный откид груди назад
local ROOT = { y = 0.2, f = 0.5, turn = -18, bend = -14 }
local function W(bend, tilt)
	return { bend = bend, turn = 23, tilt = tilt or 0 }
end

-- ===== Лицо: jaw (0..1.2), grin всегда поднят (зубы видны), brows −1 хмурый … +1 удивлённый =====
local function F(jaw, brows, ears, mane)
	return { jaw = jaw, grin = 1, brows = brows or 0, ears = ears or 0, mane = mane or 0 }
end

local keys = {
	-- 13.133 «Cuz…»: голова опущена к камере, наклон к правому плечу, оскал; руки на подлокотниках
	{
		t = 13.1,
		root = ROOT,
		waist = W(2, 5),
		neck = { nod = 40, turn = 25, tilt = 16 },
		rArm = rest("r"),
		lArm = rest("l"),
		rLeg = R_LEG,
		lLeg = L_LEG,
		rHand = "grip",
		lHand = { curl = 0.45, thumb = 0.3, thumbOut = 0.3, spread = 0.25 },
		face = F(0.7, -0.8),
	},
	{ t = 13.1333, neck = { nod = 40, turn = 25, tilt = 16 }, face = F(0.7, -0.8) },
	{ t = 13.2, waist = W(2, 5), neck = { nod = 36, turn = 22, tilt = 15 }, rArm = rest("r"), lArm = rest("l"), rHand = "grip", lHand = { curl = 0.45, thumb = 0.3, thumbOut = 0.3, spread = 0.25 }, face = F(0.65, -0.7) },
	-- 13.267 предвкушение: голова поднимается, правая кисть отрывается от подлокотника, пальцы сжимаются
	{ t = 13.267, neck = { nod = 26, turn = 15, tilt = 15 }, rArm = rest("r", 0.3), rHand = { curl = 0.82, thumb = 0.6, thumbOut = 0.2 }, face = F(0.3, -0.2) },
	-- 13.334 ДОЛЯ: обе руки пошли вверх (ускорение), голова откидывается
	{ t = 13.334, ease = "in", waist = W(0, 4), neck = { nod = 14, turn = 10, tilt = 15 }, rArm = fist("r", 2.1, 4.0, 1.05), lArm = fist("l", 2.0, 4.05, 1.0), rHand = { curl = 0.92, thumb = 0.75, thumbOut = 0.1 }, lHand = { curl = 0.8, thumb = 0.6, thumbOut = 0.15 }, face = F(0.4, 0.2) },
	{ t = 13.367, rArm = fist("r", 2.4, 4.12, 0.95), lArm = fist("l", 2.2, 4.45, 0.85), rHand = "fist", lHand = "fist" },
	-- 13.40 двойной «флекс»: кулаки на уровне груди/плеча, голова назад
	{ t = 13.4, waist = W(-4, 3), neck = { nod = 3, turn = 9, tilt = 14 }, rArm = fist("r", 2.6, 4.12, 0.82), lArm = fist("l", 2.35, 4.75, 0.62), face = F(0.7, 0.6, 0.2) },
	{ t = 13.433, rArm = fist("r", 2.85, 4.08, 0.85), lArm = fist("l", 2.6, 4.8, 0.72), rHand = "fist", lHand = "fist" },
	-- 13.467 бросок: кисти раскрываются, ладони поворачиваются вверх
	{ t = 13.467, neck = { nod = -2, turn = 9, tilt = 11 }, rArm = open("r", 3.1, 4.0, 1.0, 0.6), lArm = open("l", 3.0, 4.5, 0.95, 0.6), rHand = { curl = 0.35, thumb = 0.2, thumbOut = 0.5, spread = 0.5 }, lHand = { curl = 0.35, thumb = 0.2, thumbOut = 0.5, spread = 0.5 }, face = F(1.35, 0.8, 0.35, 0.3) },
	-- 13.50 пик хохота: голова запрокинута, рот настежь; руки на максимуме (перелёт)
	{ t = 13.5, waist = W(-8, 2), neck = { nod = -2, turn = 10, tilt = 10 }, rArm = open("r", 3.15, 3.95, 1.15), lArm = open("l", 3.1, 4.3, 1.1), rHand = { curl = 0.05, thumb = 0.02, thumbOut = 0.8, spread = 0.9 }, lHand = { curl = 0.05, thumb = 0.02, thumbOut = 0.8, spread = 0.9 }, face = F(1.6, 0.9, 0.4, 0.45) },
	{ t = 13.533, rArm = open("r", 3.05, 3.86, 1.2), lArm = open("l", 3.02, 4.12, 1.15) },
	{ t = 13.567, face = F(1.55, 0.9, 0.4, 0.4) },
	-- 13.633 руки встали в позу, рот прикрылся в улыбку
	{ t = 13.633, waist = W(-6, 1), neck = { nod = 3, turn = 10, tilt = 9 }, rArm = spreadR(), lArm = spreadL(), rHand = SPREAD_HAND, lHand = SPREAD_HAND, face = F(0.75, 0.8, 0.35, 0.3) },
	-- второй импульс смеха
	{ t = 13.7, face = F(1.35, 0.8, 0.3, 0.2) },
	{ t = 13.733, ease = "out", waist = W(-3, 0), neck = { nod = 12, turn = 8, tilt = 7 } },
	{ t = 13.767, face = F(1.4, 0.75, 0.25, 0.1) },
	{ t = 13.833, waist = W(0, 0), neck = { nod = 21, turn = 5, tilt = 3 }, rArm = spreadR(-0.06), lArm = spreadL(-0.06), face = F(1.1, 0.6, 0.15, 0) },
	{ t = 13.9, face = F(0.6, 0.5, 0.1, 0) },
	-- 13.967 голова ровно (к камере), широкая улыбка
	{ t = 13.967, waist = W(2, 0), neck = { nod = 27, turn = 2, tilt = -5 }, face = F(0.35, 0.4, 0, 0) },
	{ t = 14.033, face = F(0.35, 0.4) },
	{ t = 14.1, face = F(0.7, 0.5) },
	{ t = 14.133, neck = { nod = 25, turn = 5, tilt = -4 }, rArm = spreadR(-0.04), lArm = spreadL(-0.04), rHand = SPREAD_HAND2, lHand = SPREAD_HAND2 },
	{ t = 14.167, face = F(0.9, 0.55) },
	{ t = 14.233, neck = { nod = 22, turn = 6, tilt = -4 }, face = F(1, 0.6) },
	{ t = 14.3, face = F(0.75, 0.5) },
	{ t = 14.333, neck = { nod = 24, turn = 6, tilt = -4 }, rHand = SPREAD_HAND, lHand = SPREAD_HAND },
	{ t = 14.367, face = F(0.5, 0.4) },
	{ t = 14.433, face = F(0.3, 0.3) },
	{ t = 14.467, neck = { nod = 27, turn = 4, tilt = -5 } },
	{ t = 14.5, face = F(0.18, 0.25) },
	-- дыхание: грудь чуть поднимается, кисти дрейфуют вверх
	{ t = 14.667, waist = W(1.2, 0), rArm = spreadR(0.03), lArm = spreadL(0.03), face = F(0.2, 0.25) },
	{ t = 14.767, face = F(0.35, 0.3) },
	{ t = 14.8, neck = { nod = 25, turn = 3, tilt = -5 } },
	{ t = 14.833, face = F(0.6, 0.45) },
	{ t = 14.9, face = F(0.7, 0.5) },
	{ t = 14.967, waist = W(2, 0), face = F(0.6, 0.45) },
	{ t = 15.033, face = F(0.7, 0.5) },
	{ t = 15.067, neck = { nod = 24, turn = 2, tilt = -5 }, rArm = spreadR(0), lArm = spreadL(0) },
	{ t = 15.1, face = F(0.7, 0.5) },
	{ t = 15.167, face = F(0.75, 0.55) },
	{ t = 15.2, neck = { nod = 25, turn = 1, tilt = -5 } },
	{ t = 15.233, face = F(0.55, 0.45) },
	{ t = 15.3, face = F(0.4, 0.35) },
	{ t = 15.333, waist = W(1.5, 0), neck = { nod = 31, turn = 0, tilt = -6 }, rHand = SPREAD_HAND2, lHand = SPREAD_HAND2 },
	{ t = 15.433, face = F(0.3, 0.3) },
	{ t = 15.65, waist = W(2, 0), neck = { nod = 31, turn = 0, tilt = -6 }, rArm = spreadR(0.02), lArm = spreadL(0.02), rHand = SPREAD_HAND2, lHand = SPREAD_HAND2, face = F(0.28, 0.3) },
}

return {
	Horse = { keys = keys },
}
