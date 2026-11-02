--!nocheck
-- Locations for chapters 7-12:
--   Silent dimension (the Curve Bell + 3 pylons, the sky that cracks)
--   J-22 (everything upside down), D-716 (everything is cubes), K-9 (glowing mushroom forest)
--   the Alliance camera base in a ruined Skibidi city
--   the fake bunker shed over the hatch on B137
local U = require("./Util")
local Characters = require("./Characters")
local Vector3, CFrame, Enum, Instance = U.Vector3, U.CFrame, U.Enum, U.Instance
local rgb, v = U.rgb, U.v
local M = Enum.Material

local Worlds = {}
Worlds.SILENT = v(-6000, 0, -6000)
Worlds.UPSIDE = v(-6000, 0, -3000)
Worlds.CUBE = v(-6000, 0, 0)
Worlds.MUSH = v(-6000, 0, 3000)
Worlds.BASE = v(9000, 0, -9000)

local function light(parentPart, name, class, props)
	local l = Instance.new(class)
	l.Name = name
	for k, val in props do
		l[k] = val
	end
	l.Parent = parentPart
	return l
end

local function emitter(parentPart, name, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	for k, val in props do
		pe[k] = val
	end
	pe.Parent = parentPart
	return pe
end

local function NS(a, b, c)
	if c then
		return U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, a), U.NumberSequenceKeypoint.new(0.5, b), U.NumberSequenceKeypoint.new(1, c) })
	end
	return U.NumberSequence.new({ U.NumberSequenceKeypoint.new(0, a), U.NumberSequenceKeypoint.new(1, b) })
end

local function spot(folder, name, pos, lookAt)
	return U.marker(folder, name, CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z)), v(2, 2, 1))
end

-- a ring of invisible walls so nobody walks off the edge of a world
local function ringWall(parent, center, radius, height)
	local n = math.max(16, math.floor(radius * 2 * math.pi / 30))
	local w = radius * 2 * math.pi / n + 2
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local p = center + v(math.cos(a) * radius, height / 2, math.sin(a) * radius)
		U.part(parent, "EdgeWall", CFrame.lookAt(p, center + v(0, height / 2, 0)), v(w, height, 1), rgb(255, 255, 255), M.SmoothPlastic, {
			Transparency = 1,
			CastShadow = false,
			CanQuery = false,
		})
	end
end

local function boxWall(parent, center, half, height)
	for _, s in { { v(0, 0, -half), v(half * 2, height, 2) }, { v(0, 0, half), v(half * 2, height, 2) }, { v(-half, 0, 0), v(2, height, half * 2) }, { v(half, 0, 0), v(2, height, half * 2) } } do
		U.part(parent, "EdgeWall", CFrame.new(center + s[1] + v(0, height / 2, 0)), s[2], rgb(255, 255, 255), M.SmoothPlastic, {
			Transparency = 1,
			CastShadow = false,
			CanQuery = false,
		})
	end
end

