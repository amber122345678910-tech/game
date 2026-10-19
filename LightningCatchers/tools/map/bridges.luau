--!nocheck
-- Мосты от хаба к островам (docs/STYLE.md §6.16–6.17): настил из досок с зазорами и медными полосами,
-- коренастые столбы перил, провисающая верёвка-Beam, изоляторные фонари, арка-опора снизу, невидимые стены;
-- энергобарьеры с ценой на SkewPlate и зигзагом-молнией (Map.Gates.Gate_N) и подстанции у входа каждого острова (Map.Stations).
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local ColorSequence = roblox.ColorSequence
local NumberSequence = roblox.NumberSequence
local M = Enum.Material
local rgb = B.rgb

local Bridges = {}

local COPPER = rgb(204, 116, 64)
local TRIM = rgb(70, 64, 96)

-- Стили мостов по островам (палитры зон)
local STYLES = {
	{ deck = rgb(166, 116, 74), deckMat = M.WoodPlanks, beam = rgb(96, 64, 46), rail = rgb(124, 84, 58), lamp = rgb(255, 206, 140), arch = rgb(132, 128, 144), rope = rgb(196, 170, 120) },
	{ deck = rgb(140, 120, 116), deckMat = M.SmoothPlastic, beam = rgb(150, 82, 50), rail = COPPER, railMat = M.Metal, lamp = rgb(255, 176, 100), arch = rgb(150, 88, 56), archMat = M.Metal, rope = rgb(96, 164, 138) },
	{ deck = rgb(220, 184, 132), deckMat = M.SmoothPlastic, beam = rgb(160, 120, 84), rail = rgb(204, 160, 112), lamp = rgb(255, 210, 150), arch = rgb(196, 152, 106), rope = rgb(140, 240, 228) },
	{ deck = rgb(156, 172, 206), deckMat = M.SmoothPlastic, beam = rgb(100, 112, 152), rail = rgb(178, 214, 246), lamp = rgb(200, 170, 255), arch = rgb(140, 156, 196), rope = rgb(232, 238, 252) },
	{ deck = rgb(66, 56, 84), deckMat = M.SmoothPlastic, beam = rgb(38, 32, 52), rail = rgb(80, 66, 100), lamp = rgb(255, 200, 90), arch = rgb(56, 46, 72), rope = rgb(186, 104, 255), seam = rgb(186, 104, 255) },
}

local LIFT = 0.2 -- настил чуть выше земли (без z-fighting на стыке)

-- Верёвка между двумя столбами: Beam без текстуры с провисом (0 деталей)
local function rope(partA, a, partB, b, color)
	local function att(part, pos)
		local at = Instance.new("Attachment")
		at.Name = "Rope"
		at.CFrame = part.CFrame:Inverse() * CFrame.fromMatrix(pos, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
		at.Parent = part
		return at
	end
	local beam = Instance.new("Beam")
	beam.Name = "Rope"
	beam.Attachment0 = att(partA, a)
	beam.Attachment1 = att(partB, b)
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0)
	beam.LightInfluence = 1
	beam.Width0 = 0.22
	beam.Width1 = 0.22
	beam.Segments = 8
	beam.FaceCamera = true
	beam.CurveSize0 = 0.9
	beam.CurveSize1 = -0.9
	beam.Parent = partA
	return beam
end

