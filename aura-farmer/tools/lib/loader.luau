--!nocheck
-- Загрузчик ModuleScript-ов из src/ для Lune (вне Roblox).
-- Поддерживает require(script.Parent.X), script.Parent:WaitForChild("X"), FindFirstChild.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = {}

local cache: { [string]: any } = {}

local REF = {}

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or "."
end

local makeRef
makeRef = function(path: string)
	local ref = { [REF] = path }
	return setmetatable(ref, {
		__index = function(_, key)
			if key == "Parent" then
				return makeRef(dirname(path))
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, name)
					return makeRef(path .. "/" .. name)
				end
			elseif key == "Name" then
				return string.match(path, "([^/]+)$")
			end
			return makeRef(path .. "/" .. key)
		end,
	})
end

local function resolveFile(path: string): string?
	for _, candidate in { path .. ".luau", path .. ".lua", path .. "/init.luau", path .. "/init.lua" } do
		if fs.isFile(candidate) then
			return candidate
		end
	end
	return nil
end

Loader.globals = {
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Enum = roblox.Enum,
	Font = roblox.Font,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	Instance = roblox.Instance,
	task = task,
}

function Loader.load(path: string): any
	local file = resolveFile(path)
	assert(file, "Module not found: " .. path)
	if cache[file] ~= nil then
		return cache[file]
	end
	local source = fs.readFile(file)
	local modulePath = string.gsub(file, "%.luau?$", "")
	modulePath = string.gsub(modulePath, "/init$", "")
	local envTable = {
		script = makeRef(modulePath),
		require = function(target)
			if type(target) == "table" and rawget(target, REF) then
				return Loader.load(rawget(target, REF))
			end
			error("Unsupported require target in loader: " .. tostring(target))
		end,
	}
	for k, v in Loader.globals do
		envTable[k] = v
	end
	local env = setmetatable(envTable, { __index = _G })
	local fn = luau.load(source, { debugName = file, environment = env, injectGlobals = true })
	local result = fn()
	cache[file] = result
	return result
end

-- Сбросить кэш (для повторной загрузки после правок в одном процессе).
function Loader.reset()
	table.clear(cache)
end

return Loader
