--!nocheck
-- Компилятор поз (Lune): ключи анимации в удобном «анатомическом» виде -> Motor6D.Transform
-- (прямая кинематика + IK для рук/ног) -> «запечённая» KeyframeSequence (30 к/с, Linear).
--
-- КЛЮЧ анимации (t — абсолютное время ролика, секунды):
-- {
--   t = 4.10, ease = "smooth",            -- сглаживание сегмента ОТ этого ключа (по умолчанию smooth)
--   root  = { x=0, y=0, f=0, turn=0, bend=0, tilt=0 },  -- смещение таза (студы, f — вперёд), поворот влево+, наклон вперёд+, крен вправо+
--   waist = { bend=0, turn=0, tilt=0 },                 -- наклон вперёд+, поворот влево+, крен вправо+
--   neck  = { nod=0, turn=0, tilt=0 },                  -- кивок вниз+, поворот влево+, наклон к правому плечу+
--   rArm  = { fwd=0, out=0, twist=0, elbow=0, wrist={bend=0, side=0, twist=0} },   -- FK (градусы)
--   rArm  = { dir={x,y,f}, twist=0, elbow=0 },                                     -- FK через направление плеча
--   rArm  = { ik={x,y,f}, space="body"|"hips"|"chest"|"head", pole={x,y,f},        -- IK: куда поставить запястье
--             wrist={bend,side,twist} | wrist={palm={x,y,f}, fingers={x,y,f}} },
--   lArm  = ...  (то же, зеркально: out+ всегда «в сторону от тела», twist+ — внутрь)
--   rLeg  = { fwd=0, out=0, twist=0, knee=0, ankle={bend=0, twist=0, roll=0} }      -- FK
--   rLeg  = { ik={x,y,f}, space=..., pole={x,y,f}, foot={yaw=0, pitch=0, roll=0} } -- IK: куда поставить лодыжку
--   rHand = "fist" | "open" | "relaxed" | "grip" | "thumb" | "point" | "spread" | "peace"
--           или { curl=0..1, index=, middle=, ring=, pinky=, thumb=0..1, thumbOut=0..1, spread=0..1 }
--   face  = { jaw=0..1, brows=-1..1, browL=, browR=, blink=0..1, smile=0..1, ... }  -- каналы задаёт персонаж
--   joints = { Glasses = { x=0, y=0, f=0, rx=0, ry=0, rz=0 }, ... }                -- любые доп. суставы
-- }
-- Координаты {x,y,f}: x вправо, y вверх, f ВПЕРЁД (студы) в позе покоя (char space: начало на земле между стоп).
-- Для space="hips"/"chest"/"head" точка задаётся так же в позе покоя и затем «едет» вместе с этой костью.
-- Группа, заданная в ключе, задаётся целиком (не указанные поля = 0). Группа, не заданная в ключе,
-- интерполируется между соседними ключами, где она задана.

local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Loader = require("./loader")
local MathUtil = Loader.load("src/shared/Anim/MathUtil")
local Easing = Loader.load("src/shared/Anim/Easing")

local Pose = {}

local rad = math.rad
local ID = CFrame.new()
local DOWN = Vector3.new(0, -1, 0)

Pose.HANDS = {
	relaxed = { curl = 0.3, thumb = 0.3, thumbOut = 0.2, spread = 0.1 },
	open = { curl = 0.05, thumb = 0.05, thumbOut = 0.3, spread = 0.2 },
	spread = { curl = 0, thumb = 0, thumbOut = 0.9, spread = 1 },
	fist = { curl = 1, thumb = 0.85, thumbOut = 0.1, spread = 0 },
	grip = { curl = 0.72, thumb = 0.7, thumbOut = 0.35, spread = 0 },
	thumb = { curl = 1, thumb = 0, thumbOut = 0.9, spread = 0 },
	point = { curl = 1, index = 0, thumb = 0.8, thumbOut = 0.1, spread = 0 },
	peace = { curl = 1, index = 0, middle = 0, thumb = 0.85, spread = 0.7 },
}

