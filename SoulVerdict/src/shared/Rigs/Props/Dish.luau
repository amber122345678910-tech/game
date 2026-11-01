--!strict
-- Dish prop: Kindness' comfort food on a little plate. [Lune-safe]
--   "Pie"             golden lattice-top pie (deep amber filling, crimped crust)
--   "ButterscotchPie" Toriel's butterscotch-cinnamon pie: glossy butterscotch top, cinnamon swirl,
--                     crimped crust and a dollop of cream
--   "Sandwich"        a sandwich cut corner to corner, one half leaning on the other (bread, lettuce,
--                     cheese, tomato)
-- Built at the origin (plate bottom at y = 0), the "front" faces -Z.
--
-- API
--   Dish.Build(kind: string?, scale: number?) -> Model   kind defaults to "ButterscotchPie"
--        PrimaryPart "Plate". Food parts Role "Accent"/"Detail"/"Trim". Attributes: PropId, Kind, Scale,
--        PartCount.
--   Dish.Kinds() -> {string}

local Props = require(script.Parent)

local Dish = {}

local KINDS = { "Pie", "ButterscotchPie", "Sandwich" }

local rgb = Color3.fromRGB
local V = Vector3.new
local CRUST = rgb(214, 150, 74)
local CRUST_HI = rgb(236, 186, 110)
local PLATE = rgb(242, 244, 248)

function Dish.Kinds(): { string }
	return table.clone(KINDS)
end

