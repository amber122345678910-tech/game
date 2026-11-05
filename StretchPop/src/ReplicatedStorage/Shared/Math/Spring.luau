--!strict
-- STRETCH-POP · Пружины по закону Гука: a = −k·(x − target) − c·v.
-- Используются камерой (FOV/дистанция), желе-колебаниями рук, сквош-стретчем шара и VFX,
-- а на следующем шаге — пружинным мультяшным UI.
-- Интегрирование: полунеявный Эйлер с подшагом ≤ 1/240 с (устойчиво при k·h² < 4).

local MAX_STEP = 1 / 240
local MAX_FRAME = 0.25

type NumberSpringData = {
	Position: number,
	Velocity: number,
	Target: number,
	Stiffness: number,
	Damping: number,
}

type VectorSpringData = {
	Position: Vector3,
	Velocity: Vector3,
	Target: Vector3,
	Stiffness: number,
	Damping: number,
}

local NumberSpring = {}
NumberSpring.__index = NumberSpring

local VectorSpring = {}
VectorSpring.__index = VectorSpring

export type NumberSpring = typeof(setmetatable({} :: NumberSpringData, NumberSpring))
export type VectorSpring = typeof(setmetatable({} :: VectorSpringData, VectorSpring))

-- Перевод «частота + коэффициент затухания» в (k, c) для единичной массы.
-- dampingRatio = 1 — критическое затухание, < 1 — мультяшный перелёт и дрожание.
local function fromFrequency(frequencyHz: number, dampingRatio: number): (number, number)
	local omega = 2 * math.pi * frequencyHz
	return omega * omega, 2 * dampingRatio * omega
end

function NumberSpring.new(initial: number, frequencyHz: number, dampingRatio: number): NumberSpring
	local stiffness, damping = fromFrequency(frequencyHz, dampingRatio)
	local self: NumberSpringData = {
		Position = initial,
		Velocity = 0,
		Target = initial,
		Stiffness = stiffness,
		Damping = damping,
	}
	return setmetatable(self, NumberSpring)
end

function NumberSpring.Update(self: NumberSpring, dt: number): number
	local remaining = math.clamp(dt, 0, MAX_FRAME)
	while remaining > 1e-7 do
		local h = math.min(remaining, MAX_STEP)
		local acceleration = -self.Stiffness * (self.Position - self.Target) - self.Damping * self.Velocity
		self.Velocity += acceleration * h
		self.Position += self.Velocity * h
		remaining -= h
	end
	return self.Position
end

function NumberSpring.Impulse(self: NumberSpring, velocity: number)
	self.Velocity += velocity
end

function NumberSpring.Snap(self: NumberSpring, value: number)
	self.Position = value
	self.Target = value
	self.Velocity = 0
end

function NumberSpring.SetFrequency(self: NumberSpring, frequencyHz: number, dampingRatio: number)
	self.Stiffness, self.Damping = fromFrequency(frequencyHz, dampingRatio)
end

function VectorSpring.new(initial: Vector3, frequencyHz: number, dampingRatio: number): VectorSpring
	local stiffness, damping = fromFrequency(frequencyHz, dampingRatio)
	local self: VectorSpringData = {
		Position = initial,
		Velocity = Vector3.zero,
		Target = initial,
		Stiffness = stiffness,
		Damping = damping,
	}
	return setmetatable(self, VectorSpring)
end

function VectorSpring.Update(self: VectorSpring, dt: number): Vector3
	local remaining = math.clamp(dt, 0, MAX_FRAME)
	while remaining > 1e-7 do
		local h = math.min(remaining, MAX_STEP)
		local acceleration = (self.Position - self.Target) * -self.Stiffness - self.Velocity * self.Damping
		self.Velocity += acceleration * h
		self.Position += self.Velocity * h
		remaining -= h
	end
	return self.Position
end

function VectorSpring.Impulse(self: VectorSpring, velocity: Vector3)
	self.Velocity += velocity
end

function VectorSpring.Snap(self: VectorSpring, value: Vector3)
	self.Position = value
	self.Target = value
	self.Velocity = Vector3.zero
end

return {
	Number = NumberSpring,
	Vector = VectorSpring,
	FromFrequency = fromFrequency,
}
