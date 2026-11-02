--!strict
-- Maps/SnowdinCrossroads: a sleepy snow town crossroads at night (preset SnowNight). [Lune-safe]
-- Two packed-snow roads cross at a round town square whose giant decorated pine is the arena's pivot.
-- North: the sentry post by the road out of town (monster spawn). East: Main Street between the shop
-- and the inn, closed by a cottage (SAVE 2). North-west: the bakery and its fenced garden (SAVE 3).
-- South-west: a frozen pond (SAVE 1, open ice). South: a frozen creek crossed by an arched wooden
-- bridge, then the travellers' camp inside the town gate (human spawns). A ring of snowy pines (and far
-- blue mountains) closes the horizon. Warm windows, lamps and the campfire against the cold moonlight
-- (moon from the south-east). Playable area: an octagon 196 studs across (invisible walls).
-- Built around the origin (ground top y = 0, the creek bed sinks to y = -3); MapService offsets it.
--
-- API (Types.MapDef): SnowdinCrossroads.Id/Name/Desc/Preset/FinalPreset/Music
--   SnowdinCrossroads.Build(seed?, opts?) -> MapInfo   opts = { NoBackdrop: boolean? } (skip the forest
--   ring + mountains outside the walls: faster overview renders)
-- Layout constants: SnowdinCrossroads.Layout (tests read them).

local Types = require(script.Parent.Parent.Types)
local MapKit = require(script.Parent.MapKit)
local MapStrings = require(script.Parent.Parent.Strings.Maps2)

type MapInfo = Types.MapInfo
type Builder = MapKit.Builder

local SnowdinCrossroads = {}

SnowdinCrossroads.Id = "SnowdinCrossroads"
SnowdinCrossroads.Name = MapStrings["maps.crossroads.name"]
SnowdinCrossroads.Desc = MapStrings["maps.crossroads.desc"]
SnowdinCrossroads.Preset = "SnowNight"
SnowdinCrossroads.FinalPreset = "SnowNightFinal"
SnowdinCrossroads.Music = "Map_SnowdinCrossroads"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local V = Vector3.new
local M = Enum.Material
local UP = Vector3.new(0, 1, 0)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinder X axis -> world Y

-- Layout (studs; north = -Z) -------------------------------------------------------------------------------
local L = {
	Bound = 98, -- inradius of the playable octagon (invisible walls)
	Radius = 104, -- Collapse start radius
	KillY = -40,
	PlazaR = 23,
	RoadW = 10,
	-- frozen creek: a straight channel from (X0, Z0) to (X1, Z1); bed at BedY, banks BankW wide
	CreekX0 = -150,
	CreekZ0 = 57,
	CreekX1 = 150,
	CreekZ1 = 67,
	CreekBedY = -3,
	CreekBedW = 8,
	CreekBankW = 5,
	BridgeZ0 = 45,
	BridgeZ1 = 79,
	Pond = V(-56, 0, 26),
	PondR = 18,
	IceTop = 0.12,
	Sentry = V(18, 0, -72),
	MonsterSpawn = V(0, 0, -86),
	Camp = V(0, 0, 88),
	GateZ = 95,
	Knoll = V(-22, 0, -80),
}
SnowdinCrossroads.Layout = L

local C = {
	Snow = rgb(232, 238, 250),
	SnowShade = rgb(208, 220, 240),
	Path = rgb(186, 196, 218),
	Stone = rgb(124, 128, 146),
	StoneDark = rgb(88, 92, 108),
	Ice = rgb(146, 202, 236),
	IceDeep = rgb(92, 150, 196),
	IceMark = rgb(214, 238, 255),
	Water = rgb(20, 44, 64),
	Wood = rgb(126, 88, 60),
	WoodDark = rgb(82, 58, 42),
	WoodLight = rgb(176, 134, 92),
	Pine = rgb(30, 66, 58),
	PineFar = rgb(26, 50, 56),
	Warm = rgb(255, 186, 100),
	WarmLight = rgb(255, 170, 90),
	Cold = rgb(150, 196, 255),
	Red = rgb(186, 46, 52),
	Gold = rgb(240, 192, 84),
	Iron = rgb(38, 36, 42),
	Coal = rgb(28, 28, 34),
	Carrot = rgb(240, 122, 40),
	Canvas = rgb(198, 172, 128),
	Mountain = rgb(56, 68, 100),
}

local DIAG = L.Bound * math.sqrt(2) -- |x| + |z| limit of the octagon's diagonal walls

local function inside(x: number, z: number, margin: number): boolean
	return math.abs(x) <= L.Bound - margin and math.abs(z) <= L.Bound - margin and math.abs(x) + math.abs(z) <= DIAG - margin * 1.4142
end

local function creekZ(x: number): number
	return L.CreekZ0 + (x - L.CreekX0) * (L.CreekZ1 - L.CreekZ0) / (L.CreekX1 - L.CreekX0)
end

-- Frame along the creek: local X = downstream (east), local Z = south bank side, origin on the centre line.
local function creekFrame(): CFrame
	local a = V(L.CreekX0, 0, L.CreekZ0)
	local b = V(L.CreekX1, 0, L.CreekZ1)
	local d = (b - a).Unit
	return CFrame.fromMatrix((a + b) / 2, d, UP, d:Cross(UP))
end

-- Ground, roads, creek -------------------------------------------------------------------------------------

local function buildGround(B: Builder)
	B:Group("Ground")
	local cf = creekFrame()
	local half = L.CreekBedW / 2 + L.CreekBankW
	local depth = -L.CreekBedY
	local len = 460
	B:Solid("Block", "LandNorth", V(len, 8, 280), cf * CFrame.new(0, -4, -(half + 140)), C.Snow, M.Snow)
	B:Solid("Block", "LandSouth", V(len, 8, 150), cf * CFrame.new(0, -4, half + 75), C.Snow, M.Snow)
	B:Solid("Block", "CreekBed", V(len, 6, half * 2), cf * CFrame.new(0, L.CreekBedY - 3, 0), C.IceDeep, M.Ice)
	-- banks: wedges rising from the bed to the land (WedgePart: tall side at local +Z)
	local bankZ = L.CreekBedW / 2 + L.CreekBankW / 2
	B:Solid("Wedge", "BankNorth", V(len, depth, L.CreekBankW), cf * CFrame.new(0, -depth / 2, -bankZ) * CFrame.Angles(0, math.pi, 0), C.Snow, M.Snow)
	B:Solid("Wedge", "BankSouth", V(len, depth, L.CreekBankW), cf * CFrame.new(0, -depth / 2, bankZ), C.Snow, M.Snow)

	-- packed-snow roads (thin decals) and the round town square
	local function road(name: string, a: Vector3, b: Vector3)
		B:Beam("Decor", name, a + V(0, 0.025, 0), b + V(0, 0.025, 0), L.RoadW, 0.05, C.Path, M.Snow, { Shadow = false })
	end
	road("RoadNorth", V(0, 0, -L.PlazaR + 1), V(0, 0, -190))
	road("RoadWest", V(-L.PlazaR + 1, 0, 0), V(-190, 0, 0))
	road("RoadEast", V(L.PlazaR - 1, 0, 0), V(78, 0, 0))
	road("RoadSouth", V(0, 0, L.PlazaR - 1), V(0, 0, L.BridgeZ0 + 1))
	road("RoadCamp", V(0, 0, L.BridgeZ1 - 1), V(0, 0, 190))
	B:Disc("Decor", "CampClearing", L.Camp + V(0, 0.03, 0), 22, 0.06, C.Path, M.Snow, { Shadow = false })
	B:Disc("Decor", "Plaza", V(0, 0.035, 0), L.PlazaR * 2, 0.07, C.Path, M.Snow, { Shadow = false })
	B:Ring("Decor", "PlazaRim", V(0, 0.07, 0), L.PlazaR - 0.6, 1.8, 0.1, 24, C.Stone, M.Cobblestone, { Shadow = false })
	B:Ring("Decor", "PlazaInlay", V(0, 0.08, 0), 11.5, 0.7, 0.1, 16, C.Stone, M.Cobblestone, { Shadow = false })

	-- low snowbanks along the roads (decor drifts), skipping SAVE spots and junctions
	local rng = B.Rng
	local function bankRow(from: Vector3, to: Vector3, side: Vector3, step: number)
		local delta = to - from
		local n = math.floor(delta.Magnitude / step)
		for i = 0, n do
			local p = from + delta * (i / math.max(1, n)) + side * (L.RoadW / 2 + 1.2 + rng:Number(0, 1.2))
			if inside(p.X, p.Z, 2) and (p - V(66, 0, 0)).Magnitude > 10 then
				B:Mound("RoadDrift", p, rng:Number(1.1, 1.8), rng:Number(0.3, 0.55), {
					Collide = false,
					Color = C.SnowShade,
					Stretch = rng:Number(1.8, 2.8),
					Yaw = math.deg(math.atan2(-delta.Z, delta.X)) + rng:Number(-8, 8),
				})
			end
		end
	end
	for _, s in { -1, 1 } do
		bankRow(V(-30, 0, 0), V(-96, 0, 0), V(0, 0, s), 11)
		bankRow(V(30, 0, 0), V(52, 0, 0), V(0, 0, s), 11)
		bankRow(V(0, 0, -30), V(0, 0, -66), V(s, 0, 0), 12)
	end
	B:Group(nil)
