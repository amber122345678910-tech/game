--!strict
--[[
	StarterPlayer.StarterPlayerScripts.CoreClient
	Клиент CORE ROULETTE:
	  • процедурный брутальный ScreenGui (баннер, статистика, банк, ростер, 3 кнопки, мини-игра);
	  • камера на пружинах: свободная / за столом (параллакс мыши) / крупный план ядра / тряска;
	  • физика мини-игры "Magnetic Fuel Rod Extraction" и телеметрия 15 Гц;
	  • плавный рендер клешни и стержня для всех зрителей, искры, мерцание света, звук.

	Всё анимируется пружинами (ReplicatedStorage.Spring) — никаких линейных твинов.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Spring = require(ReplicatedStorage:WaitForChild("Spring"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

------------------------------------------------------------------------
-- НАСТРОЙКИ ОЩУЩЕНИЙ (см. Game Feel Tuning Guide в README)
------------------------------------------------------------------------

local FEEL = {
	-- Курсор натяжения
	CursorLift = 5.4, -- ускорение вверх при удержании
	CursorGravity = 2.6, -- "вес" курсора вниз
	CursorDamping = 2.0, -- вязкость
	CursorMaxSpeed = 2.0, -- должно быть < CursorMaxSpeed сервера
	TremorBase = 0.5, -- сила дрожи (умножается на Drift и нестабильность)
	TelemetryInterval = 0.065,

	-- Камера
	CameraSpeed = 7.5,
	CameraFocusSpeed = 10,
	FovFree = 70,
	FovSeated = 62,
	FovSpectateExtract = 54,
	FovExtract = 46,
	ParallaxStrength = 1.4,
	ShakeMaxAngle = 4.5, -- градусов при trauma = 1
	ShakeFrequency = 22,
	TraumaDecay = 1.3, -- в секунду
	ScrapeTrauma = 0.9, -- trauma/с при скрежете (активный игрок)
	DetonationTrauma = 1,
	FovPunchDetonation = 140, -- импульс скорости FOV
	FovPunchScrape = 30,

	-- Клешня и стержень
	RodLift = 3.2,
	HeadTremble = 0.4,

	-- UI
	HoverScale = 1.07,
	PressImpulse = -3.5,
}

------------------------------------------------------------------------
-- ССЫЛКИ НА МИР
------------------------------------------------------------------------

local Remotes = ReplicatedStorage:WaitForChild("CoreRemotes") :: Folder
local PlayerAction = Remotes:WaitForChild("PlayerAction") :: RemoteEvent
local GameStateUpdate = Remotes:WaitForChild("GameStateUpdate") :: RemoteEvent
local MicroGameStatus = Remotes:WaitForChild("MicroGameStatus") :: RemoteEvent
local CoreDetonate = Remotes:WaitForChild("CoreDetonate") :: RemoteEvent
local ReplicateManipulator = Remotes:WaitForChild("ReplicateManipulator") :: UnreliableRemoteEvent

-- Баланс публикует сервер атрибутами на CoreRemotes (единый источник правды)
local function cfg(name: string, default: number): number
	local v = Remotes:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local bunker = Workspace:WaitForChild("CoreRouletteBunker") :: Model
local coreModel = bunker:WaitForChild("Core") :: Model
local coreNeon = coreModel:WaitForChild("CoreNeon") :: BasePart
local coreLight = coreNeon:WaitForChild("CoreLight") :: PointLight
local coreCap = coreModel:WaitForChild("Cap") :: BasePart
local rimSparks = coreCap:WaitForChild("RimAttachment"):WaitForChild("RimSparks") :: ParticleEmitter
local steam = coreCap:WaitForChild("SteamAttachment"):WaitForChild("Steam") :: ParticleEmitter

local manipModel = bunker:WaitForChild("Manipulator") :: Model
local pivotPart = manipModel:WaitForChild("ShoulderPivot") :: BasePart
local sleevePart = manipModel:WaitForChild("Sleeve") :: BasePart
local pistonPart = manipModel:WaitForChild("Piston") :: BasePart
local headPart = manipModel:WaitForChild("ManipulatorHead") :: BasePart
local tipAttachment = headPart:WaitForChild("TipAttachment") :: Attachment
local clawSparks = tipAttachment:WaitForChild("ClawSparks") :: ParticleEmitter
local arcLight = tipAttachment:WaitForChild("ArcLight") :: PointLight
local fingers: { BasePart } = {}
for i = 1, 3 do
	table.insert(fingers, manipModel:WaitForChild("Finger" .. i) :: BasePart)
end

local lampModel = bunker:WaitForChild("Lamp") :: Model
local lampHinge = lampModel:WaitForChild("Hinge") :: BasePart

local flashCC = Lighting:WaitForChild("CoreFlash") :: ColorCorrectionEffect

local function attrVector(name: string, fallback: Vector3): Vector3
	local v = bunker:GetAttribute(name)
	if typeof(v) == "Vector3" then
		return v
	end
	return fallback
end

local CORE_CENTER = attrVector("CoreCenter", Vector3.new(0, 5.9, 0))
local PIVOT_POS = attrVector("PivotPos", Vector3.new(0, 15.2, -6.5))
local HEAD_REST = attrVector("HeadRest", Vector3.new(0, 12, -2.2))
local LAMP_HINGE = attrVector("LampHinge", Vector3.new(0, 23.8, 0))
local ROD_LENGTH = (bunker:GetAttribute("RodLength") :: number?) or 5

type RodInfo = { Model: Model, Root: BasePart, Rest: CFrame }
local rods: { RodInfo } = {}
local rodsFolder = coreModel:WaitForChild("FuelRods")
for i = 1, 3 do
	local m = rodsFolder:WaitForChild("Rod" .. i) :: Model
	local root = m:WaitForChild("RodRoot") :: BasePart
	local rest = root:GetAttribute("RestCFrame")
	table.insert(rods, { Model = m, Root = root, Rest = if typeof(rest) == "CFrame" then rest else root.CFrame })
end

local fissures: { BasePart } = {}
for _, child in coreModel:GetChildren() do
	if child:IsA("BasePart") and child:GetAttribute("Fissure") then
		table.insert(fissures, child)
	end
end

type SeatRef = { Index: number, Seat: Seat, Outward: Vector3 }
local seatRefs: { SeatRef } = {}
local chairsFolder = bunker:WaitForChild("Chairs")
for i = 1, 4 do
	local seat = chairsFolder:WaitForChild("Chair" .. i):WaitForChild("Seat") :: Seat
	local flat = Vector3.new(seat.Position.X, 0, seat.Position.Z)
	table.insert(seatRefs, { Index = i, Seat = seat, Outward = if flat.Magnitude > 0 then flat.Unit else Vector3.new(1, 0, 0) })
end

type BeaconRef = { Dome: BasePart, Light: SpotLight, Base: CFrame }
local beacons: { BeaconRef } = {}
local beaconFolder = bunker:WaitForChild("Beacons")
for i = 1, 3 do
	local dome = beaconFolder:WaitForChild("BeaconDome" .. i) :: BasePart
	table.insert(beacons, { Dome = dome, Light = dome:WaitForChild("BeaconLight") :: SpotLight, Base = dome.CFrame })
end

local function coreSound(name: string): Sound
	return coreNeon:WaitForChild(name) :: Sound
end
local SFX = {
	Hum = coreSound("Hum"),
	Geiger = coreSound("Geiger"),
	Scrape = coreSound("Scrape"),
	Clunk = coreSound("Clunk"),
	Explosion = coreSound("Explosion"),
	Siren = coreSound("Siren"),
	Overclock = coreSound("Overclock"),
	Eject = coreSound("Eject"),
	Servo = coreSound("Servo"),
}

local function uiSound(name: string, id: string, volume: number, speed: number): Sound
	local s = Instance.new("Sound")
	s.Name = "CoreUI_" .. name
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Parent = SoundService
	return s
end
local UISFX = {
	Hover = uiSound("Hover", "rbxasset://sounds/volume_slider.ogg", 0.35, 1.7),
	Click = uiSound("Click", "rbxasset://sounds/action_jump_land.mp3", 0.7, 1.9),
	Deny = uiSound("Deny", "rbxasset://sounds/volume_slider.ogg", 0.7, 0.5),
	Tick = uiSound("Tick", "rbxasset://sounds/volume_slider.ogg", 0.5, 1.1),
	Turn = uiSound("Turn", "rbxasset://sounds/impact_water.mp3", 0.5, 1.4),
}

------------------------------------------------------------------------
-- ТИПЫ И СОСТОЯНИЕ
------------------------------------------------------------------------

type SweetParams = { Phase1: number, Phase2: number, Phase3: number, Speed: number, HalfWidth: number }

type RosterEntry = { UserId: number, Name: string, Seat: number, Status: string }

type ClientState = {
	Phase: string,
	PhaseEndsAt: number,
	PhaseTotal: number,
	Pot: number,
	Instability: number,
	Overclock: number,
	Cycle: number,
	MaxCycles: number,
	ActiveUserId: number,
	ActiveName: string,
	ActiveSeat: number,
	Participants: { RosterEntry },
	MatchActive: boolean,
	StatusLine: string,
	Seated: number,
	CurrentDrift: number,
	DriftNext: number,
}

type MicroState = {
	Active: boolean,
	IsMine: boolean,
	UserId: number,
	Name: string,
	StartTime: number,
	Duration: number,
	Grace: number,
	Params: SweetParams,
	Drift: number,
	Rod: number,
	Cursor: number,
	CursorVel: number,
	ServerProgress: number,
	ServerInstability: number,
	LocalScraping: boolean,
	ServerScraping: boolean,
	JitterX: number,
	JitterZ: number,
	LastSend: number,
	NoiseSeed: number,
}

local S: ClientState = {
	Phase = "LOBBY",
	PhaseEndsAt = 0,
	PhaseTotal = 1,
	Pot = 0,
	Instability = 0,
	Overclock = 1,
	Cycle = 0,
	MaxCycles = 5,
	ActiveUserId = 0,
	ActiveName = "",
	ActiveSeat = 0,
	Participants = {},
	MatchActive = false,
	StatusLine = "",
	Seated = 0,
	CurrentDrift = 1,
	DriftNext = 1,
}

local MG: MicroState = {
	Active = false,
	IsMine = false,
	UserId = 0,
	Name = "",
	StartTime = 0,
	Duration = 7,
	Grace = 0.8,
	Params = { Phase1 = 0, Phase2 = 0, Phase3 = 0, Speed = 1, HalfWidth = 0.11 },
	Drift = 1,
	Rod = 1,
	Cursor = 0,
	CursorVel = 0,
	ServerProgress = 0,
	ServerInstability = 0,
	LocalScraping = false,
	ServerScraping = false,
	JitterX = 0,
	JitterZ = 0,
	LastSend = 0,
	NoiseSeed = 0,
}

local rng = Random.new()

------------------------------------------------------------------------
-- УТИЛИТЫ
------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function formatMoney(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-$" else "$") .. out
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ДОЛЖНО совпадать с сервером.
local function sweetCenter(t: number, p: SweetParams): number
	local f = p.Speed
	local c = 0.5 + 0.26 * math.sin(t * 1.15 * f + p.Phase1) + 0.12 * math.sin(t * 2.7 * f + p.Phase2) + 0.05 * math.sin(t * 6.3 * f + p.Phase3)
	return math.clamp(c, p.HalfWidth + 0.02, 1 - p.HalfWidth - 0.02)
end

local PHOSPHOR = Color3.fromRGB(120, 255, 140)
local AMBER = Color3.fromRGB(255, 176, 48)
local RED = Color3.fromRGB(255, 60, 45)

local function instabilityColor(pct: number): Color3
	if pct < 50 then
		return PHOSPHOR:Lerp(AMBER, pct / 50)
	end
	return AMBER:Lerp(RED, math.clamp((pct - 50) / 50, 0, 1))
end

local function pitchScale(): number
	-- 0.8 .. 1.8 по мере роста нестабильности
	return 0.8 + math.clamp(S.Instability / 100, 0, 1)
end

local function playOneShot(sound: Sound, speed: number?, volume: number?)
	if speed then
		sound.PlaybackSpeed = speed
	end
	if volume then
		sound.Volume = volume
	end
	sound.TimePosition = 0
	sound:Play()
end

local function mySeatIndex(): number?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local seatPart = humanoid.SeatPart
	if not seatPart then
		return nil
	end
	for _, ref in seatRefs do
		if (ref.Seat :: Instance) == (seatPart :: Instance) then
			return ref.Index
		end
	end
	return nil
end

------------------------------------------------------------------------
-- UI: ФАБРИКИ
------------------------------------------------------------------------

local T = {
	Frame = Color3.fromRGB(14, 16, 15),
	FrameHi = Color3.fromRGB(30, 34, 32),
	Steel = Color3.fromRGB(70, 78, 72),
	Text = Color3.fromRGB(222, 232, 216),
	Dim = Color3.fromRGB(118, 134, 118),
	Mono = Enum.Font.Code,
	Head = Enum.Font.Michroma,
}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst: any = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function rivets(parent: GuiObject)
	for _, pos in { UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 0, 4), UDim2.new(0, 4, 1, -8), UDim2.new(1, -8, 1, -8) } do
		new("Frame", {
			Name = "Rivet",
			BackgroundColor3 = T.Steel,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(4, 4),
			Position = pos,
			ZIndex = 4,
		}, parent)
	end
end

-- Тёмная металлическая панель с обводкой, градиентом и заклёпками.
local function panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local f = new("Frame", {
		Name = name,
		BackgroundColor3 = T.Frame,
		BorderSizePixel = 0,
		Size = size,
		Position = position,
		AnchorPoint = anchor,
	}, parent) :: Frame
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, f)
	new("UIStroke", { Name = "Stroke", Color = T.Steel, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
		}),
	}, f)
	rivets(f)
	return f
end

local function label(parent: Instance, name: string, text: string, font: Enum.Font, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Text = text,
		Font = font,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent) :: TextLabel
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

local function scanlines(parent: GuiObject, count: number, transparency: number, zIndex: number)
	local holder = new("Frame", {
		Name = "Scanlines",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
		ClipsDescendants = true,
	}, parent) :: Frame
	for i = 0, count - 1 do
		new("Frame", {
			Name = "Line",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, i / count),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = zIndex,
		}, holder)
	end
