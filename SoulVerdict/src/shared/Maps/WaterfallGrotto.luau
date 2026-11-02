--!strict
-- Maps/WaterfallGrotto: a flooded bioluminescent cavern (preset WaterfallGlow). [Lune-safe]
-- A shallow, wadeable lake (translucent water over a dark bed) holds five rocky islands joined by plank
-- boardwalks and arched bridges. North: a tall waterfall curtain pours into the plunge pool behind the
-- monster's basalt ledge. Centre: the Echo Isle (SAVE 1) under a skylight with a pale moonbeam. West:
-- the mossy Echo Garden, carpeted with glowing echo flowers (SAVE 2). East: the Crystal Grove, big cyan
-- crystal clusters as cover (SAVE 3). South: the landing with the old dock (human spawns), giant glowing
-- mushrooms on its flanks. Dark rock walls and a stalactite ceiling sparkle with crystal "stars".
-- Built around the origin (island tops y = 0 / 0.5 / 3, lake bed y = -1.6); MapService offsets it.
--
-- API (Types.MapDef): WaterfallGrotto.Id/Name/Desc/Preset/FinalPreset/Music
--   WaterfallGrotto.Build(seed?, opts?) -> MapInfo   opts = { Cutaway: boolean? } (no ceiling: overviews)
-- Layout constants: WaterfallGrotto.Layout (tests read them).

local Types = require(script.Parent.Parent.Types)
local MapKit = require(script.Parent.MapKit)
local MapStrings = require(script.Parent.Parent.Strings.Maps2)

type MapInfo = Types.MapInfo
type Builder = MapKit.Builder

local WaterfallGrotto = {}

WaterfallGrotto.Id = "WaterfallGrotto"
WaterfallGrotto.Name = MapStrings["maps.grotto.name"]
WaterfallGrotto.Desc = MapStrings["maps.grotto.desc"]
WaterfallGrotto.Preset = "WaterfallGlow"
WaterfallGrotto.FinalPreset = "WaterfallGlowFinal"
WaterfallGrotto.Music = "Map_WaterfallGrotto"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local V = Vector3.new
local M = Enum.Material
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder X axis -> world Y

-- Layout (studs; north = -Z) -------------------------------------------------------------------------------
local L = {
	Bound = 94, -- inradius of the playable octagon (invisible walls)
	Radius = 100, -- Collapse start radius
	KillY = -40,
	BedY = -1.6, -- lake bed (walkable)
	WaterY = -0.35, -- water surface (decor)
	CeilingY = 56, -- underside of the cave ceiling
	Skylight = V(0, 0, 4), -- centre of the ceiling opening (above the Echo Isle)
	SkylightR = 15,
	FallsZ = -97, -- waterfall curtain plane
	FallsHalfW = 26,
	FallsTop = 50,
	IsleTop = 0.5,
	LedgeTop = 3,
	MonsterSpawn = V(0, 3, -72),
}
WaterfallGrotto.Layout = L

local C = {
	Rock = rgb(48, 60, 76),
	RockDark = rgb(30, 38, 50),
	RockLight = rgb(70, 86, 102),
	Basalt = rgb(50, 58, 76),
	Floor = rgb(92, 112, 130),
	Moss = rgb(52, 118, 110),
	Sand = rgb(106, 118, 128),
	Bed = rgb(14, 36, 46),
	Water = rgb(26, 118, 132),
	Wood = rgb(104, 78, 58),
	WoodDark = rgb(66, 50, 40),
	Cyan = rgb(90, 232, 255),
	CrystalCyan = rgb(36, 150, 190),
	CrystalViolet = rgb(110, 74, 190),
	CyanLight = rgb(120, 220, 255),
	Teal = rgb(70, 255, 210),
	Violet = rgb(176, 124, 255),
	Echo = rgb(110, 176, 255),
	Falls = rgb(178, 238, 255),
	Foam = rgb(220, 248, 255),
	Warm = rgb(255, 196, 120),
	WarmLight = rgb(255, 178, 104),
	Stem = rgb(196, 210, 222),
	Cap = rgb(46, 70, 112),
	Iron = rgb(34, 36, 44),
}

local DIAG = L.Bound * math.sqrt(2)

local function inside(x: number, z: number, margin: number): boolean
	return math.abs(x) <= L.Bound - margin and math.abs(z) <= L.Bound - margin and math.abs(x) + math.abs(z) <= DIAG - margin * 1.4142
end

-- Islands: unions of rotated slabs {x, z, sizeX, sizeZ, yawDeg}; each slab sits SLAB_STEP higher than the
-- previous one so overlapping tops never z-fight (groundY returns the real top at a point).
type Island = { Name: string, Top: number, Color: Color3, Material: Enum.Material, Slabs: { { number } } }

local ISLANDS: { Island } = {
	{
		Name = "Landing",
		Top = 0,
		Color = C.Sand,
		Material = M.Ground,
		Slabs = { { 0, 79, 118, 36, 0 }, { -54, 74, 32, 26, 16 }, { 54, 74, 32, 26, -16 } },
	},
	{
		Name = "EchoIsle",
		Top = L.IsleTop,
		Color = C.Floor,
		Material = M.Slate,
		Slabs = { { 0, 4, 28, 26, 0 }, { -3, 3, 22, 34, 32 }, { 3, 7, 32, 18, -24 } },
	},
	{
		Name = "Garden",
		Top = 0,
		Color = C.Moss,
		Material = M.Grass,
		Slabs = { { -64, -8, 52, 78, 4 }, { -47, 24, 30, 26, -14 }, { -74, 28, 30, 30, 10 }, { -56, -44, 36, 20, -8 } },
	},
	{
		Name = "Grove",
		Top = 0,
		Color = C.Floor,
		Material = M.Slate,
		Slabs = { { 64, -6, 50, 78, -5 }, { 50, -38, 30, 22, 12 }, { 72, 30, 30, 26, -10 }, { 45, 22, 22, 24, 16 } },
	},
	{
		Name = "Ledge",
		Top = L.LedgeTop,
		Color = C.Basalt,
		Material = M.Basalt,
		Slabs = { { 0, -71, 60, 20, 0 }, { -21, -63, 22, 14, 10 }, { 21, -63, 22, 14, -10 } },
	},
}

