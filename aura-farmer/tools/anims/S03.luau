--!nocheck
-- Ключи анимации плана S03 (см. tools/lib/Pose.luau — формат ключей).
-- «THE AURA FARMER»: парень в центре поёт в объектив, держа серебряные очки двумя руками у груди;
-- девушки сзади снимают красные очки (B ведёт, A отстаёт на 1–2 кадра), ахают «О» и держат очки у талии.
--
-- Очки и кисти считаются из ОДНОЙ траектории очков (CFrame в char space): сустав Glasses
-- (у девушек — на голове, у парня — на правой кисти) и IK обеих кистей выводятся так, чтобы
-- точки щипка (большой + указательный) лежали на дужках/ободке очков в каждом ключе.

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Loader = require("../lib/loader")
local Pose = require("../lib/Pose")

local SHOT = Loader.load("src/shared/Shots/S03")
local DEBUG = process.env.S03_DEBUG ~= nil

local V = Vector3.new
local rad, deg = math.rad, math.deg

-- char Vector3 (z назад) -> {x, y, f} для DSL
local function F(v)
	return { v.X, v.Y, -v.Z }
end
-- {x, y, f} -> char Vector3
local function C(x, y, f)
	return V(x, y, -f)
end

-- как в Pose.luau (handFrame)
local function handFrame(fingers, palm, s)
	local Y = -(fingers.Unit)
	local X = if s == 1 then -palm else palm
	X = X - Y * X:Dot(Y)
	X = X.Unit
	local Z = X:Cross(Y)
	return CFrame.fromMatrix(Vector3.zero, X, Y, Z)
end

local function copyList(list)
	local out = {}
	for i, k in list do
		out[i] = k
	end
	return out
end

-- Положение очков: позиция (x, y, f), крен (правый конец вниз −), наклон (rx: −90 — дужки вверх).
local function G(x, y, f, roll, pitch, yaw)
	return CFrame.new(C(x, y, f)) * CFrame.Angles(0, rad(yaw or 0), 0) * CFrame.Angles(0, 0, rad(roll or 0)) * CFrame.Angles(rad(pitch or 0), 0, 0)
end

-- Вывод ключей кистей и сустава Glasses.
--   name — актёр плана; base — ключи тела (без rArm/lArm/joints);
--   grip = { pinch = {R = Vector3, L = Vector3} — точки щипка в осях очков, parent = "Head" | "RightHand" };
--   gk — ключи очков: { t, cf = CFrame | head = CFrame (смещение от «очки на носу»), R = {fingers, palm, pole}, L = {...}, ease }
local function derive(name, base, grip, gk)
	local a = SHOT.actors[name]
	local rig = require("../chars/" .. a.char)(a.opts or {})
	local solver = Pose.solver(rig)
	local P = rig.P
	local pw = P.handW / 1.06
	-- точка щипка в осях кисти (X — тыл кисти, Y — к запястью, −Z — сторона большого пальца)
	local off = grip.off
	local function pinchOffset(s)
		if off then
			return V(-s * off.palm, -off.along, -off.thumb)
		end
		return V(-s * 0.05, -(P.handLen + 0.12), -(pw * 0.5 + 0.06))
	end
	local pivotG = rig.pivots.Glasses
	local parent = grip.parent

	local armKeys = {}
	local function evalAt(keys, t)
		local tracks = Pose.tracks(copyList(keys), solver)
		local tr = Pose.evaluate(tracks, solver, t)
		return solver:fk(tr), tr
	end
	-- 1) для очков на голове: положение очков из движения головы
	local gcf = {}
	for i, k in gk do
		if k.cf then
			gcf[i] = k.cf
		else
			local cfs = evalAt(base, k.t)
			local M = cfs.Head * rig.rest.Head:Inverse()
			gcf[i] = M * CFrame.new(pivotG) * (k.head or CFrame.new())
		end
	end
	-- 2) кисти: запястье = точка щипка − поворот кисти * смещение щипка
	for i, k in gk do
		local key = { t = k.t, ease = k.ease }
		for _, side in { "R", "L" } do
			local s = if side == "R" then 1 else -1
			local h = k[side]
			local pinchW = gcf[i] * grip.pinch[side]
			local R3 = handFrame(h.fingers, h.palm, s)
			local wrist = pinchW - R3 * pinchOffset(s)
			key[if s == 1 then "rArm" else "lArm"] = {
				ik = F(wrist),
				pole = F(h.pole),
				wrist = { palm = F(h.palm), fingers = F(h.fingers) },
			}
		end
		armKeys[i] = key
	end
	-- 3) сустав Glasses: смещение относительно родительской кости в позе ключа
	local all = copyList(base)
	for _, k in armKeys do
		table.insert(all, k)
	end
	local out = copyList(base)
	for i, k in gk do
		local cfs = evalAt(all, k.t)
		local M = cfs[parent] * rig.rest[parent]:Inverse()
		local T = (M * CFrame.new(pivotG)):Inverse() * gcf[i]
		local rx, ry, rz = T:ToEulerAnglesXYZ()
		armKeys[i].joints = { Glasses = { x = T.X, y = T.Y, f = -T.Z, rx = deg(rx), ry = deg(ry), rz = deg(rz) } }
		table.insert(out, armKeys[i])
		if DEBUG then
			for _, side in { "Right", "Left" } do
				local key = armKeys[i][if side == "Right" then "rArm" else "lArm"]
				local want = C(key.ik[1], key.ik[2], key.ik[3])
				local got = (cfs[side .. "LowerArm"] * rig.motors[side .. "Hand"].C0).Position
				local err = (want - got).Magnitude
				if err > 0.01 then
					print(string.format("S03 %s t=%.3f %s wrist miss %.3f", name, k.t, side, err))
				end
			end
		end
	end
	return out
