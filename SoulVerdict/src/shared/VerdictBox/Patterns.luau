--!strict
-- VerdictBox/Patterns: the 2D attack library of the Verdict Box (SPEC §2.1, §11). [Lune-safe]
-- Builds a Sim.Timeline (pure data) from (pattern set, seed, duration): an opening line typed in a dialogue box
-- (Patterns.INTRO s, counts toward the duration), then EIGHT short attack segments chained deterministically from
-- the seed, scaled to fill exactly the duration (minus Patterns.END_PAD), escalating with the segment index
-- (k = 0 -> 1: speed, density, shorter warnings). Same (set, seed, duration) -> identical timeline everywhere.
--
-- Sets (kit field `VerdictBox`):
--   Classic  (The Judge)        bone gaps, sine-gap waves, bone rain, blue/orange walls, 4-blaster cross (+ / x),
--                               gravity slams with stabs, platforms over a bone floor + blaster, bone slides,
--                               a blaster spiral finale
--   Fell     (The Executioner)  faster, red bones, crossing bone rushes, chain-like bone sweeps, aggressive stab
--                               barrages, double slams, a fast bone tunnel, an "execution" finale (big blasters + stabs)
--   Eclipse  (Void Wanderer)    darkness flicker (box near black, only bone outlines glow), star-bone rains, closing
--                               eclipse rings, rift blasters from the box edges, gravity flips, a "totality" finale
-- Fairness (see Sim header for the soul): gaps >= 34 px for a 9 px hurt circle, successive gap shifts bounded by
-- the soul speed, stab warnings >= 0.28 s (escape distance < warning x speed), blasters fly in and charge >= 0.3 s,
-- beams leave reachable safe zones, blue-mode floor bones never pair a ceiling bone right after a low bone.
--
-- API
--   Patterns.SetIds -> {"Classic", "Fell", "Eclipse"} ; Patterns.Has(id) -> boolean ; Patterns.Resolve(id?) -> string
--   Patterns.Build(setId, seed, duration?) -> Sim.Timeline      (unknown set -> "Classic")
--   Patterns.Lines(setId) -> {string}                           opening line Strings keys
--   Patterns.Generators() -> {string}                           every segment generator name
--   Patterns.Chain(setId, seed) -> {string}                     the segment names a seed picks (debug / tests)
--   Patterns.INTRO, Patterns.END_PAD, Patterns.SEGMENTS (= 8)

local Sim = require(script.Parent.Sim)
local Rng = require(script.Parent.Parent.Util.Rng)
local Config = require(script.Parent.Parent.Config)

type Timeline = Sim.Timeline
type Bullet = Sim.Bullet

local Patterns = {}

Patterns.INTRO = 1.0
Patterns.END_PAD = 0.15
Patterns.SEGMENTS = 8
local LINGER = 0.35 -- red-mode bullets may outlive their segment when the next one is red in the same box

local T = Sim.Tuning
local PI = math.pi
local SQUARE, WIDE, DIALOG = Sim.BOX.Square, Sim.BOX.Wide, Sim.BOX.Dialog

type Seg = {
	name: string,
	t0: number,
	t1: number,
	dur: number,
	hardEnd: number,
	k: number,
	w: number,
	h: number,
	mode: string,
	gravity: string,
	spd: number,
	warn: number,
	params: { [string]: any },
}

type Ctx = {
	rng: Rng.Rng,
	tl: Timeline,
	set: SetDef,
}

type Gen = {
	mode: string, -- "Red" | "Blue"
	box: { number },
	nominal: number, -- relative duration weight
	min: number, -- shortest duration the generator needs (blaster volleys, slam + stab)
	gravity: string?, -- blue: "Down" | "Auto" (Down first, then any other wall)
	fn: (Ctx, Seg) -> (),
}

type Step = { pick: number?, from: { string }?, must: { string }?, name: string?, params: { [string]: any }? }

type SetDef = {
	theme: string,
	speed: number,
	warn: number,
	lines: { string },
	chain: { Step },
}

local function clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

---------------------------------------------------------------------------------------------------
-- Builder helpers

local function limitOf(ctx: Ctx, seg: Seg): number
	return math.min(seg.hardEnd, ctx.tl.duration)
end

local function add(ctx: Ctx, seg: Seg, kind: string, spec: { [string]: any }): Bullet?
	local b = Sim.Bullet(kind, spec)
	local limit = limitOf(ctx, seg)
	if b.t0 >= limit then
		return nil
	end
	if b.t1 > limit then
		b.t1 = limit
	end
	if b.t1 <= b.t0 then
		return nil
	end
	b.id = #ctx.tl.bullets + 1
	table.insert(ctx.tl.bullets, b)
	return b
end

local function setMode(ctx: Ctx, t: number, mode: string, gravity: string, slam: boolean, w: number, h: number)
	table.insert(ctx.tl.modes, { t = t, mode = mode, gravity = gravity, slam = slam, w = w, h = h })
end

local function effect(ctx: Ctx, kind: string, t0: number, t1: number, level: number)
	if t1 > t0 then
		table.insert(ctx.tl.effects, { kind = kind, t0 = t0, t1 = math.min(t1, ctx.tl.duration), level = level })
	end
end

local function wallOf(gravity: string): string
	if gravity == "Up" then
		return "Top"
	elseif gravity == "Left" then
		return "Left"
	elseif gravity == "Right" then
		return "Right"
	end
	return "Bottom"
end

