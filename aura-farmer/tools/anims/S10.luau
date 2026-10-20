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
-- (кривая снята по кадрам клипа: подъём ~0.27 с с быстрым стартом, верх с перелётом; опускание ~0.24 с, sine in-out)
local function rep(b0, b1)
	return {
		{ b0 - 0.016, -0.07 }, -- упреждение: кисть и плечо чуть проседают
		{ b0 + 0.05, 0.2 },
		{ b0 + 0.12, 0.5 },
		{ b0 + 0.19, 0.76 },
		{ b0 + 0.25, 0.97 },
		{ b0 + 0.29, 1.035 }, -- перелёт ~3°
		{ b0 + 0.36, 1.0 },
		{ b1 - 0.005, 0.995 },
		{ b1 + 0.035, 0.94 },
		{ b1 + 0.13, 0.5 },
		{ b1 + 0.2, 0.12 },
		{ b1 + 0.255, -0.015 },
		{ b1 + 0.32, 0 },
	}
end
local CURL = { { 11.0, 0 }, { 11.1333, 0 }, { 11.26, 0.01 } }
for _, r in { rep(B23, B24), rep(B25, B26) } do
	for _, k in r do
		table.insert(CURL, k)
	end
end
table.insert(CURL, { 13.25, 0 })
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
local ROOT = { y = -0.72, f = 0, bend = 12, turn = 0, tilt = 0 }
-- верх корпуса: внизу — наклон к коленям, крен и поворот к правому плечу; вверху — выпрямляется
local W_DN = { bend = 27, turn = -22, tilt = 6 }
local W_UP = { bend = 10, turn = -6, tilt = 5 }
local function waistK(k)
	return lerpT(W_DN, W_UP, k)
end

local LEGS = {
	root = ROOT,
	rLeg = { ik = { 1.3, 0.3, 0.92 }, pole = { 0.7, 0.2, 1 } },
	lLeg = { ik = { -1.3, 0.3, 0.92 }, pole = { -0.7, 0.2, 1 } },
}
-- левая ладонь на левом колене
local LARM = {
	lArm = { ik = { -1.27, 1.92, 0.66 }, pole = { -1, 0.15, -0.3 }, wrist = { palm = { 0, -1, 0 }, fingers = { 0.2, -0.5, 1 } } },
	lHand = { curl = 0.4, thumb = 0.2, thumbOut = 0.5, spread = 0.1 },
}

-- правая рука: низ (гантель у правого колена), середина, верх (у морды)
local A_DN = { ik = { 2.95, 2.02, 1.75 }, pole = { 1, 0.1, -0.5 }, palm = { -0.45, 0, -0.9 }, fingers = { 0, -1, 0 } }
local A_MID = { ik = { 2.95, 2.75, 2.0 }, pole = { 1, -0.5, -0.4 }, palm = { 0.18, -0.79, 0.57 }, fingers = { 0.25, 0.6, 0.75 } }
local A_UP = { ik = { 2.55, 3.66, 2.3 }, pole = { 1, -0.8, -0.2 }, palm = { 0.8, 0, 0.6 }, fingers = { -0.1, 1, 0.7 } }
local function armOf(a, dy)
	return { ik = { a.ik[1], a.ik[2] + (dy or 0), a.ik[3] }, pole = a.pole, wrist = { palm = a.palm, fingers = a.fingers } }
end
-- ориентация кисти интерполируется поворотом (slerp), а не покомпонентно: иначе на полпути ладонь и пальцы
-- становятся почти параллельны и кисть «переворачивается»
local RB = require("@lune/roblox")
local function handCF(palm, fingers)
	local f = RB.Vector3.new(fingers[1], fingers[2], fingers[3]).Unit
	local p = RB.Vector3.new(palm[1], palm[2], palm[3])
	p = (p - f * p:Dot(f)).Unit
	return RB.CFrame.fromMatrix(RB.Vector3.zero, p, f, p:Cross(f))
end
local function lerpArm(a, b, k)
	local cf = handCF(a.palm, a.fingers):Lerp(handCF(b.palm, b.fingers), k)
	local px, fy = cf.XVector, cf.YVector
	return {
		ik = lerpV(a.ik, b.ik, k),
		pole = lerpV(a.pole, b.pole, k),
		palm = { px.X, px.Y, px.Z },
		fingers = { fy.X, fy.Y, fy.Z },
	}
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
	return { Dumbbell = { rz = -88 * math.clamp(k, 0, 1.03) } }
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

