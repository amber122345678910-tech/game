--!strict
-- Чистые помощники серверной логики (без require и без инстансов), чтобы их можно было
-- проверять в Lune: tools/tests/server_logic.luau. Все числа приходят параметрами из Config.

local ServerLogic = {}

----------------------------------------------------------------------
-- Числа
----------------------------------------------------------------------

-- Обычное конечное число (не NaN и не бесконечность)
function ServerLogic.isFinite(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Целое конечное число
function ServerLogic.isInteger(v: any): boolean
	return ServerLogic.isFinite(v) and v == math.floor(v)
end

-- Случайное округление: 2.3 -> 2 (70%) или 3 (30%). Среднее не теряется.
function ServerLogic.stochasticRound(x: number, roll: number): number
	local whole = math.floor(x)
	if roll < x - whole then
		return whole + 1
	end
	return whole
end

-- Интервал с разбросом ±share (roll в [0, 1))
function ServerLogic.jitter(base: number, share: number, roll: number): number
	return base * (1 + (roll * 2 - 1) * share)
end

----------------------------------------------------------------------
-- Лимит частоты (ведро токенов)
----------------------------------------------------------------------
export type Bucket = { Tokens: number, Last: number }

function ServerLogic.newBucket(burst: number, now: number): Bucket
	return { Tokens = burst, Last = now }
end

-- Взять один токен. rate — токенов в секунду, burst — ёмкость ведра.
function ServerLogic.take(bucket: Bucket, rate: number, burst: number, now: number): boolean
	local elapsed = math.max(0, now - bucket.Last)
	bucket.Tokens = math.min(burst, bucket.Tokens + elapsed * rate)
	bucket.Last = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

----------------------------------------------------------------------
-- Банка
----------------------------------------------------------------------
export type JarResult = {
	After: number, -- заряд в банке после поимки
	Added: number, -- сколько поместилось (до возможного "лопнула")
	Burst: boolean, -- банка лопнула
	Lost: number, -- потеряно: не поместилось + сгорело при "лопнула"
}

-- Добавить заряд в банку.
--  capacity — 100% банки; allowOver — можно ли перегружать (до capacity × maxFill);
--  risk(fill) — шанс лопнуть для заполнения fill (>1) после поимки; roll в [0, 1);
--  burstKeep — доля заряда, которая остаётся, если банка лопнула.
-- Без перегрузки лишнее просто теряется. Если в банке уже больше предела (перегрузил на
-- другом острове), заряд не убывает — он просто не добавляется.
function ServerLogic.addToJar(
	before: number,
	amount: number,
	capacity: number,
	allowOver: boolean,
	maxFill: number,
	risk: (fill: number) -> number,
	roll: number,
	burstKeep: number
): JarResult
	local limit = if allowOver then capacity * maxFill else capacity
	local amt = math.max(0, amount)
	local after = math.max(before, math.min(before + amt, limit))
	local added = after - before
	local lost = amt - added
	local burst = false
	if allowOver and added > 0 and capacity > 0 and after > capacity then
		if roll < risk(after / capacity) then
			burst = true
			local kept = after * burstKeep
			lost += after - kept
			after = kept
		end
	end
	return { After = after, Added = added, Burst = burst, Lost = lost }
end

----------------------------------------------------------------------
-- Геометрия
----------------------------------------------------------------------

-- Расстояние по горизонтали
function ServerLogic.flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Положение точки относительно отрезка моста (по горизонтали):
--  along — сколько пройдено от начала вдоль моста, side — отступ вбок, length — длина моста.
function ServerLogic.bridgeCoords(pos: Vector3, from: Vector3, to: Vector3): (number, number, number)
	local axis = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = axis.Magnitude
	if length < 1e-6 then
		return 0, ServerLogic.flatDist(pos, from), 0
	end
	local dir = axis / length
	local rel = Vector3.new(pos.X - from.X, 0, pos.Z - from.Z)
	local along = rel:Dot(dir)
	local side = (rel - dir * along).Magnitude
	return along, side, length
end

-- Точка на мосту на расстоянии along от начала (высота — по наклону моста)
function ServerLogic.bridgePoint(from: Vector3, to: Vector3, along: number): Vector3
	local length = ServerLogic.flatDist(from, to)
	if length < 1e-6 then
		return from
	end
	return from:Lerp(to, math.clamp(along / length, 0, 1))
end

-- Внутри ли кольца (по горизонтали в пределах reach, по высоте в пределах height)
function ServerLogic.inRing(pos: Vector3, center: Vector3, reach: number, height: number): boolean
	return ServerLogic.flatDist(pos, center) <= reach and math.abs(pos.Y - center.Y) <= height
end

-- Доля пути бегущего кольца в момент t (0 — появление, 1 — первый удар)
function ServerLogic.runnerShare(spawn: number, firstHit: number, t: number): number
	local span = firstHit - spawn
	if span <= 0 then
		return 1
	end
	return math.clamp((t - spawn) / span, 0, 1)
end

----------------------------------------------------------------------
-- Поимка
----------------------------------------------------------------------

-- Правдоподобно ли время нажатия: не раньше появления кольца, не "из будущего"
-- (больше поправки задержки) и не старше maxAge.
function ServerLogic.tapPlausible(tapTime: number, now: number, spawn: number, maxAge: number, maxAhead: number): boolean
	return tapTime >= spawn and tapTime <= now + maxAhead and now - tapTime <= maxAge
end

-- Новое комбо после оценки (ИДЕАЛЬНО +1, ХОРОШО — без изменений, остальное — сброс)
function ServerLogic.nextCombo(combo: number, grade: string): number
	if grade == "perfect" then
		return combo + 1
	elseif grade == "good" then
		return combo
	end
	return 0
end

return ServerLogic
