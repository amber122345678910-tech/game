--!strict
-- Icons: vector icons drawn ONLY with GuiObjects (no images). Lune-safe pure builder.
--
--   Icons.Create(name, color, size?, accent?) -> Frame
--       name   : any name from Icons.Names() (every Kits.IconNames entry + UI icons)
--       color  : primary colour; tones derived from it: dark (shade), light (tint), inverse (for glyphs on fills)
--       size   : number (px, square) | UDim2 | nil (= fill parent, kept square by a UIAspectRatioConstraint)
--       accent : optional secondary colour for two-tone details (default: light tint of `color`)
--   Icons.Names() -> { string }          sorted list of every drawable icon
--   Icons.Has(name) -> boolean
--
-- Technique (all sizes are Scale-based, so icons scale with their parent):
--   * rect / circle      Frame (+UICorner), optional Rotation (rotation never needs clipping)
--   * ring / arc         N short tangential Frames ("segment ring"): crisp at any size, no UIStroke pixel width
--   * polygon            decomposed into horizontal slabs; each slab = centre rect + right-triangle "wedges".
--                        A wedge is an UNROTATED clip Frame (ClipsDescendants) holding one rotated Frame whose
--                        edge is the triangle hypotenuse. Parallel-edged slabs become one clipped rotated strip.
--     NOTE: Roblox ignores ClipsDescendants when the clipping frame or an ancestor is rotated, so do not
--     rotate an icon (or its ancestors) that contains polygons; use the directional variants instead
--     (Arrow/ArrowLeft/ArrowUp/ArrowDown, Chevron*).

local Icons = {}

type Ctx = {
	root: Frame,
	z: number,
	tones: { [string]: Color3 },
}

type Builder = {
	R: (cx: number, cy: number, w: number, h: number, tone: string, rot: number?, corner: number?, alpha: number?) -> (),
	C: (cx: number, cy: number, d: number, tone: string, alpha: number?) -> (),
	O: (cx: number, cy: number, d: number, t: number, tone: string, a0: number?, a1: number?, alpha: number?) -> (),
	Arc: (cx: number, cy: number, radius: number, a0: number, a1: number, tMax: number, tMin: number, tone: string) -> (),
	P: (points: { number }, tone: string, alpha: number?) -> (),
	L: (x1: number, y1: number, x2: number, y2: number, t: number, tone: string, round: boolean?, alpha: number?) -> (),
	T: (cx: number, cy: number, w: number, h: number, dir: string, tone: string) -> (),
	Heart: (cx: number, cy: number, width: number, tone: string, alpha: number?) -> (),
	Bone: (x1: number, y1: number, x2: number, y2: number, t: number, tone: string) -> (),
	Person: (cx: number, cy: number, s: number, tone: string, alpha: number?) -> (),
	Star: (cx: number, cy: number, rOut: number, rIn: number, tone: string, rot: number?) -> (),
	Sparkle: (cx: number, cy: number, s: number, tone: string) -> (),
	Diamond: (cx: number, cy: number, s: number, tone: string, alpha: number?) -> (),
	Arrowhead: (x: number, y: number, angle: number, size: number, tone: string) -> (),
	Sword: (x1: number, y1: number, x2: number, y2: number, t: number, blade: string, guard: string, grip: string) -> (),
}

local EPS = 0.45 -- seam overlap in icon units (icon box = 100 x 100)

-- tones --------------------------------------------------------------------------------------------
local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function makeTones(color: Color3, accent: Color3?): { [string]: Color3 }
	local black = Color3.new(0, 0, 0)
	local white = Color3.new(1, 1, 1)
	local light = color:Lerp(white, 0.5)
	return {
		p = color,
		d = color:Lerp(black, 0.45),
		l = light,
		s = accent or light,
		k = Color3.fromRGB(12, 12, 18),
		w = white,
		x = if luminance(color) > 0.6 then Color3.fromRGB(16, 16, 24) else white,
		r = Color3.fromRGB(255, 40, 60),
		red = Color3.fromRGB(240, 64, 72),
		yellow = Color3.fromRGB(255, 214, 64),
		blue = Color3.fromRGB(72, 144, 255),
		green = Color3.fromRGB(72, 210, 120),
	}
end

