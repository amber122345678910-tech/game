--!strict
-- Состояние клиента: зеркало данных игрока (присылает сервер), общие сигналы и запросы к серверу.
-- Все клиентские модули берут данные только отсюда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Strikes = require(Shared:WaitForChild("Strikes"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = {}

local player = Players.LocalPlayer

ClientState.player = player
ClientState.data = nil :: PlayerData.Data?

-- (data) — пришёл новый снимок данных
ClientState.Changed = Signal.new() :: Signal.Signal<PlayerData.Data>
-- (msg) — новое кольцо от сервера
ClientState.StrikeSpawned = Signal.new() :: Signal.Signal<Net.StrikeMsg>
-- (msg) — итог удара от сервера
ClientState.StrikeResolved = Signal.new() :: Signal.Signal<Net.StrikeResultMsg>
-- (msg) — разовый эффект от сервера
ClientState.Effect = Signal.new() :: Signal.Signal<Net.EffectMsg>
-- (grade, color, combo) — локальная мгновенная оценка нажатия (до ответа сервера)
ClientState.LocalGrade = Signal.new() :: Signal.Signal<string, string, number>
-- (zone, oldZone) — игрок перешёл в другую зону (0 = хаб)
ClientState.ZoneChanged = Signal.new() :: Signal.Signal<number, number>
-- (name) — открыть окно интерфейса ("Shop", "Pets", "Collection", "Teleport", "Rebirth", "Daily", "Settings")
ClientState.OpenWindow = Signal.new() :: Signal.Signal<string>
-- (text, kind) — показать тост
ClientState.Toast = Signal.new() :: Signal.Signal<string, string>
-- () — нажата кнопка ⚡ ЛОВИ на экране (HUD), CatchController слушает вместе с клавиатурой
ClientState.CatchPressed = Signal.new() :: Signal.Signal<>
-- (name) — окно открыто / закрыто (для обучения и звуков)
ClientState.WindowOpened = Signal.new() :: Signal.Signal<string>
ClientState.WindowClosed = Signal.new() :: Signal.Signal<string>

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestFn = remotes:WaitForChild("Request") :: RemoteFunction

-- Серверное время (одинаковое для всех клиентов и сервера)
function ClientState.now(): number
	return Workspace:GetServerTimeNow()
end

function ClientState.get(): PlayerData.Data?
	return ClientState.data
end

-- Ждать первого снимка данных
function ClientState.waitForData(): PlayerData.Data
	while not ClientState.data do
		ClientState.Changed:Wait()
	end
	return ClientState.data :: PlayerData.Data
end

function ClientState.zone(): number
	local z = player:GetAttribute("Zone")
	return if typeof(z) == "number" then z else 0
end

function ClientState.capacity(): number
	local d = ClientState.data
	if not d then
		return Economy.jarCapacity(0)
	end
	return Economy.jarCapacity(d.Upgrades.Jar)
end

function ClientState.cityBoost(): boolean
	local gs = ReplicatedStorage:FindFirstChild("GameState")
	if not gs then
		return false
	end
	local untilT = gs:GetAttribute("CityBoostUntil")
	return typeof(untilT) == "number" and untilT > ClientState.now()
end

-- Множитель Вольт так же, как считает сервер
function ClientState.multiplier(): number
	local d = ClientState.data
	if not d then
		return 1
	end
	local friends = player:GetAttribute("FriendCount")
	return Economy.multiplier(d, {
		friends = if typeof(friends) == "number" then friends else 0,
		cityBoost = ClientState.cityBoost(),
		now = os.time(),
	})
end

-- Окна тайминга с учётом громоотвода и питомцев
function ClientState.windows(): (number, number)
	local d = ClientState.data
	if not d then
		return Strikes.windows(0, 0)
	end
	return Strikes.windows(d.Upgrades.Rod, Economy.petBonuses(d).window)
end

-- Запрос к серверу. При ошибке показывает тост и возвращает false.
function ClientState.request(action: string, payload: any?): (boolean, any)
	local ok, a, b = pcall(function()
		return requestFn:InvokeServer(action, payload)
	end)
	if not ok then
		ClientState.Toast:Fire("Нет связи с сервером", "bad")
		return false, nil
	end
	if a ~= true then
		if typeof(b) == "string" and b ~= "" then
			ClientState.Toast:Fire(b, "bad")
		end
		return false, b
	end
	return true, b
end

-- Подключение к серверу (вызывается из Main.client один раз)
local started = false
function ClientState.start()
	if started then
		return
	end
	started = true
	Net.event("DataSync").OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" then
			ClientState.data = data :: PlayerData.Data
			ClientState.Changed:Fire(data)
		end
	end)
	Net.event("StrikeSpawn").OnClientEvent:Connect(function(msg: any)
		if typeof(msg) == "table" then
			ClientState.StrikeSpawned:Fire(msg)
		end
	end)
	Net.event("StrikeResult").OnClientEvent:Connect(function(msg: any)
		if typeof(msg) == "table" then
			ClientState.StrikeResolved:Fire(msg)
		end
	end)
	Net.event("Effect").OnClientEvent:Connect(function(msg: any)
		if typeof(msg) == "table" then
			ClientState.Effect:Fire(msg)
		end
	end)
	Net.event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if typeof(text) == "string" then
			ClientState.Toast:Fire(text, if typeof(kind) == "string" then kind else "info")
		end
	end)
	local lastZone = ClientState.zone()
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		local z = ClientState.zone()
		if z ~= lastZone then
			local old = lastZone
			lastZone = z
			ClientState.ZoneChanged:Fire(z, old)
		end
	end)
end

return ClientState
