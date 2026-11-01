--!strict
-- Signal: lightweight script signal (GoodSignal-style linked list + recycled runner coroutine).
-- Lune-safe: uses only `task` and coroutines, no services.
--
--   local s = Signal.new()                     -- typed use: local s: Signal.Signal<number> = Signal.new()
--   local c = s:Connect(function(...) end)     -> Connection { Connected: boolean, Disconnect(self) }
--   s:Once(fn) -> Connection                   handler runs at most once
--   s:Fire(...)                                calls every handler that was connected when Fire started,
--                                              in connection order. Each handler runs via task.spawn on a
--                                              recycled runner coroutine: a handler that yields or errors
--                                              cannot stop the other handlers (errors are reported by the
--                                              task scheduler, like RBXScriptSignal handlers).
--   s:Wait() -> ...                            yields the calling coroutine until the next Fire and returns
--                                              its arguments (needs a task scheduler: Roblox, or Lune's task)
--   s:DisconnectAll()                          disconnects every handler (pending Waits stay pending)
--   s:Destroy()                                DisconnectAll; afterwards Connect returns a dead connection
--                                              and Fire does nothing
--   s:HasConnections() -> boolean
--
-- Re-entrancy: handlers may Disconnect themselves or others, Connect new handlers, or Fire again while a
-- Fire runs. A handler disconnected during a Fire is not called after the disconnect; a handler connected
-- during a Fire is first called by the NEXT Fire.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

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
	Destroy: (self: Signal<T...>) -> (),
	HasConnections: (self: Signal<T...>) -> boolean,
}

-- Internal shapes ---------------------------------------------------------------------------------
type Handler = (...any) -> ()

type ConnectionImpl = {
	Connected: boolean,
	_signal: SignalImpl,
	_fn: Handler,
	_id: number,
	_prev: ConnectionImpl?,
	_next: ConnectionImpl?,
}

type SignalImpl = {
	_head: ConnectionImpl?,
	_tail: ConnectionImpl?,
	_lastId: number,
	_destroyed: boolean,
}

-- Recycled runner coroutine (GoodSignal technique) -------------------------------------------------
local freeRunner: thread? = nil

local function acquireRunnerAndCall(fn: Handler, ...: any)
	local acquired = freeRunner
	freeRunner = nil
	fn(...)
	-- The handler returned without yielding: this runner is free again.
	freeRunner = acquired
end

local function runnerLoop()
	-- The first resume only parks the coroutine here; real calls arrive through coroutine.yield().
	while true do
		acquireRunnerAndCall(coroutine.yield())
	end
end

local function callHandler(fn: Handler, ...: any)
	if freeRunner == nil then
		local runner = coroutine.create(runnerLoop)
		coroutine.resume(runner)
		freeRunner = runner
	end
	task.spawn(freeRunner :: thread, fn, ...)
end

-- Connection --------------------------------------------------------------------------------------

function Connection.Disconnect(self: ConnectionImpl)
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	local prev, nxt = self._prev, self._next
	if prev ~= nil then
		prev._next = nxt
	elseif signal._head == self then
		signal._head = nxt
	end
	if nxt ~= nil then
		nxt._prev = prev
	elseif signal._tail == self then
		signal._tail = prev
	end
	self._prev = nil
	-- self._next is kept on purpose: a Fire currently standing on this node continues its walk from it.
end

-- Signal ------------------------------------------------------------------------------------------

function Signal.new(): Signal<...any>
	local self: SignalImpl = { _head = nil, _tail = nil, _lastId = 0, _destroyed = false }
	return (setmetatable(self, Signal) :: any) :: Signal<...any>
end

local function connect(self: SignalImpl, fn: Handler): Connection
	assert(type(fn) == "function", "Signal:Connect expects a function")
	self._lastId += 1
	local conn: ConnectionImpl = {
		Connected = not self._destroyed,
		_signal = self,
		_fn = fn,
		_id = self._lastId,
		_prev = nil,
		_next = nil,
	}
	if not self._destroyed then
		local tail = self._tail
		if tail == nil then
			self._head = conn
		else
			tail._next = conn
			conn._prev = tail
		end
		self._tail = conn
	end
	return (setmetatable(conn, Connection) :: any) :: Connection
end

function Signal.Connect(self: SignalImpl, fn: Handler): Connection
	return connect(self, fn)
end

function Signal.Once(self: SignalImpl, fn: Handler): Connection
	local conn: Connection
	conn = connect(self, function(...: any)
		if conn.Connected then
			conn:Disconnect()
			fn(...)
		end
	end)
	return conn
end

function Signal.Fire(self: SignalImpl, ...: any)
	if self._destroyed then
		return
	end
	-- Ids grow along every _next chain, so stopping at the first id above the snapshot skips exactly
	-- the handlers connected during this Fire.
	local maxId = self._lastId
	local node = self._head
	while node ~= nil and node._id <= maxId do
		if node.Connected then
			callHandler(node._fn, ...)
		end
		node = node._next
	end
end

function Signal.Wait(self: SignalImpl): ...any
	local waiting = coroutine.running()
	local conn: Connection
	conn = connect(self, function(...: any)
		conn:Disconnect()
		task.spawn(waiting, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: SignalImpl)
	local node = self._head
	while node ~= nil do
		node.Connected = false
		node = node._next
	end
	self._head = nil
	self._tail = nil
end

function Signal.Destroy(self: SignalImpl)
	Signal.DisconnectAll(self)
	self._destroyed = true
end

function Signal.HasConnections(self: SignalImpl): boolean
	return self._head ~= nil
end

return Signal