-- primitive frames ---------------------------------------------------------------------------------
local function frame(ctx: Ctx, name: string, tone: string, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = ctx.tones[tone] or ctx.tones.p
	f.BackgroundTransparency = alpha or 0
	ctx.z += 1
	f.ZIndex = ctx.z
	return f
end

local function corner(parent: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function rect(ctx: Ctx, cx: number, cy: number, w: number, h: number, tone: string, rot: number?, round: number?, alpha: number?)
	local f = frame(ctx, "R", tone, alpha)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx / 100, cy / 100)
	f.Size = UDim2.fromScale(w / 100, h / 100)
	f.Rotation = rot or 0
	if round and round > 0 then
		corner(f, round)
	end
	f.Parent = ctx.root
end

-- right triangle filling half of the box (x, y, w, h); `k` = corner holding the right angle
local function wedge(ctx: Ctx, x: number, y: number, w: number, h: number, k: string, tone: string, alpha: number?)
	if w < 0.05 or h < 0.05 then
		return
	end
	local clip = frame(ctx, "W", tone, 1)
	clip.Position = UDim2.fromScale(x / 100, y / 100)
	clip.Size = UDim2.fromScale(w / 100, h / 100)
	clip.ClipsDescendants = true
	local len = math.sqrt(w * w + h * h)
	local thick = 2 * w * h / len
	local nx, ny, angle
	if k == "BL" then
		nx, ny, angle = -h / len, w / len, math.deg(math.atan2(h, w))
	elseif k == "TR" then
		nx, ny, angle = h / len, -w / len, math.deg(math.atan2(h, w))
	elseif k == "TL" then
		nx, ny, angle = -h / len, -w / len, math.deg(math.atan2(-h, w))
	else -- "BR"
		nx, ny, angle = h / len, w / len, math.deg(math.atan2(-h, w))
	end
	local cx = w / 2 + nx * thick / 2
	local cy = h / 2 + ny * thick / 2
	local inner = Instance.new("Frame")
	inner.Name = "F"
	inner.BorderSizePixel = 0
	inner.BackgroundColor3 = ctx.tones[tone] or ctx.tones.p
	inner.BackgroundTransparency = alpha or 0
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(cx / w, cy / h)
	inner.Size = UDim2.fromScale(len * 1.6 / w, thick / h)
	inner.Rotation = angle
	inner.Parent = clip
	clip.Parent = ctx.root
end

-- strip between two parallel slanted edges inside a slab
local function strip(ctx: Ctx, ya: number, yb: number, lt: number, lb: number, rt: number, rb: number, tone: string, alpha: number?)
	local x0 = math.min(lt, lb)
	local x1 = math.max(rt, rb)
	local cw, ch = x1 - x0, yb - ya
	if cw < 0.05 or ch < 0.05 then
		return
	end
	local clip = frame(ctx, "S", tone, 1)
	clip.Position = UDim2.fromScale(x0 / 100, ya / 100)
	clip.Size = UDim2.fromScale(cw / 100, ch / 100)
	clip.ClipsDescendants = true
	local dx, dy = lb - lt, yb - ya
	local edgeLen = math.sqrt(dx * dx + dy * dy)
	local cosT = dy / edgeLen
	local width = ((rt - lt) + (rb - lb)) / 2 * cosT + EPS
	local cx = (lt + lb + rt + rb) / 4 - x0
	local cy = ch / 2
	local inner = Instance.new("Frame")
	inner.Name = "F"
	inner.BorderSizePixel = 0
	inner.BackgroundColor3 = ctx.tones[tone] or ctx.tones.p
	inner.BackgroundTransparency = alpha or 0
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(cx / cw, cy / ch)
	inner.Size = UDim2.fromScale(width / cw, (ch / cosT) * 1.5 / ch)
	inner.Rotation = -math.deg(math.atan2(dx, dy))
	inner.Parent = clip
	clip.Parent = ctx.root
end

local function plainRect(ctx: Ctx, x: number, y: number, w: number, h: number, tone: string, alpha: number?)
	if w < 0.05 or h < 0.05 then
		return
	end
	local f = frame(ctx, "B", tone, alpha)
	f.Position = UDim2.fromScale(x / 100, y / 100)
	f.Size = UDim2.fromScale(w / 100, h / 100)
	f.Parent = ctx.root
end

-- emit a trapezoid slab whose left edge runs lt->lb and right edge rt->rb (x at ya / yb).
-- Seams between stacked slabs are covered afterwards by interior patches (see polygon()).
local function emitTrap(ctx: Ctx, ya: number, yb: number, lt: number, lb: number, rt: number, rb: number, tone: string, alpha: number?)
	local h = yb - ya
	local innerL = math.max(lt, lb)
	local innerR = math.min(rt, rb)
	if innerR - innerL > 0.05 then
		-- widen into the wedges (their adjacent columns are fully filled) to hide vertical seams
		local growL = if math.abs(lb - lt) > 0.05 then EPS else 0
		local growR = if math.abs(rb - rt) > 0.05 then EPS else 0
		plainRect(ctx, innerL - growL, ya, (innerR - innerL) + growL + growR, h, tone, alpha)
	end
	if math.abs(lb - lt) > 0.05 then
		wedge(ctx, math.min(lt, lb), ya, math.abs(lb - lt), h, if lt < lb then "TR" else "BR", tone, alpha)
	end
	if math.abs(rb - rt) > 0.05 then
		wedge(ctx, math.min(rt, rb), ya, math.abs(rb - rt), h, if rt > rb then "TL" else "BL", tone, alpha)
	end
end

local function trapValid(lt: number, lb: number, rt: number, rb: number): boolean
	return math.max(lt, lb) <= math.min(rt, rb) + 0.05
end

local function trapezoid(ctx: Ctx, ya: number, yb: number, lt: number, lb: number, rt: number, rb: number, tone: string, alpha: number?, depth: number)
	local h = yb - ya
	if h < 0.05 then
		return
	end
	if trapValid(lt, lb, rt, rb) then
		emitTrap(ctx, ya, yb, lt, lb, rt, rb, tone, alpha)
		return
	end
	local sl, sr = (lb - lt) / h, (rb - rt) / h
	if math.abs(sl - sr) < 0.02 then
		strip(ctx, ya, yb, lt, lb, rt, rb, tone, alpha)
		return
	end
	if depth >= 4 then
		emitTrap(ctx, ya, yb, lt, lb, rt, rb, tone, alpha)
		return
	end
	-- largest valid piece from the top
	local lo, hi = 0, 1
	for _ = 1, 18 do
		local mid = (lo + hi) / 2
		if trapValid(lt, lt + sl * h * mid, rt, rt + sr * h * mid) then
			lo = mid
		else
			hi = mid
		end
	end
	if lo > 0.04 then
		local ym = ya + h * lo
		emitTrap(ctx, ya, ym, lt, lt + sl * (ym - ya), rt, rt + sr * (ym - ya), tone, alpha)
		trapezoid(ctx, ym, yb, lt + sl * (ym - ya), lb, rt + sr * (ym - ya), rb, tone, alpha, depth + 1)
		return
	end
	-- largest valid piece from the bottom
	lo, hi = 0, 1
	for _ = 1, 18 do
		local mid = (lo + hi) / 2
		if trapValid(lb - sl * h * mid, lb, rb - sr * h * mid, rb) then
			lo = mid
		else
			hi = mid
		end
	end
	if lo > 0.04 then
		local ym = yb - h * lo
		emitTrap(ctx, ym, yb, lt + sl * (ym - ya), lb, rt + sr * (ym - ya), rb, tone, alpha)
		trapezoid(ctx, ya, ym, lt, lt + sl * (ym - ya), rt, rt + sr * (ym - ya), tone, alpha, depth + 1)
		return
	end
	-- both ends are needle tips: split in the middle
	local ym = ya + h / 2
	trapezoid(ctx, ya, ym, lt, lt + sl * h / 2, rt, rt + sr * h / 2, tone, alpha, depth + 1)
	trapezoid(ctx, ym, yb, lt + sl * h / 2, lb, rt + sr * h / 2, rb, tone, alpha, depth + 1)
end

-- filled spans of the polygon at height y (even-odd), sorted
local function spansAt(pts: { number }, n: number, y: number): { { number } }
	local xs: { number } = {}
	for i = 1, n do
		local j = i % n + 1
		local x1, y1, x2, y2 = pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j]
		if (y1 <= y and y2 > y) or (y2 <= y and y1 > y) then
			table.insert(xs, x1 + (y - y1) * (x2 - x1) / (y2 - y1))
		end
	end
	table.sort(xs)
	local out: { { number } } = {}
	for k = 1, #xs - 1, 2 do
		table.insert(out, { xs[k], xs[k + 1] })
	end
	return out
