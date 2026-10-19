--!strict
-- S11 (13.133–15.633 с): Тьма, луч прожектора: конь на золотом троне, нога на ногу.
-- Камера: низкий ракурс снизу вверх, равномерная дуга ~35° вокруг трона к правому боку персонажа
-- (влево в кадре) с креном -6° -> +20° (картинка поворачивается по часовой).
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local START, FINISH = 13.1333, 15.6333

-- Параметры дуги (локальные координаты декорации Throne; трон смотрит в -Z, камера спереди).
-- az > 0 — камера уходит к правому боку персонажа (+X, слева в кадре).
local ARC = {
	center = Vector3.new(0, 0, 0.2),
	az0 = -5,
	az1 = 30,
	r0 = 9.4,
	r1 = 8.7,
	h0 = 2.3,
	h1 = 2.5,
	look0 = Vector3.new(-1.0, 4.85, 0),
	look1 = Vector3.new(1.0, 4.85, 0.5),
	roll0 = -6,
	roll1 = 20,
	fov = 55,
}

local function camKeys(): { any }
	local keys = {}
	local n = 6
	for i = 0, n do
		local a = i / n
		local t = START + (FINISH - START) * a
		local az = math.rad(ARC.az0 + (ARC.az1 - ARC.az0) * a)
		local r = ARC.r0 + (ARC.r1 - ARC.r0) * a
		local h = ARC.h0 + (ARC.h1 - ARC.h0) * a
		local p = ARC.center + Vector3.new(math.sin(az) * r, h, -math.cos(az) * r)
		local look = ARC.look0:Lerp(ARC.look1, a)
		table.insert(keys, {
			t = t,
			pos = Config.at("Throne", p.X, p.Y, p.Z),
			look = Config.at("Throne", look.X, look.Y, look.Z),
			fov = ARC.fov,
			roll = ARC.roll0 + (ARC.roll1 - ARC.roll0) * a,
			ease = "linear",
		})
	end
	return keys
end

return {
	id = "S11",
	start = START,
	finish = FINISH,
	set = "Throne",
	preset = "Throne",
	actors = {
		Horse = { char = "Horse", place = Config.place("Throne", 0, 0, 0), opts = { sparkles = true } },
	},
	camera = {
		keys = camKeys(),
		focus = { actor = "Horse", part = "Head" },
	},
	effects = {},
}
