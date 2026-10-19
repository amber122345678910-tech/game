--!nocheck
-- Ключи анимации плана S10 (см. tools/lib/Pose.luau — формат ключей).
-- Конь сидит верхом на переднем конце скамьи лицом к камере, качает гантель «500 KG» правой рукой
-- в долю: подъём на долях 23 и 25 (11.383, 12.358), опускание на 24 и 26 (11.870, 12.846);
-- движение — первая половина доли (~0.24 с), вторая половина — стоп-поза. Левая ладонь лежит на левом колене.
-- Статисты за ним делают махи ногой назад синхронно с гантелью.

local B23, B24, B25, B26 = 11.382, 11.870, 12.358, 12.846

local function merge(...)
	local out = {}
	for _, t in { ... } do
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

-- ===================== КОНЬ =====================
local LEGS = {
	root = { y = -0.72, f = 0, bend = 8 },
	rLeg = { ik = { 1.42, 0.62, 0.95 }, pole = { 0.7, 0.2, 1 } },
	lLeg = { ik = { -1.42, 0.62, 0.95 }, pole = { -0.7, 0.2, 1 } },
}
-- левая ладонь на левом колене
local LARM = { lArm = { ik = { -1.36, 2.25, 0.85 }, pole = { -1, 0.1, -0.3 }, wrist = { palm = { 0, -1, 0 }, fingers = { 0.2, -0.5, 1 } } }, lHand = { curl = 0.4, thumb = 0.2, thumbOut = 0.5, spread = 0.1 } }

-- правая рука: внизу (гантель у правого колена), середина подъёма, верх (у морды)
local function rArmDown(dy)
	return { ik = { 2.75, 1.8 + (dy or 0), 1.6 }, pole = { 1, 0.2, -0.6 }, wrist = { palm = { -0.45, 0, -0.9 }, fingers = { 0, -1, 0 } } }
end
local R_MID = { ik = { 2.55, 2.75, 1.6 }, pole = { 1, -0.4, -0.4 }, wrist = { palm = { -0.8, 0, -0.6 }, fingers = { 0.3, 0.2, 0.6 } } }
local function rArmUp(dy)
	return { ik = { 2.45, 3.38 + (dy or 0), 2.15 }, pole = { 0.6, -1, -0.2 }, wrist = { palm = { -0.82, 0, -0.55 }, fingers = { -0.1, 1, 0.15 } } }
end
local R_MID_DN = { ik = { 2.55, 2.6, 1.6 }, pole = { 1, -0.4, -0.4 }, wrist = { palm = { -0.8, 0, -0.6 }, fingers = { 0.3, 0.2, 0.6 } } }

local W_DOWN = { bend = 30, turn = 16, tilt = 18 }
local W_MID = { bend = 24, turn = 4, tilt = 9 }
local W_UP = { bend = 18, turn = -4, tilt = 2 }
local W_UP_OS = { bend = 16, turn = -5, tilt = 1 }

local DB_DOWN = { Dumbbell = { rz = 0 } }
local DB_MID = { Dumbbell = { rz = 45 } }
local DB_UP = { Dumbbell = { rz = 88 } }

local function bodyKey(t, waist, rArm, db, ease)
	return merge(LEGS, LARM, { t = t, waist = waist, rArm = rArm, rHand = "fist", joints = db, ease = ease })
end

