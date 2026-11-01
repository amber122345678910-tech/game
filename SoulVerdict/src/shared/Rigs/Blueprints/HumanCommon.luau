--!strict
-- HumanCommon: the shared "fallen child" body of the seven SOUL-class blueprints (Human skeleton). [Lune-safe]
-- NOT a blueprint itself (Blueprints.List skips it): a class blueprint's Build calls HumanCommon.Body(rig, spec)
-- and then adds its signature items using the returned Info (face/hair frames, hair tie, chest frame, colours).
--
-- LOOK: big round head (~1.5) with full cheeks, small nose, cartoon eyes (open with highlights, half-lidded,
-- closed lines, happy/calm arcs, lashes), optional rosy cheeks; layered hair = a "helmet" cap the face pokes out of
-- (that frames the face like a bob) + bangs + locks/tufts (styles Bob, Ponytail, Spiky, Bun, Messy, Curly, Shaggy)
-- + a shine streak; sweater of stacked elliptic-cylinder bands (stripes continue across the sleeves at rest) with
-- ribbed collar, hem and cuffs; pants, shorts or tights; shoes with soles (Sneakers with laces, MaryJane,
-- Ballet, Loafers, Boots); mitten hands (open, or a fist that holds the weapon at RightGrip).
--
-- API
--   HumanCommon.Body(rig, spec: Spec) -> Info
--   HumanCommon.HoldWeapon(rig, weaponId, tiltDeg?) -> Model   weapon welded to RightHand at RightGrip
--   HumanCommon.Colors(rig) -> Colors                            palette + derived shades
--   HumanCommon.ECyl(rig, limb, name, cf, length, dy, dz, color, props) -> BasePart
--        elliptic cylinder (SpecialMesh Cylinder) whose axis is cf.XVector
--   HumanCommon.Band(rig, limb, name, pos, h, w, d, color, props) -> BasePart   vertical elliptic cylinder
--   HumanCommon.Tuft(rig, limb, name, base, dir, width, thick, length, normal, color, props) -> BasePart
--        ellipsoid growing from `base` along `dir` (thin side facing `normal`): hair tufts, spikes, ribbon loops
--   HumanCommon.Jitter(i, salt) -> number in [-1, 1] (deterministic, no RNG state)
-- PALETTE KEYS read (fallback): Skin, Hair, Sweater, Stripe (lighter Sweater), Pants, Tights (Pants), Sock, Shoe,
--   Sole, Lace, EyeDark, Iris (optional coloured iris), Cheek, Mouth. Rib/cuff/shine shades are DERIVED from their
--   base colour so every skin stays harmonious.

local Blueprints = require(script.Parent)
local PartKit = require(script.Parent.Parent.PartKit)
local Weapons = require(script.Parent.Parent.Props.Weapons)

type RigContext = Blueprints.RigContext
type Props = PartKit.Props

local V = Vector3.new
local CF = CFrame.new
local rgb = Color3.fromRGB
local rad = math.rad
local shade = PartKit.Shade
local mix = PartKit.Mix

local FABRIC = Enum.Material.Fabric
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder X axis -> world Y
local WHITE = Color3.new(1, 1, 1)

local HumanCommon = {}

export type Spec = {
	Hair: string, -- "Bob" | "Ponytail" | "Spiky" | "Bun" | "Messy" | "Curly" | "Shaggy"
	Eyes: string?, -- "Open" (default) | "Narrow" | "Closed" | "Happy" | "Calm" | "Lashes"
	Mouth: string?, -- "Smile" (default) | "Gentle" | "Grin" | "Wide" | "Smirk" | "Flat"
	Brows: string?, -- "None" (default) | "Soft" | "Bold" | "Worried"
	Cheeks: boolean?, -- rosy blush
	Ears: boolean?, -- visible ears (short or tied-back hair)
	Stripes: { { number } }?, -- {{t0, t1}, ...}: sweater space, 0 = top of the hem rib, 1 = shoulder line
	Legs: string?, -- "Pants" (default) | "Shorts" | "Tights"
	Shoes: string?, -- "Sneakers" (default) | "MaryJane" | "Ballet" | "Loafers" | "Boots"
	LeftHand: string?, -- "Open" (default) | "Fist" | "None"
	RightHand: string?, -- default "Fist" with a weapon, else "Open"
	Weapon: string?, -- Weapons id held in the right hand
	WeaponTilt: number?, -- degrees about the hand X axis (negative tips the tip down), default -20
	Collar: boolean?, -- default true
	HemLift: number?, -- raise the sweater hem (studs, default 0): cropped sweater over a tutu/apron
}

export type Colors = {
	Skin: Color3,
	SkinShade: Color3,
	Hair: Color3,
	HairShine: Color3,
	HairDark: Color3,
	Sweater: Color3,
	Stripe: Color3,
	Rib: Color3,
	Pants: Color3,
	PantsDark: Color3,
	Tights: Color3,
	Sock: Color3,
	Shoe: Color3,
	Sole: Color3,
	Lace: Color3,
	EyeDark: Color3,
	Iris: Color3?,
	Cheek: Color3,
	Mouth: Color3,
}

export type Info = {
	Colors: Colors,
	FaceCF: CFrame, -- centre of the face ellipsoid
	FaceRadii: Vector3,
	HairCF: CFrame, -- centre of the hair helmet ellipsoid
	HairRadii: Vector3,
	HairTie: CFrame?, -- ponytail tie / bun base (style dependent)
	HeadTopY: number, -- highest point of hair/head
	NeckY: number,
	ChestCF: CFrame, -- sweater front at heart height, LookVector = outward
	SweaterSize: (y: number) -> (number, number), -- width, depth of the sweater body at height y
	HemY: number, -- bottom of the sweater
	Weapon: Model?,
}

-- Deterministic jitter in [-1, 1].
function HumanCommon.Jitter(i: number, salt: number): number
	local x = math.sin(i * 127.1 + salt * 311.7) * 43758.5453
	return (x - math.floor(x)) * 2 - 1
end
local jitter = HumanCommon.Jitter

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function HumanCommon.Colors(rig: RigContext): Colors
	local P = rig.Palette
	local function key(k: string, fallback: Color3): Color3
		local c = P[k]
		return if c ~= nil then c else fallback
	end
	local skin = key("Skin", rgb(246, 210, 180))
	local hair = key("Hair", rgb(112, 72, 46))
	local sweater = key("Sweater", rgb(70, 110, 190))
	local pants = key("Pants", rgb(74, 62, 92))
	return {
		Skin = skin,
		SkinShade = mix(skin, rgb(214, 120, 110), 0.22),
		Hair = hair,
		HairShine = mix(hair, WHITE, 0.3),
		HairDark = shade(hair, -0.22),
		Sweater = sweater,
		Stripe = key("Stripe", mix(sweater, WHITE, 0.55)),
		Rib = shade(sweater, -0.14),
		Pants = pants,
		PantsDark = shade(pants, -0.18),
		Tights = key("Tights", pants),
		Sock = key("Sock", rgb(244, 240, 232)),
		Shoe = key("Shoe", rgb(108, 66, 44)),
		Sole = key("Sole", rgb(58, 44, 40)),
		Lace = key("Lace", rgb(246, 242, 234)),
		EyeDark = key("EyeDark", rgb(38, 26, 32)),
		Iris = P.Iris,
		Cheek = key("Cheek", rgb(244, 142, 146)),
		Mouth = key("Mouth", rgb(122, 46, 50)),
	}
