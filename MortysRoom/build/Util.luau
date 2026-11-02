--!nocheck
-- Small helpers for building parts with Lune's Roblox library.
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local U = {}
U.Instance = Instance
U.Vector3 = Vector3
U.CFrame = CFrame
U.Color3 = Color3
U.Enum = Enum
U.UDim2 = roblox.UDim2
U.Vector2 = roblox.Vector2
U.UDim = roblox.UDim
U.ColorSequence = roblox.ColorSequence
U.ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
U.NumberSequence = roblox.NumberSequence
U.NumberSequenceKeypoint = roblox.NumberSequenceKeypoint
U.NumberRange = roblox.NumberRange

U.partCount = 0

function U.rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

function U.v(x, y, z)
	return Vector3.new(x, y, z)
end

function U.folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function U.model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function apply(inst, props)
	if props then
		for k, val in props do
			inst[k] = val
		end
	end
end
U.apply = apply

-- Generic anchored part.
function U.part(parent, name, cf, size, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	apply(p, props)
	p.Parent = parent
	U.partCount += 1
	return p
end

-- Axis aligned box from two corners (world space).
function U.box(parent, name, x1, y1, z1, x2, y2, z2, color, material, props)
	local minV = Vector3.new(math.min(x1, x2), math.min(y1, y2), math.min(z1, z2))
	local maxV = Vector3.new(math.max(x1, x2), math.max(y1, y2), math.max(z1, z2))
	local size = maxV - minV
	local center = (minV + maxV) * 0.5
	return U.part(parent, name, CFrame.new(center), size, color, material, props)
end

-- Box from two corners given in a local frame `base`.
function U.boxL(parent, name, base, x1, y1, z1, x2, y2, z2, color, material, props)
	local minV = Vector3.new(math.min(x1, x2), math.min(y1, y2), math.min(z1, z2))
	local maxV = Vector3.new(math.max(x1, x2), math.max(y1, y2), math.max(z1, z2))
	local size = maxV - minV
	local center = (minV + maxV) * 0.5
	return U.part(parent, name, base * CFrame.new(center), size, color, material, props)
end

-- Ellipsoid (SpecialMesh sphere) with any proportions.
function U.ellipsoid(parent, name, cf, size, color, material, props)
	local p = U.part(parent, name, cf, size, color, material, props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- True sphere part.
function U.ball(parent, name, center, diameter, color, material, props)
	local p = U.part(parent, name, CFrame.new(center), Vector3.new(diameter, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Cylinder between two world points.
function U.cyl(parent, name, a, b, diameter, color, material, props)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local cf
	if math.abs(dir.Y) > 0.999 then
		-- straight up/down: lookAt would be undefined
		cf = CFrame.new((a + b) * 0.5) * CFrame.Angles(0, 0, math.rad(90))
	else
		cf = CFrame.lookAt((a + b) * 0.5, b) * CFrame.Angles(0, math.rad(90), 0)
	end
	local p = U.part(parent, name, cf, Vector3.new(len, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Vertical cylinder standing on `bottom` (a Vector3), with height and diameter.
function U.vcyl(parent, name, bottom, height, diameter, color, material, props)
	local center = bottom + Vector3.new(0, height * 0.5, 0)
	local cf = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	local p = U.part(parent, name, cf, Vector3.new(height, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Elliptic cylinder (SpecialMesh cylinder); axis = local X of cf.
function U.ecyl(parent, name, cf, size, color, material, props)
	local p = U.part(parent, name, cf, size, color, material, props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Cylinder
	m.Parent = p
	return p
end

-- Invisible, non-colliding helper part.
function U.marker(parent, name, cf, size)
	return U.part(parent, name, cf, size or Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(255, 0, 255), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

-- Simple deterministic random so every build is identical.
local seed = 1337
function U.rand()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
function U.randRange(a, b)
	return a + (b - a) * U.rand()
end

-- UI helper for SurfaceGuis built at edit time.
function U.ui(class, props, children)
	local inst = Instance.new(class)
	local parent = nil
	if props then
		for k, val in props do
			if k == "Parent" then
				parent = val
			else
				inst[k] = val
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function U.surfaceGui(part, face, pixelsPerStud, lightInfluence)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Art"
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pixelsPerStud or 100
	sg.LightInfluence = lightInfluence or 1
	sg.ClipsDescendants = true
	sg.Parent = part
	return sg
end

--[[
	A flat wall with rectangular holes (doors / windows).
	axis = "x": the wall runs along X (a1..a2), thickness along Z (t1..t2), holes = {{x1, x2, y1, y2}, ...}
	axis = "z": the wall runs along Z (a1..a2), thickness along X (t1..t2), holes = {{z1, z2, y1, y2}, ...}
]]
function U.wall(parent, name, axis, a1, a2, y1, y2, t1, t2, holes, color, material, props)
	holes = holes or {}
	local cuts = { a1, a2 }
	for _, h in holes do
		table.insert(cuts, math.clamp(h[1], a1, a2))
		table.insert(cuts, math.clamp(h[2], a1, a2))
	end
	table.sort(cuts)
	local parts = {}
	local function emit(aa, ab, ya, yb)
		if ab - aa < 1e-3 or yb - ya < 1e-3 then
			return
		end
		local p
		if axis == "x" then
			p = U.box(parent, name, aa, ya, t1, ab, yb, t2, color, material, props)
		else
			p = U.box(parent, name, t1, ya, aa, t2, yb, ab, color, material, props)
		end
		table.insert(parts, p)
	end
	for i = 1, #cuts - 1 do
		local aa, ab = cuts[i], cuts[i + 1]
		if ab - aa > 1e-3 then
			local blocked = {}
			for _, h in holes do
				if h[1] <= aa + 1e-4 and h[2] >= ab - 1e-4 then
					table.insert(blocked, { math.max(h[3], y1), math.min(h[4], y2) })
				end
			end
			table.sort(blocked, function(p1, p2)
				return p1[1] < p2[1]
			end)
			local y = y1
			for _, b in blocked do
				if b[1] > y then
					emit(aa, ab, y, b[1])
				end
				y = math.max(y, b[2])
			end
			if y < y2 then
				emit(aa, ab, y, y2)
			end
		end
	end
	return parts
end

-- Wedge (triangular prism). Roblox wedge: vertical face at local +Z (back), slope rising from front-bottom (-Z) to back-top.
function U.wedge(parent, name, cf, size, color, material, props)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, val in props do
			p[k] = val
		end
	end
	p.Parent = parent
	U.partCount += 1
	return p
end

return U
