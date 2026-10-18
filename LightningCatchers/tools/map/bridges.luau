--!nocheck
-- Мосты от хаба к островам (настил, перила, фонари, арка-опора снизу, невидимые стены),
-- энергобарьеры с ценой (Map.Gates.Gate_N) и подстанции у входа каждого острова (Map.Stations).
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local M = Enum.Material
local rgb = B.rgb

local Bridges = {}

-- Стили мостов по островам
local STYLES = {
	{ deck = rgb(150, 104, 66), deck2 = rgb(128, 88, 56), deckMat = M.WoodPlanks, pitch = 2.8, beam = rgb(96, 66, 46), beamMat = M.Wood, rail = rgb(110, 76, 52), railMat = M.Wood, lamp = rgb(255, 210, 150), arch = rgb(110, 104, 112), archMat = M.Slate },
	{ deck = rgb(132, 122, 118), deck2 = rgb(116, 108, 106), deckMat = M.DiamondPlate, pitch = 5, beam = rgb(170, 98, 58), beamMat = M.Metal, rail = rgb(198, 112, 64), railMat = M.Metal, lamp = rgb(255, 176, 100), arch = rgb(160, 92, 56), archMat = M.Metal },
	{ deck = rgb(210, 176, 128), deck2 = rgb(192, 156, 112), deckMat = M.Sandstone, pitch = 4, beam = rgb(170, 136, 100), beamMat = M.Sandstone, rail = rgb(186, 150, 110), railMat = M.Sandstone, lamp = rgb(255, 214, 160), arch = rgb(176, 140, 102), archMat = M.Sandstone },
	{ deck = rgb(150, 166, 196), deck2 = rgb(134, 150, 184), deckMat = M.Slate, pitch = 4, beam = rgb(110, 124, 160), beamMat = M.Slate, rail = rgb(180, 214, 245), railMat = M.Ice, lamp = rgb(200, 170, 255), arch = rgb(120, 136, 170), archMat = M.Slate },
	{ deck = rgb(58, 50, 70), deck2 = rgb(48, 42, 60), deckMat = M.Basalt, pitch = 4, beam = rgb(40, 34, 50), beamMat = M.Basalt, rail = rgb(70, 60, 86), railMat = M.Basalt, lamp = rgb(255, 200, 90), arch = rgb(46, 40, 58), archMat = M.Basalt, seam = rgb(176, 96, 255) },
}

local LIFT = 0.2 -- настил чуть выше земли (без z-fighting на стыке)

