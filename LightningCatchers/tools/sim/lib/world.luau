--!nocheck
-- World state: the DataModel tree, realms (server + one per client), the network transport for remotes
-- (asynchronous, ~50 ms latency, Roblox serialization rules), players and R15 characters, and a raycast
-- spatial index over the static map.
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local Classes = require("./classes")
local Sched = require("./sched")
local Report = require("./report")
local DT = require("./datatypes")

local Vector3, Vector2, CFrame, Color3, Enum = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Color3, roblox.Enum
local DATA = Engine.DATA
local readProp = Engine.readProp
local setProp = Engine.setProp
local typeof = Engine.typeof

local World = {}
World.latency = 0.05
World.realms = Sched.realms
World.players = {} -- join order: player data
World.playerRealm = {} -- player data -> client realm
World.friends = {} -- [userA][userB] = true
World.stats = { remote = {}, remoteBytes = {} }
World.spy = {} -- optional hooks: spy.onClientEvent(realm, remoteName, args), spy.onServerEvent(realm, remoteName, args)

----------------------------------------------------------------------
-- Realms
----------------------------------------------------------------------
function World.newRealm(id, kind, name)
	local r = {
		id = id,
		kind = kind,
		name = name,
		dead = false,
		modules = {},
		loading = {},
		renderBindings = {},
		casBindings = {},
		coreGui = {},
		keysDown = {},
		viewport = Vector2.new(1366, 768),
		touch = false,
		preferredInput = Enum.PreferredInput.KeyboardAndMouse,
		lastInput = Enum.UserInputType.MouseButton1,
		mouse = Vector2.new(683, 384),
		G = {},
		shared = {},
	}
	Sched.realms[id] = r
	return r
end

World.server = World.newRealm(0, "server", "server")
World.harness = World.newRealm(-1, "harness", "harness")

Classes.viewportFor = function(realm)
	if realm and realm.viewport then
		return realm.viewport
	end
	return Vector2.new(1366, 768)
end

----------------------------------------------------------------------
-- Instance creation helpers
----------------------------------------------------------------------
function World.new(className, props, parent, owner)
	local u, d = Engine.makeInstance(className, owner or 0)
	if props then
		for k, v in props do
			d.props[k] = v
		end
	end
	if parent then
		local pd = DATA[parent]
		d.parent = parent
		table.insert(pd.children, u)
	end
	return u, d
end

----------------------------------------------------------------------
-- Serialization across the network (RemoteEvent/RemoteFunction)
----------------------------------------------------------------------
local function issue(cat, msg)
	Engine.record(cat, msg)
end

