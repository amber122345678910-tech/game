--!strict
-- LeaderboardService (P76): global Wins / LV boards (SPEC §1.6, §12) on OrderedDataStores Config.Data.WinsBoard
-- ("SV_Wins_v1") and Config.Data.LevelBoard ("SV_Level_v1"); key = tostring(userId).
--   Wins value  = Profile.Stats.Wins
--   Level value = Level * 100000 + min(Exp, 99999)   (ties on LV are broken by EXP; published value = LV)
-- Scores are posted when they changed: every REFRESH_INTERVAL s and when a player leaves (DataService.Releasing).
-- The top 10 of each board is read every REFRESH_INTERVAL s (120) and published to clients:
--   ReplicatedStorage.Leaderboards (Folder; attributes UpdatedAt = unix time, Source = "Global"|"Server")
--     StringValue "Wins" / "Level": Value = JSON array {{rank, userId, name, value, exp?}} (best first)
--       + attributes Count, and per rank i: Name<i>, Value<i>, UserId<i>
-- Without DataStore access (Studio / memory mode) the boards are built from the profiles in this server.
-- API: Refresh() (yields), Board(name) -> {{rank, userId, name, value}}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any

local LeaderboardService = {}
LeaderboardService.Priority = 76

local REFRESH_INTERVAL = 120
local TOP = 10
local LEVEL_FACTOR = 100000
local BOARDS = { "Wins", "Level" }

type Entry = { rank: number, userId: number, name: string, value: number, exp: number? }

local DataService: any = nil
local dataStoreService: any = nil
local stores: { [string]: any } = {}
local folder: Folder? = nil
local values: { [string]: StringValue } = {}
local lastPosted: { [number]: { [string]: number } } = {}
local names: { [number]: string } = {}
local boards: { [string]: { Entry } } = { Wins = {}, Level = {} }

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

local function scoreOf(profile: any, board: string): number
	if board == "Wins" then
		return math.max(0, math.floor(tonumber(profile.Stats and profile.Stats.Wins) or 0))
	end
	local level = math.max(1, math.floor(tonumber(profile.Level) or 1))
	local exp = math.clamp(math.floor(tonumber(profile.Exp) or 0), 0, LEVEL_FACTOR - 1)
	return level * LEVEL_FACTOR + exp
end

local function budgetOk(kind: string): boolean
	if dataStoreService == nil then
		return true
	end
	local names2 = if kind == "write"
		then { "SetIncrementSortedAsync", "OrderedWrite" }
		else { "GetSortedAsync", "OrderedRead" }
	for _, name in names2 do
		local ok, value = pcall(function()
			return dataStoreService:GetRequestBudgetForRequestType((Enum.DataStoreRequestType :: any)[name])
		end)
		if ok and type(value) == "number" and value < 1 then
			return false
		end
	end
	return true
end

local function ensureFolder()
	if folder and folder.Parent then
		return
	end
	local f = ReplicatedStorage:FindFirstChild("Leaderboards")
	if f == nil or not f:IsA("Folder") then
		local made = Instance.new("Folder")
		made.Name = "Leaderboards"
		made:SetAttribute("UpdatedAt", 0)
		made:SetAttribute("Source", "Server")
		made.Parent = ReplicatedStorage
		f = made
	end
	folder = f :: Folder
	for _, board in BOARDS do
		local existing = (f :: Instance):FindFirstChild(board)
		if existing and existing:IsA("StringValue") then
			values[board] = existing
		else
			local v = Instance.new("StringValue")
			v.Name = board
			v.Value = "[]"
			v:SetAttribute("Count", 0)
			v.Parent = f
			values[board] = v
		end
	end
end

