--!strict
-- VerdictBox3D prop: the floating 3D battle box spawned above a boxed human (SPEC section 11). [Lune-safe]
-- Undertale's battle box extruded into a chunky cube of smoked black glass with crisp white edges: a
-- thick glowing white border on the front (the 5 px battle-box border), thin white edges elsewhere so
-- the wireframe reads through the glass, two SAVE-like 4-point sparkles, a soft inner light and a
-- downward spotlight that singles out the victim below. Built at the origin (box centre), facing -Z.
--
-- API
--   VerdictBox3D.Build(scale: number?) -> Model
--        PrimaryPart "Body" (the glass cube). Part "Screen": the black front panel (inside the white
--        border) for a SurfaceGui with Face = Front (attributes SurfaceFace "Front", PixelsPerStud 48,
--        ScreenSize Vector2 studs). Edge parts "Edge*" (Role "Trim"), sparkles "Sparkle*" (Role "Glow").
--        Lights: PointLight "Inner" in Body, SpotLight "Down" in Body (Face Bottom).
--        Attributes: PropId, BoxSize (Vector3 studs), PartCount, Scale.
--   VerdictBox3D.Size -> Vector3   box size at scale 1

local Props = require(script.Parent)

local VerdictBox3D = {}

local W, H, D = 7, 7, 2.4
VerdictBox3D.Size = Vector3.new(W, H, D)

local BORDER = 0.24 -- front border width (~5 px of a 165 px box)
local EDGE = 0.09 -- other edges
local WHITE = Color3.fromRGB(236, 241, 255)
local NEON = Enum.Material.Neon

function VerdictBox3D.Build(scale: number?): Model
	local s = scale or 1
	local kit = Props.Kit(s)
	local model = Props.NewModel("VerdictBox3D", "VerdictBox3D")

	local body = kit.Box(model, "Body", Vector3.new(W, H, D), CFrame.new(), Color3.fromRGB(6, 6, 12), {
		Role = "Dark",
		Material = Enum.Material.Glass,
		Transparency = 0.32,
		Reflectance = 0.18,
		CastShadow = false,
	})
	-- front screen panel (SurfaceGui target), just proud of the glass
	local sw, sh = W - BORDER * 2, H - BORDER * 2
	local screen = kit.Box(model, "Screen", Vector3.new(sw, sh, 0.06), CFrame.new(0, 0, -D / 2 - 0.035), Color3.new(0, 0, 0), {
		Role = "Dark",
		Material = Enum.Material.SmoothPlastic,
		CastShadow = false,
	})
	screen:SetAttribute("SurfaceFace", "Front")
	screen:SetAttribute("PixelsPerStud", 48)
	screen:SetAttribute("ScreenSize", Vector2.new(sw * s, sh * s))

	-- front border: thick glowing white frame
	local front = { Role = "Trim", Material = NEON, CastShadow = false }
	local zf = -D / 2 - 0.04
	kit.Box(model, "EdgeFrontTop", Vector3.new(W, BORDER, 0.14), CFrame.new(0, H / 2 - BORDER / 2, zf), WHITE, front)
	kit.Box(model, "EdgeFrontBottom", Vector3.new(W, BORDER, 0.14), CFrame.new(0, -H / 2 + BORDER / 2, zf), WHITE, front)
	kit.Box(model, "EdgeFrontLeft", Vector3.new(BORDER, H - BORDER * 2, 0.14), CFrame.new(-W / 2 + BORDER / 2, 0, zf), WHITE, front)
	kit.Box(model, "EdgeFrontRight", Vector3.new(BORDER, H - BORDER * 2, 0.14), CFrame.new(W / 2 - BORDER / 2, 0, zf), WHITE, front)
	-- back frame + depth edges: thin crisp white
	local thin = { Role = "Trim", Material = Enum.Material.SmoothPlastic, CastShadow = false }
	local zb = D / 2
	kit.Box(model, "EdgeBackTop", Vector3.new(W, EDGE, EDGE), CFrame.new(0, H / 2 - EDGE / 2, zb - EDGE / 2), WHITE, thin)
	kit.Box(model, "EdgeBackBottom", Vector3.new(W, EDGE, EDGE), CFrame.new(0, -H / 2 + EDGE / 2, zb - EDGE / 2), WHITE, thin)
	kit.Box(model, "EdgeBackLeft", Vector3.new(EDGE, H, EDGE), CFrame.new(-W / 2 + EDGE / 2, 0, zb - EDGE / 2), WHITE, thin)
	kit.Box(model, "EdgeBackRight", Vector3.new(EDGE, H, EDGE), CFrame.new(W / 2 - EDGE / 2, 0, zb - EDGE / 2), WHITE, thin)
	for _, c in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local x, y = c[1] * (W / 2 - EDGE / 2), c[2] * (H / 2 - EDGE / 2)
		kit.Box(model, ("EdgeDepth%s%s"):format(if c[1] < 0 then "L" else "R", if c[2] < 0 then "B" else "T"),
			Vector3.new(EDGE, EDGE, D), CFrame.new(x, y, 0), WHITE, thin)
	end

	-- SAVE-like sparkles at two corners (4-point: a diamond core and two long thin rays)
	local sparkles = {
		{ Vector3.new(-W / 2 - 0.15, H / 2 + 0.2, zf - 0.1), 1.1 },
		{ Vector3.new(W / 2 + 0.25, -H / 2 + 0.6, zf - 0.1), 0.75 },
	}
	for i, sp in sparkles do
		local pos, len = sp[1] :: Vector3, sp[2] :: number
		local sparkleProps = { Role = "Glow", Material = NEON, CastShadow = false, Attributes = { Sparkle = i } }
		kit.Box(model, "Sparkle" .. i .. "a", Vector3.new(len * 0.2, len * 0.2, 0.05),
			CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 4), WHITE, sparkleProps)
		kit.Box(model, "Sparkle" .. i .. "b", Vector3.new(len * 0.07, len, 0.04), CFrame.new(pos), WHITE, sparkleProps)
		kit.Box(model, "Sparkle" .. i .. "c", Vector3.new(len, len * 0.07, 0.04), CFrame.new(pos), WHITE, sparkleProps)
	end

	kit.Light(body, "Point", { Name = "Inner", Color = Color3.fromRGB(220, 230, 255), Brightness = 0.7, Range = 12 })
	kit.Light(body, "Spot", {
		Name = "Down",
		Color = Color3.fromRGB(235, 240, 255),
		Brightness = 2.2,
		Range = 18,
		Angle = 55,
		Face = Enum.NormalId.Bottom,
	})
	model:SetAttribute("BoxSize", VerdictBox3D.Size * s)
	model:SetAttribute("Scale", s)
	return Props.Finish(model, body)
end

return VerdictBox3D
