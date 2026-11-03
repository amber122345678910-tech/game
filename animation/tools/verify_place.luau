--!nocheck
-- Opens the built place and checks that everything the cutscene needs is in it.
-- Usage: lune run tools/verify_place.luau <place.rbxl>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "YutaVsRyu_Part1.rbxl"
local wantPart = tonumber(process.args[2] or "1")
local game = roblox.deserializePlace(fs.readFile(path))

local failures = 0
local function check(cond, msg)
	if cond then
		print("ok   " .. msg)
	else
		failures += 1
		print("FAIL " .. msg)
	end
end

local rs = game:GetService("ReplicatedStorage")
local cutscene = rs:FindFirstChild("Cutscene")
check(cutscene ~= nil, "ReplicatedStorage.Cutscene exists")
local expected = {
	"Util", "Paint", "Rig", "Track", "Layout", "Builder", "Styles", "Timeline", "Particles", "FX", "Scene", "Realizer",
	"Art/Characters/Ryu", "Art/Characters/Yuta", "Art/Characters/Rika",
	"Art/Faces/YutaEyes", "Art/Faces/RyuEyes", "Art/Faces/FaceRig",
	"Art/Sets/SkyPaint", "Art/Sets/WideSet", "Art/Sets/CloseupSet",
	"Shots/Cast", "Shots/Field", "Shots/Overlay", "Shots/Opening", "Shots/Clash", "Shots/RyuShots", "Shots/YutaShots",
	"Art/Characters/Uro", "Shots/Part2", "Shots/P2/Common", "Shots/P2/Overlay2", "Shots/P2/Blast", "Shots/P2/Realize",
	"Shots/P2/Flashback", "Shots/P2/Grapple",
}
for _, rel in expected do
	local node = cutscene
	for part in string.gmatch(rel, "[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	check(node ~= nil and node.ClassName == "ModuleScript" and #node.Source > 100, "module " .. rel)
end
local partValue = rs:FindFirstChild("CutscenePart")
check(partValue ~= nil and partValue.ClassName == "IntValue" and partValue.Value == wantPart, "ReplicatedStorage.CutscenePart = " .. tostring(wantPart))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local player = sps and sps:FindFirstChild("CutscenePlayer")
check(player ~= nil and player.ClassName == "LocalScript", "StarterPlayerScripts.CutscenePlayer is a LocalScript")
check(game:GetService("Players").CharacterAutoLoads == false, "Players.CharacterAutoLoads = false (no avatar in the shot)")
check(game:GetService("Workspace"):FindFirstChild("ReadMe") ~= nil, "Workspace.ReadMe sign exists")
local lighting = game:GetService("Lighting")
check(lighting.LightingStyle == roblox.Enum.LightingStyle.Soft, "Lighting.LightingStyle = Soft")

-- no script may use APIs that are known to be risky in a local, unpublished place
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		local src = d.Source
		check(not string.find(src, "EditableImage", 1, true), d:GetFullName() .. " does not use EditableImage")
		check(not string.find(src, "rbxassetid://", 1, true), d:GetFullName() .. " does not need uploaded assets")
	end
end

if failures > 0 then
	error(failures .. " check(s) failed")
end
print("place OK: " .. path)
