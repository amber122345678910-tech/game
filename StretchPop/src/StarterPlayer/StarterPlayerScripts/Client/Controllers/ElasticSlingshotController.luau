--!strict
-- STRETCH-POP · ElasticSlingshotController (клиент)
--
-- Управление
--   ЛКМ / ПКМ (геймпад L2 / R2) — выстрелить левой / правой рукой в точку под прицелом (Workspace:Raycast + аим-ассист).
--   Зажато на земле  → РОГАТКА: персонаж оттягивается назад от якорей, энергия E = Σ½·k·x² (закон Гука),
--                      на экране — 3D-дуга предпросмотра. Отпустил → v = √(2E/m) вдоль равнодействующей резинок.
--   Зажато в воздухе → БАНДЖИ: резинка укорачивается и тянет силой F = k·x (только натяжение), отпустил — летишь по инерции.
--   ПРОБЕЛ в полёте  → ПРУЖИННЫЙ ШАР: отскоки с сохранением импульса (e из Spring Power), каждый отскок = +1 комбо.
--   Удар о разрушаемое: E = ½·m·v² ≥ прочности → предсказанное пробитие без потери скорости, сервер подтверждает.
--
-- Архитектура кадра (RunService:BindToRenderStep, до камеры):
--   прицел → фиксированные подшаги физики 1/120 с (аккумулятор) → интерполяция prev→curr по alpha →
--   запись CFrame корня → руки (кривые Безье на Beam) → шар → дуга траектории → сигналы для HUD/аудио.
-- Физика тела в полёте — собственная: Spherecast-sweep (без туннелирования на 600 studs/s),
-- Humanoid в состоянии Physics, на земле управление возвращается Humanoid'у.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local GloveConfig = require(Shared.Config.GloveConfig)
local Bezier = require(Shared.Math.Bezier)
local Spring = require(Shared.Math.Spring)
local StretchPhysics = require(Shared.Physics.StretchPhysics)
local Signal = require(Shared.Util.Signal)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local KineticVFX = require(Client.Effects.KineticVFX)
local ShoulderCamera = require(Client.Controllers.ShoulderCameraController)

local Tags = PhysicsConfig.Tags

local RENDER_STEP_NAME = "StretchPop_Slingshot"
local ACTION_LEFT = "StretchPop_LeftArm"
local ACTION_RIGHT = "StretchPop_RightArm"
local ACTION_BALL = "StretchPop_Ball"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value

local TRAJECTORY_SEGMENTS = 28
local SMASH_MARKERS = 4
local PREDICTION_TIMEOUT = 3
local CHARGE_MAX_GROUND_SPEED = 30
local ANCHOR_BREAK_FACTOR = 1.7
local TELEPORT_DRIFT_MIN = 30
local GONG_CLIENT_COOLDOWN = 1.2
-- Скрытые детали риг-модели уводим далеко вниз: Highlight-обводка не должна рисовать невидимое
local HIDDEN_CFRAME = CFrame.new(0, -5000, 0)

local OUTLINE_COLOR = Color3.fromRGB(34, 22, 46)
local STRETCH_TINT = Color3.fromRGB(255, 236, 242)
local WHITE = Color3.new(1, 1, 1)
local AIM_VALID_COLOR = Color3.fromRGB(110, 255, 150)
local MARKER_COLORS: { [string]: Color3 } = {
	Solid = Color3.fromRGB(255, 255, 255),
	Block = Color3.fromRGB(255, 150, 60),
	Gong = Color3.fromRGB(255, 214, 64),
}

local HAND_SIDES: { Types.HandSide } = { "Left", "Right" }
local ARM_PART_NAMES: { [Types.HandSide]: { string } } = {
	Left = { "LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm" },
	Right = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" },
}

type HandPhase = "Idle" | "Flying" | "Attached" | "Retracting"
type ControllerState = "Walk" | "Charge" | "Air"
type ContactResult = "Pass" | "Bounce" | "Slide" | "Land"

type ArmRig = {
	Shoulder: Attachment,
	Middle: Attachment,
	Hand: Attachment,
	MainA: Beam,
	MainB: Beam,
	OutlineA: Beam,
	OutlineB: Beam,
	Glove: Part,
	Cuff: Part,
	Visible: boolean,
	LastTint: number,
}

type Hand = {
	Side: Types.HandSide,
	Sign: number,
	Phase: HandPhase,
	Held: boolean,
	AnchorPart: BasePart?,
	AnchorLocal: Vector3,
	AnchorWorld: Vector3,
	AnchorNormal: Vector3,
	Position: Vector3,
	RestLength: number,
	Missed: boolean,
	MissTarget: Vector3,
	Wobble: Spring.VectorSpring,
	Rig: ArmRig,
}

type AimInfo = {
	Valid: boolean,
	Point: Vector3,
	Normal: Vector3,
	Part: BasePart?,
}

type Prediction = {
	Restore: () -> (),
	ExpiresAt: number,
}

type PeerHand = {
	Active: boolean,
	Point: Vector3,
	Rig: ArmRig,
}

type PeerState = {
	Player: Player,
	Hands: { [Types.HandSide]: PeerHand },
	Ball: boolean,
	BallPart: Part,
	BodyHidden: boolean,
}

type Knot = {
	P: Vector3,
	V: Vector3,
	T: number,
	BreakAfter: boolean,
}

type PathEnd = {
	Position: Vector3,
	Normal: Vector3,
	Kind: string,
}

export type Signals = {
	StateChanged: Signal.Signal<string>,
	HandFired: Signal.Signal<Types.HandSide>,
	HandAttached: Signal.Signal<Types.HandSide>,
	HandReleased: Signal.Signal<Types.HandSide>,
	TensionChanged: Signal.Signal<number>,
	Launched: Signal.Signal<number, Vector3>,
	Bounced: Signal.Signal<number, number, Vector3>,
	Smashed: Signal.Signal<string, number, Vector3>,
	Splat: Signal.Signal<number>,
	GongStruck: Signal.Signal<number, number>,
	LootGained: Signal.Signal<number>,
	BallChanged: Signal.Signal<boolean>,
}

type ControllerFields = {
	Player: Player,
	Camera: ShoulderCamera.ShoulderCamera,
	Signals: Signals,

	Character: Model?,
	Humanoid: Humanoid?,
	Root: BasePart?,
	ShoulderOffsets: { [Types.HandSide]: Vector3 },
	RootHeight: number,
	ArmParts: { [Types.HandSide]: { BasePart } },
	ArmHidden: { [Types.HandSide]: boolean },
	BodyParts: { BasePart },
	BodyDecals: { Decal },
	BodyDirty: boolean,
	BodyHidden: boolean,
	FallTrack: AnimationTrack?,

	State: ControllerState,
	Hands: { [Types.HandSide]: Hand },
	Params: StretchPhysics.StretchParams,
	GloveColor: Color3,
	GloveMaterial: Enum.Material,

	SimPosition: Vector3,
	SimVelocity: Vector3,
	SimRotation: CFrame,
	PrevPosition: Vector3,
	PrevRotation: CFrame,
	RenderCFrame: CFrame,
	Accumulator: number,
	LastWritten: Vector3,
	LaunchGraceUntil: number,

	BallHeld: boolean,
	BallSink: boolean,
	BallActive: boolean,
	BallAxis: Vector3,
	BallSquash: Spring.NumberSpring,

	Tension: number,
	LastTensionSent: number,
	Combo: number,
	LandedAt: number?,
	GongCooldownUntil: number,
	Predictions: { [string]: Prediction },

	Aim: AimInfo,
	GrabPoints: { [BasePart]: boolean },
	CastParams: RaycastParams,
	AimParams: RaycastParams,
	PreviewParams: RaycastParams,
	PreviewTimer: number,

	RigModel: Model,
	PeerModel: Model,
	MarkerFolder: Folder,
	RigAnchor: Part,
	Highlight: Highlight,
	TrajectoryBeams: { Beam },
	TrajectoryAttachments: { Attachment },
	ImpactMarker: Part,
	AimMarker: Part,
	SmashMarkers: { Part },
	BallPart: Part,
	BallMesh: SpecialMesh,

	Peers: { [Player]: PeerState },
	Connections: { RBXScriptConnection },
	CharacterConnections: { RBXScriptConnection },
	Started: boolean,
}

local Controller = {}
Controller.__index = Controller

export type ElasticSlingshotController = typeof(setmetatable({} :: ControllerFields, Controller))

-- ── Геометрические помощники ───────────────────────────────────────────────

-- Кадр, у которого ось X направлена вдоль direction (для Attachment.Axis у Beam и осей цилиндров)
local function axisFrame(position: Vector3, direction: Vector3): CFrame
	local x = if direction.Magnitude > 1e-5 then direction.Unit else Vector3.xAxis
	local helper = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(helper).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(position, x, y, z)
end

-- Поворот «смотреть вдоль direction» без вырождения при вертикальном векторе
local function lookRotation(direction: Vector3): CFrame
	local look = if direction.Magnitude > 1e-5 then direction.Unit else -Vector3.zAxis
	local up = if math.abs(look.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	local right = look:Cross(up).Unit
	local trueUp = right:Cross(look)
	return CFrame.fromMatrix(Vector3.zero, right, trueUp, -look)
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function newPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function newBeam(name: string, a0: Attachment, a1: Attachment, color: Color3, zOffset: number, parent: Instance): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Segments = 16
	beam.LightInfluence = 0
	beam.LightEmission = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0)
	beam.ZOffset = zOffset
	beam.Enabled = false
	beam.Parent = parent
	return beam
end

local function newAttachment(name: string, parent: Instance): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = parent
	return attachment
end

