--!nocheck
-- Exports a style's scene and its frames as JSON for the offline preview.
-- Runs the exact same Luau scene/timeline code as Roblox does.
-- Usage: lune run tools/export.luau <style> <out.json> [fps] [t0] [t1]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Loader = require("./loader")
local S = require("./serialize")

local root = "src/Cutscene"
local Scene = Loader.load(root .. "/Scene")

local styleId = process.args[1] or "anime"
local outPath = process.args[2] or ("build/" .. styleId .. ".json")
local fps = tonumber(process.args[3] or "30")
local t0 = tonumber(process.args[4] or "0")
local t1 = tonumber(process.args[5] or tostring(Scene.DURATION))

local scene = Scene.build(styleId)
local st = scene.style

local parts = {}
local dynamicIds = {}
for _, p in scene.parts do
	local o = {
		id = p.id,
		name = p.name,
		model = p.model,
		shape = p.shape,
		size = S.v3(p.size),
		color = S.color(p.color),
		material = p.material,
		transparency = p.transparency,
		castShadow = p.castShadow,
		studs = p.studs,
		cf = S.cf(p.cf),
	}
	if p.gui then
		o.gui = {
			face = p.gui.face,
			canvas = { p.gui.canvas.X, p.gui.canvas.Y },
			lightInfluence = p.gui.lightInfluence,
			elems = S.elems(p.gui.elems),
		}
	end
	if p.rig or p.channel then
		table.insert(dynamicIds, p.id)
	end
	table.insert(parts, o)
end

local function colorTable(t)
	local o = {}
	for k, v in t do
		if typeof(v) == "Color3" then
			o[k] = S.color(v)
		else
			o[k] = v
		end
	end
	return o
end

local styleOut = {
	id = st.id,
	title = st.title,
	lighting = colorTable(st.lighting),
	atmosphere = st.atmosphere and colorTable(st.atmosphere) or nil,
	clouds = st.clouds and colorTable(st.clouds) or nil,
	defaultSky = st.defaultSky,
	post = {
		bloom = st.post.bloom,
		cc = st.post.cc and colorTable(st.post.cc) or nil,
		dof = st.post.dof,
		sunrays = st.post.sunrays,
	},
	outline = st.outline and { color = S.color(st.outline.color), transparency = st.outline.transparency } or nil,
	vignette = st.vignette,
	snow = st.snow,
}

local emitters = {}
for _, e in scene.emitters do
	table.insert(emitters, {
		name = e.name,
		kind = e.kind,
		cf = S.cf(e.cf),
		size = S.v3(e.size),
		rate = e.rate,
		color = S.color(e.color),
		sizeRange = e.sizeRange,
		speed = e.speed,
		lifetime = e.lifetime,
		transparency = e.transparency,
	})
end

local models = {}
for _, m in scene.models do
	table.insert(models, { name = m.name, outline = m.outline })
end

local frames = {}
local n = math.floor((t1 - t0) * fps + 0.5)
for i = 0, n - 1 do
	local t = t0 + i / fps
	local fr = Scene.evaluate(scene, t)
	local cfs = {}
	for _, id in dynamicIds do
		cfs[#cfs + 1] = S.cf(Scene.partCFrame(scene.parts[id], fr))
	end
	local overlay = {}
	for k, v in fr.overlay do
		overlay[k] = v
	end
	table.insert(frames, {
		t = t,
		shot = fr.shot,
		camera = S.cf(fr.camera),
		fov = fr.fov,
		focus = fr.focus,
		dof = fr.dof,
		cfs = cfs,
		overlay = overlay,
	})
end

local out = {
	style = styleOut,
	parts = parts,
	models = models,
	emitters = emitters,
	overlay = S.elems(scene.overlay),
	dynamicIds = dynamicIds,
	fps = fps,
	frames = frames,
}
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("%s: %d parts (%d dynamic), %d frames -> %s", styleId, #parts, #dynamicIds, #frames, outPath))
