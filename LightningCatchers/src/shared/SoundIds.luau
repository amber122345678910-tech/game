--!strict
-- Звуки игры. Все ID проверены (публичные, прошли модерацию, проигрываются в любой игре):
-- звуки самого Roblox (создатель Roblox, userId 1) и лицензированных библиотек
-- ProSoundEffects и APM из Creator Store. Start — сколько секунд тишины пропустить в начале
-- (измерено по файлам), чтобы звук совпадал с моментом удара.

export type SoundDef = {
	Id: string,
	Volume: number?,
	Pitch: number?,
	Start: number?, -- пропустить тишину в начале (с)
	Vary: number?, -- случайный разброс высоты (0.04 = ±4%)
	MinGap: number?, -- не чаще, чем раз в N секунд
	Looped: boolean?,
	Fallback: string?, -- встроенный звук клиента, если ID не загрузится
}

local SoundIds = {}

local function id(n: number): string
	return "rbxassetid://" .. tostring(n)
end

local CLICK_FALLBACK = "rbxasset://sounds/volume_slider.ogg"
local BOOM_FALLBACK = "rbxasset://sounds/impact_explosion_03.mp3"

SoundIds.Sfx = {
	-- интерфейс (Roblox)
	Click = { Id = id(15675059323), Volume = 0.5, Vary = 0.03, Fallback = CLICK_FALLBACK }, -- Roblox_UI_Bright_Click
	Hover = { Id = id(17208339919), Volume = 0.25, MinGap = 0.06 }, -- Roblox GUI - Hover 01
	Tab = { Id = id(17208408337), Volume = 0.4 }, -- Roblox GUI - Tab
	Error = { Id = id(17208353912), Volume = 0.5, Fallback = CLICK_FALLBACK }, -- Roblox GUI - Negative
	Purchase = { Id = id(17208380755), Volume = 0.6, Fallback = CLICK_FALLBACK }, -- Roblox GUI - Purchase
	Whoosh = { Id = id(15675024286), Volume = 0.35, MinGap = 0.1 }, -- Roblox_UI_Whoosh_01
	Notify = { Id = id(17208361335), Volume = 0.45, MinGap = 0.3 }, -- Roblox GUI - Notification High
	-- поимка
	Ding = { Id = id(9126073001), Volume = 1.0, Start = 0.1, MinGap = 0.02 }, -- Synth Sparkle Bell Tone Ding (PSE): тональный, для лесенки комбо
	PerfectZap = { Id = id(9113147683), Volume = 0.45, Vary = 0.05, MinGap = 0.03 }, -- Arc Zaps Phasey Short Bursts 2 (PSE)
	Miss = { Id = id(9116276051), Volume = 0.35, Pitch = 0.8, Vary = 0.05 }, -- Lightning Flashes Quick Electrical Bursts 11 (PSE)
	Zap = { Id = id(9114277402), Volume = 0.7, Start = 0.12, Vary = 0.06 }, -- Electric Zaps 6 (PSE): смешной удар током
	ThunderNear = { Id = id(9126068434), Volume = 0.55, Start = 0.2, Vary = 0.08, MinGap = 0.08, Fallback = BOOM_FALLBACK }, -- Synth Lightning Crack (PSE)
	ThunderFar = { Id = id(9120018172), Volume = 0.45, Start = 0.12, Vary = 0.1, MinGap = 0.5, Fallback = BOOM_FALLBACK }, -- Thunder Distant Boom (PSE)
	Warn = { Id = id(9125981170), Volume = 0.22, Start = 0.3, MinGap = 0.25 }, -- Electric Charge Up Glass (PSE)
	Shard = { Id = id(9126076030), Volume = 0.45, Vary = 0.06, MinGap = 0.05 }, -- Synth Sparkle Tone Burst Pin (PSE)
	Crackle = { Id = id(9116278351), Volume = 0.25, Vary = 0.1, MinGap = 0.3 }, -- Quick Electrical Bursts 38 (PSE): перегрузка
	Burst = { Id = id(9114591515), Volume = 0.55, Start = 1.0 }, -- Glass Breaks 2 (PSE): банка лопнула
	-- экономика
	Sell = { Id = id(9119806047), Volume = 0.45, Start = 0.5 }, -- Synth Doppler Rip Whoosh (PSE)
	Coins = { Id = id(127645268874265), Volume = 0.55, MinGap = 0.15 }, -- CoinTransfer_01 (Roblox)
	PowerUp = { Id = id(9117886786), Volume = 0.55 }, -- Power Up Sweeteners 17 (PSE): улучшение
	LevelUp = { Id = id(9046126586), Volume = 0.6 }, -- Rise Up (stinger) (APM): новый остров, перезапуск
	Victory = { Id = id(12222253), Volume = 0.5 }, -- victory.wav (Roblox)
	-- коллекции
	HatchWobble = { Id = id(9125644661), Volume = 0.5, Start = 0.12 }, -- Magic Twirling Spinning Chime (PSE)
	RareReveal = { Id = id(125706237686412), Volume = 0.7 }, -- Glistening Harp - Sting (APM)
	Fulgurite = { Id = id(9114619050), Volume = 0.8, Start = 0.15 }, -- Glass Tinks 2 (PSE)
	-- события
	EventStart = { Id = id(15675043410), Volume = 0.7 }, -- Roblox_UI_Tonal_Stinger
	Rainbow = { Id = id(9119447936), Volume = 1.0, Start = 0.3 }, -- Sparkle Bell Tree Wind Chimes (PSE)
	Perun = { Id = id(9120031442), Volume = 1.0, Start = 0.25, Fallback = BOOM_FALLBACK }, -- Thunder With Lion Roar (Roblox)
	CityLit = { Id = id(9125805579), Volume = 0.6, Start = 0.08 }, -- Rising Whoosh Build Up (PSE)
} :: { [string]: SoundDef }

SoundIds.Ambient = {
	Rain = { Id = id(1516791621), Volume = 0.22, Looped = true }, -- Rain Effect (Roblox)
	Wind = { Id = id(9114057128), Volume = 0.9, Looped = true }, -- Desert Wind Whistley Light Gusts (PSE), файл тихий
	Rumble = { Id = id(9120021267), Volume = 0.12, Looped = true }, -- Thunder Rumbling 3 (PSE)
} :: { [string]: SoundDef }

SoundIds.Music = {
	Zone = { Id = id(134765509233171), Volume = 0.22 }, -- Adventure Dreams (APM)
	Adventure = { Id = id(9047876673), Volume = 0.2 }, -- Happy Adventure (APM)
	Hub = { Id = id(9039509771), Volume = 0.2 }, -- Cozy Feeling (APM)
	Event = { Id = id(17422163655), Volume = 0.28 }, -- Generic - Cloud Blitz (Roblox)
	Storm = { Id = id(1840479887), Volume = 0.4 }, -- Storm Clouds Gather (B) (APM): Око Бури
} :: { [string]: SoundDef }

return SoundIds
