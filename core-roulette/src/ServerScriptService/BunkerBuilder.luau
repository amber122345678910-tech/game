--!strict
--[[
	ServerScriptService.BunkerBuilder
	Процедурно строит весь мир CORE ROULETTE без единого внешнего ассета:
	освещение, бетонный бункер, восьмиугольный стол, 4 стула с ProximityPrompt,
	качающуюся лампу со SpotLight, нестабильное Ядро с 3 топливными стержнями,
	искры, звуки, 2 ЭЛТ-монитора с SurfaceGui и механический манипулятор-клешню.

	Звуки: только встроенные файлы клиента Roblox (rbxasset://sounds/...),
	они есть в каждой установке и не требуют загрузки ассетов.
	Текстуры частиц: встроенные rbxasset://textures/particles/...

	local world = BunkerBuilder.Build()
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local BunkerBuilder = {}

------------------------------------------------------------------------
-- ТИПЫ
------------------------------------------------------------------------

export type CRTLabelSet = {
	Screen: SurfaceGui,
	Header: TextLabel,
	Operator: TextLabel,
	Pot: TextLabel,
	Instability: TextLabel,
	InstabilityFill: Frame,
	Overclock: TextLabel,
	Cycle: TextLabel,
	Status: TextLabel,
	Timer: TextLabel,
}

export type SeatInfo = {
	Index: number,
	Seat: Seat,
	Prompt: ProximityPrompt,
	Model: Model,
	Angle: number, -- радианы, позиция на окружности стола
	Position: Vector3,
	Outward: Vector3, -- единичный вектор от центра стола к стулу (горизонтальный)
}

export type ManipulatorRig = {
	Model: Model,
	Pivot: BasePart, -- плечевой шарнир (статичен)
	Sleeve: BasePart, -- толстая гильза руки
	Piston: BasePart, -- телескопический шток
	Head: BasePart, -- запястье (= ManipulatorPart)
	Fingers: { BasePart },
	TipAttachment: Attachment,
	ArcLight: PointLight,
}

export type LampRig = {
	Model: Model,
	Root: BasePart, -- шарнир у потолка; клиент вращает его, остальное приварено
	Bulb: BasePart,
	Spotlight: SpotLight,
}

export type BuildResult = {
	Root: Model,
	Center: Vector3, -- центр стола на уровне столешницы
	CoreCenter: Vector3, -- центр светящегося ядра
	FloorY: number,
	TableTopY: number,
	Seats: { Seat },
	SeatInfos: { SeatInfo },
	Prompts: { ProximityPrompt },
	CoreModel: Model,
	CoreNeon: BasePart,
	CoreLight: PointLight,
	SparksEmitter: ParticleEmitter, -- на кончике клешни
	RimSparks: ParticleEmitter, -- на ободе контейнмента
	SteamEmitter: ParticleEmitter,
	FuelRods: { Model },
	CRTLabels: { CRTLabelSet },
	ManipulatorPart: BasePart,
	Manipulator: ManipulatorRig,
	Lamp: LampRig,
	Spotlight: SpotLight,
	Beacons: { SpotLight },
	Sounds: { [string]: Sound },
	SpawnLocation: SpawnLocation,
}

------------------------------------------------------------------------
-- КОНСТАНТЫ ГЕОМЕТРИИ
------------------------------------------------------------------------

local ROOM_CENTER = Vector3.new(0, 12, 0)
local FLOOR_Y = 0.2
local ROOM_HALF = 30 -- полуширина интерьера
local ROOM_HEIGHT = 24
local WALL_T = 2

local TABLE_INRADIUS = 6.2
local TABLE_TOP_Y = 3.6
local SEAT_RADIUS = 9.6
local SEAT_ANGLES_DEG = { 45, 135, 225, 315 }
local SEAT_TOP_Y = 2.2

local CORE_BASE_TOP = TABLE_TOP_Y + 0.5
local GLASS_HEIGHT = 3.6
local CORE_CENTER = Vector3.new(0, CORE_BASE_TOP + GLASS_HEIGHT * 0.5, 0)
local CAP_TOP = CORE_BASE_TOP + GLASS_HEIGHT + 0.45
local ROD_LENGTH = 5
local ROD_RADIUS_POS = 1.55
local ROD_ANGLES_DEG = { 90, 210, 330 }

local GANTRY_Y = 18.5
local GANTRY_Z = -6.5
local PIVOT_POS = Vector3.new(0, 15.2, GANTRY_Z)
local HEAD_REST = Vector3.new(0, 12, -2.2)

local LAMP_HINGE = Vector3.new(0, FLOOR_Y + ROOM_HEIGHT - 0.4, 0)
local LAMP_DROP = 4.6

------------------------------------------------------------------------
-- ПАЛИТРА
------------------------------------------------------------------------

local C = {
	Concrete = Color3.fromRGB(74, 76, 72),
	ConcreteDark = Color3.fromRGB(48, 50, 48),
	Steel = Color3.fromRGB(58, 62, 60),
	SteelDark = Color3.fromRGB(32, 35, 34),
	Gunmetal = Color3.fromRGB(42, 44, 44),
	Rust = Color3.fromRGB(105, 64, 40),
	Hazard = Color3.fromRGB(196, 150, 28),
	HazardBlack = Color3.fromRGB(20, 20, 18),
	Phosphor = Color3.fromRGB(120, 255, 140),
	Amber = Color3.fromRGB(255, 176, 48),
	CoreGreen = Color3.fromRGB(90, 255, 120),
	Glass = Color3.fromRGB(150, 220, 200),
	Warm = Color3.fromRGB(255, 214, 160),
	Alarm = Color3.fromRGB(255, 40, 30),
	Frame = Color3.fromRGB(14, 16, 15),
}

------------------------------------------------------------------------
-- ЗВУКИ (встроенные файлы клиента; меняются в одном месте)
------------------------------------------------------------------------

type SoundSpec = { Id: string, Volume: number, Speed: number, Looped: boolean, MinDist: number, MaxDist: number }

local SOUND_SPECS: { [string]: SoundSpec } = {
	Hum = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.35, Speed = 0.8, Looped = true, MinDist = 8, MaxDist = 90 },
	Geiger = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.55, Speed = 2.6, Looped = false, MinDist = 6, MaxDist = 60 },
	Scrape = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0, Speed = 1.6, Looped = true, MinDist = 6, MaxDist = 70 },
	Clunk = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Speed = 0.55, Looped = false, MinDist = 8, MaxDist = 90 },
	Explosion = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 1, Speed = 0.8, Looped = false, MinDist = 20, MaxDist = 300 },
	Siren = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0, Speed = 1.2, Looped = true, MinDist = 20, MaxDist = 300 },
	Overclock = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.8, Speed = 1.8, Looped = false, MinDist = 8, MaxDist = 90 },
	Eject = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 1, Speed = 0.7, Looped = false, MinDist = 10, MaxDist = 120 },
	Servo = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0, Speed = 1.5, Looped = true, MinDist = 6, MaxDist = 60 },
}

------------------------------------------------------------------------
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
------------------------------------------------------------------------

local function create(className: string, props: { [string]: any }, parent: Instance?): any
	local inst: any = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

