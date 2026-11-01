--!strict
-- CameraShake: trauma-based screen shake (the "trauma^2 + Perlin noise" model). Pure and deterministic
-- (math.noise only, no services, no allocations per Update besides the two returned Vector3 values), so it is
-- unit-tested under Lune. CameraController owns the default instance and applies its offsets every frame.
--
--   local shaker = CameraShake.new(config?)
--   shaker:AddTrauma(amount)               instant trauma (0..MaxTrauma), decays linearly at DecayRate per second
--   shaker:Shake(intensity, duration?)     sustained source: `intensity` trauma that fades out over `duration`
--                                          ((1 - t/d)^2 envelope). Many sources combine as max + 25 % of the rest.
--   shaker:Update(dt) -> (Vector3, Vector3)  advances time (dt clamped to 0.25 s so a frame hitch never eats a
--                                          shake); returns (positionOffset studs in CAMERA space,
--                                          rotationOffset radians (pitch, yaw, roll))
--   shaker:Trauma() -> number              effective trauma after the last Update (0..MaxTrauma)
--   shaker:Magnitude() -> number           Trauma()^Exponent * Scale (what drives the offsets)
--   shaker:SetScale(s)                     player setting x reduced motion (0 = off)
--   shaker:Reset()
-- Module-level shortcuts drive CameraShake.Default (the instance CameraController reads):
--   CameraShake.Shake(intensity, duration?) / CameraShake.AddTrauma(amount) / CameraShake.Preset(name)
--   CameraShake.Presets = { Tiny, Light, Medium, Heavy, Huge, Rumble }  -> {intensity, duration}
-- Intensity guide (same scale as FxContext fx.Shake): 0.15 footstep-ish, 0.3 hit taken, 0.5 heavy hit /
-- blaster nearby, 0.8 ultimate / slam, 1.0+ final-phase transformation.

local CameraShake = {}
CameraShake.__index = CameraShake

export type Config = {
	DecayRate: number?, -- trauma lost per second (instant trauma)
	MaxTrauma: number?, -- cap of the effective trauma
	Exponent: number?, -- magnitude = trauma ^ Exponent
	Frequency: number?, -- noise speed at full trauma (Hz-ish)
	MinFrequency: number?, -- noise speed at zero trauma
	MaxAngles: Vector3?, -- radians (pitch, yaw, roll) at magnitude 1
	MaxOffset: Vector3?, -- studs (x, y, z camera space) at magnitude 1
	Seed: number?,
	MaxSources: number?,
}

export type Shaker = {
	DecayRate: number,
	MaxTrauma: number,
	Exponent: number,
	Frequency: number,
	MinFrequency: number,
	MaxAngles: Vector3,
	MaxOffset: Vector3,
	Seed: number,
	Scale: number,
	AddTrauma: (self: Shaker, amount: number) -> (),
	Shake: (self: Shaker, intensity: number, duration: number?) -> (),
	Update: (self: Shaker, dt: number) -> (Vector3, Vector3),
	Trauma: (self: Shaker) -> number,
	Magnitude: (self: Shaker) -> number,
	SetScale: (self: Shaker, scale: number) -> (),
	Reset: (self: Shaker) -> (),
	ActiveSources: (self: Shaker) -> number,
}

local DEFAULTS = {
	DecayRate = 1.4,
	MaxTrauma = 1.25,
	Exponent = 2,
	Frequency = 22,
	MinFrequency = 9,
	MaxAngles = Vector3.new(math.rad(2.4), math.rad(2.0), math.rad(3.2)),
	MaxOffset = Vector3.new(0.22, 0.22, 0.12),
	Seed = 7.31,
	MaxSources = 16,
}

CameraShake.Presets = {
	Tiny = { 0.12, 0.15 },
	Light = { 0.25, 0.22 },
	Medium = { 0.45, 0.35 },
	Heavy = { 0.7, 0.5 },
	Huge = { 1.0, 0.8 },
	Rumble = { 0.35, 1.6 },
}

-- Internal fields (in addition to Shaker): _trauma, _effective, _time, _phase, _amp, _dur, _age, _count
type Impl = {
	DecayRate: number,
	MaxTrauma: number,
	Exponent: number,
	Frequency: number,
	MinFrequency: number,
	MaxAngles: Vector3,
	MaxOffset: Vector3,
	Seed: number,
	Scale: number,
	_maxSources: number,
	_trauma: number,
	_effective: number,
	_phase: number,
	_amp: { number },
	_dur: { number },
	_age: { number },
	_count: number,
}

function CameraShake.new(config: Config?): Shaker
	local c: Config = config or {}
	local maxSources = c.MaxSources or DEFAULTS.MaxSources
	local self: Impl = {
		DecayRate = c.DecayRate or DEFAULTS.DecayRate,
		MaxTrauma = c.MaxTrauma or DEFAULTS.MaxTrauma,
		Exponent = c.Exponent or DEFAULTS.Exponent,
		Frequency = c.Frequency or DEFAULTS.Frequency,
		MinFrequency = c.MinFrequency or DEFAULTS.MinFrequency,
		MaxAngles = c.MaxAngles or DEFAULTS.MaxAngles,
		MaxOffset = c.MaxOffset or DEFAULTS.MaxOffset,
		Seed = c.Seed or DEFAULTS.Seed,
		Scale = 1,
		_maxSources = maxSources,
		_trauma = 0,
		_effective = 0,
		_phase = 0,
		-- fixed-size parallel arrays: no allocation when sources come and go
		_amp = table.create(maxSources, 0),
		_dur = table.create(maxSources, 0),
		_age = table.create(maxSources, 0),
		_count = 0,
	}
	return (setmetatable(self, CameraShake) :: any) :: Shaker
