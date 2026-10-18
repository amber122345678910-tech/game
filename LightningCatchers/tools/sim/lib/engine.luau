--!nocheck
-- Emulated Roblox Instance core.
--  * Instances are userdata proxies (newproxy) with locked metatables, like the real engine.
--  * Every member access is validated against the class definitions (ClassDB): unknown properties, methods
--    and events raise the real Roblox error text and are recorded in the report with the game stack trace.
--  * Writes are type-checked against the declared property type (enum/datatype/instance class).
--  * Realms: instances created by a client are visible only to that client; a client writing a property or
--    attribute of a replicated (server) instance changes only its own view (overlay), like FilteringEnabled.
--    The local character's physics (CFrame/Position/velocities) replicates (network ownership).
--  * Engine signals are deferred (Workspace.SignalBehavior = Deferred) and delivered per realm.
local roblox = require("@lune/roblox")
local ClassDB = require("./classdb")
local Sched = require("./sched")
local Report = require("./report")
local DT = require("./datatypes")

local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local Engine = {}
Engine.ClassDB = ClassDB

local DATA = {} -- proxy -> data
Engine.DATA = DATA
local NIL = newproxy(false) -- overlay marker for "set to nil"
Engine.NIL = NIL

Engine.SIGTYPE = setmetatable({}, { __mode = "k" }) -- signal/connection tables -> typeof name

----------------------------------------------------------------------
-- typeof
----------------------------------------------------------------------
local rtypeof = typeof
function Engine.typeof(v)
	if DATA[v] then
		return "Instance"
	end
	local t = rtypeof(v)
	if t == "table" then
		local k = Engine.SIGTYPE[v] or DT.kind[v]
		if k then
			return k
		end
	end
	return t
end
local typeof = Engine.typeof

----------------------------------------------------------------------
-- Errors
----------------------------------------------------------------------
-- Is the failing game function called *directly* by pcall/xpcall? (then the error is a deliberate probe
-- such as `pcall(function() return UIS.PreferredInput end)`)
local function insideGamePcall()
	for i = 2, 60 do
		local s = debug.info(i, "s")
		if s == nil then
			return false
		end
		if s ~= "[C]" and not string.find(s, "tools/sim", 1, true) then
			local f = debug.info(i + 1, "f")
			return f == pcall or f == xpcall
		end
	end
	return false
end
Engine.insideGamePcall = insideGamePcall

-- Record an engine error with the game's stack and raise it
function Engine.throw(category, msg, probeCategory)
	local cat = category
	if probeCategory and insideGamePcall() then
		cat = probeCategory
	end
	Report.add(cat, Sched.realmName(Sched.CUR), msg, Report.frames(nil, 1))
	Sched.lastThrown = msg
	error(msg, 0)
end

-- Record without raising
function Engine.record(category, msg, extra)
	Report.add(category, Sched.realmName(Sched.CUR), msg, Report.frames(nil, 1), extra)
end

function Engine.notEmulated(what)
	Engine.throw("emu", "not emulated: " .. what)
end

----------------------------------------------------------------------
-- Signals (RBXScriptSignal)
----------------------------------------------------------------------
local SignalMethods = {}
local SignalMT = {
	__index = function(s, k)
		local m = SignalMethods[k]
		if m then
			return m
		end
		Engine.throw("member", tostring(k) .. " is not a valid member of RBXScriptSignal", "member_probe")
	end,
	__newindex = function()
		error("RBXScriptSignal is read-only", 2)
	end,
	__tostring = function(s)
		return "Signal " .. (s.name or "?")
	end,
	__metatable = "The metatable is locked",
}

local ConnMethods = {}
local ConnMT = {
	__index = function(c, k)
		if k == "Connected" then
			return c._c.connected
		end
		local m = ConnMethods[k]
		if m then
			return m
		end
		Engine.throw("member", tostring(k) .. " is not a valid member of RBXScriptConnection", "member_probe")
	end,
	__newindex = function()
		error("RBXScriptConnection is read-only", 2)
	end,
	__tostring = function()
		return "Connection"
	end,
	__metatable = "The metatable is locked",
}

function ConnMethods.Disconnect(c)
	c._c.connected = false
end

-- opts: { immediate = bool (run handlers synchronously, e.g. RunService), name, onConnect(realm) }
function Engine.newSignal(name, opts)
	local s = setmetatable({ name = name, conns = {}, waiters = {}, opts = opts or false }, SignalMT)
	Engine.SIGTYPE[s] = "RBXScriptSignal"
	return s
end
local newSignal = Engine.newSignal

