--!strict
-- Maps/HallOfVerdicts: a golden judgement hall turned courtroom — the game's first arena. [Lune-safe]
-- A long marble nave (checkered gold floor, crimson runner) between two colonnades; the low sun (preset
-- GoldenHall, sun ~10 deg above the -X horizon) pours through eleven tall stained-glass windows in the
-- west (-X) wall, so long golden beams and pillar shadows stripe the floor. East aisle: alcoves with
-- statues under a gilded balcony. North end: a raised dais with the Judge's bench, a rose window and two
-- great banners (monster spawn). South end: the great doors under a clock (human spawns). Rows of pews,
-- four chandeliers, a ribbed barrel vault. Playable interior ~96 x 200 studs (1 vs 11).
-- Built around the origin (floor top y = 0, nave axis = Z); MapService offsets it.
--
-- API (Types.MapDef): HallOfVerdicts.Id/Name/Desc/Preset/FinalPreset/Music
--   HallOfVerdicts.Build(seed?, opts?) -> MapInfo   opts = { Cutaway: boolean? } (no roof: overview renders)
-- Layout constants are exported as HallOfVerdicts.Layout (tests and other tools may read them).

local Types = require(script.Parent.Parent.Types)
local MapKit = require(script.Parent.MapKit)

type MapInfo = Types.MapInfo

local HallOfVerdicts = {}

HallOfVerdicts.Id = "HallOfVerdicts"
HallOfVerdicts.Name = { en = "Hall of Verdicts", ru = "Зал Приговоров" }
HallOfVerdicts.Desc = {
	en = "A golden corridor of pillars where the last light of day passes judgement.",
	ru = "Золотой коридор колонн, где последний свет дня выносит приговор.",
}
HallOfVerdicts.Preset = "GoldenHall"
HallOfVerdicts.FinalPreset = "GoldenHallFinal"
HallOfVerdicts.Music = "Map_HallOfVerdicts"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local V = Vector3.new
local M = Enum.Material

-- Layout (studs) ------------------------------------------------------------------------------------------
local L = {
	WestX = -47, -- wall centre lines (2 thick)
	EastX = 51,
	NorthZ = -101,
	SouthZ = 101,
	ArcadeX = 28, -- colonnades at x = +-28
	PillarZ0 = -88, -- pillars every 16 studs: -88 .. 88
	PillarStep = 16,
	Pillars = 12,
	PillarH = 34,
	PillarD = 4.6,
	EntTop = 38, -- entablature 34..38
	VaultY = 50, -- vault springing (top of the clerestory walls)
	AisleCeil = 46,
	WallH = 48,
	WinBottom = 1.2,
	WinTop = 36,
	WinWidth = 8,
	DaisTop = 3,
	DaisFront = -78,
	KillY = -40,
}
HallOfVerdicts.Layout = L

local C = {
	Marble = rgb(236, 222, 192),
	MarbleWarm = rgb(224, 204, 164),
	MarbleShade = rgb(196, 172, 132),
	FloorLight = rgb(240, 224, 184),
	FloorDark = rgb(190, 142, 70),
	FloorBorder = rgb(122, 74, 44),
	Plaster = rgb(228, 206, 166),
	Gold = rgb(218, 170, 74),
	GoldDark = rgb(150, 106, 42),
	Crimson = rgb(140, 22, 36),
	CrimsonDark = rgb(96, 14, 26),
	Navy = rgb(30, 38, 78),
	Walnut = rgb(96, 60, 38),
	WalnutDark = rgb(62, 38, 26),
	Lead = rgb(70, 50, 30),
	Glass = rgb(255, 228, 176),
	Flame = rgb(255, 184, 96),
	Lamp = rgb(255, 178, 100),
	Skyline = rgb(170, 128, 104),
}

-- direction the GoldenHall sunlight travels (Lighting:GetSunDirection() negated; see docs/GRAPHICS.md)
local SUN_TRAVEL = Vector3.new(0.979, -0.168, -0.113).Unit

local GLASS_PALETTE = {
	rgb(255, 176, 60),
	rgb(206, 64, 52),
	rgb(70, 116, 214),
	rgb(244, 214, 120),
	rgb(64, 150, 120),
}

local ROSE_OUTER = { rgb(52, 86, 186), rgb(36, 120, 104), rgb(176, 112, 36), rgb(120, 46, 140) }

local function pillarZ(k: number): number
	return L.PillarZ0 + k * L.PillarStep
end

-- Sections -------------------------------------------------------------------------------------------------

