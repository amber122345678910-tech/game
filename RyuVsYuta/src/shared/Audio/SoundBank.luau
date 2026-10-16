--!strict
-- Банк звуков катсцены. Все ID в одном месте. Звуки — из Магазина Roblox (публичные, лицензированные
-- библиотеки), подобраны по спектру/громкости. Если ID не загрузится — играет запасной встроенный звук.

local SoundBank = {}

export type Cue = {
	ids: { string }, -- несколько ID = варианты, чередуются по кругу
	backups: { string }?, -- запасные ID того же звука (если основной не загрузится)
	volume: number, -- Sound.Volume
	speed: number, -- Sound.PlaybackSpeed (высота)
	offset: number?, -- с какой секунды начинать (пропуск тишины)
	duration: number?, -- длина звука в секундах (для перемотки)
	loop: boolean?,
	group: string, -- "Ambience" | "SFX" | "Energy" | "Music"
	fallback: string?,
}

export type Group = {
	volume: number,
	reverb: { decay: number, dry: number, wet: number }?,
	lowShelf: number?,
	highShelf: number?,
}

SoundBank.masterVolume = 1

SoundBank.groups = {
	Ambience = { volume = 1 },
	SFX = { volume = 1, reverb = { decay = 2.4, dry = -1, wet = -13 } },
	Energy = { volume = 1, reverb = { decay = 1.2, dry = 0, wet = -16 } },
	Music = { volume = 0.9 },
	Voice = { volume = 1 },
} :: { [string]: Group }

SoundBank.defaultFallback = "rbxasset://sounds/impact_explosion_03.mp3"