-- Stab over the whole wall (or [a, b]); shortens hold / warning to fit the segment, skips when impossible.
local function stab(ctx: Ctx, seg: Seg, t: number, wall: string, height: number, warn: number, opts: { [string]: any }?)
	local o = opts or {}
	local along = if wall == "Bottom" or wall == "Top" then seg.w else seg.h
	local a = o.a or -along / 2 - 2
	local b = o.b or along / 2 + 2
	local rise, fall = o.rise or 0.06, o.fall or 0.12
	local hold = o.hold or 0.28
	local limit = limitOf(ctx, seg)
	local room = limit - t - rise - fall
	if warn + hold > room then
		hold = math.max(room - warn, 0.12)
		if warn + hold > room then
			warn = math.max(room - hold, 0.28)
		end
		if warn + hold > room + 1e-6 then
			return nil
		end
	end
	return add(ctx, seg, "Stab", {
		t0 = t,
		wall = wall,
		a = a,
		b = b,
		height = height,
		warn = warn,
		rise = rise,
		hold = hold,
		fall = fall,
		bw = seg.w,
		bh = seg.h,
		color = o.color or "White",
		style = o.style or "",
	})
end

-- Blaster at final position (x, y) firing along `angle`; flies in from outside. Skipped if its beam would not
-- finish inside the segment.
local function blaster(ctx: Ctx, seg: Seg, t: number, x: number, y: number, angle: number, opts: { [string]: any }?)
	local o = opts or {}
	local appear = o.appear or 0.22
	local charge = o.charge or 0.4
	local fire = o.fire or 0.27
	local limit = limitOf(ctx, seg)
	if t + appear + charge + fire > limit + 1e-6 then
		charge = limit - t - appear - fire -- fit: shorter charge, never below 0.3 s
		if charge < 0.3 - 1e-6 then
			return nil
		end
	end
	local back = o.back or 40
	return add(ctx, seg, "Blaster", {
		t0 = t,
		x = x,
		y = y,
		angle = angle,
		scale = o.scale or 1,
		ex = o.ex or -math.cos(angle) * back,
		ey = o.ey or -math.sin(angle) * back,
		turn = o.turn or 0.9,
		appear = appear,
		charge = charge,
		fire = fire,
		fade = o.fade or 0.25,
		style = o.style or "",
	})
end

-- Vertical wall of bones (top + bottom bone around a gap) moving horizontally from `side` ("Left"/"Right").
local function gapWall(ctx: Ctx, seg: Seg, t: number, side: string, gapC: number, gap: number, speed: number, opts: { [string]: any }?)
	local o = opts or {}
	local w, h = seg.w, seg.h
	local dir = if side == "Left" then 1 else -1
	local thick = o.thick or 10
	local x0 = -dir * (w / 2 + thick)
	local life = (w + thick * 2 + 8) / speed
	local top, bot = -h / 2 - 12, h / 2 + 12
	local gapTop, gapBot = gapC - gap / 2, gapC + gap / 2
	local color = o.color or "White"
	local style = o.style or ""
	if gapTop - top > 8 then
		add(ctx, seg, "Bone", {
			t0 = t,
			t1 = t + life,
			x = x0,
			y = (top + gapTop) / 2,
			vx = dir * speed,
			len = gapTop - top,
			thick = thick,
			color = color,
			style = style,
		})
	end
	if bot - gapBot > 8 then
		add(ctx, seg, "Bone", {
			t0 = t,
			t1 = t + life,
			x = x0,
			y = (gapBot + bot) / 2,
			vx = dir * speed,
			len = bot - gapBot,
			thick = thick,
			color = color,
			style = style,
		})
	end
end

-- A full-height wall (one long bone) sweeping horizontally: the colour lesson (Blue = stay still, Orange = move).
local function fullWall(ctx: Ctx, seg: Seg, t: number, side: string, speed: number, color: string)
	local dir = if side == "Left" then 1 else -1
	add(ctx, seg, "Bone", {
		t0 = t,
		t1 = t + (seg.w + 30) / speed,
		x = -dir * (seg.w / 2 + 8),
		y = 0,
		vx = dir * speed,
		len = seg.h + 28,
		thick = 12,
		color = color,
	})
end

-- Chain of bones lying end to end across the box, sweeping perpendicular to itself, with a 2-link gap.
local function chain(ctx: Ctx, seg: Seg, t: number, vertical: boolean, fromStart: boolean, speed: number, color: string?)
	local rng = ctx.rng
	local span = if vertical then seg.h else seg.w
	local depth = if vertical then seg.w else seg.h
	local link = 22
	local n = math.ceil((span + 16) / link)
	local gapAt = rng:Integer(1, n - 2)
	local dir = if fromStart then 1 else -1
	local p0 = -dir * (depth / 2 + 8)
	local life = (depth + 20) / speed
	for i = 0, n - 1 do
		if i ~= gapAt and i ~= gapAt + 1 then
			local along = -span / 2 - 8 + link * (i + 0.5)
			add(ctx, seg, "Bone", {
				t0 = t,
				t1 = t + life,
				x = if vertical then p0 else along,
				y = if vertical then along else p0,
				vx = if vertical then dir * speed else 0,
				vy = if vertical then 0 else dir * speed,
				len = link,
				thick = 9,
				angle = if vertical then 0 else PI / 2,
				color = color or "White",
				style = "Chain",
			})
		end
	end
end

local function star(ctx: Ctx, seg: Seg, spec: { [string]: any })
	spec.len = spec.len or 22
	spec.thick = spec.thick or 6
	add(ctx, seg, "Star", spec)
end

-- Rift on a box edge + a blaster emerging from it (flies outward, spins round) and firing back across the box.
local function riftBlaster(ctx: Ctx, seg: Seg, t: number, edge: string, offset: number, tilt: number, opts: { [string]: any }?)
	local o = opts or {}
	local w, h = seg.w, seg.h
	local px, py, nx, ny -- edge point and inward normal
	if edge == "Left" then
		px, py, nx, ny = -w / 2, offset, 1, 0
	elseif edge == "Right" then
		px, py, nx, ny = w / 2, offset, -1, 0
	elseif edge == "Top" then
		px, py, nx, ny = offset, -h / 2, 0, 1
	else
		px, py, nx, ny = offset, h / 2, 0, -1
	end
	local angle = math.atan2(ny, nx) + tilt
	local out = 30
	local charge = o.charge or 0.38
	local b = blaster(ctx, seg, t, px - nx * out, py - ny * out, angle, {
		ex = nx * out,
		ey = ny * out,
		turn = PI,
		appear = 0.24,
		charge = charge,
		fire = o.fire or 0.27,
		style = "Rift",
		scale = o.scale or 1,
	})
	if b then
		add(ctx, seg, "Rift", {
			t0 = t - 0.12,
			t1 = t + 0.24 + b.charge + 0.2,
			x = px,
			y = py,
			angle = math.atan2(ny, nx) + PI / 2,
			len = 46,
			thick = 12,
		})
	end
