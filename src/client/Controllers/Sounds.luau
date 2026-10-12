--!strict
-- Банк звуков клиента. Все asset ID — публичные (Roblox / партнёрские библиотеки); у коротких звуков есть
-- запасной rbxasset:// на случай, если ID не загрузится. Звуки раскладываются по SoundGroup'ам
-- (UI / SFX / Ambience / Music); есть разовые 3D-звуки, зацикленные (позиционные и нет), плавное
-- затухание и предзагрузка с подменой на фолбэк при ошибке.

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Sounds = {}

export type GroupName = "UI" | "SFX" | "Ambience" | "Music"

type Def = {
	Id: number,
	Group: GroupName?,
	Volume: number?,
	Pitch: number?,
	Fallback: string?,
	Cutoff: number?, -- секунд, после которых разовый звук обрывается
	RollOff: { number }?, -- { min, max } для 3D-звуков
}

-- Встроенные звуки клиента (есть всегда)
local FB_UI = "rbxasset://sounds/button.wav"
local FB_SLIDER = "rbxasset://sounds/volume_slider.ogg"
local FB_PING = "rbxasset://sounds/electronicpingshort.wav"
local FB_LAND = "rbxasset://sounds/action_jump_land.mp3"
local FB_BOOM = "rbxasset://sounds/impact_explosion_03.mp3"
local FB_WATER = "rbxasset://sounds/impact_water.mp3"
local FB_OUCH = "rbxasset://sounds/ouch.ogg"
local FB_UUH = "rbxasset://sounds/uuhhh.mp3"
local FB_SNAP = "rbxasset://sounds/snap.mp3"
local FB_SWOOSH = "rbxasset://sounds/swoosh.wav"

