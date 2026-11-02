--!nocheck
-- Builds Morty's bedroom (plus the yard you see through the window) out of parts.
-- Room interior: X -10..10, Z -8..8, floor Y = 0, ceiling Y = 8.5.
-- The window is in the back wall (Z = -8), the door in the front wall (Z = +8).
local U = require("./Util")

local Vector3, CFrame, Enum = U.Vector3, U.CFrame, U.Enum
local UDim2, UDim = U.UDim2, U.UDim
local rgb, v = U.rgb, U.v
local box, boxL, ellipsoid, ball, cyl, vcyl, ecyl, part = U.box, U.boxL, U.ellipsoid, U.ball, U.cyl, U.vcyl, U.ecyl, U.part
local ui = U.ui
local M = Enum.Material

local C = {
	wall = rgb(166, 176, 196),
	trim = rgb(236, 232, 222),
	ceiling = rgb(232, 230, 224),
	floor = rgb(128, 88, 60),
	woodDark = rgb(92, 60, 40),
	wood = rgb(148, 104, 68),
	woodLight = rgb(186, 142, 98),
	blanket = rgb(54, 90, 150),
	blanketDark = rgb(42, 70, 118),
	sheet = rgb(234, 236, 240),
	pillow = rgb(244, 244, 248),
	skin = rgb(250, 214, 178),
	skinShade = rgb(236, 192, 156),
	hair = rgb(110, 68, 36),
	shirt = rgb(246, 222, 60),
	pants = rgb(52, 92, 160),
	curtain = rgb(196, 148, 70),
	curtainShade = rgb(170, 124, 56),
	beige = rgb(214, 204, 180),
	dark = rgb(28, 28, 32),
	metal = rgb(150, 150, 158),
	brass = rgb(206, 168, 84),
	door = rgb(238, 234, 226),
	cork = rgb(184, 142, 92),
	grass = rgb(66, 98, 50),
	leaves = rgb(48, 88, 46),
	bark = rgb(84, 62, 46),
	fence = rgb(150, 118, 84),
	siding = rgb(214, 204, 178),
	roof = rgb(72, 62, 62),
	warmWindow = rgb(255, 206, 128),
}

local Room = {}

local function facing(center, dir)
	return CFrame.lookAt(center, center + dir)
end

local function nocollide(p)
	p.CanCollide = false
	p.CanTouch = false
	return p
end

local function setOutline(model)
	model:SetAttribute("Outline", true)
end

local function interact(model, id, text)
	model:SetAttribute("Interact", id)
	model:SetAttribute("InteractText", text)
end

----------------------------------------------------------------------------
-- Walls, floor, ceiling, trim
----------------------------------------------------------------------------
local function buildStructure(house)
	local s = U.model("Structure", house)
	box(s, "Floor", -11, -1, -9, 11, 0, 9, C.floor, M.WoodPlanks)
	box(s, "Ceiling", -11, 8.5, -9, 11, 9.5, 9, C.ceiling, M.Plaster)
	box(s, "WallLeft", -11, 0, -9, -10, 8.5, 9, C.wall, M.Plaster)
	box(s, "WallRight", 10, 0, -9, 11, 8.5, 9, C.wall, M.Plaster)
	-- Back wall with the window opening (X -0.5..4.5, Y 2.9..7.0)
	box(s, "WallBackL", -10, 0, -9, -0.5, 8.5, -8, C.wall, M.Plaster)
	box(s, "WallBackR", 4.5, 0, -9, 10, 8.5, -8, C.wall, M.Plaster)
	box(s, "WallBackLow", -0.5, 0, -9, 4.5, 2.9, -8, C.wall, M.Plaster)
	box(s, "WallBackHigh", -0.5, 7.0, -9, 4.5, 8.5, -8, C.wall, M.Plaster)
	-- Front wall with the door opening (X 5..8, Y 0..6.8)
	box(s, "WallFrontL", -10, 0, 8, 5, 8.5, 9, C.wall, M.Plaster)
	box(s, "WallFrontR", 8, 0, 8, 10, 8.5, 9, C.wall, M.Plaster)
	box(s, "WallFrontHigh", 5, 6.8, 8, 8, 8.5, 9, C.wall, M.Plaster)

	-- Baseboards
	local t = C.trim
	box(s, "BaseBack", -10, 0, -8, 10, 0.5, -7.88, t)
	box(s, "BaseFrontL", -10, 0, 7.88, 4.7, 0.5, 8, t)
	box(s, "BaseFrontR", 8.3, 0, 7.88, 10, 0.5, 8, t)
	box(s, "BaseLeft", -10, 0, -7.88, -9.88, 0.5, 7.88, t)
	box(s, "BaseRight", 9.88, 0, -7.88, 10, 0.5, 7.88, t)
	-- Crown moulding
	box(s, "CrownBack", -10, 8.25, -8, 10, 8.5, -7.86, t)
	box(s, "CrownFront", -10, 8.25, 7.86, 10, 8.5, 8, t)
	box(s, "CrownLeft", -10, 8.25, -7.86, -9.86, 8.5, 7.86, t)
	box(s, "CrownRight", 9.86, 8.25, -7.86, 10, 8.5, 7.86, t)

	-- Outside of the house below the window (we are on the 2nd floor)
	box(s, "OuterWallLow", -12, -9, -9.6, 12, -1, -9, C.siding, M.WoodPlanks)
	box(s, "OuterWallUp", -12, -1, -9.6, -0.5, 9.5, -9.4, C.siding, M.WoodPlanks)
	box(s, "OuterWallUpR", 4.5, -1, -9.6, 12, 9.5, -9.4, C.siding, M.WoodPlanks)
	box(s, "OuterWallUnder", -0.5, -1, -9.6, 4.5, 2.9, -9.4, C.siding, M.WoodPlanks)
	box(s, "OuterWallOver", -0.5, 7.0, -9.6, 4.5, 9.5, -9.4, C.siding, M.WoodPlanks)
	box(s, "Eave", -12, 9.5, -10.6, 12, 9.9, -8.6, C.roof, M.SmoothPlastic)
	return s
end

