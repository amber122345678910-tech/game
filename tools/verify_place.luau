--!nocheck
-- Проверка собранного места (Lune): структура, скрипты, события, участки.
-- Запуск: lune run tools/verify_place.luau BunkerSimulator.rbxl
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local path = process.args[1] or "BunkerSimulator.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local errors = {}
local function check(cond, msg)
	if not cond then
		table.insert(errors, msg)
	end
end

local function find(root, pathStr)
	local node = root
	for name in string.gmatch(pathStr, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer")
local WS = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

-- Скрипты
local expected = {
	{ SSS, "Server.Main", "Script" },
	{ SSS, "Server.Services.DataService", "ModuleScript" },
	{ SSS, "Server.Services.PlotService", "ModuleScript" },
	{ SSS, "Server.Services.BuildService", "ModuleScript" },
	{ SSS, "Server.Services.ShopService", "ModuleScript" },
	{ SSS, "Server.Services.StormService", "ModuleScript" },
	{ SSS, "Server.Services.TutorialService", "ModuleScript" },
	{ RS, "Shared.Config", "ModuleScript" },
	{ RS, "Shared.Grid", "ModuleScript" },
	{ RS, "Shared.Prefabs", "ModuleScript" },
	{ RS, "Shared.Remotes", "ModuleScript" },
	{ RS, "Shared.Signal", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Main", "LocalScript" },
	{ SP, "StarterPlayerScripts.Client.ClientState", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.HUD", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.ShopUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.UIKit", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.Theme", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.TutorialUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.ResultsUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.BuildController", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.StormFX", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Waypoint", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.DoorController", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Sounds", "ModuleScript" },
}
local scriptCount = 0
for _, e in expected do
	local inst = find(e[1], e[2])
	check(inst ~= nil, "missing " .. e[2])
	if inst then
		check(inst.ClassName == e[3], e[2] .. " should be " .. e[3] .. " but is " .. inst.ClassName)
		check(#inst.Source > 50, e[2] .. " has empty source")
		scriptCount += 1
	end
end
-- Все скрипты: строгий режим и без устаревших API
local deprecated = { "wait%(", "spawn%(", "delay%(", "RenderStepped", "FindPartOnRay", "Instance%.new%([^)]*,", "TweenPosition", "TweenSize" }
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		local src = d.Source
		check(string.sub(src, 1, 9) == "--!strict", d:GetFullName() .. " is not --!strict")
		for _, pattern in deprecated do
			for line in string.gmatch(src, "[^\n]+") do
				local code = string.gsub(line, "%-%-.*$", "")
				if string.find(code, "[^%w_%.:]" .. pattern) or string.find(code, "^" .. pattern) then
					table.insert(errors, d:GetFullName() .. " uses deprecated API: " .. pattern .. " :: " .. line)
				end
			end
		end
	end
end

-- События
local hail = find(RS, "Remotes.HailBatch")
check(hail and hail.ClassName == "UnreliableRemoteEvent", "HailBatch must be an UnreliableRemoteEvent")
for _, name in { "PlaceBlock", "RemoveBlock", "ClearPlot", "StartStorm", "TutorialDone", "DataUpdated", "Notify", "BlockBroken", "StormResult" } do
	local r = find(RS, "Remotes." .. name)
	check(r and r.ClassName == "RemoteEvent", "RemoteEvent missing: " .. name)
end
local purchase = find(RS, "Remotes.Purchase")
check(purchase and purchase.ClassName == "RemoteFunction", "RemoteFunction Purchase missing")

-- Участки
local plots = WS:FindFirstChild("Plots")
check(plots ~= nil, "Workspace.Plots missing")
local ids = {}
if plots then
	for _, plot in plots:GetChildren() do
		local id = plot:GetAttribute("PlotId")
		local origin = plot:GetAttribute("Origin")
		check(typeof(id) == "number", plot.Name .. " has no PlotId")
		check(typeof(origin) == "CFrame", plot.Name .. " has no Origin CFrame")
		check(plot:FindFirstChild("Blocks") ~= nil, plot.Name .. " has no Blocks folder")
		check(plot:FindFirstChild("Storm") ~= nil, plot.Name .. " has no Storm folder")
		check(plot:FindFirstChild("TerrainPreview") == nil, plot.Name .. " still has TerrainPreview")
		check(plot:FindFirstChild("Sign") ~= nil, plot.Name .. " has no Sign")
		check(plot:FindFirstChild("Environment") ~= nil, plot.Name .. " has no Environment")
		if typeof(id) == "number" then
			check(not ids[id], "duplicate PlotId " .. id)
			ids[id] = true
		end
		if typeof(origin) == "CFrame" then
			local look = origin.LookVector
			-- участок должен смотреть на лобби (к центру по Z)
			local toCenter = -origin.Position.Z
			check(look.Z * toCenter > 0, plot.Name .. " does not face the lobby")
			check(math.abs(origin.UpVector.Y - 1) < 1e-4, plot.Name .. " is tilted")
		end
	end
	check(#plots:GetChildren() == 8, "expected 8 plots, got " .. #plots:GetChildren())
end

-- Карта
local map = WS:FindFirstChild("Map")
check(map ~= nil, "Workspace.Map missing")
local spawn = map and map:FindFirstChild("LobbySpawn", true)
check(spawn and spawn.ClassName == "SpawnLocation", "SpawnLocation missing")
local prompt = map and map:FindFirstChild("ShopPrompt", true)
check(prompt and prompt.ClassName == "ProximityPrompt", "ShopPrompt missing")
local partCount = 0
local unanchored = 0
for _, d in WS:GetDescendants() do
	if d:IsA("BasePart") then
		partCount += 1
		if not d.Anchored then
			unanchored += 1
		end
	end
end
check(unanchored == 0, unanchored .. " unanchored parts in Workspace")

-- Настройки
check(WS.StreamingEnabled == false, "StreamingEnabled should be false")
check(Lighting.GlobalShadows == true, "GlobalShadows should be true")
check(Lighting:FindFirstChildOfClass("Atmosphere") ~= nil, "Atmosphere missing")

print(string.format("Place: %d scripts checked, %d parts in Workspace, %d plots", scriptCount, partCount, plots and #plots:GetChildren() or 0))
if #errors > 0 then
	for _, e in errors do
		print("ERROR: " .. e)
	end
	error(#errors .. " verification errors")
end
print("Place verification OK")
