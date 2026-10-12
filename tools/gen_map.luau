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
	{ id = "KidRoomDoor", kind = "Interior", axis = "z", c = -4.5, a = -14, b = -10, y = F2, roomA = "UpperHall", roomB = "KidRoom" },
	{ id = "ParentsRoomDoor", kind = "Interior", axis = "z", c = 4.5, a = -14, b = -10, y = F2, roomA = "UpperHall", roomB = "ParentsRoom" },
	{ id = "OfficeDoor", kind = "Interior", axis = "z", c = -4.5, a = 4, b = 8, y = F2, roomA = "UpperHall", roomB = "Office" },
	{ id = "BathroomDoor", kind = "Interior", axis = "z", c = 4.5, a = 11.5, b = 15.5, y = F2, roomA = "UpperHall", roomB = "Bathroom" },
}
-- Арки без дверей (проёмы 4x7.5)
local ARCHES = {
	{ axis = "z", c = -4.5, a = -8, b = -4, y = F1 }, -- Foyer -> Living
	{ axis = "z", c = 4.5, a = -15, b = -11, y = F1 }, -- Foyer -> Kitchen
	{ axis = "x", c = -2, a = 12, b = 16, y = F1 }, -- Kitchen -> Dining
	{ axis = "z", c = -4.5, a = 11.5, b = 15.5, y = F1 }, -- Foyer -> BackHall
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
		for i = 1, 4 do
			local y0 = F1 + (i - 1) * 2
			bbox(S, "GarageDoor", 27, 39, y0, y0 + 2, -16.2, -15.85, vary(C.Trim, 0.01), M.Metal, "solid")
			bbox(S, "GarageDoorGroove", 27.2, 38.8, y0 + 1.9, y0 + 2.1, -16.25, -16.15, C.SidingDark, M.Metal, "deco")
		end
		bbox(S, "GarageDoorHandle", 32.4, 33.6, 3.4, 3.8, -16.4, -16.2, C.MetalDark, M.Metal, "deco")
	end
	-- Внутренние стены 1-го этажа (y 0..10)
	wall(S, "Wall", "z", -4.5, -16, 16, F1, H1, C.WallInt, M.SmoothPlastic, openingsFor("z", -4.5, F1))
	wall(S, "Wall", "z", 4.5, -16, 16, F1, H1, C.WallInt, M.SmoothPlastic, openingsFor("z", 4.5, F1))
	wall(S, "Wall", "x", 4, -24, -4, F1, H1, C.WallInt2, M.SmoothPlastic) -- Living / лестница в подвал
	wall(S, "Wall", "x", 9, -24, -4, F1, H1, C.WallInt2, M.SmoothPlastic, openingsFor("x", 9, F1)) -- лестница в подвал / Laundry+BackHall
	wall(S, "Wall", "x", -2, 4, 24, F1, H1, C.WallInt, M.SmoothPlastic, openingsFor("x", -2, F1)) -- Kitchen / Dining
	wall(S, "Wall", "z", -12, 9, 16, F1, H1, C.WallInt2, M.SmoothPlastic, openingsFor("z", -12, F1)) -- Laundry / BackHall
	-- Внутренние стены 2-го этажа (y 11..21)
	wall(S, "Wall", "z", -4.5, -16, 16, F2, H2, C.WallKid, M.SmoothPlastic, openingsFor("z", -4.5, F2))
	wall(S, "Wall", "z", 4.5, -16, 16, F2, H2, C.WallInt, M.SmoothPlastic, openingsFor("z", 4.5, F2))
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
	for _, r in { { -23.5, -5, -15.5, 3.5 }, { 5, 23.5, -15.5, -2.5 }, { 5, 23.5, -1.5, 15.5 } } do
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
		local len = math.sqrt(20 ^ 2 + 10 ^ 2)
		local up = Vector3.new(0, 20, -10).Unit
		local mid = Vector3.new(0.3, F1 + 5 + 2.2, 0)
		local cf = CFrame.fromMatrix(mid, Vector3.new(1, 0, 0), up)
		box(S, "StairRail", cf, Vector3.new(0.3, 3.2, len), C.WoodDark, M.Wood, "solid", { CastShadow = false })
		box(S, "StairRail", cf * CFrame.new(0, 1.8, 0), Vector3.new(0.5, 0.4, len), C.WoodLight, M.Wood, "deco")
	end
	-- Ограждение дыры на 2-м этаже: вдоль x=0 (z -2..10) и вдоль z=-2 (x 0..4)
	for _, seg in { { 0.3, -1.7, 0.3, 10 }, { 0.3, -1.7, 4, -1.7 } } do
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
		local up = Vector3.new(10, 20, 0).Unit
		local cf = CFrame.fromMatrix(Vector3.new(-7, -2.25, 8.3), Vector3.new(0, 0, -1), up)
		box(S, "StairRail", cf, Vector3.new(0.3, 0.3, 21.2), C.MetalDark, M.Metal, "deco")
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
	buildLight("Foyer", Vector3.new(0, y1, -8), { axis = "x", c = -16, along = 3.2, side = 1, floor = F1 }, Vector3.new(-3.4, F1 + 3.4, -10.4))
	buildLight("Living", Vector3.new(-14, y1, -6), { axis = "z", c = -4.5, along = -9.5, side = -1, floor = F1 }, Vector3.new(-15, F1 + 1.8, -6))
	buildLight("Kitchen", Vector3.new(14, y1, -9), { axis = "z", c = 4.5, along = -10, side = 1, floor = F1 }, Vector3.new(14, F1 + 3.4, -9))
	buildLight("Dining", Vector3.new(14, y1, 7), { axis = "x", c = -2, along = 17, side = 1, floor = F1 }, Vector3.new(14, F1 + 3.2, 6))
	buildLight("Laundry", Vector3.new(-18, y1, 12.5), { axis = "z", c = -12, along = 15.2, side = -1, floor = F1 }, Vector3.new(-22, F1 + 3.7, 14.4))
	buildLight("BackHall", Vector3.new(-8, y1, 12.5), { axis = "x", c = 16, along = -5, side = -1, floor = F1 }, Vector3.new(-6.2, F1 + 2.1, 10.3))
	buildLight("Garage", Vector3.new(33, y1, -7), { axis = "z", c = 24, along = -3.5, side = 1, floor = F1 }, Vector3.new(28.2, F1 + 3.45, 1.0), { style = "tube", color = Color3.fromRGB(236, 240, 230) })
	-- 2-й этаж
	buildLight("KidRoom", Vector3.new(-14, y2, -8), { axis = "z", c = -4.5, along = -9, side = -1, floor = F2 }, Vector3.new(-16, F2 + 3.25, -14.3))
	buildLight("ParentsRoom", Vector3.new(14, y2, -8), { axis = "z", c = 4.5, along = -9, side = 1, floor = F2 }, Vector3.new(12.5, F2 + 3.6, -14.3))
	buildLight("UpperHall", Vector3.new(0, y2, -6), { axis = "z", c = -4.5, along = 2, side = 1, floor = F2 }, Vector3.new(0, F2 + 3.4, -15.0))
	buildLight("Office", Vector3.new(-14, y2, 8), { axis = "z", c = -4.5, along = 9, side = -1, floor = F2 }, Vector3.new(-18.6, F2 + 3.25, 13.6))
	buildLight("Bathroom", Vector3.new(14, y2, 8), { axis = "z", c = 4.5, along = 10.5, side = 1, floor = F2 }, Vector3.new(6.8, F2 + 3.6, 1.5))
	-- Подвал: голая лампочка на проводе, холодный свет; выключатель на площадке лестницы
	buildLight("Basement", Vector3.new(0, -2.4, 4), { axis = "x", c = 4, along = -20, side = 1, floor = F1 }, Vector3.new(5.5, FB + 3.25, 15.0), { style = "bare", wire = 1.0, range = 12, brightness = 0.8, color = C.ColdLight })
	-- Крыльцо: фонарь у двери снаружи; выключатель внутри у входной двери
	buildLight("Porch", Vector3.new(3.6, F1 + 6.5, -16.9), { axis = "x", c = -16, along = 2.5, side = 1, floor = F1 }, Vector3.new(-6, F1 + 3.3, -23), { style = "lantern", range = 14, brightness = 1.0 })
	-- Сарай: одна лампочка
	buildLight("Shed", Vector3.new(30, 6.2, 45), { axis = "x", c = 40, along = 27.5, side = 1, floor = G }, Vector3.new(34.05, 3.5, 44.5), { style = "bare", wire = 0.6, range = 14, brightness = 1.0 })
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

local function lamp(parent: Instance, cf: CFrame, h: number)
	local m = model("Lamp", parent)
	fbox(m, "Base", cf * CFrame.new(0, 0.1, 0), Vector3.new(0.8, 0.2, 0.8), C.MetalDark, M.Metal, true)
	fbox(m, "Pole", cf * CFrame.new(0, h / 2, 0), Vector3.new(0.12, h, 0.12), C.MetalDark, M.Metal, true)
	fbox(m, "Shade", cf * CFrame.new(0, h + 0.5, 0), Vector3.new(1.4, 1.0, 1.4), Color3.fromRGB(230, 214, 180), M.Fabric, true)
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
	armchair(Fu, CFrame.new(-21.6, y, 1.6) * CFrame.Angles(0, rad(-135), 0), C.Fabric2) -- угол у окна; Веспер садится рядом
	bookshelf(Fu, CFrame.new(-14, y, 2.9) * CFrame.Angles(0, rad(180), 0), 6, 7, C.WoodDark)
	table4(Fu, "SideTable", CFrame.new(-22.5, y, -14.5), 1.6, 1.6, 2.2, C.WoodDark)
	lamp(Fu, CFrame.new(-22.5, y + 2.2, -14.5), 1.8)
	plant(Fu, CFrame.new(-6, y, -14.5), 2.4)
	pictureFrame(Fu, CFrame.new(-14, y + 6.2, -15.42), 3, 2.2, Color3.fromRGB(70, 90, 120))
	pictureFrame(Fu, CFrame.new(-6, y + 6.2, -15.42), 1.8, 2.4, Color3.fromRGB(120, 100, 70))
	-- Часы на стене x=-4 (лицо к -X)
	do
		local m = model("Clock", Fu)
		fbox(m, "Face", CFrame.new(-5.06, y + 7.5, -1), Vector3.new(0.12, 1.6, 1.6), C.Trim, M.SmoothPlastic, true, { Shape = Enum.PartType.Cylinder })
		fbox(m, "Hand", CFrame.new(-5.14, y + 7.75, -1), Vector3.new(0.06, 0.55, 0.06), C.MetalDark, M.Metal, true)
		fbox(m, "Hand", CFrame.new(-5.14, y + 7.5, -0.8), Vector3.new(0.06, 0.06, 0.45), C.MetalDark, M.Metal, true)
	end
	-- Foyer: консоль, вешалка, коврик
	cabinet(Fu, "Console", CFrame.new(-3.4, y, -11.5) * CFrame.Angles(0, rad(90), 0), 3, 2.8, 1.1, C.WoodDark, 1)
	fbox(Fu, "Bowl", CFrame.new(-3.4, y + 3.1, -11.5), Vector3.new(0.9, 0.3, 0.9), C.Metal, M.Metal, true)
	do
		local m = model("CoatRack", Fu)
		fbox(m, "Pole", CFrame.new(-3.4, y + 3.2, -14.8), Vector3.new(0.3, 6.4, 0.3), C.WoodDark, M.Wood, true, { CanCollide = true })
		fbox(m, "Base", CFrame.new(-3.4, y + 0.1, -14.8), Vector3.new(1.2, 0.2, 1.2), C.WoodDark, M.Wood, true)
		for i = 0, 3 do
			local a = i * math.pi / 2
			fbox(m, "Hook", CFrame.new(-3.4 + math.cos(a) * 0.35, y + 6.0, -14.8 + math.sin(a) * 0.35) * CFrame.Angles(0, -a, 0), Vector3.new(0.5, 0.1, 0.1), C.MetalDark, M.Metal, true)
		end
		fbox(m, "Coat", CFrame.new(-3.1, y + 4.4, -14.5), Vector3.new(0.9, 3.0, 0.5), Color3.fromRGB(60, 70, 90), M.Fabric, true)
	end
	rug(Fu, CFrame.new(-1, y, -12), 3.5, 5, Color3.fromRGB(80, 60, 50))
	pictureFrame(Fu, CFrame.new(-3.92, y + 6.5, -11.5) * CFrame.Angles(0, rad(90), 0), 2, 1.6, Color3.fromRGB(90, 110, 90))
	-- Kitchen: столешницы вдоль фронтальной стены, мойка под окном, плита, верхние шкафы, холодильник, остров
	do
		local counterColor = Color3.fromRGB(96, 92, 86)
		local cabColor = Color3.fromRGB(214, 206, 192)
		-- нижние шкафы x 8..23.5 (минус плита x 19..22)
		for _, seg in { { 9.5, 19 }, { 22, 23.5 } } do
			local w = seg[2] - seg[1]
			cabinet(Fu, "Counter", CFrame.new((seg[1] + seg[2]) / 2, y, -14.5) * CFrame.Angles(0, rad(180), 0), w, 2.85, 2.0, cabColor, math.max(1, math.floor(w / 2.5)))
			fbox(Fu, "Countertop", CFrame.new((seg[1] + seg[2]) / 2, y + 2.95, -14.5), Vector3.new(w, 0.2, 2.0), counterColor, M.Granite)
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
		for _, seg in { { 9.5, 11 }, { 17, 23.5 } } do
			local w = seg[2] - seg[1]
			fbox(Fu, "UpperCabinet", CFrame.new((seg[1] + seg[2]) / 2, y + 7.2, -14.8), Vector3.new(w, 2.6, 1.4), cabColor, M.Wood, true, { CastShadow = true })
			for i = 1, math.max(1, math.floor(w / 2.5)) do
				fbox(Fu, "Handle", CFrame.new(seg[1] + (i - 0.5) * (w / math.max(1, math.floor(w / 2.5))), y + 6.3, -14.05), Vector3.new(0.1, 0.5, 0.1), C.MetalDark, M.Metal, true)
			end
		end
		-- холодильник у восточной стены
		do
			local m = model("Fridge", Fu)
			fbox(m, "Body", CFrame.new(22.5, y + 3.3, -12.5), Vector3.new(2.0, 6.6, 2.0), C.Appliance, M.Metal)
			fbox(m, "Seam", CFrame.new(21.45, y + 4.4, -12.5), Vector3.new(0.04, 0.06, 1.9), C.MetalDark, M.Metal, true)
			fbox(m, "Handle", CFrame.new(21.35, y + 4.9, -12.5), Vector3.new(0.1, 1.6, 0.12), C.MetalDark, M.Metal, true)
			fbox(m, "Handle", CFrame.new(21.35, y + 2.4, -12.5), Vector3.new(0.1, 1.6, 0.12), C.MetalDark, M.Metal, true)
		end
		-- остров (укрытие для приседа, 3 стада)
		do
			local m = model("Island", Fu)
			fbox(m, "Body", CFrame.new(14, y + 1.4, -8), Vector3.new(5.8, 2.8, 2.8), cabColor, M.Wood)
			fbox(m, "Top", CFrame.new(14, y + 2.9, -8), Vector3.new(6, 0.2, 3), counterColor, M.Granite)
			fbox(m, "Bowl", CFrame.new(12.6, y + 3.15, -8), Vector3.new(1.0, 0.3, 1.0), Color3.fromRGB(190, 60, 50), M.SmoothPlastic, true)
			for _, dx in { -1.5, 1.5 } do
				fbox(m, "Stool", CFrame.new(14 + dx, y + 1.2, -5.6), Vector3.new(1.1, 0.2, 1.1), C.WoodDark, M.Wood, true)
				fbox(m, "StoolLeg", CFrame.new(14 + dx, y + 0.6, -5.6), Vector3.new(0.3, 1.2, 0.3), C.MetalDark, M.Metal, true)
			end
		end
		-- мусорка, часы над аркой
		fbox(Fu, "TrashCan", CFrame.new(22.9, y + 1.2, -3.2) * CFrame.Angles(0, 0, rad(90)), Vector3.new(2.4, 1.2, 1.2), C.MetalDark, M.Metal, false, { Shape = Enum.PartType.Cylinder })
		do
			local m = model("KitchenClock", Fu)
			fbox(m, "Face", CFrame.new(8, y + 8.3, -2.56) * CFrame.Angles(0, rad(90), 0), Vector3.new(0.12, 1.4, 1.4), C.Trim, M.SmoothPlastic, true, { Shape = Enum.PartType.Cylinder })
			fbox(m, "Hand", CFrame.new(8, y + 8.5, -2.63), Vector3.new(0.06, 0.5, 0.06), C.MetalDark, M.Metal, true)
			fbox(m, "Hand", CFrame.new(8.2, y + 8.3, -2.63), Vector3.new(0.4, 0.06, 0.06), C.MetalDark, M.Metal, true)
		end
	end
	-- Dining: стол, 6 стульев, буфет, витрина, ковёр
	table4(Fu, "DiningTable", CFrame.new(14.25, y, 7), 7, 4, 2.8, C.Wood)
	rug(Fu, CFrame.new(14, y, 7), 12, 8, Color3.fromRGB(80, 80, 100))
	for _, cx in { 11.75, 14.25, 16.75 } do
		chair(Fu, CFrame.new(cx, y, 3.9) * CFrame.Angles(0, rad(180), 0), C.WoodDark)
		chair(Fu, CFrame.new(cx, y, 10.1), C.WoodDark)
	end
	cabinet(Fu, "Sideboard", CFrame.new(5.7, y, 12.5) * CFrame.Angles(0, rad(-90), 0), 5.5, 2.8, 1.3, C.WoodDark, 3)
	fbox(Fu, "Vase", CFrame.new(5.7, y + 3.5, 11.5), Vector3.new(0.7, 1.2, 0.7), Color3.fromRGB(80, 110, 140), M.Glass, true)
	pictureFrame(Fu, CFrame.new(11, y + 6.5, 15.42) * CFrame.Angles(0, rad(180), 0), 3.4, 2.4, Color3.fromRGB(110, 120, 90))
	bookshelf(Fu, CFrame.new(21.5, y, 14.6) * CFrame.Angles(0, rad(180), 0), 3.5, 7, C.WoodDark)
	plant(Fu, CFrame.new(18.8, y, 14.9), 2.8)
	pictureFrame(Fu, CFrame.new(5.08, y + 6, 6) * CFrame.Angles(0, rad(-90), 0), 2.6, 2, Color3.fromRGB(90, 70, 60))
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
	cabinet(Fu, "WallCabinet", CFrame.new(-15.5, y + 4.6, 14.9) * CFrame.Angles(0, rad(180), 0), 2.6, 3, 1.2, C.WallInt, 2)
	fbox(Fu, "Basket", CFrame.new(-17.4, y + 0.8, 14.7), Vector3.new(1.2, 1.6, 1.2), Color3.fromRGB(200, 190, 170), M.Fabric)
	fbox(Fu, "Mop", CFrame.new(-23.2, y + 2.6, 10.2) * CFrame.Angles(0, 0, rad(8)), Vector3.new(0.12, 5.2, 0.12), C.Wood, M.Wood, true)
	fbox(Fu, "Bucket", CFrame.new(-22.6, y + 0.6, 10.3), Vector3.new(1.1, 1.2, 1.1), C.Metal, M.Metal, true)
	-- BackHall: скамья, крючки, обувь, коврик
	fbox(Fu, "Bench", CFrame.new(-6.2, y + 1.5, 10.2), Vector3.new(2.4, 0.3, 1.2), C.Wood, M.Wood)
	fbox(Fu, "BenchLeg", CFrame.new(-7.2, y + 0.7, 10.2), Vector3.new(0.3, 1.4, 1.0), C.WoodDark, M.Wood, true)
	fbox(Fu, "BenchLeg", CFrame.new(-5.4, y + 0.7, 10.2), Vector3.new(0.3, 1.4, 1.0), C.WoodDark, M.Wood, true)
	for i = 1, 3 do
		fbox(Fu, "Hook", CFrame.new(-7.8 + i * 0.8, y + 6, 9.65), Vector3.new(0.15, 0.4, 0.3), C.MetalDark, M.Metal, true)
	end
	fbox(Fu, "Coat", CFrame.new(-6.2, y + 4.3, 9.9), Vector3.new(1.0, 3.0, 0.4), Color3.fromRGB(110, 60, 40), M.Fabric, true)
	fbox(Fu, "Boots", CFrame.new(-5.8, y + 0.5, 11.3), Vector3.new(0.9, 1.0, 1.2), C.MetalDark, M.Fabric, true)
	rug(Fu, CFrame.new(-8, y, 13), 5, 3.5, Color3.fromRGB(70, 70, 80))
end

----------------------------------------------------------------------
-- Укрытия: сборщик модели (HidePoint, CamPoint, Prompt в HidePoint)
----------------------------------------------------------------------
local function hidingSpot(id: string, kind: string, room: string, hideCF: CFrame, camCF: CFrame, objectText: string)
	local m = model(id, hidingF, { HideId = id, Kind = kind, Room = room, Occupied = "" })
	local hp = marker({ Name = "HidePoint", CFrame = hideCF, Size = Vector3.new(1, 1, 1) }, m)
	marker({ Name = "CamPoint", CFrame = camCF, Size = Vector3.new(0.5, 0.5, 0.5) }, m)
	hp.CanQuery = true
	prompt(hp, "Prompt", "Hide", objectText, 0, 7)
	m.PrimaryPart = hp
	return m
end

local function closet(id: string, room: string, cf: CFrame, color: Color3)
	local m = hidingSpot(id, "Closet", room, cf * CFrame.new(-0.7, 0.5, 0.2), cf * CFrame.new(-0.7, 4.6, -0.55), "Closet")
	wardrobe(m, cf, 4, 2.2, 7.5, color)
	return m
end

----------------------------------------------------------------------
-- Мебель: 2-й этаж
----------------------------------------------------------------------
do
	local Fu = furniture
	local y = F2
	-- KidRoom
	do
		local bedCF = CFrame.new(-21.3, y, -3.9)
		local m = hidingSpot("BedKid", "Bed", "KidRoom", bedCF * CFrame.new(0, 0.5, 0), lookCF(Vector3.new(-19.4, y + 0.7, -3.9), Vector3.new(-10, y + 0.7, -3.9)), "Bed")
		bed(m, "Body", bedCF, 4, 7, 1.2, C.Sheet, Color3.fromRGB(70, 110, 160))
		closet("ClosetKid", "KidRoom", CFrame.new(-10, y, -1.6), C.WoodLight)
	end
	desk(Fu, CFrame.new(-18, y, -14.3) * CFrame.Angles(0, rad(180), 0), 5, C.WoodLight)
	chair(Fu, CFrame.new(-18, y, -12.6), C.WoodLight)
	fbox(Fu, "Laptop", CFrame.new(-18.6, y + 2.9, -14.5), Vector3.new(1.6, 0.12, 1.1), C.MetalDark, M.Metal, true)
	fbox(Fu, "LaptopScreen", CFrame.new(-18.6, y + 3.5, -15.0) * CFrame.Angles(rad(-15), 0, 0), Vector3.new(1.6, 1.1, 0.08), C.GlassDark, M.Glass, true)
	table4(Fu, "Nightstand", CFrame.new(-18.6, y, -1.6), 1.4, 1.4, 2.0, C.WoodLight)
	lamp(Fu, CFrame.new(-18.6, y + 2.0, -1.6), 1.2)
	boxCrate(Fu, CFrame.new(-12, y, -14.5), Vector3.new(2.6, 1.6, 1.6))
	fbox(Fu, "ToyBall", CFrame.new(-14, y + 0.4, -13.8), Vector3.new(0.8, 0.8, 0.8), C.Red, M.SmoothPlastic, true, { Shape = Enum.PartType.Ball })
	rug(Fu, CFrame.new(-14, y, -8), 8, 6, Color3.fromRGB(80, 110, 150))
	fbox(Fu, "WallShelf", CFrame.new(-5.5, y + 5.5, -6), Vector3.new(0.9, 0.15, 3.0), C.WoodLight, M.Wood, true, { CastShadow = true })
	for i = 1, 3 do
		fbox(Fu, "Toy", CFrame.new(-5.5, y + 5.95, -7 + i * 0.7), Vector3.new(0.6, 0.75, 0.5), Color3.fromHSV(rand(), 0.6, 0.85), M.SmoothPlastic, true)
	end
	pictureFrame(Fu, CFrame.new(-8, y + 6.5, -15.42), 2.4, 3.2, Color3.fromRGB(40, 60, 110))
	pictureFrame(Fu, CFrame.new(-16, y + 6.6, -0.58) * CFrame.Angles(0, rad(180), 0), 3.0, 2.0, Color3.fromRGB(120, 80, 100))
	-- ParentsRoom
	bed(Fu, "Bed", CFrame.new(14, y, -3.9), 6, 7, 0.8, C.Sheet, Color3.fromRGB(90, 70, 80))
	table4(Fu, "Nightstand", CFrame.new(10.2, y, -1.6), 1.6, 1.6, 2.2, C.WoodDark)
	table4(Fu, "Nightstand", CFrame.new(17.8, y, -1.6), 1.6, 1.6, 2.2, C.WoodDark)
	lamp(Fu, CFrame.new(17.8, y + 2.2, -1.6), 1.3)
	fbox(Fu, "Book", CFrame.new(10.2, y + 2.35, -1.6), Vector3.new(0.9, 0.3, 1.1), Color3.fromRGB(100, 50, 50), M.SmoothPlastic, true)
	cabinet(Fu, "Dresser", CFrame.new(12.5, y, -14.3) * CFrame.Angles(0, rad(180), 0), 5, 3.2, 2.0, C.WoodDark, 2)
	do
		local m = model("Mirror", Fu)
		fbox(m, "Frame", CFrame.new(12.5, y + 6.3, -15.42), Vector3.new(3.4, 3.0, 0.12), C.WoodDark, M.Wood, true)
		fbox(m, "Glass", CFrame.new(12.5, y + 6.3, -15.34), Vector3.new(3.0, 2.6, 0.06), Color3.fromRGB(170, 190, 200), M.Glass, true, { Reflectance = 0.6 })
	end
	closet("ClosetParents", "ParentsRoom", CFrame.new(22.4, y, -13) * CFrame.Angles(0, rad(90), 0), C.WoodDark)
	armchair(Fu, CFrame.new(6.6, y, -3.5) * CFrame.Angles(0, rad(-90), 0), Color3.fromRGB(120, 110, 100))
	rug(Fu, CFrame.new(14, y, -9.5), 9, 6, Color3.fromRGB(100, 90, 110))
	pictureFrame(Fu, CFrame.new(23.42, y + 6.4, -2.5) * CFrame.Angles(0, rad(-90), 0), 2.6, 2.0, Color3.fromRGB(80, 100, 80))
	-- UpperHall
	cabinet(Fu, "HallTable", CFrame.new(0, y, -15.0) * CFrame.Angles(0, rad(180), 0), 2.6, 2.8, 1.0, C.WoodDark, 1)
	fbox(Fu, "Vase", CFrame.new(0.7, y + 3.4, -15.0), Vector3.new(0.5, 0.9, 0.5), Color3.fromRGB(120, 90, 70), M.SmoothPlastic, true)
	rug(Fu, CFrame.new(-2, y, 4), 2.6, 16, Color3.fromRGB(110, 60, 60))
	pictureFrame(Fu, CFrame.new(-3.92, y + 6.3, -6) * CFrame.Angles(0, rad(90), 0), 2.2, 1.8, Color3.fromRGB(90, 90, 110))
	pictureFrame(Fu, CFrame.new(3.92, y + 6.3, -6) * CFrame.Angles(0, rad(-90), 0), 2.2, 1.8, Color3.fromRGB(110, 100, 80))
	pictureFrame(Fu, CFrame.new(-3.92, y + 6.3, 10) * CFrame.Angles(0, rad(90), 0), 1.8, 2.4, Color3.fromRGB(80, 110, 100))
	plant(Fu, CFrame.new(-3.3, y, 14.6), 2.2)
	-- Office
	desk(Fu, CFrame.new(-16, y, 14.2), 6, C.WoodDark)
	chair(Fu, CFrame.new(-16, y, 12) * CFrame.Angles(0, rad(180), 0), C.WoodDark)
	fbox(Fu, "Monitor", CFrame.new(-17, y + 3.6, 14.6), Vector3.new(2.2, 1.5, 0.15), C.GlassDark, M.Glass, true)
	fbox(Fu, "MonitorStand", CFrame.new(-17, y + 2.95, 14.6), Vector3.new(0.5, 0.3, 0.5), C.MetalDark, M.Metal, true)
	fbox(Fu, "Keyboard", CFrame.new(-17, y + 2.88, 13.6), Vector3.new(1.8, 0.1, 0.6), C.MetalDark, M.SmoothPlastic, true)
	lamp(Fu, CFrame.new(-13.8, y + 2.8, 14.5), 1.2)
	fbox(Fu, "Papers", CFrame.new(-14.5, y + 2.86, 13.4), Vector3.new(1.2, 0.08, 1.0), C.Pillow, M.SmoothPlastic, true)
	bookshelf(Fu, CFrame.new(-22.9, y, 3) * CFrame.Angles(0, rad(-90), 0), 4, 8, C.WoodDark)
	bookshelf(Fu, CFrame.new(-22.9, y, 13) * CFrame.Angles(0, rad(-90), 0), 4, 8, C.WoodDark)
	closet("ClosetOffice", "Office", CFrame.new(-10, y, 1.6) * CFrame.Angles(0, rad(180), 0), C.WoodDark)
	cabinet(Fu, "FilingCabinet", CFrame.new(-5.8, y, 13.5) * CFrame.Angles(0, rad(90), 0), 1.6, 4.2, 1.5, C.Metal, 3)
	rug(Fu, CFrame.new(-14, y, 8), 7, 6, Color3.fromRGB(70, 80, 70))
	pictureFrame(Fu, CFrame.new(-5.08, y + 6.6, 11) * CFrame.Angles(0, rad(-90), 0), 1.8, 1.4, Color3.fromRGB(200, 190, 170))
	pictureFrame(Fu, CFrame.new(-5.08, y + 6.6, 13.5) * CFrame.Angles(0, rad(-90), 0), 1.8, 1.4, Color3.fromRGB(190, 200, 180))
	fbox(Fu, "Globe", CFrame.new(-22.6, y + 3.4, 8), Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(60, 90, 140), M.SmoothPlastic, true, { Shape = Enum.PartType.Ball })
	table4(Fu, "GlobeStand", CFrame.new(-22.6, y, 8), 1.2, 1.2, 2.8, C.WoodDark)
	-- Bathroom
	do
		local m = model("Bathtub", Fu)
		fbox(m, "Body", CFrame.new(22, y + 0.9, 4), Vector3.new(3, 1.8, 6), C.Appliance, M.SmoothPlastic)
		fbox(m, "Inner", CFrame.new(22, y + 1.85, 4), Vector3.new(2.4, 0.1, 5.2), Color3.fromRGB(200, 214, 220), M.SmoothPlastic, true)
		fbox(m, "Tap", CFrame.new(22, y + 2.6, 1.3), Vector3.new(0.3, 1.2, 0.3), C.Metal, M.Metal, true)
		fbox(m, "ShowerHead", CFrame.new(22, y + 7.5, 1.4), Vector3.new(0.8, 0.3, 0.8), C.Metal, M.Metal, true)
		fbox(m, "ShowerPipe", CFrame.new(22, y + 5.0, 1.0), Vector3.new(0.15, 5.0, 0.15), C.Metal, M.Metal, true)
		fbox(m, "Curtain", CFrame.new(20.4, y + 5.0, 4), Vector3.new(0.1, 6.4, 6), Color3.fromRGB(190, 200, 210), M.Fabric, true, { Transparency = 0.2 })
		fbox(m, "CurtainRail", CFrame.new(20.4, y + 8.3, 4), Vector3.new(0.12, 0.12, 6.2), C.Metal, M.Metal, true)
	end
	do
		local m = model("Toilet", Fu)
		fbox(m, "Tank", CFrame.new(22.9, y + 2.2, 13), Vector3.new(0.9, 1.6, 1.8), C.Appliance, M.SmoothPlastic)
		fbox(m, "Bowl", CFrame.new(21.9, y + 0.8, 13), Vector3.new(1.6, 1.6, 1.4), C.Appliance, M.SmoothPlastic)
		fbox(m, "Seat", CFrame.new(21.9, y + 1.68, 13), Vector3.new(1.6, 0.15, 1.4), Color3.fromRGB(230, 230, 226), M.SmoothPlastic, true)
	end
	cabinet(Fu, "Vanity", CFrame.new(9, y, 1.5) * CFrame.Angles(0, rad(180), 0), 6, 3.0, 1.8, C.WallInt, 2)
	fbox(Fu, "Basin", CFrame.new(9, y + 3.15, 1.5), Vector3.new(2.0, 0.3, 1.3), C.Appliance, M.SmoothPlastic, true)
	fbox(Fu, "Tap", CFrame.new(9, y + 3.7, 0.9), Vector3.new(0.12, 0.8, 0.12), C.Metal, M.Metal, true)
	do
		local m = model("Mirror", Fu)
		fbox(m, "Frame", CFrame.new(9, y + 6.2, 0.58), Vector3.new(4.0, 3.0, 0.12), C.WoodDark, M.Wood, true)
		fbox(m, "Glass", CFrame.new(9, y + 6.2, 0.66), Vector3.new(3.6, 2.6, 0.06), Color3.fromRGB(170, 190, 200), M.Glass, true, { Reflectance = 0.6 })
	end
	do
		local m = model("Shower", Fu)
		fbox(m, "Tray", CFrame.new(15, y + 0.15, 13.75), Vector3.new(4, 0.3, 3.5), C.Appliance, M.SmoothPlastic)
		fbox(m, "GlassSide", CFrame.new(13.05, y + 3.9, 13.75), Vector3.new(0.1, 7.5, 3.5), C.Glass, M.Glass, true, { Transparency = 0.5, CanCollide = true })
		fbox(m, "GlassFront", CFrame.new(16, y + 3.9, 12.05), Vector3.new(2.0, 7.5, 0.1), C.Glass, M.Glass, true, { Transparency = 0.5, CanCollide = true })
		fbox(m, "Head", CFrame.new(15, y + 7.4, 15.0), Vector3.new(0.8, 0.3, 0.8), C.Metal, M.Metal, true)
		fbox(m, "Pipe", CFrame.new(15, y + 5.0, 15.3), Vector3.new(0.15, 5, 0.15), C.Metal, M.Metal, true)
	end
	cabinet(Fu, "LinenCabinet", CFrame.new(5.9, y, 6) * CFrame.Angles(0, rad(-90), 0), 3, 6, 1.6, C.WallInt, 2)
	rug(Fu, CFrame.new(18, y, 4), 2.8, 2.2, Color3.fromRGB(120, 140, 160))
	fbox(Fu, "TowelRail", CFrame.new(19, y + 5.2, 15.3), Vector3.new(3, 0.12, 0.12), C.Metal, M.Metal, true)
	fbox(Fu, "Towel", CFrame.new(18.3, y + 4.4, 15.2), Vector3.new(1.2, 1.8, 0.2), Color3.fromRGB(200, 120, 110), M.Fabric, true)
	fbox(Fu, "Towel", CFrame.new(19.7, y + 4.4, 15.2), Vector3.new(1.2, 1.8, 0.2), Color3.fromRGB(110, 140, 200), M.Fabric, true)
	plant(Fu, CFrame.new(19, y, 14.5), 1.8)
end

----------------------------------------------------------------------
-- Гараж: магазин Рэя, верстак, стеллаж, коробки
----------------------------------------------------------------------
do
	local Fu = furniture
	local y = F1
	-- Shop (House.Shop): Counter + Sign + Ray + Prompt
	do
		local shop = model("Shop", house, { Room = "Garage" })
		local counter = part({ Name = "Counter", CFrame = CFrame.new(35, y + 1.5, -1.4), Size = Vector3.new(8, 3, 2), Color = C.WoodDark, Material = M.WoodPlanks, CanCollide = true, CanQuery = true, CanTouch = false }, shop)
		shop.PrimaryPart = counter
		fbox(shop, "CounterTop", CFrame.new(35, y + 3.08, -1.4), Vector3.new(8.3, 0.16, 2.3), C.Wood, M.Wood, true)
		fbox(shop, "Register", CFrame.new(32.3, y + 3.7, -1.3), Vector3.new(1.4, 1.1, 1.2), C.MetalDark, M.Metal, true)
		fbox(shop, "RegisterKeys", CFrame.new(32.3, y + 4.3, -1.7) * CFrame.Angles(rad(-20), 0, 0), Vector3.new(1.2, 0.1, 0.6), C.Metal, M.Metal, true)
		fbox(shop, "AppleCrate", CFrame.new(37.5, y + 3.5, -1.4), Vector3.new(1.6, 0.8, 1.2), C.Wood, M.Wood, true)
		for i = 1, 3 do
			fbox(shop, "Apple", CFrame.new(37.0 + (i - 1) * 0.5, y + 4.1, -1.6 + (i % 2) * 0.4), Vector3.new(0.5, 0.5, 0.5), vary(C.Red, 0.08), M.SmoothPlastic, true, { Shape = Enum.PartType.Ball })
		end
		local sign = part({ Name = "Sign", CFrame = CFrame.new(35, y + 8.2, 1.3), Size = Vector3.new(8, 2, 0.3), Color = C.MetalDark, Material = M.Metal, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, shop)
		label(sign, Enum.NormalId.Front, "RAY'S GARAGE", C.Neon, nil, 40, "SignGui", "Label")
		fbox(shop, "SignBulb", CFrame.new(35, y + 9.5, 1.0), Vector3.new(6, 0.25, 0.25), C.Bulb, M.Neon, true)
		-- Ray: простой NPC из деталей, без Humanoid
		local ray = model("Ray", shop)
		local rx, rz = 35, 0.6
		fbox(ray, "LeftLeg", CFrame.new(rx - 0.45, y + 1.5, rz), Vector3.new(0.8, 3.0, 0.8), C.Overalls, M.Fabric, true)
		fbox(ray, "RightLeg", CFrame.new(rx + 0.45, y + 1.5, rz), Vector3.new(0.8, 3.0, 0.8), C.Overalls, M.Fabric, true)
		fbox(ray, "Torso", CFrame.new(rx, y + 4.3, rz), Vector3.new(2.0, 2.6, 1.1), C.Shirt, M.Fabric, true)
		fbox(ray, "Bib", CFrame.new(rx, y + 4.1, rz - 0.6), Vector3.new(1.2, 2.0, 0.1), C.Overalls, M.Fabric, true)
		fbox(ray, "LeftArm", CFrame.new(rx - 1.3, y + 4.2, rz), Vector3.new(0.6, 2.4, 0.6), C.Shirt, M.Fabric, true)
		fbox(ray, "RightArm", CFrame.new(rx + 1.3, y + 3.6, rz - 0.6) * CFrame.Angles(rad(-60), 0, 0), Vector3.new(0.6, 2.4, 0.6), C.Shirt, M.Fabric, true)
		fbox(ray, "LeftHand", CFrame.new(rx - 1.3, y + 2.9, rz), Vector3.new(0.6, 0.5, 0.6), C.Skin, M.SmoothPlastic, true)
		fbox(ray, "Head", CFrame.new(rx, y + 6.4, rz), Vector3.new(1.2, 1.2, 1.2), C.Skin, M.SmoothPlastic, true)
		fbox(ray, "Cap", CFrame.new(rx, y + 7.05, rz), Vector3.new(1.3, 0.35, 1.3), C.Red, M.Fabric, true)
		fbox(ray, "CapPeak", CFrame.new(rx, y + 6.95, rz - 0.9), Vector3.new(1.2, 0.12, 0.7), C.Red, M.Fabric, true)
		fbox(ray, "Beard", CFrame.new(rx, y + 5.95, rz - 0.55), Vector3.new(0.9, 0.5, 0.2), Color3.fromRGB(120, 100, 80), M.Fabric, true)
		ray.PrimaryPart = ray:FindFirstChild("Torso")
		prompt(counter, "Prompt", "Shop", "Ray", 0, 10)
	end
	-- Верстак
	do
		local m = table4(Fu, "Workbench", CFrame.new(27.5, y, 0.6), 5, 1.8, 3.0, C.Wood)
		fbox(m, "Vise", CFrame.new(29.4, y + 3.4, 0.2), Vector3.new(0.8, 0.8, 1.0), C.MetalDark, M.Metal, true)
		fbox(m, "Toolbox", CFrame.new(26.3, y + 3.4, 0.7), Vector3.new(1.6, 0.8, 0.9), C.Red, M.Metal, true)
		fbox(m, "Pegboard", CFrame.new(27.5, y + 6, 1.4), Vector3.new(5, 3, 0.1), Color3.fromRGB(150, 120, 80), M.Wood, true)
		for i = 1, 4 do
			fbox(m, "Tool", CFrame.new(25.6 + i * 0.9, y + 6, 1.3), Vector3.new(0.2, randRange(1.0, 2.2), 0.15), C.MetalDark, M.Metal, true)
		end
	end
	-- Стеллаж у восточной стены
	do
		local m = model("Shelving", Fu)
		for _, z in { -15, -8 } do
			fbox(m, "Post", CFrame.new(40.5, y + 3.5, z), Vector3.new(0.2, 7, 0.2), C.MetalDark, M.Metal, true)
			fbox(m, "Post", CFrame.new(41.4, y + 3.5, z), Vector3.new(0.2, 7, 0.2), C.MetalDark, M.Metal, true)
		end
		for i = 0, 3 do
			fbox(m, "Shelf", CFrame.new(40.95, y + 0.3 + i * 2.2, -11.5), Vector3.new(1.2, 0.12, 7), C.Metal, M.Metal, i > 0)
		end
		for i = 1, 6 do
			local sz = Vector3.new(randRange(0.7, 1.1), randRange(0.8, 1.6), randRange(0.7, 1.1))
			fbox(m, "Can", CFrame.new(40.95, y + 0.3 + (i % 4) * 2.2 + 0.06 + sz.Y / 2, -14.4 + i * 1.0), sz, Color3.fromHSV(rand(), 0.5, 0.7), M.Metal, true)
		end
	end
	boxCrate(Fu, CFrame.new(26.2, y, -14.0), Vector3.new(2.4, 2.0, 2.4))
	boxCrate(Fu, CFrame.new(26.2, y + 2.0, -14.0), Vector3.new(2.0, 1.6, 2.0))
	boxCrate(Fu, CFrame.new(28.8, y, -14.2), Vector3.new(2.0, 1.4, 2.0))
	do
		local m = model("Mower", Fu)
		fbox(m, "Body", CFrame.new(39.5, y + 0.8, -0.4), Vector3.new(2.0, 1.0, 2.6), C.Red, M.Metal)
		fbox(m, "Handle", CFrame.new(39.5, y + 2.4, 1.0) * CFrame.Angles(rad(40), 0, 0), Vector3.new(1.8, 0.12, 3.0), C.MetalDark, M.Metal, true)
		for _, o in { { -0.9, -1.0 }, { 0.9, -1.0 }, { -0.9, 1.0 }, { 0.9, 1.0 } } do
			fbox(m, "Wheel", CFrame.new(39.5 + o[1], y + 0.4, -0.4 + o[2]) * CFrame.Angles(0, 0, rad(90)), Vector3.new(0.8, 0.3, 0.8), C.MetalDark, M.SmoothPlastic, true, { Shape = Enum.PartType.Cylinder })
		end
	end
	do
		local m = model("Bike", Fu)
		for _, z in { -12.4, -9.6 } do
			fbox(m, "Wheel", CFrame.new(25.2, y + 1.1, z) * CFrame.Angles(0, 0, rad(90)), Vector3.new(2.2, 0.15, 2.2), C.MetalDark, M.SmoothPlastic, true, { Shape = Enum.PartType.Cylinder })
		end
		fbox(m, "Frame", CFrame.new(25.2, y + 1.6, -11) * CFrame.Angles(rad(30), 0, 0), Vector3.new(0.12, 0.12, 2.6), C.Blue, M.Metal, true)
		fbox(m, "Seat", CFrame.new(25.2, y + 2.6, -11.6), Vector3.new(0.5, 0.2, 0.8), C.MetalDark, M.SmoothPlastic, true)
		fbox(m, "Bars", CFrame.new(25.2, y + 2.7, -9.9), Vector3.new(1.4, 0.1, 0.1), C.MetalDark, M.Metal, true)
	end
	fbox(Fu, "OilStain", CFrame.new(33, y + 0.03, -9), Vector3.new(4, 0.05, 6), Color3.fromRGB(28, 28, 30), M.SmoothPlastic, true)
end

----------------------------------------------------------------------
-- Подвал: коробки-укрытие, щиток, бойлер, трубы, полки, печь
----------------------------------------------------------------------
do
	local Fu = furniture
	local y = FB
	-- BoxesBasement
	do
		local m = hidingSpot("BoxesBasement", "Boxes", "Basement", CFrame.new(-10, y + 0.5, -4.5), lookCF(Vector3.new(-9.2, y + 3.0, -4.5), Vector3.new(0, y + 3.0, -4.5)), "Boxes")
		local body = model("Body", m)
		-- стопки вокруг кармана (-10, -4.5): запад, восток, юг, север
		boxCrate(body, CFrame.new(-12.5, y, -6.3), Vector3.new(2, 2, 2.2))
		boxCrate(body, CFrame.new(-12.5, y + 2, -6.3), Vector3.new(1.8, 1.8, 2.0))
		boxCrate(body, CFrame.new(-12.5, y, -3.4), Vector3.new(2, 2.4, 2.4))
		boxCrate(body, CFrame.new(-12.5, y + 2.4, -3.4), Vector3.new(1.6, 1.4, 1.8))
		boxCrate(body, CFrame.new(-7.6, y, -6.0), Vector3.new(2.2, 2.6, 2.4))
		boxCrate(body, CFrame.new(-7.6, y + 2.6, -6.0), Vector3.new(1.8, 1.6, 2.0))
		boxCrate(body, CFrame.new(-7.6, y, -2.6), Vector3.new(2.2, 2.0, 2.4))
		boxCrate(body, CFrame.new(-7.6, y + 2.0, -2.6), Vector3.new(1.4, 1.2, 1.6))
		boxCrate(body, CFrame.new(-10, y, -7.0), Vector3.new(2.6, 3.4, 1.4))
		boxCrate(body, CFrame.new(-10, y, -1.8), Vector3.new(2.6, 2.2, 1.4))
		boxCrate(body, CFrame.new(-10, y + 2.2, -1.8), Vector3.new(2.0, 1.4, 1.2))
	end
	-- Fusebox на восточной стене
	do
		local fb = model("Fusebox", house, { On = true })
		local boxp = part({ Name = "Box", CFrame = CFrame.new(13.2, y + 5.5, 0), Size = Vector3.new(0.6, 2.6, 1.8), Color = C.Metal, Material = M.Metal, CanCollide = false, CanQuery = true, CanTouch = false }, fb)
		fb.PrimaryPart = boxp
		fbox(fb, "Lever", CFrame.new(12.8, y + 5.5, 0.4) * CFrame.Angles(0, 0, rad(-20)), Vector3.new(0.25, 1.0, 0.2), C.Red, M.SmoothPlastic, true)
		fbox(fb, "Indicator", CFrame.new(12.85, y + 6.4, -0.5), Vector3.new(0.1, 0.25, 0.25), Color3.fromRGB(120, 255, 120), M.Neon, true)
		fbox(fb, "Conduit", CFrame.new(13.2, y + 8.3, 0), Vector3.new(0.3, 3.0, 0.3), C.MetalDark, M.Metal, true)
		prompt(boxp, "Prompt", "Power", "Fusebox", 0.6, 8)
	end
	-- Бойлер и трубы
	do
		local m = model("WaterHeater", Fu)
		fbox(m, "Tank", CFrame.new(11.8, y + 3.0, 13.5) * CFrame.Angles(0, 0, rad(90)), Vector3.new(6, 2.6, 2.6), C.Appliance, M.Metal, false, { Shape = Enum.PartType.Cylinder })
		fbox(m, "Base", CFrame.new(11.8, y + 0.2, 13.5), Vector3.new(2.6, 0.4, 2.6), C.MetalDark, M.Metal, true)
		fbox(m, "Pipe", CFrame.new(11.8, y + 7.4, 13.5), Vector3.new(0.3, 2.8, 0.3), C.Metal, M.Metal, true)
		fbox(m, "Pipe", CFrame.new(5, y + 8.5, 13.5), Vector3.new(14, 0.3, 0.3), C.Metal, M.Metal, true)
		fbox(m, "Pipe", CFrame.new(-2.2, y + 8.5, 10), Vector3.new(0.3, 0.3, 7), C.Metal, M.Metal, true)
		fbox(m, "DripPipe", CFrame.new(-2.2, y + 7.8, 6.5), Vector3.new(0.3, 1.4, 0.3), C.Metal, M.Metal, true)
		fbox(m, "Drip", CFrame.new(-2.2, y + 6.9, 6.5), Vector3.new(0.12, 0.3, 0.12), Color3.fromRGB(170, 200, 230), M.Glass, true, { Transparency = 0.3 })
		fbox(m, "Puddle", CFrame.new(-2.2, y + 0.03, 6.5), Vector3.new(2.4, 0.05, 2.0), Color3.fromRGB(60, 70, 80), M.Glass, true, { Transparency = 0.4, Reflectance = 0.3 })
	end
	-- Полки у северной стены
	do
		local m = model("Shelving", Fu)
		for _, x in { 2, 10 } do
			fbox(m, "Post", CFrame.new(x, y + 3.6, 14.6), Vector3.new(0.2, 7.2, 0.2), C.WoodDark, M.Wood, true)
			fbox(m, "Post", CFrame.new(x, y + 3.6, 15.4), Vector3.new(0.2, 7.2, 0.2), C.WoodDark, M.Wood, true)
		end
		for i = 0, 3 do
			fbox(m, "Shelf", CFrame.new(6, y + 1.0 + i * 1.7, 15.0), Vector3.new(8, 0.15, 1.0), C.Wood, M.Wood, i > 0)
		end
		for i = 1, 8 do
			fbox(m, "Jar", CFrame.new(2.6 + i * 0.9, y + 1.0 + (i % 4) * 1.7 + 0.5, 15.0), Vector3.new(0.5, 0.8, 0.5), Color3.fromHSV(randRange(0.05, 0.15), 0.6, 0.6), M.Glass, true, { Transparency = 0.2 })
		end
	end
	-- Печь, старый стол, стул, матрас у стены
	do
		local m = model("Furnace", Fu)
		fbox(m, "Body", CFrame.new(-10, y + 3, 11.5), Vector3.new(4, 6, 3), C.MetalDark, M.Metal)
		fbox(m, "Duct", CFrame.new(-10, y + 7.5, 11.5), Vector3.new(1.0, 3.0, 1.0), C.Metal, M.Metal, true)
		fbox(m, "Grille", CFrame.new(-10, y + 2.2, 9.95), Vector3.new(2.4, 1.6, 0.1), Color3.fromRGB(40, 40, 42), M.Metal, true)
		fbox(m, "Glow", CFrame.new(-10, y + 2.2, 9.9), Vector3.new(1.4, 0.5, 0.05), Color3.fromRGB(255, 110, 40), M.Neon, true)
	end
	table4(Fu, "OldTable", CFrame.new(6, y, -4), 4, 2.5, 2.6, C.WoodDark)
	fbox(Fu, "Junk", CFrame.new(5.4, y + 2.95, -4.2), Vector3.new(1.2, 0.5, 0.8), C.Metal, M.Metal, true)
	fbox(Fu, "Junk", CFrame.new(7, y + 3.0, -3.6), Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(90, 70, 50), M.Wood, true)
	chair(Fu, CFrame.new(6, y, -1.8) * CFrame.Angles(0, rad(180), 0), C.WoodDark)
	fbox(Fu, "Mattress", CFrame.new(-4, y + 2.6, 14.8) * CFrame.Angles(rad(-12), 0, 0), Vector3.new(4, 5.4, 0.8), C.Mattress, M.Fabric, false)
	fbox(Fu, "Rug", CFrame.new(0, y + 0.04, 2), Vector3.new(6, 0.08, 5), Color3.fromRGB(70, 60, 60), M.Fabric, true)
end

----------------------------------------------------------------------
-- TV, Radio, Phone
----------------------------------------------------------------------
do
	local y = F1
	local tv = model("TV", house, { On = false })
	fbox(tv, "Bezel", CFrame.new(-21.35, y + 4.3, -6), Vector3.new(0.4, 4.4, 7.4), C.MetalDark, M.SmoothPlastic, true, { CastShadow = true })
	fbox(tv, "Foot", CFrame.new(-21.4, y + 2.18, -6), Vector3.new(1.2, 0.2, 2.2), C.MetalDark, M.Metal, true)
	local screen = part({ Name = "Screen", CFrame = CFrame.new(-21.1, y + 4.3, -6) * CFrame.Angles(0, rad(-90), 0), Size = Vector3.new(7, 4, 0.12), Color = Color3.fromRGB(12, 12, 14), Material = M.Glass, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, tv)
	tv.PrimaryPart = screen
	do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Screen"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.LightInfluence = 0
		gui.Brightness = 1.5
		gui.Parent = screen
		local static = Instance.new("Frame")
		static.Name = "Static"
		static.Size = UDim2.fromScale(1, 1)
		static.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		static.BackgroundTransparency = 0.2
		static.BorderSizePixel = 0
		static.Parent = gui
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		text.BackgroundTransparency = 0
		text.BorderSizePixel = 0
		text.TextColor3 = Color3.fromRGB(255, 255, 255)
		text.TextScaled = true
		text.TextWrapped = true
		text.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
		text.Text = ""
		text.Visible = false
		text.ZIndex = 2
		text.Parent = gui
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.05, 0)
		pad.PaddingRight = UDim.new(0.05, 0)
		pad.PaddingTop = UDim.new(0.08, 0)
		pad.PaddingBottom = UDim.new(0.08, 0)
		pad.Parent = text
	end
	-- Radio на книжном шкафу гостиной
	local radio = model("Radio", house)
	local body = part({ Name = "Body", CFrame = CFrame.new(-12.5, y + 7.55, 2.9), Size = Vector3.new(1.8, 1.0, 0.8), Color = Color3.fromRGB(150, 110, 70), Material = M.Wood, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, radio)
	radio.PrimaryPart = body
	fbox(radio, "Dial", CFrame.new(-12.9, y + 7.55, 2.48), Vector3.new(0.7, 0.4, 0.05), Color3.fromRGB(240, 220, 160), M.SmoothPlastic, true)
	fbox(radio, "Knob", CFrame.new(-12.0, y + 7.5, 2.48), Vector3.new(0.25, 0.25, 0.08), C.MetalDark, M.Metal, true)
	fbox(radio, "Antenna", CFrame.new(-11.8, y + 8.6, 3.1) * CFrame.Angles(0, 0, rad(-25)), Vector3.new(0.06, 1.6, 0.06), C.Metal, M.Metal, true)
	-- Phone (домашний телефон) на стене кухни у арки
	local phone = model("Phone", house)
	local pbody = part({ Name = "Body", CFrame = CFrame.new(5.2, y + 5.2, -5), Size = Vector3.new(0.4, 1.7, 0.9), Color = Color3.fromRGB(226, 220, 200), Material = M.SmoothPlastic, CanCollide = false, CanQuery = true, CanTouch = false, CastShadow = false }, phone)
	phone.PrimaryPart = pbody
	fbox(phone, "Handset", CFrame.new(5.45, y + 5.5, -5), Vector3.new(0.3, 1.5, 0.4), Color3.fromRGB(200, 196, 180), M.SmoothPlastic, true)
	fbox(phone, "Cord", CFrame.new(5.25, y + 3.8, -5.3), Vector3.new(0.08, 1.4, 0.08), C.MetalDark, M.SmoothPlastic, true)
	prompt(pbody, "Prompt", "Answer", "Phone", 0, 7)
end

----------------------------------------------------------------------
-- Деревья (сборщик), слоты яблонь, шаблоны
----------------------------------------------------------------------
-- Дерево: Trunk (цилиндр) + Crown (шар) [+ Crown2]. base — точка на земле.
local function buildTree(parent: Instance, base: Vector3, scale: number, isDeco: boolean?)
	local m = model("Tree", parent)
	local h = 6 * scale
	local trunk = part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, rad(90)), Size = Vector3.new(h, 1.4 * scale, 1.4 * scale), Color = vary(C.Trunk, 0.03), Material = M.Wood, CanCollide = true, CanQuery = not isDeco, CanTouch = false }, m)
	m.PrimaryPart = trunk
	local r = 7 * scale
	deco({ Name = "Crown", Shape = Enum.PartType.Ball, CFrame = CFrame.new(base + Vector3.new(0, h + r * 0.25, 0)), Size = Vector3.new(r, r * 0.85, r), Color = vary(C.Crown, 0.04), Material = M.Grass, CastShadow = true }, m)
	deco({ Name = "Crown2", Shape = Enum.PartType.Ball, CFrame = CFrame.new(base + Vector3.new(0.6 * scale, h + r * 0.55, -0.4 * scale)), Size = Vector3.new(r * 0.7, r * 0.6, r * 0.7), Color = vary(C.Crown2, 0.04), Material = M.Grass, CastShadow = true }, m)
	m.WorldPivot = CFrame.new(base)
	return m
