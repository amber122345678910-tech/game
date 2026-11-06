-- Интеграционная симуляция СЕРВЕРА: вход игрока → полоса → спавн → честное пробитие →
-- отклонение читов → респаун стены → удар в Гонг → Rebirth и мутация локации волной.
-- Запуск: lune run tests/server_sim.luau
local process = require("@lune/process")
local task = require("@lune/task")
local Engine = require("./engine")
local H = Engine.H
local roblox = H.roblox
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local PlayerDataService = H.require("ServerScriptService.Server.Services.PlayerDataService")
local Kinetic = H.require("ServerScriptService.Server.Services.KineticLevelAndRebirthService")
local Replication = H.require("ServerScriptService.Server.Services.StretchReplicationService")
local LevelConfig = H.require("ReplicatedStorage.Shared.Config.LevelConfig")
local LevelBuilder = H.require("ServerScriptService.Server.Level.LevelBuilder")
local StretchPhysics = H.require("ReplicatedStorage.Shared.Physics.StretchPhysics")
local PhysicsConfig = H.require("ReplicatedStorage.Shared.Config.PhysicsConfig")
local GloveConfig = H.require("ReplicatedStorage.Shared.Config.GloveConfig")
local Progression = H.require("ServerScriptService.Server.Services.ProgressionService")

local game = Engine.game
local workspace = Engine.workspace
local players = game:GetService("Players")
local DT = 1 / 60

local function settle()
	for _ = 1, 6 do
		task.wait(0.01)
	end
end

local function steps(count: number)
	for _ = 1, count do
		Engine.serverStep(DT)
	end
end

PlayerDataService.Init()
Kinetic.Init()
Progression.Init()
Replication.Init()

local player = roblox.Instance.new("Player")
player.Name = "Tester"
player.UserId = 4242
player.Parent = players
Engine.signalFor(players, "PlayerAdded"):Fire(player)
settle()

local root: any = nil
local function laneModel(): any
	return workspace.StretchPopWorld.Lanes:FindFirstChild("Lane_1")
end

local function moveRoot(to: any, speed: number)
	local from = root.CFrame.Position
	local distance = (to - from).Magnitude
	local count = math.max(1, math.ceil(distance / speed / DT))
	for index = 1, count do
		root.CFrame = CFrame.new(from:Lerp(to, index / count))
		Engine.serverStep(DT)
	end
end

local function lastResult(remote: string, id: string?): any
	return Engine.findLog(remote, function(entry)
		return id == nil or entry.Args[1] == id
	end)
end

H.suite("Server · join → lane → spawn")
H.test("offline profile, lane built, character spawned on own start pad", function()
	H.check(PlayerDataService.Get(player) ~= nil, "profile missing")
	H.check(PlayerDataService.IsOffline(), "harness must run in offline data mode")
	H.check(player:GetAttribute("LaneSlot") == 1, "lane slot")
	H.check(player:GetAttribute("Coins") == 0 and player:GetAttribute("LocationTier") == 0, "replicated attributes")
	H.check(player:FindFirstChild("leaderstats") ~= nil, "leaderstats")
	H.check(laneModel() ~= nil, "lane model")
	root = player.Character:FindFirstChild("HumanoidRootPart")
	local start = LevelBuilder.StartCFrame(1)
	H.check((root.CFrame.Position - start.Position).Magnitude < 0.5, "spawned at lane start")
	H.check(Engine.findLog("ControllerReset") ~= nil, "client was told where to stand")
end)

steps(120) -- окно «игнорирования» трекера после спавна

-- Цель: самая слабая стена (по прочности)
local function pickObstacle(kind: string, strongest: boolean): any
	local best = nil
	for _, part in laneModel().Obstacles:GetChildren() do
		if part:GetAttribute("ObstacleKind") == kind then
			local durability = part:GetAttribute("Durability")
			if best == nil or (strongest and durability > best:GetAttribute("Durability")) or (not strongest and durability < best:GetAttribute("Durability")) then
				best = part
			end
		end
	end
	return best
end

