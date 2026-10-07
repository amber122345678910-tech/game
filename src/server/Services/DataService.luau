--!strict
-- Сохранение данных игроков (DataStore) с простой блокировкой сессии.
-- Если DataStore недоступен (например, в Studio без доступа к API), игра работает
-- без сохранений и не падает.

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
	Coins: number,
	Inventory: { [string]: number },
	StormLevel: number,
	BestLevel: number,
	TutorialDone: boolean,
	StarterClaimed: boolean,
	Layout: string,
	StormsSurvived: number,
	StormsPlayed: number,
}

type StoredRecord = {
	Data: ProfileData?,
	Lock: { Job: string, Time: number }?,
}

type Session = {
	Player: Player,
	Data: ProfileData,
	Loaded: boolean,
	Persistent: boolean, -- false = DataStore недоступен или чужая блокировка не снялась
	Released: boolean,
	LockId: string, -- уникален для каждой сессии игрока (не только для сервера)
	ReplicateQueued: boolean,
	Leaderstats: { Coins: IntValue, Level: IntValue }?,
}

local DataService = {}

DataService.Loaded = Signal.new() :: Signal.Signal<Player, ProfileData>

-- Вызываются синхронно перед каждым сохранением (например, дописать раскладку бункера).
local preSaveHooks: { (Player) -> () } = {}
function DataService.addPreSaveHook(fn: (Player) -> ())
	table.insert(preSaveHooks, fn)
end
local function runPreSaveHooks(player: Player)
	for _, fn in preSaveHooks do
		local ok, err = pcall(fn, player)
		if not ok then
			warn("[DataService] pre-save hook failed: " .. tostring(err))
		end
	end
end

local AUTOSAVE_INTERVAL = 90
local LOCK_TIMEOUT = 120 -- через сколько секунд чужая блокировка считается устаревшей
local LOAD_RETRIES = 5

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}
-- Идентификатор этого сервера для блокировки (в Studio game.JobId пустой, поэтому GUID).
local SERVER_ID = HttpService:GenerateGUID(false)
-- Сохранения, которые сейчас выполняются (BindToClose ждёт их все).
local inFlightSaves = 0
-- Игроки, чьё финальное сохранение ещё идёт (на случай быстрого перезахода на тот же сервер).
local pendingRelease: { [number]: boolean } = {}

local function defaultData(): ProfileData
	return {
		Version = Config.DataVersion,
		Coins = if RunService:IsStudio() then Config.Economy.StudioStartingCoins else Config.Economy.StartingCoins,
		Inventory = {},
		StormLevel = 1,
		BestLevel = 1,
		TutorialDone = false,
		StarterClaimed = false,
		Layout = "",
		StormsSurvived = 0,
		StormsPlayed = 0,
	}
end

local function num(v: any, fallback: number, minValue: number, maxValue: number): number
	if typeof(v) ~= "number" or v ~= v then
		return fallback
	end
	return math.clamp(math.floor(v), minValue, maxValue)
end

-- Приводим сохранённые данные к актуальной схеме (миграции и защита от мусора).
local function reconcile(raw: any): ProfileData
	local d = defaultData()
	if typeof(raw) ~= "table" then
		return d
	end
	d.Coins = num(raw.Coins, d.Coins, 0, 1e12)
	d.StormLevel = num(raw.StormLevel, 1, 1, Config.Economy.MaxLevel)
	d.BestLevel = num(raw.BestLevel, d.StormLevel, 1, Config.Economy.MaxLevel)
	d.TutorialDone = raw.TutorialDone == true
	d.StarterClaimed = raw.StarterClaimed == true
	d.Layout = if typeof(raw.Layout) == "string" then raw.Layout else ""
	d.StormsSurvived = num(raw.StormsSurvived, 0, 0, 1e9)
	d.StormsPlayed = num(raw.StormsPlayed, 0, 0, 1e9)
	if typeof(raw.Inventory) == "table" then
		for id, count in raw.Inventory do
			if Config.getBlock(id) then
				local n = num(count, 0, 0, 1e6)
				if n > 0 then
					d.Inventory[id] = n
				end
			end
		end
	end
	return d
end

-- Ошибки, при которых повторять бессмысленно (нет доступа к API в Studio и т.п.).
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
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Монеты"
	coins.Value = session.Data.Coins
	coins.Parent = folder
	local level = Instance.new("IntValue")
	level.Name = "Уровень"
	level.Value = session.Data.StormLevel
	level.Parent = folder
	folder.Parent = session.Player
	session.Leaderstats = { Coins = coins, Level = level }
end

local function snapshot(data: ProfileData): Remotes.DataSnapshot
	return {
		Coins = data.Coins,
		Inventory = table.clone(data.Inventory),
		StormLevel = data.StormLevel,
		BestLevel = data.BestLevel,
		TutorialDone = data.TutorialDone,
		StarterClaimed = data.StarterClaimed,
		StormsSurvived = data.StormsSurvived,
		StormsPlayed = data.StormsPlayed,
	}