end

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

function CameraShake.AddTrauma(self: Impl, amount: number)
	if type(amount) ~= "number" or not finite(amount) then
		return
	end
	self._trauma = math.clamp(self._trauma + amount, 0, self.MaxTrauma)
end

function CameraShake.Shake(self: Impl, intensity: number, duration: number?)
	if type(intensity) ~= "number" or not finite(intensity) or intensity <= 0 then
		return
	end
	local d = if type(duration) == "number" and finite(duration) then math.max(duration, 0.05) else 0.3
	local amp = math.min(intensity, self.MaxTrauma)
	local n = self._count
	if n < self._maxSources then
		n += 1
		self._count = n
		self._amp[n] = amp
		self._dur[n] = d
		self._age[n] = 0
		return
	end
	-- full: replace the weakest remaining source if the new one is stronger
	local weakest, weakestValue = 1, math.huge
	for i = 1, n do
		local e = 1 - self._age[i] / self._dur[i]
		local value = self._amp[i] * e * e
		if value < weakestValue then
			weakest, weakestValue = i, value
		end
	end
	if amp > weakestValue then
		self._amp[weakest] = amp
		self._dur[weakest] = d
		self._age[weakest] = 0
	end
end

-- Envelope of source i at its current age: amp * (1 - age/dur)^2 (instant attack, smooth release).
local function envelope(self: Impl, i: number): number
	local e = 1 - self._age[i] / self._dur[i]
	if e <= 0 then
		return 0
	end
	return self._amp[i] * e * e
end

function CameraShake.Update(self: Impl, dt: number): (Vector3, Vector3)
	if type(dt) ~= "number" or not finite(dt) or dt < 0 then
		dt = 0
	end
	dt = math.min(dt, 0.25)
	-- instant trauma decays linearly
	self._trauma = math.max(0, self._trauma - self.DecayRate * dt)
	-- age sources, drop finished ones (swap-remove keeps the arrays dense)
	local i = 1
	local maxEnv, sumEnv = 0, 0
	while i <= self._count do
		self._age[i] += dt
		if self._age[i] >= self._dur[i] then
			local last = self._count
			self._amp[i] = self._amp[last]
			self._dur[i] = self._dur[last]
			self._age[i] = self._age[last]
			self._count = last - 1
		else
			local env = envelope(self, i)
			sumEnv += env
			if env > maxEnv then
				maxEnv = env
			end
			i += 1
		end
	end
	local effective = self._trauma + maxEnv + 0.25 * (sumEnv - maxEnv)
	effective = math.clamp(effective, 0, self.MaxTrauma)
	self._effective = effective

	local magnitude = (effective ^ self.Exponent) * self.Scale
	if magnitude <= 1e-5 then
		return Vector3.zero, Vector3.zero
	end
	-- noise speed rises with trauma: big shakes are faster and more violent
	local frequency = self.MinFrequency + (self.Frequency - self.MinFrequency) * math.min(effective, 1)
	self._phase += dt * frequency
	local p = self._phase
	local s = self.Seed
	-- math.noise is ~[-0.7, 0.7] in practice; x1.4 normalises it to about [-1, 1]
	local n1 = math.clamp(math.noise(s + 0.13, p, 0.37) * 1.4, -1, 1)
	local n2 = math.clamp(math.noise(s + 11.71, p, 1.93) * 1.4, -1, 1)
	local n3 = math.clamp(math.noise(s + 23.37, p * 0.8, 4.11) * 1.4, -1, 1)
	local n4 = math.clamp(math.noise(s + 37.53, p, 7.29) * 1.4, -1, 1)
	local n5 = math.clamp(math.noise(s + 51.19, p, 9.83) * 1.4, -1, 1)
	local a = self.MaxAngles
	local o = self.MaxOffset
	local rotation = Vector3.new(a.X * n1, a.Y * n2, a.Z * n3) * magnitude
	local position = Vector3.new(o.X * n4, o.Y * n5, o.Z * n3) * magnitude
	return position, rotation
end

function CameraShake.Trauma(self: Impl): number
	return self._effective
end

function CameraShake.Magnitude(self: Impl): number
	return (self._effective ^ self.Exponent) * self.Scale
end

function CameraShake.SetScale(self: Impl, scale: number)
	if type(scale) == "number" and finite(scale) then
		self.Scale = math.max(0, scale)
	end
end

function CameraShake.Reset(self: Impl)
	self._trauma = 0
	self._effective = 0
	self._count = 0
end

function CameraShake.ActiveSources(self: Impl): number
	return self._count
end

-- default instance + module-level shortcuts ------------------------------------------------------------------
local default: Shaker = CameraShake.new()
CameraShake.Default = default

-- Module-level calls (CameraShake.Shake(0.4, 0.3)) are routed to the default instance: the first argument is then
-- a number, not a shaker. Method calls (shaker:Shake(...)) keep working because `self` is a table.
local methodShake = CameraShake.Shake
local methodAddTrauma = CameraShake.AddTrauma
CameraShake.Shake = function(selfOrIntensity: any, a: any, b: any)
	if type(selfOrIntensity) == "table" then
		methodShake(selfOrIntensity, a, b)
	else
		methodShake(default :: any, selfOrIntensity, a)
	end
end :: any
CameraShake.AddTrauma = function(selfOrAmount: any, a: any)
	if type(selfOrAmount) == "table" then
		methodAddTrauma(selfOrAmount, a)
	else
		methodAddTrauma(default :: any, selfOrAmount)
	end
end :: any

function CameraShake.Preset(name: string, scale: number?)
	local preset = CameraShake.Presets[name]
	if preset then
		methodShake(default :: any, preset[1] * (scale or 1), preset[2])
	end
end

return CameraShake
