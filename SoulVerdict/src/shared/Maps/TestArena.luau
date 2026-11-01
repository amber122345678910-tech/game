--!strict
-- Maps/TestArena: "The Golden Ring" — a floating marble arena used for tests, solo practice and as the
-- fallback for any missing map (and for the lobby until Maps/Lobby.luau exists). Lune-safe.
-- Look: Ø160 marble disc with gold inlay rings and a SOUL-heart emblem, a low rim, 8 lantern pillars
-- (cover + warm lights), 3 raised SAVE daises, a stepped rock underside (floating island) and a distant
-- colonnade of giant arches whose feet vanish into the void.
-- Built around the world origin (floor top at y = 0); MapService offsets it for placement.
--
-- API (Types.MapDef): TestArena.Id/Name/Desc/Preset/FinalPreset/Music, TestArena.Build(seed?) -> MapInfo
-- MapInfo extras: DummySpawns (4 ground CFrames, used when this arena doubles as the lobby).
-- Every spawn CFrame is a GROUND point whose LookVector is the facing direction.

local Types = require(script.Parent.Parent.Types)

type MapInfo = Types.MapInfo
type MapDef = Types.MapDef

local TestArena = {}

TestArena.Id = "TestArena"
TestArena.Name = { en = "Test Arena", ru = "Тестовая арена" }
TestArena.Desc = {
	en = "A floating golden ring for trials and testing.",
	ru = "Парящее золотое кольцо для испытаний и тестов.",
}
TestArena.Preset = "GoldenHall"
TestArena.FinalPreset = "GoldenHallFinal"
TestArena.Music = "Map_HallOfVerdicts"

-- Layout constants (studs) --------------------------------------------------------------------------
local FLOOR_DIAMETER = 160
local PLAY_RADIUS = 74 -- Collapse starts here (inside the rim)
local RIM_RADIUS = 79
local PILLAR_RADIUS = 60
local SAVE_RADIUS = 40
local SPAWN_RADIUS = 54
local KILL_Y = -60

local COLORS = {
	Marble = Color3.fromRGB(231, 221, 198),
	MarbleWarm = Color3.fromRGB(222, 205, 172),
	MarbleDark = Color3.fromRGB(190, 172, 140),
	Gold = Color3.fromRGB(214, 168, 72),
	GoldDark = Color3.fromRGB(146, 106, 40),
	Stone = Color3.fromRGB(122, 106, 88),
	StoneDark = Color3.fromRGB(78, 66, 56),
	Heart = Color3.fromRGB(196, 22, 40),
	Flame = Color3.fromRGB(255, 178, 92),
	Lamp = Color3.fromRGB(255, 192, 120),
	Column = Color3.fromRGB(208, 194, 166),
}

-- Part helpers: PartKit when available (shared visual defaults), plain Instance.new otherwise ---------
type PartOpts = {
	Material: Enum.Material?,
	Collide: boolean?, -- default true
	Query: boolean?, -- default = Collide
	Shadow: boolean?, -- default true
	Transparency: number?,
	Reflectance: number?,
}

local partKitCache: any = nil
local function partKit(): any
	if partKitCache == nil then
		partKitCache = false
		local shared: any = script.Parent.Parent
		local rigs = shared:FindFirstChild("Rigs")
		local module = rigs and rigs:FindFirstChild("PartKit")
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" and type((result :: any).new) == "function" then
				local okKit, kit = pcall((result :: any).new, { Anchored = true })
				if okKit and type(kit) == "table" and type(kit.Part) == "function" then
					partKitCache = kit
				end
			end
		end
	end
	return if partKitCache == false then nil else partKitCache
end

local function makePart(
	parent: Instance,
	name: string,
	shape: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	o: PartOpts?
): BasePart
	local opts: PartOpts = o or {}
	local collide = if opts.Collide == nil then true else opts.Collide
	local query = if opts.Query == nil then collide else opts.Query
	local shadow = if opts.Shadow == nil then true else opts.Shadow
	local kit = partKit()
	if kit then
		local ok, part = pcall(kit.Part, parent, name, shape, size, cf, color, {
			Material = opts.Material,
			Transparency = opts.Transparency,
			Reflectance = opts.Reflectance,
			Anchored = true,
			CanCollide = collide,
			CanQuery = query,
			CanTouch = false,
			Massless = false,
			CastShadow = shadow,
			Role = "Detail",
		})
		if ok and typeof(part) == "Instance" then
			return part :: any
		end
	end
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		else
			p.Shape = Enum.PartType.Block
		end
		part = p
	end
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = opts.Material or Enum.Material.SmoothPlastic
	part.Transparency = opts.Transparency or 0
	part.Reflectance = opts.Reflectance or 0
	part.Anchored = true
	part.CanCollide = collide
	part.CanQuery = query
	part.CanTouch = false
	part.CastShadow = shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's X axis to world up