local wall = pickObstacle("Wall", false)
local wallId = wall:GetAttribute("ObstacleId")
local need = StretchPhysics.SpeedToBreak(wall:GetAttribute("Durability"), 1)
local wallFront = wall.CFrame.Position + Vector3.new(0, 3 - wall.CFrame.Position.Y, wall.Size.Z * 0.5 + 2.4)

H.suite("Server · honest smash")
H.test("walk up, accelerate, smash: accepted, loot paid, wall removed for everyone", function()
	moveRoot(wallFront + Vector3.new(0, 0, 60), 16)
	local speed = need * 1.3
	moveRoot(wallFront, speed)
	local before = player:GetAttribute("Coins")
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, wallId, Vector3.new(0, 0, -speed), wallFront, speed, 1)
	steps(3)
	local result = lastResult("SmashResult", wallId)
	H.check(result ~= nil and result.Args[2] == true, "smash should be accepted, got " .. tostring(result and result.Args[4]))
	H.check(wall.Parent == game:GetService("ServerStorage").StretchPopBroken, "wall moved out of workspace")
	H.check(player:GetAttribute("Coins") == before + wall:GetAttribute("Loot"), "loot paid")
	H.check(Engine.findLog("ObstacleSmashed") ~= nil, "VFX broadcast")
end)

H.suite("Server · anti-cheat")
H.test("claimed speed far above observed motion is rejected after the wait window", function()
	local strong = pickObstacle("Wall", true)
	local id = strong:GetAttribute("ObstacleId")
	local front = strong.CFrame.Position + Vector3.new(0, 3 - strong.CFrame.Position.Y, strong.Size.Z * 0.5 + 2.4)
	moveRoot(front + Vector3.new(0, 0, 20), 30)
	moveRoot(front, 30)
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, id, Vector3.new(0, 0, -600), front, 600, 1)
	steps(50)
	local result = lastResult("SmashResult", id)
	H.check(result ~= nil and result.Args[2] == false, "should be rejected")
	H.check(result.Args[4] == "speed_unverified", "reason: " .. tostring(result.Args[4]))
	H.check(strong.Parent == laneModel().Obstacles, "wall must stay")
end)
H.test("honest-but-too-slow hit is rejected immediately as too_weak", function()
	local strong = pickObstacle("Wall", true)
	local id = strong:GetAttribute("ObstacleId")
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, id, Vector3.new(0, 0, -20), root.CFrame.Position, 20, 1)
	steps(1)
	local result = lastResult("SmashResult", id)
	H.check(result.Args[4] == "too_weak", "reason: " .. tostring(result.Args[4]))
end)
H.test("garbage payloads are ignored, unknown ids rejected", function()
	local count = #Engine.remoteLog
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, 12345, "nope", nil, 0 / 0, {})
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, wallId, Vector3.new(0 / 0, 0, 0), Vector3.zero, 10, 1)
	steps(1)
	H.check(#Engine.remoteLog == count, "malformed requests must not produce any reply")
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, "T0-9999", Vector3.new(0, 0, -100), Vector3.zero, 100, 1)
	local result = lastResult("SmashResult", "T0-9999")
	H.check(result and result.Args[4] == "unknown_obstacle", "unknown id")
end)
H.test("far from the wall = rejected (distance check)", function()
	local chest = pickObstacle("Chest", false)
	local id = chest:GetAttribute("ObstacleId")
	moveRoot(root.CFrame.Position + Vector3.new(0, 0, 40), 120) -- набираем «честную» скорость, но в стороне
	Engine.remote("SmashRequest").OnServerEvent:Fire(player, id, Vector3.new(0, 0, -120), chest.CFrame.Position, 120, 1)
	steps(50)
	local result = lastResult("SmashResult", id)
	H.check(result and result.Args[2] == false and result.Args[4] == "too_far", "reason: " .. tostring(result and result.Args[4]))
end)

H.suite("Server · respawn")
H.test("smashed wall respawns after ObstacleRespawnTime", function()
	steps(math.ceil(LevelConfig.ObstacleRespawnTime / DT) + 5)
	H.check(wall.Parent == laneModel().Obstacles, "wall should be back")
end)