-- голова: углы в мире относительно направления «в камеру» (камера ниже головы — взгляд в камеру = голова опущена
-- на CAM_PITCH): вверх+, поворот к правому плечу+ (влево в кадре), крен к правому плечу+.
-- Шея = (таз·корпус)⁻¹ · голова — считается точно через CFrame (порядок поворотов как в Pose: Y, X, Z).
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local rad, deg = math.rad, math.deg
local function euler(turn, bend, tilt)
	return CFrame.Angles(0, rad(turn), 0) * CFrame.Angles(rad(-bend), 0, 0) * CFrame.Angles(0, 0, rad(-tilt))
end
local CAM_PITCH = 15
local HEAD = {
	{ 11.0, -13, 22, 17 },
	{ 11.1333, -13, 22, 17 },
	{ 11.3, -13, 22, 17 },
	{ B23 + 0.12, -8, 21, 18 },
	{ B23 + 0.25, -3, 23, 20 },
	{ 11.75, -5, 23, 20 }, -- лёгкий кивок в верхней стоп-позе
	{ B24, -3, 23, 20 },
	{ 12.0, 3, 25, 20 }, -- AIN'T: голова вверх
	{ 12.133, -2, 27, 20 },
	{ 12.25, 0, 28, 19 },
	{ 12.333, 6, 27, 17 }, -- GOT: запрокинута
	{ 12.43, 4, 26, 17 },
	{ 12.533, 8, 25, 17 }, -- NO
	{ 12.633, 3, 23, 19 },
	{ 12.767, 5, 23, 19 }, -- WOR-
	{ B26 + 0.02, 4, 24, 19 },
	{ 12.967, -1, 26, 20 }, -- -RIES
	{ 13.1, 1, 27, 20 },
	{ 13.25, 1, 27, 20 },
}
for _, h in HEAD do
	local w = waistK(curlAt(h[1]))
	local torso = euler(ROOT.turn, ROOT.bend, ROOT.tilt) * euler(w.turn, w.bend, w.tilt)
	local head = euler(-h[3], CAM_PITCH - h[2], h[4])
	local rx, ry, rz = (torso:Inverse() * head):ToEulerAnglesYXZ()
	table.insert(horse, { t = h[1], neck = { nod = -deg(rx), turn = deg(ry), tilt = -deg(rz) } })
end

-- лицо: челюсть (0 — зубы сомкнуты), оскал, брови, уши
-- (открытие рта снято по кадрам клипа, 30 к/с; jaw ≈ 1.15 × «раскрытие» из разбора)
local FACE = {
	-- t, jaw, grin, brows, ears
	{ 11.0, 0.04, 1, 0, 0 },
	{ 11.1333, 0.04, 1, 0, 0 }, -- «…stress»: сомкнутые зубы, самодовольный оскал
	{ 11.5, 0.06, 1, 0.1, 0 },
	{ 11.633, 0.12, 1, 0.2, -0.1 },
	{ 11.833, 0.08, 1, 0.2, -0.1 },
	{ 11.9, 0.17, 1, 0.25, 0 },
	{ 11.967, 0.5, 1, 0.45, 0.1 }, -- AIN'T: смеющийся раскрытый оскал
	{ 12.033, 0.62, 1, 0.55, 0.1 },
	{ 12.1, 0.4, 1, 0.45, 0.1 },
	{ 12.2, 0.22, 1, 0.35, 0.05 },
	{ 12.233, 0.24, 1, 0.35, 0.05 },
	{ 12.3, 0.86, 0.95, 0.75, 0.2 }, -- GOT: высокий раскрытый рот
	{ 12.367, 0.46, 1, 0.55, 0.1 },
	{ 12.4, 0.4, 1, 0.5, 0.1 },
	{ 12.467, 0.62, 1, 0.65, 0.15 },
	{ 12.533, 0.98, 0.9, 0.85, 0.25 }, -- NO: шире всего
	{ 12.6, 0.7, 0.9, 0.7, 0.15 },
	{ 12.65, 0.63, 0.85, 0.65, 0.1 },
	{ 12.733, 0.92, 0.55, 0.8, 0.2 }, -- WOR-: округлый рот, губы вперёд
	{ 12.8, 0.86, 0.5, 0.75, 0.2 },
	{ 12.867, 0.92, 0.55, 0.75, 0.2 },
	{ 12.933, 0.38, 1, 0.55, 0.05 }, -- -RIES: широкий оскал, зубы почти сомкнуты
	{ 13.033, 0.34, 1, 0.5, 0 },
	{ 13.1, 0.55, 1, 0.6, 0.1 },
	{ 13.25, 0.55, 1, 0.6, 0.1 },
}
for _, f in FACE do
	table.insert(horse, { t = f[1], face = { jaw = f[2], grin = f[3], brows = f[4], ears = f[5] } })