end

local TREE_SLOTS = {
	Vector3.new(-26, G, 30), Vector3.new(-10, G, 36), Vector3.new(12, G, 36), Vector3.new(27, G, 28),
	Vector3.new(-28, G, 50), Vector3.new(-12, G, 54), Vector3.new(12, G, 54), Vector3.new(34, G, 58),
}
local APPLE_OFFSETS = { Vector3.new(2.6, 5.0, 0.8), Vector3.new(-2.2, 5.3, 1.6), Vector3.new(0.4, 4.9, -2.7) }
for i, pos in TREE_SLOTS do
	local slot = marker({ Name = "Slot" .. i, CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)), Size = Vector3.new(2, 1, 2) }, treesF)
	slot:SetAttribute("Slot", i)
	slot:SetAttribute("Planted", i <= Config.Economy.StartingTrees)
	if i <= Config.Economy.StartingTrees then
		buildTree(slot, pos, 1)
	end
	local spots = folder("AppleSpots", slot)
	for j, off in APPLE_OFFSETS do
		local a = Instance.new("Attachment")
		a.Name = "Spot" .. j
		a.CFrame = CFrame.new(pos + off)
		a.Parent = spots
	end
end

do
	local T = templatesF
	local ty = -150
	buildTree(T, Vector3.new(0, ty, 0), 1)
	part({ Name = "Apple", Shape = Enum.PartType.Ball, CFrame = CFrame.new(6, ty, 0), Size = Vector3.new(1.2, 1.2, 1.2), Color = Color3.fromRGB(205, 30, 30), Material = M.SmoothPlastic, CanCollide = false, CanQuery = true, CanTouch = false }, T)
	part({ Name = "Plank", CFrame = CFrame.new(10, ty, 0), Size = Vector3.new(5.4, 0.8, 0.3), Color = C.Wood, Material = M.Wood, CanCollide = false, CanQuery = false, CanTouch = false }, T)
	do
		local m = model("BearTrap", T)
		local ring = part({ Name = "Ring", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(14, ty + 0.1, 0) * CFrame.Angles(0, 0, rad(90)), Size = Vector3.new(0.2, 2.6, 2.6), Color = C.MetalDark, Material = M.Metal, CanCollide = false, CanQuery = true, CanTouch = false }, m)
		m.PrimaryPart = ring
		deco({ Name = "Plate", CFrame = CFrame.new(14, ty + 0.22, 0), Size = Vector3.new(0.9, 0.08, 0.9), Color = C.Metal, Material = M.Metal }, m)
		deco({ Name = "Jaw", CFrame = CFrame.new(14, ty + 0.5, -1.0) * CFrame.Angles(rad(-35), 0, 0), Size = Vector3.new(2.4, 0.8, 0.15), Color = C.Metal, Material = M.Metal }, m)
		deco({ Name = "Jaw", CFrame = CFrame.new(14, ty + 0.5, 1.0) * CFrame.Angles(rad(35), 0, 0), Size = Vector3.new(2.4, 0.8, 0.15), Color = C.Metal, Material = M.Metal }, m)
		for _, dz in { -1.0, 1.0 } do
			for i = -2, 2 do
				deco({ Name = "Tooth", CFrame = CFrame.new(14 + i * 0.5, ty + 0.95, dz * 0.75), Size = Vector3.new(0.15, 0.35, 0.15), Color = C.Metal, Material = M.Metal }, m)
			end
		end
		m.WorldPivot = CFrame.new(14, ty, 0)
	end
	part({ Name = "GlueTrap", CFrame = CFrame.new(18, ty + 0.08, 0), Size = Vector3.new(3, 0.15, 3), Color = Color3.fromRGB(230, 210, 90), Material = M.SmoothPlastic, Transparency = 0.1, CanCollide = false, CanQuery = true, CanTouch = false }, T)
	do
		local m = model("MotionLight", T)
		local pole = part({ Name = "Pole", CFrame = CFrame.new(22, ty + 4, 0), Size = Vector3.new(0.4, 8, 0.4), Color = C.MetalDark, Material = M.Metal, CanCollide = false, CanQuery = true, CanTouch = false }, m)
		m.PrimaryPart = pole
		deco({ Name = "Base", CFrame = CFrame.new(22, ty + 0.15, 0), Size = Vector3.new(1.4, 0.3, 1.4), Color = C.MetalDark, Material = M.Metal }, m)
		local lampP = deco({ Name = "Lamp", CFrame = CFrame.new(22, ty + 8.2, -0.5) * CFrame.Angles(rad(-30), 0, 0), Size = Vector3.new(1.4, 0.8, 1.2), Color = C.Metal, Material = M.Metal }, m)
		deco({ Name = "Lens", CFrame = CFrame.new(22, ty + 7.9, -0.9) * CFrame.Angles(rad(-30), 0, 0), Size = Vector3.new(1.2, 0.5, 0.1), Color = C.Bulb, Material = M.Glass, Transparency = 0.3 }, m)
		deco({ Name = "Sensor", CFrame = CFrame.new(22, ty + 7.2, -0.3), Size = Vector3.new(0.5, 0.4, 0.4), Color = C.Appliance, Material = M.SmoothPlastic }, m)
		spotLight(lampP, "Light", 40, 2.0, 80, Color3.fromRGB(255, 245, 220), Enum.NormalId.Front, false)
		sound(lampP, "Beeper", "", 0.7, false)
		m.WorldPivot = CFrame.new(22, ty, 0)
	end
	do
		local candle = part({ Name = "Candle", CFrame = CFrame.new(26, ty + 0.45, 0), Size = Vector3.new(0.35, 0.9, 0.35), Color = Color3.fromRGB(240, 230, 200), Material = M.SmoothPlastic, CanCollide = false, CanQuery = false, CanTouch = false }, T)
		pointLight(candle, "Light", 9, 0.6, Color3.fromRGB(255, 190, 120), false, true)
	end
