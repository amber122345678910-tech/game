--!nocheck
-- Realms and scripts:
--  * converts the deserialized place (Lune instances) into the emulated tree (class, name, properties,
--    attributes, tags, script Source);
--  * builds the global environment of a realm (Roblox globals backed by the sim: task/wait/tick/os on the
--    simulated clock, deterministic math.random, Instance.new, require with a per-realm module cache);
--  * runs Scripts (server) and LocalScripts (client).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local ClassDB = require("./classdb")
local Classes = require("./classes")
local Sched = require("./sched")
local Report = require("./report")
local DT = require("./datatypes")
local World = require("./world")
local Services = require("./services")

local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum
local DATA = Engine.DATA
local typeof = Engine.typeof

local Realm = {}
local ROOT = Report.ROOT

----------------------------------------------------------------------
-- Source file mapping (for readable stack traces)
----------------------------------------------------------------------
local MOUNTS = {
	{ "ReplicatedStorage.Shared", "src/shared" },
	{ "ServerScriptService.Server", "src/server" },
	{ "StarterPlayer.StarterPlayerScripts.Client", "src/client" },
}
local function srcFileFor(fullName)
	for _, m in MOUNTS do
		local prefix = m[1]
		if fullName == prefix or string.sub(fullName, 1, #prefix + 1) == prefix .. "." then
			local rest = string.sub(fullName, #prefix + 2)
			local base = m[2] .. (if rest ~= "" then "/" .. string.gsub(rest, "%.", "/") else "")
			for _, suffix in { ".luau", ".server.luau", ".client.luau", ".lua", "/init.luau", "/init.server.luau", "/init.client.luau" } do
				if fs.isFile(ROOT .. base .. suffix) then
					return base .. suffix
				end
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Place conversion
----------------------------------------------------------------------
local function convertValue(v)
	local t = typeof(v)
	if t == "Font" then
		return DT.fromLuneFont(v)
	end
	return v
end

function Realm.convertPlace(luneGame)
	local refs = {} -- pending instance references: { d, prop, luneValue }
	local byName = {} -- fullName -> { { lune, proxy } }
	local count = 0

	local function convert(li, parentU, fullName)
		local className = li.ClassName
		if not ClassDB.exists(className) then
			Report.add("note", "engine", "unknown class in place: " .. className .. " (" .. fullName .. ") — loaded as Folder", {})
			className = "Folder"
		end
		local u, d = Engine.makeInstance(className, 0)
		count += 1
		d.props.Name = li.Name
		for _, prop in ClassDB.reflProps(className) do
			if prop ~= "Parent" and prop ~= "Name" and prop ~= "ClassName" then
				local ok, v = pcall(function()
					return li[prop]
				end)
				if ok and v ~= nil then
					if typeof(v) == "Instance" then
						table.insert(refs, { d = d, prop = prop, value = v })
					else
						d.props[prop] = convertValue(v)
					end
				end
			end
		end
		local okA, attrs = pcall(function()
			return li:GetAttributes()
		end)
		if okA then
			for k, v in attrs do
				d.attrs[k] = convertValue(v)
			end
		end
		local okT, tags = pcall(function()
			return li:GetTags()
		end)
		if okT and #tags > 0 then
			d.tags = {}
			for _, tg in tags do
				d.tags[tg] = true
			end
		end
		if d.cls.isA.LuaSourceContainer then
			local okS, src = pcall(function()
				return li.Source
			end)
			d.source = if okS then src else ""
			d.srcFile = srcFileFor(fullName)
		end
		if parentU then
			d.parent = parentU
			table.insert(DATA[parentU].children, u)
		end
		local list = byName[fullName]
		if not list then
			list = {}
			byName[fullName] = list
		end
		table.insert(list, { lune = li, proxy = u })
		for _, c in li:GetChildren() do
			convert(c, u, if fullName == "" then c.Name else fullName .. "." .. c.Name)
		end
		return u, d
	end

	local gameU, gameD = Engine.makeInstance("DataModel", 0)
	gameD.props.Name = "Game"
	Engine.gameData = gameD
	World.game = gameU
	World.gameD = gameD
	for _, svc in luneGame:GetChildren() do
		local u = convert(svc, gameU, svc.Name)
		Services.registerService(svc.ClassName, u)
	end
	-- resolve instance references
	for _, r in refs do
		local okN, fn = pcall(function()
			return r.value:GetFullName()
		end)
		local found = nil
		if okN then
			for _, cand in byName[fn] or {} do
				if cand.lune == r.value then
					found = cand.proxy
					break
				end
			end
		end
		if found then
			r.d.props[r.prop] = found
		end
	end
	return gameU, count
end

----------------------------------------------------------------------
-- Globals of a realm
----------------------------------------------------------------------
local compiled = {} -- source -> bytecode

local function logLine(realm, kind, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	local text = table.concat(parts, " ")
	Report.logLine(string.format("[%s %s] %s: %s", Report.fmtTime(Sched.now), realm.name, kind, text))
	return text
end

local function looksLikeError(text)
	return string.find(text, "%.luau:%d+:") ~= nil
		or string.find(text, "attempt to ", 1, true) ~= nil
		or string.find(text, "is not a valid member", 1, true) ~= nil
		or string.find(text, "Stack Begin", 1, true) ~= nil
		or string.find(text, "not emulated", 1, true) ~= nil
		or string.find(text, "Unable to assign property", 1, true) ~= nil
end

function Realm.makeGlobals(realm)
	local G = {}
	realm.G = G
	local gen = DT.makeGen(1000 + realm.id * 7919 + 17)

	-- math with deterministic random
	local m = table.clone(math)
	m.random = function(a, b)
		local r = gen()
		if a == nil then
			return r
		end
		if b == nil then
			a, b = 1, a
		end
		a, b = math.floor(a), math.floor(b)
		if a > b then
			error("bad argument #" .. (if b == nil then 1 else 2) .. " to 'random' (interval is empty)", 2)
		end
		return a + math.floor(r * (b - a + 1))
	end
	m.randomseed = function(s)
		gen = DT.makeGen(s or 0)
	end
	G.math = m

	-- os on the simulated clock
	G.os = {
		clock = function()
			return Sched.now
		end,
		time = function(t)
			if t ~= nil then
				return os.time(t)
			end
			return math.floor(Sched.EPOCH + Sched.now + Sched.osTimeOffset)
		end,
		date = function(fmt, t)
			return os.date(fmt, t or math.floor(Sched.EPOCH + Sched.now + Sched.osTimeOffset))
		end,
		difftime = os.difftime,
	}

	-- coroutines tagged with the realm
	local co = table.clone(coroutine)
	co.create = function(f)
		local c = coroutine.create(f)
		Sched.tag(c, Sched.CUR or realm)
		return c
	end
	co.wrap = function(f)
		local c = coroutine.create(f)
		Sched.tag(c, Sched.CUR or realm)
		return function(...)
			local prev = Sched.CUR
			local res = table.pack(coroutine.resume(c, ...))
			Sched.CUR = prev
			if not res[1] then
				error(Report.cleanMessage(res[2]), 2)
			end
			return table.unpack(res, 2, res.n)
		end
	end
	co.resume = function(c, ...)
		local prev = Sched.CUR
		Sched.CUR = Sched.threadRealm[c] or prev
		local res = table.pack(coroutine.resume(c, ...))
		Sched.CUR = prev
		return table.unpack(res, 1, res.n)
	end
	G.coroutine = co

	-- task
	local function cur()
		return Sched.CUR or realm
	end
	G.task = {
		spawn = function(f, ...)
			if type(f) == "thread" then
				Sched.resume(f, ...)
				return f
			elseif type(f) == "function" then
				return Sched.spawn(cur(), f, ...)
			end
			error("invalid argument #1 to 'spawn' (function or thread expected, got " .. typeof(f) .. ")", 2)
		end,
		defer = function(f, ...)
			if type(f) == "thread" then
				Sched.deferThread(f, ...)
				return f
			elseif type(f) == "function" then
				local c = Sched.create(cur(), f)
				Sched.deferThread(c, ...)
				return c
			end
			error("invalid argument #1 to 'defer' (function or thread expected, got " .. typeof(f) .. ")", 2)
		end,
		delay = function(t, f, ...)
			if t ~= nil and type(t) ~= "number" then
				error("invalid argument #1 to 'delay' (number expected, got " .. typeof(t) .. ")", 2)
			end
			if type(f) == "thread" then
				Sched.wakeAt(Sched.now + math.max(t or 0, 1e-6), f, Sched.waitToken(f), ...)
				return f
			elseif type(f) == "function" then
				return Sched.delay(cur(), t or 0, f, ...)
			end
			error("invalid argument #2 to 'delay' (function or thread expected, got " .. typeof(f) .. ")", 2)
		end,
		wait = function(t)
			if t ~= nil and type(t) ~= "number" then
				error("invalid argument #1 to 'wait' (number expected, got " .. typeof(t) .. ")", 2)
			end
			return Sched.wait(t or 0)
		end,
		cancel = function(c)
			if type(c) ~= "thread" then
				error("invalid argument #1 to 'cancel' (thread expected, got " .. typeof(c) .. ")", 2)
			end
			Sched.cancel(c)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	}

	local deprecatedNoted = {}
	local function deprecated(name, use)
		if not deprecatedNoted[name] then
			deprecatedNoted[name] = true
			Report.add("deprecated", realm.name, string.format("global %s() is deprecated (use %s)", name, use), Report.frames(nil, 2))
		end
	end
	G.wait = function(t)
		deprecated("wait", "task.wait")
		local e = Sched.wait(math.max(t or 0, 0.03))
		return e, Sched.now
	end
	G.delay = function(t, f)
		deprecated("delay", "task.delay")
		Sched.delay(cur(), math.max(t or 0, 0.03), f)
	end
	G.spawn = function(f)
		deprecated("spawn", "task.spawn/task.defer")
		Sched.delay(cur(), 0.03, f)
	end
	G.tick = function()
		return Sched.EPOCH + Sched.now + Sched.osTimeOffset
	end
	G.time = function()
		return Sched.now
	end
	G.elapsedTime = function()
		return Sched.now
	end

	G.print = function(...)
		logLine(cur(), "print", ...)
	end
	G.warn = function(...)
		local text = logLine(cur(), "warn", ...)
		local frames = Report.frames(nil, 1)
		local cat = if looksLikeError(text) then "caught" else "warn"
		if cat == "caught" then
			-- attach the stack of the original error (captured when the game's pcall swallowed it)
			for i = #Report.recentSwallowed, 1, -1 do
				local sw = Report.recentSwallowed[i]
				if string.find(text, string.sub(sw.msg, 1, 80), 1, true) then
					local merged = table.clone(sw.frames)
					for _, f in frames do
						table.insert(merged, { src = f.src, line = f.line, name = (f.name or "") .. " [warn]" })
					end
					frames = merged
					break
				end
			end
		end
		Report.add(cat, cur().name, text, frames)
	end
	G.printidentity = function()
		logLine(cur(), "print", "Current identity is 2")
	end
	G.version = function()
		return "0.694.0.6940982"
	end
	G.typeof = typeof
	G.require = function(target)
		return Realm.require(cur(), target)
	end

	-- Roblox datatypes
	for _, name in {
		"Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "BrickColor", "ColorSequence", "ColorSequenceKeypoint",
		"NumberSequence", "NumberSequenceKeypoint", "NumberRange", "Rect", "Ray", "Region3", "Region3int16", "Vector3int16",
		"Vector2int16", "Axes", "Faces", "PhysicalProperties", "Content",
	} do
		G[name] = roblox[name]
	end
	G.Enum = roblox.Enum
	G.Font = DT.Font
	G.TweenInfo = DT.TweenInfo
	G.RaycastParams = DT.RaycastParams
	G.OverlapParams = DT.OverlapParams
	G.Random = DT.Random
	G.DateTime = DT.makeDateTime(function()
		return Sched.EPOCH + Sched.now + Sched.osTimeOffset
	end)

	G.Instance = {
		new = function(className, parent)
			if type(className) ~= "string" then
				error("invalid argument #1 to 'new' (string expected, got " .. typeof(className) .. ")", 2)
			end
			if not ClassDB.creatable(className) then
				Engine.throw("runtime", 'Unable to create an Instance of type "' .. className .. '"')
			end
			local r = cur()
			local u, d = Engine.makeInstance(className, if r.id > 0 then r.id else 0)
			if parent ~= nil then
				Engine.record("deprecated", "Instance.new(className, parent) — set Parent last (performance)")
				Engine.setParent(d, parent, r)
			end
			return u
		end,
		fromExisting = function(inst)
			local d = Engine.argInstance(inst, 1, "fromExisting")
			local r = cur()
			local u, nd = Engine.makeInstance(d.class, if r.id > 0 then r.id else 0)
			for k, v in d.props do
				nd.props[k] = v
			end
			return u
		end,
	}

	G.game = World.game
	G.Game = World.game
	G.workspace = World.workspace
	G.Workspace = World.workspace
	G.shared = realm.shared
	realm.userG = realm.userG or {}
	G._G = realm.userG
	G.plugin = nil
	G.settings = function()
		Engine.notEmulated("settings()")
	end
	G.UserSettings = function()
		return Realm.userSettings()
	end
	G.stats = function()
		Engine.notEmulated("stats()")
	end

	-- standard library
	G.assert = assert
	G.error = error
	G.getmetatable = getmetatable
	G.ipairs = ipairs
	G.next = next
	G.pairs = pairs
	-- pcall that remembers code errors it swallows (reported only if the game never warn()s about them)
	local function codeError(msg)
		local m = tostring(msg)
		return string.find(m, "attempt to ", 1, true) ~= nil
			or string.find(m, "invalid argument", 1, true) ~= nil
			or string.find(m, "missing or nil", 1, true) ~= nil
			or string.find(m, "is not a valid member", 1, true) ~= nil
			or string.find(m, "Unable to ", 1, true) ~= nil
			or string.find(m, "stack overflow", 1, true) ~= nil
	end
	local function onSwallow(e)
		if codeError(e) then
			local frames = Report.frames(nil, 1)
			if #frames > 0 then
				local msg = Report.cleanMessage(e)
				table.insert(Report.recentSwallowed, { msg = msg, frames = frames })
				if #Report.recentSwallowed > 40 then
					table.remove(Report.recentSwallowed, 1)
				end
				if e ~= Sched.lastThrown then
					Report.add("swallowed", (Sched.CUR or realm).name, msg, frames)
				end
			end
		end
		return e
	end
	G.pcall = function(f, ...)
		return xpcall(f, onSwallow, ...)
	end
	G.rawequal = rawequal
	G.rawget = rawget
	G.rawlen = rawlen
	G.rawset = rawset
	G.select = select
	G.setmetatable = setmetatable
	G.tonumber = tonumber
	G.tostring = tostring
	G.type = type
	G.xpcall = xpcall
	G.newproxy = newproxy
	G.gcinfo = gcinfo
	G.unpack = table.unpack
	G.string = string
	G.table = table
	G.bit32 = bit32
	G.utf8 = utf8
	G.buffer = buffer
	G.vector = vector
	G.debug = {
		traceback = function(a, b, c)
			local s
			if type(a) == "thread" then
				s = debug.traceback(a, b, c)
			else
				s = debug.traceback(a, (b or 1) + 1)
			end
			if type(s) ~= "string" then
				return s
			end
			local keep = {}
			for line in string.gmatch(s, "[^\n]+") do
				if not string.find(line, "tools/sim", 1, true) then
					table.insert(keep, line)
				end
			end
			return table.concat(keep, "\n")
		end,
		info = debug.info,
		profilebegin = function() end,
		profileend = function() end,
		setmemorycategory = function() end,
		resetmemorycategory = function() end,
		dumpcodesize = function() end,
	}
	G.getfenv = getfenv
	G.setfenv = setfenv
	G.loadstring = function()
		return nil, "loadstring() is not available"
	end

	-- unknown globals read as nil (like Roblox) but are reported
	local unknownSeen = {}
	setmetatable(G, {
		__index = function(_, k)
			if k == "_G" then
				return nil
			end
			if not unknownSeen[k] then
				unknownSeen[k] = true
				Report.add("member", realm.name, "Unknown global '" .. tostring(k) .. "' (nil in Roblox)", Report.frames(nil, 1))
			end
			return nil
		end,
	})
	return G
end

local userSettingsU = nil
function Realm.userSettings()
	if not userSettingsU then
		local u, d = World.new("UserSettings", { Name = "UserSettings" }, nil, 0)
		local gs = World.new("UserGameSettings", { Name = "UserGameSettings" }, u, 0)
		d.userGameSettings = gs
		userSettingsU = u
	end
	return userSettingsU
end
Engine.define("GenericSettings", {
	methods = {
		GetService = function(u, name)
			local d = Engine.self(u, "GetService")
			if d.class == "UserSettings" and name == "UserGameSettings" then
				return d.userGameSettings
			end
			Engine.notEmulated("UserSettings():GetService(" .. tostring(name) .. ")")
		end,
	},
})

----------------------------------------------------------------------
-- require / script execution
----------------------------------------------------------------------
local function loadChunk(d, realm)
	local src = d.source or ""
	local bc = compiled[src]
	if not bc then
		local ok, res = pcall(luau.compile, src, { optimizationLevel = 1, debugLevel = 2 })
		if not ok then
			error("Syntax error in " .. (d.srcFile or Engine.fullName(d)) .. ": " .. tostring(res), 0)
		end
		bc = res
		compiled[src] = bc
	end
	local env = setmetatable({ script = d.proxy }, { __index = realm.G })
	local name = if d.srcFile then "@" .. d.srcFile else "=" .. Engine.fullName(d)
	return luau.load(bc, { debugName = name, environment = env, injectGlobals = false })
end

function Realm.require(realm, target)
	if type(target) == "number" then
		Engine.notEmulated("require(assetId)")
	end
	local d = DATA[target]
	if not d or d.class ~= "ModuleScript" then
		Engine.throw("runtime", "Attempted to call require with invalid argument(s).")
	end
	local entry = realm.modules[d]
	if entry then
		if entry.failed then
			Engine.throw("runtime", "Requested module experienced an error while loading")
		end
		return entry.value
	end
	local me = coroutine.running()
	local loader = realm.loading[d]
	if loader then
		if loader == me then
			Engine.throw("runtime", "Requested module was required recursively (" .. Engine.fullName(d) .. ")")
		end
		while realm.loading[d] do
			Sched.wait(0, "require (module loading in another thread)")
		end
		return Realm.require(realm, target)
	end
	realm.loading[d] = me
	local fn = loadChunk(d, realm)
	local res
	local ok = xpcall(function()
		res = table.pack(fn())
	end, function(e)
		if e ~= Sched.lastThrown then
			Report.add("runtime", realm.name, Report.cleanMessage(e), Report.frames(nil, 1), "while loading module " .. (d.srcFile or Engine.fullName(d)))
		end
		Sched.lastThrown = nil
		return e
	end)
	realm.loading[d] = nil
	if not ok then
		realm.modules[d] = { failed = true }
		Engine.throw("runtime", "Requested module experienced an error while loading (" .. (d.srcFile or Engine.fullName(d)) .. ")")
	end
	if res.n ~= 1 then
		realm.modules[d] = { failed = true }
		Engine.throw("runtime", "Module code did not return exactly one value (" .. (d.srcFile or Engine.fullName(d)) .. ")")
	end
	realm.modules[d] = { value = res[1] }
	return res[1]
end

-- Run a Script/LocalScript in its realm (a new thread, like the engine)
function Realm.runScript(realm, scriptU)
	local d = DATA[scriptU]
	local fn = loadChunk(d, realm)
	Report.logLine(string.format("[%s %s] run %s", Report.fmtTime(Sched.now), realm.name, d.srcFile or Engine.fullName(d)))
	return Sched.spawn(realm, fn)
end

-- Module value already loaded in a realm (for the harness/bots)
function Realm.module(realm, scriptU)
	local e = realm.modules[DATA[scriptU]]
	return e and e.value
end

return Realm
