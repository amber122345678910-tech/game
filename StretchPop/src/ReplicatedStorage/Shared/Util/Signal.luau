--!strict
-- STRETCH-POP · Лёгкий типизированный сигнал для связи модулей на одной стороне
-- (контроллер рогатки → HUD/аудио следующего шага). Без BindableEvent: аргументы не копируются,
-- обработчик, отключённый во время Fire, больше не вызывается, ошибки одного слушателя не ломают остальных.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Listener = {
	Callback: (...any) -> (),
	Connection: Connection,
}

type SignalImpl = {
	Listeners: { Listener },
}

local SignalClass = {}
SignalClass.__index = SignalClass

local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

function ConnectionClass.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local listeners: { Listener } = self._signal.Listeners
	for index, listener in listeners do
		if listener.Connection == self then
			table.remove(listeners, index)
			break
		end
	end
end

function SignalClass.Connect(self: SignalImpl, callback: (...any) -> ()): Connection
	local connection = setmetatable({ Connected = true, _signal = self }, ConnectionClass)
	table.insert(self.Listeners, { Callback = callback, Connection = (connection :: any) :: Connection })
	return (connection :: any) :: Connection
end

function SignalClass.Once(self: SignalImpl, callback: (...any) -> ()): Connection
	local connection: Connection
	connection = SignalClass.Connect(self, function(...: any)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function SignalClass.Fire(self: SignalImpl, ...: any)
	-- Снимок списка: подписки/отписки во время рассылки не ломают итерацию.
	local snapshot = table.clone(self.Listeners)
	for _, listener in snapshot do
		if listener.Connection.Connected then
			local ok, err = pcall(listener.Callback, ...)
			if not ok then
				warn("[StretchPop.Signal] listener error: " .. tostring(err))
			end
		end
	end
end

function SignalClass.DisconnectAll(self: SignalImpl)
	for _, listener in self.Listeners do
		listener.Connection.Connected = false
	end
	table.clear(self.Listeners)
end

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local impl: SignalImpl = { Listeners = {} }
	return (setmetatable(impl, SignalClass) :: any) :: Signal<T...>
end

return Signal
