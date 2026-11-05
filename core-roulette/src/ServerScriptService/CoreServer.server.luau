--!strict
--[[
	ServerScriptService.CoreServer
	Авторитетный сервер CORE ROULETTE:
	  • строит мир (BunkerBuilder) и создаёт ReplicatedStorage.CoreRemotes;
	  • leaderstats (Cash, Wins) + сохранение в DataStore (если доступно);
	  • посадка через ProximityPrompt, учёт занятых мест;
	  • машина состояний: LOBBY -> COUNTDOWN -> (CHOICE -> MICROGAME/OVERCLOCK/EJECT -> RESOLVE | DETONATION)* -> MATCH_END;
	  • проверка телеметрии мини-игры (скорость курсора, часы клиента, частота пакетов);
	  • выплаты, нестабильность, физическое катапультирование и детонация.

	Клиент НИЧЕМУ не доверяем: он присылает только выбор действия и положение курсора.
	Прогресс извлечения и рост нестабильности сервер считает сам.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

local BunkerBuilder = require(script.Parent.BunkerBuilder)

------------------------------------------------------------------------
-- НАСТРОЙКИ (баланс). Клиент получает их через атрибуты CoreRemotes.
------------------------------------------------------------------------

local CONFIG = {
	MinPlayers = 1,
	CountdownTime = 3,
	ChoiceTime = 10,
	MicroGameTime = 7, -- полная длительность мини-игры, с
	MicroGameGrace = 0.8, -- первые секунды без штрафа (захват стержня)
	ResolvePause = 1.8,
	DetonationCooldown = 4,
	MatchEndPause = 5,
	IntermissionTime = 5,
	MaxCycles = 5, -- полных кругов за матч

	StartingPot = 1000,
	StartingInstability = 12,
	TurnHeat = 4, -- +% нестабильности в начале каждого хода

	OverclockInstability = 15,
	OverclockPot = 500,
	OverclockMaxInstability = 85,
	OverclockMultStep = 0.5,
	OverclockMultMax = 4,
	OverclockDrift = 2, -- множитель дрожи курсора следующего игрока
	OverclockSpeedFactor = 0.15, -- +15% скорости зоны за каждую единицу дрожи сверх 1
	OverclockWidthFactor = 0, -- сужение зоны за единицу дрожи (0 = не сужать)

	ExtractReward = 1000, -- * множитель оверклока
	ExtractCool = 10, -- -% нестабильности за успешное извлечение
	ProgressRate = 0.3, -- доля прогресса в секунду внутри зоны
	ProgressDecay = 0.06, -- потеря прогресса в секунду вне зоны
	ScrapeRate = 18, -- +% нестабильности в секунду при скрежете

	EjectShare = 0.4,
	DetonationPotBurn = 0.3,
	PostDetonationInstability = 25,

	SweetHalfWidth = 0.13, -- полуширина зоны (шкала 0..1)
	SweetBaseSpeed = 1.0,
	CursorMaxSpeed = 2.4, -- макс. скорость курсора (шкала/с), проверка анти-чита
	TelemetryInterval = 0.065, -- ~15 Гц
	TelemetryMinGap = 0.03,
	TelemetryStale = 0.5,
	MaxClockSkew = 0.4,

	EjectSpeed = 55,
	EjectLift = 42,
	BlastSpeed = 85,
	BlastLift = 60,
	SeatLockTime = 2.5,
}

------------------------------------------------------------------------
-- ТИПЫ
------------------------------------------------------------------------

type Participant = {
	Player: Player,
	UserId: number,
	Name: string,
	SeatIndex: number,
	Status: string, -- "ACTIVE" | "EJECTED" | "BLASTED" | "LEFT" | "SURVIVOR"
	Turns: number,
}

type SweetParams = {
	Phase1: number,
	Phase2: number,
	Phase3: number,
	Speed: number,
	HalfWidth: number,
}

type MicroGame = {
	Player: Player,
	Participant: Participant,
	StartTime: number, -- Workspace:GetServerTimeNow()
	Duration: number,
	Grace: number,
	Params: SweetParams,
	Drift: number,
	Rod: number,
	Progress: number,
	Cursor: number,
	CursorT: number, -- время клиента (относительно старта), к которому относится Cursor
	LastPacket: number, -- os.clock() последнего принятого пакета
	JitterX: number,
	JitterZ: number,
	Scraping: boolean,
	Acked: boolean,
	Result: string?,
}

type GameState = {
	Phase: string,
	PhaseEndsAt: number,
	Pot: number,
	Instability: number,
	Overclock: number,
	Cycle: number,
	DriftNext: number,
	CurrentDrift: number,
	Active: Participant?,
	Participants: { Participant },
	MatchActive: boolean,
	MatchId: number,
	StatusLine: string,
}

------------------------------------------------------------------------
-- REMOTES
------------------------------------------------------------------------

local oldRemotes = ReplicatedStorage:FindFirstChild("CoreRemotes")
if oldRemotes then
	oldRemotes:Destroy()
end

local Remotes = Instance.new("Folder")
Remotes.Name = "CoreRemotes"

local PlayerAction = Instance.new("RemoteEvent")
PlayerAction.Name = "PlayerAction"
PlayerAction.Parent = Remotes

local GameStateUpdate = Instance.new("RemoteEvent")
GameStateUpdate.Name = "GameStateUpdate"
GameStateUpdate.Parent = Remotes

local MicroGameStatus = Instance.new("RemoteEvent")
MicroGameStatus.Name = "MicroGameStatus"
MicroGameStatus.Parent = Remotes

local CoreDetonate = Instance.new("RemoteEvent")
CoreDetonate.Name = "CoreDetonate"
CoreDetonate.Parent = Remotes

local ReplicateManipulator = Instance.new("UnreliableRemoteEvent")
ReplicateManipulator.Name = "ReplicateManipulator"
ReplicateManipulator.Parent = Remotes

for key, value in CONFIG :: { [string]: any } do
	Remotes:SetAttribute(key, value)
end

------------------------------------------------------------------------
-- МИР
------------------------------------------------------------------------

local world = BunkerBuilder.Build()
local coreModel = world.CoreModel
Remotes.Parent = ReplicatedStorage -- после постройки мира: клиент ждёт и то и другое

------------------------------------------------------------------------
-- СОСТОЯНИЕ
------------------------------------------------------------------------

local state: GameState = {
	Phase = "LOBBY",
	PhaseEndsAt = 0,
	Pot = CONFIG.StartingPot,
	Instability = CONFIG.StartingInstability,
	Overclock = 1,
	Cycle = 0,
	DriftNext = 1,
	CurrentDrift = 1,
	Active = nil,
	Participants = {},
	MatchActive = false,
	MatchId = 0,
	StatusLine = "AWAITING OPERATORS",
}

local seatOccupants: { [number]: Player? } = {}
local eliminatedThisMatch: { [number]: boolean } = {} -- UserId -> true
local pendingAction: string? = nil
local micro: MicroGame? = nil
local lastActionAt: { [Player]: number } = {}

local rng = Random.new()

------------------------------------------------------------------------
-- УТИЛИТЫ
------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function formatMoney(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-$" else "$") .. out
end

-- Положение центра "магнитной зоны" во времени t. ДОЛЖНО совпадать с клиентом.
local function sweetCenter(t: number, p: SweetParams): number
	local f = p.Speed
	local c = 0.5 + 0.26 * math.sin(t * 1.15 * f + p.Phase1) + 0.12 * math.sin(t * 2.7 * f + p.Phase2) + 0.05 * math.sin(t * 6.3 * f + p.Phase3)
	return math.clamp(c, p.HalfWidth + 0.02, 1 - p.HalfWidth - 0.02)
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function countSeated(): number
	local n = 0
	for _, occupant in seatOccupants do
		if occupant then
			n += 1
		end
	end
	return n
end

local function findParticipant(player: Player): Participant?
	for _, p in state.Participants do
		if p.Player == player then
			return p
		end
	end
	return nil
end

local function countActive(): number
	local n = 0
	for _, p in state.Participants do
		if p.Status == "ACTIVE" then
			n += 1
		end
	end
	return n
end

local function isParticipantValid(p: Participant): boolean
	return p.Status == "ACTIVE" and p.Player.Parent == Players and seatOccupants[p.SeatIndex] == p.Player
end

------------------------------------------------------------------------
-- LEADERSTATS + СОХРАНЕНИЕ
------------------------------------------------------------------------

local bankStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("CoreRoulette_Bank_v1")
	end)
	if ok then
		bankStore = result
	end
end
local loadedPlayers: { [Player]: boolean } = {}

local function getStat(player: Player, name: string): IntValue?
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		return v
	end
	return nil
end

local function addStat(player: Player, name: string, amount: number)
	local v = getStat(player, name)
	if v then
		v.Value += math.floor(amount)
	end
end

local function loadBank(player: Player)
	local store = bankStore
	if not store then
		return
	end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if not ok then
		return -- без загрузки не сохраняем, чтобы не затереть реальные данные
	end
	loadedPlayers[player] = true
	if type(data) == "table" then
		local cash = getStat(player, "Cash")
		local wins = getStat(player, "Wins")
		if cash then
			cash.Value += math.floor(tonumber((data :: any).Cash) or 0)
		end
		if wins then
			wins.Value += math.floor(tonumber((data :: any).Wins) or 0)
		end
	end
end

local function saveBank(player: Player)
	local store = bankStore
	if not store or not loadedPlayers[player] then
		return
	end
	local cash = getStat(player, "Cash")
	local wins = getStat(player, "Wins")
	if not cash or not wins then
		return
	end
	local payload = { Cash = cash.Value, Wins = wins.Value }
	pcall(function()
		store:SetAsync("u_" .. player.UserId, payload)
	end)
end

local function setupLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = 0
	wins.Parent = ls
	ls.Parent = player
	task.spawn(loadBank, player)
end

------------------------------------------------------------------------
-- РАССЫЛКА СОСТОЯНИЯ
------------------------------------------------------------------------

local function snapshot(): { [string]: any }
	local list = {}
	for _, p in state.Participants do
		table.insert(list, {
			UserId = p.UserId,
			Name = p.Name,
			Seat = p.SeatIndex,
			Status = p.Status,
		})
	end
	local active = state.Active
	return {
		Phase = state.Phase,
		PhaseEndsAt = state.PhaseEndsAt,
		Pot = state.Pot,
		Instability = state.Instability,
		Overclock = state.Overclock,
		Cycle = state.Cycle,
		MaxCycles = CONFIG.MaxCycles,
		CurrentDrift = state.CurrentDrift,
		DriftNext = state.DriftNext,
		ActiveUserId = if active then active.UserId else 0,
		ActiveName = if active then active.Name else "",
		ActiveSeat = if active then active.SeatIndex else 0,
		Participants = list,
		MatchActive = state.MatchActive,
		StatusLine = state.StatusLine,
		Seated = countSeated(),
	}
end

local function setInstability(value: number)
	state.Instability = math.clamp(value, 0, 100)
	coreModel:SetAttribute("Instability", state.Instability)
end

local function broadcastState()
	coreModel:SetAttribute("Phase", state.Phase)
	coreModel:SetAttribute("Instability", state.Instability)
	coreModel:SetAttribute("ActiveSeat", if state.Active then state.Active.SeatIndex else 0)
	GameStateUpdate:FireAllClients("STATE", snapshot())
end

local function notice(text: string, kind: string, target: Player?)
	if target then
		GameStateUpdate:FireClient(target, "NOTICE", { Text = text, Kind = kind })
	else
		GameStateUpdate:FireAllClients("NOTICE", { Text = text, Kind = kind })
	end
end

local function setPhase(phase: string, duration: number?, statusLine: string?)
	state.Phase = phase
	state.PhaseEndsAt = if duration then now() + duration else 0
	if statusLine then
		state.StatusLine = statusLine
	end
	-- Прожектор: цвет по фазе (наклон лампы клиент считает сам по ActiveSeat)
	local light = world.Spotlight
	if phase == "DETONATION" then
		light.Color = Color3.fromRGB(255, 60, 40)
		light.Brightness = 8
	elseif phase == "MICROGAME" then
		light.Color = Color3.fromRGB(210, 235, 255)
		light.Brightness = 6
	elseif phase == "CHOICE" then
		light.Color = Color3.fromRGB(255, 214, 160)
		light.Brightness = 5.5
	else
		light.Color = Color3.fromRGB(255, 200, 140)
		light.Brightness = 3.5
	end
	broadcastState()
end

------------------------------------------------------------------------
-- ЭЛТ-МОНИТОРЫ
------------------------------------------------------------------------

local function instabilityColor(pct: number): Color3
	if pct < 50 then
		return Color3.fromRGB(120, 255, 140):Lerp(Color3.fromRGB(255, 190, 60), pct / 50)
	end
	return Color3.fromRGB(255, 190, 60):Lerp(Color3.fromRGB(255, 50, 40), (pct - 50) / 50)
end

local function updateCRT()
	local active = state.Active
	local remaining = math.max(0, state.PhaseEndsAt - now())
	local blink = math.floor(os.clock() * 4) % 2 == 0
	local inst = state.Instability
	for _, set in world.CRTLabels do
		set.Operator.Text = if active then string.upper(active.Name) else "----"
		set.Pot.Text = formatMoney(state.Pot)
		set.Instability.Text = string.format("%05.1f%%", inst)
		set.Instability.TextColor3 = instabilityColor(inst)
		set.InstabilityFill.Size = UDim2.fromScale(inst / 100, 1)
		set.InstabilityFill.BackgroundColor3 = instabilityColor(inst)
		set.Overclock.Text = string.format("x%.1f", state.Overclock)
		set.Cycle.Text = if state.MatchActive then string.format("%d / %d", state.Cycle, CONFIG.MaxCycles) else "-- / --"
		set.Timer.Text = if state.PhaseEndsAt > 0 then string.format("%04.1f s", remaining) else "--.- s"
		set.Status.Text = "> " .. state.StatusLine .. (if blink then "_" else " ")
		if inst >= 75 or state.Phase == "DETONATION" then
			set.Header.BackgroundColor3 = if blink then Color3.fromRGB(255, 50, 40) else Color3.fromRGB(90, 10, 8)
			set.Header.Text = " !! CONTAINMENT WARNING !!"
		else
			set.Header.BackgroundColor3 = Color3.fromRGB(120, 255, 140)
			set.Header.Text = " CORE-7 // TELEMETRY"
		end
	end
end

------------------------------------------------------------------------
-- ФИЗИКА: КАТАПУЛЬТИРОВАНИЕ / ОТБРАСЫВАНИЕ
------------------------------------------------------------------------

local function launchFromSeat(p: Participant, speed: number, lift: number, kind: string)
	local info = world.SeatInfos[p.SeatIndex]
	local seat = info.Seat
	local velocity = info.Outward * speed + Vector3.new(0, lift, 0)

	-- Временно блокируем стул, чтобы игрока не "засосало" обратно
	seat.Disabled = true
	task.delay(CONFIG.SeatLockTime, function()
		seat.Disabled = false
	end)

	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	local humanoid, root = getHumanoid(p.Player)
	if humanoid and root then
		humanoid.Sit = false
		root.AssemblyLinearVelocity = velocity
	end
	-- Персонаж принадлежит клиенту (network owner) — он же гарантированно применит импульс у себя.
	GameStateUpdate:FireAllClients("LAUNCH", { UserId = p.UserId, Velocity = velocity, Kind = kind })
end

------------------------------------------------------------------------
-- ПОСАДКА
------------------------------------------------------------------------

local function onSeatOccupantChanged(index: number)
	local info = world.SeatInfos[index]
	local seat = info.Seat
	local occupant = seat.Occupant
	local previous = seatOccupants[index]
	local newPlayer: Player? = nil
	local character = occupant and occupant.Parent
	if character and character:IsA("Model") then
		newPlayer = Players:GetPlayerFromCharacter(character)
	end
	seatOccupants[index] = newPlayer
	info.Prompt.Enabled = occupant == nil

	if previous and previous ~= newPlayer then
		local p = findParticipant(previous)
		if p and p.Status == "ACTIVE" and state.MatchActive then
			p.Status = "LEFT"
			eliminatedThisMatch[p.UserId] = true
			notice(string.upper(p.Name) .. " ABANDONED THE TABLE", "WARN")
		end
	end
	if newPlayer and newPlayer ~= previous then
		if state.MatchActive then
			if eliminatedThisMatch[newPlayer.UserId] then
				notice("YOU ARE OUT FOR THIS MATCH — SPECTATING", "INFO", newPlayer)
			else
				notice("SEATED — YOU JOIN AT THE NEXT CYCLE", "INFO", newPlayer)
			end
		end
	end
	broadcastState()
end

for index, info in world.SeatInfos do
	seatOccupants[index] = nil
	info.Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onSeatOccupantChanged(index)
	end)
	info.Prompt.Triggered:Connect(function(player: Player)
		local humanoid, root = getHumanoid(player)
		if not humanoid or not root then
			return
		end
		if info.Seat.Occupant ~= nil or info.Seat.Disabled or humanoid.SeatPart ~= nil then
			return
		end
		if (root.Position - info.Seat.Position).Magnitude > info.Prompt.MaxActivationDistance + 4 then
			return
		end
		info.Seat:Sit(humanoid)
	end)
end

------------------------------------------------------------------------
-- ДЕЙСТВИЯ ИГРОКА
------------------------------------------------------------------------

PlayerAction.OnServerEvent:Connect(function(player: Player, action: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local t = os.clock()
	if t - (lastActionAt[player] or 0) < 0.2 then
		return
	end
	lastActionAt[player] = t

	local active = state.Active
	if state.Phase ~= "CHOICE" or not active or active.Player ~= player or pendingAction ~= nil then
		return
	end
	if action == "EXTRACT" or action == "EJECT" then
		pendingAction = action
	elseif action == "OVERCLOCK" then
		if state.Instability >= CONFIG.OverclockMaxInstability then
			notice("OVERCLOCK LOCKED — INSTABILITY ≥ " .. CONFIG.OverclockMaxInstability .. "%", "BAD", player)
			return
		end
		pendingAction = action
	end
end)

MicroGameStatus.OnServerEvent:Connect(function(player: Player, kind: unknown, payload: unknown)
	if kind == "SYNC" then
		GameStateUpdate:FireClient(player, "STATE", snapshot())
		local mg = micro
		if mg then
			MicroGameStatus:FireClient(player, "START", {
				UserId = mg.Player.UserId,
				StartTime = mg.StartTime,
				Duration = mg.Duration,
				Grace = mg.Grace,
				Params = mg.Params,
				Drift = mg.Drift,
				Rod = mg.Rod,
			})
		end
	elseif kind == "ACK" then
		local mg = micro
		if mg and mg.Player == player and typeof(payload) == "number" and math.abs(payload - mg.StartTime) < 1e-3 then
			mg.Acked = true
		end
	end
end)

-- Телеметрия клешни ~15 Гц. Проверяем всё: тип, NaN, частоту, часы и скорость курсора.
ReplicateManipulator.OnServerEvent:Connect(function(player: Player, clientT: unknown, cursor: unknown, jitterX: unknown, jitterZ: unknown)
	local mg = micro
	if not mg or mg.Player ~= player or mg.Result ~= nil then
		return
	end
	if typeof(clientT) ~= "number" or typeof(cursor) ~= "number" or typeof(jitterX) ~= "number" or typeof(jitterZ) ~= "number" then
		return
	end
	if clientT ~= clientT or cursor ~= cursor or jitterX ~= jitterX or jitterZ ~= jitterZ then
		return -- NaN
	end
	local clock = os.clock()
	if clock - mg.LastPacket < CONFIG.TelemetryMinGap then
		return -- флуд
	end

	local serverT = now() - mg.StartTime
	local t = math.clamp(clientT, serverT - CONFIG.MaxClockSkew, serverT)
	if t < mg.CursorT then
		t = mg.CursorT -- время не идёт назад
	end
	local elapsed = math.max(t - mg.CursorT, 0)
	local maxStep = CONFIG.CursorMaxSpeed * elapsed + 0.02
	local accepted = math.clamp(cursor, mg.Cursor - maxStep, mg.Cursor + maxStep)

	mg.Cursor = math.clamp(accepted, 0, 1)
	mg.CursorT = t
	mg.LastPacket = clock
	mg.JitterX = math.clamp(jitterX, -1, 1)
	mg.JitterZ = math.clamp(jitterZ, -1, 1)

	-- Ретрансляция зрителям: курсор клиента + авторитетные прогресс и скрежет
	ReplicateManipulator:FireAllClients(player.UserId, mg.Cursor, mg.JitterX, mg.JitterZ, mg.Scraping, mg.Progress)
end)

------------------------------------------------------------------------
-- ОЖИДАНИЕ
------------------------------------------------------------------------

-- Ждёт duration секунд; прерывается, когда stop() вернёт true. Возвращает true, если прервано.
local function waitUntil(duration: number, stop: () -> boolean): boolean
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if stop() then
			return true
		end
		task.wait(0.05)
	end
	return stop()
end

------------------------------------------------------------------------
-- ДЕТОНАЦИЯ
------------------------------------------------------------------------

local function detonate(p: Participant, reason: string)
	setInstability(100)
	local burned = math.floor(state.Pot * CONFIG.DetonationPotBurn)
	state.Pot -= burned
	setPhase("DETONATION", CONFIG.DetonationCooldown, "CORE CRITICAL — " .. reason)

	CoreDetonate:FireAllClients({
		VictimUserId = p.UserId,
		Reason = reason,
		Origin = world.CoreCenter,
		Burned = burned,
	})

	-- Видимый (безвредный) взрыв: давление 0, суставы не рвутся
	local explosion = Instance.new("Explosion")
	explosion.Position = world.CoreCenter + Vector3.new(0, 1, 0)
	explosion.BlastRadius = 10
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = Workspace

	if p.Status == "ACTIVE" then
		p.Status = "BLASTED"
		eliminatedThisMatch[p.UserId] = true
		launchFromSeat(p, CONFIG.BlastSpeed, CONFIG.BlastLift, "BLAST")
	end
	notice(string.format("☢ DETONATION — %s BLASTED. %s OF THE POT VAPORIZED", string.upper(p.Name), formatMoney(burned)), "BAD")
	broadcastState()

	task.wait(CONFIG.DetonationCooldown)

	setInstability(CONFIG.PostDetonationInstability)
	state.Overclock = 1
	state.DriftNext = 1
	setPhase("RESOLVE", 1, "CORE COOLED — CONTAINMENT RESTORED")
	task.wait(1)
end

------------------------------------------------------------------------
-- МИНИ-ИГРА: ИЗВЛЕЧЕНИЕ ТОПЛИВНОГО СТЕРЖНЯ
------------------------------------------------------------------------

local function runMicroGame(p: Participant, drift: number)
	local speed = CONFIG.SweetBaseSpeed * (1 + state.Instability / 100 * 0.6) * (1 + CONFIG.OverclockSpeedFactor * (drift - 1))
	local halfWidth = CONFIG.SweetHalfWidth / (1 + CONFIG.OverclockWidthFactor * (drift - 1))
	local params: SweetParams = {
		Phase1 = rng:NextNumber(0, math.pi * 2),
		Phase2 = rng:NextNumber(0, math.pi * 2),
		Phase3 = rng:NextNumber(0, math.pi * 2),
		Speed = speed,
		HalfWidth = halfWidth,
	}
	local rod = rng:NextInteger(1, #world.FuelRods)
	local mg: MicroGame = {
		Player = p.Player,
		Participant = p,
		StartTime = now(),
		Duration = CONFIG.MicroGameTime,
		Grace = CONFIG.MicroGameGrace,
		Params = params,
		Drift = drift,
		Rod = rod,
		Progress = 0,
		Cursor = 0,
		CursorT = 0,
		LastPacket = os.clock(),
		JitterX = 0,
		JitterZ = 0,
		Scraping = false,
		Acked = false,
		Result = nil,
	}
	micro = mg
	coreModel:SetAttribute("ActiveRod", rod)
	setPhase("MICROGAME", CONFIG.MicroGameTime, "EXTRACTING ROD " .. rod .. " — " .. string.upper(p.Name))

	MicroGameStatus:FireAllClients("START", {
		UserId = p.UserId,
		StartTime = mg.StartTime,
		Duration = mg.Duration,
		Grace = mg.Grace,
		Params = params,
		Drift = drift,
		Rod = rod,
	})

	local lastTick = 0
	while mg.Result == nil do
		local dt = task.wait()
		local t = now() - mg.StartTime

		if not isParticipantValid(p) then
			mg.Result = "ABANDONED"
			break
		end

		if t >= mg.Grace then
			local stale = os.clock() - mg.LastPacket > CONFIG.TelemetryStale
			local center = sweetCenter(mg.CursorT, params)
			local inside = (not stale) and math.abs(mg.Cursor - center) <= params.HalfWidth
			if inside then
				mg.Progress = math.min(1, mg.Progress + CONFIG.ProgressRate * dt)
			else
				mg.Progress = math.max(0, mg.Progress - CONFIG.ProgressDecay * dt)
				setInstability(state.Instability + CONFIG.ScrapeRate * dt)
			end
			mg.Scraping = not inside
		end

		if mg.Progress >= 1 then
			mg.Result = "SUCCESS"
		elseif state.Instability >= 100 then
			mg.Result = "CRITICAL"
		elseif t >= mg.Duration then
			mg.Result = "TIMEOUT"
		end

		if os.clock() - lastTick >= 0.1 then
			lastTick = os.clock()
			MicroGameStatus:FireAllClients("TICK", {
				UserId = p.UserId,
				Progress = mg.Progress,
				Instability = state.Instability,
				Scraping = mg.Scraping,
			})
		end
	end

	local result = mg.Result :: string
	micro = nil
	coreModel:SetAttribute("ActiveRod", 0)
	MicroGameStatus:FireAllClients("STOP", { UserId = p.UserId, Result = result, Progress = mg.Progress })

	if result == "SUCCESS" then
		local reward = math.floor(CONFIG.ExtractReward * state.Overclock)
		state.Pot += reward
		setInstability(state.Instability - CONFIG.ExtractCool)
		setPhase("RESOLVE", CONFIG.ResolvePause, string.format("ROD SECURED +%s", formatMoney(reward)))
		notice(string.format("%s EXTRACTED A FUEL ROD  +%s", string.upper(p.Name), formatMoney(reward)), "GOOD")
		task.wait(CONFIG.ResolvePause)
	elseif result == "CRITICAL" then
		detonate(p, "INSTABILITY 100%")
	elseif result == "TIMEOUT" then
		detonate(p, "EXTRACTION TIMEOUT")
	else
		setPhase("RESOLVE", 1, "OPERATOR LOST — ROD DROPPED")
		task.wait(1)
	end
end

------------------------------------------------------------------------
-- ХОД
------------------------------------------------------------------------

local function runTurn(p: Participant)
	state.Active = p
	p.Turns += 1
	state.CurrentDrift = state.DriftNext
	state.DriftNext = 1
	-- Ядро нагревается само по себе, но одно лишь тепло его не взорвёт
	setInstability(math.min(state.Instability + CONFIG.TurnHeat, 99))

	pendingAction = nil
	setPhase("CHOICE", CONFIG.ChoiceTime, string.upper(p.Name) .. " — CHOOSE")
	if state.CurrentDrift > 1 then
		notice(string.format("%s INHERITS AN OVERCLOCKED CORE — TREMOR x%d", string.upper(p.Name), state.CurrentDrift), "WARN")
	end

	waitUntil(CONFIG.ChoiceTime, function()
		return pendingAction ~= nil or not isParticipantValid(p)
	end)

	if not isParticipantValid(p) then
		state.Active = nil
		broadcastState()
		return
	end

	local action = pendingAction or "EXTRACT"
	if pendingAction == nil then
		notice(string.upper(p.Name) .. " FROZE — THE MACHINE CHOOSES: EXTRACT", "WARN")
	end
	pendingAction = nil

	if action == "OVERCLOCK" then
		setInstability(state.Instability + CONFIG.OverclockInstability)
		state.Pot += CONFIG.OverclockPot
		state.Overclock = math.min(state.Overclock + CONFIG.OverclockMultStep, CONFIG.OverclockMultMax)
		state.DriftNext = CONFIG.OverclockDrift
		GameStateUpdate:FireAllClients("FX", { Type = "OVERCLOCK", UserId = p.UserId })
		notice(string.format("%s OVERCLOCKED THE CORE  +%s  ×%.1f", string.upper(p.Name), formatMoney(CONFIG.OverclockPot), state.Overclock), "WARN")
		setPhase("RESOLVE", CONFIG.ResolvePause, "OVERCLOCK INJECTED")
		task.wait(CONFIG.ResolvePause)
	elseif action == "EJECT" then
		local amount = math.floor(state.Pot * CONFIG.EjectShare)
		state.Pot -= amount
		addStat(p.Player, "Cash", amount)
		p.Status = "EJECTED"
		eliminatedThisMatch[p.UserId] = true
		launchFromSeat(p, CONFIG.EjectSpeed, CONFIG.EjectLift, "EJECT")
		notice(string.format("%s HIT EMERGENCY EJECT  —  BANKED %s", string.upper(p.Name), formatMoney(amount)), "INFO")
		setPhase("RESOLVE", CONFIG.ResolvePause, string.upper(p.Name) .. " BAILED OUT")
		task.wait(CONFIG.ResolvePause)
	else
		runMicroGame(p, state.CurrentDrift)
	end

	state.Active = nil
	broadcastState()
end

------------------------------------------------------------------------
-- МАТЧ
------------------------------------------------------------------------

local function addSeatedParticipants()
	for index, player in seatOccupants do
		if player and not eliminatedThisMatch[player.UserId] then
			local existing = findParticipant(player)
			if existing == nil then
				table.insert(state.Participants, {
					Player = player,
					UserId = player.UserId,
					Name = player.DisplayName,
					SeatIndex = index,
					Status = "ACTIVE",
					Turns = 0,
				})
			elseif existing.Status == "ACTIVE" then
				existing.SeatIndex = index
			end
		end
	end
	table.sort(state.Participants, function(a: Participant, b: Participant)
		return a.SeatIndex < b.SeatIndex
	end)
end

local function finishMatch()
	local survivors: { Participant } = {}
	for _, p in state.Participants do
		if p.Status == "ACTIVE" and p.Player.Parent == Players then
			table.insert(survivors, p)
		end
	end

	if #survivors > 0 then
		local share = math.floor(state.Pot / #survivors)
		local names = {}
		for _, p in survivors do
			p.Status = "SURVIVOR"
			addStat(p.Player, "Cash", share)
			addStat(p.Player, "Wins", 1)
			table.insert(names, string.upper(p.Name))
		end
		notice(string.format("CYCLE COMPLETE — %s SURVIVED  +%s EACH", table.concat(names, ", "), formatMoney(share)), "GOOD")
		setPhase("MATCH_END", CONFIG.MatchEndPause, "SURVIVORS PAID " .. formatMoney(share))
	else
		notice("NO SURVIVORS — THE POT IS LOST TO THE CORE", "BAD")
		setPhase("MATCH_END", CONFIG.MatchEndPause, "POT LOST")
	end
	task.wait(CONFIG.MatchEndPause)

	state.MatchActive = false
	state.Active = nil
	state.Participants = {}
	table.clear(eliminatedThisMatch)
	for _, p in Players:GetPlayers() do
		saveBank(p)
	end
end

local function runMatch()
	state.MatchId += 1
	state.MatchActive = true
	state.Pot = CONFIG.StartingPot
	state.Overclock = 1
	state.DriftNext = 1
	state.CurrentDrift = 1
	state.Cycle = 0
	state.Participants = {}
	table.clear(eliminatedThisMatch)
	setInstability(CONFIG.StartingInstability)

	for cycle = 1, CONFIG.MaxCycles do
		state.Cycle = cycle
		addSeatedParticipants()
		if countActive() == 0 then
			break
		end
		notice(string.format("CYCLE %d / %d", cycle, CONFIG.MaxCycles), "INFO")

		-- Копия списка: участники могут добавляться только в начале цикла
		local order = table.clone(state.Participants)
		for _, p in order do
			if isParticipantValid(p) then
				runTurn(p)
			elseif p.Status == "ACTIVE" then
				p.Status = "LEFT"
			end
			if countActive() == 0 then
				break
			end
		end
		if countActive() == 0 then
			break
		end
	end

	finishMatch()
end

------------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ
------------------------------------------------------------------------

local function gameLoop()
	while true do
		state.Active = nil
		setPhase("LOBBY", nil, "AWAITING OPERATORS — SIT AT THE TABLE")
		while countSeated() < CONFIG.MinPlayers do
			task.wait(0.25)
		end

		setPhase("COUNTDOWN", CONFIG.CountdownTime, "MATCH IGNITION")
		local aborted = waitUntil(CONFIG.CountdownTime, function()
			return countSeated() < CONFIG.MinPlayers
		end)
		if not aborted then
			runMatch()
			setPhase("INTERMISSION", CONFIG.IntermissionTime, "RECALIBRATING CORE")
			setInstability(CONFIG.StartingInstability)
			task.wait(CONFIG.IntermissionTime)
		end
	end
end

------------------------------------------------------------------------
-- ИГРОКИ
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
	setupLeaderstats(player)
	GameStateUpdate:FireClient(player, "STATE", snapshot())
end)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local p = findParticipant(player)
	if p and p.Status == "ACTIVE" then
		p.Status = "LEFT"
		notice(string.upper(p.Name) .. " DISCONNECTED", "WARN")
	end
	for index, occupant in seatOccupants do
		if occupant == player then
			seatOccupants[index] = nil
			world.SeatInfos[index].Prompt.Enabled = true
		end
	end
	saveBank(player)
	loadedPlayers[player] = nil
	lastActionAt[player] = nil
	broadcastState()
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveBank(player)
	end
end)

-- Телеметрия ЭЛТ ~10 Гц
task.spawn(function()
	while true do
		updateCRT()
		task.wait(0.1)
	end
end)

task.spawn(gameLoop)