local DEFS: { [string]: Def } = {
	-- Интерфейс
	UiClick = { Id = 15675059323, Group = "UI", Volume = 0.5, Fallback = FB_UI },
	UiHover = { Id = 10066931761, Group = "UI", Volume = 0.25, Fallback = FB_SLIDER },
	Success = { Id = 1842057315, Group = "UI", Volume = 0.6, Fallback = FB_PING },
	Fail = { Id = 1844442574, Group = "UI", Volume = 0.5, Fallback = FB_OUCH },
	Coin = { Id = 127645268874265, Group = "UI", Volume = 0.6, Fallback = FB_PING },
	Pickup = { Id = 17208319162, Group = "SFX", Volume = 0.6, Fallback = FB_SNAP },
	Paper = { Id = 9125722939, Group = "UI", Volume = 0.5, Fallback = FB_SWOOSH },
	-- Фоновые петли
	AmbNight = { Id = 9112834179, Group = "Ambience", Volume = 0.5 },
	AmbNightAlt = { Id = 9112835066, Group = "Ambience", Volume = 0.5 },
	Wind = { Id = 9113286969, Group = "Ambience", Volume = 0.45 },
	RoomTone = { Id = 9125446564, Group = "Ambience", Volume = 0.35 },
	HouseCreaks = { Id = 9114834184, Group = "Ambience", Volume = 0.4 },
	Eerie = { Id = 9112775175, Group = "Ambience", Volume = 0.4 },
	FridgeHum = { Id = 9112840423, Group = "Ambience", Volume = 0.35, RollOff = { 6, 30 } },
	BulbBuzz = { Id = 9112823811, Group = "Ambience", Volume = 0.3, RollOff = { 4, 24 } },
	Drone = { Id = 9112795463, Group = "SFX", Volume = 0.6 },
	Pulse = { Id = 9116328633, Group = "SFX", Volume = 0.5 },
	Drip = { Id = 9120526794, Group = "Ambience", Volume = 0.5, Fallback = FB_WATER, RollOff = { 6, 40 } },
	TvStatic = { Id = 9118013972, Group = "Ambience", Volume = 0.5, RollOff = { 8, 45 } },
	RadioStatic = { Id = 9118013971, Group = "Ambience", Volume = 0.4, RollOff = { 6, 35 } },
	VanIdle = { Id = 9125349929, Group = "Ambience", Volume = 0.5, RollOff = { 15, 90 } },
	CarPass = { Id = 9120392088, Group = "Ambience", Volume = 0.5, Fallback = FB_SWOOSH, RollOff = { 20, 160 } },
	-- Тело
	Heartbeat = { Id = 9043365842, Group = "SFX", Volume = 0.7 },
	HeartbeatFast = { Id = 1839998022, Group = "SFX", Volume = 0.7 },
	Breathing = { Id = 9113586520, Group = "SFX", Volume = 0.6 },
	BreathingEerie = { Id = 9113586681, Group = "SFX", Volume = 0.6, RollOff = { 6, 50 } },
	-- Телефон / оповещение
	PhoneBuzz = { Id = 9113085764, Group = "UI", Volume = 0.6, Fallback = FB_PING },
	Notify = { Id = 17208361335, Group = "UI", Volume = 0.5, Fallback = FB_PING },
	AlertTone = { Id = 9113089565, Group = "UI", Volume = 0.7, Fallback = FB_PING },
	AlertShort = { Id = 9114025057, Group = "UI", Volume = 0.6, Fallback = FB_PING },
	PhoneRing = { Id = 9113750581, Group = "SFX", Volume = 0.7, Fallback = FB_PING, RollOff = { 8, 70 } },
	-- Двери, окна
	DoorOpen = { Id = 9120838480, Group = "SFX", Volume = 0.6, Fallback = FB_SNAP, RollOff = { 6, 60 } },
	DoorClose = { Id = 9120839581, Group = "SFX", Volume = 0.6, Fallback = FB_SNAP, RollOff = { 6, 60 } },
	DoorSlam = { Id = 9114153270, Group = "SFX", Volume = 0.8, Fallback = FB_LAND, RollOff = { 8, 90 } },
	Knock = { Id = 9114141047, Group = "SFX", Volume = 0.9, Fallback = FB_LAND, RollOff = { 10, 90 } },
	KnockFar = { Id = 9114140488, Group = "SFX", Volume = 0.7, Fallback = FB_LAND, RollOff = { 10, 120 } },
	Pound = { Id = 9114141413, Group = "SFX", Volume = 0.9, Fallback = FB_LAND, RollOff = { 10, 100 } },
	Doorbell = { Id = 9125492547, Group = "SFX", Volume = 0.7, Fallback = FB_PING, RollOff = { 8, 60 } },
	Glass = { Id = 9114590265, Group = "SFX", Volume = 0.9, Fallback = FB_SNAP, RollOff = { 10, 120 } },
	-- Шаги
	StepWood = { Id = 9125816969, Group = "SFX", Volume = 0.35, Fallback = FB_LAND, RollOff = { 5, 40 } },
	StepConcrete = { Id = 9118247984, Group = "SFX", Volume = 0.35, Fallback = FB_LAND, RollOff = { 5, 40 } },
	StepGrass = { Id = 9114518233, Group = "SFX", Volume = 0.3, Fallback = FB_LAND, RollOff = { 5, 40 } },
	StepHeavy = { Id = 9113472798, Group = "SFX", Volume = 0.8, Fallback = FB_LAND, RollOff = { 8, 70 } },
	FloorCreak = { Id = 9125563505, Group = "SFX", Volume = 0.5, Fallback = FB_SNAP, RollOff = { 6, 50 } },
	Creak = { Id = 9114839600, Group = "SFX", Volume = 0.45, Fallback = FB_SNAP, RollOff = { 6, 50 } },
	CreakBig = { Id = 9114835426, Group = "SFX", Volume = 0.6, Fallback = FB_SNAP, RollOff = { 8, 70 } },
	-- Предметы и механика
	ClosetSlide = { Id = 9114153584, Group = "SFX", Volume = 0.6, Fallback = FB_SWOOSH, RollOff = { 6, 40 } },
	ClosetDoor = { Id = 9113817128, Group = "SFX", Volume = 0.6, Fallback = FB_SNAP, RollOff = { 6, 40 } },
	Drawer = { Id = 9125756882, Group = "SFX", Volume = 0.5, Fallback = FB_SNAP, RollOff = { 6, 40 } },
	Keys = { Id = 9113849445, Group = "SFX", Volume = 0.5, Fallback = FB_SNAP, RollOff = { 6, 45 } },
	FlashlightClick = { Id = 9114479661, Group = "SFX", Volume = 0.5, Fallback = FB_UI },
	Switch = { Id = 9120484192, Group = "SFX", Volume = 0.5, Fallback = FB_UI, RollOff = { 6, 40 } },
	Arc = { Id = 9114237705, Group = "SFX", Volume = 0.7, Fallback = FB_SNAP, RollOff = { 8, 60 } },
	MetalClang = { Id = 9116524438, Group = "SFX", Volume = 0.8, Fallback = FB_LAND, RollOff = { 8, 80 } },
	CarDoor = { Id = 9112968238, Group = "SFX", Volume = 0.6, Fallback = FB_SNAP, RollOff = { 10, 80 } },
	Horn = { Id = 9120382641, Group = "SFX", Volume = 0.6, Fallback = FB_PING, RollOff = { 20, 160 } },
	Screech = { Id = 9113661285, Group = "SFX", Volume = 0.6, Fallback = FB_SWOOSH, RollOff = { 20, 160 } },
	EngineStart = { Id = 9125346576, Group = "SFX", Volume = 0.6, Fallback = FB_BOOM, RollOff = { 15, 120 } },
	Siren = { Id = 9112871822, Group = "Ambience", Volume = 0.4, RollOff = { 30, 220 } },
	DogFar = { Id = 9120051478, Group = "Ambience", Volume = 0.45, RollOff = { 20, 120 } },
	Owl = { Id = 9117181540, Group = "Ambience", Volume = 0.45, RollOff = { 20, 120 } },
	Thunder = { Id = 9120016738, Group = "Ambience", Volume = 0.8, Fallback = FB_BOOM },
	-- Пациенты
	ScreamShort = { Id = 9114399467, Group = "SFX", Volume = 0.8, Fallback = FB_OUCH, RollOff = { 10, 100 } },
	ScreamMale = { Id = 9125652676, Group = "SFX", Volume = 0.8, Fallback = FB_UUH, RollOff = { 10, 100 } },
	HorrorScream = { Id = 9043346594, Group = "SFX", Volume = 0.8, Fallback = FB_UUH, RollOff = { 10, 100 } },
	Growl = { Id = 9114628818, Group = "SFX", Volume = 0.8, Fallback = FB_UUH, RollOff = { 8, 80 } },
	BossRumble = { Id = 9112863181, Group = "SFX", Volume = 0.8, RollOff = { 12, 110 } },
	GrowlLoop = { Id = 9113126313, Group = "SFX", Volume = 0.6, RollOff = { 8, 70 } },
	Snarl = { Id = 9120790555, Group = "SFX", Volume = 0.7, Fallback = FB_UUH, RollOff = { 8, 70 } },
	Mumble = { Id = 9126213995, Group = "SFX", Volume = 0.6, Pitch = 0.7, RollOff = { 6, 55 } },
	Whisper = { Id = 9043347008, Group = "SFX", Volume = 0.6, RollOff = { 6, 50 } },
	Whistle = { Id = 9117181540, Group = "SFX", Volume = 0.6, Pitch = 1.6, RollOff = { 8, 80 } },
	LanternCreak = { Id = 9114839600, Group = "SFX", Volume = 0.5, Fallback = FB_SNAP, RollOff = { 6, 60 } },
	MusicBox = { Id = 9043210026, Group = "SFX", Volume = 0.55, RollOff = { 10, 90 } },
	MusicBoxTwisted = { Id = 138717310622754, Group = "SFX", Volume = 0.55, RollOff = { 10, 90 } },
	Click = { Id = 9114479661, Group = "SFX", Volume = 0.7, Pitch = 0.6, Fallback = FB_UI, RollOff = { 8, 80 } },
	TickTock = { Id = 9043366464, Group = "Ambience", Volume = 0.4, RollOff = { 6, 40 } },
	-- Стингеры и райзеры
	Stinger = { Id = 9043338036, Group = "SFX", Volume = 0.9, Fallback = FB_BOOM },
	StingerOrch = { Id = 9046537373, Group = "SFX", Volume = 0.9, Fallback = FB_BOOM },
	StringShock = { Id = 1843035239, Group = "SFX", Volume = 0.8, Fallback = FB_BOOM },
	FearHit = { Id = 9043338333, Group = "SFX", Volume = 0.8, Fallback = FB_BOOM },
	Riser = { Id = 9048835755, Group = "Music", Volume = 0.6 },
	RiserLong = { Id = 1837834536, Group = "Music", Volume = 0.6 },
	RiserHit = { Id = 1841353894, Group = "Music", Volume = 0.7, Fallback = FB_BOOM },
	BassDrop = { Id = 9043357191, Group = "SFX", Volume = 0.8, Fallback = FB_BOOM },
	-- Музыка
	TensionBed = { Id = 1837463124, Group = "Music", Volume = 0.35 },
	HorrorAtmo = { Id = 1840271919, Group = "Music", Volume = 0.35 },
	ChaseMusic = { Id = 1840028231, Group = "Music", Volume = 0.7 },
	ChaseLong = { Id = 1843789417, Group = "Music", Volume = 0.7 },
	LobbyMusic = { Id = 1838696582, Group = "Music", Volume = 0.3 },
	LobbyAlt = { Id = 1842992846, Group = "Music", Volume = 0.3 },
	DawnMusic = { Id = 1840426570, Group = "Music", Volume = 0.5 },
	DawnLong = { Id = 1839904497, Group = "Music", Volume = 0.5 },
	SunriseSting = { Id = 9042877247, Group = "Music", Volume = 0.7 },
	TitleMusic = { Id = 1837262965, Group = "Music", Volume = 0.4 },
	ChildVocal = { Id = 9043351208, Group = "SFX", Volume = 0.5, RollOff = { 10, 80 } },
	PoliceRadio = { Id = 9117773103, Group = "Ambience", Volume = 0.4, RollOff = { 8, 50 } },
	Dispatch = { Id = 9114310538, Group = "Ambience", Volume = 0.4, RollOff = { 8, 50 } },
	-- Оружие
	ShotgunFire = { Id = 9120016738, Group = "SFX", Volume = 1, Pitch = 1.3, Fallback = FB_BOOM, RollOff = { 15, 200 } },
	StunZap = { Id = 9114237705, Group = "SFX", Volume = 0.8, Fallback = FB_SNAP, RollOff = { 8, 60 } },
	Spray = { Id = 9113286969, Group = "SFX", Volume = 0.7, Pitch = 1.5, Cutoff = 1, Fallback = FB_SWOOSH, RollOff = { 6, 40 } },
}

