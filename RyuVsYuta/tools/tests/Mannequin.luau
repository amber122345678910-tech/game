--!nocheck
-- Простой манекен для проверки скелета/IK/превиза
local Sculpt = require(script.Parent.Parent.Parent.src.shared.Builders.Sculpt)
local Skeletons = require(script.Parent.Parent.Parent.src.shared.Skeletons)
local Rig = require(script.Parent.Parent.Parent.src.shared.Rig)
local M = {}
function M.build(origin, rigName)
	local def = Skeletons[rigName or "Ryu"]
	local ctx = Sculpt.newCharacter(rigName or "Mannequin", def, origin)
	local col = Color3.fromRGB(220, 200, 180)
	for i, b in def.bones do
		local p = def.parentIndex[i]
		if p ~= 0 then
			local parentName = def.bones[p].name
			local a = Vector3.zero
			local tip = b.offset.Position
			if tip.Magnitude > 0.05 then
				Sculpt.segment(ctx, parentName, a, tip, 0.18, 0.18, col)
			end
		end
	end
	local hs = def.lengths.Neck and def.lengths.Neck * 2.4 or 1
	Sculpt.ellipsoid(ctx, "Head", CFrame.new(0, 0.45 * hs, 0), Vector3.new(0.8, 1, 0.9) * hs, col)
	Sculpt.ellipsoid(ctx, "Head", CFrame.new(0, 0.5 * hs, -0.45 * hs), Vector3.new(0.2, 0.2, 0.2) * hs, Color3.new(1, 0, 0))
	Sculpt.strand(ctx, "Head", { Vector3.new(0, 0.9, 0), Vector3.new(0, 1.5, 0.3), Vector3.new(0, 1.8, 1.0) }, { width0 = 0.3, color0 = Color3.new(1, 1, 1), outline = Color3.new(0, 0, 0) })
	return ctx.model
end
return M
