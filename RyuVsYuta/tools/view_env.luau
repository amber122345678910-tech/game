--!nocheck
-- Превиз окружения с камер ключевых кадров: lune run tools/view_env.luau out.json
-- python3 tools/previz_render.py out.json out_dir --w 480 --h 270 --sheet 3
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")
local Previz = require("./lib/previz")
local Vector3 = roblox.Vector3
local MathX = Loader.load("src/shared/Math")
local Env = Loader.load("src/shared/Builders/Environment")
local out = process.args[1] or "env.json"
local fogScale = tonumber(process.args[2] or "1") or 1
local model = Env.build()
local n = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
print("environment parts: " .. n)
local views = {
	{ "A1_fog_drift", Vector3.new(2, 6, -18), Vector3.new(0, 8, 60), 60, 0.55 },
	{ "A2_rika_emerges", Vector3.new(0.5, 4, 10), Vector3.new(-1, 12, 48), 55, 0.45 },
	{ "B_ryu_wide", Vector3.new(0, 31.2, -111), Vector3.new(0, 34.5, -120), 50, 0.05 },
	{ "C_ryu_close", Vector3.new(0.3, 35.6, -117.6), Vector3.new(0, 37.2, -120), 40, 0.03 },
	{ "overview_high", Vector3.new(-160, 120, 180), Vector3.new(0, 10, 0), 60, 0.0 },
	{ "overview_side", Vector3.new(220, 60, -40), Vector3.new(0, 15, -40), 60, 0.0 },
	{ "behind_ryu", Vector3.new(0, 34, -126), Vector3.new(0, 20, 40), 60, 0.1 },
	{ "street_level", Vector3.new(-6, 3, -40), Vector3.new(0, 4, 120), 70, 0.0 },
	{ "sky_minusZ", Vector3.new(0, 31, -110), Vector3.new(0, 250, -1200), 60, 0.0 },
}
local frames = {}
for _, v in views do
	local fr = Previz.newFrame(v[1], MathX.lookAt(v[2], v[3]), v[4], {
		fog = { density = v[5] * fogScale, color = { 0.77, 0.79, 0.91 }, skyMix = 0.6 },
		sky = { { 0.85, 0.87, 0.95 }, { 0.42, 0.56, 0.84 } },
		sun = { 0.3, 0.75, 0.6 },
		ambient = { 0.55, 0.57, 0.66 },
	})
	Previz.addModel(fr, model, { group = 10 })
	table.insert(frames, fr)
end
Previz.write(out, frames)