local function createArmRig(anchor: Part, gloveParent: Instance, color: Color3, material: Enum.Material, label: string): ArmRig
	local shoulder = newAttachment(label .. "Shoulder", anchor)
	local middle = newAttachment(label .. "Middle", anchor)
	local hand = newAttachment(label .. "Hand", anchor)
	local glove = newPart(label .. "Glove", Enum.PartType.Ball, Vector3.one * 1.9, color, material, gloveParent)
	local cuff = newPart(label .. "Cuff", Enum.PartType.Cylinder, Vector3.new(0.55, 1.55, 1.55), WHITE, Enum.Material.SmoothPlastic, gloveParent)
	return {
		Shoulder = shoulder,
		Middle = middle,
		Hand = hand,
		MainA = newBeam(label .. "MainA", shoulder, middle, color, 0.08, anchor),
		MainB = newBeam(label .. "MainB", middle, hand, color, 0.08, anchor),
		OutlineA = newBeam(label .. "OutlineA", shoulder, middle, OUTLINE_COLOR, 0, anchor),
		OutlineB = newBeam(label .. "OutlineB", middle, hand, OUTLINE_COLOR, 0, anchor),
		Glove = glove,
		Cuff = cuff,
		Visible = false,
		LastTint = -1,
	}
end

local function setRigVisible(rig: ArmRig, visible: boolean)
	if rig.Visible == visible then
		return
	end
	rig.Visible = visible
	rig.MainA.Enabled = visible
	rig.MainB.Enabled = visible
	rig.OutlineA.Enabled = visible
	rig.OutlineB.Enabled = visible
	rig.Glove.Transparency = if visible then 0 else 1
	rig.Cuff.Transparency = if visible then 0 else 1
	if not visible then
		rig.Glove.CFrame = HIDDEN_CFRAME
		rig.Cuff.CFrame = HIDDEN_CFRAME
	end
end

local function destroyArmRig(rig: ArmRig)
	for _, instance in { rig.MainA, rig.MainB, rig.OutlineA, rig.OutlineB, rig.Shoulder, rig.Middle, rig.Hand, rig.Glove, rig.Cuff } :: { Instance } do
		instance:Destroy()
	end
end

-- Резиновая рука: кубика Безье плечо→кисть, делится де Кастельжо пополам на два Beam
-- (у Beam контрольные точки = Attachment ± Axis·CurveSize). Толщина — сохранение объёма:
-- w ∝ √(L₀/L), плюс дополнительное истончение середины при натяжении.
local function drawArm(
	rig: ArmRig,
	shoulder: Vector3,
	handPosition: Vector3,
	tension: number,
	wobble: Vector3,
	bodyFrame: CFrame,
	sign: number,
	color: Color3
)
	local span = handPosition - shoulder
	local spanLength = span.Magnitude
	local length = math.max(spanLength, 0.05)
	local direction = if spanLength > 1e-4 then span / spanLength else bodyFrame.LookVector
	local slack = 1 - tension
	local outward = (bodyFrame.RightVector * (0.55 * sign) + bodyFrame.LookVector * 0.45 + bodyFrame.UpVector * 0.15).Unit
	local reach = length * 0.32
	local blend = outward * (0.5 * slack + 0.15) + direction * (0.5 + 0.5 * tension)
	local p0 = shoulder
	local p1 = shoulder + blend.Unit * reach + wobble * (0.5 * slack)
	local p2 = handPosition - direction * reach + Vector3.new(0, -length * 0.16 * slack, 0) + wobble * slack
	local p3 = handPosition
	local _, a1, a2, middle, b1, b2, _ = Bezier.SplitCubic(p0, p1, p2, p3, 0.5)

	rig.Shoulder.WorldCFrame = axisFrame(p0, a1 - p0)
	rig.Middle.WorldCFrame = axisFrame(middle, b1 - middle)
	rig.Hand.WorldCFrame = axisFrame(p3, p3 - b2)
	local curve0 = (a1 - p0).Magnitude
	local curve1 = (middle - a2).Magnitude
	local curve2 = (b1 - middle).Magnitude
	local curve3 = (p3 - b2).Magnitude
	rig.MainA.CurveSize0, rig.MainA.CurveSize1 = curve0, curve1
	rig.OutlineA.CurveSize0, rig.OutlineA.CurveSize1 = curve0, curve1
	rig.MainB.CurveSize0, rig.MainB.CurveSize1 = curve2, curve3
	rig.OutlineB.CurveSize0, rig.OutlineB.CurveSize1 = curve2, curve3

	local volume = math.sqrt(PhysicsConfig.ArmRestLength / math.max(length, PhysicsConfig.ArmRestLength))
	local base = math.max(PhysicsConfig.ArmBaseWidth * volume * (1 - 0.35 * tension), PhysicsConfig.ArmMinWidth)
	local shoulderWidth = base * 1.15
	local middleWidth = math.max(base * (0.8 - 0.32 * tension), PhysicsConfig.ArmMinWidth * 0.8)
	local handWidth = base * 0.95
	local outline = PhysicsConfig.ArmOutlineWidth
	rig.MainA.Width0, rig.MainA.Width1 = shoulderWidth, middleWidth
	rig.MainB.Width0, rig.MainB.Width1 = middleWidth, handWidth
	rig.OutlineA.Width0, rig.OutlineA.Width1 = shoulderWidth + outline, middleWidth + outline
	rig.OutlineB.Width0, rig.OutlineB.Width1 = middleWidth + outline, handWidth + outline

	-- растянутая резина светлеет к середине (квантуем, чтобы не создавать ColorSequence каждый кадр)
	local tintStep = math.floor(tension * 20 + 0.5)
	if tintStep ~= rig.LastTint then
		rig.LastTint = tintStep
		local tinted = color:Lerp(STRETCH_TINT, tintStep / 20 * 0.45)
		rig.MainA.Color = ColorSequence.new(color, tinted)
		rig.MainB.Color = ColorSequence.new(tinted, color)
	end

	local tangent = p3 - b2
	local handAxis = if tangent.Magnitude > 1e-4 then tangent.Unit else direction
	rig.Glove.CFrame = axisFrame(p3, handAxis)
	rig.Cuff.CFrame = axisFrame(p3 - handAxis * 0.95, handAxis)
end

local function loadFallTrack(humanoid: Humanoid, character: Model): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	if animator == nil or animate == nil then
		return nil
	end
	local fall = animate:FindFirstChild("fall")
	local animation = if fall then fall:FindFirstChildWhichIsA("Animation") else nil
	if animation == nil then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		return track
	end
	return nil
end

-- ── Конструктор ────────────────────────────────────────────────────────────

local function makeCastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true -- предсказанно пробитые стены (CanCollide=false локально) пропускаются
	params.CollisionGroup = PhysicsConfig.CollisionGroups.Characters -- другие игроки и обломки не мешают
	return params
end

function Controller.new(camera: ShoulderCamera.ShoulderCamera): ElasticSlingshotController
	local player = Players.LocalPlayer
	local glove = GloveConfig.Get(GloveConfig.DefaultGlove)

	local rigModel = Instance.new("Model")
	rigModel.Name = "StretchPopRig_Local"
	local peerModel = Instance.new("Model")
	peerModel.Name = "StretchPopRig_Peers"
	local markerFolder = Instance.new("Folder")
	markerFolder.Name = "StretchPopMarkers"

	local rigAnchor = newPart("RigAnchor", Enum.PartType.Block, Vector3.one * 0.2, WHITE, Enum.Material.SmoothPlastic, rigModel)
	rigAnchor.CFrame = HIDDEN_CFRAME -- держатель Attachment'ов: их WorldCFrame от него не зависит

	local highlight = Instance.new("Highlight")
	highlight.Name = "CartoonOutline"
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = OUTLINE_COLOR
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = rigModel
	highlight.Parent = rigModel

	local hands = {} :: { [Types.HandSide]: Hand }
	for _, side in HAND_SIDES do
		hands[side] = {
			Side = side,
			Sign = if side == "Left" then -1 else 1,
			Phase = "Idle",
			Held = false,
			AnchorPart = nil,
			AnchorLocal = Vector3.zero,
			AnchorWorld = Vector3.zero,
			AnchorNormal = Vector3.yAxis,
			Position = Vector3.zero,
			RestLength = 0,
			Missed = false,
			MissTarget = Vector3.zero,
			Wobble = Spring.Vector.new(Vector3.zero, 2.4, 0.28),
			Rig = createArmRig(rigAnchor, rigModel, glove.Color, glove.Material, side),
		}
	end

	local trajectoryBeams: { Beam } = {}
	local trajectoryAttachments: { Attachment } = {}
	for index = 1, TRAJECTORY_SEGMENTS do
		local a0 = newAttachment("Arc" .. index .. "A", rigAnchor)
		local a1 = newAttachment("Arc" .. index .. "B", rigAnchor)
		local beam = newBeam("Arc" .. index, a0, a1, WHITE, 0.05, markerFolder)
		beam.LightEmission = 0.8
		beam.Segments = 10
		table.insert(trajectoryBeams, beam)
		table.insert(trajectoryAttachments, a0)
		table.insert(trajectoryAttachments, a1)
	end

	local impactMarker = newPart("ImpactMarker", Enum.PartType.Cylinder, Vector3.new(0.2, 5, 5), WHITE, Enum.Material.Neon, markerFolder)
	local aimMarker = newPart("AimMarker", Enum.PartType.Cylinder, Vector3.new(0.15, 2.4, 2.4), AIM_VALID_COLOR, Enum.Material.Neon, markerFolder)
	local smashMarkers: { Part } = {}
	for index = 1, SMASH_MARKERS do
		table.insert(
			smashMarkers,
			newPart("SmashMarker" .. index, Enum.PartType.Ball, Vector3.one * 1.6, AIM_VALID_COLOR, Enum.Material.Neon, markerFolder)
		)
	end

	local ballDiameter = PhysicsConfig.BallVisualRadius * 2
	local ballPart = newPart("SpringBall", Enum.PartType.Block, Vector3.one * ballDiameter, glove.Color, glove.Material, rigModel)
	ballPart.CFrame = HIDDEN_CFRAME
	local ballMesh = Instance.new("SpecialMesh")
	ballMesh.MeshType = Enum.MeshType.Sphere
	ballMesh.Parent = ballPart
	for _, hand in hands do
		hand.Rig.Glove.CFrame = HIDDEN_CFRAME
		hand.Rig.Cuff.CFrame = HIDDEN_CFRAME
	end

	rigModel.Parent = workspace
	peerModel.Parent = workspace
	markerFolder.Parent = workspace

	local fields: ControllerFields = {
		Player = player,
		Camera = camera,
		Signals = {
			StateChanged = Signal.new(),
			HandFired = Signal.new(),
			HandAttached = Signal.new(),
			HandReleased = Signal.new(),
			TensionChanged = Signal.new(),
			Launched = Signal.new(),
			Bounced = Signal.new(),
			Smashed = Signal.new(),
			Splat = Signal.new(),
			GongStruck = Signal.new(),
			LootGained = Signal.new(),
			BallChanged = Signal.new(),
		},

		Character = nil,
		Humanoid = nil,
		Root = nil,
		ShoulderOffsets = { Left = Vector3.new(-1.5, 1, 0), Right = Vector3.new(1.5, 1, 0) },
		RootHeight = 3,
		ArmParts = { Left = {}, Right = {} },
		ArmHidden = { Left = false, Right = false },
		BodyParts = {},
		BodyDecals = {},
		BodyDirty = true,
		BodyHidden = false,
		FallTrack = nil,

		State = "Walk",
		Hands = hands,
		Params = StretchPhysics.Derive({ Elasticity = 0, SpringPower = 0, SmashMass = 0 }, GloveConfig.DefaultGlove),
		GloveColor = glove.Color,
		GloveMaterial = glove.Material,

		SimPosition = Vector3.zero,
		SimVelocity = Vector3.zero,
		SimRotation = CFrame.identity,
		PrevPosition = Vector3.zero,
		PrevRotation = CFrame.identity,
		RenderCFrame = CFrame.identity,
		Accumulator = 0,
		LastWritten = Vector3.zero,
		LaunchGraceUntil = 0,

		BallHeld = false,
		BallSink = false,
		BallActive = false,
		BallAxis = Vector3.xAxis,
		BallSquash = Spring.Number.new(0, 3.2, 0.32),

		Tension = 0,
		LastTensionSent = 0,
		Combo = 0,
		LandedAt = nil,
		GongCooldownUntil = 0,
		Predictions = {},

		Aim = { Valid = false, Point = Vector3.zero, Normal = Vector3.yAxis, Part = nil },
		GrabPoints = {},
		CastParams = makeCastParams(),
		AimParams = makeCastParams(),
		PreviewParams = makeCastParams(),
		PreviewTimer = 0,

		RigModel = rigModel,
		PeerModel = peerModel,
		MarkerFolder = markerFolder,
		RigAnchor = rigAnchor,
		Highlight = highlight,
		TrajectoryBeams = trajectoryBeams,
		TrajectoryAttachments = trajectoryAttachments,
		ImpactMarker = impactMarker,
		AimMarker = aimMarker,
		SmashMarkers = smashMarkers,
		BallPart = ballPart,
		BallMesh = ballMesh,

		Peers = {},
		Connections = {},
		CharacterConnections = {},
		Started = false,
	}
	return setmetatable(fields, Controller)