local function connect(s, fn, once)
	if type(fn) ~= "function" then
		Engine.throw("runtime", "Attempt to connect failed: Passed value is not a function")
	end
	local realm = Sched.CUR
	if s.opts and s.opts.onConnect then
		s.opts.onConnect(realm)
	end
	local c = { fn = fn, realm = realm, connected = true, once = once }
	table.insert(s.conns, c)
	-- prune dead connections occasionally
	if #s.conns > 64 then
		local live = {}
		for _, x in s.conns do
			if x.connected then
				table.insert(live, x)
			end
		end
		s.conns = live
	end
	local handle = setmetatable({ _c = c }, ConnMT)
	Engine.SIGTYPE[handle] = "RBXScriptConnection"
	return handle
end

function SignalMethods.Connect(s, fn)
	if getmetatable(s) ~= "The metatable is locked" or not s.conns then
		Engine.throw("runtime", "Expected ':' not '.' calling member function Connect")
	end
	return connect(s, fn, false)
end
SignalMethods.connect = SignalMethods.Connect
function SignalMethods.ConnectParallel(s, fn)
	return connect(s, fn, false)
end
function SignalMethods.Once(s, fn)
	return connect(s, fn, true)
end
function SignalMethods.Wait(s)
	if s.opts and s.opts.onConnect then
		s.opts.onConnect(Sched.CUR)
	end
	local co = coroutine.running()
	table.insert(s.waiters, { co = co, realm = Sched.CUR, token = Sched.waitToken(co) })
	return Sched.suspend(s.name .. ":Wait()")
end

-- Fire: filter = nil (all realms) or a realm (only that realm sees it)
function Engine.fire(s, filter, ...)
	local conns = s.conns
	local n = #conns
	local immediate = s.opts and s.opts.immediate
	if n > 0 then
		for i = 1, n do
			local c = conns[i]
			if c.connected then
				local r = c.realm
				if (filter == nil or r == filter or (r and r.id < 0)) and not (r and r.dead) then
					if c.once then
						c.connected = false
					end
					if immediate then
						local co = Sched.create(r, c.fn)
						Sched.resume(co, ...)
					else
						Sched.deferCall(r, c.fn, ...)
					end
				end
			end
		end
	end
	if #s.waiters > 0 then
		local keep = {}
		for _, w in s.waiters do
			local r = w.realm
			if filter == nil or r == filter or (r and r.id < 0) then
				if Sched.waitToken(w.co) == w.token then
					if immediate then
						Sched.resume(w.co, ...)
					else
						Sched.deferThread(w.co, ...)
					end
				end
			else
				table.insert(keep, w)
			end
		end
		s.waiters = keep
	end
end
local fire = Engine.fire

function Engine.hasListeners(s)
	return #s.conns > 0 or #s.waiters > 0
end

function Engine.disconnectAll(s)
	for _, c in s.conns do
		c.connected = false
	end
	table.clear(s.conns)
	table.clear(s.waiters)
end

----------------------------------------------------------------------
-- Classes: behaviors (getters/setters/methods/events) layered over ClassDB
----------------------------------------------------------------------
local behaviors = {} -- className -> { getters = {}, setters = {}, methods = {}, init = fn }
Engine.behaviors = behaviors

function Engine.define(className, b)
	local cur = behaviors[className]
	if not cur then
		cur = { getters = {}, setters = {}, methods = {}, inits = {} }
		behaviors[className] = cur
	end
	for k, v in b.getters or {} do
		cur.getters[k] = v
	end
	for k, v in b.setters or {} do
		cur.setters[k] = v
	end
	for k, v in b.methods or {} do
		cur.methods[k] = v
	end
	if b.init then
		table.insert(cur.inits, b.init)
	end
	if b.extraMembers then
		cur.extraMembers = cur.extraMembers or {}
		for k, v in b.extraMembers do
			cur.extraMembers[k] = v
		end
	end
end

local classInfoCache = {}
local function classInfo(name)
	local ci = classInfoCache[name]
	if ci then
		return ci
	end
	if not ClassDB.exists(name) then
		return nil
	end
	ci = {
		name = name,
		members = table.clone(ClassDB.members(name)),
		defaults = ClassDB.defaults(name),
		getters = {},
		setters = {},
		impl = {},
		inits = {},
		isA = {},
	}
	local chain = ClassDB.chain(name)
	for i = #chain, 1, -1 do
		local cn = chain[i]
		ci.isA[cn] = true
		local b = behaviors[cn]
		if b then
			for k, v in b.getters do
				ci.getters[k] = v
			end
			for k, v in b.setters do
				ci.setters[k] = v
			end
			for k, v in b.methods do
				ci.impl[k] = v
			end
			for _, f in b.inits do
				table.insert(ci.inits, f)
			end
			if b.extraMembers then
				for k, v in b.extraMembers do
					ci.members[k] = v
				end
			end
		end
	end
	classInfoCache[name] = ci
	return ci