end

----------------------------------------------------------------------
-- Объёмы комнат (Rooms): RoomName, Floor, Outdoor
----------------------------------------------------------------------
local ROOMS = {
	{ "Foyer", -4, 4, -15.5, 15.5, F1, H1, 1, false },
	{ "Living", -23.5, -5, -15.5, 3.5, F1, H1, 1, false },
	{ "Kitchen", 5, 23.5, -15.5, -2.5, F1, H1, 1, false },
	{ "Dining", 5, 23.5, -1.5, 15.5, F1, H1, 1, false },
	{ "Laundry", -23.5, -12.5, 9.5, 15.5, F1, H1, 1, false },
	{ "BackHall", -11.5, -5, 9.5, 15.5, F1, H1, 1, false },
	{ "Garage", 24.5, 41.5, -15.5, 1.5, F1, H1, 1, false },
	{ "KidRoom", -23.5, -5, -15.5, -0.5, F2, H2, 2, false },
	{ "ParentsRoom", 5, 23.5, -15.5, -0.5, F2, H2, 2, false },
	{ "UpperHall", -4, 4, -15.5, 15.5, F2, H2, 2, false },
	{ "Office", -23.5, -5, 0.5, 15.5, F2, H2, 2, false },
	{ "Bathroom", 5, 23.5, 0.5, 15.5, F2, H2, 2, false },
	{ "Basement", -13.5, 13.5, -7.5, 15.5, FB, F1 - 1, 0, false },
	{ "Porch", -8, 8, -24, -16, F1, H1, 3, true },
	{ "FrontYard", -46, 48, -40, -16, G, G + 10, 3, true },
	{ "BackYard", -46, 48, 16, 64, G, G + 10, 3, true },
	{ "BackAlley", -46, 48, 64, 80, G, G + 10, 3, true },
	{ "WestYard", -46, -24, -16, 16, G, G + 10, 3, true },
	{ "EastYard", 24, 48, 2, 16, G, G + 10, 3, true },
	{ "EastSide", 42, 48, -16, 2, G, G + 10, 3, true },
	{ "Street", -130, 130, -64, -40, G, G + 10, 3, true },
	{ "Shed", 25.5, 34.5, 40.5, 49.5, G, 7, 3, false },
}
for _, r in ROOMS do
	local p = marker({ Name = r[1], CFrame = CFrame.new((r[2] + r[3]) / 2, (r[6] + r[7]) / 2, (r[4] + r[5]) / 2), Size = Vector3.new(r[3] - r[2], r[7] - r[6], r[5] - r[4]) }, roomsF)
	p:SetAttribute("RoomName", r[1])
	p:SetAttribute("Floor", r[8])
	p:SetAttribute("Outdoor", r[9])