end

-- Primitive helpers -------------------------------------------------------------------------------

function HumanCommon.ECyl(
	rig: RigContext,
	limb: string | BasePart,
	name: string,
	cf: CFrame,
	length: number,
	dy: number,
	dz: number,
	color: Color3,
	props: Props?
): BasePart
	local part = rig.Ellipsoid(limb, name, V(length, dy, dz), cf, color, props)
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.MeshType = Enum.MeshType.Cylinder
	end
	return part
end
local ecyl = HumanCommon.ECyl

function HumanCommon.Band(
	rig: RigContext,
	limb: string | BasePart,
	name: string,
	pos: Vector3,
	h: number,
	w: number,
	d: number,
	color: Color3,
	props: Props?
): BasePart
	return ecyl(rig, limb, name, CF(pos) * UPRIGHT, h, w, d, color, props)
end
local band = HumanCommon.Band

function HumanCommon.Tuft(
	rig: RigContext,
	limb: string | BasePart,
	name: string,
	base: Vector3,
	dir: Vector3,
	width: number,
	thick: number,
	length: number,
	normal: Vector3,
	color: Color3,
	props: Props?
): BasePart
	local u = dir.Unit
	return rig.Ellipsoid(limb, name, V(width, thick, length), rig.LookFrame(base + u * (length / 2), u, normal), color, props)
end
local tuft = HumanCommon.Tuft

-- Stacked vertical tube from yTop down to yBottom (diameters dTop -> dBottom), split into bands at the stripe
-- boundaries so stripes sit flush (no z-fighting). stripes are world-Y intervals {y0, y1}.
local function stackedTube(
	rig: RigContext,
	limb: string,
	name: string,
	x: number,
	z: number,
	yTop: number,
	yBottom: number,
	dTop: number,
	dBottom: number,
	depthRatio: number,
	stripes: { { number } },
	base: Color3,
	stripe: Color3
)
	local cuts: { number } = { yBottom, yTop }
	for _, s in stripes do
		for _, y in s do
			if y > yBottom + 0.01 and y < yTop - 0.01 then
				table.insert(cuts, y)
			end
		end
	end
	table.sort(cuts)
	local cloth: Props = { Role = "Cloth", Material = FABRIC }
	local alt: Props = { Role = "ClothAlt", Material = FABRIC }
	for i = 1, #cuts - 1 do
		local y0, y1 = cuts[i], cuts[i + 1]
		if y1 - y0 > 0.005 then
			local ym = (y0 + y1) / 2
			local inStripe = false
			for _, s in stripes do
				if ym > s[1] and ym < s[2] then
					inStripe = true
				end
			end
			local t = (ym - yBottom) / (yTop - yBottom)
			local d = lerp(dBottom, dTop, t)
			band(
				rig,
				limb,
				name .. (if inStripe then "Stripe" else ""),
				V(x, ym, z),
				y1 - y0,
				d,
				d * depthRatio,
				if inStripe then stripe else base,
				if inStripe then alt else cloth
			)
		end
	end
end

-- HEAD + FACE ------------------------------------------------------------------------------------

type Face = { CF: CFrame, R: Vector3 }

local function buildFace(rig: RigContext, spec: Spec, C: Colors): Face
	local hc = rig.CFrameOf("Head").Position
	local skin: Props = { Role = "Skin" }
	local faceCF = CF(hc + V(0, -0.05, -0.1))
	local R = V(0.67, 0.64, 0.63)
	rig.Ellipsoid("Head", "Face", R * 2, faceCF, C.Skin, skin)
	rig.Ellipsoid("Head", "Cheeks", V(1.28, 0.8, 0.94), CF(hc + V(0, -0.3, -0.07)), C.Skin, skin)
	local dark: Props = { Role = "Dark", CastShadow = false }
	local shine: Props = { Role = "Eye", CastShadow = false }

	-- ears
	if spec.Ears then
		for _, s in { -1, 1 } do
			local side = if s < 0 then "Left" else "Right"
			local ear = CF(hc + V(0.655 * s, -0.08, 0.02)) * CFrame.Angles(0, rad(-12 * s), 0)
			rig.Ellipsoid("Head", side .. "Ear", V(0.15, 0.3, 0.22), ear, C.Skin, skin)
			rig.Ellipsoid("Head", side .. "EarIn", V(0.06, 0.18, 0.12), ear * CF(0.05 * s, 0, -0.01), C.SkinShade, {
				Role = "Skin",
				CastShadow = false,
			})
		end
	end

	-- nose
	rig.Ellipsoid(
		"Head",
		"Nose",
		V(0.15, 0.11, 0.11),
		rig.OnEllipsoid(faceCF, R, 0, -12, 0.035),
		mix(C.Skin, C.SkinShade, 0.35),
		skin
	)

	-- eyes
	local eyes = spec.Eyes or "Open"
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local cf = rig.OnEllipsoid(faceCF, R, 23 * s, -3, 0.035)
		if eyes == "Open" or eyes == "Narrow" then
			-- layers sit almost flush with the face (front faces at +0.00 .. +0.01) so a lid can cover them
			rig.Ellipsoid("Head", side .. "EyeBase", V(0.17, 0.25, 0.085), cf, C.EyeDark, { Role = "Dark" })
			if C.Iris then
				local iris = C.Iris :: Color3
				rig.Ellipsoid("Head", side .. "Iris", V(0.135, 0.19, 0.05), cf * CF(0, -0.02, -0.015), iris, {
					Role = "Eye",
					CastShadow = false,
				})
				rig.Ellipsoid("Head", side .. "Pupil", V(0.07, 0.11, 0.04), cf * CF(0, -0.025, -0.025), C.EyeDark, dark)
			end
			local shineY = if eyes == "Narrow" then -0.005 else 0.055
			rig.Ball("Head", side .. "EyeShine", 0.065, cf * CF(0.03, shineY, -0.028), WHITE, shine)
			rig.Ball("Head", side .. "EyeShine2", 0.032, cf * CF(-0.035, -0.06, -0.025), WHITE, shine)
			if eyes == "Narrow" then
				-- heavy upper lid: a thin skin cap over the top of the eye + dark lash line, tilted for a sly look
				local lid = cf * CFrame.Angles(0, 0, rad(-10 * s))
				rig.Ellipsoid("Head", side .. "Lid", V(0.25, 0.15, 0.05), lid * CF(0, 0.1, -0.03), C.Skin, skin)
				rig.Box("Head", side .. "LidLine", V(0.23, 0.032, 0.05), lid * CF(0, 0.032, -0.03), C.EyeDark, dark)
			end
		elseif eyes == "Closed" then
			rig.Box("Head", side .. "EyeLine", V(0.2, 0.036, 0.05), cf * CF(0, 0, -0.035) * CFrame.Angles(0, 0, rad(-7 * s)), C.EyeDark, dark)
		elseif eyes == "Happy" then
			rig.Arc("Head", side .. "EyeArc", cf * CF(0, -0.05, -0.035), 0.085, 25, 155, 4, 0.04, 0.05, C.EyeDark, {
				Role = "Dark",
				CastShadow = false,
				Joints = true,
			})
		else -- Calm / Lashes: downward arcs (closed, content)
			rig.Arc("Head", side .. "EyeArc", cf * CF(0, 0.05, -0.035), 0.09, 205, 335, 4, 0.038, 0.05, C.EyeDark, {
				Role = "Dark",
				CastShadow = false,
				Joints = true,
			})
			if eyes == "Lashes" then
				for k = 1, 2 do
					local a = rad(if s > 0 then (338 + k * 10) else (202 - k * 10))
					local p = cf * CF(math.cos(a) * 0.1, 0.05 + math.sin(a) * 0.1, -0.035)
					rig.Box("Head", side .. "Lash" .. k, V(0.07, 0.028, 0.045), p * CFrame.Angles(0, 0, a + rad(s * 30)), C.EyeDark, dark)
				end
			end
		end
		rig.Attachment("Head", side .. "Eye", cf * CF(0, 0, -0.05))

		-- brows
		local brows = spec.Brows or "None"
		if brows ~= "None" then
			local bcf = rig.OnEllipsoid(faceCF, R, 23 * s, 17, 0.0)
			local tilt = if brows == "Bold" then 14 elseif brows == "Worried" then -14 else 4
			local size = if brows == "Bold" then V(0.24, 0.065, 0.06) else V(0.2, 0.042, 0.05)
			rig.Box("Head", side .. "Brow", size, bcf * CFrame.Angles(0, 0, rad(tilt * s)), C.HairDark, {
				Role = "Hair",
				CastShadow = false,
			})
		end

		-- rosy cheeks
		if spec.Cheeks then
			rig.Ellipsoid(
				"Head",
				side .. "Blush",
				V(0.25, 0.15, 0.06),
				rig.OnEllipsoid(faceCF, R, 41 * s, -15, 0.024),
				C.Cheek,
				{ Role = "Detail", CastShadow = false }
			)
		end
	end

	-- mouth
	local mouth = spec.Mouth or "Smile"
	local m = rig.OnEllipsoid(faceCF, R, 0, -25, 0.004)
	local stroke: Props = { Role = "Dark", CastShadow = false, Joints = true }
	if mouth == "Grin" then
		rig.Ellipsoid("Head", "MouthOpen", V(0.32, 0.2, 0.08), m * CF(0, -0.01, 0.015), C.Mouth, dark)
		rig.Ellipsoid("Head", "Tongue", V(0.16, 0.08, 0.06), m * CF(0.02, -0.06, -0.006), rgb(232, 112, 118), dark)
		rig.Box("Head", "Teeth", V(0.3, 0.075, 0.05), m * CF(0, 0.05, -0.006), WHITE, dark)
	elseif mouth == "Wide" then
		-- too-wide thin smile with sharp upturned corners
		rig.Arc("Head", "MouthLine", m * CF(0, 0.15, 0), 0.23, 213, 327, 6, 0.028, 0.05, C.Mouth, stroke)
		for _, s in { -1, 1 } do
			local a = rad(if s > 0 then 327 else 213)
			local p = m * CF(math.cos(a) * 0.23, 0.15 + math.sin(a) * 0.23, 0)
			rig.Box("Head", "MouthCorner", V(0.075, 0.026, 0.05), p * CF(0.02 * s, 0.022, 0) * CFrame.Angles(0, 0, rad(62 * s)), C.Mouth, dark)
		end
	elseif mouth == "Smirk" then
		rig.Arc("Head", "MouthLine", m * CF(0.04, 0.07, 0) * CFrame.Angles(0, 0, rad(10)), 0.13, 228, 330, 4, 0.034, 0.05, C.Mouth, stroke)
	elseif mouth == "Gentle" then
		rig.Arc("Head", "MouthLine", m * CF(0, 0.07, 0), 0.1, 222, 318, 4, 0.032, 0.05, C.Mouth, stroke)
	elseif mouth == "Flat" then
		rig.Box("Head", "MouthLine", V(0.14, 0.03, 0.05), m, C.Mouth, dark)
	else -- Smile
		rig.Arc("Head", "MouthLine", m * CF(0, 0.09, 0), 0.13, 215, 325, 5, 0.034, 0.05, C.Mouth, stroke)
	end
	rig.Attachment("Head", "Mouth", m * CF(0, 0, -0.04))
	return { CF = faceCF, R = R }
