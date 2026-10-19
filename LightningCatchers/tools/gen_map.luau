--!nocheck
-- Генератор карты (Lune): создаёт src/map/Map.rbxmx (корень — Model "Map").
-- Запуск из LightningCatchers/: .tools/lune run tools/gen_map.luau
-- Геометрия берётся из src/shared/Zones.luau и Config.luau, поэтому карта совпадает с логикой игры.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")
local B = require("./lib/builder")
local ZonesMap = require("./map/zones")
local Hub = require("./map/hub")
local Bridges = require("./map/bridges")
local Sky = require("./map/sky")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local ctx = {
	Config = Loader.load("src/shared/Config"),
	Zones = Loader.load("src/shared/Zones"),
	Format = Loader.load("src/shared/Format"),
	Pets = Loader.load("src/shared/Pets"),
	Fulgurite = Loader.load("src/shared/Fulgurite"),
	Models = Loader.load("src/shared/Models"),
}

-- Поставить модель из Models.luau как статичный декор: якорь, без сварок, без коллизий
function ctx.place(model, cf, parent)
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			B.count += 1
			if d:IsA("Part") and d.Shape == roblox.Enum.PartType.Ball then
				B.balls += 1
			end
		end
	end
	model.Parent = parent
	return model
end

local root = Instance.new("Model")
root.Name = "Map"
ctx.Root = root
ctx.Walls = B.folder(root, "Walls")
ctx.Markers = B.folder(root, "Markers")
local islands = B.folder(root, "Islands")

local counts = {}
local function section(name, fn)
	local before, ballsBefore = B.count, B.balls
	fn()
	table.insert(counts, string.format("  %-10s %5d   шаров %3d", name, B.count - before, B.balls - ballsBefore))
end

for i = 1, #ctx.Config.Zones do
	section("Остров " .. i, function()
		ZonesMap.build(ctx, i, islands)
	end)
end

section("Хаб", function()
	Hub.build(ctx, islands)
end)
section("Мосты", function()
	Bridges.build(ctx, root)
end)
section("Небо", function()
	Sky.build(ctx)
end)

-- Метки: точки появления и подстанции
section("Метки", function()
	local Zones, Config = ctx.Zones, ctx.Config
	for zone = 0, #Config.Zones do
		local p = Zones.spawnFor(zone)
		local look = if zone == 0 then -B.flat(p) else Zones.Geo[zone].Dir
		B.marker(ctx.Markers, "Spawn_" .. zone, B.facing(p, look))
	end
	local s0 = B.marker(ctx.Markers, "SellPad_0", CFrame.new(Zones.HubCenter), Vector3.new(2, 1, 2))
	s0:SetAttribute("Radius", Zones.HubSellRadius)
	for zone = 1, #Config.Zones do
		local s = B.marker(ctx.Markers, "SellPad_" .. zone, CFrame.new(Zones.Geo[zone].SellPad), Vector3.new(2, 1, 2))
		s:SetAttribute("Radius", Zones.SellPadRadius)
	end
end)

print("Деталей по разделам:")
for _, line in counts do
	print(line)
end
print(string.format("Всего деталей: %d, из них шаров: %d (бюджет STYLE §11: ≤ 6900 и ≤ 300)", B.count, B.balls))
fs.writeFile("src/map/Map.rbxmx", roblox.serializeModel({ root }, true))
print("src/map/Map.rbxmx записан")
