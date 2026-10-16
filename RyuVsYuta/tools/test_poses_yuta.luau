--!nocheck
-- Тестовые позы Юты для осмотра суставов (tools/view_model.luau Yuta out.json <поза> Head tools/test_poses_yuta)
local P = {}

function P.rest(_def, _origin, _M)
	return {}, nil
end

-- глубокий присед: колени и бёдра сильно согнуты, корпус наклонён вперёд
function P.crouch(_def, _origin, M)
	local a = M.angles
	return {
		Root = CFrame.new(0, -0.9, 0),
		Spine = a(-18, 0, 0),
		Chest = a(-10, 0, 0),
		Head = a(20, 0, 0),
		UpperLegL = a(95, 0, -6),
		LowerLegL = a(-115, 0, 0),
		FootL = a(20, 0, 0),
		UpperLegR = a(80, 0, 8),
		LowerLegR = a(-120, 0, 0),
		FootR = a(40, 0, 0),
		UpperArmL = a(40, 0, -10),
		LowerArmL = a(60, 0, 0),
		UpperArmR = a(40, 0, 10),
		LowerArmR = a(60, 0, 0),
	}, nil
end

-- руки в стороны (плечо 90°) и локти согнуты на 120° — проверка плеча и локтя
function P.arms(_def, _origin, M)
	local a = M.angles
	local pose = {
		UpperArmL = a(0, 0, -90),
		LowerArmL = a(0, 0, 0) * a(0, -90, 0) * a(120, 0, 0),
		UpperArmR = a(70, 0, 20),
		LowerArmR = a(120, 0, 0),
		HandR = a(0, 0, -30),
		Head = a(-10, 25, 8),
		Neck = a(-5, 10, 0),
		Chest = a(0, -15, 0),
	}
	for _, f in { "Index", "Middle", "Ring", "Pinky" } do
		pose[f .. "1R"] = a(0, 0, -70)
		pose[f .. "2R"] = a(0, 0, -80)
		pose[f .. "3R"] = a(0, 0, -60)
	end
	pose.Thumb1R = a(-20, 0, -30)
	pose.Thumb2R = a(0, 0, -40)
	return pose, nil
end

-- спокойный шаг Юты: ссутуленные плечи, руки свободно, голова чуть вправо от камеры (влево у него)
function P.calm(_def, _origin, M)
	local a = M.angles
	return {
		UpperLegL = a(18, 0, 0),
		LowerLegL = a(-8, 0, 0),
		UpperLegR = a(-12, 0, 0),
		LowerLegR = a(-22, 0, 0),
		FootR = a(10, 0, 0),
		Spine = a(4, 3, 0),
		Chest = a(6, 3, 0),
		ClavicleL = a(0, 0, -4),
		ClavicleR = a(0, 0, 4),
		UpperArmL = a(-10, 0, -3),
		LowerArmL = a(14, 0, 0),
		UpperArmR = a(12, 0, 3),
		LowerArmR = a(16, 0, 0),
		Neck = a(-6, 0, 0),
		Head = a(-4, 12, 0),
	}, nil
end

-- на носках: пятки подняты, пальцы стоп согнуты, кисти — кулаки с опорой (проверка Toe и пальцев)
function P.tiptoe(_def, _origin, M)
	local a = M.angles
	local pose = {
		Root = CFrame.new(0, 0.18, 0),
		FootL = a(-35, 0, 0),
		ToeL = a(35, 0, 0),
		FootR = a(-35, 0, 0),
		ToeR = a(35, 0, 0),
		UpperArmL = a(25, 0, -15),
		LowerArmL = a(90, 0, 0),
		HandL = a(0, 0, 20),
	}
	for _, f in { "Index", "Middle", "Ring", "Pinky" } do
		pose[f .. "1L"] = a(0, 0, 75)
		pose[f .. "2L"] = a(0, 0, 85)
		pose[f .. "3L"] = a(0, 0, 60)
	end
	pose.Thumb1L = a(-20, 0, 30)
	pose.Thumb2L = a(0, 0, 40)
	return pose, nil
end

return P