----------------------------------------------------------------------------
-- Window, curtains, radiator
----------------------------------------------------------------------------
local function buildWindow(house)
	local w = U.model("Window", house)
	setOutline(w)
	local t = C.trim
	-- inner casing
	box(w, "CasingL", -0.82, 2.9, -8, -0.5, 7.0, -7.88, t)
	box(w, "CasingR", 4.5, 2.9, -8, 4.82, 7.0, -7.88, t)
	box(w, "CasingTop", -0.82, 7.0, -8, 4.82, 7.32, -7.88, t)
	box(w, "Sill", -1.0, 2.72, -8.5, 5.0, 2.9, -7.6, t)
	-- jamb lining
	box(w, "JambL", -0.5, 2.9, -9.4, -0.38, 7.0, -8, t)
	box(w, "JambR", 4.38, 2.9, -9.4, 4.5, 7.0, -8, t)
	box(w, "JambTop", -0.5, 6.88, -9.4, 4.5, 7.0, -8, t)
	-- sash
	box(w, "SashL", -0.38, 2.9, -8.62, -0.18, 6.88, -8.5, t)
	box(w, "SashR", 4.18, 2.9, -8.62, 4.38, 6.88, -8.5, t)
	box(w, "SashTop", -0.38, 6.68, -8.62, 4.38, 6.88, -8.5, t)
	box(w, "SashBottom", -0.38, 2.9, -8.62, 4.38, 3.1, -8.5, t)
	box(w, "MeetingRail", -0.18, 4.82, -8.62, 4.18, 4.98, -8.5, t)
	box(w, "Mullion", 1.92, 3.1, -8.62, 2.08, 6.68, -8.5, t)
	box(w, "Glass", -0.18, 3.1, -8.58, 4.18, 6.68, -8.54, rgb(190, 214, 236), M.Glass, {
		Transparency = 0.92,
		Reflectance = 0.06,
		CastShadow = false,
	})
	-- curtain rod
	cyl(w, "Rod", v(-1.9, 7.55, -7.62), v(5.9, 7.55, -7.62), 0.12, rgb(70, 60, 54), M.Metal)
	ball(w, "RodEndL", v(-1.98, 7.55, -7.62), 0.24, rgb(70, 60, 54), M.Metal)
	ball(w, "RodEndR", v(5.98, 7.55, -7.62), 0.24, rgb(70, 60, 54), M.Metal)
	box(w, "BracketL", -1.75, 7.45, -8, -1.6, 7.6, -7.6, rgb(70, 60, 54), M.Metal)
	box(w, "BracketR", 5.6, 7.45, -8, 5.75, 7.6, -7.6, rgb(70, 60, 54), M.Metal)

	-- curtains: pleated panels (separate models so they can slide)
	local function curtain(name, x0, x1, gatherDir)
		local m = U.model(name, house)
		setOutline(m)
		interact(m, "Curtains", "Open curtains")
		local n = 6
		local wdt = (x1 - x0) / n
		for i = 0, n - 1 do
			local xa = x0 + i * wdt
			local front = (i % 2 == 0)
			local z0 = front and -7.78 or -7.7
			local col = front and C.curtain or C.curtainShade
			local p = box(m, "Pleat" .. i, xa, 2.35, z0 - 0.1, xa + wdt + 0.02, 7.45, z0, col, M.Fabric)
			p.CanCollide = false
		end
		-- hem
		local hem = box(m, "Hem", x0, 2.3, -7.86, x1, 2.5, -7.62, C.curtainShade, M.Fabric)
		hem.CanCollide = false
		m:SetAttribute("SlideDir", gatherDir)
		return m
	end
	curtain("CurtainLeft", -1.8, -0.05, -1)
	curtain("CurtainRight", 4.05, 5.8, 1)

	-- radiator under the window
	local r = U.model("Radiator", house)
	local white = rgb(232, 232, 228)
	for i = 0, 10 do
		local x = 0.45 + i * 0.3
		box(r, "Fin" .. i, x, 0.55, -7.95, x + 0.16, 2.3, -7.7, white, M.Metal)
	end
	cyl(r, "PipeTop", v(0.35, 2.2, -7.82), v(3.75, 2.2, -7.82), 0.16, white, M.Metal)
	cyl(r, "PipeBottom", v(0.35, 0.65, -7.82), v(3.75, 0.65, -7.82), 0.16, white, M.Metal)
	box(r, "FootL", 0.5, 0, -7.92, 0.7, 0.55, -7.74, white, M.Metal)
	box(r, "FootR", 3.4, 0, -7.92, 3.6, 0.55, -7.74, white, M.Metal)
	cyl(r, "Valve", v(3.75, 0.65, -7.82), v(3.95, 0.4, -7.82), 0.14, C.brass, M.Metal)
	return w
end

----------------------------------------------------------------------------
-- Bed + sleeping Morty
----------------------------------------------------------------------------
local HEAD_CENTER = v(-8.15, 3.29, -6.65)

local function buildBed(house)
	local b = U.model("Bed", house)
	setOutline(b)
	for _, p in { { -9.95, -7.55 }, { -6.45, -7.55 }, { -9.95, -1.85 }, { -6.45, -1.85 } } do
		box(b, "Leg", p[1], 0, p[2], p[1] + 0.4, 0.5, p[2] + 0.4, C.woodDark, M.Wood)
	end
	box(b, "Frame", -9.95, 0.5, -7.6, -6.25, 1.2, -1.8, C.woodDark, M.Wood)
	box(b, "Mattress", -9.85, 1.2, -7.55, -6.35, 2.0, -1.85, C.sheet, M.Fabric)
	box(b, "Headboard", -10, 0, -8, -6.2, 3.8, -7.6, C.wood, M.Wood)
	box(b, "HeadboardCap", -10.05, 3.8, -8.05, -6.15, 3.98, -7.55, C.woodDark, M.Wood)
	box(b, "HeadboardInlayL", -9.7, 2.25, -7.6, -8.25, 3.55, -7.56, C.woodLight, M.Wood)
	box(b, "HeadboardInlayR", -7.95, 2.25, -7.6, -6.5, 3.55, -7.56, C.woodLight, M.Wood)
	box(b, "Footboard", -10, 0, -1.8, -6.2, 2.4, -1.4, C.wood, M.Wood)
	box(b, "FootboardCap", -10.05, 2.4, -1.85, -6.15, 2.58, -1.35, C.woodDark, M.Wood)
	box(b, "FootboardInlay", -9.6, 1.0, -1.44, -6.6, 2.1, -1.4, C.woodLight, M.Wood)

	local pillow = ellipsoid(b, "Pillow", CFrame.new(-8.1, 2.32, -6.8), v(2.7, 0.65, 1.35), C.pillow, M.Fabric)
	pillow.CanCollide = false

	-- Blanket while Morty sleeps
	local cover = U.model("BlanketOn", b)
	nocollide(box(cover, "Top", -9.9, 2.0, -5.9, -6.25, 2.18, -1.85, C.blanket, M.Fabric))
	nocollide(box(cover, "Drape", -6.3, 0.9, -5.9, -6.12, 2.18, -1.85, C.blanket, M.Fabric))
	nocollide(box(cover, "DrapeHem", -6.33, 0.85, -5.9, -6.1, 1.0, -1.85, C.blanketDark, M.Fabric))
	nocollide(ellipsoid(cover, "Body", CFrame.new(-8.15, 2.12, -4.05), v(1.9, 1.0, 4.3), C.blanket, M.Fabric))
	nocollide(ellipsoid(cover, "Feet", CFrame.new(-8.1, 2.15, -2.35) * CFrame.Angles(0, 0.1, 0), v(1.7, 0.75, 0.9), C.blanket, M.Fabric))
	nocollide(cyl(cover, "Fold", v(-9.85, 2.27, -5.66), v(-6.3, 2.27, -5.66), 0.4, C.sheet, M.Fabric))
	nocollide(box(cover, "Stripe", -9.9, 2.18, -3.3, -6.25, 2.2, -3.0, rgb(232, 196, 92), M.Fabric))

	-- Blanket after Morty gets up (hidden until then)
	local tossed = U.model("BlanketOff", b)
	nocollide(box(tossed, "Top", -9.9, 2.0, -3.9, -6.25, 2.18, -1.85, C.blanket, M.Fabric))
	nocollide(box(tossed, "Drape", -6.3, 0.9, -3.9, -6.12, 2.18, -1.85, C.blanket, M.Fabric))
	nocollide(cyl(tossed, "Roll", v(-9.9, 2.4, -4.05), v(-6.2, 2.32, -4.2), 0.75, C.blanket, M.Fabric))
	nocollide(ellipsoid(tossed, "Bunch", CFrame.new(-6.9, 2.35, -3.3) * CFrame.Angles(0.2, 0.5, 0.1), v(1.4, 0.6, 1.1), C.blanketDark, M.Fabric))
	nocollide(box(tossed, "Stripe", -9.9, 2.18, -3.3, -6.25, 2.2, -3.0, rgb(232, 196, 92), M.Fabric))
	nocollide(ellipsoid(tossed, "HeadDent", CFrame.new(-8.15, 2.62, -6.7), v(1.4, 0.1, 1.0), rgb(222, 222, 228), M.Fabric))
	for _, d in tossed:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	return b
end

