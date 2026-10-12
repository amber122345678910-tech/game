--!nocheck
-- Генератор карты (Lune): пишет src/map/House.rbxmx и src/map/Lobby.rbxmx.
-- Запуск из корня репозитория: .tools/lune run tools/gen_map.luau
-- Контракт имён/атрибутов: docs/MapContract.md. Размеры: docs/GDD.md §3.
-- ВАЖНО: в Lune CFrame.lookAt работает неверно вдоль оси Z — используем только CFrame.Angles / CFrame.fromMatrix.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local UDim = roblox.UDim
local Font = roblox.Font

local Config = Loader.load("src/shared/Config")
local Locale = Loader.load("src/shared/Locale")

local LOBBY_ORIGIN = Config.Map.LobbyOrigin

local rad = math.rad
local M = Enum.Material

----------------------------------------------------------------------
-- Детерминированный ГПСЧ (LCG): карта не меняется между сборками
----------------------------------------------------------------------
local seed = 20251012
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function randRange(a: number, b: number): number
	return a + (b - a) * rand()
end
-- лёгкая вариация цвета (±amount по каждому каналу)
local function vary(c: Color3, amount: number?): Color3
	local a = amount or 0.04
	local function cl(v)
		return math.clamp(v + randRange(-a, a), 0, 1)
	end
	return Color3.new(cl(c.R), cl(c.G), cl(c.B))
end

----------------------------------------------------------------------
-- Палитра
----------------------------------------------------------------------
local C = {
	Siding = Color3.fromRGB(196, 190, 176),
	SidingDark = Color3.fromRGB(150, 144, 132),
	Trim = Color3.fromRGB(236, 232, 222),
	Roof = Color3.fromRGB(58, 56, 60),
	Brick = Color3.fromRGB(122, 74, 58),
	WallInt = Color3.fromRGB(214, 206, 188),
	WallInt2 = Color3.fromRGB(196, 200, 190),
	WallKid = Color3.fromRGB(178, 196, 214),
	WallBath = Color3.fromRGB(206, 220, 222),
	WallBasement = Color3.fromRGB(112, 110, 106),
	Ceiling = Color3.fromRGB(230, 228, 220),
	FloorWood = Color3.fromRGB(132, 96, 62),
	FloorWood2 = Color3.fromRGB(118, 86, 56),
	FloorTile = Color3.fromRGB(178, 176, 168),
	FloorTileBath = Color3.fromRGB(190, 200, 198),
	Carpet = Color3.fromRGB(96, 92, 110),
	Concrete = Color3.fromRGB(118, 116, 112),
	ConcreteDark = Color3.fromRGB(88, 88, 90),
	Asphalt = Color3.fromRGB(44, 44, 48),
	Sidewalk = Color3.fromRGB(140, 138, 132),
	Lawn = Color3.fromRGB(66, 92, 48),
	LawnDark = Color3.fromRGB(44, 62, 36),
	Ground = Color3.fromRGB(34, 40, 30),
	Dirt = Color3.fromRGB(78, 62, 44),
	Wood = Color3.fromRGB(140, 102, 66),
	WoodDark = Color3.fromRGB(86, 60, 40),
	WoodLight = Color3.fromRGB(184, 150, 104),
	Fence = Color3.fromRGB(160, 150, 130),
	Metal = Color3.fromRGB(120, 124, 130),
	MetalDark = Color3.fromRGB(62, 64, 70),
	Glass = Color3.fromRGB(150, 190, 210),
	GlassDark = Color3.fromRGB(20, 26, 36),
	Door = Color3.fromRGB(96, 60, 40),
	DoorInt = Color3.fromRGB(226, 220, 206),
	Fabric = Color3.fromRGB(90, 102, 126),
	Fabric2 = Color3.fromRGB(128, 72, 66),
	Sheet = Color3.fromRGB(222, 222, 230),
	Pillow = Color3.fromRGB(240, 238, 232),
	Mattress = Color3.fromRGB(200, 196, 190),
	Appliance = Color3.fromRGB(222, 222, 220),
	Trunk = Color3.fromRGB(92, 66, 44),
	Crown = Color3.fromRGB(54, 96, 46),
	Crown2 = Color3.fromRGB(70, 110, 52),
	Bush = Color3.fromRGB(48, 80, 42),
	Bulb = Color3.fromRGB(255, 232, 190),
	WarmLight = Color3.fromRGB(255, 214, 170),
	ColdLight = Color3.fromRGB(196, 214, 236),
	Neon = Color3.fromRGB(255, 180, 60),
	Red = Color3.fromRGB(200, 40, 40),
	Blue = Color3.fromRGB(40, 90, 220),
	Yellow = Color3.fromRGB(240, 200, 40),
	Van = Color3.fromRGB(118, 118, 120),
	Police = Color3.fromRGB(28, 30, 38),
	Skin = Color3.fromRGB(210, 170, 140),
	Shirt = Color3.fromRGB(70, 92, 120),
	Overalls = Color3.fromRGB(46, 58, 82),
}

----------------------------------------------------------------------
-- Базовые помощники
----------------------------------------------------------------------
local function part(props: { [string]: any }, parent: Instance?): Instance
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" then
			p[k] = v
		end
	end
	if parent then
		p.Parent = parent
	end
	return p
end

-- Декор: без коллизии (по умолчанию), без запросов и касаний
local function deco(props: { [string]: any }, parent: Instance?): Instance
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = if props.CastShadow == nil then false else props.CastShadow
	return part(props, parent)
end

-- Структура (стены, полы): коллизия и запросы включены, касания выключены
local function solid(props: { [string]: any }, parent: Instance?): Instance
	props.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	props.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	props.CanTouch = false
	props.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	return part(props, parent)
end

-- Мебель: CanCollide=true, CanQuery=true (за ней можно присесть), CanTouch=false
local function furn(props: { [string]: any }, parent: Instance?): Instance
	props.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	props.CanQuery = true
	props.CanTouch = false
	props.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	return part(props, parent)
end

-- Невидимый маркер (Nav, HidePoint, Rooms и т.п.)
local function marker(props: { [string]: any }, parent: Instance?): Instance
	props.Transparency = 1
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	props.Size = props.Size or Vector3.new(1, 1, 1)
	return part(props, parent)
end

local function cfYaw(x: number, y: number, z: number, yawDeg: number?): CFrame
	local cf = CFrame.new(x, y, z)
	if yawDeg and yawDeg ~= 0 then
		cf = cf * CFrame.Angles(0, rad(yawDeg), 0)
	end
	return cf
end

-- Коробка по центру/размеру
local function box(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material, kind: string?, extra: { [string]: any }?)
	local props: { [string]: any } = { Name = name, CFrame = cf, Size = size, Color = color, Material = material or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	if kind == "deco" then
		return deco(props, parent)
	elseif kind == "furn" then
		return furn(props, parent)
	else
		return solid(props, parent)
	end
end

-- Коробка по границам (x0..x1, y0..y1, z0..z1)
local function bbox(parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material, kind: string?, extra: { [string]: any }?)
	return box(parent, name, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, y1 - y0, z1 - z0), color, material, kind, extra)
end

local function folder(name: string, parent: Instance?): Instance
	local f = Instance.new("Folder")
	f.Name = name
	if parent then
		f.Parent = parent
	end
	return f
end

local function model(name: string, parent: Instance?, attrs: { [string]: any }?): Instance
	local m = Instance.new("Model")
	m.Name = name
	if attrs then
		for k, v in attrs do
			m:SetAttribute(k, v)
		end
	end
	if parent then
		m.Parent = parent
	end
	return m
end

local function prompt(parent: Instance, name: string, action: string, object: string, hold: number?, dist: number?, key: string?): Instance
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = dist or 8
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode[key or "E"]
	pp.GamepadKeyCode = if key == "F" then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
	pp.Parent = parent
	return pp
end

local function pointLight(parent: Instance, name: string, range: number, brightness: number, color: Color3, shadows: boolean, enabled: boolean?): Instance
	local l = Instance.new("PointLight")
	l.Name = name
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = shadows
	l.Enabled = if enabled == nil then true else enabled
	l.Parent = parent
	return l
end

local function spotLight(parent: Instance, name: string, range: number, brightness: number, angle: number, color: Color3, face, enabled: boolean): Instance
	local l = Instance.new("SpotLight")
	l.Name = name
	l.Range = range
	l.Brightness = brightness
	l.Angle = angle
	l.Color = color
	l.Face = face
	l.Shadows = true
	l.Enabled = enabled
	l.Parent = parent
	return l
end

local function sound(parent: Instance, name: string, id: string?, volume: number?, looped: boolean?): Instance
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id or ""
	s.Volume = volume or 0.5
	s.Looped = looped == true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 80
	s.RollOffMinDistance = 6
	s.Parent = parent
	return s
end