-- Плоские таблицы (удобно смотреть/править в Studio и использовать из других модулей)
Sounds.Ids = {} :: { [string]: string }
Sounds.Fallbacks = {} :: { [string]: string }
Sounds.Pitch = {} :: { [string]: number }
Sounds.Volumes = {} :: { [string]: number }
Sounds.Groups = {} :: { [string]: GroupName }
Sounds.Cutoff = {} :: { [string]: number }
Sounds.RollOff = {} :: { [string]: { number } }

for name, def in DEFS do
	Sounds.Ids[name] = "rbxassetid://" .. tostring(def.Id)
	if def.Fallback then
		Sounds.Fallbacks[name] = def.Fallback
	end
	if def.Pitch then
		Sounds.Pitch[name] = def.Pitch
	end
	Sounds.Volumes[name] = def.Volume or 0.5
	Sounds.Groups[name] = def.Group or "SFX"
	if def.Cutoff then
		Sounds.Cutoff[name] = def.Cutoff
	end
	if def.RollOff then
		Sounds.RollOff[name] = def.RollOff
	end
end

local templates: { [string]: Sound } = {}
local bankFolder: Folder? = nil
local activeOneShots = 0
local MAX_ONE_SHOTS = 24
-- Отдельный лимит для частых звуков, чтобы шаги не "забивали" остальные.
local MAX_PER_NAME: { [string]: number } = { StepWood = 4, StepConcrete = 4, StepGrass = 4, StepHeavy = 4, Creak = 3 }
local activeByName: { [string]: number } = {}

