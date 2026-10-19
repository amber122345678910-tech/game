--!nocheck
-- Выгрузка кадров ролика в JSON для рендера-превью (three.js).
-- Использует ТОТ ЖЕ код, что и игра: KFS-проигрыватель, FK, камеру, пресеты.
--
--   lune run tools/preview/dump.luau out.json --shot S04 --n 6
--   lune run tools/preview/dump.luau out.json --times 4.0,4.5,5.2
--   lune run tools/preview/dump.luau out.json --shot S04 --times 4.0,4.5   (только этот план)

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("../lib/loader")
local World = require("../lib/World")

local Config = Loader.load("src/shared/Config")
local Timeline = Loader.load("src/shared/Timeline")
local KFS = Loader.load("src/shared/Anim/KFS")
local FK = Loader.load("src/shared/Anim/FK")
local CameraTrack = Loader.load("src/shared/CameraTrack")
local Presets = Loader.load("src/shared/Presets")
local Lyrics = Loader.load("src/shared/Lyrics")

local args = process.args
local outPath = args[1] or "preview.json"
local opt = {}
local i = 2
while i <= #args do
	local a = args[i]
	if string.sub(a, 1, 2) == "--" then
		opt[string.sub(a, 3)] = args[i + 1]
		i += 2
	else
		i += 1
	end
end

-- Какие моменты рендерить
local times = {}
if opt.times then
	for s in string.gmatch(opt.times, "[^,]+") do
		table.insert(times, tonumber(s))
	end
end
local onlyShot = opt.shot
if #times == 0 then
	local n = tonumber(opt.n or "4")
	if onlyShot then
		local shot = Timeline.byId(onlyShot)
		assert(shot, "нет плана " .. onlyShot)
		for k = 0, n - 1 do
			table.insert(times, shot.start + (k + 0.5) / n * (shot.finish - shot.start))
		end
	else
		for k = 0, n - 1 do
			table.insert(times, (k + 0.5) / n * Config.BlackFrom)
		end
	end
end

-- Какие планы строить
local shotIds = {}
local seen = {}
for _, t in times do
	local shot = if onlyShot then Timeline.byId(onlyShot) else Timeline.shotAt(t)
	if not seen[shot.id] then
		seen[shot.id] = true
		table.insert(shotIds, shot.id)
	end
end

local world = World.build({ shots = shotIds })

local function v3(v)
	return { v.X, v.Y, v.Z }
end
local function c3(c)
	return { c.R, c.G, c.B }
end
local function rot9(cf)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local defs = {}
local function partDef(p)
	local shape = "Block"
	if p.ClassName == "Part" then
		shape = p.Shape.Name
	elseif p.ClassName == "WedgePart" then
		shape = "Wedge"
	elseif p.ClassName == "CornerWedgePart" then
		shape = "CornerWedge"
	end
	local d = {
		name = p.Name,
		shape = shape,
		size = v3(p.Size),
		color = c3(p.Color),
		mat = p.Material.Name,
		tr = p.Transparency,
		rf = p.Reflectance,
		shadow = p.CastShadow,
	}
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		d.mesh = mesh.MeshType.Name
		d.meshScale = v3(mesh.Scale)
		d.meshOffset = v3(mesh.Offset)
	end
	local texts = {}
	for _, g in p:GetChildren() do
		if g:IsA("SurfaceGui") then
			local lbl = g:FindFirstChildWhichIsA("TextLabel")
			if lbl then
				table.insert(texts, { face = g.Face.Name, text = lbl.Text, color = c3(lbl.TextColor3) })
			end
		end
	end
	if #texts > 0 then
		d.texts = texts
	end
	table.insert(defs, d)
	return #defs - 1
end

local function lightsOf(container)
	local out = {}
	for _, l in container:GetDescendants() do
		if l:IsA("Light") and l.Enabled then
			local p = l.Parent
			if p and p:IsA("BasePart") then
				local face = if l:IsA("SpotLight") or l:IsA("SurfaceLight") then l.Face.Name else nil
				local dirs = { Front = { 0, 0, -1 }, Back = { 0, 0, 1 }, Top = { 0, 1, 0 }, Bottom = { 0, -1, 0 }, Right = { 1, 0, 0 }, Left = { -1, 0, 0 } }
				local d = dirs[face or "Front"]
				local world = p.CFrame:VectorToWorldSpace(require("@lune/roblox").Vector3.new(d[1], d[2], d[3]))
				table.insert(out, {
					kind = l.ClassName,
					p = v3(p.CFrame.Position),
					dir = v3(world),
					color = c3(l.Color),
					brightness = l.Brightness,
					range = l.Range,
					angle = if l:IsA("SpotLight") or l:IsA("SurfaceLight") then l.Angle else 180,
					shadows = l.Shadows,
					size = v3(p.Size),
				})
			end
		end
	end
	return out
end

