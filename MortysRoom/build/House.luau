--!nocheck
-- The rest of the Smith house: upstairs hallway, stairs, ground floor hall, kitchen + dining table,
-- outside walls and roof, Morty's phone.
-- Upstairs floor Y = 0, ground floor Y = -9. Morty's room is X -10..10, Z -8..8 (upstairs).
local U = require("./Util")

local Vector3, CFrame, Enum = U.Vector3, U.CFrame, U.Enum
local UDim2, UDim = U.UDim2, U.UDim
local rgb, v = U.rgb, U.v
local box, boxL, ellipsoid, ball, cyl, vcyl, part, wall = U.box, U.boxL, U.ellipsoid, U.ball, U.cyl, U.vcyl, U.part, U.wall
local ui = U.ui
local M = Enum.Material

local C = {
	hallWall = rgb(214, 202, 176),
	kitchenWall = rgb(228, 214, 166),
	trim = rgb(240, 236, 226),
	ceiling = rgb(236, 234, 228),
	floor = rgb(128, 88, 60),
	stair = rgb(120, 82, 54),
	stairDark = rgb(92, 62, 42),
	tile = rgb(214, 210, 198),
	cabinet = rgb(186, 150, 104),
	cabinetDoor = rgb(198, 164, 118),
	counter = rgb(70, 66, 64),
	steel = rgb(196, 198, 204),
	white = rgb(244, 244, 240),
	siding = rgb(214, 204, 178),
	roof = rgb(76, 66, 66),
	brass = rgb(206, 168, 84),
	dark = rgb(30, 30, 34),
	chair = rgb(132, 92, 60),
	table = rgb(160, 116, 74),
}

local House = {}

local function facing(center, dir)
	return CFrame.lookAt(center, center + dir)
end

local function interact(model, id, text)
	model:SetAttribute("Interact", id)
	model:SetAttribute("InteractText", text)
end

local function soft(p)
	p.CanCollide = false
	return p
end

