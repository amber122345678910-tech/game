--!strict
-- Blueprint "FellSans": the Underfell fan-AU Sans on the "Skeleton" skeleton. [Lune-safe]
-- Menacing take on the family: heavy angry brows over the sockets, red eye lights with a glow, a
-- jagged fanged grin with one gold tooth (his LEFT side, the viewer's right), a cracked scar
-- running through his RIGHT socket (viewer's left), all matching SansSkullFell (SPEC §18).
-- Black leather jacket with broad shoulders, accent sleeve stripes and a shaggy grey fur hood trim,
-- red turtleneck sweater, black spiked collar, black shorts with a yellow stripe, bony hands and
-- shins, chunky red high-tops.
-- Palette keys: Jacket, Fur, Sweater, Accent, EyeGlow, GoldTooth (skins Ash/Royal override Jacket,
--   Fur, Accent, EyeGlow) + Shorts, Stripe, Shoes, Sole, Collar, Spike, Bone, Line, Socket, Scar.

local Blueprints = require(script.Parent)
local SansCommon = require(script.Parent.SansCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Fell's heavy brow ridge (HD units, from tools/meshgen/models/sans.py): inner ends slant down.
local BROWS: { SansCommon.SkullExtra } = {
	{ Name = "RightBrow", C = V(0.39, 0.25, -0.78), R = V(0.39, 0.15, 0.22), Angle = 0.27 },
	{ Name = "LeftBrow", C = V(-0.39, 0.25, -0.78), R = V(0.39, 0.15, 0.22), Angle = -0.27 },
	{ Name = "Glabella", C = V(0, 0.15, -0.84), R = V(0.14, 0.12, 0.13) },
}

local function build(rig: RigContext)
	local P = rig.Palette
	local jacketDark = PartKit.Shade(P.Jacket, -0.35)
	local leather = Enum.Material.Rubber -- semi-matte, reads as worn leather

	------------------------------------------------------------------------------------------
	-- HEAD
	------------------------------------------------------------------------------------------
	local skull = SansCommon.Skull(rig, { Variant = "Fell", Bone = P.Bone, Extra = BROWS })
	local K = skull.K
	SansCommon.Sockets(rig, skull, { Socket = P.Socket })
	SansCommon.Pupils(rig, skull, {
		Color = P.EyeGlow,
		Size = 0.115,
		Offset = Vector2.new(0.05, -0.05),
		Lights = P.EyeGlow,
		LightBrightness = 1.6,
	})
	SansCommon.Nose(rig, skull, P.Socket)
	local zig = SansCommon.Grin(rig, skull, { Line = P.Line, Style = "Jagged", Width = 0.06 })

	-- gold tooth: the upper fang between zig[3] and zig[5] (tip at zig[4]) on his left (-X) side
	do
		local a, tip, b = zig[3], zig[4], zig[5]
		local xc = tip[1]
		local yTop = skull.Upper(tip[3]) - 0.012
		local yTip = tip[2] + 0.005
		local h = (yTop - yTip) * K
		local frame = skull.Front(xc, (yTop + yTip) / 2, -0.003)
		local gold: PartKit.Props =
			{ Role = "Accent", Material = Enum.Material.Metal, Reflectance = 0.15, CastShadow = false }
		for _, edge in { a, b } do
			local so = if edge[1] > xc then 1 else -1
			local halfW = math.abs(edge[1] - xc) * K * 0.98
			local rot = CFrame.fromMatrix(Vector3.zero, V(0, 0, -so), V(0, -1, 0), V(-so, 0, 0))
			rig.Wedge(
				"Head",
				"GoldTooth",
				V(0.02 * K, h, halfW),
				frame * CFrame.new(so * halfW / 2, 0, 0) * rot,
				P.GoldTooth,
				gold
			)
		end
	end

	-- the scar: a jagged crack through his right socket (forehead -> socket, socket -> cheek)
	local scarProps: PartKit.Props = { Role = "Dark" }
	SansCommon.FaceLine(rig, skull, "Scar", {
		{ 0.4, 0.58 },
		{ 0.435, 0.49 },
		{ 0.395, 0.41 },
		{ 0.43, 0.32 },
		{ 0.405, 0.22 },
	}, 0.05, P.Scar, scarProps)
	SansCommon.FaceLine(
		rig,
		skull,
		"Scar",
		{ { 0.43, 0.36 }, { 0.49, 0.43 }, { 0.53, 0.46 } },
		0.032,
		P.Scar,
		scarProps
	)
	SansCommon.FaceLine(rig, skull, "Scar", {
		{ 0.4, -0.18 },
		{ 0.42, -0.27 },
		{ 0.39, -0.35 },
		{ 0.42, -0.44 },
	}, 0.045, P.Scar, scarProps)

	------------------------------------------------------------------------------------------
	-- TORSO: leather jacket over a red turtleneck, spiked collar, shaggy fur
	------------------------------------------------------------------------------------------
	local hoodie = SansCommon.Hoodie(rig, {
		Body = P.Jacket,
		Dark = jacketDark,
		Inner = P.Sweater,
		InnerMaterial = Enum.Material.Fabric,
		Material = leather,
		Zipper = PartKit.Mix(P.Spike, P.Jacket, 0.3),
		Pull = P.Accent,
		Spread = 0.14,
		HoodInner = PartKit.Shade(P.Fur, -0.45),
	})
	SansCommon.Pockets(rig, hoodie, { Body = P.Jacket, Dark = jacketDark, Material = leather })

	local neck = rig.Joint("Neck")
	-- turtleneck roll under the jaw
	SansCommon.EllipticCyl(
		rig,
		"UpperTorso",
		"Turtleneck",
		V(0.4, 1.16, 1.02),
		CFrame.new(0, neck.Y - 0.16, 0.0) * UPRIGHT,
		P.Sweater,
		{ Role = "ClothAlt", Material = Enum.Material.Fabric }
	)
	-- spiked leather collar around it (spikes fan out at the front and sides; the fur hides the back)
	local collarCF = CFrame.new(0, neck.Y - 0.17, -0.04)
	SansCommon.EllipticCyl(
		rig,
		"UpperTorso",
		"SpikeCollar",
		V(0.17, 1.3, 1.16),
		collarCF * UPRIGHT,
		P.Collar,
		{ Role = "Detail", Material = leather }
	)
	for i = -3, 3 do
		local a = math.rad(i * 26)
		local dir = V(math.sin(a), 0, -math.cos(a))
		local base = collarCF.Position + V(dir.X * 0.65, 0, dir.Z * 0.58)
		rig.Ellipsoid(
			"UpperTorso",
			"Spike",
			V(0.3, 0.085, 0.085),
			PartKit.Basis(base + dir * 0.11, dir),
			P.Spike,
			{ Role = "Metal", Material = Enum.Material.Metal, Reflectance = 0.2 }
		)
	end
	SansCommon.FurRing(rig, {
		Color = P.Fur,
		Shade = PartKit.Shade(P.Fur, -0.14),
		Radius = Vector2.new(1.14, 0.86),
		BallSize = 0.62,
		Count = 20,
		FrontDip = 0.3,
		FrontGap = 24,
		Lift = 0.06,
	})

	------------------------------------------------------------------------------------------
	-- LIMBS
	------------------------------------------------------------------------------------------
	SansCommon.Sleeves(rig, { Body = P.Jacket, Dark = jacketDark, Material = leather, Puff = 1.06, Stripe = P.Accent })
	SansCommon.Hands(rig, { Bone = P.Bone })
	SansCommon.Shorts(rig, { Body = P.Shorts, Stripe = P.Stripe })
	SansCommon.Shins(rig, { Bone = P.Bone })
	SansCommon.Sneakers(rig, {
		Body = P.Shoes,
		Toe = P.Sole,
		Sole = P.Sole,
		Lace = P.Sole,
		Collar = P.Collar,
		Stripe = P.Stripe,
	})
end

local blueprint: Blueprints.Blueprint = {
	Id = "FellSans",
	Family = "Skeleton",
	Skeleton = "Skeleton",
	Scale = 1,
	Overrides = SansCommon.Overrides,
	Palette = {
		Jacket = rgb(28, 28, 28), -- #1C1C1C
		Fur = rgb(138, 138, 138), -- #8A8A8A
		Sweater = rgb(181, 18, 27), -- #B5121B
		Accent = rgb(214, 32, 44),
		EyeGlow = rgb(255, 42, 42), -- #FF2A2A
		GoldTooth = rgb(255, 200, 61), -- #FFC83D
		Shorts = rgb(22, 22, 24),
		Stripe = rgb(250, 202, 46),
		Shoes = rgb(150, 18, 28),
		Sole = rgb(236, 232, 224),
		Collar = rgb(24, 22, 24),
		Spike = rgb(158, 162, 172),
		Bone = rgb(236, 232, 220),
		Line = rgb(38, 22, 24),
		Socket = rgb(0, 0, 0),
		Scar = rgb(92, 12, 18),
	},
	Build = build,
}

return blueprint
