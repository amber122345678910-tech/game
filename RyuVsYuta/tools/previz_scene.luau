--!nocheck
-- Превиз всей катсцены: строит модели, считает Sequence в заданные моменты и пишет JSON для рендера.
-- lune run tools/previz_scene.luau out.json [t1,t2,... | all:<step>] [noenv]
-- Затем: python3 tools/previz_render.py out.json out_dir --sheet 4
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")
local Previz = require("./lib/previz")

local out = process.args[1] or "scene.json"
local timesArg = process.args[2] or "all:1"
local noEnv = process.args[3] == "noenv"

local Rig = Loader.load("src/shared/Rig")
local Hair = Loader.load("src/shared/Anim/Hair")
local Skeletons = Loader.load("src/shared/Skeletons")
local Sequence = Loader.load("src/shared/Sequence/Sequence")
local FogCards = Loader.load("src/shared/Sequence/FogCards")

local chars = {}
local fs = require("@lune/fs")
for _, name in { "Rika", "Yuta", "Ryu" } do
	local origin = Sequence.buildOrigin(name)
	local model
	if fs.isFile("src/shared/Builders/" .. name .. ".luau") and process.env.PREVIZ_MANNEQUIN ~= "1" then
		model = Loader.load("src/shared/Builders/" .. name).build(origin)
	else
		-- модели ещё нет — манекен на том же скелете
		model = Loader.load("tools/tests/Mannequin").build(origin, name)
	end
	local def = Skeletons[name]
	chars[name] = { model = model, def = def, binding = Rig.bind(def, model, origin), group = #chars + 1 }
end
local env = nil
if not noEnv and fs.isFile("src/shared/Builders/Environment.luau") then
	local E = Loader.load("src/shared/Builders/Environment")
	env = E.build()
end

local times = {}
if string.sub(timesArg, 1, 4) == "all:" then
	local step = tonumber(string.sub(timesArg, 5)) or 1
	local t = 0
	while t <= Sequence.duration() + 1e-6 do
		table.insert(times, t)
		t += step
	end
else
	for s in string.gmatch(timesArg, "[^,]+") do
		table.insert(times, tonumber(s))
	end
end

local groupIds = { Rika = 1, Yuta = 2, Ryu = 3 }
local frames = {}
for _, t in times do
	local frame = Sequence.evaluate(t)
	local e = frame.env
	local fc = e.fogColor
	local fr = Previz.newFrame(string.format("t%05.2f_%s", t, frame.shotName), frame.camera.cf, frame.camera.fov, {
		fog = { density = e.fogDensity, color = { fc.R, fc.G, fc.B }, skyMix = math.min(0.95, e.fogDensity * 1.5) },
		sky = { { 0.85, 0.87, 0.95 }, { 0.42, 0.56, 0.84 } },
		sun = { 0.25, 0.75, 0.6 },
		ambient = { e.ambient.R + 0.25, e.ambient.G + 0.25, e.ambient.B + 0.28 },
	})
	for name, c in chars do
		local st = frame.chars[name]
		if st and st.visible then
			local world = Rig.solve(c.def, st.origin, st.pose, st.ik)
			local cfs = Rig.partCFrames(c.binding, world, t, st.flutter)
			local map = {}
			for i, p in c.binding.parts do
				map[p:GetFullName()] = cfs[i]
			end
			local attach = {}
			if st.hair then
				local hs = st.hair
				for i, a in c.binding.attachments do
					local w = c.binding.attachWeight[i]
					if w > 0 then
						local carrierCF = map[a.Parent:GetFullName()] or a.Parent.CFrame
						local params = {
							wind = carrierCF:VectorToObjectSpace(hs.wind),
							lift = carrierCF:VectorToObjectSpace(hs.lift),
							turbulence = hs.turbulence,
							freq = hs.freq,
							scale = hs.scale,
						}
						attach[a:GetFullName()] = Hair.pointCFrame(c.binding.attachRest[i], w, c.binding.attachSeed[i], t, params)
					end
				end
			end
			Previz.addModel(fr, c.model, { cframes = map, attach = attach, group = groupIds[name], outline = st.outline })
		end
	end
	if env then
		Previz.addModel(fr, env, { group = 10 })
	end
	if frame.shotName ~= "End" then
		fr.sprites = {}
		local shot = if frame.shotName == "A" then "A" else "BC"
		for _, c in FogCards.evaluate(t, shot, frame.camera.cf) do
			local p = c.center
			table.insert(fr.sprites, { center = { p.X, p.Y, p.Z }, w = c.w, h = c.h, roll = c.roll, alpha = c.alpha, color = { c.color.R, c.color.G, c.color.B } })
		end
		-- силуэт в дыму: заливка цветом тумана
		for name, c in chars do
			local st = frame.chars[name]
			if st and st.visible and (st.fill or 0) > 0 then
				fr.fills = fr.fills or {}
				fr.fills[tostring(groupIds[name])] = { alpha = st.fill, color = { 0.725, 0.765, 0.87 } }
			end
		end
	end
	table.insert(frames, fr)
end
Previz.write(out, frames)
print(string.format("frames=%d duration=%.1f", #frames, Sequence.duration()))