end

----------------------------------------------------------------------
-- Навигация: Waypoints, Entries, InmateSpawns, VesperSpots; Spawns; MotionLights
----------------------------------------------------------------------
local function navPart(parent: Instance, name: string, pos: Vector3, attrs: { [string]: any }?): Instance
	local p = marker({ Name = name, CFrame = CFrame.new(pos), Size = Vector3.new(1, 1, 1) }, parent)
	for k, v in attrs or {} do
		p:SetAttribute(k, v)
	end
	return p
end

local WAYPOINTS = {
	-- {x, y, z, room, floor}; y = верх пола + 0.5 (кроме точек на лестницах)
	{ 0, F1, -20, "Porch", 3 },
	{ 0, F1, -13, "Foyer", 1 }, { -2, F1, -7, "Foyer", 1 }, { -2, F1, 0, "Foyer", 1 }, { -2, F1, 7, "Foyer", 1 }, { -1, F1, 13.5, "Foyer", 1 },
	{ -8, F1, -12, "Living", 1 }, { -16, F1, -12, "Living", 1 }, { -20, F1, -12, "Living", 1 }, { -8, F1, -4, "Living", 1 }, { -8, F1, -8, "Living", 1 }, { -18, F1, 0, "Living", 1 }, { -14, F1, 0, "Living", 1 }, { -8, F1, 0, "Living", 1 },
	{ 7, F1, -10, "Kitchen", 1 }, { 14, F1, -11.5, "Kitchen", 1 }, { 20, F1, -9, "Kitchen", 1 }, { 8, F1, -5, "Kitchen", 1 }, { 14, F1, -4.5, "Kitchen", 1 }, { 20, F1, -4.5, "Kitchen", 1 },
	{ 14, F1, 1, "Dining", 1 }, { 8, F1, 7, "Dining", 1 }, { 20, F1, 7, "Dining", 1 }, { 8.5, F1, 12.5, "Dining", 1 }, { 16, F1, 13.2, "Dining", 1 },
	{ -8, F1, 13, "BackHall", 1 },
	{ -16, F1, 11.5, "Laundry", 1 }, { -21, F1, 11.5, "Laundry", 1 },
	{ -20.5, F1, 6.5, "Laundry", 1 }, -- площадка у двери в подвал
	{ 28, F1, -8, "Garage", 1 }, { 34, F1, -12, "Garage", 1 }, { 34, F1, -5, "Garage", 1 }, { 39, F1, -5, "Garage", 1 }, { 29, F1, -4, "Garage", 1 },
	-- Лестница в подвал (верх ступени k = -k, x = -17.5 + 2k - 1)
	{ -12.5, -3, 6.5, "Basement", 1 }, { -6.5, -6, 6.5, "Basement", 0 }, { -0.5, -9, 6.5, "Basement", 0 },
	-- Подвал
	{ 4, FB, 6.5, "Basement", 0 }, { 4, FB, 12, "Basement", 0 }, { -4, FB, 11, "Basement", 0 }, { 8, FB, 2, "Basement", 0 }, { 0, FB, -3, "Basement", 0 }, { 10, FB, 9, "Basement", 0 }, { -4, FB, 1, "Basement", 0 },
	-- Лестница наверх (верх ступени k = k, z = -10 + 2k - 1)
	{ 2, 3, -5, "Foyer", 1 }, { 2, 7, 3, "UpperHall", 2 }, { 2, 10, 9, "UpperHall", 2 },
	-- 2-й этаж
	{ 0, F2, -12, "UpperHall", 2 }, { -2, F2, -6, "UpperHall", 2 }, { -2, F2, 1, "UpperHall", 2 }, { -2, F2, 8, "UpperHall", 2 }, { 0, F2, 14, "UpperHall", 2 },
	{ -10, F2, -11, "KidRoom", 2 }, { -14, F2, -8, "KidRoom", 2 }, { -14, F2, -3, "KidRoom", 2 }, { -21.5, F2, -10, "KidRoom", 2 },
	{ 9, F2, -11, "ParentsRoom", 2 }, { 14, F2, -12, "ParentsRoom", 2 }, { 19, F2, -8, "ParentsRoom", 2 }, { 8, F2, -7, "ParentsRoom", 2 },
	{ -9, F2, 6, "Office", 2 }, { -14, F2, 8, "Office", 2 }, { -19, F2, 8, "Office", 2 }, { -10, F2, 12, "Office", 2 },
	{ 9, F2, 13.5, "Bathroom", 2 }, { 10, F2, 8, "Bathroom", 2 }, { 16, F2, 7, "Bathroom", 2 }, { 18.5, F2, 10, "Bathroom", 2 },
	-- Сарай
	{ 30.5, G, 42, "Shed", 3 },
	{ 0, G, 70, "BackAlley", 3 },
}
-- Двор: сетка точек (шаг 10 по X, 8 по Z), минуя дом, крыльцо, сарай, площадку и стволы яблонь
do
	local function nearTree(x, z)
		for _, t in TREE_SLOTS do
			if math.abs(t.X - x) < 3.5 and math.abs(t.Z - z) < 3.5 then
				return true
			end
		end
		return false
	end
	local function addOut(x, z, room)
		table.insert(WAYPOINTS, { x, G, z, room, 3 })
	end
	for _, z in { -37, -29, -21 } do
		for x = -40, 40, 10 do
			if not (z == -21 and math.abs(x) <= 10) then
				addOut(x, z, "FrontYard")
			end
		end
	end
	for _, z in { -13, -5, 3, 11 } do
		for _, x in { -40, -30 } do
			addOut(x, z, "WestYard")
		end
	end
	addOut(45, -9, "EastSide")
	addOut(45, -1, "EastSide")
	for _, z in { 5, 12 } do
		for _, x in { 30, 38, 45 } do
			addOut(x, z, "EastYard")
		end
	end
	for _, z in { 21, 29, 37, 45, 53, 61 } do
		for x = -40, 40, 10 do
			local inShed = x >= 22 and x <= 38 and z >= 37 and z <= 53
			local inStoop = z == 21 and x >= -14 and x <= -2
			if not inShed and not inStoop and not nearTree(x, z) then
				addOut(x, z, "BackYard")
			end
		end
	end
	addOut(-8, 24, "BackYard")
	for x = -120, 90, 10 do
		addOut(x, -52, "Street")
	end
	addOut(0, -46, "Street")
	for _, pnt in { { 95, -42 }, { 104, -42 }, { 110, -46 }, { 112, -52 }, { 110, -58 }, { 104, -62 }, { 95, -62 } } do
		addOut(pnt[1], pnt[2], "Street")
	end
