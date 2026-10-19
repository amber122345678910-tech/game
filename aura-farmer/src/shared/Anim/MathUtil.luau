--!strict
-- Общая математика для анимации и камеры. Работает и в Roblox, и в Lune (сборка/превью).
-- ВАЖНО: в Lune CFrame.lookAt неверен вдоль оси Z, поэтому lookAt собираем через fromMatrix.

local M = {}

local UP = Vector3.new(0, 1, 0)

function M.lookAt(pos: Vector3, target: Vector3, up: Vector3?): CFrame
	local d = target - pos
	if d.Magnitude < 1e-6 then
		return CFrame.new(pos)
	end
	local f = d.Unit
	local u = up or UP
	local r = f:Cross(u)
	if r.Magnitude < 1e-4 then
		r = f:Cross(Vector3.new(0, 0, 1))
		if r.Magnitude < 1e-4 then
			r = f:Cross(Vector3.new(1, 0, 0))
		end
	end
	r = r.Unit
	local u2 = r:Cross(f)
	return CFrame.fromMatrix(pos, r, u2, -f)
end

-- Поворот, переводящий единичный вектор a в единичный вектор b по кратчайшей дуге.
function M.fromTo(a: Vector3, b: Vector3): CFrame
	local c = a:Cross(b)
	local d = a:Dot(b)
	if d > 0.999999 then
		return CFrame.new()
	end
	if d < -0.999999 then
		local axis = a:Cross(Vector3.new(1, 0, 0))
		if axis.Magnitude < 1e-4 then
			axis = a:Cross(Vector3.new(0, 0, 1))
		end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(c.Unit, math.acos(math.clamp(d, -1, 1)))
end

function M.rotOnly(cf: CFrame): CFrame
	return cf - cf.Position
end

function M.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function M.clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

function M.smoothstep(x: number): number
	x = M.clamp01(x)
	return x * x * (3 - 2 * x)
end

-- Кубический Эрмит для чисел.
function M.hermite(p0: number, m0: number, p1: number, m1: number, t: number): number
	local t2, t3 = t * t, t * t * t
	return (2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1
end

function M.hermiteV(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return p0 * (2 * t3 - 3 * t2 + 1) + m0 * (t3 - 2 * t2 + t) + p1 * (-2 * t3 + 3 * t2) + m1 * (t3 - t2)
end

-- Сглаженный шум [-1,1] (Перлин из стандартной библиотеки Luau).
function M.noise(x: number, seed: number): number
	return math.clamp(math.noise(x, seed * 13.37 + 0.5, seed * 7.1 + 0.25) * 1.8, -1, 1)
end

-- Сумма октав для «ручной» тряски камеры.
function M.fbm(x: number, seed: number): number
	return M.noise(x, seed) * 0.6 + M.noise(x * 2.13 + 11.7, seed + 1) * 0.3 + M.noise(x * 4.37 + 3.1, seed + 2) * 0.1
end

-- Индекс сегмента в отсортированном массиве времён: times[i] <= t < times[i+1].
function M.findSegment(times: { number }, t: number): number
	local n = #times
	if n == 0 or t <= times[1] then
		return 1
	end
	if t >= times[n] then
		return n
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

return M
