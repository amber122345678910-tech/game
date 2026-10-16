--!nocheck
-- Выгрузка сцены в JSON для tools/previz_render.py (Lune).
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Enum = roblox.Enum
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local Previz = {}

local function comps(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return { x, y, z }, { r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function c3(c)
	return { c.R, c.G, c.B }
end

function Previz.newFrame(name: string, cam: CFrame, fov: number, env: any?)
	local pos, rot = comps(cam)
	env = env or {}
	return {
		name = name,
		camera = { pos = pos, rot = rot, fov = fov },
		fog = env.fog,
		sky = env.sky,
		sun = env.sun,
		ambient = env.ambient,
		parts = {},
		beams = {},
		lights = {},
		outlines = {},
	}
end

local function shapeOf(p)
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Sphere then
		return "Ellipsoid", p.Size * mesh.Scale
	end
	if p.ClassName == "WedgePart" then
		return "Wedge", p.Size
	end
	if p.ClassName == "Part" then
		if p.Shape == Enum.PartType.Ball then
			return "Ball", p.Size
		elseif p.Shape == Enum.PartType.Cylinder then
			return "Cylinder", p.Size
		end
	end
	return "Block", p.Size
end

-- В Lune один и тот же Instance при каждом обращении — новый userdata, поэтому ключи таблиц — полные имена.
function Previz.key(inst)
	return inst:GetFullName()
end

-- opts: { cframes = {[fullName]=CFrame}, attach = {[fullName]=CFrame (локальный)}, group = number }
function Previz.addModel(frame, root, opts)
	opts = opts or {}
	local cfOf = opts.cframes or {}
	local attachLocal = opts.attach or {}
	local function partCF(p)
		return cfOf[p:GetFullName()] or p.CFrame
	end
	local list = { root }
	for _, d in root:GetDescendants() do
		table.insert(list, d)
	end
	for _, d in list do
		if d:IsA("BasePart") then
			local tr = d.Transparency
			if tr < 0.98 and not opts.hidden then
				local shape, size = shapeOf(d)
				local pos, rot = comps(partCF(d))
				table.insert(frame.parts, {
					shape = shape,
					pos = pos,
					rot = rot,
					size = { size.X, size.Y, size.Z },
					color = c3(d.Color),
					transparency = tr,
					neon = d.Material == Enum.Material.Neon,
					group = opts.group or 0,
				})
			end
		elseif d:IsA("Beam") and d.Enabled ~= false and not opts.hidden then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				local w0 = partCF(a0.Parent) * (attachLocal[a0:GetFullName()] or a0.CFrame)
				local w1 = partCF(a1.Parent) * (attachLocal[a1:GetFullName()] or a1.CFrame)
				local p0 = w0.Position
				local p3 = w1.Position
				local p1 = p0 + w0.RightVector * d.CurveSize0
				local p2 = p3 - w1.RightVector * d.CurveSize1
				local n = 8
				local pts, ws, cols = {}, {}, {}
				local kps = d.Color.Keypoints
				for i = 0, n do
					local t = i / n
					local u = 1 - t
					local pt = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
					table.insert(pts, { pt.X, pt.Y, pt.Z })
					table.insert(ws, d.Width0 + (d.Width1 - d.Width0) * t)
					local c = kps[1].Value
					local c2 = kps[#kps].Value
					table.insert(cols, { c.R + (c2.R - c.R) * t, c.G + (c2.G - c.G) * t, c.B + (c2.B - c.B) * t })
				end
				local tr = d.Transparency.Keypoints[1].Value
				table.insert(frame.beams, { pts = pts, w = ws, color = cols, transparency = tr, z = d.ZOffset, group = opts.group })
			end
		elseif (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Enabled and d.Brightness > 0 then
			local par = d.Parent
			local wcf
			if par:IsA("Attachment") then
				wcf = partCF(par.Parent) * (attachLocal[par:GetFullName()] or par.CFrame)
			elseif par:IsA("BasePart") then
				wcf = partCF(par)
			end
			if wcf then
				local pos = wcf.Position
				table.insert(frame.lights, { pos = { pos.X, pos.Y, pos.Z }, color = c3(d.Color), brightness = d.Brightness, range = d.Range })
			end
		end
	end
	if opts.group and opts.outline then
		frame.outlines[tostring(opts.group)] = opts.outline
	end
end

function Previz.write(path: string, frames)
	fs.writeFile(path, serde.encode("json", { frames = frames }))
end

-- Стандартные ракурсы для осмотра модели: центр, высота, расстояние
function Previz.orbitViews(center: Vector3, dist: number, height: number)
	local views = {}
	local function at(name, yawDeg, pitchDeg, d)
		local yaw = math.rad(yawDeg)
		local pitch = math.rad(pitchDeg)
		local off = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)) * (d or dist)
		local eye = center + off + Vector3.new(0, height, 0)
		table.insert(views, { name = name, eye = eye, target = center })
	end
	at("front", 0, 5)
	at("front34", 35, 8)
	at("side", 90, 3)
	at("back34", 145, 10)
	at("back", 180, 5)
	at("low_front", 10, -18)
	at("top", 20, 60)
	return views
end

return Previz