end

-- ===================== СТАТИСТЫ =====================
-- Махи ногой назад («glute kick-back») синхронно с гантелью: вверх на долях 23/25, вниз на 24/26
-- (движение ~0.24 с в первой половине доли, затем стоп-поза). Руки на поясе.
local function rigOf(char, opts)
	return require("../chars/" .. char)(opts or {})
end

-- o: { P = пропорции рига, side = "r"|"l" (рабочая нога), hinge = наклон корпуса в верхней позе,
--      legBack = угол ноги назад от вертикали (мир), shift = отвод таза назад, lean = наклон стоя,
--      head = { {t, nod, turn, tilt, face}, ... } }
local function kicker(o)
	local P = o.P
	local keys = {}
	local kick = o.side .. "Leg"
	local stand = (if o.side == "r" then "l" else "r") .. "Leg"
	local sx = if o.side == "r" then -1 else 1 -- x опорной ноги (знак)
	local hx = P.hipX
	-- кисти на поясе (пространство таза: едут с корпусом), локти в стороны
	local handY = P.waistY - 0.12
	local handX = hx + 0.5
	local arms = {
		rArm = { ik = { handX, handY, 0.05 }, space = "hips", pole = { 1, 0.1, -0.6 }, wrist = { palm = { -1, 0, 0.1 }, fingers = { 0.05, -0.5, 1 } } },
		lArm = { ik = { -handX, handY, 0.05 }, space = "hips", pole = { -1, 0.1, -0.6 }, wrist = { palm = { 1, 0, 0.1 }, fingers = { -0.05, -0.5, 1 } } },
		rHand = "relaxed",
		lHand = "relaxed",
	}
	local function pose(t, k, drift, ease)
		-- k = 0 стоит, 1 — нога назад; drift — покачивание ноги в стоп-позе (градусы).
		-- корпус «запаздывает» на подъёме и выпрямляется раньше ноги на опускании (k^2.5)
		local bend = o.hinge * math.max(k, 0) ^ 2.5
		local rb = bend * 0.75
		local key = merge(arms, {
			t = t,
			ease = ease,
			root = { y = -0.13 * k, f = -o.shift * k, bend = rb },
			waist = { bend = bend * 0.25 + (o.lean or 0) * (1 - k), turn = 0, tilt = 0 },
		})
		key[stand] = { ik = { sx * hx, P.ankleY, 0.03 }, pole = { 0, 0, 1 } }
		local back = o.legBack * k + (drift or 0)
		key[kick] = { fwd = -(back - rb), out = 4 * k, knee = 6 * k, ankle = { bend = -35 * k } }
		return key
	end
	-- фаза — та же кривая, что у гантели (полная синхронность); в верхней стоп-позе нога слегка «пружинит»
	for _, c in CURL do
		local k = math.clamp(c[2], 0, 1.05)
		local drift = 0
		if k > 0.99 and c[1] > B23 + 0.3 and c[1] < B23 + 0.45 then
			drift = 4
		elseif k > 0.99 and c[1] > B25 + 0.3 and c[1] < B25 + 0.45 then
			drift = 4
		end
		table.insert(keys, pose(c[1], k, drift))
	end
	for _, h in o.head do
		table.insert(keys, { t = h[1], neck = { nod = h[2], turn = h[3], tilt = h[4] or 0 }, face = h[5] })
	end
	-- моргание (живые люди в кадре): закрыть за 2 кадра, открыть за 3
	for _, b in o.blinks or {} do
		local f = table.clone(b[2])
		table.insert(keys, { t = b[1] - 0.067, face = table.clone(f) })
		f.blink = 1
		table.insert(keys, { t = b[1], face = f })
		table.insert(keys, { t = b[1] + 0.1, face = table.clone(b[2]) })
	end
	table.sort(keys, function(a, b)
		return a.t < b.t
	end)
	return { keys = keys }
end