local horse = {
	-- нижняя стоп-поза
	bodyKey(11.0, W_DOWN, rArmDown(), DB_DOWN),
	bodyKey(11.1333, W_DOWN, rArmDown(), DB_DOWN),
	bodyKey(11.30, { bend = 30.5, turn = 16, tilt = 18.5 }, rArmDown(0.01), DB_DOWN),
	-- упреждение: кисть и плечо чуть проседают
	bodyKey(B23 - 0.01, { bend = 31.5, turn = 16.5, tilt = 19.5 }, rArmDown(-0.06), DB_DOWN),
	-- подъём (резкий, ease-out) с перелётом
	bodyKey(B23 + 0.095, W_MID, R_MID, DB_MID),
	bodyKey(B23 + 0.215, W_UP_OS, rArmUp(0.08), DB_UP),
	bodyKey(B23 + 0.29, W_UP, rArmUp(), DB_UP),
	-- верхняя стоп-поза
	bodyKey(B24 - 0.005, { bend = 18.5, turn = -4, tilt = 2.5 }, rArmUp(-0.01), DB_UP),
	-- опускание (sine in-out)
	bodyKey(B24 + 0.12, W_MID, R_MID_DN, DB_MID),
	bodyKey(B24 + 0.245, W_DOWN, rArmDown(-0.02), DB_DOWN),
	bodyKey(B24 + 0.30, W_DOWN, rArmDown(), DB_DOWN),
	-- нижняя стоп-поза 2
	bodyKey(B25 - 0.01, { bend = 31.5, turn = 16.5, tilt = 19.5 }, rArmDown(-0.06), DB_DOWN),
	bodyKey(B25 + 0.095, W_MID, R_MID, DB_MID),
	bodyKey(B25 + 0.215, W_UP_OS, rArmUp(0.08), DB_UP),
	bodyKey(B25 + 0.29, W_UP, rArmUp(), DB_UP),
	bodyKey(B26 - 0.005, { bend = 18.5, turn = -4, tilt = 2.5 }, rArmUp(-0.01), DB_UP),
	bodyKey(B26 + 0.12, W_MID, R_MID_DN, DB_MID),
	bodyKey(B26 + 0.245, W_DOWN, rArmDown(-0.02), DB_DOWN),
	bodyKey(13.25, W_DOWN, rArmDown(), DB_DOWN),
}

-- голова/шея (отдельная дорожка: кивки, подъём головы при пении)
local NECK = {
	{ 11.0, -8, -28, 7 },
	{ 11.1333, -8, -28, 7 },
	{ 11.30, -7, -28, 7 },
	{ B23 + 0.10, -8, -24, 4 },
	{ B23 + 0.25, -6, -22, 6 },
	{ 11.75, -4, -22, 6 }, -- кивок вниз в стоп-позе
	{ B24, -7, -22, 6 },
	{ 12.0, -14, -24, 5 }, -- AIN'T: голова вверх
	{ 12.133, -12, -26, 4 },
	{ 12.333, -18, -26, 2 }, -- GOT: запрокинута
	{ B25 + 0.08, -16, -24, 3 },
	{ 12.533, -22, -22, 2 }, -- NO
	{ 12.633, -16, -21, 5 },
	{ 12.767, -18, -21, 5 }, -- WOR-
	{ B26 + 0.02, -17, -22, 5 },
	{ 12.967, -12, -24, 5 }, -- -RIES
	{ 13.1, -14, -26, 4 },
	{ 13.25, -14, -26, 4 },
}
for _, n in NECK do
	table.insert(horse, { t = n[1], neck = { nod = n[2], turn = n[3], tilt = n[4] } })
end

-- лицо: челюсть (0 — зубы сомкнуты), оскал, брови, уши
local FACE = {
	-- t, jaw, grin, brows, ears
	{ 11.0, 0.04, 1, 0, 0 },
	{ 11.1333, 0.04, 1, 0, 0 },
	{ 11.5, 0.1, 1, 0.1, 0 },
	{ 11.633, 0.16, 1, 0.2, -0.1 },
	{ 11.867, 0.2, 1, 0.2, -0.1 },
	{ 11.93, 0.3, 1, 0.3, 0 },
	{ 12.0, 0.45, 1, 0.5, 0.1 }, -- AIN'T
	{ 12.133, 0.33, 1, 0.4, 0.1 },
	{ 12.25, 0.4, 1, 0.4, 0.1 },
	{ 12.333, 0.75, 1, 0.7, 0.2 }, -- GOT
	{ 12.4, 0.48, 1, 0.5, 0.1 },
	{ 12.533, 0.8, 1, 0.8, 0.2 }, -- NO
	{ 12.633, 0.58, 1, 0.6, 0.1 },
	{ 12.767, 0.8, 0.6, 0.7, 0.2 }, -- WOR- (округлый рот, губы вперёд)
	{ 12.867, 0.7, 0.7, 0.6, 0.1 },
	{ 12.967, 0.3, 1, 0.5, 0 }, -- -RIES (широкий оскал)
	{ 13.1, 0.55, 1, 0.6, 0.1 },
	{ 13.25, 0.55, 1, 0.6, 0.1 },
}
for _, f in FACE do
	table.insert(horse, { t = f[1], face = { jaw = f[2], grin = f[3], brows = f[4], ears = f[5] } })
end

return {
	Horse = { keys = horse },
}
