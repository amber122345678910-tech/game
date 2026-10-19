--!nocheck
-- Выгрузка деталей сцены в JSON для render.mjs.
-- lune run dump_scene.luau out.json [--skip=Имя1,Имя2] [--only=Имя] [--project=../../default.project.json] file1.rbxmx|file.rbxl [file2 ...]
--   --skip    — не выгружать экземпляры с такими именами (и всё внутри них), например --skip=Clouds
--   --only    — выгружать только поддеревья с таким именем (например --only=Hub)
--   --project — взять освещение (Lighting, Atmosphere, Bloom) из Rojo-проекта, если рендерим .rbxmx
--   --sky=N   — освещение зоны как в игре (WorldFX): Ambient, OutdoorAmbient, Atmosphere, Tint и Saturation
--               из Config.Zones[N].Sky (0 — Config.Hub.Sky); включает и цветокоррекцию (--cc)
--   --cc      — передать в рендер цветокоррекцию (ColorCorrection: Tint, Saturation, Contrast, Brightness)
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")

local outFile = process.args[1]
local parts, lights = {}, {}
local lighting = nil
local skip: { [string]: boolean } = {}
local only: { [string]: boolean }? = nil
local files = {}
local projectFile = nil
local skyZone: number? = nil
local withCC = false

for i = 2, #process.args do
	local a = process.args[i]
	local k, v = string.match(a, "^%-%-(%w+)=(.*)$")
	if k == "skip" then
		for name in string.gmatch(v, "[^,]+") do
			skip[name] = true
		end
	elseif k == "only" then
		only = {}
		for name in string.gmatch(v, "[^,]+") do
			only[name] = true
		end
	elseif k == "project" then
		projectFile = v
	elseif k == "sky" then
		skyZone = tonumber(v)
		withCC = true
	elseif a == "--cc" then
		withCC = true
	else
		table.insert(files, a)
	end
end

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

local function walk(root, inside: boolean)
	for _, d in root:GetChildren() do
		if not skip[d.Name] then
			local ins = inside or (only == nil) or (only[d.Name] == true)
			if ins and d:IsA("BasePart") and not d:IsA("Terrain") then
				addPart(d)
			end
			walk(d, ins)
		end
	end
end

local function arr(v)
	return { v[1], v[2], v[3] }
end

for _, file in files do
	local data = fs.readFile(file)
	if string.match(file, "%.rbxlx?$") then
		local place = roblox.deserializePlace(data)
		walk(place:GetService("Workspace"), false)
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
			if not skip[root.Name] then
				local ins = (only == nil) or (only[root.Name] == true)
				if ins and root:IsA("BasePart") then
					addPart(root)
				end
				walk(root, ins)
			end
		end
	end
end

-- Освещение из Rojo-проекта (для .rbxmx, где своего освещения нет)
if lighting == nil and projectFile and fs.isFile(projectFile) then
	local proj = serde.decode("json", fs.readFile(projectFile))
	local L = proj.tree and proj.tree.Lighting
	if L then
		local p = L["$properties"] or {}
		local atm = L.Atmosphere and L.Atmosphere["$properties"]
		local bloom = L.Bloom and L.Bloom["$properties"]
		lighting = {
			clockTime = p.ClockTime or 14,
			brightness = p.Brightness or 2,
			ambient = arr(p.Ambient or { 0.5, 0.5, 0.5 }),
			outdoorAmbient = arr(p.OutdoorAmbient or { 0.5, 0.5, 0.5 }),
			atmosphere = atm and { density = atm.Density or 0.3, color = arr(atm.Color or { 0.6, 0.6, 0.7 }) } or nil,
			bloom = bloom and { intensity = bloom.Intensity or 0.6, size = bloom.Size or 24, threshold = bloom.Threshold or 1 } or nil,
		}
	end
end

-- Цветокоррекция из проекта и освещение зоны из Config (как его ставит клиент)
if lighting and projectFile and fs.isFile(projectFile) and withCC then
	local proj = serde.decode("json", fs.readFile(projectFile))
	local L = proj.tree and proj.tree.Lighting
	local cc = L and L.ColorCorrection and L.ColorCorrection["$properties"]
	if cc then
		lighting.cc = { tint = arr(cc.TintColor or { 1, 1, 1 }), saturation = cc.Saturation or 0, contrast = cc.Contrast or 0, brightness = cc.Brightness or 0 }
	end
end
if lighting and skyZone ~= nil then
	local root = if projectFile then (string.match(projectFile, "^(.*)/[^/]+$") or ".") else "../.."
	local Loader = require("../lib/loader")
	local Config = Loader.load(root .. "/src/shared/Config")
	local sky = if skyZone >= 1 and Config.Zones[skyZone] then Config.Zones[skyZone].Sky else Config.Hub.Sky
	local function c3(c)
		return { c.R, c.G, c.B }
	end
	lighting.ambient = c3(sky.Ambient)
	lighting.outdoorAmbient = c3(sky.OutdoorAmbient)
	lighting.atmosphere = { density = sky.Density, color = c3(sky.AtmosphereColor) }
	lighting.cc = lighting.cc or { tint = { 1, 1, 1 }, saturation = 0, contrast = 0, brightness = 0 }
	lighting.cc.tint = c3(sky.Tint)
	lighting.cc.saturation = sky.Saturation
end

fs.writeFile(outFile, serde.encode("json", { parts = parts, lights = lights, lighting = lighting }))
print(#parts .. " parts, " .. #lights .. " lights")