-- рыжая: глубокий наклон (~65°), нога до горизонтали; стоя смотрит вверх и вправо в кадре, в наклоне лицо вниз
local ginger = kicker({
	P = rigOf("GymWoman").P,
	side = "r",
	hinge = 64,
	legBack = 88,
	shift = 0.3,
	lean = 5,
	blinks = { { 12.2, { smile = 0.4 } } },
	head = {
		{ 11.0, -20, -6, 0, { smile = 0.35 } },
		{ 11.1333, -20, -6, 0, { smile = 0.35 } },
		{ B23 + 0.05, -14, -4, 0, { smile = 0.3 } },
		{ B23 + 0.25, 22, 0, 0, { smile = 0.2, blink = 0.3 } },
		{ B24, 24, 0, 0, { smile = 0.2, blink = 0.3 } },
		{ B24 + 0.26, -15, -6, 0, { smile = 0.4 } },
		{ B25 + 0.02, -15, -6, 0, { smile = 0.4 } },
		{ B25 + 0.25, 22, 0, 0, { smile = 0.2, blink = 0.3 } },
		{ B26, 24, 0, 0, { smile = 0.2, blink = 0.3 } },
		{ B26 + 0.26, -15, -6, 0, { smile = 0.35 } },
		{ 13.25, -15, -6, 0, { smile = 0.35 } },
	},
})

-- кудрявая: наклон ~35°, ближняя к камере левая нога почти горизонтально вправо в кадре; стоя смотрит на коня,
-- в верхней позе поворачивает голову в камеру с ухмылкой (камера у неё слева: поворот влево+)
local curly = kicker({
	P = rigOf("GymGuy").P,
	side = "l",
	hinge = 36,
	legBack = 84,
	shift = 0.2,
	lean = 9,
	blinks = { { 11.25, { smile = 0.4 } }, { 12.24, { smile = 0.55 } } },
	head = {
		{ 11.0, -4, 12, 0, { smile = 0.4 } },
		{ 11.1333, -4, 12, 0, { smile = 0.4 } },
		{ B23 + 0.05, -4, 16, 0, { smile = 0.45 } },
		{ B23 + 0.25, -22, 42, -8, { smile = 0.75, squint = 0.25, lookX = -0.35 } },
		{ B24, -22, 44, -8, { smile = 0.8, squint = 0.25, lookX = -0.35 } },
		{ B24 + 0.26, -4, 14, 0, { smile = 0.55 } },
		{ B25 + 0.02, -4, 14, 0, { smile = 0.55 } },
		{ B25 + 0.25, -22, 42, -8, { smile = 1, jaw = 0.12, squint = 0.3, lookX = -0.35 } },
		{ B26, -22, 44, -8, { smile = 1, jaw = 0.12, squint = 0.3, lookX = -0.35 } },
		{ B26 + 0.26, -4, 12, 0, { smile = 0.55 } },
		{ 13.25, -4, 12, 0, { smile = 0.55 } },
	},
})

-- тёмноволосая за стойкой (почти статична: смотрит вниз на гантели, руки опущены вперёд, лёгкое покачивание)
local rackP = rigOf("Human", { female = true, height = 0.97, build = 0.9 }).P
local rack = { keys = {} }
for i, t in { 11.0, 11.6, 12.2, 12.8, 13.25 } do
	local sway = if i % 2 == 0 then 1.5 else -1
	table.insert(rack.keys, {
		t = t,
		root = { y = -0.04, bend = 8 + sway * 0.5 },
		waist = { bend = 12, tilt = sway },
		neck = { nod = 26, turn = -4 },
		-- ладони лежат на гантелях верхнего яруса стойки (за ней)
		rArm = { ik = { 0.42, 3.1 + sway * 0.01, 1.2 }, pole = { 0.6, -0.3, -1 }, wrist = { palm = { 0, -1, 0.1 }, fingers = { 0, -0.3, 1 } } },
		lArm = { ik = { -0.42, 3.1 - sway * 0.01, 1.2 }, pole = { -0.6, -0.3, -1 }, wrist = { palm = { 0, -1, 0.1 }, fingers = { 0, -0.3, 1 } } },
		rLeg = { ik = { rackP.hipX, rackP.ankleY, 0 } },
		lLeg = { ik = { -rackP.hipX, rackP.ankleY, 0.1 } },
		rHand = "relaxed",
		lHand = "relaxed",
		face = { blink = 0.35 },
	})
end

return {
	Horse = { keys = horse },
	Ginger = ginger,
	Curly = curly,
	Rack = rack,
}
