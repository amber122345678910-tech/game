--!nocheck
-- Planet B137 (desert, the dunes are generated at runtime by WorldGen), the old village,
-- Rick's bunker, and the space scene on the way there.
local U = require("./Util")

local Vector3, CFrame, Enum = U.Vector3, U.CFrame, U.Enum
local UDim2, UDim = U.UDim2, U.UDim
local rgb, v = U.rgb, U.v
local box, boxL, ellipsoid, ball, cyl, vcyl, ecyl, part, wall = U.box, U.boxL, U.ellipsoid, U.ball, U.cyl, U.vcyl, U.ecyl, U.part, U.wall
local ui = U.ui
local M = Enum.Material

local Planet = {}

Planet.ORIGIN = v(6000, 0, 0)
Planet.VILLAGE = v(6150, 0, -60)

local C = {
	stone = rgb(196, 140, 96),
	stoneDark = rgb(160, 104, 70),
	stoneLight = rgb(214, 168, 120),
	wood = rgb(112, 76, 48),
	cloth1 = rgb(170, 50, 46),
	cloth2 = rgb(60, 110, 150),
	cloth3 = rgb(220, 190, 110),
	dark = rgb(20, 14, 12),
	metal = rgb(120, 124, 130),
	concrete = rgb(122, 120, 116),
}

local function light(parentPart, name, class, props)
	local l = U.Instance.new(class)
	l.Name = name
	for k, val in props do
		l[k] = val
	end
	l.Parent = parentPart
	return l
end

local function emitter(parentPart, name, props)
	local pe = U.Instance.new("ParticleEmitter")
	pe.Name = name
	for k, val in props do
		pe[k] = val
	end
	pe.Parent = parentPart
	return pe
end

----------------------------------------------------------------------------
-- Village of old houses (somebody still lives here)
----------------------------------------------------------------------------
local function domeHut(parent, name, base, radius, height, doorYaw, lit)
	local m = U.model(name, parent)
	m:SetAttribute("Outline", true)
	vcyl(m, "Wall", base, height, radius * 2, C.stone, M.Sandstone)
	ellipsoid(m, "Dome", CFrame.new(base + v(0, height, 0)), v(radius * 2.05, radius * 1.2, radius * 2.05), C.stoneLight, M.Sandstone)
	vcyl(m, "Ring", base + v(0, height - 0.6, 0), 0.6, radius * 2 + 0.5, C.stoneDark, M.Sandstone)
	-- doorway (dark arch) facing doorYaw
	local dir = v(math.sin(doorYaw), 0, math.cos(doorYaw))
	local doorCF = CFrame.lookAt(base + dir * (radius - 0.2) + v(0, 2.6, 0), base + dir * (radius + 5) + v(0, 2.6, 0))
	part(m, "Door", doorCF, v(3, 5.2, 0.6), C.dark, M.SmoothPlastic)
	part(m, "DoorArch", doorCF * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.rad(90), 0), v(0.6, 3, 3), C.dark, M.SmoothPlastic).Shape = Enum.PartType.Cylinder
	part(m, "Lintel", doorCF * CFrame.new(0, 3.5, -0.25), v(4.2, 0.6, 0.8), C.wood, M.Wood)
	-- windows
	for i, a in { doorYaw + 1.6, doorYaw - 1.6 } do
		local d = v(math.sin(a), 0, math.cos(a))
		local w = part(m, "Window" .. i, CFrame.lookAt(base + d * (radius - 0.1) + v(0, height * 0.6, 0), base + d * (radius + 5) + v(0, height * 0.6, 0)), v(1.4, 1.6, 0.5), C.dark, M.SmoothPlastic)
		if lit and i == 1 then
			w.Color = rgb(255, 170, 80)
			w.Material = M.Neon
			w:SetAttribute("LitWindow", true)
			light(w, "HutLight", "PointLight", { Range = 14, Brightness = 1.2, Color = rgb(255, 160, 80), Shadows = true })
		end
	end
	return m
end

