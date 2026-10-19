--!nocheck
-- Финальная сборка места (Lune): base.rbxl (скрипты от Rojo) + декорации + риги + анимации -> AuraFarmer.rbxl
--   lune run tools/build.luau [вход=build/base.rbxl] [выход=AuraFarmer.rbxl]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local World = require("./lib/World")

local input = process.args[1] or "build/base.rbxl"
local output = process.args[2] or "AuraFarmer.rbxl"
local game = roblox.deserializePlace(fs.readFile(input))

local world = World.build({ allSets = true })
world.root.Parent = game:GetService("Workspace")
local ss = game:GetService("ServerStorage")
local old = ss:FindFirstChild("RBX_ANIMSAVES")
if old then
	old:Destroy()
end
world.animSaves.Parent = ss

-- Terrain со свойствами (Decoration не меняется скриптами — только в файле/Properties)
local Loader = require("./lib/loader")
local Config = Loader.load("src/shared/Config")
local ws = game:GetService("Workspace")
local terrain = ws:FindFirstChildOfClass("Terrain")
if not terrain then
	terrain = roblox.Instance.new("Terrain")
	terrain.Parent = ws
end
for k, v in Config.Terrain do
	terrain[k] = v
end
if not terrain:FindFirstChildOfClass("Clouds") then
	local clouds = roblox.Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Density = 0.55
	clouds.Parent = terrain
end

fs.writeFile(output, roblox.serializePlace(game))
local parts = 0
for _, d in world.root:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
print(string.format("build: %s — %d деталей, %d анимаций", output, parts, #world.animSaves:GetChildren()))
for _, s in world.stats do
	print("  " .. s)
end
