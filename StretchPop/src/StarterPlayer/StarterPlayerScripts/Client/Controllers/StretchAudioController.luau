--!strict
-- STRETCH-POP · StretchAudioController — процедурный и гармонический звук.
-- Все ассеты и частоты — в Shared/Config/SoundConfig; здесь только «как звучит физика»:
--   • Натяжение рогатки: луп резины, PlaybackSpeed/громкость/EQ-фильтр идут за Tension (сглажено пружиной),
--     плюс гранулярный «скрип» — короткие зёрна, частота которых растёт с натяжением.
--   • Launched: хлёсткий отстрел; полёт: свист ветра, модулированный скоростью (+ трепет и сверхзвук).
--   • Bounced/Smashed: питч удара по ступеням мажорной пентатоники от текущего Combo — серия ударов играет мелодию.
--   • Гонг и волна перерождения: глубокий резонанс через ReverbSoundEffect + EchoSoundEffect группы Resonance,
--     мажорный аккорд-«страм» на успех и протяжный свип питча на всю длину волны.
--   • Интерфейс: клики, открытие панели, покупка (арпеджио) и отказ.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local SoundConfig = require(Shared.Config.SoundConfig)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local Spring = require(Shared.Math.Spring)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ElasticSlingshotController = require(Client.Controllers.ElasticSlingshotController)
local ShoulderCamera = require(Client.Controllers.ShoulderCameraController)
local StretchHUDController = require(Client.Controllers.StretchHUDController)

type Voice = {
	Sound: Sound,
	BusyUntil: number,
}

type Bank = {
	Name: string,
	Def: SoundConfig.SoundDef,
	Voices: { Voice },
	Next: number,
}

type Loop = {
	Sound: Sound,
	Equalizer: EqualizerSoundEffect,
	Playing: boolean,
}

type Sweep = {
	Voice: Voice,
	StartsAt: number,
	Duration: number,
	FromPitch: number,
	ToPitch: number,
	Volume: number,
	Started: boolean,
}

type ScheduledNote = {
	At: number,
	Bank: string,
	Pitch: number,
	Volume: number,
}

type AudioFields = {
	Player: Player,
	Slingshot: ElasticSlingshotController.ElasticSlingshotController,
	Camera: ShoulderCamera.ShoulderCamera,
	Hud: StretchHUDController.StretchHUDController?,
	Folder: Folder,
	Groups: { [SoundConfig.SoundGroupName]: SoundGroup },
	Banks: { [string]: Bank },
	StretchLoop: Loop,
	WindLoop: Loop,
	TensionTarget: number,
	TensionSmoothed: Spring.NumberSpring,
	SpeedSmoothed: Spring.NumberSpring,
	CreakTimer: number,
	Sweeps: { Sweep },
	Schedule: { ScheduledNote },
	Random: Random,
	Connections: { any },
	Started: boolean,
}

local Audio = {}
Audio.__index = Audio

