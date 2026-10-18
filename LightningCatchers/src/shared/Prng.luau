--!strict
-- Детерминированный генератор случайных чисел (xorshift32).
-- Одинаково работает в Roblox и в Lune (тесты), поэтому форма молнии или фульгурита
-- по одному seed всегда одна и та же — на сервере, у клиента и в превью-рендере.

export type Prng = {
	state: number,
	next: (self: Prng) -> number,
	range: (self: Prng, a: number, b: number) -> number,
	int: (self: Prng, a: number, b: number) -> number,
	chance: (self: Prng, p: number) -> boolean,
}

local Prng = {}

local function nextValue(self: Prng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / 4294967296
end

local function range(self: Prng, a: number, b: number): number
	return a + (b - a) * self:next()
end

local function int(self: Prng, a: number, b: number): number
	return math.min(b, a + math.floor((b - a + 1) * self:next()))
end

local function chance(self: Prng, p: number): boolean
	return self:next() < p
end

function Prng.new(seed: number): Prng
	local s = math.floor(math.abs(seed)) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	local self: Prng = {
		state = s, -- xorshift требует только ненулевое состояние
		next = nextValue,
		range = range,
		int = int,
		chance = chance,
	}
	-- "прогрев": соседние seed дают разные последовательности
	for _ = 1, 6 do
		self:next()
	end
	return self
end

-- Смешать числа в один seed (например, userId и номер)
function Prng.hash(a: number, b: number?): number
	local h = bit32.bxor(math.floor(a) % 4294967296, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 0x5bd1e995) % 4294967296
	if b then
		h = bit32.bxor(h, math.floor(b) % 4294967296)
		h = (h * 0x27d4eb2d) % 4294967296
	end
	h = bit32.bxor(h, bit32.rshift(h, 15))
	return h
end

return Prng
