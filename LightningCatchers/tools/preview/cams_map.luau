--!nocheck
-- Камеры для превью карты, посчитанные из Zones (острова, хаб, мосты).
-- lune run tools/preview/cams_map.luau OUT.json [набор: islands|hub|bridges|all] [clockTime]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("../lib/loader")
local Vector3 = require("@lune/roblox").Vector3
local Config = Loader.load("src/shared/Config")
local Zones = Loader.load("src/shared/Zones")

local out = process.args[1] or "cams.json"
local set = process.args[2] or "all"
local clock = tonumber(process.args[3]) or 19.6
local cams = {}
local function v(p)
	return { p.X, p.Y, p.Z }
end
local function add(name, pos, look, fov)
	table.insert(cams, { name = name, pos = v(pos), look = v(look), fov = fov or 65, clockTime = clock })
end
local up = function(y)
	return Vector3.new(0, y, 0)
end

if set == "islands" or set == "all" then
	for i, g in Zones.Geo do
		local z = Config.Zones[i]
		local eye = g.Spawn + up(3) + g.Right * 4
		add("i" .. i .. "_eye", eye, g.Landmark + up(10), 70)
		add("i" .. i .. "_side", g.Center + g.ToHub * (z.Radius + 50) + g.Right * 85 + up(40), g.Center + up(-12), 60)
		add("i" .. i .. "_land", g.Landmark - g.Dir * 34 + g.Right * 16 + up(7), g.Landmark + up(14), 65)
		add("i" .. i .. "_under", g.Center - g.Right * 150 + up(-40), g.Center + up(-30), 55)
	end
end
if set == "hub" or set == "all" then
	local H = Zones.Hub
	add("hub_spawn", H.Spawn + up(3), Zones.HubCenter + up(20), 70)
	add("hub_high", Vector3.new(110, 70, 130), Vector3.new(0, 10, 0), 60)
	add("hub_shop", H.Shop - H.Shop.Unit * 22 + up(5), H.Shop + up(5), 60)
	add("hub_hatch", H.Hatchery - H.Hatchery.Unit * 20 + up(5), H.Hatchery + up(4), 60)
	add("hub_gallery", H.Gallery - H.Gallery.Unit * 26 + up(9), H.Gallery + up(2), 65)
	add("hub_rebirth", H.Rebirth - H.Rebirth.Unit * 22 + up(6), H.Rebirth + up(6), 60)
	add("hub_daily", H.Daily - H.Daily.Unit * 20 + up(5), H.Daily + up(4), 60)
	add("hub_boards", Vector3.new(0, 6, 50), Vector3.new(0, 7, 85), 70)
	add("hub_street", Vector3.new(40, 5, -60), Vector3.new(60, 8, -80), 70)
end
if set == "bridges" or set == "all" then
	for i, g in Zones.Geo do
		local a = g.BridgeStart + g.Dir * 4 + up(6) + g.Right * 4
		add("b" .. i .. "_deck", a, g.BridgeEnd + up(6), 65)
		add("b" .. i .. "_side", (g.BridgeStart + g.BridgeEnd) / 2 + g.Right * 70 + up(-10), (g.BridgeStart + g.BridgeEnd) / 2 + up(-4), 60)
	end
end
if set == "overview" or set == "all" then
	add("overview", Vector3.new(60, 330, 420), Vector3.new(0, -30, -20), 60)
	add("overview2", Vector3.new(-380, 120, 260), Vector3.new(0, 0, -20), 55)
end
fs.writeFile(out, serde.encode("json", cams))
print(#cams .. " cameras -> " .. out)
