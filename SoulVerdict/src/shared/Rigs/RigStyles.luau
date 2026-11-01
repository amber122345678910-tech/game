--!strict
-- Character style variants (SPEC §5.4). Lune-safe: pure instance edits, no services.
-- Works on the visual parts' "Role" attribute (SPEC §5.1: Skin Bone Cloth ClothAlt Trim Accent Eye Glow
-- Hair Metal Weapon Detail Dark). Physics parts (no Role) are never touched.
--
-- Reversible: the first time a style changes a part's Material / Color / Reflectance, the original is
-- stored in attributes (SV_OrigMaterial, SV_OrigColor, SV_OrigReflectance) together with the value we set
-- (SV_StyleMaterial, ...). Revert restores the original only if the property still holds our value — if
-- something else changed it meanwhile (a skin recolour), that newer value is kept.
-- Idempotent: Apply always reverts first, so Apply(model, X) twice == once; no duplicate outlines/lights.
--
-- Styles:
--   Classic  every non-special part -> SmoothPlastic (Neon / Glass / ForceField kept), no outline
--   Toon     Classic + one black outline Highlight (FillTransparency 1, OutlineTransparency 0, Occluded)
--   Soft     Cloth/ClothAlt/Trim -> Fabric, Skin/Bone -> SmoothPlastic, Metal -> slight Reflectance
--   Glow     Classic + Accent/Eye/Glow -> brighter Neon, small PointLights (max 2) on glowing Eye parts
--
-- API:
--   RigStyles.List() -> {string}                   {"Classic","Toon","Soft","Glow"} (menu order)
--   RigStyles.Get(id) -> StyleInfo?                { Id, Name: Localized, Desc: Localized }
--   RigStyles.Apply(model, styleId) -> boolean     false (model left reverted) for an unknown id
--   RigStyles.Revert(model)                        undo everything this module did to the model
--   RigStyles.Current(model) -> string?            model attribute "RigStyle"
--   RigStyles.SetOutlineVisible(model, visible)    e.g. hide the Toon outline while a character is Invisible
--   RigStyles.Default = "Toon"; RigStyles.OUTLINE_NAME / EYE_LIGHT_NAME / MAX_EYE_LIGHTS

local Types = require(script.Parent.Parent.Types)

export type StyleInfo = {
	Id: string,
	Name: Types.Localized,
	Desc: Types.Localized,
}

type StyleDef = StyleInfo & {
	Outline: boolean,
	EyeLights: boolean,
}

local RigStyles = {}

RigStyles.Default = "Toon"
RigStyles.OUTLINE_NAME = "SV_StyleOutline"
RigStyles.EYE_LIGHT_NAME = "SV_StyleEyeLight"
RigStyles.MAX_EYE_LIGHTS = 2
RigStyles.MODEL_ATTRIBUTE = "RigStyle"

local ATTR = {
	Material = "SV_OrigMaterial",
	MaterialSet = "SV_StyleMaterial",
	Color = "SV_OrigColor",
	ColorSet = "SV_StyleColor",
	Reflectance = "SV_OrigReflectance",
	ReflectanceSet = "SV_StyleReflectance",
}

local ORDER = { "Classic", "Toon", "Soft", "Glow" }

local STYLES: { [string]: StyleDef } = {
	Classic = {
		Id = "Classic",
		Name = { en = "Classic", ru = "Классика" },
		Desc = {
			en = "Clean smooth plastic, no outline.",
			ru = "Чистый гладкий пластик, без обводки.",
		},
		Outline = false,
		EyeLights = false,
	},
	Toon = {
		Id = "Toon",
		Name = { en = "Toon", ru = "Мульт" },
		Desc = {
			en = "Smooth shading with a bold black outline.",
			ru = "Гладкие формы с чёткой чёрной обводкой.",
		},
		Outline = true,
		EyeLights = false,
	},
	Soft = {
		Id = "Soft",
		Name = { en = "Soft", ru = "Мягкий" },
		Desc = {
			en = "Fabric clothes, matte skin and bone, a hint of metal shine.",
			ru = "Тканевая одежда, матовые кожа и кости, лёгкий блеск металла.",
		},
		Outline = false,
		EyeLights = false,
	},
	Glow = {
		Id = "Glow",
		Name = { en = "Glow", ru = "Сияние" },
		Desc = {
			en = "Brighter neon accents and glowing eyes that light up their surroundings.",
			ru = "Яркие неоновые акценты и светящиеся глаза, освещающие всё вокруг.",
		},
		Outline = false,
		EyeLights = true,
	},
}

