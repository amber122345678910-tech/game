--!strict
-- Главная картинка игры: кольца ударов, молнии, вспышки, осколки на земле и стрелки к кольцам за краем экрана.
-- Всё строится из деталей и встроенных текстур; детали берутся из пулов и двигаются одним BulkMoveTo за кадр.
-- Время колец — серверное (ClientState.now()), анимации эффектов — os.clock().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strikes = require(Shared:WaitForChild("Strikes"))
local BoltGeometry = require(Shared:WaitForChild("BoltGeometry"))
local Geom = require(Shared:WaitForChild("Geom"))
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Format"))
local Zones = require(Shared:WaitForChild("Zones"))
local Signal = require(Shared:WaitForChild("Signal"))
local Models = require(Shared:WaitForChild("Models"))
local Loc = require(Shared:WaitForChild("Loc"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)
local Juice = require(script.Parent.Juice)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = require(script.Parent.Parent.UI.Theme)

local StrikeController = {}

-- (id, hit, colorId, zone) — удар пришёл, а свой игрок стоял в кольце и ещё не нажимал
-- (CatchController решает, «Шарахнуло» это или подсказка, когда закроется окно нажатия)
StrikeController.UntappedHit = Signal.new() :: Signal.Signal<number, number, string, number>

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Визуальные константы (игровые числа — в Config)
----------------------------------------------------------------------
local SEGMENTS = 24 -- деталей во внешнем кольце
local OUTER_START = 2.4 -- внешнее кольцо стартует с такого радиуса (× радиус кольца)
local SEG_HEIGHT = 0.16
local SEG_RESIZE = 0.05 -- размер деталей внешнего кольца меняем, только когда он изменился больше чем на 5%
local SEG_WIDTH_STEP = 0.03
local EDGE_CANVAS = 512 -- предел размера холста края кольца (точек)
local EDGE_STROKE = 0.36 -- толщина края кольца (стадов)
local CLOUD_GLOW_TIME = 0.6 -- туча разгорается за столько секунд до удара
local LEADER_TIME = 0.3 -- «ниточка» молнии в последние столько секунд
local LEADER_JITTER = 0.05 -- «ниточка» меняет форму не чаще (с)
local LEADER_LEN_STEP = 0.5 -- длина её деталей — с таким шагом (размер меняется реже)
local WARN_LEAD = 0.7 -- звук-предупреждение для редких цветов
local WARN_MIN_ORDER = 3 -- редкие цвета: изумрудная и реже
local CLOUD_SHARE = 0.6 -- туча над кольцом: GroundY + CloudHeight × столько
local FADE_IN = 0.25
local BOLT_HOLD = 0.12 -- молния горит в полную силу
local BOLT_FADE = 0.3 -- и гаснет
local FLASH_TIME = 0.25
local FLASH_RANGE = 50
local FLASH_BRIGHTNESS = 6
local MAX_LIGHTS = 3 -- динамических источников света на всё сразу
-- светочувствительность: полных вспышек (яркая молния со светом) не больше стольких в секунду на всё сразу;
-- своя молния сверх лимита рисуется приглушённой, чужие — только пока молний в секунду меньше MAX_BOLTS
local MAX_FULL_FLASHES = 3
local MAX_BOLTS = 3
local MAX_BOLT_PARTS = 480
local MAX_SPARK_BURSTS = 10 -- выбросов искр в секунду
local SPARK_EMITTERS = 4
local SHOCKWAVE_POOL = 8
local SHOCKWAVE_TIME = 0.42
local TARGET_SLACK = 1.5 -- допуск к радиусу при выборе кольца для нажатия
local ZAP_PREDICT_SLACK = -0.5 -- «стоял в кольце» для прогноза «Шарахнуло»: чуть строже сервера (позиция у него старее)
-- сервер видит игрока там, где он был половину пинга + шаг репликации назад: вбежавшего в кольцо
-- перед самым ударом он ещё считает снаружи (молния в землю, осколок) — такой удар не прогнозируем
local ZAP_PREDICT_LAG = 0.06 -- шаг репликации позиции (с), сверх половины пинга
local ZAP_PREDICT_MAX_LAG = 0.4
local LATE_SLACK = 0.1 -- после окна ХОРОШО удар ещё можно выбрать (сервер всё равно оценит)
-- кольцо живёт после последнего удара (чтобы успело погаснуть и можно было нажать чуть позже)
local RING_TAIL = math.max(0.45, Config.Catch.MaxGoodWindow + LATE_SLACK + 0.05)
local OTHERS_BOLT_DISTANCE = 260 -- чужие молнии дальше не рисуем
local SHARD_POP = 0.25
local SHARD_GROW = 0.3
local SHARD_FADE = 0.4
local SHARD_LADDER_GAP = 1.1 -- осколки, собранные чаще, звенят всё выше
local LADDER = { 0, 2, 4, 7, 9, 12 } -- пентатоника на одну октаву (выше звук становится визгливым)
-- подбор осколка: сервер видит игрока с задержкой, поэтому ShardCollect повторяем, пока не придёт подтверждение
-- (Effect "shard" с Id осколка); «+N 💎» — только после него. Не подтвердили — осколок возвращается на землю (один раз).
local SHARD_RESEND = 0.15
local SHARD_CONFIRM_TIME = 2
local SHARD_RESEND_REACH = 8 -- повторяем, только пока игрок не дальше радиуса сбора + допуска сервера + столько
-- новый тип удара (двойной, вилка, обманка, бегущий): над первыми кольцами — подсказка, что делать
-- (пока это самый дальний открытый остров игрока, столько колец каждого типа за сессию)
local KIND_HINT_RINGS = 3
local KIND_HINT_TEXT = {
	fake = Loc.t("Обманка! Кольцо замрёт — жди"),
	runner = Loc.t("Бегущее! Беги за ним"),
} :: { [string]: string }
local ARROW_MARGIN = 54 -- отступ стрелок от края экрана (точки)
local ARROW_TOUCH_BOTTOM = 0.3 -- на телефоне нижние 30% экрана — джойстик и кнопки
local HIDDEN = CFrame.new(0, 1e4, 0)

local WHITE = Color3.new(1, 1, 1)
local CLOUD_DARK = Color3.fromRGB(52, 53, 78) -- ядро тучи, если у острова нет своего цвета
local CLOUD_DEEP = Color3.fromRGB(30, 26, 52) -- к нему тянем «брюхо» острова, получая ядро (STYLE §3.2)
local CLOUD_LIGHT = Color3.fromRGB(170, 176, 230) -- а к нему — кромку
local CLOUD_DROP = 2.6 -- низ тучи ниже cloudY: молния и «ниточка» выходят из кристалла под брюхом
local CLOUD_CORE_STEP = 0.2 -- размер кристалла-ядра меняем ступенями (реже меняется Size)
local ICON_ALPHA_STEP = 0.04 -- прозрачность значка цвета обновляем, только когда она заметно изменилась
local BLACK_FILL = Color3.fromRGB(70, 30, 110)
local BLACK_LINE = Color3.fromRGB(255, 200, 70)
local BLACK_CORE = Color3.fromRGB(24, 10, 34)
local BLACK_BRANCH = Color3.fromRGB(150, 80, 255)
local SHARD_COLOR = Color3.fromRGB(150, 235, 255)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local CATCH_HEIGHT = Config.Server.CatchHeight

----------------------------------------------------------------------
-- Типы
----------------------------------------------------------------------
export type StrikeInfo = {
	Id: number,
	Center: Vector3, -- текущий центр (бегущее кольцо — где оно сейчас)
	Radius: number,
	Color: Config.ColorId,
	Kind: Config.KindId,
	NextHit: number?, -- серверное время ближайшего ещё не прошедшего удара
	NextIndex: number?,
	HitsLeft: number,
	Shared: boolean,
	Tag: string?,
}

type LightSlot = {
	part: Part,
	light: PointLight,
	owner: any, -- кольцо, которому сейчас светит (nil — свободен)
	flashing: boolean,
	t0: number,
	peak: number,
}

-- Значок цвета молнии, нарисованный примитивами UI (● ★ ✦ ✺ ☯ нет в шрифтах игры, STYLE §8.5)
type IconGlyph = {
	holder: Frame,
	items: { GuiObject }, -- всё, что гасим при появлении/исчезновении кольца
	base: { number }, -- их исходная прозрачность
	strokes: { UIStroke },
	labels: { TextLabel },
	fills: { GuiObject }, -- слой заливки (перекраска радужной)
}

type RingVisual = {
	disk: Part,
	carrier: Part,
	edgeGui: SurfaceGui,
	edgeStroke: UIStroke,
	edgeFill: Frame,
	iconGui: BillboardGui,
	glyphs: { [string]: IconGlyph }, -- по виду значка, строятся по требованию и остаются в пуле
	glyph: IconGlyph?,
	glyphAlpha: number,
	count: TextLabel,
	hintGui: BillboardGui,
	hint: TextLabel,
	segs: { Part },
	cloud: { Part }, -- тучка удара (Models.strikeCloudRecipe), без кристалла-ядра
	cloudOffsets: { CFrame },
	cloudTones: { string },
	cloudColor: Color3,
	cloudT: number,
	core: Part,
	coreOffset: CFrame,
	coreSize: number,
	leader: { Part },
	leaderJit: { Vector3 },
	leaderLen: { number },
	leaderNext: number,
	segLen: number,
	segWidth: number,
	segTransp: number,
	segColor: Color3,
	segsShown: boolean,
	leaderShown: boolean,
}

type Ring = {
	id: number,
	kind: Config.KindId,
	radius: number,
	base: Vector3, -- центр на земле (для бегущего — начало пути)
	runTo: Vector3?,
	groundY: number,
	normal: Vector3,
	cloudY: number,
	cloudYaw: number,
	cloudCore: Color3, -- цвета тучи острова: ядро (низ), брюхо, кромка
	cloudBelly: Color3,
	cloudEdge: Color3,
	spawn: number,
	hits: { number },
	finalColor: Config.ColorId,
	shown: Config.ColorId?,
	upgradeTime: number,
	colorId: Config.ColorId, -- цвет, который сейчас видно
	isShared: boolean,
	tag: string?,
	zone: number,
	judged: { [number]: boolean },
	localGrade: { [number]: string },
	results: { [number]: string },
	bolted: { [number]: boolean },
	warned: { [number]: boolean },
	center: Vector3,
	vis: RingVisual,
	light: LightSlot?,
	born: number,
	spin: number,
	lastHitsLeft: number,
	lastRay: number,
	appliedColor: Color3?,
	kindHint: boolean, -- показать подсказку нового типа удара
}

type Bolt = {
	cores: { Part },
	sheaths: { Part },
	t0: number,
	flick: boolean, -- короткое «перезажигание» (нет при мягких вспышках и сверх лимита)
	coreBase: number,
	sheathBase: number,
	lastCore: number,
	lastSheath: number,
}

type Shockwave = { part: Part, t0: number, from: number, to: number, cf: CFrame }

type ShardVis = { parts: { BasePart }, offsets: { CFrame }, sizes: { Vector3 }, transp: { number } }

type Shard = {
	id: number,
	pos: Vector3,
	amount: number,
	expires: number,
	vis: ShardVis,
	t0: number,
	phase: number,
	collected: boolean,
	collectT: number,
	fadeT: number?,
	lastScale: number,
	restored: boolean, -- уже возвращали на землю после неподтверждённого подбора
}

-- Подобранный осколок, который ждёт подтверждения сервера
type PendingShard = {
	id: number,
	pos: Vector3,
	amount: number,
	expires: number,
	zone: number,
	t0: number,
	nextSend: number,
	restored: boolean,
}

-- Стрелка к кольцу за краем экрана: треугольник-указатель и нарисованный значок цвета (как на кольце)
type Arrow = { frame: Frame, pointer: TextLabel, dots: { [string]: IconGlyph }, dot: IconGlyph? }

----------------------------------------------------------------------
-- Папка эффектов и общие помощники
----------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "StrikeFX"
fxFolder.Parent = Workspace

local function newPart(shape: Enum.PartType, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = HIDDEN
	p.Parent = fxFolder
	return p
end

-- Деталь по рецепту из Models (Block или CornerWedge), с теми же настройками, что newPart
local function newRecipePart(kind: string, material: Enum.Material): BasePart
	if kind ~= "CornerWedge" then
		return newPart(Enum.PartType.Block, material)
	end
	local p = Instance.new("CornerWedgePart")
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = HIDDEN
	p.Parent = fxFolder
	return p
end

-- Очередь перемещений: все детали кадра двигаются одним BulkMoveTo
local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}
local moveN = 0

local function queueMove(p: BasePart, cf: CFrame)
	moveN += 1
	moveParts[moveN] = p
	moveCFs[moveN] = cf
end

local function flushMoves()
	if moveN == 0 then
		return
	end
	for i = #moveParts, moveN + 1, -1 do
		moveParts[i] = nil
		moveCFs[i] = nil
	end
	Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	moveN = 0
end

local function colorDef(id: string): Config.ColorDef
	return Config.Colors[id :: Config.ColorId] or Config.Colors.blue
end

local function isColorId(v: any): boolean
	return typeof(v) == "string" and Config.Colors[v :: any] ~= nil
end

-- Цвет линий (внешнее кольцо, оболочка молнии)
local function lineColor(id: string, clock: number): Color3
	if id == "black" then
		return BLACK_LINE
	elseif id == "rainbow" then
		return Color3.fromHSV((clock * 0.35) % 1, 0.55, 1)
	end
	return colorDef(id).Color
end

-- Цвет заливки диска
local function fillColor(id: string, clock: number): Color3
	if id == "black" then
		return BLACK_FILL
	end
	return lineColor(id, clock)
end

local function softFlash(): boolean
	local d = ClientState.data
	return d == nil or d.Settings.SoftFlash
end

local function shakeOn(): boolean
	local d = ClientState.data
	return d ~= nil and d.Settings.Shake
end

local function localRoot(): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Кончик громоотвода (или голова) персонажа — сюда бьёт пойманная молния
local function rodTipOf(char: Model?): Vector3?
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then
		local tip = tool:FindFirstChild("Tip", true)
		if tip and tip:IsA("BasePart") then
			return tip.Position
		end
	end
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, 1.2, 0)
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 3, 0)
	end
	return nil
