--!strict
-- STRETCH-POP · Профили игроков в DataStore.
-- • Сессионный замок (JobId + время) внутри записи: два сервера не перетрут прогресс друг друга.
-- • Все чтения проходят через ProfileTemplate.Sanitize (миграции + защита от битых данных).
-- • Автосейв, сохранение при выходе и в BindToClose; повторы с экспоненциальной задержкой.
-- • Studio без доступа к API / неопубликованное место → сессионный режим без сохранения (с предупреждением).
-- • Значения для клиента отдаются атрибутами Player (реплицируются автоматически) + leaderstats.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local ProfileTemplate = require(Shared.Data.ProfileTemplate)
local Signal = require(Shared.Util.Signal)

local STORE_NAME = "StretchPop_Profiles_v1"
local SESSION_LOCK_TIMEOUT = 1800
local AUTOSAVE_INTERVAL = 75
local LOAD_ATTEMPTS = 6
local LOCK_RETRY_DELAY = 4
local SAVE_ATTEMPTS = 4
local CLOSE_SAVE_BUDGET = 25

type Session = {
	Player: Player,
	Key: string,
	Profile: Types.PlayerProfile,
	Offline: boolean,
	Released: boolean,
	Saving: boolean,
	PlayClock: number,
	Leaderstats: Folder,
	CoinsValue: IntValue,
	RebirthsValue: IntValue,
}

