--!strict
-- Soul prop: the Undertale SOUL heart in 3D (Neon), its broken halves and shatter shards. [Lune-safe]
-- Proportions follow the 16x16 battle sprite (docs/research/undertale.md section 6): two round lobes
-- that meet in a notch, straight full-width sides, then a 45-degree V to the tip. The heart is a crisp
-- flat extrusion (like a glowing sign) so the silhouette reads perfectly from the front (-Z) and stays
-- solid from the side. size = overall width in studs (height = 1.05 x width), centred on the origin.
--
-- API
--   Soul.Build(color: Color3, size: number?) -> Model
--        PrimaryPart "Core" (the full-width band); parts LobeL, LobeR (round lobes flattened to the
--        slab depth), TipL, TipR (wedges); PointLight "Glow" in Core (Range ~ 7 x size). Role "Glow".
--   Soul.BuildBroken(color: Color3, size: number?) -> Model
--        child Models "LeftHalf" / "RightHalf" split along the iconic zig-zag crack (they interlock
--        when unmoved). Each half's PrimaryPart is its lobe, with a PivotOffset that puts the half's
--        pivot at the heart centre; the outer model's PrimaryPart is LeftHalf's lobe (same pivot).
--   Soul.Shards(color: Color3, size: number?, n: number?, seed: number?) -> {BasePart}
--        n (default 6) small triangular Neon shards (single WedgeParts), unparented, positioned in
--        heart-local space (origin = heart centre, facing -Z) inside the heart outline. Move them with
--        shard.CFrame = heartCFrame * shard.CFrame, then fling them. Attribute "Shard" = index.
--   Soul.Outline(size: number?) -> {Vector2}   the heart outline polygon (front view, CCW)

local Props = require(script.Parent)
local Rng = require(script.Parent.Parent.Parent.Util.Rng)

local Soul = {}

-- Geometry at width 1 (front view, X right, Y up), bounding box centred on the origin.
local W = 1
local H = 1.05
local TOP = H / 2
local LOBE_R = 0.25 * W
local Y_C = TOP - LOBE_R -- lobe centre line (the notch cusp)
local Y_V = Y_C - 0.3 -- start of the V
local Y_TIP = -H / 2
local DEPTH = 0.36 -- slab thickness (front-to-back) at width 1

local NEON = Enum.Material.Neon

local function glowProps(): any
	return { Role = "Glow", Material = NEON, CastShadow = false }
end

-- A lobe: a disc ("ball" flattened to the slab depth, so its front face is flush with the band and
-- the outline stays exact under perspective).
local function lobe(kit: any, parent: Instance, name: string, x: number, color: Color3): BasePart
	return kit.Disc(parent, name, LOBE_R * 2, DEPTH, CFrame.new(x, Y_C, 0), color, glowProps())
end

function Soul.Build(color: Color3, size: number?): Model
	local s = size or 1
	local kit = Props.Kit(s)
	local model = Props.NewModel("Soul", "Soul")
	local core = kit.Box(
		model,
		"Core",
		Vector3.new(W, Y_C - Y_V, DEPTH),
		CFrame.new(0, (Y_C + Y_V) / 2, 0),
		color,
		glowProps()
	)
	lobe(kit, model, "LobeL", -0.25, color)
	lobe(kit, model, "LobeR", 0.25, color)
	-- the V: two right-triangle wedges sharing the vertical leg on the centre line
	local f = Vector3.new(0, Y_V, 0)
	local tip = Vector3.new(0, Y_TIP, 0)
	local tl = Props.Triangle(kit, model, "TipL", tip, f, Vector3.new(-W / 2, Y_V, 0), DEPTH, color, glowProps())
	local tr = Props.Triangle(kit, model, "TipR", tip, f, Vector3.new(W / 2, Y_V, 0), DEPTH, color, glowProps())
	tl[1].Name = "TipL"
	tr[1].Name = "TipR"
	kit.Light(core, "Point", { Name = "Glow", Color = color, Brightness = 1.6, Range = 7 })
	model:SetAttribute("Size", s)
	return Props.Finish(model, core)
end