----------------------------------------------------------------------
-- Мост
----------------------------------------------------------------------
local function bridge(ctx, i, parent)
	local Config, Zones = ctx.Config, ctx.Zones
	local g = Zones.Geo[i]
	local st = STYLES[i]
	local rng = B.rng(300 + i * 13)
	local W = Config.BridgeWidth
	local m = B.model(parent, "Bridge_" .. i)
	local dir = g.Dir
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local S = g.BridgeStart
	local E = g.BridgeEnd
	-- путь: площадка у хаба → пандус → площадка у острова
	local A = S + dir * 3
	local Bp = Vector3.new((E - dir * 3).X, E.Y, (E - dir * 3).Z)
	local S0 = S - dir * 2.5
	local E0 = E + dir * 2.5
	local segs = { { S0, A }, { A, Bp }, { Bp, E0 } }
	local lift = Vector3.new(0, LIFT, 0)
	-- рамка сегмента: ось Z вдоль пути, Y — нормаль настила
	local function frame(a, b)
		return B.lookAt((a + b) / 2, b)
	end
	-- высота настила (центр) в точке t∈[0,1] пути S0→E0 (по горизонтали)
	local total = B.flat(E0 - S0).Magnitude
	local function deckAt(d)
		-- d — расстояние по горизонтали от S0
		local pa = B.flat(A - S0).Magnitude
		local pb = B.flat(Bp - S0).Magnitude
		local y
		if d <= pa then
			y = S.Y
		elseif d >= pb then
			y = E.Y
		else
			y = S.Y + (E.Y - S.Y) * (d - pa) / (pb - pa)
		end
		local p = S0 + dir * d
		return Vector3.new(p.X, y, p.Z)
	end

	-- основание настила (коллизия) и балки-бортики
	for _, s in segs do
		local a, b = s[1] + lift, s[2] + lift
		local len = (b - a).Magnitude
		local cf = frame(a, b)
		B.block(m, cf * CFrame.new(0, -0.5, 0), Vector3.new(W, 1, len + 0.05), B.shade(st.deck2, 0.2), { Material = st.deckMat, Shadow = true, Name = "Deck" })
		for side = -1, 1, 2 do
			B.block(m, cf * CFrame.new(side * (W / 2 + 0.5), -0.2, 0), Vector3.new(1.2, 1.9, len + 0.6), st.beam, { Material = st.beamMat, Shadow = true, Name = "Stringer" })
		end
	end
	-- доски/плиты (декор поверх основания)
	local n = math.floor(total / st.pitch)
	for k = 0, n - 1 do
		local d0 = (k + 0.5) * total / n
		local p = deckAt(d0)
		local pNext = deckAt(math.min(total, d0 + 0.5))
		local pPrev = deckAt(math.max(0, d0 - 0.5))
		local cf = B.lookAt(p + lift, p + lift + (pNext - pPrev))
		local len = total / n - (if st.deckMat == M.WoodPlanks then 0.25 else 0.12)
		local col = B.vary(if k % 2 == 0 then st.deck else st.deck2, rng, 0.03)
		B.block(m, cf * CFrame.new(rng:range(-0.15, 0.15), 0.05, 0), Vector3.new(W - 0.2, 0.12, len), col, B.deco({ Material = st.deckMat, Shadow = false, Name = "Plank" }))
		if st.seam and k % 2 == 0 then
			B.block(m, cf * CFrame.new(0, 0.06, len / 2 + 0.06), Vector3.new(W - 2, 0.1, 0.12), st.seam, B.neon())
		end
	end

	-- перила: столбики и две перекладины по каждому сегменту
	for _, s in segs do
		local a, b = s[1] + lift, s[2] + lift
		local len = (b - a).Magnitude
		local cf = frame(a, b)
		for side = -1, 1, 2 do
			local x = side * (W / 2 + 0.5)
			for _, y in { 1.9, 3.3 } do
				B.block(m, cf * CFrame.new(x, y, 0), Vector3.new(0.35, 0.35, len + 0.3), st.rail, { Material = st.railMat, Collide = y > 3, Shadow = false, Name = "Rail" })
			end
		end
	end
	local posts = math.floor(total / 8)
	local lampAt = { [2] = 1, [4] = -1, [6] = 1, [8] = -1 }
	for k = 0, posts do
		local p = deckAt(k * total / posts) + lift
		for side = -1, 1, 2 do
			local q = p + right * side * (W / 2 + 0.5)
			if lampAt[k] == side then
				-- столбик-фонарь: высокий столб, фонарь и козырёк (3 детали + свет)
				B.block(m, CFrame.new(q + Vector3.new(0, 3.4, 0)), Vector3.new(0.7, 6.4, 0.7), rgb(46, 46, 56), B.deco({ Material = M.Metal }))
				local lantern = B.block(m, CFrame.new(q + Vector3.new(0, 7.2, 0)), Vector3.new(1, 1.3, 1), st.lamp, B.neon())
				B.block(m, CFrame.new(q + Vector3.new(0, 8.05, 0)), Vector3.new(1.5, 0.4, 1.5), rgb(46, 46, 56), B.deco({ Material = M.Metal }))
				B.light(lantern, st.lamp, 20, 1.2)
			else
				B.block(m, CFrame.new(q + Vector3.new(0, 2, 0)), Vector3.new(0.65, 3.8, 0.65), st.rail, B.deco({ Material = st.railMat }))
			end
		end
	end
	-- арка-опора снизу (две дуги + подвесы)
	for side = -1, 1, 2 do
		local pts = {}
		local steps = 6
		for k = 0, steps do
			local t = k / steps
			local d = t * total
			local p = deckAt(d) + right * side * (W / 2 - 1.5)
			local sag = math.sin(t * math.pi) * 7 + 1.2
			table.insert(pts, p - Vector3.new(0, sag, 0))
		end
		for k = 1, steps do
			B.bar(m, pts[k], pts[k + 1], 1.4, 1.6, B.vary(st.arch, rng, 0.03), B.deco({ Material = st.archMat, Shadow = true }))
		end
		for k = 3, steps - 1, 2 do
			local top = deckAt((k - 1) / steps * total) + right * side * (W / 2 - 1.5) - Vector3.new(0, 0.9, 0)
			B.rod(m, pts[k], top, 0.5, B.shade(st.arch, 0.15), B.deco({ Material = st.archMat }))
		end
	end
	-- поперечины под настилом
	for k = 1, 3 do
		local p = deckAt(k / 4 * total) - Vector3.new(0, 1.2, 0)
		B.block(m, B.facing(p, dir), Vector3.new(W, 0.8, 1), st.arch, B.deco({ Material = st.archMat }))
	end

	-- невидимые стены вдоль моста (чтобы не упасть), по сегментам
	for _, s in segs do
		local a, b = s[1], s[2]
		local len = (b - a).Magnitude
		local cf = frame(a, b)
		for side = -1, 1, 2 do
			local w = B.block(ctx.Walls, cf * CFrame.new(side * (W / 2 + 1.2), 7, 0), Vector3.new(1, 15, len + 1), Color3.new(1, 1, 1), { Collide = true, Query = false, Shadow = false, Transparency = 1, Name = "Wall" })
			w.CanTouch = false
		end
	end
	return m, deckAt, total
