--!strict
-- Maps/MapKit: high-level, deterministic map-building helpers on top of Rigs/PartKit. [Lune-safe]
-- Every map module builds around the world origin (walkable floor top at y = 0, forward = -Z); MapService
-- moves the finished Model. A builder owns one Model with four category folders:
--   Geometry (collidable + queryable: floors, walls, pillar shafts, stairs ramps, invisible boundaries)
--   Decor    (CanCollide = CanQuery = false: trims, flutes, glass, banners, foliage, lamps' bodies...)
--   Lights   (invisible holder parts carrying every PointLight/SpotLight/SurfaceLight -> easy to scale/cull)
--   Markers  (invisible, non-colliding named parts: spawns, SAVE points, podiums, boards, kill floor...)
-- B:Group(name) routes the following parts into a same-named sub-folder of each category.
-- Part and light budgets (SPEC §14: <= 6000 parts, <= 60 lights) are tracked; B:Finish() stamps them as
-- model attributes (PartCount, LightCount) and MapKit.Validate checks them.
--
-- MODULE API (pure helpers)
--   MapKit.new(name, opts?) -> Builder          opts = { Seed: number?, PartBudget: number?, LightBudget: number? }
--   MapKit.LookAt(pos, target) -> CFrame        LookVector towards target (fromMatrix: identical in Roblox and Lune)
--   MapKit.Facing(pos, target) -> CFrame        level (yaw-only) version of LookAt
--   MapKit.Yaw(pos, deg) -> CFrame              CFrame.new(pos) * CFrame.Angles(0, rad(deg), 0) (+deg turns LEFT)
--   MapKit.Ground(root) -> probe(pos, up?, maxDrop?) -> (surfaceY?, partName?)
--        pure-maths vertical ray cast against every CanCollide part (Block/Wedge/Cylinder/Ball, any rotation)
--   MapKit.Stats(root) -> { Parts, Lights, Colliders, Markers, Decor }
--   MapKit.Validate(info, opts?) -> (ok, {problems})   MapInfo contract + budgets + spawns/saves on solid ground
--        opts = { Kind: "Arena"|"Lobby"?, MinHumanSpawns: number?, Saves: number?, PartBudget?, LightBudget? }
--   MapKit.Fingerprint(root) -> string           order-dependent hash of every part (determinism tests)
--   MapKit.Shade(color, amount), MapKit.Mix(a, b, t)   (PartKit re-exports)
--
-- BUILDER API  (B = MapKit.new(...); every method is deterministic; colours are Color3, positions Vector3)
--   B.Model, B.Rng (Util/Rng), B.Folders.{Geometry,Decor,Lights,Markers}, B.PartCount, B.LightCount
--   B:Group(name?) -> previousName
--   B:Solid(shape, name, size, cf, color, material?, props?) -> BasePart    collidable geometry
--   B:Deco(shape, name, size, cf, color, material?, props?) -> BasePart     decor (no collision / queries)
--        shape: "Block"|"Ball"|"Cylinder"|"Wedge"|"CornerWedge"|"Ellipsoid"; props: { Collide, Query, Shadow,
--        Transparency, Reflectance, Category ("Geometry"|"Decor"), Parent (Instance) }
--   B:Disc(category, name, center, diameter, thickness, color, material?, props?)  upright cylinder (axis Y)
--   B:Triangle(category, name, a, b, c, thickness, color, material?, props?) -> {WedgePart} (2 wedges)
--   B:Cone(category, name, base, height, radius, sides, color, material?, props?) -> {parts}  n-sided pyramid
--        props.Phase (deg), props.Tip (Vector3 offset of the apex)
--   B:Star(category, name, cf, outerR, innerR, depth, color, material?, props?)   faceted 5-point star in cf's
--        local XY plane (points up = cf.UpVector), depth > 0 -> 3D bevelled (20 tris), depth = 0 -> flat (10 tris)
--   B:Heart(category, name, cf, size, thickness, color, material?, props?)         heart in cf's local XY plane
--   B:Floor(name, top: Vector3, sizeX, sizeZ, opts)  slab whose top face is at top.Y; opts = { Color, Material,
--        Thickness, Pattern: nil|"Checker"|"Tiles"|"Planks", Tile, Color2, Material2, Grout, Border = {Width,
--        Color, Material}, Collide (true) }
--   B:Wall(name, cf, length, height, opts)  cf = bottom centre, local X along the wall, LookVector = INTERIOR.
--        opts = { Thickness, Color, Material, Openings = {{X, Width, Bottom, Top}}, Baseboard = {Height, Color,
--        Material?}, Rail = {Y, Height, Color}, Cornice = {Height, Color, Material?}, BothSides }
--   B:Column(name, base, height, diameter, opts) -> shaft   opts = { Style "Classic"|"Square"|"Simple", Color,
--        Accent, Dark, Material, AccentMaterial, Flutes, Collide }
--   B:Arch(name, cf, span, thickness, depth, color, opts)   cf = springline centre, local X = span direction
--   B:ArcRing(category, name, cf, radius, fromDeg, toDeg, segments, thickness, depth, color, material?, props?)
--   B:Ring(category, name, center, radius, thickness, height, segments, color, material?, props?)  horizontal ring
--   B:Window(name, cf, width, height, opts) -> {Light}  stained-glass window in an opening (cf = centre of the
--        rectangular opening on the wall mid-plane, LookVector = into the room); opts = { Frame, Lead, Clear,
--        Palette {Color3}, Arch (true), Cols, Rows, Light = {Brightness, Range, Color, Angle} | false, Depth }
--   B:Stairs(name, cf, width, rise, run, opts)  cf = bottom-front centre (LookVector = climbing direction);
--        visual steps + an invisible collidable ramp
--   B:Railing(name, a, b, opts)   posts + rail (+ balusters); opts = { Height, Spacing, Color, Material,
--        Balusters, Collide }
--   B:Banner(name, cf, width, length, opts)  cf = top centre, LookVector = the banner's front
--        opts = { Color, Trim, Emblem: "Heart"|"Star"|"Delta"|nil, EmblemColor, Rod }
--   B:Lamp(name, base, opts) -> Light?   opts = { Style "Post"|"Lantern"|"Wall"|"Brazier"|"Candle", Height,
--        Metal, Glow, LightColor, Brightness, Range, Shadows, Facing (Vector3 for Wall), NoLight }
--   B:Chandelier(name, hang, opts) -> Light?   hang = ceiling point; opts = { Drop, Radius, Arms, Metal, Glow,
--        LightColor, Brightness, Range, Shadows }
--   B:Pine(name, base, height, opts)    layered low-poly pine (n-sided cones) + snow caps
--        opts = { Tiers, Sides, Snow, Leaf, Trunk, SnowColor, Width (radius factor), Collide }
--   B:Tree(name, base, height, opts)    round-canopy tree (ellipsoid clusters)
--   B:Rock(name, center, size, opts)    cluster of rotated blocks; opts = { Color, Material, Snow, Collide }
--   B:Crystal(name, base, height, opts) cluster of glowing crystals; opts = { Color, Count, Light }
--   B:Bridge(name, a, b, width, opts)   arched plank bridge between two deck-top points (collidable planks)
--   B:Fence(name, points, opts)         posts + rails (collidable); opts = { Height, Spacing, Color, Snow }
--   B:Signpost(name, base, signs, opts) signs = {{Key|Text, Yaw (deg), Color?}}
--   B:House(name, cf, opts) -> {Lights}  cf = ground centre, LookVector = the door side. Solid body, gable roof,
--        glowing windows (+ PointLights), door, chimney (+ smoke), optional snow + icicles
--   B:Mound(name, center, radius, height, opts)  walkable sphere cap (Collide) or decorative ellipsoid drift
--   B:Bones(name, cf, opts) / B:SkullStatue(name, base, opts)   decorative bones / monster skull statue
--   B:Text(part, face, opts) -> SurfaceGui   opts = { Key, Args, Text, Font, Color, Stroke, Glow, Align, Pixels,
--        Width, Height, Attributes (set on the TextLabel) }
--        (TextLabel attribute "TextKey" lets clients re-localise; see LobbyController)
--   B:Prompt(part, opts) -> ProximityPrompt  opts = { Action, ActionKey, ObjectKey, Hold, Distance }
--   B:Light(kind, at: Vector3|CFrame, props) -> Light   kind "Point"|"Spot"|"Surface"; props = { Brightness,
--        Range (<= 120), Color, Shadows, Angle, Face, Size, Name }
--   B:Particles(part, preset, props?) -> ParticleEmitter   preset "Smoke"|"Sparkles"|"Motes"|"Embers"
--   B:Shaft(name, from, dir, width, height, length, color, opts?)   fake volumetric light shaft (translucent Neon)
--   B:Marker(name, cf, opts?) -> BasePart     opts = { Size, Attributes }
--   B:SavePoint(index, pos, opts?) -> Vector3  floor inlay (gold ring + star) + marker "SavePoint_<i>"
--   B:SpawnPoint(kind, index, cf) -> CFrame    marker "<kind>Spawn_<i>" (kind "Human"|"Monster"|"Lobby")
--   B:Boundary(name, cf, length, height, thickness?)   invisible wall (CanCollide, CanQuery false, no shadow)
--   B:BoundaryBox(center, sizeX, sizeZ, height)        4 invisible walls around a rectangle
--   B:KillFloor(y, size)                                marker "KillFloor" (visual reference of MapInfo.KillY)
--   B:Finish(mapId) -> { Parts, Lights }               attributes MapId/PartCount/LightCount + WorldPivot

local PartKit = require(script.Parent.Parent.Rigs.PartKit)
local Rng = require(script.Parent.Parent.Util.Rng)
local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

type MapInfo = Types.MapInfo

local MapKit = {}

MapKit.PART_BUDGET = 6000
MapKit.LIGHT_BUDGET = 60
MapKit.MAX_LIGHT_RANGE = 120

MapKit.Shade = PartKit.Shade
MapKit.Mix = PartKit.Mix

local HALF_PI = math.pi / 2
local UP = Vector3.new(0, 1, 0)
local UPRIGHT = CFrame.Angles(0, 0, HALF_PI) -- cylinder X axis -> world Y

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(255, 255, 255)
local SNOW = rgb(236, 242, 252)
local GOLD = rgb(214, 168, 72)
local DARK = rgb(40, 34, 30)

-- Pure helpers ----------------------------------------------------------------------------------------

function MapKit.LookAt(position: Vector3, target: Vector3): CFrame
	local delta = target - position
	if delta.Magnitude < 1e-6 then
		return CFrame.new(position)
	end
	local look = delta.Unit
	local up = UP
	if math.abs(look:Dot(up)) > 0.999 then
		up = Vector3.new(0, 0, -1)
	end
	local right = look:Cross(up).Unit
	local trueUp = right:Cross(look).Unit
	return CFrame.fromMatrix(position, right, trueUp, -look)
end

function MapKit.Facing(position: Vector3, target: Vector3): CFrame
	return MapKit.LookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

function MapKit.Yaw(position: Vector3, deg: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(deg), 0)
end

-- Horizontal frame at `pos` whose X axis runs along `dir` (projected on the ground) and whose
-- LookVector (-Z) is the horizontal normal on the `side` (+1 = left of dir when looking along it).
local function alongFrame(pos: Vector3, dir: Vector3): CFrame
	local d = Vector3.new(dir.X, 0, dir.Z)
	if d.Magnitude < 1e-6 then
		d = Vector3.new(1, 0, 0)
	end
	d = d.Unit
	local z = d:Cross(UP) -- right-handed: X = d, Y = up, Z = d x up
	return CFrame.fromMatrix(pos, d, UP, z)
end

-- Vertical-ray intersection helpers (local space). Return the distance t along the ray or nil.
local INF = math.huge

local function rayPlanes(o: Vector3, d: Vector3, planes: { { number } }): number?
	-- convex solid = intersection of half-spaces n . p <= w (plane = {nx, ny, nz, w})
	local tEnter, tExit = -INF, INF
	for _, pl in planes do
		local nx, ny, nz, w = pl[1], pl[2], pl[3], pl[4]
		local denom = nx * d.X + ny * d.Y + nz * d.Z
		local dist = w - (nx * o.X + ny * o.Y + nz * o.Z)
		if math.abs(denom) < 1e-9 then
			if dist < 0 then
				return nil
			end
		else
			local t = dist / denom
			if denom < 0 then
				if t > tEnter then
					tEnter = t
				end
			else
				if t < tExit then
					tExit = t
				end
			end
		end
		if tEnter > tExit then
			return nil
		end
	end
	if tExit < 0 then
		return nil
	end
	return if tEnter >= 0 then tEnter else 0
end

local function boxPlanes(s: Vector3): { { number } }
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	return {
		{ 1, 0, 0, hx },
		{ -1, 0, 0, hx },
		{ 0, 1, 0, hy },
		{ 0, -1, 0, hy },
		{ 0, 0, 1, hz },
		{ 0, 0, -1, hz },
	}
end

local function wedgePlanes(s: Vector3): { { number } }
	-- Roblox WedgePart: full bottom (-Y) and back (+Z) faces; slope from bottom-front to top-back.
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local planes = {
		{ 1, 0, 0, hx },
		{ -1, 0, 0, hx },
		{ 0, -1, 0, hy },
		{ 0, 0, 1, hz },
	}
	-- slope plane through (y=-hy, z=-hz) and (y=hy, z=hz): normal (0, sz, -sy), n.p <= 0
	local ny, nz = s.Z, -s.Y
	local len = math.sqrt(ny * ny + nz * nz)
	if len > 1e-9 then
		table.insert(planes, { 0, ny / len, nz / len, 0 })
	end
	return planes
end

local function rayCylinder(o: Vector3, d: Vector3, s: Vector3): number?
	-- axis = local X, length s.X, radius min(s.Y, s.Z) / 2
	local r = math.min(s.Y, s.Z) / 2
	local hx = s.X / 2
	local best: number? = nil
	-- side: (oy + t dy)^2 + (oz + t dz)^2 = r^2
	local a = d.Y * d.Y + d.Z * d.Z
	if a > 1e-12 then
		local b = 2 * (o.Y * d.Y + o.Z * d.Z)
		local c = o.Y * o.Y + o.Z * o.Z - r * r
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			local sq = math.sqrt(disc)
			for _, t in { (-b - sq) / (2 * a), (-b + sq) / (2 * a) } do
				if t >= 0 then
					local x = o.X + t * d.X
					if math.abs(x) <= hx + 1e-6 and (best == nil or t < (best :: number)) then
						best = t
					end
				end
			end
		end
	end
	-- caps x = +-hx
	if math.abs(d.X) > 1e-12 then
		for _, cx in { -hx, hx } do
			local t = (cx - o.X) / d.X
			if t >= 0 then
				local y, z = o.Y + t * d.Y, o.Z + t * d.Z
				if y * y + z * z <= r * r + 1e-6 and (best == nil or t < (best :: number)) then
					best = t
				end
			end
		end
	end
	-- origin inside the cylinder
	if o.Y * o.Y + o.Z * o.Z <= r * r and math.abs(o.X) <= hx then
		return 0
	end
	return best
end

local function raySphere(o: Vector3, d: Vector3, r: number): number?
	local b = o:Dot(d)
	local c = o:Dot(o) - r * r
	if c <= 0 then
		return 0
	end
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	local t = -b - math.sqrt(disc)
	return if t >= 0 then t else nil
end

type Collider = { Name: string, Inv: CFrame, Shape: string, Size: Vector3, Planes: { { number } }? }

local function colliderOf(part: BasePart): Collider?
	if not part.CanCollide then
		return nil
	end
	local shape = "Block"
	if part:IsA("WedgePart") then
		shape = "Wedge"
	elseif part:IsA("CornerWedgePart") then
		shape = "Block" -- conservative (bounding box)
	elseif part:IsA("Part") then
		local p = part :: Part
		if p.Shape == Enum.PartType.Cylinder then
			shape = "Cylinder"
		elseif p.Shape == Enum.PartType.Ball then
			shape = "Ball"
		end
	end
	local size = part.Size
	local planes: { { number } }? = nil
	if shape == "Block" then
		planes = boxPlanes(size)
	elseif shape == "Wedge" then
		planes = wedgePlanes(size)
	end
	return { Name = part.Name, Inv = part.CFrame:Inverse(), Shape = shape, Size = size, Planes = planes }
end

-- Returns a probe function that finds the highest collidable surface under a point.
function MapKit.Ground(root: Instance): (Vector3, number?, number?) -> (number?, string?)
	local colliders: { Collider } = {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			local c = colliderOf(inst)
			if c then
				table.insert(colliders, c)
			end
		end
	end
	return function(pos: Vector3, up: number?, maxDrop: number?): (number?, string?)
		local origin = pos + Vector3.new(0, up or 3, 0)
		local reach = (up or 3) + (maxDrop or 50)
		local bestT: number? = nil
		local bestName: string? = nil
		local dirW = Vector3.new(0, -1, 0)
		for _, c in colliders do
			local o = c.Inv * origin
			local d = c.Inv:VectorToWorldSpace(dirW)
			local t: number? = nil
			if c.Shape == "Cylinder" then
				t = rayCylinder(o, d, c.Size)
			elseif c.Shape == "Ball" then
				t = raySphere(o, d, math.min(c.Size.X, c.Size.Y, c.Size.Z) / 2)
			elseif c.Planes then
				t = rayPlanes(o, d, c.Planes)
			end
			if t and t <= reach and (bestT == nil or t < (bestT :: number)) then
				bestT = t
				bestName = c.Name
			end
		end
		if bestT == nil then
			return nil, nil
		end
		return origin.Y - (bestT :: number), bestName
	end
end

function MapKit.Stats(root: Instance): { [string]: number }
	local stats = { Parts = 0, Lights = 0, Colliders = 0, Markers = 0, Decor = 0 }
	local markers = root:FindFirstChild("Markers")
	local decor = root:FindFirstChild("Decor")
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			stats.Parts += 1
			if inst.CanCollide then
				stats.Colliders += 1
			end
			if markers and inst:IsDescendantOf(markers) then
				stats.Markers += 1
			elseif decor and inst:IsDescendantOf(decor) then
				stats.Decor += 1
			end
		elseif inst:IsA("Light") then
			stats.Lights += 1
		end
	end
	return stats
end

local function fmt(n: number): string
	return string.format("%.3f", n)
end

function MapKit.Fingerprint(root: Instance): string
	local h = Rng.Hash("fp")
	local count = 0
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			count += 1
			local cf = inst.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			local s = inst.Size
			local c = inst.Color
			local line = table.concat({
				inst.Name,
				fmt(x),
				fmt(y),
				fmt(z),
				fmt(r00),
				fmt(r01),
				fmt(r02),
				fmt(r10),
				fmt(r11),
				fmt(r12),
				fmt(r20),
				fmt(r21),
				fmt(r22),
				fmt(s.X),
				fmt(s.Y),
				fmt(s.Z),
				fmt(c.R),
				fmt(c.G),
				fmt(c.B),
				inst.Material.Name,
			}, ",")
			h = Rng.Hash(h, line)
		end
	end
	return string.format("%d:%08x", count, h)
end

local function isCFrame(v: any): boolean
	return typeof(v) == "CFrame"
end

-- MapInfo contract check (used by tests and handy while authoring a map).
function MapKit.Validate(info: MapInfo, options: { [string]: any }?): (boolean, { string })
	local opts = options or {}
	local problems: { string } = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end
	if type(info) ~= "table" then
		return false, { "MapInfo is not a table" }
	end
	local kind = opts.Kind or "Arena"
	if typeof(info.Model) ~= "Instance" or not info.Model:IsA("Model") then
		return false, { "Model missing" }
	end
	local model = info.Model
	local minSpawns = opts.MinHumanSpawns or 8
	if type(info.HumanSpawns) ~= "table" or #info.HumanSpawns < minSpawns then
		bad(("HumanSpawns: need >= %d, got %d"):format(minSpawns, type(info.HumanSpawns) == "table" and #info.HumanSpawns or 0))
	end
	if not isCFrame(info.MonsterSpawn) then
		bad("MonsterSpawn is not a CFrame")
	end
	local saves = if opts.Saves ~= nil then opts.Saves elseif kind == "Lobby" then 0 else Config.Objectives.SavesPerMap
	if type(info.SavePoints) ~= "table" or #info.SavePoints ~= saves then
		bad(("SavePoints: need exactly %d"):format(saves))
	end
	if type(info.IntroPath) ~= "table" or #info.IntroPath < 3 then
		bad("IntroPath needs >= 3 CFrames")
	end
	if typeof(info.Center) ~= "Vector3" then
		bad("Center is not a Vector3")
	end
	if type(info.Radius) ~= "number" or info.Radius < 20 or info.Radius > 400 then
		bad("Radius out of range (20..400)")
	end
	local probe = MapKit.Ground(model)
	local lowest = INF
	local function onGround(label: string, p: Vector3)
		local y = probe(p, 2.5, 6)
		if y == nil then
			bad(label .. " has no solid ground below " .. tostring(p))
		elseif math.abs((y :: number) - p.Y) > 0.75 then
			bad(("%s is %.2f studs off the ground"):format(label, p.Y - (y :: number)))
		end
		lowest = math.min(lowest, p.Y)
	end
	if type(info.HumanSpawns) == "table" then
		for i, cf in info.HumanSpawns do
			if isCFrame(cf) then
				onGround("HumanSpawns[" .. i .. "]", cf.Position)
			else
				bad("HumanSpawns[" .. i .. "] is not a CFrame")
			end
		end
	end
	if isCFrame(info.MonsterSpawn) then
		onGround("MonsterSpawn", info.MonsterSpawn.Position)
	end
	if type(info.SavePoints) == "table" then
		for i, p in info.SavePoints do
			if typeof(p) == "Vector3" then
				onGround("SavePoints[" .. i .. "]", p)
			else
				bad("SavePoints[" .. i .. "] is not a Vector3")
			end
		end
	end
	if type(info.DummySpawns) == "table" then
		for i, cf in info.DummySpawns do
			onGround("DummySpawns[" .. i .. "]", cf.Position)
		end
	end
	if type(info.KillY) ~= "number" or info.KillY > lowest - 8 then
		bad("KillY must be at least 8 studs below every spawn")
	end
	if type(info.IntroPath) == "table" then
		for i, cf in info.IntroPath do
			if not isCFrame(cf) then
				bad("IntroPath[" .. i .. "] is not a CFrame")
			end
		end
	end
	local stats = MapKit.Stats(model)
	local partBudget = opts.PartBudget or MapKit.PART_BUDGET
	local lightBudget = opts.LightBudget or MapKit.LIGHT_BUDGET
	if stats.Parts > partBudget then
		bad(("part budget exceeded: %d > %d"):format(stats.Parts, partBudget))
	end
	if stats.Lights > lightBudget then
		bad(("light budget exceeded: %d > %d"):format(stats.Lights, lightBudget))
	end
	for _, folderName in { "Geometry", "Decor", "Lights", "Markers" } do
		if model:FindFirstChild(folderName) == nil then
			bad("missing folder " .. folderName)
		end
	end
	return #problems == 0, problems
end

-- Strings (lazy, optional: maps must build even if a strings file is broken) --------------------------
local stringsModule: any = nil
local function L(key: string, ...: any): string
	if stringsModule == nil then
		stringsModule = false
		local shared: any = script.Parent.Parent
		local module = shared:FindFirstChild("Strings")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				stringsModule = result
			end
		end
	end
	if stringsModule then
		local ok, text = pcall(stringsModule.L, key, ...)
		if ok and type(text) == "string" then
			return text
		end
	end
	return key
end
MapKit.L = L

-- Builder -----------------------------------------------------------------------------------------------

export type PartProps = {
	Collide: boolean?,
	Query: boolean?,
	Shadow: boolean?,
	Transparency: number?,
	Reflectance: number?,
	Category: string?,
	Parent: Instance?,
	Phase: number?,
	Tip: Vector3?,
}

local Builder = {}
Builder.__index = Builder

type BuilderData = {
	Model: Model,
	Rng: Rng.Rng,
	Folders: { [string]: Folder },
	PartCount: number,
	LightCount: number,
	PartBudget: number,
	LightBudget: number,
	_group: string?,
	_sub: { [string]: Folder },
	_kit: any,
}

export type Builder = typeof(setmetatable({} :: BuilderData, Builder))

function MapKit.new(name: string, options: { [string]: any }?): Builder
	local opts = options or {}
	local model = Instance.new("Model")
	model.Name = name
	local folders: { [string]: Folder } = {}
	for _, category in { "Geometry", "Decor", "Lights", "Markers" } do
		local f = Instance.new("Folder")
		f.Name = category
		f.Parent = model
		folders[category] = f
	end
	local self: BuilderData = {
		Model = model,
		Rng = Rng.new(opts.Seed or 0),
		Folders = folders,
		PartCount = 0,
		LightCount = 0,
		PartBudget = opts.PartBudget or MapKit.PART_BUDGET,
		LightBudget = opts.LightBudget or MapKit.LIGHT_BUDGET,
		_group = nil,
		_sub = {},
		_kit = nil,
	}
	local b = setmetatable(self, Builder)
	self._kit = PartKit.new({
		Anchored = true,
		Sink = function(_part: BasePart)
			self.PartCount += 1
		end,
	})
	return b
end

function Builder.Group(self: Builder, name: string?): string?
	local previous = self._group
	self._group = name
	return previous
end

function Builder._folder(self: Builder, category: string): Instance
	local root = self.Folders[category] or self.Folders.Decor
	local group = self._group
	if group == nil then
		return root
	end
	local key = category .. "/" .. group
	local f = self._sub[key]
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = group
		nf.Parent = root
		self._sub[key] = nf
		f = nf
	end
	return f :: Folder
end

-- Core part factory.
function Builder.Part(
	self: Builder,
	category: string,
	shape: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): BasePart
	local p: PartProps = props or {}
	local solid = category == "Geometry"
	local collide = if p.Collide ~= nil then p.Collide else solid
	local query = if p.Query ~= nil then p.Query else (solid or collide)
	local largest = math.max(size.X, size.Y, size.Z)
	local shadow = if p.Shadow ~= nil then p.Shadow else (solid or largest >= 2)
	local parent = p.Parent or self:_folder(category)
	local kitProps = {
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = collide,
		CanQuery = query,
		CanTouch = false,
		CastShadow = shadow,
		Transparency = p.Transparency,
		Reflectance = p.Reflectance,
		Massless = false,
	}
	if shape == "Ellipsoid" then
		return self._kit.Ellipsoid(parent, name, size, cf, color, kitProps)
	end
	return self._kit.Part(parent, name, shape, size, cf, color, kitProps)
end

function Builder.Solid(
	self: Builder,
	shape: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): BasePart
	return self:Part((props and props.Category) or "Geometry", shape, name, size, cf, color, material, props)
end

function Builder.Deco(
	self: Builder,
	shape: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): BasePart
	return self:Part((props and props.Category) or "Decor", shape, name, size, cf, color, material, props)
end

-- Upright cylinder (axis = world Y) centred at `center`.
function Builder.Disc(
	self: Builder,
	category: string,
	name: string,
	center: Vector3,
	diameter: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): BasePart
	return self:Part(
		category,
		"Cylinder",
		name,
		Vector3.new(thickness, diameter, diameter),
		CFrame.new(center) * UPRIGHT,
		color,
		material,
		props
	)
end

-- Cylinder between two points (axis = a -> b).
function Builder.Rod(
	self: Builder,
	category: string,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): BasePart
	local delta = b - a
	local cf = PartKit.Basis((a + b) / 2, delta, UP)
	return self:Part(category, "Cylinder", name, Vector3.new(delta.Magnitude, diameter, diameter), cf, color, material, props)
end

-- Box spanning a -> b (centre line), with the given cross-section (width along the horizontal normal,
-- height along up).
function Builder.Beam(
	self: Builder,
	category: string,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): BasePart
	local delta = b - a
	local cf = PartKit.Basis((a + b) / 2, delta, UP)
	return self:Part(category, "Block", name, Vector3.new(delta.Magnitude, height, width), cf, color, material, props)
end

-- Triangle (a, b, c) as two WedgeParts (the classic two-wedge technique), `thickness` centred on the plane.
function Builder.Triangle(
	self: Builder,
	category: string,
	name: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): { BasePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-9 or bc.Magnitude < 1e-9 then
		return {}
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local out: { BasePart } = {}
	local d1 = math.abs(ab:Dot(back))
	local d2 = math.abs(ac:Dot(back))
	if d1 > 1e-4 and height > 1e-4 then
		table.insert(
			out,
			self:Part(
				category,
				"Wedge",
				name,
				Vector3.new(thickness, height, d1),
				CFrame.fromMatrix((a + b) / 2, right, up, back),
				color,
				material,
				props
			)
		)
	end
	if d2 > 1e-4 and height > 1e-4 then
		table.insert(
			out,
			self:Part(
				category,
				"Wedge",
				name .. "_b",
				Vector3.new(thickness, height, d2),
				CFrame.fromMatrix((a + c) / 2, -right, up, -back),
				color,
				material,
				props
			)
		)
	end
	return out
end

-- n-sided pyramid ("cone") standing on `base` (centre of the base polygon).
function Builder.Cone(
	self: Builder,
	category: string,
	name: string,
	base: Vector3,
	height: number,
	radius: number,
	sides: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): { BasePart }
	local p = props or {}
	local phase = math.rad(p.Phase or 0)
	local apex = base + Vector3.new(0, height, 0) + (p.Tip or Vector3.new())
	local out: { BasePart } = {}
	local n = math.max(3, math.floor(sides))
	local thickness = math.clamp(radius * 0.06, 0.08, 0.4)
	for i = 0, n - 1 do
		local a0 = phase + i * 2 * math.pi / n
		local a1 = phase + (i + 1) * 2 * math.pi / n
		local p0 = base + Vector3.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)
		local p1 = base + Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius)
		-- push the shell inwards by half its thickness so the outer surface is the true cone
		local mid = (p0 + p1) / 2
		local outward = (mid - base)
		outward = Vector3.new(outward.X, 0, outward.Z)
		local inset = if outward.Magnitude > 1e-6 then outward.Unit * (-thickness * 0.5) else Vector3.new()
		for _, part in self:Triangle(category, name .. "_" .. i, apex + inset * 0.2, p0 + inset, p1 + inset, thickness, color, material, props) do
			table.insert(out, part)
		end
	end
	return out
end

-- Faceted five-point star in cf's local XY plane.
function Builder.Star(
	self: Builder,
	category: string,
	name: string,
	cf: CFrame,
	outerR: number,
	innerR: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): { BasePart }
	local out: { BasePart } = {}
	local verts: { Vector3 } = {}
	for k = 0, 9 do
		local angle = math.rad(90 + k * 36)
		local r = if k % 2 == 0 then outerR else innerR
		table.insert(verts, cf * Vector3.new(math.cos(angle) * r, math.sin(angle) * r, 0))
	end
	local function add(list: { BasePart })
		for _, part in list do
			table.insert(out, part)
		end
	end
	if depth > 0 then
		local front = cf * Vector3.new(0, 0, -depth)
		local back = cf * Vector3.new(0, 0, depth)
		local t = math.max(0.06, outerR * 0.03)
		for k = 1, 10 do
			local v0, v1 = verts[k], verts[k % 10 + 1]
			add(self:Triangle(category, name .. "_F" .. k, front, v0, v1, t, color, material, props))
			add(self:Triangle(category, name .. "_B" .. k, back, v0, v1, t, color, material, props))
		end
	else
		local center = cf.Position
		local t = math.max(0.04, outerR * 0.02)
		for k = 1, 10 do
			add(self:Triangle(category, name .. "_" .. k, center, verts[k], verts[k % 10 + 1], t, color, material, props))
		end
	end
	return out
end

-- Heart (point down) in cf's local XY plane; `size` = side of the central square.
function Builder.Heart(
	self: Builder,
	category: string,
	name: string,
	cf: CFrame,
	size: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): { BasePart }
	local s = size
	local h = s / math.sqrt(2)
	local lift = s * 0.07 -- centre the silhouette vertically
	local out: { BasePart } = {}
	table.insert(
		out,
		self:Part(
			category,
			"Block",
			name .. "_Body",
			Vector3.new(s, s, thickness),
			cf * CFrame.new(0, lift, 0) * CFrame.Angles(0, 0, math.rad(45)),
			color,
			material,
			props
		)
	)
	for _, side in { -1, 1 } do
		table.insert(
			out,
			self:Part(
				category,
				"Cylinder",
				name .. (if side < 0 then "_LobeL" else "_LobeR"),
				Vector3.new(thickness, s, s),
				cf * CFrame.new(side * h / 2, lift + h / 2, 0) * CFrame.Angles(0, HALF_PI, 0),
				color,
				material,
				props
			)
		)
	end
	return out
end

-- Floors ------------------------------------------------------------------------------------------------

function Builder.Floor(self: Builder, name: string, top: Vector3, sizeX: number, sizeZ: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local thickness = o.Thickness or 2
	local color = o.Color or rgb(200, 190, 170)
	local material = o.Material or Enum.Material.SmoothPlastic
	local collide = if o.Collide == nil then true else o.Collide
	local base = self:Part(
		if collide then "Geometry" else "Decor",
		"Block",
		name,
		Vector3.new(sizeX, thickness, sizeZ),
		CFrame.new(top - Vector3.new(0, thickness / 2, 0)),
		color,
		material,
		{ Collide = collide, Query = true, Shadow = false }
	)
	local pattern = o.Pattern
	local tile = o.Tile or 6
	local inset = 0
	if o.Border then
		local bw = o.Border.Width or tile * 0.5
		inset = bw
		local bc = o.Border.Color or GOLD
		local bm = o.Border.Material or Enum.Material.Metal
		local y = top.Y + 0.025
		local strips = {
			{ Vector3.new(sizeX, 0.05, bw), Vector3.new(0, 0, -(sizeZ - bw) / 2) },
			{ Vector3.new(sizeX, 0.05, bw), Vector3.new(0, 0, (sizeZ - bw) / 2) },
			{ Vector3.new(bw, 0.05, sizeZ - 2 * bw), Vector3.new(-(sizeX - bw) / 2, 0, 0) },
			{ Vector3.new(bw, 0.05, sizeZ - 2 * bw), Vector3.new((sizeX - bw) / 2, 0, 0) },
		}
		for i, s in strips do
			self:Deco(
				"Block",
				name .. "_Border" .. i,
				s[1],
				CFrame.new(Vector3.new(top.X, y, top.Z) + s[2]),
				bc,
				bm,
				{ Shadow = false }
			)
		end
	end
	local innerX, innerZ = sizeX - 2 * inset, sizeZ - 2 * inset
	local nx = math.max(1, math.floor(innerX / tile + 0.5))
	local nz = math.max(1, math.floor(innerZ / tile + 0.5))
	local tx, tz = innerX / nx, innerZ / nz
	local x0, z0 = top.X - innerX / 2, top.Z - innerZ / 2
	if pattern == "Checker" then
		local c2 = o.Color2 or PartKit.Shade(color, -0.35)
		local m2 = o.Material2 or material
		local gap = o.Gap or 0
		for ix = 0, nx - 1 do
			for iz = 0, nz - 1 do
				if (ix + iz) % 2 == 1 then
					self:Deco(
						"Block",
						name .. "_Tile",
						Vector3.new(tx - gap, 0.06, tz - gap),
						CFrame.new(x0 + (ix + 0.5) * tx, top.Y + 0.03, z0 + (iz + 0.5) * tz),
						c2,
						m2,
						{ Shadow = false }
					)
				end
			end
		end
	elseif pattern == "Tiles" then
		local grout = o.Grout or PartKit.Shade(color, -0.3)
		local w = o.GroutWidth or 0.18
		for ix = 1, nx - 1 do
			self:Deco(
				"Block",
				name .. "_GroutX",
				Vector3.new(w, 0.04, innerZ),
				CFrame.new(x0 + ix * tx, top.Y + 0.02, top.Z),
				grout,
				Enum.Material.SmoothPlastic,
				{ Shadow = false }
			)
		end
		for iz = 1, nz - 1 do
			self:Deco(
				"Block",
				name .. "_GroutZ",
				Vector3.new(innerX, 0.04, w),
				CFrame.new(top.X, top.Y + 0.02, z0 + iz * tz),
				grout,
				Enum.Material.SmoothPlastic,
				{ Shadow = false }
			)
		end
	elseif pattern == "Planks" then
		-- planks run along X; alternate tones
		local c2 = o.Color2 or PartKit.Shade(color, -0.12)
		for iz = 0, nz - 1 do
			if iz % 2 == 1 then
				self:Deco(
					"Block",
					name .. "_Plank",
					Vector3.new(innerX, 0.05, tz - 0.12),
					CFrame.new(top.X, top.Y + 0.025, z0 + (iz + 0.5) * tz),
					c2,
					o.Material2 or material,
					{ Shadow = false }
				)
			end
		end
	end
	return base
end

-- Walls -------------------------------------------------------------------------------------------------

type Opening = { X: number, Width: number, Bottom: number, Top: number }

-- Wall pieces around openings in wall-local coordinates (x along the wall, y up from the base).
local function wallPieces(length: number, height: number, openings: { Opening }): { { number } }
	-- returns {x0, x1, y0, y1}
	local pieces: { { number } } = {}
	local sorted = table.clone(openings)
	table.sort(sorted, function(a, b)
		return a.X < b.X
	end)
	local cursor = -length / 2
	for _, op in sorted do
		local ox0 = math.max(-length / 2, op.X - op.Width / 2)
		local ox1 = math.min(length / 2, op.X + op.Width / 2)
		if ox0 > cursor + 1e-4 then
			table.insert(pieces, { cursor, ox0, 0, height })
		end
		if op.Bottom > 1e-4 then
			table.insert(pieces, { ox0, ox1, 0, op.Bottom })
		end
		if op.Top < height - 1e-4 then
			table.insert(pieces, { ox0, ox1, op.Top, height })
		end
		cursor = math.max(cursor, ox1)
	end
	if cursor < length / 2 - 1e-4 then
		table.insert(pieces, { cursor, length / 2, 0, height })
	end
	return pieces
end

-- Horizontal trim strip with gaps where openings cross its height band.
local function trimSegments(length: number, y0: number, y1: number, openings: { Opening }): { { number } }
	local segs: { { number } } = { { -length / 2, length / 2 } }
	for _, op in openings do
		if op.Bottom < y1 and op.Top > y0 then
			local cut0, cut1 = op.X - op.Width / 2, op.X + op.Width / 2
			local nextSegs: { { number } } = {}
			for _, s in segs do
				if cut1 <= s[1] or cut0 >= s[2] then
					table.insert(nextSegs, s)
				else
					if cut0 > s[1] then
						table.insert(nextSegs, { s[1], cut0 })
					end
					if cut1 < s[2] then
						table.insert(nextSegs, { cut1, s[2] })
					end
				end
			end
			segs = nextSegs
		end
	end
	return segs
end

function Builder.Wall(self: Builder, name: string, cf: CFrame, length: number, height: number, opts: { [string]: any }?): { BasePart }
	local o = opts or {}
	local t = o.Thickness or 2
	local color = o.Color or rgb(210, 200, 180)
	local material = o.Material or Enum.Material.Plaster
	local openings: { Opening } = o.Openings or {}
	local out: { BasePart } = {}
	for i, pc in wallPieces(length, height, openings) do
		local w, h = pc[2] - pc[1], pc[4] - pc[3]
		if w > 0.01 and h > 0.01 then
			table.insert(
				out,
				self:Solid(
					"Block",
					name .. "_" .. i,
					Vector3.new(w, h, t),
					cf * CFrame.new((pc[1] + pc[2]) / 2, (pc[3] + pc[4]) / 2, 0),
					color,
					material
				)
			)
		end
	end
	local sides = if o.BothSides then { -1, 1 } else { -1 }
	local function trim(label: string, spec: { [string]: any }, y0: number, y1: number, proud: number)
		for _, side in sides do
			for k, seg in trimSegments(length, y0, y1, openings) do
				local w = seg[2] - seg[1]
				if w > 0.05 then
					self:Deco(
						"Block",
						name .. "_" .. label .. k,
						Vector3.new(w, y1 - y0, proud),
						cf * CFrame.new((seg[1] + seg[2]) / 2, (y0 + y1) / 2, side * (t / 2 + proud / 2 - 0.01)),
						spec.Color or PartKit.Shade(color, -0.25),
						spec.Material or material,
						{ Shadow = false }
					)
				end
			end
		end
	end
	if o.Baseboard then
		local bh = o.Baseboard.Height or 1.2
		trim("Base", o.Baseboard, 0, bh, o.Baseboard.Depth or 0.35)
	end
	if o.Rail then
		local ry = o.Rail.Y or 4
		local rh = o.Rail.Height or 0.4
		trim("Rail", o.Rail, ry, ry + rh, o.Rail.Depth or 0.25)
	end
	if o.Cornice then
		local ch = o.Cornice.Height or 1.4
		trim("Cornice", o.Cornice, height - ch, height, o.Cornice.Depth or 0.7)
	end
	return out
end

-- Columns -----------------------------------------------------------------------------------------------

function Builder.Column(self: Builder, name: string, base: Vector3, height: number, diameter: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local style = o.Style or "Classic"
	local color = o.Color or rgb(226, 214, 190)
	local accent = o.Accent or GOLD
	local dark = o.Dark or PartKit.Shade(color, -0.3)
	local material = o.Material or Enum.Material.Marble
	local accentMat = o.AccentMaterial or Enum.Material.Metal
	local collide = if o.Collide == nil then true else o.Collide
	local d = diameter
	local cat = if collide then "Geometry" else "Decor"
	local plinthH = d * 0.32
	local capH = d * 0.55
	if style == "Square" then
		self:Part(cat, "Block", name .. "_Plinth", Vector3.new(d * 1.3, plinthH, d * 1.3), CFrame.new(base + Vector3.new(0, plinthH / 2, 0)), dark, material)
		local shaftH = height - plinthH - capH
		local shaft = self:Part(
			cat,
			"Block",
			name,
			Vector3.new(d, shaftH, d),
			CFrame.new(base + Vector3.new(0, plinthH + shaftH / 2, 0)),
			color,
			material
		)
		self:Deco("Block", name .. "_Cap", Vector3.new(d * 1.3, capH, d * 1.3), CFrame.new(base + Vector3.new(0, height - capH / 2, 0)), dark, material)
		return shaft
	end
	-- plinth + torus base
	self:Part(cat, "Block", name .. "_Plinth", Vector3.new(d * 1.4, plinthH, d * 1.4), CFrame.new(base + Vector3.new(0, plinthH / 2, 0)), dark, material)
	local torusH = d * 0.14
	self:Disc("Decor", name .. "_Torus", base + Vector3.new(0, plinthH + torusH / 2, 0), d * 1.2, torusH, accent, accentMat, { Shadow = false })
	self:Disc("Decor", name .. "_Torus2", base + Vector3.new(0, plinthH + torusH * 1.5, 0), d * 1.1, torusH, color, material, { Shadow = false })
	local shaftBottom = plinthH + torusH * 2
	local shaftH = height - shaftBottom - capH
	local shaft = self:Disc(cat, name, base + Vector3.new(0, shaftBottom + shaftH / 2, 0), d, shaftH, color, material)
	if style == "Classic" then
		local flutes = o.Flutes or 8
		for k = 0, flutes - 1 do
			local a = (k + 0.5) * 2 * math.pi / flutes
			local r = d / 2 - 0.02
			self:Deco(
				"Block",
				name .. "_Flute",
				Vector3.new(d * 0.07, shaftH * 0.9, d * 0.07),
				CFrame.new(base + Vector3.new(math.cos(a) * r, shaftBottom + shaftH / 2, math.sin(a) * r)) * CFrame.Angles(0, -a, 0),
				dark,
				material,
				{ Shadow = false }
			)
		end
	end
	-- neck ring, echinus, abacus
	local neckY = shaftBottom + shaftH
	self:Disc("Decor", name .. "_Neck", base + Vector3.new(0, neckY + 0.1, 0), d * 1.08, d * 0.1, accent, accentMat, { Shadow = false })
	self:Disc("Decor", name .. "_Echinus", base + Vector3.new(0, neckY + capH * 0.38, 0), d * 1.28, capH * 0.5, color, material)
	self:Part(
		cat,
		"Block",
		name .. "_Abacus",
		Vector3.new(d * 1.5, capH * 0.42, d * 1.5),
		CFrame.new(base + Vector3.new(0, height - capH * 0.21, 0)),
		color,
		material
	)
	self:Deco("Block", name .. "_AbacusBand", Vector3.new(d * 1.52, capH * 0.1, d * 1.52), CFrame.new(base + Vector3.new(0, height - capH * 0.38, 0)), accent, accentMat, { Shadow = false })
	return shaft
end

-- Rings and arcs of box segments -----------------------------------------------------------------------------

-- Box segments along a circle in cf's local XY plane (0 deg = +X, 90 deg = +Y); `thickness` is radial,
-- `depth` runs along cf.ZVector. A horizontal ring: cf = CFrame.new(center) * CFrame.Angles(math.pi / 2, 0, 0).
function Builder.ArcRing(
	self: Builder,
	category: string,
	name: string,
	cf: CFrame,
	radius: number,
	fromDeg: number,
	toDeg: number,
	segments: number,
	thickness: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): { BasePart }
	local parts: { BasePart } = {}
	local n = math.max(1, math.floor(segments))
	local span = math.rad(toDeg - fromDeg) / n
	for i = 0, n - 1 do
		local am = math.rad(fromDeg) + (i + 0.5) * span
		local chord = 2 * radius * math.sin(math.abs(span) / 2) + thickness * 0.35
		local pos = cf * Vector3.new(math.cos(am) * radius, math.sin(am) * radius, 0)
		local tangent = cf:VectorToWorldSpace(Vector3.new(-math.sin(am), math.cos(am), 0))
		local radial = cf:VectorToWorldSpace(Vector3.new(math.cos(am), math.sin(am), 0))
		local segCF = CFrame.fromMatrix(pos, tangent, radial, cf.ZVector)
		table.insert(parts, self:Part(category, "Block", name .. "_" .. i, Vector3.new(chord, thickness, depth), segCF, color, material, props))
	end
	return parts
end

-- Horizontal ring (e.g. a fountain rim or a plaza inlay) centred at `center` (mid-height of the ring).
function Builder.Ring(
	self: Builder,
	category: string,
	name: string,
	center: Vector3,
	radius: number,
	thickness: number,
	height: number,
	segments: number,
	color: Color3,
	material: Enum.Material?,
	props: PartProps?
): { BasePart }
	return self:ArcRing(category, name, CFrame.new(center) * CFrame.Angles(math.pi / 2, 0, 0), radius, 0, 360, segments, thickness, height, color, material, props)
end

-- Arches ------------------------------------------------------------------------------------------------

function Builder.Arch(
	self: Builder,
	name: string,
	cf: CFrame,
	span: number,
	thickness: number,
	depth: number,
	color: Color3,
	opts: { [string]: any }?
): { BasePart }
	local o = opts or {}
	local material = o.Material or Enum.Material.Marble
	local segments = o.Segments or 9
	local radius = span / 2 + thickness / 2
	local parts: { BasePart } = {}
	local step = 180 / segments
	for i = 0, segments - 1 do
		local a0 = math.rad(i * step)
		local a1 = math.rad((i + 1) * step)
		local am = (a0 + a1) / 2
		local chord = 2 * radius * math.sin((a1 - a0) / 2) + thickness * 0.35
		local pos = cf * Vector3.new(math.cos(am) * radius, math.sin(am) * radius, 0)
		local segCF = CFrame.fromMatrix(pos, cf:VectorToWorldSpace(Vector3.new(-math.sin(am), math.cos(am), 0)), cf:VectorToWorldSpace(Vector3.new(math.cos(am), math.sin(am), 0)), cf.ZVector)
		table.insert(parts, self:Deco("Block", name .. "_Seg" .. i, Vector3.new(chord, thickness, depth), segCF, color, material))
	end
	if o.Keystone ~= false then
		local key = o.KeystoneColor or GOLD
		table.insert(
			parts,
			self:Deco(
				"Block",
				name .. "_Key",
				Vector3.new(thickness * 0.7, thickness * 1.25, depth + 0.3),
				cf * CFrame.new(0, radius, 0),
				key,
				o.KeystoneMaterial or Enum.Material.Metal
			)
		)
	end
	return parts
end

-- Lights ------------------------------------------------------------------------------------------------

function Builder.Light(self: Builder, kind: string, at: any, props: { [string]: any }?): Light
	local p = props or {}
	local cf: CFrame = if typeof(at) == "CFrame" then at else CFrame.new(at :: Vector3)
	local size: Vector3 = p.Size or Vector3.new(0.4, 0.4, 0.4)
	local holder = self:Part("Lights", "Block", p.Name or (kind .. "Light"), size, cf, WHITE, Enum.Material.SmoothPlastic, {
		Collide = false,
		Query = false,
		Shadow = false,
		Transparency = 1,
	})
	local light: Light
	if kind == "Spot" then
		local s = Instance.new("SpotLight")
		s.Angle = p.Angle or 60
		s.Face = p.Face or Enum.NormalId.Front
		s.Range = math.min(p.Range or 16, MapKit.MAX_LIGHT_RANGE)
		light = s
	elseif kind == "Surface" then
		local s = Instance.new("SurfaceLight")
		s.Angle = p.Angle or 90
		s.Face = p.Face or Enum.NormalId.Front
		s.Range = math.min(p.Range or 16, MapKit.MAX_LIGHT_RANGE)
		light = s
	else
		local s = Instance.new("PointLight")
		s.Range = math.min(p.Range or 16, MapKit.MAX_LIGHT_RANGE)
		light = s
	end
	light.Brightness = p.Brightness or 1
	light.Color = p.Color or rgb(255, 214, 160)
	light.Shadows = p.Shadows == true
	light.Parent = holder
	self.LightCount += 1
	return light
end

-- A fake volumetric light shaft: a translucent glowing slab from an aperture along the light direction.
-- `from` = centre of the aperture, `dir` = direction the light travels; width/height = the slab's cross
-- section (perpendicular to dir), length along dir. Purely visual (no collision, queries or shadows).
function Builder.Shaft(
	self: Builder,
	name: string,
	from: Vector3,
	dir: Vector3,
	width: number,
	height: number,
	length: number,
	color: Color3,
	opts: { [string]: any }?
): BasePart
	local o = opts or {}
	local d = dir.Unit
	local frame = PartKit.LookFrame(from + d * (length / 2), d, UP)
	return self:Part("Decor", "Block", name, Vector3.new(width, height, length), frame, color, o.Material or Enum.Material.Neon, {
		Transparency = o.Transparency or 0.94,
		Shadow = false,
		Query = false,
		Collide = false,
	})
end

-- Particles (built-in textures only) -------------------------------------------------------------------

local TEX = {
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Sparkles = "rbxasset://textures/particles/sparkles_main.dds",
}

local function ns(points: { { number } }): NumberSequence
	local keys = {}
	for _, pt in points do
		table.insert(keys, NumberSequenceKeypoint.new(pt[1], pt[2]))
	end
	return NumberSequence.new(keys)
end

function Builder.Particles(self: Builder, part: BasePart, preset: string, props: { [string]: any }?): ParticleEmitter
	local p = props or {}
	local e = Instance.new("ParticleEmitter")
	e.Name = preset .. "Emitter"
	if preset == "Smoke" then
		e.Texture = TEX.Smoke
		e.Color = ColorSequence.new(p.Color or rgb(190, 196, 210))
		e.Size = ns({ { 0, 1.2 }, { 1, 4.5 } })
		e.Transparency = ns({ { 0, 1 }, { 0.15, 0.55 }, { 1, 1 } })
		e.Lifetime = NumberRange.new(4, 6)
		e.Rate = p.Rate or 3
		e.Speed = NumberRange.new(2, 3.5)
		e.SpreadAngle = Vector2.new(8, 8)
		e.Acceleration = Vector3.new(0.6, 0.4, 0.2)
		e.RotSpeed = NumberRange.new(-20, 20)
		e.Rotation = NumberRange.new(0, 360)
		e.LightInfluence = 0.6
		e.Drag = 0.4
		e.WindAffectsDrag = true
	elseif preset == "Embers" then
		e.Texture = TEX.Glow
		e.Color = ColorSequence.new(p.Color or rgb(255, 170, 70))
		e.Size = ns({ { 0, 0.35 }, { 1, 0 } })
		e.Transparency = ns({ { 0, 0.2 }, { 1, 1 } })
		e.Lifetime = NumberRange.new(1.2, 2.2)
		e.Rate = p.Rate or 6
		e.Speed = NumberRange.new(2, 4)
		e.SpreadAngle = Vector2.new(20, 20)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Brightness = 2
	elseif preset == "Motes" then
		e.Texture = TEX.Glow
		e.Color = ColorSequence.new(p.Color or rgb(255, 230, 160))
		e.Size = ns({ { 0, 0 }, { 0.3, p.Size or 0.4 }, { 1, 0 } })
		e.Transparency = ns({ { 0, 0.3 }, { 1, 1 } })
		e.Lifetime = NumberRange.new(3, 5)
		e.Rate = p.Rate or 4
		e.Speed = NumberRange.new(0.4, 1.2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Brightness = 1.5
	else -- Sparkles
		e.Texture = TEX.Sparkles
		e.Color = ColorSequence.new(p.Color or rgb(255, 236, 170))
		e.Size = ns({ { 0, 0 }, { 0.5, p.Size or 0.6 }, { 1, 0 } })
		e.Transparency = ns({ { 0, 0.2 }, { 1, 1 } })
		e.Lifetime = NumberRange.new(1, 1.8)
		e.Rate = p.Rate or 5
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Brightness = 2
	end
	e.Parent = part
	return e
end

-- Windows -----------------------------------------------------------------------------------------------

function Builder.Window(self: Builder, name: string, cf: CFrame, width: number, height: number, opts: { [string]: any }?): { Light }
	local o = opts or {}
	local frameColor = o.Frame or rgb(120, 86, 44)
	local lead = o.Lead or rgb(60, 46, 32)
	local clear = o.Clear or rgb(255, 226, 170)
	local palette: { Color3 } = o.Palette or { rgb(255, 176, 64), rgb(214, 70, 60), rgb(80, 120, 220), rgb(240, 210, 120) }
	local depth = o.Depth or 1.2
	local wallT = o.Wall or depth -- wall thickness: the arched head and the light sit on its interior face
	local cols = o.Cols or 3
	local rows = o.Rows or 6
	local frameMat = o.FrameMaterial or Enum.Material.Metal
	local fw = math.max(0.35, width * 0.06)
	local lights: { Light } = {}
	-- frame (jambs, sill, head) fills the reveal; zIn = the wall's interior face
	local zIn = -wallT / 2
	self:Deco("Block", name .. "_JambL", Vector3.new(fw, height, depth), cf * CFrame.new(-width / 2 + fw / 2, 0, 0), frameColor, frameMat)
	self:Deco("Block", name .. "_JambR", Vector3.new(fw, height, depth), cf * CFrame.new(width / 2 - fw / 2, 0, 0), frameColor, frameMat)
	self:Deco("Block", name .. "_Sill", Vector3.new(width + 1.2, 0.6, depth + 1.4), cf * CFrame.new(0, -height / 2 + 0.3, zIn - 0.2), frameColor, frameMat)
	self:Deco("Block", name .. "_Head", Vector3.new(width, fw, depth), cf * CFrame.new(0, height / 2 - fw / 2, 0), frameColor, frameMat)
	-- glass: one big clear pane (lets the sun through) + coloured border panes (glowing accents)
	local paneW, paneH = width - 2 * fw, height - fw - 0.6
	local paneCF = cf * CFrame.new(0, (-height / 2 + 0.6 + height / 2 - fw) / 2, 0)
	self:Deco("Block", name .. "_Glass", Vector3.new(paneW, paneH, 0.12), paneCF, clear, Enum.Material.Glass, {
		Transparency = o.ClearTransparency or 0.72,
		Shadow = false,
	})
	-- lead grid
	for c = 1, cols - 1 do
		local x = -paneW / 2 + c * paneW / cols
		self:Deco("Block", name .. "_Mullion" .. c, Vector3.new(0.22, paneH, 0.3), paneCF * CFrame.new(x, 0, 0), lead, Enum.Material.Metal)
	end
	for r = 1, rows - 1 do
		local y = -paneH / 2 + r * paneH / rows
		self:Deco("Block", name .. "_Transom" .. r, Vector3.new(paneW, 0.2, 0.3), paneCF * CFrame.new(0, y, 0), lead, Enum.Material.Metal)
	end
	-- coloured accent panes on the top row and in a diagonal chain (deterministic by name)
	local rng = Rng.new(Rng.Hash(name))
	local cellW, cellH = paneW / cols, paneH / rows
	for c = 0, cols - 1 do
		local color = palette[(c % #palette) + 1]
		self:Deco(
			"Block",
			name .. "_Accent",
			Vector3.new(cellW - 0.24, cellH - 0.24, 0.14),
			paneCF * CFrame.new(-paneW / 2 + (c + 0.5) * cellW, paneH / 2 - cellH / 2, -0.04),
			color,
			Enum.Material.Neon,
			{ Transparency = 0.45, Shadow = false }
		)
	end
	for r = 1, rows - 2 do
		if rng:Bool(0.5) then
			local c = rng:Integer(0, cols - 1)
			self:Deco(
				"Block",
				name .. "_Accent",
				Vector3.new(cellW - 0.24, cellH - 0.24, 0.14),
				paneCF * CFrame.new(-paneW / 2 + (c + 0.5) * cellW, -paneH / 2 + (r + 0.5) * cellH, -0.04),
				palette[rng:Integer(1, #palette)],
				Enum.Material.Neon,
				{ Transparency = 0.55, Shadow = false }
			)
		end
	end
	-- arched head: a fan of coloured triangles over the opening (on the interior face)
	if o.Arch ~= false then
		local r = width / 2
		local center = cf * Vector3.new(0, height / 2, zIn - 0.08)
		local fan = o.FanSegments or 6
		local inner = r * 0.32
		for k = 0, fan - 1 do
			local a0 = math.rad(k * 180 / fan)
			local a1 = math.rad((k + 1) * 180 / fan)
			local p0 = center + cf:VectorToWorldSpace(Vector3.new(math.cos(a0) * r, math.sin(a0) * r, 0))
			local p1 = center + cf:VectorToWorldSpace(Vector3.new(math.cos(a1) * r, math.sin(a1) * r, 0))
			local color = palette[(k % #palette) + 1]
			self:Triangle("Decor", name .. "_Fan" .. k, center, p0, p1, 0.12, color, Enum.Material.Neon, {
				Transparency = 0.3,
				Shadow = false,
			})
			self:Rod("Decor", name .. "_Rib" .. k, center, p0, 0.22, lead, Enum.Material.Metal, { Shadow = false })
		end
		-- sunburst hub at the springline (cylinder axis turned to face the room)
		self:Part(
			"Decor",
			"Cylinder",
			name .. "_Rose",
			Vector3.new(0.1, inner * 2, inner * 2),
			cf * CFrame.new(0, height / 2, zIn - 0.16) * CFrame.Angles(0, HALF_PI, 0),
			o.Rose or rgb(255, 236, 190),
			Enum.Material.Neon,
			{ Shadow = false, Transparency = 0.1 }
		)
		self:Arch(name .. "_ArchFrame", cf * CFrame.new(0, height / 2, zIn - 0.1), width, 0.55, 0.5, frameColor, {
			Material = frameMat,
			Segments = 8,
			Keystone = o.Keystone,
		})
	end
	-- warm fill light shaped like the window
	if o.Light ~= false then
		local lp = o.Light or {}
		table.insert(
			lights,
			self:Light("Surface", cf * CFrame.new(0, 0, zIn - 0.4), {
				Name = name .. "_Light",
				Size = Vector3.new(paneW, paneH, 0.2),
				Face = Enum.NormalId.Front,
				Brightness = lp.Brightness or 1.2,
				Range = lp.Range or 28,
				Angle = lp.Angle or 75,
				Color = lp.Color or rgb(255, 196, 120),
			})
		)
	end
	return lights
end

-- Stairs, railings ---------------------------------------------------------------------------------------

function Builder.Stairs(self: Builder, name: string, cf: CFrame, width: number, rise: number, run: number, opts: { [string]: any }?): { BasePart }
	local o = opts or {}
	local color = o.Color or rgb(214, 200, 172)
	local nose = o.Nose or PartKit.Shade(color, -0.15)
	local material = o.Material or Enum.Material.Marble
	local steps = o.Steps or math.max(1, math.ceil(rise / 0.75))
	local h = rise / steps
	local d = run / steps
	local out: { BasePart } = {}
	for i = 0, steps - 1 do
		local top = (i + 1) * h
		-- each step block reaches down to the ground (no gaps from any angle)
		local zc = -(i * d + (run - i * d) / 2)
		table.insert(
			out,
			self:Deco("Block", name .. "_Step" .. (i + 1), Vector3.new(width, h, run - i * d), cf * CFrame.new(0, top - h / 2, zc), color, material, {
				Query = true,
				Shadow = true,
			})
		)
		self:Deco("Block", name .. "_Nose" .. (i + 1), Vector3.new(width, 0.12, 0.22), cf * CFrame.new(0, top - 0.06, -(i * d) - 0.09), nose, o.NoseMaterial or Enum.Material.Metal, { Shadow = false })
	end
	-- invisible ramp (collision): slope rising along the look direction
	local ramp = self:Solid("Wedge", name .. "_Ramp", Vector3.new(width, rise, run), cf * CFrame.new(0, rise / 2, -run / 2) * CFrame.Angles(0, math.pi, 0), color, material, {
		Transparency = 1,
		Shadow = false,
		Query = false,
	})
	table.insert(out, ramp)
	if o.Top ~= false then
		-- landing collider flush with the top step
		table.insert(out, self:Solid("Block", name .. "_Landing", Vector3.new(width, 0.2, 0.6), cf * CFrame.new(0, rise - 0.1, -run + 0.3), color, material, { Transparency = 1, Shadow = false, Query = false }))
	end
	return out
end

function Builder.Railing(self: Builder, name: string, a: Vector3, b: Vector3, opts: { [string]: any }?): { BasePart }
	local o = opts or {}
	local height = o.Height or 3.2
	local spacing = o.Spacing or 6
	local color = o.Color or GOLD
	local material = o.Material or Enum.Material.Metal
	local out: { BasePart } = {}
	local delta = b - a
	local length = delta.Magnitude
	local n = math.max(1, math.ceil(length / spacing))
	for i = 0, n do
		local p = a + delta * (i / n)
		table.insert(out, self:Deco("Block", name .. "_Post" .. i, Vector3.new(0.5, height, 0.5), CFrame.new(p + Vector3.new(0, height / 2, 0)), color, material))
		self:Deco("Ball", name .. "_Finial" .. i, Vector3.new(0.7, 0.7, 0.7), CFrame.new(p + Vector3.new(0, height + 0.25, 0)), color, material, { Shadow = false })
	end
	table.insert(out, self:Beam("Decor", name .. "_Rail", a + Vector3.new(0, height, 0), b + Vector3.new(0, height, 0), 0.4, 0.3, color, material))
	table.insert(out, self:Beam("Decor", name .. "_RailLow", a + Vector3.new(0, 0.5, 0), b + Vector3.new(0, 0.5, 0), 0.3, 0.25, color, material, { Shadow = false }))
	if o.Balusters ~= false then
		local count = math.max(1, math.floor(length / (o.BalusterGap or 1.2)))
		for i = 1, count - 1 do
			local p = a + delta * (i / count)
			self:Deco("Cylinder", name .. "_Baluster", Vector3.new(height - 0.6, 0.22, 0.22), CFrame.new(p + Vector3.new(0, height / 2 + 0.2, 0)) * UPRIGHT, color, material, { Shadow = false })
		end
	end
	if o.Collide ~= false then
		local frame = alongFrame((a + b) / 2 + Vector3.new(0, (height + 0.6) / 2, 0), delta)
		self:Solid("Block", name .. "_Collider", Vector3.new(length, height + 0.6, 0.6), frame, color, material, {
			Transparency = 1,
			Shadow = false,
			Query = false,
		})
	end
	return out
end

-- Banners ------------------------------------------------------------------------------------------------

function Builder.Banner(self: Builder, name: string, cf: CFrame, width: number, length: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local color = o.Color or rgb(150, 28, 40)
	local trim = o.Trim or GOLD
	local fabric = Enum.Material.Fabric
	local tail = math.min(width * 0.45, length * 0.25)
	local body = length - tail
	local cloth = self:Deco("Block", name, Vector3.new(width, body, 0.12), cf * CFrame.new(0, -body / 2, 0), color, fabric)
	-- V-cut tail: two triangles hanging below the body
	local left = cf * Vector3.new(-width / 2, -body, 0)
	local right = cf * Vector3.new(width / 2, -body, 0)
	local mid = cf * Vector3.new(0, -body, 0)
	local tipL = cf * Vector3.new(-width / 2, -length, 0)
	local tipR = cf * Vector3.new(width / 2, -length, 0)
	local notch = cf * Vector3.new(0, -body - tail * 0.25, 0)
	self:Triangle("Decor", name .. "_TailL", left, tipL, notch, 0.12, color, fabric)
	self:Triangle("Decor", name .. "_TailL2", left, mid, notch, 0.12, color, fabric)
	self:Triangle("Decor", name .. "_TailR", right, tipR, notch, 0.12, color, fabric)
	self:Triangle("Decor", name .. "_TailR2", right, mid, notch, 0.12, color, fabric)
	-- trim stripes + rod
	for _, side in { -1, 1 } do
		self:Deco("Block", name .. "_Trim", Vector3.new(width * 0.07, body, 0.16), cf * CFrame.new(side * width * 0.4, -body / 2, -0.02), trim, Enum.Material.Metal, { Shadow = false })
	end
	self:Deco("Block", name .. "_TrimTop", Vector3.new(width, width * 0.07, 0.16), cf * CFrame.new(0, -width * 0.12, -0.02), trim, Enum.Material.Metal, { Shadow = false })
	if o.Rod ~= false then
		self:Deco("Cylinder", name .. "_Rod", Vector3.new(width + 1.2, 0.35, 0.35), cf, o.RodColor or trim, Enum.Material.Metal, { Shadow = false })
		for _, side in { -1, 1 } do
			self:Deco("Ball", name .. "_RodEnd", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(side * (width / 2 + 0.6), 0, 0), o.RodColor or trim, Enum.Material.Metal, { Shadow = false })
		end
	end
	local emblem = o.Emblem
	local ec = o.EmblemColor or trim
	local ecf = cf * CFrame.new(0, -body * 0.48, -0.09)
	local s = width * 0.36
	if emblem == "Heart" then
		self:Heart("Decor", name .. "_Heart", ecf, s, 0.08, ec, o.EmblemMaterial or Enum.Material.Neon, { Shadow = false })
	elseif emblem == "Star" then
		self:Star("Decor", name .. "_Star", ecf, s * 0.95, s * 0.4, 0, ec, o.EmblemMaterial or Enum.Material.Metal, { Shadow = false })
	elseif emblem == "Delta" then
		-- winged triangle sigil (original take on the Delta motif)
		local top = ecf * Vector3.new(0, s * 0.75, 0)
		local bl = ecf * Vector3.new(-s * 0.6, -s * 0.35, 0)
		local br = ecf * Vector3.new(s * 0.6, -s * 0.35, 0)
		self:Triangle("Decor", name .. "_Delta", top, bl, br, 0.08, ec, o.EmblemMaterial or Enum.Material.Metal, { Shadow = false })
		for _, side in { -1, 1 } do
			local w0 = ecf * Vector3.new(side * s * 0.3, s * 0.2, -0.02)
			local w1 = ecf * Vector3.new(side * s * 1.05, s * 0.55, -0.02)
			local w2 = ecf * Vector3.new(side * s * 0.75, -s * 0.05, -0.02)
			self:Triangle("Decor", name .. "_Wing", w0, w1, w2, 0.06, ec, o.EmblemMaterial or Enum.Material.Metal, { Shadow = false })
		end
		self:Ball("Decor", name .. "_Eye", ecf * Vector3.new(0, s * 0.05, -0.08), s * 0.22, PartKit.Shade(color, -0.4))
	end
	return cloth
end

function Builder.Ball(self: Builder, category: string, name: string, pos: Vector3, diameter: number, color: Color3, material: Enum.Material?, props: PartProps?): BasePart
	return self:Part(category, "Ball", name, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, material, props)
end

-- Lamps --------------------------------------------------------------------------------------------------

function Builder.Lamp(self: Builder, name: string, base: Vector3, opts: { [string]: any }?): Light?
	local o = opts or {}
	local style = o.Style or "Post"
	local metal = o.Metal or rgb(40, 36, 34)
	local glow = o.Glow or rgb(255, 196, 110)
	local lightColor = o.LightColor or rgb(255, 176, 96)
	local brightness = o.Brightness or 1.6
	local range = o.Range or 20
	local metalMat = o.MetalMaterial or Enum.Material.Metal
	local function addLight(at: Vector3): Light?
		if o.NoLight then
			return nil
		end
		return self:Light("Point", at, { Name = name .. "_Light", Brightness = brightness, Range = range, Color = lightColor, Shadows = o.Shadows == true })
	end
	local function lantern(center: Vector3, s: number)
		-- housing: base plate, 4 corner posts, glowing core, glass, pyramid cap, finial
		self:Deco("Block", name .. "_LanternBase", Vector3.new(s * 1.1, s * 0.15, s * 1.1), CFrame.new(center - Vector3.new(0, s * 0.62, 0)), metal, metalMat)
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			self:Deco("Block", name .. "_LanternPost", Vector3.new(s * 0.1, s * 1.2, s * 0.1), CFrame.new(center + Vector3.new(c[1] * s * 0.45, 0, c[2] * s * 0.45)), metal, metalMat, { Shadow = false })
		end
		self:Deco("Block", name .. "_LanternGlass", Vector3.new(s * 0.86, s * 1.1, s * 0.86), CFrame.new(center), glow, Enum.Material.Glass, { Transparency = 0.45, Shadow = false })
		self:Deco("Ball", name .. "_Flame", Vector3.new(s * 0.5, s * 0.5, s * 0.5), CFrame.new(center), glow, Enum.Material.Neon, { Shadow = false })
		self:Cone("Decor", name .. "_LanternCap", center + Vector3.new(0, s * 0.6, 0), s * 0.55, s * 0.75, 4, metal, metalMat, { Phase = 45, Shadow = false })
		self:Deco("Ball", name .. "_Finial", Vector3.new(s * 0.25, s * 0.25, s * 0.25), CFrame.new(center + Vector3.new(0, s * 1.2, 0)), metal, metalMat, { Shadow = false })
	end
	if style == "Post" then
		local height = o.Height or 9
		self:Deco("Block", name .. "_Foot", Vector3.new(1.4, 0.6, 1.4), CFrame.new(base + Vector3.new(0, 0.3, 0)), metal, metalMat)
		self:Solid("Cylinder", name .. "_Pole", Vector3.new(height - 1.6, 0.42, 0.42), CFrame.new(base + Vector3.new(0, (height - 1.6) / 2 + 0.6, 0)) * UPRIGHT, metal, metalMat)
		self:Deco("Cylinder", name .. "_Collar", Vector3.new(0.3, 0.7, 0.7), CFrame.new(base + Vector3.new(0, 2.2, 0)) * UPRIGHT, metal, metalMat, { Shadow = false })
		local center = base + Vector3.new(0, height - 0.4, 0)
		lantern(center, 1.2)
		return addLight(center)
	elseif style == "Lantern" then
		-- hanging lantern: `base` is the hang point
		local drop = o.Drop or 3
		self:Rod("Decor", name .. "_Chain", base, base - Vector3.new(0, drop, 0), 0.12, metal, metalMat, { Shadow = false })
		local center = base - Vector3.new(0, drop + 0.8, 0)
		lantern(center, o.Size or 1)
		return addLight(center)
	elseif style == "Wall" then
		local facing: Vector3 = o.Facing or Vector3.new(0, 0, -1)
		local f = Vector3.new(facing.X, 0, facing.Z).Unit
		self:Deco("Block", name .. "_Plate", Vector3.new(0.9, 1.4, 0.9), MapKit.Facing(base, base + f) * CFrame.new(0, 0, 0.1), metal, metalMat, { Shadow = false })
		self:Rod("Decor", name .. "_Arm", base, base + f * 1.1 + Vector3.new(0, 0.3, 0), 0.18, metal, metalMat, { Shadow = false })
		local center = base + f * 1.2 + Vector3.new(0, 0.9, 0)
		lantern(center, 0.8)
		return addLight(center)
	elseif style == "Brazier" then
		local height = o.Height or 3.2
		self:Solid("Cylinder", name .. "_Stand", Vector3.new(height - 0.8, 0.7, 0.7), CFrame.new(base + Vector3.new(0, (height - 0.8) / 2, 0)) * UPRIGHT, metal, metalMat)
		self:Disc("Decor", name .. "_Bowl", base + Vector3.new(0, height - 0.5, 0), 2.6, 0.8, metal, metalMat)
		self:Disc("Decor", name .. "_BowlRim", base + Vector3.new(0, height - 0.08, 0), 2.9, 0.16, o.Rim or GOLD, Enum.Material.Metal, { Shadow = false })
		local flame = self:Deco("Ball", name .. "_Flame", Vector3.new(1.6, 1.6, 1.6), CFrame.new(base + Vector3.new(0, height + 0.2, 0)), glow, Enum.Material.Neon, { Shadow = false })
		self:Deco("Ball", name .. "_FlameTip", Vector3.new(0.9, 0.9, 0.9), CFrame.new(base + Vector3.new(0, height + 1.0, 0)), PartKit.Shade(glow, 0.4), Enum.Material.Neon, { Shadow = false })
		if o.Embers ~= false then
			self:Particles(flame, "Embers", { Color = glow, Rate = 4 })
		end
		return addLight(base + Vector3.new(0, height + 1.2, 0))
	else -- Candle
		local height = o.Height or 1.2
		self:Deco("Cylinder", name .. "_Wax", Vector3.new(height, 0.35, 0.35), CFrame.new(base + Vector3.new(0, height / 2, 0)) * UPRIGHT, o.Wax or rgb(246, 236, 214), Enum.Material.SmoothPlastic, { Shadow = false })
		self:Deco("Ball", name .. "_Flame", Vector3.new(0.3, 0.42, 0.3), CFrame.new(base + Vector3.new(0, height + 0.22, 0)), glow, Enum.Material.Neon, { Shadow = false })
		return addLight(base + Vector3.new(0, height + 0.4, 0))
	end
end

function Builder.Chandelier(self: Builder, name: string, hang: Vector3, opts: { [string]: any }?): Light?
	local o = opts or {}
	local drop = o.Drop or 8
	local radius = o.Radius or 4
	local arms = o.Arms or 8
	local metal = o.Metal or GOLD
	local glow = o.Glow or rgb(255, 214, 140)
	local mat = Enum.Material.Metal
	local center = hang - Vector3.new(0, drop, 0)
	self:Rod("Decor", name .. "_Chain", hang, center + Vector3.new(0, 1.2, 0), 0.22, metal, mat, { Shadow = false })
	self:Deco("Ball", name .. "_Hub", Vector3.new(1.4, 1.4, 1.4), CFrame.new(center + Vector3.new(0, 0.8, 0)), metal, mat)
	self:Disc("Decor", name .. "_Bowl", center, radius * 0.7, 0.5, metal, mat)
	self:Cone("Decor", name .. "_Drop", center - Vector3.new(0, 2.2, 0), 2.0, 0.7, 6, metal, mat, { Shadow = false })
	-- outer ring (box segments) and candle arms
	local ring = math.max(8, arms * 2)
	for k = 0, ring - 1 do
		local a0 = k * 2 * math.pi / ring
		local a1 = (k + 1) * 2 * math.pi / ring
		local p0 = center + Vector3.new(math.cos(a0) * radius, 0.2, math.sin(a0) * radius)
		local p1 = center + Vector3.new(math.cos(a1) * radius, 0.2, math.sin(a1) * radius)
		self:Beam("Decor", name .. "_Ring", p0, p1, 0.28, 0.28, metal, mat, { Shadow = false })
	end
	for k = 0, arms - 1 do
		local a = (k + 0.5) * 2 * math.pi / arms
		local tip = center + Vector3.new(math.cos(a) * radius, 0.2, math.sin(a) * radius)
		self:Rod("Decor", name .. "_Arm", center + Vector3.new(0, 0.3, 0), tip, 0.18, metal, mat, { Shadow = false })
		self:Deco("Cylinder", name .. "_Candle", Vector3.new(0.9, 0.32, 0.32), CFrame.new(tip + Vector3.new(0, 0.6, 0)) * UPRIGHT, rgb(248, 238, 220), Enum.Material.SmoothPlastic, { Shadow = false })
		self:Deco("Ball", name .. "_Flame", Vector3.new(0.34, 0.5, 0.34), CFrame.new(tip + Vector3.new(0, 1.3, 0)), glow, Enum.Material.Neon, { Shadow = false })
	end
	-- hanging crystal drops
	for k = 0, arms - 1 do
		local a = k * 2 * math.pi / arms
		local p = center + Vector3.new(math.cos(a) * radius * 0.92, -0.6, math.sin(a) * radius * 0.92)
		self:Deco("Ball", name .. "_Drop", Vector3.new(0.32, 0.55, 0.32), CFrame.new(p), rgb(255, 240, 210), Enum.Material.Glass, { Shadow = false, Transparency = 0.2 })
	end
	if o.NoLight then
		return nil
	end
	return self:Light("Point", center + Vector3.new(0, 0.8, 0), {
		Name = name .. "_Light",
		Brightness = o.Brightness or 2,
		Range = o.Range or 36,
		Color = o.LightColor or rgb(255, 196, 120),
		Shadows = o.Shadows == true,
	})
end

-- Nature ---------------------------------------------------------------------------------------------------

function Builder.Pine(self: Builder, name: string, base: Vector3, height: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local tiers = o.Tiers or 3
	local sides = o.Sides or 6
	local leaf = o.Leaf or rgb(34, 66, 58)
	local trunkColor = o.Trunk or rgb(74, 52, 40)
	local snow = o.Snow ~= false
	local snowColor = o.SnowColor or SNOW
	local widthF = o.Width or 0.36
	local rng = self.Rng
	local trunkH = height * 0.22
	local trunkD = math.max(0.6, height * 0.06)
	local trunk = self:Part(
		if o.Collide == false then "Decor" else "Geometry",
		"Cylinder",
		name .. "_Trunk",
		Vector3.new(trunkH + 1, trunkD, trunkD),
		CFrame.new(base + Vector3.new(0, (trunkH + 1) / 2 - 0.5, 0)) * UPRIGHT,
		trunkColor,
		Enum.Material.Wood
	)
	local crownH = height - trunkH
	local y = trunkH
	local tierH = crownH / (tiers * 0.72 + 0.28)
	local phase = rng:Number(0, 360)
	for t = 1, tiers do
		local k = (t - 1) / math.max(1, tiers - 1)
		local radius = height * widthF * (1 - 0.48 * k)
		local h = tierH * (1.0 - 0.08 * k)
		local shade = PartKit.Shade(leaf, (rng:Number(-1, 1) * 0.06) + 0.05 * k)
		local tierBase = base + Vector3.new(0, y, 0)
		self:Cone("Decor", name .. "_Tier" .. t, tierBase, h, radius, sides, shade, Enum.Material.SmoothPlastic, {
			Phase = phase + t * 30,
			Shadow = true,
		})
		if snow then
			-- snow mantle on the upper part of each tier (slightly proud of the needles)
			local f = 0.5 + 0.08 * k
			local sBase = tierBase + Vector3.new(0, h * (1 - f), 0)
			self:Cone("Decor", name .. "_Snow" .. t, sBase + Vector3.new(0, 0.06, 0), h * f + 0.08, radius * f + 0.12, sides, snowColor, Enum.Material.Snow, {
				Phase = phase + t * 30,
				Shadow = false,
			})
		end
		y += h * 0.72
	end
	return trunk
end

function Builder.Tree(self: Builder, name: string, base: Vector3, height: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local leaf = o.Leaf or rgb(96, 142, 70)
	local trunkColor = o.Trunk or rgb(100, 72, 50)
	local rng = self.Rng
	local trunkH = height * 0.45
	local trunk = self:Solid("Cylinder", name .. "_Trunk", Vector3.new(trunkH + 0.5, height * 0.08, height * 0.08), CFrame.new(base + Vector3.new(0, (trunkH + 0.5) / 2 - 0.25, 0)) * UPRIGHT, trunkColor, Enum.Material.Wood)
	local crown = base + Vector3.new(0, trunkH + height * 0.22, 0)
	local r = height * 0.32
	self:Deco("Ellipsoid", name .. "_Crown", Vector3.new(r * 2, r * 1.6, r * 2), CFrame.new(crown), leaf, Enum.Material.LeafyGrass)
	for i = 1, (o.Blobs or 4) do
		local a = rng:Number(0, 2 * math.pi)
		local off = Vector3.new(math.cos(a) * r * 0.62, rng:Number(-0.25, 0.4) * r, math.sin(a) * r * 0.62)
		local s = r * rng:Number(0.9, 1.25)
		self:Deco("Ellipsoid", name .. "_Blob" .. i, Vector3.new(s, s * 0.85, s), CFrame.new(crown + off), PartKit.Shade(leaf, rng:Number(-0.12, 0.1)), Enum.Material.LeafyGrass)
	end
	if o.Blossom then
		for i = 1, 6 do
			local a = rng:Number(0, 2 * math.pi)
			local p = crown + Vector3.new(math.cos(a) * r * 0.9, rng:Number(-0.1, 0.6) * r, math.sin(a) * r * 0.9)
			self:Deco("Ball", name .. "_Blossom" .. i, Vector3.new(0.6, 0.6, 0.6), CFrame.new(p), o.Blossom, Enum.Material.SmoothPlastic, { Shadow = false })
		end
	end
	return trunk
end

function Builder.Rock(self: Builder, name: string, center: Vector3, size: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local color = o.Color or rgb(110, 112, 120)
	local material = o.Material or Enum.Material.Slate
	local rng = self.Rng
	local collide = if o.Collide == nil then size >= 3 else o.Collide
	local cat = if collide then "Geometry" else "Decor"
	local main = self:Part(
		cat,
		"Block",
		name,
		Vector3.new(size, size * 0.62, size * 0.85),
		CFrame.new(center + Vector3.new(0, size * 0.2, 0)) * CFrame.Angles(math.rad(rng:Number(-12, 12)), math.rad(rng:Number(0, 360)), math.rad(rng:Number(-15, 15))),
		PartKit.Shade(color, rng:Number(-0.08, 0.08)),
		material
	)
	for i = 1, (o.Chunks or 2) do
		local a = rng:Number(0, 2 * math.pi)
		local s = size * rng:Number(0.35, 0.6)
		local p = center + Vector3.new(math.cos(a) * size * 0.45, s * 0.18, math.sin(a) * size * 0.45)
		self:Part(
			cat,
			"Block",
			name .. "_Chunk" .. i,
			Vector3.new(s, s * 0.7, s * 0.9),
			CFrame.new(p) * CFrame.Angles(math.rad(rng:Number(-25, 25)), math.rad(rng:Number(0, 360)), math.rad(rng:Number(-25, 25))),
			PartKit.Shade(color, rng:Number(-0.15, 0.05)),
			material
		)
	end
	if o.Snow then
		self:Deco("Ellipsoid", name .. "_Snow", Vector3.new(size * 0.95, size * 0.28, size * 0.8), CFrame.new(center + Vector3.new(0, size * 0.5, 0)) * CFrame.Angles(0, math.rad(rng:Number(0, 360)), 0), o.SnowColor or SNOW, Enum.Material.Snow)
	end
	return main
end

function Builder.Crystal(self: Builder, name: string, base: Vector3, height: number, opts: { [string]: any }?): Light?
	local o = opts or {}
	local color = o.Color or rgb(90, 220, 255)
	local rng = self.Rng
	local count = o.Count or 4
	for i = 1, count do
		local h = height * (if i == 1 then 1 else rng:Number(0.4, 0.75))
		local w = h * rng:Number(0.18, 0.26)
		local tilt = if i == 1 then 0 else rng:Number(15, 35)
		local yaw = rng:Number(0, 360)
		local off = if i == 1 then Vector3.new() else Vector3.new(rng:Number(-1, 1), 0, rng:Number(-1, 1)) * (height * 0.18)
		local frame = CFrame.new(base + off) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(tilt), 0, 0)
		local bodyH = h * 0.72
		self:Deco("Block", name .. "_Body" .. i, Vector3.new(w, bodyH, w), frame * CFrame.new(0, bodyH / 2, 0) * CFrame.Angles(0, math.rad(45), 0), color, o.Material or Enum.Material.Neon, { Transparency = o.Transparency or 0.15 })
		local tipBase = frame * CFrame.new(0, bodyH, 0)
		-- 4-sided tip in the crystal's own frame
		local corners: { Vector3 } = {}
		for k = 0, 3 do
			local a = math.rad(45 + k * 90 + 45)
			table.insert(corners, tipBase * Vector3.new(math.cos(a) * w * 0.7071, 0, math.sin(a) * w * 0.7071))
		end
		local apex = tipBase * Vector3.new(0, h - bodyH, 0)
		for k = 1, 4 do
			self:Triangle("Decor", name .. "_Tip" .. i .. "_" .. k, apex, corners[k], corners[k % 4 + 1], 0.08, color, o.Material or Enum.Material.Neon, { Transparency = o.Transparency or 0.15, Shadow = false })
		end
	end
	if o.Light == false then
		return nil
	end
	return self:Light("Point", base + Vector3.new(0, height * 0.5, 0), { Name = name .. "_Light", Brightness = o.Brightness or 1.2, Range = o.Range or 12, Color = color })
end

-- Structures ---------------------------------------------------------------------------------------------

function Builder.Bridge(self: Builder, name: string, a: Vector3, b: Vector3, width: number, opts: { [string]: any }?): { BasePart }
	local o = opts or {}
	local wood = o.Color or rgb(122, 86, 58)
	local rise = o.Arch or 1.6
	local rng = self.Rng
	local out: { BasePart } = {}
	local delta = b - a
	local length = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local plankW = o.PlankWidth or 1.5
	local n = math.max(2, math.floor(length / plankW + 0.5))
	local function deckPoint(t: number): Vector3
		return a:Lerp(b, t) + Vector3.new(0, math.sin(t * math.pi) * rise, 0)
	end
	for i = 0, n - 1 do
		local p0, p1 = deckPoint(i / n), deckPoint((i + 1) / n)
		local mid = (p0 + p1) / 2
		local dir = p1 - p0
		local frame = PartKit.Basis(mid - Vector3.new(0, 0.2, 0), dir, UP) * CFrame.Angles(math.rad(rng:Number(-1.2, 1.2)), 0, 0)
		table.insert(out, self:Solid("Block", name .. "_Plank" .. i, Vector3.new(dir.Magnitude + 0.04, 0.4, width), frame, PartKit.Shade(wood, rng:Number(-0.1, 0.08)), Enum.Material.WoodPlanks))
	end
	-- stringers + rails on both sides
	for _, side in { -1, 1 } do
		local normal = Vector3.new(-delta.Z, 0, delta.X).Unit * (side * width / 2)
		local last: Vector3? = nil
		local posts = math.max(2, math.floor(length / 5))
		for i = 0, posts do
			local p = deckPoint(i / posts) + normal
			self:Deco("Block", name .. "_Post", Vector3.new(0.45, 3.4, 0.45), CFrame.new(p + Vector3.new(0, 1.3, 0)), PartKit.Shade(wood, -0.15), Enum.Material.Wood)
			if last then
				self:Beam("Decor", name .. "_Rail", (last :: Vector3) + Vector3.new(0, 3, 0), p + Vector3.new(0, 3, 0), 0.3, 0.3, PartKit.Shade(wood, -0.05), Enum.Material.Wood)
				self:Beam("Decor", name .. "_Stringer", (last :: Vector3) - Vector3.new(0, 0.6, 0), p - Vector3.new(0, 0.6, 0), 0.5, 0.6, PartKit.Shade(wood, -0.25), Enum.Material.Wood)
				if o.Snow then
					self:Beam("Decor", name .. "_RailSnow", (last :: Vector3) + Vector3.new(0, 3.2, 0), p + Vector3.new(0, 3.2, 0), 0.34, 0.14, SNOW, Enum.Material.Snow, { Shadow = false })
				end
				-- invisible side collider so nobody walks off the deck into the creek by accident
				local mid = ((last :: Vector3) + p) / 2
				local seg = p - (last :: Vector3)
				self:Solid("Block", name .. "_RailCollider", Vector3.new(seg.Magnitude, 3.4, 0.4), PartKit.Basis(mid + Vector3.new(0, 1.7, 0), seg, UP), wood, Enum.Material.Wood, {
					Transparency = 1,
					Shadow = false,
					Query = false,
				})
			end
			last = p
		end
	end
	return out
end

function Builder.Fence(self: Builder, name: string, points: { Vector3 }, opts: { [string]: any }?): { BasePart }
	local o = opts or {}
	local height = o.Height or 3.2
	local spacing = o.Spacing or 6
	local color = o.Color or rgb(132, 96, 66)
	local rng = self.Rng
	local out: { BasePart } = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local delta = b - a
		local n = math.max(1, math.ceil(delta.Magnitude / spacing))
		for k = 0, n do
			if k == 0 and i > 1 then
				continue
			end
			local p = a + delta * (k / n)
			local h = height + rng:Number(-0.15, 0.25)
			table.insert(out, self:Solid("Block", name .. "_Post", Vector3.new(0.55, h, 0.55), CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, math.rad(rng:Number(-6, 6)), math.rad(rng:Number(-2, 2))), PartKit.Shade(color, rng:Number(-0.12, 0.05)), Enum.Material.Wood))
			if o.Snow then
				self:Deco("Block", name .. "_PostSnow", Vector3.new(0.7, 0.22, 0.7), CFrame.new(p + Vector3.new(0, h + 0.08, 0)), SNOW, Enum.Material.Snow, { Shadow = false })
			end
		end
		for r, y in { height * 0.35, height * 0.78 } do
			table.insert(out, self:Beam("Geometry", name .. "_Rail" .. r, a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.25, 0.4, PartKit.Shade(color, 0.05), Enum.Material.WoodPlanks, { Collide = true }))
			if o.Snow and r == 2 then
				self:Beam("Decor", name .. "_RailSnow", a + Vector3.new(0, y + 0.28, 0), b + Vector3.new(0, y + 0.28, 0), 0.32, 0.16, SNOW, Enum.Material.Snow, { Shadow = false })
			end
		end
	end
	return out
end

function Builder.Signpost(self: Builder, name: string, base: Vector3, signs: { { [string]: any } }, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local wood = o.Color or rgb(118, 84, 56)
	local height = o.Height or 7
	local post = self:Solid("Block", name .. "_Post", Vector3.new(0.6, height, 0.6), CFrame.new(base + Vector3.new(0, height / 2, 0)), wood, Enum.Material.Wood)
	self:Deco("Ball", name .. "_Cap", Vector3.new(0.8, 0.8, 0.8), CFrame.new(base + Vector3.new(0, height + 0.2, 0)), PartKit.Shade(wood, -0.2), Enum.Material.Wood, { Shadow = false })
	for i, sign in signs do
		local y = height - 0.9 - (i - 1) * 1.3
		local yaw = math.rad(sign.Yaw or 0)
		local frame = CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, yaw, 0)
		local color = sign.Color or rgb(206, 176, 128)
		local board = self:Deco("Block", name .. "_Sign" .. i, Vector3.new(3.6, 0.95, 0.22), frame * CFrame.new(2.1, 0, 0), color, Enum.Material.WoodPlanks)
		-- arrow tip
		local tipBase = frame * CFrame.new(3.9, 0, 0)
		self:Triangle("Decor", name .. "_Tip" .. i, tipBase * Vector3.new(0, 0.475, 0), tipBase * Vector3.new(0, -0.475, 0), tipBase * Vector3.new(0.7, 0, 0), 0.22, color, Enum.Material.WoodPlanks)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			self:Text(board, face, { Key = sign.Key, Text = sign.Text, Color = o.TextColor or rgb(62, 40, 26), Font = "Merriweather", Pixels = 60 })
		end
		if o.Snow then
			self:Deco("Block", name .. "_SignSnow" .. i, Vector3.new(3.5, 0.14, 0.3), frame * CFrame.new(2.1, 0.53, 0), SNOW, Enum.Material.Snow, { Shadow = false })
		end
	end
	return post
end

function Builder.House(self: Builder, name: string, cf: CFrame, opts: { [string]: any }?): { Light }
	local o = opts or {}
	local w = o.Width or 18
	local d = o.Depth or 14
	local wallH = o.WallHeight or 10
	local roofH = o.RoofHeight or 6
	local over = o.Overhang or 1.4
	local wallColor = o.WallColor or rgb(150, 104, 70)
	local wallMat = o.WallMaterial or Enum.Material.WoodPlanks
	local trim = o.Trim or rgb(84, 58, 42)
	local roofColor = o.RoofColor or rgb(120, 60, 54)
	local roofMat = o.RoofMaterial or Enum.Material.RoofShingles
	local glow = o.Glow or rgb(255, 184, 96)
	local lightColor = o.LightColor or rgb(255, 170, 90)
	local snow = o.Snow == true
	local rng = self.Rng
	local lights: { Light } = {}
	-- foundation + body
	self:Solid("Block", name .. "_Footing", Vector3.new(w + 0.8, 1.2, d + 0.8), cf * CFrame.new(0, 0.3, 0), o.Stone or rgb(96, 92, 98), Enum.Material.Cobblestone)
	self:Solid("Block", name .. "_Body", Vector3.new(w, wallH, d), cf * CFrame.new(0, wallH / 2 + 0.5, 0), wallColor, wallMat)
	-- timber corner posts and a mid beam (decor)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			self:Deco("Block", name .. "_Corner", Vector3.new(0.8, wallH + 0.2, 0.8), cf * CFrame.new(sx * w / 2, wallH / 2 + 0.6, sz * d / 2), trim, Enum.Material.Wood)
		end
	end
	self:Deco("Block", name .. "_BeltF", Vector3.new(w + 0.3, 0.5, 0.3), cf * CFrame.new(0, wallH * 0.92 + 0.5, -d / 2 - 0.1), trim, Enum.Material.Wood, { Shadow = false })
	self:Deco("Block", name .. "_BeltB", Vector3.new(w + 0.3, 0.5, 0.3), cf * CFrame.new(0, wallH * 0.92 + 0.5, d / 2 + 0.1), trim, Enum.Material.Wood, { Shadow = false })
	-- gable roof (ridge along local X)
	local halfD = d / 2 + over
	local slopeLen = math.sqrt(halfD * halfD + roofH * roofH)
	local pitch = math.atan2(roofH, halfD)
	local eaveY = wallH + 0.5
	for _, side in { -1, 1 } do
		-- slab centred on the slope line, rotated about X
		local mid = cf * CFrame.new(0, eaveY + roofH / 2 + 0.25, side * halfD / 2)
		local slab = mid * CFrame.Angles(side * pitch, 0, 0)
		self:Solid("Block", name .. "_Roof", Vector3.new(w + over * 2, 0.6, slopeLen + 0.3), slab, roofColor, roofMat)
		if snow then
			self:Deco("Block", name .. "_RoofSnow", Vector3.new(w + over * 2 - 0.2, 0.55, slopeLen * 0.96), slab * CFrame.new(0, 0.5, 0), SNOW, Enum.Material.Snow, { Shadow = false })
			-- rounded snow lip along the eave
			self:Deco("Cylinder", name .. "_SnowLip", Vector3.new(w + over * 2, 0.9, 0.9), slab * CFrame.new(0, 0.42, side * (slopeLen / 2 - 0.1)), SNOW, Enum.Material.Snow, { Shadow = false })
			-- icicles along the eave
			local count = math.floor((w + over * 2) / 2.2)
			for k = 1, count do
				if rng:Bool(0.75) then
					local x = -(w + over * 2) / 2 + (k - 0.5) * (w + over * 2) / count + rng:Number(-0.4, 0.4)
					local tipLen = rng:Number(0.8, 2.0)
					local root = (slab * CFrame.new(x, -0.2, side * (slopeLen / 2 + 0.05))).Position
					self:Cone("Decor", name .. "_Icicle", root, -tipLen, 0.22, 3, rgb(210, 236, 255), Enum.Material.Ice, { Shadow = false, Transparency = 0.15 })
				end
			end
		end
	end
	-- gable triangles (front/back of the roof volume along X)
	for _, sx in { -1, 1 } do
		local a = cf * Vector3.new(sx * w / 2, eaveY, -d / 2)
		local b = cf * Vector3.new(sx * w / 2, eaveY, d / 2)
		local c = cf * Vector3.new(sx * w / 2, eaveY + roofH - 0.2, 0)
		self:Triangle("Geometry", name .. "_Gable", a, b, c, 0.8, PartKit.Shade(wallColor, -0.06), wallMat)
		-- round attic window glowing in the gable
		self:Deco("Cylinder", name .. "_Attic", Vector3.new(0.3, 1.8, 1.8), cf * CFrame.new(sx * (w / 2 + 0.35), eaveY + roofH * 0.38, 0), glow, Enum.Material.Neon, { Shadow = false })
		self:Deco("Cylinder", name .. "_AtticRim", Vector3.new(0.25, 2.3, 2.3), cf * CFrame.new(sx * (w / 2 + 0.25), eaveY + roofH * 0.38, 0), trim, Enum.Material.Wood, { Shadow = false })
	end
	self:Deco("Cylinder", name .. "_Ridge", Vector3.new(w + over * 2 + 0.4, 0.7, 0.7), cf * CFrame.new(0, eaveY + roofH + 0.25, 0), trim, Enum.Material.Wood)
	if snow then
		self:Deco("Cylinder", name .. "_RidgeSnow", Vector3.new(w + over * 2 + 0.2, 1.1, 1.1), cf * CFrame.new(0, eaveY + roofH + 0.55, 0), SNOW, Enum.Material.Snow, { Shadow = false })
	end
	-- front door (local -Z face)
	local doorW, doorH = o.DoorWidth or 3.6, o.DoorHeight or 6.4
	local doorX = o.DoorX or 0
	local front = -d / 2
	self:Deco("Block", name .. "_DoorFrame", Vector3.new(doorW + 1, doorH + 0.6, 0.4), cf * CFrame.new(doorX, 0.5 + (doorH + 0.6) / 2, front - 0.15), trim, Enum.Material.Wood)
	self:Deco("Block", name .. "_Door", Vector3.new(doorW, doorH, 0.4), cf * CFrame.new(doorX, 0.5 + doorH / 2, front - 0.3), o.DoorColor or rgb(96, 58, 40), Enum.Material.WoodPlanks)
	self:Deco("Ball", name .. "_Knob", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(doorX + doorW * 0.32, 0.5 + doorH * 0.48, front - 0.55), GOLD, Enum.Material.Metal, { Shadow = false })
	self:Solid("Block", name .. "_Step", Vector3.new(doorW + 1.6, 0.5, 1.6), cf * CFrame.new(doorX, 0.25, front - 0.8), o.Stone or rgb(96, 92, 98), Enum.Material.Cobblestone)
	-- porch lantern by the door
	local lanternLight = self:Lamp(name .. "_DoorLamp", (cf * CFrame.new(doorX + doorW / 2 + 1.1, doorH * 0.8, front - 0.2)).Position, {
		Style = "Wall",
		Facing = -cf.LookVector * -1,
		Glow = glow,
		LightColor = lightColor,
		Brightness = o.LampBrightness or 1.6,
		Range = o.LampRange or 16,
		NoLight = o.NoDoorLight,
	})
	if lanternLight then
		table.insert(lights, lanternLight)
	end
	-- windows: front (either side of the door) + both side walls
	local winW, winH = 3, 3.4
	local winY = 0.5 + wallH * 0.52
	local function window(localCF: CFrame, withLight: boolean)
		self:Deco("Block", name .. "_WinFrame", Vector3.new(winW + 0.8, winH + 0.8, 0.3), localCF * CFrame.new(0, 0, -0.1), trim, Enum.Material.Wood)
		self:Deco("Block", name .. "_WinGlow", Vector3.new(winW, winH, 0.3), localCF * CFrame.new(0, 0, -0.2), glow, Enum.Material.Neon, { Shadow = false })
		self:Deco("Block", name .. "_WinBarV", Vector3.new(0.22, winH, 0.2), localCF * CFrame.new(0, 0, -0.4), trim, Enum.Material.Wood, { Shadow = false })
		self:Deco("Block", name .. "_WinBarH", Vector3.new(winW, 0.22, 0.2), localCF * CFrame.new(0, 0, -0.4), trim, Enum.Material.Wood, { Shadow = false })
		self:Deco("Block", name .. "_WinSill", Vector3.new(winW + 1.2, 0.3, 0.8), localCF * CFrame.new(0, -winH / 2 - 0.45, -0.35), trim, Enum.Material.Wood, { Shadow = false })
		for _, sx in { -1, 1 } do
			self:Deco("Block", name .. "_Shutter", Vector3.new(winW * 0.48, winH + 0.4, 0.18), localCF * CFrame.new(sx * (winW * 0.74 + 0.4), 0, -0.25), o.Shutter or PartKit.Shade(roofColor, 0.05), Enum.Material.WoodPlanks, { Shadow = false })
		end
		if snow then
			self:Deco("Block", name .. "_SillSnow", Vector3.new(winW + 1.1, 0.25, 0.75), localCF * CFrame.new(0, -winH / 2 - 0.2, -0.35), SNOW, Enum.Material.Snow, { Shadow = false })
		end
		if withLight and not o.NoWindowLights then
			table.insert(
				lights,
				self:Light("Point", (localCF * CFrame.new(0, -0.3, -1.6)).Position, {
					Name = name .. "_WinLight",
					Brightness = o.WindowBrightness or 1.4,
					Range = o.WindowRange or 14,
					Color = lightColor,
				})
			)
		end
	end
	local frontCF = cf * CFrame.new(0, winY, front)
	local winOffsets = o.FrontWindows or { -w * 0.3, w * 0.3 }
	for i, x in winOffsets do
		if math.abs(x - doorX) > doorW / 2 + winW / 2 + 0.8 then
			window(frontCF * CFrame.new(x, 0, 0), i == 1)
		end
	end
	for _, sx in { -1, 1 } do
		local sideCF = cf * CFrame.new(sx * w / 2, winY, 0) * CFrame.Angles(0, -sx * HALF_PI, 0)
		window(sideCF, false)
	end
	-- chimney + smoke
	if o.Chimney ~= false then
		local cx = o.ChimneyX or w * 0.28
		local cz = d * 0.18
		local ch = roofH + 3
		local chimney = self:Solid("Block", name .. "_Chimney", Vector3.new(2, ch, 2), cf * CFrame.new(cx, eaveY + ch / 2 - 0.5, cz), o.ChimneyColor or rgb(128, 82, 70), Enum.Material.Brick)
		self:Deco("Block", name .. "_ChimneyCap", Vector3.new(2.5, 0.4, 2.5), cf * CFrame.new(cx, eaveY + ch - 0.3, cz), PartKit.Shade(o.ChimneyColor or rgb(128, 82, 70), -0.2), Enum.Material.Brick)
		if snow then
			self:Deco("Block", name .. "_ChimneySnow", Vector3.new(2.4, 0.3, 2.4), cf * CFrame.new(cx, eaveY + ch, cz), SNOW, Enum.Material.Snow, { Shadow = false })
		end
		if o.Smoke ~= false then
			local emitterPart = self:Deco("Block", name .. "_Smoke", Vector3.new(1.2, 0.2, 1.2), cf * CFrame.new(cx, eaveY + ch + 0.4, cz), WHITE, Enum.Material.SmoothPlastic, { Transparency = 1, Shadow = false })
			self:Particles(emitterPart, "Smoke", { Rate = 2.5 })
		end
		local _ = chimney
	end
	if o.Sign then
		local board = self:Deco("Block", name .. "_Sign", Vector3.new(math.min(w * 0.6, 10), 1.6, 0.3), cf * CFrame.new(doorX, 0.5 + doorH + 1.4, front - 0.35), o.SignColor or rgb(224, 196, 140), Enum.Material.WoodPlanks)
		self:Text(board, Enum.NormalId.Front, { Key = o.Sign, Color = rgb(70, 40, 24), Font = "Merriweather", Pixels = 50 })
		if snow then
			self:Deco("Block", name .. "_SignSnow", Vector3.new(math.min(w * 0.6, 10), 0.2, 0.4), cf * CFrame.new(doorX, 0.5 + doorH + 2.25, front - 0.35), SNOW, Enum.Material.Snow, { Shadow = false })
		end
	end
	return lights
end

-- Terrain-like mounds: walkable sphere caps (exact collision) or decorative ellipsoid drifts.
function Builder.Mound(self: Builder, name: string, center: Vector3, radius: number, height: number, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local color = o.Color or SNOW
	local material = o.Material or Enum.Material.Snow
	local collide = if o.Collide == nil then height > 1.4 else o.Collide
	if collide then
		local R = (radius * radius + height * height) / (2 * height)
		return self:Solid("Ball", name, Vector3.new(R * 2, R * 2, R * 2), CFrame.new(center + Vector3.new(0, height - R, 0)), color, material, { Shadow = false })
	end
	local yaw = o.Yaw or self.Rng:Number(0, 360)
	local stretch = o.Stretch or 1
	return self:Deco("Ellipsoid", name, Vector3.new(radius * 2 * stretch, height * 2, radius * 2), CFrame.new(center) * CFrame.Angles(0, math.rad(yaw), 0), color, material, { Shadow = false })
end

-- Decorative bones (crossed pair or a small pile).
function Builder.Bones(self: Builder, name: string, cf: CFrame, opts: { [string]: any }?): ()
	local o = opts or {}
	local color = o.Color or rgb(240, 236, 224)
	local length = o.Length or 3
	local thick = o.Thickness or 0.35
	local parent = self:_folder("Decor")
	local props = { Material = o.Material or Enum.Material.SmoothPlastic, CastShadow = true, Anchored = true }
	if o.Pile then
		local rng = self.Rng
		for i = 1, o.Pile do
			local yaw = rng:Number(0, 2 * math.pi)
			local p = cf * Vector3.new(rng:Number(-1, 1) * length * 0.4, thick * 0.6 + (i % 2) * thick * 0.8, rng:Number(-1, 1) * length * 0.4)
			local dir = Vector3.new(math.cos(yaw), rng:Number(-0.05, 0.12), math.sin(yaw)) * (length / 2)
			self._kit.Bone(parent, name .. "_" .. i, p - dir, p + dir, thick, color, props)
		end
		return
	end
	for _, sign in { -1, 1 } do
		local dir = cf:VectorToWorldSpace(Vector3.new(math.cos(math.rad(45)) * sign, math.sin(math.rad(45)), 0)) * (length / 2)
		local mid = cf.Position
		self._kit.Bone(parent, name .. (if sign < 0 then "_A" else "_B"), mid - dir, mid + dir, thick, color, props)
	end
end

-- A big stone monster-skull statue on a plinth (decor except the plinth).
function Builder.SkullStatue(self: Builder, name: string, base: Vector3, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local scale = o.Scale or 1
	local stone = o.Color or rgb(214, 204, 184)
	local dark = o.Dark or rgb(34, 28, 30)
	local accent = o.Accent or GOLD
	local facing: Vector3 = o.Facing or Vector3.new(0, 0, -1)
	local frame = MapKit.Facing(base, base + facing)
	local plinthH = 4 * scale
	local plinth = self:Solid("Block", name .. "_Plinth", Vector3.new(6, plinthH, 6) * scale, frame * CFrame.new(0, plinthH / 2, 0), PartKit.Shade(stone, -0.2), Enum.Material.Marble)
	self:Deco("Block", name .. "_PlinthBand", Vector3.new(6.3, 0.4, 6.3) * scale, frame * CFrame.new(0, plinthH - 0.5 * scale, 0), accent, Enum.Material.Metal, { Shadow = false })
	local head = frame * CFrame.new(0, plinthH + 3.4 * scale, 0)
	self:Deco("Ellipsoid", name .. "_Cranium", Vector3.new(6.2, 5.6, 5.8) * scale, head, stone, Enum.Material.Marble)
	self:Deco("Ellipsoid", name .. "_Cheeks", Vector3.new(6.6, 3.2, 5.2) * scale, head * CFrame.new(0, -1.5 * scale, -0.3 * scale), stone, Enum.Material.Marble)
	self:Deco("Block", name .. "_Jaw", Vector3.new(4.6, 1.2, 4) * scale, head * CFrame.new(0, -2.9 * scale, -0.4 * scale), PartKit.Shade(stone, -0.05), Enum.Material.Marble)
	for _, side in { -1, 1 } do
		self:Deco("Ellipsoid", name .. "_Socket", Vector3.new(1.6, 1.8, 1) * scale, head * CFrame.new(side * 1.35 * scale, 0.2 * scale, -2.65 * scale), dark, Enum.Material.SmoothPlastic, { Shadow = false })
		self:Deco("Ball", name .. "_Pupil", Vector3.new(0.45, 0.45, 0.45) * scale, head * CFrame.new(side * 1.35 * scale, 0.15 * scale, -3.0 * scale), o.Eye or rgb(255, 230, 170), Enum.Material.Neon, { Shadow = false })
	end
	self:Deco("Block", name .. "_Nose", Vector3.new(0.5, 0.7, 0.4) * scale, head * CFrame.new(0, -1 * scale, -2.85 * scale) * CFrame.Angles(0, 0, math.rad(45)), dark, Enum.Material.SmoothPlastic, { Shadow = false })
	-- grin line with teeth gaps
	self:Deco("Block", name .. "_Grin", Vector3.new(3.4, 0.16, 0.3) * scale, head * CFrame.new(0, -2.25 * scale, -2.45 * scale), dark, Enum.Material.SmoothPlastic, { Shadow = false })
	for k = -2, 2 do
		self:Deco("Block", name .. "_Tooth", Vector3.new(0.1, 0.6, 0.3) * scale, head * CFrame.new(k * 0.62 * scale, -2.25 * scale, -2.45 * scale), dark, Enum.Material.SmoothPlastic, { Shadow = false })
	end
	return plinth
end

-- Text, prompts, markers -------------------------------------------------------------------------------------

function Builder.Text(self: Builder, part: BasePart, face: Enum.NormalId, opts: { [string]: any }): SurfaceGui
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.Name or ("Text_" .. face.Name)
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.Pixels or 50
	gui.LightInfluence = if o.Glow then 0 else 1
	gui.Brightness = o.Brightness or (if o.Glow then 1.6 else 1)
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(o.Width or 0.92, o.Height or 0.86)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = o.Rich == true
	label.FontFace = Font.new("rbxasset://fonts/families/" .. (o.Font or "Merriweather") .. ".json", o.Weight or Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	label.TextColor3 = o.Color or rgb(255, 244, 220)
	label.TextStrokeColor3 = o.StrokeColor or rgb(20, 14, 10)
	label.TextStrokeTransparency = if o.Stroke then 0.4 else 1
	label.TextXAlignment = o.Align or Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	if o.Attributes then
		for k, v in o.Attributes do
			label:SetAttribute(k, v)
		end
	end
	if o.Key then
		label:SetAttribute("TextKey", o.Key)
		label.Text = L(o.Key, table.unpack(o.Args or {}))
	else
		label.Text = o.Text or ""
	end
	label.Parent = gui
	gui.Parent = part
	return gui
end

function Builder.Prompt(self: Builder, part: BasePart, opts: { [string]: any }): ProximityPrompt
	local o = opts or {}
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = o.Name or "Prompt"
	prompt.ActionText = if o.ActionKey then L(o.ActionKey) else (o.ActionText or "")
	prompt.ObjectText = if o.ObjectKey then L(o.ObjectKey) else (o.ObjectText or "")
	prompt.HoldDuration = o.Hold or 0
	prompt.MaxActivationDistance = o.Distance or 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = o.KeyCode or Enum.KeyCode.E
	prompt:SetAttribute("Action", o.Action or "")
	if o.ActionKey then
		prompt:SetAttribute("ActionTextKey", o.ActionKey)
	end
	if o.ObjectKey then
		prompt:SetAttribute("ObjectTextKey", o.ObjectKey)
	end
	prompt.Parent = part
	return prompt
end

function Builder.Marker(self: Builder, name: string, cf: CFrame, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local prev = self._group
	self._group = o.Group
	local part = self:Part("Markers", "Block", name, o.Size or Vector3.new(1, 1, 1), cf, o.Color or rgb(255, 0, 255), Enum.Material.SmoothPlastic, {
		Collide = false,
		Query = false,
		Shadow = false,
		Transparency = 1,
	})
	self._group = prev
	if o.Attributes then
		for k, v in o.Attributes do
			part:SetAttribute(k, v)
		end
	end
	return part
end

function Builder.SpawnPoint(self: Builder, kind: string, index: number, cf: CFrame): CFrame
	self:Marker(kind .. "Spawn_" .. index, cf + Vector3.new(0, 0.5, 0), { Group = "Spawns", Attributes = { Kind = kind, Index = index } })
	return cf
end

-- SAVE point inlay: gold ring + star flush with the floor; the returned point is the ground point.
function Builder.SavePoint(self: Builder, index: number, pos: Vector3, opts: { [string]: any }?): Vector3
	local o = opts or {}
	local gold = o.Color or rgb(232, 186, 82)
	local radius = o.Radius or Config.Objectives.SaveRadius
	local prev = self:Group("SavePoints")
	self:Disc("Decor", "Save" .. index .. "_Ring", pos + Vector3.new(0, 0.03, 0), radius * 2 + 0.6, 0.06, gold, Enum.Material.Metal, { Shadow = false })
	self:Disc("Decor", "Save" .. index .. "_Inner", pos + Vector3.new(0, 0.045, 0), radius * 2 - 0.6, 0.06, o.Inner or rgb(56, 40, 30), o.InnerMaterial or Enum.Material.Marble, { Shadow = false })
	self:Disc("Decor", "Save" .. index .. "_Halo", pos + Vector3.new(0, 0.06, 0), 7, 0.06, PartKit.Shade(gold, -0.3), Enum.Material.Metal, { Shadow = false })
	self:Star("Decor", "Save" .. index .. "_Star", CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(-HALF_PI, 0, 0), 3, 1.25, 0, o.StarColor or rgb(255, 222, 120), Enum.Material.Neon, { Shadow = false })
	self:Group(prev)
	self:Marker("SavePoint_" .. index, CFrame.new(pos + Vector3.new(0, 0.5, 0)), { Group = "SavePoints", Attributes = { Index = index } })
	return pos
end

function Builder.Boundary(self: Builder, name: string, cf: CFrame, length: number, height: number, thickness: number?): BasePart
	local t = thickness or 2
	local prev = self:Group("Boundary")
	local part = self:Solid("Block", name, Vector3.new(length, height, t), cf * CFrame.new(0, height / 2, 0), WHITE, Enum.Material.SmoothPlastic, {
		Transparency = 1,
		Shadow = false,
		Query = false,
	})
	self:Group(prev)
	return part
end

function Builder.BoundaryBox(self: Builder, center: Vector3, sizeX: number, sizeZ: number, height: number): ()
	local t = 2
	self:Boundary("BoundaryN", CFrame.new(center + Vector3.new(0, 0, -sizeZ / 2 - t / 2)), sizeX + 2 * t, height, t)
	self:Boundary("BoundaryS", CFrame.new(center + Vector3.new(0, 0, sizeZ / 2 + t / 2)), sizeX + 2 * t, height, t)
	self:Boundary("BoundaryW", CFrame.new(center + Vector3.new(-sizeX / 2 - t / 2, 0, 0)) * CFrame.Angles(0, HALF_PI, 0), sizeZ + 2 * t, height, t)
	self:Boundary("BoundaryE", CFrame.new(center + Vector3.new(sizeX / 2 + t / 2, 0, 0)) * CFrame.Angles(0, HALF_PI, 0), sizeZ + 2 * t, height, t)
end

function Builder.KillFloor(self: Builder, y: number, size: number): BasePart
	return self:Marker("KillFloor", CFrame.new(0, y, 0), { Size = Vector3.new(size, 1, size), Attributes = { KillY = y } })
end

function Builder.Finish(self: Builder, mapId: string): { [string]: number }
	local model = self.Model
	model:SetAttribute("MapId", mapId)
	model:SetAttribute("PartCount", self.PartCount)
	model:SetAttribute("LightCount", self.LightCount)
	model.WorldPivot = CFrame.new()
	return { Parts = self.PartCount, Lights = self.LightCount }
end

-- Convenience for map modules: a level CFrame at `pos` facing `target`, as a GROUND spawn point.
function MapKit.SpawnFacing(pos: Vector3, target: Vector3): CFrame
	return MapKit.Facing(pos, target)
end

local _ = DARK
return MapKit
