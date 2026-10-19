--!nocheck
-- Ключи анимации плана S07 (см. tools/lib/Pose.luau — формат ключей).
-- «HE'S SUCH A CHARMER»: селфи снизу широким углом. A (слева в кадре) хохочет, запрокинув голову,
-- на доле 6.992 роняет голову вперёд и к концу подаётся к объективу; B (справа) поёт, глядя вверх-вправо:
-- левая кисть «коготь» -> «джаз-ладонь» на полудоле 6.748, правая с красными очками у горла.
-- Очки в правых руках обеих — «маятник»: подвешены к точке хвата и раскачиваются от движения кисти
-- (сустав Glasses считается симуляцией по запечённой позе, ключи каждые 2 кадра).
--
-- Углы головы задаются «в сцене» (как в разборе плана): hp — вверх+, hy — влево+ (от оси сцены), hr — к правому плечу+;
-- функция key() переводит их в каналы root/waist/neck с учётом наклона/поворота корпуса.

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Loader = require("../lib/loader")
local Pose = require("../lib/Pose")

local SHOT = Loader.load("src/shared/Shots/S07")

local V = Vector3.new
local deg = math.deg

local function F(v)
	return { v.X, v.Y, -v.Z }
end
local function C(x, y, f)
	return V(x, y, -f)
end

-- поворот места актёра (градусы, влево+) относительно сцены: A поставлена с поворотом +25°
local function placeYaw(name)
	local look = SHOT.actors[name].place.LookVector
	return deg(math.atan2(-look.X, -look.Z))
end
local STAGE_YAW = placeYaw("WomanA") - 25

-- s = { t, ease, yaw (корпус в сцене), lean (вперёд+), tilt (крен корпуса вправо+), x/y/f (таз),
--       hp, hy, hr (голова в сцене) } + любые группы позы (rArm, face, ...)
local SKIP = { t = true, ease = true, yaw = true, lean = true, tilt = true, x = true, y = true, f = true, hp = true, hy = true, hr = true }
local function key(name, s)
	local base = placeYaw(name) - STAGE_YAW
	local lean = s.lean or 0
	local tilt = s.tilt or 0
	local yaw = s.yaw or base
	local bodyTurn = yaw - base
	local k = {
		t = s.t,
		ease = s.ease,
		root = { x = s.x or 0, y = s.y or 0, f = s.f or 0, turn = bodyTurn * 0.4, bend = lean * 0.45, tilt = tilt * 0.4 },
		waist = { turn = bodyTurn * 0.6, bend = lean * 0.55, tilt = tilt * 0.6 },
		neck = { nod = -(s.hp or 0) - lean, turn = (s.hy or 0) - yaw, tilt = (s.hr or 0) - tilt },
	}
	for g, v in s do
		if not SKIP[g] then
			k[g] = v
		end
	end
	return k
end

local function rigOf(name)
	local a = SHOT.actors[name]
	return require("../chars/" .. a.char)(a.opts or {})
end
local rigA, rigB = rigOf("WomanA"), rigOf("WomanB")

-- ===================================================================================
-- B (справа в кадре): кудрявая, поёт «he's such a CHAR-MER», смотрит вверх-вправо.
-- Кисти — в пространстве груди (едут с корпусом).
-- ===================================================================================
local CLAW = { curl = 0.5, index = 0.45, thumb = 0.25, thumbOut = 0.75, spread = 0.65 }
local CLAW2 = { curl = 0.72, index = 0.64, thumb = 0.35, thumbOut = 0.7, spread = 0.55 }
local JAZZ = { curl = 0, thumb = 0, thumbOut = 1, spread = 1 }
local JAZZ_SOFT = { curl = 0.08, index = 0.04, thumb = 0.05, thumbOut = 0.95, spread = 0.9 }
local PINCH_B = { curl = 0.92, index = 0.5, middle = 0.7, thumb = 0.6, thumbOut = 0.35 }
local BLADE = { curl = 1, index = 0.06, middle = 0.08, ring = 0.85, pinky = 1, thumb = 0.75, thumbOut = 0.2, spread = 0.12 }
local BLADE_FLUTTER = { curl = 1, index = 0.2, middle = 0.22, ring = 0.85, pinky = 1, thumb = 0.75, thumbOut = 0.2, spread = 0.12 }