end
for i, w in WAYPOINTS do
	navPart(waypointsF, "WP" .. i, Vector3.new(w[1], w[2] + 0.5, w[3]), { Room = w[4], Floor = w[5] })
end

-- Точки входа пациентов (снаружи дома)
for _, d in DOORS do
	if d.kind == "Entry" then
		local mid = (d.a + d.b) / 2
		local pos
		if d.axis == "x" then
			pos = Vector3.new(mid, F1 + 0.5, d.c + d.out * 2.5)
		else
			pos = Vector3.new(d.c + d.out * 2.0, G + 0.5, mid)
		end
		if d.id == "GarageSide" then
			pos = Vector3.new(44.5, G + 0.5, mid)
		end
		navPart(entriesF, d.id, pos, { EntryId = d.id, Kind = "Door", TargetId = d.id, Room = d.roomB })
	end
end
for _, w in WINDOWS do
	local mid = (w.a + w.b) / 2
	local pos = if w.axis == "x" then Vector3.new(mid, G + 0.5, w.c + w.out * 2.5) else Vector3.new(w.c + w.out * 2.5, G + 0.5, mid)
	navPart(entriesF, w.id, pos, { EntryId = w.id, Kind = "Window", TargetId = w.id, Room = w.room })
end
-- Спавны пациентов: улица (x = ±60, z = -52), у калитки, у тупика
navPart(inmateSpawnsF, "StreetWest", Vector3.new(-60, G + 0.55, -52), { Index = 1 })
navPart(inmateSpawnsF, "StreetEast", Vector3.new(60, G + 0.55, -52), { Index = 2 })
navPart(inmateSpawnsF, "BackGate", Vector3.new(0, G + 0.5, 70), { Index = 3 })
navPart(inmateSpawnsF, "CulDeSac", Vector3.new(90, G + 0.55, -44), { Index = 4 })
-- Места Веспер
for _, v in { { "Living", -19, F1, -0.5 }, { "Dining", 9, F1, 2 }, { "KidRoom", -14, F2, -10 }, { "ParentsRoom", 20, F2, -7 }, { "Office", -18, F2, 8 }, { "Basement", 6, FB, 9 } } do
	navPart(vesperF, v[1], Vector3.new(v[2], v[3] + 0.5, v[4]), { Room = v[1] })
end
-- Спавны игроков: гостиная и холл
for i, s in { { -8, -12 }, { -12, -13 }, { -17, -12 }, { -18, 0 }, { -9, -7 }, { -2, -12 }, { -2, -6 }, { -1, -14.5 }, { -14, 0 }, { -8, -1 } } do
	local p = navPart(spawnsF, "Spawn" .. i, Vector3.new(s[1], F1 + 0.5, s[2]), { Index = i })
	p:SetAttribute("Room", if s[1] <= -5 then "Living" else "Foyer")
end
-- Позиции прожекторов во дворе
for i, p in { Vector3.new(-34, G, -30), Vector3.new(40, G, 12), Vector3.new(-36, G, 52) } do
	local mp = navPart(motionF, "MotionLight" .. i, p + Vector3.new(0, 0.5, 0), { Index = i })
	spotLight(mp, "Light", 40, 2.0, 80, Color3.fromRGB(255, 245, 220), Enum.NormalId.Front, false)
	sound(mp, "Beeper", "", 0.7, false)