local function buildFloor(B: MapKit.Builder)
	B:Group("Floor")
	-- one slab under everything (walls stand on it), checkered marble inside a dark border
	B:Floor("Floor", V(2, 0, 0), 98, 202, {
		Color = C.FloorLight,
		Material = M.Marble,
		Thickness = 4,
		Pattern = "Checker",
		Tile = 6.5,
		Color2 = C.FloorDark,
		Border = { Width = 3, Color = C.FloorBorder, Material = M.Marble },
	})
	-- gold fillets framing the border
	for _, x in { -44.4, 48.4 } do
		B:Deco("Block", "Fillet", V(0.35, 0.07, 194), CFrame.new(x, 0.04, 0), C.Gold, M.Metal, { Shadow = false })
	end
	for _, z in { -96.4, 96.4 } do
		B:Deco("Block", "Fillet", V(93, 0.07, 0.35), CFrame.new(2, 0.04, z), C.Gold, M.Metal, { Shadow = false })
	end
	-- crimson runner from the doors to the dais, gold edges and diamonds
	local z0, z1 = L.DaisFront + 4, 97
	local len = z1 - z0
	local zc = (z0 + z1) / 2
	B:Deco("Block", "Runner", V(10, 0.1, len), CFrame.new(0, 0.07, zc), C.Crimson, M.Fabric, { Shadow = false })
	for _, x in { -4.4, 4.4 } do
		B:Deco("Block", "RunnerEdge", V(0.5, 0.12, len), CFrame.new(x, 0.08, zc), C.Gold, M.Fabric, { Shadow = false })
	end
	local count = math.floor(len / 12)
	for i = 0, count - 1 do
		local z = z0 + 6 + i * 12
		if math.abs(z) > 8 then
			B:Deco("Block", "RunnerDiamond", V(1.6, 0.13, 1.6), CFrame.new(0, 0.09, z) * CFrame.Angles(0, math.rad(45), 0), C.Gold, M.Fabric, { Shadow = false })
		end
	end
	-- the Seal of Verdicts at the hall centre: gold rings + heart on the runner
	B:Disc("Decor", "SealRing", V(0, 0.1, 0), 13, 0.08, C.Gold, M.Metal, { Shadow = false })
	B:Disc("Decor", "SealField", V(0, 0.12, 0), 11.6, 0.08, C.CrimsonDark, M.Fabric, { Shadow = false })
	B:Disc("Decor", "SealInner", V(0, 0.14, 0), 8.4, 0.06, C.Gold, M.Metal, { Shadow = false })
	B:Disc("Decor", "SealCore", V(0, 0.16, 0), 7.6, 0.06, C.Crimson, M.Fabric, { Shadow = false })
	B:Heart("Decor", "SealHeart", CFrame.new(0, 0.2, 0.3) * CFrame.Angles(-math.pi / 2, 0, 0), 3.2, 0.06, rgb(255, 210, 110), M.Neon, { Shadow = false })
	B:Group(nil)
end

local function buildWestWall(B: MapKit.Builder): number
	B:Group("WestWall")
	local lights = 0
	local cf = MapKit.Facing(V(L.WestX, 0, 0), V(0, 0, 0)) -- local X = +Z, LookVector = +X (interior)
	local openings = {}
	for k = 0, 10 do
		table.insert(openings, { X = -80 + k * 16, Width = L.WinWidth, Bottom = L.WinBottom, Top = L.WinTop })
	end
	B:Wall("WestWall", cf, 204, L.WallH, {
		Thickness = 2,
		Color = C.Plaster,
		Material = M.Plaster,
		Openings = openings,
		Baseboard = { Height = 1.4, Color = C.MarbleShade, Material = M.Marble, Depth = 0.4 },
		Cornice = { Height = 1.6, Color = C.MarbleWarm, Material = M.Marble, Depth = 0.9 },
	})
	-- windows
	local yc = (L.WinBottom + L.WinTop) / 2
	for k = 0, 10 do
		local z = -80 + k * 16
		local wcf = MapKit.Facing(V(L.WestX, yc, z), V(0, yc, z))
		local palette = { GLASS_PALETTE[(k % 5) + 1], GLASS_PALETTE[((k + 2) % 5) + 1], GLASS_PALETTE[((k + 3) % 5) + 1] }
		local ls = B:Window("Window" .. k, wcf, L.WinWidth, L.WinTop - L.WinBottom, {
			Depth = 2,
			Wall = 2,
			Cols = 3,
			Rows = 8,
			Frame = C.GoldDark,
			Lead = C.Lead,
			Clear = C.Glass,
			Palette = palette,
			Light = { Brightness = 1.1, Range = 30, Angle = 80, Color = rgb(255, 190, 118) },
		})
		lights += #ls
		-- faint light spill near each window (kept short so the shafts never stack along the nave)
		B:Shaft("SunShaft" .. k, V(L.WestX + 1, yc + 2, z), SUN_TRAVEL, L.WinWidth - 2, (L.WinTop - L.WinBottom) * 0.7, 26, rgb(255, 200, 130), {
			Transparency = 0.975,
		})
	end
	-- pilasters between the windows (aligned with the colonnade)
	for k = 0, L.Pillars - 1 do
		local z = pillarZ(k)
		B:Solid("Block", "Pilaster", V(1.2, 40, 2.6), CFrame.new(L.WestX + 1.6, 20, z), C.MarbleWarm, M.Marble)
		B:Deco("Block", "PilasterCap", V(1.8, 1.4, 3.4), CFrame.new(L.WestX + 1.9, 40.4, z), C.Gold, M.Metal)
		B:Deco("Block", "PilasterBase", V(1.8, 1.6, 3.4), CFrame.new(L.WestX + 1.9, 0.8, z), C.MarbleShade, M.Marble)
	end
	B:Group(nil)
	return lights
