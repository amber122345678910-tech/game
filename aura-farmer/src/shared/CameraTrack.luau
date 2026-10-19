--!strict
-- Камера плана: ключи (позиция, точка взгляда, FOV, крен, размытие), сплайн Катмулла-Рома,
-- сглаживание на сегмент и «ручная» тряска. Чистая функция времени — работает в Roblox и в Lune.
--
-- shot.camera = {
--   keys = { { t = 3.9, pos = Vector3, look = Vector3, fov = 40, roll = 0, blur = 0, ease = "inout" }, ... },
--   shake = { rot = 0.4, pos = 0.02, freq = 1.2, seed = 1 },   -- градусы / студы / Гц
--   focus = { actor = "Horse", part = "Head" } или число (дистанция фокуса), необязательно
-- }
-- t в ключах — абсолютное время ролика. ease — сглаживание сегмента ОТ этого ключа к следующему.

local MathUtil = require(script.Parent:WaitForChild("Anim"):WaitForChild("MathUtil"))
local Easing = require(script.Parent:WaitForChild("Anim"):WaitForChild("Easing"))

local CameraTrack = {}

export type Result = {
	cframe: CFrame,
	fov: number,
	blur: number,
	focusDistance: number?,
	look: Vector3,
}

local function keyPos(k: any): Vector3
	if k.cf then
		return k.cf.Position
	end
	return k.pos
end

local function keyLook(k: any): Vector3
	if k.cf then
		return k.cf.Position + k.cf.LookVector * (k.lookDist or 10)
	end
	return k.look
end

local function tangent(points: { Vector3 }, times: { number }, i: number): Vector3
	local n = #points
	if n < 2 then
		return Vector3.zero
	end
	local a = points[math.max(i - 1, 1)]
	local b = points[math.min(i + 1, n)]
	local ta = times[math.max(i - 1, 1)]
	local tb = times[math.min(i + 1, n)]
	local dt = tb - ta
	if dt <= 0 then
		return Vector3.zero
	end
	-- Касательная в единицах «на сегмент»: масштабируем на длительность сегмента позже.
	return (b - a) / dt
end

local function numberAt(keys: { any }, field: string, i: number, e: number, default: number): number
	local a = keys[i][field]
	local nextKey = keys[i + 1]
	local b = if nextKey then nextKey[field] else nil
	if a == nil then
		-- взять ближайшее заданное значение слева
		for j = i - 1, 1, -1 do
			if keys[j][field] ~= nil then
				a = keys[j][field]
				break
			end
		end
	end
	a = if a == nil then default else a
	if b == nil then
		b = a
	end
	return a + (b - a) * e
end

function CameraTrack.evaluate(shot: any, t: number): Result
	local cam = shot.camera
	local keys: { any } = cam.keys
	local n = #keys
	local times: { number } = {}
	local pts: { Vector3 } = {}
	local looks: { Vector3 } = {}
	for i, k in keys do
		times[i] = k.t
		pts[i] = keyPos(k)
		looks[i] = keyLook(k)
	end

	local i = MathUtil.findSegment(times, t)
	local pos: Vector3, look: Vector3, e: number
	if n == 1 or t <= times[1] then
		pos, look, e, i = pts[1], looks[1], 0, 1
	elseif t >= times[n] then
		pos, look, e, i = pts[n], looks[n], 0, n
	else
		local t0, t1 = times[i], times[i + 1]
		local u = (t - t0) / (t1 - t0)
		e = Easing.named(keys[i].ease, u)
		local dt = t1 - t0
		if cam.path == "linear" then
			pos = pts[i]:Lerp(pts[i + 1], e)
			look = looks[i]:Lerp(looks[i + 1], e)
		else
			pos = MathUtil.hermiteV(pts[i], tangent(pts, times, i) * dt, pts[i + 1], tangent(pts, times, i + 1) * dt, e)
			look = MathUtil.hermiteV(looks[i], tangent(looks, times, i) * dt, looks[i + 1], tangent(looks, times, i + 1) * dt, e)
		end
	end

	local fov = numberAt(keys, "fov", i, e, 70)
	local roll = numberAt(keys, "roll", i, e, 0)
	local blur = numberAt(keys, "blur", i, e, 0)
	local focusDistance: number? = nil
	if keys[i].focus ~= nil or (keys[i + 1] and keys[i + 1].focus ~= nil) then
		focusDistance = numberAt(keys, "focus", i, e, 20)
	end

	local cf = MathUtil.lookAt(pos, look) * CFrame.Angles(0, 0, math.rad(roll))

	local shake = cam.shake
	if shake then
		local f = shake.freq or 1
		local seed = shake.seed or 1
		local r = math.rad(shake.rot or 0)
		local p = shake.pos or 0
		local x = t * f
		cf = cf
			* CFrame.new(MathUtil.fbm(x, seed + 3) * p, MathUtil.fbm(x, seed + 4) * p, 0)
			* CFrame.Angles(MathUtil.fbm(x, seed) * r, MathUtil.fbm(x, seed + 1) * r, MathUtil.fbm(x, seed + 2) * r * 0.5)
	end

	return { cframe = cf, fov = fov, blur = blur, focusDistance = focusDistance, look = look }
end

return CameraTrack
