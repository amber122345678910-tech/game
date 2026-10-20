--!nocheck
-- Ключи анимации плана S10 (см. tools/lib/Pose.luau — формат ключей).
-- Конь сидит верхом на переднем конце скамьи лицом к камере, качает гантель «500 KG» правой рукой
-- в долю: подъём на долях 23 и 25 (11.382, 12.358), опускание на 24 и 26 (11.870, 12.846);
-- движение — первая половина доли (~0.24 с), вторая половина — стоп-поза. Левая ладонь лежит на левом колене.
-- Корпус наклонён к коленям и «складывается» на опускании; голова повёрнута и наклонена к правому плечу.
-- Статисты за ним делают махи ногой назад синхронно с гантелью.

local B23, B24, B25, B26 = 11.3824, 11.8702, 12.358, 12.8458

local function merge(...)
	local out = {}
	for _, t in { ... } do
		for k, v in t do
			out[k] = v
		end
	end
	return out
end
local function lerp(a, b, k)
	return a + (b - a) * k
end
local function lerpV(a, b, k)
	return { lerp(a[1], b[1], k), lerp(a[2], b[2], k), lerp(a[3], b[3], k) }
end
local function lerpT(A, B, k)
	local o = {}
	for key, va in A do
		o[key] = lerp(va, B[key] or 0, k)
	end
	return o
end

