--!strict
-- Rng: deterministic pseudo-random generator (xoshiro128** by Blackman & Vigna, period 2^128 - 1).
-- Lune-safe. Pure Luau: every step is exact integer arithmetic on doubles (< 2^53) plus bit32, so the
-- SAME seed gives the SAME sequence in Roblox, in Lune and on every platform. Use it instead of
-- Random / math.random wherever determinism matters (maps, patterns, daily shop, quests, tests).
--
--   Rng.new(seed: number | string?) -> Rng   any number (fractions, negatives, > 2^32) or a string;
--                                            nil seed = 0 (still deterministic)
--   Rng.fromState(state: {number}) -> Rng    restore from rng:State()
--   Rng.Hash(...: number | string) -> number 32-bit hash of the arguments (e.g. Rng.new(Rng.Hash(userId, day)))
--   rng:Number(min?, max?) -> number         [0, 1) | [0, max) | [min, max); 53-bit resolution
--   rng:Integer(min, max) -> number          uniform integer in [min, max] (inclusive, unbiased)
--   rng:Bool(p?) -> boolean                  true with probability p (default 0.5)
--   rng:Pick(list) -> value?                 uniform element (nil for an empty list)
--   rng:WeightedIndex(weights) -> number?    index chosen proportionally to weights[i] >= 0 (nil if all 0)
--   rng:Shuffle(list) -> list                Fisher-Yates IN PLACE, returns the same table
--   rng:UnitVector() -> Vector3              uniform direction on the unit sphere
--   rng:InCircle(radius) -> (x, z)           uniform point in a disk
--   rng:Clone() -> Rng                       independent copy continuing the same sequence
--   rng:State() -> {number}                  4 state words (serialisable)
--   rng:NextU32() -> number                  raw 32-bit output in [0, 2^32)
-- Roblox Random-compatible aliases: NextNumber, NextInteger, NextUnitVector.

local Rng = {}
Rng.__index = Rng

export type Rng = {
	Number: (self: Rng, min: number?, max: number?) -> number,
	Integer: (self: Rng, min: number, max: number) -> number,
	Bool: (self: Rng, p: number?) -> boolean,
	Pick: <T>(self: Rng, list: { T }) -> T?,
	WeightedIndex: (self: Rng, weights: { number }) -> number?,
	Shuffle: <T>(self: Rng, list: { T }) -> { T },
	UnitVector: (self: Rng) -> Vector3,
	InCircle: (self: Rng, radius: number) -> (number, number),
	Clone: (self: Rng) -> Rng,
	State: (self: Rng) -> { number },
	NextU32: (self: Rng) -> number,
	NextNumber: (self: Rng, min: number?, max: number?) -> number,
	NextInteger: (self: Rng, min: number, max: number) -> number,
	NextUnitVector: (self: Rng) -> Vector3,
}

type State = { s0: number, s1: number, s2: number, s3: number }

local TWO32 = 4294967296
local TWO26 = 67108864
local TWO53 = 9007199254740992
local TAU = 2 * math.pi

local bxor = bit32.bxor
local lrotate = bit32.lrotate
local lshift = bit32.lshift
local rshift = bit32.rshift

-- (a * b) mod 2^32 for a, b in [0, 2^32), exact (all partial products < 2^53).
local function mul32(a: number, b: number): number
	local aHi = math.floor(a / 65536)
	local aLo = a % 65536
	return ((aHi * b) % 65536 * 65536 + aLo * b) % TWO32
end