-- Deep copy following Roblox remote argument rules; reports problems
local function replicate(v, receiver, path, seen, ctx)
	local tv = typeof(v)
	if tv == "table" then
		if seen[v] then
			issue("remote", string.format("%s: cyclic table sent through %s (Roblox errors: tables cannot be cyclic)", path, ctx))
			return nil
		end
		seen[v] = true
		if getmetatable(v) ~= nil then
			issue("remote", string.format("%s: table with a metatable sent through %s (metatable is lost)", path, ctx))
		end
		local n = #v
		local count, strKeys, numKeys, otherKeys = 0, 0, 0, 0
		for k in pairs(v) do
			count += 1
			local tk = type(k)
			if tk == "string" then
				strKeys += 1
			elseif tk == "number" then
				numKeys += 1
			else
				otherKeys += 1
			end
		end
		local out = {}
		if strKeys == 0 and otherKeys == 0 and numKeys == n then
			for i = 1, n do
				out[i] = replicate(v[i], receiver, path .. "[" .. i .. "]", seen, ctx)
			end
		elseif numKeys > 0 and (strKeys > 0 or otherKeys > 0) then
			issue("remote", string.format("%s: mixed table (number and string keys) sent through %s — Roblox drops part of it", path, ctx))
			for k, x in pairs(v) do
				if type(k) == "number" and k >= 1 and k <= n and k == math.floor(k) then
					out[k] = replicate(x, receiver, path .. "[" .. k .. "]", seen, ctx)
				end
			end
		elseif numKeys > 0 then
			issue("remote", string.format("%s: sparse/non-sequential numeric keys sent through %s — keys after a gap are lost or become strings", path, ctx))
			for k, x in pairs(v) do
				out[tostring(k)] = replicate(x, receiver, path .. "[" .. tostring(k) .. "]", seen, ctx)
			end
		else
			for k, x in pairs(v) do
				local key = k
				if type(k) ~= "string" then
					key = tostring(k)
				end
				out[key] = replicate(x, receiver, path .. "." .. tostring(key), seen, ctx)
			end
		end
		seen[v] = nil
		return out
	elseif tv == "function" or tv == "thread" then
		issue("remote", string.format("%s: %s value sent through %s (it arrives as nil)", path, tv, ctx))
		return nil
	elseif tv == "Instance" then
		local d = DATA[v]
		if receiver and not Engine.visibleTo(d, receiver) then
			if d.serverOnly then
				issue("remote", string.format("%s: Instance %s lives in a server-only container and arrives as nil on the client (%s)", path, Engine.fullName(d), ctx))
			end
			return nil
		end
		if d.destroyed or not Engine.inGame(d) then
			-- instances outside the DataModel do not replicate
			if d.owner == 0 and not Engine.inGame(d) then
				issue("remote", string.format("%s: Instance %s (not in the DataModel) sent through %s — arrives as nil", path, d.props.Name, ctx))
				return nil
			end
		end
		return v
	elseif tv == "RBXScriptSignal" or tv == "RBXScriptConnection" then
		issue("remote", string.format("%s: %s sent through %s", path, tv, ctx))
		return nil
	end
	return v
end
World.replicate = replicate

local function estimateSize(v, depth)
	depth = depth or 0
	local tv = type(v)
	if tv == "string" then
		return #v + 2
	elseif tv == "number" then
		return 9
	elseif tv == "boolean" then
		return 1
	elseif tv == "table" and depth < 20 then
		local s = 2
		for k, x in pairs(v) do
			s += estimateSize(k, depth + 1) + estimateSize(x, depth + 1)
		end
		return s
	elseif tv == "userdata" then
		return 16
	end
	return 1
end
World.estimateSize = estimateSize

local function packArgs(receiver, ctx, ...)
	local n = select("#", ...)
	local out = { n = n }
	for i = 1, n do
		out[i] = replicate((select(i, ...)), receiver, "arg" .. i, {}, ctx)
	end
	return out
end
World.packArgs = packArgs

local function countRemote(name, args)
	local st = World.stats.remote
	st[name] = (st[name] or 0) + 1
	local b = World.stats.remoteBytes
	b[name] = (b[name] or 0) + estimateSize(args)
end

----------------------------------------------------------------------
-- Remote event queues: events that arrive before anyone listens are queued (like Roblox)
----------------------------------------------------------------------
local function realmHasListener(sig, realm)
	for _, c in sig.conns do
		if c.connected and c.realm == realm then
			return true
		end
	end
	return #sig.waiters > 0
end

local function deliver(rd, sigName, realm, args, prefix)
	local sig = Engine.getSignal(rd, sigName)
	if realm.dead then
		return
	end
	if not realmHasListener(sig, realm) then
		rd.pending = rd.pending or {}
		local key = sigName .. "#" .. realm.id
		local q = rd.pending[key]
		if not q then
			q = {}
			rd.pending[key] = q
		end
		table.insert(q, { args = args, prefix = prefix })
		if #q == 257 then
			Report.add("remote", realm.name, string.format("Remote event queue exhausted for %s.%s (nobody connected; Roblox drops events)", Engine.fullName(rd), sigName), {})
		end
		return
	end
	if prefix ~= nil then
		Engine.fire(sig, realm, prefix, table.unpack(args, 1, args.n))
	else
		Engine.fire(sig, realm, table.unpack(args, 1, args.n))
	end
