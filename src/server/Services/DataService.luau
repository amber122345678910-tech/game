--!strict
-- Профили игроков (DataStore) с блокировкой сессии: Амбер, опыт, перки, статистика, настройки.
-- Без доступа к DataStore (Studio, неопубликованное место) игра работает без сохранений.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local Remotes = require(Shared:WaitForChild("Remotes"))

export type ProfileData = {
	Version: number,
	Amber: number,
	Xp: number,
	Perks: { [string]: number },
	NightsSurvived: number,
	Wins: number,
	Runs: number,
	BestNights: number,
	Settings: { [string]: any },
}

type StoredRecord = {
	Data: ProfileData?,
	Lock: { Job: string, Time: number }?,
}

type Session = {
	Player: Player,
	Data: ProfileData,
	Loaded: boolean,
	Persistent: boolean,
	Released: boolean,
	LockId: string,
	ReplicateQueued: boolean,
	Leaderstats: { Level: IntValue, Nights: IntValue }?,
}

local DataService = {}

DataService.Loaded = Signal.new() :: Signal.Signal<Player, ProfileData>

local AUTOSAVE_INTERVAL = 90
local LOCK_TIMEOUT = 120
local LOAD_RETRIES = 5

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}
local SERVER_ID = HttpService:GenerateGUID(false)
local inFlightSaves = 0
local pendingRelease: { [number]: boolean } = {}

local ALLOWED_SETTINGS: { [string]: string } = {
	Brightness = "number",
	Music = "number",
	Sfx = "number",
	HeadBob = "boolean",
	Vhs = "boolean",
	Language = "string",
	ShowTips = "boolean",
	FlashlightColor = "string",
}

local function defaultData(): ProfileData
	return {
		Version = Config.DataVersion,
		Amber = 0,
		Xp = 0,
		Perks = {},
		NightsSurvived = 0,
		Wins = 0,
		Runs = 0,
		BestNights = 0,
		Settings = {},
	}
end

local function num(v: any, fallback: number, minValue: number, maxValue: number): number
	if typeof(v) ~= "number" or v ~= v then
		return fallback
	end
	return math.clamp(math.floor(v), minValue, maxValue)
end

local function sanitizeSettings(raw: any): { [string]: any }
	local out: { [string]: any } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for key, kind in ALLOWED_SETTINGS do
		local v = raw[key]
		if typeof(v) == kind then
			if kind == "number" then
				if v == v then
					out[key] = math.clamp(v, 0, 1)
				end
			elseif kind == "string" then
				if #v <= 16 then
					out[key] = v
				end
			else
				out[key] = v
			end
		end
	end
	return out
end

local function reconcile(raw: any): ProfileData
	local d = defaultData()
	if typeof(raw) ~= "table" then
		return d
	end
	d.Amber = num(raw.Amber, 0, 0, 1e9)
	d.Xp = num(raw.Xp, 0, 0, 1e9)
	d.NightsSurvived = num(raw.NightsSurvived, 0, 0, 1e9)
	d.Wins = num(raw.Wins, 0, 0, 1e9)
	d.Runs = num(raw.Runs, 0, 0, 1e9)
	d.BestNights = num(raw.BestNights, 0, 0, 1e6)
	if typeof(raw.Perks) == "table" then
		for id, level in raw.Perks do
			local def = Config.Perks[id]
			if def then
				local n = num(level, 0, 0, #def.Costs)
				if n > 0 then
					d.Perks[id] = n
				end
			end
		end
	end
	d.Settings = sanitizeSettings(raw.Settings)
	return d
end

local function isFatalError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "not allowed", 1, true) ~= nil
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local delay = 1
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		if isFatalError(tostring(result)) then
			store = nil
			return false, nil
		end
		if attempt < 4 then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function setupLeaderstats(session: Session)
	local f = Instance.new("Folder")
	f.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = Config.levelFromXp(session.Data.Xp)
	level.Parent = f
	local nights = Instance.new("IntValue")
	nights.Name = "Nights"
	nights.Value = session.Data.NightsSurvived
	nights.Parent = f
	f.Parent = session.Player
	session.Leaderstats = { Level = level, Nights = nights }
