--!strict
-- Spring: damped harmonic spring with an EXACT analytic step (stable for any dt — 0.5 s frame hitches,
-- 10 s time skips — no sub-stepping needed). Lune-safe.
-- Works for number, Vector3, Vector2 (anything with T + T, T - T and T * number).
--
--   local s = Spring.new(initial, speed, damping?)
--     speed   = angular frequency w (rad/s). Higher = snappier. Critically damped settles to ~1 % of a
--               step in about 6.6 / speed seconds (e.g. speed 20 -> ~0.33 s).
--     damping = zeta. 1 = critical (default, no overshoot), < 1 bouncy (0.3 = very wobbly), > 1 sluggish.
--   s.Position, s.Velocity, s.Target, s.Speed, s.Damping   plain fields: read/write freely
--   s:Update(dt) -> Position          advances the simulation by dt seconds (dt <= 0 is a no-op)
--   s:Impulse(v)                      Velocity += v (kick)
--   s:Reset(p?)                       Position = Target = (p or Target), Velocity = 0
--   s:IsSettled(epsilon?) -> boolean  |Position - Target| and |Velocity| below epsilon (default 1e-3)
-- Allocation-free helpers for hot loops (e.g. per-joint springs):
--   Spring.Coefficients(speed, damping, dt) -> (A, B, C, D)
--       with x = Position - Target: x' = x*A + v*B, v' = x*C + v*D   (compute once per frame, reuse)
--   Spring.Step(position, velocity, target, speed, damping, dt) -> (position, velocity)
-- NOTE: values are multiplied as `value * number` (never `number * value`): Lune's Vector3 only
-- supports the vector-first form.

local Spring = {}
Spring.__index = Spring

export type Spring<T> = {
	Position: T,
	Velocity: T,
	Target: T,
	Speed: number,
	Damping: number,
	Update: (self: Spring<T>, dt: number) -> T,
	Impulse: (self: Spring<T>, velocity: T) -> (),
	Reset: (self: Spring<T>, position: T?) -> (),
	IsSettled: (self: Spring<T>, epsilon: number?) -> boolean,
}

type SpringImpl = {
	Position: any,
	Velocity: any,
	Target: any,
	Speed: number,
	Damping: number,
}

-- |damping - 1| below this uses the critical formula. The under/over-damped formulas stay accurate
-- much closer to 1 than this (no cancellation), so the switch costs < 1e-9 relative error.
local CRITICAL_BAND = 1e-9

-- Exact solution of x'' = -w^2 x - 2 z w x' after time t, as a linear map of (x0, v0):
--   x(t) = A*x0 + B*v0,  v(t) = C*x0 + D*v0.
function Spring.Coefficients(speed: number, damping: number, t: number): (number, number, number, number)
	local w = speed
	local z = math.max(damping, 0)
	if w <= 0 or w ~= w then
		return 1, t, 0, 1 -- no spring force: coast
	end
	if z < 1 - CRITICAL_BAND then
		-- under-damped: decaying oscillation
		local wd = w * math.sqrt(1 - z * z)
		local e = math.exp(-z * w * t)
		local c = math.cos(wd * t)
		local s = math.sin(wd * t)
		local k = z * w / wd
		return e * (c + k * s), e * s / wd, -e * w * w / wd * s, e * (c - k * s)
	elseif z <= 1 + CRITICAL_BAND then
		-- critically damped
		local e = math.exp(-w * t)
		return (1 + w * t) * e, t * e, -w * w * t * e, (1 - w * t) * e
	end
	-- over-damped: e^(-z w t) * (cosh, sinh) of gamma t, gamma = w sqrt(z^2 - 1)
	local gamma = w * math.sqrt(z * z - 1)
	local gt = gamma * t
	if gt < 1 then
		-- hyperbolic form: no cancellation when gamma*t is small, no overflow because gt < 1
		local e = math.exp(-z * w * t)
		local ch = math.cosh(gt)
		local sh = math.sinh(gt)
		local k = z * w / gamma
		return e * (ch + k * sh), e * sh / gamma, -e * w * w / gamma * sh, e * (ch - k * sh)
	end
	-- two decaying exponentials (both roots negative): no overflow for huge t
	local r1 = -z * w + gamma
	local r2 = -z * w - gamma
	local e1 = math.exp(r1 * t)
	local e2 = math.exp(r2 * t)
	local inv = 1 / (r2 - r1)
	return (r2 * e1 - r1 * e2) * inv, (e2 - e1) * inv, r1 * r2 * (e1 - e2) * inv, (r2 * e2 - r1 * e1) * inv
end

function Spring.Step<T>(position: T, velocity: T, target: T, speed: number, damping: number, dt: number): (T, T)
	if dt <= 0 then
		return position, velocity
	end
	local a, b, c, d = Spring.Coefficients(speed, damping, dt)
	local x: any = (position :: any) - (target :: any)
	local v: any = velocity
	return (target :: any) + x * a + v * b, x * c + v * d
end

function Spring.new<T>(initial: T, speed: number?, damping: number?): Spring<T>
	local self: SpringImpl = {
		Position = initial,
		Velocity = (initial :: any) - (initial :: any),
		Target = initial,
		Speed = speed or 10,
		Damping = damping or 1,
	}
	return (setmetatable(self, Spring) :: any) :: Spring<T>
end

function Spring.Update(self: SpringImpl, dt: number): any
	if dt > 0 then
		self.Position, self.Velocity = Spring.Step(self.Position, self.Velocity, self.Target, self.Speed, self.Damping, dt)
	end
	return self.Position
end

function Spring.Impulse(self: SpringImpl, velocity: any)
	self.Velocity = self.Velocity + velocity
end

function Spring.Reset(self: SpringImpl, position: any?)
	local p = if position ~= nil then position else self.Target
	self.Position = p
	self.Target = p
	self.Velocity = p - p
end

local function magnitude(value: any): number
	if type(value) == "number" then
		return math.abs(value)
	end
	return value.Magnitude
end

function Spring.IsSettled(self: SpringImpl, epsilon: number?): boolean
	local eps = epsilon or 1e-3
	return magnitude(self.Position - self.Target) < eps and magnitude(self.Velocity) < eps
end

return Spring