end
Engine.classInfo = classInfo

----------------------------------------------------------------------
-- Realm visibility
----------------------------------------------------------------------
local function visibleTo(d, R)
	local o = d.owner
	if R == nil or R.id < 0 then
		return true
	end
	if d.serverOnly and R.id > 0 then
		return false -- ServerScriptService / ServerStorage never replicate to clients
	end
	if o ~= 0 and o ~= R.id then
		return false
	end
	local h = d.hidden
	if h and h[R.id] then
		return false
	end
	return true
end
Engine.visibleTo = visibleTo

-- Realm filter for events about instance d: nil (everyone) or the owning client realm
local function eventFilter(d)
	if d.owner ~= 0 then
		return Engine.realmById(d.owner)
	end
	return nil
end
Engine.eventFilter = eventFilter

Engine.realmById = function(id)
	return Sched.realms[id]
end

----------------------------------------------------------------------
-- Instance proxies
----------------------------------------------------------------------
local instIndex, instNewindex

local function instToString(u)
	local d = DATA[u]
	return d and d.props.Name or "Instance"
end

local idCounter = 0
Engine.stats = { created = {} }

local function makeInstance(className, owner)
	local ci = classInfo(className)
	if not ci then
		error("Unable to create an Instance of type \"" .. tostring(className) .. "\"", 3)
	end
	local u = newproxy(true)
	local mt = getmetatable(u)
	mt.__index = instIndex
	mt.__newindex = instNewindex
	mt.__tostring = instToString
	mt.__metatable = "The metatable is locked"
	idCounter += 1
	local d = {
		proxy = u,
		class = className,
		cls = ci,
		props = { Name = className },
		parent = nil,
		children = {},
		attrs = {},
		tags = nil,
		sigs = nil,
		owner = owner or 0,
		overlay = nil,
		hidden = nil,
		destroyed = false,
		id = idCounter,
	}
	DATA[u] = d
	for _, f in ci.inits do
		f(d)
	end
	local st = Engine.stats.created
	local key = (if (owner or 0) > 0 then "client" else "server") .. ":" .. className
	st[key] = (st[key] or 0) + 1
	return u, d
end
Engine.makeInstance = makeInstance

function Engine.data(u)
	return DATA[u]
end

local function getSignal(d, key)
	local sigs = d.sigs
	if not sigs then
		sigs = {}
		d.sigs = sigs
	end
	local s = sigs[key]
	if not s then
		s = newSignal(d.props.Name .. "." .. key)
		sigs[key] = s
	end
	return s
end
Engine.getSignal = getSignal

-- Fire a named event of an instance if anyone listens
local function fireEvent(d, key, filter, ...)
	local sigs = d.sigs
	if sigs then
		local s = sigs[key]
		if s then
			fire(s, filter, ...)
		end
	end
end
Engine.fireEvent = fireEvent

----------------------------------------------------------------------
-- Type validation of property writes
----------------------------------------------------------------------
local DATATYPES = {
	Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, BrickColor = true,
	ColorSequence = true, NumberSequence = true, NumberRange = true, Rect = true, Font = true, Ray = true,
	PhysicalProperties = true, Faces = true, Axes = true, Region3 = true, Vector3int16 = true, Vector2int16 = true,
	Region3int16 = true, TweenInfo = true,
}

local enumCache = {}
local function enumByName(name)
	local e = enumCache[name]
	if e == nil then
		local ok, v = pcall(function()
			return Enum[name]
		end)
		e = if ok then v else false
		enumCache[name] = e
	end
	return e or nil
end
Engine.enumByName = enumByName

local function enumItemFrom(enum, v)
	local tv = typeof(v)
	if tv == "EnumItem" then
		if v.EnumType == enum then
			return v
		end
		return nil
	elseif tv == "string" then
		local ok, item = pcall(function()
			return enum[v]
		end)
		return if ok then item else nil
	elseif tv == "number" then
		for _, item in enum:GetEnumItems() do
			if item.Value == v then
				return item
			end
		end
	end
	return nil
end
Engine.enumItemFrom = enumItemFrom

