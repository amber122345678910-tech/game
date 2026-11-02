--!strict
-- SoundController (client, SPEC §20, Priority 10): plays named sounds from Shared/Audio.luau with pooling, three
-- SoundGroups (SV_Music / SV_SFX / SV_UI under SoundService) scaled by the player's MusicVolume / SfxVolume settings,
-- two-deck music crossfades with ducking, automatic checking of every audio id and automatic music selection.
--
-- Audio ids: every entry has candidates (Audio.Candidates = {Id, ...Ids}, best first). Each id is checked with
-- ContentProvider:PreloadAsync({sound}, callback) (which also downloads it into the cache): AssetFetchStatus.Success =
-- good; Failure / TimedOut / any other final status / no answer in time = bad; a Sound that reports IsLoaded with
-- TimeLength 0 (or a Sound / music deck that never loads its id) = bad too. Every bad id is reported once in the
-- Output window:
--     [Sound] audio id failed to load: <id> (<entry>)
-- Built-in rbxasset:// files are trusted without a probe. Per-id state: pending / good / bad.
--   Time allowed: PROBE_TIMEOUT s for SFX / UI ids; music ids (big files on a phone) MUSIC_PROBE_TIMEOUT s, extended
--     by MUSIC_PROBE_EXTEND s while the engine still reports the download as Loading, up to MUSIC_PROBE_MAX s.
--   A bad verdict is not final unless the asset is empty: a failed / timed-out / never-loaded id is checked again in
--     the background (RETRY_AFTER s later, doubling up to RETRY_MAX) when its entry is wanted again and it ranks
--     before the candidate in use (or the entry is dead). It stays bad until that check answers Success; a late
--     Success never switches a track that is already playing (the next start of that track uses it).
--   SFX / UI: play the first candidate that is not known bad (an untested one optimistically while its probe runs;
--     short files are also probed in a small background batch after Start, one at a time while a music id is being
--     downloaded); when it turns bad, the pool switches to the next candidate.
--   Music: the requested track starts on its first GOOD candidate (probed in order, never two candidates of one entry
--     at once), then the usual crossfade. While it is still being checked, the track that plays goes on only if it is
--     an acceptable stand-in for the new request (MusicChoices: e.g. the normal boss theme while the Phase 2 theme
--     loads, the arena track while the box track loads); else the first stand-in that is ready plays; else the music
--     fades out (never a stale track: the box loop after the box, a stinger after the round, the menu track...).
--   Warm-up: music that will be needed soon is checked (= downloaded) in the background, one id at a time and never
--     while a track the player is waiting for downloads: at Start the title / lobby / box / shop tracks, and for a
--     round the fight track, the box track, the Phase 2 track, CollapsePhase, Victory and Defeat (PrefetchOrder), so
--     those switches are instant.
--   A looped track that comes back within RESUME_WINDOW s (the boss theme after a Verdict Box, the lobby after the
--     shop) resumes where it was (the box track itself always starts from the top).
--   An entry whose candidates all failed is "dead": plays follow its Fallback chain, and the automatic music
--   selection moves on to its next option as soon as a key dies.
-- Automatic music selection (MusicFor, pure; picks the first USABLE key = a candidate along its Fallback chain that
-- is not dead):
--   Waiting / Intermission -> "Lobby";
--   Intro / Round / Collapse -> (Collapse only: CollapsePhase) Theme_<RoundState.MonsterKit>, then the map's track (Maps/Registry Music key);
--     while RoundState.FinalPhase: Theme_<kit>_Final, Theme_<kit>, "<map>_Final" (-> FinalPhase), FinalPhase, then
--     the map's track (nothing usable -> the map's track, silent);
--   Ending -> "Victory" / "Defeat" stinger (from RoundEnd; a stinger that has played is not restarted by later
--     refreshes);
--   InputController context "Box" (the local player is inside the Verdict Box) -> "VerdictBox";
--   a local player who is not a round participant (StateController.Role() "Lobby": waiting in the lobby during a
--   round, mid-match joiners) keeps "Lobby" in every phase (no arena track, no Victory/Defeat stinger);
--   PreviewMusic(key) (admin test) beats SetMusicOverride(key) (title screen, Style Lab...) beats everything else.
-- Entries without candidates play nothing and never warn.
-- Voices: one pool per resolved entry (max Audio MaxInstances, oldest voice is stolen when full); 3D sounds at a
-- Vector3 use pooled Attachments under workspace.Terrain; at a BasePart / Attachment the voice is parented there
-- and comes back to the pool when it ends. Plays of one entry closer than MinInterval are dropped (hit spam).
--
-- API (SPEC §20)
--   SoundController.Play(name, at?: Vector3|CFrame|BasePart|Attachment|Model, opts?) -> Sound?
--       opts: { Volume: number? (x entry volume), Pitch: number? (exact PlaybackSpeed), Looped: boolean?,
--               Delay: number? (schedules the play; returns nil), StartTime: number?, Force2D: boolean? }
--       The returned Sound belongs to the pool: never Destroy it; stop it with SoundController.Stop(sound).
--   SoundController.PlayMusic(key, fadeTime?)        crossfade (automatic selection may change it later;
--                                                    use SetMusicOverride for a sticky choice)
--   SoundController.StopMusic(fadeTime?)
--   SoundController.SetVolumes(music, sfx)           0..1 multipliers (settings call this automatically)
--   SoundController.Register(name, soundId | {ids}, opts?)   runtime entry / id override (opts = SoundDef fields)
--   SoundController.ActiveId(name) -> string?        the id `name` uses now (music: the one on the playing deck;
--                                                    while Status is "pending" the id that is being checked)
--   SoundController.Status(name) -> "ok" | "pending" | "dead" | "empty"     along the Fallback chain:
--                                                    ok = a good id; pending = being checked / not checked yet;
--                                                    dead = every candidate failed; empty = no candidates
--   SoundController.PreviewMusic(key?)               sticky test override (admin panel); nil = automatic again
-- Extras
--   SoundController.Stop(sound, fadeTime?) ; StopAll(name)
--   SoundController.SetMusicOverride(key?, fadeTime?) ; CurrentMusic() -> string? ; MusicChanged: Signal(key?)
--   SoundController.NowPlaying() -> { Key, Entry, Id, Status, Index, Count, Preview, Playing }   admin status line:
--       Key = requested track, Entry = Audio entry that supplies it, Id = id in use (Index of Count candidates)
--   SoundController.IdState(id) -> "good" | "bad" | "pending" | nil (not checked yet)
--   SoundController.Duck(amount 0..1, duration, fadeTime?)   temporarily lowers music (big moments)
--   SoundController.Resolve(name) -> (SoundDef?, string?)    first live entry along the Fallback chain
--   SoundController.Groups() -> { Music: SoundGroup?, SFX: SoundGroup?, UI: SoundGroup? }
--   SoundController.Prewarm(name)       checks (downloads) an entry's candidate ahead of time in the background, the
--                                       next one after a bad one; music one id at a time, after the first track and
--                                       what is already queued. Safe to call repeatedly.
--   SoundController.BOX_FADE_IN / BOX_FADE_OUT   music fades into / out of the Verdict Box ("Box" context)
-- Pure helpers (Lune tests)
--   SoundController.PickCandidate(candidates, stateOf) -> (id?, status)   stateOf(id) -> "good"|"bad"|"pending"|nil
--   SoundController.ResolveChain(name, defOf, stateOf, candidatesOf?) -> (entry?, id?, status)
--   SoundController.ArenaMusicOrder(round) -> {string}                     Intro / Round / Collapse preference order
--   SoundController.MusicFor(round, ctx) -> string?   ctx = { Override, Box, Stinger, Current, Playing (the key on
--                                                    the playing deck), Participant (false = lobby viewer),
--                                                    Usable(key) -> boolean (default: the key has candidates in
--                                                    Shared/Audio) }
--   SoundController.MusicChoices(round, ctx) -> {string}   MusicFor's answer first, then the stand-ins accepted
--                                                    while it is still being checked (the context it sits on:
--                                                    override -> box -> phase track(s))
--   SoundController.PrefetchOrder(round, ctx) -> {string}  music a round will soon need, most urgent first
--                                                    (ctx = { Participant, Usable }; nothing outside a round)

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Registry = require(Shared:WaitForChild("Maps"):WaitForChild("Registry"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type SoundDef = Audio.SoundDef
export type Status = "ok" | "pending" | "dead" | "empty"
export type IdState = "good" | "bad" | "pending"

local SoundController = {}
SoundController.Priority = 10
SoundController.MusicChanged = Signal.new()

SoundController.DEFAULT_MUSIC_FADE = 1.6
SoundController.MAX_EMITTERS = 40
SoundController.PROBE_TIMEOUT = 10 -- s without a final answer from PreloadAsync = bad id (SFX / UI: short files)
SoundController.MUSIC_PROBE_TIMEOUT = 20 -- s for a music id (a 3-5 MB download on a phone)...
SoundController.MUSIC_PROBE_EXTEND = 10 -- ...plus this, again and again, while the engine still reports it Loading...
SoundController.MUSIC_PROBE_MAX = 60 -- ...up to this in total
SoundController.LOAD_TIMEOUT = 15 -- s a music deck may take to load a checked id before that id counts as bad
SoundController.PROBE_BATCH = 3 -- concurrent background probes (SFX / UI)
SoundController.PROBE_BATCH_DELAY = 4 -- s after Start before the background batch begins
SoundController.RETRY_AFTER = 60 -- s before a failed / timed-out id may be checked again (in the background)...
SoundController.RETRY_MAX = 600 -- ...doubling after every failed check, up to this
SoundController.RESUME_WINDOW = 60 -- s: a looped track that comes back this soon resumes where it was
-- Verdict Box: the box track starts on the first frame of the victim's pull-in (its ids are warmed up at Start), so
-- the switch INTO the box is a short fade; the way back out keeps a normal one.
SoundController.BOX_FADE_IN = 0.15
SoundController.BOX_FADE_OUT = 1.0

-- music warmed up at Start (after the first track): the title, the lobby, the Verdict Box, the shop
local START_MUSIC = { "Menu", "Lobby", "VerdictBox", "Shop" }
-- tracks that always start from the top (each box is a new fight)
local RESTART_KEYS: { [string]: boolean } = { VerdictBox = true }

export type PlayOpts = {
	Volume: number?,
	Pitch: number?,
	Looped: boolean?,
	Delay: number?,
	StartTime: number?,
	Force2D: boolean?,
}

type Voice = {
	Sound: Sound,
	Busy: boolean,
	Started: number,
	Emitter: Attachment?,
	Pool: Pool,
	Dead: boolean,
}

type Pool = {
	Name: string,
	Def: SoundDef,
	Id: string,
	Voices: { Voice },
	LastPlay: number,
	WatchedId: string?, -- the id whose first play is watched for a load that never happens
}

type Deck = {
	Sound: Sound,
	Key: string?, -- requested music key this deck plays
	Entry: string?, -- Audio entry that supplied the id (after the Fallback chain)
	Id: string?, -- content id loaded on the deck
	Current: number,
	Target: number,
	Rate: number,
	StartedAt: number,
	Checked: boolean, -- the load check (IsLoaded with TimeLength > 0) is done for this id
	Resume: number?, -- TimePosition to make sure of once the id has loaded (a resumed track)
}

local custom: { [string]: SoundDef } = {}
local pools: { [string]: Pool } = {}
local voiceBySound: { [Sound]: Voice } = setmetatable({}, { __mode = "k" }) :: any
local groups: { [string]: SoundGroup } = {}
local poolFolder: Folder? = nil
local rng: Random? = nil
local volumes = { Music = 1, SFX = 1 }

local decks: { Deck } = {}
local activeDeck = 1
local requestedMusic: string? = nil
local requestedChoices: { string } = {} -- requestedMusic + the stand-ins accepted while it is being checked
local requestedFade: number? = nil
local resumeAt: { [string]: { Position: number, At: number } } = {} -- looped ids stopped mid-play
local musicOverride: string? = nil
local previewKey: string? = nil
local stingerKey: string? = nil
local boxActive = false
local duckLevel, duckTarget, duckUntil, duckRate = 1, 1, 0, 4
local faderConnection: RBXScriptConnection? = nil
local started = false

-- audio id checks
local TIMEOUT_REASON = "no answer (timed out)"
local EMPTY_REASON = "empty audio (TimeLength 0)"
local idState: { [string]: IdState } = {}
local idEntry: { [string]: string } = {} -- the first entry that used an id (for messages)
local idBadReason: { [string]: string } = {}
local idWarned: { [string]: boolean } = {}
local idRetryAt: { [string]: number } = {} -- bad ids that may be checked again from this os.clock() on (nil = never)
local idFailures: { [string]: number } = {} -- failed checks per id (retry backoff)
local idRetrying: { [string]: boolean } = {} -- bad ids being checked again right now (they stay bad until Success)
local probeQueue: { string } = {}
local probeQueued: { [string]: boolean } = {}
local backgroundProbes = 0
local musicProbes: { [string]: boolean } = {} -- music ids being checked right now (big downloads)
local musicQueue: { string } = {} -- music entries to warm up, most urgent first
local musicQueued: { [string]: boolean } = {}
local refreshQueued = false
local warmupOpen = false -- the background music warm-up starts once the first track has been asked for
type CacheEntry = { Id: string, Ids: any, List: { string } }
local candidateCache: { [SoundDef]: CacheEntry } = setmetatable({}, { __mode = "k" }) :: any

-------------------------------------------------------------------------------------------- lazy deps

local controllerCache: { [string]: any } = {}
local function controller(name: string): any?
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local folder = script.Parent
	local module = folder and folder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			controllerCache[name] = result
			return result
		end
	end
	controllerCache[name] = false
	return nil
end

----------------------------------------------------------------------------------- candidates (pure)

-- Pure: the candidate to use from one entry's list. stateOf(id) -> "good" | "bad" | "pending" | nil (not checked).
-- Strict priority: the first candidate that is not known bad decides ("ok" when it is good, else "pending").
function SoundController.PickCandidate(candidates: { string }, stateOf: (string) -> string?): (string?, Status)
	if #candidates == 0 then
		return nil, "empty"
	end
	for _, id in candidates do
		local state = stateOf(id)
		if state == "good" then
			return id, "ok"
		elseif state ~= "bad" then
			return id, "pending"
		end
	end
	return nil, "dead"
end

-- Pure: walks `name`'s Fallback chain to the first entry with a usable candidate. defFn(name) -> SoundDef?,
-- listFn(def) -> {string} (default Audio.CandidatesOf). Returns (entry, id, "ok" | "pending"), else
-- (nil, nil, "dead") when an entry on the chain had candidates that all failed, or (nil, nil, "empty").
function SoundController.ResolveChain(
	name: string,
	defFn: (string) -> SoundDef?,
	stateFn: (string) -> string?,
	listFn: ((SoundDef) -> { string })?
): (string?, string?, Status)
	local candidatesFor = listFn or Audio.CandidatesOf
	local seen: { [string]: boolean } = {}
	local sawDead = false
	local current: string? = name
	while current ~= nil and not seen[current] do
		seen[current] = true
		local def = defFn(current)
		if def == nil then
			break
		end
		local id, status = SoundController.PickCandidate(candidatesFor(def), stateFn)
		if status == "ok" or status == "pending" then
			return current, id, status
		elseif status == "dead" then
			sawDead = true
		end
		current = def.Fallback
	end
	return nil, nil, if sawDead then "dead" else "empty"
end

--------------------------------------------------------------------------------- candidates (runtime)

local function isBuiltin(id: string): boolean
	return string.sub(id, 1, 11) == "rbxasset://"
end

local function stateOf(id: string): IdState?
	local state = idState[id]
	if state == nil and isBuiltin(id) then
		return "good" -- files that ship with every client
	end
	return state
end

local function candidatesOf(def: SoundDef): { string }
	local cached = candidateCache[def]
	if cached and cached.Id == def.Id and cached.Ids == def.Ids then
		return cached.List
	end
	local list = Audio.CandidatesOf(def)
	candidateCache[def] = { Id = def.Id, Ids = def.Ids, List = list }
	return list
end

local function defOf(name: string): SoundDef?
	return custom[name] or Audio.Get(name)
end

local function canonical(name: string): string
	if custom[name] ~= nil or Audio.Sounds[name] ~= nil then
		return name
	end
	return Audio.Aliases[name] or name
end

local function resolveLive(name: string): (string?, string?, Status)
	return SoundController.ResolveChain(canonical(name), defOf, stateOf, candidatesOf)
end

local function usableKey(key: string): boolean
	local _, _, status = resolveLive(key)
	return status == "ok" or status == "pending"
end

--------------------------------------------------------------------------------------------- registry

function SoundController.Resolve(name: string): (SoundDef?, string?)
	if type(name) ~= "string" or name == "" then
		return nil, nil
	end
	local entry = resolveLive(name)
	if entry == nil then
		return nil, nil
	end
	return defOf(entry), entry
end

function SoundController.Status(name: string): Status
	if type(name) ~= "string" or name == "" then
		return "empty"
	end
	local _, _, status = resolveLive(name)
	return status
end

function SoundController.IdState(id: string): IdState?
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return stateOf(Audio.NormalizeId(id))
end

----------------------------------------------------------------------------------------- id probing

local onIdChanged: (string) -> () -- (forward) pools + music react to a new id state
local pumpProbes: () -> () -- (forward) starts queued background probes
local pumpMusic: () -> () -- (forward) starts the next music warm-up
local prefetchMusic: (string, boolean?) -> () -- (forward) queues a music entry for the warm-up
local scheduleMusicRefresh: () -> () -- (forward) re-runs the music selection on the next resumption point

local function isMusicEntry(name: string?): boolean
	local def = if name ~= nil then defOf(name) else nil
	return def ~= nil and def.Group == "Music"
end

local function fetchStatus(id: string): Enum.AssetFetchStatus?
	local ok, status = pcall(function(): Enum.AssetFetchStatus
		return ContentProvider:GetAssetFetchStatus(id)
	end)
	return if ok then status else nil
end

local function markBad(id: string, reason: string?)
	local why = reason or "failed"
	local failures = (idFailures[id] or 0) + 1
	idFailures[id] = failures
	-- an empty asset is broken for good; anything else (a failure, no answer, a load that never finished) may be a bad
	-- connection: the id may be checked again later (backoff doubles with every failed check)
	local wait = math.min(SoundController.RETRY_AFTER * 2 ^ (failures - 1), SoundController.RETRY_MAX)
	idRetryAt[id] = if why == EMPTY_REASON then nil else os.clock() + wait
	if why ~= EMPTY_REASON and isMusicEntry(idEntry[id]) then
		-- the music selection looks again when the re-check is due (a dead track that is wanted gets it then)
		task.delay(wait + 0.05, function()
			scheduleMusicRefresh()
		end)
	end
	if idState[id] == "bad" then
		idBadReason[id] = why -- a failed re-check: still bad, nothing switches
		return
	end
	idState[id] = "bad"
	idBadReason[id] = why
	if not idWarned[id] then
		idWarned[id] = true
		local suffix = if why ~= "" then " - " .. why else ""
		warn(("[Sound] audio id failed to load: %s (%s)%s"):format(id, idEntry[id] or "?", suffix))
	end
	onIdChanged(id)
end

local function markGood(id: string)
	local before = idState[id]
	if before == "good" then
		return
	end
	idState[id] = "good"
	idBadReason[id] = nil
	idRetryAt[id] = nil
	if before == "bad" then
		print(("[Sound] audio id loaded after all (slow network): %s (%s)"):format(id, idEntry[id] or "?"))
	end
	onIdChanged(id)
end

-- queues the id `name` would use next for a background probe (SFX / UI)
local function queueEntry(name: string)
	local entry, id, status = resolveLive(name)
	if status == "pending" and entry ~= nil and id ~= nil and idState[id] == nil and not probeQueued[id] then
		probeQueued[id] = true
		if idEntry[id] == nil then
			idEntry[id] = entry
		end
		table.insert(probeQueue, id)
	end
end

-- Success / Failure / TimedOut (not None / Loading / nil)
local function isFinalStatus(status: Enum.AssetFetchStatus?): boolean
	return status ~= nil and status ~= Enum.AssetFetchStatus.None and status ~= Enum.AssetFetchStatus.Loading
end

type ProbeOpts = {
	batch: boolean?, -- one of the SFX / UI background batch slots
	warm: string?, -- a music warm-up of this entry (its next candidate is queued after a bad answer)
	retry: boolean?, -- a background re-check of a bad id (it stays bad until Success)
}

-- Checks one id: PreloadAsync on a throwaway Sound in its own thread, with a timeout. Never yields the caller. An id
-- is checked once, except for the background re-checks of a bad id (`retry`) that retryDue starts.
local function startProbe(id: string, entry: string?, opts: ProbeOpts?)
	local o: ProbeOpts = opts or {}
	if entry ~= nil and idEntry[id] == nil then
		idEntry[id] = entry
	end
	if o.retry then
		if idState[id] ~= "bad" or idRetrying[id] then
			return
		end
		idRetrying[id] = true
	else
		if idState[id] ~= nil then
			return
		end
		if isBuiltin(id) then
			idState[id] = "good"
			return
		end
		idState[id] = "pending"
	end
	local music = isMusicEntry(entry or idEntry[id])
	if music then
		musicProbes[id] = true
	end
	local batch = o.batch == true
	if batch then
		backgroundProbes += 1
	end
	local started = os.clock()
	local done = false
	local function finish(good: boolean, reason: string?)
		if done then
			-- an answer after the timeout: a slow load that did succeed counts after all
			if good and idState[id] == "bad" and idBadReason[id] == TIMEOUT_REASON then
				markGood(id)
			end
			return
		end
		done = true
		if batch then
			backgroundProbes -= 1
		end
		musicProbes[id] = nil
		idRetrying[id] = nil
		if good then
			markGood(id)
		else
			markBad(id, reason)
		end
		if not good and not o.retry then
			if o.warm ~= nil then
				prefetchMusic(o.warm, true) -- that entry's next candidate, first in line
			elseif batch and idEntry[id] ~= nil then
				queueEntry(idEntry[id]) -- that entry's next candidate
			end
		end
		pumpMusic()
		pumpProbes()
	end
	-- no final answer in time = bad (and checked again later); a music download the engine still reports as Loading
	-- gets more time, up to MUSIC_PROBE_MAX
	local function onTimeout()
		if done then
			return
		end
		local left = SoundController.MUSIC_PROBE_MAX - (os.clock() - started)
		if music and left > 0.05 and fetchStatus(id) == Enum.AssetFetchStatus.Loading then
			task.delay(math.min(SoundController.MUSIC_PROBE_EXTEND, left), onTimeout)
			return
		end
		finish(false, TIMEOUT_REASON)
	end
	task.delay(if music then SoundController.MUSIC_PROBE_TIMEOUT else SoundController.PROBE_TIMEOUT, onTimeout)
	task.spawn(function()
		local probe: Sound? = nil
		local result: Enum.AssetFetchStatus? = nil
		local ok, err = pcall(function()
			local sound = Instance.new("Sound")
			sound.Name = "SV_AudioProbe"
			sound.SoundId = id
			probe = sound
			ContentProvider:PreloadAsync({ sound }, function(_contentId: string, status: Enum.AssetFetchStatus)
				result = status
			end)
		end)
		if not ok then
			-- the check itself failed (not the asset): never keep audio silent because of that (a music deck that
			-- then does not load is still caught by the deck load check)
			warn(
				("[Sound] could not check audio id %s (%s), playing it unchecked: %s"):format(
					id,
					idEntry[id] or "?",
					tostring(err)
				)
			)
			finish(true)
		else
			-- no final status from the callback yet: ask ContentProvider until it has one (or the timeout hits)
			while not done and not isFinalStatus(result) do
				local status = fetchStatus(id)
				if isFinalStatus(status) then
					result = status
					break
				end
				task.wait(0.5)
			end
			local final = result
			if final == Enum.AssetFetchStatus.Success then
				local sound = probe
				if sound ~= nil and sound.IsLoaded and sound.TimeLength <= 0 then
					finish(false, EMPTY_REASON)
				else
					finish(true)
				end
			elseif final ~= nil and isFinalStatus(final) then
				finish(false, "status " .. final.Name) -- Failure, TimedOut, ...
			end
		end
		local sound = probe
		if sound ~= nil then
			pcall(function()
				sound:Destroy()
			end)
		end
	end)
end

-- Starts a background re-check of the first bad id of `name` (along its Fallback chain) whose retry time has come,
-- when it ranks before the candidate in use or the entry is dead. One per call; a music id only when no other music
-- download runs. The id stays bad until the check answers Success: nothing switches meanwhile.
local function retryDue(name: string)
	local now = os.clock()
	local seen: { [string]: boolean } = {}
	local current: string? = canonical(name)
	while current ~= nil and not seen[current] do
		seen[current] = true
		local def = defOf(current)
		if def == nil then
			return
		end
		for _, id in candidatesOf(def) do
			if stateOf(id) ~= "bad" then
				return -- this candidate is in use (or being checked): nothing better to re-check
			end
			local at = idRetryAt[id]
			if at ~= nil and now >= at and not idRetrying[id] then
				if def.Group == "Music" and next(musicProbes) ~= nil then
					return -- one music download at a time: next time
				end
				startProbe(id, current, { retry = true })
				return
			end
		end
		current = def.Fallback
	end
end

pumpProbes = function()
	-- a music download in flight gets the bandwidth: the short-sound batch then checks one id at a time
	local limit = if next(musicProbes) ~= nil then 1 else SoundController.PROBE_BATCH
	while backgroundProbes < limit and #probeQueue > 0 do
		local id = table.remove(probeQueue, 1) :: string
		if idState[id] == nil then
			startProbe(id, nil, { batch = true })
		end
	end
end

-- Queues a music entry for the warm-up (`urgent`: first in line). Entries already queued are not duplicated.
prefetchMusic = function(name: string, urgent: boolean?)
	local key = canonical(name)
	if not isMusicEntry(key) then
		return
	end
	if musicQueued[key] then
		if not urgent then
			return
		end
		local at = table.find(musicQueue, key)
		if at then
			table.remove(musicQueue, at)
		end
	end
	musicQueued[key] = true
	if urgent then
		table.insert(musicQueue, 1, key)
	else
		table.insert(musicQueue, key)
	end
end

-- several entries, most urgent first; `front` = ahead of everything already queued (keeping this order)
local function prefetchList(names: { string }, front: boolean?)
	if front then
		for i = #names, 1, -1 do
			prefetchMusic(names[i], true)
		end
	else
		for _, name in names do
			prefetchMusic(name)
		end
	end
end

-- The music warm-up: one id at a time, and only while no music id is being checked (the track the player waits for
-- always has the connection to itself). A bad answer queues the entry's next candidate; a dead entry gets a re-check
-- when one is due.
pumpMusic = function()
	if not started or not warmupOpen then
		return
	end
	while next(musicProbes) == nil and #musicQueue > 0 do
		local key = table.remove(musicQueue, 1) :: string
		musicQueued[key] = nil
		local entry, id, status = resolveLive(key)
		if status == "pending" and entry ~= nil and id ~= nil and idState[id] == nil then
			startProbe(id, entry, { warm = key })
		elseif status == "dead" then
			retryDue(key)
		end
	end
end

-- background batch after Start: the first untested candidate of every SFX / UI entry (short files)
local function probeShortSounds()
	for _, name in Audio.Names() do
		local def = Audio.Sounds[name]
		if def ~= nil and def.Group ~= "Music" then
			queueEntry(name)
		end
	end
	for name, def in custom do
		if def.Group ~= "Music" then
			queueEntry(name)
		end
	end
	pumpProbes()
end

----------------------------------------------------------------------------------------------- groups

local function ensureGroups()
	local function group(name: string, groupKey: string): SoundGroup
		local existing = SoundService:FindFirstChild(name)
		if existing and existing:IsA("SoundGroup") then
			groups[groupKey] = existing
			return existing
		end
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = (Audio.Groups :: any)[groupKey].Volume
		g.Parent = SoundService
		groups[groupKey] = g
		return g
	end
	group("SV_Music", "Music")
	group("SV_SFX", "SFX")
	group("SV_UI", "UI")
	if poolFolder == nil then
		local folder = Instance.new("Folder")
		folder.Name = "SV_Sounds"
		folder.Parent = SoundService
		poolFolder = folder
	end
end

local function applyGroupVolumes()
	local music = groups.Music
	if music then
		music.Volume = Audio.Groups.Music.Volume * volumes.Music
	end
	local sfxGroup = groups.SFX
	if sfxGroup then
		sfxGroup.Volume = Audio.Groups.SFX.Volume * volumes.SFX
	end
	local uiGroup = groups.UI
	if uiGroup then
		uiGroup.Volume = Audio.Groups.UI.Volume * volumes.SFX
	end
end

function SoundController.SetVolumes(music: number?, sfx: number?)
	if type(music) == "number" and music == music then
		volumes.Music = math.clamp(music, 0, 1)
	end
	if type(sfx) == "number" and sfx == sfx then
		volumes.SFX = math.clamp(sfx, 0, 1)
	end
	applyGroupVolumes()
end

function SoundController.Groups(): { [string]: SoundGroup }
	return groups
end

------------------------------------------------------------------------------------------------ voices

local function configureSound(sound: Sound, def: SoundDef, id: string)
	sound.SoundId = id
	sound.Volume = def.Volume
	sound.Looped = def.Looped == true
	local rollOff = def.RollOff or Audio.DEFAULT_ROLLOFF
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = rollOff[1]
	sound.RollOffMaxDistance = rollOff[2]
	sound.SoundGroup = groups[def.Group] or groups.SFX
end

-- a Sound that reports IsLoaded with TimeLength 0 carries a broken / empty asset (`id` = the id it should hold)
local function checkLoaded(sound: Sound, id: string)
	if
		id ~= ""
		and sound.SoundId == id
		and sound.IsLoaded
		and sound.TimeLength <= 0
		and idState[id] ~= "bad"
		and not isBuiltin(id)
	then
		markBad(id, EMPTY_REASON)
	end
end

local function returnHome(voice: Voice)
	local folder = poolFolder
	if folder == nil or voice.Dead then
		return
	end
	local sound = voice.Sound
	if sound.Parent ~= folder then
		local ok = pcall(function()
			sound.Parent = folder
		end)
		if not ok then
			voice.Dead = true
		end
	end
end

local function newVoice(pool: Pool): Voice
	local sound = Instance.new("Sound")
	sound.Name = pool.Name
	configureSound(sound, pool.Def, pool.Id)
	local voice: Voice = {
		Sound = sound,
		Busy = false,
		Started = 0,
		Emitter = nil,
		Pool = pool,
		Dead = false,
	}
	sound.Ended:Connect(function()
		voice.Busy = false
		returnHome(voice)
	end)
	sound.Destroying:Connect(function()
		voice.Dead = true
	end)
	sound.Loaded:Connect(function()
		checkLoaded(sound, voice.Pool.Id)
	end)
	sound.Parent = poolFolder
	voiceBySound[sound] = voice
	return voice
end

local function setPoolId(pool: Pool, id: string)
	if pool.Id == id then
		return
	end
	pool.Id = id
	for _, voice in pool.Voices do
		if not voice.Dead then
			pcall(function()
				voice.Sound.SoundId = id
			end)
		end
	end
end

local function dropPool(name: string)
	local pool = pools[name]
	if pool == nil then
		return
	end
	pools[name] = nil
	for _, voice in pool.Voices do
		voice.Dead = true
		pcall(function()
			voice.Sound:Destroy()
			if voice.Emitter then
				voice.Emitter:Destroy()
			end
		end)
	end
end

local function getPool(name: string, def: SoundDef, id: string): Pool
	local pool = pools[name]
	if pool == nil or pool.Def ~= def then
		pool = {
			Name = name,
			Def = def,
			Id = id,
			Voices = {},
			LastPlay = -math.huge,
			WatchedId = nil,
		}
		pools[name] = pool
	elseif pool.Id ~= id then
		setPoolId(pool, id)
	end
	return pool
end

local function voiceFree(voice: Voice, now: number): boolean
	if not voice.Busy then
		return true
	end
	local sound = voice.Sound
	if sound.Looped then
		return false
	end
	-- safety net: Ended never fired (sound loading failed, parent destroyed...)
	local length = sound.TimeLength
	local speed = math.max(sound.PlaybackSpeed, 0.05)
	local maxTime = if length > 0 then length / speed + 0.5 else 8
	return now - voice.Started > maxTime
end

local function acquire(pool: Pool, now: number): Voice
	local voices = pool.Voices
	-- purge voices whose Sound died with a destroyed parent
	for i = #voices, 1, -1 do
		local v = voices[i]
		if v.Dead or v.Sound.Parent == nil then
			v.Dead = true
			if v.Emitter then
				pcall(function()
					(v.Emitter :: Attachment):Destroy()
				end)
			end
			table.remove(voices, i)
		end
	end
	local oldest: Voice? = nil
	for _, v in voices do
		if voiceFree(v, now) then
			return v
		end
		if not v.Sound.Looped and (oldest == nil or v.Started < oldest.Started) then
			oldest = v
		end
	end
	local maxInstances = pool.Def.MaxInstances or Audio.DEFAULT_MAX_INSTANCES
	if #voices < maxInstances or oldest == nil then
		local v = newVoice(pool)
		table.insert(voices, v)
		return v
	end
	oldest.Sound:Stop()
	return oldest
end

local function emitterFor(voice: Voice, position: Vector3): Attachment?
	local emitter = voice.Emitter
	if emitter == nil or emitter.Parent == nil then
		local terrain = workspace.Terrain
		if terrain == nil then
			return nil
		end
		local a = Instance.new("Attachment")
		a.Name = "SV_SoundEmitter"
		a.Parent = terrain
		voice.Emitter = a
		emitter = a
	end
	assert(emitter)
	emitter.WorldCFrame = CFrame.new(position)
	return emitter
end

local function playNow(name: string, at: any?, opts: PlayOpts?): Sound?
	retryDue(name) -- a failed better candidate (or a dead entry) may be checked again, in the background
	local entry, id, status = resolveLive(name)
	if entry == nil or id == nil then
		return nil
	end
	local def = defOf(entry)
	if def == nil then
		return nil
	end
	if poolFolder == nil then
		ensureGroups()
	end
	local now = os.clock()
	local pool = getPool(entry, def, id)
	local minInterval = def.MinInterval or Audio.DEFAULT_MIN_INTERVAL
	if now - pool.LastPlay < minInterval then
		return nil
	end
	pool.LastPlay = now
	local voice = acquire(pool, now)
	local sound = voice.Sound

	-- placement: 3D only for spatial entries with a target
	local parent: Instance? = poolFolder
	local o: PlayOpts = opts or {}
	if def.Spatial and at ~= nil and not o.Force2D then
		local kind = typeof(at)
		if kind == "CFrame" then
			at = (at :: CFrame).Position
			kind = "Vector3"
		elseif kind == "Instance" and (at :: Instance):IsA("Model") then
			at = (at :: Model).PrimaryPart
			kind = if at ~= nil then "Instance" else "nil"
		end
		if kind == "Vector3" then
			parent = emitterFor(voice, at :: Vector3) or poolFolder
		elseif kind == "Instance" and ((at :: Instance):IsA("BasePart") or (at :: Instance):IsA("Attachment")) then
			if (at :: Instance).Parent ~= nil then
				parent = at :: Instance
			end
		end
	end
	local okParent = pcall(function()
		sound.Parent = parent
	end)
	if not okParent then
		voice.Dead = true
		return nil
	end

	sound.Volume = def.Volume * (if type(o.Volume) == "number" then math.max(0, o.Volume) else 1)
	local pitch = o.Pitch
	if type(pitch) ~= "number" then
		local range = def.Pitch
		if range and rng then
			pitch = range[1] + (range[2] - range[1]) * rng:NextNumber()
		else
			pitch = if range then range[1] else 1
		end
	end
	sound.PlaybackSpeed = math.max(0.05, pitch :: number)
	sound.Looped = if o.Looped ~= nil then o.Looped == true else def.Looped == true
	sound.TimePosition = if type(o.StartTime) == "number" then math.max(0, o.StartTime) else 0
	voice.Busy = true
	voice.Started = now
	sound:Play()
	checkLoaded(sound, id)
	if status == "pending" and idState[id] == nil then
		startProbe(id, entry) -- optimistic: this play used the id while it is being checked
	end
	if pool.WatchedId ~= id and not isBuiltin(id) then
		-- the first play of an id: a Sound that never loads it means a broken id even if the probe said Success
		pool.WatchedId = id
		task.delay(SoundController.LOAD_TIMEOUT, function()
			if not voice.Dead and pool.Id == id and sound.SoundId == id and not sound.IsLoaded then
				markBad(id, ("did not load within %d s"):format(SoundController.LOAD_TIMEOUT))
			end
		end)
	end
	return sound
end

function SoundController.Play(name: string, at: any?, opts: PlayOpts?): Sound?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local delay = opts and opts.Delay
	if type(delay) == "number" and delay > 0 then
		task.delay(delay, playNow, name, at, opts)
		return nil
	end
	local ok, result = pcall(playNow, name, at, opts)
	if not ok then
		warn("[SoundController] Play " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

function SoundController.Stop(sound: Sound?, fadeTime: number?)
	if sound == nil then
		return
	end
	local voice = voiceBySound[sound]
	local function finish()
		pcall(function()
			sound:Stop()
		end)
		if voice then
			voice.Busy = false
			returnHome(voice)
		end
	end
	if type(fadeTime) == "number" and fadeTime > 0 then
		local ok, tween = pcall(function()
			return TweenService:Create(sound, TweenInfo.new(fadeTime, Enum.EasingStyle.Sine), { Volume = 0 })
		end)
		if ok and tween then
			tween.Completed:Connect(finish)
			tween:Play()
			return
		end
	end
	finish()
end

function SoundController.StopAll(name: string)
	local _, resolvedName = SoundController.Resolve(name)
	local pool = pools[resolvedName or name]
	if pool then
		for _, voice in pool.Voices do
			if voice.Busy then
				SoundController.Stop(voice.Sound)
			end
		end
	end
end

function SoundController.Register(name: string, soundId: any, opts: { [string]: any }?)
	local base: SoundDef? = custom[name] or Audio.Get(name)
	local o = opts or {}
	local id = ""
	local list: { string } = {}
	if type(soundId) == "table" then
		for _, v in ipairs(soundId) do
			table.insert(list, Audio.NormalizeId(tostring(v)))
		end
	elseif soundId ~= nil then
		id = Audio.NormalizeId(tostring(soundId))
	end
	if type(o.Ids) == "table" then
		for _, v in ipairs(o.Ids) do
			table.insert(list, Audio.NormalizeId(tostring(v)))
		end
	end
	local def: SoundDef = {
		Id = id,
		Ids = if #list > 0 then list else nil,
		Group = o.Group or (base and base.Group) or "SFX",
		Volume = o.Volume or (base and base.Volume) or 0.5,
		Pitch = o.Pitch or (base and base.Pitch),
		Spatial = if o.Spatial ~= nil then o.Spatial else (base and base.Spatial),
		Looped = if o.Looped ~= nil then o.Looped else (base and base.Looped),
		RollOff = o.RollOff or (base and base.RollOff),
		MaxInstances = o.MaxInstances or (base and base.MaxInstances),
		MinInterval = o.MinInterval or (base and base.MinInterval),
		Fallback = o.Fallback or (base and base.Fallback),
		Note = base and base.Note,
	}
	custom[name] = def
	dropPool(name) -- its sounds carry the previous id
	scheduleMusicRefresh() -- the entry may be the current track
end

------------------------------------------------------------------------------------------------- music

local function ensureDecks()
	if #decks > 0 then
		return
	end
	ensureGroups()
	for i = 1, 2 do
		local sound = Instance.new("Sound")
		sound.Name = "SV_MusicDeck" .. i
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = groups.Music
		sound.Parent = SoundService
		table.insert(decks, {
			Sound = sound,
			Key = nil,
			Entry = nil,
			Id = nil,
			Current = 0,
			Target = 0,
			Rate = 1,
			StartedAt = 0,
			Checked = true,
			Resume = nil,
		})
	end
end

-- a looped track about to stop mid-play: remember where it was (resumed if it comes back within RESUME_WINDOW s)
local function rememberPosition(deck: Deck)
	local id, key = deck.Id, deck.Key
	if id == nil or key == nil or RESTART_KEYS[key] or not deck.Sound.Looped then
		return
	end
	local position = deck.Sound.TimePosition
	if type(position) == "number" and position > 0.5 then
		resumeAt[id] = { Position = position, At = os.clock() }
	end
end

-- where a track starts: the remembered position of a looped id stopped less than RESUME_WINDOW s ago, else 0
local function resumePosition(key: string, id: string, looped: boolean): number
	local saved = resumeAt[id]
	resumeAt[id] = nil
	if saved == nil or not looped or RESTART_KEYS[key] or os.clock() - saved.At > SoundController.RESUME_WINDOW then
		return 0
	end
	return saved.Position
end

local function faderStep(dt: number)
	-- ducking
	local now = os.clock()
	local wantDuck = if now < duckUntil then duckTarget else 1
	if duckLevel ~= wantDuck then
		local step = duckRate * dt
		if math.abs(wantDuck - duckLevel) <= step then
			duckLevel = wantDuck
		else
			duckLevel += if wantDuck > duckLevel then step else -step
		end
	end
	local busy = duckLevel ~= 1 or now < duckUntil
	for _, deck in decks do
		local id = deck.Id
		if id ~= nil and deck.Target > 0 and not deck.Checked then
			-- load check of the id on this deck: IsLoaded with TimeLength 0, or never loading, = a bad id
			if deck.Sound.IsLoaded then
				deck.Checked = true
				if deck.Sound.TimeLength <= 0 then
					markBad(id, EMPTY_REASON)
				end
			elseif now - deck.StartedAt > SoundController.LOAD_TIMEOUT then
				deck.Checked = true
				markBad(id, ("did not load within %d s"):format(SoundController.LOAD_TIMEOUT))
			else
				busy = true
			end
		end
		local resume = deck.Resume
		if resume ~= nil and deck.Sound.IsLoaded then
			-- a resumed track: make sure the position held through the load (and fits the file)
			deck.Resume = nil
			local length = deck.Sound.TimeLength
			local want = if length > 0 then resume % length else resume
			if math.abs(deck.Sound.TimePosition - want) > 1 then
				deck.Sound.TimePosition = want
			end
		end
		if deck.Current < deck.Target and not deck.Sound.IsLoaded then
			-- hold the fade-in until the asset has loaded (no full-volume pop after a slow load)
			busy = true
		elseif deck.Current ~= deck.Target then
			local step = deck.Rate * dt
			if math.abs(deck.Target - deck.Current) <= step then
				deck.Current = deck.Target
			else
				deck.Current += if deck.Target > deck.Current then step else -step
			end
			busy = true
		end
		deck.Sound.Volume = deck.Current * duckLevel
		if deck.Current <= 0 and deck.Target <= 0 and (deck.Sound.Playing or deck.Id ~= nil) then
			rememberPosition(deck)
			deck.Sound:Stop()
			deck.Key = nil
			deck.Entry = nil
			deck.Id = nil
			deck.Resume = nil
		end
	end
	if not busy and faderConnection then
		faderConnection:Disconnect()
		faderConnection = nil
	end
end

local function runFader()
	if faderConnection == nil then
		faderConnection = RunService.Heartbeat:Connect(faderStep)
	end
end

local function setDeck(deck: Deck, target: number, fade: number)
	deck.Target = target
	deck.Rate = math.max(math.abs(target - deck.Current), 0.001) / math.max(fade, 0.05)
end

local function fadeOutDeck(deck: Deck, fade: number)
	setDeck(deck, 0, fade)
	runFader()
end

-- the id on a deck is still fine to keep playing (not found bad)
local function deckAlive(deck: Deck): boolean
	local id = deck.Id
	return id ~= nil and deck.Target > 0 and stateOf(id) ~= "bad"
end

-- Plays `key` (resolved to `entry` / `id`) on the decks: crossfade from the current deck, or keep going when the
-- current deck already holds that audio.
local function playOn(key: string, entry: string, id: string, fade: number)
	local def = defOf(entry)
	if def == nil then
		return
	end
	local current = decks[activeDeck]
	local oneShotPlayed = current.Key == key and not current.Sound.Looped and current.Target > 0
	if current.Id == id and (current.Sound.Playing or oneShotPlayed) then
		-- already on this audio (e.g. "<map>_Final" -> FinalPhase while FinalPhase plays): keep it going; a one-shot
		-- (the Victory / Defeat stinger) that has already played for this request is never started again
		current.Key = key
		current.Entry = entry
		if current.Target ~= def.Volume then
			setDeck(current, def.Volume, fade)
			runFader()
		end
		return
	end
	local nextIndex = 3 - activeDeck
	local deck = decks[nextIndex]
	setDeck(current, 0, fade)
	local looped = def.Looped ~= false
	if not (deck.Id == id and deck.Sound.Playing and deck.Current > 0) then
		-- (otherwise: back to the track that is still fading out -> fade it back in without a restart)
		rememberPosition(deck)
		deck.Sound:Stop()
		deck.Sound.SoundId = id
		deck.Sound.Looped = looped
		local resume = resumePosition(key, id, looped)
		deck.Sound.TimePosition = resume
		deck.Resume = if resume > 0 then resume else nil
		deck.Current = 0
		deck.Sound.Volume = 0
		deck.StartedAt = os.clock()
		deck.Checked = false
		deck.Sound:Play()
	end
	deck.Sound.Looped = looped
	deck.Key = key
	deck.Entry = entry
	deck.Id = id
	setDeck(deck, def.Volume, fade)
	activeDeck = nextIndex
	runFader()
end

-- Puts the requested track on the decks: a good id -> (cross)fade to it; still being checked -> the playing track
-- goes on only if it is an acceptable stand-in (requestedChoices), else the first ready stand-in plays, else the music
-- fades out; dead / empty -> fade out (the selection has already moved on if it could).
local function syncDeck(fade: number)
	ensureDecks()
	local current = decks[activeDeck]
	local key = requestedMusic
	if key == nil then
		fadeOutDeck(current, fade)
		return
	end
	retryDue(key) -- a failed better candidate (or a dead entry) may be checked again, in the background
	local entry, id, status = resolveLive(key)
	if status == "ok" and entry ~= nil and id ~= nil then
		local keepEntry = if current.Key == key and current.Entry ~= nil then defOf(current.Entry :: string) else nil
		if
			keepEntry ~= nil
			and current.Id ~= id
			and deckAlive(current)
			and table.find(candidatesOf(keepEntry), current.Id) ~= nil
		then
			-- this track already plays on another good candidate (a better one answered late): keep it, no song
			-- switch mid-play; its next start uses the better one
			entry, id = current.Entry :: string, current.Id :: string
		end
		playOn(key, entry, id, fade)
	elseif status == "pending" and id ~= nil then
		startProbe(id, entry) -- its answer re-runs the selection (onIdChanged)
		if current.Key ~= nil and deckAlive(current) and table.find(requestedChoices, current.Key) ~= nil then
			return -- an acceptable stand-in keeps playing meanwhile
		end
		for _, alt in requestedChoices do
			if alt ~= key then
				local altEntry, altId, altStatus = resolveLive(alt)
				if altStatus == "ok" and altEntry ~= nil and altId ~= nil then
					playOn(alt, altEntry, altId, fade)
					return
				end
			end
		end
		fadeOutDeck(current, fade) -- nothing ready: silence rather than a stale track
	else
		fadeOutDeck(current, fade)
	end
end

function SoundController.CurrentMusic(): string?
	local deck = decks[activeDeck]
	return if deck then deck.Key else nil
end

-- the request behind PlayMusic and the automatic selection: `choices` = stand-ins accepted while `key` is checked
local function request(key: string?, choices: { string }?, fadeTime: number?)
	ensureDecks()
	local fade = if type(fadeTime) == "number" then math.max(0, fadeTime) else SoundController.DEFAULT_MUSIC_FADE
	local wanted = if type(key) == "string" and key ~= "" then canonical(key) else nil
	local changed = wanted ~= requestedMusic
	if changed then
		requestedMusic = wanted
		requestedFade = fade
	end
	local list: { string } = {}
	if wanted ~= nil then
		table.insert(list, wanted)
	end
	for _, choice in choices or {} do
		local c = canonical(choice)
		if table.find(list, c) == nil then
			table.insert(list, c)
		end
	end
	requestedChoices = list
	syncDeck(fade)
	if changed then
		SoundController.MusicChanged:Fire(wanted)
	end
end

function SoundController.PlayMusic(key: string?, fadeTime: number?)
	request(key, nil, fadeTime)
end

function SoundController.StopMusic(fadeTime: number?)
	SoundController.PlayMusic(nil, fadeTime)
end

function SoundController.Duck(amount: number, duration: number, fadeTime: number?)
	if type(amount) ~= "number" or type(duration) ~= "number" then
		return
	end
	duckTarget = math.clamp(1 - amount, 0, 1)
	duckUntil = math.max(duckUntil, os.clock() + duration)
	duckRate = 1 / math.max(fadeTime or 0.25, 0.05)
	ensureDecks()
	runFader()
end

function SoundController.ActiveId(name: string): string?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local key = canonical(name)
	local deck = decks[activeDeck]
	if deck and deck.Key == key and deck.Id ~= nil and deck.Target > 0 and idState[deck.Id] ~= "bad" then
		return deck.Id
	end
	local _, id, status = resolveLive(key)
	return if status == "ok" or status == "pending" then id else nil
end

function SoundController.NowPlaying(): { [string]: any }
	local key = requestedMusic
	local info: { [string]: any } = {
		Key = key,
		Entry = nil,
		Id = nil,
		Status = "empty",
		Index = nil,
		Count = 0,
		Preview = previewKey ~= nil,
		Playing = false,
	}
	if key == nil then
		return info
	end
	local entry, id, status = resolveLive(key)
	info.Status = status
	info.Entry = entry
	info.Id = id
	local deck = decks[activeDeck]
	if deck and deck.Key == key and deck.Id ~= nil and deck.Target > 0 and idState[deck.Id] ~= "bad" then
		info.Playing = true
		info.Id = deck.Id
		info.Entry = deck.Entry or entry
	end
	local entryDef = if info.Entry then defOf(info.Entry) else nil
	if entryDef then
		local list = candidatesOf(entryDef)
		info.Count = #list
		info.Index = if info.Id then table.find(list, info.Id) else nil
	end
	return info
end

------------------------------------------------------------------------------------- automatic music

local function stateRound(): { [string]: any }
	local State = controller("StateController")
	if State and type(State.Round) == "function" then
		local ok, round = pcall(State.Round)
		if ok and type(round) == "table" then
			return round
		end
	end
	return {}
end

local function mapMusicKey(mapId: any): string
	if type(mapId) == "string" and mapId ~= "" then
		local info = Registry.Info(mapId)
		if info and type(info.Music) == "string" and info.Music ~= "" then
			return info.Music
		end
		return "Map_" .. mapId
	end
	return "Lobby"
end

-- Pure: the arena music keys for a RoundState snapshot, most preferred first (no duplicates).
function SoundController.ArenaMusicOrder(round: { [string]: any }): { string }
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(key: string?)
		if key ~= nil and not seen[key] then
			seen[key] = true
			table.insert(order, key)
		end
	end
	local kit = if type(round.MonsterKit) == "string" then round.MonsterKit else nil
	local mapKey = Audio.MapMusic(mapMusicKey(round.MapId), false)
	if round.Phase == "Collapse" then
		add("CollapsePhase") -- the closing ring has its own track; when it is unusable the fight music keeps going
	end
	if round.FinalPhase == true then
		add(Audio.MonsterTheme(kit, true))
		add(Audio.MonsterTheme(kit, false))
		add(Audio.MapMusic(mapKey, true)) -- "<map>_Final" (falls back to FinalPhase) or FinalPhase
		add("FinalPhase")
	else
		add(Audio.MonsterTheme(kit, false))
	end
	add(mapKey)
	return order
end

local function staticUsable(key: string): boolean
	return Audio.Resolve(key) ~= nil
end

-- The automatic selection's choices, most preferred first: an override, then the box track, then the phase's track(s)
-- (a lobby viewer: the lobby; the arena: every usable key of ArenaMusicOrder; Ending: the stinger, else the track
-- that was on - never the box track). `firstOnly` stops at the first key (MusicFor: no Usable calls past it).
local function musicChoices(round: { [string]: any }, ctx: { [string]: any }, firstOnly: boolean): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(key: any): boolean -- true = done (firstOnly and a key is in)
		if type(key) == "string" and key ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
		return firstOnly and #out > 0
	end
	if ctx.Override and add(ctx.Override) then
		return out
	end
	if ctx.Box and add("VerdictBox") then
		return out
	end
	if ctx.Participant == false then
		add("Lobby") -- waiting in the lobby while a round runs elsewhere
		return out
	end
	local phase = round.Phase
	if phase == "Intro" or phase == "Round" or phase == "Collapse" then
		local usable: (string) -> boolean = if type(ctx.Usable) == "function" then ctx.Usable else staticUsable
		local order = SoundController.ArenaMusicOrder(round)
		local any = false
		for _, key in order do
			if usable(key) then
				any = true
				if add(key) then
					return out
				end
			end
		end
		if not any then
			add(order[#order]) -- nothing playable: the map's track (silent), as without themes
		end
	elseif phase == "Ending" then
		if ctx.Stinger then
			add(ctx.Stinger)
		else
			for _, key in { ctx.Current, ctx.Playing } do
				if key ~= "VerdictBox" and add(key) then
					return out
				end
			end
		end
	else
		add("Lobby")
	end
	return out
end

-- Pure: the track the automatic selection wants for a RoundState snapshot.
function SoundController.MusicFor(round: { [string]: any }, ctx: { [string]: any }): string?
	return musicChoices(round, ctx, true)[1]
end

-- Pure: MusicFor's answer first, then the stand-ins that may play while it is still being checked.
function SoundController.MusicChoices(round: { [string]: any }, ctx: { [string]: any }): { string }
	return musicChoices(round, ctx, false)
end

-- Pure: the music a round will soon need, most urgent first: the fight track, the box track, the Phase 2 track,
-- CollapsePhase, Victory, Defeat. Nothing for a lobby viewer or outside Intro / Round / Collapse.
function SoundController.PrefetchOrder(round: { [string]: any }, ctx: { [string]: any }?): { string }
	local c = ctx or {}
	local out: { string } = {}
	local phase = round.Phase
	if c.Participant == false or (phase ~= "Intro" and phase ~= "Round" and phase ~= "Collapse") then
		return out
	end
	local usable: (string) -> boolean = if type(c.Usable) == "function" then c.Usable else staticUsable
	local function add(key: string?)
		if key ~= nil and table.find(out, key) == nil then
			table.insert(out, key)
		end
	end
	local function firstUsable(final: boolean): string?
		local order =
			SoundController.ArenaMusicOrder({ Phase = "Round", MapId = round.MapId, MonsterKit = round.MonsterKit, FinalPhase = final })
		for _, key in order do
			if usable(key) then
				return key
			end
		end
		return nil
	end
	add(firstUsable(false))
	add("VerdictBox")
	add(firstUsable(true))
	add("CollapsePhase")
	add("Victory")
	add("Defeat")
	return out
end

-- false only when we know the local player is waiting in the lobby (Role "Lobby"); unknown = participant
local function isParticipant(): boolean
	local State = controller("StateController")
	if State and type(State.Role) == "function" then
		local ok, role = pcall(State.Role)
		if ok and type(role) == "string" and role ~= "" then
			return role ~= "Lobby"
		end
	end
	return true
end

local function musicCtx(): { [string]: any }
	local deck = decks[activeDeck]
	return {
		Override = previewKey or musicOverride,
		Box = boxActive,
		Stinger = stingerKey,
		Current = requestedMusic,
		Playing = if deck and deck.Target > 0 then deck.Key else nil,
		Participant = isParticipant(),
		Usable = usableKey,
	}
end

local function refreshMusic(fadeTime: number?)
	-- a no-op when the key and its id are unchanged
	local round = stateRound()
	local ctx = musicCtx()
	local choices = SoundController.MusicChoices(round, ctx)
	request(choices[1], choices, fadeTime)
	local phase = round.Phase
	if ctx.Participant ~= false and (phase == "Intro" or phase == "Round" or phase == "Collapse") then
		-- the arena tracks preferred over the one chosen are dead right now: each gets its re-check when due
		for _, key in SoundController.ArenaMusicOrder(round) do
			if key == choices[1] or table.find(choices, key) ~= nil then
				break
			end
			retryDue(key)
		end
	end
end

-- warms up what the current round will need (front of the queue); nothing outside a round
local function prefetchRound()
	local order = SoundController.PrefetchOrder(stateRound(), { Participant = isParticipant(), Usable = usableKey })
	if #order > 0 then
		prefetchList(order, true)
		pumpMusic()
	end
end

scheduleMusicRefresh = function()
	if refreshQueued or not started then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		local ok, err = pcall(refreshMusic, requestedFade)
		if not ok then
			warn("[SoundController] music refresh: " .. tostring(err))
		end
	end)
end

onIdChanged = function(id: string)
	if idState[id] == "bad" then
		-- SFX / UI pools that use this id switch to their next candidate (dead entries are dropped: their plays
		-- follow the Fallback chain from now on)
		for name, pool in pools do
			if pool.Id == id then
				local nextId, status = SoundController.PickCandidate(candidatesOf(pool.Def), stateOf)
				if nextId ~= nil then
					if status == "pending" and idState[nextId] == nil then
						startProbe(nextId, name)
					end
					setPoolId(pool, nextId)
				else
					dropPool(name)
				end
			end
		end
	end
	scheduleMusicRefresh()
end

function SoundController.SetMusicOverride(key: string?, fadeTime: number?)
	musicOverride = if type(key) == "string" and key ~= "" then key else nil
	refreshMusic(fadeTime)
end

function SoundController.PreviewMusic(key: string?)
	previewKey = if type(key) == "string" and key ~= "" then canonical(key) else nil
	if started then
		refreshMusic(0.5)
	end
end

local function onRoundEnd(data: any)
	local winner = if type(data) == "table" then data.winner else nil
	local State = controller("StateController")
	local role: string? = nil
	if State then
		local okRole, current = pcall(State.Role)
		if okRole and (current == "Human" or current == "Monster") then
			role = current
		elseif type(State.LastCombatRole) == "function" then
			local okLast, last = pcall(State.LastCombatRole)
			if okLast then
				role = last
			end
		end
	end
	if winner == "Monster" or winner == "Humans" then
		if role == nil then
			stingerKey = "Victory"
		else
			local won = (role == "Monster" and winner == "Monster") or (role == "Human" and winner == "Humans")
			stingerKey = if won then "Victory" else "Defeat"
		end
	else
		stingerKey = nil
	end
	refreshMusic(0.6)
end

local function hookState()
	local State = controller("StateController")
	if State == nil then
		return
	end
	local function readSettings()
		local okM, music = pcall(State.Setting, "MusicVolume")
		local okS, sfx = pcall(State.Setting, "SfxVolume")
		SoundController.SetVolumes(if okM then music else nil, if okS then sfx else nil)
	end
	readSettings()
	if State.SettingChanged then
		State.SettingChanged:Connect(function(key: string)
			if key == "MusicVolume" or key == "SfxVolume" then
				readSettings()
			end
		end)
	end
	if State.RoundChanged then
		State.RoundChanged:Connect(function(attr: string, value: any)
			if attr == "Phase" then
				if value ~= "Ending" then
					stingerKey = nil
				end
				refreshMusic()
				prefetchRound()
			elseif attr == "MapId" or attr == "FinalPhase" or attr == "MonsterKit" then
				refreshMusic(if attr == "FinalPhase" then 0.8 else nil)
				prefetchRound()
			end
		end)
	end
	if State.RoleChanged then
		-- joining / leaving the round (or waiting in the lobby during one) switches between arena and lobby music
		State.RoleChanged:Connect(function()
			refreshMusic()
			prefetchRound()
		end)
	end
	if type(State.OnRoundEvent) == "function" then
		State.OnRoundEvent("RoundEnd", onRoundEnd)
		State.OnRoundEvent("FinalPhase", function()
			if not isParticipant() then
				return -- the lobby does not hear the arena's stinger
			end
			SoundController.Play("FinalPhaseStinger")
			SoundController.Duck(0.6, 1.2, 0.15)
		end)
	end
end

-- Prewarm(name): checks (downloads) an entry's candidate ahead of time in the background, the next one after a bad
-- one, so a later PlayMusic / Play of it starts at once instead of waiting for its first check. Music joins the
-- one-at-a-time warm-up queue (after what already waits there). Safe to call repeatedly.
function SoundController.Prewarm(name: string)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = canonical(name)
	if isMusicEntry(key) then
		prefetchMusic(key)
		pumpMusic()
	else
		queueEntry(key)
		pumpProbes()
	end
end

local function hookInput()
	local Input = controller("InputController")
	if Input == nil or Input.ContextChanged == nil then
		return
	end
	if type(Input.HasContext) == "function" then
		boxActive = Input.HasContext("Box")
	end
	Input.ContextChanged:Connect(function(name: string, active: boolean)
		if name == "Box" then
			boxActive = active
			refreshMusic(if active then SoundController.BOX_FADE_IN else SoundController.BOX_FADE_OUT)
		end
	end)
end

--------------------------------------------------------------------------------------------- lifecycle

function SoundController.Init()
	rng = Random.new()
end

function SoundController.Start()
	if started then
		return
	end
	started = true
	ensureGroups()
	ensureDecks()
	applyGroupVolumes()
	hookState()
	hookInput()
	prefetchList(START_MUSIC)
	-- the first track one resumption later: a title screen that opens at once asks for its own track first, so the
	-- lobby track is not downloaded in the foreground next to it (it is warmed up right after)
	task.defer(function()
		local ok, err = pcall(refreshMusic, 2.5)
		if not ok then
			warn("[SoundController] music: " .. tostring(err))
		end
		warmupOpen = true
		prefetchRound() -- joined during a round
		pumpMusic()
	end)
	task.delay(SoundController.PROBE_BATCH_DELAY, probeShortSounds)
end

return SoundController
