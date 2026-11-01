--!nocheck
-- Tests for src/shared/Util/* (Signal, Trove, Spring, MathUtil, TableUtil, Rng, Geometry).
-- Rng golden values were produced by an independent Python implementation (exact 32-bit integers),
-- so they prove the Luau double/bit32 arithmetic is exact (=> identical sequences in Roblox and Lune).
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function U(Loader, name)
	return Loader.require("ReplicatedStorage.Shared.Util." .. name)
end

local function vnear(T, a, b, eps, msg)
	eps = eps or 1e-4
	local d = (a - b).Magnitude
	return T.ok(d <= eps, (msg or "vectors differ") .. (" (got %s, expected %s, |d|=%g)"):format(tostring(a), tostring(b), d))
end

local function isFinite(x)
	return x == x and x ~= math.huge and x ~= -math.huge
end

local tests = {}

-- Rng -----------------------------------------------------------------------------------------------

local GOLDEN = {
	{ 0, { 628536190, 1778826032, 2276654518, 4190711461, 972076964 } },
	{ 1, { 2344621659, 4069116248, 1645832203, 2416382896, 149842050 } },
	{ 42, { 350440284, 3662042560, 2131501457, 145782416, 1025342686 } },
	{ -7, { 4119930690, 3731597302, 2444126770, 314439371, 1187222267 } },
	{ 123456789012, { 1948357701, 3895134134, 822757885, 592771294, 795833563 } },
	{ 0.5, { 483151621, 1130376862, 3822049148, 124643038, 2113630534 } },
	{ "daily-7", { 1796071554, 3631622014, 2813338803, 592088726, 932817410 } },
}

function tests.rng_golden_sequences(T, Loader)
	local Rng = U(Loader, "Rng")
	for _, case in GOLDEN do
		local r = Rng.new(case[1])
		for i, expected in case[2] do
			T.eq(r:NextU32(), expected, ("seed %s output %d"):format(tostring(case[1]), i))
		end
	end
	T.eq(Rng.Hash(1, 2), 1667472528, "Hash(1,2)")
	T.eq(Rng.Hash("abc"), 2138547952, "Hash('abc')")
	T.eq(Rng.Hash(1.25, "x", -3), 4014388403, "Hash(1.25,'x',-3)")
	local r = Rng.new(2024)
	local ints = { 72, 78, 66, 21, 67, 63, 90, 71, 65, 92 }
	for i, v in ints do
		T.eq(r:Integer(1, 100), v, "Integer golden " .. i)
	end
	local r2 = Rng.new(99)
	T.near(r2:Number(), 0.12995040614528142, 1e-15, "Number golden 1")
	T.near(r2:Number(), 0.0657327938238047, 1e-15, "Number golden 2")
	T.near(r2:Number(), 0.12010481836330056, 1e-15, "Number golden 3")
end

function tests.rng_determinism_clone_state(T, Loader)
	local Rng = U(Loader, "Rng")
	local a, b = Rng.new(777), Rng.new(777)
	for _ = 1, 200 do
		T.eq(a:NextU32(), b:NextU32(), "same seed same sequence")
	end
	local c, d = Rng.new(1), Rng.new(2)
	T.ok(c:NextU32() ~= d:NextU32(), "different seeds differ")
	T.ok(Rng.new(nil):NextU32() == Rng.new(0):NextU32(), "nil seed == 0")
	local src = Rng.new("clone")
	src:Number()
	local copy = src:Clone()
	local st = Rng.fromState(src:State())
	for _ = 1, 50 do
		local v = src:NextU32()
		T.eq(copy:NextU32(), v, "clone continues")
		T.eq(st:NextU32(), v, "fromState continues")
	end
	-- outputs are always 32-bit integers
	local r = Rng.new(5)
	for _ = 1, 500 do
		local v = r:NextU32()
		if not T.ok(v >= 0 and v < 4294967296 and v % 1 == 0, "u32 range " .. v) then
			break
		end
	end
end

function tests.rng_ranges(T, Loader)
	local Rng = U(Loader, "Rng")
	local r = Rng.new(31337)
	local okNum, okMinMax, okMax = true, true, true
	for _ = 1, 2000 do
		local x = r:Number()
		okNum = okNum and x >= 0 and x < 1
		local y = r:Number(-3, 5)
		okMinMax = okMinMax and y >= -3 and y < 5
		local z = r:Number(10)
		okMax = okMax and z >= 0 and z < 10
	end
	T.ok(okNum, "Number() in [0,1)")
	T.ok(okMinMax, "Number(min,max) in range")
	T.ok(okMax, "Number(max) in [0,max)")
	local seen = {}
	local inRange = true
	for _ = 1, 600 do
		local v = r:Integer(1, 6)
		inRange = inRange and v >= 1 and v <= 6 and v % 1 == 0
		seen[v] = (seen[v] or 0) + 1
	end
	T.ok(inRange, "Integer(1,6) inclusive range")
	for face = 1, 6 do
		T.ok((seen[face] or 0) > 60, "die face " .. face .. " appears ~100 times, got " .. tostring(seen[face]))
	end
	T.eq(r:Integer(4, 4), 4, "min == max")
	local swapped = r:Integer(10, 1)
	T.ok(swapped >= 1 and swapped <= 10, "swapped bounds")
	local big = r:Integer(0, 2 ^ 40)
	T.ok(big >= 0 and big <= 2 ^ 40 and big % 1 == 0, "range > 2^32")
	T.eq(r.NextNumber, r.Number, "NextNumber alias")
	T.eq(r.NextInteger, r.Integer, "NextInteger alias")
	-- Bool probability
	local hits = 0
	for _ = 1, 4000 do
		if r:Bool(0.25) then
			hits += 1
		end
	end
	T.ok(hits > 850 and hits < 1150, "Bool(0.25) ~1000/4000, got " .. hits)
	T.ok(not Rng.new(1):Bool(0), "Bool(0) is always false")
end

function tests.rng_collections(T, Loader)
	local Rng = U(Loader, "Rng")
	local r = Rng.new(9)
	T.eq(r:Pick({}), nil, "Pick empty")
	local list = { "a", "b", "c" }
	local picked = {}
	for _ = 1, 100 do
		picked[r:Pick(list)] = true
	end
	T.ok(picked.a and picked.b and picked.c, "Pick reaches every element")
	local arr = {}
	for i = 1, 20 do
		arr[i] = i
	end
	local same = r:Shuffle(arr)
	T.ok(same == arr, "Shuffle is in place and returns the list")
	local sum, seenAll = 0, {}
	for _, v in arr do
		sum += v
		seenAll[v] = true
	end
	T.eq(sum, 210, "Shuffle keeps elements")
	local count = 0
	for _ in seenAll do
		count += 1
	end
	T.eq(count, 20, "Shuffle is a permutation")
	local x1 = Rng.new(3):Shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })
	local x2 = Rng.new(3):Shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })
	T.eq(table.concat(x1, ","), table.concat(x2, ","), "Shuffle deterministic")
	-- WeightedIndex
	T.eq(r:WeightedIndex({ 0, 0 }), nil, "all-zero weights -> nil")
	T.eq(r:WeightedIndex({}), nil, "empty weights -> nil")
	local counts = { 0, 0, 0 }
	for _ = 1, 3000 do
		local i = r:WeightedIndex({ 1, 0, 3 })
		counts[i] += 1
	end
	T.eq(counts[2], 0, "zero weight never chosen")
	T.ok(counts[3] > 2 * counts[1], "weight 3 chosen ~3x weight 1 (" .. counts[1] .. " vs " .. counts[3] .. ")")
	-- geometry helpers
	local okUnit, okCircle = true, true
	local sx, sz = 0, 0
	for _ = 1, 1000 do
		local v = r:UnitVector()
		okUnit = okUnit and math.abs(v.Magnitude - 1) < 1e-5
		local x, z = r:InCircle(3)
		okCircle = okCircle and (x * x + z * z) <= 9 + 1e-9
		sx += x
		sz += z
	end
	T.ok(okUnit, "UnitVector has length 1")
	T.ok(okCircle, "InCircle inside radius")
	T.ok(math.abs(sx / 1000) < 0.3 and math.abs(sz / 1000) < 0.3, "InCircle centred")
end

-- MathUtil --------------------------------------------------------------------------------------------

function tests.mathutil_scalars(T, Loader)
	local M = U(Loader, "MathUtil")
	T.near(M.lerp(2, 10, 0.25), 4)
	T.near(M.inverseLerp(2, 10, 4), 0.25)
	T.eq(M.inverseLerp(3, 3, 7), 0, "inverseLerp degenerate")
	T.eq(M.clamp(5, 0, 1), 1)
	T.eq(M.clamp(-5, 0, 1), 0)
	T.eq(M.clamp(5, 10, 0), 5, "clamp with swapped bounds")
	T.near(M.remap(5, 0, 10, 100, 200), 150)
	T.near(M.remap(20, 0, 10, 100, 200), 300, nil, "remap extrapolates")
	T.near(M.remap(20, 0, 10, 100, 200, true), 200, nil, "remap clamped")
	T.eq(M.smoothstep(0, 1, -1), 0)
	T.eq(M.smoothstep(0, 1, 2), 1)
	T.near(M.smoothstep(0, 1, 0.5), 0.5)
	T.near(M.smootherstep(0, 1, 0.5), 0.5)
	T.near(M.smoothstep(10, 20, 12.5), 0.15625)
	T.eq(M.round(2.4), 2)
	T.eq(M.round(2.5), 3)
	T.eq(M.round(-2.5), -2, "halves round toward +inf")
	T.near(M.round(7.3, 0.5), 7.5)
	T.near(M.round(7.2, 0.5), 7)
	T.eq(M.round(3.3, 0), 3.3, "step 0 = identity")
	T.eq(M.sign(-3), -1)
	T.eq(M.sign(0), 0)
	T.eq(M.sign(4), 1)
	T.eq(M.approach(0, 10, 3), 3)
	T.eq(M.approach(9, 10, 3), 10, "approach does not overshoot")
	T.eq(M.approach(10, 0, -4), 6, "approach uses |maxDelta|")
	T.near(M.wrapAngle(3 * math.pi), math.pi)
	T.near(M.wrapAngle(-math.pi), math.pi, nil, "-pi wraps to pi")
	T.near(M.wrapAngle(0.5), 0.5)
	T.near(M.wrapAngle(-7), -7 + 2 * math.pi)
	local inRange = true
	for i = -50, 50 do
		local w = M.wrapAngle(i * 0.37)
		inRange = inRange and w > -math.pi and w <= math.pi
	end
	T.ok(inRange, "wrapAngle range (-pi, pi]")
	T.near(M.angleDiff(math.rad(170), math.rad(-170)), math.rad(20), 1e-9, "angleDiff takes the short way")
	T.near(M.angleDiff(math.rad(-170), math.rad(170)), math.rad(-20), 1e-9)
	T.near(M.lerpAngle(math.rad(170), math.rad(-170), 0.5), math.rad(180), 1e-9, "lerpAngle across the seam")
	T.eq(M.expAlpha(5, 0), 0)
	T.near(M.expAlpha(1, 1), 1 - math.exp(-1))
	T.near(M.damp(0, 10, 1, 1), 10 * (1 - math.exp(-1)))
	-- frame-rate independence: two half steps == one full step
	local a = M.damp(M.damp(0, 10, 3, 0.05), 10, 3, 0.05)
	T.near(a, M.damp(0, 10, 3, 0.1), 1e-12, "damp is frame-rate independent")
end

function tests.mathutil_vectors(T, Loader)
	local M = U(Loader, "MathUtil")
	vnear(T, M.flat(Vector3.new(1, 5, -2)), Vector3.new(1, 0, -2))
	vnear(T, M.safeUnit(Vector3.new(3, 0, 4)), Vector3.new(0.6, 0, 0.8))
	vnear(T, M.safeUnit(Vector3.zero), Vector3.zero, nil, "safeUnit(0) -> zero")
	vnear(T, M.safeUnit(Vector3.zero, Vector3.new(0, 0, -1)), Vector3.new(0, 0, -1), nil, "safeUnit fallback")
	vnear(T, M.flatUnit(Vector3.new(0, 9, 2)), Vector3.new(0, 0, 1))
	vnear(T, M.lerpVector(Vector3.zero, Vector3.new(2, 4, 6), 0.5), Vector3.new(1, 2, 3))
	for _, yaw in { 0, 0.5, -1.2, 3, -3 } do
		local look = CFrame.Angles(0, yaw, 0).LookVector
		T.near(M.yawFromVector(look), M.wrapAngle(yaw), 1e-5, "yawFromVector inverts CFrame.Angles yaw " .. yaw)
		local cf = M.cframeFromYaw(Vector3.new(1, 2, 3), yaw)
		vnear(T, cf.LookVector, look, 1e-5, "cframeFromYaw look")
		vnear(T, cf.Position, Vector3.new(1, 2, 3), 1e-5, "cframeFromYaw position")
	end
	local cf = M.lerpCFrame(CFrame.new(0, 0, 0), CFrame.new(10, 0, 0), 0.3)
	vnear(T, cf.Position, Vector3.new(3, 0, 0))
	local dcf = M.dampCFrame(CFrame.new(), CFrame.new(10, 0, 0), 1, 1)
	T.near(dcf.Position.X, 10 * (1 - math.exp(-1)), 1e-4)
	local Rng = U(Loader, "Rng")
	local rng = Rng.new(4)
	local inside = true
	for _ = 1, 300 do
		local p = M.randomInCircle(rng, 5)
		inside = inside and p.Y == 0 and p.Magnitude <= 5 + 1e-4
	end
	T.ok(inside, "randomInCircle inside radius, y = 0")
	local p1 = M.randomInCircle(Rng.new(8), 2)
	local p2 = M.randomInCircle(Rng.new(8), 2)
	vnear(T, p1, p2, 0, "randomInCircle deterministic with Rng")
	local shim = Loader.Random.new(3) -- Roblox Random-like object
	T.noerror(function()
		M.randomInCircle(shim, 1)
	end, "randomInCircle accepts Random")
end

function tests.mathutil_easing(T, Loader)
	local M = U(Loader, "MathUtil")
	local styles = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Back", "Elastic", "Bounce", "Expo", "Circ" }
	local dirs = { "In", "Out", "InOut" }
	for _, style in styles do
		T.ok(M.IsEasingStyle(style), style .. " is a style")
		for _, dir in dirs do
			local tag = style .. "/" .. dir
			T.eq(M.Ease(0, style, dir), 0, tag .. " at 0")
			T.eq(M.Ease(1, style, dir), 1, tag .. " at 1")
			T.eq(M.Ease(-1, style, dir), 0, tag .. " clamps below")
			T.eq(M.Ease(2, style, dir), 1, tag .. " clamps above")
			-- continuity (no jumps): Circ has a vertical tangent at the end, hence the loose bound
			local prev = M.Ease(0, style, dir)
			local jump = 0
			for i = 1, 2000 do
				local v = M.Ease(i / 2000, style, dir)
				jump = math.max(jump, math.abs(v - prev))
				prev = v
			end
			T.ok(jump < 0.05, tag .. " is continuous (max step " .. jump .. ")")
		end
		-- Out is the mirror of In
		for i = 1, 9 do
			local t = i / 10
			T.near(M.Ease(t, style, "Out"), 1 - M.Ease(1 - t, style, "In"), 1e-9, style .. " Out mirrors In")
		end
		if style ~= "Elastic" then
			T.near(M.Ease(0.5, style, "InOut"), 0.5, 1e-9, style .. " InOut midpoint")
		end
	end
	-- reference values (easings.net / Roblox curves)
	T.near(M.Ease(0.5, "Quad", "In"), 0.25, 1e-12)
	T.near(M.Ease(0.5, "Quad", "Out"), 0.75, 1e-12)
	T.near(M.Ease(0.25, "Cubic", "InOut"), 0.0625, 1e-12)
	T.near(M.Ease(0.5, "Sine", "In"), 1 - math.cos(math.pi / 4), 1e-12)
	T.near(M.Ease(0.5, "Expo", "In"), 2 ^ -5, 1e-12)
	T.near(M.Ease(0.5, "Circ", "In"), 1 - math.sqrt(0.75), 1e-12)
	T.near(M.Ease(0.5, "Bounce", "Out"), 0.765625, 1e-12)
	T.near(M.Ease(0.5, "Elastic", "Out"), 1.015625, 1e-9)
	T.near(M.Ease(0.75, "Quart", "Out"), 1 - 0.25 ^ 4, 1e-12)
	T.near(M.Ease(0.5, "Back", "In"), 2.70158 * 0.125 - 1.70158 * 0.25, 1e-12)
	local minBack = 1
	for i = 0, 100 do
		minBack = math.min(minBack, M.Ease(i / 100, "Back", "In"))
	end
	T.ok(minBack < -0.09 and minBack > -0.11, "Back In undershoots ~-0.1, got " .. minBack)
	-- defaults, aliases, enums, unknown
	T.near(M.Ease(0.5, "Quad"), 0.75, 1e-12, "default direction is Out")
	T.near(M.Ease(0.3, "Exponential", "In"), M.Ease(0.3, "Expo", "In"), 1e-12, "Exponential alias")
	T.near(M.Ease(0.3, "Circular", "Out"), M.Ease(0.3, "Circ", "Out"), 1e-12, "Circular alias")
	T.near(M.Ease(0.5, roblox.Enum.EasingStyle.Quad, roblox.Enum.EasingDirection.In), 0.25, 1e-12, "EnumItems accepted")
	T.near(M.Ease(0.37, "Nope", "In"), 0.37, 1e-12, "unknown style -> Linear")
	T.ok(not M.IsEasingStyle("Nope"), "IsEasingStyle rejects unknown")
	T.ok(M.IsEasingStyle(roblox.Enum.EasingStyle.Exponential), "IsEasingStyle accepts EnumItem")
	T.eq(M.Ease(0 / 0, "Quad", "In"), 0, "NaN alpha -> 0")
end

-- TableUtil -------------------------------------------------------------------------------------------

function tests.tableutil_copy_merge(T, Loader)
	local TU = U(Loader, "TableUtil")
	local inner = { 1, 2 }
	local src = { a = 1, inner = inner }
	local shallow = TU.copy(src)
	T.ok(shallow ~= src and shallow.inner == inner, "copy is shallow")
	local deep = TU.deepCopy(src)
	T.ok(deep.inner ~= inner and deep.inner[2] == 2, "deepCopy copies nested")
	local cyc = { name = "c" }
	cyc.self = cyc
	local cycCopy = TU.deepCopy(cyc)
	T.ok(cycCopy.self == cycCopy and cycCopy ~= cyc, "deepCopy keeps cycles")
	local m = TU.merge({ a = 1, b = 2 }, { b = 3, c = 4 })
	T.ok(m.a == 1 and m.b == 3 and m.c == 4, "merge")
	local A = { s = { x = 1, y = 2 }, k = 1 }
	local B = { s = { y = 20, z = 30 }, k = { deep = true } }
	local dm = TU.deepMerge(A, B)
	T.ok(dm.s.x == 1 and dm.s.y == 20 and dm.s.z == 30, "deepMerge nested")
	T.ok(type(dm.k) == "table" and dm.k.deep, "deepMerge replaces non-table")
	T.ok(A.s.y == 2 and A.s.z == nil and B.s.x == nil, "deepMerge leaves inputs untouched")
	T.ok(dm.k ~= B.k, "deepMerge deep-copies b's tables")
end

function tests.tableutil_queries(T, Loader)
	local TU = U(Loader, "TableUtil")
	local t = { a = 1, b = 2, c = 3 }
	T.eq(#TU.keys(t), 3)
	T.eq(#TU.values(t), 3)
	T.eq(TU.count(t), 3)
	T.eq(TU.count({ 1, 2, x = 3 }), 3, "count array + hash")
	T.eq(table.concat(TU.sortedKeys({ b = 1, a = 2, [2] = 0, [1] = 0 }), ","), "1,2,a,b", "sortedKeys numbers first")
	local doubled = TU.map(t, function(v)
		return v * 2
	end)
	T.ok(doubled.a == 2 and doubled.c == 6, "map")
	local odd = TU.filter({ 1, 2, 3, 4, 5 }, function(v)
		return v % 2 == 1
	end)
	T.eq(table.concat(odd, ","), "1,3,5", "filter keeps order")
	local fd = TU.filterDict(t, function(v)
		return v >= 2
	end)
	T.ok(fd.a == nil and fd.b == 2 and fd.c == 3, "filterDict")
	local v, k = TU.find({ 5, 6, 7 }, 6)
	T.ok(v == 6 and k == 2, "find by value")
	local v2, k2 = TU.find({ x = 1, y = 9 }, function(val)
		return val > 5
	end)
	T.ok(v2 == 9 and k2 == "y", "find by predicate")
	T.eq(TU.find({ 1 }, 99), nil, "find missing -> nil")
	T.ok(TU.deepEquals({ a = { 1, 2 }, b = "x" }, { b = "x", a = { 1, 2 } }), "deepEquals equal")
	T.ok(not TU.deepEquals({ a = { 1, 2 } }, { a = { 1, 3 } }), "deepEquals different")
	T.ok(not TU.deepEquals({ a = 1 }, { a = 1, b = 2 }), "deepEquals extra key")
	T.ok(TU.isArray({ 1, 2, 3 }) and TU.isArray({}), "isArray")
	T.ok(not TU.isArray({ 1, 2, x = 1 }), "isArray mixed")
	T.eq(table.concat(TU.slice({ 1, 2, 3, 4, 5 }, 2, 4), ","), "2,3,4", "slice")
	T.eq(table.concat(TU.slice({ 1, 2, 3, 4, 5 }, -2), ","), "4,5", "slice negative")
	T.eq(table.concat(TU.reverse({ 1, 2, 3 }), ","), "3,2,1", "reverse")
end

function tests.tableutil_shuffle_reconcile_freeze(T, Loader)
	local TU = U(Loader, "TableUtil")
	local Rng = U(Loader, "Rng")
	local list = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
	local s1 = TU.shuffle(list, Rng.new(12))
	local s2 = TU.shuffle(list, Rng.new(12))
	T.eq(table.concat(s1, ","), table.concat(s2, ","), "shuffle deterministic with Rng")
	T.eq(table.concat(list, ","), "1,2,3,4,5,6,7,8,9,10", "shuffle does not mutate input")
	table.sort(s1)
	T.eq(table.concat(s1, ","), "1,2,3,4,5,6,7,8,9,10", "shuffle is a permutation")
	T.noerror(function()
		TU.shuffle(list, Loader.Random.new(1))
	end, "shuffle accepts Random")
	T.fails(function()
		TU.shuffle(list, nil)
	end, "shuffle requires an rng")
	-- reconcile = profile migration
	local template = {
		Version = 2,
		Gold = 0,
		Stats = { Wins = 0, Kills = 0 },
		Settings = { Volume = 0.5 },
		List = { 1, 2 },
	}
	local profile = { Gold = 55, Stats = { Wins = 3 }, Settings = "corrupt" }
	local out = TU.reconcile(profile, template)
	T.ok(out == profile, "reconcile returns target")
	T.eq(profile.Gold, 55, "existing value kept")
	T.eq(profile.Version, 2, "missing value filled")
	T.eq(profile.Stats.Wins, 3, "nested existing kept")
	T.eq(profile.Stats.Kills, 0, "nested missing filled")
	T.eq(profile.Settings, "corrupt", "type mismatch keeps existing value")
	T.ok(profile.List ~= template.List and profile.List[2] == 2, "filled tables are deep copies")
	template.Stats.Kills = 99
	T.eq(profile.Stats.Kills, 0, "template mutation does not leak")
	-- freezeDeep
	local data = { a = { b = { c = 1 } }, list = { 1, 2 } }
	data.a.b.back = data
	TU.freezeDeep(data)
	T.ok(table.isfrozen(data) and table.isfrozen(data.a) and table.isfrozen(data.a.b) and table.isfrozen(data.list), "freezeDeep freezes all levels")
	T.fails(function()
		data.a.b.c = 2
	end, "frozen table rejects writes")
	T.noerror(function()
		TU.freezeDeep(data)
	end, "freezeDeep twice is fine")
end

-- Signal ----------------------------------------------------------------------------------------------

function tests.signal_basics(T, Loader)
	local Signal = U(Loader, "Signal")
	local s = Signal.new()
	local log = {}
	local c1 = s:Connect(function(a, b)
		table.insert(log, "1:" .. tostring(a) .. tostring(b))
	end)
	s:Connect(function(a)
		table.insert(log, "2:" .. tostring(a))
	end)
	T.ok(s:HasConnections(), "HasConnections")
	s:Fire("x", "y")
	T.eq(table.concat(log, ","), "1:xy,2:x", "handlers called in connection order with args")
	T.ok(c1.Connected, "Connected true")
	c1:Disconnect()
	T.ok(not c1.Connected, "Connected false after Disconnect")
	c1:Disconnect() -- double disconnect is harmless
	log = {}
	s:Fire(1)
	T.eq(table.concat(log, ","), "2:1", "disconnected handler not called")
	local onceCount = 0
	local oc = s:Once(function()
		onceCount += 1
	end)
	s:Fire()
	s:Fire()
	T.eq(onceCount, 1, "Once fires once")
	T.ok(not oc.Connected, "Once connection disconnects itself")
	-- nil holes in arguments are preserved
	local got
	s:Connect(function(...)
		got = table.pack(...)
	end)
	s:Fire(nil, 2, nil)
	T.ok(got.n == 3 and got[2] == 2, "varargs with nils preserved")
	s:DisconnectAll()
	T.ok(not s:HasConnections(), "DisconnectAll")
	local after = false
	s:Connect(function()
		after = true
	end)
	s:Destroy()
	s:Fire()
	T.ok(not after, "Destroy disconnects")
	local dead = s:Connect(function() end)
	T.ok(not dead.Connected, "Connect after Destroy returns a dead connection")
end

function tests.signal_reentrancy(T, Loader)
	local Signal = U(Loader, "Signal")
	local s = Signal.new()
	local log = {}
	local cB
	s:Connect(function()
		table.insert(log, "A")
		cB:Disconnect() -- disconnect a LATER handler during Fire
	end)
	cB = s:Connect(function()
		table.insert(log, "B")
	end)
	s:Connect(function()
		table.insert(log, "C")
	end)
	s:Fire()
	T.eq(table.concat(log, ""), "AC", "handler disconnected mid-Fire is skipped")
	-- self-disconnect + connect during fire
	local s2 = Signal.new()
	local log2 = {}
	local selfConn
	selfConn = s2:Connect(function()
		table.insert(log2, "self")
		selfConn:Disconnect()
	end)
	s2:Connect(function()
		table.insert(log2, "next")
		if #log2 < 3 then
			s2:Connect(function()
				table.insert(log2, "late")
			end)
		end
	end)
	s2:Fire()
	T.eq(table.concat(log2, ","), "self,next", "connect during Fire is not called by that Fire")
	s2:Fire()
	T.eq(table.concat(log2, ","), "self,next,next,late", "late handler called on next Fire")
	-- re-entrant Fire
	local s3 = Signal.new()
	local depth, calls = 0, 0
	s3:Connect(function(n)
		calls += 1
		if n > 0 then
			depth = math.max(depth, n)
			s3:Fire(n - 1)
		end
	end)
	s3:Fire(3)
	T.eq(calls, 4, "re-entrant Fire works")
	-- disconnect everything (incl. the running handler) mid-Fire, then connect again
	local s4 = Signal.new()
	local log4 = {}
	s4:Connect(function()
		table.insert(log4, 1)
		s4:DisconnectAll()
		s4:Connect(function()
			table.insert(log4, 3)
		end)
	end)
	s4:Connect(function()
		table.insert(log4, 2)
	end)
	s4:Fire()
	T.eq(table.concat(log4, ","), "1", "DisconnectAll mid-Fire stops later handlers")
	s4:Fire()
	T.eq(table.concat(log4, ","), "1,3", "new handler after DisconnectAll works")
end

function tests.signal_yield_and_wait(T, Loader)
	local Signal = U(Loader, "Signal")
	local s = Signal.new()
	local order = {}
	s:Connect(function()
		table.insert(order, "yielder-start")
		task.wait(0.01) -- yields this handler's coroutine only
		table.insert(order, "yielder-end")
	end)
	s:Connect(function()
		table.insert(order, "second")
	end)
	s:Fire()
	T.eq(table.concat(order, ","), "yielder-start,second", "a yielding handler does not block the next one")
	-- Wait
	local received
	task.spawn(function()
		received = table.pack(s:Wait())
	end)
	T.eq(received, nil, "Wait is pending before Fire")
	s:Fire("hello", 7)
	T.ok(received ~= nil and received[1] == "hello" and received[2] == 7, "Wait returns the Fire arguments")
	-- Wait is one-shot: its internal connection is gone
	s:Fire("again")
	T.ok(received[1] == "hello", "Wait does not receive later Fires")
	task.wait(0.03)
	T.eq(order[#order], "yielder-end", "yielded handler resumed later")
end

-- Trove -----------------------------------------------------------------------------------------------

function tests.trove_cleanup(T, Loader)
	local Trove = U(Loader, "Trove")
	local Signal = U(Loader, "Signal")
	local trove = Trove.new()
	local order = {}
	trove:Add(function()
		table.insert(order, "f1")
	end)
	trove:Add(function()
		table.insert(order, "f2")
	end)
	local folder = roblox.Instance.new("Folder")
	local part = roblox.Instance.new("Part")
	part.Parent = folder
	trove:Add(part)
	local destroyed = false
	trove:Add({
		Destroy = function()
			destroyed = true
		end,
	})
	local disconnected = false
	trove:Add({
		Disconnect = function()
			disconnected = true
		end,
	})
	local custom = false
	trove:Add({
		Cancel = function()
			custom = true
		end,
	}, "Cancel")
	local sig = Signal.new()
	local fired = 0
	local conn = trove:Connect(sig, function()
		fired += 1
	end)
	sig:Fire()
	local thread = task.delay(100, function() end)
	trove:Add(thread)
	T.eq(trove:Count(), 8, "Count")
	trove:Clean()
	T.eq(table.concat(order, ","), "f2,f1", "functions called, newest first")
	T.eq(part.Parent, nil, "Instance destroyed")
	T.ok(destroyed and disconnected and custom, "table Destroy/Disconnect/custom method")
	T.ok(not conn.Connected, "Connect-ed connection disconnected")
	sig:Fire()
	T.eq(fired, 1, "handler gone after Clean")
	T.eq(coroutine.status(thread), "dead", "thread cancelled")
	T.eq(trove:Count(), 0, "empty after Clean")
	-- reusable
	local again = false
	trove:Add(function()
		again = true
	end)
	trove:Destroy()
	T.ok(again, "trove reusable; Destroy cleans")
end

function tests.trove_remove_extend_errors(T, Loader)
	local Trove = U(Loader, "Trove")
	local trove = Trove.new()
	local removed = 0
	local fn = function()
		removed += 1
	end
	trove:Add(fn)
	T.ok(trove:Remove(fn), "Remove returns true")
	T.eq(removed, 1, "Remove cleans immediately")
	trove:Clean()
	T.eq(removed, 1, "removed object not cleaned twice")
	T.ok(not trove:Remove(fn), "Remove unknown -> false")
	local child = trove:Extend()
	local childCleaned = false
	child:Add(function()
		childCleaned = true
	end)
	trove:Clean()
	T.ok(childCleaned, "Extend child cleaned with parent")
	-- error isolation
	Loader.quietWarnings = true
	local ran = false
	trove:Add(function()
		ran = true
	end)
	trove:Add(function()
		error("boom")
	end)
	T.noerror(function()
		trove:Clean()
	end, "Clean survives a failing cleanup")
	Loader.quietWarnings = false
	T.ok(ran, "other cleanups still ran")
	T.fails(function()
		trove:Add(123)
	end, "Add rejects unknown types")
	T.fails(function()
		trove:Add(nil)
	end, "Add rejects nil")
	-- cleanup that adds more objects while cleaning
	local late = false
	trove:Add(function()
		trove:Add(function()
			late = true
		end)
	end)
	trove:Clean()
	T.ok(late, "objects added during Clean are cleaned too")
end

-- Spring ----------------------------------------------------------------------------------------------

-- Reference: RK4 integration of x'' = -w^2 (x - target) - 2 z w x' with a tiny step.
local function rk4(x, v, target, w, z, duration)
	local h = 1e-4
	local steps = math.floor(duration / h + 0.5)
	local function acc(px, pv)
		return -w * w * (px - target) - 2 * z * w * pv
	end
	for _ = 1, steps do
		local k1x, k1v = v, acc(x, v)
		local k2x, k2v = v + k1v * h / 2, acc(x + k1x * h / 2, v + k1v * h / 2)
		local k3x, k3v = v + k2v * h / 2, acc(x + k2x * h / 2, v + k2v * h / 2)
		local k4x, k4v = v + k3v * h, acc(x + k3x * h, v + k3v * h)
		x += (k1x + 2 * k2x + 2 * k3x + k4x) * h / 6
		v += (k1v + 2 * k2v + 2 * k3v + k4v) * h / 6
	end
	return x, v
end

function tests.spring_matches_ode(T, Loader)
	local Spring = U(Loader, "Spring")
	for _, z in { 0, 0.3, 1 - 1e-7, 1, 1 + 1e-7, 1 + 5e-5, 1.02, 2.5 } do
		local s = Spring.new(0, 8, z)
		s.Target = 10
		s.Velocity = 3
		local px, pv = s:Update(0.37), s.Velocity
		local rx, rv = rk4(0, 3, 10, 8, z, 0.37)
		T.near(px, rx, 1e-6, "position matches ODE, damping " .. z)
		T.near(pv, rv, 1e-5, "velocity matches ODE, damping " .. z)
	end
	local a, b, c, d = Spring.Coefficients(12, 0.4, 0)
	T.ok(a == 1 and b == 0 and c == 0 and d == 1, "coefficients at t=0 are identity")
end

function tests.spring_convergence_and_large_dt(T, Loader)
	local Spring = U(Loader, "Spring")
	-- critically damped: no overshoot, converges
	local s = Spring.new(0, 10)
	s.Target = 10
	local maxPos = 0
	for _ = 1, 200 do
		maxPos = math.max(maxPos, s:Update(1 / 60))
	end
	T.ok(maxPos <= 10 + 1e-9, "critical spring never overshoots (max " .. maxPos .. ")")
	T.near(s.Position, 10, 1e-3, "critical spring converged after ~3.3 s")
	-- dt = 0.5 frame hitches: stable for every damping (bounded, finite, converging)
	for _, z in { 0.05, 0.3, 1, 3 } do
		local sp = Spring.new(0, 30, z)
		sp.Target = 1
		local finite, bounded = true, true
		for _ = 1, 40 do
			local p = sp:Update(0.5)
			finite = finite and isFinite(p) and isFinite(sp.Velocity)
			bounded = bounded and math.abs(p - 1) <= 1 + 1e-9
		end
		T.ok(finite, "dt=0.5 finite, damping " .. z)
		T.ok(bounded, "dt=0.5 bounded by the initial offset, damping " .. z)
		T.near(sp.Position, 1, 1e-3, "dt=0.5 converges, damping " .. z)
	end
	-- exact composition: 1 step of 1 s == 100 steps of 0.01 s
	local one = Spring.new(0, 6, 0.4)
	one.Target, one.Velocity = 5, -2
	local many = Spring.new(0, 6, 0.4)
	many.Target, many.Velocity = 5, -2
	one:Update(1)
	for _ = 1, 100 do
		many:Update(0.01)
	end
	T.near(one.Position, many.Position, 1e-9, "analytic step is exact for any dt")
	T.near(one.Velocity, many.Velocity, 1e-8)
	-- huge dt
	local huge = Spring.new(3, 5, 0.2)
	huge.Target = -4
	huge:Update(1e4)
	T.near(huge.Position, -4, 1e-9, "dt=1e4 lands on target")
	T.ok(isFinite(huge.Velocity), "dt=1e4 finite velocity")
	T.ok(huge:IsSettled(), "IsSettled")
	-- underdamped overshoots, overdamped does not and is slower than critical
	local under = Spring.new(0, 10, 0.3)
	under.Target = 1
	local over = Spring.new(0, 10, 3)
	over.Target = 1
	local crit = Spring.new(0, 10, 1)
	crit.Target = 1
	local maxUnder, maxOver = 0, 0
	for _ = 1, 120 do
		maxUnder = math.max(maxUnder, under:Update(1 / 60))
		maxOver = math.max(maxOver, over:Update(1 / 60))
	end
	for _ = 1, 30 do
		crit:Update(1 / 60)
	end
	T.ok(maxUnder > 1.2, "damping 0.3 overshoots (max " .. maxUnder .. ")")
	T.ok(maxOver <= 1 + 1e-9, "damping 3 never overshoots")
	local over2 = Spring.new(0, 10, 3)
	over2.Target = 1
	for _ = 1, 30 do
		over2:Update(1 / 60)
	end
	T.ok(over2.Position < crit.Position, "overdamped is slower than critical")
	-- no spring force: coast
	local coast = Spring.new(0, 0)
	coast.Velocity = 2
	coast:Update(1.5)
	T.near(coast.Position, 3, 1e-12, "speed 0 coasts")
	-- dt <= 0 is a no-op
	local still = Spring.new(1, 10)
	still.Target = 5
	T.eq(still:Update(0), 1, "dt=0 no-op")
	T.eq(still:Update(-1), 1, "negative dt no-op")
end

function tests.spring_vectors_impulse_reset(T, Loader)
	local Spring = U(Loader, "Spring")
	local s = Spring.new(Vector3.zero, 15, 0.6)
	vnear(T, s.Velocity, Vector3.zero, 0, "Vector3 spring starts at rest")
	s.Target = Vector3.new(4, -2, 8)
	for _ = 1, 600 do
		s:Update(1 / 60)
	end
	vnear(T, s.Position, Vector3.new(4, -2, 8), 1e-3, "Vector3 spring converges")
	s:Impulse(Vector3.new(0, 50, 0))
	T.ok(s.Velocity.Y > 49, "Impulse adds velocity")
	s:Update(0.05)
	T.ok(s.Position.Y > -2, "Impulse moves the spring")
	s:Reset(Vector3.new(1, 1, 1))
	vnear(T, s.Position, Vector3.new(1, 1, 1), 0, "Reset position")
	vnear(T, s.Target, Vector3.new(1, 1, 1), 0, "Reset target")
	vnear(T, s.Velocity, Vector3.zero, 0, "Reset velocity")
	s.Target = Vector3.new(2, 2, 2)
	s:Reset()
	vnear(T, s.Position, Vector3.new(2, 2, 2), 0, "Reset() snaps to target")
	-- Step helper matches the object
	local obj = Spring.new(0, 9, 0.5)
	obj.Target = 3
	obj:Update(0.2)
	local p, v = Spring.Step(0, 0, 3, 9, 0.5, 0.2)
	T.near(p, obj.Position, 1e-12, "Step == Update position")
	T.near(v, obj.Velocity, 1e-12, "Step == Update velocity")
	local v2 = Spring.new(roblox.Vector2.new(0, 0), 10)
	v2.Target = roblox.Vector2.new(3, 4)
	v2:Update(5)
	T.near(v2.Position.X, 3, 1e-4, "Vector2 spring")
end

-- Geometry --------------------------------------------------------------------------------------------

function tests.geometry_ellipsoid(T, Loader)
	local G = U(Loader, "Geometry")
	vnear(T, G.direction(0, 0), Vector3.new(0, 0, -1), 1e-9, "yaw 0 = front (-Z)")
	vnear(T, G.direction(90, 0), Vector3.new(1, 0, 0), 1e-9, "yaw +90 = right (+X)")
	vnear(T, G.direction(-90, 0), Vector3.new(-1, 0, 0), 1e-9, "yaw -90 = left (-X)")
	vnear(T, G.direction(180, 0), Vector3.new(0, 0, 1), 1e-9, "yaw 180 = back (+Z)")
	vnear(T, G.direction(37, 90), Vector3.new(0, 1, 0), 1e-9, "pitch 90 = top")
	-- sphere
	local p, n = G.ellipsoidPoint(CFrame.new(), Vector3.new(2, 2, 2), 30, 20)
	vnear(T, p, G.direction(30, 20) * 2, 1e-5, "sphere point")
	vnear(T, n, G.direction(30, 20), 1e-5, "sphere normal = direction")
	-- ellipsoid: on the surface, radial, normal orthogonal to the surface tangents
	local radii = Vector3.new(1, 2, 3)
	for _, ang in { { 0, 0 }, { 45, 30 }, { -120, -60 }, { 170, 10 }, { 10, 89 } } do
		local yaw, pitch = ang[1], ang[2]
		local q, nn = G.ellipsoidPoint(CFrame.new(), radii, yaw, pitch)
		local f = (q.X / 1) ^ 2 + (q.Y / 2) ^ 2 + (q.Z / 3) ^ 2
		T.near(f, 1, 1e-4, ("on surface yaw %d pitch %d"):format(yaw, pitch))
		T.near(q.Unit:Dot(G.direction(yaw, pitch)), 1, 1e-5, "radial projection")
		T.near(nn.Magnitude, 1, 1e-5, "unit normal")
		T.ok(nn:Dot(q) > 0, "normal points outward")
		local h = 0.1 -- central differences (float32 Vector3 precision)
		local ty = G.ellipsoidPoint(CFrame.new(), radii, yaw + h, pitch) - G.ellipsoidPoint(CFrame.new(), radii, yaw - h, pitch)
		local tp = G.ellipsoidPoint(CFrame.new(), radii, yaw, pitch + h) - G.ellipsoidPoint(CFrame.new(), radii, yaw, pitch - h)
		if ty.Magnitude > 1e-6 then
			T.ok(math.abs(ty.Unit:Dot(nn)) < 2e-3, "normal orthogonal to yaw tangent")
		end
		T.ok(math.abs(tp.Unit:Dot(nn)) < 2e-3, "normal orthogonal to pitch tangent")
	end
	-- world transform
	local cf = CFrame.new(5, 6, 7) * CFrame.Angles(0.3, 1.1, -0.4)
	local lp, ln = G.ellipsoidPoint(CFrame.new(), radii, 40, -25)
	local wp, wn = G.ellipsoidPoint(cf, radii, 40, -25)
	vnear(T, wp, cf:PointToWorldSpace(lp), 1e-4, "world point = cf * local point")
	vnear(T, wn, cf:VectorToWorldSpace(ln), 1e-4, "world normal rotated")
end

function tests.geometry_surface_cframe(T, Loader)
	local G = U(Loader, "Geometry")
	local radii = Vector3.new(1.2, 1, 0.9)
	local center = CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.7, 0)
	for _, ang in { { 0, 0 }, { 60, 20 }, { -60, 20 }, { 120, -40 }, { 0, 90 }, { 45, 90 }, { 0, -90 } } do
		local yaw, pitch = ang[1], ang[2]
		local cf = G.surfaceCFrame(center, radii, yaw, pitch)
		local p, n = G.ellipsoidPoint(center, radii, yaw, pitch)
		local tag = ("yaw %d pitch %d"):format(yaw, pitch)
		vnear(T, cf.Position, p, 1e-4, "on surface " .. tag)
		vnear(T, cf.LookVector, n, 1e-4, "LookVector = outward normal " .. tag)
		T.near(cf.RightVector:Dot(cf.UpVector), 0, 1e-5, "orthogonal " .. tag)
		T.near(cf.UpVector.Magnitude, 1, 1e-5, "unit up " .. tag)
		vnear(T, cf.RightVector:Cross(cf.UpVector), -cf.LookVector, 1e-4, "right-handed " .. tag)
		T.ok(isFinite(cf.UpVector.X) and isFinite(cf.UpVector.Z), "finite up " .. tag)
	end
	-- front point keeps the centre orientation
	local front = G.surfaceCFrame(center, radii, 0, 0)
	vnear(T, front.UpVector, center.UpVector, 1e-5, "front: up = centre up")
	vnear(T, front.RightVector, center.RightVector, 1e-5, "front: right = centre right")
	-- pole continuity
	local nearPole = G.surfaceCFrame(CFrame.new(), Vector3.one, 30, 89.9)
	local pole = G.surfaceCFrame(CFrame.new(), Vector3.one, 30, 90)
	vnear(T, nearPole.UpVector, pole.UpVector, 1e-2, "up vector continuous at the top pole")
	local nearBottom = G.surfaceCFrame(CFrame.new(), Vector3.one, -50, -89.9)
	local bottom = G.surfaceCFrame(CFrame.new(), Vector3.one, -50, -90)
	vnear(T, nearBottom.UpVector, bottom.UpVector, 1e-2, "up vector continuous at the bottom pole")
	-- offset and roll
	local base = G.surfaceCFrame(center, radii, 30, 10)
	local raised = G.surfaceCFrame(center, radii, 30, 10, 0.25)
	vnear(T, raised.Position, base.Position + base.LookVector * 0.25, 1e-4, "offset moves along the normal")
	local rolled = G.surfaceCFrame(center, radii, 30, 10, 0, 90)
	vnear(T, rolled.LookVector, base.LookVector, 1e-5, "roll keeps LookVector")
	vnear(T, rolled.RightVector, base.UpVector, 1e-5, "positive roll turns Right toward Up")
end

function tests.geometry_segments(T, Loader)
	local G = U(Loader, "Geometry")
	local p, t = G.closestPointOnSegment(Vector3.new(1, 5, 0), Vector3.zero, Vector3.new(0, 10, 0))
	vnear(T, p, Vector3.new(0, 5, 0))
	T.near(t, 0.5)
	p, t = G.closestPointOnSegment(Vector3.new(1, -5, 0), Vector3.zero, Vector3.new(0, 10, 0))
	vnear(T, p, Vector3.zero, nil, "clamped to start")
	T.eq(t, 0)
	p, t = G.closestPointOnSegment(Vector3.new(1, 50, 0), Vector3.zero, Vector3.new(0, 10, 0))
	T.eq(t, 1, "clamped to end")
	p = G.closestPointOnSegment(Vector3.new(3, 3, 3), Vector3.one, Vector3.one)
	vnear(T, p, Vector3.one, nil, "degenerate segment")
	-- segment-segment known cases
	T.near(G.segmentSegmentDistance(Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, -1, 2), Vector3.new(0, 1, 2)), 2, 1e-6, "skew perpendicular")
	T.near(G.segmentSegmentDistance(Vector3.new(0, 0, 0), Vector3.new(0, 10, 0), Vector3.new(3, 2, 0), Vector3.new(3, 5, 0)), 3, 1e-6, "parallel overlapping")
	T.near(G.segmentSegmentDistance(Vector3.new(0, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 4, 0), Vector3.new(0, 9, 0)), 3, 1e-6, "collinear disjoint")
	T.near(G.segmentSegmentDistance(Vector3.new(0, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 1, 0), Vector3.new(5, 1, 0)), 0, 1e-6, "touching")
	T.near(G.segmentSegmentDistance(Vector3.one, Vector3.one, Vector3.new(4, 5, 1), Vector3.new(4, 5, 1)), 5, 1e-6, "two points")
	T.near(G.segmentSegmentDistance(Vector3.new(0, 3, 0), Vector3.new(0, 3, 0), Vector3.new(-5, 0, 0), Vector3.new(5, 0, 0)), 3, 1e-6, "point vs segment")
	-- random segments vs brute force
	local Rng = U(Loader, "Rng")
	local rng = Rng.new(2718)
	local function rv(scale)
		return Vector3.new(rng:Number(-scale, scale), rng:Number(-scale, scale), rng:Number(-scale, scale))
	end
	local worst = 0
	for _ = 1, 60 do
		local p1, q1, p2, q2 = rv(5), rv(5), rv(5), rv(5)
		local d = G.segmentSegmentDistance(p1, q1, p2, q2)
		local best = math.huge
		local N = 60
		for i = 0, N do
			local a = p1:Lerp(q1, i / N)
			local c = G.closestPointOnSegment(a, p2, q2)
			best = math.min(best, (a - c).Magnitude)
		end
		-- exact result can only be <= the sampled minimum, and close to it
		worst = math.max(worst, d - best)
		T.ok(d <= best + 1e-4 and d >= best - 0.25, ("seg-seg %.4f vs sampled %.4f"):format(d, best))
	end
	T.ok(worst <= 1e-4, "segment distance never exceeds brute force")
end

-- independent reference: ternary search of the convex point-box distance along the segment
local function refSegBox(G, a, b, cf, size)
	local lo, hi = 0, 1
	local function f(s)
		return G.pointBoxDistance(a:Lerp(b, s), cf, size)
	end
	for _ = 1, 120 do
		local m1 = lo + (hi - lo) / 3
		local m2 = hi - (hi - lo) / 3
		if f(m1) <= f(m2) then
			hi = m2
		else
			lo = m1
		end
	end
	return math.min(f((lo + hi) / 2), f(0), f(1))
end

function tests.geometry_boxes(T, Loader)
	local G = U(Loader, "Geometry")
	local box = CFrame.new(0, 0, 0)
	local size = Vector3.new(4, 4, 4)
	T.eq(G.pointBoxDistance(Vector3.new(1, 1, 1), box, size), 0, "inside -> 0")
	T.near(G.pointBoxDistance(Vector3.new(5, 0, 0), box, size), 3, 1e-6, "face distance")
	T.near(G.pointBoxDistance(Vector3.new(3, 3, 0), box, size), math.sqrt(2), 1e-6, "edge distance")
	T.near(G.pointBoxDistance(Vector3.new(3, 3, 3), box, size), math.sqrt(3), 1e-6, "corner distance")
	T.ok(G.pointInBox(Vector3.new(2, 2, 2), box, size), "pointInBox boundary counts")
	T.ok(not G.pointInBox(Vector3.new(2.01, 0, 0), box, size), "pointInBox outside")
	-- segment through the box
	T.near(G.segmentBoxDistance(Vector3.new(-10, 0, 0), Vector3.new(10, 0, 0), box, size), 0, 1e-9, "segment through box")
	-- segment passing a corner diagonally
	T.near(G.segmentBoxDistance(Vector3.new(4, -10, 4), Vector3.new(4, 10, 4), box, size), math.sqrt(8), 1e-5, "segment beside an edge")
	-- rotated boxes vs reference
	local Rng = U(Loader, "Rng")
	local rng = Rng.new(161803)
	local function rv(scale)
		return Vector3.new(rng:Number(-scale, scale), rng:Number(-scale, scale), rng:Number(-scale, scale))
	end
	local worst = 0
	for _ = 1, 80 do
		local cf = CFrame.new(rv(3)) * CFrame.Angles(rng:Number(0, 6.3), rng:Number(0, 6.3), rng:Number(0, 6.3))
		local sz = Vector3.new(rng:Number(0.2, 6), rng:Number(0.2, 6), rng:Number(0.2, 6))
		local a, b = rv(8), rv(8)
		if rng:Bool(0.2) then
			b = a -- degenerate segment
		end
		local d = G.segmentBoxDistance(a, b, cf, sz)
		local ref = refSegBox(G, a, b, cf, sz)
		worst = math.max(worst, math.abs(d - ref))
	end
	T.ok(worst < 1e-3, "segment-box distance matches reference (worst error " .. worst .. ")")
end

function tests.geometry_capsules(T, Loader)
	local G = U(Loader, "Geometry")
	local r = 1.1
	local a, b = G.verticalCapsule(Vector3.new(0, 3, 0), 5, r)
	vnear(T, a, Vector3.new(0, 1.6, 0), 1e-6, "verticalCapsule bottom")
	vnear(T, b, Vector3.new(0, 4.4, 0), 1e-6, "verticalCapsule top")
	local ta, tb = G.verticalCapsule(Vector3.zero, 1, 1.1)
	vnear(T, ta, tb, 0, "short capsule collapses to a ball")
	-- capsule vs box: faces, edges, corners (character next to a 4x4x4 crate at origin)
	local box, size = CFrame.new(0, 2, 0), Vector3.new(4, 4, 4)
	local function charAt(x, z)
		return G.verticalCapsule(Vector3.new(x, 3, z), 5, r)
	end
	local ca, cb = charAt(2 + r - 0.01, 0)
	T.ok(G.capsuleVsBox(ca, cb, r, box, size), "touching a face -> hit")
	ca, cb = charAt(2 + r + 0.01, 0)
	T.ok(not G.capsuleVsBox(ca, cb, r, box, size), "just outside a face -> miss")
	local dd = r / math.sqrt(2)
	ca, cb = charAt(2 + dd - 0.01, 2 + dd - 0.01)
	T.ok(G.capsuleVsBox(ca, cb, r, box, size), "near a vertical edge -> hit")
	ca, cb = charAt(2 + dd + 0.01, 2 + dd + 0.01)
	T.ok(not G.capsuleVsBox(ca, cb, r, box, size), "past a vertical edge -> miss (AABB test would hit)")
	-- capsule hovering above the box: bottom cap vs top face
	local ha, hb = G.verticalCapsule(Vector3.new(0, 4 + 2.5 - 0.05, 0), 5, r)
	T.ok(G.capsuleVsBox(ha, hb, r, box, size), "standing on the box -> hit")
	ha, hb = G.verticalCapsule(Vector3.new(0, 4 + 2.5 + 0.05, 0), 5, r)
	T.ok(not G.capsuleVsBox(ha, hb, r, box, size), "hovering above -> miss")
	-- rotated box (45 deg): the corner sticks out to sqrt(2) * 1
	local rot = CFrame.new(0, 2, 0) * CFrame.Angles(0, math.rad(45), 0)
	local thin = Vector3.new(2, 4, 2)
	ca, cb = charAt(math.sqrt(2) + r - 0.01, 0)
	T.ok(G.capsuleVsBox(ca, cb, r, rot, thin), "rotated box corner -> hit")
	ca, cb = charAt(math.sqrt(2) + r + 0.01, 0)
	T.ok(not G.capsuleVsBox(ca, cb, r, rot, thin), "rotated box corner -> miss")
	-- capsule vs ball
	T.ok(G.capsuleVsBall(a, b, r, Vector3.new(2.09, 3, 0), 1), "ball touching the side")
	T.ok(not G.capsuleVsBall(a, b, r, Vector3.new(2.2, 3, 0), 1), "ball just outside")
	T.ok(G.capsuleVsBall(a, b, r, Vector3.new(0, 4.4 + 2.09, 0), 1), "ball on the head cap")
	T.ok(not G.capsuleVsBall(a, b, r, Vector3.new(0, 4.4 + 2.11, 0), 1), "ball above the head")
	-- capsule vs capsule
	local oa, ob = G.verticalCapsule(Vector3.new(2.19, 3, 0), 5, r)
	T.ok(G.capsuleVsCapsule(a, b, r, oa, ob, r), "side by side touching")
	oa, ob = G.verticalCapsule(Vector3.new(2.21, 3, 0), 5, r)
	T.ok(not G.capsuleVsCapsule(a, b, r, oa, ob, r), "side by side apart")
	-- horizontal bone (capsule, radius 0.5) sweeping past the legs: reach = 1.1 + 0.5 = 1.6
	T.ok(G.capsuleVsCapsule(a, b, r, Vector3.new(-5, 1.6, -1.55), Vector3.new(5, 1.6, -1.55), 0.5), "bone at the shins hits")
	T.ok(not G.capsuleVsCapsule(a, b, r, Vector3.new(-5, 1.6, -1.65), Vector3.new(5, 1.6, -1.65), 0.5), "bone passing in front misses")
	-- low bone under the feet: closest point is the bottom cap
	T.ok(not G.capsuleVsCapsule(a, b, r, Vector3.new(-5, -0.05, -0.2), Vector3.new(5, -0.05, -0.2), 0.5), "bone below the feet misses")
end

function tests.geometry_volumes_cones(T, Loader)
	local G = U(Loader, "Geometry")
	local r = 1.1
	local a, b = G.verticalCapsule(Vector3.new(0, 3, 0), 5, r)
	-- SPEC 7.6 volumes
	local ball = { Shape = "Ball", CFrame = CFrame.new(3.0, 3, 0), Size = Vector3.new(4, 4, 4) }
	T.ok(G.capsuleVsVolume(a, b, r, ball), "Ball volume hit (diameter = Size.X)")
	T.ok(not G.capsuleVsVolume(a, b, r, ball, 0.85), "forgiveness scale shrinks the ball")
	local boxVol = { Shape = "Box", CFrame = CFrame.new(3.0, 3, 0), Size = Vector3.new(4, 1, 1) }
	T.ok(G.capsuleVsVolume(a, b, r, boxVol), "Box volume hit")
	T.ok(not G.capsuleVsVolume(a, b, r, boxVol, 0.5), "Box volume scaled -> miss")
	-- capsule volume lying along X (UpVector rotated to +X), Size.Y = total length incl. caps
	local lying = CFrame.new(6.0, 3, 0) * CFrame.Angles(0, 0, math.rad(-90))
	local ca, cb, cr = G.volumeCapsule(lying, Vector3.new(1, 8, 1))
	T.near(cr, 0.5, 1e-9, "volumeCapsule radius = Size.X/2")
	T.near((cb - ca).Magnitude, 7, 1e-4, "volumeCapsule segment = Size.Y - diameter")
	T.near(math.min(ca.X, cb.X), 2.5, 1e-4, "capsule end along UpVector")
	local capVol = { Shape = "Capsule", CFrame = lying, Size = Vector3.new(1, 8, 1) }
	T.ok(not G.capsuleVsVolume(a, b, r, capVol), "segment end 2.5 from the axis, reach 1.6 -> miss")
	capVol.CFrame = CFrame.new(5.0, 3, 0) * CFrame.Angles(0, 0, math.rad(-90))
	T.ok(G.capsuleVsVolume(a, b, r, capVol), "segment end 1.5 from the axis -> hit")
	T.fails(function()
		G.capsuleVsVolume(a, b, r, { Shape = "Cone", CFrame = CFrame.new(), Size = Vector3.one })
	end, "unknown shape errors")
	-- cones
	local apex, dir = Vector3.zero, Vector3.new(0, 0, -1)
	T.ok(G.pointInCone(Vector3.new(0, 0, -10), apex, dir, 35), "on axis")
	T.ok(G.pointInCone(Vector3.new(math.tan(math.rad(34)) * 10, 0, -10), apex, dir, 35), "inside angle")
	T.ok(not G.pointInCone(Vector3.new(math.tan(math.rad(36)) * 10, 0, -10), apex, dir, 35), "outside angle")
	T.ok(not G.pointInCone(Vector3.new(0, 0, 10), apex, dir, 35), "behind")
	T.ok(not G.pointInCone(Vector3.new(0, 0, -30), apex, dir, 35, 28), "beyond range")
	T.ok(G.pointInCone(apex, apex, dir, 10), "apex counts as inside")
	T.ok(not G.pointInCone(Vector3.new(0, 0, -5), apex, Vector3.zero, 10), "zero direction -> false")
	T.ok(G.pointInConeDot(Vector3.new(0, 0, -5), apex, dir * 7, 0.82), "pointInConeDot with non-unit dir")
	T.near(G.flatDistance(Vector3.new(0, 100, 0), Vector3.new(3, -50, 4)), 5, 1e-9, "flatDistance ignores Y")
	T.near(G.flatDistanceSq(Vector3.new(1, 0, 1), Vector3.new(2, 9, 2)), 2, 1e-9, "flatDistanceSq")
end

return tests
