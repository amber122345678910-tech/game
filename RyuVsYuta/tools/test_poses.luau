--!nocheck
-- Тестовые позы для осмотра моделей (tools/view_model.luau). Каждая: (def, origin, MathX) -> pose, ik
local P = {}

function P.rest(_def, _origin, _M)
	return {}, nil
end

-- шаг: левая нога вперёд, правая рука вперёд, лёгкий наклон корпуса
function P.walk(_def, _origin, M)
	local a = M.angles
	return {
		UpperLegL = a(28, 0, 0),
		LowerLegL = a(-12, 0, 0),
		UpperLegR = a(-18, 0, 0),
		LowerLegR = a(-35, 0, 0),
		FootR = a(15, 0, 0),
		Spine = a(-6, 4, 0),
		Chest = a(-4, 4, 0),
		UpperArmL = a(-22, 0, -6),
		LowerArmL = a(10, 0, 0),
		UpperArmR = a(26, 0, 6),
		LowerArmR = a(25, 0, 0),
		Head = a(4, -6, 0),
	}, nil
end

-- руки к голове через IK (как Рю приглаживает помпадур)
function P.hands_up(def, origin, M)
	local Rig = nil
	local head = origin * def.rest[def.index.Head]
	local hp = head.Position
	local up = Vector3 and Vector3.new or nil
	local V = (head.Position - head.Position) -- нулевой вектор нужного типа
	local function vec(x, y, z)
		return hp + (head.RightVector * x) + (head.UpVector * y) + (head.LookVector * z)
	end
	local s = def.lengths.UpperArmL or 1
	return {
		Chest = M.angles(6, 0, 0),
		Head = M.angles(10, 0, 0),
	}, {
		{ upper = "UpperArmL", lower = "LowerArmL", tip = "HandL", target = vec(-s * 0.55, s * 0.55, s * 0.1), pole = vec(-s * 2.5, s * 0.6, -s * 0.5) },
		{ upper = "UpperArmR", lower = "LowerArmR", tip = "HandR", target = vec(s * 0.55, s * 0.55, s * 0.1), pole = vec(s * 2.5, s * 0.6, -s * 0.5) },
	}
end

-- кулак/растопыренные пальцы
function P.fists(_def, _origin, M)
	local pose = {}
	for _, side in { "L", "R" } do
		local sgn = if side == "L" then 1 else -1
		for _, f in { "Index", "Middle", "Ring", "Pinky" } do
			pose[f .. "1" .. side] = M.angles(0, 0, 70 * sgn)
			pose[f .. "2" .. side] = M.angles(0, 0, 80 * sgn)
			pose[f .. "3" .. side] = M.angles(0, 0, 60 * sgn)
		end
		pose["UpperArm" .. side] = M.angles(0, 0, -25 * sgn)
	end
	return pose, nil
end

return P
