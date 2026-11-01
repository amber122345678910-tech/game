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
	SansCommon.Sockets(rig, skull, { Rim = P.BoneShade, Socket = P.Socket, Deep = rgb(3, 3, 6) })
	SansCommon.Pupils(rig, skull, { Color = P.Pupil })
	SansCommon.Nose(rig, skull, P.Socket)
	SansCommon.Grin(rig, skull, { Line = P.Line, Style = "Classic" })

	-- attack-eye hint: a faint EyeGlow iris ring around his LEFT pupil + a tiny light
	local leftPupil = rig.Model.Head:FindFirstChild("LeftPupil") :: BasePart
	local iris = rig.Arc(
		"Head",
		"LeftIris",
		leftPupil.CFrame * CFrame.new(0, 0, 0.012),
		0.105,
		0,
		360,
		10,
		0.028,
		0.02,
		P.EyeGlow,
		{ Role = "Glow", Material = Enum.Material.Neon, CastShadow = false }
	)
	rig.Light(iris[1], "Point", { Name = "EyeGlowLight", Color = P.EyeGlow, Brightness = 0.8, Range = 2.5 })

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
	Id = "ClassicSans",
	Family = "Skeleton",
	Skeleton = "Skeleton",
	Scale = 1,
	Overrides = SansCommon.Overrides,
	Palette = {
		Hoodie = rgb(71, 130, 201), -- #4782C9
		HoodieDark = rgb(48, 92, 156),
		Fur = rgb(189, 192, 201), -- #BDC0C9
		Shirt = rgb(255, 255, 255),
		Shorts = rgb(30, 30, 36),
		Slippers = rgb(247, 168, 200), -- #F7A8C8
		Accent = rgb(238, 240, 246),
		EyeGlow = rgb(132, 255, 242), -- #84FFF2
		Bone = rgb(238, 236, 228),
		BoneShade = rgb(198, 194, 186),
		Socket = rgb(16, 14, 20),
		Line = rgb(34, 30, 34),
		Pupil = rgb(255, 255, 255),
	},
	Build = build,
}

return blueprint