local PlayerDataService = {
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, Types.PlayerProfile>,
	ProfileChanged = Signal.new() :: Signal.Signal<Player, Types.PlayerProfile>,
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local store: DataStore? = nil
local offlineMode = false
local offlineWarned = false
local initialized = false

local function enterOfflineMode(reason: string)
	offlineMode = true
	if not offlineWarned then
		offlineWarned = true
		warn(
			"[StretchPop] DataStore недоступен ("
				.. reason
				.. "). Прогресс живёт только в этой сессии. "
				.. "Для сохранений: опубликуй место и включи Game Settings → Security → Enable Studio Access to API Services."
		)
	end
end

local function resolveStore(): DataStore?
	if offlineMode then
		return nil
	end
	if store then
		return store
	end
	if game.PlaceId == 0 then
		enterOfflineMode("место не опубликовано")
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return result
	end
	enterOfflineMode(tostring(result))
	return nil
end

local function syncReplicatedState(session: Session)
	local player = session.Player
	local profile = session.Profile
	local location = ProfileTemplate.GetLocation(profile, profile.ActiveLocation)
	player:SetAttribute("Coins", profile.Coins)
	player:SetAttribute("Stat_Elasticity", profile.Stats.Elasticity)
	player:SetAttribute("Stat_SpringPower", profile.Stats.SpringPower)
	player:SetAttribute("Stat_SmashMass", profile.Stats.SmashMass)
	player:SetAttribute("Glove", profile.Gloves.Equipped)
	player:SetAttribute("Location", profile.ActiveLocation)
	player:SetAttribute("LocationTier", location.Tier)
	player:SetAttribute("LocationRebirths", location.Rebirths)
	player:SetAttribute("TotalRebirths", profile.TotalRebirths)
	player:SetAttribute("TopSpeed", math.floor(profile.Records.TopSpeed))
	player:SetAttribute("DataOffline", session.Offline)
	session.CoinsValue.Value = math.min(profile.Coins, 2 ^ 53)
	session.RebirthsValue.Value = profile.TotalRebirths
end

local function createLeaderstats(player: Player): (Folder, IntValue, IntValue)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
	return folder, coins, rebirths
end

-- UpdateAsync с замком. Возвращает: успех, профиль (если взят), «занято другим сервером».
local function tryAcquire(dataStore: DataStore, key: string, force: boolean): (boolean, Types.PlayerProfile?, boolean, string?)
	local acquired: Types.PlayerProfile? = nil
	local lockedByOther = false
	local ok, err = pcall(function()
		dataStore:UpdateAsync(key, function(old: any)
			acquired = nil
			lockedByOther = false
			local now = os.time()
			if type(old) == "table" then
				local lock = old.Session
				if
					not force
					and type(lock) == "table"
					and lock.JobId ~= game.JobId
					and type(lock.LockedAt) == "number"
					and now - lock.LockedAt < SESSION_LOCK_TIMEOUT
				then
					lockedByOther = true
					return nil
				end
			end
			local profile = ProfileTemplate.Sanitize(if type(old) == "table" then old.Profile else nil, now)
			acquired = profile
			return {
				Profile = profile,
				Session = { JobId = game.JobId, LockedAt = now },
				SavedAt = now,
			}
		end)
	end)
	if not ok then
		return false, nil, false, tostring(err)
	end
	return true, acquired, lockedByOther, nil
end

local function loadProfile(player: Player): (Types.PlayerProfile?, boolean)
	local dataStore = resolveStore()
	if dataStore == nil then
		return ProfileTemplate.Create(os.time()), true
	end
	local key = "Player_" .. player.UserId
	local lastError = "unknown"
	for attempt = 1, LOAD_ATTEMPTS do
		if player.Parent ~= Players then
			return nil, false
		end
		local force = attempt == LOAD_ATTEMPTS
		local ok, profile, lockedByOther, err = tryAcquire(dataStore, key, force)
		if ok and profile then
			return profile, false
		end
		if ok and lockedByOther then
			lastError = "session locked by another server"
			task.wait(LOCK_RETRY_DELAY)
		else
			lastError = err or "UpdateAsync failed"
			if RunService:IsStudio() then
				enterOfflineMode(lastError)
				return ProfileTemplate.Create(os.time()), true
			end
			task.wait(math.min(2 ^ attempt, 16))
		end
	end
	warn("[StretchPop] Не удалось загрузить профиль " .. player.Name .. ": " .. lastError)
	return nil, false
end

local function saveSession(session: Session, release: boolean): boolean
	if session.Offline then
		return true
	end
	local dataStore = resolveStore()
	if dataStore == nil then
		return false
	end
	local now = os.clock()
	session.Profile.PlaySeconds += now - session.PlayClock
	session.PlayClock = now
	local snapshot = ProfileTemplate.DeepCopy(session.Profile)
	for attempt = 1, SAVE_ATTEMPTS do
		local stolen = false
		local ok, err = pcall(function()
			dataStore:UpdateAsync(session.Key, function(old: any)
				stolen = false
				if type(old) == "table" and type(old.Session) == "table" and old.Session.JobId ~= game.JobId then
					-- Замок забрал другой сервер (игрок перезашёл туда) — не затираем его свежие данные.
					stolen = true
					return nil
				end
				local record: { [string]: any } = {
					Profile = snapshot,
					SavedAt = os.time(),
				}
				if not release then
					record.Session = { JobId = game.JobId, LockedAt = os.time() }
				end
				return record
			end)
		end)
		if ok then
			if stolen then
				warn("[StretchPop] Профиль " .. session.Key .. " удерживается другим сервером, сохранение пропущено")
			end
			return not stolen
		end
		warn(string.format("[StretchPop] Сохранение %s, попытка %d: %s", session.Key, attempt, tostring(err)))
		task.wait(math.min(2 ^ attempt, 8))
	end
	return false
end

local function onPlayerAdded(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	local profile, offline = loadProfile(player)
	loading[player] = nil
	if player.Parent ~= Players then
		return
	end
	if profile == nil then
		player:Kick("STRETCH-POP: не удалось загрузить сохранение. Перезайди через минуту — прогресс в безопасности.")
		return
	end
	profile.LastJoinUnix = os.time()
	local folder, coinsValue, rebirthsValue = createLeaderstats(player)
	local session: Session = {
		Player = player,
		Key = "Player_" .. player.UserId,
		Profile = profile,
		Offline = offline,
		Released = false,
		Saving = false,
		PlayClock = os.clock(),
		Leaderstats = folder,
		CoinsValue = coinsValue,
		RebirthsValue = rebirthsValue,
	}
	sessions[player] = session
	syncReplicatedState(session)
	PlayerDataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil
	if session.Released then
		return
	end
	session.Released = true
	saveSession(session, true)
end

function PlayerDataService.Get(player: Player): Types.PlayerProfile?
	local session = sessions[player]
	return if session then session.Profile else nil
end

function PlayerDataService.WaitFor(player: Player, timeout: number): Types.PlayerProfile?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local session = sessions[player]
		if session then
			return session.Profile
		end
		if player.Parent ~= Players then
			return nil
		end
		task.wait(0.1)
	end
	local session = sessions[player]
	return if session then session.Profile else nil
end

-- Единственная точка изменения профиля: мутация → синхронизация атрибутов → событие.
function PlayerDataService.Update(player: Player, mutator: (Types.PlayerProfile) -> ()): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	mutator(session.Profile)
	syncReplicatedState(session)
	PlayerDataService.ProfileChanged:Fire(player, session.Profile)
	return true
end

function PlayerDataService.GetLocation(profile: Types.PlayerProfile, locationId: string): Types.LocationProgress
	return ProfileTemplate.GetLocation(profile, locationId)
end

function PlayerDataService.IsOffline(): boolean
	return offlineMode
end

function PlayerDataService.Init()
	if initialized then
		return
	end
	initialized = true
	resolveStore()

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(onPlayerRemoving, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, session in sessions do
				if not session.Released and not session.Saving then
					session.Saving = true
					task.spawn(function()
						saveSession(session, false)
						session.Saving = false
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			if not session.Released then
				session.Released = true
				pending += 1
				task.spawn(function()
					saveSession(session, true)
					pending -= 1
				end)
			end
			sessions[player] = nil
		end
		local deadline = os.clock() + CLOSE_SAVE_BUDGET
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