export type StretchAudioController = typeof(setmetatable({} :: AudioFields, Audio))

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function createSound(def: SoundConfig.SoundDef, name: string, group: SoundGroup, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.PlaybackSpeed = def.Pitch
	sound.Looped = def.Looped
	sound.SoundGroup = group
	sound.Parent = parent
	return sound
end

local function createGroup(name: SoundConfig.SoundGroupName, parent: Instance): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = "StretchPop_" .. name
	group.Volume = SoundConfig.MasterVolume * SoundConfig.GroupVolumes[name]
	if name == "Resonance" then
		local settings = SoundConfig.Resonance
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DecayTime = settings.DecayTime
		reverb.Density = settings.Density
		reverb.Diffusion = settings.Diffusion
		reverb.DryLevel = settings.DryLevel
		reverb.WetLevel = settings.WetLevel
		reverb.Priority = 1
		reverb.Parent = group
		local echo = Instance.new("EchoSoundEffect")
		echo.Delay = settings.EchoDelay
		echo.Feedback = settings.EchoFeedback
		echo.DryLevel = settings.EchoDryLevel
		echo.WetLevel = settings.EchoWetLevel
		echo.Priority = 2
		echo.Parent = group
	end
	group.Parent = parent
	return group
end

local function createLoop(def: SoundConfig.SoundDef, name: string, group: SoundGroup, parent: Instance): Loop
	local sound = createSound(def, name, group, parent)
	sound.Looped = true
	sound.Volume = 0
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.LowGain = 0
	equalizer.MidGain = 0
	equalizer.HighGain = 0
	equalizer.Parent = sound
	return { Sound = sound, Equalizer = equalizer, Playing = false }
end

function Audio.new(
	slingshot: ElasticSlingshotController.ElasticSlingshotController,
	camera: ShoulderCamera.ShoulderCamera,
	hud: StretchHUDController.StretchHUDController?
): StretchAudioController
	local folder = Instance.new("Folder")
	folder.Name = "StretchPopAudio"
	folder.Parent = SoundService

	local groups = {} :: { [SoundConfig.SoundGroupName]: SoundGroup }
	for _, groupName in { "Sfx", "Resonance", "Ui" } :: { SoundConfig.SoundGroupName } do
		groups[groupName] = createGroup(groupName, SoundService)
	end

	local banks: { [string]: Bank } = {}
	for name, def in SoundConfig.Sounds do
		if not def.Looped then
			local voices: { Voice } = {}
			for index = 1, math.max(def.Voices, 1) do
				table.insert(voices, { Sound = createSound(def, name .. index, groups[def.Group], folder), BusyUntil = 0 })
			end
			banks[name] = { Name = name, Def = def, Voices = voices, Next = 1 }
		end
	end

	local stretchDef = SoundConfig.Sounds.StretchLoop
	local windDef = SoundConfig.Sounds.WindLoop
	local fields: AudioFields = {
		Player = Players.LocalPlayer,
		Slingshot = slingshot,
		Camera = camera,
		Hud = hud,
		Folder = folder,
		Groups = groups,
		Banks = banks,
		StretchLoop = createLoop(stretchDef, "StretchLoop", groups[stretchDef.Group], folder),
		WindLoop = createLoop(windDef, "WindLoop", groups[windDef.Group], folder),
		TensionTarget = 0,
		TensionSmoothed = Spring.Number.new(0, SoundConfig.Tension.Smoothing, 1),
		SpeedSmoothed = Spring.Number.new(0, SoundConfig.Wind.Smoothing, 1),
		CreakTimer = 0,
		Sweeps = {},
		Schedule = {},
		Random = Random.new(),
		Connections = {},
		Started = false,
	}
	return setmetatable(fields, Audio)
end

-- ── Воспроизведение ─────────────────────────────────────────────────────────

-- Свободный голос банка (или самый старый — «кража голоса», как в синтезаторах)
function Audio.TakeVoice(self: StretchAudioController, bank: Bank): Voice
	local now = os.clock()
	local count = #bank.Voices
	for offset = 0, count - 1 do
		local index = ((bank.Next - 1 + offset) % count) + 1
		local voice = bank.Voices[index]
		if voice.BusyUntil <= now then
			bank.Next = (index % count) + 1
			return voice
		end
	end
	local voice = bank.Voices[bank.Next]
	bank.Next = (bank.Next % count) + 1
	return voice
end

-- pitch и volume — множители к значениям слота из SoundConfig
function Audio.Play(self: StretchAudioController, bankName: string, pitch: number, volume: number): Voice?
	local bank = self.Banks[bankName]
	if bank == nil or volume <= 0 then
		return nil
	end
	local voice = self:TakeVoice(bank)
	local jitter = 1 + self.Random:NextNumber(-SoundConfig.Impact.PitchJitter, SoundConfig.Impact.PitchJitter)
	local sound = voice.Sound
	sound:Stop()
	sound.Looped = false
	sound.PlaybackSpeed = bank.Def.Pitch * pitch * jitter
	sound.Volume = bank.Def.Volume * volume
	sound.TimePosition = 0
	sound:Play()
	voice.BusyUntil = os.clock() + 0.35 / math.max(pitch, 0.1)
	return voice
end

-- Нота мажорной пентатоники: step 0 = тоника, дальше вверх по ладу
function Audio.PlayNote(self: StretchAudioController, bankName: string, step: number, volume: number)
	local ratio = SoundConfig.SemitoneRatio(SoundConfig.PentatonicSemitones(step))
	self:Play(bankName, ratio, volume)
end

function Audio.ScheduleNotes(self: StretchAudioController, bankName: string, semitones: { number }, spacing: number, basePitch: number, volume: number)
	local now = os.clock()
	for index, semitone in semitones do
		table.insert(self.Schedule, {
			At = now + (index - 1) * spacing,
			Bank = bankName,
			Pitch = basePitch * SoundConfig.SemitoneRatio(semitone),
			Volume = volume,
		})
	end
end

function Audio.StartSweep(self: StretchAudioController, bankName: string, startsAt: number, duration: number, fromPitch: number, toPitch: number, volume: number)
	local bank = self.Banks[bankName]
	if bank == nil then
		return
	end
	local voice = self:TakeVoice(bank)
	voice.BusyUntil = startsAt + duration + 0.5
	table.insert(self.Sweeps, {
		Voice = voice,
		StartsAt = startsAt,
		Duration = math.max(duration, 0.1),
		FromPitch = fromPitch,
		ToPitch = toPitch,
		Volume = volume,
		Started = false,
	})
end

local function impactVolume(speed: number): number
	local settings = SoundConfig.Impact
	return math.clamp(speed / settings.SpeedForFullVolume, settings.MinVolumeScale, 1.25)
end

-- ── Реакции на игру ─────────────────────────────────────────────────────────

function Audio.OnBounced(self: StretchAudioController, combo: number, speed: number)
	self:PlayNote("Bounce", combo - 1, impactVolume(speed))
end

function Audio.OnSmashed(self: StretchAudioController, kind: string, speed: number)
	local step = math.max(self.Slingshot:GetCombo() - 1, 0)
	local volume = impactVolume(speed)
	self:PlayNote("Smash", step, volume)
	local ratio = SoundConfig.SemitoneRatio(SoundConfig.PentatonicSemitones(step))
	self:Play("SmashLayer", ratio, volume * 0.8)
	if kind == "Chest" then
		self:ScheduleNotes("Coin", SoundConfig.Arpeggio, SoundConfig.ArpeggioStep, 1, 0.9)
	end
end

function Audio.OnLaunched(self: StretchAudioController, speed: number)
	local strength = math.clamp(speed / 250, 0.45, 1.3)
	self:Play("Snap", 0.9 + 0.25 * strength, strength)
	self.TensionTarget = 0
	self.TensionSmoothed:Snap(0) -- резина отпущена: гул обрывается сразу, щелчок «съедает» хвост
end

function Audio.OnGongStruck(self: StretchAudioController)
	self:Play("Gong", 1, 1)
	self:Play("GongLayer", 1, 0.8)
end

function Audio.OnGongResult(self: StretchAudioController, accepted: boolean)
	if accepted then
		-- мажорный аккорд-«страм» с резонансом поверх удара
		self:ScheduleNotes("Gong", SoundConfig.GongChord, SoundConfig.ChordStrum, 1, 0.85)
	else
		self:Play("Gong", SoundConfig.SemitoneRatio(-5), 0.6)
		self:Play("UiError", 1, 0.8)
	end
end

function Audio.OnRebirthWave(self: StretchAudioController, info: Types.RebirthWaveInfo)
	if info.OwnerUserId ~= self.Player.UserId then
		return
	end
	local delay = math.max(info.StartServerTime - workspace:GetServerTimeNow(), 0)
	local duration = (info.EndZ - info.OriginZ) / info.Speed
	local startsAt = os.clock() + delay
	self:StartSweep("WaveSweep", startsAt, duration, 0.5, 1.8, 1)
	-- в конце волны — восходящее арпеджио пентатоники через октаву
	local finale = { 0, 2, 4, 7, 9, 12, 14, 16 }
	for index, semitone in finale do
		table.insert(self.Schedule, {
			At = startsAt + duration + (index - 1) * SoundConfig.ArpeggioStep,
			Bank = "Coin",
			Pitch = SoundConfig.SemitoneRatio(semitone),
			Volume = 0.9,
		})
	end
end

-- ── Кадр: лупы, гранулы, свипы, расписание ─────────────────────────────────

function Audio.UpdateLoop(self: StretchAudioController, loop: Loop, volume: number, pitch: number, highGain: number, midGain: number)
	local sound = loop.Sound
	if volume > 0.004 then
		if not loop.Playing then
			loop.Playing = true
			sound:Play()
		end
		sound.Volume = volume
		sound.PlaybackSpeed = math.max(pitch, 0.05)
		loop.Equalizer.HighGain = highGain
		loop.Equalizer.MidGain = midGain
	elseif loop.Playing then
		loop.Playing = false
		sound.Volume = 0
		sound:Stop()
	end
end

function Audio.OnRenderStep(self: StretchAudioController, dt: number)
	local now = os.clock()
	local step = math.min(dt, 0.1)

	-- Натяжение: громкость ∝ tension^curve, питч и «открытие» верхов растут вместе с ним
	local tensionConfig = SoundConfig.Tension
	local stretchDef = SoundConfig.Sounds.StretchLoop
	local charging = self.Slingshot:GetState() ~= "Walk"
	self.TensionSmoothed.Target = if charging then self.TensionTarget else 0
	local tension = math.clamp(self.TensionSmoothed:Update(step), 0, 1)
	self:UpdateLoop(
		self.StretchLoop,
		stretchDef.Volume * tensionConfig.VolumeMax * tension ^ tensionConfig.VolumeCurve,
		stretchDef.Pitch * lerp(tensionConfig.PitchMin, tensionConfig.PitchMax, tension),
		lerp(tensionConfig.HighGainMin, tensionConfig.HighGainMax, tension),
		tensionConfig.MidGainMax * tension
	)
	-- Гранулярный скрип: зёрна всё чаще и выше по мере натяжения
	if tension > tensionConfig.CreakThreshold then
		local amount = (tension - tensionConfig.CreakThreshold) / (1 - tensionConfig.CreakThreshold)
		local interval = 1 / lerp(tensionConfig.CreakRateMin, tensionConfig.CreakRateMax, amount)
		self.CreakTimer = math.min(self.CreakTimer + step, interval * 2)
		if self.CreakTimer >= interval then
			self.CreakTimer -= interval
			local jitter = self.Random:NextNumber(-tensionConfig.CreakPitchJitter, tensionConfig.CreakPitchJitter)
			self:Play("Creak", 1 + 0.35 * amount + jitter, 0.4 + 0.6 * amount)
		end
	else
		self.CreakTimer = 0
	end

	-- Ветер: только в полёте, от сглаженной скорости; на сверхзвуке — прибавка и трепет
	local windConfig = SoundConfig.Wind
	local windDef = SoundConfig.Sounds.WindLoop
	local flying = self.Slingshot:GetState() == "Air"
	self.SpeedSmoothed.Target = if flying then self.Slingshot:GetSpeed() else 0
	local speed = math.max(self.SpeedSmoothed:Update(step), 0)
	local alpha = math.clamp((speed - windConfig.SpeedMin) / (windConfig.SpeedForMax - windConfig.SpeedMin), 0, 1)
	local boost = if speed >= PhysicsConfig.SupersonicSpeed then windConfig.SupersonicBoost * alpha else 0
	local flutter = 1 + windConfig.FlutterDepth * math.sin(now * windConfig.FlutterRate * 2 * math.pi) * alpha
	self:UpdateLoop(
		self.WindLoop,
		windDef.Volume * (windConfig.VolumeMax * alpha ^ 1.3 + boost),
		windDef.Pitch * lerp(windConfig.PitchMin, windConfig.PitchMax, alpha) * flutter,
		lerp(windConfig.HighGainMin, windConfig.HighGainMax, alpha),
		0
	)

	-- Свипы (волна перерождения): питч скользит по ease-in-out, громкость — мягкая вспышка
	local index = 1
	while index <= #self.Sweeps do
		local sweep = self.Sweeps[index]
		if now < sweep.StartsAt then
			index += 1
		else
			local sound = sweep.Voice.Sound
			if not sweep.Started then
				sweep.Started = true
				sound:Stop()
				sound.Looped = true
				sound.TimePosition = 0
				sound:Play()
			end
			local t = (now - sweep.StartsAt) / sweep.Duration
			if t >= 1 then
				sound:Stop()
				sound.Looped = false
				table.remove(self.Sweeps, index)
			else
				local eased = t * t * (3 - 2 * t)
				local def = SoundConfig.Sounds.WaveSweep
				-- From/To — абсолютный PlaybackSpeed свипа (питч слота задаёт только одиночные проигрывания)
				sound.PlaybackSpeed = lerp(sweep.FromPitch, sweep.ToPitch, eased)
				sound.Volume = def.Volume * sweep.Volume * math.sin(math.pi * t) ^ 0.6
				index += 1
			end
		end
	end

	-- Расписание нот (аккорды, арпеджио)
	local noteIndex = 1
	while noteIndex <= #self.Schedule do
		local note = self.Schedule[noteIndex]
		if now >= note.At then
			self:Play(note.Bank, note.Pitch, note.Volume)
			table.remove(self.Schedule, noteIndex)
		else
			noteIndex += 1
		end
	end
end

-- ── Запуск / остановка ──────────────────────────────────────────────────────

function Audio.Start(self: StretchAudioController)
	if self.Started then
		return
	end
	self.Started = true
	local signals = self.Slingshot.Signals
	local connections = self.Connections

	table.insert(
		connections,
		signals.TensionChanged:Connect(function(tension: number)
			self.TensionTarget = tension
		end)
	)
	table.insert(
		connections,
		signals.Launched:Connect(function(speed: number, _velocity: Vector3)
			self:OnLaunched(speed)
		end)
	)
	table.insert(
		connections,
		signals.HandFired:Connect(function(_side: Types.HandSide)
			self:Play("HandFire", 1, 1)
		end)
	)
	table.insert(
		connections,
		signals.HandAttached:Connect(function(_side: Types.HandSide)
			self:Play("HandAttach", 1, 1)
		end)
	)
	table.insert(
		connections,
		signals.HandReleased:Connect(function(_side: Types.HandSide)
			self:Play("HandRelease", 1, 1)
		end)
	)
	table.insert(
		connections,
		signals.Bounced:Connect(function(combo: number, speed: number, _point: Vector3)
			self:OnBounced(combo, speed)
		end)
	)
	table.insert(
		connections,
		signals.Smashed:Connect(function(kind: string, speed: number, _point: Vector3)
			self:OnSmashed(kind, speed)
		end)
	)
	table.insert(
		connections,
		signals.Splat:Connect(function(impact: number)
			self:Play("Splat", 1 - math.min(impact / 600, 0.3), math.clamp(impact / 300, 0.4, 1))
		end)
	)
	table.insert(
		connections,
		signals.GongStruck:Connect(function(_speed: number, _combo: number)
			self:OnGongStruck()
		end)
	)
	table.insert(
		connections,
		signals.LootGained:Connect(function(_loot: number)
			self:ScheduleNotes("Coin", { 7, 12, 16 }, 0.06, 1, 0.7)
		end)
	)
	table.insert(
		connections,
		signals.BallChanged:Connect(function(active: boolean)
			self:Play("BallToggle", if active then 1.25 else 0.85, 0.9)
		end)
	)

	table.insert(
		connections,
		Net.GongResult.OnClientEvent:Connect(function(accepted: boolean)
			self:OnGongResult(accepted)
		end)
	)
	table.insert(
		connections,
		Net.RebirthWave.OnClientEvent:Connect(function(info: Types.RebirthWaveInfo)
			self:OnRebirthWave(info)
		end)
	)

	local hud = self.Hud
	if hud then
		table.insert(
			connections,
			hud.Signals.UiClick:Connect(function()
				self:Play("UiClick", 1, 1)
			end)
		)
		table.insert(
			connections,
			hud.Signals.PanelToggled:Connect(function(open: boolean)
				self:Play("UiOpen", if open then 1.2 else 0.85, 1)
			end)
		)
		table.insert(
			connections,
			hud.Signals.Purchase:Connect(function(success: boolean, _reason: string)
				if success then
					self:ScheduleNotes("Coin", SoundConfig.Arpeggio, SoundConfig.ArpeggioStep, 1, 1)
				else
					self:Play("UiError", 1, 1)
				end
			end)
		)
	end

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt: number)
			self:OnRenderStep(dt)
		end)
	)
end

function Audio.Destroy(self: StretchAudioController)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	table.clear(self.Sweeps)
	table.clear(self.Schedule)
	self.Folder:Destroy()
	for _, group in self.Groups do
		group:Destroy()
	end
	self.Started = false
end

return Audio
