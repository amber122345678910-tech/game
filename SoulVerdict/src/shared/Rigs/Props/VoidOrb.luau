--!strict
-- VoidOrb prop: Eclipse Sans' "black star" (Gravity Well). [Lune-safe]
-- An eclipse in a bottle: a pitch-black void sphere ringed by a razor-thin white-cyan corona, a wider
-- translucent violet glow ring, eight flare rays fanning out behind it and a tilted violet/cyan
-- accretion disc. The corona sits in the XY plane facing -Z: turn the model towards the camera for the
-- full eclipse look (the disc keeps it readable from any angle). Built at the origin, diameter ~2 x scale.
--
-- API
--   VoidOrb.Build(scale: number?, color: Color3?) -> Model
--        PrimaryPart "Core" (void sphere, Role "Dark"). Parts "Corona<i>" (hot rim), "Glow<i>"
--        (translucent ring), "Ray<i>" (flares), "Disc<i>" (accretion disc, its own tilt). PointLight
--        "Glow" in Core. Attributes: PropId, Scale, PartCount.
--   VoidOrb.SetPulse(model, k: number)   0..1 brightens the corona/rays (charge/implode beats)

local Props = require(script.Parent)
local PartKit = require(script.Parent.Parent.PartKit)

local VoidOrb = {}

local NEON = Enum.Material.Neon
local VIOLET = Color3.fromRGB(139, 61, 255)
local CYAN = Color3.fromRGB(125, 249, 255)
local HALO = Color3.fromRGB(205, 240, 255)

-- Box segments around a circle in `frame`'s XY plane.
local function circle(
	kit: any,
	parent: Instance,
	name: string,
	frame: CFrame,
	n: number,
	r: number,
	thickness: number,
	depth: number,
	color: (number) -> Color3,
	props: any
)
	local chord = 2 * r * math.sin(math.pi / n)
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi * 2
		local cf = frame * CFrame.Angles(0, 0, a) * CFrame.new(r, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
		kit.Box(parent, name .. i, Vector3.new(chord + thickness * 0.6, thickness, depth), cf, color(i), props)
	end
end

function VoidOrb.Build(scale: number?, color: Color3?): Model
	local s = scale or 1
	local tint = color or VIOLET
	local kit = Props.Kit(s)
	local model = Props.NewModel("VoidOrb", "VoidOrb")

	local core = kit.Ball(model, "Core", 2, CFrame.new(), Color3.fromRGB(4, 2, 10), {
		Role = "Dark",
		Material = NEON,
		CastShadow = false,
	})
	local glow = { Role = "Glow", Material = NEON, CastShadow = false }
	-- corona: razor-thin hot rim hugging the silhouette
	circle(kit, model, "Corona", CFrame.new(0, 0, 0.05), 18, 1.03, 0.09, 0.08, function(i)
		return if i % 3 == 0 then CYAN else HALO
	end, glow)
	-- translucent violet glow ring
	circle(kit, model, "Glow", CFrame.new(0, 0, 0.12), 12, 1.24, 0.34, 0.05, function()
		return tint
	end, { Role = "Glow", Material = NEON, Transparency = 0.45, CastShadow = false })
	-- flare rays behind the disc (alternating long/short, like a corona photograph)
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2 + math.pi / 8
		local long = i % 2 == 1
		local len = if long then 1.5 else 0.95
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local mid = dir * (1.0 + len * 0.42)
		local cf = PartKit.LookFrame(mid + Vector3.new(0, 0, 0.18), dir, Vector3.new(0, 0, 1))
		kit.Ellipsoid(
			model,
			"Ray" .. i,
			Vector3.new(0.16, 0.1, len),
			cf,
			if long then tint:Lerp(CYAN, 0.25) else tint,
			{
				Role = "Glow",
				Material = NEON,
				Transparency = if long then 0.15 else 0.3,
				CastShadow = false,
			}
		)
	end
	-- tilted accretion disc (reads from the side and from above)
	local discFrame = CFrame.Angles(math.rad(72), 0, math.rad(-18))
	circle(kit, model, "Disc", discFrame, 16, 1.62, 0.26, 0.05, function(i)
		return if i % 2 == 0 then tint else tint:Lerp(CYAN, 0.6)
	end, { Role = "Glow", Material = NEON, Transparency = 0.2, CastShadow = false })

	kit.Light(core, "Point", { Name = "Glow", Color = tint, Brightness = 2.2, Range = 16 })
	model:SetAttribute("Scale", s)
	return Props.Finish(model, core)
end

function VoidOrb.SetPulse(model: Model, k: number)
	local t = math.clamp(k, 0, 1)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = d.Name
			if string.sub(n, 1, 3) == "Ray" then
				local base = d:GetAttribute("BaseT")
				if type(base) ~= "number" then
					base = d.Transparency
					d:SetAttribute("BaseT", base)
				end
				d.Transparency = (base :: number) * (1 - t)
			elseif string.sub(n, 1, 4) == "Glow" then
				d.Transparency = 0.45 - 0.3 * t
			end
		elseif d:IsA("PointLight") then
			d.Brightness = 2.2 + 2.5 * t
		end
	end
	model:SetAttribute("Pulse", t)
end

return VoidOrb