end

-- Загрузка с блокировкой: пишем свою JobId в запись. Если запись заблокирована другим
-- сервером недавно — ждём и пробуем снова, потом забираем блокировку.
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
				if
					typeof(lock) == "table"
					and lock.Job ~= lockId
					and typeof(lock.Time) == "number"
					and now - lock.Time < LOCK_TIMEOUT
					and attempt < LOAD_RETRIES
				then
					lockedByOther = true
					return nil -- не меняем запись
				end
				lockedByOther = false
				local raw = record.Data
				if typeof(raw) == "table" and typeof(raw.Version) == "number" and raw.Version > Config.DataVersion then
					-- данные новее этой версии игры: не трогаем их
					newerSchema = true
					return nil
				end
				local data = reconcile(raw)
				loaded = data
				return {
					Data = data,
					Lock = { Job = lockId, Time = now },
				}
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
			-- хуки (например, раскладка бункера) — прямо в транзакции, чтобы инвентарь и
			-- раскладка попали в запись согласованными
			runPreSaveHooks(session.Player)
			local record: StoredRecord = if typeof(old) == "table" then old else {}
			local lock = record.Lock
			if typeof(lock) ~= "table" or lock.Job ~= lockId then
				-- Блокировку забрал (или снял) другой сервер — не перезаписываем его данные.
				warn("[DataService] Session lock lost, skip save for " .. key)
				return nil
			end
			return {
				Data = data,
				Lock = if release then nil else { Job = lockId, Time = os.time() },
			}
		end)
		return true
	end)
	inFlightSaves -= 1
	return ok
end

-- Финальное сохранение с освобождением блокировки.
local function releaseSession(session: Session)
	if session.Released then
		return
	end
	session.Released = true
	runPreSaveHooks(session.Player)
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

	-- быстрый перезаход на этот же сервер: ждём, пока допишется прошлое сохранение
	local waitStarted = os.clock()
	while pendingRelease[player.UserId] and os.clock() - waitStarted < 30 do
		task.wait(0.25)
	end

	local data, persistent = loadRecord(player, session.LockId)
	if player.Parent ~= Players then
		-- игрок ушёл во время загрузки: снимаем блокировку, данные не меняем
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
				Remotes.Notify:FireClient(player, "Сохранения недоступны: прогресс не будет сохранён.", "warning")
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
	-- В Studio используем отдельное хранилище, чтобы тесты не портили данные живой игры.
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
	-- В Studio без "Enable Studio Access to API Services" запросы падают — проверяем сразу,
	-- чтобы игроки не ждали повторных попыток.
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

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Автосохранение
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, session in sessions do
				if session.Loaded and not session.Released then
					runPreSaveHooks(session.Player)
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
		-- ждём и свои сохранения, и уже начатые в PlayerRemoving
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

function DataService.waitForData(player: Player, timeout: number?): ProfileData?
	local limit = timeout or 30
	local started = os.clock()
	while player.Parent == Players and os.clock() - started < limit do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return DataService.get(player)
end

-- Отправить клиенту свежий снимок (с объединением нескольких изменений в одно сообщение).
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
			stats.Coins.Value = math.min(session.Data.Coins, 2 ^ 31 - 1)
			stats.Level.Value = session.Data.StormLevel
		end
		Remotes.DataUpdated:FireClient(player, snapshot(session.Data))
	end)
end

function DataService.addCoins(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Coins += math.floor(amount)
	DataService.replicate(player)
end

function DataService.trySpend(player: Player, amount: number): boolean
	local data = DataService.get(player)
	if not data or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= math.floor(amount)
	DataService.replicate(player)
	return true
end

function DataService.getBlockCount(player: Player, blockId: string): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return data.Inventory[blockId] or 0
end

function DataService.addBlocks(player: Player, blockId: string, count: number)
	local data = DataService.get(player)
	if not data or count <= 0 or not Config.getBlock(blockId) then
		return
	end
	data.Inventory[blockId] = (data.Inventory[blockId] or 0) + math.floor(count)
	DataService.replicate(player)
end

function DataService.takeBlocks(player: Player, blockId: string, count: number): boolean
	local data = DataService.get(player)
	if not data or count <= 0 then
		return false
	end
	local have = data.Inventory[blockId] or 0
	if have < count then
		return false
	end
	local left = have - count
	data.Inventory[blockId] = if left > 0 then left else nil
	DataService.replicate(player)
	return true
end

function DataService.setLayout(player: Player, layout: string)
	local data = DataService.get(player)
	if data then
		data.Layout = layout
	end
end

function DataService.isPersistent(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Persistent
end

return DataService
