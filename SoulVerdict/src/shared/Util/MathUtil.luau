--!strict
-- MathUtil: scalar / vector / CFrame helpers and Roblox-style easing curves. Lune-safe (pure math;
-- only Vector3/CFrame datatypes, no services). All angles are RADIANS unless a name says "Deg".
--
-- Scalars:
--   lerp(a, b, t)                      inverseLerp(a, b, v) -> t (0 when a == b)
--   clamp(x, lo, hi)                   remap(x, inMin, inMax, outMin, outMax, clampOutput?)
--   smoothstep(e0, e1, x)              smootherstep(e0, e1, x)
--   round(x, step?)                    nearest multiple of step (default 1); halves round UP (+inf)
--   sign(x) -> -1|0|1                  approach(current, target, maxDelta)
--   wrapAngle(a) -> (-pi, pi]          angleDiff(from, to) -> shortest signed delta in (-pi, pi]
--   lerpAngle(a, b, t)                 expAlpha(rate, dt) -> 1 - e^(-rate*dt) (frame-rate independent)
--   damp(current, target, rate, dt)    exponential smoothing of numbers (or Vector3 via dampVector)
-- Vectors / CFrames:
--   flat(v) -> Vector3(v.X, 0, v.Z)    safeUnit(v, fallback?) -> unit vector or fallback (default zero)
--   flatUnit(v, fallback?)             lerpVector(a, b, t)
--   lerpCFrame(a, b, t)                dampCFrame(current, target, rate, dt)
--   yawFromVector(v) -> radians (0 = facing -Z, positive = turning LEFT, i.e. CFrame.Angles(0, yaw, 0))
--   cframeFromYaw(position, yaw)       randomInCircle(rng, radius) -> Vector3 (x, 0, z), uniform in disk
-- Easing (curves of Roblox Enum.EasingStyle / EasingDirection; standard Penner/easings.net forms):
--   Ease(alpha, style, dir) -> number  alpha is clamped to [0, 1]; result is 0 at 0 and 1 at 1.
--     style: "Linear"|"Sine"|"Quad"|"Cubic"|"Quart"|"Quint"|"Back"|"Elastic"|"Bounce"|"Expo"|"Circ"
--            (Roblox names "Exponential"/"Circular" and EasingStyle EnumItems are accepted too;
--             unknown styles fall back to Linear — use IsEasingStyle to validate data)
--     dir:   "In" | "Out" | "InOut" (default "Out", like TweenInfo); EnumItems accepted.
--   IsEasingStyle(name) -> boolean    EasingStyles -> {string}

local MathUtil = {}

local PI = math.pi
local TAU = 2 * math.pi
local HALF_PI = math.pi / 2
local EPSILON = 1e-9

-- Scalars ---------------------------------------------------------------------------------------

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.inverseLerp(a: number, b: number, v: number): number
	local d = b - a
	if math.abs(d) < EPSILON then
		return 0
	end
	return (v - a) / d
end

function MathUtil.clamp(x: number, lo: number, hi: number): number
	if lo > hi then
		lo, hi = hi, lo
	end
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

function MathUtil.remap(x: number, inMin: number, inMax: number, outMin: number, outMax: number, clampOutput: boolean?): number
	local t = MathUtil.inverseLerp(inMin, inMax, x)
	if clampOutput then
		t = MathUtil.clamp(t, 0, 1)
	end
	return outMin + (outMax - outMin) * t
end

