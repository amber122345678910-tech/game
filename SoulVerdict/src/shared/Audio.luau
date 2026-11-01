--!strict
-- Audio: the named sound registry used by Client/Controllers/SoundController (SPEC §9, §20). Lune-safe, data only.
--
-- OWNER: HOW TO ADD SOUNDS (no upload needed)
--   1. In Roblox Studio open the Toolbox -> Creator Store -> Audio (100k+ free SFX & music by Roblox/partners).
--   2. Find a sound that fits the entry's `Note`, right-click it -> "Copy Asset ID".
--   3. Paste it into that entry's Id below, e.g.  Id = "rbxassetid://1234567890"  (a bare "1234567890" works too).
--   An entry whose Id is "" plays NOTHING (silently) — the game is fully playable without any ids.
--   Do not use Undertale's soundtrack (copyrighted); use original / licensed Creator Store music.
--   Entries with `Fallback` use another entry while their own Id is empty: e.g. every UI theme sound falls back to
--   the generic Ui* sounds, every per-map "<Map>_Final" track falls back to "FinalPhase".
--
-- Only these built-in files are confirmed to ship with every Roblox client (docs/research/builtin_sounds.txt):
--   rbxasset://sounds/{action_footsteps_plastic.mp3, action_falling.ogg, action_get_up.mp3, action_jump.mp3,
--   action_jump_land.mp3, action_swim.mp3, impact_water.mp3, uuhhh.mp3}
--
-- API
--   Audio.Sounds: { [name]: SoundDef }               every entry (SFX, UI and music)
--   Audio.Get(name) -> SoundDef?                     raw entry (aliases resolved), Id may be ""
--   Audio.Resolve(name) -> (SoundDef?, string?)      first entry along the Fallback chain with a non-empty Id
--                                                    (and the name of that entry); nil = silent
--   Audio.NormalizeId(id) -> string                  "123" -> "rbxassetid://123"; "" stays ""
--   Audio.Names(group?) -> {string}                  sorted names (optionally of one group)
--   Audio.MapMusic(musicKey, final?) -> string       "<key>" or "<key>_Final" (final falls back to "FinalPhase")
--   Audio.Validate() -> {string}                     list of problems (empty = well-formed); used by the tests
--   Audio.Groups: { Music, SFX, UI }                 base volumes of the SoundGroups (x player settings)
--   Audio.Aliases: { [alias]: name }                 e.g. "HallOfVerdicts" -> "Map_HallOfVerdicts"
--
-- SoundDef = {
--   Id: string,            "rbxassetid://<n>" | "rbxasset://sounds/<file>" | "<n>" | "" (silent)
--   Group: "Music" | "SFX" | "UI",
--   Volume: number,        Sound.Volume before the group volume (0..2)
--   Pitch: {number}?,      {min, max} random PlaybackSpeed per play (default {1, 1})
--   Spatial: boolean?,     true = 3D when played at a position / part / attachment (else always 2D)
--   Looped: boolean?,
--   RollOff: {number}?,    {min, max} studs for 3D sounds (default {10, 160})
--   MaxInstances: number?, concurrent voices of this name (default 6, music 1)
--   MinInterval: number?,  plays closer together than this (seconds) are dropped (default 0.03)
--   Fallback: string?,     entry used while this Id is empty
--   Note: string?,         what to search for in the Creator Store
-- }

export type Group = "Music" | "SFX" | "UI"

export type SoundDef = {
	Id: string,
	Group: Group,
	Volume: number,
	Pitch: { number }?,
	Spatial: boolean?,
	Looped: boolean?,
	RollOff: { number }?,
	MaxInstances: number?,
	MinInterval: number?,
	Fallback: string?,
	Note: string?,
}

local Audio = {}

Audio.Groups = {
	Music = { Volume = 0.8 },
	SFX = { Volume = 1.0 },
	UI = { Volume = 0.9 },
}

Audio.DEFAULT_ROLLOFF = { 10, 160 }
Audio.DEFAULT_MAX_INSTANCES = 6
Audio.DEFAULT_MIN_INTERVAL = 0.03

