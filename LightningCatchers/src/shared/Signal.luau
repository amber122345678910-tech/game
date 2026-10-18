--!strict
-- Простой сигнал для общения модулей внутри одной стороны (клиент или сервер).

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Handler = {
	fn: (...any) -> (),
	conn: Connection,
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { Handler } = {}

	local self = {} :: any

	function self.Connect(_: any, fn: (...any) -> ()): Connection
		local conn = { Connected = true } :: any
		local handler: Handler = { fn = fn, conn = conn }
		function conn.Disconnect(c: any)
			if not c.Connected then
				return
			end
			c.Connected = false
			local i = table.find(handlers, handler)
			if i then
				table.remove(handlers, i)
			end
		end
		table.insert(handlers, handler)
		return conn
	end

	function self.Once(s: any, fn: (...any) -> ()): Connection
		local conn: Connection
		conn = s:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function self.Fire(_: any, ...: any)
		-- копия, чтобы отключения во время рассылки не ломали обход
		local snapshot = table.clone(handlers)
		for _, h in snapshot do
			if h.conn.Connected then
				task.spawn(h.fn, ...)
			end
		end
	end

	function self.Wait(s: any): ...any
		local thread = coroutine.running()
		s:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self.DisconnectAll(_: any)
		for _, h in handlers do
			h.conn.Connected = false
		end
		table.clear(handlers)
	end

	return self :: Signal<T...>
end

return Signal
