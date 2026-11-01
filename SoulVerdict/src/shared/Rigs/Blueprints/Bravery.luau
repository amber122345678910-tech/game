--!strict
-- Blueprint "Bravery" ("The Brawler"): orange SOUL class on the Human skeleton. [Lune-safe]
-- Orange sweater with two cream stripes, denim shorts with rolled cuffs, scuffed knees (band-aid cross on the
-- left, grazes on the right), sneakers; spiky dark hair with sideburns, bold brows, a confident open grin and a
-- band-aid on the nose; a polka-dot MANLY BANDANNA knotted round the neck; ONE big TOUGH GLOVE (boxing glove with a
-- white laced cuff) worn on the right hand - an outfit piece, not a weapon prop. Body: HumanCommon.
-- Palette keys: Glove, Bandanna, Sweater (skins override these three), Stripe, Skin, Hair, Pants, Sock, Shoe, Sole,
--               Lace, GloveCuff, Plaster, Graze.

local Blueprints = require(script.Parent)
local HumanCommon = require(script.Parent.HumanCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local rad = math.rad

local function plaster(rig: RigContext, limb: string, name: string, cf: CFrame, color: Color3, scale: number)
	local p = { Role = "Detail", CastShadow = false }
	rig.Box(limb, name, V(0.26, 0.085, 0.03) * scale, cf, color, p)
	rig.Box(limb, name .. "Pad", V(0.085, 0.07, 0.035) * scale, cf * CF(0, 0, -0.004), PartKit.Shade(color, -0.12), p)
end

local function build(rig: RigContext)
	local P = rig.Palette
	local info = HumanCommon.Body(rig, {
		Hair = "Spiky",
		Eyes = "Open",
		Brows = "Bold",
		Mouth = "Grin",
		Ears = true,
		Stripes = { { 0.3, 0.4 }, { 0.5, 0.6 } },
		Legs = "Shorts",
		Shoes = "Sneakers",
		RightHand = "None",
	})

	HumanCommon.Neckerchief(rig, info, P.Bandanna, { Dots = P.Lace, KnotSide = 0.9, Size = 1.2 })

	-- band-aid across the nose bridge
	local face, R = info.FaceCF, info.FaceRadii
	plaster(rig, "Head", "NosePlaster", rig.OnEllipsoid(face, R, 9, -6, -0.004) * CFrame.Angles(0, 0, rad(-18)), P.Plaster, 1)

	-- TOUGH GLOVE (right hand): mitt, thumb lobe, white laced cuff with a coloured band, logo oval
	local wr = rig.Joint("RightWrist")
	local x = wr.X
	local leather = { Role = "Accent", Material = Enum.Material.SmoothPlastic, Reflectance = 0.08 }
	local cuffP = { Role = "Trim", Material = Enum.Material.SmoothPlastic }
	local mitt = CF(x + 0.03, wr.Y - 0.4, -0.04)
	rig.Ellipsoid("RightHand", "GloveMitt", V(0.64, 0.72, 0.74), mitt, P.Glove, leather)
	rig.Ellipsoid("RightHand", "GlovePunch", V(0.56, 0.4, 0.62), mitt * CF(0.0, -0.19, -0.02), P.Glove, leather)
	rig.Ellipsoid(
		"RightHand",
		"GloveThumb",
		V(0.22, 0.44, 0.26),
		CF(x - 0.22, wr.Y - 0.33, -0.23) * CFrame.Angles(rad(12), 0, rad(-10)),
		PartKit.Shade(P.Glove, -0.05),
		leather
	)
	HumanCommon.Band(rig, "RightHand", "GloveCuff", V(x, wr.Y - 0.05, -0.01), 0.3, 0.46, 0.48, P.GloveCuff, cuffP)
	HumanCommon.Band(rig, "RightHand", "GloveCuffBand", V(x, wr.Y - 0.06, -0.01), 0.07, 0.47, 0.49, P.Glove, leather)
	HumanCommon.Band(rig, "RightHand", "GloveCuffRim", V(x, wr.Y + 0.09, -0.01), 0.04, 0.44, 0.46, PartKit.Shade(P.GloveCuff, -0.1), cuffP)
	for k = 1, 3 do
		rig.Box(
			"RightHand",
			"GloveLace" .. k,
			V(0.03, 0.025, 0.2),
			CF(x - 0.235, wr.Y + 0.04 - k * 0.075, -0.01) * CFrame.Angles(rad(if k % 2 == 0 then 22 else -22), 0, 0),
			P.Lace,
			{ Role = "Detail", CastShadow = false }
		)
	end
	rig.Ellipsoid(
		"RightHand",
		"GloveLogo",
		V(0.03, 0.2, 0.28),
		mitt * CF(0.315, 0.06, 0.0),
		P.GloveCuff,
		{ Role = "Detail", CastShadow = false }
	)
	rig.Ellipsoid("RightHand", "GloveShine", V(0.06, 0.26, 0.1), mitt * CF(0.23, 0.13, -0.25) * CFrame.Angles(0, rad(-40), 0), PartKit.Mix(P.Glove, Color3.new(1, 1, 1), 0.45), {
		Role = "Detail",
		CastShadow = false,
	})
	rig.Attachment("RightHand", "RightGrip", mitt * CF(0, -0.2, 0))

	-- scuffed knees: band-aid cross on the left knee, grazes on the right one
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local knee = rig.Joint(side .. "Knee")
		local front = CF(knee.X, knee.Y - 0.01, -0.175)
		if s < 0 then
			plaster(rig, side .. "LowerLeg", "KneePlaster", front * CFrame.Angles(0, 0, rad(40)), P.Plaster, 0.9)
			plaster(rig, side .. "LowerLeg", "KneePlaster2", front * CF(0, 0, -0.006) * CFrame.Angles(0, 0, rad(-40)), P.Plaster, 0.9)
		else
			for i, g in { { -0.04, 0.03, 0.15, 0.09 }, { 0.05, -0.04, 0.11, 0.07 } } do
				rig.Ellipsoid(side .. "LowerLeg", "Graze" .. i, V(g[3], g[4], 0.04), front * CF(g[1], g[2], 0.004), P.Graze, {
					Role = "Detail",
					CastShadow = false,
				})
			end
		end
	end
end

local blueprint: Blueprints.Blueprint = {
	Id = "Bravery",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	Palette = {
		Glove = rgb(214, 44, 40),
		Bandanna = rgb(44, 58, 104),
		Sweater = rgb(244, 140, 26),
		Stripe = rgb(252, 234, 196),
		Skin = rgb(200, 142, 102),
		Hair = rgb(64, 40, 30),
		Pants = rgb(66, 96, 152),
		Sock = rgb(244, 242, 236),
		Shoe = rgb(52, 62, 96),
		Sole = rgb(34, 34, 44),
		Lace = rgb(246, 244, 236),
		GloveCuff = rgb(246, 242, 232),
		Plaster = rgb(236, 196, 150),
		Graze = rgb(214, 96, 92),
	},
	Build = build,
}

return blueprint