-- левая: { x, y, f, palm, fingers }
local function bL(p)
	return { ik = { p[1], p[2], p[3] }, space = "chest", pole = { -0.35, -1, 0.15 }, wrist = { palm = p[4], fingers = p[5] } }
end
local function bR(p)
	return { ik = { p[1], p[2], p[3] }, space = "chest", pole = { 0.5, -1, 0.1 }, wrist = { palm = p[4], fingers = p[5] } }
end
local PL = { 0.3, -0.12, 1 } -- ладонь в объектив
local RH = { -1, 0, 0.3 } -- ладонь правой к шее
local UP = { 0.05, 1, 0.08 }

-- B: { t, yaw, lean, tilt, x, y, hp, hy, hr, L = {..}, lh, R = {..}, rh, face, ease }
-- Кисти B (в rest-координатах груди): левая «джаз-ладонь» перед левым плечом, правая «лезвие» перед правой
-- ключицей — так в кадре ладонь справа-снизу от лица, а пальцы правой у подбородка слева от лица (как в клипе).
local function Lp(x, y, f, rock)
	-- rock: покачивание запястья ±5° (поворот ладони вокруг вертикали)
	local r = rock or 0
	return { x, y, f, { 0.3 + r, -0.12, 1 }, { -0.22 - r * 0.5, 1, 0.05 } }
end
local function Rp(x, y, f)
	return { x, y, f, RH, UP }
end
local CLAWP = { 0.3, -0.45, 1 }

