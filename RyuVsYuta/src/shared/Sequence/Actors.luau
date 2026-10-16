--!strict
-- Игра персонажей как функция времени (без привязки к кадрам: кадр лишь решает, кого видно).

local Shared = script.Parent.Parent
local MathX = require(Shared.Math)
local Rig = require(Shared.Rig)
local Track = require(Shared.Track)
local Skeletons = require(Shared.Skeletons)
local Gait = require(Shared.Anim.Gait)
local Types = require(script.Parent.Types)
local Timing = require(script.Parent.Timing)
local Layout = require(script.Parent.Layout)

local Actors = {}

local A = MathX.angles
local T = Timing

------------------------------------------------------------------------------------------
-- Общие слои
------------------------------------------------------------------------------------------

-- Дыхание: грудь и плечи чуть поднимаются, голова слегка покачивается
local function breathe(pose: { [string]: CFrame }, t: number, rate: number, depth: number)
	local b = math.sin(t * rate * 2 * math.pi)
	local function mul(name: string, cf: CFrame)
		local base = pose[name]
		pose[name] = if base then base * cf else cf
	end
	mul("Chest", A(-depth * b, 0, 0))
	mul("ClavicleL", A(0, 0, depth * 0.8 * b))
	mul("ClavicleR", A(0, 0, -depth * 0.8 * b))
	mul("Neck", A(depth * 0.6 * b, 0, 0))
end

local function mulPose(pose: { [string]: CFrame }, name: string, cf: CFrame)
	local base = pose[name]
	pose[name] = if base then base * cf else cf
end

-- Пальцы: curl 0..1 (сжатие к ладони), spread — веер в градусах
local function fingers(pose: { [string]: CFrame }, side: string, curl: number, spread: number, thumb: number?)
	local sgn = if side == "L" then 1 else -1
	local fan: { [string]: number } = { Index = 1, Middle = 0.3, Ring = -0.4, Pinky = -1 }
	for f, k in fan do
		mulPose(pose, f .. "1" .. side, A(spread * k, 0, 55 * curl * sgn))
		mulPose(pose, f .. "2" .. side, A(0, 0, 70 * curl * sgn))
		mulPose(pose, f .. "3" .. side, A(0, 0, 50 * curl * sgn))
	end
	local th = thumb or curl
	mulPose(pose, "Thumb1" .. side, A(-10 * th, 0, 25 * th * sgn))
	mulPose(pose, "Thumb2" .. side, A(0, 0, 30 * th * sgn))
	mulPose(pose, "Thumb3" .. side, A(0, 0, 25 * th * sgn))
end

------------------------------------------------------------------------------------------
-- Рика: ног нет (ниже пояса — чёрная дымная масса-хвост), она плывёт над землёй,
-- сутулая, как горилла, руки висят перед телом. Тяжёлые "толчки": тело проседает, плечи перекатываются.
------------------------------------------------------------------------------------------

local rikaPath: { Track.Key<Vector3> } = {
	{ t = 0, v = Layout.rikaFrom },
	{ t = T.walkEnd, v = Layout.rikaTo, ease = "Linear" },
	{ t = T.walkEnd + 10, v = Layout.rikaTo + (Layout.rikaTo - Layout.rikaFrom) * (10 / T.walkEnd), ease = "Linear" },
}

-- Фаза толчка: 0 в момент удара, растёт до 1 к следующему
local function pulsePhase(t: number): (number, number)
	local x = (t - T.rikaFirstPulse) / T.rikaPulse
	local k = math.floor(x)
	return k, x - k
end

-- Моменты толчков (для звука и пыли)
function Actors.rikaPulses(t0: number, t1: number): { { t: number, side: string } }
	local out = {}
	local k = math.max(0, math.ceil((t0 - T.rikaFirstPulse) / T.rikaPulse))
	while true do
		local tc = T.rikaFirstPulse + k * T.rikaPulse
		if tc > t1 then
			break
		end
		table.insert(out, { t = tc, side = if k % 2 == 0 then "L" else "R" })
		k += 1
	end
	return out
