--!strict
-- STRETCH-POP · StretchHUDController — тактильный мультяшный интерфейс.
-- Всё строится кодом (без ассетов): шрифт FredokaOne, сочные UIGradient, толстые UIStroke-контуры,
-- и каждая анимация — пружина по закону Гука из Shared.Math.Spring (Spring.Number / Spring.Vector).
--
--   • Прицел + кольцо натяжения рогатки (TensionChanged): цвет зелёный→жёлтый→красный, на 100% — дрожь.
--   • Пружинный спидометр (slingshot:GetSpeed()): стрелка с перелётом, на SupersonicSpeed — неон и пламя.
--   • Счётчик комбо, подпрыгивающий на каждом Bounced/Smashed, и подсказка порога Гонга.
--   • 3D-цифры скорости и лута, летящие по параболе (BillboardGui), слова «BOING!» на отскоках.
--   • Баннер перерождения (RebirthWave) и подсказка «чего не хватило» (GongResult).
--   • Панель прокачки 3 статов с превью через StretchPhysics.Derive и витрина перчаток GloveConfig.
--     Открывается Tab / Alt / кнопкой на экране / Y на геймпаде; курсор камеры освобождается.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local LevelConfig = require(Shared.Config.LevelConfig)
local GloveConfig = require(Shared.Config.GloveConfig)
local Spring = require(Shared.Math.Spring)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local Signal = require(Shared.Util.Signal)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ElasticSlingshotController = require(Client.Controllers.ElasticSlingshotController)
local ShoulderCamera = require(Client.Controllers.ShoulderCameraController)

-- ── Стиль ──────────────────────────────────────────────────────────────────

local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(28, 18, 48)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 214, 64)
local GOLD_DARK = Color3.fromRGB(255, 136, 28)
local GREEN = Color3.fromRGB(110, 240, 120)
local GREEN_DARK = Color3.fromRGB(30, 170, 80)
local RED = Color3.fromRGB(255, 86, 98)
local RED_DARK = Color3.fromRGB(190, 30, 70)
local GRAY = Color3.fromRGB(150, 150, 170)
local GRAY_DARK = Color3.fromRGB(80, 80, 104)
local NEON_PINK = Color3.fromRGB(255, 64, 200)
local NEON_CYAN = Color3.fromRGB(64, 240, 255)
local NEON_YELLOW = Color3.fromRGB(255, 250, 120)
local PANEL_TOP = Color3.fromRGB(96, 70, 210)
local PANEL_BOTTOM = Color3.fromRGB(46, 26, 118)
local CARD_TOP = Color3.fromRGB(132, 108, 236)
local CARD_BOTTOM = Color3.fromRGB(78, 52, 176)
local SPEEDO_TOP = Color3.fromRGB(58, 64, 140)
local SPEEDO_BOTTOM = Color3.fromRGB(26, 22, 70)
local TENSION_LOW = Color3.fromRGB(110, 255, 140)
local TENSION_MID = Color3.fromRGB(255, 226, 80)
local TENSION_HIGH = Color3.fromRGB(255, 70, 70)

local REFERENCE_HEIGHT = 900
local RING_SEGMENTS = 32
local RING_RADIUS = 34
local GAUGE_TICKS = 21
local GAUGE_RADIUS = 96
local GAUGE_MAX_SPEED = 420
local FLAME_COUNT = 9
local MAX_POPUPS = 14
local POPUP_GRAVITY = Vector3.new(0, -55, 0)
local ACTION_TOGGLE = "StretchPop_TogglePanel"
local SUPERSONIC_OFF_MARGIN = 20
local REQUEST_TIMEOUT = 2

type StatInfo = {
	Title: string,
	Subtitle: string,
	Letter: string,
	Color: Color3,
}

local STAT_ORDER: { Types.StatName } = { "Elasticity", "SpringPower", "SmashMass" }
local STAT_INFO: { [Types.StatName]: StatInfo } = {
	Elasticity = { Title = "ELASTICITY", Subtitle = "Растяжимость", Letter = "E", Color = Color3.fromRGB(255, 120, 200) },
	SpringPower = { Title = "SPRING POWER", Subtitle = "Сила пружины", Letter = "S", Color = Color3.fromRGB(80, 220, 255) },
	SmashMass = { Title = "SMASH MASS", Subtitle = "Ударная масса", Letter = "M", Color = Color3.fromRGB(255, 170, 60) },
}

local REASON_TEXT: { [string]: string } = {
	not_enough_coins = "Не хватает монет",
	max_level = "Максимальный уровень",
	rate_limited = "Слишком быстро!",
	no_profile = "Профиль ещё грузится",
	already_owned = "Уже куплено",
	not_owned = "Сначала купи",
	unknown_glove = "Нет такой перчатки",
	timeout = "Сервер не ответил",
	too_slow = "мало скорости",
	combo_too_low = "мало комбо",
	speed_unverified = "сервер не подтвердил скорость",
	combo_unverified = "сервер не подтвердил комбо",
	too_far = "сервер не увидел тебя у Гонга",
	cooldown = "Гонг ещё звенит",
	wave_in_progress = "волна ещё идёт",
	not_your_lane = "это чужой Гонг",
	lane_changed = "полоса уже перестроилась",
	no_gong = "Гонг ещё не появился",
}

local BOUNCE_WORDS = { "BOING!", "POP!", "BAM!", "ZOING!", "BOP!", "SPROING!" }

-- ── Типы ────────────────────────────────────────────────────────────────────

type RingSegment = {
	Frame: Frame,
	Lit: boolean,
	Bucket: number,
}

type Popup = {
	Gui: BillboardGui,
	Attachment: Attachment,
	Label: TextLabel,
	Stroke: UIStroke,
	Scale: UIScale,
	ScaleSpring: Spring.NumberSpring,
	Tilt: Spring.NumberSpring,
	Origin: Vector3,
	Velocity: Vector3,
	Born: number,
	Life: number,
}

type StatCard = {
	Stat: Types.StatName,
	Order: number,
	Root: Frame,
	Scale: UIScale,
	Pop: Spring.NumberSpring,
	Shake: Spring.VectorSpring,
	Level: TextLabel,
	Preview: TextLabel,
	BarFill: Frame,
	Button: TextButton,
	ButtonGradient: UIGradient,
	Cost: TextLabel,
	Message: TextLabel,
	MessageUntil: number,
	PendingUntil: number,
}

type GloveCard = {
	Id: string,
	Def: GloveConfig.GloveDef,
	Root: Frame,
	Scale: UIScale,
	Pop: Spring.NumberSpring,
	Shake: Spring.VectorSpring,
	Button: TextButton,
	ButtonGradient: UIGradient,
	Stroke: UIStroke,
	Message: TextLabel,
	MessageUntil: number,
	PendingUntil: number,
}

type Banner = {
	Root: Frame,
	Scale: UIScale,
	Gradient: UIGradient,
	Title: TextLabel,
	Subtitle: TextLabel,
	Rays: Frame,
	ScaleSpring: Spring.NumberSpring,
	Shake: Spring.VectorSpring,
	HideAt: number,
	Showing: boolean,
	BasePosition: UDim2,
}

export type HudSignals = {
	UiClick: Signal.Signal<>,
	PanelToggled: Signal.Signal<boolean>,
	Purchase: Signal.Signal<boolean, string>,
}

type HudFields = {
	Player: Player,
	Slingshot: ElasticSlingshotController.ElasticSlingshotController,
	Camera: ShoulderCamera.ShoulderCamera,
	Signals: HudSignals,
	Gui: ScreenGui,
	Root: Frame,
	RootScale: UIScale,
	ViewportKey: Vector2,

	Reticle: Frame,
	ReticleScale: UIScale,
	Dot: Frame,
	DotScale: UIScale,
	DotPop: Spring.NumberSpring,
	Segments: { RingSegment },
	TensionSpring: Spring.NumberSpring,
	TensionTarget: number,
	Jitter: Spring.VectorSpring,

	Speedo: Frame,
	SpeedoGradient: UIGradient,
	SpeedoStroke: UIStroke,
	SpeedoScale: UIScale,
	SpeedPop: Spring.NumberSpring,
	SpeedText: TextLabel,
	NeedlePivot: Frame,
	NeedleSpring: Spring.NumberSpring,
	Ticks: { Frame },
	LitTicks: number,
	Neon: boolean,
	NeonSpring: Spring.NumberSpring,
	NeonBucket: number,
	SupersonicLabel: TextLabel,
	SupersonicScale: UIScale,
	FlameHolder: Frame,
	Flames: { Frame },
	LastSpeedShown: number,

	Combo: Frame,
	ComboText: TextLabel,
	ComboGradient: UIGradient,
	ComboScale: UIScale,
	ComboPop: Spring.NumberSpring,
	ComboTilt: Spring.NumberSpring,
	ComboVisible: Spring.NumberSpring,
	ComboKick: Spring.VectorSpring,
	ComboShown: number,
	GongHint: TextLabel,
	GongHintText: string,

	CoinsText: TextLabel,
	CoinsScale: UIScale,
	CoinsPop: Spring.NumberSpring,
	CoinsShown: number,
	CoinsTarget: number,

	PopupFolder: Folder,
	PopupAnchor: Part,
	Popups: { Popup },
	LastSmashPoint: Vector3?,
	LastSmashAt: number,
	LastBounceWordAt: number,

	Banner: Banner,

	Panel: Frame,
	PanelScale: UIScale,
	PanelSpring: Spring.NumberSpring,
	PanelOpen: boolean,
	PanelDirty: boolean,
	PanelCoins: TextLabel,
	StatCards: { [Types.StatName]: StatCard },
	GloveCards: { [string]: GloveCard },
	GloveOrder: { string },
	RecordsText: TextLabel,
	OfflineText: TextLabel,
	MenuButton: TextButton,
	OwnedLocal: { [string]: boolean },
	Snapshot: Types.ProfileSnapshot?,

	Random: Random,
	Connections: { RBXScriptConnection },
	Started: boolean,
}

