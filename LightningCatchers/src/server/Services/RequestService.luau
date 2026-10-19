--!strict
-- Единый роутер RemoteFunction "Request": действие -> обработчик.
--  * сервисы регистрируют обработчики через RequestService.handle(action, fn);
--  * лимит частоты на игрока (ведро токенов: Config.Server.RequestRate / RequestBurst);
--  * обработчик вызывается в xpcall: ошибка в коде не ломает сервер, игрок видит понятный текст.
-- Проверка типов payload — забота обработчика (он лучше знает, что ждёт).
-- Обработчик возвращает (true, результат) или (false, текст ошибки): строка-исходник по-русски или Loc.msg(...) —
-- клиент рисует его на языке игрока (Loc.render).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Loc = require(Shared:WaitForChild("Loc"))
local Net = require(Shared:WaitForChild("Net"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)

export type Handler = (player: Player, payload: any) -> (boolean, any)

local RequestService = {}

RequestService.ErrorText = Loc.msg("Ошибка, попробуй ещё раз")
RequestService.UnknownText = Loc.msg("Неизвестное действие")
RequestService.TooFastText = Loc.msg("Слишком быстро! Подожди секунду")

local handlers: { [string]: Handler } = {}
local buckets: { [Player]: ServerLogic.Bucket } = {}

-- Зарегистрировать обработчик действия (повторная регистрация заменяет старый)
function RequestService.handle(action: string, fn: Handler)
	assert(action ~= "", "RequestService.handle: пустое имя действия")
	if handlers[action] then
		warn("[RequestService] обработчик заменён: " .. action)
	end
	handlers[action] = fn
end

-- Есть ли обработчик (для отладки и тестов)
function RequestService.has(action: string): boolean
	return handlers[action] ~= nil
end

-- Взять токен из ведра игрока; false — слишком часто
local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = ServerLogic.newBucket(Config.Server.RequestBurst, now)
		buckets[player] = b
	end
	return ServerLogic.take(b, Config.Server.RequestRate, Config.Server.RequestBurst, now)
end

local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

-- Выполнить запрос так же, как его выполнит RemoteFunction (без лимита частоты — для серверного кода)
function RequestService.invoke(player: Player, action: string, payload: any): (boolean, any)
	local fn = handlers[action]
	if not fn then
		return false, RequestService.UnknownText
	end
	local ok, success, result = xpcall(fn, traceback, player, payload)
	if not ok then
		warn(string.format("[RequestService] %s (%s): %s", action, player.Name, tostring(success)))
		return false, RequestService.ErrorText
	end
	if success == true then
		return true, result
	end
	-- обработчик отказал: показываем его текст (строка-исходник или Loc.msg), если он есть
	local hasText = (typeof(result) == "string" and result ~= "") or (typeof(result) == "table" and typeof(result[1]) == "string")
	return false, if hasText then result else RequestService.ErrorText
end

local function onInvoke(player: Player, action: any, payload: any): (boolean, any)
	if typeof(action) ~= "string" then
		return false, RequestService.UnknownText
	end
	if not allow(player) then
		return false, RequestService.TooFastText
	end
	if not handlers[action] then
		return false, RequestService.UnknownText
	end
	return RequestService.invoke(player, action, payload)
end

function RequestService.start()
	local remote = Net.func("Request")
	remote.OnServerInvoke = function(player: Player, action: any, payload: any)
		return onInvoke(player, action, payload)
	end
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return RequestService
