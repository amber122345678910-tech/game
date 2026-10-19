--!nocheck
-- Прогон НАСТОЯЩИХ скриптов ролика (сервер + клиент) из собранного места в Lune с макетами сервисов Roblox.
-- Ловит ошибки выполнения до запуска в Studio: lune run tools/tests/runtime_sim.luau [AuraFarmer.rbxl]
-- Проверяет: запуск, все кадры ролика (камера, анимации, субтитры, эффекты), клавиши управления.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local RInstance = roblox.Instance
local Vector3, Vector2, CFrame, Enum = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Enum

local path = process.args[1] or "AuraFarmer.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

-- ===== Сигналы =====
local function Signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function s:Wait()
		return task.wait(0.05)
	end
	function s:Fire(...)
		for _, h in self.handlers do
			h(...)
		end
	end
	return s
end

-- ===== Обёртки экземпляров (стабильная идентичность, доп. методы) =====
local wrappers = {}
local raw = setmetatable({}, { __mode = "k" })
local overrides = {} -- DebugId -> { key = value }
local attrSignals = {}
local wrap

local function unwrap(v)
	if type(v) == "table" and raw[v] then
		return raw[v]
	end
	return v
end

local function unwrapArgs(...)
	local n = select("#", ...)
	local out = table.create(n)
	for i = 1, n do
		local a = select(i, ...)
		if type(a) == "table" and not raw[a] then
			-- массив экземпляров
			local copy = {}
			local changed = false
			for k, v in a do
				if type(v) == "table" and raw[v] then
					copy[k] = raw[v]
					changed = true
				else
					copy[k] = v
				end
			end
			out[i] = if changed then copy else a
		else
			out[i] = unwrap(a)
		end
	end
	return table.unpack(out, 1, n)
end

local function wrapResults(...)
	local n = select("#", ...)
	local out = table.create(n)
	for i = 1, n do
		local v = select(i, ...)
		if typeof(v) == "Instance" then
			out[i] = wrap(v)
		elseif type(v) == "table" then
			local arr = {}
			local any = false
			for k, x in v do
				if typeof(x) == "Instance" then
					arr[k] = wrap(x)
					any = true
				else
					arr[k] = x
				end
			end
			out[i] = if any then arr else v
		else
			out[i] = v
		end
	end
	return table.unpack(out, 1, n)
end

local extraMethods = {}

wrap = function(inst)
	if inst == nil then
		return nil
	end
	local id = inst:GetDebugId()
	local w = wrappers[id]
	if w then
		return w
	end
	w = {}
	raw[w] = inst
	setmetatable(w, {
		__index = function(_, key)
			local ov = overrides[id]
			if ov and ov[key] ~= nil then
				return ov[key]
			end
			local em = extraMethods[inst.ClassName] and extraMethods[inst.ClassName][key] or extraMethods.Instance[key]
			if em then
				return em
			end
			local ok, v = pcall(function()
				return inst[key]
			end)
			if not ok then
				-- свойство без значения в Lune: вернуть разумное значение по умолчанию
				-- вычисляемые свойства, которых нет в Lune
				if key == "Position" and inst:IsA("BasePart") then
					return inst.CFrame.Position
				elseif key == "WorldPosition" and inst:IsA("Attachment") then
					return (inst.Parent.CFrame * inst.CFrame).Position
				elseif key == "WorldCFrame" and inst:IsA("Attachment") then
					return inst.Parent.CFrame * inst.CFrame
				end
				local defaults = { Enabled = true, SoundId = "", IsLoaded = false, IsPlaying = false, TimePosition = 0 }
				if defaults[key] ~= nil then
					return defaults[key]
				end
				error(v, 2)
			end
			if type(v) == "function" then
				return function(_, ...)
					return wrapResults(v(inst, unwrapArgs(...)))
				end
			end
			if typeof(v) == "Instance" then
				return wrap(v)
			end
			if v == nil then
				local child = inst:FindFirstChild(key)
				if child then
					return wrap(child)
				end
			end
			return v
		end,
		__newindex = function(_, key, value)
			local ov = overrides[id]
			if ov and ov[key] ~= nil then
				ov[key] = value
				return
			end
			local ok, err = pcall(function()
				inst[key] = unwrap(value)
			end)
			if not ok then
				overrides[id] = overrides[id] or {}
				overrides[id][key] = value
			end
		end,
		__eq = function(a, b)
			return unwrap(a) == unwrap(b)
		end,
		__tostring = function()
			return "W(" .. inst:GetFullName() .. ")"
		end,
	})
	wrappers[id] = w
	return w
end