end

-- Сутулая поза Рики (общая для сцены и меню). sway — -1..1 перекат на сторону.
local function rikaHunch(pose: { [string]: CFrame }, t: number, drop: number, sway: number)
	mulPose(pose, "Hips", CFrame.new(0, -drop, 0) * A(-4, 3 * sway, 2 * sway))
	mulPose(pose, "Spine", A(-14 - 3 * drop, -2 * sway, -2 * sway))
	mulPose(pose, "Chest", A(-16 - 4 * drop, -3 * sway, -1.5 * sway))
	-- голова вынесена вперёд-вниз, но маска смотрит вперёд (исподлобья)
	mulPose(pose, "Neck", A(16, 0, 0))
	mulPose(pose, "Head", A(10 + 2 * math.sin(t * 0.37), 4 * math.sin(t * 0.21), 2 * math.sin(t * 0.29)))
	mulPose(pose, "Jaw", A(1 + math.sin(t * 0.7), 0, 0))
	-- плечи вздёрнуты, перекатываются
	mulPose(pose, "ClavicleL", A(0, 0, -6 + 4 * sway))
	mulPose(pose, "ClavicleR", A(0, 0, 6 + 4 * sway))
	-- руки висят вертикально (компенсируем наклон корпуса), чуть выгнуты наружу, локти согнуты
	local swing = 4 * sway
	mulPose(pose, "UpperArmL", A(30 + swing, 10, -12))
	mulPose(pose, "UpperArmR", A(30 - swing, -10, 12))
	mulPose(pose, "LowerArmL", A(16 + 3 * drop, 0, 4))
	mulPose(pose, "LowerArmR", A(16 + 3 * drop, 0, -4))
	mulPose(pose, "HandL", A(10, 0, -6))
	mulPose(pose, "HandR", A(10, 0, 6))
	fingers(pose, "L", 0.42 + 0.06 * math.sin(t * 0.9), 8, 0.3)
	fingers(pose, "R", 0.45 + 0.06 * math.sin(t * 0.8 + 1), 8, 0.3)
	-- "ноги" внутри массы чуть подогнуты
	mulPose(pose, "UpperLegL", A(18, 0, -4))
	mulPose(pose, "UpperLegR", A(14, 0, 4))
	mulPose(pose, "LowerLegL", A(-30, 0, 0))
	mulPose(pose, "LowerLegR", A(-26, 0, 0))
	breathe(pose, t, 0.2, 2.2)
end

local function rikaHair(dirBack: Vector3, bloom: number): Types.HairState
	return {
		wind = dirBack * (0.6 + 0.6 * bloom) + Vector3.new(0.35, 0, 0),
		lift = Vector3.new(0, 0.5 + 1.3 * bloom, 0) + dirBack * (0.2 + 0.4 * bloom),
		turbulence = 0.45 + 0.35 * bloom,
		freq = 0.55,
		scale = 0.35,
	}
end

function Actors.rika(t: number): Types.CharState
	local pos = Track.vector(rikaPath, t)
	local dir = Vector3.new(0, 0, -1)
	local k, ph = pulsePhase(t)
	-- удар: резкое проседание и медленный подъём
	local drop = 0.16 * math.exp(-ph * 5) * math.sin(math.min(1, ph * 8) * math.pi * 0.5) + 0.05 * math.sin(ph * math.pi * 2)
	local sway = (if k % 2 == 0 then 1 else -1) * math.sin(math.min(1, ph * 1.2) * math.pi)
	local pose: { [string]: CFrame } = {}
	rikaHunch(pose, t, drop, sway)
	local bloom = MathX.smoothstep(MathX.progress(t, T.maneBloom - 1.2, T.maneBloom + 1.6))
	local origin = CFrame.new(pos) * MathX.lookAt(Vector3.zero, dir) * CFrame.new(0, 0.35 + 0.08 * math.sin(t * 0.9), 0)
	return {
		visible = true,
		origin = origin,
		pose = pose,
		ik = nil,
		outline = 1,
		flutter = 1,
		hair = rikaHair(-origin.LookVector, bloom),
	}