end

local function flushPending(rd, sigName, realm)
	local key = sigName .. "#" .. realm.id
	local q = rd.pending and rd.pending[key]
	if not q then
		return
	end
	rd.pending[key] = nil
	local sig = Engine.getSignal(rd, sigName)
	for _, e in q do
		if e.prefix ~= nil then
			Engine.fire(sig, realm, e.prefix, table.unpack(e.args, 1, e.args.n))
		else
			Engine.fire(sig, realm, table.unpack(e.args, 1, e.args.n))
		end
	end
end

function World.realmOfPlayer(player)
	local pd = DATA[player]
	return pd and World.playerRealm[pd]
end

local function requireKind(kind, what)
	local cur = Sched.CUR
	if not cur or (cur.kind ~= kind and cur.kind ~= "harness") then
		Engine.throw("runtime", what)
	end
end

local function remoteSignalGetter(sigName, side)
	return function(d, realm)
		local sig = Engine.getSignal(d, sigName)
		if not rawget(sig, "opts") then
			rawset(sig, "opts", {
				onConnect = function(r)
					if r and r.kind ~= side and r.kind ~= "harness" then
						Engine.throw("runtime", string.format("%s can only be used on the %s", sigName, side))
					end
					-- deliver queued events once the first listener of this realm connects
					if r then
						Sched.deferCall(r, function()
							flushPending(d, sigName, r)
						end)
					end
				end,
			})
		end
		return sig
	end
end

local function remoteFire(remoteKind)
	local function checkUnreliable(d, args)
		if remoteKind == "UnreliableRemoteEvent" then
			local size = estimateSize(args)
			if size > 900 then
				Engine.record("remote", string.format("UnreliableRemoteEvent %s payload ~%d bytes > 900 (Roblox drops it)", d.props.Name, size))
			end
		end
	end
	return {
		FireServer = function(u, ...)
			local d = Engine.self(u, "FireServer")
			requireKind("client", "FireServer can only be called from the client")
			local from = Sched.CUR
			local player = from.player
			local args = packArgs(World.server, "RemoteEvent " .. d.props.Name, ...)
			checkUnreliable(d, args)
			countRemote(d.props.Name, args)
			if World.spy.onServerEvent then
				World.spy.onServerEvent(from, d.props.Name, args)
			end
			Sched.at(Sched.now + World.latency, function()
				if from.dead then
					return
				end
				deliver(d, "OnServerEvent", World.server, args, player)
			end)
		end,
		FireClient = function(u, player, ...)
			local d = Engine.self(u, "FireClient")
			requireKind("server", "FireClient can only be called from the server")
			local pd = DATA[player]
			if not pd or pd.class ~= "Player" then
				Engine.throw("runtime", "FireClient: player argument must be a Player object (got " .. typeof(player) .. ")")
			end
			local realm = World.playerRealm[pd]
			local args = packArgs(realm, "RemoteEvent " .. d.props.Name, ...)
			checkUnreliable(d, args)
			countRemote(d.props.Name, args)
			if not realm then
				return
			end
			Sched.at(Sched.now + World.latency, function()
				if realm.dead then
					return
				end
				if World.spy.onClientEvent then
					World.spy.onClientEvent(realm, d.props.Name, args)
				end
				deliver(d, "OnClientEvent", realm, args, nil)
			end)
		end,
		FireAllClients = function(u, ...)
			local d = Engine.self(u, "FireAllClients")
			requireKind("server", "FireAllClients can only be called from the server")
			local packed = table.pack(...)
			for _, pd in World.players do
				local realm = World.playerRealm[pd]
				if realm and not realm.dead then
					local args = packArgs(realm, "RemoteEvent " .. d.props.Name, table.unpack(packed, 1, packed.n))
					countRemote(d.props.Name, args)
					Sched.at(Sched.now + World.latency, function()
						if realm.dead then
							return
						end
						if World.spy.onClientEvent then
							World.spy.onClientEvent(realm, d.props.Name, args)
						end
						deliver(d, "OnClientEvent", realm, args, nil)
					end)
				end
			end
		end,
	}
