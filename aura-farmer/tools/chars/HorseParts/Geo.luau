--!nocheck
-- Геометрические помощники для коня: эллипсоиды по отрезку, цилиндры, плоские многоугольники из клиньев.
-- Все координаты — char space в позе покоя (см. tools/lib/Rig.luau).
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

local V = Vector3.new
local rad = math.rad

local Geo = {}
Geo.__index = Geo

function Geo.new(rig)
	return setmetatable({ rig = rig, xf = nil }, Geo)
end

-- Создать деталь; если задан self.xf (CFrame), он применяется ко всей детали (напр. наклон морды).
function Geo:put(bone, spec)
	if self.xf then
		spec.cf = self.xf * spec.cf
	end
	return self.rig:part(bone, spec)
end

-- Точка с учётом текущего преобразования.
function Geo:pt(p)
	return if self.xf then self.xf * p else p
end

function Geo.hex(h: string)
	return Color3.fromHex(h)
end

-- CFrame с осью X вдоль dir; up — подсказка для оси Y.
function Geo.axisX(pos, dir, up)
	local x = dir.Unit
	up = up or V(0, 1, 0)
	if math.abs(x:Dot(up.Unit)) > 0.98 then
		up = if math.abs(x.Z) < 0.9 then V(0, 0, -1) else V(1, 0, 0)
	end
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

-- CFrame с осью Y вдоль dir (удобно для «костей», висящих вниз); fwd — подсказка для -Z.
function Geo.axisY(pos, dir, fwd)
	local y = dir.Unit
	fwd = fwd or V(0, 0, -1)
	local back = -fwd
	if math.abs(y:Dot(back.Unit)) > 0.98 then
		back = V(1, 0, 0)
	end
	local x = y:Cross(back).Unit
	local z = x:Cross(y).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

local function cfOf(pos, rot)
	local r = rot or V(0, 0, 0)
	return CFrame.new(pos) * CFrame.Angles(rad(r.X), rad(r.Y), rad(r.Z))
end
Geo.cfOf = cfOf

local function merge(spec, extra)
	if extra then
		for k, v in extra do
			spec[k] = v
		end
	end
	return spec
end

-- Эллипсоид (SpecialMesh Sphere). pos: Vector3 или CFrame.
function Geo:ell(bone, pos, size, color, mat, rot, extra)
	local cf = if typeof(pos) == "CFrame" then pos else cfOf(pos, rot)
	return self:put(bone, merge({ cf = cf, size = size, color = color, material = mat or "SmoothPlastic", mesh = "Sphere" }, extra))
end

-- Эллипсоид, вытянутый между точками a и b (концы включительно), сечение w×h (h по умолчанию = w).
-- roll — подсказка «вверх» для сечения.
function Geo:ellSeg(bone, a, b, w, h, color, mat, up, extra)
	local d = b - a
	local cf = Geo.axisX((a + b) / 2, d, up)
	return self:put(bone, merge({ cf = cf, size = V(d.Magnitude, h or w, w), color = color, material = mat or "SmoothPlastic", mesh = "Sphere" }, extra))
end

-- Цилиндр (Part Cylinder) между точками a и b, диаметр d.
function Geo:cylSeg(bone, a, b, d, color, mat, extra)
	local dv = b - a
	local cf = Geo.axisX((a + b) / 2, dv)
	return self:put(bone, merge({ cf = cf, size = V(dv.Magnitude, d, d), color = color, material = mat or "SmoothPlastic", shape = "Cylinder" }, extra))
end

-- Эллиптический цилиндр (SpecialMesh Cylinder в блоке): ось вдоль a->b, сечение w (по up×dir) и h (по up).
function Geo:ecylSeg(bone, a, b, w, h, color, mat, up, extra)
	local dv = b - a
	local cf = Geo.axisY((a + b) / 2, dv, up)
	return self:put(bone, merge({ cf = cf, size = V(w, dv.Magnitude, h), color = color, material = mat or "SmoothPlastic", mesh = "Cylinder" }, extra))
end

function Geo:ball(bone, pos, d, color, mat, extra)
	return self:put(bone, merge({ cf = CFrame.new(pos), size = V(d, d, d), color = color, material = mat or "SmoothPlastic", shape = "Ball" }, extra))
end

function Geo:box(bone, pos, size, color, mat, rot, extra)
	local cf = if typeof(pos) == "CFrame" then pos else cfOf(pos, rot)
	return self:put(bone, merge({ cf = cf, size = size, color = color, material = mat or "SmoothPlastic" }, extra))
end

