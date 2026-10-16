--!strict
-- Процедурная ходьба без состояния: стопы ставятся в точки на пути и стоят там всю опору (IK ног),
-- таз опускается при ударе стопы (вес), корпус и руки качаются в противофазе.
-- Всё — функция времени t, поэтому перемотка и превиз работают без симуляции.

local MathX = require(script.Parent.Parent.Math)
local Rig = require(script.Parent.Parent.Rig)
local Track = require(script.Parent.Parent.Track)

local Gait = {}

export type PathKey = { t: number, pos: Vector3, ease: string? }

export type Params = {
	stepTime: number, -- время одного шага (полупериод), с
	firstStep: number, -- момент первого касания (левой стопой), с
	footSpacing: number, -- половина колеи (смещение стоп от оси пути)
	lift: number, -- высота подъёма стопы в переносе
	bob: number, -- провал таза при ударе стопы (студы)
	rise: number, -- подъём таза в середине шага
	sway: number, -- боковой перенос таза к опорной ноге
	hipRoll: number, -- крен таза (градусы)
	hipYaw: number, -- поворот таза (градусы)
	lean: number, -- наклон корпуса вперёд (градусы)
	armSwing: number, -- мах рук (градусы)
	armOut: number, -- отведение рук от тела (градусы)
	elbow: number, -- базовый сгиб локтя (градусы)
	armLag: number, -- запаздывание маха рук (доля шага) — у тяжёлых и расслабленных больше
	headBob: number, -- компенсация головы (0..1)
	impact: number, -- "тяжесть" удара: резкость провала при касании (0..1)
	ankleHeight: number,
	toeOff: number, -- поворот стопы при отрыве (градусы)
	crouch: number?, -- дополнительное приседание (студы) поверх необходимого для шага
}

