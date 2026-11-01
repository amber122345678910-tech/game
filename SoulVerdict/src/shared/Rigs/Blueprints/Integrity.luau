--!strict
-- Blueprint "Integrity" ("The Dancer"): dark-blue SOUL class on the Human skeleton. [Lune-safe]
-- Royal-blue sweater with two thin tutu-coloured stripes, an OLD TUTU (two flared rings of tulle petals over a
-- satin waistband, slightly worn: a few petals droop), pale tights, BALLET SHOES with satin ribbons criss-crossing
-- up the ankles; blond hair slicked into a ballerina bun with a ribbon scrunchie and a swept fringe; graceful closed
-- eyes with lashes, rosy cheeks and a soft smile. Body: HumanCommon.
-- Palette keys: Tutu, Sweater, Shoes (skins override these three), Skin, Hair, Tights, Cheek.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad

local function build(rig: RigContext)
	local P = rig.Palette
	P.Stripe = PartKit.Mix(P.Tutu, Color3.new(1, 1, 1), 0.25)
	P.Shoe = P.Shoes
	local info = HumanCommon.Body(rig, {
		Hair = "Bun",
		Eyes = "Lashes",
		Mouth = "Gentle",
		Cheeks = true,
		Ears = true,
		Stripes = { { 0.36, 0.43 }, { 0.53, 0.6 } },
		Legs = "Tights",
		Shoes = "Ballet",
		HemLift = 0.1,
	})

	-- scrunchie round the bun
	local bun = info.HairTie :: CFrame
	local tulle = { Role = "Cloth", Material = Enum.Material.Fabric }
	HumanCommon.Band(rig, "Head", "Scrunchie", (bun * CF(0, 0.02, 0.04)).Position, 0.1, 0.62, 0.58, P.Tutu, tulle)
	HumanCommon.Band(rig, "Head", "ScrunchieRoll", (bun * CF(0, 0.07, 0.04)).Position, 0.05, 0.56, 0.52, PartKit.Shade(P.Tutu, -0.12), tulle)

	-- OLD TUTU on the pelvis: satin waistband + two rings of tilted tulle petals
	local waistY = rig.Joint("Waist").Y
	local satin = { Role = "Trim", Material = Enum.Material.SmoothPlastic, Reflectance = 0.05 }
	HumanCommon.Band(rig, "LowerTorso", "TutuBand", V(0, waistY - 0.15, 0.02), 0.16, 1.32, 0.94, PartKit.Shade(P.Tutu, -0.1), satin)
	local layers = {
		{ y = -0.24, r = 0.54, n = 14, tilt = 5, size = V(0.44, 0.13, 0.9), color = P.Tutu, phase = 0 },
		{ y = -0.33, r = 0.6, n = 14, tilt = 14, size = V(0.44, 0.11, 0.86), color = PartKit.Mix(P.Tutu, Color3.new(1, 1, 1), 0.22), phase = 13 },
	}
	for li, L in layers do
		for k = 1, L.n do
			local a = rad(L.phase + (k - 1) * 360 / L.n)
			local droop = if (k + li) % 5 == 0 then 12 else 0 -- old tutu: a few petals sag
			local dir = V(math.sin(a), 0, -math.cos(a))
			local pos = V(0, waistY + L.y, 0.02) + dir * L.r
			local frame = rig.LookFrame(pos, dir, V(0, 1, 0)) * CFrame.Angles(rad(-(L.tilt + droop)), 0, 0)
			rig.Ellipsoid("LowerTorso", "Tulle" .. li, L.size, frame, L.color, tulle)
		end
	end

	-- satin ribbons criss-crossing up each ankle (two strands wound in opposite directions)
	local ribbon = { Role = "Accent", Material = Enum.Material.SmoothPlastic, Reflectance = 0.05, CastShadow = false }
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local ankle = rig.Joint(side .. "Ankle")
		local x = ankle.X
		for strand = 1, 2 do
			local dirSign = if strand == 1 then 1 else -1
			local pts: { Vector3 } = {}
			for i = 0, 4 do
				local a = rad(-90 + dirSign * i * 75)
				local radius = 0.212 - i * 0.006
				table.insert(pts, V(x + math.cos(a) * radius, ankle.Y - 0.05 + i * 0.1, 0.01 + math.sin(a) * radius))
			end
			rig.Tube(side .. "LowerLeg", "BalletRibbon" .. strand, pts, 0.035, P.Shoes, ribbon)
		end
		rig.Ellipsoid(side .. "LowerLeg", "RibbonKnot", V(0.1, 0.07, 0.07), CF(x + 0.17 * s, ankle.Y + 0.36, 0.04), P.Shoes, ribbon)
	end
end

local blueprint: Blueprints.Blueprint = {
	Id = "Integrity",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Tutu = rgb(158, 184, 248),
		Sweater = rgb(40, 70, 176),
		Shoes = rgb(242, 182, 198),
		Skin = rgb(250, 222, 204),
		Hair = rgb(230, 190, 112),
		Tights = rgb(222, 228, 252),
		Cheek = rgb(246, 150, 168),
	},
	Build = build,
}

return blueprint
