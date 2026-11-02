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
local PhaseLook = require(script.Parent.Parent.PhaseLook)
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

	-- PHASE LOOKS (owner's picture): parts named Phase2_* / Phase3_* show from that phase on (Rigs/PhaseLook)
	local blood = Color3.fromRGB(170, 0, 14)
	local wound: PartKit.Props = { Role = "Detail", CastShadow = false }
	-- phase 2: a scar crossing his left socket, blood at the corner of the grin, the eye starts to burn
	SansCommon.FaceLine(rig, skull, "Phase2_EyeScar", { { -0.66, 0.24 }, { -0.45, 0.03 }, { -0.25, -0.17 } }, 0.05, blood, wound)
	SansCommon.FaceLine(rig, skull, "Phase2_EyeScar", { { -0.66, -0.17 }, { -0.45, 0.03 }, { -0.25, 0.24 } }, 0.05, blood, wound)
	SansCommon.FaceLine(rig, skull, "Phase2_MouthBlood", { { 0.5, -0.46 }, { 0.53, -0.58 }, { 0.5, -0.7 } }, 0.06, blood, wound)
	SansCommon.FaceLine(rig, skull, "Phase3_MouthBlood", { { -0.55, -0.66 }, { -0.2, -0.72 }, { 0.2, -0.72 }, { 0.55, -0.64 } }, 0.07, blood, wound)
	local flame = rig.Disc(
		"Head",
		"Phase2_EyeFlame",
		0.11 * skull.K,
		0.01,
		leftPupil.CFrame * CFrame.new(-0.04, 0.16, 0.014),
		P.EyeGlow,
		{ Role = "Glow", Material = Enum.Material.Neon, CastShadow = false }
	)
	flame.Size = Vector3.new(flame.Size.X * 0.7, flame.Size.Y * 1.8, flame.Size.Z)
	-- phase 3: the skull cracks open over the left side
	local crack: PartKit.Props = { Role = "Dark" }
	SansCommon.FaceLine(rig, skull, "Phase3_Crack", {
		{ -0.12, 0.86 },
		{ -0.24, 0.74 },
		{ -0.16, 0.63 },
		{ -0.32, 0.52 },
		{ -0.26, 0.42 },
	}, 0.08, Color3.fromRGB(12, 12, 14), crack)
	SansCommon.FaceLine(rig, skull, "Phase3_Crack", { { -0.24, 0.74 }, { -0.4, 0.78 }, { -0.52, 0.72 } }, 0.035, P.Line, crack)
	SansCommon.FaceLine(rig, skull, "Phase3_Crack", { { -0.32, 0.52 }, { -0.46, 0.47 } }, 0.03, P.Line, crack)

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

	-- phase 2: a bloody slash across the hoodie and a bone in his right hand; phase 3: a bloody left hand
	local neckY, waistY = rig.Joint("Neck").Y, rig.Joint("Waist").Y
	local slashProps: PartKit.Props = { Role = "Detail", CastShadow = false }
	-- a torn, uneven cut: three offset pieces along the diagonal instead of one clean stripe
	local midY = (neckY + waistY) / 2 - 0.1
	for k, seg in { { -0.62, -0.32, 0.6, 0.12, 49 }, { -0.25, -0.06, 0.75, 0.15, 54 }, { 0.14, 0.22, 0.55, 0.1, 47 } } do
		rig.Box("UpperTorso", "Phase2_Slash" .. k, Vector3.new(seg[4], seg[3], 0.06),
			CFrame.new(seg[1], midY + seg[2], -0.93) * CFrame.Angles(0, 0, math.rad(seg[5])), blood, slashProps)
	end
	rig.Box("UpperTorso", "Phase2_SlashDrip", Vector3.new(0.08, 0.5, 0.06),
		CFrame.new(-0.62, (neckY + waistY) / 2 - 0.62, -0.9), blood, slashProps)
	local wr = rig.Joint("RightWrist")
	local bone: PartKit.Props = { Role = "Bone", Material = Enum.Material.SmoothPlastic }
	local shaftTop, shaftBottom = wr + Vector3.new(0.1, -0.15, -0.18), wr + Vector3.new(0.1, -1.55, -0.18)
	rig.Box("RightHand", "Phase2_BoneShaft", Vector3.new(0.15, (shaftTop - shaftBottom).Magnitude, 0.15),
		CFrame.new((shaftTop + shaftBottom) / 2), P.Bone, bone)
	for _, endPos in { shaftTop, shaftBottom } do
		for _, dx in { -0.09, 0.09 } do
			rig.Ball("RightHand", "Phase2_BoneKnob", 0.24, CFrame.new(endPos + Vector3.new(dx, 0, 0)), P.Bone, bone)
		end
	end
	rig.Ball("LeftHand", "Phase3_HandBlood", 0.3, CFrame.new(rig.Joint("LeftWrist") + Vector3.new(0, -0.24, -0.02)), blood, slashProps)

	PhaseLook.Apply(rig.Model, 1) -- phase 1: clean
end

local blueprint: Blueprints.Blueprint = {
	Id = "LastBreathSans",
	Family = "Skeleton",
	Skeleton = "Skeleton",
	Scale = 1,
	Overrides = SansCommon.Overrides,
	Palette = {
		Hoodie = rgb(28, 28, 32), -- black jacket (owner's reference)
		HoodieDark = rgb(14, 14, 17),
		Fur = rgb(236, 236, 240), -- white hood fur
		Shirt = rgb(255, 255, 255),
		Shorts = rgb(30, 30, 36),
		Slippers = rgb(238, 238, 242), -- white shoes
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