local function boxHouse(parent, name, base, size, yaw, opts)
	local m = U.model(name, parent)
	m:SetAttribute("Outline", true)
	local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	local w, h, d = size.X, size.Y, size.Z
	boxL(m, "Body", cf, -w / 2, 0, -d / 2, w / 2, h, d / 2, C.stone, M.Sandstone)
	boxL(m, "Parapet", cf, -w / 2 - 0.2, h, -d / 2 - 0.2, w / 2 + 0.2, h + 0.8, d / 2 + 0.2, C.stoneLight, M.Sandstone)
	boxL(m, "RoofInner", cf, -w / 2 + 0.6, h + 0.1, -d / 2 + 0.6, w / 2 - 0.6, h + 0.9, d / 2 - 0.6, C.stoneDark, M.Sandstone)
	-- wooden beams sticking out (vigas)
	local n = math.floor(w / 2.2)
	for i = 0, n - 1 do
		local x = -w / 2 + 1.2 + i * 2.2
		local p0 = (cf * CFrame.new(x, h - 0.7, -d / 2 + 0.5)).Position
		local p1 = (cf * CFrame.new(x, h - 0.7, -d / 2 - 1.0)).Position
		cyl(m, "Viga" .. i, p0, p1, 0.45, C.wood, M.Wood)
	end
	-- arched door on the front (-Z local)
	boxL(m, "Door", cf, -1.4, 0, -d / 2 - 0.05, 1.4, 4.6, -d / 2 + 0.4, C.dark, M.SmoothPlastic)
	part(m, "DoorArch", cf * CFrame.new(0, 4.6, -d / 2 + 0.17) * CFrame.Angles(0, math.rad(90), 0), v(0.46, 2.8, 2.8), C.dark, M.SmoothPlastic).Shape = Enum.PartType.Cylinder
	-- a cloth curtain in the doorway
	if opts and opts.curtain then
		boxL(m, "Curtain", cf, -1.3, 0.6, -d / 2 - 0.12, 1.3, 5.2, -d / 2 - 0.06, opts.curtain, M.Fabric)
	end
	-- windows
	for i, x in { -w / 2 + 2.2, w / 2 - 2.2 } do
		local win = boxL(m, "Window" .. i, cf, x - 0.7, h * 0.55, -d / 2 - 0.05, x + 0.7, h * 0.55 + 1.5, -d / 2 + 0.3, C.dark, M.SmoothPlastic)
		if opts and opts.lit and i == 2 then
			win.Color = rgb(255, 176, 90)
			win.Material = M.Neon
			win:SetAttribute("LitWindow", true)
			light(win, "HouseLight", "PointLight", { Range = 16, Brightness = 1.3, Color = rgb(255, 160, 80), Shadows = true })
		end
	end
	-- ladder to the roof
	if opts and opts.ladder then
		local lx = w / 2 + 0.6
		for _, z in { -0.6, 0.6 } do
			local p0 = (cf * CFrame.new(lx, 0, z)).Position
			local p1 = (cf * CFrame.new(lx + 0.9, h + 1.8, z)).Position
			cyl(m, "LadderRail", p0, p1, 0.2, C.wood, M.Wood)
		end
		for k = 1, math.floor(h / 1.1) do
			local t = k / (h / 1.1 + 1)
			local a = (cf * CFrame.new(lx + 0.9 * t, (h + 1.8) * t, -0.6)).Position
			local b = (cf * CFrame.new(lx + 0.9 * t, (h + 1.8) * t, 0.6)).Position
			cyl(m, "Rung" .. k, a, b, 0.14, C.wood, M.Wood)
		end
	end
	-- chimney with smoke
	if opts and opts.chimney then
		local c = boxL(m, "Chimney", cf, w / 4 - 0.7, h, d / 4 - 0.7, w / 4 + 0.7, h + 3.2, d / 4 + 0.7, C.stoneDark, M.Sandstone)
		local smoke = U.Instance.new("Smoke")
		smoke.Name = "ChimneySmoke"
		smoke.Color = rgb(120, 110, 104)
		smoke.Opacity = 0.18
		smoke.RiseVelocity = 4
		smoke.Size = 2.5
		smoke.Parent = c
	end
	return m
end