local BUILTIN = {
	Footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Falling = "rbxasset://sounds/action_falling.ogg",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Oof = "rbxasset://sounds/uuhhh.mp3",
}
Audio.Builtin = BUILTIN

local function music(note: string, volume: number?, looped: boolean?): SoundDef
	return {
		Id = "", -- OWNER: paste a Creator Store music id
		Group = "Music",
		Volume = volume or 0.5,
		Looped = if looped == nil then true else looped,
		MaxInstances = 1,
		Note = note,
	}
end

local function sfx(id: string, volume: number, pitch: { number }?, spatial: boolean?, note: string?): SoundDef
	return {
		Id = id,
		Group = "SFX",
		Volume = volume,
		Pitch = pitch,
		Spatial = if spatial == nil then true else spatial,
		Note = note,
	}
end

local function ui(id: string, volume: number, pitch: { number }?, note: string?): SoundDef
	return {
		Id = id,
		Group = "UI",
		Volume = volume,
		Pitch = pitch,
		Spatial = false,
		MinInterval = 0.04,
		MaxInstances = 4,
		Note = note,
	}
end

local SOUNDS: { [string]: SoundDef } = {
	------------------------------------------------------------------------------------------------- music
	-- Keys match Maps/Registry `Music` fields ("Lobby", "Map_<MapId>").
	Lobby = music("calm, mysterious lobby loop (piano / music box, ~90 BPM)", 0.45),
	Map_HallOfVerdicts = music("solemn golden-hall battle loop: organ / strings, building tension", 0.5),
	Map_SnowdinCrossroads = music("cozy-but-tense snowy town battle loop: bells, pizzicato, light drums", 0.5),
	Map_WaterfallGrotto = music("echoing cave battle loop: plucks, pads, water ambience, mid tempo", 0.5),
	Map_VoidRift = music("eerie synth battle loop: detuned pads, glitchy percussion", 0.5),
	Map_CoreReactor = music("driving industrial/electronic battle loop, high energy", 0.5),
	FinalPhase = music("desperate final-phase boss loop: fast, intense, heavy drums", 0.55),
	VerdictBox = music("short frantic chiptune/8-bit bullet-hell loop (~7-15 s)", 0.55),
	Victory = music("short triumphant victory stinger (3-8 s, not looping)", 0.6, false),
	Defeat = music("short somber defeat stinger (3-8 s, not looping)", 0.6, false),

	------------------------------------------------------------------------------------------- movement
	Footstep = sfx(BUILTIN.Footstep, 0.35, { 0.95, 1.1 }, true, "built-in"),
	Falling = sfx(BUILTIN.Falling, 0.3, nil, true, "built-in"),
	Jump = sfx(BUILTIN.Jump, 0.4, { 0.95, 1.05 }, true, "built-in"),
	DoubleJump = sfx(BUILTIN.Jump, 0.5, { 1.25, 1.35 }, true, "built-in, pitched up"),
	Land = sfx(BUILTIN.Land, 0.45, { 0.9, 1.05 }, true, "built-in"),
	Swim = sfx(BUILTIN.Swim, 0.35, nil, true, "built-in"),
	Splash = sfx(BUILTIN.Splash, 0.5, { 0.9, 1.1 }, true, "built-in"),
	GetUp = sfx(BUILTIN.GetUp, 0.5, nil, true, "built-in (revive stand-up)"),
	Oof = sfx(BUILTIN.Oof, 0.5, nil, true, "built-in classic death sound (unused by default)"),
	Dash = sfx("", 0.6, { 0.95, 1.08 }, true, "short air whoosh / swish (0.2-0.4 s)"),
	Teleport = sfx("", 0.6, { 0.95, 1.05 }, true, "quick blink / warp zap"),
	SlamLand = sfx("", 0.8, { 0.9, 1.0 }, true, "heavy ground slam thud"),

	-------------------------------------------------------------------------------------------- combat
	BlasterCharge = sfx("", 0.75, { 0.97, 1.03 }, true, "rising laser/energy charge-up (~0.6-1 s)"),
	BlasterFire = sfx("", 0.9, { 0.95, 1.02 }, true, "big laser beam blast"),
	BoneRise = sfx("", 0.55, { 0.92, 1.08 }, true, "quick rattling rise / wooden clack"),
	BoneHit = sfx("", 0.6, { 0.9, 1.1 }, true, "bony clack impact"),
	BoneThrow = sfx("", 0.5, { 0.95, 1.1 }, true, "light whoosh with a rattle"),
	Slash = sfx("", 0.6, { 0.92, 1.08 }, true, "blade slash swish"),
	Punch = sfx("", 0.65, { 0.9, 1.08 }, true, "punch impact"),
	Kick = sfx("", 0.6, { 0.9, 1.05 }, true, "kick impact"),
	Shot = sfx("", 0.6, { 0.95, 1.05 }, true, "magic pistol shot / pew"),
	Explosion = sfx("", 0.8, { 0.92, 1.04 }, true, "small magical explosion"),
	Whoosh = sfx("", 0.5, { 0.9, 1.1 }, true, "generic whoosh"),
	Charge = sfx("", 0.5, { 0.98, 1.02 }, true, "magic charge loop/hum"),
	Cast = sfx("", 0.5, { 0.95, 1.05 }, true, "generic spell cast shimmer"),
	Hit = sfx("", 0.6, { 0.92, 1.08 }, true, "Undertale-like damage hit (crunchy blip)"),
	HitHeavy = sfx("", 0.75, { 0.9, 1.0 }, true, "heavy hit impact"),
	Crit = sfx("", 0.7, { 0.98, 1.04 }, true, "sharp critical hit ding/crack"),
	Hurt = sfx("", 0.6, { 0.95, 1.05 }, false, "player SOUL hurt blip (2D, local player only)"),
	Block = sfx("", 0.6, { 0.95, 1.05 }, true, "shield block clank"),
	Parry = sfx("", 0.8, { 1.0, 1.05 }, true, "bright metallic parry ring"),
	GuardBreak = sfx("", 0.8, { 0.95, 1.0 }, true, "shield shatter / break"),
	Dodge = sfx("", 0.55, { 0.95, 1.1 }, true, "lazy side-step whoosh (monster MISS)"),
	Miss = sfx("", 0.45, { 1.0, 1.05 }, true, "light 'miss' blip"),
	Exhausted = sfx("", 0.6, nil, true, "tired exhale / deflate"),
	KR = sfx("", 0.35, { 1.0, 1.1 }, false, "tiny poison tick (2D, local player only)"),
	Heal = sfx("", 0.6, { 1.0, 1.05 }, true, "soft healing chime"),
	Shield = sfx("", 0.55, nil, true, "magic barrier hum-up"),
	Stun = sfx("", 0.55, nil, true, "dizzy stars / stun ring"),
	Downed = sfx("", 0.7, nil, true, "heart crack (SOUL cracked)"),
	SoulBreak = sfx("", 0.8, nil, true, "heart shatter (Undertale-like, original)"),
	Revive = sfx("", 0.65, nil, true, "uplifting revive swell"),
	Kill = sfx("", 0.7, nil, false, "kill confirm sting (2D)"),
	HitConfirm = sfx("", 0.5, { 1.0, 1.05 }, false, "2D hit-marker tick for the attacker (very short)"),
	BoneImpact = sfx("", 0.6, { 0.9, 1.1 }, true, "bone projectile hitting the ground"),
	Shockwave = sfx("", 0.75, { 0.92, 1.05 }, true, "ground shockwave boom / ring"),
	Implode = sfx("", 0.7, { 0.95, 1.05 }, true, "reverse whoosh into a dark implosion"),
	SoulAppear = sfx("", 0.55, { 1.0, 1.04 }, true, "SOUL heart appears: soft shimmer"),
	SoulCrack = sfx("", 0.7, nil, true, "heart crack (SOUL cracked / downed)"),
	SoulShatter = sfx("", 0.8, nil, true, "heart shatters into pieces"),
	Dust = sfx("", 0.6, nil, true, "a monster turns to dust: soft sandy crumble"),
	-- kit-specific (Classic Sans client kit)
	BlasterSummon = sfx("", 0.75, { 0.97, 1.03 }, true, "Gaster Blaster materialising: deep magical whoom"),
	BlasterTick = sfx("", 0.45, { 1.0, 1.08 }, true, "short tick while a blaster locks on"),
	BoneSummon = sfx("", 0.7, { 0.95, 1.05 }, true, "a field of bones erupting from the ground"),
	SoulGrab = sfx("", 0.7, nil, true, "blue SOUL grab: magical whoosh + chime"),
	Slam = sfx("", 0.85, { 0.92, 1.0 }, true, "body slammed into the ground: heavy thud"),
	Shortcut = sfx("", 0.6, { 0.98, 1.04 }, true, "the monster takes a shortcut: quick blink"),
	BadTime = sfx("", 0.9, nil, true, "ominous low sting for the monster's ultimate"),
	-- kit-specific (Determination client kit)
	Lunge = sfx("", 0.65, { 0.95, 1.05 }, true, "fast lunge whoosh + stab"),
	Counter = sfx("", 0.75, { 1.0, 1.05 }, true, "sharp counter-strike clang"),
	Afterimage = sfx("", 0.5, { 1.0, 1.1 }, true, "ghostly whoosh as an afterimage is left behind"),
	Determination = sfx("", 0.85, nil, true, "heroic DETERMINATION swell (human ultimate)"),
	Portal = sfx("", 0.6, { 0.95, 1.05 }, true, "void portal open"),
	VoidHum = sfx("", 0.4, nil, true, "dark void hum loop"),
	Freeze = sfx("", 0.55, nil, true, "ice crackle"),

	------------------------------------------------------------------------------------------ objectives
	SaveChannel = sfx("", 0.45, nil, true, "gentle rising shimmer loop (channeling a SAVE star)"),
	SaveLit = sfx("", 0.8, nil, false, "SAVE point lit: bright sparkle chime"),
	Surge = sfx("", 0.85, nil, false, "big heroic power-up swell"),
	FinalPhaseStinger = sfx("", 0.9, nil, false, "dramatic transformation hit + rumble"),
	Collapse = sfx("", 0.7, nil, false, "deep rumble / alarm, the arena collapses"),
	CollapseTick = sfx("", 0.4, nil, false, "void damage tick"),
	BoxOpen = sfx("", 0.75, nil, false, "battle-box open whoosh + chime"),
	BoxClose = sfx("", 0.6, nil, false, "battle-box close"),
	RoundStart = sfx("", 0.8, nil, false, "fight start stinger / gong"),
	Countdown = sfx("", 0.6, nil, false, "countdown tick"),
	Ding = sfx("", 0.6, nil, false, "clear 'ding' (rewards, level up)"),
	LevelUp = sfx("", 0.8, nil, false, "LOVE/level up jingle"),

	------------------------------------------------------------------------------------------------ UI
	UiHover = ui("", 0.35, { 1.0, 1.04 }, "soft tick / menu move"),
	UiClick = ui("", 0.45, nil, "button click"),
	UiConfirm = ui("", 0.5, nil, "menu select / confirm"),
	UiBack = ui("", 0.45, nil, "menu back / cancel"),
	UiOpen = ui("", 0.45, nil, "panel open whoosh"),
	UiClose = ui("", 0.4, nil, "panel close"),
	UiError = ui("", 0.45, nil, "error buzz"),
	UiToggle = ui("", 0.4, nil, "toggle switch click"),
	UiReward = ui("", 0.55, nil, "reward sparkle"),
	TextBlip = ui("", 0.3, { 0.98, 1.02 }, "typewriter text blip (very short)"),
	SansTextBlip = ui("", 0.3, { 0.98, 1.02 }, "lower, rounder text blip for the monster's lines"),
	Notify = ui("", 0.4, nil, "notification pop"),
	Denied = ui("", 0.4, nil, "short 'not ready' buzz (ability on cooldown / no target)"),
}