end

local function buildEastWall(B: MapKit.Builder): number
	B:Group("EastWall")
	local lights = 0
	local cf = MapKit.Facing(V(L.EastX, 0, 0), V(0, 0, 0))
	B:Wall("EastWall", cf, 204, L.WallH, {
		Thickness = 2,
		Color = C.Plaster,
		Material = M.Plaster,
		Baseboard = { Height = 1.4, Color = C.MarbleShade, Material = M.Marble, Depth = 0.4 },
		Rail = { Y = 24, Height = 0.6, Color = C.Gold, Material = M.Metal, Depth = 0.3 },
		Cornice = { Height = 1.6, Color = C.MarbleWarm, Material = M.Marble, Depth = 0.9 },
	})
	local faceX = L.EastX - 1 -- interior face
	-- piers carve the wall into alcoves; brackets carry the balcony
	for k = 0, L.Pillars - 1 do
		local z = pillarZ(k)
		B:Solid("Block", "Pier", V(3, L.AisleCeil, 3), CFrame.new(faceX - 1.5, L.AisleCeil / 2, z), C.MarbleWarm, M.Marble)
		B:Deco("Block", "PierBase", V(3.6, 1.6, 3.6), CFrame.new(faceX - 1.5, 0.8, z), C.MarbleShade, M.Marble)
		B:Deco("Wedge", "Bracket", V(2.2, 3.2, 6), CFrame.new(faceX - 6, 17.2, z) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0), C.MarbleWarm, M.Marble)
	end
	-- balcony (gallery) at y = 20
	local balY = 20
	B:Solid("Block", "Balcony", V(9, 1.2, 198), CFrame.new(faceX - 4.5, balY - 0.6, 0), C.MarbleWarm, M.Marble)
	B:Deco("Block", "BalconyFascia", V(0.5, 1.6, 198), CFrame.new(faceX - 9.1, balY - 0.7, 0), C.Gold, M.Metal)
	B:Railing("BalconyRail", V(faceX - 8.8, balY, -98), V(faceX - 8.8, balY, 98), {
		Height = 3.4,
		Spacing = 8,
		BalusterGap = 2,
		Color = C.Gold,
		Collide = true,
	})
	-- alcove dressing: statues and benches alternate; sconces in every other alcove
	for k = 0, 10 do
		local z = -80 + k * 16
		local base = V(faceX - 3, 0, z)
		if k % 2 == 0 then
			B:SkullStatue("AlcoveStatue" .. k, base, { Scale = 0.62, Facing = V(-1, 0, 0), Color = C.Marble })
		else
			B:Solid("Block", "Bench" .. k, V(3.2, 1.8, 9), CFrame.new(faceX - 2.2, 0.9, z), C.Walnut, M.Wood)
			B:Deco("Block", "BenchTop" .. k, V(3.6, 0.35, 9.4), CFrame.new(faceX - 2.2, 1.9, z), C.WalnutDark, M.Wood)
			B:Banner("AlcoveBanner" .. k, MapKit.Facing(V(faceX - 0.15, 15.5, z), V(0, 15.5, z)), 4.5, 10, {
				Color = C.Navy,
				Trim = C.Gold,
				Emblem = "Delta",
				Rod = true,
			})
		end
		if k % 2 == 0 then
			local light = B:Lamp("Sconce" .. k, V(faceX - 0.3, 11, z), {
				Style = "Wall",
				Facing = V(-1, 0, 0),
				Metal = C.GoldDark,
				Glow = C.Flame,
				LightColor = C.Lamp,
				Brightness = 1.4,
				Range = 16,
			})
			if light then
				lights += 1
			end
		end
	end
	B:Group(nil)
	return lights
end

local function buildColonnades(B: MapKit.Builder, cutaway: boolean)
	B:Group("Colonnade")
	for _, side in { -1, 1 } do
		local x = side * L.ArcadeX
		for k = 0, L.Pillars - 1 do
			B:Column("Pillar", V(x, 0, pillarZ(k)), L.PillarH, L.PillarD, {
				Style = "Classic",
				Color = C.Marble,
				Accent = C.Gold,
				Dark = C.MarbleShade,
				Material = M.Marble,
				Flutes = 10,
			})
		end
		-- entablature: architrave, gold frieze, cornice
		B:Solid("Block", "Architrave", V(5, 2, 190), CFrame.new(x, L.PillarH + 1, 0), C.MarbleWarm, M.Marble)
		B:Deco("Block", "Frieze", V(5.2, 1.2, 190), CFrame.new(x, L.PillarH + 2.6, 0), C.Gold, M.Metal)
		B:Deco("Block", "EntCornice", V(6.4, 0.8, 190), CFrame.new(x, L.EntTop - 0.4, 0), C.MarbleWarm, M.Marble)
		-- clerestory wall above, with gilded panels on the nave face
		if cutaway then
			continue
		end
		B:Solid("Block", "Clerestory", V(2, L.VaultY - L.EntTop, 202), CFrame.new(x, (L.VaultY + L.EntTop) / 2, 0), C.Plaster, M.Plaster)
		for k = 0, 10 do
			local z = -80 + k * 16
			B:Deco("Block", "Panel", V(0.3, 7, 10), CFrame.new(x - side * 1.1, 44, z), C.MarbleWarm, M.Marble, { Shadow = false })
			B:Deco("Block", "PanelInset", V(0.35, 5.6, 8.6), CFrame.new(x - side * 1.15, 44, z), C.Gold, M.Metal, { Shadow = false })
		end
	end
	B:Group(nil)
