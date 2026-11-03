--!nocheck
-- Loads the cutscene ModuleScripts from src/ in Lune (outside Roblox).
-- require(script.Parent.X) chains are resolved to files on disk and the
-- Roblox datatypes come from @lune/roblox.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

local cache = {}
local REF = {}

local function dirname(path)
	return string.match(path, "^(.*)/[^/]+$") or "."
end

local function makeRef(path)
	return setmetatable({ [REF] = path }, {
		__index = function(_, key)
			if key == "Parent" then
				return makeRef(dirname(path))
			end
			return makeRef(path .. "/" .. key)
		end,
	})
end

local function resolveFile(path)
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
	Rect = roblox.Rect,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	typeof = roblox.typeof or typeof,
}

function Loader.load(path)
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

return Loader