end

-- ── Публичные геттеры (для HUD и аудио следующего шага) ────────────────────

function Controller.GetState(self: ElasticSlingshotController): string
	return self.State
end

function Controller.GetSpeed(self: ElasticSlingshotController): number
	if self.State ~= "Walk" then
		return self.SimVelocity.Magnitude
	end
	local root = self.Root
	return if root then root.AssemblyLinearVelocity.Magnitude else 0
end

function Controller.GetTension(self: ElasticSlingshotController): number
	return self.Tension
end

function Controller.GetCombo(self: ElasticSlingshotController): number
	return self.Combo
end

function Controller.GetParams(self: ElasticSlingshotController): StretchPhysics.StretchParams
	return self.Params
end

-- ── Статы и перчатка из атрибутов игрока (сервер их реплицирует) ───────────

function Controller.RefreshParams(self: ElasticSlingshotController)
	local player = self.Player
	local function stat(name: string): number
		local value = player:GetAttribute(name)
		return if typeof(value) == "number" then value else 0
	end
	local gloveAttribute = player:GetAttribute("Glove")
	local gloveId = if typeof(gloveAttribute) == "string" then gloveAttribute else nil
	self.Params = StretchPhysics.Derive({
		Elasticity = stat("Stat_Elasticity"),
		SpringPower = stat("Stat_SpringPower"),
		SmashMass = stat("Stat_SmashMass"),
	}, gloveId)
	local glove = GloveConfig.Get(gloveId)
	self.GloveColor = glove.Color
	self.GloveMaterial = glove.Material
	for _, hand in self.Hands do
		hand.Rig.Glove.Color = glove.Color
		hand.Rig.Glove.Material = glove.Material
		hand.Rig.Cuff.Color = glove.Accent
		hand.Rig.LastTint = -1
	end
	self.BallPart.Color = glove.Color
	self.BallPart.Material = glove.Material
	for _, beam in self.TrajectoryBeams do
		beam.Color = ColorSequence.new(WHITE, glove.Color)
	end
end

-- ── Состояния ───────────────────────────────────────────────────────────────

function Controller.SetState(self: ElasticSlingshotController, state: ControllerState)
	if self.State == state then
		return
	end
	self.State = state
	self.Signals.StateChanged:Fire(state)
end

function Controller.AnyAttached(self: ElasticSlingshotController): boolean
	for _, hand in self.Hands do
		if hand.Phase == "Attached" then
			return true
		end
	end
	return false
end

function Controller.CollectBands(self: ElasticSlingshotController): { StretchPhysics.Band }
	local bands: { StretchPhysics.Band } = {}
	for _, hand in self.Hands do
		if hand.Phase == "Attached" then
			table.insert(bands, { Anchor = hand.AnchorWorld, Rest = hand.RestLength })
		end
	end
	return bands
end

function Controller.AttachedCentroid(self: ElasticSlingshotController): Vector3?
	local sum = Vector3.zero
	local count = 0
	for _, hand in self.Hands do
		if hand.Phase == "Attached" then
			sum += hand.AnchorWorld
			count += 1
		end
	end
	return if count > 0 then sum / count else nil
end

function Controller.BodyPosition(self: ElasticSlingshotController): Vector3
	if self.State ~= "Walk" then
		return self.SimPosition
	end
	local root = self.Root
	return if root then root.Position else self.SimPosition
end

function Controller.PlayFall(self: ElasticSlingshotController, playing: boolean)
	local humanoid, character = self.Humanoid, self.Character
	if playing and self.FallTrack == nil and humanoid and character then
		self.FallTrack = loadFallTrack(humanoid, character)
	end
	local track = self.FallTrack
	if track then
		if playing and not track.IsPlaying then
			track:Play(0.15)
		elseif not playing and track.IsPlaying then
			track:Stop(0.2)
		end
	end
end

function Controller.EnterCustom(self: ElasticSlingshotController, state: ControllerState, velocity: Vector3)
	local root, humanoid = self.Root, self.Humanoid
	if root == nil or humanoid == nil then
		return
	end
	if self.State == "Walk" then
		self.SimPosition = root.Position
		self.SimRotation = root.CFrame.Rotation
		self.PrevPosition = self.SimPosition
		self.PrevRotation = self.SimRotation
		self.Accumulator = 0
		self.LastWritten = root.Position
		self.LandedAt = nil
		humanoid.AutoRotate = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	self.SimVelocity = velocity
	self:SetState(state)
	self:PlayFall(state == "Air")
end

function Controller.ExitCustom(self: ElasticSlingshotController, grounded: boolean)
	if self.State == "Walk" then
		return
	end
	local humanoid, root = self.Humanoid, self.Root
	if root and not grounded then
		-- выходим в обычное падение: вертикально, с сохранением импульса
		local look = flatten(self.SimRotation.LookVector)
		if look.Magnitude < 1e-3 then
			look = self.Camera:GetFlatLook()
		end
		root.CFrame = CFrame.new(root.Position) * lookRotation(look.Unit)
		root.AssemblyLinearVelocity = self.SimVelocity
		root.AssemblyAngularVelocity = Vector3.zero
	end
	self:SetState("Walk")
	self:PlayFall(false)
	self.Tension = 0
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:ChangeState(if grounded then Enum.HumanoidStateType.Landed else Enum.HumanoidStateType.Freefall)
	end
	if grounded then
		self.LandedAt = os.clock()
	end
end

-- Внешний телепорт / сброс сервером / смерть: прекращаем кастомную физику, руки домой.
function Controller.AbortCustom(self: ElasticSlingshotController)
	for _, hand in self.Hands do
		if hand.Phase == "Attached" then
			Net.ArmVisual:FireServer(hand.Side, false, nil)
			self.Signals.HandReleased:Fire(hand.Side)
		end
		if hand.Phase ~= "Idle" then
			hand.Phase = "Retracting"
			hand.AnchorPart = nil
		end
	end
	self.BallHeld = false
	self:ExitCustom(false)
end

function Controller.HardReset(self: ElasticSlingshotController, target: CFrame?)
	self:AbortCustom()
	self.Combo = 0
	self.Accumulator = 0
	local character, root = self.Character, self.Root
	if target and character and root then
		character:PivotTo(target)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		self.Camera:SnapBehind(target.LookVector)
	end
	if root then
		self.SimPosition = root.Position
		self.LastWritten = root.Position
	end
end

-- ── Руки: выстрел, захват, отпускание ──────────────────────────────────────

function Controller.ShoulderWorld(self: ElasticSlingshotController, side: Types.HandSide): Vector3
	return self.RenderCFrame:PointToWorldSpace(self.ShoulderOffsets[side])
end