----------------------------------------------------------------------------
-- 1. The Silent dimension: a floating island where nothing makes a sound
----------------------------------------------------------------------------
local function buildSilent(root)
	local O = Worlds.SILENT
	local m = U.model("SilentDimension", root)
	local stone = rgb(204, 208, 216)
	U.vcyl(m, "Island", O + v(0, -6, 0), 6, 240, stone, M.Slate)
	U.vcyl(m, "IslandEdge", O + v(0, -11, 0), 5.5, 248, rgb(168, 172, 184), M.Slate, { CanCollide = false })
	for i, e in { { 0, -30, 0, 236, 48 }, { 8, -62, -6, 172, 86 }, { -6, -106, 8, 94, 98 }, { 4, -152, 0, 36, 72 } } do
		U.ellipsoid(m, "Under" .. i, CFrame.new(O + v(e[1], e[2], e[3])), v(e[4], e[5], e[4]), rgb(150 - i * 10, 152 - i * 10, 166 - i * 10), M.Rock, { CanCollide = false })
	end
	ringWall(m, O, 116, 24)
	-- white crystal shards around the edge
	for _ = 1, 28 do
		local a = U.rand() * math.pi * 2
		local r = U.randRange(68, 110)
		local base = O + v(math.cos(a) * r, 0, math.sin(a) * r)
		local h = U.randRange(3, 12)
		local tilt = CFrame.Angles(U.randRange(-0.35, 0.35), U.rand() * 6.28, U.randRange(-0.35, 0.35))
		U.part(m, "Shard", CFrame.new(base) * tilt * CFrame.new(0, h / 2 - 0.6, 0), v(h * 0.26, h, h * 0.26), rgb(236, 240, 250), M.Glass, { Transparency = 0.12, CanCollide = false })
	end
	-- leaning white monoliths
	for i, p in { { -92, 30, 0.12 }, { -78, 70, -0.08 }, { 90, 52, 0.1 }, { 96, -62, -0.15 }, { -86, -70, 0.06 } } do
		local base = O + v(p[1], 0, p[2])
		U.part(m, "Monolith" .. i, CFrame.lookAt(base, O) * CFrame.Angles(p[3], 0, 0) * CFrame.new(0, 11, 0), v(6, 24, 2.2), rgb(238, 238, 242), M.Marble)
	end
	-- rocks floating in the white void
	for _ = 1, 18 do
		local a = U.rand() * math.pi * 2
		local r = U.randRange(170, 440)
		local s = U.randRange(10, 56)
		local p = O + v(math.cos(a) * r, U.randRange(-90, 130), math.sin(a) * r)
		U.ellipsoid(m, "FloatRock", CFrame.new(p) * CFrame.Angles(U.rand(), U.rand() * 6, U.rand()), v(s, s * 0.55, s * 0.8), rgb(160, 162, 176), M.Rock, { CanCollide = false })
	end

	-- THE CURVE BELL: a giant tuning fork with the Titan's broken speaker as the resonator
	local B = O + v(0, 0, -40)
	local bell = U.model("CurveBell", m)
	local chrome = rgb(218, 222, 230)
	local shiny = { Reflectance = 0.15 }
	U.vcyl(bell, "BaseRim", B, 1.2, 30, rgb(40, 42, 50), M.Metal)
	U.vcyl(bell, "Base", B, 2.4, 27, rgb(66, 68, 78), M.DiamondPlate)
	U.vcyl(bell, "Stem", B + v(0, 2.4, 0), 15, 4.6, chrome, M.Metal, shiny)
	U.cyl(bell, "Bend", B + v(-10.5, 17.4, 0), B + v(10.5, 17.4, 0), 4.6, chrome, M.Metal, shiny)
	for _, sx in { -1, 1 } do
		U.ball(bell, "Elbow", B + v(sx * 10.5, 17.4, 0), 4.6, chrome, M.Metal, shiny)
		local prong = U.cyl(bell, "Prong", B + v(sx * 10.5, 17.4, 0), B + v(sx * 10.5, 70, 0), 4.2, chrome, M.Metal, shiny)
		prong:SetAttribute("BellProng", sx)
		U.ball(bell, "Tip", B + v(sx * 10.5, 70, 0), 4.4, chrome, M.Metal, shiny)
		for k = 1, 3 do
			U.ecyl(bell, "Band", CFrame.new(B + v(sx * 10.5, 22 + k * 12, 0)) * CFrame.Angles(0, 0, math.rad(90)), v(0.8, 4.8, 4.8), rgb(60, 62, 70), M.Metal)
		end
	end
	local spk = B + v(0, 9, 3.4)
	U.part(bell, "Resonator", CFrame.new(spk), v(10, 10, 5), rgb(18, 18, 20), M.Metal)
	U.ecyl(bell, "ResonatorRim", CFrame.new(spk + v(0, 0, 2.6)) * CFrame.Angles(0, math.rad(90), 0), v(0.6, 8.4, 8.4), rgb(52, 52, 58), M.Metal)
	local cone = U.ecyl(bell, "ResonatorCone", CFrame.new(spk + v(0, 0, 2.95)) * CFrame.Angles(0, math.rad(90), 0), v(0.4, 7, 7), rgb(150, 40, 24), M.Neon, { CastShadow = false })
	cone:SetAttribute("BellCone", true)
	U.ellipsoid(bell, "ResonatorHot", CFrame.new(spk + v(0, 0, 3.2)), v(2.4, 2.4, 0.8), rgb(255, 170, 110), M.Neon, { CastShadow = false })
	U.part(bell, "ResonatorCrack", CFrame.new(spk + v(1.3, 1.5, 3.2)) * CFrame.Angles(0, 0, math.rad(35)), v(0.3, 5, 0.2), rgb(30, 10, 8), M.SmoothPlastic, { CanCollide = false })
	U.part(bell, "Clamp", CFrame.new(spk + v(0, 0, -3.2)), v(6, 3, 1.6), rgb(60, 62, 70), M.Metal)
	light(cone, "BellLight", "PointLight", { Range = 24, Brightness = 0.6, Color = rgb(255, 80, 40) })
	local ring = U.ecyl(bell, "BellRing", CFrame.new(B + v(0, 2.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), v(0.2, 33, 33), rgb(120, 255, 170), M.Neon, { Transparency = 1, CanCollide = false, CastShadow = false })
	ring:SetAttribute("BellRing", true)
	-- Rick's console
	local con = B + v(16, 0, 15)
	local conCF = CFrame.lookAt(con, con + v(0, 0, 1))
	U.part(bell, "Console", conCF * CFrame.new(0, 1.8, 0), v(6, 3.6, 2.6), rgb(52, 54, 62), M.Metal)
	U.part(bell, "ConsoleTop", conCF * CFrame.new(0, 3.75, 0.2) * CFrame.Angles(math.rad(-25), 0, 0), v(5.6, 0.3, 2.2), rgb(30, 32, 38), M.Metal)
	local scr = U.part(bell, "ConsoleScreen", conCF * CFrame.new(0, 3.95, 0.25) * CFrame.Angles(math.rad(-25), 0, 0), v(4.6, 0.1, 1.6), rgb(110, 255, 160), M.Neon, { CastShadow = false })
	scr:SetAttribute("ConsoleScreen", true)
	for i = -1, 1 do
		U.ball(bell, "Knob", (conCF * CFrame.new(i * 1.6, 3.4, -0.9)).Position, 0.45, rgb(220, 60, 40), M.SmoothPlastic)
	end
	U.cyl(bell, "ConsoleCable", con + v(0, 0.3, 0), B + v(0, 0.3, 0), 0.6, rgb(24, 24, 28), M.SmoothPlastic, { CanCollide = false })

	-- three pylons that must be switched on
	local spots = U.folder("SilentSpots", m)
	for i, p in { v(-62, 0, -6), v(62, 0, -6), v(0, 0, -100) } do
		local base = O + p
		local py = U.model("Pylon" .. i, m)
		py:SetAttribute("Interact", "Pylon")
		py:SetAttribute("Index", i)
		U.part(py, "Base", CFrame.new(base + v(0, 0.75, 0)), v(7, 1.5, 7), rgb(70, 72, 82), M.Slate)
		U.part(py, "Column", CFrame.new(base + v(0, 8, 0)), v(3.4, 13, 3.4), rgb(52, 54, 64), M.Slate)
		U.part(py, "Cap", CFrame.new(base + v(0, 15, 0)), v(4.4, 1, 4.4), rgb(70, 72, 82), M.Slate)
		for k = 0, 3 do
			local a = k * math.pi / 2
			U.part(py, "Rib", CFrame.new(base + v(math.cos(a) * 1.9, 8, math.sin(a) * 1.9)) * CFrame.Angles(0, -a, 0), v(0.5, 11, 0.8), rgb(90, 92, 104), M.Metal)
		end
		local cr = U.ellipsoid(py, "Crystal", CFrame.new(base + v(0, 18, 0)), v(2.8, 4.8, 2.8), rgb(40, 80, 60), M.Glass, { CanCollide = false })
		cr:SetAttribute("PylonCrystal", true)
		light(cr, "PylonLight", "PointLight", { Range = 24, Brightness = 0, Color = rgb(120, 255, 170) })
		local panelCF = CFrame.lookAt(base + v(0, 4.2, 0), Vector3.new(O.X, base.Y + 4.2, O.Z)) * CFrame.new(0, 0, -1.85)
		local panel = U.part(py, "Panel", panelCF, v(2, 1.6, 0.3), rgb(60, 120, 90), M.SmoothPlastic)
		panel:SetAttribute("PylonPanel", true)
		U.cyl(m, "Cable", base + v(0, 0.3, 0), B + v(0, 0.3, 0), 0.7, rgb(24, 24, 28), M.SmoothPlastic, { CanCollide = false })
		spot(spots, "Pylon" .. i, base + (O - base).Unit * 6 + v(0, 3, 0), base)
	end
	spot(spots, "Arrive", O + v(0, 3, 88), B)
	spot(spots, "RickArrive", O + v(4.5, 3.36, 86), B)
	spot(spots, "RickConsole", con + v(0, 3.36, 3.6), con)
	spot(spots, "MortyWatch", O + v(-6, 3, 34), B + v(0, 0, 0))
	spot(spots, "EvilArrive", O + v(-26, 3, 18), O + v(-6, 3, 34))
	U.marker(spots, "Portal", CFrame.lookAt(O + v(0, 6, 96), O + v(0, 6, 0)), v(1, 1, 1))
	U.marker(spots, "EvilPortal", CFrame.lookAt(O + v(-30, 6, 10), O + v(-6, 6, 34)), v(1, 1, 1))
	U.marker(spots, "Bell", CFrame.new(B), v(1, 1, 1))

	-- cracks in the sky (shown one by one when the curve gives way)
	local cracks = U.model("Cracks", m)
	local C = O + v(0, 175, -430)
	local branches = { v(1, 0.15, 0), v(-1, 0.25, 0), v(0.35, 1, 0), v(-0.4, -0.9, 0), v(0.8, -0.7, 0), v(-0.8, 0.8, 0) }
	for bi, d0 in branches do
		local p = C
		local dir = d0.Unit
		for k = 1, 7 do
			local len = U.randRange(16, 34)
			dir = (dir + v(U.randRange(-0.55, 0.55), U.randRange(-0.55, 0.55), 0)).Unit
			local q = p + dir * len
			local seg = U.cyl(cracks, "Crack", p, q, U.randRange(1.4, 2.8) * (1 - k / 10), rgb(235, 250, 255), M.Neon, { Transparency = 1, CanCollide = false, CastShadow = false })
			seg:SetAttribute("Crack", k * 10 + bi)
			p = q
		end
	end
	local glow = U.ball(cracks, "CrackCore", C, 14, rgb(240, 252, 255), M.Neon, { Transparency = 1, CanCollide = false, CastShadow = false })
	glow:SetAttribute("Crack", 0)
	return m
end

----------------------------------------------------------------------------
-- 2. J-22: a town where everything stands upside down (and the rain falls up)
----------------------------------------------------------------------------
local function house(parent, cf, w, d, h, wall, roof)
	local hm = U.model("House", parent)
	local function P(name, x, y, z, sx, sy, sz, color, mat)
		return U.part(hm, name, cf * CFrame.new(x, y, z), v(sx, sy, sz), color, mat or M.SmoothPlastic)
	end
	P("Walls", 0, h / 2, 0, w, h, d, wall, M.Plaster)
	P("Trim", 0, h + 0.3, 0, w + 0.6, 0.6, d + 0.6, rgb(240, 240, 236))
	-- roof: two slanted slabs
	local rh = w * 0.32
	local slope = math.atan2(rh, w / 2)
	local len = math.sqrt((w / 2) ^ 2 + rh ^ 2) + 0.6
	for _, s in { -1, 1 } do
		U.part(hm, "Roof", cf * CFrame.new(s * w / 4, h + 0.6 + rh / 2, 0) * CFrame.Angles(0, 0, -s * slope), v(len, 0.7, d + 1.4), roof, M.Slate)
	end
	-- attic fill under the roof: the tall side of each wedge sits under the ridge
	U.wedge(hm, "Gable", cf * CFrame.new(-w / 4, h + 0.6 + rh / 2 - 0.2, 0) * CFrame.Angles(0, math.rad(90), 0), v(d - 0.2, rh - 0.4, w / 2 - 0.2), wall, M.Plaster)
	U.wedge(hm, "Gable", cf * CFrame.new(w / 4, h + 0.6 + rh / 2 - 0.2, 0) * CFrame.Angles(0, math.rad(-90), 0), v(d - 0.2, rh - 0.4, w / 2 - 0.2), wall, M.Plaster)
	P("Door", 0, 3.6, -d / 2 - 0.1, 3.4, 7, 0.4, rgb(120, 70, 40), M.Wood)
	P("Knob", 1.1, 3.4, -d / 2 - 0.35, 0.3, 0.3, 0.3, rgb(220, 190, 90), M.Metal)
	for _, sx in { -1, 1 } do
		local win = P("Window", sx * w * 0.3, h * 0.55, -d / 2 - 0.1, 3, 3, 0.3, rgb(170, 210, 240), M.Glass)
		win:SetAttribute("NightWindow", true)
		P("WindowFrame", sx * w * 0.3, h * 0.55, -d / 2 - 0.05, 3.6, 3.6, 0.2, rgb(245, 245, 240))
	end
	P("Chimney", w * 0.25, h + rh + 1, d * 0.2, 1.8, 4, 1.8, rgb(150, 70, 60), M.Brick)
	return hm
end

local function buildUpside(root)
	local O = Worlds.UPSIDE
	local m = U.model("WorldJ22", root)
	U.part(m, "Ground", CFrame.new(O + v(0, -1, 0)), v(340, 2, 340), rgb(96, 140, 72), M.Grass)
	U.part(m, "Road", CFrame.new(O + v(0, 0.05, 0)), v(24, 0.1, 340), rgb(62, 62, 66), M.Asphalt, { CanCollide = false })
	for z = -160, 160, 16 do
		U.part(m, "RoadLine", CFrame.new(O + v(0, 0.12, z)), v(0.6, 0.05, 7), rgb(240, 220, 120), M.SmoothPlastic, { CanCollide = false })
	end
	boxWall(m, O, 150, 30)
	-- upside-down houses (roof on the grass, floor in the air)
	local colors = { rgb(236, 200, 160), rgb(180, 210, 230), rgb(230, 170, 170), rgb(200, 230, 180), rgb(240, 230, 170), rgb(210, 190, 230) }
	local i = 0
	for _, side in { -1, 1 } do
		for k = -2, 2 do
			i += 1
			local w, d, h = 18 + (i % 3) * 3, 16 + (i % 2) * 4, 11 + (i % 2) * 2
			local rh = w * 0.32
			local base = O + v(side * 34, 0, k * 46 + side * 8)
			local yaw = if side < 0 then math.rad(-90) else math.rad(90)
			-- flip over: the roof ridge touches the ground
			local cf = CFrame.new(base + v(0, h + 0.6 + rh, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi)
			house(m, cf, w, d, h, colors[(i % #colors) + 1], rgb(90, 60, 56))
		end
	end
	-- upside-down trees: crown on the ground, roots in the air
	for t = 1, 16 do
		local x = (if t % 2 == 0 then 1 else -1) * U.randRange(60, 130)
		local z = U.randRange(-140, 140)
		local base = O + v(x, 0, z)
		local hgt = U.randRange(12, 20)
		U.ellipsoid(m, "Crown", CFrame.new(base + v(0, 4, 0)), v(12, 9, 12), rgb(70, 130, 60), M.Grass, { CanCollide = false })
		U.vcyl(m, "Trunk", base + v(0, 6, 0), hgt, 1.8, rgb(110, 80, 56), M.Wood)
		for r = 0, 3 do
			local a = r * math.pi / 2 + t
			U.cyl(m, "Root", base + v(0, 6 + hgt, 0), base + v(math.cos(a) * 3.5, 9 + hgt, math.sin(a) * 3.5), 0.7, rgb(100, 72, 50), M.Wood, { CanCollide = false })
		end
	end
	-- an upside-down car and street lamps
	local car = CFrame.new(O + v(5, 2.2, -30)) * CFrame.Angles(0, math.rad(10), math.pi)
	U.part(m, "CarBody", car, v(7, 2.4, 14), rgb(200, 60, 50), M.SmoothPlastic)
	U.part(m, "CarTop", car * CFrame.new(0, 1.9, 1), v(6.4, 1.8, 7), rgb(200, 60, 50), M.SmoothPlastic)
	for _, wx in { -3.7, 3.7 } do
		for _, wz in { -4.6, 4.6 } do
			U.ecyl(m, "Wheel", car * CFrame.new(wx, -1.6, wz), v(1.2, 3, 3), rgb(20, 20, 22), M.SmoothPlastic)
		end
	end
	for k = -3, 3 do
		local base = O + v(13.5, 0, k * 44 + 20)
		U.ball(m, "LampHead", base + v(0, 1, 0), 2, rgb(255, 230, 170), M.Neon, { CastShadow = false })
		U.vcyl(m, "LampPole", base + v(0, 1.6, 0), 14, 0.6, rgb(50, 50, 56), M.Metal)
		U.part(m, "LampBase", CFrame.new(base + v(0, 16, 0)), v(1.6, 1, 1.6), rgb(50, 50, 56), M.Metal)
	end
	-- rain that falls UP
	local rain = U.part(m, "RainSource", CFrame.new(O + v(0, 1, 0)), v(300, 1, 300), rgb(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	emitter(rain, "UpRain", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = U.ColorSequence.new(rgb(190, 220, 255)),
		LightEmission = 0.3,
		Size = NS(0.25, 0.15),
		Transparency = NS(0.2, 1),
		Lifetime = U.NumberRange.new(2, 3),
		Speed = U.NumberRange.new(30, 40),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 260,
		Enabled = false,
	})
	-- a puddle in the sky (water hanging above the road)
	U.ellipsoid(m, "SkyPuddle", CFrame.new(O + v(-8, 46, 10)), v(30, 2, 22), rgb(90, 150, 220), M.Glass, { Transparency = 0.35, CanCollide = false })
	local spots = U.folder("J22Spots", m)
	spot(spots, "Arrive", O + v(-4, 3, 120), O + v(0, 3, 0))
	spot(spots, "RickArrive", O + v(1, 3.36, 118), O + v(0, 3, 0))
	spot(spots, "EvilArrive", O + v(-8, 3, 116), O + v(0, 3, 0))
	spot(spots, "Walk", O + v(-3, 3, 40), O + v(0, 3, -40))
	U.marker(spots, "Portal", CFrame.lookAt(O + v(-3, 6, 128), O + v(0, 6, 0)), v(1, 1, 1))
	U.marker(spots, "PortalOut", CFrame.lookAt(O + v(0, 6, 10), O + v(0, 6, 120)), v(1, 1, 1))
	return m
end

----------------------------------------------------------------------------
-- 3. D-716: a world made of cubes
----------------------------------------------------------------------------
local function cubeCow(parent, cf)
	local c = U.model("CubeCow", parent)
	local white, black, pink = rgb(240, 240, 236), rgb(30, 30, 32), rgb(240, 170, 170)
	local function P(name, x, y, z, sx, sy, sz, color)
		return U.part(c, name, cf * CFrame.new(x, y, z), v(sx, sy, sz), color, M.SmoothPlastic)
	end
	c.PrimaryPart = P("Body", 0, 3.6, 0, 3.6, 3, 6, white)
	P("Spot1", 1.85, 4, 0.8, 0.1, 1.6, 2, black)
	P("Spot2", -1.85, 3.4, -1.2, 0.1, 1.4, 1.6, black)
	P("Spot3", 0.4, 5.15, 1.4, 1.8, 0.1, 1.6, black)
	P("Head", 0, 4.6, -3.9, 2.6, 2.4, 2, white)
	P("Snout", 0, 4.1, -5, 2, 1.1, 0.4, pink)
	P("EyeL", -0.7, 5.1, -4.95, 0.45, 0.45, 0.1, black)
	P("EyeR", 0.7, 5.1, -4.95, 0.45, 0.45, 0.1, black)
	P("HornL", -1, 6, -3.6, 0.4, 0.8, 0.4, rgb(230, 220, 190))
	P("HornR", 1, 6, -3.6, 0.4, 0.8, 0.4, rgb(230, 220, 190))
	for _, lx in { -1.2, 1.2 } do
		for _, lz in { -2.2, 2.2 } do
			P("Leg", lx, 1.05, lz, 1, 2.1, 1, white)
		end
	end
	c:SetAttribute("Cow", true)
	return c
end

local function buildCube(root)
	local O = Worlds.CUBE
	local m = U.model("WorldD716", root)
	local greens = { rgb(92, 160, 70), rgb(84, 150, 64), rgb(100, 168, 76), rgb(78, 140, 60) }
	local S = 12
	U.part(m, "Ground", CFrame.new(O + v(0, -S / 2, 0)), v(S * 26, S, S * 26), greens[1], M.SmoothPlastic)
	-- checkerboard tint on top
	for gx = -12, 12, 2 do
		for gz = -12, 12, 3 do
			local h = (gx * 7 + gz * 13) % 4
			U.part(m, "Tile", CFrame.new(O + v(gx * S, 0.05, gz * S)), v(S, 0.1, S), greens[h + 1], M.SmoothPlastic, { CanCollide = false })
		end
	end
	boxWall(m, O, S * 13, 40)
	-- cube hills (stacks of blocks) away from the middle
	for _ = 1, 30 do
		local gx = math.floor(U.randRange(-11, 11))
		local gz = math.floor(U.randRange(-11, 11))
		if math.abs(gx) > 3 or math.abs(gz) > 4 then
			local hgt = math.floor(U.randRange(1, 4))
			for k = 1, hgt do
				local col = if k == hgt then greens[(k % 4) + 1] else rgb(140, 100, 64)
				U.part(m, "Block", CFrame.new(O + v(gx * S, S * (k - 0.5), gz * S)), v(S, S, S), col, M.SmoothPlastic)
			end
		end
	end
	-- blocky trees
	for t = 1, 14 do
		local x = (if t % 2 == 0 then 1 else -1) * U.randRange(30, 140)
		local z = U.randRange(-140, 140)
		local base = O + v(x, 0, z)
		U.part(m, "TreeTrunk", CFrame.new(base + v(0, 6, 0)), v(2.4, 12, 2.4), rgb(110, 76, 46), M.SmoothPlastic)
		U.part(m, "TreeLeaves", CFrame.new(base + v(0, 15, 0)), v(10, 8, 10), rgb(60, 130, 50), M.SmoothPlastic)
		U.part(m, "TreeTop", CFrame.new(base + v(0, 20.5, 0)), v(6, 3, 6), rgb(70, 145, 58), M.SmoothPlastic)
	end
	-- cube cows grazing
	for i, p in { v(-22, 0, 30), v(-34, 0, 10), v(26, 0, 22), v(18, 0, -18), v(-14, 0, -40), v(40, 0, -6) } do
		cubeCow(m, CFrame.new(O + p) * CFrame.Angles(0, i * 1.1, 0))
	end
	-- the square sun
	local sun = U.part(m, "CubeSun", CFrame.new(O + v(260, 300, -420)) * CFrame.Angles(0.4, 0.6, 0.2), v(60, 60, 60), rgb(255, 220, 90), M.Neon, { CanCollide = false, CastShadow = false })
	light(sun, "CubeSunLight", "PointLight", { Range = 60, Brightness = 0.5, Color = rgb(255, 220, 120) })
	-- blocky clouds
	for _ = 1, 10 do
		local p = O + v(U.randRange(-260, 260), U.randRange(110, 170), U.randRange(-260, 260))
		U.part(m, "Cloud", CFrame.new(p), v(U.randRange(30, 60), 8, U.randRange(16, 30)), rgb(250, 250, 252), M.SmoothPlastic, { CanCollide = false, CastShadow = false })
	end
	local spots = U.folder("D716Spots", m)
	spot(spots, "Arrive", O + v(-4, 3, 60), O)
	spot(spots, "RickArrive", O + v(2, 3.36, 58), O)
	spot(spots, "EvilArrive", O + v(-9, 3, 56), O)
	spot(spots, "CowTalk", O + v(-16, 3, 34), O + v(-22, 3, 30))
	U.marker(spots, "Portal", CFrame.lookAt(O + v(-2, 6, 68), O + v(0, 6, 0)), v(1, 1, 1))
	U.marker(spots, "PortalOut", CFrame.lookAt(O + v(0, 6, 0), O + v(0, 6, 60)), v(1, 1, 1))
	return m
end

----------------------------------------------------------------------------
-- 4. K-9: a forest of giant glowing mushrooms
----------------------------------------------------------------------------
local function buildMushroom(root)
	local O = Worlds.MUSH
	local m = U.model("WorldK9", root)
	U.part(m, "Ground", CFrame.new(O + v(0, -1, 0)), v(340, 2, 340), rgb(56, 36, 70), M.Grass)
	boxWall(m, O, 150, 40)
	local caps = { rgb(80, 230, 255), rgb(255, 80, 200), rgb(255, 160, 60), rgb(150, 110, 255), rgb(120, 255, 160) }
	for i = 1, 22 do
		local a = U.rand() * math.pi * 2
		local r = U.randRange(26, 140)
		local base = O + v(math.cos(a) * r, 0, math.sin(a) * r)
		if math.abs(base.X - O.X) < 14 then
			base = base + v(28, 0, 0)
		end
		local h = U.randRange(16, 58)
		local cw = h * U.randRange(0.7, 1.1)
		local col = caps[(i % #caps) + 1]
		local lean = CFrame.Angles(U.randRange(-0.12, 0.12), 0, U.randRange(-0.12, 0.12))
		local cf = CFrame.new(base) * lean
		U.ecyl(m, "Stem", cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), v(h, h * 0.14, h * 0.14), rgb(230, 220, 236), M.SmoothPlastic)
		local cap = U.ellipsoid(m, "Cap", cf * CFrame.new(0, h, 0), v(cw, cw * 0.36, cw), col, M.SmoothPlastic, { CanCollide = false })
		cap:SetAttribute("MushCap", i)
		local under = U.ellipsoid(m, "Gills", cf * CFrame.new(0, h - cw * 0.06, 0), v(cw * 0.92, cw * 0.14, cw * 0.92), col, M.Neon, { CanCollide = false, CastShadow = false })
		if i % 3 == 0 then
			light(under, "MushLight", "PointLight", { Range = math.min(60, cw * 1.2), Brightness = 1.2, Color = col })
		end
		for d = 1, 4 do
			local da = d * 1.7 + i
			U.ball(m, "Dot", (cf * CFrame.new(math.cos(da) * cw * 0.28, h + cw * 0.15, math.sin(da) * cw * 0.28)).Position, cw * 0.09, rgb(255, 255, 240), M.SmoothPlastic, { CanCollide = false })
		end
	end
	-- little glowing mushrooms along the path
	for k = 1, 40 do
		local z = U.randRange(-120, 120)
		local x = (if k % 2 == 0 then 1 else -1) * U.randRange(5, 14)
		local base = O + v(x, 0, z)
		local col = caps[(k % #caps) + 1]
		U.vcyl(m, "SmallStem", base, 1.2, 0.35, rgb(230, 220, 236), M.SmoothPlastic, { CanCollide = false })
		U.ellipsoid(m, "SmallCap", CFrame.new(base + v(0, 1.3, 0)), v(1.5, 0.6, 1.5), col, M.Neon, { CanCollide = false, CastShadow = false })
	end
	-- spores drifting in the air
	local spores = U.part(m, "SporeSource", CFrame.new(O + v(0, 12, 0)), v(260, 1, 260), rgb(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	emitter(spores, "Spores", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = U.ColorSequence.new(rgb(200, 255, 220), rgb(255, 160, 240)),
		LightEmission = 1,
		Size = NS(0.15, 0.4, 0.1),
		Transparency = NS(1, 0.2, 1),
		Lifetime = U.NumberRange.new(6, 10),
		Speed = U.NumberRange.new(0.5, 2),
		SpreadAngle = U.Vector2.new(180, 180),
		Rate = 120,
		Enabled = false,
	})
	-- hidden red eyes in the dark (spore hallucination)
	local eyes = U.model("SporeEyes", m)
	for e = 1, 6 do
		local p = O + v((e % 2 == 0 and 1 or -1) * U.randRange(26, 60), U.randRange(6, 18), U.randRange(-60, 40))
		for _, sx in { -1, 1 } do
			local eye = U.ellipsoid(eyes, "RedEye", CFrame.lookAt(p + v(sx * 1.1, 0, 0), O + v(0, 4, 60)) * CFrame.Angles(0, 0, sx * math.rad(16)), v(1.4, 0.55, 0.3), rgb(255, 30, 20), M.Neon, { Transparency = 1, CanCollide = false, CastShadow = false })
			eye:SetAttribute("SporeEye", e)
		end
	end
	local spots = U.folder("K9Spots", m)
	spot(spots, "Arrive", O + v(-3, 3, 110), O)
	spot(spots, "RickArrive", O + v(3, 3.36, 108), O)
	spot(spots, "EvilArrive", O + v(-8, 3, 106), O)
	spot(spots, "Clearing", O + v(0, 3, 40), O)
	U.marker(spots, "Portal", CFrame.lookAt(O + v(-2, 6, 118), O + v(0, 6, 0)), v(1, 1, 1))
	U.marker(spots, "PortalOut", CFrame.lookAt(O + v(0, 6, 26), O + v(0, 6, 110)), v(1, 1, 1))
	return m
end

----------------------------------------------------------------------------
-- 5. The Alliance camera base in a ruined Skibidi city
----------------------------------------------------------------------------
local function tower(parent, base, w, d, h, yaw, broken)
	local t = U.model("Ruin", parent)
	local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	local concrete = rgb(118 + (h % 20), 114 + (h % 16), 110)
	U.part(t, "Block", cf * CFrame.new(0, h / 2, 0), v(w, h, d), concrete, M.Concrete)
	-- window bands (some lit)
	for k = 1, math.floor(h / 9) do
		local lit = (k + math.floor(w)) % 5 == 0
		local band = U.part(t, "Windows", cf * CFrame.new(0, k * 9 - 3, -d / 2 - 0.1), v(w - 3, 3.4, 0.3), if lit then rgb(255, 190, 120) else rgb(26, 28, 34), if lit then M.Neon else M.Glass, { CastShadow = false })
		band:SetAttribute("CityWindow", lit)
		U.part(t, "WindowsSide", cf * CFrame.new(-w / 2 - 0.1, k * 9 - 3, 0), v(0.3, 3.4, d - 3), rgb(26, 28, 34), M.Glass, { CastShadow = false })
	end
	if broken then
		-- a broken, slanted top and rubble
		U.part(t, "BrokenTop", cf * CFrame.new(w * 0.15, h + 3, 0) * CFrame.Angles(0.2, 0, -0.35), v(w * 0.7, 8, d * 0.8), concrete, M.Concrete)
		for r = 1, 4 do
			local p = base + v(U.randRange(-w, w), 1.5, U.randRange(-d, d))
			U.part(t, "Rubble", CFrame.new(p) * CFrame.Angles(U.rand() * 3, U.rand() * 3, U.rand() * 3), v(U.randRange(2, 6), U.randRange(1.5, 4), U.randRange(2, 6)), concrete, M.Concrete)
			local _ = r
		end
		U.part(t, "Rebar", cf * CFrame.new(-w * 0.2, h + 4, d * 0.2) * CFrame.Angles(0.3, 0, 0.4), v(0.4, 9, 0.4), rgb(90, 60, 40), M.Metal)
	end
	return t
end

local function sandbags(parent, from, to)
	local dir = to - from
	local len = dir.Magnitude
	local cf = CFrame.lookAt(from + dir / 2, to)
	U.part(parent, "Sandbags", cf * CFrame.new(0, 1.1, 0), v(2.2, 2.2, len), rgb(176, 156, 112), M.Fabric)
	U.part(parent, "SandbagsTop", cf * CFrame.new(0, 2.6, 0), v(1.8, 0.8, len - 0.6), rgb(186, 166, 120), M.Fabric)
end

local function buildBase(root)
	local O = Worlds.BASE
	local m = U.model("CameraBase", root)
	local concrete = rgb(120, 118, 114)
	U.part(m, "Ground", CFrame.new(O + v(0, -1, 0)), v(800, 2, 800), rgb(70, 70, 74), M.Asphalt)
	boxWall(m, O, 160, 40)
	-- cracks / stains on the ground
	for _ = 1, 40 do
		local p = O + v(U.randRange(-300, 300), 0.06, U.randRange(-300, 300))
		U.part(m, "Stain", CFrame.new(p) * CFrame.Angles(0, U.rand() * 3, 0), v(U.randRange(4, 16), 0.05, U.randRange(1, 6)), rgb(52, 52, 56), M.Asphalt, { CanCollide = false })
	end
	-- the ruined city around the base
	local ruins = U.model("Ruins", m)
	for i = 1, 22 do
		local a = (i / 22) * math.pi * 2 + U.randRange(-0.1, 0.1)
		local r = U.randRange(190, 330)
		local base = O + v(math.cos(a) * r, 0, math.sin(a) * r)
		tower(ruins, base, U.randRange(24, 44), U.randRange(24, 40), math.floor(U.randRange(40, 140)), a, i % 3 ~= 0)
	end
	-- smoke columns over the ruins
	for i = 1, 5 do
		local a = i * 1.3
		local p = U.marker(m, "SmokeColumn", CFrame.new(O + v(math.cos(a) * 240, 20, math.sin(a) * 240)), v(6, 1, 6))
		emitter(p, "CitySmoke", {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = U.ColorSequence.new(rgb(40, 36, 36), rgb(80, 70, 66)),
			Size = NS(8, 40),
			Transparency = NS(0.3, 1),
			Lifetime = U.NumberRange.new(8, 12),
			Speed = U.NumberRange.new(10, 16),
			SpreadAngle = U.Vector2.new(12, 12),
			Acceleration = v(4, 2, 0),
			Rate = 4,
			Enabled = false,
		})
	end

	-- the base: walls with a gate on the south side (+Z)
	local base = U.model("Base", m)
	local half = 78
	local function wallSeg(a, b)
		local dir = b - a
		local cf = CFrame.lookAt(a + dir / 2, b)
		U.part(base, "Wall", cf * CFrame.new(0, 5, 0), v(3, 10, dir.Magnitude), concrete, M.Concrete)
		U.part(base, "WallCap", cf * CFrame.new(0, 10.3, 0), v(3.6, 0.6, dir.Magnitude), rgb(96, 94, 90), M.Concrete)
		for k = 0, math.floor(dir.Magnitude / 12) do
			U.part(base, "Stripe", cf * CFrame.new(-1.6, 7.6, -dir.Magnitude / 2 + k * 12 + 3), v(0.2, 1, 6), rgb(220, 180, 40), M.SmoothPlastic, { CanCollide = false })
		end
	end
	local c1, c2, c3, c4 = O + v(-half, 0, -half), O + v(half, 0, -half), O + v(half, 0, half), O + v(-half, 0, half)
	wallSeg(c1, c2)
	wallSeg(c2, c3)
	wallSeg(c1, c4)
	wallSeg(c4, O + v(-14, 0, half))
	wallSeg(O + v(14, 0, half), c3)
	-- gate posts + barrier
	for _, sx in { -1, 1 } do
		U.part(base, "GatePost", CFrame.new(O + v(sx * 15.5, 7, half)), v(4, 14, 4), rgb(90, 88, 84), M.Concrete)
		local gl = U.ball(base, "GateLight", O + v(sx * 15.5, 14.8, half), 1.4, rgb(255, 60, 40), M.Neon, { CastShadow = false })
		light(gl, "GateLight", "PointLight", { Range = 18, Brightness = 1.5, Color = rgb(255, 70, 40) })
	end
	-- watchtowers in the corners
	for i, c in { c1, c2, c3, c4 } do
		local inward = (O - c).Unit
		local p = c + inward * 5
		for _, off in { v(-2.5, 0, -2.5), v(2.5, 0, -2.5), v(-2.5, 0, 2.5), v(2.5, 0, 2.5) } do
			U.vcyl(base, "TowerLeg", p + off, 22, 0.9, rgb(70, 66, 60), M.Metal)
		end
		U.part(base, "TowerFloor", CFrame.new(p + v(0, 22.5, 0)), v(8, 1, 8), rgb(96, 84, 70), M.WoodPlanks)
		U.part(base, "TowerRail", CFrame.new(p + v(0, 24, 0)), v(8, 2, 8), rgb(80, 72, 62), M.WoodPlanks, { Transparency = 0 })
		U.part(base, "TowerRoof", CFrame.new(p + v(0, 29, 0)), v(9.5, 0.8, 9.5), rgb(60, 70, 56), M.Metal)
		for _, off in { v(-3.8, 0, -3.8), v(3.8, 0, -3.8), v(-3.8, 0, 3.8), v(3.8, 0, 3.8) } do
			U.vcyl(base, "TowerPost", p + off + v(0, 23, 0), 6, 0.4, rgb(70, 66, 60), M.Metal)
		end
		local lamp = U.part(base, "Searchlight", CFrame.lookAt(p + v(0, 26.5, 0), O + v(0, 0, 0)), v(1.6, 1.6, 2.4), rgb(40, 40, 44), M.Metal)
		light(lamp, "Searchlight" .. i, "SpotLight", { Range = 60, Brightness = 3, Angle = 35, Face = Enum.NormalId.Front, Color = rgb(255, 240, 210) })
	end
	-- tents
	for i, p in { v(-46, 0, -20), v(-46, 0, 10), v(46, 0, -20), v(46, 0, 10) } do
		local cf = CFrame.new(O + p) * CFrame.Angles(0, if i <= 2 then 0 else math.pi, 0)
		local canvas = rgb(84, 98, 66)
		for _, sx in { -1, 1 } do
			U.part(base, "TentSide", cf * CFrame.new(sx * 3.2, 3.2, 0) * CFrame.Angles(0, 0, sx * math.rad(-38)), v(0.3, 8.4, 14), canvas, M.Fabric)
		end
		U.part(base, "TentBack", cf * CFrame.new(0, 2.4, 6.8), v(8, 4.8, 0.3), rgb(70, 82, 56), M.Fabric)
		U.part(base, "TentInside", cf * CFrame.new(0, 1.6, 0), v(5, 3, 13), rgb(30, 32, 28), M.Fabric, { CanCollide = false })
		U.part(base, "Cot", cf * CFrame.new(0, 0.8, 2), v(2.4, 0.4, 6), rgb(60, 70, 50), M.Fabric)
	end
	-- crates
	for i = 1, 12 do
		local p = O + v(U.randRange(-62, 62), 0, U.randRange(-62, 62))
		if math.abs(p.X - O.X) > 22 or math.abs(p.Z - O.Z) > 46 then
			local s = U.randRange(2.6, 4.2)
			U.part(base, "Crate", CFrame.new(p + v(0, s / 2, 0)) * CFrame.Angles(0, U.rand() * 3, 0), v(s, s, s), rgb(120, 92, 56), M.WoodPlanks)
			local _ = i
		end
	end
	-- sandbag rings
	for _, p in { v(-28, 0, 52), v(28, 0, 52), v(-60, 0, -52), v(60, 0, -52) } do
		local cpos = O + p
		for k = 0, 5 do
			local a1, a2 = k * math.pi / 3.6, (k + 1) * math.pi / 3.6
			sandbags(base, cpos + v(math.cos(a1) * 6, 0, math.sin(a1) * 6), cpos + v(math.cos(a2) * 6, 0, math.sin(a2) * 6))
		end
	end
	-- landing pad
	local pad = O + v(0, 0, 18)
	U.vcyl(base, "Pad", pad, 0.3, 58, rgb(58, 60, 64), M.Concrete)
	U.vcyl(base, "PadRing", pad + v(0, 0.3, 0), 0.06, 50, rgb(230, 230, 230), M.SmoothPlastic, { CanCollide = false })
	U.vcyl(base, "PadInner", pad + v(0, 0.32, 0), 0.06, 46, rgb(58, 60, 64), M.Concrete, { CanCollide = false })
	U.vcyl(base, "PadLens", pad + v(0, 0.34, 0), 0.06, 16, rgb(230, 230, 230), M.SmoothPlastic, { CanCollide = false })
	U.vcyl(base, "PadLensIn", pad + v(0, 0.36, 0), 0.06, 11, rgb(58, 60, 64), M.Concrete, { CanCollide = false })
	for k = 0, 11 do
		local a = k * math.pi / 6
		local lp = U.ball(base, "PadLight", pad + v(math.cos(a) * 28, 0.4, math.sin(a) * 28), 0.8, rgb(120, 200, 255), M.Neon, { CastShadow = false })
		lp:SetAttribute("PadLight", k)
	end
	-- the base bunker (north side)
	local bk = O + v(0, 0, -56)
	U.part(base, "BunkerBlock", CFrame.new(bk + v(0, 7, -6)), v(36, 14, 22), rgb(104, 102, 98), M.Concrete)
	U.part(base, "BunkerTop", CFrame.new(bk + v(0, 14.6, -6)), v(38, 1.2, 24), rgb(84, 82, 78), M.Concrete)
	U.part(base, "BlastFrame", CFrame.new(bk + v(0, 5.5, 5.2)), v(16, 11, 1), rgb(70, 70, 74), M.Metal)
	local door = U.model("BlastDoor", base)
	U.part(door, "DoorL", CFrame.new(bk + v(-3.4, 4.8, 5.8)), v(6.8, 9.4, 0.8), rgb(130, 134, 140), M.DiamondPlate)
	U.part(door, "DoorR", CFrame.new(bk + v(3.4, 4.8, 5.8)), v(6.8, 9.4, 0.8), rgb(130, 134, 140), M.DiamondPlate)
	for k = 0, 5 do
		U.part(base, "Hazard", CFrame.new(bk + v(-7.5 + k * 3, 10.6, 5.8)) * CFrame.Angles(0, 0, math.rad(40)), v(1, 2.6, 0.2), if k % 2 == 0 then rgb(230, 190, 30) else rgb(20, 20, 20), M.SmoothPlastic, { CanCollide = false })
	end
	local bl = U.ball(base, "BunkerLight", bk + v(0, 12.6, 6), 1.4, rgb(255, 60, 40), M.Neon, { CastShadow = false })
	light(bl, "BaseAlarmLight", "PointLight", { Range = 30, Brightness = 0, Color = rgb(255, 50, 30) })
	-- containment cube with the curse's head (red glow)
	local cube = O + v(-24, 0, -26)
	U.part(base, "Pedestal", CFrame.new(cube + v(0, 1, 0)), v(10, 2, 10), rgb(60, 62, 70), M.Metal)
	local glass = U.part(base, "Containment", CFrame.new(cube + v(0, 6.5, 0)), v(8, 9, 8), rgb(255, 120, 110), M.Glass, { Transparency = 0.6 })
	glass:SetAttribute("Containment", true)
	for _, e in { v(-4, 0, -4), v(4, 0, -4), v(-4, 0, 4), v(4, 0, 4) } do
		U.part(base, "CubeEdge", CFrame.new(cube + e + v(0, 6.5, 0)), v(0.4, 9, 0.4), rgb(255, 60, 40), M.Neon, { CastShadow = false })
	end
	U.part(base, "CubeLid", CFrame.new(cube + v(0, 11.2, 0)), v(8.6, 0.4, 8.6), rgb(60, 62, 70), M.Metal)
	-- antenna mast with a camera dish
	U.vcyl(base, "Mast", O + v(30, 0, -40), 36, 1.2, rgb(150, 150, 156), M.Metal)
	U.ellipsoid(base, "Dish", CFrame.new(O + v(30, 34, -38)) * CFrame.Angles(math.rad(-50), 0, 0), v(10, 2, 10), rgb(200, 200, 206), M.Metal)
	-- broken Skibidi toilets outside the walls (from earlier battles)
	for i, p in { v(-96, 0, 60), v(110, 0, 34), v(-120, 0, -70), v(88, 0, -110), v(20, 0, 120) } do
		local t = Characters.buildToilet(m, CFrame.new(O + p) * CFrame.Angles(0.15 * (i % 3), i * 1.3, 0.2), true)
		t.Name = "DeadToilet"
	end
	-- spots
	local spots = U.folder("BaseSpots", m)
	local padCenter = pad + v(0, 0, 0)
	U.marker(spots, "TitanLand", CFrame.lookAt(padCenter, padCenter + v(0, 0, -1)), v(4, 4, 4))
	spot(spots, "MortyLand", padCenter + v(-10, 3, -12), bk)
	spot(spots, "CamFriend", padCenter + v(-16, 3.45, -18), padCenter + v(-10, 3, -12))
	spot(spots, "LensFriend", padCenter + v(-19, 3.45, -14), padCenter + v(-10, 3, -12))
	spot(spots, "Commander", padCenter + v(8, 3.45, -26), padCenter + v(-10, 3, -12))
	spot(spots, "BunkerDoor", bk + v(0, 3, 14), bk)
	spot(spots, "RickPortal", O + v(-12, 3.36, -30), padCenter)
	U.marker(spots, "PortalRick", CFrame.lookAt(O + v(-16, 6, -34), padCenter + v(0, 6, 0)), v(1, 1, 1))
	U.marker(spots, "PortalHome", CFrame.lookAt(O + v(-8, 6, -40), O + v(-8, 6, 0)), v(1, 1, 1))
	U.marker(spots, "Mothership", CFrame.new(O + v(0, 420, -120)), v(4, 4, 4))
	U.marker(spots, "MothershipFar", CFrame.new(O + v(0, 1600, -2600)), v(4, 4, 4))
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local p = O + v(math.cos(a) * 130, 70 + (i % 3) * 22, math.sin(a) * 130)
		U.marker(spots, "Ship" .. i, CFrame.lookAt(p, O + v(0, 30, 0)), v(2, 2, 2))
	end
	-- a path from the pad to the bunker door (Morty walks it with his friends)
	for i, p in { padCenter + v(-10, 3, -16), padCenter + v(-6, 3, -34), padCenter + v(-2, 3, -52), bk + v(0, 3, 16) } do
		U.marker(spots, "Walk" .. i, CFrame.new(p), v(1, 1, 1))
	end
	-- formation rows for the agents inside the base
	local f = U.folder("BaseFormation", m)
	local n = 0
	for row = 0, 2 do
		for col = -3, 3 do
			n += 1
			local p = padCenter + v(col * 6 + (row % 2) * 3, 3.45, 34 + row * 7)
			U.marker(f, "F" .. n, CFrame.lookAt(p, v(p.X, p.Y, padCenter.Z)), v(1, 1, 1))
		end
	end
	return m
end

----------------------------------------------------------------------------
-- 6. B137: the bunker shed Rick "built" over the hatch (it's a trap)
----------------------------------------------------------------------------
local function buildShed(planetRoot, hatchPos, facing)
	local m = U.model("BunkerShed", planetRoot)
	local cf = CFrame.lookAt(hatchPos, hatchPos + facing)
	m.PrimaryPart = U.marker(m, "Center", cf, v(1, 1, 1))
	local plank = { rgb(120, 86, 56), rgb(110, 78, 50), rgb(132, 94, 60), rgb(104, 74, 48) }
	local W, D, H = 10, 10, 7.5
	local function boards(name, localCF, length, height, count, horizontal)
		for k = 0, count - 1 do
			local t = (k + 0.5) / count - 0.5
			local off = if horizontal then CFrame.new(0, t * height, 0) else CFrame.new(t * length, 0, 0)
			local size = if horizontal then v(length, height / count - 0.08, 0.5) else v(length / count - 0.08, height, 0.5)
			local p = U.part(m, name, cf * localCF * off * CFrame.Angles(0, 0, (U.rand() - 0.5) * 0.03), size, plank[(k % 4) + 1], M.WoodPlanks)
			p:SetAttribute("ShedPart", true)
		end
	end
	-- back and side walls
	boards("Back", CFrame.new(0, H / 2, D / 2), W, H, 7, false)
	boards("Left", CFrame.new(-W / 2, H / 2, 0) * CFrame.Angles(0, math.rad(90), 0), D, H, 6, true)
	boards("Right", CFrame.new(W / 2, H / 2, 0) * CFrame.Angles(0, math.rad(90), 0), D, H, 6, true)
	-- front wall with a door gap
	boards("FrontL", CFrame.new(-W / 2 + 1.6, H / 2, -D / 2), 3.2, H, 2, false)
	boards("FrontR", CFrame.new(W / 2 - 1.6, H / 2, -D / 2), 3.2, H, 2, false)
	boards("FrontTop", CFrame.new(0, H - 0.9, -D / 2), 3.6, 1.8, 2, true)
	-- the door (hinged on the left)
	local door = U.model("ShedDoor", m)
	for k = 0, 3 do
		local p = U.part(door, "DoorPlank", cf * CFrame.new(-1.35 + k * 0.9, 2.85, -D / 2 - 0.05), v(0.86, 5.7, 0.4), plank[(k % 4) + 1], M.WoodPlanks)
		p:SetAttribute("ShedPart", true)
	end
	local bar = U.part(door, "DoorBar", cf * CFrame.new(0, 2.85, -D / 2 - 0.3) * CFrame.Angles(0, 0, math.rad(35)), v(0.4, 6, 0.3), rgb(96, 68, 44), M.WoodPlanks)
	bar:SetAttribute("ShedPart", true)
	door:SetAttribute("Hinge", (cf * CFrame.new(-1.8, 0, -D / 2)).Position)
	-- slanted roof
	local roofCF = cf * CFrame.new(0, H + 0.45, 0) * CFrame.Angles(math.rad(-10), 0, 0)
	local roofLen = D + 1.6
	for k = 0, 5 do
		local p = U.part(m, "Roof", roofCF * CFrame.new(0, 0, -roofLen / 2 + (k + 0.5) * roofLen / 6), v(W + 1.4, 0.4, roofLen / 6 - 0.05), plank[(k % 4) + 1], M.WoodPlanks)
		p:SetAttribute("ShedPart", true)
	end
	-- painted sign (its front face looks out of the shed, towards the village)
	local sign = U.part(m, "Sign", cf * CFrame.new(0, H - 0.3, -D / 2 - 0.4), v(4.6, 1.2, 0.2), rgb(150, 112, 74), M.WoodPlanks)
	sign:SetAttribute("ShedPart", true)
	local gui = U.surfaceGui(sign, Enum.NormalId.Front, 60, 1)
	U.ui("TextLabel", {
		Name = "SignText",
		BackgroundTransparency = 1,
		Size = U.UDim2.fromScale(1, 1),
		Text = "БУНКЕР / BUNKER",
		TextScaled = true,
		Font = Enum.Font.PermanentMarker,
		TextColor3 = rgb(250, 240, 230),
		Parent = gui,
	})
	-- everything starts hidden
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
		end
	end
	m:SetAttribute("Hidden", true)
	U.marker(m, "DoorSpot", cf * CFrame.new(0, 3, -D / 2 - 4) * CFrame.Angles(0, math.pi, 0), v(2, 2, 1))
	return m
end

function Worlds.build(world, planetRoot, hatchPos)
	local root = U.model("Worlds", world)
	buildSilent(root)
	buildUpside(root)
	buildCube(root)
	buildMushroom(root)
	buildBase(root)
	-- the shed faces north, where Morty runs in from (the chase corridor)
	buildShed(planetRoot, hatchPos, v(0, 0, 1))
	local spots = U.folder("ChaseSpots", planetRoot)
	U.marker(spots, "Arrive", CFrame.lookAt(hatchPos + v(0, 3, 262), hatchPos + v(0, 3, 0)), v(2, 2, 1))
	U.marker(spots, "RickArrive", CFrame.lookAt(hatchPos + v(4.5, 3.36, 266), hatchPos + v(0, 3.36, 0)), v(2, 2, 1))
	U.marker(spots, "EvilArrive", CFrame.lookAt(hatchPos + v(-4.5, 3, 265), hatchPos + v(0, 3, 0)), v(2, 2, 1))
	U.marker(spots, "Portal", CFrame.lookAt(hatchPos + v(0, 6, 270), hatchPos + v(0, 6, 0)), v(1, 1, 1))
	return root
end

return Worlds
