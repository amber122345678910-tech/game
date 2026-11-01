--!strict
-- GiantBook prop: Perseverance's ultimate - a huge torn notebook that hovers open over the monster and
-- slams shut. [Lune-safe]
-- Purple cloth covers with gold corners and a glowing violet fore-edge, thick cream page blocks with
-- ruled lines and a red margin, a ribbon bookmark and a spine with gold bands. The spine runs along Z
-- at the origin; covers are child Models "LeftCover" / "RightCover" hinged on the spine edges.
-- Open (alpha 1): both covers lie flat, pages facing DOWN (towards whatever is below). Closing swings
-- both covers down until they meet under the spine (alpha 0 = shut) - the slam.
--
-- API
--   GiantBook.Build(scale: number?, color: Color3?) -> Model
--        PrimaryPart "Spine". Spine attachments "LeftHinge" / "RightHinge" (rotation axis = their Z).
--        Each cover Model: PrimaryPart "Board" + "Pages", "Line<i>", "Margin", "Corner<i>", "Frame*",
--        "Emblem*" (the purple SOUL, Neon), "PageEdge<i>", "Edge" (glowing fore-edge).
--        Attributes: PropId, Scale, Open (0..1), PartCount.
--   GiantBook.SetOpen(model, alpha: number)   1 = flat open, 0 = slammed shut (-0.05..1.1 allowed for
--        overshoot). Pure instance edits; reads Spine.CFrame, so it works wherever the book was moved.
--   GiantBook.Preview(alpha?, scale?) -> Model   Build + SetOpen (galleries, previews)
--   GiantBook.Size -> Vector3   open footprint at scale 1

local Props = require(script.Parent)

local GiantBook = {}

local COVER_W, COVER_L, COVER_T = 6.2, 9, 0.34 -- one cover: width (from spine), length (Z), thickness
local PAGES_T = 0.9
local SPINE_HALF = PAGES_T + COVER_T * 0.5 -- hinge offset from the centre line
GiantBook.Size = Vector3.new((COVER_W + SPINE_HALF) * 2, COVER_T + PAGES_T, COVER_L)

local PURPLE = Color3.fromRGB(110, 36, 140)
local GOLD = Color3.fromRGB(233, 180, 55)
local PAGE = Color3.fromRGB(244, 236, 214)
local INK = Color3.fromRGB(120, 130, 170)
local MARGIN = Color3.fromRGB(214, 70, 80)
local GLOW = Color3.fromRGB(213, 53, 217)

