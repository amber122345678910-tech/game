--!strict
-- Фоновый звук по контексту: двор ночью (сверчки/ветер) или дом (комнатный тон + скрипы) — по объёму
-- House.Rooms, в котором находится камера (атрибут Outdoor); капель в подвале; музыка лобби в
-- Lobby/Countdown/Results; тихая тревожная подложка ночью; музыка рассвета; случайные одиночные звуки
-- (скрип, собака, сова, проезжающая машина) раз в 20–50 с в 15–40 стадах от игрока только ночью.
-- Голоса пациентов — зацикленный звук на HumanoidRootPart каждого Model в workspace.Inmates.
-- Кроссфейд 1.5 с. Громкость групп: Music ← Settings.Music, SFX/Ambience/UI ← Settings.Sfx.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Inmates = require(Shared:WaitForChild("Inmates"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Ambience = {}

local CROSSFADE = 1.5
local EVAL_INTERVAL = 0.25
local ROOMS_REFRESH = 3
local ONESHOT_MIN, ONESHOT_MAX = 20, 50
local ONESHOT_DIST_MIN, ONESHOT_DIST_MAX = 15, 40
local LOBBY_RADIUS = 160

local INDOOR_ONESHOTS = { "FloorCreak", "Creak", "CreakBig", "Drawer" }
local OUTDOOR_ONESHOTS = { "DogFar", "Owl", "CarPass", "Owl", "DogFar" }

type Bed = {
	Name: string,
	Group: Sounds.GroupName,
	Sound: Sound?,
	Current: number,
}

local function bed(name: string, group: Sounds.GroupName): Bed
	return { Name = name, Group = group, Sound = nil, Current = 0 }
end

local beds: { [string]: Bed } = {
	AmbNight = bed("AmbNight", "Ambience"),
	Wind = bed("Wind", "Ambience"),
	RoomTone = bed("RoomTone", "Ambience"),
	HouseCreaks = bed("HouseCreaks", "Ambience"),
	Drip = bed("Drip", "Ambience"),
	LobbyMusic = bed("LobbyMusic", "Music"),
	TensionBed = bed("TensionBed", "Music"),
	DawnMusic = bed("DawnMusic", "Music"),
}

type Context = {
	Room: string,
	Outdoor: boolean,
	InLobby: boolean,
}

local player = Players.LocalPlayer
local evalTimer = 0
local roomsTimer = ROOMS_REFRESH
local rooms: { BasePart } = {}
local oneshotTimer = 0
local lastContext: Context = { Room = "", Outdoor = true, InLobby = true }
local voices: { [Model]: Sound } = {}
local inmateConns: { RBXScriptConnection } = {}

----------------------------------------------------------------------
-- Громкость групп
----------------------------------------------------------------------

local function applyVolumes(settings: { [string]: any })
	local music = if typeof(settings.Music) == "number" then settings.Music else 0.8
	local sfx = if typeof(settings.Sfx) == "number" then settings.Sfx else 1
	Sounds.group("Music").Volume = math.clamp(music, 0, 1)
	Sounds.group("SFX").Volume = math.clamp(sfx, 0, 1)
	Sounds.group("Ambience").Volume = math.clamp(sfx, 0, 1)
	Sounds.group("UI").Volume = math.clamp(sfx, 0, 1) * 0.8
end

----------------------------------------------------------------------
-- Контекст: комната, двор, лобби
----------------------------------------------------------------------

local function refreshRooms()
	table.clear(rooms)
	local house = workspace:FindFirstChild("House")
	local folder = if house then house:FindFirstChild("Rooms") else nil
	if not folder then
		return
	end
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(rooms, part)
		end
	end
end

local function roomAt(pos: Vector3): BasePart?
	for _, part in rooms do
		if part.Parent == nil then
			continue
		end
		local rel = part.CFrame:PointToObjectSpace(pos)
		local half = part.Size * 0.5
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
			return part
		end
	end
	return nil
end

local function contextAt(pos: Vector3): Context
	local inLobby = (pos - Config.Map.LobbyOrigin).Magnitude < LOBBY_RADIUS
	local part = if inLobby then nil else roomAt(pos)
	if part then
		local name = part:GetAttribute("RoomName")
		return {
			Room = if typeof(name) == "string" then name else part.Name,
			Outdoor = part:GetAttribute("Outdoor") == true,
			InLobby = false,
		}
	end
	return { Room = "", Outdoor = true, InLobby = inLobby }
end

----------------------------------------------------------------------
-- Подложки
----------------------------------------------------------------------

local function setBed(key: string, scale: number)
	local b = beds[key]
	if not b then
		return
	end
	local target = Sounds.baseVolume(b.Name) * math.clamp(scale, 0, 1)
	if math.abs(target - b.Current) < 0.005 then
		return
	end
	b.Current = target
	if target <= 0.001 then
		if b.Sound then
			Sounds.fadeOut(b.Sound, CROSSFADE)
			b.Sound = nil
		end
		return
	end
	if not b.Sound then
		b.Sound = Sounds.loop(b.Name, b.Group, 0)
	end
	Sounds.fadeTo(b.Sound, target, CROSSFADE)
end

local function evaluate()
	local cam = workspace.CurrentCamera
	local pos = if cam then cam.CFrame.Position else Vector3.zero
	local ctx = contextAt(pos)
	lastContext = ctx

	local phase = ClientState.Snapshot.Phase
	local night = phase == "Night" or phase == "Alert"
	local day = phase == "Day"
	local dawn = phase == "Dawn"
	local lobbyPhase = phase == "Lobby" or phase == "Countdown" or phase == "Results"
	local outdoor = ctx.Outdoor

	setBed("AmbNight", if day then 0 elseif outdoor then 1 else 0.3)
	setBed("Wind", if outdoor then (if day then 1 else 0.4) else 0.1)
	setBed("RoomTone", if outdoor then 0 else 1)
	setBed("HouseCreaks", if outdoor then 0 elseif night then 1 else 0.35)
	setBed("Drip", if ctx.Room == "Basement" then 1 else 0)
	setBed("LobbyMusic", if lobbyPhase then 1 else 0)
	setBed("TensionBed", if night then 1 else 0)
	setBed("DawnMusic", if dawn then 1 else 0)

	local reverb = if outdoor
		then Enum.ReverbType.NoReverb
		elseif ctx.Room == "Basement" then Enum.ReverbType.StoneRoom
		else Enum.ReverbType.Room
	if SoundService.AmbientReverb ~= reverb then
		SoundService.AmbientReverb = reverb
	end
end

----------------------------------------------------------------------
-- Одиночные звуки ночью
----------------------------------------------------------------------

local function scheduleOneshot()
	oneshotTimer = ONESHOT_MIN + math.random() * (ONESHOT_MAX - ONESHOT_MIN)
end

local function playOneshot()
	local status = ClientState.Status
	if not ClientState.isNight() or (status ~= "Alive" and status ~= "Hiding") then
		return
	end
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local pool = if lastContext.Outdoor then OUTDOOR_ONESHOTS else INDOOR_ONESHOTS
	local name = pool[math.random(1, #pool)]
	local angle = math.random() * math.pi * 2
	local dist = ONESHOT_DIST_MIN + math.random() * (ONESHOT_DIST_MAX - ONESHOT_DIST_MIN)
	local pos = root.Position + Vector3.new(math.cos(angle) * dist, -1 + math.random() * 4, math.sin(angle) * dist)
	Sounds.playAt(name, pos, 0.5 + math.random() * 0.4)
end

----------------------------------------------------------------------
-- Голоса пациентов
----------------------------------------------------------------------

local function attachVoice(model: Instance)
	if not model:IsA("Model") or voices[model] then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 8)
		if not root or not root:IsA("BasePart") or model.Parent == nil or voices[model] then
			return
		end
		local idAttr = model:GetAttribute("InmateId")
		local id = if typeof(idAttr) == "string" then idAttr else model.Name
		local def = Inmates.get(id)
		local voice = if def then def.Sounds.Voice else ""
		if voice == "" or root:FindFirstChild(voice) then
			return
		end
		local s = Sounds.loopAt(voice, root, 0.9)
		if not s then
			return
		end
		if def and def.Kind == "Sentinel" then
			-- колыбельная слышна за две комнаты
			s.RollOffMaxDistance = def.LullabyRange
		end
		voices[model] = s
	end)
end

local function detachVoice(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local s = voices[model]
	if s then
		voices[model] = nil
		Sounds.stop(s)
	end
end

local function bindInmatesFolder(folder: Instance)
	for _, c in inmateConns do
		c:Disconnect()
	end
	table.clear(inmateConns)
	for _, child in folder:GetChildren() do
		attachVoice(child)
	end
	table.insert(inmateConns, folder.ChildAdded:Connect(attachVoice))
	table.insert(inmateConns, folder.ChildRemoved:Connect(detachVoice))
end

----------------------------------------------------------------------

function Ambience.init()
	applyVolumes(ClientState.Settings)
	ClientState.SettingsChanged:Connect(applyVolumes)
	ClientState.StateChanged:Connect(function()
		evalTimer = EVAL_INTERVAL
	end)
	ClientState.StatusChanged:Connect(function()
		evalTimer = EVAL_INTERVAL
	end)

	local existing = workspace:FindFirstChild("Inmates")
	if existing then
		bindInmatesFolder(existing)
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Inmates" then
			bindInmatesFolder(child)
		end
	end)

	refreshRooms()
	scheduleOneshot()

	RunService.Heartbeat:Connect(function(dt: number)
		roomsTimer += dt
		if roomsTimer >= ROOMS_REFRESH then
			roomsTimer = 0
			refreshRooms()
		end
		evalTimer += dt
		if evalTimer >= EVAL_INTERVAL then
			evalTimer = 0
			evaluate()
		end
		oneshotTimer -= dt
		if oneshotTimer <= 0 then
			scheduleOneshot()
			playOneshot()
		end
	end)
end

return Ambience