end

local function buildCreek(B: Builder)
	B:Group("Creek")
	local cf = creekFrame()
	local rng = B.Rng
	local yawDeg = math.deg(math.atan2(-(L.CreekZ1 - L.CreekZ0), L.CreekX1 - L.CreekX0))
	-- dark open-water leads in the ice + pale cracked floes
	for _, x in { -86, -52, -24, 22, 50, 84 } do
		local z = creekZ(x) + rng:Number(-1.2, 1.2)
		local len = rng:Number(9, 16)
		B:Deco("Ellipsoid", "Lead", V(len, 0.08, rng:Number(2.2, 3.4)), CFrame.new(x, L.CreekBedY + 0.03, z) * CFrame.Angles(0, math.rad(yawDeg + rng:Number(-6, 6)), 0), C.Water, M.SmoothPlastic, {
			Reflectance = 0.25,
			Shadow = false,
		})
		B:Deco("Ellipsoid", "Floe", V(rng:Number(2, 3.5), 0.12, rng:Number(1.4, 2.2)), CFrame.new(x + len * 0.5 + 1.5, L.CreekBedY + 0.05, z + rng:Number(-1.5, 1.5)) * CFrame.Angles(0, math.rad(rng:Number(0, 180)), 0), C.IceMark, M.Ice, {
			Shadow = false,
		})
	end
	-- snowy stones along both banks
	for i, x in { -70, -36, 30, 64, 92 } do
		local side = if i % 2 == 0 then -1 else 1
		local p = (cf * CFrame.new(x - cf.Position.X, 0, side * (L.CreekBedW / 2 + 1.2))).Position
		B:Rock("BankStone", V(p.X, L.CreekBedY + 0.6, p.Z), rng:Number(1.6, 2.6), { Collide = false, Snow = true, Color = C.StoneDark })
	end
	B:Group(nil)
end

local function buildBridge(B: Builder): number
	B:Group("Bridge")
	local a = V(0, 0.25, L.BridgeZ0)
	local b = V(0, 0.25, L.BridgeZ1)
	B:Bridge("Bridge", a, b, 9, { Arch = 3.6, Snow = true, Color = C.Wood })
	-- stone abutments where the deck meets the banks
	for _, z in { L.BridgeZ0 + 1.5, L.BridgeZ1 - 1.5 } do
		B:Deco("Block", "Abutment", V(11, 1.4, 3), CFrame.new(0, -0.5, z), C.Stone, M.Cobblestone)
	end
	local lights = 0
	for _, z in { L.BridgeZ0 - 0.5, L.BridgeZ1 + 0.5 } do
		for _, x in { -6.2, 6.2 } do
			if B:Lamp("BridgeLamp", V(x, 0, z), { Style = "Post", Height = 7.5, Metal = C.Iron, Glow = C.Warm, LightColor = C.WarmLight, Brightness = 1.8, Range = 18 }) then
				lights += 1
			end
		end
	end
	B:Group(nil)
	return lights
end

-- Props ----------------------------------------------------------------------------------------------------

local function bench(B: Builder, name: string, cf: CFrame)
	-- cf = ground centre, LookVector = the way a sitter faces
	B:Solid("Block", name .. "_Seat", V(5, 0.35, 1.5), cf * CFrame.new(0, 1.45, 0), C.WoodLight, M.WoodPlanks)
	B:Deco("Block", name .. "_Back", V(5, 1.3, 0.3), cf * CFrame.new(0, 2.45, 0.8) * CFrame.Angles(math.rad(12), 0, 0), C.WoodLight, M.WoodPlanks)
	for _, sx in { -2.1, 2.1 } do
		B:Deco("Block", name .. "_Frame", V(0.3, 1.3, 1.4), cf * CFrame.new(sx, 0.65, 0), C.Iron, M.Metal)
	end
	B:Deco("Block", name .. "_Snow", V(4.6, 0.16, 1.1), cf * CFrame.new(0, 1.7, 0.1), C.Snow, M.Snow, { Shadow = false })
end

local function snowman(B: Builder, name: string, base: Vector3, facing: Vector3, scale: number)
	local f = MapKit.Facing(base, base + facing)
	local s = scale
	B:Solid("Ball", name .. "_Base", V(3.4, 3.4, 3.4) * s, f * CFrame.new(0, 1.5 * s, 0), C.Snow, M.Snow)
	B:Solid("Ball", name .. "_Body", V(2.6, 2.6, 2.6) * s, f * CFrame.new(0, 3.6 * s, 0), C.Snow, M.Snow)
	B:Deco("Ball", name .. "_Head", V(1.9, 1.9, 1.9) * s, f * CFrame.new(0, 5.25 * s, 0), C.Snow, M.Snow)
	for _, sx in { -1, 1 } do
		B:Deco("Ball", name .. "_Eye", V(0.26, 0.26, 0.26) * s, f * CFrame.new(sx * 0.35 * s, 5.45 * s, -0.82 * s), C.Coal, M.SmoothPlastic, { Shadow = false })
		local shoulder = (f * CFrame.new(sx * 1.1 * s, 4.0 * s, 0)).Position
		local hand = (f * CFrame.new(sx * 2.6 * s, 5.0 * s, 0.2 * s)).Position
		B:Rod("Decor", name .. "_Arm", shoulder, hand, 0.16 * s, C.WoodDark, M.Wood, { Shadow = false })
	end
	for k = 0, 2 do
		B:Deco("Ball", name .. "_Button", V(0.24, 0.24, 0.24) * s, f * CFrame.new(0, (3.1 + k * 0.45) * s, -1.22 * s), C.Coal, M.SmoothPlastic, { Shadow = false })
	end
	local nose = (f * CFrame.new(0, 5.2 * s, -0.9 * s)).Position
	B:Rod("Decor", name .. "_Nose", nose, nose + f.LookVector * (0.9 * s), 0.22 * s, C.Carrot, M.SmoothPlastic, { Shadow = false })
	B:Deco("Cylinder", name .. "_Scarf", V(0.45, 2.3, 2.3) * s, f * CFrame.new(0, 4.6 * s, 0) * UPRIGHT, C.Red, M.Fabric, { Shadow = false })
	B:Deco("Block", name .. "_ScarfTail", V(0.5, 1.3, 0.16) * s, f * CFrame.new(0.55 * s, 4.0 * s, -1.0 * s) * CFrame.Angles(0, 0, math.rad(10)), C.Red, M.Fabric, { Shadow = false })
	B:Deco("Cylinder", name .. "_HatBrim", V(0.16, 1.9, 1.9) * s, f * CFrame.new(0, 6.0 * s, 0) * UPRIGHT, C.Coal, M.Fabric, { Shadow = false })
	B:Deco("Cylinder", name .. "_Hat", V(1.1, 1.25, 1.25) * s, f * CFrame.new(0, 6.6 * s, 0) * UPRIGHT, C.Coal, M.Fabric, { Shadow = false })
