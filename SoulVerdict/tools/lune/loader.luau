--!nocheck
-- Lune harness: loads project ModuleScripts outside Roblox.
-- Emulates the Rojo tree (default.project.json) with lightweight "instance proxies":
--   game:GetService("ReplicatedStorage").Shared   -> src/shared
--   game:GetService("ServerScriptService").Server -> src/server
--   game:GetService("StarterPlayer").StarterPlayerScripts.Client -> src/client
-- Inside a loaded module, `script` is a proxy supporting .Parent, .Name, :FindFirstChild, :WaitForChild,
-- :GetChildren, :IsA, :GetFullName and indexing children by name; `require(proxy)` loads the module.
-- Roblox datatypes come from @lune/roblox. A deterministic `Random` shim is provided.
--
-- Usage:
--   local Loader = require("./loader")
--   local Config = Loader.require("ReplicatedStorage.Shared.Config")   -- dotted instance path
--   local RigBuilder = Loader.requirePath("src/shared/Rigs/RigBuilder") -- file path (no extension)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local serde = require("@lune/serde")

local Loader = {}

-- Rojo mapping: instance path prefix -> directory
local MOUNTS = {
	{ "ReplicatedStorage.Shared", "src/shared" },
	{ "ServerScriptService.Server", "src/server" },
	{ "StarterPlayer.StarterPlayerScripts.Client", "src/client" },
}

local cache = {}
local loading = {}
local REF = newproxy and newproxy() or {}
local proxyCache = {}

-- File index (Lune fs calls may yield, which is illegal inside metamethods, so we pre-scan).
local FILES = {}
local DIRS = {}
local DIR_ENTRIES = {}
local function scan(dir)
	DIRS[dir] = true
	local entries = fs.readDir(dir)
	table.sort(entries)
	DIR_ENTRIES[dir] = entries
	for _, e in entries do
		local p = dir .. "/" .. e
		if fs.isDir(p) then
			scan(p)
		else
			FILES[p] = true
		end
	end
end
for _, root in { "src" } do
	if fs.isDir(root) then
		scan(root)
	end
end

function Loader.rescan()
	FILES, DIRS, DIR_ENTRIES = {}, {}, {}
	scan("src")
end

local function isDir(path)
	return DIRS[path] == true
end

local function isFile(path)
	return FILES[path] == true
end

local function resolveFile(dirPath)
	for _, c in { dirPath .. ".luau", dirPath .. ".lua", dirPath .. "/init.luau", dirPath .. "/init.lua",
		dirPath .. ".server.luau", dirPath .. ".client.luau", dirPath .. "/init.server.luau", dirPath .. "/init.client.luau" } do
		if isFile(c) then
			return c
		end
	end
	return nil
end

