--!strict
-- Blueprint registry + the blueprint/RigContext contract. [Lune-safe]
--
-- Each child ModuleScript of this folder is a blueprint whose module name == its Id
-- (ClassicSans, FellSans, EclipseSans, HumanBase, Determination, ..., Dummy).
-- Modules are required lazily on first use; a missing module is simply "not available yet"
-- (Get returns nil) so agents can add blueprints independently. A module that exists but errors
-- while loading raises a clear error (bugs must not be silent).
--
-- API
--   Blueprints.Get(id) -> Blueprint?      lazy, cached, validated
--   Blueprints.Has(id) -> boolean
--   Blueprints.List() -> {string}         available ids (known roster order first, then extras A-Z)
--   Blueprints.KNOWN -> {string}          the roster from SPEC §2.1 (may not all exist yet)
--   Blueprints.Validate(id, bp)           asserts the blueprint shape (used by Get and RigBuilder)
--
-- BLUEPRINT MODULE SHAPE (SPEC §5.2)
--   return {
--     Id = "Dummy", Family = "Human", Scale = 1.0,
--     Skeleton = "Human",                          -- optional, defaults to Family
--     Overrides = { [limb] = { Size = Vector3?, Joint = Vector3? (pivot DELTA, studs) } }?,
--     GroundOffset = number?,                      -- lift the skeleton (e.g. it stands on its own base)
--     Palette = { [key] = Color3 },                -- default colours; skins override keys
--     Anchors = { [attachmentName] = { Limb = "Head", CFrame = CFrame } }?  -- optional, limb-relative
--     Build = function(rig: Blueprints.RigContext) ... end,
--   }
--
-- RIGCONTEXT (passed to Build; everything in studs at scale 1, model space at rest pose:
-- feet on y = 0, facing -Z, right hand on +X; RigBuilder rescales the finished model by rig.Scale)
--   rig.Model: Model              the character being built (physics parts already exist)
--   rig.Id / rig.Family / rig.SkinId / rig.Style
--   rig.Scale: number             FINAL scale (informational: do NOT multiply by it yourself)
--   rig.Palette: {[string]: Color3}  blueprint Palette <- skin palette <- opts.Palette
--   rig.Skeleton                  resolved skeleton (Skeletons.Resolved)
--   rig.Kit: PartKit.Kit          raw kit (scale 1) if you need to build outside a limb
--   rig.Limb(name) -> BasePart    physics part (errors on unknown names)
--   rig.CFrameOf(name) -> CFrame  rest CFrame of a limb (identity rotation)
--   rig.Size(name) -> Vector3     physics size of a limb
--   rig.Joint(motorName) -> Vector3   rest pivot of a Motor6D ("LeftShoulder", "Neck", ...)
--   rig.Color(key, fallback?) -> Color3   palette lookup (errors if missing and no fallback)
--   rig.Add(limb, part) -> part   parent a hand-made part to a limb (string or BasePart) and weld it
--   rig.Attachment(limb, name, worldCF) -> Attachment   create/move an attachment (worldCF = rest pose)
--   rig.Light(limb, kind, props) -> Light
--   rig.Count() -> number         visual parts created so far
--   Bound builders (same arguments as PartKit, but the first argument is the LIMB the parts
--   follow — a limb name or any BasePart already in the rig; parts are parented to it and welded):
--     rig.Box  rig.Ellipsoid  rig.Ball  rig.Cyl  rig.Disc  rig.CylBetween  rig.Wedge  rig.CornerWedge
--     rig.RoundedBox  rig.Cone  rig.Taper  rig.Bone  rig.Ring  rig.Arc  rig.Tube  rig.Dashes
--   Pure helpers: rig.OnEllipsoid, rig.Basis, rig.LookFrame (see PartKit)
-- After Build, RigBuilder welds any visual part left unwelded to its nearest limb ancestor and
-- enforces the visual flags (CanCollide/CanQuery/CanTouch false, Massless, not Anchored, Role).

local PartKit = require(script.Parent.PartKit)
local Skeletons = require(script.Parent.Skeletons)

type Props = PartKit.Props
type LimbRef = string | BasePart

