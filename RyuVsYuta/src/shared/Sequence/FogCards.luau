--!strict
-- "Карточки" тумана: плоские полупрозрачные листы дыма (Beam, всегда лицом к камере) на фиксированной глубине.
-- Рика и Юта проходят сквозь "занавесы" — так их видно всё лучше (как в ролике), а перед ними туман
-- расходится влево и вправо. Положение каждой карточки — функция времени (перемотка и превиз точные).
-- Объём дополняют эмиттеры частиц окружения и клочья у объектива (FX/Effects).

local Shared = script.Parent.Parent
local MathX = require(Shared.Math)
local Timing = require(script.Parent.Timing)

local FogCards = {}
local T = Timing

export type Card = {
	layer: string, -- "wall" | "bank" | "curtain" | "part" | "near" | "shadow" | "sea"
	tex: string, -- ключ Textures.hq
	base: Vector3,
	w: number,
	h: number,
	alpha: number, -- непрозрачность 0..1
	color: Color3,
	drift: Vector3, -- студ/с
	roll: number, -- градусы
	spin: number, -- градусы/с
	shot: string, -- "A" — кадр с туманом, "BC" — кадры с Рю
	part: number?, -- для "part": куда расходится (-1 влево, +1 вправо)
}

export type CardState = { center: Vector3, w: number, h: number, roll: number, alpha: number, color: Color3, tex: string }

local HIGH = Color3.fromRGB(202, 212, 230)
local MID = Color3.fromRGB(180, 191, 220)
local LOW = Color3.fromRGB(155, 166, 204)
local SHADOW = Color3.fromRGB(142, 154, 198)

local ROUND = { "softFog", "mist", "whitePuff", "cumulusPuff", "softFog", "mist" }

local cards: { Card } = {}