type PartOpts = {
	Shape: Enum.PartType?,
	Collide: boolean?,
	Transparency: number?,
	Reflectance: number?,
	Shadow: boolean?,
}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	opts: PartOpts?
): BasePart
	local o: PartOpts = opts or {}
	local p: Part = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.Shape then
		p.Shape = o.Shape
	end
	local collide = if o.Collide == nil then true else o.Collide
	p.CanCollide = collide
	p.CanTouch = collide
	p.CanQuery = collide
	p.Transparency = o.Transparency or 0
	p.Reflectance = o.Reflectance or 0
	p.CastShadow = if o.Shadow == nil then true else o.Shadow
	p.Parent = parent
	return p
end

-- Вертикальный цилиндр (ось цилиндра Roblox — X, поворачиваем её в Y).
local function cylinderY(
	parent: Instance,
	name: string,
	center: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	opts: PartOpts?
): BasePart
	local o: PartOpts = opts or {}
	o.Shape = Enum.PartType.Cylinder
	return part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, o)
end

-- Цилиндр между двумя точками.
local function cylinderBetween(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	opts: PartOpts?
): BasePart
	local o: PartOpts = opts or {}
	o.Shape = Enum.PartType.Cylinder
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) * 0.5, b) * CFrame.Angles(0, math.rad(90), 0)
	return part(parent, name, Vector3.new(length, diameter, diameter), cf, color, material, o)
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material, opts: PartOpts?): BasePart
	local o: PartOpts = opts or {}
	o.Shape = Enum.PartType.Ball
	return part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, material, o)
end

local function weld(a: BasePart, b: BasePart): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function polar(angleRad: number, radius: number, y: number): Vector3
	return Vector3.new(math.cos(angleRad) * radius, y, math.sin(angleRad) * radius)
end

-- Регулярный восьмиугольник из 4 перекрывающихся полос (inradius r, толщина h).
local function octagon(parent: Instance, name: string, center: Vector3, inradius: number, thickness: number, color: Color3, material: Enum.Material, opts: PartOpts?): { BasePart }
	local side = 2 * inradius * math.tan(math.rad(22.5))
	local parts = {}
	for i = 0, 3 do
		local p = part(
			parent,
			name .. "_" .. tostring(i + 1),
			Vector3.new(inradius * 2, thickness, side),
			CFrame.new(center) * CFrame.Angles(0, math.rad(45 * i), 0),
			color,
			material,
			opts
		)
		table.insert(parts, p)
	end
	return parts
end

-- Процедурные горизонтальные ЭЛТ-полосы.
local function addScanlines(parent: GuiObject, count: number, transparency: number, zIndex: number)
	local holder = create("Frame", {
		Name = "Scanlines",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
		ClipsDescendants = true,
	}, parent) :: Frame
	for i = 0, count - 1 do
		create("Frame", {
			Name = "Line",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, i / count),
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = zIndex,
		}, holder)
	end
end

------------------------------------------------------------------------
-- ОСВЕЩЕНИЕ
------------------------------------------------------------------------

