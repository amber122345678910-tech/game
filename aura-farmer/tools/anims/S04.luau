--!nocheck
-- Ключи анимации плана S04 (см. tools/lib/Pose.luau — формат ключей).
-- Конь: профиль -> хлёсткий разворот к камере (3.877–3.967), левый кулак с большим пальцем «через плечо»,
-- смех с пиком на доле 4.066, кивок вниз к полудоле 4.310, оскал-ухмылка к доле 4.554, «живая» фиксация.
-- Финальный торс смотрит в −Z; камера стоит спереди-справа от коня (≈40° от фронта торса).

local PALM = { 0.85, -0.15, 0.5 } -- ладонь к камере
local UP = { -0.1, 1, 0.23 } -- кисть чуть наклонена от головы: большой палец смотрит горизонтально
local THUMB = { curl = 1, thumb = 0, thumbOut = 1.55, spread = 0 }
local POLE = { -1, -0.8, 0.2 }

-- кулак (IK запястья в пространстве груди)
local function fist(x, y, f)
	return { ik = { x, y, f }, space = "chest", pole = POLE, wrist = { palm = PALM, fingers = UP } }
end

local NOD = 35
local LEAN = -12

-- t, root.turn, waist.turn, waist.bend, neck.turn, neck.nod, neck.tilt, ease, root.x, root.y, root.f
local body = {
	{ 3.8667, 25, 42, 0, -15, 20, 0, "linear", 0.22, -0.06, -0.22 },
	{ 3.9, 17, 30, 0, -30, 14, -3, "linear", 0.15, -0.05, -0.15 },
	{ 3.9333, 10, 17, -2, -38, 9, -10, "linear", 0.06, -0.03, -0.06 },
	{ 3.9667, 3, 4, -5, -36, 6, -15, nil, 0, 0, 0 },
	{ 4.0, 1, 1, -6, -34, 4, -12, nil, 0, 0.02, 0 },
	{ 4.0333, 0, 0, -7, -33, 3, -8, nil, 0, 0.035, 0 },
	{ 4.0667, 0, 0, -8, -33, 3, -6, nil, 0, 0.04, 0 },
	{ 4.1667, 0, 0, -7, -31, 7, -4, "Sine_InOut", 0, 0.02, 0 },
	{ 4.2333, 0, 0, -6, -30, 11, -3, nil, 0, -0.03, 0 },
	{ 4.3, 0, 0, -4, -29, 15, -3, nil, 0, -0.07, 0 },
	{ 4.4333, 0, 0, -4, -29, 15, -3, "Sine_Out", 0, -0.07, 0 },
	{ 4.5333, 0, 0, -4, -30, 12, -3, nil, 0, -0.05, 0 },
	{ 4.6333, 0, 0, -4, -31, 10, -3, nil, 0, -0.05, 0 },
	{ 4.9667, 0, 0, -4.5, -31, 9, -3, nil, 0, -0.045, 0 },
}

-- t, jaw, grin, brows, LeftEar.rz, RightEar.rz, Mane.rx
local faceKeys = {
	{ 3.8667, 0, 0.55, 0, 0, 0, 0 },
	{ 3.9, 0.18, 0.8, 0.2, 25, -8, 8 },
	{ 3.9333, 0.42, 1.0, 0.35, 50, -15, 14 },
	{ 3.9667, 0.55, 1.15, 0.4, 55, -18, 10 },
	{ 4.0, 0.6, 1.2, 0.4, 42, -14, 2 },
	{ 4.0333, 0.78, 1.3, 0.45, 30, -10, -6 },
	{ 4.0667, 0.83, 1.35, 0.45, 18, -6, -3 },
	{ 4.1667, 0.6, 1.35, 0.3, 10, -4, 0 },
	{ 4.2333, 0.42, 1.4, 0.2, 8, -4, 0 },
	{ 4.3, 0.28, 1.45, 0.1, 8, -4, 0 },
	{ 4.4333, 0.12, 1.5, 0, 8, -4, 0 },
	{ 4.5333, 0.04, 1.6, -0.1, 8, -4, 0 },
	{ 4.6333, 0.03, 1.6, -0.15, 8, -4, 0 },
	{ 4.9667, 0.03, 1.6, -0.15, 8, -4, 0 },
}

-- t, lArm, lHand
local armKeys = {
	{ 3.8667, { ik = { -1.45, 2.35, 0.15 }, space = "chest", pole = { -0.6, -0.2, -1 }, wrist = { palm = { 1, 0, 0 }, fingers = { 0, -1, 0 } } }, "relaxed" },
	{ 3.9, { ik = { -1.55, 4.45, 2.2 }, space = "chest", pole = { -0.3, -1, 0.2 }, wrist = { palm = { 0, -1, 0 }, fingers = { 0, 0, 1 } } }, "open" },
	{ 3.9333, { ik = { -2.35, 4.85, 1.05 }, space = "chest", pole = { -1, -0.7, 0.3 }, wrist = { palm = { 0.6, -0.6, 0.5 }, fingers = { -0.2, 0.6, 0.8 } } }, { curl = 0.7, thumb = 0, thumbOut = 1.2, spread = 0 } },
	{ 3.9667, fist(-2.1, 5.35, 0.45), THUMB },
	{ 4.0, fist(-2.1, 5.4, 0.45) },
	{ 4.0333, fist(-2.12, 5.48, 0.45) },
	{ 4.0667, fist(-2.12, 5.5, 0.45) },
	{ 4.1667, fist(-2.12, 5.48, 0.45) },
	{ 4.3, fist(-2.2, 5.33, 0.4) },
	{ 4.4333, fist(-2.2, 5.33, 0.4) },
	{ 4.5333, fist(-2.2, 5.35, 0.4) },
	{ 4.6333, fist(-2.2, 5.35, 0.4) },
	{ 4.9667, fist(-2.2, 5.36, 0.4), THUMB },
}

local keys = {}
local byT = {}
local function key(t)
	local k = byT[t]
	if not k then
		k = { t = t }
		byT[t] = k
		table.insert(keys, k)
	end
	return k
end

for _, b in body do
	local k = key(b[1])
	k.ease = b[8]
	k.root = { turn = b[2], x = b[9], y = b[10], f = b[11] }
	k.waist = { turn = b[3], bend = b[4] + (if b[1] >= 3.95 then LEAN else 0) }
	k.neck = { turn = b[5], nod = b[6] + NOD, tilt = b[7] }
end
for _, f in faceKeys do
	local k = key(f[1])
	k.face = { jaw = f[2], grin = f[3], brows = f[4] }
	k.joints = { LeftEar = { rz = f[5] }, RightEar = { rz = f[6] }, Mane = { rx = f[7] } }
end
for _, a in armKeys do
	local k = key(a[1])
	k.lArm = a[2]
	k.lHand = a[3]
end

-- правая рука висит (вне кадра), ноги стоят на месте
for _, t in { 3.8667, 4.9667 } do
	local k = key(t)
	k.rArm = { out = 6, fwd = -4, elbow = 12 }
	k.rLeg = { ik = { 0.55, 0.3, 0 }, foot = { yaw = 0 } }
	k.lLeg = { ik = { -0.55, 0.3, 0 }, foot = { yaw = 0 } }
end

table.sort(keys, function(a, b)
	return a.t < b.t
end)

return {
	Horse = { keys = keys },
}
