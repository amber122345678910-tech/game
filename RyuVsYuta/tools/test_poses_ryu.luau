--!nocheck
-- Тестовые позы Рю (жесты из клипа) для tools/view_model.luau:
--   lune run tools/view_model.luau Ryu out.json bowed HandR tools/test_poses_ryu
-- Каждая: (def, origin, MathX) -> pose, ik. Цели IK считаются от уже повёрнутой головы/помпадура.
local Rig = require(script.Parent.Parent.src.shared.Rig)

local P = {}

local FINGERS = { "Index", "Middle", "Ring", "Pinky" }
local SPREAD = { Index = 1, Middle = 0.35, Ring = -0.35, Pinky = -1 }

-- Поворот кисти в мире: пальцы вдоль fingerDir, ладонь смотрит по palmN.
-- В осях кисти пальцы — это -Y, ладонь правой — -X, левой — +X.
local function handRot(fingerDir, palmN, side)
	local s = if side == "R" then 1 else -1
	local y = -fingerDir.Unit
	local x = -palmN.Unit * s
	x = (x - y * x:Dot(y)).Unit
	local z = x:Cross(y)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- Пальцы: curl — сгиб (градусы на фалангу), spread — веер (градусы между крайними пальцами)
local function fingers(pose, M, side, curl1, curl2, curl3, spread, thumbCurl)
	local c = if side == "L" then 1 else -1 -- к ладони
	for _, f in FINGERS do
		local sp = SPREAD[f] * spread
		pose[f .. "1" .. side] = M.angles(sp, 0, curl1 * c)
		pose[f .. "2" .. side] = M.angles(0, 0, curl2 * c)
		pose[f .. "3" .. side] = M.angles(0, 0, curl3 * c)
	end
	pose["Thumb1" .. side] = M.angles(10, 0, (thumbCurl or 20) * c)
	pose["Thumb2" .. side] = M.angles(0, 0, (thumbCurl or 20) * 0.6 * c)
	pose["Thumb3" .. side] = M.angles(0, 0, (thumbCurl or 20) * 0.5 * c)
end

local function stanceLegs(pose, M, deg)
	pose.UpperLegL = M.angles(0, 0, -deg)
	pose.UpperLegR = M.angles(0, 0, deg)
	pose.FootL = M.angles(0, 0, deg)
	pose.FootR = M.angles(0, 0, -deg)
end

-- Мировой CFrame кости при позе без IK рук
local function boneAt(def, origin, pose, name)
	local w = Rig.solve(def, origin, pose, nil)
	return Rig.boneWorld(def, w, name)
end

-- Цели IK обеих рук от CFrame опорной кости: wrist/fingers/palm/pole заданы в её осях для правой руки (+X)
local function armsTo(ref, wrist, fdir, palm, pole, sh)
	local ik = {}
	for _, side in { "R", "L" } do
		local s = if side == "R" then 1 else -1
		local function m(v)
			return Vector3.new(v.X * s, v.Y, v.Z)
		end
		table.insert(ik, {
			upper = "UpperArm" .. side,
			lower = "LowerArm" .. side,
			tip = "Hand" .. side,
			target = ref:PointToWorldSpace(m(wrist)),
			pole = (sh or ref):PointToWorldSpace(m(pole)),
			tipRotation = handRot(ref:VectorToWorldSpace(m(fdir)), ref:VectorToWorldSpace(m(palm)), side),
		})
	end
	return ik
end

-- Кадр B, начало: стойка ноги врозь, руки держат лацканы у груди, локти в стороны
function P.lapels(def, origin, M)
	local pose = { Chest = M.angles(4, 0, 0), Head = M.angles(-4, 0, 0) }
	stanceLegs(pose, M, 9)
	fingers(pose, M, "R", 70, 80, 50, 4, 40)
	fingers(pose, M, "L", 70, 80, 50, 4, 40)
	local ch = boneAt(def, origin, pose, "Chest")
	return pose, armsTo(ch, Vector3.new(0.34, 0.02, -0.66), Vector3.new(-0.25, 0.9, 0.1), Vector3.new(-0.3, 0, 1), Vector3.new(3, -0.6, 0.8))
end

