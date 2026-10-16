--!nocheck
-- Тестовые позы Рики для tools/view_model.luau (5-й аргумент): (def, origin, MathX) -> pose, ik
-- hunch* берут настоящую позу сцены (Actors.rika), чтобы проверять модель так, как её видит камера.
local Base = require(script.Parent.test_poses)
local P = {}

P.rest = Base.rest
P.walk = Base.walk
P.hands_up = Base.hands_up
P.fists = Base.fists

local function actorPose(t)
	local ok, Actors = pcall(function()
		return require(script.Parent.Parent.src.shared.Sequence.Actors)
	end)
	if ok and Actors and Actors.rika then
		return Actors.rika(t).pose
	end
	return nil
end

-- сутулая поза сцены (горилла): корпус вперёд ~30°, голова вынесена, руки висят, пальцы поджаты
function P.hunch(_def, _origin, M)
	local pose = actorPose(1.0)
	if pose then
		return pose, nil
	end
	local a = M.angles
	return {
		Spine = a(-14, 0, 0),
		Chest = a(-16, 0, 0),
		Neck = a(16, 0, 0),
		Head = a(10, 0, 0),
		UpperArmL = a(30, 10, -12),
		UpperArmR = a(30, -10, 12),
		LowerArmL = a(16, 0, 4),
		LowerArmR = a(16, 0, -4),
	}, nil
end

-- та же поза в момент «толчка» (проседание и перекат плеч) + приоткрытая пасть
function P.hunch_open(def, origin, M)
	local pose = actorPose(1.8) or P.hunch(def, origin, M)
	pose.Jaw = M.angles(-22, 0, 0)
	return pose, nil
end

-- удар правой (как в кадре с Рю): рука вперёд-вверх, кулак
function P.punch(_def, _origin, M)
	local a = M.angles
	local pose = {
		Spine = a(-10, -12, 0),
		Chest = a(-8, -18, 0),
		UpperArmR = a(95, 0, 10),
		LowerArmR = a(10, 0, 0),
		UpperArmL = a(-20, 0, -25),
		LowerArmL = a(40, 0, 0),
		Head = a(5, 10, 0),
		Jaw = a(-10, 0, 0),
	}
	for _, f in { "Index", "Middle", "Ring", "Pinky" } do
		pose[f .. "1R"] = a(0, 0, -75)
		pose[f .. "2R"] = a(0, 0, -85)
		pose[f .. "3R"] = a(0, 0, -60)
		pose[f .. "1L"] = a(0, 0, 30)
		pose[f .. "2L"] = a(0, 0, 40)
		pose[f .. "3L"] = a(0, 0, 30)
	end
	pose.Thumb1R = a(-20, 0, -40)
	pose.Thumb2R = a(0, 0, -40)
	return pose, nil
end

return P