local function publish(source: string)
	ensureFolder()
	for _, board in BOARDS do
		local list = boards[board]
		local v = values[board]
		local ok, json = pcall(HttpService.JSONEncode, HttpService, list)
		v.Value = if ok then json else "[]"
		for i = 1, TOP do
			local e = list[i]
			v:SetAttribute("Name" .. i, if e then e.name else nil)
			v:SetAttribute("Value" .. i, if e then e.value else nil)
			v:SetAttribute("UserId" .. i, if e then e.userId else nil)
		end
		v:SetAttribute("Count", #list)
	end
	local f = folder :: Folder
	f:SetAttribute("UpdatedAt", os.time())
	f:SetAttribute("Source", source)
end

local function displayNames(userIds: { number })
	local missing: { number } = {}
	for _, id in userIds do
		local player = Players:GetPlayerByUserId(id)
		if player then
			names[id] = player.DisplayName
		elseif names[id] == nil then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return game:GetService("UserService"):GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				names[info.Id] = info.DisplayName or info.Username
			end
		end
	end
	for _, id in missing do
		if names[id] == nil then
			local okName, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
			names[id] = if okName and type(name) == "string" then name else ("#" .. tostring(id))
		end
	end
end

local function decode(board: string, raw: number): (number, number?)
	if board == "Level" then
		return math.floor(raw / LEVEL_FACTOR), raw % LEVEL_FACTOR
	end
	return raw, nil
end

-- Server-only boards (memory mode / DataStore down): the profiles of the players in this server.
local function localBoards()
	for _, board in BOARDS do
		local list: { Entry } = {}
		for _, player in Players:GetPlayers() do
			local profile = if DataService then DataService.Get(player) else nil
			if profile then
				local value, exp = decode(board, scoreOf(profile, board))
				table.insert(
					list,
					{ rank = 0, userId = player.UserId, name = player.DisplayName, value = value, exp = exp }
				)
			end
		end
		table.sort(list, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			return (a.exp or 0) > (b.exp or 0)
		end)
		for i = #list, TOP + 1, -1 do
			table.remove(list, i)
		end
		for i, e in list do
			e.rank = i
		end
		boards[board] = list
	end
	publish("Server")
end

local function post(player: Player, profile: any)
	if stores.Wins == nil then
		return
	end
	local posted = lastPosted[player.UserId] or {}
	lastPosted[player.UserId] = posted
	for _, board in BOARDS do
		local score = scoreOf(profile, board)
		local minimum = if board == "Level" then 2 * LEVEL_FACTOR else 1 -- LV 1 / 0 wins are not worth a write
		if score >= minimum and posted[board] ~= score and budgetOk("write") then
			local ok, err = pcall(function()
				stores[board]:SetAsync(tostring(player.UserId), score)
			end)
			if ok then
				posted[board] = score
			else
				warn("[LeaderboardService] post " .. board .. ": " .. tostring(err))
			end
		end
	end
end

local function readBoard(board: string): { Entry }?
	if not budgetOk("read") then
		return nil
	end
	local ok, page = pcall(function()
		return stores[board]:GetSortedAsync(false, TOP):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		warn("[LeaderboardService] read " .. board .. ": " .. tostring(page))
		return nil
	end
	local list: { Entry } = {}
	local ids: { number } = {}
	for i, item in page do
		local userId = tonumber(item.key)
		local raw = tonumber(item.value)
		if userId and raw then
			local value, exp = decode(board, raw)
			table.insert(list, { rank = i, userId = userId, name = "", value = value, exp = exp })
			table.insert(ids, userId)
		end
	end
	displayNames(ids)
	for _, e in list do
		e.name = names[e.userId] or ("#" .. tostring(e.userId))
	end
	return list
end

function LeaderboardService.Refresh()
	if stores.Wins == nil then
		localBoards()
		return
	end
	for _, player in Players:GetPlayers() do
		local profile = if DataService then DataService.Get(player) else nil
		if profile and DataService.IsPersistent(player) then
			post(player, profile)
		end
	end
	local any = false
	for _, board in BOARDS do
		local list = readBoard(board)
		if list then
			boards[board] = list
			any = true
		end
	end
	if any then
		publish("Global")
	else
		localBoards()
	end
end

function LeaderboardService.Board(name: string): { Entry }
	return boards[name] or {}
end

function LeaderboardService.Init()
	DataService = tryService("DataService")
end

function LeaderboardService.Start()
	ensureFolder()
	-- the DataStore mode is decided by DataService.Start; wait for it (bounded)
	local deadline = os.clock() + 30
	while DataService and DataService.Mode() == "Pending" and os.clock() < deadline do
		task.wait(0.5)
	end
	if DataService and DataService.Mode() == "DataStore" then
		local ok, err = pcall(function()
			dataStoreService = game:GetService("DataStoreService")
			stores.Wins = dataStoreService:GetOrderedDataStore(Config.Data.WinsBoard)
			stores.Level = dataStoreService:GetOrderedDataStore(Config.Data.LevelBoard)
		end)
		if not ok then
			warn("[LeaderboardService] ordered stores unavailable: " .. tostring(err))
			stores = {}
		end
	end
	if DataService then
		DataService.Releasing:Connect(function(player: Player, profile: any)
			if stores.Wins and DataService.IsPersistent(player) then
				task.spawn(post, player, profile)
			end
			task.delay(1, function()
				lastPosted[player.UserId] = nil
			end)
		end)
		DataService.Loaded:Connect(function()
			if stores.Wins == nil then
				task.defer(localBoards)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function()
		if stores.Wins == nil then
			task.defer(localBoards)
		end
	end)
	task.spawn(function()
		task.wait(8)
		while true do
			local ok, err = pcall(LeaderboardService.Refresh)
			if not ok then
				warn("[LeaderboardService] refresh: " .. tostring(err))
			end
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return LeaderboardService