end

for _, cls in { "RemoteEvent", "UnreliableRemoteEvent" } do
	Engine.define(cls, {
		getters = {
			OnServerEvent = remoteSignalGetter("OnServerEvent", "server"),
			OnClientEvent = remoteSignalGetter("OnClientEvent", "client"),
		},
		methods = remoteFire(cls),
	})
end

-- RemoteFunction
local function invokeCallback(d, key, realm, args, prefix, onDone)
	local function run()
		local cb = d.callbacks and d.callbacks[key]
		if not cb then
			-- wait until a callback is set (Roblox queues the invocation)
			d.invokeQueue = d.invokeQueue or {}
			table.insert(d.invokeQueue, { key = key, realm = realm, args = args, prefix = prefix, onDone = onDone })
			return
		end
		local co = Sched.create(realm, function()
			local res
			local ok, err = xpcall(function()
				if prefix ~= nil then
					res = table.pack(cb(prefix, table.unpack(args, 1, args.n)))
				else
					res = table.pack(cb(table.unpack(args, 1, args.n)))
				end
			end, function(e)
				if e ~= Sched.lastThrown then
					Report.add("runtime", realm.name, Report.cleanMessage(e), Report.frames(nil, 1), "inside " .. key .. " of " .. Engine.fullName(d))
				end
				Sched.lastThrown = nil
				return e
			end)
			if ok then
				onDone(true, res)
			else
				onDone(false, err)
			end
		end)
		Sched.resume(co)
	end
	run()
end

Engine.define("RemoteFunction", {
	getters = {
		OnServerInvoke = function()
			Engine.throw("runtime", "OnServerInvoke is a callback member of RemoteFunction; you can only set the callback value, get is not available")
		end,
		OnClientInvoke = function()
			Engine.throw("runtime", "OnClientInvoke is a callback member of RemoteFunction; you can only set the callback value, get is not available")
		end,
	},
	setters = {
		OnServerInvoke = function(d, v, realm)
			if realm and realm.kind == "client" then
				Engine.throw("runtime", "OnServerInvoke can only be set on the server")
			end
			if v ~= nil and type(v) ~= "function" then
				Engine.throw("proptype", "OnServerInvoke must be a function")
			end
			d.callbacks = d.callbacks or {}
			d.callbacks.OnServerInvoke = v
			d.callbackRealm = realm
			if v and d.invokeQueue then
				local q = d.invokeQueue
				d.invokeQueue = nil
				for _, e in q do
					invokeCallback(d, e.key, e.realm, e.args, e.prefix, e.onDone)
				end
			end
		end,
		OnClientInvoke = function(d, v, realm)
			if realm and realm.kind == "server" then
				Engine.throw("runtime", "OnClientInvoke can only be set on the client")
			end
			d.clientCallbacks = d.clientCallbacks or {}
			d.clientCallbacks[realm.id] = v
		end,
	},
	methods = {
		InvokeServer = function(u, ...)
			local d = Engine.self(u, "InvokeServer")
			requireKind("client", "InvokeServer can only be called from the client")
			local from = Sched.CUR
			local args = packArgs(World.server, "RemoteFunction " .. d.props.Name, ...)
			countRemote(d.props.Name, args)
			local co = coroutine.running()
			local token = Sched.waitToken(co)
			local started = Sched.now
			local frames = Report.frames(nil, 1)
			local done = false
			Sched.at(Sched.now + World.latency, function()
				if from.dead then
					return
				end
				invokeCallback(d, "OnServerInvoke", World.server, args, from.player, function(ok, res)
					local back = if ok then packArgs(from, "RemoteFunction return " .. d.props.Name, table.unpack(res, 1, res.n)) else res
					Sched.at(Sched.now + World.latency, function()
						done = true
						if from.dead then
							return
						end
						Sched.wakeAt(Sched.now, co, token, ok, back)
					end)
				end)
			end)
			Sched.at(Sched.now + 5, function()
				if not done and not from.dead then
					Report.add("yield", from.name, string.format("RemoteFunction %s:InvokeServer has not returned after 5 s (no OnServerInvoke or the handler yields)", d.props.Name), frames)
				end
			end)
			local ok, res = Sched.suspend("InvokeServer " .. d.props.Name)
			Report.logLine(string.format("[%s %s] InvokeServer %s(%s) -> %s %s", Report.fmtTime(Sched.now), from.name, d.props.Name,
				table.concat((function()
					local t = {}
					for i = 1, args.n do
						t[i] = tostring(args[i])
					end
					return t
				end)(), ", "), tostring(ok), if ok and res then tostring(res[1]) .. " " .. tostring(res[2]) else tostring(res)))
			if World.spy.onInvokeDone then
				World.spy.onInvokeDone(from, d.props.Name, args, ok, res, Sched.now - started)
			end
			if not ok then
				error(Report.cleanMessage(res), 0)
			end
			return table.unpack(res, 1, res.n)
		end,
		InvokeClient = function(u, player, ...)
			local d = Engine.self(u, "InvokeClient")
			requireKind("server", "InvokeClient can only be called from the server")
			Engine.notEmulated("RemoteFunction:InvokeClient")
		end,
	},
})

