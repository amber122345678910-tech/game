--!strict
-- Сохранение данных игроков (DataStore) с блокировкой сессии.
--  * Данные одного игрока может менять только один сервер: в записи хранится "замок"
--    (идентификатор сессии + время). Чужой свежий замок ждём, устаревший забираем.
--  * Каждое сохранение проверяет, что замок всё ещё наш, иначе не перезаписывает данные.
--  * Автосохранение, сохранение при выходе и при выключении сервера (BindToClose).
--  * Если DataStore недоступен (Studio без доступа к API), игра работает без сохранений.
-- Схема данных (значения по умолчанию и проверка) задаётся модулем PlayerData.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

type Data = PlayerData.Data

type StoredRecord = {
	Data: any,
	Lock: { Id: string, Time: number }?,
}

type Session = {
	Player: Player,
	Data: Data,
	Persistent: boolean, -- false = DataStore недоступен или замок не удалось взять
	Released: boolean,
	LockId: string,
	LastSave: number,
}

local DataService = {}

-- (player, data) — данные загружены (или созданы по умолчанию)
DataService.Loaded = Signal.new() :: Signal.Signal<Player, Data>
-- (player) — данные изменились (через DataService.update)
DataService.Changed = Signal.new() :: Signal.Signal<Player>
-- (player) — вызывается перед каждым сохранением, синхронно
DataService.BeforeSave = Signal.new() :: Signal.Signal<Player>

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 75
local LOCK_STALE_AFTER = 150 -- замок без обновления дольше этого считается брошенным
local LOCK_WAIT_TRIES = 3 -- сколько раз подождать чужой свежий замок (по 4 секунды), потом забрать
local RETRIES = 5

local store: DataStore? = nil
local storeDisabled = false
local sessions: { [Player]: Session } = {}
local inFlight = 0
local closing = false
local beforeSaveHooks: { (Player, Data) -> () } = {}

local function now(): number
	return os.time()
end

local function isFatal(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "must publish", 1, true) ~= nil
		or string.find(lower, "not allowed", 1, true) ~= nil
		or string.find(lower, "cannot write to datastore from studio", 1, true) ~= nil
end

local function getStore(): DataStore?
	if storeDisabled then
		return nil
	end
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return result
	end
	storeDisabled = true
	warn("[DataService] DataStore недоступен, игра без сохранений: " .. tostring(result))
	return nil
end

-- Повторять вызов с паузами. Возвращает (успех, результат).
local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local delay = 1
	for attempt = 1, RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		local message = tostring(result)
		if isFatal(message) then
			if not storeDisabled then
				storeDisabled = true
				warn("[DataService] Сохранения выключены (нет доступа к API): " .. message)
			end
			return false, nil
		end
		warn(string.format("[DataService] %s: попытка %d/%d не удалась: %s", label, attempt, RETRIES, message))
		if attempt < RETRIES then
			task.wait(delay)
			delay = math.min(delay * 2, 8)
		end
	end
	return false, nil
end

local function key(player: Player): string
	return "u_" .. tostring(player.UserId)
end

-- Загрузить данные и взять замок. Возвращает (данные, сохранять ли).
local function load(player: Player, lockId: string): (Data, boolean)
	local ds = getStore()
	if not ds then
		return PlayerData.default(), false
	end
	for waitTry = 0, LOCK_WAIT_TRIES do
		local blockedByOther = false
		local loaded: any = nil
		local ok = withRetries("load " .. player.Name, function()
			(ds :: DataStore):UpdateAsync(key(player), function(old: any)
				blockedByOther = false
				local record: StoredRecord = if typeof(old) == "table" then old else { Data = nil, Lock = nil }
				local lock = record.Lock
				if
					lock
					and typeof(lock) == "table"
					and lock.Id ~= lockId
					and typeof(lock.Time) == "number"
					and now() - lock.Time < LOCK_STALE_AFTER
					and waitTry < LOCK_WAIT_TRIES
				then
					-- замок держит другая сессия: ничего не меняем, подождём
					blockedByOther = true
					return nil
				end
				loaded = record.Data
				return { Data = record.Data, Lock = { Id = lockId, Time = now() } }
			end)
			return true
		end)
		if not ok then
			-- DataStore не отвечает: играем без сохранений, чтобы не затереть настоящие данные
			return PlayerData.default(), false
		end
		if not blockedByOther then
			return PlayerData.reconcile(loaded), true
		end
		if not player.Parent then
			break
		end
		task.wait(4)
	end
	return PlayerData.default(), false
end