-- Группа по имени; если в SoundService её нет (например, в тестовом месте) — создаём.
function Sounds.group(name: GroupName): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = SoundService
	return g
end

local function getBankFolder(): Folder
	local f = bankFolder
	if f and f.Parent then
		return f
	end
	local existing = SoundService:FindFirstChild("Bank")
	if existing and existing:IsA("Folder") then
		bankFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Bank"
	folder.Parent = SoundService
	bankFolder = folder
	return folder
end

-- Папка в Workspace для клиентских частей (держатели звуков, фонарик, призрак-превью).
function Sounds.fxFolder(): Folder
	local existing = workspace:FindFirstChild("ClientFX")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientFX"
	folder.Parent = workspace
	return folder
end

local holder: Part? = nil
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
	p.Parent = Sounds.fxFolder()
	holder = p
	return p
end

local function template(name: string): Sound?
	local existing = templates[name]
	if existing then
		return existing
	end
	local assetId = Sounds.Ids[name]
	if not assetId or assetId == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = assetId
	s.Volume = Sounds.Volumes[name] or 0.5
	s.PlaybackSpeed = Sounds.Pitch[name] or 1
	s.SoundGroup = Sounds.group(Sounds.Groups[name] or "SFX")
	s.Parent = getBankFolder()
	templates[name] = s
	return s