local function buildChecker(m)
	local t = m.Type
	local optional = string.sub(t, -1) == "?"
	local base = if optional then string.sub(t, 1, -2) else t
	base = string.gsub(base, "^%s+", ""):gsub("%s+$", "")
	if base == "number" then
		return function(v)
			if type(v) == "number" then
				return true, v
			end
			return false
		end, "number"
	elseif base == "string" or base == "ContentId" then
		return function(v)
			local tv = type(v)
			if tv == "string" then
				return true, v
			elseif tv == "number" then
				return true, tostring(v)
			end
			return false
		end, "string"
	elseif base == "boolean" then
		return function(v)
			if type(v) == "boolean" then
				return true, v
			end
			return false
		end, "bool"
	elseif base == "Content" then
		return function(v)
			local tv = typeof(v)
			if tv == "string" or tv == "Content" then
				return true, v
			end
			return false
		end, "Content"
	end
	local ename = string.match(base, "^Enum(%w+)$")
	if ename then
		local enum = enumByName(ename)
		if enum then
			return function(v)
				local item = enumItemFrom(enum, v)
				if item then
					return true, item
				end
				return false
			end, "EnumItem of type " .. ename
		end
	end
	if DATATYPES[base] then
		return function(v)
			if typeof(v) == base then
				return true, v
			end
			return false
		end, base
	end
	if ClassDB.exists(base) then
		return function(v)
			if v == nil then
				return true, nil
			end
			local d = DATA[v]
			if d and d.cls.isA[base] then
				return true, v
			end
			return false
		end, base
	end
	return nil
end

local nanSeen = {}
local function isNanValue(v)
	local tv = typeof(v)
	if tv == "number" then
		return v ~= v or v == math.huge or v == -math.huge
	elseif tv == "Vector3" or tv == "Vector2" then
		local x, y = v.X, v.Y
		local z = if tv == "Vector3" then v.Z else 0
		return x ~= x or y ~= y or z ~= z or math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge
	elseif tv == "CFrame" then
		local p = v.Position
		local lv = v.LookVector
		return p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or lv.X ~= lv.X or math.abs(p.X) == math.huge or math.abs(p.Y) == math.huge
	end
	return false
end

local function validate(d, key, m, value)
	if m.check == nil then
		local f, expected = buildChecker(m)
		m.check = f or false
		m.expected = expected
	end
	local check = m.check
	if check then
		if value == nil and string.sub(m.Type, -1) ~= "?" and not ClassDB.exists(string.gsub(m.Type, "%?$", "")) then
			Engine.throw("proptype", string.format("Unable to assign property %s. %s expected, got nil", key, m.expected))
		end
		if value ~= nil then
			local ok, conv = check(value)
			if not ok then
				Engine.throw(
					"proptype",
					string.format("Unable to assign property %s. %s expected, got %s (on %s %q)", key, m.expected, typeof(value), d.class, Engine.fullName(d))
				)
			end
			value = conv
		end
	end
	if value ~= nil and isNanValue(value) then
		local k = d.class .. "." .. key
		if not nanSeen[k] then
			nanSeen[k] = true
			Engine.record("nan", string.format("NaN/inf assigned to %s.%s (%s)", d.class, key, tostring(value)))
		end
	end
	return value
end
Engine.validate = validate

----------------------------------------------------------------------
-- Property storage with realm overlays
----------------------------------------------------------------------
local PHYSICS_KEYS = {
	CFrame = true, Position = true, Orientation = true, Rotation = true, AssemblyLinearVelocity = true,
	AssemblyAngularVelocity = true, Velocity = true, RotVelocity = true,
}

-- Does client realm R own d physically (part of its own character)?
local function ownsPhysics(d, R, key)
	if not PHYSICS_KEYS[key] then
		return false
	end
	local player = R.player
	if not player then
		return false
	end
	local pd = DATA[player]
	local char = pd and pd.props.Character
	if not char then
		return false
	end
	local cur = d
	local guard = 0
	while cur and guard < 50 do
		if cur.proxy == char then
			return true
		end
		cur = cur.parent and DATA[cur.parent]
		guard += 1
	end
	return false
end

-- Raw read (realm view) of a property, including getters/defaults; no validation
local function readProp(d, key, R)
	local ov = d.overlay
	if ov and R then
		local o = ov[R.id]
		if o then
			local v = o[key]
			if v ~= nil then
				if v == NIL then
					return nil
				end
				return v
			end
		end
	end
	local v = d.props[key]
	if v ~= nil then
		return v
	end
	local g = d.cls.getters[key]
	if g then
		return g(d, R)
	end
	return d.cls.defaults[key]
