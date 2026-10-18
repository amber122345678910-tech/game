--!nocheck
-- Simulated clock and thread scheduler (replaces the Roblox task scheduler).
--  * Time advances only in Sched.step() by a fixed frame (1/30 s) — fully deterministic.
--  * Every game thread is a coroutine tagged with its realm (server / client N). The realm decides what the
--    thread can see (client-local instances, LocalPlayer, ...).
--  * Threads run their body inside xpcall, so an error in any connection/task is reported with a stack trace
--    and never crashes the harness.
--  * Engine signals use Deferred SignalBehavior (like the project's Workspace.SignalBehavior): handlers are
--    queued and run at the next resumption point (Sched.flush).
local Report = require("./report")

local Sched = {}

Sched.now = 0 -- simulated seconds since boot
Sched.EPOCH = 1728000000 -- server time at boot (multiple of 43200: event schedules start in phase)
Sched.osTimeOffset = 0 -- extra seconds added to os.time()/os.date()/tick()/DateTime (calendar tests)
Sched.FRAME = 1 / 30
Sched.frame = 0
Sched.CUR = nil -- current realm
Sched.realms = {}

local threadRealm = setmetatable({}, { __mode = "k" })
local waitToken = setmetatable({}, { __mode = "k" })
local cancelled = setmetatable({}, { __mode = "k" })
local threadInfo = setmetatable({}, { __mode = "k" }) -- co -> { what = "...", since = t }
Sched.threadRealm = threadRealm
Sched.threadInfo = threadInfo

Report.now = function()
	return Sched.now
end

----------------------------------------------------------------------
-- Timer heap
----------------------------------------------------------------------
local heap = {}
local seqCounter = 0

local function less(a, b)
	if a.t ~= b.t then
		return a.t < b.t
	end
	return a.seq < b.seq
end

local function heapPush(e)
	seqCounter += 1
	e.seq = seqCounter
	local i = #heap + 1
	heap[i] = e
	while i > 1 do
		local p = i // 2
		if less(heap[i], heap[p]) then
			heap[i], heap[p] = heap[p], heap[i]
			i = p
		else
			break
		end
	end
end

local function heapPop()
	local n = #heap
	if n == 0 then
		return nil
	end
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local m = i
		if l <= n and less(heap[l], heap[m]) then
			m = l
		end
		if r <= n and less(heap[r], heap[m]) then
			m = r
		end
		if m == i then
			break
		end
		heap[i], heap[m] = heap[m], heap[i]
		i = m
	end
	return top
end

function Sched.at(t, fn)
	heapPush({ t = t, call = fn })
end

----------------------------------------------------------------------
-- Errors
----------------------------------------------------------------------
Sched.lastThrown = nil -- engine error already recorded (avoid double report)

local function realmName(r)
	return if r then r.name else "?"
end
Sched.realmName = realmName

local function onThreadError(e)
	local msg = e
	if msg == Sched.lastThrown then
		Sched.lastThrown = nil
		return e
	end
	Sched.lastThrown = nil
	local frames = Report.frames(nil, 1)
	local text = Report.cleanMessage(msg)
	-- an error inside the harness itself (not a deliberate engine error): keep the harness location
	if #frames == 0 or string.find(text, "tools/sim", 1, true) then
		local s, l = debug.info(2, "sl")
		local raw = {}
		for i = 2, 30 do
			local src, line, name = debug.info(i, "sln")
			if not src then
				break
			end
			if src ~= "[C]" then
				table.insert(raw, { src = src, line = line, name = name })
			end
		end
		Report.add("runtime", realmName(Sched.CUR), "[harness?] " .. text, raw)
		return e
	end
	Report.add("runtime", realmName(Sched.CUR), text, frames)
	return e
end
Sched.onThreadError = onThreadError

local function threadBody(fn, ...)
	xpcall(fn, onThreadError, ...)
end

----------------------------------------------------------------------
-- Threads
----------------------------------------------------------------------
function Sched.newThread(realm, fn)
	local co = coroutine.create(threadBody)
	threadRealm[co] = realm
	return co, fn
end

-- Resume a thread (switches the current realm). Returns ok.
local pendingStart = setmetatable({}, { __mode = "k" }) -- co -> fn (not started yet)

function Sched.resume(co, ...)
	if cancelled[co] then
		return false
	end
	local realm = threadRealm[co]
	if realm and realm.dead then
		return false
	end
	if coroutine.status(co) ~= "suspended" then
		local s = coroutine.status(co)
		if s == "dead" then
			return false
		end
		-- resuming a running/normal thread is an error in Roblox too
		Report.add("runtime", realmName(Sched.CUR), "cannot resume non-suspended coroutine (status " .. s .. ")", Report.frames(nil, 2))
		return false
	end
	waitToken[co] = (waitToken[co] or 0) + 1
	threadInfo[co] = nil
	local prev = Sched.CUR
	Sched.CUR = realm or prev
	local ok, err
	local fn = pendingStart[co]
	if fn then
		pendingStart[co] = nil
		ok, err = coroutine.resume(co, fn, ...)
	else
		ok, err = coroutine.resume(co, ...)
	end
	Sched.CUR = prev
	if not ok then
		-- only raw game coroutines (coroutine.create in game code) can die with an error here
		local frames = Report.frames(co, 0)
		Report.add("runtime", realmName(realm or prev), Report.cleanMessage(err), frames)
	end
	return ok
end

-- New thread for fn in realm, not started
function Sched.create(realm, fn)
	local co = coroutine.create(threadBody)
	threadRealm[co] = realm
	pendingStart[co] = fn
	return co
end

-- Tag a raw coroutine created by game code
function Sched.tag(co, realm)
	threadRealm[co] = realm
end

function Sched.spawn(realm, fn, ...)
	local co = Sched.create(realm, fn)
	Sched.resume(co, ...)
	return co
end

----------------------------------------------------------------------
-- Deferred queue
----------------------------------------------------------------------
local deferQ = {}

-- job: thread to resume with args
function Sched.deferThread(co, ...)
	table.insert(deferQ, { co = co, args = table.pack(...) })
end

-- job: call fn(...) in a new thread of realm
function Sched.deferCall(realm, fn, ...)
	table.insert(deferQ, { realm = realm, fn = fn, args = table.pack(...) })
end

function Sched.flush()
	local rounds = 0
	while #deferQ > 0 do
		rounds += 1
		if rounds > 400 then
			Report.add("runtime", "engine", string.format("deferred-event loop: %d jobs still queued after 400 rounds in one frame (re-entrancy)", #deferQ), {})
			table.clear(deferQ)
			return
		end
		local batch = deferQ
		deferQ = {}
		for _, job in batch do
			if job.co then
				Sched.resume(job.co, table.unpack(job.args, 1, job.args.n))
			else
				local r = job.realm
				if not (r and r.dead) then
					local co = Sched.create(r, job.fn)
					Sched.resume(co, table.unpack(job.args, 1, job.args.n))
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Waiting
----------------------------------------------------------------------
local function current()
	local co = coroutine.running()
	return co
end

-- Yield the current thread until `t` seconds pass. Returns elapsed.
function Sched.wait(t, what)
	local co = current()
	if not coroutine.isyieldable() then
		error("attempt to yield across metamethod/C-call boundary (task.wait from a non-yieldable context)", 2)
	end
	t = tonumber(t) or 0
	if t ~= t or t < 0 then
		t = 0
	end
	local start = Sched.now
	local token = (waitToken[co] or 0) + 1
	-- token is incremented by resume; we compute the value it will have *after* we yield
	local target = Sched.now + math.max(t, 1e-6)
	heapPush({ t = target, co = co, token = token - 1 })
	threadInfo[co] = { what = what or ("task.wait(" .. tostring(t) .. ")"), since = Sched.now }
	coroutine.yield()
	return Sched.now - start
end

-- Yield until resumed by someone (signal, remote reply). Returns resume args.
function Sched.suspend(what)
	local co = current()
	threadInfo[co] = { what = what, since = Sched.now }
	return coroutine.yield()
end

function Sched.waitToken(co)
	return waitToken[co] or 0
end

-- Wake `co` (with args) at time t if it has not been resumed since token was taken
function Sched.wakeAt(t, co, token, ...)
	heapPush({ t = t, co = co, token = token, args = table.pack(...) })
end

function Sched.delay(realm, t, fn, ...)
	local co = Sched.create(realm, fn)
	t = tonumber(t) or 0
	if t ~= t or t < 0 then
		t = 0
	end
	heapPush({ t = Sched.now + math.max(t, 1e-6), co = co, token = 0, args = table.pack(...), fresh = true })
	return co
end

function Sched.cancel(co)
	cancelled[co] = true
	pendingStart[co] = nil
	if coroutine.status(co) == "suspended" then
		pcall(coroutine.close, co)
	end
end

function Sched.isCancelled(co)
	return cancelled[co] == true
end

----------------------------------------------------------------------
-- Frame step
----------------------------------------------------------------------
Sched.frameHooks = {} -- functions called each frame (after timers): fn(dt)

local function runTimers()
	while #heap > 0 and heap[1].t <= Sched.now + 1e-9 do
		local e = heapPop()
		if e.call then
			local ok, err = xpcall(e.call, function(m)
				return tostring(m) .. "\n" .. debug.traceback()
			end)
			if not ok then
				Report.add("runtime", "harness", "[harness] timer callback failed: " .. tostring(err), {})
			end
		elseif e.fresh then
			if not cancelled[e.co] then
				Sched.resume(e.co, table.unpack(e.args, 1, e.args.n))
			end
		else
			local co = e.co
			if (waitToken[co] or 0) == e.token and coroutine.status(co) == "suspended" and not cancelled[co] then
				if e.args then
					Sched.resume(co, table.unpack(e.args, 1, e.args.n))
				else
					Sched.resume(co)
				end
			end
		end
	end
end

function Sched.step()
	Sched.frame += 1
	Sched.now = Sched.frame * Sched.FRAME
	runTimers()
	Sched.flush()
	for _, hook in Sched.frameHooks do
		hook(Sched.FRAME)
		Sched.flush()
	end
end

-- Run frames until simulated time reaches t
function Sched.runUntil(t, onFrame)
	while Sched.now < t - 1e-9 do
		Sched.step()
		if onFrame then
			onFrame()
		end
	end
end

-- Threads that are still suspended waiting on something (for the end-of-run report)
function Sched.blockedThreads()
	local list = {}
	for co, info in threadInfo do
		if coroutine.status(co) == "suspended" and not cancelled[co] then
			local r = threadRealm[co]
			if not (r and r.dead) then
				table.insert(list, { co = co, info = info, realm = r })
			end
		end
	end
	return list
end

return Sched
