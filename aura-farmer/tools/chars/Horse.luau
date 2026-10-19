--!nocheck
-- ВРЕМЕННАЯ заглушка коня (грубые формы) — будет заменена детальной моделью.
local roblox = require("@lune/roblox")
local V = roblox.Vector3.new
local Color3 = roblox.Color3
local Skel = require("./HorseSkeleton")

return function(opts)
	local rig = Skel.new("Horse")
	local P = rig.P
	local fur = Color3.fromRGB(52, 36, 28)
	local suit = Color3.fromRGB(88, 70, 200)
	rig:ellipsoid("UpperTorso", V(0, 4.0, 0), V(2.3, 2.0, 1.3), suit, "Fabric")
	rig:ellipsoid("LowerTorso", V(0, 2.9, 0), V(2.1, 0.9, 1.2), Color3.fromRGB(110, 150, 210), "Fabric")
	rig:ellipsoid("Head", V(0, 5.6, -0.1), V(0.9, 1.4, 0.9), fur, "Carpet")
	rig:ellipsoid("Head", V(0, 6.1, -0.6), V(1.0, 0.9, 1.3), fur, "Carpet")
	rig:ellipsoid("Head", V(0, 5.85, -1.2), V(0.8, 0.7, 0.9), fur, "Carpet")
	rig:ellipsoid("Jaw", V(0, 5.6, -1.0), V(0.7, 0.3, 0.9), fur, "Carpet")
	for _, s in { "Right", "Left" } do
		local x = if s == "Right" then 1 else -1
		rig:ellipsoid(s .. "UpperArm", V(x * P.shoulderX, P.shoulderY - 0.6, 0), V(0.6, 1.4, 0.6), suit, "Fabric")
		rig:ellipsoid(s .. "LowerArm", V(x * P.shoulderX, P.shoulderY - 1.85, 0), V(0.5, 1.3, 0.5), suit, "Fabric")
		rig:ellipsoid(s .. "Hand", V(x * P.shoulderX, P.shoulderY - 2.7, 0), V(0.3, 0.55, 0.55), fur, "Carpet")
		for _, f in { "Index", "Middle", "Ring", "Pinky", "Thumb" } do
			rig:ellipsoid(s .. f .. "1", rig.rest[s .. f .. "1"].Position, V(0.13, 0.27, 0.13), fur, "Carpet")
			rig:ellipsoid(s .. f .. "2", rig.rest[s .. f .. "2"].Position, V(0.12, 0.23, 0.12), fur, "Carpet")
		end
		rig:ellipsoid(s .. "UpperLeg", V(x * P.hipX, 2.0, 0), V(0.75, 1.4, 0.75), Color3.fromRGB(110, 150, 210), "Fabric")
		rig:ellipsoid(s .. "LowerLeg", V(x * P.hipX, 0.85, 0), V(0.65, 1.25, 0.65), Color3.fromRGB(110, 150, 210), "Fabric")
		rig:ellipsoid(s .. "Foot", V(x * P.hipX, 0.15, -0.2), V(0.7, 0.3, 1.2), Color3.fromRGB(20, 20, 20), "Leather")
	end
	return rig
end