end
Engine.readProp = readProp

local function fireChanged(d, key, filter, newValue)
	local sigs = d.sigs
	if not sigs then
		return
	end
	local s = sigs["prop:" .. key]
	if s then
		fire(s, filter)
	end
	s = sigs.Changed
	if s then
		if d.cls.isA.ValueBase and key == "Value" then
			fire(s, filter, newValue)
		elseif not d.cls.isA.ValueBase then
			fire(s, filter, key)
		end
	end
end
Engine.fireChanged = fireChanged

-- Store a property value (realm-aware) and fire change events
function Engine.setProp(d, key, value, R)
	R = R or Sched.CUR
	local rid = if R then R.id else 0
	if rid > 0 and d.owner == 0 and not ownsPhysics(d, R, key) then
		local ov = d.overlay
		if not ov then
			ov = {}
			d.overlay = ov
		end
		local o = ov[rid]
		if not o then
			o = {}
			ov[rid] = o
		end
		local old = readProp(d, key, R)
		o[key] = if value == nil then NIL else value
		if old ~= value then
			fireChanged(d, key, R, value)
		end
		return
	end
	local old = d.props[key]
	if old == nil then
		old = readProp(d, key, nil)
	end
	d.props[key] = value
	if rid <= 0 and d.overlay then
		for _, o in d.overlay do
			o[key] = nil
		end
	end
	if old ~= value then
		fireChanged(d, key, eventFilter(d), value)
	end
end
local setProp = Engine.setProp

-- Engine-internal write that bypasses overlays (engine-owned state such as Humanoid.MoveDirection)
function Engine.setRaw(d, key, value)
	local old = d.props[key]
	d.props[key] = value
	if old ~= value then
		fireChanged(d, key, eventFilter(d), value)
	end
end

----------------------------------------------------------------------
-- Hierarchy helpers
----------------------------------------------------------------------
function Engine.fullName(d)
	local parts = {}
	local cur = d
	local guard = 0
	while cur and guard < 60 do
		if cur.class == "DataModel" then
			break
		end
		table.insert(parts, 1, cur.props.Name)
		cur = cur.parent and DATA[cur.parent]
		guard += 1
	end
	return table.concat(parts, ".")
end

local function findChild(d, name, R)
	for _, c in d.children do
		local cd = DATA[c]
		if cd.props.Name == name and visibleTo(cd, R) then
			return c
		end
	end
	return nil
end
Engine.findChild = findChild

local function childrenOf(d, R)
	local out = {}
	for _, c in d.children do
		if visibleTo(DATA[c], R) then
			table.insert(out, c)
		end
	end
	return out
end
Engine.childrenOf = childrenOf

local function descendantsOf(d, R, out)
	out = out or {}
	for _, c in d.children do
		local cd = DATA[c]
		if visibleTo(cd, R) then
			table.insert(out, c)
			descendantsOf(cd, R, out)
		end
	end
	return out
end
Engine.descendantsOf = descendantsOf

local function isDescendantOf(d, ad)
	local cur = d.parent and DATA[d.parent]
	local guard = 0
	while cur and guard < 100 do
		if cur == ad then
			return true
		end
		cur = cur.parent and DATA[cur.parent]
		guard += 1
	end
	return false
end
Engine.isDescendantOf = isDescendantOf

Engine.gameData = nil -- DataModel data (set by world)

local function inGame(d)
	local g = Engine.gameData
	return g ~= nil and (d == g or isDescendantOf(d, g))
end
Engine.inGame = inGame

----------------------------------------------------------------------
-- Parent changes
----------------------------------------------------------------------
Engine.onParentChanged = {} -- hooks fn(d, oldParentData, newParentData)
Engine.waiters = {} -- WaitForChild bookkeeping: parentData -> list

local function forSubtree(d, fn)
	fn(d)
	for _, c in d.children do
		forSubtree(DATA[c], fn)
	end
end
Engine.forSubtree = forSubtree

local function resolveWaiters(pd, cd)
	local list = pd.waitList
	if not list then
		return
	end
	local name = cd.props.Name
	local keep = {}
	for _, w in list do
		if not w.done and w.name == name and visibleTo(cd, w.realm) then
			w.done = true
			if Sched.waitToken(w.co) == w.token then
				Sched.deferThread(w.co, cd.proxy)
			end
		elseif not w.done then
			table.insert(keep, w)
		end
	end
	pd.waitList = keep
end
Engine.resolveWaiters = resolveWaiters

