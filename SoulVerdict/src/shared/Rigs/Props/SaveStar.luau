--!strict
-- SaveStar prop: the glowing yellow SAVE star objective (SPEC section 1.4 / 5.3). [Lune-safe]
-- A chunky 5-point Neon star (gold rim around a white-hot core star) facing -Z, a soft halo, four
-- twinkling 4-point sparkles and a horizontal ring of progress segments around it (Saturn-style, so
-- it reads from any camera yaw). One PointLight ("Glow", the only light: ObjectiveService finds and
-- drives it). Built at the origin = star centre; ~55 parts, all Anchored and non-interactive.
--
-- API
--   SaveStar.Build(scale: number?) -> Model
--        PrimaryPart "Star" (the core disc). Parts: "Star", "RimDisc", "Rim*"/"Core*" point wedges,
--        "Halo", "Sparkle<i>a/b". Child Model "ProgressRing" holds parts "Seg01".."Seg24" (attribute
--        Index 1..24, clockwise from the front when seen from above). Model attributes: PropId,
--        RingSegments (24), PartCount, Scale.
--   SaveStar.SetProgress(model, progress: number, contested: boolean?, lit: boolean?)
--        client-side visual update (pure instance edits; cheap, call on attribute change):
--        progress 0..1 fills segments in order (the partially filled segment glows dimmer);
--        contested = monster inside: filled segments turn warning red, the star dims;
--        lit = SAVE complete: every segment and the star go bright white-gold.
--        Does NOT touch the PointLight (ObjectiveService owns it on the server).
--   SaveStar.Preview(progress?, contested?, lit?) -> Model   Build + SetProgress (galleries)
--   SaveStar.Colors = { Gold, Core, Lit, Empty, Contested, Partial }

local Props = require(script.Parent)

local SaveStar = {}

SaveStar.Colors = {
	Gold = Color3.fromRGB(255, 205, 52),
	Core = Color3.fromRGB(255, 238, 150),
	Lit = Color3.fromRGB(255, 248, 222),
	Empty = Color3.fromRGB(58, 56, 74),
	Contested = Color3.fromRGB(255, 70, 58),
	Partial = Color3.fromRGB(196, 150, 40),
}

local SEGMENTS = 24
local OUTER = 1.35 -- star tip radius
local INNER = 0.6 -- star valley radius (chunky, cartoon star)
local RIM_T = 0.26 -- rim star thickness
local CORE_SCALE = 0.5
local CORE_T = 0.4 -- the core star bulges out front and back
local RING_R = 2.25
local NEON = Enum.Material.Neon

-- One star point (tip + its two valley vertices) as two wedges, in the XY plane of `frame`.
local function point(
	kit: any,
	parent: Instance,
	name: string,
	k: number,
	outer: number,
	inner: number,
	thickness: number,
	z: number,
	color: Color3,
	props: any
)
	local function polar(r: number, deg: number): Vector3
		local a = math.rad(deg)
		return Vector3.new(math.cos(a) * r, math.sin(a) * r, z)
	end
	local tipDeg = 90 + 72 * k
	local tip = polar(outer, tipDeg)
	local left = polar(inner, tipDeg - 36)
	local right = polar(inner, tipDeg + 36)
	Props.Triangle(kit, parent, name, tip, left, right, thickness, color, props)
end