end

-- HAIR -------------------------------------------------------------------------------------------

type HairResult = { CF: CFrame, R: Vector3, Tie: CFrame?, Top: number }

local function buildHair(rig: RigContext, spec: Spec, C: Colors, _face: Face): HairResult
	local hc = rig.CFrameOf("Head").Position
	local hairP: Props = { Role = "Hair" }
	local small: Props = { Role = "Hair", CastShadow = false }
	local style = spec.Hair
	local function helmet(size: Vector3, offset: Vector3): (CFrame, Vector3)
		local cf = CF(hc + offset)
		rig.Ellipsoid("Head", "HairCap", size, cf, C.Hair, hairP)
		return cf, size / 2
	end
	local function on(cf: CFrame, r: Vector3, yaw: number, pitch: number, inset: number?): CFrame
		return rig.OnEllipsoid(cf, r, yaw, pitch, inset)
	end
	-- a spike/tuft that grows OUT of the helmet at (yaw, pitch), pointing along the surface normal found at
	-- (yaw + dirYaw, pitch + dirPitch)
	local function capTuft(
		name: string,
		cf: CFrame,
		r: Vector3,
		yaw: number,
		pitch: number,
		dirYaw: number,
		dirPitch: number,
		w: number,
		t: number,
		len: number,
		color: Color3?,
		inset: number?
	): BasePart
		local at = on(cf, r, yaw, pitch, inset or 0.12)
		local dir = on(cf, r, yaw + dirYaw, pitch + dirPitch).LookVector
		return tuft(rig, "Head", name, at.Position, dir, w, t, len, at.UpVector, color or C.Hair, hairP)
	end
	-- a lock LYING on the head: from (yaw, pitch) on the helmet to the tip (yaw2, pitch2) held `tipOut` above the
	-- surface (so it covers the face where the face pokes out of the helmet); lift tilts it outward
	local function lay(
		name: string,
		cf: CFrame,
		r: Vector3,
		yaw: number,
		pitch: number,
		yaw2: number,
		pitch2: number,
		w: number,
		t: number,
		tipOut: number?,
		lift: number?,
		color: Color3?
	): BasePart
		local a = on(cf, r, yaw, pitch, 0.04)
		local b = on(cf, r, yaw2, pitch2, -(tipOut or 0.08))
		local chord = b.Position - a.Position
		local n = (a.LookVector + b.LookVector).Unit
		local dir = (chord.Unit + n * (lift or 0)).Unit
		return tuft(rig, "Head", name, a.Position, dir, w, t, chord.Magnitude + t * 0.5, n, color or C.Hair, hairP)
	end
	local function shine(cf: CFrame, r: Vector3, yaw: number, pitch: number, w: number, roll: number)
		rig.Ellipsoid(
			"Head",
			"HairShine",
			V(w, 0.075, 0.05),
			on(cf, r, yaw, pitch, 0.012) * CFrame.Angles(0, 0, rad(roll)),
			C.HairShine,
			small
		)
	end
	local top = hc.Y + 0.75
	local tie: CFrame? = nil
	local cf: CFrame, r: Vector3

	if style == "Bob" then
		cf, r = helmet(V(1.54, 1.38, 1.48), V(0, 0.12, 0.07))
		-- parted fringe: locks sweep down and outward from a centre part
		for i, b in { { 10, 22 }, { 26, 42 }, { 42, 62 }, { -10, -22 }, { -26, -42 }, { -42, -62 } } do
			lay("Bang" .. i, cf, r, b[1], 54 - math.abs(b[1]) * 0.15, b[2], 10, 0.32, 0.12, 0.07, 0.06)
		end
		for _, s in { -1, 1 } do
			local side = if s < 0 then "Left" else "Right"
			local lock = CF(hc + V(0.67 * s, -0.2, 0.03)) * CFrame.Angles(rad(-4), 0, rad(6 * s))
			rig.Ellipsoid("Head", side .. "Lock", V(0.3, 0.72, 0.68), lock, C.Hair, hairP)
			rig.Ellipsoid("Head", side .. "Flick", V(0.2, 0.13, 0.46), lock * CF(0.07 * s, -0.31, -0.04) * CFrame.Angles(0, 0, rad(-24 * s)), C.Hair, hairP)
		end
		rig.Ellipsoid("Head", "HairBack", V(1.4, 0.8, 0.74), CF(hc + V(0, -0.2, 0.36)), C.Hair, hairP)
		shine(cf, r, -24, 46, 0.42, 18)
		shine(cf, r, 22, 48, 0.3, -16)
		top = cf.Position.Y + r.Y
	elseif style == "Ponytail" then
		cf, r = helmet(V(1.52, 1.36, 1.48), V(0, 0.12, 0.07))
		-- straight-cut fringe
		for i = 1, 5 do
			local yaw = -40 + (i - 1) * 20
			lay("Bang" .. i, cf, r, yaw * 0.8, 62, yaw, 20, 0.34, 0.13, 0.08, 0.08)
		end
		for _, s in { -1, 1 } do
			local side = if s < 0 then "Left" else "Right"
			local lock = CF(hc + V(0.64 * s, -0.12, 0.04)) * CFrame.Angles(0, 0, rad(5 * s))
			rig.Ellipsoid("Head", side .. "Lock", V(0.3, 0.66, 0.66), lock, C.Hair, hairP)
		end
		-- high ponytail: tie at the back-top, a tapering swish down the back
		local tieCF = rig.LookFrame(hc + V(0, 0.5, 0.6), V(0, 0.6, 1), V(0, 1, 0))
		tie = tieCF
		local p0 = tieCF.Position
		local pts = { p0 + V(0, 0.02, 0.1), p0 + V(0, -0.24, 0.42), p0 + V(0, -0.72, 0.5), p0 + V(0, -1.16, 0.36) }
		local widths = { 0.42, 0.46, 0.36, 0.2 }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			tuft(rig, "Head", "Tail" .. i, a, b - a, widths[i], widths[i] * 0.8, (b - a).Magnitude + 0.2, V(0, 0, 1), C.Hair, hairP)
		end
		tuft(rig, "Head", "TailTip", pts[4], V(0.1, -1, -0.4), 0.18, 0.14, 0.26, V(0, 0, 1), C.Hair, hairP)
		shine(cf, r, -20, 44, 0.42, 16)
		top = cf.Position.Y + r.Y
	elseif style == "Spiky" then
		cf, r = helmet(V(1.48, 1.16, 1.42), V(0, 0.24, 0.08))
		-- spikes all over the crown, swept up and back (soft cartoon spikes: slim ellipsoids rooted in the cap);
		-- {yaw, pitch, length, width, back-sweep}
		local back, up = V(0, 0, 1), V(0, 1, 0)
		local spikes = {
			{ -34, 34, 0.42, 0.3, 0.15 },
			{ -11, 38, 0.48, 0.32, 0.15 },
			{ 13, 38, 0.48, 0.32, 0.15 },
			{ 35, 34, 0.42, 0.3, 0.15 },
			{ -56, 58, 0.5, 0.3, 0.6 },
			{ -20, 66, 0.56, 0.32, 0.6 },
			{ 20, 66, 0.56, 0.32, 0.6 },
			{ 56, 58, 0.5, 0.3, 0.6 },
			{ -122, 46, 0.48, 0.3, 0.9 },
			{ 180, 54, 0.5, 0.32, 0.9 },
			{ 122, 46, 0.48, 0.3, 0.9 },
			{ -90, 34, 0.38, 0.28, 0.5 },
			{ 90, 34, 0.38, 0.28, 0.5 },
		}
		for i, sp in spikes do
			local at = on(cf, r, sp[1], sp[2], 0.12)
			local dir = (at.LookVector + back * sp[5] + up * 0.35).Unit
			tuft(rig, "Head", "Spike" .. i, at.Position, dir, sp[4] * 0.85, sp[4] * 0.62, sp[3] + 0.12, at.UpVector, if i % 4 == 0 then C.HairDark else C.Hair, hairP)
		end
		-- sideburns
		for _, s in { -1, 1 } do
			rig.Ellipsoid("Head", "Sideburn", V(0.16, 0.36, 0.26), CF(hc + V(0.62 * s, -0.02, -0.1)) * CFrame.Angles(0, 0, rad(-4 * s)), C.Hair, hairP)
		end
		shine(cf, r, -18, 52, 0.36, 18)
		top = cf.Position.Y + r.Y + 0.42
	elseif style == "Bun" then
		cf, r = helmet(V(1.5, 1.32, 1.46), V(0, 0.13, 0.08))
		-- swept side fringe (part on the left)
		lay("Sweep", cf, r, -30, 66, 34, 30, 0.46, 0.14, 0.07, 0.05)
		lay("Sweep2", cf, r, -12, 70, 56, 22, 0.38, 0.13, 0.07, 0.05)
		lay("Sweep3", cf, r, -44, 60, -54, 26, 0.3, 0.12, 0.06, 0.05)
		for _, s in { -1, 1 } do
			local side = if s < 0 then "Left" else "Right"
			rig.Ellipsoid("Head", side .. "Temple", V(0.2, 0.54, 0.6), CF(hc + V(0.66 * s, 0.06, 0.08)), C.Hair, hairP)
		end
		local bunCF = CF(hc + V(0, 0.76, 0.2))
		tie = bunCF
		rig.Ellipsoid("Head", "Bun", V(0.66, 0.56, 0.62), bunCF * CF(0, 0.16, 0.04), C.Hair, hairP)
		rig.Ellipsoid("Head", "BunTwist", V(0.42, 0.3, 0.4), bunCF * CF(0.04, 0.4, 0.02) * CFrame.Angles(0, 0, rad(12)), C.Hair, hairP)
		shine(cf, r, -18, 40, 0.42, 14)
		top = bunCF.Position.Y + 0.56
	elseif style == "Messy" then
		cf, r = helmet(V(1.58, 1.42, 1.52), V(0, 0.11, 0.07))
		-- uneven fringe
		for i, yaw in { -40, -20, 0, 20, 40 } do
			local tipPitch = 18 + jitter(i, 3) * 7
			lay("Bang" .. i, cf, r, yaw * 0.8, 64, yaw + jitter(i, 7) * 14, tipPitch, 0.32, 0.13, 0.08, 0.14)
		end
		-- tufts sticking out all around (deterministic jitter)
		for i = 1, 12 do
			local yaw = -150 + (i - 1) * (300 / 11) + jitter(i, 11) * 10
			local pitch = 18 + math.abs(jitter(i, 13)) * 50
			if math.abs(yaw) < 50 and pitch < 40 then
				pitch += 26 -- keep the face clear
			end
			capTuft("Tuft" .. i, cf, r, yaw, pitch, jitter(i, 17) * 30, 40 + jitter(i, 19) * 25, 0.26, 0.12, 0.36 + math.abs(jitter(i, 23)) * 0.16, if i % 3 == 0 then C.HairDark else nil, 0.08)
		end
		-- cowlick
		capTuft("Cowlick", cf, r, 14, 78, 40, 50, 0.22, 0.1, 0.42, nil, 0.06)
		capTuft("Cowlick2", cf, r, -10, 80, -30, 56, 0.18, 0.09, 0.34, nil, 0.06)
		for _, s in { -1, 1 } do
			local side = if s < 0 then "Left" else "Right"
			rig.Ellipsoid("Head", side .. "Lock", V(0.32, 0.72, 0.68), CF(hc + V(0.66 * s, -0.18, 0.04)) * CFrame.Angles(0, 0, rad(9 * s)), C.Hair, hairP)
		end
		rig.Ellipsoid("Head", "HairBack", V(1.36, 0.8, 0.72), CF(hc + V(0, -0.18, 0.38)), C.Hair, hairP)
		shine(cf, r, -22, 44, 0.34, 18)
		top = cf.Position.Y + r.Y + 0.3
	elseif style == "Curly" then
		cf, r = helmet(V(1.5, 1.34, 1.46), V(0, 0.12, 0.08))
		-- a cloud of curls around the crown and down the sides/back
		local n = 0
		for ring, info in { { 70, 6, 0.48 }, { 44, 10, 0.43 }, { 16, 8, 0.4 } } do
			local pitch, count, d = info[1], info[2], info[3]
			for k = 1, count do
				local yaw = -180 + (k - 0.5) * 360 / count + ring * 13
				local wrapped = ((yaw + 180) % 360) - 180
				if not (pitch < 30 and math.abs(wrapped) < 60) then
					n += 1
					local at = on(cf, r, wrapped, pitch + jitter(k, ring) * 5, 0.1)
					rig.Ball("Head", "Curl" .. n, d + jitter(k, ring + 5) * 0.05, at, if n % 4 == 0 then C.HairDark else C.Hair, hairP)
				end
			end
		end
		-- curly bangs
		for i, yaw in { -30, -6, 18, 38 } do
			rig.Ball("Head", "BangCurl" .. i, 0.3, on(cf, r, yaw, 30 + (if i % 2 == 0 then 4 else 0), 0.08), C.Hair, hairP)
		end
		for _, s in { -1, 1 } do
			for k = 1, 2 do
				rig.Ball("Head", "SideCurl", 0.36 - k * 0.04, CF(hc + V(0.66 * s, -0.08 - k * 0.24, 0.12)), C.Hair, hairP)
			end
		end
		shine(cf, r, -20, 60, 0.3, 16)
		top = cf.Position.Y + r.Y + 0.22
	elseif style == "Shaggy" then
		cf, r = helmet(V(1.56, 1.38, 1.5), V(0, 0.12, 0.08))
		for i, yaw in { -36, -14, 8, 30 } do
			lay("Bang" .. i, cf, r, yaw * 0.7, 60, yaw * 1.1 + 6, 16 + jitter(i, 2) * 5, 0.32, 0.13, 0.08, 0.1)
		end
		-- shaggy layers around the sides and the nape, pointing down
		for i = 1, 9 do
			local yaw = -120 + (i - 1) * 30
			if math.abs(yaw) > 50 then
				local at = on(cf, r, yaw, -12, 0.1)
				local dir = (V(0, -1, 0) + at.LookVector * 0.35 + V(jitter(i, 9) * 0.2, 0, 0)).Unit
				tuft(rig, "Head", "Shag" .. i, at.Position, dir, 0.3, 0.14, 0.42, at.LookVector, if i % 3 == 0 then C.HairDark else C.Hair, hairP)
			end
		end
		shine(cf, r, -22, 44, 0.36, 18)
		top = cf.Position.Y + r.Y
	else
		error(("HumanCommon: unknown hair style '%s'"):format(tostring(style)))
	end
	return { CF = cf, R = r, Tie = tie, Top = top }
