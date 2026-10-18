--!strict
-- Рассылка снимка данных игроку (RemoteEvent DataSync) после каждого DataService.Changed.
-- Изменения склеиваются: не чаще одного снимка за Config.Server.SyncInterval, и всегда
-- отправляется самое свежее состояние (снимок берётся в момент отправки, а не в момент изменения).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local DataService = require(script.Parent.DataService)

local SyncService = {}

local scheduled: { [Player]: boolean } = {}
local lastSent: { [Player]: number } = {}
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
	lastSent[player] = os.clock()
	r:FireClient(player, data)
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
	Players.PlayerRemoving:Connect(function(player)
		scheduled[player] = nil
		lastSent[player] = nil
	end)
	-- игроки, чьи данные загрузились раньше старта сервиса
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			SyncService.push(player)
		end
	end
end

return SyncService