local SLAB_STEP = 0.03

local function slabFrame(slab: { number }, y: number): CFrame
	return CFrame.new(slab[1], y, slab[2]) * CFrame.Angles(0, math.rad(slab[5]), 0)
end

local function inSlab(slab: { number }, p: Vector3, margin: number): boolean
	local lp = slabFrame(slab, 0):PointToObjectSpace(V(p.X, 0, p.Z))
	return math.abs(lp.X) <= slab[3] / 2 - margin and math.abs(lp.Z) <= slab[4] / 2 - margin
end

local function onIsland(isle: Island, p: Vector3, margin: number): boolean
	for _, slab in isle.Slabs do
		if inSlab(slab, p, margin) then
			return true
		end
	end
	return false
end

-- Walkable top at (x, z): the highest island slab covering it, else the lake bed.
local function groundY(p: Vector3): number
	local best = L.BedY
	for _, isle in ISLANDS do
		for i, slab in isle.Slabs do
			if inSlab(slab, p, 0) then
				best = math.max(best, isle.Top + (i - 1) * SLAB_STEP)
			end
		end
	end
	return best
end

local function onGround(x: number, z: number): Vector3
	local p = V(x, 0, z)
	return V(x, groundY(p), z)
end

-- Boardwalk / bridge landings (shore rocks keep clear of them)
local CROSSINGS: { { Vector3 } } = {
	{ V(0, 0.6, 63), V(0, 0.6, 15) }, -- dock: landing -> Echo Isle
	{ V(-12, 0.6, 2), V(-40, 0.6, -2) }, -- isle -> garden
	{ V(12, 0.6, 6), V(41, 0.6, 10) }, -- isle -> grove
	{ V(-50, 0.6, 63), V(-55, 0.6, 33) }, -- landing -> garden
	{ V(50, 0.6, 63), V(53, 0.6, 32) }, -- landing -> grove
}
local BRIDGES: { { Vector3 } } = {
	{ V(0, L.IsleTop + 0.25, -8), V(0, L.LedgeTop + 0.25, -62) }, -- isle -> ledge (long arch)
	{ V(-29, L.LedgeTop + 0.25, -67), V(-46, 0.25, -48) }, -- ledge -> garden
	{ V(29, L.LedgeTop + 0.25, -67), V(46, 0.25, -45) }, -- ledge -> grove
}

local function nearCrossing(p: Vector3, radius: number): boolean
	for _, list in { CROSSINGS, BRIDGES } do
		for _, seg in list do
			for _, e in seg do
				if (V(p.X, 0, p.Z) - V(e.X, 0, e.Z)).Magnitude < radius then
					return true
				end
			end
		end
	end
	return false
end

-- Lake, islands, shores -------------------------------------------------------------------------------------

local function buildLake(B: Builder)
	B:Group("Lake")
	B:Solid("Block", "LakeBed", V(320, 6, 320), CFrame.new(0, L.BedY - 3, 0), C.Bed, M.Slate)
	B:Deco("Block", "Water", V(300, 0.3, 300), CFrame.new(0, L.WaterY - 0.15, 0), C.Water, M.Glass, {
		Transparency = 0.3,
		Reflectance = 0.15,
		Shadow = false,
	})
	B:Group(nil)
end

local function buildIslands(B: Builder)
	B:Group("Islands")
	local rng = B.Rng
	for _, isle in ISLANDS do
		for i, slab in isle.Slabs do
			local top = isle.Top + (i - 1) * SLAB_STEP
			local h = top - L.BedY + 2
			B:Solid("Block", isle.Name, V(slab[3], h, slab[4]), slabFrame(slab, top - h / 2), MapKit.Shade(isle.Color, (i % 2) * 0.02), isle.Material)
		end
		-- shoreline: half-submerged decor stones along the outer edges (not inside a sibling slab)
		for _, slab in isle.Slabs do
			local frame = slabFrame(slab, 0)
			local hx, hz = slab[3] / 2, slab[4] / 2
			local edges = { { V(-hx, 0, -hz), V(hx, 0, -hz) }, { V(hx, 0, -hz), V(hx, 0, hz) }, { V(hx, 0, hz), V(-hx, 0, hz) }, { V(-hx, 0, hz), V(-hx, 0, -hz) } }
			for _, e in edges do
				local len = (e[2] - e[1]).Magnitude
				local n = math.max(1, math.floor(len / 7))
				for k = 0, n - 1 do
					local lp = e[1]:Lerp(e[2], (k + rng:Number(0.2, 0.8)) / n)
					local p = frame * lp
					local covered = false
					for _, other in isle.Slabs do
						if other ~= slab and inSlab(other, p, -0.5) then
							covered = true
						end
					end
					if not covered and inside(p.X, p.Z, -6) and not nearCrossing(p, 5) then
						B:Rock("Shore", V(p.X, isle.Top - 0.9, p.Z), rng:Number(1.8, 3.4), {
							Collide = false,
							Chunks = 1,
							Color = MapKit.Shade(C.RockDark, rng:Number(-0.05, 0.08)),
							Material = M.Slate,
						})
					end
				end
			end
		end
	end
	-- ramps from the basalt ledge down to the water on its east and west tips
	for _, sx in { -1, 1 } do
		B:Solid("Wedge", "LedgeRamp", V(10, L.LedgeTop - L.BedY, 9), CFrame.new(sx * 34.5, (L.LedgeTop + L.BedY) / 2, -77) * CFrame.Angles(0, -sx * math.pi / 2, 0), C.Basalt, M.Basalt)
	end
	B:Group(nil)