end

-- SWEATER + ARMS ---------------------------------------------------------------------------------

type Sweater = { Size: (y: number) -> (number, number), HemY: number, Chest: CFrame }

local function buildSweater(rig: RigContext, spec: Spec, C: Colors): Sweater
	local cloth: Props = { Role = "Cloth", Material = FABRIC }
	local rib: Props = { Role = "Trim", Material = FABRIC }
	local waistY = rig.Joint("Waist").Y
	local neckY = rig.Joint("Neck").Y
	local shoulder = rig.Joint("RightShoulder")
	local hemY = waistY - 0.19 + (spec.HemLift or 0)
	local ribTop = hemY + 0.15
	local yokeY = shoulder.Y - 0.1
	local function size(y: number): (number, number)
		local t = math.clamp((y - ribTop) / (yokeY - ribTop), 0, 1)
		return lerp(1.36, 1.26, t), lerp(0.9, 0.82, t)
	end

	-- stripes in world Y
	local stripes: { { number } } = {}
	for _, s in spec.Stripes or {} do
		table.insert(stripes, { lerp(ribTop, yokeY, s[1]), lerp(ribTop, yokeY, s[2]) })
	end

	-- body bands (bottom -> top) and the yoke cap
	local cuts: { number } = { ribTop, yokeY }
	for _, s in stripes do
		table.insert(cuts, s[1])
		table.insert(cuts, s[2])
	end
	table.sort(cuts)
	for i = 1, #cuts - 1 do
		local y0, y1 = cuts[i], cuts[i + 1]
		if y1 - y0 > 0.005 then
			local ym = (y0 + y1) / 2
			local inStripe = false
			for _, s in stripes do
				if ym > s[1] and ym < s[2] then
					inStripe = true
				end
			end
			local w, d = size(ym)
			band(
				rig,
				"UpperTorso",
				if inStripe then "SweaterStripe" else "Sweater",
				V(0, ym, 0.01),
				y1 - y0,
				w,
				d,
				if inStripe then C.Stripe else C.Sweater,
				if inStripe then { Role = "ClothAlt", Material = FABRIC } else cloth
			)
		end
	end
	local yw, yd = size(yokeY)
	rig.Ellipsoid("UpperTorso", "Yoke", V(yw + 0.14, 0.6, yd + 0.02), CF(0, yokeY, 0.01), C.Sweater, cloth)
	-- ribbed hem: band + vertical rib lines
	local hw, hd = size(ribTop)
	band(rig, "UpperTorso", "Hem", V(0, hemY + 0.075, 0.01), 0.15, hw + 0.04, hd + 0.04, C.Rib, rib)
	-- collar + neck
	if spec.Collar ~= false then
		band(rig, "UpperTorso", "Collar", V(0, neckY - 0.01, 0.0), 0.13, 0.66, 0.56, C.Rib, rib)
		band(rig, "UpperTorso", "CollarRoll", V(0, neckY + 0.05, 0.0), 0.05, 0.6, 0.5, shade(C.Rib, 0.06), rib)
	end
	rig.Cyl("Head", "Neck", 0.34, 0.4, CF(0, neckY + 0.06, 0.02) * UPRIGHT, C.Skin, { Role = "Skin" })

	-- sleeves
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local ua, la = side .. "UpperArm", side .. "LowerArm"
		local sh, el, wr = rig.Joint(side .. "Shoulder"), rig.Joint(side .. "Elbow"), rig.Joint(side .. "Wrist")
		local x = sh.X
		rig.Ball(ua, "ShoulderCap", 0.44, CF(sh) * CF(0.0, -0.08, 0), C.Sweater, cloth)
		stackedTube(rig, ua, "Sleeve", x, 0, sh.Y - 0.08, el.Y + 0.02, 0.43, 0.41, 1, stripes, C.Sweater, C.Stripe)
		rig.Ball(la, "Elbow", 0.41, CF(el), C.Sweater, cloth)
		stackedTube(rig, la, "Forearm", x, 0, el.Y, wr.Y + 0.14, 0.4, 0.38, 1, stripes, C.Sweater, C.Stripe)
		band(rig, la, "Cuff", V(x, wr.Y + 0.08, 0), 0.13, 0.42, 0.42, C.Rib, rib)
		-- a soft fold above the cuff
		band(rig, la, "CuffFold", V(x, wr.Y + 0.17, 0), 0.04, 0.4, 0.4, shade(C.Sweater, -0.05), cloth)
	end

	local chestY = lerp(ribTop, yokeY, 0.62)
	local _, cd = size(chestY)
	local chest = rig.LookFrame(V(0, chestY, 0.01 - cd / 2), V(0, 0, -1))
	return { Size = size, HemY = hemY, Chest = chest }
