--!strict
-- STRETCH-POP · Конфиг звука: ВСЕ ассеты и настройки частот — только здесь.
--
-- Свой звук в один клик: замени Id нужного слота на "rbxassetid://<твой id>". Код трогать не нужно —
-- StretchAudioController сам строит голоса, группы и эффекты по этой таблице.
--
-- По умолчанию стоят встроенные звуки клиента Roblox (rbxasset://sounds/...): они лежат в установке
-- у каждого игрока, не из библиотеки ассетов, и звучат сразу. Характер (питч, фильтр, ноты пентатоники,
-- реверберация) задаёт процедурный слой контроллера, поэтому кастомные ассеты подхватываются без правок.

export type SoundGroupName = "Sfx" | "Resonance" | "Ui"

export type SoundDef = {
	Id: string,
	Volume: number, -- базовая громкость слоя (шкала Roblox 0..10)
	Pitch: number, -- базовый PlaybackSpeed (1 = как записано)
	Voices: number, -- полифония: сколько копий может звучать одновременно
	Looped: boolean,
	Group: SoundGroupName,
}

local BUILTIN = {
	Wind = "rbxasset://sounds/action_falling.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
}

local function sound(id: string, volume: number, pitch: number, voices: number, looped: boolean, group: SoundGroupName): SoundDef
	return { Id = id, Volume = volume, Pitch = pitch, Voices = voices, Looped = looped, Group = group }
end

local SoundConfig = {
	MasterVolume = 0.9,
	GroupVolumes = {
		Sfx = 1,
		Resonance = 0.95,
		Ui = 0.8,
	} :: { [SoundGroupName]: number },

	Sounds = {
		-- Резина и руки
		StretchLoop = sound(BUILTIN.Wind, 0.6, 1, 1, true, "Sfx"), -- гул натяжения (луп); питч ведёт Tension.Pitch*
		Creak = sound(BUILTIN.Land, 0.22, 2.4, 6, false, "Sfx"), -- зерно «скрипа» (гранулярно, чаще с натяжением)
		Snap = sound(BUILTIN.Jump, 1, 1.35, 3, false, "Sfx"), -- хлёсткий отстрел рогатки
		HandFire = sound(BUILTIN.Jump, 0.5, 2.1, 3, false, "Sfx"),
		HandAttach = sound(BUILTIN.Land, 0.45, 1.9, 3, false, "Sfx"),
		HandRelease = sound(BUILTIN.Jump, 0.35, 2.6, 3, false, "Sfx"),
		-- Полёт
		WindLoop = sound(BUILTIN.Wind, 0.8, 1, 1, true, "Sfx"), -- свист ветра (луп)
		BallToggle = sound(BUILTIN.Land, 0.5, 1.6, 2, false, "Sfx"),
		-- Удары (питч ведёт пентатоника по комбо)
		Bounce = sound(BUILTIN.Land, 0.85, 1, 6, false, "Sfx"),
		Smash = sound(BUILTIN.Land, 1, 0.75, 4, false, "Sfx"),
		SmashLayer = sound(BUILTIN.Splash, 0.55, 0.7, 4, false, "Sfx"),
		Splat = sound(BUILTIN.GetUp, 0.7, 0.8, 2, false, "Sfx"),
		Coin = sound(BUILTIN.Land, 0.45, 2.3, 8, false, "Ui"),
		-- Резонанс (через ReverbSoundEffect + EchoSoundEffect группы Resonance)
		Gong = sound(BUILTIN.Land, 1.2, 0.42, 6, false, "Resonance"),
		GongLayer = sound(BUILTIN.Splash, 0.5, 0.35, 2, false, "Resonance"),
		WaveSweep = sound(BUILTIN.Wind, 1, 0.5, 2, false, "Resonance"),
		-- Интерфейс
		UiClick = sound(BUILTIN.Land, 0.35, 2.8, 4, false, "Ui"),
		UiOpen = sound(BUILTIN.Jump, 0.4, 1.8, 2, false, "Ui"),
		UiError = sound(BUILTIN.GetUp, 0.55, 0.65, 2, false, "Ui"),
	} :: { [string]: SoundDef },

	-- Натяжение рогатки: питч, громкость и «фильтр» (EQ) идут за Tension 0..1
	Tension = {
		PitchMin = 0.45, -- итоговый PlaybackSpeed = Pitch слота · lerp(PitchMin, PitchMax, tension)
		PitchMax = 1.25,
		VolumeMax = 0.65,
		VolumeCurve = 0.8, -- громкость ∝ tension^0.8
		HighGainMin = -36, -- dB: при слабом натяжении звук глухой…
		HighGainMax = 0, -- …при сильном — звонкий (открываем верха)
		MidGainMax = 4,
		CreakThreshold = 0.12,
		CreakRateMin = 5, -- зёрен скрипа в секунду при пороге
		CreakRateMax = 22, -- …и на 100% натяжения
		CreakPitchJitter = 0.12,
		Smoothing = 7, -- Гц пружины сглаживания параметров
	},

	-- Свист ветра в полёте: громкость/питч/фильтр от скорости
	Wind = {
		SpeedMin = 35,
		SpeedForMax = 420,
		VolumeMax = 0.75,
		PitchMin = 0.55,
		PitchMax = 1.85,
		HighGainMin = -30,
		HighGainMax = 3,
		FlutterDepth = 0.035, -- лёгкое «трепетание» питча
		FlutterRate = 9,
		SupersonicBoost = 0.15, -- прибавка громкости на сверхзвуке
		Smoothing = 4,
	},

	Impact = {
		SpeedForFullVolume = 260,
		MinVolumeScale = 0.35,
		PitchJitter = 0.02,
	},

	-- Ноты: мажорная пентатоника (полутоны от тоники). Каждый следующий удар в комбо — следующая ступень.
	Pentatonic = { 0, 2, 4, 7, 9 },
	PentatonicOctaves = 2, -- потолок: выше мелодия ходит по верхней октаве
	GongChord = { 0, 4, 7, 12 }, -- мажорное трезвучие + октава
	ChordStrum = 0.05,
	Arpeggio = { 0, 4, 7, 12 },
	ArpeggioStep = 0.07,

	Resonance = {
		DecayTime = 4.5,
		Density = 1,
		Diffusion = 1,
		DryLevel = -2,
		WetLevel = 0,
		EchoDelay = 0.22,
		EchoFeedback = 0.35,
		EchoDryLevel = 0,
		EchoWetLevel = -9,
	},
}

-- Полутоны step-й ступени (step 0 = тоника). Выше потолка октав — ходим по верхней октаве.
function SoundConfig.PentatonicSemitones(step: number): number
	local scale = SoundConfig.Pentatonic
	local index = math.max(math.floor(step), 0)
	local octave = math.min(index // #scale, SoundConfig.PentatonicOctaves)
	local degree = index % #scale
	return scale[degree + 1] + 12 * octave
end

-- Полутоны → множитель частоты (равномерная темперация)
function SoundConfig.SemitoneRatio(semitones: number): number
	return 2 ^ (semitones / 12)
end

return SoundConfig