----------------------------------------------------------------------
-- Мост (≤ 130 деталей)
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

	-- основание настила (коллизия; виден в зазорах как тёмный продольный брус) и балки-бортики
	for _, s in segs do
		local a, b = s[1] + lift, s[2] + lift
		local len = (b - a).Magnitude
		local cf = frame(a, b)
		B.block(m, cf * CFrame.new(0, -0.5, 0), Vector3.new(W, 1, len + 0.05), B.shade(st.beam, 0.6), { Shadow = true, Name = "Deck" })
		for side = -1, 1, 2 do
			B.block(m, cf * CFrame.new(side * (W / 2 + 0.5), -0.2, 0), Vector3.new(1.2, 1.9, len + 0.6), st.beam, { Material = st.archMat or M.SmoothPlastic, Shadow = true, Name = "Stringer" })
		end
	end
	-- доски 1.6 с зазором 0.15, тон чередуется ±6%, лёгкий разброс поворота; каждая 6-я — с медной полосой
	local pitch = 1.75
	local n = math.floor(total / pitch)
	for k = 0, n - 1 do
		local d0 = (k + 0.5) * total / n
		local p = deckAt(d0)
		local pNext = deckAt(math.min(total, d0 + 0.5))
		local pPrev = deckAt(math.max(0, d0 - 0.5))
		local cf = B.lookAt(p + lift, p + lift + (pNext - pPrev)) * CFrame.Angles(0, math.rad(rng:range(-1.5, 1.5)), 0)
		local h, s, v = st.deck:ToHSV()
		local col = Color3.fromHSV(h, s, math.clamp(v * (if k % 2 == 0 then 1.06 else 0.94) + rng:range(-0.015, 0.015), 0, 1))
		B.block(m, cf * CFrame.new(rng:range(-0.12, 0.12), 0.05, 0), Vector3.new(W - 0.3, 0.14, total / n - 0.15), col, B.deco({ Material = st.deckMat, Shadow = false, Name = "Plank" }))
		if k % 6 == 3 then
			B.block(m, cf * CFrame.new(0, 0.14, 0), Vector3.new(W - 1.2, 0.06, 0.3), st.seam or COPPER, if st.seam then B.neon() else B.deco({ Material = M.Metal, Shadow = false }))
		end
	end

	-- перила: верхний брус по каждому сегменту, столбы через ~6 стадов, верёвка-Beam между столбами
	for _, s in segs do
		local a, b = s[1] + lift, s[2] + lift
		local len = (b - a).Magnitude
		local cf = frame(a, b)
		for side = -1, 1, 2 do
			B.block(m, cf * CFrame.new(side * (W / 2 + 0.5), 3.45, 0), Vector3.new(0.6, 0.5, len + 0.3), B.tint(st.rail, 0.3), { Material = st.railMat or M.SmoothPlastic, Collide = true, Shadow = false, Name = "Rail" })
		end
	end
	local posts = math.max(2, math.floor(total / 6))
	local lampAt = {}
	-- фонари на каждом втором столбе в середине моста, по очереди с разных сторон
	local lampSide = 1
	for k = 2, posts - 2, 2 do
		lampAt[k] = lampSide
		lampSide = -lampSide
	end
	local prev = { [-1] = nil, [1] = nil }
	for k = 0, posts do
		local p = deckAt(k * total / posts) + lift
		for side = -1, 1, 2 do
			local q = p + right * side * (W / 2 + 0.5)
			local post
			if lampAt[k] == side then
				-- столб-фонарь: высокий ромбовидный столб, изолятор, фонарь и гранёное навершие (4 детали + свет)
				post = B.block(m, CFrame.new(q + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.8, 7.2, 0.8), TRIM, B.deco({ Shadow = true }))
				B.cylY(m, q + Vector3.new(0, 7.35, 0), 0.3, 1.5, P.PORCELAIN, B.deco({ Shadow = false }))
				local lantern = B.block(m, CFrame.new(q + Vector3.new(0, 8.1, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, 1.2, 0.9), st.lamp, B.neon())
				B.gem(m, q + Vector3.new(0, 9.25, 0), 1.0, math.rad(45), TRIM, B.deco({ Shadow = false }))
				B.light(lantern, st.lamp, 18, 1.1)
			else
				post = B.block(m, CFrame.new(q + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, math.rad(45) * (k % 2), 0), Vector3.new(0.8, 3.4, 0.8), st.rail, B.deco({ Material = st.railMat or M.SmoothPlastic }))
			end
			if prev[side] then
				rope(prev[side][1], prev[side][2], post, q + Vector3.new(0, 2.2, 0), st.rope)
			end
			prev[side] = { post, q + Vector3.new(0, 2.2, 0) }
		end
	end
	-- арка-опора снизу (две дуги из брусков, тон по поясам + подвесы)
	for side = -1, 1, 2 do
		local pts = {}
		local steps = 6
		for k = 0, steps do
			local t = k / steps
			local p = deckAt(t * total) + right * side * (W / 2 - 1.5)
			local sag = math.sin(t * math.pi) * 7 + 1.2
			table.insert(pts, p - Vector3.new(0, sag, 0))
		end
		for k = 1, steps do
			local mid = math.abs(k - 3.5)
			local col = if mid < 1 then B.shade(st.arch, 0.5) elseif mid < 2 then st.arch else B.tint(st.arch, 0.4)
			B.bar(m, pts[k], pts[k + 1], 1.4, 1.6, B.vary(col, rng, 0.02), B.deco({ Material = st.archMat or M.SmoothPlastic, Shadow = true }))
		end
		for k = 3, steps - 1, 2 do
			local top = deckAt((k - 1) / steps * total) + right * side * (W / 2 - 1.5) - Vector3.new(0, 0.9, 0)
			B.bar(m, pts[k], top, 0.5, 0.5, B.shade(st.arch, 0.6), B.deco({ Material = st.archMat or M.SmoothPlastic }))
		end
	end
	-- поперечины под настилом
	for k = 1, 3 do
		local p = deckAt(k / 4 * total) - Vector3.new(0, 1.2, 0)
		B.block(m, B.facing(p, dir), Vector3.new(W, 0.8, 1), B.shade(st.arch, 0.4), B.deco({ Material = st.archMat or M.SmoothPlastic }))
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
-- Энергобарьер (острова 2..5, ≤ 30): шестигранные пилоны со стопками изоляторов, барьер с зигзагом-молнией,
-- цена на SkewPlate над проёмом
----------------------------------------------------------------------
local function gate(ctx, i, gatesFolder)
	local Config, Zones, Format = ctx.Config, ctx.Zones, ctx.Format
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local W = Config.BridgeWidth
	local dir = g.Dir
	local base = g.Gate + Vector3.new(0, LIFT + 0.1, 0)
	local accent = z.Accent
	local frame = B.model(gatesFolder, "Frame_" .. i)
	local cf = B.facing(base, dir) -- LookVector к острову
	local metal = rgb(56, 52, 78)
	-- барьер: ForceField, без коллизий (доступ проверяет сервер)
	local barrier = B.block(gatesFolder, cf * CFrame.new(0, 5, 0), Vector3.new(W + 1.4, 10, 0.5), accent, { Material = M.ForceField, Collide = false, Query = false, Shadow = false, Name = "Gate_" .. i })
	barrier:SetAttribute("Zone", i)
	-- шеврон-молния по центру барьера
	B.zigzag(frame, (cf * CFrame.new(-0.6, 8.4, 0)).Position, (cf * CFrame.new(0.6, 1.6, 0)).Position, 3, 0.55, B.tint(accent, 0.3), B.neon(), cf.LookVector, 0.7)
	-- пилоны
	for side = -1, 1, 2 do
		local pc = cf * CFrame.new(side * (W / 2 + 1.9), 0, 0)
		B.block(frame, pc * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3.4, 1.2, 3.4), B.shade(metal, 0.6), {})
		B.hexPrism(frame, (pc * CFrame.new(0, 1.2 + 4.5, 0)).Position, 1.6, 9, B.yawOf(dir) + math.rad(30), metal, { Shadow = true, Material = M.Metal })
		local yy = 1.2 + 9
		for k, dd in { 1.8, 1.5, 1.2 } do
			B.cylY(frame, (pc * CFrame.new(0, yy + 0.25 + (k - 1) * 0.55, 0)).Position, 0.35, dd, P.PORCELAIN, B.deco({ Shadow = false }))
		end
		local orb = B.gem(frame, (pc * CFrame.new(0, yy + 2.3, 0)).Position, 0.9, 0.4, accent, B.neon())
		B.light(orb, accent, 20, 1.3)
	end
	-- перекладина и табличка с ценой (лицом к хабу); с обратной стороны — название острова
	B.block(frame, cf * CFrame.new(0, 10.6, 0), Vector3.new(W + 3.2, 0.9, 1.2), B.shade(metal, 0.4), B.deco({ Material = M.Metal, Shadow = true }))
	local signCf = cf * CFrame.new(0, 12.9, 0) * CFrame.Angles(0, math.pi, 0)
	B.sign(frame, signCf, 13, 3.4, {
		{ Text = z.Name, Size = 0.85 },
		{ Text = "⚡ " .. Format.short(z.Cost), Font = B.FontNumber, Gradient = { B.VOLT_HI, B.VOLT }, Stroke = true, Size = 1.1 },
	}, { Back = true, BackLines = { { Text = z.Name } }, Underline = accent, Slant = 1.2, Thickness = 0.5 })
	-- светящаяся полоса-«порог» на настиле
	B.block(frame, cf * CFrame.new(0, 0.05, 0), Vector3.new(W, 0.1, 0.6), accent, B.neon())
	B.marker(ctx.Markers, "Gate_" .. i, cf * CFrame.new(0, 3, 0), Vector3.new(W, 6, 1))
	return barrier