local GROUPS = { "root", "waist", "neck", "rArm", "lArm", "rLeg", "lLeg", "rHand", "lHand", "face", "joints" }

local function vec(t, default)
	if t == nil then
		return default
	end
	if typeof(t) == "Vector3" then
		return t
	end
	return Vector3.new(t.x or t[1] or 0, t.y or t[2] or 0, -(t.f or t[3] or 0))
end

-- ===== Нормализация ключа группы в плоскую таблицу чисел (+ режимы) =====

local function flattenInto(out, prefix, tbl)
	for k, val in tbl do
		if type(val) == "number" then
			out[prefix .. k] = val
		elseif type(val) == "table" then
			flattenInto(out, prefix .. k .. ".", val)
		end
	end
end

local function normHand(h)
	if type(h) == "string" then
		h = Pose.HANDS[h] or error("unknown hand preset " .. h)
	end
	local c = h.curl or 0
	return {
		index = h.index or c,
		middle = h.middle or c,
		ring = h.ring or c,
		pinky = h.pinky or c,
		thumb = h.thumb or 0,
		thumbOut = h.thumbOut or 0,
		spread = h.spread or 0,
	}
end

local function normLimb(g, isArm)
	local out = {}
	local mode
	if g.ik then
		mode = "ik:" .. (g.space or "body")
		local p = vec(g.ik)
		out.ikx, out.iky, out.ikz = p.X, p.Y, p.Z
		local pole = vec(g.pole)
		if pole then
			out.px, out.py, out.pz = pole.X, pole.Y, pole.Z
			mode ..= ":pole"
		end
	else
		mode = "fk"
		if g.dir then
			local d = vec(g.dir).Unit
			out.dx, out.dy, out.dz = d.X, d.Y, d.Z
			mode = "fkdir"
		else
			out.fwd = g.fwd or 0
			out.out = g.out or 0
		end
		out.twist = g.twist or 0
		if isArm then
			out.elbow = g.elbow or 0
		else
			out.knee = g.knee or 0
		end
	end
	out.ltwist = g.twist or 0
	local w = if isArm then g.wrist else (g.ankle or g.foot)
	if w then
		if w.palm or w.fingers then
			mode ..= ":palm"
			local pn = vec(w.palm or { 0, 0, 0 })
			local fd = vec(w.fingers or { 0, -1, 0 })
			out.pnx, out.pny, out.pnz = pn.X, pn.Y, pn.Z
			out.fdx, out.fdy, out.fdz = fd.X, fd.Y, fd.Z
		else
			out.wbend = w.bend or w.pitch or 0
			out.wside = w.side or w.roll or 0
			out.wtwist = w.twist or w.yaw or 0
		end
	end
	return out, mode
end

local function normGroup(name, g)
	if name == "rHand" or name == "lHand" then
		return normHand(g), "hand"
	elseif name == "rArm" or name == "lArm" then
		return normLimb(g, true)
	elseif name == "rLeg" or name == "lLeg" then
		return normLimb(g, false)
	elseif name == "root" then
		local p = vec(g.pos or { g.x or 0, g.y or 0, g.f or 0 })
		return { x = p.X, y = p.Y, z = p.Z, turn = g.turn or 0, bend = g.bend or 0, tilt = g.tilt or 0 }, "root"
	elseif name == "waist" then
		return { bend = g.bend or 0, turn = g.turn or 0, tilt = g.tilt or 0 }, "waist"
	elseif name == "neck" then
		return { nod = g.nod or 0, turn = g.turn or 0, tilt = g.tilt or 0 }, "neck"
	elseif name == "face" then
		local out = {}
		flattenInto(out, "", g)
		return out, "face"
	elseif name == "joints" then
		local out = {}
		for jn, j in g do
			out[jn .. ".x"] = j.x or 0
			out[jn .. ".y"] = j.y or 0
			out[jn .. ".z"] = -(j.f or 0)
			out[jn .. ".rx"] = j.rx or 0
			out[jn .. ".ry"] = j.ry or 0
			out[jn .. ".rz"] = j.rz or 0
		end
		return out, "joints"
	end
	error("unknown group " .. name)