local function setupLighting()
	-- Technology не задаётся из скриптов во время игры: пробуем (сработает в плагинах/командной строке),
	-- а в Rojo-проекте оно уже выставлено в Future. Вручную: Lighting -> Technology = Future.
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)

	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(10, 12, 11)
	Lighting.OutdoorAmbient = Color3.fromRGB(8, 9, 9)
	Lighting.EnvironmentDiffuseScale = 0.15
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.15
	Lighting.ExposureCompensation = 0.25
	Lighting.FogColor = Color3.fromRGB(10, 12, 11)
	Lighting.FogStart = 25
	Lighting.FogEnd = 220

	for _, name in { "CoreAtmosphere", "CoreGrade", "CoreBloom", "CoreDepth", "CoreFlash" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("SunRaysEffect") then
			child:Destroy()
		end
	end

	create("Atmosphere", {
		Name = "CoreAtmosphere",
		Density = 0.42,
		Offset = 0,
		Color = Color3.fromRGB(40, 52, 44),
		Decay = Color3.fromRGB(16, 20, 18),
		Glare = 0,
		Haze = 2.4,
	}, Lighting)

	create("ColorCorrectionEffect", {
		Name = "CoreGrade",
		Brightness = 0.02,
		Contrast = 0.32,
		Saturation = -0.18,
		TintColor = Color3.fromRGB(232, 245, 226),
	}, Lighting)

	create("BloomEffect", {
		Name = "CoreBloom",
		Intensity = 1.1,
		Size = 32,
		Threshold = 0.92,
	}, Lighting)

	create("DepthOfFieldEffect", {
		Name = "CoreDepth",
		FarIntensity = 0.18,
		FocusDistance = 18,
		InFocusRadius = 22,
		NearIntensity = 0,
	}, Lighting)

	-- Вспышка детонации: клиент локально крутит Brightness/TintColor.
	create("ColorCorrectionEffect", {
		Name = "CoreFlash",
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	}, Lighting)
end

------------------------------------------------------------------------
-- КОМНАТА
------------------------------------------------------------------------

local function buildRoom(root: Model)
	local structure = folder(root, "Structure")
	local outer = ROOM_HALF + WALL_T * 0.5

	-- Пол: бетонная плита + рифлёная сталь под столом
	part(structure, "Floor", Vector3.new(ROOM_HALF * 2 + WALL_T * 2, 1, ROOM_HALF * 2 + WALL_T * 2), CFrame.new(0, FLOOR_Y - 0.5, 0), C.ConcreteDark, Enum.Material.Concrete)
	part(structure, "FloorPlate", Vector3.new(30, 0.1, 30), CFrame.new(0, FLOOR_Y + 0.05, 0), C.SteelDark, Enum.Material.DiamondPlate)
	-- Дренажные решётки по краям плиты
	for _, z in { -15.6, 15.6 } do
		part(structure, "Grate", Vector3.new(30, 0.12, 1.2), CFrame.new(0, FLOOR_Y + 0.06, z), C.Rust, Enum.Material.CorrodedMetal)
	end
	for _, x in { -15.6, 15.6 } do
		part(structure, "Grate", Vector3.new(1.2, 0.12, 32.4), CFrame.new(x, FLOOR_Y + 0.06, 0), C.Rust, Enum.Material.CorrodedMetal)
	end

	-- Кольцо "опасной зоны" из жёлто-чёрных сегментов вокруг стола
	local segments = 32
	local ringR = 12.6
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local pos = polar(a, ringR, FLOOR_Y + 0.11)
		local len = 2 * math.pi * ringR / segments
		part(
			structure,
			"HazardRing",
			Vector3.new(len * 1.02, 0.02, 0.9),
			CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)),
			if i % 2 == 0 then C.Hazard else C.HazardBlack,
			Enum.Material.SmoothPlastic,
			{ Collide = false, Shadow = false }
		)
	end

	-- Потолок
	part(structure, "Ceiling", Vector3.new(ROOM_HALF * 2 + WALL_T * 2, 1.5, ROOM_HALF * 2 + WALL_T * 2), CFrame.new(0, FLOOR_Y + ROOM_HEIGHT + 0.75, 0), C.ConcreteDark, Enum.Material.Concrete)

	-- 4 стены: нижняя ржавая панель + бетон
	local wallH = ROOM_HEIGHT
	local wallY = FLOOR_Y + wallH * 0.5
	local walls: { { pos: Vector3, size: Vector3, inward: Vector3 } } = {
		{ pos = Vector3.new(0, wallY, -outer), size = Vector3.new(ROOM_HALF * 2 + WALL_T * 2, wallH, WALL_T), inward = Vector3.new(0, 0, 1) },
		{ pos = Vector3.new(0, wallY, outer), size = Vector3.new(ROOM_HALF * 2 + WALL_T * 2, wallH, WALL_T), inward = Vector3.new(0, 0, -1) },
		{ pos = Vector3.new(-outer, wallY, 0), size = Vector3.new(WALL_T, wallH, ROOM_HALF * 2), inward = Vector3.new(1, 0, 0) },
		{ pos = Vector3.new(outer, wallY, 0), size = Vector3.new(WALL_T, wallH, ROOM_HALF * 2), inward = Vector3.new(-1, 0, 0) },
	}
	for i, w in walls do
		part(structure, "Wall" .. i, w.size, CFrame.new(w.pos), C.Concrete, Enum.Material.Concrete)
		-- Ржавая нижняя облицовка
		local along = if math.abs(w.inward.X) > 0 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
		local span = ROOM_HALF * 2
		local facePos = Vector3.new(w.pos.X, FLOOR_Y, w.pos.Z) + w.inward * (WALL_T * 0.5 + 0.15)
		local panelCF = CFrame.lookAt(facePos + Vector3.new(0, 1.6, 0), facePos + Vector3.new(0, 1.6, 0) + w.inward)
		part(structure, "WainscotPanel", Vector3.new(span, 3.2, 0.3), panelCF, C.Rust, Enum.Material.CorrodedMetal, { Collide = false })
		part(structure, "WainscotTrim", Vector3.new(span, 0.25, 0.45), panelCF + Vector3.new(0, 1.65, 0), C.Hazard, Enum.Material.Metal, { Collide = false })

		-- Стальные рёбра каждые 7.5 стадов
		local ribs = 8
		for r = 0, ribs do
			local offset = -ROOM_HALF + r * (span / ribs)
			local ribBase = facePos + along * offset
			part(
				structure,
				"Rib",
				Vector3.new(0.8, wallH, 0.6),
				CFrame.lookAt(ribBase + Vector3.new(0, wallH * 0.5, 0), ribBase + Vector3.new(0, wallH * 0.5, 0) + w.inward),
				C.SteelDark,
				Enum.Material.Metal,
				{ Collide = false }
			)
		end

		-- Трубы вдоль стены
		for k, h in { 17.2, 18.4 } do
			local a = facePos + Vector3.new(0, h, 0) + w.inward * (0.6 + k * 0.4) - along * ROOM_HALF
			local b = facePos + Vector3.new(0, h, 0) + w.inward * (0.6 + k * 0.4) + along * ROOM_HALF
			cylinderBetween(structure, "Pipe", a, b, 0.55 + k * 0.15, if k == 1 then C.Rust else C.Steel, Enum.Material.CorrodedMetal, { Collide = false })
		end

		-- Настенный бронированный светильник (тусклый янтарь)
		for _, offset in { -14, 14 } do
			local base = facePos + along * offset + Vector3.new(0, 9, 0) + w.inward * 0.4
			local housing = part(structure, "BulkheadLight", Vector3.new(1.4, 0.9, 0.6), CFrame.lookAt(base, base + w.inward), C.SteelDark, Enum.Material.Metal, { Collide = false })
			local glow = part(structure, "BulkheadGlow", Vector3.new(1.0, 0.55, 0.2), housing.CFrame * CFrame.new(0, 0, -0.35), C.Amber, Enum.Material.Neon, { Collide = false, Shadow = false })
			create("PointLight", { Brightness = 0.7, Range = 13, Color = C.Amber, Shadows = false }, glow)
		end
	end

	-- Колонны в углах
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(structure, "Pillar", Vector3.new(2.4, ROOM_HEIGHT, 2.4), CFrame.new(sx * (ROOM_HALF - 1.2), FLOOR_Y + ROOM_HEIGHT * 0.5, sz * (ROOM_HALF - 1.2)), C.Steel, Enum.Material.DiamondPlate)
			part(structure, "PillarStripe", Vector3.new(2.5, 1.2, 2.5), CFrame.new(sx * (ROOM_HALF - 1.2), FLOOR_Y + 2.2, sz * (ROOM_HALF - 1.2)), C.Hazard, Enum.Material.Metal, { Collide = false })
		end
	end

	-- Потолочные балки
	for _, x in { -18, -9, 9, 18 } do
		part(structure, "CeilingBeam", Vector3.new(1, 1.4, ROOM_HALF * 2), CFrame.new(x, FLOOR_Y + ROOM_HEIGHT - 0.7, 0), C.SteelDark, Enum.Material.Metal, { Collide = false })
	end

	-- Гермодверь на северной стене (декор)
	local doorBase = Vector3.new(0, FLOOR_Y, -ROOM_HALF + 0.3)
	part(structure, "BlastDoorFrame", Vector3.new(12, 11, 0.8), CFrame.new(doorBase + Vector3.new(0, 5.5, 0)), C.Hazard, Enum.Material.Metal, { Collide = false })
	part(structure, "BlastDoor", Vector3.new(10, 9.6, 1.0), CFrame.new(doorBase + Vector3.new(0, 4.8, 0.2)), C.Gunmetal, Enum.Material.DiamondPlate, { Collide = false })
	for i = -2, 2 do
		part(structure, "DoorStripe", Vector3.new(1.0, 8, 1.05), CFrame.new(doorBase + Vector3.new(i * 1.8, 4.8, 0.22)) * CFrame.Angles(0, 0, math.rad(25)), if i % 2 == 0 then C.HazardBlack else C.Hazard, Enum.Material.SmoothPlastic, { Collide = false, Shadow = false })
	end
	cylinderBetween(structure, "DoorWheel", doorBase + Vector3.new(0, 5, 0.6), doorBase + Vector3.new(0, 5, 1.1), 3, C.Rust, Enum.Material.CorrodedMetal, { Collide = false })
	local doorLamp = ball(structure, "DoorLamp", doorBase + Vector3.new(0, 10.3, 0.9), 0.9, C.Alarm, Enum.Material.Neon, { Collide = false, Shadow = false })
	create("PointLight", { Brightness = 1.2, Range = 8, Color = C.Alarm }, doorLamp)

	-- Трафаретная надпись на южной стене
	local signPart = part(structure, "WallSign", Vector3.new(16, 5, 0.2), CFrame.lookAt(Vector3.new(0, 13, ROOM_HALF - 0.1), Vector3.new(0, 13, 0)), C.Concrete, Enum.Material.Concrete, { Collide = false })
	local signGui = create("SurfaceGui", {
		Name = "Stencil",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 1,
	}, signPart) :: SurfaceGui
	create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "☢ CORE-7  //  SECTOR 04",
		TextColor3 = Color3.fromRGB(190, 160, 70),
		TextTransparency = 0.15,
		Font = Enum.Font.Michroma,
		TextScaled = true,
	}, signGui)
end

------------------------------------------------------------------------
-- СТОЛ И СТУЛЬЯ
------------------------------------------------------------------------