-- defaults that are fallbacks of other generic entries
SOUNDS.UiOpen.Fallback = "UiConfirm"
SOUNDS.UiClose.Fallback = "UiBack"
SOUNDS.UiToggle.Fallback = "UiClick"
SOUNDS.UiReward.Fallback = "UiConfirm"
SOUNDS.Notify.Fallback = "UiHover"
SOUNDS.Denied.Fallback = "UiError"
SOUNDS.SansTextBlip.Fallback = "TextBlip"
SOUNDS.HitHeavy.Fallback = "Hit"
SOUNDS.Crit.Fallback = "Hit"
SOUNDS.Kick.Fallback = "Punch"
SOUNDS.Miss.Fallback = "Dodge"
SOUNDS.SoulBreak.Fallback = "Downed"
SOUNDS.SlamLand.Fallback = "Land"
SOUNDS.Revive.Fallback = "GetUp"
SOUNDS.HitConfirm.Fallback = "Hit"
SOUNDS.BoneImpact.Fallback = "BoneHit"
SOUNDS.Shockwave.Fallback = "Explosion"
SOUNDS.SoulCrack.Fallback = "Downed"
SOUNDS.SoulShatter.Fallback = "SoulBreak"
SOUNDS.Implode.Fallback = "Portal"
SOUNDS.BlasterSummon.Fallback = "BlasterCharge"
SOUNDS.BoneSummon.Fallback = "BoneRise"
SOUNDS.SoulGrab.Fallback = "Cast"
SOUNDS.Slam.Fallback = "SlamLand"
SOUNDS.Shortcut.Fallback = "Teleport"
SOUNDS.BadTime.Fallback = "FinalPhaseStinger"
SOUNDS.Lunge.Fallback = "Slash"
SOUNDS.Counter.Fallback = "Parry"
SOUNDS.Afterimage.Fallback = "Dodge"
SOUNDS.Determination.Fallback = "Surge"

