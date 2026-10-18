--!nocheck
-- Небо: потолок грозовых туч над каждым островом (Map.Clouds.Clouds_1..5, из него бьют молнии),
-- стена туч вокруг Ока Бури, «море облаков» далеко внизу и далёкие парящие скалы для глубины.
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local M = Enum.Material
local rgb = B.rgb

local Sky = {}

local function cloudBall(parent, pos, d, color, transparency)
	return B.ball(parent, pos, d, color, B.deco({ Material = M.SmoothPlastic, Shadow = false, Transparency = transparency, Name = "Cloud" }))
end

-- Потолок туч над островом: нижний слой тёмных шаров на высоте GroundY + CloudHeight и верхние «башни»
local function ceiling(ctx, i, folder)
	local Config, Zones = ctx.Config, ctx.Zones
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local rng = B.rng(7000 + i * 31)
	local H = z.GroundY + Config.CloudHeight
	local m = B.model(folder, "Clouds_" .. i)
	local center = B.marker(m, "Center", CFrame.new(g.Center.X, H, g.Center.Z), Vector3.new(4, 4, 4))
	m.PrimaryPart = center
	m:SetAttribute("Height", H)
	local base = z.Sky.CloudColor
	local placed = {}
	local R = z.Radius * 1.12
	local count = 0
	local tries = 0
	while count < 28 and tries < 600 do
		tries += 1
		local off = rng:disc(R)
		local d = rng:range(24, 38)
		local ok = true
		for _, p in placed do
			if (Vector3.new(off.X, 0, off.Z) - p[1]).Magnitude < (d + p[2]) * 0.36 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, { Vector3.new(off.X, 0, off.Z), d })
			count += 1
			local edge = off.Magnitude / R
			local pos = g.Center + Vector3.new(off.X, H - z.GroundY + rng:range(-2, 3) + edge * 4, off.Z)
			-- середина темнее (грозовое брюхо), к краю светлее — мягкий силуэт
			local col = B.vary(base:Lerp(rgb(150, 150, 176), 0.1 + edge * 0.22), rng, 0.03)
			cloudBall(m, pos, d, col)
		end
	end
	-- верхние клубы (видны с мостов и из хаба)
	for _ = 1, 8 do
		local off = rng:disc(R * 0.75)
		local d = rng:range(30, 46)
		cloudBall(m, g.Center + Vector3.new(off.X, H - z.GroundY + rng:range(10, 18), off.Z), d, B.vary(base:Lerp(rgb(170, 170, 196), 0.25), rng, 0.03))
	end
	-- Око Бури: «стена глаза» — кольцо туч, свисающее с потолка по краю (видно изнутри как чашу туч,
	-- снаружи — как тёмную воронку над островом; сам остров не закрывает)
	if i == 5 then
		local wall = B.model(m, "Wall")
		local n = 20
		for k = 0, n - 1 do
			local a = (k + rng:range(-0.25, 0.25)) / n * math.pi * 2
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			local diff = math.acos(math.clamp(d:Dot(g.ToHub), -1, 1))
			for tier = 0, 1 do
				if tier == 1 or diff > math.rad(28) then
					local size = rng:range(40, 54)
					local rr = z.Radius + 10 + tier * 8 + rng:range(-3, 5)
					local pos = g.Center + d * rr + Vector3.new(0, H - z.GroundY - 40 + tier * 22 + rng:range(-4, 4), 0)
					cloudBall(wall, pos, size, B.vary(base:Lerp(rgb(150, 126, 186), 0.12 + tier * 0.1), rng, 0.04))
				end
			end
		end
	end
	return m
end

-- Маленький далёкий остров: травяная шапка, земля, три слоя скал, иногда дерево
local function farRock(parent, center, r, rng, pal)
	local m = B.model(parent, "FarRock")
	B.cylY(m, center - Vector3.new(0, 0.8, 0), 1.6, r * 2, B.vary(pal.top, rng, 0.04), B.deco({ Material = pal.topMat, Shadow = false }))
	B.cylY(m, center - Vector3.new(0, 2.6, 0), 2.2, r * 1.9, pal.dirt, B.deco({ Material = M.Ground, Shadow = false }))
	local y = center.Y - 3.6
	local rr = r * 0.95
	for layer = 1, 3 do
		local h = r * 0.55
		local n = 4
		local rot = rng:range(0, 6.28)
		for q = 1, n do
			local a = rot + q / n * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local d = math.max(2, rr * 0.7)
			local w = 2 * math.pi * rr / n * 1.3
			local pos = Vector3.new(center.X, y - h / 2, center.Z) + out * (rr - d / 2)
			B.block(m, B.facing(pos, out) * CFrame.Angles(-0.35, rng:range(-0.2, 0.2), 0), Vector3.new(w, h * 1.3, d), B.vary(B.shade(pal.rock, 0.15 + layer * 0.2), rng, 0.05), B.deco({ Material = M.Slate, Shadow = false }))
		end
		y -= h
		rr *= 0.62
	end
	if rng:chance(0.6) and r > 9 then
		local tp = center + Vector3.new(rng:range(-r * 0.4, r * 0.4), 0, rng:range(-r * 0.4, r * 0.4))
		B.cylY(m, tp + Vector3.new(0, 2.5, 0), 5, 1, rgb(96, 70, 50), B.deco({ Material = M.Wood }))
		B.ball(m, tp + Vector3.new(0, 6.5, 0), 6, B.vary(pal.leaf, rng, 0.05), B.deco({ Material = M.Grass }))
	end
	return m
end

function Sky.build(ctx)
	local Config = ctx.Config
	local folder = B.folder(ctx.Root, "Clouds")
	for i = 1, #Config.Zones do
		ceiling(ctx, i, folder)
	end
	local rng = B.rng(31337)
	-- море облаков внизу (Y ниже Config.VoidY — туда не долететь)
	local sea = B.model(folder, "Sea")
	local seaTop = Config.VoidY - 45
	for _ = 1, 115 do
		local off = rng:disc(820)
		local d = rng:range(110, 190)
		local t = math.clamp(off.Magnitude / 820, 0, 1)
		local col = B.vary(B.mix(rgb(150, 150, 196), rgb(110, 108, 160), t), rng, 0.03)
		cloudBall(sea, Vector3.new(off.X, seaTop - d * 0.5 + rng:range(-6, 10), off.Z), d, col)
	end
	-- далёкие парящие скалы
	local far = B.model(folder, "FarRocks")
	local pals = {
		{ top = rgb(92, 168, 82), topMat = M.Grass, dirt = rgb(140, 98, 66), rock = rgb(128, 124, 132), leaf = rgb(80, 160, 70) },
		{ top = rgb(236, 242, 255), topMat = M.Snow, dirt = rgb(200, 216, 240), rock = rgb(140, 158, 190), leaf = rgb(60, 110, 96) },
		{ top = rgb(232, 204, 146), topMat = M.Sand, dirt = rgb(200, 164, 116), rock = rgb(180, 144, 106), leaf = rgb(96, 146, 82) },
	}
	for k = 1, 7 do
		local a = (k / 7) * math.pi * 2 + rng:range(-0.25, 0.25)
		local dist = rng:range(440, 640)
		local pos = Vector3.new(math.cos(a) * dist, rng:range(-40, 70), math.sin(a) * dist)
		farRock(far, pos, rng:range(8, 18), rng, pals[(k % #pals) + 1])
	end
end

return Sky