end

local function sideOf(rng: Rng.Rng): string
	return if rng:Bool() then "Left" else "Right"
end

---------------------------------------------------------------------------------------------------
-- Segment generators (each fits its bullets into [seg.t0, seg.hardEnd])

local GEN: { [string]: Gen } = {}

-- Classic -----------------------------------------------------------------------------------------

GEN.BoneWall = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.7,
	min = 0.5,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local n = if seg.k > 0.45 then 3 else 2
		local speed = 165 * seg.spd * (1 + 0.3 * seg.k)
		local gap = 46 - 10 * seg.k
		local spacing = math.max((seg.dur - 0.05) / n, 0.3)
		local side = sideOf(rng)
		local lim = seg.h / 2 - gap / 2 - 14
		local c = rng:Number(-1, 1) * lim
		local maxShift = T.SoulSpeed * spacing * 0.55
		local glow = if seg.params.glow then "Glow" else ""
		for i = 0, n - 1 do
			gapWall(ctx, seg, seg.t0 + 0.04 + i * spacing, side, c, gap, speed, { style = glow })
			local shift = rng:Number(0.35, 1) * maxShift * (if rng:Bool() then 1 else -1)
			if math.abs(c + shift) > lim then
				shift = -shift
			end
			c = clamp(c + shift, -lim, lim)
		end
	end,
}

GEN.SineWave = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.75,
	min = 0.5,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local speed = 185 * seg.spd * (1 + 0.25 * seg.k)
		local pairDt = 16 / speed
		local gap = 46 - 6 * seg.k
		local amp = math.min(seg.h / 2 - gap / 2 - 12, 38)
		local omega = 0.55 * T.SoulSpeed / amp
		local phase = rng:Number(0, 2 * PI)
		local side = sideOf(rng)
		local count = math.max(math.floor(seg.dur * 0.92 / pairDt), 4)
		for i = 0, count - 1 do
			local c = amp * math.sin(phase + omega * i * pairDt)
			gapWall(ctx, seg, seg.t0 + 0.04 + i * pairDt, side, c, gap, speed, { thick = 8 })
		end
	end,
}

GEN.BoneRain = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.65,
	min = 0.4,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local interval = 0.1 - 0.025 * seg.k
		local n = math.max(math.floor((seg.dur - 0.05) / interval), 3)
		local lastX = 1e9
		for i = 0, n - 1 do
			local x = rng:Number(-seg.w / 2 + 10, seg.w / 2 - 10)
			if math.abs(x - lastX) < 26 then
				x = clamp(x + (if x > lastX then 30 else -30), -seg.w / 2 + 10, seg.w / 2 - 10)
			end
			lastX = x
			local len = rng:Number(18, 28)
			local vy = (165 + 75 * seg.k) * seg.spd * rng:Number(0.9, 1.1)
			local t = seg.t0 + 0.02 + i * interval
			add(ctx, seg, "Bone", {
				t0 = t,
				t1 = t + (seg.h + len + 12) / vy,
				x = x,
				y = -seg.h / 2 - len / 2 - 4,
				vx = rng:Number(-14, 14),
				vy = vy,
				len = len,
				thick = 9,
				color = if seg.k > 0.4 and rng:Bool(0.2) then "Blue" else "White",
			})
		end
	end,
}

GEN.ColorWalls = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.7,
	min = 0.55,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local speed = 190 * seg.spd * (1 + 0.2 * seg.k)
		local side = sideOf(rng)
		local spacing = clamp(seg.dur * 0.45, 0.32, 0.5)
		local first = if rng:Bool(0.65) then "Blue" else "Orange"
		local second = if first == "Blue" then "Orange" else "Blue"
		fullWall(ctx, seg, seg.t0 + 0.04, side, speed, first)
		fullWall(ctx, seg, seg.t0 + 0.04 + spacing, side, speed, second)
		if seg.k > 0.5 then
			fullWall(ctx, seg, seg.t0 + 0.04 + spacing * 2, side, speed, first)
		end
	end,
}

local function crossVolley(ctx: Ctx, seg: Seg, t: number, shape: string, opts: { [string]: any })
	local w, h = seg.w, seg.h
	if shape == "Plus" then
		blaster(ctx, seg, t, -w / 2 - 36, 0, 0, opts)
		blaster(ctx, seg, t, w / 2 + 36, 0, PI, opts)
		blaster(ctx, seg, t, 0, -h / 2 - 36, PI / 2, opts)
		blaster(ctx, seg, t, 0, h / 2 + 36, -PI / 2, opts)
	else
		local d = 26
		blaster(ctx, seg, t, -w / 2 - d, -h / 2 - d, PI / 4, opts)
		blaster(ctx, seg, t, w / 2 + d, -h / 2 - d, 3 * PI / 4, opts)
		blaster(ctx, seg, t, w / 2 + d, h / 2 + d, -3 * PI / 4, opts)
		blaster(ctx, seg, t, -w / 2 - d, h / 2 + d, -PI / 4, opts)
	end
end

