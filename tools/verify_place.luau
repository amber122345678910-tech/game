--!nocheck
-- Проверка собранного места (Lune): скрипты, события, карта, настройки.
-- Запуск: .tools/lune run tools/verify_place.luau AmberAlert.rbxl
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local path = process.args[1] or "AmberAlert.rbxl"
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
local SoundService = game:GetService("SoundService")

local expected = {
	{ SSS, "Server.Main", "Script" },
	{ SSS, "Server.Services.World", "ModuleScript" },
	{ SSS, "Server.Services.DataService", "ModuleScript" },
	{ SSS, "Server.Services.PlayerService", "ModuleScript" },
	{ SSS, "Server.Services.HouseService", "ModuleScript" },
	{ SSS, "Server.Services.AppleService", "ModuleScript" },
	{ SSS, "Server.Services.ItemService", "ModuleScript" },
	{ SSS, "Server.Services.NoiseService", "ModuleScript" },
	{ SSS, "Server.Services.ServerSounds", "ModuleScript" },
	{ SSS, "Server.Services.R15Rig", "ModuleScript" },
	{ SSS, "Server.Services.InmateAI", "ModuleScript" },
	{ SSS, "Server.Services.InmateService", "ModuleScript" },
	{ SSS, "Server.Services.RoundService", "ModuleScript" },
	{ RS, "Shared.Config", "ModuleScript" },
	{ RS, "Shared.Inmates", "ModuleScript" },
	{ RS, "Shared.Remotes", "ModuleScript" },
	{ RS, "Shared.Signal", "ModuleScript" },
	{ RS, "Shared.Locale", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Main", "LocalScript" },
	{ SP, "StarterPlayerScripts.Client.ClientState", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.UIKit", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.Theme", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.HUD", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.AlertUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.ShopUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.LobbyUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.ResultsUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.SettingsUI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.Notifications", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.UI.Tips", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Camera", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Movement", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Flashlight", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Footsteps", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Interaction", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Hiding", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Spectate", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.FX", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Controllers.Ambience", "ModuleScript" },
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

local deprecated = { "wait%(", "spawn%(", "delay%(", "RenderStepped", "FindPartOnRay", "Instance%.new%([^)]*,", "TweenPosition", "TweenSize", "Humanoid:LoadAnimation" }
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
for _, name in { "Ready", "VoteDifficulty", "VoteSkipAlert", "Interact", "SellApples", "UseItem", "DropItem", "SetFlashlight", "SetCrouch", "SetSprint", "HoldBreath", "LookingAt", "SaveSettings", "State", "Alert", "Inventory", "PlayerState", "Breath", "InmateEvent", "Notify", "Data", "Result", "FX", "LightsChanged", "Leaderboard" } do
	local r = find(RS, "Remotes." .. name)
	check(r and r.ClassName == "RemoteEvent", "RemoteEvent missing: " .. name)
end
for _, name in { "BuyItem", "BuyPerk" } do
	local r = find(RS, "Remotes." .. name)
	check(r and r.ClassName == "RemoteFunction", "RemoteFunction missing: " .. name)
end
local noise = find(RS, "Remotes.Noise")
check(noise and noise.ClassName == "UnreliableRemoteEvent", "Noise must be UnreliableRemoteEvent")

-- Карта
local house = WS:FindFirstChild("House")
check(house ~= nil, "Workspace.House missing")
if house then
	local function count(folderName)
		local f = house:FindFirstChild(folderName)
		return f and #f:GetChildren() or 0
	end
	for _, id in { "FrontDoor", "BackDoor", "GarageSide", "GarageKitchen", "LaundryDoor", "BasementDoor", "KidRoomDoor", "ParentsRoomDoor", "OfficeDoor" } do
		local d = find(house, "Doors." .. id)
		check(d ~= nil, "door missing " .. id)
		if d then
			check(d:FindFirstChild("Hinge") and d:FindFirstChild("Panel"), id .. " needs Hinge and Panel")
			check(d:GetAttribute("DoorId") == id, id .. " DoorId attribute")
		end
	end
	for _, id in { "Living1", "Living2", "Kitchen1", "Dining1", "Laundry1" } do
		local w = find(house, "Windows." .. id)
		check(w ~= nil, "window missing " .. id)
		if w then
			check(w:FindFirstChild("Glass") and w:FindFirstChild("Board1") and w:FindFirstChild("Board3"), id .. " needs Glass/Boards")
		end
	end
	for _, id in { "ClosetKid", "ClosetParents", "ClosetOffice", "BedKid", "BoxesBasement", "Shed" } do
		local h = find(house, "HidingSpots." .. id)
		check(h ~= nil, "hiding spot missing " .. id)
		if h then
			check(h:FindFirstChild("HidePoint") and h:FindFirstChild("CamPoint"), id .. " needs HidePoint/CamPoint")
			check(h:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil, id .. " needs Prompt")
		end
	end
	for _, room in { "Foyer", "Living", "Kitchen", "Dining", "Laundry", "BackHall", "Garage", "KidRoom", "ParentsRoom", "UpperHall", "Office", "Bathroom", "Basement", "Porch", "Shed" } do
		local l = find(house, "Lights." .. room)
		check(l ~= nil, "light missing " .. room)
		if l then
			check(l:FindFirstChild("Bulb") ~= nil, room .. " light needs Bulb")
			check(l:FindFirstChild("Switch") ~= nil, room .. " light needs Switch")
		end
	end
	for i = 1, 8 do
		check(find(house, "Trees.Slot" .. i) ~= nil, "tree slot missing " .. i)
	end
	check(count("Rooms") >= 15, "rooms: " .. count("Rooms"))
	check((find(house, "Nav.Waypoints") and #find(house, "Nav.Waypoints"):GetChildren() or 0) >= 25, "waypoints < 25")
	check((find(house, "Nav.Entries") and #find(house, "Nav.Entries"):GetChildren() or 0) >= 8, "entries < 8")
	check((find(house, "Nav.InmateSpawns") and #find(house, "Nav.InmateSpawns"):GetChildren() or 0) >= 3, "inmate spawns < 3")
	check(count("Spawns") >= 8, "player spawns < 8")
	for _, name in { "Shop", "TV", "Fusebox", "Phone", "Templates" } do
		check(house:FindFirstChild(name) ~= nil, "house." .. name .. " missing")
	end
	check(find(house, "Templates.Tree") and find(house, "Templates.Apple"), "templates Tree/Apple")
end
local lobby = WS:FindFirstChild("Lobby")
check(lobby ~= nil, "Workspace.Lobby missing")
if lobby then
	local spawns = lobby:FindFirstChild("Spawns")
	check(spawns and #spawns:GetChildren() >= 8, "lobby spawns < 8")
	check(lobby:FindFirstChild("ReadyPad") ~= nil, "ReadyPad missing")
	check(lobby:FindFirstChild("PerkKiosk") ~= nil, "PerkKiosk missing")
end

local partCount, unanchored = 0, 0
for _, d in WS:GetDescendants() do
	if d:IsA("BasePart") then
		partCount += 1
		if not d.Anchored then
			unanchored += 1
		end
	end
end
check(unanchored == 0, unanchored .. " unanchored parts in Workspace")

check(WS.StreamingEnabled == false, "StreamingEnabled should be false")
check(Lighting.GlobalShadows == true, "GlobalShadows should be true")
check(Lighting:FindFirstChildOfClass("Atmosphere") ~= nil, "Atmosphere missing")
check(Lighting.ClockTime < 1, "ClockTime should be midnight")
for _, g in { "Music", "SFX", "Ambience", "UI" } do
	check(SoundService:FindFirstChild(g) ~= nil, "SoundGroup missing " .. g)
end
check(SP.CameraMode == roblox.Enum.CameraMode.Classic, "CameraMode should be Classic (first person is set by the client in matches)")

print(string.format("Place: %d scripts checked, %d parts in Workspace", scriptCount, partCount))
if #errors > 0 then
	for _, e in errors do
		print("ERROR: " .. e)
	end
	error(#errors .. " verification errors")
end
print("Place verification OK")