local function buildMortySleeping(house)
	local m = U.model("MortySleeping", house)
	setOutline(m)
	local head = U.model("Head", m)
	-- Lying on his back, top of the head towards the headboard (-Z), face up, turned 25 deg towards the room (+X).
	local headCF = CFrame.new(HEAD_CENTER.X, HEAD_CENTER.Y, HEAD_CENTER.Z, -1, 0, 0, 0, 0, -1, 0, -1, 0)
		* CFrame.Angles(0, math.rad(25), 0)
	local function hp(name, offset, size, color, rot)
		local cf = headCF * CFrame.new(offset)
		if rot then
			cf = cf * rot
		end
		return nocollide(ellipsoid(head, name, cf, size, color, M.SmoothPlastic))
	end
	hp("HeadCore", v(0, 0, 0), v(2.0, 1.8, 1.7), C.skin)
	hp("Hair", v(0, 0.34, 0.07), v(2.08, 1.35, 1.75), C.hair)
	hp("EarL", v(-1.0, -0.05, 0.05), v(0.28, 0.42, 0.3), C.skin)
	hp("EarR", v(1.0, -0.05, 0.05), v(0.28, 0.42, 0.3), C.skin)
	hp("LidL", v(-0.4, 0.04, -0.74), v(0.58, 0.5, 0.3), C.skinShade)
	hp("LidR", v(0.4, 0.04, -0.74), v(0.58, 0.5, 0.3), C.skinShade)
	hp("LashL", v(-0.4, -0.12, -0.84), v(0.5, 0.06, 0.1), rgb(60, 40, 30), CFrame.Angles(0, 0, math.rad(-7)))
	hp("LashR", v(0.4, -0.12, -0.84), v(0.5, 0.06, 0.1), rgb(60, 40, 30), CFrame.Angles(0, 0, math.rad(7)))
	hp("Nose", v(0, -0.22, -0.84), v(0.16, 0.14, 0.12), C.skinShade)
	hp("Mouth", v(0, -0.5, -0.72), v(0.24, 0.16, 0.1), rgb(70, 30, 30))
	head:SetAttribute("EyeOffset", v(0, 0.05, -0.55))

	-- left arm hanging out of the blanket on the room side
	local arm = U.model("Arm", m)
	nocollide(cyl(arm, "Sleeve", v(-7.25, 2.62, -5.3), v(-6.75, 2.6, -4.7), 0.5, C.shirt, M.Fabric))
	nocollide(cyl(arm, "Forearm", v(-6.8, 2.6, -4.72), v(-6.25, 2.45, -4.15), 0.38, C.skin))
	nocollide(cyl(arm, "Wrist", v(-6.27, 2.46, -4.15), v(-6.05, 1.88, -4.0), 0.34, C.skin))
	nocollide(ellipsoid(arm, "Hand", CFrame.new(-6.0, 1.7, -3.97) * CFrame.Angles(0, 0.4, 0.15), v(0.36, 0.5, 0.28), C.skin))
	return m
end

----------------------------------------------------------------------------
-- Nightstand with alarm clock and lamp
----------------------------------------------------------------------------
local function buildNightstand(house)
	local n = U.model("Nightstand", house)
	setOutline(n)
	for _, p in { { -5.85, -7.95 }, { -4.45, -7.95 }, { -5.85, -6.75 }, { -4.45, -6.75 } } do
		box(n, "Leg", p[1], 0, p[2], p[1] + 0.2, 0.25, p[2] + 0.2, C.woodDark, M.Wood)
	end
	box(n, "Body", -5.9, 0.25, -8, -4.2, 2.0, -6.5, C.wood, M.Wood)
	box(n, "Top", -5.95, 2.0, -8.02, -4.15, 2.08, -6.45, C.woodDark, M.Wood)
	box(n, "Drawer", -5.75, 1.2, -6.5, -4.35, 1.85, -6.44, C.woodLight, M.Wood)
	ball(n, "Knob", v(-5.05, 1.52, -6.38), 0.16, C.brass, M.Metal)
	box(n, "Shelf", -5.75, 0.45, -6.5, -4.35, 0.55, -6.46, C.woodDark, M.Wood)
	-- book lying on the shelf space
	box(n, "Book", -5.6, 0.55, -7.6, -4.6, 0.75, -6.7, rgb(150, 50, 50), M.SmoothPlastic)

	-- Alarm clock (interactive)
	local clock = U.model("AlarmClock", house)
	setOutline(clock)
	interact(clock, "AlarmClock", "Turn off alarm")
	local center = v(-5.3, 2.32, -6.98)
	local cf = facing(center, v(-1, 0, 0.6).Unit)
	local body = part(clock, "Body", cf, v(0.95, 0.48, 0.42), rgb(34, 34, 40), M.SmoothPlastic)
	part(clock, "Bezel", cf * CFrame.new(0, 0, -0.22), v(0.8, 0.34, 0.04), rgb(16, 16, 18), M.SmoothPlastic)
	local face = part(clock, "Face", cf * CFrame.new(0, 0, -0.245), v(0.72, 0.28, 0.01), rgb(40, 8, 8), M.SmoothPlastic)
	part(clock, "Snooze", cf * CFrame.new(0, 0.26, 0.02), v(0.5, 0.05, 0.18), rgb(70, 70, 80), M.SmoothPlastic)
	local sg = U.surfaceGui(face, Enum.NormalId.Front, 300, 0)
	sg.Name = "ClockFace"
	sg.Brightness = 2.2
	ui("Frame", { BackgroundColor3 = rgb(24, 4, 4), Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0, Parent = sg })
	ui("TextLabel", {
		Name = "ClockText",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.Arcade,
		Text = "3:14",
		TextColor3 = rgb(255, 54, 40),
		TextScaled = true,
		Parent = sg,
	})
	ui("TextLabel", {
		Name = "AmPm",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.04, 0, 0.06, 0),
		Size = UDim2.new(0.12, 0, 0.25, 0),
		Font = Enum.Font.Arcade,
		Text = "AM",
		TextColor3 = rgb(255, 54, 40),
		TextScaled = true,
		Parent = sg,
	})
	local glow = U.Instance.new("SurfaceLight")
	glow.Name = "ClockGlow"
	glow.Face = Enum.NormalId.Front
	glow.Color = rgb(255, 60, 40)
	glow.Brightness = 0.6
	glow.Range = 5
	glow.Angle = 120
	glow.Parent = face

	-- Bedside lamp (interactive)
	local lamp = U.model("BedsideLamp", house)
	setOutline(lamp)
	interact(lamp, "NightLamp", "Toggle lamp")
	vcyl(lamp, "Base", v(-4.6, 2.08, -7.6), 0.1, 0.6, rgb(60, 52, 48), M.Metal)
	vcyl(lamp, "Stem", v(-4.6, 2.18, -7.6), 0.72, 0.09, C.brass, M.Metal)
	local shade = vcyl(lamp, "Shade", v(-4.6, 2.78, -7.6), 0.55, 0.8, rgb(236, 220, 186), M.Fabric)
	shade.CastShadow = false
	local bulb = ball(lamp, "Bulb", v(-4.6, 2.85, -7.6), 0.24, rgb(255, 236, 200), M.SmoothPlastic)
	bulb:SetAttribute("BulbFor", "NightLamp")
	bulb.CastShadow = false
	local light = U.Instance.new("PointLight")
	light.Name = "NightLamp"
	light.Color = rgb(255, 190, 120)
	light.Range = 9
	light.Brightness = 0.9
	light.Shadows = true
	light.Enabled = false
	light.Parent = bulb
	return n
end

