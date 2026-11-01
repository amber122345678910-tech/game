--!strict
-- Blueprint "Determination" ("The Fallen"): red SOUL class on the Human skeleton. [Lune-safe]
-- Green sweater with one broad yellow stripe (continued across the sleeves), brown trousers with rolled cuffs,
-- light-brown parted bob, pale skin with rosy cheeks, half-lidded red eyes and a too-wide smile, a gold heart
-- locket on a fine chain, the Real Knife in the right fist. Body: HumanCommon.
-- Palette keys: Sweater, Stripe, Pants, Accent (eyes + locket heart; skins override these four), Skin, Hair,
--               Shoe, Sole, Lace, Cheek, Gold.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad

local function build(rig: RigContext)
	local P = rig.Palette
	P.Iris = P.Accent
	local info = HumanCommon.Body(rig, {
		Hair = "Bob",
		Eyes = "Narrow",
		Mouth = "Wide",
		Cheeks = true,
		Stripes = { { 0.44, 0.7 } },
		Legs = "Pants",
		Shoes = "Sneakers",
		Weapon = "RealKnife",
		WeaponTilt = -24,
	})

	-- heart locket on a fine gold chain (welded to the chest)
	local gold = P.Gold
	local metal = { Role = "Metal", Material = Enum.Material.Metal, Reflectance = 0.1, CastShadow = false }
	local chest = info.ChestCF
	local neckY = info.NeckY
	local lockY = chest.Position.Y + 0.2
	local _, dLock = info.SweaterSize(lockY)
	local front = 0.01 - dLock / 2
	local heart = CF(0, lockY, front - 0.035)
	for _, s in { -1, 1 } do
		local _, d1 = info.SweaterSize(neckY - 0.25)
		rig.Tube("UpperTorso", "Chain", {
			V(0.27 * s, neckY - 0.06, -0.1),
			V(0.24 * s, neckY - 0.2, 0.01 - d1 / 2 - 0.006),
			V(0.1 * s, lockY + 0.2, front - 0.01),
			V(0.02 * s, lockY + 0.1, front - 0.02),
		}, 0.03, gold, metal)
	end
	rig.Ball("UpperTorso", "LocketBail", 0.06, heart * CF(0, 0.1, 0), gold, metal)
	for _, s in { -1, 1 } do
		rig.Ball("UpperTorso", "LocketLobe", 0.15, heart * CF(0.052 * s, 0.025, 0), gold, metal)
	end
	rig.Box("UpperTorso", "LocketPoint", V(0.15, 0.15, 0.07), heart * CF(0, -0.035, 0) * CFrame.Angles(0, 0, rad(45)), gold, metal)
	-- inner red heart (enamel)
	local inner = heart * CF(0, 0.005, -0.045)
	for _, s in { -1, 1 } do
		rig.Ball("UpperTorso", "LocketHeart", 0.085, inner * CF(0.03 * s, 0.022, 0), P.Accent, {
			Role = "Accent",
			CastShadow = false,
		})
	end
	rig.Box("UpperTorso", "LocketHeartPoint", V(0.085, 0.085, 0.04), inner * CF(0, -0.014, 0) * CFrame.Angles(0, 0, rad(45)), P.Accent, {
		Role = "Accent",
		CastShadow = false,
	})
end

local blueprint: Blueprints.Blueprint = {
	Id = "Determination",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Sweater = rgb(58, 150, 76),
		Stripe = rgb(244, 204, 64),
		Pants = rgb(112, 74, 48),
		Accent = rgb(214, 30, 46),
		Skin = rgb(252, 224, 202),
		Hair = rgb(146, 98, 66),
		Shoe = rgb(96, 60, 42),
		Sole = rgb(52, 38, 34),
		Lace = rgb(240, 232, 214),
		Cheek = rgb(246, 132, 142),
		Gold = rgb(232, 186, 84),
	},
	Build = build,
}

return blueprint
