--!strict
-- Обычный персонаж Roblox (блочный манекен R15) вместо модели Рю или Юты.
-- Тот же скелет и те же кости, что у модели персонажа, поэтому анимация сцены работает без изменений.
-- Включается переключателем на стартовом экране («Рю и Юта: обычные манекены Roblox»).

local Sculpt = require(script.Parent.Sculpt)
local Skeletons = require(script.Parent.Parent.Skeletons)

local Dummy = {}

local V = Vector3.new

-- Классический серый манекен из Rig Builder; лицо — встроенная текстура клиента
local BODY = Color3.fromRGB(163, 162, 165)
local SHADE = Color3.fromRGB(140, 139, 142)
local OUTLINE = Color3.fromRGB(20, 18, 26)
local FACE = "rbxasset://textures/face.png"

local function block(ctx: Sculpt.Ctx, bone: string, top: number, bottom: number, w: number, d: number, z: number?, name: string?, color: Color3?): Part
	local h = top - bottom
	return Sculpt.box(ctx, bone, CFrame.new(0, (top + bottom) / 2, z or 0), V(w, h, d), color or BODY, { name = name })
end

-- name — "Ryu" или "Yuta" (скелет и пропорции персонажа), modelName — имя модели в месте
function Dummy.build(origin: CFrame, name: string, modelName: string): Model
	local def = (Skeletons :: any)[name]
	local p: Skeletons.Proportions = (Skeletons :: any)[name .. "Proportions"]
	assert(def and p, "unknown rig " .. tostring(name))
	local ctx = Sculpt.newCharacter(modelName, def, origin)
	ctx.model:SetAttribute("Dummy", true)

	-- R15: ширина торса 2, конечности 1 (в масштабе роста)
	local W = p.shoulderHalf * 1.75
	local limb = W * 0.48
	local D = W * 0.5

	-- нижний торс (таз) и верхний торс
	block(ctx, "Hips", p.spineLen, -0.18, W * 0.96, D * 0.95, 0, "LowerTorso")
	block(ctx, "Chest", p.neckBase, -p.chestLen, W, D, 0, "UpperTorso")
	-- шея (у R15 её почти не видно)
	block(ctx, "Neck", p.neckLen + 0.05, 0, W * 0.32, D * 0.6, 0, "NeckBlock", SHADE)

	-- голова: классическая форма головы Roblox + лицо
	local hs = W * 0.6
	local head = Sculpt.box(ctx, "Head", CFrame.new(0, hs * 0.5, 0), V(hs, hs, hs), BODY, { name = "Head" })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = V(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = FACE
	face.Parent = head

	for _, side in { "L", "R" } do
		-- руки
		block(ctx, "UpperArm" .. side, 0.18, -p.upperArm, limb, limb, 0, side .. "UpperArm")
		block(ctx, "LowerArm" .. side, 0, -p.lowerArm, limb * 0.94, limb * 0.94, 0, side .. "LowerArm")
		block(ctx, "Hand" .. side, 0, -(p.palmLen + p.fingerLen[1] + p.fingerLen[2] * 0.5), limb * 0.9, limb * 0.9, 0, side .. "Hand")
		-- ноги
		block(ctx, "UpperLeg" .. side, 0.1, -p.upperLeg, limb, limb, 0, side .. "UpperLeg")
		block(ctx, "LowerLeg" .. side, 0, -p.lowerLeg, limb * 0.94, limb * 0.94, 0, side .. "LowerLeg")
		-- стопа (она же "подошва" для пыли)
		Sculpt.box(ctx, "Foot" .. side, CFrame.new(0, -p.ankleHeight / 2, -p.footLen * 0.18), V(limb, p.ankleHeight, p.footLen * 0.9), BODY, {
			name = "Sole" .. side,
		})
	end

	-- точка энергии (у Рю — над лбом; у манекена помпадура нет)
	if def.index.Pompadour then
		Sculpt.box(ctx, "Pompadour", CFrame.new(0, hs * 0.35, -hs * 0.45), V(0.3, 0.3, 0.3), BODY, {
			name = "EnergyAnchor",
			transparency = 1,
			castShadow = false,
		})
	end

	Sculpt.outline(ctx, OUTLINE)
	return ctx.model
end

return Dummy
