-- Sound helper: one-shots, 3D sounds and cross-faded music.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Config = require(script.Parent.Config)

local Audio = {}

local oneShots: { [string]: Sound } = {}
local musicSound: Sound? = nil
local musicKey: string? = nil

local function group(name: string): SoundGroup?
	local g = SoundService:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	return g :: SoundGroup
end

function Audio.make(key: string, parent: Instance?): Sound?
	local def = Config.Sounds[key]
	if not def or not def.Id or def.Id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	s.Looped = def.Looped == true
	s.SoundGroup = group(def.Group or "SFX")
	if def.RollOff then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = def.RollOffMin or 5
		s.RollOffMaxDistance = def.RollOff
	end
	s:SetAttribute("BaseVolume", s.Volume)
	s.Parent = parent or SoundService
	return s
end

-- 2D one-shot (UI clicks, whooshes...)
function Audio.play(key: string, pitch: number?): Sound?
	local s = oneShots[key]
	if not s then
		s = Audio.make(key, SoundService)
		if not s then
			return nil
		end
		oneShots[key] = s
	end
	local snd = s :: Sound
	snd.PlaybackSpeed = pitch or 1
	snd.TimePosition = 0
	snd:Play()
	return snd
end

function Audio.fadeTo(sound: Sound?, volume: number, t: number)
	if sound then
		TweenService:Create(sound, TweenInfo.new(t, Enum.EasingStyle.Sine), { Volume = volume }):Play()
	end
end

function Audio.fadeIn(sound: Sound?, t: number)
	if sound then
		local target = sound:GetAttribute("BaseVolume") or sound.Volume
		sound.Volume = 0
		if not sound.IsPlaying then
			sound:Play()
		end
		Audio.fadeTo(sound, target, t)
	end
end

function Audio.fadeOut(sound: Sound?, t: number, destroy: boolean?)
	if sound then
		Audio.fadeTo(sound, 0, t)
		task.delay(t + 0.05, function()
			if destroy then
				sound:Destroy()
			else
				sound:Stop()
			end
		end)
	end
end

function Audio.music(key: string?, fadeTime: number?)
	local t = fadeTime or 1.5
	if key == musicKey then
		return
	end
	if musicSound then
		Audio.fadeOut(musicSound, t, true)
	end
	musicSound = nil
	musicKey = key
	if key then
		local s = Audio.make(key, SoundService)
		if s then
			Audio.fadeIn(s, t)
			musicSound = s
		end
	end
end

function Audio.setGroupVolume(name: string, volume: number)
	local g = group(name)
	if g then
		g.Volume = volume
	end
end

return Audio