end

-- ===== Интерполяция дорожки группы =====

-- track = { times = {}, values = { {field=num} }, eases = {}, mode = "..." }
local function evalTrack(track, t)
	local times = track.times
	local n = #times
	if n == 1 or t <= times[1] then
		return track.values[1]
	end
	if t >= times[n] then
		return track.values[n]
	end
	local i = MathUtil.findSegment(times, t)
	local t0, t1 = times[i], times[i + 1]
	local dt = t1 - t0
	local u = (t - t0) / dt
	local ease = track.eases[i]
	local a, b = track.values[i], track.values[i + 1]
	local out = {}
	if ease == "smooth" then
		local prev = track.values[i - 1]
		local nxt = track.values[i + 2]
		for k, pa in a do
			local pb = b[k] or pa
			-- автозажатые касательные Катмулла-Рома (без перелёта на экстремумах)
			local m0, m1 = 0, 0
			if prev and prev[k] ~= nil then
				local pp = prev[k]
				if not ((pa >= pp and pa >= pb) or (pa <= pp and pa <= pb)) then
					m0 = (pb - pp) / (t1 - times[i - 1]) * dt
				end
			end
			if nxt and nxt[k] ~= nil then
				local pn = nxt[k]
				if not ((pb >= pa and pb >= pn) or (pb <= pa and pb <= pn)) then
					m1 = (pn - pa) / (times[i + 2] - t0) * dt
				end
			end
			out[k] = MathUtil.hermite(pa, m0, pb, m1, u)
		end
	else
		local e = Easing.named(ease, u)
		for k, pa in a do
			local pb = b[k] or pa
			out[k] = pa + (pb - pa) * e
		end
	end
	return out
end

-- ===== Кинематика =====

local function eulerYXZ(turn, bend, tilt)
	-- поворот влево+, наклон вперёд+, крен вправо+
	return CFrame.Angles(0, rad(turn), 0) * CFrame.Angles(rad(-bend), 0, 0) * CFrame.Angles(0, 0, rad(-tilt))
end

local Solver = {}
Solver.__index = Solver

function Pose.solver(rig)
	local self = setmetatable({}, Solver)
	self.rig = rig
	-- порядок костей от корня (родитель раньше ребёнка)
	local order = {}
	local seen = { HumanoidRootPart = true }
	local changed = true
	while changed do
		changed = false
		for child, parent in rig.motorParent do
			if not seen[child] and seen[parent] then
				seen[child] = true
				table.insert(order, child)
				changed = true
			end
		end
	end
	self.order = order
	return self
end

-- Мировые (char space) CFrame костей по текущим transforms.
function Solver:fk(transforms, upto)
	local rig = self.rig
	local cfs = { HumanoidRootPart = rig.rest.HumanoidRootPart }
	for _, b in self.order do
		local m = rig.motors[b]
		local p = rig.motorParent[b]
		cfs[b] = cfs[p] * m.C0 * (transforms[b] or ID) * m.C1:Inverse()
		if upto and b == upto then
			break
		end
	end
	return cfs
end

local function boneCf(self, cfs, bone)
	return cfs[bone]
end

-- Пространство IK: rest-координаты, «едущие» вместе с костью.
function Solver:spaceCf(space, cfs)
	local rig = self.rig
	if space == "body" then
		return ID
	end
	local bone = if space == "hips" then "LowerTorso" elseif space == "chest" then "UpperTorso" elseif space == "head" then "Head" else nil
	assert(bone, "unknown IK space " .. tostring(space))
	return cfs[bone] * rig.rest[bone]:Inverse()
end

