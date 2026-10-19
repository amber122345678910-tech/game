--!nocheck
-- Services and engine-driven classes: DataModel, Workspace, Players/Player (characters), Humanoid,
-- RunService, TweenService, DataStoreService, HttpService, input services, GUI services, misc stubs.
-- Anything a service declares (ClassDB) but the sim does not implement raises "not emulated: X".
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Engine = require("./engine")
local Classes = require("./classes")
local Sched = require("./sched")
local Report = require("./report")
local DT = require("./datatypes")
local World = require("./world")

local Vector3, Vector2, CFrame, Color3, UDim2, Enum = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Color3, roblox.UDim2, roblox.Enum
local DATA = Engine.DATA
local define = Engine.define
local readProp = Engine.readProp
local setProp = Engine.setProp
local throw = Engine.throw
local typeof = Engine.typeof

local Services = {}

local function self(u, n)
	return Engine.self(u, n)
end
local function R()
	return Sched.CUR
end
local function onlyServer(what)
	local r = Sched.CUR
	if r and r.kind == "client" then
		throw("runtime", what .. " can only be called from the server")
	end
end
local function onlyClient(what)
	local r = Sched.CUR
	if r and r.kind == "server" then
		throw("runtime", what .. " can only be called from a LocalScript (client)")
	end
end
local function serverTime()
	return Sched.EPOCH + Sched.now
end
Services.serverTime = serverTime

----------------------------------------------------------------------
-- DataModel
----------------------------------------------------------------------
Services.bindToClose = {}

define("ServiceProvider", {
	methods = {
		GetService = function(u, name)
			local d = self(u, "GetService")
			if type(name) ~= "string" then
				throw("runtime", "Argument 1 missing or nil")
			end
			return Services.getService(name)
		end,
		FindService = function(u, name)
			self(u, "FindService")
			return Services.services[name]
		end,
	},
})
define("DataModel", {
	getters = {
		Workspace = function()
			return World.workspace
		end,
		PlaceId = function()
			return 0
		end,
		GameId = function()
			return 0
		end,
		JobId = function()
			return "00000000-sim-job"
		end,
		CreatorId = function()
			return 0
		end,
		PrivateServerId = function()
			return ""
		end,
		PrivateServerOwnerId = function()
			return 0
		end,
	},
	methods = {
		BindToClose = function(u, fn)
			self(u, "BindToClose")
			onlyServer("BindToClose")
			if type(fn) ~= "function" then
				throw("runtime", "BindToClose expects a function")
			end
			table.insert(Services.bindToClose, { fn = fn, realm = Sched.CUR })
		end,
		IsLoaded = function()
			return true
		end,
		GetEngineFeature = function()
			return true
		end,
		GetFastFlag = function()
			return false
		end,
		DefineFastFlag = function(_, _, v)
			return v
		end,
		GetJobsInfo = function()
			return {}
		end,
	},
})

----------------------------------------------------------------------
-- Service registry
----------------------------------------------------------------------
Services.services = {}

function Services.registerService(name, u)
	Services.services[name] = u
	DATA[u].isService = true
end

function Services.getService(name)
	local s = Services.services[name]
	if s then
		return s
	end
	local cdb = Engine.ClassDB
	if not cdb.exists(name) then
		throw("runtime", "'" .. tostring(name) .. "' is not a valid Service name")
	end
	local tags = cdb.tags(name)
	if not tags.Service and name ~= "UserGameSettings" then
		throw("runtime", "'" .. tostring(name) .. "' is not a valid Service name")
	end
	local u = World.new(name, { Name = name }, World.game, 0)
	Services.registerService(name, u)
	return u
end