export type RigContext = {
	Model: Model,
	Id: string,
	Family: string,
	SkinId: string,
	Style: string?,
	Scale: number,
	Palette: { [string]: Color3 },
	Skeleton: Skeletons.Resolved,
	Kit: PartKit.Kit,
	Limb: (name: string) -> BasePart,
	CFrameOf: (name: string) -> CFrame,
	Size: (name: string) -> Vector3,
	Joint: (motorName: string) -> Vector3,
	Color: (key: string, fallback: Color3?) -> Color3,
	Add: (limb: LimbRef, part: BasePart) -> BasePart,
	Attachment: (limb: LimbRef, name: string, worldCF: CFrame) -> Attachment,
	Light: (limb: LimbRef, kind: string, props: Props?) -> Light,
	Count: () -> number,
	Box: (limb: LimbRef, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Ellipsoid: (limb: LimbRef, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Ball: (limb: LimbRef, name: string, diameter: number, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	Cyl: (
		limb: LimbRef,
		name: string,
		length: number,
		diameter: number,
		cf: CFrame,
		color: Color3,
		props: Props?
	) -> BasePart,
	Disc: (
		limb: LimbRef,
		name: string,
		diameter: number,
		thickness: number,
		cf: CFrame,
		color: Color3,
		props: Props?
	) -> BasePart,
	CylBetween: (
		limb: LimbRef,
		name: string,
		p0: Vector3,
		p1: Vector3,
		diameter: number,
		color: Color3,
		props: Props?
	) -> BasePart,
	Wedge: (limb: LimbRef, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	CornerWedge: (limb: LimbRef, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?) -> BasePart,
	RoundedBox: (
		limb: LimbRef,
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		radius: number,
		props: Props?
	) -> { BasePart },
	Cone: (
		limb: LimbRef,
		name: string,
		p0: Vector3,
		p1: Vector3,
		d0: number,
		d1: number,
		color: Color3,
		props: Props?
	) -> { BasePart },
	Taper: (
		limb: LimbRef,
		name: string,
		p0: Vector3,
		p1: Vector3,
		d0: number,
		d1: number,
		color: Color3,
		props: Props?
	) -> { BasePart },
	Bone: (
		limb: LimbRef,
		name: string,
		p0: Vector3,
		p1: Vector3,
		thickness: number,
		color: Color3,
		props: Props?
	) -> { BasePart },
	Ring: (
		limb: LimbRef,
		name: string,
		cf: CFrame,
		radius: number,
		count: number,
		ballSize: number,
		color: Color3,
		props: Props?
	) -> { BasePart },
	Arc: (
		limb: LimbRef,
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
	Tube: (
		limb: LimbRef,
		name: string,
		points: { Vector3 },
		diameter: number | { number },
		color: Color3,
		props: Props?
	) -> { BasePart },
	Dashes: (
		limb: LimbRef,
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
}

export type Blueprint = {
	Id: string,
	Family: "Skeleton" | "Human",
	Skeleton: string?,
	Scale: number?,
	Overrides: Skeletons.Overrides?,
	GroundOffset: number?,
	Palette: { [string]: Color3 },
	Anchors: { [string]: { Limb: string, CFrame: CFrame } }?,
	Build: (rig: RigContext) -> (),
}

local Blueprints = {}

Blueprints.KNOWN = {
	"ClassicSans",
	"FellSans",
	"EclipseSans",
	"HumanBase",
	"Determination",
	"Patience",
	"Bravery",
	"Integrity",
	"Perseverance",
	"Kindness",
	"Justice",
	"Dummy",
}

local cache: { [string]: Blueprint } = {}

local function findModule(id: string): Instance?
	local child = (script :: any):FindFirstChild(id)
	if child ~= nil and child:IsA("ModuleScript") then
		return child
	end
	return nil
end

local function validate(id: string, bp: any)
	assert(type(id) == "string", "blueprint id must be a string")
	assert(type(bp) == "table", ("blueprint %s must return a table"):format(id))
	assert(bp.Id == id, ("blueprint module %s has Id %s (must match the module name)"):format(id, tostring(bp.Id)))
	assert(bp.Family == "Skeleton" or bp.Family == "Human", ("blueprint %s: Family must be Skeleton|Human"):format(id))
	assert(type(bp.Build) == "function", ("blueprint %s: Build must be a function"):format(id))
	assert(type(bp.Palette) == "table", ("blueprint %s: Palette must be a table"):format(id))
	local skeletonId = bp.Skeleton or bp.Family
	assert(Skeletons.Get(skeletonId) ~= nil, ("blueprint %s: unknown skeleton %s"):format(id, tostring(skeletonId)))
	if bp.Scale ~= nil then
		assert(type(bp.Scale) == "number" and bp.Scale > 0, ("blueprint %s: Scale must be > 0"):format(id))
	end
	if bp.GroundOffset ~= nil then
		assert(
			type(bp.GroundOffset) == "number" and bp.GroundOffset >= 0,
			("blueprint %s: GroundOffset must be >= 0"):format(id)
		)
	end
end

Blueprints.Validate = validate

function Blueprints.Get(id: string): Blueprint?
	local cached = cache[id]
	if cached then
		return cached
	end
	local module = findModule(id)
	if module == nil then
		return nil
	end
	local ok, result = pcall(require, module :: any)
	if not ok then
		error(("Blueprints: failed to load blueprint %s: %s"):format(id, tostring(result)), 2)
	end
	validate(id, result)
	cache[id] = result :: any
	return result :: any
end

function Blueprints.Has(id: string): boolean
	return findModule(id) ~= nil
end

-- Lists blueprints that exist and load. Helper modules living in this folder (anything whose
-- module does not return a valid blueprint with a matching Id) are skipped.
function Blueprints.List(): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function loads(id: string): boolean
		local ok, bp = pcall(Blueprints.Get, id)
		return ok and bp ~= nil
	end
	for _, id in Blueprints.KNOWN do
		seen[id] = true
		if findModule(id) and loads(id) then
			table.insert(out, id)
		end
	end
	local extras: { string } = {}
	for _, child in (script :: any):GetChildren() do
		if child:IsA("ModuleScript") and not seen[child.Name] and loads(child.Name) then
			table.insert(extras, child.Name)
		end
	end
	table.sort(extras)
	for _, id in extras do
		table.insert(out, id)
	end
	return out
end

return Blueprints