local function rotOnly(cf)
	return cf - cf.Position
end

-- Двухзвенный IK. Возвращает R1 (поворот верхнего сегмента, char space) и угол сгиба.
local function twoBone(S, T, L1, L2, poleDir, isArm)
	local D = T - S
	local d = D.Magnitude
	local minD = math.abs(L1 - L2) + 1e-3
	local maxD = (L1 + L2) * 0.9995
	d = math.clamp(d, minD, maxD)
	local dir = if D.Magnitude > 1e-6 then D.Unit else DOWN
	local cosA = math.clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local pp = poleDir - dir * poleDir:Dot(dir)
	if pp.Magnitude < 1e-4 then
		pp = Vector3.new(0, 0, 1) - dir * dir.Z
		if pp.Magnitude < 1e-4 then
			pp = Vector3.new(1, 0, 0)
		end
	end
	local bend = pp.Unit
	local E = S + (dir * cosA + bend * sinA) * L1
	local Tc = S + dir * d
	local u = (E - S).Unit
	local vv = (Tc - E).Unit
	local w = vv - u * u:Dot(vv)
	if w.Magnitude < 1e-5 then
		w = -bend
	end
	w = w.Unit
	local theta = math.acos(math.clamp(u:Dot(vv), -1, 1))
	local R
	if isArm then
		R = CFrame.fromMatrix(Vector3.zero, u:Cross(w), -u, -w)
	else
		R = CFrame.fromMatrix(Vector3.zero, w:Cross(u), -u, w)
	end
	return R, theta
end

local function handFrame(fingers, palm, s)
	-- s = 1 правая (ладонь в покое смотрит в -X), -1 левая (в +X)
	local Y = -(fingers.Unit)
	local X = if s == 1 then -palm else palm
	X = X - Y * X:Dot(Y)
	if X.Magnitude < 1e-5 then
		X = Vector3.new(1, 0, 0) - Y * Y.X
	end
	X = X.Unit
	local Z = X:Cross(Y)
	return CFrame.fromMatrix(Vector3.zero, X, Y, Z)
end

local function wristFk(v, s)
	return CFrame.Angles(0, rad(s * (v.wtwist or 0)), 0) * CFrame.Angles(0, 0, rad(-s * (v.wbend or 0))) * CFrame.Angles(rad(v.wside or 0), 0, 0)
end

local function ankleFk(v, s)
	return CFrame.Angles(0, rad(s * (v.wtwist or 0)), 0) * CFrame.Angles(rad(v.wbend or 0), 0, 0) * CFrame.Angles(0, 0, rad(-s * (v.wside or 0)))
end

