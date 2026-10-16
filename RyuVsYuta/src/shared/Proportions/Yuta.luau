--!strict
-- Юта: ~6 стадов, стройный, плечи чуть узкие (объём даёт свободная куртка)
-- Пропорции скелета (студы). Владелец файла — строитель модели Yuta.
local Types = require(script.Parent.Parent.SkeletonTypes)

return {
	hipHeight = 3.05,
	pelvisHalf = 0.36,
	hipDrop = 0.12,
	spineLen = 0.55,
	chestLen = 0.62,
	neckBase = 0.52,
	neckLen = 0.3,
	shoulderHalf = 0.72,
	shoulderY = 0.35,
	clavicleHalf = 0.12,
	upperArm = 1.08,
	lowerArm = 0.95,
	palmLen = 0.34,
	palmWidth = 0.34,
	fingerLen = { 0.13, 0.095 },
	thumbLen = { 0.13, 0.1 },
	upperLeg = 1.42,
	lowerLeg = 1.31,
	ankleHeight = 0.2,
	footLen = 0.9,
} :: Types.Proportions
