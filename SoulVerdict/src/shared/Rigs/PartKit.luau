--!strict
-- PartKit: primitive builders for code-only visuals (rigs, props, VFX meshes). [Lune-safe]
--
-- Every builder creates fully configured VISUAL parts and parents them LAST:
--   Anchored = false (unless props.Anchored / kit Anchored), CanCollide = CanQuery = CanTouch = false,
--   Massless = true, Top/BottomSurface = Smooth, Material = SmoothPlastic, attribute "Role"
--   (default "Detail"), CastShadow = true unless the part is small (largest side < 0.3 studs).
-- Units: studs. CFrames are in the space you build in (for rigs: model space at rest pose).
-- Y up, front = -Z (LookVector), right = +X. Cylinders run along their CFrame's X axis (Roblox rule).
--
-- USAGE
--   local PartKit = require(path.to.PartKit)
--   PartKit.Ball(parent, "Knob", 0.5, CFrame.new(0, 2, 0), Color3.new(1, 1, 1), { Role = "Bone" })
--   local K = PartKit.WithScale(1.5)   -- same API; sizes and CFrame POSITIONS are multiplied by 1.5
--   local K2 = PartKit.new({ Scale = 1, Anchored = true, Sink = function(part) end })
-- The module itself is a kit with Scale 1 (PartKit.Ball == PartKit.new().Ball semantics).
-- Rigs: blueprints should use the RigContext helpers (rig.Ball("Head", ...)) which parent to the
-- limb and weld automatically; RigBuilder rescales the finished model, so author at scale 1.
-- Scaled kits are meant for props/maps authored at scale 1: feed them ONLY authoring-space CFrames
-- (never CFrames read back from parts that were already built with the scaled kit).
--
-- BUILDERS (all take a final optional `props: Props`; single-part builders return the part,
-- multi-part builders return {BasePart} with the main part first; part names: name, name_2, ...)
--   Part(parent, name, shape, size, cf, color, props)            shape: "Block"|"Ball"|"Cylinder"|"Wedge"|"CornerWedge"
--   Box(parent, name, size, cf, color, props)
--   Ellipsoid(parent, name, size, cf, color, props)              Block + SpecialMesh Sphere (fills size)
--   Ball(parent, name, diameter, cf, color, props)
--   Cyl(parent, name, length, diameter, cf, color, props)        axis = cf.XVector
--   Disc(parent, name, diameter, thickness, cf, color, props)    flat cylinder whose faces look along cf.LookVector
--   CylBetween(parent, name, p0, p1, diameter, color, props)     props.Roll (deg) spins it about its axis
--   Wedge(parent, name, size, cf, color, props)                  WedgePart (slope faces front/up, tall side at +Z)
--   CornerWedge(parent, name, size, cf, color, props)            CornerWedgePart
--   RoundedBox(parent, name, size, cf, color, radius, props) -> {BasePart}
--        props.Round = "All" (3 slabs + 12 edge cylinders + 8 balls = 23 parts, default)
--                    | "X"|"Y"|"Z" (only the 4 edges parallel to that axis: 6 parts, cheap)
--   Cone(parent, name, p0, p1, d0, d1, color, props) -> {BasePart}   stacked cylinders (props.Segments, default 5)
--   Taper(parent, name, p0, p1, d0, d1, color, props) -> {BasePart}  overlapping balls (smooth horn/tuft), props.Segments
--   Bone(parent, name, p0, p1, thickness, color, props) -> {BasePart} cartoon bone: shaft + 2 knobs per end (5 parts)
--        props.Roll (deg) spins the knob pair about the shaft, props.KnobScale (default 1.45)
--   Ring(parent, name, cf, radius, count, ballSize, color, props) -> {BasePart}
--        balls on a circle in cf's local XZ plane (ring axis = cf.UpVector), props.Phase (deg)
--   Arc(parent, name, centerCF, radius, fromDeg, toDeg, segments, thickness, depth, color, props) -> {BasePart}
--        box segments along a circle in centerCF's local XY plane (0 deg = +X, 90 deg = +Y), depth
--        along centerCF.ZVector. A smile on a face: centerCF facing out, fromDeg 200, toDeg 340.
--        props.Joints = true adds balls between segments (round stroke).
--   Tube(parent, name, points, diameter, color, props) -> {BasePart}
--        cylinders through the points with balls at the joints; diameter may be a number or a
--        per-point {number}; props.Caps = true also caps both ends with balls.
--   Dashes(parent, name, points, dashLength, gap, thickness, color, props) -> {BasePart}
--        evenly spaced short boxes along a polyline (stitches, seams, road marks).
--        props.Depth (default = thickness), props.Normal: Vector3? (the dash's thin axis faces it)
-- PLACEMENT HELPERS (pure maths, never scaled)
--   OnEllipsoid(centerCF, radii, yawDeg, pitchDeg, inset?) -> CFrame
--        point on the ellipsoid (radii = semi-axes, i.e. Size/2) whose LookVector is the outward
--        surface normal and whose UpVector stays close to centerCF.UpVector. yaw 0 = front (-Z),
--        +yaw towards +X (the character's RIGHT), +pitch upwards. inset > 0 pushes it inside.
--   Basis(pos, xAxis, upHint?) -> CFrame      frame whose XVector = xAxis (robust when parallel to up)
--   LookFrame(pos, look, upHint?) -> CFrame   frame whose LookVector = look
-- INSTANCES
--   Weld(part0, part1) -> WeldConstraint  (parented to part1, named "Weld_<part0>")
--   Attach(part, name, localCF) -> Attachment  (re-uses an existing child with that name)
--   Light(part, kind: "Point"|"Spot"|"Surface", props) -> Light
--        props: Brightness (1), Range (8, scaled), Color (white), Shadows (false), Angle, Face, Name
-- UTILITIES (module level)
--   PartKit.new(opts) / PartKit.WithScale(s) -> Kit
--   PartKit.ScaleModel(root, factor, origin?)  uniform rescale of an instance tree (Lune-safe ScaleTo):
--        part sizes/positions, SpecialMesh offsets, attachments, joint C0/C1, light ranges,
--        Humanoid.HipHeight, ParticleEmitter sizes/speeds, Beam widths
--   PartKit.Shade(color, amount) (-1..1, <0 darker, >0 lighter), PartKit.Mix(a, b, t)
--   PartKit.ROLES -> the valid Role attribute values (SPEC §5.1)

local PartKit = {}

export type Props = {
	Name: string?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	Role: string?,
	CastShadow: boolean?,
	Anchored: boolean?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	Massless: boolean?,
	Attributes: { [string]: any }?,
	-- builder options (ignored by single-part builders)
	Segments: number?,
	Round: string?,
	Roll: number?,
	KnobScale: number?,
	Phase: number?,
	Joints: boolean?,
	Caps: boolean?,
	Overlap: number?,
	Depth: number?,
	Normal: Vector3?,
	-- Light options
	Brightness: number?,
	Range: number?,
	Color: Color3?,
	Shadows: boolean?,
	Angle: number?,
	Face: Enum.NormalId?,
}

export type KitOptions = {
	Scale: number?,
	Anchored: boolean?,
	Material: Enum.Material?,
	Role: string?,
	Sink: ((part: BasePart) -> ())?,
}

export type Kit = {
	Scale: number,
	Part: (parent: Instance?, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Box: (parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Ellipsoid: (parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Ball: (parent: Instance?, name: string, diameter: number, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Cyl: (parent: Instance?, name: string, length: number, diameter: number, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Disc: (parent: Instance?, name: string, diameter: number, thickness: number, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	CylBetween: (parent: Instance?, name: string, p0: Vector3, p1: Vector3, diameter: number, color: Color3, props: Props?) -> BasePart,
	Wedge: (parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	CornerWedge: (parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	RoundedBox: (parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, radius: number, props: Props?) -> { BasePart },
	Cone: (parent: Instance?, name: string, p0: Vector3, p1: Vector3, d0: number, d1: number, color: Color3, props: Props?) -> { BasePart },
	Taper: (parent: Instance?, name: string, p0: Vector3, p1: Vector3, d0: number, d1: number, color: Color3, props: Props?) -> { BasePart },
	Bone: (parent: Instance?, name: string, p0: Vector3, p1: Vector3, thickness: number, color: Color3, props: Props?) -> { BasePart },
	Ring: (parent: Instance?, name: string, cf: CFrame, radius: number, count: number, ballSize: number, color: Color3, props: Props?) -> { BasePart },
	Arc: (
		parent: Instance?,
		name: string,
		centerCF: CFrame,
		radius: number,
		fromDeg: number,
		toDeg: number,
		segments: number,
		thickness: number,
		depth: number,
		color: Color3,
		props: Props?
	) -> { BasePart },
	Tube: (parent: Instance?, name: string, points: { Vector3 }, diameter: number | { number }, color: Color3, props: Props?) -> { BasePart },
	Dashes: (
		parent: Instance?,
		name: string,
		points: { Vector3 },
		dashLength: number,
		gap: number,
		thickness: number,
		color: Color3,
		props: Props?
	) -> { BasePart },
	OnEllipsoid: (centerCF: CFrame, radii: Vector3, yawDeg: number, pitchDeg: number, inset: number?) -> CFrame,
	Basis: (pos: Vector3, xAxis: Vector3, upHint: Vector3?) -> CFrame,
	LookFrame: (pos: Vector3, look: Vector3, upHint: Vector3?) -> CFrame,
	Weld: (part0: BasePart, part1: BasePart) -> WeldConstraint,
	Attach: (part: BasePart, name: string, cf: CFrame) -> Attachment,
	Light: (part: BasePart, kind: string, props: Props?) -> Light,
}

PartKit.ROLES = {
	"Skin",
	"Bone",
	"Cloth",
	"ClothAlt",
	"Trim",
	"Accent",
	"Eye",
	"Glow",
	"Hair",
	"Metal",
	"Weapon",
	"Detail",
	"Dark",
}

PartKit.SMALL_PART = 0.3 -- parts whose largest side is below this do not cast shadows by default

local EMPTY: Props = {}
local Y_AXIS = Vector3.new(0, 1, 0)
local Z_AXIS = Vector3.new(0, 0, 1)
local X_AXIS = Vector3.new(1, 0, 0)

-- Pure maths helpers --------------------------------------------------------------------------

-- Frame whose XVector points along xAxis; Y as close as possible to upHint.
local function basis(pos: Vector3, xAxis: Vector3, upHint: Vector3?): CFrame
	local x = xAxis.Unit
	local up = upHint or Y_AXIS
	if math.abs(x:Dot(up.Unit)) > 0.985 then
		up = if math.abs(x:Dot(Z_AXIS)) > 0.985 then Y_AXIS else Z_AXIS
	end
	local y = (up - x * x:Dot(up)).Unit
	local z = x:Cross(y)
	return CFrame.fromMatrix(pos, x, y, z)
end

-- Frame whose LookVector = look; UpVector as close as possible to upHint.
local function lookFrame(pos: Vector3, look: Vector3, upHint: Vector3?): CFrame
	local back = -look.Unit
	local up = upHint or Y_AXIS
	if math.abs(back:Dot(up.Unit)) > 0.985 then
		up = if math.abs(back:Dot(Z_AXIS)) > 0.985 then Y_AXIS else Z_AXIS
	end
	local right = up:Cross(back).Unit
	local y = back:Cross(right)
	return CFrame.fromMatrix(pos, right, y, back)
end

local function onEllipsoid(centerCF: CFrame, radii: Vector3, yawDeg: number, pitchDeg: number, inset: number?): CFrame
	local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
	local d = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
	local p = d * radii
	local n = Vector3.new(p.X / (radii.X * radii.X), p.Y / (radii.Y * radii.Y), p.Z / (radii.Z * radii.Z)).Unit
	local local_ = lookFrame(p - n * (inset or 0), n, Y_AXIS)
	return centerCF * local_
end

PartKit.Basis = basis
PartKit.LookFrame = lookFrame
PartKit.OnEllipsoid = onEllipsoid

function PartKit.Shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), math.min(amount, 1))
	end
	return color:Lerp(Color3.new(0, 0, 0), math.min(-amount, 1))
end

function PartKit.Mix(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function suffix(name: string, i: number): string
	if i <= 1 then
		return name
	end
	return name .. "_" .. tostring(i)
end

-- Kit factory ----------------------------------------------------------------------------------

function PartKit.new(options: KitOptions?): Kit
	local opts: KitOptions = options or {}
	local scale = opts.Scale or 1
	assert(scale > 0, "PartKit: scale must be positive")
	local kitAnchored = opts.Anchored == true
	local kitMaterial = opts.Material or Enum.Material.SmoothPlastic
	local kitRole = opts.Role or "Detail"
	local sink = opts.Sink

	local K: any = {}
	K.Scale = scale

	local function S(v: Vector3): Vector3
		return if scale == 1 then v else v * scale
	end
	local function P(v: Vector3): Vector3
		return if scale == 1 then v else v * scale
	end
	local function SC(cf: CFrame): CFrame
		if scale == 1 then
			return cf
		end
		return cf + (cf.Position * (scale - 1))
	end

	-- Applies the visual defaults + props, then parents (last) and reports to the sink.
	local function finish(part: BasePart, parent: Instance?, name: string, color: Color3, props: Props)
		part.Name = props.Name or name
		part.Color = color
		part.Material = props.Material or kitMaterial
		part.Transparency = props.Transparency or 0
		part.Reflectance = props.Reflectance or 0
		part.Anchored = if props.Anchored ~= nil then props.Anchored else kitAnchored
		part.CanCollide = props.CanCollide == true
		part.CanQuery = props.CanQuery == true
		part.CanTouch = props.CanTouch == true
		part.Massless = if props.Massless ~= nil then props.Massless else true
		local size = part.Size
		local largest = math.max(size.X, size.Y, size.Z)
		part.CastShadow = if props.CastShadow ~= nil then props.CastShadow else largest >= PartKit.SMALL_PART
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part:SetAttribute("Role", props.Role or kitRole)
		if props.Attributes then
			for key, value in props.Attributes do
				part:SetAttribute(key, value)
			end
		end
		part.Parent = parent
		if sink then
			sink(part)
		end
	end

	-- Raw (already scaled) constructors used internally.
	local function rawPart(parent: Instance?, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, props: Props): BasePart
		local part: BasePart
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		elseif shape == "CornerWedge" then
			part = Instance.new("CornerWedgePart")
		else
			local p = Instance.new("Part")
			if shape == "Ball" then
				p.Shape = Enum.PartType.Ball
			elseif shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
			elseif shape == "Block" then
				p.Shape = Enum.PartType.Block
			else
				error("PartKit: unknown shape " .. tostring(shape))
			end
			part = p
		end
		part.Size = size
		part.CFrame = cf
		finish(part, parent, name, color, props)
		return part
	end

	local function rawBall(parent: Instance?, name: string, d: number, pos: Vector3, color: Color3, props: Props): BasePart
		return rawPart(parent, name, "Ball", Vector3.new(d, d, d), CFrame.new(pos), color, props)
	end

	local function rawCylBetween(parent: Instance?, name: string, a: Vector3, b: Vector3, d: number, color: Color3, props: Props): BasePart
		local delta = b - a
		local length = delta.Magnitude
		assert(length > 1e-6, "PartKit.CylBetween: points coincide for " .. name)
		local cf = basis((a + b) / 2, delta, Y_AXIS)
		if props.Roll then
			cf = cf * CFrame.Angles(math.rad(props.Roll), 0, 0)
		end
		return rawPart(parent, name, "Cylinder", Vector3.new(length, d, d), cf, color, props)
	end

	-- Public single-part builders -----------------------------------------------------------

	function K.Part(parent: Instance?, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		return rawPart(parent, name, shape, S(size), SC(cf), color, props or EMPTY)
	end

	function K.Box(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		return rawPart(parent, name, "Block", S(size), SC(cf), color, props or EMPTY)
	end

	function K.Ellipsoid(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = S(size)
		part.CFrame = SC(cf)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1, 1)
		mesh.Parent = part
		finish(part, parent, name, color, props or EMPTY)
		return part
	end

	function K.Ball(parent: Instance?, name: string, diameter: number, cf: CFrame, color: Color3, props: Props?): BasePart
		local d = diameter * scale
		return rawPart(parent, name, "Ball", Vector3.new(d, d, d), SC(cf), color, props or EMPTY)
	end

	function K.Cyl(parent: Instance?, name: string, length: number, diameter: number, cf: CFrame, color: Color3, props: Props?): BasePart
		local size = Vector3.new(length * scale, diameter * scale, diameter * scale)
		return rawPart(parent, name, "Cylinder", size, SC(cf), color, props or EMPTY)
	end

	function K.Disc(parent: Instance?, name: string, diameter: number, thickness: number, cf: CFrame, color: Color3, props: Props?): BasePart
		local size = Vector3.new(thickness * scale, diameter * scale, diameter * scale)
		return rawPart(parent, name, "Cylinder", size, SC(cf) * CFrame.Angles(0, math.pi / 2, 0), color, props or EMPTY)
	end

	function K.CylBetween(parent: Instance?, name: string, p0: Vector3, p1: Vector3, diameter: number, color: Color3, props: Props?): BasePart
		return rawCylBetween(parent, name, P(p0), P(p1), diameter * scale, color, props or EMPTY)
	end

	function K.Wedge(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		return rawPart(parent, name, "Wedge", S(size), SC(cf), color, props or EMPTY)
	end

	function K.CornerWedge(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): BasePart
		return rawPart(parent, name, "CornerWedge", S(size), SC(cf), color, props or EMPTY)
	end

	-- Multi-part builders -------------------------------------------------------------------

	function K.RoundedBox(parent: Instance?, name: string, size: Vector3, cf: CFrame, color: Color3, radius: number, props: Props?): { BasePart }
		local pr = props or EMPTY
		local sz = S(size)
		local c = SC(cf)
		local r = math.min(radius * scale, math.min(sz.X, sz.Y, sz.Z) / 2 - 1e-3)
		local mode = pr.Round or "All"
		local out: { BasePart } = {}
		local n = 0
		local function add(p: BasePart)
			table.insert(out, p)
		end
		local function nextName(): string
			n += 1
			return suffix(name, n)
		end
		if r <= 1e-3 then
			add(rawPart(parent, name, "Block", sz, c, color, pr))
			return out
		end
		local hx, hy, hz = sz.X / 2 - r, sz.Y / 2 - r, sz.Z / 2 - r
		if mode == "All" then
			add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X, sz.Y - 2 * r, sz.Z - 2 * r), c, color, pr))
			add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X - 2 * r, sz.Y, sz.Z - 2 * r), c, color, pr))
			add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X - 2 * r, sz.Y - 2 * r, sz.Z), c, color, pr))
			for _, sy in { -1, 1 } do
				for _, sz2 in { -1, 1 } do
					-- edges along X
					add(rawPart(parent, nextName(), "Cylinder", Vector3.new(2 * hx, 2 * r, 2 * r), c * CFrame.new(0, sy * hy, sz2 * hz), color, pr))
				end
			end
			for _, sx in { -1, 1 } do
				for _, sz2 in { -1, 1 } do
					-- edges along Y
					add(
						rawPart(
							parent,
							nextName(),
							"Cylinder",
							Vector3.new(2 * hy, 2 * r, 2 * r),
							c * CFrame.new(sx * hx, 0, sz2 * hz) * CFrame.Angles(0, 0, math.pi / 2),
							color,
							pr
						)
					)
				end
			end
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					-- edges along Z
					add(
						rawPart(
							parent,
							nextName(),
							"Cylinder",
							Vector3.new(2 * hz, 2 * r, 2 * r),
							c * CFrame.new(sx * hx, sy * hy, 0) * CFrame.Angles(0, math.pi / 2, 0),
							color,
							pr
						)
					)
				end
			end
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz2 in { -1, 1 } do
						add(rawBall(parent, nextName(), 2 * r, (c * CFrame.new(sx * hx, sy * hy, sz2 * hz)).Position, color, pr))
					end
				end
			end
		else
			-- Only the 4 edges parallel to `mode` are rounded.
			local axisCF: CFrame = CFrame.new()
			local a: number, b: number, len: number = 0, 0, 0
			if mode == "X" then
				axisCF = CFrame.new()
				a, b, len = hy, hz, sz.X
				add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X, sz.Y - 2 * r, sz.Z), c, color, pr))
				add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X, sz.Y, sz.Z - 2 * r), c, color, pr))
			elseif mode == "Y" then
				axisCF = CFrame.Angles(0, 0, math.pi / 2)
				a, b, len = hx, hz, sz.Y
				add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X - 2 * r, sz.Y, sz.Z), c, color, pr))
				add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X, sz.Y, sz.Z - 2 * r), c, color, pr))
			elseif mode == "Z" then
				axisCF = CFrame.Angles(0, math.pi / 2, 0)
				a, b, len = hx, hy, sz.Z
				add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X - 2 * r, sz.Y, sz.Z), c, color, pr))
				add(rawPart(parent, nextName(), "Block", Vector3.new(sz.X, sz.Y - 2 * r, sz.Z), c, color, pr))
			else
				error("PartKit.RoundedBox: props.Round must be All|X|Y|Z")
			end
			for _, s1 in { -1, 1 } do
				for _, s2 in { -1, 1 } do
					local offset: Vector3
					if mode == "X" then
						offset = Vector3.new(0, s1 * a, s2 * b)
					elseif mode == "Y" then
						offset = Vector3.new(s1 * a, 0, s2 * b)
					else
						offset = Vector3.new(s1 * a, s2 * b, 0)
					end
					add(rawPart(parent, nextName(), "Cylinder", Vector3.new(len, 2 * r, 2 * r), c * CFrame.new(offset) * axisCF, color, pr))
				end
			end
		end
		return out
	end

	function K.Cone(parent: Instance?, name: string, p0: Vector3, p1: Vector3, d0: number, d1: number, color: Color3, props: Props?): { BasePart }
		local pr = props or EMPTY
		local a, b = P(p0), P(p1)
		local segs = math.max(1, math.floor(pr.Segments or 5))
		local out: { BasePart } = {}
		for i = 1, segs do
			local t0, t1 = (i - 1) / segs, i / segs
			local d = (d0 + (d1 - d0) * ((t0 + t1) / 2)) * scale
			d = math.max(d, 0.02)
			table.insert(out, rawCylBetween(parent, suffix(name, i), a:Lerp(b, t0), a:Lerp(b, t1), d, color, pr))
		end
		return out
	end

	function K.Taper(parent: Instance?, name: string, p0: Vector3, p1: Vector3, d0: number, d1: number, color: Color3, props: Props?): { BasePart }
		local pr = props or EMPTY
		local a, b = P(p0), P(p1)
		local length = (b - a).Magnitude
		local smallest = math.max(math.min(d0, d1) * scale, 0.02)
		local segs = pr.Segments or math.clamp(math.ceil(length / (smallest * 0.6)), 2, 24)
		segs = math.max(2, math.floor(segs))
		local out: { BasePart } = {}
		for i = 1, segs do
			local t = (i - 1) / (segs - 1)
			local d = math.max((d0 + (d1 - d0) * t) * scale, 0.02)
			table.insert(out, rawBall(parent, suffix(name, i), d, a:Lerp(b, t), color, pr))
		end
		return out
	end

	function K.Bone(parent: Instance?, name: string, p0: Vector3, p1: Vector3, thickness: number, color: Color3, props: Props?): { BasePart }
		local pr = props or EMPTY
		local a, b = P(p0), P(p1)
		local t = thickness * scale
		local axis = (b - a)
		assert(axis.Magnitude > 1e-6, "PartKit.Bone: points coincide")
		local frame = basis(a, axis, Y_AXIS)
		if pr.Roll then
			frame = frame * CFrame.Angles(math.rad(pr.Roll), 0, 0)
		end
		local dir = axis.Unit
		local side = frame.UpVector -- unit, perpendicular to the shaft (frame X = shaft axis)
		local knob = t * (pr.KnobScale or 1.45)
		local spread = t * 0.42
		local inset = knob * 0.18
		local out: { BasePart } = {}
		table.insert(out, rawCylBetween(parent, name, a + dir * inset, b - dir * inset, t, color, pr))
		local i = 1
		for _, endPoint in { a + dir * inset, b - dir * inset } do
			for _, s in { -1, 1 } do
				i += 1
				table.insert(out, rawBall(parent, suffix(name, i), knob, endPoint + side * (s * spread), color, pr))
			end
		end
		return out
	end

	function K.Ring(parent: Instance?, name: string, cf: CFrame, radius: number, count: number, ballSize: number, color: Color3, props: Props?): { BasePart }
		local pr = props or EMPTY
		local c = SC(cf)
		local r = radius * scale
		local d = ballSize * scale
		local phase = math.rad(pr.Phase or 0)
		local out: { BasePart } = {}
		local n = math.max(1, math.floor(count))
		for i = 1, n do
			local ang = phase + (i - 1) / n * math.pi * 2
			local pos = (c * CFrame.new(math.cos(ang) * r, 0, math.sin(ang) * r)).Position
			table.insert(out, rawBall(parent, suffix(name, i), d, pos, color, pr))
		end
		return out
	end

	function K.Arc(
		parent: Instance?,
		name: string,
		centerCF: CFrame,
		radius: number,
		fromDeg: number,
		toDeg: number,
		segments: number,
		thickness: number,
		depth: number,
		color: Color3,
		props: Props?
	): { BasePart }
		local pr = props or EMPTY
		local c = SC(centerCF)
		local r = radius * scale
		local th, dp = thickness * scale, depth * scale
		local segs = math.max(1, math.floor(segments))
		local overlap = (pr.Overlap or 0.5) * th
		local out: { BasePart } = {}
		local function at(deg: number): Vector3
			local a = math.rad(deg)
			return (c * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0)).Position
		end
		local zAxis = c.ZVector
		local idx = 0
		for i = 1, segs do
			local a0 = fromDeg + (toDeg - fromDeg) * (i - 1) / segs
			local a1 = fromDeg + (toDeg - fromDeg) * i / segs
			local q0, q1 = at(a0), at(a1)
			local tangent = q1 - q0
			local len = tangent.Magnitude
			if len > 1e-6 then
				local x = tangent.Unit
				local y = zAxis:Cross(x).Unit
				local z = x:Cross(y)
				local cfSeg = CFrame.fromMatrix((q0 + q1) / 2, x, y, z)
				idx += 1
				table.insert(out, rawPart(parent, suffix(name, idx), "Block", Vector3.new(len + overlap, th, dp), cfSeg, color, pr))
				if pr.Joints and i < segs then
					idx += 1
					table.insert(out, rawBall(parent, suffix(name, idx), math.min(th, dp), q1, color, pr))
				end
			end
		end
		return out
	end

	function K.Tube(parent: Instance?, name: string, points: { Vector3 }, diameter: number | { number }, color: Color3, props: Props?): { BasePart }
		local pr = props or EMPTY
		assert(#points >= 2, "PartKit.Tube needs at least 2 points")
		local function dAt(i: number): number
			if type(diameter) == "number" then
				return diameter * scale
			end
			local list = diameter :: { number }
			return (list[i] or list[#list]) * scale
		end
		local out: { BasePart } = {}
		local idx = 0
		for i = 1, #points - 1 do
			idx += 1
			local d = (dAt(i) + dAt(i + 1)) / 2
			table.insert(out, rawCylBetween(parent, suffix(name, idx), P(points[i]), P(points[i + 1]), d, color, pr))
		end
		local first, last = 2, #points - 1
		if pr.Caps then
			first, last = 1, #points
		end
		for i = first, last do
			idx += 1
			table.insert(out, rawBall(parent, suffix(name, idx), dAt(i), P(points[i]), color, pr))
		end
		return out
	end

	function K.Dashes(
		parent: Instance?,
		name: string,
		points: { Vector3 },
		dashLength: number,
		gap: number,
		thickness: number,
		color: Color3,
		props: Props?
	): { BasePart }
		local pr = props or EMPTY
		assert(#points >= 2, "PartKit.Dashes needs at least 2 points")
		local pts: { Vector3 } = {}
		for i, p in points do
			pts[i] = P(p)
		end
		local dash, step = dashLength * scale, (dashLength + gap) * scale
		local th = thickness * scale
		local depth = (pr.Depth or thickness) * scale
		-- cumulative lengths
		local cum = { 0 }
		for i = 2, #pts do
			cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
		end
		local total = cum[#pts]
		local count = math.max(1, math.floor((total + gap * scale) / step))
		local used = count * step - gap * scale
		local start = (total - used) / 2 + dash / 2
		local out: { BasePart } = {}
		local seg = 2
		for i = 1, count do
			local s = start + (i - 1) * step
			while seg < #pts and cum[seg] < s do
				seg += 1
			end
			local p0, p1 = pts[seg - 1], pts[seg]
			local segLen = cum[seg] - cum[seg - 1]
			local t = if segLen > 1e-9 then (s - cum[seg - 1]) / segLen else 0
			local pos = p0:Lerp(p1, math.clamp(t, 0, 1))
			local dir = p1 - p0
			local cf: CFrame
			if pr.Normal then
				-- X along the stroke, Z (thin "depth" axis) along the given normal
				local x = dir.Unit
				local nz = (pr.Normal - x * x:Dot(pr.Normal)).Unit
				local y = nz:Cross(x)
				cf = CFrame.fromMatrix(pos, x, y, nz)
			else
				cf = basis(pos, dir, Y_AXIS)
			end
			table.insert(out, rawPart(parent, suffix(name, i), "Block", Vector3.new(dash, th, depth), cf, color, pr))
		end
		return out
	end

	-- Placement helpers (pure) --------------------------------------------------------------
	K.OnEllipsoid = onEllipsoid
	K.Basis = basis
	K.LookFrame = lookFrame

	-- Instances -----------------------------------------------------------------------------

	function K.Weld(part0: BasePart, part1: BasePart): WeldConstraint
		local weld = Instance.new("WeldConstraint")
		weld.Name = "Weld_" .. part0.Name
		weld.Part0 = part0
		weld.Part1 = part1
		weld.Parent = part1
		return weld
	end

	function K.Attach(part: BasePart, name: string, cf: CFrame): Attachment
		local existing = part:FindFirstChild(name)
		local att: Attachment
		if existing and existing:IsA("Attachment") then
			att = existing
		else
			att = Instance.new("Attachment")
			att.Name = name
		end
		att.CFrame = SC(cf)
		att.Parent = part
		return att
	end

	function K.Light(part: BasePart, kind: string, props: Props?): Light
		local pr = props or EMPTY
		local light: Light
		if kind == "Point" then
			light = Instance.new("PointLight")
		elseif kind == "Spot" then
			local spot = Instance.new("SpotLight")
			spot.Angle = pr.Angle or 60
			spot.Face = pr.Face or Enum.NormalId.Front
			light = spot
		elseif kind == "Surface" then
			local surf = Instance.new("SurfaceLight")
			surf.Angle = pr.Angle or 90
			surf.Face = pr.Face or Enum.NormalId.Front
			light = surf
		else
			error("PartKit.Light: kind must be Point|Spot|Surface")
		end
		light.Name = pr.Name or (kind .. "Light")
		light.Brightness = pr.Brightness or 1
		light.Color = pr.Color or Color3.new(1, 1, 1)
		light.Shadows = pr.Shadows == true
		local range = (pr.Range or 8) * scale
		if light:IsA("PointLight") then
			light.Range = range
		elseif light:IsA("SpotLight") then
			light.Range = range
		elseif light:IsA("SurfaceLight") then
			light.Range = range
		end
		light.Parent = part
		return light
	end

	return K :: Kit
end

function PartKit.WithScale(s: number): Kit
	return PartKit.new({ Scale = s })
end

-- Uniform rescale of an instance tree around `origin` (default (0,0,0)). Lune-safe replacement
-- for Model:ScaleTo. Call it on a model that is NOT simulated (built, not yet parented to workspace).
function PartKit.ScaleModel(root: Instance, factor: number, origin: Vector3?)
	assert(factor > 0, "PartKit.ScaleModel: factor must be positive")
	if factor == 1 then
		return
	end
	local o = origin or Vector3.new(0, 0, 0)
	local function scaleCF(cf: CFrame): CFrame
		return cf + (cf.Position * (factor - 1))
	end
	local function scaleSeq(seq: NumberSequence): NumberSequence
		local keys = {}
		for i, k in seq.Keypoints do
			keys[i] = NumberSequenceKeypoint.new(k.Time, k.Value * factor, k.Envelope * factor)
		end
		return NumberSequence.new(keys)
	end
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, inst in list do
		if inst:IsA("BasePart") then
			local cf = inst.CFrame
			local pos = o + (cf.Position - o) * factor
			inst.Size = inst.Size * factor
			inst.CFrame = cf + (pos - cf.Position)
		elseif inst:IsA("SpecialMesh") then
			inst.Offset = inst.Offset * factor
			if inst.MeshType == Enum.MeshType.FileMesh then
				inst.Scale = inst.Scale * factor
			end
		elseif inst:IsA("DataModelMesh") then
			local mesh = inst :: any
			mesh.Offset = mesh.Offset * factor
		elseif inst:IsA("Attachment") then
			inst.CFrame = scaleCF(inst.CFrame)
		elseif inst:IsA("JointInstance") then
			local joint = inst :: any
			joint.C0 = scaleCF(joint.C0)
			joint.C1 = scaleCF(joint.C1)
		elseif inst:IsA("PointLight") then
			inst.Range = inst.Range * factor
		elseif inst:IsA("SpotLight") then
			inst.Range = inst.Range * factor
		elseif inst:IsA("SurfaceLight") then
			inst.Range = inst.Range * factor
		elseif inst:IsA("Humanoid") then
			inst.HipHeight = inst.HipHeight * factor
		elseif inst:IsA("ParticleEmitter") then
			inst.Size = scaleSeq(inst.Size)
			inst.Speed = NumberRange.new(inst.Speed.Min * factor, inst.Speed.Max * factor)
			inst.Acceleration = inst.Acceleration * factor
		elseif inst:IsA("Beam") then
			inst.Width0 = inst.Width0 * factor
			inst.Width1 = inst.Width1 * factor
			inst.CurveSize0 = inst.CurveSize0 * factor
			inst.CurveSize1 = inst.CurveSize1 * factor
		end
	end
end

-- Module-level default kit (scale 1, not anchored): PartKit.Ball(...), PartKit.Weld(...), ...
local default = PartKit.new()
for key, value in default :: any do
	if (PartKit :: any)[key] == nil then
		(PartKit :: any)[key] = value
	end
end

return PartKit