-- Сохранить сессию. release = снять замок (игрок вышел).
local function save(session: Session, release: boolean)
	if not session.Persistent then
		return
	end
	local ds = getStore()
	if not ds then
		return
	end
	DataService.BeforeSave:Fire(session.Player)
	for _, hook in beforeSaveHooks do
		local okHook, err = pcall(hook, session.Player, session.Data)
		if not okHook then
			warn("[DataService] before-save hook: " .. tostring(err))
		end
	end
	local snapshot = PlayerData.serialize(session.Data)
	inFlight += 1
	local lostLock = false
	withRetries("save " .. session.Player.Name, function()
		(ds :: DataStore):UpdateAsync(key(session.Player), function(old: any)
			lostLock = false
			local record: StoredRecord = if typeof(old) == "table" then old else { Data = nil, Lock = nil }
			local lock = record.Lock
			if lock and typeof(lock) == "table" and lock.Id ~= session.LockId then
				-- другой сервер забрал данные (например, мы долго не сохранялись) — не трогаем
				lostLock = true
				return nil
			end
			return {
				Data = snapshot,
				Lock = if release then nil else { Id = session.LockId, Time = now() },
			}
		end)
		return true
	end)
	inFlight -= 1
	session.LastSave = os.clock()
	if lostLock then
		warn("[DataService] Замок данных перехвачен другим сервером, сохранения для " .. session.Player.Name .. " отключены")
		session.Persistent = false
	end
end

----------------------------------------------------------------------
-- Публичное API
----------------------------------------------------------------------

function DataService.get(player: Player): Data?
	local s = sessions[player]
	return if s then s.Data else nil
end

function DataService.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function DataService.isPersistent(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and s.Persistent
end

-- Изменить данные игрока. fn получает таблицу данных и меняет её на месте.
function DataService.update(player: Player, fn: (Data) -> ()): boolean
	local s = sessions[player]
	if not s or s.Released then
		return false
	end
	fn(s.Data)
	DataService.Changed:Fire(player)
	return true
end

-- Сообщить, что данные изменены напрямую (без update)
function DataService.markChanged(player: Player)
	if sessions[player] then
		DataService.Changed:Fire(player)
	end
end

function DataService.addBeforeSave(fn: (Player, Data) -> ())
	table.insert(beforeSaveHooks, fn)
end

-- Ждать загрузки данных игрока (или его выхода). Возвращает данные или nil.
function DataService.waitFor(player: Player, timeout: number?): Data?
	local deadline = os.clock() + (timeout or 60)
	while player.Parent and not sessions[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.get(player)
end

function DataService.saveNow(player: Player)
	local s = sessions[player]
	if s and not s.Released then
		task.spawn(save, s, false)
	end
end

local function onPlayerAdded(player: Player)
	local lockId = HttpService:GenerateGUID(false)
	local data, persistent = load(player, lockId)
	if not player.Parent then
		-- ушёл, пока грузились: сразу снять замок
		if persistent then
			local tmp: Session = { Player = player, Data = data, Persistent = true, Released = true, LockId = lockId, LastSave = 0 }
			save(tmp, true)
		end
		return
	end
	if not persistent and not storeDisabled and getStore() ~= nil then
		warn("[DataService] " .. player.Name .. ": данные не загрузились, прогресс в этой сессии не сохранится")
	end
	PlayerData.onSessionStart(data, now())
	local session: Session = {
		Player = player,
		Data = data,
		Persistent = persistent,
		Released = false,
		LockId = lockId,
		LastSave = os.clock(),
	}
	sessions[player] = session
	DataService.Loaded:Fire(player, data)
	DataService.Changed:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	s.Released = true
	save(s, true)
	sessions[player] = nil
end

function DataService.start()
	if RunService:IsStudio() then
		-- в Studio проверяем доступ сразу, чтобы не ждать ретраев при входе
		local ds = getStore()
		if ds then
			local ok, err = pcall(function()
				return (ds :: DataStore):GetAsync("__probe")
			end)
			if not ok and isFatal(tostring(err)) then
				storeDisabled = true
				warn("[DataService] Studio без доступа к API — игра работает без сохранений (это нормально)")
			end
		end
	end

	Players.PlayerAdded:Connect(function(p)
		task.spawn(onPlayerAdded, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		task.spawn(onPlayerRemoving, p)
	end)

	-- автосохранение (по одному игроку, чтобы не упираться в лимиты DataStore)
	task.spawn(function()
		while not closing do
			task.wait(5)
			for _, s in sessions do
				if not closing and not s.Released and os.clock() - s.LastSave >= AUTOSAVE_INTERVAL then
					save(s, false)
					task.wait(1)
				end
			end
		end
	end)

	game:BindToClose(function()
		closing = true
		for player, s in sessions do
			if not s.Released then
				s.Released = true
				task.spawn(save, s, true)
			end
			sessions[player] = nil
		end
		local deadline = os.clock() + 25
		task.wait(0.5)
		while inFlight > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return DataService
