--!nocheck
-- Export selected instants (for quick checks): lune run tools/export_times.luau out.json t1 t2 ...
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Loader = require("./loader")
local E = require("./exportlib")
local Scene = Loader.load("src/Cutscene/Scene")
local Particles = Loader.load("src/Cutscene/Particles")
local scene = Scene.build("cinema")
local json = E.sceneJson(scene, Particles)
json.fps = 30
json.frames = {}
for i = 2, #process.args do
	local t = tonumber(process.args[i])
	table.insert(json.frames, E.frameJson(scene, Scene.evaluate(scene, t), Scene.partCFrame, json.dynamicIds))
end
fs.writeFile(process.args[1], serde.encode("json", json))
print(#json.frames, "frames")