end

-- Жёлто-чёрная полоса "hazard" через жёсткие шаги UIGradient.
local function hazardStripe(parent: Instance, accent: Color3, size: UDim2, position: UDim2, zIndex: number): Frame
	local f = new("Frame", {
		Name = "Hazard",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = size,
		Position = position,
		ZIndex = zIndex,
	}, parent) :: Frame
	local keys = {}
	local stripes = 9
	for i = 0, stripes - 1 do
		local c = if i % 2 == 0 then accent else Color3.fromRGB(12, 12, 10)
		table.insert(keys, ColorSequenceKeypoint.new(i / stripes, c))
		table.insert(keys, ColorSequenceKeypoint.new(if i == stripes - 1 then 1 else (i + 1) / stripes - 0.0005, c))
	end
	new("UIGradient", { Color = ColorSequence.new(keys), Rotation = 12 }, f)
	return f
end

------------------------------------------------------------------------
-- UI: СБОРКА HUD
------------------------------------------------------------------------

local oldHud = playerGui:FindFirstChild("CoreHUD")
if oldHud then
	oldHud:Destroy()
end
local oldFx = playerGui:FindFirstChild("CoreFX")
if oldFx then
	oldFx:Destroy()
end

local hud = new("ScreenGui", {
	Name = "CoreHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
}, playerGui) :: ScreenGui

local fxGui = new("ScreenGui", {
	Name = "CoreFX",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}, playerGui) :: ScreenGui

local responsiveScales: { UIScale } = {}
local function responsive(obj: GuiObject): UIScale
	local s = new("UIScale", { Name = "Responsive" }, obj) :: UIScale
	table.insert(responsiveScales, s)
	return s
end

-- Полноэкранные эффекты
local vignette = new("Frame", {
	Name = "DangerVignette",
	BackgroundColor3 = RED,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
}, fxGui) :: Frame
local vignetteGradient = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.22, 0.85),
		NumberSequenceKeypoint.new(0.78, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	}),
}, vignette) :: UIGradient
local whiteFlash = new("Frame", {
	Name = "WhiteFlash",
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 3,
}, fxGui) :: Frame

-- Баннер
local banner = panel(hud, "Banner", UDim2.fromOffset(620, 76), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
responsive(banner)
local phaseTag = label(banner, "PhaseTag", "LOBBY", T.Mono, 14, T.Frame, {
	BackgroundTransparency = 0,
	BackgroundColor3 = PHOSPHOR,
	Size = UDim2.fromOffset(120, 22),
	Position = UDim2.fromOffset(12, 10),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 2,
})
local bannerTitle = label(banner, "Title", "AWAITING OPERATORS", T.Head, 20, T.Text, {
	Size = UDim2.new(1, -230, 0, 28),
	Position = UDim2.fromOffset(142, 6),
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 2,
})
local bannerSub = label(banner, "Sub", "Sit at the table to join", T.Mono, 15, T.Dim, {
	Size = UDim2.new(1, -24, 0, 22),
	Position = UDim2.fromOffset(12, 38),
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 2,
})
local bannerTimer = label(banner, "Timer", "--.-", T.Mono, 26, AMBER, {
	Size = UDim2.fromOffset(80, 30),
	Position = UDim2.new(1, -92, 0, 6),
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 2,
})
local timerTrack = new("Frame", {
	Name = "TimerTrack",
	BackgroundColor3 = Color3.fromRGB(30, 30, 26),
	BorderSizePixel = 0,
	Size = UDim2.new(1, -24, 0, 4),
	Position = UDim2.new(0, 12, 1, -10),
	ZIndex = 2,
}, banner) :: Frame
local timerFill = new("Frame", {
	Name = "Fill",
	BackgroundColor3 = AMBER,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 3,
}, timerTrack) :: Frame

-- Строка статистики
local stats = panel(hud, "Stats", UDim2.fromOffset(620, 58), UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0))
responsive(stats)

local function statCell(order: number, key: string, color: Color3): (Frame, TextLabel)
	local cell = new("Frame", {
		Name = key,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.25, 0, 1, 0),
		Position = UDim2.fromScale((order - 1) * 0.25, 0),
	}, stats) :: Frame
	label(cell, "Key", key, T.Mono, 12, T.Dim, {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 6),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local value = label(cell, "Value", "--", T.Head, 19, color, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	if order > 1 then
		new("Frame", {
			Name = "Divider",
			BackgroundColor3 = T.Steel,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 2, 0.7, 0),
			Position = UDim2.fromScale(0, 0.15),
		}, cell)
	end
	return cell, value
end

local _, potValue = statCell(1, "POT ($)", AMBER)
local instabCell, instabValue = statCell(2, "CORE INSTABILITY", PHOSPHOR)
local _, overclockValue = statCell(3, "OVERCLOCK", AMBER)
local _, cycleValue = statCell(4, "CYCLE", T.Text)
local instabBar = new("Frame", {
	Name = "Bar",
	BackgroundColor3 = Color3.fromRGB(24, 30, 26),
	BorderSizePixel = 0,
	Size = UDim2.new(0.8, 0, 0, 4),
	Position = UDim2.new(0.1, 0, 1, -8),
}, instabCell) :: Frame
local instabFill = new("Frame", {
	Name = "Fill",
	BackgroundColor3 = PHOSPHOR,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(0, 1),
}, instabBar) :: Frame

-- Банк
local bank = panel(hud, "Bank", UDim2.fromOffset(220, 76), UDim2.new(1, -10, 0, 8), Vector2.new(1, 0))
local bankScale = responsive(bank)
label(bank, "Key", "SAVED BANK", T.Mono, 12, T.Dim, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 8) })
local bankValue = label(bank, "Value", "$0", T.Head, 22, PHOSPHOR, { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 24) })
local winsValue = label(bank, "Wins", "WINS 0", T.Mono, 13, AMBER, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 52) })
local bankPunch = Spring.new(1, 0.45, 18)