end

-- Walkways --------------------------------------------------------------------------------------------------

local function boardwalk(B: Builder, name: string, a: Vector3, b: Vector3, width: number)
	local rng = B.Rng
	local delta = b - a
	local flatDir = V(delta.X, 0, delta.Z).Unit
	local side = V(-flatDir.Z, 0, flatDir.X)
	local len = V(delta.X, 0, delta.Z).Magnitude
	local n = math.max(2, math.floor(len / 1.6 + 0.5))
	for i = 0, n - 1 do
		local p0 = a:Lerp(b, i / n)
		local p1 = a:Lerp(b, (i + 1) / n)
		local mid = (p0 + p1) / 2
		local frame = CFrame.fromMatrix(mid - V(0, 0.18, 0), side, V(0, 1, 0), side:Cross(V(0, 1, 0))) * CFrame.Angles(0, math.rad(rng:Number(-1.5, 1.5)), 0)
		B:Solid("Block", name .. "_Plank", V(width + rng:Number(-0.3, 0.3), 0.36, (p1 - p0).Magnitude - 0.18), frame, MapKit.Shade(C.Wood, rng:Number(-0.12, 0.06)), M.WoodPlanks)
	end
	for _, s in { -1, 1 } do
		local off = side * (s * (width / 2 - 0.5))
		B:Beam("Decor", name .. "_Stringer", a + off - V(0, 0.6, 0), b + off - V(0, 0.6, 0), 0.5, 0.5, C.WoodDark, M.Wood)
		local posts = math.max(1, math.floor(len / 7))
		for k = 0, posts do
			local p = a:Lerp(b, k / posts) + side * (s * (width / 2 + 0.1))
			B:Deco("Cylinder", name .. "_Post", V(p.Y - L.BedY + 0.9, 0.5, 0.5), CFrame.new(V(p.X, (p.Y + 0.9 + L.BedY) / 2, p.Z)) * UPRIGHT, C.WoodDark, M.Wood)
		end
	end
end

local function lantern(B: Builder, name: string, base: Vector3, warm: boolean): number
	local light = B:Lamp(name, base, {
		Style = "Post",
		Height = 7,
		Metal = C.Iron,
		Glow = if warm then C.Warm else C.CyanLight,
		LightColor = if warm then C.WarmLight else C.Cyan,
		Brightness = if warm then 1.8 else 1.5,
		Range = 18,
	})
	return if light then 1 else 0
end

local function buildWalkways(B: Builder): number
	B:Group("Walkways")
	local lights = 0
	for i, seg in CROSSINGS do
		boardwalk(B, "Boardwalk" .. i, seg[1], seg[2], if i == 1 then 7 else 6)
	end
	for i, seg in BRIDGES do
		B:Bridge("Bridge" .. i, seg[1], seg[2], if i == 1 then 8 else 7, { Arch = if i == 1 then 3.2 else 2, Color = C.Wood })
	end
	-- cyan lanterns along the long dock, warm ones where the travellers landed
	for _, z in { 50, 30 } do
		lights += lantern(B, "DockLantern", V(-4.6, 0.6, z), false)
	end
	B:Group(nil)
	return lights
end

-- Waterfall (north) ---------------------------------------------------------------------------------------------

local function buildFalls(B: Builder): number
	B:Group("Falls")
	local rng = B.Rng
	local z = L.FallsZ
	local hw = L.FallsHalfW
	-- recess wall behind the curtain + the crevice lip it pours from
	B:Deco("Block", "FallsBack", V(hw * 2 + 30, 80, 6), CFrame.new(0, 30, z - 6), C.RockDark, M.Slate)
	B:Deco("Block", "FallsLip", V(hw * 2 + 8, 4, 8), CFrame.new(0, L.FallsTop + 2, z - 1), C.Rock, M.Slate)
	-- the curtain: a sheet of translucent glassy strips with thin glowing streaks stacked in front
	local strips = 13
	local w = hw * 2 / strips
	for i = 0, strips - 1 do
		local x = -hw + (i + 0.5) * w
		local top = L.FallsTop + rng:Number(-1.5, 0.5)
		local h = top - L.WaterY
		B:Deco("Block", "Curtain", V(w * 1.05, h, 0.4), CFrame.new(x, L.WaterY + h / 2, z + rng:Number(-0.3, 0.3)), MapKit.Shade(rgb(60, 140, 172), rng:Number(-0.08, 0.06)), M.Glass, {
			Transparency = 0.25,
			Shadow = false,
		})
	end
	for i = 0, 2 * strips - 1 do
		local x = -hw + (i + 0.5) * (w / 2) + rng:Number(-0.4, 0.4)
		local top = L.FallsTop + rng:Number(-6, 0)
		local h = top - L.WaterY - rng:Number(0, 8)
		B:Deco("Block", "Streak", V(rng:Number(0.35, 0.9), h, 0.2), CFrame.new(x, top - h / 2, z + 0.9 + rng:Number(0, 0.6)), MapKit.Shade(C.Falls, rng:Number(-0.25, 0)), M.Neon, {
			Transparency = rng:Number(0.35, 0.6),
			Shadow = false,
		})
	end
	-- churning foam + mist at the base, the top lip spill
	for i = 0, 9 do
		local x = -hw + (i + 0.5) * (hw * 2 / 10)
		B:Deco("Ellipsoid", "Foam", V(rng:Number(6, 9), rng:Number(1.0, 1.8), rng:Number(4, 6)), CFrame.new(x, L.WaterY + 0.15, z + 2.2 + rng:Number(-0.6, 0.6)), rgb(150, 210, 230), M.Neon, {
			Transparency = 0.55,
			Shadow = false,
		})
	end
	B:Deco("Cylinder", "Spill", V(hw * 2 + 2, 1.6, 1.6), CFrame.new(0, L.FallsTop + 0.2, z + 0.4), rgb(150, 210, 230), M.Neon, { Transparency = 0.5, Shadow = false })
	local mist = B:Deco("Block", "Mist", V(hw * 2, 1, 6), CFrame.new(0, 1, z + 4), C.Foam, M.SmoothPlastic, { Transparency = 1, Shadow = false })
	B:Particles(mist, "Smoke", { Color = rgb(170, 230, 255), Rate = 6 })
	B:Particles(mist, "Sparkles", { Color = C.CyanLight, Rate = 4 })
	-- framing rocks and the lights that make the curtain glow onto the ledge
	for _, sx in { -1, 1 } do
		for k = 0, 3 do
			local p = V(sx * (hw + 3 + k * 1.5), k * 12 + 4, z + rng:Number(-1, 2))
			B:Rock("FallsRock", p, rng:Number(7, 11), { Collide = false, Chunks = 1, Color = C.Rock, Material = M.Slate })
		end
	end
	for _, x in { -13, 13 } do
		B:Light("Point", V(x, 7, z + 8), { Name = "FallsLight", Brightness = 2.2, Range = 42, Color = rgb(150, 230, 255) })
	end
	B:Group(nil)
	return 2
