--!strict
-- Колыхание прядей (волосы Рики, мех воротника Рю, волосы Юты) без физики и без состояния:
-- смещение точки — функция времени и её положения, поэтому сцену можно перематывать.
-- Пряди собраны из Beam между Attachment; у каждой точки атрибут Weight (0 у корня, 1 на кончике).

local MathX = require(script.Parent.Parent.Math)

local Hair = {}

export type Params = {
	wind: Vector3, -- направление и сила ветра в осях кости-носителя (студы смещения на кончике)
	lift: Vector3, -- постоянный "подъём" гривы (аниме-вздыбленность), в осях носителя
	turbulence: number, -- амплитуда шума (студы на кончике)
	freq: number, -- частота шума (Гц)
	scale: number, -- пространственный масштаб шума (чем больше, тем мельче волны)
}

local function noiseVec(p: Vector3, t: number, seed: number, freq: number, scale: number): Vector3
	local x = p.X * scale + t * freq
	local y = p.Y * scale - t * freq * 0.7
	local z = p.Z * scale + t * freq * 0.45
	return Vector3.new(
		math.noise(x, y + seed, z) + 0.5 * math.noise(x * 2.1, y * 2.1, z * 2.1 + seed),
		math.noise(y + 31.7, z, x + seed) + 0.5 * math.noise(y * 2.1 + 5.1, z * 2.1, x * 2.1),
		math.noise(z + 17.3 + seed, x, y) + 0.5 * math.noise(z * 2.1, x * 2.1 + 9.3, y * 2.1)
	)
end

-- Смещение точки (в осях носителя) для веса w
function Hair.displace(rest: Vector3, w: number, seed: number, t: number, p: Params): Vector3
	if w <= 0 then
		return Vector3.zero
	end
	-- порывы: медленная модуляция силы ветра
	local gust = 0.75 + 0.35 * math.noise(t * 0.35, seed * 0.05, 3.3)
	local n = noiseVec(rest, t, seed * 0.13, p.freq, p.scale)
	return (p.wind * gust + p.lift + n * p.turbulence) * w
end

-- Новый локальный CFrame точки пряди (ось X — касательная, по ней строит кривую Beam)
function Hair.pointCFrame(restCF: CFrame, w: number, seed: number, t: number, p: Params): CFrame
	local pos = restCF.Position
	local tan = restCF.RightVector
	local d0 = Hair.displace(pos, w, seed, t, p)
	-- касательная по разности смещений чуть дальше по пряди
	local step = 0.35
	local d1 = Hair.displace(pos + tan * step, math.min(1, w + 0.08), seed, t, p)
	local newTan = tan * step + (d1 - d0)
	return MathX.axisX(pos + d0, newTan)
end

return Hair