end

-- HANDS ------------------------------------------------------------------------------------------

local function buildHand(rig: RigContext, side: string, mode: string, C: Colors): CFrame
	local s = if side == "Left" then -1 else 1
	local hand = side .. "Hand"
	local wr = rig.Joint(side .. "Wrist")
	local x = wr.X
	local skin: Props = { Role = "Skin" }
	local grip = CF(x, wr.Y - 0.29, 0)
	if mode == "Open" then
		-- palm + three chubby fingers (slightly curled) + thumb
		rig.Ellipsoid(hand, "Palm", V(0.2, 0.28, 0.3), CF(x, wr.Y - 0.15, 0), C.Skin, skin)
		for k, z in { -0.085, 0.0, 0.085 } do
			local len = if k == 2 then 0.24 else 0.21
			rig.Ellipsoid(
				hand,
				"Finger" .. k,
				V(0.11, len, 0.105),
				CF(x - 0.005 * s, wr.Y - 0.3 - (if k == 2 then 0.015 else 0), z - 0.01) * CFrame.Angles(rad(-8), 0, rad(-5 * s)),
				C.Skin,
				skin
			)
		end
		rig.Ellipsoid(
			hand,
			"Thumb",
			V(0.1, 0.2, 0.11),
			CF(x - 0.06 * s, wr.Y - 0.19, -0.14) * CFrame.Angles(rad(24), 0, rad(16 * s)),
			C.Skin,
			skin
		)
		grip = CF(x, wr.Y - 0.25, 0)
	elseif mode == "Fist" then
		rig.Ellipsoid(hand, "Fist", V(0.28, 0.3, 0.32), CF(x, wr.Y - 0.24, 0), C.Skin, skin)
		for k, z in { -0.09, 0.0, 0.09 } do
			rig.Ellipsoid(hand, "Knuckle" .. k, V(0.13, 0.14, 0.12), CF(x + 0.06 * s, wr.Y - 0.36, z), C.Skin, skin)
		end
		rig.Ellipsoid(
			hand,
			"Thumb",
			V(0.12, 0.13, 0.2),
			CF(x - 0.09 * s, wr.Y - 0.22, -0.12) * CFrame.Angles(rad(-20), 0, 0),
			C.Skin,
			skin
		)
		grip = CF(x, wr.Y - 0.29, 0)
	end
	rig.Attachment(hand, side .. "Grip", grip)
	return grip