end

-- Flora and crystals ---------------------------------------------------------------------------------------------

local function echoFlower(B: Builder, name: string, base: Vector3, color: Color3)
	local rng = B.Rng
	local h = rng:Number(1.1, 1.9)
	local lean = V(rng:Number(-0.25, 0.25), 0, rng:Number(-0.25, 0.25))
	local head = base + V(0, h, 0) + lean
	B:Rod("Decor", name .. "_Stem", base, head, 0.12, rgb(40, 110, 100), M.SmoothPlastic, { Shadow = false })
	local yaw = rng:Number(0, 360)
	for k = 0, 2 do
		local frame = CFrame.new(head) * CFrame.Angles(0, math.rad(yaw + k * 120), 0) * CFrame.new(0.42, 0.08, 0) * CFrame.Angles(0, 0, math.rad(24))
		B:Deco("Ellipsoid", name .. "_Petal", V(1.0, 0.14, 0.52), frame, color, M.Neon, { Shadow = false })
	end
	B:Deco("Ball", name .. "_Heart", V(0.32, 0.32, 0.32), CFrame.new(head + V(0, 0.14, 0)), rgb(230, 250, 255), M.Neon, { Shadow = false })
end

local function flowerPatch(B: Builder, name: string, center: Vector3, radius: number, count: number, withLight: boolean, color: Color3?): number
	local rng = B.Rng
	local col = color or C.Echo
	for _ = 1, count do
		local x, z = rng:InCircle(radius)
		echoFlower(B, name, center + V(x, 0, z), MapKit.Shade(col, rng:Number(-0.08, 0.1)))
	end
	-- a soft moss disc under the patch
	B:Disc("Decor", name .. "_Moss", center + V(0, 0.03, 0), radius * 2 + 2, 0.06, MapKit.Shade(C.Moss, 0.08), M.Grass, { Shadow = false })
	if withLight then
		B:Light("Point", center + V(0, 2.2, 0), { Name = name .. "_Light", Brightness = 1.3, Range = 14, Color = col })
		return 1
	end
	return 0
end

local function mushroom(B: Builder, name: string, base: Vector3, height: number, capD: number, glow: Color3, withLight: boolean): number
	local rng = B.Rng
	local tilt = CFrame.Angles(math.rad(rng:Number(-6, 6)), 0, math.rad(rng:Number(-6, 6)))
	local root = CFrame.new(base) * tilt
	local stemD = math.max(0.5, capD * 0.18)
	if height >= 5 then
		B:Solid("Cylinder", name .. "_Stem", V(height, stemD, stemD), root * CFrame.new(0, height / 2, 0) * UPRIGHT, C.Stem, M.SmoothPlastic)
	else
		B:Deco("Cylinder", name .. "_Stem", V(height, stemD, stemD), root * CFrame.new(0, height / 2, 0) * UPRIGHT, C.Stem, M.SmoothPlastic)
	end
	local capCF = root * CFrame.new(0, height, 0)
	B:Deco("Ellipsoid", name .. "_Cap", V(capD, capD * 0.42, capD), capCF * CFrame.new(0, capD * 0.08, 0), MapKit.Shade(C.Cap, rng:Number(-0.06, 0.08)), M.SmoothPlastic)
	B:Deco("Cylinder", name .. "_Gills", V(0.12, capD * 0.86, capD * 0.86), capCF * CFrame.new(0, -0.02, 0) * UPRIGHT, glow, M.Neon, { Shadow = false })
	if capD >= 5 then
		for k = 0, 3 do
			local a = math.rad(k * 90 + rng:Number(0, 60))
			local r = capD * rng:Number(0.18, 0.32)
			B:Deco("Ball", name .. "_Spot", V(capD * 0.09, capD * 0.09, capD * 0.09), capCF * CFrame.new(math.cos(a) * r, capD * 0.24, math.sin(a) * r), MapKit.Shade(glow, 0.2), M.Neon, { Shadow = false })
		end
	end
	if withLight then
		B:Light("Point", (capCF * CFrame.new(0, -1.2, 0)).Position, { Name = name .. "_Light", Brightness = 1.4, Range = 16, Color = glow })
		return 1
	end
	return 0
end