-- Ростер
local roster = panel(hud, "Roster", UDim2.fromOffset(230, 150), UDim2.new(0, 10, 0, 8), Vector2.new(0, 0))
responsive(roster)
label(roster, "Key", "OPERATORS", T.Mono, 12, T.Dim, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 8) })
local rosterRows: { TextLabel } = {}
for i = 1, 4 do
	table.insert(
		rosterRows,
		label(roster, "Row" .. i, string.format("0%d  ----", i), T.Mono, 15, T.Dim, {
			Size = UDim2.new(1, -24, 0, 26),
			Position = UDim2.fromOffset(12, 26 + (i - 1) * 28),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	)
end

-- Подсказка для стоящих игроков
local hint = label(hud, "SitHint", "WALK TO AN OPERATOR CHAIR  ·  [E] SIT AT TABLE", T.Mono, 16, AMBER, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(560, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundTransparency = 0.25,
	BackgroundColor3 = T.Frame,
})
responsive(hint)
new("UIStroke", { Color = AMBER, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hint)

-- Уведомление по центру + лента
local noticeLabel = label(hud, "Notice", "", T.Head, 24, T.Text, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.33),
	Size = UDim2.fromOffset(900, 44),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.4,
	TextStrokeColor3 = Color3.new(0, 0, 0),
	TextTransparency = 1,
})
local noticeScale = responsive(noticeLabel)
local noticeSpring = Spring.new(1, 0.4, 16)
local noticeAlpha = Spring.new(0, 1, 6)
local noticeHideAt = 0

local feed = new("Frame", {
	Name = "Feed",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 10, 1, -10),
	Size = UDim2.fromOffset(420, 104),
}, hud) :: Frame
responsive(feed)
local feedLines: { TextLabel } = {}
for i = 1, 4 do
	table.insert(
		feedLines,
		label(feed, "Line" .. i, "", T.Mono, 14, T.Dim, {
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, (i - 1) * 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextStrokeTransparency = 0.6,
		})
	)
end
local feedLog: { { Text: string, Color: Color3 } } = {}

------------------------------------------------------------------------
-- UI: КНОПКИ ДЕЙСТВИЙ
------------------------------------------------------------------------

type ActionButton = {
	Action: string,
	Button: TextButton,
	Stroke: UIStroke,
	Scale: UIScale,
	Title: TextLabel,
	Sub: TextLabel,
	Accent: Color3,
	ScaleSpring: Spring.Spring<number>,
	RotSpring: Spring.Spring<number>,
	GlowSpring: Spring.Spring<number>,
	Hover: boolean,
	Enabled: boolean,
}

local actionPanel = panel(hud, "Actions", UDim2.fromOffset(780, 156), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
responsive(actionPanel)
label(actionPanel, "Key", "▌ OPERATOR CONSOLE — CHOOSE YOUR MOVE", T.Mono, 13, AMBER, {
	Size = UDim2.new(1, -24, 0, 18),
	Position = UDim2.fromOffset(12, 6),
})
local actionTimerTrack = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(30, 30, 26),
	BorderSizePixel = 0,
	Size = UDim2.new(1, -24, 0, 3),
	Position = UDim2.new(0, 12, 0, 26),
}, actionPanel) :: Frame
local actionTimerFill = new("Frame", {
	BackgroundColor3 = AMBER,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
}, actionTimerTrack) :: Frame
local buttonRow = new("Frame", {
	Name = "Row",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -24, 1, -42),
	Position = UDim2.fromOffset(12, 36),
}, actionPanel) :: Frame
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 12),
}, buttonRow)

local actionButtons: { ActionButton } = {}
local actionPanelSpring = Spring.new(0, 0.7, 13)

local function makeActionButton(order: number, action: string, title: string, sub: string, accent: Color3, key: string): ActionButton
	local holder = new("Frame", {
		Name = action,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 240, 1, 0),
		LayoutOrder = order,
	}, buttonRow) :: Frame
	local button = new("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.FrameHi,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
	}, holder) :: TextButton
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, button)
	local stroke = new("UIStroke", { Color = accent, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button) :: UIStroke
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 110, 110)),
		}),
	}, button)
	local scale = new("UIScale", { Name = "Juice" }, button) :: UIScale
	label(button, "KeyBadge", key, T.Mono, 13, T.Frame, {
		BackgroundTransparency = 0,
		BackgroundColor3 = accent,
		Size = UDim2.fromOffset(26, 18),
		Position = UDim2.fromOffset(8, 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	local titleLabel = label(button, "Title", title, T.Head, 14, accent, {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	local subLabel = label(button, "Sub", sub, T.Mono, 13, T.Dim, {
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, 56),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ZIndex = 3,
	})
	hazardStripe(button, accent, UDim2.new(1, -8, 0, 5), UDim2.new(0, 4, 1, -9), 3)
	rivets(button)

	local ab: ActionButton = {
		Action = action,
		Button = button,
		Stroke = stroke,
		Scale = scale,
		Title = titleLabel,
		Sub = subLabel,
		Accent = accent,
		ScaleSpring = Spring.new(1, 0.45, 20),
		RotSpring = Spring.new(0, 0.3, 24),
		GlowSpring = Spring.new(0, 1, 14),
		Hover = false,
		Enabled = true,
	}
	table.insert(actionButtons, ab)
	return ab
end

local extractButton = makeActionButton(1, "EXTRACT", "[EXTRACT FUEL ROD]", "7s magnetic micro-game\n+$1,000 × OVERCLOCK", PHOSPHOR, "1")
local overclockButton = makeActionButton(2, "OVERCLOCK", "[OVERCLOCK CORE]", "+15% INSTAB · +$500\nNEXT TREMOR ×2", AMBER, "2")
local ejectButton = makeActionButton(3, "EJECT", "[EMERGENCY EJECT]", "BANK 40% OF POT\nAND LEAVE THE TABLE", RED, "3")

local actionLocked = false

local function choiceAvailable(): boolean
	return S.Phase == "CHOICE" and S.ActiveUserId == player.UserId and not actionLocked
end

local fovSpring: Spring.Spring<number> -- объявлена ниже, нужна для "панча" по нажатию

local function pressAction(ab: ActionButton)
	if not choiceAvailable() then
		return
	end
	if not ab.Enabled then
		ab.RotSpring:Impulse(if rng:NextNumber() < 0.5 then -90 else 90)
		ab.ScaleSpring:Impulse(-1.5)
		playOneShot(UISFX.Deny)
		return
	end
	actionLocked = true
	ab.ScaleSpring:Impulse(FEEL.PressImpulse)
	ab.RotSpring:Impulse(if rng:NextNumber() < 0.5 then -45 else 45)
	ab.GlowSpring:Impulse(12)
	playOneShot(UISFX.Click, 1.9 * pitchScale())
	fovSpring:Impulse(-25)
	PlayerAction:FireServer(ab.Action)
end

for _, ab in actionButtons do
	ab.Button.MouseEnter:Connect(function()
		ab.Hover = true
		ab.RotSpring:Impulse(if rng:NextNumber() < 0.5 then -12 else 12)
		if actionPanelSpring.Target > 0.5 then
			playOneShot(UISFX.Hover, 1.7 * pitchScale())
		end
	end)
	ab.Button.MouseLeave:Connect(function()
		ab.Hover = false
	end)
	ab.Button.SelectionGained:Connect(function()
		ab.Hover = true
	end)
	ab.Button.SelectionLost:Connect(function()
		ab.Hover = false
	end)
	ab.Button.Activated:Connect(function()
		pressAction(ab)
	end)
end

------------------------------------------------------------------------
-- UI: МИНИ-ИГРА
------------------------------------------------------------------------

local TUBE_H = 330

local micro = panel(hud, "MicroGame", UDim2.fromOffset(230, 470), UDim2.new(1, -16, 0.5, 30), Vector2.new(1, 0.5))
responsive(micro)
local microStroke = micro:FindFirstChild("Stroke") :: UIStroke
local microSlide = Spring.new(0, 0.75, 12)
label(micro, "Title", "MAG-LOCK EXTRACTION", T.Head, 13, PHOSPHOR, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 8) })
local microSub = label(micro, "Sub", "ROD 1 · TREMOR ×1", T.Mono, 13, T.Dim, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 30) })

local tube = new("Frame", {
	Name = "Tube",
	BackgroundColor3 = Color3.fromRGB(6, 12, 8),
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(84, TUBE_H),
	Position = UDim2.fromOffset(16, 58),
	ClipsDescendants = true,
}, micro) :: Frame
new("UIStroke", { Color = Color3.fromRGB(60, 140, 70), Thickness = 2 }, tube)
new("UIGradient", {
	Rotation = 0,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 120, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 120)),
	}),
}, tube)
for i = 1, 9 do
	new("Frame", {
		Name = "Tick",
		BackgroundColor3 = Color3.fromRGB(40, 90, 50),
		BorderSizePixel = 0,
		Size = UDim2.new(0, if i % 5 == 0 then 22 else 12, 0, 1),
		Position = UDim2.new(0, 0, i / 10, 0),
		ZIndex = 2,
	}, tube)
end
local sweetZone = new("Frame", {
	Name = "SweetSpot",
	BackgroundColor3 = PHOSPHOR,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(1, 0, 0.22, 0),
	Position = UDim2.fromScale(0, 0.5),
	ZIndex = 3,
}, tube) :: Frame
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.6),
	}),
}, sweetZone)
new("UIStroke", { Color = PHOSPHOR, Thickness = 1 }, sweetZone)
local marker = new("Frame", {
	Name = "TensionMarker",
	BackgroundColor3 = AMBER,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(1, 0, 0, 6),
	Position = UDim2.fromScale(0, 1),
	ZIndex = 5,
}, tube) :: Frame
local markerArrow = label(micro, "Arrow", "◀", T.Mono, 20, AMBER, {
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.fromOffset(20, 20),
	Position = UDim2.fromOffset(104, 58 + TUBE_H),
	ZIndex = 5,
})
scanlines(tube, 60, 0.6, 6)

