--!strict
-- Функции сглаживания. tween(): как в TweenService. pose(): как Roblox интерполирует Pose в KeyframeSequence.

local Easing = {}

local PI = math.pi

local function bounceOut(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t -= 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t -= 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t -= 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end

-- Кривые «In» (медленный старт); Out/InOut строятся из них.
local IN: { [string]: (number) -> number } = {
	Linear = function(t)
		return t
	end,
	Sine = function(t)
		return 1 - math.cos(t * PI / 2)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t * t * t * t
	end,
	Quint = function(t)
		return t * t * t * t * t
	end,
	Exponential = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	end,
	Circular = function(t)
		return 1 - math.sqrt(1 - t * t)
	end,
	Back = function(t)
		local s = 1.70158
		return t * t * ((s + 1) * t - s)
	end,
	Elastic = function(t)
		if t <= 0 or t >= 1 then
			return t
		end
		return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * PI) / 3)
	end,
	Bounce = function(t)
		return 1 - bounceOut(1 - t)
	end,
}

function Easing.tween(style: string, direction: string, t: number): number
	t = math.clamp(t, 0, 1)
	local f = IN[style] or IN.Linear
	if direction == "In" then
		return f(t)
	elseif direction == "Out" then
		return 1 - f(1 - t)
	else
		if t < 0.5 then
			return f(t * 2) / 2
		end
		return 1 - f((1 - t) * 2) / 2
	end
end

-- Направление в Pose у Roblox исторически перевёрнуто относительно TweenService:
-- PoseEasingDirection.In ведёт себя как EasingDirection.Out (быстрый старт, плавная остановка).
Easing.POSE_DIRECTION_FLIPPED = true

local POSE_STYLE: { [string]: string } = {
	Linear = "Linear",
	Constant = "Constant",
	Cubic = "Cubic",
	CubicV2 = "Cubic",
	Elastic = "Elastic",
	Bounce = "Bounce",
}

-- styleName/directionName: имена EnumItem (PoseEasingStyle/PoseEasingDirection).
function Easing.pose(styleName: string, directionName: string, t: number): number
	local style = POSE_STYLE[styleName] or "Linear"
	if style == "Constant" then
		return if t >= 1 then 1 else 0
	end
	if style == "Linear" then
		return math.clamp(t, 0, 1)
	end
	local dir = directionName
	if Easing.POSE_DIRECTION_FLIPPED then
		if dir == "In" then
			dir = "Out"
		elseif dir == "Out" then
			dir = "In"
		end
	end
	return Easing.tween(style, dir, t)
end

-- Имена сглаживания в DSL ключей камеры/эффектов: "linear", "in", "out", "inout", "hold", "smooth",
-- а также "<style>_<dir>" например "Back_Out", "Sine_InOut".
function Easing.named(name: string?, t: number): number
	if name == nil or name == "smooth" or name == "inout" then
		return Easing.tween("Cubic", "InOut", t)
	elseif name == "linear" then
		return math.clamp(t, 0, 1)
	elseif name == "in" then
		return Easing.tween("Cubic", "In", t)
	elseif name == "out" then
		return Easing.tween("Cubic", "Out", t)
	elseif name == "hold" then
		return if t >= 1 then 1 else 0
	end
	local style, dir = string.match(name, "^(%a+)_(%a+)$")
	if style and dir then
		return Easing.tween(style, dir, t)
	end
	return Easing.tween("Cubic", "InOut", t)
end

return Easing
