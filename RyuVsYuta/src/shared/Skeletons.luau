--!strict
-- Скелеты трёх персонажей. Общая схема костей (имена одинаковые у всех), разные пропорции.
-- Начало модели (Root) — на земле между стоп, персонаж смотрит в -Z, правая рука на +X.
-- Руки в покое висят вдоль тела, ладони смотрят к телу, пальцы — вниз.

local Rig = require(script.Parent.Rig)

local Skeletons = {}

local SkeletonTypes = require(script.Parent.SkeletonTypes)
export type Proportions = SkeletonTypes.Proportions

local FINGERS = { "Index", "Middle", "Ring", "Pinky" }
-- коэффициенты длины и смещение по Z (вперёд = -Z) относительно ширины ладони
local FINGER_SCALE: { [string]: number } = { Index = 0.92, Middle = 1.0, Ring = 0.95, Pinky = 0.76 }
local FINGER_Z: { [string]: number } = { Index = -0.375, Middle = -0.125, Ring = 0.125, Pinky = 0.375 }

Skeletons.FINGERS = FINGERS

local function v(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

function Skeletons.humanoid(name: string, p: Proportions, extra: { Rig.BoneDef }?): Rig.RigDef
	local bones: { Rig.BoneDef } = {}
	local function add(bname: string, parent: string?, offset: CFrame)
		table.insert(bones, { name = bname, parent = parent, offset = offset })
	end
	add("Root", nil, CFrame.new())
	add("Hips", "Root", v(0, p.hipHeight, 0))
	add("Spine", "Hips", v(0, p.spineLen, 0))
	add("Chest", "Spine", v(0, p.chestLen, 0))
	add("Neck", "Chest", v(0, p.neckBase, 0))
	add("Head", "Neck", v(0, p.neckLen, 0))
	if p.jaw then
		add("Jaw", "Head", v(0, 0.02 * p.hipHeight, -0.02 * p.hipHeight))
	end
	for _, side in { "L", "R" } do
		local sx = if side == "L" then -1 else 1
		add("Clavicle" .. side, "Chest", v(sx * p.clavicleHalf, p.shoulderY * 0.9, 0))
		add("UpperArm" .. side, "Clavicle" .. side, v(sx * (p.shoulderHalf - p.clavicleHalf), p.shoulderY * 0.1, 0))
		add("LowerArm" .. side, "UpperArm" .. side, v(0, -p.upperArm, 0))
		add("Hand" .. side, "LowerArm" .. side, v(0, -p.lowerArm, 0))
		-- пальцы: костяшки на конце ладони, веер по Z
		for _, f in FINGERS do
			local s = FINGER_SCALE[f]
			local knuckleY = -p.palmLen * (if f == "Middle" then 1 else if f == "Pinky" then 0.9 else 0.96)
			add(f .. "1" .. side, "Hand" .. side, v(0, knuckleY, FINGER_Z[f] * p.palmWidth))
			add(f .. "2" .. side, f .. "1" .. side, v(0, -p.fingerLen[1] * s, 0))
			add(f .. "3" .. side, f .. "2" .. side, v(0, -p.fingerLen[2] * s, 0))
		end
		-- большой палец: у основания ладони, впереди и чуть к телу
		add("Thumb1" .. side, "Hand" .. side, v(-sx * p.palmWidth * 0.12, -p.palmLen * 0.25, -p.palmWidth * 0.48))
		add("Thumb2" .. side, "Thumb1" .. side, v(0, -p.thumbLen[1], -p.thumbLen[1] * 0.35))
		add("Thumb3" .. side, "Thumb2" .. side, v(0, -p.thumbLen[2], 0))
		add("UpperLeg" .. side, "Hips", v(sx * p.pelvisHalf, -p.hipDrop, 0))
		add("LowerLeg" .. side, "UpperLeg" .. side, v(0, -p.upperLeg, 0))
		add("Foot" .. side, "LowerLeg" .. side, v(0, -p.lowerLeg, 0))
		add("Toe" .. side, "Foot" .. side, v(0, -p.ankleHeight * 0.75, -p.footLen * 0.62))
	end
	if extra then
		for _, b in extra do
			table.insert(bones, b)
		end
	end
	return Rig.define(name, bones)
end

-- Проверка: сумма вертикальных длин ног должна давать hipHeight (стопа стоит на земле)
local function legCheck(p: Proportions): number
	return p.hipDrop + p.upperLeg + p.lowerLeg + p.ankleHeight
end

Skeletons.YutaProportions = require(script.Parent.Proportions.Yuta)

Skeletons.RyuProportions = require(script.Parent.Proportions.Ryu)

Skeletons.RikaProportions = require(script.Parent.Proportions.Rika)

assert(math.abs(legCheck(Skeletons.YutaProportions) - Skeletons.YutaProportions.hipHeight) < 1e-6, "Yuta legs")
assert(math.abs(legCheck(Skeletons.RyuProportions) - Skeletons.RyuProportions.hipHeight) < 1e-6, "Ryu legs")
assert(math.abs(legCheck(Skeletons.RikaProportions) - Skeletons.RikaProportions.hipHeight) < 1e-6, "Rika legs")

Skeletons.Yuta = Skeletons.humanoid("Yuta", Skeletons.YutaProportions, {
	-- катана в ножнах на поясе слева (может перецепляться анимацией к руке через позу)
	{ name = "Katana", parent = "Hips", offset = CFrame.new(-0.42, 0.05, -0.05) },
})
Skeletons.Ryu = Skeletons.humanoid("Ryu", Skeletons.RyuProportions, {
	-- помпадур — отдельная кость: позволяет ему пружинить/сминаться под ладонями
	{ name = "Pompadour", parent = "Head", offset = CFrame.new(0, 0.55, -0.15) },
})
Skeletons.Rika = Skeletons.humanoid("Rika", Skeletons.RikaProportions, {
	-- корень гривы — для общего "дыхания" волос
	{ name = "Mane", parent = "Head", offset = CFrame.new(0, 1.4, 0.6) },
})

return Skeletons
