--!nocheck
-- Осмотр персонажа или декорации со стандартных ракурсов (для моделирования).
--   lune run tools/preview/look.luau out.json --char Horse [--opts '{"glasses":"yellow"}'] [--keys path/to/pose.luau --t 0]
--        [--views front,three,side,back,head,hands,feet]
--   lune run tools/preview/look.luau out.json --set Beach --cams "0,5,-20>0,3,0@50;..."  (локальные координаты декорации)
-- Персонаж ставится в начало координат на серый пол, свет — студийный (или пресет --preset Beach).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Loader = require("../lib/loader")
local Build = require("../lib/Build")
local Pose = require("../lib/Pose")
local Config = Loader.load("src/shared/Config")
local FK = Loader.load("src/shared/Anim/FK")
local MathUtil = Loader.load("src/shared/Anim/MathUtil")
local Presets = Loader.load("src/shared/Presets")

local args = process.args
local outPath = args[1]
local opt = {}
local i = 2
while i <= #args do
	opt[string.sub(args[i], 3)] = args[i + 1]
	i += 2
end

local defs = {}
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
local function partDef(p)
	local shape = if p.ClassName == "Part" then p.Shape.Name elseif p.ClassName == "WedgePart" then "Wedge" else "Block"
	local d = { name = p.Name, shape = shape, size = v3(p.Size), color = c3(p.Color), mat = p.Material.Name, tr = p.Transparency, rf = p.Reflectance, shadow = p.CastShadow }
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

local statics, terrains, lights, beams = {}, {}, {}, {}
local parts = {}
local cams = {}
local setName = "Look"
local presetName = opt.preset

if opt.char then
	local build = require("../chars/" .. opt.char)
	local o = if opt.opts then serde.decode("json", opt.opts) else {}
	local rig = build(o)
	local tr = {}
	if opt.keys then
		-- файл ключей: путь от корня aura-farmer, модуль вида return { keys = {...} } (или { Horse = { keys = ... } })
		local luau = require("@lune/luau")
		local anim = luau.load(fs.readFile(opt.keys), { debugName = opt.keys })()
		if not anim.keys then
			local _, first = next(anim)
			anim = first
		end
		local solver = Pose.solver(rig)
		local tracks = Pose.tracks(anim.keys, solver)
		tr = Pose.evaluate(tracks, solver, tonumber(opt.t or "0"))
	end
	rig:finish(CFrame.new())
	local fk = FK.build(rig.model)
	local cfs = {}
	FK.solve(fk, fk.root.CFrame, tr, cfs)
	for k, p in fk.parts do
		if p.Transparency < 1 then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cfs[k]:GetComponents()
			table.insert(parts, { partDef(p), x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 })
		end
	end
	-- пол
	local floor = Instance.new("Part")
	floor.Size = Vector3.new(60, 1, 60)
	floor.CFrame = CFrame.new(0, -0.5, 0)
	floor.Color = roblox.Color3.fromRGB(120, 122, 126)
	floor.Material = roblox.Enum.Material.Concrete
	statics.Look = { { d = partDef(floor), p = v3(floor.CFrame.Position), r = rot9(floor.CFrame) } }
	-- ракурсы
	local P = rig.P
	local H = P.neckY + P.headH
	local headY = P.neckY + P.headH * 0.6
	local handY = P.shoulderY - P.upperArm - P.lowerArm - P.handLen * 0.5
	local views = {
		front = { Vector3.new(0, H * 0.55, -H * 1.55), Vector3.new(0, H * 0.5, 0), 40 },
		three = { Vector3.new(-H * 0.95, H * 0.62, -H * 1.2), Vector3.new(0, H * 0.5, 0), 40 },
		side = { Vector3.new(-H * 1.55, H * 0.55, 0), Vector3.new(0, H * 0.5, 0), 40 },
		back = { Vector3.new(0.01, H * 0.55, H * 1.55), Vector3.new(0, H * 0.5, 0), 40 },
		head = { Vector3.new(-0.9, headY + 0.25, -2.6), Vector3.new(0, headY, -0.3), 40 },
		headside = { Vector3.new(-2.8, headY + 0.1, -0.4), Vector3.new(0, headY, -0.4), 40 },
		hands = { Vector3.new(0, handY + 0.4, -2.8), Vector3.new(0, handY + 0.2, 0), 55 },
		hand = { Vector3.new(-P.shoulderX - 1.4, handY + 0.4, -1.4), Vector3.new(-P.shoulderX, handY, 0), 35 },
		feet = { Vector3.new(-1.2, 1.0, -3.2), Vector3.new(0, 0.4, 0), 40 },
		torso = { Vector3.new(-0.6, P.waistY + 0.6, -3.4), Vector3.new(0, P.waistY + 0.5, 0), 40 },
	}
	for name in string.gmatch(opt.views or "front,three,side,head", "[^,]+") do
		local v = views[name]
		assert(v, "unknown view " .. name)
		table.insert(cams, { name = name, cf = MathUtil.lookAt(v[1], v[2]), fov = v[3] })
	end
	presetName = presetName or "Studio"