-- Позиция и направление на пути в момент t
function Gait.pathAt(path: { PathKey }, t: number): (Vector3, Vector3)
	local keys: { Track.Key<Vector3> } = {}
	for i, k in path do
		keys[i] = { t = k.t, v = k.pos, ease = k.ease }
	end
	local p = Track.vector(keys, t)
	local dt = 0.05
	local p2 = Track.vector(keys, t + dt)
	local p1 = Track.vector(keys, t - dt)
	local dir = p2 - p1
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1e-4 then
		-- стоим: направление по всему пути
		local a, b = path[1].pos, path[#path].pos
		dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if dir.Magnitude < 1e-4 then
			dir = Vector3.new(0, 0, -1)
		end
	end
	return p, dir.Unit
end

local function heading(dir: Vector3): CFrame
	return MathX.lookAt(Vector3.zero, dir)
end

export type Result = {
	origin: CFrame,
	pose: { [string]: CFrame },
	ik: { Rig.IKTarget },
	contact: { L: boolean, R: boolean },
}

-- Номер шага k (0, 1, 2...) и фаза внутри шага для момента t
local function stepIndex(t: number, p: Params): (number, number)
	local x = (t - p.firstStep) / p.stepTime
	local k = math.floor(x)
	return k, x - k
end

-- Точка постановки стопы для шага k (k чётный — левая, нечётный — правая)
local function plantPoint(path: { PathKey }, p: Params, k: number, lead: number): Vector3
	local tc = p.firstStep + k * p.stepTime
	local pos, dir = Gait.pathAt(path, tc)
	local side = if k % 2 == 0 then -1 else 1 -- левая на -X персонажа
	local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
	return Vector3.new(pos.X, 0, pos.Z) + right * (side * p.footSpacing) + dir * lead
end

-- Основная функция. moving(t) — 0..1 (можно плавно остановить шаги, умножается на амплитуды).
function Gait.walk(def: Rig.RigDef, path: { PathKey }, p: Params, t: number, groundY: number?): Result
	local gy = groundY or 0
	local pos, dir = Gait.pathAt(path, t)
	-- скорость (для вылета стопы вперёд) — шаг вперёд на полшага пути
	local posNext = Gait.pathAt(path, t + p.stepTime)
	local strideLen = Vector3.new(posNext.X - pos.X, 0, posNext.Z - pos.Z).Magnitude
	local moving = math.clamp(strideLen / math.max(0.05, p.stepTime) / 2, 0, 1)
	local lead = strideLen * 0.5

	local k, ph = stepIndex(t, p)
	local pose: { [string]: CFrame } = {}
	local ik: { Rig.IKTarget } = {}

	-- Таз: провал после касания (тяжесть), подъём к середине шага
	local impactCurve = math.exp(-ph * (4 + 10 * p.impact)) * math.sin(math.min(1, ph * 6) * math.pi * 0.5)
	-- ноги в покое прямые: чтобы дотянуться до стопы впереди/позади, таз опускается (колени согнуты)
	local legLen = def.lengths["UpperLeg" .. "L"] + def.lengths["LowerLeg" .. "L"]
	local reach = math.min(lead, legLen * 0.6)
	local needCrouch = legLen - math.sqrt(legLen * legLen - reach * reach) + legLen * 0.03
	local crouch = (needCrouch + (p.crouch or 0)) * math.clamp(moving * 1.5, 0, 1)
	local bobY = (-p.bob * impactCurve + p.rise * math.sin(ph * math.pi)) * moving - crouch
	-- боковой перенос к опорной ноге: k чётный — опора на левой (она только что встала)
	local supportSide = if k % 2 == 0 then -1 else 1
	local swayX = supportSide * p.sway * math.sin(ph * math.pi) * moving
	local h = heading(dir)
	local origin = CFrame.new(Vector3.new(pos.X, gy, pos.Z)) * h * CFrame.new(swayX, bobY, 0)

	-- Стопы
	local footRest = def.rest[def.index.FootL]
	local _ = footRest
	local contact = { L = false, R = false }
	for _, side in { "L", "R" } do
		local isLeft = side == "L"
		-- последний шаг этой ноги (касание) и следующий
		local myLast = if (k % 2 == 0) == isLeft then k else k - 1
		local myNext = myLast + 2
		local tLast = p.firstStep + myLast * p.stepTime
		local u = (t - tLast) / p.stepTime -- 0..2: 0..1 опора, 1..2 перенос (у этой ноги)
		local plantA = plantPoint(path, p, myLast, lead)
		local target: Vector3
		local footPitch = 0
		if t < p.firstStep - (if isLeft then 0 else p.stepTime) then
			-- до первого шага: стоим
			target = plantPoint(path, p, if isLeft then 0 else -1, 0)
			contact[side] = true
		elseif u < 1 then
			target = plantA
			contact[side] = true
			footPitch = -p.toeOff * MathX.smoothstep((u - 0.75) / 0.25) * moving
		else
			local s = MathX.ease("InOutSine", u - 1)
			local plantB = plantPoint(path, p, myNext, lead)
			target = plantA:Lerp(plantB, s) + Vector3.new(0, p.lift * math.sin(s * math.pi) * moving, 0)
			footPitch = (-p.toeOff * (1 - s) + 10 * math.sin(s * math.pi)) * moving
		end
		local ankle = target + Vector3.new(0, gy + p.ankleHeight, 0)
		local footRot = h * MathX.angles(footPitch, 0, 0)
		local hipW = origin * def.rest[def.index["UpperLeg" .. side]]
		local pole = hipW.Position + h.LookVector * 6 + Vector3.new(0, -1, 0)
		table.insert(ik, {
			upper = "UpperLeg" .. side,
			lower = "LowerLeg" .. side,
			tip = "Foot" .. side,
			target = ankle,
			pole = pole,
			tipRotation = footRot,
			hingeSign = 1,
		})
	end

	-- Корпус: крен/поворот таза к опорной ноге, противоповорот груди
	local swing = math.sin((k + ph) * math.pi) -- +1 на середине шага правой... знак чередуется
	local yawSign = if k % 2 == 0 then 1 else -1
	local phaseYaw = math.cos(ph * math.pi) * yawSign
	pose.Hips = MathX.angles(0, p.hipYaw * phaseYaw * moving, -supportSide * p.hipRoll * math.sin(ph * math.pi) * moving)
	pose.Spine = MathX.angles(-p.lean * 0.5, -p.hipYaw * 0.5 * phaseYaw * moving, supportSide * p.hipRoll * 0.4 * math.sin(ph * math.pi) * moving)
	pose.Chest = MathX.angles(-p.lean * 0.5, -p.hipYaw * 0.6 * phaseYaw * moving, 0)
	-- голова гасит качку
	pose.Neck = MathX.angles(p.lean * 0.6, p.hipYaw * 0.5 * phaseYaw * moving * p.headBob, 0)
	pose.Head = MathX.angles(p.lean * 0.3 - bobY * 6 * p.headBob, 0, -supportSide * p.hipRoll * 0.3 * math.sin(ph * math.pi) * moving * p.headBob)

	-- Руки: мах в противофазе ногам, с запаздыванием
	local lagPh = (k + ph - p.armLag)
	local armPhase = math.cos(lagPh * math.pi) -- +1 когда вперёд идёт левая рука (правая нога впереди)
	for _, side in { "L", "R" } do
		local sgn = if side == "L" then 1 else -1
		-- при касании левой (k чётный) левая нога впереди, значит вперёд идёт правая рука
		local a = -p.armSwing * armPhase * sgn * moving
		pose["UpperArm" .. side] = MathX.angles(a, 0, -sgn * p.armOut)
		pose["LowerArm" .. side] = MathX.angles(p.elbow + math.max(0, a) * 0.6, 0, 0)
		pose["Hand" .. side] = MathX.angles(0, 0, 0)
	end
	local _s = swing
	return { origin = origin, pose = pose, ik = ik, contact = contact }
end

-- Моменты касаний (для звуков шагов и пыли) на отрезке [t0, t1]
function Gait.contacts(p: Params, t0: number, t1: number): { { t: number, foot: string } }
	local out = {}
	local k = math.max(0, math.ceil((t0 - p.firstStep) / p.stepTime))
	while true do
		local tc = p.firstStep + k * p.stepTime
		if tc > t1 then
			break
		end
		table.insert(out, { t = tc, foot = if k % 2 == 0 then "L" else "R" })
		k += 1
	end
	return out
end

return Gait