local function buildVillage(world)
	local V = Planet.VILLAGE
	local vil = U.model("Village", world)
	domeHut(vil, "HutA", V + v(-26, 0, 22), 6, 6, math.rad(200), false)
	domeHut(vil, "HutB", V + v(18, 0, 30), 5, 5, math.rad(250), true)
	domeHut(vil, "HutC", V + v(34, 0, -14), 7, 7, math.rad(270), false)
	boxHouse(vil, "HouseA", V + v(-12, 0, -24), v(14, 8, 10), math.rad(20), { lit = true, chimney = true, curtain = C.cloth1 })
	boxHouse(vil, "HouseB", V + v(12, 0, -34), v(12, 7, 9), math.rad(-10), { ladder = true, curtain = C.cloth2 })
	boxHouse(vil, "HouseC", V + v(-34, 0, -6), v(10, 6, 8), math.rad(70), {})
	-- tower
	local tower = U.model("Tower", vil)
	tower:SetAttribute("Outline", true)
	vcyl(tower, "Body", V + v(42, 0, 18), 20, 8, C.stone, M.Sandstone)
	vcyl(tower, "Top", V + v(42, 20, 18), 1.2, 9.2, C.stoneLight, M.Sandstone)
	for i = 0, 5 do
		local a = i * math.pi / 3
		box(tower, "Merlon" .. i, V.X + 42 + math.cos(a) * 4.0 - 0.7, 21.2, V.Z + 18 + math.sin(a) * 4.0 - 0.7, V.X + 42 + math.cos(a) * 4.0 + 0.7, 22.6, V.Z + 18 + math.sin(a) * 4.0 + 0.7, C.stoneLight, M.Sandstone)
	end
	for i, y in { 6, 12, 16 } do
		local a = math.rad(200 + i * 25)
		local d = v(math.cos(a), 0, math.sin(a))
		part(tower, "Slit" .. i, CFrame.lookAt(V + v(42, y, 18) + d * 3.85, V + v(42, y, 18) + d * 10), v(0.6, 2.0, 0.5), C.dark, M.SmoothPlastic)
	end
	-- ruins
	local ruins = U.model("Ruins", vil)
	for i = 1, 6 do
		local a = i * 1.1
		local p = V + v(math.cos(a) * 52, 0, math.sin(a) * 46)
		local h = U.randRange(2, 9)
		local col = vcyl(ruins, "Column" .. i, p, h, 1.6, C.stoneLight, M.Sandstone)
		col.CFrame = col.CFrame * CFrame.Angles(math.rad(U.randRange(-6, 6)), 0, 0)
		if i % 2 == 0 then
			box(ruins, "Block" .. i, p.X + 1.5, 0, p.Z - 1, p.X + 3.5, 1.2, p.Z + 1, C.stoneDark, M.Sandstone)
		end
	end
	U.wall(ruins, "WallPiece", "x", V.X - 48, V.X - 36, 0, 5, V.Z + 36, V.Z + 37.4, { { V.X - 44, V.X - 41, 0, 3.5 } }, C.stoneDark, M.Sandstone)
	box(ruins, "WallTop", V.X - 48, 5, V.Z + 36, V.X - 46, 6.5, V.Z + 37.4, C.stoneDark, M.Sandstone)

	-- well in the middle
	local well = U.model("Well", vil)
	well:SetAttribute("Outline", true)
	vcyl(well, "Ring", V + v(0, 0, 0), 2.2, 5, C.stoneDark, M.Sandstone)
	vcyl(well, "Water", V + v(0, 1.6, 0), 0.4, 3.6, rgb(30, 40, 50), M.SmoothPlastic)
	for _, x in { -2.2, 2.2 } do
		box(well, "Post", V.X + x - 0.25, 0, V.Z - 0.25, V.X + x + 0.25, 6, V.Z + 0.25, C.wood, M.Wood)
	end
	cyl(well, "Beam", V + v(-2.6, 5.8, 0), V + v(2.6, 5.8, 0), 0.4, C.wood, M.Wood)
	cyl(well, "Rope", V + v(0, 5.8, 0), V + v(0, 2.6, 0), 0.08, rgb(170, 140, 90), M.Fabric)
	vcyl(well, "Bucket", V + v(0, 2.2, 0), 0.8, 0.8, C.wood, M.Wood)

	-- market stall with cloth canopy
	local stall = U.model("Stall", vil)
	stall:SetAttribute("Outline", true)
	local sp = V + v(-6, 0, 14)
	for _, o in { { -2.5, -1.5 }, { 2.5, -1.5 }, { -2.5, 1.5 }, { 2.5, 1.5 } } do
		box(stall, "Post", sp.X + o[1] - 0.15, 0, sp.Z + o[2] - 0.15, sp.X + o[1] + 0.15, 4.4, sp.Z + o[2] + 0.15, C.wood, M.Wood)
	end
	part(stall, "Canopy", CFrame.new(sp + v(0, 4.6, 0)) * CFrame.Angles(math.rad(8), 0, 0), v(6, 0.15, 4), C.cloth1, M.Fabric)
	box(stall, "Counter", sp.X - 2.6, 1.8, sp.Z - 1.6, sp.X + 2.6, 2.1, sp.Z + 0.2, C.wood, M.Wood)
	for i = 0, 3 do
		ellipsoid(stall, "Pot" .. i, CFrame.new(sp + v(-1.8 + i * 1.2, 2.5, -0.8)), v(0.8, 0.9, 0.8), ({ rgb(180, 90, 60), rgb(200, 120, 70), rgb(150, 80, 50), rgb(210, 150, 90) })[i + 1], M.SmoothPlastic)
	end
	-- laundry line between HouseA and HutA (fresh laundry = someone lives here)
	local laundry = U.model("Laundry", vil)
	local a = V + v(-20, 5.5, -14)
	local b = V + v(-26, 5.5, 12)
	cyl(laundry, "Line", a, b, 0.06, rgb(200, 190, 170), M.Fabric)
	box(laundry, "PoleA", a.X - 0.15, 0, a.Z - 0.15, a.X + 0.15, a.Y + 0.4, a.Z + 0.15, C.wood, M.Wood)
	box(laundry, "PoleB", b.X - 0.15, 0, b.Z - 0.15, b.X + 0.15, b.Y + 0.4, b.Z + 0.15, C.wood, M.Wood)
	for i = 1, 5 do
		local t = i / 6
		local p = a:Lerp(b, t)
		local cloth = part(laundry, "Cloth" .. i, CFrame.lookAt(p - v(0, 1.0, 0), p - v(0, 1.0, 0) + (b - a).Unit:Cross(v(0, 1, 0))), v(1.4, 2.0, 0.06), ({ C.cloth1, C.cloth2, C.cloth3, rgb(240, 240, 230), C.cloth2 })[i], M.Fabric)
		cloth:SetAttribute("Laundry", true)
		cloth.CanCollide = false
	end

	-- campfire still smouldering
	local fire = U.model("Campfire", vil)
	local fp = V + v(8, 0, 8)
	for i = 0, 7 do
		local ang = i * math.pi / 4
		ball(fire, "Stone" .. i, fp + v(math.cos(ang) * 1.6, 0.25, math.sin(ang) * 1.6), 0.8, rgb(90, 80, 76), M.Slate)
	end
	for i = 0, 2 do
		local ang = i * 2.1
		cyl(fire, "Log" .. i, fp + v(math.cos(ang) * 1.0, 0.2, math.sin(ang) * 1.0), fp + v(-math.cos(ang) * 0.6, 0.6, -math.sin(ang) * 0.6), 0.45, rgb(50, 34, 24), M.Wood)
	end
	local ember = ball(fire, "Embers", fp + v(0, 0.3, 0), 1.2, rgb(255, 110, 40), M.Neon)
	ember.CastShadow = false
	local f = U.Instance.new("Fire")
	f.Name = "Flame"
	f.Size = 3
	f.Heat = 6
	f.Color = rgb(255, 150, 60)
	f.SecondaryColor = rgb(255, 60, 20)
	f.Parent = ember
	light(ember, "Campfire", "PointLight", { Range = 14, Brightness = 1.5, Color = rgb(255, 140, 60), Shadows = true })
	local smoke = U.Instance.new("Smoke")
	smoke.Color = rgb(90, 86, 84)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 3
	smoke.Size = 3
	smoke.Parent = ember

	-- footprints leading into HouseA
	local prints = U.model("Footprints", vil)
	for i = 0, 11 do
		local t = i / 11
		local p = (V + v(4, 0, 4)):Lerp(V + v(-10, 0, -17), t)
		local side = (i % 2 == 0) and 0.45 or -0.45
		local dirv = ((V + v(-10, 0, -17)) - (V + v(4, 0, 4))).Unit
		local perp = dirv:Cross(v(0, 1, 0))
		local fpp = part(prints, "Print" .. i, CFrame.lookAt(p + perp * side + v(0, 0.03, 0), p + perp * side + dirv + v(0, 0.03, 0)), v(0.45, 0.04, 0.9), rgb(150, 92, 56), M.Sand)
		fpp.CanCollide = false
		local mesh = U.Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = fpp
	end

	-- the shadow in the lit window of HouseA (the client makes it walk past)
	local shadow = part(vil, "WindowShadow", CFrame.new(0, -500, 0), v(0.6, 1.6, 0.2), rgb(10, 6, 4), M.SmoothPlastic)
	shadow.CanCollide = false
	shadow.Transparency = 1
	shadow.CastShadow = false

	-- lanterns hanging at doors
	for i, p in { V + v(-11, 5.4, -30.5), V + v(16, 4.2, 25) } do
		local lan = ball(vil, "Lantern" .. i, p, 0.6, rgb(255, 200, 120), M.Neon)
		lan.CastShadow = false
		light(lan, "Lantern", "PointLight", { Range = 10, Brightness = 1, Color = rgb(255, 170, 90) })
	end
	return vil