GEN.BlasterCross = {
	mode = "Red",
	box = SQUARE,
	nominal = 1.25,
	min = 1.17,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local fast = seg.params.fast == true
		local style = seg.params.style or ""
		local fire = if fast then 0.22 else 0.27
		local appear = 0.22
		local gap = 0.1
		local room = limitOf(ctx, seg) - seg.t0
		-- both volleys must fit: the second one fires `gap` s after the first beams end
		local charge = clamp(room - appear - 2 * fire - gap, 0.3, math.max((0.42 - 0.1 * seg.k) * seg.warn, 0.3))
		local opts = { charge = charge, fire = fire, appear = appear, style = style }
		local first = if rng:Bool() then "Plus" else "X"
		local second = if first == "Plus" then "X" else "Plus"
		crossVolley(ctx, seg, seg.t0, first, opts)
		-- (the wedges between the + and x beams are safe for both volleys)
		local t2 = seg.t0 + fire + gap
		crossVolley(ctx, seg, t2, second, opts)
		if seg.k > 0.6 then
			crossVolley(ctx, seg, t2 + fire + gap, first, opts)
		end
	end,
}

-- time for a slam to reach the wall from anywhere in the box (+ a beat)
local function slamTime(seg: Seg, gravity: string): number
	local extent = if gravity == "Left" or gravity == "Right" then seg.w else seg.h
	return 0.06 + (extent - 2 * T.SoulHalf) / T.SlamSpeed
end

GEN.SlamStab = {
	mode = "Blue",
	box = SQUARE,
	nominal = 0.95,
	min = 0.88,
	gravity = "Auto",
	fn = function(ctx, seg)
		local rng = ctx.rng
		local style = if seg.params.glow then "Glow" else ""
		local double = seg.params.double and seg.dur >= 1.7
		local g1 = seg.gravity
		-- the red warning shows while the soul is slammed; the stab rises >= 0.24 s after the worst-case landing
		local t1 = seg.t0 + 0.1
		local warn = slamTime(seg, g1) - 0.1 + math.max((0.3 - 0.05 * seg.k) * seg.warn, 0.24)
		stab(ctx, seg, t1, wallOf(g1), 32, warn, { style = style, hold = if double then 0.16 else 0.28 })
		if seg.params.flank then
			-- Fell: a second stab juts from a side wall over the half next to the floor: jump AND drift away
			local vertical = g1 == "Down" or g1 == "Up"
			local wall = if vertical
				then (if rng:Bool() then "Left" else "Right")
				else (if rng:Bool() then "Top" else "Bottom")
			local sign = if g1 == "Down" or g1 == "Right" then 1 else -1
			local along = if vertical then seg.h else seg.w
			local a, b = 0, sign * (along / 2 + 2)
			stab(ctx, seg, t1, wall, 40, warn, { style = style, a = math.min(a, b), b = math.max(a, b) })
		end
		if double then
			local tm = seg.t0 + seg.dur * 0.5
			local walls = { "Down", "Left", "Right", "Up" }
			table.remove(walls, table.find(walls, g1) or 1)
			local g2 = walls[rng:Integer(1, #walls)]
			setMode(ctx, tm, "Blue", g2, true, seg.w, seg.h)
			local warn2 = slamTime(seg, g2) - 0.1 + math.max((0.3 - 0.05 * seg.k) * seg.warn, 0.24)
			stab(ctx, seg, tm + 0.1, wallOf(g2), 32, warn2, { style = style })
		end
	end,
}

GEN.PlatformBlaster = {
	mode = "Blue",
	box = WIDE,
	nominal = 0.9,
	min = 0.75,
	gravity = "Down",
	fn = function(ctx, seg)
		local rng = ctx.rng
		local w, h = seg.w, seg.h
		local limit = limitOf(ctx, seg)
		local top = h / 2 - 44 -- platform top surface (44 px above the floor: one full jump reaches it)
		local dir = if rng:Bool() then 1 else -1
		for i, px in { -120, 0, 120 } do
			local v = (if i % 2 == 0 then -1 else 1) * dir * 26
			add(ctx, seg, "Platform", {
				t0 = seg.t0,
				t1 = limit,
				x = px,
				y = top + T.PlatformThick / 2,
				w = 66,
				vx = v,
				minX = px - 22,
				maxX = px + 22,
			})
		end
		local warn = math.max(0.46 * seg.warn, 0.36)
		stab(ctx, seg, seg.t0, "Bottom", 18, warn, { hold = math.max(limit - seg.t0 - warn - 0.06 - 0.12, 0.12) })
		-- a beam just above the platforms: stay low (don't jump) while it fires
		local side = if rng:Bool() then -1 else 1
		blaster(ctx, seg, seg.t0 + 0.3, side * (w / 2 + 34), top - 38, if side < 0 then 0 else PI, {
			charge = math.max(0.42 * seg.warn, 0.32),
		})
	end,
}

GEN.BoneSlide = {
	mode = "Blue",
	box = WIDE,
	nominal = 0.8,
	min = 0.6,
	gravity = "Down",
	fn = function(ctx, seg)
		local rng = ctx.rng
		local fast = seg.params.fast == true
		local w, h = seg.w, seg.h
		local speed = (if fast then 230 else 175) * seg.spd * (1 + 0.25 * seg.k)
		local interval = math.max((if fast then 0.27 else 0.33) - 0.05 * seg.k, 0.22)
		local side = if rng:Bool() then 1 else -1
		local n = math.max(math.floor((seg.dur - 0.05) / interval), 2)
		local prev = ""
		local floorY = h / 2 + 12
		for i = 0, n - 1 do
			local roll = rng:Number()
			local kind = "Low"
			if roll < 0.28 and prev ~= "Low" then
				kind = "High"
			elseif roll > (if fast then 0.66 else 0.78) and seg.k > 0.25 then
				kind = if seg.params.orange and rng:Bool() then "Orange" else "Blue"
			end
			prev = kind
			local t = seg.t0 + 0.05 + i * interval
			local life = (w + 40) / speed
			local len, y, color
			if kind == "High" then
				len = h - 40 + 12 -- leaves 40 px above the floor: stand, don't jump
				y = -h / 2 - 12 + len / 2
				color = "White"
			elseif kind == "Blue" or kind == "Orange" then
				len = 46 + 12
				y = floorY - len / 2
				color = kind
			else
				len = rng:Number(22, 28) + 12
				y = floorY - len / 2
				color = "White"
			end
			add(ctx, seg, "Bone", {
				t0 = t,
				t1 = t + life,
				x = side * (w / 2 + 12),
				y = y,
				vx = -side * speed,
				len = len,
				thick = 10,
				color = color,
			})
		end
	end,
}

GEN.BoneTunnel = {
	mode = "Blue",
	box = WIDE,
	nominal = 0.8,
	min = 0.6,
	gravity = "Down",
	fn = function(ctx, seg)
		seg.params.fast = true
		seg.params.orange = true
		GEN.BoneSlide.fn(ctx, seg)
	end,
}

GEN.Spiral = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.95,
	min = 0.85,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local limit = limitOf(ctx, seg)
		local appear, fire = 0.2, 0.25
		local charge = math.max((0.45 - 0.1 * seg.k) * seg.warn, 0.3)
		local n = 5 + math.floor(2 * seg.k + 0.5)
		local window = limit - seg.t0 - (appear + charge + fire) - 0.02
		local spacing = math.max(window / (n - 1), 0.12)
		local base = rng:Number(0, 2 * PI)
		local spin = (if rng:Bool() then 1 else -1) * (2 * PI / n) * 1.25
		for i = 0, n - 1 do
			local a = base + spin * i
			local R = 128
			local x, y = math.cos(a) * R, math.sin(a) * R
			local off = (if i % 2 == 0 then 1 else -1) * rng:Number(16, 34)
			-- aim at a point offset sideways from the centre
			local tx, ty = -math.sin(a) * off, math.cos(a) * off
			blaster(ctx, seg, seg.t0 + i * spacing, x, y, math.atan2(ty - y, tx - x), {
				appear = appear,
				charge = charge,
				fire = fire,
			})
		end
	end,
}

-- Fell --------------------------------------------------------------------------------------------

GEN.RedRush = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.7,
	min = 0.5,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local speed = 200 * seg.spd * (1 + 0.3 * seg.k)
		local gap = 42 - 6 * seg.k
		local lim = seg.h / 2 - gap / 2 - 14
		local cA = rng:Number(-1, 1) * lim
		local cB = clamp(cA + (if rng:Bool() then 1 else -1) * rng:Number(20, 46), -lim, lim)
		local first = sideOf(rng)
		local second = if first == "Left" then "Right" else "Left"
		gapWall(ctx, seg, seg.t0 + 0.04, first, cA, gap, speed, { thick = 11 })
		gapWall(ctx, seg, seg.t0 + 0.22, second, cB, gap, speed, { thick = 11 })
		if seg.dur > 0.7 then
			local cC = clamp(cB + (if rng:Bool() then 1 else -1) * rng:Number(16, 40), -lim, lim)
			gapWall(ctx, seg, seg.t0 + 0.46, first, cC, gap, speed, { thick = 11 })
		end
	end,
}

GEN.ChainSweep = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.75,
	min = 0.6,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local speed = 150 * seg.spd * (1 + 0.3 * seg.k)
		local vertical = rng:Bool()
		chain(ctx, seg, seg.t0 + 0.03, vertical, rng:Bool(), speed)
		chain(ctx, seg, seg.t0 + math.max(seg.dur * 0.45, 0.3), not vertical, rng:Bool(), speed * 1.05)
	end,
}