local progressTube = new("Frame", {
	Name = "ProgressTube",
	BackgroundColor3 = Color3.fromRGB(10, 10, 8),
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(26, TUBE_H),
	Position = UDim2.fromOffset(130, 58),
}, micro) :: Frame
new("UIStroke", { Color = AMBER, Thickness = 2 }, progressTube)
local progressFill = new("Frame", {
	Name = "Fill",
	BackgroundColor3 = AMBER,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0),
}, progressTube) :: Frame
scanlines(progressTube, 60, 0.55, 3)
local progressLabel = label(micro, "Progress", "000%", T.Head, 16, AMBER, {
	Size = UDim2.fromOffset(64, 22),
	Position = UDim2.fromOffset(160, 58),
	TextXAlignment = Enum.TextXAlignment.Left,
})
label(micro, "ProgressKey", "EXTR.", T.Mono, 12, T.Dim, { Size = UDim2.fromOffset(60, 16), Position = UDim2.fromOffset(162, 80) })
local microInstab = label(micro, "Instab", "000%", T.Head, 16, PHOSPHOR, {
	Size = UDim2.fromOffset(64, 22),
	Position = UDim2.fromOffset(160, 110),
})
label(micro, "InstabKey", "INSTAB.", T.Mono, 12, T.Dim, { Size = UDim2.fromOffset(60, 16), Position = UDim2.fromOffset(162, 132) })
local scrapeWarn = label(micro, "ScrapeWarn", "!! SCRAPE !!", T.Mono, 13, RED, {
	Size = UDim2.fromOffset(70, 40),
	Position = UDim2.fromOffset(160, 170),
	TextWrapped = true,
	TextTransparency = 1,
})
local microTimerTrack = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(30, 30, 26),
	BorderSizePixel = 0,
	Size = UDim2.new(1, -32, 0, 5),
	Position = UDim2.new(0, 16, 0, 58 + TUBE_H + 12),
}, micro) :: Frame
local microTimerFill = new("Frame", {
	BackgroundColor3 = PHOSPHOR,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
}, microTimerTrack) :: Frame
local microHint = label(micro, "Hint", "HOLD [LMB] / [SPACE]", T.Mono, 14, T.Text, {
	Size = UDim2.new(1, -20, 0, 36),
	Position = UDim2.new(0, 10, 1, -44),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = true,
})
-- Кнопка удержания для тача (на ПК невидима, но тоже работает)
local holdButton = new("TextButton", {
	Name = "HoldPad",
	BackgroundTransparency = 1,
	Text = "",
	Size = UDim2.fromScale(1, 1),
	ZIndex = 10,
	AutoButtonColor = false,
}, micro) :: TextButton
scanlines(micro, 120, 0.82, 9)

------------------------------------------------------------------------
-- РЕАКЦИЯ НА ИЗМЕНЕНИЯ ЭКРАНА
------------------------------------------------------------------------

local function updateResponsive()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local vp = camera.ViewportSize
	local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.25)
	for _, sc in responsiveScales do
		sc.Scale = s
	end
end

------------------------------------------------------------------------
-- УВЕДОМЛЕНИЯ
------------------------------------------------------------------------

local function kindColor(kind: string): Color3
	if kind == "GOOD" then
		return PHOSPHOR
	elseif kind == "BAD" then
		return RED
	elseif kind == "WARN" then
		return AMBER
	end
	return T.Text
end

local function showNotice(text: string, kind: string)
	local color = kindColor(kind)
	noticeLabel.Text = text
	noticeLabel.TextColor3 = color
	noticeSpring.Position = 0.6
	noticeSpring.Target = 1
	noticeSpring:Impulse(4)
	noticeAlpha.Target = 1
	noticeAlpha.Position = 1
	noticeHideAt = os.clock() + 3.2

	table.insert(feedLog, 1, { Text = "> " .. text, Color = color })
	while #feedLog > #feedLines do
		table.remove(feedLog)
	end
	for i, line in feedLines do
		local entry = feedLog[i]
		line.Text = if entry then entry.Text else ""
		line.TextColor3 = if entry then entry.Color else T.Dim
		line.TextTransparency = (i - 1) * 0.22
	end
end

------------------------------------------------------------------------
-- КАМЕРА
------------------------------------------------------------------------

local camPos = Spring.new(Vector3.new(0, 10, 20), 1, FEEL.CameraSpeed)
local camFocus = Spring.new(CORE_CENTER, 1, FEEL.CameraFocusSpeed)
fovSpring = Spring.new(FEEL.FovFree, 0.5, 12)
local cameraMode = "FREE"
local appliedShake: CFrame? = nil -- тряска, наложенная поверх стандартной камеры в прошлом кадре
local trauma = 0
local shakeSeed = rng:NextNumber(0, 1000)