-- Materials that are an effect in themselves: no style replaces them.
local KEEP_MATERIAL: { [string]: boolean } = { Neon = true, Glass = true, ForceField = true }

local COLOR_EPSILON = 0.006 -- BasePart.Color is stored with 8 bits per channel
local SOFT_METAL_REFLECTANCE = 0.12
local EYE_LIGHT_BRIGHTNESS = 1.6
local EYE_LIGHT_RANGE = 7

function RigStyles.List(): { string }
	return table.clone(ORDER)
end

function RigStyles.Get(id: string): StyleInfo?
	local def = STYLES[id]
	if def == nil then
		return nil
	end
	return { Id = def.Id, Name = def.Name, Desc = def.Desc }
end

function RigStyles.Current(model: Instance): string?
	local value = model:GetAttribute(RigStyles.MODEL_ATTRIBUTE)
	return if type(value) == "string" then value else nil
end

---------------------------------------------------------------------------------------------- helpers

local function materialByName(name: string): Enum.Material?
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	return nil
end

local function colorsClose(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) <= COLOR_EPSILON
		and math.abs(a.G - b.G) <= COLOR_EPSILON
		and math.abs(a.B - b.B) <= COLOR_EPSILON
end

local function brighten(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s * 0.92, math.min(1, v * 1.25 + 0.15))
end

local function styledParts(model: Instance): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and type(descendant:GetAttribute("Role")) == "string" then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function setMaterial(part: BasePart, material: Enum.Material)
	if part.Material == material then
		return
	end
	if part:GetAttribute(ATTR.Material) == nil then
		part:SetAttribute(ATTR.Material, part.Material.Name)
	end
	part.Material = material
	part:SetAttribute(ATTR.MaterialSet, part.Material.Name)
end

local function setColor(part: BasePart, color: Color3)
	if colorsClose(part.Color, color) then
		return
	end
	if part:GetAttribute(ATTR.Color) == nil then
		part:SetAttribute(ATTR.Color, part.Color)
	end
	part.Color = color
	part:SetAttribute(ATTR.ColorSet, part.Color) -- read back: the engine quantises colours
end

local function setReflectance(part: BasePart, reflectance: number)
	if math.abs(part.Reflectance - reflectance) < 1e-4 then
		return
	end
	if part:GetAttribute(ATTR.Reflectance) == nil then
		part:SetAttribute(ATTR.Reflectance, part.Reflectance)
	end
	part.Reflectance = reflectance
	part:SetAttribute(ATTR.ReflectanceSet, part.Reflectance)
end

local function restorePart(part: BasePart)
	local origMaterial = part:GetAttribute(ATTR.Material)
	if type(origMaterial) == "string" then
		local styled = part:GetAttribute(ATTR.MaterialSet)
		if styled == nil or part.Material.Name == styled then
			local material = materialByName(origMaterial)
			if material then
				part.Material = material
			end
		end
		part:SetAttribute(ATTR.Material, nil)
		part:SetAttribute(ATTR.MaterialSet, nil)
	end

	local origColor = part:GetAttribute(ATTR.Color)
	if typeof(origColor) == "Color3" then
		local styled = part:GetAttribute(ATTR.ColorSet)
		if typeof(styled) ~= "Color3" or colorsClose(part.Color, styled :: Color3) then
			part.Color = origColor :: Color3
		end
		part:SetAttribute(ATTR.Color, nil)
		part:SetAttribute(ATTR.ColorSet, nil)
	end

	local origReflectance = part:GetAttribute(ATTR.Reflectance)
	if type(origReflectance) == "number" then
		local styled = part:GetAttribute(ATTR.ReflectanceSet)
		if type(styled) ~= "number" or math.abs(part.Reflectance - styled) < 1e-4 then
			part.Reflectance = origReflectance
		end
		part:SetAttribute(ATTR.Reflectance, nil)
		part:SetAttribute(ATTR.ReflectanceSet, nil)
	end