function SaveStar.Build(scale: number?): Model
	local s = scale or 1
	local kit = Props.Kit(s)
	local model = Props.NewModel("SaveStar", "SaveStar")
	local glow = { Role = "Glow", Material = NEON, CastShadow = false }
	local C = SaveStar.Colors

	-- core (PrimaryPart): disc covering the inner pentagon of the core star, white-hot
	local core = kit.Disc(model, "Star", INNER * CORE_SCALE * 2, CORE_T, CFrame.new(), C.Core, glow)
	for k = 0, 4 do
		point(kit, model, "Core" .. k, k, OUTER * CORE_SCALE, INNER * CORE_SCALE, CORE_T, 0, C.Core, glow)
	end
	-- gold rim star around it
	kit.Disc(model, "RimDisc", INNER * 2, RIM_T, CFrame.new(), C.Gold, glow)
	for k = 0, 4 do
		point(kit, model, "Rim" .. k, k, OUTER, INNER, RIM_T, 0, C.Gold, glow)
	end
	-- faint halo ring behind the star (bloom does the rest)
	kit.Disc(model, "Halo", OUTER * 1.55, 0.03, CFrame.new(0, 0, 0.16), C.Gold, {
		Role = "Glow",
		Material = NEON,
		Transparency = 0.93,
		CastShadow = false,
	})
	-- 4-point sparkles (two crossed thin diamonds each)
	local sparkles = {
		{ Vector3.new(1.55, 1.25, -0.1), 0.42 },
		{ Vector3.new(-1.7, 0.55, 0.15), 0.3 },
		{ Vector3.new(1.25, -1.3, 0.1), 0.26 },
		{ Vector3.new(-1.05, -1.55, -0.15), 0.34 },
	}
	for i, sp in sparkles do
		local pos, len = sp[1] :: Vector3, sp[2] :: number
		local cf = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 4)
		local props = { Role = "Glow", Material = NEON, CastShadow = false, Attributes = { Sparkle = i } }
		-- a long thin diamond = a square block squashed along one diagonal
		kit.Box(model, "Sparkle" .. i .. "a", Vector3.new(len * 0.2, len * 0.2, 0.04), cf, C.Core, props)
		kit.Box(
			model,
			"Sparkle" .. i .. "b",
			Vector3.new(len * 0.08, len * 0.72, 0.04),
			CFrame.new(pos),
			C.Core,
			props
		)
		kit.Box(
			model,
			"Sparkle" .. i .. "c",
			Vector3.new(len * 0.72, len * 0.08, 0.04),
			CFrame.new(pos),
			C.Core,
			props
		)
	end
	-- progress ring: horizontal, segments clockwise from the front (-Z) seen from above
	local ring = Instance.new("Model")
	ring.Name = "ProgressRing"
	local step = 360 / SEGMENTS
	local chord = 2 * RING_R * math.sin(math.rad(step / 2))
	for i = 1, SEGMENTS do
		local deg = (i - 0.5) * step
		local a = math.rad(deg)
		-- clockwise from above: start at -Z, move towards +X
		local pos = Vector3.new(math.sin(a) * RING_R, 0, -math.cos(a) * RING_R)
		local cf = CFrame.new(pos) * CFrame.Angles(0, -a, 0)
		kit.Box(ring, ("Seg%02d"):format(i), Vector3.new(chord * 0.78, 0.09, 0.2), cf, C.Empty, {
			Role = "Glow",
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.3,
			CastShadow = false,
			Attributes = { Index = i },
		})
	end
	ring.Parent = model

	kit.Light(core, "Point", { Name = "Glow", Color = C.Gold, Brightness = 1.4, Range = 14 })
	model:SetAttribute("RingSegments", SEGMENTS)
	model:SetAttribute("Scale", s)
	Props.Finish(model, core)
	SaveStar.SetProgress(model, 0, false, false)
	return model
end

-- Built + SetProgress in one call (galleries, previews).
function SaveStar.Preview(progress: number?, contested: boolean?, lit: boolean?): Model
	local model = SaveStar.Build()
	SaveStar.SetProgress(model, progress or 0, contested, lit)
	return model
end

function SaveStar.SetProgress(model: Model, progress: number, contested: boolean?, lit: boolean?)
	local C = SaveStar.Colors
	local p = math.clamp(progress, 0, 1)
	local ring = model:FindFirstChild("ProgressRing")
	if ring then
		local n = 0
		for _, seg in ring:GetChildren() do
			if seg:IsA("BasePart") then
				n += 1
			end
		end
		local fill = p * n
		for _, seg in ring:GetChildren() do
			if seg:IsA("BasePart") then
				local idx = seg:GetAttribute("Index")
				local i = if type(idx) == "number" then idx else 0
				local color, transparency, material = C.Empty, 0.3, Enum.Material.SmoothPlastic
				if lit then
					color, transparency, material = C.Lit, 0, NEON
				elseif i <= fill then
					color, transparency, material = if contested then C.Contested else C.Gold, 0, NEON
				elseif i - 1 < fill then
					-- partially filled segment
					color, transparency, material = if contested then C.Contested else C.Partial, 0.25, NEON
				elseif contested then
					color = C.Empty:Lerp(C.Contested, 0.35)
				end
				seg.Color = color
				seg.Transparency = transparency
				seg.Material = material
			end
		end
	end
	-- star body: dimmer while contested, white-gold once lit
	local rim = if lit then C.Lit else if contested then C.Gold:Lerp(C.Contested, 0.3) else C.Gold
	local coreColor = if lit then Color3.fromRGB(255, 252, 235) else C.Core
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local name = d.Name
			if name == "RimDisc" or string.sub(name, 1, 3) == "Rim" then
				d.Color = rim
			elseif name == "Star" or string.sub(name, 1, 4) == "Core" then
				d.Color = coreColor
			elseif name == "Halo" then
				d.Color = rim
				d.Transparency = if lit then 0.86 else 0.93
			end
		end
	end
	model:SetAttribute("VisualProgress", p)
end

return SaveStar
