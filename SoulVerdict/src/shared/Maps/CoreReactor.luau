--!strict
-- Maps/CoreReactor: "Core Reactor" — steel catwalks over a lake of magma around a roaring reactor. [Lune-safe]
-- Layout (top view, forward = -Z = north). The arena is a wheel of steel hung above lava (floor -29):
--   centre   the REACTOR: a glowing core seen through a slotted casing, steel flanges, two floating
--            containment rings, a crown with emitter prongs, a heat beam into the sky and four containment
--            lasers to pylons on the diagonal pads (all far above the fight). It blocks every sightline.
--   ring     the Reactor Ring (y 0, r 14..38): the duel floor around the core — consoles, crates and barrels
--            as cover, a railed inner edge, two railed outer arcs (the rest drops into the lava).
--   S  Loading Bay (0)        human spawns (12) before a sealed blast door, shipping containers.
--   N  Control Deck (+8)      monster spawn before the open, red-lit door of the control block.
--   E  Turbine Hall (0)       a turbine and generators — SAVE 2.    W Coolant Station (-4) blue tanks, steam — SAVE 1.
--   NE Heat Gantry (+12)      radiators, SAVE 3 (closest to the monster). SW Crane Gantry (+10) crane cab, crates.
--   SE Lava Overlook (0)      laser fence over the lava.   NW Vent Pad (+2) steam stack.
-- Four straight arms and two steel stairs join the ring to the pads; ten more catwalks/stairs link the pads into
-- an outer loop (S-Overlook-E-HeatGantry-N-VentPad-W-CraneGantry-S). Diamond-plate catwalks with yellow
-- railings (+ invisible guards); pads are plain metal plates so telegraphs read. Neon lava channels with
-- PointLights under-light the steel; vents carry steam (built-in smoke texture), heat vents carry embers.
-- Far machinery (cooling towers, smokestacks, pipes) stands in the haze. Invisible 16-sided boundary at
-- r = 114, KillY = -20 (the lava surface is ~-27; decor, never collidable).
-- Built around the origin (ring floor top y = 0, forward = -Z); MapService offsets it.
--
-- API (Types.MapDef): CoreReactor.Id/Name/Desc/Preset/FinalPreset/Music
--   CoreReactor.Build(seed?, opts?) -> MapInfo   opts = { Overview: boolean? } (skips the far machinery)
--   CoreReactor.Layout                           layout constants (pads, saves, KillY...) for tests/tools
-- Local helpers metalStairs/catwalk are open steel variants (treads + stringers + invisible ramp, exactly the
-- MapKit B:Stairs collision scheme) because MapKit's stairs are solid masonry.

local Types = require(script.Parent.Parent.Types)
local MapKit = require(script.Parent.MapKit)

type MapInfo = Types.MapInfo
type Builder = MapKit.Builder

local CoreReactor = {}

CoreReactor.Id = "CoreReactor"
CoreReactor.Name = { en = "Core Reactor", ru = "Реактор Ядра" }
CoreReactor.Desc = {
	en = "Catwalks over a roaring heart of magma and machinery.",
	ru = "Мостки над ревущим сердцем из магмы и машин.",
}
CoreReactor.Preset = "CoreInferno"
CoreReactor.FinalPreset = "CoreInfernoFinal"
CoreReactor.Music = "Map_CoreReactor"

local V = Vector3.new
local M = Enum.Material
local UP = Vector3.new(0, 1, 0)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local C = {
	Deck = rgb(78, 74, 74), -- pad plates
	DeckAlt = rgb(68, 64, 66),
	DeckDark = rgb(44, 40, 40),
	Plate = rgb(96, 90, 88), -- diamond-plate catwalks
	Steel = rgb(58, 56, 60),
	SteelDark = rgb(32, 30, 32),
	Rust = rgb(112, 62, 40),
	Concrete = rgb(116, 106, 98),
	Hazard = rgb(240, 182, 30),
	HazardDark = rgb(26, 24, 24),
	Rail = rgb(226, 166, 28),
	Lava = rgb(255, 98, 20),
	LavaHot = rgb(255, 184, 70),
	Crust = rgb(58, 30, 24),
	Core = rgb(255, 128, 34),
	CoreHot = rgb(255, 214, 130),
	Laser = rgb(255, 54, 30),
	Coolant = rgb(60, 186, 255),
	Window = rgb(255, 150, 70),
	Alarm = rgb(255, 36, 24),
	Pipe = rgb(84, 74, 70),
	PipeHot = rgb(140, 70, 40),
	Container = rgb(150, 50, 34),
	Container2 = rgb(40, 92, 104),
	Screen = rgb(255, 160, 60),
	ScreenGreen = rgb(90, 255, 150),
	Light = rgb(255, 128, 48),
	LightWarm = rgb(255, 176, 104),
	Steam = rgb(232, 226, 220),
}

-- Layout (studs) --------------------------------------------------------------------------------------------
export type PadSpec = { Center: Vector3, SX: number, SZ: number }

local L = {
	KillY = -20,
	FloorY = -29, -- crust floor top (supports stand on it)
	LavaY = -27.2, -- lava channel surface
	Radius = 104, -- Collapse start radius
	BoundaryR = 114,
	RingIn = 14,
	RingOut = 38,
	CoreR = 9,
	CoreTop = 44,
	Pads = {
		Bay = { Center = V(0, 0, 82), SX = 52, SZ = 28 },
		Control = { Center = V(0, 8, -82), SX = 44, SZ = 24 },
		Turbine = { Center = V(84, 0, 0), SX = 32, SZ = 44 },
		Coolant = { Center = V(-84, -4, 0), SX = 32, SZ = 44 },
		HeatGantry = { Center = V(54, 12, -54), SX = 26, SZ = 26 },
		CraneGantry = { Center = V(-54, 10, 54), SX = 26, SZ = 26 },
		Overlook = { Center = V(58, 0, 58), SX = 18, SZ = 18 },
		VentPad = { Center = V(-58, 2, -58), SX = 18, SZ = 18 },
	} :: { [string]: PadSpec },
	Saves = { V(-80, -4, -2), V(80, 0, 2), V(54, 12, -54) },
	MonsterSpawn = V(0, 8, -79),
}
CoreReactor.Layout = L

local function flat(v: Vector3): Vector3
	return V(v.X, 0, v.Z)
end

local function polar(deg: number, r: number, y: number?): Vector3
	local a = math.rad(deg)
	return V(math.cos(a) * r, y or 0, math.sin(a) * r)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Structure helpers ------------------------------------------------------------------------------------------

-- Steel support column from `top` down to `bottomY` with a concrete footing in the lava.
local function column(B: Builder, name: string, top: Vector3, bottomY: number, width: number?)
	local w = width or 1.4
	local h = top.Y - bottomY
	if h <= 0.5 then
		return
	end
	B:Deco("Block", name, V(w, h, w), CFrame.new(V(top.X, (top.Y + bottomY) / 2, top.Z)), C.SteelDark, M.Metal)
	B:Deco("Block", name .. "_Cap", V(w + 0.7, 0.4, w + 0.7), CFrame.new(top - UP * 0.2), C.Steel, M.Metal, { Shadow = false })
	B:Disc("Decor", name .. "_Footing", V(top.X, bottomY + 1.6, top.Z), w * 2.6, 3.2, C.Concrete, M.Concrete)
end

-- Hazard stripes (alternating yellow / black blocks) lying on a surface from a to b.
local function stripes(B: Builder, name: string, a: Vector3, b: Vector3, width: number, seg: number?)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / (seg or 1.6) + 0.5))
	for i = 0, n - 1 do
		B:Beam("Decor", name, a:Lerp(b, i / n), a:Lerp(b, (i + 1) / n), width, 0.06, if i % 2 == 0 then C.Hazard else C.HazardDark, M.SmoothPlastic, { Shadow = false })
	end
end

local function railing(B: Builder, name: string, a: Vector3, b: Vector3)
	B:Railing(name, a, b, { Height = 3, Spacing = 4, Color = C.Rail, Material = M.Metal, Balusters = false })
end