end

-- ===================================================================================
-- ПАРЕНЬ (центр): поёт «THE AU-ra FAR-MER», очки у груди, в конце подаётся к камере.
-- ===================================================================================
-- голова: наклон в мире (−: подбородок вверх), взгляд в объектив (камера ниже глаз на ≈5.8°)
local function manKey(t, wb, nodW, tilt, turn, face, root, ease)
	face.lookY = -(5.8 - nodW) / 18
	face.lookX = (turn or 0) / 22
	return {
		t = t,
		ease = ease,
		root = root or { y = 0 },
		waist = { bend = wb },
		neck = { nod = nodW - wb, tilt = tilt, turn = turn or 0 },
		face = face,
	}
end

local manBase = {
	manKey(2.633, 4, -3, 5, 0, { jaw = 0.2, oh = 0.1, brows = 0.9, blink = 0.5 }),
	manKey(2.7, 4, -3, 5, 0, { jaw = 0.25, oh = 0.1, brows = 0.9, blink = 0.5 }),
	manKey(2.733, 4, -3.2, 4.5, 0, { jaw = 0.3, oh = 0.3, brows = 0.95, blink = 0.35 }),
	manKey(2.767, 4, -3.5, 4, 0, { jaw = 0.45, oh = 0.55, brows = 1.0, blink = 0.15 }),
	manKey(2.833, 4, -5, 3, 0, { jaw = 0.9, oh = 0.4, brows = 1.15, blink = -0.15 }),
	manKey(2.9, 3.5, -6, -1.5, 0, { jaw = 1.15, oh = 0.4, brows = 0.85, blink = 0.75, squint = 0.5 }, { y = 0.03 }),
	manKey(2.967, 4, -4, -1, 0, { jaw = 0.95, oh = 0.35, brows = 1.15, blink = -0.1 }, { y = 0.015 }),
	manKey(3.033, 4, 0, 0, 0, { jaw = 0.55, oh = 0.7, brows = 1.1, blink = -0.15 }),
	manKey(3.1, 4, 0, 0, 0, { jaw = 0.12, oh = 1, brows = 1.05, blink = -0.1 }),
	manKey(3.167, 4, -1, 0, 0, { jaw = 0.5, oh = 0.35, brows = 1.1, blink = -0.15 }),
	manKey(3.233, 4.5, 2, -2, 0, { jaw = 0, oh = 0.75, smile = -0.6, brows = 0.9, frown = 0.15, blink = -0.1 }),
	manKey(3.3, 4.5, 2, -2.5, 0, { jaw = 0, oh = 0.7, smile = -0.65, browR = 1.15, browL = 0.8, frown = 0.1, blink = -0.1 }),
	manKey(3.367, 4, -1, -1, 0, { jaw = 0.38, oh = 0.25, brows = 1.0, blink = -0.1 }),
	manKey(3.467, 4, -2, 0, 0, { jaw = 0.65, oh = 0.15, brows = 1.1, blink = -0.15 }),
	manKey(3.533, 4.2, -1.5, 0, 0, { jaw = 0.35, oh = 0.2, brows = 1.05, blink = -0.1 }),
	manKey(3.567, 4.5, -1, 0, 0, { jaw = 0.05, oh = 0.3, brows = 1.0, blink = -0.1 }),
	manKey(3.633, 5.5, 0, 1.5, 0.5, { jaw = 0.55, oh = 0.25, brows = 1.05, blink = -0.15 }, { f = 0.01, y = -0.005 }),
	manKey(3.733, 7.2, 2, 3.5, 1.5, { jaw = 0.62, oh = 0.1, brows = 1.15, frown = 0.3, blink = -0.15 }, { f = 0.03, y = -0.02 }),
	manKey(3.833, 8.5, 4, 5.5, 3, { jaw = 0.62, oh = 0.1, brows = 1.1, frown = 0.4, blink = -0.15 }, { f = 0.05, y = -0.03 }),
	manKey(3.9, 9, 4.5, 6, 3.5, { jaw = 0.6, oh = 0.1, brows = 1.1, frown = 0.4, blink = -0.15 }, { f = 0.06, y = -0.035 }),
}
-- кисти: щипок большим и указательным, остальные свободно поджаты; ноги стоят
local MAN_HAND = { index = 0.5, middle = 0.72, ring = 0.82, pinky = 0.88, thumb = 0.45, thumbOut = 0.55, spread = 0.1 }
table.insert(manBase, {
	t = 2.7,
	rHand = MAN_HAND,
	lHand = MAN_HAND,
	rLeg = { ik = { 0.52, 0.27, 0 } },
	lLeg = { ik = { -0.52, 0.27, 0 } },
})
table.insert(manBase, {
	t = 3.8667,
	rHand = MAN_HAND,
	lHand = MAN_HAND,
	rLeg = { ik = { 0.52, 0.27, 0 } },
	lLeg = { ik = { -0.52, 0.27, 0 } },
})