end

local function styleParts(style: string, parts: { BasePart })
	for _, part in parts do
		local role = part:GetAttribute("Role")
		local special = KEEP_MATERIAL[part.Material.Name] == true
		if style == "Classic" or style == "Toon" then
			if not special then
				setMaterial(part, Enum.Material.SmoothPlastic)
			end
		elseif style == "Soft" then
			if not special then
				if role == "Cloth" or role == "ClothAlt" or role == "Trim" then
					setMaterial(part, Enum.Material.Fabric)
				elseif role == "Skin" or role == "Bone" then
					setMaterial(part, Enum.Material.SmoothPlastic)
				elseif role == "Metal" then
					setReflectance(part, math.max(part.Reflectance, SOFT_METAL_REFLECTANCE))
				end
			end
		elseif style == "Glow" then
			if role == "Accent" or role == "Eye" or role == "Glow" then
				setMaterial(part, Enum.Material.Neon)
				setColor(part, brighten(part.Color))
			elseif not special then
				setMaterial(part, Enum.Material.SmoothPlastic)
			end
		end
	end
end

local function addOutline(model: Instance)
	local highlight = Instance.new("Highlight")
	highlight.Name = RigStyles.OUTLINE_NAME
	highlight.FillColor = Color3.new(0, 0, 0)
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.new(0, 0, 0)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
end

local function eyePriority(part: BasePart): number
	local name = part.Name
	if string.find(name, "Pupil") or string.find(name, "Iris") then
		return 0
	end
	return 1
end

local function addEyeLights(parts: { BasePart })
	local eyes: { BasePart } = {}
	for _, part in parts do
		if part:GetAttribute("Role") == "Eye" and part.Material == Enum.Material.Neon then
			table.insert(eyes, part)
		end
	end
	table.sort(eyes, function(a, b)
		local pa, pb = eyePriority(a), eyePriority(b)
		if pa ~= pb then
			return pa < pb
		end
		return a.Name < b.Name
	end)
	for index = 1, math.min(#eyes, RigStyles.MAX_EYE_LIGHTS) do
		local part = eyes[index]
		local light = Instance.new("PointLight")
		light.Name = RigStyles.EYE_LIGHT_NAME
		light.Color = part.Color
		light.Brightness = EYE_LIGHT_BRIGHTNESS
		light.Range = EYE_LIGHT_RANGE
		light.Shadows = false
		light.Parent = part
	end
end

------------------------------------------------------------------------------------------------- API

function RigStyles.Revert(model: Instance)
	for _, descendant in model:GetDescendants() do
		local ours = (descendant.Name == RigStyles.OUTLINE_NAME and descendant:IsA("Highlight"))
			or (descendant.Name == RigStyles.EYE_LIGHT_NAME and descendant:IsA("PointLight"))
		if ours then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			restorePart(descendant)
		end
	end
	model:SetAttribute(RigStyles.MODEL_ATTRIBUTE, nil)
end

function RigStyles.Apply(model: Instance, styleId: string): boolean
	RigStyles.Revert(model)
	local style = STYLES[styleId]
	if style == nil then
		return false
	end
	local parts = styledParts(model)
	styleParts(styleId, parts)
	if style.Outline then
		addOutline(model)
	end
	if style.EyeLights then
		addEyeLights(parts)
	end
	model:SetAttribute(RigStyles.MODEL_ATTRIBUTE, styleId)
	return true
end

function RigStyles.SetOutlineVisible(model: Instance, visible: boolean)
	local outline = model:FindFirstChild(RigStyles.OUTLINE_NAME)
	if outline and outline:IsA("Highlight") then
		outline.Enabled = visible
	end
end

return RigStyles
