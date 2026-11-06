-- Lune-харнесс: эмулирует Roblox-окружение для ModuleScript'ов проекта.
-- • Дерево src/* зеркалится в настоящие Lune-Instance (DataModel → сервисы → Folder/ModuleScript),
--   поэтому script.Parent.Parent.X и ReplicatedStorage.Shared.X работают как в игре.
-- • Instance.new / свойства / Enum проверяются reflection-базой Roblox внутри Lune:
--   опечатка в имени свойства или неверный тип значения = ошибка теста.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = {}

local game = roblox.Instance.new("DataModel")
local workspaceInstance = game:GetService("Workspace")
workspaceInstance.Gravity = 196.2

-- Детерминированный полифилл Roblox Random (xorshift32): тестам важны API и детерминизм.
local RandomPolyfill = {}
RandomPolyfill.__index = RandomPolyfill
function RandomPolyfill.new(seed: number?)
	local state = math.floor(math.abs(seed or os.clock() * 1e6)) % 4294967296
	if state == 0 then
		state = 2463534242
	end
	return setmetatable({ State = state }, RandomPolyfill)
end
function RandomPolyfill:_next(): number
	local x = self.State
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.State = x
	return x / 4294967296
end
function RandomPolyfill:NextNumber(minValue: number?, maxValue: number?): number
	local low = minValue or 0
	local high = maxValue or 1
	return low + (high - low) * self:_next()
end
function RandomPolyfill:NextInteger(minValue: number, maxValue: number): number
	return minValue + math.floor(self:_next() * (maxValue - minValue + 1))
end

local cache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

local customRequire

Harness.warnings = {} :: { string }

-- Доп. глобалы окружения модулей (мок-движок кладёт сюда os/Instance/RaycastParams/UserSettings)
Harness.envExtras = {} :: { [string]: any }

local function makeEnvironment(scriptInstance: any)
	local env = {
		script = scriptInstance,
		require = customRequire,
		game = game,
		workspace = workspaceInstance,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		Font = roblox.Font,
		Random = RandomPolyfill,
		task = task,
		warn = function(...)
			local parts = table.pack(...)
			local text = ""
			for index = 1, parts.n do
				text ..= tostring(parts[index]) .. " "
			end
			table.insert(Harness.warnings, text)
			print("[warn]", text)
		end,
	}
	for key, value in Harness.envExtras do
		env[key] = value
	end
	return env
end

customRequire = function(moduleScript: any): any
	local path = moduleScript:GetAttribute("SourcePath")
	assert(type(path) == "string", "require: not a mirrored ModuleScript: " .. tostring(moduleScript))
	if cache[path] ~= nil then
		return cache[path]
	end
	assert(not loading[path], "cyclic require: " .. path)
	loading[path] = true
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = makeEnvironment(moduleScript),
		injectGlobals = true,
	})
	local result = chunk()
	loading[path] = nil
	cache[path] = result
	return result
end

local function stripExtension(name: string): (string, string)
	if string.sub(name, -12) == ".server.luau" then
		return string.sub(name, 1, -13), "Script"
	elseif string.sub(name, -12) == ".client.luau" then
		return string.sub(name, 1, -13), "LocalScript"
	end
	return string.sub(name, 1, -6), "ModuleScript"
end

local function mirror(dir: string, parent: any)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			local folder = roblox.Instance.new("Folder")
			folder.Name = name
			folder.Parent = parent
			mirror(path, folder)
		elseif string.sub(name, -5) == ".luau" then
			local baseName, className = stripExtension(name)
			local instance = roblox.Instance.new(className)
			instance.Name = baseName
			instance:SetAttribute("SourcePath", path)
			instance.Parent = parent
		end
	end
end

local replicatedStorage = game:GetService("ReplicatedStorage")
local shared = roblox.Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = replicatedStorage
mirror("src/ReplicatedStorage/Shared", shared)

local serverScriptService = game:GetService("ServerScriptService")
local server = roblox.Instance.new("Folder")
server.Name = "Server"
server.Parent = serverScriptService
mirror("src/ServerScriptService/Server", server)

local starterPlayer = game:GetService("StarterPlayer")
local starterPlayerScripts = roblox.Instance.new("StarterPlayerScripts")
starterPlayerScripts.Parent = starterPlayer
local client = roblox.Instance.new("Folder")
client.Name = "Client"
client.Parent = starterPlayerScripts
mirror("src/StarterPlayer/StarterPlayerScripts/Client", client)

-- Сетевые события берём прямо из default.project.json — единственный источник правды
local serde = require("@lune/serde")
local project = serde.decode("json", fs.readFile("default.project.json"))
local netSpec = project.tree.ReplicatedStorage.StretchPopNet
local net = roblox.Instance.new("Folder")
net.Name = "StretchPopNet"
local remoteNames = {}
for remoteName, spec in netSpec do
	if type(spec) == "table" and spec["$className"] then
		table.insert(remoteNames, remoteName)
		local remote = roblox.Instance.new(spec["$className"])
		remote.Name = remoteName
		remote.Parent = net
	end
end
table.sort(remoteNames)
net.Parent = replicatedStorage
Harness.remoteNames = remoteNames

Harness.game = game
Harness.workspace = workspaceInstance
Harness.roblox = roblox
Harness.Random = RandomPolyfill

function Harness.require(instancePath: string): any
	local current: any = game
	for segment in string.gmatch(instancePath, "[^%.]+") do
		local child = current:FindFirstChild(segment)
		assert(child, "Harness.require: path not found: " .. instancePath .. " (at " .. segment .. ")")
		current = child
	end
	return customRequire(current)
end

-- Мини-фреймворк тестов
local passed = 0
local failed = 0
local currentSuite = ""

function Harness.suite(name: string)
	currentSuite = name
	print("\n▶ " .. name)
end

function Harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

function Harness.near(actual: number, expected: number, epsilon: number, label: string?)
	if math.abs(actual - expected) > epsilon then
		error(string.format("%s: expected %.6f ± %.6f, got %.6f", label or "value", expected, epsilon, actual), 2)
	end
end

function Harness.check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

function Harness.summary(): boolean
	print(string.format("\n%d passed, %d failed (%s)", passed, failed, currentSuite))
	return failed == 0
end

return Harness
