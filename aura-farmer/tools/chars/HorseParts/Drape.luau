--!nocheck
-- «Драпировка»: плоские контуры (вид спереди x,y) проецируются на переднюю поверхность торса
-- и собираются из треугольников (клинья), поэтому лацканы/воротник/планки облегают грудь.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local V = roblox.Vector3.new

local Drape = {}
Drape.__index = Drape

-- shapes = { { c = Vector3, r = Vector3 }, ... } — эллипсоиды, образующие переднюю поверхность.
function Drape.new(g, shapes)
	return setmetatable({ g = g, shapes = shapes }, Drape)
end

-- z передней поверхности в точке (x, y) (минимум по эллипсоидам); nil, если вне всех.
function Drape:z(x, y)
	local best = nil
	for _, e in self.shapes do
		local dx, dy = (x - e.c.X) / e.r.X, (y - e.c.Y) / e.r.Y
		local t = 1 - dx * dx - dy * dy
		if t > 0 then
			local z = e.c.Z - e.r.Z * math.sqrt(t)
			if best == nil or z < best then
				best = z
			end
		end
	end
	return best
end

-- Точка на поверхности со смещением наружу off (по нормали) и нормаль.
function Drape:at(x, y, off)
	local h = 0.01
	local z = self:z(x, y) or 0
	local zx = (self:z(x + h, y) or z) - (self:z(x - h, y) or z)
	local zy = (self:z(x, y + h) or z) - (self:z(x, y - h) or z)
	-- поверхность z(x,y), смотрит в -Z: нормаль = (dz/dx, dz/dy, -1)
	local n = V(zx / (2 * h), zy / (2 * h), -1).Unit
	return V(x, y, z) + n * (off or 0), n
end

local function subdivide(pts, maxLen, closed)
	local out = {}
	local n = #pts
	local last = if closed then n else n - 1
	for i = 1, last do
		local a, b = pts[i], pts[i % n + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l = math.sqrt(dx * dx + dy * dy)
		local k = math.max(1, math.ceil(l / maxLen))
		for j = 0, k - 1 do
			table.insert(out, { a[1] + dx * j / k, a[2] + dy * j / k })
		end
	end
	if not closed then
		table.insert(out, pts[n])
	end
	return out
end
Drape.subdivide = subdivide

-- Залитый контур (звёздный относительно центроида): веер треугольников с вершинами на поверхности.
-- pts = { {x, y}, ... }; center — необязательный центр веера {x, y}.
function Drape:fill(bone, pts, off, thick, color, mat, maxLen, extra, center)
	local outline = subdivide(pts, maxLen or 0.3, true)
	local cx, cy = 0, 0
	if center then
		cx, cy = center[1], center[2]
	else
		for _, p in pts do
			cx += p[1]
			cy += p[2]
		end
		cx /= #pts
		cy /= #pts
	end
	local c = self:at(cx, cy, off)
	local ring = {}
	for _, p in outline do
		table.insert(ring, (self:at(p[1], p[2], off)))
	end
	local n = #ring
	for i = 1, n do
		self.g:tri3(bone, ring[i], ring[i % n + 1], c, thick, color, mat, extra)
	end
	return ring, c
end

-- Лента между двумя цепочками точек (левая и правая кромки, одинаковой длины, сверху вниз):
-- четырёхугольники по 2 треугольника — мягкие «складки» поперёк ленты.
function Drape:strip(bone, left, right, off, thick, color, mat, extra)
	extra = extra or { castShadow = false }
	local L, R = {}, {}
	for i = 1, #left do
		L[i] = self:at(left[i][1], left[i][2], off)
		R[i] = self:at(right[i][1], right[i][2], off)
	end
	for i = 1, #left - 1 do
		if (R[i] - L[i]).Magnitude > 1e-3 then
			self.g:tri3(bone, L[i], R[i], R[i + 1], thick, color, mat, extra)
		end
		if (L[i + 1] - R[i + 1]).Magnitude > 1e-3 then
			self.g:tri3(bone, L[i], R[i + 1], L[i + 1], thick, color, mat, extra)
		end
	end
	return L, R
end

-- Трубка вдоль ломаной на поверхности.
function Drape:tube(bone, pts, off, d, color, mat, maxLen, closed, extra)
	local line = subdivide(pts, maxLen or 0.25, closed)
	local p3 = {}
	for _, p in line do
		table.insert(p3, (self:at(p[1], p[2], off)))
	end
	if closed then
		table.insert(p3, p3[1])
	end
	self.g:tube(bone, p3, d, color, mat, extra)
end

-- CFrame детали, лежащей на поверхности в (x, y): -Z смотрит наружу по нормали, поворот rot (град) вокруг нормали.
function Drape:cf(x, y, off, rot)
	local p, n = self:at(x, y, off)
	local up = V(0, 1, 0)
	local back = -n
	local right = up:Cross(back).Unit
	local up2 = back:Cross(right).Unit
	return CFrame.fromMatrix(p, right, up2, back) * CFrame.Angles(0, 0, math.rad(rot or 0))
end

return Drape
