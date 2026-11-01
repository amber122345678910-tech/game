--!strict
-- Props: registry + shared authoring helpers for the prop library (Rigs/Props/*). [Lune-safe]
-- Props are the iconic attack shapes and objects used by combat VFX, objectives and the Verdict
-- Box: bones, Gaster Blasters, SOUL hearts, SAVE stars, the 3D battle box, rifts, void orbs, ...
-- Every builder returns an unparented Model built at the origin facing -Z (SPEC section 3) with a
-- PrimaryPart; parts are Anchored, CanCollide/CanQuery/CanTouch = false and carry a Role attribute.
-- Models get attributes PropId (module name) and PartCount.
--
-- REGISTRY
--   Props.Get(name: string) -> any?          lazily requires Rigs/Props/<name> (nil if missing/broken)
--   Props.Names() -> {string}                 known prop modules that exist in this folder
--   Props.Build(name: string, ...) -> Model?  Props.Get(name).Build(...)
-- AUTHORING HELPERS (used by the prop modules; all positions are authoring space at scale 1)
--   Props.Kit(scale: number?) -> PartKit.Kit   anchored PartKit kit (sizes + positions x scale)
--   Props.NewModel(name: string, propId: string) -> Model
--   Props.Finish(model, primary: BasePart) -> Model   PrimaryPart, safety flags, PartCount
--   Props.Triangle(kit, parent, name, a, b, c, thickness, color, props?) -> {BasePart}
--        a solid triangle (two WedgeParts split along the altitude) extruded by `thickness`
--        symmetrically about the plane of a, b, c. Degenerate halves are skipped.
--   Props.Polygon(kit, parent, name, points: {Vector2}, frame: CFrame, thickness, color, props?)
--        -> {BasePart}   simple polygon (any winding) in frame's local XY plane, ear-clipped
--   Props.StarOutline(points: number, outer: number, inner: number, rotDeg: number?) -> {Vector2}
--        star polygon vertices (tip first, CCW), tip 0 points along +Y unless rotated
--   Props.CountParts(root: Instance) -> number
--   Props.ColorOf(name: string) -> Color3     shared attack colours (White Blue Orange Red Purple
--        Cyan Yellow Green Gold Void Violet) — Blue #14A9FF / Orange #FFA040 per Undertale rules

local PartKit = require(script.Parent.PartKit)

local Props = {}

-- Prop modules this registry knows about (Weapons is owned by the rig team, BoneSword may
-- delegate to it). Order = gallery order.
local KNOWN: { string } = {
	"Bone",
	"GasterBlaster",
	"Soul",
	"SaveStar",
	"VerdictBox3D",
	"Rift",
	"VoidOrb",
	"GiantBook",
	"Dish",
	"StarBone",
	"Chain",
	"BoneSword",
	"Weapons",
}

local COLORS: { [string]: Color3 } = {
	White = Color3.fromRGB(255, 255, 255),
	Blue = Color3.fromRGB(20, 169, 255), -- #14A9FF: hurts while moving
	Orange = Color3.fromRGB(255, 160, 64), -- #FFA040: hurts while still
	Red = Color3.fromRGB(255, 36, 48),
	Purple = Color3.fromRGB(213, 53, 217),
	Cyan = Color3.fromRGB(66, 252, 255),
	Yellow = Color3.fromRGB(255, 255, 0),
	Green = Color3.fromRGB(0, 192, 0),
	Gold = Color3.fromRGB(255, 214, 92),
	Void = Color3.fromRGB(10, 6, 22),
	Violet = Color3.fromRGB(150, 70, 255),
}

local cache: { [string]: any } = {}

function Props.Get(name: string): any?
	local cached = cache[name]
	if cached ~= nil then
		return cached
	end
	local module = script:FindFirstChild(name)
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module :: ModuleScript)
	if not ok or type(result) ~= "table" then
		return nil
	end
	cache[name] = result
	return result
end

function Props.Names(): { string }
	local out: { string } = {}
	for _, name in KNOWN do
		local module = script:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			table.insert(out, name)
		end
	end
	return out
end

function Props.Build(name: string, ...: any): Model?
	local module = Props.Get(name)
	if module == nil or type(module.Build) ~= "function" then
		return nil
	end
	return module.Build(...)
end

function Props.ColorOf(name: string): Color3
	return COLORS[name] or COLORS.White
end

-- Authoring helpers ---------------------------------------------------------------------------

function Props.Kit(scale: number?): PartKit.Kit
	return PartKit.new({ Scale = scale or 1, Anchored = true })
end

function Props.NewModel(name: string, propId: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("PropId", propId)
	return model
end

function Props.CountParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Final safety pass: every part anchored and non-interactive (props are visuals only).
function Props.Finish(model: Model, primary: BasePart): Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.PrimaryPart = primary
	model:SetAttribute("PartCount", Props.CountParts(model))
	return model
end

-- A WedgePart whose right angle sits at `f`, with legs f->p (local +Y) and f->b (local -Z).
local function rightWedge(
	kit: PartKit.Kit,
	parent: Instance?,
	name: string,
	p: Vector3,
	f: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	props: PartKit.Props?
): BasePart?
	local up = p - f
	local back = f - b
	local h, d = up.Magnitude, back.Magnitude
	if h < 1e-4 or d < 1e-4 then
		return nil
	end
	local y = up / h
	local z = back / d
	local x = y:Cross(z)
	local cf = CFrame.fromMatrix((p + b) / 2, x, y, z)
	return kit.Wedge(parent, name, Vector3.new(thickness, h, d), cf, color, props)
end

function Props.Triangle(
	kit: PartKit.Kit,
	parent: Instance?,
	name: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number,
	color: Color3,
	props: PartKit.Props?
): { BasePart }
	-- apex = vertex opposite the longest edge, so the altitude foot lies on that edge
	local ab, bc, ca = (b - a).Magnitude, (c - b).Magnitude, (a - c).Magnitude
	local apex, b1, b2 = a, b, c
	if ab >= bc and ab >= ca then
		apex, b1, b2 = c, a, b
	elseif ca >= ab and ca >= bc then
		apex, b1, b2 = b, c, a
	end
	local base = b2 - b1
	local len2 = base:Dot(base)
	local out: { BasePart } = {}
	if len2 < 1e-8 then
		return out
	end
	local t = math.clamp((apex - b1):Dot(base) / len2, 0, 1)
	local foot = b1 + base * t
	local w1 = rightWedge(kit, parent, name, apex, foot, b1, thickness, color, props)
	if w1 then
		table.insert(out, w1)
	end
	local w2 = rightWedge(kit, parent, name .. "b", apex, foot, b2, thickness, color, props)
	if w2 then
		table.insert(out, w2)
	end
	return out
end

-- Ear clipping for a simple polygon (no self intersections). Returns index triples.
local function triangulate(points: { Vector2 }): { { number } }
	local n = #points
	local idx: { number } = {}
	for i = 1, n do
		idx[i] = i
	end
	local area = 0
	for i = 1, n do
		local p, q = points[i], points[i % n + 1]
		area += p.X * q.Y - q.X * p.Y
	end
	local ccw = area > 0
	local function cross(o: Vector2, a: Vector2, b: Vector2): number
		return (a.X - o.X) * (b.Y - o.Y) - (a.Y - o.Y) * (b.X - o.X)
	end
	local function inside(p: Vector2, a: Vector2, b: Vector2, c: Vector2): boolean
		local d1, d2, d3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
		local hasNeg = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
		local hasPos = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
		return not (hasNeg and hasPos)
	end
	local tris: { { number } } = {}
	local guard = 0
	while #idx > 3 and guard < 500 do
		guard += 1
		local clipped = false
		local m = #idx
		for i = 1, m do
			local ia, ib, ic = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
			local a, b, c = points[ia], points[ib], points[ic]
			local turn = cross(a, b, c)
			local convex = if ccw then turn > 1e-9 else turn < -1e-9
			if convex then
				local ear = true
				for _, j in idx do
					if j ~= ia and j ~= ib and j ~= ic and inside(points[j], a, b, c) then
						ear = false
						break
					end
				end
				if ear then
					table.insert(tris, { ia, ib, ic })
					table.remove(idx, i)
					clipped = true
					break
				end
			end
		end
		if not clipped then
			break -- degenerate input: emit what we have
		end
	end
	if #idx == 3 then
		table.insert(tris, { idx[1], idx[2], idx[3] })
	end
	return tris
end

function Props.Polygon(
	kit: PartKit.Kit,
	parent: Instance?,
	name: string,
	points: { Vector2 },
	frame: CFrame,
	thickness: number,
	color: Color3,
	props: PartKit.Props?
): { BasePart }
	local out: { BasePart } = {}
	for i, tri in triangulate(points) do
		local function at(k: number): Vector3
			local p = points[tri[k]]
			return (frame * CFrame.new(p.X, p.Y, 0)).Position
		end
		for _, part in Props.Triangle(kit, parent, name .. i, at(1), at(2), at(3), thickness, color, props) do
			table.insert(out, part)
		end
	end
	return out
end

function Props.StarOutline(points: number, outer: number, inner: number, rotDeg: number?): { Vector2 }
	local out: { Vector2 } = {}
	local rot = math.rad(rotDeg or 0)
	for i = 0, points * 2 - 1 do
		local r = if i % 2 == 0 then outer else inner
		local a = math.pi / 2 + rot + i * math.pi / points
		table.insert(out, Vector2.new(math.cos(a) * r, math.sin(a) * r))
	end
	return out
end

return Props
