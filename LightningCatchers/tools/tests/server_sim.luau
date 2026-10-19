--!nocheck
-- Прогон настоящих серверных сервисов (Main.server.luau + Services/*) в Lune на "игрушечном" Roblox:
-- поддельные Instance/Players/RemoteEvent, DataStore выключен (как в Studio без доступа к API).
-- Время настоящее, поэтому задержки в Config уменьшены. Проверяет весь цикл:
-- появление, кольца, поимка, осколки, сдача, покупки, барьеры, «Шарахнуло», перегрузка, падение,
-- перезапуск, дрон, общие удары и цепная молния, смерть и выход.
-- Запуск из LightningCatchers/: .tools/lune run tools/tests/server_sim.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

----------------------------------------------------------------------
-- Сигналы и поддельные Instance
----------------------------------------------------------------------
local function newEvent()
	local handlers = {}
	local ev = {}
	function ev:Connect(fn)
		local c = { Connected = true }
		function c:Disconnect()
			c.Connected = false
		end
		table.insert(handlers, { fn = fn, c = c })
		return c
	end
	function ev:Once(fn)
		local c
		c = ev:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function ev:_fire(...)
		for _, h in table.clone(handlers) do
			if h.c.Connected then
				task.spawn(h.fn, ...)
			end
		end
	end
	return ev
end

local TREE = {
	Part = { "BasePart", "PVInstance" },
	WedgePart = { "BasePart", "PVInstance" },
	CornerWedgePart = { "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Tool = { "BackpackItem" },
	BillboardGui = { "LayerCollector", "GuiBase2d" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	PointLight = { "Light" },
	Weld = { "JointInstance" },
	Workspace = { "WorldRoot", "Model", "PVInstance" },
}
local EVENTS = { AncestryChanged = true, Died = true, CharacterAdded = true, OnServerEvent = true, PlayerAdded = true, PlayerRemoving = true }

local Fake = {}
local mt = {}
local remoteLog = {} -- [remoteName] = { {to = player|"all", args = {...}} }

local function fakeNew(className, extra)
	local self = setmetatable({ _class = className, _children = {}, _props = { Name = className }, _attrs = {}, _attrEvents = {}, _events = {} }, mt)
	if TREE[className] and table.find(TREE[className], "BasePart") then
		self._props.CFrame = CFrame.new()
		self._props.Size = Vector3.new(4, 1, 2)
		self._props.AssemblyLinearVelocity = Vector3.zero
	end
	if className == "Humanoid" then
		self._props.Health = 100
		self._props.WalkSpeed = 16
	end
	for k, v in extra or {} do
		self._props[k] = v
	end
	return self
end
Fake.new = fakeNew

local methods = {}
function methods:IsA(cls)
	if cls == "Instance" or self._class == cls then
		return true
	end
	return TREE[self._class] ~= nil and table.find(TREE[self._class], cls) ~= nil
end
function methods:FindFirstChild(name)
	for _, c in self._children do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end
function methods:FindFirstChildOfClass(cls)
	for _, c in self._children do
		if c._class == cls then
			return c
		end
	end
	return nil
end
function methods:GetChildren()
	return table.clone(self._children)
end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in i._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:IsDescendantOf(anc)
	local p = rawget(self, "_parent")
	while p do
		if p == anc then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end
function methods:Destroy()
	self.Parent = nil
	for _, c in table.clone(self._children) do
		c:Destroy()
	end
end
function methods:SetAttribute(k, v)
	local old = self._attrs[k]
	self._attrs[k] = v
	if old ~= v and self._attrEvents[k] then
		self._attrEvents[k]:_fire()
	end
end
function methods:GetAttribute(k)
	return self._attrs[k]
end
function methods:GetAttributeChangedSignal(k)
	self._attrEvents[k] = self._attrEvents[k] or newEvent()
	return self._attrEvents[k]
end
function methods:GetBoundingBox()
	-- грубо: по осям, без поворотов деталей
	local lo, hi
	for _, d in self:GetDescendants() do
		if d._props.CFrame and d._props.Size then
			local p, half = d._props.CFrame.Position, d._props.Size / 2
			lo = if lo then lo:Min(p - half) else p - half
			hi = if hi then hi:Max(p + half) else p + half
		end
	end
	if not lo then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end
function methods:PivotTo(cf)
	local root = self:FindFirstChild("HumanoidRootPart") or self._props.PrimaryPart
	if root then
		root.CFrame = cf
	end
end
-- RemoteEvent / UnreliableRemoteEvent
function methods:FireClient(player, ...)
	remoteLog[self.Name] = remoteLog[self.Name] or {}
	table.insert(remoteLog[self.Name], { to = player, args = table.pack(...) })
end
function methods:FireAllClients(...)
	remoteLog[self.Name] = remoteLog[self.Name] or {}
	table.insert(remoteLog[self.Name], { to = "all", args = table.pack(...) })
end
-- Humanoid
function methods:EquipTool(tool)
	tool.Parent = rawget(self, "_parent")
end

mt.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "ClassName" then
		return rawget(self, "_class")
	elseif key == "Position" and self._props.CFrame then
		return self._props.CFrame.Position
	end
	local v = self._props[key]
	if v ~= nil then
		return v
	end
	if methods[key] then
		return methods[key]
	end
	if EVENTS[key] then
		self._events[key] = self._events[key] or newEvent()
		return self._events[key]
	end
	return self:FindFirstChild(key)
end
mt.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old == value then
			return
		end
		if old then
			local i = table.find(old._children, self)
			if i then
				table.remove(old._children, i)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(value._children, self)
		end
		if self._events.AncestryChanged then
			self._events.AncestryChanged:_fire(self, value)
		end
	elseif key == "Position" then
		self._props.CFrame = CFrame.new(value)
	else
		self._props[key] = value
	end
end

----------------------------------------------------------------------
-- Мир
----------------------------------------------------------------------
local TIME_OFFSET = 5000
local Workspace = fakeNew("Workspace", { Name = "Workspace" })
function Workspace:GetServerTimeNow()
	return os.clock() + TIME_OFFSET
end
function Workspace:Raycast()
	return nil
end
local function serverNow()
	return os.clock() + TIME_OFFSET
end

local Players = fakeNew("Players", { Name = "Players", CharacterAutoLoads = true, RespawnTime = 0.3 })
function Players:GetPlayers()
	local out = {}
	for _, c in self._children do
		if c._class == "Player" then
			table.insert(out, c)
		end
	end
	return out
end

local ReplicatedStorage = fakeNew("ReplicatedStorage", { Name = "ReplicatedStorage" })
local Remotes = fakeNew("Folder", { Name = "Remotes" })
Remotes.Parent = ReplicatedStorage
for _, name in { "DataSync", "StrikeSpawn", "StrikeResult", "Catch", "ShardSpawn", "ShardCollect", "Notify", "Banner", "Effect" } do
	fakeNew("RemoteEvent", { Name = name }).Parent = Remotes
end
fakeNew("UnreliableRemoteEvent", { Name = "BoltFX" }).Parent = Remotes
fakeNew("RemoteFunction", { Name = "Request" }).Parent = Remotes

local guid = 0
local services = {
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	Workspace = Workspace,
	DataStoreService = {
		GetDataStore = function()
			error("StudioAccessToApisNotAllowed")
		end,
	},
	RunService = {
		IsStudio = function()
			return true
		end,
	},
	HttpService = {
		GenerateGUID = function()
			guid += 1
			return "guid-" .. guid
		end,
	},
}
local game = {
	GetService = function(_, name)
		return assert(services[name], "нет сервиса " .. name)
	end,
	BindToClose = function() end,
}

----------------------------------------------------------------------
-- Загрузчик модулей из src/ (script, require, WaitForChild/FindFirstChild)
----------------------------------------------------------------------
local REF = {}
local cache = {}
local function fileFor(path)
	for _, c in { path .. ".luau", path .. ".server.luau", path .. "/init.luau" } do
		if fs.isFile(c) then
			return c
		end
	end
	return nil
end
local function dirname(path)
	return string.match(path, "^(.*)/[^/]+$") or "."
end
local makeRef
function makeRef(path)
	return setmetatable({ [REF] = path }, {
		__index = function(_, key)
			if key == "Parent" then
				return makeRef(dirname(path))
			elseif key == "Name" then
				return string.match(path, "([^/]+)$")
			elseif key == "FindFirstChild" or key == "WaitForChild" then
				return function(_, name)
					local child = path .. "/" .. name
					if fileFor(child) or fs.isDir(child) then
						return makeRef(child)
					end
					return nil
				end
			elseif key == "IsA" then
				return function(_, cls)
					return cls == "ModuleScript" and fileFor(path) ~= nil
				end
			end
			return makeRef(path .. "/" .. key)
		end,
	})
end

-- Общая папка Shared лежит в ReplicatedStorage
local sharedRef = makeRef("src/shared")
local rsWait = methods.WaitForChild
ReplicatedStorage._props.WaitForChild = function(self, name)
	if name == "Shared" then
		return sharedRef
	end
	return rsWait(self, name)
end

local warnings = {}
local load
local function req(target)
	assert(type(target) == "table" and rawget(target, REF), "require: не модуль " .. tostring(target))
	return load(rawget(target, REF))
end
function load(path)
	local file = assert(fileFor(path), "нет модуля " .. path)
	if cache[file] ~= nil then
		return cache[file]
	end
	local env = setmetatable({
		script = makeRef(path),
		require = req,
		game = game,
		workspace = Workspace,
		Instance = { new = fakeNew },
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Enum = roblox.Enum,
		-- в Lune устаревший список шрифтов (нет BuilderSans) — подделка
		Font = {
			fromEnum = function(e)
				return { Enum = e }
			end,
			-- шрифты игры (src/shared/Fonts.luau) создаются через Font.new(путь, вес, стиль)
			new = function(family, weight, style)
				return { Family = family, Weight = weight, Style = style }
			end,
		},
		task = task,
		typeof = function(v)
			if getmetatable(v) == mt then
				return "Instance"
			end
			return typeof(v)
		end,
		warn = function(...)
			local text = table.concat(table.pack(...), " ")
			table.insert(warnings, text)
			print("  [warn] " .. text)
		end,
	}, { __index = _G })
	local fn = luau.load(fs.readFile(file), { debugName = file, environment = env, injectGlobals = true })
	local result = fn()
	cache[file] = if result == nil then true else result
	return result
end

----------------------------------------------------------------------
-- Тестовые помощники
----------------------------------------------------------------------
local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. msg)
	end
end
local function waitUntil(pred, timeout)
	local deadline = os.clock() + (timeout or 3)
	while os.clock() < deadline do
		local v = pred()
		if v then
			return v
		end
		task.wait(0.02)
	end
	return nil
end
local function messages(remote, player)
	local out = {}
	for _, m in remoteLog[remote] or {} do
		if player == nil or m.to == player then
			table.insert(out, m.args)
		end
	end
	return out
end
local function clearLog()
	table.clear(remoteLog)
end
local function lastMsg(remote, player, pred)
	local list = messages(remote, player)
	for i = #list, 1, -1 do
		if pred == nil or pred(list[i]) then
			return list[i]
		end
	end
	return nil
end

-- Конфиг: короткие задержки, чтобы прогон шёл секунды
local Config = load("src/shared/Config")
Config.Catch.FirstStrikeDelay = 0.3
Config.Catch.FirstStrikeWarning = 0.7
Config.Server.ZoneEnterDelay = 0.2
Config.Drone.TripTime = 0.4
Config.Server.TeleportCooldown = 0 -- пауза телепорта проверяется отдельно
for _, z in Config.Zones do
	z.Warning = 0.9
	z.Interval = 0.35
end
local Zones = load("src/shared/Zones")
local Economy = load("src/shared/Economy")
local Strikes = load("src/shared/Strikes")

-- Игрок и его персонаж
local nextUserId = 0
local function addPlayer(name)
	nextUserId += 1
	local p = fakeNew("Player", { Name = name, DisplayName = name, UserId = nextUserId })
	fakeNew("Backpack", { Name = "Backpack" }).Parent = p
	p._props.LoadCharacterAsync = function(self)
		local old = rawget(self, "_props").Character
		if old then
			old:Destroy()
		end
		local char = fakeNew("Model", { Name = name })
		local hum = fakeNew("Humanoid", { Name = "Humanoid" })
		hum.Parent = char
		local root = fakeNew("Part", { Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1) })
		root.Parent = char
		fakeNew("Part", { Name = "Head", Size = Vector3.new(1, 1, 1) }).Parent = char
		fakeNew("Part", { Name = "UpperTorso", Size = Vector3.new(2, 1.6, 1) }).Parent = char
		char._props.PrimaryPart = root
		self.Character = char
		char.Parent = Workspace
		task.defer(function()
			self.CharacterAdded:_fire(char)
		end)
	end
	p.Parent = Players
	Players.PlayerAdded:_fire(p)
	return p
end
local function removePlayer(p)
	Players.PlayerRemoving:_fire(p)
	task.wait()
	p.Parent = nil
end
local function root(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end
local function moveTo(p, pos)
	root(p).CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
end
local function request(p, action, payload)
	local fn = Remotes.Request.OnServerInvoke
	return fn(p, action, payload)
end
local function fireCatch(p, id, hit, tap)
	Remotes.Catch.OnServerEvent:_fire(p, id, hit, tap)
end
local function strikeMsgs(p)
	local out = {}
	for _, args in messages("StrikeSpawn", p) do
		table.insert(out, args[1])
	end
	return out
end
local function resultFor(p, id, hit)
	for _, args in messages("StrikeResult", p) do
		local m = args[1]
		if m.Id == id and m.Hit == hit then
			return m
		end
	end
	return nil
end
-- Поймать кольцо: встать в центр к моменту удара и нажать (tapOffset — ошибка тайминга)
local function catchRing(p, msg, hit, tapOffset)
	local hitTime = msg.Hits[hit]
	local pos = msg.To or msg.Pos
	moveTo(p, pos)
	waitUntil(function()
		return serverNow() >= hitTime + math.max(0, tapOffset or 0)
	end, 5)
	fireCatch(p, msg.Id, hit, hitTime + (tapOffset or 0))
	return waitUntil(function()
		return resultFor(p, msg.Id, hit)
	end, 2)
end

----------------------------------------------------------------------
-- Запуск сервера
----------------------------------------------------------------------
load("src/server/Main.server")
local DataService = load("src/server/Services/DataService")
local EconomyService = load("src/server/Services/EconomyService")
local PlayerService = load("src/server/Services/PlayerService")
local StrikeService = load("src/server/Services/StrikeService")
local RequestService = load("src/server/Services/RequestService")
local FulguriteService = load("src/server/Services/FulguriteService")
local Fulgurite = load("src/shared/Fulgurite")
local PlayerData = load("src/shared/PlayerData")

check(ReplicatedStorage:FindFirstChild("GameState") ~= nil, "GameState создан")
check(ReplicatedStorage.GameState:GetAttribute("Event") == "", "GameState.Event")
check(Players.CharacterAutoLoads == false, "CharacterAutoLoads выключен")
check(RequestService.has("BuyUpgrade") and RequestService.has("Rebirth") and RequestService.has("Teleport"), "обработчики Request")

local resolved = {}
StrikeService.CatchResolved:Connect(function(p, info)
	table.insert(resolved, { p = p, info = info })
end)
local sold = {}
EconomyService.Sold:Connect(function(p, volts, fill)
	table.insert(sold, { p = p, volts = volts, fill = fill })
end)
local shardsCollected = 0
StrikeService.ShardCollected:Connect(function(_, n)
	shardsCollected += n
end)

----------------------------------------------------------------------
-- 1. Новичок: появление и снаряжение
----------------------------------------------------------------------
print("1. появление")
local A = addPlayer("Аня")
check(waitUntil(function()
	return A.Character and PlayerService.getRoot(A)
end), "персонаж появился")
task.wait(0.1)
local spawn1 = Zones.spawnFor(1)
check(Zones.flatDist(root(A).Position, spawn1) < 0.5, "появился на острове 1")
check(A:GetAttribute("Zone") == 1, "атрибут Zone = 1")
check(A:GetAttribute("JarFill") == 0, "JarFill = 0")
check(A:GetAttribute("RodTier") == 0 and A:GetAttribute("Rebirths") == 0 and A:GetAttribute("BestCombo") == 0, "атрибуты показателей")
local hum = A.Character.Humanoid
check(hum.WalkSpeed == Economy.walkSpeed(0), "скорость от сапог")
local rod = A.Character:FindFirstChild("Громоотвод")
check(rod and rod:IsA("Tool") and rod.ManualActivationOnly and not rod.CanBeDropped and rod.RequiresHandle, "громоотвод в руке")
check(rod and rod.Handle and rod.Tip and rod.Tip.Material == roblox.Enum.Material.Neon, "у громоотвода есть Handle и Tip")
-- кончик лежит по оси "вверх" хвата (у общей модели — WeldConstraint и CFrame, у запасной — Weld.C0)
local tipWeld = rod and rod.Tip:FindFirstChildOfClass("Weld")
local tipOffset = if tipWeld then tipWeld.C0.Position elseif rod then rod.Handle.CFrame:PointToObjectSpace(rod.Tip.Position) else Vector3.zero
check(rod and tipOffset.Magnitude > 1 and tipOffset.Unit:Dot(rod.Grip.UpVector) > 0.95, "хват вертикальный (кончик вверх)")
check(rod and rod:GetAttribute("Tier") == 0, "уровень громоотвода 0")
local jar = A.Character:FindFirstChild("Jar")
check(rod and rod.ToolTip == "Медный громоотвод" and jar and jar:FindFirstChild("Strap") ~= nil, "модели из общего Models")
local jarLight = jar and jar.Core and jar.Core:FindFirstChildOfClass("PointLight")
check(jarLight ~= nil and jarLight.Enabled == false, "банка с ядром и выключенным светом")
local jarWeld = jar and jar.PrimaryPart and jar.PrimaryPart:FindFirstChild("JarWeld")
check(jarWeld and jarWeld.Part0 == A.Character.UpperTorso and jarWeld.C0.Position.Z > 0.5, "банка приварена к спине")
local tag = A.Character.Head:FindFirstChild("Nametag")
check(tag and tag.MaxDistance == 60 and tag.PlayerName.Text == "Аня", "табличка над головой")
check(tag and tag.Series.Visible == false, "серия скрыта, пока 0")

----------------------------------------------------------------------
-- 2. Первое кольцо и поимка
----------------------------------------------------------------------
print("2. первое кольцо")
local first = waitUntil(function()
	return strikeMsgs(A)[1]
end, 2)
check(first ~= nil, "первое кольцо пришло")
if first then
	check(first.Kind == "single", "первое кольцо — обычное")
	check(math.abs((first.Hits[1] - first.Spawn) - Config.Catch.FirstStrikeWarning) < 1e-6, "предупреждение первого кольца")
	check(Zones.flatDist(first.Pos, root(A).Position) <= Config.Catch.RingRadius, "первое кольцо у ног")
	local r = catchRing(A, first, 1, 0)
	check(r and r.Grade == "perfect", "ИДЕАЛЬНО при точном нажатии: " .. tostring(r and r.Grade))
	if r then
		local expect = Economy.catchCharge(1, first.Color, "perfect", 1, 0, 1)
		check(math.abs(r.Charge - expect) < 1e-6, "заряд по формуле")
		check(r.Combo == 1 and A:GetAttribute("Combo") == 1, "комбо 1")
		check(r.Final == true, "последний удар кольца")
		check(r.NewIndex == "1:" .. first.Color, "новая ячейка Молниедекса")
		check(math.abs(r.Jar - expect) < 1e-6 and r.Capacity == Economy.jarCapacity(0), "банка в результате")
	end
	local d = DataService.get(A)
	check(d.Stats.Catches == 1 and d.Stats.Perfects == 1 and d.Stats.BestCombo == 1, "статистика")
	check(A:GetAttribute("BestCombo") == 1, "атрибут BestCombo")
	check(tag.Series.Visible and tag.Series.Text == "Серия: 1", "табличка: серия")
	check(A:GetAttribute("JarFill") > 0, "JarFill вырос")
	-- повторное нажатие того же удара игнорируется
	local before = #messages("StrikeResult", A)
	fireCatch(A, first.Id, 1, first.Hits[1])
	task.wait(0.1)
	check(#messages("StrikeResult", A) == before, "повтор не оценивается")
end

----------------------------------------------------------------------
-- 3. Обычный поток, ХОРОШО / МИМО, осколки
----------------------------------------------------------------------
print("3. поток колец")
local skipped = 0
local function freshRing(p, after, pred)
	local found = waitUntil(function()
		for _, m in strikeMsgs(p) do
			if m.Spawn > after and (pred == nil or pred(m)) and serverNow() < m.Hits[1] - 0.25 then
				return m
			end
		end
		return nil
	end, 3)
	if not found then
		skipped += 1
		print("  (подходящее кольцо не появилось: " .. debug.traceback("", 2):match("server_sim:(%d+)") .. ")")
	end
	return found
end
local t0 = serverNow()
local ring = freshRing(A, t0)
check(ring ~= nil, "новые кольца появляются")
if ring then
	local d = DataService.get(A)
	local _, good = Strikes.windows(0, 0)
	local r = catchRing(A, ring, 1, good - 0.02)
	check(r and r.Grade == "good", "ХОРОШО: " .. tostring(r and r.Grade))
	check(r and r.Combo == 1, "ХОРОШО сохраняет комбо")
	check(d.Stats.Catches == 2, "поимок 2")
end
local ringMiss = freshRing(A, serverNow())
if ringMiss then
	local r = catchRing(A, ringMiss, 1, 0.4)
	check(r and r.Grade == "miss", "МИМО: " .. tostring(r and r.Grade))
	check(r and r.Combo == 0 and A:GetAttribute("Combo") == 0, "МИМО сбрасывает комбо")
	check((A:GetAttribute("ZappedUntil") or 0) < serverNow(), "на острове 1 током не бьёт")
end
-- чужое и несуществующее
fireCatch(A, 999999, 1, serverNow())
fireCatch(A, "x", 1, serverNow())
fireCatch(A, 1, 0 / 0, serverNow())
task.wait(0.05)
check(true, "мусорные Catch не роняют сервер")

-- стоим в стороне: удары уходят в землю, растут осколки
print("   осколки")
clearLog()
local farSpot = Zones.Geo[1].Center
moveTo(A, farSpot)
local ground = waitUntil(function()
	return lastMsg("StrikeResult", A, function(a)
		return a[1].Grade == "ground"
	end)
end, 4)
check(ground ~= nil, "удар без нажатия вне кольца -> ground")
local shardMsg = waitUntil(function()
	return lastMsg("ShardSpawn", A)
end, 1)
check(shardMsg ~= nil, "осколок появился")
if shardMsg then
	local s = shardMsg[1]
	check(s.Amount >= 1 and s.Expires > serverNow(), "осколок: количество и срок")
	local shardsBefore = DataService.get(A).Shards
	local away = Zones.Geo[1].Center + (Zones.Geo[1].Center - s.Pos).Unit * 30
	moveTo(A, Vector3.new(away.X, s.Pos.Y, away.Z))
	Remotes.ShardCollect.OnServerEvent:_fire(A, s.Id)
	task.wait(0.05)
	check(DataService.get(A).Shards == shardsBefore, "издалека не собирается")
	moveTo(A, s.Pos)
	Remotes.ShardCollect.OnServerEvent:_fire(A, s.Id)
	task.wait(0.05)
	check(DataService.get(A).Shards == shardsBefore + s.Amount, "осколок собран")
	check(shardsCollected == s.Amount, "сигнал ShardCollected")
	Remotes.ShardCollect.OnServerEvent:_fire(A, s.Id)
	task.wait(0.05)
	check(DataService.get(A).Shards == shardsBefore + s.Amount, "дважды не собирается")
end
-- стоим в кольце и не жмём: на острове 1 — "miss" (подсказка), без удара током
clearLog()
local standRing = freshRing(A, serverNow())
if standRing then
	moveTo(A, standRing.Pos)
	local r = waitUntil(function()
		return resultFor(A, standRing.Id, 1)
	end, 3)
	check(r and r.Grade == "miss", "стоял в кольце без нажатия (остров 1) -> miss: " .. tostring(r and r.Grade))
end
local evGrades = {}
for _, e in resolved do
	evGrades[e.info.grade] = true
end
check(evGrades.perfect and evGrades.good and evGrades.miss and evGrades.ground, "CatchResolved для всех исходов")

----------------------------------------------------------------------
-- 4. Банка: полная без перегрузки, сдача
----------------------------------------------------------------------
print("4. банка и сдача")
moveTo(A, Zones.Geo[1].Center)
local cap = EconomyService.capacity(A)
DataService.update(A, function(d)
	d.Charge = cap - 0.5
end)
clearLog()
local added, burst, lost = EconomyService.addCharge(A, 3, 1)
check(math.abs(added - 0.5) < 1e-9 and not burst and math.abs(lost - 2.5) < 1e-9, "остров 1: лишнее теряется")
check(A:GetAttribute("JarFill") == 1, "JarFill = 1")
check(lastMsg("Notify", A, function(a)
	return string.find(a[1], "Банка полна", 1, true) ~= nil
end) ~= nil, "напоминание «Банка полна»")
-- на подстанцию
local pad = Zones.Geo[1].SellPad
local voltsBefore = DataService.get(A).Volts
moveTo(A, pad)
check(waitUntil(function()
	return DataService.get(A).Charge == 0
end, 1.5), "сдал на подстанции")
local d = DataService.get(A)
local expectVolts = Economy.sellValue(cap, cap, EconomyService.multiplierFor(A))
check(d.Volts - voltsBefore == expectVolts, "Вольты по формуле")
check(d.TotalVolts >= expectVolts and d.Stats.Sells == 1, "TotalVolts и Sells")
check(#sold == 1 and sold[1].volts == expectVolts and sold[1].fill == 1, "сигнал Sold")
check(lastMsg("Effect", A, function(a)
	return a[1].Kind == "sell" and a[1].Value == expectVolts
end) ~= nil, "Effect sell")
check(A:GetAttribute("JarFill") == 0, "JarFill = 0 после сдачи")
-- снимок копируется в момент отправки (как в Roblox), отправка — с троттлингом
check(waitUntil(function()
	local dataSync = lastMsg("DataSync", A)
	return dataSync ~= nil and dataSync[1].Volts == d.Volts
end, 1), "DataSync со свежими данными")
moveTo(A, Zones.Geo[1].Center)

----------------------------------------------------------------------
-- 5. Покупки
----------------------------------------------------------------------
print("5. покупки")
DataService.update(A, function(dd)
	dd.Volts = 0
end)
local ok, err = request(A, "BuyUpgrade", "Boots")
check(ok == false and err == "Не хватает Вольт", "нет денег: " .. tostring(err))
ok, err = request(A, "BuyUpgrade", "Nope")
check(ok == false and type(err) == "string", "неизвестное улучшение")
ok, err = request(A, "BuyUpgrade", { 1 })
check(ok == false, "мусорный payload")
ok, err = request(A, "Hack", nil)
check(ok == false and err == "Неизвестное действие", "неизвестное действие")
ok, err = request(A, 123, nil)
check(ok == false, "действие не строка")
EconomyService.grantVolts(A, 1e9, "test")
check(DataService.get(A).Volts == 1e9, "grantVolts")
ok, err = request(A, "BuyUpgrade", "Boots")
check(ok == true and err == 1, "купил сапоги")
check(A.Character.Humanoid.WalkSpeed == Economy.walkSpeed(1), "скорость обновилась")
check(lastMsg("Effect", A, function(a)
	return a[1].Kind == "levelUp" and a[1].Text == "Boots"
end) ~= nil, "Effect levelUp")
for _ = 1, 6 do
	request(A, "BuyUpgrade", "Rod")
	task.wait(0.11)
end
check(DataService.get(A).Upgrades.Rod == 6 and A:GetAttribute("RodTier") == 1, "RodTier = floor(Rod/6)")
local rods = 0
for _, c in A.Character:GetChildren() do
	if c.Name == "Громоотвод" then
		rods += 1
	end
end
check(A.Character["Громоотвод"]:GetAttribute("Tier") == 1 and rods == 1, "громоотвод сменился на уровень 1")
local capBefore = EconomyService.capacity(A)
request(A, "BuyUpgrade", "Jar")
check(EconomyService.capacity(A) > capBefore, "банка больше")
ok, err = request(A, "UnlockZone", 3)
check(ok == false, "через остров нельзя")
ok, err = request(A, "BuyDrone", nil)
check(ok == false, "дрон рано: " .. tostring(err))
ok, err = request(A, "UnlockZone", 2)
check(ok == true and err == 2 and DataService.get(A).Zone == 2, "открыл остров 2")
check(lastMsg("Effect", A, function(a)
	return a[1].Kind == "zoneUnlocked" and a[1].Zone == 2
end) ~= nil, "Effect zoneUnlocked")
ok = request(A, "UnlockZone", 2)
check(ok == false, "дважды не открыть")
ok, err = request(A, "ToggleDrone", true)
check(ok == false, "без дрона не переключить")
ok, err = request(A, "UnlockZone", 0 / 0)
check(ok == false, "NaN не остров")
-- лимит частоты
task.wait(1.3)
local tooFast = 0
for _ = 1, 25 do
	local okR, e = request(A, "Teleport", 99)
	if not okR and e == "Слишком быстро! Подожди секунду" then
		tooFast += 1
	end
end
check(tooFast >= 10, "лимит запросов: " .. tooFast)
task.wait(1.3)

----------------------------------------------------------------------
-- 6. Барьер закрытого острова, телепорт, падение
----------------------------------------------------------------------
print("6. барьеры и телепорт")
clearLog()
local g3 = Zones.Geo[3]
local pastGate = g3.Gate + g3.Dir * 4
moveTo(A, pastGate)
check(waitUntil(function()
	local along = (root(A).Position - g3.BridgeStart):Dot(g3.Dir)
	local gateAlong = (g3.Gate - g3.BridgeStart):Dot(g3.Dir)
	return along < gateAlong - 4
end, 1), "отброшен назад от барьера")
check(lastMsg("Notify", A, function(a)
	-- у барьера следующего острова — цена (или «Хватает ⚡!» и магазин), у дальнего — «сначала открой …»
	return string.find(a[1], "Остров закрыт", 1, true) == 1 or string.find(a[1], "Хватает", 1, true) == 1
end) ~= nil, "Notify «Остров закрыт»")
moveTo(A, g3.Center)
check(waitUntil(function()
	return Zones.zoneAt(root(A).Position) ~= 3
end, 1), "с закрытого острова тоже выкидывает")
check(A:GetAttribute("Zone") ~= 3, "закрытый остров не становится зоной")
ok, err = request(A, "Teleport", 3)
check(ok == false and err == "Остров закрыт — открой его в магазине", "телепорт на закрытый остров")
local zc = {}
PlayerService.ZoneChanged:Connect(function(p, new, old)
	table.insert(zc, { p = p, new = new, old = old })
end)
ok = request(A, "Teleport", 2)
check(ok == true and A:GetAttribute("Zone") == 2 and DataService.get(A).LastZone == 2, "телепорт на остров 2")
check(#zc >= 1 and zc[#zc].new == 2, "ZoneChanged")
check(Zones.zoneAt(root(A).Position) == 2, "персонаж на острове 2")
ok = request(A, "Teleport", 0)
check(ok == true and A:GetAttribute("Zone") == 0, "телепорт в хаб")
task.wait(0.6)
local hubRings = 0
for _, m in strikeMsgs(A) do
	if m.Spawn > serverNow() - 0.5 then
		hubRings += 1
	end
end
check(hubRings == 0, "в хабе колец нет")
ok, err = request(A, "Teleport", 0)
check(ok == false and err == "Ты уже в городе", "телепорт туда, где стоишь, — нельзя: " .. tostring(err))
ok, err = request(A, "Teleport", 2)
check(ok == true and A:GetAttribute("Zone") == 2, "телепорт обратно на остров 2: " .. tostring(err))
Config.Server.TeleportCooldown = 5
ok, err = request(A, "Teleport", 0)
check(ok == false and typeof(err) == "string" and string.find(err, "заряжается", 1, true) ~= nil, "пауза между телепортами: " .. tostring(err))
check(A:GetAttribute("Zone") == 2, "без телепорта остался на острове 2")
Config.Server.TeleportCooldown = 0
-- падение
root(A).CFrame = CFrame.new(Zones.Geo[2].Center + Vector3.new(200, -200, 0))
check(waitUntil(function()
	return root(A).Position.Y > Config.VoidY
end, 1), "возврат после падения")
check(Zones.flatDist(root(A).Position, Zones.spawnFor(2)) < 0.5, "на точку появления острова 2")

----------------------------------------------------------------------
-- 7. Остров 2: удар током, перегрузка
----------------------------------------------------------------------
print("7. остров 2")
clearLog()
moveTo(A, Zones.Geo[2].Center)
local r2 = freshRing(A, serverNow(), function(m)
	return m.Kind == "single"
end)
if r2 then
	local r = catchRing(A, r2, 1, 0.45)
	check(r and r.Grade == "miss", "МИМО на острове 2")
	check((A:GetAttribute("ZappedUntil") or 0) > serverNow(), "ZappedUntil выставлен")
	check(A.Character.Humanoid.WalkSpeed == 0, "оглушён")
	task.wait(Economy.zapStun(0) + 0.1)
	check(A.Character.Humanoid.WalkSpeed == Economy.walkSpeed(1), "оглушение прошло")
end
-- стоял в кольце и не нажал -> zap
local r3 = freshRing(A, serverNow(), function(m)
	return m.Kind == "single"
end)
if r3 then
	moveTo(A, r3.Pos)
	local r = waitUntil(function()
		return resultFor(A, r3.Id, 1)
	end, 3)
	check(r and r.Grade == "zap", "стоял и не нажал (остров 2) -> zap: " .. tostring(r and r.Grade))
end
-- двойной удар: два результата, Final на последнем
local dblFrom = serverNow()
local dbl = nil
for _ = 1, 10 do -- двойных 20%: ждём подольше
	dbl = freshRing(A, serverNow(), function(m)
		return m.Kind == "double"
	end)
	if dbl then
		break
	end
end
check(dbl ~= nil, "двойные удары на острове 2")
if not dbl then
	local kinds = {}
	for _, m in strikeMsgs(A) do
		if m.Spawn > dblFrom then
			table.insert(kinds, m.Kind)
		end
	end
	print("   колец за время ожидания:", #kinds, table.concat(kinds, ","), "area", PlayerService.getArea(A), "zone", PlayerService.getZone(A), "pos", root(A).Position)
end
if dbl then
	local a1 = catchRing(A, dbl, 1, 0)
	local a2 = catchRing(A, dbl, 2, 0)
	check(a1 and a1.Final == false and a2 and a2.Final == true, "двойной: Final только на последнем")
	check(a2 and a2.Combo == 2, "комбо растёт по ударам: " .. tostring(a2 and a2.Combo))
end
-- перегрузка
moveTo(A, Zones.Geo[2].Center)
local cap2 = EconomyService.capacity(A)
DataService.update(A, function(dd)
	dd.Charge = cap2 * 1.45
end)
local add2, _, lost2 = EconomyService.addCharge(A, cap2, 2)
local d2 = DataService.get(A)
check(d2.Charge <= cap2 * 1.5 + 1e-6, "не больше 150%")
check(math.abs(add2 - cap2 * 0.05) < 1e-6 or d2.Charge < cap2, "добавилось до предела (или лопнула)")
check(lost2 > 0, "лишнее потеряно")
-- много поимок сверх 100%: хоть раз лопнет, остаётся половина
local bursts = 0
for _ = 1, 200 do
	DataService.update(A, function(dd)
		dd.Charge = cap2 * 1.4
	end)
	local _, b = EconomyService.addCharge(A, 1, 2)
	if b then
		bursts += 1
		check(math.abs(DataService.get(A).Charge - (cap2 * 1.4 + 1) * 0.5) < 1e-6, "лопнула: осталась половина")
		break
	end
end
check(bursts == 1, "банка может лопнуть при перегрузке")
local safeBurst = false
for _ = 1, 200 do
	DataService.update(A, function(dd)
		dd.Charge = cap2 * 1.4
	end)
	local _, b = EconomyService.addCharge(A, 1, 2, true)
	safeBurst = safeBurst or b
end
check(not safeBurst, "бонус safe не лопает банку")
check(A:GetAttribute("JarFill") <= 1.5, "JarFill ≤ 1.5")
DataService.update(A, function(dd)
	dd.Charge = 0
end)

----------------------------------------------------------------------
-- 8. Дрон
----------------------------------------------------------------------
print("8. дрон")
DataService.update(A, function(dd)
	dd.Zone = 3
end)
ok = request(A, "BuyDrone", nil)
check(ok == true and DataService.get(A).Drone == true, "купил дрон")
request(A, "Teleport", 1)
task.wait(0.1)
clearLog()
local capNow = EconomyService.capacity(A)
DataService.update(A, function(dd)
	dd.Charge = capNow
end)
check(waitUntil(function()
	return lastMsg("Effect", A, function(a)
		return a[1].Kind == "drone" and a[1].Text == "depart"
	end)
end, 1), "дрон вылетел")
check(waitUntil(function()
	return lastMsg("Effect", A, function(a)
		return a[1].Kind == "drone" and a[1].Text == "sold" and a[1].Value > 0
	end)
end, 1.5), "дрон сдал банку")
check(DataService.get(A).Charge == 0, "банка пуста")
local function departed()
	return lastMsg("Effect", A, function(a)
		return a[1].Kind == "drone" and a[1].Text == "depart"
	end)
end
local function droneSold()
	return lastMsg("Effect", A, function(a)
		return a[1].Kind == "drone" and a[1].Text == "sold" and a[1].Value > 0
	end)
end
-- остров с перегрузкой: дрон тоже летит сразу и забирает банку с собой; с дроном банка не перегружается
request(A, "Teleport", 2)
task.wait(0.1)
clearLog()
DataService.update(A, function(dd)
	dd.Charge = capNow * 0.95
end)
local addedD, burstD, lostD = EconomyService.addCharge(A, capNow * 0.2, 2)
check(not burstD and math.abs(addedD - capNow * 0.05) < 1e-6 and lostD > 0, "с дроном банка не перегружается и не лопается")
check(waitUntil(departed, 1), "на острове с перегрузкой дрон летит сразу")
check(DataService.get(A).Charge == 0 and A:GetAttribute("JarFill") == 0, "дрон забрал заряд с собой")
local voltsD = DataService.get(A).Volts
EconomyService.addCharge(A, 1, 2)
check(math.abs(DataService.get(A).Charge - 1) < 1e-9, "пока дрон в пути — ловишь в пустую банку")
check(waitUntil(droneSold, 1.5), "дрон сдал груз")
local gotD = DataService.get(A).Volts - voltsD
check(gotD == Economy.sellValue(capNow, capNow, EconomyService.multiplierFor(A)), "груз дрона — по формуле подстанции: " .. tostring(gotD))
check(math.abs(DataService.get(A).Charge - 1) < 1e-9, "новый заряд в банке не тронут")
-- перегруженную с выключенным дроном банку дрон сдаёт с перегрузочной частью
ok, err = request(A, "ToggleDrone", false)
check(ok == true and err == false and DataService.get(A).DroneOn == false, "дрон выключен")
ok = request(A, "ToggleDrone", "yes")
check(ok == false, "ToggleDrone проверяет тип")
DataService.update(A, function(dd)
	dd.Charge = capNow * 1.3
end)
task.wait(0.4)
check(DataService.get(A).Charge == capNow * 1.3, "выключенный дрон не летает")
clearLog()
voltsD = DataService.get(A).Volts
request(A, "ToggleDrone", true)
check(waitUntil(departed, 1), "включили — дрон полетел")
check(waitUntil(droneSold, 1.5), "дрон сдал перегруженную банку")
check(DataService.get(A).Volts - voltsD == Economy.sellValue(capNow * 1.3, capNow, EconomyService.multiplierFor(A)), "перегрузочная часть ×1.5")
request(A, "ToggleDrone", false)
DataService.update(A, function(dd)
	dd.Charge = 0
end)

----------------------------------------------------------------------
-- 9. Общие удары и цепная молния
----------------------------------------------------------------------
print("9. общие удары")
local B = addPlayer("Боря")
check(waitUntil(function()
	return PlayerService.getRoot(B)
end), "второй игрок появился")
DataService.update(B, function(dd)
	dd.Zone = 2
end)
request(B, "Teleport", 2)
task.wait(0.15)
local center2 = Zones.Geo[2].Center
local caughtBy = {}
local sid = StrikeService.spawnShared(2, center2, "rainbow", {
	radius = 18,
	warning = 0.6,
	tag = "rainbow",
	onCatch = function(p, grade)
		table.insert(caughtBy, { p = p, grade = grade })
	end,
})
local function sharedMsg(p)
	for _, m in strikeMsgs(p) do
		if m.Id == sid then
			return m
		end
	end
	return nil
end
check(sharedMsg(A) and sharedMsg(A).Shared == true and sharedMsg(B) ~= nil, "общее кольцо у обоих")
local sm = sharedMsg(A)
if sm then
	moveTo(A, center2 + Vector3.new(3, 0, 0))
	moveTo(B, center2 + Vector3.new(-3, 0, 0))
	waitUntil(function()
		return serverNow() >= sm.Hits[1]
	end, 3)
	fireCatch(A, sid, 1, sm.Hits[1])
	task.wait(0.05)
	fireCatch(B, sid, 1, sm.Hits[1] + 0.03)
	local ra = waitUntil(function()
		return resultFor(A, sid, 1)
	end, 1)
	local rb = waitUntil(function()
		return resultFor(B, sid, 1)
	end, 1)
	check(ra and (ra.Grade == "perfect" or ra.Grade == "burst") and rb and (rb.Grade == "perfect" or rb.Grade == "burst"), "оба поймали общее кольцо")
	check(#caughtBy == 2, "onCatch для каждого")
	check(rb and rb.Chain == nil, "общее кольцо не даёт цепную молнию")
	check(lastMsg("Effect", A, function(a)
		return a[1].Kind == "chain"
	end) == nil and lastMsg("Effect", B, function(a)
		return a[1].Kind == "chain"
	end) == nil, "без Effect chain")
	check(DataService.get(A).Index["2:rainbow"] == true and DataService.get(A).Stats.Rainbows == 1, "радужная в статистике и Молниедексе")
	fireCatch(A, sid, 1, sm.Hits[1])
	task.wait(0.05)
	local count = 0
	for _, args in messages("StrikeResult", A) do
		if args[1].Id == sid then
			count += 1
		end
	end
	check(count == 1, "общее кольцо ловится один раз")
end
-- кольцо шаровой (общее, обычный цвет): не открывает Молниедекс и не идёт в золотую статистику
do
	local golds = DataService.get(B).Stats.Golds
	local hadIndex = DataService.get(B).Index["2:gold"] == true
	local bid = StrikeService.spawnShared(2, center2 + Vector3.new(-3, 0, 0), "gold", { radius = 10, warning = 0.6, tag = "ball" })
	local bm = sharedMsg(B)
	for _, m in strikeMsgs(B) do
		if m.Id == bid then
			bm = m
		end
	end
	if bm and bm.Id == bid then
		moveTo(B, center2 + Vector3.new(-3, 0, 0))
		local r = catchRing(B, bm, 1, 0)
		check(r and (r.Grade == "perfect" or r.Grade == "burst"), "кольцо шаровой поймано")
		local db = DataService.get(B)
		check(db.Stats.Golds == golds and (db.Index["2:gold"] == true) == hadIndex, "шаровая не считается в Молниедекс и золотые")
	else
		check(false, "кольцо шаровой дошло до игрока")
	end
end
-- пришёл на остров, пока общее кольцо ещё сжимается, — тоже видит его
do
	request(B, "Teleport", 1)
	task.wait(0.1)
	local lid = StrikeService.spawnShared(2, center2 + Vector3.new(30, 0, 0), "rainbow", { radius = 5, warning = 1.5, tag = "rainbow" })
	local function seen()
		for _, m in strikeMsgs(B) do
			if m.Id == lid then
				return m
			end
		end
		return nil
	end
	check(seen() == nil, "на другом острове общее кольцо не приходит")
	request(B, "Teleport", 2)
	check(waitUntil(seen, 0.5) ~= nil, "опоздавший на остров получил общее кольцо")
end
-- BoltFX: чужие молнии видит второй игрок
check(waitUntil(function()
	for _, args in messages("BoltFX", B) do
		if args[1].UserId == A.UserId then
			return true
		end
	end
	return false
end, 3), "BoltFX другим в зоне")

----------------------------------------------------------------------
-- 10. Перезапуск
----------------------------------------------------------------------
print("10. перезапуск")
ok, err = request(A, "Rebirth", nil)
check(ok == false, "перезапуск рано: " .. tostring(err))
DataService.update(A, function(dd)
	dd.Zone = 4
	dd.Volts = Economy.rebirthCost(0) + 5
	dd.Shards = 77
	dd.IncomeRate = 500
end)
local petsBefore = #DataService.get(A).Pets
clearLog()
ok, err = request(A, "Rebirth", nil)
local dr = DataService.get(A)
check(ok == true and err == 1, "перезапуск")
check(dr.Volts == 0 and dr.Charge == 0 and dr.Zone == 1 and dr.Upgrades.Rod == 0 and dr.Upgrades.Boots == 0, "сброс прогресса")
check(dr.IncomeRate == 0, "доход в минуту — с нуля")
check(dr.Drone == true, "Тесла-дрон остаётся")
check(dr.Rebirths == 1 and dr.Shards == 77 and #dr.Pets == petsBefore and dr.Index["2:rainbow"], "сохранено нужное")
check(A:GetAttribute("Rebirths") == 1 and A:GetAttribute("Zone") == 1, "атрибуты после перезапуска")
check(A.Character.Humanoid.WalkSpeed == Economy.walkSpeed(0), "скорость сброшена")
check(lastMsg("Banner", "all", function(a)
	return a[1] == "♻ Генератор перезапущен! Аня теперь ×1.5"
end) ~= nil, "баннер перезапуска")

----------------------------------------------------------------------
-- 12. Особые кольца, хуки, модификаторы, крайние случаи
----------------------------------------------------------------------
print("12. особые случаи")
task.wait(1.3) -- ведро запросов наполнилось
local function single(m)
	return m.Kind == "single" and m.Color ~= "black"
end
local function emptyJar(p)
	DataService.update(p, function(dd)
		dd.Charge = 0
	end)
end
local function findKind(p, kind, tries)
	for _ = 1, tries or 10 do
		local m = freshRing(p, serverNow(), function(x)
			return x.Kind == kind
		end)
		if m then
			return m
		end
	end
	return nil
end
DataService.update(A, function(dd)
	dd.Zone = 5
	dd.Upgrades.Jar = 30 -- огромная банка: заряд не упирается в предел
	dd.Charge = 0
end)
ok = request(A, "Teleport", 5)
check(ok == true and A:GetAttribute("Zone") == 5, "телепорт на остров 5")
moveTo(A, Zones.Geo[5].Center)
-- частота колец: упирается в лимит MaxActive (кольцо живёт предупреждение + удары + LatencyGrace)
do
	local from = serverNow()
	task.wait(4)
	local n = 0
	for _, m in strikeMsgs(A) do
		if m.Spawn > from then
			n += 1
		end
	end
	print(string.format("   остров 5: %d колец за 4 с", n))
	check(n >= 4, "кольца на острове 5 идут потоком: " .. n)
end

-- бегущее кольцо
local runner = findKind(A, "runner")
check(runner ~= nil and runner.To ~= nil, "бегущее кольцо с конечной точкой")
if runner then
	local path = Zones.flatDist(runner.Pos, runner.To)
	check(path <= Config.Catch.RunnerSpeed * (runner.Hits[1] - runner.Spawn) + 1e-3, "бегущее не быстрее RunnerSpeed")
	check(Zones.inPlayArea(5, runner.To), "конец пути в игровой зоне")
	local r = catchRing(A, runner, 1, 0)
	check(r and (r.Grade == "perfect" or r.Grade == "burst"), "бегущее поймано в конечной точке: " .. tostring(r and r.Grade))
	check(r and Zones.flatDist(r.Pos, runner.To) < 1e-3, "результат — в конечной точке")
end

-- вилка: три удара
local fork = findKind(A, "fork")
check(fork ~= nil and #fork.Hits == 3, "вилка: три удара")
if fork then
	local res = {}
	for k = 1, 3 do
		res[k] = catchRing(A, fork, k, 0)
	end
	check(res[1] and res[2] and res[3] and res[3].Final and not res[1].Final and not res[2].Final, "вилка: Final на третьем")
end

-- Чёрная молния Перуна (шанс подкручен) + фульгурит через dropHook
local perunCalls = {}
StrikeService.onPerun = function(_, msg)
	table.insert(perunCalls, msg)
end
Config.Events.Perun.Chance = 1
local black = freshRing(A, serverNow(), function(m)
	return m.Color == "black"
end)
Config.Events.Perun.Chance = 1 / 6000
check(black and black.Tag == "perun" and black.Kind == "single" and black.Shown == nil, "Чёрная молния Перуна")
check(black and math.abs((black.Hits[1] - black.Spawn) - Config.Events.Perun.Warning) < 1e-6, "предупреждение Перуна")
check(waitUntil(function()
	return #perunCalls > 0
end, 1), "хук onPerun вызван")
if black then
	StrikeService.dropHook = function(_, color, zone, tagArg)
		check(color == "black" and zone == 5 and tagArg == "perun", "аргументы dropHook")
		return 42
	end
	local r = catchRing(A, black, 1, 0)
	check(r and r.Fulg == 42, "фульгурит из dropHook: " .. tostring(r and r.Fulg))
	check(DataService.get(A).Stats.Blacks >= 1 and DataService.get(A).Index["5:black"], "Blacks и Молниедекс")
	check(waitUntil(function()
		local title = A:GetAttribute("Title")
		return typeof(title) == "string" and string.find(title, "Ловец Перуна", 1, true) ~= nil
	end, 1), "титул «Ловец Перуна» на табличке")
	check(waitUntil(function()
		local rod = A.Character and A.Character:FindFirstChild(PlayerService.RodName)
		return rod ~= nil and rod:FindFirstChild("PerunArc") ~= nil
	end, 1), "дуги Перуна на громоотводе")
end
StrikeService.dropHook = function()
	return { Id = 43 }
end
local fr = freshRing(A, serverNow(), single)
if fr then
	emptyJar(A)
	local r = catchRing(A, fr, 1, 0)
	check(r and r.Fulg == 43, "dropHook вернул запись")
end
StrikeService.dropHook = function()
	error("boom")
end
fr = freshRing(A, serverNow(), single)
if fr then
	emptyJar(A)
	local r = catchRing(A, fr, 1, 0)
	check(r and r.Grade == "perfect" and r.Fulg == nil, "ошибка dropHook не ломает поимку")
end
StrikeService.dropHook = nil
local fr2 = freshRing(A, serverNow(), single)
if fr2 then
	emptyJar(A)
	local r = catchRing(A, fr2, 1, -0.2)
	check(r and r.Grade == "good" and r.Fulg == nil, "фульгурит только при ИДЕАЛЬНО")
end
-- радужная (фульгурит гарантирован) на ХОРОШО: фульгурит приходит в том же результате удара
StrikeService.dropHook = function(_, color, _zone, tagArg)
	return if color == "rainbow" and tagArg == "rainbow" then 44 else nil
end
do
	local rid = StrikeService.spawnShared(5, root(A).Position, "rainbow", { radius = 8, warning = 0.8, tag = "rainbow" })
	local rm = waitUntil(function()
		for _, m in strikeMsgs(A) do
			if m.Id == rid then
				return m
			end
		end
		return nil
	end, 1)
	check(rm ~= nil, "общее радужное кольцо на острове 5")
	if rm then
		emptyJar(A)
		local r = catchRing(A, rm, 1, -0.2)
		check(r and (r.Grade == "good" or r.Grade == "burst") and r.Fulg == 44, "радужная на ХОРОШО — фульгурит в результате: " .. tostring(r and r.Fulg))
	end
end
StrikeService.dropHook = nil

-- переливающееся кольцо
Config.Catch.ShimmerChance = 1
local sh = freshRing(A, serverNow(), function(m)
	return m.Shown ~= nil
end)
Config.Catch.ShimmerChance = 0.05
check(sh and sh.UpgradeAt == Config.Server.ShimmerAt and sh.Color == Strikes.upgradedColor(sh.Shown) and sh.Shown ~= "gold", "переливающееся кольцо")

-- модификаторы событий
StrikeService.setModifiers({
	chargeMult = function()
		return 3
	end,
	rateMult = function()
		return 0 / 0 -- мусор игнорируется
	end,
})
local mr = freshRing(A, serverNow(), single)
if mr then
	emptyJar(A)
	local r = catchRing(A, mr, 1, 0)
	local d5 = DataService.get(A)
	local expect = Economy.catchCharge(5, mr.Color, "perfect", r.Combo, d5.Upgrades.Rod, 3)
	check(r and math.abs(r.Charge - expect) < 1e-6 * expect, "модификатор заряда ×3")
end
StrikeService.setModifiers({})

-- таймаут комбо (в хабе колец нет — сбросить комбо может только таймаут)
Config.Catch.ComboTimeout = 0.6
local cr = freshRing(A, serverNow(), single)
if cr then
	emptyJar(A)
	local r = catchRing(A, cr, 1, 0)
	check(r and r.Combo >= 1, "комбо есть")
	request(A, "Teleport", 0)
	check(waitUntil(function()
		return A:GetAttribute("Combo") == 0
	end, 1.5), "комбо сбросилось по таймауту")
end
Config.Catch.ComboTimeout = 7

-- смена зоны отменяет кольца молча
request(A, "Teleport", 5)
local zr = freshRing(A, serverNow())
if zr then
	request(A, "Teleport", 1)
	task.wait(zr.Hits[#zr.Hits] - serverNow() + Config.Catch.LatencyGrace + 0.2)
	check(resultFor(A, zr.Id, 1) == nil, "кольцо отменено при смене зоны")
end

-- неправдоподобные нажатия
local tr = freshRing(A, serverNow(), single)
if tr then
	moveTo(A, tr.Pos)
	fireCatch(A, tr.Id, 1, serverNow() + 1) -- из будущего
	fireCatch(A, tr.Id, 1, serverNow() - 5) -- слишком старое
	fireCatch(A, tr.Id, 2, tr.Hits[1]) -- нет такого удара
	fireCatch(A, tr.Id, 1.5, tr.Hits[1]) -- не целое
	task.wait(0.05)
	check(resultFor(A, tr.Id, 1) == nil, "неправдоподобные нажатия не оцениваются")
	emptyJar(A)
	local r = catchRing(A, tr, 1, 0)
	check(r and r.Grade == "perfect", "после них честное нажатие работает")
end

-- спам Catch упирается в лимит
task.wait(1.1)
local sp = freshRing(A, serverNow(), single)
if sp then
	moveTo(A, sp.Pos)
	waitUntil(function()
		return serverNow() >= sp.Hits[1]
	end, 3)
	for _ = 1, 30 do
		fireCatch(A, 123456789, 1, serverNow())
	end
	fireCatch(A, sp.Id, 1, sp.Hits[1])
	task.wait(0.05)
	local r = resultFor(A, sp.Id, 1)
	check(r == nil or r.Grade ~= "perfect", "спам Catch упирается в лимит")
end
task.wait(1.1)

-- доход в минуту
Config.Server.IncomeWindow = 0.5
request(A, "Teleport", 1)
DataService.update(A, function(dd)
	dd.IncomeRate = 0
	dd.Charge = 10
end)
moveTo(A, Zones.Geo[1].SellPad)
check(waitUntil(function()
	return DataService.get(A).Charge == 0
end, 1.5), "сдал для дохода")
check(waitUntil(function()
	return DataService.get(A).IncomeRate > 0
end, 2), "доход в минуту обновился")
Config.Server.IncomeWindow = 60

-- множитель: город и друзья
local m1 = EconomyService.multiplierFor(A)
EconomyService.setCityBoostProvider(function()
	return true
end)
check(math.abs(EconomyService.multiplierFor(A) - m1 * 2) < 1e-9, "город сияет ×2")
EconomyService.setCityBoostProvider(function()
	error("x")
end)
check(EconomyService.multiplierFor(A) == m1, "ошибка провайдера города не ломает множитель")
EconomyService.setCityBoostProvider(nil)
A:SetAttribute("FriendCount", 2)
check(math.abs(EconomyService.multiplierFor(A) - m1 * 1.2) < 1e-9, "друзья +20%")
A:SetAttribute("FriendCount", nil)

-- кольцо подстанции у Тесла-башни
request(A, "Teleport", 0)
DataService.update(A, function(dd)
	dd.Charge = 5
end)
moveTo(A, Zones.Hub.Tower + Vector3.new(Zones.HubSellRadius - 1, 0, 0))
check(waitUntil(function()
	return DataService.get(A).Charge == 0
end, 1.5), "сдача у Тесла-башни")

-- персонажа удалили без смерти
local c0 = A.Character
c0.Parent = nil
check(waitUntil(function()
	return A.Character ~= c0 and PlayerService.getRoot(A)
end, 2), "персонаж удалён — появился снова")

-- полная коллекция: обычный фульгурит не выпадает, гарантированный разбивает самый простой ненадетый
do
	local keep = {}
	DataService.update(A, function(dd)
		dd.Fulgs = {}
		dd.EquippedFulgs = {}
		for i = 1, Fulgurite.MaxInventory do
			table.insert(dd.Fulgs, { Id = 5000 + i, Seed = 900 + i, Color = if i <= 3 then "gold" else "blue", Serial = 5000 + i, Zone = 1 })
		end
		dd.EquippedFulgs = { 5001, 5002, 5003 }
		dd.NextFulgId = 5000 + Fulgurite.MaxInventory + 1
		keep = table.clone(dd.EquippedFulgs)
	end)
	clearLog()
	check(FulguriteService.grant(A, "blue", 1, nil) == nil and #DataService.get(A).Fulgs == Fulgurite.MaxInventory, "полная коллекция: обычный не выпал")
	local shardsBefore = DataService.get(A).Shards
	local rec = FulguriteService.grant(A, "rainbow", 1, "rainbow")
	local dd = DataService.get(A)
	check(rec ~= nil and #dd.Fulgs == Fulgurite.MaxInventory and dd.Fulgs[#dd.Fulgs].Color == "rainbow", "радужный нашёл место в полной коллекции")
	check(dd.Shards > shardsBefore, "разбитый дал осколки")
	local equippedKept = true
	for _, id in keep do
		if not PlayerData.findFulg(dd, id) then
			equippedKept = false
		end
	end
	check(equippedKept, "надетые не разбиваются")
	check(lastMsg("Notify", A, function(a)
		return string.find(a[1], "Коллекция полна", 1, true) ~= nil and string.find(a[1], "разбит", 1, true) ~= nil
	end) ~= nil, "игроку сказали, какой разбит")
	DataService.update(A, function(d2)
		d2.Fulgs = {}
		d2.EquippedFulgs = {}
	end)
end

-- Электроград: почти пустая банка очков не даёт
do
	local gs = ReplicatedStorage.GameState
	local before = gs:GetAttribute("CityPoints")
	EconomyService.Sold:Fire(A, 1, Config.City.MinFill * 0.5)
	task.wait(0.05)
	check(gs:GetAttribute("CityPoints") == before, "почти пустая банка не зажигает город")
	EconomyService.Sold:Fire(A, 1, 0.5)
	task.wait(0.05)
	check(math.abs(gs:GetAttribute("CityPoints") - before - 0.5) < 1e-6, "очки города = заполнение банки")
end

-- смена дня: выполненное, но не забранное задание зачисляется само
do
	task.wait(1.1)
	local yesterday = math.floor(os.time() / 86400) - 1
	DataService.update(A, function(dd)
		dd.Quests = { Day = yesterday, List = { { Id = "catch", Target = 60, Progress = 60, Claimed = false }, { Id = "sell", Target = 8, Progress = 2, Claimed = false } } }
	end)
	clearLog()
	local voltsBefore = DataService.get(A).Volts
	local okQ, errQ = request(A, "ClaimQuest", 1)
	check(okQ == false and errQ == "Наступил новый день — задания обновились", "после смены дня — новые задания: " .. tostring(errQ))
	check(DataService.get(A).Quests.Day == yesterday + 1 and DataService.get(A).Volts > voltsBefore, "вчерашняя награда зачислена")
	check(lastMsg("Notify", A, function(a)
		return string.find(a[1], "прошлое задание", 1, true) ~= nil
	end) ~= nil, "тост о вчерашней награде")
end

----------------------------------------------------------------------
-- 11. Смерть и выход
----------------------------------------------------------------------
print("11. смерть и выход")
local oldChar = A.Character
oldChar.Humanoid.Health = 0
oldChar.Humanoid.Died:_fire()
check(waitUntil(function()
	return A.Character ~= oldChar and PlayerService.getRoot(A)
end, 2), "появился заново после смерти")
task.wait(0.1)
check(Zones.zoneAt(root(A).Position) == DataService.get(A).LastZone, "появился в последней зоне")
check(A.Character:FindFirstChild("Jar") and A.Character:FindFirstChild("Громоотвод"), "снова снаряжён")
removePlayer(B)
task.wait(0.2)
check(PlayerService.getZone(B) == 0 and PlayerService.getRoot(B) == nil, "состояние ушедшего очищено")
removePlayer(A)
task.wait(0.3)

-- предупреждения сервера (кроме ожидаемого "без сохранений") — это ошибки
local unexpected = {}
for _, w in warnings do
	local expected = string.find(w, "без сохранений", 1, true) or string.find(w, "DataStore", 1, true) or string.find(w, "dropHook: ", 1, true)
	if not expected then
		table.insert(unexpected, w)
	end
end
check(#unexpected == 0, "нет неожиданных предупреждений: " .. table.concat(unexpected, " | "))

print(string.format("server_sim: %d passed, %d failed, %d skipped waits", passed, failed, skipped))
process.exit(if failed > 0 then 1 else 0)
