--!strict
-- Keyframe tracks sampled by time. Values are numbers; interpolation is a
-- monotone cubic (no overshoot), so curves measured from the reference video
-- can be used directly as keyframes.
local Track = {}

export type Track = { ts: { number }, vs: { number }, ms: { number } }

-- keys: { {t, v}, ... } sorted by t
function Track.new(keys: { { number } }): Track
	local n = #keys
	local ts: { number }, vs: { number } = {}, {}
	for i, k in keys do
		ts[i] = k[1]
		vs[i] = k[2]
	end
	-- Fritsch-Carlson monotone tangents
	local ds: { number } = {}
	for i = 1, n - 1 do
		ds[i] = (vs[i + 1] - vs[i]) / (ts[i + 1] - ts[i])
	end
	local ms: { number } = {}
	if n == 1 then
		ms[1] = 0
	else
		ms[1] = ds[1]
		ms[n] = ds[n - 1]
		for i = 2, n - 1 do
			if ds[i - 1] * ds[i] <= 0 then
				ms[i] = 0
			else
				ms[i] = (ds[i - 1] + ds[i]) / 2
			end
		end
		for i = 1, n - 1 do
			if ds[i] == 0 then
				ms[i] = 0
				ms[i + 1] = 0
			else
				local a = ms[i] / ds[i]
				local b = ms[i + 1] / ds[i]
				local s = a * a + b * b
				if s > 9 then
					local tau = 3 / math.sqrt(s)
					ms[i] = tau * a * ds[i]
					ms[i + 1] = tau * b * ds[i]
				end
			end
		end
	end
	return { ts = ts, vs = vs, ms = ms }
end

function Track.sample(tr: Track, t: number): number
	local ts, vs, ms = tr.ts, tr.vs, tr.ms
	local n = #ts
	if n == 0 then
		return 0
	end
	if t <= ts[1] then
		return vs[1]
	end
	if t >= ts[n] then
		-- hold the last slope a little? No: hold the value.
		return vs[n]
	end
	-- binary search
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if ts[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local h = ts[hi] - ts[lo]
	local s = (t - ts[lo]) / h
	local s2, s3 = s * s, s * s * s
	local h00 = 2 * s3 - 3 * s2 + 1
	local h10 = s3 - 2 * s2 + s
	local h01 = -2 * s3 + 3 * s2
	local h11 = s3 - s2
	return h00 * vs[lo] + h10 * h * ms[lo] + h01 * vs[hi] + h11 * h * ms[hi]
end

return Track