function Solver:limb(transforms, cfs, side, isArm, v, mode)
	local rig = self.rig
	local s = if side == "Right" then 1 else -1
	local seg1 = side .. (if isArm then "UpperArm" else "UpperLeg")
	local seg2 = side .. (if isArm then "LowerArm" else "LowerLeg")
	local seg3 = side .. (if isArm then "Hand" else "Foot")
	local parentBone = rig.motorParent[seg1]
	local R0 = rotOnly(cfs[parentBone])
	local isIK = string.sub(mode, 1, 2) == "ik"
	local palmMode = string.find(mode, ":palm") ~= nil

	local R1, bendAngle
	if isIK then
		local space = string.match(mode, "^ik:(%a+)")
		local spc = self:spaceCf(space, cfs)
		local S = (cfs[parentBone] * rig.motors[seg1].C0).Position
		local T = spc * Vector3.new(v.ikx, v.iky, v.ikz)
		local pole
		if v.px then
			pole = rotOnly(spc) * Vector3.new(v.px, v.py, v.pz)
		elseif isArm then
			pole = R0 * Vector3.new(s * 0.7, -0.3, 0.65)
		else
			pole = R0 * Vector3.new(s * 0.15, 0, -1)
		end
		local L1 = if isArm then rig.lengths.upperArm else rig.lengths.upperLeg
		local L2 = if isArm then rig.lengths.lowerArm else rig.lengths.lowerLeg
		R1, bendAngle = twoBone(S, T, L1, L2, pole, isArm)
		-- скрутка вокруг оси сегмента (для рук двигает «локоть» не меняя кисти — оставляем 0 по умолчанию)
		transforms[seg1] = R0:Inverse() * R1
	else
		local d
		if string.sub(mode, 1, 5) == "fkdir" then
			d = Vector3.new(v.dx, v.dy, v.dz).Unit
		else
			d = (CFrame.Angles(0, 0, rad(s * v.out)) * CFrame.Angles(rad(v.fwd), 0, 0)) * DOWN
		end
		local T1 = MathUtil.fromTo(DOWN, d) * CFrame.Angles(0, rad(s * (v.twist or 0)), 0)
		transforms[seg1] = T1
		R1 = R0 * T1
		bendAngle = rad(if isArm then (v.elbow or 0) else (v.knee or 0))
	end
	local T2 = if isArm then CFrame.Angles(bendAngle, 0, 0) else CFrame.Angles(-bendAngle, 0, 0)
	transforms[seg2] = T2
	local R2 = R1 * T2
	if palmMode then
		local space = string.match(mode, "^ik:(%a+)") or "body"
		local spr = rotOnly(self:spaceCf(space, cfs))
		local R3
		if isArm then
			R3 = handFrame(spr * Vector3.new(v.fdx, v.fdy, v.fdz), spr * Vector3.new(v.pnx, v.pny, v.pnz), s)
		else
			-- для стопы: fingers = направление носка, palm = «верх» стопы
			local toe = (spr * Vector3.new(v.fdx, v.fdy, v.fdz)).Unit
			local up = spr * Vector3.new(v.pnx, v.pny, v.pnz)
			local Z = -toe
			local X = up:Cross(Z)
			if X.Magnitude < 1e-5 then
				X = Vector3.new(1, 0, 0)
			end
			X = X.Unit
			R3 = CFrame.fromMatrix(Vector3.zero, X, Z:Cross(X), Z)
		end
		transforms[seg3] = R2:Inverse() * R3
	elseif not isArm and isIK then
		-- стопа по умолчанию стоит ровно (в пространстве IK), углы — поправки
		local space = string.match(mode, "^ik:(%a+)") or "body"
		local spr = rotOnly(self:spaceCf(space, cfs))
		local R3 = spr * ankleFk(v, s)
		transforms[seg3] = R2:Inverse() * R3
	else
		transforms[seg3] = if isArm then wristFk(v, s) else ankleFk(v, s)
	end
end

function Solver:fingers(transforms, side, h)
	local rig = self.rig
	if not rig.bones[side .. "Index1"] then
		return
	end
	local s = if side == "Right" then 1 else -1
	local spreadDeg = { Index = 12, Middle = 3, Ring = -5, Pinky = -14 }
	local keys = { Index = "index", Middle = "middle", Ring = "ring", Pinky = "pinky" }
	for f, key in keys do
		local c = h[key] or 0
		transforms[side .. f .. "1"] = CFrame.Angles(rad(spreadDeg[f] * (h.spread or 0)), 0, 0) * CFrame.Angles(0, 0, rad(-s * c * 85))
		transforms[side .. f .. "2"] = CFrame.Angles(0, 0, rad(-s * c * 100))
	end
	local th = h.thumb or 0
	local to = h.thumbOut or 0
	transforms[side .. "Thumb1"] = CFrame.Angles(rad(15 + 45 * to), 0, 0) * CFrame.Angles(0, 0, rad(-s * (10 + 55 * th)))
	transforms[side .. "Thumb2"] = CFrame.Angles(0, 0, rad(-s * 75 * th))
end