-- murmur3 finalizer: bijective 32-bit avalanche mix.
local function fmix32(x: number): number
	local h = bxor(x, rshift(x, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bxor(h, rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bxor(h, rshift(h, 16))
end

-- FNV-1a over the bytes of a string.
local function hashString(s: string): number
	local h = 0x811C9DC5
	for i = 1, #s do
		h = mul32(bxor(h, string.byte(s, i)), 0x01000193)
	end
	return h
end

-- Maps any number to three 32-bit words (integer low/high parts + fraction bits), deterministically.
local function numberWords(n: number): (number, number, number)
	if n ~= n or n == math.huge or n == -math.huge then
		n = 0
	end
	local whole = math.floor(n)
	local lo = whole % TWO32
	local hi = math.floor(whole / TWO32) % TWO32
	local frac = math.floor((n - whole) * TWO32) % TWO32
	return lo, hi, frac
end

local function hashValue(acc: number, v: number | string): number
	if type(v) == "string" then
		return fmix32(bxor(acc, hashString(v)))
	end
	local lo, hi, frac = numberWords(v :: number)
	acc = fmix32(bxor(acc, lo))
	acc = fmix32(bxor((acc + 0x9E3779B9) % TWO32, hi))
	return fmix32(bxor((acc + 0x632BE5AB) % TWO32, frac))
end

-- 32-bit hash of the arguments (numbers and/or strings). Deterministic everywhere.
function Rng.Hash(...: number | string): number
	local acc = 0x2545F491
	for i = 1, select("#", ...) do
		acc = hashValue(acc, (select(i, ...)))
	end
	return acc
end

local function next32(s: State): number
	local s0, s1, s2, s3 = s.s0, s.s1, s.s2, s.s3
	local result = (lrotate((s1 * 5) % TWO32, 7) * 9) % TWO32
	local t = lshift(s1, 9)
	s2 = bxor(s2, s0)
	s3 = bxor(s3, s1)
	s1 = bxor(s1, s2)
	s0 = bxor(s0, s3)
	s2 = bxor(s2, t)
	s3 = lrotate(s3, 11)
	s.s0, s.s1, s.s2, s.s3 = s0, s1, s2, s3
	return result
end

-- Uniform double in [0, 1) with 53 random bits.
local function unit(s: State): number
	local a = rshift(next32(s), 5) -- 27 bits
	local b = rshift(next32(s), 6) -- 26 bits
	return (a * TWO26 + b) / TWO53
end

local function integer(s: State, min: number, max: number): number
	if min > max then
		min, max = max, min
	end
	local range = max - min + 1
	if range <= 1 then
		return min
	end
	if range <= TWO32 then
		local limit = TWO32 - (TWO32 % range) -- rejection keeps the result unbiased
		local x = next32(s)
		while x >= limit do
			x = next32(s)
		end
		return min + (x % range)
	end
	return min + math.floor(unit(s) * range)
end

local function make(s0: number, s1: number, s2: number, s3: number, warmup: number): Rng
	if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
		s0 = 0x9E3779B9 -- the all-zero state is the only invalid xoshiro state
	end
	local state: State = { s0 = s0, s1 = s1, s2 = s2, s3 = s3 }
	for _ = 1, warmup do
		next32(state) -- decorrelate the first outputs from the seeding
	end
	return (setmetatable(state, Rng) :: any) :: Rng
end

function Rng.new(seed: (number | string)?): Rng
	local base = Rng.Hash(seed or 0)
	local x = base
	local words = table.create(4, 0)
	for i = 1, 4 do
		x = (x + 0x9E3779B9) % TWO32 -- splitmix-style counter, then avalanche
		words[i] = fmix32(bxor(x, mul32(base, 2 * i + 1)))
	end
	return make(words[1], words[2], words[3], words[4], 4)
end

function Rng.fromState(state: { number }): Rng
	assert(type(state) == "table" and #state == 4, "Rng.fromState expects {s0, s1, s2, s3}")
	local w = table.create(4, 0)
	for i = 1, 4 do
		w[i] = math.floor(state[i]) % TWO32
	end
	return make(w[1], w[2], w[3], w[4], 0)
end

-- Methods (self is the internal State table; the public type is Rng) -----------------------------

function Rng.NextU32(self: State): number
	return next32(self)
end

function Rng.Number(self: State, min: number?, max: number?): number
	local r = unit(self)
	if min == nil then
		return r
	elseif max == nil then
		return r * min -- Number(max) -> [0, max)
	end
	return min + (max - min) * r
end

function Rng.Integer(self: State, min: number, max: number): number
	return integer(self, math.floor(min), math.floor(max))
end

function Rng.Bool(self: State, p: number?): boolean
	return unit(self) < (p or 0.5)
end

function Rng.Pick<T>(self: State, list: { T }): T?
	local n = #list
	if n == 0 then
		return nil
	end
	return list[integer(self, 1, n)]
end

function Rng.WeightedIndex(self: State, weights: { number }): number?
	local total = 0
	for _, w in weights do
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local r = unit(self) * total
	local last: number? = nil
	for i, w in weights do
		if w > 0 then
			last = i
			r -= w
			if r < 0 then
				return i
			end
		end
	end
	return last -- floating-point leftovers land on the last positive weight
end

function Rng.Shuffle<T>(self: State, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = integer(self, 1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Rng.UnitVector(self: State): Vector3
	local z = unit(self) * 2 - 1
	local a = unit(self) * TAU
	local r = math.sqrt(math.max(0, 1 - z * z))
	return Vector3.new(r * math.cos(a), r * math.sin(a), z)
end

function Rng.InCircle(self: State, radius: number): (number, number)
	local r = radius * math.sqrt(unit(self))
	local a = unit(self) * TAU
	return r * math.cos(a), r * math.sin(a)
end

function Rng.Clone(self: State): Rng
	return make(self.s0, self.s1, self.s2, self.s3, 0)
end

function Rng.State(self: State): { number }
	return { self.s0, self.s1, self.s2, self.s3 }
end

Rng.NextNumber = Rng.Number
Rng.NextInteger = Rng.Integer
Rng.NextUnitVector = Rng.UnitVector

return Rng
