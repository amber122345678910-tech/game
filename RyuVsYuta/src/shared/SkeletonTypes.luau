--!strict
-- Тип пропорций скелета (общий для всех персонажей)
local SkeletonTypes = {}

export type Proportions = {
	hipHeight: number, -- от земли до тазобедренных суставов (центр таза)
	pelvisHalf: number, -- половина расстояния между тазобедренными суставами
	hipDrop: number, -- насколько суставы бедра ниже центра таза
	spineLen: number, -- таз -> поясница
	chestLen: number, -- поясница -> грудь (сустав в середине груди)
	neckBase: number, -- грудь -> основание шеи
	neckLen: number, -- основание шеи -> голова (основание черепа)
	shoulderHalf: number, -- половина ширины плеч (между плечевыми суставами)
	shoulderY: number, -- высота плечевых суставов над суставом груди
	clavicleHalf: number, -- где начинаются ключицы (от центра)
	upperArm: number,
	lowerArm: number,
	palmLen: number, -- запястье -> костяшки
	palmWidth: number, -- ширина ладони (по Z)
	fingerLen: { number }, -- длина фаланг 1,2,3 (средний палец); остальные — по коэффициентам
	thumbLen: { number },
	upperLeg: number,
	lowerLeg: number,
	ankleHeight: number,
	footLen: number,
	jaw: boolean?,
}

return SkeletonTypes