-- GLSL smoothstep: 0 below e0, 1 above e1, cubic Hermite in between.
function MathUtil.smoothstep(e0: number, e1: number, x: number): number
	local t = MathUtil.clamp(MathUtil.inverseLerp(e0, e1, x), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Ken Perlin's smootherstep (zero 1st and 2nd derivatives at the edges).
function MathUtil.smootherstep(e0: number, e1: number, x: number): number
	local t = MathUtil.clamp(MathUtil.inverseLerp(e0, e1, x), 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- Nearest multiple of `step` (default 1). Exact halves round toward +infinity (floor(x/step + 0.5)).
function MathUtil.round(x: number, step: number?): number
	local s = step or 1
	if s == 0 then
		return x
	end
	return math.floor(x / s + 0.5) * s
end

function MathUtil.sign(x: number): number
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	end
	return 0
end

-- Moves `current` toward `target` by at most |maxDelta| without overshooting.
function MathUtil.approach(current: number, target: number, maxDelta: number): number
	local step = math.abs(maxDelta)
	if current < target then
		return math.min(current + step, target)
	elseif current > target then
		return math.max(current - step, target)
	end
	return target
end

-- Wraps an angle (radians) into (-pi, pi].
function MathUtil.wrapAngle(a: number): number
	local w = (a + PI) % TAU -- Luau % is floored: result in [0, TAU)
	if w == 0 then
		return PI
	end
	return w - PI
end

-- Shortest signed rotation (radians) that takes angle `from` to angle `to`, in (-pi, pi].
function MathUtil.angleDiff(from: number, to: number): number
	return MathUtil.wrapAngle(to - from)
end

function MathUtil.lerpAngle(a: number, b: number, t: number): number
	return a + MathUtil.angleDiff(a, b) * t
end

-- Frame-rate independent smoothing factor: use as lerp alpha each frame.
-- rate = how fast (1/s); after 1/rate seconds ~63% of the gap is closed.
function MathUtil.expAlpha(rate: number, dt: number): number
	if rate <= 0 or dt <= 0 then
		return 0
	end
	return 1 - math.exp(-rate * dt)
end

function MathUtil.damp(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * MathUtil.expAlpha(rate, dt)
end

-- Vectors -----------------------------------------------------------------------------------------

function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.safeUnit(v: Vector3, fallback: Vector3?): Vector3
	local m = v.Magnitude
	if m < 1e-6 or m ~= m then
		return fallback or Vector3.zero
	end
	return v / m
end

function MathUtil.flatUnit(v: Vector3, fallback: Vector3?): Vector3
	return MathUtil.safeUnit(Vector3.new(v.X, 0, v.Z), fallback)
end

function MathUtil.lerpVector(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

function MathUtil.dampVector(current: Vector3, target: Vector3, rate: number, dt: number): Vector3
	return current + (target - current) * MathUtil.expAlpha(rate, dt)
end

function MathUtil.lerpCFrame(a: CFrame, b: CFrame, t: number): CFrame
	return a:Lerp(b, t)
end

function MathUtil.dampCFrame(current: CFrame, target: CFrame, rate: number, dt: number): CFrame
	return current:Lerp(target, MathUtil.expAlpha(rate, dt))
end

-- Yaw (radians) of a direction such that CFrame.Angles(0, yaw, 0).LookVector points along flat(v).
-- 0 = facing -Z; positive = turned LEFT (toward -X), matching Roblox's rotation convention.
function MathUtil.yawFromVector(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

function MathUtil.cframeFromYaw(position: Vector3, yaw: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

-- Uniform random point in a horizontal disk of `radius`, as Vector3(x, 0, z).
-- `rng` may be a Shared/Util/Rng object (deterministic) or a Roblox Random.
function MathUtil.randomInCircle(rng: any, radius: number): Vector3
	local u, a = 0, 0
	if type(rng) == "table" and rng.Number ~= nil then
		u = rng:Number()
		a = rng:Number() * TAU
	else
		u = rng:NextNumber()
		a = rng:NextNumber() * TAU
	end
	local r = radius * math.sqrt(u)
	return Vector3.new(r * math.cos(a), 0, r * math.sin(a))
end

-- Easing ------------------------------------------------------------------------------------------

type EaseFn = (t: number) -> number

local function powIn(n: number): EaseFn
	return function(t: number): number
		return t ^ n
	end
end

local BACK_C1 = 1.70158
local BACK_C2 = BACK_C1 * 1.525
local BACK_C3 = BACK_C1 + 1
local ELASTIC_C4 = TAU / 3 -- period 0.3 (In/Out)
local ELASTIC_C5 = TAU / 4.5 -- period 0.45 (InOut)

local function bounceOut(t: number): number
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		local u = t - 1.5 / d1
		return n1 * u * u + 0.75
	elseif t < 2.5 / d1 then
		local u = t - 2.25 / d1
		return n1 * u * u + 0.9375
	end
	local u = t - 2.625 / d1
	return n1 * u * u + 0.984375
end

-- The "In" curve of every style; Out/InOut are derived from it unless overridden below.
local IN: { [string]: EaseFn } = {
	Linear = function(t: number): number
		return t
	end,
	Sine = function(t: number): number
		return 1 - math.cos(t * HALF_PI)
	end,
	Quad = powIn(2),
	Cubic = powIn(3),
	Quart = powIn(4),
	Quint = powIn(5),
	Expo = function(t: number): number
		if t <= 0 then
			return 0
		end
		return 2 ^ (10 * t - 10)
	end,
	Circ = function(t: number): number
		return 1 - math.sqrt(math.max(0, 1 - t * t))
	end,
	Back = function(t: number): number
		return BACK_C3 * t * t * t - BACK_C1 * t * t
	end,
	Elastic = function(t: number): number
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * ELASTIC_C4)
	end,
	Bounce = function(t: number): number
		return 1 - bounceOut(1 - t)
	end,
}

-- InOut curves that are NOT the plain mirror of In (Back and Elastic use wider constants, like Penner).
local INOUT_OVERRIDE: { [string]: EaseFn } = {
	Back = function(t: number): number
		if t < 0.5 then
			local u = 2 * t
			return (u * u * ((BACK_C2 + 1) * u - BACK_C2)) / 2
		end
		local u = 2 * t - 2
		return (u * u * ((BACK_C2 + 1) * u + BACK_C2) + 2) / 2
	end,
	Elastic = function(t: number): number
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		elseif t < 0.5 then
			return -(2 ^ (20 * t - 10) * math.sin((20 * t - 11.125) * ELASTIC_C5)) / 2
		end
		return (2 ^ (-20 * t + 10) * math.sin((20 * t - 11.125) * ELASTIC_C5)) / 2 + 1
	end,
}

local ALIASES: { [string]: string } = {
	Exponential = "Expo",
	Circular = "Circ",
}

local STYLE_LIST = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Back", "Elastic", "Bounce", "Expo", "Circ" }
MathUtil.EasingStyles = table.freeze(table.clone(STYLE_LIST))

local function nameOf(value: any): string?
	if type(value) == "string" then
		return value
	elseif typeof(value) == "EnumItem" then
		return (value :: any).Name
	end
	return nil
end

local function styleKey(style: any): string
	local name = nameOf(style) or "Linear"
	return ALIASES[name] or name
end

function MathUtil.IsEasingStyle(style: any): boolean
	local name = nameOf(style)
	if name == nil then
		return false
	end
	return IN[ALIASES[name] or name] ~= nil
end

-- Roblox-equivalent easing value for alpha in [0, 1] (clamped). See header for accepted names.
function MathUtil.Ease(alpha: number, style: any?, direction: any?): number
	local t = alpha
	if t ~= t or t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	local key = styleKey(style)
	local f = IN[key]
	if f == nil then
		return t -- unknown style -> Linear
	end
	local dir = nameOf(direction) or "Out"
	if dir == "In" then
		return f(t)
	elseif dir == "InOut" then
		local override = INOUT_OVERRIDE[key]
		if override then
			return override(t)
		end
		if t < 0.5 then
			return f(2 * t) / 2
		end
		return 1 - f(2 - 2 * t) / 2
	end
	-- "Out" (default): mirror of In
	return 1 - f(1 - t)
end

return MathUtil