-- Diamond-plate catwalk between two walk-surface points (ends sit ~1-2 studs inside the pads).
-- opts = { Rails = "Both"|"Left"|"Right"|"None", Pipe: boolean? }
local function catwalk(B: Builder, name: string, a: Vector3, b: Vector3, width: number, opts: { [string]: any }?)
	local o = opts or {}
	local delta = b - a
	local len = delta.Magnitude
	local fl = flat(delta).Unit
	local side = V(-fl.Z, 0, fl.X)
	local deckT = 0.8
	B:Beam("Geometry", name .. "_Deck", a - UP * (deckT / 2), b - UP * (deckT / 2), width, deckT, C.Plate, M.DiamondPlate)
	for _, s in { -1, 1 } do
		local off = side * (s * (width / 2 - 0.25))
		B:Beam("Decor", name .. "_Stringer", a + off - UP * 1.4, b + off - UP * 1.4, 0.5, 1.4, C.Steel, M.Metal)
		B:Beam("Decor", name .. "_Kick", a + off + UP * 0.22, b + off + UP * 0.22, 0.14, 0.44, C.Hazard, M.Metal, { Shadow = false })
	end
	local n = math.max(1, math.floor(len / 6))
	for i = 1, n - 1 do
		local p = a:Lerp(b, i / n) - UP * 1.3
		B:Beam("Decor", name .. "_Girder", p - side * (width / 2 - 0.2), p + side * (width / 2 - 0.2), 0.45, 0.9, C.SteelDark, M.Metal, { Shadow = false })
	end
	local rails: string = o.Rails or "Both"
	if rails ~= "None" then
		local sides: { number } = if rails == "Both" then { -1, 1 } elseif rails == "Left" then { 1 } else { -1 }
		for _, s in sides do
			local off = side * (s * (width / 2 - 0.3))
			railing(B, name .. "_Rail", a + off + fl * 1, b + off - fl * 1)
		end
	end
	local supports = math.max(1, math.floor(len / 18))
	for i = 1, supports do
		local p = a:Lerp(b, i / (supports + 1)) - UP * 2.1
		for _, s in { -1, 1 } do
			column(B, name .. "_Leg", p + side * (s * (width / 2 - 0.9)), L.FloorY, 1)
		end
		B:Beam("Decor", name .. "_Brace", p + side * (width / 2 - 0.9) - UP * 5, p - side * (width / 2 - 0.9) - UP * 13, 0.45, 0.45, C.SteelDark, M.Metal, { Shadow = false })
	end
	if o.Pipe then
		local off = side * (width / 2 - 1.4) - UP * 2.7
		B:Rod("Decor", name .. "_Pipe", a + off, b + off, 1.3, C.Pipe, M.Metal)
		local m = math.max(1, math.floor(len / 9))
		for i = 1, m - 1 do
			local p = (a + off):Lerp(b + off, i / m)
			B:Rod("Decor", name .. "_PipeFlange", p - fl * 0.2, p + fl * 0.2, 1.7, C.Steel, M.Metal, { Shadow = false })
		end
	end
end

-- Open steel stairs from `low` to `high` (walk-surface points): diamond-plate treads with yellow nosings,
-- stringers, railings, an invisible collision ramp + top landing (the MapKit B:Stairs scheme).
local function metalStairs(B: Builder, name: string, low: Vector3, high: Vector3, width: number)
	local delta = high - low
	local run = flat(delta).Magnitude
	local rise = delta.Y
	local fl = flat(delta).Unit
	local side = V(-fl.Z, 0, fl.X)
	local cf = MapKit.Facing(low, low + fl)
	local steps = math.max(2, math.ceil(rise / 0.8))
	local sr, sd = rise / steps, run / steps
	for i = 1, steps do
		local top = sr * i
		B:Deco("Block", name .. "_Step" .. i, V(width, 0.3, sd + 0.15), cf * CFrame.new(0, top - 0.15, -(sd * (i - 0.5))), C.Plate, M.DiamondPlate, {
			Query = true,
			Shadow = true,
		})
		B:Deco("Block", name .. "_Nose" .. i, V(width - 0.2, 0.06, 0.32), cf * CFrame.new(0, top + 0.02, -(sd * (i - 1)) - 0.18), C.Hazard, M.SmoothPlastic, { Shadow = false })
	end
	for _, s in { -1, 1 } do
		local off = side * (s * (width / 2 + 0.25))
		B:Beam("Decor", name .. "_Stringer", low + off - UP * 0.2, high + off - UP * 0.2, 0.4, 1.3, C.Steel, M.Metal)
		local roff = side * (s * (width / 2 - 0.05))
		railing(B, name .. "_Rail", low + roff + fl * 0.6, high + roff - fl * 0.6)
	end
	B:Solid("Wedge", name .. "_Ramp", V(width, rise, run), cf * CFrame.new(0, rise / 2, -run / 2) * CFrame.Angles(0, math.pi, 0), C.Steel, M.Metal, {
		Transparency = 1,
		Shadow = false,
		Query = false,
	})
	B:Solid("Block", name .. "_Landing", V(width, 0.2, 0.6), cf * CFrame.new(0, rise - 0.1, -run + 0.3), C.Steel, M.Metal, {
		Transparency = 1,
		Shadow = false,
		Query = false,
	})
	column(B, name .. "_Leg", low:Lerp(high, 0.55) - UP * 1.4 - side * (width / 2 - 0.8), L.FloorY, 1)
	column(B, name .. "_Leg", low:Lerp(high, 0.55) - UP * 1.4 + side * (width / 2 - 0.8), L.FloorY, 1)
end

