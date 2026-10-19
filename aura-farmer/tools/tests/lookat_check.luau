--!nocheck
local roblox = require("@lune/roblox")
local V = roblox.Vector3.new
local lookAt = require("../lib/LookAt")
for _, b in { V(0, 0, 1), V(1, 0, 0), V(0.15, 1, -0.1), V(1, 0.5, -2), V(0, -1, 0) } do
	local cf = lookAt(V(0, 0, 0), b)
	assert(cf.LookVector:Dot(b.Unit) > 0.9999, "lookAt wrong for " .. tostring(b))
end
print("lookAt OK")