end

-- Луч к земле: высота и нормаль (только карта и рельеф)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true
local rayMap: Instance? = nil

local function groundAt(pos: Vector3): (number?, Vector3?)
	if not rayMap or not rayMap.Parent then
		local map = Workspace:FindFirstChild("Map")
		rayMap = map
		local list: { Instance } = { Workspace.Terrain }
		if map then
			table.insert(list, map)
		end
		rayParams.FilterDescendantsInstances = list
	end
	local res = Workspace:Raycast(pos + Vector3.new(0, 10, 0), Vector3.new(0, -26, 0), rayParams)
	if res then
		return res.Position.Y, res.Normal
	end
	return nil, nil
end

----------------------------------------------------------------------
-- Свет: не больше MAX_LIGHTS источников на всё (свечение туч + вспышки ударов)
----------------------------------------------------------------------
local lights: { LightSlot } = {}
for i = 1, MAX_LIGHTS do
	local p = newPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	p.Name = "Light" .. i
	p.Size = Vector3.one * 0.2
	local l = Instance.new("PointLight")
	l.Enabled = false
	l.Shadows = false
	l.Parent = p
	lights[i] = { part = p, light = l, owner = nil, flashing = false, t0 = 0, peak = 0 }
end

local function releaseLight(slot: LightSlot)
	slot.owner = nil
	slot.flashing = false
	slot.light.Enabled = false
	slot.part.CFrame = HIDDEN
end

local function acquireGlow(owner: any): LightSlot?
	for _, slot in lights do
		if slot.owner == nil and not slot.flashing then
			slot.owner = owner
			slot.light.Enabled = true
			slot.light.Brightness = 0
			return slot
		end
	end
	return nil
end

local flashTimes: { number } = {} -- полные вспышки за последнюю секунду
local boltTimes: { number } = {} -- все нарисованные молнии за последнюю секунду

local function pruneTimes(list: { number }, clock: number)
	for i = #list, 1, -1 do
		if clock - list[i] > 1 then
			table.remove(list, i)
		end
	end
end

-- Можно ли сейчас полную вспышку (яркая молния + свет). Своим — до MAX_FULL_FLASHES в секунду,
-- чужим — только если недавно вспышек не было, чтобы не съесть лимит своих.
local function takeFlash(own: boolean): boolean
	local clock = os.clock()
	pruneTimes(flashTimes, clock)
	if #flashTimes >= (if own then MAX_FULL_FLASHES else 1) then
		return false
	end
	table.insert(flashTimes, clock)
	return true
end

-- Учёт молний: своя рисуется всегда, чужая — только пока молний за секунду меньше MAX_BOLTS
local function takeBolt(own: boolean): boolean
	local clock = os.clock()
	pruneTimes(boltTimes, clock)
	if not own and #boltTimes >= MAX_BOLTS then
		return false
	end
	table.insert(boltTimes, clock)
	return true
end

-- Вспышка света в точке удара (лимит — takeFlash у вызывающего). Вспышки важнее свечения туч:
-- могут забрать у тучи источник.
local function flashLight(pos: Vector3, color: Color3, strength: number)
	local clock = os.clock()
	local slot: LightSlot? = nil
	for _, s in lights do
		if s.owner == nil and not s.flashing then
			slot = s
			break
		end
	end
	if not slot then
		for _, s in lights do
			if not s.flashing then
				local owner = s.owner
				if owner then
					owner.light = nil
				end
				slot = s
				break
			end
		end
	end
	if not slot then
		return
	end
	slot.owner = nil
	slot.flashing = true
	slot.t0 = clock
	slot.peak = FLASH_BRIGHTNESS * strength * (if softFlash() then 0.5 else 1)
	slot.light.Range = FLASH_RANGE
	slot.light.Color = color:Lerp(WHITE, 0.45)
	slot.light.Brightness = slot.peak
	slot.light.Enabled = true
	slot.part.CFrame = CFrame.new(pos)
end

local function updateFlashes(clock: number)
	for _, slot in lights do
		if slot.flashing then
			local k = (clock - slot.t0) / FLASH_TIME
			if k >= 1 then
				releaseLight(slot)
			else
				slot.light.Brightness = slot.peak * (1 - k) * (1 - k)
			end
		end
	end
end

----------------------------------------------------------------------
-- Искры (встроенная текстура), по кругу из нескольких излучателей
----------------------------------------------------------------------
local sparkParts: { Part } = {}
local sparkEmitters: { ParticleEmitter } = {}
local sparkNext = 1
local sparkTimes: { number } = {}

for i = 1, SPARK_EMITTERS do
	local p = newPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	p.Name = "Sparks" .. i
	p.Size = Vector3.one * 0.5
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEXTURE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Enabled = false
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.35, 0.75)
	e.Speed = NumberRange.new(14, 30)
	e.SpreadAngle = Vector2.new(75, 75)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -50, 0)
	e.Drag = 2.5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.ZOffset = 1
	e.Parent = p
	sparkParts[i] = p
	sparkEmitters[i] = e
end

local function sparks(pos: Vector3, color: Color3, count: number)
	local clock = os.clock()
	for i = #sparkTimes, 1, -1 do
		if clock - sparkTimes[i] > 1 then
			table.remove(sparkTimes, i)
		end
	end
	if #sparkTimes >= MAX_SPARK_BURSTS then
		return
	end
	table.insert(sparkTimes, clock)
	local i = sparkNext
	sparkNext = sparkNext % SPARK_EMITTERS + 1
	local e = sparkEmitters[i]
	sparkParts[i].CFrame = CFrame.new(pos)
	e.Color = ColorSequence.new(color:Lerp(WHITE, 0.55), color)
	e:Emit(count)