function Controller.FireHand(self: ElasticSlingshotController, hand: Hand)
	if self.Root == nil or hand.Phase == "Attached" or hand.Phase == "Flying" then
		return
	end
	local shoulder = self:ShoulderWorld(hand.Side)
	if hand.Phase == "Idle" then
		hand.Position = shoulder
	end
	local aim = self.Aim
	local aimPart = aim.Part
	if aim.Valid and aimPart then
		-- точка видна с камеры; проверяем, не заслоняет ли что-то линию от плеча
		local point, part, normal = aim.Point, aimPart, aim.Normal
		local toPoint = point - shoulder
		local blocker = workspace:Raycast(shoulder, toPoint, self.CastParams)
		if blocker and blocker.Distance < toPoint.Magnitude - 0.5 then
			point, part, normal = blocker.Position, blocker.Instance, blocker.Normal
		end
		hand.AnchorPart = part
		hand.AnchorLocal = part.CFrame:PointToObjectSpace(point)
		hand.AnchorWorld = point
		hand.AnchorNormal = normal
		hand.Missed = false
	else
		local _, direction = self.Camera:GetAimRay()
		hand.AnchorPart = nil
		hand.Missed = true
		hand.MissTarget = shoulder + direction * (self.Params.GrabRange * PhysicsConfig.MissReachFraction)
	end
	hand.Phase = "Flying"
	self.Signals.HandFired:Fire(hand.Side)
end

function Controller.IsAnchorValid(self: ElasticSlingshotController, hand: Hand): boolean
	local part = hand.AnchorPart
	if part == nil or not part.CanCollide or not part:IsDescendantOf(workspace) then
		return false
	end
	local body = self:BodyPosition()
	local limit = (self.Params.GrabRange + self.Params.MaxStretch) * ANCHOR_BREAK_FACTOR
	return (part.CFrame:PointToWorldSpace(hand.AnchorLocal) - body).Magnitude <= limit
end

function Controller.AttachHand(self: ElasticSlingshotController, hand: Hand)
	local root, humanoid = self.Root, self.Humanoid
	if root == nil or humanoid == nil then
		return
	end
	hand.Phase = "Attached"
	local body = self:BodyPosition()
	local offset = hand.AnchorWorld - body
	hand.RestLength = math.max(offset.Magnitude, PhysicsConfig.AirMinRestLength)
	if offset.Magnitude > 1e-3 then
		hand.Wobble:Impulse(offset.Unit * 26)
	end
	Net.ArmVisual:FireServer(hand.Side, true, hand.AnchorWorld)
	self.Signals.HandAttached:Fire(hand.Side)
	KineticVFX.ImpactRing(hand.AnchorWorld, hand.AnchorNormal, 2.6, self.GloveColor)

	if self.State == "Walk" then
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local groundSpeed = flatten(root.AssemblyLinearVelocity).Magnitude
		if grounded and groundSpeed < CHARGE_MAX_GROUND_SPEED then
			self:EnterCustom("Charge", Vector3.zero)
		else
			self:EnterCustom("Air", root.AssemblyLinearVelocity)
		end
	end
end

function Controller.DetachHand(self: ElasticSlingshotController, hand: Hand, snap: boolean)
	if hand.Phase == "Attached" then
		Net.ArmVisual:FireServer(hand.Side, false, nil)
		self.Signals.HandReleased:Fire(hand.Side)
	end
	if hand.Phase ~= "Idle" then
		hand.Phase = "Retracting"
	end
	hand.AnchorPart = nil
	if snap then
		-- «хлыст» резинки при отпускании
		local frame = self.RenderCFrame
		hand.Wobble:Impulse(frame.UpVector * 34 + frame.RightVector * (hand.Sign * 18))
	end
	if self.State == "Charge" and not self:AnyAttached() then
		self:ExitCustom(true)
	end
end

function Controller.ReleaseSlingshot(self: ElasticSlingshotController)
	local bands = self:CollectBands()
	local velocity, _, tension = StretchPhysics.SlingshotLaunch(self.SimPosition, bands, self.Params)
	local speed = velocity.Magnitude
	local launching = speed >= PhysicsConfig.MinLaunchSpeed
	if launching then
		-- сначала переводим в полёт, потом отпускаем резинки (иначе Charge без резинок вернёт в ходьбу)
		self.Combo = 0
		self.LaunchGraceUntil = os.clock() + PhysicsConfig.LaunchGroundGrace
		self.SimVelocity = velocity
		self:SetState("Air")
		self:PlayFall(true)
	end
	for _, hand in self.Hands do
		if hand.Phase == "Attached" then
			self:DetachHand(hand, true)
		end
	end
	if not launching then
		self:ExitCustom(true)
		return
	end
	self.Tension = 0
	self.Signals.Launched:Fire(speed, velocity)
	self.Camera:AddTrauma(0.18 + 0.35 * tension)
	self.Camera:Kick(10 * tension)
	KineticVFX.LaunchBurst(self.SimPosition, velocity / speed, self.GloveColor)
end

function Controller.OnArmPressed(self: ElasticSlingshotController, side: Types.HandSide)
	local hand = self.Hands[side]
	hand.Held = true
	self:FireHand(hand)
end

function Controller.OnArmReleased(self: ElasticSlingshotController, side: Types.HandSide)
	local hand = self.Hands[side]
	hand.Held = false
	if hand.Phase == "Attached" then
		if self.State == "Charge" then
			self:ReleaseSlingshot()
		else
			self:DetachHand(hand, true)
		end
	end
end

function Controller.HandTension(self: ElasticSlingshotController, hand: Hand): number
	if hand.Phase == "Attached" then
		local stretch = (hand.AnchorWorld - self:BodyPosition()).Magnitude - hand.RestLength
		return math.clamp(stretch / self.Params.MaxStretch, 0, 1)
	elseif hand.Phase == "Flying" then
		return 0.12
	end
	return 0
end

function Controller.UpdateHands(self: ElasticSlingshotController, dt: number)
	for _, side in HAND_SIDES do
		local hand = self.Hands[side]
		local shoulder = self:ShoulderWorld(side)
		if hand.Phase == "Flying" then
			local part = hand.AnchorPart
			local target = hand.MissTarget
			if not hand.Missed and part then
				target = part.CFrame:PointToWorldSpace(hand.AnchorLocal)
				hand.AnchorWorld = target
			end
			local toTarget = target - hand.Position
			local distance = toTarget.Magnitude
			local stepLength = PhysicsConfig.HandSpeed * dt
			if distance <= stepLength + PhysicsConfig.HandArriveEpsilon then
				hand.Position = target
				if hand.Missed or not hand.Held or not self:IsAnchorValid(hand) then
					hand.Phase = "Retracting"
					hand.AnchorPart = nil
					hand.Wobble:Impulse(Vector3.new(0, 18, 0))
				else
					self:AttachHand(hand)
				end
			else
				hand.Position += toTarget / distance * stepLength
			end
		elseif hand.Phase == "Attached" then
			local part = hand.AnchorPart
			if part and self:IsAnchorValid(hand) then
				hand.AnchorWorld = part.CFrame:PointToWorldSpace(hand.AnchorLocal)
				hand.Position = hand.AnchorWorld
			else
				-- якорь исчез (стену пробили, деталь удалили волной) — резинка лопается
				self:DetachHand(hand, true)
			end
		elseif hand.Phase == "Retracting" then
			local toShoulder = shoulder - hand.Position
			local distance = toShoulder.Magnitude
			local stepLength = PhysicsConfig.HandRetractSpeed * dt
			if distance <= stepLength + 1 then
				hand.Phase = "Idle"
				hand.Position = shoulder
			else
				hand.Position += toShoulder / distance * stepLength
			end
		else
			hand.Position = shoulder
		end
		hand.Wobble:Update(dt)
	end
end

-- ── Прицел ──────────────────────────────────────────────────────────────────

function Controller.UpdateAim(self: ElasticSlingshotController)
	local root = self.Root
	if root == nil then
		return
	end
	local origin, direction = self.Camera:GetAimRay()
	local body = self:BodyPosition()
	local range = self.Params.GrabRange
	local castLength = range + (origin - body).Magnitude + 8
	local aim = self.Aim
	aim.Valid = false
	aim.Part = nil

	local hit = workspace:Raycast(origin, direction * castLength, self.AimParams)
	if hit and (hit.Position - body).Magnitude <= range then
		aim.Valid = true
		aim.Point = hit.Position
		aim.Normal = hit.Normal
		aim.Part = hit.Instance
	else
		-- Аим-ассист: ближайшая к лучу точка захвата в конусе (кольца, арки)
		local best: BasePart? = nil
		local bestDot = PhysicsConfig.AimAssistCos
		for point in self.GrabPoints do
			local toPoint = point.Position - origin
			local distance = toPoint.Magnitude
			if distance > 1e-3 and (point.Position - body).Magnitude <= range then
				local alignment = direction:Dot(toPoint / distance)
				if alignment > bestDot then
					best = point
					bestDot = alignment
				end
			end
		end
		if best then
			local lineOfSight = workspace:Raycast(origin, (best.Position - origin) * 1.02, self.AimParams)
			if lineOfSight and lineOfSight.Instance == best then
				aim.Valid = true
				aim.Point = lineOfSight.Position
				aim.Normal = lineOfSight.Normal
				aim.Part = best
			end
		end
	end

	if aim.Valid then
		self.AimMarker.CFrame = axisFrame(aim.Point + aim.Normal * 0.08, aim.Normal)
		self.AimMarker.Transparency = 0.15
	else
		self.AimMarker.Transparency = 1
	end
end

-- ── Фиксированный шаг: рогатка на земле ────────────────────────────────────