local function setOverride(inst, key, value)
	local id = (unwrap(inst)):GetDebugId()
	overrides[id] = overrides[id] or {}
	overrides[id][key] = value
end

extraMethods.Instance = {
	WaitForChild = function(self, name, timeout)
		local c = raw[self]:FindFirstChild(name)
		if not c then
			for _ = 1, 40 do
				task.wait(0.05)
				c = raw[self]:FindFirstChild(name)
				if c then
					break
				end
			end
		end
		if not c then
			error("WaitForChild timed out: " .. raw[self]:GetFullName() .. "." .. name, 2)
		end
		return wrap(c)
	end,
	GetAttributeChangedSignal = function(self, name)
		local key = raw[self]:GetDebugId() .. name
		attrSignals[key] = attrSignals[key] or Signal()
		return attrSignals[key]
	end,
	SetAttribute = function(self, name, value)
		raw[self]:SetAttribute(name, value)
		local key = raw[self]:GetDebugId() .. name
		if attrSignals[key] then
			attrSignals[key]:Fire()
		end
	end,
	Emit = function(self, n)
		_G.SIM_EMITS = (_G.SIM_EMITS or 0) + 1
	end,
}

-- ===== Макеты сервисов =====
local renderSteps = {}
local RunService = {
	BindToRenderStep = function(_, name, prio, fn)
		renderSteps[name] = fn
	end,
	IsStudio = function()
		return true
	end,
	IsClient = function()
		return _G.SIM_SIDE == "client"
	end,
	IsServer = function()
		return _G.SIM_SIDE == "server"
	end,
	RenderStepped = Signal(),
	Heartbeat = Signal(),
	Stepped = Signal(),
	PreSimulation = Signal(),
	PreRender = Signal(),
}
local inputBegan = Signal()
local UserInputService = { InputBegan = inputBegan, InputEnded = Signal(), MouseIconEnabled = true }
local StarterGui = { SetCoreGuiEnabled = function() end, SetCore = function() end }

local playerGui = RInstance.new("Folder")
playerGui.Name = "PlayerGui"
local playerInst = RInstance.new("Folder")
playerInst.Name = "LocalPlayer"
playerGui.Parent = playerInst
local Players = setmetatable({ LocalPlayer = wrap(playerInst) }, { __index = wrap(game:GetService("Players")) })

-- Lighting: GetSunDirection по простой модели солнца (для проверки подбора)
local lighting = game:GetService("Lighting")
extraMethods.Lighting = {
	GetSunDirection = function(self)
		local ct = raw[self].ClockTime
		local lat = math.rad(raw[self].GeographicLatitude)
		local h = (ct - 12) / 24 * math.pi * 2
		-- экваториальные координаты -> горизонтальные (склонение 0)
		local el = math.asin(math.cos(lat) * math.cos(h))
		local az = math.atan2(math.sin(h), math.cos(h) * math.sin(lat))
		return Vector3.new(math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el))
	end,
}

-- Workspace: камера, Terrain, BulkMoveTo
local ws = game:GetService("Workspace")
local camera = RInstance.new("Camera")
camera.Name = "Camera"
camera.Parent = ws
local terrain = ws:FindFirstChildOfClass("Terrain")
if not terrain then
	terrain = RInstance.new("Folder")
	terrain.Name = "Terrain"
	terrain.Parent = ws
