--!strict
-- VerdictBox/Sim: deterministic 2D bullet-hell simulation of the Verdict Box (SPEC §11). [Lune-safe]
--
-- Units: Undertale screen pixels (640x480 logical screen) in BOX-CENTRED coordinates: (0, 0) is the centre of the
-- battle box, +x right, +y DOWN (screen convention); angles in radians, clockwise on screen (= GUI Rotation).
-- Time: seconds since the box opened (BoxStart t0).
-- A Timeline (built by VerdictBox/Patterns from a seed) is pure data: soul modes (Red / Blue + gravity + box size),
-- bullets with ANALYTIC motion (the pose of a bullet at any t is a pure function), screen effects and the intro
-- line. Only the SOUL is integrated (input -> movement, blue-soul gravity, one-way platforms) on a fixed 1/60 s
-- tick and tested against the bullet poses: the same timeline + the same input per tick always gives identical
-- results (victim client), and watchers can draw the very same bullets at any t with a relayed soul position.
--
-- Rules (docs/research/undertale.md §4): White always hurts; Blue (#14A9FF) only while the SOUL moves; Orange
-- (#FFA040) only while it stands still. "Moving" = the soul's OWN displacement this tick (platform carry excluded).
-- Fairness: the SOUL hurts with a circle of radius Tuning.HitRadius (4.5 px) inside its 16x16 sprite; bones hurt
-- with their shaft only (Tuning.BoneShaft of the thickness, ends trimmed by Tuning.BoneTrim); beams hurt with 75 %
-- of their width and only while >= 80 % opaque; stabs show a red warning outline before they rise; after a hit the
-- soul is invincible for hitInterval (Config.VerdictBox.MinHitInterval) and blinks.
-- Blue soul (gravity toward any wall): side speed 150, jump 180 (release = upward speed capped at 30), gravity by
-- vertical speed (rise 180 / slowing 450 / apex 180 / fall 540 px/s^2), max fall 360, slams at 750.
--
-- API
--   Sim.TICK, Sim.Tuning, Sim.BOX ({w, h} named box sizes), Sim.Palette (rule colours)
--   Sim.Bullet(kind, spec) -> Bullet           record with every field defaulted; unknown fields error (Patterns)
--   Sim.new(timeline, opts?) -> State          opts: { hitInterval: number? }
--   Sim.Step(state, dt, input?) -> number      advance by dt (fixed 1/60 ticks inside); returns hits gained
--   Sim.AdvanceTo(state, t, input?) -> number  step until state.t reaches t (work capped; far behind = skip ahead)
--   Sim.ModeAt(timeline, t) -> (Mode, index)   active soul mode ("Intro" before the first attack, "End" after)
--   Sim.BoxAt(timeline, t) -> (w, h)           animated inner box size (Tuning.ResizeTime tween)
--   Sim.NewPose() -> Pose ; Sim.Pose(bullet, t, out?) -> Pose?   geometry + render info at t (nil = inactive)
--   Sim.Overlap(pose, x, y, r) -> boolean      circle vs the pose's hurt shape
--   Sim.ColorHurts(color, moving) -> boolean
--   Sim.HitAt(timeline, t, x, y, moving, r?) -> Bullet?   first bullet that would hurt a soul at (x, y)
--   Sim.EffectLevel(timeline, kind, t) -> number          0..1 ("Dark", "Flash", "Shake")
--   Sim.AutoSoul(timeline, t) -> (x, y)        plausible soul path (bot victims / watchers without a relay)
--   Sim.IntroChars(timeline, t, total) -> number   typewriter progress of the opening line (Tuning.TextSpeed)
--   Sim.SoulAngle(gravity) -> number           heart rotation in degrees (tip points along gravity)
--   Sim.Clamp(timeline, t, x, y) -> (x, y)     keep a point inside the box (relay validation, watchers)
-- State: t (sim seconds), ticks, soul {x, y, vFall, mode, gravity, grounded, slamming, moving, iframesUntil,
--   active, platform}, hits, events (append-only {kind = "Hit"|"Slam"|"Mode"|"Jump", t, color, x, y, n}).

local Config = require(script.Parent.Parent.Config)

local Sim = {}

Sim.TICK = 1 / 60

Sim.Tuning = {
	SoulSpeed = 150, -- px/s: red soul, blue-soul side movement
	SlowMult = 0.5, -- hold Shift / X: precise movement
	SoulHalf = 8, -- half the 16x16 sprite: the sprite always stays inside the box border
	HitRadius = 4.5, -- the SOUL's hurt circle (the heart's core, not the whole sprite)
	JumpSpeed = 180,
	JumpCut = 30, -- releasing jump caps the upward speed (variable jump height)
	GravRiseFast = 180, -- while vFall <= RiseFastBelow (floaty start of the jump)
	RiseFastBelow = -120,
	GravRiseSlow = 450, -- while vFall <= RiseSlowBelow
	RiseSlowBelow = -30,
	GravApex = 180, -- while vFall <= ApexBelow (hang time)
	ApexBelow = 15,
	GravFall = 540, -- falling
	MaxFall = 360,
	SlamSpeed = 750,
	MoveEpsilon = 0.15, -- px per tick: less = "still" (orange hurts), more = "moving" (blue hurts)
	BoneShaft = 0.6, -- fraction of a bone's thickness that hurts
	BoneTrim = 2, -- px trimmed from each bone end
	StabTrim = 2, -- px trimmed from a stab's tip
	BeamHurt = 0.75, -- fraction of the beam width that hurts
	BeamHurtAlpha = 0.8, -- beams stop hurting below this opacity
	BeamBase = 35, -- beam width at blaster scale 1
	BeamLength = 1000,
	BlasterMuzzle = 18, -- skull centre -> muzzle (x scale)
	StarHurt = 0.36, -- hurting radius of a star-bone / its size
	PlatformThick = 8,
	ResizeTime = 0.2, -- box resize tween
	TextSpeed = 32, -- typewriter chars per second
	TextDelay = 0.3, -- the opening line starts typing after the box opened
	MaxCatchUpTicks = 45, -- AdvanceTo work cap per call (0.75 s of simulation)
}
local T = Sim.Tuning
local TICK = Sim.TICK

Sim.BOX = {
	Square = { 165, 165 }, -- red / free mode (Sans square)
	Wide = { 375, 140 }, -- blue-soul wide box
	Dialog = { 300, 120 }, -- the opening line
}

Sim.Palette = {
	White = Color3.fromRGB(255, 255, 255),
	Blue = Color3.fromRGB(20, 169, 255), -- #14A9FF
	Orange = Color3.fromRGB(255, 160, 64), -- #FFA040
	SoulRed = Color3.fromRGB(255, 0, 0),
	SoulBlue = Color3.fromRGB(0, 60, 255), -- #003CFF
	Warn = Color3.fromRGB(255, 0, 0),
	PlatformEdge = Color3.fromRGB(46, 95, 46), -- #2E5F2E
}

export type Bullet = {
	id: number,
	kind: string, -- "Bone" | "Stab" | "Blaster" | "Platform" | "Star" | "Rift"
	t0: number,
	t1: number,
	color: string, -- "White" | "Blue" | "Orange"
	style: string, -- visual variant: "" | "Chain" | "Glow" | "Rift" | "Big" ...
	-- Bone / Star / Rift / Platform: linear motion (or polar when polar = true)
	x: number,
	y: number,
	vx: number,
	vy: number,
	ax: number,
	ay: number,
	len: number,
	thick: number,
	angle: number,
	spin: number,
	polar: boolean,
	cx: number,
	cy: number,
	r0: number,
	vr: number,
	a0: number,
	va: number,
	rmin: number,
	-- Stab: rises from `wall` over [a, b] (along the wall), box size bw x bh at spawn
	wall: string,
	a: number,
	b: number,
	height: number,
	warn: number,
	rise: number,
	hold: number,
	fall: number,
	bw: number,
	bh: number,
	-- Blaster: final skull centre (x, y), beam direction `angle`; flies in from (x + ex, y + ey)
	scale: number,
	ex: number,
	ey: number,
	appear: number,
	charge: number,
	fire: number,
	fade: number,
	turn: number,
	-- Platform: width w, ping-pong between minX and maxX (when minX < maxX)
	w: number,
	minX: number,
	maxX: number,
}

export type Mode = { t: number, mode: string, gravity: string, slam: boolean, w: number, h: number }
export type Effect = { kind: string, t0: number, t1: number, level: number }
export type Segment = { name: string, t0: number, t1: number, mode: string, k: number }
export type Timeline = {
	set: string,
	theme: string,
	seed: number,
	duration: number,
	introEnd: number,
	line: string, -- Strings key of the opening line
	modes: { Mode },
	bullets: { Bullet },
	effects: { Effect },
	segments: { Segment },
}

export type Pose = {
	kind: string,
	color: string,
	style: string,
	id: number,
	time: number, -- t - t0
	phase: string, -- "Move" | "Warn" | "Rise" | "Hold" | "Fall" | "Appear" | "Charge" | "Fire" | "Fade" | "Open" | "Close"
	x: number,
	y: number,
	angle: number,
	len: number,
	thick: number,
	alpha: number,
	open: number, -- blaster jaw / rift opening 0..1
	beamX: number, -- muzzle
	beamY: number,
	beamW: number,
	beamAlpha: number,
	wall: string,
	height: number, -- stab: current height
	fx: number, -- stab: full-height rect (warning outline), centre + half extents
	fy: number,
	fw: number,
	fh: number,
	hurt: boolean,
	shape: string, -- "Rect" | "Circle" | "None"
	hx: number,
	hy: number,
	hw: number, -- half extents (Circle: hw = radius)
	hh: number,
	hangle: number,
}

export type Soul = {
	x: number,
	y: number,
	vFall: number,
	mode: string,
	gravity: string,
	grounded: boolean,
	slamming: boolean,
	moving: boolean,
	jumpHeld: boolean,
	iframesUntil: number,
	active: boolean,
	platform: Bullet?,
}

export type Event = { kind: string, t: number, color: string, x: number, y: number, n: number }

export type State = {
	timeline: Timeline,
	t: number,
	ticks: number,
	acc: number,
	soul: Soul,
	hits: number,
	events: { Event },
	modeIndex: number,
	hitInterval: number,
}

export type Input = { x: number?, y: number?, jump: boolean?, slow: boolean? }

local DEFAULTS: { [string]: any } = {
	id = 0,
	kind = "Bone",
	t0 = 0,
	t1 = 0,
	color = "White",
	style = "",
	x = 0,
	y = 0,
	vx = 0,
	vy = 0,
	ax = 0,
	ay = 0,
	len = 24,
	thick = 10,
	angle = 0,
	spin = 0,
	polar = false,
	cx = 0,
	cy = 0,
	r0 = 0,
	vr = 0,
	a0 = 0,
	va = 0,
	rmin = -1,
	wall = "Bottom",
	a = 0,
	b = 0,
	height = 30,
	warn = 0.4,
	rise = 0.06,
	hold = 0.3,
	fall = 0.12,
	bw = 165,
	bh = 165,
	scale = 1,
	ex = 0,
	ey = 0,
	appear = 0.22,
	charge = 0.4,
	fire = 0.27,
	fade = 0.25,
	turn = 0,
	w = 60,
	minX = 0,
	maxX = 0,
}

local function clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function easeOutCubic(t: number): number
	local u = 1 - t
	return 1 - u * u * u
end

-- Bullet record with every field present. Stabs / blasters get t1 from their phases unless t1 is given larger.
function Sim.Bullet(kind: string, spec: { [string]: any }): Bullet
	local b: { [string]: any } = table.clone(DEFAULTS)
	b.kind = kind
	for key, value in spec do
		if DEFAULTS[key] == nil then
			error("Sim.Bullet: unknown field " .. tostring(key))
		end
		b[key] = value
	end
	if kind == "Stab" then
		b.t1 = b.t0 + b.warn + b.rise + b.hold + b.fall
	elseif kind == "Blaster" then
		b.t1 = b.t0 + b.appear + b.charge + b.fire + b.fade
	end
	return (b :: any) :: Bullet
end

---------------------------------------------------------------------------------------------------
-- Timeline queries

function Sim.ModeAt(tl: Timeline, t: number): (Mode, number)
	local modes = tl.modes
	for i = #modes, 1, -1 do
		if modes[i].t <= t then
			return modes[i], i
		end
	end
	return modes[1], 1
end

function Sim.BoxAt(tl: Timeline, t: number): (number, number)
	local m, i = Sim.ModeAt(tl, t)
	if i > 1 then
		local a = (t - m.t) / T.ResizeTime
		if a < 1 then
			local prev = tl.modes[i - 1]
			local e = easeOutCubic(clamp(a, 0, 1))
			return lerp(prev.w, m.w, e), lerp(prev.h, m.h, e)
		end
	end
	return m.w, m.h
end

function Sim.Clamp(tl: Timeline, t: number, x: number, y: number): (number, number)
	local w, h = Sim.BoxAt(tl, t)
	local hx, hy = math.max(w / 2 - T.SoulHalf, 0), math.max(h / 2 - T.SoulHalf, 0)
	return clamp(x, -hx, hx), clamp(y, -hy, hy)
end

function Sim.EffectLevel(tl: Timeline, kind: string, t: number): number
	local best = 0
	for _, e in tl.effects do
		if e.kind == kind and t >= e.t0 and t <= e.t1 then
			local edge = math.min(t - e.t0, e.t1 - t)
			local level = e.level * clamp(edge / 0.06, 0, 1)
			if level > best then
				best = level
			end
		end
	end
	return best
end

function Sim.IntroChars(tl: Timeline, t: number, total: number): number
	if t >= tl.introEnd then
		return total
	end
	return clamp(math.floor((t - T.TextDelay) * T.TextSpeed), 0, total)
end

function Sim.SoulAngle(gravity: string): number
	if gravity == "Left" then
		return 90
	elseif gravity == "Up" then
		return 180
	elseif gravity == "Right" then
		return -90
	end
	return 0
end

function Sim.ColorHurts(color: string, moving: boolean): boolean
	if color == "Blue" then
		return moving
	elseif color == "Orange" then
		return not moving
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- Poses

function Sim.NewPose(): Pose
	return {
		kind = "",
		color = "White",
		style = "",
		id = 0,
		time = 0,
		phase = "Move",
		x = 0,
		y = 0,
		angle = 0,
		len = 0,
		thick = 0,
		alpha = 1,
		open = 0,
		beamX = 0,
		beamY = 0,
		beamW = 0,
		beamAlpha = 0,
		wall = "",
		height = 0,
		fx = 0,
		fy = 0,
		fw = 0,
		fh = 0,
		hurt = false,
		shape = "None",
		hx = 0,
		hy = 0,
		hw = 0,
		hh = 0,
		hangle = 0,
	}
end

local function pingPong(pos: number, lo: number, hi: number): number
	local span = hi - lo
	if span <= 0 then
		return pos
	end
	local u = (pos - lo) % (2 * span)
	if u > span then
		u = 2 * span - u
	end
	return lo + u
end

-- Linear (or polar) motion of bones / stars / rifts. Returns false when a polar bullet collapsed below rmin.
local function motion(b: Bullet, dt: number, out: Pose): boolean
	if b.polar then
		local r = b.r0 + b.vr * dt
		if b.rmin >= 0 and r < b.rmin then
			return false
		end
		local a = b.a0 + b.va * dt
		out.x = b.cx + r * math.cos(a)
		out.y = b.cy + r * math.sin(a)
	else
		out.x = b.x + b.vx * dt + 0.5 * b.ax * dt * dt
		out.y = b.y + b.vy * dt + 0.5 * b.ay * dt * dt
	end
	out.angle = b.angle + b.spin * dt
	return true
end

-- Stab rect for a height h: centre + half extents (box-centred).
local function stabRect(b: Bullet, h: number): (number, number, number, number)
	local wall = b.wall
	local mid, half = (b.a + b.b) / 2, math.abs(b.b - b.a) / 2
	if wall == "Bottom" then
		return mid, b.bh / 2 - h / 2, half, h / 2
	elseif wall == "Top" then
		return mid, -b.bh / 2 + h / 2, half, h / 2
	elseif wall == "Left" then
		return -b.bw / 2 + h / 2, mid, h / 2, half
	end
	return b.bw / 2 - h / 2, mid, h / 2, half
end

local function poseStab(b: Bullet, dt: number, out: Pose)
	local H = b.height
	local cur, phase
	if dt < b.warn then
		phase, cur = "Warn", 0
	elseif dt < b.warn + b.rise then
		phase, cur = "Rise", H * (dt - b.warn) / math.max(b.rise, 1e-3)
	elseif dt < b.warn + b.rise + b.hold then
		phase, cur = "Hold", H
	else
		phase = "Fall"
		cur = H * clamp(1 - (dt - b.warn - b.rise - b.hold) / math.max(b.fall, 1e-3), 0, 1)
	end
	out.phase = phase
	out.wall = b.wall
	out.height = cur
	out.fx, out.fy, out.fw, out.fh = stabRect(b, H)
	local cx, cy, hw, hh = stabRect(b, cur)
	out.x, out.y = cx, cy
	out.len = math.abs(b.b - b.a)
	out.thick = b.thick
	local tip = math.max(cur - T.StabTrim, 0)
	out.hurt = phase ~= "Warn" and tip > 0.5
	out.shape = "Rect"
	out.hx, out.hy, out.hw, out.hh = stabRect(b, tip)
	out.hangle = 0
	if b.wall == "Left" or b.wall == "Right" then
		out.hh = math.max(hh - 1, 0)
	else
		out.hw = math.max(hw - 1, 0)
	end
end

local function poseBlaster(b: Bullet, dt: number, out: Pose)
	local tA = b.appear
	local tC = tA + b.charge
	local tF = tC + b.fire
	local s = b.scale
	local dirX, dirY = math.cos(b.angle), math.sin(b.angle)
	local x, y, angle = b.x, b.y, b.angle
	local base, beamAlpha, alpha, open = 0, 0, 1, 0
	local phase
	if dt < tA then
		phase = "Appear"
		local p = easeOutCubic(clamp(dt / math.max(tA, 1e-3), 0, 1))
		x, y = b.x + b.ex * (1 - p), b.y + b.ey * (1 - p)
		angle = b.angle + b.turn * (1 - p)
		alpha = clamp(dt / 0.08, 0, 1)
	elseif dt < tC then
		phase = "Charge"
		local p = clamp((dt - tA) / math.max(b.charge, 1e-3), 0, 1)
		open = 0.3 * p * p * p
	else
		local since = dt - tC
		local recoil = math.min(450 * since * since, 60 * s)
		x, y = b.x - dirX * recoil, b.y - dirY * recoil
		open = 1
		if dt < tF then
			phase = "Fire"
			base = T.BeamBase * s * clamp(since / 0.13, 0.25, 1)
			beamAlpha = 1
		else
			phase = "Fade"
			local frames = (dt - tF) * 30
			base = T.BeamBase * s * math.pow(0.8, frames)
			beamAlpha = clamp(1 - 0.1 * frames, 0, 1)
			alpha = clamp(1 - (dt - tF) / math.max(b.fade, 1e-3), 0, 1)
		end
	end
	out.phase = phase
	out.x, out.y, out.angle = x, y, angle
	out.len = 44 * s
	out.thick = 40 * s
	out.alpha = alpha
	out.open = open
	local mx, my = x + math.cos(angle) * T.BlasterMuzzle * s, y + math.sin(angle) * T.BlasterMuzzle * s
	out.beamX, out.beamY = mx, my
	out.beamW = base
	out.beamAlpha = beamAlpha
	out.hurt = base > 0 and beamAlpha >= T.BeamHurtAlpha
	out.shape = "Rect"
	local half = T.BeamLength / 2
	out.hx, out.hy = mx + dirX * half, my + dirY * half
	out.hw, out.hh = half, base * T.BeamHurt / 2
	out.hangle = b.angle
end

-- Pose of `b` at time t (absolute sim seconds) into `out` (or a new Pose). nil while the bullet is inactive.
function Sim.Pose(b: Bullet, t: number, out: Pose?): Pose?
	if t < b.t0 or t > b.t1 then
		return nil
	end
	local p = out or Sim.NewPose()
	local dt = t - b.t0
	p.kind, p.color, p.style, p.id, p.time = b.kind, b.color, b.style, b.id, dt
	p.alpha, p.open, p.beamW, p.beamAlpha = 1, 0, 0, 0
	p.hurt, p.shape, p.hangle = false, "None", 0
	local kind = b.kind
	if kind == "Bone" or kind == "Star" then
		if not motion(b, dt, p) then
			return nil
		end
		p.phase = "Move"
		p.len, p.thick = b.len, b.thick
		p.hurt = true
		p.hx, p.hy = p.x, p.y
		if kind == "Bone" then
			p.shape = "Rect"
			p.hw = b.thick * T.BoneShaft / 2
			p.hh = math.max(b.len / 2 - T.BoneTrim, 0)
			p.hangle = p.angle
		else
			p.shape = "Circle"
			p.hw = b.len * T.StarHurt
			p.hh = p.hw
		end
	elseif kind == "Stab" then
		poseStab(b, dt, p)
	elseif kind == "Blaster" then
		poseBlaster(b, dt, p)
	elseif kind == "Platform" then
		p.phase = "Move"
		local x = b.x + b.vx * dt
		if b.minX < b.maxX then
			x = pingPong(x, b.minX, b.maxX)
		end
		p.x, p.y, p.angle = x, b.y, 0
		p.len, p.thick = b.w, T.PlatformThick
	elseif kind == "Rift" then
		motion(b, dt, p)
		p.len, p.thick = b.len, b.thick
		local life = b.t1 - b.t0
		local open = math.min(clamp(dt / 0.15, 0, 1), clamp((life - dt) / 0.2, 0, 1))
		p.open = easeOutCubic(open)
		p.phase = if dt < 0.15 then "Open" elseif life - dt < 0.2 then "Close" else "Hold"
	else
		return nil
	end
	return p
end

function Sim.Overlap(p: Pose, x: number, y: number, r: number): boolean
	if not p.hurt then
		return false
	end
	if p.shape == "Circle" then
		local dx, dy = x - p.hx, y - p.hy
		local rr = r + p.hw
		return dx * dx + dy * dy <= rr * rr
	elseif p.shape == "Rect" then
		local dx, dy = x - p.hx, y - p.hy
		local lx, ly = dx, dy
		if p.hangle ~= 0 then
			local c, s = math.cos(p.hangle), math.sin(p.hangle)
			lx = dx * c + dy * s
			ly = -dx * s + dy * c
		end
		local qx = math.max(math.abs(lx) - p.hw, 0)
		local qy = math.max(math.abs(ly) - p.hh, 0)
		return qx * qx + qy * qy <= r * r
	end
	return false
end

local scratch = Sim.NewPose()

function Sim.HitAt(tl: Timeline, t: number, x: number, y: number, moving: boolean, r: number?): Bullet?
	local radius = r or T.HitRadius
	for _, b in tl.bullets do
		if t >= b.t0 and t <= b.t1 and Sim.ColorHurts(b.color, moving) then
			local p = Sim.Pose(b, t, scratch)
			if p and Sim.Overlap(p, x, y, radius) then
				return b
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Soul simulation

function Sim.new(tl: Timeline, opts: { hitInterval: number? }?): State
	local cfg = (Config :: any).VerdictBox
	local interval = (opts and opts.hitInterval) or (cfg and cfg.MinHitInterval) or 0.45
	return {
		timeline = tl,
		t = 0,
		ticks = 0,
		acc = 0,
		soul = {
			x = 0,
			y = 0,
			vFall = 0,
			mode = "Intro",
			gravity = "Down",
			grounded = false,
			slamming = false,
			moving = false,
			jumpHeld = false,
			iframesUntil = 0,
			active = false,
			platform = nil,
		},
		hits = 0,
		events = {},
		modeIndex = 0,
		hitInterval = interval,
	}
end

local function pushEvent(st: State, kind: string, color: string?, n: number?)
	table.insert(st.events, {
		kind = kind,
		t = st.t,
		color = color or "",
		x = st.soul.x,
		y = st.soul.y,
		n = n or 0,
	})
end

local function enterMode(st: State, m: Mode)
	local soul = st.soul
	local wasMode, wasGravity = soul.mode, soul.gravity
	soul.mode = m.mode
	soul.gravity = m.gravity
	if m.mode == "Red" or m.mode == "Blue" then
		if not soul.active then
			soul.active = true
			soul.x, soul.y = 0, 0
		end
		local keep = m.mode == "Blue" and wasMode == "Blue" and wasGravity == m.gravity and not m.slam
		if not keep then
			soul.vFall = 0
			soul.grounded = false
			soul.platform = nil
			soul.slamming = false
			soul.jumpHeld = false
		end
		if m.mode == "Blue" and m.slam then
			soul.slamming = true
			soul.vFall = T.SlamSpeed
		end
	else
		soul.active = false
		soul.platform = nil
	end
	pushEvent(st, "Mode", m.mode)
end

local function axisInput(v: number?): number
	if type(v) ~= "number" or v ~= v then
		return 0
	end
	return clamp(v, -1, 1)
end

local platformPose = Sim.NewPose()

-- Blue soul: gravity toward one wall. (s, f) = (side, fall) coordinates for that gravity.
local function blueTick(st: State, input: Input, w: number, h: number, ix: number, iy: number): number
	local soul = st.soul
	local tl = st.timeline
	local t = st.t
	local g = soul.gravity
	local half = T.SoulHalf
	local s, f, sideIn, jumpIn, sideLim, floorF
	if g == "Up" then
		s, f, sideIn, jumpIn = soul.x, -soul.y, ix, iy > 0.5
		sideLim, floorF = w / 2 - half, h / 2 - half
	elseif g == "Left" then
		s, f, sideIn, jumpIn = soul.y, -soul.x, iy, ix > 0.5
		sideLim, floorF = h / 2 - half, w / 2 - half
	elseif g == "Right" then
		s, f, sideIn, jumpIn = soul.y, soul.x, iy, ix < -0.5
		sideLim, floorF = h / 2 - half, w / 2 - half
	else
		s, f, sideIn, jumpIn = soul.x, soul.y, ix, iy < -0.5
		sideLim, floorF = w / 2 - half, h / 2 - half
	end
	jumpIn = jumpIn or input.jump == true
	sideLim, floorF = math.max(sideLim, 0), math.max(floorF, 0)
	local speed = T.SoulSpeed * (if input.slow then T.SlowMult else 1)
	local s0, f0 = s, f
	s += sideIn * speed * TICK
	local carry = 0

	-- riding a platform (gravity Down only)
	local plat = soul.platform
	if plat and soul.grounded then
		local now = Sim.Pose(plat, t, platformPose)
		if now == nil then
			soul.platform = nil
			soul.grounded = false
		else
			local px, py, pw = now.x, now.y, now.len
			local before = Sim.Pose(plat, t - TICK, platformPose)
			if before then
				carry = px - before.x
			end
			s += carry
			if math.abs(s - px) > pw / 2 + 3 then
				soul.platform = nil
				soul.grounded = false
			else
				f = py - T.PlatformThick / 2 - half
			end
		end
	end

	if soul.grounded and jumpIn and not soul.slamming then
		soul.vFall = -T.JumpSpeed
		soul.grounded = false
		soul.platform = nil
		soul.jumpHeld = true
		pushEvent(st, "Jump")
	end
	if not soul.grounded then
		if soul.slamming then
			soul.vFall = T.SlamSpeed
		else
			if not jumpIn then
				soul.jumpHeld = false
			end
			if not soul.jumpHeld and soul.vFall < -T.JumpCut then
				soul.vFall = -T.JumpCut
			end
			local v = soul.vFall
			local a = if v <= T.RiseFastBelow
				then T.GravRiseFast
				elseif v <= T.RiseSlowBelow then T.GravRiseSlow
				elseif v <= T.ApexBelow then T.GravApex
				else T.GravFall
			soul.vFall = math.min(v + a * TICK, T.MaxFall)
		end
		local nf = f + soul.vFall * TICK
		if g == "Down" and soul.vFall >= 0 then
			for _, b in tl.bullets do
				if b.kind == "Platform" and t >= b.t0 and t <= b.t1 then
					local p = Sim.Pose(b, t, platformPose)
					if p then
						local top = p.y - T.PlatformThick / 2
						if f + half <= top + 0.5 and nf + half >= top and math.abs(s - p.x) <= p.len / 2 + 3 then
							nf = top - half
							soul.grounded = true
							soul.platform = b
							soul.vFall = 0
							soul.slamming = false
							break
						end
					end
				end
			end
		end
		if nf >= floorF then
			nf = floorF
			if soul.slamming then
				soul.slamming = false
				pushEvent(st, "Slam", g)
			end
			soul.vFall = 0
			soul.grounded = true
			soul.platform = nil
		elseif nf <= -floorF then
			nf = -floorF
			soul.vFall = math.max(soul.vFall, 0)
		end
		f = nf
	elseif soul.platform == nil then
		f = floorF -- standing on the floor (follows a resizing box)
	end
	s = clamp(s, -sideLim, sideLim)
	f = clamp(f, -floorF, floorF)
	if g == "Up" then
		soul.x, soul.y = s, -f
	elseif g == "Left" then
		soul.x, soul.y = -f, s
	elseif g == "Right" then
		soul.x, soul.y = f, s
	else
		soul.x, soul.y = s, f
	end
	local ds, df = s - s0 - carry, f - f0
	return ds * ds + df * df
end

local function tick(st: State, input: Input): number
	st.ticks += 1
	st.t = st.ticks * TICK
	local tl = st.timeline
	local t = st.t
	local m, mi = Sim.ModeAt(tl, t)
	if mi ~= st.modeIndex then
		st.modeIndex = mi
		enterMode(st, m)
	end
	local soul = st.soul
	if not soul.active or t >= tl.duration then
		soul.moving = false
		return 0
	end
	local w, h = Sim.BoxAt(tl, t)
	local ix, iy = axisInput(input.x), axisInput(input.y)
	local mag = math.sqrt(ix * ix + iy * iy)
	if mag > 1 then
		ix, iy = ix / mag, iy / mag
	end
	local moved2
	if soul.mode == "Blue" then
		moved2 = blueTick(st, input, w, h, ix, iy)
	else
		local speed = T.SoulSpeed * (if input.slow then T.SlowMult else 1)
		local x0, y0 = soul.x, soul.y
		local hx, hy = math.max(w / 2 - T.SoulHalf, 0), math.max(h / 2 - T.SoulHalf, 0)
		soul.x = clamp(soul.x + ix * speed * TICK, -hx, hx)
		soul.y = clamp(soul.y + iy * speed * TICK, -hy, hy)
		local dx, dy = soul.x - x0, soul.y - y0
		moved2 = dx * dx + dy * dy
	end
	soul.moving = moved2 > T.MoveEpsilon * T.MoveEpsilon
	if t >= soul.iframesUntil then
		local b = Sim.HitAt(tl, t, soul.x, soul.y, soul.moving, T.HitRadius)
		if b then
			st.hits += 1
			soul.iframesUntil = t + st.hitInterval
			pushEvent(st, "Hit", b.color, st.hits)
			return 1
		end
	end
	return 0
end

local EMPTY_INPUT: Input = {}

-- Advance by dt seconds of real time; inputs apply to every tick inside. Returns the hits gained.
function Sim.Step(st: State, dt: number, input: Input?): number
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
		return 0
	end
	st.acc += dt
	local gained = 0
	local inp = input or EMPTY_INPUT
	local n = 0
	while st.acc >= TICK - 1e-9 do
		st.acc -= TICK
		gained += tick(st, inp)
		n += 1
		if n >= T.MaxCatchUpTicks then
			st.acc = 0
			break
		end
	end
	return gained
end

-- Advance until state.t reaches `target` (absolute sim seconds). If the client fell far behind (hitch), the
-- missing time is skipped without simulating (the soul just stands still), so the box never drifts from the
-- server clock.
function Sim.AdvanceTo(st: State, target: number, input: Input?): number
	local want = math.floor(target / TICK + 1e-6)
	local behind = want - st.ticks
	if behind <= 0 then
		return 0
	end
	if behind > T.MaxCatchUpTicks then
		st.ticks = want - T.MaxCatchUpTicks
		st.t = st.ticks * TICK
		behind = T.MaxCatchUpTicks
	end
	local gained = 0
	local inp = input or EMPTY_INPUT
	for _ = 1, behind do
		gained += tick(st, inp)
	end
	st.acc = 0
	return gained
end

-- A plausible, smooth soul path for watchers when no relay arrives (bot victims): wanders inside the box, rests
-- on the floor (with small hops) in blue mode.
function Sim.AutoSoul(tl: Timeline, t: number): (number, number)
	local m = Sim.ModeAt(tl, t)
	local w, h = Sim.BoxAt(tl, t)
	local ph = (tl.seed % 997) * 0.37
	local hx, hy = math.max(w / 2 - T.SoulHalf - 6, 0), math.max(h / 2 - T.SoulHalf - 6, 0)
	if m.mode == "Blue" then
		local side = math.sin(t * 1.6 + ph) * 0.65 + math.sin(t * 3.7 + ph * 2) * 0.25
		local hop = math.max(0, math.sin(t * 4.2 + ph)) * 34
		local g = m.gravity
		if g == "Up" then
			return side * hx, -(h / 2 - T.SoulHalf) + hop
		elseif g == "Left" then
			return -(w / 2 - T.SoulHalf) + hop, side * hy
		elseif g == "Right" then
			return (w / 2 - T.SoulHalf) - hop, side * hy
		end
		return side * hx, (h / 2 - T.SoulHalf) - hop
	end
	local x = math.sin(t * 1.7 + ph) * 0.6 + math.sin(t * 3.1 + ph * 2) * 0.25
	local y = math.cos(t * 1.3 + ph) * 0.55 + math.sin(t * 2.6 + ph * 3) * 0.25
	return clamp(x, -1, 1) * hx, clamp(y, -1, 1) * hy
end

return Sim