function Controller.StepCharge(self: ElasticSlingshotController, dt: number)
	local bands = self:CollectBands()
	if #bands == 0 then
		return
	end
	local params = self.Params
	local position = self.SimPosition

	-- опора пропала (платформу снесло) → висим на резинках
	local support = workspace:Raycast(position, Vector3.new(0, -(self.RootHeight + 1.5), 0), self.CastParams)
	if support == nil then
		self.SimVelocity = Vector3.zero
		self:SetState("Air")
		self:PlayFall(true)
		return
	end

	local currentStretch = StretchPhysics.MaxBandStretch(position, bands)
	local moved = Vector3.zero
	if currentStretch < params.MaxStretch then
		local ratio = math.clamp(currentStretch / params.MaxStretch, 0, 1)
		-- чем сильнее натяжение, тем тяжелее тянуть (ощущение F = −kx)
		local drawSpeed = PhysicsConfig.DrawSpeed * (1 - PhysicsConfig.DrawResistance * ratio * ratio)
		local stepVector = -self.Camera:GetFlatLook() * (drawSpeed * dt)
		local candidate = position + stepVector
		local candidateStretch = StretchPhysics.MaxBandStretch(candidate, bands)
		if candidateStretch <= currentStretch + 1e-4 then
			-- шаг не натягивает резинку (якорь позади камеры) — стоим, а не скользим к якорю
			candidate = position
		elseif candidateStretch > params.MaxStretch then
			local fraction = (params.MaxStretch - currentStretch) / (candidateStretch - currentStretch)
			candidate = position + stepVector * math.clamp(fraction, 0, 1)
		end
		local sweep = candidate - position
		if sweep.Magnitude > 1e-4 then
			local blocked = workspace:Spherecast(position + Vector3.new(0, 0.6, 0), PhysicsConfig.BodyRadius * 0.75, sweep, self.CastParams)
			if blocked then
				candidate = position
			else
				local ground = workspace:Raycast(candidate + Vector3.new(0, 3, 0), Vector3.new(0, -(self.RootHeight + 7), 0), self.CastParams)
				if ground and ground.Normal.Y >= PhysicsConfig.GroundNormalMinY then
					candidate = Vector3.new(candidate.X, ground.Position.Y + self.RootHeight, candidate.Z)
				else
					candidate = position -- край: дальше не тянем, чтобы не сорваться
				end
			end
		end
		moved = candidate - position
		position = candidate
	end
	self.SimPosition = position
	self.SimVelocity = moved / dt

	local _, _, tension = StretchPhysics.SlingshotLaunch(position, bands, params)
	self.Tension = tension
	local centroid = self:AttachedCentroid() or position
	local toCentroid = flatten(centroid - position)
	local facing = if toCentroid.Magnitude > 0.5 then toCentroid.Unit else self.Camera:GetFlatLook()
	local lean = math.rad(PhysicsConfig.ChargeLeanDegrees) * tension
	self.SimRotation = lookRotation(facing) * CFrame.Angles(lean, 0, 0)
end

-- ── Фиксированный шаг: полёт, банджи, шар ──────────────────────────────────

function Controller.RegisterBounce(self: ElasticSlingshotController, point: Vector3, normal: Vector3, normalSpeed: number)
	self.Combo += 1
	self.BallAxis = normal
	self.BallSquash.Position = -0.42
	self.BallSquash.Velocity = 0
	KineticVFX.ImpactRing(point, normal, math.clamp(normalSpeed * 0.05, 3, 12), self.GloveColor)
	self.Camera:AddTrauma(math.clamp(normalSpeed / 500, 0.05, 0.3))
	self.Signals.Bounced:Fire(self.Combo, self.SimVelocity.Magnitude, point)
end

function Controller.PredictSmash(
	self: ElasticSlingshotController,
	part: BasePart,
	obstacleId: string,
	point: Vector3,
	velocity: Vector3,
	impactSpeed: number
)
	if self.Predictions[obstacleId] then
		return
	end
	local snapshot = KineticVFX.Snapshot(part)
	local restore = KineticVFX.PredictHide(part)
	self.Predictions[obstacleId] = { Restore = restore, ExpiresAt = os.clock() + PREDICTION_TIMEOUT }
	KineticVFX.SmashBurst(snapshot, point, velocity)
	self.Combo += 1
	self.Camera:AddTrauma(0.32)
	self.Camera:Kick(4)
	Net.SmashRequest:FireServer(obstacleId, velocity, point, impactSpeed, self.Combo)
	self.Signals.Smashed:Fire(snapshot.Kind, impactSpeed, point)
end

function Controller.StrikeGong(self: ElasticSlingshotController, gong: BasePart, point: Vector3, velocity: Vector3)
	local now = os.clock()
	if now < self.GongCooldownUntil then
		return
	end
	self.GongCooldownUntil = now + GONG_CLIENT_COOLDOWN
	local speed = velocity.Magnitude
	KineticVFX.GongStrike(gong, point, velocity)
	self.Camera:AddTrauma(0.6)
	self.Camera:Kick(6)
	self.Signals.GongStruck:Fire(speed, self.Combo)
	local slot = gong:GetAttribute("GongLaneSlot")
	if typeof(slot) == "number" and gong:GetAttribute("OwnerUserId") == self.Player.UserId then
		Net.GongStrike:FireServer(slot, velocity, speed, self.Combo)
	end
end

function Controller.ResolveContact(self: ElasticSlingshotController, hit: RaycastResult): ContactResult
	local part = hit.Instance
	local normal = hit.Normal
	local velocity = self.SimVelocity
	local normalSpeed = velocity:Dot(normal)
	if normalSpeed >= -0.01 then
		return "Slide"
	end
	local speed = velocity.Magnitude
	local impact = -normalSpeed

	if part:HasTag(Tags.Gong) then
		self:StrikeGong(part, hit.Position, velocity)
		self.SimVelocity = StretchPhysics.Reflect(velocity, normal, PhysicsConfig.GongRestitution, 0.8)
		return "Bounce"
	end

	if part:HasTag(Tags.Smashable) then
		local durability = part:GetAttribute("Durability")
		local obstacleId = part:GetAttribute("ObstacleId")
		local mine = part:GetAttribute("OwnerUserId") == self.Player.UserId
		if typeof(durability) == "number" and typeof(obstacleId) == "string" then
			local impactSpeed = StretchPhysics.ImpactSpeed(velocity, normal)
			if mine and StretchPhysics.CanSmash(durability, self.Params.ImpactMass, impactSpeed) then
				self:PredictSmash(part, obstacleId, hit.Position, velocity, impactSpeed)
				return "Pass" -- «не тормозя игрока»: скорость не меняется
			end
			local needed = StretchPhysics.SpeedToBreak(durability, self.Params.ImpactMass)
			KineticVFX.WallWobble(part, velocity, impactSpeed / needed)
		end
	end

	if part:HasTag(Tags.Bouncy) then
		local reflected = StretchPhysics.Reflect(velocity, normal, PhysicsConfig.BouncySurfaceRestitution, 1)
		self.SimVelocity = StretchPhysics.ClampSpeed(reflected, math.max(PhysicsConfig.BouncySurfaceMaxSpeed, speed))
		self:RegisterBounce(hit.Position, normal, impact)
		return "Bounce"
	end

	if self.BallActive then
		if impact > PhysicsConfig.BounceMinNormalSpeed then
			self.SimVelocity = StretchPhysics.Reflect(velocity, normal, self.Params.Restitution, PhysicsConfig.BallTangentKeep)
			self:RegisterBounce(hit.Position, normal, impact)
			return "Bounce"
		end
		self.SimVelocity = velocity - normal * normalSpeed -- катимся
		return "Slide"
	end

	if normal.Y >= PhysicsConfig.GroundNormalMinY then
		local tangent = velocity - normal * normalSpeed
		if tangent.Magnitude < PhysicsConfig.LandSpeed and os.clock() >= self.LaunchGraceUntil then
			return "Land"
		end
		self.SimVelocity = tangent
		if impact > 60 then
			self.Camera:AddTrauma(math.clamp(impact / 400, 0, 0.35))
			KineticVFX.ImpactRing(hit.Position, normal, 5, WHITE)
		end
		return "Slide"
	end

	-- Стена/потолок без шара: мультяшный «шлепок», теряем нормальную скорость и часть касательной
	self.SimVelocity = (velocity - normal * normalSpeed) * PhysicsConfig.WallSlideKeep
	if impact > 40 then
		self.Camera:AddTrauma(math.clamp(impact / 300, 0.1, 0.5))
		KineticVFX.ImpactRing(hit.Position, normal, 4 + impact * 0.02, WHITE)
		self.Signals.Splat:Fire(impact)
	end
	return "Slide"
end

function Controller.Land(self: ElasticSlingshotController, groundPoint: Vector3)
	local root = self.Root
	local flat = flatten(self.SimVelocity)
	local look = if flat.Magnitude > 1 then flat.Unit else flatten(self.SimRotation.LookVector)
	if look.Magnitude < 1e-3 then
		look = self.Camera:GetFlatLook()
	end
	local position = groundPoint + Vector3.new(0, self.RootHeight, 0)
	self.SimPosition = position
	self.SimRotation = lookRotation(look.Unit)
	self.PrevPosition = position
	self.PrevRotation = self.SimRotation
	if root then
		root.CFrame = CFrame.new(position) * self.SimRotation
		root.AssemblyLinearVelocity = StretchPhysics.ClampSpeed(flat, 50)
		root.AssemblyAngularVelocity = Vector3.zero
	end
	self.BallHeld = false
	self:ExitCustom(true)
end

-- Sweep сферой с разрешением до 4 контактов за подшаг. Возвращает true, если приземлились.
function Controller.MoveAndCollide(self: ElasticSlingshotController, dt: number): boolean
	local radius = PhysicsConfig.BodyRadius
	local position = self.SimPosition
	local remaining = dt
	for _ = 1, 4 do
		local displacement = self.SimVelocity * remaining
		local length = displacement.Magnitude
		if length < 1e-4 then
			break
		end
		local hit = workspace:Spherecast(position, radius, displacement, self.CastParams)
		if hit == nil then
			position += displacement
			break
		end
		local travel = math.max(hit.Distance - PhysicsConfig.SkinWidth, 0)
		position += displacement.Unit * travel
		remaining *= math.max(1 - travel / length, 0)
		self.SimPosition = position
		local result = self:ResolveContact(hit)
		if result == "Land" then
			self:Land(hit.Position)
			return true
		end
		if result ~= "Pass" then
			position += hit.Normal * PhysicsConfig.SkinWidth
		end
	end
	self.SimPosition = position
	return false
