--!strict
-- Общие константы ролика «Aura Farmer».

local Config = {}

-- Длина ролика (как в референсе: последний кадр трона — 15.633 с). После конца — чёрный кадр.
Config.Duration = 15.667
Config.BlackFrom = 15.633

-- Частота «запекания» анимаций в KeyframeSequence (кадров в секунду).
Config.BakeFPS = 30

-- Порядок планов (модули в Shots/).
Config.ShotOrder = { "S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10", "S11" }

-- Начала координат декораций. Земля (песок/трава/пол) на высоте Y = 0 относительно начала.
-- Декорации разнесены далеко, чтобы не попадать в кадр друг друга.
Config.Sets = {
	Beach = CFrame.new(0, 0, 0),
	Park = CFrame.new(0, 0, 9000),
	Gym = CFrame.new(9000, 0, 9000),
	Throne = CFrame.new(-9000, 0, 9000),
}

-- Свойства Terrain (ставятся сервером при запуске).
Config.Terrain = {
	Decoration = true,
	WaterColor = Color3.fromRGB(36, 104, 120),
	WaterReflectance = 0.6,
	WaterTransparency = 0.35,
	WaterWaveSize = 0.18,
	WaterWaveSpeed = 12,
}

-- Мировая точка в декорации: x вправо (+X), y вверх, z (+Z «назад», -Z «вперёд/на север»).
function Config.at(set: string, x: number, y: number, z: number): Vector3
	return (Config.Sets[set] * CFrame.new(x, y, z)).Position
end

-- Постановка персонажа: точка на земле между стопами (x, z) и поворот (градусы, вокруг Y).
-- yaw = 0 — персонаж смотрит в -Z; yaw = 90 — в -X; yaw = 180 — в +Z; yaw = -90 — в +X.
function Config.place(set: string, x: number, z: number, yawDeg: number, y: number?): CFrame
	return Config.Sets[set] * CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

return Config