local function dirToInstancePath(dir)
	for _, m in MOUNTS do
		if dir == m[2] then
			return m[1]
		end
		if string.sub(dir, 1, #m[2] + 1) == m[2] .. "/" then
			return m[1] .. "." .. string.gsub(string.sub(dir, #m[2] + 2), "/", ".")
		end
	end
	return dir
end

local function classOf(path)
	local file = resolveFile(path)
	if file then
		if string.find(file, "%.server%.luau$") then
			return "Script"
		elseif string.find(file, "%.client%.luau$") then
			return "LocalScript"
		end
		return "ModuleScript"
	end
	if isDir(path) then
		return "Folder"
	end
	return nil
end

local makeProxy

local function childNames(path)
	local names = {}
	local seen = {}
	if isDir(path) then
		for _, entry in DIR_ENTRIES[path] or {} do
			local name = entry
			name = string.gsub(name, "%.server%.luau$", "")
			name = string.gsub(name, "%.client%.luau$", "")
			name = string.gsub(name, "%.luau$", "")
			name = string.gsub(name, "%.lua$", "")
			if name ~= "init" and not seen[name] and string.sub(name, 1, 1) ~= "." and not string.find(name, "%.json$") then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	return names
end

local function exists(path)
	return resolveFile(path) ~= nil or isDir(path)
end

-- path: filesystem path without extension (dir or module)
makeProxy = function(path, virtualName, virtualParent)
	local key = path
	if proxyCache[key] then
		return proxyCache[key]
	end
	local proxy = {}
	proxy[REF] = path
	local name = virtualName or string.match(path, "([^/]+)$") or path
	local methods = {}
	function methods:FindFirstChild(childName)
		local p = path .. "/" .. childName
		if exists(p) then
			return makeProxy(p)
		end
		return nil
	end
	function methods:WaitForChild(childName)
		local p = path .. "/" .. childName
		if exists(p) then
			return makeProxy(p)
		end
		error("Loader: WaitForChild would hang — missing " .. p, 2)
	end
	function methods:GetChildren()
		local out = {}
		for _, n in childNames(path) do
			table.insert(out, makeProxy(path .. "/" .. n))
		end
		return out
	end
	function methods:GetDescendants()
		local out = {}
		local function walk(p)
			for _, n in childNames(p) do
				local cp = p .. "/" .. n
				table.insert(out, makeProxy(cp))
				if isDir(cp) then
					walk(cp)
				end
			end
		end
		walk(path)
		return out
	end
	function methods:IsA(className)
		local c = classOf(path)
		if className == "Instance" then
			return true
		end
		if className == "LuaSourceContainer" then
			return c == "ModuleScript" or c == "Script" or c == "LocalScript"
		end
		return c == className
	end
	function methods:GetFullName()
		return dirToInstancePath(path)
	end
	setmetatable(proxy, {
		__index = function(_, k)
			if k == "Parent" then
				if virtualParent then
					return virtualParent
				end
				local parent = string.match(path, "^(.*)/[^/]+$")
				return parent and makeProxy(parent) or nil
			elseif k == "Name" then
				return name
			elseif k == "ClassName" then
				return classOf(path)
			elseif methods[k] then
				return methods[k]
			end
			local p = path .. "/" .. k
			if exists(p) then
				return makeProxy(p)
			end
			error(("Loader: %s is not a valid member of %s"):format(tostring(k), dirToInstancePath(path)), 2)
		end,
		__tostring = function()
			return name
		end,
	})
	proxyCache[key] = proxy
	return proxy
end

-- Deterministic Random shim (Lune has no Random datatype)
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed)
	local self = setmetatable({}, RandomShim)
	self._s = math.floor((seed or os.clock() * 1e6)) % 2147483647
	if self._s <= 0 then
		self._s = self._s + 2147483646
	end
	return self
end
function RandomShim:_next()
	self._s = (self._s * 16807) % 2147483647
	return self._s / 2147483647
end
function RandomShim:NextNumber(a, b)
	local r = self:_next()
	if a == nil then
		return r
	end
	return a + (b - a) * r
end
function RandomShim:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end
function RandomShim:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local t = self:NextNumber(0, math.pi * 2)
	local r = math.sqrt(1 - z * z)
	return roblox.Vector3.new(r * math.cos(t), r * math.sin(t), z)
end
function RandomShim:Clone()
	local c = RandomShim.new(1)
	c._s = self._s
	return c
end

-- Minimal service mocks for modules that touch services at require time.
local function fakeSignal()
	return {
		Connect = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Once = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Wait = function() end,
	}
end

local SERVICE_MOUNTS = {
	ReplicatedStorage = "src/shared/..",
}

local serviceProxies = {}
local function serviceProxy(serviceName)
	if serviceProxies[serviceName] then
		return serviceProxies[serviceName]
	end
	local children = {}
	for _, m in MOUNTS do
		local first, rest = string.match(m[1], "^([^%.]+)%.(.+)$")
		if first == serviceName then
			children[rest] = m[2]
		end
	end
	local svc = { Name = serviceName, ClassName = serviceName }
	local function child(childName)
		for vpath, dir in children do
			local head, tail = string.match(vpath, "^([^%.]+)%.?(.*)$")
			if head == childName then
				if tail == "" then
					return makeProxy(dir, childName, svc)
				end
				-- nested virtual container (e.g. StarterPlayer.StarterPlayerScripts.Client)
				local holder = { Name = childName, ClassName = "Folder" }
				setmetatable(holder, {
					__index = function(_, k)
						if k == "FindFirstChild" or k == "WaitForChild" then
							return function(_, n)
								if n == tail then
									return makeProxy(dir, tail, holder)
								end
								return nil
							end
						end
						if k == tail then
							return makeProxy(dir, tail, holder)
						end
						if k == "Parent" then
							return svc
						end
						return nil
					end,
				})
				return holder
			end
		end
		return nil
	end
	svc.FindFirstChild = function(_, n)
		return child(n)
	end
	svc.WaitForChild = function(_, n)
		local c = child(n)
		if not c then
			error("Loader: service " .. serviceName .. " has no mounted child " .. tostring(n), 2)
		end
		return c
	end
	svc.IsA = function(_, c)
		return c == serviceName or c == "Instance"
	end
	-- common mocks
	if serviceName == "RunService" then
		svc.IsStudio = function()
			return true
		end
		svc.IsServer = function()
			return Loader.isServer
		end
		svc.IsClient = function()
			return not Loader.isServer
		end
		svc.IsRunning = function()
			return false
		end
		for _, e in { "Heartbeat", "Stepped", "RenderStepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" } do
			svc[e] = fakeSignal()
		end
		svc.BindToRenderStep = function() end
		svc.UnbindFromRenderStep = function() end
	elseif serviceName == "Players" then
		svc.LocalPlayer = nil
		svc.GetPlayers = function()
			return {}
		end
		svc.PlayerAdded = fakeSignal()
		svc.PlayerRemoving = fakeSignal()
	elseif serviceName == "HttpService" then
		svc.JSONEncode = function(_, v)
			return serde.encode("json", v)
		end
		svc.JSONDecode = function(_, s)
			return serde.decode("json", s)
		end
		svc.GenerateGUID = function()
			return "00000000-0000-0000-0000-000000000000"
		end
	elseif serviceName == "TweenService" then
		svc.Create = function()
			return { Play = function() end, Cancel = function() end, Completed = fakeSignal() }
		end
	end
	setmetatable(svc, {
		__index = function(_, k)
			local c = child(k)
			if c then
				return c
			end
			error(("Loader: mock service %s has no member %s (not available offline)"):format(serviceName, tostring(k)), 2)
		end,
	})
	serviceProxies[serviceName] = svc
	return svc
end

local gameMock = {
	GetService = function(_, name)
		return serviceProxy(name)
	end,
	FindService = function(_, name)
		return serviceProxy(name)
	end,
}

Loader.isServer = true
Loader.quietWarnings = false

local function makeEnv(modulePath)
	local env = {
		script = makeProxy(modulePath),
		game = gameMock,
		require = function(target)
			if type(target) == "table" and rawget(target, REF) then
				return Loader.requirePath(rawget(target, REF))
			end
			if type(target) == "string" then
				return require(target)
			end
			error("Loader: unsupported require target " .. tostring(target), 2)
		end,
		Instance = roblox.Instance,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		Vector3int16 = roblox.Vector3int16,
		Vector2int16 = roblox.Vector2int16,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		Font = roblox.Font,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		Faces = roblox.Faces,
		Axes = roblox.Axes,
		Random = RandomShim,
		task = task,
		tick = os.clock,
		time = os.clock,
		warn = function(...)
			if Loader.onWarn then
				Loader.onWarn(...) -- tests that assert "no warnings" install a collector here
			end
			if not Loader.quietWarnings then
				print("[warn]", ...)
			end
		end,
		workspace = nil,
		shared = {},
		DateTime = {
			now = function()
				return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 }
			end,
		},
	}
	return setmetatable(env, { __index = _G })
end

function Loader.requirePath(path)
	path = string.gsub(path, "%.luau$", "")
	local file = resolveFile(path)
	assert(file, "Loader: module not found: " .. path)
	if cache[file] ~= nil then
		return cache[file]
	end
	if loading[file] then
		error("Loader: cyclic require: " .. file, 2)
	end
	loading[file] = true
	local source = fs.readFile(file)
	local modulePath = string.gsub(file, "%.luau$", "")
	modulePath = string.gsub(modulePath, "%.server$", "")
	modulePath = string.gsub(modulePath, "%.client$", "")
	modulePath = string.gsub(modulePath, "/init$", "")
	local fn = luau.load(source, { debugName = file, environment = makeEnv(modulePath), injectGlobals = true })
	local result = fn()
	loading[file] = nil
	cache[file] = result
	return result
end

-- dotted instance path, e.g. "ReplicatedStorage.Shared.Rigs.RigBuilder"
function Loader.require(instancePath)
	for _, m in MOUNTS do
		if instancePath == m[1] then
			return Loader.requirePath(m[2])
		end
		if string.sub(instancePath, 1, #m[1] + 1) == m[1] .. "." then
			local rest = string.sub(instancePath, #m[1] + 2)
			return Loader.requirePath(m[2] .. "/" .. string.gsub(rest, "%.", "/"))
		end
	end
	error("Loader: path not under a mount: " .. instancePath)
end

function Loader.reset()
	cache = {}
	loading = {}
end

-- Test hygiene (used by run_tests.luau around EVERY test): Loader.reset() only drops the module cache, while
-- the mock services (game:GetService(...) proxies), the loader flags and the shared script environment
-- (getfenv(Loader.requirePath), where specs park workspace / RaycastParams / typeof fakes) live for the
-- whole run. A test that changes them and does not undo it poisons every later suite (e.g. a plain-table
-- Players.LocalPlayer made ui_screens fail). captureState() snapshots all of it; restoreState(snapshot)
-- puts it back and returns the names of whatever had leaked ({} = the test was clean).
local function rawFields(t)
	local out = {}
	for k, v in next, t do
		out[k] = v
	end
	return out
end

-- `inherited` (optional): the table behind now's __index; a raw field equal to the inherited value is not a
-- change (specs restore with `G.warn = oldWarn`, where oldWarn was read through __index).
local function diffFields(before, now, prefix, leaks, inherited)
	for k, v in next, now do
		if before[k] ~= v and not (before[k] == nil and inherited ~= nil and rawget(inherited, k) == v) then
			table.insert(leaks, prefix .. tostring(k))
		end
	end
	for k in next, before do
		if rawget(now, k) == nil then
			table.insert(leaks, prefix .. tostring(k))
		end
	end
end

function Loader.captureState()
	local services = {}
	for name, svc in serviceProxies do
		services[name] = rawFields(svc)
	end
	local env = getfenv(Loader.requirePath)
	return {
		isServer = Loader.isServer,
		quietWarnings = Loader.quietWarnings,
		onWarn = Loader.onWarn,
		services = services,
		env = rawFields(env),
	}
end

function Loader.restoreState(snapshot): { string }
	local leaks = {}
	if Loader.isServer ~= snapshot.isServer then
		table.insert(leaks, "Loader.isServer")
		Loader.isServer = snapshot.isServer
	end
	if Loader.quietWarnings ~= snapshot.quietWarnings then
		table.insert(leaks, "Loader.quietWarnings")
		Loader.quietWarnings = snapshot.quietWarnings
	end
	if Loader.onWarn ~= snapshot.onWarn then
		table.insert(leaks, "Loader.onWarn")
		Loader.onWarn = snapshot.onWarn
	end
	for name, svc in serviceProxies do
		local before = snapshot.services[name]
		if before == nil then
			-- created lazily during the test: drop it, the next GetService builds a pristine mock
			serviceProxies[name] = nil
		else
			local changed = {}
			diffFields(before, svc, name .. ".", changed)
			if #changed > 0 then
				table.move(changed, 1, #changed, #leaks + 1, leaks)
				table.clear(svc)
				for k, v in next, before do
					rawset(svc, k, v)
				end
			end
		end
	end
	local env = getfenv(Loader.requirePath)
	local meta = getmetatable(env)
	local inherited = if type(meta) == "table" and type(meta.__index) == "table" then meta.__index else nil
	local changed = {}
	diffFields(snapshot.env, env, "env.", changed, inherited)
	if #changed > 0 then
		table.move(changed, 1, #changed, #leaks + 1, leaks)
		for k in next, rawFields(env) do
			if snapshot.env[k] == nil then
				rawset(env, k, nil)
			end
		end
		for k, v in next, snapshot.env do
			rawset(env, k, v)
		end
	end
	table.sort(leaks)
	return leaks
end

Loader.roblox = roblox
Loader.Random = RandomShim
Loader.fileToInstancePath = function(file)
	local p = string.gsub(file, "%.luau$", "")
	p = string.gsub(p, "/init$", "")
	return dirToInstancePath(p)
end

return Loader