end

-- Скольжение по земле: экспоненциальное трение и мягкое приземление
function Controller.ApplyGroundContact(self: ElasticSlingshotController, dt: number)
	if os.clock() < self.LaunchGraceUntil then
		return
	end
	local probe = Vector3.new(0, -(PhysicsConfig.BodyRadius + PhysicsConfig.GroundProbeExtra), 0)
	local ground = workspace:Raycast(self.SimPosition, probe, self.CastParams)
	if ground == nil or ground.Normal.Y < PhysicsConfig.GroundNormalMinY then
		return
	end
	local velocity = self.SimVelocity
	local normal = ground.Normal
	local normalSpeed = velocity:Dot(normal)
	if normalSpeed > 2 then
		return -- отрываемся от земли
	end
	local friction = if self.BallActive then 0.35 else PhysicsConfig.SkidFriction
	local tangent = (velocity - normal * normalSpeed) * math.exp(-friction * dt)
	self.SimVelocity = tangent
	local landSpeed = if self.BallActive then PhysicsConfig.LandSpeed * 0.4 else PhysicsConfig.LandSpeed
	if tangent.Magnitude < landSpeed then
		self:Land(ground.Position)
	end
end

function Controller.UpdateFlightRotation(self: ElasticSlingshotController, dt: number)
	local velocity = self.SimVelocity
	local target = self.SimRotation
	local centroid = self:AttachedCentroid()
	if centroid then
		local toAnchor = centroid - self.SimPosition
		if toAnchor.Magnitude > 1 then
			target = lookRotation(toAnchor) * CFrame.Angles(math.rad(-25), 0, 0)
		end
	elseif velocity.Magnitude > 8 then
		-- поза «супергероя»: голова вперёд по скорости
		target = lookRotation(velocity) * CFrame.Angles(math.rad(-70), 0, 0)
	end
	self.SimRotation = self.SimRotation:Lerp(target, 1 - math.exp(-10 * dt))
end

function Controller.StepAir(self: ElasticSlingshotController, dt: number)
	local params = self.Params
	local velocity = self.SimVelocity
	local position = self.SimPosition
	local acceleration = StretchPhysics.Gravity() + StretchPhysics.Drag(velocity)
	local humanoid = self.Humanoid
	if humanoid then
		local move = flatten(humanoid.MoveDirection)
		if move.Magnitude > 0.05 then
			acceleration += move.Unit * PhysicsConfig.AirControlAcceleration
		end
	end
	local maxTension = 0
	for _, hand in self.Hands do
		if hand.Phase == "Attached" then
			-- резинка укорачивается, пока кнопка зажата → тянет к якорю (банджи)
			hand.RestLength = math.max(PhysicsConfig.AirMinRestLength, hand.RestLength - PhysicsConfig.AirRetractSpeed * dt)
			local force, stretch =
				StretchPhysics.BandForce(position, hand.AnchorWorld, hand.RestLength, params.AirStiffness, velocity, PhysicsConfig.AirRadialDamping)
			acceleration += force / params.FlightMass
			maxTension = math.max(maxTension, stretch / params.MaxStretch)
		end
	end
	self.Tension = math.clamp(maxTension, 0, 1)
	self.SimVelocity = StretchPhysics.ClampSpeed(velocity + acceleration * dt, PhysicsConfig.MaxFlightSpeed)
	if self:MoveAndCollide(dt) then
		return
	end
	self:ApplyGroundContact(dt)
	if self.State ~= "Air" then
		return
	end
	self:UpdateFlightRotation(dt)
end

function Controller.Simulate(self: ElasticSlingshotController, dt: number)
	if self.State == "Charge" then
		self:StepCharge(dt)
	elseif self.State == "Air" then
		self:StepAir(dt)
	end
end

-- ── Шар и скрытие тела ──────────────────────────────────────────────────────

function Controller.CollectBody(self: ElasticSlingshotController)
	local character = self.Character
	table.clear(self.BodyParts)
	table.clear(self.BodyDecals)
	if character then
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				if descendant.Name ~= "HumanoidRootPart" then
					table.insert(self.BodyParts, descendant)
				end
			elseif descendant:IsA("Decal") then
				table.insert(self.BodyDecals, descendant)
			end
		end
	end
	self.BodyDirty = false
end

function Controller.ApplyArmVisibility(self: ElasticSlingshotController, side: Types.HandSide, hidden: boolean)
	self.ArmHidden[side] = hidden
	if self.BodyHidden then
		return
	end
	for _, part in self.ArmParts[side] do
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end
end

function Controller.SetBodyHidden(self: ElasticSlingshotController, hidden: boolean)
	if self.BodyDirty then
		self:CollectBody()
	end
	self.BodyHidden = hidden
	local modifier = if hidden then 1 else 0
	for _, part in self.BodyParts do
		part.LocalTransparencyModifier = modifier
	end
	for _, decal in self.BodyDecals do
		decal.LocalTransparencyModifier = modifier
	end
	if not hidden then
		for _, side in HAND_SIDES do
			if self.ArmHidden[side] then
				for _, part in self.ArmParts[side] do
					part.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

function Controller.UpdateBall(self: ElasticSlingshotController, dt: number)
	local shouldBall = self.BallHeld and self.State == "Air"
	if shouldBall ~= self.BallActive then
		self.BallActive = shouldBall
		self:SetBodyHidden(shouldBall)
		self.BallSquash:Snap(0)
		Net.ArmVisual:FireServer("Ball", shouldBall, nil)
		self.Signals.BallChanged:Fire(shouldBall)
		if shouldBall then
			KineticVFX.ImpactRing(self.RenderCFrame.Position, Vector3.yAxis, 5, self.GloveColor)
		end
	end
	if not self.BallActive then
		if self.BallPart.Transparency < 1 then
			self.BallPart.Transparency = 1
			self.BallPart.CFrame = HIDDEN_CFRAME
		end
		return
	end
	local velocity = self.SimVelocity
	local speed = velocity.Magnitude
	if speed > 5 and self.BallSquash.Position > -0.05 then
		local blended = self.BallAxis:Lerp(velocity / speed, 1 - math.exp(-14 * dt))
		self.BallAxis = if blended.Magnitude > 0.1 then blended.Unit else velocity / speed
	end
	-- растяжение вдоль скорости, сжатие при ударе; объём сохраняется (across = 1/√along)
	self.BallSquash.Target = math.clamp(speed / 600, 0, 0.32)
	local squash = self.BallSquash:Update(dt)
	local along = math.max(1 + squash, 0.35)
	local across = 1 / math.sqrt(along)
	self.BallPart.CFrame = axisFrame(self.RenderCFrame.Position, self.BallAxis)
	self.BallMesh.Scale = Vector3.new(along, across, across)
	self.BallPart.Transparency = 0
end

-- ── Рендер рук ──────────────────────────────────────────────────────────────

function Controller.RenderArms(self: ElasticSlingshotController)
	for _, side in HAND_SIDES do
		local hand = self.Hands[side]
		local active = hand.Phase ~= "Idle"
		setRigVisible(hand.Rig, active)
		if active ~= self.ArmHidden[side] then
			self:ApplyArmVisibility(side, active)
		end
		if active then
			drawArm(
				hand.Rig,
				self:ShoulderWorld(side),
				hand.Position,
				self:HandTension(hand),
				hand.Wobble.Position,
				self.RenderCFrame,
				hand.Sign,
				self.GloveColor
			)
		end
	end
end

-- ── Предпросмотр траектории ─────────────────────────────────────────────────