GEN.StabBarrage = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.75,
	min = 0.6,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local n = if seg.k > 0.6 then 4 else 3
		local spacing = math.max((seg.dur - 0.3) / n, 0.18)
		local warn = math.max((0.42 - 0.08 * seg.k) * seg.warn, 0.32)
		local walls = { "Left", "Right", "Top", "Bottom" }
		local prev = ""
		for i = 0, n - 1 do
			local wall = walls[rng:Integer(1, 4)]
			if wall == prev then
				wall = walls[(table.find(walls, wall) :: number) % 4 + 1]
			end
			prev = wall
			stab(ctx, seg, seg.t0 + 0.02 + i * spacing, wall, 38, warn, { hold = 0.22, rise = 0.05, fall = 0.1 })
		end
	end,
}

-- Narrow full-height bone columns crash down from the ceiling one after another (step aside).
GEN.Guillotine = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.7,
	min = 0.6,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local n = if seg.k > 0.6 then 5 else 4
		local width = 34
		local spacing = math.max((seg.dur - 0.55) / (n - 1), 0.1)
		local warn = math.max((0.36 - 0.06 * seg.k) * seg.warn, 0.3)
		local lim = seg.w / 2 - width / 2
		local lastX = 1e9
		for i = 0, n - 1 do
			local x = rng:Number(-lim, lim)
			if math.abs(x - lastX) < width then
				x = clamp(x + (if x > lastX then width else -width), -lim, lim)
			end
			lastX = x
			stab(ctx, seg, seg.t0 + 0.02 + i * spacing, "Top", seg.h + 4, warn, {
				a = x - width / 2,
				b = x + width / 2,
				rise = 0.07,
				hold = 0.12,
				fall = 0.1,
			})
		end
	end,
}

GEN.Execution = {
	mode = "Red",
	box = SQUARE,
	nominal = 1.0,
	min = 0.9,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local w, h = seg.w, seg.h
		local charge = math.max(0.4 * seg.warn, 0.32)
		local side = if rng:Bool() then 1 else -1
		-- two big beams along the top and bottom thirds (safe middle band) ...
		for _, row in { -50, 50 } do
			blaster(ctx, seg, seg.t0, side * (w / 2 + 44), row, if side > 0 then PI else 0, {
				scale = 1.4,
				charge = charge,
				style = "Big",
			})
		end
		-- ... while stabs close in from the left and right walls (safe centre)
		stab(ctx, seg, seg.t0 + 0.2, "Left", 40, 0.36, { hold = 0.32 })
		stab(ctx, seg, seg.t0 + 0.2, "Right", 40, 0.36, { hold = 0.32 })
		-- then the verdict: one big vertical beam beside the centre
		local x = (if rng:Bool() then 1 else -1) * rng:Number(24, 34)
		blaster(ctx, seg, seg.t0 + 0.55, x, -h / 2 - 46, PI / 2, { scale = 1.3, charge = charge, style = "Big" })
	end,
}

