--!strict
-- Взвешенный случайный выбор (редкости, яйца). Чистая логика — покрыта тестами.

local Rng = {}

export type Weighted<T> = { item: T, weight: number }

-- Выбрать элемент по весам. roll в [0, 1) можно передать для тестов.
function Rng.pick<T>(entries: { Weighted<T> }, roll: number?): T
	local total = 0
	for _, e in entries do
		total += math.max(0, e.weight)
	end
	assert(total > 0, "Rng.pick: пустой набор весов")
	local r = (roll or math.random()) * total
	for _, e in entries do
		local w = math.max(0, e.weight)
		if r < w then
			return e.item
		end
		r -= w
	end
	return entries[#entries].item
end

-- Вероятность каждого элемента (для показа шансов в интерфейсе)
function Rng.chances<T>(entries: { Weighted<T> }): { [T]: number }
	local total = 0
	for _, e in entries do
		total += math.max(0, e.weight)
	end
	local out = {}
	for _, e in entries do
		out[e.item] = if total > 0 then math.max(0, e.weight) / total else 0
	end
	return out
end

return Rng
