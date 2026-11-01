--!strict
-- Blueprint "Dummy": a stuffed burlap training dummy on the Human skeleton. [Lune-safe]
-- Showcase of the rig pipeline: soft stuffed shapes with joint "stuffing balls", stitched seams,
-- mismatched button eyes, a sewn smile and scar, twisted rope ties, straw poking out of the seams,
-- a patched knee, a padded red/white target on the chest (concentric thin cylinders) and a round
-- wooden stand with no post (welded to the root, so it stays put while the dummy wobbles).
-- Palette keys: Burlap, Canvas, Rope, Thread, Straw, StrawDark, ButtonL, ButtonR, ButtonThread,
--               Target, TargetLight, Pad, Patch, Sole, Wood, WoodLight, Bolt.

local Blueprints = require(script.Parent)

type RigContext = Blueprints.RigContext

local rgb = Color3.fromRGB
local V = Vector3.new

local STAND = 0.24 -- stand thickness = GroundOffset

-- Deterministic jitter in [-1, 1] (stable across runs, no RNG state).
local function jitter(i: number, salt: number): number
	local x = math.sin(i * 127.1 + salt * 311.7) * 43758.5453
	return (x - math.floor(x)) * 2 - 1
end

local function build(rig: RigContext)
	local P = rig.Palette
	local FABRIC = Enum.Material.Fabric

	local cloth = { Role = "Cloth", Material = FABRIC }
	local canvas = { Role = "ClothAlt", Material = FABRIC }
	local rope = { Role = "Trim", Material = FABRIC }
	local thread = { Role = "Detail", Material = FABRIC, CastShadow = false }
	local straw = { Role = "Hair", Material = Enum.Material.SmoothPlastic, CastShadow = false }

	-- Straw strands fanning out of `cf` (UpVector = main direction).
	local function strawTuft(
		limb: string,
		name: string,
		cf: CFrame,
		count: number,
		length: number,
		spread: number,
		salt: number
	)
		for i = 1, count do
			local yaw = (i - 1) / count * 360 + jitter(i, salt) * 25
			local tilt = spread * (0.55 + 0.45 * math.abs(jitter(i, salt + 1)))
			local dir = (cf * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(tilt), 0, 0)).UpVector
			local base = cf.Position + dir * 0.02
			local len = length * (0.7 + 0.3 * math.abs(jitter(i, salt + 2)))
			local color = if i % 3 == 0 then P.StrawDark else P.Straw
			rig.CylBetween(limb, name, base, base + dir * len, 0.045, color, straw)
		end
	end

	-- Twisted rope around an elliptic loop: overlapping ellipsoids tilted the same way read as
	-- the helix strands of a real rope.
	local function ropeLoop(
		limb: string,
		name: string,
		cf: CFrame,
		rx: number,
		rz: number,
		count: number,
		thick: number
	)
		for i = 1, count do
			local a0 = (i - 1) / count * math.pi * 2
			local a1 = i / count * math.pi * 2
			local p0 = (cf * CFrame.new(math.cos(a0) * rx, 0, math.sin(a0) * rz)).Position
			local p1 = (cf * CFrame.new(math.cos(a1) * rx, 0, math.sin(a1) * rz)).Position
			local frame = rig.Basis((p0 + p1) / 2, p1 - p0, cf.UpVector) * CFrame.Angles(0, 0, math.rad(32))
			rig.Ellipsoid(limb, name, V((p1 - p0).Magnitude * 1.7, thick, thick * 0.92), frame, P.Rope, rope)
		end
	end

	-- Short stitch lying on a surface frame (LookVector = outward normal), rotated in-plane by deg.
	local function stitch(limb: string, name: string, cf: CFrame, length: number, deg: number)
		rig.Box(limb, name, V(length, 0.034, 0.03), cf * CFrame.Angles(0, 0, math.rad(deg)), P.Thread, thread)
	end

	-- A sewn line on an ellipsoid: thread segments through `pts` plus cross stitches.
	local function sewnLine(limb: string, name: string, pts: { CFrame }, crossLength: number)
		for i = 1, #pts - 1 do
			local a, b = pts[i].Position, pts[i + 1].Position
			local normal = (pts[i].LookVector + pts[i + 1].LookVector).Unit
			local x = (b - a).Unit
			local z = (normal - x * x:Dot(normal)).Unit
			local cf = CFrame.fromMatrix((a + b) / 2, x, z:Cross(x), z)
			rig.Box(limb, name .. "Line", V((b - a).Magnitude + 0.03, 0.03, 0.025), cf, P.Thread, thread)
		end
		for i = 2, #pts - 1 do
			local along = (pts[i + 1].Position - pts[i - 1].Position).Unit
			local f = pts[i]
			local deg = math.deg(math.atan2(along:Dot(f.UpVector), along:Dot(f.RightVector)))
			stitch(limb, name .. "Stitch", f, crossLength, deg + 90 + jitter(i, #pts) * 8)
		end
	end

	------------------------------------------------------------------------------------------
	-- STAND: round wooden base with bolts (welded to the root: does not follow the legs)
	------------------------------------------------------------------------------------------
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- turns a Cyl's X axis to Y
	local wood = { Role = "Detail", Material = Enum.Material.Wood }
	rig.Cyl(
		"HumanoidRootPart",
		"StandBase",
		STAND - 0.05,
		2.0,
		CFrame.new(0, (STAND - 0.05) / 2, -0.06) * upright,
		P.Wood,
		wood
	)
	rig.Cyl("HumanoidRootPart", "StandTop", 0.06, 1.86, CFrame.new(0, STAND - 0.04, -0.06) * upright, P.WoodLight, wood)
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi * 2
		rig.Ball(
			"HumanoidRootPart",
			"StandBolt",
			0.11,
			CFrame.new(math.cos(a) * 0.82, STAND - 0.005, -0.06 + math.sin(a) * 0.82),
			P.Bolt,
			{
				Role = "Metal",
				Material = Enum.Material.Metal,
			}
		)
	end

	------------------------------------------------------------------------------------------
	-- HEAD: round stuffed sack, gathered and tied on top with straw sticking out
	------------------------------------------------------------------------------------------
	local headCF = rig.CFrameOf("Head")
	local headSize = V(1.56, 1.42, 1.44)
	local headCentre = headCF * CFrame.new(0, -0.04, 0)
	local radii = headSize / 2
	rig.Ellipsoid("Head", "Sack", headSize, headCentre, P.Burlap, cloth)

	local top = headCentre * CFrame.new(0, radii.Y - 0.02, 0.04)
	rig.Ellipsoid("Head", "TopGather", V(0.52, 0.3, 0.5), top * CFrame.new(0, 0.05, 0), P.Burlap, cloth)
	rig.Cyl("Head", "TopTie", 0.11, 0.4, top * CFrame.new(0, 0.12, 0) * upright, P.Rope, rope)
	rig.Ellipsoid("Head", "TopFrill", V(0.44, 0.16, 0.42), top * CFrame.new(0, 0.22, 0), P.Burlap, cloth)
	strawTuft("Head", "TopStraw", top * CFrame.new(0, 0.24, 0), 8, 0.5, 34, 1)

	-- button eyes (mismatched): base disc, raised boss, crossed thread
	for _, side in { "Left", "Right" } do
		local s = if side == "Left" then -1 else 1
		local color = if side == "Left" then P.ButtonL else P.ButtonR
		local cf = rig.OnEllipsoid(headCentre, radii, 23 * s, 6, -0.03)
		local eye = { Role = "Eye", Reflectance = 0.08 }
		rig.Disc("Head", side .. "EyeButton", 0.31, 0.06, cf, color, eye)
		rig.Disc(
			"Head",
			side .. "EyeBoss",
			0.22,
			0.03,
			cf * CFrame.new(0, 0, -0.035),
			color:Lerp(Color3.new(1, 1, 1), 0.12),
			{
				Role = "Eye",
				Reflectance = 0.08,
				CastShadow = false,
			}
		)
		local front = cf * CFrame.new(0, 0, -0.055)
		for _, deg in { 45, -45 } do
			rig.Box(
				"Head",
				side .. "EyeThread",
				V(0.17, 0.032, 0.02),
				front * CFrame.Angles(0, 0, math.rad(deg)),
				P.ButtonThread,
				{
					Role = "Detail",
					Material = FABRIC,
					CastShadow = false,
				}
			)
		end
		rig.Attachment("Head", side .. "Eye", cf * CFrame.new(0, 0, -0.06))
	end

	-- sewn smile
	local mouth: { CFrame } = {}
	for i = 0, 6 do
		local t = i / 6 * 2 - 1
		table.insert(mouth, rig.OnEllipsoid(headCentre, radii, t * 25, -23 + 6 * t * t, -0.008))
	end
	sewnLine("Head", "Mouth", mouth, 0.15)
	rig.Attachment("Head", "Mouth", mouth[4])

	-- stitched scar over the left brow
	local scar: { CFrame } = {}
	for i = 0, 3 do
		local t = i / 3
		table.insert(
			scar,
			rig.OnEllipsoid(headCentre, radii, -44 + 30 * t, 44 - 12 * t + 3 * math.sin(t * math.pi), -0.008)
		)
	end
	sewnLine("Head", "Scar", scar, 0.12)

	-- seam down the back of the sack
	for _, pitch in { 32, 44, 56, 68 } do
		stitch("Head", "SeamBack", rig.OnEllipsoid(headCentre, radii, 180, pitch, -0.008), 0.13, 0)
	end

	-- patch on the right cheek
	local patchCF = rig.OnEllipsoid(headCentre, radii, 60, 22, -0.012) * CFrame.Angles(0, 0, math.rad(8))
	rig.Box(
		"Head",
		"CheekPatch",
		V(0.36, 0.32, 0.03),
		patchCF,
		P.Patch,
		{ Role = "Accent", Material = FABRIC, CastShadow = false }
	)
	local pf = patchCF * CFrame.new(0, 0, -0.02)
	stitch("Head", "PatchStitch", pf * CFrame.new(-0.17, 0, 0), 0.1, 0)
	stitch("Head", "PatchStitch", pf * CFrame.new(0.17, 0, 0), 0.1, 0)
	stitch("Head", "PatchStitch", pf * CFrame.new(0, 0.155, 0), 0.1, 90)
	stitch("Head", "PatchStitch", pf * CFrame.new(0, -0.155, 0), 0.1, 90)

	------------------------------------------------------------------------------------------
	-- TORSO: broad stuffed chest + belly, padded target, rope collar, back seam
	------------------------------------------------------------------------------------------
	local torsoCF = rig.CFrameOf("UpperTorso")
	local chestSize = V(1.52, 0.96, 0.84)
	local bellySize = V(1.34, 1.22, 0.86)
	local bellyCF = torsoCF * CFrame.new(0, -0.12, 0)
	rig.Ellipsoid("UpperTorso", "ChestStuffing", chestSize, torsoCF * CFrame.new(0, 0.2, 0.01), P.Burlap, cloth)
	rig.Ellipsoid("UpperTorso", "Belly", bellySize, bellyCF, P.Burlap, cloth)

	local neckCF = CFrame.new(0, rig.Joint("Neck").Y - 0.06, 0.01)
	rig.Cyl("UpperTorso", "NeckStub", 0.3, 0.66, neckCF * upright, P.Burlap, cloth)
	ropeLoop("UpperTorso", "Collar", neckCF * CFrame.new(0, -0.04, 0), 0.36, 0.33, 13, 0.15)
	strawTuft(
		"UpperTorso",
		"NeckStraw",
		neckCF * CFrame.new(0.3, 0.02, 0.12) * CFrame.Angles(0, 0, math.rad(-60)),
		4,
		0.3,
		20,
		7
	)

	-- target pad + concentric rings
	local targetY = torsoCF.Position.Y + 0.08
	local padCF = rig.LookFrame(V(0, targetY, -bellySize.Z / 2 + 0.02), V(0, 0, -1))
	rig.Disc("UpperTorso", "TargetPad", 0.92, 0.16, padCF, P.Pad, { Role = "ClothAlt", Material = FABRIC })
	local face = padCF * CFrame.new(0, 0, -0.08)
	local rings =
		{ { 0.78, P.Target }, { 0.6, P.TargetLight }, { 0.43, P.Target }, { 0.26, P.TargetLight }, { 0.11, P.Target } }
	for i, ring in rings do
		rig.Disc(
			"UpperTorso",
			"Target" .. i,
			ring[1] :: number,
			0.02,
			face * CFrame.new(0, 0, -0.008 * i),
			ring[2] :: Color3,
			{
				Role = "Accent",
				CastShadow = i == 1,
			}
		)
	end
	local loop: { Vector3 } = {}
	for i = 0, 24 do
		local a = i / 24 * math.pi * 2
		table.insert(loop, (face * CFrame.new(math.cos(a) * 0.43, math.sin(a) * 0.43, -0.004)).Position)
	end
	rig.Dashes("UpperTorso", "PadStitch", loop, 0.09, 0.08, 0.03, P.Thread, {
		Role = "Detail",
		Material = FABRIC,
		Normal = padCF.LookVector,
		CastShadow = false,
	})
	rig.Attachment("UpperTorso", "Chest", face * CFrame.new(0, 0, -0.06))

	for i = 0, 5 do
		local y = 0.42 - i * 0.17
		local pitch = math.deg(math.asin(math.clamp((y + 0.12) / (bellySize.Y / 2), -1, 1)))
		stitch("UpperTorso", "BackSeam", rig.OnEllipsoid(bellyCF, bellySize / 2, 180, pitch, -0.006), 0.14, 0)
	end

	------------------------------------------------------------------------------------------
	-- PELVIS: darker canvas "pants" + twisted rope belt with a knot
	------------------------------------------------------------------------------------------
	local pelvisCF = rig.CFrameOf("LowerTorso")
	rig.Ellipsoid("LowerTorso", "Hips", V(1.24, 0.74, 0.84), pelvisCF * CFrame.new(0, 0.02, 0), P.Canvas, canvas)
	local beltCF = CFrame.new(0, rig.Joint("Waist").Y - 0.02, 0)
	ropeLoop("LowerTorso", "Belt", beltCF, 0.66, 0.45, 16, 0.15)
	local knot = beltCF * CFrame.new(-0.36, -0.02, -0.41)
	rig.Ball("LowerTorso", "BeltKnot", 0.22, knot, P.Rope, rope)
	rig.Tube("LowerTorso", "BeltEndA", {
		knot.Position,
		(knot * CFrame.new(-0.05, -0.2, -0.05)).Position,
		(knot * CFrame.new(-0.02, -0.36, -0.02)).Position,
	}, 0.09, P.Rope, rope)
	rig.Tube("LowerTorso", "BeltEndB", {
		knot.Position,
		(knot * CFrame.new(0.07, -0.16, -0.06)).Position,
		(knot * CFrame.new(0.12, -0.28, -0.04)).Position,
	}, 0.09, P.Rope, rope)

	------------------------------------------------------------------------------------------
	-- ARMS: stuffing balls at the joints, stuffed tubes, mitten hands, rope cuffs
	------------------------------------------------------------------------------------------
	for _, side in { "Left", "Right" } do
		local s = if side == "Left" then -1 else 1
		local ua, la, hand = side .. "UpperArm", side .. "LowerArm", side .. "Hand"
		local uaCF, laCF, handCF = rig.CFrameOf(ua), rig.CFrameOf(la), rig.CFrameOf(hand)
		rig.Ball(ua, "ShoulderStuffing", 0.5, CFrame.new(rig.Joint(side .. "Shoulder")), P.Burlap, cloth)
		rig.Ellipsoid(ua, "Sleeve", V(0.46, 0.9, 0.46), uaCF * CFrame.new(0, 0.02, 0), P.Burlap, cloth)
		rig.Ball(la, "ElbowStuffing", 0.42, CFrame.new(rig.Joint(side .. "Elbow")), P.Burlap, cloth)
		rig.Ellipsoid(la, "Forearm", V(0.41, 0.86, 0.41), laCF * CFrame.new(0, 0.01, 0), P.Burlap, cloth)
		local wristY = rig.Joint(side .. "Wrist").Y
		rig.Cyl(la, "Cuff", 0.1, 0.4, CFrame.new(laCF.Position.X, wristY + 0.06, 0) * upright, P.Rope, rope)
		rig.Ellipsoid(hand, "Mitten", V(0.42, 0.5, 0.34), handCF * CFrame.new(0, -0.05, 0), P.Burlap, cloth)
		rig.Ellipsoid(
			hand,
			"Thumb",
			V(0.16, 0.26, 0.16),
			handCF * CFrame.new(-0.13 * s, 0.0, -0.12) * CFrame.Angles(math.rad(-15), 0, math.rad(-20 * s)),
			P.Burlap,
			cloth
		)
		if side == "Right" then
			local wrist = CFrame.new(handCF.Position.X + 0.16, wristY + 0.02, -0.04)
				* CFrame.Angles(0, 0, math.rad(-70))
			strawTuft(hand, "WristStraw", wrist, 4, 0.24, 25, 11)
		end
	end

	------------------------------------------------------------------------------------------
	-- LEGS: stuffing balls, stuffed tubes, round feet with leather soles, patched left knee
	------------------------------------------------------------------------------------------
	for _, side in { "Left", "Right" } do
		local ul, ll, foot = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
		local ulCF, llCF, footCF = rig.CFrameOf(ul), rig.CFrameOf(ll), rig.CFrameOf(foot)
		rig.Ball(ul, "HipStuffing", 0.54, CFrame.new(rig.Joint(side .. "Hip")), P.Canvas, canvas)
		rig.Ellipsoid(ul, "Thigh", V(0.56, 0.96, 0.56), ulCF * CFrame.new(0, 0.02, 0), P.Canvas, canvas)
		rig.Ball(ll, "KneeStuffing", 0.5, CFrame.new(rig.Joint(side .. "Knee")), P.Canvas, canvas)
		rig.Ellipsoid(ll, "Shin", V(0.5, 0.9, 0.5), llCF * CFrame.new(0, 0.03, 0), P.Canvas, canvas)
		local ankleY = rig.Joint(side .. "Ankle").Y
		rig.Cyl(ll, "Cuff", 0.1, 0.46, CFrame.new(llCF.Position.X, ankleY + 0.05, 0) * upright, P.Rope, rope)
		local fp = footCF.Position
		local floorY = fp.Y - rig.Size(foot).Y / 2
		rig.Ellipsoid(foot, "Boot", V(0.56, 0.42, 0.88), CFrame.new(fp.X, floorY + 0.22, fp.Z - 0.02), P.Burlap, cloth)
		rig.Ellipsoid(foot, "Sole", V(0.54, 0.12, 0.86), CFrame.new(fp.X, floorY + 0.06, fp.Z - 0.02), P.Sole, {
			Role = "Dark",
			Material = Enum.Material.Leather,
		})
		rig.Attachment(foot, side .. "FootAttachment", CFrame.new(fp.X, floorY, fp.Z))
		if side == "Left" then
			local kneeY = rig.Joint(side .. "Knee").Y
			local patch = CFrame.new(llCF.Position.X, kneeY - 0.08, -0.262) * CFrame.Angles(0, 0, math.rad(-6))
			rig.Box(
				ll,
				"KneePatch",
				V(0.34, 0.3, 0.04),
				patch,
				P.Patch,
				{ Role = "Accent", Material = FABRIC, CastShadow = false }
			)
			local kp = patch * CFrame.new(0, 0, -0.024)
			for k, off in { V(-0.16, 0, 0), V(0.16, 0, 0), V(0, 0.14, 0), V(0, -0.14, 0) } do
				stitch(ll, "PatchStitch", kp * CFrame.new(off), 0.1, if k <= 2 then 0 else 90)
			end
			local ankle = CFrame.new(llCF.Position.X - 0.18, ankleY + 0.06, 0.05) * CFrame.Angles(0, 0, math.rad(70))
			strawTuft(ll, "AnkleStraw", ankle, 4, 0.22, 25, 21)
		end
	end
end

local blueprint: Blueprints.Blueprint = {
	Id = "Dummy",
	Family = "Human",
	Skeleton = "Human",
	Scale = 1,
	GroundOffset = STAND,
	Palette = {
		Burlap = rgb(206, 168, 116),
		Canvas = rgb(150, 112, 74),
		Rope = rgb(226, 199, 146),
		Thread = rgb(74, 48, 34),
		Straw = rgb(240, 208, 112),
		StrawDark = rgb(204, 160, 66),
		ButtonL = rgb(38, 34, 42),
		ButtonR = rgb(104, 50, 40),
		ButtonThread = rgb(236, 226, 205),
		Target = rgb(208, 38, 44),
		TargetLight = rgb(246, 240, 226),
		Pad = rgb(232, 214, 176),
		Patch = rgb(86, 118, 166),
		Sole = rgb(84, 56, 38),
		Wood = rgb(116, 78, 50),
		WoodLight = rgb(150, 104, 66),
		Bolt = rgb(120, 122, 128),
	},
	Build = build,
}

return blueprint
