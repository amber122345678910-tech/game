--!strict
-- STRETCH-POP · Кривые Безье: рендер резиновых рук и дуги траектории.
-- Кубика B(t) = (1−t)³P0 + 3(1−t)²tP1 + 3(1−t)t²P2 + t³P3.

local Bezier = {}

function Bezier.Quadratic(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

function Bezier.Cubic(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	local uu = u * u
	local tt = t * t
	return p0 * (uu * u) + p1 * (3 * uu * t) + p2 * (3 * u * tt) + p3 * (tt * t)
end

function Bezier.CubicDerivative(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t)
end

-- Деление кубики де Кастельжо в точке t.
-- Левая половина: p0, a, d, m. Правая: m, e, c, p3. Касательные в m коллинеарны (гладкий стык).
function Bezier.SplitCubic(
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	t: number
): (Vector3, Vector3, Vector3, Vector3, Vector3, Vector3, Vector3)
	local a = p0:Lerp(p1, t)
	local b = p1:Lerp(p2, t)
	local c = p2:Lerp(p3, t)
	local d = a:Lerp(b, t)
	local e = b:Lerp(c, t)
	local m = d:Lerp(e, t)
	return p0, a, d, m, e, c, p3
end

-- Сегмент Эрмита (позиция + скорость на концах, длительность dt) → внутренние контрольные точки кубики.
-- Для параболы (полёт без сопротивления) результат точный, т.к. парабола — полином степени 2.
function Bezier.FromHermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, dt: number): (Vector3, Vector3)
	return p0 + v0 * (dt / 3), p1 - v1 * (dt / 3)
end

-- Точная кубика баллистической дуги p(t) = p0 + v0·t + ½·g·t² на интервале [0, duration].
function Bezier.FromBallistic(
	p0: Vector3,
	v0: Vector3,
	gravity: Vector3,
	duration: number
): (Vector3, Vector3, Vector3, Vector3)
	local p3 = p0 + v0 * duration + gravity * (0.5 * duration * duration)
	local v1 = v0 + gravity * duration
	local c1, c2 = Bezier.FromHermite(p0, v0, p3, v1, duration)
	return p0, c1, c2, p3
end

function Bezier.ApproxLength(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, samples: number): number
	local length = 0
	local previous = p0
	for i = 1, samples do
		local point = Bezier.Cubic(p0, p1, p2, p3, i / samples)
		length += (point - previous).Magnitude
		previous = point
	end
	return length
end

return Bezier