local function plate(kit: any, model: Model): BasePart
	local p = kit.Disc(model, "Plate", 2.5, 0.07, CFrame.new(0, 0.115, 0) * CFrame.Angles(-math.pi / 2, 0, 0), PLATE, {
		Role = "Detail",
		Material = Enum.Material.SmoothPlastic,
	})
	kit.Disc(
		model,
		"PlateFoot",
		1.5,
		0.08,
		CFrame.new(0, 0.04, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
		PLATE:Lerp(rgb(170, 175, 190), 0.25),
		{
			Role = "Detail",
		}
	)
	kit.Disc(
		model,
		"PlateWell",
		1.85,
		0.01,
		CFrame.new(0, 0.152, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
		rgb(226, 230, 238),
		{
			Role = "Detail",
			CastShadow = false,
		}
	)
	return p
end

-- Crust ring of small balls (crimped edge).
local function crimp(kit: any, model: Model, y: number, r: number, n: number, d: number)
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		kit.Ball(
			model,
			"Crimp" .. i,
			d,
			CFrame.new(math.cos(a) * r, y, math.sin(a) * r),
			if i % 2 == 0 then CRUST else CRUST_HI,
			{
				Role = "Trim",
				CastShadow = false,
			}
		)
	end
end

local function pie(kit: any, model: Model, butterscotch: boolean)
	local base, top = 0.155, 0.47
	-- crust shell
	kit.Disc(
		model,
		"Crust",
		1.95,
		top - base,
		CFrame.new(0, (base + top) / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
		CRUST,
		{
			Role = "Accent",
		}
	)
	local fill = if butterscotch then rgb(238, 162, 46) else rgb(150, 62, 38)
	kit.Disc(model, "Filling", 1.76, 0.05, CFrame.new(0, top + 0.01, 0) * CFrame.Angles(-math.pi / 2, 0, 0), fill, {
		Role = "Accent",
		Reflectance = if butterscotch then 0.12 else 0.04,
	})
	crimp(kit, model, top + 0.02, 0.9, 14, 0.2)
	if butterscotch then
		-- cinnamon swirl (dots along an Archimedean spiral) + cream dollop
		for i = 1, 9 do
			local t = i / 9
			local a = t * math.pi * 3.2
			local r = 0.12 + t * 0.6
			kit.Ellipsoid(
				model,
				"Cinnamon" .. i,
				V(0.12, 0.03, 0.12),
				CFrame.new(math.cos(a) * r, top + 0.04, math.sin(a) * r),
				rgb(140, 72, 30),
				{
					Role = "Detail",
					CastShadow = false,
				}
			)
		end
		kit.Ellipsoid(model, "Cream", V(0.42, 0.26, 0.42), CFrame.new(0, top + 0.13, 0), rgb(255, 250, 240), {
			Role = "Detail",
		})
		kit.Ellipsoid(model, "CreamTip", V(0.18, 0.18, 0.18), CFrame.new(0.02, top + 0.27, 0.01), rgb(255, 252, 246), {
			Role = "Detail",
			CastShadow = false,
		})
	else
		-- lattice: three strips each way, slightly raised
		for i = -1, 1 do
			local o = i * 0.42
			local len = 2 * math.sqrt(math.max(0.85 ^ 2 - o * o, 0.05))
			kit.Box(
				model,
				"LatticeX" .. (i + 2),
				V(len, 0.06, 0.16),
				CFrame.new(0, top + 0.05, o) * CFrame.Angles(0, 0, 0),
				CRUST_HI,
				{
					Role = "Trim",
					CastShadow = false,
				}
			)
			kit.Box(model, "LatticeZ" .. (i + 2), V(0.16, 0.06, len), CFrame.new(o, top + 0.075, 0), CRUST_HI, {
				Role = "Trim",
				CastShadow = false,
			})
		end
	end
end

-- One triangular sandwich half: layers stacked on a right-isosceles triangle (right angle at `corner`).
local function sandwichHalf(kit: any, model: Model, idx: number, frame: CFrame)
	local bread = rgb(244, 222, 170)
	local crust = rgb(196, 132, 70)
	local function tri(name: string, y: number, t: number, inset: number, color: Color3, props: any)
		local L = 1.5 - inset
		local o = inset * 0.5
		local corner = (frame * CFrame.new(o, y, o)).Position
		local a = (frame * CFrame.new(o + L, y, o)).Position
		local b = (frame * CFrame.new(o, y, o + L)).Position
		Props.Triangle(kit, model, name .. idx, corner, a, b, t, color, props)
	end
	local food = { Role = "Accent" }
	tri("CrustLow", 0.08, 0.15, 0, crust, food)
	tri("BreadLow", 0.08, 0.17, 0.1, bread, food)
	tri("Lettuce", 0.2, 0.05, -0.12, rgb(110, 196, 70), { Role = "Accent", CastShadow = false })
	tri("Cheese", 0.25, 0.04, 0.05, rgb(255, 204, 60), { Role = "Accent", CastShadow = false })
	for j = 1, 2 do
		local p = frame * CFrame.new(0.35 + j * 0.3, 0.3, 0.35 + (2 - j) * 0.3)
		kit.Disc(model, "Tomato" .. idx .. j, 0.5, 0.06, p * CFrame.Angles(-math.pi / 2, 0, 0), rgb(226, 58, 48), {
			Role = "Accent",
			CastShadow = false,
		})
	end
	tri("CrustTop", 0.42, 0.15, 0, crust, food)
	tri("BreadTop", 0.42, 0.17, 0.1, bread, food)
end

local function sandwich(kit: any)
	return function(model: Model)
		-- half 1 flat on the plate, half 2 leaning on it
		sandwichHalf(kit, model, 1, CFrame.new(-0.85, 0.15, -0.6))
		sandwichHalf(
			kit,
			model,
			2,
			CFrame.new(0.95, 0.3, 0.75) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, -0.32)
		)
	end
end

function Dish.Build(kind: string?, scale: number?): Model
	local k = if kind and table.find(KINDS, kind) then kind else "ButterscotchPie"
	local s = scale or 1
	local kit = Props.Kit(s)
	local model = Props.NewModel("Dish", "Dish")
	local p = plate(kit, model)
	if k == "Pie" then
		pie(kit, model, false)
	elseif k == "ButterscotchPie" then
		pie(kit, model, true)
	else
		sandwich(kit)(model)
	end
	model:SetAttribute("Kind", k)
	model:SetAttribute("Scale", s)
	return Props.Finish(model, p)
end

return Dish
