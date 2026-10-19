--!nocheck
-- Boot sequence and per-frame engine work:
--  * load the built place, convert it, index the map for raycasts, run server Scripts;
--  * players join (Player, PlayerGui, Backpack, PlayerScripts copy + client realm running LocalScripts) and leave;
--  * every frame: humanoid MoveTo kinematics, client cameras, RenderStep bindings/PreRender/RenderStepped,
--    Stepped/PreSimulation, Heartbeat/PostSimulation, ProximityPrompt shown/hidden.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Engine = require("./engine")
local Classes = require("./classes")
local Sched = require("./sched")
local Report = require("./report")
local World = require("./world")
local Services = require("./services")
local Realm = require("./realm")

local Vector3, Vector2, CFrame, Enum = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Enum
local DATA = Engine.DATA
local readProp = Engine.readProp
local setProp = Engine.setProp

local Runtime = {}
Runtime.clients = {} -- list of client realms (join order)

local function svc(name)
	return Services.getService(name)
end

function Runtime.boot(placePath)
	local t0 = os.clock()
	local luneGame = roblox.deserializePlace(fs.readFile(placePath))
	local gameU, count = Realm.convertPlace(luneGame)
	Report.logLine(string.format("converted %d instances in %.2fs", count, os.clock() - t0))
	World.workspace = svc("Workspace")
	World.workspaceD = DATA[World.workspace]
	World.starterPlayer = svc("StarterPlayer")
	-- Terrain and the server camera exist in every place
	local terrain = World.new("Terrain", { Name = "Terrain" }, World.workspace, 0)
	World.terrain = terrain
	local cam = World.new("Camera", { Name = "Camera", CFrame = CFrame.new(0, 20, 20), FieldOfView = 70 }, World.workspace, 0)
	World.serverCamera = cam
	for _, c in Engine.descendantsOf(World.workspaceD, nil) do
		local cd = DATA[c]
		if cd.class == "SpawnLocation" then
			World.spawnLocation = c
		end
	end
	-- services that are always present
	for _, name in { "Players", "RunService", "TweenService", "UserInputService", "ContextActionService", "GuiService", "StarterGui", "SoundService", "ContentProvider", "HttpService", "DataStoreService", "Debris", "CollectionService", "ProximityPromptService", "TextService", "MarketplaceService", "Lighting", "ReplicatedFirst", "ServerStorage", "StarterPack", "Teams", "Chat", "PhysicsService" } do
		svc(name)
	end
	setProp(DATA[svc("Players")], "CharacterAutoLoads", true, nil)
	-- server-only containers
	for _, name in { "ServerScriptService", "ServerStorage" } do
		local u = svc(name)
		Engine.forSubtree(DATA[u], function(x)
			x.serverOnly = true
		end)
	end
	-- map raycast index
	local map = Engine.findChild(World.workspaceD, "Map", nil)
	if map then
		World.indexStatic(DATA[map])
	end
	Realm.makeGlobals(World.server)
	Realm.makeGlobals(World.harness)
	table.insert(Sched.frameHooks, Runtime.frame)
	Report.logLine(string.format("boot done in %.2fs", os.clock() - t0))
end

-- Pre-require a module in a realm (used to patch Config before the game boots)
function Runtime.requireIn(realm, inst)
	local result
	local co = Sched.create(realm, function()
		result = Realm.require(realm, inst)
	end)
	Sched.resume(co)
	Sched.flush()
	return result
end

-- Instances alive in the DataModel by owner realm and class (leak detection)
function Runtime.census()
	local out = {}
	Engine.forSubtree(World.gameD, function(x)
		local key = (if x.owner > 0 then "client" .. x.owner else "server") .. ":" .. x.class
		out[key] = (out[key] or 0) + 1
	end)
	return out
end

function Runtime.find(path, realm)
	local cur = World.gameD
	for part in string.gmatch(path, "[^%.]+") do
		local c = Engine.findChild(cur, part, realm)
		if not c then
			return nil
		end
		cur = DATA[c]
	end
	return cur.proxy
end

function Runtime.startServer()
	local list = {}
	for _, root in { svc("ServerScriptService"), World.workspace } do
		for _, c in Engine.descendantsOf(DATA[root], nil) do
			local cd = DATA[c]
			if cd.class == "Script" and readProp(cd, "Disabled", nil) ~= true and readProp(cd, "Enabled", nil) ~= false then
				local rc = readProp(cd, "RunContext", nil)
				if rc == nil or rc == Enum.RunContext.Legacy or rc == Enum.RunContext.Server then
					table.insert(list, c)
				end
			end
		end
	end
	for _, s in list do
		Realm.runScript(World.server, s)
	end
	Sched.flush()
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------
local nextClientId = 1

