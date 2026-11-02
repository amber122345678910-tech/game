--!nocheck
-- Rick's garage in the back yard (floor Y = -9) and Rick's saucer.
-- Garage inside: X -44..-20, Z -30..-12. The big door is in the east wall (X = -20).
local U = require("./Util")
local Characters = require("./Characters")

local Vector3, CFrame, Enum = U.Vector3, U.CFrame, U.Enum
local UDim2, UDim = U.UDim2, U.UDim
local rgb, v = U.rgb, U.v
local box, boxL, ellipsoid, ball, cyl, vcyl, ecyl, part, wall = U.box, U.boxL, U.ellipsoid, U.ball, U.cyl, U.vcyl, U.ecyl, U.part, U.wall
local ui = U.ui
local M = Enum.Material

local C = {
	wall = rgb(150, 146, 138),
	floor = rgb(120, 120, 118),
	siding = rgb(214, 204, 178),
	roof = rgb(76, 66, 66),
	metal = rgb(150, 154, 160),
	darkMetal = rgb(70, 72, 78),
	wood = rgb(140, 100, 64),
	green = rgb(110, 255, 90),
	trim = rgb(236, 232, 222),
}

local Garage = {}
local FLOOR = -9

local function interact(model, id, text)
	model:SetAttribute("Interact", id)
	model:SetAttribute("InteractText", text)
end

local function light(parentPart, name, class, props)
	local l = U.Instance.new(class)
	l.Name = name
	for k, val in props do
		l[k] = val
	end
	l.Parent = parentPart
	return l
end

local function buildBuilding(world)
	local g = U.model("RickGarage", world)
	-- floor, walls, roof
	box(g, "Floor", -45, FLOOR - 1, -31, -19, FLOOR + 0.02, -11, C.floor, M.Concrete)
	box(g, "Stain", -33, FLOOR + 0.02, -24, -29, FLOOR + 0.025, -19, rgb(80, 80, 80), M.Concrete)
	box(g, "WallWest", -45, FLOOR, -31, -44, 1, -11, C.wall, M.Concrete)
	box(g, "WallNorth", -44, FLOOR, -31, -19, 1, -30, C.wall, M.Concrete)
	wall(g, "WallSouth", "x", -44, -19, FLOOR, 1, -12, -11, { { -40, -36, -5.5, -2.5 }, { -31, -27, -5.5, -2.5 } }, C.wall, M.Concrete)
	wall(g, "WallEast", "z", -30, -12, FLOOR, 1, -20, -19, { { -27.5, -14.5, FLOOR, -1 } }, C.wall, M.Concrete)
	box(g, "Ceiling", -45, 1, -31, -19, 1.6, -11, rgb(110, 108, 104), M.Concrete)
	-- outside skin
	box(g, "SidingN", -45.4, FLOOR, -31.4, -18.6, 1.6, -31, C.siding, M.WoodPlanks)
	box(g, "SidingW", -45.4, FLOOR, -31, -45, 1.6, -11, C.siding, M.WoodPlanks)
	wall(g, "SidingS", "x", -45.4, -18.6, FLOOR, 1.6, -11, -10.6, { { -40, -36, -5.5, -2.5 }, { -31, -27, -5.5, -2.5 } }, C.siding, M.WoodPlanks)
	wall(g, "SidingE", "z", -31, -11, FLOOR, 1.6, -19, -18.6, { { -27.5, -14.5, FLOOR, -1 } }, C.siding, M.WoodPlanks)
	box(g, "Roof", -46, 1.6, -32, -18, 2.2, -10, C.roof, M.Slate)
	-- south windows glow green at night
	for i, x in { -38, -29 } do
		local w = box(g, "Window" .. i, x - 2, -5.5, -11.55, x + 2, -2.5, -11.45, rgb(150, 255, 130), M.Neon)
		w:SetAttribute("NightWindow", true)
		w.Transparency = 0.35
	end
	-- driveway
	box(g, "Driveway", -19, FLOOR, -28, 4, FLOOR + 0.04, -14, rgb(140, 136, 130), M.Concrete)

	-- up-and-over garage door (hinge along the top edge of the opening)
	local door = U.model("GarageDoor", g)
	box(door, "Panel", -19.95, FLOOR + 0.05, -27.45, -19.7, -1.05, -14.55, rgb(200, 196, 186), M.Metal)
	for i = 1, 4 do
		local y = FLOOR + i * 1.6
		box(door, "Rib" .. i, -19.7, y - 0.08, -27.4, -19.6, y + 0.08, -14.6, rgb(176, 172, 162), M.Metal)
	end
	box(door, "Handle", -19.6, FLOOR + 1.2, -21.6, -19.5, FLOOR + 1.35, -20.4, rgb(90, 90, 96), M.Metal)
	door:SetAttribute("Hinge", v(-19.8, -1.05, -21))
	return g