-- Лицевые каналы: rig.face[канал] = { { joint=, pos=Vector3 (при 1.0), rot=Vector3 градусы (при 1.0) }, ... }
function Solver:face(acc, values)
	local cfg = self.rig.face
	for ch, val in values do
		local list = cfg[ch]
		if list then
			for _, e in list do
				local a = acc[e.joint]
				if not a then
					a = { pos = Vector3.zero, rot = Vector3.zero }
					acc[e.joint] = a
				end
				if e.pos then
					a.pos += e.pos * val
				end
				if e.rot then
					a.rot += e.rot * val
				end
			end
		end
	end
end

-- Полная поза: values[группа] = плоская таблица, modes[группа] = режим.
function Solver:pose(values, modes)
	local rig = self.rig
	local tr = {}
	local r = values.root
	if r then
		tr.LowerTorso = CFrame.new(r.x, r.y, r.z) * eulerYXZ(r.turn, r.bend, r.tilt)
	end
	local w = values.waist
	if w then
		tr.UpperTorso = eulerYXZ(w.turn, w.bend, w.tilt)
	end
	local n = values.neck
	if n then
		tr.Head = eulerYXZ(n.turn, n.nod, n.tilt)
	end
	local cfs = self:fk(tr)
	for _, g in { { "rArm", "Right", true }, { "lArm", "Left", true }, { "rLeg", "Right", false }, { "lLeg", "Left", false } } do
		local v = values[g[1]]
		if v then
			self:limb(tr, cfs, g[2], g[3], v, modes[g[1]])
		end
	end
	if values.rHand then
		self:fingers(tr, "Right", values.rHand)
	end
	if values.lHand then
		self:fingers(tr, "Left", values.lHand)
	end
	local acc = {}
	if values.face then
		self:face(acc, values.face)
	end
	if values.joints then
		for k, val in values.joints do
			local jn, field = string.match(k, "^(.+)%.(%a+)$")
			local a = acc[jn]
			if not a then
				a = { pos = Vector3.zero, rot = Vector3.zero }
				acc[jn] = a
			end
			if field == "x" then
				a.pos += Vector3.new(val, 0, 0)
			elseif field == "y" then
				a.pos += Vector3.new(0, val, 0)
			elseif field == "z" then
				a.pos += Vector3.new(0, 0, val)
			elseif field == "rx" then
				a.rot += Vector3.new(val, 0, 0)
			elseif field == "ry" then
				a.rot += Vector3.new(0, val, 0)
			elseif field == "rz" then
				a.rot += Vector3.new(0, 0, val)
			end
		end
	end
	for jn, a in acc do
		if rig.bones[jn] then
			tr[jn] = CFrame.new(a.pos) * CFrame.Angles(rad(a.rot.X), rad(a.rot.Y), rad(a.rot.Z))
		end
	end
	return tr
end

-- ===== Дорожки из ключей =====

