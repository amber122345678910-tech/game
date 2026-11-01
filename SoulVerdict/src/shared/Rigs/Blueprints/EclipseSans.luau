--!strict
-- Blueprint "EclipseSans": original SOUL VERDICT AU on the "Skeleton" skeleton. [Lune-safe]
-- The judge who swallowed the night: a deep navy hoodie whose inside is a starfield (tiny Neon stars
-- in the open front and inside the lowered hood), a tattered hood rim instead of fur, a skull cracked
-- across his right crown by glowing void fissures (violet -> cyan Neon) around a small chipped hole
-- (matches SansSkullEclipse, SPEC §18), a single white-cyan ring eye in his LEFT socket (the viewer's
-- right) and darkness with a faint ember in the other, void-dark hands with glowing veins, and a
-- broken eclipse halo floating behind his head (a dark disc rimmed by a cracked corona).
-- Palette keys: Hoodie, Lining, Void, EyeGlow (skins Solar/Aurora) + Shorts, Bone, Line, Socket.

local Blueprints = require(script.Parent)
local SansCommon = require(script.Parent.SansCommon)
local PartKit = require(script.Parent.Parent.PartKit)

type RigContext = Blueprints.RigContext
type Props = PartKit.Props

local rgb = Color3.fromRGB
local V = Vector3.new
local BLACK = Color3.new(0, 0, 0)
local jitter = SansCommon.Jitter

-- Fissures over his right crown (yaw deg + = his right, pitch deg up), after the HD sculpt.
local CRACK_MAIN = { { 1, 74 }, { 5, 64 }, { 11.5, 58 }, { 9.7, 50 }, { 17, 42 }, { 15.5, 34 }, { 22, 27 } }
local CRACK_BRANCHES = {
	{ { 11.5, 58 }, { 22, 61 }, { 30, 56 }, { 40, 58 }, { 49, 53 } },
	{ { 17, 42 }, { 26, 40 }, { 33, 33 } },
	{ { 30, 56 }, { 35, 65 }, { 44, 70 } },
	{ { 5, 64 }, { -3.5, 58 }, { -7, 53 } },
}
local CHIP = { 34, 46 } -- the missing chip near the fissures