local function buildTable(root: Model)
	local tbl = model(root, "Table")
	local topThickness = 0.5
	local topCenter = Vector3.new(0, TABLE_TOP_Y - topThickness * 0.5, 0)

	-- Основание и тумба
	octagon(tbl, "Foot", Vector3.new(0, FLOOR_Y + 0.25, 0), 4, 0.5, C.SteelDark, Enum.Material.DiamondPlate)
	cylinderY(tbl, "Pedestal", Vector3.new(0, (FLOOR_Y + TABLE_TOP_Y - topThickness) * 0.5 + 0.25, 0), TABLE_TOP_Y - topThickness - FLOOR_Y - 0.4, 4.6, C.Gunmetal, Enum.Material.Metal)
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		local lower = polar(a, 3.6, FLOOR_Y + 0.5)
		local upper = polar(a, 2.2, TABLE_TOP_Y - 0.9)
		cylinderBetween(tbl, "Strut", lower, upper, 0.45, C.Steel, Enum.Material.Metal, { Collide = false })
	end

	-- Столешница
	octagon(tbl, "Top", topCenter, TABLE_INRADIUS, topThickness, C.Steel, Enum.Material.DiamondPlate)
	octagon(tbl, "Inlay", Vector3.new(0, TABLE_TOP_Y + 0.01, 0), TABLE_INRADIUS - 0.9, 0.04, C.SteelDark, Enum.Material.CorrodedMetal, { Collide = false })

	-- Обод, болты и неоновая подсветка снизу
	local side = 2 * (TABLE_INRADIUS + 0.3) * math.tan(math.rad(22.5))
	for i = 0, 7 do
		local a = math.rad(i * 45)
		local pos = polar(a, TABLE_INRADIUS + 0.3, TABLE_TOP_Y - 0.05)
		local rim = part(tbl, "Rim", Vector3.new(side + 0.25, 0.7, 0.6), CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)), C.Hazard, Enum.Material.Metal)
		rim.Color = if i % 2 == 0 then C.Hazard else C.Rust
		local under = polar(a, TABLE_INRADIUS - 0.1, TABLE_TOP_Y - 0.6)
		part(tbl, "UnderGlow", Vector3.new(side * 0.85, 0.12, 0.12), CFrame.lookAt(under, Vector3.new(0, under.Y, 0)), C.CoreGreen, Enum.Material.Neon, { Collide = false, Shadow = false })
		local corner = polar(a + math.rad(22.5), (TABLE_INRADIUS + 0.3) / math.cos(math.rad(22.5)), TABLE_TOP_Y + 0.35)
		cylinderY(tbl, "Bolt", corner, 0.25, 0.5, C.SteelDark, Enum.Material.Metal, { Collide = false })
	end

	-- Таблички с номерами мест
	for i, deg in SEAT_ANGLES_DEG do
		local a = math.rad(deg)
		local pos = polar(a, TABLE_INRADIUS - 0.45, TABLE_TOP_Y + 0.03)
		local plate = part(tbl, "SeatPlate" .. i, Vector3.new(1.6, 0.05, 0.8), CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)), C.Frame, Enum.Material.Metal, { Collide = false })
		local gui = create("SurfaceGui", {
			Face = Enum.NormalId.Top,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 60,
			LightInfluence = 0,
			Brightness = 1.5,
		}, plate) :: SurfaceGui
		create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Rotation = 180,
			Text = string.format("0%d", i),
			TextColor3 = C.Amber,
			Font = Enum.Font.Code,
			TextScaled = true,
		}, gui)
	end
end

local function buildChair(chairs: Folder, index: number, angleDeg: number): SeatInfo
	local a = math.rad(angleDeg)
	local pos = polar(a, SEAT_RADIUS, 0)
	local outward = Vector3.new(math.cos(a), 0, math.sin(a))
	local m = model(chairs, "Chair" .. index)

	local seatCenter = Vector3.new(pos.X, SEAT_TOP_Y - 0.2, pos.Z)
	local seatCF = CFrame.lookAt(seatCenter, Vector3.new(0, seatCenter.Y, 0))

	local seat: Seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Anchored = true
	seat.Size = Vector3.new(2.6, 0.4, 2.4)
	seat.CFrame = seatCF
	seat.Color = C.Gunmetal
	seat.Material = Enum.Material.DiamondPlate
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat:SetAttribute("SeatIndex", index)
	seat.Parent = m
	m.PrimaryPart = seat

	-- Ножки
	for _, lx in { -1.05, 1.05 } do
		for _, lz in { -0.95, 0.95 } do
			local top = (seatCF * CFrame.new(lx, -0.2, lz)).Position
			cylinderBetween(m, "Leg", top, Vector3.new(top.X, FLOOR_Y, top.Z), 0.3, C.SteelDark, Enum.Material.Metal)
		end
	end
	-- Спинка (сзади = +Z в локальных координатах сиденья)
	for _, lx in { -1.05, 1.05 } do
		local bottom = (seatCF * CFrame.new(lx, 0, 1.05)).Position
		cylinderBetween(m, "BackPost", bottom, bottom + Vector3.new(0, 2.9, 0) + outward * 0.35, 0.28, C.SteelDark, Enum.Material.Metal)
	end
	local backCF = seatCF * CFrame.new(0, 1.9, 1.2) * CFrame.Angles(math.rad(-8), 0, 0)
	local backrest = part(m, "Backrest", Vector3.new(2.4, 1.6, 0.25), backCF, C.Gunmetal, Enum.Material.DiamondPlate)
	part(m, "BackStripe", Vector3.new(2.42, 0.35, 0.27), backCF * CFrame.new(0, 0.55, 0), C.Hazard, Enum.Material.Metal, { Collide = false })
	-- Подлокотники
	for _, lx in { -1.35, 1.35 } do
		part(m, "Armrest", Vector3.new(0.25, 0.2, 2.0), seatCF * CFrame.new(lx, 1.0, 0.1), C.Rust, Enum.Material.CorrodedMetal)
		part(m, "ArmPost", Vector3.new(0.2, 1.0, 0.2), seatCF * CFrame.new(lx, 0.5, -0.6), C.SteelDark, Enum.Material.Metal, { Collide = false })
	end
	-- Номер места на спинке
	local gui = create("SurfaceGui", {
		Face = Enum.NormalId.Back,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 50,
		LightInfluence = 0.6,
	}, backrest) :: SurfaceGui
	create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = string.format("OPERATOR 0%d", index),
		TextColor3 = C.Amber,
		Font = Enum.Font.Code,
		TextScaled = true,
	}, gui)

	local prompt: ProximityPrompt = Instance.new("ProximityPrompt")
	prompt.Name = "SitPrompt"
	prompt.ActionText = "Sit at Table"
	prompt.ObjectText = string.format("Operator Chair 0%d", index)
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = seat

	return {
		Index = index,
		Seat = seat,
		Prompt = prompt,
		Model = m,
		Angle = a,
		Position = seatCenter,
		Outward = outward,
	}
end

------------------------------------------------------------------------
-- ЯДРО
------------------------------------------------------------------------

type CoreParts = {
	Model: Model,
	Neon: BasePart,
	Light: PointLight,
	RimSparks: ParticleEmitter,
	Steam: ParticleEmitter,
	Rods: { Model },
	Sounds: { [string]: Sound },
}

local function sparkEmitter(parent: Instance, name: string): ParticleEmitter
	return create("ParticleEmitter", {
		Name = name,
		Enabled = false,
		Rate = 0,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 230)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 190, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 20)),
		}),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(0.25, 0.6),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -45, 0),
		Drag = 3,
		EmissionDirection = Enum.NormalId.Bottom,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(1.8),
	}, parent) :: ParticleEmitter