local function cover(kit: any, model: Model, side: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = if side < 0 then "LeftCover" else "RightCover"
	local hingeX = SPINE_HALF * side
	local cx = hingeX + side * COVER_W / 2
	-- board on top, pages hanging under it (pages face -Y when open)
	local board = kit.Box(m, "Board", Vector3.new(COVER_W, COVER_T, COVER_L), CFrame.new(cx, COVER_T / 2, 0), color, {
		Role = "Cloth",
		Material = Enum.Material.Fabric,
	})
	local pageW, pageL = COVER_W - 0.35, COVER_L - 0.5
	local pageCX = hingeX + side * (pageW / 2 + 0.05)
	kit.Box(m, "Pages", Vector3.new(pageW, PAGES_T, pageL), CFrame.new(pageCX, -PAGES_T / 2, 0), PAGE, {
		Role = "ClothAlt",
		Material = Enum.Material.SmoothPlastic,
	})
	-- ruled lines + red margin on the page face (underside)
	local y = -PAGES_T - 0.012
	for i = 1, 7 do
		local z = -pageL / 2 + 0.9 + (i - 1) * (pageL - 1.8) / 6
		kit.Box(m, "Line" .. i, Vector3.new(pageW * 0.78, 0.02, 0.07), CFrame.new(pageCX + side * 0.25, y, z), INK, {
			Role = "Detail",
			CastShadow = false,
		})
	end
	kit.Box(m, "Margin", Vector3.new(0.07, 0.02, pageL * 0.96), CFrame.new(hingeX + side * 1.25, y, 0), MARGIN, {
		Role = "Detail",
		CastShadow = false,
	})
	-- gold corner protectors (right triangles on the outer corners, on top of the board)
	local outer = hingeX + side * COVER_W
	for i, zs in { -1, 1 } do
		local corner = Vector3.new(outer, COVER_T + 0.03, zs * COVER_L / 2)
		local a = corner - Vector3.new(side * 1.3, 0, 0)
		local b = corner - Vector3.new(0, 0, zs * 1.3)
		Props.Triangle(
			kit,
			m,
			"Corner" .. i,
			corner,
			a,
			b,
			0.08,
			GOLD,
			{ Role = "Trim", Material = Enum.Material.Metal }
		)
	end
	-- gold frame inset on the cover + the purple SOUL embossed in the middle
	local fy = COVER_T + 0.02
	local fx0, fx1 = hingeX + side * 0.45, hingeX + side * (COVER_W - 0.45)
	local fw = math.abs(fx1 - fx0)
	local fcx = (fx0 + fx1) / 2
	local trim = { Role = "Trim", Material = Enum.Material.Metal, CastShadow = false }
	kit.Box(m, "FrameA", Vector3.new(fw, 0.05, 0.14), CFrame.new(fcx, fy, -COVER_L / 2 + 0.55), GOLD, trim)
	kit.Box(m, "FrameB", Vector3.new(fw, 0.05, 0.14), CFrame.new(fcx, fy, COVER_L / 2 - 0.55), GOLD, trim)
	kit.Box(m, "FrameC", Vector3.new(0.14, 0.05, COVER_L - 1.1), CFrame.new(fx0, fy, 0), GOLD, trim)
	kit.Box(m, "FrameD", Vector3.new(0.14, 0.05, COVER_L - 1.1), CFrame.new(fx1, fy, 0), GOLD, trim)
	local Soul = require(script.Parent.Soul) :: any
	local heart = Soul.Build(GLOW, 2.2 * kit.Scale)
	-- lay the heart flat on the cover (mostly sunk in, lobes towards the book's front, -Z)
	local place = CFrame.new(fcx * kit.Scale, (fy - 0.24) * kit.Scale, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	for _, d in heart:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = place * d.CFrame
			d.Name = "Emblem" .. d.Name
			d:SetAttribute("Role", "Glow")
			d.Parent = m
		elseif d:IsA("PointLight") then
			d:Destroy()
		end
	end
	heart:Destroy()
	-- page edges: two darker stripes along the fore-edge read as stacked paper
	for i, yy in { -PAGES_T * 0.32, -PAGES_T * 0.68 } do
		kit.Box(
			m,
			"PageEdge" .. i,
			Vector3.new(0.03, 0.03, pageL * 0.98),
			CFrame.new(hingeX + side * (pageW + 0.035), yy, 0),
			PAGE:Lerp(INK, 0.35),
			{
				Role = "Detail",
				CastShadow = false,
			}
		)
	end
	-- glowing fore-edge (the magic of the ultimate)
	kit.Box(
		m,
		"Edge",
		Vector3.new(0.08, PAGES_T * 0.25, pageL),
		CFrame.new(hingeX + side * (pageW + 0.06), -PAGES_T * 0.92, 0),
		GLOW,
		{
			Role = "Glow",
			Material = Enum.Material.Neon,
			CastShadow = false,
		}
	)
	m.PrimaryPart = board
	m.Parent = model
	return m
end

function GiantBook.Build(scale: number?, color: Color3?): Model
	local s = scale or 1
	local kit = Props.Kit(s)
	local c = color or PURPLE
	local model = Props.NewModel("GiantBook", "GiantBook")
	local spine = kit.Box(
		model,
		"Spine",
		Vector3.new(SPINE_HALF * 2, COVER_T, COVER_L),
		CFrame.new(0, COVER_T / 2, 0),
		c:Lerp(Color3.new(0, 0, 0), 0.25),
		{
			Role = "Cloth",
			Material = Enum.Material.Fabric,
		}
	)
	for i, z in { -COVER_L * 0.32, COVER_L * 0.32 } do
		kit.Box(
			model,
			"Band" .. i,
			Vector3.new(SPINE_HALF * 2 + 0.04, COVER_T + 0.04, 0.32),
			CFrame.new(0, COVER_T / 2, z),
			GOLD,
			{
				Role = "Trim",
				Material = Enum.Material.Metal,
			}
		)
	end
	-- ribbon bookmark hanging from the spine between the pages
	kit.Box(
		model,
		"Ribbon",
		Vector3.new(0.05, 2.2, 0.36),
		CFrame.new(0, -1.1, COVER_L * 0.18) * CFrame.Angles(0, 0, 0.08),
		MARGIN,
		{
			Role = "Accent",
			Material = Enum.Material.Fabric,
			CastShadow = false,
		}
	)
	kit.Attach(spine, "LeftHinge", CFrame.new(-SPINE_HALF, -COVER_T / 2, 0))
	kit.Attach(spine, "RightHinge", CFrame.new(SPINE_HALF, -COVER_T / 2, 0))
	for _, side in { -1, 1 } do
		local m = cover(kit, model, side, c)
		-- rest pose relative to the hinge frame (spine frame shifted to the hinge line)
		local hinge = spine.CFrame * CFrame.new(SPINE_HALF * side * s, -COVER_T / 2 * s, 0)
		local inv = hinge:Inverse()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d:SetAttribute("BookRest", inv * d.CFrame)
			end
		end
	end
	model:SetAttribute("Scale", s)
	model:SetAttribute("Open", 1)
	return Props.Finish(model, spine)
end

-- Built + SetOpen in one call (galleries, previews).
function GiantBook.Preview(alpha: number?, scale: number?): Model
	local model = GiantBook.Build(scale)
	GiantBook.SetOpen(model, alpha or 1)
	return model
end

function GiantBook.SetOpen(model: Model, alpha: number)
	local spine = model.PrimaryPart
	if spine == nil then
		return
	end
	local a = math.clamp(alpha, -0.05, 1.1)
	local angle = (1 - a) * math.pi / 2
	for _, side in { -1, 1 } do
		local name = if side < 0 then "LeftCover" else "RightCover"
		local m = model:FindFirstChild(name)
		local att = spine:FindFirstChild(if side < 0 then "LeftHinge" else "RightHinge")
		if m and att and att:IsA("Attachment") then
			-- left cover swings down with +Z rotation, right cover with -Z rotation
			local target = spine.CFrame * att.CFrame * CFrame.Angles(0, 0, -side * angle)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					local rest = d:GetAttribute("BookRest")
					if typeof(rest) == "CFrame" then
						d.CFrame = target * rest
					end
				end
			end
		end
	end
	model:SetAttribute("Open", a)
end

return GiantBook
