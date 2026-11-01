--!strict
-- SansCommon: shared part builders for the Sans family blueprints (ClassicSans, FellSans,
-- EclipseSans) on the "Skeleton" skeleton. [Lune-safe]
-- Not a blueprint itself (no Id: Blueprints.List skips it). Each family blueprint calls these
-- builders with its palette + variant options and then adds its own signature details.
--
-- SKULL (the centrepiece; a squircle, NOT an oval)
--   A big ellipsoid cranium (dome + round back) fused with a rounded-box face block (flat front,
--   flat sides, flat base). Everything is authored in "HD units" = the bounding-box-centred
--   coordinates of the generated HD skull meshes (src/shared/Meshes/SansSkull*.luau, SPEC §18),
--   multiplied by SansCommon.SKULL_K, so the part-built skull, its features and the HD mesh line up:
--   sockets at (±0.45, +0.03), nose at y -0.29, grin rows -0.39..-0.76 (cylindrical u/v layout of
--   tools/meshgen/models/sans.py). Every part the HD mesh replaces carries HDGroup = "Skull"; the
--   anchor Attachment "HD_Skull" (Head, at the HD bounding-box centre, -Z forward) carries
--   HDMesh / HDSize. Pupils are NOT in the group (they stay visible over the HD mesh).
--
-- API (all builders take the blueprint's RigContext first; sizes in studs at scale 1)
--   SansCommon.SKULL_K, SansCommon.HD[variant] = { Mesh, Size, Centre }   (variant: Classic|Fell|Eclipse)
--   SansCommon.Overrides                         skeleton overrides shared by the family
--   SansCommon.Skull(rig, { Variant, Bone, BoneShade? }) -> Skull
--       Skull.CF (HD-unit origin, model space), Skull.K, Skull.Front(x, y, inset?) -> CFrame on the
--       face surface (LookVector = outward normal), Skull.Dome(yawDeg, pitchDeg, inset?) -> CFrame on
--       the cranium, Skull.Point(x, y, z) -> Vector3, Skull.Grin(u, v) -> (x, y) HD face coordinates
--   SansCommon.Sockets(rig, skull, opts) / Pupils(...) / Nose(...) / Grin(...)   face features
--   SansCommon.FaceLine(rig, skull, name, pts, width, color, props)  dark stroke hugging the face
--   SansCommon.Hoodie(rig, opts) -> HoodieInfo   puffy open jacket: panels, hem, inner shirt,
--       zipper, pockets, drawstrings, hood
--   SansCommon.FurRing(rig, opts)                fur trim bunched around the neck & shoulders
--   SansCommon.Sleeves(rig, opts) / Hands(rig, opts) / Shorts(rig, opts) / Shins(rig, opts)
--   SansCommon.Slippers(rig, opts)
--   SansCommon.EllipticCyl(rig, limb, name, size, cf, color, props)   cylinder (axis = cf.X) with an
--       elliptic section (Block + SpecialMesh Cylinder)
--   SansCommon.Jitter(i, salt) -> number in [-1, 1] (deterministic)

local PartKit = require(script.Parent.Parent.PartKit)
local Blueprints = require(script.Parent)

type RigContext = Blueprints.RigContext
type Props = PartKit.Props

local V = Vector3.new
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's X axis to +Y

local SansCommon = {}

------------------------------------------------------------------------------------------------
-- Family constants
------------------------------------------------------------------------------------------------

-- HD meshes (Meshes/SansSkull*.Size; tests/rigs_sans.spec.luau checks they stay in sync).
-- Centre = the mesh's bounding-box centre in Classic HD units (Fell's heavy brow sticks out
-- 0.138 further, so its box centre sits 0.069 forward).
SansCommon.HD = {
	Classic = { Mesh = "SansSkullClassic", Size = V(2.0452, 1.7764, 1.8873), Centre = V(0, 0, 0) },
	Fell = { Mesh = "SansSkullFell", Size = V(2.0447, 1.7764, 2.0251), Centre = V(0, 0, -0.0689) },
	Eclipse = { Mesh = "SansSkullEclipse", Size = V(2.0452, 1.7756, 1.8873), Centre = V(0, 0, 0) },
}

SansCommon.SKULL_K = 1.06 -- skull scale relative to the HD mesh (2.17 x 1.88 x 2.0 studs)
SansCommon.SKULL_DROP = 0.1 -- the jaw sits this far below the Neck pivot (hidden in the fur)

-- Shared skeleton tweaks (the family keeps one skeleton so animation clips fit all three).
SansCommon.Overrides = nil :: any

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------

-- Deterministic jitter in [-1, 1].
function SansCommon.Jitter(i: number, salt: number): number
	local x = math.sin(i * 127.1 + salt * 311.7) * 43758.5453
	return (x - math.floor(x)) * 2 - 1
end
local jitter = SansCommon.Jitter

local function merge(a: Props, b: Props?): Props
	local out = table.clone(a)
	if b then
		for k, v in b :: any do
			(out :: any)[k] = v
		end
	end
	return out
end

-- Cylinder whose section is an ellipse (Size.Y x Size.Z), axis along cf.XVector.
function SansCommon.EllipticCyl(
	rig: RigContext,
	limb: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	props: Props?
): BasePart
	local part = rig.Ellipsoid(limb, name, size, cf, color, props)
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.MeshType = Enum.MeshType.Cylinder
	end
	return part
end
local ellipticCyl = SansCommon.EllipticCyl

-- Front point of an ellipsoid (centre c, semi-axes r) at (x, y); nil outside.
local function ellipsoidFrontZ(c: Vector3, r: Vector3, x: number, y: number): number?
	local t = 1 - ((x - c.X) / r.X) ^ 2 - ((y - c.Y) / r.Y) ^ 2
	if t <= 0 then
		return nil
	end
	return c.Z - r.Z * math.sqrt(t)
end

------------------------------------------------------------------------------------------------
-- Skull
------------------------------------------------------------------------------------------------

