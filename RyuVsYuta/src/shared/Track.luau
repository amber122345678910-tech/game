--!strict
-- Ключевые кадры. Значения: число, Vector3, CFrame или поза (таблица кость -> {x, y, z [, px, py, pz]}).
-- Между ключами без ease — гладкий сплайн Эрмита (касательные как у Catmull-Rom, на краях — ноль),
-- это даёт естественное движение без рывков на ключах. Если у ключа задан ease, отрезок ДО этого
-- ключа интерполируется этой функцией (как в Roblox TweenService).

local MathX = require(script.Parent.Math)

local Track = {}

export type Key<T> = { t: number, v: T, ease: string? }
export type PoseValue = { [string]: { number } }

local function findSegment<T>(keys: { Key<T> }, t: number): (number, number)
	local n = #keys
	if t <= keys[1].t then
		return 1, 1
	elseif t >= keys[n].t then
		return n, n
	end
	-- бинарный поиск
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if keys[mid].t <= t then
			lo = mid
		else
			hi = mid
		end
	end
	return lo, hi
end

-- Эрмит для скаляров с неравномерным временем
local function hermite(p0: number, p1: number, m0: number, m1: number, h: number, s: number): number
	local s2 = s * s
	local s3 = s2 * s
	return (2 * s3 - 3 * s2 + 1) * p0 + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * p1 + (s3 - s2) * h * m1
end

local function tangent(keys: { Key<number> }, i: number): number
	local n = #keys
	if i <= 1 or i >= n then
		return 0
	end
	local dt = keys[i + 1].t - keys[i - 1].t
	if dt <= 0 then
		return 0
	end
	-- если ключ — локальный экстремум, касательная 0 (без перелёта)
	local a, b, c = keys[i - 1].v, keys[i].v, keys[i + 1].v
	if (b - a) * (c - b) <= 0 then
		return 0
	end
	return (c - a) / dt
end

function Track.number(keys: { Key<number> }, t: number): number
	local i, j = findSegment(keys, t)
	if i == j then
		return keys[i].v
	end
	local a, b = keys[i], keys[j]
	local h = b.t - a.t
	local s = (t - a.t) / h
	if b.ease then
		return a.v + (b.v - a.v) * MathX.ease(b.ease, s)
	end
	return hermite(a.v, b.v, tangent(keys, i), tangent(keys, j), h, s)
end

-- Vector3: по компонентам тем же Эрмитом
function Track.vector(keys: { Key<Vector3> }, t: number): Vector3
	local i, j = findSegment(keys, t)
	if i == j then
		return keys[i].v
	end
	local a, b = keys[i], keys[j]
	local h = b.t - a.t
	local s = (t - a.t) / h
	if b.ease then
		return a.v:Lerp(b.v, MathX.ease(b.ease, s))
	end
	local n = #keys
	local function tan(k: number): Vector3
		if k <= 1 or k >= n then
			return Vector3.zero
		end
		local dt = keys[k + 1].t - keys[k - 1].t
		if dt <= 0 then
			return Vector3.zero
		end
		return (keys[k + 1].v - keys[k - 1].v) / dt
	end
	local m0, m1 = tan(i), tan(j)
	local s2 = s * s
	local s3 = s2 * s
	return a.v * (2 * s3 - 3 * s2 + 1) + m0 * (h * (s3 - 2 * s2 + s)) + b.v * (-2 * s3 + 3 * s2) + m1 * (h * (s3 - s2))
end

-- CFrame: позиция — Эрмитом, поворот — сферической интерполяцией (Lerp) со сглаживанием
function Track.cframe(keys: { Key<CFrame> }, t: number): CFrame
	local i, j = findSegment(keys, t)
	if i == j then
		return keys[i].v
	end
	local a, b = keys[i], keys[j]
	local s = (t - a.t) / (b.t - a.t)
	local e = if b.ease then MathX.ease(b.ease, s) else MathX.smoothstep(s)
	return a.v:Lerp(b.v, e)
end

-- Поза: каждый канал каждой кости — отдельная числовая дорожка (кость, отсутствующая в ключе, = 0)
function Track.pose(keys: { Key<PoseValue> }, t: number, out: { [string]: CFrame }?): { [string]: CFrame }
	local result = out or {}
	local i, j = findSegment(keys, t)
	local n = #keys
	-- набор костей сегмента (и соседей для касательных)
	local bones: { [string]: boolean } = {}
	for k = math.max(1, i - 1), math.min(n, j + 1) do
		for name in keys[k].v do
			bones[name] = true
		end
	end
	local a, b = keys[i], keys[j]
	local h = b.t - a.t
	local s = if h > 0 then (t - a.t) / h else 0
	local function ch(k: number, name: string, c: number): number
		local v = keys[k].v[name]
		return if v then (v[c] or 0) else 0
	end
	local function tan(k: number, name: string, c: number): number
		if k <= 1 or k >= n then
			return 0
		end
		local dt = keys[k + 1].t - keys[k - 1].t
		if dt <= 0 then
			return 0
		end
		local p0, p1, p2 = ch(k - 1, name, c), ch(k, name, c), ch(k + 1, name, c)
		if (p1 - p0) * (p2 - p1) <= 0 then
			return 0
		end
		return (p2 - p0) / dt
	end
	local eased = if b.ease then MathX.ease(b.ease, s) else -1
	for name in bones do
		local vals = table.create(6, 0)
		for c = 1, 6 do
			local v0, v1 = ch(i, name, c), ch(j, name, c)
			if i == j or h <= 0 then
				vals[c] = v0
			elseif eased >= 0 then
				vals[c] = v0 + (v1 - v0) * eased
			else
				vals[c] = hermite(v0, v1, tan(i, name, c), tan(j, name, c), h, s)
			end
		end
		local cf = MathX.angles(vals[1], vals[2], vals[3])
		if vals[4] ~= 0 or vals[5] ~= 0 or vals[6] ~= 0 then
			cf = CFrame.new(vals[4], vals[5], vals[6]) * cf
		end
		result[name] = cf
	end
	return result
end

-- Сложение двух поз: base * add (add — слой поверх, например дыхание или дрожь)
function Track.layer(base: { [string]: CFrame }, add: { [string]: CFrame }): { [string]: CFrame }
	for name, cf in add do
		local b = base[name]
		base[name] = if b then b * cf else cf
	end
	return base
end

return Track