-- Кадр C 5.23-5.73: голова низко опущена (~60°), ладони на боках помпадура посередине, пальцы веером
function P.bowed(def, origin, M)
	local pose = { Spine = M.angles(-6, 0, 0), Chest = M.angles(-8, 0, 0), Neck = M.angles(-22, 0, 0), Head = M.angles(-36, 0, 0) }
	fingers(pose, M, "R", 18, 22, 14, 22, 10)
	fingers(pose, M, "L", 18, 22, 14, 22, 10)
	local pp = boneAt(def, origin, pose, "Pompadour")
	local ch = boneAt(def, origin, pose, "Chest")
	return pose, armsTo(pp, Vector3.new(0.5, -0.08, 0.32), Vector3.new(-0.32, 0.3, -1), Vector3.new(-1, -0.25, 0), Vector3.new(3.2, 0.6, 0.6), ch)
end

-- Кадр C 5.77-6.03: голова поднимается, пальцы «когтями» по передней части помпадура, большие пальцы у висков
function P.rake(def, origin, M)
	local pose = { Chest = M.angles(4, 0, 0), Neck = M.angles(4, 0, 0), Head = M.angles(8, 0, 0) }
	fingers(pose, M, "R", 30, 40, 30, 26, 5)
	fingers(pose, M, "L", 30, 40, 30, 26, 5)
	local hd = boneAt(def, origin, pose, "Head")
	local ch = boneAt(def, origin, pose, "Chest")
	return pose, armsTo(hd, Vector3.new(0.44, 0.5, -0.02), Vector3.new(-0.35, 0.85, -0.55), Vector3.new(-1, -0.35, -0.2), Vector3.new(3, 1.2, 0.4), ch)
end

-- Кадр C 6.3-7.15: голова запрокинута, ладони на макушке/затылке, предплечья вертикально у головы, локти высоко
function P.hold(def, origin, M)
	local pose = { Chest = M.angles(6, 0, 0), Neck = M.angles(8, 0, 0), Head = M.angles(14, 0, 0) }
	fingers(pose, M, "R", 35, 45, 30, 16, 15)
	fingers(pose, M, "L", 35, 45, 30, 16, 15)
	local hd = boneAt(def, origin, pose, "Head")
	local ch = boneAt(def, origin, pose, "Chest")
	return pose, armsTo(hd, Vector3.new(0.4, 0.62, 0.22), Vector3.new(-0.55, 0.75, 0.35), Vector3.new(-1, -0.2, 0.25), Vector3.new(2.5, 2.4, 0.6), ch)
end

-- Широкий план B: стойка ноги врозь (A-стойка), руки опущены
function P.stance(_def, _origin, M)
	local pose = { UpperArmL = M.angles(0, 0, -6), UpperArmR = M.angles(0, 0, 6), LowerArmL = M.angles(12, 0, 0), LowerArmR = M.angles(12, 0, 0) }
	stanceLegs(pose, M, 9)
	fingers(pose, M, "R", 15, 25, 15, 6, 10)
	fingers(pose, M, "L", 15, 25, 15, 6, 10)
	return pose, nil
end

-- Проверка сгибов: глубокий присед, локти и кисти согнуты
function P.bend(_def, _origin, M)
	local pose = {
		UpperLegL = M.angles(70, 0, -6),
		LowerLegL = M.angles(-110, 0, 0),
		FootL = M.angles(30, 0, 0),
		UpperLegR = M.angles(40, 0, 6),
		LowerLegR = M.angles(-80, 0, 0),
		ToeR = M.angles(-30, 0, 0),
		Spine = M.angles(-15, 0, 0),
		Chest = M.angles(-10, 10, 0),
		UpperArmL = M.angles(60, 0, -40),
		LowerArmL = M.angles(110, 0, 0),
		HandL = M.angles(0, 0, 40),
		UpperArmR = M.angles(-30, 0, 70),
		LowerArmR = M.angles(90, 0, 0),
		HandR = M.angles(-30, 0, 0),
		Neck = M.angles(-15, 20, 0),
		Head = M.angles(-10, 15, 0),
	}
	fingers(pose, M, "R", 70, 85, 60, 0, 45)
	fingers(pose, M, "L", 40, 50, 30, 20, 20)
	return pose, nil
end

return P