end

----------------------------------------------------------------------------
-- Rick's bunker: hatch in the sand + room underground
----------------------------------------------------------------------------
local BUNKER = v(6000, -400, 0)
Planet.BUNKER = BUNKER

local function buildBunker(world)
	local bk = U.model("Bunker", world)
	-- hatch (hidden until Rick has "built" it)
	local hatch = U.model("Hatch", bk)
	local hp = Planet.VILLAGE + v(-70, 0, 40)
	vcyl(hatch, "Collar", hp, 0.7, 6, C.metal, M.DiamondPlate)
	vcyl(hatch, "Lid", hp + v(0, 0.7, 0), 0.3, 4.4, rgb(90, 96, 104), M.Metal)
	vcyl(hatch, "Wheel", hp + v(0, 1.0, 0), 0.2, 1.8, rgb(200, 60, 40), M.Metal)
	local beacon = ball(hatch, "Beacon", hp + v(2.6, 1.0, 0), 0.5, rgb(255, 60, 40), M.Neon)
	beacon.CastShadow = false
	light(beacon, "BunkerBeacon", "PointLight", { Range = 10, Brightness = 2, Color = rgb(255, 60, 40) })
	for _, d in hatch:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
		end
	end
	hatch:SetAttribute("Hidden", true)

	-- the room
	local room = U.model("BunkerRoom", bk)
	local x0, x1, z0, z1, y0, y1 = BUNKER.X - 11, BUNKER.X + 11, BUNKER.Z - 8, BUNKER.Z + 8, BUNKER.Y, BUNKER.Y + 8
	box(room, "Floor", x0 - 1, y0 - 1, z0 - 1, x1 + 1, y0, z1 + 1, rgb(96, 94, 90), M.Concrete)
	box(room, "Ceiling", x0 - 1, y1, z0 - 1, x1 + 1, y1 + 1, z1 + 1, rgb(80, 80, 78), M.Concrete)
	box(room, "WallW", x0 - 1, y0, z0 - 1, x0, y1, z1 + 1, C.concrete, M.Concrete)
	box(room, "WallE", x1, y0, z0 - 1, x1 + 1, y1, z1 + 1, C.concrete, M.Concrete)
	box(room, "WallN", x0, y0, z0 - 1, x1, y1, z0, C.concrete, M.Concrete)
	box(room, "WallS", x0, y0, z1, x1, y1, z1 + 1, C.concrete, M.Concrete)
	-- ceiling beams + pipes
	for i = -2, 2 do
		box(room, "Beam" .. i, BUNKER.X + i * 4.4 - 0.3, y1 - 0.6, z0, BUNKER.X + i * 4.4 + 0.3, y1, z1, rgb(70, 72, 76), M.Metal)
	end
	cyl(room, "Pipe1", v(x0 + 0.5, y1 - 1.0, z0 + 0.6), v(x1 - 0.5, y1 - 1.0, z0 + 0.6), 0.5, rgb(120, 70, 50), M.CorrodedMetal)
	cyl(room, "Pipe2", v(x0 + 0.5, y1 - 1.6, z0 + 0.6), v(x1 - 0.5, y1 - 1.6, z0 + 0.6), 0.3, rgb(90, 110, 90), M.Metal)
	-- table + map + stools
	local tbl = U.model("BunkerTable", room)
	tbl:SetAttribute("Outline", true)
	box(tbl, "Top", BUNKER.X - 3, y0 + 2.6, BUNKER.Z - 2, BUNKER.X + 3, y0 + 2.85, BUNKER.Z + 2, rgb(110, 80, 56), M.Wood)
	for _, o in { { -2.7, -1.7 }, { 2.5, -1.7 }, { -2.7, 1.5 }, { 2.5, 1.5 } } do
		box(tbl, "Leg", BUNKER.X + o[1], y0, BUNKER.Z + o[2], BUNKER.X + o[1] + 0.25, y0 + 2.6, BUNKER.Z + o[2] + 0.25, rgb(70, 72, 76), M.Metal)
	end
	local map = part(tbl, "Map", CFrame.new(BUNKER.X, y0 + 2.86, BUNKER.Z) * CFrame.Angles(0, math.rad(5), 0), v(4.4, 0.01, 3.0), rgb(226, 214, 180), M.SmoothPlastic)
	local sg = U.surfaceGui(map, Enum.NormalId.Top, 120, 1)
	sg.Name = "MapArt"
	ui("Frame", { BackgroundColor3 = rgb(226, 212, 176), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = sg })
	-- dunes / paths doodles
	for i = 1, 9 do
		ui("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(U.rand() * 0.85, 0, U.rand() * 0.85, 0),
			Size = UDim2.new(0, 60, 0, 30),
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }), ui("UIStroke", { Color = rgb(150, 110, 70), Thickness = 2 }) })
	end
	ui("Frame", { BackgroundColor3 = rgb(40, 90, 200), BorderSizePixel = 0, Position = UDim2.new(0.18, 0, 0.62, 0), Size = UDim2.new(0, 14, 0, 14), Parent = sg }, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	ui("TextLabel", { Name = "HereLabel", BackgroundTransparency = 1, Position = UDim2.new(0.08, 0, 0.7, 0), Size = UDim2.new(0.35, 0, 0.1, 0), Font = Enum.Font.PatrickHand, Text = "B137", TextColor3 = rgb(40, 60, 160), TextScaled = true, Parent = sg })
	-- dashed route
	for i = 0, 9 do
		ui("Frame", { BackgroundColor3 = rgb(200, 40, 40), BorderSizePixel = 0, Position = UDim2.new(0.22 + i * 0.055, 0, 0.6 - i * 0.04, 0), Size = UDim2.new(0, 14, 0, 4), Rotation = -36, Parent = sg })
	end
	ui("TextLabel", { Name = "TargetX", BackgroundTransparency = 1, Position = UDim2.new(0.74, 0, 0.12, 0), Size = UDim2.new(0, 60, 0, 60), Font = Enum.Font.PermanentMarker, Text = "X", TextColor3 = rgb(210, 30, 30), TextScaled = true, Parent = sg })
	ui("TextLabel", { Name = "TargetLabel", BackgroundTransparency = 1, Position = UDim2.new(0.55, 0, 0.32, 0), Size = UDim2.new(0.42, 0, 0.12, 0), Font = Enum.Font.GothamBold, Text = "EVIL MORTY", TextColor3 = rgb(180, 20, 20), TextScaled = true, Parent = sg })
	for _, o in { { 0, 3.6 }, { 0, -3.6 } } do
		vcyl(tbl, "Stool", v(BUNKER.X + o[1], y0, BUNKER.Z + o[2]), 1.7, 1.4, rgb(70, 72, 76), M.Metal)
	end
	part(tbl, "Mug", CFrame.new(BUNKER.X - 2.2, y0 + 3.1, BUNKER.Z + 1.2), v(0.4, 0.5, 0.4), rgb(200, 200, 196), M.SmoothPlastic)
	part(tbl, "Flask", CFrame.new(BUNKER.X + 2.1, y0 + 3.15, BUNKER.Z - 1.0) * CFrame.Angles(0, 0.4, 0), v(0.5, 0.6, 0.2), rgb(160, 160, 170), M.Metal)
	-- hanging lamp (the client makes it swing)
	local lamp = U.model("HangingLamp", room)
	lamp:SetAttribute("Pivot", v(BUNKER.X, y1, BUNKER.Z))
	cyl(lamp, "Cord", v(BUNKER.X, y1, BUNKER.Z), v(BUNKER.X, y1 - 2.4, BUNKER.Z), 0.06, rgb(30, 30, 30), M.Plastic)
	ellipsoid(lamp, "Shade", CFrame.new(BUNKER.X, y1 - 2.6, BUNKER.Z), v(1.6, 0.7, 1.6), rgb(60, 70, 60), M.Metal).CastShadow = false
	local bulb = ball(lamp, "Bulb", v(BUNKER.X, y1 - 2.85, BUNKER.Z), 0.36, rgb(255, 220, 160), M.Neon)
	bulb:SetAttribute("BulbFor", "BunkerLamp")
	bulb.CastShadow = false
	light(bulb, "BunkerLamp", "PointLight", { Range = 18, Brightness = 1.6, Color = rgb(255, 206, 140), Shadows = true })
	-- emergency light
	local em = ball(room, "Emergency", v(x1 - 0.4, y1 - 1.2, BUNKER.Z), 0.6, rgb(255, 40, 30), M.Neon)
	em.CastShadow = false
	light(em, "BunkerEmergency", "PointLight", { Range = 16, Brightness = 0, Color = rgb(255, 40, 30) })
	-- bunk bed, shelves, radio, monitors, ladder
	local bunk = U.model("Bunk", room)
	for i, y in { 0.9, 4.0 } do
		box(bunk, "Bed" .. i, x0 + 0.2, y0 + y, z1 - 3.2, x0 + 7.2, y0 + y + 0.5, z1 - 0.2, rgb(90, 96, 80), M.Fabric)
	end
	for _, x in { x0 + 0.2, x0 + 7.0 } do
		box(bunk, "Post", x, y0, z1 - 3.2, x + 0.2, y0 + 5.2, z1 - 3.0, rgb(70, 72, 76), M.Metal)
	end
	local shelf = U.model("Shelves", room)
	for i = 0, 2 do
		box(shelf, "Board" .. i, x1 - 6, y0 + 1.2 + i * 2.0, z0, x1 - 0.2, y0 + 1.4 + i * 2.0, z0 + 1.4, rgb(70, 72, 76), M.Metal)
		for j = 0, 5 do
			vcyl(shelf, "Can" .. i .. j, v(x1 - 5.5 + j * 0.9, y0 + 1.4 + i * 2.0, z0 + 0.7), 0.8, 0.6, ({ rgb(200, 50, 40), rgb(60, 140, 60), rgb(220, 190, 60) })[(i + j) % 3 + 1], M.Metal)
		end
	end
	local monitors = U.model("Monitors", room)
	for i, z in { -2.4, 2.4 } do
		local scr = part(monitors, "Screen" .. i, CFrame.lookAt(v(x1 - 0.3, y0 + 4.2, BUNKER.Z + z), v(x1 - 5, y0 + 4.2, BUNKER.Z + z)), v(3.2, 2.2, 0.3), rgb(10, 12, 14), M.SmoothPlastic)
		local msg = U.surfaceGui(scr, Enum.NormalId.Front, 100, 0)
		msg.Name = "Static"
		msg.Brightness = 1.4
		ui("Frame", { Name = "Bg", BackgroundColor3 = rgb(30, 34, 36), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = msg })
		ui("TextLabel", { Name = "Label", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.RobotoMono, Text = "NO SIGNAL", TextColor3 = rgb(200, 200, 200), TextScaled = true, Parent = msg })
		light(scr, "MonitorLight" .. i, "SurfaceLight", { Face = Enum.NormalId.Front, Range = 6, Brightness = 0.4, Color = rgb(170, 190, 200) })
	end
	local ladder = U.model("Ladder", room)
	for _, z in { -0.7, 0.7 } do
		box(ladder, "Rail", x0 + 0.3, y0, BUNKER.Z - 6 + z - 0.1, x0 + 0.5, y1, BUNKER.Z - 6 + z + 0.1, rgb(160, 160, 166), M.Metal)
	end
	for k = 1, 7 do
		box(ladder, "Rung" .. k, x0 + 0.3, y0 + k, BUNKER.Z - 6.7, x0 + 0.5, y0 + k + 0.12, BUNKER.Z - 5.3, rgb(160, 160, 166), M.Metal)
	end
	vcyl(ladder, "HatchUp", v(x0 + 1.5, y1 - 0.1, BUNKER.Z - 6), 0.2, 3.2, rgb(90, 96, 104), M.Metal)
	-- dust from the ceiling (the client turns it on when things explode above)
	local dustPart = U.marker(room, "DustSource", CFrame.new(BUNKER.X, y1 - 0.2, BUNKER.Z), v(18, 0.2, 12))
	emitter(dustPart, "Dust", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = U.ColorSequence.new(rgb(170, 160, 150)),
		Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.3), U.NumberSequenceKeypoint.new(1, 1.6) }),
		Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.5), U.NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = U.NumberRange.new(2, 3),
		Speed = U.NumberRange.new(1, 3),
		Acceleration = v(0, -4, 0),
		EmissionDirection = Enum.NormalId.Bottom,
		Rate = 0,
		LightInfluence = 1,
	})
	pcall(function()
		dustPart.Dust.Shape = Enum.ParticleEmitterShape.Box
	end)
	-- seats + eye
	local spots = U.folder("BunkerSpots", bk)
	local rickRoot = v(BUNKER.X, y0 + 1.7 + 1.12, BUNKER.Z - 3.6)
	U.marker(spots, "RickSeat", CFrame.lookAt(rickRoot, rickRoot + v(0, 0, 1)), v(2, 2, 1))
	local mortyRoot = v(BUNKER.X, y0 + 1.7 + 1.0, BUNKER.Z + 3.6)
	U.marker(spots, "MortySeat", CFrame.lookAt(mortyRoot, mortyRoot + v(0, 0, -1)), v(2, 2, 1))
	U.marker(spots, "MortyEye", CFrame.lookAt(mortyRoot + v(0, 1.95, -0.3), v(BUNKER.X, y0 + 3.0, BUNKER.Z - 0.6)), v(0.4, 0.4, 0.4))
	U.marker(spots, "Arrive", CFrame.lookAt(v(x0 + 1.6, y0 + 4.5, BUNKER.Z - 6), v(BUNKER.X, y0 + 3, BUNKER.Z)), v(0.4, 0.4, 0.4))
	return bk
