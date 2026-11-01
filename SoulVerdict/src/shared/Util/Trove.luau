--!strict
-- Trove: cleanup bag. Collect everything an object/controller creates and release it with one call.
-- Lune-safe (type checks use typeof/type only; no services).
--
--   local trove = Trove.new()
--   trove:Add(obj, method?) -> obj     Instance -> :Destroy(); RBXScriptConnection -> :Disconnect();
--                                      function -> called; thread -> task.cancel (coroutine.close fallback);
--                                      table with Destroy / Disconnect (Signal connections, Signals, Troves,
--                                      Springs...) -> that method; `method` (string) overrides the choice,
--                                      e.g. trove:Add(tween, "Cancel")
--   trove:Connect(signal, fn) -> conn  connects to an RBXScriptSignal or a Util/Signal and tracks the connection
--   trove:Remove(obj) -> boolean       stops tracking obj and cleans it now
--   trove:Clean()                      cleans every tracked object (LIFO: newest first); the trove stays usable
--   trove:Extend() -> Trove            child trove; the parent's next Clean cleans it and detaches it
--   trove:Destroy()                    alias of Clean (so a Trove can itself be Add-ed); stays usable
--   trove:Count() -> number            number of tracked objects
-- Cleaning is error-isolated: one failing cleanup does not stop the rest (errors are re-raised as a warn).

local Trove = {}
Trove.__index = Trove

export type Trove = {
	Add: <T>(self: Trove, obj: T, method: string?) -> T,
	Connect: (self: Trove, signal: any, fn: (...any) -> ()) -> any,
	Remove: (self: Trove, obj: any) -> boolean,
	Clean: (self: Trove) -> (),
	Extend: (self: Trove) -> Trove,
	Destroy: (self: Trove) -> (),
	Count: (self: Trove) -> number,
}

type Entry = { obj: any, method: string | (() -> ()) }

type TroveImpl = {
	_entries: { Entry },
	_cleaning: boolean,
}

local function pickMethod(obj: any, method: string?): string | (() -> ())
	if method ~= nil then
		return method
	end
	local t = typeof(obj)
	if t == "function" then
		return obj :: () -> ()
	elseif t == "thread" then
		return "__thread"
	elseif t == "Instance" then
		return "Destroy"
	elseif t == "RBXScriptConnection" then
		return "Disconnect"
	elseif t == "table" then
		if type(obj.Destroy) == "function" then
			return "Destroy"
		elseif type(obj.Disconnect) == "function" then
			return "Disconnect"
		end
	end
	error(("Trove:Add: don't know how to clean a %s (pass a method name)"):format(t), 3)
end

local function cleanEntry(entry: Entry)
	local obj, method = entry.obj, entry.method
	if type(method) == "function" then
		method()
	elseif method == "__thread" then
		local thread = obj :: thread
		if coroutine.status(thread) ~= "dead" then
			local ok = pcall(task.cancel, thread)
			if not ok then
				coroutine.close(thread)
			end
		end
	else
		local fn = obj[method]
		if type(fn) == "function" then
			fn(obj)
		end
	end
end

function Trove.new(): Trove
	local self: TroveImpl = { _entries = {}, _cleaning = false }
	return (setmetatable(self, Trove) :: any) :: Trove
end

function Trove.Add(self: TroveImpl, obj: any, method: string?): any
	assert(obj ~= nil, "Trove:Add: object is nil")
	table.insert(self._entries, { obj = obj, method = pickMethod(obj, method) })
	return obj
end

function Trove.Connect(self: TroveImpl, signal: any, fn: (...any) -> ()): any
	local conn = signal:Connect(fn)
	Trove.Add(self, conn)
	return conn
end

function Trove.Remove(self: TroveImpl, obj: any): boolean
	local entries = self._entries
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if entry.obj == obj then
			table.remove(entries, i)
			cleanEntry(entry)
			return true
		end
	end
	return false
end

function Trove.Clean(self: TroveImpl)
	if self._cleaning then
		return
	end
	self._cleaning = true
	-- Objects added while cleaning (e.g. by a cleanup function) are cleaned in the same pass.
	while #self._entries > 0 do
		local entry = table.remove(self._entries) :: Entry
		local ok, err = pcall(cleanEntry, entry)
		if not ok then
			warn("Trove: cleanup failed: " .. tostring(err))
		end
	end
	self._cleaning = false
end

function Trove.Extend(self: TroveImpl): Trove
	local child = Trove.new()
	Trove.Add(self, child, "Clean")
	return child
end

function Trove.Destroy(self: TroveImpl)
	Trove.Clean(self)
end

function Trove.Count(self: TroveImpl): number
	return #self._entries
end

return Trove