-- Bindables (same realm, deferred, args copied)
Engine.define("BindableEvent", {
	methods = {
		Fire = function(u, ...)
			local d = Engine.self(u, "Fire")
			local args = packArgs(nil, "BindableEvent " .. d.props.Name, ...)
			Engine.fire(Engine.getSignal(d, "Event"), Sched.CUR, table.unpack(args, 1, args.n))
		end,
	},
})
Engine.define("BindableFunction", {
	getters = {
		OnInvoke = function()
			Engine.throw("runtime", "OnInvoke is a callback member of BindableFunction; you can only set the callback value, get is not available")
		end,
	},
	setters = {
		OnInvoke = function(d, v)
			d.onInvoke = v
		end,
	},
	methods = {
		Invoke = function(u, ...)
			local d = Engine.self(u, "Invoke")
			while not d.onInvoke do
				Sched.wait(0.03, "BindableFunction:Invoke (no OnInvoke)")
			end
			local args = packArgs(nil, "BindableFunction " .. d.props.Name, ...)
			return d.onInvoke(table.unpack(args, 1, args.n))
		end,
	},
})

----------------------------------------------------------------------
-- Raycast spatial index (static map parts)
----------------------------------------------------------------------
local CELL = 32
local grid = {} -- key "ix,iz" -> { [d] = true }
local gridParts = {}
World.grid = grid

local function cellKey(ix, iz)
	return ix * 100003 + iz
end

local function partAABB(d)
	local cf = d.props.CFrame or CFrame.identity
	local s = (d.props.Size or Vector3.one) / 2
	local r = cf.RightVector
	local u = cf.UpVector
	local l = cf.LookVector
	local ex = math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z
	local ey = math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z
	local ez = math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	local p = cf.Position
	return p.X - ex, p.Y - ey, p.Z - ez, p.X + ex, p.Y + ey, p.Z + ez
end

local function gridInsert(d)
	local x0, _, z0, x1, _, z1 = partAABB(d)
	local cells = {}
	for ix = math.floor(x0 / CELL), math.floor(x1 / CELL) do
		for iz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
			local k = cellKey(ix, iz)
			local c = grid[k]
			if not c then
				c = {}
				grid[k] = c
			end
			c[d] = true
			table.insert(cells, k)
		end
	end
	d.gridCells = cells
	d.inGrid = true
	gridParts[d] = true
end

local function gridRemove(d)
	for _, k in d.gridCells or {} do
		local c = grid[k]
		if c then
			c[d] = nil
		end
	end
	d.gridCells = nil
	d.inGrid = false
	gridParts[d] = nil
end

Classes.onPartMoved = function(d)
	gridRemove(d)
	gridInsert(d)