end

local function buildCeilings(B: MapKit.Builder)
	B:Group("Vault")
	-- aisle ceilings + transverse beams
	B:Solid("Block", "AisleCeilW", V(20, 2, 204), CFrame.new(-37.5, L.AisleCeil + 1, 0), C.Plaster, M.Plaster)
	B:Solid("Block", "AisleCeilE", V(24, 2, 204), CFrame.new(39.5, L.AisleCeil + 1, 0), C.Plaster, M.Plaster)
	for k = 0, L.Pillars - 1 do
		local z = pillarZ(k)
		B:Deco("Block", "AisleBeamW", V(19, 1.4, 1.6), CFrame.new(-37.5, L.AisleCeil - 0.7, z), C.MarbleWarm, M.Marble)
		B:Deco("Block", "AisleBeamE", V(22, 1.4, 1.6), CFrame.new(38.5, L.AisleCeil - 0.7, z), C.MarbleWarm, M.Marble)
	end
	-- barrel vault over the nave: long curved boards + gilded transverse ribs over every pillar pair
	local R = L.ArcadeX
	local segs = 14
	for i = 0, segs - 1 do
		local a0 = math.rad(i * 180 / segs)
		local a1 = math.rad((i + 1) * 180 / segs)
		local am = (a0 + a1) / 2
		local chord = 2 * (R + 0.8) * math.sin((a1 - a0) / 2) + 0.4
		local pos = V(math.cos(am) * (R + 0.8), L.VaultY + math.sin(am) * (R + 0.8), 0)
		local cf = CFrame.fromMatrix(pos, V(-math.sin(am), math.cos(am), 0), V(-math.cos(am), -math.sin(am), 0), V(0, 0, 1))
		local shade = if i % 2 == 0 then C.Plaster else MapKit.Shade(C.Plaster, -0.05)
		B:Solid("Block", "VaultBoard", V(chord, 1.6, 204), cf, shade, M.Plaster)
	end
	for k = 0, L.Pillars - 1 do
		B:Arch("Rib" .. k, CFrame.new(0, L.VaultY, pillarZ(k)), 2 * R - 1.2, 1.4, 2.2, C.MarbleWarm, {
			Material = M.Marble,
			Segments = 12,
			KeystoneColor = C.Gold,
		})
	end
	-- ridge beam
	B:Deco("Block", "Ridge", V(2.4, 1.2, 202), CFrame.new(0, L.VaultY + R - 0.6, 0), C.Gold, M.Metal)
	B:Group(nil)
end