local function beamsOf(container)
	local out = {}
	for _, b in container:GetDescendants() do
		if b:IsA("Beam") and b.Enabled and b.Attachment0 and b.Attachment1 then
			local tr = 0
			for _, kp in b.Transparency.Keypoints do
				tr += kp.Value
			end
			tr /= #b.Transparency.Keypoints
			table.insert(out, {
				a = v3((b.Attachment0.Parent.CFrame * b.Attachment0.CFrame).Position),
				b = v3((b.Attachment1.Parent.CFrame * b.Attachment1.CFrame).Position),
				w0 = b.Width0,
				w1 = b.Width1,
				color = c3(b.Color.Keypoints[1].Value),
				tr = tr,
				emission = b.LightEmission,
				t0 = b.Transparency.Keypoints[1].Value,
				t1 = b.Transparency.Keypoints[#b.Transparency.Keypoints].Value,
			})
		end
	end
	return out
end

-- Статичные декорации
local statics = {}
local terrains = {}
local setLights = {}
local setBeams = {}
for name, model in world.sets do
	local list = {}
	local terr = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("TerrainMaterial") then
				table.insert(terr, {
					shape = d:GetAttribute("TerrainShape"),
					material = d:GetAttribute("TerrainMaterial"),
					size = v3(d.Size),
					p = v3(d.CFrame.Position),
					r = rot9(d.CFrame),
				})
			elseif d.Transparency < 1 or d:FindFirstChildWhichIsA("Light") then
				table.insert(list, { d = partDef(d), p = v3(d.CFrame.Position), r = rot9(d.CFrame) })
			end
		end
	end
	statics[name] = list
	terrains[name] = terr
	setLights[name] = lightsOf(model)
	setBeams[name] = beamsOf(model)
end

-- Актёры: FK-риги, клипы, определения деталей
local actorData = {}
for id, entry in world.shots do
	for actorName, a in entry.actors do
		local rig = FK.build(a.model)
		local defIdx = {}
		for k, p in rig.parts do
			if p.Transparency < 1 then
				defIdx[k] = partDef(p)
			end
		end
		actorData[a.name] = {
			rig = rig,
			clip = if a.kfs then KFS.compile(a.kfs) else nil,
			defIdx = defIdx,
			shot = id,
		}
	end
end

local frames = {}
for _, t in times do
	local shot = if onlyShot then Timeline.byId(onlyShot) else Timeline.shotAt(t)
	local entry = world.shots[shot.id]
	local cam = CameraTrack.evaluate(shot, t)
	local preset = Presets.resolve(shot)
	local parts = {}
	local focusPoint = nil
	for actorName, a in entry.actors do
		local ad = actorData[a.name]
		local tr = {}
		if ad.clip then
			KFS.sample(ad.clip, t - shot.start, tr)
		end
		local cfs = {}
		FK.solve(ad.rig, ad.rig.root.CFrame, tr, cfs)
		for k, cf in cfs do
			local di = ad.defIdx[k]
			if di then
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
				table.insert(parts, { di, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 })
			end
		end
		local f = shot.camera.focus
		if type(f) == "table" and f.actor == actorName then
			for k, p in ad.rig.parts do
				if p.Name == (f.part or "Head") then
					focusPoint = v3(cfs[k].Position)
				end
			end
		end
	end
	local L = preset.lighting or {}
	local function col(c, def)
		return if c then c3(c) else def
	end
	local lyric = ""
	for _, l in Lyrics do
		if t >= l.start and t < l.finish then
			lyric = l.text
		end
	end
	table.insert(frames, {
		t = t,
		lyric = lyric,
		shot = shot.id,
		set = shot.set,
		camera = { p = v3(cam.cframe.Position), r = rot9(cam.cframe), fov = cam.fov, blur = cam.blur, focus = focusPoint },
		preset = {
			name = shot.preset,
			sunDir = v3(preset.sunDir.Unit),
			brightness = L.Brightness or 2,
			exposure = L.ExposureCompensation or 0,
			ambient = col(L.Ambient, { 0.3, 0.3, 0.3 }),
			outdoorAmbient = col(L.OutdoorAmbient, { 0.5, 0.5, 0.5 }),
			colorShiftTop = col(L.ColorShift_Top, { 0, 0, 0 }),
			envDiffuse = L.EnvironmentDiffuseScale or 1,
			envSpecular = L.EnvironmentSpecularScale or 1,
			atmosphere = preset.atmosphere and {
				density = preset.atmosphere.Density or 0,
				offset = preset.atmosphere.Offset or 0,
				color = col(preset.atmosphere.Color, { 0.8, 0.8, 0.8 }),
				haze = preset.atmosphere.Haze or 0,
				glare = preset.atmosphere.Glare or 0,
			} or nil,
			bloom = preset.bloom,
			cc = preset.cc and {
				brightness = preset.cc.Brightness or 0,
				contrast = preset.cc.Contrast or 0,
				saturation = preset.cc.Saturation or 0,
				tint = col(preset.cc.TintColor, { 1, 1, 1 }),
			} or nil,
			day = (L.Brightness or 0) > 0.5,
		},
		parts = parts,
	})
end

local out = {
	defs = defs,
	statics = statics,
	terrains = terrains,
	lights = setLights,
	beams = setBeams,
	frames = frames,
}
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("dump: %d кадров, %d определений деталей -> %s", #frames, #defs, outPath))
for _, s in world.stats do
	print("  " .. s)
end