-- Текстовая табличка на грани детали
local function label(parentPart: Instance, face, text: string, textColor: Color3, bgColor: Color3?, pixelsPerStud: number?, guiName: string?, labelName: string?, fontFamily: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = guiName or "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0.3
	gui.Parent = parentPart
	local tl = Instance.new("TextLabel")
	tl.Name = labelName or "Label"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = bgColor or Color3.fromRGB(0, 0, 0)
	tl.BackgroundTransparency = if bgColor then 0 else 1
	tl.BorderSizePixel = 0
	tl.TextColor3 = textColor
	tl.TextScaled = true
	tl.TextWrapped = true
	tl.FontFace = Font.new(fontFamily or "rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
	tl.Text = text
	tl.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = tl
	return gui, tl
end

----------------------------------------------------------------------
-- Геометрические помощники: прямоугольник минус дыры, стены с проёмами
----------------------------------------------------------------------
type Rect = { x0: number, x1: number, z0: number, z1: number }

local function uniqSort(t: { number }): { number }
	table.sort(t)
	local out = {}
	for _, v in t do
		if out[#out] ~= v then
			table.insert(out, v)
		end
	end
	return out
end

-- Разбивает прямоугольник на детали, исключая дыры. emit(x0, x1, z0, z1)
local function rectMinusHoles(r: Rect, holes: { Rect }, emit)
	local xs = { r.x0, r.x1 }
	local zs = { r.z0, r.z1 }
	local inner = {}
	for _, h in holes do
		local hx0, hx1 = math.max(h.x0, r.x0), math.min(h.x1, r.x1)
		local hz0, hz1 = math.max(h.z0, r.z0), math.min(h.z1, r.z1)
		if hx1 > hx0 and hz1 > hz0 then
			table.insert(inner, { x0 = hx0, x1 = hx1, z0 = hz0, z1 = hz1 })
			table.insert(xs, hx0)
			table.insert(xs, hx1)
			table.insert(zs, hz0)
			table.insert(zs, hz1)
		end
	end
	if #inner == 0 then
		emit(r.x0, r.x1, r.z0, r.z1)
		return
	end
	xs = uniqSort(xs)
	zs = uniqSort(zs)
	local function isHole(cx, cz)
		for _, h in inner do
			if cx > h.x0 and cx < h.x1 and cz > h.z0 and cz < h.z1 then
				return true
			end
		end
		return false
	end
	for zi = 1, #zs - 1 do
		local z0, z1 = zs[zi], zs[zi + 1]
		local runStart = nil
		for xi = 1, #xs do
			local isSolid = false
			if xi < #xs then
				isSolid = not isHole((xs[xi] + xs[xi + 1]) / 2, (z0 + z1) / 2)
			end
			if isSolid and runStart == nil then
				runStart = xs[xi]
			elseif not isSolid and runStart ~= nil then
				emit(runStart, xs[xi], z0, z1)
				runStart = nil
			end
		end
	end
end

-- Плита пола: верх на yTop, толщиной th
local function slab(parent: Instance, name: string, r: Rect, yTop: number, th: number, color: Color3, material, holes: { Rect }?, kind: string?)
	rectMinusHoles(r, holes or {}, function(x0, x1, z0, z1)
		bbox(parent, name, x0, x1, yTop - th, yTop, z0, z1, color, material, kind)
	end)
end

type Opening = { a: number, b: number, y0: number, y1: number }

-- Стена толщиной 1 вдоль оси axis ("x": тянется по X при z=c; "z": по Z при x=c), от a до b, высота y0..y1.
-- openings: проёмы вдоль стены {a, b, y0, y1}. Возвращает список деталей.
local WALL_T = 1
local function wall(parent: Instance, name: string, axis: string, c: number, a: number, b: number, y0: number, y1: number, color: Color3, material, openings: { Opening }?, thickness: number?)
	local th = thickness or WALL_T
	local parts = {}
	local function emit(s0, s1, h0, h1)
		if s1 - s0 <= 0.001 or h1 - h0 <= 0.001 then
			return
		end
		local p
		if axis == "x" then
			p = bbox(parent, name, s0, s1, h0, h1, c - th / 2, c + th / 2, color, material)
		else
			p = bbox(parent, name, c - th / 2, c + th / 2, h0, h1, s0, s1, color, material)
		end
		table.insert(parts, p)
	end
	local ops = {}
	for _, o in openings or {} do
		if o.b > a and o.a < b and o.y1 > y0 and o.y0 < y1 then
			table.insert(ops, { a = math.max(o.a, a), b = math.min(o.b, b), y0 = math.max(o.y0, y0), y1 = math.min(o.y1, y1) })
		end
	end
	-- Разбиение вдоль стены по краям проёмов; в каждом отрезке — вертикальные промежутки между проёмами
	local edges = { a, b }
	for _, o in ops do
		table.insert(edges, o.a)
		table.insert(edges, o.b)
	end
	edges = uniqSort(edges)
	local function gapsFor(mid: number): { { number } }
		local ivs = {}
		for _, o in ops do
			if mid > o.a and mid < o.b then
				table.insert(ivs, { o.y0, o.y1 })
			end
		end
		table.sort(ivs, function(p, q)
			return p[1] < q[1]
		end)
		local gaps = {}
		local cursor = y0
		for _, iv in ivs do
			if iv[1] > cursor + 0.001 then
				table.insert(gaps, { cursor, iv[1] })
			end
			cursor = math.max(cursor, iv[2])
		end
		if y1 > cursor + 0.001 then
			table.insert(gaps, { cursor, y1 })
		end
		return gaps
	end
	local function sameGaps(g1, g2): boolean
		if #g1 ~= #g2 then
			return false
		end
		for i, g in g1 do
			if math.abs(g[1] - g2[i][1]) > 0.001 or math.abs(g[2] - g2[i][2]) > 0.001 then
				return false
			end
		end
		return true
	end
	-- объединяем соседние отрезки с одинаковой структурой промежутков
	local runStart, runGaps = nil, nil
	for i = 1, #edges - 1 do
		local s0, s1 = edges[i], edges[i + 1]
		local gaps = gapsFor((s0 + s1) / 2)
		if runGaps == nil then
			runStart, runGaps = s0, gaps
		elseif not sameGaps(runGaps, gaps) then
			for _, g in runGaps do
				emit(runStart, s0, g[1], g[2])
			end
			runStart, runGaps = s0, gaps
		end
	end
	if runGaps ~= nil then
		for _, g in runGaps do
			emit(runStart, edges[#edges], g[1], g[2])
		end
	end
	return parts
end

-- Лестница: ступени-блоки от bottomY до верха ступени. dir: "+z" | "-z" | "+x" | "-x".
-- Начало (первая ступень) в start по оси; поперечный диапазон s0..s1. Верх ступени k = yBase + k*rise.
local function stairs(parent: Instance, name: string, dir: string, start: number, s0: number, s1: number, count: number, rise: number, depth: number, yBase: number, bottomY: number, color: Color3, material)
	local parts = {}
	for k = 1, count do
		local top = yBase + k * rise
		local l0 = start + (k - 1) * depth
		local l1 = start + k * depth
		if dir == "-z" or dir == "-x" then
			l0, l1 = start - k * depth, start - (k - 1) * depth
		end
		local p
		if dir == "+z" or dir == "-z" then
			p = bbox(parent, name, s0, s1, bottomY, top, l0, l1, color, material)
		else
			p = bbox(parent, name, l0, l1, bottomY, top, s0, s1, color, material)
		end
		table.insert(parts, p)
	end
	return parts
end

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- Уровни и папки дома
----------------------------------------------------------------------
local F1, F2, FB, G = 0, 11, -10, -1 -- верх пола 1-го/2-го этажа, подвала, земли
local H1, H2 = 10, 21 -- верх внутренних стен (низ плиты 2-го этажа / потолочной плиты)
local ATTIC = 22
local DOOR_W, DOOR_H = 4, 7.5
local WIN_W, WIN_H, WIN_Y = 5, 4, 3.5

local house = folder("House")
local structure = folder("Structure", house)
local furniture = folder("Furniture", house)
local roomsF = folder("Rooms", house)
local lightsF = folder("Lights", house)
local doorsF = folder("Doors", house)
local windowsF = folder("Windows", house)
local hidingF = folder("HidingSpots", house)
local treesF = folder("Trees", house)
local templatesF = folder("Templates", house)
local navF = folder("Nav", house)
local waypointsF = folder("Waypoints", navF)
local entriesF = folder("Entries", navF)
local inmateSpawnsF = folder("InmateSpawns", navF)
local vesperF = folder("VesperSpots", navF)
local spawnsF = folder("Spawns", house)
local motionF = folder("MotionLights", house)

----------------------------------------------------------------------
-- Описание дверей и окон (используется и для проёмов в стенах, и для моделей)
-- axis "x": стена вдоль X при z=c; "z": стена вдоль Z при x=c. a..b — проём вдоль стены.
----------------------------------------------------------------------
local DOORS = {
	{ id = "FrontDoor", kind = "Entry", axis = "x", c = -16, a = -2, b = 2, y = F1, roomA = "Porch", roomB = "Foyer", out = -1 },
	{ id = "BackDoor", kind = "Entry", axis = "x", c = 16, a = -10, b = -6, y = F1, roomA = "BackYard", roomB = "BackHall", out = 1 },
	{ id = "GarageSide", kind = "Entry", axis = "z", c = 42, a = -6, b = -2, y = F1, roomA = "EastSide", roomB = "Garage", out = 1 },
	{ id = "GarageKitchen", kind = "Interior", axis = "z", c = 24, a = -9, b = -5, y = F1, roomA = "Kitchen", roomB = "Garage" },
	{ id = "LaundryDoor", kind = "Interior", axis = "z", c = -12, a = 10.5, b = 14.5, y = F1, roomA = "BackHall", roomB = "Laundry" },
	{ id = "BasementDoor", kind = "Interior", axis = "x", c = 9, a = -21.5, b = -17.5, y = F1, roomA = "Laundry", roomB = "Basement" },
	{ id = "KidRoomDoor", kind = "Interior", axis = "z", c = -4, a = -14, b = -10, y = F2, roomA = "UpperHall", roomB = "KidRoom" },
	{ id = "ParentsRoomDoor", kind = "Interior", axis = "z", c = 4, a = -14, b = -10, y = F2, roomA = "UpperHall", roomB = "ParentsRoom" },
	{ id = "OfficeDoor", kind = "Interior", axis = "z", c = -4, a = 4, b = 8, y = F2, roomA = "UpperHall", roomB = "Office" },
	{ id = "BathroomDoor", kind = "Interior", axis = "z", c = 4, a = 11.5, b = 15.5, y = F2, roomA = "UpperHall", roomB = "Bathroom" },
}
-- Арки без дверей (проёмы 4x7.5)
local ARCHES = {
	{ axis = "z", c = -4, a = -8, b = -4, y = F1 }, -- Foyer -> Living
	{ axis = "z", c = 4, a = -15, b = -11, y = F1 }, -- Foyer -> Kitchen
	{ axis = "x", c = -2, a = 12, b = 16, y = F1 }, -- Kitchen -> Dining
	{ axis = "z", c = -4, a = 11.5, b = 15.5, y = F1 }, -- Foyer -> BackHall
}
-- Окна 1-го этажа (с моделями). out: знак внешней нормали по перпендикулярной оси
local WINDOWS = {
	{ id = "Living1", axis = "x", c = -16, a = -20.5, b = -15.5, room = "Living", out = -1 },
	{ id = "Living2", axis = "x", c = -16, a = -12.5, b = -7.5, room = "Living", out = -1 },
	{ id = "Kitchen1", axis = "x", c = -16, a = 11.5, b = 16.5, room = "Kitchen", out = -1 },
	{ id = "Dining1", axis = "z", c = 24, a = 4.5, b = 9.5, room = "Dining", out = 1 },
	{ id = "Laundry1", axis = "z", c = -24, a = 10, b = 15, room = "Laundry", out = -1 },
}
-- Декоративные окна 2-го этажа (без моделей)
local DECO_WINDOWS = {
	{ axis = "x", c = -16, a = -20.5, b = -15.5 },
	{ axis = "x", c = -16, a = -12.5, b = -7.5 },
	{ axis = "x", c = -16, a = 7.5, b = 12.5 },
	{ axis = "x", c = -16, a = 15.5, b = 20.5 },
	{ axis = "z", c = -24, a = -10.5, b = -5.5 },
	{ axis = "z", c = -24, a = 5.5, b = 10.5 },
	{ axis = "z", c = 24, a = -10.5, b = -5.5 },
	{ axis = "z", c = 24, a = 7, b = 10 },
	{ axis = "x", c = 16, a = -16.5, b = -11.5 },
	{ axis = "x", c = 16, a = 11.5, b = 15.5 },
}

local function openingsFor(axis: string, c: number, floorY: number?): { Opening }
	local ops = {}
	for _, d in DOORS do
		if d.axis == axis and d.c == c and (floorY == nil or d.y == floorY) then
			table.insert(ops, { a = d.a, b = d.b, y0 = d.y, y1 = d.y + DOOR_H })
		end
	end
	for _, d in ARCHES do
		if d.axis == axis and d.c == c and (floorY == nil or d.y == floorY) then
			table.insert(ops, { a = d.a, b = d.b, y0 = d.y, y1 = d.y + DOOR_H })
		end
	end
	for _, w in WINDOWS do
		if w.axis == axis and w.c == c and (floorY == nil or floorY == F1) then
			table.insert(ops, { a = w.a, b = w.b, y0 = F1 + WIN_Y, y1 = F1 + WIN_Y + WIN_H })
		end
	end
	for _, w in DECO_WINDOWS do
		if w.axis == axis and w.c == c and (floorY == nil or floorY == F2) then
			table.insert(ops, { a = w.a, b = w.b, y0 = F2 + WIN_Y, y1 = F2 + WIN_Y + WIN_H })
		end
	end
	return ops
end

----------------------------------------------------------------------
-- Полы и потолки
----------------------------------------------------------------------
local STAIR_HOLE_UP = { x0 = 0, x1 = 4, z0 = -2, z1 = 12 } -- дыра в плите 2-го этажа над лестницей
local STAIR_HOLE_DOWN = { x0 = -17.5, x1 = -5.5, z0 = 4.5, z1 = 8.5 } -- дыра в плите 1-го этажа над лестницей в подвал

do
	local S = structure
	-- 1-й этаж (верх y=0)
	slab(S, "Floor", { x0 = -24, x1 = -4, z0 = -16, z1 = 4 }, F1, 1, C.FloorWood, M.WoodPlanks)
	slab(S, "Floor", { x0 = -4, x1 = 4, z0 = -16, z1 = 16 }, F1, 1, C.FloorWood2, M.WoodPlanks)
	slab(S, "Floor", { x0 = 4, x1 = 24, z0 = -16, z1 = -2 }, F1, 1, C.FloorTile, M.Marble)
	slab(S, "Floor", { x0 = 4, x1 = 24, z0 = -2, z1 = 16 }, F1, 1, C.FloorWood, M.WoodPlanks)
	slab(S, "Floor", { x0 = -24, x1 = -12, z0 = 9, z1 = 16 }, F1, 1, C.FloorTile, M.Marble)
	slab(S, "Floor", { x0 = -12, x1 = -4, z0 = 9, z1 = 16 }, F1, 1, C.FloorWood2, M.WoodPlanks)
	slab(S, "Floor", { x0 = -24, x1 = -4, z0 = 4, z1 = 9 }, F1, 1, C.Concrete, M.Concrete, { STAIR_HOLE_DOWN })
	slab(S, "Floor", { x0 = 24, x1 = 42, z0 = -16, z1 = 2 }, F1, 1, C.ConcreteDark, M.Concrete)
	-- 2-й этаж (верх y=11)
	slab(S, "Floor", { x0 = -24, x1 = -4, z0 = -16, z1 = 0 }, F2, 1, C.Carpet, M.Fabric)
	slab(S, "Floor", { x0 = -24, x1 = -4, z0 = 0, z1 = 16 }, F2, 1, C.FloorWood, M.WoodPlanks)
	slab(S, "Floor", { x0 = 4, x1 = 24, z0 = -16, z1 = 0 }, F2, 1, vary(C.Carpet, 0.03), M.Fabric)
	slab(S, "Floor", { x0 = 4, x1 = 24, z0 = 0, z1 = 16 }, F2, 1, C.FloorTileBath, M.Marble)
	slab(S, "Floor", { x0 = -4, x1 = 4, z0 = -16, z1 = 16 }, F2, 1, C.FloorWood2, M.WoodPlanks, { STAIR_HOLE_UP })
	-- Потолки (тонкие накладки под плитами)
	for _, r in {
		{ -24, -4, -16, 4 }, { -4, 4, -16, 16 }, { 4, 24, -16, -2 }, { 4, 24, -2, 16 }, { -24, -12, 9, 16 }, { -12, -4, 9, 16 }, { -24, -4, 4, 9 },
	} do
		bbox(S, "Ceiling", r[1], r[2], H1 - 0.2, H1, r[3], r[4], C.Ceiling, M.SmoothPlastic, "deco")
	end
	bbox(S, "Ceiling", 24, 42, H1 - 0.2, H1, -16, 2, C.ConcreteDark, M.Concrete, "deco")
	for _, r in { { -24, -4, -16, 0 }, { -24, -4, 0, 16 }, { 4, 24, -16, 0 }, { 4, 24, 0, 16 }, { -4, 4, -16, 16 } } do
		bbox(S, "Ceiling", r[1], r[2], H2 - 0.2, H2, r[3], r[4], C.Ceiling, M.SmoothPlastic, "deco")
	end
	-- Чердачная плита и плита гаража
	bbox(S, "Floor", -24, 24, H2, ATTIC, -16, 16, C.WoodDark, M.WoodPlanks)
	bbox(S, "Floor", 24, 42, H1, H1 + 1, -16, 2, C.WoodDark, M.WoodPlanks)
	-- Подвал
	bbox(S, "Floor", -14, 14, FB - 1, FB, -8, 16, C.ConcreteDark, M.Concrete)
	-- балки под потолком подвала
	for z = -6, 14, 4 do
		bbox(S, "Joist", -13.5, 13.5, -1.8, -1, z - 0.4, z + 0.4, C.WoodDark, M.Wood, "deco")
	end
end

----------------------------------------------------------------------
-- Стены
----------------------------------------------------------------------
do
	local S = structure
	local ext = C.Siding
	-- Наружные стены дома (y -1..22)
	wall(S, "Wall", "x", -16, -24, 24, G, ATTIC, ext, M.WoodPlanks, openingsFor("x", -16))
	wall(S, "Wall", "x", 16, -24, 24, G, ATTIC, ext, M.WoodPlanks, openingsFor("x", 16))
	wall(S, "Wall", "z", -24, -16, 16, G, ATTIC, ext, M.WoodPlanks, openingsFor("z", -24))
	wall(S, "Wall", "z", 24, -16, 16, G, ATTIC, ext, M.WoodPlanks, openingsFor("z", 24))
	-- Гараж (y -1..11), ворота: проём 12x8 закрыт декоративными панелями
	wall(S, "Wall", "x", -16, 24, 42, G, H1 + 1, ext, M.WoodPlanks, { { a = 27, b = 39, y0 = F1, y1 = F1 + 8 } })
	wall(S, "Wall", "x", 2, 24, 42, G, H1 + 1, ext, M.WoodPlanks)
	wall(S, "Wall", "z", 42, -16, 2, G, H1 + 1, ext, M.WoodPlanks, openingsFor("z", 42))
	do
		local shades = { 0.0, 0.02, -0.02, 0.01 }
		for i = 1, 4 do
			local y0 = F1 + (i - 1) * 2
			bbox(S, "GarageDoor", 27, 39, y0, y0 + 2, -16.2, -15.85, vary(C.Trim, 0.01), M.Metal, "solid")
			bbox(S, "GarageDoorGroove", 27.2, 38.8, y0 + 1.9, y0 + 2.1, -16.25, -16.15, C.SidingDark, M.Metal, "deco")
			local _ = shades
		end
		bbox(S, "GarageDoorHandle", 32.4, 33.6, 3.4, 3.8, -16.4, -16.2, C.MetalDark, M.Metal, "deco")
	end
	-- Внутренние стены 1-го этажа (y 0..10)
	wall(S, "Wall", "z", -4, -16, 16, F1, H1, C.WallInt, M.SmoothPlastic, openingsFor("z", -4, F1))
	wall(S, "Wall", "z", 4, -16, 16, F1, H1, C.WallInt, M.SmoothPlastic, openingsFor("z", 4, F1))
	wall(S, "Wall", "x", 4, -24, -4, F1, H1, C.WallInt2, M.SmoothPlastic) -- Living / лестница в подвал
	wall(S, "Wall", "x", 9, -24, -4, F1, H1, C.WallInt2, M.SmoothPlastic, openingsFor("x", 9, F1)) -- лестница в подвал / Laundry+BackHall
	wall(S, "Wall", "x", -2, 4, 24, F1, H1, C.WallInt, M.SmoothPlastic, openingsFor("x", -2, F1)) -- Kitchen / Dining
	wall(S, "Wall", "z", -12, 9, 16, F1, H1, C.WallInt2, M.SmoothPlastic, openingsFor("z", -12, F1)) -- Laundry / BackHall
	-- Внутренние стены 2-го этажа (y 11..21)
	wall(S, "Wall", "z", -4, -16, 16, F2, H2, C.WallKid, M.SmoothPlastic, openingsFor("z", -4, F2))
	wall(S, "Wall", "z", 4, -16, 16, F2, H2, C.WallInt, M.SmoothPlastic, openingsFor("z", 4, F2))
	wall(S, "Wall", "x", 0, -24, -4, F2, H2, C.WallKid, M.SmoothPlastic)
	wall(S, "Wall", "x", 0, 4, 24, F2, H2, C.WallBath, M.SmoothPlastic)
	-- Подвал (y -10..0) и шахта лестницы в подвал (y -11..0)
	wall(S, "Wall", "z", -14, -8, 16, FB, F1, C.WallBasement, M.Concrete, { { a = 4, b = 9, y0 = FB, y1 = F1 } })
	wall(S, "Wall", "z", 14, -8, 16, FB, F1, C.WallBasement, M.Concrete)
	wall(S, "Wall", "x", -8, -14, 14, FB, F1, C.WallBasement, M.Concrete)
	wall(S, "Wall", "x", 16, -14, 14, FB, F1, C.WallBasement, M.Concrete)
	wall(S, "Wall", "x", 4, -24, -14, FB - 1, F1, C.WallBasement, M.Concrete)
	wall(S, "Wall", "x", 9, -24, -14, FB - 1, F1, C.WallBasement, M.Concrete)
	wall(S, "Wall", "z", -24, 4, 9, FB - 1, F1, C.WallBasement, M.Concrete)
	-- Плинтусы по комнатам 1-го этажа (декор)
	for _, r in { { -23.5, -4.5, -15.5, 3.5 }, { 4.5, 23.5, -15.5, -2.5 }, { 4.5, 23.5, -1.5, 15.5 } } do
		local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
		bbox(S, "Trim", x0, x1, F1, F1 + 0.4, z0, z0 + 0.15, C.Trim, M.SmoothPlastic, "deco")
		bbox(S, "Trim", x0, x1, F1, F1 + 0.4, z1 - 0.15, z1, C.Trim, M.SmoothPlastic, "deco")
	end
end

----------------------------------------------------------------------
-- Лестницы
----------------------------------------------------------------------
do
	local S = structure
	-- Наверх: 11 ступеней 1x2 вдоль +Z при x 0..4, от z=-10; верх ступени k = k
	stairs(S, "Step", "+z", -10, 0, 4, 11, 1, 2, F1, F1, C.FloorWood2, M.WoodPlanks)
	-- Балюстрада вдоль открытой стороны (x=0), наклонная сплошная панель + поручень
	do
		local len = math.sqrt(22 ^ 2 + 11 ^ 2)
		local dirv = Vector3.new(0, 11, 22).Unit
		local up = Vector3.new(0, 22, -11).Unit
		local mid = Vector3.new(0, F1 + 5.5 + 2.2, 1)
		local cf = CFrame.fromMatrix(mid, Vector3.new(1, 0, 0), up)
		box(S, "StairRail", cf, Vector3.new(0.3, 3.2, len), C.WoodDark, M.Wood, "solid", { CastShadow = false })
		local _ = dirv
		box(S, "StairRail", cf * CFrame.new(0, 1.8, 0), Vector3.new(0.5, 0.4, len), C.WoodLight, M.Wood, "deco")
	end
	-- Ограждение дыры на 2-м этаже: вдоль x=0 (z -2..10) и вдоль z=-2 (x 0..4)
	for _, seg in { { 0, -2, 0, 10 }, { 0, -2, 4, -2 } } do
		local x0, z0, x1, z1 = seg[1], seg[2], seg[3], seg[4]
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		local sx, sz = math.max(0.3, math.abs(x1 - x0)), math.max(0.3, math.abs(z1 - z0))
		box(S, "Railing", CFrame.new(cx, F2 + 1.6, cz), Vector3.new(sx, 3.2, sz), C.WoodDark, M.Wood, "solid", { Transparency = 0.35, CastShadow = false })
		box(S, "Railing", CFrame.new(cx, F2 + 3.3, cz), Vector3.new(if sx > 0.3 then sx + 0.3 else 0.5, 0.4, if sz > 0.3 then sz + 0.3 else 0.5), C.WoodLight, M.Wood, "deco")
	end
	-- В подвал: 10 ступеней 1x2 вдоль +X при z 4.5..8.5, от x=-17.5; верх ступени k = -k
	stairs(S, "Step", "+x", -17.5, 4.5, 8.5, 10, -1, 2, F1, FB - 1, C.Concrete, M.Concrete)
	-- Поручень вдоль стены лестницы в подвал
	do
		local len = math.sqrt(20 ^ 2 + 10 ^ 2)
		local up = Vector3.new(10, 20, 0).Unit
		local cf = CFrame.fromMatrix(Vector3.new(-7.5, -5.5 + 3, 8.3), Vector3.new(0, 0, -1), up)
		box(S, "StairRail", cf, Vector3.new(0.3, 0.3, len), C.MetalDark, M.Metal, "deco")
	end
end

----------------------------------------------------------------------
-- Крыша, крыльцо, задняя площадка, наружные детали
----------------------------------------------------------------------
do
	local S = structure
	-- Чердак: два клина (фронтоны = треугольные грани клиньев)
	local south = part({ ClassName = "WedgePart", Name = "Attic", Size = Vector3.new(50, 8.5, 17), CFrame = CFrame.new(0, ATTIC + 4.25, -8.5), Color = C.Siding, Material = M.WoodPlanks, CanTouch = false, CanQuery = false }, S)
	local north = part({ ClassName = "WedgePart", Name = "Attic", Size = Vector3.new(50, 8.5, 17), CFrame = CFrame.new(0, ATTIC + 4.25, 8.5) * CFrame.Angles(0, rad(180), 0), Color = C.Siding, Material = M.WoodPlanks, CanTouch = false, CanQuery = false }, S)
	local _ = south, north
	-- Черепица: наклонные плиты на скатах
	local slopeLen = math.sqrt(17 ^ 2 + 8.5 ^ 2)
	for _, sgn in { -1, 1 } do
		local normal = Vector3.new(0, 17, sgn * 8.5).Unit
		local mid = Vector3.new(0, ATTIC + 4.25, sgn * 8.5) + normal * 0.25
		local cf = CFrame.fromMatrix(mid, Vector3.new(1, 0, 0), normal)
		box(S, "Roof", cf, Vector3.new(50.6, 0.5, slopeLen + 0.6), C.Roof, M.Slate, "solid", { CanQuery = false })
	end
	box(S, "RoofRidge", CFrame.new(0, ATTIC + 8.6, 0), Vector3.new(50.8, 0.5, 1.4), C.MetalDark, M.Metal, "deco")
	-- Дымоход
	bbox(S, "Chimney", 12.5, 15.5, ATTIC + 2, ATTIC + 11, 4.5, 7.5, C.Brick, M.Brick, "deco", { CastShadow = true })
	bbox(S, "ChimneyCap", 12.2, 15.8, ATTIC + 11, ATTIC + 11.4, 4.2, 7.8, C.ConcreteDark, M.Concrete, "deco")
	-- Чердачные окошки на фронтонах
	for _, x in { -24.6, 24.6 } do
		box(S, "AtticVent", CFrame.new(x, ATTIC + 4, 0), Vector3.new(0.3, 2, 1.6), C.GlassDark, M.Glass, "deco")
	end
	-- Угловые накладки (декор)
	for _, cx in { -24, 24 } do
		for _, cz in { -16, 16 } do
			bbox(S, "Trim", cx - 0.7, cx + 0.7, G, ATTIC, cz - 0.7, cz + 0.7, C.Trim, M.SmoothPlastic, "deco", { CastShadow = true })
		end
	end
	-- Крыша гаража: односкатная, высокая у дома (x=24), низкая у x=43
	part({ ClassName = "WedgePart", Name = "GarageRoof", Size = Vector3.new(20, 3, 19.5), CFrame = CFrame.new(24 + 9.75, H1 + 1 + 1.5, -7) * CFrame.Angles(0, rad(-90), 0), Color = C.Roof, Material = M.Slate, CanTouch = false, CanQuery = false }, S)
	bbox(S, "GarageFascia", 24, 43.6, H1 + 0.6, H1 + 1.2, -17.2, 3.2, C.Trim, M.SmoothPlastic, "deco")

	-- Крыльцо: настил x -8..8, z -24..-16 (верх y=0), ступень 0.5 у z -26..-24
	bbox(S, "Floor", -8, 8, G, F1, -24, -16, C.WoodLight, M.WoodPlanks)
	bbox(S, "Step", -3, 3, G, F1 - 0.5, -26, -24, C.WoodLight, M.WoodPlanks)
	for _, x in { -8, 8 } do
		bbox(S, "PorchPost", x - 0.4, x + 0.4, G, H1 + 0.5, -24.4, -23.6, C.Trim, M.Wood, "deco", { CastShadow = true })
	end
	bbox(S, "PorchRoof", -9, 9, H1 + 0.5, H1 + 1.1, -25, -16, C.Roof, M.Slate, "deco", { CastShadow = true })
	bbox(S, "PorchFascia", -9, 9, H1 + 0.1, H1 + 0.5, -25, -24.6, C.Trim, M.SmoothPlastic, "deco")
	-- Перила крыльца (декор) с просветом у ступеней
	for _, seg in { { -8, -3, -24 }, { 3, 8, -24 } } do
		bbox(S, "PorchRail", seg[1], seg[2], F1 + 2.6, F1 + 2.9, seg[3] - 0.2, seg[3] + 0.2, C.Trim, M.Wood, "deco")
		for x = seg[1] + 0.5, seg[2] - 0.5, 1.25 do
			bbox(S, "PorchBaluster", x - 0.1, x + 0.1, F1, F1 + 2.6, seg[3] - 0.1, seg[3] + 0.1, C.Trim, M.Wood, "deco")
		end
	end
	for _, x in { -8, 8 } do
		bbox(S, "PorchRail", x - 0.2, x + 0.2, F1 + 2.6, F1 + 2.9, -24, -16, C.Trim, M.Wood, "deco")
	end
	-- Коврик у двери, почтовый номер
	bbox(S, "Mat", -2, 2, F1, F1 + 0.08, -19, -16.6, Color3.fromRGB(80, 60, 44), M.Fabric, "deco")
	-- Задняя площадка у BackDoor: x -12..-4, z 16..20, ступень z 20..22
	bbox(S, "Floor", -12, -4, G, F1, 16, 20, C.Concrete, M.Concrete)
	bbox(S, "Step", -11, -5, G, F1 - 0.5, 20, 22, C.Concrete, M.Concrete)
	-- Ступень у боковой двери гаража (x=42, z -6..-2)
	bbox(S, "Step", 42.5, 44.5, G, F1 - 0.5, -6.5, -1.5, C.Concrete, M.Concrete)
	bbox(S, "Floor", 42, 42.5, G, F1, -6, -2, C.Concrete, M.Concrete)
end

----------------------------------------------------------------------
-- Двери (Hinge + Panel + Prompt [+ LockPrompt]) и наличники
----------------------------------------------------------------------
local function doorFrame(d, color: Color3)
	local S = structure
	local y0, y1 = d.y, d.y + DOOR_H
	if d.axis == "x" then
		bbox(S, "DoorFrame", d.a - 0.35, d.a, y0, y1 + 0.35, d.c - 0.6, d.c + 0.6, color, M.Wood, "deco")
		bbox(S, "DoorFrame", d.b, d.b + 0.35, y0, y1 + 0.35, d.c - 0.6, d.c + 0.6, color, M.Wood, "deco")
		bbox(S, "DoorFrame", d.a - 0.35, d.b + 0.35, y1, y1 + 0.35, d.c - 0.6, d.c + 0.6, color, M.Wood, "deco")
	else
		bbox(S, "DoorFrame", d.c - 0.6, d.c + 0.6, y0, y1 + 0.35, d.a - 0.35, d.a, color, M.Wood, "deco")
		bbox(S, "DoorFrame", d.c - 0.6, d.c + 0.6, y0, y1 + 0.35, d.b, d.b + 0.35, color, M.Wood, "deco")
		bbox(S, "DoorFrame", d.c - 0.6, d.c + 0.6, y1, y1 + 0.35, d.a - 0.35, d.b + 0.35, color, M.Wood, "deco")
	end
end

for _, d in DOORS do
	local m = model(d.id, doorsF, { DoorId = d.id, Kind = d.kind, Open = false, Locked = false, LockHP = 100, RoomA = d.roomA, RoomB = d.roomB })
	local hingePos, right
	if d.axis == "x" then
		hingePos = Vector3.new(d.a, d.y + DOOR_H / 2, d.c)
		right = Vector3.new(1, 0, 0)
	else
		hingePos = Vector3.new(d.c, d.y + DOOR_H / 2, d.a)
		right = Vector3.new(0, 0, 1)
	end
	local hcf = CFrame.fromMatrix(hingePos, right, Vector3.new(0, 1, 0))
	marker({ Name = "Hinge", CFrame = hcf, Size = Vector3.new(0.2, DOOR_H, 0.2) }, m)
	local isEntry = d.kind == "Entry"
	local panel = part({
		Name = "Panel",
		CFrame = hcf * CFrame.new(DOOR_W / 2, 0, 0),
		Size = Vector3.new(DOOR_W - 0.1, DOOR_H - 0.1, 0.3),
		Color = if isEntry then C.Door else C.DoorInt,
		Material = M.Wood,
		CanCollide = true,
		CanQuery = true,
		CanTouch = false,
	}, m)
	m.PrimaryPart = panel
	prompt(panel, "Prompt", "Open", "Door", 0, 8)
	if isEntry then
		prompt(panel, "LockPrompt", "Lock", "Door", 1, 8, "F")
	end
	doorFrame(d, if isEntry then C.Trim else C.DoorInt)
end
-- Наличники арок
for _, a in ARCHES do
	doorFrame(a, C.DoorInt)
end

----------------------------------------------------------------------
-- Окна: Glass + Board1..3 + Entry + Prompt; рамы и подоконники — декор
----------------------------------------------------------------------
local function windowFrame(w, yBase: number, color: Color3)
	local S = structure
	local y0, y1 = yBase + WIN_Y, yBase + WIN_Y + WIN_H
	if w.axis == "x" then
		bbox(S, "WindowSill", w.a - 0.4, w.b + 0.4, y0 - 0.3, y0, w.c - 0.75, w.c + 0.75, color, M.Wood, "deco")
		bbox(S, "WindowFrame", w.a - 0.3, w.b + 0.3, y1, y1 + 0.3, w.c - 0.6, w.c + 0.6, color, M.Wood, "deco")
		bbox(S, "WindowFrame", w.a - 0.3, w.a, y0, y1, w.c - 0.6, w.c + 0.6, color, M.Wood, "deco")
		bbox(S, "WindowFrame", w.b, w.b + 0.3, y0, y1, w.c - 0.6, w.c + 0.6, color, M.Wood, "deco")
		bbox(S, "WindowMullion", (w.a + w.b) / 2 - 0.08, (w.a + w.b) / 2 + 0.08, y0, y1, w.c - 0.15, w.c + 0.15, color, M.Wood, "deco")
	else
		bbox(S, "WindowSill", w.c - 0.75, w.c + 0.75, y0 - 0.3, y0, w.a - 0.4, w.b + 0.4, color, M.Wood, "deco")
		bbox(S, "WindowFrame", w.c - 0.6, w.c + 0.6, y1, y1 + 0.3, w.a - 0.3, w.b + 0.3, color, M.Wood, "deco")
		bbox(S, "WindowFrame", w.c - 0.6, w.c + 0.6, y0, y1, w.a - 0.3, w.a, color, M.Wood, "deco")
		bbox(S, "WindowFrame", w.c - 0.6, w.c + 0.6, y0, y1, w.b, w.b + 0.3, color, M.Wood, "deco")
		bbox(S, "WindowMullion", w.c - 0.15, w.c + 0.15, y0, y1, (w.a + w.b) / 2 - 0.08, (w.a + w.b) / 2 + 0.08, color, M.Wood, "deco")
	end
end

for _, w in WINDOWS do
	local m = model(w.id, windowsF, { WindowId = w.id, Boards = 0, Broken = false, Room = w.room })
	local mid = (w.a + w.b) / 2
	local cy = F1 + WIN_Y + WIN_H / 2
	local function at(along: number, y: number, perp: number): CFrame
		if w.axis == "x" then
			return CFrame.new(along, y, perp)
		end
		return CFrame.new(perp, y, along) * CFrame.Angles(0, rad(90), 0)
	end
	local glass = part({
		Name = "Glass",
		CFrame = at(mid, cy, w.c),
		Size = Vector3.new(WIN_W, WIN_H, 0.2),
		Color = C.Glass,
		Material = M.Glass,
		Transparency = 0.55,
		Reflectance = 0.1,
		CanCollide = true,
		CanQuery = true,
		CanTouch = false,
		CastShadow = false,
	}, m)
	m.PrimaryPart = glass
	prompt(glass, "Prompt", "Board up", "Window", 0.8, 8)
	for i = 1, 3 do
		part({
			Name = "Board" .. i,
			CFrame = at(mid, F1 + WIN_Y + 0.8 + (i - 1) * 1.2, w.c - w.out * 0.65) * CFrame.Angles(0, 0, rad(randRange(-4, 4))),
			Size = Vector3.new(5.4, 0.8, 0.3),
			Color = vary(C.Wood, 0.05),
			Material = M.Wood,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, m)
	end
	marker({ Name = "Entry", CFrame = at(mid, G + 0.5, w.c + w.out * 2.5), Size = Vector3.new(1, 1, 1) }, m)
	windowFrame(w, F1, C.Trim)
end
-- Декоративные окна 2-го этажа: тёмное стекло
for _, w in DECO_WINDOWS do
	local mid = (w.a + w.b) / 2
	local cy = F2 + WIN_Y + WIN_H / 2
	local cf = if w.axis == "x" then CFrame.new(mid, cy, w.c) else CFrame.new(w.c, cy, mid) * CFrame.Angles(0, rad(90), 0)
	deco({ Name = "DecoGlass", CFrame = cf, Size = Vector3.new(w.b - w.a, WIN_H, 0.2), Color = C.GlassDark, Material = M.Glass, Transparency = 0.25, Reflectance = 0.15, CanCollide = true }, structure)
	windowFrame(w, F2, C.Trim)
end

----------------------------------------------------------------------
-- Свет по комнатам: Bulb(+Light) + Switch(+Prompt) + Candle(+Light)
----------------------------------------------------------------------
-- switch = { axis, c, along, side }: стена axis при координате c; выключатель внутри комнаты со стороны side (+1/-1)
local function buildLight(roomName: string, bulbPos: Vector3, switch, candlePos: Vector3, opts)
	opts = opts or {}
	local m = model(roomName, lightsF, { RoomName = roomName, On = true })
	local style = opts.style or "ceiling"
	local bulbColor = opts.color or C.WarmLight
	if style == "ceiling" then
		deco({ Name = "Shade", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(bulbPos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, rad(90)), Size = Vector3.new(0.5, 2.6, 2.6), Color = C.Trim, Material = M.SmoothPlastic }, m)
	elseif style == "tube" then
		deco({ Name = "Shade", CFrame = CFrame.new(bulbPos + Vector3.new(0, 0.3, 0)), Size = Vector3.new(4.4, 0.3, 1.2), Color = C.Metal, Material = M.Metal }, m)
	elseif style == "bare" then
		deco({ Name = "Wire", CFrame = CFrame.new(bulbPos + Vector3.new(0, (opts.wire or 1) / 2 + 0.3, 0)), Size = Vector3.new(0.1, opts.wire or 1, 0.1), Color = C.MetalDark, Material = M.Metal }, m)
	elseif style == "lantern" then
		local cf = opts.lanternCF or CFrame.new(bulbPos)
		deco({ Name = "LanternCap", CFrame = cf * CFrame.new(0, 0.7, 0), Size = Vector3.new(1.3, 0.3, 1.3), Color = C.MetalDark, Material = M.Metal }, m)
		deco({ Name = "LanternBase", CFrame = cf * CFrame.new(0, -0.6, 0), Size = Vector3.new(1.0, 0.2, 1.0), Color = C.MetalDark, Material = M.Metal }, m)
		for _, o in { { 0.55, 0 }, { -0.55, 0 }, { 0, 0.55 }, { 0, -0.55 } } do
			deco({ Name = "LanternBar", CFrame = cf * CFrame.new(o[1], 0, o[2]), Size = Vector3.new(0.1, 1.1, 0.1), Color = C.MetalDark, Material = M.Metal }, m)
		end
	end
	local bulbSize = if style == "tube" then Vector3.new(4, 0.25, 0.8) elseif style == "bare" or style == "lantern" then Vector3.new(0.7, 0.9, 0.7) else Vector3.new(1.4, 0.4, 1.4)
	local bulb = part({
		Name = "Bulb",
		Shape = if style == "bare" or style == "lantern" then Enum.PartType.Ball else Enum.PartType.Block,
		CFrame = CFrame.new(bulbPos),
		Size = bulbSize,
		Color = C.Bulb,
		Material = M.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, m)
	m.PrimaryPart = bulb
	pointLight(bulb, "Light", opts.range or 18, opts.brightness or 1.2, bulbColor, true)
	-- Выключатель у двери
	local scf
	if switch.axis == "x" then
		scf = CFrame.new(switch.along, switch.y or (switch.floor + 4.5), switch.c + switch.side * 0.6)
	else
		scf = CFrame.new(switch.c + switch.side * 0.6, switch.y or (switch.floor + 4.5), switch.along) * CFrame.Angles(0, rad(90), 0)
	end
	local sw = part({ Name = "Switch", CFrame = scf, Size = Vector3.new(0.4, 0.6, 0.2), Color = C.Trim, Material = M.SmoothPlastic, CanCollide = false, CanQuery = true, CanTouch = false, CastShadow = false }, m)
	prompt(sw, "Prompt", "Light", "Switch", 0, 7)
	-- Свеча (по умолчанию скрыта; сервер показывает при апгрейде)
	local candle = part({ Name = "Candle", CFrame = CFrame.new(candlePos), Size = Vector3.new(0.35, 0.9, 0.35), Color = Color3.fromRGB(240, 230, 200), Material = M.SmoothPlastic, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, m)
	pointLight(candle, "Light", 9, 0.6, Color3.fromRGB(255, 190, 120), false, false)
	return m
end

do
	local y1, y2 = H1 - 0.5, H2 - 0.5
	-- 1-й этаж
	buildLight("Foyer", Vector3.new(0, y1, -8), { axis = "x", c = -16, along = 3.2, side = 1, floor = F1 }, Vector3.new(-3, F1 + 3.2, -11.5))
	buildLight("Living", Vector3.new(-14, y1, -6), { axis = "z", c = -4, along = -9.5, side = -1, floor = F1 }, Vector3.new(-15, F1 + 1.8, -6))
	buildLight("Kitchen", Vector3.new(14, y1, -9), { axis = "z", c = 4, along = -10, side = 1, floor = F1 }, Vector3.new(14, F1 + 3.4, -9))
	buildLight("Dining", Vector3.new(14, y1, 7), { axis = "x", c = -2, along = 17, side = 1, floor = F1 }, Vector3.new(14, F1 + 3.2, 6))
	buildLight("Laundry", Vector3.new(-18, y1, 12.5), { axis = "z", c = -12, along = 15.2, side = -1, floor = F1 }, Vector3.new(-22, F1 + 3.7, 14.4))
	buildLight("BackHall", Vector3.new(-8, y1, 12.5), { axis = "x", c = 16, along = -5, side = -1, floor = F1 }, Vector3.new(-8, F1 + 2.0, 10.3))
	buildLight("Garage", Vector3.new(33, y1, -7), { axis = "z", c = 24, along = -3.5, side = 1, floor = F1 }, Vector3.new(30, F1 + 3.4, 0.8), { style = "tube", color = Color3.fromRGB(236, 240, 230) })
	-- 2-й этаж
	buildLight("KidRoom", Vector3.new(-14, y2, -8), { axis = "z", c = -4, along = -9, side = -1, floor = F2 }, Vector3.new(-9, F2 + 3.2, -2))
	buildLight("ParentsRoom", Vector3.new(14, y2, -8), { axis = "z", c = 4, along = -9, side = 1, floor = F2 }, Vector3.new(8, F2 + 2.4, -14))
	buildLight("UpperHall", Vector3.new(0, y2, -6), { axis = "z", c = -4, along = 2, side = 1, floor = F2 }, Vector3.new(0, F2 + 3.0, -15))
	buildLight("Office", Vector3.new(-14, y2, 8), { axis = "z", c = -4, along = 9, side = -1, floor = F2 }, Vector3.new(-16, F2 + 3.2, 13.5))
	buildLight("Bathroom", Vector3.new(14, y2, 8), { axis = "z", c = 4, along = 10.5, side = 1, floor = F2 }, Vector3.new(8, F2 + 3.4, 1.5))
	-- Подвал: голая лампочка на проводе, холодный свет; выключатель на площадке лестницы
	buildLight("Basement", Vector3.new(0, -2.4, 4), { axis = "x", c = 4, along = -20, side = 1, floor = F1 }, Vector3.new(6, FB + 3.1, 14.6), { style = "bare", wire = 1.0, range = 12, brightness = 0.8, color = C.ColdLight })
	-- Крыльцо: фонарь у двери снаружи; выключатель внутри у входной двери
	buildLight("Porch", Vector3.new(3.6, F1 + 6.5, -16.9), { axis = "x", c = -16, along = -3.2, side = 1, floor = F1 }, Vector3.new(-6, F1 + 3.3, -23), { style = "lantern", range = 14, brightness = 1.0 })
	-- Сарай: одна лампочка
	buildLight("Shed", Vector3.new(30, 6.2, 45), { axis = "x", c = 40, along = 27.5, side = 1, floor = G }, Vector3.new(33.4, 3.5, 47), { style = "bare", wire = 0.6, range = 14, brightness = 1.0 })
end

----------------------------------------------------------------------
-- Мебель: сборщики. cf — опорная точка на полу (центр предмета), локальная ось -Z = "лицо" предмета.
----------------------------------------------------------------------
local function lookCF(pos: Vector3, target: Vector3): CFrame
	local look = (target - pos)
	look = Vector3.new(look.X, 0, look.Z).Unit
	local up = Vector3.new(0, 1, 0)
	local vX = look:Cross(up).Unit
	local vZ = -look
	local vY = vZ:Cross(vX)
	return CFrame.fromMatrix(pos, vX, vY)
end

local function fbox(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material, isDeco: boolean?, extra)
	return box(parent, name, cf, size, color, material, if isDeco then "deco" else "furn", extra)
end

local function couch(parent: Instance, cf: CFrame, len: number, color: Color3)
	local m = model("Couch", parent)
	local c = vary(color, 0.03)
	fbox(m, "Seat", cf * CFrame.new(0, 0.8, 0.2), Vector3.new(len, 1.6, 2.6), c, M.Fabric)
	fbox(m, "Back", cf * CFrame.new(0, 1.9, 1.2), Vector3.new(len, 2.2, 0.7), c, M.Fabric)
	fbox(m, "Arm", cf * CFrame.new(-len / 2 + 0.3, 1.3, 0.1), Vector3.new(0.6, 2.6, 2.8), c, M.Fabric)
	fbox(m, "Arm", cf * CFrame.new(len / 2 - 0.3, 1.3, 0.1), Vector3.new(0.6, 2.6, 2.8), c, M.Fabric)
	local n = math.floor(len / 2.4)
	for i = 1, n do
		local x = -len / 2 + 0.6 + (i - 0.5) * ((len - 1.2) / n)
		fbox(m, "Cushion", cf * CFrame.new(x, 1.75, 0.0), Vector3.new((len - 1.2) / n - 0.15, 0.35, 2.2), vary(color, 0.06), M.Fabric, true)
	end
	for _, o in { { -len / 2 + 0.4, -1.0 }, { len / 2 - 0.4, -1.0 }, { -len / 2 + 0.4, 1.3 }, { len / 2 - 0.4, 1.3 } } do
		fbox(m, "Leg", cf * CFrame.new(o[1], 0.1, o[2]), Vector3.new(0.3, 0.2, 0.3), C.WoodDark, M.Wood, true)
	end
	return m
end

local function armchair(parent: Instance, cf: CFrame, color: Color3)
	local m = model("Armchair", parent)
	fbox(m, "Seat", cf * CFrame.new(0, 0.8, 0.1), Vector3.new(2.8, 1.6, 2.4), color, M.Fabric)
	fbox(m, "Back", cf * CFrame.new(0, 2.0, 1.0), Vector3.new(2.8, 2.4, 0.6), color, M.Fabric)
	fbox(m, "Arm", cf * CFrame.new(-1.2, 1.3, 0), Vector3.new(0.5, 2.6, 2.4), color, M.Fabric)
	fbox(m, "Arm", cf * CFrame.new(1.2, 1.3, 0), Vector3.new(0.5, 2.6, 2.4), color, M.Fabric)
	fbox(m, "Cushion", cf * CFrame.new(0, 1.75, -0.1), Vector3.new(1.7, 0.35, 2.0), vary(color, 0.06), M.Fabric, true)
	return m
end

local function table4(parent: Instance, name: string, cf: CFrame, w: number, d: number, h: number, color: Color3, material)
	local m = model(name, parent)
	fbox(m, "Top", cf * CFrame.new(0, h - 0.15, 0), Vector3.new(w, 0.3, d), color, material or M.Wood)
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		fbox(m, "Leg", cf * CFrame.new(o[1] * (w / 2 - 0.3), (h - 0.3) / 2, o[2] * (d / 2 - 0.3)), Vector3.new(0.3, h - 0.3, 0.3), C.WoodDark, M.Wood, true, { CanCollide = true })
	end
	return m
end

local function chair(parent: Instance, cf: CFrame, color: Color3)
	local m = model("Chair", parent)
	fbox(m, "Seat", cf * CFrame.new(0, 1.6, 0), Vector3.new(1.6, 0.2, 1.6), color, M.Wood)
	fbox(m, "Back", cf * CFrame.new(0, 2.7, 0.7), Vector3.new(1.6, 2.0, 0.2), color, M.Wood)
	for _, o in { { -0.65, -0.65 }, { 0.65, -0.65 }, { -0.65, 0.65 }, { 0.65, 0.65 } } do
		fbox(m, "Leg", cf * CFrame.new(o[1], 0.75, o[2]), Vector3.new(0.18, 1.5, 0.18), C.WoodDark, M.Wood, true)
	end
	return m
end

-- Кровать: w x len, высота ножек legH; изголовье со стороны +Z
local function bed(parent: Instance, name: string, cf: CFrame, w: number, len: number, legH: number, sheet: Color3, blanket: Color3)
	local m = model(name, parent)
	fbox(m, "Frame", cf * CFrame.new(0, legH + 0.3, 0), Vector3.new(w, 0.6, len), C.WoodDark, M.Wood)
	fbox(m, "Mattress", cf * CFrame.new(0, legH + 1.0, 0), Vector3.new(w - 0.3, 0.8, len - 0.3), C.Mattress, M.Fabric)
	fbox(m, "Blanket", cf * CFrame.new(0, legH + 1.5, -0.9), Vector3.new(w - 0.2, 0.3, len - 2.6), blanket, M.Fabric, true)
	fbox(m, "Sheet", cf * CFrame.new(0, legH + 1.45, len / 2 - 1.4), Vector3.new(w - 0.3, 0.12, 2.0), sheet, M.Fabric, true)
	if w > 4.5 then
		fbox(m, "Pillow", cf * CFrame.new(-w / 4, legH + 1.7, len / 2 - 0.9), Vector3.new(w / 2 - 0.6, 0.45, 1.3), C.Pillow, M.Fabric, true)
		fbox(m, "Pillow", cf * CFrame.new(w / 4, legH + 1.7, len / 2 - 0.9), Vector3.new(w / 2 - 0.6, 0.45, 1.3), C.Pillow, M.Fabric, true)
	else
		fbox(m, "Pillow", cf * CFrame.new(0, legH + 1.7, len / 2 - 0.9), Vector3.new(w - 1.2, 0.45, 1.3), C.Pillow, M.Fabric, true)
	end
	fbox(m, "Headboard", cf * CFrame.new(0, legH + 1.6, len / 2 + 0.15), Vector3.new(w, legH + 3.2, 0.3), C.WoodDark, M.Wood)
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		fbox(m, "Leg", cf * CFrame.new(o[1] * (w / 2 - 0.25), legH / 2, o[2] * (len / 2 - 0.25)), Vector3.new(0.4, legH, 0.4), C.WoodDark, M.Wood, true, { CanCollide = true })
	end
	return m
end

local function bookshelf(parent: Instance, cf: CFrame, w: number, h: number, color: Color3)
	local m = model("Bookshelf", parent)
	local d = 1.2
	fbox(m, "Side", cf * CFrame.new(-w / 2 + 0.1, h / 2, 0), Vector3.new(0.2, h, d), color, M.Wood)
	fbox(m, "Side", cf * CFrame.new(w / 2 - 0.1, h / 2, 0), Vector3.new(0.2, h, d), color, M.Wood)
	fbox(m, "Back", cf * CFrame.new(0, h / 2, d / 2 - 0.08), Vector3.new(w, h, 0.16), color, M.Wood)
	fbox(m, "Top", cf * CFrame.new(0, h - 0.1, 0), Vector3.new(w, 0.2, d), color, M.Wood)
	local shelves = math.floor(h / 1.8)
	for i = 0, shelves - 1 do
		local y = 0.3 + i * (h - 0.6) / shelves
		fbox(m, "Shelf", cf * CFrame.new(0, y, 0), Vector3.new(w - 0.4, 0.15, d), color, M.Wood, true)
		-- книги: несколько разноцветных блоков
		local x = -w / 2 + 0.5
		while x < w / 2 - 0.8 do
			local bw = randRange(0.25, 0.6)
			local bh = randRange(0.9, 1.3)
			fbox(m, "Book", cf * CFrame.new(x + bw / 2, y + bh / 2 + 0.08, 0.1), Vector3.new(bw, bh, 0.9), Color3.fromHSV(rand(), 0.45, randRange(0.35, 0.8)), M.SmoothPlastic, true)
			x += bw + randRange(0.02, 0.3)
			if rand() < 0.2 then
				x += 0.8
			end
		end
	end
	return m
end

local function desk(parent: Instance, cf: CFrame, w: number, color: Color3)
	local m = table4(parent, "Desk", cf, w, 2.4, 2.8, color, M.Wood)
	fbox(m, "Drawers", cf * CFrame.new(w / 2 - 0.9, 1.3, 0), Vector3.new(1.6, 2.4, 2.2), vary(color, 0.03), M.Wood)
	for i = 1, 3 do
		fbox(m, "Handle", cf * CFrame.new(w / 2 - 0.9, 0.5 + i * 0.6, -1.15), Vector3.new(0.6, 0.1, 0.1), C.MetalDark, M.Metal, true)
	end
	return m
end

local function pictureFrame(parent: Instance, cf: CFrame, w: number, h: number, pic: Color3)
	local m = model("Picture", parent)
	fbox(m, "Frame", cf, Vector3.new(w, h, 0.15), C.WoodDark, M.Wood, true)
	fbox(m, "Canvas", cf * CFrame.new(0, 0, -0.05), Vector3.new(w - 0.3, h - 0.3, 0.1), pic, M.SmoothPlastic, true)
	return m
end

local function rug(parent: Instance, cf: CFrame, w: number, d: number, color: Color3)
	local m = model("Rug", parent)
	fbox(m, "Rug", cf * CFrame.new(0, 0.04, 0), Vector3.new(w, 0.08, d), color, M.Fabric, true)
	fbox(m, "Border", cf * CFrame.new(0, 0.05, 0), Vector3.new(w + 0.4, 0.06, d + 0.4), vary(color, 0.1), M.Fabric, true)
	return m
end

local function lamp(parent: Instance, cf: CFrame, h: number, lit: boolean?)
	local m = model("Lamp", parent)
	fbox(m, "Base", cf * CFrame.new(0, 0.1, 0), Vector3.new(0.8, 0.2, 0.8), C.MetalDark, M.Metal, true)
	fbox(m, "Pole", cf * CFrame.new(0, h / 2, 0), Vector3.new(0.12, h, 0.12), C.MetalDark, M.Metal, true)
	local shade = fbox(m, "Shade", cf * CFrame.new(0, h + 0.5, 0), Vector3.new(1.4, 1.0, 1.4), Color3.fromRGB(230, 214, 180), M.Fabric, true)
	local _ = shade, lit
	return m
end

local function plant(parent: Instance, cf: CFrame, h: number)
	local m = model("Plant", parent)
	fbox(m, "Pot", cf * CFrame.new(0, 0.5, 0), Vector3.new(1.2, 1.0, 1.2), Color3.fromRGB(150, 90, 70), M.SmoothPlastic, true, { CanCollide = true })
	fbox(m, "Leaves", cf * CFrame.new(0, 1.0 + h / 2, 0), Vector3.new(1.8, h, 1.8), vary(C.Crown2, 0.06), M.Grass, true, { Shape = Enum.PartType.Ball })
	return m
end

local function cabinet(parent: Instance, name: string, cf: CFrame, w: number, h: number, d: number, color: Color3, handles: number?)
	local m = model(name, parent)
	fbox(m, "Body", cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), color, M.Wood)
	fbox(m, "Top", cf * CFrame.new(0, h + 0.08, 0), Vector3.new(w + 0.2, 0.16, d + 0.2), vary(color, 0.05), M.Wood, true)
	for i = 1, handles or 2 do
		local x = -w / 2 + (i - 0.5) * (w / (handles or 2))
		fbox(m, "Handle", cf * CFrame.new(x, h * 0.55, -d / 2 - 0.08), Vector3.new(0.5, 0.12, 0.12), C.MetalDark, M.Metal, true)
	end
	return m
end

local function boxCrate(parent: Instance, cf: CFrame, size: Vector3, isDeco: boolean?)
	local m = model("Box", parent)
	fbox(m, "Box", cf * CFrame.new(0, size.Y / 2, 0), size, vary(Color3.fromRGB(170, 140, 100), 0.05), M.SmoothPlastic, isDeco)
	fbox(m, "Tape", cf * CFrame.new(0, size.Y + 0.02, 0), Vector3.new(0.5, 0.04, size.Z + 0.02), Color3.fromRGB(190, 170, 130), M.SmoothPlastic, true)
	return m
end

-- Шкаф с жалюзийными дверцами (укрытие): лицо = -Z локально. Возвращает model Body, часть Door и CFrame внутренней точки.
local function wardrobe(parent: Instance, cf: CFrame, w: number, d: number, h: number, color: Color3)
	local body = model("Body", parent)
	fbox(body, "Side", cf * CFrame.new(-w / 2 + 0.1, h / 2, 0), Vector3.new(0.2, h, d), color, M.Wood)
	fbox(body, "Side", cf * CFrame.new(w / 2 - 0.1, h / 2, 0), Vector3.new(0.2, h, d), color, M.Wood)
	fbox(body, "Back", cf * CFrame.new(0, h / 2, d / 2 - 0.08), Vector3.new(w, h, 0.16), color, M.Wood)
	fbox(body, "Top", cf * CFrame.new(0, h - 0.1, 0), Vector3.new(w, 0.2, d), color, M.Wood)
	fbox(body, "Bottom", cf * CFrame.new(0, 0.15, 0), Vector3.new(w, 0.3, d), color, M.Wood)
	fbox(body, "Rail", cf * CFrame.new(0, h - 1.2, 0.2), Vector3.new(w - 0.6, 0.1, 0.1), C.Metal, M.Metal, true)
	-- пара вещей на вешалках (справа, чтобы слева было место стоять)
	for i = 1, 2 do
		fbox(body, "Coat", cf * CFrame.new(w / 4 + (i - 1.5) * 0.5, h - 2.9, 0.2), Vector3.new(0.3, 3.2, 1.1), Color3.fromHSV(rand(), 0.4, 0.5), M.Fabric, true)
	end
	-- Две жалюзийные створки: стойки/перекладины + наклонные ламели
	local leafW = w / 2 - 0.05
	local zf = -d / 2 + 0.1
	local slatColor = vary(color, 0.04)
	for _, sx in { -leafW / 2 - 0.025, leafW / 2 + 0.025 } do
		fbox(body, "Stile", cf * CFrame.new(sx - leafW / 2 + 0.15, h / 2, zf), Vector3.new(0.3, h - 0.5, 0.16), color, M.Wood, true)
		fbox(body, "Stile", cf * CFrame.new(sx + leafW / 2 - 0.15, h / 2, zf), Vector3.new(0.3, h - 0.5, 0.16), color, M.Wood, true)
		fbox(body, "Rail", cf * CFrame.new(sx, h - 0.55, zf), Vector3.new(leafW, 0.6, 0.16), color, M.Wood, true)
		fbox(body, "Rail", cf * CFrame.new(sx, 0.65, zf), Vector3.new(leafW, 0.7, 0.16), color, M.Wood, true)
		fbox(body, "Knob", cf * CFrame.new(sx + (if sx < 0 then leafW / 2 - 0.5 else -leafW / 2 + 0.5), h * 0.5, zf - 0.15), Vector3.new(0.2, 0.2, 0.2), C.MetalDark, M.Metal, true)
		local y = 1.3
		while y < h - 1.0 do
			fbox(body, "Slat", cf * CFrame.new(sx, y, zf) * CFrame.Angles(rad(-32), 0, 0), Vector3.new(leafW - 0.6, 0.25, 0.08), slatColor, M.Wood, true)
			y += 0.7
		end
	end
	local door = part({
		Name = "Door",
		CFrame = cf * CFrame.new(0, h / 2, -d / 2 + 0.1),
		Size = Vector3.new(w, h, 0.2),
		Transparency = 1,
		CanCollide = true,
		CanQuery = true,
		CanTouch = false,
		CastShadow = false,
	}, parent)
	return body, door
end

----------------------------------------------------------------------
-- Мебель: 1-й этаж
----------------------------------------------------------------------
do
	local Fu = furniture
	local y = F1
	-- Living: TV-тумба у западной стены, диван лицом к ней, журнальный столик, ковёр, книжный шкаф у z=4
	cabinet(Fu, "TVStand", CFrame.new(-22.4, y, -6) * CFrame.Angles(0, rad(-90), 0), 7, 2.0, 1.8, C.WoodDark, 3)
	couch(Fu, CFrame.new(-12.6, y, -6) * CFrame.Angles(0, rad(90), 0), 7.5, C.Fabric)
	table4(Fu, "CoffeeTable", CFrame.new(-17, y, -6), 4, 2.4, 1.4, C.Wood)
	rug(Fu, CFrame.new(-17, y, -6), 9, 7.5, Color3.fromRGB(110, 70, 60))
	armchair(Fu, CFrame.new(-9, y, 1) * CFrame.Angles(0, rad(180), 0), C.Fabric2) -- место Веспер
	bookshelf(Fu, CFrame.new(-14, y, 2.9) * CFrame.Angles(0, rad(180), 0), 6, 7, C.WoodDark)
	table4(Fu, "SideTable", CFrame.new(-21.5, y, 1.8), 1.6, 1.6, 2.2, C.WoodDark)
	lamp(Fu, CFrame.new(-21.5, y + 2.2, 1.8), 1.8)
	plant(Fu, CFrame.new(-22.5, y, -14.5), 2.4)
	pictureFrame(Fu, CFrame.new(-14, y + 6.2, -15.42), 3, 2.2, Color3.fromRGB(70, 90, 120))
	pictureFrame(Fu, CFrame.new(-6, y + 6.2, -15.42), 1.8, 2.4, Color3.fromRGB(120, 100, 70))
	-- Часы на стене x=-4 (лицо к -X)
	do
		local m = model("Clock", Fu)
		fbox(m, "Face", CFrame.new(-4.55, y + 7.5, -1) * CFrame.Angles(0, rad(90), 0), Vector3.new(1.6, 1.6, 0.12), C.Trim, M.SmoothPlastic, true, { Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(-4.56, y + 7.5, -1) })
		fbox(m, "Hand", CFrame.new(-4.62, y + 7.75, -1), Vector3.new(0.06, 0.55, 0.06), C.MetalDark, M.Metal, true)
		fbox(m, "Hand", CFrame.new(-4.62, y + 7.5, -0.8), Vector3.new(0.06, 0.06, 0.45), C.MetalDark, M.Metal, true)
	end
	-- Foyer: консоль, вешалка, коврик
	cabinet(Fu, "Console", CFrame.new(-2.9, y, -11.5) * CFrame.Angles(0, rad(90), 0), 3, 2.8, 1.1, C.WoodDark, 1)
	fbox(Fu, "Bowl", CFrame.new(-2.9, y + 3.1, -11.5), Vector3.new(0.9, 0.3, 0.9), C.Metal, M.Metal, true)
	do
		local m = model("CoatRack", Fu)
		fbox(m, "Pole", CFrame.new(3.0, y + 3.2, -14.8), Vector3.new(0.3, 6.4, 0.3), C.WoodDark, M.Wood, true, { CanCollide = true })
		fbox(m, "Base", CFrame.new(3.0, y + 0.1, -14.8), Vector3.new(1.2, 0.2, 1.2), C.WoodDark, M.Wood, true)
		for i = 0, 3 do
			local a = i * math.pi / 2
			fbox(m, "Hook", CFrame.new(3.0 + math.cos(a) * 0.35, y + 6.0, -14.8 + math.sin(a) * 0.35) * CFrame.Angles(0, -a, 0), Vector3.new(0.5, 0.1, 0.1), C.MetalDark, M.Metal, true)
		end
		fbox(m, "Coat", CFrame.new(2.7, y + 4.4, -14.6), Vector3.new(0.9, 3.0, 0.5), Color3.fromRGB(60, 70, 90), M.Fabric, true)
	end
	rug(Fu, CFrame.new(-1, y, -12), 3.5, 5, Color3.fromRGB(80, 60, 50))
	pictureFrame(Fu, CFrame.new(-3.42, y + 6.5, -11.5) * CFrame.Angles(0, rad(90), 0), 2, 1.6, Color3.fromRGB(90, 110, 90))
	-- Kitchen: столешницы вдоль фронтальной стены, мойка под окном, плита, верхние шкафы, холодильник, остров
	do
		local counterColor = Color3.fromRGB(96, 92, 86)
		local cabColor = Color3.fromRGB(214, 206, 192)
		-- нижние шкафы x 8..23.5 (минус плита x 19..22)
		for _, seg in { { 8, 19 }, { 22, 23.5 } } do
			local w = seg[2] - seg[1]
			cabinet(Fu, "Counter", CFrame.new((seg[1] + seg[2]) / 2, y, -14.5) * CFrame.Angles(0, rad(180), 0), w, 2.85, 2.0, cabColor, math.max(1, math.floor(w / 2.5)))
			fbox(Fu, "Countertop", CFrame.new((seg[1] + seg[2]) / 2, y + 2.95, -14.4), Vector3.new(w + 0.1, 0.2, 2.2), counterColor, M.Granite)
		end
		-- мойка под окном
		fbox(Fu, "Sink", CFrame.new(14, y + 2.9, -14.5), Vector3.new(2.6, 0.5, 1.6), C.Metal, M.Metal, true)
		fbox(Fu, "Tap", CFrame.new(14, y + 3.6, -15.2), Vector3.new(0.12, 1.0, 0.12), C.Metal, M.Metal, true)
		-- плита
		do
			local m = model("Stove", Fu)
			fbox(m, "Body", CFrame.new(20.5, y + 1.5, -14.5), Vector3.new(3, 3.0, 2.0), C.Appliance, M.Metal)
			fbox(m, "Top", CFrame.new(20.5, y + 3.05, -14.5), Vector3.new(3, 0.1, 2.0), C.MetalDark, M.Metal, true)
			for _, o in { { -0.75, -0.45 }, { 0.75, -0.45 }, { -0.75, 0.45 }, { 0.75, 0.45 } } do
				fbox(m, "Burner", CFrame.new(20.5 + o[1], y + 3.12, -14.5 + o[2]), Vector3.new(0.8, 0.06, 0.8), Color3.fromRGB(30, 30, 30), M.Metal, true)
			end
			fbox(m, "Backsplash", CFrame.new(20.5, y + 3.6, -15.35), Vector3.new(3, 1.2, 0.3), C.Appliance, M.Metal, true)
			fbox(m, "OvenWindow", CFrame.new(20.5, y + 1.3, -13.45), Vector3.new(2.2, 1.0, 0.08), C.GlassDark, M.Glass, true)
		end
		-- верхние шкафы (не над окном x 11.5..16.5)
		for _, seg in { { 8, 11 }, { 17, 23.5 } } do
			local w = seg[2] - seg[1]
			fbox(Fu, "UpperCabinet", CFrame.new((seg[1] + seg[2]) / 2, y + 7.2, -14.8), Vector3.new(w, 2.6, 1.4), cabColor, M.Wood, true, { CastShadow = true })
			for i = 1, math.max(1, math.floor(w / 2.5)) do
				fbox(Fu, "Handle", CFrame.new(seg[1] + (i - 0.5) * (w / math.max(1, math.floor(w / 2.5))), y + 6.3, -14.05), Vector3.new(0.1, 0.5, 0.1), C.MetalDark, M.Metal, true)
			end
		end
		-- холодильник у восточной стены
		do
			local m = model("Fridge", Fu)
			fbox(m, "Body", CFrame.new(22.4, y + 3.3, -12.4), Vector3.new(2.2, 6.6, 2.2), C.Appliance, M.Metal)
			fbox(m, "Seam", CFrame.new(21.25, y + 4.4, -12.4), Vector3.new(0.04, 0.06, 2.1), C.MetalDark, M.Metal, true)
			fbox(m, "Handle", CFrame.new(21.15, y + 4.9, -12.4), Vector3.new(0.1, 1.6, 0.12), C.MetalDark, M.Metal, true)
			fbox(m, "Handle", CFrame.new(21.15, y + 2.4, -12.4), Vector3.new(0.1, 1.6, 0.12), C.MetalDark, M.Metal, true)
		end
		-- остров (укрытие для приседа, 3 стада)
		do
			local m = model("Island", Fu)
			fbox(m, "Body", CFrame.new(14, y + 1.4, -8), Vector3.new(6, 2.8, 3), cabColor, M.Wood)
			fbox(m, "Top", CFrame.new(14, y + 2.9, -8), Vector3.new(6.3, 0.2, 3.3), counterColor, M.Granite)
			fbox(m, "Bowl", CFrame.new(12.6, y + 3.15, -8), Vector3.new(1.0, 0.3, 1.0), Color3.fromRGB(190, 60, 50), M.SmoothPlastic, true)
			for _, dx in { -1.5, 1.5 } do
				fbox(m, "Stool", CFrame.new(14 + dx, y + 1.2, -5.6), Vector3.new(1.1, 0.2, 1.1), C.WoodDark, M.Wood, true, { CanCollide = true })
				fbox(m, "StoolLeg", CFrame.new(14 + dx, y + 0.6, -5.6), Vector3.new(0.3, 1.2, 0.3), C.MetalDark, M.Metal, true)
			end
		end
		-- мусорка, часы над аркой
		fbox(Fu, "TrashCan", CFrame.new(5.5, y + 1.2, -3.4), Vector3.new(1.2, 2.4, 1.2), C.MetalDark, M.Metal, false, { Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(5.5, y + 1.2, -3.4) * CFrame.Angles(0, 0, rad(90)) })
		do
			local m = model("KitchenClock", Fu)
			fbox(m, "Face", CFrame.new(8, y + 8.3, -2.56) * CFrame.Angles(0, rad(90), 0), Vector3.new(0.12, 1.4, 1.4), C.Trim, M.SmoothPlastic, true, { Shape = Enum.PartType.Cylinder })
			fbox(m, "Hand", CFrame.new(8, y + 8.5, -2.63), Vector3.new(0.06, 0.5, 0.06), C.MetalDark, M.Metal, true)
			fbox(m, "Hand", CFrame.new(8.2, y + 8.3, -2.63), Vector3.new(0.4, 0.06, 0.06), C.MetalDark, M.Metal, true)
		end
	end
	-- Dining: стол, 6 стульев, буфет, витрина, ковёр
	table4(Fu, "DiningTable", CFrame.new(14, y, 7), 8, 4, 2.8, C.Wood)
	rug(Fu, CFrame.new(14, y, 7), 12, 8, Color3.fromRGB(80, 80, 100))
	for _, cx in { 11.5, 14, 16.5 } do
		chair(Fu, CFrame.new(cx, y, 3.9) * CFrame.Angles(0, rad(180), 0), C.WoodDark)
		chair(Fu, CFrame.new(cx, y, 10.1), C.WoodDark)
	end
	cabinet(Fu, "Sideboard", CFrame.new(11, y, 14.8) * CFrame.Angles(0, rad(180), 0), 6, 2.8, 1.3, C.WoodDark, 3)
	fbox(Fu, "Vase", CFrame.new(10, y + 3.5, 14.8), Vector3.new(0.7, 1.2, 0.7), Color3.fromRGB(80, 110, 140), M.Glass, true)
	pictureFrame(Fu, CFrame.new(11, y + 6.5, 15.42) * CFrame.Angles(0, rad(180), 0), 3.4, 2.4, Color3.fromRGB(110, 120, 90))
	bookshelf(Fu, CFrame.new(21.5, y, 14.6) * CFrame.Angles(0, rad(180), 0), 3.5, 7, C.WoodDark)
	plant(Fu, CFrame.new(5.6, y, 14.6), 2.8)
	pictureFrame(Fu, CFrame.new(4.58, y + 6, 8) * CFrame.Angles(0, rad(-90), 0), 2.6, 2, Color3.fromRGB(90, 70, 60))
	-- Laundry: стиралка, сушилка, полка, корзина, швабра
	for i, name in { "Washer", "Dryer" } do
		local m = model(name, Fu)
		local cx = -21.8 + (i - 1) * 2.4
		fbox(m, "Body", CFrame.new(cx, y + 1.6, 14.5), Vector3.new(2.2, 3.2, 2.0), C.Appliance, M.Metal)
		fbox(m, "Door", CFrame.new(cx, y + 1.4, 13.46) * CFrame.Angles(0, rad(90), 0), Vector3.new(0.1, 1.5, 1.5), C.GlassDark, M.Glass, true, { Shape = Enum.PartType.Cylinder })
		fbox(m, "Panel", CFrame.new(cx, y + 2.9, 13.5), Vector3.new(2.0, 0.4, 0.1), C.MetalDark, M.Metal, true)
	end
	fbox(Fu, "Shelf", CFrame.new(-19, y + 6.2, 15.0), Vector3.new(8, 0.2, 1.0), C.Wood, M.Wood, true, { CastShadow = true })
	for i = 1, 4 do
		fbox(Fu, "Bottle", CFrame.new(-22 + i * 1.4, y + 6.8, 15.0), Vector3.new(0.6, 1.1, 0.6), Color3.fromHSV(rand(), 0.5, 0.8), M.SmoothPlastic, true)
	end
	cabinet(Fu, "Cabinet", CFrame.new(-14.5, y, 14.9) * CFrame.Angles(0, rad(180), 0), 3, 3, 1.2, C.WallInt, 2)
	fbox(Fu, "Basket", CFrame.new(-16.8, y + 0.8, 14.6), Vector3.new(1.6, 1.6, 1.4), Color3.fromRGB(200, 190, 170), M.Fabric)
	fbox(Fu, "Mop", CFrame.new(-23.2, y + 2.6, 10.2) * CFrame.Angles(0, 0, rad(8)), Vector3.new(0.12, 5.2, 0.12), C.Wood, M.Wood, true)
	fbox(Fu, "Bucket", CFrame.new(-22.6, y + 0.6, 10.3), Vector3.new(1.1, 1.2, 1.1), C.Metal, M.Metal, true)
	-- BackHall: скамья, крючки, обувь, коврик
	fbox(Fu, "Bench", CFrame.new(-8, y + 1.5, 10.2), Vector3.new(6, 0.3, 1.2), C.Wood, M.Wood)
	fbox(Fu, "BenchLeg", CFrame.new(-10.6, y + 0.7, 10.2), Vector3.new(0.3, 1.4, 1.0), C.WoodDark, M.Wood, true)
	fbox(Fu, "BenchLeg", CFrame.new(-5.4, y + 0.7, 10.2), Vector3.new(0.3, 1.4, 1.0), C.WoodDark, M.Wood, true)
	for i = 1, 4 do
		fbox(Fu, "Hook", CFrame.new(-10.5 + i * 1.2, y + 6, 9.65), Vector3.new(0.15, 0.4, 0.3), C.MetalDark, M.Metal, true)
	end
	fbox(Fu, "Coat", CFrame.new(-8.1, y + 4.3, 9.9), Vector3.new(1.0, 3.0, 0.4), Color3.fromRGB(110, 60, 40), M.Fabric, true)
	fbox(Fu, "Boots", CFrame.new(-9.5, y + 0.5, 11.2), Vector3.new(0.9, 1.0, 1.2), C.MetalDark, M.Fabric, true)
	rug(Fu, CFrame.new(-8, y, 13), 5, 3.5, Color3.fromRGB(70, 70, 80))
end