function Engine.setParent(d, newParent, R)
	R = R or Sched.CUR
	local nd = nil
	if newParent ~= nil then
		nd = DATA[newParent]
		if not nd then
			Engine.throw("proptype", "Unable to assign property Parent. Instance expected, got " .. typeof(newParent))
		end
	end
	local oldParent = d.parent
	if oldParent == newParent then
		return
	end
	if d.destroyed or d.parentLocked then
		Engine.throw(
			"runtime",
			string.format("The Parent property of %s is locked, current parent: NULL, new parent %s", d.props.Name, if nd then nd.props.Name else "NULL")
		)
	end
	if d.isService then
		Engine.throw("runtime", "The Parent property of " .. d.props.Name .. " is locked")
	end
	if nd then
		if nd == d or isDescendantOf(nd, d) then
			Engine.throw("runtime", string.format("Attempt to set parent of %s to %s would result in circular reference", Engine.fullName(d), Engine.fullName(nd)))
		end
	end
	local rid = if R then R.id else 0
	if rid > 0 and d.owner == 0 then
		-- a client re-parenting a replicated instance only changes its own view
		if nd == nil then
			d.hidden = d.hidden or {}
			if not d.hidden[rid] then
				d.hidden[rid] = true
				fireEvent(d, "AncestryChanged", R, d.proxy, nil)
				if oldParent then
					fireEvent(DATA[oldParent], "ChildRemoved", R, d.proxy)
				end
			end
			return
		end
		if nd.owner == 0 then
			Engine.record("note", string.format("client re-parented replicated instance %s to %s (in Roblox this would not replicate)", Engine.fullName(d), Engine.fullName(nd)))
		end
	end
	local od = oldParent and DATA[oldParent]
	local filter = eventFilter(d)
	if od then
		-- DescendantRemoving on old ancestors (before removal, like the engine)
		local anc = od
		local guard = 0
		while anc and guard < 100 do
			if anc.sigs and anc.sigs.DescendantRemoving then
				forSubtree(d, function(x)
					fireEvent(anc, "DescendantRemoving", eventFilter(x), x.proxy)
				end)
			end
			anc = anc.parent and DATA[anc.parent]
			guard += 1
		end
		local list = od.children
		local i = table.find(list, d.proxy)
		if i then
			table.remove(list, i)
		end
	end
	local wasInGame = od ~= nil and inGame(od)
	d.parent = newParent
	if nd and nd.serverOnly and not d.serverOnly then
		forSubtree(d, function(x)
			x.serverOnly = true
		end)
	end
	if nd then
		table.insert(nd.children, d.proxy)
	end
	local nowInGame = nd ~= nil and inGame(nd)
	-- events
	if od then
		fireEvent(od, "ChildRemoved", filter, d.proxy)
	end
	forSubtree(d, function(x)
		if x.sigs and x.sigs.AncestryChanged then
			fireEvent(x, "AncestryChanged", eventFilter(x), d.proxy, newParent)
		end
	end)
	fireChanged(d, "Parent", filter)
	if nd then
		fireEvent(nd, "ChildAdded", filter, d.proxy)
		resolveWaiters(nd, d)
		local anc = nd
		local guard = 0
		while anc and guard < 100 do
			if anc.sigs and anc.sigs.DescendantAdded then
				forSubtree(d, function(x)
					fireEvent(anc, "DescendantAdded", eventFilter(x), x.proxy)
				end)
			end
			anc = anc.parent and DATA[anc.parent]
			guard += 1
		end
	end
	for _, hook in Engine.onParentChanged do
		hook(d, od, nd, wasInGame, nowInGame)
	end
end

----------------------------------------------------------------------
-- Destroy / Clone
----------------------------------------------------------------------
function Engine.destroy(d, R)
	R = R or Sched.CUR
	local rid = if R then R.id else 0
	if d.isService then
		Engine.throw("runtime", "Cannot Destroy() " .. d.props.Name)
	end
	if rid > 0 and d.owner == 0 then
		-- local-only removal of a replicated instance
		forSubtree(d, function(x)
			fireEvent(x, "Destroying", R)
		end)
		Engine.setParent(d, nil, R)
		return
	end
	if d.destroyed then
		return
	end
	forSubtree(d, function(x)
		fireEvent(x, "Destroying", eventFilter(x))
	end)
	if d.parent ~= nil then
		Engine.setParent(d, nil, R)
	end
	local all = {}
	forSubtree(d, function(x)
		table.insert(all, x)
	end)
	for _, x in all do
		x.destroyed = true
		if x.onDestroy then
			x.onDestroy(x)
		end
	end
	-- children are detached (parent stays the destroyed instance in Roblox; descendants are destroyed too)
	-- disconnect after pending deferred events of this destroy were delivered
	Sched.deferCall(nil, function()
		for _, x in all do
			if x.sigs then
				for _, s in x.sigs do
					Engine.disconnectAll(s)
				end
			end
		end
	end)