----------------------------------------------------------------------------
-- Desk, computer, desk lamp, shelf, chair
----------------------------------------------------------------------------
local function buildDesk(house)
	local d = U.model("Desk", house)
	setOutline(d)
	box(d, "Top", 6.8, 2.45, -6.2, 10, 2.65, -1.0, C.woodLight, M.Wood)
	for _, p in { { 6.9, -6.1 }, { 6.9, -1.32 }, { 9.68, -6.1 } } do
		box(d, "Leg", p[1], 0, p[2], p[1] + 0.22, 2.45, p[2] + 0.22, C.wood, M.Wood)
	end
	box(d, "Drawers", 7.0, 0.12, -2.4, 9.98, 2.45, -1.05, C.wood, M.Wood)
	for i, y in { 0.3, 1.1, 1.85 } do
		box(d, "DrawerFront" .. i, 6.93, y, -2.32, 7.0, y + 0.65, -1.12, C.woodLight, M.Wood)
		cyl(d, "Handle" .. i, v(6.88, y + 0.33, -1.95), v(6.88, y + 0.33, -1.5), 0.07, C.metal, M.Metal)
	end
	box(d, "Modesty", 9.75, 0.6, -6.1, 9.95, 2.45, -2.4, C.wood, M.Wood)

	-- CRT monitor (interactive)
	local mon = U.model("Monitor", house)
	setOutline(mon)
	interact(mon, "Monitor", "Use computer")
	box(mon, "Body", 8.25, 2.65, -5.0, 9.95, 4.75, -2.6, C.beige, M.SmoothPlastic)
	box(mon, "Bezel", 8.12, 2.65, -5.0, 8.25, 4.75, -2.6, rgb(200, 190, 166), M.SmoothPlastic)
	box(mon, "Chin", 8.06, 2.65, -4.9, 8.12, 2.82, -2.7, rgb(190, 180, 156), M.SmoothPlastic)
	ball(mon, "Power", v(8.07, 2.73, -2.9), 0.08, rgb(80, 255, 120), M.Neon)
	local screen = part(mon, "Screen", facing(v(8.09, 3.72, -3.8), v(-1, 0, 0)), v(1.9, 1.5, 0.04), rgb(10, 14, 22), M.SmoothPlastic)
	screen.CastShadow = false
	local sg = U.surfaceGui(screen, Enum.NormalId.Front, 200, 0)
	sg.Name = "ScreenSaver"
	sg.Brightness = 1.6
	ui("Frame", {
		Name = "Bg",
		BackgroundColor3 = rgb(8, 14, 30),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = sg,
	}, {
		ui("UIGradient", {
			Rotation = 90,
			Color = U.ColorSequence.new({
				U.ColorSequenceKeypoint.new(0, rgb(16, 30, 60)),
				U.ColorSequenceKeypoint.new(1, rgb(4, 6, 14)),
			}),
		}),
	})
	ui("TextLabel", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0.42, 0),
		AnchorPoint = U.Vector2 and U.Vector2.new(0.5, 0.5) or nil,
		Size = UDim2.new(0.8, 0, 0.22, 0),
		Font = Enum.Font.RobotoMono,
		Text = "MORTY-OS",
		TextColor3 = rgb(120, 255, 150),
		TextScaled = true,
		Parent = sg,
	})
	ui("TextLabel", {
		Name = "Hint",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.1, 0, 0.62, 0),
		Size = UDim2.new(0.8, 0, 0.1, 0),
		Font = Enum.Font.RobotoMono,
		Text = "zzz... screen saver",
		TextColor3 = rgb(90, 170, 110),
		TextScaled = true,
		Parent = sg,
	})
	local glow = U.Instance.new("SurfaceLight")
	glow.Name = "MonitorGlow"
	glow.Face = Enum.NormalId.Front
	glow.Color = rgb(120, 170, 255)
	glow.Brightness = 0.8
	glow.Range = 9
	glow.Angle = 100
	glow.Shadows = true
	glow.Parent = screen

	-- keyboard, mouse, mug, papers
	box(d, "Keyboard", 7.1, 2.65, -4.7, 7.8, 2.75, -2.9, rgb(204, 198, 182), M.SmoothPlastic)
	box(d, "Keys", 7.18, 2.75, -4.6, 7.72, 2.78, -3.0, rgb(150, 145, 134), M.SmoothPlastic)
	box(d, "MousePad", 7.05, 2.65, -2.6, 7.85, 2.67, -1.8, rgb(40, 52, 90), M.Fabric)
	ellipsoid(d, "Mouse", CFrame.new(7.45, 2.72, -2.2), v(0.24, 0.14, 0.36), rgb(204, 198, 182), M.SmoothPlastic)
	vcyl(d, "Mug", v(7.25, 2.65, -5.75), 0.45, 0.36, rgb(186, 62, 52), M.SmoothPlastic)
	vcyl(d, "Coffee", v(7.25, 3.1, -5.75), 0.012, 0.28, rgb(60, 36, 24), M.SmoothPlastic)
	cyl(d, "MugHandle", v(7.45, 2.95, -5.75), v(7.45, 2.75, -5.75), 0.08, rgb(186, 62, 52), M.SmoothPlastic)
	part(d, "Paper1", CFrame.new(7.45, 2.655, -5.0) * CFrame.Angles(0, math.rad(8), 0), v(0.75, 0.01, 1.0), rgb(246, 246, 240), M.SmoothPlastic)
	part(d, "Paper2", CFrame.new(7.55, 2.665, -4.95) * CFrame.Angles(0, math.rad(-14), 0), v(0.75, 0.01, 1.0), rgb(240, 236, 220), M.SmoothPlastic)

	-- desk lamp (interactive)
	local lamp = U.model("DeskLamp", house)
	setOutline(lamp)
	interact(lamp, "DeskLamp", "Toggle desk lamp")
	local green = rgb(50, 100, 76)
	vcyl(lamp, "Base", v(9.55, 2.65, -5.75), 0.1, 0.7, green, M.Metal)
	cyl(lamp, "Arm1", v(9.55, 2.72, -5.75), v(9.2, 3.95, -5.6), 0.08, C.metal, M.Metal)
	ball(lamp, "Joint", v(9.2, 3.95, -5.6), 0.16, C.metal, M.Metal)
	cyl(lamp, "Arm2", v(9.2, 3.95, -5.6), v(8.45, 4.22, -5.42), 0.08, C.metal, M.Metal)
	cyl(lamp, "Shade", v(8.5, 4.28, -5.43), v(8.12, 3.86, -5.33), 0.55, green, M.Metal)
	local bulb = ball(lamp, "Bulb", v(8.14, 3.86, -5.33), 0.22, rgb(255, 236, 200), M.SmoothPlastic)
	bulb:SetAttribute("BulbFor", "DeskLamp")
	bulb.CastShadow = false
	local lp = U.marker(lamp, "LightSource", CFrame.lookAt(v(8.02, 3.74, -5.28), v(7.35, 2.65, -4.2)))
	local spot = U.Instance.new("SpotLight")
	spot.Name = "DeskLamp"
	spot.Face = Enum.NormalId.Front
	spot.Angle = 80
	spot.Range = 10
	spot.Brightness = 2.2
	spot.Color = rgb(255, 196, 128)
	spot.Shadows = true
	spot.Parent = lp
	local fill = U.Instance.new("PointLight")
	fill.Name = "DeskLamp"
	fill.Range = 6
	fill.Brightness = 0.35
	fill.Color = rgb(255, 196, 128)
	fill.Parent = bulb
	return d
end

local function buildShelf(house)
	local s = U.model("Shelf", house)
	setOutline(s)
	box(s, "Plank", 8.9, 5.5, -6.2, 10, 5.65, -1.4, C.woodLight, M.Wood)
	box(s, "BracketA", 9.75, 5.05, -5.6, 9.88, 5.5, -5.45, C.metal, M.Metal)
	box(s, "BracketB", 9.75, 5.05, -2.15, 9.88, 5.5, -2.0, C.metal, M.Metal)
	local colors = {
		rgb(170, 52, 52), rgb(52, 96, 170), rgb(232, 196, 70), rgb(60, 140, 90), rgb(110, 70, 140),
		rgb(220, 120, 50), rgb(40, 40, 46), rgb(200, 200, 190), rgb(70, 150, 170), rgb(150, 40, 70),
	}
	local z = -6.05
	for i = 1, 11 do
		local w = U.randRange(0.18, 0.34)
		local h = U.randRange(0.75, 1.15)
		local col = colors[(i - 1) % #colors + 1]
		if i == 9 then
			-- a leaning book
			part(s, "Book" .. i, CFrame.new(9.45, 5.65 + h * 0.5 - 0.04, z + 0.25) * CFrame.Angles(math.rad(-16), 0, 0), v(0.85, h, w), col, M.SmoothPlastic)
			z += 0.55
		else
			box(s, "Book" .. i, 9.05, 5.65, z, 9.9, 5.65 + h, z + w, col, M.SmoothPlastic)
			z += w + 0.02
		end
	end
	-- trophy
	vcyl(s, "TrophyBase", v(9.45, 5.65, -2.45), 0.2, 0.42, rgb(60, 50, 40), M.Wood)
	vcyl(s, "TrophyStem", v(9.45, 5.85, -2.45), 0.3, 0.1, C.brass, M.Metal)
	ellipsoid(s, "TrophyCup", CFrame.new(9.45, 6.3, -2.45), v(0.42, 0.4, 0.42), C.brass, M.Metal)
	-- small plant
	vcyl(s, "Pot", v(9.45, 5.65, -1.75), 0.38, 0.42, rgb(176, 98, 64), M.SmoothPlastic)
	ball(s, "Leaf1", v(9.42, 6.18, -1.78), 0.42, rgb(70, 140, 70), M.LeafyGrass)
	ball(s, "Leaf2", v(9.55, 6.3, -1.66), 0.32, rgb(80, 160, 80), M.LeafyGrass)
	ball(s, "Leaf3", v(9.32, 6.32, -1.7), 0.3, rgb(60, 130, 64), M.LeafyGrass)
	return s
end

local function buildChair(house)
	local c = U.model("Chair", house)
	setOutline(c)
	local base = CFrame.new(5.75, 0, -3.7) * CFrame.Angles(0, math.rad(-20), 0)
	local fabric = rgb(58, 60, 72)
	local black = rgb(30, 30, 34)
	boxL(c, "Seat", base, -0.7, 1.55, -0.7, 0.7, 1.82, 0.7, fabric, M.Fabric)
	boxL(c, "Back", base, -0.78, 1.95, -0.62, -0.6, 3.6, 0.62, fabric, M.Fabric)
	ellipsoid(c, "BackTop", base * CFrame.new(-0.69, 3.6, 0), v(0.18, 0.4, 1.24), fabric, M.Fabric)
	boxL(c, "BackPost", base, -0.75, 1.6, -0.08, -0.62, 2.0, 0.08, black, M.Metal)
	part(c, "Post", base * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), v(1.25, 0.2, 0.2), black, M.Metal).Shape = Enum.PartType.Cylinder
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		local tip = base * CFrame.new(math.cos(a) * 1.0, 0.18, math.sin(a) * 1.0)
		local center = base * CFrame.new(0, 0.3, 0)
		cyl(c, "Leg" .. i, center.Position, tip.Position, 0.12, black, M.Metal)
		ball(c, "Wheel" .. i, tip.Position - v(0, 0.08, 0), 0.2, black, M.Rubber)
	end
	return c