function Controller.PredictPath(
	self: ElasticSlingshotController,
	startPosition: Vector3,
	startVelocity: Vector3,
	ball: boolean
): ({ Knot }, PathEnd?, { Vector3 })
	local knots: { Knot } = { { P = startPosition, V = startVelocity, T = 0, BreakAfter = false } }
	local smashPoints: { Vector3 } = {}
	local filter: { Instance } = { self.RigModel, self.MarkerFolder, KineticVFX.GetFolder() }
	local character = self.Character
	if character then
		table.insert(filter, character)
	end
	self.PreviewParams.FilterDescendantsInstances = filter

	local stepTime = PhysicsConfig.PreviewStep
	local steps = math.floor(PhysicsConfig.PreviewDuration / stepTime)
	local radius = PhysicsConfig.BodyRadius
	local gravity = StretchPhysics.Gravity()
	local position, velocity = startPosition, startVelocity
	local bounces = 0
	local t = 0
	for index = 1, steps do
		velocity = StretchPhysics.ClampSpeed(velocity + (gravity + StretchPhysics.Drag(velocity)) * stepTime, PhysicsConfig.MaxFlightSpeed)
		local displacement = velocity * stepTime
		local hit = workspace:Spherecast(position, radius, displacement, self.PreviewParams)
		t += stepTime
		if hit then
			local travel = math.max(hit.Distance - PhysicsConfig.SkinWidth, 0)
			position += displacement.Unit * travel
			local part = hit.Instance
			local normal = hit.Normal
			if part:HasTag(Tags.Gong) then
				table.insert(knots, { P = position, V = velocity, T = t, BreakAfter = false })
				return knots, { Position = hit.Position, Normal = normal, Kind = "Gong" }, smashPoints
			end
			local smashable = false
			if part:HasTag(Tags.Smashable) and part:GetAttribute("OwnerUserId") == self.Player.UserId then
				local durability = part:GetAttribute("Durability")
				if typeof(durability) == "number" then
					smashable = StretchPhysics.CanSmash(durability, self.Params.ImpactMass, StretchPhysics.ImpactSpeed(velocity, normal))
				end
			end
			local bouncy = part:HasTag(Tags.Bouncy)
			if smashable then
				table.insert(smashPoints, hit.Position)
				table.insert(filter, part)
				self.PreviewParams.FilterDescendantsInstances = filter
				position += displacement.Unit * math.max(displacement.Magnitude - travel, 0)
			elseif (ball or bouncy) and bounces < PhysicsConfig.PreviewMaxBounces and -velocity:Dot(normal) > PhysicsConfig.BounceMinNormalSpeed then
				table.insert(knots, { P = position, V = velocity, T = t, BreakAfter = true })
				local restitution = if bouncy then PhysicsConfig.BouncySurfaceRestitution else self.Params.Restitution
				velocity = StretchPhysics.Reflect(velocity, normal, restitution, if bouncy then 1 else PhysicsConfig.BallTangentKeep)
				position += normal * PhysicsConfig.SkinWidth
				bounces += 1
				table.insert(knots, { P = position, V = velocity, T = t, BreakAfter = false })
			else
				table.insert(knots, { P = position, V = velocity, T = t, BreakAfter = false })
				local kind = if part:HasTag(Tags.Smashable) then "Block" else "Solid"
				return knots, { Position = hit.Position, Normal = normal, Kind = kind }, smashPoints
			end
		else
			position += displacement
		end
		if index % PhysicsConfig.PreviewKnotEvery == 0 then
			table.insert(knots, { P = position, V = velocity, T = t, BreakAfter = false })
		end
	end
	if knots[#knots].T < t then
		table.insert(knots, { P = position, V = velocity, T = t, BreakAfter = false })
	end
	return knots, nil, smashPoints
end

function Controller.HidePreview(self: ElasticSlingshotController)
	for _, beam in self.TrajectoryBeams do
		beam.Enabled = false
	end
	self.ImpactMarker.Transparency = 1
	for _, marker in self.SmashMarkers do
		marker.Transparency = 1
	end
end

-- Дуга из сегментов Эрмита → кубики Безье на Beam (для параболы без сопротивления — точно)
function Controller.DrawPath(self: ElasticSlingshotController, knots: { Knot }, pathEnd: PathEnd?, smashPoints: { Vector3 })
	local beamIndex = 0
	local totalTime = math.max(knots[#knots].T, 1e-3)
	for index = 1, #knots - 1 do
		local a, b = knots[index], knots[index + 1]
		local segmentTime = b.T - a.T
		if not a.BreakAfter and segmentTime > 1e-4 and beamIndex < TRAJECTORY_SEGMENTS then
			beamIndex += 1
			local beam = self.TrajectoryBeams[beamIndex]
			local startAttachment = self.TrajectoryAttachments[beamIndex * 2 - 1]
			local endAttachment = self.TrajectoryAttachments[beamIndex * 2]
			local c1, c2 = Bezier.FromHermite(a.P, a.V, b.P, b.V, segmentTime)
			startAttachment.WorldCFrame = axisFrame(a.P, c1 - a.P)
			endAttachment.WorldCFrame = axisFrame(b.P, b.P - c2)
			beam.CurveSize0 = (c1 - a.P).Magnitude
			beam.CurveSize1 = (b.P - c2).Magnitude
			local f0, f1 = a.T / totalTime, b.T / totalTime
			beam.Transparency = NumberSequence.new(0.05 + 0.7 * f0, 0.05 + 0.7 * f1)
			beam.Width0 = 0.6 - 0.32 * f0
			beam.Width1 = 0.6 - 0.32 * f1
			beam.Enabled = true
		end
	end
	for index = beamIndex + 1, TRAJECTORY_SEGMENTS do
		self.TrajectoryBeams[index].Enabled = false
	end

	local marker = self.ImpactMarker
	if pathEnd then
		marker.CFrame = axisFrame(pathEnd.Position + pathEnd.Normal * 0.1, pathEnd.Normal)
		marker.Color = MARKER_COLORS[pathEnd.Kind] or WHITE
		marker.Transparency = 0.2
	else
		marker.Transparency = 1
	end
	for index, smashMarker in self.SmashMarkers do
		local point = smashPoints[index]
		if point then
			smashMarker.CFrame = CFrame.new(point)
			smashMarker.Transparency = 0.1
		else
			smashMarker.Transparency = 1
		end
	end
end

function Controller.UpdatePreview(self: ElasticSlingshotController, dt: number)
	local charging = self.State == "Charge" and self.Tension > 0.02
	local grappling = self.State == "Air" and self:AnyAttached()
	if not charging and not grappling then
		self:HidePreview()
		self.PreviewTimer = 0
		return
	end
	self.PreviewTimer -= dt
	if self.PreviewTimer > 0 then
		return
	end
	self.PreviewTimer = PhysicsConfig.PreviewRefreshInterval
	local startVelocity = self.SimVelocity
	if charging then
		startVelocity = StretchPhysics.SlingshotLaunch(self.SimPosition, self:CollectBands(), self.Params)
	end
	local knots, pathEnd, smashPoints = self:PredictPath(self.SimPosition, startVelocity, self.BallHeld)
	self:DrawPath(knots, pathEnd, smashPoints)
end

-- ── Другие игроки (визуал по ретрансляции сервера) ─────────────────────────

function Controller.GetPeer(self: ElasticSlingshotController, player: Player): PeerState
	local existing = self.Peers[player]
	if existing then
		return existing
	end
	local glove = GloveConfig.Get(GloveConfig.DefaultGlove)
	local hands = {} :: { [Types.HandSide]: PeerHand }
	for _, side in HAND_SIDES do
		hands[side] = {
			Active = false,
			Point = Vector3.zero,
			Rig = createArmRig(self.RigAnchor, self.PeerModel, glove.Color, glove.Material, "Peer" .. player.UserId .. side),
		}
	end
	local ballPart = newPart(
		"PeerBall" .. player.UserId,
		Enum.PartType.Block,
		Vector3.one * PhysicsConfig.BallVisualRadius * 2,
		glove.Color,
		glove.Material,
		self.PeerModel
	)
	ballPart.CFrame = HIDDEN_CFRAME
	for _, hand in hands do
		hand.Rig.Glove.CFrame = HIDDEN_CFRAME
		hand.Rig.Cuff.CFrame = HIDDEN_CFRAME
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = ballPart
	local peer: PeerState = {
		Player = player,
		Hands = hands,
		Ball = false,
		BallPart = ballPart,
		BodyHidden = false,
	}
	self.Peers[player] = peer
	return peer
end

function Controller.RemovePeer(self: ElasticSlingshotController, player: Player)
	local peer = self.Peers[player]
	if peer == nil then
		return
	end
	for _, hand in peer.Hands do
		destroyArmRig(hand.Rig)
	end
	peer.BallPart:Destroy()
	self.Peers[player] = nil
end

function Controller.OnPeerArmVisual(self: ElasticSlingshotController, player: Player, side: string, active: boolean, point: Vector3?)
	if player == self.Player then
		return
	end
	local peer = self:GetPeer(player)
	if side == "Ball" then
		peer.Ball = active
		return
	end
	local hand = if side == "Left" then peer.Hands.Left elseif side == "Right" then peer.Hands.Right else nil
	if hand then
		hand.Active = active
		if point then
			hand.Point = point
		end
	end
end

local function setCharacterHidden(character: Model, hidden: boolean)
	local modifier = if hidden then 1 else 0
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.LocalTransparencyModifier = modifier
		elseif descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = modifier
		end
	end
end

function Controller.UpdatePeers(self: ElasticSlingshotController)
	for player, peer in self.Peers do
		if player.Parent == nil then
			self:RemovePeer(player)
			continue
		end
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local gloveAttribute = player:GetAttribute("Glove")
		local glove = GloveConfig.Get(if typeof(gloveAttribute) == "string" then gloveAttribute else nil)
		if character == nil or root == nil or not root:IsA("BasePart") then
			for _, hand in peer.Hands do
				setRigVisible(hand.Rig, false)
			end
			peer.BallPart.Transparency = 1
			continue
		end
		local frame = root.CFrame
		for _, side in HAND_SIDES do
			local hand = peer.Hands[side]
			setRigVisible(hand.Rig, hand.Active)
			if hand.Active then
				local sign = if side == "Left" then -1 else 1
				local shoulder = frame:PointToWorldSpace(Vector3.new(sign * 1.5, 1.1, 0))
				local length = (hand.Point - shoulder).Magnitude
				hand.Rig.Glove.Color = glove.Color
				drawArm(hand.Rig, shoulder, hand.Point, math.clamp((length - 12) / 60, 0, 1), Vector3.zero, frame, sign, glove.Color)
			end
		end
		if peer.Ball ~= peer.BodyHidden then
			peer.BodyHidden = peer.Ball
			setCharacterHidden(character, peer.Ball)
		end
		if peer.Ball then
			local velocity = root.AssemblyLinearVelocity
			local axis = if velocity.Magnitude > 5 then velocity.Unit else Vector3.xAxis
			peer.BallPart.CFrame = axisFrame(frame.Position, axis)
			peer.BallPart.Color = glove.Color
			peer.BallPart.Transparency = 0
		elseif peer.BallPart.Transparency < 1 then
			peer.BallPart.Transparency = 1
			peer.BallPart.CFrame = HIDDEN_CFRAME
		end
	end
end

-- ── Персонаж ────────────────────────────────────────────────────────────────

function Controller.UnbindCharacter(self: ElasticSlingshotController)
	for _, connection in self.CharacterConnections do
		connection:Disconnect()
	end
	table.clear(self.CharacterConnections)
	local track = self.FallTrack
	if track then
		track:Stop(0)
		track:Destroy()
	end
	self.FallTrack = nil
	self.Character = nil
	self.Humanoid = nil
	self.Root = nil
	self.State = "Walk"
	self.BallActive = false
	self.BallHeld = false
	self.BodyHidden = false
	for _, hand in self.Hands do
		hand.Phase = "Idle"
		hand.Held = false
		hand.AnchorPart = nil
		setRigVisible(hand.Rig, false)
	end
	self.ArmHidden.Left = false
	self.ArmHidden.Right = false
	self.BallPart.Transparency = 1
	self.AimMarker.Transparency = 1
	self:HidePreview()
end

function Controller.BindCharacter(self: ElasticSlingshotController, character: Model)
	self:UnbindCharacter()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if humanoid == nil or root == nil or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	if self.Player.Character ~= character then
		return
	end
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local torso = character:WaitForChild(if isR15 then "UpperTorso" else "Torso", 5)

	self.Character = character
	self.Humanoid = humanoid
	self.Root = root
	self.RootHeight = if isR15 then humanoid.HipHeight + root.Size.Y * 0.5 else root.Size.Y * 0.5 + 2

	if torso and torso:IsA("BasePart") then
		local torsoInRoot = root.CFrame:ToObjectSpace(torso.CFrame)
		for _, side in HAND_SIDES do
			local sign = if side == "Left" then -1 else 1
			self.ShoulderOffsets[side] = torsoInRoot:PointToWorldSpace(Vector3.new(sign * torso.Size.X * 0.5, torso.Size.Y * 0.28, 0))
		end
	end

	for _, side in HAND_SIDES do
		local list: { BasePart } = {}
		for _, name in ARM_PART_NAMES[side] do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				table.insert(list, part)
			end
		end
		self.ArmParts[side] = list
	end
	self.BodyDirty = true

	local filter: { Instance } = { character, self.RigModel, self.PeerModel, self.MarkerFolder, KineticVFX.GetFolder() }
	self.CastParams.FilterDescendantsInstances = filter
	self.AimParams.FilterDescendantsInstances = filter

	self.RenderCFrame = root.CFrame
	self.SimPosition = root.Position
	self.LastWritten = root.Position
	self.Accumulator = 0
	self.Combo = 0

	table.insert(
		self.CharacterConnections,
		humanoid.Died:Connect(function()
			self:AbortCustom()
			self:UnbindCharacter()
		end)
	)
	table.insert(
		self.CharacterConnections,
		character.DescendantAdded:Connect(function()
			self.BodyDirty = true
		end)
	)
end

-- ── Кадр ────────────────────────────────────────────────────────────────────

function Controller.ExpirePredictions(self: ElasticSlingshotController, now: number)
	for obstacleId, prediction in self.Predictions do
		if now > prediction.ExpiresAt then
			prediction.Restore()
			self.Predictions[obstacleId] = nil
		end
	end
end

function Controller.OnRenderStep(self: ElasticSlingshotController, frameDt: number)
	local dt = math.min(frameDt, 0.1)
	local now = os.clock()
	self:UpdatePeers()

	local root, humanoid = self.Root, self.Humanoid
	if root == nil or humanoid == nil or humanoid.Health <= 0 or root.Parent == nil then
		self.AimMarker.Transparency = 1
		self:HidePreview()
		return
	end

	self:ExpirePredictions(now)
	self:UpdateAim()

	if self.State == "Walk" then
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local landedAt = self.LandedAt
		if landedAt and grounded and now - landedAt > PhysicsConfig.ComboRestTime then
			self.Combo = 0
			self.LandedAt = nil
		end
		if self.BallHeld and not grounded then
			self:EnterCustom("Air", root.AssemblyLinearVelocity)
		end
	else
		-- кто-то (сервер, сброс, спавн) переставил персонажа — не спорим с ним
		local drift = (root.Position - self.LastWritten).Magnitude
		if drift > math.max(TELEPORT_DRIFT_MIN, self.SimVelocity.Magnitude * dt * 4 + 12) then
			self:AbortCustom()
		end
	end

	if self.State ~= "Walk" then
		local fixed = PhysicsConfig.FixedTimestep
		self.Accumulator += dt
		local steps = 0
		while self.Accumulator >= fixed and steps < PhysicsConfig.MaxSubstepsPerFrame do
			self.PrevPosition = self.SimPosition
			self.PrevRotation = self.SimRotation
			self:Simulate(fixed)
			self.Accumulator -= fixed
			steps += 1
			if self.State == "Walk" then
				break
			end
		end
		if steps >= PhysicsConfig.MaxSubstepsPerFrame then
			self.Accumulator = 0 -- защита от «спирали смерти» на просадках FPS
		end
	end

	if self.State ~= "Walk" then
		local alpha = math.clamp(self.Accumulator / PhysicsConfig.FixedTimestep, 0, 1)
		local position = self.PrevPosition:Lerp(self.SimPosition, alpha)
		local rotation = self.PrevRotation:Lerp(self.SimRotation, alpha)
		local frame = CFrame.new(position) * rotation
		root.CFrame = frame
		root.AssemblyLinearVelocity = self.SimVelocity
		root.AssemblyAngularVelocity = Vector3.zero
		self.LastWritten = position
		self.RenderCFrame = frame
	else
		self.RenderCFrame = root.CFrame
		self.SimPosition = root.Position
	end

	self:UpdateHands(dt)
	self:UpdateBall(dt)
	self:RenderArms()
	self:UpdatePreview(dt)

	local speed = self:GetSpeed()
	self.Camera:SetSpeed(speed)
	if self.State == "Walk" then
		self.Tension = 0
	end
	if math.abs(self.Tension - self.LastTensionSent) > 0.01 then
		self.LastTensionSent = self.Tension
		self.Signals.TensionChanged:Fire(self.Tension)
	end
end

-- ── Ввод ────────────────────────────────────────────────────────────────────

function Controller.BindInput(self: ElasticSlingshotController)
	local function armAction(side: Types.HandSide)
		return function(_: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				if self.Camera:IsMouseFree() then
					return Enum.ContextActionResult.Pass -- курсор освобождён (ALT): клики идут в интерфейс
				end
				self:OnArmPressed(side)
				return Enum.ContextActionResult.Sink
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				self:OnArmReleased(side)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end
	end

	ContextActionService:BindActionAtPriority(
		ACTION_LEFT,
		armAction("Left"),
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonL2
	)
	ContextActionService:BindActionAtPriority(
		ACTION_RIGHT,
		armAction("Right"),
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindActionAtPriority(ACTION_BALL, function(_: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			local humanoid = self.Humanoid
			local airborne = self.State ~= "Walk" or (humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air)
			if airborne then
				self.BallHeld = true
				self.BallSink = true
				return Enum.ContextActionResult.Sink
			end
			self.BallSink = false
			return Enum.ContextActionResult.Pass -- на земле пробел = обычный прыжок
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			self.BallHeld = false
			local sunk = self.BallSink
			self.BallSink = false
			return if sunk then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Pass
	end, false, ACTION_PRIORITY, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
end

-- ── Запуск / остановка ──────────────────────────────────────────────────────

function Controller.Start(self: ElasticSlingshotController)
	if self.Started then
		return
	end
	self.Started = true
	self:RefreshParams()

	local player = self.Player
	table.insert(
		self.Connections,
		player.AttributeChanged:Connect(function(attribute: string)
			if string.sub(attribute, 1, 5) == "Stat_" or attribute == "Glove" then
				self:RefreshParams()
			end
		end)
	)

	for _, instance in CollectionService:GetTagged(Tags.GrabPoint) do
		if instance:IsA("BasePart") then
			self.GrabPoints[instance] = true
		end
	end
	table.insert(
		self.Connections,
		CollectionService:GetInstanceAddedSignal(Tags.GrabPoint):Connect(function(instance: Instance)
			if instance:IsA("BasePart") then
				self.GrabPoints[instance] = true
			end
		end)
	)
	table.insert(
		self.Connections,
		CollectionService:GetInstanceRemovedSignal(Tags.GrabPoint):Connect(function(instance: Instance)
			if instance:IsA("BasePart") then
				self.GrabPoints[instance] = nil
			end
		end)
	)

	table.insert(
		self.Connections,
		Net.SmashResult.OnClientEvent:Connect(function(obstacleId: string, accepted: boolean, loot: number, _reason: string?)
			local prediction = self.Predictions[obstacleId]
			self.Predictions[obstacleId] = nil
			if accepted then
				if loot > 0 then
					self.Signals.LootGained:Fire(loot)
				end
			elseif prediction then
				prediction.Restore() -- сервер не подтвердил: стена возвращается
			end
		end)
	)
	table.insert(
		self.Connections,
		Net.ControllerReset.OnClientEvent:Connect(function(target: CFrame?)
			self:HardReset(target)
		end)
	)
	table.insert(
		self.Connections,
		Net.PeerArmVisual.OnClientEvent:Connect(function(peer: Player, side: string, active: boolean, point: Vector3?)
			self:OnPeerArmVisual(peer, side, active, point)
		end)
	)
	table.insert(
		self.Connections,
		Players.PlayerRemoving:Connect(function(leaving: Player)
			self:RemovePeer(leaving)
		end)
	)
	table.insert(
		self.Connections,
		player.CharacterAdded:Connect(function(character: Model)
			self:BindCharacter(character)
		end)
	)
	local character = player.Character
	if character then
		task.spawn(function()
			self:BindCharacter(character)
		end)
	end

	self:BindInput()
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Input.Value + 5, function(dt: number)
		self:OnRenderStep(dt)
	end)
end

function Controller.Destroy(self: ElasticSlingshotController)
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	ContextActionService:UnbindAction(ACTION_LEFT)
	ContextActionService:UnbindAction(ACTION_RIGHT)
	ContextActionService:UnbindAction(ACTION_BALL)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	self:AbortCustom()
	self:UnbindCharacter()
	for player in self.Peers do
		self:RemovePeer(player)
	end
	local signals: { [string]: any } = self.Signals :: any
	for _, signal in signals do
		signal:DisconnectAll()
	end
	self.RigModel:Destroy()
	self.PeerModel:Destroy()
	self.MarkerFolder:Destroy()
	self.Started = false
end

return Controller