end

local function buildRod(parent: Instance, index: number, angleDeg: number): Model
	local m = model(parent, "Rod" .. index)
	local a = math.rad(angleDeg)
	local base = polar(a, ROD_RADIUS_POS, CORE_BASE_TOP)
	local center = base + Vector3.new(0, ROD_LENGTH * 0.5, 0)

	local root = cylinderY(m, "RodRoot", center, ROD_LENGTH, 0.5, C.Steel, Enum.Material.Metal, { Collide = false })
	m.PrimaryPart = root
	root:SetAttribute("RestCFrame", root.CFrame)

	-- Приваренные детали двигаются вместе с корнем, когда клиент меняет его CFrame.
	local function attach(p: BasePart)
		p.Anchored = false
		p.Massless = true
		weld(root, p)
	end
	local glowBand = cylinderY(m, "GlowBand", center + Vector3.new(0, ROD_LENGTH * 0.28, 0), 0.6, 0.56, C.CoreGreen, Enum.Material.Neon, { Collide = false, Shadow = false })
	attach(glowBand)
	local cap = cylinderY(m, "Cap", center + Vector3.new(0, ROD_LENGTH * 0.5 + 0.15, 0), 0.3, 0.7, C.Hazard, Enum.Material.Metal, { Collide = false })
	attach(cap)
	local handle = cylinderY(m, "Handle", center + Vector3.new(0, ROD_LENGTH * 0.5 - 0.35, 0), 0.25, 0.75, C.SteelDark, Enum.Material.Metal, { Collide = false })
	attach(handle)
	for k = 1, 3 do
		local ring = cylinderY(m, "Ring", center + Vector3.new(0, -ROD_LENGTH * 0.5 + k * 0.9, 0), 0.12, 0.58, C.SteelDark, Enum.Material.Metal, { Collide = false })
		attach(ring)
	end
	return m
end

local function buildCore(root: Model): CoreParts
	local core = model(root, "Core")

	-- Основание
	cylinderY(core, "Base", Vector3.new(0, TABLE_TOP_Y + 0.25, 0), 0.5, 6.2, C.SteelDark, Enum.Material.DiamondPlate)
	cylinderY(core, "BaseRing", Vector3.new(0, TABLE_TOP_Y + 0.42, 0), 0.18, 6.5, C.Hazard, Enum.Material.Metal, { Collide = false })

	-- Стеклянный контейнмент
	local glass = cylinderY(core, "Containment", CORE_CENTER, GLASS_HEIGHT, 4.6, C.Glass, Enum.Material.Glass, { Transparency = 0.62, Shadow = false, Reflectance = 0.1 })
	glass.CanCollide = true
	-- Решётка-клетка
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		local bottom = polar(a, 2.45, CORE_BASE_TOP)
		cylinderBetween(core, "CageBar", bottom, bottom + Vector3.new(0, GLASS_HEIGHT, 0), 0.22, C.SteelDark, Enum.Material.Metal, { Collide = false })
	end
	for _, h in { 0.25, GLASS_HEIGHT * 0.5, GLASS_HEIGHT - 0.25 } do
		cylinderY(core, "CageHoop", Vector3.new(0, CORE_BASE_TOP + h, 0), 0.18, 5.1, C.Rust, Enum.Material.CorrodedMetal, { Collide = false, Transparency = 0 })
	end
	-- Крышка (обруч, чтобы стержни торчали наружу)
	local cap = cylinderY(core, "Cap", Vector3.new(0, CAP_TOP - 0.2, 0), 0.4, 5.3, C.Gunmetal, Enum.Material.DiamondPlate)
	cylinderY(core, "CapHub", Vector3.new(0, CAP_TOP + 0.1, 0), 0.3, 1.4, C.Hazard, Enum.Material.Metal, { Collide = false })

	-- Светящееся ядро: неоновый шар + базальтовые "осколки" с щелями-разломами
	local neon = ball(core, "CoreNeon", CORE_CENTER, 2.0, C.CoreGreen, Enum.Material.Neon, { Collide = false, Shadow = false })
	local dirs: { Vector3 } = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 1, 0),
		Vector3.new(0, -1, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
	}
	for i, d in dirs do
		local shard = ball(core, "Shard" .. i, CORE_CENTER + d * 0.55, 1.35, Color3.fromRGB(22, 24, 22), Enum.Material.Basalt, { Collide = false })
		shard.CFrame = shard.CFrame * CFrame.Angles(math.rad(i * 37), math.rad(i * 61), 0)
	end
	-- Тонкие неоновые трещины поверх осколков (fissures)
	for i = 1, 6 do
		local a = math.rad(i * 60 + 15)
		local p = CORE_CENTER + Vector3.new(math.cos(a) * 1.02, (i % 3 - 1) * 0.35, math.sin(a) * 1.02)
		local fissure = part(core, "Fissure" .. i, Vector3.new(0.08, 1.1, 0.3), CFrame.lookAt(p, CORE_CENTER) * CFrame.Angles(0, 0, math.rad(i * 29)), C.CoreGreen, Enum.Material.Neon, { Collide = false, Shadow = false })
		fissure:SetAttribute("Fissure", true)
	end

	local light = create("PointLight", {
		Name = "CoreLight",
		Brightness = 3,
		Range = 20,
		Color = C.CoreGreen,
		Shadows = true,
	}, neon) :: PointLight

	-- Искры на ободе крышки
	local rimAttachment = create("Attachment", { Name = "RimAttachment", Position = Vector3.new(0.3, 0, 0) }, cap) :: Attachment
	local rimSparks = sparkEmitter(rimAttachment, "RimSparks")
	rimSparks.EmissionDirection = Enum.NormalId.Right -- ось X крышки смотрит вверх

	-- Пар из вентиляции крышки
	local steamAttachment = create("Attachment", { Name = "SteamAttachment", Position = Vector3.new(0.4, 0, 0) }, cap) :: Attachment
	local steam = create("ParticleEmitter", {
		Name = "Steam",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 4,
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(1, 2.2),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, 0.6, 0),
		Drag = 0.6,
		LightEmission = 0.15,
		LightInfluence = 0.8,
		Color = ColorSequence.new(Color3.fromRGB(150, 170, 160)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 3.4),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
		RotSpeed = NumberRange.new(-20, 20),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Right, -- ось цилиндра крышки = X = вверх
	}, steamAttachment) :: ParticleEmitter

	-- Топливные стержни
	local rodsFolder = folder(core, "FuelRods")
	local rods: { Model } = {}
	for i, deg in ROD_ANGLES_DEG do
		table.insert(rods, buildRod(rodsFolder, i, deg))
	end

	-- Звуки (пространственные, из центра ядра)
	local sounds: { [string]: Sound } = {}
	for name, spec in SOUND_SPECS do
		local s: Sound = Instance.new("Sound")
		s.Name = name
		s.SoundId = spec.Id
		s.Volume = spec.Volume
		s.PlaybackSpeed = spec.Speed
		s.Looped = spec.Looped
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = spec.MinDist
		s.RollOffMaxDistance = spec.MaxDist
		s.Parent = neon
		sounds[name] = s
	end

	return {
		Model = core,
		Neon = neon,
		Light = light,
		RimSparks = rimSparks,
		Steam = steam,
		Rods = rods,
		Sounds = sounds,
	}
