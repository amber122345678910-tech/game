--!strict
-- Рика (полное проявление, «Колония Сендай»): маска до ~10.2 стада в полный рост, грива ещё на ~2.7 выше.
-- Размеры подогнаны под клип в сутулой позе сцены (маска ~9.5, глаз ~8, подбородок ~6.2, плечи ~7.25).
-- Огромный V-образный торс, длинные руки (кончики пальцев у колен Юты),
-- ниже пояса — чёрная дымная масса-хвост (ноги скелета спрятаны внутри неё, на них висит только масса).
-- Пропорции скелета (студы). Владелец файла — строитель модели Rika.
local Types = require(script.Parent.Parent.SkeletonTypes)

return {
	hipHeight = 3.7,
	pelvisHalf = 0.65,
	hipDrop = 0.2,
	spineLen = 1.2,
	chestLen = 1.3,
	neckBase = 1.0,
	neckLen = 0.45,
	shoulderHalf = 2.0,
	shoulderY = 0.8,
	clavicleHalf = 0.35,
	upperArm = 2.45,
	lowerArm = 2.15,
	palmLen = 0.6,
	palmWidth = 0.68,
	fingerLen = { 0.36, 0.27 },
	thumbLen = { 0.3, 0.24 },
	upperLeg = 1.7,
	lowerLeg = 1.55,
	ankleHeight = 0.25,
	footLen = 1.2,
	jaw = true,
} :: Types.Proportions