end

----------------------------------------------------------------------------
-- Dresser, door, light switch
----------------------------------------------------------------------------
local function buildDresser(house)
	local d = U.model("Dresser", house)
	setOutline(d)
	box(d, "Plinth", -9.1, 0, 6.5, -5.3, 0.15, 7.95, C.woodDark, M.Wood)
	box(d, "Body", -9.2, 0.15, 6.4, -5.2, 3.1, 8, C.wood, M.Wood)
	box(d, "Top", -9.28, 3.1, 6.32, -5.12, 3.2, 8, C.woodDark, M.Wood)
	for i, y in { 0.35, 1.3, 2.25 } do
		box(d, "Drawer" .. i, -9.05, y, 6.32, -5.35, y + 0.75, 6.4, C.woodLight, M.Wood)
		ball(d, "KnobA" .. i, v(-8.2, y + 0.38, 6.27), 0.16, C.brass, M.Metal)
		ball(d, "KnobB" .. i, v(-6.2, y + 0.38, 6.27), 0.16, C.brass, M.Metal)
	end
	-- photo frame
	local pf = CFrame.new(-8.55, 3.55, 7.55) * CFrame.Angles(math.rad(-10), math.rad(180), 0)
	part(d, "PhotoFrame", pf, v(0.9, 0.7, 0.07), rgb(70, 50, 36), M.Wood)
	local photo = part(d, "Photo", pf * CFrame.new(0, 0, -0.04), v(0.72, 0.52, 0.01), rgb(150, 190, 220), M.SmoothPlastic)
	local sg = U.surfaceGui(photo, Enum.NormalId.Front, 200, 1)
	ui("Frame", { BackgroundColor3 = rgb(150, 196, 230), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = sg })
	ui("Frame", { BackgroundColor3 = rgb(110, 170, 90), BorderSizePixel = 0, Position = UDim2.new(0, 0, 0.72, 0), Size = UDim2.new(1, 0, 0.28, 0), Parent = sg })
	local people = {
		{ 0.18, 0.3, rgb(250, 214, 178), rgb(160, 200, 240) },
		{ 0.36, 0.4, rgb(250, 214, 178), rgb(246, 222, 60) },
		{ 0.55, 0.28, rgb(250, 214, 178), rgb(220, 90, 120) },
		{ 0.74, 0.34, rgb(250, 214, 178), rgb(120, 170, 120) },
	}
	for i, pp in people do
		local hgt = pp[2]
		ui("Frame", {
			Name = "Body" .. i,
			BackgroundColor3 = pp[4],
			BorderSizePixel = 0,
			Position = UDim2.new(pp[1], -7, 0.92 - hgt, 0),
			Size = UDim2.new(0, 14, hgt, 0),
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0, 5) }) })
		ui("Frame", {
			Name = "Head" .. i,
			BackgroundColor3 = pp[3],
			BorderSizePixel = 0,
			Position = UDim2.new(pp[1], -8, 0.92 - hgt - 0.16, 0),
			Size = UDim2.new(0, 16, 0, 16),
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	-- piggy bank
	local pig = rgb(240, 160, 176)
	ellipsoid(d, "Pig", CFrame.new(-6.0, 3.52, 7.3), v(0.62, 0.5, 0.82), pig, M.SmoothPlastic)
	part(d, "Snout", CFrame.new(-6.0, 3.52, 6.86) * CFrame.Angles(0, math.rad(90), 0), v(0.08, 0.2, 0.2), pig, M.SmoothPlastic).Shape = Enum.PartType.Cylinder
	ball(d, "EarL", v(-6.15, 3.78, 7.1), 0.14, pig, M.SmoothPlastic)
	ball(d, "EarR", v(-5.85, 3.78, 7.1), 0.14, pig, M.SmoothPlastic)
	for _, o in { { -6.15, 7.1 }, { -5.85, 7.1 }, { -6.15, 7.5 }, { -5.85, 7.5 } } do
		vcyl(d, "PigLeg", v(o[1], 3.2, o[2]), 0.15, 0.12, pig, M.SmoothPlastic)
	end
	-- comics stack
	local comicColors = { rgb(220, 60, 50), rgb(60, 120, 220), rgb(240, 200, 60), rgb(80, 180, 90), rgb(160, 80, 200) }
	for i = 1, 5 do
		part(d, "Comic" .. i, CFrame.new(-7.25, 3.2 + i * 0.045, 7.35) * CFrame.Angles(0, math.rad(U.randRange(-14, 14)), 0), v(0.85, 0.04, 1.15), comicColors[i], M.SmoothPlastic)
	end
	return d
end

local function buildDoor(house)
	local d = U.model("Door", house)
	setOutline(d)
	interact(d, "Door", "Open door")
	local t = C.trim
	box(d, "JambL", 5.0, 0, 8, 5.12, 6.8, 9, t)
	box(d, "JambR", 7.88, 0, 8, 8.0, 6.8, 9, t)
	box(d, "JambTop", 5.0, 6.68, 8, 8.0, 6.8, 9, t)
	box(d, "CasingL", 4.7, 0, 7.88, 5.0, 7.1, 8.0, t)
	box(d, "CasingR", 8.0, 0, 7.88, 8.3, 7.1, 8.0, t)
	box(d, "CasingTop", 4.7, 6.8, 7.88, 8.3, 7.1, 8.0, t)
	box(d, "Slab", 5.13, 0.04, 8.3, 7.87, 6.67, 8.48, C.door, M.Wood)
	box(d, "PanelTL", 5.45, 3.9, 8.25, 6.38, 6.3, 8.3, C.door, M.Wood)
	box(d, "PanelTR", 6.62, 3.9, 8.25, 7.55, 6.3, 8.3, C.door, M.Wood)
	box(d, "PanelBL", 5.45, 0.5, 8.25, 6.38, 3.5, 8.3, C.door, M.Wood)
	box(d, "PanelBR", 6.62, 0.5, 8.25, 7.55, 3.5, 8.3, C.door, M.Wood)
	cyl(d, "Rosette", v(7.5, 3.1, 8.3), v(7.5, 3.1, 8.24), 0.36, C.brass, M.Metal)
	cyl(d, "KnobNeck", v(7.5, 3.1, 8.24), v(7.5, 3.1, 8.12), 0.1, C.brass, M.Metal)
	ball(d, "Knob", v(7.5, 3.1, 8.06), 0.3, C.brass, M.Metal)
	-- sign
	local sign = part(d, "Sign", facing(v(6.5, 5.15, 8.22), v(0, 0, -1)) * CFrame.Angles(0, 0, math.rad(-3)), v(1.5, 0.75, 0.04), rgb(250, 248, 240), M.SmoothPlastic)
	local sg = U.surfaceGui(sign, Enum.NormalId.Front, 200, 1)
	ui("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.05, 0, 0.04, 0),
		Size = UDim2.new(0.9, 0, 0.5, 0),
		Font = Enum.Font.PermanentMarker,
		Text = "MORTY'S ROOM",
		TextColor3 = rgb(30, 30, 40),
		TextScaled = true,
		Parent = sg,
	})
	ui("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.15, 0, 0.52, 0),
		Size = UDim2.new(0.7, 0, 0.42, 0),
		Font = Enum.Font.PermanentMarker,
		Text = "KEEP OUT!!",
		TextColor3 = rgb(200, 40, 40),
		TextScaled = true,
		Rotation = -3,
		Parent = sg,
	})

	-- light switch
	local sw = U.model("LightSwitch", house)
	interact(sw, "LightSwitch", "Light switch")
	box(sw, "Plate", 4.2, 3.6, 7.92, 4.55, 4.15, 8.0, rgb(240, 238, 232), M.SmoothPlastic)
	local toggle = box(sw, "Toggle", 4.33, 3.88, 7.86, 4.42, 4.0, 7.92, rgb(250, 250, 248), M.SmoothPlastic)
	toggle:SetAttribute("OnOffset", 0.1)
	return d