----------------------------------------------------------------------------
-- Upstairs hallway + stairs
----------------------------------------------------------------------------
local function buildHallway(house)
	local h = U.model("Hallway", house)
	-- upstairs floor pieces (a hole above the stairs X -9..5, Z 12.4..16)
	box(h, "FloorWalkway", -11, -1, 9, 11, 0, 12.4, C.floor, M.WoodPlanks)
	box(h, "FloorLanding", -11, -1, 12.4, -9, 0, 17, C.floor, M.WoodPlanks)
	box(h, "FloorEast", 5, -1, 12.4, 11, 0, 17, C.floor, M.WoodPlanks)
	box(h, "Ceiling", -11, 8.5, 9, 11, 9.5, 17, C.ceiling, M.Plaster)
	-- runner rug on the walkway
	box(h, "Runner", -8.5, 0, 9.6, 8.5, 0.04, 11.8, rgb(120, 52, 58), M.Carpet)
	box(h, "RunnerEdge", -8.3, 0.04, 9.8, 8.3, 0.05, 11.6, rgb(200, 170, 110), M.Carpet)

	-- side walls go through both floors
	box(h, "WallWest", -11, -9, 9, -10, 8.5, 17, C.hallWall, M.Plaster)
	box(h, "WallEast", 10, -9, 9, 11, 8.5, 17, C.hallWall, M.Plaster)
	-- front wall: front door below, a window upstairs
	wall(h, "WallFront", "x", -11, 11, -9, 8.5, 16, 17, {
		{ 6.5, 9.5, -9, -2.2 },
		{ -3, 0, 3, 6.6 },
	}, C.hallWall, M.Plaster)
	-- upstairs window
	box(h, "WinSill", -3.3, 2.82, 15.6, 0.3, 3.0, 16.2, C.trim)
	box(h, "WinTop", -3.3, 6.6, 15.9, 0.3, 6.85, 16.05, C.trim)
	box(h, "WinL", -3.3, 3.0, 15.9, -3.0, 6.6, 16.05, C.trim)
	box(h, "WinR", 0, 3.0, 15.9, 0.3, 6.6, 16.05, C.trim)
	box(h, "WinMullion", -1.58, 3.0, 16.4, -1.42, 6.6, 16.55, C.trim)
	box(h, "WinGlass", -3, 3, 16.47, 0, 6.6, 16.5, rgb(190, 214, 236), M.Glass, { Transparency = 0.9, CastShadow = false })

	-- stairs: 14 steps going down towards +X
	local st = U.model("Stairs", house)
	for k = 1, 14 do
		local x0 = -9 + (k - 1)
		local top = -0.6 * k
		box(st, "Step" .. k, x0, -9, 12.5, x0 + 1, top, 16, C.stair, M.Wood)
		box(st, "Nose" .. k, x0 - 0.04, top - 0.08, 12.5, x0 + 0.06, top + 0.02, 16, C.stairDark, M.Wood)
		box(st, "Tread" .. k, x0 + 0.06, top, 13.0, x0 + 1, top + 0.02, 15.5, rgb(110, 50, 54), M.Carpet)
	end
	-- banister along the open side of the stairs
	local function railY(x)
		return 3.0 - (x + 9) * (9 / 14)
	end
	cyl(st, "Handrail", v(-9, railY(-9), 12.55), v(5, railY(5), 12.55), 0.2, C.stairDark, M.Wood)
	box(st, "NewelTop", -9.2, 0, 12.4, -8.8, 3.3, 12.75, C.stairDark, M.Wood)
	box(st, "NewelBottom", 4.8, -9, 12.4, 5.2, -5.6, 12.75, C.stairDark, M.Wood)
	ball(st, "NewelCap", v(5.0, -5.5, 12.57), 0.45, C.stairDark, M.Wood)
	for k = 1, 14 do
		local x = -9 + k - 0.5
		local top = -0.6 * k
		cyl(st, "Baluster" .. k, v(x, top, 12.55), v(x, railY(x), 12.55), 0.1, C.white, M.Wood)
	end
	-- upstairs railings around the stair hole
	cyl(st, "RailUp", v(-8.9, 3.2, 12.38), v(5.0, 3.2, 12.38), 0.2, C.stairDark, M.Wood)
	cyl(st, "RailUpEast", v(5.05, 3.2, 12.4), v(5.05, 3.2, 16), 0.2, C.stairDark, M.Wood)
	box(st, "PostCorner", 4.85, 0, 12.2, 5.25, 3.4, 12.6, C.stairDark, M.Wood)
	local x = -8.4
	while x < 4.8 do
		cyl(st, "BalUp", v(x, 0, 12.38), v(x, 3.2, 12.38), 0.09, C.white, M.Wood)
		x += 0.8
	end
	local z = 13.0
	while z < 16 do
		cyl(st, "BalUpE", v(5.05, 0, z), v(5.05, 3.2, z), 0.09, C.white, M.Wood)
		z += 0.8
	end

	-- Summer's door (closed) on the east wall upstairs
	local sd = U.model("SummerDoor", house)
	interact(sd, "SummerDoor", "Summer's room")
	box(sd, "Slab", 9.78, 0.04, 13.0, 9.98, 6.7, 15.8, C.white, M.Wood)
	box(sd, "Casing", 9.88, 0, 12.7, 10.0, 7.0, 16.1, C.trim, M.Wood)
	ball(sd, "Knob", v(9.65, 3.1, 13.4), 0.28, C.brass, M.Metal)
	local sign = part(sd, "Sign", facing(v(9.75, 5.0, 14.4), v(-1, 0, 0)), v(1.6, 0.8, 0.03), rgb(255, 210, 230), M.SmoothPlastic)
	local sg = U.surfaceGui(sign, Enum.NormalId.Front, 200, 1)
	ui("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.PermanentMarker,
		Text = "SUMMER\nNO BOYS!",
		TextColor3 = rgb(200, 40, 110),
		TextScaled = true,
		Parent = sg,
	})

	-- family photos on the walkway wall
	for i, px in { -7.5, -4.5, -1.5 } do
		local frame = part(h, "Photo" .. i, facing(v(px, 5.0, 9.04), v(0, 0, 1)), v(1.6, 1.2, 0.06), rgb(70, 50, 36), M.Wood)
		local pic = part(h, "PhotoPic" .. i, facing(v(px, 5.0, 9.08), v(0, 0, 1)), v(1.3, 0.9, 0.01), rgb(170, 200, 230), M.SmoothPlastic)
		local psg = U.surfaceGui(pic, Enum.NormalId.Front, 100, 1)
		ui("Frame", { BackgroundColor3 = rgb(150 + i * 20, 190, 220 - i * 20), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = psg })
		for j = 1, i + 1 do
			ui("Frame", {
				BackgroundColor3 = rgb(250, 214, 178),
				BorderSizePixel = 0,
				Position = UDim2.new(0.15 + (j - 1) * 0.22, 0, 0.3, 0),
				Size = UDim2.new(0, 16, 0, 16),
				Parent = psg,
			}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			ui("Frame", {
				BackgroundColor3 = rgb(80 + j * 40, 120, 200 - j * 30),
				BorderSizePixel = 0,
				Position = UDim2.new(0.15 + (j - 1) * 0.22, -2, 0.52, 0),
				Size = UDim2.new(0, 20, 0, 30),
				Parent = psg,
			}, { ui("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		end
		local _ = frame
	end

	-- lights
	local up = U.marker(h, "LightUp", CFrame.new(0, 8.0, 12.6))
	vcyl(h, "LampUp", v(0, 8.25, 12.6), 0.25, 1.3, rgb(250, 246, 236), M.SmoothPlastic).CastShadow = false
	local pl = U.Instance.new("PointLight")
	pl.Name = "HallLight"
	pl.Range = 18
	pl.Brightness = 0.9
	pl.Color = rgb(255, 228, 190)
	pl.Shadows = true
	pl.Parent = up
	return h
end

----------------------------------------------------------------------------
-- Ground floor: hall + kitchen
----------------------------------------------------------------------------
local function chair(parent, name, center, yaw)
	local m = U.model(name, parent)
	local base = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	-- seat top at Y = -7.3 (floor -9). Backrest at local +Z (away from the table, which is at local -Z).
	boxL(m, "Seat", base, -0.8, 1.5, -0.8, 0.8, 1.7, 0.8, C.chair, M.Wood)
	for _, p in { { -0.68, -0.68 }, { 0.68, -0.68 }, { -0.68, 0.68 }, { 0.68, 0.68 } } do
		boxL(m, "Leg", base, p[1] - 0.09, 0, p[2] - 0.09, p[1] + 0.09, 1.5, p[2] + 0.09, C.chair, M.Wood)
	end
	boxL(m, "BackL", base, -0.77, 1.7, 0.6, -0.6, 3.9, 0.76, C.chair, M.Wood)
	boxL(m, "BackR", base, 0.6, 1.7, 0.6, 0.77, 3.9, 0.76, C.chair, M.Wood)
	boxL(m, "BackTop", base, -0.8, 3.5, 0.58, 0.8, 3.95, 0.78, C.chair, M.Wood)
	boxL(m, "BackMid", base, -0.6, 2.5, 0.64, 0.6, 2.7, 0.72, C.chair, M.Wood)
	boxL(m, "Cushion", base, -0.7, 1.7, -0.7, 0.7, 1.82, 0.62, rgb(170, 60, 60), M.Fabric)
	m:SetAttribute("Outline", true)
	return m
end

local function plate(parent, name, pos)
	vcyl(parent, name, pos, 0.06, 1.25, C.white, M.SmoothPlastic)
	vcyl(parent, name .. "Rim", pos + v(0, 0.06, 0), 0.02, 0.95, rgb(232, 232, 226), M.SmoothPlastic)
end

local function pancakes(parent, name, pos, count)
	for i = 1, count do
		local p = vcyl(parent, name .. i, pos + v(U.randRange(-0.04, 0.04), 0.08 + (i - 1) * 0.11, U.randRange(-0.04, 0.04)), 0.11, 0.82, rgb(214, 160, 80), M.SmoothPlastic)
		p.CanCollide = false
	end
	local top = pos + v(0, 0.08 + count * 0.11, 0)
	box(parent, name .. "Butter", top.X - 0.12, top.Y, top.Z - 0.1, top.X + 0.12, top.Y + 0.12, top.Z + 0.1, rgb(250, 230, 140), M.SmoothPlastic)
	vcyl(parent, name .. "Syrup", top + v(0.05, -0.005, 0.05), 0.02, 0.6, rgb(150, 76, 26), M.Glass)
end

local function buildKitchen(house)
	local k = U.model("Kitchen", house)
	-- floor (whole ground floor) + kitchen tiles
	box(k, "FloorGround", -11, -10, -9, 11, -9, 17, C.floor, M.WoodPlanks)
	box(k, "Tiles", -10, -9, -8, 10, -8.97, 8, C.tile, M.CeramicTiles)
	box(k, "HallRug", 6.4, -9, 9.6, 9.6, -8.96, 15.6, rgb(64, 84, 120), M.Carpet)
	-- walls
	wall(k, "WallBack", "x", -11, 11, -9, -1, -9, -8, { { -5, -1, -5.6, -2.6 } }, C.kitchenWall, M.Plaster)
	box(k, "WallLeft", -11, -9, -9, -10, -1, 9, C.kitchenWall, M.Plaster)
	box(k, "WallRight", 10, -9, -9, 11, -1, 9, C.kitchenWall, M.Plaster)
	wall(k, "WallDivider", "x", -10, 10, -9, -1, 8, 9, { { 1, 7, -9, -2.2 } }, C.kitchenWall, M.Plaster)
	-- archway trim
	box(k, "ArchL", 0.75, -9, 7.9, 1.0, -2.0, 9.1, C.trim, M.Wood)
	box(k, "ArchR", 7.0, -9, 7.9, 7.25, -2.0, 9.1, C.trim, M.Wood)
	box(k, "ArchTop", 0.75, -2.2, 7.9, 7.25, -1.95, 9.1, C.trim, M.Wood)
	-- baseboards
	box(k, "BaseL", -10, -9, -8, -9.88, -8.5, 8, C.trim)
	box(k, "BaseR", 9.88, -9, -8, 10, -8.5, 8, C.trim)

	-- kitchen window over the sink
	box(k, "KWinSill", -5.3, -5.8, -8.5, -0.7, -5.6, -7.7, C.trim)
	box(k, "KWinTop", -5.3, -2.6, -8.1, -0.7, -2.35, -7.95, C.trim)
	box(k, "KWinL", -5.3, -5.6, -8.1, -5.0, -2.6, -7.95, C.trim)
	box(k, "KWinR", -1.0, -5.6, -8.1, -0.7, -2.6, -7.95, C.trim)
	box(k, "KWinMullion", -3.08, -5.6, -8.6, -2.92, -2.6, -8.45, C.trim)
	box(k, "KWinGlass", -5, -5.6, -8.56, -1, -2.6, -8.53, rgb(190, 214, 236), M.Glass, { Transparency = 0.9, CastShadow = false })

	-- counters along the back wall
	local cab = U.model("Counters", house)
	cab:SetAttribute("Outline", true)
	box(cab, "Base", -9.9, -9, -8, 3.2, -6.25, -6.25, C.cabinet, M.Wood)
	box(cab, "Kick", -9.9, -9, -6.3, 3.2, -8.7, -6.2, C.dark)
	box(cab, "Top", -10, -6.25, -8, 3.35, -6.0, -6.0, C.counter, M.Granite)
	local x = -9.8
	local n = 0
	while x < 3.0 do
		n += 1
		local w = 1.5
		box(cab, "Door" .. n, x, -8.6, -6.3, math.min(x + w, 3.1), -6.5, -6.22, C.cabinetDoor, M.Wood)
		cyl(cab, "Handle" .. n, v(x + w - 0.25, -6.75, -6.15), v(x + w - 0.25, -7.25, -6.15), 0.06, C.steel, M.Metal)
		x += w + 0.08
	end
	-- sink
	box(cab, "Sink", -4.4, -6.02, -7.6, -1.6, -5.99, -6.4, C.steel, M.Metal)
	box(cab, "SinkHole", -4.2, -6.0, -7.4, -1.8, -5.985, -6.6, rgb(90, 92, 98), M.Metal)
	vcyl(cab, "FaucetBase", v(-3.0, -6.0, -7.75), 0.25, 0.25, C.steel, M.Metal)
	cyl(cab, "Faucet", v(-3.0, -5.75, -7.75), v(-3.0, -5.25, -7.75), 0.12, C.steel, M.Metal)
	cyl(cab, "Spout", v(-3.0, -5.25, -7.75), v(-3.0, -5.3, -7.1), 0.12, C.steel, M.Metal)
	-- stove + frying pan with an egg
	box(cab, "Stove", 0.1, -9, -8, 2.3, -6.0, -6.1, rgb(232, 232, 230), M.Metal)
	box(cab, "OvenDoor", 0.25, -8.4, -6.12, 2.15, -6.6, -6.05, rgb(40, 40, 44), M.Glass)
	box(cab, "Cooktop", 0.1, -6.0, -8, 2.3, -5.95, -6.1, rgb(24, 24, 26), M.Glass)
	for _, p in { { 0.65, -7.5 }, { 1.75, -7.5 }, { 0.65, -6.6 }, { 1.75, -6.6 } } do
		vcyl(cab, "Burner", v(p[1], -5.95, p[2]), 0.02, 0.7, rgb(60, 60, 64), M.Metal)
	end
	vcyl(cab, "Pan", v(0.65, -5.93, -6.6), 0.16, 0.9, rgb(36, 36, 40), M.Metal)
	cyl(cab, "PanHandle", v(1.05, -5.84, -6.45), v(1.75, -5.8, -6.15), 0.1, rgb(36, 36, 40), M.Metal)
	vcyl(cab, "EggWhite", v(0.65, -5.77, -6.6), 0.03, 0.55, C.white, M.SmoothPlastic)
	ellipsoid(cab, "EggYolk", CFrame.new(0.65, -5.73, -6.6), v(0.22, 0.12, 0.22), rgb(255, 196, 40), M.SmoothPlastic)
	-- upper cabinets + hood
	box(cab, "UpperL", -9.9, -4.3, -8, -5.4, -1.4, -7.0, C.cabinet, M.Wood)
	box(cab, "UpperR", -0.5, -4.3, -8, 3.2, -1.4, -7.0, C.cabinet, M.Wood)
	box(cab, "UpperLDoor", -9.8, -4.2, -7.02, -5.5, -1.5, -6.96, C.cabinetDoor, M.Wood)
	box(cab, "Hood", 0.1, -3.6, -8, 2.3, -2.8, -7.0, C.steel, M.Metal)
	-- fridge
	local fr = U.model("Fridge", house)
	fr:SetAttribute("Outline", true)
	box(fr, "Body", 4.0, -9, -8, 6.6, -2.6, -5.7, rgb(236, 236, 234), M.SmoothPlastic)
	box(fr, "Gap", 4.0, -5.0, -5.72, 6.6, -4.92, -5.64, rgb(150, 150, 150), M.SmoothPlastic)
	cyl(fr, "HandleTop", v(4.3, -4.6, -5.55), v(4.3, -3.2, -5.55), 0.09, C.steel, M.Metal)
	cyl(fr, "HandleBottom", v(4.3, -6.0, -5.55), v(4.3, -7.6, -5.55), 0.09, C.steel, M.Metal)
	local magnetColors = { rgb(230, 60, 60), rgb(60, 140, 230), rgb(250, 210, 60), rgb(90, 190, 90) }
	for i, c in magnetColors do
		box(fr, "Magnet" .. i, 4.6 + i * 0.35, -3.6 - (i % 2) * 0.4, -5.72, 4.85 + i * 0.35, -3.35 - (i % 2) * 0.4, -5.66, c, M.SmoothPlastic)
	end
	local drawing = part(fr, "Drawing", facing(v(5.6, -6.6, -5.69), v(0, 0, 1)) * CFrame.Angles(0, 0, math.rad(4)), v(1.2, 1.5, 0.01), rgb(250, 250, 245), M.SmoothPlastic)
	local dsg = U.surfaceGui(drawing, Enum.NormalId.Front, 100, 1)
	ui("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.3, 0),
		Font = Enum.Font.PatrickHand,
		Text = "MY FAMILY",
		TextColor3 = rgb(40, 60, 160),
		TextScaled = true,
		Parent = dsg,
	})
	for i = 1, 5 do
		ui("Frame", {
			BackgroundColor3 = ({ rgb(250, 214, 178), rgb(170, 200, 230), rgb(250, 214, 178), rgb(240, 150, 60), rgb(246, 222, 60) })[i],
			BorderSizePixel = 0,
			Position = UDim2.new(0.05 + (i - 1) * 0.18, 0, 0.45, 0),
			Size = UDim2.new(0, 16, 0, 50),
			Parent = dsg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.4, 0) }) })
	end

	-- dining table
	local t = U.model("DiningTable", house)
	t:SetAttribute("Outline", true)
	box(t, "Top", -2, -6.45, -1, 4, -6.25, 3, C.table, M.Wood)
	box(t, "Apron", -1.8, -6.75, -0.8, 3.8, -6.45, 2.8, rgb(140, 100, 64), M.Wood)
	for _, p in { { -1.8, -0.8 }, { 3.6, -0.8 }, { -1.8, 2.6 }, { 3.6, 2.6 } } do
		box(t, "Leg", p[1], -9, p[2], p[1] + 0.22, -6.45, p[2] + 0.22, rgb(140, 100, 64), M.Wood)
	end
	box(t, "Runner", -1.6, -6.25, 0.55, 3.6, -6.24, 1.45, rgb(220, 200, 160), M.Fabric)

	local food = U.model("Breakfast", house)
	local seats = U.folder("Seats", house)
	local SEAT_Y = -7.3
	local function seatMarker(name, center, lookDir)
		local root = center + v(0, 1.0, 0) - lookDir * 0.15
		U.marker(seats, name, CFrame.lookAt(root, root + lookDir), v(2, 2, 1))
	end
	-- Morty (south, facing north), Summer (north), Beth (west end), Jerry (east end)
	local mortyChair = chair(house, "MortyChair", v(1, -9, 4.3), 0)
	interact(mortyChair, "SitDown", "Sit down")
	chair(house, "SummerChair", v(1, -9, -2.3), math.pi)
	chair(house, "BethChair", v(-3.3, -9, 1), -math.pi / 2)
	chair(house, "JerryChair", v(5.3, -9, 1), math.pi / 2)
	seatMarker("Morty", v(1, SEAT_Y, 4.3), v(0, 0, -1))
	seatMarker("Summer", v(1, SEAT_Y, -2.3), v(0, 0, 1))
	seatMarker("Beth", v(-3.3, SEAT_Y, 1), v(1, 0, 0))
	seatMarker("Jerry", v(5.3, SEAT_Y, 1), v(-1, 0, 0))

	local TOP = -6.25
	plate(food, "PlateMorty", v(1, TOP, 2.3))
	pancakes(food, "PancakeMorty", v(1, TOP, 2.3), 3)
	plate(food, "PlateSummer", v(1, TOP, -0.3))
	pancakes(food, "PancakeSummer", v(1, TOP, -0.3), 2)
	plate(food, "PlateBeth", v(-1.3, TOP, 1))
	pancakes(food, "PancakeBeth", v(-1.3, TOP, 1), 2)
	plate(food, "PlateJerry", v(3.3, TOP, 1))
	pancakes(food, "PancakeJerry", v(3.3, TOP, 1), 4)
	-- forks
	for _, p in { { 1.8, 2.3 }, { 0.2, -0.3 }, { -1.3, 1.8 }, { 3.3, 0.2 } } do
		soft(box(food, "Fork", p[1] - 0.04, TOP, p[2] - 0.3, p[1] + 0.04, TOP + 0.03, p[2] + 0.3, C.steel, M.Metal))
	end
	-- juice, coffee, cereal, fruit, newspaper
	vcyl(food, "Pitcher", v(1.6, TOP, 1.0), 0.9, 0.5, rgb(255, 170, 40), M.Glass).Transparency = 0.25
	vcyl(food, "JuiceGlass", v(0.3, TOP, 2.6), 0.5, 0.3, rgb(255, 170, 40), M.Glass).Transparency = 0.2
	vcyl(food, "MugBeth", v(-1.1, TOP, 1.9), 0.42, 0.34, rgb(232, 232, 226), M.SmoothPlastic)
	vcyl(food, "MugJerry", v(3.1, TOP, 1.9), 0.42, 0.34, rgb(70, 120, 200), M.SmoothPlastic)
	local cereal = box(food, "Cereal", -1.75, TOP, -0.75, -1.15, TOP + 1.1, -0.35, rgb(230, 120, 40), M.SmoothPlastic)
	local csg = U.surfaceGui(cereal, Enum.NormalId.Right, 120, 1)
	ui("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.LuckiestGuy,
		Text = "SPACE\nFLAKES",
		TextColor3 = rgb(255, 250, 220),
		TextScaled = true,
		Parent = csg,
	})
	ellipsoid(food, "FruitBowl", CFrame.new(2.4, TOP + 0.2, 1.0), v(1.1, 0.45, 1.1), rgb(200, 190, 170), M.SmoothPlastic)
	for i, c in { rgb(220, 40, 40), rgb(250, 200, 50), rgb(120, 190, 60), rgb(240, 140, 40) } do
		ball(food, "Fruit" .. i, v(2.2 + (i % 2) * 0.35, TOP + 0.45, 0.8 + (i // 2) * 0.35), 0.34, c, M.SmoothPlastic)
	end
	part(food, "Newspaper", CFrame.new(4.0, TOP + 0.02, 0.5) * CFrame.Angles(0, math.rad(12), 0), v(1.3, 0.03, 1.7), rgb(226, 222, 210), M.SmoothPlastic)
	part(food, "SummerPhone", CFrame.new(1.25, TOP + 0.02, -0.95) * CFrame.Angles(0, math.rad(-20), 0), v(0.34, 0.03, 0.66), rgb(240, 120, 170), M.SmoothPlastic)

	-- pendant lamp over the table
	local lamp = U.model("PendantLamp", house)
	cyl(lamp, "Cord", v(1, -1, 1), v(1, -2.45, 1), 0.05, C.dark, M.Plastic)
	ellipsoid(lamp, "Shade", CFrame.new(1, -2.6, 1), v(1.7, 0.75, 1.7), rgb(60, 100, 80), M.Metal).CastShadow = false
	local bulb = ball(lamp, "Bulb", v(1, -2.8, 1), 0.35, rgb(255, 236, 200), M.Neon)
	bulb:SetAttribute("BulbFor", "KitchenLight")
	bulb.CastShadow = false
	local pl = U.Instance.new("PointLight")
	pl.Name = "KitchenLight"
	pl.Range = 16
	pl.Brightness = 1.1
	pl.Color = rgb(255, 222, 176)
	pl.Shadows = true
	pl.Parent = bulb

	-- wall clock
	cyl(k, "WallClock", v(10.0, -3.6, 1.0), v(9.86, -3.6, 1.0), 1.3, rgb(60, 60, 66), M.SmoothPlastic)
	local face = part(k, "ClockFace", facing(v(9.88, -3.6, 1.0), v(-1, 0, 0)), v(1.0, 1.0, 0.01), C.white, M.SmoothPlastic)
	face.Transparency = 1
	local fsg = U.surfaceGui(face, Enum.NormalId.Front, 120, 1)
	ui("Frame", {
		BackgroundColor3 = rgb(250, 250, 246),
		Size = UDim2.new(1, 0, 1, 0),
		Parent = fsg,
	}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	ui("Frame", { BackgroundColor3 = C.dark, BorderSizePixel = 0, AnchorPoint = U.Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 4, 0.32, 0), Parent = fsg })
	ui("Frame", { BackgroundColor3 = C.dark, BorderSizePixel = 0, AnchorPoint = U.Vector2.new(0, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0.22, 0, 0, 4), Parent = fsg })

	-- ground floor hall: front door, coat rack, shoes
	local fd = U.model("FrontDoor", house)
	interact(fd, "FrontDoor", "Front door")
	box(fd, "Slab", 6.55, -9, 16.3, 9.45, -2.25, 16.5, rgb(120, 40, 40), M.Wood)
	box(fd, "Casing", 6.2, -9, 15.88, 9.8, -1.9, 16.0, C.trim, M.Wood)
	ball(fd, "Knob", v(9.0, -5.6, 16.15), 0.3, C.brass, M.Metal)
	box(fd, "Window", 7.4, -4.4, 16.27, 8.6, -3.0, 16.31, rgb(200, 220, 240), M.Glass)
	local rack = U.model("CoatRack", house)
	vcyl(rack, "Pole", v(4.2, -9, 15.2), 5.6, 0.18, C.stairDark, M.Wood)
	ellipsoid(rack, "CoatA", CFrame.new(4.0, -5.0, 15.15), v(1.0, 2.6, 0.7), rgb(90, 110, 70), M.Fabric)
	ellipsoid(rack, "CoatB", CFrame.new(4.45, -5.2, 15.3), v(0.9, 2.3, 0.6), rgb(150, 60, 60), M.Fabric)
	for i = 0, 3 do
		soft(ellipsoid(house, "HallShoe" .. i, CFrame.new(6.9 + i * 0.6, -8.85, 15.1) * CFrame.Angles(0, 0.2 * i, 0), v(0.45, 0.3, 0.9), ({ C.dark, rgb(200, 60, 60), C.white, rgb(80, 60, 40) })[i + 1], M.Leather))
	end

	-- light for the hall
	local hl = U.marker(house, "HallDownLight", CFrame.new(7.5, -1.6, 12.5))
	local hpl = U.Instance.new("PointLight")
	hpl.Name = "HallLight"
	hpl.Range = 16
	hpl.Brightness = 0.8
	hpl.Color = rgb(255, 228, 190)
	hpl.Shadows = true
	hpl.Parent = hl

	-- morning sun through the kitchen window
	local windowCenter = v(-3, -4.1, -8.5)
	local target = v(0.6, -6.3, 1.0)
	local d = target - windowCenter
	local src = U.marker(house, "KitchenSunSource", CFrame.lookAt(windowCenter - d * 2.5, target))
	local sun = U.Instance.new("SpotLight")
	sun.Name = "KitchenSun"
	sun.Face = Enum.NormalId.Front
	sun.Angle = 32
	sun.Range = 40
	sun.Brightness = 5
	sun.Color = rgb(255, 196, 130)
	sun.Shadows = true
	sun.Enabled = false
	sun.Parent = src
	return k
end

----------------------------------------------------------------------------
-- Outside walls, roof, chimney
----------------------------------------------------------------------------
local function buildShell(house)
	local s = U.model("Shell", house)
	local sid = C.siding
	wall(s, "SidingBack", "x", -11.6, 11.6, -9, 9.5, -9.6, -9, {
		{ -0.5, 4.5, 2.9, 7.0 },
		{ -5, -1, -5.6, -2.6 },
	}, sid, M.WoodPlanks)
	wall(s, "SidingFront", "x", -11.6, 11.6, -9, 9.5, 17, 17.6, {
		{ 6.5, 9.5, -9, -2.2 },
		{ -3, 0, 3, 6.6 },
	}, sid, M.WoodPlanks)
	box(s, "SidingLeft", -11.6, -9, -9, -11, 9.5, 17, sid, M.WoodPlanks)
	box(s, "SidingRight", 11, -9, -9, 11.6, 9.5, 17, sid, M.WoodPlanks)
	-- corner boards + floor band
	for _, c in { { -11.8, -9.8 }, { 11.4, -9.8 }, { -11.8, 17.4 }, { 11.4, 17.4 } } do
		box(s, "Corner", c[1], -9, c[2], c[1] + 0.4, 9.5, c[2] + 0.4, C.trim, M.Wood)
	end
	box(s, "BandBack", -11.6, -1.2, -9.75, 11.6, -0.6, -9.6, C.trim, M.Wood)
	box(s, "BandFront", -11.6, -1.2, 17.6, 11.6, -0.6, 17.75, C.trim, M.Wood)
	box(s, "Foundation", -11.8, -9.6, -9.8, 11.8, -9, 17.8, rgb(150, 146, 140), M.Concrete)
	-- outside window trims for the real windows
	local function trim(x1, x2, y1, y2, z, out)
		box(s, "Trim", x1 - 0.3, y2, z, x2 + 0.3, y2 + 0.3, z + out, C.trim, M.Wood)
		box(s, "Trim", x1 - 0.4, y1 - 0.25, z, x2 + 0.4, y1, z + out * 1.5, C.trim, M.Wood)
		box(s, "Trim", x1 - 0.3, y1, z, x1, y2, z + out, C.trim, M.Wood)
		box(s, "Trim", x2, y1, z, x2 + 0.3, y2, z + out, C.trim, M.Wood)
	end
	trim(-0.5, 4.5, 2.9, 7.0, -9.6, -0.15)
	trim(-5, -1, -5.6, -2.6, -9.6, -0.15)
	trim(-3, 0, 3, 6.6, 17.6, 0.15)
	-- fake windows on the side walls
	for _, side in { -1, 1 } do
		local xo = side * 11.6
		for _, zc in { -3, 9 } do
			for _, yc in { -4.6, 4.6 } do
				local x1 = math.min(xo, xo + side * 0.08)
				local x2 = math.max(xo, xo + side * 0.08)
				box(s, "FakeWin", x1, yc - 1.4, zc - 1.2, x2, yc + 1.4, zc + 1.2, rgb(52, 60, 76), M.Glass)
				box(s, "FakeWinTrim", math.min(xo, xo + side * 0.05), yc - 1.6, zc - 1.4, math.max(xo, xo + side * 0.05), yc + 1.6, zc + 1.4, C.trim, M.Wood)
			end
		end
	end

	-- roof: two slabs (ridge along X at Z = 4, 30 degree pitch) + gable wedges
	local R = v(0, 9.5 + 7.85, 4)
	local L = 16.9
	local north = R + v(0, -0.5, -0.866) * (L / 2) + v(0, 0.866, -0.5) * 0.3
	local south = R + v(0, -0.5, 0.866) * (L / 2) + v(0, 0.866, 0.5) * 0.3
	part(s, "RoofNorth", CFrame.new(north) * CFrame.Angles(math.rad(-30), 0, 0), v(25.4, 0.6, L), C.roof, M.Slate)
	part(s, "RoofSouth", CFrame.new(south) * CFrame.Angles(math.rad(30), 0, 0), v(25.4, 0.6, L), C.roof, M.Slate)
	cyl(s, "Ridge", v(-12.7, R.Y + 0.55, 4), v(12.7, R.Y + 0.55, 4), 0.5, rgb(60, 52, 52), M.Slate)
	for _, gx in { -11.3, 11.3 } do
		U.wedge(s, "GableN", CFrame.new(gx, 9.5 + 7.85 / 2, 4 - 6.8), v(0.6, 7.85, 13.6), sid, M.WoodPlanks)
		U.wedge(s, "GableS", CFrame.new(gx, 9.5 + 7.85 / 2, 4 + 6.8) * CFrame.Angles(0, math.pi, 0), v(0.6, 7.85, 13.6), sid, M.WoodPlanks)
	end
	box(s, "Chimney", -7.2, 11, 9.0, -5.4, 20.5, 10.8, rgb(150, 74, 60), M.Brick)
	box(s, "ChimneyCap", -7.4, 20.5, 8.8, -5.2, 20.9, 11.0, rgb(90, 86, 84), M.Concrete)
	-- porch roof over the front door
	part(s, "Porch", CFrame.new(8, -1.6, 18.6) * CFrame.Angles(math.rad(-15), 0, 0), v(5.2, 0.4, 2.4), C.roof, M.Slate)
	local porch = U.marker(s, "PorchLightSource", CFrame.new(8, -2.4, 18.0))
	local ppl = U.Instance.new("PointLight")
	ppl.Name = "PorchLight"
	ppl.Range = 12
	ppl.Brightness = 0.8
	ppl.Color = rgb(255, 200, 140)
	ppl.Parent = porch
	return s
end

----------------------------------------------------------------------------
-- Morty's phone on the nightstand
----------------------------------------------------------------------------
local function buildPhone(house)
	local m = U.model("Phone", house)
	interact(m, "Phone", "Take phone")
	m:SetAttribute("Outline", true)
	local cf = CFrame.new(-4.62, 2.098, -6.8) * CFrame.Angles(0, math.rad(12), 0)
	part(m, "Body", cf, v(0.36, 0.035, 0.72), rgb(26, 26, 30), M.SmoothPlastic)
	local screen = part(m, "Screen", cf * CFrame.new(0, 0.019, 0), v(0.32, 0.004, 0.66), rgb(10, 10, 14), M.SmoothPlastic)
	local sg = U.surfaceGui(screen, Enum.NormalId.Top, 600, 0)
	sg.Brightness = 1.6
	ui("Frame", {
		BackgroundColor3 = rgb(30, 20, 70),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = sg,
	}, {
		ui("UIGradient", {
			Rotation = 90,
			Color = U.ColorSequence.new({ U.ColorSequenceKeypoint.new(0, rgb(80, 40, 160)), U.ColorSequenceKeypoint.new(1, rgb(20, 120, 140)) }),
		}),
	})
	ui("TextLabel", {
		Name = "Time",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.12, 0),
		Size = UDim2.new(1, 0, 0.22, 0),
		Font = Enum.Font.GothamBold,
		Text = "7:00",
		TextColor3 = rgb(255, 255, 255),
		TextScaled = true,
		Parent = sg,
	})
	ui("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.08, 0, 0.5, 0),
		Size = UDim2.new(0.84, 0, 0.1, 0),
		Font = Enum.Font.GothamMedium,
		Text = "GALAXY RAID III  •  battery 4%",
		TextColor3 = rgb(230, 230, 255),
		TextScaled = true,
		Parent = sg,
	})
	local glow = U.Instance.new("SurfaceLight")
	glow.Name = "PhoneGlow"
	glow.Face = Enum.NormalId.Top
	glow.Range = 3
	glow.Brightness = 0.6
	glow.Color = rgb(150, 120, 255)
	glow.Parent = screen
	return m
end

function House.build(house)
	buildHallway(house)
	buildKitchen(house)
	buildShell(house)
	buildPhone(house)
end

return House