local HUD = {}
HUD.__index = HUD

export type StretchHUDController = typeof(setmetatable({} :: HudFields, HUD))

-- ── Помощники построения ───────────────────────────────────────────────────

local function addCorner(parent: GuiObject, radius: UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

local function addStroke(parent: GuiObject, thickness: number, color: Color3, mode: Enum.ApplyStrokeMode): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.ApplyStrokeMode = mode
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Вертикальный градиент сверху вниз
local function addGradient(parent: GuiObject, top: Color3, bottom: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

local function addScale(parent: GuiObject, value: number): UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = value
	scale.Parent = parent
	return scale
end

local function newFrame(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function newLabel(
	name: string,
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	color: Color3,
	inkThickness: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.AnchorPoint = anchor
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = parent
	if inkThickness > 0 then
		addStroke(label, inkThickness, INK, Enum.ApplyStrokeMode.Contextual)
	end
	return label
end

local function newButton(
	name: string,
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	top: Color3,
	bottom: Color3
): (TextButton, UIGradient)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.AnchorPoint = anchor
	button.BackgroundColor3 = WHITE
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = FONT
	button.Text = text
	button.TextColor3 = WHITE
	button.TextScaled = true
	button.Parent = parent
	addCorner(button, UDim.new(0, 14))
	addStroke(button, 3, INK, Enum.ApplyStrokeMode.Border)
	addStroke(button, 2.5, INK, Enum.ApplyStrokeMode.Contextual)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = button
	return button, addGradient(button, top, bottom)
end

local function setGradient(gradient: UIGradient, top: Color3, bottom: Color3)
	gradient.Color = ColorSequence.new(top, bottom)
end

local function formatNumber(value: number): string
	local integer = math.floor(math.max(value, 0) + 0.5)
	local text = tostring(integer)
	local result = ""
	while #text > 3 do
		result = " " .. string.sub(text, -3) .. result
		text = string.sub(text, 1, -4)
	end
	return text .. result
end

local function tensionColor(tension: number): Color3
	if tension < 0.6 then
		return TENSION_LOW:Lerp(TENSION_MID, tension / 0.6)
	end
	return TENSION_MID:Lerp(TENSION_HIGH, math.clamp((tension - 0.6) / 0.4, 0, 1))
end

local function gaugeColor(fraction: number): Color3
	if fraction < 0.5 then
		return TENSION_LOW:Lerp(TENSION_MID, fraction / 0.5)
	end
	return TENSION_MID:Lerp(TENSION_HIGH, (fraction - 0.5) / 0.5)
end

local function comboColors(combo: number): (Color3, Color3)
	if combo >= 10 then
		return NEON_PINK, Color3.fromRGB(150, 60, 255)
	elseif combo >= 5 then
		return GOLD, GOLD_DARK
	end
	return Color3.fromRGB(150, 245, 255), Color3.fromRGB(60, 150, 255)
end

local function attributeNumber(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function currentStats(player: Player): Types.PhysicalStats
	return {
		Elasticity = attributeNumber(player, "Stat_Elasticity"),
		SpringPower = attributeNumber(player, "Stat_SpringPower"),
		SmashMass = attributeNumber(player, "Stat_SmashMass"),
	}
end

local function statLevel(stats: Types.PhysicalStats, stat: Types.StatName): number
	if stat == "Elasticity" then
		return stats.Elasticity
	elseif stat == "SpringPower" then
		return stats.SpringPower
	end
	return stats.SmashMass
end

local function withStat(stats: Types.PhysicalStats, stat: Types.StatName, level: number): Types.PhysicalStats
	return {
		Elasticity = if stat == "Elasticity" then level else stats.Elasticity,
		SpringPower = if stat == "SpringPower" then level else stats.SpringPower,
		SmashMass = if stat == "SmashMass" then level else stats.SmashMass,
	}
end

-- Превью роста параметров: сравниваем Derive текущего и следующего уровня
local function statPreview(stat: Types.StatName, stats: Types.PhysicalStats, gloveId: string?): string
	local level = statLevel(stats, stat)
	local now = StretchPhysics.Derive(stats, gloveId)
	if level >= PhysicsConfig.StatUpgrade.MaxLevel then
		if stat == "Elasticity" then
			return string.format("Натяжение %.1f · Дальность %d\nМАКСИМУМ", now.MaxStretch, math.floor(now.GrabRange + 0.5))
		elseif stat == "SpringPower" then
			return string.format("Запуск %d st/s · Упругость %.3f\nМАКСИМУМ", math.floor(StretchPhysics.MaxLaunchSpeed(now) + 0.5), now.Restitution)
		end
		return string.format("Ударная масса %.2f\nМАКСИМУМ", now.ImpactMass)
	end
	local nextParams = StretchPhysics.Derive(withStat(stats, stat, level + 1), gloveId)
	if stat == "Elasticity" then
		return string.format(
			"Натяжение %.1f → %.1f\nДальность %d → %d",
			now.MaxStretch,
			nextParams.MaxStretch,
			math.floor(now.GrabRange + 0.5),
			math.floor(nextParams.GrabRange + 0.5)
		)
	elseif stat == "SpringPower" then
		return string.format(
			"Запуск %d → %d st/s\nУпругость %.3f → %.3f",
			math.floor(StretchPhysics.MaxLaunchSpeed(now) + 0.5),
			math.floor(StretchPhysics.MaxLaunchSpeed(nextParams) + 0.5),
			now.Restitution,
			nextParams.Restitution
		)
	end
	local gain = (nextParams.ImpactMass / now.ImpactMass - 1) * 100
	return string.format("Ударная масса %.2f → %.2f\nЭнергия удара +%.1f%%", now.ImpactMass, nextParams.ImpactMass, gain)
end

-- ── Конструктор ────────────────────────────────────────────────────────────

function HUD.new(
	slingshot: ElasticSlingshotController.ElasticSlingshotController,
	camera: ShoulderCamera.ShoulderCamera
): StretchHUDController
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "StretchPopHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5

	-- Root масштабируется под высоту экрана; размер 1/scale, чтобы после UIScale ровно покрыть экран
	local root = newFrame("Root", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 1)
	local rootScale = addScale(root, 1)

	local popupFolder = Instance.new("Folder")
	popupFolder.Name = "StretchPopPopups"
	popupFolder.Parent = playerGui
	local popupAnchor = Instance.new("Part")
	popupAnchor.Name = "StretchPopPopupAnchor"
	popupAnchor.Anchored = true
	popupAnchor.CanCollide = false
	popupAnchor.CanQuery = false
	popupAnchor.CanTouch = false
	popupAnchor.Transparency = 1
	popupAnchor.Size = Vector3.one * 0.2
	popupAnchor.CFrame = CFrame.new(0, -5000, 0)
	popupAnchor.Parent = workspace

	local fields = {
		Player = player,
		Slingshot = slingshot,
		Camera = camera,
		Signals = {
			UiClick = Signal.new(),
			PanelToggled = Signal.new(),
			Purchase = Signal.new(),
		},
		Gui = gui,
		Root = root,
		RootScale = rootScale,
		ViewportKey = Vector2.zero,
		TensionSpring = Spring.Number.new(0, 9, 0.85),
		TensionTarget = 0,
		Jitter = Spring.Vector.new(Vector3.zero, 18, 0.35),
		DotPop = Spring.Number.new(0, 5, 0.3),
		SpeedPop = Spring.Number.new(0, 4.5, 0.3),
		NeedleSpring = Spring.Number.new(180, 3, 0.36),
		LitTicks = -1,
		Neon = false,
		NeonSpring = Spring.Number.new(0, 3.5, 0.7),
		NeonBucket = -1,
		LastSpeedShown = -1,
		ComboPop = Spring.Number.new(0, 5, 0.28),
		ComboTilt = Spring.Number.new(0, 4, 0.25),
		ComboVisible = Spring.Number.new(0, 4, 0.6),
		ComboKick = Spring.Vector.new(Vector3.zero, 6, 0.3),
		ComboShown = 0,
		GongHintText = "",
		CoinsPop = Spring.Number.new(0, 5, 0.3),
		CoinsShown = attributeNumber(player, "Coins"),
		CoinsTarget = attributeNumber(player, "Coins"),
		PopupFolder = popupFolder,
		PopupAnchor = popupAnchor,
		Popups = {},
		LastSmashPoint = nil,
		LastSmashAt = -math.huge,
		LastBounceWordAt = -math.huge,
		PanelSpring = Spring.Number.new(0, 3.2, 0.55),
		PanelOpen = false,
		PanelDirty = true,
		StatCards = {},
		GloveCards = {},
		GloveOrder = {},
		OwnedLocal = { [GloveConfig.DefaultGlove] = true },
		Snapshot = nil,
		Random = Random.new(),
		Connections = {},
		Started = false,
	}
	local self = setmetatable(fields :: any, HUD) :: StretchHUDController
	self:BuildReticle()
	self:BuildSpeedometer()
	self:BuildCombo()
	self:BuildCoins()
	self:BuildBanner()
	self:BuildPanel()
	self:BuildMenuButton()
	gui.Parent = playerGui
	return self
end

-- ── Прицел и кольцо натяжения ──────────────────────────────────────────────

function HUD.BuildReticle(self: StretchHUDController)
	local reticle = newFrame("Reticle", self.Root, UDim2.fromOffset(120, 120), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 1)
	self.Reticle = reticle
	self.ReticleScale = addScale(reticle, 1)
	local segments: { RingSegment } = {}
	for index = 0, RING_SEGMENTS - 1 do
		-- сегменты по часовой от 12 часов; длинная ось — по касательной к окружности
		local angle = -90 + index * 360 / RING_SEGMENTS
		local radians = math.rad(angle)
		local segment = newFrame(
			"Segment" .. index,
			reticle,
			UDim2.fromOffset(9, 4),
			UDim2.new(0.5, math.cos(radians) * RING_RADIUS, 0.5, math.sin(radians) * RING_RADIUS),
			Vector2.new(0.5, 0.5),
			INK,
			0.55
		)
		segment.Rotation = angle + 90
		addCorner(segment, UDim.new(0.5, 0))
		table.insert(segments, { Frame = segment, Lit = false, Bucket = -1 })
	end
	self.Segments = segments
	local dot = newFrame("Dot", reticle, UDim2.fromOffset(9, 9), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 0)
	addCorner(dot, UDim.new(0.5, 0))
	addStroke(dot, 2, INK, Enum.ApplyStrokeMode.Border)
	self.Dot = dot
	self.DotScale = addScale(dot, 1)
end

function HUD.UpdateReticle(self: StretchHUDController, dt: number, now: number)
	self.TensionSpring.Target = self.TensionTarget
	local tension = math.clamp(self.TensionSpring:Update(dt), 0, 1)
	local lit = math.floor(tension * RING_SEGMENTS + 0.5)
	local maxed = self.TensionTarget >= 0.995
	local color = if maxed and math.floor(now * 16) % 2 == 0 then WHITE else tensionColor(tension)
	local bucket = math.floor(tension * 24) + (if maxed then 100 + math.floor(now * 16) % 2 else 0)
	for index, segment in self.Segments do
		local shouldLight = index <= lit
		if segment.Lit ~= shouldLight or (shouldLight and segment.Bucket ~= bucket) then
			segment.Lit = shouldLight
			segment.Bucket = bucket
			segment.Frame.BackgroundColor3 = if shouldLight then color else INK
			segment.Frame.BackgroundTransparency = if shouldLight then 0 else 0.55
			segment.Frame.Size = if shouldLight then UDim2.fromOffset(11, 5) else UDim2.fromOffset(9, 4)
		end
	end
	-- На 100% натяжения кольцо мелко дрожит: пружина гоняется за случайной целью
	if maxed then
		local rng = self.Random
		self.Jitter.Target = Vector3.new(rng:NextNumber(-2.6, 2.6), rng:NextNumber(-2.6, 2.6), 0)
	else
		self.Jitter.Target = Vector3.zero
	end
	local jitter = self.Jitter:Update(dt)
	self.Reticle.Position = UDim2.new(0.5, jitter.X, 0.5, jitter.Y)
	self.ReticleScale.Scale = 1 + tension * 0.12 + (if maxed then 0.05 * math.sin(now * 32) else 0)

	local aimValid = self.Slingshot.Aim.Valid
	self.Dot.BackgroundColor3 = if aimValid then GREEN else WHITE
	self.DotScale.Scale = 1 + self.DotPop:Update(dt) + (if aimValid then 0.15 else 0)
	self.Reticle.Visible = not self.PanelOpen
end

-- ── Спидометр ───────────────────────────────────────────────────────────────

function HUD.BuildSpeedometer(self: StretchHUDController)
	local flameHolder = newFrame(
		"Flames",
		self.Root,
		UDim2.fromOffset(320, 110),
		UDim2.new(0.5, 0, 1, -166),
		Vector2.new(0.5, 1),
		WHITE,
		1
	)
	flameHolder.ZIndex = 1
	local flames: { Frame } = {}
	for index = 1, FLAME_COUNT do
		local flame = newFrame(
			"Flame" .. index,
			flameHolder,
			UDim2.fromOffset(30, 60),
			UDim2.new((index - 0.5) / FLAME_COUNT, 0, 1, 18),
			Vector2.new(0.5, 1),
			WHITE,
			0
		)
		flame.ZIndex = 1
		addCorner(flame, UDim.new(0.5, 0))
		local gradient = addGradient(flame, Color3.fromRGB(255, 255, 210), Color3.fromRGB(255, 70, 20))
		gradient.Transparency = NumberSequence.new(0.05, 0.35)
		table.insert(flames, flame)
	end
	flameHolder.Visible = false
	self.FlameHolder = flameHolder
	self.Flames = flames

	local speedo = newFrame("Speedometer", self.Root, UDim2.fromOffset(320, 170), UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1), WHITE, 0)
	speedo.ZIndex = 2
	addCorner(speedo, UDim.new(0, 26))
	self.SpeedoGradient = addGradient(speedo, SPEEDO_TOP, SPEEDO_BOTTOM)
	self.SpeedoStroke = addStroke(speedo, 4, WHITE, Enum.ApplyStrokeMode.Border)
	self.SpeedoScale = addScale(speedo, 1)
	self.Speedo = speedo

	local centerX, centerY = 160, 132
	local ticks: { Frame } = {}
	for index = 0, GAUGE_TICKS - 1 do
		local fraction = index / (GAUGE_TICKS - 1)
		local angle = 180 + 180 * fraction
		local radians = math.rad(angle)
		local tick = newFrame(
			"Tick" .. index,
			speedo,
			UDim2.fromOffset(if index % 5 == 0 then 18 else 12, 5),
			UDim2.fromOffset(centerX + math.cos(radians) * GAUGE_RADIUS, centerY + math.sin(radians) * GAUGE_RADIUS),
			Vector2.new(0.5, 0.5),
			gaugeColor(fraction),
			0.6
		)
		tick.Rotation = angle
		tick.ZIndex = 3
		addCorner(tick, UDim.new(0.5, 0))
		table.insert(ticks, tick)
	end
	self.Ticks = ticks

	-- Стрелка: квадратный «шарнир» в центре шкалы, внутри — стрелка от центра вправо; крутим шарнир
	local pivot = newFrame("NeedlePivot", speedo, UDim2.fromOffset(GAUGE_RADIUS * 2, GAUGE_RADIUS * 2), UDim2.fromOffset(centerX, centerY), Vector2.new(0.5, 0.5), WHITE, 1)
	pivot.Rotation = 180
	pivot.ZIndex = 4
	local needle = newFrame("Needle", pivot, UDim2.fromOffset(GAUGE_RADIUS - 10, 7), UDim2.fromScale(0.5, 0.5), Vector2.new(0, 0.5), Color3.fromRGB(255, 90, 90), 0)
	needle.ZIndex = 4
	addCorner(needle, UDim.new(0.5, 0))
	addStroke(needle, 2, INK, Enum.ApplyStrokeMode.Border)
	addGradient(needle, Color3.fromRGB(255, 160, 140), Color3.fromRGB(220, 40, 70))
	self.NeedlePivot = pivot
	local hub = newFrame("Hub", speedo, UDim2.fromOffset(22, 22), UDim2.fromOffset(centerX, centerY), Vector2.new(0.5, 0.5), WHITE, 0)
	hub.ZIndex = 5
	addCorner(hub, UDim.new(0.5, 0))
	addStroke(hub, 3, INK, Enum.ApplyStrokeMode.Border)

	local speedText = newLabel("Speed", speedo, "0", UDim2.fromOffset(150, 50), UDim2.new(0.5, 0, 1, -30), Vector2.new(0.5, 1), WHITE, 3.5)
	speedText.ZIndex = 6
	self.SpeedText = speedText
	local units = newLabel("Units", speedo, "STUDS/S", UDim2.fromOffset(110, 20), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1), Color3.fromRGB(200, 210, 255), 2)
	units.ZIndex = 6

	local supersonic = newLabel(
		"Supersonic",
		speedo,
		"SUPERSONIC!",
		UDim2.fromOffset(300, 44),
		UDim2.new(0.5, 0, 0, -12),
		Vector2.new(0.5, 1),
		NEON_YELLOW,
		4
	)
	supersonic.ZIndex = 7
	addGradient(supersonic, NEON_YELLOW, NEON_PINK)
	supersonic.Visible = false
	self.SupersonicLabel = supersonic
	self.SupersonicScale = addScale(supersonic, 0)
end

function HUD.UpdateSpeedometer(self: StretchHUDController, dt: number, now: number)
	local speed = self.Slingshot:GetSpeed()
	local fraction = math.clamp(speed / GAUGE_MAX_SPEED, 0, 1)

	self.NeedleSpring.Target = 180 + 180 * math.min(speed / GAUGE_MAX_SPEED, 1.04)
	self.NeedlePivot.Rotation = self.NeedleSpring:Update(dt)

	local lit = math.floor(fraction * (GAUGE_TICKS - 1) + 0.5) + (if speed > 1 then 1 else 0)
	if lit ~= self.LitTicks then
		self.LitTicks = lit
		for index, tick in self.Ticks do
			tick.BackgroundTransparency = if index <= lit then 0 else 0.6
		end
	end

	local shown = math.floor(speed + 0.5)
	if shown ~= self.LastSpeedShown then
		self.LastSpeedShown = shown
		self.SpeedText.Text = tostring(shown)
	end

	-- Сверхзвук с гистерезисом, чтобы режим не мигал на границе
	local threshold = PhysicsConfig.SupersonicSpeed
	if not self.Neon and speed >= threshold then
		self.Neon = true
		self.SpeedPop:Impulse(6)
		self.SupersonicScale.Scale = 0.2
	elseif self.Neon and speed < threshold - SUPERSONIC_OFF_MARGIN then
		self.Neon = false
	end
	self.NeonSpring.Target = if self.Neon then 1 else 0
	local neon = math.clamp(self.NeonSpring:Update(dt), 0, 1)
	local bucket = math.floor(neon * 40 + 0.5)
	if bucket ~= self.NeonBucket then
		self.NeonBucket = bucket
		local alpha = bucket / 40
		setGradient(self.SpeedoGradient, SPEEDO_TOP:Lerp(NEON_PINK, alpha), SPEEDO_BOTTOM:Lerp(Color3.fromRGB(20, 40, 120), alpha))
		self.SpeedoStroke.Color = WHITE:Lerp(NEON_CYAN, alpha)
		self.SpeedText.TextColor3 = WHITE:Lerp(NEON_YELLOW, alpha)
	end
	self.SpeedoStroke.Thickness = 4 + 3 * neon + (if neon > 0.5 then math.sin(now * 18) * 1.2 else 0)
	self.SpeedoScale.Scale = 1 + self.SpeedPop:Update(dt) * 0.8 + neon * 0.04

	self.SupersonicLabel.Visible = neon > 0.03
	if self.SupersonicLabel.Visible then
		local target = neon * (1 + 0.07 * math.sin(now * 12))
		self.SupersonicScale.Scale += (target - self.SupersonicScale.Scale) * math.min(dt * 14, 1)
		self.SupersonicLabel.Rotation = math.sin(now * 7) * 4
	end

	-- Мультяшное пламя: языки пламени дрожат шумом Перлина, высота растёт со скоростью
	self.FlameHolder.Visible = neon > 0.03
	if self.FlameHolder.Visible then
		local overdrive = math.clamp((speed - threshold) / 160, 0, 1)
		for index, flame in self.Flames do
			local flicker = math.noise(index * 1.7, now * 7.5)
			local height = (46 + 40 * overdrive + 26 * flicker) * neon
			flame.Size = UDim2.fromOffset(26 + 6 * math.noise(index, now * 5), math.max(height, 2))
			flame.Rotation = math.noise(index * 3.1, now * 4) * 14
		end
	end
end

-- ── Комбо и подсказка Гонга ────────────────────────────────────────────────

function HUD.BuildCombo(self: StretchHUDController)
	local combo = newFrame("Combo", self.Root, UDim2.fromOffset(200, 110), UDim2.new(0.5, 178, 1, -36), Vector2.new(0, 1), WHITE, 1)
	self.Combo = combo
	self.ComboScale = addScale(combo, 0.01)
	local text = newLabel("Count", combo, "x0", UDim2.new(1, 0, 0.72, 0), UDim2.fromScale(0, 0), Vector2.zero, WHITE, 5)
	text.TextXAlignment = Enum.TextXAlignment.Left
	self.ComboText = text
	self.ComboGradient = addGradient(text, comboColors(1))
	local caption = newLabel("Caption", combo, "COMBO", UDim2.new(0.7, 0, 0.3, 0), UDim2.fromScale(0, 0.7), Vector2.zero, WHITE, 3)
	caption.TextXAlignment = Enum.TextXAlignment.Left

	local hint = newLabel("GongHint", self.Root, "", UDim2.fromOffset(240, 46), UDim2.new(0.5, -178, 1, -40), Vector2.new(1, 1), WHITE, 3)
	hint.RichText = true
	hint.TextXAlignment = Enum.TextXAlignment.Right
	self.GongHint = hint
end

function HUD.UpdateCombo(self: StretchHUDController, dt: number)
	local combo = self.Slingshot:GetCombo()
	if combo ~= self.ComboShown then
		if combo > self.ComboShown then
			self.ComboPop:Impulse(7 + math.min(combo, 20) * 0.35)
			self.ComboTilt:Impulse((if self.Random:NextNumber() < 0.5 then -1 else 1) * 90)
			self.ComboKick:Impulse(Vector3.new(0, -400, 0))
		end
		self.ComboShown = combo
		if combo > 0 then
			self.ComboText.Text = "x" .. combo
			local top, bottom = comboColors(combo)
			setGradient(self.ComboGradient, top, bottom)
		end
	end
	self.ComboVisible.Target = if combo > 0 then 1 else 0
	local visible = math.clamp(self.ComboVisible:Update(dt), 0, 1.3)
	local pop = self.ComboPop:Update(dt)
	self.ComboScale.Scale = math.max(visible * (1 + pop), 0.001)
	self.Combo.Rotation = self.ComboTilt:Update(dt) * 4
	local kick = self.ComboKick:Update(dt)
	self.Combo.Position = UDim2.new(0.5, 178 + kick.X, 1, -36 + kick.Y)
	self.Combo.Visible = visible > 0.01

	-- Подсказка порога Гонга с живой отметкой: что уже набрано
	local tier = attributeNumber(self.Player, "LocationTier")
	local needSpeed, needCombo = LevelConfig.GongRequirement(tier)
	local speedOk = self.Slingshot:GetSpeed() >= needSpeed
	local comboOk = combo >= needCombo
	local text = string.format(
		'ГОНГ: <font color="%s">≥%d st/s</font> · <font color="%s">x%d</font>',
		if speedOk then "#6EF078" else "#FFFFFF",
		math.floor(needSpeed),
		if comboOk then "#6EF078" else "#FFFFFF",
		needCombo
	)
	if text ~= self.GongHintText then
		self.GongHintText = text
		self.GongHint.Text = text
	end
end

-- ── Монеты ──────────────────────────────────────────────────────────────────

function HUD.BuildCoins(self: StretchHUDController)
	local coins = newFrame("Coins", self.Root, UDim2.fromOffset(240, 64), UDim2.new(1, -24, 0, 24), Vector2.new(1, 0), WHITE, 0)
	addCorner(coins, UDim.new(0, 20))
	addGradient(coins, Color3.fromRGB(70, 56, 160), Color3.fromRGB(36, 22, 96))
	addStroke(coins, 4, WHITE, Enum.ApplyStrokeMode.Border)
	self.CoinsScale = addScale(coins, 1)
	local icon = newFrame("Icon", coins, UDim2.fromOffset(44, 44), UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5), WHITE, 0)
	addCorner(icon, UDim.new(0.5, 0))
	addGradient(icon, GOLD, GOLD_DARK)
	addStroke(icon, 3, INK, Enum.ApplyStrokeMode.Border)
	newLabel("Glyph", icon, "$", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 2.5)
	local amount = newLabel("Amount", coins, formatNumber(self.CoinsShown), UDim2.new(1, -72, 0.72, 0), UDim2.new(0, 62, 0.5, 0), Vector2.new(0, 0.5), GOLD, 3.5)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	self.CoinsText = amount
end

function HUD.UpdateCoins(self: StretchHUDController, dt: number)
	local target = attributeNumber(self.Player, "Coins")
	if target > self.CoinsTarget then
		self.CoinsPop:Impulse(6)
	end
	self.CoinsTarget = target
	if math.abs(self.CoinsShown - target) > 0.5 then
		self.CoinsShown += (target - self.CoinsShown) * (1 - math.exp(-9 * dt))
	else
		self.CoinsShown = target
	end
	local text = formatNumber(self.CoinsShown)
	if self.CoinsText.Text ~= text then
		self.CoinsText.Text = text
		if self.PanelOpen then
			self.PanelCoins.Text = formatNumber(target)
		end
	end
	self.CoinsScale.Scale = 1 + self.CoinsPop:Update(dt)
end

-- ── 3D-цифры по параболе ───────────────────────────────────────────────────

function HUD.SpawnPopup(self: StretchHUDController, text: string, position: Vector3, top: Color3, bottom: Color3, pixelHeight: number)
	if #self.Popups >= MAX_POPUPS then
		local oldest = table.remove(self.Popups, 1)
		if oldest then
			oldest.Gui:Destroy()
			oldest.Attachment:Destroy()
		end
	end
	local rng = self.Random
	local attachment = Instance.new("Attachment")
	attachment.Name = "Popup"
	attachment.Parent = self.PopupAnchor
	attachment.WorldCFrame = CFrame.new(position)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Popup"
	gui.Adornee = attachment
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 900
	gui.Size = UDim2.fromOffset(pixelHeight * 4, pixelHeight * 1.5)
	gui.Parent = self.PopupFolder

	local label = newLabel("Text", gui, text, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 0)
	local stroke = addStroke(label, math.max(pixelHeight / 14, 2.5), INK, Enum.ApplyStrokeMode.Contextual)
	addGradient(label, top, bottom)
	local scale = addScale(label, 0.01)
	local scaleSpring = Spring.Number.new(0, 3.4, 0.38)
	scaleSpring.Target = 1
	local tilt = Spring.Number.new(rng:NextNumber(-16, 16), 3, 0.4)
	tilt.Target = 0

	table.insert(self.Popups, {
		Gui = gui,
		Attachment = attachment,
		Label = label,
		Stroke = stroke,
		Scale = scale,
		ScaleSpring = scaleSpring,
		Tilt = tilt,
		Origin = position,
		Velocity = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(24, 32), rng:NextNumber(-9, 9)),
		Born = os.clock(),
		Life = rng:NextNumber(1.05, 1.3),
	})
end

function HUD.UpdatePopups(self: StretchHUDController, dt: number, now: number)
	local index = 1
	while index <= #self.Popups do
		local popup = self.Popups[index]
		local age = now - popup.Born
		if age >= popup.Life then
			popup.Gui:Destroy()
			popup.Attachment:Destroy()
			table.remove(self.Popups, index)
		else
			-- p(t) = p0 + v0·t + ½·g·t²
			local position = popup.Origin + popup.Velocity * age + POPUP_GRAVITY * (0.5 * age * age)
			popup.Attachment.WorldCFrame = CFrame.new(position)
			popup.Scale.Scale = math.max(popup.ScaleSpring:Update(dt), 0.01)
			popup.Label.Rotation = popup.Tilt:Update(dt)
			local fadeStart = popup.Life * 0.65
			local fade = if age > fadeStart then (age - fadeStart) / (popup.Life - fadeStart) else 0
			popup.Label.TextTransparency = fade
			popup.Stroke.Transparency = fade
			index += 1
		end
	end
end

function HUD.PlayerHeadPosition(self: StretchHUDController): Vector3
	local character = self.Player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 4, 0)
	end
	local origin = self.Camera:GetAimRay()
	return origin