local rng = MathX.rng(17031)
local function pick<T>(list: { T }): T
	return list[rng:int(1, #list)]
end

local function add(c: Card)
	table.insert(cards, c)
end

-- 1. Дальняя стена дыма за Рикой
for i = 1, 6 do
	add({
		layer = "wall",
		tex = pick(ROUND),
		base = Vector3.new(rng:range(-70, 70), rng:range(12, 30), rng:range(100, 150)),
		w = rng:range(90, 140),
		h = rng:range(50, 80),
		alpha = rng:range(0.3, 0.45),
		color = if i % 2 == 0 then HIGH else MID,
		drift = Vector3.new(rng:range(-0.6, 0.6), 0, 0),
		roll = rng:range(-20, 20),
		spin = rng:range(-0.6, 0.6),
		shot = "A",
	})
end

-- 2. Клубы вокруг и позади Рики
for i = 1, 26 do
	local z = rng:range(52, 112)
	add({
		layer = "bank",
		tex = pick(ROUND),
		base = Vector3.new(rng:range(-28, 28), rng:range(2, 20), z),
		w = rng:range(16, 32),
		h = rng:range(14, 28),
		alpha = rng:range(0.3, 0.48),
		color = if i % 3 == 0 then LOW elseif i % 3 == 1 then MID else HIGH,
		drift = Vector3.new(rng:range(-0.8, 0.8), rng:range(0, 0.15), rng:range(-0.3, 0.3)),
		roll = rng:range(0, 360),
		spin = rng:range(-4, 4),
		shot = "A",
	})
end

-- 3. Занавесы на пути Рики: она проходит сквозь них (Z 58, 54.5, 51) — с каждым видно чётче
for _, z in { 58, 54.5, 51 } do
	for j = 1, 7 do
		add({
			layer = "curtain",
			tex = pick(ROUND),
			base = Vector3.new(-21 + j * 6 + rng:range(-2, 2), rng:range(2.5, 13), z + rng:range(-1, 1)),
			w = rng:range(16, 26),
			h = rng:range(14, 22),
			alpha = rng:range(0.32, 0.46),
			color = if j % 2 == 0 then HIGH else MID,
			drift = Vector3.new(rng:range(-0.5, 0.5), 0, 0),
			roll = rng:range(0, 360),
			spin = rng:range(-3, 3),
			shot = "A",
		})
	end
end

-- 4. Туман между ней и камерой расходится влево и вправо (как в ролике)
for _, z in { 45, 40.5, 36 } do
	for j = 1, 6 do
		local side = if j <= 3 then -1 else 1
		add({
			layer = "part",
			tex = pick(ROUND),
			base = Vector3.new(side * rng:range(0, 9), rng:range(2, 11), z + rng:range(-1, 1)),
			w = rng:range(14, 22),
			h = rng:range(12, 20),
			alpha = rng:range(0.3, 0.42),
			color = if j % 2 == 0 then HIGH else MID,
			drift = Vector3.new(0, 0.05, 0),
			roll = rng:range(0, 360),
			spin = rng:range(-3, 3),
			shot = "A",
			part = side,
		})
	end
end

-- 5. Листы у самой камеры: камера проплывает сквозь них в начале (Z 16–29)
for i = 1, 9 do
	add({
		layer = "near",
		tex = pick({ "softFog", "mist", "wisps" }),
		base = Vector3.new(rng:range(-8, 8), rng:range(2, 9), rng:range(16, 30)),
		w = rng:range(12, 20),
		h = rng:range(9, 16),
		alpha = rng:range(0.35, 0.55),
		color = if i % 2 == 0 then HIGH else MID,
		drift = Vector3.new(if i % 2 == 0 then 1.4 else -1.4, 0.1, 0),
		roll = rng:range(0, 360),
		spin = rng:range(-6, 6),
		shot = "A",
	})
end

-- 6. Тёмные пятна в дыму (синеватые провалы, как в кадрах ролика)
for _ = 1, 7 do
	add({
		layer = "shadow",
		tex = "mist",
		base = Vector3.new(rng:range(-40, 40), rng:range(6, 26), rng:range(70, 120)),
		w = rng:range(24, 40),
		h = rng:range(18, 30),
		alpha = rng:range(0.18, 0.28),
		color = SHADOW,
		drift = Vector3.new(rng:range(-0.3, 0.3), 0, 0),
		roll = rng:range(0, 360),
		spin = rng:range(-1, 1),
		shot = "A",
	})
end

-- 7. Море дыма под плитой Рю (видно у нижнего края в кадрах с ним)
for _ = 1, 14 do
	add({
		layer = "sea",
		tex = pick(ROUND),
		base = Vector3.new(rng:range(-70, 70), rng:range(17, 27), rng:range(-260, -128)),
		w = rng:range(40, 80),
		h = rng:range(16, 30),
		alpha = rng:range(0.35, 0.55),
		color = if rng:next() > 0.5 then HIGH else MID,
		drift = Vector3.new(rng:range(-1.5, 1.5), 0.05, 0),
		roll = rng:range(-25, 25),
		spin = rng:range(-1, 1),
		shot = "BC",
	})
end

FogCards.cards = cards

-- Множитель плотности слоя по времени
local function layerAlpha(layer: string, t: number): number
	if layer == "near" then
		return 1
	elseif layer == "curtain" then
		return 1 - 0.35 * MathX.smoothstep(MathX.progress(t, 6, T.aEnd))
	elseif layer == "part" then
		return 1 - 0.55 * MathX.smoothstep(MathX.progress(t, 6.5, T.aEnd))
	elseif layer == "wall" or layer == "bank" or layer == "shadow" then
		return 1 - 0.25 * MathX.smoothstep(MathX.progress(t, 7, T.aEnd))
	end
	return 1
end

-- Состояния видимых карточек в момент t для камеры camCF. shot — "A" или "BC".
function FogCards.evaluate(t: number, shot: string, camCF: CFrame): { CardState }
	local out: { CardState } = {}
	local camPos = camCF.Position
	local look = camCF.LookVector
	for _, c in cards do
		if c.shot == shot then
			local center = c.base + c.drift * t
			if c.layer == "part" then
				-- расходятся в стороны, начиная с появления силуэта
				local p = MathX.smoothstep(MathX.progress(t, T.silhouette, T.aEnd))
				center += Vector3.new((c.part or 0) * 16 * p, 2.5 * p, 0)
			end
			local d = (center - camPos):Dot(look)
			if d > 0.5 then
				-- у самого объектива лист плавно исчезает, чтобы не "хлопал" на весь экран
				local near = MathX.smoothstep((d - 1) / 5)
				local a = c.alpha * layerAlpha(c.layer, t) * near
				if a > 0.01 then
					table.insert(out, {
						center = center,
						w = c.w,
						h = c.h,
						roll = c.roll + c.spin * t,
						alpha = a,
						color = c.color,
						tex = c.tex,
					})
				end
			end
		end
	end
	return out
end

return FogCards