end

function Engine.clone(d, R)
	R = R or Sched.CUR
	local owner = if R and R.id > 0 then R.id else 0
	if d.props.Archivable == false then
		return nil
	end
	local map = {}
	local function cloneRec(src)
		if src.props.Archivable == false then
			return nil
		end
		local u, nd = makeInstance(src.class, owner)
		for k, v in src.props do
			nd.props[k] = v
		end
		-- overlay values the cloning client sees become the clone's own values
		if src.overlay and R and src.overlay[R.id] then
			for k, v in src.overlay[R.id] do
				nd.props[k] = if v == NIL then nil else v
			end
		end
		for k, v in src.attrs do
			nd.attrs[k] = v
		end
		if src.tags then
			nd.tags = table.clone(src.tags)
		end
		for _, f in { "source", "srcFile", "bytecode" } do
			nd[f] = src[f]
		end
		if src.cloneHook then
			src.cloneHook(src, nd)
		end
		map[src.proxy] = u
		for _, c in src.children do
			local cd = DATA[c]
			if visibleTo(cd, R) then
				local cc = cloneRec(cd)
				if cc then
					local ccd = DATA[cc]
					ccd.parent = u
					table.insert(nd.children, cc)
				end
			end
		end
		return u
	end
	local root = cloneRec(d)
	-- remap references inside the cloned subtree
	forSubtree(DATA[root], function(x)
		for k, v in x.props do
			if DATA[v] and map[v] then
				x.props[k] = map[v]
			end
		end
		if x.afterClone then
			x.afterClone(x, map)
		end
	end)
	return root
end

----------------------------------------------------------------------
-- Attributes
----------------------------------------------------------------------
local ATTR_TYPES = {
	boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, Font = true, EnumItem = true,
}

function Engine.setAttribute(d, name, value, R)
	R = R or Sched.CUR
	if type(name) ~= "string" then
		Engine.throw("runtime", "Argument 1 missing or nil (attribute name must be a string)")
	end
	if #name > 100 or not string.match(name, "^[%w_]+$") or string.sub(name, 1, 3) == "RBX" then
		Engine.throw("runtime", "Attribute name '" .. name .. "' is invalid (alphanumeric/underscore, <=100 chars, no RBX prefix)")
	end
	if value ~= nil and not ATTR_TYPES[typeof(value)] then
		Engine.throw("proptype", typeof(value) .. " is not a supported attribute type (SetAttribute \"" .. name .. "\" on " .. Engine.fullName(d) .. ")")
	end
	if value ~= nil and isNanValue(value) then
		Engine.record("nan", string.format("NaN/inf attribute %s on %s", name, d.class))
	end
	local rid = if R then R.id else 0
	local old
	if rid > 0 and d.owner == 0 then
		d.overlay = d.overlay or {}
		local o = d.overlay[rid]
		if not o then
			o = {}
			d.overlay[rid] = o
		end
		local ak = "@" .. name
		local ov = o[ak]
		if ov ~= nil then
			old = if ov == NIL then nil else ov
		else
			old = d.attrs[name]
		end
		o[ak] = if value == nil then NIL else value
		if old ~= value then
			fireEvent(d, "AttributeChanged", R, name)
			fireEvent(d, "attr:" .. name, R)
		end
		return
	end
	old = d.attrs[name]
	d.attrs[name] = value
	if rid <= 0 and d.overlay then
		for _, o in d.overlay do
			o["@" .. name] = nil
		end
	end
	if old ~= value then
		local f = eventFilter(d)
		fireEvent(d, "AttributeChanged", f, name)
		fireEvent(d, "attr:" .. name, f)
	end
end

function Engine.getAttribute(d, name, R)
	R = R or Sched.CUR
	local ov = d.overlay
	if ov and R then
		local o = ov[R.id]
		if o then
			local v = o["@" .. name]
			if v ~= nil then
				if v == NIL then
					return nil
				end
				return v
			end
		end
	end
	return d.attrs[name]
end

function Engine.getAttributes(d, R)
	R = R or Sched.CUR
	local out = table.clone(d.attrs)
	local ov = d.overlay
	if ov and R and ov[R.id] then
		for k, v in ov[R.id] do
			if string.sub(k, 1, 1) == "@" then
				out[string.sub(k, 2)] = if v == NIL then nil else v
			end
		end
	end
	return out