end

-- ── Баннер ──────────────────────────────────────────────────────────────────

function HUD.BuildBanner(self: StretchHUDController)
	local basePosition = UDim2.fromScale(0.5, 0.2)
	local root = newFrame("Banner", self.Root, UDim2.fromOffset(620, 140), basePosition, Vector2.new(0.5, 0.5), WHITE, 0)
	root.ZIndex = 20
	root.Visible = false
	addCorner(root, UDim.new(0, 30))
	local gradient = addGradient(root, GOLD, GOLD_DARK)
	addStroke(root, 6, WHITE, Enum.ApplyStrokeMode.Border)

	local rays = newFrame("Rays", root, UDim2.fromOffset(760, 760), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 1)
	rays.ZIndex = 19
	for index = 0, 11 do
		local ray = newFrame("Ray" .. index, rays, UDim2.fromOffset(760, 26), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 0.82)
		ray.Rotation = index * 15
		ray.ZIndex = 19
		addCorner(ray, UDim.new(0.5, 0))
	end

	local title = newLabel("Title", root, "REBIRTH!", UDim2.new(1, -40, 0.62, 0), UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0), WHITE, 6)
	title.ZIndex = 21
	addGradient(title, WHITE, Color3.fromRGB(255, 236, 160))
	local subtitle = newLabel("Subtitle", root, "", UDim2.new(1, -40, 0.3, 0), UDim2.new(0.5, 0, 1, -10), Vector2.new(0.5, 1), WHITE, 3.5)
	subtitle.ZIndex = 21

	self.Banner = {
		Root = root,
		Scale = addScale(root, 0.01),
		Gradient = gradient,
		Title = title,
		Subtitle = subtitle,
		Rays = rays,
		ScaleSpring = Spring.Number.new(0, 2.8, 0.42),
		Shake = Spring.Vector.new(Vector3.zero, 7, 0.22),
		HideAt = 0,
		Showing = false,
		BasePosition = basePosition,
	}