end

local function intersectSpans(a: { { number } }, b: { { number } }): { { number } }
	local out: { { number } } = {}
	for _, s1 in a do
		for _, s2 in b do
			local lo, hi = math.max(s1[1], s2[1]), math.min(s1[2], s2[2])
			if hi > lo then
				table.insert(out, { lo, hi })
			end
		end
	end
	return out
end

local PATCH = 0.7 -- half-height of the seam patches (icon units)

local function polygon(ctx: Ctx, pts: { number }, tone: string, alpha: number?)
	local n = #pts // 2
	if n < 3 then
		return
	end
	local ys: { number } = {}
	for i = 1, n do
		table.insert(ys, pts[2 * i])
	end
	table.sort(ys)
	local levels: { number } = {}
	for _, y in ys do
		if #levels == 0 or y - levels[#levels] > 0.05 then
			table.insert(levels, y)
		end
	end
	for li = 1, #levels - 1 do
		local ya, yb = levels[li], levels[li + 1]
		local ym = (ya + yb) / 2
		local hits: { { number } } = {}
		for i = 1, n do
			local j = i % n + 1
			local x1, y1, x2, y2 = pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j]
			if (y1 <= ym and y2 > ym) or (y2 <= ym and y1 > ym) then
				local slope = (x2 - x1) / (y2 - y1)
				table.insert(hits, { x1 + (ym - y1) * slope, x1 + (ya - y1) * slope, x1 + (yb - y1) * slope })
			end
		end
		table.sort(hits, function(a, b)
			return a[1] < b[1]
		end)
		for k = 1, #hits - 1, 2 do
			local left, right = hits[k], hits[k + 1]
			trapezoid(ctx, ya, yb, left[2], left[3], right[2], right[3], tone, alpha, 0)
		end
	end
	-- seam patches: thin bands across every internal slab boundary, clipped to the region that is
	-- inside the polygon for the whole band (so they never change the silhouette)
	if alpha == nil or alpha == 0 then
		for li = 2, #levels - 1 do
			local y = levels[li]
			local d = math.min(PATCH, (y - levels[li - 1]) * 0.5, (levels[li + 1] - y) * 0.5)
			if d > 0.05 then
				local safe = intersectSpans(spansAt(pts, n, y - d), spansAt(pts, n, y + d))
				safe = intersectSpans(safe, spansAt(pts, n, y - 0.001))
				safe = intersectSpans(safe, spansAt(pts, n, y + 0.001))
				for _, span in safe do
					if span[2] - span[1] > 0.3 then
						plainRect(ctx, span[1] + 0.05, y - d, span[2] - span[1] - 0.1, d * 2, tone, alpha)
					end
				end
			end
		end
	end
end