local function addTrauma(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

local function shakeRotation(): CFrame
	local t = os.clock() * FEEL.ShakeFrequency
	local power = trauma * trauma
	local maxAngle = math.rad(FEEL.ShakeMaxAngle) * power
	local pitch = math.noise(shakeSeed, t, 0) * maxAngle * 2
	local yaw = math.noise(shakeSeed + 31.7, t, 0) * maxAngle * 2
	local roll = math.noise(shakeSeed + 77.3, t, 0) * maxAngle * 1.4
	return CFrame.Angles(pitch, yaw, roll)
end

local function setCameraMode(mode: string)
	if mode == cameraMode then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if cameraMode == "FREE" and mode ~= "FREE" then
		-- плавный вход из текущего положения камеры
		camPos:Snap(camera.CFrame.Position)
		camFocus:Snap(camera.CFrame.Position + camera.CFrame.LookVector * 12)
		camera.CameraType = Enum.CameraType.Scriptable
	elseif mode == "FREE" then
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	cameraMode = mode
end

local function rodTopRest(index: number): Vector3
	local r = rods[index]
	if not r then
		return CORE_CENTER + Vector3.new(0, 3, 0)
	end
	return r.Rest.Position + Vector3.new(0, ROD_LENGTH * 0.5, 0)
end

local rodLift = Spring.new(0, 0.6, 9)

local function updateCamera(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local seatIndex = mySeatIndex()
	local wanted = if MG.Active and MG.IsMine then "EXTRACT" elseif seatIndex then "SEATED" else "FREE"
	setCameraMode(wanted)

	trauma = math.max(0, trauma - FEEL.TraumaDecay * dt)

	if cameraMode == "FREE" then
		fovSpring.Target = FEEL.FovFree
		camera.FieldOfView = math.clamp(fovSpring:Update(dt), 20, 110)
		if trauma > 0 then
			local shake = shakeRotation()
			camera.CFrame = camera.CFrame * shake
			appliedShake = shake
		end
		return
	end

	local seatRef = seatRefs[seatIndex or S.ActiveSeat] or seatRefs[1]
	local outward = seatRef.Outward
	local right = Vector3.yAxis:Cross(outward).Unit
	local vp = camera.ViewportSize
	local mouse = UserInputService:GetMouseLocation()
	local mx = math.clamp((mouse.X / math.max(vp.X, 1)) * 2 - 1, -1, 1)
	local my = math.clamp((mouse.Y / math.max(vp.Y, 1)) * 2 - 1, -1, 1)

	if cameraMode == "EXTRACT" then
		local rodTop = rodTopRest(MG.Rod) + Vector3.new(0, rodLift.Position, 0)
		local rodFlat = Vector3.new(rodTop.X, 0, rodTop.Z)
		local side = if rodFlat.Magnitude > 0.01 then rodFlat.Unit else outward
		local viewDir = (outward * 0.75 + side * 0.25).Unit
		camPos.Target = CORE_CENTER + viewDir * 6.2 + Vector3.new(0, 3.6, 0) + right * 1.2
		camFocus.Target = rodTop - Vector3.new(0, 0.9, 0) + right * mx * 0.3
		fovSpring.Target = FEEL.FovExtract
	else
		local seatPos = seatRef.Seat.Position
		local par = FEEL.ParallaxStrength
		camPos.Target = seatPos + outward * 4.0 + Vector3.new(0, 6.2, 0) + right * (mx * par * 0.35) + Vector3.new(0, -my * par * 0.25, 0)
		local focus = CORE_CENTER + Vector3.new(0, 0.4, 0) + right * (mx * par) + Vector3.new(0, -my * par * 0.6, 0)
		if MG.Active then
			focus = CORE_CENTER + Vector3.new(0, 1.6, 0)
			fovSpring.Target = FEEL.FovSpectateExtract
		else
			fovSpring.Target = FEEL.FovSeated
		end
		camFocus.Target = focus
	end

	local pos = camPos:Update(dt)
	local focus = camFocus:Update(dt)
	camera.FieldOfView = math.clamp(fovSpring:Update(dt), 20, 110)
	camera.CFrame = CFrame.lookAt(pos, focus) * shakeRotation()
	camera.Focus = CFrame.new(focus)
end

------------------------------------------------------------------------
-- ВВОД МИНИ-ИГРЫ
------------------------------------------------------------------------

local holdKey = false
local holdMouse = false
local holdPad = false
local activeTouches: { [InputObject]: boolean } = {}

local function isHolding(): boolean
	return holdKey or holdMouse or holdPad or next(activeTouches) ~= nil
end

local function holdAction(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local down = inputState == Enum.UserInputState.Begin
	local up = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if down then
			holdMouse = true
		elseif up then
			holdMouse = false
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if down then
			activeTouches[input] = true
		elseif up then
			activeTouches[input] = nil
		end
	else
		if down then
			holdKey = true
		elseif up then
			holdKey = false
		end
	end
	return Enum.ContextActionResult.Sink -- Space не должен поднимать игрока со стула
end

holdButton.MouseButton1Down:Connect(function()
	if MG.Active and MG.IsMine then
		holdPad = true
	end
end)
holdButton.MouseButton1Up:Connect(function()
	holdPad = false
end)
holdButton.MouseLeave:Connect(function()
	holdPad = false
end)

local function bindHold()
	ContextActionService:BindActionAtPriority(
		"CoreRouletteHold",
		holdAction,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonA,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.Touch
	)
end

local function unbindHold()
	ContextActionService:UnbindAction("CoreRouletteHold")
	holdKey = false
	holdMouse = false
	holdPad = false
	table.clear(activeTouches)
end

-- Горячие клавиши 1/2/3 для кнопок действий
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.One then
		pressAction(extractButton)
	elseif input.KeyCode == Enum.KeyCode.Two then
		pressAction(overclockButton)
	elseif input.KeyCode == Enum.KeyCode.Three then
		pressAction(ejectButton)
	end
end)

------------------------------------------------------------------------
-- ОБРАБОТКА СОСТОЯНИЯ С СЕРВЕРА
------------------------------------------------------------------------

local lastPhaseKey = ""
local lastCountdownSecond = -1

local function rebuildRoster()
	local bySeat: { [number]: RosterEntry } = {}
	for _, p in S.Participants do
		bySeat[p.Seat] = p
	end
	for i, row in rosterRows do
		local p = bySeat[i]
		local seatOccupant = seatRefs[i].Seat.Occupant
		if p then
			local mark = "  "
			local color = T.Text
			if p.UserId == S.ActiveUserId then
				mark = "▶ "
				color = AMBER
			elseif p.Status == "BLASTED" then
				mark = "✖ "
				color = RED
			elseif p.Status == "EJECTED" then
				mark = "⏏ "
				color = T.Dim
			elseif p.Status == "LEFT" then
				mark = "— "
				color = T.Dim
			elseif p.Status == "SURVIVOR" then
				mark = "★ "
				color = PHOSPHOR
			end
			row.Text = string.format("0%d %s%s", i, mark, string.upper(p.Name))
			row.TextColor3 = color
		elseif seatOccupant then
			local occCharacter = seatOccupant.Parent
			local occ = if occCharacter and occCharacter:IsA("Model") then Players:GetPlayerFromCharacter(occCharacter) else nil
			row.Text = string.format("0%d   %s (WAITING)", i, if occ then string.upper(occ.DisplayName) else "OPERATOR")
			row.TextColor3 = T.Dim
		else
			row.Text = string.format("0%d   ----", i)
			row.TextColor3 = Color3.fromRGB(70, 80, 70)
		end
	end
end

local function applyState(data: any)
	if type(data) ~= "table" then
		return
	end
	local prevActive = S.ActiveUserId
	local prevPhase = S.Phase
	S.Phase = tostring(data.Phase or "LOBBY")
	S.PhaseEndsAt = tonumber(data.PhaseEndsAt) or 0
	S.Pot = tonumber(data.Pot) or 0
	S.Instability = tonumber(data.Instability) or 0
	S.Overclock = tonumber(data.Overclock) or 1
	S.Cycle = tonumber(data.Cycle) or 0
	S.MaxCycles = tonumber(data.MaxCycles) or 5
	S.ActiveUserId = tonumber(data.ActiveUserId) or 0
	S.ActiveName = tostring(data.ActiveName or "")
	S.ActiveSeat = tonumber(data.ActiveSeat) or 0
	S.MatchActive = data.MatchActive == true
	S.StatusLine = tostring(data.StatusLine or "")
	S.Seated = tonumber(data.Seated) or 0
	S.CurrentDrift = tonumber(data.CurrentDrift) or 1
	S.DriftNext = tonumber(data.DriftNext) or 1
	local list: { RosterEntry } = {}
	if type(data.Participants) == "table" then
		for _, p in data.Participants do
			if type(p) == "table" then
				table.insert(list, {
					UserId = tonumber(p.UserId) or 0,
					Name = tostring(p.Name or "?"),
					Seat = tonumber(p.Seat) or 0,
					Status = tostring(p.Status or "ACTIVE"),
				})
			end
		end
	end
	S.Participants = list

	local phaseKey = S.Phase .. ":" .. tostring(S.PhaseEndsAt)
	if phaseKey ~= lastPhaseKey then
		lastPhaseKey = phaseKey
		S.PhaseTotal = math.max(S.PhaseEndsAt - serverNow(), 0.01)
	end

	-- Мой ход начался
	if S.Phase == "CHOICE" and S.ActiveUserId == player.UserId and (prevPhase ~= "CHOICE" or prevActive ~= player.UserId) then
		actionLocked = false
		playOneShot(UISFX.Turn, 1.3)
		fovSpring:Impulse(-40)
		for _, ab in actionButtons do
			ab.ScaleSpring.Position = 0.4
			ab.ScaleSpring:Impulse(6)
		end
	end
	if S.Phase ~= "CHOICE" then
		actionLocked = false
	end

	-- Подписи на кнопках с живыми цифрами
	local share = cfg("EjectShare", 0.4)
	local lockAt = cfg("OverclockMaxInstability", 85)
	extractButton.Sub.Text = string.format("%ds magnetic micro-game\n+%s", cfg("MicroGameTime", 7), formatMoney(cfg("ExtractReward", 1000) * S.Overclock))
	ejectButton.Sub.Text = string.format("BANK %d%% = %s\nAND LEAVE THE TABLE", math.floor(share * 100 + 0.5), formatMoney(math.floor(S.Pot * share)))
	overclockButton.Enabled = S.Instability < lockAt
	overclockButton.Sub.Text = if overclockButton.Enabled
		then string.format("+%d%% INSTAB · +%s\nNEXT TREMOR ×%d", cfg("OverclockInstability", 15), formatMoney(cfg("OverclockPot", 500)), cfg("OverclockDrift", 2))
		else string.format("LOCKED\nINSTABILITY ≥ %d%%", lockAt)

	rebuildRoster()
end

GameStateUpdate.OnClientEvent:Connect(function(kind: any, data: any)
	if kind == "STATE" then
		applyState(data)
	elseif kind == "NOTICE" and type(data) == "table" then
		showNotice(tostring(data.Text or ""), tostring(data.Kind or "INFO"))
	elseif kind == "FX" and type(data) == "table" then
		if data.Type == "OVERCLOCK" then
			playOneShot(SFX.Overclock, 1.8 * pitchScale() / 1.4)
			rimSparks:Emit(35)
			addTrauma(0.4)
			fovSpring:Impulse(60)
			coreLight.Brightness = 12
		end
	elseif kind == "LAUNCH" and type(data) == "table" then
		local victim = tonumber(data.UserId) or 0
		local velocity = data.Velocity
		if data.Kind == "EJECT" then
			playOneShot(SFX.Eject, 0.7)
			addTrauma(0.3)
		end
		if victim == player.UserId and typeof(velocity) == "Vector3" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and root:IsA("BasePart") then
				local seatPart = humanoid.SeatPart
				if seatPart then
					local seatWeld = seatPart:FindFirstChild("SeatWeld")
					if seatWeld then
						seatWeld:Destroy()
					end
				end
				humanoid.Sit = false
				humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
				root.AssemblyLinearVelocity = velocity
				task.delay(0.05, function()
					if root.Parent then
						root.AssemblyLinearVelocity = velocity
					end
				end)
				addTrauma(0.8)
				fovSpring:Impulse(120)
			end
		end
	end
end)

------------------------------------------------------------------------
-- МИНИ-ИГРА: СОБЫТИЯ
------------------------------------------------------------------------

local remoteCursor = Spring.new(0, 0.8, 18)
local remoteJitter = Spring.new(Vector3.zero, 0.7, 20)
local progressSpring = Spring.new(0, 0.9, 10)
local headSpring = Spring.new(HEAD_REST, 0.55, 15)
local gripSpring = Spring.new(0, 0.5, 14)
local lampTilt = Spring.new(Vector3.zero, 0.22, 2.6)
local flashSpring = Spring.new(0, 1, 3.2)
local coreFlash = Spring.new(0, 1, 5)
local instabDisplay = Spring.new(0, 1, 8)
local potDisplay = Spring.new(0, 1, 6)
local bankDisplay = Spring.new(0, 1, 5)
local rodPopUntil = 0
local sirenUntil = 0
local detonationStart = -100

local function startMicro(data: any)
	if type(data) ~= "table" or type(data.Params) ~= "table" then
		return
	end
	local p = data.Params
	MG.Active = true
	MG.UserId = tonumber(data.UserId) or 0
	MG.IsMine = MG.UserId == player.UserId
	MG.StartTime = tonumber(data.StartTime) or serverNow()
	MG.Duration = tonumber(data.Duration) or 7
	MG.Grace = tonumber(data.Grace) or 0.8
	MG.Params = {
		Phase1 = tonumber(p.Phase1) or 0,
		Phase2 = tonumber(p.Phase2) or 0,
		Phase3 = tonumber(p.Phase3) or 0,
		Speed = tonumber(p.Speed) or 1,
		HalfWidth = tonumber(p.HalfWidth) or 0.11,
	}
	MG.Drift = tonumber(data.Drift) or 1
	MG.Rod = math.clamp(tonumber(data.Rod) or 1, 1, #rods)
	MG.Cursor = 0
	MG.CursorVel = 0
	MG.ServerProgress = 0
	MG.LocalScraping = false
	MG.ServerScraping = false
	MG.JitterX = 0
	MG.JitterZ = 0
	MG.LastSend = 0
	MG.NoiseSeed = rng:NextNumber(0, 500)
	MG.Name = ""
	for _, entry in S.Participants do
		if entry.UserId == MG.UserId then
			MG.Name = entry.Name
		end
	end
	remoteCursor:Snap(0)
	remoteJitter:Snap(Vector3.zero)
	progressSpring:Snap(0)
	gripSpring.Target = 1

	microSub.Text = string.format("ROD %d · TREMOR ×%d", MG.Rod, MG.Drift)
	if MG.IsMine then
		microHint.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "HOLD THE SCREEN" else "HOLD [LMB] / [SPACE]"
		microHint.TextColor3 = T.Text
		bindHold()
		MicroGameStatus:FireServer("ACK", MG.StartTime)
		fovSpring:Impulse(-60)
	else
		microHint.Text = "WATCHING: " .. string.upper(MG.Name)
		microHint.TextColor3 = T.Dim
	end
	microSlide.Target = 1
	playOneShot(SFX.Clunk, 1.3)
end

local function stopMicro(data: any)
	local result = if type(data) == "table" then tostring(data.Result or "") else ""
	local wasMine = MG.IsMine
	MG.Active = false
	MG.IsMine = false
	MG.LocalScraping = false
	MG.ServerScraping = false
	gripSpring.Target = 0
	microSlide.Target = 0
	if wasMine then
		unbindHold()
	end
	if result == "SUCCESS" then
		playOneShot(SFX.Clunk, 0.55)
		rodPopUntil = os.clock() + 1.3
		addTrauma(if wasMine then 0.35 else 0.15)
		fovSpring:Impulse(if wasMine then 50 else 20)
		coreFlash.Position = 0.6
	end
end

MicroGameStatus.OnClientEvent:Connect(function(kind: any, data: any)
	if kind == "START" then
		startMicro(data)
	elseif kind == "STOP" then
		stopMicro(data)
	elseif kind == "TICK" and type(data) == "table" then
		if MG.Active and tonumber(data.UserId) == MG.UserId then
			MG.ServerProgress = tonumber(data.Progress) or MG.ServerProgress
			MG.ServerInstability = tonumber(data.Instability) or MG.ServerInstability
			MG.ServerScraping = data.Scraping == true
			S.Instability = MG.ServerInstability
		end
	end
end)

ReplicateManipulator.OnClientEvent:Connect(function(userId: any, cursor: any, jx: any, jz: any, scraping: any, progress: any)
	if not MG.Active or MG.IsMine or userId ~= MG.UserId then
		return
	end
	if typeof(cursor) == "number" then
		remoteCursor.Target = math.clamp(cursor, 0, 1)
	end
	if typeof(jx) == "number" and typeof(jz) == "number" then
		remoteJitter.Target = Vector3.new(math.clamp(jx, -1, 1), 0, math.clamp(jz, -1, 1))
	end
	if typeof(progress) == "number" then
		MG.ServerProgress = math.clamp(progress, 0, 1)
	end
	MG.ServerScraping = scraping == true
end)

------------------------------------------------------------------------
-- ДЕТОНАЦИЯ
------------------------------------------------------------------------

local function spawnShockwave(origin: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "CoreShockwave"
	folder.Parent = Workspace

	local sphere = Instance.new("Part")
	sphere.Name = "Blast"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.ForceField
	sphere.Color = Color3.fromRGB(255, 120, 60)
	sphere.Size = Vector3.one
	sphere.CFrame = CFrame.new(origin)
	sphere.Parent = folder

	local segments: { BasePart } = {}
	local count = 36
	for i = 1, count do
		local seg = Instance.new("Part")
		seg.Name = "Ring"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(255, 240, 220)
		seg.Size = Vector3.new(1, 0.3, 0.3)
		seg.Parent = folder
		table.insert(segments, seg)
	end

	local radius = Spring.new(0.5, 0.9, 4.5)
	radius.Target = 42
	radius:Impulse(80)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local age = os.clock() - started
		local r = radius:Update(dt)
		local fade = math.clamp(age / 1.1, 0, 1)
		sphere.Size = Vector3.one * math.min(r * 0.9, 34)
		sphere.Transparency = 0.2 + fade * 0.8
		local y = origin.Y - 2.2 + age * 0.4
		local segLen = 2 * math.pi * r / count * 1.05
		for i, seg in segments do
			local a = (i / count) * math.pi * 2
			local pos = Vector3.new(origin.X + math.cos(a) * r, y, origin.Z + math.sin(a) * r)
			seg.Size = Vector3.new(segLen, 0.3 + (1 - fade) * 0.6, 0.3)
			seg.CFrame = CFrame.lookAt(pos, Vector3.new(origin.X, y, origin.Z))
			seg.Transparency = fade
			seg.Color = Color3.fromRGB(255, 240, 220):Lerp(RED, fade)
		end
		if age > 1.2 then
			connection:Disconnect()
			folder:Destroy()
		end
	end)
end

CoreDetonate.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then
		return
	end
	local origin = if typeof(data.Origin) == "Vector3" then data.Origin else CORE_CENTER
	detonationStart = os.clock()
	sirenUntil = os.clock() + 4
	S.Instability = 100
	playOneShot(SFX.Explosion, 0.7, 1)
	flashSpring.Position = 1
	flashSpring.Target = 0
	coreFlash.Position = 1
	addTrauma(FEEL.DetonationTrauma)
	fovSpring:Impulse(FEEL.FovPunchDetonation)
	rimSparks:Emit(120)
	clawSparks:Emit(60)
	lampTilt:Impulse(Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)))
	headSpring:Impulse(Vector3.new(rng:NextNumber(-25, 25), 30, rng:NextNumber(-25, 25)))
	spawnShockwave(origin)
	whiteFlash.BackgroundTransparency = if tonumber(data.VictimUserId) == player.UserId then 0 else 0.35
end)

