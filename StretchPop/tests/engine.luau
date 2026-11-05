-- Мини-мок движка Roblox поверх Lune: сигналы, RemoteEvent, Players, RunService, ContextActionService,
-- CollectionService, PhysicsService, управляемые часы и геометрия Raycast/Spherecast (OBB, фильтры,
-- RespectCanCollide, коллизионные группы). Позволяет прогонять настоящие сценарии игры без Studio.
local roblox = require("@lune/roblox")
local H = require("./harness")

local Instance, Vector3, CFrame, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Enum

local Engine = {}
Engine.game = H.game
Engine.workspace = H.workspace
Engine.time = 1000
Engine.remoteLog = {} :: { any }
Engine.renderSteps = {} :: { [string]: { Priority: number, Fn: (number) -> () } }
Engine.actions = {} :: { [string]: (string, any, any) -> any }
Engine.dynamicParts = {} :: { any }
Engine.kicked = {} :: { [any]: string }
Engine.collisionGroups = {} :: { [string]: boolean }
Engine.fakeChildren = setmetatable({}, { __mode = "k" }) :: { [any]: { [string]: any } }

local game = H.game
local workspace = H.workspace
game.PlaceId = 0
game.JobId = ""

-- ── Часы ───────────────────────────────────────────────────────────────────
local fakeOs = setmetatable({
	clock = function()
		return Engine.time
	end,
	time = function()
		return math.floor(Engine.time)
	end,
}, { __index = os })

-- ── Сигналы ────────────────────────────────────────────────────────────────
local function newSignal()
	local signal = { _handlers = {} }
	function signal:Connect(fn)
		local connection = { Connected = true }
		function connection:Disconnect()
			connection.Connected = false
		end
		table.insert(signal._handlers, { Fn = fn, Connection = connection })
		return connection
	end
	function signal:Once(fn)
		local connection
		connection = signal:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal:Fire(...)
		for _, handler in table.clone(signal._handlers) do
			if handler.Connection.Connected then
				handler.Fn(...)
			end
		end
	end
	return signal
end
Engine.newSignal = newSignal

local signals = setmetatable({}, { __mode = "k" })
local function signalFor(instance: any, name: string)
	local bag = signals[instance]
	if bag == nil then
		bag = {}
		signals[instance] = bag
	end
	local signal = bag[name]
	if signal == nil then
		signal = newSignal()
		bag[name] = signal
	end
	return signal
end
Engine.signalFor = signalFor

for _, name in { "DescendantAdded", "DescendantRemoving", "ChildAdded", "ChildRemoved", "AttributeChanged", "AncestryChanged" } do
	roblox.implementProperty("Instance", name, function(self)
		return signalFor(self, name)
	end)
end
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, attribute)
	return signalFor(self, "Attr:" .. attribute)
end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name, _timeout)
	local fakes = Engine.fakeChildren[self]
	if fakes and fakes[name] then
		return fakes[name]
	end
	return self:FindFirstChild(name)
end)

-- ── Сеть ───────────────────────────────────────────────────────────────────
roblox.implementProperty("RemoteEvent", "OnServerEvent", function(self)
	return signalFor(self, "OnServerEvent")
end)
roblox.implementProperty("RemoteEvent", "OnClientEvent", function(self)
	return signalFor(self, "OnClientEvent")
end)
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	table.insert(Engine.remoteLog, { Remote = self.Name, Kind = "FireServer", Args = table.pack(...), Time = Engine.time })
end)
roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
	table.insert(Engine.remoteLog, { Remote = self.Name, Kind = "FireClient", Player = player, Args = table.pack(...), Time = Engine.time })
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
	table.insert(Engine.remoteLog, { Remote = self.Name, Kind = "FireAllClients", Args = table.pack(...), Time = Engine.time })
end)

function Engine.findLog(remote: string, predicate: ((any) -> boolean)?): any
	for index = #Engine.remoteLog, 1, -1 do
		local entry = Engine.remoteLog[index]
		if entry.Remote == remote and (predicate == nil or predicate(entry)) then
			return entry
		end
	end
	return nil
