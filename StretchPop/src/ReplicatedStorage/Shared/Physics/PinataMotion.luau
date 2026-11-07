--!strict
-- STRETCH-POP · Движение золотых пиньят.
-- Пиньята плывёт поперёк полосы по синусоиде от общего серверного времени
-- (workspace:GetServerTimeNow()), поэтому все клиенты рисуют её в одной точке, а сервер
-- проверяет пробитие по той же формуле. Сервер сам деталь не двигает: нет сетевого дрожания.

local PinataMotion = {}

export type MotionSpec = {
	Amplitude: number, -- полуразмах вдоль локальной X полосы, studs
	Frequency: number, -- Гц
	Phase: number, -- радианы
}

-- Смещение от базовой точки в локальных осях полосы
function PinataMotion.Offset(spec: MotionSpec, serverTime: number): Vector3
	local angle = 2 * math.pi * spec.Frequency * serverTime + spec.Phase
	return Vector3.new(spec.Amplitude * math.sin(angle), 1.6 * math.sin(angle * 2.3), 0)
end

-- Поза в момент serverTime: сдвиг + лёгкое покачивание (мультяшная «живость»)
function PinataMotion.CFrameAt(base: CFrame, spec: MotionSpec, serverTime: number): CFrame
	local angle = 2 * math.pi * spec.Frequency * serverTime + spec.Phase
	local sway = math.rad(14) * math.cos(angle)
	local wobble = math.rad(6) * math.sin(angle * 3.1)
	return base * CFrame.new(PinataMotion.Offset(spec, serverTime)) * CFrame.Angles(wobble, sway, 0)
end

-- Габарит «коридора» движения: бокс детали, растянутый на ±Amplitude по локальной X
function PinataMotion.SweepSize(size: Vector3, spec: MotionSpec): Vector3
	return size + Vector3.new(spec.Amplitude * 2, 3.2, 0)
end

-- Читает параметры движения из атрибутов детали (их ставит LevelBuilder)
function PinataMotion.FromAttributes(part: Instance): (CFrame?, MotionSpec?)
	local base = part:GetAttribute("BaseCFrame")
	local amplitude = part:GetAttribute("Amplitude")
	local frequency = part:GetAttribute("Frequency")
	local phase = part:GetAttribute("Phase")
	if typeof(base) ~= "CFrame" or typeof(amplitude) ~= "number" or typeof(frequency) ~= "number" or typeof(phase) ~= "number" then
		return nil, nil
	end
	return base, { Amplitude = amplitude, Frequency = frequency, Phase = phase }
end

return PinataMotion
