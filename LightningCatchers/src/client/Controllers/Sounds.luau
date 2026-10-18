--!strict
-- Звуки и музыка. Все ID и громкости — в shared/SoundIds.
-- Если звук не загрузится, игра работает дальше (подставляется встроенный звук клиента или тишина).

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundIds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundIds"))

local Sounds = {}

local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "SFX"
sfxGroup.Volume = 1
sfxGroup.Parent = SoundService

local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 1
musicGroup.Parent = SoundService

local ambientGroup = Instance.new("SoundGroup")
ambientGroup.Name = "Ambient"
ambientGroup.Volume = 1
ambientGroup.Parent = SoundService

local templates: { [string]: Sound } = {}
local failed: { [string]: boolean } = {}
local lastPlayed: { [string]: number } = {}
local activeOneShots = 0
local MAX_ONESHOTS = 24

local function makeSound(name: string, def: SoundIds.SoundDef, group: SoundGroup): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	s.PlaybackSpeed = def.Pitch or 1
	s.Looped = def.Looped == true
	s.SoundGroup = group
	s.Parent = SoundService
	return s
end

for name, def in SoundIds.Sfx do
	templates[name] = makeSound(name, def, sfxGroup)
end

-- Предзагрузка: проблемные ID заменяются запасными
task.spawn(function()
	local list: { Instance } = {}
	for _, s in templates do
		table.insert(list, s)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				for name, s in templates do
					if s.SoundId == contentId then
						local def = SoundIds.Sfx[name]
						if def and def.Fallback then
							s.SoundId = def.Fallback
						else
							failed[name] = true
						end
					end
				end
			end
		end)
	end)
end)

-- Проиграть звук. pitch умножается на высоту из таблицы; vary — случайный разброс (0.04 = ±4%).
function Sounds.play(name: string, pitch: number?, volumeScale: number?, vary: number?)
	local t = templates[name]
	if not t or failed[name] then
		return
	end
	local def = SoundIds.Sfx[name]
	-- не играть один и тот же звук чаще, чем раз в minGap секунд
	local gap = def.MinGap or 0.03
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < gap then
		return
	end
	lastPlayed[name] = now
	if activeOneShots >= MAX_ONESHOTS then
		return
	end
	local s = t:Clone()
	local v = vary or def.Vary or 0
	local rnd = if v > 0 then 1 + (math.random() * 2 - 1) * v else 1
	s.PlaybackSpeed = (def.Pitch or 1) * (pitch or 1) * rnd
	s.Volume = (def.Volume or 0.5) * (volumeScale or 1)
	if def.Start and def.Start > 0 and s.SoundId == def.Id then
		s.TimePosition = def.Start
	end
	s.Parent = SoundService
	activeOneShots += 1
	s.Ended:Once(function()
		activeOneShots -= 1
		s:Destroy()
	end)
	s:Play()
	-- страховка, если Ended не придёт (звук не загрузился)
	task.delay(8, function()
		if s.Parent then
			activeOneShots -= 1
			s:Destroy()
		end
	end)
end

-- Лесенка высоты для комбо: каждая ступень на полтона выше, потолок ступеней — cap.
function Sounds.ladderPitch(step: number, cap: number?): number
	local n = math.clamp(step, 0, cap or 12)
	return 2 ^ (n / 12)
end

----------------------------------------------------------------------
-- Музыка и фоновые звуки (плавная смена)
----------------------------------------------------------------------
local currentMusic: Sound? = nil
local currentMusicName: string? = nil
local ambientLoops: { [string]: Sound } = {}

local function fade(s: Sound, to: number, time: number): Tween
	local tw = TweenService:Create(s, TweenInfo.new(time, Enum.EasingStyle.Sine), { Volume = to })
	tw:Play()
	return tw
end

function Sounds.playMusic(name: string?)
	if name == currentMusicName then
		return
	end
	local old = currentMusic
	if old then
		local tw = fade(old, 0, 1.5)
		tw.Completed:Once(function()
			old:Destroy()
		end)
	end
	currentMusic = nil
	currentMusicName = name
	if not name then
		return
	end
	local def = SoundIds.Music[name]
	if not def then
		return
	end
	local s = makeSound("Music_" .. name, def, musicGroup)
	s.Looped = true
	local target = def.Volume or 0.3
	s.Volume = 0
	s:Play()
	fade(s, target, 2)
	currentMusic = s
end

function Sounds.setAmbient(name: string, on: boolean)
	local def = SoundIds.Ambient[name]
	if not def then
		return
	end
	local s = ambientLoops[name]
	if on then
		if not s then
			local snd = makeSound("Amb_" .. name, def, ambientGroup)
			snd.Looped = true
			snd.Volume = 0
			snd:Play()
			ambientLoops[name] = snd
			s = snd
		end
		fade(s :: Sound, def.Volume or 0.3, 1.5)
	elseif s then
		fade(s, 0, 1.5)
	end
end

function Sounds.setMusicEnabled(on: boolean)
	musicGroup.Volume = if on then 1 else 0
end

function Sounds.setSfxEnabled(on: boolean)
	sfxGroup.Volume = if on then 1 else 0
	ambientGroup.Volume = if on then 1 else 0
end

return Sounds