local bBeats = {
	{ t = 6.533, yaw = 8, lean = -5, tilt = 0, x = 0, hp = 8, hy = 26, L = { -0.64, 3.23, 0.58, CLAWP, { -0.3, 1, 0.3 } }, lh = CLAW, R = Rp(0.54, 3.23, 0.84), rh = PINCH_B, face = { jaw = 0.5, smile = 0.3, brows = 0.6 } },
	{ t = 6.6, yaw = 8, lean = -5, tilt = 0, x = 0, hp = 8, hy = 26, L = { -0.65, 3.25, 0.58, CLAWP, { -0.3, 1, 0.3 } }, lh = CLAW, R = Rp(0.54, 3.25, 0.84), rh = PINCH_B, face = { jaw = 0.55, smile = 0.35, brows = 0.6 } },
	-- коготь сжимается, кисть подтягивается вверх
	{ t = 6.667, yaw = 8, lean = -5, tilt = -1, x = -0.01, hp = 6, hy = 28, L = { -0.66, 3.30, 0.60, { 0.25, -0.55, 1 }, { -0.25, 1, 0.45 } }, lh = CLAW2, R = Rp(0.54, 3.27, 0.84), rh = PINCH_B, face = { jaw = 0.4, smile = 0.4, brows = 0.6 } },
	{ t = 6.7, ease = "inout", yaw = 8, lean = -5, tilt = -1.5, x = -0.02, hp = 6, hy = 29, L = { -0.67, 3.33, 0.61, { 0.25, -0.55, 1 }, { -0.25, 1, 0.45 } }, lh = CLAW2, R = Rp(0.53, 3.30, 0.85), rh = { curl = 0.95, index = 0.3, middle = 0.4, ring = 0.85, thumb = 0.7, thumbOut = 0.25 }, face = { jaw = 0.45, smile = 0.4, brows = 0.65 } },
	-- ВЗМАХ (6.733–6.767): коготь -> джаз-ладонь с перелётом вверх, корпус качнулся влево (вправо в кадре)
	{ t = 6.767, ease = "inout", yaw = 6, lean = -5, tilt = -4.5, x = -0.08, hp = 4, hy = 34, hr = -2, L = Lp(-0.64, 3.62, 0.60), lh = JAZZ, R = Rp(0.52, 3.38, 0.88), rh = BLADE, face = { jaw = 0.48, smile = 0.5, brows = 0.72 } },
	{ t = 6.833, yaw = 6, lean = -5, tilt = -5, x = -0.1, hp = 3, hy = 36, hr = -2, L = Lp(-0.64, 3.55, 0.60), lh = JAZZ, R = Rp(0.52, 3.36, 0.88), rh = BLADE, face = { jaw = 0.45, smile = 0.45, brows = 0.7 } },
	{ t = 6.9, yaw = 6, lean = -5, tilt = -4, x = -0.09, hp = 1, hy = 34, hr = -2, L = Lp(-0.63, 3.54, 0.60), lh = JAZZ, R = Rp(0.52, 3.36, 0.88), rh = BLADE, face = { jaw = 0.33, oh = 0.5, smile = 0.15, brows = 0.65 } },
	-- доля 6.992: кивок и «приседание»
	{ t = 7.0, yaw = 6, lean = -4, tilt = -3, x = -0.08, y = -0.035, hp = -2, hy = 33, hr = -1, L = Lp(-0.62, 3.51, 0.60), lh = JAZZ, R = Rp(0.52, 3.34, 0.88), rh = BLADE, face = { jaw = 0.36, oh = 0.75, smile = 0.05, brows = 0.6 } },
	{ t = 7.1, yaw = 6, lean = -4, tilt = -2, x = -0.07, y = -0.01, hp = -1, hy = 32, hr = -1, L = Lp(-0.61, 3.50, 0.60, 0.08), lh = JAZZ_SOFT, R = Rp(0.52, 3.34, 0.88), rh = BLADE, face = { jaw = 0.28, oh = 0.3, smile = 0.2, brows = 0.6 } },
	{ t = 7.2, yaw = 6, lean = -4, tilt = -1, x = -0.06, hp = -1, hy = 32, hr = 0, L = Lp(-0.60, 3.48, 0.60, -0.06), lh = JAZZ, R = Rp(0.52, 3.34, 0.88), rh = BLADE_FLUTTER, face = { jaw = 0.22, smile = 0.35, brows = 0.6 } },
	-- «CHAR»: подбородок вверх, рот широко «А/О»
	{ t = 7.3, yaw = 6, lean = -2, tilt = 0, x = -0.05, hp = 5, hy = 29, hr = 0, L = Lp(-0.59, 3.47, 0.60, 0.08), lh = JAZZ_SOFT, R = Rp(0.52, 3.34, 0.88), rh = BLADE, face = { jaw = 0.9, oh = 0.55, brows = 0.9, squint = 0.15 } },
	{ t = 7.4, yaw = 6, lean = -3, tilt = 0, x = -0.04, hp = 7, hy = 29, hr = 0, L = Lp(-0.58, 3.45, 0.60, -0.06), lh = JAZZ, R = Rp(0.52, 3.34, 0.88), rh = BLADE, face = { jaw = 0.7, oh = 0.6, brows = 0.85, squint = 0.1 } },
	-- «m» (доля 7.48): губы сомкнуты, голова чуть вниз
	{ t = 7.483, yaw = 6, lean = -2, tilt = 0, x = -0.03, y = -0.03, hp = 1, hy = 32, hr = 0, L = Lp(-0.57, 3.43, 0.60, 0.06), lh = JAZZ_SOFT, R = Rp(0.52, 3.33, 0.88), rh = BLADE, face = { jaw = 0, smile = 0.2, brows = 0.7 } },
	-- «MER»
	{ t = 7.583, yaw = 6, lean = -2, tilt = 0, x = -0.02, hp = 6, hy = 29, hr = 0, L = Lp(-0.56, 3.42, 0.60, -0.06), lh = JAZZ, R = Rp(0.52, 3.33, 0.88), rh = BLADE, face = { jaw = 0.9, oh = 0.5, brows = 0.9, squint = 0.1 } },
	{ t = 7.7, yaw = 6, lean = -2, tilt = 0, x = -0.01, hp = 4, hy = 29, hr = 0, L = Lp(-0.55, 3.41, 0.60, 0.05), lh = JAZZ_SOFT, R = Rp(0.52, 3.33, 0.88), rh = BLADE, face = { jaw = 0.5, oh = 0.3, smile = 0.3, brows = 0.72 } },
	{ t = 7.9, yaw = 6, lean = -2, tilt = 0, x = 0.0, hp = 2, hy = 29, hr = 0, L = Lp(-0.54, 3.40, 0.60, -0.03), lh = JAZZ, R = Rp(0.52, 3.33, 0.88), rh = BLADE, face = { jaw = 0.38, smile = 0.45, brows = 0.6 } },
}

