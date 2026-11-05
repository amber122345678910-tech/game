--!strict
--[[
	ReplicatedStorage.Spring
	Пружина по закону Гука с точным (аналитическим) решением:
	x'' = -Speed² · (x - Target) - 2 · Damper · Speed · x'

	Damper = 1   -> критическое демпфирование (быстро и без перелёта)
	Damper < 1   -> недодемпфированная (пружинит, перелетает цель)
	Damper > 1   -> передемпфированная (вязкая, медленно подползает)
	Speed        -> угловая частота (рад/с): чем больше, тем резче

	Работает с number и Vector3 (любой тип с +, -, * number).
	Решение аналитическое, поэтому устойчиво при любом dt (лаги, 240 FPS — неважно).

	local s = Spring.new(0, 1, 12)
	s.Target = 1
	s:Impulse(5)
	local value = s:Update(dt)
]]

export type Spring<T> = {
	Position: T,
	Velocity: T,
	Target: T,
	Damper: number,
	Speed: number,
	Update: (self: Spring<T>, dt: number) -> T,
	Impulse: (self: Spring<T>, velocity: T) -> (),
	Snap: (self: Spring<T>, value: T) -> (),
	SetTarget: (self: Spring<T>, target: T) -> (),
	IsResting: (self: Spring<T>, epsilon: number?) -> boolean,
}

local Spring = {}
Spring.__index = Spring

local MAX_DT = 0.1 -- после фриза кадра пружина не "выстреливает"
local EPS = 1e-4

local function magnitudeOf(value: any): number
	if typeof(value) == "Vector3" then
		return (value :: Vector3).Magnitude
	end
	return math.abs(value :: number)
end

-- Создаёт пружину. initialValue: number | Vector3.
function Spring.new<T>(initialValue: T, damper: number?, speed: number?): Spring<T>
	local zero: any = (initialValue :: any) * 0
	local self = setmetatable({
		Position = initialValue,
		Velocity = zero,
		Target = initialValue,
		Damper = damper or 1,
		Speed = speed or 10,
	}, Spring)
	return (self :: any) :: Spring<T>
end

-- Продвигает симуляцию на dt секунд и возвращает новую позицию.
function Spring.Update<T>(self: Spring<T>, dt: number): T
	local t = math.clamp(dt, 0, MAX_DT)
	if t <= 0 then
		return self.Position
	end

	local d = math.max(self.Damper, 0)
	local w = math.max(self.Speed, EPS)
	local target: any = self.Target
	local x0: any = (self.Position :: any) - target -- смещение от цели
	local v0: any = self.Velocity

	local x: any
	local v: any

	if math.abs(d - 1) < 1e-3 then
		-- Критическое демпфирование: x(t) = (x0 + (v0 + w·x0)·t)·e^(-w·t)
		local e = math.exp(-w * t)
		local c: any = v0 + x0 * w
		x = (x0 + c * t) * e
		v = (v0 - c * (w * t)) * e
	elseif d < 1 then
		-- Недодемпфированная: затухающие колебания
		local wd = w * math.sqrt(1 - d * d)
		local e = math.exp(-d * w * t)
		local cosT = math.cos(wd * t)
		local sinT = math.sin(wd * t)
		local b: any = (v0 + x0 * (d * w)) * (1 / wd)
		x = (x0 * cosT + b * sinT) * e
		v = (v0 * cosT - (b * (d * w) + x0 * wd) * sinT) * e
	else
		-- Передемпфированная: сумма двух экспонент
		local root = math.sqrt(d * d - 1)
		local r1 = -w * (d - root)
		local r2 = -w * (d + root)
		local c1: any = (v0 - x0 * r2) * (1 / (r1 - r2))
		local c2: any = x0 - c1
		local e1 = math.exp(r1 * t)
		local e2 = math.exp(r2 * t)
		x = c1 * e1 + c2 * e2
		v = c1 * (r1 * e1) + c2 * (r2 * e2)
	end

	self.Position = (target + x) :: T
	self.Velocity = v :: T
	return self.Position
end

-- Мгновенно добавляет скорость (удар, отдача, "пинок" кнопки).
function Spring.Impulse<T>(self: Spring<T>, velocity: T)
	self.Velocity = ((self.Velocity :: any) + (velocity :: any)) :: T
end

-- Телепортирует пружину в значение без инерции.
function Spring.Snap<T>(self: Spring<T>, value: T)
	self.Position = value
	self.Target = value
	self.Velocity = ((value :: any) * 0) :: T
end

function Spring.SetTarget<T>(self: Spring<T>, target: T)
	self.Target = target
end

-- true, если пружина почти остановилась у цели.
function Spring.IsResting<T>(self: Spring<T>, epsilon: number?): boolean
	local e = epsilon or 1e-3
	local offset: any = (self.Position :: any) - (self.Target :: any)
	return magnitudeOf(offset) < e and magnitudeOf(self.Velocity) < e
end

return Spring
