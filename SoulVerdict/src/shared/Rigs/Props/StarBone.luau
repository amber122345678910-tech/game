--!strict
-- StarBone prop: Eclipse Sans' Starfall projectile - a pale bone riding a violet/cyan falling star.
-- [Lune-safe]
-- The bone flies point-first along -Z: a glowing 3D twinkle (three crossed diamonds + a hot core) at
-- the nose, the bone behind it, and a two-layer comet tail streaming back (+Z). Built at the origin
-- (the star core), so PivotTo(CFrame.lookAt(pos, pos + velocity)) style placement just works.
--
-- API
--   StarBone.Build(scale: number?, color: Color3?) -> Model
--        PrimaryPart "Star" (core, Role "Glow"). Parts: "Ray1..3" (twinkle), "Shaft", "Knob*" (bone),
--        "Tail", "TailCore" (translucent Neon). PointLight "Glow" in Star. Attributes: PropId, Scale,
--        PartCount. ~12 parts.

local Props = require(script.Parent)

local StarBone = {}

local NEON = Enum.Material.Neon
local VIOLET = Color3.fromRGB(139, 61, 255)
local CYAN = Color3.fromRGB(125, 249, 255)
local BONE = Color3.fromRGB(236, 235, 244)

function StarBone.Build(scale: number?, color: Color3?): Model
	local s = scale or 1
	local tint = color or VIOLET
	local kit = Props.Kit(s)
	local model = Props.NewModel("StarBone", "StarBone")
	local glow = { Role = "Glow", Material = NEON, CastShadow = false }

	local star = kit.Ball(model, "Star", 0.62, CFrame.new(), Color3.fromRGB(235, 252, 255), glow)
	-- twinkle: three long thin diamonds along X, Y and the flight axis
	kit.Box(model, "Ray1", Vector3.new(1.7, 0.12, 0.12), CFrame.new() * CFrame.Angles(math.pi / 4, 0, 0), CYAN, glow)
	kit.Box(model, "Ray2", Vector3.new(0.12, 1.7, 0.12), CFrame.new() * CFrame.Angles(0, math.pi / 4, 0), CYAN, glow)
	kit.Box(model, "Ray3", Vector3.new(0.1, 0.1, 1.15), CFrame.new(0, 0, -0.1) * CFrame.Angles(0, 0, math.pi / 4), tint:Lerp(CYAN, 0.5), glow)
	-- the bone trailing behind the star (axis along Z)
	local len, t = 2.5, 0.3
	local z0, z1 = 0.45, 0.45 + len
	local bone = { Role = "Bone", Material = Enum.Material.SmoothPlastic }
	kit.Cyl(model, "Shaft", z1 - z0 - 0.3, t, CFrame.new(0, 0, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0), BONE, bone)
	for i, k in { { -1, z0 + 0.15 }, { 1, z0 + 0.15 }, { -1, z1 - 0.15 }, { 1, z1 - 0.15 } } do
		kit.Ball(model, "Knob" .. i, t * 1.35, CFrame.new(k[1] * t * 0.42, 0, k[2]), BONE, bone)
	end
	-- comet tail
	kit.Ellipsoid(model, "Tail", Vector3.new(1.05, 1.05, 4.6), CFrame.new(0, 0, 2.1), tint, {
		Role = "Glow",
		Material = NEON,
		Transparency = 0.62,
		CastShadow = false,
	})
	kit.Ellipsoid(model, "TailCore", Vector3.new(0.42, 0.42, 3.2), CFrame.new(0, 0, 1.45), CYAN, {
		Role = "Glow",
		Material = NEON,
		Transparency = 0.35,
		CastShadow = false,
	})
	kit.Light(star, "Point", { Name = "Glow", Color = tint:Lerp(CYAN, 0.4), Brightness = 2.4, Range = 10 })
	model:SetAttribute("Scale", s)
	return Props.Finish(model, star)
end

return StarBone