------------------------------------------------------------------------
-- ЛОКАЛЬНАЯ СИМУЛЯЦИЯ МИНИ-ИГРЫ (МОЙ ХОД)
------------------------------------------------------------------------

local lastGeiger = 0
local lastSparkBurst = 0

local function simulateMine(dt: number, t: number)
	local inst01 = math.clamp(S.Instability / 100, 0, 1)
	local holding = isHolding()

	local accel = (if holding then FEEL.CursorLift else 0) - FEEL.CursorGravity
	local seed = MG.NoiseSeed
	local tremor = (math.noise(seed, t * 3.1) * 2.6 + math.noise(seed + 7.3, t * 11.7) * 1.2) * FEEL.TremorBase * MG.Drift * (0.6 + inst01)
	accel += tremor
	MG.CursorVel += accel * dt
	MG.CursorVel *= math.exp(-FEEL.CursorDamping * dt)
	MG.CursorVel = math.clamp(MG.CursorVel, -FEEL.CursorMaxSpeed, FEEL.CursorMaxSpeed)
	MG.Cursor += MG.CursorVel * dt
	if MG.Cursor <= 0 then
		MG.Cursor = 0
		MG.CursorVel = math.max(MG.CursorVel, 0) - MG.CursorVel * 0.2
	elseif MG.Cursor >= 1 then
		MG.Cursor = 1
		MG.CursorVel = math.min(MG.CursorVel, 0) - MG.CursorVel * 0.2
	end

	-- Предсказание скрежета (мгновенный отклик; авторитет — сервер)
	local center = sweetCenter(t, MG.Params)
	local inside = math.abs(MG.Cursor - center) <= MG.Params.HalfWidth
	local wasScraping = MG.LocalScraping
	MG.LocalScraping = t >= MG.Grace and not inside
	if MG.LocalScraping and not wasScraping then
		fovSpring:Impulse(FEEL.FovPunchScrape)
		addTrauma(0.25)
	end

	-- Дрожь клешни (латеральная), уходит на сервер как jitter
	local trem = MG.Drift * (0.25 + inst01)
	local jx = math.noise(seed + 101, t * 5.3) * 1.6 * trem
	local jz = math.noise(seed + 202, t * 5.9) * 1.6 * trem
	if MG.LocalScraping then
		jx += math.noise(seed + 303, t * 23) * 1.4
		jz += math.noise(seed + 404, t * 21) * 1.4
	end
	MG.JitterX = math.clamp(jx, -1, 1)
	MG.JitterZ = math.clamp(jz, -1, 1)

	-- Телеметрия ~15 Гц
	local clock = os.clock()
	if clock - MG.LastSend >= FEEL.TelemetryInterval then
		MG.LastSend = clock
		ReplicateManipulator:FireServer(t, MG.Cursor, MG.JitterX, MG.JitterZ)
	end
end

------------------------------------------------------------------------
-- КАДР: МИР, КЛЕШНЯ, ЗВУК, UI
------------------------------------------------------------------------