-- Geometry in HD units (Classic bounding box: x ±1.0226, y ±0.8882, z ±0.9437).
local CRANIUM_C = V(0, 0.03, 0.03)
local CRANIUM_R = V(1.0226, 0.8582, 0.9137) -- top 0.888, back 0.944, front -0.884
local BLOCK_C = V(0, -0.244, -0.3469)
local BLOCK_HALF = V(0.86, 0.644, 0.5969) -- y -0.888..0.40, z -0.944..0.25 (flat face + jaw)
local BLOCK_R = 0.42

-- Grin layout (tools/meshgen/models/sans.py, converted to HD units)
local GRIN = {
	AxisZ = 0.1685, -- cylinder axis (z) of the u/v face projection
	CylR = 1.16,
	VShift = -0.0708, -- field v -> HD y
	Y0 = -0.47,
	A = 0.26,
	Drop = 0.215,
	C = 0.62,
}
GRIN.CornerU = math.sqrt(GRIN.Drop / (GRIN.C - GRIN.A))
SansCommon.GRIN = GRIN

local function blockFrontZ(x: number, y: number): number?
	local ix, iy = BLOCK_HALF.X - BLOCK_R, BLOCK_HALF.Y - BLOCK_R
	local dx = math.max(math.abs(x - BLOCK_C.X) - ix, 0)
	local dy = math.max(math.abs(y - BLOCK_C.Y) - iy, 0)
	local d2 = dx * dx + dy * dy
	if d2 >= BLOCK_R * BLOCK_R then
		return nil
	end
	return BLOCK_C.Z - (BLOCK_HALF.Z - BLOCK_R) - math.sqrt(BLOCK_R * BLOCK_R - d2)
end

export type Skull = {
	CF: CFrame,
	K: number,
	Variant: string,
	Front: (x: number, y: number, inset: number?) -> CFrame,
	Dome: (yawDeg: number, pitchDeg: number, inset: number?) -> CFrame,
	Point: (x: number, y: number, z: number) -> Vector3,
	Grin: (u: number, v: number) -> (number, number),
	Upper: (u: number) -> number,
	Lower: (u: number) -> number,
}

