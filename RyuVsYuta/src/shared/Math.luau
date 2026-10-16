--!strict
-- Математика катсцены: сглаживание (easing), интерполяция, сплайны, шум, построение CFrame.
-- Модуль работает и в Roblox, и в Lune (сборка/превиз), поэтому не трогает сервисы движка.

local MathX = {}

local PI = math.pi
local HALF_PI = PI / 2
local rad = math.rad

export type EaseName = string

local function clamp01(t: number): number
	if t < 0 then
		return 0
	elseif t > 1 then
		return 1
	end
	return t
end
MathX.clamp01 = clamp01

function MathX.clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

function MathX.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Где v между a и b (0..1, без ограничения)
function MathX.invLerp(a: number, b: number, v: number): number
	if a == b then
		return 0
	end
	return (v - a) / (b - a)
end

-- Доля прошедшего отрезка [a, b] (0..1, с ограничением)
function MathX.progress(t: number, a: number, b: number): number
	if b <= a then
		return if t >= b then 1 else 0
	end
	return clamp01((t - a) / (b - a))
end

function MathX.remap(v: number, a: number, b: number, c: number, d: number): number
	return c + (d - c) * MathX.invLerp(a, b, v)
end

function MathX.smoothstep(t: number): number
	t = clamp01(t)
	return t * t * (3 - 2 * t)
end

function MathX.smootherstep(t: number): number
	t = clamp01(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- Плавный "колокол": 0 -> 1 -> 0 на отрезке [a, b] с фронтами fadeIn/fadeOut
function MathX.window(t: number, a: number, b: number, fadeIn: number, fadeOut: number): number
	if t <= a or t >= b then
		return 0
	end
	local up = if fadeIn > 0 then MathX.smoothstep((t - a) / fadeIn) else 1
	local down = if fadeOut > 0 then MathX.smoothstep((b - t) / fadeOut) else 1
	return math.min(up, down)
end

------------------------------------------------------------------------------------------
-- Easing. Имена как у Roblox (Enum.EasingStyle + направление): "InOutSine", "OutBack", ...
------------------------------------------------------------------------------------------

local function outBounce(t: number): number
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	end
	t -= 2.625 / d1
	return n1 * t * t + 0.984375
end

local IN: { [string]: (number) -> number } = {
	Linear = function(t)
		return t
	end,
	Sine = function(t)
		return 1 - math.cos(t * HALF_PI)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t * t * t * t
	end,
	Quint = function(t)
		return t * t * t * t * t
	end,
	Expo = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	end,
	Circ = function(t)
		return 1 - math.sqrt(math.max(0, 1 - t * t))
	end,
	Back = function(t)
		local c1 = 1.70158
		return (c1 + 1) * t * t * t - c1 * t * t
	end,
	Elastic = function(t)
		if t <= 0 or t >= 1 then
			return t
		end
		return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * PI / 3))
	end,
	Bounce = function(t)
		return 1 - outBounce(1 - t)
	end,
}

local easeCache: { [string]: (number) -> number } = {}

-- Возвращает функцию сглаживания по имени: "Linear", "InSine", "OutCubic", "InOutQuint", "OutBack", ...
function MathX.easeFn(name: string?): (number) -> number
	local key = name or "Linear"
	local cached = easeCache[key]
	if cached then
		return cached
	end
	local fn: (number) -> number
	if key == "Linear" then
		fn = IN.Linear
	elseif key == "Smooth" then
		fn = MathX.smoothstep
	elseif key == "Smoother" then
		fn = MathX.smootherstep
	elseif key == "Constant" then
		fn = function(_t: number): number
			return 0
		end
	else
		local dir, style = string.match(key, "^(InOut)(%a+)$")
		if not dir then
			dir, style = string.match(key, "^(Out)(%a+)$")
		end
		if not dir then
			dir, style = string.match(key, "^(In)(%a+)$")
		end
		local base = if style then IN[style] else nil
		assert(dir and base, "Unknown easing: " .. key)
		local f = base :: (number) -> number
		if dir == "In" then
			fn = f
		elseif dir == "Out" then
			fn = function(t: number): number
				return 1 - f(1 - t)
			end
		else
			fn = function(t: number): number
				if t < 0.5 then
					return f(t * 2) / 2
				end
				return 1 - f((1 - t) * 2) / 2
			end
		end
	end
	easeCache[key] = fn
	return fn
end

function MathX.ease(name: string?, t: number): number
	return MathX.easeFn(name)(clamp01(t))
end