end

local function crate(B: Builder, name: string, cf: CFrame, size: number)
	B:Solid("Block", name, V(size, size, size), cf * CFrame.new(0, size / 2, 0), C.WoodLight, M.WoodPlanks)
	for _, face in { -1, 1 } do
		B:Deco("Block", name .. "_Brace", V(size * 1.3, 0.3, 0.12), cf * CFrame.new(0, size / 2, face * (size / 2 + 0.05)) * CFrame.Angles(0, 0, math.rad(45)), C.WoodDark, M.Wood, { Shadow = false })
	end
	B:Deco("Block", name .. "_Snow", V(size * 0.92, 0.25, size * 0.92), cf * CFrame.new(0, size + 0.1, 0), C.Snow, M.Snow, { Shadow = false })
end

local function barrel(B: Builder, name: string, base: Vector3)
	B:Solid("Cylinder", name, V(3, 2.3, 2.3), CFrame.new(base + V(0, 1.5, 0)) * UPRIGHT, C.Wood, M.Wood)
	for _, y in { 0.6, 2.4 } do
		B:Disc("Decor", name .. "_Hoop", base + V(0, y, 0), 2.4, 0.2, C.Iron, M.Metal, { Shadow = false })
	end
	B:Disc("Decor", name .. "_Snow", base + V(0, 3.05, 0), 2.1, 0.2, C.Snow, M.Snow, { Shadow = false })
end

local function logPile(B: Builder, name: string, cf: CFrame, length: number)
	-- cf = ground centre, local X = log direction; one invisible collider + stacked decor logs
	B:Solid("Block", name .. "_Hitbox", V(length, 2.6, 3.6), cf * CFrame.new(0, 1.3, 0), C.Wood, M.Wood, { Transparency = 1, Shadow = false })
	local rows = { { -1.25, 0.6 }, { 0, 0.6 }, { 1.25, 0.6 }, { -0.62, 1.65 }, { 0.62, 1.65 }, { 0, 2.6 } }
	for i, r in rows do
		B:Deco("Cylinder", name .. "_Log", V(length + (i % 2) * 0.4, 1.2, 1.2), cf * CFrame.new(0, r[2], r[1]), MapKit.Shade(C.Wood, (i % 3) * 0.05 - 0.05), M.Wood)
	end
	B:Deco("Block", name .. "_Snow", V(length - 0.4, 0.3, 1.4), cf * CFrame.new(0, 3.25, 0), C.Snow, M.Snow, { Shadow = false })
end

local function tent(B: Builder, name: string, cf: CFrame)
	-- A-frame tent: ridge along local Z, entrance at local -Z (cf.LookVector)
	local w, h, d = 7, 5, 8
	for _, side in { -1, 1 } do
		-- WedgePart tall side = local +Z; turn it so the tall side meets the ridge in the middle
		B:Solid("Wedge", name .. "_Canvas", V(d, h, w / 2), cf * CFrame.new(side * w / 4, h / 2, 0) * CFrame.Angles(0, side * -math.pi / 2, 0), C.Canvas, M.Fabric)
	end
	B:Rod("Decor", name .. "_Ridge", (cf * CFrame.new(0, h + 0.1, -d / 2 - 0.4)).Position, (cf * CFrame.new(0, h + 0.1, d / 2 + 0.4)).Position, 0.3, C.WoodDark, M.Wood)
	local fl = cf * CFrame.new(0, 0, -d / 2 - 0.05)
	B:Triangle("Decor", name .. "_Door", fl * Vector3.new(-1.4, 0.05, 0), fl * Vector3.new(1.4, 0.05, 0), fl * Vector3.new(0, 3.2, 0), 0.1, C.WoodDark, M.Fabric, { Shadow = false })
	B:Deco("Block", name .. "_Snow", V(1.4, 0.35, d + 0.2), cf * CFrame.new(0, h - 0.05, 0), C.Snow, M.Snow, { Shadow = false })
end

local function snowFort(B: Builder, name: string, cf: CFrame)
	-- low curved wall of snow bricks (cover), a pyramid of snowballs behind it, a little flag
	local rng = B.Rng
	for i = -2, 2 do
		local a = math.rad(i * 18)
		local p = cf * CFrame.new(math.sin(a) * 7, 1.5, -math.cos(a) * 7 + 7)
		B:Solid("Block", name .. "_Wall", V(4.6, 3, 1.8), p * CFrame.Angles(0, -a, 0), MapKit.Shade(C.Snow, rng:Number(-0.04, 0.02)), M.Snow)
		B:Deco("Ellipsoid", name .. "_Cap", V(4.8, 0.7, 2.1), p * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, -a, 0), C.Snow, M.Snow, { Shadow = false })
	end
	for k, off in { V(-1, 0.6, 2.4), V(0.2, 0.6, 2.6), V(-0.4, 1.5, 2.5) } do
		B:Deco("Ball", name .. "_Ball" .. k, V(1.2, 1.2, 1.2), cf * CFrame.new(off), C.Snow, M.Snow, { Shadow = false })
	end
	local pole = cf * CFrame.new(3.5, 0, 0.6)
	B:Rod("Decor", name .. "_Pole", pole.Position, (pole * CFrame.new(0, 6, 0)).Position, 0.16, C.WoodDark, M.Wood, { Shadow = false })
	B:Deco("Block", name .. "_Flag", V(1.8, 1.1, 0.06), pole * CFrame.new(0.95, 5.3, 0), C.Red, M.Fabric, { Shadow = false })
end

local function bush(B: Builder, name: string, base: Vector3, size: number)
	local rng = B.Rng
	B:Deco("Ellipsoid", name, V(size * 1.3, size * 0.9, size), CFrame.new(base + V(0, size * 0.3, 0)) * CFrame.Angles(0, math.rad(rng:Number(0, 180)), 0), MapKit.Shade(C.Pine, 0.1), M.Grass)
	B:Deco("Ellipsoid", name .. "_Snow", V(size * 1.15, size * 0.5, size * 0.85), CFrame.new(base + V(0, size * 0.62, 0)) * CFrame.Angles(0, math.rad(rng:Number(0, 180)), 0), C.Snow, M.Snow, { Shadow = false })
end