-- B чуть ниже A: стоит, слегка согнув колени (стопы на месте — IK ног); к «CHARMER» выпрямляется
local function bDrop(t)
	if t <= 6.8 then
		return -0.25
	elseif t <= 7.0 then
		return -0.25 + 0.05 * (t - 6.8) / 0.2
	end
	return -0.2 + 0.2 * math.clamp((t - 7.0) / 0.5, 0, 1)
end
local bKeys = {}
for _, b in bBeats do
	local face = table.clone(b.face)
	face.lookX = face.lookX or -0.45 -- взгляд вверх-вправо (влево от неё)
	face.lookY = face.lookY or 0.75
	table.insert(bKeys, key("WomanB", {
		t = b.t, ease = b.ease, yaw = b.yaw, lean = b.lean, tilt = b.tilt, x = b.x, f = b.f, y = (b.y or 0) + bDrop(b.t), hp = b.hp, hy = b.hy, hr = b.hr,
		lArm = bL(b.L), lHand = b.lh, rArm = bR(b.R), rHand = b.rh, face = face,
	}))
end
-- моргание B (6.95–7.05, перед «such»)
table.insert(bKeys, { t = 7.05, face = { jaw = 0.32, oh = 0.6, smile = 0.1, brows = 0.6, blink = 0.9, lookX = -0.45, lookY = 0.45 } })

-- ===================================================================================
-- A (слева в кадре): хохочет, запрокинув голову; на доле 6.992 роняет голову; к концу подаётся к объективу.
-- ===================================================================================
local PINCH_A = { curl = 0.8, index = 0.55, middle = 0.62, thumb = 0.6, thumbOut = 0.45, spread = 0.05 }
local CUP = { curl = 0.35, thumb = 0.25, thumbOut = 0.5, spread = 0.15 }

local function aR(x, y, f, palm, fingers, pole)
	return { ik = { x, y, f }, pole = pole or { 0.35, -1, 0.25 }, wrist = { palm = palm, fingers = fingers } }
end

local function laugh(jaw, extra)
	local f = { smile = 1, squint = 0.6, blink = 0.55, brows = 0.25, lookX = -0.3, lookY = 0.6, jaw = jaw }
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