end

function HUD.ShowBanner(
	self: StretchHUDController,
	title: string,
	subtitle: string,
	top: Color3,
	bottom: Color3,
	duration: number,
	celebratory: boolean
)
	local banner = self.Banner
	banner.Title.Text = title
	banner.Subtitle.Text = subtitle
	setGradient(banner.Gradient, top, bottom)
	banner.Rays.Visible = celebratory
	banner.Root.Visible = true
	banner.Showing = true
	banner.HideAt = os.clock() + duration
	banner.ScaleSpring.Position = 0.05
	banner.ScaleSpring.Velocity = 0
	banner.ScaleSpring.Target = 1
	if not celebratory then
		banner.Shake:Impulse(Vector3.new(900, 0, 0)) -- «нет-нет»: тряска вбок
	end
end

function HUD.UpdateBanner(self: StretchHUDController, dt: number, now: number)
	local banner = self.Banner
	if not banner.Root.Visible then
		return
	end
	if banner.Showing and now >= banner.HideAt then
		banner.Showing = false
		banner.ScaleSpring.Target = 0
	end
	local scale = banner.ScaleSpring:Update(dt)
	banner.Scale.Scale = math.max(scale, 0.01)
	local shake = banner.Shake:Update(dt)
	banner.Root.Position = banner.BasePosition + UDim2.fromOffset(shake.X, shake.Y)
	banner.Rays.Rotation = (now * 25) % 360
	if not banner.Showing and scale < 0.03 then
		banner.Root.Visible = false
	end