end

----------------------------------------------------------------------
-- Member access
----------------------------------------------------------------------
local deprecatedSeen = {}
local function noteDeprecated(d, key, m)
	local k = d.class .. "." .. key
	if deprecatedSeen[k] then
		return
	end
	deprecatedSeen[k] = true
	local use = if type(m.Deprecated) == "string" then " (use " .. m.Deprecated .. ")" else ""
	Engine.record("deprecated", string.format("%s.%s is deprecated%s", d.class, key, use))
end

local notEmulatedFns = {}
local function notEmulatedMethod(d, key)
	local k = d.class .. ":" .. key
	local f = notEmulatedFns[k]
	if not f then
		f = function()
			Engine.notEmulated(k .. "()")
		end
		notEmulatedFns[k] = f
	end
	return f
end

local function throwMember(d, key, mode)
	local msg = string.format("%s is not a valid member of %s \"%s\"", tostring(key), d.class, Engine.fullName(d))
	if mode == "write" then
		Engine.throw("member", msg)
	else
		Engine.throw("member", msg, "member_probe")
	end
end

local function zeroFor(t)
	t = string.gsub(t, "%?$", "")
	if t == "number" then
		return 0
	elseif t == "string" then
		return ""
	elseif t == "boolean" then
		return false
	elseif t == "Vector3" then
		return Vector3.zero
	elseif t == "Vector2" then
		return roblox.Vector2.zero
	elseif t == "CFrame" then
		return CFrame.identity
	elseif t == "Color3" then
		return Color3.new(0, 0, 0)
	elseif t == "UDim2" then
		return roblox.UDim2.new()
	elseif t == "UDim" then
		return roblox.UDim.new()
	end
	return nil
end

instIndex = function(u, key)
	local d = DATA[u]
	local R = Sched.CUR
	local ov = d.overlay
	if ov and R then
		local o = ov[R.id]
		if o then
			local v = o[key]
			if v ~= nil then
				if v == NIL then
					return nil
				end
				return v
			end
		end
	end
	local v = d.props[key]
	if v ~= nil then
		return v
	end
	local cls = d.cls
	local m = cls.members[key]
	if m then
		local kind = m.Kind
		if m.Deprecated then
			noteDeprecated(d, key, m)
		end
		if kind == "prop" then
			local g = cls.getters[key]
			if g then
				return g(d, R)
			end
			local dv = cls.defaults[key]
			if dv ~= nil then
				return dv
			end
			if key == "Parent" then
				return nil
			end
			return zeroFor(m.Type)
		elseif kind == "method" then
			local f = cls.impl[key]
			if f then
				return f
			end
			return notEmulatedMethod(d, key)
		else
			local g = cls.getters[key]
			if g then
				return g(d, R)
			end
			return getSignal(d, key)
		end
	end
	if type(key) == "string" then
		local c = findChild(d, key, R)
		if c then
			return c
		end
	end
	throwMember(d, key, "read")
end

instNewindex = function(u, key, value)
	local d = DATA[u]
	local cls = d.cls
	local m = cls.members[key]
	if not m then
		throwMember(d, key, "write")
	end
	if m.Kind ~= "prop" then
		Engine.throw("member", string.format("%s is not a valid member of %s \"%s\" (cannot assign to a %s)", key, d.class, Engine.fullName(d), m.Kind))
	end
	if m.Deprecated then
		noteDeprecated(d, key, m)
	end
	local setter = cls.setters[key]
	if (m.ReadOnly and type(setter) ~= "function") or setter == "readonly" then
		Engine.throw("proptype", string.format("Unable to assign property %s. Property is read only (%s %q)", key, d.class, Engine.fullName(d)))
	end
	if key ~= "Parent" then
		value = validate(d, key, m, value)
	end
	if setter then
		setter(d, value, Sched.CUR)
		return
	end
	setProp(d, key, value, Sched.CUR)
end

-- Method self-check: called as inst:Method(), not inst.Method()
function Engine.self(u, method)
	local d = DATA[u]
	if not d then
		Engine.throw("runtime", "Expected ':' not '.' calling member function " .. method)
	end
	return d
end

-- Instance from proxy argument (or error)
function Engine.argInstance(v, argn, fn)
	local d = DATA[v]
	if not d then
		Engine.throw("runtime", string.format("invalid argument #%d to '%s' (Instance expected, got %s)", argn, fn, typeof(v)))
	end
	return d
end

return Engine