local function rotatePoints(pts: { number }, cx: number, cy: number, deg: number): { number }
	local a = math.rad(deg)
	local ca, sa = math.cos(a), math.sin(a)
	local out = table.create(#pts)
	for i = 1, #pts, 2 do
		local dx, dy = pts[i] - cx, pts[i + 1] - cy
		out[i] = cx + dx * ca - dy * sa
		out[i + 1] = cy + dx * sa + dy * ca
	end
	return out
end

-- builder ------------------------------------------------------------------------------------------
local function builder(ctx: Ctx): Builder
	local b = {} :: Builder

	b.R = function(cx, cy, w, h, tone, rot, round, alpha)
		rect(ctx, cx, cy, w, h, tone, rot, round, alpha)
	end

	b.C = function(cx, cy, d, tone, alpha)
		rect(ctx, cx, cy, d, d, tone, 0, 0.5, alpha)
	end

	-- ring / arc of outer diameter d and thickness t, angles in degrees (0 = right, 90 = down)
	b.O = function(cx, cy, d, t, tone, a0, a1, alpha)
		local from = a0 or 0
		local to = a1 or 360
		local span = to - from
		local radius = d / 2
		local mid = radius - t / 2
		local segments = math.max(6, math.ceil(math.abs(span) / 360 * math.clamp(d * 0.5, 16, 40)))
		local step = span / segments
		local half = math.rad(math.abs(step) / 2)
		local length = 2 * radius * math.tan(half) + 1.4
		for i = 0, segments - 1 do
			local a = math.rad(from + (i + 0.5) * step)
			rect(ctx, cx + mid * math.cos(a), cy + mid * math.sin(a), length, t, tone, math.deg(a) + 90, nil, alpha)
		end
	end

	-- tapered arc (crescents): thickness tMin at the ends -> tMax in the middle, outer radius fixed
	b.Arc = function(cx, cy, radius, a0, a1, tMax, tMin, tone)
		local span = a1 - a0
		local segments = math.max(10, math.ceil(math.abs(span) / 360 * 48))
		local step = span / segments
		local half = math.rad(math.abs(step) / 2)
		for i = 0, segments - 1 do
			local s = (i + 0.5) / segments
			local t = tMin + (tMax - tMin) * math.sin(math.pi * s)
			local a = math.rad(a0 + (i + 0.5) * step)
			local mid = radius - t / 2
			local length = 2 * radius * math.tan(half) + 1.4
			rect(ctx, cx + mid * math.cos(a), cy + mid * math.sin(a), length, t, tone, math.deg(a) + 90)
		end
	end

	b.P = function(points, tone, alpha)
		polygon(ctx, points, tone, alpha)
	end

	-- straight bar between two points (round = pill caps centred on the end points)
	b.L = function(x1, y1, x2, y2, t, tone, round, alpha)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		rect(ctx, (x1 + x2) / 2, (y1 + y2) / 2, len + (if round then t else 0), t, tone, math.deg(math.atan2(dy, dx)), if round then 0.5 else nil, alpha)
	end

	-- isoceles triangle in the box centred at (cx, cy) pointing `dir`
	b.T = function(cx, cy, w, h, dir, tone)
		local x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
		if dir == "Up" then
			polygon(ctx, { cx, y0, x1, y1, x0, y1 }, tone)
		elseif dir == "Down" then
			polygon(ctx, { x0, y0, x1, y0, cx, y1 }, tone)
		elseif dir == "Left" then
			polygon(ctx, { x0, cy, x1, y0, x1, y1 }, tone)
		else
			polygon(ctx, { x1, cy, x0, y1, x0, y0 }, tone)
		end
	end

	b.Heart = function(cx, cy, width, tone, alpha)
		local k = width / 71.7
		local side = 42 * k
		rect(ctx, cx, cy + 3.1 * k, side, side, tone, 45, nil, alpha)
		rect(ctx, cx - 14.85 * k, cy - 11.75 * k, side, side, tone, 0, 0.5, alpha)
		rect(ctx, cx + 14.85 * k, cy - 11.75 * k, side, side, tone, 0, 0.5, alpha)
	end

	b.Bone = function(x1, y1, x2, y2, t, tone)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local ux, uy = dx / len, dy / len
		local nx, ny = -uy, ux
		b.L(x1, y1, x2, y2, t, tone)
		local knob = t * 1.32
		local off = t * 0.5
		local back = t * 0.15
		for _, e in { { x1 - ux * back, y1 - uy * back }, { x2 + ux * back, y2 + uy * back } } do
			b.C(e[1] + nx * off, e[2] + ny * off, knob, tone)
			b.C(e[1] - nx * off, e[2] - ny * off, knob, tone)
		end
	end

	b.Person = function(cx, cy, s, tone, alpha)
		rect(ctx, cx, cy - 15 * s, 24 * s, 24 * s, tone, 0, 0.5, alpha)
		rect(ctx, cx, cy + 17 * s, 44 * s, 30 * s, tone, 0, 0.46, alpha)
	end

	b.Star = function(cx, cy, rOut, rIn, tone, rot)
		local pts = {}
		for i = 0, 9 do
			local a = math.rad(-90 + i * 36 + (rot or 0))
			local r = if i % 2 == 0 then rOut else rIn
			table.insert(pts, cx + r * math.cos(a))
			table.insert(pts, cy + r * math.sin(a))
		end
		polygon(ctx, pts, tone)
	end

	b.Sparkle = function(cx, cy, s, tone)
		local q = s * 0.2
		polygon(ctx, { cx, cy - s, cx + q, cy - q, cx + s, cy, cx + q, cy + q, cx, cy + s, cx - q, cy + q, cx - s, cy, cx - q, cy - q }, tone)
	end

	b.Diamond = function(cx, cy, s, tone, alpha)
		rect(ctx, cx, cy, s, s, tone, 45, nil, alpha)
	end

	-- small triangle with its tip at (x, y) pointing along `angle` (degrees)
	b.Arrowhead = function(x, y, angle, size, tone)
		local pts = { x, y, x - size, y - size * 0.62, x - size, y + size * 0.62 }
		polygon(ctx, rotatePoints(pts, x, y, angle), tone)
	end

	-- sword from hilt (x1, y1) to tip (x2, y2)
	b.Sword = function(x1, y1, x2, y2, t, blade, guard, grip)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local ux, uy = dx / len, dy / len
		local nx, ny = -uy, ux
		local gx, gy = x1 + ux * len * 0.24, y1 + uy * len * 0.24 -- guard position
		local tipBase = 0.86
		b.L(x1 - ux * 2, y1 - uy * 2, gx, gy, t * 0.72, grip)
		b.L(gx, gy, x1 + dx * tipBase, y1 + dy * tipBase, t, blade)
		-- tip: diamond whose corner points along the blade
		local s = t / math.sqrt(2)
		local tipx, tipy = x1 + dx * tipBase, y1 + dy * tipBase
		rect(ctx, tipx, tipy, s, s, blade, math.deg(math.atan2(dy, dx)) - 45, nil)
		b.L(gx + ux * 2, gy + uy * 2, x1 + dx * tipBase, y1 + dy * tipBase, t * 0.28, "l", false, 0.25)
		b.L(gx - nx * t * 1.25, gy - ny * t * 1.25, gx + nx * t * 1.25, gy + ny * t * 1.25, t * 0.62, guard, true)
		b.C(x1 - ux * 4, y1 - uy * 4, t * 0.95, guard)
	end

	return b
end

-- icon definitions (100 x 100 box) -----------------------------------------------------------------
local DEFS: { [string]: (b: Builder) -> () } = {}

-- kit icons ---------------------------------------------------------------------------------------
DEFS.Bone = function(b)
	b.Bone(29, 75, 75, 29, 12, "d")
	b.Bone(26, 72, 72, 26, 12, "p")
	b.L(33, 61, 61, 33, 2.6, "l", true, 0.3)
end

DEFS.Blaster = function(b)
	-- horns
	b.P({ 30, 34, 10, 10, 20, 8, 40, 26 }, "p")
	b.P({ 70, 34, 90, 10, 80, 8, 60, 26 }, "p")
	-- skull + muzzle
	b.R(50, 40, 60, 42, "p", 0, 0.42)
	b.P({ 28, 50, 72, 50, 64, 82, 36, 82 }, "p")
	-- eye sockets with angry brows
	b.C(37, 46, 16, "k")
	b.C(63, 46, 16, "k")
	b.R(37, 38.5, 22, 7, "p", 16)
	b.R(63, 38.5, 22, 7, "p", -16)
	b.C(63, 47, 6, "s")
	-- snout + jaws
	b.C(45, 61, 4, "k")
	b.C(55, 61, 4, "k")
	b.R(50, 74, 24, 10, "k", 0, 0.3)
	b.R(43.5, 70.5, 4, 4, "p")
	b.R(50, 70.5, 4, 4, "p")
	b.R(56.5, 70.5, 4, 4, "p")
	-- charging beam
	b.R(50, 91, 16, 14, "s", 0, 0.3, 0.55)
	b.R(50, 90, 8, 16, "s", 0, 0.5)
end

DEFS.BlueSoul = function(b)
	b.Heart(50, 41, 68, "p")
	b.C(33, 31, 9, "l", 0.25)
	b.P({ 34, 76, 50, 86, 66, 76, 66, 84, 50, 94, 34, 84 }, "s")
end

DEFS.BoneZone = function(b)
	local t, a = 6, 18
	for _, c in { { 12, 12, 1, 1 }, { 88, 12, -1, 1 }, { 12, 88, 1, -1 }, { 88, 88, -1, -1 } } do
		local x, y, sx, sy = c[1], c[2], c[3], c[4]
		b.R(x + sx * a / 2 - sx * t / 2, y, a, t, "s")
		b.R(x, y + sy * a / 2 - sy * t / 2, t, a, "s")
	end
	b.Bone(32, 78, 32, 44, 8, "p")
	b.Bone(50, 80, 50, 28, 8, "p")
	b.Bone(68, 78, 68, 44, 8, "p")
end

DEFS.BoneWall = function(b)
	for i, x in { 18, 34, 50, 66, 82 } do
		local top = if i % 2 == 0 then 24 else 30
		b.Bone(x, 80, x, top, 7.5, "p")
	end
	b.R(50, 89, 88, 6, "s", 0, 0.5)
end

DEFS.Teleport = function(b)
	b.C(50, 24, 22, "p")
	b.R(50, 45, 34, 8, "p", 0, 0.3)
	b.R(50, 55, 38, 6, "p", 0, 0.3, 0.2)
	b.R(50, 64, 40, 5, "p", 0, 0.3, 0.45)
	b.R(50, 72, 40, 4, "p", 0, 0.3, 0.62)
	b.R(50, 79, 36, 3, "p", 0, 0.3, 0.78)
	b.R(50, 90, 56, 8, "s", 0, 0.5, 0.35)
	b.Sparkle(20, 36, 9, "s")
	b.Sparkle(80, 58, 7, "s")
	b.Sparkle(77, 22, 5, "s")
end

DEFS.Eye = function(b)
	b.P({ 6, 50, 24, 32, 50, 24, 76, 32, 94, 50, 76, 68, 50, 76, 24, 68 }, "p")
	b.C(50, 50, 36, "s")
	b.C(50, 50, 16, "k")
	b.C(44, 44, 8, "w")
end

DEFS.Skull = function(b)
	b.C(50, 42, 68, "p")
	b.R(50, 66, 52, 26, "p", 0, 0.35)
	b.C(36, 45, 17, "k")
	b.C(64, 45, 17, "k")
	b.C(64, 45, 6, "s")
	b.P({ 50, 55, 54.5, 62, 45.5, 62 }, "k")
	b.R(50, 71, 38, 4, "k")
	b.R(29.5, 68.2, 8, 4, "k", -32)
	b.R(70.5, 68.2, 8, 4, "k", 32)
	for _, x in { 38, 46, 54, 62 } do
		b.R(x, 71, 2.6, 9, "k")
	end
end

DEFS.Dash = function(b)
	b.P({ 26, 24, 38, 24, 62, 50, 38, 76, 26, 76, 50, 50 }, "s")
	b.P({ 46, 20, 60, 20, 88, 50, 60, 80, 46, 80, 74, 50 }, "p")
	b.R(14, 38, 16, 5, "s", 0, 0.5, 0.3)
	b.R(10, 62, 12, 5, "s", 0, 0.5, 0.5)
end

DEFS.Sword = function(b)
	b.Sword(24, 76, 82, 18, 11, "p", "s", "d")
end

DEFS.Chain = function(b)
	-- two stadium links (diagonal) joined by an edge-on link
	local function link(cx: number, cy: number, tone: string)
		local ux, uy = 0.7071, -0.7071
		local nx, ny = 0.7071, 0.7071
		local half, r, t = 9, 10, 6
		local e1x, e1y = cx + ux * half, cy + uy * half
		local e2x, e2y = cx - ux * half, cy - uy * half
		b.O(e1x, e1y, r * 2, t, tone, -135, 45)
		b.O(e2x, e2y, r * 2, t, tone, 45, 225)
		local o = r - t / 2
		b.L(e1x + nx * o, e1y + ny * o, e2x + nx * o, e2y + ny * o, t, tone)
		b.L(e1x - nx * o, e1y - ny * o, e2x - nx * o, e2y - ny * o, t, tone)
	end
	link(28, 72, "p")
	link(72, 28, "p")
	b.L(38, 62, 62, 38, 9, "l", true)
end

DEFS.Rage = function(b)
	-- anger mark: four thick arcs whose bellies face the centre
	for _, q in { { 14, 14, 0 }, { 86, 14, 90 }, { 86, 86, 180 }, { 14, 86, 270 } } do
		b.O(q[1], q[2], 64, 12, "p", q[3] + 8, q[3] + 82)
	end
	b.C(50, 50, 8, "s")
end

DEFS.Crown = function(b)
	b.P({ 14, 80, 14, 36, 32, 56, 50, 24, 68, 56, 86, 36, 86, 80 }, "p")
	b.R(50, 74, 72, 5, "l", 0, nil, 0.35)
	b.C(14, 33, 10, "p")
	b.C(50, 21, 10, "p")
	b.C(86, 33, 10, "p")
	b.C(50, 62, 11, "s")
	b.C(29, 65, 7, "s")
	b.C(71, 65, 7, "s")
end

DEFS.Wave = function(b)
	b.R(50, 76, 88, 5, "s", 0, 0.5)
	b.C(50, 66, 13, "p")
	b.O(50, 72, 34, 6, "p", 180, 360)
	b.O(50, 72, 58, 6, "p", 185, 355, 0.25)
	b.O(50, 72, 84, 5, "p", 192, 348, 0.5)
end

DEFS.Portal = function(b)
	b.O(50, 50, 86, 9, "p", 0, 300)
	b.O(50, 50, 62, 7, "s", 120, 420)
	b.O(50, 50, 40, 6, "p", 240, 540)
	b.C(50, 50, 16, "l")
end

DEFS.Orb = function(b)
	b.C(50, 50, 86, "p", 0.82)
	b.C(50, 50, 58, "p")
	b.C(42, 42, 22, "l", 0.25)
	b.C(39, 39, 9, "w")
	b.O(50, 50, 78, 4, "s", 200, 340)
	b.Sparkle(84, 20, 7, "s")
end

DEFS.Star = function(b)
	b.Star(50, 53, 45, 19, "p")
	b.Star(50, 53, 22, 9, "l")
end

DEFS.Trap = function(b)
	for _, x in { 23, 41, 59, 77 } do
		b.T(x, 54, 15, 42, "Up", "p")
	end
	b.R(50, 80, 84, 12, "d", 0, 0.3)
	for _, x in { 20, 38, 56, 74 } do
		b.R(x, 80, 6, 12, "s", 30, nil, 0.3)
	end
end

DEFS.Moon = function(b)
	b.Arc(50, 50, 40, 100, 260, 26, 2, "p")
	b.C(40, 33, 6, "d", 0.4)
	b.C(34, 58, 8, "d", 0.4)
	b.Sparkle(72, 30, 9, "s")
	b.Sparkle(80, 64, 6, "s")
end

DEFS.Eclipse = function(b)
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		b.L(50 + 38 * math.cos(a), 50 + 38 * math.sin(a), 50 + 47 * math.cos(a), 50 + 47 * math.sin(a), 4, "s", true, 0.35)
	end
	b.C(50, 50, 72, "p")
	b.C(52, 50, 60, "k")
	b.Arc(52, 50, 30, 120, 240, 5, 1, "l")
end

DEFS.Knife = function(b)
	b.L(38, 62, 74, 26, 13, "p")
	b.R(74, 26, 9.2, 9.2, "p", 0)
	b.L(42, 63, 77, 28, 3, "l", false, 0.2)
	b.L(32, 56, 44, 68, 6, "s", true)
	b.L(36, 64, 20, 80, 10, "d", true)
end

DEFS.Afterimage = function(b)
	b.Person(28, 52, 1.05, "p", 0.75)
	b.Person(46, 52, 1.05, "p", 0.45)
	b.Person(66, 52, 1.05, "p")
	b.R(14, 30, 12, 4, "s", 0, 0.5, 0.4)
	b.R(10, 78, 12, 4, "s", 0, 0.5, 0.4)
end

DEFS.Heart = function(b)
	b.Heart(50, 50, 80, "p")
	b.C(32, 37, 11, "l", 0.25)
end

DEFS.Clock = function(b)
	b.O(50, 50, 86, 8, "p")
	for i = 0, 3 do
		local a = math.rad(i * 90)
		b.R(50 + 30 * math.cos(a), 50 + 30 * math.sin(a), 7, 4, "p", i * 90)
	end
	b.L(50, 50, 50, 29, 7, "p", true)
	b.L(50, 50, 66, 59, 5, "s", true)
	b.C(50, 50, 10, "s")
end

DEFS.Ribbon = function(b)
	b.L(46, 56, 34, 86, 9, "d", true)
	b.L(54, 56, 66, 86, 9, "d", true)
	b.P({ 50, 45, 18, 24, 11, 48, 17, 72, 50, 55 }, "p")
	b.P({ 50, 45, 82, 24, 89, 48, 83, 72, 50, 55 }, "p")
	b.R(50, 50, 15, 18, "s", 0, 0.3)
end

DEFS.Stealth = function(b)
	b.P({ 6, 50, 24, 32, 50, 24, 76, 32, 94, 50, 76, 68, 50, 76, 24, 68 }, "d")
	b.C(50, 50, 30, "p", 0.5)
	b.C(50, 50, 12, "k")
	b.L(18, 84, 84, 16, 9, "p", true)
end

DEFS.Fist = function(b)
	b.L(50, 6, 50, 14, 4, "s", true)
	b.L(25, 12, 30, 19, 4, "s", true)
	b.L(75, 12, 70, 19, 4, "s", true)
	b.R(50, 56, 58, 42, "p", 0, 0.24)
	for i, x in { 30, 44, 58, 72 } do
		b.C(x, if i == 1 or i == 4 then 39 else 37, 17, "p")
	end
	for _, x in { 37, 51, 65 } do
		b.R(x, 44, 2.6, 13, "d")
	end
	b.R(40, 62, 32, 11, "d", -8, 0.5)
	b.R(50, 85, 34, 14, "d", 0, 0.2)
end

DEFS.Shield = function(b)
	b.P({ 50, 8, 85, 20, 83, 52, 72, 72, 50, 92, 28, 72, 17, 52, 15, 20 }, "p")
	b.P({ 50, 19, 75, 28, 73, 52, 65, 66, 50, 80, 35, 66, 27, 52, 25, 28 }, "d")
	b.R(50, 48, 8, 34, "s", 0, 0.3)
	b.R(50, 42, 26, 8, "s", 0, 0.3)
end

DEFS.Flame = function(b)
	b.P({ 50, 4, 70, 30, 81, 54, 77, 76, 63, 91, 37, 91, 23, 76, 19, 54, 30, 30 }, "p")
	b.P({ 50, 36, 61, 54, 64, 71, 56, 84, 44, 84, 36, 71, 39, 54 }, "s")
end

DEFS.Shoe = function(b)
	-- ballet slipper (side view) with crossed ribbons
	b.L(36, 52, 22, 14, 4, "s", true)
	b.L(50, 50, 66, 12, 4, "s", true)
	b.P({ 10, 70, 12, 60, 22, 54, 40, 56, 58, 52, 76, 54, 88, 62, 92, 70, 86, 78, 16, 78 }, "p")
	b.R(42, 56, 30, 7, "d", -4, 0.5)
	b.R(52, 80, 80, 5, "d", 0, 0.5)
	b.C(44, 58, 6, "s")
end

DEFS.Spin = function(b)
	b.O(50, 50, 74, 9, "p", 200, 330)
	b.O(50, 50, 74, 9, "p", 20, 150)
	local r = 32.5
	b.Arrowhead(50 + r * math.cos(math.rad(340)), 50 + r * math.sin(math.rad(340)), 340 + 90, 13, "p")
	b.Arrowhead(50 + r * math.cos(math.rad(160)), 50 + r * math.sin(math.rad(160)), 160 + 90, 13, "p")
	b.C(50, 50, 12, "s")
end

DEFS.Book = function(b)
	b.R(77, 52, 9, 70, "l")
	b.R(46, 50, 60, 78, "p", 0, 0.08)
	b.R(20, 50, 8, 78, "d")
	b.R(49, 34, 32, 9, "s", 0, 0.2)
	b.R(49, 46, 22, 4, "s", 0, 0.5, 0.45)
	b.P({ 62, 86, 70, 86, 70, 98, 66, 94, 62, 98 }, "r")
end

DEFS.Rewind = function(b)
	b.T(33, 50, 34, 50, "Left", "p")
	b.T(65, 50, 34, 50, "Left", "p")
	b.R(12, 50, 6, 50, "s", 0, 0.3)
end

DEFS.Pan = function(b)
	b.L(62, 40, 88, 14, 10, "d", true)
	b.C(40, 60, 62, "p")
	b.C(40, 60, 48, "d")
	b.C(34, 54, 12, "s", 0.4)
	b.C(85, 17, 4, "k")
end

DEFS.Food = function(b)
	b.P({ 32, 50, 8, 32, 12, 50, 8, 68 }, "s")
	b.P({ 68, 50, 92, 32, 88, 50, 92, 68 }, "s")
	b.C(50, 50, 44, "p")
	b.L(37, 63, 63, 37, 6, "l", true, 0.2)
	b.C(42, 42, 8, "w", 0.3)
end

DEFS.Gun = function(b)
	b.R(60, 36, 52, 10, "p", 0, 0.15)
	b.R(87, 33, 3, 6, "p")
	b.R(40, 44, 28, 18, "p", 0, 0.15)
	b.C(44, 44, 16, "d")
	b.C(44, 44, 6, "p")
	b.P({ 26, 50, 42, 50, 36, 84, 18, 80 }, "d")
	b.O(46, 58, 18, 4, "p", 0, 180)
	b.R(28, 33, 7, 8, "p", -20)
end

DEFS.Bullet = function(b)
	b.C(50, 31, 26, "p")
	b.R(50, 40, 26, 18, "p")
	b.R(50, 64, 28, 30, "s", 0, 0.12)
	b.R(50, 82, 32, 6, "d", 0, 0.3)
	b.R(43, 60, 4, 22, "w", 0, 0.5, 0.7)
	b.L(18, 26, 18, 52, 4, "s", true, 0.4)
	b.L(82, 34, 82, 60, 4, "s", true, 0.4)
end

DEFS.Target = function(b)
	b.O(50, 50, 82, 7, "p")
	b.O(50, 50, 52, 7, "p")
	b.C(50, 50, 18, "s")
	b.R(50, 7, 5, 14, "p")
	b.R(50, 93, 5, 14, "p")
	b.R(7, 50, 14, 5, "p")
	b.R(93, 50, 14, 5, "p")
end

DEFS.Box = function(b)
	b.R(50, 13, 80, 7, "p")
	b.R(50, 87, 80, 7, "p")
	b.R(13, 50, 7, 80, "p")
	b.R(87, 50, 7, 80, "p")
	b.Heart(50, 52, 30, "r")
end

-- UI icons ----------------------------------------------------------------------------------------
DEFS.Play = function(b)
	b.T(56, 50, 52, 60, "Right", "p")
end

DEFS.Settings = function(b)
	for i = 0, 7 do
		local a = i * 45
		local r = math.rad(a)
		b.R(50 + 36 * math.cos(r), 50 + 36 * math.sin(r), 16, 15, "p", a + 90, 0.15)
	end
	b.O(50, 50, 70, 17, "p")
	b.C(50, 50, 12, "s")
end

DEFS.Shop = function(b)
	b.O(50, 36, 38, 7, "d", 180, 360)
	b.P({ 16, 36, 84, 36, 88, 90, 12, 90 }, "p")
	b.C(50, 64, 22, "s")
	b.C(50, 64, 11, "d")
end

DEFS.Quests = function(b)
	b.R(50, 50, 58, 66, "l")
	b.R(50, 17, 70, 12, "p", 0, 0.5)
	b.R(50, 83, 70, 12, "p", 0, 0.5)
	b.R(46, 36, 34, 4, "d", 0, 0.5)
	b.R(46, 48, 34, 4, "d", 0, 0.5)
	b.R(40, 60, 22, 4, "d", 0, 0.5)
	b.C(66, 66, 14, "s")
end

DEFS.Trophy = function(b)
	b.O(26, 30, 24, 5, "p", 90, 270)
	b.O(74, 30, 24, 5, "p", -90, 90)
	b.P({ 26, 14, 74, 14, 72, 40, 62, 56, 38, 56, 28, 40 }, "p")
	b.R(50, 64, 10, 14, "d")
	b.R(50, 78, 40, 8, "p", 0, 0.2)
	b.R(50, 87, 52, 7, "d", 0, 0.3)
	b.Star(50, 33, 11, 4.6, "s")
end

DEFS.Profile = function(b)
	b.C(50, 34, 32, "p")
	b.R(50, 76, 60, 36, "p", 0, 0.5)
end

DEFS.Close = function(b)
	b.L(24, 24, 76, 76, 13, "p", true)
	b.L(76, 24, 24, 76, 13, "p", true)
end

local function arrowLeft(): { number }
	return { 8, 50, 42, 18, 42, 37, 90, 37, 90, 63, 42, 63, 42, 82 }
end

DEFS.Back = function(b)
	b.P(arrowLeft(), "p")
end

DEFS.ArrowLeft = DEFS.Back

DEFS.Arrow = function(b)
	b.P(rotatePoints(arrowLeft(), 50, 50, 180), "p")
end

DEFS.ArrowUp = function(b)
	b.P(rotatePoints(arrowLeft(), 50, 50, 90), "p")
end

DEFS.ArrowDown = function(b)
	b.P(rotatePoints(arrowLeft(), 50, 50, -90), "p")
end

local function chevronRight(): { number }
	return { 30, 14, 48, 14, 84, 50, 48, 86, 30, 86, 66, 50 }
end

DEFS.ChevronRight = function(b)
	b.P(chevronRight(), "p")
end

DEFS.ChevronLeft = function(b)
	b.P(rotatePoints(chevronRight(), 50, 50, 180), "p")
end

DEFS.ChevronDown = function(b)
	b.P(rotatePoints(chevronRight(), 50, 50, 90), "p")
end

DEFS.ChevronUp = function(b)
	b.P(rotatePoints(chevronRight(), 50, 50, -90), "p")
end

DEFS.Lock = function(b)
	b.O(50, 40, 48, 9, "p", 180, 360)
	b.R(30.5, 48, 9, 18, "p")
	b.R(69.5, 48, 9, 18, "p")
	b.R(50, 68, 66, 46, "p", 0, 0.14)
	b.C(50, 63, 13, "d")
	b.R(50, 73, 6, 14, "d", 0, 0.3)
end

DEFS.Check = function(b)
	b.L(20, 52, 41, 73, 14, "p", true)
	b.L(41, 73, 82, 30, 14, "p", true)
end

DEFS.Gold = function(b)
	b.R(50, 82, 66, 13, "d", 0, 0.5)
	b.R(50, 73, 66, 13, "d", 0, 0.5)
	b.C(50, 46, 60, "p")
	b.O(50, 46, 46, 4, "l")
	b.O(50, 46, 26, 5, "d", 35, 320)
	b.R(56, 47, 9, 5, "d")
end

DEFS.Exp = function(b)
	b.P({ 50, 6, 80, 36, 50, 94, 20, 36 }, "p")
	b.P({ 50, 6, 62, 36, 50, 94, 38, 36 }, "l", 0.45)
	b.R(50, 36, 60, 3, "d", 0, nil, 0.3)
	b.Sparkle(82, 16, 7, "s")
end

DEFS.Music = function(b)
	b.R(34, 74, 26, 19, "p", -20, 0.5)
	b.R(70, 66, 26, 19, "p", -20, 0.5)
	b.R(44.5, 44, 7, 58, "p")
	b.R(80.5, 36, 7, 58, "p")
	b.P({ 41, 14, 84, 4, 84, 18, 41, 28 }, "p")
end

DEFS.Sound = function(b)
	b.R(22, 50, 18, 28, "p", 0, 0.15)
	b.P({ 28, 36, 52, 16, 52, 84, 28, 64 }, "p")
	b.O(52, 50, 36, 6, "p", -50, 50)
	b.O(52, 50, 64, 6, "s", -50, 50)
end

DEFS.Camera = function(b)
	b.R(36, 30, 26, 12, "p", 0, 0.3)
	b.R(50, 58, 84, 54, "p", 0, 0.16)
	b.O(50, 58, 40, 7, "d")
	b.C(50, 58, 20, "d")
	b.C(45, 53, 7, "l")
	b.R(77, 42, 9, 6, "l", 0, 0.3)
end

DEFS.Palette = function(b)
	b.C(50, 52, 84, "p")
	b.C(64, 72, 16, "d")
	b.C(30, 42, 13, "red")
	b.C(46, 28, 13, "yellow")
	b.C(65, 30, 13, "blue")
	b.C(76, 47, 13, "green")
end

DEFS.Map = function(b)
	b.P({ 10, 24, 36, 16, 36, 80, 10, 88 }, "p")
	b.P({ 36, 16, 64, 24, 64, 88, 36, 80 }, "d")
	b.P({ 64, 24, 90, 16, 90, 80, 64, 88 }, "p")
	b.T(66, 56, 14, 16, "Down", "s")
	b.C(66, 42, 20, "s")
	b.C(66, 42, 8, "w")
end

DEFS.Swords = function(b)
	b.Sword(22, 80, 82, 20, 9, "p", "s", "d")
	b.Sword(78, 80, 18, 20, 9, "p", "s", "d")
end

DEFS.Info = function(b)
	b.C(50, 50, 88, "p")
	b.C(50, 29, 12, "x")
	b.R(50, 61, 11, 34, "x", 0, 0.3)
end

DEFS.Plus = function(b)
	b.R(50, 50, 70, 15, "p", 0, 0.25)
	b.R(50, 50, 15, 70, "p", 0, 0.25)
end

DEFS.Minus = function(b)
	b.R(50, 50, 70, 15, "p", 0, 0.25)
end

DEFS.Refresh = function(b)
	b.O(50, 50, 74, 10, "p", -40, 225)
	local r, a = 32, math.rad(225)
	local tx, ty = math.cos(a + math.pi / 2), math.sin(a + math.pi / 2)
	b.Arrowhead(50 + r * math.cos(a) + tx * 10, 50 + r * math.sin(a) + ty * 10, 225 + 90, 17, "p")
end

DEFS.Users = function(b)
	b.Person(64, 46, 0.95, "d")
	b.Person(40, 56, 1.1, "p")
end

DEFS.Gamepad = function(b)
	b.C(24, 66, 30, "p")
	b.C(76, 66, 30, "p")
	b.R(50, 50, 86, 40, "p", 0, 0.5)
	b.R(27, 50, 17, 6, "d")
	b.R(27, 50, 6, 17, "d")
	b.C(71, 43, 8, "s")
	b.C(79, 51, 8, "s")
	b.C(63, 51, 8, "s")
	b.C(71, 59, 8, "s")
end

DEFS.Keyboard = function(b)
	b.R(50, 52, 92, 56, "p", 0, 0.12)
	for row = 0, 2 do
		local count = 7 - row
		local w = 9
		local gap = 3
		local total = count * w + (count - 1) * gap
		for i = 0, count - 1 do
			b.R(50 - total / 2 + w / 2 + i * (w + gap), 36 + row * 11, w, 8, "d", 0, 0.2)
		end
	end
	b.R(50, 69, 44, 8, "d", 0, 0.3)
end

DEFS.Phone = function(b)
	b.R(50, 50, 48, 88, "p", 0, 0.2)
	b.R(50, 47, 38, 62, "d", 0, 0.08)
	b.R(50, 11, 12, 3, "d", 0, 0.5)
	b.C(50, 85, 7, "d")
end

DEFS.Flag = function(b)
	b.R(22, 52, 6, 84, "d", 0, 0.5)
	b.P({ 25, 12, 82, 18, 70, 34, 84, 52, 25, 48 }, "p")
	b.C(22, 10, 9, "s")
end

DEFS.Bolt = function(b)
	b.P({ 56, 4, 24, 54, 46, 54, 36, 96, 76, 40, 47, 40, 70, 4 }, "p")
end

-- extra glyphs used by UIKit -----------------------------------------------------------------------
DEFS.Soul = DEFS.Heart

DEFS.Diamond = function(b)
	b.Diamond(50, 50, 56, "p")
	b.Diamond(50, 50, 24, "l")
end

DEFS.Sparkle = function(b)
	b.Sparkle(50, 50, 44, "p")
	b.Sparkle(80, 22, 10, "s")
end

DEFS.Fang = function(b)
	b.P({ 22, 18, 78, 18, 74, 38, 50, 90, 26, 38 }, "p")
	b.R(42, 34, 6, 22, "l", 0, 0.5, 0.4)
end

DEFS.Mouse = function(b)
	b.R(50, 52, 52, 80, "p", 0, 0.5)
	b.R(50, 34, 3, 22, "d")
	b.R(37, 30, 20, 26, "s", 0, 0.5, 0.2)
end

-- public API ---------------------------------------------------------------------------------------
local NAMES: { string } = {}
for name in DEFS do
	table.insert(NAMES, name)
end
table.sort(NAMES)

function Icons.Names(): { string }
	return table.clone(NAMES)
end

function Icons.Has(name: string): boolean
	return DEFS[name] ~= nil
end

function Icons.Create(name: string, color: Color3, size: (number | UDim2)?, accent: Color3?): Frame
	local root = Instance.new("Frame")
	root.Name = "Icon_" .. name
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	if typeof(size) == "number" then
		root.Size = UDim2.fromOffset(size :: number, size :: number)
	elseif typeof(size) == "UDim2" then
		root.Size = size :: UDim2
	else
		root.Size = UDim2.fromScale(1, 1)
	end
	root:SetAttribute("Icon", name)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = root
	local def = DEFS[name] or DEFS.Info
	local ctx: Ctx = { root = root, z = 0, tones = makeTones(color, accent) }
	def(builder(ctx))
	return root
end

return Icons
