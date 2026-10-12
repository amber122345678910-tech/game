--!strict
-- Серверные 3D-звуки (слышат все): голоса пациентов, стук, стекло, ловушки, выстрел.
-- ID — только проверенные публичные ассеты (ProSoundEffects / APM / Roblox).

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local ServerSounds = {}

ServerSounds.Ids = {
	Knock = "rbxassetid://9114141047",
	KnockFar = "rbxassetid://9114140488",
	Pound = "rbxassetid://9114141413",
	Glass = "rbxassetid://9114590265",
	DoorOpen = "rbxassetid://9120838480",
	DoorClose = "rbxassetid://9120839581",
	DoorSlam = "rbxassetid://9114153270",
	Lock = "rbxassetid://9113849445",
	WoodBreak = "rbxassetid://9116524438",
	Switch = "rbxassetid://9120484192",
	Arc = "rbxassetid://9114237705",
	TrapSnap = "rbxassetid://9116524438",
	Shotgun = "rbxassetid://9120016738",
	StunZap = "rbxassetid://9114237705",
	Spray = "rbxassetid://9113286969",
	Beep = "rbxassetid://9113399767",
	Mumble = "rbxassetid://9126213995",
	Breathing = "rbxassetid://9113586520",
	LanternCreak = "rbxassetid://9114839600",
	Creak = "rbxassetid://9125563505",
	Whistle = "rbxassetid://9117181540",
	MusicBox = "rbxassetid://9043210026",
	Whisper = "rbxassetid://9043347008",
	Keys = "rbxassetid://9113849445",
	Click = "rbxassetid://9114479661",
	BossRumble = "rbxassetid://9112863181",
	Growl = "rbxassetid://9114628818",
	ScreamShort = "rbxassetid://9114399467",
	Gasp = "rbxassetid://9114393946",
	Pickup = "rbxassetid://17208319162",
	Coin = "rbxassetid://127645268874265",
	TvStatic = "rbxassetid://9118013972",
	AlertTone = "rbxassetid://9113089565",
	PhoneRing = "rbxassetid://9113750581",
	Siren = "rbxassetid://9112871822",
	VanIdle = "rbxassetid://9125349929",
	Stomp = "rbxassetid://9113472798",
} :: { [string]: string }

ServerSounds.Pitch = {
	Mumble = 0.7,
	Whistle = 1.6,
	Click = 0.6,
	Shotgun = 1.3,
	Spray = 1.5,
	Growl = 0.8,
} :: { [string]: number }

local function group(): SoundGroup?
	local g = SoundService:FindFirstChild("SFX")
	return if g and g:IsA("SoundGroup") then g else nil
end

local function make(key: string, volume: number?, pitch: number?): Sound?
	local id = ServerSounds.Ids[key]
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = (pitch or 1) * (ServerSounds.Pitch[key] or 1)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 120
	s.SoundGroup = group()
	return s
end

-- Разовый звук на детали (или в точке мира)
function ServerSounds.playOn(key: string, parent: Instance, volume: number?, pitch: number?, maxDistance: number?): Sound?
	local s = make(key, volume, pitch)
	if not s then
		return nil
	end
	if maxDistance then
		s.RollOffMaxDistance = maxDistance
	end
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 12)
	return s
end

local holder: Folder? = nil
local function holderFolder(): Folder
	local h = holder
	if h and h.Parent then
		return h
	end
	local f = Instance.new("Folder")
	f.Name = "ServerSounds"
	f.Parent = workspace
	holder = f
	return f
end

function ServerSounds.playAt(key: string, position: Vector3, volume: number?, pitch: number?, maxDistance: number?): Sound?
	local p = Instance.new("Part")
	p.Name = "SoundPoint"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(position)
	p.Parent = holderFolder()
	Debris:AddItem(p, 12)
	return ServerSounds.playOn(key, p, volume, pitch, maxDistance)
end

-- Зацикленный звук на детали (голос пациента). Вернёт Sound, чтобы остановить.
function ServerSounds.loopOn(key: string, parent: Instance, volume: number?, pitch: number?, maxDistance: number?): Sound?
	local s = make(key, volume, pitch)
	if not s then
		return nil
	end
	s.Looped = true
	if maxDistance then
		s.RollOffMaxDistance = maxDistance
	end
	s.Parent = parent
	s:Play()
	return s
end

return ServerSounds