end

-- ── Панель прокачки и витрина перчаток ─────────────────────────────────────

function HUD.BuildStatCard(self: StretchHUDController, parent: Instance, stat: Types.StatName, order: number): StatCard
	local info = STAT_INFO[stat]
	local card = newFrame(stat, parent, UDim2.fromOffset(430, 124), UDim2.fromOffset(0, (order - 1) * 136), Vector2.zero, WHITE, 0)
	addCorner(card, UDim.new(0, 20))
	addGradient(card, CARD_TOP, CARD_BOTTOM)
	addStroke(card, 3.5, INK, Enum.ApplyStrokeMode.Border)
	local scale = addScale(card, 1)

	local icon = newFrame("Icon", card, UDim2.fromOffset(64, 64), UDim2.fromOffset(14, 14), Vector2.zero, WHITE, 0)
	addCorner(icon, UDim.new(0.5, 0))
	addGradient(icon, info.Color:Lerp(WHITE, 0.35), info.Color)
	addStroke(icon, 3, INK, Enum.ApplyStrokeMode.Border)
	newLabel("Letter", icon, info.Letter, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 3)

	local title = newLabel("Title", card, info.Title, UDim2.fromOffset(200, 26), UDim2.fromOffset(90, 10), Vector2.zero, WHITE, 3)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local level = newLabel("Level", card, "Lv 0", UDim2.fromOffset(70, 26), UDim2.fromOffset(296, 10), Vector2.new(1, 0), GOLD, 3)
	level.TextXAlignment = Enum.TextXAlignment.Right
	local subtitle = newLabel("Subtitle", card, info.Subtitle, UDim2.fromOffset(200, 16), UDim2.fromOffset(16, 84), Vector2.zero, Color3.fromRGB(220, 214, 255), 2)
	subtitle.Size = UDim2.fromOffset(70, 16)
	local preview = newLabel("Preview", card, "", UDim2.fromOffset(206, 44), UDim2.fromOffset(90, 40), Vector2.zero, Color3.fromRGB(236, 232, 255), 2)
	preview.TextXAlignment = Enum.TextXAlignment.Left
	preview.TextYAlignment = Enum.TextYAlignment.Top

	local bar = newFrame("Bar", card, UDim2.fromOffset(206, 12), UDim2.fromOffset(90, 96), Vector2.zero, INK, 0.35)
	addCorner(bar, UDim.new(0.5, 0))
	local fill = newFrame("Fill", bar, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.zero, WHITE, 0)
	addCorner(fill, UDim.new(0.5, 0))
	addGradient(fill, info.Color:Lerp(WHITE, 0.4), info.Color)

	local buttonButton, buttonGradient = newButton(
		"Upgrade",
		card,
		"",
		UDim2.fromOffset(112, 84),
		UDim2.new(1, -12, 0.5, 0),
		Vector2.new(1, 0.5),
		GREEN,
		GREEN_DARK
	)
	local caption = newLabel("Caption", buttonButton, "UPGRADE", UDim2.fromScale(1, 0.34), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), WHITE, 2)
	caption.ZIndex = 2
	local cost = newLabel("Cost", buttonButton, "", UDim2.fromScale(1, 0.58), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1), GOLD, 2.5)
	cost.ZIndex = 2

	local message = newLabel("Message", card, "", UDim2.fromOffset(300, 22), UDim2.new(0, 90, 1, -2), Vector2.new(0, 1), WHITE, 2.5)
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.Visible = false

	local statCard: StatCard = {
		Stat = stat,
		Order = order,
		Root = card,
		Scale = scale,
		Pop = Spring.Number.new(0, 5, 0.3),
		Shake = Spring.Vector.new(Vector3.zero, 9, 0.2),
		Level = level,
		Preview = preview,
		BarFill = fill,
		Button = buttonButton,
		ButtonGradient = buttonGradient,
		Cost = cost,
		Message = message,
		MessageUntil = 0,
		PendingUntil = 0,
	}
	table.insert(
		self.Connections,
		buttonButton.Activated:Connect(function()
			self.Signals.UiClick:Fire()
			self:RequestUpgrade(statCard)
		end)
	)
	return statCard