end

-- Рика для фона стартового меню (стоит на месте, дышит, грива колышется)
function Actors.rikaIdle(clock: number, at: CFrame): Types.CharState
	local pose: { [string]: CFrame } = {}
	rikaHunch(pose, clock, 0.04 * math.sin(clock * 0.8), 0.35 * math.sin(clock * 0.25))
	return {
		visible = true,
		origin = at * CFrame.new(0, 0.35 + 0.1 * math.sin(clock * 0.7), 0),
		pose = pose,
		ik = nil,
		outline = 1,
		flutter = 1,
		hair = rikaHair(-at.LookVector, 1),
	}
end

------------------------------------------------------------------------------------------
-- Юта
------------------------------------------------------------------------------------------

local YutaP = Skeletons.YutaProportions
local yutaGait: Gait.Params = {
	stepTime = T.yutaStepTime,
	firstStep = T.yutaFirstStep,
	footSpacing = 0.3,
	lift = 0.22,
	bob = 0.06,
	rise = 0.05,
	sway = 0.05,
	hipRoll = 3,
	hipYaw = 6,
	lean = 2,
	armSwing = 7,
	armOut = 5,
	elbow = 12,
	armLag = 0.12,
	headBob = 0.8,
	impact = 0.15,
	ankleHeight = YutaP.ankleHeight,
	toeOff = 12,
	crouch = 0.03,
}
local yutaPath: { Gait.PathKey } = {
	{ t = 0, pos = Layout.yutaFrom },
	{ t = T.walkEnd, pos = Layout.yutaTo, ease = "Linear" },
	{ t = T.walkEnd + 10, pos = Layout.yutaTo + (Layout.yutaTo - Layout.yutaFrom) * (10 / T.walkEnd), ease = "Linear" },
}
Actors.yutaGait = yutaGait

function Actors.yuta(t: number): Types.CharState
	local def = Skeletons.Yuta
	local g = Gait.walk(def, yutaPath, yutaGait, t)
	local pose = g.pose
	-- спокойный, собранный: голова прямо, взгляд вперёд (на Рю вдалеке), руки расслаблены
	mulPose(pose, "Head", A(1 + 1.2 * math.sin(t * 0.4), -2, 0))
	fingers(pose, "L", 0.3, 2, 0.15)
	fingers(pose, "R", 0.28, 2, 0.15)
	breathe(pose, t, 0.3, 0.8)
	local back = g.origin.LookVector * -1
	return {
		visible = true,
		origin = g.origin,
		pose = pose,
		ik = g.ik,
		outline = 1,
		flutter = 0.6,
		hair = {
			wind = back * 0.25 + Vector3.new(0.1, 0, 0),
			lift = Vector3.new(0, 0.05, 0),
			turbulence = 0.12,
			freq = 0.9,
			scale = 0.8,
		},
	}
end

function Actors.yutaIdle(clock: number, at: CFrame): Types.CharState
	local pose: { [string]: CFrame } = {}
	mulPose(pose, "Head", A(1 + math.sin(clock * 0.3), -4 + 3 * math.sin(clock * 0.15), 0))
	mulPose(pose, "UpperArmL", A(2, 0, -4))
	mulPose(pose, "LowerArmL", A(8, 0, 0))
	mulPose(pose, "UpperArmR", A(2, 0, 4))
	mulPose(pose, "LowerArmR", A(8, 0, 0))
	fingers(pose, "L", 0.3, 2, 0.15)
	fingers(pose, "R", 0.25, 2, 0.15)
	breathe(pose, clock, 0.28, 1)
	return {
		visible = true,
		origin = at,
		pose = pose,
		ik = nil,
		outline = 1,
		flutter = 0.6,
		hair = {
			wind = at.LookVector * -0.2,
			lift = Vector3.new(0, 0.05, 0),
			turbulence = 0.12,
			freq = 0.9,
			scale = 0.8,
		},
	}