end

local function applyRollOff(s: Sound, name: string, defaultMin: number, defaultMax: number)
	local r = Sounds.RollOff[name]
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = if r then r[1] else defaultMin
	s.RollOffMaxDistance = if r then r[2] else defaultMax
end

-- Разовый звук: клон играет до конца (или до Cutoff), потом удаляется.
local function playClone(base: Sound, name: string, parent: Instance, volumeScale: number?, randomPitch: boolean): Sound
	local s = base:Clone()
	s.Looped = false
	s.Volume = base.Volume * (volumeScale or 1)
	if randomPitch then
		s.PlaybackSpeed = base.PlaybackSpeed * (0.94 + math.random() * 0.12)
	end
	s.Parent = parent
	local cutoff = Sounds.Cutoff[name]
	if cutoff then
		task.delay(cutoff, function()
			if s.Parent then
				s:Stop()
			end
		end)
	end
	s:Play()
	return s
end

-- Получить шаблон (например, для звука клика кнопок через SoundService:PlayLocalSound).
function Sounds.get(name: string): Sound?
	return template(name)
end

-- Звук интерфейса / нелокализованный звук (стингер, щелчок фонарика).
function Sounds.playUI(name: string, volumeScale: number?)
	local base = template(name)
	if not base then
		return
	end
	local s = playClone(base, name, getBankFolder(), volumeScale, false)
	local function cleanup()
		if s.Parent then
			s:Destroy()
		end
	end
	s.Ended:Once(cleanup)
	s.Stopped:Once(cleanup)
	task.delay(30, cleanup)
end

