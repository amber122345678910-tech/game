--!nocheck
-- Проверка собранного места (Lune): структура, скрипты, события, карта и метки.
-- Запуск: lune run tools/verify_place.luau LightningCatchers.rbxl
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local path = process.args[1] or "LightningCatchers.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local errors, warnings = {}, {}
local function check(cond, msg)
	if not cond then
		table.insert(errors, msg)
	end
end
local function warnIf(cond, msg)
	if cond then
		table.insert(warnings, msg)
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

-- Обязательные скрипты
local required = {
	{ SSS, "Server.Main", "Script" },
	{ SSS, "Server.Services.DataService", "ModuleScript" },
	{ SSS, "Server.Services.PlayerService", "ModuleScript" },
	{ SSS, "Server.Services.EconomyService", "ModuleScript" },
	{ SSS, "Server.Services.StrikeService", "ModuleScript" },
	{ RS, "Shared.Config", "ModuleScript" },
	{ RS, "Shared.Strikes", "ModuleScript" },
	{ RS, "Shared.Economy", "ModuleScript" },
	{ RS, "Shared.Zones", "ModuleScript" },
	{ RS, "Shared.Net", "ModuleScript" },
	{ RS, "Shared.PlayerData", "ModuleScript" },
	{ SP, "StarterPlayerScripts.Client.Main", "LocalScript" },
	{ SP, "StarterPlayerScripts.Client.ClientState", "ModuleScript" },
}
for _, e in required do
	local inst = find(e[1], e[2])
	check(inst ~= nil, "нет скрипта " .. e[2])
	if inst then
		check(inst.ClassName == e[3], e[2] .. " должен быть " .. e[3] .. ", а не " .. inst.ClassName)
		check(#inst.Source > 50, e[2] .. " пустой")
	end
end

-- Все скрипты: строгий режим, без устаревших API
local deprecated = { "wait%(", "spawn%(", "delay%(", "RenderStepped", "FindPartOnRay", "Instance%.new%([^)]*,", "TweenPosition", "TweenSize", ":connect%(", "game%.Players%.LocalPlayer" }
local scriptCount, lineCount = 0, 0
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		scriptCount += 1
		local src = d.Source
		check(string.sub(src, 1, 9) == "--!strict", d:GetFullName() .. " без --!strict")
		for line in string.gmatch(src, "[^\n]+") do
			lineCount += 1
			local code = string.gsub(line, "%-%-.*$", "")
			for _, pattern in deprecated do
				if string.find(code, "[^%w_%.:]" .. pattern) or string.find(code, "^" .. pattern) then
					table.insert(errors, d:GetFullName() .. ": устаревшее API " .. pattern .. " :: " .. line)
				end
			end
		end
	end
end

-- Удалённые события
local remotes = RS:FindFirstChild("Remotes")
check(remotes ~= nil, "нет ReplicatedStorage.Remotes")
if remotes then
	for _, name in { "DataSync", "StrikeSpawn", "StrikeResult", "Catch", "ShardSpawn", "ShardCollect", "Notify", "Banner", "Effect" } do
		local r = remotes:FindFirstChild(name)
		check(r and r.ClassName == "RemoteEvent", "Remote " .. name .. " должен быть RemoteEvent")
	end
	local bolt = remotes:FindFirstChild("BoltFX")
	check(bolt and bolt.ClassName == "UnreliableRemoteEvent", "BoltFX должен быть UnreliableRemoteEvent")
	local req = remotes:FindFirstChild("Request")
	check(req and req.ClassName == "RemoteFunction", "Request должен быть RemoteFunction")
end

-- Карта и метки
local map = WS:FindFirstChild("Map")
check(map ~= nil, "нет Workspace.Map")
local partCount, unanchored, shadowSmall = 0, 0, 0
if map then
	local markers = map:FindFirstChild("Markers")
	check(markers ~= nil, "нет Map.Markers")
	if markers then
		local names = { "Tower_Top" }
		for i = 0, 5 do
			table.insert(names, "Spawn_" .. i)
			table.insert(names, "SellPad_" .. i)
		end
		for i = 2, 5 do
			table.insert(names, "Gate_" .. i)
		end
		for _, k in { "Shop", "Hatchery", "Gallery", "Rebirth", "Daily" } do
			table.insert(names, "Kiosk_" .. k)
		end
		for _, c in { "meadow", "ice", "storm" } do
			table.insert(names, "Cocoon_" .. c)
		end
		for i = 1, 12 do
			table.insert(names, "Pedestal_" .. i)
		end
		for _, b in { "Board_Leaders", "Board_Forecast", "Board_Hall" } do
			table.insert(names, b)
		end
		for _, n in names do
			local m = markers:FindFirstChild(n)
			check(m ~= nil, "нет метки " .. n)
			if m and m:IsA("BasePart") then
				check(m.Transparency >= 0.99 and not m.CanCollide, "метка " .. n .. " должна быть невидимой и без коллизий")
			end
		end
	end
	local city = map:FindFirstChild("City")
	check(city ~= nil, "нет Map.City")
	if city then
		for i = 1, 6 do
			local dist = city:FindFirstChild("District_" .. i)
			check(dist ~= nil, "нет квартала District_" .. i)
			if dist then
				local windows = 0
				for _, w in dist:GetDescendants() do
					if w:IsA("BasePart") and w:GetAttribute("OnColor") then
						windows += 1
					end
				end
				check(windows > 0, "в District_" .. i .. " нет окон с OnColor")
			end
		end
	end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			partCount += 1
			if not d.Anchored then
				unanchored += 1
			end
			local s = d.Size
			if d.CastShadow and math.max(s.X, s.Y, s.Z) < 2 then
				shadowSmall += 1
			end
		end
	end
	check(unanchored == 0, unanchored .. " незакреплённых деталей на карте")
	warnIf(partCount > 9000, "много деталей на карте: " .. partCount)
	warnIf(shadowSmall > 200, shadowSmall .. " мелких деталей отбрасывают тень (дорого на телефонах)")
end

-- Освещение
check(Lighting:FindFirstChildOfClass("Atmosphere") ~= nil, "нет Atmosphere")
check(Lighting:FindFirstChildOfClass("BloomEffect") ~= nil, "нет Bloom")
check(Lighting:FindFirstChildOfClass("Sky") ~= nil, "нет Sky")

-- Звуки: все ID в формате rbxassetid://число
local soundSrc = find(RS, "Shared.SoundIds")
if soundSrc then
	for id in string.gmatch(soundSrc.Source, "id%((%d+)%)") do
		check(#id >= 5, "подозрительный ID звука " .. id)
	end
end

print(string.format("Скриптов: %d, строк кода: %d, деталей карты: %d", scriptCount, lineCount, partCount))
for _, w in warnings do
	print("ПРЕДУПРЕЖДЕНИЕ: " .. w)
end
if #errors > 0 then
	for _, e in errors do
		print("ОШИБКА: " .. e)
	end
	process.exit(1)
end
print("Место в порядке")
