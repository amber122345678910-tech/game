--!nocheck
-- Выгрузка деталей карты в JSON (для рендера-превью). lune run tools/dump_parts.luau out.json [prefab]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./lib/loader")
local out = {}
local function add(part, extra)
	local cf = part.CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	table.insert(out, {
		name = part.Name,
		class = part.ClassName,
		pos = { x, y, z },
		rot = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		size = { part.Size.X, part.Size.Y, part.Size.Z },
		color = { part.Color.R, part.Color.G, part.Color.B },
		transparency = part.Transparency,
		shape = if part:IsA("Part") then part.Shape.Name else "Block",
		extra = extra,
	})
end
for _, file in { "src/map/Map.rbxmx", "src/map/Plots.rbxmx" } do
	for _, root in roblox.deserializeModel(fs.readFile(file)) do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				add(d)
			end
		end
	end
end
-- поставить готовый бункер на участок 1 для превью
local prefab = process.args[2]
if prefab then
	local Prefabs = Loader.load("src/shared/Prefabs")
	local Config = Loader.load("src/shared/Config")
	local Grid = Loader.load("src/shared/Grid")
	local plots = roblox.deserializeModel(fs.readFile("src/map/Plots.rbxmx"))[1]
	for _, plot in plots:GetChildren() do
		local origin = plot:GetAttribute("Origin")
		for _, e in Prefabs.layout(prefab) do
			local def = Config.Blocks[e.id]
			local lx, _, lz = Grid.cellCenterLocal(e.x, e.y, e.z)
			local ly = (e.y + def.HeightCells / 2) * 4
			local cf = origin * roblox.CFrame.new(lx, ly, lz) * roblox.CFrame.Angles(0, e.rot * math.pi / 2, 0)
			local p = roblox.Instance.new("Part")
			p.Name = e.id
			p.CFrame = cf
			p.Size = if def.IsDoor then roblox.Vector3.new(4, 8, 1) else roblox.Vector3.new(4, 4, 4)
			p.Color = def.Color
			add(p)
		end
	end
end
fs.writeFile(process.args[1] or "parts.json", serde.encode("json", out))
print(#out .. " parts")