-- Sagging string of coloured bulbs between two anchor points (a festive garland).
local function garland(B: Builder, name: string, a: Vector3, b: Vector3, sag: number, bulbs: number)
	local colors = { rgb(255, 80, 80), C.Gold, rgb(90, 200, 255), rgb(120, 230, 140) }
	local last = a
	for i = 1, bulbs + 1 do
		local t = i / (bulbs + 1)
		local p = a:Lerp(b, t) - V(0, sag * 4 * t * (1 - t), 0)
		B:Rod("Decor", name .. "_Wire", last, p, 0.08, C.Iron, M.SmoothPlastic, { Shadow = false })
		if i <= bulbs then
			B:Deco("Ball", name .. "_Bulb", V(0.5, 0.5, 0.5), CFrame.new(p - V(0, 0.3, 0)), colors[i % #colors + 1], M.Neon, { Shadow = false })
		end
		last = p
	end
end

local function postLamp(B: Builder, name: string, base: Vector3, shadows: boolean?): number
	local light = B:Lamp(name, base, {
		Style = "Post",
		Height = 10,
		Metal = C.Iron,
		Glow = C.Warm,
		LightColor = C.WarmLight,
		Brightness = 2,
		Range = 22,
		Shadows = shadows == true,
	})
	B:Deco("Ellipsoid", name .. "_SnowCap", V(1.1, 0.35, 1.1), CFrame.new(base + V(0, 10.85, 0)), C.Snow, M.Snow, { Shadow = false })
	return if light then 1 else 0
end

-- Town square: the great decorated pine ------------------------------------------------------------------

local function buildPlaza(B: Builder): number
	B:Group("Plaza")
	local rng = B.Rng
	local lights = 0
	-- raised stone planter (collidable, jumpable) filled with snow
	local planterTop = 1.6
	B:Ring("Geometry", "Planter", V(0, planterTop / 2, 0), 5.6, 1.2, planterTop, 16, C.Stone, M.Cobblestone)
	B:Disc("Geometry", "PlanterSnow", V(0, planterTop - 0.2, 0), 10.4, 0.4, C.Snow, M.Snow)
	B:Ring("Decor", "PlanterCap", V(0, planterTop + 0.08, 0), 5.6, 1.5, 0.16, 16, C.SnowShade, M.Snow, { Shadow = false })

	-- the tree (same tier maths as MapKit Pine, so the ornaments sit on its tiers)
	local base = V(0, planterTop - 0.05, 0)
	local height, tiers, widthF = 32, 4, 0.32
	B:Pine("GreatPine", base, height, { Tiers = tiers, Sides = 8, Width = widthF, Leaf = rgb(28, 74, 60) })
	local trunkH = height * 0.22
	local tierH = (height - trunkH) / (tiers * 0.72 + 0.28)
	local tierList: { { number } } = {} -- {bottom y, height, radius}
	local y = trunkH
	for t = 1, tiers do
		local k = (t - 1) / math.max(1, tiers - 1)
		local h = tierH * (1.0 - 0.08 * k)
		table.insert(tierList, { y, h, height * widthF * (1 - 0.48 * k) })
		y += h * 0.72
	end
	local function surfaceR(yy: number): number
		local best = 0
		for _, tier in tierList do
			local f = (yy - tier[1]) / tier[2]
			if f >= 0 and f <= 1 then
				best = math.max(best, tier[3] * (1 - f))
			end
		end
		return best * 0.924 -- 8-sided crown: mid-edge inset
	end
	y = trunkH
	local palette = { rgb(255, 72, 72), C.Gold, rgb(90, 200, 255), rgb(255, 120, 200) }
	local ornament = 0
	for t = 1, tiers do
		local h = tierList[t][2]
		local count = 7 - t
		for i = 1, count do
			ornament += 1
			local f = rng:Number(0.1, 0.32)
			local a = (i / count) * 2 * math.pi + t * 0.7 + rng:Number(-0.2, 0.2)
			local r = surfaceR(y + f * h) + 0.35
			local p = base + V(math.cos(a) * r, y + f * h, math.sin(a) * r)
			B:Deco("Ball", "Ornament", V(0.95, 0.95, 0.95), CFrame.new(p), palette[ornament % #palette + 1], M.Neon, { Shadow = false })
		end
		y += h * 0.72
	end
	-- garland of warm bulbs spiralling down the crown
	local top = trunkH + (height - trunkH) * 0.9
	local bulbs = 34
	for i = 0, bulbs - 1 do
		local f = i / bulbs
		local yy = top - f * (height - trunkH) * 0.86
		local r = surfaceR(yy) + 0.3
		local a = f * math.pi * 2 * 3.2
		B:Deco("Ball", "Bulb", V(0.42, 0.42, 0.42), CFrame.new(base + V(math.cos(a) * r, yy, math.sin(a) * r)), rgb(255, 226, 160), M.Neon, { Shadow = false })
	end
	-- crossed gold stars on the top
	local starAt = base + V(0, height + 1.4, 0)
	for _, yaw in { 0, 90 } do
		B:Star("Decor", "TopStar", CFrame.new(starAt) * CFrame.Angles(0, math.rad(yaw), 0), 2.2, 0.95, 0, C.Gold, M.Neon, { Shadow = false })
	end
	B:Light("Point", starAt, { Name = "StarLight", Brightness = 1.6, Range = 18, Color = rgb(255, 214, 130) })
	B:Light("Point", base + V(0, 9, 0), { Name = "TreeLight", Brightness = 1.8, Range = 30, Color = rgb(255, 190, 120), Shadows = true })
	lights += 2
	-- gifts at the foot of the tree (on the planter)
	local giftColors = { { C.Red, C.Gold }, { rgb(60, 110, 200), rgb(236, 240, 255) }, { rgb(70, 150, 100), C.Red }, { C.Gold, rgb(150, 40, 60) } }
	for i, gc in giftColors do
		local a = math.rad(i * 90 + 25)
		local s = 1.4 + (i % 2) * 0.5
		local cf = CFrame.new(math.cos(a) * 3.4, planterTop, math.sin(a) * 3.4) * CFrame.Angles(0, a, 0)
		B:Deco("Block", "Gift", V(s, s, s), cf * CFrame.new(0, s / 2, 0), gc[1], M.SmoothPlastic)
		B:Deco("Block", "GiftRibbon", V(s + 0.04, s + 0.04, 0.3), cf * CFrame.new(0, s / 2, 0), gc[2], M.Fabric, { Shadow = false })
		B:Deco("Block", "GiftRibbon", V(0.3, s + 0.04, s + 0.04), cf * CFrame.new(0, s / 2, 0), gc[2], M.Fabric, { Shadow = false })
		B:Deco("Ball", "GiftBow", V(0.5, 0.5, 0.5), cf * CFrame.new(0, s + 0.15, 0), gc[2], M.Fabric, { Shadow = false })
	end

	-- lamps on the diagonals, benches facing the tree, a snowman and the notice board
	for i, a in { 45, 135, 225, 315 } do
		local r = math.rad(a)
		lights += postLamp(B, "PlazaLamp", V(math.sin(r) * 19.5, 0, -math.cos(r) * 19.5), i == 2 or i == 4)
	end
	for _, a in { 24, 114, 204, 294 } do
		local r = math.rad(a)
		local p = V(math.sin(r) * 16.5, 0, -math.cos(r) * 16.5)
		bench(B, "Bench", MapKit.Facing(p, V(0, 0, 0)))
	end
	snowman(B, "Snowman", V(-13, 0, -14), V(0.4, 0, 1), 1)
	local boardBase = V(15.5, 0, -15.5)
	local boardCF = MapKit.Facing(boardBase, V(0, 0, 0))
	for _, sx in { -2.2, 2.2 } do
		B:Solid("Block", "BoardPost", V(0.5, 6.4, 0.5), boardCF * CFrame.new(sx, 3.2, 0), C.WoodDark, M.Wood)
	end
	local board = B:Deco("Block", "NoticeBoard", V(4.6, 3.2, 0.3), boardCF * CFrame.new(0, 4.2, -0.05), C.WoodLight, M.WoodPlanks)
	B:Text(board, Enum.NormalId.Front, { Key = "maps.crossroads.board", Color = rgb(64, 38, 22), Font = "Merriweather", Pixels = 60, Align = Enum.TextXAlignment.Left })
	B:Deco("Block", "BoardRoof", V(5.6, 0.3, 1.4), boardCF * CFrame.new(0, 6.5, 0), C.WoodDark, M.WoodPlanks)
	B:Deco("Block", "BoardRoofSnow", V(5.4, 0.3, 1.3), boardCF * CFrame.new(0, 6.75, 0), C.Snow, M.Snow, { Shadow = false })
	B:Signpost("Signpost", V(8.6, 0, 26.5), {
		{ Key = "maps.snowdin.sign.sentry", Yaw = 90 },
		{ Key = "maps.snowdin.sign.pond", Yaw = 180 },
		{ Key = "maps.snowdin.sign.bridge", Yaw = -90 },
		{ Key = "maps.snowdin.sign.forest", Yaw = 0 },
	}, { Snow = true, Height = 7.6 })
	B:Group(nil)
	return lights
end

-- Houses -----------------------------------------------------------------------------------------------------

local function houseDrifts(B: Builder, name: string, cf: CFrame, w: number, d: number)
	local rng = B.Rng
	for _, spot in { { -w / 2 - 0.6, d * 0.25 }, { w / 2 + 0.6, -d * 0.2 }, { w * 0.3, d / 2 + 0.6 }, { -w * 0.25, d / 2 + 0.6 } } do
		local p = (cf * CFrame.new(spot[1], 0, spot[2])).Position
		local alongX = math.abs(spot[2]) > d / 2
		local yaw = math.deg(math.atan2(-cf.LookVector.X, -cf.LookVector.Z)) + (if alongX then 90 else 0)
		B:Mound(name .. "_Drift", p, rng:Number(2.4, 3.4), rng:Number(0.8, 1.3), { Collide = false, Stretch = rng:Number(1.8, 2.6), Yaw = yaw })
	end
end

-- Extra lit window (same look as MapKit House windows) on a wall plane; cf LookVector = outwards.
local function extraWindow(B: Builder, name: string, cf: CFrame, trim: Color3, shutter: Color3)
	local winW, winH = 3, 3.4
	B:Deco("Block", name .. "_WinFrame", V(winW + 0.8, winH + 0.8, 0.3), cf * CFrame.new(0, 0, -0.1), trim, M.Wood)
	B:Deco("Block", name .. "_WinGlow", V(winW, winH, 0.3), cf * CFrame.new(0, 0, -0.2), C.Warm, M.Neon, { Shadow = false })
	B:Deco("Block", name .. "_WinBarV", V(0.22, winH, 0.2), cf * CFrame.new(0, 0, -0.4), trim, M.Wood, { Shadow = false })
	B:Deco("Block", name .. "_WinBarH", V(winW, 0.22, 0.2), cf * CFrame.new(0, 0, -0.4), trim, M.Wood, { Shadow = false })
	B:Deco("Block", name .. "_WinSill", V(winW + 1.2, 0.3, 0.8), cf * CFrame.new(0, -winH / 2 - 0.45, -0.35), trim, M.Wood, { Shadow = false })
	B:Deco("Block", name .. "_SillSnow", V(winW + 1.1, 0.25, 0.75), cf * CFrame.new(0, -winH / 2 - 0.2, -0.35), C.Snow, M.Snow, { Shadow = false })
	for _, sx in { -1, 1 } do
		B:Deco("Block", name .. "_Shutter", V(winW * 0.48, winH + 0.4, 0.18), cf * CFrame.new(sx * (winW * 0.74 + 0.4), 0, -0.25), shutter, M.WoodPlanks, { Shadow = false })
	end
end

local function buildHouses(B: Builder): number
	B:Group("Houses")
	local lights = 0
	local function house(name: string, pos: Vector3, facing: Vector3, opts: { [string]: any })
		local cf = MapKit.Facing(pos, pos + facing)
		opts.Snow = true
		local hl = B:House(name, cf, opts)
		lights += #hl
		houseDrifts(B, name, cf, opts.Width or 18, opts.Depth or 14)
		return cf
	end
	-- Shop (north side of Main Street)
	local shop = house("Shop", V(44, 0, -30), V(0, 0, 1), {
		Width = 20,
		Depth = 14,
		WallColor = rgb(150, 104, 70),
		RoofColor = rgb(124, 52, 50),
		Sign = "maps.snowdin.shop",
	})
	-- Inn (south side, bigger, blue-grey planks)
	local inn = house("Inn", V(48, 0, 30), V(0, 0, -1), {
		Width = 26,
		Depth = 16,
		WallHeight = 13,
		RoofHeight = 7,
		WallColor = rgb(96, 116, 140),
		Trim = rgb(58, 50, 46),
		RoofColor = rgb(48, 60, 92),
		Shutter = rgb(130, 60, 56),
		Sign = "maps.snowdin.inn",
		FrontWindows = { -8.5, 8.5 },
		ChimneyX = -7,
	})
	-- Bakery (north-west, door facing the north road)
	local bakery = house("Bakery", V(-34, 0, -46), V(1, 0, 0), {
		Width = 20,
		Depth = 14,
		WallColor = rgb(204, 168, 120),
		Trim = rgb(110, 70, 46),
		RoofColor = rgb(150, 82, 44),
		Shutter = rgb(70, 110, 90),
		Sign = "maps.snowdin.bakery",
	})
	-- Cottage closing Main Street
	local cottage = house("Cottage", V(84, 0, 0), V(-1, 0, 0), {
		Width = 16,
		Depth = 12,
		WallHeight = 9,
		RoofHeight = 5.5,
		WallColor = rgb(118, 80, 56),
		RoofColor = rgb(56, 88, 70),
		Shutter = rgb(170, 120, 60),
		FrontWindows = { -4.6 },
		ChimneyX = 4,
	})
	local _ = cottage
	-- lit windows on the backs that face the camp / the monster's side
	local back = CFrame.Angles(0, math.pi, 0)
	for _, x in { -8.5, 8.5 } do
		extraWindow(B, "InnBack", inn * CFrame.new(x, 0.5 + 13 * 0.52, 8) * back, rgb(58, 50, 46), rgb(130, 60, 56))
	end
	extraWindow(B, "ShopBack", shop * CFrame.new(-5, 0.5 + 10 * 0.52, 7) * back, rgb(84, 58, 42), MapKit.Shade(rgb(124, 52, 50), 0.05))
	extraWindow(B, "BakeryBack", bakery * CFrame.new(4, 0.5 + 10 * 0.52, 7) * back, rgb(110, 70, 46), rgb(70, 110, 90))
	-- street dressing: crates/barrels by the shop, a log pile by the inn, benches by the cottage
	crate(B, "Crate", shop * CFrame.new(12.6, 0, -1) * CFrame.Angles(0, math.rad(12), 0), 3)
	crate(B, "Crate", shop * CFrame.new(13.1, 3, -1.2) * CFrame.Angles(0, math.rad(-20), 0), 2.2)
	barrel(B, "Barrel", (shop * CFrame.new(12.8, 0, 3.2)).Position)
	barrel(B, "Barrel", (shop * CFrame.new(-12.6, 0, -3)).Position)
	logPile(B, "InnLogs", inn * CFrame.new(16.4, 0, 2) * CFrame.Angles(0, math.rad(90), 0), 7)
	bench(B, "InnBench", inn * CFrame.new(-9, 0, -10.4))
	barrel(B, "Barrel", (bakery * CFrame.new(-12.5, 0, -2)).Position)
	crate(B, "Crate", bakery * CFrame.new(12.4, 0, 4) * CFrame.Angles(0, math.rad(8), 0), 2.6)
	-- festive garlands across Main Street, from the shop's eave to the inn's
	for _, x in { 39.5, 51.5 } do
		garland(B, "Garland", V(x, 10.2, -22.6), V(x - 1, 13.2, 21.6), 3.2, 12)
	end
	-- shop backyard fence + bushes
	B:Fence("ShopFence", { V(30, 0, -46), V(58, 0, -46), V(62, 0, -40) }, { Snow = true, Color = C.Wood })
	for _, p in { V(32, 0, -21), V(57, 0, -20.5), V(36, 0, 20), V(61, 0, 19.5), V(-26, 0, -34), V(-25.5, 0, -58) } do
		bush(B, "Bush", p, B.Rng:Number(2.2, 3))
	end
	B:Group(nil)
	return lights
end

-- Sentry post (north, next to the monster spawn) ------------------------------------------------------------

local function buildSentry(B: Builder): number
	B:Group("Sentry")
	local cf = MapKit.Facing(L.Sentry, L.Sentry + V(0, 0, 1)) -- the counter faces south (the town)
	B:Solid("Block", "Deck", V(11, 0.6, 8), cf * CFrame.new(0, 0.3, 0), C.WoodDark, M.WoodPlanks)
	B:Solid("Block", "Counter", V(9.4, 3.2, 1.4), cf * CFrame.new(0, 2.2, -2.7), C.Wood, M.WoodPlanks)
	B:Deco("Block", "CounterTop", V(10.2, 0.3, 2.1), cf * CFrame.new(0, 3.95, -2.8), C.WoodLight, M.Wood)
	for _, sx in { -1, 1 } do
		B:Solid("Block", "Side", V(0.5, 3.2, 5.4), cf * CFrame.new(sx * 4.75, 2.2, 0.3), C.Wood, M.WoodPlanks)
		B:Deco("Block", "Post", V(0.6, 7.7, 0.6), cf * CFrame.new(sx * 4.95, 4.45, -3.3), C.WoodDark, M.Wood)
	end
	B:Solid("Block", "Back", V(10, 8, 0.5), cf * CFrame.new(0, 4.6, 3.1), C.Wood, M.WoodPlanks)
	local roof = cf * CFrame.new(0, 8.75, -0.3) * CFrame.Angles(math.rad(10), 0, 0)
	B:Solid("Block", "Roof", V(12.4, 0.5, 9), roof, rgb(70, 92, 140), M.WoodPlanks)
	B:Deco("Block", "RoofSnow", V(12.2, 0.6, 8.8), roof * CFrame.new(0, 0.5, 0), C.Snow, M.Snow, { Shadow = false })
	B:Deco("Cylinder", "RoofLip", V(12.4, 0.9, 0.9), roof * CFrame.new(0, 0.45, -4.4), C.Snow, M.Snow, { Shadow = false })
	-- sign on the roof front + note on the counter
	local board = B:Deco("Block", "Sign", V(7.4, 1.5, 0.3), cf * CFrame.new(0, 10.75, -3.4), C.WoodLight, M.WoodPlanks)
	B:Text(board, Enum.NormalId.Front, { Key = "maps.snowdin.sentry", Color = rgb(70, 40, 24), Font = "Merriweather", Pixels = 50 })
	local note = B:Deco("Block", "Note", V(2.2, 0.05, 1.3), cf * CFrame.new(1.6, 4.13, -2.9) * CFrame.Angles(0, math.rad(-8), 0), rgb(246, 240, 222), M.SmoothPlastic, { Shadow = false })
	B:Text(note, Enum.NormalId.Top, { Key = "maps.snowdin.sentry.note", Color = rgb(40, 40, 60), Font = "PatrickHand", Pixels = 60, Weight = Enum.FontWeight.Regular })
	B:Deco("Cylinder", "Mug", V(0.7, 0.6, 0.6), cf * CFrame.new(-2.4, 4.45, -2.9) * UPRIGHT, rgb(200, 70, 60), M.SmoothPlastic, { Shadow = false })
	local lamp = B:Lamp("SentryLamp", (cf * CFrame.new(-3.6, 8.2, -3.9)).Position, { Style = "Lantern", Drop = 1.0, Metal = C.Iron, Glow = C.Warm, LightColor = C.WarmLight, Brightness = 1.8, Range = 18 })
	-- drifts around the booth and a stack of crates
	local rng = B.Rng
	for _, off in { V(-7, 0, 1), V(6.8, 0, 2.5), V(0, 0, 5) } do
		B:Mound("SentryDrift", (cf * CFrame.new(off)).Position, rng:Number(2.2, 3), rng:Number(0.8, 1.2), { Collide = false, Stretch = 1.8 })
	end
	crate(B, "SentryCrate", cf * CFrame.new(7.6, 0, -1.5) * CFrame.Angles(0, math.rad(-14), 0), 2.6)
	B:Group(nil)
	return if lamp then 1 else 0
end

-- Frozen pond (south-west) ----------------------------------------------------------------------------------

local function buildPond(B: Builder): number
	B:Group("Pond")
	local c = L.Pond
	local rng = B.Rng
	B:Disc("Geometry", "PondIce", V(c.X, L.IceTop / 2, c.Z), L.PondR * 2, L.IceTop, C.Ice, M.Ice, { Reflectance = 0.08 })
	B:Disc("Decor", "PondIceDeep", V(c.X, L.IceTop + 0.01, c.Z), L.PondR * 1.25, 0.02, C.IceDeep, M.Ice, { Shadow = false, Transparency = 0.35 })
	B:Ring("Decor", "PondBank", V(c.X, 0.25, c.Z), L.PondR + 0.6, 2.2, 0.5, 26, C.SnowShade, M.Snow, { Shadow = false })
	-- skate marks (thin pale arcs, outside the SAVE inlay)
	for k = 1, 3 do
		local r = 9.5 + k * 2.2
		local from = rng:Number(0, 360)
		B:ArcRing("Decor", "SkateMark", CFrame.new(c.X, L.IceTop + 0.025, c.Z) * CFrame.Angles(math.pi / 2, 0, 0), r, from, from + rng:Number(70, 120), 5, 0.14, 0.02, C.IceMark, M.SmoothPlastic, { Shadow = false })
	end
	-- stones, reeds and a lamp on the bank
	for i, a in { 20, 75, 160, 215, 300 } do
		local r = math.rad(a)
		local p = c + V(math.cos(r) * (L.PondR + 1.6), 0, math.sin(r) * (L.PondR + 1.6))
		B:Rock("PondStone", p, rng:Number(1.4, 2.4) + (if i == 3 then 1.4 else 0), { Collide = false, Snow = true, Color = C.Stone })
	end
	for _, a in { 120, 250 } do
		local r = math.rad(a)
		local center = c + V(math.cos(r) * (L.PondR - 0.5), 0, math.sin(r) * (L.PondR - 0.5))
		for _ = 1, 6 do
			local p = center + V(rng:Number(-1.6, 1.6), 0, rng:Number(-1.6, 1.6))
			local h = rng:Number(2.2, 3.6)
			B:Rod("Decor", "Reed", p, p + V(rng:Number(-0.4, 0.4), h, rng:Number(-0.4, 0.4)), 0.14, rgb(120, 104, 70), M.SmoothPlastic, { Shadow = false })
		end
	end
	bench(B, "PondBench", MapKit.Facing(c + V(-L.PondR - 4.5, 0, -3), c))
	local lights = postLamp(B, "PondLamp", c + V(16, 0, -14.5))
	-- cold under-glow that makes the ice shine against the warm town
	B:Light("Point", c + V(0, 7, 0), { Name = "PondGlow", Brightness = 0.9, Range = 26, Color = C.Cold })
	B:Group(nil)
	return lights + 1
end

-- Bakery garden (north-west) and the knoll -------------------------------------------------------------------

local function buildGarden(B: Builder): number
	B:Group("Garden")
	B:Fence("GardenFence", { V(-30, 0, -76), V(-58, 0, -76), V(-70, 0, -64), V(-70, 0, -40) }, { Snow = true, Color = C.Wood })
	-- raised vegetable beds under the snow (low cover)
	for i, p in { V(-60, 0, -48), V(-44, 0, -70) } do
		local cf = CFrame.new(p) * CFrame.Angles(0, math.rad(if i == 1 then 90 else 0), 0)
		B:Solid("Block", "Bed", V(9, 1.1, 3.6), cf * CFrame.new(0, 0.55, 0), C.WoodDark, M.WoodPlanks)
		B:Deco("Ellipsoid", "BedSnow", V(8.6, 0.9, 3.2), cf * CFrame.new(0, 1.1, 0), C.Snow, M.Snow, { Shadow = false })
	end
	-- the knoll north of the bakery: a walkable snow hill with a lookout bench
	B:Mound("Knoll", L.Knoll, 13, 3.4, { Collide = true })
	bench(B, "KnollBench", MapKit.Facing(L.Knoll + V(2, 3.1, 3), V(0, 3.1, 0)))
	local lights = postLamp(B, "GardenLamp", V(-28, 0, -64))
	B:Group(nil)
	return lights
end

-- Travellers' camp + town gate (south, human spawns) --------------------------------------------------------

local function buildCamp(B: Builder): number
	B:Group("Camp")
	local rng = B.Rng
	local c = L.Camp
	-- campfire: stone ring, crossed logs, layered flames, embers, a warm shadow-casting light
	for k = 0, 8 do
		local a = k * 2 * math.pi / 9
		B:Deco("Ellipsoid", "FireStone", V(1.2, 0.7, 1.0), CFrame.new(c + V(math.cos(a) * 2.2, 0.3, math.sin(a) * 2.2)) * CFrame.Angles(0, -a, 0), MapKit.Shade(C.Stone, rng:Number(-0.1, 0.05)), M.Slate)
	end
	for k = 0, 2 do
		local a = k * math.pi / 3
		local d = V(math.cos(a), 0, math.sin(a)) * 1.7
		B:Rod("Decor", "FireLog", c + V(0, 0.35, 0) - d, c + V(0, 0.75, 0) + d, 0.5, C.WoodDark, M.Wood)
	end
	B:Cone("Decor", "Flame", c + V(0, 0.4, 0), 3.2, 1.2, 5, rgb(255, 120, 40), M.Neon, { Shadow = false })
	B:Cone("Decor", "FlameCore", c + V(0, 0.5, 0), 2.2, 0.75, 5, rgb(255, 214, 110), M.Neon, { Shadow = false, Phase = 36 })
	local ember = B:Deco("Block", "Embers", V(1, 0.2, 1), CFrame.new(c + V(0, 1.6, 0)), C.Warm, M.SmoothPlastic, { Transparency = 1, Shadow = false })
	B:Particles(ember, "Embers", { Color = rgb(255, 170, 70), Rate = 6 })
	B:Light("Point", c + V(0, 2.6, 0), { Name = "CampfireLight", Brightness = 2.4, Range = 30, Color = rgb(255, 150, 70), Shadows = true })
	-- log seats around the fire
	for k, a in { 30, 150, 270 } do
		local r = math.rad(a)
		local p = c + V(math.cos(r) * 5.6, 0.55, math.sin(r) * 5.6)
		local t = V(-math.sin(r), 0, math.cos(r)) * 1.9
		B:Rod("Geometry", "SeatLog" .. k, p - t, p + t, 1.1, C.Wood, M.Wood)
	end
	tent(B, "TentWest", MapKit.Facing(V(-40, 0, 86), V(-30, 0, 86)))
	tent(B, "TentEast", MapKit.Facing(V(40, 0, 86), V(30, 0, 86)))
	-- the town gate: log posts, a snowy crossbeam, the hanging name board and two lanterns
	local z = L.GateZ
	for _, sx in { -1, 1 } do
		B:Solid("Cylinder", "GatePost", V(12.4, 1.4, 1.4), CFrame.new(sx * 7.6, 6.2, z) * UPRIGHT, C.WoodDark, M.Wood)
		B:Deco("Ellipsoid", "GatePostSnow", V(1.6, 0.6, 1.6), CFrame.new(sx * 7.6, 12.45, z), C.Snow, M.Snow, { Shadow = false })
	end
	B:Deco("Cylinder", "GateBeam", V(18.6, 1.1, 1.1), CFrame.new(0, 11.3, z), C.WoodDark, M.Wood)
	B:Deco("Block", "GateBeamSnow", V(18, 0.45, 1.0), CFrame.new(0, 11.95, z), C.Snow, M.Snow, { Shadow = false })
	local board = B:Deco("Block", "GateBoard", V(11.5, 2.1, 0.35), CFrame.new(0, 9.1, z), C.WoodLight, M.WoodPlanks)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		B:Text(board, face, { Key = "maps.crossroads.gate", Color = rgb(70, 40, 24), Font = "Merriweather", Pixels = 50 })
	end
	for _, sx in { -1, 1 } do
		B:Rod("Decor", "GateChain", V(sx * 4.6, 10.15, z), V(sx * 4.6, 10.8, z), 0.12, C.Iron, M.Metal, { Shadow = false })
	end
	local lights = 2
	for _, sx in { -1, 1 } do
		if B:Lamp("GateLantern", V(sx * 7.6, 10.4, z - 1.2), { Style = "Lantern", Drop = 0.6, Metal = C.Iron, Glow = C.Warm, LightColor = C.WarmLight, Brightness = 1.8, Range = 18 }) then
			lights += 1
		end
	end
	-- fences along the south edge, following the octagon's diagonal walls
	for _, sx in { -1, 1 } do
		B:Fence("SouthFence", { V(sx * 10, 0, z + 0.5), V(sx * 40, 0, z + 0.5), V(sx * 66, 0, 70) }, { Snow = true, Color = C.Wood })
	end
	B:Signpost("CampSign", V(7.5, 0, 80.5), { { Key = "maps.snowdin.sign.square", Yaw = 90 }, { Key = "maps.crossroads.sign.camp", Yaw = -90 } }, { Snow = true, Height = 6.4 })
	B:Group(nil)
	return lights
end

-- Cover in the open: snow forts, rocks, mounds, creek-side fences --------------------------------------------

local function buildCover(B: Builder)
	B:Group("Cover")
	local rng = B.Rng
	snowFort(B, "FortEast", MapKit.Facing(V(22, 0, 40), V(22, 0, 0)))
	snowFort(B, "FortWest", MapKit.Facing(V(-18, 0, -32), V(0, 0, 0)))
	snowman(B, "CampSnowman", V(-22, 0, 80), V(0.3, 0, -1), 0.85)
	local boulders = {
		{ P = V(-80, 0, 2), S = 5 },
		{ P = V(70, 0, -64), S = 5.5 },
		{ P = V(-6, 0, -58), S = 4 },
		{ P = V(84, 0, 46), S = 4.5 },
		{ P = V(-34, 0, 36), S = 4.2 },
		{ P = V(30, 0, 62.5), S = 3 },
		{ P = V(-88, 0, -40), S = 5 },
	}
	for _, r in boulders do
		B:Rock("Boulder", r.P, r.S, { Snow = true, Color = C.Stone })
	end
	-- gentle walkable snow hills
	for _, m in { { P = V(-60, 0, 66), R = 10, H = 1.8 }, { P = V(68, 0, 78), R = 9, H = 1.6 }, { P = V(76, 0, -24), R = 9, H = 2.2 } } do
		B:Mound("Hill", m.P, m.R, m.H, { Collide = true })
	end
	-- fences along the creek's north bank (open around the bridge)
	for _, seg in { { 14, 42 }, { -40, -14 } } do
		local x0, x1 = seg[1], seg[2]
		B:Fence("CreekFence", { V(x0, 0, creekZ(x0) - 11), V(x1, 0, creekZ(x1) - 11) }, { Snow = true, Color = C.Wood, Height = 2.8 })
	end
	logPile(B, "WestLogs", CFrame.new(-90, 0, 14) * CFrame.Angles(0, math.rad(80), 0), 8)
	-- a sled left by the camp
	local sled = CFrame.new(18, 0, 78) * CFrame.Angles(0, math.rad(-30), 0)
	B:Deco("Block", "SledDeck", V(2.2, 0.25, 4.6), sled * CFrame.new(0, 0.9, 0), C.Red, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		B:Deco("Block", "SledRunner", V(0.2, 0.25, 5.2), sled * CFrame.new(sx * 1.0, 0.25, 0.1), C.Iron, M.Metal, { Shadow = false })
		B:Deco("Block", "SledLeg", V(0.2, 0.7, 0.2), sled * CFrame.new(sx * 1.0, 0.55, 1.4), C.Iron, M.Metal, { Shadow = false })
		B:Deco("Block", "SledLeg", V(0.2, 0.7, 0.2), sled * CFrame.new(sx * 1.0, 0.55, -1.4), C.Iron, M.Metal, { Shadow = false })
	end
	local _ = rng
	B:Group(nil)
end

-- Street lamps --------------------------------------------------------------------------------------------------

local function buildLamps(B: Builder): number
	B:Group("Lamps")
	local lights = 0
	for _, p in { V(30, 0, -7.5), V(60, 0, 7.5), V(-32, 0, 7.5), V(-78, 0, -7.5), V(7.5, 0, -42) } do
		lights += postLamp(B, "StreetLamp", p)
	end
	B:Group(nil)
	return lights
end

-- Pines: cover inside the arena, the forest ring and the far mountains outside --------------------------------

local function pine(B: Builder, name: string, x: number, z: number, h: number, opts: { [string]: any }?)
	local o = opts or {}
	B:Pine(name, V(x, o.Y or 0, z), h, {
		Tiers = o.Tiers or 3,
		Sides = o.Sides or 5,
		Width = o.Width or 0.36,
		Leaf = o.Leaf or MapKit.Shade(C.Pine, B.Rng:Number(-0.07, 0.05)),
		Collide = o.Collide,
	})
end

-- Lighter pine for the forest outside the walls (same proportions as MapKit Pine): the sheltered lowest
-- tier carries no snow, the trunk is optional (hidden behind the nearer ring anyway).
local function forestPine(B: Builder, name: string, base: Vector3, height: number, sides: number, tiers: number, trunk: boolean, leaf: Color3)
	local rng = B.Rng
	local trunkH = height * 0.22
	if trunk then
		local d = math.max(0.6, height * 0.06)
		B:Deco("Cylinder", name .. "_Trunk", V(trunkH + 1, d, d), CFrame.new(base + V(0, (trunkH + 1) / 2 - 0.5, 0)) * UPRIGHT, rgb(70, 50, 40), M.Wood)
	end
	local tierH = (height - trunkH) / (tiers * 0.72 + 0.28)
	local y = trunkH
	local phase = rng:Number(0, 360)
	for t = 1, tiers do
		local k = (t - 1) / math.max(1, tiers - 1)
		local radius = height * 0.36 * (1 - 0.48 * k)
		local h = tierH * (1 - 0.08 * k)
		local tierBase = base + V(0, y, 0)
		B:Cone("Decor", name .. "_Tier" .. t, tierBase, h, radius, sides, MapKit.Shade(leaf, 0.05 * k), M.SmoothPlastic, { Phase = phase + t * 30 })
		if t > 1 then
			local f = 0.5 + 0.08 * k
			B:Cone("Decor", name .. "_Snow" .. t, tierBase + V(0, h * (1 - f) + 0.06, 0), h * f + 0.08, radius * f + 0.12, sides, C.Snow, M.Snow, {
				Phase = phase + t * 30,
				Shadow = false,
			})
		end
		y += h * 0.72
	end
end

local INNER_PINES = {
	{ 64, -54, 24 },
	{ 80, -36, 20 },
	{ 56, -72, 26 },
	{ 36, -62, 18 },
	{ -14, -62, 21 },
	{ 34, -86, 24 },
	{ -42, -88, 22 },
	{ -74, -30, 24 },
	{ -86, -12, 19 },
	{ -86, 32, 22 },
	{ -86, 46, 17 },
	{ 76, 44, 22 },
	{ 88, 24, 19 },
	{ 90, -20, 18 },
	{ -50, 80, 20 },
	{ 52, 78, 19 },
	{ -24, 46, 18 },
	{ -64, -58, 14 },
}

local function buildPines(B: Builder)
	B:Group("Pines")
	for i, t in INNER_PINES do
		pine(B, "Pine", t[1], t[2], t[3], { Width = if t[3] >= 22 then 0.34 else 0.36 })
		-- a sapling next to some of them
		if i % 5 == 0 then
			forestPine(B, "Sapling", V(t[1] + 4.5, 0, t[2] + 3), t[3] * 0.42, 4, 2, true, C.Pine)
		end
	end
	B:Group(nil)
end

local function exitGap(x: number, z: number): boolean
	return math.abs(x) < 15 or math.abs(z) < 15 or math.abs(z - creekZ(x)) < 15
end

local function buildBackdrop(B: Builder)
	B:Group("Forest")
	local rng = B.Rng
	-- inner ring: full pines hugging the walls; outer ring: bigger, cheaper silhouettes
	local n1 = 30
	for i = 0, n1 - 1 do
		local a = (i + rng:Number(-0.25, 0.25)) * 2 * math.pi / n1
		local r = 113 + rng:Number(-3, 8)
		local x, z = math.sin(a) * r, -math.cos(a) * r
		if not exitGap(x, z) then
			forestPine(B, "ForestPine", V(x, 0, z), rng:Number(26, 38), 5, 3, true, MapKit.Shade(C.PineFar, rng:Number(-0.05, 0.08)))
		end
	end
	local n2 = 22
	for i = 0, n2 - 1 do
		local a = (i + 0.5 + rng:Number(-0.2, 0.2)) * 2 * math.pi / n2
		local r = 140 + rng:Number(-4, 10)
		local x, z = math.sin(a) * r, -math.cos(a) * r
		if not exitGap(x, z) then
			forestPine(B, "ForestPineFar", V(x, 0, z), rng:Number(38, 50), 4, 3, false, MapKit.Shade(C.PineFar, rng:Number(-0.12, 0)))
		end
	end
	B:Group("Mountains")
	for i = 0, 8 do
		local a = math.rad(i * 40 + rng:Number(-12, 12))
		local r = rng:Number(380, 460)
		local base = V(math.sin(a) * r, -30, -math.cos(a) * r)
		local h = rng:Number(130, 200)
		local rad = h * rng:Number(0.7, 0.9)
		local phase = rng:Number(0, 72)
		B:Cone("Decor", "Peak", base, h, rad, 5, MapKit.Shade(C.Mountain, rng:Number(-0.08, 0.06)), M.Slate, { Phase = phase, Shadow = false })
		B:Cone("Decor", "PeakSnow", base + V(0, h * 0.58, 0), h * 0.42 + 0.5, rad * 0.42 + 1, 5, C.SnowShade, M.Snow, { Phase = phase, Shadow = false })
	end
	B:Group(nil)
end

-- Walls, objectives, spawns ------------------------------------------------------------------------------------

local function buildBoundary(B: Builder)
	local t = 2
	for k = 0, 7 do
		local a = math.rad(k * 45)
		local dir = V(math.sin(a), 0, -math.cos(a))
		local center = dir * (L.Bound + t / 2) + V(0, -12, 0)
		local side = 2 * L.Bound * math.tan(math.rad(22.5)) + 6
		-- local X along the wall, LookVector towards the centre
		B:Boundary("Boundary" .. k, MapKit.Facing(center, V(0, -12, 0)), side, 100, t)
	end
end

function SnowdinCrossroads.Build(seed: number?, opts: { [string]: any }?): MapInfo
	local o = opts or {}
	local B = MapKit.new("SnowdinCrossroads", { Seed = seed or 1 })
	buildGround(B)
	buildCreek(B)
	local lights = 0
	lights += buildBridge(B)
	lights += buildPlaza(B)
	lights += buildHouses(B)
	lights += buildSentry(B)
	lights += buildPond(B)
	lights += buildGarden(B)
	lights += buildCamp(B)
	buildCover(B)
	lights += buildLamps(B)
	buildPines(B)
	if not o.NoBackdrop then
		buildBackdrop(B)
	end
	buildBoundary(B)

	-- objectives: frozen pond (open ice), Main Street (between the shop and the inn), the bakery garden
	local saveStyle = { Inner = rgb(40, 56, 84), InnerMaterial = M.Slate }
	local saves = {
		B:SavePoint(1, V(L.Pond.X, L.IceTop, L.Pond.Z), { Inner = rgb(60, 110, 150), InnerMaterial = M.Ice }),
		B:SavePoint(2, V(66, 0, 0), saveStyle),
		B:SavePoint(3, V(-50, 0, -60), saveStyle),
	}
	local humanSpawns: { CFrame } = {}
	local i = 0
	for _, z in { 82, 90 } do
		for _, x in { -30, -20, -11, 11, 20, 30 } do
			i += 1
			table.insert(humanSpawns, B:SpawnPoint("Human", i, MapKit.Facing(V(x, 0, z), V(x * 0.3, 0, 0))))
		end
	end
	local monsterSpawn = B:SpawnPoint("Monster", 1, MapKit.Facing(L.MonsterSpawn, V(0, 0, 0)))
	local center = V(0, 0, 0)
	B:Marker("Center", CFrame.new(center + V(0, 0.5, 0)))
	B:KillFloor(L.KillY, 600)
	local _ = lights
	B:Finish(SnowdinCrossroads.Id)

	return {
		Id = SnowdinCrossroads.Id,
		Model = B.Model,
		HumanSpawns = humanSpawns,
		MonsterSpawn = monsterSpawn,
		SavePoints = saves,
		Center = center,
		Radius = L.Radius,
		KillY = L.KillY,
		IntroPath = {
			MapKit.LookAt(V(84, 70, 196), V(0, 6, 20)),
			MapKit.LookAt(V(-18, 18, 112), V(0, 5, 52)),
			MapKit.LookAt(V(-40, 13, 34), V(0, 14, 0)),
			MapKit.LookAt(V(28, 10, -16), V(0, 8, -60)),
			MapKit.LookAt(V(6, 8, -60), V(0, 6, -86)),
		},
		Preset = SnowdinCrossroads.Preset,
		FinalPreset = SnowdinCrossroads.FinalPreset,
		Music = SnowdinCrossroads.Music,
	}
end

return SnowdinCrossroads
