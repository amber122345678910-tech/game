--!nocheck
-- Генератор карты (Lune): создаёт src/map/Map.rbxmx (корень — Model "Map").
-- Запуск из LightningCatchers/: .tools/lune run tools/gen_map.luau
-- Геометрия берётся из src/shared/Zones.luau и Config.luau, поэтому карта совпадает с логикой игры.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")
local B = require("./lib/builder")
local Island = require("./map/island")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Enum = roblox.Enum
local M = Enum.Material

local Config = Loader.load("src/shared/Config")
local Zones = Loader.load("src/shared/Zones")

local root = Instance.new("Model")
root.Name = "Map"

local walls = B.folder(root, "Walls")
local islands = B.folder(root, "Islands")

for i, z in Config.Zones do
	local g = Zones.Geo[i]
	Island.body(islands, {
		name = "Island_" .. i,
		center = g.Center,
		radius = z.Radius,
		seed = 100 + i * 31,
		top = z.Grass,
		topMaterial = z.GrassMaterial,
		dirt = B.rgb(118, 84, 58),
		rock = z.Rock,
		depth = 64,
		openings = { g.ToHub },
		walls = { radius = z.Radius + 0.8 },
		wallParent = walls,
	})
end

local hubOpen = {}
for _, g in Zones.Geo do
	table.insert(hubOpen, g.Dir)
end
Island.body(islands, {
	name = "Hub",
	center = Zones.HubCenter,
	radius = Config.Hub.Radius,
	seed = 7,
	top = B.rgb(150, 146, 140),
	topMaterial = M.Cobblestone,
	dirt = B.rgb(110, 90, 70),
	rock = B.rgb(120, 118, 128),
	depth = 70,
	openings = hubOpen,
	walls = { radius = Config.Hub.Radius + 0.8 },
	wallParent = walls,
})

print(string.format("Деталей: %d", B.count))
fs.writeFile("src/map/Map.rbxmx", roblox.serializeModel({ root }, true))
print("src/map/Map.rbxmx записан")