end

function HumanCommon.HoldWeapon(rig: RigContext, weaponId: string, tiltDeg: number?): Model
	local hand = rig.Limb("RightHand")
	local gripAtt = hand:FindFirstChild("RightGrip")
	local gripCF = if gripAtt and gripAtt:IsA("Attachment") then hand.CFrame * gripAtt.CFrame else hand.CFrame
	gripCF = gripCF * CFrame.Angles(rad(tiltDeg or -20), 0, 0)
	local weapon = Weapons.Build(weaponId, rig.Palette)
	for _, d in weapon:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = gripCF * d.CFrame
		end
	end
	weapon.Parent = hand
	local primary = weapon.PrimaryPart
	assert(primary ~= nil, "HumanCommon.HoldWeapon: weapon has no PrimaryPart")
	rig.Add(hand, primary)
	return weapon
end

-- LEGS + SHOES -----------------------------------------------------------------------------------

local function buildLegs(rig: RigContext, spec: Spec, C: Colors)
	local legs = spec.Legs or "Pants"
	local pantsP: Props = { Role = "ClothAlt", Material = FABRIC }
	local skin: Props = { Role = "Skin" }
	local waistY = rig.Joint("Waist").Y
	local seatColor = if legs == "Tights" then C.Tights else C.Pants
	band(rig, "LowerTorso", "Hips", V(0, waistY - 0.2, 0.02), 0.36, 1.22, 0.8, seatColor, pantsP)
	rig.Ellipsoid("LowerTorso", "Seat", V(0.62, 0.36, 0.7), CF(0, waistY - 0.4, 0.03), seatColor, pantsP)
	if legs ~= "Tights" then
		-- fly seam + front pockets
		rig.Box("LowerTorso", "Fly", V(0.03, 0.17, 0.03), CF(0, waistY - 0.3, -0.385), C.PantsDark, {
			Role = "Detail",
			CastShadow = false,
		})
	end
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local ul, ll = side .. "UpperLeg", side .. "LowerLeg"
		local hip, knee, ankle = rig.Joint(side .. "Hip"), rig.Joint(side .. "Knee"), rig.Joint(side .. "Ankle")
		local x = hip.X
		if legs == "Pants" then
			band(rig, ul, "PantLeg", V(x, (hip.Y + 0.06 + knee.Y) / 2, 0.01), hip.Y + 0.06 - knee.Y, 0.55, 0.55, C.Pants, pantsP)
			rig.Ball(ll, "Knee", 0.51, CF(knee) + V(0, 0, 0.0), C.Pants, pantsP)
			band(rig, ll, "Shin", V(x, (knee.Y + ankle.Y + 0.14) / 2, 0.01), knee.Y - ankle.Y - 0.14, 0.49, 0.49, C.Pants, pantsP)
			if spec.Shoes ~= "Boots" then -- trousers are tucked into boots
				band(rig, ll, "PantCuff", V(x, ankle.Y + 0.13, 0.01), 0.15, 0.54, 0.54, shade(C.Pants, 0.1), pantsP)
				band(rig, ll, "PantCuffEdge", V(x, ankle.Y + 0.2, 0.01), 0.03, 0.55, 0.55, C.PantsDark, pantsP)
			end
		elseif legs == "Shorts" then
			local hemY = hip.Y - 0.42
			band(rig, ul, "ShortLeg", V(x, (hip.Y + 0.06 + hemY) / 2, 0.01), hip.Y + 0.06 - hemY, 0.58, 0.58, C.Pants, pantsP)
			band(rig, ul, "ShortCuff", V(x, hemY + 0.03, 0.01), 0.1, 0.62, 0.62, shade(C.Pants, 0.08), pantsP)
			rig.Ellipsoid(ul, "Thigh", V(0.4, hemY - knee.Y + 0.3, 0.4), CF(x, (hemY + knee.Y) / 2, 0.01), C.Skin, skin)
			rig.Ball(ll, "Knee", 0.35, CF(knee) * CF(0, 0, -0.01), C.Skin, skin)
			local sockTop = ankle.Y + 0.34
			rig.Ellipsoid(ll, "Shin", V(0.37, knee.Y - sockTop + 0.3, 0.37), CF(x, (knee.Y + sockTop) / 2 + 0.02, 0.01), C.Skin, skin)
			band(rig, ll, "Sock", V(x, (sockTop + ankle.Y) / 2, 0.01), sockTop - ankle.Y, 0.39, 0.39, C.Sock, { Role = "Trim", Material = FABRIC })
			band(rig, ll, "SockRib", V(x, sockTop - 0.03, 0.01), 0.07, 0.41, 0.41, shade(C.Sock, -0.06), { Role = "Trim", Material = FABRIC })
		else -- Tights
			local tights: Props = { Role = "ClothAlt", Material = Enum.Material.SmoothPlastic }
			rig.Ellipsoid(ul, "Thigh", V(0.43, hip.Y - knee.Y + 0.42, 0.43), CF(x, (hip.Y + knee.Y) / 2 + 0.04, 0.01), C.Tights, tights)
			rig.Ball(ll, "Knee", 0.36, CF(knee) * CF(0, 0, -0.01), C.Tights, tights)
			rig.Ellipsoid(ll, "Shin", V(0.37, knee.Y - ankle.Y + 0.3, 0.37), CF(x, (knee.Y + ankle.Y) / 2 + 0.03, 0.01), C.Tights, tights)
		end
	end