end

----------------------------------------------------------------------------
-- Space: planet B137 seen from orbit
----------------------------------------------------------------------------
Planet.SPACE = v(-9000, 3000, 0)

local function buildSpace(world)
	local sp = U.model("Space", world)
	local center = Planet.SPACE + v(0, -600, -7000)
	local planet = part(sp, "PlanetB137", CFrame.new(center), v(2048, 2048, 2048), rgb(222, 132, 70), M.SmoothPlastic)
	local mesh = U.Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = v(2.2, 2.2, 2.2)
	mesh.Parent = planet
	planet.CanCollide = false
	planet.CastShadow = false
	local atm = part(sp, "Atmosphere", CFrame.new(center), v(2048, 2048, 2048), rgb(255, 170, 90), M.Neon)
	local mesh2 = U.Instance.new("SpecialMesh")
	mesh2.MeshType = Enum.MeshType.Sphere
	mesh2.Scale = v(2.32, 2.32, 2.32)
	mesh2.Parent = atm
	atm.Transparency = 0.9
	atm.CanCollide = false
	atm.CastShadow = false
	-- bands on the planet
	for i, s in { 2.205, 2.21 } do
		local band = part(sp, "Band" .. i, CFrame.new(center) * CFrame.Angles(math.rad(10 + i * 12), 0, math.rad(8)), v(2048, 2048, 2048), rgb(190, 100, 56), M.SmoothPlastic)
		local bm = U.Instance.new("SpecialMesh")
		bm.MeshType = Enum.MeshType.Sphere
		bm.Scale = v(s, s * 0.18, s)
		bm.Parent = band
		band.Transparency = 0.5
		band.CanCollide = false
		band.CastShadow = false
	end
	local moon = part(sp, "Moon", CFrame.new(center + v(3600, 1500, 1800)), v(420, 420, 420), rgb(170, 160, 150), M.Slate)
	moon.Shape = Enum.PartType.Ball
	moon.CanCollide = false
	-- a few rocks floating by
	for i = 1, 14 do
		local p = Planet.SPACE + v(U.randRange(-260, 260), U.randRange(-140, 140), -U.randRange(300, 2200))
		local r = U.randRange(4, 22)
		local rock = part(sp, "Asteroid" .. i, CFrame.new(p) * CFrame.Angles(U.rand() * 6, U.rand() * 6, U.rand() * 6), v(r, r * 0.8, r * 1.1), rgb(110, 100, 94), M.Slate)
		local rm = U.Instance.new("SpecialMesh")
		rm.MeshType = Enum.MeshType.Sphere
		rm.Parent = rock
		rock.CanCollide = false
	end
	return sp