-- UI theme keys used by src/client/UI/Themes.luau ("UI.<Theme>.<Kind>"): silent placeholders that fall back to
-- the generic Ui* entries. Paste theme-specific ids here to give each menu theme its own voice.
local THEME_KINDS: { [string]: string } = {
	Move = "UiHover",
	Hover = "UiHover",
	Select = "UiConfirm",
	Back = "UiBack",
	Open = "UiOpen",
	Close = "UiClose",
	Error = "UiError",
	Toggle = "UiToggle",
	Text = "TextBlip",
	Save = "UiReward",
	Reward = "UiReward",
}
for _, theme in { "Classic", "Royal", "Void", "Fell" } do
	for kind, generic in THEME_KINDS do
		SOUNDS["UI." .. theme .. "." .. kind] = {
			Id = "", -- OWNER: optional theme-specific id
			Group = "UI",
			Volume = SOUNDS[generic].Volume,
			Pitch = SOUNDS[generic].Pitch,
			Spatial = false,
			MinInterval = 0.04,
			MaxInstances = 4,
			Fallback = generic,
		}
	end
end

-- Optional per-map final-phase tracks ("<MusicKey>_Final") fall back to the shared FinalPhase track.
local MAP_MUSIC = {
	"Map_HallOfVerdicts",
	"Map_SnowdinCrossroads",
	"Map_WaterfallGrotto",
	"Map_VoidRift",
	"Map_CoreReactor",
}
for _, key in MAP_MUSIC do
	local finalDef = music("optional: this map's own final-phase loop", 0.55)
	finalDef.Fallback = "FinalPhase"
	SOUNDS[key .. "_Final"] = finalDef