-- кисти парня: тыльной стороной к камере, пальцы (пясть) вперёд-вверх-внутрь, ладонь вниз — большой палец
-- внутрь (щипок у шарнира очков); локти опущены вдоль тела
local function manHands(spread)
	spread = spread or 0
	return {
		R = { fingers = C(-0.2, 1, 0.3), palm = C(-1, 0, 0.25), pole = C(0.3 + spread, -1, 0.15) },
		L = { fingers = C(0.2, 1, 0.3), palm = C(1, 0, 0.25), pole = C(-0.3 - spread, -1, 0.15) },
	}
end
-- очки парня: стёкла почти горизонтально, дужки торчат вверх из кулаков (как в клипе)
local MAN_PITCH = -50
local function manG(t, y, f, roll, spread, ease)
	local h = manHands(spread)
	return { t = t, cf = G(0, y, f, roll, MAN_PITCH), R = h.R, L = h.L, ease = ease }
end
-- y — высота центра очков (char space, новые пропорции: плечи 4.6, низ груди ≈ 3.9)
local MAN_GLASSES = {
	manG(2.633, 4, 0.95, -8, 0),
	manG(2.7, 4, 0.95, -8, 0),
	manG(2.9, 4.01, 0.95, -7, 0),
	manG(3.033, 4, 0.95, -2, 0),
	manG(3.133, 3.99, 0.96, 8, 0),
	manG(3.3, 3.995, 0.96, 5, 0),
	manG(3.467, 4, 0.95, 0, 0),
	manG(3.633, 3.99, 0.97, 0, 0.1),
	manG(3.733, 3.95, 1.03, 0, 0.3),
	manG(3.833, 3.9, 1.07, 0, 0.45),
	manG(3.9, 3.89, 1.08, 0, 0.5),
}

local man = derive("Man", manBase, {
	parent = "RightHand",
	pinch = { R = V(0.5, 0.06, 0.06), L = V(-0.5, 0.06, 0.06) },
	-- щипок у середины кисти, с внутренней (ладонной) стороны: пальцы обхватывают шарнир
	off = { palm = 0.12, along = 0.3, thumb = 0.06 },
}, MAN_GLASSES)

-- ===================================================================================
-- ДЕВУШКА A (слева в кадре, +X мира): круглые красные очки, «джазовые» пальцы, отстаёт от B.
-- ===================================================================================
local function womanKey(t, neck, face, waist, root)
	return { t = t, neck = neck, face = face, waist = waist or { bend = 0 }, root = root or { x = 0 } }