end

function Engine.remote(name: string): any
	return game:GetService("ReplicatedStorage").StretchPopNet:FindFirstChild(name)
end

-- ── Игроки ─────────────────────────────────────────────────────────────────
roblox.implementProperty("Players", "PlayerAdded", function(self)
	return signalFor(self, "PlayerAdded")
end)
roblox.implementProperty("Players", "PlayerRemoving", function(self)
	return signalFor(self, "PlayerRemoving")
end)
roblox.implementMethod("Players", "GetPlayers", function(self)
	local list = {}
	for _, child in self:GetChildren() do
		if child:IsA("Player") then
			table.insert(list, child)
		end
	end
	return list
end)
roblox.implementProperty("Player", "CharacterAdded", function(self)
	return signalFor(self, "CharacterAdded")
end)
roblox.implementProperty("Player", "CharacterRemoving", function(self)
	return signalFor(self, "CharacterRemoving")
end)
roblox.implementMethod("Player", "Kick", function(self, message)
	Engine.kicked[self] = message or ""
end)

function Engine.initDefaults(instance: any)
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = 0
		instance.AssemblyLinearVelocity = Vector3.zero
		instance.AssemblyAngularVelocity = Vector3.zero
		instance.Position = instance.CFrame.Position
	elseif instance:IsA("Decal") then
		instance.LocalTransparencyModifier = 0
	end
end

-- Обёртка Instance.new для модулей: выставляет свойства, у которых в Lune нет дефолтов
local InstanceWrapper = setmetatable({
	new = function(className: string, parent: any?)
		local instance = Instance.new(className)
		Engine.initDefaults(instance)
		if parent then
			instance.Parent = parent
		end
		return instance
	end,
}, { __index = Instance })
Engine.Instance = InstanceWrapper

function Engine.newHumanoid(): any
	local humanoid = {
		ClassName = "Humanoid",
		Name = "Humanoid",
		Health = 100,
		HipHeight = 2,
		RigType = Enum.HumanoidRigType.R15,
		AutoRotate = true,
		FloorMaterial = Enum.Material.Plastic,
		MoveDirection = Vector3.zero,
		State = Enum.HumanoidStateType.Running,
		StateLog = {},
		Died = newSignal(),
	}
	function humanoid:IsA(className: string): boolean
		return className == "Humanoid" or className == "Instance"
	end
	function humanoid:ChangeState(state)
		humanoid.State = state
		table.insert(humanoid.StateLog, state)
	end
	function humanoid:GetState()
		return humanoid.State
	end
	function humanoid:FindFirstChildOfClass(_className: string)
		return nil
	end
	return humanoid
end

function Engine.newPart(name: string, size: any, cframe: any, parent: any): any
	local part = InstanceWrapper.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Position = cframe.Position
	part.Anchored = true
	part.Parent = parent
	return part
end

function Engine.buildCharacter(player: any, cframe: any): (any, any, any)
	local character = Instance.new("Model")
	character.Name = player.Name
	local root = Engine.newPart("HumanoidRootPart", Vector3.new(2, 2, 1), cframe, character)
	root.Anchored = false
	Engine.newPart("UpperTorso", Vector3.new(2, 1.6, 1), cframe * CFrame.new(0, 0.8, 0), character)
	for _, name in { "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "Head" } do
		Engine.newPart(name, Vector3.new(1, 1, 1), cframe, character)
	end
	local humanoid = Engine.newHumanoid()
	Engine.fakeChildren[character] = { Humanoid = humanoid }
	table.insert(Engine.dynamicParts, root)
	character.Parent = workspace
	player.Character = character
	return character, root, humanoid
end

roblox.implementMethod("Player", "LoadCharacter", function(self)
	local character = Engine.buildCharacter(self, CFrame.new(0, 10, 14))
	signalFor(self, "CharacterAdded"):Fire(character)
end)

roblox.implementMethod("Model", "PivotTo", function(self, target)
	local root = self:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = target
		root.Position = target.Position
	end
end)

roblox.implementMethod("DataModel", "BindToClose", function(_self, fn)
	Engine.closeHandler = fn
end)

-- ── Сервисы ────────────────────────────────────────────────────────────────
for _, name in { "Heartbeat", "RenderStepped", "Stepped" } do
	roblox.implementProperty("RunService", name, function(self)
		return signalFor(self, name)
	end)
end
roblox.implementMethod("RunService", "BindToRenderStep", function(_self, name, priority, fn)
	Engine.renderSteps[name] = { Priority = priority, Fn = fn }
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_self, name)
	Engine.renderSteps[name] = nil
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)