local function updateManipulator(dt: number, t: number, scraping: boolean, cursor: number, jitter: Vector3, inst01: number)
	local engaged = MG.Active
	local progress = progressSpring.Position

	-- Стержень: поднимается с прогрессом, после успеха "выстреливает" и возвращается
	local popping = os.clock() < rodPopUntil
	if engaged then
		rodLift.Target = progress * FEEL.RodLift + cursor * 0.3
	elseif popping then
		rodLift.Target = FEEL.RodLift + 1.4
	else
		rodLift.Target = 0
	end
	local lift = rodLift:Update(dt)
	for i, rod in rods do
		local offset = Vector3.zero
		if i == MG.Rod and (engaged or popping or math.abs(lift) > 0.01) then
			offset = Vector3.new(0, lift, 0)
			if scraping then
				offset += Vector3.new(jitter.X, 0, jitter.Z) * 0.08
			end
		end
		rod.Root.CFrame = rod.Rest + offset
	end

	-- Цель запястья
	local target: Vector3
	if engaged or popping then
		local rodTop = rodTopRest(MG.Rod) + Vector3.new(0, lift, 0)
		target = rodTop + Vector3.new(0, 1.5, 0)
		target += Vector3.new(jitter.X, 0, jitter.Z) * (0.12 + FEEL.HeadTremble * inst01) * MG.Drift
		if scraping then
			local flat = Vector3.new(rodTop.X, 0, rodTop.Z)
			if flat.Magnitude > 0.01 then
				target += flat.Unit * 0.35
			end
		end
	else
		target = HEAD_REST + Vector3.new(math.sin(t * 0.6) * 0.25, math.sin(t * 1.1) * 0.15, math.cos(t * 0.45) * 0.2)
	end
	headSpring.Target = target
	local headPos = headSpring:Update(dt)
	local headVel = headSpring.Velocity
	local tremble = Vector3.zero
	if scraping then
		tremble = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 0.06
	end
	headPos += tremble

	local lean = CFrame.Angles(math.clamp(headVel.Z * 0.04, -0.4, 0.4), 0, math.clamp(-headVel.X * 0.04, -0.4, 0.4))
	local yaw = t * (if engaged then 0.4 else 0.15)
	headPart.CFrame = CFrame.new(headPos) * lean * CFrame.Angles(0, yaw, 0)

	-- Рука: шток от плеча до запястья + гильза
	local dir = headPos - PIVOT_POS
	local length = dir.Magnitude
	if length > 0.05 then
		local unit = dir.Unit
		pistonPart.Size = Vector3.new(length, pistonPart.Size.Y, pistonPart.Size.Z)
		pistonPart.CFrame = CFrame.lookAt((PIVOT_POS + headPos) * 0.5, headPos) * CFrame.Angles(0, math.rad(90), 0)
		local sleeveLen = math.min(3.2, length * 0.6)
		sleevePart.Size = Vector3.new(sleevePart.Size.X, sleevePart.Size.Y, sleeveLen)
		sleevePart.CFrame = CFrame.lookAt(PIVOT_POS + unit * (sleeveLen * 0.5), headPos)
	end
	pivotPart.CFrame = CFrame.lookAt(PIVOT_POS, headPos)

	-- Пальцы
	local grip = gripSpring:Update(dt)
	local open = 1 - math.clamp(grip, -0.2, 1.2)
	for i, finger in fingers do
		local a = math.rad(i * 120) + yaw
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		local rootPos = headPos + radial * 0.45 - Vector3.new(0, 0.45, 0)
		local theta = lerp(-0.12, 0.6, open) + (if scraping then rng:NextNumber(-0.08, 0.08) else 0)
		finger.CFrame = CFrame.lookAt(rootPos, rootPos + radial) * CFrame.Angles(theta, 0, 0) * CFrame.new(0, -0.65, 0)
	end

	-- Сервопривод гудит от скорости руки
	local speed = headVel.Magnitude
	SFX.Servo.Volume = math.clamp(speed * 0.035, 0, 0.35)
	SFX.Servo.PlaybackSpeed = (1.1 + math.clamp(speed * 0.05, 0, 0.6)) * pitchScale() / 1.3
	if not SFX.Servo.IsPlaying then
		SFX.Servo:Play()
	end
end

local function updateCoreFX(dt: number, t: number, scraping: boolean, inst01: number)
	local flash = coreFlash:Update(dt)
	local baseColor = instabilityColor(inst01 * 100)
	local col = baseColor:Lerp(Color3.new(1, 1, 1), math.clamp(flash, 0, 1))
	local flicker = 0
	if scraping then
		flicker = rng:NextNumber(0, 5)
		col = col:Lerp(Color3.fromRGB(190, 220, 255), rng:NextNumber(0, 0.5))
	elseif inst01 > 0.7 then
		flicker = (math.noise(t * 9, 3.3) + 0.5) * 2 * (inst01 - 0.7) * 3
	end
	coreNeon.Color = col
	for _, f in fissures do
		f.Color = col
	end
	local pulse = 1 + math.sin(t * (2 + inst01 * 10)) * (0.02 + inst01 * 0.05)
	coreNeon.Size = Vector3.one * 2 * pulse
	coreLight.Color = col
	coreLight.Brightness = lerp(coreLight.Brightness, 2.5 + inst01 * 3 + flicker + flash * 10, math.clamp(dt * 12, 0, 1))
	coreLight.Range = 18 + inst01 * 8
	steam.Rate = 3 + inst01 * 14

	-- Искры при скрежете
	if scraping and os.clock() - lastSparkBurst > 0.05 then
		lastSparkBurst = os.clock()
		clawSparks:Emit(rng:NextInteger(4, 9))
		rimSparks:Emit(rng:NextInteger(2, 5))
		arcLight.Brightness = rng:NextNumber(3, 8)
	else
		arcLight.Brightness = math.max(0, arcLight.Brightness - dt * 30)
	end

	-- Звук: гул, счётчик Гейгера, скрежет, сирена
	local ps = pitchScale()
	SFX.Hum.PlaybackSpeed = ps
	SFX.Hum.Volume = 0.25 + inst01 * 0.45
	if not SFX.Hum.IsPlaying then
		SFX.Hum:Play()
	end

	local interval = lerp(0.7, 0.06, inst01) * (if scraping then 0.35 else 1)
	if os.clock() - lastGeiger > interval * rng:NextNumber(0.5, 1.5) then
		lastGeiger = os.clock()
		playOneShot(SFX.Geiger, 2.2 * ps * rng:NextNumber(0.9, 1.15), 0.35 + inst01 * 0.4)
	end

	SFX.Scrape.Volume = lerp(SFX.Scrape.Volume, if scraping then 0.9 else 0, math.clamp(dt * 18, 0, 1))
	SFX.Scrape.PlaybackSpeed = 1.2 * ps + (if scraping then rng:NextNumber(-0.1, 0.1) else 0)
	if SFX.Scrape.Volume > 0.01 and not SFX.Scrape.IsPlaying then
		SFX.Scrape:Play()
	elseif SFX.Scrape.Volume <= 0.01 and SFX.Scrape.IsPlaying then
		SFX.Scrape:Stop()
	end

	local alarm = os.clock() < sirenUntil or S.Phase == "DETONATION" or inst01 >= 0.9
	SFX.Siren.Volume = lerp(SFX.Siren.Volume, if alarm then 0.55 else 0, math.clamp(dt * 6, 0, 1))
	SFX.Siren.PlaybackSpeed = 1.0 + 0.45 * math.sin(t * 3.4)
	if SFX.Siren.Volume > 0.01 and not SFX.Siren.IsPlaying then
		SFX.Siren:Play()
	elseif SFX.Siren.Volume <= 0.01 and SFX.Siren.IsPlaying then
		SFX.Siren:Stop()
	end

	-- Аварийные маяки
	for i, b in beacons do
		if alarm then
			b.Dome.CFrame = b.Base * CFrame.Angles(0, t * 7 + i * 2, 0)
			b.Dome.Material = Enum.Material.Neon
			b.Dome.Color = RED
			b.Light.Brightness = 7
		else
			b.Dome.CFrame = b.Base
			b.Dome.Material = Enum.Material.Glass
			b.Dome.Color = Color3.fromRGB(90, 20, 18)
			b.Light.Brightness = 0
		end
	end

	-- Вспышка детонации
	local f = math.clamp(flashSpring:Update(dt), 0, 1)
	local strobe = os.clock() - detonationStart < 1.4 and math.floor(os.clock() * 14) % 2 == 0
	flashCC.Brightness = f * 0.8
	flashCC.Contrast = f * 0.6
	flashCC.TintColor = if strobe then Color3.fromRGB(255, 80, 70) else Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 150, 140), f)
	whiteFlash.BackgroundTransparency = math.clamp(math.max(1 - f * 1.1, whiteFlash.BackgroundTransparency + dt * 1.5), 0, 1)
end

local function updateLamp(dt: number, t: number)
	local target = Vector3.zero
	if S.ActiveSeat > 0 and seatRefs[S.ActiveSeat] then
		target = seatRefs[S.ActiveSeat].Outward * 0.5
	end
	target += Vector3.new(math.sin(t * 0.7) * 0.025, 0, math.cos(t * 0.53) * 0.025)
	lampTilt.Target = target
	local tilt = lampTilt:Update(dt)
	local angle = tilt.Magnitude
	if angle > 1e-4 then
		local axis = Vector3.new(-tilt.Z, 0, tilt.X).Unit
		lampHinge.CFrame = CFrame.new(LAMP_HINGE) * CFrame.fromAxisAngle(axis, angle)
	else
		lampHinge.CFrame = CFrame.new(LAMP_HINGE)
	end
end

