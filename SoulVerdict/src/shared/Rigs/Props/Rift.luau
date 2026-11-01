--!strict
-- Rift prop: a torn portal in space (Eclipse Sans' Rift Blaster / Rift Trap). [Lune-safe]
-- A jagged, slightly tall elliptical Neon rim (two layers: hot inner edge + translucent outer glow),
-- a void-black interior with a faint spiral, and crystalline shards drifting around the tear.
-- Built standing in the XY plane facing -Z at the origin; lay it flat for traps
-- (model:PivotTo(cf * CFrame.Angles(-math.pi / 2, 0, 0))).
--
-- API
--   Rift.Build(color: Color3?, radius: number?) -> Model
--        color defaults to Eclipse violet; radius (default 3) = mean rim radius in studs.
--        PrimaryPart "Void" (the dark interior disc). Parts "Rim<i>" (Role "Glow", hot edge),
--        "Aura<i>" (translucent outer glow), "Swirl<i>" (interior spiral), "Shard<i>" (Role "Accent").
--        PointLight "Glow" in Void. Attributes: PropId, Radius, PartCount.
--   Rift.SetOpen(model, alpha: number)   0 = sealed slit .. 1 = fully open (scales the tear in X/Y
--        about the centre; pure instance edits, uses the stored rest layout)

local Props = require(script.Parent)

local Rift = {}

local NEON = Enum.Material.Neon
local DEFAULT = Color3.fromRGB(139, 61, 255)
local RIM_SEGMENTS = 18
local AURA_SEGMENTS = 12

-- Jagged tear outline: unit-ish radius with a few deterministic harmonics, taller than wide.
local function outline(theta: number, R: number): Vector3
	local r = R * (1 + 0.1 * math.sin(theta * 5 + 0.6) + 0.05 * math.sin(theta * 11 + 2.1))
	return Vector3.new(math.cos(theta) * r * 0.78, math.sin(theta) * r * 1.12, 0)
end

local function ring(
	kit: any,
	parent: Instance,
	name: string,
	n: number,
	R: number,
	thickness: number,
	depth: number,
	color: Color3,
	props: any
)
	for i = 1, n do
		local a0 = (i - 1) / n * math.pi * 2
		local a1 = i / n * math.pi * 2
		local p0, p1 = outline(a0, R), outline(a1, R)
		local dir = p1 - p0
		local x = dir.Unit
		local z = Vector3.new(0, 0, 1)
		local y = z:Cross(x)
		local cf = CFrame.fromMatrix((p0 + p1) / 2, x, y, z)
		kit.Box(parent, name .. i, Vector3.new(dir.Magnitude + thickness * 0.7, thickness, depth), cf, color, props)
	end
end

function Rift.Build(color: Color3?, radius: number?): Model
	local c = color or DEFAULT
	local R = radius or 3
	local kit = Props.Kit(1)
	local model = Props.NewModel("Rift", "Rift")
	local hot = c:Lerp(Color3.new(1, 1, 1), 0.55)

	local void =
		kit.Ellipsoid(model, "Void", Vector3.new(R * 1.62, R * 2.3, 0.08), CFrame.new(), Color3.fromRGB(6, 3, 14), {
			Role = "Dark",
			Material = NEON,
			CastShadow = false,
		})
	ring(kit, model, "Rim", RIM_SEGMENTS, R, 0.22, 0.2, hot, { Role = "Glow", Material = NEON, CastShadow = false })
	ring(kit, model, "Aura", AURA_SEGMENTS, R * 1.06, 0.6, 0.1, c, {
		Role = "Glow",
		Material = NEON,
		Transparency = 0.55,
		CastShadow = false,
	})
	-- vortex inside the void: three continuous log-spiral arms (joined box segments)
	local swirl = { Role = "Glow", Material = NEON, Transparency = 0.3, CastShadow = false }
	local function spiral(arm: number, t: number): Vector3
		local a = arm * math.pi * 2 / 3 + t * 3.4
		local r = R * (0.8 - 0.62 * t)
		return Vector3.new(math.cos(a) * r * 0.78, math.sin(a) * r * 1.12, -0.06)
	end
	local k = 0
	for arm = 0, 2 do
		for j = 0, 3 do
			k += 1
			local p0, p1 = spiral(arm, j / 4), spiral(arm, (j + 1) / 4)
			local dir = p1 - p0
			local x = dir.Unit
			local z = Vector3.new(0, 0, 1)
			local y = z:Cross(x)
			local width = 0.12 - j * 0.02
			kit.Box(
				model,
				"Swirl" .. k,
				Vector3.new(dir.Magnitude + width * 0.8, width, 0.04),
				CFrame.fromMatrix((p0 + p1) / 2, x, y, z),
				c:Lerp(hot, 0.2 + j * 0.15),
				swirl
			)
		end
	end
	-- crystalline shards drifting around the tear
	local shard = { Role = "Accent", Material = NEON, CastShadow = false }
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2 + 0.4
		local p = outline(a, R * 1.32) + Vector3.new(0, 0, (i % 2 - 0.5) * 0.5)
		local size = 0.3 + (i % 3) * 0.12
		local cf = CFrame.new(p) * CFrame.Angles(i * 0.7, i * 1.3, a)
		kit.Wedge(model, "Shard" .. i, Vector3.new(0.08, size, size * 0.6), cf, if i % 2 == 0 then hot else c, shard)
	end
	kit.Light(void, "Point", { Name = "Glow", Color = c, Brightness = 2, Range = R * 4 })

	-- rest layout (relative to Void) for SetOpen
	local inv = void.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("RiftRest", inv * d.CFrame)
			d:SetAttribute("RiftSize", d.Size)
		end
	end
	model:SetAttribute("Radius", R)
	return Props.Finish(model, void)
end

function Rift.SetOpen(model: Model, alpha: number)
	local void = model.PrimaryPart
	if void == nil then
		return
	end
	local a = math.clamp(alpha, 0, 1.2)
	local sx, sy = 0.08 + 0.92 * a, 0.35 + 0.65 * a -- opens from a thin vertical slit
	local base = void.CFrame
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rest = d:GetAttribute("RiftRest")
			local size = d:GetAttribute("RiftSize")
			if typeof(rest) == "CFrame" and typeof(size) == "Vector3" then
				local p = rest.Position
				if d ~= void then
					d.CFrame = base * CFrame.new(p.X * sx, p.Y * sy, p.Z) * rest.Rotation
				end
				local k = math.max(math.min(sx, sy), 0.05)
				d.Size = if d == void then Vector3.new(size.X * sx, size.Y * sy, size.Z) else size * (0.5 + 0.5 * k)
			end
		end
	end
	model:SetAttribute("Open", a)
end

return Rift