-- Horizontal disc (cylinder standing up) centred at `center`.
local function disc(
	parent: Instance,
	name: string,
	diameter: number,
	thickness: number,
	center: Vector3,
	color: Color3,
	o: PartOpts?
): BasePart
	return makePart(
		parent,
		name,
		"Cylinder",
		Vector3.new(thickness, diameter, diameter),
		CFrame.new(center) * UPRIGHT,
		color,
		o
	)
end

-- Vertical cylinder whose bottom face sits at `base`.
local function column(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	base: Vector3,
	color: Color3,
	o: PartOpts?
): BasePart
	return disc(parent, name, diameter, height, base + Vector3.new(0, height / 2, 0), color, o)
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, o: PartOpts?): BasePart
	return makePart(parent, name, "Block", size, cf, color, o)
end

local function light(part: BasePart, brightness: number, range: number, color: Color3, shadows: boolean)
	local l = Instance.new("PointLight")
	l.Brightness = brightness
	l.Range = range
	l.Color = color
	l.Shadows = shadows
	l.Parent = part
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Point on the floor circle; angle in degrees, 0 = +X, 90 = +Z (towards the human side).
local function polar(radius: number, angleDeg: number, y: number?): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a) * radius, y or 0, math.sin(a) * radius)
end

-- CFrame at `position` whose LookVector points at `target` (built with fromMatrix: identical in Roblox
-- and in Lune, whose CFrame.lookAt is inverted).
local function lookAt(position: Vector3, target: Vector3): CFrame
	local delta = target - position
	if delta.Magnitude < 1e-6 then
		return CFrame.new(position)
	end
	local look = delta.Unit
	local up = Vector3.new(0, 1, 0)
	if math.abs(look:Dot(up)) > 0.999 then
		up = Vector3.new(0, 0, -1)
	end
	local right = look:Cross(up).Unit
	local trueUp = right:Cross(look).Unit
	return CFrame.fromMatrix(position, right, trueUp, -look)
end

-- Level (yaw-only) frame at `position` facing `target`.
local function facing(position: Vector3, target: Vector3): CFrame
	return lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

-- Builders ------------------------------------------------------------------------------------------

