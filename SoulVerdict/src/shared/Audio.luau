--!strict
-- Audio: the named sound registry used by Client/Controllers/SoundController (SPEC §9, §20). Lune-safe, data only.
--
-- OWNER: HOW TO ADD SOUNDS (no upload needed)
--   1. In Roblox Studio open the Toolbox -> Creator Store -> Audio (100k+ free SFX & music by Roblox/partners).
--   2. Find a sound that fits the entry's `Note`, right-click it -> "Copy Asset ID".
--   3. Add it to that entry's CANDIDATE LIST, best first (a bare "1234567890" or "rbxassetid://1234567890"):
--        music:   Theme_FellSans = music("...", 0.5, { "1234567890", "2345678901" }),
--        SFX/UI:  Hit = sfx({ "1234567890", "2345678901" }, 0.6, ...),     (a single "id" string works too)
--        others:  SOUNDS["Map_VoidRift_Final"].Ids = { "1234567890" }   (generated entries, below their loop)
--   4. Or just send the ids to the developer.
--   The game CHECKS every id automatically while it runs (ContentProvider:PreloadAsync) and skips the broken ones
--   (private since Roblox's 2022 audio privacy update, deleted or moderated): the next candidate plays instead, and
--   the Output window shows "[Sound] audio id failed to load: <id> (<entry>)" for each one. When every candidate
--   of a monster theme fails, the map's track plays. Admin panel -> TEST -> MUSIC previews any track and shows the
--   id in use and its status. An entry without candidates plays NOTHING (silently): the game is fully playable
--   without any ids.
--   Undertale / Underfell songs and remixes on Roblox are fan uploads of copyrighted music: Roblox can remove them
--   at any time (then the next candidate plays). Original / licensed Creator Store music is the safe choice, so
--   list one as the last candidate where you can.
--   Entries with `Fallback` use another entry while they have no working candidate: e.g. every UI theme sound falls
--   back to the generic Ui* sounds, every per-map "<Map>_Final" track falls back to "FinalPhase".
--
-- Only these built-in files are confirmed to ship with every Roblox client (docs/research/builtin_sounds.txt):
--   rbxasset://sounds/{action_footsteps_plastic.mp3, action_falling.ogg, action_get_up.mp3, action_jump.mp3,
--   action_jump_land.mp3, action_swim.mp3, impact_water.mp3, uuhhh.mp3}
--
-- API
--   Audio.Sounds: { [name]: SoundDef }               every entry (SFX, UI and music)
--   Audio.Get(name) -> SoundDef?                     raw entry (aliases resolved), may have no candidates
--   Audio.Candidates(name) -> {string}               normalized, de-duplicated {Id, ...Ids} of that exact entry
--                                                    (aliases resolved, no Fallback chain); {} when none
--   Audio.CandidatesOf(def?) -> {string}             the same for a SoundDef table (runtime entries)
--   Audio.IsFilled(def?) -> boolean                  the entry has at least one candidate
--   Audio.Resolve(name) -> (SoundDef?, string?)      first entry along the Fallback chain with a candidate
--                                                    (and the name of that entry); nil = silent
--   Audio.NormalizeId(id) -> string                  "123" -> "rbxassetid://123"; "" stays ""
--   Audio.Names(group?) -> {string}                  sorted names (optionally of one group)
--   Audio.MapMusic(musicKey, final?) -> string       "<key>" or "<key>_Final" (final falls back to "FinalPhase")
--   Audio.MonsterTheme(kitId?, final?) -> string?    "Theme_<kit>" / "Theme_<kit>_Final" when that entry exists
--   Audio.ThemeKits: {string}                        kit ids that have Theme_<kit> entries
--   Audio.Validate() -> {string}                     list of problems (empty = well-formed); used by the tests
--   Audio.Groups: { Music, SFX, UI }                 base volumes of the SoundGroups (x player settings)
--   Audio.Aliases: { [alias]: name }                 e.g. "HallOfVerdicts" -> "Map_HallOfVerdicts"
--
-- SoundDef = {
--   Id: string,            "rbxassetid://<n>" | "rbxasset://sounds/<file>" | "<n>" | "" (none)
--   Ids: {string}?,        more candidate ids (same formats), tried in order after Id
--   Group: "Music" | "SFX" | "UI",
--   Volume: number,        Sound.Volume before the group volume (0..2)
--   Pitch: {number}?,      {min, max} random PlaybackSpeed per play (default {1, 1})
--   Spatial: boolean?,     true = 3D when played at a position / part / attachment (else always 2D)
--   Looped: boolean?,
--   RollOff: {number}?,    {min, max} studs for 3D sounds (default {10, 160})
--   MaxInstances: number?, concurrent voices of this name (default 6, music 1)
--   MinInterval: number?,  plays closer together than this (seconds) are dropped (default 0.03)
--   Fallback: string?,     entry used while this one has no working candidate
--   Note: string?,         what to search for in the Creator Store
-- }