-- Heart outline (front view), CCW starting at the right end of the band.
function Soul.Outline(size: number?): { Vector2 }
	local s = size or 1
	local pts: { Vector2 } = {}
	local function add(x: number, y: number)
		table.insert(pts, Vector2.new(x * s, y * s))
	end
	add(0.5, Y_V)
	for i = 0, 8 do -- right lobe, from the outer side over the top to the notch
		local a = math.rad(i * 22.5)
		add(0.25 + math.cos(a) * LOBE_R, Y_C + math.sin(a) * LOBE_R)
	end
	for i = 0, 8 do
		local a = math.rad(i * 22.5)
		add(-0.25 + math.cos(a) * LOBE_R, Y_C + math.sin(a) * LOBE_R)
	end
	add(-0.5, Y_V)
	add(0, Y_TIP)
	return pts
end

-- Zig-zag crack from the notch to the tip (top to bottom), shared by both halves.
local CRACK: { Vector2 } = {
	Vector2.new(0, Y_C),
	Vector2.new(0.085, Y_C - 0.1),
	Vector2.new(-0.07, Y_C - 0.22),
	Vector2.new(0.075, Y_V - 0.05),
	Vector2.new(-0.045, Y_V - 0.2),
	Vector2.new(0.02, Y_V - 0.36),
	Vector2.new(0, Y_TIP),
}

local function half(parent: Model, kit: any, color: Color3, side: number, s: number): Model
	local model = Instance.new("Model")
	model.Name = if side < 0 then "LeftHalf" else "RightHalf"
	-- polygon: outer corner at the lobe line -> outer V start -> tip -> crack (bottom to top) -> notch
	local pts: { Vector2 } = {}
	table.insert(pts, Vector2.new(side * 0.5, Y_C))
	table.insert(pts, Vector2.new(side * 0.5, Y_V))
	for i = #CRACK, 1, -1 do
		table.insert(pts, CRACK[i])
	end
	Props.Polygon(kit, model, "Body", pts, CFrame.new(), DEPTH, color, glowProps())
	local disc = lobe(kit, model, "Lobe", side * 0.25, color)
	-- pivot at the heart centre (the disc is rotated: express the offset in its own frame)
	disc.PivotOffset = disc.CFrame:Inverse() * CFrame.new()
	model.PrimaryPart = disc
	model.Parent = parent
	return model
end

function Soul.BuildBroken(color: Color3, size: number?): Model
	local s = size or 1
	local kit = Props.Kit(s)
	local model = Props.NewModel("SoulBroken", "Soul")
	local left = half(model, kit, color, -1, s)
	half(model, kit, color, 1, s)
	model:SetAttribute("Size", s)
	return Props.Finish(model, left.PrimaryPart :: BasePart)
end

-- Uniform point inside the heart (rejection sampling against the outline pieces).
local function insideHeart(x: number, y: number): boolean
	if y > Y_C then
		return (Vector2.new(x, y) - Vector2.new(-0.25, Y_C)).Magnitude <= LOBE_R
			or (Vector2.new(x, y) - Vector2.new(0.25, Y_C)).Magnitude <= LOBE_R
	elseif y >= Y_V then
		return math.abs(x) <= 0.5
	elseif y >= Y_TIP then
		return math.abs(x) <= (y - Y_TIP) / (Y_V - Y_TIP) * 0.5
	end
	return false
end

function Soul.Shards(color: Color3, size: number?, n: number?, seed: number?): { BasePart }
	local s = size or 1
	local count = math.max(1, math.floor(n or 6))
	local kit = Props.Kit(s)
	local rng = Rng.new(seed or 7)
	local out: { BasePart } = {}
	for i = 1, count do
		local x, y = 0, 0
		for _ = 1, 30 do
			x, y = rng:Number(-0.5, 0.5), rng:Number(Y_TIP, TOP)
			if insideHeart(x, y) then
				break
			end
		end
		local a = rng:Number(0.13, 0.24)
		local b = rng:Number(0.1, 0.2)
		local cf = CFrame.new(x, y, 0)
			* CFrame.Angles(0, 0, rng:Number(0, math.pi * 2))
			* CFrame.Angles(0, math.pi / 2, 0) -- wedge triangle faces the front
		local shard = kit.Wedge(nil, "Shard" .. i, Vector3.new(DEPTH * 0.7, a, b), cf, color, glowProps())
		shard:SetAttribute("Shard", i)
		table.insert(out, shard)
	end
	return out
end

return Soul
