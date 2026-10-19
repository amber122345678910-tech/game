--!strict
-- S04 (3.867–4.967 с): Нижний ракурс, солнце сзади: конь поворачивает голову и показывает большим пальцем назад.
-- Постановка: конь стоит у кромки воды, камера смотрит в сторону моря (пирс справа-сзади), солнце за головой.
-- Камера и солнце заданы в пространстве персонажа (x вправо, y вверх, f вперёд; финальный торс смотрит в −Z).
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local YAW = -160
local PLACE = Config.place("Beach", 70, -95, YAW)

-- точка в пространстве персонажа -> мир
local function at(x: number, y: number, f: number): Vector3
	return (PLACE * CFrame.new(x, y, -f)).Position
end

-- направление в пространстве персонажа -> мир
local function dir(x: number, y: number, f: number): Vector3
	return PLACE:VectorToWorldSpace(Vector3.new(x, y, -f)).Unit
end

local CAM = at(2.4, 4.4, 2.6)
local LOOK = at(0, 5.3, 0.2)

return {
	id = "S04",
	start = 3.8667,
	finish = 4.9667,
	set = "Beach",
	preset = "Beach",
	lighting = {
		sunDir = dir(-0.412, 0.5, -0.761),
		clouds = { Enabled = false },
	},
	actors = {
		Horse = { char = "Horse", place = PLACE },
	},
	camera = {
		keys = {
			{ t = 3.8667, pos = CAM, look = LOOK, fov = 42, blur = 0 },
			{ t = 4.9667, pos = CAM, look = LOOK, fov = 42, blur = 0 },
		},
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