local function buildNorthEnd(B: MapKit.Builder, cutaway: boolean): number
	B:Group("NorthEnd")
	local lights = 0
	local wallZ = L.NorthZ
	local faceZ = wallZ + 1
	B:Solid("Block", "NorthWall", V(102, L.VaultY, 2), CFrame.new(2, L.VaultY / 2, wallZ), C.Plaster, M.Plaster)
	if not cutaway then
		-- tympanum closing the vault
		local c = V(0, L.VaultY, wallZ)
		for i = 0, 9 do
			local a0, a1 = math.rad(i * 18), math.rad((i + 1) * 18)
			B:Triangle("Geometry", "Tympanum", c, c + V(math.cos(a0) * 30, math.sin(a0) * 30, 0), c + V(math.cos(a1) * 30, math.sin(a1) * 30, 0), 2, C.Plaster, M.Plaster)
		end
	end
	-- rose window: rings of coloured triangles with lead ribs, glowing from within
	local rose = CFrame.new(0, 36, faceZ + 0.25)
	local R = 11
	local n = 16
	for i = 0, n - 1 do
		local a0, a1 = math.rad(i * 360 / n), math.rad((i + 1) * 360 / n)
		local p0 = rose * V(math.cos(a0) * R, math.sin(a0) * R, 0)
		local p1 = rose * V(math.cos(a1) * R, math.sin(a1) * R, 0)
		local q0 = rose * V(math.cos(a0) * R * 0.55, math.sin(a0) * R * 0.55, 0)
		local q1 = rose * V(math.cos(a1) * R * 0.55, math.sin(a1) * R * 0.55, 0)
		local outer = ROSE_OUTER[(i % #ROSE_OUTER) + 1]
		local inner = if i % 2 == 0 then rgb(196, 140, 44) else rgb(160, 26, 40)
		B:Triangle("Decor", "RoseOuter", p0, p1, q0, 0.12, outer, M.Neon, { Transparency = 0.25, Shadow = false })
		B:Triangle("Decor", "RoseOuterB", p1, q1, q0, 0.12, outer, M.Neon, { Transparency = 0.25, Shadow = false })
		B:Triangle("Decor", "RoseInner", rose.Position, q0, q1, 0.12, inner, M.Neon, { Transparency = 0.2, Shadow = false })
		B:Rod("Decor", "RoseRib", rose * V(0, 0, 0.1), rose * V(math.cos(a0) * R, math.sin(a0) * R, 0.1), 0.35, C.Lead, M.Metal, { Shadow = false })
	end
	B:Arch("RoseRimTop", rose * CFrame.new(0, 0, 0.2), 2 * R, 1.2, 1, C.Gold, { Material = M.Metal, Segments = 12, Keystone = false })
	B:Arch("RoseRimBottom", rose * CFrame.new(0, 0, 0.2) * CFrame.Angles(0, 0, math.pi), 2 * R, 1.2, 1, C.Gold, { Material = M.Metal, Segments = 12, Keystone = false })
	B:Part("Decor", "Cylinder", "RoseBoss", V(0.3, 5.4, 5.4), CFrame.new(rose.Position + V(0, 0, 0.3)) * CFrame.Angles(0, math.pi / 2, 0), C.Gold, M.Metal, { Shadow = false })
	B:Heart("Decor", "RoseHeart", rose * CFrame.new(0, 0, 0.55) * CFrame.Angles(0, math.pi, 0), 2.2, 0.2, rgb(255, 36, 60), M.Neon, { Shadow = false })
	B:Light("Surface", CFrame.new(0, 36, faceZ + 1.2), {
		Name = "RoseLight",
		Size = V(16, 16, 0.2),
		Face = Enum.NormalId.Back, -- towards +Z (into the hall)
		Brightness = 1.4,
		Range = 44,
		Angle = 70,
		Color = rgb(255, 190, 140),
	})
	lights += 1
	-- great banners flanking the rose window
	for _, side in { -1, 1 } do
		B:Banner("GreatBanner", CFrame.new(side * 19, 47, faceZ + 0.3) * CFrame.Angles(0, math.pi, 0), 8, 28, {
			Color = C.Crimson,
			Trim = C.Gold,
			Emblem = "Heart",
			EmblemColor = rgb(255, 214, 110),
		})
	end
	-- dais: platform, gold edge, steps, runner on the steps
	local top = L.DaisTop
	local front = L.DaisFront
	local depth = front - faceZ
	B:Solid("Block", "Dais", V(40, top, depth), CFrame.new(0, top / 2, (front + faceZ) / 2), C.MarbleWarm, M.Marble)
	B:Floor("DaisTop", V(0, top, (front + faceZ) / 2), 39, depth - 0.6, {
		Color = C.FloorLight,
		Material = M.Marble,
		Thickness = 0.4,
		Pattern = "Checker",
		Tile = 4,
		Color2 = C.FloorDark,
		Collide = true,
	})
	for _, x in { -20, 20 } do
		B:Deco("Block", "DaisEdge", V(0.6, top + 0.2, depth), CFrame.new(x, top / 2 + 0.1, (front + faceZ) / 2), C.Gold, M.Metal)
	end
	B:Stairs("DaisSteps", CFrame.new(0, 0, front + 4), 40, top, 4, {
		Steps = 4,
		Color = C.Marble,
		Nose = C.Gold,
		Material = M.Marble,
	})
	for i = 1, 4 do
		B:Deco("Block", "StepRunner", V(10, 0.06, 1.0), CFrame.new(0, i * 0.75 + 0.03, front + 4 - (i - 0.5)), C.Crimson, M.Fabric, { Shadow = false })
	end
	-- the Judge's bench
	local benchZ = -93
	B:Solid("Block", "Bench", V(24, 5.4, 4), CFrame.new(0, top + 2.7, benchZ), C.Walnut, M.Wood)
	B:Deco("Block", "BenchTop", V(25, 0.5, 5.2), CFrame.new(0, top + 5.65, benchZ + 0.3), C.WalnutDark, M.Wood)
	B:Deco("Block", "BenchPlinth", V(25, 0.8, 5), CFrame.new(0, top + 0.4, benchZ + 0.2), C.WalnutDark, M.Wood)
	for i = -1, 1 do
		B:Deco("Block", "BenchPanel", V(6.6, 3.2, 0.2), CFrame.new(i * 7.6, top + 2.8, benchZ + 2.05), C.GoldDark, M.Metal, { Shadow = false })
		B:Deco("Block", "BenchPanelIn", V(6, 2.6, 0.24), CFrame.new(i * 7.6, top + 2.8, benchZ + 2.08), MapKit.Shade(C.Walnut, 0.08), M.Wood, { Shadow = false })
	end
	B:Heart("Decor", "BenchHeart", CFrame.new(0, top + 2.9, benchZ + 2.25), 1.5, 0.2, rgb(220, 26, 46), M.Neon, { Shadow = false })
	-- high-backed chair with a gold star crest
	B:Solid("Block", "ChairSeat", V(5, 2.4, 4), CFrame.new(0, top + 1.2, benchZ - 4.5), C.CrimsonDark, M.Fabric)
	B:Solid("Block", "ChairBack", V(6, 13, 1.2), CFrame.new(0, top + 6.5, benchZ - 6.8), C.Walnut, M.Wood)
	B:Deco("Block", "ChairCushion", V(4.4, 10, 0.3), CFrame.new(0, top + 7, benchZ - 6.1), C.Crimson, M.Fabric, { Shadow = false })
	B:Star("Decor", "ChairStar", CFrame.new(0, top + 15.2, benchZ - 6.8), 2.2, 0.95, 0.5, C.Gold, M.Metal)
	-- bone gavel and candelabras on the bench
	B:Bones("Gavel", CFrame.new(5, top + 6.2, benchZ + 0.6), { Length = 2.4, Thickness = 0.3 })
	for _, x in { -10.5, 10.5 } do
		B:Deco("Cylinder", "CandelabraStem", V(2, 0.3, 0.3), CFrame.new(x, top + 6.9, benchZ) * CFrame.Angles(0, 0, math.pi / 2), C.Gold, M.Metal)
		B:Deco("Block", "CandelabraArm", V(2.4, 0.2, 0.2), CFrame.new(x, top + 7.8, benchZ), C.Gold, M.Metal)
		for _, dx in { -1.1, 0, 1.1 } do
			B:Lamp("Candle", V(x + dx, top + 7.9, benchZ), { Style = "Candle", Height = 0.9, Glow = C.Flame, NoLight = true })
		end
	end
	B:Light("Point", V(0, top + 9, benchZ + 1), { Name = "BenchLight", Brightness = 1.6, Range = 22, Color = C.Lamp })
	lights += 1
	-- skull statues guarding the dais + braziers at the foot of the steps
	for _, side in { -1, 1 } do
		B:SkullStatue("JudgeStatue", V(side * 16.5, top, -91), { Facing = V(0, 0, 1), Color = C.Marble, Scale = 0.85 })
		local l = B:Lamp("Brazier", V(side * 13, 0, front + 7), {
			Style = "Brazier",
			Height = 3.6,
			Metal = C.GoldDark,
			Glow = C.Flame,
			LightColor = C.Lamp,
			Brightness = 1.8,
			Range = 24,
		})
		if l then
			lights += 1
		end
	end
	B:Group(nil)
	return lights
end

local function buildSouthEnd(B: MapKit.Builder, cutaway: boolean): number
	B:Group("SouthEnd")
	local lights = 0
	local wallZ = L.SouthZ
	local faceZ = wallZ - 1
	B:Solid("Block", "SouthWall", V(102, L.VaultY, 2), CFrame.new(2, L.VaultY / 2, wallZ), C.Plaster, M.Plaster)
	if not cutaway then
		local c = V(0, L.VaultY, wallZ)
		for i = 0, 9 do
			local a0, a1 = math.rad(i * 18), math.rad((i + 1) * 18)
			B:Triangle("Geometry", "Tympanum", c, c + V(math.cos(a0) * 30, math.sin(a0) * 30, 0), c + V(math.cos(a1) * 30, math.sin(a1) * 30, 0), 2, C.Plaster, M.Plaster)
		end
	end
	-- great doors in an arched portal (closed; decorative)
	local doorW, doorH = 14, 22
	B:Deco("Block", "DoorL", V(doorW / 2 - 0.1, doorH, 0.8), CFrame.new(-doorW / 4, doorH / 2, faceZ - 0.4), C.Walnut, M.WoodPlanks)
	B:Deco("Block", "DoorR", V(doorW / 2 - 0.1, doorH, 0.8), CFrame.new(doorW / 4, doorH / 2, faceZ - 0.4), C.Walnut, M.WoodPlanks)
	for _, x in { -doorW / 4, doorW / 4 } do
		for _, y in { 5, 11, 17 } do
			B:Deco("Block", "DoorBand", V(doorW / 2 - 0.6, 0.5, 0.2), CFrame.new(x, y, faceZ - 0.9), C.GoldDark, M.Metal, { Shadow = false })
		end
		B:Deco("Cylinder", "DoorRing", V(0.3, 1.6, 1.6), CFrame.new(x + (if x < 0 then 2.2 else -2.2), 9.5, faceZ - 1.0) * CFrame.Angles(0, math.pi / 2, 0), C.Gold, M.Metal, { Shadow = false })
	end
	for _, side in { -1, 1 } do
		B:Deco("Block", "PortalPost", V(2.6, doorH, 1.6), CFrame.new(side * (doorW / 2 + 1.3), doorH / 2, faceZ - 0.8), C.MarbleWarm, M.Marble)
	end
	B:Arch("PortalArch", CFrame.new(0, doorH, faceZ - 0.8), doorW + 2.6, 2.6, 1.6, C.MarbleWarm, { Material = M.Marble, Segments = 10 })
	-- tympanum fill above the doors (gold sunburst)
	for i = 0, 7 do
		local a0, a1 = math.rad(i * 22.5), math.rad((i + 1) * 22.5)
		local c = V(0, doorH, faceZ - 0.3)
		local r = doorW / 2 + 0.1
		B:Triangle("Decor", "DoorFan", c, c + V(math.cos(a0) * r, math.sin(a0) * r, 0), c + V(math.cos(a1) * r, math.sin(a1) * r, 0), 0.2, if i % 2 == 0 then C.Gold else C.GoldDark, M.Metal, { Shadow = false })
	end
	-- the clock of the hour of judgement
	local clock = CFrame.new(0, 40, faceZ - 0.4) -- faces the hall (-Z); local +X = the viewer's left
	B:Part("Decor", "Cylinder", "ClockRim", V(0.6, 15, 15), clock * CFrame.Angles(0, math.pi / 2, 0), C.Gold, M.Metal)
	B:Part("Decor", "Cylinder", "ClockFace", V(0.7, 13.4, 13.4), clock * CFrame.Angles(0, math.pi / 2, 0), rgb(248, 236, 206), M.Marble)
	for h = 0, 11 do
		local a = math.rad(h * 30)
		local len = if h % 3 == 0 then 1.6 else 0.9
		B:Deco("Block", "ClockTick", V(0.35, len, 0.2), clock * CFrame.new(math.sin(a) * 5.6, math.cos(a) * 5.6, -0.45) * CFrame.Angles(0, 0, -a), C.Walnut, M.Wood, { Shadow = false })
	end
	-- hands at a quarter to midnight
	B:Deco("Block", "ClockHour", V(0.6, 3.8, 0.2), clock * CFrame.new(0.3, 1.8, -0.55) * CFrame.Angles(0, 0, math.rad(-8)), C.GoldDark, M.Metal, { Shadow = false })
	B:Deco("Block", "ClockMinute", V(0.4, 5.4, 0.2), clock * CFrame.new(2.6, 0, -0.6) * CFrame.Angles(0, 0, math.rad(-90)), C.GoldDark, M.Metal, { Shadow = false })
	B:Deco("Ball", "ClockPin", V(0.8, 0.8, 0.8), clock * CFrame.new(0, 0, -0.7), C.Gold, M.Metal, { Shadow = false })
	-- door lanterns
	for _, side in { -1, 1 } do
		local l = B:Lamp("DoorLamp", V(side * 11.5, 12, faceZ - 0.2), {
			Style = "Wall",
			Facing = V(0, 0, -1),
			Metal = C.GoldDark,
			Glow = C.Flame,
			LightColor = C.Lamp,
			Brightness = 1.5,
			Range = 20,
		})
		if l then
			lights += 1
		end
	end
	B:Group(nil)
	return lights
end

local function buildPews(B: MapKit.Builder)
	B:Group("Pews")
	for _, z in { 6, 14, 22, 30 } do
		for _, side in { -1, 1 } do
			local xc = side * 15
			B:Solid("Block", "PewSeat", V(12, 0.5, 2.4), CFrame.new(xc, 1.9, z), C.Walnut, M.Wood)
			B:Solid("Block", "PewBack", V(12, 3.2, 0.45), CFrame.new(xc, 3.6, z + 1.25) * CFrame.Angles(math.rad(-6), 0, 0), C.Walnut, M.Wood)
			B:Deco("Block", "PewRail", V(12.2, 0.35, 0.7), CFrame.new(xc, 5.3, z + 1.4), C.WalnutDark, M.Wood, { Shadow = false })
			for _, ex in { -6.2, 6.2 } do
				B:Solid("Block", "PewEnd", V(0.5, 4.6, 3.2), CFrame.new(xc + ex, 2.3, z + 0.3), C.WalnutDark, M.Wood)
				B:Deco("Cylinder", "PewEndCap", V(0.6, 1.4, 1.4), CFrame.new(xc + ex, 4.7, z + 1.1), C.Gold, M.Metal, { Shadow = false })
			end
		end
	end
	B:Group(nil)
end

local function buildNaveDressing(B: MapKit.Builder, cutaway: boolean): number
	local lights = 0
	B:Group("Chandeliers")
	for _, z in { -56, -24, 8, 40, 72 } do
		local l = B:Chandelier("Chandelier", V(0, L.VaultY + L.ArcadeX - 1, z), {
			Drop = 46,
			Radius = 4.6,
			Arms = 10,
			Metal = C.Gold,
			Glow = C.Flame,
			LightColor = C.Lamp,
			Brightness = 1.7,
			Range = 40,
		})
		if l then
			lights += 1
		end
	end
	B:Group("Banners")
	for _, side in (if cutaway then {} else { -1, 1 }) :: { number } do
		for k = 0, 10, 2 do
			local z = -80 + k * 16
			local x = side * (L.ArcadeX - 1.35)
			local cf = MapKit.Facing(V(x, L.VaultY - 1, z), V(0, L.VaultY - 1, z))
			B:Banner("NaveBanner", cf, 5, 10, {
				Color = if side < 0 then C.Crimson else C.Navy,
				Trim = C.Gold,
				Emblem = if side < 0 then "Heart" else "Delta",
				EmblemColor = rgb(255, 210, 110),
			})
		end
	end
	B:Group(nil)
	return lights
end

-- Outside: a lower sun terrace beyond the windows and a hazy skyline (seen through the glass).
local function buildOutside(B: MapKit.Builder)
	B:Group("Outside")
	B:Solid("Block", "Terrace", V(18, 2, 204), CFrame.new(L.WestX - 10, -3, 0), C.MarbleShade, M.Marble)
	B:Railing("TerraceRail", V(L.WestX - 18, -2, -100), V(L.WestX - 18, -2, 100), {
		Height = 2.8,
		Spacing = 10,
		BalusterGap = 2.5,
		Color = C.MarbleWarm,
		Material = M.Marble,
		Collide = false,
	})
	-- underside of the building (it floats above the golden haze)
	B:Deco("Block", "Underside", V(118, 10, 210), CFrame.new(-5, -9, 0), rgb(150, 112, 80), M.Slate)
	B:Deco("Block", "Underside2", V(90, 14, 170), CFrame.new(0, -20, 0), rgb(120, 88, 64), M.Slate)
	local rng = B.Rng
	for i = 1, 9 do
		local z = -220 + i * 44 + rng:Number(-10, 10)
		local x = -230 - rng:Number(0, 120)
		local h = rng:Number(40, 110)
		local w = rng:Number(10, 20)
		local base = V(x, -60, z)
		local shade = MapKit.Shade(C.Skyline, rng:Number(-0.12, 0.06))
		B:Deco("Block", "Spire", V(w, h, w), CFrame.new(base + V(0, h / 2, 0)), shade, M.Slate, { Shadow = false })
		B:Cone("Decor", "SpireRoof", base + V(0, h, 0), w * 1.4, w * 0.75, 4, MapKit.Shade(shade, -0.15), M.Slate, { Phase = 45, Shadow = false })
	end
	B:Group(nil)
end

-- MapInfo -------------------------------------------------------------------------------------------------

function HallOfVerdicts.Build(seed: number?, opts: { [string]: any }?): MapInfo
	local o = opts or {}
	local cutaway = o.Cutaway == true
	local B = MapKit.new("HallOfVerdicts", { Seed = seed or 1 })
	buildFloor(B)
	local lights = 0
	lights += buildWestWall(B)
	lights += buildEastWall(B)
	buildColonnades(B, cutaway)
	if not cutaway then
		buildCeilings(B)
	end
	lights += buildNorthEnd(B, cutaway)
	lights += buildSouthEnd(B, cutaway)
	buildPews(B)
	lights += buildNaveDressing(B, cutaway)
	buildOutside(B)

	-- objectives and spawns
	local saveStyle = { Inner = C.CrimsonDark, InnerMaterial = M.Marble }
	local saves = {
		B:SavePoint(1, V(18, 0, 48), saveStyle),
		B:SavePoint(2, V(-38, 0, 0), saveStyle),
		B:SavePoint(3, V(16, 0, -50), saveStyle),
	}
	local center = V(0, 0, 0)
	local humanSpawns: { CFrame } = {}
	local i = 0
	for _, z in { 84, 91 } do
		for _, x in { -20, -12, -4, 4, 12, 20 } do
			i += 1
			table.insert(humanSpawns, B:SpawnPoint("Human", i, MapKit.Facing(V(x, 0, z), V(x * 0.3, 0, 0))))
		end
	end
	local monsterSpawn = B:SpawnPoint("Monster", 1, MapKit.Facing(V(0, L.DaisTop, -84), V(0, L.DaisTop, 0)))
	B:Marker("Center", CFrame.new(center + V(0, 0.5, 0)))
	B:KillFloor(L.KillY, 400)
	local _ = lights
	B:Finish(HallOfVerdicts.Id)

	return {
		Id = HallOfVerdicts.Id,
		Model = B.Model,
		HumanSpawns = humanSpawns,
		MonsterSpawn = monsterSpawn,
		SavePoints = saves,
		Center = center,
		Radius = 100,
		KillY = L.KillY,
		IntroPath = {
			MapKit.LookAt(V(0, 44, 96), V(0, 8, -40)),
			MapKit.LookAt(V(-36, 22, 52), V(-10, 6, 0)),
			MapKit.LookAt(V(-24, 9, -14), V(8, 4, -56)),
			MapKit.LookAt(V(10, 8, -58), V(0, 6, -86)),
			MapKit.LookAt(V(0, 9, -66), V(0, 7, -88)),
		},
		Preset = HallOfVerdicts.Preset,
		FinalPreset = HallOfVerdicts.FinalPreset,
		Music = HallOfVerdicts.Music,
	}
end

return HallOfVerdicts