end

Audio.Sounds = SOUNDS
Audio.MapMusicKeys = MAP_MUSIC

Audio.Aliases = {
	HallOfVerdicts = "Map_HallOfVerdicts",
	SnowdinCrossroads = "Map_SnowdinCrossroads",
	WaterfallGrotto = "Map_WaterfallGrotto",
	VoidRift = "Map_VoidRift",
	CoreReactor = "Map_CoreReactor",
	TestArena = "Map_HallOfVerdicts",
	Map_TestArena = "Map_HallOfVerdicts",
	Map_Lobby = "Lobby",
	Final = "FinalPhase",
	UiSelect = "UiConfirm",
}

local MAX_FALLBACK_DEPTH = 6

function Audio.Get(name: string): SoundDef?
	local def = SOUNDS[name]
	if def == nil then
		local alias = Audio.Aliases[name]
		if alias then
			def = SOUNDS[alias]
		end
	end
	return def
end

function Audio.NormalizeId(id: string?): string
	if type(id) ~= "string" or id == "" then
		return ""
	end
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

-- Follows the Fallback chain to the first entry with a non-empty Id. Returns (nil, nil) when silent.
function Audio.Resolve(name: string): (SoundDef?, string?)
	local current: string? = if SOUNDS[name] then name else Audio.Aliases[name]
	local depth = 0
	while current ~= nil and depth < MAX_FALLBACK_DEPTH do
		local def = SOUNDS[current]
		if def == nil then
			return nil, nil
		end
		if def.Id ~= "" then
			return def, current
		end
		current = def.Fallback
		depth += 1
	end
	return nil, nil