function Runtime.addPlayer(opts)
	local userId = opts.userId
	local name = opts.name
	local players = svc("Players")
	local pu, pd = World.new("Player", { Name = name, UserId = userId, DisplayName = opts.displayName or name }, nil, 0)
	pd.props.Character = nil
	pd.locale = opts.locale or "en-us" -- Player.LocaleId, and LocalizationService.RobloxLocaleId on its client
	World.new("Backpack", { Name = "Backpack" }, pu, 0)
	World.new("PlayerGui", { Name = "PlayerGui" }, pu, 0)
	World.new("StarterGear", { Name = "StarterGear" }, pu, 0)
	-- client realm
	local id = nextClientId
	nextClientId += 1
	local realm = World.newRealm(id, "client", "client " .. id .. " (" .. name .. ")")
	realm.player = pu
	realm.playerD = pd
	realm.viewport = opts.viewport or Vector2.new(1366, 768)
	realm.touch = opts.touch == true
	realm.preferredInput = if realm.touch then Enum.PreferredInput.Touch else Enum.PreferredInput.KeyboardAndMouse
	realm.lastInput = if realm.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseMovement
	realm.mouse = realm.viewport / 2
	World.playerRealm[pd] = realm
	table.insert(World.players, pd)
	table.insert(Runtime.clients, realm)
	Realm.makeGlobals(realm)
	-- client camera (local to the client)
	local cam, camD = World.new("Camera", { Name = "Camera", CFrame = CFrame.new(0, 30, 30), FieldOfView = 70, CameraType = Enum.CameraType.Custom }, nil, id)
	camD.viewport = realm.viewport
	realm.camera = cam
	Engine.setParent(camD, World.workspace, realm)
	-- PlayerScripts: copy of StarterPlayerScripts, local to the client
	local ps, psd = World.new("PlayerScripts", { Name = "PlayerScripts" }, nil, id)
	local sps = Runtime.find("StarterPlayer.StarterPlayerScripts", nil)
	if sps then
		for _, c in DATA[sps].children do
			local clone = Engine.clone(DATA[c], realm)
			if clone then
				local cd = DATA[clone]
				cd.parent = ps
				table.insert(psd.children, clone)
			end
		end
	end
	psd.parent = pu
	table.insert(pd.children, ps)
	-- join: parent to Players (PlayerAdded on server and every client)
	Sched.spawn(World.server, function()
		Engine.setParent(pd, players, World.server)
		Engine.fireEvent(DATA[players], "PlayerAdded", nil, pu)
	end)
	Sched.flush()
	-- LocalScripts start on the client
	Sched.at(Sched.now + (opts.clientDelay or 0.1), function()
		if realm.dead then
			return
		end
		for _, c in Engine.descendantsOf(psd, realm) do
			local cd = DATA[c]
			if cd.class == "LocalScript" and readProp(cd, "Disabled", realm) ~= true and readProp(cd, "Enabled", realm) ~= false then
				Realm.runScript(realm, c)
			end
		end
	end)
	return realm
end

function Runtime.removePlayer(pd, reason)
	local realm = World.playerRealm[pd]
	if not pd.parent then
		return
	end
	local players = svc("Players")
	Sched.spawn(World.server, function()
		Engine.fireEvent(DATA[players], "PlayerRemoving", nil, pd.proxy, Enum.PlayerExitReason.Unknown)
	end)
	Sched.flush()
	if realm then
		realm.dead = true
	end
	-- character and player leave the world right after PlayerRemoving handlers start
	Sched.spawn(World.server, function()
		local char = pd.props.Character
		if char then
			Engine.destroy(DATA[char], World.server)
		end
		Engine.setParent(pd, nil, World.server)
	end)
	Sched.flush()
	World.playerRealm[pd] = nil
	local i = table.find(World.players, pd)
	if i then
		table.remove(World.players, i)
	end
	local j = table.find(Runtime.clients, realm)
	if j then
		table.remove(Runtime.clients, j)
	end
end
Services.removePlayer = Runtime.removePlayer