end

------------------------------------------------------------------------------------------
-- Рю (покадрово по ролику): B — широкая стойка, руки от отворотов вверх по воротнику, ко лбу, на затылок;
-- C — голова низко опущена (помпадур смотрит в объектив), ладони ведут волосы от кончика к макушке,
-- кончик загорается, на вспышке голова вскидывается назад, пальцы граблями по лбу, ухмылка; потом пауза.
------------------------------------------------------------------------------------------

local RyuP = Skeletons.RyuProportions
local ryuOrigin = CFrame.new(Layout.ryuSpot) * Layout.ryuFacing

Actors.ryuOrigin = ryuOrigin

-- Корпус и голова (градусы; x > 0 — откинуться назад / поднять лицо)
local ryuBody: { Track.Key<Track.PoseValue> } = {
	{ t = T.bStart, v = { Hips = { 0, 0, 0, 0, -0.1, 0 }, Spine = { 2, 0, 0 }, Chest = { 4, 0, 0 }, Neck = { -3, 0, 0 }, Head = { -4, 0, 0 } } },
	{ t = T.armsUp, v = { Hips = { 0, 0, 0, 0, -0.1, 0 }, Spine = { 2, 0, 0 }, Chest = { 5, 0, 0 }, Neck = { -3, 0, 0 }, Head = { -6, 0, 0 } } },
	{ t = T.handsOnHair, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { 3, 0, 0 }, Chest = { 8, 0, 0 }, Neck = { -8, 0, 0 }, Head = { -14, 0, 0 } } },
	{ t = T.bEnd, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { 3, 0, 0 }, Chest = { 8, 0, 0 }, Neck = { -9, 0, 0 }, Head = { -16, 0, 0 } }, ease = "InOutSine" },
	-- C: голова резко опущена — помпадур "дулом" в объектив
	{ t = T.cStart, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { -4, 0, 0 }, Chest = { -8, 0, 0 }, Neck = { -22, 0, 0 }, Head = { -28, 0, 0 } }, ease = "Constant" },
	{ t = T.slickEnd, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { -4, 0, 0 }, Chest = { -9, 0, 0 }, Neck = { -24, 0, 0 }, Head = { -30, 1, 0 } }, ease = "InOutSine" },
	{ t = T.liftStart, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { -4, 0, 0 }, Chest = { -9, 0, 0 }, Neck = { -23, 0, 0 }, Head = { -29, 1, 0 } } },
	-- вспышка: голова вскидывается и запрокидывается
	{ t = T.headUp, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { 4, 0, 0 }, Chest = { 10, 0, 0 }, Neck = { 12, 0, 0 }, Head = { 15, -2, -2 } }, ease = "OutCubic" },
	{ t = T.settle, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { 4, 0, 0 }, Chest = { 10, 0, 0 }, Neck = { 11, 0, 0 }, Head = { 13, -2, -2 } } },
	{ t = T.cEnd, v = { Hips = { 0, 0, 0, 0, -0.12, 0 }, Spine = { 4, 0, 0 }, Chest = { 9, 0, 0 }, Neck = { 10, 0, 0 }, Head = { 12, -3, -2 } } },
}