end

local function buildLab(world)
	local lab = U.model("RickLab", world)
	-- revival table
	local tbl = U.model("RevivalTable", lab)
	tbl:SetAttribute("Outline", true)
	box(tbl, "Base", -41.2, FLOOR, -22.5, -39.8, FLOOR + 2.4, -19.5, C.darkMetal, M.Metal)
	box(tbl, "Top", -41.8, FLOOR + 2.4, -24.4, -39.2, FLOOR + 2.8, -17.6, C.metal, M.DiamondPlate)
	box(tbl, "Sheet", -41.7, FLOOR + 2.8, -24.3, -39.3, FLOOR + 2.86, -17.7, rgb(230, 236, 236), M.Fabric)
	ellipsoid(tbl, "Pillow", CFrame.new(-40.5, FLOOR + 3.0, -23.5), v(1.9, 0.4, 0.9), rgb(240, 244, 244), M.Fabric)
	-- straps
	for i, z in { -21.5, -19.2 } do
		box(tbl, "Strap" .. i, -41.85, FLOOR + 2.86, z - 0.15, -39.15, FLOOR + 2.9, z + 0.15, rgb(60, 50, 40), M.Leather)
	end
	-- robot arms from the ceiling
	local arms = U.model("RobotArms", lab)
	for i, side in { -1, 1 } do
		local base = v(-40.5 + side * 1.6, 0.9, -21)
		vcyl(arms, "Mount" .. i, base - v(0, 0.3, 0), 0.4, 0.9, C.darkMetal, M.Metal)
		local elbow = base + v(side * 0.8, -2.6, -0.6)
		local tip = v(-40.5 + side * 0.6, FLOOR + 4.2, -21.4)
		cyl(arms, "Upper" .. i, base, elbow, 0.35, C.metal, M.Metal)
		ball(arms, "Joint" .. i, elbow, 0.5, C.darkMetal, M.Metal)
		cyl(arms, "Lower" .. i, elbow, tip, 0.28, C.metal, M.Metal)
		local t = ball(arms, "Tip" .. i, tip, 0.3, C.green, M.Neon)
		t.CastShadow = false
	end
	-- big surgical lamp
	vcyl(lab, "LampStem", v(-40.5, -1.0, -21), 2.0, 0.15, C.darkMetal, M.Metal)
	local lampHead = ellipsoid(lab, "LampHead", CFrame.new(-40.5, -1.2, -21), v(2.4, 0.7, 2.4), C.metal, M.Metal)
	lampHead.CastShadow = false
	local lampGlow = vcyl(lab, "LampGlow", v(-40.5, -1.6, -21), 0.05, 1.8, rgb(240, 250, 255), M.Neon)
	lampGlow:SetAttribute("BulbFor", "SurgeryLight")
	lampGlow.CastShadow = false
	local lm = U.marker(lab, "SurgeryLightSource", CFrame.new(-40.5, -1.7, -21) * CFrame.Angles(math.rad(-90), 0, 0))
	light(lm, "SurgeryLight", "SpotLight", { Face = Enum.NormalId.Front, Angle = 60, Range = 14, Brightness = 2.4, Color = rgb(225, 240, 255), Shadows = true })

	-- cloning vat with green goo
	local vat = U.model("Vat", lab)
	vat:SetAttribute("Outline", true)
	vcyl(vat, "Base", v(-42.2, FLOOR, -27.6), 0.8, 3.4, C.darkMetal, M.Metal)
	local goo = vcyl(vat, "Goo", v(-42.2, FLOOR + 0.8, -27.6), 5.2, 2.7, rgb(120, 255, 100), M.Neon)
	goo.Transparency = 0.45
	goo.CastShadow = false
	local glass = vcyl(vat, "Glass", v(-42.2, FLOOR + 0.8, -27.6), 5.6, 3.0, rgb(200, 240, 230), M.Glass)
	glass.Transparency = 0.75
	glass.CastShadow = false
	vcyl(vat, "Cap", v(-42.2, FLOOR + 6.4, -27.6), 0.6, 3.3, C.darkMetal, M.Metal)
	cyl(vat, "Pipe", v(-42.2, FLOOR + 6.9, -27.6), v(-42.2, 1, -27.6), 0.4, C.darkMetal, M.Metal)
	local bub = U.Instance.new("ParticleEmitter")
	bub.Name = "Bubbles"
	bub.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bub.Color = U.ColorSequence.new(rgb(220, 255, 210))
	bub.Size = U.NumberSequence.new(0.18)
	bub.Rate = 12
	bub.Lifetime = U.NumberRange.new(1.5, 2.5)
	bub.Speed = U.NumberRange.new(1.5, 3)
	bub.SpreadAngle = U.Vector2.new(8, 8)
	bub.LightEmission = 0.6
	bub.Acceleration = v(0, 1, 0)
	bub.EmissionDirection = Enum.NormalId.Right
	bub.Parent = goo
	light(goo, "VatGlow", "PointLight", { Range = 16, Brightness = 1.4, Color = rgb(110, 255, 90), Shadows = true })

	-- workbench + pegboard + tools
	local wb = U.model("Workbench", lab)
	wb:SetAttribute("Outline", true)
	box(wb, "Top", -40, FLOOR + 3.0, -30, -28, FLOOR + 3.3, -27.8, C.wood, M.Wood)
	for _, x in { -39.7, -28.4 } do
		box(wb, "Leg", x, FLOOR, -29.8, x + 0.3, FLOOR + 3.0, -28.0, C.darkMetal, M.Metal)
	end
	box(wb, "Shelf", -40, FLOOR + 1.0, -30, -28, FLOOR + 1.2, -28.2, C.wood, M.Wood)
	box(wb, "Pegboard", -40, FLOOR + 3.6, -29.98, -28, FLOOR + 7.4, -29.9, rgb(180, 150, 110), M.Cardboard)
	local tools = { { -38.5, 0.25, 1.6, rgb(200, 60, 50) }, { -37.2, 0.2, 1.4, C.metal }, { -36, 0.6, 0.9, rgb(60, 90, 200) }, { -34.5, 0.18, 1.8, C.metal }, { -33, 0.5, 1.2, rgb(240, 180, 40) }, { -31.4, 0.3, 1.5, C.darkMetal }, { -30, 0.9, 0.5, rgb(200, 60, 50) } }
	for i, t in tools do
		box(wb, "Tool" .. i, t[1] - t[2] / 2, FLOOR + 5.4 - t[3] / 2, -29.9, t[1] + t[2] / 2, FLOOR + 5.4 + t[3] / 2, -29.82, t[4], M.Metal)
	end
	-- gadgets on the bench
	box(wb, "Gadget1", -38, FLOOR + 3.3, -29.6, -36.8, FLOOR + 4.0, -28.6, rgb(90, 96, 104), M.Metal)
	ball(wb, "GadgetLight1", v(-37.4, FLOOR + 4.15, -29.1), 0.3, C.green, M.Neon)
	ecyl(wb, "PortalGunBody", CFrame.new(-33.5, FLOOR + 3.55, -28.9) * CFrame.Angles(0, math.rad(80), 0), v(1.3, 0.5, 0.5), rgb(220, 220, 214), M.SmoothPlastic)
	ball(wb, "PortalGunTip", v(-33.5, FLOOR + 3.55, -28.25), 0.36, C.green, M.Neon)
	vcyl(wb, "Can", v(-31, FLOOR + 3.3, -29.2), 0.7, 0.45, rgb(200, 40, 40), M.Metal)
	vcyl(wb, "Flask", v(-30.2, FLOOR + 3.3, -28.8), 0.9, 0.5, rgb(150, 255, 120), M.Glass).Transparency = 0.3

	-- terminal with screens
	local term = U.model("Terminal", lab)
	term:SetAttribute("Outline", true)
	box(term, "Desk", -43.9, FLOOR, -17, -41.5, FLOOR + 2.8, -13.2, C.darkMetal, M.Metal)
	for i, z in { -16.2, -14.2 } do
		local scr = part(term, "Screen" .. i, CFrame.lookAt(v(-43.3, FLOOR + 4.3, z), v(-40, FLOOR + 4.3, z)), v(1.8, 1.3, 0.15), rgb(10, 20, 14), M.SmoothPlastic)
		local sg = U.surfaceGui(scr, Enum.NormalId.Front, 150, 0)
		sg.Brightness = 1.6
		ui("Frame", { BackgroundColor3 = rgb(6, 18, 10), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = sg })
		ui("TextLabel", {
			Name = "Text",
			BackgroundTransparency = 1,
			Position = UDim2.new(0.05, 0, 0.05, 0),
			Size = UDim2.new(0.9, 0, 0.9, 0),
			Font = Enum.Font.RobotoMono,
			Text = if i == 1 then "MORTY_REBUILD.exe\n> tissue: 96%\n> brain: ok?\n> phone: NOT FOUND" else "C-137 // GARAGE\n> saucer: READY\n> fuel: 63%\n> curse: ???",
			TextColor3 = rgb(120, 255, 140),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextScaled = true,
			Parent = sg,
		})
		light(scr, "ScreenGlow" .. i, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 6, Brightness = 0.6, Color = rgb(120, 255, 140) })
	end
	box(term, "Keyboard", -42.9, FLOOR + 2.8, -16, -42.1, FLOOR + 2.9, -14.4, rgb(50, 52, 58), M.SmoothPlastic)

	-- junk: shelves, boxes, barrels, cables, tires
	local junk = U.model("Junk", lab)
	box(junk, "ShelfFrame", -27, FLOOR, -12.9, -21, FLOOR + 7, -12.1, C.darkMetal, M.Metal)
	for i = 1, 3 do
		box(junk, "ShelfBoard" .. i, -27, FLOOR + i * 2.1, -12.95, -21, FLOOR + i * 2.1 + 0.15, -12.05, C.wood, M.Wood)
		for j = 0, 2 do
			local x = -26.5 + j * 1.9
			box(junk, "Box" .. i .. j, x, FLOOR + i * 2.1 + 0.15, -12.85, x + 1.4, FLOOR + i * 2.1 + 1.2, -12.15, ({ rgb(170, 130, 80), rgb(150, 110, 70), rgb(190, 150, 100) })[j + 1], M.Cardboard)
		end
	end
	vcyl(junk, "Barrel", v(-43, FLOOR, -12.9), 2.6, 1.6, rgb(60, 110, 60), M.CorrodedMetal)
	vcyl(junk, "Barrel2", v(-41.2, FLOOR, -12.8), 2.6, 1.6, rgb(160, 60, 40), M.CorrodedMetal)
	for i = 0, 2 do
		part(junk, "Tire" .. i, CFrame.new(-23, FLOOR + 0.35 + i * 0.7, -28.5) * CFrame.Angles(0, 0, math.rad(90)), v(0.7, 2.2, 2.2), rgb(30, 30, 32), M.Rubber).Shape = Enum.PartType.Cylinder
	end
	cyl(junk, "Cable1", v(-42.2, FLOOR + 0.15, -26), v(-39.8, FLOOR + 0.15, -22.8), 0.3, rgb(30, 30, 32), M.Rubber)
	cyl(junk, "Cable2", v(-41.8, FLOOR + 0.15, -17), v(-40.6, FLOOR + 0.15, -19.4), 0.3, rgb(160, 30, 30), M.Rubber)

	-- fluorescent ceiling lights
	for i, z in { -26, -21, -16 } do
		local tube = box(lab, "Tube" .. i, -38, 0.55, z - 0.25, -26, 0.85, z + 0.25, rgb(240, 248, 255), M.Neon)
		tube:SetAttribute("BulbFor", "GarageLight")
		tube.CastShadow = false
		light(tube, "GarageLight", "PointLight", { Range = 22, Brightness = 0.9, Color = rgb(225, 238, 255), Shadows = true })
	end

	-- where Morty wakes up / stands after getting off the table
	local spots = U.folder("GarageSpots", lab)
	-- head lies at the north end of the table, face up, top of the head towards -Z
	U.marker(spots, "MortyHead", CFrame.new(-40.5, FLOOR + 3.75, -23.1, -1, 0, 0, 0, 0, -1, 0, -1, 0))
	local stand = v(-37.8, FLOOR + 3, -20.4)
	U.marker(spots, "MortyStand", CFrame.lookAt(stand, stand + v(1, 0, 0.15)), v(2, 2, 1))
	local rick = v(-38.6, FLOOR + 3 * 1.12, -22.6)
	U.marker(spots, "RickByTable", CFrame.lookAt(rick, rick + v(-1, 0, -0.1)), v(2, 2, 1))
	return lab
