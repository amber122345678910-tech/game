--!nocheck
-- Мини-фреймворк для тестов на Lune.
local T = {}
T.passed = 0
T.failed = 0

function T.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		T.passed += 1
	else
		T.failed += 1
		print("FAIL: " .. name .. "\n  " .. tostring(err))
	end
end

function T.eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end

function T.near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then
		error(string.format("%s: expected ~%s, got %s", msg or "near", tostring(b), tostring(a)), 2)
	end
end

function T.truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

function T.falsy(v, msg)
	if v then
		error(msg or "expected falsy", 2)
	end
end

function T.summary(): boolean
	print(string.format("%d passed, %d failed", T.passed, T.failed))
	return T.failed == 0
end

return T
