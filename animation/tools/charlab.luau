--!nocheck
-- Character lab: one character in a pose on a snow floor, seen from several
-- angles, exported for the preview renderer (one "frame" per view).
-- Usage: lune run tools/charlab.luau <Rika|Ryu|Yuta> <pose> <out.json> [faceGroups,...]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Loader = require("./loader")
local E = require("./exportlib")

local root = "src/Cutscene"
local Builder = Loader.load(root .. "/Builder")
local Styles = Loader.load(root .. "/Styles")
local Rig = Loader.load(root .. "/Rig")
local Timeline = Loader.load(root .. "/Timeline")
local Util = Loader.load(root .. "/Util")
local Particles = Loader.load(root .. "/Particles")

local who = process.args[1] or "Rika"
local poseName = process.args[2] or "crouch"
local outPath = process.args[3] or "build/charlab.json"
local groups = process.args[4]

local scene = Builder.new(Styles.get("cinema"))
Builder.model(scene, "Lab", false)
Builder.part(scene, "Lab", Vector3.new(200, 2, 200), CFrame.new(0, -1, 0), scene.style.color.snow, { material = "Snow", name = "Floor" })
local Char = Loader.load(root .. "/Art/Characters/" .. who)
local def = Char.build(scene, who)
local pose = Char.poses[poseName] or {}

local function partCFrame(part, frame)
	if part.rig and part.bone then
		local bones = frame.rigs[part.rig]
		if bones and bones[part.bone] then
			return bones[part.bone] * part.cf
		end
		return CFrame.new(0, -5000, 0)
	elseif part.fx then
		return frame.parts[part.id] or CFrame.new(0, -5000, 0)
	end
	return part.cf
end

local headH = (def.index.Head and Rig.solve(def, CFrame.new(), pose).Head.Position.Y) or 6
local views = {
	{ "front", Vector3.new(0, headH * 0.6, -1), 0.0 },
	{ "three-quarter", Vector3.new(-0.75, headH * 0.6, -0.75), 0.0 },
	{ "side", Vector3.new(-1, headH * 0.6, 0), 0.0 },
	{ "back", Vector3.new(0.4, headH * 0.6, 1), 0.0 },
	{ "head", Vector3.new(-0.45, headH, -1), 1.0 },
}
local json = E.sceneJson(scene, Particles)
json.fps = 30
json.frames = {}
for i, v in views do
	local fr = Timeline.newFrame(i / 30)
	fr.shot = v[1]
	fr.rigs[who] = Rig.solve(def, CFrame.new(), pose)
	local target = if v[3] > 0.5 then fr.rigs[who].Head.Position + Vector3.new(0, 0.5, 0) else Vector3.new(0, headH * 0.62, 0)
	local dist = if v[3] > 0.5 then headH * 0.55 else headH * 3.1
	local dir = Vector3.new(v[2].X, 0, v[2].Z).Unit
	local eye = target + dir * dist + Vector3.new(0, if v[3] > 0.5 then 0.2 else headH * 0.25, 0)
	fr.camera = Util.lookAt(eye, target)
	fr.fov = 40
	fr.focus = dist
	fr.dof = 0
	if groups then
		for g in string.gmatch(groups, "[^,]+") do
			fr.vis[g] = true
		end
	end
	table.insert(json.frames, E.frameJson(scene, fr, partCFrame, json.dynamicIds))
end
fs.writeFile(outPath, serde.encode("json", json))
print(who, poseName, #scene.parts, "parts ->", outPath)
