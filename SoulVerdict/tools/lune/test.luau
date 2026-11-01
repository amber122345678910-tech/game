--!nocheck
-- Tiny assertion library for Lune tests.
local T = {}
T.failures = {}
T.count = 0
T.current = "?"

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function T.ok(cond, msg)
	T.count += 1
	if not cond then
		table.insert(T.failures, T.current .. ": " .. (msg or "assertion failed"))
	end
	return cond
end

function T.eq(a, b, msg)
	return T.ok(a == b, (msg or "expected equal") .. " (got " .. fmt(a) .. ", expected " .. fmt(b) .. ")")
end

function T.near(a, b, eps, msg)
	eps = eps or 1e-4
	return T.ok(type(a) == "number" and math.abs(a - b) <= eps, (msg or "expected near") .. " (got " .. fmt(a) .. ", expected " .. fmt(b) .. ")")
end

function T.noerror(fn, msg)
	local ok, err = pcall(fn)
	T.ok(ok, (msg or "unexpected error") .. ": " .. tostring(err))
	return ok
end

function T.fails(fn, msg)
	local ok = pcall(fn)
	return T.ok(not ok, msg or "expected an error")
end

return T
