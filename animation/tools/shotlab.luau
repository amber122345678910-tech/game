--!nocheck
-- Shot lab: evaluates the real scene at given times and exports them as
-- preview frames, optionally re-aiming the camera to zoom in on something.
-- Usage: lune run tools/shotlab.luau <out.json> <t1,t2,...> [x,y,z] [fov] [dist]
--   with a target point the camera keeps its viewing direction but moves to
--   <dist> studs from the target (and uses <fov>), depth of field is off
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local Loader = require("./loader")
local E = require("./exportlib")

local root = "src/Cutscene"
local Scene = Loader.load(root .. "/Scene")
local Particles = Loader.load(root .. "/Particles")
local Util = Loader.load(root .. "/Util")

local outPath = process.args[1] or "build/shotlab.json"
local times = {}
for s in string.gmatch(process.args[2] or "0.4", "[^,]+") do
	table.insert(times, tonumber(s))
end
local target
if process.args[3] then
	local c = {}
	for s in string.gmatch(process.args[3], "[^,]+") do
		table.insert(c, tonumber(s))
	end
	target = Vector3.new(c[1], c[2], c[3])
end
local fov = tonumber(process.args[4] or "12")
local dist = tonumber(process.args[5] or "0")

local scene = Scene.build("cinema")
local json = E.sceneJson(scene, Particles)
json.fps = 30
json.frames = {}
for _, t in times do
	local fr = Scene.evaluate(scene, t)
	if target then
		local look = fr.camera.LookVector
		local eye = if dist > 0 then target - look * dist else fr.camera.Position
		fr.camera = Util.lookAt(eye, target)
		fr.fov = fov
		fr.dof = 0
	end
	table.insert(json.frames, E.frameJson(scene, fr, Scene.partCFrame, json.dynamicIds))
end
fs.writeFile(outPath, serde.encode("json", json))
print(#json.frames, "frames ->", outPath)
