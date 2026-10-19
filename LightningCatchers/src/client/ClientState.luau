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
local Loc = require(Shared:WaitForChild("Loc"))

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
-- (grade, color, combo) — локальная мгновенная оценка нажатия (до ответа сервера): "perfect" | "good" | "miss";
-- "zap" — прогноз «ШАРАХНУЛО» (стоял в кольце и не нажал); "miss" ещё и поправка, если сервер не засчитал поимку
ClientState.LocalGrade = Signal.new() :: Signal.Signal<string, string, number>
-- (zone, oldZone) — игрок перешёл в другую зону (0 = хаб)
ClientState.ZoneChanged = Signal.new() :: Signal.Signal<number, number>
-- (name) — открыть окно интерфейса ("Shop", "Pets", "Collection", "Teleport", "Rebirth", "Daily", "Settings")
ClientState.OpenWindow = Signal.new() :: Signal.Signal<string>
-- (text, kind) — показать тост: текст уже на языке игрока (Loc.t / Loc.render)
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
		-- бусты хранят серверный os.time(): сравниваем с серверным временем, а не с часами устройства
		now = math.floor(ClientState.now()),
	})
end

-- Прогнозы клиента по ударам ("id:hit" -> оценка и os.clock()), например «ШАРАХНУЛО» до ответа сервера:
-- ответ сервера с той же оценкой второй раз не показываем. Старые записи чистятся сами.
local PREDICT_KEEP = 10
local predicted: { [string]: { grade: string, at: number } } = {}
local predictedCount = 0

local function predictKey(id: number, hit: number): string
	return tostring(id) .. ":" .. tostring(hit)
end

function ClientState.markPredicted(id: number, hit: number, grade: string)
	local clock = os.clock()
	if predictedCount >= 32 then
		for k, p in predicted do
			if clock - p.at > PREDICT_KEEP then
				predicted[k] = nil
				predictedCount -= 1
			end
		end
	end
	local k = predictKey(id, hit)
	if not predicted[k] then
		predictedCount += 1
	end
	predicted[k] = { grade = grade, at = clock }
end

-- Оценка, которую клиент уже показал для удара сам (nil — не показывал)
function ClientState.predictedGrade(id: number, hit: number): string?
	local p = predicted[predictKey(id, hit)]
	if p and os.clock() - p.at <= PREDICT_KEEP then
		return p.grade
	end
	return nil
end

-- Тесла-дрон улетел с зарядом (Effect drone "depart") и ещё не сдал его ("sold"): os.clock() крайнего срока
local DRONE_LATE = 1.5 -- запас к времени полёта, если "sold" не пришёл
local droneAwayUntil = 0

function ClientState.droneAway(): boolean
	return os.clock() < droneAwayUntil
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
-- Ошибку сервер присылает строкой-исходником или Loc.Msg: тост рисует её через Loc.render, а вторым
-- значением возвращается как есть (вызывающий тоже рисует её через Loc.render, если показывает)
function ClientState.request(action: string, payload: any?): (boolean, any)
	local ok, a, b = pcall(function()
		return requestFn:InvokeServer(action, payload)
	end)
	if not ok then
		ClientState.Toast:Fire(Loc.t("Нет связи с сервером"), "bad")
		return false, nil
	end
	if a ~= true then
		if typeof(b) == "string" or typeof(b) == "table" then
			local text = Loc.render(b)
			if text ~= "" then
				ClientState.Toast:Fire(text, "bad")
			end
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
			-- неизменные тяжёлые разделы (Pets, Fulgs, Index) сервер не присылает: Keep = их имена
			local keep = data.Keep
			if typeof(keep) == "table" then
				local prev: any = ClientState.data
				if not prev then
					return -- полного снимка ещё не было: дождёмся следующего полного
				end
				for _, key in keep do
					if typeof(key) == "string" then
						data[key] = prev[key]
					end
				end
				data.Keep = nil
			end
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
			if msg.Kind == "drone" and (msg.UserId == nil or msg.UserId == player.UserId) then
				if msg.Text == "depart" then
					local trip = if typeof(msg.Value) == "number" then math.clamp(msg.Value, 0, 60) else 5
					droneAwayUntil = os.clock() + trip + DRONE_LATE
				elseif msg.Text == "sold" then
					droneAwayUntil = 0
				end
			end
			ClientState.Effect:Fire(msg)
		end
	end)
	-- текст от сервера — строка-исходник или Loc.Msg: рисуем на языке игрока
	Net.event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if typeof(text) == "string" or typeof(text) == "table" then
			local s = Loc.render(text)
			if s ~= "" then
				ClientState.Toast:Fire(s, if typeof(kind) == "string" then kind else "info")
			end
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