-- Цели левой кисти. frame = 0 — в осях груди, 1 — в осях головы (x — вправо от Рю, y — вверх, -z — вперёд).
type HandKey = { t: number, v: Vector3, ease: string? }
local handL: { HandKey } = {
	{ t = T.bStart, v = Vector3.new(-0.42, 0.42, -0.62) }, -- держит отворот у грудины (оси груди)
	{ t = T.armsUp, v = Vector3.new(-0.45, 0.48, -0.64) },
	{ t = T.armsUp + 0.4, v = Vector3.new(-0.36, -0.7, -0.5), ease = "InOutSine" }, -- по воротнику к подбородку (оси головы)
	{ t = T.armsUp + 0.8, v = Vector3.new(-0.62, 0.45, -0.62), ease = "InOutSine" }, -- на уровне лба, локти выше плеч
	{ t = T.handsOnHair, v = Vector3.new(-0.58, 0.9, 0.05), ease = "OutBack" }, -- щелчок: на помпадуре
	{ t = T.bEnd, v = Vector3.new(-0.58, 0.88, 0.15), ease = "InOutSine" },
	-- C: ладони входят с боков на середину помпадура и ведут к макушке
	{ t = T.cStart, v = Vector3.new(-0.64, 0.66, -0.72), ease = "Constant" },
	{ t = T.slickEnd, v = Vector3.new(-0.58, 0.82, 0.02), ease = "InOutSine" },
	{ t = T.liftStart, v = Vector3.new(-0.55, 0.78, -0.12) },
	-- вспышка: пальцы граблями по передней части помпадура и линии волос
	{ t = T.zing + 0.3, v = Vector3.new(-0.5, 0.55, -0.55), ease = "OutCubic" },
	-- щелчок в финальную позу: ладони на макушке и затылке, предплечья вертикально
	{ t = T.settle, v = Vector3.new(-0.42, 0.98, 0.32), ease = "OutBack" },
	{ t = T.cEnd, v = Vector3.new(-0.42, 0.98, 0.36) },
}
-- куда смотрят пальцы (в осях груди/головы)
local fingerDirL: { HandKey } = {
	{ t = T.bStart, v = Vector3.new(0.25, -1, -0.35) },
	{ t = T.armsUp, v = Vector3.new(0.25, -1, -0.35) },
	{ t = T.armsUp + 0.4, v = Vector3.new(0.2, 1, -0.2), ease = "InOutSine" },
	{ t = T.handsOnHair, v = Vector3.new(0.3, 0.35, 1), ease = "InOutSine" },
	{ t = T.bEnd, v = Vector3.new(0.3, 0.3, 1), ease = "InOutSine" },
	{ t = T.cStart, v = Vector3.new(0.35, 0.2, 1), ease = "Constant" },
	{ t = T.slickEnd, v = Vector3.new(0.35, 0.4, 1), ease = "InOutSine" },
	{ t = T.liftStart, v = Vector3.new(0.35, 0.4, 1) },
	{ t = T.zing + 0.3, v = Vector3.new(0.3, 0.9, 0.5), ease = "OutCubic" },
	{ t = T.settle, v = Vector3.new(0.5, 0.2, 1), ease = "OutBack" },
	{ t = T.cEnd, v = Vector3.new(0.5, 0.2, 1) },
}

local function sampleHand(keys: { HandKey }, t: number, mirror: boolean): Vector3
	local tk: { Track.Key<Vector3> } = {}
	for i, k in keys do
		tk[i] = { t = k.t, v = if mirror then Vector3.new(-k.v.X, k.v.Y, k.v.Z) else k.v, ease = k.ease }
	end
	return Track.vector(tk, t)
end

-- Ориентация кисти: ось X кисти — вправо (как у головы/груди), -Y — куда смотрят пальцы
local function handRot(frameRot: CFrame, fingerDir: Vector3): CFrame
	local f = frameRot:VectorToWorldSpace(fingerDir.Unit)
	local xAxis = frameRot:VectorToWorldSpace(Vector3.new(1, 0, 0))
	local y = -f
	local z = xAxis:Cross(y)
	if z.Magnitude < 1e-3 then
		z = frameRot:VectorToWorldSpace(Vector3.new(0, 0, 1))
	end
	z = z.Unit
	local x = y:Cross(z).Unit
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

