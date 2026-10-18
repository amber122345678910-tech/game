--!nocheck
-- Class definitions for the emulated engine.
--  * Member names/kinds/types come from .tools/globalTypes.d.luau (the same file luau-lsp uses), parsed like
--    tools/check_ui_props.py: "declare extern type X extends Y with ... end".
--  * Default property values, read-only flags and creatable/service tags come from Lune's reflection database.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local ClassDB = {}

local DEFS_PATH = "/home/user/game/.tools/globalTypes.d.luau"

-- classes[name] = { Name, Base, Own = {member -> info}, Members (merged, lazily), Defaults, Tags }
-- member info: { Kind = "prop"|"event"|"method", Type = "string type", Deprecated = bool|string, ReadOnly = bool }
local classes = {}
ClassDB.classes = classes

local function trim(s)
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function parseDefs()
	local text = fs.readFile(DEFS_PATH)
	local cur = nil
	local pendingDeprecated = nil
	for line in string.gmatch(text, "[^\n]+") do
		local name, base = string.match(line, "^declare extern type ([%w_]+) extends ([%w_]+) with")
		if not name then
			name = string.match(line, "^declare extern type ([%w_]+) with")
		end
		if not name then
			name, base = string.match(line, "^declare class ([%w_]+) extends ([%w_]+)")
		end
		if name then
			cur = { Name = name, Base = base, Own = {}, Members = nil }
			classes[name] = cur
			pendingDeprecated = nil
			if string.find(line, "with end", 1, true) then
				cur = nil
			end
		elseif cur and line == "end" then
			cur = nil
		elseif cur then
			local s = trim(line)
			if string.sub(s, 1, 1) == "@" then
				local use = string.match(s, 'use%s*=%s*"([^"]+)"')
				pendingDeprecated = use or (string.find(s, "deprecated", 1, true) and true) or nil
			else
				local fname = string.match(s, "^function ([%w_]+)%(")
				if fname then
					local prev = cur.Own[fname]
					if not prev or prev.Deprecated then
						cur.Own[fname] = { Kind = "method", Type = s, Deprecated = pendingDeprecated }
					end
				else
					local pname, ptype = string.match(s, "^([%w_]+)%s*:%s*(.+)$")
					if pname then
						local kind = if string.sub(ptype, 1, 15) == "RBXScriptSignal" then "event" else "prop"
						local prev = cur.Own[pname]
						if not prev or prev.Deprecated then
							cur.Own[pname] = { Kind = kind, Type = ptype, Deprecated = pendingDeprecated }
						end
					end
				end
				pendingDeprecated = nil
			end
		end
	end
end
parseDefs()

local refl = roblox.getReflectionDatabase()
ClassDB.reflection = refl

local reflCache = {}
local function reflClass(name)
	local c = reflCache[name]
	if c == nil then
		c = refl:GetClass(name) or false
		reflCache[name] = c
	end
	return c or nil
end
ClassDB.reflClass = reflClass

function ClassDB.exists(name)
	return classes[name] ~= nil or reflClass(name) ~= nil
end

function ClassDB.base(name)
	local c = classes[name]
	if c and c.Base then
		return c.Base
	end
	local r = reflClass(name)
	if r and r.Superclass then
		return r.Superclass
	end
	return nil
end

-- Chain of class names from the class itself up to Object
local chainCache = {}
function ClassDB.chain(name)
	local ch = chainCache[name]
	if ch then
		return ch
	end
	ch = {}
	local n = name
	local guard = 0
	while n and guard < 40 do
		table.insert(ch, n)
		n = ClassDB.base(n)
		guard += 1
	end
	chainCache[name] = ch
	return ch
end

local isaCache = {}
function ClassDB.isA(name, target)
	local key = name .. ">" .. target
	local v = isaCache[key]
	if v == nil then
		v = false
		for _, n in ClassDB.chain(name) do
			if n == target then
				v = true
				break
			end
		end
		isaCache[key] = v
	end
	return v
end

-- Read-only according to reflection (Scriptability "Read")
local function reflReadOnly(className, prop)
	for _, n in ClassDB.chain(className) do
		local r = reflClass(n)
		if r then
			local p = r.Properties[prop]
			if p then
				return p.Scriptability == "Read" or p.Scriptability == "None"
			end
		end
	end
	return false
end

-- Merged member map for a class (own + inherited); child definitions override parent ones
local memberCache = {}
function ClassDB.members(name)
	local m = memberCache[name]
	if m then
		return m
	end
	m = {}
	local ch = ClassDB.chain(name)
	for i = #ch, 1, -1 do
		local c = classes[ch[i]]
		if c then
			for k, info in c.Own do
				m[k] = info
			end
		end
	end
	-- copy so ReadOnly can be per-class
	local out = {}
	for k, info in m do
		local copy = table.clone(info)
		if copy.Kind == "prop" then
			copy.ReadOnly = reflReadOnly(name, k)
		end
		out[k] = copy
	end
	memberCache[name] = out
	return out
end

-- Default values (reflection DefaultProperties include inherited ones)
local defaultsCache = {}
function ClassDB.defaults(name)
	local d = defaultsCache[name]
	if d then
		return d
	end
	d = {}
	local r = reflClass(name)
	if r then
		for k, v in r.DefaultProperties do
			d[k] = v
		end
	end
	defaultsCache[name] = d
	return d
end

function ClassDB.tags(name)
	local r = reflClass(name)
	if not r then
		return {}
	end
	local t = {}
	for _, tag in r.Tags do
		t[tag] = true
	end
	return t
end

function ClassDB.creatable(name)
	if not ClassDB.exists(name) then
		return false
	end
	local t = ClassDB.tags(name)
	return not t.NotCreatable and not t.Service
end

-- Reflection property list (for copying deserialized instances): scriptable, non-hidden
local reflPropCache = {}
function ClassDB.reflProps(name)
	local list = reflPropCache[name]
	if list then
		return list
	end
	list = {}
	local seen = {}
	for _, n in ClassDB.chain(name) do
		local r = reflClass(n)
		if r then
			for pname, p in r.Properties do
				if not seen[pname] then
					seen[pname] = true
					local hidden = false
					for _, tag in p.Tags do
						if tag == "Hidden" or tag == "NotScriptable" or tag == "Deprecated" or tag == "WriteOnly" then
							hidden = true
						end
					end
					if not hidden and p.Scriptability ~= "None" then
						table.insert(list, pname)
					end
				end
			end
		end
	end
	reflPropCache[name] = list
	return list
end

return ClassDB
