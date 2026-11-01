--!strict
-- Blueprint "Kindness" ("The Cook"): green SOUL class on the Human skeleton. [Lune-safe]
-- Spring-green sweater with cream stripes, brown trousers, sneakers; fluffy dark curls, smiling closed eyes, a
-- gentle smile and rosy cheeks; a STAINED APRON over everything: bib (three panels that follow the chest), straps,
-- waist tie with a bow at the back, knee-length skirt with a stitched pocket holding a wooden spoon, and
-- splotches of sauce, grease and burnt crumbs; the Burnt Pan held in the right fist. Body: HumanCommon.
-- Palette keys: Apron, Sweater, Pan (skins override these three), Stripe, Skin, Hair, Pants, Shoe, Sole, Spoon.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local mix = PartKit.Mix
local shade = PartKit.Shade

local function build(rig: RigContext)
	local P = rig.Palette
	local info = HumanCommon.Body(rig, {
		Hair = "Curly",
		Eyes = "Happy",
		Mouth = "Gentle",
		Cheeks = true,
		Stripes = { { 0.24, 0.34 }, { 0.62, 0.72 } },
		Legs = "Pants",
		Shoes = "Sneakers",
		Weapon = "BurntPan",
		WeaponTilt = -58,
	})

	local apron = P.Apron
	local trim = shade(apron, -0.12)
	local cloth = { Role = "ClothAlt", Material = Enum.Material.Fabric }
	local trimP = { Role = "Trim", Material = Enum.Material.Fabric }
	local stainP = { Role = "Detail", CastShadow = false }

	-- three panels laid on a curved surface: centre flat, sides turned to follow the body
	local function panels(limb: string, name: string, yTop: number, yBottom: number, wTop: number, wBottom: number, frontZ: (number) -> number, tilt: number)
		local h = yTop - yBottom
		local ym = (yTop + yBottom) / 2
		local w = (wTop + wBottom) / 2
		local cw = w * 0.5
		local z = frontZ(ym)
		rig.Box(limb, name, V(cw, h, 0.035), CF(0, ym, z) * CFrame.Angles(rad(tilt), 0, 0), apron, cloth)
		for _, s in { -1, 1 } do
			local sw = (w - cw) / 2 + 0.03
			local edge = CF(cw / 2 * s, ym, z) * CFrame.Angles(rad(tilt), 0, 0) * CFrame.Angles(0, rad(-28 * s), 0)
			rig.Box(limb, name .. "Side", V(sw, h, 0.035), edge * CF(sw / 2 * s - 0.01 * s, 0, 0), apron, cloth)
		end
	end

	local function sweaterFront(y: number): number
		local _, d = info.SweaterSize(y)
		return 0.01 - d / 2 - 0.025
	end

	-- bib on the chest + hemmed top edge + straps to the collar
	local bibTop, bibBottom = info.NeckY - 0.42, info.NeckY - 1.08
	panels("UpperTorso", "Bib", bibTop, bibBottom, 0.66, 0.74, sweaterFront, -2)
	rig.Box("UpperTorso", "BibHem", V(0.38, 0.045, 0.045), CF(0, bibTop - 0.02, sweaterFront(bibTop) - 0.004), trim, trimP)
	-- straps run up the chest, over the shoulders (on the yoke surface) and down the back
	local yokeY = rig.Joint("RightShoulder").Y - 0.1
	for _, s in { -1, 1 } do
		rig.Tube("UpperTorso", "Strap", {
			V(0.29 * s, bibTop - 0.03, sweaterFront(bibTop) + 0.03),
			V(0.3 * s, yokeY + 0.17, -0.31),
			V(0.31 * s, yokeY + 0.285, 0.02),
			V(0.3 * s, yokeY + 0.15, 0.36),
		}, 0.06, trim, trimP)
	end

	-- waist tie round the body, bow at the back
	local tieY = info.HemY + 0.1
	local hw, hd = info.SweaterSize(tieY + 0.1)
	HumanCommon.Band(rig, "UpperTorso", "ApronTie", V(0, tieY, 0.01), 0.085, hw + 0.06, hd + 0.06, trim, trimP)
	HumanCommon.Bow(rig, "UpperTorso", "ApronBow", CF(0, tieY, 0.01 + (hd + 0.06) / 2 + 0.03) * CFrame.Angles(0, math.pi, 0), 1.25, apron, {
		Role = "Trim",
		Material = Enum.Material.Fabric,
	})

	-- skirt on the hips, tilted out over the thighs
	local waistY = rig.Joint("Waist").Y
	local skirtTop, skirtBottom = tieY - 0.03, waistY - 1.02
	local function hipFront(_y: number): number
		return -0.43
	end
	panels("LowerTorso", "Skirt", skirtTop, skirtBottom, 1.08, 1.26, hipFront, -7)
	local skirtFront = CF(0, (skirtTop + skirtBottom) / 2, -0.43) * CFrame.Angles(rad(-7), 0, 0)
	rig.Box("LowerTorso", "SkirtHem", V(0.5, 0.05, 0.045), skirtFront * CF(0, -(skirtTop - skirtBottom) / 2 + 0.03, -0.004), trim, trimP)

	-- stitched pocket with a wooden spoon
	local pocket = skirtFront * CF(0.1, -0.06, -0.026)
	rig.Box("LowerTorso", "Pocket", V(0.4, 0.28, 0.025), pocket, shade(apron, -0.05), cloth)
	rig.Box("LowerTorso", "PocketHem", V(0.4, 0.04, 0.03), pocket * CF(0, 0.12, -0.004), trim, trimP)
	rig.Dashes("LowerTorso", "PocketStitch", {
		(pocket * CF(-0.18, 0.09, -0.016)).Position,
		(pocket * CF(-0.18, -0.12, -0.016)).Position,
		(pocket * CF(0.18, -0.12, -0.016)).Position,
		(pocket * CF(0.18, 0.09, -0.016)).Position,
	}, 0.08, 0.05, 0.018, trim, { Role = "Detail", CastShadow = false, Normal = pocket.LookVector })
	local spoonBase = pocket * CF(-0.08, 0.02, 0.02)
	local spoonTop = spoonBase * CF(-0.1, 0.38, -0.03)
	rig.CylBetween("LowerTorso", "SpoonHandle", spoonBase.Position, spoonTop.Position, 0.05, P.Spoon, {
		Role = "Detail",
		Material = Enum.Material.Wood,
	})
	rig.Ellipsoid("LowerTorso", "SpoonBowl", V(0.13, 0.19, 0.06), spoonTop * CF(-0.03, 0.1, 0) * CFrame.Angles(0, 0, rad(14)), P.Spoon, {
		Role = "Detail",
		Material = Enum.Material.Wood,
	})

	-- stains (derived from the apron colour so every skin keeps them believable)
	local sauce = mix(apron, rgb(196, 66, 48), 0.55)
	local grease = mix(apron, rgb(196, 156, 70), 0.45)
	local burnt = mix(apron, rgb(70, 46, 32), 0.6)
	local bibFront = CF(0, 2.7, sweaterFront(2.7) - 0.02)
	rig.Ellipsoid("UpperTorso", "StainSauce", V(0.17, 0.13, 0.02), bibFront * CF(-0.1, 0.12, 0) * CFrame.Angles(0, 0, rad(25)), sauce, stainP)
	rig.Ellipsoid("UpperTorso", "StainGrease", V(0.14, 0.18, 0.02), bibFront * CF(0.13, -0.16, 0) * CFrame.Angles(0, 0, rad(-20)), grease, stainP)
	rig.Ellipsoid("LowerTorso", "StainBurnt", V(0.2, 0.12, 0.02), skirtFront * CF(-0.2, 0.25, -0.024) * CFrame.Angles(0, 0, rad(10)), burnt, stainP)
	rig.Ellipsoid("LowerTorso", "StainBurnt2", V(0.08, 0.07, 0.02), skirtFront * CF(-0.08, 0.31, -0.024), burnt, stainP)
	rig.Ellipsoid("LowerTorso", "StainSauce3", V(0.15, 0.1, 0.02), skirtFront * CF(0.22, -0.36, -0.024) * CFrame.Angles(0, 0, rad(-30)), sauce, stainP)
end

local blueprint: Blueprints.Blueprint = {
	Id = "Kindness",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Apron = rgb(246, 238, 220),
		Sweater = rgb(104, 190, 88),
		Pan = rgb(66, 64, 70),
		Stripe = rgb(236, 244, 210),
		Skin = rgb(180, 122, 88),
		Hair = rgb(62, 42, 34),
		Pants = rgb(126, 88, 60),
		Shoe = rgb(96, 64, 46),
		Sole = rgb(50, 38, 34),
		Spoon = rgb(196, 146, 92),
	},
	Build = build,
}

return blueprint