end

function HUD.BuildGloveCard(self: StretchHUDController, parent: Instance, glove: GloveConfig.GloveDef, order: number): GloveCard
	local card = newFrame(glove.Id, parent, UDim2.fromOffset(196, 128), UDim2.fromOffset(0, 0), Vector2.zero, WHITE, 0)
	card.LayoutOrder = order
	addCorner(card, UDim.new(0, 20))
	addGradient(card, CARD_TOP, CARD_BOTTOM)
	local stroke = addStroke(card, 3.5, INK, Enum.ApplyStrokeMode.Border)
	local scale = addScale(card, 1)

	local swatch = newFrame("Swatch", card, UDim2.fromOffset(54, 54), UDim2.fromOffset(12, 12), Vector2.zero, WHITE, 0)
	addCorner(swatch, UDim.new(0.5, 0))
	addGradient(swatch, glove.Color:Lerp(WHITE, 0.45), glove.Color)
	addStroke(swatch, 3, INK, Enum.ApplyStrokeMode.Border)
	local shine = newFrame("Shine", swatch, UDim2.fromOffset(14, 10), UDim2.fromOffset(12, 10), Vector2.zero, WHITE, 0.25)
	addCorner(shine, UDim.new(0.5, 0))

	local name = newLabel("Name", card, glove.DisplayName, UDim2.fromOffset(112, 30), UDim2.fromOffset(74, 10), Vector2.zero, WHITE, 2.5)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local bonusText = if glove.ImpactMassBonus > 0 then string.format("+%d%% удара", math.floor(glove.ImpactMassBonus * 100 + 0.5)) else "Классика"
	local bonus = newLabel("Bonus", card, bonusText, UDim2.fromOffset(112, 20), UDim2.fromOffset(74, 42), Vector2.zero, glove.Accent, 2)
	bonus.TextXAlignment = Enum.TextXAlignment.Left

	local actionButton, actionGradient = newButton(
		"Action",
		card,
		"",
		UDim2.fromOffset(172, 40),
		UDim2.new(0.5, 0, 1, -10),
		Vector2.new(0.5, 1),
		GREEN,
		GREEN_DARK
	)
	local message = newLabel("Message", card, "", UDim2.fromOffset(172, 16), UDim2.new(0.5, 0, 0, 62), Vector2.new(0.5, 0), WHITE, 2)
	message.Visible = false

	local gloveCard: GloveCard = {
		Id = glove.Id,
		Def = glove,
		Root = card,
		Scale = scale,
		Pop = Spring.Number.new(0, 5, 0.3),
		Shake = Spring.Vector.new(Vector3.zero, 9, 0.2),
		Button = actionButton,
		ButtonGradient = actionGradient,
		Stroke = stroke,
		Message = message,
		MessageUntil = 0,
		PendingUntil = 0,
	}
	table.insert(
		self.Connections,
		actionButton.Activated:Connect(function()
			self.Signals.UiClick:Fire()
			self:RequestGlove(gloveCard)
		end)
	)
	return gloveCard
end

function HUD.BuildPanel(self: StretchHUDController)
	local panel = newFrame("UpgradePanel", self.Root, UDim2.fromOffset(900, 548), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), WHITE, 0)
	panel.ZIndex = 30
	panel.Visible = false
	addCorner(panel, UDim.new(0, 30))
	addGradient(panel, PANEL_TOP, PANEL_BOTTOM)
	addStroke(panel, 6, WHITE, Enum.ApplyStrokeMode.Border)
	self.Panel = panel
	self.PanelScale = addScale(panel, 0.01)

	local title = newLabel("Title", panel, "ПРОКАЧКА  •  ПЕРЧАТКИ", UDim2.fromOffset(520, 48), UDim2.fromOffset(28, 16), Vector2.zero, WHITE, 4.5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	addGradient(title, WHITE, Color3.fromRGB(255, 226, 150))

	local coinBox = newFrame("CoinBox", panel, UDim2.fromOffset(200, 46), UDim2.new(1, -84, 0, 18), Vector2.new(1, 0), INK, 0.4)
	addCorner(coinBox, UDim.new(0, 16))
	local coinIcon = newFrame("Icon", coinBox, UDim2.fromOffset(32, 32), UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5), WHITE, 0)
	addCorner(coinIcon, UDim.new(0.5, 0))
	addGradient(coinIcon, GOLD, GOLD_DARK)
	addStroke(coinIcon, 2.5, INK, Enum.ApplyStrokeMode.Border)
	local panelCoins = newLabel("Amount", coinBox, "0", UDim2.new(1, -54, 0.8, 0), UDim2.new(0, 48, 0.5, 0), Vector2.new(0, 0.5), GOLD, 3)
	panelCoins.TextXAlignment = Enum.TextXAlignment.Left
	self.PanelCoins = panelCoins

	local close = newButton("Close", panel, "X", UDim2.fromOffset(52, 52), UDim2.new(1, -16, 0, 14), Vector2.new(1, 0), RED, RED_DARK)
	table.insert(
		self.Connections,
		close.Activated:Connect(function()
			self.Signals.UiClick:Fire()
			self:SetPanelOpen(false)
		end)
	)

	local statsHeader = newLabel("StatsHeader", panel, "ФИЗИКА", UDim2.fromOffset(200, 26), UDim2.fromOffset(28, 74), Vector2.zero, Color3.fromRGB(255, 226, 150), 3)
	statsHeader.TextXAlignment = Enum.TextXAlignment.Left
	local statsColumn = newFrame("Stats", panel, UDim2.fromOffset(430, 400), UDim2.fromOffset(24, 104), Vector2.zero, WHITE, 1)
	for order, stat in STAT_ORDER do
		self.StatCards[stat] = self:BuildStatCard(statsColumn, stat, order)
	end

	local glovesHeader = newLabel("GlovesHeader", panel, "ПЕРЧАТКИ", UDim2.fromOffset(200, 26), UDim2.fromOffset(474, 74), Vector2.zero, Color3.fromRGB(255, 226, 150), 3)
	glovesHeader.TextXAlignment = Enum.TextXAlignment.Left
	local glovesScroll = Instance.new("ScrollingFrame")
	glovesScroll.Name = "Gloves"
	glovesScroll.Size = UDim2.fromOffset(410, 400)
	glovesScroll.Position = UDim2.fromOffset(470, 104)
	glovesScroll.BackgroundTransparency = 1
	glovesScroll.BorderSizePixel = 0
	glovesScroll.ScrollBarThickness = 8
	glovesScroll.ScrollBarImageColor3 = WHITE
	glovesScroll.CanvasSize = UDim2.fromOffset(0, 0)
	glovesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	glovesScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	glovesScroll.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(196, 128)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = glovesScroll
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.Parent = glovesScroll

	local gloves: { GloveConfig.GloveDef } = {}
	for _, glove in GloveConfig.Gloves do
		table.insert(gloves, glove)
	end
	table.sort(gloves, function(a: GloveConfig.GloveDef, b: GloveConfig.GloveDef): boolean
		if a.Price == b.Price then
			return a.Id < b.Id
		end
		return a.Price < b.Price
	end)
	for order, glove in gloves do
		self.GloveCards[glove.Id] = self:BuildGloveCard(glovesScroll, glove, order)
		table.insert(self.GloveOrder, glove.Id)
	end

	local records = newLabel("Records", panel, "", UDim2.new(1, -56, 0, 24), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1), Color3.fromRGB(220, 214, 255), 2.5)
	self.RecordsText = records
	local offline = newLabel("Offline", panel, "", UDim2.fromOffset(420, 20), UDim2.new(0, 560, 0, 70), Vector2.new(0, 0), Color3.fromRGB(255, 200, 120), 2)
	offline.TextXAlignment = Enum.TextXAlignment.Left
	self.OfflineText = offline
end

function HUD.BuildMenuButton(self: StretchHUDController)
	local button = newButton(
		"MenuButton",
		self.Root,
		"ПРОКАЧКА  [TAB]",
		UDim2.fromOffset(240, 62),
		UDim2.new(1, -24, 1, -24),
		Vector2.new(1, 1),
		Color3.fromRGB(180, 255, 120),
		Color3.fromRGB(40, 190, 90)
	)
	self.MenuButton = button
	table.insert(
		self.Connections,
		button.Activated:Connect(function()
			self.Signals.UiClick:Fire()
			self:SetPanelOpen(not self.PanelOpen)
		end)
	)