end

----------------------------------------------------------------------------
-- Markers used by the story
----------------------------------------------------------------------------
local function buildMarkers(world)
	local m = U.folder("PlanetSpots", world)
	local O = Planet.ORIGIN
	local V = Planet.VILLAGE
	U.marker(m, "Landing", CFrame.new(O) * CFrame.Angles(0, math.rad(-60), 0), v(1, 1, 1))
	local exitPos = O + v(-2, 3, 9)
	U.marker(m, "MortyExit", CFrame.lookAt(exitPos, exitPos + v(0.6, 0, -1)), v(2, 2, 1))
	-- path Rick walks to the village
	local path = { O + v(6, 0, 4), O + v(36, 0, -6), O + v(72, 0, -22), O + v(104, 0, -36), V + v(-32, 0, 10) }
	for i, p in path do
		U.marker(m, "Path" .. i, CFrame.new(p + v(0, 3 * 1.12, 0)), v(1, 1, 1))
	end
	local look = V + v(-26, 3, 14)
	U.marker(m, "MortyVillage", CFrame.lookAt(look, V + v(0, 3, 0)), v(2, 2, 1))
	U.marker(m, "TitanLanding", CFrame.lookAt(V + v(120, 0, -120), V + v(-30, 0, 30)), v(4, 4, 4))
	U.marker(m, "EntityHome", CFrame.lookAt(V + v(330, 0, -330), V), v(4, 4, 4))
	return m
end

function Planet.build(world)
	local root = U.model("Planet", world)
	buildVillage(root)
	buildBunker(root)
	buildMarkers(root)
	buildSpace(world)
	return root
end

return Planet