-- A: { t, yaw, lean, f, x, hp, hy, hr, R = { x, y, f, palm, fingers, pole? }, face }
local DOWN_P, DOWN_F, DOWN_POLE = { 0.5, 0, -1 }, { 0, 0, 1 }, { 1, -0.4, 0.5 }
local aBeats = {
	{ t = 6.533, yaw = 32, lean = 0, f = 0.05, hp = 8, hy = 40, hr = 7, R = { 0.66, 2.83, 0.66, { 0.2, -0.1, -1 }, { -0.25, 1, 0.25 } }, face = laugh(0.40) },
	{ t = 6.6, yaw = 32, lean = 0, f = 0.05, hp = 8, hy = 40, hr = 7, R = { 0.66, 2.85, 0.68, { 0.2, -0.1, -1 }, { -0.25, 1, 0.25 } }, face = laugh(0.39) },
	{ t = 6.7, yaw = 32, lean = 0, f = 0.05, hp = 8, hy = 40, hr = 5, R = { 0.68, 2.9, 0.74, { 0.2, -0.25, -1 }, { -0.3, 1, 0.35 } }, face = laugh(0.26) },
	{ t = 6.8, yaw = 32, lean = 0, f = 0.05, x = -0.03, hp = 6, hy = 37, hr = 5, R = { 0.72, 2.88, 0.8, { 0.2, -0.25, -1 }, { -0.3, 1, 0.35 } }, face = laugh(0.39) },
	{ t = 6.9, yaw = 31, lean = 0, f = 0.05, x = -0.05, hp = 2, hy = 35, hr = 5, R = { 0.82, 2.6, 0.76, { 0.3, -0.3, -1 }, { -0.2, 1, 0.5 } }, face = laugh(0.33, { blink = 0.38 }) },
	-- доля 6.992: голова падает вперёд, корпус выпрямляется, рука с очками ушла вниз из кадра
	{ t = 7.0, ease = "out", yaw = 29, lean = 2, f = 0.1, x = -0.04, hp = -8, hy = 35, hr = 6, R = { 1.02, 2.35, 0.5, DOWN_P, { -0.05, 0.3, 1 }, DOWN_POLE }, face = laugh(0.23, { blink = 0.12, squint = 0.5, lookX = -0.45, lookY = 0.55 }) },
	{ t = 7.1, yaw = 28, lean = 3, f = 0.08, x = 0.0, hp = -9, hy = 33, hr = 0, R = { 1.05, 2.15, 0.42, DOWN_P, DOWN_F, DOWN_POLE }, face = laugh(0.23, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.45, lookY = 0.55 }) },
	{ t = 7.2, yaw = 27, lean = 3, f = 0.04, x = 0.05, hp = -10, hy = 30, hr = -5, R = { 1.05, 2.12, 0.42, DOWN_P, DOWN_F, DOWN_POLE }, face = laugh(0.23, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.45, lookY = 0.5 }) },
	-- «CHAR»: широкий смех, корпус к объективу
	{ t = 7.3, yaw = 26, lean = 3, f = 0.0, x = 0.12, tilt = 2, hp = -7, hy = 27, hr = -8, R = { 1.05, 2.12, 0.42, DOWN_P, DOWN_F, DOWN_POLE }, face = laugh(0.47, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.4, lookY = 0.5 }) },
	{ t = 7.4, yaw = 25, lean = 3, f = -0.03, x = 0.16, tilt = 3, hp = -8, hy = 30, hr = -8, R = { 1.05, 2.12, 0.42, DOWN_P, DOWN_F, DOWN_POLE }, face = laugh(0.20, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.4, lookY = 0.45 }) },
	{ t = 7.5, yaw = 24, lean = 3, f = -0.06, x = 0.22, tilt = 4, hp = -10, hy = 30, hr = -8, R = { 1.05, 2.2, 0.5, DOWN_P, { 0, 0.2, 1 }, DOWN_POLE }, face = laugh(0.23, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.3, lookY = 0.4 }) },
	-- «MER»: снова широкий смех, наклон к объективу и вправо (влево в кадре); правая рука поднимается
	{ t = 7.6, yaw = 23, lean = 3, f = -0.09, x = 0.28, tilt = 5, hp = -11, hy = 25, hr = -10, R = { 1.0, 2.6, 0.75, { 0.3, -0.3, -1 }, { -0.2, 0.8, 0.6 } }, face = laugh(0.47, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.2, lookY = 0.3 }) },
	{ t = 7.7, yaw = 22, lean = 2, f = -0.12, x = 0.32, tilt = 6, hp = -12, hy = 25, hr = -10, R = { 0.98, 3.12, 0.98, { 0.2, -0.3, -1 }, { -0.3, 1, 0.4 } }, face = laugh(0.36, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.1, lookY = 0.2 }) },
	{ t = 7.9, yaw = 22, lean = 2, f = -0.14, x = 0.35, tilt = 6, hp = -13, hy = 23, hr = -10, R = { 0.92, 3.42, 1.05, { 0.2, -0.3, -1 }, { -0.3, 1, 0.3 } }, face = laugh(0.33, { blink = 0.12, squint = 0.5, brows = 0.2, lookX = -0.05, lookY = 0.15 }) },
}
local aKeys = {}
for _, a in aBeats do
	local R = a.R
	table.insert(aKeys, key("WomanA", {
		t = a.t, ease = a.ease, yaw = a.yaw, lean = a.lean, tilt = a.tilt, f = a.f, x = a.x, hp = a.hp, hy = a.hy, hr = a.hr,
		rArm = aR(R[1], R[2], R[3], R[4], R[5], R[6]), rHand = PINCH_A, face = a.face,
	}))