-- Подобрано по замерам (LUFS, спектр, пропуск тишины). volume рассчитан так, чтобы громкость
-- совпадала с ролью звука: подложки тихо, толчки и удары плотно, "дзынь" — самый громкий момент.
SoundBank.cues = {
	-- хвост взрыва Granite Blast
	blast_aftermath = {
		ids = { "rbxassetid://1843024924" },
		backups = { "rbxassetid://9114224129", "rbxassetid://1845133529" },
		volume = 0.63,
		speed = 0.9,
		offset = 0.35,
		duration = 6.8,
		group = "SFX",
		fallback = "rbxasset://sounds/impact_explosion_03.mp3",
	},
	-- смешок Рю
	chuckle = {
		ids = { "rbxassetid://9116452741" },
		backups = { "rbxassetid://9116452733", "rbxassetid://9116452853" },
		volume = 3.85,
		speed = 0.95,
		offset = 0.24,
		duration = 2.74,
		group = "Voice",
	},
	-- куртка треплется на ветру (петля)
	coat_flap = {
		ids = { "rbxassetid://9114576083" },
		backups = { "rbxassetid://9113716666", "rbxassetid://9114576087" },
		volume = 0.79,
		speed = 1.1,
		offset = 0.09,
		duration = 26.84,
		loop = true,
		group = "SFX",
	},
	-- взмах куртки
	coat_swish = {
		ids = { "rbxassetid://9125714290" },
		backups = { "rbxassetid://9113716929", "rbxassetid://9125714280" },
		volume = 0.88,
		speed = 1.0,
		offset = 0.04,
		duration = 1.37,
		group = "SFX",
	},
	-- дыхание Рики
	creature_breath = {
		ids = { "rbxassetid://9113983944" },
		backups = { "rbxassetid://9116300504", "rbxassetid://9043349882" },
		volume = 1.41,
		speed = 0.8,
		offset = 0.35,
		duration = 4.69,
		group = "SFX",
	},
	-- осыпаются мелкие обломки
	debris_settle = {
		ids = { "rbxassetid://9114035055" },
		backups = { "rbxassetid://9125870803", "rbxassetid://9114035117" },
		volume = 1.23,
		speed = 1.0,
		offset = 0.1,
		duration = 13.9,
		group = "Ambience",
	},
	-- вдалеке рушится здание
	distant_crumble = {
		ids = { "rbxassetid://9114220506" },
		backups = { "rbxassetid://9113224519", "rbxassetid://9113220466" },
		volume = 0.33,
		speed = 0.85,
		offset = 1.5,
		duration = 12.8,
		group = "SFX",
	},
	-- треск проклятой энергии (петля)
	electric_crackle_loop = {
		ids = { "rbxassetid://9112776285" },
		backups = { "rbxassetid://9119993024", "rbxassetid://9125566580" },
		volume = 0.19,
		speed = 1.0,
		offset = 0,
		duration = 51.01,
		loop = true,
		group = "Energy",
	},
	-- вспышка синей энергии «дзынь»
	electric_zing = {
		ids = { "rbxassetid://9118067736" },
		backups = { "rbxassetid://9116280102", "rbxassetid://9118068025" },
		volume = 2.02,
		speed = 1.0,
		offset = 0.09,
		duration = 1.71,
		group = "Energy",
	},
	-- нарастание энергии перед вспышкой
	energy_charge = {
		ids = { "rbxassetid://9125806397" },
		backups = { "rbxassetid://9125980784", "rbxassetid://1845124443" },
		volume = 0.54,
		speed = 1.0,
		offset = 0.08,
		duration = 1.94,
		group = "Energy",
	},
	-- вспыхивает глаз Рики
	eye_glint = {
		ids = { "rbxassetid://9114365649" },
		backups = { "rbxassetid://9119076600", "rbxassetid://9114365437" },
		volume = 0.38,
		speed = 0.9,
		offset = 0.2,
		duration = 1.61,
		group = "SFX",
	},
	-- клубы дыма проносятся мимо камеры
	fog_whoosh = {
		ids = { "rbxassetid://9120697982", "rbxassetid://9120698420", "rbxassetid://9120697823" },
		backups = { "rbxassetid://9125633095", "rbxassetid://9113201092" },
		volume = 0.33,
		speed = 0.85,
		offset = 0.2,
		duration = 6.2,
		group = "SFX",
	},
	-- мех воротника на ветру (петля)
	fur_rustle = {
		ids = { "rbxassetid://9114461591" },
		backups = { "rbxassetid://9114462805", "rbxassetid://9113837058" },
		volume = 4.79,
		speed = 1.15,
		offset = 0.12,
		duration = 10.68,
		loop = true,
		group = "SFX",
	},
	-- тяжёлый толчок Рики
	giant_footstep = {
		ids = { "rbxassetid://9114077357", "rbxassetid://9114077122", "rbxassetid://9114077061" },
		backups = {  },
		volume = 3.43,
		speed = 0.9,
		offset = 0,
		duration = 1.98,
		group = "SFX",
		fallback = "rbxasset://sounds/impact_explosion_03.mp3",
	},
	-- дрожь земли
	ground_tremor = {
		ids = { "rbxassetid://1837830248" },
		backups = { "rbxassetid://9114221862", "rbxassetid://9118748536" },
		volume = 0.33,
		speed = 0.85,
		offset = 0,
		duration = 3.76,
		group = "SFX",
		fallback = "rbxasset://sounds/impact_explosion_03.mp3",
	},
	-- ладони по волосам
	hair_slick = {
		ids = { "rbxassetid://9113593785" },
		backups = { "rbxassetid://9114743127", "rbxassetid://9113534108" },
		volume = 10.0,
		speed = 0.9,
		offset = 0.07,
		duration = 0.7,
		group = "SFX",
	},
	-- хлопок ладоней по помпадуру
	hand_grab = {
		ids = { "rbxassetid://9114743127" },
		backups = { "rbxassetid://9113534108" },
		volume = 1.1,
		speed = 1.0,
		offset = 0.0,
		duration = 0.98,
		group = "SFX",
	},
	-- сердцебиение
	heartbeat = {
		ids = { "rbxassetid://1839090417" },
		backups = { "rbxassetid://1839088414", "rbxassetid://9043365993" },
		volume = 0.34,
		speed = 1.0,
		offset = 0.35,
		duration = 5.77,
		group = "Music",
	},
	-- шаги Юты по гравию
	human_footstep_gravel = {
		ids = { "rbxassetid://9118685568", "rbxassetid://9118687679", "rbxassetid://9118688006" },
		backups = {  },
		volume = 1.57,
		speed = 1.05,
		offset = 0.02,
		duration = 0.3,
		group = "SFX",
	},
	-- звяканье ножен
	katana_rattle = {
		ids = { "rbxassetid://9119748088" },
		backups = { "rbxassetid://9119747932", "rbxassetid://9113154591" },
		volume = 0.2,
		speed = 1.0,
		offset = 0.85,
		duration = 3.57,
		group = "SFX",
	},
	-- гул клубящегося дыма (петля)
	rumble_bed = {
		ids = { "rbxassetid://9125443744" },
		backups = { "rbxassetid://9112775375", "rbxassetid://9112775165" },
		volume = 0.4,
		speed = 1.0,
		offset = 0,
		duration = 36.0,
		loop = true,
		group = "Ambience",
	},
	-- хруст обломков
	step_debris = {
		ids = { "rbxassetid://9119050086", "rbxassetid://9119051028" },
		backups = {  },
		volume = 0.51,
		speed = 1.0,
		offset = 0.05,
		duration = 1.75,
		group = "SFX",
	},
	-- удар на смене кадра
	sting_hit = {
		ids = { "rbxassetid://1837829309" },
		backups = { "rbxassetid://9038214902", "rbxassetid://1843025542" },
		volume = 0.83,
		speed = 1.0,
		offset = 0,
		duration = 5.49,
		group = "SFX",
		fallback = "rbxasset://sounds/impact_explosion_03.mp3",
	},
	-- тёмная напряжённая музыка (петля)
	tension_music = {
		ids = { "rbxassetid://1838630765" },
		backups = { "rbxassetid://1839410752", "rbxassetid://9043359255" },
		volume = 0.18,
		speed = 1.0,
		offset = 0.03,
		duration = 29.99,
		loop = true,
		group = "Music",
	},
	-- ветер над руинами (петля)
	wind_bed = {
		ids = { "rbxassetid://15675021174" },
		backups = { "rbxassetid://551546110", "rbxassetid://9125742262" },
		volume = 0.42,
		speed = 1.1,
		offset = 0,
		duration = 10.6,
		loop = true,
		group = "Ambience",
	},

} :: { [string]: Cue }

return SoundBank
