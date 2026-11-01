--!strict
-- Blueprint "Patience" ("The Quiet One"): light-blue SOUL class on the Human skeleton. [Lune-safe]
-- Cyan sweater with two pale stripes, navy shorts, white knee socks and Mary Jane shoes; dark hair with a
-- straight fringe and a high ponytail tied with a big FADED RIBBON bow (loops stick out past the head so the bow
-- reads from the front); calm closed eyes and a tiny smile; a bandage wrapped round the left hand; the Toy Knife
-- in the right fist. Body: HumanCommon.
-- Palette keys: Sweater, Stripe, Ribbon (skins override these three), Skin, Hair, Pants, Sock, Shoe, Sole,
--               Cheek, Bandage.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad

local function build(rig: RigContext)
	local P = rig.Palette
	local info = HumanCommon.Body(rig, {
		Hair = "Ponytail",
		Eyes = "Calm",
		Mouth = "Gentle",
		Cheeks = true,
		Stripes = { { 0.26, 0.37 }, { 0.6, 0.71 } },
		Legs = "Shorts",
		Shoes = "MaryJane",
		Weapon = "ToyKnife",
		WeaponTilt = -18,
	})

	-- FADED RIBBON: a big bow on the top-right of the head (reads from the front) + a ribbon band round the
	-- ponytail tie
	local fadedP = { Role = "Accent", Material = Enum.Material.Fabric }
	local bowAt = rig.OnEllipsoid(info.HairCF, info.HairRadii, 38, 44, -0.02)
	HumanCommon.Bow(rig, "Head", "Ribbon", bowAt * CFrame.Angles(0, 0, rad(-24)), 1.65, P.Ribbon, fadedP)
	local tie = info.HairTie :: CFrame
	HumanCommon.ECyl(rig, "Head", "RibbonTie", tie * CF(0, 0, -0.06), 0.1, 0.24, 0.22, P.Ribbon, fadedP)

	-- bandage wraps on the left hand (Omega Flowey's Patience phase: knives + bandage)
	local wr = rig.Joint("LeftWrist")
	local wrap = { Role = "Detail", Material = Enum.Material.Fabric }
	for i, dy in { -0.1, -0.2 } do
		HumanCommon.Band(rig, "LeftHand", "Bandage" .. i, V(wr.X, wr.Y + dy, 0.0), 0.075, 0.25, 0.33, P.Bandage, wrap)
	end
	rig.Box("LeftHand", "BandageEnd", V(0.035, 0.12, 0.07), CF(wr.X - 0.12, wr.Y - 0.24, -0.06) * CFrame.Angles(rad(10), 0, rad(-14)), P.Bandage, wrap)
end

local blueprint: Blueprints.Blueprint = {
	Id = "Patience",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Sweater = rgb(84, 192, 212),
		Stripe = rgb(228, 248, 248),
		Ribbon = rgb(150, 214, 226),
		Skin = rgb(246, 214, 190),
		Hair = rgb(46, 40, 60),
		Pants = rgb(52, 64, 104),
		Sock = rgb(244, 244, 248),
		Shoe = rgb(46, 52, 86),
		Sole = rgb(30, 30, 40),
		Cheek = rgb(244, 160, 170),
		Bandage = rgb(246, 240, 228),
	},
	Build = build,
}

return blueprint