H.suite("Server · Kinetic Gong Rebirth")
local gong = laneModel().Mutable:FindFirstChild("GongDisc")
local gongFront = gong.CFrame.Position + Vector3.new(0, 0, 4.5)
H.test("too little combo is rejected with requirements", function()
	local needSpeed = LevelConfig.GongRequirement(0)
	moveRoot(gongFront + Vector3.new(0, 0, 80), 40)
	moveRoot(gongFront, needSpeed + 30)
	Engine.remote("GongStrike").OnServerEvent:Fire(player, 1, Vector3.new(0, 0, -(needSpeed + 30)), needSpeed + 30, 0)
	steps(2)
	local result = Engine.findLog("GongResult")
	H.check(result and result.Args[1] == false and result.Args[2] == "combo_too_low", "reason: " .. tostring(result and result.Args[2]))
end)
H.test("fast zig-zag (server sees bounces) + gong hit → Rebirth, tier 1, wave, rebuilt lane", function()
	steps(80) -- кулдаун антиспама
	local needSpeed, needCombo = LevelConfig.GongRequirement(0)
	local speed = needSpeed + 40
	-- зигзаг: резкие развороты на скорости — сервер сам считает «отскоки»
	local base = gongFront + Vector3.new(0, 0, 160)
	moveRoot(base, 40)
	local points = {
		base + Vector3.new(30, 0, -30),
		base + Vector3.new(-30, 0, -60),
		base + Vector3.new(30, 0, -90),
		base + Vector3.new(-20, 0, -120),
		gongFront,
	}
	for _, point in points do
		moveRoot(point, speed)
	end
	local coinsBefore = player:GetAttribute("Coins")
	Engine.remote("GongStrike").OnServerEvent:Fire(player, 1, Vector3.new(0, 0, -speed), speed, needCombo + 1)
	steps(3)
	local result = Engine.findLog("GongResult")
	H.check(result and result.Args[1] == true, "gong should accept, reason: " .. tostring(result and result.Args[2]))
	H.check(player:GetAttribute("LocationTier") == 1 and player:GetAttribute("TotalRebirths") == 1, "tier/rebirth attrs")
	H.check(player:GetAttribute("Coins") > coinsBefore, "rebirth bonus")
	local wave = Engine.findLog("RebirthWave")
	H.check(wave and wave.Args[1].Tier == 1 and wave.Args[1].Slot == 1, "wave broadcast")
	-- волна проходит всю полосу
	local info = wave.Args[1]
	local duration = LevelConfig.Rebirth.StartDelay + (info.EndZ - info.OriginZ) / info.Speed + 1
	steps(math.ceil(duration / DT))
	local lane = laneModel()
	local tierOneObstacles, staleObstacles = 0, 0
	for _, part in lane.Obstacles:GetChildren() do
		local id = part:GetAttribute("ObstacleId")
		if string.sub(id, 1, 3) == "T1-" then
			tierOneObstacles += 1
		else
			staleObstacles += 1
		end
	end
	H.check(tierOneObstacles == #LevelBuilder.GenerateLayout("Meadows", 1).Obstacles, "all tier-1 obstacles built: " .. tierOneObstacles)
	H.check(staleObstacles == 0, "old obstacles removed: " .. staleObstacles)
	H.check(lane:GetAttribute("Tier") == 1, "lane tier attribute")
	H.check(lane.Mutable:FindFirstChild("GongDisc") ~= nil, "new gong exists")
	H.check(lane.Static.StartPad.Color == LevelConfig.GetTheme(1).Floor.Color, "start pad rethemed to Golden")
	local reset = Engine.findLog("ControllerReset", function(entry)
		return entry.Time > info.StartServerTime - LevelConfig.Rebirth.StartDelay
	end)
	H.check(reset ~= nil, "player teleported back to start for the wave")
end)

H.suite("Server · progression (stats, gloves, sync)")
local function setCoins(amount: number)
	PlayerDataService.Update(player, function(profile)
		profile.Coins = amount
	end)
end
local function lastReply(remote: string): any
	return Engine.findLog(remote, function(entry)
		return entry.Kind == "FireClient" and entry.Player == player
	end)
end
local function upgrade(stat: any)
	Engine.remote("UpgradeStat").OnServerEvent:Fire(player, stat)
end
local function glove(action: any, gloveId: any)
	Engine.remote("GloveAction").OnServerEvent:Fire(player, action, gloveId)
end

H.test("profile snapshot was pushed on join with owned gloves and records", function()
	local sync = Engine.remoteLog[1]
	for _, entry in Engine.remoteLog do
		if entry.Remote == "ProfileSync" then
			sync = entry
			break
		end
	end
	H.check(sync and sync.Remote == "ProfileSync", "snapshot sent on join")
	local snapshot = sync.Args[1]
	H.check(table.find(snapshot.OwnedGloves, "Rubber") ~= nil and snapshot.EquippedGlove == "Rubber", "default glove")
	H.check(snapshot.Records ~= nil and snapshot.Stats ~= nil and snapshot.DataOffline == true, "records / stats / offline flag")
end)
H.test("upgrade: rejected without coins, accepted at exact cost, attributes replicate", function()
	steps(120)
	setCoins(0)
	upgrade("Elasticity")
	local reply = lastReply("UpgradeStat")
	H.check(reply.Args[1] == "Elasticity" and reply.Args[2] == false and reply.Args[3] == "not_enough_coins", "reason " .. tostring(reply.Args[3]))
	local level = player:GetAttribute("Stat_Elasticity")
	local cost = StretchPhysics.UpgradeCost(level)
	setCoins(cost)
	upgrade("Elasticity")
	reply = lastReply("UpgradeStat")
	H.check(reply.Args[2] == true and reply.Args[4] == level + 1, "accepted to level " .. tostring(reply.Args[4]))
	H.check(player:GetAttribute("Stat_Elasticity") == level + 1, "stat attribute replicated")
	H.check(player:GetAttribute("Coins") == 0 and reply.Args[5] == 0, "exact cost charged")
end)
H.test("max level is enforced server-side", function()
	PlayerDataService.Update(player, function(profile)
		profile.Stats.SmashMass = PhysicsConfig.StatUpgrade.MaxLevel
		profile.Coins = 1e9
	end)
	upgrade("SmashMass")
	local reply = lastReply("UpgradeStat")
	H.check(reply.Args[2] == false and reply.Args[3] == "max_level", "reason " .. tostring(reply.Args[3]))
	H.check(player:GetAttribute("Stat_SmashMass") == PhysicsConfig.StatUpgrade.MaxLevel, "not exceeded")
end)
H.test("junk is ignored; a 40-request burst is capped and never double-spends", function()
	local count = #Engine.remoteLog
	upgrade("Charisma")
	upgrade(42)
	upgrade(nil)
	glove("Hack", "Rubber")
	glove("Buy", string.rep("x", 100))
	H.check(#Engine.remoteLog == count, "junk produced replies")
	PlayerDataService.Update(player, function(profile)
		profile.Stats.SpringPower = 0
		profile.Coins = 1e9
	end)
	steps(120) -- корзина токенов полна
	local before = player:GetAttribute("Stat_SpringPower")
	local logStart = #Engine.remoteLog
	for _ = 1, 40 do
		upgrade("SpringPower")
	end
	local after = player:GetAttribute("Stat_SpringPower")
	local gained = after - before
	H.check(gained >= 9 and gained <= 10, "burst should be capped at the bucket size, gained " .. gained)
	local spent = 0
	for level = before, after - 1 do
		spent += StretchPhysics.UpgradeCost(level)
	end
	-- сверяем с профилем: атрибуты Lune хранят float32 (в Roblox — double), на 1e9 они округляются
	local profileCoins = PlayerDataService.Get(player).Coins
	H.check(profileCoins == 1e9 - spent, string.format("coins match accepted upgrades exactly: %d vs %d", profileCoins, 1e9 - spent))
	local limitedReplies = 0
	for index = logStart + 1, #Engine.remoteLog do
		local entry = Engine.remoteLog[index]
		if entry.Remote == "UpgradeStat" and entry.Args[3] == "rate_limited" then
			limitedReplies += 1
		end
	end
	H.check(limitedReplies <= 1, "flood replies are throttled: " .. limitedReplies)
end)
H.test("gloves: unknown / too expensive / buy auto-equips / already owned / not owned / equip", function()
	steps(120)
	setCoins(0)
	glove("Buy", "NopeGlove")
	H.check(lastReply("GloveAction").Args[4] == "unknown_glove", "unknown")
	glove("Buy", "GoldenGrip")
	H.check(lastReply("GloveAction").Args[4] == "not_enough_coins", "too expensive")
	setCoins(GloveConfig.Gloves.GoldenGrip.Price)
	glove("Buy", "GoldenGrip")
	local reply = lastReply("GloveAction")
	H.check(reply.Args[3] == true and reply.Args[4] == "bought", "bought")
	H.check(player:GetAttribute("Glove") == "GoldenGrip" and player:GetAttribute("Coins") == 0, "auto-equipped, paid")
	glove("Buy", "GoldenGrip")
	H.check(lastReply("GloveAction").Args[4] == "already_owned", "no double buy")
	glove("Equip", "VoidFist")
	H.check(lastReply("GloveAction").Args[4] == "not_owned", "cannot equip unowned")
	glove("Equip", "Rubber")
	reply = lastReply("GloveAction")
	H.check(reply.Args[3] == true and player:GetAttribute("Glove") == "Rubber", "equip owned")
end)
H.test("ProfileSync: request returns fresh snapshot, repeats are debounced into one", function()
	steps(120)
	Engine.remote("ProfileSync").OnServerEvent:Fire(player)
	local sync = lastReply("ProfileSync")
	local owned = sync.Args[1].OwnedGloves
	H.check(table.find(owned, "GoldenGrip") ~= nil and table.find(owned, "Rubber") ~= nil, "owned gloves synced")
	local before = #Engine.remoteLog
	Engine.remote("ProfileSync").OnServerEvent:Fire(player)
	Engine.remote("ProfileSync").OnServerEvent:Fire(player)
	H.check(#Engine.remoteLog == before, "rapid repeats are not answered immediately")
	steps(40)
	local delivered = 0
	for index = before + 1, #Engine.remoteLog do
		if Engine.remoteLog[index].Remote == "ProfileSync" then
			delivered += 1
		end
	end
	H.check(delivered == 1, "exactly one coalesced snapshot, got " .. delivered)
end)

H.suite("Server · world rules")
H.test("falling into the void respawns at lane start", function()
	steps(120)
	local count = #Engine.remoteLog
	root.CFrame = CFrame.new(root.CFrame.Position.X, -150, root.CFrame.Position.Z)
	steps(2)
	local reset = Engine.findLog("ControllerReset")
	H.check(#Engine.remoteLog > count and reset.Args[1] ~= nil, "ControllerReset with target")
end)
H.test("arm visuals are relayed to other players only, with validation", function()
	local other = roblox.Instance.new("Player")
	other.Name = "Friend"
	other.UserId = 777
	other.Parent = players
	Engine.remote("ArmVisual").OnServerEvent:Fire(player, "Left", true, root.CFrame.Position + Vector3.new(0, 0, -30))
	local relay = Engine.findLog("PeerArmVisual")
	H.check(relay and relay.Player == other and relay.Args[1] == player and relay.Args[2] == "Left", "relay to peer")
	local count = #Engine.remoteLog
	Engine.remote("ArmVisual").OnServerEvent:Fire(player, "Hacker", true, nil)
	Engine.remote("ArmVisual").OnServerEvent:Fire(player, "Left", true, root.CFrame.Position + Vector3.new(0, 0, -5000))
	H.check(#Engine.remoteLog == count, "invalid side / far point not relayed")
	other.Parent = nil
end)
H.test("leaving destroys the lane and frees the slot", function()
	Engine.signalFor(players, "PlayerRemoving"):Fire(player)
	settle()
	H.check(laneModel() == nil, "lane destroyed")
end)

local ok = H.summary()
process.exit(if ok then 0 else 1)