-- Eclipse -----------------------------------------------------------------------------------------

GEN.StarRain = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.7,
	min = 0.4,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local dark = seg.params.dark == true
		local interval = (if dark then 0.1 else 0.085) - 0.02 * seg.k
		local n = math.max(math.floor((seg.dur - 0.04) / interval), 3)
		local lastX = 1e9
		if dark then
			effect(ctx, "Dark", seg.t0, seg.t1, 0.9)
		end
		for i = 0, n - 1 do
			local x = rng:Number(-seg.w / 2 + 12, seg.w / 2 - 12)
			if math.abs(x - lastX) < 28 then
				x = clamp(x + (if x > lastX then 32 else -32), -seg.w / 2 + 12, seg.w / 2 - 12)
			end
			lastX = x
			local vy = (125 + 60 * seg.k) * seg.spd * rng:Number(0.9, 1.15)
			local t = seg.t0 + 0.02 + i * interval
			star(ctx, seg, {
				t0 = t,
				t1 = t + (seg.h + 40) / vy,
				x = x,
				y = -seg.h / 2 - 14,
				vx = rng:Number(-22, 22),
				vy = vy,
				spin = rng:Number(-5, 5),
				angle = rng:Number(0, PI),
				color = if seg.k > 0.4 and rng:Bool(0.18) then "Orange" else "White",
			})
		end
	end,
}

GEN.DarkGap = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.75,
	min = 0.5,
	fn = function(ctx, seg)
		-- darkness flicker: dark, a brief light flash, dark again
		local mid = seg.t0 + seg.dur * 0.45
		effect(ctx, "Dark", seg.t0, mid, 0.93)
		effect(ctx, "Flash", mid, mid + 0.07, 0.35)
		effect(ctx, "Dark", mid + 0.07, seg.t1 + 0.1, 0.93)
		seg.params.glow = true
		GEN.BoneWall.fn(ctx, seg)
	end,
}

local function ring(ctx: Ctx, seg: Seg, t: number, inward: boolean, speed: number)
	local rng = ctx.rng
	local slots = 14
	local gapAt = rng:Integer(0, slots - 1)
	local base = rng:Number(0, 2 * PI)
	local va = (if rng:Bool() then 1 else -1) * 0.5
	local r0 = if inward then 128 else 10
	local rEnd = if inward then 8 else 140
	local life = math.abs(rEnd - r0) / speed
	for i = 0, slots - 1 do
		local rel = (i - gapAt) % slots
		if rel > 2 then -- three missing slots = the way through
			star(ctx, seg, {
				t0 = t,
				t1 = t + life + (if inward then 0 else 0.3),
				polar = true,
				cx = 0,
				cy = 0,
				r0 = r0,
				vr = if inward then -speed else speed,
				rmin = if inward then 8 else -1,
				a0 = base + i * 2 * PI / slots,
				va = va,
				spin = va * 3,
				delay = if inward then 0 else 0.35,
				len = 22,
			})
		end
	end
end

GEN.EclipseRing = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.8,
	min = 0.55,
	fn = function(ctx, seg)
		ring(ctx, seg, seg.t0, true, 150 + 40 * seg.k)
		if seg.k > 0.45 and seg.dur > 0.75 then
			ring(ctx, seg, seg.t0 + seg.dur * 0.55, false, 120 + 30 * seg.k)
		end
	end,
}

GEN.RiftBlasters = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.9,
	min = 1.05,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local edges = rng:Shuffle({ "Left", "Right", "Top", "Bottom" })
		local n = 3 + math.floor(seg.k * 1.5)
		local room = limitOf(ctx, seg) - seg.t0 - 0.04
		local spacing = 0.1
		local charge = clamp(room - 0.24 - 0.27 - (n - 1) * spacing, 0.3, 0.38)
		while n > 2 and 0.24 + charge + 0.27 + (n - 1) * spacing > room do
			n -= 1
		end
		for i = 0, n - 1 do
			local edge = edges[i % 4 + 1]
			riftBlaster(ctx, seg, seg.t0 + 0.04 + i * spacing, edge, rng:Number(-45, 45), rng:Number(-0.3, 0.3), {
				charge = charge,
			})
		end
	end,
}

GEN.GravityFlip = {
	mode = "Blue",
	box = SQUARE,
	nominal = 0.9,
	min = 0.65,
	gravity = "Down",
	fn = function(ctx, seg)
		local rng = ctx.rng
		local half = seg.dur * 0.5
		local function stars(t0: number, fromTop: boolean)
			local n = 3 + math.floor(seg.k * 2)
			for i = 0, n - 1 do
				local t = t0 + 0.16 + i * math.max((half - 0.2) / n, 0.08)
				local vy = (150 + 40 * seg.k) * seg.spd
				star(ctx, seg, {
					t0 = t,
					t1 = t + (seg.h + 40) / vy,
					x = rng:Number(-seg.w / 2 + 14, seg.w / 2 - 14),
					y = if fromTop then -seg.h / 2 - 14 else seg.h / 2 + 14,
					vy = if fromTop then vy else -vy,
					spin = rng:Number(-4, 4),
				})
			end
		end
		stars(seg.t0, true)
		setMode(ctx, seg.t0 + half, "Blue", "Up", true, seg.w, seg.h)
		effect(ctx, "Flash", seg.t0 + half, seg.t0 + half + 0.06, 0.3)
		stars(seg.t0 + half, false)
	end,
}