roblox.implementMethod("PhysicsService", "RegisterCollisionGroup", function(_self, name)
	Engine.collisionGroups[name] = true
end)
roblox.implementMethod("PhysicsService", "IsCollisionGroupRegistered", function(_self, name)
	return Engine.collisionGroups[name] == true
end)
roblox.implementMethod("PhysicsService", "CollisionGroupSetCollidable", function() end)

roblox.implementMethod("ContextActionService", "BindActionAtPriority", function(_self, name, fn)
	Engine.actions[name] = fn
end)
roblox.implementMethod("ContextActionService", "UnbindAction", function(_self, name)
	Engine.actions[name] = nil
end)

roblox.implementMethod("CollectionService", "GetTagged", function(_self, tag)
	local list = {}
	for _, descendant in workspace:GetDescendants() do
		if descendant:HasTag(tag) then
			table.insert(list, descendant)
		end
	end
	return list
end)
roblox.implementMethod("CollectionService", "GetInstanceAddedSignal", function(self, tag)
	return signalFor(self, "Added:" .. tag)
end)
roblox.implementMethod("CollectionService", "GetInstanceRemovedSignal", function(self, tag)
	return signalFor(self, "Removed:" .. tag)
end)

roblox.implementMethod("ParticleEmitter", "Emit", function(self, count)
	Engine.emitted = (Engine.emitted or 0) + (count or 1)
end)

roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return Engine.time
end)

for _, name in { "InputBegan", "InputChanged", "InputEnded" } do
	roblox.implementProperty("UserInputService", name, function(self)
		return signalFor(self, name)
	end)
end
roblox.implementMethod("UserInputService", "GetMouseDelta", function()
	return roblox.Vector2.new(12, -4)
end)
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function()
	return nil
end)
roblox.implementMethod("TweenService", "Create", function(_self, instance, _info, goals)
	return {
		Play = function()
			for key, value in goals do
				instance[key] = value
			end
		end,
	}
end)

-- ── Геометрия запросов ─────────────────────────────────────────────────────
local RaycastParams = {}
function RaycastParams.new()
	local params = {
		FilterType = Enum.RaycastFilterType.Exclude,
		FilterDescendantsInstances = {},
		IgnoreWater = false,
		RespectCanCollide = false,
		CollisionGroup = "Default",
	}
	function params:AddToFilter(value)
		table.insert(params.FilterDescendantsInstances, value)
	end
	return params
end
Engine.RaycastParams = RaycastParams

local function excluded(part: any, params: any): boolean
	for _, instance in params.FilterDescendantsInstances do
		if part == instance or part:IsDescendantOf(instance) then
			return true
		end
	end
	return false
end

local NONCOLLIDING = { StretchCharacters = true, StretchDebris = true }