-- Возвращает tracks[группа] = { times, values, eases, mode }.
function Pose.tracks(keys, solver)
	table.sort(keys, function(a, b)
		return a.t < b.t
	end)
	local tracks = {}
	for _, g in GROUPS do
		local tr = { times = {}, values = {}, eases = {}, modes = {}, raw = {} }
		for _, k in keys do
			local gv = k[g]
			if gv ~= nil then
				local val, mode = normGroup(g, gv)
				table.insert(tr.times, k.t)
				table.insert(tr.values, val)
				table.insert(tr.eases, (type(gv) == "table" and gv.ease) or k.ease or "smooth")
				table.insert(tr.modes, mode)
				table.insert(tr.raw, gv)
			end
		end
		if #tr.times > 0 then
			-- одинаковый набор полей у всех ключей группы (недостающие = 0)
			local fields = {}
			for _, val in tr.values do
				for k in val do
					fields[k] = true
				end
			end
			for _, val in tr.values do
				for k in fields do
					if val[k] == nil then
						val[k] = 0
					end
				end
			end
			tracks[g] = tr
		end
	end
	-- Смешанные FK/IK в одной конечности: переводим FK-ключи в IK (точка запястья/лодыжки из FK).
	for _, g in { "rArm", "lArm", "rLeg", "lLeg" } do
		local tr = tracks[g]
		if tr then
			local ikMode
			for _, m in tr.modes do
				if string.sub(m, 1, 2) == "ik" then
					ikMode = ikMode or m
				end
			end
			if ikMode then
				for i, m in tr.modes do
					if string.sub(m, 1, 2) ~= "ik" then
						tr.values[i], tr.modes[i] = Pose._fkToIk(solver, tracks, g, i, ikMode)
					end
				end
			end
			-- все ключи группы должны иметь одинаковый набор полей
			local base = tr.modes[1]
			for i, m in tr.modes do
				local norm = function(x)
					return (string.gsub(x, ":pole", ""))
				end
				if norm(m) ~= norm(base) then
					error(string.format("группа %s: разные режимы ключей (%s и %s) в t=%.3f — сделайте их одинаковыми", g, base, m, tr.times[i]))
				end
			end
			-- заполнить pole по умолчанию там, где его не задали, если у других ключей он есть
			local anyPole = false
			for _, m in tr.modes do
				anyPole = anyPole or string.find(m, ":pole") ~= nil
			end
			if anyPole then
				for i, m in tr.modes do
					if not string.find(m, ":pole") then
						local val = tr.values[i]
						local s = if string.sub(g, 1, 1) == "r" then 1 else -1
						local isArm = string.find(g, "Arm") ~= nil
						local d = if isArm then Vector3.new(s * 0.7, -0.3, 0.65) else Vector3.new(s * 0.15, 0, -1)
						val.px, val.py, val.pz = d.X, d.Y, d.Z
						tr.modes[i] = m .. ":pole"
					end
				end
			end
		end
	end
	return tracks
end

function Pose._fkToIk(solver, tracks, g, i, ikMode)
	local tr = tracks[g]
	local t = tr.times[i]
	local values, modes = {}, {}
	for name, other in tracks do
		if name == "root" or name == "waist" or name == "neck" then
			values[name] = evalTrack(other, t)
			modes[name] = other.modes[1]
		end
	end
	values[g] = tr.values[i]
	modes[g] = tr.modes[i]
	local pose = solver:pose(values, modes)
	local cfs = solver:fk(pose)
	local isArm = string.find(g, "Arm") ~= nil
	local side = if string.sub(g, 1, 1) == "r" then "Right" else "Left"
	local seg2 = side .. (if isArm then "LowerArm" else "LowerLeg")
	local seg3 = side .. (if isArm then "Hand" else "Foot")
	local wristWorld = (cfs[seg2] * solver.rig.motors[seg3].C0).Position
	local elbowWorld = (cfs[solver.rig.motorParent[seg2]] * solver.rig.motors[seg2].C0).Position
	local space = string.match(ikMode, "^ik:(%a+)")
	local spc = solver:spaceCf(space, cfs)
	local p = spc:Inverse() * wristWorld
	local shoulder = (cfs[solver.rig.motorParent[side .. (if isArm then "UpperArm" else "UpperLeg")]] * solver.rig.motors[side .. (if isArm then "UpperArm" else "UpperLeg")].C0).Position
	local mid = (shoulder + wristWorld) / 2
	local pole = rotOnly(spc):Inverse() * (elbowWorld - mid)
	local out = { ikx = p.X, iky = p.Y, ikz = p.Z, px = pole.X, py = pole.Y, pz = pole.Z, ltwist = 0 }
	local old = tr.values[i]
	local mode = ikMode
	if string.find(ikMode, ":palm") then
		error("группа " .. g .. ": смешивание FK-ключей с IK-ключами, у которых wrist={palm=...}, не поддерживается — задайте IK во всех ключах")
	end
	out.wbend, out.wside, out.wtwist = old.wbend, old.wside, old.wtwist
	if not string.find(mode, ":pole") then
		mode ..= ":pole"
	end
	return out, mode