end
local A_TURN = -5 -- голова дополнительно к корпусу смотрит в объектив
local aBase = {
	womanKey(2.633, { nod = 0, tilt = -4, turn = A_TURN }, { jaw = 0.18, brows = 0.3 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.7, { nod = 0, tilt = -4, turn = A_TURN }, { jaw = 0.2, brows = 0.3 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.8, { nod = 0, tilt = -4, turn = A_TURN }, { jaw = 0.3, oh = 0.3, brows = 0.4 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.833, { nod = -1, tilt = -3, turn = A_TURN }, { jaw = 0.45, oh = 0.8, brows = 0.6 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.867, { nod = -2, tilt = -1, turn = A_TURN }, { jaw = 0.55, oh = 1, brows = 1 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.9, { nod = -3, tilt = 1, turn = A_TURN }, { jaw = 0.7, oh = 1, brows = 1.05 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.933, { nod = -5, tilt = 3, turn = A_TURN }, { jaw = 0.8, oh = 1, brows = 1.15 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(2.967, { nod = -4, tilt = 3, turn = A_TURN }, { jaw = 0.8, oh = 1, brows = 1.1 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.033, { nod = 0, tilt = 2, turn = A_TURN }, { jaw = 0.6, oh = 0.9, brows = 1 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.1, { nod = 0, tilt = 3, turn = A_TURN }, { jaw = 0.3, oh = 0.6, brows = 0.85 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.167, { nod = 0, tilt = 5, turn = A_TURN }, { jaw = 0.35, oh = 0.8, brows = 0.85 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.3, { nod = 2, tilt = 6, turn = A_TURN }, { jaw = 0.15, oh = 0.4, brows = 0.6 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.433, { nod = 1, tilt = 6, turn = A_TURN }, { jaw = 0.5, oh = 1, brows = 0.8 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.567, { nod = 1, tilt = 6, turn = A_TURN }, { jaw = 0.35, oh = 0.8, brows = 0.8 }, nil, { x = -0.05, tilt = -1 }),
	womanKey(3.7, { nod = 0, tilt = 7, turn = A_TURN }, { jaw = 0.5, oh = 1, brows = 0.9 }, { tilt = 2 }, { x = -0.03, tilt = -1 }),
	womanKey(3.833, { nod = 0, tilt = 7, turn = A_TURN }, { jaw = 0.45, oh = 0.9, brows = 0.9 }, { tilt = 2.5 }, { x = -0.02, tilt = -1 }),
	womanKey(3.9, { nod = 0, tilt = 7, turn = A_TURN }, { jaw = 0.45, oh = 0.9, brows = 0.9 }, { tilt = 2.5 }, { x = -0.02, tilt = -1 }),
}
local A_HAND = { index = 0.55, middle = 0.02, ring = 0.02, pinky = 0.05, thumb = 0.6, thumbOut = 0.45, spread = 1 }
for _, t in { 2.7, 3.8667 } do
	table.insert(aBase, {
		t = t,
		rHand = A_HAND,
		lHand = A_HAND,
		rLeg = { ik = { 0.47, 0.25, 0 } },
		lLeg = { ik = { -0.47, 0.25, 0 } },
	})
end

-- кисти у висков: пальцы вверх, ладонь к лицу и чуть вперёд; локти низко
local A_FACE = {
	R = { fingers = C(-0.1, 1, 0.15), palm = C(-0.8, 0, 0.5), pole = C(0.6, -1, 0.4) },
	L = { fingers = C(0.1, 1, 0.15), palm = C(0.8, 0, 0.5), pole = C(-0.6, -1, 0.4) },
}
-- кисти у талии: предплечья вперёд-внутрь, кисть отогнута — пальцы веером вверх-наружу
local A_HOLD = {
	R = { fingers = C(0.25, 1, 0.35), palm = C(-0.9, 0, 0.3), pole = C(0.35, -1, -0.5) },
	L = { fingers = C(-0.25, 1, 0.35), palm = C(0.9, 0, 0.3), pole = C(-0.35, -1, -0.5) },
}
local function mix(h1, h2, u)
	local out = {}
	for side, a in h1 do
		local b = h2[side]
		out[side] = { fingers = a.fingers:Lerp(b.fingers, u), palm = a.palm:Lerp(b.palm, u), pole = a.pole:Lerp(b.pole, u) }
	end
	return out
end
local function onFace(t, dy, df, rx, hands, ease)
	return { t = t, head = CFrame.new(V(0, dy, -df)) * CFrame.Angles(rad(rx or 0), 0, 0), R = hands.R, L = hands.L, ease = ease }
end
local function inHands(t, x, y, f, roll, pitch, hands, ease)
	return { t = t, cf = G(x, y, f, roll, pitch), R = hands.R, L = hands.L, ease = ease }
end
-- y — высота очков (char space): на носу ≈ 4.65, подол топа ≈ 3.1
local A_GLASSES = {
	onFace(2.633, 0, 0, 0, A_FACE),
	onFace(2.7, 0, 0, 0, A_FACE),
	onFace(2.8, -0.03, 0.01, 0, A_FACE),
	onFace(2.833, -0.12, 0.04, 4, mix(A_FACE, A_HOLD, 0.05)),
	inHands(2.867, 0, 5.05, 0.85, 0, 12, mix(A_FACE, A_HOLD, 0.15)),
	inHands(2.9, 0, 4.86, 0.95, 0, 35, mix(A_FACE, A_HOLD, 0.35)),
	inHands(2.933, 0, 4.58, 1.0, 0, 60, mix(A_FACE, A_HOLD, 0.6)),
	inHands(2.967, 0, 4.28, 1.0, 0, 80, mix(A_FACE, A_HOLD, 0.8)),
	inHands(3.033, 0, 3.94, 0.98, 0, 96, mix(A_FACE, A_HOLD, 0.95)),
	inHands(3.1, 0, 3.66, 0.95, 0, 103, A_HOLD),
	inHands(3.167, 0, 3.7, 0.95, 0, 103, A_HOLD),
	inHands(3.3, 0, 3.7, 0.95, 2, 103, A_HOLD),
	inHands(3.433, 0, 3.7, 0.95, -3, 103, A_HOLD),
	inHands(3.567, 0, 3.7, 0.95, 2, 103, A_HOLD),
	inHands(3.7, 0.02, 3.69, 0.95, 0, 103, A_HOLD),
	inHands(3.833, 0.03, 3.69, 0.95, -1, 103, A_HOLD),
	inHands(3.9, 0.03, 3.69, 0.95, -1, 103, A_HOLD),
}
local womanA = derive("WomanA", aBase, {
	parent = "Head",
	pinch = { R = V(0.47, 0.02, 0.06), L = V(-0.47, 0.02, 0.06) },
	-- «О-кей»: щипок большим и указательным у середины кисти, остальные пальцы веером вверх
	off = { palm = 0.06, along = 0.28, thumb = 0.12 },
}, A_GLASSES)

-- ===================================================================================
-- ДЕВУШКА B (справа в кадре, −X мира): узкие красные очки, локти высоко и широко, ведёт рывок.
-- ===================================================================================
local B_TURN = 0
local bBase = {
	womanKey(2.633, { nod = 5, tilt = 0, turn = B_TURN }, { jaw = 0, brows = 0.1 }),
	womanKey(2.7, { nod = 5, tilt = 0, turn = B_TURN }, { jaw = 0, brows = 0.1 }),
	womanKey(2.767, { nod = 4, tilt = 0, turn = B_TURN }, { jaw = 0.05, brows = 0.5 }),
	womanKey(2.8, { nod = 3, tilt = 0, turn = B_TURN }, { jaw = 0.2, oh = 0.4, brows = 0.8 }),
	womanKey(2.833, { nod = 2, tilt = 0, turn = B_TURN }, { jaw = 0.4, oh = 0.8, brows = 0.95 }),
	womanKey(2.867, { nod = 1, tilt = 0, turn = B_TURN }, { jaw = 0.6, oh = 1, brows = 1.05 }),
	womanKey(2.9, { nod = 0, tilt = 0, turn = B_TURN }, { jaw = 0.8, oh = 1, brows = 1.15 }),
	womanKey(2.933, { nod = 0, tilt = 0, turn = B_TURN }, { jaw = 0.7, oh = 1, brows = 1.1 }),
	womanKey(2.967, { nod = 0, tilt = 0, turn = B_TURN }, { jaw = 0.6, oh = 1, brows = 1.05 }),
	womanKey(3.033, { nod = 0, tilt = 0, turn = B_TURN }, { jaw = 0.55, oh = 0.9, brows = 0.95 }),
	womanKey(3.167, { nod = 2, tilt = 0, turn = B_TURN - 5 }, { jaw = 0.05, oh = 0.2, brows = 0.5 }),
	womanKey(3.3, { nod = 1, tilt = 0, turn = B_TURN }, { jaw = 0.15, oh = 0.4, brows = 0.5 }),
	womanKey(3.433, { nod = 1, tilt = 0, turn = B_TURN }, { jaw = 0.45, oh = 1, brows = 0.8 }),
	womanKey(3.567, { nod = 1, tilt = -3, turn = B_TURN }, { jaw = 0.45, oh = 1, brows = 0.8 }),
	womanKey(3.7, { nod = 0, tilt = -4, turn = B_TURN }, { jaw = 0.3, oh = 0.7, brows = 0.75 }, { bend = 3 }),
	womanKey(3.833, { nod = 0, tilt = -4, turn = B_TURN }, { jaw = 0.4, oh = 0.9, brows = 0.85 }, { bend = 3 }),
	womanKey(3.9, { nod = 0, tilt = -4, turn = B_TURN }, { jaw = 0.4, oh = 0.9, brows = 0.85 }, { bend = 3 }),
}
local B_HAND = { index = 0.5, middle = 0.62, ring = 0.72, pinky = 0.78, thumb = 0.5, thumbOut = 0.4, spread = 0.1 }
for _, t in { 2.7, 3.8667 } do
	table.insert(bBase, {
		t = t,
		rHand = B_HAND,
		lHand = B_HAND,
		rLeg = { ik = { 0.5, 0.25, 0 } },
		lLeg = { ik = { -0.5, 0.25, 0 } },
	})
end
-- у висков: пальцы вперёд, ладони к голове (большой палец сверху), локти высоко в стороны
local B_FACE = {
	R = { fingers = C(-0.2, 0.35, 1), palm = C(-1, 0, 0.1), pole = C(1, 0.35, 0.1) },
	L = { fingers = C(0.2, 0.35, 1), palm = C(1, 0, 0.1), pole = C(-1, 0.35, 0.1) },
}
-- у талии: предплечья горизонтально внутрь, локти наружу и назад
local B_HOLD = {
	R = { fingers = C(-0.45, 0.25, 1), palm = C(-1, 0, 0.2), pole = C(1, -0.5, -0.7) },
	L = { fingers = C(0.45, 0.25, 1), palm = C(1, 0, 0.2), pole = C(-1, -0.5, -0.7) },
}
local B_GLASSES = {
	onFace(2.633, 0, 0, 0, B_FACE),
	onFace(2.7, 0, 0, 0, B_FACE),
	onFace(2.767, -0.08, 0.02, 2, B_FACE),
	onFace(2.8, -0.2, 0.06, 4, mix(B_FACE, B_HOLD, 0.05)),
	onFace(2.833, -0.3, 0.12, 2, mix(B_FACE, B_HOLD, 0.12)),
	inHands(2.867, 0, 4.68, 0.95, 0, 8, mix(B_FACE, B_HOLD, 0.3)),
	inHands(2.9, 0, 4.33, 1.0, 0, 18, mix(B_FACE, B_HOLD, 0.55)),
	inHands(2.933, 0, 3.98, 1.0, 0, 28, mix(B_FACE, B_HOLD, 0.75)),
	inHands(2.967, 0, 3.68, 0.98, 0, 38, mix(B_FACE, B_HOLD, 0.9)),
	inHands(3.033, 0, 3.44, 0.95, 0, 45, B_HOLD),
	inHands(3.067, 0, 3.42, 0.95, 0, 45, B_HOLD),
	inHands(3.1, 0, 3.45, 0.95, 0, 45, B_HOLD),
	inHands(3.3, 0, 3.45, 0.95, 0, 45, B_HOLD),
	inHands(3.567, 0, 3.45, 0.95, -2, 45, B_HOLD),
	inHands(3.833, -0.02, 3.44, 0.97, -3, 45, B_HOLD),
	inHands(3.9, -0.02, 3.44, 0.97, -3, 45, B_HOLD),
}
local womanB = derive("WomanB", bBase, {
	parent = "Head",
	pinch = { R = V(0.5, 0.05, 0.22), L = V(-0.5, 0.05, 0.22) },
}, B_GLASSES)

return {
	WomanA = { keys = womanA },
	Man = { keys = man },
	WomanB = { keys = womanB },
}