local function build(rig: RigContext)
	local P = rig.Palette
	local mat = Enum.Material.Fabric
	local liningBase = PartKit.Mix(P.Lining, BLACK, 0.86) -- the night inside the hoodie
	local hoodDark = PartKit.Shade(P.Hoodie, -0.4)
	local voidBone = PartKit.Mix(P.Void, BLACK, 0.8)
	local neon: Props = { Role = "Glow", Material = Enum.Material.Neon, CastShadow = false }

	------------------------------------------------------------------------------------------
	-- HEAD
	------------------------------------------------------------------------------------------
	local skull = SansCommon.Skull(rig, { Variant = "Eclipse", Bone = P.Bone })
	local K = skull.K
	SansCommon.Sockets(rig, skull, { Socket = P.Socket })
	SansCommon.Nose(rig, skull, P.Socket)
	SansCommon.Grin(rig, skull, { Line = P.Line, Style = "Classic" })

	-- his LEFT eye: one bright ring (white-cyan iris, black core) with a soft halo + light
	local ringCF = skull.Front(-0.43, 0.02, -0.03)
	rig.Disc(
		"Head",
		"LeftEyeHalo",
		0.4 * K,
		0.008,
		ringCF * CFrame.new(0, 0, 0.012),
		PartKit.Mix(P.EyeGlow, P.Void, 0.45),
		{ Role = "Glow", Material = Enum.Material.Neon, Transparency = 0.45, CastShadow = false }
	)
	local ring = rig.Disc("Head", "LeftPupil", 0.25 * K, 0.012, ringCF, P.EyeGlow, {
		Role = "Eye",
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	rig.Disc("Head", "LeftPupilCore", 0.11 * K, 0.012, ringCF * CFrame.new(0, 0, -0.008), BLACK, {
		Role = "Dark",
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	rig.Light(ring, "Point", { Name = "RingEyeLight", Color = P.EyeGlow, Brightness = 2, Range = 4 })
	rig.Attachment("Head", "LeftEye", ringCF * CFrame.new(0, 0, -0.02))
	-- his RIGHT socket stays dark: only a faint void ember deep inside
	local emberCF = skull.Front(0.4, -0.02, -0.025)
	rig.Ball("Head", "RightPupil", 0.05 * K, emberCF, P.Void, {
		Role = "Eye",
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	rig.Attachment("Head", "RightEye", emberCF * CFrame.new(0, 0, -0.02))

	-- glowing void fissures (core runs cyan near the chip, violet at the tips) + the chipped hole
	local function gradient(n: number, from: number, to: number): { Color3 }
		local out = {}
		for i = 1, n do
			local t = from + (to - from) * (i - 1) / math.max(n - 1, 1)
			table.insert(out, PartKit.Mix(P.EyeGlow, P.Void, t))
		end
		return out
	end
	SansCommon.DomeLine(rig, skull, "Fissure", CRACK_MAIN, 0.05, gradient(#CRACK_MAIN - 1, 0.85, 0.15), neon)
	for _, path in CRACK_BRANCHES do
		SansCommon.DomeLine(rig, skull, "Fissure", path, 0.036, gradient(#path - 1, 0.35, 1), neon)
	end
	local chip = skull.Dome(CHIP[1], CHIP[2], -0.01)
	rig.Ellipsoid(
		"Head",
		"ChipGlow",
		V(0.36, 0.27, 0.1) * K,
		chip * CFrame.Angles(0, 0, math.rad(-20)),
		P.Void,
		{ Role = "Glow", Material = Enum.Material.Neon, CastShadow = false, Attributes = { HDGroup = "Skull" } }
	)
	rig.Ellipsoid(
		"Head",
		"ChipHole",
		V(0.27, 0.19, 0.1) * K,
		chip * CFrame.new(0, 0, -0.012) * CFrame.Angles(0, 0, math.rad(-20)),
		BLACK,
		{ Role = "Dark", Material = Enum.Material.Neon, CastShadow = false, Attributes = { HDGroup = "Skull" } }
	)

	-- the broken eclipse halo behind his head: void disc, cracked corona, drifting shards
	local haloCF = skull.CF * CFrame.new(0, 0.2 * K, 1.3 * K) * CFrame.Angles(math.rad(10), 0, math.rad(-12))
	local disc = rig.Disc("Head", "HaloDisc", 2.62, 0.05, haloCF, PartKit.Mix(P.Hoodie, BLACK, 0.75), {
		Role = "Dark",
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	local corona = haloCF * CFrame.new(0, 0, -0.03)
	for _, arc in { { 18, 104, 3 }, { 128, 208, 3 }, { 232, 338, 4 } } do
		rig.Arc("Head", "Corona", corona, 1.36, arc[1], arc[2], arc[3], 0.11, 0.04, P.EyeGlow, neon)
	end
	for _, arc in { { 40, 86, 2 }, { 150, 196, 2 }, { 262, 316, 2 } } do
		rig.Arc("Head", "CoronaFlare", corona, 1.5, arc[1], arc[2], arc[3], 0.05, 0.03, P.Void, neon)
	end
	for i, deg in { 116, 220 } do
		local a = math.rad(deg)
		local r = 1.42 + 0.08 * i
		rig.Box(
			"Head",
			"HaloShard",
			V(0.2, 0.09, 0.04),
			corona * CFrame.new(math.cos(a) * r, math.sin(a) * r, -0.02) * CFrame.Angles(0, 0, a + 0.7 * i),
			if i == 1 then P.EyeGlow else P.Void,
			neon
		)
	end
	rig.Light(disc, "Point", { Name = "CoronaLight", Color = P.EyeGlow, Brightness = 1.4, Range = 5 })

	------------------------------------------------------------------------------------------
	-- TORSO: navy hoodie with the night inside, tattered hood rim
	------------------------------------------------------------------------------------------
	local hoodie = SansCommon.Hoodie(rig, {
		Body = P.Hoodie,
		Dark = hoodDark,
		Inner = liningBase,
		InnerRole = "Dark",
		Zipper = PartKit.Mix(P.Lining, P.Hoodie, 0.55),
		Pull = P.Lining,
		Cord = PartKit.Mix(P.Lining, P.Hoodie, 0.3),
		Aglet = P.Void,
		HoodInner = liningBase,
	})
	SansCommon.Pockets(rig, hoodie, { Body = P.Hoodie, Dark = hoodDark })

	-- stars scattered over the night in the open front
	local waistY, neckY = rig.Joint("Waist").Y, rig.Joint("Neck").Y
	for i = 1, 9 do
		local y = waistY - 0.35 + (neckY - 0.45 - (waistY - 0.35)) * (i - 0.5) / 9
		local edge = hoodie.EdgeX(y)
		local x = edge * 0.7 * jitter(i, 21)
		local z = hoodie.InnerFrontZ(x, y)
		if z then
			local d = 0.035 + 0.03 * math.abs(jitter(i, 22))
			rig.Ball(
				"UpperTorso",
				"Star",
				d,
				CFrame.new(x, y, z - 0.004),
				if i % 3 == 0 then P.Lining else rgb(236, 240, 255),
				neon
			)
		end
	end
	-- and inside the lowered hood behind his neck
	for i = 1, 4 do
		local a = math.rad(-50 + (i - 1) * 33)
		rig.Ball(
			"UpperTorso",
			"Star",
			0.05 + 0.02 * math.abs(jitter(i, 31)),
			CFrame.new(math.sin(a) * 0.55, neckY + 0.34 + 0.05 * jitter(i, 32), 0.42 + math.cos(a) * 0.06),
			if i % 2 == 0 then P.Lining else rgb(236, 240, 255),
			neon
		)
	end

	-- hood rim: a soft folded roll (open at the front) with torn strips draping over the shoulders
	SansCommon.FurRing(rig, {
		Color = P.Hoodie,
		Shade = PartKit.Shade(P.Hoodie, -0.15),
		BallSize = 0.42,
		Count = 16,
		FrontGap = 26,
		Radius = Vector2.new(1.02, 0.78),
	})
	local tatter: Props = { Role = "ClothAlt", Material = mat }
	for i = 1, 9 do
		local deg = 62 + (i - 1) * (236 / 8) + jitter(i, 41) * 8
		local a = math.rad(deg)
		local normal = V(math.sin(a), 0, -math.cos(a))
		local back = math.max(-normal.Z, 0)
		local rim = V(normal.X * 1.0, neckY - 0.18 + 0.1 * back, 0.14 + normal.Z * 0.78)
		local L = 0.42 + 0.18 * math.abs(jitter(i, 43))
		local W = 0.3 + 0.08 * jitter(i, 44)
		local frame = PartKit.Basis(rim, normal, V(0, 1, 0)) * CFrame.Angles(0, 0, 0.55 + 0.15 * jitter(i, 45))
		rig.Wedge(
			"UpperTorso",
			"HoodTatter",
			V(0.05, L, W),
			frame * CFrame.new(0, -L / 2, W / 2 * (if i % 2 == 0 then 1 else -1)) * CFrame.Angles(math.pi, 0, 0),
			if i % 2 == 0 then P.Hoodie else PartKit.Shade(P.Hoodie, -0.18),
			tatter
		)
	end

	------------------------------------------------------------------------------------------
	-- LIMBS
	------------------------------------------------------------------------------------------
	SansCommon.Sleeves(rig, { Body = P.Hoodie, Dark = hoodDark })
	SansCommon.Hands(rig, { Bone = voidBone, Role = "Dark", Glow = P.Void })
	SansCommon.Shorts(rig, { Body = P.Shorts, Stripe = P.Lining })
	SansCommon.Shins(rig, { Bone = P.Bone })
	SansCommon.Slippers(rig, {
		Body = PartKit.Shade(P.Hoodie, -0.15),
		Sole = PartKit.Shade(P.Hoodie, -0.55),
		Rim = P.Lining,
	})
end

local blueprint: Blueprints.Blueprint = {
	Id = "EclipseSans",
	Family = "Skeleton",
	Skeleton = "Skeleton",
	Scale = 1,
	Overrides = SansCommon.Overrides,
	Palette = {
		Hoodie = rgb(26, 32, 74), -- deep navy
		Lining = rgb(132, 96, 255), -- starfield glow / trims
		Void = rgb(150, 72, 255), -- fissures, chip, veins, corona flare
		EyeGlow = rgb(170, 240, 255), -- the ring eye and the corona
		Shorts = rgb(18, 18, 30),
		Bone = rgb(234, 235, 240),
		Line = rgb(28, 26, 40),
		Socket = rgb(0, 0, 0),
	},
	Build = build,
}

return blueprint