end

function Pose.evaluate(tracks, solver, t)
	local values, modes = {}, {}
	for g, tr in tracks do
		values[g] = evalTrack(tr, t)
		modes[g] = tr.modes[1]
	end
	local rig = solver.rig
	if rig.defaultHand then
		values.rHand = values.rHand or normHand(rig.defaultHand)
		values.lHand = values.lHand or normHand(rig.defaultHand)
	end
	if rig.defaultFace then
		local f = values.face or {}
		for k, val in rig.defaultFace do
			if f[k] == nil then
				f[k] = val
			end
		end
		values.face = f
	end
	return solver:pose(values, modes)
end

-- ===== Запекание в KeyframeSequence =====

local function angleBetween(a, b)
	local _, ang = (rotOnly(a):Inverse() * rotOnly(b)):ToAxisAngle()
	return math.abs(ang)
end

local function closeEnough(a, b, posTol, angTol)
	if (a.Position - b.Position).Magnitude > posTol then
		return false
	end
	return angleBetween(a, b) <= angTol
end

-- shot: { start, finish }, actor: { keys = {...} }, rig: Rig-объект (tools/lib/Rig.luau)
function Pose.bake(rig, shot, actor, name, fps)
	fps = fps or 30
	local solver = Pose.solver(rig)
	local tracks = Pose.tracks(actor.keys, solver)
	local frames = {}
	local dur = shot.finish - shot.start
	local n = math.max(1, math.floor(dur * fps + 0.5))
	for i = 0, n do
		local lt = math.min(i / fps, dur)
		local tr = Pose.evaluate(tracks, solver, shot.start + lt)
		table.insert(frames, { time = lt, tr = tr })
	end
	-- все кости рига должны быть в каждом кадре (полные позы)
	local boneList = {}
	for b in rig.motorParent do
		table.insert(boneList, b)
	end
	table.sort(boneList)
	for _, f in frames do
		for _, b in boneList do
			f.tr[b] = f.tr[b] or ID
		end
	end
	-- прореживание: убрать кадры, которые линейная интерполяция соседей воспроизводит с точностью
	local kept = { frames[1] }
	local last = 1
	for i = 2, #frames - 1 do
		local nextF = frames[i + 1]
		local ok = true
		for j = last + 1, i do
			local alpha = (frames[j].time - frames[last].time) / (nextF.time - frames[last].time)
			for _, b in boneList do
				local interp = frames[last].tr[b]:Lerp(nextF.tr[b], alpha)
				if not closeEnough(interp, frames[j].tr[b], 0.004, rad(0.25)) then
					ok = false
					break
				end
			end
			if not ok then
				break
			end
		end
		if not ok then
			table.insert(kept, frames[i])
			last = i
		end
	end
	if #frames > 1 then
		table.insert(kept, frames[#frames])
	end

	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = false
	kfs.Priority = Enum.AnimationPriority.Action
	for _, f in kept do
		local kf = Instance.new("Keyframe")
		kf.Time = f.time
		kf.Name = "Keyframe"
		local poses = {}
		local rootPose = Instance.new("Pose")
		rootPose.Name = "HumanoidRootPart"
		rootPose.CFrame = ID
		rootPose.Weight = 0
		rootPose.Parent = kf
		poses.HumanoidRootPart = rootPose
		for _, b in solver.order do
			local p = Instance.new("Pose")
			p.Name = b
			p.CFrame = f.tr[b]
			p.Weight = 1
			p.EasingStyle = Enum.PoseEasingStyle.Linear
			p.EasingDirection = Enum.PoseEasingDirection.In
			p.Parent = poses[rig.motorParent[b]]
			poses[b] = p
		end
		kf.Parent = kfs
	end
	kfs:SetAttribute("Frames", #frames)
	kfs:SetAttribute("Keyframes", #kept)
	return kfs, tracks
end

return Pose
