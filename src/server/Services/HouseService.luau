--!strict
-- Дом: двери (открыть/запереть/взломать), окна (доски/стекло), свет по комнатам, щиток, свечи,
-- укрытия (промпты), телевизор, телефон, магазин и киоск перков (промпты), датчики движения.

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local World = require(script.Parent:WaitForChild("World"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ServerSounds = require(script.Parent:WaitForChild("ServerSounds"))

local HouseService = {}

export type Door = {
	Id: string,
	Kind: string,
	Model: Model,
	Hinge: BasePart,
	Panel: BasePart,
	Offset: CFrame,
	Open: boolean,
	Locked: boolean,
	Angle: number,
	Tween: Tween?,
	AngleValue: NumberValue,
	Breaking: boolean,
}

export type Window = {
	Id: string,
	Model: Model,
	Glass: BasePart,
	Boards: { BasePart },
	BoardCount: number,
	Broken: boolean,
	Room: string,
	Entry: BasePart?,
}

export type RoomLight = {
	Room: string,
	Model: Model,
	Bulb: BasePart?,
	Light: PointLight?,
	Candle: BasePart?,
	CandleLight: PointLight?,
	On: boolean,
	BulbColor: Color3,
}

HouseService.Doors = {} :: { [string]: Door }
HouseService.Windows = {} :: { [string]: Window }
HouseService.Lights = {} :: { [string]: RoomLight }
HouseService.Power = true
HouseService.Candles = false
HouseService.MotionLightsOn = false

HouseService.WindowBoardRequested = Signal.new() :: Signal.Signal<Player, string>
HouseService.ShopRequested = Signal.new() :: Signal.Signal<Player>
HouseService.PerksRequested = Signal.new() :: Signal.Signal<Player>
HouseService.ReadyPadRequested = Signal.new() :: Signal.Signal<Player>
HouseService.LightToggled = Signal.new() :: Signal.Signal<string, boolean, Player?>
HouseService.DoorOpened = Signal.new() :: Signal.Signal<string, Player?>
HouseService.PhoneAnswered = Signal.new() :: Signal.Signal<Player>

local DOOR_OPEN_ANGLE = 100
local phoneRinging = false
local phoneSound: Sound? = nil

----------------------------------------------------------------------
-- Двери
----------------------------------------------------------------------
local function applyDoorAngle(d: Door, angle: number)
	d.Panel.CFrame = d.Hinge.CFrame * CFrame.Angles(0, math.rad(angle), 0) * d.Offset
end

local function swingDoor(d: Door, targetAngle: number, duration: number)
	if d.Tween then
		d.Tween:Cancel()
	end
	d.AngleValue.Value = d.Angle
	local tween = TweenService:Create(d.AngleValue, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = targetAngle })
	d.Tween = tween
	tween:Play()
	d.Angle = targetAngle
end

local function initDoor(model: Model)
	local id = (model:GetAttribute("DoorId") :: string?) or model.Name
	local hinge = model:FindFirstChild("Hinge")
	local panel = model:FindFirstChild("Panel")
	if not hinge or not panel or not hinge:IsA("BasePart") or not panel:IsA("BasePart") then
		warn("[House] door without Hinge/Panel: " .. id)
		return
	end
	local angleValue = Instance.new("NumberValue")
	angleValue.Name = "Angle"
	angleValue.Parent = model
	local d: Door = {
		Id = id,
		Kind = (model:GetAttribute("Kind") :: string?) or "Interior",
		Model = model,
		Hinge = hinge,
		Panel = panel,
		Offset = hinge.CFrame:Inverse() * panel.CFrame,
		Open = false,
		Locked = false,
		Angle = 0,
		Tween = nil,
		AngleValue = angleValue,
		Breaking = false,
	}
	angleValue.Changed:Connect(function(v)
		applyDoorAngle(d, v)
	end)
	panel.CollisionGroup = World.COLLISION_PROPS
	-- Путь пациентов проходит сквозь закрытую дверь (физика её держит, пока он не откроет/сломает)
	local modifier = Instance.new("PathfindingModifier")
	modifier.Name = "DoorPass"
	modifier.PassThrough = true
	modifier.Parent = panel
	HouseService.Doors[id] = d
end

local function setDoorAttributes(d: Door)
	d.Model:SetAttribute("Open", d.Open)
	d.Model:SetAttribute("Locked", d.Locked)
end

-- Открыть/закрыть. awayFrom — с какой стороны стоит тот, кто открывает (дверь распахивается от него).
function HouseService.setDoorOpen(id: string, open: boolean, awayFrom: Vector3?, by: Player?, force: boolean?): boolean
	local d = HouseService.Doors[id]
	if not d then
		return false
	end
	if open and d.Locked and not force then
		return false
	end
	if d.Open == open then
		return true
	end
	d.Open = open
	if open then
		local sign = 1
		if awayFrom then
			local rel = d.Hinge.CFrame:PointToObjectSpace(awayFrom)
			sign = if rel.Z > 0 then 1 else -1
		end
		swingDoor(d, DOOR_OPEN_ANGLE * sign, 0.55)
		ServerSounds.playOn("DoorOpen", d.Panel, 0.55, 1)
		NoiseService.emit(d.Panel.Position, "Door", by)
		HouseService.DoorOpened:Fire(id, by)
	else
		swingDoor(d, 0, 0.45)
		ServerSounds.playOn("DoorClose", d.Panel, 0.5, 1)
		NoiseService.emit(d.Panel.Position, "Door", by, Config.Noise.Door * 0.6)
	end
	setDoorAttributes(d)
	return true
end

function HouseService.setDoorLocked(id: string, locked: boolean, by: Player?): boolean
	local d = HouseService.Doors[id]
	if not d or d.Kind ~= "Entry" then
		return false
	end
	if locked and d.Open then
		HouseService.setDoorOpen(id, false, nil, by)
	end
	d.Locked = locked
	setDoorAttributes(d)
	ServerSounds.playOn("Lock", d.Panel, 0.5, if locked then 1 else 0.9)
	if by then
		Remotes.Notify:FireClient(by, if locked then "N_DoorLocked" else "N_DoorUnlocked", "info")
	end
	return true
end

function HouseService.isDoorLocked(id: string): boolean
	local d = HouseService.Doors[id]
	return d ~= nil and d.Locked
end

function HouseService.isDoorOpen(id: string): boolean
	local d = HouseService.Doors[id]
	return d ~= nil and d.Open
end

function HouseService.doorPosition(id: string): Vector3?
	local d = HouseService.Doors[id]
	return if d then d.Panel.Position else nil
end

-- Пациент ломает замок: возвращает true, когда дверь открыта
function HouseService.breakLock(id: string)
	local d = HouseService.Doors[id]
	if not d then
		return
	end
	d.Locked = false
	setDoorAttributes(d)
	ServerSounds.playOn("DoorSlam", d.Panel, 0.9, 0.9)
	NoiseService.emit(d.Panel.Position, "Breaking")
	for _, p in Players:GetPlayers() do
		Remotes.Notify:FireClient(p, "N_LockBroken", "warning")
	end
	HouseService.setDoorOpen(id, true, nil, nil, true)
end

function HouseService.knockDoor(id: string)
	local d = HouseService.Doors[id]
	if d then
		ServerSounds.playOn("Knock", d.Panel, 1, 0.9, 140)
		Remotes.FX:FireAllClients("Knock", { Position = d.Panel.Position })
	end
end

----------------------------------------------------------------------
-- Окна
----------------------------------------------------------------------
local function initWindow(model: Model)
	local id = (model:GetAttribute("WindowId") :: string?) or model.Name
	local glass = model:FindFirstChild("Glass")
	if not glass or not glass:IsA("BasePart") then
		warn("[House] window without Glass: " .. id)
		return
	end
	local boards = {}
	for i = 1, 3 do
		local b = model:FindFirstChild("Board" .. i)
		if b and b:IsA("BasePart") then
			table.insert(boards, b)
		end
	end
	local entry = model:FindFirstChild("Entry")
	glass.CollisionGroup = World.COLLISION_PROPS
	HouseService.Windows[id] = {
		Id = id,
		Model = model,
		Glass = glass,
		Boards = boards,
		BoardCount = 0,
		Broken = false,
		Room = (model:GetAttribute("Room") :: string?) or "",
		Entry = if entry and entry:IsA("BasePart") then entry else nil,
	}
end

local function refreshWindow(w: Window)
	for i, b in w.Boards do
		local shown = i <= w.BoardCount
		b.Transparency = if shown then 0 else 1
		b.CanCollide = shown
	end
	w.Glass.Transparency = if w.Broken then 1 else 0.55
	w.Glass.CanCollide = not w.Broken
	w.Model:SetAttribute("Boards", w.BoardCount)
	w.Model:SetAttribute("Broken", w.Broken)
end

function HouseService.addBoard(id: string, by: Player?): boolean
	local w = HouseService.Windows[id]
	if not w or w.BoardCount >= #w.Boards then
		return false
	end
	w.BoardCount += 1
	refreshWindow(w)
	ServerSounds.playOn("WoodBreak", w.Glass, 0.5, 1.2)
	NoiseService.emit(w.Glass.Position, "Switch", by, 10)
	if by then
		Remotes.Notify:FireClient(by, "N_WindowBoarded", "success", { w.BoardCount })
	end
	return true
end

function HouseService.windowBoards(id: string): number
	local w = HouseService.Windows[id]
	return if w then w.BoardCount else 0
end

function HouseService.isWindowBroken(id: string): boolean
	local w = HouseService.Windows[id]
	return w ~= nil and w.Broken
end

function HouseService.breakBoard(id: string): boolean
	local w = HouseService.Windows[id]
	if not w or w.BoardCount <= 0 then
		return false
	end
	w.BoardCount -= 1
	refreshWindow(w)
	ServerSounds.playOn("WoodBreak", w.Glass, 0.9, 0.8, 140)
	NoiseService.emit(w.Glass.Position, "Breaking")
	return true
end

function HouseService.breakGlass(id: string)
	local w = HouseService.Windows[id]
	if not w or w.Broken then
		return
	end
	w.Broken = true
	refreshWindow(w)
	ServerSounds.playOn("Glass", w.Glass, 1, 1, 160)
	NoiseService.emit(w.Glass.Position, "Window")
end

function HouseService.knockWindow(id: string)
	local w = HouseService.Windows[id]
	if w then
		ServerSounds.playOn("Knock", w.Glass, 1, 1.1, 140)
		Remotes.FX:FireAllClients("Knock", { Position = w.Glass.Position })
	end
end

function HouseService.windowPosition(id: string): Vector3?
	local w = HouseService.Windows[id]
	return if w then w.Glass.Position else nil
end

----------------------------------------------------------------------
-- Свет
----------------------------------------------------------------------
local function initLight(model: Model)
	local room = (model:GetAttribute("RoomName") :: string?) or model.Name
	local bulb = model:FindFirstChild("Bulb")
	local candle = model:FindFirstChild("Candle")
	local rl: RoomLight = {
		Room = room,
		Model = model,
		Bulb = if bulb and bulb:IsA("BasePart") then bulb else nil,
		Light = if bulb then bulb:FindFirstChildOfClass("PointLight") else nil,
		Candle = if candle and candle:IsA("BasePart") then candle else nil,
		CandleLight = if candle then candle:FindFirstChildOfClass("PointLight") else nil,
		On = true,
		BulbColor = if bulb and bulb:IsA("BasePart") then bulb.Color else Color3.fromRGB(255, 230, 190),
	}
	HouseService.Lights[room] = rl
end

local function refreshLight(rl: RoomLight)
	local lit = rl.On and HouseService.Power
	if rl.Bulb then
		rl.Bulb.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		rl.Bulb.Color = if lit then rl.BulbColor else Color3.fromRGB(70, 66, 60)
	end
	if rl.Light then
		rl.Light.Enabled = lit
	end
	if rl.Candle then
		rl.Candle.Transparency = if HouseService.Candles then 0 else 1
	end
	if rl.CandleLight then
		rl.CandleLight.Enabled = HouseService.Candles
	end
	rl.Model:SetAttribute("On", rl.On)
	rl.Model:SetAttribute("Lit", lit)
end

function HouseService.isLit(room: string): boolean
	local rl = HouseService.Lights[room]
	if not rl then
		return false
	end
	return (rl.On and HouseService.Power) or HouseService.Candles
end

-- Освещена ли точка (по комнате; на улице — по фонарям: крыльцо/улица считаются освещёнными)
function HouseService.isPositionLit(position: Vector3): boolean
	local room = World.roomAt(position)
	if not room then
		return true
	end
	if room.Outdoor then
		return HouseService.isLit(room.Name) or room.Name == "FrontYard" or room.Name == "Porch"
	end
	return HouseService.isLit(room.Name)
end

function HouseService.setLight(room: string, on: boolean, by: Player?, silent: boolean?): boolean
	local rl = HouseService.Lights[room]
	if not rl then
		return false
	end
	if rl.On == on then
		return true
	end
	rl.On = on
	refreshLight(rl)
	if not silent then
		if rl.Bulb then
			ServerSounds.playOn("Switch", rl.Bulb, 0.5, 1, 60)
		end
		if rl.Bulb then
			NoiseService.emit(rl.Bulb.Position, "Switch", by)
		end
	end
	Remotes.LightsChanged:FireAllClients(room, on and HouseService.Power)
	HouseService.LightToggled:Fire(room, on, by)
	return true
end

function HouseService.litRooms(): { string }
	local list = {}
	for room, rl in HouseService.Lights do
		if rl.On and HouseService.Power then
			table.insert(list, room)
		end
	end
	return list
end

function HouseService.setPower(on: boolean, by: Player?)
	if HouseService.Power == on then
		return
	end
	HouseService.Power = on
	for room, rl in HouseService.Lights do
		refreshLight(rl)
		Remotes.LightsChanged:FireAllClients(room, rl.On and on)
	end
	local fuse = World.houseChild("Fusebox")
	if fuse then
		fuse:SetAttribute("On", on)
		ServerSounds.playOn("Arc", fuse, 0.8, if on then 1.1 else 0.8, 90)
	end
	Remotes.FX:FireAllClients("Blackout", { On = not on })
	if by then
		local root = PlayerService.rootPart(by)
		if root then
			NoiseService.emit(root.Position, "Switch", by, 12)
		end
	end
end

function HouseService.setCandles(on: boolean)
	HouseService.Candles = on
	for _, rl in HouseService.Lights do
		refreshLight(rl)
	end
end

-- Мигание лампы в комнате (телеграф) — только косметика на клиентах
function HouseService.flicker(room: string, duration: number)
	Remotes.FX:FireAllClients("Flicker", { Room = room, Duration = duration })
end

----------------------------------------------------------------------
-- Телевизор, телефон, датчики движения
----------------------------------------------------------------------
function HouseService.setTV(on: boolean, text: string?)
	local tv = World.houseChild("TV")
	if not tv then
		return
	end
	tv:SetAttribute("On", on)
	local screen = tv:FindFirstChild("Screen")
	local gui = screen and screen:FindFirstChild("Screen")
	if gui and gui:IsA("SurfaceGui") then
		local static = gui:FindFirstChild("Static")
		local label = gui:FindFirstChild("Text")
		if static and static:IsA("GuiObject") then
			static.Visible = on
		end
		if label and label:IsA("TextLabel") then
			label.Visible = on and text ~= nil
			label.Text = text or ""
		end
	end
	if screen and screen:IsA("BasePart") then
		screen.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		screen.Color = if on then Color3.fromRGB(190, 200, 215) else Color3.fromRGB(20, 20, 22)
		if on then
			ServerSounds.playOn("TvStatic", screen, 0.35, 1, 70)
		end
	end
end

function HouseService.ringPhone(seconds: number)
	local phone = World.houseChild("Phone")
	local body = phone and phone:FindFirstChild("Body")
	if not body or phoneRinging then
		return
	end
	phoneRinging = true
	phoneSound = ServerSounds.loopOn("PhoneRing", body, 0.8, 1, 110)
	task.delay(seconds, function()
		if phoneRinging then
			-- не ответили: телефон "выдал" дом
			phoneRinging = false
			if phoneSound then
				phoneSound:Destroy()
				phoneSound = nil
			end
			if body:IsA("BasePart") then
				NoiseService.emit(body.Position, "Phone")
			end
		end
	end)
end

local function answerPhone(player: Player)
	if not phoneRinging then
		return
	end
	phoneRinging = false
	if phoneSound then
		phoneSound:Destroy()
		phoneSound = nil
	end
	HouseService.PhoneAnswered:Fire(player)
end

local motionLights: { { Part: BasePart, Light: SpotLight?, Beeper: Sound?, Cooldown: number } } = {}

local function initMotionLights()
	local folder = World.houseFolder("MotionLights")
	if not folder then
		return
	end
	for _, m in folder:GetChildren() do
		local part = if m:IsA("BasePart") then m else m:FindFirstChildWhichIsA("BasePart")
		if part then
			local light = part:FindFirstChildOfClass("SpotLight") or m:FindFirstChildWhichIsA("SpotLight", true)
			table.insert(motionLights, { Part = part, Light = light, Beeper = nil, Cooldown = 0 })
		end
	end
end

function HouseService.setMotionLights(on: boolean)
	HouseService.MotionLightsOn = on
	for _, ml in motionLights do
		ml.Part.Transparency = if on then 0 else 1
	end
end

-- Вызывается InmateService для каждого пациента снаружи
function HouseService.checkMotionLights(position: Vector3)
	if not HouseService.MotionLightsOn then
		return
	end
	local now = os.clock()
	for _, ml in motionLights do
		if now >= ml.Cooldown and (ml.Part.Position - position).Magnitude < 16 then
			ml.Cooldown = now + 6
			if ml.Light then
				ml.Light.Enabled = true
				task.delay(2.5, function()
					if ml.Light then
						ml.Light.Enabled = false
					end
				end)
			end
			ServerSounds.playOn("Beep", ml.Part, 0.8, 1.2, 120)
		end
	end
end

----------------------------------------------------------------------
-- Промпты
----------------------------------------------------------------------
local function onPrompt(prompt: ProximityPrompt, player: Player)
	local model = prompt.Parent and prompt.Parent.Parent
	local record = PlayerService.get(player)
	if not record then
		return
	end
	-- Дверь
	local doorModel = if model and model:IsA("Model") and model:GetAttribute("DoorId") then model else nil
	if doorModel then
		local id = doorModel:GetAttribute("DoorId") :: string
		local d = HouseService.Doors[id]
		if not d or record.Status ~= "Alive" then
			return
		end
		local root = PlayerService.rootPart(player)
		if prompt.Name == "LockPrompt" then
			HouseService.setDoorLocked(id, not d.Locked, player)
			return
		end
		if d.Locked then
			Remotes.Notify:FireClient(player, "N_DoorLocked", "warning")
			return
		end
		HouseService.setDoorOpen(id, not d.Open, if root then root.Position else nil, player)
		return
	end
	-- Окно
	local windowModel = if model and model:IsA("Model") and model:GetAttribute("WindowId") then model else nil
	if windowModel then
		if record.Status ~= "Alive" then
			return
		end
		HouseService.WindowBoardRequested:Fire(player, windowModel:GetAttribute("WindowId") :: string)
		return
	end
	-- Укрытие
	local hideModel = if model and model:IsA("Model") and model:GetAttribute("HideId") then model else nil
	if hideModel then
		PlayerService.hide(player, hideModel:GetAttribute("HideId") :: string)
		return
	end
	-- Свет: Switch лежит в модели света
	if model and model:IsA("Model") and model:GetAttribute("RoomName") and prompt.Parent and prompt.Parent.Name == "Switch" then
		if record.Status ~= "Alive" then
			return
		end
		local room = model:GetAttribute("RoomName") :: string
		local rl = HouseService.Lights[room]
		if rl then
			HouseService.setLight(room, not rl.On, player)
		end
		return
	end
	if model and model.Name == "Fusebox" then
		if record.Status ~= "Alive" then
			return
		end
		HouseService.setPower(not HouseService.Power, player)
		return
	end
	if model and model.Name == "Shop" then
		HouseService.ShopRequested:Fire(player)
		return
	end
	if model and model.Name == "Phone" then
		answerPhone(player)
		return
	end
	if model and model.Name == "PerkKiosk" then
		HouseService.PerksRequested:Fire(player)
		return
	end
	if prompt.Parent and prompt.Parent.Name == "ReadyPad" then
		HouseService.ReadyPadRequested:Fire(player)
		return
	end
end

----------------------------------------------------------------------
-- Сброс
----------------------------------------------------------------------
function HouseService.resetMatch()
	for id, d in HouseService.Doors do
		d.Locked = false
		d.Breaking = false
		if d.Open then
			d.Open = false
			swingDoor(d, 0, 0.2)
		end
		setDoorAttributes(d)
	end
	for _, w in HouseService.Windows do
		w.BoardCount = 0
		w.Broken = false
		refreshWindow(w)
	end
	HouseService.Power = true
	HouseService.Candles = false
	for room, rl in HouseService.Lights do
		rl.On = true
		refreshLight(rl)
		Remotes.LightsChanged:FireAllClients(room, true)
	end
	local fuse = World.houseChild("Fusebox")
	if fuse then
		fuse:SetAttribute("On", true)
	end
	HouseService.setMotionLights(false)
	HouseService.setTV(false)
	if phoneRinging then
		phoneRinging = false
		if phoneSound then
			phoneSound:Destroy()
			phoneSound = nil
		end
	end
end

-- Рассвет: стёкла восстанавливаются, доски остаются, свет остаётся как был
function HouseService.onDawn()
	for _, w in HouseService.Windows do
		if w.Broken then
			w.Broken = false
			refreshWindow(w)
		end
	end
	if phoneRinging then
		phoneRinging = false
		if phoneSound then
			phoneSound:Destroy()
			phoneSound = nil
		end
	end
	HouseService.setTV(false)
end

function HouseService.init()
	local doors = World.houseFolder("Doors")
	if doors then
		for _, m in doors:GetChildren() do
			if m:IsA("Model") then
				initDoor(m)
			end
		end
	end
	local windows = World.houseFolder("Windows")
	if windows then
		for _, m in windows:GetChildren() do
			if m:IsA("Model") then
				initWindow(m)
			end
		end
	end
	local lights = World.houseFolder("Lights")
	if lights then
		for _, m in lights:GetChildren() do
			if m:IsA("Model") then
				initLight(m)
			end
		end
	end
	initMotionLights()
	HouseService.resetMatch()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local ok, err = pcall(onPrompt, prompt, player)
		if not ok then
			warn("[House] prompt failed: " .. tostring(err))
		end
	end)
	print(string.format("[House] doors %d, windows %d, lights %d", (function()
		local n = 0
		for _ in HouseService.Doors do
			n += 1
		end
		return n
	end)(), (function()
		local n = 0
		for _ in HouseService.Windows do
			n += 1
		end
		return n
	end)(), (function()
		local n = 0
		for _ in HouseService.Lights do
			n += 1
		end
		return n
	end)()))
end

return HouseService