elseif opt.set then
	setName = opt.set
	local model = Instance.new("Model")
	model.Name = setName
	require("../sets/" .. setName)(Build.new(setName, model))
	local list, terr, ls, bs = {}, {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("TerrainMaterial") then
				table.insert(terr, { shape = d:GetAttribute("TerrainShape"), material = d:GetAttribute("TerrainMaterial"), size = v3(d.Size), p = v3(d.CFrame.Position), r = rot9(d.CFrame) })
			elseif d.Transparency < 1 then
				table.insert(list, { d = partDef(d), p = v3(d.CFrame.Position), r = rot9(d.CFrame) })
			end
		elseif d:IsA("Light") and d.Enabled and d.Parent:IsA("BasePart") then
			local dirs = { Front = { 0, 0, -1 }, Back = { 0, 0, 1 }, Top = { 0, 1, 0 }, Bottom = { 0, -1, 0 }, Right = { 1, 0, 0 }, Left = { -1, 0, 0 } }
			local face = if d:IsA("PointLight") then "Front" else d.Face.Name
			local dd = dirs[face]
			table.insert(ls, {
				kind = d.ClassName,
				p = v3(d.Parent.CFrame.Position),
				dir = v3(d.Parent.CFrame:VectorToWorldSpace(Vector3.new(dd[1], dd[2], dd[3]))),
				color = c3(d.Color),
				brightness = d.Brightness,
				range = d.Range,
				angle = if d:IsA("PointLight") then 180 else d.Angle,
				shadows = d.Shadows,
			})
		elseif d:IsA("Beam") and d.Attachment0 and d.Attachment1 then
			local kp = d.Transparency.Keypoints
			table.insert(bs, {
				a = v3((d.Attachment0.Parent.CFrame * d.Attachment0.CFrame).Position),
				b = v3((d.Attachment1.Parent.CFrame * d.Attachment1.CFrame).Position),
				w0 = d.Width0,
				w1 = d.Width1,
				color = c3(d.Color.Keypoints[1].Value),
				emission = d.LightEmission,
				t0 = kp[1].Value,
				t1 = kp[#kp].Value,
			})
		end
	end
	statics[setName], terrains[setName], lights[setName], beams[setName] = list, terr, ls, bs
	local origin = Config.Sets[setName]
	for spec in string.gmatch(opt.cams or "0,6,-30>0,4,0@50", "[^;]+") do
		local a, b, f = string.match(spec, "^([^>]+)>([^@]+)@(.+)$")
		local function vec(s)
			local x, y, z = string.match(s, "([^,]+),([^,]+),([^,]+)")
			return (origin * CFrame.new(tonumber(x), tonumber(y), tonumber(z))).Position
		end
		table.insert(cams, { name = spec, cf = MathUtil.lookAt(vec(a), vec(b)), fov = tonumber(f) })
	end
	presetName = presetName or setName
end

local studio = {
	name = "Studio",
	sunDir = { -0.45, 0.65, -0.62 },
	brightness = 2.6,
	exposure = 0,
	ambient = { 0.35, 0.35, 0.38 },
	outdoorAmbient = { 0.55, 0.57, 0.62 },
	envSpecular = 1,
	day = true,
}
local preset
if presetName == "Studio" then
	preset = studio
else
	local p = Presets[presetName]
	assert(p, "unknown preset " .. tostring(presetName))
	local L = p.lighting
	preset = {
		name = presetName,
		sunDir = v3(p.sunDir.Unit),
		brightness = L.Brightness,
		exposure = L.ExposureCompensation or 0,
		ambient = c3(L.Ambient),
		outdoorAmbient = c3(L.OutdoorAmbient),
		envSpecular = L.EnvironmentSpecularScale or 1,
		atmosphere = p.atmosphere and { density = p.atmosphere.Density, color = c3(p.atmosphere.Color) } or nil,
		bloom = p.bloom,
		cc = p.cc and { brightness = p.cc.Brightness, contrast = p.cc.Contrast, saturation = p.cc.Saturation, tint = c3(p.cc.TintColor) } or nil,
		day = (L.Brightness or 0) > 0.5,
	}
end

local frames = {}
for k, c in cams do
	table.insert(frames, {
		t = k,
		lyric = "",
		shot = "LOOK_" .. string.gsub(c.name, "[^%w]", "_"),
		set = setName,
		camera = { p = v3(c.cf.Position), r = rot9(c.cf), fov = c.fov },
		preset = preset,
		parts = parts,
	})
end
fs.writeFile(outPath, serde.encode("json", { defs = defs, statics = statics, terrains = terrains, lights = lights, beams = beams, frames = frames }))
print(string.format("look: %d видов, %d деталей", #frames, #parts))