end

----------------------------------------------------------------------
-- Энергобарьер (острова 2..5)
----------------------------------------------------------------------
local function gate(ctx, i, gatesFolder)
	local Config, Zones, Format = ctx.Config, ctx.Zones, ctx.Format
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local W = Config.BridgeWidth
	local dir = g.Dir
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local base = g.Gate + Vector3.new(0, LIFT + 0.1, 0)
	local accent = z.Accent
	local frame = B.model(gatesFolder, "Frame_" .. i)
	local cf = B.facing(base, dir) -- LookVector к острову
	local metal = rgb(44, 46, 58)
	-- барьер: ForceField, без коллизий (доступ проверяет сервер)
	local barrier = B.block(gatesFolder, cf * CFrame.new(0, 6.2, 0), Vector3.new(W + 1.4, 12.4, 0.5), accent, { Material = M.ForceField, Collide = false, Query = false, Shadow = false, Name = "Gate_" .. i })
	barrier:SetAttribute("Zone", i)
	-- пилоны
	for side = -1, 1, 2 do
		local pc = cf * CFrame.new(side * (W / 2 + 1.7), 0, 0)
		B.block(frame, pc * CFrame.new(0, 7, 0), Vector3.new(2.2, 14, 2.2), metal, { Material = M.Metal, Shadow = true })
		B.block(frame, pc * CFrame.new(0, 0.6, 0), Vector3.new(3, 1.2, 3), B.shade(metal, 0.2), { Material = M.Metal })
		for _, y in { 3, 6, 9, 12 } do
			B.block(frame, pc * CFrame.new(-side * 1.12, y, 0), Vector3.new(0.12, 1.4, 1.4), accent, B.neon())
		end
		local orb = B.ball(frame, (pc * CFrame.new(0, 15, 0)).Position, 1.6, accent, B.neon())
		B.light(orb, accent, 22, 1.4)
		B.cylY(frame, (pc * CFrame.new(0, 14.1, 0)).Position, 0.4, 2.6, B.shade(metal, 0.1), B.deco({ Material = M.Metal }))
	end
	-- перекладина и табличка с ценой (смотрит к хабу)
	B.block(frame, cf * CFrame.new(0, 13.2, 0), Vector3.new(W + 5.6, 1.2, 1.4), metal, B.deco({ Material = M.Metal, Shadow = true }))
	local sign = B.block(frame, cf * CFrame.new(0, 15.5, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(15, 3.6, 0.5), rgb(26, 28, 44), B.deco({ Name = "Sign" }))
	B.text(sign, {
		{ Text = "Остров " .. i .. ": " .. z.Name, Color = accent:Lerp(Color3.new(1, 1, 1), 0.4), Size = 1 },
		{ Text = "⚡ " .. Format.short(z.Cost), Color = rgb(255, 230, 120), Size = 1.1 },
	}, { Face = Enum.NormalId.Front, PixelsPerStud = 30 })
	B.text(sign, { { Text = z.Name, Color = accent:Lerp(Color3.new(1, 1, 1), 0.4) } }, { Face = Enum.NormalId.Back, PixelsPerStud = 30, Name = "SignBack" })
	B.block(frame, cf * CFrame.new(0, 15.5, 0), Vector3.new(15.6, 4.2, 0.3), accent, B.neon())
	-- светящаяся полоса-«порог» на настиле
	B.block(frame, cf * CFrame.new(0, 0.05, 0), Vector3.new(W, 0.1, 0.6), accent, B.neon())
	B.marker(ctx.Markers, "Gate_" .. i, cf * CFrame.new(0, 3, 0), Vector3.new(W, 6, 1))
	return barrier
end

----------------------------------------------------------------------
-- Подстанция: светящаяся площадка (радиус Zones.SellPadRadius) + трансформатор с катушками
----------------------------------------------------------------------
local function station(ctx, i, parent)
	local Config, Zones = ctx.Config, ctx.Zones
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local rng = B.rng(900 + i)
	local m = B.model(parent, "Station_" .. i)
	local pad = g.SellPad
	local r = Zones.SellPadRadius
	local accent = z.Accent
	local metal = rgb(70, 74, 90)
	-- площадка
	B.cylY(m, pad + Vector3.new(0, 0.15, 0), 0.3, r * 2, metal, { Material = M.DiamondPlate, Shadow = false, Name = "Pad" })
	B.cylY(m, pad + Vector3.new(0, 0.1, 0), 0.24, r * 2 + 0.7, accent, B.neon({ Name = "PadGlow" }))
	B.cylY(m, pad + Vector3.new(0, 0.32, 0), 0.06, r * 2 - 2.4, rgb(94, 100, 118), B.deco({ Material = M.Metal, Shadow = false }))
	-- молния-эмблема
	local out = B.flat(pad - g.Center).Unit
	local side = Vector3.new(-out.Z, 0, out.X)
	local y = Vector3.new(0, 0.38, 0)
	local z1 = pad + y - out * 2.8 + side * 0.9
	local z2 = pad + y - side * 0.7
	local z3 = pad + y + side * 0.7
	local z4 = pad + y + out * 2.8 - side * 0.9
	B.bar(m, z1, z2, 0.7, 0.06, accent, B.neon())
	B.bar(m, z2, z3, 0.7, 0.06, accent, B.neon())
	B.bar(m, z3, z4, 0.7, 0.06, accent, B.neon())
	local glow = B.block(m, CFrame.new(pad + Vector3.new(0, 2, 0)), Vector3.new(1, 1, 1), accent, B.deco({ Transparency = 1 }))
	B.light(glow, accent, 16, 1.2)
	-- трансформатор (за площадкой, снаружи игровой зоны)
	local tp = pad + out * 12
	local cf = B.facing(tp, -out) -- лицом к площадке
	local body = rgb(104, 118, 116)
	B.block(m, cf * CFrame.new(0, 0.4, 0), Vector3.new(8, 0.8, 5.4), rgb(120, 116, 112), { Material = M.Concrete })
	B.block(m, cf * CFrame.new(0, 3.2, 0), Vector3.new(6.2, 4.8, 3.8), body, { Material = M.Metal, Shadow = true })
	-- изоляторы с неоновыми навершиями
	for k = -1, 1 do
		local base = cf * CFrame.new(k * 1.9, 5.6, 0)
		for q = 0, 2 do
			B.cylY(m, (base * CFrame.new(0, 0.3 + q * 0.55, 0)).Position, 0.3, 1.2 - q * 0.2, rgb(232, 224, 210), B.deco({ Material = M.SmoothPlastic }))
		end
		B.ball(m, (base * CFrame.new(0, 2, 0)).Position, 0.7, accent, B.neon())
	end
	-- катушки по бокам
	for s = -1, 1, 2 do
		local cp = (cf * CFrame.new(s * 4.1, 2.4, 0.5)).Position
		B.cylY(m, cp, 3.6, 1.8, rgb(198, 112, 64), B.deco({ Material = M.Metal, Shadow = false }))
		for q = -1, 1 do
			B.cylY(m, cp + Vector3.new(0, q * 1.1, 0), 0.22, 1.95, accent, B.neon())
		end
		B.cylY(m, cp + Vector3.new(0, 1.95, 0), 0.3, 2.2, metal, B.deco({ Material = M.Metal }))
	end
	-- светящаяся панель и полосы «осторожно»
	B.block(m, cf * CFrame.new(0, 3.6, -1.95), Vector3.new(4.4, 0.35, 0.1), accent, B.neon())
	for k = -1, 1 do
		B.block(m, cf * CFrame.new(k * 1.3, 1.2, -1.95) * CFrame.Angles(0, 0, 0.6), Vector3.new(0.55, 1.2, 0.08), rgb(250, 200, 50), B.deco())
	end
	-- вывеска «Подстанция» на стойке
	local signPos = cf * CFrame.new(0, 8.8, 0)
	B.block(m, cf * CFrame.new(0, 7.6, 0.6), Vector3.new(0.4, 2.4, 0.4), metal, B.deco({ Material = M.Metal }))
	local sign = B.block(m, signPos, Vector3.new(8.5, 1.9, 0.35), rgb(26, 28, 44), B.deco({ Name = "Sign" }))
	B.text(sign, { { Text = "⚡ Подстанция", Color = accent:Lerp(Color3.new(1, 1, 1), 0.45) } }, { Face = Enum.NormalId.Front, PixelsPerStud = 30 })
	-- кабель от трансформатора к площадке
	B.bar(m, pad + out * (r - 0.3) + Vector3.new(0, 0.12, 0), tp - out * 2.6 + Vector3.new(0, 0.12, 0), 0.5, 0.24, rgb(30, 30, 36), B.deco({ Shadow = false, Name = "Cable" }))
	local _ = rng
	return m
end

function Bridges.build(ctx, parent)
	local Config = ctx.Config
	local bridges = B.folder(parent, "Bridges")
	local gates = B.folder(ctx.Root, "Gates")
	local stations = B.folder(ctx.Root, "Stations")
	for i = 1, #Config.Zones do
		bridge(ctx, i, bridges)
		if i >= 2 then
			gate(ctx, i, gates)
		end
		station(ctx, i, stations)
	end
end

return Bridges