local function crystalCluster(B: Builder, name: string, base: Vector3, height: number, color: Color3, withLight: boolean): number
	local light = B:Crystal(name, base, height, { Color = color, Count = 5, Light = withLight, Brightness = 1.8, Range = 20, Transparency = 0.35 })
	-- the glass shards are decor: a solid rock foot + an invisible core make the cluster real cover
	B:Rock(name .. "_Foot", base, height * 0.32, { Collide = true, Chunks = 1, Color = C.RockDark, Material = M.Slate })
	B:Solid("Block", name .. "_Core", V(height * 0.26, height * 0.85, height * 0.26), CFrame.new(base + V(0, height * 0.42, 0)), color, M.SmoothPlastic, {
		Transparency = 1,
		Shadow = false,
	})
	return if light then 1 else 0
end

local function buildFlora(B: Builder): number
	B:Group("Flora")
	local lights = 0
	-- the Echo Garden (west): flower meadows around SAVE 2
	local patches = {
		{ X = -74, Z = -30, R = 6, N = 12 },
		{ X = -50, Z = -18, R = 5, N = 10 },
		{ X = -80, Z = 2, R = 5, N = 9 },
		{ X = -52, Z = 30, R = 5, N = 9 },
		{ X = -76, Z = 36, R = 4, N = 7 },
	}
	for i, pt in patches do
		lights += flowerPatch(B, "EchoPatch", onGround(pt.X, pt.Z), pt.R, pt.N, i <= 4)
	end
	-- the Echo Isle: two patches flanking the SAVE ring
	lights += flowerPatch(B, "IslePatch", onGround(-10, 14), 3, 6, true)
	flowerPatch(B, "IslePatch", onGround(12, -5), 3, 6, false, C.Teal)
	-- violet patches on the grove, cyan on the landing
	lights += flowerPatch(B, "GrovePatch", onGround(80, 22), 4, 7, true, C.Violet)
	flowerPatch(B, "LandingPatch", onGround(-30, 70), 4, 7, false)
	-- giant mushrooms: the landing's flanks and the garden's south shore
	local pink = rgb(255, 120, 220)
	local shrooms = {
		{ X = -40, Z = 78, H = 11, D = 9, Glow = C.Teal, Light = true },
		{ X = -48, Z = 70, H = 7, D = 6, Glow = C.Teal, Light = false },
		{ X = -62, Z = 80, H = 9, D = 8, Glow = pink, Light = true },
		{ X = 40, Z = 80, H = 10, D = 8.5, Glow = pink, Light = true },
		{ X = 50, Z = 72, H = 6.5, D = 5.5, Glow = C.Teal, Light = false },
		{ X = -66, Z = 30, H = 9, D = 8, Glow = C.Teal, Light = true },
		{ X = -84, Z = 16, H = 7, D = 6.5, Glow = pink, Light = false },
		{ X = 84, Z = -30, H = 8, D = 7, Glow = C.Teal, Light = true },
	}
	for _, m in shrooms do
		local base = onGround(m.X, m.Z)
		lights += mushroom(B, "Mushroom", base, m.H, m.D, m.Glow, m.Light)
		-- a few small ones at the foot of each giant
		for k = 1, 3 do
			local a = math.rad(k * 120 + B.Rng:Number(0, 40))
			local r = m.D * 0.55 + B.Rng:Number(0.5, 1.5)
			mushroom(B, "Toadstool", base + V(math.cos(a) * r, 0, math.sin(a) * r), B.Rng:Number(0.9, 1.8), B.Rng:Number(1.1, 1.8), m.Glow, false)
		end
	end
	-- the Crystal Grove (east): big clusters as cover, small shards around
	local clusters = {
		{ X = 48, Z = -22, H = 14, Light = true },
		{ X = 76, Z = -8, H = 17, Light = true },
		{ X = 58, Z = 24, H = 12, Light = true },
		{ X = 80, Z = -44, H = 13, Light = false },
		{ X = 47, Z = 0, H = 9, Light = false },
		{ X = -58, Z = -40, H = 11, Light = true },
		{ X = -86, Z = -16, H = 13, Light = false },
	}
	for i, c in clusters do
		lights += crystalCluster(B, "Crystal", onGround(c.X, c.Z), c.H, if i % 3 == 0 then C.CrystalViolet else C.CrystalCyan, c.Light)
	end
	local rng = B.Rng
	for _ = 1, 14 do
		local x, z = rng:InCircle(26)
		local p = V(64 + x, 0, -4 + z)
		if (p - V(64, 0, -22)).Magnitude > 11 and (p - V(47, 0, 0)).Magnitude > 4 then
			B:Crystal("Shard", p, rng:Number(1.6, 3.6), { Color = C.Cyan, Count = 2, Light = false })
		end
	end
	B:Group(nil)
	return lights
end

-- Cave shell: walls, ceiling, stalactites, star crystals, skylight -----------------------------------------------

local function octagonRadius(angle: number): number
	local a = math.deg(angle) % 45
	return L.Bound / math.cos(math.rad(a - 22.5))
end

