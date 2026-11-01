--!strict
-- Blueprint "Justice" ("The Gunslinger"): yellow SOUL class on the Human skeleton. [Lune-safe]
-- Mustard-yellow sweater with two rust stripes, jeans tucked into heeled cowboy boots with spurs, a tin star pinned
-- on the chest, a red bandana knotted at the neck; shaggy dark hair under a COWBOY HAT (pinched crown with a
-- centre crease, coloured hat band with a concho, wide brim curled up at the sides, tipped back so the face reads);
-- determined brows and a smirk; the Empty Gun (revolver) in the right fist. Body: HumanCommon.
-- Palette keys: Hat, Sweater, Accent (hat band + bandana; skins override these three), Stripe, Skin, Hair, Pants,
--               Shoe, Sole, Badge.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local shade = PartKit.Shade

local function build(rig: RigContext)
	local P = rig.Palette
	local info = HumanCommon.Body(rig, {
		Hair = "Shaggy",
		Eyes = "Open",
		Brows = "Bold",
		Mouth = "Smirk",
		Stripes = { { 0.3, 0.4 }, { 0.54, 0.64 } },
		Legs = "Pants",
		Shoes = "Boots",
		Weapon = "EmptyGun",
		WeaponTilt = 0,
	})

	HumanCommon.Neckerchief(rig, info, P.Accent, { KnotSide = -0.8, Size = 0.9 })

	-- COWBOY HAT (welded to the head), tipped back
	local hc = rig.CFrameOf("Head").Position
	local hat = CF(hc + V(0, 0.32, 0.07)) * CFrame.Angles(rad(10), 0, 0)
	local felt = { Role = "Accent", Material = Enum.Material.Fabric }
	local hatColor = P.Hat
	local dent = shade(hatColor, -0.24)
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	-- brim: flat centre, sides curled up, front dipping slightly
	HumanCommon.ECyl(rig, "Head", "HatBrim", hat * upright, 0.06, 2.0, 2.1, hatColor, felt)
	for _, s in { -1, 1 } do
		rig.Ellipsoid("Head", "HatBrimCurl", V(0.72, 0.07, 1.78), hat * CF(0.86 * s, 0.13, 0.02) * CFrame.Angles(0, 0, rad(28 * s)), hatColor, felt)
	end
	rig.Ellipsoid("Head", "HatBrimDip", V(1.6, 0.06, 0.52), hat * CF(0, -0.01, -0.86) * CFrame.Angles(rad(-8), 0, 0), shade(hatColor, -0.05), felt)
	-- crown wide enough to sit on the big head, domed top with a centre crease
	HumanCommon.ECyl(rig, "Head", "HatCrown", hat * CF(0, 0.27, 0) * upright, 0.5, 1.56, 1.5, hatColor, felt)
	rig.Ellipsoid("Head", "HatTop", V(1.5, 0.44, 1.44), hat * CF(0, 0.52, 0), hatColor, felt)
	rig.Ellipsoid("Head", "HatCrease", V(0.16, 0.08, 0.92), hat * CF(0, 0.72, 0.06), dent, { Role = "Accent", CastShadow = false })
	-- hat band + concho
	HumanCommon.ECyl(rig, "Head", "HatBand", hat * CF(0, 0.1, 0) * upright, 0.15, 1.585, 1.525, P.Accent, {
		Role = "Trim",
		Material = Enum.Material.Fabric,
	})
	rig.Disc("Head", "HatConcho", 0.15, 0.03, hat * CF(-0.5, 0.1, -0.56) * CFrame.Angles(0, rad(-40), 0), P.Badge, {
		Role = "Metal",
		Material = Enum.Material.Metal,
		CastShadow = false,
	})
	rig.Attachment("Head", "HeadTop", hat * CF(0, 1.1, 0))

	-- tin star on the chest (left side)
	local chestY = info.ChestCF.Position.Y + 0.12
	local _, d = info.SweaterSize(chestY)
	local star = CF(-0.32, chestY, 0.01 - d / 2 * 0.88 - 0.02) * CFrame.Angles(0, rad(-18), 0)
	local tin = { Role = "Metal", Material = Enum.Material.Metal, Reflectance = 0.1, CastShadow = false }
	rig.Disc("UpperTorso", "StarCore", 0.13, 0.03, star, P.Badge, tin)
	for k = 0, 4 do
		local a = rad(k * 72)
		rig.Box(
			"UpperTorso",
			"StarRay" .. k,
			V(0.075, 0.12, 0.022),
			star * CFrame.Angles(0, 0, a) * CF(0, 0.07, -0.004) * CFrame.Angles(0, 0, 0),
			P.Badge,
			tin
		)
		rig.Ball("UpperTorso", "StarTip" .. k, 0.04, star * CFrame.Angles(0, 0, a) * CF(0, 0.135, -0.008), shade(P.Badge, 0.1), tin)
	end

	-- spurs on the boot heels
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local ankle = rig.Joint(side .. "Ankle")
		local foot = side .. "Foot"
		local heel = CF(ankle.X, 0.17, rig.CFrameOf(foot).Position.Z + 0.44)
		rig.Box(foot, "SpurStrap", V(0.5, 0.04, 0.05), heel * CF(0, 0, -0.03), shade(P.Shoe, -0.25), { Role = "Detail" })
		rig.Cyl(foot, "SpurShank", 0.04, 0.05, heel * CF(0, 0, 0.06) * CFrame.Angles(0, math.pi / 2, 0), P.Badge, tin)
		rig.Disc(foot, "SpurRowel", 0.13, 0.02, heel * CF(0, 0, 0.11) * CFrame.Angles(0, math.pi / 2, 0), P.Badge, tin)
	end
end

local blueprint: Blueprints.Blueprint = {
	Id = "Justice",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Hat = rgb(150, 96, 54),
		Sweater = rgb(244, 204, 58),
		Accent = rgb(190, 54, 44),
		Stripe = rgb(196, 112, 44),
		Skin = rgb(226, 178, 136),
		Hair = rgb(70, 46, 34),
		Pants = rgb(64, 90, 142),
		Shoe = rgb(120, 72, 42),
		Sole = rgb(52, 36, 28),
		Badge = rgb(200, 206, 218),
	},
	Build = build,
}

return blueprint