end

------------------------------------------------------------------------
-- ЭЛТ-МОНИТОРЫ
------------------------------------------------------------------------

local function crtRow(parent: Instance, name: string, order: number, label: string, textColor: Color3): TextLabel
	local row = create("Frame", {
		Name = name .. "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = order,
	}, parent) :: Frame
	create("TextLabel", {
		Name = "Key",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.5, 1),
		Text = label,
		TextColor3 = Color3.fromRGB(90, 150, 100),
		Font = Enum.Font.Code,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	return create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.45, 0),
		Size = UDim2.fromScale(0.55, 1),
		Text = "--",
		TextColor3 = textColor,
		Font = Enum.Font.Code,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row) :: TextLabel
end

local function buildCRTScreen(screenPart: BasePart): CRTLabelSet
	local gui = create("SurfaceGui", {
		Name = "CRTScreen",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 170,
		LightInfluence = 0,
		Brightness = 2.2,
		ClipsDescendants = true,
		AlwaysOnTop = false,
	}, screenPart) :: SurfaceGui

	local bg = create("Frame", {
		Name = "Phosphor",
		BackgroundColor3 = Color3.fromRGB(6, 14, 8),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, gui) :: Frame
	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 34, 18)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 20, 11)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 6, 3)),
		}),
		Rotation = 90,
	}, bg)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
	}, bg)

	local list = create("Frame", { Name = "Rows", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, bg) :: Frame
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}, list)

	local header = create("TextLabel", {
		Name = "Header",
		BackgroundColor3 = C.Phosphor,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 32),
		Text = " CORE-7 // TELEMETRY",
		TextColor3 = Color3.fromRGB(4, 14, 6),
		Font = Enum.Font.Code,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	}, list) :: TextLabel

	local operator = crtRow(list, "Operator", 1, "OPERATOR", C.Phosphor)
	local pot = crtRow(list, "Pot", 2, "POT ($)", C.Amber)
	local instability = crtRow(list, "Instability", 3, "CORE INSTAB.", C.Phosphor)

	local barBack = create("Frame", {
		Name = "InstabilityBar",
		BackgroundColor3 = Color3.fromRGB(10, 26, 14),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 4,
	}, list) :: Frame
	create("UIStroke", { Color = Color3.fromRGB(60, 140, 70), Thickness = 2 }, barBack)
	local fill = create("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.Phosphor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}, barBack) :: Frame
	-- Деления шкалы
	for i = 1, 9 do
		create("Frame", {
			Name = "Tick",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Position = UDim2.new(i / 10, -1, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			ZIndex = 2,
		}, barBack)
	end

	local overclock = crtRow(list, "Overclock", 5, "OVERCLOCK", C.Amber)
	local cycle = crtRow(list, "Cycle", 6, "CYCLE", C.Phosphor)
	local timer = crtRow(list, "Timer", 7, "T-MINUS", C.Phosphor)

	local status = create("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Text = "> AWAITING OPERATORS_",
		TextColor3 = C.Phosphor,
		Font = Enum.Font.Code,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = 8,
	}, list) :: TextLabel

	addScanlines(bg, 90, 0.72, 5)
	-- Виньетка ЭЛТ
	local vignette = create("Frame", {
		Name = "Vignette",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 36, 1, 24),
		Position = UDim2.fromOffset(-18, -12),
		ZIndex = 6,
	}, bg) :: Frame
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.12, 1),
			NumberSequenceKeypoint.new(0.88, 1),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
	}, vignette)

	return {
		Screen = gui,
		Header = header,
		Operator = operator,
		Pot = pot,
		Instability = instability,
		InstabilityFill = fill,
		Overclock = overclock,
		Cycle = cycle,
		Status = status,
		Timer = timer,
	}
end

local function buildMonitor(parent: Instance, index: number, angleDeg: number): CRTLabelSet
	local m = model(parent, "Monitor" .. index)
	local a = math.rad(angleDeg)
	local outward = Vector3.new(math.cos(a), 0, math.sin(a))
	local base = polar(a, TABLE_INRADIUS - 1.9, TABLE_TOP_Y)

	-- Кронштейн, прикрученный к столу
	part(m, "Bracket", Vector3.new(2.2, 0.25, 1.6), CFrame.lookAt(base + Vector3.new(0, 0.12, 0), base + Vector3.new(0, 0.12, 0) + outward), C.SteelDark, Enum.Material.DiamondPlate)
	for _, side in { -0.85, 0.85 } do
		local boltPos = (CFrame.lookAt(base, base + outward) * CFrame.new(side, 0.3, 0)).Position
		cylinderY(m, "Bolt", boltPos, 0.2, 0.3, C.Hazard, Enum.Material.Metal, { Collide = false })
	end
	local neckTop = base + Vector3.new(0, 0.9, 0)
	cylinderBetween(m, "Neck", base + Vector3.new(0, 0.2, 0), neckTop, 0.5, C.Gunmetal, Enum.Material.Metal)

	local casingCenter = base + Vector3.new(0, 2.25, 0)
	local casingCF = CFrame.lookAt(casingCenter, casingCenter + outward) * CFrame.Angles(math.rad(12), 0, 0)
	part(m, "Casing", Vector3.new(3.4, 2.7, 2.0), casingCF, C.Frame, Enum.Material.Metal)
	part(m, "Tube", Vector3.new(2.4, 1.9, 1.4), casingCF * CFrame.new(0, 0, 1.4), C.Frame, Enum.Material.Metal)
	part(m, "Bezel", Vector3.new(3.5, 2.8, 0.2), casingCF * CFrame.new(0, 0, -1.0), C.SteelDark, Enum.Material.DiamondPlate)
	part(m, "BezelStripe", Vector3.new(3.52, 0.2, 0.22), casingCF * CFrame.new(0, -1.25, -1.01), C.Hazard, Enum.Material.Metal, { Collide = false })
	local screen = part(m, "Screen", Vector3.new(2.9, 2.1, 0.06), casingCF * CFrame.new(0, 0.1, -1.12), Color3.fromRGB(10, 20, 12), Enum.Material.Glass, { Collide = false, Shadow = false })
	-- Индикаторы на корпусе
	for k = 0, 2 do
		local led = ball(m, "Led", (casingCF * CFrame.new(-1.3 + k * 0.3, -1.25, -1.12)).Position, 0.14, if k == 0 then C.CoreGreen else C.Amber, Enum.Material.Neon, { Collide = false, Shadow = false })
		led.Name = "Led" .. k
	end
	-- Свечение экрана на стол
	create("SurfaceLight", {
		Face = Enum.NormalId.Front,
		Brightness = 0.6,
		Range = 6,
		Angle = 70,
		Color = C.Phosphor,
	}, screen)

	return buildCRTScreen(screen)
end

------------------------------------------------------------------------
-- МАНИПУЛЯТОР
------------------------------------------------------------------------