end

function World.indexStatic(rootD)
	Engine.forSubtree(rootD, function(x)
		if x.cls.isA.BasePart then
			gridInsert(x)
		end
	end)
end

-- Ray vs oriented box (with optional wedge plane); returns t, normal
local function rayPart(d, origin, dir, maxT, realm)
	local cf = readProp(d, "CFrame", realm) or CFrame.identity
	local size = readProp(d, "Size", realm) or Vector3.one
	local o = cf:PointToObjectSpace(origin)
	local v = cf:VectorToObjectSpace(dir)
	local h = size / 2
	local cls = d.class
	local shape = d.props.Shape
	if cls == "Part" and shape == Enum.PartType.Ball then
		local r = math.min(h.X, h.Y, h.Z)
		local a = v:Dot(v)
		local b = 2 * o:Dot(v)
		local c = o:Dot(o) - r * r
		local disc = b * b - 4 * a * c
		if disc < 0 or a == 0 then
			return nil
		end
		local t = (-b - math.sqrt(disc)) / (2 * a)
		if t < 0 then
			t = (-b + math.sqrt(disc)) / (2 * a)
		end
		if t < 0 or t > maxT then
			return nil
		end
		local p = o + v * t
		return t, cf:VectorToWorldSpace(p.Unit)
	end
	local tmin, tmax = -math.huge, math.huge
	local nmin = nil
	local axes = { { o.X, v.X, h.X, Vector3.xAxis }, { o.Y, v.Y, h.Y, Vector3.yAxis }, { o.Z, v.Z, h.Z, Vector3.zAxis } }
	for _, ax in axes do
		local oo, vv, hh, n = ax[1], ax[2], ax[3], ax[4]
		if math.abs(vv) < 1e-12 then
			if oo < -hh or oo > hh then
				return nil
			end
		else
			local t1 = (-hh - oo) / vv
			local t2 = (hh - oo) / vv
			local n1 = -n
			if t1 > t2 then
				t1, t2 = t2, t1
				n1 = n
			end
			if t1 > tmin then
				tmin = t1
				nmin = n1
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	if cls == "WedgePart" then
		-- wedge: solid where y/hy <= z/hz (slope rises toward +Z); clip by the slope plane
		local pn = Vector3.new(0, 1 / h.Y, -1 / h.Z)
		local denom = pn:Dot(v)
		local num = -pn:Dot(o)
		if math.abs(denom) < 1e-12 then
			if num < 0 then
				return nil
			end
		else
			local t = num / denom
			if denom < 0 then
				-- entering
				if t > tmin then
					tmin = t
					nmin = pn.Unit
				end
			else
				if t < tmax then
					tmax = t
				end
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	local t = tmin
	if t < 0 then
		return nil -- origin inside: Roblox ignores the part the ray starts in
	end
	if t > maxT or not nmin then
		return nil
	end
	return t, cf:VectorToWorldSpace(nmin)
end

local function passesFilter(d, params, realm, filterSet, include)
	if readProp(d, "CanQuery", realm) == false then
		return false
	end
	if not Engine.visibleTo(d, realm) or d.destroyed then
		return false
	end
	if params and params.RespectCanCollide and readProp(d, "CanCollide", realm) == false then
		return false
	end
	if filterSet then
		local cur = d
		local hit = false
		local guard = 0
		while cur and guard < 60 do
			if filterSet[cur] then
				hit = true
				break
			end
			cur = cur.parent and DATA[cur.parent]
			guard += 1
		end
		if include then
			return hit
		end
		return not hit
	end
	return true
end