----------------------------------------------------------------------
-- Workspace
----------------------------------------------------------------------
define("Workspace", {
	getters = {
		CurrentCamera = function(d, realm)
			if realm and realm.camera then
				return realm.camera
			end
			return World.serverCamera
		end,
		DistributedGameTime = function()
			return Sched.now
		end,
		Terrain = function()
			return World.terrain
		end,
	},
	setters = {
		CurrentCamera = function(d, v, realm)
			if realm and realm.kind == "client" then
				realm.camera = v
			else
				World.serverCamera = v
			end
		end,
	},
	methods = {
		GetServerTimeNow = function(u)
			self(u, "GetServerTimeNow")
			return serverTime()
		end,
		Raycast = function(u, origin, dir, params)
			self(u, "Raycast")
			return World.raycast(origin, dir, params, R())
		end,
		GetPartBoundsInBox = function(u, cf, size, params)
			self(u, "GetPartBoundsInBox")
			return World.partsInBox(cf, size, params, R())
		end,
		GetPartBoundsInRadius = function(u, pos, radius, params)
			self(u, "GetPartBoundsInRadius")
			return World.partsInBox(CFrame.new(pos), Vector3.one * radius * 2, params, R())
		end,
		GetPartsInPart = function(u, part, params)
			self(u, "GetPartsInPart")
			local pd = Engine.argInstance(part, 1, "GetPartsInPart")
			return World.partsInBox(readProp(pd, "CFrame", R()), readProp(pd, "Size", R()), params, R())
		end,
		BulkMoveTo = function(u, parts, cfs, mode)
			self(u, "BulkMoveTo")
			if type(parts) ~= "table" or type(cfs) ~= "table" then
				throw("runtime", "BulkMoveTo expects two arrays")
			end
			if #parts ~= #cfs then
				throw("runtime", string.format("BulkMoveTo: partList and cframeList must have the same length (%d vs %d)", #parts, #cfs))
			end
			local realm = R()
			for i, p in parts do
				local pd = DATA[p]
				if not pd or not pd.cls.isA.BasePart then
					throw("runtime", "BulkMoveTo: partList[" .. i .. "] is not a BasePart")
				end
				local cf = cfs[i]
				if typeof(cf) ~= "CFrame" then
					throw("runtime", "BulkMoveTo: cframeList[" .. i .. "] is not a CFrame")
				end
				Classes.setPartCFrame(pd, cf, realm, true)
			end
		end,
		FindPartOnRay = function(u, ray, ignore)
			self(u, "FindPartOnRay")
			local params = DT.RaycastParams.new()
			if ignore then
				params.FilterDescendantsInstances = { ignore }
			end
			local res = World.raycast(ray.Origin, ray.Direction, params, R())
			if res then
				return res.Instance, res.Position, res.Normal, res.Material
			end
			return nil, ray.Origin + ray.Direction, Vector3.zero, Enum.Material.Air
		end,
		ArePartsTouchingOthers = function()
			return false
		end,
		CalculateJumpPower = function(_, g, h)
			return math.sqrt(2 * g * h)
		end,
		CalculateJumpHeight = function(_, g, p)
			return p * p / (2 * g)
		end,
		GetRealPhysicsFPS = function()
			return 60
		end,
		GetNumAwakeParts = function()
			return 0
		end,
		IsRegion3Empty = function()
			return true
		end,
	},
})

----------------------------------------------------------------------
-- Lighting
----------------------------------------------------------------------
define("Lighting", {
	getters = {
		TimeOfDay = function(d, realm)
			local ct = readProp(d, "ClockTime", realm) or 14
			local h = math.floor(ct)
			local m = math.floor((ct - h) * 60)
			local s = math.floor(((ct - h) * 60 - m) * 60)
			return string.format("%02d:%02d:%02d", h, m, s)
		end,
	},
	setters = {
		TimeOfDay = function(d, v, realm)
			local h, m, s = string.match(v, "^(%d+):?(%d*):?(%d*)$")
			if h then
				setProp(d, "ClockTime", (tonumber(h) or 0) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600, realm)
			end
		end,
	},
	methods = {
		GetMinutesAfterMidnight = function(u)
			return (readProp(self(u, "GetMinutesAfterMidnight"), "ClockTime", R()) or 14) * 60
		end,
		SetMinutesAfterMidnight = function(u, m)
			setProp(self(u, "SetMinutesAfterMidnight"), "ClockTime", (m / 60) % 24, R())
		end,
		GetSunDirection = function()
			return Vector3.new(0.3, 0.5, 0.2).Unit
		end,
		GetMoonDirection = function()
			return Vector3.new(-0.3, 0.5, -0.2).Unit
		end,
	},
})

----------------------------------------------------------------------
-- Players / Player / characters
----------------------------------------------------------------------
define("Players", {
	getters = {
		LocalPlayer = function(d, realm)
			if realm and realm.kind == "client" then
				return realm.player
			end
			return nil
		end,
		RespawnTime = function(d)
			return d.props.RespawnTime or 5
		end,
		MaxPlayers = function()
			return 12
		end,
		PreferredPlayers = function()
			return 10
		end,
	},
	setters = {
		CharacterAutoLoads = function(d, v, realm)
			if realm and realm.kind == "client" then
				throw("runtime", "CharacterAutoLoads can only be set by the server")
			end
			setProp(d, "CharacterAutoLoads", v, realm)
		end,
	},
	methods = {
		GetPlayers = function(u)
			local d = self(u, "GetPlayers")
			local out = {}
			for _, c in Engine.childrenOf(d, R()) do
				if DATA[c].class == "Player" then
					table.insert(out, c)
				end
			end
			return out
		end,
		GetPlayerByUserId = function(u, id)
			self(u, "GetPlayerByUserId")
			if type(id) ~= "number" then
				throw("runtime", "Unable to cast value to std::string / int64 (GetPlayerByUserId expects a number)")
			end
			for _, pd in World.players do
				if pd.props.UserId == id and pd.parent ~= nil then
					return pd.proxy
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(u, char)
			self(u, "GetPlayerFromCharacter")
			if char == nil then
				return nil
			end
			for _, pd in World.players do
				if pd.props.Character == char and pd.parent ~= nil then
					return pd.proxy
				end
			end
			return nil
		end,
		GetNameFromUserIdAsync = function(u, id)
			self(u, "GetNameFromUserIdAsync")
			Sched.wait(0.05, "GetNameFromUserIdAsync")
			for _, pd in World.players do
				if pd.props.UserId == id then
					return pd.props.Name
				end
			end
			if type(id) ~= "number" or id <= 0 then
				error("Players:GetNameFromUserIdAsync() failed: Unknown user", 0)
			end
			return "Player" .. tostring(id)
		end,
		GetUserIdFromNameAsync = function(u, name)
			self(u, "GetUserIdFromNameAsync")
			Sched.wait(0.05, "GetUserIdFromNameAsync")
			for _, pd in World.players do
				if pd.props.Name == name then
					return pd.props.UserId
				end
			end
			error("Players:GetUserIdFromNameAsync() failed: Unknown user", 0)
		end,
		GetUserThumbnailAsync = function(u, id, ttype, tsize)
			self(u, "GetUserThumbnailAsync")
			Sched.wait(0.05, "GetUserThumbnailAsync")
			return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150", true
		end,
		GetHumanoidDescriptionFromUserId = function(u)
			self(u, "GetHumanoidDescriptionFromUserId")
			return (World.new("HumanoidDescription", { Name = "HumanoidDescription" }, nil, R() and math.max(R().id, 0) or 0))
		end,
		GetFriendsAsync = function()
			Engine.notEmulated("Players:GetFriendsAsync()")
		end,
	},
})

define("Player", {
	getters = {
		UserId = function(d)
			return d.props.UserId or 0
		end,
		DisplayName = function(d)
			return d.props.DisplayName or d.props.Name
		end,
		AccountAge = function()
			return 365
		end,
		MembershipType = function()
			return Enum.MembershipType.None
		end,
		-- Roblox account locale: Runtime.addPlayer({ locale = "ru-ru" }), "en-us" by default
		LocaleId = function(d)
			return d.locale or "en-us"
		end,
		CharacterAppearanceId = function(d)
			return d.props.UserId or 0
		end,
		HasVerifiedBadge = function()
			return false
		end,
	},
	setters = {
		Character = function(d, v, realm)
			setProp(d, "Character", v, realm)
		end,
		UserId = "readonly",
	},
	methods = {
		LoadCharacter = function(u)
			local d = self(u, "LoadCharacter")
			onlyServer("LoadCharacter")
			Services.loadCharacter(d)
		end,
		LoadCharacterAsync = function(u)
			local d = self(u, "LoadCharacterAsync")
			onlyServer("LoadCharacterAsync")
			Services.loadCharacter(d)
		end,
		Kick = function(u, msg)
			local d = self(u, "Kick")
			Report.add("check", Sched.realmName(R()), "Player " .. d.props.Name .. " was KICKED: " .. tostring(msg), Report.frames(nil, 1))
			Sched.deferCall(World.harness, function()
				Services.removePlayer(d, "kick")
			end)
		end,
		IsFriendsWith = function(u, id)
			local d = self(u, "IsFriendsWith")
			Sched.wait(0.05, "IsFriendsWith")
			local f = World.friends[d.props.UserId]
			return f ~= nil and f[id] == true
		end,
		IsFriendsWithAsync = function(u, id)
			local d = self(u, "IsFriendsWithAsync")
			Sched.wait(0.05, "IsFriendsWithAsync")
			local f = World.friends[d.props.UserId]
			return f ~= nil and f[id] == true
		end,
		GetFriendsOnline = function()
			Engine.notEmulated("Player:GetFriendsOnline()")
		end,
		IsInGroupAsync = function()
			return false
		end,
		GetRankInGroupAsync = function()
			return 0
		end,
		GetRoleInGroupAsync = function()
			return "Guest"
		end,
		IsInGroup = function()
			return false
		end,
		GetRankInGroup = function()
			return 0
		end,
		GetRoleInGroup = function()
			return "Guest"
		end,
		HasAppearanceLoaded = function()
			return true
		end,
		GetJoinData = function()
			return { LaunchData = "", SourcePlaceId = 0, Members = {} }
		end,
		GetNetworkPing = function()
			return World.latency
		end,
		DistanceFromCharacter = function(u, pos)
			local d = self(u, "DistanceFromCharacter")
			local char = d.props.Character
			local root = char and Engine.findChild(DATA[char], "HumanoidRootPart", R())
			if not root then
				return 0
			end
			return (readProp(DATA[root], "CFrame", R()).Position - pos).Magnitude
		end,
		GetMouse = function(u)
			local d = self(u, "GetMouse")
			onlyClient("GetMouse")
			local realm = R()
			if not realm.mouseObj then
				realm.mouseObj = World.new("PlayerMouse", { Name = "Mouse" }, nil, realm.id)
			end
			return realm.mouseObj
		end,
		ClearCharacterAppearance = function() end,
		RequestStreamAroundAsync = function() end,
		SetAttribute = nil,
	},
})

define("PlayerMouse", {
	getters = {
		Hit = function(d, realm)
			return CFrame.new(0, 0, 0)
		end,
		X = function(d, realm)
			return realm and realm.mouse.X or 0
		end,
		Y = function(d, realm)
			return realm and realm.mouse.Y or 0
		end,
		ViewSizeX = function(d, realm)
			return realm and realm.viewport.X or 1366
		end,
		ViewSizeY = function(d, realm)
			return realm and realm.viewport.Y or 768
		end,
	},
})

-- Build an R15-ish character model for player data pd
local R15 = {
	{ "LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, -0.8, 0), "HumanoidRootPart", "Root" },
	{ "UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.2, 0), "LowerTorso", "Waist" },
	{ "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), "UpperTorso", "Neck" },
	{ "LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 0.4, 0), "UpperTorso", "LeftShoulder" },
	{ "LeftLowerArm", Vector3.new(1, 1, 1), Vector3.new(-1.5, -0.7, 0), "LeftUpperArm", "LeftElbow" },
	{ "LeftHand", Vector3.new(1, 0.3, 1), Vector3.new(-1.5, -1.35, 0), "LeftLowerArm", "LeftWrist" },
	{ "RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 0.4, 0), "UpperTorso", "RightShoulder" },
	{ "RightLowerArm", Vector3.new(1, 1, 1), Vector3.new(1.5, -0.7, 0), "RightUpperArm", "RightElbow" },
	{ "RightHand", Vector3.new(1, 0.3, 1), Vector3.new(1.5, -1.35, 0), "RightLowerArm", "RightWrist" },
	{ "LeftUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(-0.5, -1.6, 0), "LowerTorso", "LeftHip" },
	{ "LeftLowerLeg", Vector3.new(1, 1, 1), Vector3.new(-0.5, -2.7, 0), "LeftUpperLeg", "LeftKnee" },
	{ "LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, -3.35, 0), "LeftLowerLeg", "LeftAnkle" },
	{ "RightUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(0.5, -1.6, 0), "LowerTorso", "RightHip" },
	{ "RightLowerLeg", Vector3.new(1, 1, 1), Vector3.new(0.5, -2.7, 0), "RightUpperLeg", "RightKnee" },
	{ "RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, -3.35, 0), "RightLowerLeg", "RightAnkle" },
}
local ATTACH = {
	HumanoidRootPart = { RootAttachment = CFrame.identity },
	Head = { HatAttachment = CFrame.new(0, 0.6, 0), HairAttachment = CFrame.new(0, 0.6, 0), FaceFrontAttachment = CFrame.new(0, 0, -0.6), FaceCenterAttachment = CFrame.identity, NeckRigAttachment = CFrame.new(0, -0.5, 0) },
	UpperTorso = { BodyBackAttachment = CFrame.new(0, 0, 0.5), BodyFrontAttachment = CFrame.new(0, 0, -0.5), NeckAttachment = CFrame.new(0, 0.8, 0), LeftCollarAttachment = CFrame.new(-1, 0.8, 0), RightCollarAttachment = CFrame.new(1, 0.8, 0), WaistRigAttachment = CFrame.new(0, -0.8, 0) },
	LowerTorso = { WaistCenterAttachment = CFrame.identity, WaistBackAttachment = CFrame.new(0, 0, 0.5), WaistFrontAttachment = CFrame.new(0, 0, -0.5), RootRigAttachment = CFrame.identity },
	RightHand = { RightGripAttachment = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0) },
	LeftHand = { LeftGripAttachment = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0) },
}

function Services.buildCharacter(pd, rootCF)
	local model, md = World.new("Model", { Name = pd.props.Name }, nil, 0)
	local function part(name, size, cf)
		local p, ppd = World.new("Part", {
			Name = name,
			Size = size,
			CFrame = cf,
			Anchored = false,
			CanCollide = name ~= "HumanoidRootPart",
			Transparency = if name == "HumanoidRootPart" then 1 else 0,
			Color = Color3.fromRGB(234, 184, 146),
			Material = Enum.Material.Plastic,
		}, model, 0)
		for an, acf in ATTACH[name] or {} do
			World.new("Attachment", { Name = an, CFrame = acf }, p, 0)
		end
		return p, ppd
	end
	local root, rootD = part("HumanoidRootPart", Vector3.new(2, 2, 1), rootCF)
	local byName = { HumanoidRootPart = root }
	for _, def in R15 do
		local name, size, off, parentName, jointName = def[1], def[2], def[3], def[4], def[5]
		local cf = rootCF * CFrame.new(off)
		local p = part(name, size, cf)
		byName[name] = p
		local p0 = byName[parentName]
		local p0d, p1d = DATA[p0], DATA[p]
		local m, mdd = World.new("Motor6D", {
			Name = jointName,
			Part0 = p0,
			Part1 = p,
			C0 = p0d.props.CFrame:Inverse() * cf,
			C1 = CFrame.identity,
		}, p, 0)
		-- register joint
		p0d.joints = p0d.joints or {}
		p1d.joints = p1d.joints or {}
		p0d.joints[mdd] = true
		p1d.joints[mdd] = true
		mdd.attached = { [p0d] = true, [p1d] = true }
	end
	World.new("Decal", { Name = "face", Texture = "rbxasset://textures/face.png" }, byName.Head, 0)
	local hum, hd = World.new("Humanoid", {
		Name = "Humanoid",
		Health = 100,
		MaxHealth = 100,
		WalkSpeed = readProp(DATA[World.starterPlayer], "CharacterWalkSpeed", nil) or 16,
		JumpPower = readProp(DATA[World.starterPlayer], "CharacterJumpPower", nil) or 50,
		UseJumpPower = true,
		HipHeight = 2,
		RigType = Enum.HumanoidRigType.R15,
		DisplayName = pd.props.DisplayName or pd.props.Name,
		MoveDirection = Vector3.zero,
	}, model, 0)
	World.new("Animator", { Name = "Animator" }, hum, 0)
	World.new("HumanoidDescription", { Name = "HumanoidDescription" }, hum, 0)
	md.props.PrimaryPart = root
	return model, md
end

Services.characterReplicationDelay = 0.1

function Services.spawnCFrame()
	local sp = World.spawnLocation
	if sp then
		local sd = DATA[sp]
		local cf = readProp(sd, "CFrame", nil)
		local size = readProp(sd, "Size", nil) or Vector3.one
		return CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + 3, 0))
	end
	return CFrame.new(0, 10, 0)
end

function Services.loadCharacter(pd)
	if pd.parent == nil then
		throw("runtime", "LoadCharacter can only be called when Player is in the world")
	end
	local old = pd.props.Character
	if old then
		local od = DATA[old]
		Engine.fireEvent(pd, "CharacterRemoving", nil, old)
		Engine.destroy(od, World.server)
	end
	-- the Backpack is recreated on every spawn
	local oldPack = Engine.findChild(pd, "Backpack", nil)
	if oldPack then
		Engine.destroy(DATA[oldPack], World.server)
	end
	local pack = World.new("Backpack", { Name = "Backpack" }, nil, 0)
	Engine.setParent(DATA[pack], pd.proxy, World.server)
	-- PlayerGui reset: ScreenGuis with ResetOnSpawn = true are removed on every (re)spawn
	local gui = Engine.findChild(pd, "PlayerGui", nil)
	if gui then
		local removed = {}
		for _, c in table.clone(DATA[gui].children) do
			local cd = DATA[c]
			if cd.cls.isA.LayerCollector and readProp(cd, "ResetOnSpawn", nil) ~= false then
				table.insert(removed, cd.props.Name)
				Engine.destroy(cd, World.server)
			end
		end
		if #removed > 0 then
			Report.add(
				"check",
				"engine",
				"ScreenGui(s) with ResetOnSpawn=true were destroyed by a character (re)spawn: " .. table.concat(removed, ", "),
				{},
				"Set ResetOnSpawn = false on GUIs created by code, or recreate them on CharacterAdded."
			)
		end
		-- StarterGui contents are copied in
		local sg = Services.services.StarterGui
		if sg then
			for _, c in DATA[sg].children do
				local cd = DATA[c]
				if cd.cls.isA.LayerCollector then
					local clone = Engine.clone(cd, World.server)
					if clone then
						Engine.setParent(DATA[clone], gui, World.server)
					end
				end
			end
		end
	end
	local model, md = Services.buildCharacter(pd, Services.spawnCFrame())
	md.props.Archivable = false -- like real characters: Clone() returns nil
	-- clients get the model first and its parts a moment later (replication is not atomic)
	local staged = {}
	local readyAt = Sched.now + Services.characterReplicationDelay
	for _, c in Engine.descendantsOf(md, nil) do
		local cd = DATA[c]
		cd.replicateAt = readyAt
		table.insert(staged, cd)
	end
	Sched.at(readyAt, function()
		for _, realm in Sched.realms do
			if realm.kind == "client" and not realm.dead then
				for _, x in staged do
					local parent = x.parent and DATA[x.parent]
					if parent and not x.destroyed then
						Engine.fireEvent(parent, "ChildAdded", realm, x.proxy)
						local anc = parent
						local guard = 0
						while anc and guard < 60 do
							Engine.fireEvent(anc, "DescendantAdded", realm, x.proxy)
							anc = anc.parent and DATA[anc.parent]
							guard += 1
						end
					end
				end
			end
		end
		for _, x in staged do
			x.replicateAt = nil
			local parent = x.parent and DATA[x.parent]
			if parent then
				Engine.resolveWaiters(parent, x)
			end
		end
	end)
	setProp(pd, "Character", model, World.server)
	Engine.setParent(md, World.workspace, World.server)
	Engine.fireEvent(pd, "CharacterAdded", nil, model)
	Engine.fireEvent(pd, "CharacterAppearanceLoaded", nil, model)
	-- camera subject for the owning client
	local realm = World.playerRealm[pd]
	if realm and realm.camera then
		local hum = Engine.findChild(md, "Humanoid", nil)
		setProp(DATA[realm.camera], "CameraSubject", hum, realm)
	end
	return model
end

----------------------------------------------------------------------
-- Humanoid
----------------------------------------------------------------------
local function humRoot(d, realm)
	local p = d.parent and DATA[d.parent]
	if not p then
		return nil
	end
	return Engine.findChild(p, "HumanoidRootPart", realm)
end

local function setHealth(d, v, realm)
	local max = readProp(d, "MaxHealth", realm) or 100
	v = math.clamp(v, 0, max)
	local old = readProp(d, "Health", realm)
	setProp(d, "Health", v, realm)
	if old ~= v then
		Engine.fireEvent(d, "HealthChanged", Engine.eventFilter(d), v)
	end
	if v <= 0 and not d.dead then
		d.dead = true
		d.state = Enum.HumanoidStateType.Dead
		Engine.fireEvent(d, "Died", Engine.eventFilter(d))
		Engine.fireEvent(d, "StateChanged", Engine.eventFilter(d), Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Dead)
		-- auto respawn when CharacterAutoLoads
		local plrs = Services.services.Players
		if plrs and readProp(DATA[plrs], "CharacterAutoLoads", nil) ~= false then
			local char = d.parent
			for _, pd in World.players do
				if pd.props.Character == char then
					Sched.at(Sched.now + (readProp(DATA[plrs], "RespawnTime", nil) or 5), function()
						if pd.parent and pd.props.Character == char then
							Sched.spawn(World.server, function()
								Services.loadCharacter(pd)
							end)
						end
					end)
				end
			end
		end
	end
end

define("Humanoid", {
	getters = {
		RootPart = function(d, realm)
			return humRoot(d, realm)
		end,
		FloorMaterial = function(d)
			return Enum.Material.Grass
		end,
		SeatPart = function()
			return nil
		end,
		MoveDirection = function(d)
			return d.props.MoveDirection or Vector3.zero
		end,
		TargetPoint = function()
			return Vector3.zero
		end,
		WalkToPoint = function(d)
			return d.moveTarget or Vector3.zero
		end,
	},
	setters = {
		Health = function(d, v, realm)
			setHealth(d, v, realm)
		end,
		MoveDirection = "readonly",
		Jump = function(d, v, realm)
			if v then
				Engine.fireEvent(d, "Jumping", Engine.eventFilter(d), true)
			end
		end,
	},
	methods = {
		TakeDamage = function(u, n)
			local d = self(u, "TakeDamage")
			if type(n) ~= "number" then
				throw("runtime", "invalid argument #1 to 'TakeDamage' (number expected)")
			end
			setHealth(d, (readProp(d, "Health", R()) or 100) - n, R())
		end,
		EquipTool = function(u, tool)
			local d = self(u, "EquipTool")
			local td = Engine.argInstance(tool, 1, "EquipTool")
			if not td.cls.isA.Tool then
				throw("runtime", "EquipTool: argument is not a Tool")
			end
			Services.equipTool(d, td, R())
		end,
		UnequipTools = function(u)
			local d = self(u, "UnequipTools")
			Services.unequipTools(d, R())
		end,
		GetState = function(u)
			local d = self(u, "GetState")
			return d.state or Enum.HumanoidStateType.Running
		end,
		ChangeState = function(u, st)
			local d = self(u, "ChangeState")
			if typeof(st) ~= "EnumItem" or st.EnumType ~= Enum.HumanoidStateType then
				throw("runtime", "ChangeState expects Enum.HumanoidStateType")
			end
			local old = d.state or Enum.HumanoidStateType.Running
			d.state = st
			Engine.fireEvent(d, "StateChanged", Engine.eventFilter(d), old, st)
			if st == Enum.HumanoidStateType.Dead then
				setHealth(d, 0, R())
			end
		end,
		SetStateEnabled = function(u, st, on)
			local d = self(u, "SetStateEnabled")
			d.stateEnabled = d.stateEnabled or {}
			d.stateEnabled[st] = on
		end,
		GetStateEnabled = function(u, st)
			local d = self(u, "GetStateEnabled")
			return not d.stateEnabled or d.stateEnabled[st] ~= false
		end,
		MoveTo = function(u, pos, part)
			local d = self(u, "MoveTo")
			if typeof(pos) ~= "Vector3" then
				throw("runtime", "invalid argument #1 to 'MoveTo' (Vector3 expected)")
			end
			d.moveTarget = pos
			d.moveStarted = Sched.now
		end,
		Move = function(u, dir)
			local d = self(u, "Move")
			d.moveDir = dir
		end,
		LoadAnimation = function(u, anim)
			local d = self(u, "LoadAnimation")
			local animator = Engine.findChild(d, "Animator", R())
			return Classes.loadAnimation(animator or u, anim, "LoadAnimation")
		end,
		GetPlayingAnimationTracks = function()
			return {}
		end,
		ApplyDescription = function() end,
		ApplyDescriptionReset = function() end,
		GetAppliedDescription = function(u)
			local d = self(u, "GetAppliedDescription")
			return Engine.findChild(d, "HumanoidDescription", R()) or (World.new("HumanoidDescription", {}, nil, 0))
		end,
		GetAccessories = function()
			return {}
		end,
		AddAccessory = function(u, acc)
			local d = self(u, "AddAccessory")
			local ad = Engine.argInstance(acc, 1, "AddAccessory")
			Engine.setParent(ad, d.parent, R())
		end,
		RemoveAccessories = function() end,
		BuildRigFromAttachments = function() end,
		GetLimb = function()
			return Enum.Limb.Unknown
		end,
		GetBodyPartR15 = function()
			return Enum.BodyPartR15.Unknown
		end,
		PlayEmote = function()
			return false
		end,
	},
})

function Services.equipTool(hd, td, realm)
	local char = hd.parent
	if not char then
		return
	end
	-- unequip others
	for _, c in Engine.childrenOf(DATA[char], realm) do
		local cd = DATA[c]
		if cd.cls.isA.Tool and cd ~= td then
			Services.unequipOne(hd, cd, realm)
		end
	end
	if td.parent ~= char then
		Engine.setParent(td, char, realm)
	end
	local handle = Engine.findChild(td, "Handle", realm)
	local hand = Engine.findChild(DATA[char], "RightHand", realm) or Engine.findChild(DATA[char], "Right Arm", realm)
	if handle and hand then
		local handD = DATA[hand]
		local old = Engine.findChild(handD, "RightGrip", realm)
		if old then
			Engine.destroy(DATA[old], realm)
		end
		local att = Engine.findChild(handD, "RightGripAttachment", realm)
		local c0 = if att then readProp(DATA[att], "CFrame", realm) else CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		local w, wd = World.new("Weld", { Name = "RightGrip" }, nil, 0)
		wd.props.C0 = c0
		wd.props.C1 = readProp(td, "Grip", realm) or CFrame.identity
		wd.props.Part0 = hand
		wd.props.Part1 = handle
		local hdd, hand_ = DATA[handle], handD
		hdd.joints = hdd.joints or {}
		hand_.joints = hand_.joints or {}
		hdd.joints[wd] = true
		hand_.joints[wd] = true
		wd.attached = { [hdd] = true, [hand_] = true }
		Classes.snapJoint(wd, realm)
		Engine.setParent(wd, hand, realm)
	end
	Engine.fireEvent(td, "Equipped", nil, nil)
end

function Services.unequipOne(hd, td, realm)
	local char = hd.parent
	for _, pd in World.players do
		if pd.props.Character == char then
			local pack = Engine.findChild(pd, "Backpack", realm)
			if pack then
				Engine.setParent(td, pack, realm)
			end
		end
	end
	Engine.fireEvent(td, "Unequipped", nil)
end

function Services.unequipTools(hd, realm)
	local char = hd.parent
	if not char then
		return
	end
	for _, c in Engine.childrenOf(DATA[char], realm) do
		local cd = DATA[c]
		if cd.cls.isA.Tool then
			Services.unequipOne(hd, cd, realm)
		end
	end
end

----------------------------------------------------------------------
-- RunService
----------------------------------------------------------------------
define("RunService", {
	getters = {
		Heartbeat = function(d)
			return Services.rsSignal(d, "Heartbeat", false)
		end,
		PostSimulation = function(d)
			return Services.rsSignal(d, "PostSimulation", false)
		end,
		Stepped = function(d)
			return Services.rsSignal(d, "Stepped", false)
		end,
		PreSimulation = function(d)
			return Services.rsSignal(d, "PreSimulation", false)
		end,
		PreAnimation = function(d)
			return Services.rsSignal(d, "PreAnimation", false)
		end,
		RenderStepped = function(d)
			return Services.rsSignal(d, "RenderStepped", true)
		end,
		PreRender = function(d)
			return Services.rsSignal(d, "PreRender", true)
		end,
		FrameNumber = function()
			return Sched.frame
		end,
	},
	methods = {
		IsServer = function()
			local r = Sched.CUR
			return r ~= nil and r.kind == "server"
		end,
		IsClient = function()
			local r = Sched.CUR
			return r ~= nil and r.kind == "client"
		end,
		IsStudio = function()
			return true
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(u, name, priority, fn)
			self(u, "BindToRenderStep")
			onlyClient("BindToRenderStep")
			if type(name) ~= "string" or type(priority) ~= "number" or type(fn) ~= "function" then
				throw("runtime", "BindToRenderStep(name: string, priority: number, fn: function) — bad arguments")
			end
			local realm = R()
			for i, b in realm.renderBindings do
				if b.name == name then
					table.remove(realm.renderBindings, i)
					break
				end
			end
			table.insert(realm.renderBindings, { name = name, priority = priority, fn = fn })
			table.sort(realm.renderBindings, function(a, b)
				return a.priority < b.priority
			end)
		end,
		UnbindFromRenderStep = function(u, name)
			self(u, "UnbindFromRenderStep")
			local realm = R()
			for i, b in realm.renderBindings do
				if b.name == name then
					table.remove(realm.renderBindings, i)
					return
				end
			end
		end,
		Set3dRenderingEnabled = function() end,
		GetRobloxVersion = function()
			return "0.694.0.6940982"
		end,
	},
})

function Services.rsSignal(d, name, clientOnly)
	d.rs = d.rs or {}
	local s = d.rs[name]
	if not s then
		s = Engine.newSignal("RunService." .. name, {
			immediate = true,
			onConnect = if clientOnly
				then function(r)
					if r and r.kind == "server" then
						throw("runtime", name .. " event can only be used from local scripts")
					end
				end
				else nil,
		})
		d.rs[name] = s
	end
	return s
end

----------------------------------------------------------------------
-- TweenService
----------------------------------------------------------------------
local TWEENABLE = { number = true, boolean = true, CFrame = true, Rect = true, Color3 = true, UDim = true, UDim2 = true, Vector2 = true, Vector2int16 = true, Vector3 = true, EnumItem = true }
local activeTweens = {} -- target d -> { [prop] = tweenD }

local function easing(style, dir, t)
	local n = style.Name
	local function ease(x)
		if n == "Linear" then
			return x
		elseif n == "Quad" then
			return x * x
		elseif n == "Cubic" then
			return x * x * x
		elseif n == "Quart" then
			return x ^ 4
		elseif n == "Quint" then
			return x ^ 5
		elseif n == "Sine" then
			return 1 - math.cos(x * math.pi / 2)
		elseif n == "Exponential" then
			return if x == 0 then 0 else 2 ^ (10 * x - 10)
		elseif n == "Circular" then
			return 1 - math.sqrt(1 - x * x)
		elseif n == "Back" then
			local s = 1.70158
			return x * x * ((s + 1) * x - s)
		elseif n == "Bounce" then
			local y = 1 - x
			local b
			if y < 1 / 2.75 then
				b = 7.5625 * y * y
			elseif y < 2 / 2.75 then
				y -= 1.5 / 2.75
				b = 7.5625 * y * y + 0.75
			elseif y < 2.5 / 2.75 then
				y -= 2.25 / 2.75
				b = 7.5625 * y * y + 0.9375
			else
				y -= 2.625 / 2.75
				b = 7.5625 * y * y + 0.984375
			end
			return 1 - b
		elseif n == "Elastic" then
			if x == 0 or x == 1 then
				return x
			end
			return -(2 ^ (10 * x - 10)) * math.sin((x * 10 - 10.75) * (2 * math.pi) / 3)
		end
		return x
	end
	local dn = dir.Name
	if dn == "In" then
		return ease(t)
	elseif dn == "Out" then
		return 1 - ease(1 - t)
	end
	if t < 0.5 then
		return ease(t * 2) / 2
	end
	return 1 - ease((1 - t) * 2) / 2
end
Services.easing = easing

local function tweenFinish(td, state)
	if td.state ~= Enum.PlaybackState.Playing and td.state ~= Enum.PlaybackState.Delayed then
		return
	end
	td.state = state
	local target = td.target
	if state == Enum.PlaybackState.Completed and target and not target.destroyed then
		local info = td.info
		local finalProps = if info.Reverses then td.startValues else td.goals
		for k, v in finalProps do
			local owned = activeTweens[target] and activeTweens[target][k]
			if owned == td then
				local ok, err = pcall(function()
					local m = target.cls.members[k]
					local setter = target.cls.setters[k]
					if type(setter) == "function" then
						setter(target, v, td.realm)
					else
						setProp(target, k, v, td.realm)
					end
				end)
				if not ok then
					Report.add("runtime", Sched.realmName(td.realm), "Tween apply failed: " .. tostring(err), td.frames)
				end
				activeTweens[target][k] = nil
			end
		end
	end
	if activeTweens[target] then
		for k, v in activeTweens[target] do
			if v == td then
				activeTweens[target][k] = nil
			end
		end
	end
	setProp(td, "PlaybackState", state, td.realm)
	Engine.fireEvent(td, "Completed", Engine.eventFilter(td), state)
end

local function tweenPlay(td)
	if td.state == Enum.PlaybackState.Playing then
		return
	end
	local target = td.target
	if not target or target.destroyed then
		return
	end
	local info = td.info
	td.state = Enum.PlaybackState.Playing
	setProp(td, "PlaybackState", Enum.PlaybackState.Playing, td.realm)
	-- take over properties from other tweens
	activeTweens[target] = activeTweens[target] or {}
	td.startValues = {}
	for k in td.goals do
		local other = activeTweens[target][k]
		if other and other ~= td then
			activeTweens[target][k] = nil
			local still = false
			for _, v in activeTweens[target] do
				if v == other then
					still = true
				end
			end
			if not still then
				tweenFinish(other, Enum.PlaybackState.Cancelled)
			end
		end
		activeTweens[target][k] = td
		td.startValues[k] = readProp(target, k, td.realm)
	end
	td.playToken = (td.playToken or 0) + 1
	local token = td.playToken
	local reps = info.RepeatCount
	if reps < 0 then
		-- infinite: apply goals after the first cycle and keep "playing"
		Sched.at(Sched.now + info.DelayTime + info.Time, function()
			if td.playToken == token and td.state == Enum.PlaybackState.Playing and not target.destroyed then
				for k, v in td.goals do
					if activeTweens[target] and activeTweens[target][k] == td then
						local setter = target.cls.setters[k]
						if type(setter) == "function" then
							setter(target, v, td.realm)
						else
							setProp(target, k, v, td.realm)
						end
					end
				end
			end
		end)
		return
	end
	local total = info.DelayTime + info.Time * (reps + 1) * (if info.Reverses then 2 else 1)
	Sched.at(Sched.now + total, function()
		if td.playToken == token then
			tweenFinish(td, Enum.PlaybackState.Completed)
		end
	end)
end

define("TweenService", {
	methods = {
		Create = function(u, inst, info, goals)
			self(u, "Create")
			local target = DATA[inst]
			if not target then
				throw("runtime", "TweenService:Create: argument #1 must be an Instance (got " .. typeof(inst) .. ")")
			end
			if typeof(info) ~= "TweenInfo" then
				throw("runtime", "TweenService:Create: argument #2 must be a TweenInfo (got " .. typeof(info) .. ")")
			end
			if type(goals) ~= "table" then
				throw("runtime", "TweenService:Create: argument #3 must be a table")
			end
			local realm = R()
			local checked = {}
			for k, v in goals do
				local m = target.cls.members[k]
				if not m or m.Kind ~= "prop" then
					throw("member", string.format("TweenService:Create no property named '%s' for object '%s'", tostring(k), target.props.Name))
				end
				local tv = typeof(v)
				if not TWEENABLE[tv] then
					throw("proptype", string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", k, m.Type, tv))
				end
				local cur = readProp(target, k, realm)
				local ct = typeof(cur)
				if cur ~= nil and ct ~= tv and not (ct == "number" and tv == "number") then
					throw("proptype", string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", k, ct, tv))
				end
				checked[k] = Engine.validate(target, k, m, v)
			end
			local tw, td = World.new("Tween", { Name = "Tween" }, nil, if realm and realm.id > 0 then realm.id else 0)
			td.target = target
			td.info = info
			td.goals = checked
			td.realm = realm
			td.state = Enum.PlaybackState.Begin
			td.frames = Report.frames(nil, 1)
			td.props.Instance = inst
			td.props.TweenInfo = info
			td.props.PlaybackState = Enum.PlaybackState.Begin
			return tw
		end,
		GetValue = function(u, alpha, style, dir)
			self(u, "GetValue")
			return easing(style, dir, math.clamp(alpha, 0, 1))
		end,
		SmoothDamp = function()
			Engine.notEmulated("TweenService:SmoothDamp()")
		end,
	},
})
define("TweenBase", {
	getters = {
		PlaybackState = function(d)
			return d.state or Enum.PlaybackState.Begin
		end,
	},
	methods = {
		Play = function(u)
			tweenPlay(self(u, "Play"))
		end,
		Cancel = function(u)
			local d = self(u, "Cancel")
			d.playToken = (d.playToken or 0) + 1
			tweenFinish(d, Enum.PlaybackState.Cancelled)
		end,
		Pause = function(u)
			local d = self(u, "Pause")
			if d.state == Enum.PlaybackState.Playing then
				d.playToken = (d.playToken or 0) + 1
				d.state = Enum.PlaybackState.Paused
				setProp(d, "PlaybackState", Enum.PlaybackState.Paused, d.realm)
			end
		end,
	},
})

----------------------------------------------------------------------
-- DataStoreService (in-memory; values validated like the real service)
----------------------------------------------------------------------
Services.stores = {} -- "name/scope" -> { kind, data = { key -> value }, versions }
Services.dataStoreLatency = 0.08

local function dsValidate(v, path, depth, seen)
	local tv = typeof(v)
	if tv == "nil" or tv == "boolean" or tv == "string" then
		return nil
	elseif tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return path .. ": NaN/inf number (saved as null/garbage)"
		end
		return nil
	elseif tv == "table" then
		if seen[v] then
			return path .. ": cyclic table"
		end
		seen[v] = true
		if depth > 60 then
			return path .. ": table nesting too deep"
		end
		local n = #v
		local count, strKeys, numKeys = 0, 0, 0
		for k in pairs(v) do
			count += 1
			if type(k) == "string" then
				strKeys += 1
			elseif type(k) == "number" then
				numKeys += 1
			else
				return path .. ": key of type " .. typeof(k) .. " — Cannot convert mixed or non-array tables: keys must be strings"
			end
		end
		if numKeys > 0 and (strKeys > 0 or numKeys ~= n) then
			return path .. ": Cannot convert mixed or non-array tables: keys must be strings"
		end
		for k, x in pairs(v) do
			local err = dsValidate(x, path .. "." .. tostring(k), depth + 1, seen)
			if err then
				return err
			end
		end
		seen[v] = nil
		return nil
	end
	return path .. ": Cannot store " .. tv .. " in data store. Data stores can only accept valid UTF-8 characters."
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end
Services.deepCopy = deepCopy

local function storeFor(name, scope, kind)
	local key = kind .. ":" .. name .. "/" .. (scope or "global")
	local s = Services.stores[key]
	if not s then
		s = { kind = kind, name = name, data = {}, writes = 0, reads = 0 }
		Services.stores[key] = s
	end
	return s
end
Services.storeFor = storeFor

local function dsCheckValue(store, value)
	local err = dsValidate(value, "value", 0, {})
	if err then
		throw("remote", "DataStore " .. store.name .. ": " .. err)
	end
	local okSize, encoded = pcall(serde.encode, "json", value)
	if okSize and #encoded > 4194304 then
		throw("remote", "DataStore " .. store.name .. ": value too large (" .. #encoded .. " chars > 4MB)")
	end
	if store.kind == "ordered" and (type(value) ~= "number" or value ~= math.floor(value)) then
		throw("remote", "OrderedDataStore " .. store.name .. ": only integer values can be stored (got " .. typeof(value) .. " " .. tostring(value) .. ")")
	end
end

local function dsKey(key)
	if type(key) ~= "string" or key == "" or #key > 50 then
		throw("runtime", "DataStore key must be a non-empty string of at most 50 characters (got " .. typeof(key) .. " " .. tostring(key) .. ")")
	end
end

local function dsYield(what)
	Sched.wait(Services.dataStoreLatency, what)
end

local function keyInfo()
	local u, d = World.new("DataStoreKeyInfo", { Name = "DataStoreKeyInfo" }, nil, 0)
	d.props.Version = "1"
	d.props.CreatedTime = math.floor(serverTime() * 1000)
	d.props.UpdatedTime = math.floor(serverTime() * 1000)
	return u
end

local storeMethods = {
	GetAsync = function(u, key)
		local d = self(u, "GetAsync")
		onlyServer("DataStore:GetAsync")
		dsKey(key)
		dsYield("DataStore:GetAsync")
		d.store.reads += 1
		local v = d.store.data[key]
		if v == nil then
			return nil, nil
		end
		return deepCopy(v), keyInfo()
	end,
	SetAsync = function(u, key, value)
		local d = self(u, "SetAsync")
		onlyServer("DataStore:SetAsync")
		dsKey(key)
		dsCheckValue(d.store, value)
		dsYield("DataStore:SetAsync")
		d.store.writes += 1
		d.store.data[key] = deepCopy(value)
		return "1"
	end,
	UpdateAsync = function(u, key, fn)
		local d = self(u, "UpdateAsync")
		onlyServer("DataStore:UpdateAsync")
		dsKey(key)
		if type(fn) ~= "function" then
			throw("runtime", "UpdateAsync: argument #2 must be a function")
		end
		dsYield("DataStore:UpdateAsync")
		d.store.reads += 1
		local old = deepCopy(d.store.data[key])
		-- the transform function must not yield
		local co = coroutine.create(fn)
		Sched.tag(co, Sched.CUR)
		local ok, newValue = coroutine.resume(co, old, if old ~= nil then keyInfo() else nil)
		if coroutine.status(co) == "suspended" then
			throw("runtime", "UpdateAsync: transform function yielded (callbacks cannot yield)")
		end
		if not ok then
			error(newValue, 0)
		end
		if newValue == nil then
			return nil
		end
		dsCheckValue(d.store, newValue)
		d.store.writes += 1
		d.store.data[key] = deepCopy(newValue)
		return deepCopy(newValue), keyInfo()
	end,
	RemoveAsync = function(u, key)
		local d = self(u, "RemoveAsync")
		onlyServer("DataStore:RemoveAsync")
		dsKey(key)
		dsYield("DataStore:RemoveAsync")
		local old = d.store.data[key]
		d.store.data[key] = nil
		d.store.writes += 1
		return deepCopy(old)
	end,
	IncrementAsync = function(u, key, delta)
		local d = self(u, "IncrementAsync")
		onlyServer("DataStore:IncrementAsync")
		dsKey(key)
		dsYield("DataStore:IncrementAsync")
		local old = d.store.data[key] or 0
		if type(old) ~= "number" then
			throw("runtime", "IncrementAsync: stored value is not a number")
		end
		local nv = old + math.floor(delta or 1)
		d.store.data[key] = nv
		d.store.writes += 1
		return nv
	end,
}

define("GlobalDataStore", { methods = storeMethods })
define("DataStore", {
	methods = {
		ListKeysAsync = function()
			Engine.notEmulated("DataStore:ListKeysAsync()")
		end,
		GetVersionAsync = function()
			Engine.notEmulated("DataStore:GetVersionAsync()")
		end,
		ListVersionsAsync = function()
			Engine.notEmulated("DataStore:ListVersionsAsync()")
		end,
	},
})
define("OrderedDataStore", {
	methods = {
		GetSortedAsync = function(u, ascending, pageSize, minValue, maxValue)
			local d = self(u, "GetSortedAsync")
			onlyServer("OrderedDataStore:GetSortedAsync")
			if type(ascending) ~= "boolean" then
				throw("runtime", "GetSortedAsync: argument #1 (ascending) must be a boolean")
			end
			if type(pageSize) ~= "number" or pageSize < 1 or pageSize > 100 then
				throw("runtime", "GetSortedAsync: PageSize must be within a range of 1 to 100")
			end
			dsYield("OrderedDataStore:GetSortedAsync")
			local list = {}
			for k, v in d.store.data do
				if (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
					table.insert(list, { key = k, value = v })
				end
			end
			table.sort(list, function(a, b)
				if a.value == b.value then
					return a.key < b.key
				end
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			local pages, pd = World.new("DataStorePages", { Name = "DataStorePages" }, nil, 0)
			pd.list = list
			pd.pageSize = math.floor(pageSize)
			pd.page = 1
			return pages
		end,
	},
})
define("Pages", {
	getters = {
		IsFinished = function(d)
			if not d.list then
				return true
			end
			return d.page * d.pageSize >= #d.list
		end,
	},
	methods = {
		GetCurrentPage = function(u)
			local d = self(u, "GetCurrentPage")
			local out = {}
			if d.list then
				for i = (d.page - 1) * d.pageSize + 1, math.min(#d.list, d.page * d.pageSize) do
					table.insert(out, { key = d.list[i].key, value = d.list[i].value })
				end
			end
			return out
		end,
		AdvanceToNextPageAsync = function(u)
			local d = self(u, "AdvanceToNextPageAsync")
			dsYield("Pages:AdvanceToNextPageAsync")
			if d.list and d.page * d.pageSize >= #d.list then
				throw("runtime", "AdvanceToNextPageAsync: no more pages (check IsFinished)")
			end
			d.page += 1
		end,
	},
})

define("DataStoreService", {
	methods = {
		GetDataStore = function(u, name, scope, options)
			self(u, "GetDataStore")
			onlyServer("DataStoreService:GetDataStore")
			if type(name) ~= "string" or name == "" or #name > 50 then
				throw("runtime", "GetDataStore: name must be a non-empty string of at most 50 characters")
			end
			local s, sd = World.new("DataStore", { Name = name }, nil, 0)
			sd.store = storeFor(name, scope, "global")
			return s
		end,
		GetGlobalDataStore = function(u)
			self(u, "GetGlobalDataStore")
			onlyServer("DataStoreService:GetGlobalDataStore")
			local s, sd = World.new("GlobalDataStore", { Name = "GlobalDataStore" }, nil, 0)
			sd.store = storeFor("__global", nil, "global")
			return s
		end,
		GetOrderedDataStore = function(u, name, scope)
			self(u, "GetOrderedDataStore")
			onlyServer("DataStoreService:GetOrderedDataStore")
			if type(name) ~= "string" or name == "" then
				throw("runtime", "GetOrderedDataStore: name must be a non-empty string")
			end
			local s, sd = World.new("OrderedDataStore", { Name = name }, nil, 0)
			sd.store = storeFor(name, scope, "ordered")
			return s
		end,
		GetRequestBudgetForRequestType = function()
			return 100
		end,
		ListDataStoresAsync = function()
			Engine.notEmulated("DataStoreService:ListDataStoresAsync()")
		end,
	},
})

----------------------------------------------------------------------
-- HttpService
----------------------------------------------------------------------
local guidCounter = 0
local function toJsonable(v, seen)
	local tv = typeof(v)
	if tv == "table" then
		if seen[v] then
			throw("runtime", "JSONEncode: tables cannot be cyclic")
		end
		seen[v] = true
		local out = {}
		for k, x in pairs(v) do
			out[k] = toJsonable(x, seen)
		end
		seen[v] = nil
		return out
	elseif tv == "number" or tv == "string" or tv == "boolean" or tv == "nil" then
		return v
	end
	-- Roblox encodes unsupported values as null
	return nil
end

define("HttpService", {
	getters = {
		HttpEnabled = function()
			return false
		end,
	},
	methods = {
		GenerateGUID = function(u, wrap)
			self(u, "GenerateGUID")
			guidCounter += 1
			local hex = string.format("%08X-%04X-4%03X-A%03X-%012X", 0x5EED0000 + guidCounter, guidCounter % 65536, guidCounter % 4096, (guidCounter * 7) % 4096, guidCounter * 7919)
			if wrap == false then
				return hex
			end
			return "{" .. hex .. "}"
		end,
		JSONEncode = function(u, v)
			self(u, "JSONEncode")
			local ok, res = pcall(serde.encode, "json", toJsonable(v, {}))
			if not ok then
				throw("runtime", "Can't convert to JSON: " .. tostring(res))
			end
			return res
		end,
		JSONDecode = function(u, s)
			self(u, "JSONDecode")
			if type(s) ~= "string" then
				throw("runtime", "JSONDecode: argument must be a string")
			end
			local ok, res = pcall(serde.decode, "json", s)
			if not ok then
				error("Can't parse JSON", 0)
			end
			return res
		end,
		UrlEncode = function(u, s)
			self(u, "UrlEncode")
			return (string.gsub(tostring(s), "[^%w%-_%.~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end,
		GetAsync = function()
			error("Http requests are not enabled. Enable via game settings", 0)
		end,
		PostAsync = function()
			error("Http requests are not enabled. Enable via game settings", 0)
		end,
		RequestAsync = function()
			error("Http requests are not enabled. Enable via game settings", 0)
		end,
	},
})

----------------------------------------------------------------------
-- Input services (per client realm)
----------------------------------------------------------------------
define("UserInputService", {
	getters = {
		TouchEnabled = function(d, realm)
			return realm ~= nil and realm.touch == true
		end,
		KeyboardEnabled = function(d, realm)
			return realm ~= nil and not realm.touch
		end,
		MouseEnabled = function(d, realm)
			return realm ~= nil and not realm.touch
		end,
		GamepadEnabled = function()
			return false
		end,
		VREnabled = function()
			return false
		end,
		AccelerometerEnabled = function()
			return false
		end,
		GyroscopeEnabled = function()
			return false
		end,
		PreferredInput = function(d, realm)
			return if realm and realm.preferredInput then realm.preferredInput else Enum.PreferredInput.KeyboardAndMouse
		end,
		OnScreenKeyboardVisible = function()
			return false
		end,
		TouchScreenEnabled = function(d, realm)
			return realm ~= nil and realm.touch == true
		end,
	},
	methods = {
		GetMouseLocation = function(u)
			self(u, "GetMouseLocation")
			local r = R()
			return if r and r.mouse then r.mouse else Vector2.zero
		end,
		GetMouseDelta = function()
			return Vector2.zero
		end,
		GetLastInputType = function(u)
			local r = R()
			return if r and r.lastInput then r.lastInput else Enum.UserInputType.None
		end,
		GetFocusedTextBox = function(u)
			self(u, "GetFocusedTextBox")
			local f = Classes.focusedBox
			if f and f.realm == R() and f.d.focused then
				return f.d.proxy
			end
			return nil
		end,
		IsKeyDown = function(u, key)
			self(u, "IsKeyDown")
			local r = R()
			return r ~= nil and r.keysDown[key] == true
		end,
		IsMouseButtonPressed = function()
			return false
		end,
		GetKeysPressed = function()
			return {}
		end,
		GetMouseButtonsPressed = function()
			return {}
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetNavigationGamepads = function()
			return {}
		end,
		GetGamepadConnected = function()
			return false
		end,
		GetSupportedGamepadKeyCodes = function()
			return {}
		end,
		GamepadSupports = function()
			return false
		end,
		GetStringForKeyCode = function(u, k)
			return if typeof(k) == "EnumItem" then k.Name else ""
		end,
		GetImageForKeyCode = function()
			return ""
		end,
		GetDeviceAcceleration = function()
			Engine.notEmulated("UserInputService:GetDeviceAcceleration()")
		end,
		GetUserCFrame = function()
			return CFrame.identity
		end,
	},
})

define("ContextActionService", {
	methods = {
		BindAction = function(u, name, fn, touchButton, ...)
			self(u, "BindAction")
			Services.casBind(name, fn, touchButton, 2000, ...)
		end,
		BindActionAtPriority = function(u, name, fn, touchButton, priority, ...)
			self(u, "BindActionAtPriority")
			if type(priority) ~= "number" then
				throw("runtime", "BindActionAtPriority: argument #4 (priority) must be a number")
			end
			Services.casBind(name, fn, touchButton, priority, ...)
		end,
		UnbindAction = function(u, name)
			self(u, "UnbindAction")
			local r = R()
			r.casBindings[name] = nil
		end,
		BindActivate = function() end,
		UnbindActivate = function() end,
		SetTitle = function() end,
		SetDescription = function() end,
		SetImage = function() end,
		SetPosition = function() end,
		GetButton = function()
			return nil
		end,
		GetBoundActionInfo = function(u, name)
			local r = R()
			local b = r.casBindings[name]
			return if b then { priorityLevel = b.priority, createTouchButton = b.touch, inputTypes = b.inputs } else {}
		end,
		GetAllBoundActionInfo = function(u)
			local out = {}
			for n, b in R().casBindings do
				out[n] = { priorityLevel = b.priority }
			end
			return out
		end,
		GetCurrentLocalToolIcon = function()
			return ""
		end,
	},
})

local casOrder = 0
function Services.casBind(name, fn, touch, priority, ...)
	onlyClient("ContextActionService binding")
	if type(name) ~= "string" then
		throw("runtime", "BindAction: argument #1 (actionName) must be a string")
	end
	if type(fn) ~= "function" then
		throw("runtime", "BindAction: argument #2 (functionToBind) must be a function")
	end
	local inputs = { ... }
	for i, inp in inputs do
		local ok = typeof(inp) == "EnumItem" and (inp.EnumType == Enum.KeyCode or inp.EnumType == Enum.UserInputType or inp.EnumType == Enum.PlayerActions)
		if not ok then
			throw("runtime", "BindAction: input #" .. i .. " must be an Enum.KeyCode/UserInputType/PlayerActions (got " .. typeof(inp) .. ")")
		end
	end
	casOrder += 1
	R().casBindings[name] = { name = name, fn = fn, touch = touch, priority = priority, inputs = inputs, order = casOrder }
end

define("InputObject", {})

-- Dispatch a keyboard/mouse input in a client realm (CAS first, then UserInputService)
function Services.dispatchInput(realm, keyCode, inputType, state)
	local u, d = World.new("InputObject", { Name = "InputObject" }, nil, realm.id)
	d.props.KeyCode = keyCode or Enum.KeyCode.Unknown
	d.props.UserInputType = inputType or Enum.UserInputType.Keyboard
	d.props.UserInputState = state or Enum.UserInputState.Begin
	d.props.Position = Vector3.new(realm.mouse.X, realm.mouse.Y, 0)
	d.props.Delta = Vector3.zero
	realm.lastInput = d.props.UserInputType
	local sunk = false
	local list = {}
	for _, b in realm.casBindings do
		for _, inp in b.inputs do
			if inp == keyCode or inp == inputType then
				table.insert(list, b)
				break
			end
		end
	end
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.order > b.order
	end)
	for _, b in list do
		local result
		local co = Sched.create(realm, function()
			result = b.fn(b.name, d.props.UserInputState, u)
		end)
		Sched.resume(co)
		if result ~= Enum.ContextActionResult.Pass then
			sunk = true
			break
		end
	end
	if state == Enum.UserInputState.Begin then
		if keyCode then
			realm.keysDown[keyCode] = true
		end
		Engine.fire(Engine.getSignal(DATA[Services.getService("UserInputService")], "InputBegan"), realm, u, sunk)
	elseif state == Enum.UserInputState.End then
		if keyCode then
			realm.keysDown[keyCode] = nil
		end
		Engine.fire(Engine.getSignal(DATA[Services.getService("UserInputService")], "InputEnded"), realm, u, sunk)
	end
	return sunk
end

----------------------------------------------------------------------
-- GUI-related services
----------------------------------------------------------------------
define("GuiService", {
	getters = {
		TopbarInset = function(d, realm)
			local vp = Classes.viewportFor(realm)
			return roblox.Rect.new(104, 0, vp.X - 60, Classes.GUI_INSET)
		end,
		MenuIsOpen = function()
			return false
		end,
		PreferredTransparency = function()
			return 1
		end,
		ReducedMotionEnabled = function()
			return false
		end,
		PreferredTextSize = function()
			return Enum.PreferredTextSize.Medium
		end,
		IsWindows = function()
			return false
		end,
	},
	methods = {
		GetGuiInset = function()
			return Vector2.new(0, Classes.GUI_INSET), Vector2.zero
		end,
		IsTenFootInterface = function()
			return false
		end,
		GetEmotesMenuOpen = function()
			return false
		end,
		SetEmotesMenuOpen = function() end,
		GetInspectMenuEnabled = function()
			return true
		end,
		SetInspectMenuEnabled = function() end,
		CloseInspectMenu = function() end,
		InspectPlayerFromUserId = function() end,
		Select = function() end,
	},
})

local CORE_SETTABLE = {
	ResetButtonCallback = true, SendNotification = true, ChatMakeSystemMessage = true, TopbarEnabled = true,
	PointsNotificationsActive = true, BadgesNotificationsActive = true, AvatarContextMenuEnabled = true,
	ChatActive = true, ChatWindowSize = true, ChatWindowPosition = true, ChatBarDisabled = true,
	PlayerBlockedEvent = true, PlayerUnblockedEvent = true, PlayerMutedEvent = true, PlayerUnmutedEvent = true,
	DevConsoleVisible = true, PromptSendFriendRequest = true, PromptUnfriend = true, PromptBlockPlayer = true,
	PromptUnblockPlayer = true, CoreGuiChatConnections = true, AvatarContextMenuTarget = true, AddAvatarContextMenuOption = true,
	RemoveAvatarContextMenuOption = true, EmotesMenuOpen = true, VRRotationIntensity = true, VREnableControllerModels = true,
	VRLaserPointerMode = true,
}
define("StarterGui", {
	methods = {
		SetCoreGuiEnabled = function(u, t, on)
			self(u, "SetCoreGuiEnabled")
			onlyClient("SetCoreGuiEnabled")
			if typeof(t) ~= "EnumItem" or t.EnumType ~= Enum.CoreGuiType then
				throw("runtime", "SetCoreGuiEnabled: argument #1 must be Enum.CoreGuiType")
			end
			if type(on) ~= "boolean" then
				throw("runtime", "SetCoreGuiEnabled: argument #2 must be a boolean")
			end
			R().coreGui[t] = on
		end,
		GetCoreGuiEnabled = function(u, t)
			local v = R().coreGui[t]
			return v ~= false
		end,
		SetCore = function(u, name, v)
			self(u, "SetCore")
			onlyClient("SetCore")
			if not CORE_SETTABLE[name] then
				throw("runtime", "SetCore: " .. tostring(name) .. " has not been registered by the CoreScripts")
			end
		end,
		GetCore = function(u, name)
			self(u, "GetCore")
			onlyClient("GetCore")
			if name == "DevConsoleVisible" or name == "TopbarEnabled" then
				return false
			end
			throw("runtime", "GetCore: " .. tostring(name) .. " has not been registered by the CoreScripts")
		end,
		RegisterSetCore = function() end,
		RegisterGetCore = function() end,
	},
})

define("SoundService", {
	methods = {
		PlayLocalSound = function(u, s)
			self(u, "PlayLocalSound")
			local sd = Engine.argInstance(s, 1, "PlayLocalSound")
			if sd.class ~= "Sound" then
				throw("runtime", "PlayLocalSound expects a Sound")
			end
			Classes.soundPlay(sd, R())
		end,
		SetListener = function() end,
		GetListener = function()
			return Enum.ListenerType.Camera, nil
		end,
	},
})

define("ContentProvider", {
	getters = {
		RequestQueueSize = function()
			return 0
		end,
		BaseUrl = function()
			return "https://www.roblox.com/"
		end,
	},
	methods = {
		PreloadAsync = function(u, list, cb)
			self(u, "PreloadAsync")
			if type(list) ~= "table" then
				throw("runtime", "PreloadAsync expects an array of Instances or content strings")
			end
			local ids = {}
			for _, item in list do
				local t = typeof(item)
				if t == "string" then
					table.insert(ids, item)
				elseif t == "Instance" then
					local d = DATA[item]
					for _, k in { "SoundId", "Texture", "Image", "MeshId", "TextureID", "AnimationId" } do
						local m = d.cls.members[k]
						if m and m.Kind == "prop" then
							local v = readProp(d, k, R())
							if type(v) == "string" and v ~= "" then
								table.insert(ids, v)
							end
						end
					end
				elseif t == "Content" then
					table.insert(ids, tostring(item))
				else
					throw("runtime", "PreloadAsync: unsupported list item " .. t)
				end
			end
			Sched.wait(0.1 + 0.002 * #ids, "ContentProvider:PreloadAsync")
			if cb then
				if type(cb) ~= "function" then
					throw("runtime", "PreloadAsync: callback must be a function")
				end
				for _, id in ids do
					cb(id, Enum.AssetFetchStatus.Success)
				end
			end
		end,
		GetAssetFetchStatus = function()
			return Enum.AssetFetchStatus.Success
		end,
		GetAssetFetchStatusChangedSignal = function(u, id)
			return Engine.getSignal(self(u, "GetAssetFetchStatusChangedSignal"), "fetch:" .. tostring(id))
		end,
	},
})

define("TextService", {
	methods = {
		GetTextSize = function(u, text, size, font, frame)
			self(u, "GetTextSize")
			if type(text) ~= "string" or type(size) ~= "number" or typeof(font) ~= "EnumItem" or typeof(frame) ~= "Vector2" then
				throw("runtime", "GetTextSize(string, number, Enum.Font, Vector2) — bad arguments")
			end
			local w = (utf8.len(text) or #text) * size * 0.52
			local lines = 1
			if w > frame.X and frame.X > 0 then
				lines = math.ceil(w / frame.X)
				w = frame.X
			end
			return Vector2.new(math.floor(w + 0.5), lines * size)
		end,
		GetTextBoundsAsync = function(u, params)
			self(u, "GetTextBoundsAsync")
			local pd = Engine.argInstance(params, 1, "GetTextBoundsAsync")
			local text = readProp(pd, "Text", R()) or ""
			local size = readProp(pd, "Size", R()) or 14
			local width = readProp(pd, "Width", R()) or 0
			local w = (utf8.len(text) or #text) * size * 0.52
			local lines = 1
			if width > 0 and w > width then
				lines = math.ceil(w / width)
				w = width
			end
			return Vector2.new(math.floor(w + 0.5), lines * size)
		end,
		FilterStringAsync = function(u, text)
			self(u, "FilterStringAsync")
			local f, fd = World.new("TextFilterResult", { Name = "TextFilterResult" }, nil, 0)
			fd.text = text
			return f
		end,
	},
})
define("TextFilterResult", {
	methods = {
		GetNonChatStringForBroadcastAsync = function(u)
			return self(u, "GetNonChatStringForBroadcastAsync").text
		end,
		GetNonChatStringForUserAsync = function(u)
			return self(u, "GetNonChatStringForUserAsync").text
		end,
		GetChatForUserAsync = function(u)
			return self(u, "GetChatForUserAsync").text
		end,
	},
})

----------------------------------------------------------------------
-- Misc services
----------------------------------------------------------------------
define("Debris", {
	methods = {
		AddItem = function(u, inst, t)
			self(u, "AddItem")
			local d = Engine.argInstance(inst, 1, "AddItem")
			local realm = R()
			Sched.at(Sched.now + (t or 10), function()
				if not d.destroyed then
					Sched.spawn(realm, function()
						Engine.destroy(d, realm)
					end)
				end
			end)
		end,
	},
})

define("CollectionService", {
	methods = {
		AddTag = function(u, inst, tag)
			self(u, "AddTag")
			Classes.addTag(Engine.argInstance(inst, 1, "AddTag"), tag)
		end,
		RemoveTag = function(u, inst, tag)
			self(u, "RemoveTag")
			Classes.removeTag(Engine.argInstance(inst, 1, "RemoveTag"), tag)
		end,
		HasTag = function(u, inst, tag)
			self(u, "HasTag")
			local d = Engine.argInstance(inst, 1, "HasTag")
			return d.tags ~= nil and d.tags[tag] == true
		end,
		GetTags = function(u, inst)
			self(u, "GetTags")
			local d = Engine.argInstance(inst, 1, "GetTags")
			local out = {}
			for t in d.tags or {} do
				table.insert(out, t)
			end
			return out
		end,
		GetTagged = function(u, tag)
			self(u, "GetTagged")
			local out = {}
			local realm = R()
			Engine.forSubtree(World.gameD, function(x)
				if x.tags and x.tags[tag] and Engine.visibleTo(x, realm) then
					table.insert(out, x.proxy)
				end
			end)
			return out
		end,
		GetInstanceAddedSignal = function(u, tag)
			self(u, "GetInstanceAddedSignal")
			return Classes.tagSignal(tag, "added")
		end,
		GetInstanceRemovedSignal = function(u, tag)
			self(u, "GetInstanceRemovedSignal")
			return Classes.tagSignal(tag, "removed")
		end,
		GetAllTags = function()
			local out = {}
			for t in Classes.tagSignals do
				table.insert(out, t)
			end
			return out
		end,
	},
})

define("ProximityPromptService", {})
define("ProximityPrompt", {
	methods = {
		InputHoldBegin = function(u)
			self(u, "InputHoldBegin")
		end,
		InputHoldEnd = function(u)
			self(u, "InputHoldEnd")
		end,
	},
})

define("MarketplaceService", {
	getters = {
		ProcessReceipt = function()
			throw("runtime", "ProcessReceipt is a callback member of MarketplaceService; you can only set the callback value, get is not available")
		end,
	},
	setters = {
		ProcessReceipt = function(d, v, realm)
			if realm and realm.kind == "client" then
				throw("runtime", "ProcessReceipt can only be set on the server")
			end
			d.processReceipt = v
		end,
	},
	methods = {
		PromptProductPurchase = function(u, player, id)
			self(u, "PromptProductPurchase")
			Report.add("note", Sched.realmName(R()), "MarketplaceService:PromptProductPurchase(" .. tostring(id) .. ") — purchase prompt shown (sim does not buy)", {})
		end,
		PromptGamePassPurchase = function(u, player, id)
			self(u, "PromptGamePassPurchase")
			Report.add("note", Sched.realmName(R()), "MarketplaceService:PromptGamePassPurchase(" .. tostring(id) .. ") — prompt shown", {})
		end,
		PromptPurchase = function(u)
			self(u, "PromptPurchase")
		end,
		UserOwnsGamePassAsync = function(u)
			self(u, "UserOwnsGamePassAsync")
			Sched.wait(0.05, "UserOwnsGamePassAsync")
			return false
		end,
		PlayerOwnsAsset = function(u)
			self(u, "PlayerOwnsAsset")
			Sched.wait(0.05, "PlayerOwnsAsset")
			return false
		end,
		GetProductInfo = function(u, id)
			self(u, "GetProductInfo")
			Sched.wait(0.05, "GetProductInfo")
			return { Name = "Product " .. tostring(id), Description = "", PriceInRobux = 0, IsForSale = false, AssetId = id, ProductId = id }
		end,
	},
})

define("BadgeService", {
	methods = {
		AwardBadge = function(u)
			self(u, "AwardBadge")
			onlyServer("BadgeService:AwardBadge")
			Sched.wait(0.05, "AwardBadge")
			return true
		end,
		UserHasBadgeAsync = function(u)
			self(u, "UserHasBadgeAsync")
			Sched.wait(0.05, "UserHasBadgeAsync")
			return false
		end,
		GetBadgeInfoAsync = function(u, id)
			self(u, "GetBadgeInfoAsync")
			Sched.wait(0.05, "GetBadgeInfoAsync")
			return { Name = "Badge", Description = "", IconImageId = 0, IsEnabled = true }
		end,
	},
})

define("PolicyService", {
	methods = {
		GetPolicyInfoForPlayerAsync = function(u)
			self(u, "GetPolicyInfoForPlayerAsync")
			Sched.wait(0.05, "GetPolicyInfoForPlayerAsync")
			return {
				AreAdsAllowed = false,
				ArePaidRandomItemsRestricted = false,
				AllowedExternalLinkReferences = {},
				IsPaidItemTradingAllowed = true,
				IsSubjectToChinaPolicies = false,
				IsContentSharingAllowed = true,
			}
		end,
	},
})

define("PhysicsService", {
	methods = {
		RegisterCollisionGroup = function(u, name)
			local d = self(u, "RegisterCollisionGroup")
			d.groups = d.groups or {}
			d.groups[name] = true
		end,
		UnregisterCollisionGroup = function(u, name)
			local d = self(u, "UnregisterCollisionGroup")
			if d.groups then
				d.groups[name] = nil
			end
		end,
		IsCollisionGroupRegistered = function(u, name)
			local d = self(u, "IsCollisionGroupRegistered")
			return name == "Default" or (d.groups ~= nil and d.groups[name] == true)
		end,
		CollisionGroupSetCollidable = function(u, a, b, on)
			local d = self(u, "CollisionGroupSetCollidable")
			for _, n in { a, b } do
				if n ~= "Default" and not (d.groups and d.groups[n]) then
					throw("runtime", "CollisionGroupSetCollidable: collision group '" .. tostring(n) .. "' is not registered")
				end
			end
		end,
		CollisionGroupsAreCollidable = function()
			return true
		end,
		GetRegisteredCollisionGroups = function(u)
			local d = self(u, "GetRegisteredCollisionGroups")
			local out = { { name = "Default", mask = 0 } }
			for n in d.groups or {} do
				table.insert(out, { name = n, mask = 0 })
			end
			return out
		end,
		GetMaxCollisionGroups = function()
			return 32
		end,
	},
})

define("LocalizationService", {
	getters = {
		-- on a client: its player's locale (Player.LocaleId); on the server: "en-us"
		RobloxLocaleId = function(_, realm)
			local r = realm or R()
			local pd = r and r.kind == "client" and r.playerD
			return if pd then pd.locale or "en-us" else "en-us"
		end,
		SystemLocaleId = function(_, realm)
			local r = realm or R()
			local pd = r and r.kind == "client" and r.playerD
			return if pd then pd.locale or "en-us" else "en-us"
		end,
	},
})

define("SocialService", {
	methods = {
		CanSendGameInviteAsync = function()
			Sched.wait(0.05, "CanSendGameInviteAsync")
			return false
		end,
		PromptGameInvite = function() end,
	},
})

define("AnalyticsService", {
	methods = {
		LogCustomEvent = function() end,
		LogEconomyEvent = function() end,
		LogFunnelStepEvent = function() end,
		LogOnboardingFunnelStepEvent = function() end,
		LogProgressionEvent = function() end,
		LogProgressionStartEvent = function() end,
		LogProgressionCompleteEvent = function() end,
		LogProgressionFailEvent = function() end,
	},
})

define("UserGameSettings", {
	getters = {
		SavedQualityLevel = function()
			return Enum.SavedQualitySetting.Automatic
		end,
		MasterVolume = function()
			return 1
		end,
	},
})

return Services
