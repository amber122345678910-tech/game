--!strict
-- Blueprint "ClassicSans": the lazy, friendly judge on the "Skeleton" skeleton. [Lune-safe]
-- Squircle skull (HD-matched, see SansCommon), deep sockets with tiny white pupils, inverted-teardrop
-- nose, the fixed wide grin; puffy open blue hoodie with fur-trimmed hood bunched around the neck,
-- white T-shirt, zipper, drawstrings, hand-warmer pockets; bony hands and shins; black shorts with
-- white side stripes; fluffy pink slippers (fan convention). The attack eye (his LEFT eye, the
-- viewer's right) carries a faint EyeGlow iris ring + light.
-- Palette keys: Hoodie, HoodieDark, Fur, Shirt, Shorts, Slippers, Accent, EyeGlow (skins: Midnight,
--   Judge, Monochrome) + Bone, BoneShade, Socket, Line.

local Blueprints = require(script.Parent)
local SansCommon = require(script.Parent.SansCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB

local function build(rig: RigContext)
	local P = rig.Palette

	------------------------------------------------------------------------------------------
	-- HEAD
	------------------------------------------------------------------------------------------
	local skull = SansCommon.Skull(rig, { Variant = "Classic", Bone = P.Bone })
	SansCommon.Sockets(rig, skull, { Socket = P.Socket })
	SansCommon.Pupils(rig, skull, { Color = P.Pupil })
	SansCommon.Nose(rig, skull, P.Socket)
	SansCommon.Grin(rig, skull, { Line = P.Line, Style = "Classic" })

	-- attack-eye hint: a faint EyeGlow iris ring around his LEFT pupil + a tiny light
	local leftPupil = rig.Model.Head:FindFirstChild("LeftPupil") :: BasePart
	local iris = rig.Disc(
		"Head",
		"LeftIris",
		0.15 * skull.K,
		0.01,
		leftPupil.CFrame * CFrame.new(0, 0, 0.012),
		P.EyeGlow,
		{ Role = "Glow", Material = Enum.Material.Neon, CastShadow = false }
	)
	rig.Light(iris, "Point", { Name = "EyeGlowLight", Color = P.EyeGlow, Brightness = 0.8, Range = 2.5 })

	-- Last Breath: a crack through his left socket and an eye that burns
	local crack: PartKit.Props = { Role = "Dark" }
	SansCommon.FaceLine(rig, skull, "Crack", {
		{ -0.4, 0.6 },
		{ -0.44, 0.5 },
		{ -0.39, 0.41 },
		{ -0.44, 0.31 },
		{ -0.41, 0.22 },
	}, 0.05, P.Line, crack)
	SansCommon.FaceLine(rig, skull, "Crack", { { -0.44, 0.36 }, { -0.51, 0.44 }, { -0.56, 0.47 } }, 0.032, P.Line, crack)
	SansCommon.FaceLine(rig, skull, "Crack", { { -0.4, -0.16 }, { -0.43, -0.26 }, { -0.4, -0.34 } }, 0.04, P.Line, crack)
	local flame = rig.Disc(
		"Head",
		"EyeFlame",
		0.11 * skull.K,
		0.01,
		leftPupil.CFrame * CFrame.new(-0.04, 0.16, 0.014),
		P.EyeGlow,
		{ Role = "Glow", Material = Enum.Material.Neon, CastShadow = false }
	)
	flame.Size = Vector3.new(flame.Size.X * 0.7, flame.Size.Y * 1.8, flame.Size.Z)

	------------------------------------------------------------------------------------------
	-- TORSO: hoodie, shirt, fur trim
	------------------------------------------------------------------------------------------
	local hoodie = SansCommon.Hoodie(rig, {
		Body = P.Hoodie,
		Dark = P.HoodieDark,
		Inner = P.Shirt,
		Zipper = PartKit.Mix(P.Accent, P.HoodieDark, 0.35),
		Pull = P.Accent,
		Cord = PartKit.Mix(P.Shirt, P.Fur, 0.4),
		Aglet = P.Accent,
	})
	SansCommon.Pockets(rig, hoodie, { Body = P.Hoodie, Dark = P.HoodieDark })
	SansCommon.FurRing(rig, { Color = P.Fur })

	------------------------------------------------------------------------------------------
	-- LIMBS
	------------------------------------------------------------------------------------------
	SansCommon.Sleeves(rig, { Body = P.Hoodie, Dark = P.HoodieDark })
	SansCommon.Hands(rig, { Bone = P.Bone })
	SansCommon.Shorts(rig, { Body = P.Shorts, Stripe = P.Accent })
	SansCommon.Shins(rig, { Bone = P.Bone })
	SansCommon.Slippers(rig, { Body = P.Slippers })
end

local blueprint: Blueprints.Blueprint = {
	Id = "LastBreathSans",
	Family = "Skeleton",
	Skeleton = "Skeleton",
	Scale = 1,
	Overrides = SansCommon.Overrides,
	Palette = {
		Hoodie = rgb(42, 72, 140), -- worn navy
		HoodieDark = rgb(26, 44, 92),
		Fur = rgb(189, 192, 201), -- #BDC0C9
		Shirt = rgb(255, 255, 255),
		Shorts = rgb(30, 30, 36),
		Slippers = rgb(150, 110, 128), -- faded
		Accent = rgb(238, 240, 246),
		EyeGlow = rgb(80, 220, 255), -- burning cyan
		Bone = rgb(238, 236, 228),
		BoneShade = rgb(198, 194, 186),
		Socket = rgb(0, 0, 0),
		Line = rgb(34, 30, 34),
		Pupil = rgb(255, 255, 255),
	},
	Build = build,
}

return blueprint
