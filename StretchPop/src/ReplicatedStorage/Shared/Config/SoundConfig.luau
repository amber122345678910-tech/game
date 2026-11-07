--!strict
-- STRETCH-POP · Звуковой конфиг на огибающих.
-- Все ассеты — ТОЛЬКО в таблице Samples ниже. Каждый игровой звук (Cue) — это слои,
-- у каждого слоя своя огибающая: питч едет StartPitch → EndPitch за PitchCurveTime по кривой
-- (Spring — пружинный перелёт, Exp — резкий спад, Linear), громкость гаснет к нулю за DecayTime.
-- StretchAudioController пересчитывает огибающие каждый кадр RenderStepped.
--
-- Свой звук в один клик: замени путь в Samples на "rbxassetid://<id>". Fallbacks подставляет
-- другой сэмпл из этого же набора, если какой-то ассет не загрузился.

export type SampleName = "Swoosh" | "RocketWhoosh" | "Snap" | "Bass" | "Ping" | "Button" | "MetalHit" | "Victory" | "PageTurn"
export type GroupName = "Sfx" | "Resonance" | "Ui"
export type Curve = "Spring" | "Exp" | "Linear"

export type Layer = {
	Sample: SampleName,
	Volume: number,
	StartPitch: number,
	EndPitch: number,
	PitchCurveTime: number,
	DecayTime: number,
	Delay: number,
	Curve: Curve,
	NoteScaled: boolean, -- умножать питч на ступень пентатоники (комбо)
	Group: GroupName,
}

export type Cue = {
	Layers: { Layer },
}

local Samples: { [SampleName]: string } = {
	Swoosh = "rbxasset://sounds/swoosh.wav",
	RocketWhoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	Snap = "rbxasset://sounds/snap.mp3",
	Bass = "rbxasset://sounds/bass.mp3",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Button = "rbxasset://sounds/button.wav",
	MetalHit = "rbxasset://sounds/metal_hit.mp3",
	Victory = "rbxasset://sounds/victory.wav",
	PageTurn = "rbxasset://sounds/pageturn.wav",
}

-- Сколько одновременных голосов держит каждый сэмпл (зерна натяжения и арпеджио — самые плотные)
local Polyphony: { [SampleName]: number } = {
	Swoosh = 8,
	RocketWhoosh = 4,
	Snap = 6,
	Bass = 6,
	Ping = 14,
	Button = 12,
	MetalHit = 4,
	Victory = 2,
	PageTurn = 3,
}

-- Если ассет не загрузился — по очереди пробуем замены (только из разрешённого набора)
local Fallbacks: { [SampleName]: { SampleName } } = {
	Swoosh = { "RocketWhoosh" },
	RocketWhoosh = { "Swoosh" },
	Snap = { "Button", "Swoosh" },
	Bass = { "RocketWhoosh", "Swoosh" },
	Ping = { "Button" },
	Button = { "Ping" },
	MetalHit = { "Ping", "Snap" },
	Victory = { "Ping" },
	PageTurn = { "Button", "Swoosh" },
}

local function layer(
	sample: SampleName,
	volume: number,
	startPitch: number,
	endPitch: number,
	pitchCurveTime: number,
	decayTime: number,
	curve: Curve,
	noteScaled: boolean,
	group: GroupName,
	delay: number?
): Layer
	return {
		Sample = sample,
		Volume = volume,
		StartPitch = startPitch,
		EndPitch = endPitch,
		PitchCurveTime = pitchCurveTime,
		DecayTime = decayTime,
		Delay = delay or 0,
		Curve = curve,
		NoteScaled = noteScaled,
		Group = group,
	}
end