function World.raycast(origin, dir, params, realm)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		Engine.throw("runtime", "Unable to cast to Vector3 (Raycast origin/direction)")
	end
	if params ~= nil and typeof(params) ~= "RaycastParams" then
		Engine.throw("runtime", "Unable to cast value to RaycastParams")
	end
	local len = dir.Magnitude
	if len < 1e-9 then
		return nil
	end
	if len > 15000 then
		Engine.record("runtime", "Raycast direction longer than 15000 studs (Roblox clamps)")
	end
	local unit = dir / len
	local filterSet = nil
	local include = false
	if params then
		local list = params.FilterDescendantsInstances
		if #list > 0 or params.FilterType == Enum.RaycastFilterType.Include then
			filterSet = {}
			for _, inst in list do
				local fd = DATA[inst]
				if fd then
					filterSet[fd] = true
				end
			end
			include = params.FilterType == Enum.RaycastFilterType.Include
		end
	end
	-- candidates: grid cells along the ray (sampled), plus non-static parts
	local cands = {}
	local steps = math.max(1, math.ceil(len / (CELL / 2)))
	local seenCells = {}
	for i = 0, steps do
		local p = origin + unit * (len * i / steps)
		local k = cellKey(math.floor(p.X / CELL), math.floor(p.Z / CELL))
		if not seenCells[k] then
			seenCells[k] = true
			local c = grid[k]
			if c then
				for pd in c do
					cands[pd] = true
				end
			end
		end
	end
	for _, pd in World.dynamicParts(realm) do
		cands[pd] = true
	end
	local bestT, bestD, bestN = math.huge, nil, nil
	for pd in cands do
		if passesFilter(pd, params, realm, filterSet, include) then
			local t, n = rayPart(pd, origin, unit, len, realm)
			if t and t < bestT then
				bestT, bestD, bestN = t, pd, n
			end
		end
	end
	if not bestD then
		return nil
	end
	return DT.raycastResult(bestD.proxy, origin + unit * bestT, bestN, bestT, readProp(bestD, "Material", realm))
end

-- Parts in Workspace that are not in the static grid (characters, effects): scanned linearly
World.dynamicCache = nil
function World.dynamicParts(realm)
	local out = {}
	local ws = World.workspaceD
	if not ws then
		return out
	end
	for _, c in ws.children do
		local cd = DATA[c]
		if cd.props.Name ~= "Map" and Engine.visibleTo(cd, realm) then
			Engine.forSubtree(cd, function(x)
				if x.cls.isA.BasePart and not x.inGrid then
					table.insert(out, x)
				end
			end)
		end
	end
	return out
end

-- Parts whose bounds intersect a sphere/box (approximate, AABB based)
function World.partsInBox(cf, size, params, realm)
	local half = size / 2
	local out = {}
	local p = cf.Position
	local r = half.Magnitude
	local x0, x1, z0, z1 = p.X - r, p.X + r, p.Z - r, p.Z + r
	local cands = {}
	for ix = math.floor(x0 / CELL), math.floor(x1 / CELL) do
		for iz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
			local c = grid[cellKey(ix, iz)]
			if c then
				for pd in c do
					cands[pd] = true
				end
			end
		end
	end
	for _, pd in World.dynamicParts(realm) do
		cands[pd] = true
	end
	local filterSet, include = nil, false
	if params then
		local list = params.FilterDescendantsInstances
		if #list > 0 or params.FilterType == Enum.RaycastFilterType.Include then
			filterSet = {}
			for _, inst in list do
				if DATA[inst] then
					filterSet[DATA[inst]] = true
				end
			end
			include = params.FilterType == Enum.RaycastFilterType.Include
		end
	end
	for pd in cands do
		if passesFilter(pd, params, realm, filterSet, include) then
			local ax0, ay0, az0, ax1, ay1, az1 = partAABB(pd)
			local lp = cf:PointToObjectSpace(Vector3.new((ax0 + ax1) / 2, (ay0 + ay1) / 2, (az0 + az1) / 2))
			local ext = Vector3.new(ax1 - ax0, ay1 - ay0, az1 - az0) / 2
			if math.abs(lp.X) <= half.X + ext.X and math.abs(lp.Y) <= half.Y + ext.Y and math.abs(lp.Z) <= half.Z + ext.Z then
				table.insert(out, pd.proxy)
			end
		end
	end
	return out
end

return World