end

function HUD.IsOwned(self: StretchHUDController, gloveId: string): boolean
	if self.OwnedLocal[gloveId] then
		return true
	end
	local snapshot = self.Snapshot
	if snapshot then
		for _, owned in snapshot.OwnedGloves do
			if owned == gloveId then
				return true
			end
		end
	end
	return self.Player:GetAttribute("Glove") == gloveId
end

function HUD.CardMessage(self: StretchHUDController, label: TextLabel, text: string, positive: boolean): number
	label.Text = text
	label.TextColor3 = if positive then GREEN else RED
	label.Visible = true
	return os.clock() + 1.6
end

function HUD.RefreshPanel(self: StretchHUDController)
	self.PanelDirty = false
	local player = self.Player
	local coins = attributeNumber(player, "Coins")
	local stats = currentStats(player)
	local gloveAttribute = player:GetAttribute("Glove")
	local equipped = if typeof(gloveAttribute) == "string" then gloveAttribute else GloveConfig.DefaultGlove
	local now = os.clock()
	self.PanelCoins.Text = formatNumber(coins)

	for _, stat in STAT_ORDER do
		local card = self.StatCards[stat]
		local level = statLevel(stats, stat)
		local maxLevel = PhysicsConfig.StatUpgrade.MaxLevel
		card.Level.Text = "Lv " .. level
		card.Preview.Text = statPreview(stat, stats, equipped)
		card.BarFill.Size = UDim2.fromScale(math.clamp(level / maxLevel, 0, 1), 1)
		if level >= maxLevel then
			card.Cost.Text = "MAX"
			setGradient(card.ButtonGradient, GRAY, GRAY_DARK)
		else
			local cost = StretchPhysics.UpgradeCost(level)
			card.Cost.Text = if now < card.PendingUntil then "..." else formatNumber(cost)
			if coins >= cost then
				setGradient(card.ButtonGradient, GREEN, GREEN_DARK)
			else
				setGradient(card.ButtonGradient, GRAY, GRAY_DARK)
			end
		end
	end

	for _, gloveId in self.GloveOrder do
		local card = self.GloveCards[gloveId]
		local owned = self:IsOwned(gloveId)
		local isEquipped = equipped == gloveId
		if now < card.PendingUntil then
			card.Button.Text = "..."
		elseif isEquipped then
			card.Button.Text = "НАДЕТО"
			setGradient(card.ButtonGradient, GOLD, GOLD_DARK)
		elseif owned then
			card.Button.Text = "НАДЕТЬ"
			setGradient(card.ButtonGradient, Color3.fromRGB(120, 210, 255), Color3.fromRGB(40, 110, 230))
		else
			card.Button.Text = "$ " .. formatNumber(card.Def.Price)
			if coins >= card.Def.Price then
				setGradient(card.ButtonGradient, GREEN, GREEN_DARK)
			else
				setGradient(card.ButtonGradient, GRAY, GRAY_DARK)
			end
		end
		card.Stroke.Color = if isEquipped then GOLD else INK
		card.Stroke.Thickness = if isEquipped then 5 else 3.5
	end

	local snapshot = self.Snapshot
	if snapshot then
		local records = snapshot.Records
		self.RecordsText.Text = string.format(
			"Рекорд скорости %d  •  Комбо %d  •  Стен %s  •  Сундуков %s  •  Ребёртов %d",
			math.floor(records.TopSpeed + 0.5),
			records.LongestCombo,
			formatNumber(records.WallsSmashed),
			formatNumber(records.ChestsOpened),
			snapshot.TotalRebirths
		)
		self.OfflineText.Text = if snapshot.DataOffline then "Сохранения выключены: сессия Studio" else ""
	else
		self.RecordsText.Text = "Загружаем профиль…"
	end
end

function HUD.RequestUpgrade(self: StretchHUDController, card: StatCard)
	local now = os.clock()
	if now < card.PendingUntil then
		return
	end
	local stats = currentStats(self.Player)
	local level = statLevel(stats, card.Stat)
	if level >= PhysicsConfig.StatUpgrade.MaxLevel then
		card.MessageUntil = self:CardMessage(card.Message, REASON_TEXT.max_level, false)
		card.Shake:Impulse(Vector3.new(700, 0, 0))
		self.Signals.Purchase:Fire(false, "max_level")
		return
	end
	local cost = StretchPhysics.UpgradeCost(level)
	local coins = attributeNumber(self.Player, "Coins")
	if coins < cost then
		-- мгновенный отказ без запроса: клиент знает ту же формулу цены, что и сервер
		card.MessageUntil = self:CardMessage(card.Message, string.format("%s: нужно ещё %s", REASON_TEXT.not_enough_coins, formatNumber(cost - coins)), false)
		card.Shake:Impulse(Vector3.new(700, 0, 0))
		self.Signals.Purchase:Fire(false, "not_enough_coins")
		return
	end
	card.PendingUntil = now + REQUEST_TIMEOUT
	card.Cost.Text = "..."
	Net.UpgradeStat:FireServer(card.Stat)
end

function HUD.RequestGlove(self: StretchHUDController, card: GloveCard)
	local now = os.clock()
	if now < card.PendingUntil then
		return
	end
	local equipped = self.Player:GetAttribute("Glove")
	if equipped == card.Id then
		card.Pop:Impulse(4)
		return
	end
	local action: Types.GloveActionKind = if self:IsOwned(card.Id) then "Equip" else "Buy"
	if action == "Buy" then
		local coins = attributeNumber(self.Player, "Coins")
		if coins < card.Def.Price then
			card.MessageUntil = self:CardMessage(card.Message, string.format("Нужно ещё %s", formatNumber(card.Def.Price - coins)), false)
			card.Shake:Impulse(Vector3.new(700, 0, 0))
			self.Signals.Purchase:Fire(false, "not_enough_coins")
			return
		end
	end
	card.PendingUntil = now + REQUEST_TIMEOUT
	card.Button.Text = "..."
	Net.GloveAction:FireServer(action, card.Id)
end

function HUD.OnUpgradeResult(self: StretchHUDController, stat: string, accepted: boolean, reason: string, level: number)
	local card: StatCard? = nil
	if stat == "Elasticity" then
		card = self.StatCards.Elasticity
	elseif stat == "SpringPower" then
		card = self.StatCards.SpringPower
	elseif stat == "SmashMass" then
		card = self.StatCards.SmashMass
	end
	if card == nil then
		return
	end
	card.PendingUntil = 0
	if accepted then
		card.Pop:Impulse(9)
		card.MessageUntil = self:CardMessage(card.Message, string.format("Уровень %d!", level), true)
	else
		card.Shake:Impulse(Vector3.new(700, 0, 0))
		card.MessageUntil = self:CardMessage(card.Message, REASON_TEXT[reason] or reason, false)
	end
	self.Signals.Purchase:Fire(accepted, reason)
	self.PanelDirty = true
end

function HUD.OnGloveResult(self: StretchHUDController, action: string, gloveId: string, accepted: boolean, reason: string)
	local card = self.GloveCards[gloveId]
	if card == nil then
		return
	end
	card.PendingUntil = 0
	if accepted then
		if action == "Buy" then
			self.OwnedLocal[gloveId] = true
		end
		card.Pop:Impulse(9)
		card.MessageUntil = self:CardMessage(card.Message, if action == "Buy" then "Куплено!" else "Надето!", true)
	else
		card.Shake:Impulse(Vector3.new(700, 0, 0))
		card.MessageUntil = self:CardMessage(card.Message, REASON_TEXT[reason] or reason, false)
	end
	self.Signals.Purchase:Fire(accepted, reason)
	self.PanelDirty = true
end

function HUD.SetPanelOpen(self: StretchHUDController, open: boolean)
	if self.PanelOpen == open then
		return
	end
	self.PanelOpen = open
	self.Camera:SetMouseFree(open)
	self.PanelSpring.Target = if open then 1 else 0
	self.MenuButton.Text = if open then "ЗАКРЫТЬ  [TAB]" else "ПРОКАЧКА  [TAB]"
	if open then
		self.Panel.Visible = true
		self.PanelSpring.Position = math.min(self.PanelSpring.Position, 0.35)
		self:RefreshPanel()
		Net.ProfileSync:FireServer()
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.StatCards.Elasticity.Button
		end
	elseif GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(self.Panel) then
		GuiService.SelectedObject = nil
	end
	self.Signals.PanelToggled:Fire(open)
end