end

----------------------------------------------------------------------------
-- Rug, clutter, posters, corkboard, ceiling lamp
----------------------------------------------------------------------------
local function poster(parent, name, center, dir, w, h, build)
	local p = part(parent, name, facing(center, dir), v(w, h, 0.03), rgb(240, 240, 240), M.SmoothPlastic)
	p.CanCollide = false
	local sg = U.surfaceGui(p, Enum.NormalId.Front, 100, 1)
	build(sg, w * 100, h * 100)
	return p
end

local function buildDecor(house)
	local d = U.model("Decor", house)
	-- rug
	box(d, "RugOuter", -4.0, 0, -2.6, 4.0, 0.05, 3.0, rgb(96, 46, 52), M.Carpet)
	box(d, "RugStripe", -3.75, 0, -2.35, 3.75, 0.06, 2.75, rgb(214, 182, 120), M.Carpet)
	box(d, "RugInner", -3.55, 0, -2.15, 3.55, 0.07, 2.55, rgb(146, 70, 66), M.Carpet)
	box(d, "RugCenter", -1.4, 0, -0.6, 1.4, 0.075, 1.0, rgb(214, 182, 120), M.Carpet)

	-- ceiling lamp (light switch controls it)
	local lamp = U.model("CeilingLamp", house)
	vcyl(lamp, "Base", v(0, 8.4, 0), 0.1, 2.0, rgb(230, 228, 222), M.SmoothPlastic)
	local dome = ellipsoid(lamp, "Dome", CFrame.new(0, 8.38, 0), v(1.8, 0.5, 1.8), rgb(250, 246, 236), M.SmoothPlastic)
	dome:SetAttribute("BulbFor", "CeilingLight")
	dome.CastShadow = false
	local lp = U.marker(lamp, "LightSource", CFrame.new(0, 7.95, 0))
	local pl = U.Instance.new("PointLight")
	pl.Name = "CeilingLight"
	pl.Range = 24
	pl.Brightness = 1.15
	pl.Color = rgb(255, 238, 214)
	pl.Shadows = true
	pl.Enabled = false
	pl.Parent = lp

	-- clutter (non-colliding so you don't trip)
	local function soft(p)
		p.CanCollide = false
		return p
	end
	soft(ellipsoid(d, "Jeans", CFrame.new(-5.2, 0.16, 0.6) * CFrame.Angles(0, 0.6, 0), v(1.7, 0.3, 0.9), C.pants, M.Fabric))
	soft(ellipsoid(d, "Shirt", CFrame.new(-5.0, 0.3, 0.3) * CFrame.Angles(0.05, -0.4, 0.04), v(1.25, 0.26, 1.05), C.shirt, M.Fabric))
	soft(ellipsoid(d, "Sock", CFrame.new(-4.3, 0.06, 1.3) * CFrame.Angles(0, 1.2, 0), v(0.6, 0.12, 0.22), rgb(240, 240, 240), M.Fabric))
	local function sneaker(name, pos, yaw)
		local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		soft(boxL(d, name .. "Sole", base, -0.24, 0, -0.5, 0.24, 0.12, 0.5, rgb(244, 244, 244), M.Rubber))
		soft(ellipsoid(d, name .. "Upper", base * CFrame.new(0, 0.2, 0.06), v(0.46, 0.36, 0.86), rgb(236, 236, 236), M.Leather))
		soft(ellipsoid(d, name .. "Toe", base * CFrame.new(0, 0.14, -0.36), v(0.42, 0.22, 0.3), rgb(80, 120, 200), M.Leather))
	end
	sneaker("ShoeL", v(-5.35, 0, -2.75), math.rad(15))
	sneaker("ShoeR", v(-4.7, 0, -2.35), math.rad(-25))
	-- backpack
	local bp = rgb(170, 64, 54)
	soft(boxL(d, "Backpack", CFrame.new(6.3, 0, -0.35) * CFrame.Angles(0, 0.3, -0.12), -0.55, 0, -0.3, 0.55, 1.3, 0.3, bp, M.Fabric))
	soft(ellipsoid(d, "BackpackTop", CFrame.new(6.3, 0, -0.35) * CFrame.Angles(0, 0.3, -0.12) * CFrame.new(0, 1.3, 0), v(1.1, 0.5, 0.6), bp, M.Fabric))
	soft(boxL(d, "BackpackPocket", CFrame.new(6.3, 0, -0.35) * CFrame.Angles(0, 0.3, -0.12), -0.4, 0.15, -0.42, 0.4, 0.75, -0.3, rgb(140, 50, 44), M.Fabric))
	-- trash can + paper balls
	local can = vcyl(d, "TrashCan", v(9.35, 0, -0.5), 1.1, 0.8, rgb(90, 96, 104), M.Metal)
	can.CanCollide = true
	for i, p in { v(8.7, 0.13, 0.15), v(9.05, 0.13, 0.62), v(9.3, 1.18, -0.45), v(9.45, 1.2, -0.6) } do
		soft(ball(d, "PaperBall" .. i, p, 0.28, rgb(244, 244, 236), M.SmoothPlastic))
	end

	-- posters
	poster(d, "PosterSpace", v(-9.97, 5.6, -4.6), v(1, 0, 0), 2.8, 1.9, function(sg, W, H)
		ui("Frame", { BackgroundColor3 = rgb(18, 22, 56), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = sg }, {
			ui("UIGradient", {
				Rotation = 90,
				Color = U.ColorSequence.new({ U.ColorSequenceKeypoint.new(0, rgb(26, 30, 80)), U.ColorSequenceKeypoint.new(1, rgb(8, 8, 24)) }),
			}),
		})
		for i = 1, 34 do
			local s = math.floor(U.randRange(2, 5))
			ui("Frame", {
				BackgroundColor3 = rgb(255, 255, 240),
				BorderSizePixel = 0,
				Position = UDim2.new(U.rand(), 0, U.rand() * 0.8, 0),
				Size = UDim2.new(0, s, 0, s),
				Parent = sg,
			}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		end
		ui("Frame", {
			Name = "Planet",
			BackgroundColor3 = rgb(232, 124, 64),
			BorderSizePixel = 0,
			Position = UDim2.new(0.56, 0, 0.18, 0),
			Size = UDim2.new(0, 92, 0, 92),
			Parent = sg,
		}, {
			ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			ui("UIGradient", {
				Rotation = 35,
				Color = U.ColorSequence.new({ U.ColorSequenceKeypoint.new(0, rgb(255, 196, 120)), U.ColorSequenceKeypoint.new(1, rgb(150, 50, 40)) }),
			}),
		})
		ui("Frame", {
			Name = "Ring",
			BackgroundColor3 = rgb(244, 214, 150),
			BorderSizePixel = 0,
			Position = UDim2.new(0.49, 0, 0.385, 0),
			Size = UDim2.new(0, 170, 0, 9),
			Rotation = -18,
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		ui("Frame", {
			Name = "Moon",
			BackgroundColor3 = rgb(180, 200, 230),
			BorderSizePixel = 0,
			Position = UDim2.new(0.18, 0, 0.3, 0),
			Size = UDim2.new(0, 30, 0, 30),
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.06, 0, 0.78, 0),
			Size = UDim2.new(0.88, 0, 0.16, 0),
			Font = Enum.Font.Michroma,
			Text = "EXPLORE THE GALAXY",
			TextColor3 = rgb(240, 240, 255),
			TextScaled = true,
			Parent = sg,
		})
	end)

	poster(d, "PosterArcade", v(-7.2, 5.65, 7.97), v(0, 0, -1), 2.8, 1.9, function(sg, W, H)
		ui("Frame", { BackgroundColor3 = rgb(40, 10, 60), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = sg }, {
			ui("UIGradient", {
				Rotation = 90,
				Color = U.ColorSequence.new({ U.ColorSequenceKeypoint.new(0, rgb(90, 20, 120)), U.ColorSequenceKeypoint.new(1, rgb(20, 6, 40)) }),
			}),
		})
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.05, 0, 0.06, 0),
			Size = UDim2.new(0.9, 0, 0.24, 0),
			Font = Enum.Font.Arcade,
			Text = "COSMIC",
			TextColor3 = rgb(255, 224, 70),
			TextScaled = true,
			Parent = sg,
		})
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.12, 0, 0.3, 0),
			Size = UDim2.new(0.76, 0, 0.17, 0),
			Font = Enum.Font.Arcade,
			Text = "ARCADE",
			TextColor3 = rgb(80, 230, 255),
			TextScaled = true,
			Parent = sg,
		})
		-- pixel invader
		local pattern = {
			"00100000100",
			"00010001000",
			"00111111100",
			"01101110110",
			"11111111111",
			"10111111101",
			"10100000101",
			"00011011000",
		}
		local px = 7
		local ox = W * 0.5 - (11 * px) / 2
		local oy = H * 0.52
		for r, row in pattern do
			for c = 1, #row do
				if string.sub(row, c, c) == "1" then
					ui("Frame", {
						BackgroundColor3 = rgb(120, 255, 120),
						BorderSizePixel = 0,
						Position = UDim2.new(0, ox + (c - 1) * px, 0, oy + (r - 1) * px),
						Size = UDim2.new(0, px, 0, px),
						Parent = sg,
					})
				end
			end
		end
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.2, 0, 0.86, 0),
			Size = UDim2.new(0.6, 0, 0.09, 0),
			Font = Enum.Font.Arcade,
			Text = "INSERT COIN",
			TextColor3 = rgb(255, 255, 255),
			TextScaled = true,
			Parent = sg,
		})
	end)

	poster(d, "PosterMovie", v(9.97, 4.9, 2.6), v(-1, 0, 0), 2.0, 3.0, function(sg, W, H)
		ui("Frame", { BackgroundColor3 = rgb(120, 20, 20), BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), Parent = sg }, {
			ui("UIGradient", {
				Rotation = 90,
				Color = U.ColorSequence.new({ U.ColorSequenceKeypoint.new(0, rgb(30, 10, 30)), U.ColorSequenceKeypoint.new(0.6, rgb(150, 30, 30)), U.ColorSequenceKeypoint.new(1, rgb(240, 120, 40)) }),
			}),
		})
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.08, 0, 0.04, 0),
			Size = UDim2.new(0.84, 0, 0.07, 0),
			Font = Enum.Font.Bangers,
			Text = "INVASION FROM",
			TextColor3 = rgb(255, 240, 200),
			TextScaled = true,
			Parent = sg,
		})
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.04, 0, 0.1, 0),
			Size = UDim2.new(0.92, 0, 0.2, 0),
			Font = Enum.Font.Bangers,
			Text = "DIMENSION\nC-137",
			TextColor3 = rgb(255, 214, 60),
			TextScaled = true,
			Parent = sg,
		})
		-- tractor beam
		ui("Frame", {
			BackgroundColor3 = rgb(180, 255, 140),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, -28, 0.47, 0),
			Size = UDim2.new(0, 56, 0.4, 0),
			Parent = sg,
		}, {
			ui("UIGradient", {
				Rotation = 90,
				Transparency = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.2), U.NumberSequenceKeypoint.new(1, 1) }),
			}),
		})
		-- saucer
		ui("Frame", {
			BackgroundColor3 = rgb(140, 220, 255),
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, -26, 0.36, 0),
			Size = UDim2.new(0, 52, 0, 40),
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		ui("Frame", {
			BackgroundColor3 = rgb(170, 176, 190),
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, -80, 0.42, 0),
			Size = UDim2.new(0, 160, 0, 30),
			Parent = sg,
		}, { ui("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.06, 0, 0.88, 0),
			Size = UDim2.new(0.88, 0, 0.07, 0),
			Font = Enum.Font.SpecialElite,
			Text = "THEY CAME FROM THE GARAGE",
			TextColor3 = rgb(255, 240, 220),
			TextScaled = true,
			Parent = sg,
		})
	end)

	-- corkboard with notes
	local cork = part(d, "Corkboard", facing(v(-3.2, 5.0, -7.96), v(0, 0, 1)), v(2.4, 1.7, 0.08), C.cork, M.Cardboard)
	cork.CanCollide = false
	part(d, "CorkFrame", facing(v(-3.2, 5.0, -7.985), v(0, 0, 1)), v(2.56, 1.86, 0.04), C.woodDark, M.Wood)
	local notes = {
		{ -3.85, 5.3, 8, rgb(255, 236, 120), "MATH TEST\nFRIDAY!!" },
		{ -2.7, 5.35, -6, rgb(255, 170, 190), "Jessica\n<3" },
		{ -3.3, 4.5, 4, rgb(160, 210, 255), "DON'T go in\nthe garage" },
		{ -2.35, 4.55, -10, rgb(190, 240, 170), "feed\nthe dog" },
	}
	for i, n in notes do
		local cf = facing(v(n[1], n[2], -7.91), v(0, 0, 1)) * CFrame.Angles(0, 0, math.rad(n[3]))
		local note = part(d, "Note" .. i, cf, v(0.62, 0.58, 0.01), n[4], M.SmoothPlastic)
		note.CanCollide = false
		ball(d, "Pin" .. i, (cf * CFrame.new(0, 0.22, -0.02)).Position, 0.07, rgb(220, 40, 40), M.SmoothPlastic)
		local sg = U.surfaceGui(note, Enum.NormalId.Front, 200, 1)
		ui("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.06, 0, 0.12, 0),
			Size = UDim2.new(0.88, 0, 0.8, 0),
			Font = Enum.Font.PatrickHand,
			Text = n[5],
			TextColor3 = rgb(40, 40, 70),
			TextScaled = true,
			Parent = sg,
		})
	end
	return d
