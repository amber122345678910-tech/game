-- Lune: проверка собранного place-файла (rojo build) — что Studio получит именно то, что нужно.
-- Запуск: rojo build default.project.json -o build/StretchPop.rbxlx && lune run tests/place_check.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local place = roblox.deserializePlace(fs.readFile("build/StretchPop.rbxlx"))
local failures = 0

local function expect(condition: any, message: string)
	if condition then
		print("  ✓ " .. message)
	else
		failures += 1
		print("  ✗ " .. message)
	end
end

local function find(path: string): any
	local current: any = place
	for segment in string.gmatch(path, "[^%.]+") do
		current = current:FindFirstChild(segment)
		if current == nil then
			return nil
		end
	end
	return current
end

local function scriptOk(path: string, className: string)
	local instance = find(path)
	expect(
		instance ~= nil and instance.ClassName == className and #instance.Source > 50 and string.find(instance.Source, "--!strict", 1, true) == 1,
		string.format("%s is a %s with --!strict source", path, className)
	)
end

print("▶ place structure")
scriptOk("ServerScriptService.Server.Main", "Script")
scriptOk("ServerScriptService.Server.Services.KineticLevelAndRebirthService", "ModuleScript")
scriptOk("ServerScriptService.Server.Services.PlayerDataService", "ModuleScript")
scriptOk("ServerScriptService.Server.Services.StretchReplicationService", "ModuleScript")
scriptOk("ServerScriptService.Server.Level.LevelBuilder", "ModuleScript")
scriptOk("StarterPlayer.StarterPlayerScripts.Client.Main", "LocalScript")
scriptOk("StarterPlayer.StarterPlayerScripts.Client.Controllers.ElasticSlingshotController", "ModuleScript")
scriptOk("StarterPlayer.StarterPlayerScripts.Client.Controllers.ShoulderCameraController", "ModuleScript")
scriptOk("StarterPlayer.StarterPlayerScripts.Client.Controllers.KineticLevelClient", "ModuleScript")
scriptOk("StarterPlayer.StarterPlayerScripts.Client.Effects.KineticVFX", "ModuleScript")
for _, name in { "Types", "Net", "Config.PhysicsConfig", "Config.LevelConfig", "Config.GloveConfig", "Math.Bezier", "Math.Spring", "Physics.StretchPhysics", "Util.Signal", "Data.ProfileTemplate" } do
	scriptOk("ReplicatedStorage.Shared." .. name, "ModuleScript")
end

print("▶ remotes")
for _, name in { "SmashRequest", "SmashResult", "ObstacleSmashed", "GongStrike", "GongResult", "RebirthWave", "ControllerReset", "ArmVisual", "PeerArmVisual" } do
	local remote = find("ReplicatedStorage.StretchPopNet." .. name)
	expect(remote ~= nil and remote.ClassName == "RemoteEvent", "RemoteEvent " .. name)
end

print("▶ settings")
local playersService = find("Players")
expect(playersService and playersService.CharacterAutoLoads == false, "Players.CharacterAutoLoads = false (персонаж после загрузки профиля)")
local starterPlayer = find("StarterPlayer")
expect(starterPlayer and starterPlayer.EnableMouseLockOption == false, "StarterPlayer.EnableMouseLockOption = false")
local lighting = find("Lighting")
expect(lighting and lighting.Technology == roblox.Enum.Technology.ShadowMap, "Lighting.Technology = ShadowMap (лёгкий для слабых ПК)")
expect(find("Lighting.Bloom") and find("Lighting.ColorCorrection") and find("Lighting.Atmosphere"), "post effects present")
local spawn = find("Workspace.StretchPopSpawn")
expect(spawn and spawn.ClassName == "SpawnLocation" and spawn.Neutral == true, "neutral SpawnLocation")

print(string.format("\n%d failures", failures))
process.exit(if failures == 0 then 0 else 1)