-- Разовый 3D-звук в точке мира.
function Sounds.playAt(name: string, position: Vector3, volumeScale: number?)
	local base = template(name)
	if not base or activeOneShots >= MAX_ONE_SHOTS then
		return
	end
	local limit = MAX_PER_NAME[name]
	local current = activeByName[name] or 0
	if limit and current >= limit then
		return
	end
	activeOneShots += 1
	activeByName[name] = current + 1
	local att = Instance.new("Attachment")
	att.Parent = getHolder()
	att.WorldPosition = position
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		activeOneShots -= 1
		activeByName[name] = math.max(0, (activeByName[name] or 1) - 1)
		att:Destroy()
	end
	local s = base:Clone()
	s.Looped = false
	s.Volume = base.Volume * (volumeScale or 1)
	s.PlaybackSpeed = base.PlaybackSpeed * (0.94 + math.random() * 0.12)
	applyRollOff(s, name, 8, 120)
	s.Parent = att
	local cutoff = Sounds.Cutoff[name]
	if cutoff then
		task.delay(cutoff, function()
			if s.Parent then
				s:Stop()
			end
		end)
	end
	s.Ended:Once(release)
	s.Stopped:Once(release)
	s:Play()
	-- слот освобождается, когда звук доиграл (или максимум через 12 с)
	task.delay(12, release)
end

-- Зацикленный 3D-звук на объекте (голос пациента, капающая труба). Вернёт Sound, чтобы потом остановить.
function Sounds.loopAt(name: string, parent: Instance, volumeScale: number?): Sound?
	local base = template(name)
	if not base then
		return nil
	end
	local s = base:Clone()
	s.Looped = true
	s.Volume = base.Volume * (volumeScale or 1)
	applyRollOff(s, name, 10, 120)
	s.Parent = parent
	s:Play()
	return s
end

-- Зацикленный непозиционный звук в группе (музыка, фоновая петля, сердце). Громкость тянут вызывающие.
function Sounds.loop(name: string, group: GroupName?, volumeScale: number?): Sound?
	local base = template(name)
	if not base then
		return nil
	end
	local s = base:Clone()
	s.Looped = true
	s.Volume = base.Volume * (volumeScale or 1)
	if group then
		s.SoundGroup = Sounds.group(group)
	end
	s.Parent = getBankFolder()
	s:Play()
	return s
end

-- Базовая громкость звука (чтобы тянуть к "полной" громкости).
function Sounds.baseVolume(name: string): number
	return Sounds.Volumes[name] or 0.5
end

-- Остановить и удалить звук, созданный loop/loopAt.
function Sounds.stop(sound: Sound?)
	if sound and sound.Parent then
		sound:Stop()
		sound:Destroy()
	end
end

-- Плавно изменить громкость; вернёт Tween (или nil, если звука нет).
function Sounds.fadeTo(sound: Sound?, volume: number, seconds: number): Tween?
	if not sound or not sound.Parent then
		return nil
	end
	local tween = TweenService:Create(sound, TweenInfo.new(math.max(0.01, seconds), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = volume })
	tween:Play()
	return tween
end

-- Плавно затушить и удалить.
function Sounds.fadeOut(sound: Sound?, seconds: number)
	if not sound or not sound.Parent then
		return
	end
	local tween = Sounds.fadeTo(sound, 0, seconds)
	if tween then
		tween.Completed:Once(function()
			Sounds.stop(sound)
		end)
	else
		Sounds.stop(sound)
	end
end

-- Предзагрузка всех звуков; если какой-то не загрузился — меняем на встроенный.
function Sounds.preload()
	local list: { Instance } = {}
	for name in Sounds.Ids do
		local s = template(name)
		if s then
			table.insert(list, s)
		end
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Success then
					return
				end
				for name, s in templates do
					local fallback = Sounds.Fallbacks[name]
					if s.SoundId == contentId and fallback and fallback ~= contentId then
						s.SoundId = fallback
					end
				end
			end)
		end)
		if not ok then
			warn("[Sounds] preload failed: " .. tostring(err))
		end
	end)
end

return Sounds