end

----------------------------------------------------------------------------
-- Outside: yard, fence, trees, neighbours, street lamp, Rick's portal
----------------------------------------------------------------------------
local function tree(parent, name, base, height, crown)
	local m = U.model(name, parent)
	vcyl(m, "Trunk", base, height, 1.1, C.bark, M.Wood)
	local top = base + v(0, height, 0)
	ball(m, "Crown1", top, crown, C.leaves, M.LeafyGrass)
	ball(m, "Crown2", top + v(crown * 0.3, -crown * 0.25, crown * 0.18), crown * 0.75, rgb(54, 96, 50), M.LeafyGrass)
	ball(m, "Crown3", top + v(-crown * 0.32, -crown * 0.2, -crown * 0.1), crown * 0.78, rgb(44, 80, 42), M.LeafyGrass)
	ball(m, "Crown4", top + v(0.1, crown * 0.32, -crown * 0.15), crown * 0.62, rgb(58, 102, 54), M.LeafyGrass)
	return m
end

local function neighbour(parent, name, x0, x1, z0, z1, wallTop, color)
	local m = U.model(name, parent)
	box(m, "Body", x0, -9, z0, x1, wallTop, z1, color, M.WoodPlanks)
	local depth = math.abs(z1 - z0)
	local s = depth / math.sqrt(2)
	local center = v((x0 + x1) / 2, wallTop, (z0 + z1) / 2)
	part(m, "Roof", CFrame.new(center) * CFrame.Angles(math.rad(45), 0, 0), v(math.abs(x1 - x0) + 1.2, s, s), C.roof, M.SmoothPlastic)
	-- windows facing us (+Z side)
	local zf = math.max(z0, z1)
	local wx = {}
	local count = 4
	for i = 1, count do
		wx[i] = x0 + (x1 - x0) * (i - 0.5) / count
	end
	for i, x in wx do
		for j, y in { -6.2, -1.6 } do
			local lit = ((i + j) % 3 ~= 0)
			local w = box(m, "Window" .. i .. "_" .. j, x - 0.9, y, zf, x + 0.9, y + 2.0, zf + 0.1, lit and C.warmWindow or rgb(40, 46, 60), lit and M.Neon or M.Glass)
			w:SetAttribute("NightWindow", lit)
		end
	end
	return m
end

