--!nocheck
-- lune run dump_scene.luau out.json file1.rbxmx|file.rbxl [file2 ...]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")

local outFile = process.args[1]
local parts, lights = {}, {}
local lighting = nil

local function shapeOf(p)
	if p.ClassName == "WedgePart" then
		return "Wedge"
	elseif p.ClassName == "CornerWedgePart" then
		return "CornerWedge"
	elseif p.ClassName == "Part" or p.ClassName == "SpawnLocation" then
		local s = p.Shape.Name
		if s == "Ball" or s == "Cylinder" then
			return s
		end
		return "Block"
	elseif p.ClassName == "TrussPart" then
		return "Block"
	end
	return "Block"
end

local function addPart(p)
	local cf = p.CFrame
	table.insert(parts, {
		shape = shapeOf(p),
		cf = { cf:GetComponents() },
		size = { p.Size.X, p.Size.Y, p.Size.Z },
		color = { p.Color.R, p.Color.G, p.Color.B },
		material = p.Material.Name,
		transparency = p.Transparency,
		name = p.Name,
	})
	for _, c in p:GetChildren() do
		if c:IsA("PointLight") or c:IsA("SpotLight") or c:IsA("SurfaceLight") then
			if c.Enabled then
				table.insert(lights, {
					pos = { p.CFrame.Position.X, p.CFrame.Position.Y, p.CFrame.Position.Z },
					color = { c.Color.R, c.Color.G, c.Color.B },
					range = c.Range,
					brightness = c.Brightness,
				})
			end
		end
	end
end

local function walk(root)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("Terrain") then
			addPart(d)
		end
	end
end

for i = 2, #process.args do
	local file = process.args[i]
	local data = fs.readFile(file)
	if string.match(file, "%.rbxlx?$") then
		local place = roblox.deserializePlace(data)
		walk(place:GetService("Workspace"))
		local L = place:GetService("Lighting")
		local atm = L:FindFirstChildOfClass("Atmosphere")
		local bloom = L:FindFirstChildOfClass("BloomEffect")
		lighting = {
			clockTime = L.ClockTime,
			brightness = L.Brightness,
			ambient = { L.Ambient.R, L.Ambient.G, L.Ambient.B },
			outdoorAmbient = { L.OutdoorAmbient.R, L.OutdoorAmbient.G, L.OutdoorAmbient.B },
			atmosphere = atm and { density = atm.Density, color = { atm.Color.R, atm.Color.G, atm.Color.B } } or nil,
			bloom = bloom and { intensity = bloom.Intensity, size = bloom.Size, threshold = bloom.Threshold } or nil,
		}
	else
		for _, root in roblox.deserializeModel(data) do
			if root:IsA("BasePart") then
				addPart(root)
			end
			walk(root)
		end
	end
end

fs.writeFile(outFile, serde.encode("json", { parts = parts, lights = lights, lighting = lighting }))
print(#parts .. " parts, " .. #lights .. " lights")
