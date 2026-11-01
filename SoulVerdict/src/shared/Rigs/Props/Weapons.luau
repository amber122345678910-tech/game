--!strict
-- Weapons: hand-held weapon props for the SOUL-class rigs + Fell Sans' bone sword. [Lune-safe]
--
-- API
--   Weapons.Build(id: string, palette: {[string]: Color3}?) -> Model
--   Weapons.List() -> {string}          every id Build accepts (display order)
--   Weapons.Has(id: string) -> boolean
-- ids: RealKnife, ToyKnife, Notebook (closed), NotebookOpen, BurntPan, EmptyGun (revolver), BoneSword.
-- Worn items (Tough Glove, Ballet Shoes, Old Tutu ...) are part of the outfits (Rigs/Blueprints/*), not props.
--
-- The returned Model is named "Weapon" (attribute WeaponId = id), Parent = nil. Every part is unanchored with
-- the PartKit visual defaults (Massless, CanCollide/CanQuery/CanTouch false, small parts cast no shadow) and
-- Role "Weapon". PrimaryPart "Grip" is the handle at the origin; every other part is welded to it
-- (WeldConstraint "Weld"), so welding the Grip alone carries the whole weapon.
--
-- GRIP SPACE (= the RIGHT hand at rest, arm hanging, character facing -Z): the handle runs along Z through the
-- fist, -Z is the thumb side (blades, the pan and the knife tips point that way), -Y is towards the fingertips
-- (the revolver's barrel points down at rest and forward once the forearm is raised), +X is the outside (back)
-- of the right hand. Blueprints place the Grip on their RightGrip attachment (HumanCommon.HoldWeapon); VFX can
-- PivotTo the model anywhere or rescale it with PartKit.ScaleModel.
--
-- Palette keys (all optional; a rig passes its whole palette): Blade, Handle (Real Knife); ToyBlade, ToyHandle;
-- Book, Page, BookTrim (Notebook); Pan, PanHandle (Burnt Pan); Gun, GunGrip, GunTrim (Empty Gun);
-- Bone, BoneGlow, BoneWrap (Bone Sword).

local PartKit = require(script.Parent.Parent.PartKit)

type Kit = PartKit.Kit
type Props = PartKit.Props
type Palette = { [string]: Color3 }
type ColorFn = (key: string, fallback: Color3) -> Color3

local V = Vector3.new
local CF = CFrame.new
local rgb = Color3.fromRGB
local rad = math.rad
local shade = PartKit.Shade

local Weapons = {}

local ORDER = { "RealKnife", "ToyKnife", "Notebook", "NotebookOpen", "BurntPan", "EmptyGun", "BoneSword" }

local AXIS_Z = CFrame.Angles(0, math.pi / 2, 0) -- turns a Cyl's X axis onto -Z (length along Z)
local AXIS_Y = CFrame.Angles(0, 0, math.pi / 2) -- turns a Cyl's X axis onto +Y

local function props(material: Enum.Material?, extra: Props?): Props
	local p: Props = { Role = "Weapon", Material = material or Enum.Material.SmoothPlastic }
	if extra then
		for k, v in extra :: any do
			(p :: any)[k] = v
		end
	end
	return p
end

------------------------------------------------------------------------------------------------
-- Real Knife: steel chef-style blade (spine up, edge down), bolster, riveted dark handle
------------------------------------------------------------------------------------------------
local function realKnife(K: Kit, m: Model, C: ColorFn): BasePart
	local steel = C("Blade", rgb(198, 204, 212))
	local handle = C("Handle", rgb(62, 42, 36))
	local metal = props(Enum.Material.Metal, { Reflectance = 0.12 })
	local grip = K.Ellipsoid(m, "Grip", V(0.13, 0.17, 0.52), CF(0, 0, 0.07), handle, props(Enum.Material.Wood))
	K.Ellipsoid(m, "Pommel", V(0.14, 0.16, 0.09), CF(0, 0, 0.32), steel, metal)
	for i, z in { -0.02, 0.17 } do
		K.Cyl(m, "Rivet" .. i, 0.15, 0.05, CF(0, 0.01, z), shade(steel, 0.1), metal)
	end
	K.Box(m, "Bolster", V(0.12, 0.19, 0.07), CF(0, 0.005, -0.215), shade(steel, -0.08), metal)
	K.Box(m, "Blade", V(0.035, 0.2, 0.46), CF(0, 0.01, -0.47), steel, metal)
	K.Wedge(m, "Tip", V(0.035, 0.2, 0.36), CF(0, 0.01, -0.88) * CFrame.Angles(0, 0, math.pi), steel, metal)
	K.Box(m, "Edge", V(0.039, 0.035, 0.46), CF(0, -0.075, -0.47), shade(steel, 0.3), metal)
	K.Box(m, "Fuller", V(0.04, 0.022, 0.4), CF(0, 0.06, -0.46), shade(steel, -0.3), metal)
	return grip
end

------------------------------------------------------------------------------------------------
-- Toy Knife: chunky plastic butter-knife with a rounded tip, toy serrations and a ring pommel
------------------------------------------------------------------------------------------------
local function toyKnife(K: Kit, m: Model, C: ColorFn): BasePart
	local blade = C("ToyBlade", rgb(214, 224, 236))
	local handle = C("ToyHandle", rgb(236, 92, 78))
	local plastic = props(Enum.Material.SmoothPlastic, { Reflectance = 0.05 })
	local grip = K.Ellipsoid(m, "Grip", V(0.15, 0.18, 0.5), CF(0, 0, 0.06), handle, plastic)
	K.Ellipsoid(m, "Guard", V(0.13, 0.32, 0.1), CF(0, 0.0, -0.2), shade(handle, 0.12), plastic)
	K.Box(m, "Blade", V(0.06, 0.18, 0.38), CF(0, 0.01, -0.42), blade, plastic)
	K.Cyl(m, "BladeTip", 0.06, 0.18, CF(0, 0.01, -0.61), blade, plastic)
	for i = 1, 4 do
		local z = -0.33 - (i - 1) * 0.085
		K.Box(m, "Tooth" .. i, V(0.05, 0.06, 0.06), CF(0, -0.08, z) * CFrame.Angles(rad(45), 0, 0), blade, plastic)
	end
	K.Cyl(m, "PommelRing", 0.06, 0.15, CF(0, 0, 0.33), shade(handle, 0.12), plastic)
	K.Box(m, "Sticker", V(0.155, 0.07, 0.07), CF(0, 0.02, 0.06) * CFrame.Angles(rad(45), 0, 0), rgb(255, 222, 92), {
		Role = "Weapon",
		CastShadow = false,
	})
	return grip
end

------------------------------------------------------------------------------------------------
-- Notebook (closed): spiral-bound, torn cover corner, ragged pages and a ribbon bookmark.
-- Held by its top edge: the book hangs below the fist in the hand's YZ plane.
------------------------------------------------------------------------------------------------
local function notebook(K: Kit, m: Model, C: ColorFn): BasePart
	local cover = C("Book", rgb(150, 52, 64))
	local page = C("Page", rgb(244, 236, 214))
	local trim = C("BookTrim", rgb(196, 198, 206))
	local coverP = props(Enum.Material.Leather)
	local paper = props(Enum.Material.SmoothPlastic)
	local metal = props(Enum.Material.Metal, { CastShadow = false })
	local cy, cz = -0.24, -0.02 -- book centre (top edge inside the fist)
	local grip = K.Box(m, "Grip", V(0.1, 0.7, 0.52), CF(0, cy, cz + 0.01), page, paper)
	K.Box(m, "CoverFront", V(0.025, 0.74, 0.56), CF(0.063, cy, cz), cover, coverP)
	K.Box(m, "CoverBack", V(0.025, 0.74, 0.56), CF(-0.063, cy, cz), cover, coverP)
	-- torn corner on the front cover (bottom-front) shows the pages beneath
	K.CornerWedge(
		m,
		"TornCorner",
		V(0.03, 0.2, 0.18),
		CF(0.066, cy - 0.28, cz - 0.2) * CFrame.Angles(0, 0, math.pi),
		page,
		paper
	)
	-- label
	K.Box(m, "Label", V(0.03, 0.14, 0.26), CF(0.064, cy + 0.12, cz - 0.02), rgb(248, 244, 230), paper)
	K.Box(m, "LabelLine", V(0.034, 0.02, 0.2), CF(0.064, cy + 0.12, cz - 0.02), shade(cover, -0.2), {
		Role = "Weapon",
		CastShadow = false,
	})
	-- spiral binding along the back edge (+Z)
	for i = 1, 6 do
		local y = cy + 0.3 - (i - 1) * 0.12
		K.Cyl(m, "Coil" .. i, 0.025, 0.15, CF(0, y, cz + 0.28) * AXIS_Y, trim, metal)
	end
	-- ragged pages sticking out of the open edge
	for i, info in { { -0.1, 14 }, { -0.32, -10 }, { 0.12, 6 } } do
		K.Wedge(
			m,
			"TornPage" .. i,
			V(0.01, 0.12, 0.1),
			CF(0.02 - i * 0.012, cy + info[1], cz - 0.29) * CFrame.Angles(rad(info[2]), 0, 0),
			page,
			paper
		)
	end
	-- ribbon bookmark hanging below
	K.Box(m, "Bookmark", V(0.012, 0.2, 0.05), CF(0.0, cy - 0.43, cz + 0.08) * CFrame.Angles(rad(8), 0, 0), rgb(214, 56, 76), {
		Role = "Weapon",
		CastShadow = false,
	})
	return grip
end

------------------------------------------------------------------------------------------------
-- Notebook (open): two halves in a shallow V on the fist, pages facing +Y (towards the face once the
-- forearm is raised), spiral rings along the spine (Z axis).
------------------------------------------------------------------------------------------------
local function notebookOpen(K: Kit, m: Model, C: ColorFn): BasePart
	local cover = C("Book", rgb(150, 52, 64))
	local page = C("Page", rgb(244, 236, 214))
	local trim = C("BookTrim", rgb(196, 198, 206))
	local coverP = props(Enum.Material.Leather)
	local paper = props(Enum.Material.SmoothPlastic)
	local metal = props(Enum.Material.Metal, { CastShadow = false })
	local spine = CF(0, 0.14, -0.02)
	local grip = K.Cyl(m, "Grip", 0.74, 0.07, spine * CF(0, -0.02, 0) * AXIS_Z, cover, coverP)
	for _, s in { -1, 1 } do
		local half = spine * CFrame.Angles(0, 0, rad(14 * s)) -- tilt each half up by 14 degrees
		local tag = if s < 0 then "L" else "R"
		K.Box(m, "Cover" .. tag, V(0.56, 0.025, 0.76), half * CF(0.28 * s, -0.01, 0), cover, coverP)
		K.Box(m, "Pages" .. tag, V(0.5, 0.045, 0.7), half * CF(0.27 * s, 0.024, 0), page, paper)
		K.Ellipsoid(m, "Curl" .. tag, V(0.14, 0.07, 0.7), half * CF(0.06 * s, 0.04, 0), page, paper)
		for r = 1, 3 do
			K.Box(m, "Line" .. tag .. r, V(0.36, 0.05, 0.016), half * CF(0.3 * s, 0.03, -0.2 + r * 0.12), rgb(160, 176, 214), {
				Role = "Weapon",
				CastShadow = false,
			})
		end
	end
	for i = 1, 6 do
		local z = -0.3 + (i - 1) * 0.12
		K.Cyl(m, "Coil" .. i, 0.025, 0.12, spine * CF(0, 0.02, z) * AXIS_Z, trim, metal)
	end
	K.Wedge(m, "TornPage", V(0.01, 0.12, 0.14), spine * CF(0.5, 0.06, -0.36) * CFrame.Angles(0, 0, rad(80)), page, paper)
	return grip
end

------------------------------------------------------------------------------------------------
-- Burnt Pan: iron frying pan (cooking face +X), rolled lip, burnt floor with scorch marks and a stuck
-- fried egg, riveted neck, dark handle with a hanging hole. The pan reaches forward (-Z) from the fist.
------------------------------------------------------------------------------------------------
local function burntPan(K: Kit, m: Model, C: ColorFn): BasePart
	local iron = C("Pan", rgb(66, 64, 70))
	local handle = C("PanHandle", rgb(46, 34, 30))
	local metal = props(Enum.Material.Metal, { Reflectance = 0.06 })
	local grip = K.Cyl(m, "Grip", 0.5, 0.11, CF(0, 0, 0.05) * AXIS_Z, handle, props(Enum.Material.Wood))
	K.Cyl(m, "HangHole", 0.13, 0.045, CF(0, 0, 0.24), rgb(20, 16, 16), props(nil, { CastShadow = false }))
	K.Cyl(m, "Ferrule", 0.1, 0.125, CF(0, 0, -0.22) * AXIS_Z, shade(iron, 0.15), metal)
	K.Cyl(m, "Neck", 0.2, 0.085, CF(0, 0, -0.35) * AXIS_Z, iron, metal)
	local c = CF(0, 0, -0.84)
	K.Cyl(m, "Pan", 0.12, 0.86, c, iron, metal)
	K.Cyl(m, "Lip", 0.035, 0.9, c * CF(0.05, 0, 0), shade(iron, 0.12), metal)
	K.Cyl(m, "Floor", 0.02, 0.74, c * CF(0.062, 0, 0), rgb(34, 28, 26), props(Enum.Material.Slate))
	for i, info in { { 0.12, 0.16, 0.3, 0.22 }, { -0.2, -0.05, 0.22, 0.16 }, { 0.02, -0.24, 0.18, 0.13 } } do
		K.Ellipsoid(
			m,
			"Scorch" .. i,
			V(0.02, info[3], info[4]),
			c * CF(0.071, info[1], info[2]) * CFrame.Angles(rad(i * 37), 0, 0),
			rgb(14, 10, 10),
			props(nil, { CastShadow = false })
		)
	end
	-- the stuck egg: burnt rim, white, yolk
	local egg = c * CF(0.075, -0.05, 0.08)
	K.Ellipsoid(m, "EggBurnt", V(0.03, 0.34, 0.3), egg * CFrame.Angles(rad(20), 0, 0), rgb(92, 58, 34), props(nil, { CastShadow = false }))
	K.Ellipsoid(m, "EggWhite", V(0.04, 0.28, 0.24), egg * CF(0.006, 0.01, 0) * CFrame.Angles(rad(20), 0, 0), rgb(246, 240, 226), props(nil, { CastShadow = false }))
	K.Ellipsoid(m, "EggYolk", V(0.07, 0.12, 0.12), egg * CF(0.025, 0.03, -0.02), rgb(255, 176, 40), props(nil, { CastShadow = false }))
	for i, y in { 0.06, -0.06 } do
		K.Ball(m, "Rivet" .. i, 0.06, CF(0.0, y, -0.43), shade(iron, 0.2), metal)
	end
	return grip
end

------------------------------------------------------------------------------------------------
-- Empty Gun: old single-action revolver. Authored in "gun space" (barrel -Z, top +Y, grip centre at the
-- origin) and turned into grip space (barrel -> -Y, top -> -Z) by GUN_TO_GRIP.
------------------------------------------------------------------------------------------------
local GUN_TO_GRIP = CFrame.Angles(-math.pi / 2, 0, 0)

local function emptyGun(K: Kit, m: Model, C: ColorFn): BasePart
	local steel = C("Gun", rgb(96, 100, 112))
	local wood = C("GunGrip", rgb(132, 78, 44))
	local brass = C("GunTrim", rgb(210, 170, 84))
	local metal = props(Enum.Material.Metal, { Reflectance = 0.08 })
	local small = props(Enum.Material.Metal, { CastShadow = false })
	local G = GUN_TO_GRIP
	local grip =
		K.Ellipsoid(m, "Grip", V(0.13, 0.4, 0.17), G * CF(0, -0.02, 0.05) * CFrame.Angles(rad(-16), 0, 0), wood, props(Enum.Material.Wood))
	K.Ellipsoid(m, "ButtCap", V(0.135, 0.08, 0.18), G * CF(0, -0.21, 0.11) * CFrame.Angles(rad(-16), 0, 0), brass, small)
	K.Box(m, "Frame", V(0.1, 0.2, 0.36), G * CF(0, 0.25, -0.12), steel, metal)
	K.Cyl(m, "Cylinder", 0.22, 0.22, G * CF(0, 0.26, -0.15) * AXIS_Z, shade(steel, 0.08), metal)
	K.Cyl(m, "CylinderBand", 0.03, 0.225, G * CF(0, 0.26, -0.2) * AXIS_Z, shade(steel, -0.18), small)
	K.Cyl(m, "Barrel", 0.56, 0.09, G * CF(0, 0.31, -0.52) * AXIS_Z, steel, metal)
	K.Cyl(m, "EjectorRod", 0.36, 0.05, G * CF(0, 0.245, -0.45) * AXIS_Z, shade(steel, -0.1), small)
	K.Cyl(m, "Muzzle", 0.02, 0.05, G * CF(0, 0.31, -0.805) * AXIS_Z, rgb(16, 14, 16), small)
	K.Box(m, "FrontSight", V(0.02, 0.05, 0.05), G * CF(0, 0.37, -0.76), brass, small)
	K.Box(m, "Hammer", V(0.05, 0.1, 0.07), G * CF(0, 0.37, 0.04) * CFrame.Angles(rad(-30), 0, 0), shade(steel, -0.1), small)
	K.Box(m, "HammerSpur", V(0.06, 0.03, 0.06), G * CF(0, 0.42, 0.08) * CFrame.Angles(rad(-30), 0, 0), shade(steel, -0.1), small)
	-- trigger guard (lower semicircle in the gun's YZ plane) + trigger
	local guardCF = G * CF(0, 0.11, -0.1) * CFrame.Angles(0, math.pi / 2, 0)
	K.Arc(m, "Guard", guardCF, 0.08, 180, 360, 5, 0.025, 0.035, brass, { Role = "Weapon", Material = Enum.Material.Metal, CastShadow = false })
	K.Box(m, "Trigger", V(0.025, 0.09, 0.03), G * CF(0, 0.1, -0.09) * CFrame.Angles(rad(18), 0, 0), brass, small)
	-- empty chambers on the cylinder face (the top one hides behind the barrel)
	for i = 1, 5 do
		local a = rad(90 + i * 60)
		K.Cyl(m, "Chamber" .. i, 0.02, 0.05, G * CF(math.cos(a) * 0.068, 0.26 + math.sin(a) * 0.068, -0.262) * AXIS_Z, rgb(18, 16, 18), small)
	end
	return grip
end

------------------------------------------------------------------------------------------------
-- Bone Sword (Fell Sans): bone hilt with knobbed pommel and cross-guard, long jagged bone blade with a red
-- glowing core. Roughly 2.6 studs long; VFX may rescale it.
------------------------------------------------------------------------------------------------
local function boneSword(K: Kit, m: Model, C: ColorFn): BasePart
	local bone = C("Bone", rgb(236, 228, 210))
	local glow = C("BoneGlow", rgb(255, 42, 42))
	local wrap = C("BoneWrap", rgb(120, 18, 24))
	local boneP = props(Enum.Material.SmoothPlastic)
	local grip = K.Cyl(m, "Grip", 0.5, 0.12, CF(0, 0, 0.06) * AXIS_Z, bone, boneP)
	for i, z in { -0.08, 0.06, 0.2 } do
		K.Cyl(m, "Wrap" .. i, 0.05, 0.135, CF(0, 0, z) * AXIS_Z * CFrame.Angles(rad(i * 9), 0, 0), wrap, props(Enum.Material.Leather))
	end
	for _, x in { -0.065, 0.065 } do
		K.Ball(m, "Pommel", 0.17, CF(x, 0, 0.33), bone, boneP)
	end
	-- cross-guard: a short bone across the edges (Y) with paired knobs
	K.Cyl(m, "Guard", 0.62, 0.11, CF(0, 0, -0.2) * AXIS_Y, bone, boneP)
	for _, y in { -0.31, 0.31 } do
		for _, x in { -0.055, 0.055 } do
			K.Ball(m, "GuardKnob", 0.13, CF(x, y, -0.2), bone, boneP)
		end
	end
	-- blade
	local bladeLen = 1.6
	local zc = -0.26 - bladeLen / 2
	K.Box(m, "Blade", V(0.07, 0.27, bladeLen), CF(0, 0, zc), bone, boneP)
	K.Wedge(m, "TipTop", V(0.07, 0.135, 0.42), CF(0, 0.0675, zc - bladeLen / 2 - 0.21), bone, boneP)
	K.Wedge(m, "TipBottom", V(0.07, 0.135, 0.42), CF(0, -0.0675, zc - bladeLen / 2 - 0.21) * CFrame.Angles(0, 0, math.pi), bone, boneP)
	K.Box(m, "Core", V(0.08, 0.05, bladeLen - 0.1), CF(0, 0, zc), glow, props(Enum.Material.Neon, { CastShadow = false }))
	K.Box(m, "CoreTip", V(0.08, 0.035, 0.3), CF(0, 0, zc - bladeLen / 2 - 0.08), glow, props(Enum.Material.Neon, { CastShadow = false }))
	-- jagged teeth along both edges (diamonds half-buried in the edge), alternating sizes
	for i = 1, 6 do
		local z = -0.42 - (i - 1) * 0.26
		local big = i % 2 == 1
		local s = if big then 0.15 else 0.11
		for _, side in { 1, -1 } do
			local y = side * (0.135 + (if big then 0.02 else 0.01))
			K.Box(m, "Tooth", V(0.06, s, s), CF(0, y, z + side * 0.03) * CFrame.Angles(rad(45 + side * 10), 0, 0), bone, boneP)
		end
	end
	return grip
end

local BUILDERS: { [string]: (K: Kit, m: Model, C: ColorFn) -> BasePart } = {
	RealKnife = realKnife,
	ToyKnife = toyKnife,
	Notebook = notebook,
	NotebookOpen = notebookOpen,
	BurntPan = burntPan,
	EmptyGun = emptyGun,
	BoneSword = boneSword,
}

function Weapons.List(): { string }
	return table.clone(ORDER)
end

function Weapons.Has(id: string): boolean
	return BUILDERS[id] ~= nil
end

function Weapons.Build(id: string, palette: Palette?): Model
	local builder = BUILDERS[id]
	if builder == nil then
		error(("Weapons.Build: unknown weapon id '%s'"):format(tostring(id)), 2)
	end
	local pal: Palette = palette or {}
	local function color(key: string, fallback: Color3): Color3
		local c = pal[key]
		if typeof(c) == "Color3" then
			return c
		end
		return fallback
	end
	local parts: { BasePart } = {}
	local K = PartKit.new({
		Role = "Weapon",
		Sink = function(part: BasePart)
			table.insert(parts, part)
		end,
	})
	local model = Instance.new("Model")
	model.Name = "Weapon"
	model:SetAttribute("WeaponId", id)
	local grip = builder(K, model, color)
	for _, part in parts do
		if part ~= grip then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "Weld"
			weld.Part0 = grip
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.PrimaryPart = grip
	return model
end

return Weapons
