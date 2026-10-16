--!nocheck
-- Осмотр модели персонажа в превизе: lune run tools/view_model.luau <Builder> <out.json> [poseName] [close]
--   Builder — имя модуля в src/shared/Builders (Rika, Ryu, Yuta) или путь к модулю-строителю.
--   poseName — поза из tools/test_poses.luau (по умолчанию rest).
-- Затем: python3 tools/previz_render.py out.json out_dir
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")
local Previz = require("./lib/previz")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local builderName = process.args[1] or "Rika"
local out = process.args[2] or "view.json"
local poseName = process.args[3] or "rest"
local closeBone = process.args[4]

local MathX = Loader.load("src/shared/Math")
local Rig = Loader.load("src/shared/Rig")
local Skeletons = Loader.load("src/shared/Skeletons")
local builderPath = if string.find(builderName, "/") then builderName else "src/shared/Builders/" .. builderName
local Builder = Loader.load(builderPath)
local poses = Loader.load(process.args[5] or "tools/test_poses")

local origin = CFrame.new()
local model = Builder.build(origin)
local rigName = model:GetAttribute("Rig")
local def = Skeletons[rigName]
assert(def, "no skeleton " .. tostring(rigName))
local binding = Rig.bind(def, model, origin)
local poseFn = poses[poseName]
assert(poseFn, "no test pose " .. poseName)
local pose, ik = poseFn(def, origin, MathX)
local world = Rig.solve(def, origin, pose, ik)
local cfs = Rig.partCFrames(binding, world, 0, 0)
local map = {}
for i, p in binding.parts do
	map[p:GetFullName()] = cfs[i]
end
-- габариты
local minY, maxY, minX, maxX = math.huge, -math.huge, math.huge, -math.huge
for i, p in binding.parts do
	if p.Transparency < 0.98 then
		local c = cfs[i].Position
		minY = math.min(minY, c.Y - p.Size.Y / 2)
		maxY = math.max(maxY, c.Y + p.Size.Y / 2)
		minX = math.min(minX, c.X - p.Size.X / 2)
		maxX = math.max(maxX, c.X + p.Size.X / 2)
	end
end
local height = maxY - math.max(minY, 0)
print(string.format("model %s parts=%d beams=%d height=%.2f width=%.2f", builderName, #binding.parts, (function()
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Beam") then n += 1 end
	end
	return n
end)(), height, maxX - minX))
local center = Vector3.new(0, height * 0.5, 0)
local frames = {}
local env = { sky = { { 0.86, 0.88, 0.95 }, { 0.55, 0.66, 0.86 } }, sun = { 0.35, 0.8, -0.45 }, ambient = { 0.5, 0.5, 0.56 } }
for _, v in Previz.orbitViews(center, height * 1.55, 0) do
	local fr = Previz.newFrame(builderName .. "_" .. poseName .. "_" .. v.name, MathX.lookAt(v.eye, v.target), 50, env)
	Previz.addModel(fr, model, { cframes = map, group = 1, outline = 1 })
	table.insert(frames, fr)
end
if closeBone then
	local hb = Rig.boneWorld(def, world, closeBone).Position
	local s = height * 0.16
	for _, v in Previz.orbitViews(hb, s * 2.2, 0) do
		if v.name == "front" or v.name == "front34" or v.name == "side" or v.name == "low_front" then
			local fr = Previz.newFrame(builderName .. "_" .. poseName .. "_close_" .. v.name, MathX.lookAt(v.eye, v.target), 50, env)
			Previz.addModel(fr, model, { cframes = map, group = 1, outline = 1 })
			table.insert(frames, fr)
		end
	end
end
Previz.write(out, frames)