export type Group = "Music" | "SFX" | "UI"

export type SoundDef = {
	Id: string,
	Ids: { string }?,
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

-- `ids` = the candidate list, best first (OWNER: paste ids into the `{}` of an entry)
local function music(note: string, volume: number?, ids: { string }?, looped: boolean?): SoundDef
	return {
		Id = "",
		Ids = ids or {},
		Group = "Music",
		Volume = volume or 0.5,
		Looped = if looped == nil then true else looped,
		MaxInstances = 1,
		Note = note,
	}
end

-- `id` = one id string ("" = none yet) or a candidate list { "123", "456" } (best first)
local function sfx(
	id: string | { string },
	volume: number,
	pitch: { number }?,
	spatial: boolean?,
	note: string?
): SoundDef
	return {
		Id = if type(id) == "string" then id else "",
		Ids = if type(id) == "table" then id else nil,
		Group = "SFX",
		Volume = volume,
		Pitch = pitch,
		Spatial = if spatial == nil then true else spatial,
		Note = note,
	}
end

local function ui(id: string | { string }, volume: number, pitch: { number }?, note: string?): SoundDef
	return {
		Id = if type(id) == "string" then id else "",
		Ids = if type(id) == "table" then id else nil,
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
	-- OWNER: candidate ids go into the `{}` of each entry, best first, e.g. music("...", 0.5, { "123", "456" }).
	-- Keys match Maps/Registry `Music` fields ("Lobby", "Map_<MapId>").
	Lobby = music("calm, mysterious lobby loop (piano / music box, ~90 BPM)", 0.45, { "328964090", "314069452", "1848363318", "1838649967", "1848354536" }),
	Map_HallOfVerdicts = music("solemn golden-hall battle loop: organ / strings, building tension", 0.5, { "746812937", "1844758350", "1839290228", "1837835644" }),
	Map_SnowdinCrossroads = music("cozy-but-tense snowy town battle loop: bells, pizzicato, light drums", 0.5, { "14264872551", "98223235470761", "6390779289", "1836542585", "1836595204" }),
	Map_WaterfallGrotto = music("echoing cave battle loop: plucks, pads, water ambience, mid tempo", 0.5, { "99649859652828", "126038262761422", "10728729976", "1839824117", "1846767914" }),
	Map_VoidRift = music("eerie synth battle loop: detuned pads, glitchy percussion", 0.5, { "134959834418523", "1846350498", "1838974004", "1841587251" }),
	Map_CoreReactor = music("driving industrial/electronic battle loop, high energy", 0.5, { "122054437119612", "16527023337", "1837825257", "1839246774", "1846368080" }),
	FinalPhase = music("desperate final-phase boss loop: fast, intense, heavy drums", 0.55, { "88808485680832", "107986977620509", "1837853076", "9042370693" }),
	CollapsePhase = music("arena collapse (the last ~40 s, the ring closes): urgent, relentless loop", 0.55, { "128611309933897" }),
	VerdictBox = music("short frantic chiptune/8-bit bullet-hell loop (~7-15 s)", 0.55, { "6334012651", "117051223265396", "9048375035", "9048376021", "1841609664" }),
	Victory = music("short triumphant victory stinger (3-8 s, not looping)", 0.6, { "1844604574", "1841605720", "1844876242" }, false),
	Defeat = music("short somber defeat stinger (3-8 s, not looping)", 0.6, { "1846891028", "1841700487", "1836102253" }, false),
	-- Monster themes, picked by RoundState.MonsterKit (kit id): "Theme_<kit>" plays during the fight and
	-- "Theme_<kit>_Final" in the final phase (else the normal theme). When a theme has no candidates or every
	-- candidate failed, the map's track plays (SoundController music selection, SPEC §20).
	Theme_ClassicSans = music("Sans boss theme: fast, jazzy electronic loop, playful but deadly", 0.5, { "3745550364", "101598365847186", "98142057415884", "128830409645703", "3813059729", "137220025405002" }),
	Theme_ClassicSans_Final = music("Sans final phase: the same theme, harder and faster (optional)", 0.55, { "85617271533620", "5119156054", "5956427401", "137220025405002" }),
	Theme_FellSans = music("Fell Sans (Underfell): aggressive, distorted, heavy boss loop", 0.5, { "120838650095309", "101730223568557", "1837853076", "9043754347" }),
	Theme_FellSans_Final = music("Fell Sans final phase: harsher, faster, darker remix (optional)", 0.55, { "120928193831867", "137220025405002", "1837880957" }),
	Theme_EclipseSans = music("Eclipse Sans (original void AU): eerie cosmic dark-synth boss loop", 0.5, { "114505147154737", "9045683296", "9045934037", "1847456615" }),
	Theme_EclipseSans_Final = music("Eclipse Sans final phase: darker, glitchier, faster (optional)", 0.55, { "103167351125844", "78368445861935", "1837779548" }),

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
	Dash = sfx({ "624706518", "18388189427", "9126284289" }, 0.6, { 0.95, 1.08 }, true, "short air whoosh / swish (0.2-0.4 s)"),
	Teleport = sfx({ "6439289406", "8184327494" }, 0.6, { 0.95, 1.05 }, true, "quick blink / warp zap"),
	SlamLand = sfx({ "3923230963", "9113476681" }, 0.8, { 0.9, 1.0 }, true, "heavy ground slam thud"),

	-------------------------------------------------------------------------------------------- combat
	BlasterCharge = sfx({ "3140269034", "9069975578", "6645293593", "9125973984" }, 0.75, { 0.97, 1.03 }, true, "rising laser/energy charge-up (~0.6-1 s)"),
	BlasterFire = sfx({ "345052019", "332223043", "71716604434885", "9116231442" }, 0.9, { 0.95, 1.02 }, true, "big laser beam blast"),
	BoneRise = sfx({ "8862481350", "82284970220669" }, 0.55, { 0.92, 1.08 }, true, "quick rattling rise / wooden clack"),
	BoneHit = sfx({ "9120907213", "9113964719" }, 0.6, { 0.9, 1.1 }, true, "bony clack impact"),
	BoneThrow = sfx({ "4264104024", "9126284289" }, 0.5, { 0.95, 1.1 }, true, "light whoosh with a rattle"),
	Slash = sfx({ "9113213247", "623904185", "7140798795", "9119749822" }, 0.6, { 0.92, 1.08 }, true, "blade slash swish"),
	Punch = sfx({ "170014277", "9075325599", "9113511616" }, 0.65, { 0.9, 1.08 }, true, "punch impact"),
	Kick = sfx({ "9075327500", "9113511616" }, 0.6, { 0.9, 1.05 }, true, "kick impact"),
	Shot = sfx({ "4936708385", "5880986785", "171137312" }, 0.6, { 0.95, 1.05 }, true, "magic pistol shot / pew"),
	Explosion = sfx({ "9119964094", "1582829611", "9114363548" }, 0.8, { 0.92, 1.04 }, true, "small magical explosion"),
	Whoosh = sfx({ "624706518", "147722270", "9126284289" }, 0.5, { 0.9, 1.1 }, true, "generic whoosh"),
	Charge = sfx({ "9077531729", "9116386540" }, 0.5, { 0.98, 1.02 }, true, "magic charge loop/hum"),
	Cast = sfx({ "9119834605", "9116420445", "3356359494" }, 0.5, { 0.95, 1.05 }, true, "generic spell cast shimmer"),
	Hit = sfx({ "406913243", "410625063", "4735718618", "1471213022" }, 0.6, { 0.92, 1.08 }, true, "Undertale-like damage hit (crunchy blip)"),
	HitHeavy = sfx({ "4898185564", "3041191430", "9113964719" }, 0.75, { 0.9, 1.0 }, true, "heavy hit impact"),
	Crit = sfx("", 0.7, { 0.98, 1.04 }, true, "sharp critical hit ding/crack"),
	Hurt = sfx({ "1471213022", "4735718618" }, 0.6, { 0.95, 1.05 }, false, "player SOUL hurt blip (2D, local player only)"),
	Block = sfx({ "9116669896", "7171761940" }, 0.6, { 0.95, 1.05 }, true, "shield block clank"),
	Parry = sfx({ "7171761940", "9116669896", "9119752920" }, 0.8, { 1.0, 1.05 }, true, "bright metallic parry ring"),
	GuardBreak = sfx({ "5648455728", "170765215", "97721362", "9116546593" }, 0.8, { 0.95, 1.0 }, true, "shield shatter / break"),
	Dodge = sfx({ "7267892760", "5713085119", "624706518" }, 0.55, { 0.95, 1.1 }, true, "lazy side-step whoosh (monster MISS)"),
	Miss = sfx({ "7147896579", "7740697719" }, 0.45, { 1.0, 1.05 }, true, "light 'miss' blip"),
	Exhausted = sfx({ "1836245036" }, 0.6, nil, true, "tired exhale / deflate"),
	KR = sfx({ "4612384434" }, 0.35, { 1.0, 1.1 }, false, "tiny poison tick (2D, local player only)"),
	Heal = sfx({ "5008997031", "1655262564", "9038523649" }, 0.6, { 1.0, 1.05 }, true, "soft healing chime"),
	Shield = sfx({ "9125975059", "9116386540" }, 0.55, nil, true, "magic barrier hum-up"),
	Stun = sfx({ "266278159" }, 0.55, nil, true, "dizzy stars / stun ring"),
	Downed = sfx({ "129978441932803", "7521666726" }, 0.7, nil, true, "heart crack (SOUL cracked)"),
	SoulBreak = sfx({ "5193339590", "18786129148" }, 0.8, nil, true, "heart shatter (Undertale-like, original)"),
	Revive = sfx({ "130363919513154", "8807795651" }, 0.65, nil, true, "uplifting revive swell"),
	Kill = sfx({ "8864069181", "9086371917" }, 0.7, nil, false, "kill confirm sting (2D)"),
	HitConfirm = sfx({ "160432334" }, 0.5, { 1.0, 1.05 }, false, "2D hit-marker tick for the attacker (very short)"),
	BoneImpact = sfx({ "9120907213", "9120856267" }, 0.6, { 0.9, 1.1 }, true, "bone projectile hitting the ground"),
	Shockwave = sfx({ "9120769331", "9120705982", "3923230963" }, 0.75, { 0.92, 1.05 }, true, "ground shockwave boom / ring"),
	Implode = sfx({ "9125626784", "9126139357", "9113081793" }, 0.7, { 0.95, 1.05 }, true, "reverse whoosh into a dark implosion"),
	SoulAppear = sfx({ "7047238398", "9114365649", "9126072433" }, 0.55, { 1.0, 1.04 }, true, "SOUL heart appears: soft shimmer"),
	SoulCrack = sfx({ "129978441932803", "7521666726", "5193339590" }, 0.7, nil, true, "heart crack (SOUL cracked / downed)"),
	SoulShatter = sfx({ "5193339590", "18786129148", "18633296261", "7521666726" }, 0.8, nil, true, "heart shatters into pieces"),
	Dust = sfx({ "5416548293", "17615543215" }, 0.6, nil, true, "a monster turns to dust: soft sandy crumble"),
	-- kit-specific (Classic Sans client kit)
	BlasterSummon = sfx({ "9125517246", "9116410978" }, 0.75, { 0.97, 1.03 }, true, "Gaster Blaster materialising: deep magical whoom"),
	BlasterTick = sfx({ "4612384434", "9114479860", "9126109935" }, 0.45, { 1.0, 1.08 }, true, "short tick while a blaster locks on"),
	BoneSummon = sfx({ "8862481350", "18430580696", "9120856267" }, 0.7, { 0.95, 1.05 }, true, "a field of bones erupting from the ground"),
	SoulGrab = sfx({ "7149373060", "7128958209", "9126073011" }, 0.7, nil, true, "blue SOUL grab: magical whoosh + chime"),
	Slam = sfx({ "6866657635", "9113476681" }, 0.85, { 0.92, 1.0 }, true, "body slammed into the ground: heavy thud"),
	Shortcut = sfx({ "8184327494", "18388189427" }, 0.6, { 0.98, 1.04 }, true, "the monster takes a shortcut: quick blink"),
	BadTime = sfx({ "17230188731", "4836187667", "1841700487" }, 0.9, nil, true, "ominous low sting for the monster's ultimate"),
	-- kit-specific (Determination client kit)
	Lunge = sfx({ "12222208", "5685940877" }, 0.65, { 0.95, 1.05 }, true, "fast lunge whoosh + stab"),
	Counter = sfx({ "9119752920", "7171761940" }, 0.75, { 1.0, 1.05 }, true, "sharp counter-strike clang"),
	Afterimage = sfx({ "9126232612", "9114365649", "9116410978" }, 0.5, { 1.0, 1.1 }, true, "ghostly whoosh as an afterimage is left behind"),
	Determination = sfx({ "4613871802" }, 0.85, nil, true, "heroic DETERMINATION swell (human ultimate)"),
	Portal = sfx({ "915686003", "4624851154" }, 0.6, { 0.95, 1.05 }, true, "void portal open"),
	VoidHum = sfx({ "9112775175", "9125515917", "9113122524" }, 0.4, nil, true, "dark void hum loop"),
	Freeze = sfx({ "9039298484", "176399994" }, 0.55, nil, true, "ice crackle"),

	------------------------------------------------------------------------------------------ objectives
	SaveChannel = sfx({ "9125986205" }, 0.45, nil, true, "gentle rising shimmer loop (channeling a SAVE star)"),
	SaveLit = sfx({ "4613871802", "7485277857", "9126073011" }, 0.8, nil, false, "SAVE point lit: bright sparkle chime"),
	Surge = sfx({ "9039943266", "4729756264", "9125973984" }, 0.85, nil, false, "big heroic power-up swell"),
	FinalPhaseStinger = sfx({ "1841700487", "9116384799", "9120769331" }, 0.9, nil, false, "dramatic transformation hit + rumble"),
	Collapse = sfx({ "9114224217", "9113086365", "9125351660" }, 0.7, nil, false, "deep rumble / alarm, the arena collapses"),
	CollapseTick = sfx({ "1588058260", "9114478791" }, 0.4, nil, false, "void damage tick"),
	BoxOpen = sfx({ "4969296569", "12222200" }, 0.75, nil, false, "battle-box open whoosh + chime"),
	BoxClose = sfx({ "9126228631", "9114436019" }, 0.6, nil, false, "battle-box close"),
	RoundStart = sfx({ "2888333253", "7047238398", "4969296569", "123008168359289" }, 0.8, nil, false, "fight start stinger / gong"),
	Countdown = sfx({ "4969296907", "9126065684" }, 0.6, nil, false, "countdown tick"),
	Ding = sfx({ "9126073011", "7128958209", "12222253" }, 0.6, nil, false, "clear 'ding' (rewards, level up)"),
	LevelUp = sfx({ "2167611163", "6066818759", "2686079706" }, 0.8, nil, false, "LOVE/level up jingle"),

	------------------------------------------------------------------------------------------------ UI
	UiHover = ui({ "5053384572", "9125397532" }, 0.35, { 1.0, 1.04 }, "soft tick / menu move"),
	UiClick = ui({ "12221967", "6895079853", "9126109935" }, 0.45, nil, "button click"),
	UiConfirm = ui({ "5350464575", "762117042", "9125594507" }, 0.5, nil, "menu select / confirm"),
	UiBack = ui({ "9120156870", "6652808984" }, 0.45, nil, "menu back / cancel"),
	UiOpen = ui({ "12222200", "9126228631" }, 0.45, nil, "panel open whoosh"),
	UiClose = ui({ "9126228631", "12222200" }, 0.4, nil, "panel close"),
	UiError = ui({ "2200505478", "2130284653", "5521959695" }, 0.45, nil, "error buzz"),
	UiToggle = ui({ "5124453445", "9114479860" }, 0.4, nil, "toggle switch click"),
	UiReward = ui({ "9126072433", "9119834605", "12222253" }, 0.55, nil, "reward sparkle"),
	TextBlip = ui({ "5416666166", "5416573471", "103029640262152" }, 0.3, { 0.98, 1.02 }, "typewriter text blip (very short)"),
	SansTextBlip = ui({ "5417004822", "5416485881", "358280695", "928210219" }, 0.3, { 0.98, 1.02 }, "lower, rounder text blip for the monster's lines"),
	Notify = ui({ "9125397532", "2375539277", "7383525713" }, 0.4, nil, "notification pop"),
	Denied = ui({ "9113401879" }, 0.4, nil, "short 'not ready' buzz (ability on cooldown / no target)"),
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
	local finalDef = music("optional: this map's own final-phase loop", 0.55, {})
	finalDef.Fallback = "FinalPhase"
	SOUNDS[key .. "_Final"] = finalDef
end
-- OWNER: candidates for the generated entries above, e.g. SOUNDS["Map_VoidRift_Final"].Ids = { "1234567890" }

Audio.Sounds = SOUNDS
Audio.MapMusicKeys = MAP_MUSIC
Audio.ThemeKits = { "ClassicSans", "FellSans", "EclipseSans" }

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

-- The candidate ids of one SoundDef: {Id, ...Ids} normalized, without "" and without duplicates, in order.
function Audio.CandidatesOf(def: SoundDef?): { string }
	local out: { string } = {}
	if type(def) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	local function add(id: any)
		if type(id) ~= "string" then
			return
		end
		local norm = Audio.NormalizeId(id)
		if norm ~= "" and not seen[norm] then
			seen[norm] = true
			table.insert(out, norm)
		end
	end
	add(def.Id)
	local ids: any = def.Ids
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			add(id)
		end
	end
	return out
end

-- Candidates of that exact entry (aliases resolved, the Fallback chain is NOT followed).
function Audio.Candidates(name: string): { string }
	return Audio.CandidatesOf(Audio.Get(name))
end

-- true when the entry has at least one candidate id (a filled Ids list counts like a filled Id)
function Audio.IsFilled(def: SoundDef?): boolean
	if type(def) ~= "table" then
		return false
	end
	if type(def.Id) == "string" and def.Id ~= "" then
		return true
	end
	local ids: any = def.Ids
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			if type(id) == "string" and id ~= "" then
				return true
			end
		end
	end
	return false
end

-- Follows the Fallback chain to the first entry with a candidate id. Returns (nil, nil) when silent.
function Audio.Resolve(name: string): (SoundDef?, string?)
	local current: string? = if SOUNDS[name] then name else Audio.Aliases[name]
	local depth = 0
	while current ~= nil and depth < MAX_FALLBACK_DEPTH do
		local def = SOUNDS[current]
		if def == nil then
			return nil, nil
		end
		if Audio.IsFilled(def) then
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

-- "Theme_<kit>" (or "Theme_<kit>_Final" when `final`) when that entry exists, else nil.
function Audio.MonsterTheme(kitId: string?, final: boolean?): string?
	if type(kitId) ~= "string" or kitId == "" then
		return nil
	end
	local key = "Theme_" .. kitId .. (if final then "_Final" else "")
	return if SOUNDS[key] ~= nil then key else nil
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
		local ids: any = def.Ids
		if ids ~= nil then
			if type(ids) ~= "table" then
				bad(name, "Ids must be a list of ids, got " .. type(ids))
			else
				local count = 0
				for _ in ids do
					count += 1
				end
				if count ~= #ids then
					bad(name, 'Ids must be a plain list { "id", "id" } (no named keys / holes)')
				end
				for i, id in ipairs(ids) do
					if not validId(id) then
						bad(name, ("bad Ids[%d] %s"):format(i, tostring(id)))
					end
				end
			end
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