GEN.DarkStabs = {
	mode = "Blue",
	box = WIDE,
	nominal = 0.9,
	min = 0.88,
	gravity = "Down",
	fn = function(ctx, seg)
		effect(ctx, "Dark", seg.t0 + 0.05, seg.t1 + 0.05, 0.9)
		seg.params.glow = true
		GEN.SlamStab.fn(ctx, seg)
		-- star-bones drift down through the dark while the floor stab is up
		local rng = ctx.rng
		for i = 0, 2 do
			local t = seg.t0 + 0.3 + i * 0.16
			local vy = 120 * seg.spd
			star(ctx, seg, {
				t0 = t,
				t1 = t + (seg.h + 40) / vy,
				x = rng:Number(-seg.w / 2 + 20, seg.w / 2 - 20),
				y = -seg.h / 2 - 14,
				vy = vy,
				spin = rng:Number(-4, 4),
			})
		end
	end,
}

GEN.RiftCross = {
	mode = "Red",
	box = SQUARE,
	nominal = 0.95,
	min = 0.85,
	fn = function(ctx, seg)
		local rng = ctx.rng
		local first = if rng:Bool() then 0 else PI / 4
		-- rifts at the corners / edge midpoints, four beams through the centre, then the other diagonal set
		local function volley(t: number, rot: number)
			for i = 0, 3 do
				local a = rot + i * PI / 2
				local R = if rot % (PI / 2) == 0 then 82 else 82 * math.sqrt(2)
				local px, py = math.cos(a) * R, math.sin(a) * R
				local nx, ny = -math.cos(a), -math.sin(a)
				local b = blaster(ctx, seg, t, px - nx * 30, py - ny * 30, math.atan2(ny, nx), {
					ex = nx * 30,
					ey = ny * 30,
					turn = PI,
					appear = 0.24,
					charge = math.max(0.38 * seg.warn, 0.32),
					style = "Rift",
				})
				if b then
					add(ctx, seg, "Rift", {
						t0 = t - 0.12,
						t1 = t + 0.24 + b.charge + 0.2,
						x = px,
						y = py,
						angle = a + PI / 2,
						len = 46,
						thick = 12,
					})
				end
			end
		end
		volley(seg.t0, first)
		volley(seg.t0 + 0.27 + 0.12, if first == 0 then PI / 4 else 0)
		if seg.params.dark then
			effect(ctx, "Dark", seg.t0, seg.t1, 0.85)
		end
	end,
}

GEN.Totality = {
	mode = "Red",
	box = SQUARE,
	nominal = 1.0,
	min = 0.85,
	fn = function(ctx, seg)
		local rng = ctx.rng
		-- darkness pulses with brief light
		local t = seg.t0
		while t < seg.t1 do
			local len = rng:Number(0.22, 0.34)
			effect(ctx, "Dark", t, math.min(t + len, seg.t1 + 0.1), 0.95)
			effect(ctx, "Flash", t + len, t + len + 0.05, 0.25)
			t += len + 0.07
		end
		ring(ctx, seg, seg.t0, true, 160)
		local edges = rng:Shuffle({ "Left", "Right", "Top", "Bottom" })
		riftBlaster(ctx, seg, seg.t0 + 0.42, edges[1], rng:Number(-40, 40), rng:Number(-0.25, 0.25))
		riftBlaster(ctx, seg, seg.t0 + 0.6, edges[2], rng:Number(-40, 40), rng:Number(-0.25, 0.25))
	end,
}

---------------------------------------------------------------------------------------------------
-- Sets

local SETS: { [string]: SetDef } = {
	Classic = {
		theme = "Classic",
		speed = 1.0,
		warn = 1.0,
		lines = { "vb.line.Classic.1", "vb.line.Classic.2", "vb.line.Classic.3" },
		chain = {
			{ pick = 3, from = { "BoneWall", "SineWave", "BoneRain" }, must = { "ColorWalls" } },
			{ name = "BlasterCross" },
			{ name = "SlamStab" },
			{ pick = 2, from = { "PlatformBlaster", "BoneSlide" } },
			{ name = "Spiral" },
		},
	},
	Fell = {
		theme = "Fell",
		speed = 1.18,
		warn = 0.85,
		lines = { "vb.line.Fell.1", "vb.line.Fell.2", "vb.line.Fell.3" },
		chain = {
			{ pick = 3, from = { "RedRush", "ChainSweep", "StabBarrage" } },
			{ name = "BlasterCross", params = { fast = true } },
			{ name = "SlamStab", params = { flank = true } },
			{ name = "BoneTunnel" },
			{ pick = 1, from = { "ChainSweep", "StabBarrage", "Guillotine" } },
			{ name = "Execution" },
		},
	},
	Eclipse = {
		theme = "Eclipse",
		speed = 1.05,
		warn = 1.0,
		lines = { "vb.line.Eclipse.1", "vb.line.Eclipse.2", "vb.line.Eclipse.3" },
		chain = {
			{ pick = 3, from = { "StarRain", "DarkGap", "EclipseRing" } },
			{ name = "RiftBlasters" },
			{ name = "GravityFlip" },
			{ name = "DarkStabs" },
			{ pick = 1, from = { "RiftCross", "StarRain" }, params = { dark = true } },
			{ name = "Totality" },
		},
	},
}

Patterns.SetIds = { "Classic", "Fell", "Eclipse" }

function Patterns.Has(id: string?): boolean
	return type(id) == "string" and SETS[id] ~= nil
end

function Patterns.Resolve(id: string?): string
	if type(id) == "string" and SETS[id] ~= nil then
		return id
	end
	return "Classic"
end

function Patterns.Lines(id: string?): { string }
	return table.clone(SETS[Patterns.Resolve(id)].lines)
end

function Patterns.Generators(): { string }
	local out = {}
	for name in GEN do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

type Item = { name: string, params: { [string]: any } }