end

----------------------------------------------------------------------
-- Двор, участок, забор, сарай
----------------------------------------------------------------------
local LOT = { x0 = -46, x1 = 48, z0 = -40, z1 = 64 }
local HOUSE_FOOT = { x0 = -24, x1 = 24, z0 = -16, z1 = 16 }
local GARAGE_FOOT = { x0 = 24, x1 = 42, z0 = -16, z1 = 2 }
do
	local S = structure
	-- Земля (тёмная, большая), с вырезом под дом (подвал)
	rectMinusHoles({ x0 = -400, x1 = 400, z0 = -400, z1 = 300 }, { HOUSE_FOOT, GARAGE_FOOT }, function(x0, x1, z0, z1)
		bbox(S, "Ground", x0, x1, G - 4, G, z0, z1, C.Ground, M.Grass, "solid", { CanQuery = true })
	end)
	-- Лужайка участка (без дома, дорожки, подъезда, сарая)
	local DRIVE = { x0 = 26, x1 = 40, z0 = -44, z1 = -16 }
	local PATH = { x0 = -2, x1 = 2, z0 = -44, z1 = -26 }
	local SHED = { x0 = 25, x1 = 35, z0 = 40, z1 = 50 }
	rectMinusHoles(LOT, { HOUSE_FOOT, GARAGE_FOOT, DRIVE, PATH, SHED }, function(x0, x1, z0, z1)
		bbox(S, "Lawn", x0, x1, G - 0.3, G + 0.05, z0, z1, vary(C.Lawn, 0.02), M.Grass, "solid", { CanQuery = true })
	end)
	bbox(S, "Driveway", DRIVE.x0, DRIVE.x1, G - 0.3, G + 0.05, DRIVE.z0, DRIVE.z1, C.Concrete, M.Concrete)
	bbox(S, "Path", PATH.x0, PATH.x1, G - 0.3, G + 0.05, PATH.z0, PATH.z1, C.Sidewalk, M.Concrete)
	-- Дорожка к заднему двору вдоль западной стороны и к калитке
	bbox(S, "Path", -30, -27, G - 0.3, G + 0.05, -26, 22, C.Sidewalk, M.Concrete)
	bbox(S, "Path", -30, -6, G - 0.3, G + 0.05, 19, 22, C.Sidewalk, M.Concrete)
	bbox(S, "Path", -2, 2, G - 0.3, G + 0.05, 22, 64, C.Sidewalk, M.Concrete)
	-- Почтовый ящик
	bbox(S, "MailPost", 4.3, 4.7, G, G + 3.6, -41.7, -41.3, C.WoodDark, M.Wood, "deco", { CastShadow = true })
	bbox(S, "Mailbox", 3.7, 5.3, G + 3.6, G + 4.6, -42.4, -40.6, C.MetalDark, M.Metal, "deco", { CastShadow = true })
	bbox(S, "MailFlag", 5.3, 5.45, G + 3.8, G + 4.9, -41.2, -40.9, C.Red, M.SmoothPlastic, "deco")

	-- Забор: столбы каждые 8 стадов, две перекладины; разрывы: калитка спереди, калитка сзади, ворота подъезда (закрыты)
	local function fenceLine(axis: string, c: number, a: number, b: number, gaps: { { number } })
		-- участки между разрывами
		local segs = {}
		local cursor = a
		table.sort(gaps, function(p, q)
			return p[1] < q[1]
		end)
		for _, g in gaps do
			if g[1] > cursor then
				table.insert(segs, { cursor, g[1] })
			end
			cursor = math.max(cursor, g[2])
		end
		if b > cursor then
			table.insert(segs, { cursor, b })
		end
		for _, seg in segs do
			local s0, s1 = seg[1], seg[2]
			-- невидимый блокиратор
			if axis == "x" then
				bbox(S, "FenceBlock", s0, s1, G, G + 6, c - 0.2, c + 0.2, C.Fence, M.Wood, "solid", { Transparency = 1, CastShadow = false, CanQuery = false })
				bbox(S, "FenceRail", s0, s1, G + 1.2, G + 1.5, c - 0.12, c + 0.12, C.Fence, M.Wood, "deco")
				bbox(S, "FenceRail", s0, s1, G + 3.0, G + 3.3, c - 0.12, c + 0.12, C.Fence, M.Wood, "deco")
			else
				bbox(S, "FenceBlock", c - 0.2, c + 0.2, G, G + 6, s0, s1, C.Fence, M.Wood, "solid", { Transparency = 1, CastShadow = false, CanQuery = false })
				bbox(S, "FenceRail", c - 0.12, c + 0.12, G + 1.2, G + 1.5, s0, s1, C.Fence, M.Wood, "deco")
				bbox(S, "FenceRail", c - 0.12, c + 0.12, G + 3.0, G + 3.3, s0, s1, C.Fence, M.Wood, "deco")
			end
			local n = math.max(1, math.floor((s1 - s0) / 8 + 0.5))
			for i = 0, n do
				local t = s0 + (s1 - s0) * i / n
				if axis == "x" then
					bbox(S, "FencePost", t - 0.3, t + 0.3, G, G + 4, c - 0.3, c + 0.3, vary(C.Fence, 0.03), M.Wood, "deco", { CastShadow = true })
				else
					bbox(S, "FencePost", c - 0.3, c + 0.3, G, G + 4, t - 0.3, t + 0.3, vary(C.Fence, 0.03), M.Wood, "deco", { CastShadow = true })
				end
			end
		end
	end
	fenceLine("x", LOT.z0, LOT.x0, LOT.x1, { { -2.5, 2.5 }, { 26, 40 } })
	fenceLine("x", LOT.z1, LOT.x0, LOT.x1, { { -2.5, 2.5 } })
	fenceLine("z", LOT.x0, LOT.z0, LOT.z1, {})
	fenceLine("z", LOT.x1, LOT.z0, LOT.z1, {})
	-- Ворота подъезда (закрыты, сетчатые): блокиратор + рама
	bbox(S, "DriveGateBlock", 26, 40, G, G + 6, LOT.z0 - 0.2, LOT.z0 + 0.2, C.Metal, M.Metal, "solid", { Transparency = 1, CastShadow = false, CanQuery = false })
	bbox(S, "DriveGate", 26, 40, G + 0.4, G + 4, LOT.z0 - 0.08, LOT.z0 + 0.08, C.MetalDark, M.DiamondPlate, "deco", { Transparency = 0.45 })
	bbox(S, "DriveGateFrame", 26, 40, G + 3.9, G + 4.2, LOT.z0 - 0.15, LOT.z0 + 0.15, C.Metal, M.Metal, "deco")
	bbox(S, "DriveGateFrame", 32.85, 33.15, G, G + 4.2, LOT.z0 - 0.15, LOT.z0 + 0.15, C.Metal, M.Metal, "deco")
	-- Открытые калитки (створка декоративно распахнута внутрь)
	for _, gz in { LOT.z0, LOT.z1 } do
		local sgn = if gz < 0 then 1 else -1
		box(S, "Gate", CFrame.new(-2.5, G + 1.9, gz) * CFrame.Angles(0, rad(-70 * sgn), 0) * CFrame.new(2.3, 0, 0), Vector3.new(4.6, 3.4, 0.2), C.Fence, M.Wood, "deco", { Transparency = 0.1 })
	end
	-- Невидимые стены границы игровой зоны
	for _, w in {
		{ CFrame.new(0, 20, -80), Vector3.new(262, 40, 1) },
		{ CFrame.new(0, 20, 80), Vector3.new(262, 40, 1) },
		{ CFrame.new(-130, 20, 0), Vector3.new(1, 40, 160) },
		{ CFrame.new(130, 20, 0), Vector3.new(1, 40, 160) },
	} do
		box(S, "Boundary", w[1], w[2], C.Ground, M.SmoothPlastic, "solid", { Transparency = 1, CanQuery = false, CastShadow = false })
	end

	-- Сарай x 25..35, z 40..50: стены y -1..7, дверной проём x 28..32 на z=40, плоская крыша
	bbox(S, "Floor", 25, 35, G - 0.5, G + 0.1, 40, 50, C.ConcreteDark, M.Concrete)
	wall(S, "ShedWall", "x", 40, 25, 35, G, 7, C.WoodDark, M.WoodPlanks, { { a = 28, b = 32, y0 = G, y1 = 6 } }, 0.6)
	wall(S, "ShedWall", "x", 50, 25, 35, G, 7, C.WoodDark, M.WoodPlanks, nil, 0.6)
	wall(S, "ShedWall", "z", 25, 40, 50, G, 7, C.WoodDark, M.WoodPlanks, nil, 0.6)
	wall(S, "ShedWall", "z", 35, 40, 50, G, 7, C.WoodDark, M.WoodPlanks, nil, 0.6)
	bbox(S, "ShedRoof", 24.2, 35.8, 7, 7.6, 39.2, 50.8, C.Roof, M.Slate, "solid", { CanQuery = false })
	bbox(S, "DoorFrame", 27.6, 28, G, 6.3, 39.6, 40.4, C.Fence, M.Wood, "deco")
	bbox(S, "DoorFrame", 32, 32.4, G, 6.3, 39.6, 40.4, C.Fence, M.Wood, "deco")
	bbox(S, "DoorFrame", 27.6, 32.4, 6, 6.3, 39.6, 40.4, C.Fence, M.Wood, "deco")
	-- Укрытие Shed: закуток в северо-восточном углу за бочками и ящиком
	do
		local m = hidingSpot("Shed", "Shed", "Shed", CFrame.new(33.2, G + 0.5, 48.2), lookCF(Vector3.new(33.2, G + 3.6, 48.2), Vector3.new(30, G + 3.6, 40)), "Shed")
		local body = model("Body", m)
		for _, z in { 47.2, 49.2 } do
			fbox(body, "Barrel", CFrame.new(31.1, G + 1.4, z) * CFrame.Angles(0, 0, rad(90)), Vector3.new(2.8, 1.9, 1.9), C.Blue, M.Metal, false, { Shape = Enum.PartType.Cylinder })
		end
		boxCrate(body, CFrame.new(33.2, G, 46.0), Vector3.new(2.4, 2.4, 1.6))
		fbox(body, "Sack", CFrame.new(30.6, G + 0.6, 45.4), Vector3.new(1.6, 1.2, 1.2), Color3.fromRGB(180, 160, 120), M.Fabric, false)
	end
	-- Полки сарая и инвентарь (Furniture)
	do
		local Fu = furniture
		local m = model("ShedShelves", Fu)
		for _, z in { 41, 46 } do
			fbox(m, "Post", CFrame.new(33.7, G + 2.5, z), Vector3.new(0.2, 5, 0.2), C.WoodDark, M.Wood, true)
			fbox(m, "Post", CFrame.new(34.4, G + 2.5, z), Vector3.new(0.2, 5, 0.2), C.WoodDark, M.Wood, true)
		end
		for i = 0, 2 do
			fbox(m, "Shelf", CFrame.new(34.05, G + 1.0 + i * 1.5, 43.5), Vector3.new(0.9, 0.12, 5), C.Wood, M.Wood, i > 0)
		end
		for i = 1, 5 do
			fbox(m, "Pot", CFrame.new(34.05, G + 1.0 + (i % 3) * 1.5 + 0.45, 41.5 + i * 0.8), Vector3.new(0.6, 0.8, 0.6), Color3.fromRGB(150, 90, 70), M.SmoothPlastic, true)
		end
		fbox(Fu, "Rake", CFrame.new(25.6, G + 2.6, 48.5) * CFrame.Angles(0, 0, rad(-10)), Vector3.new(0.12, 5.2, 0.12), C.Wood, M.Wood, true)
		fbox(Fu, "RakeHead", CFrame.new(26.1, G + 5.1, 48.5), Vector3.new(0.12, 0.3, 1.6), C.MetalDark, M.Metal, true)
		fbox(Fu, "Shovel", CFrame.new(25.6, G + 2.6, 47.0) * CFrame.Angles(0, 0, rad(-8)), Vector3.new(0.12, 5.0, 0.12), C.Wood, M.Wood, true)
		fbox(Fu, "ShovelHead", CFrame.new(25.75, G + 0.6, 47.0), Vector3.new(0.3, 1.2, 0.8), C.MetalDark, M.Metal, true)
		do
			local mw = model("Mower", Fu)
			fbox(mw, "Body", CFrame.new(27.5, G + 0.8, 44), Vector3.new(2.0, 1.0, 2.6), C.Red, M.Metal)
			fbox(mw, "Handle", CFrame.new(27.5, G + 2.4, 45.4) * CFrame.Angles(rad(40), 0, 0), Vector3.new(1.8, 0.12, 3.0), C.MetalDark, M.Metal, true)
		end
	end
end