-- Extra bone volumes fused into the skull surface (e.g. Fell's heavy brows), HD units; Angle rotates
-- the ellipsoid about the view (Z) axis.
export type SkullExtra = { Name: string, C: Vector3, R: Vector3, Angle: number? }

export type SkullOptions = {
	Variant: string,
	Bone: Color3,
	Material: Enum.Material?,
	Extra: { SkullExtra }?,
}

-- Builds the cranium + face block on Head and the HD_Skull anchor. Returns the face toolkit.
function SansCommon.Skull(rig: RigContext, opts: SkullOptions): Skull
	local K = SansCommon.SKULL_K
	local hd = SansCommon.HD[opts.Variant] or SansCommon.HD.Classic
	local neck = rig.Joint("Neck")
	local headCF = rig.CFrameOf("Head")
	local centreY = neck.Y + 0.8882 * K - SansCommon.SKULL_DROP
	local origin = CFrame.new(0, centreY, headCF.Position.Z + 0.01)
	local bone: Props = {
		Role = "Bone",
		Material = opts.Material or Enum.Material.SmoothPlastic,
		Attributes = { HDGroup = "Skull" },
	}

	rig.Ellipsoid("Head", "Cranium", CRANIUM_R * (2 * K), origin * CFrame.new(CRANIUM_C * K), opts.Bone, bone)
	local extras = opts.Extra or {}
	for _, e in extras do
		rig.Ellipsoid(
			"Head",
			e.Name,
			e.R * (2 * K),
			origin * CFrame.new(e.C * K) * CFrame.Angles(0, 0, e.Angle or 0),
			opts.Bone,
			bone
		)
	end

	-- front surface z (HD units) of the fused skull at face coordinates (x, y)
	local function surfaceZ(x: number, y: number): number
		local best = blockFrontZ(x, y)
		local c = ellipsoidFrontZ(CRANIUM_C, CRANIUM_R, x, y)
		if c and (best == nil or c < best) then
			best = c
		end
		for _, e in extras do
			local dx, dy = x - e.C.X, y - e.C.Y
			local ang = -(e.Angle or 0)
			local lx = dx * math.cos(ang) - dy * math.sin(ang)
			local ly = dx * math.sin(ang) + dy * math.cos(ang)
			local z = ellipsoidFrontZ(V(0, 0, e.C.Z), e.R, lx, ly)
			if z and (best == nil or z < best) then
				best = z
			end
		end
		return best or 0
	end
	rig.RoundedBox(
		"Head",
		"SkullFace",
		BLOCK_HALF * (2 * K),
		origin * CFrame.new(BLOCK_C * K),
		opts.Bone,
		BLOCK_R * K,
		bone
	)

	-- SPEC §18 anchor: HD bounding-box centre, -Z forward, size at scale 1.
	local anchor = rig.Attachment("Head", "HD_Skull", origin * CFrame.new(hd.Centre * K))
	anchor:SetAttribute("HDMesh", hd.Mesh)
	anchor:SetAttribute("HDSize", hd.Size * K)

	local skull = {} :: Skull
	skull.CF = origin
	skull.K = K
	skull.Variant = opts.Variant

	function skull.Point(x: number, y: number, z: number): Vector3
		return (origin * CFrame.new(x * K, y * K, z * K)).Position
	end

	function skull.Front(x: number, y: number, inset: number?): CFrame
		local h = 0.004
		local z = surfaceZ(x, y)
		local fx = (surfaceZ(x + h, y) - surfaceZ(x - h, y)) / (2 * h)
		local fy = (surfaceZ(x, y + h) - surfaceZ(x, y - h)) / (2 * h)
		local n = V(fx, fy, -1).Unit
		local p = V(x, y, z) - n * (inset or 0)
		return origin * PartKit.LookFrame(p * K, n)
	end

	function skull.Dome(yawDeg: number, pitchDeg: number, inset: number?): CFrame
		local c = origin * CFrame.new(CRANIUM_C * K)
		return PartKit.OnEllipsoid(c, CRANIUM_R * K, yawDeg, pitchDeg, (inset or 0) * K)
	end

	function skull.Upper(u: number): number
		return GRIN.Y0 + GRIN.A * u * u + GRIN.VShift
	end

	function skull.Lower(u: number): number
		return GRIN.Y0 - GRIN.Drop + GRIN.C * u * u + GRIN.VShift
	end

	-- cylindrical face coordinates (arc length u, height v already in HD y) -> HD (x, y)
	function skull.Grin(u: number, v: number): (number, number)
		return GRIN.CylR * math.sin(u / GRIN.CylR), v
	end

	return skull
end

------------------------------------------------------------------------------------------------
-- Face features
------------------------------------------------------------------------------------------------

-- A stroke through HD face points {x, y}: thin flat boxes hugging the face surface. Each segment
-- is centred on the surface point under its midpoint (a chord would sink into the convex skull)
-- and lies along the chord between the endpoints' surface points.
function SansCommon.FaceLine(
	rig: RigContext,
	skull: Skull,
	name: string,
	pts: { { number } },
	width: number,
	color: Color3,
	props: Props?
): { BasePart }
	local K = skull.K
	local out: { BasePart } = {}
	local pr = merge({ Role = "Dark", CastShadow = false, Attributes = { HDGroup = "Skull" } }, props)
	for i = 1, #pts - 1 do
		local p0, p1 = pts[i], pts[i + 1]
		local pa = skull.Front(p0[1], p0[2], 0).Position
		local pb = skull.Front(p1[1], p1[2], 0).Position
		local mid = skull.Front((p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2, -0.005)
		local len = (pb - pa).Magnitude
		if len > 1e-4 then
			local normal = mid.LookVector
			local x = (pb - pa).Unit
			local zAxis = -(normal - x * x:Dot(normal)).Unit -- ZVector points into the skull
			local y = zAxis:Cross(x)
			local cf = CFrame.fromMatrix(mid.Position, x, y, zAxis)
			table.insert(out, rig.Box("Head", name, V(len + width * K * 0.55, width * K, 0.02 * K), cf, color, pr))
		end
	end
	return out
end

-- A stroke over the cranium through (yawDeg, pitchDeg) points (yaw + = his right, pitch + = up),
-- each segment centred on the dome under its midpoint. Colors: one Color3 or one per segment.
function SansCommon.DomeLine(
	rig: RigContext,
	skull: Skull,
	name: string,
	pts: { { number } },
	width: number,
	color: Color3 | { Color3 },
	props: Props?
): { BasePart }
	local K = skull.K
	local out: { BasePart } = {}
	local pr = merge({ Role = "Dark", CastShadow = false, Attributes = { HDGroup = "Skull" } }, props)
	for i = 1, #pts - 1 do
		local p0, p1 = pts[i], pts[i + 1]
		local pa = skull.Dome(p0[1], p0[2], 0).Position
		local pb = skull.Dome(p1[1], p1[2], 0).Position
		local mid = skull.Dome((p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2, -0.006)
		local len = (pb - pa).Magnitude
		if len > 1e-4 then
			local normal = mid.LookVector
			local x = (pb - pa).Unit
			local zAxis = -(normal - x * x:Dot(normal)).Unit
			local y = zAxis:Cross(x)
			local c: Color3 = if typeof(color) == "Color3" then color else (color :: { Color3 })[i] or (color :: { Color3 })[1]
			table.insert(
				out,
				rig.Box(
					"Head",
					name,
					V(len + width * K * 0.55, width * K, 0.02 * K),
					CFrame.fromMatrix(mid.Position, x, y, zAxis),
					c,
					pr
				)
			)
		end
	end
	return out
end

export type SocketOptions = {
	Socket: Color3, -- the void (rendered as Neon so it never catches light: a true black hole)
	Rim: Color3?, -- optional soft bevel just outside the void (slightly darker bone)
	Scale: number?,
	Size: Vector2?, -- HD units (default 0.66 x 0.47)
}

-- Two deep eye sockets: flush, light-proof dark ovals (Neon black reads as a bottomless recess) with
-- an optional soft bevel. Returns the socket centre frames (HD units: x ±0.45, y 0.03).
function SansCommon.Sockets(rig: RigContext, skull: Skull, opts: SocketOptions): { [string]: CFrame }
	local K = skull.K
	local s = opts.Scale or 1
	local size = opts.Size or Vector2.new(0.66, 0.47)
	local out: { [string]: CFrame } = {}
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local cf = skull.Front(0.45 * sx, 0.03, 0)
		local tilt = CFrame.Angles(0, 0, math.rad(2 * sx))
		local hdGroup = { HDGroup = "Skull" }
		if opts.Rim then
			rig.Ellipsoid(
				"Head",
				side .. "SocketRim",
				V(size.X + 0.08, size.Y + 0.07, 0.4) * K * s,
				cf * tilt * CFrame.new(0, 0, 0.185 * K),
				opts.Rim,
				{ Role = "Bone", CastShadow = false, Attributes = hdGroup }
			)
		end
		rig.Ellipsoid(
			"Head",
			side .. "Socket",
			V(size.X, size.Y, 0.4) * K * s,
			cf * tilt * CFrame.new(0, 0, 0.18 * K),
			opts.Socket,
			{ Role = "Dark", Material = Enum.Material.Neon, CastShadow = false, Attributes = hdGroup }
		)
		out[side] = cf
	end
	return out
end

export type PupilOptions = {
	Color: Color3,
	Size: number?, -- HD units (default 0.13)
	Offset: Vector2?, -- toward the nose (+) and up (+), HD units (default (0.07, -0.06))
	Lights: Color3?, -- optional PointLight colour in each socket
	LightBrightness: number?,
}

-- LeftPupil / RightPupil (Neon, Role Eye, under Head) + LeftEye / RightEye attachments.
function SansCommon.Pupils(rig: RigContext, skull: Skull, opts: PupilOptions): { [string]: BasePart }
	local K = skull.K
	local size = (opts.Size or 0.085) * K
	local off = opts.Offset or Vector2.new(0.07, -0.06)
	local out: { [string]: BasePart } = {}
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local x, y = 0.45 * sx - off.X * sx, 0.03 + off.Y
		local cf = skull.Front(x, y, -0.03)
		local pupil = rig.Ball("Head", side .. "Pupil", size, cf, opts.Color, {
			Role = "Eye",
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
		rig.Attachment("Head", side .. "Eye", cf * CFrame.new(0, 0, -0.02))
		if opts.Lights then
			rig.Light(pupil, "Point", {
				Name = side .. "EyeLight",
				Color = opts.Lights,
				Brightness = opts.LightBrightness or 1.2,
				Range = 3,
			})
		end
		out[side] = pupil
	end
	return out
end

-- Inverted teardrop nose: round dark bottom + a pointed top (two mirrored wedges).
function SansCommon.Nose(rig: RigContext, skull: Skull, color: Color3, scale: number?)
	local K = skull.K
	local s = scale or 1
	local props: Props = { Role = "Dark", CastShadow = false, Attributes = { HDGroup = "Skull" } }
	local base = skull.Front(0, -0.335, 0.02)
	rig.Ellipsoid("Head", "NoseBase", V(0.2, 0.15, 0.1) * K * s, base, color, props)
	local tip = skull.Front(0, -0.25, 0.012)
	local w, h = 0.085 * K * s, 0.2 * K * s
	for _, sx in { -1, 1 } do
		-- WedgePart: right angle at the bottom-centre, slope from the top-centre to the bottom-outer
		local rot = if sx > 0
			then CFrame.fromMatrix(Vector3.zero, V(0, 0, 1), V(0, 1, 0), V(-1, 0, 0))
			else CFrame.fromMatrix(Vector3.zero, V(0, 0, -1), V(0, 1, 0), V(1, 0, 0))
		local cf = tip * CFrame.new(sx * w / 2, -0.0 * K, 0) * rot
		rig.Wedge("Head", "NoseTip", V(0.04 * K, h, w), cf, color, props)
	end
end

export type GrinOptions = {
	Line: Color3,
	Style: string?, -- "Classic" (5 square teeth) | "Jagged" (Fell fangs)
	Width: number?, -- stroke width (HD units)
}

-- The fixed wide grin: upper + lower lip strokes, tooth separators, corner creases.
-- Returns the zig-zag points (Jagged) so blueprints can add a gold tooth between them.
function SansCommon.Grin(rig: RigContext, skull: Skull, opts: GrinOptions): { { number } }
	local uc = GRIN.CornerU
	local w = opts.Width or 0.066
	local function curve(f: (number) -> number, n: number, shrink: number): { { number } }
		local pts = {}
		for i = 0, n do
			local u = (-uc + 2 * uc * i / n) * shrink
			local x, y = skull.Grin(u, f(u))
			table.insert(pts, { x, y })
		end
		return pts
	end
	SansCommon.FaceLine(rig, skull, "GrinUpper", curve(skull.Upper, 6, 1), w, opts.Line)
	SansCommon.FaceLine(rig, skull, "GrinLower", curve(skull.Lower, 7, 1), w, opts.Line)
	local zig: { { number } } = {}
	if opts.Style == "Jagged" then
		local n = 11
		for i = 0, n - 1 do
			local u = -uc * 0.93 + 2 * uc * 0.93 * i / (n - 1)
			local top, bot = skull.Upper(u), skull.Lower(u)
			local t = if i % 2 == 0 then 0.18 else 0.86
			local x, y = skull.Grin(u, top + (bot - top) * t)
			table.insert(zig, { x, y, u })
		end
		SansCommon.FaceLine(rig, skull, "GrinFangs", zig, w * 0.8, opts.Line)
	else
		for _, u in { -0.525, -0.315, -0.105, 0.105, 0.315, 0.525 } do
			local x0, y0 = skull.Grin(u, skull.Upper(u) - w * 0.3)
			local x1, y1 = skull.Grin(u, skull.Lower(u) + w * 0.3)
			SansCommon.FaceLine(rig, skull, "GrinTooth", { { x0, y0 }, { x1, y1 } }, w * 0.7, opts.Line)
		end
	end
	-- corner creases: a short diagonal curl continuing the upper lip up and out
	for _, s in { -1, 1 } do
		local cu = s * uc
		local cv = skull.Upper(uc)
		local function p(du: number, dv: number): { number }
			local x, y = skull.Grin(cu + du, cv + dv)
			return { x, y }
		end
		SansCommon.FaceLine(rig, skull, "GrinCrease", { p(-s * 0.01, -0.012), p(s * 0.045, 0.075) }, w * 0.85, opts.Line)
	end
	return zig
end

------------------------------------------------------------------------------------------------
-- Hoodie / jacket
------------------------------------------------------------------------------------------------

export type HoodieOptions = {
	Body: Color3,
	Dark: Color3,
	Inner: Color3, -- shirt / sweater visible in the open front
	InnerRole: string?,
	InnerMaterial: Enum.Material?,
	Material: Enum.Material?,
	Zipper: Color3?,
	Pull: Color3?,
	Cord: Color3?,
	Aglet: Color3?,
	Hood: boolean?, -- bunched hood on the upper back (default true)
	HoodInner: Color3?, -- inside of the lowered hood (default Dark)
	Spread: number?, -- extra panel width (Fell: broader)
}

export type HoodieInfo = {
	FrontZ: (x: number, y: number) -> number, -- jacket front surface z at (x, y) (model space)
	InnerFrontZ: (x: number, y: number) -> number?, -- front of the shirt/lining showing in the opening
	EdgeX: (y: number) -> number, -- |x| of the jacket opening edge at height y
	PanelC: Vector3, -- right panel centre (mirror x for the left one)
	PanelR: Vector3, -- panel semi-axes
}

-- The puffy open jacket: two tall panels (left/right) whose rounded inner edges frame the shirt
-- behind them, a gathered ribbed hem split at the zipper, zipper tapes, drawstrings, the lowered
-- hood on the upper back.
function SansCommon.Hoodie(rig: RigContext, opts: HoodieOptions): HoodieInfo
	local mat = opts.Material or Enum.Material.Fabric
	local cloth: Props = { Role = "Cloth", Material = mat }
	local trim: Props = { Role = "Trim", Material = mat }
	local waistY = rig.Joint("Waist").Y
	local neckY = rig.Joint("Neck").Y
	local spread = opts.Spread or 0
	local panelC = V(0.56 + spread * 0.5, (neckY + waistY) / 2 - 0.25, -0.07)
	local panelR = V(0.7 + spread * 0.5, 1.12, 0.9)

	for _, sx in { -1, 1 } do
		local side = if sx < 0 then "Left" else "Right"
		rig.Ellipsoid(
			"UpperTorso",
			side .. "Panel",
			panelR * 2,
			CFrame.new(panelC.X * sx, panelC.Y, panelC.Z),
			opts.Body,
			cloth
		)
		-- ribbed hem halves (gathered, split at the zipper)
		ellipticCyl(
			rig,
			"UpperTorso",
			side .. "Hem",
			V(0.17, 0.98, 1.36),
			CFrame.new((0.4 + spread * 0.3) * sx, panelC.Y - panelR.Y + 0.13, -0.02) * UPRIGHT,
			opts.Dark,
			trim
		)
	end

	-- broad round shoulders (the sleeves hang from them)
	for _, sx in { -1, 1 } do
		local side = if sx < 0 then "Left" else "Right"
		rig.Ellipsoid(
			"UpperTorso",
			side .. "ShoulderPad",
			V(1.15 + spread, 0.82, 1.2),
			CFrame.new((0.66 + spread * 0.5) * sx, neckY - 0.3, 0.04) * CFrame.Angles(0, 0, math.rad(-12 * sx)),
			opts.Body,
			cloth
		)
	end

	-- the shirt / sweater behind the open front
	local shirtC = V(0, panelC.Y, -0.36)
	local shirtR = V(0.31, panelR.Y - 0.03, 0.4)
	rig.Ellipsoid(
		"UpperTorso",
		"InnerShirt",
		shirtR * 2,
		CFrame.new(shirtC),
		opts.Inner,
		{ Role = opts.InnerRole or "ClothAlt", Material = opts.InnerMaterial or mat }
	)

	local function panelFrontZ(x: number, y: number): number?
		local best: number? = nil
		for _, sx in { -1, 1 } do
			local z = ellipsoidFrontZ(V(panelC.X * sx, panelC.Y, panelC.Z), panelR, x, y)
			if z and (best == nil or z < best) then
				best = z
			end
		end
		return best
	end
	local function frontZ(x: number, y: number): number
		return panelFrontZ(x, y) or -0.3
	end

	-- the visible jacket edge at height y: where the right panel's front meets the shirt's front
	local function edgeX(y: number): number
		local lo, hi = 0, panelC.X
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			local pz = panelFrontZ(mid, y)
			local sz = ellipsoidFrontZ(shirtC, shirtR, mid, y)
			if pz == nil or (sz ~= nil and sz < pz) then
				lo = mid -- shirt still in front: the edge is further out
			else
				hi = mid
			end
		end
		return (lo + hi) / 2
	end

	-- a cord/tape lying on the jacket: points (x, y) projected onto the panel surface, `lift` proud
	local function onJacket(name: string, pts: { Vector2 }, d: number, lift: number, color: Color3, props: Props)
		for i = 1, #pts - 1 do
			local p0, p1 = pts[i], pts[i + 1]
			local a = V(p0.X, p0.Y, frontZ(math.abs(p0.X), p0.Y) - lift)
			local b = V(p1.X, p1.Y, frontZ(math.abs(p1.X), p1.Y) - lift)
			rig.CylBetween("UpperTorso", name, a, b, d, color, props)
		end
	end

	if opts.Zipper then
		local top, bottom = neckY - 0.34, panelC.Y - panelR.Y + 0.3
		for _, sx in { -1, 1 } do
			local pts: { Vector2 } = {}
			for i = 0, 4 do
				local y = top + (bottom - top) * i / 4
				table.insert(pts, Vector2.new((edgeX(y) + 0.03) * sx, y))
			end
			onJacket("Zipper", pts, 0.05, 0.004, opts.Zipper, {
				Role = "Metal",
				Material = Enum.Material.Metal,
				CastShadow = false,
			})
		end
		if opts.Pull then
			local y = panelC.Y - 0.12
			local x = edgeX(y) + 0.035
			local p = V(x, y - 0.1, frontZ(x, y - 0.1) - 0.03)
			rig.Box(
				"UpperTorso",
				"ZipperPull",
				V(0.08, 0.2, 0.035),
				CFrame.new(p) * CFrame.Angles(0.25, 0, 0.1),
				opts.Pull,
				{ Role = "Accent", Material = Enum.Material.Metal }
			)
		end
	end

	-- drawstrings hanging from the hood opening over the chest
	if opts.Cord then
		for _, sx in { -1, 1 } do
			local y0, y1 = neckY - 0.3, neckY - 1.0
			local ym = (y0 + y1) / 2
			local pts = {
				Vector2.new((edgeX(y0) + 0.17) * sx, y0),
				Vector2.new((edgeX(ym) + 0.15) * sx, ym),
				Vector2.new((edgeX(y1) + 0.13) * sx, y1),
			}
			onJacket("Drawstring", pts, 0.05, 0.022, opts.Cord, { Role = "Trim", Material = mat })
			local b = V(pts[3].X, pts[3].Y, frontZ(math.abs(pts[3].X), pts[3].Y) - 0.03)
			rig.Ellipsoid(
				"UpperTorso",
				"Aglet",
				V(0.07, 0.15, 0.07),
				CFrame.new(b + V(0, -0.065, 0)),
				opts.Aglet or opts.Cord,
				{ Role = "Accent", Material = Enum.Material.SmoothPlastic }
			)
		end
	end

	-- the lowered hood lies bunched on the upper back
	if opts.Hood ~= false then
		rig.Ellipsoid(
			"UpperTorso",
			"Hood",
			V(1.85, 0.9, 0.62),
			CFrame.new(0, neckY - 0.16, 0.66) * CFrame.Angles(math.rad(-14), 0, 0),
			opts.Body,
			cloth
		)
		rig.Ellipsoid(
			"UpperTorso",
			"HoodInner",
			V(1.45, 0.3, 0.55),
			CFrame.new(0, neckY + 0.3, 0.52) * CFrame.Angles(math.rad(10), 0, 0),
			opts.HoodInner or opts.Dark,
			{ Role = "Dark", Material = mat }
		)
		rig.Ellipsoid(
			"UpperTorso",
			"HoodTip",
			V(0.9, 0.7, 0.36),
			CFrame.new(0, neckY - 0.66, 0.84) * CFrame.Angles(math.rad(-12), 0, 0),
			opts.Body,
			cloth
		)
	end

	return {
		FrontZ = frontZ,
		InnerFrontZ = function(x: number, y: number): number?
			return ellipsoidFrontZ(shirtC, shirtR, x, y)
		end,
		EdgeX = edgeX,
		PanelC = panelC,
		PanelR = panelR,
	}
end

export type PocketOptions = {
	Body: Color3,
	Dark: Color3,
	Material: Enum.Material?,
}

-- Hand-warmer pockets: puffy pouches on the lower panels with slanted openings near the outer top
-- edge; sized so the Skeleton "Pockets" pose tucks the hands in behind them.
function SansCommon.Pockets(rig: RigContext, info: HoodieInfo, opts: PocketOptions)
	local mat = opts.Material or Enum.Material.Fabric
	local y = info.PanelC.Y - 0.7
	for _, sx in { -1, 1 } do
		local side = if sx < 0 then "Left" else "Right"
		local x = 0.72 * sx
		local z = info.FrontZ(x, y)
		local cf = CFrame.new(x, y, z + 0.1) * CFrame.Angles(math.rad(-10), math.rad(-16 * sx), math.rad(4 * sx))
		rig.Ellipsoid("UpperTorso", side .. "Pocket", V(0.86, 0.76, 0.72), cf, opts.Body, {
			Role = "Cloth",
			Material = mat,
		})
		local slit = cf * CFrame.new(0.15 * sx, 0.19, -0.25) * CFrame.Angles(math.rad(-34), 0, math.rad(-60 * sx))
		rig.Ellipsoid("UpperTorso", side .. "PocketSlit", V(0.52, 0.08, 0.16), slit, opts.Dark, {
			Role = "Dark",
			Material = mat,
			CastShadow = false,
		})
	end
end

export type FurOptions = {
	Color: Color3,
	Shade: Color3?,
	Count: number?,
	Radius: Vector2?, -- ring semi-axes (x, z)
	Lift: number?,
	Material: Enum.Material?,
	BallSize: number?,
	FrontDip: number?, -- how far the ring drops at the front (default 0.24)
	FrontGap: number?, -- degrees either side of the front left open (the trim parts around the
	-- jacket opening, e.g. to show a collar); 0 = closed ring
	Inner: boolean?, -- second, higher roll behind the neck (default true)
}

-- Fluffy fur trim of the lowered hood, bunched around the neck & shoulders: a dense outer roll of
-- overlapping fabric balls (lower at the front where the hood opening drapes onto the chest,
-- higher at the back) + an inner, higher roll behind the neck.
function SansCommon.FurRing(rig: RigContext, opts: FurOptions)
	local mat = opts.Material or Enum.Material.Fabric
	local neckY = rig.Joint("Neck").Y + (opts.Lift or 0)
	local r = opts.Radius or Vector2.new(1.08, 0.8)
	local n = opts.Count or 20
	local size = opts.BallSize or 0.5
	local shade = opts.Shade or PartKit.Shade(opts.Color, -0.06)
	local cz = 0.14
	local fur: Props = { Role = "Trim", Material = mat }
	local function ringPoint(a: number, scale: number, lift: number): (Vector3, number, number)
		local sx, sz = math.sin(a), -math.cos(a) -- a = 0 at the front (-Z)
		local front = math.max(-sz, 0)
		local back = math.max(sz, 0)
		local side = 1 - front - back
		local y = neckY - 0.1 - (opts.FrontDip or 0.24) * front * front + 0.06 * side + 0.16 * back + lift
		return V(sx * r.X * scale * (1 - 0.05 * front), y, cz + sz * r.Y * scale), front, back
	end
	-- outer roll: overlapping tufts lying along the ring (puffy, continuous, bumpy)
	local gap = math.rad(opts.FrontGap or 0)
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi * 2
		if gap > 0 then
			-- squeeze the ring into the arc [gap, 2pi - gap] so it frames the opening
			a = gap + (i - 0.5) / n * (math.pi * 2 - 2 * gap)
		end
		local pos, front = ringPoint(a, 1, jitter(i, 3) * 0.025)
		local nextPos = ringPoint(a + 0.2, 1, 0)
		local tangent = nextPos - pos
		local d = size * (0.92 + 0.1 * jitter(i, 5)) * (1 - 0.1 * front)
		local cf = PartKit.Basis(pos, tangent, V(0, 1, 0)) * CFrame.Angles(math.rad(jitter(i, 7) * 12), 0, 0)
		rig.Ellipsoid("UpperTorso", "Fur", V(d * 1.35, d * 0.92, d), cf, if i % 2 == 0 then shade else opts.Color, fur)
	end
	-- inner roll: higher, bunched up behind the neck (skipped at the front so the jaw stays clear)
	local m = if opts.Inner == false then 0 else math.floor(n * 0.6)
	for i = 1, m do
		local a = (i - 0.5) / m * math.pi * 2 + 0.25
		local pos, front = ringPoint(a, 0.74, 0.17)
		if front < 0.55 then
			local nextPos = ringPoint(a + 0.2, 0.74, 0.17)
			local d = size * (0.96 + 0.08 * jitter(i, 9))
			rig.Ellipsoid(
				"UpperTorso",
				"FurInner",
				V(d * 1.3, d * 0.95, d),
				PartKit.Basis(pos, nextPos - pos, V(0, 1, 0)),
				opts.Color,
				fur
			)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Arms
------------------------------------------------------------------------------------------------

export type SleeveOptions = {
	Body: Color3,
	Dark: Color3,
	Material: Enum.Material?,
	Puff: number?, -- sleeve diameter multiplier
	Stripe: Color3?, -- optional sleeve stripe (Fell)
}

function SansCommon.Sleeves(rig: RigContext, opts: SleeveOptions)
	local mat = opts.Material or Enum.Material.Fabric
	local cloth: Props = { Role = "Cloth", Material = mat }
	local puff = opts.Puff or 1
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local ua, la = side .. "UpperArm", side .. "LowerArm"
		local sh = rig.Joint(side .. "Shoulder")
		local el = rig.Joint(side .. "Elbow")
		local wr = rig.Joint(side .. "Wrist")
		rig.Ball(ua, "ShoulderPuff", 0.8 * puff, CFrame.new(sh + V(-0.08 * sx, -0.04, 0)), opts.Body, cloth)
		local upperLen = (sh - el).Magnitude + 0.62
		rig.Ellipsoid(
			ua,
			"UpperSleeve",
			V(0.84 * puff, upperLen, 0.86 * puff),
			CFrame.new((sh + el) / 2 + V(0.02 * sx, -0.02, 0)),
			opts.Body,
			cloth
		)
		local lowerLen = (el - wr).Magnitude + 0.34
		rig.Ellipsoid(
			la,
			"LowerSleeve",
			V(0.86 * puff, lowerLen, 0.88 * puff),
			CFrame.new((el + wr) / 2 + V(0.02 * sx, 0.13, 0)),
			opts.Body,
			cloth
		)
		ellipticCyl(
			rig,
			la,
			"Cuff",
			V(0.17, 0.62 * puff, 0.64 * puff),
			CFrame.new(wr + V(0.02 * sx, 0.09, 0)) * UPRIGHT,
			opts.Dark,
			{ Role = "Trim", Material = mat }
		)
		if opts.Stripe then
			-- thin fins concentric with the sleeves: a stripe that follows their curve exactly
			rig.Ellipsoid(
				ua,
				"SleeveStripe",
				V(0.84 * puff + 0.03, upperLen - 0.04, 0.11),
				CFrame.new((sh + el) / 2 + V(0.02 * sx, -0.02, 0)),
				opts.Stripe,
				{ Role = "Accent", Material = mat, CastShadow = false }
			)
			rig.Ellipsoid(
				la,
				"SleeveStripe",
				V(0.86 * puff + 0.03, lowerLen - 0.04, 0.11),
				CFrame.new((el + wr) / 2 + V(0.02 * sx, 0.13, 0)),
				opts.Stripe,
				{ Role = "Accent", Material = mat, CastShadow = false }
			)
		end
	end
end

export type HandOptions = {
	Bone: Color3,
	Joint: Color3?, -- knuckle / crease tint
	Material: Enum.Material?,
	Role: string?,
	Glow: Color3?, -- optional Neon fingertip/vein accent (Eclipse void hands)
}

-- Bony hands: a flat palm, four slightly curled finger bones spread sideways and a thumb on the
-- body side. Rest pose: the back of the hand faces forward (reads clearly from the front) and the
-- fingers curl back; in the "Pockets" pose the hand slides into the pocket pouch edge-first.
function SansCommon.Hands(rig: RigContext, opts: HandOptions)
	local bone: Props = { Role = opts.Role or "Bone", Material = opts.Material or Enum.Material.SmoothPlastic }
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local hand = side .. "Hand"
		local wr = rig.Joint(side .. "Wrist")
		local palmC = wr + V(0.01 * sx, -0.2, 0.01)
		rig.Ellipsoid(hand, "Palm", V(0.38, 0.34, 0.19), CFrame.new(palmC), opts.Bone, bone)
		for f = 1, 4 do
			local u = (f - 2.5) / 1.5 -- -1 = index (body side) .. 1 = little finger
			local len = if f == 2 or f == 3 then 0.28 else 0.24
			local base = palmC + V(u * 0.13 * sx, -0.14 + math.abs(u) * 0.02, 0)
			local tip = base + V(u * 0.035 * sx, -len, 0.09)
			rig.Ellipsoid(hand, "Finger", V(len + 0.07, 0.095, 0.095), PartKit.Basis((base + tip) / 2, tip - base), opts.Bone, bone)
		end
		-- thumb on the body side, angled down and forward
		local tb = palmC + V(-0.17 * sx, 0.02, -0.01)
		local tt = tb + V(-0.07 * sx, -0.2, -0.05)
		rig.Ellipsoid(hand, "Thumb", V(0.29, 0.1, 0.1), PartKit.Basis((tb + tt) / 2, tt - tb), opts.Bone, bone)
		if opts.Glow then
			rig.Box(
				hand,
				"HandVein",
				V(0.22, 0.025, 0.02),
				CFrame.new(palmC + V(0, 0.03, -0.095)) * CFrame.Angles(0, 0, math.rad(-20 * sx)),
				opts.Glow,
				{ Role = "Glow", Material = Enum.Material.Neon, CastShadow = false }
			)
		end
		rig.Attachment(hand, side .. "Grip", CFrame.new(palmC + V(0, -0.15, 0)))
	end
end

------------------------------------------------------------------------------------------------
-- Legs
------------------------------------------------------------------------------------------------

export type ShortsOptions = {
	Body: Color3,
	Stripe: Color3?,
	Stripes: number?, -- 1 (default) or 2
	Material: Enum.Material?,
}

function SansCommon.Shorts(rig: RigContext, opts: ShortsOptions)
	local mat = opts.Material or Enum.Material.Fabric
	local cloth: Props = { Role = "ClothAlt", Material = mat }
	local pelvis = rig.CFrameOf("LowerTorso").Position
	rig.Ellipsoid("LowerTorso", "ShortsSeat", V(1.66, 0.78, 1.12), CFrame.new(pelvis + V(0, -0.12, 0.02)), opts.Body, cloth)
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local ul = side .. "UpperLeg"
		local hip = rig.Joint(side .. "Hip")
		local knee = rig.Joint(side .. "Knee")
		local top = V(hip.X + 0.03 * sx, hip.Y - 0.05, 0)
		local hemY = knee.Y + 0.06
		rig.Ellipsoid(ul, "ShortsThigh", V(0.84, 0.62, 0.86), CFrame.new(top + V(0, -0.12, 0)), opts.Body, cloth)
		local legH = top.Y - hemY
		ellipticCyl(
			rig,
			ul,
			"ShortsLeg",
			V(legH, 0.84, 0.86),
			CFrame.new(top.X + 0.02 * sx, hemY + legH / 2, 0) * UPRIGHT,
			opts.Body,
			cloth
		)
		if opts.Stripe then
			local count = opts.Stripes or 1
			for k = 1, count do
				local dz = if count == 1 then 0 else (k - 1.5) * 0.11
				rig.Box(
					ul,
					"ShortsStripe",
					V(0.04, legH + 0.22, 0.075),
					CFrame.new(top.X + 0.02 * sx + 0.42 * sx, hemY + (legH + 0.22) / 2 - 0.01, dz),
					opts.Stripe,
					{ Role = "Accent", Material = mat, CastShadow = false }
				)
			end
		end
	end
end

export type ShinOptions = {
	Bone: Color3,
	Material: Enum.Material?,
}

-- Bony shins: a slim tibia with a double knob under the knee (the ankle hides in the footwear).
function SansCommon.Shins(rig: RigContext, opts: ShinOptions)
	local bone: Props = { Role = "Bone", Material = opts.Material or Enum.Material.SmoothPlastic }
	for _, side in { "Left", "Right" } do
		local ll = side .. "LowerLeg"
		local knee = rig.Joint(side .. "Knee")
		local ankle = rig.Joint(side .. "Ankle")
		local top = knee + V(0, -0.08, 0)
		rig.CylBetween(ll, "Shin", top, ankle + V(0, 0.02, 0), 0.15, opts.Bone, bone)
		for _, dx in { -0.07, 0.07 } do
			rig.Ball(ll, "KneeKnob", 0.19, CFrame.new(top + V(dx, 0.02, -0.01)), opts.Bone, bone)
		end
	end
end

export type SlipperOptions = {
	Body: Color3,
	Sole: Color3?,
	Rim: Color3?,
	Material: Enum.Material?,
}

-- Fluffy round slippers (pink by fan convention): sole, puffy upper, fluffy rim around the ankle.
function SansCommon.Slippers(rig: RigContext, opts: SlipperOptions)
	local mat = opts.Material or Enum.Material.Fabric
	for _, side in { "Left", "Right" } do
		local foot = side .. "Foot"
		local fp = rig.CFrameOf(foot).Position
		local floorY = fp.Y - rig.Size(foot).Y / 2
		local cz = fp.Z - 0.04
		ellipticCyl(
			rig,
			foot,
			"SlipperSole",
			V(0.09, 0.8, 1.12),
			CFrame.new(fp.X, floorY + 0.045, cz) * UPRIGHT,
			opts.Sole or PartKit.Shade(opts.Body, -0.18),
			{ Role = "ClothAlt", Material = Enum.Material.SmoothPlastic }
		)
		rig.Ellipsoid(foot, "Slipper", V(0.78, 0.44, 1.1), CFrame.new(fp.X, floorY + 0.24, cz), opts.Body, {
			Role = "Cloth",
			Material = mat,
		})
		rig.Ellipsoid(
			foot,
			"SlipperRim",
			V(0.6, 0.16, 0.56),
			CFrame.new(fp.X, floorY + 0.42, fp.Z + 0.13),
			opts.Rim or PartKit.Shade(opts.Body, 0.25),
			{ Role = "Trim", Material = mat }
		)
		rig.Attachment(foot, side .. "FootAttachment", CFrame.new(fp.X, floorY, fp.Z))
	end
end

export type SneakerOptions = {
	Body: Color3, -- upper
	Toe: Color3, -- toe cap / heel counter
	Sole: Color3,
	Lace: Color3,
	Collar: Color3?, -- ankle collar (default Toe)
	Stripe: Color3?, -- side stripe (Accent)
}

-- Chunky high-top sneakers (Fell): thick sole, rounded upper with a toe cap, collar, laces and an
-- accent side stripe.
function SansCommon.Sneakers(rig: RigContext, opts: SneakerOptions)
	for _, side in { "Left", "Right" } do
		local sx = if side == "Left" then -1 else 1
		local foot = side .. "Foot"
		local fp = rig.CFrameOf(foot).Position
		local floorY = rig.CFrameOf(foot).Position.Y - rig.Size(foot).Y / 2
		local cz = fp.Z - 0.03
		ellipticCyl(
			rig,
			foot,
			"SneakerSole",
			V(0.12, 0.8, 1.14),
			CFrame.new(fp.X, floorY + 0.06, cz) * UPRIGHT,
			opts.Sole,
			{ Role = "ClothAlt", Material = Enum.Material.SmoothPlastic }
		)
		rig.Ellipsoid(foot, "Sneaker", V(0.74, 0.52, 1.04), CFrame.new(fp.X, floorY + 0.26, cz + 0.03), opts.Body, {
			Role = "Cloth",
			Material = Enum.Material.SmoothPlastic,
		})
		rig.Ellipsoid(foot, "SneakerToe", V(0.68, 0.3, 0.46), CFrame.new(fp.X, floorY + 0.15, cz - 0.31), opts.Toe, {
			Role = "Detail",
			Material = Enum.Material.SmoothPlastic,
		})
		ellipticCyl(
			rig,
			foot,
			"SneakerCollar",
			V(0.16, 0.56, 0.56),
			CFrame.new(fp.X, floorY + 0.47, fp.Z + 0.14) * UPRIGHT,
			opts.Collar or opts.Toe,
			{ Role = "Trim", Material = Enum.Material.SmoothPlastic }
		)
		for k = 0, 1 do
			rig.Box(
				foot,
				"Lace",
				V(0.3, 0.035, 0.05),
				CFrame.new(fp.X, floorY + 0.43 - k * 0.07, cz - 0.1 - k * 0.12) * CFrame.Angles(math.rad(-38), 0, 0),
				opts.Lace,
				{ Role = "Detail", CastShadow = false }
			)
		end
		if opts.Stripe then
			rig.Box(
				foot,
				"SneakerStripe",
				V(0.03, 0.08, 0.62),
				CFrame.new(fp.X + 0.36 * sx, floorY + 0.24, cz) * CFrame.Angles(math.rad(-12), 0, 0),
				opts.Stripe,
				{ Role = "Accent", CastShadow = false }
			)
		end
		rig.Attachment(foot, side .. "FootAttachment", CFrame.new(fp.X, floorY, fp.Z))
	end
end

return SansCommon
