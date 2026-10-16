--!nocheck
-- Загрузчик ModuleScript-ов из src/ для Lune (сборка моделей, превиз, тесты — вне Roblox).
-- require(script.Parent.X) / require(script.Parent.Parent.X.Y) разрешаются в файлы.
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

local function makeRef(path: string)
	local ref = { [REF] = path }
	return setmetatable(ref, {
		__index = function(_, key)
			if key == "Parent" then
				return makeRef(dirname(path))
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
	Instance = roblox.Instance,
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Enum = roblox.Enum,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	BrickColor = roblox.BrickColor,
	Font = roblox.Font,
	Rect = roblox.Rect,
	PhysicalProperties = roblox.PhysicalProperties,
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

return Loader