function Actors.ryu(t: number): Types.CharState
	local def = Skeletons.Ryu
	local pose = Track.pose(ryuBody, t)
	breathe(pose, t, 0.25, 1.1)
	-- ноги: стойка шире плеч, носки чуть врозь, стопы на месте
	local ik: { Rig.IKTarget } = {}
	for _, side in { "L", "R" } do
		local sx = if side == "L" then -1 else 1
		local foot = ryuOrigin * CFrame.new(sx * 1.0, RyuP.ankleHeight, -0.05)
		local hip = ryuOrigin * def.rest[def.index["UpperLeg" .. side]]
		table.insert(ik, {
			upper = "UpperLeg" .. side,
			lower = "LowerLeg" .. side,
			tip = "Foot" .. side,
			target = foot.Position,
			pole = hip.Position + ryuOrigin.LookVector * 6 + ryuOrigin.RightVector * (sx * 2),
			tipRotation = ryuOrigin * CFrame.Angles(0, -sx * math.rad(12), 0),
			hingeSign = 1,
		})
	end
	-- предварительное решение — где голова и грудь
	local pre = Rig.solve(def, ryuOrigin, pose, ik)
	local head = pre[def.index.Head]
	local chest = pre[def.index.Chest]
	local headRot = head - head.Position
	local chestRot = chest - chest.Position
	local toHead = MathX.smoothstep(MathX.progress(t, T.armsUp + 0.05, T.armsUp + 0.35))
	local onHair = MathX.progress(t, T.armsUp + 0.6, T.handsOnHair)
	for _, side in { "L", "R" } do
		local mirror = side == "R"
		local sx = if side == "L" then -1 else 1
		local lv = sampleHand(handL, t, mirror)
		local target = chest:PointToWorldSpace(lv):Lerp(head:PointToWorldSpace(lv), toHead)
		local fd = sampleHand(fingerDirL, t, mirror)
		local rot = handRot(chestRot:Lerp(headRot, toHead), fd)
		-- локти: у отворотов — в стороны и вниз, у головы — высоко и широко
		local poleLow = chest:PointToWorldSpace(Vector3.new(sx * 3, -1.2, 0.8))
		local poleHigh = head:PointToWorldSpace(Vector3.new(sx * 3.2, 1.2, 0.6))
		local pole = poleLow:Lerp(poleHigh, toHead)
		table.insert(ik, {
			upper = "UpperArm" .. side,
			lower = "LowerArm" .. side,
			tip = "Hand" .. side,
			target = target,
			pole = pole,
			tipRotation = rot,
			hingeSign = -1,
		})
		-- пальцы: на отвороте сжаты, по пути вверх раскрываются, на волосах растопырены и цепкие
		local grip = MathX.lerp(0.85, 0.3, toHead)
		local rake = MathX.window(t, T.zing, T.settle + 0.2, 0.15, 0.5)
		local spread = MathX.lerp(2, 12, toHead) + 8 * rake
		fingers(pose, side, grip + 0.2 * rake, spread, MathX.lerp(0.7, 0.2, toHead))
	end
	local _ = onHair
	-- помпадур приминается ладонями и пружинит после вспышки
	local press = MathX.window(t, T.handsOnHair - 0.3, T.zing + 0.15, 0.5, 0.15)
	local spring = MathX.window(t, T.zing, T.zing + 1.3, 0.02, 1.2) * math.sin((t - T.zing) * 17)
	mulPose(pose, "Pompadour", CFrame.new(0, -0.05 * press, 0.07 * press) * A(-7 * press + 3 * spring, 0, 0))
	return {
		visible = true,
		origin = ryuOrigin,
		pose = pose,
		ik = ik,
		outline = 1,
		flutter = 1,
		hair = {
			-- ветер наверху сильный: мех воротника и манжет треплет
			wind = Vector3.new(-0.7, 0.05, -0.5),
			lift = Vector3.new(0, 0.1, 0),
			turbulence = 0.3,
			freq = 1.7,
			scale = 1.2,
		},
	}
end

-- Модели при сборке стоят там, где начинают сцену
function Actors.buildOrigin(name: string): CFrame
	if name == "Rika" then
		return CFrame.new(Layout.rikaFrom)
	elseif name == "Yuta" then
		return CFrame.new(Layout.yutaFrom)
	end
	return ryuOrigin
end

return Actors