end

----------------------------------------------------------------------------
-- The saucer (all anchored, moved with PivotTo). Local frame: Y = 0 is the ground, front = -Z.
----------------------------------------------------------------------------
function Garage.buildSaucer(world, pivot)
	local s = U.model("Saucer", world)
	s:SetAttribute("Outline", true)
	local root = U.marker(s, "Root", pivot, v(1, 1, 1))
	s.PrimaryPart = root
	local function L(x, y, z)
		return pivot * CFrame.new(x, y, z)
	end
	local hull = rgb(156, 162, 168)
	local hullDark = rgb(96, 100, 108)
	-- landing legs
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3 + math.pi / 6
		local top = (pivot * CFrame.new(math.cos(a) * 2.6, 1.6, math.sin(a) * 2.6)).Position
		local foot = (pivot * CFrame.new(math.cos(a) * 3.6, 0.2, math.sin(a) * 3.6)).Position
		cyl(s, "Leg" .. i, top, foot, 0.32, hullDark, M.Metal)
		part(s, "Foot" .. i, CFrame.new(foot) * CFrame.Angles(0, 0, math.rad(90)), v(0.2, 1.0, 1.0), hullDark, M.Metal).Shape = Enum.PartType.Cylinder
	end
	-- hull
	ellipsoid(s, "HullLow", L(0, 2.0, 0), v(11, 2.4, 11), hull, M.Metal)
	ecyl(s, "Rim", L(0, 2.15, 0) * CFrame.Angles(0, 0, math.rad(90)), v(0.5, 11.3, 11.3), hullDark, M.Metal)
	ellipsoid(s, "Deck", L(0, 2.9, 0.4), v(8.4, 1.3, 8.0), rgb(176, 180, 186), M.Metal)
	ellipsoid(s, "Belly", L(0, 1.25, 0), v(5, 1.2, 5), hullDark, M.Metal)
	local belly = ecyl(s, "BellyGlow", L(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90)), v(0.15, 3.6, 3.6), rgb(120, 255, 200), M.Neon)
	belly.CastShadow = false
	light(belly, "SaucerGlow", "PointLight", { Range = 14, Brightness = 1.2, Color = rgb(120, 255, 200), Shadows = false })
	-- rim lights
	for i = 0, 15 do
		local a = i * math.pi * 2 / 16
		local p = (pivot * CFrame.new(math.cos(a) * 5.6, 2.15, math.sin(a) * 5.6)).Position
		local b = ball(s, "RimLight" .. i, p, 0.32, if i % 2 == 0 then rgb(255, 210, 80) else rgb(120, 220, 255), M.Neon)
		b.CastShadow = false
	end
	-- patches / rust
	part(s, "Patch1", L(3.6, 2.95, 2.2) * CFrame.Angles(math.rad(-14), math.rad(30), 0), v(1.4, 0.06, 1.0), rgb(140, 100, 70), M.CorrodedMetal)
	part(s, "Patch2", L(-3.4, 2.9, -2.6) * CFrame.Angles(math.rad(12), math.rad(-20), 0), v(1.0, 0.06, 0.8), rgb(120, 110, 100), M.CorrodedMetal)
	-- cockpit tub
	ellipsoid(s, "Tub", L(0, 3.2, 0.2), v(5.2, 1.6, 4.6), rgb(64, 66, 72), M.Metal)
	local function seat(name, x)
		part(s, name .. "Cushion", L(x, 3.55, 0.7), v(1.5, 0.35, 1.5), rgb(150, 40, 40), M.Leather)
		part(s, name .. "Back", L(x, 4.6, 1.45) * CFrame.Angles(math.rad(-12), 0, 0), v(1.5, 2.0, 0.35), rgb(150, 40, 40), M.Leather)
		part(s, name .. "Head", L(x, 5.75, 1.62) * CFrame.Angles(math.rad(-12), 0, 0), v(1.0, 0.6, 0.35), rgb(130, 34, 34), M.Leather)
	end
	seat("SeatL", -1.1)
	seat("SeatR", 1.1)
	-- dashboard
	part(s, "Dash", L(0, 4.0, -1.35) * CFrame.Angles(math.rad(25), 0, 0), v(4.4, 0.9, 0.9), rgb(50, 52, 58), M.Metal)
	for i = 0, 5 do
		local b = ball(s, "Button" .. i, (L(-1.6 + i * 0.64, 4.42, -1.25)).Position, 0.16, ({ rgb(255, 60, 60), C.green, rgb(80, 160, 255), rgb(255, 210, 60) })[i % 4 + 1], M.Neon)
		b.CastShadow = false
	end
	local screen = part(s, "DashScreen", L(0.9, 4.45, -1.2) * CFrame.Angles(math.rad(-55), 0, 0), v(1.1, 0.6, 0.05), rgb(10, 30, 20), M.SmoothPlastic)
	local sg = U.surfaceGui(screen, Enum.NormalId.Front, 150, 0)
	sg.Brightness = 1.5
	ui("TextLabel", {
		Name = "Text",
		BackgroundColor3 = rgb(6, 20, 12),
		Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.RobotoMono,
		Text = "NAV: B137",
		TextColor3 = rgb(120, 255, 150),
		TextScaled = true,
		Parent = sg,
	})
	-- steering yoke + levers
	cyl(s, "Column", (L(-1.1, 4.1, -1.0)).Position, (L(-1.1, 4.6, -0.4)).Position, 0.15, rgb(40, 40, 44), M.Metal)
	part(s, "Yoke", L(-1.1, 4.65, -0.35) * CFrame.Angles(math.rad(-30), 0, 0), v(1.2, 0.18, 0.18), rgb(30, 30, 34), M.Metal)
	for i, x in { -0.25, 0.1 } do
		cyl(s, "Lever" .. i, (L(x, 3.9, -0.6)).Position, (L(x, 4.6, -0.5)).Position, 0.08, rgb(160, 160, 166), M.Metal)
		ball(s, "LeverKnob" .. i, (L(x, 4.65, -0.5)).Position, 0.2, rgb(220, 40, 40), M.SmoothPlastic)
	end
	-- windshield (arc of glass panels)
	for i = -2, 2 do
		local a = math.rad(i * 22)
		local cf = L(math.sin(a) * 2.5, 4.55, -1.6 + (1 - math.cos(a)) * 2.5) * CFrame.Angles(0, -a, 0) * CFrame.Angles(math.rad(-20), 0, 0)
		local g = part(s, "Glass" .. i, cf, v(1.05, 1.2, 0.06), rgb(180, 220, 240), M.Glass)
		g.Transparency = 0.7
		g.CastShadow = false
	end
	part(s, "GlassFrame", L(0, 5.12, -1.75) * CFrame.Angles(math.rad(-20), 0, 0), v(5.4, 0.12, 0.12), hullDark, M.Metal)
	-- engine at the back
	ellipsoid(s, "EngineHousing", L(0, 3.0, 4.4), v(3.4, 1.6, 2.2), hullDark, M.Metal)
	for i, x in { -0.9, 0.9 } do
		local noz = part(s, "Nozzle" .. i, L(x, 3.0, 5.4) * CFrame.Angles(0, math.rad(90), 0), v(0.9, 0.9, 0.9), rgb(40, 40, 44), M.Metal)
		noz.Shape = Enum.PartType.Cylinder
		local flame = part(s, "Flame" .. i, L(x, 3.0, 5.86) * CFrame.Angles(0, math.rad(90), 0), v(0.05, 0.7, 0.7), rgb(120, 220, 255), M.Neon)
		flame.Shape = Enum.PartType.Cylinder
		flame.CastShadow = false
		local pe = U.Instance.new("ParticleEmitter")
		pe.Name = "Thrust"
		pe.Texture = "rbxasset://textures/particles/fire_main.dds"
		pe.Color = U.ColorSequence.new(rgb(120, 220, 255), rgb(60, 80, 255))
		pe.LightEmission = 1
		pe.Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.9), U.NumberSequenceKeypoint.new(1, 0.1) })
		pe.Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.2), U.NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = U.NumberRange.new(0.25, 0.45)
		pe.Speed = U.NumberRange.new(8, 14)
		pe.Rate = 60
		pe.EmissionDirection = Enum.NormalId.Left
		pe.Enabled = false
		pe.Parent = flame
	end
	-- markers
	local seats = U.folder("Spots", s)
	U.marker(seats, "SeatRick", L(-1.1, 3.72 + 1.0 * 1.12, 0.7) , v(1, 1, 1))
	U.marker(seats, "SeatMorty", L(1.1, 3.72 + 1.0, 0.7), v(1, 1, 1))
	U.marker(seats, "EyeMorty", L(1.1, 3.72 + 2.95, 0.45), v(0.4, 0.4, 0.4))
	U.marker(seats, "Smoke", L(0, 3.4, 2.5), v(0.4, 0.4, 0.4))
	-- smoke + fire for the crash (off until then)
	local smokePart = seats:FindFirstChild("Smoke")
	local sm = U.Instance.new("ParticleEmitter")
	sm.Name = "CrashSmoke"
	sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
	sm.Color = U.ColorSequence.new(rgb(40, 38, 36))
	sm.Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 1.5), U.NumberSequenceKeypoint.new(1, 7) })
	sm.Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.3), U.NumberSequenceKeypoint.new(1, 1) })
	sm.Lifetime = U.NumberRange.new(3, 5)
	sm.Speed = U.NumberRange.new(3, 6)
	sm.SpreadAngle = U.Vector2.new(20, 20)
	sm.Rate = 18
	sm.Acceleration = v(2, 2, 0)
	sm.Enabled = false
	sm.Parent = smokePart
	local fire = U.Instance.new("Fire")
	fire.Name = "CrashFire"
	fire.Size = 4
	fire.Heat = 8
	fire.Enabled = false
	fire.Parent = smokePart
	return s
end

function Garage.build(world)
	buildBuilding(world)
	local lab = buildLab(world)
	-- Rick waits by the table
	local spots = lab:FindFirstChild("GarageSpots")
	local rick = Characters.build(world:FindFirstChild("Cast"), Characters.Specs.Rick, spots:FindFirstChild("RickByTable").CFrame)
	-- saucer parked in the middle of the garage, nose towards the door (+X)
	local pivot = CFrame.new(-30.5, FLOOR, -21) * CFrame.Angles(0, math.rad(-90), 0)
	local saucer = Garage.buildSaucer(world, pivot)
	interact(saucer, "Saucer", "Get in")
	return rick, saucer
end

return Garage
