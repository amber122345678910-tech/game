--!strict
-- Геометрические помощники без особых случаев (вертикальные отрезки и т.п.).

local Geom = {}

-- CFrame цилиндра между точками a и b: ось X детали идёт вдоль отрезка.
-- (CFrame.lookAt ведёт себя плохо, если отрезок строго вертикальный — здесь это учтено.)
function Geom.axisCFrame(a: Vector3, b: Vector3): (CFrame, number)
	local d = b - a
	local len = d.Magnitude
	local mid = (a + b) / 2
	if len < 1e-6 then
		return CFrame.new(mid), 0
	end
	local x = d / len
	local up = if math.abs(x.Y) < 0.99 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(mid, x, y, z), len
end

return Geom