local function buildManipulator(root: Model): ManipulatorRig
	local m = model(root, "Manipulator")

	-- Портальная балка через всю комнату
	part(m, "GantryWeb", Vector3.new(ROOM_HALF * 2, 1.4, 0.3), CFrame.new(0, GANTRY_Y, GANTRY_Z), C.SteelDark, Enum.Material.Metal, { Collide = false })
	for _, dy in { -0.75, 0.75 } do
		part(m, "GantryFlange", Vector3.new(ROOM_HALF * 2, 0.2, 1.1), CFrame.new(0, GANTRY_Y + dy, GANTRY_Z), C.Steel, Enum.Material.Metal, { Collide = false })
	end
	for _, x in { -ROOM_HALF + 2, ROOM_HALF - 2 } do
		part(m, "GantryHanger", Vector3.new(0.6, ROOM_HEIGHT - GANTRY_Y + FLOOR_Y, 0.6), CFrame.new(x, (GANTRY_Y + FLOOR_Y + ROOM_HEIGHT) * 0.5, GANTRY_Z), C.SteelDark, Enum.Material.Metal, { Collide = false })
	end
	-- Тележка
	part(m, "Trolley", Vector3.new(2.6, 1.6, 2.0), CFrame.new(0, GANTRY_Y - 1.4, GANTRY_Z), C.Hazard, Enum.Material.Metal, { Collide = false })
	part(m, "TrolleyStripe", Vector3.new(2.62, 0.3, 2.02), CFrame.new(0, GANTRY_Y - 1.4, GANTRY_Z), C.HazardBlack, Enum.Material.SmoothPlastic, { Collide = false })
	part(m, "Column", Vector3.new(0.9, GANTRY_Y - 2.2 - PIVOT_POS.Y, 0.9), CFrame.new(0, (GANTRY_Y - 2.2 + PIVOT_POS.Y) * 0.5, GANTRY_Z), C.Gunmetal, Enum.Material.DiamondPlate, { Collide = false })
	local pivot = ball(m, "ShoulderPivot", PIVOT_POS, 1.5, C.SteelDark, Enum.Material.Metal, { Collide = false })
	local cableTop = create("Attachment", { Name = "CableTop", Position = Vector3.new(0.5, 0.4, 0) }, pivot) :: Attachment

	-- Рука (клиент ставит CFrame каждый кадр)
	local dir = (HEAD_REST - PIVOT_POS).Unit
	local sleeve = part(m, "Sleeve", Vector3.new(1.0, 1.0, 3.2), CFrame.lookAt(PIVOT_POS + dir * 1.6, HEAD_REST), C.Gunmetal, Enum.Material.DiamondPlate, { Collide = false })
	local piston = cylinderBetween(m, "Piston", PIVOT_POS, HEAD_REST, 0.45, Color3.fromRGB(170, 175, 170), Enum.Material.Metal, { Collide = false, Reflectance = 0.15 })

	-- Запястье
	local head = part(m, "ManipulatorHead", Vector3.new(1.2, 0.9, 1.2), CFrame.new(HEAD_REST), C.Hazard, Enum.Material.Metal, { Collide = false })
	local headStripe = part(m, "HeadStripe", Vector3.new(1.22, 0.25, 1.22), CFrame.new(HEAD_REST), C.HazardBlack, Enum.Material.SmoothPlastic, { Collide = false })
	headStripe.Anchored = false
	headStripe.Massless = true
	weld(head, headStripe)
	local hub = cylinderY(m, "Hub", HEAD_REST - Vector3.new(0, 0.6, 0), 0.35, 0.9, C.SteelDark, Enum.Material.Metal, { Collide = false })
	hub.Anchored = false
	hub.Massless = true
	weld(head, hub)
	local eye = ball(m, "SensorEye", HEAD_REST + Vector3.new(0, 0, -0.62), 0.28, C.Alarm, Enum.Material.Neon, { Collide = false, Shadow = false })
	eye.Anchored = false
	eye.Massless = true
	weld(head, eye)

	local tip = create("Attachment", { Name = "TipAttachment", Position = Vector3.new(0, -1.6, 0) }, head) :: Attachment
	local cableBottom = create("Attachment", { Name = "CableBottom", Position = Vector3.new(0.5, 0.3, 0) }, head) :: Attachment
	local arcLight = create("PointLight", {
		Name = "ArcLight",
		Brightness = 0,
		Range = 10,
		Color = Color3.fromRGB(170, 210, 255),
		Shadows = false,
		Enabled = true,
	}, tip) :: PointLight

	-- Гидравлический шланг (Beam без текстуры = сплошной цвет)
	create("Beam", {
		Name = "Hose",
		Attachment0 = cableTop,
		Attachment1 = cableBottom,
		Color = ColorSequence.new(Color3.fromRGB(25, 25, 25)),
		Width0 = 0.18,
		Width1 = 0.18,
		CurveSize0 = -2,
		CurveSize1 = 2,
		Segments = 16,
		FaceCamera = true,
		LightInfluence = 1,
		Transparency = NumberSequence.new(0),
	}, pivot)

	-- Пальцы клешни (клиент двигает каждый палец отдельно)
	local fingers: { BasePart } = {}
	for i = 1, 3 do
		local a = math.rad(i * 120)
		local fpos = HEAD_REST + Vector3.new(math.cos(a) * 0.45, -1.2, math.sin(a) * 0.45)
		local finger = part(m, "Finger" .. i, Vector3.new(0.22, 1.3, 0.34), CFrame.new(fpos), C.SteelDark, Enum.Material.Metal, { Collide = false })
		local fingerTip = part(m, "FingerTip" .. i, Vector3.new(0.24, 0.3, 0.36), CFrame.new(fpos - Vector3.new(0, 0.65, 0)), C.Rust, Enum.Material.CorrodedMetal, { Collide = false })
		fingerTip.Anchored = false
		fingerTip.Massless = true
		weld(finger, fingerTip)
		table.insert(fingers, finger)
	end

	sparkEmitter(tip, "ClawSparks")

	return {
		Model = m,
		Pivot = pivot,
		Sleeve = sleeve,
		Piston = piston,
		Head = head,
		Fingers = fingers,
		TipAttachment = tip,
		ArcLight = arcLight,
	}
end

------------------------------------------------------------------------
-- КАЧАЮЩАЯСЯ ЛАМПА
------------------------------------------------------------------------

