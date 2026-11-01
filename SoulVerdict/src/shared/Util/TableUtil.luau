--!strict
-- TableUtil: table helpers. Lune-safe. Functions never mutate their inputs unless the name says so
-- (reconcile, freezeDeep). "Plain table" = any table; metatables are NOT copied by deep operations.
--
--   copy(t) -> t'                         shallow copy
--   deepCopy(t) -> t'                     recursive copy (handles cycles / shared sub-tables)
--   merge(a, b) -> t                      shallow: keys of a, then b overrides
--   deepMerge(a, b) -> t                  recursive merge of plain tables; b wins on conflicts; inputs untouched
--   keys(t) -> {K}   values(t) -> {V}     (order follows iteration order; use sortedKeys for determinism)
--   sortedKeys(t) -> {K}                  keys sorted (numbers before strings, then by value/tostring)
--   count(t) -> number                    number of entries (array + hash part)
--   map(t, fn(v, k) -> v') -> t'          same keys, mapped values (nil results drop the key)
--   filter(list, fn(v, i) -> boolean)     new ARRAY with the elements that pass (order kept)
--   filterDict(t, fn(v, k) -> boolean)    new table with the passing entries (keys kept)
--   find(t, predicateOrValue) -> (v?, k?) first entry whose value == predicateOrValue, or for which the
--                                         predicate(v, k) returns true (array order first)
--   shuffle(list, rng) -> list'           shuffled COPY; rng = Util/Rng (deterministic) or Roblox Random
--   reconcile(target, template) -> target fills MISSING keys of target from template, recursively, with
--                                         deep copies (existing values, even of another type, are kept).
--                                         Used for profile migration. Mutates and returns target.
--   freezeDeep(t) -> t                    table.freeze on t and every nested table (cycle-safe)
--   deepEquals(a, b) -> boolean           structural equality of plain data
--   isArray(t) -> boolean                 keys are exactly 1..#t
--   slice(list, i, j?) -> list'           elements i..j (negative indices count from the end)
--   reverse(list) -> list'                reversed copy

local TableUtil = {}

function TableUtil.copy<T>(t: T): T
	return table.clone(t :: any) :: any
end

local function deepCopyInner(value: any, seen: { [any]: any }): any
	if type(value) ~= "table" then
		return value
	end
	local existing = seen[value]
	if existing ~= nil then
		return existing
	end
	local out: { [any]: any } = {}
	seen[value] = out
	for k, v in value do
		out[deepCopyInner(k, seen)] = deepCopyInner(v, seen)
	end
	return out
end

function TableUtil.deepCopy<T>(t: T): T
	return deepCopyInner(t, {})
end

function TableUtil.merge(a: { [any]: any }, b: { [any]: any }): { [any]: any }
	local out = table.clone(a)
	for k, v in b do
		out[k] = v
	end
	return out
end

local function deepMergeInner(a: { [any]: any }, b: { [any]: any }): { [any]: any }
	local out = deepCopyInner(a, {})
	for k, v in b do
		local current = out[k]
		if type(v) == "table" and type(current) == "table" then
			out[k] = deepMergeInner(current, v)
		else
			out[k] = deepCopyInner(v, {})
		end
	end
	return out
end

function TableUtil.deepMerge(a: { [any]: any }, b: { [any]: any }): { [any]: any }
	return deepMergeInner(a, b)
end

function TableUtil.keys<K, V>(t: { [K]: V }): { K }
	local out: { K } = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

local function keyLess(a: any, b: any): boolean
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		if ta == "number" then
			return true
		elseif tb == "number" then
			return false
		end
		return ta < tb
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

function TableUtil.sortedKeys<K, V>(t: { [K]: V }): { K }
	local out = TableUtil.keys(t)
	table.sort(out, keyLess)
	return out
end

function TableUtil.values<K, V>(t: { [K]: V }): { V }
	local out: { V } = {}
	for _, v in t do
		table.insert(out, v)
	end
	return out
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.map<K, V, R>(t: { [K]: V }, fn: (V, K) -> R): { [K]: R }
	local out: { [K]: R } = {}
	for k, v in t do
		out[k] = fn(v, k)
	end
	return out
end

function TableUtil.filter<V>(list: { V }, predicate: (V, number) -> boolean): { V }
	local out: { V } = {}
	for i, v in ipairs(list) do
		if predicate(v, i) then
			table.insert(out, v)
		end
	end
	return out
end

function TableUtil.filterDict<K, V>(t: { [K]: V }, predicate: (V, K) -> boolean): { [K]: V }
	local out: { [K]: V } = {}
	for k, v in t do
		if predicate(v, k) then
			out[k] = v
		end
	end
	return out
end

function TableUtil.find(t: { [any]: any }, predicateOrValue: any): (any, any)
	if type(predicateOrValue) == "function" then
		for k, v in t do
			if predicateOrValue(v, k) then
				return v, k
			end
		end
	else
		for k, v in t do
			if v == predicateOrValue then
				return v, k
			end
		end
	end
	return nil, nil
end

function TableUtil.shuffle<V>(list: { V }, rng: any): { V }
	assert(rng ~= nil, "TableUtil.shuffle needs an rng (Util/Rng or Random) for determinism")
	local out = table.clone(list)
	local useRng = type(rng) == "table" and rng.Integer ~= nil
	for i = #out, 2, -1 do
		local j = if useRng then rng:Integer(1, i) else rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function reconcileInner(target: { [any]: any }, template: { [any]: any })
	for k, v in template do
		local current = target[k]
		if current == nil then
			target[k] = deepCopyInner(v, {})
		elseif type(current) == "table" and type(v) == "table" then
			reconcileInner(current, v)
		end
	end
end

function TableUtil.reconcile<T>(target: T, template: { [any]: any }): T
	reconcileInner(target :: any, template)
	return target
end

local function freezeInner(t: { [any]: any }, seen: { [any]: boolean })
	if seen[t] then
		return
	end
	seen[t] = true
	for k, v in t do
		if type(k) == "table" then
			freezeInner(k, seen)
		end
		if type(v) == "table" then
			freezeInner(v, seen)
		end
	end
	if not table.isfrozen(t) then
		table.freeze(t)
	end
end

function TableUtil.freezeDeep<T>(t: T): T
	freezeInner(t :: any, {})
	return t
end

local function deepEqualsInner(a: any, b: any, seen: { [any]: any }): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	if seen[a] == b then
		return true -- already being compared further up (cycle)
	end
	seen[a] = b
	for k, v in a do
		if not deepEqualsInner(v, b[k], seen) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function TableUtil.deepEquals(a: any, b: any): boolean
	return deepEqualsInner(a, b, {})
end

function TableUtil.isArray(t: { [any]: any }): boolean
	local n = #t
	local count = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
			return false
		end
		count += 1
	end
	return count == n
end

function TableUtil.slice<V>(list: { V }, i: number, j: number?): { V }
	local n = #list
	local first = if i < 0 then n + i + 1 else i
	local last = j or n
	if last < 0 then
		last = n + last + 1
	end
	first = math.max(first, 1)
	last = math.min(last, n)
	local out: { V } = {}
	for index = first, last do
		table.insert(out, list[index])
	end
	return out
end

function TableUtil.reverse<V>(list: { V }): { V }
	local out: { V } = table.create(#list)
	for index = #list, 1, -1 do
		table.insert(out, list[index])
	end
	return out
end

return TableUtil
