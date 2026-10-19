--!nocheck
-- ЗАФИКСИРОВАННЫЙ скелет Конь-Аурафармера. Аниматоры ставят IK-цели в этих координатах,
-- поэтому пропорции здесь менять НЕЛЬЗЯ (геометрию строит Horse.luau вокруг этого скелета).
-- Рост ~7 студов с ушами. char space: начало на земле между стопами, -Z — вперёд.
local Rig = require("../lib/Rig")

local S = {}

S.PROPORTIONS = {
	hipX = 0.55,
	hipY = 2.6,
	kneeY = 1.36,
	ankleY = 0.3,
	footLen = 1.2,
	footFwd = 0.8,
	footW = 0.85,
	pelvisY = 2.85,
	waistY = 3.1,
	neckY = 4.95,
	shoulderX = 1.38,
	shoulderY = 4.68,
	upperArm = 1.28,
	lowerArm = 1.18,
	handLen = 0.5,
	handW = 0.62,
	torsoW = 2.2,
	torsoD = 1.25,
	headH = 1.7,
	fingers = true,
	fingerLen1 = 0.25,
	fingerLen2 = 0.21,
	thumbLen1 = 0.22,
	thumbLen2 = 0.19,
}

-- Дополнительные суставы головы (опора в char space покоя). Имена — часть контракта с аниматорами.
-- Голова: шея поднимается от Neck (y=4.95) вверх-вперёд, череп ~y 6.0, морда вытянута вперёд до z≈-1.5.
S.EXTRA = {
	Jaw = { parent = "Head", pivot = { 0, 5.789, -0.061 } }, -- нижняя челюсть, открывается вниз (вращение по X)
	RightEar = { parent = "Head", pivot = { 0.4, 6.723, 0.004 } },
	LeftEar = { parent = "Head", pivot = { -0.4, 6.723, 0.004 } },
	Glasses = { parent = "Head", pivot = { 0, 6.096, -0.732 } },
	RightBrow = { parent = "Head", pivot = { 0.3, 6.354, -0.702 } },
	LeftBrow = { parent = "Head", pivot = { -0.3, 6.354, -0.702 } },
	UpperLip = { parent = "Head", pivot = { 0, 5.747, -0.86 } }, -- верхняя губа (оскал/улыбка: подъём)
	Mane = { parent = "Head", pivot = { 0, 6.772, -0.114 } }, -- хохолок между ушами
}

function S.new(name)
	local rig = Rig.new(name or "Horse", S.PROPORTIONS)
	local roblox = require("@lune/roblox")
	local V = roblox.Vector3.new
	for jn, j in S.EXTRA do
		local p = j.pivot
		rig:joint(jn, j.parent, V(p[1], p[2], p[3]), V(p[1], p[2], p[3]), V(0.2, 0.2, 0.2))
	end
	-- Лицевые каналы (значения в ключах 0..1 или -1..1)
	rig.face = {
		jaw = { { joint = "Jaw", rot = V(-17, 0, 0) } }, -- 1 = рот открыт широко
		grin = { { joint = "UpperLip", pos = V(0, 0.04, -0.05), rot = V(4, 0, 0) } }, -- 1 = верхняя губа поднята и вывернута (видны зубы и дёсны)
		brows = { { joint = "RightBrow", pos = V(0, 0.09, 0) }, { joint = "LeftBrow", pos = V(0, 0.09, 0) } },
		browR = { { joint = "RightBrow", pos = V(0, 0.09, 0) } },
		browL = { { joint = "LeftBrow", pos = V(0, 0.09, 0) } },
		ears = { { joint = "RightEar", rot = V(-25, 0, -20) }, { joint = "LeftEar", rot = V(-25, 0, 20) } }, -- 1 = уши назад/в стороны, -1 = торчком вперёд
		earR = { { joint = "RightEar", rot = V(-25, 0, -20) } },
		earL = { { joint = "LeftEar", rot = V(-25, 0, 20) } },
		mane = { { joint = "Mane", rot = V(-20, 0, 0) } }, -- 1 = хохолок отклонён назад
	}
	rig.defaultHand = "relaxed"
	rig.defaultFace = { grin = 1 }
	return rig
end

return S
