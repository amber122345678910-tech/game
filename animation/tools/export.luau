--!nocheck
-- Exports the scene and its frames as JSON for the offline preview.
-- Runs the exact same Luau scene/timeline code as Roblox does.
-- Usage: [PART=2] lune run tools/export.luau <out.json> [fps] [t0] [t1] [step]
--   step > 1 exports every n-th frame (quick contact sheets)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Loader = require("./loader")
local E = require("./exportlib")

local root = "src/Cutscene"
local Scene = Loader.load(root .. "/Scene")
local Particles = Loader.load(root .. "/Particles")

local outPath = process.args[1] or "build/part1.json"
local fps = tonumber(process.args[2] or "30")
local t0 = tonumber(process.args[3] or "0")
local t1 = tonumber(process.args[4] or "0")
local step = tonumber(process.args[5] or "1")

local PART = tonumber(process.env.PART or "1") or 1 -- PART=2 for part 2
local scene = Scene.build("cinema", PART)
if t1 <= 0 then
	t1 = Scene.duration(scene)
end
local json = E.sceneJson(scene, Particles)
json.fps = fps / step
local n = math.floor((t1 - t0) * fps + 0.5)
-- long exports: scene JSON + one frame per line (JSON Lines) next to it,
-- so the renderer can stream frames instead of loading everything at once
local lines = string.sub(outPath, -6) == ".jsonl"
local frames = {}
for i = 0, n - 1, step do
	local t = t0 + i / fps
	local fr = Scene.evaluate(scene, t)
	local fj = E.frameJson(scene, fr, Scene.partCFrame, json.dynamicIds)
	table.insert(frames, if lines then serde.encode("json", fj) else fj)
end
if lines then
	fs.writeFile(string.sub(outPath, 1, -7) .. ".scene.json", serde.encode("json", json))
	fs.writeFile(outPath, table.concat(frames, "\n") .. "\n")
else
	json.frames = frames
	fs.writeFile(outPath, serde.encode("json", json))
end
print(string.format("%d parts (%d dynamic), %d frames -> %s", #json.parts, #json.dynamicIds, #frames, outPath))