-- ===================== КОНЬ =====================
-- Фаза «сгиба» k: 0 — гантель внизу, 1 — вверху (k<0 — упреждающий присед, k>1 — перелёт).
local CURL = {
	{ 11.0, 0 },
	{ 11.1333, 0 },
	{ 11.26, 0.01 },
	{ B23 - 0.016, -0.07 }, -- упреждение: кисть и плечо чуть проседают
	{ B23 + 0.1, 0.62, "out" }, -- подъём: резкий старт (cubic out)
	{ B23 + 0.215, 1.06 }, -- перелёт ~3°
	{ B23 + 0.3, 1.0 },
	{ B24 - 0.005, 0.99 },
	{ B24 + 0.13, 0.5 }, -- опускание: sine in-out
	{ B24 + 0.255, -0.02 },
	{ B24 + 0.32, 0 },
	{ B25 - 0.016, -0.07 },
	{ B25 + 0.1, 0.62, "out" },
	{ B25 + 0.215, 1.06 },
	{ B25 + 0.3, 1.0 },
	{ B26 - 0.005, 0.99 },
	{ B26 + 0.13, 0.5 },
	{ B26 + 0.255, -0.02 },
	{ 13.25, 0 },
}
local function curlAt(t)
	if t <= CURL[1][1] then
		return CURL[1][2]
	end
	for i = 1, #CURL - 1 do
		local a, b = CURL[i], CURL[i + 1]
		if t <= b[1] then
			return lerp(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
		end
	end
	return CURL[#CURL][2]
end

-- таз: сидит на сиденье, наклонён вперёд
local ROOT = { y = -0.72, f = 0, bend = 10, turn = 0, tilt = 0 }
-- верх корпуса: внизу — наклон к коленям, крен и поворот к правому плечу; вверху — выпрямляется
local W_DN = { bend = 24, turn = -8, tilt = 12 }
local W_UP = { bend = 9, turn = 4, tilt = 0 }
local function waistK(k)
	return lerpT(W_DN, W_UP, k)
end

local LEGS = {
	root = ROOT,
	rLeg = { ik = { 1.42, 0.62, 0.95 }, pole = { 0.7, 0.2, 1 } },
	lLeg = { ik = { -1.42, 0.62, 0.95 }, pole = { -0.7, 0.2, 1 } },
}
-- левая ладонь на левом колене
local LARM = {
	lArm = { ik = { -1.36, 2.25, 0.85 }, pole = { -1, 0.1, -0.3 }, wrist = { palm = { 0, -1, 0 }, fingers = { 0.2, -0.5, 1 } } },
	lHand = { curl = 0.4, thumb = 0.2, thumbOut = 0.5, spread = 0.1 },
}

-- правая рука: низ (гантель у правого колена), середина, верх (у морды)
local A_DN = { ik = { 2.9, 1.68, 1.8 }, pole = { 1, 0.1, -0.5 }, palm = { -0.45, 0, -0.9 }, fingers = { 0, -1, 0 } }
local A_MID = { ik = { 2.8, 2.3, 1.95 }, pole = { 1, -0.5, -0.4 }, palm = { -0.18, 0.79, -0.57 }, fingers = { 0.25, 0.6, 0.75 } }
local A_UP = { ik = { 2.45, 3.38, 2.15 }, pole = { 0.6, -1, -0.2 }, palm = { -0.82, 0, -0.55 }, fingers = { -0.1, 1, 0.15 } }
local function armOf(a, dy)
	return { ik = { a.ik[1], a.ik[2] + (dy or 0), a.ik[3] }, pole = a.pole, wrist = { palm = a.palm, fingers = a.fingers } }
end
local function lerpArm(a, b, k)
	return { ik = lerpV(a.ik, b.ik, k), pole = lerpV(a.pole, b.pole, k), palm = lerpV(a.palm, b.palm, k), fingers = lerpV(a.fingers, b.fingers, k) }
end
local K_MID = 0.6
local function armK(k)
	if k <= 0 then
		return armOf(A_DN, k * 0.9)
	elseif k <= K_MID then
		return armOf(lerpArm(A_DN, A_MID, k / K_MID))
	elseif k <= 1 then
		return armOf(lerpArm(A_MID, A_UP, (k - K_MID) / (1 - K_MID)))
	end
	return armOf(A_UP, (k - 1) * 1.4)
end
local function dbK(k)
	return { Dumbbell = { rz = 88 * math.clamp(k, 0, 1.03) } }
end

local horse = {}
for _, c in CURL do
	local k = c[2]
	table.insert(horse, merge(LEGS, LARM, {
		t = c[1],
		ease = c[3],
		waist = waistK(k),
		rArm = armK(k),
		rHand = "fist",
		joints = dbK(k),
	}))
end

-- голова: мировые углы (вверх+, вправо+ — к правому плечу коня, крен к правому плечу+); шея = голова − корпус
local HEAD = {
	{ 11.0, -15, 25, 20 },
	{ 11.1333, -15, 25, 20 },
	{ 11.3, -15, 25, 20 },
	{ B23 + 0.1, -10, 20, 20 },
	{ B23 + 0.25, -5, 15, 20 },
	{ 11.75, -8, 15, 20 }, -- лёгкий кивок в верхней стоп-позе
	{ B24, -5, 15, 20 },
	{ 12.0, 5, 18, 19 }, -- AIN'T: голова вверх
	{ 12.133, 0, 20, 18 },
	{ 12.25, 3, 20, 17 },
	{ 12.333, 10, 20, 15 }, -- GOT: запрокинута
	{ 12.43, 8, 18, 15 },
	{ 12.533, 12, 16, 15 }, -- NO
	{ 12.633, 5, 15, 18 },
	{ 12.767, 8, 15, 18 }, -- WOR-
	{ B26 + 0.02, 6, 16, 18 },
	{ 12.967, 0, 18, 18 }, -- -RIES
	{ 13.1, 2, 20, 18 },
	{ 13.25, 2, 20, 18 },
}
for _, h in HEAD do
	local w = waistK(curlAt(h[1]))
	table.insert(horse, {
		t = h[1],
		neck = {
			nod = -h[2] - (ROOT.bend + w.bend),
			turn = -h[3] - (ROOT.turn + w.turn),
			tilt = h[4] - (ROOT.tilt + w.tilt),
		},
	})
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

-- ===================== СТАТИСТЫ =====================
-- Махи ногой назад («glute kick-back») синхронно с гантелью: вверх на долях 23/25, вниз на 24/26.
-- Руки на поясе (стойки с гантелями в декорации далеко — опереться не на что).
local UP_T = { B23, B25 }
local DN_T = { B24, B26 }

-- kicker: { side = "r"|"l", hinge = градусы наклона корпуса, legBack = угол ноги назад от вертикали (мир),
--           hipX = полуширина таза, headDown/headUp = кивки, turnUp = поворот головы в верхней позе }
local function kicker(o)
	local keys = {}
	local kick = o.side .. "Leg"
	local stand = (if o.side == "r" then "l" else "r") .. "Leg"
	local sx = if o.side == "r" then -1 else 1 -- x опорной ноги (знак)
	local function arms()
		return {
			rArm = { ik = { o.hipX + 0.42, o.waistY - 0.05, 0.12 }, space = "hips", pole = { 1, -0.2, -0.5 }, wrist = { palm = { -1, 0.2, 0 }, fingers = { 0.1, -0.6, 1 } } },
			lArm = { ik = { -(o.hipX + 0.42), o.waistY - 0.05, 0.12 }, space = "hips", pole = { -1, -0.2, -0.5 }, wrist = { palm = { 1, 0.2, 0 }, fingers = { -0.1, -0.6, 1 } } },
			rHand = "relaxed",
			lHand = "relaxed",
		}
	end
	local function pose(t, k, drift, ease)
		-- k = 0 стоит, 1 — нога назад; drift — покачивание ноги в стоп-позе (градусы)
		local bend = o.hinge * k
		local key = merge(arms(), {
			t = t,
			ease = ease,
			root = { y = -0.04 * k, f = -o.shift * k, bend = bend * 0.8 },
			waist = { bend = bend * 0.2 + (o.lean or 0) * (1 - k), turn = 0, tilt = 0 },
		})
		key[stand] = { ik = { sx * o.hipX, o.ankleY, 0.05 } }
		key[kick] = { fwd = -(o.legBack - bend * 0.8) * k - (drift or 0) + 3 * (1 - k), out = 3, knee = 4 + 30 * (1 - k) * 0, ankle = { bend = -40 * k } }
		return key
	end
	local function swing(t0, up)
		-- подъём: cubic out; опускание: sine in-out; ~0.24 с
		if up then
			table.insert(keys, pose(t0 - 0.01, 0, 0))
			table.insert(keys, pose(t0 + 0.11, 0.62, 0))
			table.insert(keys, pose(t0 + 0.24, 1.03, 0))
			table.insert(keys, pose(t0 + 0.3, 1, 0))
			table.insert(keys, pose(t0 + 0.4, 1, 4))
		else
			table.insert(keys, pose(t0 - 0.01, 1, 1))
			table.insert(keys, pose(t0 + 0.12, 0.45, 0))
			table.insert(keys, pose(t0 + 0.24, 0, 0))
			table.insert(keys, pose(t0 + 0.32, 0, 0))
		end
	end
	table.insert(keys, pose(11.0, 0, 0))
	table.insert(keys, pose(11.1333, 0, 0))
	for i = 1, 2 do
		swing(UP_T[i], true)
		swing(DN_T[i], false)
	end
	table.insert(keys, pose(13.25, 0, 0))
	-- голова
	for _, h in o.head do
		table.insert(keys, { t = h[1], neck = { nod = h[2], turn = h[3], tilt = h[4] or 0 }, face = h[5] })
	end
	return { keys = keys }
end

local ginger = kicker({
	side = "r",
	hinge = 62,
	legBack = 88,
	shift = 0.35,
	lean = 4,
	hipX = 0.405,
	waistY = 2.38,
	ankleY = 0.25,
	head = {
		{ 11.0, -20, -8, 0, { smile = 0.6 } },
		{ 11.1333, -20, -8, 0, { smile = 0.6 } },
		{ B23 + 0.05, -16, -6, 0, { smile = 0.5 } },
		{ B23 + 0.25, 25, 0, 0, { smile = 0.3 } },
		{ B24, 25, 0, 0, { smile = 0.3 } },
		{ B24 + 0.26, -15, -8, 0, { smile = 0.6 } },
		{ B25 + 0.02, -15, -8, 0, { smile = 0.6 } },
		{ B25 + 0.25, 25, 0, 0, { smile = 0.3 } },
		{ B26, 25, 0, 0, { smile = 0.3 } },
		{ B26 + 0.26, -15, -8, 0, { smile = 0.5 } },
		{ 13.25, -15, -8, 0, { smile = 0.5 } },
	},
})

local curly = kicker({
	side = "r",
	hinge = 34,
	legBack = 76,
	shift = 0.22,
	lean = 8,
	hipX = 0.47,
	waistY = 2.45,
	ankleY = 0.26,
	head = {
		{ 11.0, -4, -12, 0, { smile = 0.4 } },
		{ 11.1333, -4, -12, 0, { smile = 0.4 } },
		{ B23 + 0.05, -2, 0, 0, { smile = 0.5 } },
		{ B23 + 0.25, 4, 26, -6, { smile = 0.8, squint = 0.2 } },
		{ B24, 5, 26, -6, { smile = 0.8, squint = 0.2 } },
		{ B24 + 0.26, -4, -10, 0, { smile = 0.6 } },
		{ B25 + 0.02, -4, -10, 0, { smile = 0.6 } },
		{ B25 + 0.25, 4, 26, -6, { smile = 1, jaw = 0.1, squint = 0.3 } },
		{ B26, 5, 26, -6, { smile = 1, jaw = 0.1, squint = 0.3 } },
		{ B26 + 0.26, -4, -12, 0, { smile = 0.6 } },
		{ 13.25, -4, -12, 0, { smile = 0.6 } },
	},
})

-- девушка у стойки (почти статична: смотрит вниз, руки опущены вперёд, лёгкое покачивание)
local rack = { keys = {} }
for i, t in { 11.0, 11.6, 12.2, 12.8, 13.25 } do
	local sway = if i % 2 == 0 then 1.5 else -1
	table.insert(rack.keys, {
		t = t,
		root = { bend = 6 + sway * 0.5 },
		waist = { bend = 10, tilt = sway },
		neck = { nod = 28, turn = -4 },
		rArm = { fwd = 22, out = 6, elbow = 12 },
		lArm = { fwd = 22, out = 6, elbow = 12 },
		rLeg = { ik = { 0.405, 0.25, 0 } },
		lLeg = { ik = { -0.405, 0.25, 0.1 } },
		face = { blink = 0.3 },
	})
end

return {
	Horse = { keys = horse },
	Ginger = ginger,
	Curly = curly,
	Rack = rack,
}