local function buildExterior(house)
	local e = U.model("Outside", house)
	box(e, "Ground", -90, -10, -120, 90, -9, -9.6, C.grass, M.Grass)
	box(e, "Path", 1, -9, -32, 4, -8.95, -9.6, rgb(150, 140, 130), M.Concrete)
	-- fence
	local fence = U.model("Fence", e)
	local x = -46
	local i = 0
	while x < 48 do
		local h = 6 + ((i % 2 == 0) and 0.25 or 0)
		box(fence, "Board", x, -9, -32.1, x + 0.85, -9 + h, -31.95, C.fence, M.WoodPlanks)
		x += 1.0
		i += 1
	end
	box(fence, "RailLow", -46, -7.8, -32.25, 48, -7.4, -32.1, rgb(130, 100, 70), M.Wood)
	box(fence, "RailHigh", -46, -4.4, -32.25, 48, -4.0, -32.1, rgb(130, 100, 70), M.Wood)

	tree(e, "TreeA", v(-13, -9, -22), 11, 8)
	tree(e, "TreeB", v(18, -9, -27), 12, 9)
	tree(e, "TreeC", v(-27, -9, -44), 16, 10)
	tree(e, "TreeD", v(36, -9, -46), 14, 9)

	neighbour(e, "HouseA", -34, -10, -66, -50, 1, rgb(150, 166, 182))
	neighbour(e, "HouseB", 10, 32, -64, -48, 0, rgb(206, 186, 156))

	-- Rick's garage (side of the yard)
	local g = U.model("Garage", e)
	box(g, "Body", -30, -9, -24, -18, -1.5, -12, C.siding, M.WoodPlanks)
	part(g, "Roof", CFrame.new(-24, -1.5, -18) * CFrame.Angles(0, 0, math.rad(45)), v(8.5, 8.5, 12.8), C.roof, M.SmoothPlastic)
	box(g, "Door", -18.05, -9, -21.5, -17.9, -3.5, -14.5, rgb(200, 196, 186), M.Metal)
	local gw = box(g, "Window", -18.05, -5.5, -23.5, -17.9, -3.8, -22.2, rgb(160, 255, 140), M.Neon)
	gw:SetAttribute("NightWindow", true)

	-- street lamp
	local sl = U.model("StreetLamp", e)
	vcyl(sl, "Pole", v(5, -9, -40), 12.5, 0.35, rgb(40, 40, 44), M.Metal)
	cyl(sl, "Arm", v(5, 3.2, -40), v(7.2, 3.2, -40), 0.22, rgb(40, 40, 44), M.Metal)
	box(sl, "Head", 6.6, 2.7, -40.45, 7.8, 3.2, -39.55, rgb(40, 40, 44), M.Metal)
	local bulb = box(sl, "Bulb", 6.7, 2.62, -40.35, 7.7, 2.7, -39.65, rgb(255, 210, 140), M.Neon)
	bulb:SetAttribute("BulbFor", "StreetLamp")
	local pl = U.Instance.new("PointLight")
	pl.Name = "StreetLamp"
	pl.Range = 32
	pl.Brightness = 1.4
	pl.Color = rgb(255, 186, 110)
	pl.Shadows = true
	pl.Parent = bulb

	-- Rick's portal in the yard (only shown in the "Portal" graphics preset)
	local portal = U.model("Portal", e)
	local pc = v(6, 1.5, -22)
	local axis = CFrame.lookAt(pc, pc + v(0, 0, 1)) * CFrame.Angles(0, math.rad(90), 0)
	local rings = {
		{ "Outer", v(0.3, 8.2, 6.8), rgb(60, 200, 50) },
		{ "Mid", v(0.36, 6.9, 5.7), rgb(140, 240, 90) },
		{ "Inner", v(0.42, 5.0, 4.1), rgb(210, 255, 160) },
		{ "Core", v(0.48, 2.8, 2.3), rgb(240, 255, 220) },
	}
	for idx, r in rings do
		local p = ecyl(portal, r[1], axis * CFrame.new(idx * 0.02, 0, 0), r[2], r[3], M.Neon)
		p.Transparency = 1
		p.CastShadow = false
		p.CanCollide = false
		p:SetAttribute("PortalFX", true)
	end
	local core = portal:FindFirstChild("Core")
	local pe = U.Instance.new("ParticleEmitter")
	pe.Name = "Sparks"
	pe.Color = U.ColorSequence.new(rgb(170, 255, 120))
	pe.LightEmission = 1
	pe.Rate = 40
	pe.Lifetime = U.NumberRange.new(0.8, 1.6)
	pe.Speed = U.NumberRange.new(3, 7)
	pe.SpreadAngle = U.Vector2 and U.Vector2.new(180, 180) or nil
	pe.Size = U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, 0.35), U.NumberSequenceKeypoint.new(1, 0) })
	pe.Enabled = false
	pe.Parent = core
	local plight = U.Instance.new("PointLight")
	plight.Name = "PortalLight"
	plight.Range = 40
	plight.Brightness = 5
	plight.Color = rgb(110, 255, 90)
	plight.Shadows = true
	plight.Enabled = false
	plight.Parent = core
	return e
end

----------------------------------------------------------------------------
-- Moon / sun beams through the window, dust, spawns
----------------------------------------------------------------------------
local function buildLights(house)
	local f = U.folder("Lights", house)
	local windowCenter = v(2, 4.95, -8.55)
	local function beam(name, source, target, angle, brightness, color, range)
		local p = U.marker(f, name .. "Source", CFrame.lookAt(source, target))
		local s = U.Instance.new("SpotLight")
		s.Name = name
		s.Face = Enum.NormalId.Front
		s.Angle = angle
		s.Brightness = brightness
		s.Color = color
		s.Range = range
		s.Shadows = true
		s.Parent = p
		return s
	end
	-- moonlight lands on the rug
	local moonTarget = v(-1, 0, -1.5)
	local md = moonTarget - windowCenter
	beam("MoonBeam", windowCenter - md * 1.6, moonTarget, 42, 3, rgb(140, 165, 255), 40)
	-- low sunrise light lands on the wall above the bed
	local sunTarget = v(-9.9, 4.2, -3.2)
	local sd = sunTarget - windowCenter
	local sun = beam("SunBeam", windowCenter - sd * 2.0, sunTarget, 30, 5, rgb(255, 170, 100), 55)
	sun.Enabled = false

	-- floating dust (only visible inside light beams)
	local dust = U.part(f, "DustVolume", CFrame.new(0, 4, -3), v(12, 7, 9), rgb(255, 255, 255), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local pe = U.Instance.new("ParticleEmitter")
	pe.Name = "Dust"
	pe.Rate = 10
	pe.Lifetime = U.NumberRange.new(8, 14)
	pe.Speed = U.NumberRange.new(0.05, 0.25)
	pe.Size = U.NumberSequence.new(0.05)
	pe.Transparency = U.NumberSequence.new({
		U.NumberSequenceKeypoint.new(0, 1),
		U.NumberSequenceKeypoint.new(0.2, 0.35),
		U.NumberSequenceKeypoint.new(0.8, 0.35),
		U.NumberSequenceKeypoint.new(1, 1),
	})
	pe.LightInfluence = 1
	pe.LightEmission = 0.3
	pe.Parent = dust
	pcall(function()
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end)
	return f
end

local function buildSpawns(house)
	local f = U.folder("Spawns", house)
	local pos = v(-4.9, 3, -4.6)
	U.marker(f, "WakeUpPoint", CFrame.lookAt(pos, pos + v(1, 0, 0.45)), v(2, 2, 1))
	U.marker(f, "HoldPoint", CFrame.new(0, -80, 0), v(2, 2, 1))
	local sp = U.Instance.new("SpawnLocation")
	sp.Name = "SpawnLocation"
	sp.Anchored = true
	sp.CanCollide = false
	sp.CanQuery = false
	sp.CanTouch = false
	sp.Transparency = 1
	sp.Size = v(2, 0.1, 2)
	sp.CFrame = CFrame.new(-4.9, 0.05, -4.6)
	sp.Duration = 0
	sp.Neutral = true
	sp.Parent = f
	return f
end

function Room.build(workspace)
	local house = U.model("MortysHouse", workspace)
	buildStructure(house)
	buildWindow(house)
	buildBed(house)
	buildMortySleeping(house)
	buildNightstand(house)
	buildDesk(house)
	buildShelf(house)
	buildChair(house)
	buildDresser(house)
	buildDoor(house)
	buildDecor(house)
	buildExterior(house)
	buildLights(house)
	buildSpawns(house)
	return house
end

return Room