local function buildCave(B: Builder, cutaway: boolean): number
	B:Group("Cave")
	local rng = B.Rng
	local lights = 0
	-- wall: a ring of huge tilted rock slabs just outside the invisible walls (gap behind the falls)
	local n = 44
	for k = 0, n - 1 do
		local a = (k + rng:Number(-0.3, 0.3)) * 2 * math.pi / n
		local r = octagonRadius(a) + rng:Number(5, 10)
		local x, z = math.sin(a) * r, -math.cos(a) * r
		if not (math.abs(x) < L.FallsHalfW + 4 and z < -80) then
			local h = if cutaway then rng:Number(18, 30) else rng:Number(58, 70)
			local cf = CFrame.new(x, h / 2 - 4, z) * CFrame.Angles(0, -a + rng:Number(-0.4, 0.4), 0) * CFrame.Angles(math.rad(rng:Number(-8, 8)), 0, math.rad(rng:Number(-6, 6)))
			B:Deco("Block", "Wall", V(rng:Number(20, 30), h, rng:Number(12, 18)), cf, MapKit.Shade(C.Rock, rng:Number(-0.1, 0.06)), M.Slate)
			-- a lower boulder in front, partly inside the arena (cover near the walls)
			if k % 2 == 0 then
				local rb = octagonRadius(a) + rng:Number(-1, 2)
				B:Rock("WallBoulder", V(math.sin(a) * rb, rng:Number(-1, 0), -math.cos(a) * rb), rng:Number(7, 11), { Chunks = 1, Color = C.RockLight, Material = M.Slate })
			end
		end
	end
	-- glowing crystal veins on the walls
	for k = 0, 11 do
		local a = (k + 0.5) * 2 * math.pi / 12 + rng:Number(-0.1, 0.1)
		local r = octagonRadius(a) + 2
		local p = V(math.sin(a) * r, rng:Number(6, 22), -math.cos(a) * r)
		if not (math.abs(p.X) < L.FallsHalfW + 6 and p.Z < -80) then
			local withLight = k % 2 == 0
			local light = B:Crystal("WallCrystal", p, rng:Number(5, 9), { Color = if k % 4 == 1 then C.CrystalViolet else C.CrystalCyan, Count = 3, Light = withLight, Brightness = 1.4, Range = 22 })
			if light then
				lights += 1
			end
		end
	end
	-- stalagmites rising from the lake near the walls
	for _ = 1, 14 do
		local a = rng:Number(0, 2 * math.pi)
		local r = octagonRadius(a) - rng:Number(4, 14)
		local p = V(math.sin(a) * r, L.BedY, -math.cos(a) * r)
		local onLand = false
		for _, isle in ISLANDS do
			if onIsland(isle, p, -2) then
				onLand = true
			end
		end
		if not onLand and not (math.abs(p.X) < L.FallsHalfW + 4 and p.Z < -78) then
			local h = rng:Number(6, 14)
			B:Cone("Decor", "Stalagmite", p, h, h * 0.22, 5, MapKit.Shade(C.Rock, rng:Number(-0.05, 0.1)), M.Slate, { Phase = rng:Number(0, 72) })
		end
	end
	if not cutaway then
		-- ceiling slabs around the skylight opening
		local y = L.CeilingY + 5
		local s = L.Skylight
		local R = L.SkylightR
		local big = 260
		B:Deco("Block", "CeilingN", V(big, 10, big / 2), CFrame.new(0, y, s.Z - R - big / 4), C.RockDark, M.Slate)
		B:Deco("Block", "CeilingS", V(big, 10, big / 2), CFrame.new(0, y, s.Z + R + big / 4), C.RockDark, M.Slate)
		B:Deco("Block", "CeilingW", V(big / 2, 10, R * 2 + 1), CFrame.new(s.X - R - big / 4, y, s.Z), C.RockDark, M.Slate)
		B:Deco("Block", "CeilingE", V(big / 2, 10, R * 2 + 1), CFrame.new(s.X + R + big / 4, y, s.Z), C.RockDark, M.Slate)
		-- rough rim stones around the opening
		for k = 0, 9 do
			local a = k * 2 * math.pi / 10
			B:Rock("SkylightRim", s + V(math.cos(a) * R, L.CeilingY - 1, math.sin(a) * R), rng:Number(5, 8), { Collide = false, Chunks = 1, Color = C.Rock, Material = M.Slate })
		end
		-- lumpy underside + stalactites
		for _ = 1, 16 do
			local x, z = rng:InCircle(86)
			if (V(x, 0, z) - V(s.X, 0, s.Z)).Magnitude > R + 8 then
				local size = rng:Number(14, 26)
				B:Deco("Block", "CeilingLump", V(size, rng:Number(4, 8), size * rng:Number(0.6, 1)), CFrame.new(x, L.CeilingY - 1, z) * CFrame.Angles(math.rad(rng:Number(-10, 10)), rng:Number(0, 6.28), 0), C.RockDark, M.Slate)
			end
		end
		for _ = 1, 22 do
			local x, z = rng:InCircle(88)
			if (V(x, 0, z) - V(s.X, 0, s.Z)).Magnitude > R + 4 then
				local h = rng:Number(5, 13)
				B:Cone("Decor", "Stalactite", V(x, L.CeilingY + 0.5, z), -h, h * 0.2, 4, MapKit.Shade(C.Rock, rng:Number(-0.08, 0.06)), M.Slate, { Phase = rng:Number(0, 90), Shadow = false })
			end
		end
		-- the ceiling "stars": tiny glowing crystal points
		local starColors = { C.CyanLight, rgb(230, 250, 255), C.Violet, C.Teal }
		for i = 1, 130 do
			local x, z = rng:InCircle(92)
			if (V(x, 0, z) - V(s.X, 0, s.Z)).Magnitude > R + 2 then
				local d = rng:Number(0.25, 0.7)
				B:Deco("Ball", "CeilingStar", V(d, d, d), CFrame.new(x, L.CeilingY - 0.4 - rng:Number(0, 1.2), z), starColors[i % #starColors + 1], M.Neon, { Shadow = false })
			end
		end
	end
	-- the moonbeam through the skylight onto the Echo Isle
	local s = L.Skylight
	-- (a soft translucent cylinder: no hard box edges when a player walks through it)
	local beamTop = s + V(0, L.CeilingY + 4, 0)
	local beamDir = V(0.12, -1, 0.08).Unit
	B:Rod("Decor", "Moonbeam", beamTop, beamTop + beamDir * (L.CeilingY + 4.5), L.SkylightR * 0.85, rgb(70, 110, 150), M.Neon, {
		Transparency = 0.965,
		Shadow = false,
	})
	-- broad, dim teal fill so the island floors stay readable between the glowing landmarks
	for _, p in { V(0, 22, 76), V(-60, 22, -4), V(60, 22, -6), V(0, 22, -66), V(0, 20, 38), V(0, 20, -30) } do
		B:Light("Point", p, { Name = "CaveFill", Brightness = 1.3, Range = 55, Color = rgb(90, 170, 200) })
		lights += 1
	end
	B:Light("Spot", MapKit.LookAt(s + V(0, L.CeilingY - 2, 0), s), { Name = "MoonbeamLight", Brightness = 2, Range = 70, Angle = 38, Color = rgb(170, 215, 255) })
	B:Group(nil)
	return lights + 1
end

-- Props: the landing, the isle's plaque, signs ------------------------------------------------------------------

local function rowboat(B: Builder, name: string, cf: CFrame)
	-- simple hull: a floor plank, two tapered sides, a bow wedge, two benches
	B:Deco("Block", name .. "_Floor", V(2.4, 0.3, 7), cf * CFrame.new(0, 0.2, 0), C.WoodDark, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		B:Deco("Block", name .. "_Side", V(0.3, 1.1, 7.2), cf * CFrame.new(sx * 1.3, 0.7, 0.1) * CFrame.Angles(0, 0, math.rad(sx * -14)), C.Wood, M.WoodPlanks)
	end
	B:Deco("Wedge", name .. "_Bow", V(2.9, 1.2, 2.4), cf * CFrame.new(0, 0.65, -4.6) * CFrame.Angles(0, math.pi, 0), C.Wood, M.WoodPlanks)
	for _, z in { -1.5, 1.6 } do
		B:Deco("Block", name .. "_Bench", V(2.5, 0.25, 0.8), cf * CFrame.new(0, 0.9, z), C.WoodDark, M.Wood)
	end
	B:Rod("Decor", name .. "_Oar", (cf * CFrame.new(-0.6, 1.0, 0)).Position, (cf * CFrame.new(1.8, 0.3, 2.6)).Position, 0.18, C.WoodDark, M.Wood)
end

local function buildLanding(B: Builder): number
	B:Group("Landing")
	local lights = 0
	-- warm lanterns: the travellers' side of the cave
	for _, p in { V(-12, 0, 68), V(12, 0, 68), V(-26, 0, 90), V(26, 0, 90) } do
		lights += lantern(B, "LandingLantern", p, true)
	end
	-- the old dock (a pier east of the main boardwalk) with a moored rowboat
	boardwalk(B, "Pier", V(22, 0.6, 66), V(26, 0.6, 50), 5)
	rowboat(B, "Rowboat", CFrame.new(31, L.WaterY - 0.1, 54) * CFrame.Angles(0, math.rad(8), 0))
	B:Rod("Decor", "MooringRope", V(26.5, 1.2, 52), V(31.5, 0.4, 51), 0.12, rgb(180, 160, 120), M.Fabric, { Shadow = false })
	-- crates, barrels and a signpost at the head of the dock
	for i, p in { V(-17, 0, 92), V(-14.6, 0, 92.6), V(17, 0, 93) } do
		local s = if i == 2 then 2 else 2.8
		B:Solid("Block", "Crate", V(s, s, s), CFrame.new(p + V(0, s / 2, 0)) * CFrame.Angles(0, math.rad(i * 17), 0), MapKit.Shade(C.Wood, 0.1), M.WoodPlanks)
	end
	B:Solid("Cylinder", "Barrel", V(3, 2.3, 2.3), CFrame.new(20, 1.5, 91) * UPRIGHT, C.Wood, M.Wood)
	B:Signpost("DockSign", V(-6.5, 0, 64), {
		{ Key = "maps.grotto.sign.falls", Yaw = 90 },
		{ Key = "maps.grotto.sign.garden", Yaw = 155 },
		{ Key = "maps.grotto.sign.dock", Yaw = 0 },
	}, { Color = C.Wood, Height = 6.6 })
	B:Group(nil)
	return lights
end

local function buildIsle(B: Builder)
	B:Group("Isle")
	-- a mossy standing stone with the plaque (the cavern "remembers every word")
	local base = onGround(-12, -4)
	local stone = B:Solid("Block", "StandingStone", V(3.4, 6, 1.6), CFrame.new(base + V(0, 3, 0)) * CFrame.Angles(0, math.rad(35), math.rad(3)), C.RockLight, M.Slate)
	local plaque = B:Deco("Block", "Plaque", V(2.6, 1.6, 0.12), stone.CFrame * CFrame.new(0, 0.6, -0.86), rgb(150, 190, 200), M.Metal)
	B:Text(plaque, Enum.NormalId.Front, { Key = "maps.grotto.plaque", Color = rgb(20, 40, 52), Font = "Merriweather", Pixels = 60 })
	B:Deco("Ellipsoid", "StoneMoss", V(3.6, 0.8, 1.9), stone.CFrame * CFrame.new(0, 3, 0), C.Moss, M.Grass)
	-- small rocks to break up the island floor
	for _, p in { onGround(13, 13), onGround(-5, 18), onGround(15, -7) } do
		B:Rock("IsleRock", p, B.Rng:Number(2.2, 3.4), { Chunks = 1, Color = C.RockLight, Material = M.Slate })
	end
	B:Group(nil)
end

-- Soft bioluminescent lichen on the island floors (dim Neon smears, kept off SAVE rings and walkways).
local LICHEN = {
	V(-80, 0, -20),
	V(-70, 0, 20),
	V(-46, 0, -32),
	V(-84, 0, 26),
	V(-40, 0, 14),
	V(48, 0, -8),
	V(82, 0, 10),
	V(70, 0, -38),
	V(56, 0, 34),
	V(84, 0, -18),
	V(-10, 0, -4),
	V(12, 0, 16),
	V(-36, 0, 86),
	V(36, 0, 88),
	V(-18, 0, -70),
	V(18, 0, -72),
}

local function buildLichen(B: Builder)
	B:Group("Lichen")
	local rng = B.Rng
	for _, p in LICHEN do
		local g = V(p.X, groundY(p), p.Z)
		for k = 1, 3 do
			local x, z = rng:InCircle(3.5)
			local size = rng:Number(2.5, 5)
			B:Deco("Ellipsoid", "Lichen", V(size, 0.08, size * rng:Number(0.5, 0.9)), CFrame.new(g + V(x, 0.03 + k * 0.004, z)) * CFrame.Angles(0, rng:Number(0, 6.28), 0), MapKit.Shade(rgb(24, 96, 92), rng:Number(-0.1, 0.1)), M.Neon, {
				Transparency = 0.45,
				Shadow = false,
			})
		end
	end
	B:Group(nil)
end

local function buildLedge(B: Builder): number
	B:Group("Ledge")
	local lights = 0
	for _, sx in { -1, 1 } do
		lights += lantern(B, "LedgeLantern", V(sx * 24, L.LedgeTop, -72), false)
	end
	-- the monster's perch: two broken pillars and a fallen slab framing the falls
	for _, sx in { -1, 1 } do
		local p = V(sx * 14, L.LedgeTop, -76)
		B:Solid("Cylinder", "Pillar", V(9 + sx, 2.4, 2.4), CFrame.new(p + V(0, (9 + sx) / 2, 0)) * UPRIGHT, C.RockLight, M.Slate)
		B:Deco("Cylinder", "PillarCap", V(0.8, 3.2, 3.2), CFrame.new(p + V(0, 9 + sx + 0.3, 0)) * UPRIGHT, C.Rock, M.Slate)
		B:Crystal("LedgeCrystal", p + V(sx * 3, 0, 2), 4, { Color = C.Cyan, Count = 3, Light = false })
	end
	B:Solid("Block", "FallenSlab", V(9, 1.6, 3.4), CFrame.new(-6, L.LedgeTop + 0.6, -64) * CFrame.Angles(0, math.rad(28), math.rad(8)), C.RockLight, M.Slate)
	B:Group(nil)
	return lights
end

local function buildBoundary(B: Builder)
	local t = 2
	for k = 0, 7 do
		local a = math.rad(k * 45)
		local dir = V(math.sin(a), 0, -math.cos(a))
		local center = dir * (L.Bound + t / 2) + V(0, -10, 0)
		local side = 2 * L.Bound * math.tan(math.rad(22.5)) + 6
		B:Boundary("Boundary" .. k, MapKit.Facing(center, V(0, -10, 0)), side, 90, t)
	end
end

function WaterfallGrotto.Build(seed: number?, opts: { [string]: any }?): MapInfo
	local o = opts or {}
	local cutaway = o.Cutaway == true
	local B = MapKit.new("WaterfallGrotto", { Seed = seed or 1 })
	buildLake(B)
	buildIslands(B)
	local lights = 0
	lights += buildWalkways(B)
	lights += buildFalls(B)
	lights += buildFlora(B)
	lights += buildCave(B, cutaway)
	lights += buildLanding(B)
	buildIsle(B)
	lights += buildLedge(B)
	buildLichen(B)
	buildBoundary(B)

	-- objectives: the Echo Isle (centre), the Echo Garden (west), the Crystal Grove (east)
	local saves = {
		B:SavePoint(1, onGround(2, 4), { Inner = rgb(24, 52, 70), InnerMaterial = M.Slate, StarColor = rgb(255, 236, 140) }),
		B:SavePoint(2, onGround(-64, 12), { Inner = rgb(22, 60, 58), InnerMaterial = M.Slate }),
		B:SavePoint(3, onGround(64, -22), { Inner = rgb(24, 46, 70), InnerMaterial = M.Slate }),
	}
	local humanSpawns: { CFrame } = {}
	local i = 0
	for _, z in { 78, 86 } do
		for _, x in { -30, -20, -10, 10, 20, 30 } do
			i += 1
			table.insert(humanSpawns, B:SpawnPoint("Human", i, MapKit.Facing(V(x, 0, z), V(x * 0.3, 0, 0))))
		end
	end
	local monsterSpawn = B:SpawnPoint("Monster", 1, MapKit.Facing(L.MonsterSpawn, V(0, L.LedgeTop, 0)))
	local center = V(0, 0, 0)
	B:Marker("Center", CFrame.new(center + V(0, 0.5, 0)))
	B:KillFloor(L.KillY, 500)
	local _ = lights
	B:Finish(WaterfallGrotto.Id)

	return {
		Id = WaterfallGrotto.Id,
		Model = B.Model,
		HumanSpawns = humanSpawns,
		MonsterSpawn = monsterSpawn,
		SavePoints = saves,
		Center = center,
		Radius = L.Radius,
		KillY = L.KillY,
		IntroPath = {
			MapKit.LookAt(V(0, 40, 104), V(0, 12, -60)),
			MapKit.LookAt(V(-78, 22, 44), V(-50, 4, -12)),
			MapKit.LookAt(V(-26, 10, 24), V(6, 6, -6)),
			MapKit.LookAt(V(74, 14, 34), V(56, 6, -18)),
			MapKit.LookAt(V(12, 12, -30), V(0, 10, -86)),
		},
		Preset = WaterfallGrotto.Preset,
		FinalPreset = WaterfallGrotto.FinalPreset,
		Music = WaterfallGrotto.Music,
	}
end

return WaterfallGrotto