local function buildLamp(root: Model): LampRig
	local m = model(root, "Lamp")
	part(m, "CeilingMount", Vector3.new(1.4, 0.4, 1.4), CFrame.new(LAMP_HINGE + Vector3.new(0, 0.2, 0)), C.SteelDark, Enum.Material.Metal, { Collide = false })
	local hinge = ball(m, "Hinge", LAMP_HINGE, 0.5, C.SteelDark, Enum.Material.Metal, { Collide = false })
	m.PrimaryPart = hinge

	local function hang(p: BasePart)
		p.Anchored = false
		p.Massless = true
		weld(hinge, p)
	end

	-- Цепь из звеньев
	local links = 9
	for i = 1, links do
		local y = LAMP_HINGE.Y - (i - 0.5) * (LAMP_DROP - 0.8) / links
		local link = part(m, "Link", Vector3.new(0.12, 0.42, 0.26), CFrame.new(0, y, 0) * CFrame.Angles(0, if i % 2 == 0 then math.rad(90) else 0, 0), C.SteelDark, Enum.Material.Metal, { Collide = false })
		hang(link)
	end
	local shadeY = LAMP_HINGE.Y - LAMP_DROP
	local shadeTop = cylinderY(m, "ShadeTop", Vector3.new(0, shadeY + 0.65, 0), 0.5, 0.9, C.Gunmetal, Enum.Material.Metal, { Collide = false })
	hang(shadeTop)
	local shade = cylinderY(m, "Shade", Vector3.new(0, shadeY + 0.2, 0), 0.5, 2.0, Color3.fromRGB(40, 60, 46), Enum.Material.Metal, { Collide = false })
	hang(shade)
	local shadeLip = cylinderY(m, "ShadeLip", Vector3.new(0, shadeY - 0.15, 0), 0.25, 3.2, Color3.fromRGB(40, 60, 46), Enum.Material.Metal, { Collide = false })
	hang(shadeLip)
	-- Защитная решётка
	for i = 0, 3 do
		local cage = part(m, "Cage", Vector3.new(0.06, 0.06, 2.4), CFrame.new(0, shadeY - 0.45, 0) * CFrame.Angles(0, math.rad(i * 45), 0), C.SteelDark, Enum.Material.Metal, { Collide = false, Shadow = false })
		hang(cage)
	end
	local bulb = ball(m, "Bulb", Vector3.new(0, shadeY - 0.15, 0), 0.75, C.Warm, Enum.Material.Neon, { Collide = false, Shadow = false })
	hang(bulb)

	local spotlight = create("SpotLight", {
		Name = "Spotlight",
		Face = Enum.NormalId.Bottom,
		Angle = 62,
		Range = 32,
		Brightness = 5,
		Color = C.Warm,
		Shadows = true,
	}, bulb) :: SpotLight
	create("PointLight", {
		Name = "Fill",
		Brightness = 0.4,
		Range = 9,
		Color = C.Warm,
		Shadows = false,
	}, bulb)

	return { Model = m, Root = hinge, Bulb = bulb, Spotlight = spotlight }
end

------------------------------------------------------------------------
-- АВАРИЙНЫЕ МАЯКИ
------------------------------------------------------------------------

local function buildBeacons(root: Model): { SpotLight }
	local f = folder(root, "Beacons")
	local beacons: { SpotLight } = {}
	local spots = {
		Vector3.new(-ROOM_HALF + 0.6, 20, 0),
		Vector3.new(ROOM_HALF - 0.6, 20, 0),
		Vector3.new(0, 20, ROOM_HALF - 0.6),
	}
	for i, pos in spots do
		local inward = Vector3.new(-pos.X, 0, -pos.Z).Unit
		part(f, "BeaconBase" .. i, Vector3.new(1.2, 0.6, 1.2), CFrame.lookAt(pos - Vector3.new(0, 0.6, 0), pos - Vector3.new(0, 0.6, 0) + inward), C.SteelDark, Enum.Material.Metal, { Collide = false })
		local dome = ball(f, "BeaconDome" .. i, pos, 1.0, Color3.fromRGB(90, 20, 18), Enum.Material.Glass, { Collide = false, Shadow = false, Transparency = 0.2 })
		dome:SetAttribute("BeaconIndex", i)
		local light = create("SpotLight", {
			Name = "BeaconLight",
			Face = Enum.NormalId.Front,
			Angle = 40,
			Range = 45,
			Brightness = 0,
			Color = C.Alarm,
			Shadows = false,
			Enabled = true,
		}, dome) :: SpotLight
		table.insert(beacons, light)
	end
	return beacons
end

------------------------------------------------------------------------
-- ТОЧКА ПОЯВЛЕНИЯ
------------------------------------------------------------------------

local function buildSpawn(root: Model): SpawnLocation
	-- Отключаем стандартные спавны шаблона Baseplate (тот, что в центре, удаляем — там стол).
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") and not inst:IsDescendantOf(root) then
			local p = inst.Position
			if math.abs(p.X) < ROOM_HALF + 4 and math.abs(p.Z) < ROOM_HALF + 4 then
				inst:Destroy()
			else
				inst.Enabled = false
			end
		end
	end

	local spawn: SpawnLocation = Instance.new("SpawnLocation")
	spawn.Name = "BunkerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.2, 6)
	spawn.CFrame = CFrame.new(0, FLOOR_Y + 0.1, 22) * CFrame.Angles(0, math.rad(0), 0)
	spawn.Color = C.SteelDark
	spawn.Material = Enum.Material.DiamondPlate
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
	local decal = create("SurfaceGui", {
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0.5,
	}, spawn) :: SurfaceGui
	create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "ENTRY",
		TextColor3 = C.Hazard,
		Font = Enum.Font.Michroma,
		TextScaled = true,
	}, decal)
	return spawn
end

------------------------------------------------------------------------
-- СБОРКА
------------------------------------------------------------------------

function BunkerBuilder.Build(): BuildResult
	local existing = Workspace:FindFirstChild("CoreRouletteBunker")
	if existing then
		existing:Destroy()
	end

	setupLighting()

	local root = Instance.new("Model")
	root.Name = "CoreRouletteBunker"
	root.WorldPivot = CFrame.new(ROOM_CENTER)
	root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- клиент всегда видит весь бункер

	buildRoom(root)
	buildTable(root)

	local chairs = folder(root, "Chairs")
	local seatInfos: { SeatInfo } = {}
	local seats: { Seat } = {}
	local prompts: { ProximityPrompt } = {}
	for i, deg in SEAT_ANGLES_DEG do
		local info = buildChair(chairs, i, deg)
		table.insert(seatInfos, info)
		table.insert(seats, info.Seat)
		table.insert(prompts, info.Prompt)
	end

	local core = buildCore(root)

	local crtFolder = folder(root, "CRT")
	local crtLabels: { CRTLabelSet } = {
		buildMonitor(crtFolder, 1, 90),
		buildMonitor(crtFolder, 2, 270),
	}

	local manipulator = buildManipulator(root)
	local lamp = buildLamp(root)
	local beacons = buildBeacons(root)
	local spawn = buildSpawn(root)

	local clawSparks = manipulator.TipAttachment:FindFirstChild("ClawSparks") :: ParticleEmitter

	-- Метаданные для клиента (он находит всё по именам и атрибутам)
	root:SetAttribute("FloorY", FLOOR_Y)
	root:SetAttribute("TableTopY", TABLE_TOP_Y)
	root:SetAttribute("CoreCenter", CORE_CENTER)
	root:SetAttribute("CapTop", CAP_TOP)
	root:SetAttribute("PivotPos", PIVOT_POS)
	root:SetAttribute("HeadRest", HEAD_REST)
	root:SetAttribute("LampHinge", LAMP_HINGE)
	root:SetAttribute("RodLength", ROD_LENGTH)

	root.Parent = Workspace

	return {
		Root = root,
		Center = Vector3.new(0, TABLE_TOP_Y, 0),
		CoreCenter = CORE_CENTER,
		FloorY = FLOOR_Y,
		TableTopY = TABLE_TOP_Y,
		Seats = seats,
		SeatInfos = seatInfos,
		Prompts = prompts,
		CoreModel = core.Model,
		CoreNeon = core.Neon,
		CoreLight = core.Light,
		SparksEmitter = clawSparks,
		RimSparks = core.RimSparks,
		SteamEmitter = core.Steam,
		FuelRods = core.Rods,
		CRTLabels = crtLabels,
		ManipulatorPart = manipulator.Head,
		Manipulator = manipulator,
		Lamp = lamp,
		Spotlight = lamp.Spotlight,
		Beacons = beacons,
		Sounds = core.Sounds,
		SpawnLocation = spawn,
	}
end

return BunkerBuilder