end

local function snapshot(data: ProfileData): Remotes.ProfileSnapshot
	local level = Config.levelFromXp(data.Xp)
	return {
		Amber = data.Amber,
		Xp = data.Xp,
		Level = level,
		Title = Config.titleForLevel(level),
		Perks = table.clone(data.Perks),
		NightsSurvived = data.NightsSurvived,
		Wins = data.Wins,
		BestNights = data.BestNights,
		Settings = table.clone(data.Settings),
	}
end

local function loadRecord(player: Player, lockId: string): (ProfileData?, boolean)
	local ds = store
	if not ds then
		return nil, false
	end
	local key = keyFor(player)
	for attempt = 1, LOAD_RETRIES do
		local lockedByOther = false
		local newerSchema = false
		local loaded: ProfileData? = nil
		local ok = withRetries("Load " .. key, function()
			ds:UpdateAsync(key, function(old: any)
				local record: StoredRecord = if typeof(old) == "table" then old else {}
				local lock = record.Lock
				local now = os.time()
				if typeof(lock) == "table" and lock.Job ~= lockId and typeof(lock.Time) == "number" and now - lock.Time < LOCK_TIMEOUT and attempt < LOAD_RETRIES then
					lockedByOther = true
					return nil
				end
				lockedByOther = false
				local raw = record.Data
				if typeof(raw) == "table" and typeof(raw.Version) == "number" and raw.Version > Config.DataVersion then
					newerSchema = true
					return nil
				end
				local data = reconcile(raw)
				loaded = data
				return { Data = data, Lock = { Job = lockId, Time = now } }
			end)
			return true
		end)
		if not ok or newerSchema then
			return nil, false
		end
		if not lockedByOther and loaded then
			return loaded, true
		end
		task.wait(4)
		if player.Parent ~= Players then
			return nil, false
		end
	end
	return nil, false
end

local function saveRecord(session: Session, release: boolean): boolean
	local ds = store
	if not ds or not session.Persistent then
		return false
	end
	local key = keyFor(session.Player)
	local data = session.Data
	local lockId = session.LockId
	inFlightSaves += 1
	local ok = withRetries("Save " .. key, function()
		ds:UpdateAsync(key, function(old: any)
			local record: StoredRecord = if typeof(old) == "table" then old else {}
			local lock = record.Lock
			if typeof(lock) ~= "table" or lock.Job ~= lockId then
				warn("[DataService] Session lock lost, skip save for " .. key)
				return nil
			end
			return { Data = data, Lock = if release then nil else { Job = lockId, Time = os.time() } }
		end)
		return true
	end)
	inFlightSaves -= 1
	return ok
end

local function releaseSession(session: Session)
	if session.Released then
		return
	end
	session.Released = true
	local userId = session.Player.UserId
	pendingRelease[userId] = true
	saveRecord(session, true)
	pendingRelease[userId] = nil
end

local function onPlayerAdded(player: Player)
	local session: Session = {
		Player = player,
		Data = defaultData(),
		Loaded = false,
		Persistent = false,
		Released = false,
		LockId = SERVER_ID .. ":" .. HttpService:GenerateGUID(false),
		ReplicateQueued = false,
		Leaderstats = nil,
	}
	sessions[player] = session
	local waitStarted = os.clock()
	while pendingRelease[player.UserId] and os.clock() - waitStarted < 30 do
		task.wait(0.25)
	end
	local data, persistent = loadRecord(player, session.LockId)
	if player.Parent ~= Players then
		if persistent then
			session.Data = data or session.Data
			session.Persistent = true
			releaseSession(session)
		end
		if sessions[player] == session then
			sessions[player] = nil
		end
		return
	end
	if data then
		session.Data = data
	end
	session.Persistent = persistent
	session.Loaded = true
	setupLeaderstats(session)
	DataService.replicate(player)
	if not persistent then
		task.delay(3, function()
			if player.Parent == Players then
				if RunService:IsStudio() then
					Remotes.Notify:FireClient(player, "N_StudioSaves", "info")
				else
					Remotes.Notify:FireClient(player, "N_SavesUnavailable", "warning")
				end
			end
		end)
	end
	DataService.Loaded:Fire(player, session.Data)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	if session.Loaded then
		releaseSession(session)
	end
	if sessions[player] == session then
		sessions[player] = nil
	end