-- Скруглённый блок (SpecialMesh Head) — для зубов, пряжек, звеньев.
function Geo:rbox(bone, pos, size, color, mat, rot, extra)
	local cf = if typeof(pos) == "CFrame" then pos else cfOf(pos, rot)
	return self:put(bone, merge({ cf = cf, size = size, color = color, material = mat or "SmoothPlastic", mesh = "Head" }, extra))
end

-- Гладкая «трубка» через точки: цилиндры между точками + шары в узлах. d — диаметр (число или функция i->d).
function Geo:tube(bone, pts, d, color, mat, extra, caps)
	local function dia(i)
		return if type(d) == "function" then d(i) else d
	end
	for i = 1, #pts - 1 do
		local di = math.min(dia(i), dia(i + 1))
		self:cylSeg(bone, pts[i], pts[i + 1], di, color, mat, extra)
	end
	for i = 1, #pts do
		if caps ~= false or (i > 1 and i < #pts) then
			self:ball(bone, pts[i], dia(i), color, mat, extra)
		end
	end
end

-- Цепочка капсул (эллипсоиды по отрезкам с перекрытием концов) — гладкий жгут вдвое дешевле tube.
function Geo:caps(bone, pts, d, color, mat, extra, up)
	local function dia(i)
		return if type(d) == "function" then d(i) else d
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dir = b - a
		local l = dir.Magnitude
		if l > 1e-4 then
			local u = dir / l
			local di = (dia(i) + dia(i + 1)) / 2
			local ext = di * 0.42
			self:ellSeg(bone, a - u * ext, b + u * ext, di, di, color, mat, up, extra)
		end
	end
end

-- ===== Плоские фигуры из клиньев =====
-- frame: CFrame плоскости (u = X, v = Y, нормаль = -Z — «лицо» смотрит в -Z фрейма), толщина вдоль Z.

-- Прямоугольный треугольник: прямой угол в (uc, vc), катеты до (uc+wu, vc) и (uc, vc+hv).
function Geo:tri(bone, frame, uc, vc, wu, hv, thick, color, mat, zoff, extra)
	if math.abs(wu) < 1e-4 or math.abs(hv) < 1e-4 then
		return nil
	end
	-- базовая ориентация Ry(90): прямой угол справа-снизу, катеты влево и вверх
	local flip = CFrame.new()
	if wu > 0 then
		flip = flip * CFrame.Angles(0, math.pi, 0)
	end
	if hv < 0 then
		flip = CFrame.Angles(math.pi, 0, 0) * flip
	end
	local cf = frame * CFrame.new(uc + wu / 2, vc + hv / 2, zoff or 0) * flip * CFrame.Angles(0, math.pi / 2, 0)
	return self:put(bone, merge({ cf = cf, size = V(thick, math.abs(hv), math.abs(wu)), color = color, material = mat or "SmoothPlastic", shape = "Wedge" }, extra))
end

-- Трапеция между v0 и v1: левая граница от L0 до L1, правая от R0 до R1.
function Geo:trap(bone, frame, v0, v1, L0, L1, R0, R1, thick, color, mat, zoff, extra, depth)
	depth = depth or 0
	local h = v1 - v0
	if h < 1e-4 then
		return
	end
	local rl, rr = math.max(L0, L1), math.min(R0, R1)
	if rl > rr + 1e-5 then
		if depth > 5 then
			return
		end
		local vm = (v0 + v1) / 2
		local Lm, Rm = (L0 + L1) / 2, (R0 + R1) / 2
		self:trap(bone, frame, v0, vm, L0, Lm, R0, Rm, thick, color, mat, zoff, extra, depth + 1)
		self:trap(bone, frame, vm, v1, Lm, L1, Rm, R1, thick, color, mat, zoff, extra, depth + 1)
		return
	end
	if rr - rl > 1e-4 then
		self:box(bone, frame * CFrame.new((rl + rr) / 2, (v0 + v1) / 2, zoff or 0), V(rr - rl, h, thick), color, mat, nil, extra)
	end
	-- левый треугольник
	if L0 < L1 - 1e-4 then
		self:tri(bone, frame, L1, v0, L0 - L1, h, thick, color, mat, zoff, extra)
	elseif L0 > L1 + 1e-4 then
		self:tri(bone, frame, L0, v1, L1 - L0, -h, thick, color, mat, zoff, extra)
	end
	-- правый треугольник
	if R0 > R1 + 1e-4 then
		self:tri(bone, frame, R1, v0, R0 - R1, h, thick, color, mat, zoff, extra)
	elseif R0 < R1 - 1e-4 then
		self:tri(bone, frame, R0, v1, R1 - R0, -h, thick, color, mat, zoff, extra)
	end
end

-- Прямоугольный треугольник в 3D: прямой угол в R, катеты к A и B. Клин толщиной thick.
function Geo:rtri3(bone, R, A, B, thick, color, mat, extra)
	local ya, zb = A - R, B - R
	local h, w = ya.Magnitude, zb.Magnitude
	if h < 1e-4 or w < 1e-4 then
		return nil
	end
	local Y = ya / h
	local Z = -(zb / w)
	local X = Y:Cross(Z).Unit
	Z = X:Cross(Y).Unit
	local cf = CFrame.fromMatrix((A + B) / 2, X, Y, Z)
	return self:put(bone, merge({ cf = cf, size = V(thick, h, w), color = color, material = mat or "SmoothPlastic", shape = "Wedge" }, extra))
end

-- Произвольный треугольник в 3D -> 2 клина (высота к самой длинной стороне).
function Geo:tri3(bone, a, b, c, thick, color, mat, extra)
	local pts = { a, b, c }
	local best, bi = -1, 1
	for i = 1, 3 do
		local p, q = pts[i], pts[i % 3 + 1]
		local l = (q - p).Magnitude
		if l > best then
			best, bi = l, i
		end
	end
	local p, q, r = pts[bi], pts[bi % 3 + 1], pts[(bi + 1) % 3 + 1]
	local e = (q - p).Unit
	local f = p + e * (r - p):Dot(e)
	self:rtri3(bone, f, r, p, thick, color, mat, extra)
	self:rtri3(bone, f, r, q, thick, color, mat, extra)
end

-- Выпуклый многоугольник pts = { {u, v}, ... } в плоскости frame -> веер треугольников.
function Geo:poly(bone, frame, pts, thick, color, mat, zoff, extra)
	local p3 = {}
	for _, p in pts do
		table.insert(p3, frame * V(p[1], p[2], zoff or 0))
	end
	for i = 2, #p3 - 1 do
		self:tri3(bone, p3[1], p3[i], p3[i + 1], thick, color, mat, extra)
	end
end

-- Плоская панель по 3D-точкам (выпуклый многоугольник; точки проецируются на плоскость первых трёх).
function Geo:panel(bone, pts3, thick, color, mat, extra)
	local a, b, c = pts3[1], pts3[2], pts3[3]
	local n = (b - a):Cross(c - a).Unit
	local o = Vector3.zero
	for _, p in pts3 do
		o += p
	end
	o /= #pts3
	local up = V(0, 1, 0) - n * n.Y
	if up.Magnitude < 1e-3 then
		up = V(0, 0, -1)
	end
	up = up.Unit
	local x = up:Cross(n).Unit
	local frame = CFrame.fromMatrix(o, x, up, n)
	local pts = {}
	for _, p in pts3 do
		local d = p - o
		table.insert(pts, { d:Dot(x), d:Dot(up) })
	end
	self:poly(bone, frame, pts, thick, color, mat, 0, extra)
	return frame, pts
end

-- Обводка многоугольника цилиндрами (замкнутая), d — диаметр.
function Geo:outline(bone, frame, pts, d, color, mat, zoff, extra)
	local n = #pts
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		local pa = frame * V(a[1], a[2], zoff or 0)
		local pb = frame * V(b[1], b[2], zoff or 0)
		local dir = (pb - pa).Unit
		self:cylSeg(bone, pa - dir * d * 0.45, pb + dir * d * 0.45, d, color, mat, extra)
	end
end

-- Сдвиг многоугольника внутрь (для выпуклого, обход любой) на e.
function Geo.inset(pts, e)
	local n = #pts
	-- ориентация
	local area = 0
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		area += a[1] * b[2] - b[1] * a[2]
	end
	local sgn = if area > 0 then 1 else -1
	local lines = {}
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l = math.sqrt(dx * dx + dy * dy)
		local nx, ny = -dy / l * sgn, dx / l * sgn -- внутренняя нормаль
		lines[i] = { a[1] + nx * e, a[2] + ny * e, dx, dy }
	end
	local out = {}
	for i = 1, n do
		local p = lines[(i - 2) % n + 1]
		local q = lines[i]
		-- пересечение p: P + t*dp и q: Q + s*dq
		local den = p[3] * q[4] - p[4] * q[3]
		if math.abs(den) < 1e-9 then
			table.insert(out, { q[1], q[2] })
		else
			local t = ((q[1] - p[1]) * q[4] - (q[2] - p[2]) * q[3]) / den
			table.insert(out, { p[1] + p[3] * t, p[2] + p[4] * t })
		end
	end
	return out
end

return Geo
