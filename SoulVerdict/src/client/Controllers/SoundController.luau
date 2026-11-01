--!strict
-- SoundController (client, SPEC §20, Priority 10): plays named sounds from Shared/Audio.luau with pooling, three
-- SoundGroups (SV_Music / SV_SFX / SV_UI under SoundService) scaled by the player's MusicVolume / SfxVolume settings,
-- two-deck music crossfades with ducking, and automatic music selection:
--   Waiting / Intermission -> "Lobby";  Intro / Round / Collapse -> the map's track (Maps/Registry Music key; while
--   RoundState.FinalPhase: "<key>_Final" -> "FinalPhase");  Ending -> "Victory" / "Defeat" stinger (from RoundEnd);
--   InputController context "Box" (the local player is inside the Verdict Box) -> "VerdictBox";
--   SetMusicOverride(key) beats everything (title screen, Style Lab...).
-- Empty ids (Audio entries the owner has not filled yet) play nothing and never warn.
-- Voices: one pool per resolved entry (max Audio MaxInstances, oldest voice is stolen when full); 3D sounds at a
-- Vector3 use pooled Attachments under workspace.Terrain; at a BasePart / Attachment the voice is parented there
-- and comes back to the pool when it ends. Plays of one entry closer than MinInterval are dropped (hit spam).
--
-- API (SPEC §20)
--   SoundController.Play(name, at?: Vector3|BasePart|Attachment, opts?) -> Sound?
--       opts: { Volume: number? (x entry volume), Pitch: number? (exact PlaybackSpeed), Looped: boolean?,
--               Delay: number? (schedules the play; returns nil), StartTime: number?, Force2D: boolean? }
--       The returned Sound belongs to the pool: never Destroy it; stop it with SoundController.Stop(sound).
--   SoundController.PlayMusic(key, fadeTime?)        immediate crossfade (automatic selection may change it later;
--                                                    use SetMusicOverride for a sticky choice)
--   SoundController.StopMusic(fadeTime?)
--   SoundController.SetVolumes(music, sfx)           0..1 multipliers (settings call this automatically)
--   SoundController.Register(name, soundId, opts?)   runtime entry / id override (opts = SoundDef fields)
-- Extras
--   SoundController.Stop(sound, fadeTime?) ; StopAll(name)
--   SoundController.SetMusicOverride(key?, fadeTime?) ; CurrentMusic() -> string? ; MusicChanged: Signal(key?)
--   SoundController.Duck(amount 0..1, duration, fadeTime?)   temporarily lowers music (big moments)
--   SoundController.Resolve(name) -> (SoundDef?, string?)    runtime registry + Shared/Audio
--   SoundController.Groups() -> { Music: SoundGroup?, SFX: SoundGroup?, UI: SoundGroup? }

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Registry = require(Shared:WaitForChild("Maps"):WaitForChild("Registry"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

type SoundDef = Audio.SoundDef

local SoundController = {}
SoundController.Priority = 10
SoundController.MusicChanged = Signal.new()

SoundController.DEFAULT_MUSIC_FADE = 1.6
SoundController.MAX_EMITTERS = 40

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
}

type Deck = {
	Sound: Sound,
	Key: string?,
	Current: number,
	Target: number,
	Rate: number,
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
local musicOverride: string? = nil
local stingerKey: string? = nil
local boxActive = false
local duckLevel, duckTarget, duckUntil, duckRate = 1, 1, 0, 4
local faderConnection: RBXScriptConnection? = nil
local started = false

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

--------------------------------------------------------------------------------------------- registry

function SoundController.Resolve(name: string): (SoundDef?, string?)
	local current: string? = name
	local depth = 0
	while current ~= nil and depth < 8 do
		local def: SoundDef? = custom[current] or Audio.Get(current)
		if def == nil then
			return nil, nil
		end
		if def.Id ~= "" then
			local resolvedName = if custom[current] or Audio.Sounds[current] then current else Audio.Aliases[current]
			return def, resolvedName or current
		end
		current = def.Fallback
		depth += 1
	end
	return nil, nil
end

function SoundController.Register(name: string, soundId: string | number, opts: { [string]: any }?)
	local base: SoundDef? = custom[name] or Audio.Get(name)
	local o = opts or {}
	local def: SoundDef = {
		Id = Audio.NormalizeId(tostring(soundId)),
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
	-- drop the old pool: its sounds carry the previous id
	local pool = pools[name]
	if pool then
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

local function configureSound(sound: Sound, def: SoundDef)
	sound.SoundId = Audio.NormalizeId(def.Id)
	sound.Volume = def.Volume
	sound.Looped = def.Looped == true
	local rollOff = def.RollOff or Audio.DEFAULT_ROLLOFF
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = rollOff[1]
	sound.RollOffMaxDistance = rollOff[2]
	sound.SoundGroup = groups[def.Group] or groups.SFX
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
	configureSound(sound, pool.Def)
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
	sound.Parent = poolFolder
	voiceBySound[sound] = voice
	return voice
end

local function getPool(name: string, def: SoundDef): Pool
	local pool = pools[name]
	if pool == nil or pool.Def ~= def then
		pool = {
			Name = name,
			Def = def,
			Id = def.Id,
			Voices = {},
			LastPlay = -math.huge,
		}
		pools[name] = pool
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
	local def, resolvedName = SoundController.Resolve(name)
	if def == nil or resolvedName == nil then
		return nil
	end
	if poolFolder == nil then
		ensureGroups()
	end
	local now = os.clock()
	local pool = getPool(resolvedName, def)
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
		table.insert(decks, { Sound = sound, Key = nil, Current = 0, Target = 0, Rate = 1 })
	end
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
		if deck.Current <= 0 and deck.Target <= 0 and deck.Sound.Playing then
			deck.Sound:Stop()
			deck.Key = nil
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

function SoundController.CurrentMusic(): string?
	local deck = decks[activeDeck]
	return if deck then deck.Key else nil
end

function SoundController.PlayMusic(key: string?, fadeTime: number?)
	ensureDecks()
	local fade = if type(fadeTime) == "number" then math.max(0, fadeTime) else SoundController.DEFAULT_MUSIC_FADE
	local wanted = if type(key) == "string" and key ~= "" then (Audio.Aliases[key] or key) else nil
	if wanted ~= nil and wanted == requestedMusic then
		return
	end
	requestedMusic = wanted
	local def = if wanted then SoundController.Resolve(wanted) else nil
	local current = decks[activeDeck]
	if def == nil then
		-- unknown / silent track: fade the current one out
		setDeck(current, 0, fade)
		runFader()
		SoundController.MusicChanged:Fire(wanted)
		return
	end
	local nextIndex = 3 - activeDeck
	local deck = decks[nextIndex]
	setDeck(current, 0, fade)
	deck.Sound:Stop()
	deck.Sound.SoundId = Audio.NormalizeId(def.Id)
	deck.Sound.Looped = def.Looped ~= false
	deck.Sound.TimePosition = 0
	deck.Key = wanted
	deck.Current = 0
	deck.Sound.Volume = 0
	setDeck(deck, def.Volume, fade)
	deck.Sound:Play()
	activeDeck = nextIndex
	runFader()
	SoundController.MusicChanged:Fire(wanted)
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

local function desiredMusic(): string?
	if musicOverride then
		return musicOverride
	end
	if boxActive then
		return "VerdictBox"
	end
	local round = stateRound()
	local phase = round.Phase
	if phase == "Intro" or phase == "Round" or phase == "Collapse" then
		return Audio.MapMusic(mapMusicKey(round.MapId), round.FinalPhase == true)
	elseif phase == "Ending" then
		return stingerKey or requestedMusic
	end
	return "Lobby"
end

local function refreshMusic(fadeTime: number?)
	local key = desiredMusic()
	if key ~= requestedMusic then
		SoundController.PlayMusic(key, fadeTime)
	end
end

function SoundController.SetMusicOverride(key: string?, fadeTime: number?)
	musicOverride = if type(key) == "string" and key ~= "" then key else nil
	refreshMusic(fadeTime)
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
			elseif attr == "MapId" or attr == "FinalPhase" then
				refreshMusic(if attr == "FinalPhase" then 0.8 else nil)
			end
		end)
	end
	if type(State.OnRoundEvent) == "function" then
		State.OnRoundEvent("RoundEnd", onRoundEnd)
		State.OnRoundEvent("FinalPhase", function()
			SoundController.Play("FinalPhaseStinger")
			SoundController.Duck(0.6, 1.2, 0.15)
		end)
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
			refreshMusic(if active then 0.35 else 1.0)
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
	refreshMusic(2.5)
end

return SoundController