end

-- ===== «смеховые» покачивания головы: синусоида поверх ключей шеи (на ключах и в пиках между ними) =====
local function addBob(keys, t0, t1, freq, amp, field)
	local neckKeys = {}
	for _, k in keys do
		if k.neck then
			table.insert(neckKeys, k)
		end
	end
	table.sort(neckKeys, function(a, b)
		return a.t < b.t
	end)
	local function offset(t)
		local w = math.clamp((t - t0) / 0.08, 0, 1) * math.clamp((t1 - t) / 0.08, 0, 1)
		return amp * w * math.sin(2 * math.pi * freq * (t - t0))
	end
	local function lerpNeck(t)
		local a, b = neckKeys[1], neckKeys[#neckKeys]
		for i = 1, #neckKeys - 1 do
			if neckKeys[i].t <= t and neckKeys[i + 1].t >= t then
				a, b = neckKeys[i], neckKeys[i + 1]
				break
			end
		end
		local u = if b.t > a.t then (t - a.t) / (b.t - a.t) else 0
		local n = {}
		for _, f in { "nod", "turn", "tilt" } do
			n[f] = (a.neck[f] or 0) + ((b.neck[f] or 0) - (a.neck[f] or 0)) * u
		end
		return n
	end
	local extra = {}
	local t = t0 + 0.25 / freq
	while t < t1 do
		local near = false
		for _, k in neckKeys do
			if math.abs(k.t - t) < 0.03 then
				near = true
			end
		end
		if not near then
			table.insert(extra, { t = t, neck = lerpNeck(t) })
		end
		t += 0.5 / freq
	end
	for _, k in neckKeys do
		if k.t > t0 and k.t < t1 then
			k.neck = table.clone(k.neck)
			k.neck[field] = (k.neck[field] or 0) + offset(k.t)
		end
	end
	for _, k in extra do
		k.neck[field] += offset(k.t)
		table.insert(keys, k)
	end
end
-- A смеётся: кивки ±2.5° ~4 Гц после того, как уронила голову; B — лёгкие покачивания головы в ритм пения
addBob(aKeys, 7.05, 7.86, 4, 2.5, "nod")
addBob(bKeys, 7.05, 7.86, 2.05, 1.5, "tilt")

-- ===== стопы на месте (ноги вне кадра, но таз качается) =====
local function addLegs(keys, rig)
	local P = rig.P
	table.insert(keys, { t = 6.5, rLeg = { ik = { P.hipX, P.ankleY, 0 } }, lLeg = { ik = { -P.hipX, P.ankleY, 0 } } })
end
addLegs(aKeys, rigA)
addLegs(bKeys, rigB)

-- ===== A: левая кисть на правом плече / плече-руке B (едет вместе с B) =====
local solverA, solverB = Pose.solver(rigA), Pose.solver(rigB)
local tracksB = Pose.tracks(table.clone(bKeys), solverB)
local A2B = SHOT.actors.WomanA.place:Inverse() * SHOT.actors.WomanB.place
local function onB(t, bone, p)
	local cfs = solverB:fk(Pose.evaluate(tracksB, solverB, t))
	return A2B * ((cfs[bone] * rigB.rest[bone]:Inverse()) * p)
end
for _, t in { 6.533, 6.6, 6.8, 7.0, 7.1, 7.3, 7.5, 7.7, 7.9 } do
	-- до 6.95: кисть сверху-спереди на плече; с 7.1 — спереди на плече-руке
	local u = math.clamp((t - 6.95) / 0.2, 0, 1)
	local pB = C(1.1, 3.92 - 0.4 * u, 0.12 + 0.16 * u)
	table.insert(aKeys, {
		t = t,
		lArm = { ik = F(onB(t, "RightUpperArm", pB)), pole = { -0.6, -0.4, -1 }, wrist = { palm = { 0.6, -0.2, -0.4 }, fingers = { 0.5, -0.4, 0.8 } } },
		lHand = CUP,
	})
end

-- ===== Очки-маятник =====
-- Точка подвеса задаётся в позе покоя относительно запястья (кость RightHand), очки висят на ней:
-- ось «центр очков -> хват» (локальная +X очков) смотрит вдоль нити маятника, дужки (локальная +Z) — в сторону pref.
local function glassesKeys(rig, keys, hang, pref, t0, t1)
	local solver = Pose.solver(rig)
	local tracks = Pose.tracks(table.clone(keys), solver)
	local pivotG = rig.pivots.Glasses
	local wrist = rig.pivots.RightHand
	local q = (wrist + hang) - pivotG -- точка подвеса в осях очков (поза покоя)
	local L = q.Magnitude
	local function frame(t)
		local cfs = solver:fk(Pose.evaluate(tracks, solver, t))
		local M = cfs.RightHand * rig.rest.RightHand:Inverse()
		return M, M * (wrist + hang)
	end
	local g = V(0, -40, 0)
	local dt = 1 / 120
	local _, p0 = frame(t0 - 0.4)
	local x, xp = p0 - q.Unit * L, p0 - q.Unit * L
	-- в покое центр висит под точкой подвеса
	x = p0 + V(0, -L, 0)
	xp = x
	local out = {}
	local nextSample = t0
	local t = t0 - 0.4
	while t <= t1 + 1e-6 do
		local M, p = frame(t)
		local nx = x + (x - xp) * 0.955 + g * dt * dt
		nx = p + (nx - p).Unit * L
		xp, x = x, nx
		if t >= nextSample - 1e-6 then
			local X = (p - x).Unit
			local Z = pref - X * pref:Dot(X)
			Z = Z.Unit
			local Y = Z:Cross(X)
			local R = CFrame.fromMatrix(V(0, 0, 0), X, Y, Z)
			local G = CFrame.new(p - R * q) * R
			local T = (M * CFrame.new(pivotG)):Inverse() * G
			local rx, ry, rz = T:ToEulerAnglesXYZ()
			table.insert(out, { t = nextSample, ease = "linear", joints = { Glasses = { x = T.X, y = T.Y, f = -T.Z, rx = deg(rx), ry = deg(ry), rz = deg(rz) } } })
			nextSample += 2 / 30
		end
		t += dt
	end
	for _, k in out do
		table.insert(keys, k)
	end
end
-- A держит очки щипком за край оправы (точка щипка рига), дужки назад-внутрь
glassesKeys(rigA, aKeys, V(-0.05, -(rigA.P.handLen + 0.12), -(rigA.P.handW / 1.06 * 0.5 + 0.06)), V(-0.35, 0, 1), 6.5, 7.9)
-- B прижимает очки безымянным и большим к ладони: подвес у основания большого пальца, стёкла к объективу
glassesKeys(rigB, bKeys, V(-0.1, -0.22, -0.16), V(-0.25, 0, 1), 6.5, 7.9)

return {
	WomanA = { keys = aKeys },
	WomanB = { keys = bKeys },
}