local Cues: { [string]: Cue } = {
	-- «ПЬЮИНГ!»: старт с 0.75 ноты, пружинный взлёт до 1.25 ноты за 0.12 с
	Boing = {
		Layers = {
			layer("Ping", 0.9, 0.75, 1.25, 0.12, 0.42, "Spring", true, "Sfx"),
			layer("Button", 0.32, 0.75, 1.6, 0.1, 0.16, "Spring", true, "Sfx"),
		},
	},
	-- Пробитие: басовый кик 1.6 → 0.5 за 0.09 с + хрустящий верх
	Smash = {
		Layers = {
			layer("Bass", 1.35, 1.6, 0.5, 0.09, 0.45, "Exp", false, "Sfx"),
			layer("Snap", 0.9, 1.15, 0.95, 0.05, 0.24, "Exp", true, "Sfx"),
			layer("MetalHit", 0.7, 1.3, 1, 0.08, 0.5, "Exp", true, "Sfx", 0.01),
		},
	},
	-- Одна звонкая монетка (арпеджио собирает контроллер по ступеням пентатоники)
	Coin = {
		Layers = {
			layer("Ping", 0.75, 1, 1.06, 0.03, 0.08, "Linear", true, "Ui"),
		},
	},
	Launch = {
		Layers = {
			layer("Snap", 1.05, 1.3, 1, 0.06, 0.3, "Exp", false, "Sfx"),
			layer("Bass", 0.85, 1.15, 0.7, 0.12, 0.36, "Exp", false, "Sfx"),
			layer("Swoosh", 0.65, 0.9, 1.55, 0.25, 0.42, "Linear", false, "Sfx", 0.02),
		},
	},
	HandFire = {
		Layers = {
			layer("Swoosh", 0.45, 1.6, 2.2, 0.1, 0.18, "Linear", false, "Sfx"),
		},
	},
	HandAttach = {
		Layers = {
			layer("Button", 0.5, 1.7, 1.3, 0.05, 0.12, "Exp", false, "Sfx"),
			layer("Snap", 0.22, 2, 1.8, 0.04, 0.08, "Exp", false, "Sfx"),
		},
	},
	HandRelease = {
		Layers = {
			layer("Snap", 0.4, 1.8, 1.45, 0.05, 0.12, "Exp", false, "Sfx"),
		},
	},
	BallOn = {
		Layers = {
			layer("Ping", 0.5, 0.8, 1.6, 0.15, 0.3, "Spring", false, "Sfx"),
		},
	},
	BallOff = {
		Layers = {
			layer("Ping", 0.4, 1.4, 0.85, 0.12, 0.25, "Exp", false, "Sfx"),
		},
	},
	Splat = {
		Layers = {
			layer("Bass", 0.9, 1.05, 0.6, 0.12, 0.3, "Exp", false, "Sfx"),
			layer("Button", 0.38, 0.7, 0.5, 0.08, 0.12, "Exp", false, "Sfx"),
		},
	},
	Boost = {
		Layers = {
			layer("RocketWhoosh", 0.9, 0.9, 1.8, 0.3, 0.7, "Linear", false, "Sfx"),
			layer("Ping", 0.5, 1.5, 2, 0.1, 0.26, "Spring", true, "Sfx"),
		},
	},
	-- Гонг: глубокий бас + металлический резонанс через Reverb/Echo группы Resonance
	Gong = {
		Layers = {
			layer("Bass", 1.25, 0.8, 0.45, 0.4, 1.8, "Exp", false, "Resonance"),
			layer("MetalHit", 1, 0.7, 0.62, 0.5, 2.6, "Exp", false, "Resonance"),
		},
	},
	GongSuccess = {
		Layers = {
			layer("Victory", 1, 1, 1, 0.01, 4, "Linear", false, "Resonance"),
			layer("MetalHit", 0.7, 1, 0.9, 0.3, 2, "Exp", false, "Resonance", 0.05),
		},
	},
	GongFail = {
		Layers = {
			layer("MetalHit", 0.7, 0.6, 0.5, 0.3, 0.8, "Exp", false, "Resonance"),
			layer("Bass", 0.7, 0.7, 0.4, 0.2, 0.6, "Exp", false, "Sfx"),
		},
	},
	RebirthFinale = {
		Layers = {
			layer("Victory", 1, 1.12, 1.12, 0.01, 4, "Linear", false, "Resonance"),
			layer("Bass", 0.9, 0.9, 0.55, 0.3, 1.4, "Exp", false, "Resonance"),
		},
	},
	UiClick = {
		Layers = {
			layer("Button", 0.6, 1, 1.05, 0.03, 0.12, "Linear", false, "Ui"),
		},
	},
	UiHover = {
		Layers = {
			layer("Button", 0.16, 1.6, 1.7, 0.02, 0.06, "Linear", false, "Ui"),
		},
	},
	UiOpen = {
		Layers = {
			layer("PageTurn", 0.75, 1, 1, 0.01, 0.5, "Linear", false, "Ui"),
			layer("Swoosh", 0.3, 1.4, 1.9, 0.15, 0.2, "Linear", false, "Ui"),
		},
	},
	UiClose = {
		Layers = {
			layer("PageTurn", 0.55, 0.85, 0.85, 0.01, 0.4, "Linear", false, "Ui"),
		},
	},
	UiError = {
		Layers = {
			layer("Bass", 0.6, 0.9, 0.7, 0.1, 0.25, "Exp", false, "Ui"),
			layer("Button", 0.4, 0.62, 0.55, 0.06, 0.15, "Exp", false, "Ui"),
		},
	},
	HatchTick = {
		Layers = {
			layer("Button", 0.45, 0.9, 1.15, 0.06, 0.1, "Spring", true, "Ui"),
		},
	},
	HatchPop = {
		Layers = {
			layer("Snap", 1, 1.2, 0.9, 0.06, 0.3, "Exp", false, "Ui"),
			layer("MetalHit", 0.6, 1.4, 1.2, 0.08, 0.6, "Exp", false, "Ui"),
			layer("Bass", 0.9, 1.4, 0.6, 0.1, 0.5, "Exp", false, "Ui"),
		},
	},
	HatchReveal = {
		Layers = {
			layer("Victory", 0.9, 1, 1, 0.01, 3.2, "Linear", false, "Ui"),
		},
	},
}

