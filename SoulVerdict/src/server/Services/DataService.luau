--!strict
-- DataService (P5): persistent player profiles (SPEC §12, §17). One session per player:
--   load  -> UpdateAsync on DataStore Config.Data.StoreName, key "u_<userId>", record = {Data, Session, SavedAt}.
--            Session = {JobId, Id, PlaceId, Time} is a lock: a live lock of another server is waited for
--            (retry every LOCK_RETRY s; a lock older than Config.Data.SessionLockTimeout is stolen at once, and
--            after LOCK_WAIT_MAX s of waiting it is force-stolen: a player cannot be in two servers, so such a
--            lock belongs to a dead/hung server — that server's later writes are refused by the lock check).
--            Data goes through ProfileSchema.Migrate (old/partial profiles are deep-reconciled + sanitised).
--   save  -> autosave every Config.Data.AutosaveInterval (staggered, refreshes the lock), save + release on
--            leave, BindToClose saves every session in parallel and waits (<= 25 s). A save is refused when the
--            stored lock is not ours (LockLost: that server stops writing). Retries with exponential backoff +
--            jitter (Config.Data.MaxRetries); every request waits for DataStore request budget first.
--   fallback -> Studio without API access / unpublished place / DataStore unavailable: profiles live in memory
--            (one-time Notify "prog.notify.memoryMode", nothing is saved). A failed load gives a temporary default
--            profile that is NEVER saved (so it can't overwrite real data) + Notify "prog.notify.loadFailed".
--            Nobody is ever kicked.
--   replicate -> Net "Profile" (full ProfileSchema.View incl. ShopToday + Meta) throttled to <= 4/s per player,
--            and Player attributes Level, Exp, Gold, RolePreference, EquippedHuman, EquippedMonster, Title, Trail,
--            RoundsSinceMonster (MonsterChance only when QueueService is absent — QueueService owns it).
--            Net function "GetProfile" returns the same view (waits up to 15 s for the load).
--
-- API (SPEC §17)
--   Get(player) -> Profile?                  live profile table (nil while loading). Mutate ONLY via Update.
--   WaitFor(player, timeout?) -> Profile?    yields until loaded (default 30 s)
--   Update(player, fn(profile)) -> boolean   runs fn on the live profile, marks dirty, Changed + Replicate
--   Replicate(player)                         queue a "Profile" push + attribute refresh (coalesced, <= 4/s)
--   IsReady(player) -> boolean               IsPersistent(player) -> boolean     Mode() -> "DataStore"|"Memory"|"Pending"
--   RequestSave(player)                      debounced early save (purchases)    LanguageOf(player) -> "en"|"ru"
--   View(player) -> ProfileView?             Loaded: Signal(player, profile)
--   Changed: Signal(player, profile)         deferred, coalesced per player after Update
--   Releasing: Signal(player, profile)       right before the final save of a leaving player / shutdown
--   AcquireTransform / SaveTransform / Normalize   pure UpdateAsync transforms of the lock protocol (tests)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local TableUtil = require(Shared:WaitForChild("Util"):WaitForChild("TableUtil")) :: any
local ProfileSchema = require(Shared:WaitForChild("Progression"):WaitForChild("ProfileSchema")) :: any

local DataService = {}
DataService.Priority = 5

DataService.Loaded = Signal.new()
DataService.Changed = Signal.new()
DataService.Releasing = Signal.new()

local REPLICATE_INTERVAL = 0.25 -- <= 4 "Profile" pushes per second per player
local LOCK_RETRY = 6
local LOCK_WAIT_MAX = 45
local AUTOSAVE_TICK = 5
local EARLY_SAVE_MIN_GAP = 15
local CLOSE_TIMEOUT = 25
local VIEW_CACHE_TIME = 0.5

type Session = {
	Player: Player,
	UserId: number,
	Key: string,
	Id: string,
	Profile: any?,
	State: string, -- "Loading" | "Ready" | "Releasing" | "Released"
	Persistent: boolean,
	LockLost: boolean,
	ChangeCount: number,
	SavedCount: number,
	LastSave: number,
	NextAutosave: number,
	Saving: boolean,
	ReplicateQueued: boolean,
	LastReplicate: number,
	ChangedQueued: boolean,
	EarlySaveQueued: boolean,
	ViewCache: any?,
	ViewAt: number,
}

local sessions: { [Player]: Session } = {}
local releasing: { [number]: Session } = {} -- userId -> session whose final save is in flight
local mode: string = "Pending"
local modeDecided = Signal.new()
local store: any = nil
local dataStoreService: any = nil
local jobId = ""
local shuttingDown = false
local random = Random.new()
local QueueService: any = nil

-- Helpers ---------------------------------------------------------------------------------------------

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function backoff(attempt: number): number
	return math.min(2 ^ (attempt - 1), 16) + random:NextNumber() * 0.5
end

local function budgetOk(kind: string): boolean
	if dataStoreService == nil then
		return true
	end
	local types = if kind == "write" then { "UpdateAsync", "StandardWrite" } else { "GetAsync", "StandardRead" }
	for _, name in types do
		local ok, value = pcall(function()
			return dataStoreService:GetRequestBudgetForRequestType((Enum.DataStoreRequestType :: any)[name])
		end)
		if ok and type(value) == "number" and value < 1 then
			return false
		end
	end
	return true
end

-- Waits (bounded) until the DataStore request budget allows a call; proceeds anyway after maxWait.
local function waitForBudget(kind: string, maxWait: number)
	local deadline = os.clock() + maxWait
	while not budgetOk(kind) and os.clock() < deadline do
		task.wait(0.5)
	end
end

local function waitForMode()
	if mode == "Pending" then
		modeDecided:Wait()
	end
end

-- Stored value -> {Data, Session, SavedAt}; accepts a bare legacy profile too.
local function normalize(old: any): { [string]: any }
	if type(old) ~= "table" then
		return {}
	end
	if old.Data ~= nil or old.Session ~= nil then
		return old
	end
	if old.Version ~= nil or old.Level ~= nil then
		return { Data = old }
	end
	return {}
end

-- Pure UpdateAsync transforms (unit-tested) ---------------------------------------------------------------
-- AcquireTransform(old, {JobId, Id, PlaceId, Now, Timeout, Force}) -> (record?, lockedBy?)
--   record = value to write (lock taken); nil + lockedBy = a live foreign lock (cancel the write).
--   A lock of the same JobId (this server) or older than Timeout, or Force, is taken over.
function DataService.AcquireTransform(old: any, args: { [string]: any }): (any, any)
	local record = normalize(old)
	local lock = record.Session
	if
		type(lock) == "table"
		and lock.JobId ~= args.JobId
		and type(lock.Time) == "number"
		and args.Now - lock.Time < args.Timeout
		and not args.Force
	then
		return nil, lock
	end
	record.Session = { JobId = args.JobId, Id = args.Id, PlaceId = args.PlaceId, Time = args.Now }
	return record, nil
end

-- SaveTransform(old, {JobId, Id, PlaceId, Now, Release, Data}) -> (record?, lost: boolean)
--   writes Data only while the stored lock is still this session's (Id); Release clears the lock.
function DataService.SaveTransform(old: any, args: { [string]: any }): (any, boolean)
	local record = normalize(old)
	local lock = record.Session
	if type(lock) ~= "table" or lock.Id ~= args.Id then
		return nil, true
	end
	record.Data = args.Data
	record.Session = if args.Release
		then nil
		else { JobId = args.JobId, Id = args.Id, PlaceId = args.PlaceId, Time = args.Now }
	record.SavedAt = args.Now
	return record, false
end

DataService.Normalize = normalize

local function languageOf(player: Player, profile: any?): string
	local lang = if profile and type(profile.Settings) == "table" then profile.Settings.Language else nil
	if lang == "en" or lang == "ru" then
		return lang
	end
	local ok, locale = pcall(function()
		return player.LocaleId
	end)
	if ok and type(locale) == "string" and string.sub(string.lower(locale), 1, 2) == "ru" then
		return "ru"
	end
	return "en"
end

-- Replication -----------------------------------------------------------------------------------------

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function fallbackMonsterChance(player: Player)
	-- only used when QueueService is missing; QueueService is otherwise the only writer of this attribute
	local total, mine = 0, 0
	for p, s in sessions do
		local prof = s.Profile
		if prof and prof.RolePreference ~= "Human" then
			local w = if type(prof.MonsterChance) == "number" then prof.MonsterChance else 1
			total += w
			if p == player then
				mine = w
			end
		end
	end
	local share = if total > 0 then mine / total else 0
	setAttr(player, "MonsterChance", math.floor(share * 1000 + 0.5) / 1000)
end

local function buildView(session: Session): any
	local profile = session.Profile
	if profile == nil then
		return nil
	end
	local view = ProfileSchema.View(profile, { Now = os.time(), Persistent = session.Persistent })
	session.ViewCache = view
	session.ViewAt = os.clock()
	return view
end

local function doReplicate(session: Session)
	local player = session.Player
	local profile = session.Profile
	if profile == nil or player.Parent == nil or sessions[player] ~= session then
		return
	end
	session.LastReplicate = os.clock()
	local ok, view = pcall(buildView, session)
	if ok and view then
		pcall(Net.Server.Fire, "Profile", player, view)
	elseif not ok then
		warn("[DataService] view failed for " .. player.Name .. ": " .. tostring(view))
	end
	local equipped = profile.Equipped
	setAttr(player, "Level", profile.Level)
	setAttr(player, "Exp", profile.Exp)
	setAttr(player, "Gold", profile.Gold)
	setAttr(player, "RolePreference", profile.RolePreference)
	setAttr(player, "EquippedHuman", equipped.Human)
	setAttr(player, "EquippedMonster", equipped.Monster)
	setAttr(player, "Title", equipped.Title or "")
	setAttr(player, "Trail", equipped.Trail or "")
	setAttr(player, "RoundsSinceMonster", profile.RoundsSinceMonster)
	if QueueService == nil then
		fallbackMonsterChance(player)
	end
end

function DataService.Replicate(player: Player)
	local session = sessions[player]
	if session == nil or session.Profile == nil or session.ReplicateQueued then
		return
	end
	session.ReplicateQueued = true
	local delay = math.max(0, session.LastReplicate + REPLICATE_INTERVAL - os.clock())
	task.delay(delay, function()
		session.ReplicateQueued = false
		doReplicate(session)
	end)
end

local function scheduleChanged(session: Session)
	if session.ChangedQueued then
		return
	end
	session.ChangedQueued = true
	task.defer(function()
		session.ChangedQueued = false
		local profile = session.Profile
		if profile and session.Player.Parent and sessions[session.Player] == session then
			DataService.Changed:Fire(session.Player, profile)
		end
	end)
end

-- DataStore I/O -------------------------------------------------------------------------------------------

-- Returns (ok, data, failReason). ok with data == nil means a brand-new player.
local function loadRecord(session: Session): (boolean, any, string?)
	local attempts = 0
	local lockWaitStart: number? = nil
	local forceSteal = false
	local notifiedWait = false
	while session.Player.Parent ~= nil and not shuttingDown do
		attempts += 1
		waitForBudget("write", 15)
		local args = {
			JobId = jobId,
			Id = session.Id,
			PlaceId = game.PlaceId,
			Now = os.time(),
			Timeout = Config.Data.SessionLockTimeout,
			Force = forceSteal,
		}
		local lockedBy: any = nil
		local ok, result = pcall(function()
			return store:UpdateAsync(session.Key, function(old: any)
				local record, holder = DataService.AcquireTransform(old, args)
				lockedBy = holder
				return record -- nil cancels the write: someone else holds a live lock
			end)
		end)
		if ok and lockedBy == nil then
			local record = normalize(result)
			return true, record.Data, nil
		elseif ok then
			lockWaitStart = lockWaitStart or os.clock()
			if not notifiedWait then
				notifiedWait = true
				notify(session.Player, "prog.notify.lockWait", nil, "Info")
			end
			if os.clock() - (lockWaitStart :: number) >= LOCK_WAIT_MAX then
				warn(
					("[DataService] force-stealing the session lock of %d (held by job %s)"):format(
						session.UserId,
						tostring(lockedBy.JobId)
					)
				)
				forceSteal = true
			else
				task.wait(LOCK_RETRY)
			end
		else
			warn(("[DataService] load %s attempt %d failed: %s"):format(session.Key, attempts, tostring(result)))
			if attempts >= Config.Data.MaxRetries then
				return false, nil, "error"
			end
			task.wait(backoff(attempts))
		end
	end
	return false, nil, "left"
end

-- Writes the profile (and keeps or releases the lock). Returns true on success.
local function saveSession(session: Session, release: boolean): boolean
	local profile = session.Profile
	if mode ~= "DataStore" or not session.Persistent or session.LockLost or profile == nil then
		return false
	end
	while session.Saving do
		task.wait(0.1)
	end
	if session.LockLost then
		return false
	end
	session.Saving = true
	local snapshot = TableUtil.deepCopy(profile)
	snapshot.LastSeen = os.time()
	local countAtSnapshot = session.ChangeCount
	local okSanitize, err = pcall(ProfileSchema.Sanitize, snapshot)
	if not okSanitize then
		warn("[DataService] sanitize before save failed: " .. tostring(err))
	end
	local saved = false
	for attempt = 1, Config.Data.MaxRetries do
		if not shuttingDown then
			waitForBudget("write", if release then 5 else 10)
		end
		local args = {
			JobId = jobId,
			Id = session.Id,
			PlaceId = game.PlaceId,
			Now = os.time(),
			Release = release,
			Data = snapshot,
		}
		local lost = false
		local ok, result = pcall(function()
			return store:UpdateAsync(session.Key, function(old: any)
				local record, isLost = DataService.SaveTransform(old, args)
				lost = isLost
				return record
			end)
		end)
		if ok then
			if lost then
				session.LockLost = true
				warn(("[DataService] %s: session lock lost, this server stops saving it"):format(session.Key))
			else
				saved = true
				session.SavedCount = countAtSnapshot
				session.LastSave = os.clock()
			end
			break
		end
		warn(("[DataService] save %s attempt %d failed: %s"):format(session.Key, attempt, tostring(result)))
		if attempt < Config.Data.MaxRetries then
			task.wait(if shuttingDown then 0.5 else backoff(attempt))
		end
	end
	session.Saving = false
	return saved
end

-- Sessions ---------------------------------------------------------------------------------------------------

local function finishLoad(session: Session, profile: any, persistent: boolean)
	session.Profile = profile
	session.Persistent = persistent
	session.State = "Ready"
	session.LastSave = os.clock()
	session.NextAutosave = os.clock() + Config.Data.AutosaveInterval + random:NextNumber() * 20
	local player = session.Player
	DataService.Loaded:Fire(player, profile)
	doReplicate(session)
	if mode == "Memory" then
		notify(player, "prog.notify.memoryMode", nil, "Warning")
	elseif not persistent then
		notify(player, "prog.notify.loadFailed", nil, "Warning")
	end
end

local function releaseSession(session: Session)
	if session.State == "Releasing" or session.State == "Released" then
		return
	end
	local player = session.Player
	local wasLoading = session.State == "Loading"
	session.State = "Releasing"
	releasing[session.UserId] = session
	if session.Profile and not wasLoading then
		DataService.Releasing:Fire(player, session.Profile)
		task.wait() -- let Releasing handlers record final values before the snapshot
		saveSession(session, true)
	end
	session.State = "Released"
	if releasing[session.UserId] == session then
		releasing[session.UserId] = nil
	end
	if sessions[player] == session then
		sessions[player] = nil
	end
end

local function startSession(player: Player)
	if sessions[player] then
		return
	end
	local session: Session = {
		Player = player,
		UserId = player.UserId,
		Key = Config.Data.KeyPrefix .. tostring(player.UserId),
		Id = HttpService:GenerateGUID(false),
		Profile = nil,
		State = "Loading",
		Persistent = false,
		LockLost = false,
		ChangeCount = 0,
		SavedCount = 0,
		LastSave = os.clock(),
		NextAutosave = math.huge,
		Saving = false,
		ReplicateQueued = false,
		LastReplicate = 0,
		ChangedQueued = false,
		EarlySaveQueued = false,
		ViewCache = nil,
		ViewAt = 0,
	}
	sessions[player] = session
	waitForMode()
	-- a previous session of the same user in THIS server must finish its final save first
	local deadline = os.clock() + 30
	while releasing[session.UserId] ~= nil and os.clock() < deadline do
		task.wait(0.2)
	end
	if sessions[player] ~= session then
		return
	end
	if mode ~= "DataStore" then
		local profile = ProfileSchema.Migrate(nil)
		profile.Created = os.time()
		finishLoad(session, profile, false)
		return
	end
	local ok, data, reason = loadRecord(session)
	if reason == "left" or player.Parent == nil or sessions[player] ~= session then
		-- the player left while loading; if we took the lock, hand it back (data unchanged)
		if ok then
			local okMigrate, profile = pcall(ProfileSchema.Migrate, data)
			if okMigrate then
				session.Profile = profile
				session.Persistent = true
				saveSession(session, true)
			end
		end
		session.State = "Released"
		if sessions[player] == session then
			sessions[player] = nil
		end
		return
	end
	if not ok then
		finishLoad(session, ProfileSchema.Migrate(nil), false)
		return
	end
	local okMigrate, profile, fresh = pcall(ProfileSchema.Migrate, data)
	if not okMigrate then
		-- corrupt data: play on a temporary profile and never overwrite what is stored
		warn(("[DataService] migrate %s failed: %s"):format(session.Key, tostring(profile)))
		finishLoad(session, ProfileSchema.Migrate(nil), false)
		return
	end
	if fresh or profile.Created == 0 then
		profile.Created = os.time()
	end
	finishLoad(session, profile, true)
	if sessions[player] ~= session or player.Parent == nil or shuttingDown then
		releaseSession(session)
	end
end

local function decideMode()
	if RunService:IsStudio() and game.PlaceId == 0 then
		mode = "Memory"
		return
	end
	local okService, service = pcall(function()
		return game:GetService("DataStoreService")
	end)
	if not okService or service == nil then
		mode = "Memory"
		return
	end
	dataStoreService = service
	local okStore, result = pcall(function()
		return service:GetDataStore(Config.Data.StoreName)
	end)
	if not okStore then
		warn("[DataService] DataStore unavailable (" .. tostring(result) .. ") — profiles are kept in memory only")
		mode = "Memory"
		return
	end
	store = result
	if RunService:IsStudio() then
		-- Studio without "Enable Studio Access to API Services" fails every request: detect it once
		local okProbe, err = pcall(function()
			return result:GetAsync("__sv_probe")
		end)
		if not okProbe then
			local msg = string.lower(tostring(err))
			if
				string.find(msg, "403")
				or string.find(msg, "studio")
				or string.find(msg, "publish")
				or string.find(msg, "api")
			then
				warn("[DataService] Studio has no DataStore access — profiles are kept in memory only")
				mode = "Memory"
				return
			end
		end
	end
	mode = "DataStore"
end

-- Public API --------------------------------------------------------------------------------------------------

function DataService.Get(player: Player): any
	local session = sessions[player]
	if session and session.Profile and session.State ~= "Loading" then
		return session.Profile
	end
	return nil
end

function DataService.WaitFor(player: Player, timeout: number?): any
	local deadline = os.clock() + (timeout or 30)
	repeat
		local profile = DataService.Get(player)
		if profile then
			return profile
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return DataService.Get(player)
end

function DataService.IsReady(player: Player): boolean
	return DataService.Get(player) ~= nil
end

function DataService.IsPersistent(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Persistent and not session.LockLost
end

function DataService.Mode(): string
	return mode
end

function DataService.LanguageOf(player: Player): string
	return languageOf(player, DataService.Get(player))
end

function DataService.Update(player: Player, fn: (any) -> ()): boolean
	local session = sessions[player]
	local profile = if session then session.Profile else nil
	if session == nil or profile == nil or session.State == "Loading" then
		return false
	end
	local ok, err = pcall(fn, profile)
	if not ok then
		warn("[DataService] Update failed for " .. player.Name .. ": " .. tostring(err))
	end
	session.ChangeCount += 1
	session.ViewCache = nil
	scheduleChanged(session)
	DataService.Replicate(player)
	return ok
end

function DataService.View(player: Player): any
	local session = sessions[player]
	if session == nil or session.Profile == nil then
		return nil
	end
	if session.ViewCache and os.clock() - session.ViewAt < VIEW_CACHE_TIME then
		return session.ViewCache
	end
	return buildView(session)
end

function DataService.RequestSave(player: Player)
	local session = sessions[player]
	if session == nil or session.EarlySaveQueued or mode ~= "DataStore" or not session.Persistent then
		return
	end
	session.EarlySaveQueued = true
	local wait = math.max(1, session.LastSave + EARLY_SAVE_MIN_GAP - os.clock())
	task.delay(wait, function()
		session.EarlySaveQueued = false
		if session.State == "Ready" and session.ChangeCount ~= session.SavedCount then
			saveSession(session, false)
		end
	end)
end

-- Lifecycle -----------------------------------------------------------------------------------------------------

local function autosaveStep()
	local now = os.clock()
	for _, session in sessions do
		if session.State == "Ready" and session.Persistent and not session.LockLost and now >= session.NextAutosave then
			session.NextAutosave = now + Config.Data.AutosaveInterval
			task.spawn(saveSession, session, false)
		end
	end
end

local function onClose()
	shuttingDown = true
	if mode ~= "DataStore" then
		return
	end
	local pending = 0
	for _, session in sessions do
		if session.State == "Ready" then
			pending += 1
			task.spawn(function()
				local ok, err = pcall(releaseSession, session)
				if not ok then
					warn("[DataService] close save failed: " .. tostring(err))
				end
				pending -= 1
			end)
		end
	end
	local deadline = os.clock() + CLOSE_TIMEOUT
	while os.clock() < deadline do
		local inFlight = pending > 0
		for _ in releasing do
			inFlight = true
			break
		end
		if not inFlight then
			break
		end
		task.wait(0.1)
	end
end

-- Test hooks (Lune): drive the real session flow against a fake store without Start().
function DataService._TestSetup(opts: { [string]: any })
	store = opts.Store
	mode = opts.Mode or "DataStore"
	jobId = opts.JobId or "test-job"
	dataStoreService = nil
end
DataService._StartSession = startSession
function DataService._ReleaseSession(player: Player)
	local session = sessions[player]
	if session then
		releaseSession(session)
	end
end
function DataService._Save(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and saveSession(session, false)
end

function DataService.Init()
	QueueService = tryService("QueueService")
end

function DataService.Start()
	jobId = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))
	pcall(function()
		game:BindToClose(onClose)
	end)
	Net.Server.OnInvoke("GetProfile", function(player: Player)
		if DataService.WaitFor(player, 15) == nil then
			return nil
		end
		return DataService.View(player)
	end)
	Players.PlayerAdded:Connect(startSession)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			releaseSession(session)
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(startSession, player)
	end
	local okMode, err = pcall(decideMode)
	if not okMode then
		warn("[DataService] mode detection failed: " .. tostring(err))
		mode = "Memory"
	end
	print("[DataService] profiles: " .. mode)
	modeDecided:Fire()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_TICK)
			local ok, stepErr = pcall(autosaveStep)
			if not ok then
				warn("[DataService] autosave: " .. tostring(stepErr))
			end
		end
	end)
end

return DataService