-- Ray против OBB, раздутого на radius (приближение суммы Минковского сфера+бокс)
local function castBox(origin: any, direction: any, part: any, radius: number): (number?, any?)
	local cframe = part.CFrame
	local o = cframe:PointToObjectSpace(origin)
	local d = cframe:VectorToObjectSpace(direction)
	local half = part.Size * 0.5 + Vector3.one * radius
	local tMin, tMax = -math.huge, math.huge
	local hitAxis, hitSign = 0, 0
	local originAxes = { o.X, o.Y, o.Z }
	local ds = { d.X, d.Y, d.Z }
	local hs = { half.X, half.Y, half.Z }
	for axis = 1, 3 do
		if math.abs(ds[axis]) < 1e-9 then
			if originAxes[axis] < -hs[axis] or originAxes[axis] > hs[axis] then
				return nil, nil
			end
		else
			local t1 = (-hs[axis] - originAxes[axis]) / ds[axis]
			local t2 = (hs[axis] - originAxes[axis]) / ds[axis]
			local sign = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				sign = 1
			end
			if t1 > tMin then
				tMin = t1
				hitAxis = axis
				hitSign = sign
			end
			if t2 < tMax then
				tMax = t2
			end
			if tMin > tMax then
				return nil, nil
			end
		end
	end
	if tMin < 0 or tMin > 1 or hitAxis == 0 then
		return nil, nil -- старт внутри или промах (как у шейпкастов Roblox)
	end
	local localNormal = Vector3.new(
		if hitAxis == 1 then hitSign else 0,
		if hitAxis == 2 then hitSign else 0,
		if hitAxis == 3 then hitSign else 0
	)
	return tMin, cframe:VectorToWorldSpace(localNormal)
end

function Engine.cast(origin: any, direction: any, radius: number, params: any): any
	if direction.Magnitude < 1e-9 then
		return nil
	end
	local bestT, bestNormal, bestPart = math.huge, nil, nil
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CanQuery and not (params.RespectCanCollide and not descendant.CanCollide) then
			if not (NONCOLLIDING[params.CollisionGroup] and NONCOLLIDING[descendant.CollisionGroup]) and not excluded(descendant, params) then
				local t, normal = castBox(origin, direction, descendant, radius)
				if t and t < bestT then
					bestT, bestNormal, bestPart = t, normal, descendant
				end
			end
		end
	end
	if bestPart == nil then
		return nil
	end
	local center = origin + direction * bestT
	return {
		Instance = bestPart,
		Normal = bestNormal,
		Distance = direction.Magnitude * bestT,
		Position = center - bestNormal * radius,
		Material = bestPart.Material,
	}
end

roblox.implementMethod("Workspace", "Raycast", function(_self, origin, direction, params)
	return Engine.cast(origin, direction, 0, params or RaycastParams.new())
end)
roblox.implementMethod("Workspace", "Spherecast", function(_self, origin, radius, direction, params)
	return Engine.cast(origin, direction, radius, params or RaycastParams.new())
end)

-- ── Окружение модулей ──────────────────────────────────────────────────────
H.envExtras.os = fakeOs
H.envExtras.Instance = InstanceWrapper
H.envExtras.RaycastParams = RaycastParams
H.envExtras.TweenInfo = {
	new = function(...)
		return table.pack(...)
	end,
}
H.envExtras.UserSettings = function()
	return {
		GetService = function()
			return { MouseSensitivity = 1 }
		end,
	}
end

-- ── Шаги симуляции ─────────────────────────────────────────────────────────
local function syncDynamic()
	for _, part in Engine.dynamicParts do
		part.Position = part.CFrame.Position
	end
end
Engine.syncDynamic = syncDynamic

function Engine.serverStep(dt: number)
	Engine.time += dt
	syncDynamic()
	signalFor(game:GetService("RunService"), "Heartbeat"):Fire(dt)
end

function Engine.clientStep(dt: number)
	Engine.time += dt
	syncDynamic()
	signalFor(game:GetService("RunService"), "RenderStepped"):Fire(dt)
	local ordered = {}
	for _, entry in Engine.renderSteps do
		table.insert(ordered, entry)
	end
	table.sort(ordered, function(a, b)
		return a.Priority < b.Priority
	end)
	for _, entry in ordered do
		entry.Fn(dt)
	end
	syncDynamic()
end

Engine.H = H
return Engine