end

function DataService.init()
	local storeName = Config.DataStoreName .. (if RunService:IsStudio() then "_Studio" else "")
	local ok, result = pcall(function()
		if game.PlaceId == 0 then
			error("Place is not published (PlaceId = 0)")
		end
		return DataStoreService:GetDataStore(storeName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable, running without saves: " .. tostring(result))
		store = nil
	end
	local probeStore = store
	if probeStore and RunService:IsStudio() then
		local probeOk, probeErr = pcall(function()
			return probeStore:GetAsync("__probe")
		end)
		if not probeOk then
			warn("[DataService] DataStore probe failed in Studio, saves disabled: " .. tostring(probeErr))
			store = nil
		end
	end

	Remotes.SaveSettings.OnServerEvent:Connect(function(player: Player, settings: any)
		local data = DataService.get(player)
		if not data then
			return
		end
		data.Settings = sanitizeSettings(settings)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, session in sessions do
				if session.Loaded and not session.Released then
					task.spawn(saveRecord, session, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		for _, session in sessions do
			if session.Loaded and not session.Released then
				task.spawn(releaseSession, session)
			end
		end
		task.wait()
		local started = os.clock()
		while inFlightSaves > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

function DataService.get(player: Player): ProfileData?
	local session = sessions[player]
	if session and session.Loaded then
		return session.Data
	end
	return nil
end

function DataService.isPersistent(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Persistent
end

function DataService.replicate(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded or session.ReplicateQueued then
		return
	end
	session.ReplicateQueued = true
	task.defer(function()
		session.ReplicateQueued = false
		if player.Parent ~= Players then
			return
		end
		local stats = session.Leaderstats
		if stats then
			stats.Level.Value = Config.levelFromXp(session.Data.Xp)
			stats.Nights.Value = session.Data.NightsSurvived
		end
		Remotes.Data:FireClient(player, snapshot(session.Data))
	end)
end

function DataService.perkLevel(player: Player, perkId: string): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return data.Perks[perkId] or 0
end

function DataService.perkValue(player: Player, perkId: string): number
	return Config.perkValue(perkId, DataService.perkLevel(player, perkId))
end

function DataService.addAmber(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Amber += math.floor(amount)
	DataService.replicate(player)
end

function DataService.addXp(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Xp += math.floor(amount)
	DataService.replicate(player)
end

function DataService.tryBuyPerk(player: Player, perkId: string): (boolean, string)
	local data = DataService.get(player)
	local def = Config.Perks[perkId]
	if not data or not def then
		return false, "N_CantNow"
	end
	local level = data.Perks[perkId] or 0
	if level >= #def.Costs then
		return false, "N_MaxOwned"
	end
	local cost = def.Costs[level + 1]
	if data.Amber < cost then
		return false, "N_NotEnoughAmber"
	end
	data.Amber -= cost
	data.Perks[perkId] = level + 1
	DataService.replicate(player)
	task.spawn(function()
		local session = sessions[player]
		if session then
			saveRecord(session, false)
		end
	end)
	return true, "N_PerkBought"
end

-- Итоги забега: ночей пережито, победа
function DataService.recordRun(player: Player, nights: number, won: boolean)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.Runs += 1
	if won then
		data.Wins += 1
	end
	if nights > data.BestNights then
		data.BestNights = nights
	end
	DataService.replicate(player)
	task.spawn(function()
		local session = sessions[player]
		if session then
			saveRecord(session, false)
		end
	end)
end

function DataService.recordNight(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.NightsSurvived += 1
	DataService.replicate(player)
end

return DataService