local SoundConfig = {
	MasterVolume = 0.9,
	GroupVolumes = {
		Sfx = 1,
		Resonance = 0.95,
		Ui = 0.85,
	} :: { [GroupName]: number },
	Samples = Samples,
	Polyphony = Polyphony,
	Fallbacks = Fallbacks,
	Cues = Cues,

	-- Натяжение рогатки: «резиновый тон» из перекрывающихся коротких зёрен Button/Swoosh
	Stretch = {
		Samples = { "Button", "Swoosh" } :: { SampleName },
		PitchMin = 0.6, -- при Tension = 0
		PitchMax = 2.2, -- при Tension = 1
		VolumeMin = 0.05,
		VolumeMax = 0.3,
		GrainRateMin = 26, -- зёрен в секунду
		GrainRateMax = 48,
		GrainDecay = 0.09, -- каждое зерно живёт дольше интервала → зёрна перекрываются в тон
		PitchJitter = 0.03,
		Threshold = 0.03,
		Smoothing = 9,
	},

	-- Свист ветра в полёте: зацикленный RocketWhoosh, питч/громкость от скорости
	Wind = {
		Sample = "RocketWhoosh" :: SampleName,
		SpeedMin = 35,
		SpeedForMax = 420,
		VolumeMax = 0.7,
		PitchMin = 0.5,
		PitchMax = 1.6,
		FlutterDepth = 0.04,
		FlutterRate = 9,
		SupersonicBoost = 0.15,
		Smoothing = 4,
	},

	-- Свип волны перерождения (питч ползёт вверх всю длину волны)
	WaveSweep = {
		Sample = "RocketWhoosh" :: SampleName,
		PitchFrom = 0.5,
		PitchTo = 1.9,
		Volume = 0.9,
	},

	Impact = {
		SpeedForFullVolume = 260,
		MinVolumeScale = 0.35,
		PitchJitter = 0.015,
	},

	Pentatonic = { 0, 2, 4, 7, 9 }, -- мажорная пентатоника, полутоны от тоники
	PentatonicOctaves = 2,
	GongChord = { 0, 4, 7, 12 },
	ChordStrum = 0.05,
	CoinArpeggio = { 0, 2, 4, 7, 9, 12 },
	CoinStep = 0.045,
	PurchaseArpeggio = { 0, 4, 7, 12 },
	PurchaseStep = 0.06,

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

function SoundConfig.SemitoneRatio(semitones: number): number
	return 2 ^ (semitones / 12)
end

return SoundConfig