end

local function buildShoes(rig: RigContext, spec: Spec, C: Colors)
	local style = spec.Shoes or "Sneakers"
	local leather: Props = { Role = "Accent", Material = Enum.Material.SmoothPlastic, Reflectance = 0.04 }
	local shoeP: Props = { Role = "Trim", Material = Enum.Material.SmoothPlastic }
	local soleP: Props = { Role = "Dark", Material = Enum.Material.Rubber }
	local laceP: Props = { Role = "Detail", CastShadow = false }
	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		local foot = side .. "Foot"
		local ankle = rig.Joint(side .. "Ankle")
		local x = ankle.X
		local fz = rig.CFrameOf(foot).Position.Z -- foot centre (toes forward)
		if style == "Sneakers" then
			rig.Ellipsoid(foot, "Shoe", V(0.5, 0.4, 0.84), CF(x, 0.21, fz + 0.02), C.Shoe, shoeP)
			rig.Ellipsoid(foot, "ToeCap", V(0.47, 0.28, 0.42), CF(x, 0.135, fz - 0.2), C.Lace, { Role = "Trim" })
			band(rig, foot, "Sole", V(x, 0.05, fz + 0.02), 0.1, 0.54, 0.88, C.Sole, soleP)
			band(rig, foot, "SoleStripe", V(x, 0.115, fz + 0.02), 0.03, 0.53, 0.87, C.Lace, { Role = "Trim" })
			band(rig, foot, "Collar", V(x, ankle.Y + 0.05, 0.0), 0.07, 0.44, 0.44, shade(C.Shoe, -0.12), shoeP)
			rig.Ellipsoid(foot, "Tongue", V(0.24, 0.12, 0.32), CF(x, 0.38, fz + 0.02) * CFrame.Angles(rad(-24), 0, 0), C.Shoe, shoeP)
			for k = 1, 3 do
				local z = fz + 0.06 - k * 0.09
				rig.Box(foot, "Lace" .. k, V(0.25, 0.035, 0.045), CF(x, 0.405 - k * 0.025, z) * CFrame.Angles(rad(-22), 0, 0), C.Lace, laceP)
			end
			-- bow
			for _, b in { -1, 1 } do
				rig.Ellipsoid(foot, "LaceBow", V(0.12, 0.05, 0.07), CF(x + 0.06 * b, 0.43, fz + 0.03) * CFrame.Angles(0, rad(20 * b), rad(-18 * b)), C.Lace, laceP)
			end
		elseif style == "MaryJane" then
			rig.Ellipsoid(foot, "Shoe", V(0.48, 0.34, 0.82), CF(x, 0.18, fz + 0.01), C.Shoe, leather)
			band(rig, foot, "Sole", V(x, 0.04, fz + 0.01), 0.08, 0.52, 0.86, C.Sole, soleP)
			rig.Box(foot, "Strap", V(0.5, 0.06, 0.09), CF(x, 0.31, fz + 0.03) * CFrame.Angles(rad(-14), 0, 0), shade(C.Shoe, -0.15), leather)
			rig.Ball(foot, "Button", 0.08, CF(x + 0.22 * s, 0.3, fz + 0.03), rgb(236, 220, 160), laceP)
		elseif style == "Ballet" then
			rig.Ellipsoid(foot, "Shoe", V(0.4, 0.3, 0.8), CF(x, 0.15, fz - 0.01), C.Shoe, { Role = "Accent", Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 })
			rig.Ellipsoid(foot, "Toe", V(0.3, 0.2, 0.3), CF(x, 0.12, fz - 0.25), shade(C.Shoe, 0.08), { Role = "Accent", Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 })
			band(rig, foot, "Sole", V(x, 0.03, fz - 0.01), 0.05, 0.38, 0.78, shade(C.Shoe, -0.25), soleP)
			rig.Ellipsoid(foot, "Opening", V(0.28, 0.06, 0.34), CF(x, 0.29, fz + 0.1), shade(C.Shoe, -0.18), { Role = "Accent", CastShadow = false })
			for _, b in { -1, 1 } do
				rig.Ellipsoid(foot, "Drawstring", V(0.09, 0.045, 0.06), CF(x + 0.045 * b, 0.3, fz - 0.06) * CFrame.Angles(0, rad(25 * b), 0), shade(C.Shoe, -0.1), laceP)
			end
		elseif style == "Loafers" then
			rig.Ellipsoid(foot, "Shoe", V(0.48, 0.36, 0.84), CF(x, 0.19, fz + 0.02), C.Shoe, leather)
			band(rig, foot, "Sole", V(x, 0.045, fz + 0.02), 0.09, 0.52, 0.88, C.Sole, soleP)
			rig.Box(foot, "Heel", V(0.4, 0.1, 0.22), CF(x, 0.05, fz + 0.3), C.Sole, soleP)
			rig.Box(foot, "Strap", V(0.36, 0.05, 0.1), CF(x, 0.35, fz - 0.06) * CFrame.Angles(rad(-20), 0, 0), shade(C.Shoe, -0.2), leather)
			rig.Box(foot, "Penny", V(0.14, 0.055, 0.045), CF(x, 0.355, fz - 0.06) * CFrame.Angles(rad(-20), 0, 0), rgb(214, 170, 86), laceP)
		elseif style == "Boots" then
			rig.Ellipsoid(foot, "Shoe", V(0.5, 0.38, 0.9), CF(x, 0.22, fz - 0.02), C.Shoe, leather)
			rig.Ellipsoid(foot, "Toe", V(0.36, 0.24, 0.36), CF(x, 0.16, fz - 0.32), shade(C.Shoe, -0.06), leather)
			band(rig, foot, "Sole", V(x, 0.04, fz - 0.02), 0.08, 0.52, 0.92, C.Sole, soleP)
			rig.Box(foot, "Heel", V(0.36, 0.16, 0.22), CF(x, 0.08, fz + 0.3), C.Sole, soleP)
			local shin = side .. "LowerLeg"
			band(rig, shin, "BootShaft", V(x, ankle.Y + 0.24, 0.01), 0.5, 0.55, 0.55, C.Shoe, leather)
			band(rig, shin, "BootTop", V(x, ankle.Y + 0.5, 0.01), 0.07, 0.59, 0.59, shade(C.Shoe, -0.2), leather)
			for _, b in { -1, 1 } do
				rig.Box(shin, "BootPull", V(0.03, 0.14, 0.09), CF(x + 0.28 * b, ankle.Y + 0.55, 0.01), shade(C.Shoe, -0.2), laceP)
			end
			rig.Box(shin, "BootStitch", V(0.04, 0.34, 0.565), CF(x, ankle.Y + 0.25, 0.01), shade(C.Shoe, 0.25), laceP)
		else
			error(("HumanCommon: unknown shoe style '%s'"):format(tostring(style)))
		end
		rig.Attachment(foot, side .. "FootAttachment", CF(x, 0, fz))
	end
