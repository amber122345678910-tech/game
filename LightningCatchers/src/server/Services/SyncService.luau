--!strict
-- Рассылка снимка данных игроку (RemoteEvent DataSync) после каждого DataService.Changed.
-- Изменения склеиваются: не чаще одного снимка за Config.Server.SyncInterval, и всегда
-- отправляется самое свежее состояние (снимок берётся в момент отправки, а не в момент изменения).
-- Тяжёлые разделы (Pets, Fulgs, Index) меняются редко, а снимок уходит почти на каждую поимку,
-- поэтому неизменные разделы не отправляются: вместо них в снимке Keep = { "Pets", ... } —
-- клиент берёт их из прошлого снимка. Полный снимок — первый и не реже Config.Server.FullSyncEvery с.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))

local DataService = require(script.Parent.DataService)

type Data = PlayerData.Data

local SyncService = {}

-- Раздел снимка и его дешёвая подпись: поменялась подпись — раздел отправляется заново
local SECTIONS: { { Key: string, Sig: (Data) -> string } } = {
	{
		Key = "Pets",
		Sig = function(d: Data): string
			return d.NextPetId .. ":" .. #d.Pets
		end,
	},
	{
		Key = "Fulgs",
		Sig = function(d: Data): string
			return d.NextFulgId .. ":" .. #d.Fulgs
		end,
	},
	{
		Key = "Index",
		Sig = function(d: Data): string
			local n = 0
			for _ in d.Index do
				n += 1
			end
			return tostring(n)
		end,
	},
}

local scheduled: { [Player]: boolean } = {}
local lastSent: { [Player]: number } = {}
local lastFull: { [Player]: number } = {}
local sentSigs: { [Player]: { [string]: string } } = {}
local remote: RemoteEvent? = nil

local function send(player: Player)
	scheduled[player] = nil
	local r = remote
	if not r or player.Parent ~= Players then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local clock = os.clock()
	lastSent[player] = clock
	local sigs = sentSigs[player]
	local full = sigs == nil or clock - (lastFull[player] or -math.huge) >= Config.Server.FullSyncEvery
	local fresh: { [string]: string } = {}
	local keep: { string } = {}
	for _, section in SECTIONS do
		local sig = section.Sig(data)
		fresh[section.Key] = sig
		if not full and sigs and sigs[section.Key] == sig then
			table.insert(keep, section.Key)
		end
	end
	sentSigs[player] = fresh
	if #keep == 0 then
		lastFull[player] = clock
		r:FireClient(player, data)
		return
	end
	-- неглубокая копия без неизменных разделов (FireClient копирует аргументы сразу)
	local snapshot: { [string]: any } = table.clone(data :: any)
	for _, key in keep do
		snapshot[key] = nil
	end
	snapshot.Keep = keep
	r:FireClient(player, snapshot)
end

-- Запланировать отправку снимка (повторные вызовы до отправки ничего не добавляют)
function SyncService.push(player: Player)
	if scheduled[player] then
		return
	end
	scheduled[player] = true
	local last = lastSent[player]
	local waitFor = if last then Config.Server.SyncInterval - (os.clock() - last) else 0
	if waitFor <= 0 then
		-- в конце кадра: все изменения этого кадра уйдут одним снимком
		task.defer(send, player)
	else
		task.delay(waitFor, send, player)
	end
end

function SyncService.start()
	remote = Net.event("DataSync")
	DataService.Changed:Connect(SyncService.push)
	DataService.Loaded:Connect(function(player)
		sentSigs[player] = nil -- новая сессия — снова полный снимок
	end)
	Players.PlayerRemoving:Connect(function(player)
		scheduled[player] = nil
		lastSent[player] = nil
		lastFull[player] = nil
		sentSigs[player] = nil
	end)
	-- игроки, чьи данные загрузились раньше старта сервиса
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			SyncService.push(player)
		end
	end
end

return SyncService