local function updateHUD(dt: number, t: number, scraping: boolean)
	local now = serverNow()
	local remaining = math.max(0, S.PhaseEndsAt - now)
	local hasTimer = S.PhaseEndsAt > 0
	local isMe = S.ActiveUserId == player.UserId

	-- Баннер
	local title: string
	local tagColor = PHOSPHOR
	if S.Phase == "LOBBY" then
		title = "AWAITING OPERATORS"
	elseif S.Phase == "COUNTDOWN" then
		title = string.format("IGNITION IN %d", math.ceil(remaining))
		tagColor = AMBER
		local sec = math.ceil(remaining)
		if sec ~= lastCountdownSecond then
			lastCountdownSecond = sec
			if sec > 0 then
				playOneShot(UISFX.Tick, 1.0 + (3 - sec) * 0.2)
			end
		end
	elseif S.Phase == "CHOICE" then
		title = if isMe then "YOUR TURN — CHOOSE" else string.upper(S.ActiveName) .. " IS DECIDING"
		tagColor = AMBER
	elseif S.Phase == "MICROGAME" then
		title = if isMe then "EXTRACT THE ROD" else string.upper(S.ActiveName) .. " IS EXTRACTING"
		tagColor = if scraping then RED else PHOSPHOR
	elseif S.Phase == "DETONATION" then
		title = "☢ CORE CRITICAL ☢"
		tagColor = RED
	elseif S.Phase == "MATCH_END" then
		title = "CYCLE COMPLETE"
	elseif S.Phase == "INTERMISSION" then
		title = "RECALIBRATING CORE"
	else
		title = S.StatusLine
	end
	bannerTitle.Text = title
	bannerTitle.TextColor3 = if S.Phase == "DETONATION" and math.floor(t * 6) % 2 == 0 then RED else T.Text
	phaseTag.Text = S.Phase
	phaseTag.BackgroundColor3 = tagColor
	bannerSub.Text = if S.Phase == "LOBBY" then string.format("Sit at the table to join  ·  seated %d / 4", S.Seated) else S.StatusLine
	bannerTimer.Text = if hasTimer then string.format("%04.1f", remaining) else "--.-"
	local frac = if hasTimer then math.clamp(remaining / math.max(S.PhaseTotal, 0.01), 0, 1) else 0
	timerFill.Size = UDim2.fromScale(frac, 1)
	timerFill.BackgroundColor3 = if frac < 0.3 then RED else AMBER

	-- Статистика (числа доезжают пружиной)
	potDisplay.Target = S.Pot
	instabDisplay.Target = S.Instability
	local pot = potDisplay:Update(dt)
	local inst = math.clamp(instabDisplay:Update(dt), 0, 100)
	potValue.Text = formatMoney(pot)
	instabValue.Text = string.format("%03d%%", math.floor(inst + 0.5))
	instabValue.TextColor3 = instabilityColor(inst)
	instabFill.Size = UDim2.fromScale(inst / 100, 1)
	instabFill.BackgroundColor3 = instabilityColor(inst)
	overclockValue.Text = string.format("×%.1f", S.Overclock)
	cycleValue.Text = if S.MatchActive then string.format("%d / %d", S.Cycle, S.MaxCycles) else "-- / --"
	local statsStroke = stats:FindFirstChild("Stroke") :: UIStroke?
	if statsStroke then
		statsStroke.Color = if inst >= 75 and math.floor(t * 4) % 2 == 0 then RED else T.Steel
	end

	-- Банк
	local cashStat = player:FindFirstChild("leaderstats") and (player :: any).leaderstats:FindFirstChild("Cash")
	local winsStat = player:FindFirstChild("leaderstats") and (player :: any).leaderstats:FindFirstChild("Wins")
	if cashStat and cashStat:IsA("IntValue") then
		if math.abs(bankDisplay.Target - cashStat.Value) > 0.5 then
			if cashStat.Value > bankDisplay.Target then
				bankPunch:Impulse(3)
			end
			bankDisplay.Target = cashStat.Value
		end
	end
	if winsStat and winsStat:IsA("IntValue") then
		winsValue.Text = "WINS " .. winsStat.Value
	end
	bankValue.Text = formatMoney(bankDisplay:Update(dt))
	local responsiveScale = responsiveScales[1] and responsiveScales[1].Scale or 1
	bankScale.Scale = responsiveScale * bankPunch:Update(dt)

	-- Подсказка "сесть"
	local seated = mySeatIndex() ~= nil
	hint.Visible = not seated
	if not seated then
		hint.Text = if S.MatchActive then "MATCH IN PROGRESS · SIT TO JOIN THE NEXT CYCLE  ·  [E]" else "WALK TO AN OPERATOR CHAIR  ·  [E] SIT AT TABLE"
	end

	-- Панель действий
	local showActions = choiceAvailable()
	actionPanelSpring.Target = if showActions then 1 else 0
	local slide = actionPanelSpring:Update(dt)
	actionPanel.Position = UDim2.new(0.5, 0, 1, -18 + (1 - slide) * 240)
	actionPanel.Visible = slide > 0.02 or showActions
	actionTimerFill.Size = UDim2.fromScale(frac, 1)
	actionTimerFill.BackgroundColor3 = if frac < 0.3 then RED else AMBER
	for _, ab in actionButtons do
		ab.ScaleSpring.Target = if ab.Hover and ab.Enabled then FEEL.HoverScale else 1
		ab.GlowSpring.Target = if ab.Hover then 1 else 0
		ab.RotSpring.Target = 0
		local sc = ab.ScaleSpring:Update(dt)
		local rot = ab.RotSpring:Update(dt)
		local glow = math.clamp(ab.GlowSpring:Update(dt), 0, 3)
		ab.Scale.Scale = math.max(sc, 0.1)
		ab.Button.Rotation = rot
		ab.Stroke.Thickness = 2 + glow * 2.5
		ab.Stroke.Transparency = math.clamp(0.4 - glow * 0.4, 0, 1)
		local accent = if ab.Enabled then ab.Accent else Color3.fromRGB(90, 90, 86)
		ab.Stroke.Color = accent
		ab.Title.TextColor3 = accent
		ab.Button.BackgroundColor3 = T.FrameHi:Lerp(accent, math.clamp(glow * 0.12, 0, 0.4))
	end

	-- Уведомление
	local ns = noticeSpring:Update(dt)
	noticeScale.Scale = (responsiveScales[1] and responsiveScales[1].Scale or 1) * math.max(ns, 0.1)
	if os.clock() > noticeHideAt then
		noticeAlpha.Target = 0
	end
	local alpha = math.clamp(noticeAlpha:Update(dt), 0, 1)
	noticeLabel.TextTransparency = 1 - alpha
	noticeLabel.TextStrokeTransparency = 1 - alpha * 0.6

	-- Мини-игра
	local slideMicro = microSlide:Update(dt)
	micro.Visible = slideMicro > 0.02 or MG.Active
	micro.Position = UDim2.new(1, -16 + (1 - slideMicro) * 320, 0.5, 30)
	if micro.Visible then
		local mt = serverNow() - MG.StartTime
		local cursor = if MG.IsMine then MG.Cursor else remoteCursor.Position
		local center = sweetCenter(math.max(mt, 0), MG.Params)
		sweetZone.Position = UDim2.fromScale(0, 1 - center)
		sweetZone.Size = UDim2.new(1, 0, MG.Params.HalfWidth * 2, 0)
		sweetZone.BackgroundColor3 = if scraping then AMBER else PHOSPHOR
		marker.Position = UDim2.fromScale(0, 1 - cursor)
		marker.BackgroundColor3 = if scraping then RED else AMBER
		markerArrow.Position = UDim2.fromOffset(104, 58 + TUBE_H * (1 - cursor))
		markerArrow.TextColor3 = marker.BackgroundColor3
		local progress = math.clamp(progressSpring.Position, 0, 1)
		progressFill.Size = UDim2.fromScale(1, progress)
		progressLabel.Text = string.format("%03d%%", math.floor(progress * 100 + 0.5))
		microInstab.Text = string.format("%03d%%", math.floor(S.Instability + 0.5))
		microInstab.TextColor3 = instabilityColor(S.Instability)
		scrapeWarn.TextTransparency = if scraping and math.floor(t * 10) % 2 == 0 then 0 else 1
		local mfrac = math.clamp(1 - mt / math.max(MG.Duration, 0.01), 0, 1)
		microTimerFill.Size = UDim2.fromScale(mfrac, 1)
		microTimerFill.BackgroundColor3 = if mfrac < 0.3 then RED else PHOSPHOR
		microStroke.Color = if scraping then RED else Color3.fromRGB(60, 140, 70)
		microStroke.Thickness = if scraping then 2 + math.abs(math.sin(t * 30)) * 3 else 2
		if MG.IsMine and mt < MG.Grace then
			microHint.Text = "ENGAGING MAG-LOCK…"
		elseif MG.IsMine then
			microHint.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "HOLD THE SCREEN" else "HOLD [LMB] / [SPACE]"
		end
	end

	-- Красная виньетка при скрежете / высокой нестабильности
	local danger = 0
	if MG.Active and MG.IsMine and scraping then
		danger = 0.55 + math.abs(math.sin(t * 18)) * 0.3
	elseif S.Instability >= 85 then
		danger = 0.15 + math.abs(math.sin(t * 4)) * 0.15
	end
	vignette.BackgroundTransparency = 1 - danger
	vignetteGradient.Rotation = if danger > 0 and math.floor(t * 2) % 2 == 0 then 90 else 0
end

------------------------------------------------------------------------
-- ГЛАВНЫЕ ЦИКЛЫ
------------------------------------------------------------------------

-- Перед стандартной камерой снимаем прошлую тряску: PlayerModule читает camera.CFrame,
-- и без этого случайные повороты накапливались бы.
RunService:BindToRenderStep("CoreRouletteUnshake", Enum.RenderPriority.Camera.Value - 1, function()
	local shake = appliedShake
	local camera = Workspace.CurrentCamera
	if shake and camera and cameraMode == "FREE" then
		camera.CFrame = camera.CFrame * shake:Inverse()
	end
	appliedShake = nil
end)

RunService:BindToRenderStep("CoreRouletteCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	updateCamera(dt)
end)

RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock()
	local inst01 = math.clamp(S.Instability / 100, 0, 1)

	-- Мини-игра
	local scraping = false
	local cursor = 0
	local jitter = Vector3.zero
	if MG.Active then
		local mt = serverNow() - MG.StartTime
		if mt > MG.Duration + 3 then
			stopMicro({ Result = "LOCAL_TIMEOUT" }) -- страховка, если STOP потерялся
		elseif MG.IsMine then
			simulateMine(dt, math.max(mt, 0))
			scraping = MG.LocalScraping
			cursor = MG.Cursor
			jitter = Vector3.new(MG.JitterX, 0, MG.JitterZ)
			if scraping then
				addTrauma(FEEL.ScrapeTrauma * dt)
			end
		else
			cursor = remoteCursor:Update(dt)
			jitter = remoteJitter:Update(dt)
			scraping = MG.ServerScraping
			if scraping then
				addTrauma(FEEL.ScrapeTrauma * 0.15 * dt)
			end
		end
		progressSpring.Target = MG.ServerProgress
	else
		progressSpring.Target = 0
	end
	progressSpring:Update(dt)

	updateManipulator(dt, t, scraping, cursor, jitter, inst01)
	updateCoreFX(dt, t, scraping, inst01)
	updateLamp(dt, t)
	updateHUD(dt, t, scraping)
end)

-- Адаптация к размеру экрана
local function hookCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)
	end
	updateResponsive()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()

-- Смена персонажа: сбрасываем ввод и камеру
player.CharacterAdded:Connect(function(character: Model)
	unbindHold()
	cameraMode = "FREE"
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Seated:Connect(function()
		rebuildRoster()
	end)
end)

-- Синхронизация при входе (поздний заход посреди матча)
MicroGameStatus:FireServer("SYNC")
