--!nocheck
-- Face lab: paints the close-up faces for a style and writes them as JSON
-- (reference-pixel space) so the browser renderer can draw them next to the
-- reference frame.  Usage: lune run tools/facelab.luau <style> <out.json>
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local root = "src/Cutscene"
local Loader = require("./loader")
local S = require("./serialize")

local styleId = process.args[1] or "anime"
local outPath = process.args[2] or "build/facelab.json"

local Styles = Loader.load(root .. "/Styles")
local Paint = Loader.load(root .. "/Paint")
local YutaEyes = Loader.load(root .. "/Art/Faces/YutaEyes")
local RyuEyes = Loader.load(root .. "/Art/Faces/RyuEyes")

local style = Styles.get(styleId)
local out = { style = styleId, panels = {} }
for _, f in { { "yuta", YutaEyes }, { "ryu", RyuEyes } } do
	local mod = f[2]
	local c = Paint.canvas(1, mod.X0, mod.Y0)
	mod.paint(c, style.color, style.face.line, style.face.soft)
	table.insert(out.panels, {
		name = f[1],
		x0 = mod.X0,
		y0 = mod.Y0,
		w = mod.X1 - mod.X0,
		h = mod.Y1 - mod.Y0,
		elems = S.elems(c.elems),
	})
	print(f[1], #c.elems, "elements")
end
fs.writeFile(outPath, serde.encode("json", out))
