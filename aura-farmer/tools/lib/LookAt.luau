--!nocheck
-- Правильный CFrame.lookAt для Lune (встроенный в Lune 0.10 ошибается: вдоль Z и в наклонных направлениях).
-- Поведение как в Roblox: LookVector = (target - at).Unit, «вверх» по up (по умолчанию +Y).
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

return function(at, target, up)
	local d = target - at
	if d.Magnitude < 1e-9 then
		return CFrame.new(at)
	end
	local f = d.Unit
	local u = up or Vector3.new(0, 1, 0)
	local r = f:Cross(u)
	if r.Magnitude < 1e-6 then
		r = f:Cross(Vector3.new(0, 0, 1))
		if r.Magnitude < 1e-6 then
			r = f:Cross(Vector3.new(1, 0, 0))
		end
	end
	r = r.Unit
	return CFrame.fromMatrix(at, r, r:Cross(f), -f)
end