end

----------------------------------------------------------------------
-- Ударная волна на земле
----------------------------------------------------------------------
local waveFree: { Part } = {}
local waves: { Shockwave } = {}
for i = 1, SHOCKWAVE_POOL do
	local p = newPart(Enum.PartType.Cylinder, Enum.Material.Neon)
	p.Name = "Wave" .. i
	table.insert(waveFree, p)
end

local function shockwave(groundPos: Vector3, color: Color3, radius: number)
	local p = table.remove(waveFree)
	if not p then
		return
	end
	p.Color = color:Lerp(WHITE, 0.25)
	p.Transparency = 0.15
	local cf = CFrame.new(groundPos + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Size = Vector3.new(0.12, 2, 2)
	p.CFrame = cf
	table.insert(waves, { part = p, t0 = os.clock(), from = 2, to = radius * 3.2, cf = cf })
end

local function updateWaves(clock: number)
	for i = #waves, 1, -1 do
		local w = waves[i]
		local k = (clock - w.t0) / SHOCKWAVE_TIME
		if k >= 1 then
			w.part.Transparency = 1
			w.part.CFrame = HIDDEN
			table.insert(waveFree, w.part)
			waves[i] = waves[#waves]
			waves[#waves] = nil
		else
			local e = 1 - (1 - k) * (1 - k) * (1 - k)
			local d = w.from + (w.to - w.from) * e
			w.part.Size = Vector3.new(0.12, d, d)
			w.part.Transparency = 0.15 + 0.85 * k
		end
	end
end

----------------------------------------------------------------------
-- Молнии: пул неоновых цилиндров (белое ядро + цветная оболочка)
----------------------------------------------------------------------
local boltFree: { Part } = {}
local boltCreated = 0
local bolts: { Bolt } = {}

local function releaseBolt(index: number)
	local b = bolts[index]
	table.remove(bolts, index)
	for _, p in b.cores do
		p.Transparency = 1
		queueMove(p, HIDDEN)
		table.insert(boltFree, p)
	end
	for _, p in b.sheaths do
		p.Transparency = 1
		queueMove(p, HIDDEN)
		table.insert(boltFree, p)
	end
end

local function takeBoltPart(): Part?
	local p = table.remove(boltFree)
	if p then
		return p
	end
	if boltCreated < MAX_BOLT_PARTS then
		boltCreated += 1
		local np = newPart(Enum.PartType.Cylinder, Enum.Material.Neon)
		np.Name = "Bolt"
		return np
	end
	-- пул исчерпан: гасим самую старую молнию и берём её детали
	if #bolts > 0 then
		releaseBolt(1)
		flushMoves() -- сначала убрать старые детали, потом ставить заново
		return table.remove(boltFree)
	end
	return nil
end

-- Нарисовать молнию от точки в туче до точки удара.
-- dim — приглушённая (чужая или сверх лимита вспышек), flick — короткое «перезажигание» (двойная вспышка)
local function drawBolt(seed: number, from: Vector3, to: Vector3, colorId: string, detail: number, dim: boolean, flick: boolean)
	local clock = os.clock()
	local segs = BoltGeometry.build(seed, from, to, detail)
	local black = colorId == "black"
	local rainbow = colorId == "rainbow"
	local base = lineColor(colorId, clock)
	local coreColor = if black then BLACK_CORE else WHITE:Lerp(base, 0.18)
	local bolt: Bolt = {
		cores = {},
		sheaths = {},
		t0 = clock,
		flick = flick,
		coreBase = if dim then 0.25 else 0,
		sheathBase = if dim then 0.5 else 0.3,
		lastCore = -1,
		lastSheath = -1,
	}
	local n = #segs
	for i, s in segs do
		local cf, len = BoltGeometry.segmentCFrame(s)
		if len > 0.02 then
			local core = takeBoltPart()
			local sheath = takeBoltPart()
			if not core or not sheath then
				if core then
					table.insert(boltFree, core)
				end
				if sheath then
					table.insert(boltFree, sheath)
				end
				break
			end
			local w = s.Width * (if dim then 0.8 else 1)
			core.Size = Vector3.new(len + w * 0.4, w * 0.45, w * 0.45)
			core.Color = coreColor
			core.Transparency = bolt.coreBase
			local sheathColor = base
			if black then
				sheathColor = if s.Branch then BLACK_BRANCH else BLACK_LINE
			elseif rainbow then
				sheathColor = Color3.fromHSV((i / math.max(1, n) + clock * 0.2) % 1, 0.6, 1)
			end
			sheath.Size = Vector3.new(len + w * 0.8, w * 1.35, w * 1.35)
			sheath.Color = sheathColor
			sheath.Transparency = bolt.sheathBase + (if s.Branch then 0.15 else 0)
			queueMove(core, cf)
			queueMove(sheath, cf)
			table.insert(bolt.cores, core)
			table.insert(bolt.sheaths, sheath)
		end
	end
	table.insert(bolts, bolt)
end

local function updateBolts(clock: number)
	for i = #bolts, 1, -1 do
		local b = bolts[i]
		local age = clock - b.t0
		if age >= BOLT_HOLD + BOLT_FADE then
			releaseBolt(i)
		else
			local coreT, sheathT
			if age < BOLT_HOLD then
				-- короткое мерцание: молния «перезажигается» (только у полной вспышки без «мягких вспышек»)
				local flick = if b.flick and age > 0.045 and age < 0.075 then 0.55 else 0
				coreT = math.min(1, b.coreBase + flick)
				sheathT = math.min(1, b.sheathBase + flick * 0.5)
			else
				local k = (age - BOLT_HOLD) / BOLT_FADE
				coreT = b.coreBase + (1 - b.coreBase) * k
				sheathT = b.sheathBase + (1 - b.sheathBase) * k
			end
			if math.abs(coreT - b.lastCore) > 0.02 then
				b.lastCore = coreT
				for _, p in b.cores do
					p.Transparency = coreT
				end
			end
			if math.abs(sheathT - b.lastSheath) > 0.02 then
				b.lastSheath = sheathT
				for _, p in b.sheaths do
					p.Transparency = sheathT
				end
			end
		end
	end
end

-- Всё, что происходит в точке удара (full — с полной вспышкой света, см. takeFlash)
local function impact(groundPos: Vector3, hitPos: Vector3, color: Color3, radius: number, own: boolean, full: boolean)
	if full then
		flashLight(hitPos + Vector3.new(0, 3, 0), color, if own then 1 else 0.5)
	end
	shockwave(groundPos, color, radius)
	sparks(hitPos, color, if own then 14 else 8)
	if own then
		Sounds.play("ThunderNear", 1, 1, 0.12)
	else
		Sounds.play("ThunderFar", 1, 0.35)
	end
end

----------------------------------------------------------------------
-- Кольца: визуальные комплекты из пула
----------------------------------------------------------------------
-- Тучка удара — угловатая «гроза» без шаров (STYLE §6.3): плита-шестиугольник, два наклонных клуба
-- и неоновый кристалл-ядро под брюхом. Рецепт общий с листом превью (Models.strikeCloudRecipe).
local CLOUD_RECIPE = Models.strikeCloudRecipe()

-- Вид значка цвета: ◆ и ▲ есть в Montserrat, остальные — нарисованные примитивы (UIKit.glyph)
local function iconKind(colorId: string): string
	return UIKit.colorGlyphKind(colorId)
end

-- Построить значок вида kind в BillboardGui кольца и запомнить, что в нём гасить и перекрашивать
local function buildIconGlyph(parent: Instance, kind: string, color: Color3): IconGlyph
	local isPerun = kind == "perun"
	local holder = UIKit.glyph(parent, kind, {
		Name = "Glyph_" .. kind,
		Color = if isPerun then BLACK_CORE else color,
		StrokeColor = if isPerun then BLACK_LINE else Theme.Ink,
		Stroke = 3,
		Size = UDim2.fromScale(0.74, 0.74),
		Visible = false,
	})
	local g: IconGlyph = { holder = holder, items = {}, base = {}, strokes = {}, labels = {}, fills = {} }
	for _, d in holder:GetDescendants() do
		if d:IsA("Frame") then
			table.insert(g.items, d)
			table.insert(g.base, d.BackgroundTransparency)
			if string.sub(d.Name, 1, 1) == "F" and not isPerun then
				table.insert(g.fills, d)
			end
		elseif d:IsA("TextLabel") then
			table.insert(g.labels, d)
		elseif d:IsA("UIStroke") then
			table.insert(g.strokes, d)
		end
	end
	return g
end

-- Прозрачность значка: a = 1 — виден полностью, 0 — спрятан
local function setIconAlpha(g: IconGlyph, a: number)
	local t = 1 - a
	for i, item in g.items do
		local b = g.base[i]
		item.BackgroundTransparency = 1 - (1 - b) * a
	end
	for _, s in g.strokes do
		s.Transparency = t
	end
	for _, l in g.labels do
		l.TextTransparency = t
	end
end

local function setIconColor(g: IconGlyph, color: Color3)
	for _, f in g.fills do
		f.BackgroundColor3 = color
	end
	for _, l in g.labels do
		l.TextColor3 = color
	end
end

local visualPool: { RingVisual } = {}

local function makeVisual(): RingVisual
	local disk = newPart(Enum.PartType.Cylinder, Enum.Material.Neon)
	disk.Name = "RingDisk"
	local carrier = newPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	carrier.Name = "RingEdge"
	carrier.Size = Vector3.new(14, 0.05, 14)

	-- край кольца: круг с обводкой на поверхности (чёткий и дешёвый)
	local edgeGui = Instance.new("SurfaceGui")
	edgeGui.Name = "Edge"
	edgeGui.Face = Enum.NormalId.Top
	edgeGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	edgeGui.PixelsPerStud = 16
	edgeGui.LightInfluence = 0
	edgeGui.Brightness = 2
	edgeGui.AlwaysOnTop = false
	edgeGui.ResetOnSpawn = false
	edgeGui.Enabled = false
	edgeGui.Parent = carrier
	local edgeFill = Instance.new("Frame")
	edgeFill.Name = "Circle"
	edgeFill.AnchorPoint = Vector2.new(0.5, 0.5)
	edgeFill.Position = UDim2.fromScale(0.5, 0.5)
	edgeFill.Size = UDim2.new(1, -12, 1, -12)
	edgeFill.BackgroundColor3 = WHITE
	edgeFill.BackgroundTransparency = 0.82
	edgeFill.BorderSizePixel = 0
	edgeFill.Parent = edgeGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = edgeFill
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Thickness = 6
	edgeStroke.Transparency = 0.1
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Parent = edgeFill

	-- значок цвета в центре (видно издалека и под углом)
	local iconGui = Instance.new("BillboardGui")
	iconGui.Name = "Icon"
	iconGui.Size = UDim2.fromScale(3.2, 3.2)
	iconGui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	iconGui.LightInfluence = 0
	iconGui.MaxDistance = 220
	iconGui.AlwaysOnTop = false
	iconGui.ResetOnSpawn = false
	iconGui.Enabled = false
	iconGui.Parent = carrier
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(0, 0)
	count.Position = UDim2.fromScale(0.62, -0.12)
	count.Size = UDim2.fromScale(0.75, 0.6)
	count.TextScaled = true
	count.FontFace = Theme.Font
	count.TextColor3 = Theme.Volt
	count.Text = ""
	count.Visible = false
	count.Parent = iconGui
	local countStroke = Instance.new("UIStroke")
	countStroke.Thickness = 2.5
	countStroke.Color = Theme.TextStroke
	countStroke.Parent = count
	local hintGui = Instance.new("BillboardGui")
	hintGui.Name = "KindHint"
	hintGui.Size = UDim2.fromScale(11, 1.8)
	hintGui.StudsOffsetWorldSpace = Vector3.new(0, 5.4, 0)
	hintGui.LightInfluence = 0
	hintGui.MaxDistance = 140
	hintGui.AlwaysOnTop = true
	hintGui.ResetOnSpawn = false
	hintGui.Enabled = false
	hintGui.Parent = carrier
	local hint = Instance.new("TextLabel")
	hint.Name = "Text"
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.fromScale(1, 1)
	hint.TextScaled = true
	hint.FontFace = Theme.Font
	hint.TextColor3 = Theme.Volt
	hint.Text = ""
	hint.Parent = hintGui
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Thickness = 3
	hintStroke.Color = Theme.TextStroke
	hintStroke.Parent = hint

	local segs: { Part } = {}
	for i = 1, SEGMENTS do
		local s = newPart(Enum.PartType.Block, Enum.Material.Neon)
		s.Name = "RingSeg"
		segs[i] = s
	end
	local cloud: { Part } = {}
	local cloudOffsets: { CFrame } = {}
	local cloudTones: { string } = {}
	local core: Part? = nil
	local coreOffset = CFrame.identity
	local coreSize = 1.6
	for _, rp in CLOUD_RECIPE do
		if rp.Tone == "glow" then
			local c = newPart(Enum.PartType.Block, Enum.Material.Neon)
			c.Name = "CloudCore"
			c.Size = rp.Size
			core = c
			coreOffset = rp.CFrame
			coreSize = rp.Size.X
		else
			local c = newPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
			c.Name = "Cloud"
			c.Size = rp.Size
			c.Color = CLOUD_DARK
			table.insert(cloud, c)
			table.insert(cloudOffsets, rp.CFrame)
			table.insert(cloudTones, rp.Tone)
		end
	end
	if not core then
		core = newPart(Enum.PartType.Block, Enum.Material.Neon)
	end
	local coreP = core :: Part
	local leader: { Part } = {}
	for i = 1, 3 do
		local l = newPart(Enum.PartType.Cylinder, Enum.Material.Neon)
		l.Name = "Leader"
		leader[i] = l
	end
	return {
		disk = disk,
		carrier = carrier,
		edgeGui = edgeGui,
		edgeStroke = edgeStroke,
		edgeFill = edgeFill,
		iconGui = iconGui,
		glyphs = {},
		glyph = nil,
		glyphAlpha = -1,
		count = count,
		hintGui = hintGui,
		hint = hint,
		segs = segs,
		cloud = cloud,
		cloudOffsets = cloudOffsets,
		cloudTones = cloudTones,
		cloudColor = CLOUD_DARK,
		cloudT = -1,
		core = coreP,
		coreOffset = coreOffset,
		coreSize = coreSize,
		leader = leader,
		leaderJit = { Vector3.zero, Vector3.zero, Vector3.zero },
		leaderLen = { -1, -1, -1 },
		leaderNext = 0,
		segLen = -1,
		segWidth = -1,
		segTransp = -1,
		segColor = WHITE,
		segsShown = false,
		leaderShown = false,
	}
end

local function hideVisual(vis: RingVisual)
	vis.edgeGui.Enabled = false
	vis.iconGui.Enabled = false
	vis.hintGui.Enabled = false
	vis.count.Visible = false
	vis.disk.Transparency = 1
	queueMove(vis.disk, HIDDEN)
	queueMove(vis.carrier, HIDDEN)
	for _, s in vis.segs do
		s.Transparency = 1
		queueMove(s, HIDDEN)
	end
	for _, c in vis.cloud do
		c.Transparency = 1
		queueMove(c, HIDDEN)
	end
	vis.core.Transparency = 1
	queueMove(vis.core, HIDDEN)
	for _, l in vis.leader do
		l.Transparency = 1
		queueMove(l, HIDDEN)
	end
	vis.segLen = -1
	vis.segWidth = -1
	vis.segTransp = -1
	vis.segsShown = false
	vis.leaderShown = false
	vis.glyphAlpha = -1
	vis.coreSize = -1
	vis.cloudT = -1
end

local function acquireVisual(): RingVisual
	local vis = table.remove(visualPool)
	if vis then
		return vis
	end
	return makeVisual()
end

----------------------------------------------------------------------
-- Кольца: состояние
----------------------------------------------------------------------
local rings: { [number]: Ring } = {}

local function currentCenter(r: Ring, now: number): Vector3
	local runTo = r.runTo
	if runTo then
		local span = math.max(0.05, r.hits[1] - r.spawn)
		local p = Strikes.runnerPosition(r.base, runTo, (now - r.spawn) / span)
		return Vector3.new(p.X, r.groundY, p.Z)
	end
	return Vector3.new(r.base.X, r.groundY, r.base.Z)
end

-- Индекс ближайшего удара, который ещё не случился (nil — все прошли)
local function upcomingIndex(r: Ring, now: number): number?
	for i, t in r.hits do
		if now < t then
			return i
		end
	end
	return nil
end

local function removeRing(id: number)
	local r = rings[id]
	if not r then
		return
	end
	rings[id] = nil
	local slot = r.light
	if slot and slot.owner == r then
		releaseLight(slot)
	end
	r.light = nil
	hideVisual(r.vis)
	table.insert(visualPool, r.vis)
end

local function clearRings(keepZone: number?)
	local ids = {}
	for id, r in rings do
		if keepZone == nil or r.zone ~= keepZone then
			table.insert(ids, id)
		end
	end
	for _, id in ids do
		removeRing(id)
	end
	flushMoves()
end

local function applyRingColor(r: Ring, clock: number)
	local vis = r.vis
	local def = colorDef(r.colorId)
	local line = lineColor(r.colorId, clock)
	local fill = fillColor(r.colorId, clock)
	vis.disk.Color = fill
	vis.edgeStroke.Color = line
	vis.edgeFill.BackgroundColor3 = fill
	-- значок вида цвета: строится один раз на вид и остаётся в комплекте пула
	local kind = iconKind(def.Id)
	local g = vis.glyphs[kind]
	if not g then
		g = buildIconGlyph(vis.iconGui, kind, line)
		vis.glyphs[kind] = g
	end
	local cur = vis.glyph
	if cur ~= g then
		if cur then
			cur.holder.Visible = false
		end
		g.holder.Visible = true
		vis.glyph = g
		vis.glyphAlpha = -1
	end
	if def.Id ~= "black" then
		setIconColor(g, line)
	end
	r.appliedColor = line
end

-- Подсказка нового типа удара: только на своих кольцах, пока этот остров — самый дальний открытый
local kindHintsShown: { [string]: number } = {}
local function wantsKindHint(kind: Config.KindId, shared: boolean): boolean
	local d = ClientState.data
	local def = Config.Kinds[kind]
	if shared or kind == "single" or not d or not def or d.Zone > def.FromZone then
		return false
	end
	local n = kindHintsShown[kind] or 0
	if n >= KIND_HINT_RINGS then
		return false
	end
	kindHintsShown[kind] = n + 1
	return true
end

-- Текст подсказки: сколько раз жать (двойной, вилка) или что делать (обманка, бегущий)
local function kindHintText(r: Ring, left: number): string
	local fixed = KIND_HINT_TEXT[r.kind]
	if fixed then
		return fixed
	end
	if left >= #r.hits then
		return Loc.t("%s! Жми ⚡ %d раза", Loc.t("kind::" .. Config.Kinds[r.kind].Name), left)
	elseif left >= 2 then
		return Loc.t("Ещё %d раза!", left)
	end
	return Loc.t("Ещё раз!")
end

-- Сервер прислал новое кольцо
local function onStrikeSpawned(msg: Net.StrikeMsg)
	local m = msg :: any
	if typeof(m) ~= "table" or typeof(m.Id) ~= "number" or typeof(m.Pos) ~= "Vector3" then
		return
	end
	if typeof(m.Radius) ~= "number" or m.Radius <= 0 or m.Radius > 60 then
		return
	end
	if not isColorId(m.Color) or typeof(m.Kind) ~= "string" or Config.Kinds[m.Kind :: any] == nil then
		return
	end
	if typeof(m.Spawn) ~= "number" or typeof(m.Hits) ~= "table" then
		return
	end
	local hits: { number } = {}
	for i = 1, math.min(#m.Hits, 8) do
		local t = m.Hits[i]
		if typeof(t) ~= "number" or t ~= t or (i > 1 and t < hits[i - 1]) then
			return
		end
		hits[i] = t
	end
	if #hits == 0 then
		return
	end
	local now = ClientState.now()
	if now > hits[#hits] + RING_TAIL then
		return -- опоздавшее сообщение
	end
	local id = msg.Id
	if rings[id] then
		removeRing(id)
	end
	local zone = if typeof(m.Zone) == "number" then m.Zone else ClientState.zone()
	local zoneGround = if zone >= 1 and zone <= #Config.Zones then Config.Zones[zone].GroundY else msg.Pos.Y
	local groundY = msg.Pos.Y
	local normal = Vector3.yAxis
	local hy, hn = groundAt(msg.Pos)
	if hy and hn and math.abs(hy - msg.Pos.Y) < 3 then
		groundY = hy
		if hn.Y >= 0.7 then
			normal = hn
		end
	end
	local shown: Config.ColorId? = nil
	if isColorId(m.Shown) and m.Shown ~= msg.Color then
		shown = m.Shown
	end
	local upgradeAt = if typeof(m.UpgradeAt) == "number" then math.clamp(m.UpgradeAt, 0, 1) else 0.5
	local runTo: Vector3? = nil
	if msg.Kind == "runner" and typeof(m.To) == "Vector3" then
		runTo = m.To
	end
	local vis = acquireVisual()
	-- цвета тучи — от «брюха» туч острова (Config.Zones[i].Sky.CloudColor): ядро темнее, кромка светлее
	local zoneDef = Config.Zones[zone]
	local belly = if zoneDef then zoneDef.Sky.CloudColor else Config.Hub.Sky.CloudColor
	local r: Ring = {
		id = id,
		kind = msg.Kind,
		radius = msg.Radius,
		base = msg.Pos,
		runTo = runTo,
		groundY = groundY,
		normal = normal,
		cloudY = math.max(zoneGround, groundY) + Config.CloudHeight * CLOUD_SHARE,
		cloudYaw = (id * 2.39996) % (2 * math.pi),
		cloudCore = belly:Lerp(CLOUD_DEEP, 0.45),
		cloudBelly = belly,
		cloudEdge = belly:Lerp(CLOUD_LIGHT, 0.36),
		spawn = math.min(msg.Spawn, hits[1] - 0.05),
		hits = hits,
		finalColor = msg.Color,
		shown = shown,
		upgradeTime = msg.Spawn + (hits[1] - msg.Spawn) * upgradeAt,
		colorId = shown or msg.Color,
		isShared = m.Shared == true,
		tag = if typeof(m.Tag) == "string" then m.Tag else nil,
		zone = zone,
		judged = {},
		localGrade = {},
		results = {},
		bolted = {},
		warned = {},
		center = Vector3.new(msg.Pos.X, groundY, msg.Pos.Z),
		vis = vis,
		light = nil,
		born = os.clock(),
		spin = math.random() * math.pi * 2,
		lastHitsLeft = -1,
		lastRay = 0,
		appliedColor = nil,
		kindHint = false,
	}
	r.kindHint = now < hits[1] and wantsKindHint(r.kind, r.isShared)
	-- удары, которые уже прошли до прихода сообщения, не рисуем
	for i, t in hits do
		if now >= t then
			r.bolted[i] = true
		end
	end
	local d = r.radius * 2
	vis.disk.Size = Vector3.new(0.2, d, d)
	vis.carrier.Size = Vector3.new(d, 0.05, d)
	-- холст края не больше EDGE_CANVAS точек, толщина обводки — постоянная в стадах
	local pps = math.min(16, EDGE_CANVAS / d)
	local stroke = math.max(2, EDGE_STROKE * pps)
	vis.edgeGui.PixelsPerStud = pps
	vis.edgeStroke.Thickness = stroke
	vis.edgeFill.Size = UDim2.new(1, -2 * stroke, 1, -2 * stroke)
	vis.edgeGui.Enabled = true
	vis.iconGui.Enabled = true
	for i, c in vis.cloud do
		local tone = vis.cloudTones[i]
		c.Color = if tone == "edge" then r.cloudEdge elseif tone == "belly" then r.cloudBelly else r.cloudCore
	end
	vis.cloudColor = r.cloudCore
	applyRingColor(r, os.clock())
	rings[id] = r
end

-- Куда бьёт молния этого удара: в громоотвод игрока или в землю
local function insideRing(r: Ring, center: Vector3, slack: number): boolean
	local root = localRoot()
	if not root then
		return false
	end
	local p = root.Position
	return Zones.flatDist(p, center) <= r.radius + slack and math.abs(p.Y - center.Y) <= CATCH_HEIGHT
end

-- Прогноз «Шарахнуло»: игрок в кольце и сейчас, и там, где его видит сервер (позиция минус скорость × задержка)
local function insideForZap(r: Ring, center: Vector3): boolean
	local root = localRoot()
	if not root or not insideRing(r, center, ZAP_PREDICT_SLACK) then
		return false
	end
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.5 then
		return true
	end
	local okPing, ping = pcall(function(): number
		return player:GetNetworkPing()
	end)
	local halfPing = if okPing and typeof(ping) == "number" and ping == ping and ping >= 0 then ping / 2 else 0.05
	local lag = math.min(ZAP_PREDICT_MAX_LAG, halfPing + ZAP_PREDICT_LAG)
	return Zones.flatDist(root.Position - flat * lag, center) <= r.radius + ZAP_PREDICT_SLACK
end

local function strikeHit(r: Ring, index: number, center: Vector3)
	local result = r.results[index]
	local predicted = r.localGrade[index]
	local toPlayer: boolean
	if result == "ground" then
		toPlayer = false
	elseif result == "perfect" or result == "good" or result == "burst" or result == "zap" then
		toPlayer = true
	elseif result == nil and (predicted == "perfect" or predicted == "good") then
		toPlayer = true
	else
		-- промах (или ответа ещё нет): молния бьёт в игрока, только если он стоит в кольце
		toPlayer = insideRing(r, center, 0.5)
	end
	local cloudPt = Vector3.new(center.X, r.cloudY - 3, center.Z)
	local target = center
	if toPlayer then
		target = rodTipOf(player.Character) or center
	end
	local color = lineColor(r.colorId, os.clock())
	takeBolt(true)
	local full = takeFlash(true)
	drawBolt(r.id * 7 + index, cloudPt, target, r.colorId, 4, not full, full and not softFlash())
	impact(center, target, color, r.radius, true, full)
	-- стоял в кольце и не нажимал: CatchController решит, «Шарахнуло» это или подсказка
	if not r.judged[index] and r.results[index] == nil and insideForZap(r, center) then
		StrikeController.UntappedHit:Fire(r.id, index, r.colorId, r.zone)
	end
end

-- Обновить одно кольцо за кадр. Возвращает false, если кольцо пора убрать.
local function updateRing(r: Ring, now: number, clock: number, dt: number): boolean
	local hits = r.hits
	local last = hits[#hits]
	if now > last + RING_TAIL then
		return false
	end
	local vis = r.vis
	local center = currentCenter(r, now)
	-- бегущее кольцо: уточняем высоту земли под ним
	if r.runTo and clock - r.lastRay > 0.12 then
		r.lastRay = clock
		local hy, hn = groundAt(center)
		if hy and math.abs(hy - r.groundY) < 6 then
			r.groundY = hy
			r.normal = if hn and hn.Y >= 0.7 then hn else Vector3.yAxis
			center = Vector3.new(center.X, hy, center.Z)
		end
	end
	r.center = center

	-- переливание цвета
	local colorId = r.finalColor
	local shown = r.shown
	if shown and now < r.upgradeTime then
		colorId = shown
	end
	if colorId ~= r.colorId then
		r.colorId = colorId
		applyRingColor(r, clock)
		if colorId == r.finalColor and shown then
			sparks(center + Vector3.new(0, 1, 0), lineColor(colorId, clock), 24)
			Sounds.play("Shard", 1.4)
		end
	elseif colorId == "rainbow" then
		applyRingColor(r, clock)
	end
	local line = lineColor(r.colorId, clock)
	if shown and now < r.upgradeTime then
		-- кольцо «переливается»: подмигивает белым, намекая на сюрприз
		line = line:Lerp(WHITE, 0.25 + 0.25 * math.sin(clock * 9))
	end

	-- удары, время которых наступило
	for i, t in hits do
		if now >= t and not r.bolted[i] then
			r.bolted[i] = true
			strikeHit(r, i, center)
		end
	end

	local idx = upcomingIndex(r, now)
	local fadeIn = math.clamp((clock - r.born) / FADE_IN, 0, 1)
	local fadeOut = if idx then 0 else math.clamp((now - last) / RING_TAIL, 0, 1)
	local vis01 = fadeIn * (1 - fadeOut)

	-- плоскость кольца (по склону земли)
	local n = r.normal
	local right = n:Cross(Vector3.zAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local plane = CFrame.fromMatrix(center, right, n)

	local p = 0
	local remaining = math.huge
	if idx then
		local prev = if idx == 1 then r.spawn else hits[idx - 1]
		local span = math.max(0.05, hits[idx] - prev)
		p = Strikes.ringProgress(r.kind, (now - prev) / span)
		remaining = hits[idx] - now
		-- звук-предупреждение для редких цветов
		if not r.warned[idx] and remaining <= WARN_LEAD and colorDef(r.colorId).Order >= WARN_MIN_ORDER then
			r.warned[idx] = true
			Sounds.play("Warn", 1, 0.6)
		end
	end

	-- диск и край
	queueMove(vis.disk, plane * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2))
	queueMove(vis.carrier, plane * CFrame.new(0, 0.24, 0))
	vis.disk.Transparency = 1 - (0.45 + 0.25 * p * p * p) * vis01
	vis.edgeStroke.Transparency = 1 - 0.92 * vis01
	vis.edgeFill.BackgroundTransparency = 1 - 0.2 * vis01
	local glyph = vis.glyph
	if glyph and (math.abs(vis01 - vis.glyphAlpha) >= ICON_ALPHA_STEP or (vis01 >= 1 and vis.glyphAlpha < 1) or (vis01 <= 0 and vis.glyphAlpha > 0)) then
		vis.glyphAlpha = vis01
		setIconAlpha(glyph, vis01)
	end

	-- сколько ударов осталось (двойной, вилка)
	local left = 0
	for _, t in hits do
		if now < t then
			left += 1
		end
	end
	if left ~= r.lastHitsLeft then
		r.lastHitsLeft = left
		-- двойной и вилка: «×2» → «×1» до последнего удара (второй удар — тоже нажатие)
		vis.count.Visible = #hits >= 2 and left >= 1
		vis.count.Text = "×" .. tostring(left)
		if r.kindHint then
			vis.hintGui.Enabled = left >= 1
			vis.hint.Text = kindHintText(r, left)
		end
	end
	if r.kindHint and left >= 1 then
		vis.hint.TextTransparency = 0.2 * (0.5 + 0.5 * math.sin(clock * 8))
	end

	-- внешнее сжимающееся кольцо
	if idx then
		r.spin += dt * (0.5 + 2.5 * p)
		local radius = r.radius * (OUTER_START - (OUTER_START - 1) * p)
		local arc = 2 * math.pi * radius / SEGMENTS
		-- пунктир смыкается к удару
		local segLen = arc * (0.68 + 0.38 * p)
		local width = 0.28 + 0.22 * p
		local transp = 1 - (0.35 + 0.65 * p ^ 1.4) * fadeIn
		local color = line:Lerp(WHITE, 0.65 * p ^ 6)
		-- размер деталей менять дорого (телефоны): только при заметной разнице, а не каждый кадр
		if math.abs(segLen - vis.segLen) > vis.segLen * SEG_RESIZE or math.abs(width - vis.segWidth) > SEG_WIDTH_STEP then
			vis.segLen = segLen
			vis.segWidth = width
			local size = Vector3.new(segLen, SEG_HEIGHT, width)
			for _, s in vis.segs do
				s.Size = size
			end
		end
		if math.abs(transp - vis.segTransp) > 0.01 then
			vis.segTransp = transp
			for _, s in vis.segs do
				s.Transparency = transp
			end
		end
		if color ~= vis.segColor then
			vis.segColor = color
			for _, s in vis.segs do
				s.Color = color
			end
		end
		local step = 2 * math.pi / SEGMENTS
		for i, s in vis.segs do
			local a = r.spin + i * step
			local c, sn = math.cos(a), math.sin(a)
			local local_ = CFrame.fromMatrix(Vector3.new(c * radius, 0.3, sn * radius), Vector3.new(-sn, 0, c), Vector3.yAxis)
			queueMove(s, plane * local_)
		end
		vis.segsShown = true
	elseif vis.segsShown then
		vis.segsShown = false
		for _, s in vis.segs do
			s.Transparency = 1
			queueMove(s, HIDDEN)
		end
		vis.segTransp = -1
	end

	-- туча над кольцом: разгорается изнутри перед ударом
	local glow = 0
	if idx then
		glow = math.clamp(1 - remaining / CLOUD_GLOW_TIME, 0, 1)
	else
		glow = math.clamp(1 - (now - last) / 0.2, 0, 1)
	end
	local cloudBase = Vector3.new(center.X, r.cloudY, center.Z)
	-- тучка плотная, как потолок туч: проявляется и тает вместе с кольцом; перед ударом её ядро (низ)
	-- наливается цветом молнии, а кристалл под брюхом растёт, крутится и светится
	local sway = math.sin(clock * 0.6 + r.cloudYaw) * 0.06
	local wob = Vector3.new(math.sin(clock * 0.7 + r.id) * 0.35, math.sin(clock * 0.9 + r.id * 2) * 0.25 - CLOUD_DROP, 0)
	local cloudCF = CFrame.new(cloudBase + wob) * CFrame.Angles(0, r.cloudYaw + sway, 0)
	local cloudT = 1 - vis01
	local fadeCloud = math.abs(cloudT - vis.cloudT) > 0.01 or (cloudT <= 0 and vis.cloudT > 0)
	if fadeCloud then
		vis.cloudT = cloudT
	end
	local cloudColor = r.cloudCore:Lerp(line, 0.45 * glow)
	local recolor = cloudColor ~= vis.cloudColor
	vis.cloudColor = cloudColor
	for i, c in vis.cloud do
		queueMove(c, cloudCF * vis.cloudOffsets[i])
		if fadeCloud then
			c.Transparency = cloudT
		end
		if recolor and vis.cloudTones[i] == "core" then
			c.Color = cloudColor
		end
	end
	local coreP = (cloudCF * vis.coreOffset).Position - Vector3.new(0, 0.35 * glow, 0)
	if glow > 0.01 then
		local s = math.floor((1.6 + 1.6 * glow) / CLOUD_CORE_STEP + 0.5) * CLOUD_CORE_STEP
		if s ~= vis.coreSize then
			vis.coreSize = s
			vis.core.Size = Vector3.new(s, s, s)
		end
		queueMove(vis.core, CFrame.new(coreP) * CFrame.Angles(0, clock * 2.2, 0) * vis.coreOffset.Rotation)
		vis.core.Color = line:Lerp(WHITE, 0.3)
		vis.core.Transparency = 1 - 0.85 * glow * vis01
		local slot = r.light
		if not slot then
			slot = acquireGlow(r)
			r.light = slot
		end
		if slot then
			slot.part.CFrame = CFrame.new(coreP)
			slot.light.Range = 28
			slot.light.Color = line
			slot.light.Brightness = 3.5 * glow * (if softFlash() then 0.6 else 1)
		end
	else
		vis.core.Transparency = 1
		local slot = r.light
		if slot then
			if slot.owner == r then
				releaseLight(slot)
			end
			r.light = nil
		end
	end

	-- дрожащая «ниточка» из тучи к земле в последние доли секунды
	if idx and remaining <= LEADER_TIME then
		local k = 1 - remaining / LEADER_TIME
		local from = cloudBase + Vector3.new(0, -3, 0)
		local tip = from:Lerp(center + Vector3.new(0, 1, 0), k)
		local parts = #vis.leader
		-- форма дрожит не каждый кадр, а раз в LEADER_JITTER (дешевле и без стробоскопа)
		local rejitter = not vis.leaderShown or clock >= vis.leaderNext
		if rejitter then
			vis.leaderNext = clock + LEADER_JITTER
		end
		local prevPt = from
		for i, l in vis.leader do
			if rejitter then
				vis.leaderJit[i] = if i < parts then Vector3.new((math.random() - 0.5) * 2.4, 0, (math.random() - 0.5) * 2.4) else Vector3.zero
				l.Color = WHITE:Lerp(line, 0.4)
				l.Transparency = 0.1 + math.random() * 0.55
			end
			local pt = from:Lerp(tip, i / parts) + vis.leaderJit[i]
			local cf, len = Geom.axisCFrame(prevPt, pt)
			-- длина с шагом и запасом (без щелей между частями): размер меняется редко
			local q = math.ceil((len + 0.1) / LEADER_LEN_STEP) * LEADER_LEN_STEP
			if q ~= vis.leaderLen[i] then
				vis.leaderLen[i] = q
				l.Size = Vector3.new(q, 0.14, 0.14)
			end
			queueMove(l, cf)
			prevPt = pt
		end
		vis.leaderShown = true
	elseif vis.leaderShown then
		vis.leaderShown = false
		for _, l in vis.leader do
			l.Transparency = 1
			queueMove(l, HIDDEN)
		end
	end
	return true
end

----------------------------------------------------------------------
-- Итоги ударов от сервера
----------------------------------------------------------------------
local function onStrikeResolved(msg: Net.StrikeResultMsg)
	local m = msg :: any
	if typeof(m) ~= "table" or typeof(m.Id) ~= "number" or typeof(m.Hit) ~= "number" or typeof(m.Grade) ~= "string" then
		return
	end
	local grade = msg.Grade
	local r = rings[msg.Id]
	if r then
		r.results[msg.Hit] = grade
		r.judged[msg.Hit] = true
		local t = r.hits[msg.Hit]
		-- сервер ответил раньше, чем кадр дошёл до удара: рисуем сразу (если время удара уже наступило)
		if t and not r.bolted[msg.Hit] and ClientState.now() >= t - 0.03 then
			r.bolted[msg.Hit] = true
			strikeHit(r, msg.Hit, r.center)
		end
	end
	if (grade == "perfect" or grade == "good") and typeof(m.Charge) == "number" and m.Charge > 0 then
		local pos: Vector3 = if r then r.center elseif typeof(m.Pos) == "Vector3" then m.Pos else Vector3.zero
		if r or typeof(m.Pos) == "Vector3" then
			local colorId = if isColorId(m.Color) then m.Color else "blue"
			Juice.popup(pos + Vector3.new(0, 3, 0), "+" .. Format.short(msg.Charge), lineColor(colorId, os.clock()), grade == "perfect")
		end
		if shakeOn() then
			Juice.shake(if grade == "perfect" then 0.22 else 0.14)
		end
	elseif (grade == "perfect" or grade == "good") and typeof(m.Jar) == "number" and typeof(m.Capacity) == "number" and m.Jar >= m.Capacity then
		-- поймал, но заряд не влез (банка полна, а перегружать нельзя): объяснить, куда делась награда
		local pos: Vector3? = if r then r.center elseif typeof(m.Pos) == "Vector3" then m.Pos else nil
		if pos then
			local text = if ClientState.droneAway() then Loc.t("Банка полна — дрон в пути") else Loc.t("Банка полна!")
			Juice.popup(pos + Vector3.new(0, 3, 0), text, Theme.Volt, false)
		end
	end
end

-- Чужие молнии (для красоты): упрощённо, тише и без лишнего света
local function onBoltFX(msg: any)
	if typeof(msg) ~= "table" or typeof(msg.Pos) ~= "Vector3" or not isColorId(msg.Color) then
		return
	end
	if msg.UserId == player.UserId then
		return
	end
	local zone = if typeof(msg.Zone) == "number" then msg.Zone else 0
	if zone ~= ClientState.zone() or zone < 1 or zone > #Config.Zones then
		return
	end
	local cam = Workspace.CurrentCamera
	if cam and (cam.CFrame.Position - msg.Pos).Magnitude > OTHERS_BOLT_DISTANCE then
		return
	end
	local pos: Vector3 = msg.Pos
	local cloudY = math.max(Config.Zones[zone].GroundY, pos.Y) + Config.CloudHeight * CLOUD_SHARE
	local from = Vector3.new(pos.X, cloudY - 3, pos.Z)
	local target = pos
	if msg.Caught == true and typeof(msg.UserId) == "number" then
		local other = Players:GetPlayerByUserId(msg.UserId)
		local tip = if other then rodTipOf(other.Character) else nil
		if tip then
			target = tip
		end
	end
	if not takeBolt(false) then
		return -- и так много молний за секунду (светочувствительность)
	end
	local seed = if typeof(msg.Seed) == "number" then msg.Seed else math.random(1, 1e6)
	local color = lineColor(msg.Color, os.clock())
	drawBolt(seed, from, target, msg.Color, 3, true, false)
	impact(pos, target, color, Config.Catch.RingRadius, false, takeFlash(false))
end

----------------------------------------------------------------------
-- Осколки на земле
----------------------------------------------------------------------
-- Осколок: три стеклянных шипа-уголка разной высоты и неоновая сердцевина-ромб (Models.shardRecipe)
local CRYSTALS = Models.shardRecipe()

local shardPool: { ShardVis } = {}
local shards: { [number]: Shard } = {}
local shardCount = 0
local pendingShards: { [number]: PendingShard } = {}
local shardStep = 0
local lastShardPick = 0
local shardCollectEvent: RemoteEvent? = nil

local function makeShardVis(): ShardVis
	local vis: ShardVis = { parts = {}, offsets = {}, sizes = {}, transp = {} }
	for i, c in CRYSTALS do
		local neon = c.Tone == "glow"
		local p = newRecipePart(c.Kind, if neon then Enum.Material.Neon else Enum.Material.Glass)
		p.Name = "Shard"
		p.Color = if neon then Theme.Shard else SHARD_COLOR
		p.Reflectance = if neon then 0 else 0.15
		p.Size = c.Size
		vis.parts[i] = p
		vis.offsets[i] = c.CFrame
		vis.sizes[i] = c.Size
		vis.transp[i] = if neon then 0.15 else 0.25
	end
	return vis
end

local function removeShard(id: number)
	local s = shards[id]
	if not s then
		return
	end
	shards[id] = nil
	shardCount -= 1
	for i, p in s.vis.parts do
		p.Transparency = 1
		p.Size = s.vis.sizes[i]
		queueMove(p, HIDDEN)
	end
	table.insert(shardPool, s.vis)
end

local function clearShards()
	local ids = {}
	for id in shards do
		table.insert(ids, id)
	end
	for _, id in ids do
		removeShard(id)
	end
	flushMoves()
end

local function addShard(id: number, pos: Vector3, amount: number, expires: number, restored: boolean)
	-- лимит: убираем самый старый
	if shardCount >= Config.Server.MaxShards then
		local oldestId, oldestT = nil, math.huge
		for sid, s in shards do
			if s.t0 < oldestT then
				oldestId, oldestT = sid, s.t0
			end
		end
		if oldestId then
			removeShard(oldestId)
		end
	end
	local vis = table.remove(shardPool) or makeShardVis()
	shards[id] = {
		id = id,
		pos = pos,
		amount = amount,
		expires = expires,
		vis = vis,
		t0 = os.clock(),
		phase = math.random() * math.pi * 2,
		collected = false,
		collectT = 0,
		fadeT = nil,
		lastScale = -1,
		restored = restored,
	}
	shardCount += 1
end

local function onShardSpawn(msg: any)
	if typeof(msg) ~= "table" or typeof(msg.Id) ~= "number" or typeof(msg.Pos) ~= "Vector3" then
		return
	end
	local id: number = msg.Id
	if shards[id] or pendingShards[id] then
		return
	end
	local expires = if typeof(msg.Expires) == "number" then msg.Expires else ClientState.now() + Config.Catch.ShardLifetime
	addShard(id, msg.Pos, if typeof(msg.Amount) == "number" then msg.Amount else 1, expires, false)
end

local function sendShardCollect(id: number)
	local ev = shardCollectEvent
	if ev then
		ev:FireServer(id)
	end
end

-- Подобрал (по своей позиции): осколок лопается со звоном сразу, а «+N 💎» — когда сервер подтвердит
local function collectShard(s: Shard)
	local clock = os.clock()
	s.collected = true
	s.collectT = clock
	sendShardCollect(s.id)
	pendingShards[s.id] = {
		id = s.id,
		pos = s.pos,
		amount = s.amount,
		expires = s.expires,
		zone = ClientState.zone(),
		t0 = clock,
		nextSend = clock + SHARD_RESEND,
		restored = s.restored,
	}
	if clock - lastShardPick < SHARD_LADDER_GAP then
		shardStep = math.min(shardStep + 1, #LADDER)
	else
		shardStep = 1
	end
	lastShardPick = clock
	Sounds.play("Shard", Sounds.ladderPitch(LADDER[shardStep], 12))
end

-- Повторы ShardCollect и истёкшие ожидания
local function updatePendingShards(now: number, clock: number)
	local done: { number }? = nil
	local root = localRoot()
	local reach = Config.Catch.ShardPickupRadius + Config.Server.ShardPickupSlack + SHARD_RESEND_REACH
	for id, p in pendingShards do
		if clock - p.t0 >= SHARD_CONFIRM_TIME then
			done = done or {}
			table.insert(done :: { number }, id)
		elseif clock >= p.nextSend then
			p.nextSend = clock + SHARD_RESEND
			-- далеко ушёл — сервер его рядом уже не увидит, повторять бесполезно
			if root and Zones.flatDist(root.Position, p.pos) <= reach then
				sendShardCollect(id)
			end
		end
	end
	if not done then
		return
	end
	for _, id in done do
		local p = pendingShards[id]
		pendingShards[id] = nil
		-- сервер так и не засчитал (видел игрока дальше): осколок снова на земле, можно подобрать ещё раз
		if p and not p.restored and not shards[id] and p.zone == ClientState.zone() and now < p.expires - 1 then
			addShard(id, p.pos, p.amount, p.expires, true)
		end
	end
end

-- Сервер засчитал подбор осколка id (Effect "shard"): больше не повторяем ShardCollect, «+N 💎»
local function onShardConfirmed(id: number)
	local p = pendingShards[id]
	local s = shards[id]
	local amount: number
	if p then
		pendingShards[id] = nil
		amount = p.amount
	elseif s and s.restored and not s.collected then
		-- подтверждение опоздало, и осколок уже вернули на землю: убрать его
		amount = s.amount
		removeShard(id)
	else
		return
	end
	local root = localRoot()
	local at = if root then root.Position + Vector3.new(0, 3, 0) elseif p then p.pos + Vector3.new(0, 1.5, 0) else nil
	if at then
		Juice.popup(at, "+" .. Format.short(amount) .. " 💎", Theme.Shard, false)
	end
end

local function updateShards(now: number, clock: number)
	if shardCount == 0 then
		return
	end
	local root = localRoot()
	local rootPos = if root then root.Position else nil
	local pickR = Config.Catch.ShardPickupRadius
	local dead: { number }? = nil
	for id, s in shards do
		local age = clock - s.t0
		-- подбор
		if not s.collected and rootPos and Zones.flatDist(rootPos, s.pos) <= pickR and math.abs(rootPos.Y - s.pos.Y) <= CATCH_HEIGHT then
			collectShard(s)
		end
		-- исчезновение по времени
		if not s.collected and not s.fadeT and now >= s.expires then
			s.fadeT = clock
		end
		local scale = 1
		local transpAdd = 0
		local lift = 0
		local fadeT = s.fadeT
		if s.collected then
			local k = (clock - s.collectT) / SHARD_POP
			if k >= 1 then
				dead = dead or {}
				table.insert(dead :: { number }, id)
				continue
			end
			scale = 1 + 0.6 * k
			transpAdd = k
			lift = 2.5 * k
		elseif fadeT then
			local k = (clock - fadeT) / SHARD_FADE
			if k >= 1 then
				dead = dead or {}
				table.insert(dead :: { number }, id)
				continue
			end
			scale = 1 - 0.6 * k
			transpAdd = k
		elseif age < SHARD_GROW then
			local k = age / SHARD_GROW
			-- рост с перелётом (Back)
			scale = 1 + 2.7 * (k - 1) ^ 3 + 1.7 * (k - 1) ^ 2
			scale = math.max(0.05, scale)
		end
		local spin = clock * 1.6 + s.phase
		local bob = 0.45 + math.sin(clock * 2.4 + s.phase) * 0.3 + lift
		local base = CFrame.new(s.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin, 0)
		local vis = s.vis
		local resize = math.abs(scale - s.lastScale) > 0.005
		for i, part in vis.parts do
			local off = vis.offsets[i]
			if scale ~= 1 then
				off = CFrame.new(off.Position * scale) * off.Rotation
			end
			queueMove(part, base * off)
			if resize then
				part.Size = vis.sizes[i] * scale
				part.Transparency = math.min(1, vis.transp[i] + transpAdd)
			end
		end
		s.lastScale = scale
	end
	if dead then
		for _, id in dead do
			removeShard(id)
		end
	end
end

----------------------------------------------------------------------
-- Стрелки к кольцам за краем экрана
----------------------------------------------------------------------
local arrowRoot: Frame? = nil
local arrows: { Arrow } = {}

local function ensureArrowRoot(): Frame?
	local rootFrame = arrowRoot
	if rootFrame and rootFrame.Parent then
		return rootFrame
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gui = UIKit.new("ScreenGui", {
		Name = "StrikeArrows",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = pg,
	}) :: ScreenGui
	local frame = UIKit.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		Parent = gui,
	}) :: Frame
	arrowRoot = frame
	table.clear(arrows)
	return frame
end

local function makeArrow(parent: Frame): Arrow
	local frame = UIKit.new("Frame", {
		Name = "Arrow",
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = parent,
	}) :: Frame
	UIKit.autoScale(frame, "hud")
	local pointer = UIKit.label({
		Name = "Pointer",
		Text = "▲",
		FontFace = Theme.FontDisplayFlat, -- ▲ есть только в Montserrat
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		MaxTextSize = 40,
		NoStroke = false,
		Parent = frame,
	})
	return { frame = frame, pointer = pointer, dots = {}, dot = nil }
end

-- Значок цвета в стрелке: строится один раз на вид и остаётся в стрелке
local function setArrowDot(a: Arrow, colorId: string, color: Color3)
	local kind = iconKind(colorId)
	local g = a.dots[kind]
	if not g then
		local isPerun = kind == "perun"
		local holder = UIKit.glyph(a.frame, kind, {
			Name = "Dot_" .. kind,
			Color = if isPerun then BLACK_CORE else color,
			StrokeColor = if isPerun then BLACK_LINE else Theme.Ink,
			Stroke = 2,
			Size = UDim2.fromOffset(30, 30),
		})
		g = { holder = holder, items = {}, base = {}, strokes = {}, labels = {}, fills = {} }
		for _, d in holder:GetDescendants() do
			if d:IsA("Frame") and string.sub(d.Name, 1, 1) == "F" and not isPerun then
				table.insert(g.fills, d)
			elseif d:IsA("TextLabel") then
				table.insert(g.labels, d)
			end
		end
		a.dots[kind] = g
	end
	if a.dot ~= g then
		if a.dot then
			a.dot.holder.Visible = false
		end
		g.holder.Visible = true
		a.dot = g
	end
	if colorId ~= "black" then
		setIconColor(g, color)
	end
end

local function updateArrows(now: number, clock: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local used = 0
	local rootFrame: Frame? = nil
	local vp = cam.ViewportSize
	local margin = ARROW_MARGIN * math.clamp(vp.Y / 720, 0.6, 1.2)
	local cx, cy = vp.X / 2, vp.Y / 2
	-- на телефоне внизу джойстик и кнопки (прыжок, ⚡): стрелки туда не ставим
	local left, right, top = margin, vp.X - margin, margin
	local bottom = if UIKit.isTouch() then vp.Y * (1 - ARROW_TOUCH_BOTTOM) else vp.Y - margin
	for _, r in rings do
		local idx = upcomingIndex(r, now)
		if idx then
			local sp = cam:WorldToViewportPoint(r.center + Vector3.new(0, 1, 0))
			local inView = sp.Z > 0 and sp.X >= margin and sp.X <= vp.X - margin and sp.Y >= margin and sp.Y <= vp.Y - margin
			if not inView then
				rootFrame = rootFrame or ensureArrowRoot()
				local parent = rootFrame
				if not parent then
					break
				end
				used += 1
				local a = arrows[used]
				if not a then
					a = makeArrow(parent)
					arrows[used] = a
				end
				local dx, dy = sp.X - cx, sp.Y - cy
				if sp.Z < 0 then
					dx, dy = -dx, -dy
				end
				local len = math.sqrt(dx * dx + dy * dy)
				if len < 1e-3 then
					dx, dy, len = 0, 1, 1
				end
				dx, dy = dx / len, dy / len
				-- луч из центра экрана до края разрешённой рамки
				local sx = if dx > 1e-4 then (right - cx) / dx elseif dx < -1e-4 then (left - cx) / dx else math.huge
				local sy = if dy > 1e-4 then (bottom - cy) / dy elseif dy < -1e-4 then (top - cy) / dy else math.huge
				local s = math.max(0, math.min(sx, sy))
				local color = lineColor(r.colorId, clock)
				a.frame.Position = UDim2.fromOffset(cx + dx * s, cy + dy * s)
				a.pointer.Rotation = math.deg(math.atan2(dy, dx)) + 90
				a.pointer.Position = UDim2.new(0.5, dx * 20, 0.5, dy * 20)
				a.pointer.TextColor3 = color
				setArrowDot(a, r.colorId, color)
				-- пульс перед ударом
				local remaining = r.hits[idx] - now
				local pulse = if remaining < 0.8 then 0.5 + 0.5 * math.sin(clock * 18) else 0
				a.pointer.TextTransparency = 0.25 * pulse
				a.frame.Visible = true
			end
		end
	end
	for i = used + 1, #arrows do
		arrows[i].frame.Visible = false
	end
end

----------------------------------------------------------------------
-- Главный цикл
----------------------------------------------------------------------
local function step(dt: number)
	local now = ClientState.now()
	local clock = os.clock()
	local dead: { number }? = nil
	for id, r in rings do
		if not updateRing(r, now, clock, dt) then
			dead = dead or {}
			table.insert(dead :: { number }, id)
		end
	end
	if dead then
		for _, id in dead do
			removeRing(id)
		end
	end
	updateShards(now, clock)
	if next(pendingShards) ~= nil then
		updatePendingShards(now, clock)
	end
	updateBolts(clock)
	updateWaves(clock)
	updateFlashes(clock)
	flushMoves()
	updateArrows(now, clock)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------
local function infoOf(r: Ring, now: number): StrikeInfo
	local idx = upcomingIndex(r, now)
	local left = 0
	for _, t in r.hits do
		if now < t then
			left += 1
		end
	end
	return {
		Id = r.id,
		Center = currentCenter(r, now),
		Radius = r.radius,
		Color = r.finalColor,
		Kind = r.kind,
		NextHit = if idx then r.hits[idx] else nil,
		NextIndex = idx,
		HitsLeft = left,
		Shared = r.isShared,
		Tag = r.tag,
	}
end

-- Кольца, у которых ещё есть удары впереди
function StrikeController.activeStrikes(): { StrikeInfo }
	local now = ClientState.now()
	local out: { StrikeInfo } = {}
	for _, r in rings do
		if upcomingIndex(r, now) then
			table.insert(out, infoOf(r, now))
		end
	end
	return out
end

function StrikeController.info(id: number): StrikeInfo?
	local r = rings[id]
	if not r then
		return nil
	end
	return infoOf(r, ClientState.now())
end

-- Серверное время удара hit кольца id
function StrikeController.hitTime(id: number, hit: number): number?
	local r = rings[id]
	return if r then r.hits[hit] else nil
end

-- Удар для нажатия: из колец, в которых стоит игрок (центр с учётом бегущего, Radius + TARGET_SLACK),
-- берём ещё не оценённый удар, окно которого не закрылось, ближайший по времени к нажатию
-- (у двойного и вилки это может быть и не первый: пропустил удар — нажатие идёт следующему).
-- Третье значение — стоит ли игрок хоть в каком-то кольце (даже если ловить там уже нечего).
function StrikeController.targetFor(rootPos: Vector3, tapTime: number): (number?, number?, boolean)
	local _, good = ClientState.windows()
	local now = ClientState.now()
	local bestId: number? = nil
	local bestHit: number? = nil
	local bestErr = math.huge
	local inside = false
	for id, r in rings do
		local c = currentCenter(r, now)
		if Zones.flatDist(rootPos, c) <= r.radius + TARGET_SLACK and math.abs(rootPos.Y - c.Y) <= CATCH_HEIGHT then
			inside = true
			for i, t in r.hits do
				if not r.judged[i] and tapTime <= t + good + LATE_SLACK then
					local err = math.abs(tapTime - t)
					if err < bestErr then
						bestErr = err
						bestId = id
						bestHit = i
					end
				end
			end
		end
	end
	return bestId, bestHit, inside
end

-- Нажатие на этот удар уже отправлено (второй раз его выбрать нельзя)
function StrikeController.markJudged(id: number, hit: number, grade: string?)
	local r = rings[id]
	if not r then
		return
	end
	r.judged[hit] = true
	if grade then
		r.localGrade[hit] = grade
	end
end

-- Убрать все кольца (смена зоны, гибель персонажа)
function StrikeController.clear()
	clearRings(nil)
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
local started = false
function StrikeController.start()
	if started then
		return
	end
	started = true
	ClientState.StrikeSpawned:Connect(onStrikeSpawned)
	ClientState.StrikeResolved:Connect(onStrikeResolved)
	ClientState.Effect:Connect(function(msg: Net.EffectMsg)
		local m = msg :: any
		if m.Kind == "shard" and typeof(m.Value) == "number" then
			onShardConfirmed(m.Value)
		end
	end)
	ClientState.ZoneChanged:Connect(function(zone: number)
		clearRings(zone)
		clearShards()
	end)

	local function hookCharacter(char: Model)
		task.spawn(function()
			local hum = char:WaitForChild("Humanoid", 10)
			if hum and hum:IsA("Humanoid") then
				hum.Died:Connect(function()
					clearRings(nil)
				end)
			end
		end)
	end
	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(char: Model)
		clearRings(nil)
		hookCharacter(char)
	end)

	-- удалённые события без ClientState (они нужны только здесь)
	task.spawn(function()
		shardCollectEvent = Net.event("ShardCollect")
		Net.event("ShardSpawn").OnClientEvent:Connect(onShardSpawn)
		Net.unreliable("BoltFX").OnClientEvent:Connect(onBoltFX)
	end)

	RunService.PreRender:Connect(step)
end

return StrikeController
