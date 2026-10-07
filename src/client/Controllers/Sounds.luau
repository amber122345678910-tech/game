--!strict
-- Звуки игры. Все ID в одном месте — их легко заменить в Studio.
-- Если звук не загрузится (ID недоступен), игра продолжит работать, просто без этого звука.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sounds = {}

-- Встроенные звуки клиента Roblox (rbxasset://) есть всегда.
-- Звуки каталога Roblox (rbxassetid://) — публичные звуки, загруженные самим Roblox.
Sounds.Ids = {
	Click = "",
	Purchase = "",
	Error = "",
	Success = "",
	Rain = "",
	Thunder = "",
	HailHit = "",
	BlockBreak = "",
	Leak = "",
	DoorOpen = "",
	DoorClose = "",
	Place = "",
} :: { [string]: string }

Sounds.Volumes = {
	Click = 0.5,
	Purchase = 0.6,
	Error = 0.5,
	Success = 0.7,
	Rain = 0.5,
	Thunder = 0.8,
	HailHit = 0.45,
	BlockBreak = 0.6,
	Leak = 0.6,
	DoorOpen = 0.5,
	DoorClose = 0.5,
	Place = 0.5,
} :: { [string]: number }

local templates: { [string]: Sound } = {}
local holder: Part? = nil
local activeOneShots = 0
local MAX_ONE_SHOTS = 12

local function getHolder(): Part
	local h = holder
	if h and h.Parent then
		return h
	end
	local p = Instance.new("Part")
	p.Name = "SoundHolder"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new()
	local folder = workspace:FindFirstChild("ClientFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientFX"
		folder.Parent = workspace
	end
	p.Parent = folder
	holder = p
	return p
end

local function template(name: string): Sound?
	local existing = templates[name]
	if existing then
		return existing
	end
	local id = Sounds.Ids[name]
	if not id or id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = Sounds.Volumes[name] or 0.5
	s.Parent = SoundService
	templates[name] = s
	return s
end

-- Звук интерфейса (не зависит от положения).
function Sounds.playUI(name: string)
	local s = template(name)
	if s then
		SoundService:PlayLocalSound(s)
	end
end

-- Получить шаблон (например, для звука клика кнопок).
function Sounds.get(name: string): Sound?
	return template(name)
end

-- Разовый 3D-звук в точке мира.
function Sounds.playAt(name: string, position: Vector3, volumeScale: number?)
	local base = template(name)
	if not base or activeOneShots >= MAX_ONE_SHOTS then
		return
	end
	activeOneShots += 1
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	local s = base:Clone()
	s.Volume = base.Volume * (volumeScale or 1)
	s.PlaybackSpeed = 0.9 + math.random() * 0.2
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 140
	s.Parent = att
	att.Parent = getHolder()
	s:Play()
	Debris:AddItem(att, 6)
	task.delay(6, function()
		activeOneShots -= 1
	end)
end

-- Зацикленный 3D-звук на объекте (дождь, протечка). Вернёт Sound, чтобы потом удалить.
function Sounds.loopAt(name: string, parent: Instance, volumeScale: number?): Sound?
	local base = template(name)
	if not base then
		return nil
	end
	local s = base:Clone()
	s.Looped = true
	s.Volume = base.Volume * (volumeScale or 1)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 200
	s.Parent = parent
	s:Play()
	return s
end

return Sounds