-- Metal pad (plates + grout lines + steel border) on legs, with an under-frame.
local function pad(B: Builder, name: string, spec: PadSpec)
	local c = spec.Center
	B:Floor(name, c, spec.SX, spec.SZ, {
		Color = C.Deck,
		Material = M.Metal,
		Thickness = 1.6,
		Pattern = "Tiles",
		Tile = 8,
		Grout = C.DeckDark,
		GroutWidth = 0.14,
		Border = { Width = 1, Color = C.Steel, Material = M.Metal },
	})
	B:Deco("Block", name .. "_Underframe", V(spec.SX - 3, 1.6, spec.SZ - 3), CFrame.new(c - UP * 2.4), C.SteelDark, M.Metal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			column(B, name .. "_Leg", c + V(sx * (spec.SX / 2 - 3), -3.2, sz * (spec.SZ / 2 - 3)), L.FloorY, 2)
		end
	end
end

-- Corner helpers for pad rails: returns the walk-surface corner of a pad (sx, sz = -1|1), inset.
local function corner(spec: PadSpec, sx: number, sz: number, inset: number): Vector3
	local c = spec.Center
	return V(c.X + sx * (spec.SX / 2 - inset), c.Y, c.Z + sz * (spec.SZ / 2 - inset))
end

-- Props ------------------------------------------------------------------------------------------------------

local function crateStack(B: Builder, name: string, base: Vector3, yaw: number, count: number)
	local rng = B.Rng
	local frame = CFrame.new(base) * CFrame.Angles(0, math.rad(yaw), 0)
	local spots = { V(0, 1.5, 0), V(3.2, 1.5, 0.3), V(1.5, 4.5, 0.1), V(-0.2, 1.5, 3.1) }
	for i = 1, math.min(count, #spots) do
		local cf = frame * CFrame.new(spots[i]) * CFrame.Angles(0, math.rad(rng:Number(-8, 8)), 0)
		B:Solid("Block", name, V(3, 3, 3), cf, MapKit.Shade(C.Rust, rng:Number(-0.1, 0.1)), M.CorrodedMetal)
		B:Deco("Block", name .. "_Band", V(3.08, 0.3, 3.08), cf * CFrame.new(0, 0.9, 0), C.Steel, M.Metal, { Shadow = false })
		B:Deco("Block", name .. "_Band", V(3.08, 0.3, 3.08), cf * CFrame.new(0, -0.9, 0), C.Steel, M.Metal, { Shadow = false })
	end
end

local function barrels(B: Builder, name: string, base: Vector3, count: number)
	local rng = B.Rng
	for i = 1, count do
		local a = i * 2.4
		local p = base + V(math.cos(a) * 1.6 * (i - 1) * 0.6, 0, math.sin(a) * 1.6 * (i - 1) * 0.6)
		local color = if i % 3 == 0 then C.Container2 else C.Hazard
		B:Disc("Geometry", name, p + UP * 1.6, 2.2, 3.2, color, M.Metal)
		B:Disc("Decor", name .. "_Rim", p + UP * 3.25, 2.3, 0.15, C.SteelDark, M.Metal, { Shadow = false })
		B:Disc("Decor", name .. "_Band", p + UP * 1.6, 2.28, 0.5, if color == C.Hazard then C.HazardDark else C.Steel, M.Metal, { Shadow = false })
		local _ = rng
	end
end

local function console(B: Builder, name: string, base: Vector3, facing: Vector3, screen: Color3)
	local frame = MapKit.Facing(base, base + facing)
	B:Solid("Block", name, V(4.4, 3, 2), frame * CFrame.new(0, 1.5, 0), C.Steel, M.Metal)
	B:Deco("Wedge", name .. "_Desk", V(4.4, 1.2, 2), frame * CFrame.new(0, 3.6, 0), C.Steel, M.Metal)
	-- the screen sits on the slanted face (Wedge slope faces local front/up)
	local slope = frame * CFrame.new(0, 3.62, -0.02) * CFrame.Angles(math.atan2(2, 1.2) - math.pi / 2, 0, 0)
	B:Deco("Block", name .. "_Screen", V(3.6, 0.06, 1.7), slope * CFrame.Angles(-math.pi / 2 + math.atan2(1.2, 2), 0, 0) * CFrame.new(0, 0.02, 0), screen, M.Neon, { Shadow = false })
	B:Deco("Block", name .. "_Kick", V(4.5, 0.4, 2.1), frame * CFrame.new(0, 0.2, 0), C.HazardDark, M.Metal, { Shadow = false })
end

local function container(B: Builder, name: string, center: Vector3, alongX: boolean, color: Color3)
	local size = if alongX then V(12, 8, 6) else V(6, 8, 12)
	local cf = CFrame.new(center + UP * 4)
	B:Solid("Block", name, size, cf, color, M.CorrodedMetal)
	-- corrugation ribs on both long sides
	local long = if alongX then size.X else size.Z
	local n = math.floor(long / 1.6)
	for i = 1, n - 1 do
		local t = -long / 2 + i * long / n
		for _, s in { -1, 1 } do
			local off = if alongX then V(t, 0, s * (size.Z / 2 + 0.05)) else V(s * (size.X / 2 + 0.05), 0, t)
			local rib = if alongX then V(0.3, 7.4, 0.12) else V(0.12, 7.4, 0.3)
			B:Deco("Block", name .. "_Rib", rib, cf * CFrame.new(off), MapKit.Shade(color, -0.18), M.Metal, { Shadow = false })
		end
	end
	B:Deco("Block", name .. "_Roof", size + V(0.3, -7.6, 0.3), cf * CFrame.new(0, 4, 0), MapKit.Shade(color, -0.25), M.Metal, { Shadow = false })
end

-- Steam vent: grate + hidden emitter (MapKit "Smoke" preset tinted as steam).
local function steamVent(B: Builder, name: string, pos: Vector3, rate: number)
	B:Deco("Block", name, V(3.2, 0.2, 3.2), CFrame.new(pos + UP * 0.1), C.SteelDark, M.Metal, { Shadow = false })
	for k = -1, 1 do
		B:Deco("Block", name .. "_Slat", V(3, 0.24, 0.3), CFrame.new(pos + V(0, 0.13, k * 0.9)), C.Steel, M.Metal, { Shadow = false })
	end
	local holder = B:Deco("Block", name .. "_Emitter", V(2.4, 0.2, 2.4), CFrame.new(pos + UP * 0.4), C.Steam, M.SmoothPlastic, {
		Transparency = 1,
		Shadow = false,
	})
	B:Particles(holder, "Smoke", { Color = C.Steam, Rate = rate })
end

-- Glowing floor grate with rising embers (heat vents around the reactor).
local function heatVent(B: Builder, name: string, pos: Vector3, yaw: number)
	local frame = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	B:Deco("Block", name .. "_Glow", V(3.6, 0.06, 2), frame * CFrame.new(0, 0.03, 0), C.Core, M.Neon, { Shadow = false })
	for k = -2, 2 do
		B:Deco("Block", name .. "_Bar", V(0.3, 0.14, 2.2), frame * CFrame.new(k * 0.8, 0.08, 0), C.SteelDark, M.Metal, { Shadow = false })
	end
	B:Deco("Block", name .. "_Frame", V(4, 0.1, 2.4), frame * CFrame.new(0, 0.01, 0), C.Steel, M.Metal, { Shadow = false })
	local holder = B:Deco("Block", name .. "_Emitter", V(3, 0.2, 1.6), frame * CFrame.new(0, 0.3, 0), C.Core, M.SmoothPlastic, {
		Transparency = 1,
		Shadow = false,
	})
	B:Particles(holder, "Embers", { Color = C.LavaHot, Rate = 5 })
end

local function sign(B: Builder, name: string, cf: CFrame, width: number, height: number, key: string, glow: Color3?)
	local panel = B:Deco("Block", name, V(width, height, 0.3), cf, C.HazardDark, M.Metal)
	B:Deco("Block", name .. "_Frame", V(width + 0.4, height + 0.4, 0.2), cf * CFrame.new(0, 0, 0.1), C.Hazard, M.Metal, { Shadow = false })
	B:Text(panel, Enum.NormalId.Front, { Key = key, Font = "Oswald", Color = glow or C.Hazard, Glow = true, Pixels = 40 })
end

local function beacon(B: Builder, name: string, pos: Vector3, color: Color3, withLight: boolean): number
	B:Deco("Cylinder", name .. "_Base", V(0.5, 1.2, 1.2), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), C.SteelDark, M.Metal, { Shadow = false })
	B:Ball("Decor", name, pos + UP * 0.6, 1, color, M.Neon, { Shadow = false })
	if withLight then
		B:Light("Point", pos + UP * 1.2, { Name = name .. "_Light", Brightness = 2, Range = 16, Color = color })
		return 1
	end
	return 0
end

-- Sections ---------------------------------------------------------------------------------------------------

local function buildReactor(B: Builder): number
	B:Group("Reactor")
	local r = L.CoreR
	local bottom = L.FloorY
	local top = L.CoreTop
	local casingBottom = bottom + 8
	local casingH = top - casingBottom
	local casingMid = (top + casingBottom) / 2
	B:Disc("Geometry", "Foundation", V(0, bottom + 4, 0), 30, 8, C.Concrete, M.Concrete)
	B:Disc("Decor", "FoundationBand", V(0, bottom + 7.4, 0), 30.4, 1.2, C.Hazard, M.Metal, { Shadow = false })
	-- the glowing core, seen through the slots between the casing staves
	B:Disc("Decor", "Core", V(0, casingMid, 0), 13.4, casingH, C.Core, M.Neon, { Shadow = false })
	local staves = 12
	for k = 0, staves - 1 do
		local a = math.rad((k + 0.5) * 360 / staves)
		local p = V(math.cos(a) * (r - 0.7), casingMid, math.sin(a) * (r - 0.7))
		local tangent = V(-math.sin(a), 0, math.cos(a))
		B:Solid("Block", "Stave", V(3.5, casingH, 1.4), CFrame.fromMatrix(p, tangent, UP), C.Steel, M.Metal)
		-- rivet strip
		B:Deco("Block", "StaveRib", V(0.5, casingH - 2, 0.3), CFrame.fromMatrix(p + V(math.cos(a), 0, math.sin(a)) * 0.8, tangent, UP), C.SteelDark, M.Metal, { Shadow = false })
	end
	-- flanges
	for _, y in { casingBottom + 1, -6, 6.5, 19, 31 } do
		B:Ring("Decor", "Flange", V(0, y, 0), r + 0.5, 1.6, 1.4, 16, C.SteelDark, M.Metal)
	end
	-- floating containment rings
	for i, y in { 14, 24 } do
		B:Ring("Decor", "ContainmentRing", V(0, y, 0), 12.4 - i * 0.4, 0.5, 0.5, 24, C.CoreHot, M.Neon, { Shadow = false })
	end
	-- crown: cap, glowing iris, six emitter prongs and the heat beam
	B:Disc("Decor", "Crown", V(0, top + 1.5, 0), 23, 3, C.Steel, M.Metal)
	B:Disc("Decor", "CrownIris", V(0, top + 3.1, 0), 13, 0.3, C.CoreHot, M.Neon, { Shadow = false })
	for k = 0, 5 do
		local a = k * 60 + 30
		local base = polar(a, 10.5, top + 2.5)
		local tip = polar(a, 5.5, top + 10)
		B:Rod("Decor", "Prong", base, tip, 1.3, C.Steel, M.Metal)
		B:Ball("Decor", "ProngTip", tip, 1.4, C.CoreHot, M.Neon, { Shadow = false })
	end
	B:Disc("Decor", "HeatBeam", V(0, top + 33, 0), 3.4, 58, C.Core, M.Neon, { Shadow = false, Transparency = 0.35 })
	B:Disc("Decor", "HeatBeamHalo", V(0, top + 30, 0), 7.5, 52, C.Lava, M.Neon, { Shadow = false, Transparency = 0.85 })
	-- big pipes feeding the core from below the ring
	for k = 0, 3 do
		local a = k * 90 + 45
		B:Rod("Decor", "FeedPipe", polar(a, 8.5, -12), polar(a, 70, -18), 3.2, C.PipeHot, M.Metal)
		B:Rod("Decor", "FeedPipeCollar", polar(a, 12, -12.3), polar(a, 13, -12.4), 4.2, C.SteelDark, M.Metal, { Shadow = false })
	end
	-- light: the core floods the whole ring (Neon does not light its surroundings)
	B:Light("Point", V(0, -16, 0), { Name = "CorePool", Brightness = 3, Range = 50, Color = C.Light })
	B:Light("Point", V(0, 6, 0), { Name = "CoreMid", Brightness = 2.6, Range = 44, Color = C.Light, Shadows = true })
	B:Light("Point", V(0, 24, 0), { Name = "CoreHigh", Brightness = 2.2, Range = 40, Color = C.LightWarm })
	B:Light("Point", V(0, top + 6, 0), { Name = "CoreCrown", Brightness = 2.4, Range = 36, Color = C.LightWarm })
	B:Group(nil)
	return 4
end

local function buildRing(B: Builder): number
	B:Group("Ring")
	local lights = 0
	local rIn, rOut = L.RingIn, L.RingOut
	local n = 24
	local thick = 1.6
	for k = 0, n - 1 do
		local a0, a1 = k * 360 / n, (k + 1) * 360 / n
		local i0, i1 = polar(a0, rIn, -thick / 2), polar(a1, rIn, -thick / 2)
		local o0, o1 = polar(a0, rOut, -thick / 2), polar(a1, rOut, -thick / 2)
		local color = if k % 2 == 0 then C.Deck else C.DeckAlt
		B:Triangle("Geometry", "RingPlate", i0, o0, o1, thick, color, M.Metal)
		B:Triangle("Geometry", "RingPlate", i0, o1, i1, thick, color, M.Metal)
		-- seam line between plates
		B:Beam("Decor", "RingSeam", polar(a0, rIn + 0.6, 0.03), polar(a0, rOut - 0.4, 0.03), 0.16, 0.05, C.DeckDark, M.Metal, { Shadow = false })
	end
	-- under-structure: box girders on both edges, radial girders, legs
	B:Ring("Decor", "RingGirderOuter", V(0, -2.6, 0), rOut - 1, 1.8, 3, 24, C.SteelDark, M.Metal)
	B:Ring("Decor", "RingGirderInner", V(0, -2.6, 0), rIn + 1, 1.6, 3, 16, C.SteelDark, M.Metal)
	for k = 0, 11 do
		local a = k * 30 + 15
		B:Beam("Decor", "RadialGirder", polar(a, rIn + 1, -2.4), polar(a, rOut - 1, -2.4), 1, 2.4, C.Steel, M.Metal, { Shadow = false })
		if k % 2 == 0 then
			column(B, "RingLeg", polar(a, 30, -4), L.FloorY, 2)
		end
	end
	-- hazard band along the inner edge, steel lip on the outer edge
	local m = 40
	for k = 0, m - 1 do
		local a0, a1 = k * 360 / m, (k + 1) * 360 / m
		B:Beam("Decor", "InnerStripe", polar(a0, rIn + 1.3, 0.03), polar(a1, rIn + 1.3, 0.03), 1.1, 0.06, if k % 2 == 0 then C.Hazard else C.HazardDark, M.SmoothPlastic, { Shadow = false })
	end
	B:Ring("Decor", "OuterLip", V(0, 0.15, 0), rOut - 0.3, 0.6, 0.3, 32, C.Steel, M.Metal, { Shadow = false })
	-- inner railing all around (nobody drops into the core shaft), outer railings on two arcs only
	local seg = 16
	for k = 0, seg - 1 do
		railing(B, "InnerRail", polar(k * 360 / seg, rIn + 0.4, 0), polar((k + 1) * 360 / seg, rIn + 0.4, 0))
	end
	for _, arc in { { 15, 75 }, { 195, 255 } } do
		local steps = 4
		for k = 0, steps - 1 do
			local a0 = lerp(arc[1], arc[2], k / steps)
			local a1 = lerp(arc[1], arc[2], (k + 1) / steps)
			railing(B, "OuterRail", polar(a0, rOut - 0.6, 0), polar(a1, rOut - 0.6, 0))
		end
	end
	-- cover: consoles, crates, barrels (free sectors only; arms at 0/90/180/270, stairs at 135/315)
	console(B, "Console", polar(40, 24), -polar(40, 1), C.Screen)
	console(B, "Console", polar(116, 27), -polar(116, 1), C.ScreenGreen)
	console(B, "Console", polar(238, 31), -polar(238, 1), C.Screen)
	console(B, "Console", polar(334, 26), -polar(334, 1), C.ScreenGreen)
	crateStack(B, "Crate", polar(62, 31), 20, 3)
	crateStack(B, "Crate", polar(206, 26), -30, 4)
	crateStack(B, "Crate", polar(292, 30), 60, 2)
	barrels(B, "Barrel", polar(156, 30), 4)
	barrels(B, "Barrel", polar(20, 31), 3)
	-- heat vents between the inner rail and the cover
	for _, a in { 70, 160, 250, 340 } do
		heatVent(B, "HeatVent", polar(a, 18.5), -a + 90)
	end
	B:Group(nil)
	return lights
end

local function buildLava(B: Builder, overview: boolean): number
	B:Group("Lava")
	local rng = B.Rng
	local lights = 0
	local reach = if overview then 120 else 190
	-- crust floor (CrackedLava) and the pool around the reactor foundation
	local crust = if overview then 250 else 420
	B:Deco("Block", "Crust", V(crust, 2, crust), CFrame.new(0, L.FloorY - 1, 0), C.Crust, M.CrackedLava, { Shadow = false })
	B:Disc("Decor", "CorePool", V(0, L.LavaY, 0), 58, 0.8, C.Lava, M.Neon, { Shadow = false })
	B:Disc("Decor", "CorePoolHot", V(0, L.LavaY + 0.1, 0), 40, 0.8, C.LavaHot, M.Neon, { Shadow = false })
	-- channels meandering out from the pool
	for k = 0, 5 do
		local a = k * 60 + 18 + rng:Number(-8, 8)
		local r = 26
		local pts: { Vector3 } = { polar(a, r, L.LavaY) }
		while r < reach do
			r += rng:Number(18, 26)
			a += rng:Number(-9, 9)
			table.insert(pts, polar(a, r, L.LavaY))
		end
		for i = 1, #pts - 1 do
			local t = (i - 1) / (#pts - 1)
			local w = lerp(13, 6, t)
			B:Beam("Decor", "LavaChannel", pts[i], pts[i + 1], w, 0.6, C.Lava, M.Neon, { Shadow = false })
			B:Disc("Decor", "LavaBend", pts[i + 1], w, 0.6, C.Lava, M.Neon, { Shadow = false })
			B:Beam("Decor", "LavaCore", pts[i] + UP * 0.12, pts[i + 1] + UP * 0.12, w * 0.3, 0.5, C.LavaHot, M.Neon, { Shadow = false })
		end
	end
	-- crust rocks and cooled lava ridges
	for _ = 1, 34 do
		local p = polar(rng:Number(0, 360), rng:Number(40, reach - 15), L.FloorY)
		B:Rock("CrustRock", p, rng:Number(4, 11), { Color = MapKit.Shade(C.Crust, rng:Number(-0.2, 0.1)), Material = M.CrackedLava, Collide = false })
	end
	-- under-glow: lights just above the lava under the steel
	for _, p in { V(0, -21, 58), V(58, -21, 0), V(-58, -21, 0), V(0, -21, -58), V(40, -21, 40), V(-40, -21, -40), V(40, -21, -40), V(-40, -21, 40) } do
		B:Light("Point", p, { Name = "LavaGlow", Brightness = 2.2, Range = 44, Color = C.Light })
		lights += 1
	end
	-- embers rising from the lava under the ring
	for k = 0, 3 do
		local holder = B:Deco("Block", "LavaEmbers", V(14, 0.2, 14), CFrame.new(polar(k * 90 + 45, 24, L.LavaY + 0.6)), C.Lava, M.SmoothPlastic, {
			Transparency = 1,
			Shadow = false,
		})
		B:Particles(holder, "Embers", { Color = C.LavaHot, Rate = 10 })
	end
	B:Group(nil)
	return lights
end

local function buildBay(B: Builder, spec: PadSpec): number
	B:Group("LoadingBay")
	local c = spec.Center
	local lights = 0
	pad(B, "BayFloor", spec)
	-- painted lanes: two yellow lines and a stop band before the door
	for _, x in { -18.5, 18.5 } do
		B:Deco("Block", "LaneLine", V(0.4, 0.05, spec.SZ - 4), CFrame.new(c + V(x, 0.03, 0)), C.Hazard, M.SmoothPlastic, { Shadow = false })
	end
	stripes(B, "DoorStripe", c + V(-14, 0.04, 11.5), c + V(14, 0.04, 11.5), 1.4, 1.75)
	-- the sealed blast door in its bulkhead
	local wallZ = c.Z + spec.SZ / 2 + 1
	B:Solid("Block", "Bulkhead", V(spec.SX + 4, 26, 2), CFrame.new(c.X, 13 - 0.8, wallZ), C.Steel, M.Metal)
	B:Deco("Block", "BulkheadTop", V(spec.SX + 5, 2, 3), CFrame.new(c.X, 25.4, wallZ), C.SteelDark, M.Metal)
	for _, x in { -27, 27 } do
		B:Deco("Block", "BulkheadPillar", V(3, 26, 3.4), CFrame.new(c.X + x, 12.2, wallZ - 0.4), C.SteelDark, M.Metal)
	end
	local doorZ = wallZ - 1.1
	B:Deco("Block", "DoorFrame", V(26, 19, 0.6), CFrame.new(c.X, 9.5, doorZ), C.SteelDark, M.Metal)
	for _, s in { -1, 1 } do
		local leaf = CFrame.new(c.X + s * 6.05, 9, doorZ - 0.45)
		B:Deco("Block", "DoorLeaf", V(12, 17, 0.6), leaf, C.Steel, M.DiamondPlate)
		-- chevrons (yellow/black diagonal bands)
		for k = -3, 3 do
			local band = leaf * CFrame.new(0, k * 2.3, -0.34) * CFrame.Angles(0, 0, math.rad(s * 35))
			B:Deco("Block", "DoorChevron", V(13.2, 0.9, 0.08), band, if k % 2 == 0 then C.Hazard else C.HazardDark, M.SmoothPlastic, { Shadow = false })
		end
	end
	-- the chevron bands overhang the leaves: trim them visually with frame posts
	for _, s in { -1, 1 } do
		B:Deco("Block", "DoorJamb", V(1.4, 19, 1.4), CFrame.new(c.X + s * 12.7, 9.5, doorZ - 0.6), C.SteelDark, M.Metal)
	end
	B:Deco("Block", "DoorLintel", V(26.8, 1.6, 1.4), CFrame.new(c.X, 18.6, doorZ - 0.6), C.SteelDark, M.Metal)
	B:Deco("Block", "DoorSeam", V(0.2, 17, 0.1), CFrame.new(c.X, 9, doorZ - 0.8), C.HazardDark, M.SmoothPlastic, { Shadow = false })
	sign(B, "BaySign", CFrame.new(c.X, 21.6, doorZ - 0.2) * CFrame.Angles(0, math.pi, 0), 16, 2.6, "maps.corereactor.sign.bay")
	lights += beacon(B, "DoorBeacon", V(c.X - 15, 19.4, doorZ - 0.6), C.Alarm, true)
	lights += beacon(B, "DoorBeacon", V(c.X + 15, 19.4, doorZ - 0.6), C.Alarm, true)
	-- containers (cover) at the ends of the bay
	container(B, "Container", V(c.X - 22, c.Y, c.Z + 6.5), false, C.Container)
	container(B, "Container", V(c.X + 22, c.Y, c.Z + 7.5), false, C.Container2)
	crateStack(B, "BayCrate", V(c.X + 13, c.Y, c.Z - 9), 15, 2)
	barrels(B, "BayBarrel", V(c.X - 12, c.Y, c.Z - 10), 3)
	-- rails along the open north edge (gap for the arm)
	railing(B, "BayRail", corner(spec, -1, -1, 0.5), V(c.X - 8, c.Y, c.Z - spec.SZ / 2 + 0.5))
	railing(B, "BayRail", V(c.X + 8, c.Y, c.Z - spec.SZ / 2 + 0.5), corner(spec, 1, -1, 0.5))
	B:Group(nil)
	return lights
end

local function buildControl(B: Builder, spec: PadSpec): number
	B:Group("ControlDeck")
	local c = spec.Center
	local lights = 0
	pad(B, "ControlFloor", spec)
	local backZ = c.Z - spec.SZ / 2
	-- the control block (solid) with an open blast door and a window band
	local blockZ = backZ - 7
	B:Solid("Block", "ControlBlock", V(48, 22, 12), CFrame.new(c.X, c.Y + 11 - 0.8, blockZ), C.Steel, M.Metal)
	B:Deco("Block", "ControlRoof", V(50, 1.6, 14), CFrame.new(c.X, c.Y + 21, blockZ), C.SteelDark, M.Metal)
	B:Deco("Block", "WindowBand", V(40, 3.2, 0.3), CFrame.new(c.X, c.Y + 15.5, backZ - 0.9), C.Window, M.Neon, { Shadow = false, Transparency = 0.15 })
	for k = -4, 4 do
		B:Deco("Block", "WindowMullion", V(0.5, 3.4, 0.5), CFrame.new(c.X + k * 4.6, c.Y + 15.5, backZ - 0.75), C.SteelDark, M.Metal, { Shadow = false })
	end
	-- open door: a dark red-lit recess, leaves slid aside
	B:Deco("Block", "LairRecess", V(13, 11, 0.4), CFrame.new(c.X, c.Y + 5.5, backZ - 0.4), rgb(40, 6, 4), M.SmoothPlastic, { Shadow = false })
	B:Deco("Block", "LairGlow", V(9, 7, 0.2), CFrame.new(c.X, c.Y + 4.5, backZ - 0.55), rgb(150, 16, 10), M.Neon, { Shadow = false, Transparency = 0.25 })
	for _, s in { -1, 1 } do
		B:Deco("Block", "LairLeaf", V(6.6, 12, 0.8), CFrame.new(c.X + s * 10.3, c.Y + 6, backZ - 1.2), C.Steel, M.DiamondPlate)
		for k = -2, 2 do
			B:Deco("Block", "LairChevron", V(7, 0.8, 0.08), CFrame.new(c.X + s * 10.3, c.Y + 6 + k * 2.2, backZ - 1.65) * CFrame.Angles(0, 0, math.rad(s * 35)), if k % 2 == 0 then C.Hazard else C.HazardDark, M.SmoothPlastic, { Shadow = false })
		end
	end
	B:Deco("Block", "LairLintel", V(15, 1.4, 1.2), CFrame.new(c.X, c.Y + 11.7, backZ - 1), C.SteelDark, M.Metal)
	B:Light("Point", V(c.X, c.Y + 5, backZ - 3), { Name = "LairLight", Brightness = 2.4, Range = 26, Color = rgb(255, 60, 30) })
	lights += 1
	sign(B, "ControlSign", CFrame.new(c.X, c.Y + 19, backZ - 0.9) * CFrame.Angles(0, math.pi, 0), 20, 2.4, "maps.corereactor.sign.core", C.Screen)
	lights += beacon(B, "ControlBeacon", V(c.X - 20, c.Y + 21.8, blockZ + 5), C.Alarm, false)
	lights += beacon(B, "ControlBeacon", V(c.X + 20, c.Y + 21.8, blockZ + 5), C.Alarm, false)
	-- consoles flanking the spawn, rails on the side edges (front stays open to the stairs)
	console(B, "DeckConsole", c + V(-13, 0, -5), V(0, 0, 1), C.Screen)
	console(B, "DeckConsole", c + V(13, 0, -5), V(0, 0, 1), C.Screen)
	railing(B, "ControlRail", corner(spec, -1, 1, 0.5), V(c.X - 8.5, c.Y, c.Z + spec.SZ / 2 - 0.5))
	railing(B, "ControlRail", V(c.X + 8.5, c.Y, c.Z + spec.SZ / 2 - 0.5), corner(spec, 1, 1, 0.5))
	stripes(B, "ControlEdge", V(c.X - 7, c.Y + 0.04, c.Z + spec.SZ / 2 - 0.8), V(c.X + 7, c.Y + 0.04, c.Z + spec.SZ / 2 - 0.8), 1.2)
	B:Group(nil)
	return lights
end

local function buildTurbine(B: Builder, spec: PadSpec): number
	B:Group("TurbineHall")
	local c = spec.Center
	pad(B, "TurbineFloor", spec)
	-- the turbine: a long housing (axis Z) on saddles, with ribs and an exhaust cone
	local axisX = c.X + 10
	local z0, z1 = c.Z - 14, c.Z + 12
	local y = c.Y + 4.2
	B:Solid("Cylinder", "Turbine", V(z1 - z0, 7.2, 7.2), CFrame.new(axisX, y, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0), C.Steel, M.Metal)
	for k = 0, 5 do
		local z = lerp(z0 + 1.5, z1 - 1.5, k / 5)
		B:Deco("Cylinder", "TurbineRib", V(0.6, 7.8, 7.8), CFrame.new(axisX, y, z) * CFrame.Angles(0, math.pi / 2, 0), C.SteelDark, M.Metal, { Shadow = false })
	end
	B:Deco("Cylinder", "TurbineHot", V(2.2, 7.6, 7.6), CFrame.new(axisX, y, z1 - 4) * CFrame.Angles(0, math.pi / 2, 0), C.PipeHot, M.Metal, { Shadow = false })
	for _, z in { z0 + 3, z1 - 3 } do
		B:Solid("Block", "TurbineSaddle", V(8, 1.6, 2), CFrame.new(axisX, c.Y + 0.8, z), C.SteelDark, M.Metal)
	end
	-- generators in the north-east corner
	for k = 0, 2 do
		B:Solid("Block", "Generator", V(4, 5, 3.4), CFrame.new(c.X + 8 + k * 4.4, c.Y + 2.5, c.Z - 19.5), C.Container2, M.Metal)
		B:Deco("Block", "GeneratorGrill", V(3, 2.4, 0.1), CFrame.new(c.X + 8 + k * 4.4, c.Y + 3, c.Z - 17.75), C.SteelDark, M.Metal, { Shadow = false })
		B:Deco("Block", "GeneratorLamp", V(0.6, 0.3, 0.1), CFrame.new(c.X + 8 + k * 4.4, c.Y + 4.6, c.Z - 17.74), C.ScreenGreen, M.Neon, { Shadow = false })
	end
	sign(B, "TurbineSign", CFrame.new(axisX - 3.75, y + 1.4, c.Z - 1) * CFrame.Angles(0, -math.pi / 2, 0), 9, 1.6, "maps.corereactor.sign.turbine")
	-- rails: the whole east edge, the open west edge keeps its arm gap
	railing(B, "TurbineRail", corner(spec, 1, -1, 0.5), corner(spec, 1, 1, 0.5))
	railing(B, "TurbineRail", corner(spec, -1, -1, 0.5), V(c.X - spec.SX / 2 + 0.5, c.Y, c.Z - 7.5))
	B:Light("Point", c + V(-2, 7, 0), { Name = "TurbineLight", Brightness = 1.4, Range = 22, Color = C.LightWarm })
	B:Group(nil)
	return 1
end

local function buildCoolant(B: Builder, spec: PadSpec): number
	B:Group("CoolantStation")
	local c = spec.Center
	local lights = 0
	pad(B, "CoolantFloor", spec)
	-- three coolant tanks with glowing level windows along the west edge
	for i, z in { -14, 0, 14 } do
		local base = V(c.X - 10, c.Y, c.Z + z)
		B:Disc("Geometry", "Tank", base + UP * 6, 7, 12, C.Steel, M.Metal)
		B:Disc("Decor", "TankCap", base + UP * 12.4, 6.2, 0.8, C.SteelDark, M.Metal)
		B:Disc("Decor", "TankBand", base + UP * 3, 7.3, 0.8, C.Hazard, M.Metal, { Shadow = false })
		-- level window facing east (towards the arena)
		B:Deco("Block", "TankWindow", V(0.3, 6, 1.6), CFrame.new(base + V(3.55, 6.6, 0)), C.Coolant, M.Neon, { Shadow = false })
		B:Deco("Block", "TankWindowFrame", V(0.2, 6.6, 2.2), CFrame.new(base + V(3.45, 6.6, 0)), C.SteelDark, M.Metal, { Shadow = false })
		B:Rod("Decor", "TankPipe", base + V(2.4, 10.6, 2.2), base + V(8, 0.6, 2.2), 0.9, C.Pipe, M.Metal)
		if i ~= 2 then
			B:Light("Point", base + V(5, 6, 0), { Name = "CoolantGlow", Brightness = 1.4, Range = 16, Color = C.Coolant })
			lights += 1
		end
	end
	B:Rod("Decor", "Manifold", V(c.X - 2, c.Y + 0.6, c.Z - 16), V(c.X - 2, c.Y + 0.6, c.Z + 16), 1.1, C.Pipe, M.Metal)
	steamVent(B, "SteamVent", V(c.X + 9, c.Y, c.Z - 15), 5)
	steamVent(B, "SteamVent", V(c.X + 10, c.Y, c.Z + 15), 4)
	sign(B, "CoolantSign", CFrame.new(c.X - 6.4, c.Y + 9, c.Z + 7) * CFrame.Angles(0, math.pi / 2, 0), 7, 1.6, "maps.corereactor.sign.coolant", C.Coolant)
	railing(B, "CoolantRail", corner(spec, -1, -1, 0.5), corner(spec, -1, 1, 0.5))
	B:Group(nil)
	return lights
end

local function buildHeatGantry(B: Builder, spec: PadSpec): number
	B:Group("HeatGantry")
	local c = spec.Center
	pad(B, "GantryFloor", spec)
	-- radiator banks (cover) in the far corner, glowing fins
	for k = 0, 4 do
		local p = c + V(6 + k * 1.3, 0, -9 + k * 0.2)
		B:Solid("Block", "Radiator", V(0.6, 4.6, 6), CFrame.new(p + UP * 2.3), C.Steel, M.Metal)
		B:Deco("Block", "RadiatorHeat", V(0.62, 0.4, 5.6), CFrame.new(p + UP * 3.6), C.Core, M.Neon, { Shadow = false })
	end
	B:Deco("Block", "RadiatorFrame", V(7.4, 0.6, 6.6), CFrame.new(c + V(8.6, 4.9, -8.6)), C.SteelDark, M.Metal)
	-- rails: north and east edges
	railing(B, "GantryRail", corner(spec, -1, -1, 0.5), corner(spec, 1, -1, 0.5))
	railing(B, "GantryRail", corner(spec, 1, -1, 0.5), V(c.X + spec.SX / 2 - 0.5, c.Y, c.Z + 6))
	sign(B, "GantrySign", CFrame.new(c.X - 2, c.Y + 2.4, c.Z - spec.SZ / 2 + 0.7) * CFrame.Angles(0, math.pi, 0), 10, 1.6, "maps.corereactor.sign.gantry")
	B:Light("Point", c + V(0, 7, 0), { Name = "GantryLight", Brightness = 1.4, Range = 22, Color = C.LightWarm })
	B:Group(nil)
	return 1
end

local function buildCraneGantry(B: Builder, spec: PadSpec): number
	B:Group("CraneGantry")
	local c = spec.Center
	pad(B, "CraneFloor", spec)
	-- crane: a mast in the far corner, a boom over the lava and a hanging hook
	local mast = c + V(-8, 0, 8)
	B:Solid("Block", "CraneMast", V(2.4, 18, 2.4), CFrame.new(mast + UP * 9), C.Hazard, M.Metal)
	B:Solid("Block", "CraneCab", V(5, 4, 4), CFrame.new(mast + V(1.4, 2, -2.6)), C.Hazard, M.Metal)
	B:Deco("Block", "CraneCabWindow", V(4.2, 1.6, 0.1), CFrame.new(mast + V(1.4, 2.8, -4.62)), C.Window, M.Neon, { Shadow = false, Transparency = 0.2 })
	local boomEnd = mast + V(-26, 17, 22)
	B:Beam("Decor", "CraneBoom", mast + V(0, 17, 0), boomEnd, 1.6, 1.6, C.Hazard, M.Metal)
	B:Beam("Decor", "CraneCounter", mast + V(0, 17, 0), mast + V(9, 16, -8), 1.6, 1.6, C.Hazard, M.Metal)
	B:Deco("Block", "CraneWeight", V(3, 3, 3), CFrame.new(mast + V(9, 15, -8)), C.Concrete, M.Concrete)
	B:Rod("Decor", "CraneCable", boomEnd, boomEnd - UP * 22, 0.18, C.SteelDark, M.Metal, { Shadow = false })
	B:Deco("Block", "CraneHook", V(1.6, 2.2, 0.6), CFrame.new(boomEnd - UP * 23), C.SteelDark, M.Metal)
	B:Deco("Block", "CraneLoad", V(6, 3, 6), CFrame.new(boomEnd - UP * 25.5) * CFrame.Angles(0, math.rad(20), 0), C.Container, M.CorrodedMetal)
	crateStack(B, "GantryCrate", c + V(5, 0, -4), 40, 3)
	railing(B, "CraneRail", corner(spec, -1, 1, 0.5), corner(spec, 1, 1, 0.5))
	railing(B, "CraneRail", corner(spec, -1, -1, 0.5), V(c.X - spec.SX / 2 + 0.5, c.Y, c.Z + 3))
	B:Light("Point", mast + V(1.4, 5, -5), { Name = "CraneLight", Brightness = 1.4, Range = 20, Color = C.LightWarm })
	B:Group(nil)
	return 1
end

local function buildOverlook(B: Builder, spec: PadSpec): number
	B:Group("Overlook")
	local c = spec.Center
	pad(B, "OverlookFloor", spec)
	-- laser fence along the outer (south-east) edges: emitter posts + thin beams + invisible guard
	local fence = { corner(spec, -1, 1, 0.6), corner(spec, 1, 1, 0.6), corner(spec, 1, -1, 0.6) }
	for i = 1, #fence - 1 do
		local a, b = fence[i], fence[i + 1]
		for _, p in { a, b } do
			B:Solid("Block", "LaserPost", V(0.8, 3.6, 0.8), CFrame.new(p + UP * 1.8), C.SteelDark, M.Metal)
			B:Ball("Decor", "LaserEye", p + UP * 3.8, 0.6, C.Laser, M.Neon, { Shadow = false })
		end
		for _, h in { 1, 2, 3 } do
			B:Rod("Decor", "LaserBeam", a + UP * h, b + UP * h, 0.12, C.Laser, M.Neon, { Shadow = false })
		end
		B:Boundary("LaserGuard", CFrame.fromMatrix((a + b) / 2, (b - a).Unit, UP), (b - a).Magnitude, 3.8, 0.6)
	end
	sign(B, "HeatSign", CFrame.new(c.X - 7.5, c.Y + 2.6, c.Z + 3) * CFrame.Angles(0, -math.pi / 2, 0), 9, 1.8, "maps.corereactor.sign.heat", C.Alarm)
	B:Deco("Block", "HeatSignPost", V(0.4, 1.8, 0.4), CFrame.new(c.X - 7.5, c.Y + 0.9, c.Z + 3), C.SteelDark, M.Metal)
	B:Light("Point", c + V(0, 4, 0), { Name = "OverlookLight", Brightness = 1.2, Range = 18, Color = C.Laser })
	B:Group(nil)
	return 1
end

local function buildVentPad(B: Builder, spec: PadSpec): number
	B:Group("VentPad")
	local c = spec.Center
	pad(B, "VentFloor", spec)
	-- vent stack: a short tower with steam pouring out
	local base = c + V(-4, 0, -4)
	B:Solid("Cylinder", "VentStack", V(10, 5, 5), CFrame.new(base + UP * 5) * CFrame.Angles(0, 0, math.pi / 2), C.Steel, M.Metal)
	for k = 0, 2 do
		B:Deco("Cylinder", "VentStackRing", V(0.5, 5.6, 5.6), CFrame.new(base + UP * (2 + k * 3.4)) * CFrame.Angles(0, 0, math.pi / 2), C.Hazard, M.Metal, { Shadow = false })
	end
	local holder = B:Deco("Block", "VentStackEmitter", V(3, 0.3, 3), CFrame.new(base + UP * 10.2), C.Steam, M.SmoothPlastic, { Transparency = 1, Shadow = false })
	B:Particles(holder, "Smoke", { Color = C.Steam, Rate = 8 })
	steamVent(B, "VentGrate", c + V(4, 0, 3), 4)
	railing(B, "VentRail", corner(spec, -1, -1, 0.5), corner(spec, 1, -1, 0.5))
	railing(B, "VentRail", corner(spec, -1, -1, 0.5), corner(spec, -1, 1, 0.5))
	B:Light("Point", c + V(2, 6, 2), { Name = "VentLight", Brightness = 1.2, Range = 18, Color = C.LightWarm })
	B:Group(nil)
	return 1
end

-- Containment pylons on the diagonal pads + lasers to the reactor crown (all far above the fight).
local function buildLasers(B: Builder)
	B:Group("Lasers")
	local pads = L.Pads
	local spots = {
		corner(pads.HeatGantry, 1, -1, 1.6),
		corner(pads.CraneGantry, -1, 1, 1.6),
		corner(pads.Overlook, 1, 1, 2.2),
		corner(pads.VentPad, -1, -1, 2.2),
	}
	for i, p in spots do
		local h = 26 - p.Y * 0.5
		B:Solid("Block", "Pylon", V(1.8, h, 1.8), CFrame.new(p + UP * (h / 2)), C.SteelDark, M.Metal)
		for k = 1, 3 do
			B:Deco("Block", "PylonBand", V(2, 0.4, 2), CFrame.new(p + UP * (h * k / 4)), C.Hazard, M.Metal, { Shadow = false })
		end
		local head = p + UP * (h + 1.2)
		B:Deco("Block", "PylonHead", V(2.6, 2.4, 2.6), CFrame.new(head), C.Steel, M.Metal)
		B:Ball("Decor", "PylonLens", head + UP * 1.6, 1.3, C.Laser, M.Neon, { Shadow = false })
		local crownPoint = polar(i * 90 + 45, 6, L.CoreTop + 9)
		B:Rod("Decor", "ContainmentLaser", head + UP * 1.6, crownPoint, 0.22, C.Laser, M.Neon, { Shadow = false })
	end
	B:Group(nil)
end

-- Far machinery in the haze (decor only).
local function buildFar(B: Builder)
	B:Group("Far")
	local rng = B.Rng
	-- cooling towers (stacked, waisted cylinders) with steam
	for i, spot in { { 70, 230 }, { 110, 250 }, { 300, 240 } } do
		local base = polar(spot[1], spot[2], L.FloorY)
		local tiers = 7
		local h = 92
		for k = 0, tiers - 1 do
			local t = (k + 0.5) / tiers
			local radius = 30 * (0.62 + 0.38 * ((2 * t - 1.25) ^ 2))
			B:Disc("Decor", "CoolingTower", base + UP * (h * t), radius * 2, h / tiers + 0.2, MapKit.Shade(C.Concrete, -0.05 * (k % 2)), M.Concrete, { Shadow = false })
		end
		local holder = B:Deco("Block", "TowerSteam", V(30, 1, 30), CFrame.new(base + UP * (h + 1)), C.Steam, M.SmoothPlastic, { Transparency = 1, Shadow = false })
		B:Particles(holder, "Smoke", { Color = C.Steam, Rate = 6 })
		local _ = i
	end
	-- smokestacks with warning bands
	for _, spot in { { 20, 190 }, { 150, 200 }, { 200, 180 }, { 250, 210 }, { 335, 190 } } do
		local base = polar(spot[1] + rng:Number(-6, 6), spot[2], L.FloorY)
		local h = rng:Number(90, 120)
		B:Disc("Decor", "Stack", base + UP * (h / 2), 8, h, C.SteelDark, M.Metal, { Shadow = false })
		for k = 1, 3 do
			B:Disc("Decor", "StackBand", base + UP * (h - k * 6), 8.4, 2.5, if k % 2 == 1 then C.Alarm else C.Concrete, M.Metal, { Shadow = false })
		end
		B:Ball("Decor", "StackLamp", base + UP * (h + 0.8), 1.4, C.Alarm, M.Neon, { Shadow = false })
		local holder = B:Deco("Block", "StackSmoke", V(6, 1, 6), CFrame.new(base + UP * (h + 1)), C.Steam, M.SmoothPlastic, { Transparency = 1, Shadow = false })
		B:Particles(holder, "Smoke", { Color = rgb(70, 56, 52), Rate = 4 })
	end
	-- trunk pipes on stilts crossing the lava to the edge of the world
	for k = 0, 3 do
		local a = k * 90 + 45
		local p0, p1 = polar(a, 70, -18), polar(a + 6, 210, -18)
		B:Rod("Decor", "TrunkPipe", p0, p1, 3.2, C.PipeHot, M.Metal, { Shadow = false })
		for j = 1, 5 do
			local p = p0:Lerp(p1, j / 6)
			B:Deco("Block", "TrunkStilt", V(1.4, p.Y - L.FloorY, 1.4), CFrame.new(V(p.X, (p.Y + L.FloorY) / 2 - 1.6, p.Z)), C.SteelDark, M.Metal, { Shadow = false })
		end
	end
	-- a ring of dark rock cliffs at the edge of the lava lake
	for k = 0, 17 do
		local a = k * 20 + rng:Number(-6, 6)
		local p = polar(a, rng:Number(165, 185), L.FloorY)
		local s = rng:Number(18, 34)
		B:Deco("Block", "Cliff", V(s, rng:Number(16, 34), s * 0.8), CFrame.new(p) * CFrame.Angles(0, math.rad(rng:Number(0, 360)), math.rad(rng:Number(-8, 8))), MapKit.Shade(C.Crust, rng:Number(-0.3, -0.05)), M.Basalt, { Shadow = false })
	end
	B:Group(nil)
end

local function buildBoundary(B: Builder)
	local n = 16
	local r = L.BoundaryR
	local len = 2 * r * math.tan(math.pi / n) + 2
	for k = 0, n - 1 do
		local a = (k + 0.5) * 2 * math.pi / n
		local center = V(math.cos(a) * r, L.FloorY, math.sin(a) * r)
		B:Boundary("Boundary" .. k, CFrame.fromMatrix(center, V(-math.sin(a), 0, math.cos(a)), UP), len, 170, 2)
	end
end

-- MapInfo -------------------------------------------------------------------------------------------------------

function CoreReactor.Build(seed: number?, opts: { [string]: any }?): MapInfo
	local o = opts or {}
	local B = MapKit.new("CoreReactor", { Seed = seed or 1 })
	local P = L.Pads
	local lights = 0
	lights += buildLava(B, o.Overview == true)
	lights += buildReactor(B)
	lights += buildRing(B)
	lights += buildBay(B, P.Bay)
	lights += buildControl(B, P.Control)
	lights += buildTurbine(B, P.Turbine)
	lights += buildCoolant(B, P.Coolant)
	lights += buildHeatGantry(B, P.HeatGantry)
	lights += buildCraneGantry(B, P.CraneGantry)
	lights += buildOverlook(B, P.Overlook)
	lights += buildVentPad(B, P.VentPad)

	-- arms, stairs and the outer loop
	B:Group("Catwalks")
	local rIn = L.RingOut - 0.6
	catwalk(B, "BayArm", V(0, 0, rIn), V(0, 0, 69.2), 14, { Pipe = true })
	catwalk(B, "TurbineArm", V(rIn, 0, 0), V(69.2, 0, 0), 12, { Pipe = true })
	catwalk(B, "CoolantArm", V(-rIn, 0, 0), V(-69.2, -4, 0), 12, { Pipe = true })
	metalStairs(B, "ControlStairs", V(0, 0, -rIn), V(0, 8, -70.8), 14)
	metalStairs(B, "HeatStairs", polar(315, rIn), V(45, 12, -45), 10)
	metalStairs(B, "CraneStairs", polar(135, rIn), V(-45, 10, 45), 10)
	catwalk(B, "HeatBridge", V(44, 12, -58), V(18, 8, -81), 8)
	metalStairs(B, "TurbineStairs", V(76, 0, -17), V(58, 12, -45), 8)
	metalStairs(B, "BayStairs", V(-20, 0, 74), V(-45, 10, 58), 8)
	metalStairs(B, "CoolantStairs", V(-76, -4, 17), V(-58, 10, 45), 8)
	catwalk(B, "OverlookWalk", V(76, 0, 19), V(60, 0, 52), 8, { Pipe = true })
	catwalk(B, "OverlookBayWalk", V(52, 0, 62), V(22, 0, 78), 8)
	catwalk(B, "VentWalk", V(-18, 8, -81), V(-53, 2, -61), 8, { Pipe = true })
	catwalk(B, "VentCoolantWalk", V(-60, 2, -53), V(-76, -4, -19), 8)
	B:Group(nil)

	buildLasers(B)
	if not o.Overview then
		buildFar(B)
	end
	buildBoundary(B)

	-- objectives and spawns
	local saveStyle = { Inner = rgb(40, 34, 32), InnerMaterial = M.Metal }
	local saves = {
		B:SavePoint(1, L.Saves[1], saveStyle),
		B:SavePoint(2, L.Saves[2], saveStyle),
		B:SavePoint(3, L.Saves[3], saveStyle),
	}
	local center = V(0, 0, 0)
	local humanSpawns: { CFrame } = {}
	local bay = P.Bay.Center
	local i = 0
	for _, dz in { -4, 4 } do
		for _, x in { -15, -9, -3, 3, 9, 15 } do
			i += 1
			local p = V(x, bay.Y, bay.Z + dz)
			table.insert(humanSpawns, B:SpawnPoint("Human", i, MapKit.SpawnFacing(p, V(x * 0.4, bay.Y, 0))))
		end
	end
	local monsterSpawn = B:SpawnPoint("Monster", 1, MapKit.SpawnFacing(L.MonsterSpawn, V(0, L.MonsterSpawn.Y, 0)))
	B:Marker("Center", CFrame.new(center + V(0, 0.5, 0)))
	B:KillFloor(L.KillY, 400)
	local _ = lights
	B:Finish(CoreReactor.Id)

	return {
		Id = CoreReactor.Id,
		Model = B.Model,
		HumanSpawns = humanSpawns,
		MonsterSpawn = monsterSpawn,
		SavePoints = saves,
		Center = center,
		Radius = L.Radius,
		KillY = L.KillY,
		IntroPath = {
			MapKit.LookAt(V(170, 70, -90), V(0, 20, 0)),
			MapKit.LookAt(V(80, 34, 120), V(0, 6, 60)),
			MapKit.LookAt(V(12, 10, 64), V(0, 16, 0)),
			MapKit.LookAt(V(-34, 16, 6), V(0, 22, -30)),
			MapKit.LookAt(V(-14, 18, -48), V(0, 12, -82)),
			MapKit.LookAt(V(0, 14, -58), V(0, 11, -80)),
		},
		Preset = CoreReactor.Preset,
		FinalPreset = CoreReactor.FinalPreset,
		Music = CoreReactor.Music,
	}
end

return CoreReactor