local function buildFloor(model: Model)
	local f = folder(model, "Floor")
	-- walkable slab: top face at y = 0
	disc(f, "Slab", FLOOR_DIAMETER, 4, Vector3.new(0, -2, 0), COLORS.Marble, { Material = Enum.Material.Marble })
	-- inlay rings: stacked thin discs (largest first, each a bit higher) -> gold rings on marble
	type Layer = { Diameter: number, Color: Color3, Material: Enum.Material }
	local layers: { Layer } = {
		{ Diameter = 2 * 71.2, Color = COLORS.Gold, Material = Enum.Material.Metal },
		{ Diameter = 2 * 69.8, Color = COLORS.MarbleWarm, Material = Enum.Material.Marble },
		{ Diameter = 2 * 46.7, Color = COLORS.Gold, Material = Enum.Material.Metal },
		{ Diameter = 2 * 45.5, Color = COLORS.Marble, Material = Enum.Material.Marble },
		{ Diameter = 2 * 24.6, Color = COLORS.Gold, Material = Enum.Material.Metal },
		{ Diameter = 2 * 23.6, Color = COLORS.MarbleWarm, Material = Enum.Material.Marble },
		{ Diameter = 2 * 9.6, Color = COLORS.Gold, Material = Enum.Material.Metal },
		{ Diameter = 2 * 8.8, Color = COLORS.MarbleDark, Material = Enum.Material.Marble },
	}
	for i, layer in layers do
		disc(f, "Inlay" .. i, layer.Diameter, 0.04, Vector3.new(0, 0.01 + i * 0.022, 0), layer.Color, {
			Material = layer.Material,
			Collide = false,
			Query = false,
			Shadow = false,
		})
	end
	local topY = 0.01 + (#layers + 1) * 0.022
	-- radial gold spokes between the inner and middle rings
	for k = 0, 7 do
		local a = k * 45
		local mid = polar(35, a, topY)
		box(f, "Spoke" .. k, Vector3.new(0.5, 0.04, 20), facing(mid, Vector3.new(0, topY, 0)), COLORS.Gold, {
			Material = Enum.Material.Metal,
			Collide = false,
			Query = false,
			Shadow = false,
		})
	end
	-- the SOUL heart emblem (square rotated 45 degrees + two lobes), point towards the human side (+Z)
	local s = 7.5
	local h = s / math.sqrt(2)
	local heartY = topY + 0.03
	box(
		f,
		"HeartBody",
		Vector3.new(s, 0.06, s),
		CFrame.new(0, heartY, 0) * CFrame.Angles(0, math.rad(45), 0),
		COLORS.Heart,
		{
			Material = Enum.Material.Neon,
			Collide = false,
			Query = false,
			Shadow = false,
		}
	)
	for _, side in { -1, 1 } do
		disc(
			f,
			if side < 0 then "HeartLobeL" else "HeartLobeR",
			s,
			0.06,
			Vector3.new(side * h / 2, heartY, -h / 2),
			COLORS.Heart,
			{
				Material = Enum.Material.Neon,
				Collide = false,
				Query = false,
				Shadow = false,
			}
		)
	end
	-- tiny gold studs around the emblem
	for k = 0, 11 do
		local p = polar(12.5, k * 30 + 15, topY + 0.05)
		disc(
			f,
			"Stud" .. k,
			0.9,
			0.1,
			p,
			COLORS.Gold,
			{ Material = Enum.Material.Metal, Collide = false, Query = false, Shadow = false }
		)
	end
	-- low rim: 40 marble segments + gold caps (jumpable, stops accidental walk-offs)
	local count = 40
	local segLen = 2 * math.pi * RIM_RADIUS / count + 0.35
	for i = 0, count - 1 do
		local a = (i + 0.5) * 360 / count
		local base = polar(RIM_RADIUS, a, 0)
		local cf = facing(base, Vector3.new(0, 0, 0))
		box(
			f,
			"Rim" .. i,
			Vector3.new(segLen, 3, 2.4),
			cf * CFrame.new(0, 1.5, 0),
			COLORS.MarbleWarm,
			{ Material = Enum.Material.Marble }
		)
		box(f, "RimCap" .. i, Vector3.new(segLen, 0.5, 2.9), cf * CFrame.new(0, 3.25, 0), COLORS.Gold, {
			Material = Enum.Material.Metal,
			Shadow = false,
		})
	end
	-- outer lip below the rim (thin gold band on the slab edge)
	disc(f, "EdgeBand", FLOOR_DIAMETER + 1.2, 0.8, Vector3.new(0, -0.7, 0), COLORS.GoldDark, {
		Material = Enum.Material.Metal,
		Collide = false,
		Query = false,
		Shadow = false,
	})
end

local function buildPillars(model: Model)
	local f = folder(model, "Pillars")
	for k = 0, 7 do
		local a = 22.5 + k * 45
		local p = polar(PILLAR_RADIUS, a, 0)
		local cf = facing(p, Vector3.new(0, 0, 0))
		local name = "Pillar" .. k
		box(
			f,
			name .. "_Plinth",
			Vector3.new(7, 1.4, 7),
			cf * CFrame.new(0, 0.7, 0),
			COLORS.MarbleDark,
			{ Material = Enum.Material.Marble }
		)
		column(
			f,
			name .. "_Base",
			5.8,
			1.2,
			p + Vector3.new(0, 1.4, 0),
			COLORS.Gold,
			{ Material = Enum.Material.Metal }
		)
		column(
			f,
			name .. "_Shaft",
			4.4,
			19,
			p + Vector3.new(0, 2.6, 0),
			COLORS.Column,
			{ Material = Enum.Material.Marble }
		)
		-- carved grooves read as vertical stripes
		for g = 0, 3 do
			local ga = math.rad(g * 90 + 45)
			local offset = Vector3.new(math.cos(ga) * 2.12, 0, math.sin(ga) * 2.12)
			box(
				f,
				name .. "_Groove" .. g,
				Vector3.new(0.35, 17, 0.35),
				CFrame.new(p + offset + Vector3.new(0, 12.1, 0)),
				COLORS.MarbleDark,
				{
					Material = Enum.Material.Marble,
					Collide = false,
					Query = false,
					Shadow = false,
				}
			)
		end
		column(
			f,
			name .. "_Ring",
			5.2,
			0.8,
			p + Vector3.new(0, 21.6, 0),
			COLORS.Gold,
			{ Material = Enum.Material.Metal }
		)
		box(
			f,
			name .. "_Capital",
			Vector3.new(7, 1.8, 7),
			cf * CFrame.new(0, 23.3, 0),
			COLORS.MarbleWarm,
			{ Material = Enum.Material.Marble }
		)
		box(
			f,
			name .. "_Abacus",
			Vector3.new(7.8, 0.6, 7.8),
			cf * CFrame.new(0, 24.5, 0),
			COLORS.Gold,
			{ Material = Enum.Material.Metal }
		)
		-- lantern flame on top: neon core + warm light
		local flame = makePart(
			f,
			name .. "_Flame",
			"Ball",
			Vector3.new(2.2, 2.2, 2.2),
			CFrame.new(p + Vector3.new(0, 26.2, 0)),
			COLORS.Flame,
			{
				Material = Enum.Material.Neon,
				Collide = false,
				Query = false,
				Shadow = false,
			}
		)
		light(flame, 1.8, 26, COLORS.Lamp, false)
		-- a second, low light so the floor around the pillar glows warm
		local foot = box(f, name .. "_Glow", Vector3.new(1, 0.2, 1), cf * CFrame.new(0, 1.5, -3.8), COLORS.Gold, {
			Material = Enum.Material.Neon,
			Collide = false,
			Query = false,
			Shadow = false,
		})
		light(foot, 0.6, 12, COLORS.Lamp, false)
	end
end

local function buildSaveDaises(model: Model): { Vector3 }
	local f = folder(model, "SaveDaises")
	local points: { Vector3 } = {}
	for i, a in { 270, 30, 150 } do
		local p = polar(SAVE_RADIUS, a, 0)
		disc(
			f,
			"Dais" .. i .. "_Step",
			13,
			0.4,
			p + Vector3.new(0, 0.2, 0),
			COLORS.GoldDark,
			{ Material = Enum.Material.Metal }
		)
		disc(
			f,
			"Dais" .. i .. "_Top",
			11.6,
			0.6,
			p + Vector3.new(0, 0.3, 0),
			COLORS.MarbleWarm,
			{ Material = Enum.Material.Marble }
		)
		disc(f, "Dais" .. i .. "_Star", 4, 0.08, p + Vector3.new(0, 0.63, 0), COLORS.Gold, {
			Material = Enum.Material.Metal,
			Collide = false,
			Query = false,
			Shadow = false,
		})
		table.insert(points, p + Vector3.new(0, 0.6, 0))
	end
	return points
end

local function buildUnderside(model: Model)
	local f = folder(model, "Underside")
	-- {diameter, thickness, centre y}
	local tiers: { { number } } = {
		{ 152, 6, -7 },
		{ 124, 8, -14 },
		{ 92, 10, -23 },
		{ 58, 12, -34 },
		{ 26, 12, -45 },
	}
	for i, t in tiers do
		local color = if i % 2 == 0 then COLORS.StoneDark else COLORS.Stone
		disc(f, "Tier" .. i, t[1], t[2], Vector3.new(0, t[3], 0), color, {
			Material = Enum.Material.Slate,
			Collide = false,
			Query = false,
		})
	end
	-- hanging crystal: a downward gold spike under the island
	column(
		f,
		"Keel",
		6,
		10,
		Vector3.new(0, -61, 0),
		COLORS.GoldDark,
		{ Material = Enum.Material.Metal, Collide = false, Query = false }
	)
	-- floating ruins: broken column drums drifting around the island (hand placed, deterministic, never
	-- in the play area). {position, {diameter, length}, tilt in degrees}
	local drums: { { Vector3 } } = {
		{ Vector3.new(104, -14, 22), Vector3.new(6, 9, 0), Vector3.new(12, 30, 70) },
		{ Vector3.new(-98, -24, -40), Vector3.new(7, 6, 0), Vector3.new(-8, 70, 20) },
		{ Vector3.new(30, -36, -112), Vector3.new(5, 7, 0), Vector3.new(20, 10, 95) },
		{ Vector3.new(-40, -10, 108), Vector3.new(6, 5, 0), Vector3.new(-14, 45, 10) },
		{ Vector3.new(88, -46, -78), Vector3.new(8, 11, 0), Vector3.new(6, -30, 60) },
		{ Vector3.new(-112, -38, 52), Vector3.new(7, 8, 0), Vector3.new(16, 110, 80) },
		{ Vector3.new(118, 12, -36), Vector3.new(4.5, 5, 0), Vector3.new(-20, 15, 35) },
		{ Vector3.new(-70, 8, -104), Vector3.new(5, 6, 0), Vector3.new(30, 60, 100) },
	}
	for i, d in drums do
		local rot = d[3]
		local cf = CFrame.new(d[1]) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		local diameter, length = d[2].X, d[2].Y
		local opts: PartOpts = { Material = Enum.Material.Marble, Collide = false, Query = false }
		-- the drum (cylinder axis = local X) + a gold band near one end + a chipped cap
		makePart(f, "Drum" .. i, "Cylinder", Vector3.new(length, diameter, diameter), cf, COLORS.Column, opts)
		makePart(
			f,
			"DrumBand" .. i,
			"Cylinder",
			Vector3.new(0.7, diameter + 0.5, diameter + 0.5),
			cf * CFrame.new(length / 2 - 1, 0, 0),
			COLORS.Gold,
			{
				Material = Enum.Material.Metal,
				Collide = false,
				Query = false,
				Shadow = false,
			}
		)
		makePart(
			f,
			"DrumChip" .. i,
			"Wedge",
			Vector3.new(diameter * 0.6, diameter * 0.45, diameter * 0.7),
			cf * CFrame.new(-length / 2 - diameter * 0.15, diameter * 0.12, 0) * CFrame.Angles(0, math.rad(90), 0),
			COLORS.MarbleDark,
			opts
		)
	end
end

local function buildColonnade(model: Model)
	local f = folder(model, "Colonnade")
	local count = 16
	local radius = 150
	local top = 74
	local bottom = -140
	local chord = 2 * radius * math.sin(math.pi / count)
	for k = 0, count - 1 do
		local a = k * 360 / count
		local p = polar(radius, a, 0)
		local opts: PartOpts = { Material = Enum.Material.Marble, Collide = false, Query = false }
		column(f, "Column" .. k, 9, top - bottom, Vector3.new(p.X, bottom, p.Z), COLORS.Column, opts)
		box(
			f,
			"Capital" .. k,
			Vector3.new(13, 4, 13),
			facing(p + Vector3.new(0, top + 2, 0), Vector3.new(0, top + 2, 0)),
			COLORS.MarbleWarm,
			opts
		)
		-- architrave beam to the next column
		local mid = polar(radius * math.cos(math.pi / count), a + 180 / count, top + 5.5)
		box(f, "Beam" .. k, Vector3.new(chord + 6, 3, 5), facing(mid, Vector3.new(0, mid.Y, 0)), COLORS.Gold, {
			Material = Enum.Material.Metal,
			Collide = false,
			Query = false,
		})
	end
end

-- MapInfo ---------------------------------------------------------------------------------------------

local function humanSpawns(): { CFrame }
	local spawns: { CFrame } = {}
	for i = 0, 6 do
		local a = 72 + i * 6 -- arc on the +Z side between two pillars
		local p = polar(SPAWN_RADIUS, a, 0)
		table.insert(spawns, facing(p, Vector3.new(0, 0, 0)))
	end
	return spawns
end

local function dummySpawns(): { CFrame }
	local spawns: { CFrame } = {}
	for _, a in { -30, -10, 10, 30 } do
		local p = polar(30, a, 0)
		table.insert(spawns, facing(p, Vector3.new(0, 0, 0)))
	end
	return spawns
end

function TestArena.Build(seed: number?): MapInfo
	local _ = seed -- the test arena is fully deterministic
	local model = Instance.new("Model")
	model.Name = "TestArena"
	buildFloor(model)
	buildPillars(model)
	local savePoints = buildSaveDaises(model)
	buildUnderside(model)
	buildColonnade(model)
	model:SetAttribute("MapId", TestArena.Id)
	model.WorldPivot = CFrame.new(0, 0, 0)

	local center = Vector3.new(0, 0, 0)
	local info: MapInfo = {
		Id = TestArena.Id,
		Model = model,
		HumanSpawns = humanSpawns(),
		MonsterSpawn = facing(Vector3.new(0, 0, -56), center),
		SavePoints = savePoints,
		Center = center,
		Radius = PLAY_RADIUS,
		KillY = KILL_Y,
		IntroPath = {
			lookAt(Vector3.new(0, 72, 150), Vector3.new(0, 0, 0)),
			lookAt(Vector3.new(118, 30, 34), Vector3.new(0, 6, -8)),
			lookAt(Vector3.new(12, 9, -34), Vector3.new(0, 5, -56)),
			lookAt(Vector3.new(0, 11, 80), Vector3.new(0, 5, 0)),
		},
		Preset = TestArena.Preset,
		FinalPreset = TestArena.FinalPreset,
		Music = TestArena.Music,
		DummySpawns = dummySpawns(),
	}
	return info
end

return TestArena
