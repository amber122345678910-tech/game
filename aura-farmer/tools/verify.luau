--!nocheck
-- Проверка собранного места: lune run tools/verify.luau AuraFarmer.rbxl
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")
local KFS = Loader.load("src/shared/Anim/KFS")
local FK = Loader.load("src/shared/Anim/FK")
local Config = Loader.load("src/shared/Config")

local path = process.args[1] or "AuraFarmer.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))
local errors, warnings = {}, {}
local function check(cond, msg)
	if not cond then
		table.insert(errors, msg)
	end
end
local function warn(cond, msg)
	if not cond then
		table.insert(warnings, msg)
	end
end
local function find(root, p)
	local node = root
	for name in string.gmatch(p, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local SP = game:GetService("StarterPlayer")

for _, spec in {
	{ SSS, "AuraFarmerServer.World", "Script" },
	{ SSS, "AuraFarmerServer.TerrainBuilder", "ModuleScript" },
	{ SP, "StarterPlayerScripts.AuraFarmerClient.Cinematic", "LocalScript" },
	{ SP, "StarterPlayerScripts.AuraFarmerClient.Effects", "ModuleScript" },
	{ RS, "AuraFarmer.Timeline", "ModuleScript" },
	{ RS, "AuraFarmer.Anim.KFS", "ModuleScript" },
} do
	local inst = find(spec[1], spec[2])
	check(inst and inst.ClassName == spec[3], "нет " .. spec[2] .. " (" .. spec[3] .. ")")
end
check(game:GetService("Players").CharacterAutoLoads == false, "CharacterAutoLoads должен быть false")

local world = WS:FindFirstChild("AuraFarmer")
check(world, "нет Workspace.AuraFarmer")
local saves = SS:FindFirstChild("RBX_ANIMSAVES")
check(saves, "нет ServerStorage.RBX_ANIMSAVES")
if world and saves then
	for name in Config.Sets do
		check(find(world, "Sets." .. name), "нет декорации " .. name)
	end
	local totalParts = 0
	for _, id in Config.ShotOrder do
		local f = find(world, "Shots." .. id)
		check(f, "нет папки плана " .. id)
		if f then
			for _, rig in f:GetChildren() do
				local holder = saves:FindFirstChild(rig.Name)
				warn(holder, "у рига " .. rig.Name .. " нет анимации")
				local fk = FK.build(rig)
				totalParts += #fk.parts
				local nParts = 0
				for _, d in rig:GetDescendants() do
					if d:IsA("BasePart") then
						nParts += 1
					end
				end
				check(nParts == #fk.parts, string.format("%s: %d деталей не прикреплены к скелету", rig.Name, nParts - #fk.parts))
				if holder then
					local kfs = holder:FindFirstChildWhichIsA("KeyframeSequence")
					check(kfs, rig.Name .. ": нет KeyframeSequence")
					if kfs then
						local clip = KFS.compile(kfs)
						local keys = FK.motorKeys(fk)
						for jn in clip.tracks do
							check(keys[jn] or jn == "HumanoidRootPart", rig.Name .. ": поза для несуществующего сустава " .. jn)
						end
						local shot = Loader.load("src/shared/Shots/" .. id)
						warn(math.abs(clip.length - (shot.finish - shot.start)) < 0.05, string.format("%s: длина клипа %.3f, а план %.3f", rig.Name, clip.length, shot.finish - shot.start))
						local out, cfs = {}, {}
						for _, t in { 0, clip.length / 2, clip.length } do
							KFS.sample(clip, t, out)
							FK.solve(fk, fk.root.CFrame, out, cfs)
							for _, cf in cfs do
								local p = cf.Position
								check(p.X == p.X and p.Y == p.Y and p.Z == p.Z, rig.Name .. ": NaN в позе")
							end
						end
					end
				end
			end
		end
	end
	print(string.format("verify: деталей в ригах %d", totalParts))
end

for _, w in warnings do
	print("WARN: " .. w)
end
if #errors > 0 then
	for _, e in errors do
		print("ERROR: " .. e)
	end
	error(#errors .. " ошибок проверки")
end
print("verify: OK")
