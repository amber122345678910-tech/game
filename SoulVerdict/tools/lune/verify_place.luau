--!nocheck
-- verify_place.luau — sanity checks on a BUILT place file (rojo build output).
-- Usage (from the project root): lune run tools/lune/verify_place.luau SoulVerdict.rbxl
-- Asserts:
--   * ReplicatedStorage.Shared exists; ServerScriptService.Server.Main is a Script;
--     StarterPlayer.StarterPlayerScripts.Client.Main is a LocalScript
--   * Lighting.LightingStyle == Realistic and PrioritizeLightingQuality == true (SPEC §0.3: not scriptable at
--     runtime, so the place file must carry them)
--   * Players.CharacterAutoLoads == false
--   * every LuaSourceContainer's Source starts with --!strict; no script is empty
--   * Script.RunContext is Legacy/Server for server scripts (warn if a Script would also run on the client)
-- Prints a summary (script counts per class and per top-level service). Exit code 1 on any failure.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "SoulVerdict.rbxl"
if not fs.isFile(path) then
	print("verify_place: file not found: " .. path)
	process.exit(1)
end

local ok, game = pcall(roblox.deserializePlace, fs.readFile(path))
if not ok then
	print("verify_place: cannot deserialize " .. path .. ": " .. tostring(game))
	process.exit(1)
end

local failures = {}
local warnings = {}
local function fail(msg)
	table.insert(failures, msg)
end
local function warn(msg)
	table.insert(warnings, msg)
end

local function find(pathString)
	local node = game
	for name in string.gmatch(pathString, "[^%.]+") do
		local child = node:FindFirstChild(name)
		if child == nil then
			return nil
		end
		node = child
	end
	return node
end

local function expect(pathString, className)
	local inst = find(pathString)
	if inst == nil then
		fail(("missing %s"):format(pathString))
	elseif className and inst.ClassName ~= className then
		fail(("%s is a %s, expected %s"):format(pathString, inst.ClassName, className))
	end
	return inst
end

expect("ReplicatedStorage.Shared")
expect("ServerScriptService.Server.Main", "Script")
expect("StarterPlayer.StarterPlayerScripts.Client.Main", "LocalScript")

local lighting = game:FindFirstChildOfClass("Lighting")
if lighting == nil then
	fail("no Lighting service")
else
	local okStyle, style = pcall(function()
		return lighting.LightingStyle
	end)
	if not okStyle then
		fail("cannot read Lighting.LightingStyle: " .. tostring(style))
	elseif style ~= roblox.Enum.LightingStyle.Realistic then
		fail("Lighting.LightingStyle is " .. tostring(style) .. ", expected Enum.LightingStyle.Realistic")
	end
	local okPrio, prio = pcall(function()
		return lighting.PrioritizeLightingQuality
	end)
	if not okPrio or prio ~= true then
		fail("Lighting.PrioritizeLightingQuality must be true (got " .. tostring(prio) .. ")")
	end
end

local players = game:FindFirstChildOfClass("Players")
if players == nil then
	fail("no Players service")
elseif players.CharacterAutoLoads ~= false then
	fail("Players.CharacterAutoLoads must be false")
end

local byClass = {}
local byService = {}
local total = 0
for _, inst in game:GetDescendants() do
	if inst:IsA("LuaSourceContainer") then
		total += 1
		byClass[inst.ClassName] = (byClass[inst.ClassName] or 0) + 1
		local top = inst
		while top.Parent ~= nil and top.Parent ~= game do
			top = top.Parent
		end
		byService[top.Name] = (byService[top.Name] or 0) + 1
		local source = inst.Source or ""
		if string.gsub(source, "%s", "") == "" then
			fail(inst:GetFullName() .. " has an empty Source")
		elseif string.sub(source, 1, 9) ~= "--!strict" then
			fail(inst:GetFullName() .. " does not start with --!strict")
		end
		if inst.ClassName == "Script" then
			local okRc, rc = pcall(function()
				return inst.RunContext
			end)
			if okRc and rc == roblox.Enum.RunContext.Client then
				warn(inst:GetFullName() .. " is a Script with RunContext.Client")
			end
		end
	end
end

print(("verify_place: %s"):format(path))
print(("  scripts: %d total"):format(total))
local classes = {}
for className, count in byClass do
	table.insert(classes, ("%s=%d"):format(className, count))
end
table.sort(classes)
print("  by class:   " .. table.concat(classes, ", "))
local services = {}
for name, count in byService do
	table.insert(services, ("%s=%d"):format(name, count))
end
table.sort(services)
print("  by service: " .. table.concat(services, ", "))
if lighting then
	print(
		("  Lighting: LightingStyle=%s PrioritizeLightingQuality=%s Technology=%s"):format(
			tostring(lighting.LightingStyle),
			tostring(lighting.PrioritizeLightingQuality),
			tostring((pcall(function()
				return lighting.Technology
			end)) and lighting.Technology or "?")
		)
	)
end
for _, w in warnings do
	print("  WARNING: " .. w)
end
if #failures > 0 then
	for _, f in failures do
		print("  FAIL: " .. f)
	end
	print(("verify_place: %d failures"):format(#failures))
	process.exit(1)
end
print("verify_place: OK")
