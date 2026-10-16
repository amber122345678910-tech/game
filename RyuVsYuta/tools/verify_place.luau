--!nocheck
-- Проверка собранного места катсцены (Lune): структура, скрипты, модели, свет, привязка деталей к костям.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Loader = require("./lib/loader")

local path = process.args[1] or "../RyuVsYuta.rbxl"
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
local SP = game:GetService("StarterPlayer")
local WS = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

for _, p in {
	{ RS, "Cutscene.Math", "ModuleScript" },
	{ RS, "Cutscene.Rig", "ModuleScript" },
	{ RS, "Cutscene.Track", "ModuleScript" },
	{ RS, "Cutscene.Skeletons", "ModuleScript" },
	{ RS, "Cutscene.Textures", "ModuleScript" },
	{ RS, "Cutscene.Anim.Gait", "ModuleScript" },
	{ RS, "Cutscene.Anim.Hair", "ModuleScript" },
	{ RS, "Cutscene.Audio.SoundBank", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Sequence", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Types", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Look", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.Main", "LocalScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.FX.FogCards", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.FX.TextureLoader", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Actors", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Cameras", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Atmos", "ModuleScript" },
	{ RS, "Cutscene.Sequence.FogCards", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Timing", "ModuleScript" },
	{ RS, "Cutscene.Sequence.Layout", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.Director", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.UI", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.Audio", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.CharacterDriver", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.FX.Env", "ModuleScript" },
	{ SP, "StarterPlayerScripts.CutsceneClient.FX.Effects", "ModuleScript" },
} do
	local inst = find(p[1], p[2])
	check(inst ~= nil, "missing " .. p[2])
	check(inst == nil or inst.ClassName == p[3], p[2] .. " should be " .. p[3] .. " got " .. (inst and inst.ClassName or "nil"))
end
check(Players.CharacterAutoLoads == false, "CharacterAutoLoads must be false (player is not a character)")
check(WS.StreamingEnabled == false, "StreamingEnabled must be false")
check(Lighting.Technology == roblox.Enum.Technology.Future, "Lighting.Technology should be Future")
check(Lighting:FindFirstChildOfClass("Atmosphere") ~= nil, "Atmosphere missing")
check(Lighting:FindFirstChildOfClass("Sky") ~= nil, "Sky missing")

local Rig = Loader.load("src/shared/Rig")
local Skeletons = Loader.load("src/shared/Skeletons")
local budget = { Rika = 1700, Ryu = 1000, Yuta = 600, RyuDummy = 40, YutaDummy = 40 }
local total = 0
for _, name in { "Rika", "Yuta", "Ryu", "YutaDummy", "RyuDummy" } do
	local m = find(WS, "Cutscene.Characters." .. name)
	check(m ~= nil, "character missing: " .. name)
	if m then
		local root = m:FindFirstChild("Root")
		check(root ~= nil and root:IsA("BasePart"), name .. ": Root part missing")
		local def = Skeletons[m:GetAttribute("Rig") or name]
		check(def ~= nil, name .. ": unknown Rig attribute")
		local ok, binding = pcall(Rig.bind, def, m, root.CFrame)
		check(ok, name .. ": bind failed " .. tostring(binding))
		local n, unanchored, collide, unbound = 0, 0, 0, 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
				if not d.Anchored then unanchored += 1 end
				if d.CanCollide then collide += 1 end
				if d.Name ~= "Root" and type(d:GetAttribute("Bone")) ~= "string" then unbound += 1 end
			elseif d:IsA("Beam") then
				check(d.Attachment0 ~= nil and d.Attachment1 ~= nil, name .. ": beam without attachments " .. d:GetFullName())
			elseif d:IsA("Humanoid") then
				check(false, name .. ": must not contain Humanoid")
			end
		end
		total += n
		check(n <= budget[name], string.format("%s: %d parts > budget %d", name, n, budget[name]))
		check(unanchored == 0, name .. ": unanchored parts " .. unanchored)
		check(collide == 0, name .. ": CanCollide parts " .. collide)
		check(unbound == 0, name .. ": parts without Bone attribute " .. unbound)
		check(m:FindFirstChildOfClass("Highlight") ~= nil, name .. ": outline Highlight missing")
		local soleL = m:FindFirstChild("SoleL", true)
		local soleR = m:FindFirstChild("SoleR", true)
		check(soleL ~= nil and soleR ~= nil, name .. ": SoleL/SoleR missing")
		print(string.format("%s: %d parts", name, n))
	end
end
local rika = find(WS, "Cutscene.Characters.Rika")
if rika then
	check(rika:FindFirstChild("Eye", true) ~= nil, "Rika: Eye missing")
	local el = rika:FindFirstChild("EyeLight", true)
	check(el ~= nil and el.ClassName == "PointLight", "Rika: EyeLight PointLight missing")
end
for _, rn in { "Ryu", "RyuDummy" } do
	local ryu = find(WS, "Cutscene.Characters." .. rn)
	if ryu then
		check(ryu:FindFirstChild("EnergyAnchor", true) ~= nil, rn .. ": EnergyAnchor missing")
	end
end
local env = find(WS, "Cutscene.Environment")
check(env ~= nil, "Environment missing")
if env then
	local fog = env:FindFirstChild("FogEmitters")
	check(fog ~= nil, "Environment.FogEmitters missing")
	local n, em = 0, 0
	for _, d in env:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
			check(d.Anchored, "env part not anchored: " .. d:GetFullName())
		elseif d:IsA("ParticleEmitter") then
			em += 1
		end
	end
	total += n
	print(string.format("Environment: %d parts, %d emitters", n, em))
	check(n <= 4000, "environment too many parts " .. n)
end
-- одинаковые имена у соседних скриптов/папок ломают WaitForChild
for _, root in { RS:FindFirstChild("Cutscene"), SP:FindFirstChild("StarterPlayerScripts") } do
	if root then
		for _, d in root:GetDescendants() do
			local seen = {}
			for _, c in d:GetChildren() do
				check(not seen[c.Name], "duplicate child name " .. c.Name .. " under " .. d:GetFullName())
				seen[c.Name] = true
			end
		end
	end
end
-- устаревшие/запрещённые классы
for _, d in game:GetDescendants() do
	if d:IsA("UnionOperation") or d:IsA("MeshPart") or d.ClassName == "CornerWedgePart" then
		check(false, "forbidden class " .. d.ClassName .. " " .. d:GetFullName())
	end
end
print("total parts: " .. total)
if #errors > 0 then
	for _, e in errors do
		print("ERROR: " .. e)
	end
	process.exit(1)
end
print("Place OK")
