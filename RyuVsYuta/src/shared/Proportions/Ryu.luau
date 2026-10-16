--!strict
-- Рю: ~6.6 стада до макушки (+ помпадур ~0.15), мощный торс, широкие плечи, длинные ноги
-- Пропорции скелета (студы). Владелец файла — строитель модели Ryu.
-- Тождество ног: hipDrop + upperLeg + lowerLeg + ankleHeight = hipHeight.
local Types = require(script.Parent.Parent.SkeletonTypes)

return {
	hipHeight = 3.4,
	pelvisHalf = 0.42,
	hipDrop = 0.13,
	spineLen = 0.62,
	chestLen = 0.74,
	neckBase = 0.62,
	neckLen = 0.36, -- длинная жилистая шея (видна на крупном плане)
	shoulderHalf = 1.12,
	shoulderY = 0.38,
	clavicleHalf = 0.14,
	upperArm = 1.2,
	lowerArm = 1.05,
	palmLen = 0.42,
	palmWidth = 0.42,
	fingerLen = { 0.2, 0.15 },
	thumbLen = { 0.19, 0.15 },
	upperLeg = 1.6,
	lowerLeg = 1.45,
	ankleHeight = 0.22,
	footLen = 1.0,
} :: Types.Proportions