local function chainItems(set: SetDef, rng: Rng.Rng): { Item }
	local items: { Item } = {}
	for _, step in set.chain do
		local params = step.params or {}
		if step.pick then
			local pool = table.clone(step.from or {})
			local chosen = table.clone(step.must or {})
			rng:Shuffle(pool)
			for _, name in pool do
				if #chosen >= step.pick then
					break
				end
				table.insert(chosen, name)
			end
			rng:Shuffle(chosen)
			for _, name in chosen do
				table.insert(items, { name = name, params = table.clone(params) })
			end
		else
			table.insert(items, { name = step.name :: string, params = table.clone(params) })
		end
	end
	return items
end

local function seedRng(id: string, seed: number): Rng.Rng
	local s = if type(seed) == "number" and seed == seed then seed else 0
	return Rng.new(Rng.Hash(s, id))
end

function Patterns.Chain(setId: string?, seed: number): { string }
	local id = Patterns.Resolve(setId)
	local out = {}
	for _, item in chainItems(SETS[id], seedRng(id, seed)) do
		table.insert(out, item.name)
	end
	return out
end

function Patterns.Build(setId: string?, seed: number, duration: number?): Timeline
	local id = Patterns.Resolve(setId)
	local set = SETS[id]
	local cfg = (Config :: any).VerdictBox
	local D = duration or (cfg and cfg.Duration) or 7
	D = math.max(D, 2)
	local rng = seedRng(id, seed)
	local items = chainItems(set, rng)
	local introEnd = math.min(Patterns.INTRO, D * 0.2)
	local tl: Timeline = {
		set = id,
		theme = set.theme,
		seed = seed,
		duration = D,
		introEnd = introEnd,
		line = set.lines[rng:Integer(1, #set.lines)],
		modes = { { t = 0, mode = "Intro", gravity = "Down", slam = false, w = DIALOG[1], h = DIALOG[2] } },
		bullets = {},
		effects = {},
		segments = {},
	}
	local ctx: Ctx = { rng = rng, tl = tl, set = set }

	-- plan: mode / box / gravity of every segment (blue gravity: Down first, then any other wall)
	type Plan = { gen: Gen, item: Item, gravity: string }
	local plans: { Plan } = {}
	local lastBlue: string? = nil
	for _, item in items do
		local gen = GEN[item.name]
		assert(gen, "Patterns: unknown generator " .. item.name)
		local gravity = "Down"
		if gen.mode == "Blue" then
			if gen.gravity == "Auto" then
				local walls = { "Down", "Left", "Right", "Up" }
				local idx = table.find(walls, lastBlue or "")
				if idx then
					table.remove(walls, idx)
				else
					table.insert(walls, "Down") -- first slam: down is the most likely
				end
				gravity = walls[rng:Integer(1, #walls)]
			end
			lastBlue = gravity
		end
		table.insert(plans, { gen = gen, item = item, gravity = gravity })
	end

	-- durations: proportional to `nominal`, but never below a generator's `min` (then renormalised to fill)
	local avail = D - introEnd - Patterns.END_PAD
	local durs: { number } = {}
	local fixed: { [number]: boolean } = {}
	for _ = 1, #plans + 1 do
		local freeNominal, fixedSum = 0, 0
		for i, p in plans do
			if fixed[i] then
				fixedSum += durs[i]
			else
				freeNominal += p.gen.nominal
			end
		end
		local scale = if freeNominal > 0 then (avail - fixedSum) / freeNominal else 0
		local changed = false
		for i, p in plans do
			if not fixed[i] then
				durs[i] = p.gen.nominal * scale
				if durs[i] < p.gen.min then
					durs[i] = p.gen.min
					fixed[i] = true
					changed = true
				end
			end
		end
		if not changed then
			break
		end
	end
	local sum = 0
	for _, d in durs do
		sum += d
	end
	for i in durs do
		durs[i] *= avail / sum
	end
	local n = #plans
	local t = introEnd
	local prevMode, prevGravity, prevBox = "", "", nil :: { number }?
	for i, p in plans do
		local gen = p.gen
		local dur = durs[i]
		local nextPlan = plans[i + 1]
		local same = nextPlan ~= nil and gen.mode == "Red" and nextPlan.gen.mode == "Red" and nextPlan.gen.box == gen.box
		local t1 = if i == n then D - Patterns.END_PAD else t + dur
		local seg: Seg = {
			name = p.item.name,
			t0 = t,
			t1 = t1,
			dur = t1 - t,
			hardEnd = if i == n then D else (if same then t1 + LINGER else t1),
			k = if n > 1 then (i - 1) / (n - 1) else 1,
			w = gen.box[1],
			h = gen.box[2],
			mode = gen.mode,
			gravity = p.gravity,
			spd = set.speed,
			warn = set.warn,
			params = p.item.params,
		}
		-- soul mode entry (blue: slam whenever the gravity or the box changes, or after red)
		local slam = gen.mode == "Blue" and (prevMode ~= "Blue" or prevGravity ~= p.gravity or prevBox ~= gen.box)
		if not (gen.mode == prevMode and gen.box == prevBox and (gen.mode ~= "Blue" or p.gravity == prevGravity)) then
			setMode(ctx, t, gen.mode, p.gravity, slam, gen.box[1], gen.box[2])
		end
		gen.fn(ctx, seg)
		table.insert(tl.segments, { name = seg.name, t0 = seg.t0, t1 = seg.t1, mode = seg.mode, k = seg.k })
		-- the last mode entry (a generator may have changed gravity mid-segment)
		local last = tl.modes[#tl.modes]
		prevMode, prevGravity, prevBox = gen.mode, last.gravity, gen.box
		t = t1
	end
	local final = tl.modes[#tl.modes]
	table.insert(tl.modes, { t = D, mode = "End", gravity = final.gravity, slam = false, w = final.w, h = final.h })
	-- generators append mid-segment entries in time order, but keep the list sorted defensively (stable)
	for i = 2, #tl.modes do
		local m = tl.modes[i]
		local j = i - 1
		while j >= 1 and tl.modes[j].t > m.t do
			tl.modes[j + 1] = tl.modes[j]
			j -= 1
		end
		tl.modes[j + 1] = m
	end
	return tl
end

return Patterns