end
local fills = 0
extraMethods.Workspace = {
	BulkMoveTo = function(self, parts, cfs)
		assert(#parts == #cfs, "BulkMoveTo: длины не совпадают")
		for i, p in parts do
			local cf = cfs[i]
			assert(typeof(cf) == "CFrame", "BulkMoveTo: не CFrame")
			local pos = cf.Position
			assert(pos.X == pos.X and pos.Y == pos.Y and pos.Z == pos.Z, "BulkMoveTo: NaN")
			unwrap(p).CFrame = cf
		end
		_G.SIM_MOVES = (_G.SIM_MOVES or 0) + #parts
	end,
}
extraMethods.Terrain = {
	FillBlock = function()
		fills += 1
	end,
	FillBall = function()
		fills += 1
	end,
	FillCylinder = function()
		fills += 1
	end,
	FillWedge = function()
		fills += 1
	end,
}
extraMethods.Folder = extraMethods.Terrain
setOverride(camera, "ViewportSize", Vector2.new(1920, 1080))
setOverride(camera, "CameraType", Enum.CameraType.Custom)
local wsW = wrap(ws)
setOverride(ws, "CurrentCamera", wrap(camera))
setOverride(ws, "Terrain", wrap(terrain))

local services = {
	RunService = RunService,
	UserInputService = UserInputService,
	StarterGui = StarterGui,
	Players = Players,
}
local gameW = setmetatable({
	GetService = function(_, name)
		if services[name] then
			return services[name]
		end
		return wrap(game:GetService(name))
	end,
}, {
	__index = function(_, k)
		return wrap(game)[k]
	end,
})

-- ===== require и запуск скриптов =====
local moduleCache = {}
local function runScript(scriptInst, side)
	local env = {}
	env.script = wrap(scriptInst)
	env.game = gameW
	env.workspace = wsW
	env.task = task
	env.require = function(m)
		local r = unwrap(m)
		local id = r:GetDebugId()
		if moduleCache[id] == nil then
			moduleCache[id] = runScript(r, side)
		end
		return moduleCache[id]
	end
	env.Instance = {
		new = function(className, parent)
			local i = RInstance.new(className)
			local w = wrap(i)
			if parent then
				i.Parent = unwrap(parent)
			end
			return w
		end,
	}
	for k, v in roblox do
		if env[k] == nil and k ~= "Instance" then
			env[k] = v
		end
	end
	env.typeof = function(v)
		if type(v) == "table" and raw[v] then
			return "Instance"
		end
		return typeof(v)
	end
	setmetatable(env, { __index = _G })
	local src = scriptInst.Source
	local fn = luau.load(src, { debugName = scriptInst:GetFullName(), environment = env, injectGlobals = true })
	_G.SIM_SIDE = side
	return fn()
end

-- Сервер
local serverScript = game:GetService("ServerScriptService").AuraFarmerServer.World
local okServer, errServer = pcall(runScript, serverScript, "server")
assert(okServer, "server error: " .. tostring(errServer))
print("server: OK, terrain fills = " .. fills)

-- Клиент
local clientScript = game:GetService("StarterPlayer").StarterPlayerScripts.AuraFarmerClient.Cinematic
local clientErr
task.spawn(function()
	local ok, err = pcall(runScript, clientScript, "client")
	if not ok then
		clientErr = err
	end
end)
for _ = 1, 100 do
	if renderSteps.AuraFarmerCinematic or clientErr then
		break
	end
	task.wait(0.05)
end
assert(not clientErr, "client init error: " .. tostring(clientErr))
local step = renderSteps.AuraFarmerCinematic
assert(step, "клиент не привязал шаг рендера")
task.wait(1.1) -- секунда чёрного кадра перед стартом

local Config = require("../lib/loader").load("src/shared/Config")
local gui = playerGui:FindFirstChild("AuraFarmerUI")
assert(gui, "нет AuraFarmerUI")
local subRoot = gui:FindFirstChild("Subtitle")
local frames = math.ceil(Config.Duration * 30) + 10
local lyricsSeen = {}
local camPositions = {}
for i = 1, frames do
	local ok, err = pcall(step, 1 / 30)
	if not ok then
		error(string.format("кадр %d: %s", i, tostring(err)))
	end
	local fill = subRoot and subRoot:FindFirstChild("Fill")
	if fill and subRoot.Visible and fill.Text ~= "" then
		lyricsSeen[fill.Text] = true
	end
	table.insert(camPositions, camera.CFrame.Position)
	if i == 60 and process.env.SIM_DEBUG then
		local names = {} for _, c in subRoot:GetChildren() do table.insert(names, c.Name .. ":" .. c.ClassName) end print("dbg", table.concat(names, ","), #gui:GetChildren())
	end
end
local nLyrics = 0
for _ in lyricsSeen do
	nLyrics += 1
end
print(string.format("client: %d кадров OK, перемещений деталей %d, строк субтитров %d, вспышек частиц %d", frames, _G.SIM_MOVES or 0, nLyrics, _G.SIM_EMITS or 0))
assert(nLyrics >= 6, "субтитры не показывались")
assert(gui:FindFirstChild("Black").Visible, "в конце должен быть чёрный кадр")

-- Клавиши: пауза, перемотка, планы, заново
local function key(code)
	inputBegan:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, false)
	for _ = 1, 3 do
		step(1 / 30)
	end
end
for _, k in { Enum.KeyCode.R, Enum.KeyCode.Space, Enum.KeyCode.Space, Enum.KeyCode.Right, Enum.KeyCode.Left, Enum.KeyCode.Four, Enum.KeyCode.Minus, Enum.KeyCode.T, Enum.KeyCode.B, Enum.KeyCode.H, Enum.KeyCode.L, Enum.KeyCode.Zero } do
	key(k)
end
print("keys: OK")
print("runtime_sim: OK")