function HUD.UpdatePanel(self: StretchHUDController, dt: number, now: number)
	if not self.Panel.Visible then
		return
	end
	local value = self.PanelSpring:Update(dt)
	self.PanelScale.Scale = math.max(value, 0.01)
	if not self.PanelOpen and value < 0.04 then
		self.Panel.Visible = false
		return
	end
	local pendingExpired = false
	for _, stat in STAT_ORDER do
		local card = self.StatCards[stat]
		card.Scale.Scale = 1 + card.Pop:Update(dt) * 0.7
		local shake = card.Shake:Update(dt)
		card.Root.Position = UDim2.fromOffset(shake.X, (card.Order - 1) * 136)
		if card.Message.Visible and now > card.MessageUntil then
			card.Message.Visible = false
		end
		if card.PendingUntil > 0 and now > card.PendingUntil then
			card.PendingUntil = 0
			card.MessageUntil = self:CardMessage(card.Message, REASON_TEXT.timeout, false)
			pendingExpired = true
		end
	end
	for _, gloveId in self.GloveOrder do
		local card = self.GloveCards[gloveId]
		card.Scale.Scale = 1 + card.Pop:Update(dt) * 0.7
		local shake = card.Shake:Update(dt)
		card.Button.Position = UDim2.new(0.5, shake.X, 1, -10)
		if card.Message.Visible and now > card.MessageUntil then
			card.Message.Visible = false
		end
		if card.PendingUntil > 0 and now > card.PendingUntil then
			card.PendingUntil = 0
			card.MessageUntil = self:CardMessage(card.Message, REASON_TEXT.timeout, false)
			pendingExpired = true
		end
	end
	if self.PanelDirty or pendingExpired then
		self:RefreshPanel()
	end
end

-- ── Сетевые и игровые события ──────────────────────────────────────────────

function HUD.OnGongResult(
	self: StretchHUDController,
	accepted: boolean,
	reason: string,
	needSpeed: number,
	needCombo: number,
	speed: number,
	combo: number
)
	if accepted then
		return -- праздничный баннер покажет RebirthWave со сведениями о новом тире
	end
	local parts: { string } = {}
	local speedGap = math.ceil(needSpeed - speed)
	local comboGap = needCombo - combo
	if speedGap > 0 then
		table.insert(parts, string.format("+%d скорости (%d/%d)", speedGap, math.floor(speed), math.floor(needSpeed)))
	end
	if comboGap > 0 then
		table.insert(parts, string.format("+%d комбо (%d/%d)", comboGap, combo, needCombo))
	end
	local subtitle = if #parts > 0 then "Не хватило: " .. table.concat(parts, "  •  ") else "Гонг: " .. (REASON_TEXT[reason] or reason)
	self:ShowBanner("ЕЩЁ ЧУТЬ-ЧУТЬ!", subtitle, Color3.fromRGB(255, 150, 110), RED_DARK, 2.6, false)
end

function HUD.OnRebirthWave(self: StretchHUDController, info: Types.RebirthWaveInfo)
	if info.OwnerUserId ~= self.Player.UserId then
		return
	end
	local theme = LevelConfig.GetTheme(info.Tier)
	local subtitle = string.format(
		"%s → %s  •  ЛУТ x%d",
		LevelConfig.TierName(info.Tier - 1),
		LevelConfig.TierName(info.Tier),
		math.floor(LevelConfig.LootMultiplier(info.Tier) + 0.5)
	)
	self:ShowBanner("REBIRTH!", subtitle, theme.Wave:Lerp(WHITE, 0.25), theme.Wave:Lerp(INK, 0.35), 3.4, true)
end

function HUD.OnSmashed(self: StretchHUDController, kind: string, speed: number, point: Vector3)
	self.LastSmashPoint = point
	self.LastSmashAt = os.clock()
	if kind == "Chest" then
		self:SpawnPopup(string.format("%d!", math.floor(speed + 0.5)), point, GOLD, GOLD_DARK, 50)
	else
		self:SpawnPopup(string.format("%d!", math.floor(speed + 0.5)), point, WHITE, Color3.fromRGB(255, 150, 60), 48)
	end
end

function HUD.OnLootGained(self: StretchHUDController, loot: number)
	local lastPoint = self.LastSmashPoint
	local point = if lastPoint and os.clock() - self.LastSmashAt < 1.5 then lastPoint + Vector3.new(0, 3, 0) else self:PlayerHeadPosition()
	self:SpawnPopup("+" .. formatNumber(loot), point, GOLD, GOLD_DARK, 58)
end

function HUD.OnBounced(self: StretchHUDController, _combo: number, _speed: number, point: Vector3)
	local now = os.clock()
	if now - self.LastBounceWordAt < 0.18 then
		return
	end
	self.LastBounceWordAt = now
	local word = BOUNCE_WORDS[self.Random:NextInteger(1, #BOUNCE_WORDS)]
	self:SpawnPopup(word, point, Color3.fromRGB(170, 255, 255), Color3.fromRGB(60, 160, 255), 36)
end

-- ── Кадр ────────────────────────────────────────────────────────────────────

function HUD.UpdateScale(self: StretchHUDController)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local viewport = camera.ViewportSize
	if viewport == self.ViewportKey or viewport.Y < 1 then
		return
	end
	self.ViewportKey = viewport
	local scale = math.clamp(viewport.Y / REFERENCE_HEIGHT, 0.6, 1.4)
	self.RootScale.Scale = scale
	self.Root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

function HUD.OnRenderStep(self: StretchHUDController, dt: number)
	local now = os.clock()
	local step = math.min(dt, 0.1)
	self:UpdateScale()
	self:UpdateReticle(step, now)
	self:UpdateSpeedometer(step, now)
	self:UpdateCombo(step)
	self:UpdateCoins(step)
	self:UpdatePopups(step, now)
	self:UpdateBanner(step, now)
	self:UpdatePanel(step, now)
	-- свой прицел вместо системного курсора, пока мышь захвачена камерой
	local showCursor = self.Camera:IsMouseFree() or GuiService.MenuIsOpen
	if UserInputService.MouseIconEnabled ~= showCursor then
		UserInputService.MouseIconEnabled = showCursor
	end
end

function HUD.Start(self: StretchHUDController)
	if self.Started then
		return
	end
	self.Started = true
	local signals = self.Slingshot.Signals

	table.insert(
		self.Connections,
		signals.TensionChanged:Connect(function(tension: number)
			self.TensionTarget = tension
		end) :: any
	)
	table.insert(
		self.Connections,
		signals.HandFired:Connect(function(_side: Types.HandSide)
			self.DotPop:Impulse(6)
		end) :: any
	)
	table.insert(
		self.Connections,
		signals.Launched:Connect(function(_speed: number, _velocity: Vector3)
			self.SpeedPop:Impulse(5)
			self.TensionTarget = 0
		end) :: any
	)
	table.insert(
		self.Connections,
		signals.Bounced:Connect(function(combo: number, speed: number, point: Vector3)
			self:OnBounced(combo, speed, point)
		end) :: any
	)
	table.insert(
		self.Connections,
		signals.Smashed:Connect(function(kind: string, speed: number, point: Vector3)
			self:OnSmashed(kind, speed, point)
		end) :: any
	)
	table.insert(
		self.Connections,
		signals.LootGained:Connect(function(loot: number)
			self:OnLootGained(loot)
		end) :: any
	)

	table.insert(
		self.Connections,
		Net.GongResult.OnClientEvent:Connect(function(accepted: boolean, reason: string, needSpeed: number, needCombo: number, speed: number, combo: number)
			self:OnGongResult(accepted, reason, needSpeed, needCombo, speed, combo)
		end)
	)
	table.insert(
		self.Connections,
		Net.RebirthWave.OnClientEvent:Connect(function(info: Types.RebirthWaveInfo)
			self:OnRebirthWave(info)
		end)
	)
	table.insert(
		self.Connections,
		Net.UpgradeStat.OnClientEvent:Connect(function(stat: string, accepted: boolean, reason: string, level: number, _coins: number)
			self:OnUpgradeResult(stat, accepted, reason, level)
		end)
	)
	table.insert(
		self.Connections,
		Net.GloveAction.OnClientEvent:Connect(function(action: string, gloveId: string, accepted: boolean, reason: string)
			self:OnGloveResult(action, gloveId, accepted, reason)
		end)
	)
	table.insert(
		self.Connections,
		Net.ProfileSync.OnClientEvent:Connect(function(snapshot: Types.ProfileSnapshot)
			self.Snapshot = snapshot
			for _, gloveId in snapshot.OwnedGloves do
				self.OwnedLocal[gloveId] = true
			end
			self.PanelDirty = true
		end)
	)
	table.insert(
		self.Connections,
		self.Player.AttributeChanged:Connect(function(attribute: string)
			if attribute == "Coins" or attribute == "Glove" or string.sub(attribute, 1, 5) == "Stat_" then
				self.PanelDirty = true
			end
		end)
	)

	ContextActionService:BindActionAtPriority(
		ACTION_TOGGLE,
		function(_: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				self:SetPanelOpen(not self.PanelOpen)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.Tab,
		Enum.KeyCode.LeftAlt,
		Enum.KeyCode.RightAlt,
		Enum.KeyCode.ButtonY
	)

	table.insert(
		self.Connections,
		RunService.RenderStepped:Connect(function(dt: number)
			self:OnRenderStep(dt)
		end)
	)
	Net.ProfileSync:FireServer()
end

function HUD.Destroy(self: StretchHUDController)
	ContextActionService:UnbindAction(ACTION_TOGGLE)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, popup in self.Popups do
		popup.Gui:Destroy()
		popup.Attachment:Destroy()
	end
	table.clear(self.Popups)
	if self.PanelOpen then
		self.Camera:SetMouseFree(false)
	end
	UserInputService.MouseIconEnabled = true
	self.Gui:Destroy()
	self.PopupFolder:Destroy()
	self.PopupAnchor:Destroy()
	self.Started = false
end

return HUD
