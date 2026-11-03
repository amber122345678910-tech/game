--!strict
-- Vector "painting" with plain Roblox UI frames (no uploaded images).
--
-- Everything is drawn with rectangles, pills (Frame + UICorner) and gradients.
-- Curves are drawn as chains of overlapping pills ("brush strokes") whose
-- thickness can change along the stroke, which gives tapered anime lines.
-- Sharp convex shapes are drawn as a covering rectangle plus "cut" rectangles
-- painted in the color underneath (painter's algorithm).
--
-- A Canvas only produces data (a flat list of elements in draw order). The
-- Realizer turns the list into Frames inside a SurfaceGui; the offline preview
-- renderer draws the same list with an HTML canvas.
local Util = require(script.Parent.Util)

local Paint = {}

export type GradSpec = {
	color: ColorSequence?,
	transparency: NumberSequence?,
	rotation: number?,
}

export type Elem = {
	x: number, -- center, canvas px
	y: number,
	w: number,
	h: number,
	rot: number, -- degrees, clockwise (Roblox GuiObject.Rotation)
	color: Color3,
	alpha: number, -- BackgroundTransparency
	radius: number, -- corner radius in px; -1 means "pill" (UDim scale 0.5)
	grad: GradSpec?,
	group: string?,
}

export type Canvas = {
	elems: { Elem },
	scale: number,
	ox: number,
	oy: number,
	group: string?,
	-- Methods
	setGroup: (self: Canvas, g: string?) -> (),
	rect: (self: Canvas, x: number, y: number, w: number, h: number, rot: number, color: Color3, alpha: number?, radius: number?) -> Elem,
	box: (self: Canvas, x0: number, y0: number, x1: number, y1: number, color: Color3, alpha: number?) -> Elem,
	grad: (self: Canvas, x0: number, y0: number, x1: number, y1: number, g: GradSpec, color: Color3?, alpha: number?) -> Elem,
	pill: (self: Canvas, x: number, y: number, len: number, thick: number, rot: number, color: Color3, alpha: number?) -> Elem,
	circle: (self: Canvas, x: number, y: number, r: number, color: Color3, alpha: number?) -> Elem,
	ellipse: (self: Canvas, x: number, y: number, rx: number, ry: number, rot: number, color: Color3) -> (),
	stroke: (self: Canvas, pts: { { number } }, widths: { number } | number, color: Color3, opts: StrokeOpts?) -> (),
	poly: (self: Canvas, pts: { { number } }, color: Color3, cutColor: Color3) -> (),
	edge: (self: Canvas, pts: { { number } }, depth: number, side: number, color: Color3) -> (),
	blob: (self: Canvas, x: number, y: number, w: number, h: number, color: Color3, alpha: number, layers: number?) -> (),
}

export type StrokeOpts = {
	maxStep: number?, -- longest pill (canvas units, before scale)
	minStep: number?, -- shortest pill: coarse strokes for big 2D overlays
	minWidth: number?,
	closed: boolean?,
}

local Canvas = {}
Canvas.__index = Canvas

function Paint.canvas(scale: number, ox: number, oy: number): Canvas
	local self = setmetatable({
		elems = {},
		scale = scale,
		ox = ox,
		oy = oy,
		group = nil,
	}, Canvas)
	return (self :: any) :: Canvas
end

function Canvas.setGroup(self: Canvas, g: string?)
	self.group = g
end

local function push(self: Canvas, e: Elem): Elem
	e.group = self.group
	table.insert(self.elems, e)
	return e
end

-- Rectangle centered at (x, y) in design units.
function Canvas.rect(self: Canvas, x: number, y: number, w: number, h: number, rot: number, color: Color3, alpha: number?, radius: number?): Elem
	local s = self.scale
	local r = radius or 0
	return push(self, {
		x = (x - self.ox) * s,
		y = (y - self.oy) * s,
		w = w * s,
		h = h * s,
		rot = rot,
		color = color,
		alpha = alpha or 0,
		radius = if r < 0 then -1 else r * s,
	})
end

-- Axis-aligned box from corners.
function Canvas.box(self: Canvas, x0: number, y0: number, x1: number, y1: number, color: Color3, alpha: number?): Elem
	return self:rect((x0 + x1) / 2, (y0 + y1) / 2, math.abs(x1 - x0), math.abs(y1 - y0), 0, color, alpha, 0)
end

-- Axis-aligned box with a UIGradient. Base color is white by default so the
-- gradient colors show exactly.
function Canvas.grad(self: Canvas, x0: number, y0: number, x1: number, y1: number, g: GradSpec, color: Color3?, alpha: number?): Elem
	local e = self:box(x0, y0, x1, y1, color or Color3.new(1, 1, 1), alpha)
	e.grad = g
	return e
end

function Canvas.pill(self: Canvas, x: number, y: number, len: number, thick: number, rot: number, color: Color3, alpha: number?): Elem
	return self:rect(x, y, math.max(len, thick), thick, rot, color, alpha, -1)
end

function Canvas.circle(self: Canvas, x: number, y: number, r: number, color: Color3, alpha: number?): Elem
	return self:rect(x, y, r * 2, r * 2, 0, color, alpha, -1)
end

-- Ellipse as a chain of pills along the major axis. The chain ends at the
-- centers of the osculating circles of the tips, so the round caps follow
-- the outline closely.
function Canvas.ellipse(self: Canvas, x: number, y: number, rx: number, ry: number, rot: number, color: Color3)
	local swap = ry > rx
	local a: number = if swap then ry else rx
	local b: number = if swap then rx else ry
	local ang: number = math.rad(if swap then rot + 90 else rot)
	if a - b < 0.5 then
		self:circle(x, y, (a + b) / 2, color)
		return
	end
	local ca, sa = math.cos(ang), math.sin(ang)
	local ue = a - b * b / a -- osculating circle center at the tip
	local n = math.clamp(math.floor(a / b * 5), 4, 16)
	local pts, ws = {}, {}
	for i = 0, n do
		local t = i / n
		local u = -math.cos(t * math.pi) * ue
		local w = 2 * b * math.sqrt(math.max(0, 1 - (u / a) ^ 2))
		if i == 0 or i == n then
			w = 2 * b * b / a
		end
		table.insert(pts, { x + ca * u, y + sa * u })
		table.insert(ws, w)
	end
	self:stroke(pts, ws, color)
end

------------------------------------------------------------------------
-- Brush strokes
------------------------------------------------------------------------

-- Centripetal Catmull-Rom through pts, returns a dense polyline with the
-- interpolated width at every vertex.
local function densify(pts: { { number } }, widths: { number }): ({ number }, { number }, { number })
	local n = #pts
	local xs, ys, ws = {}, {}, {}
	if n == 1 then
		return { pts[1][1] }, { pts[1][2] }, { widths[1] }
	end
	local function P(i: number): (number, number)
		if i < 1 then
			-- reflect the first point
			local x1, y1 = pts[1][1], pts[1][2]
			local x2, y2 = pts[2][1], pts[2][2]
			return 2 * x1 - x2, 2 * y1 - y2
		elseif i > n then
			local x1, y1 = pts[n][1], pts[n][2]
			local x0, y0 = pts[n - 1][1], pts[n - 1][2]
			return 2 * x1 - x0, 2 * y1 - y0
		end
		return pts[i][1], pts[i][2]
	end
	for i = 1, n - 1 do
		local x0, y0 = P(i - 1)
		local x1, y1 = P(i)
		local x2, y2 = P(i + 1)
		local x3, y3 = P(i + 2)
		local function tj(ti: number, ax: number, ay: number, bx: number, by: number): number
			local d = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
			return ti + math.max(math.sqrt(d), 1e-4)
		end
		local t0 = 0
		local t1 = tj(t0, x0, y0, x1, y1)
		local t2 = tj(t1, x1, y1, x2, y2)
		local t3 = tj(t2, x2, y2, x3, y3)
		local segLen = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local k = math.clamp(math.floor(segLen / 2), 4, 200)
		local wa, wb = widths[i], widths[i + 1]
		for j = (if i == 1 then 0 else 1), k do
			local u = j / k
			local t = t1 + (t2 - t1) * u
			local a1x = (t1 - t) / (t1 - t0) * x0 + (t - t0) / (t1 - t0) * x1
			local a1y = (t1 - t) / (t1 - t0) * y0 + (t - t0) / (t1 - t0) * y1
			local a2x = (t2 - t) / (t2 - t1) * x1 + (t - t1) / (t2 - t1) * x2
			local a2y = (t2 - t) / (t2 - t1) * y1 + (t - t1) / (t2 - t1) * y2
			local a3x = (t3 - t) / (t3 - t2) * x2 + (t - t2) / (t3 - t2) * x3
			local a3y = (t3 - t) / (t3 - t2) * y2 + (t - t2) / (t3 - t2) * y3
			local b1x = (t2 - t) / (t2 - t0) * a1x + (t - t0) / (t2 - t0) * a2x
			local b1y = (t2 - t) / (t2 - t0) * a1y + (t - t0) / (t2 - t0) * a2y
			local b2x = (t3 - t) / (t3 - t1) * a2x + (t - t1) / (t3 - t1) * a3x
			local b2y = (t3 - t) / (t3 - t1) * a2y + (t - t1) / (t3 - t1) * a3y
			local cx = (t2 - t) / (t2 - t1) * b1x + (t - t1) / (t2 - t1) * b2x
			local cy = (t2 - t) / (t2 - t1) * b1y + (t - t1) / (t2 - t1) * b2y
			table.insert(xs, cx)
			table.insert(ys, cy)
			-- smooth width blend between control points
			local s = u * u * (3 - 2 * u)
			table.insert(ws, wa + (wb - wa) * s)
		end
	end
	return xs, ys, ws
end

-- Variable-width stroke through control points (design units).
function Canvas.stroke(self: Canvas, pts: { { number } }, widths: { number } | number, color: Color3, opts: StrokeOpts?)
	local o: StrokeOpts = opts or {}
	local ww: { number } = {}
	if type(widths) == "number" then
		for i = 1, #pts do
			ww[i] = widths
		end
	else
		ww = widths :: { number }
		assert(#ww == #pts, "stroke: widths must match points")
	end
	local p2 = pts
	if o.closed then
		p2 = table.clone(pts)
		table.insert(p2, pts[1])
		ww = table.clone(ww)
		table.insert(ww, ww[1])
	end
	local xs, ys, ws = densify(p2, ww)
	local minW = o.minWidth or 0.6
	local maxStep = o.maxStep or 40
	local n = #xs
	if n == 1 then
		self:circle(xs[1], ys[1], math.max(ws[1], minW) / 2, color)
		return
	end
	-- choose nodes
	local nodes = { 1 }
	local lastI = 1
	local acc = 0
	for i = 2, n do
		acc += math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
		local w = math.max(math.min(ws[i], ws[lastI]), minW)
		local step = Util.clamp(0.9 * w, o.minStep or 1.2, maxStep)
		local split = acc >= step
		local minAcc = math.max(0.8, (o.minStep or 0) * 0.5)
		if not split and i - lastI >= 2 then
			-- direction change since the last node
			local dx1, dy1 = xs[lastI + 1] - xs[lastI], ys[lastI + 1] - ys[lastI]
			local dx2, dy2 = xs[i] - xs[i - 1], ys[i] - ys[i - 1]
			local a1, a2 = math.atan2(dy1, dx1), math.atan2(dy2, dx2)
			local d = math.abs((a2 - a1 + math.pi) % (2 * math.pi) - math.pi)
			if d > math.rad(7) and acc > minAcc then
				split = true
			end
			local wr = math.abs(ws[i] - ws[lastI]) / math.max(ws[lastI], minW)
			if wr > 0.18 and acc > minAcc then
				split = true
			end
		end
		if split or i == n then
			table.insert(nodes, i)
			lastI = i
			acc = 0
		end
	end
	for k = 1, #nodes - 1 do
		local a, b = nodes[k], nodes[k + 1]
		local ax, ay, bx, by = xs[a], ys[a], xs[b], ys[b]
		local th = math.max((ws[a] + ws[b]) / 2, minW)
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		self:pill((ax + bx) / 2, (ay + by) / 2, len + th, th, math.deg(math.atan2(dy, dx)), color)
	end
end

------------------------------------------------------------------------
-- Convex polygon: covering rectangle + cuts in the underlying color
------------------------------------------------------------------------

function Canvas.poly(self: Canvas, pts: { { number } }, color: Color3, cutColor: Color3)
	local n = #pts
	assert(n >= 3, "poly needs 3+ points")
	-- orientation (make it counter-clockwise in y-down screen space -> use signed area)
	local area = 0
	for i = 1, n do
		local j = i % n + 1
		area += pts[i][1] * pts[j][2] - pts[j][1] * pts[i][2]
	end
	local sgn = if area > 0 then 1 else -1
	-- pick the edge giving the smallest bounding rectangle
	local best: { ux: number, uy: number, minU: number, maxU: number, minV: number, maxV: number, area: number }? = nil
	for i = 1, n do
		local j = i % n + 1
		local ex, ey = pts[j][1] - pts[i][1], pts[j][2] - pts[i][2]
		local len = math.sqrt(ex * ex + ey * ey)
		if len > 1e-6 then
			local ux, uy = ex / len, ey / len
			local vx, vy = -uy, ux
			local minU: number, maxU: number, minV: number, maxV: number = math.huge, -math.huge, math.huge, -math.huge
			for k = 1, n do
				local u = pts[k][1] * ux + pts[k][2] * uy
				local v = pts[k][1] * vx + pts[k][2] * vy
				minU = math.min(minU, u)
				maxU = math.max(maxU, u)
				minV = math.min(minV, v)
				maxV = math.max(maxV, v)
			end
			local a = (maxU - minU) * (maxV - minV)
			if best == nil or a < best.area then
				best = { ux = ux, uy = uy, minU = minU, maxU = maxU, minV = minV, maxV = maxV, area = a }
			end
		end
	end
	assert(best, "degenerate polygon")
	local b = best :: { ux: number, uy: number, minU: number, maxU: number, minV: number, maxV: number, area: number }
	local ux, uy = b.ux, b.uy
	local vx, vy = -uy, ux
	local cu, cv = (b.minU + b.maxU) / 2, (b.minV + b.maxV) / 2
	local cx, cy = cu * ux + cv * vx, cu * uy + cv * vy
	local rot = math.deg(math.atan2(uy, ux))
	self:rect(cx, cy, b.maxU - b.minU, b.maxV - b.minV, rot, color)
	-- rectangle corners
	local corners = {
		{ b.minU * ux + b.minV * vx, b.minU * uy + b.minV * vy },
		{ b.maxU * ux + b.minV * vx, b.maxU * uy + b.minV * vy },
		{ b.maxU * ux + b.maxV * vx, b.maxU * uy + b.maxV * vy },
		{ b.minU * ux + b.maxV * vx, b.minU * uy + b.maxV * vy },
	}
	for i = 1, n do
		local j = i % n + 1
		local ex, ey = pts[j][1] - pts[i][1], pts[j][2] - pts[i][2]
		local len = math.sqrt(ex * ex + ey * ey)
		if len > 1e-6 then
			local eux, euy = ex / len, ey / len
			-- outward normal (y-down coordinates)
			local nx, ny = euy * sgn, -eux * sgn
			-- region of the covering rectangle outside this edge: corners on the
			-- outer side plus the points where the edge line crosses the rectangle
			local maxD: number, minT: number, maxT: number = 0, math.huge, -math.huge
			local ds: { number }, ts: { number } = {}, {}
			for k, c in corners do
				local dx, dy = c[1] - pts[i][1], c[2] - pts[i][2]
				ds[k] = dx * nx + dy * ny
				ts[k] = dx * eux + dy * euy
			end
			for k = 1, 4 do
				local m = k % 4 + 1
				if ds[k] > 1e-3 then
					maxD = math.max(maxD, ds[k])
					minT = math.min(minT, ts[k])
					maxT = math.max(maxT, ts[k])
				end
				if (ds[k] > 1e-3 and ds[m] < -1e-3) or (ds[k] < -1e-3 and ds[m] > 1e-3) then
					local f = ds[k] / (ds[k] - ds[m])
					local t = ts[k] + (ts[m] - ts[k]) * f
					minT = math.min(minT, t)
					maxT = math.max(maxT, t)
				end
			end
			if maxD > 0.05 then
				local midT = (minT + maxT) / 2
				local depth = maxD + 0.5
				local mx = pts[i][1] + eux * midT + nx * depth / 2
				local my = pts[i][2] + euy * midT + ny * depth / 2
				self:rect(mx, my, (maxT - minT) + 1, depth, math.deg(math.atan2(euy, eux)), cutColor)
			end
		end
	end
end

-- Crisp contour against transparency: for every segment of the polyline a
-- rotated rectangle whose outer edge lies exactly on the segment and which
-- extends "depth" units to one side (side = 1: left of the travel direction
-- in y-down coordinates, -1: right). Nothing is painted beyond the contour.
function Canvas.edge(self: Canvas, pts: { { number } }, depth: number, side: number, color: Color3)
	for i = 1, #pts - 1 do
		local ax, ay = pts[i][1], pts[i][2]
		local bx, by = pts[i + 1][1], pts[i + 1][2]
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 1e-6 then
			local ux, uy = dx / len, dy / len
			local nx, ny = uy * side, -ux * side
			local ext = 1.5
			local cx = (ax + bx) / 2 + nx * depth / 2
			local cy = (ay + by) / 2 + ny * depth / 2
			self:rect(cx, cy, len + ext * 2, depth, math.deg(math.atan2(uy, ux)), color)
		end
	end
end

-- Soft blob (cloud / mist): a few concentric pills, each fading out towards
-- its top and bottom edge with a vertical transparency gradient, so the
-- outline has no hard steps.
local BLOB_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.35),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.7, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})

function Canvas.blob(self: Canvas, x: number, y: number, w: number, h: number, color: Color3, alpha: number, layers: number?)
	local k = layers or 4
	-- per-layer opacity so the center reaches "alpha" opacity
	local per = 1 - (1 - alpha) ^ (1 / k)
	for i = 0, k - 1 do
		local f = 1 - i / k * 0.62
		local e = self:rect(x, y, w * f, h * (0.75 + 0.25 * f), 0, color, 1 - per, -1)
		e.grad = { transparency = BLOB_FADE, rotation = 90 }
	end
end

return Paint