end

----------------------------------------------------------------------
-- Подстанция: светящаяся площадка (радиус Zones.SellPadRadius) + трансформатор с фасками и изоляторами
----------------------------------------------------------------------
local function station(ctx, i, parent)
	local Config, Zones = ctx.Config, ctx.Zones
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local m = B.model(parent, "Station_" .. i)
	local pad = g.SellPad
	local r = Zones.SellPadRadius
	local accent = z.Accent
	local metal = rgb(78, 76, 104)
	-- площадка
	B.cylY(m, pad + Vector3.new(0, 0.15, 0), 0.3, r * 2, metal, { Material = M.Metal, Shadow = false, Name = "Pad" })
	B.cylY(m, pad + Vector3.new(0, 0.1, 0), 0.24, r * 2 + 0.7, accent, B.neon({ Name = "PadGlow" }))
	B.cylY(m, pad + Vector3.new(0, 0.32, 0), 0.06, r * 2 - 2.4, B.tint(metal, 0.4), B.deco({ Material = M.Metal, Shadow = false }))
	-- молния-эмблема: зигзаг из трёх неоновых брусков
	local out = B.flat(pad - g.Center).Unit
	local y = Vector3.new(0, 0.38, 0)
	B.zigzag(m, pad + y - out * 3, pad + y + out * 3, 3, 0.7, accent, B.neon(), Vector3.yAxis, 0.06)
	local glow = B.block(m, CFrame.new(pad + Vector3.new(0, 2, 0)), Vector3.new(1, 1, 1), accent, B.deco({ Transparency = 1 }))
	B.light(glow, accent, 16, 1.2)
	-- трансформатор (за площадкой, снаружи игровой зоны)
	local tp = pad + out * 12
	local cf = B.facing(tp, -out) -- лицом к площадке
	local body = rgb(104, 118, 128)
	B.block(m, cf * CFrame.new(0, 0.4, 0), Vector3.new(8, 0.8, 5.4), rgb(120, 116, 128), {})
	B.block(m, cf * CFrame.new(0, 3.0, 0), Vector3.new(6.2, 4.4, 3.8), body, { Material = M.Metal, Shadow = true })
	-- фаски-клинья по верхним продольным рёбрам
	B.wedge(m, cf * CFrame.new(0, 5.6, -1.2), Vector3.new(6.2, 0.8, 1.4), B.tint(body, 0.5), B.deco({ Material = M.Metal }))
	B.wedge(m, cf * CFrame.new(0, 5.6, 1.2) * CFrame.Angles(0, math.pi, 0), Vector3.new(6.2, 0.8, 1.4), B.shade(body, 0.5), B.deco({ Material = M.Metal }))
	B.block(m, cf * CFrame.new(0, 5.6, 0), Vector3.new(6.2, 0.8, 1.0), body, B.deco({ Material = M.Metal }))
	-- изоляторы-стопки с неоновыми гранёными навершиями
	for k = -1, 1 do
		local bcf = cf * CFrame.new(k * 1.9, 6.0, 0)
		for q = 0, 2 do
			B.cylY(m, (bcf * CFrame.new(0, 0.3 + q * 0.55, 0)).Position, 0.3, 1.2 - q * 0.2, P.PORCELAIN, B.deco())
		end
		B.gem(m, (bcf * CFrame.new(0, 2.05, 0)).Position, 0.6, k, accent, B.neon())
	end
	-- катушки по бокам
	for s = -1, 1, 2 do
		local cp = (cf * CFrame.new(s * 4.1, 2.4, 0.5)).Position
		B.cylY(m, cp, 3.6, 1.8, COPPER, B.deco({ Material = M.Metal, Shadow = false }))
		B.cylY(m, cp + Vector3.new(0, 0.6, 0), 0.22, 1.95, accent, B.neon())
		B.cylY(m, cp + Vector3.new(0, 1.95, 0), 0.3, 2.2, metal, B.deco({ Material = M.Metal }))
	end
	-- зигзаг-полоса на лицевой стороне и знак «осторожно»
	B.zigzag(m, (cf * CFrame.new(-1.9, 3.6, -1.95)).Position, (cf * CFrame.new(1.9, 3.6, -1.95)).Position, 4, 0.32, accent, B.neon(), cf.LookVector, 0.1)
	for k = -1, 1 do
		B.block(m, cf * CFrame.new(k * 1.3, 1.6, -1.95) * CFrame.Angles(0, 0, 0.6), Vector3.new(0.55, 1.1, 0.08), B.VOLT, B.deco())
	end
	-- вывеска «Подстанция» на стойке
	B.block(m, cf * CFrame.new(0, 7.6, 0.6), Vector3.new(0.4, 2.4, 0.4), TRIM, B.deco())
	B.sign(m, cf * CFrame.new(0, 9.0, 0.6), 8, 1.9, { { Text = "Подстанция" } }, { Underline = accent, Slant = 0.8, Thickness = 0.35 })
	-- кабель от трансформатора к площадке
	B.bar(m, pad + out * (r - 0.3) + Vector3.new(0, 0.12, 0), tp - out * 2.6 + Vector3.new(0, 0.12, 0), 0.5, 0.24, rgb(30, 28, 40), B.deco({ Shadow = false, Name = "Cable" }))
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