end

function Audio.MapMusic(musicKey: string?, final: boolean?): string
	local key = if type(musicKey) == "string" and musicKey ~= "" then musicKey else "Lobby"
	key = Audio.Aliases[key] or key
	if final then
		local finalKey = key .. "_Final"
		if SOUNDS[finalKey] then
			return finalKey
		end
		return "FinalPhase"
	end
	return key
end

function Audio.Names(group: Group?): { string }
	local out = {}
	for name, def in SOUNDS do
		if group == nil or def.Group == group then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

local VALID_GROUP = { Music = true, SFX = true, UI = true }

local function validId(id: any): boolean
	if type(id) ~= "string" then
		return false
	end
	if id == "" or string.match(id, "^%d+$") then
		return true
	end
	return string.match(id, "^rbxassetid://%d+$") ~= nil or string.match(id, "^rbxasset://sounds/[%w_%./ ]+$") ~= nil
end

function Audio.Validate(): { string }
	local problems = {}
	local function bad(name: string, msg: string)
		table.insert(problems, name .. ": " .. msg)
	end
	for name, def in SOUNDS do
		if type(def) ~= "table" then
			bad(name, "not a table")
			continue
		end
		if not validId(def.Id) then
			bad(name, "bad Id " .. tostring(def.Id))
		end
		if not VALID_GROUP[def.Group] then
			bad(name, "bad Group " .. tostring(def.Group))
		end
		if type(def.Volume) ~= "number" or def.Volume < 0 or def.Volume > 2 then
			bad(name, "Volume must be 0..2")
		end
		if def.Pitch ~= nil then
			local p = def.Pitch
			if type(p) ~= "table" or type(p[1]) ~= "number" or type(p[2]) ~= "number" or p[1] <= 0 or p[2] < p[1] then
				bad(name, "Pitch must be {min, max} with 0 < min <= max")
			end
		end
		if def.RollOff ~= nil then
			local r = def.RollOff
			if type(r) ~= "table" or type(r[1]) ~= "number" or type(r[2]) ~= "number" or r[1] <= 0 or r[2] <= r[1] then
				bad(name, "RollOff must be {min, max} with 0 < min < max")
			end
		end
		if def.MaxInstances ~= nil and (type(def.MaxInstances) ~= "number" or def.MaxInstances < 1) then
			bad(name, "MaxInstances must be >= 1")
		end
		if def.Fallback ~= nil then
			if SOUNDS[def.Fallback] == nil then
				bad(name, "unknown Fallback " .. tostring(def.Fallback))
			elseif SOUNDS[def.Fallback].Group ~= def.Group then
				bad(name, "Fallback in another group")
			end
			-- cycle check
			local seen = { [name] = true }
			local current: string? = def.Fallback
			local depth = 0
			while current ~= nil do
				if seen[current] then
					bad(name, "Fallback cycle")
					break
				end
				seen[current] = true
				depth += 1
				if depth > MAX_FALLBACK_DEPTH then
					bad(name, "Fallback chain too long")
					break
				end
				local nextDef = SOUNDS[current]
				current = if nextDef then nextDef.Fallback else nil
			end
		end
		if def.Group == "Music" and def.Spatial then
			bad(name, "music cannot be spatial")
		end
	end
	for alias, target in Audio.Aliases do
		if SOUNDS[target] == nil then
			bad(alias, "alias to unknown entry " .. tostring(target))
		end
		if SOUNDS[alias] ~= nil then
			bad(alias, "alias shadows a real entry")
		end
	end
	table.sort(problems)
	return problems
end

return Audio