-- Device changes: screen rotation / window resize and input switching (fire the change events the UI listens to)
function Runtime.setViewport(realm, size)
	realm.viewport = size
	local camD = realm.camera and DATA[realm.camera]
	if camD then
		camD.viewport = size
		Engine.fireChanged(camD, "ViewportSize", realm)
	end
	local gui = Engine.findChild(realm.playerD, "PlayerGui", realm)
	if gui then
		Engine.forSubtree(DATA[gui], function(x)
			if x.sigs and (x.sigs["prop:AbsoluteSize"] or x.sigs["prop:AbsolutePosition"] or x.sigs.Changed) and x.cls.isA.GuiBase2d then
				Engine.fireChanged(x, "AbsoluteSize", realm)
				Engine.fireChanged(x, "AbsolutePosition", realm)
			end
		end)
	end
end

function Runtime.setPreferredInput(realm, touch)
	realm.touch = touch
	realm.preferredInput = if touch then Enum.PreferredInput.Touch else Enum.PreferredInput.KeyboardAndMouse
	realm.lastInput = if touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseMovement
	local uis = DATA[svc("UserInputService")]
	Engine.fireChanged(uis, "PreferredInput", realm)
	Engine.fireChanged(uis, "TouchEnabled", realm)
	Engine.fireEvent(uis, "LastInputTypeChanged", realm, realm.lastInput)
end

-- Server shutdown: run BindToClose callbacks (each in its own thread) and wait up to 30 s
function Runtime.shutdown()
	local threads = {}
	for _, b in Services.bindToClose do
		table.insert(threads, Sched.spawn(b.realm or World.server, b.fn))
	end
	Sched.flush()
	local deadline = Sched.now + 30
	while Sched.now < deadline do
		local busy = false
		for _, co in threads do
			if coroutine.status(co) ~= "dead" then
				busy = true
			end
		end
		if not busy then
			break
		end
		Sched.step()
	end
	return Sched.now
end

----------------------------------------------------------------------
-- Per-frame engine work
----------------------------------------------------------------------
local function charRoot(pd, realm)
	local char = pd.props.Character
	if not char then
		return nil, nil
	end
	local cd = DATA[char]
	local root = Engine.findChild(cd, "HumanoidRootPart", realm)
	local hum = Engine.findChild(cd, "Humanoid", realm)
	return root and DATA[root], hum and DATA[hum]
end
Runtime.charRoot = charRoot

local function stepHumanoids(dt)
	for _, pd in World.players do
		local rootD, humD = charRoot(pd, nil)
		if rootD and humD and not humD.dead then
			local target = humD.moveTarget
			if target then
				local cf = readProp(rootD, "CFrame", nil)
				local pos = cf.Position
				local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
				local dist = flat.Magnitude
				local speed = readProp(humD, "WalkSpeed", nil) or 16
				if dist < 0.5 or Sched.now - (humD.moveStarted or 0) > 8 then
					humD.moveTarget = nil
					Engine.setRaw(humD, "MoveDirection", Vector3.zero)
					Engine.fireEvent(humD, "MoveToFinished", nil, dist < 0.5)
				else
					local step = math.min(dist, speed * dt)
					local dir = flat.Unit
					local np = pos + dir * step
					-- follow the ground under the character
					local hit = World.raycast(np + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), nil, nil)
					if hit and DATA[hit.Instance] and not Engine.isDescendantOf(DATA[hit.Instance], DATA[pd.props.Character]) then
						np = Vector3.new(np.X, hit.Position.Y + 3, np.Z)
					end
					Classes.setPartCFrame(rootD, CFrame.lookAt(np, np + dir), World.server)
					Engine.setRaw(humD, "MoveDirection", dir)
				end
			elseif humD.props.MoveDirection ~= Vector3.zero and humD.props.MoveDirection ~= nil and not humD.botMoving then
				Engine.setRaw(humD, "MoveDirection", Vector3.zero)
			end
		end
	end
end

local function stepCameras()
	for _, realm in Runtime.clients do
		if not realm.dead and realm.camera then
			local camD = DATA[realm.camera]
			local ct = readProp(camD, "CameraType", realm)
			if ct == Enum.CameraType.Custom or ct == nil then
				local rootD = charRoot(realm.playerD, realm)
				if rootD then
					local p = readProp(rootD, "CFrame", realm).Position
					local eye = p + Vector3.new(0, 9, 16)
					camD.props.CFrame = CFrame.lookAt(eye, p + Vector3.new(0, 2, 0))
					camD.props.Focus = CFrame.new(p)
				end
			end
		end
	end
end