------------------------------------------------------------------------------------------
-- Векторы, сплайны
------------------------------------------------------------------------------------------

function MathX.lerpV(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

-- Catmull-Rom (центростремительный не нужен — точки камеры расставлены равномерно)
function MathX.catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Точка на ломаной через все точки (Catmull-Rom), u в [0, 1]
function MathX.splinePoint(points: { Vector3 }, u: number): Vector3
	local n = #points
	if n == 1 then
		return points[1]
	elseif n == 2 then
		return points[1]:Lerp(points[2], clamp01(u))
	end
	u = clamp01(u) * (n - 1)
	local i = math.min(math.floor(u), n - 2)
	local f = u - i
	local p1 = points[i + 1]
	local p2 = points[i + 2]
	local p0 = if i > 0 then points[i] else p1 * 2 - p2
	local p3 = if i + 3 <= n then points[i + 3] else p2 * 2 - p1
	return MathX.catmullRom(p0, p1, p2, p3, f)
end

function MathX.bezier3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

------------------------------------------------------------------------------------------
-- CFrame
------------------------------------------------------------------------------------------

local UP = Vector3.new(0, 1, 0)

-- Надёжный lookAt (в Lune встроенный CFrame.lookAt неверен, поэтому строим матрицу сами).
-- Результат: LookVector = (target - pos).Unit, UpVector ~ up.
function MathX.lookAt(pos: Vector3, target: Vector3, up: Vector3?): CFrame
	local fwd = target - pos
	if fwd.Magnitude < 1e-6 then
		return CFrame.new(pos)
	end
	fwd = fwd.Unit
	local u = up or UP
	local right = fwd:Cross(u)
	if right.Magnitude < 1e-4 then
		right = fwd:Cross(Vector3.new(0, 0, 1))
		if right.Magnitude < 1e-4 then
			right = fwd:Cross(Vector3.new(1, 0, 0))
		end
	end
	right = right.Unit
	local realUp = right:Cross(fwd).Unit
	-- столбцы: X = right, Y = up, Z = -look
	return CFrame.fromMatrix(pos, right, realUp, -fwd)
end

-- CFrame, у которого ось X направлена по dir (нужно для Attachment у Beam: кривая идёт по оси X)
function MathX.axisX(pos: Vector3, dir: Vector3, upHint: Vector3?): CFrame
	local x = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.new(1, 0, 0)
	local hint = upHint or UP
	local z = x:Cross(hint)
	if z.Magnitude < 1e-4 then
		z = x:Cross(Vector3.new(0, 0, 1))
		if z.Magnitude < 1e-4 then
			z = x:Cross(Vector3.new(1, 0, 0))
		end
	end
	z = z.Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

-- Углы в градусах -> поворот. Порядок YXZ: сначала рыскание (Y), затем тангаж (X), затем крен (Z).
-- x > 0 — наклон вперёд-вверх вокруг локальной оси X (по правилу правой руки), y — поворот влево, z — крен влево.
function MathX.angles(xDeg: number, yDeg: number, zDeg: number): CFrame
	return CFrame.fromEulerAnglesYXZ(rad(xDeg), rad(yDeg), rad(zDeg))
end

------------------------------------------------------------------------------------------
-- Шум
------------------------------------------------------------------------------------------

-- Фрактальный шум (-1..1 примерно). seed разводит независимые каналы.
function MathX.fbm(x: number, seed: number, octaves: number?): number
	local sum: number, amp: number, freq: number, norm: number = 0, 1, 1, 0
	for _ = 1, octaves or 3 do
		sum += math.noise(x * freq, seed * 1.618 + 0.5, seed * 0.37 + 11.3) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.03
	end
	return sum / norm * 1.6
end

-- Детерминированное псевдослучайное число 0..1 по целому ключу (без состояния — годится для перемотки)
function MathX.hash01(n: number): number
	local s = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return s - math.floor(s)
end

-- Детерминированный ГПСЧ (для сборки моделей в Lune и в Roblox одинаково)
export type Rng = { next: (self: Rng) -> number, range: (self: Rng, a: number, b: number) -> number, int: (self: Rng, a: number, b: number) -> number }

function MathX.rng(seed: number): Rng
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	function r.next(_self: Rng): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
	function r.range(self: Rng, a: number, b: number): number
		return a + (b - a) * self:next()
	end
	function r.int(self: Rng, a: number, b: number): number
		return math.floor(a + (b - a + 1) * self:next())
	end
	return (r :: any) :: Rng
end

return MathX