----------------------------------------------------------------------
-- Улица, тротуары, фонари, соседние дома, фургон, деревья и кусты
----------------------------------------------------------------------
do
	local S = structure
	bbox(S, "Road", -130, 100, G - 0.3, G + 0.05, -60, -44, C.Asphalt, M.Asphalt)
	part({ Name = "Road", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(100, G - 0.125, -52) * CFrame.Angles(0, 0, rad(90)), Size = Vector3.new(0.35, 36, 36), Color = C.Asphalt, Material = M.Asphalt, CanCollide = true, CanQuery = true, CanTouch = false }, S)
	bbox(S, "Sidewalk", -130, 118, G - 0.3, G + 0.06, -44, -40, C.Sidewalk, M.Concrete)
	bbox(S, "Sidewalk", -130, 118, G - 0.3, G + 0.06, -64, -60, C.Sidewalk, M.Concrete)
	bbox(S, "Curb", -130, 82, G + 0.06, G + 0.3, -44.4, -43.8, C.Concrete, M.Concrete, "deco")
	bbox(S, "Curb", -130, 82, G + 0.06, G + 0.3, -60.2, -59.6, C.Concrete, M.Concrete, "deco")
	for x = -124, 80, 12 do
		bbox(S, "RoadLine", x, x + 5, G + 0.05, G + 0.08, -52.25, -51.75, Color3.fromRGB(190, 170, 70), M.SmoothPlastic, "deco")
	end
	-- Люк, решётка ливнёвки
	part({ Name = "Manhole", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(-20, G + 0.07, -48) * CFrame.Angles(0, 0, rad(90)), Size = Vector3.new(0.06, 2.4, 2.4), Color = C.MetalDark, Material = M.Metal, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, S)
	bbox(S, "Drain", 10, 13, G + 0.04, G + 0.1, -45.2, -44.2, C.MetalDark, M.Metal, "deco")

	-- Фонари улицы: 3 горят, четвёртый (у тупика) — тёмный
	local function streetLamp(x: number, z: number, lit: boolean)
		local m = model("StreetLamp", S)
		box(m, "Pole", CFrame.new(x, G + 7, z), Vector3.new(0.6, 14, 0.6), C.MetalDark, M.Metal, "solid", { CanQuery = false })
		box(m, "PoleBase", CFrame.new(x, G + 0.4, z), Vector3.new(1.4, 0.8, 1.4), C.MetalDark, M.Metal, "deco")
		box(m, "Arm", CFrame.new(x, G + 13.8, z - 1.6), Vector3.new(0.4, 0.4, 3.6), C.MetalDark, M.Metal, "deco")
		box(m, "Head", CFrame.new(x, G + 13.5, z - 3.2), Vector3.new(1.8, 0.7, 1.8), C.MetalDark, M.Metal, "deco", { CastShadow = true })
		local bulb = box(m, "Bulb", CFrame.new(x, G + 13.05, z - 3.2), Vector3.new(1.3, 0.25, 1.3), if lit then C.Bulb else Color3.fromRGB(70, 70, 68), if lit then M.Neon else M.SmoothPlastic, "deco")
		if lit then
			pointLight(bulb, "Light", 30, 1.0, Color3.fromRGB(255, 205, 150), true)
		end
		return m
	end
	streetLamp(-80, -42.5, true)
	streetLamp(-30, -42.5, true)
	streetLamp(20, -42.5, true)
	streetLamp(95, -33.5, false)

	-- Соседние дома-фасады
	local function neighbour(cx: number)
		local m = model("NeighbourHouse", S)
		local x0, x1, z0, z1 = cx - 14, cx + 14, -36, -18
		local col = vary(C.SidingDark, 0.04)
		bbox(m, "Lawn", cx - 22, cx + 22, G - 0.3, G + 0.04, -40, -8, vary(C.LawnDark, 0.02), M.Grass, "solid", { CanQuery = true })
		bbox(m, "NWall", x0, x1, G, G + 20, z0, z0 + 1, col, M.WoodPlanks)
		bbox(m, "NWall", x0, x1, G, G + 20, z1 - 1, z1, col, M.WoodPlanks)
		bbox(m, "NWall", x0, x0 + 1, G, G + 20, z0, z1, col, M.WoodPlanks)
		bbox(m, "NWall", x1 - 1, x1, G, G + 20, z0, z1, col, M.WoodPlanks)
		bbox(m, "NCeiling", x0, x1, G + 19.5, G + 20, z0, z1, col, M.WoodPlanks, "deco")
		for _, sgn in { -1, 1 } do
			part({ ClassName = "WedgePart", Name = "NRoof", Size = Vector3.new(30, 5, 10), CFrame = CFrame.new(cx, G + 22.5, -27 + sgn * 5) * CFrame.Angles(0, if sgn > 0 then rad(180) else 0, 0), Color = C.Roof, Material = M.Slate, CanTouch = false, CanQuery = false }, m)
		end
		for _, wx in { cx - 9, cx, cx + 9 } do
			for _, wy in { G + 4.5, G + 14.5 } do
				if not (wx == cx and wy < G + 10) then
					box(m, "NWindow", CFrame.new(wx, wy + 2, z0 - 0.05), Vector3.new(4, 4, 0.2), C.GlassDark, M.Glass, "deco", { Transparency = 0.2, Reflectance = 0.15 })
					box(m, "NTrim", CFrame.new(wx, wy + 2, z0 - 0.1), Vector3.new(4.6, 4.6, 0.12), C.Trim, M.SmoothPlastic, "deco")
				end
			end
		end
		box(m, "NDoor", CFrame.new(cx, G + 3.5, z0 - 0.08), Vector3.new(4, 7, 0.2), C.Door, M.Wood, "deco")
		bbox(m, "NPorch", cx - 6, cx + 6, G - 0.2, G + 0.4, z0 - 5, z0, C.WoodLight, M.WoodPlanks)
		bbox(m, "NPorchRoof", cx - 6.5, cx + 6.5, G + 8.5, G + 9, z0 - 5.5, z0, C.Roof, M.Slate, "deco", { CastShadow = true })
		for _, px in { cx - 5.5, cx + 5.5 } do
			bbox(m, "NPost", px - 0.3, px + 0.3, G, G + 8.5, z0 - 5, z0 - 4.4, C.Trim, M.Wood, "deco", { CastShadow = true })
		end
		bbox(m, "NPath", cx - 1.5, cx + 1.5, G - 0.2, G + 0.06, -40, z0 - 5, C.Sidewalk, M.Concrete)
		bbox(m, "NChimney", cx + 8, cx + 10.5, G + 18, G + 27, -30, -27.5, C.Brick, M.Brick, "deco", { CastShadow = true })
		return m
	end
	neighbour(-70)
	neighbour(70)
	-- Низкие заборы соседей (декор)
	for _, cx in { -70, 70 } do
		for x = cx - 22, cx + 22, 4 do
			bbox(S, "NFencePost", x - 0.2, x + 0.2, G, G + 2.4, -40.2, -39.8, C.Trim, M.Wood, "deco")
		end
		bbox(S, "NFenceRail", cx - 22, cx + 22, G + 1.8, G + 2.1, -40.1, -39.9, C.Trim, M.Wood, "deco")
	end

	-- Фургон у тупика (серый, без надписей)
	do
		local m = model("Van", S)
		local vx, vz = 100, -52
		bbox(m, "Body", vx - 8, vx + 3, G + 1.2, G + 6.6, vz - 2.6, vz + 2.6, C.Van, M.Metal)
		bbox(m, "Cab", vx + 3, vx + 8, G + 1.2, G + 5.4, vz - 2.6, vz + 2.6, C.Van, M.Metal)
		bbox(m, "Hood", vx + 8, vx + 9.5, G + 1.2, G + 3.8, vz - 2.5, vz + 2.5, vary(C.Van, 0.02), M.Metal, "deco", { CastShadow = true })
		box(m, "Windshield", CFrame.new(vx + 8.1, G + 4.6, vz) * CFrame.Angles(0, 0, rad(-25)), Vector3.new(0.2, 2.0, 4.6), C.GlassDark, M.Glass, "deco", { Transparency = 0.25, Reflectance = 0.2 })
		for _, sz in { -1, 1 } do
			box(m, "SideWindow", CFrame.new(vx + 5.5, G + 4.5, vz + sz * 2.65), Vector3.new(2.6, 1.6, 0.1), C.GlassDark, M.Glass, "deco", { Transparency = 0.25 })
			box(m, "Mirror", CFrame.new(vx + 7.6, G + 4.6, vz + sz * 3.0), Vector3.new(0.4, 0.6, 0.5), C.MetalDark, M.Metal, "deco")
			for _, wx in { vx - 5.5, vx + 5.5 } do
				box(m, "Wheel", CFrame.new(wx, G + 1.2, vz + sz * 2.4) * CFrame.Angles(0, rad(90), 0), Vector3.new(2.4, 0.9, 2.4), Color3.fromRGB(26, 26, 28), M.SmoothPlastic, "deco", { Shape = Enum.PartType.Cylinder, CastShadow = true })
				box(m, "Hub", CFrame.new(wx, G + 1.2, vz + sz * 2.75) * CFrame.Angles(0, rad(90), 0), Vector3.new(1.2, 0.2, 1.2), C.Metal, M.Metal, "deco", { Shape = Enum.PartType.Cylinder })
			end
			box(m, "Headlight", CFrame.new(vx + 9.6, G + 3.0, vz + sz * 1.8), Vector3.new(0.15, 0.7, 1.0), Color3.fromRGB(120, 120, 110), M.SmoothPlastic, "deco")
			box(m, "TailLight", CFrame.new(vx - 8.1, G + 2.6, vz + sz * 2.0), Vector3.new(0.15, 1.0, 0.6), Color3.fromRGB(120, 30, 30), M.SmoothPlastic, "deco")
		end
		bbox(m, "Bumper", vx + 9.4, vx + 9.9, G + 1.4, G + 2.0, vz - 2.7, vz + 2.7, C.MetalDark, M.Metal, "deco")
		bbox(m, "Bumper", vx - 8.4, vx - 7.9, G + 1.4, G + 2.0, vz - 2.7, vz + 2.7, C.MetalDark, M.Metal, "deco")
		bbox(m, "RearDoorSeam", vx - 8.15, vx - 8.05, G + 1.4, G + 6.4, vz - 0.05, vz + 0.05, C.MetalDark, M.Metal, "deco")
		bbox(m, "SideDoorSeam", vx + 2.95, vx + 3.05, G + 1.4, G + 6.4, vz - 2.7, vz - 2.6, C.MetalDark, M.Metal, "deco")
	end

	-- Деревья и кусты по краям участка и вокруг
	local function bush(x: number, z: number, s: number)
		deco({ Name = "Bush", Shape = Enum.PartType.Ball, CFrame = CFrame.new(x, G + s * 0.4, z), Size = Vector3.new(s, s * 0.8, s), Color = vary(C.Bush, 0.05), Material = M.Grass, CastShadow = true, CanCollide = true }, S)
	end
	for _, t in {
		{ -42, -30, 1.1 }, { 42, 30, 1.2 }, { -41, 20, 1.0 }, { -40, 58, 1.3 }, { 43, 48, 1.1 }, { -60, -10, 1.4 }, { 58, -12, 1.2 },
		{ -105, -30, 1.3 }, { -118, -20, 1.0 }, { 118, -20, 1.2 }, { -30, 74, 1.2 }, { 30, 74, 1.4 }, { 60, 60, 1.3 }, { -70, 50, 1.5 }, { 80, 20, 1.2 }, { -90, 10, 1.1 }, { 110, -70, 1.3 }, { -40, -74, 1.2 }, { 50, -72, 1.1 },
	} do
		buildTree(S, Vector3.new(t[1], G, t[2]), t[3], true)
	end
	for _, b in { { -12, -18.5, 2.6 }, { 12, -18.5, 2.4 }, { -22, -18.5, 2.2 }, { 22, -18.5, 2.6 }, { -45, -36, 3 }, { 45, -36, 3 }, { -45, 60, 3 }, { 45, 62, 3 }, { -26, 62, 2.6 }, { 26, 62, 2.4 }, { 44, 18, 2.4 }, { -44, 0, 2.8 }, { 6, -41.5, 2 }, { -6, -41.5, 2 } } do
		bush(b[1], b[2], b[3])
	end
end

----------------------------------------------------------------------
-- Лобби: полицейский блокпост на тёмной дороге (смещение Config.Map.LobbyOrigin)
----------------------------------------------------------------------
local lobby = folder("Lobby")
do
	local O = LOBBY_ORIGIN
	local S = folder("Structure", lobby)
	local Fu = folder("Furniture", lobby)
	local function L(x: number, y: number, z: number, yawDeg: number?): CFrame
		return cfYaw(O.X + x, O.Y + y, O.Z + z, yawDeg)
	end
	local function lbbox(parent, name, x0, x1, y0, y1, z0, z1, color, material, kind, extra)
		return bbox(parent, name, O.X + x0, O.X + x1, O.Y + y0, O.Y + y1, O.Z + z0, O.Z + z1, color, material, kind, extra)
	end
	-- Земля, дорога, обочины, разметка
	lbbox(S, "Ground", -70, 70, -4, 0, -70, 70, C.Ground, M.Grass, "solid", { CanQuery = true })
	lbbox(S, "Road", -14, 14, -0.3, 0.06, -70, 70, C.Asphalt, M.Asphalt)
	lbbox(S, "Shoulder", -18, -14, -0.3, 0.03, -70, 70, C.Dirt, M.Ground)
	lbbox(S, "Shoulder", 14, 18, -0.3, 0.03, -70, 70, C.Dirt, M.Ground)
	for z = -66, 62, 12 do
		lbbox(S, "RoadLine", -0.25, 0.25, 0.06, 0.09, z, z + 5, Color3.fromRGB(190, 170, 70), M.SmoothPlastic, "deco")
	end
	lbbox(S, "RoadLine", -13.6, -13.2, 0.06, 0.09, -70, 70, Color3.fromRGB(200, 200, 200), M.SmoothPlastic, "deco")
	lbbox(S, "RoadLine", 13.2, 13.6, 0.06, 0.09, -70, 70, Color3.fromRGB(200, 200, 200), M.SmoothPlastic, "deco")
	-- Невидимые стены вокруг лобби (±60)
	for _, w in {
		{ L(0, 15, -60), Vector3.new(122, 30, 1) },
		{ L(0, 15, 60), Vector3.new(122, 30, 1) },
		{ L(-60, 15, 0), Vector3.new(1, 30, 122) },
		{ L(60, 15, 0), Vector3.new(1, 30, 122) },
	} do
		box(S, "Boundary", w[1], w[2], C.Ground, M.SmoothPlastic, "solid", { Transparency = 1, CanQuery = false, CastShadow = false })
	end
	-- Барьеры поперёк дороги (козлы с полосами), табличка ROAD CLOSED
	for i, bx in { -8.5, 0, 8.5 } do
		local m = model("Barrier", S)
		for _, dz in { -0.6, 0.6 } do
			for _, dx in { -3.6, 3.6 } do
				box(m, "Leg", L(bx + dx, 1.6, -14 + dz) * CFrame.Angles(rad(dz * 25), 0, 0), Vector3.new(0.3, 3.4, 0.3), C.MetalDark, M.Metal, "deco")
			end
		end
		local board = box(m, "Board", L(bx, 2.6, -14), Vector3.new(8, 1.2, 0.3), Color3.fromRGB(230, 230, 220), M.SmoothPlastic, "solid")
		for k = 0, 3 do
			box(m, "Stripe", L(bx - 3.2 + k * 2, 2.6, -14.17), Vector3.new(1.0, 1.2, 0.05), Color3.fromRGB(230, 110, 40), M.SmoothPlastic, "deco")
		end
		box(m, "LowerBar", L(bx, 1.0, -14), Vector3.new(8, 0.3, 0.3), C.MetalDark, M.Metal, "solid")
		if i == 2 then
			local sign = box(m, "Sign", L(bx, 4.4, -14), Vector3.new(6, 2.2, 0.3), Color3.fromRGB(230, 110, 40), M.SmoothPlastic, "deco")
			label(sign, Enum.NormalId.Back, "ROAD CLOSED", Color3.fromRGB(20, 20, 20), nil, 40)
			label(sign, Enum.NormalId.Front, "ROAD CLOSED", Color3.fromRGB(20, 20, 20), nil, 40)
		end
	end
	-- Ограждающая лента на стойках вдоль обочин
	for _, sx in { -13, 13 } do
		for z = -10, 10, 10 do
			box(S, "TapePost", L(sx, 1.8, z), Vector3.new(0.3, 3.6, 0.3), C.MetalDark, M.Metal, "deco")
			box(S, "TapeBase", L(sx, 0.2, z), Vector3.new(1.4, 0.3, 1.4), C.MetalDark, M.Metal, "deco")
		end
		box(S, "Tape", L(sx, 3.1, 0), Vector3.new(0.08, 0.5, 20), C.Yellow, M.SmoothPlastic, "deco")
	end
	box(S, "Tape", L(0, 3.1, -10), Vector3.new(26, 0.5, 0.08), C.Yellow, M.SmoothPlastic, "deco")
	-- Конусы
	for _, c in { { -11, -20 }, { 11, -20 }, { -6, -18 }, { 6, -18 } } do
		box(S, "Cone", L(c[1], 0.9, c[2]), Vector3.new(1.2, 1.8, 1.2), Color3.fromRGB(230, 110, 40), M.SmoothPlastic, "deco")
		box(S, "ConeBase", L(c[1], 0.1, c[2]), Vector3.new(1.8, 0.2, 1.8), C.MetalDark, M.SmoothPlastic, "deco")
	end
	-- Патрульные машины (силуэты) с тусклыми красно-синими огнями
	local function patrolCar(x: number, z: number, yaw: number)
		local m = model("PatrolCar", S)
		local function P(dx, dy, dz)
			return L(x, 0, z, yaw) * CFrame.new(dx, dy, dz)
		end
		box(m, "Body", P(0, 2.0, 0), Vector3.new(5.2, 2.0, 11), C.Police, M.Metal, "solid")
		box(m, "Cab", P(0, 3.8, -0.6), Vector3.new(4.4, 1.7, 5.4), C.Police, M.Metal, "solid")
		box(m, "Stripe", P(0, 2.2, 0), Vector3.new(5.3, 0.5, 11.1), Color3.fromRGB(230, 230, 230), M.SmoothPlastic, "deco")
		for _, sx in { -2.25, 2.25 } do
			box(m, "Window", P(sx, 3.9, -0.6), Vector3.new(0.1, 1.2, 4.6), C.GlassDark, M.Glass, "deco", { Transparency = 0.2 })
		end
		box(m, "Windshield", P(0, 3.9, -3.35) * CFrame.Angles(rad(28), 0, 0), Vector3.new(4.2, 1.6, 0.12), C.GlassDark, M.Glass, "deco", { Transparency = 0.2 })
		box(m, "RearGlass", P(0, 3.9, 2.15) * CFrame.Angles(rad(-28), 0, 0), Vector3.new(4.2, 1.6, 0.12), C.GlassDark, M.Glass, "deco", { Transparency = 0.2 })
		for _, dz in { -3.4, 3.4 } do
			for _, sx in { -2.3, 2.3 } do
				box(m, "Wheel", P(sx, 1.0, dz), Vector3.new(0.7, 2.0, 2.0), Color3.fromRGB(26, 26, 28), M.SmoothPlastic, "deco", { Shape = Enum.PartType.Cylinder, CastShadow = true })
			end
		end
		box(m, "LightBar", P(0, 4.8, -0.8), Vector3.new(3.6, 0.35, 0.8), C.MetalDark, M.Metal, "deco")
		local red = box(m, "RedLight", P(-1.0, 4.85, -0.8), Vector3.new(1.4, 0.4, 0.7), Color3.fromRGB(220, 40, 40), M.Neon, "deco")
		local blue = box(m, "BlueLight", P(1.0, 4.85, -0.8), Vector3.new(1.4, 0.4, 0.7), Color3.fromRGB(50, 90, 230), M.Neon, "deco")
		pointLight(red, "Light", 16, 0.6, Color3.fromRGB(255, 60, 60), false)
		pointLight(blue, "Light", 16, 0.6, Color3.fromRGB(70, 110, 255), false)
		for _, sx in { -1.6, 1.6 } do
			box(m, "Headlight", P(sx, 2.2, -5.55), Vector3.new(1.0, 0.6, 0.12), Color3.fromRGB(220, 220, 200), M.SmoothPlastic, "deco")
			box(m, "TailLight", P(sx, 2.2, 5.55), Vector3.new(1.0, 0.5, 0.12), Color3.fromRGB(150, 30, 30), M.SmoothPlastic, "deco")
		end
		return m
	end
	patrolCar(-23, -2, 12)
	patrolCar(23, 14, 195)
	-- Прожектор на треноге, направлен на ReadyPad
	do
		local m = model("Floodlight", S)
		local base = Vector3.new(O.X - 13, O.Y, O.Z + 20)
		for i = 0, 2 do
			local a = i * 2 * math.pi / 3
			box(m, "Leg", CFrame.new(base + Vector3.new(math.cos(a) * 0.9, 3.0, math.sin(a) * 0.9)) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, rad(-12)), Vector3.new(0.2, 6.2, 0.2), C.MetalDark, M.Metal, "deco")
		end
		box(m, "Mast", CFrame.new(base + Vector3.new(0, 7.5, 0)), Vector3.new(0.3, 4, 0.3), C.MetalDark, M.Metal, "deco")
		local headPos = base + Vector3.new(0, 9.5, 0)
		local headCF = lookCF(headPos, Vector3.new(O.X, O.Y + 0.5, O.Z + 6))
		local head = box(m, "Head", headCF, Vector3.new(2.6, 1.8, 1.4), C.MetalDark, M.Metal, "deco", { CastShadow = true })
		box(m, "Lens", headCF * CFrame.new(0, 0, -0.72), Vector3.new(2.2, 1.4, 0.1), C.Bulb, M.Neon, "deco")
		spotLight(head, "Light", 50, 1.8, 70, Color3.fromRGB(255, 240, 215), Enum.NormalId.Front, true)
		box(m, "Generator", L(-16, 1.2, 24), Vector3.new(3, 2.4, 2), C.Metal, M.DiamondPlate, "solid")
	end
	-- Уличные фонари лобби
	for _, lp in { { -17, 36 }, { 17, -30 } } do
		box(S, "LampPole", L(lp[1], 6, lp[2]), Vector3.new(0.5, 12, 0.5), C.MetalDark, M.Metal, "solid", { CanQuery = false })
		local b = box(S, "LampBulb", L(lp[1], 12.2, lp[2]), Vector3.new(1.4, 0.5, 1.4), C.Bulb, M.Neon, "deco")
		box(S, "LampHead", L(lp[1], 12.6, lp[2]), Vector3.new(1.8, 0.4, 1.8), C.MetalDark, M.Metal, "deco")
		pointLight(b, "Light", 26, 0.9, Color3.fromRGB(255, 205, 150), true)
	end
	-- Деревья и кусты по краям
	for _, t in { { -40, -40, 1.3 }, { 40, -30, 1.2 }, { -45, 10, 1.4 }, { 44, 40, 1.3 }, { -30, 50, 1.2 }, { 30, 52, 1.1 }, { -50, -10, 1.0 }, { 50, 0, 1.2 } } do
		buildTree(S, Vector3.new(O.X + t[1], O.Y, O.Z + t[2]), t[3], true)
	end
	for _, b in { { -20, -8, 2.6 }, { 21, 30, 2.4 }, { -24, 44, 3 }, { 26, -40, 2.6 } } do
		deco({ Name = "Bush", Shape = Enum.PartType.Ball, CFrame = L(b[1], b[3] * 0.4, b[2]), Size = Vector3.new(b[3], b[3] * 0.8, b[3]), Color = vary(C.Bush, 0.05), Material = M.Grass, CastShadow = true, CanCollide = true }, S)
	end

	-- ReadyPad: площадка на дороге с янтарной неоновой окантовкой + Prompt
	local pad = part({ Name = "ReadyPad", CFrame = L(0, 0.16, 6), Size = Vector3.new(8, 0.2, 8), Color = Color3.fromRGB(30, 30, 34), Material = M.SmoothPlastic, CanCollide = true, CanQuery = true, CanTouch = false, CastShadow = false }, lobby)
	prompt(pad, "Prompt", "Ready", "Ready Pad", 0, 7)
	for _, e in { { 0, -4, 8.3, 0.3 }, { 0, 4, 8.3, 0.3 }, { -4, 0, 0.3, 8.3 }, { 4, 0, 0.3, 8.3 } } do
		deco({ Name = "PadEdge", CFrame = L(e[1], 0.3, 6 + e[2]), Size = Vector3.new(e[3], 0.12, e[4]), Color = C.Neon, Material = M.Neon }, Fu)
	end
	deco({ Name = "PadMark", CFrame = L(0, 0.27, 6), Size = Vector3.new(3, 0.04, 3), Color = C.Neon, Material = M.Neon, Transparency = 0.5 }, Fu)

	-- PerkKiosk: фургон-киоск с открытым боковым люком и прилавком, лицом к дороге (-X)
	do
		local k = model("PerkKiosk", lobby)
		local kx, kz = 27, -24
		lbbox(k, "Body", kx - 3, kx + 3, 1.2, 7.4, kz - 7, kz + 5, Color3.fromRGB(160, 150, 130), M.Metal)
		lbbox(k, "Cab", kx - 3, kx + 3, 1.2, 5.6, kz + 5, kz + 9, Color3.fromRGB(160, 150, 130), M.Metal)
		box(k, "Windshield", L(kx, 4.6, kz + 9.05) * CFrame.Angles(rad(-20), 0, 0), Vector3.new(5.2, 1.8, 0.15), C.GlassDark, M.Glass, "deco", { Transparency = 0.25 })
		for _, dz in { kz - 4.5, kz + 6.5 } do
			for _, sx in { -2.9, 2.9 } do
				box(k, "Wheel", L(kx + sx, 1.2, dz), Vector3.new(0.8, 2.4, 2.4), Color3.fromRGB(26, 26, 28), M.SmoothPlastic, "deco", { Shape = Enum.PartType.Cylinder, CastShadow = true })
			end
		end
		-- люк (поднятая створка-навес) и окно киоска
		box(k, "Hatch", L(kx - 3.4, 7.2, kz - 1) * CFrame.Angles(0, 0, rad(-70)), Vector3.new(0.2, 4.4, 9), Color3.fromRGB(150, 140, 120), M.Metal, "deco", { CastShadow = true })
		box(k, "Opening", L(kx - 3.05, 5.0, kz - 1), Vector3.new(0.12, 3.6, 9), Color3.fromRGB(28, 26, 24), M.SmoothPlastic, "deco")
		local counter = part({ Name = "Counter", CFrame = L(kx - 3.9, 3.0, kz - 1), Size = Vector3.new(1.8, 0.3, 9.4), Color = C.Wood, Material = M.Wood, CanCollide = true, CanQuery = true, CanTouch = false }, k)
		k.PrimaryPart = counter
		lbbox(k, "CounterFront", kx - 4.8, kx - 3.0, 0, 2.85, kz - 5.7, kz + 3.7, C.WoodDark, M.WoodPlanks)
		local sign = box(k, "Sign", L(kx - 3.4, 8.6, kz - 1), Vector3.new(0.3, 1.6, 7), C.MetalDark, M.Metal, "deco")
		label(sign, Enum.NormalId.Left, "PERKS", C.Neon, nil, 40)
		for i = 0, 5 do
			local b = deco({ Name = "StringLight", CFrame = L(kx - 4.6, 7.0, kz - 5 + i * 1.6), Size = Vector3.new(0.3, 0.3, 0.3), Color = C.Bulb, Material = M.Neon, Shape = Enum.PartType.Ball }, k)
			if i == 2 then
				pointLight(b, "Light", 12, 0.6, Color3.fromRGB(255, 210, 150), false)
			end
		end
		deco({ Name = "StringWire", CFrame = L(kx - 4.6, 7.2, kz - 1), Size = Vector3.new(0.06, 0.06, 9), Color = C.MetalDark, Material = M.Metal }, k)
		for i = 1, 3 do
			deco({ Name = "Jar", CFrame = L(kx - 3.6, 3.6, kz - 4 + i * 1.4), Size = Vector3.new(0.8, 0.9, 0.8), Color = Color3.fromHSV(0.08 + i * 0.1, 0.6, 0.8), Material = M.Glass, Transparency = 0.2 }, k)
		end
		prompt(counter, "Prompt", "Perks", "Kiosk", 0, 8)
	end

	-- Доска «как играть» (Board) и табло рекордов (Leaderboard): щиты на столбах лицом к дороге (+X)
	local function noticeBoard(name: string, z: number, title: string, bodyName: string, bodyText: string)
		local m = model(name, lobby)
		local bx = -25
		for _, dz in { -5.4, 5.4 } do
			lbbox(m, "Post", bx - 0.4, bx + 0.4, 0, 10, z + dz - 0.4, z + dz + 0.4, C.WoodDark, M.Wood)
		end
		lbbox(m, "Backing", bx - 0.5, bx + 0.1, 2.6, 9.6, z - 5.6, z + 5.6, C.WoodDark, M.WoodPlanks)
		lbbox(m, "Roof", bx - 1.2, bx + 1.2, 9.6, 10.1, z - 6.2, z + 6.2, C.Roof, M.Slate, "deco", { CastShadow = true })
		local screen = part({ Name = "Screen", CFrame = L(bx + 0.25, 6.1, z, -90), Size = Vector3.new(10.4, 6.4, 0.3), Color = Color3.fromRGB(20, 22, 26), Material = M.SmoothPlastic, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, m)
		m.PrimaryPart = screen
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Gui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0.2
		gui.Brightness = 1.2
		gui.Parent = screen
		local titleL = Instance.new("TextLabel")
		titleL.Name = "Title"
		titleL.Size = UDim2.fromScale(1, 0.18)
		titleL.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
		titleL.BorderSizePixel = 0
		titleL.TextColor3 = Color3.fromRGB(20, 18, 14)
		titleL.TextScaled = true
		titleL.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
		titleL.Text = title
		titleL.Parent = gui
		local body = Instance.new("TextLabel")
		body.Name = bodyName
		body.Position = UDim2.fromScale(0, 0.18)
		body.Size = UDim2.fromScale(1, 0.82)
		body.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
		body.BorderSizePixel = 0
		body.TextColor3 = Color3.fromRGB(235, 232, 225)
		body.TextScaled = true
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
		body.Text = bodyText
		body.Parent = gui
		local pad2 = Instance.new("UIPadding")
		pad2.PaddingLeft = UDim.new(0.04, 0)
		pad2.PaddingRight = UDim.new(0.04, 0)
		pad2.PaddingTop = UDim.new(0.05, 0)
		pad2.PaddingBottom = UDim.new(0.05, 0)
		pad2.Parent = body
		return m
	end
	noticeBoard("Board", -22, "HOW TO PLAY", "Text", Locale.t("HowToPlay"))
	noticeBoard("Leaderboard", 22, "BEST NIGHTS", "Rows", "")

	-- Спавны: SpawnLocation'ы на дороге
	local spawns = folder("Spawns", lobby)
	local idx = 0
	for _, z in { 26, 32 } do
		for _, x in { -6, -2, 2, 6 } do
			idx += 1
			local sp = part({
				ClassName = "SpawnLocation",
				Name = "Spawn" .. idx,
				CFrame = L(x, 0.56, z),
				Size = Vector3.new(4, 1, 4),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = true,
				CastShadow = false,
			}, spawns)
			sp.Neutral = true
			sp.Duration = 0
			sp.Enabled = true
			sp.AllowTeamChangeOnTouch = false
		end
	end
end

----------------------------------------------------------------------
-- Запись
----------------------------------------------------------------------
fs.writeFile("src/map/House.rbxmx", roblox.serializeModel({ house }, true))
fs.writeFile("src/map/Lobby.rbxmx", roblox.serializeModel({ lobby }, true))

local function countFolder(root: Instance, name: string): number
	local f = root:FindFirstChild(name)
	return if f then countParts(f) else 0
end
print(string.format("House: %d parts (Structure %d, Furniture %d, Doors %d, Windows %d, HidingSpots %d, Lights %d), %d waypoints, %d rooms",
	countParts(house), countFolder(house, "Structure"), countFolder(house, "Furniture"), countFolder(house, "Doors"), countFolder(house, "Windows"),
	countFolder(house, "HidingSpots"), countFolder(house, "Lights"), #waypointsF:GetChildren(), #roomsF:GetChildren()))
print(string.format("Lobby: %d parts", countParts(lobby)))
