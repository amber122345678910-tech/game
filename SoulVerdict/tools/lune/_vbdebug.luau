local Loader = require("./loader")
local Patterns = Loader.require("ReplicatedStorage.Shared.VerdictBox.Patterns")
for _, set in Patterns.SetIds do
	local tl = Patterns.Build(set, 7919 + 13, 7)
	print(set, "introEnd", tl.introEnd, "bullets", #tl.bullets)
	for _, s in tl.segments do
		local n = 0
		for _, b in tl.bullets do if b.t0 >= s.t0 - 0.13 and b.t0 < s.t1 then n += 1 end end
		print(("  %-15s %.2f-%.2f dur %.2f k %.2f mode %s bullets %d"):format(s.name, s.t0, s.t1, s.t1 - s.t0, s.k, s.mode, n))
	end
	for _, m in tl.modes do print(("    mode %.2f %s %s slam=%s %dx%d"):format(m.t, m.mode, m.gravity, tostring(m.slam), m.w, m.h)) end
end