end

-- ACCESSORY HELPERS ------------------------------------------------------------------------------

-- Ribbon bow: knot + two loops (with a shaded inner fold) + two tails. cf = knot centre, LookVector = the side the
-- bow faces, UpVector = up. 7 parts.
function HumanCommon.Bow(
	rig: RigContext,
	limb: string | BasePart,
	name: string,
	cf: CFrame,
	scale: number,
	color: Color3,
	props: Props?
): { BasePart }
	local k = scale
	local pr: Props = props or { Role = "Trim", Material = FABRIC }
	local inner = shade(color, -0.2)
	local out: { BasePart } = {}
	table.insert(out, rig.Ellipsoid(limb, name .. "Knot", V(0.15, 0.13, 0.11) * k, cf, shade(color, -0.06), pr))
	for _, s in { -1, 1 } do
		local loop = cf * CF(0.19 * s * k, 0.05 * k, 0.02 * k) * CFrame.Angles(0, rad(-12 * s), rad(24 * s))
		table.insert(out, rig.Ellipsoid(limb, name .. "Loop", V(0.4, 0.2, 0.09) * k, loop, color, pr))
		table.insert(out, rig.Ellipsoid(limb, name .. "Fold", V(0.2, 0.09, 0.05) * k, loop * CF(-0.05 * s * k, 0, -0.03 * k), inner, {
			Role = "Trim",
			Material = FABRIC,
			CastShadow = false,
		}))
		local tail = cf * CF(0.06 * s * k, -0.17 * k, 0.02 * k) * CFrame.Angles(0, 0, rad(-16 * s))
		table.insert(out, rig.Box(limb, name .. "Tail", V(0.085, 0.3, 0.025) * k, tail, color, pr))
	end
	return out
end

-- Knotted triangle scarf around the neck (bandanna / cowboy bandana): neck wrap, front flap, knot + ends,
-- optional polka dots. Welded to UpperTorso.
function HumanCommon.Neckerchief(rig: RigContext, info: Info, color: Color3, opts: { Dots: Color3?, Size: number?, KnotSide: number? }?)
	local o = opts or {}
	local k = o.Size or 1
	local cloth: Props = { Role = "Trim", Material = FABRIC }
	local y = info.NeckY - 0.08
	band(rig, "UpperTorso", "ScarfWrap", V(0, y, 0.0), 0.17, 0.78, 0.66, color, cloth)
	band(rig, "UpperTorso", "ScarfRoll", V(0, y + 0.07, 0.0), 0.06, 0.72, 0.6, shade(color, -0.12), cloth)
	-- front flap: two mirrored right-triangle wedges forming a downward point, leaning on the chest
	local w, h = 0.56 * k, 0.42 * k
	local _, d = info.SweaterSize(y - h / 2)
	local flapTop = CF(0, y - 0.04, 0.01 - d / 2 - 0.02) * CFrame.Angles(rad(-10), 0, 0)
	for _, s in { -1, 1 } do
		local half = flapTop * CF(w / 4 * s, -h / 2, 0) * CFrame.Angles(0, rad(-90 * s), 0) * CFrame.Angles(0, 0, math.pi)
		rig.Wedge("UpperTorso", "ScarfFlap", V(0.04, h, w / 2), half, color, cloth)
	end
	if o.Dots then
		for i, p in { V(-0.1, -0.1, 0), V(0.11, -0.12, 0), V(0, -0.24, 0), V(-0.02, -0.02, 0) } do
			rig.Disc("UpperTorso", "ScarfDot" .. i, 0.065 * k, 0.012, flapTop * CF(p * k + V(0, 0, -0.025)), o.Dots :: Color3, {
				Role = "Detail",
				CastShadow = false,
			})
		end
	end
	local ks = o.KnotSide or 0
	local knot = CF(0.2 * ks, y + 0.01, 0.01 - d / 2 - 0.05)
	rig.Ellipsoid("UpperTorso", "ScarfKnot", V(0.17, 0.14, 0.13) * k, knot, shade(color, -0.06), cloth)
	for _, s in { -1, 1 } do
		rig.Ellipsoid(
			"UpperTorso",
			"ScarfEnd",
			V(0.09, 0.22, 0.05) * k,
			knot * CF(0.07 * s * k, -0.12 * k, -0.02) * CFrame.Angles(0, 0, rad(-26 * s)),
			color,
			cloth
		)
	end
end

-- BODY -------------------------------------------------------------------------------------------

function HumanCommon.Body(rig: RigContext, spec: Spec): Info
	local C = HumanCommon.Colors(rig)
	local face = buildFace(rig, spec, C)
	local hair = buildHair(rig, spec, C, face)
	local sweater = buildSweater(rig, spec, C)
	buildLegs(rig, spec, C)
	buildShoes(rig, spec, C)
	buildHand(rig, "Left", spec.LeftHand or "Open", C)
	local rightMode = spec.RightHand or (if spec.Weapon then "Fist" else "Open")
	buildHand(rig, "Right", rightMode, C)
	local weapon: Model? = nil
	if spec.Weapon then
		weapon = HumanCommon.HoldWeapon(rig, spec.Weapon :: string, spec.WeaponTilt)
	end
	rig.Attachment("UpperTorso", "Chest", sweater.Chest * CF(0, 0, -0.06))
	local backY = sweater.Chest.Position.Y
	local _, bd = sweater.Size(backY)
	rig.Attachment("UpperTorso", "Back", CF(0, backY, 0.01 + bd / 2 + 0.04))
	rig.Attachment("Head", "HeadTop", CF(0, hair.Top + 0.35, 0))
	return {
		Colors = C,
		FaceCF = face.CF,
		FaceRadii = face.R,
		HairCF = hair.CF,
		HairRadii = hair.R,
		HairTie = hair.Tie,
		HeadTopY = hair.Top,
		NeckY = rig.Joint("Neck").Y,
		ChestCF = sweater.Chest,
		SweaterSize = sweater.Size,
		HemY = sweater.HemY,
		Weapon = weapon,
	}
end

return HumanCommon