local promptTimer = 0
local function stepPrompts(dt)
	promptTimer += dt
	if promptTimer < 0.2 then
		return
	end
	promptTimer = 0
	local pps = Services.services.ProximityPromptService
	if not pps then
		return
	end
	local ppsD = DATA[pps]
	local prompts = {}
	Engine.forSubtree(World.workspaceD, function(x)
		if x.class == "ProximityPrompt" then
			table.insert(prompts, x)
		end
	end)
	for _, realm in Runtime.clients do
		if not realm.dead then
			realm.shownPrompts = realm.shownPrompts or {}
			local rootD = charRoot(realm.playerD, realm)
			local pos = rootD and readProp(rootD, "CFrame", realm).Position
			for _, pr in prompts do
				local visible = false
				if pos and Engine.visibleTo(pr, realm) and readProp(pr, "Enabled", realm) ~= false then
					local par = pr.parent and DATA[pr.parent]
					local ppos = nil
					if par and par.cls.isA.BasePart then
						ppos = readProp(par, "CFrame", realm).Position
					elseif par and par.class == "Attachment" then
						ppos = Classes.absPos and (readProp(par, "WorldPosition", realm) or nil)
						if not ppos then
							local g = par.cls.getters.WorldPosition
							ppos = g and g(par, realm)
						end
					elseif par and par.class == "Model" then
						ppos = Classes.modelPivot(par, realm).Position
					end
					if ppos then
						local dist = (ppos - pos).Magnitude
						visible = dist <= (readProp(pr, "MaxActivationDistance", realm) or 10)
					end
				end
				local was = realm.shownPrompts[pr] == true
				if visible and not was then
					realm.shownPrompts[pr] = true
					Engine.fire(Engine.getSignal(ppsD, "PromptShown"), realm, pr.proxy, Enum.ProximityPromptInputType.Keyboard)
					Engine.fire(Engine.getSignal(pr, "PromptShown"), realm, Enum.ProximityPromptInputType.Keyboard)
				elseif not visible and was then
					realm.shownPrompts[pr] = nil
					Engine.fire(Engine.getSignal(ppsD, "PromptHidden"), realm, pr.proxy)
					Engine.fire(Engine.getSignal(pr, "PromptHidden"), realm)
				end
			end
		end
	end
end

-- Trigger a prompt as player (what pressing E does): server Triggered + service PromptTriggered
function Runtime.triggerPrompt(realm, promptD)
	local pps = DATA[svc("ProximityPromptService")]
	local player = realm.player
	-- the triggering client gets the events locally right away
	Engine.fire(Engine.getSignal(promptD, "Triggered"), realm, player)
	Engine.fire(Engine.getSignal(pps, "PromptTriggered"), realm, promptD.proxy, player)
	Engine.fire(Engine.getSignal(promptD, "TriggerEnded"), realm, player)
	Engine.fire(Engine.getSignal(pps, "PromptTriggerEnded"), realm, promptD.proxy, player)
	Sched.at(Sched.now + World.latency, function()
		Engine.fire(Engine.getSignal(promptD, "Triggered"), World.server, player)
		Engine.fire(Engine.getSignal(pps, "PromptTriggered"), World.server, promptD.proxy, player)
		Engine.fire(Engine.getSignal(promptD, "TriggerEnded"), World.server, player)
		Engine.fire(Engine.getSignal(pps, "PromptTriggerEnded"), World.server, promptD.proxy, player)
	end)
end

function Runtime.frame(dt)
	stepHumanoids(dt)
	Sched.flush()
	stepCameras()
	local rs = DATA[svc("RunService")]
	-- client render step
	for _, realm in Runtime.clients do
		if not realm.dead then
			for _, b in table.clone(realm.renderBindings) do
				local co = Sched.create(realm, b.fn)
				Sched.resume(co, dt)
			end
		end
	end
	Engine.fire(Services.rsSignal(rs, "PreRender", true), nil, dt)
	Engine.fire(Services.rsSignal(rs, "RenderStepped", true), nil, dt)
	Sched.flush()
	Engine.fire(Services.rsSignal(rs, "PreAnimation", false), nil, dt)
	Engine.fire(Services.rsSignal(rs, "Stepped", false), nil, Sched.now, dt)
	Engine.fire(Services.rsSignal(rs, "PreSimulation", false), nil, dt)
	Sched.flush()
	Engine.fire(Services.rsSignal(rs, "Heartbeat", false), nil, dt)
	Engine.fire(Services.rsSignal(rs, "PostSimulation", false), nil, dt)
	Sched.flush()
	stepPrompts(dt)
end

return Runtime
