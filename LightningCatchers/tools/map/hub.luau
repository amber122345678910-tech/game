--!nocheck
-- Хаб «Электроград» (docs/STYLE.md §6.14): брусчатая площадь с медными зигзагами-инкрустациями к мостам,
-- Тесла-башня с шестигранными катушками и кристаллом на вершине, кольцо подстанции,
-- 6 кварталов домов с медными коньками и громоотводом на каждой скатной крыше, тёплыми фонариками у дверей
-- и окнами (зажигаются клиентом), гирлянды над улицами, киоски с вывесками, табло, фонари, скамейки, клумбы.
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Island = require("./island")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local UDim = roblox.UDim
local UDim2 = roblox.UDim2
local M = Enum.Material
local rgb = B.rgb

local Hub = {}

local TAU = math.pi * 2
local W = B.W

-- Палитра хаба (STYLE §3.2)
local ENERGY = rgb(90, 210, 255) -- энергия башни
local LAMP = rgb(255, 206, 140)
local COBBLE = rgb(150, 148, 170)
local COBBLE_SHADE = B.shade(COBBLE, 1)
local COBBLE_LIGHT = B.tint(COBBLE, 1)
local COPPER = rgb(204, 116, 64)
local TRIM = rgb(70, 64, 96) -- отделка, железо
local DOOR = rgb(124, 84, 58)

local function hubPoint(angleDeg: number, dist: number, y: number?)
	return B.dir(angleDeg) * dist + Vector3.new(0, y or 0, 0)
end

-- Поворот «лицом к центру» (LookVector к башне)
local function faceCenter(pos)
	return B.facing(pos, -B.flat(pos))
end

----------------------------------------------------------------------
-- Тесла-башня: силуэт прежний, катушки и кольца шестигранные, на вершине кристалл
----------------------------------------------------------------------
local function teslaTower(parent, ctx, rng)
	local m = B.model(parent, "TeslaTower")
	local metal = rgb(70, 72, 96)
	local O = Vector3.zero
	-- основание: шестигранные ступени и неоновый обод
	B.hexPlate(m, O + Vector3.new(0, 0.8, 0), 9.2, 1.6, 0, 0, nil, B.shade(COBBLE, 0.6), { Shadow = true })
	B.hexPlate(m, O + Vector3.new(0, 1.35, 0), 9.5, 0.2, 0, 0, nil, ENERGY, B.neon())
	B.hexPlate(m, O + Vector3.new(0, 2.3, 0), 7, 1.4, math.rad(30), 0, nil, B.tint(metal, 0.5), { Shadow = true, Material = M.Metal })
	-- центральная колонна
	B.cylY(m, O + Vector3.new(0, 3 + 30, 0), 60, 3.4, metal, { Material = M.Metal, Shadow = true, Collide = false, Query = false })
	-- 4 ноги решётки
	local function leg(sx, sz, y)
		local t = (y - 3) / 58
		local w = 5.6 * (1 - t) + 1.9 * t
		return Vector3.new(sx * w, y, sz * w)
	end
	local corners = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
	local levels = { 3, 17, 31, 45, 59 }
	for _, s in corners do
		B.bar(m, leg(s[1], s[2], 3), leg(s[1], s[2], 61), 1.0, 1.0, metal, { Material = M.Metal, Shadow = true, Collide = false, Query = false })
		B.block(m, CFrame.new(leg(s[1], s[2], 3) + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(2, 0.8, 2), B.shade(metal, 0.6), B.deco({ Material = M.Metal }))
	end
	for li = 2, #levels do
		for c = 1, 4 do
			local a, b = corners[c], corners[c % 4 + 1]
			B.bar(m, leg(a[1], a[2], levels[li]), leg(b[1], b[2], levels[li]), 0.45, 0.45, B.shade(metal, 0.3), B.deco({ Material = M.Metal }))
			B.bar(m, leg(a[1], a[2], levels[li - 1]), leg(b[1], b[2], levels[li]), 0.3, 0.3, B.shade(metal, 0.5), B.deco({ Material = M.Metal }))
		end
	end
	-- катушки (Tower_Coil_1..4): медные шестигранные барабаны, неоновые обмотки — шестигранные кольца
	local coilY = { 11, 24, 37, 50 }
	local coilR = { 4.1, 3.7, 3.25, 2.8 }
	local coils = {}
	for k = 1, 4 do
		local y = coilY[k]
		local r = coilR[k]
		local yaw = k * 0.35
		B.hexPrism(m, Vector3.new(0, y, 0), r, 4.2, yaw, B.vary(COPPER, rng, 0.02), B.deco({ Material = M.Metal, Shadow = true }))
		B.hexPlate(m, Vector3.new(0, y + 0.6, 0), r + 0.18, 0.4, yaw, 0, nil, ENERGY, B.neon())
		B.cylY(m, Vector3.new(0, y + 2.35, 0), 0.5, r * 2 + 0.8, TRIM, B.deco({ Material = M.Metal }))
		-- белые керамические изоляторы над катушкой
		B.cylY(m, Vector3.new(0, y + 3.15, 0), 0.5, r * 1.05, P.PORCELAIN, B.deco())
		coils[k] = Vector3.new(0, y, 0)
	end
	-- верх: площадка, шестигранный тороид из брусков, гранёный кристалл с неоновым сердцем, шпиль
	B.hexPlate(m, Vector3.new(0, 61.5, 0), 4.3, 1, 0, 0, nil, TRIM, B.deco({ Material = M.Metal }))
	for k = 0, 5 do
		local a = k / 6 * TAU
		local p = Vector3.new(math.cos(a) * 4.2, 63.2, math.sin(a) * 4.2)
		B.block(m, B.facing(p, Vector3.new(math.cos(a), 0, math.sin(a))), Vector3.new(4.9, 1.6, 1.6), rgb(176, 182, 200), B.deco({ Material = M.Metal }))
	end
	local topY = 67.5
	B.gem(m, Vector3.new(0, topY, 0), 5.2, 0.3, rgb(190, 236, 255), B.deco({ Material = M.Glass, Transparency = 0.25, Shadow = false }))
	local heart = B.gem(m, Vector3.new(0, topY, 0), 2.4, 0.9, ENERGY, B.neon())
	B.light(heart, ENERGY, 50, 2.2)
	B.block(m, CFrame.new(0, topY + 7.5, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.4, 6, 0.4), rgb(176, 182, 200), B.deco({ Material = M.Metal }))
	B.gem(m, Vector3.new(0, topY + 11, 0), 1.1, 0, ENERGY, B.neon())
	-- неоновые пояса решётки
	for _, y in { 17, 45 } do
		local corner = {}
		for c = 1, 4 do
			corner[c] = leg(corners[c][1], corners[c][2], y) + Vector3.new(0, 0.6, 0)
		end
		for c = 1, 4 do
			B.bar(m, corner[c], corner[c % 4 + 1], 0.35, 0.35, ENERGY, B.neon())
		end
	end
	local baseLight = B.block(m, CFrame.new(0, 5, 0), Vector3.new(1, 1, 1), ENERGY, B.deco({ Transparency = 1, Shadow = false }))
	B.light(baseLight, ENERGY, 26, 1.2)
	return coils, Vector3.new(0, topY, 0)
end

----------------------------------------------------------------------
-- Дома с окнами (≤ 16 деталей + окна по 2)
----------------------------------------------------------------------
-- Фасады кварталов (STYLE §3.2): тёплый, мятный, лавандовый — по два квартала каждого
local FACADES = {
	rgb(236, 206, 166),
	rgb(160, 206, 190),
	rgb(190, 176, 224),
	rgb(236, 206, 166),
	rgb(160, 206, 190),
	rgb(190, 176, 224),
}
local ROOF_RED = rgb(176, 76, 62)
local ROOF_SLATE = rgb(70, 80, 108)
local WINDOW_OFF = rgb(48, 54, 72)
local WINDOW_ON = { rgb(255, 214, 140), rgb(255, 190, 110), rgb(190, 225, 255), rgb(255, 214, 140) }
local AWNINGS = { rgb(206, 72, 70), rgb(60, 120, 210), rgb(236, 186, 64), rgb(64, 160, 110) }

-- style: roof = "gable" | "tent" | "flat", roofColor, awning, bay
local function house(parent, windows, pos, w, d, floors, facade, rng, style)
	local m = B.model(parent, "House")
	local cf = faceCenter(pos) -- −Z (вперёд) смотрит к башне
	local fh = 5.4
	local H = floors * fh
	local shade = B.shade(facade, 1)
	local base = 0.9
	B.block(m, cf * CFrame.new(0, base / 2, 0), Vector3.new(w + 0.6, base, d + 0.6), COBBLE_SHADE, { Material = M.Cobblestone })
	B.block(m, cf * CFrame.new(0, base + H / 2, 0), Vector3.new(w, H, d), facade, { Shadow = true })
	-- угловые лопатки и междуэтажные пояса (фасад)
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * (w / 2 - 0.4), base + H / 2, -d / 2 - 0.2), Vector3.new(0.8, H, 0.5), shade, B.deco({ Shadow = false }))
	end
	for f = 1, floors - 1 do
		B.block(m, cf * CFrame.new(0, base + f * fh, -d / 2 - 0.2), Vector3.new(w + 0.3, 0.4, 0.5), shade, B.deco({ Shadow = false }))
	end
	-- дверь с козырьком и тёплым фонариком
	local doorX = if w > 11 then rng:range(-1.5, 1.5) else rng:range(-0.6, 0.6)
	B.block(m, cf * CFrame.new(doorX, base + 1.9, -d / 2 - 0.1), Vector3.new(2.2, 3.8, 0.3), B.vary(DOOR, rng, 0.04), B.deco())
	B.wedge(m, cf * CFrame.new(doorX, base + 4.25, -d / 2 - 1.0) * CFrame.Angles(0, math.pi, 0), Vector3.new(3.6, 0.9, 2), style.awning or TRIM, B.deco({ Material = M.Fabric }))
	B.block(m, cf * CFrame.new(doorX + 1.75, base + 3.4, -d / 2 - 0.35) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.6, 0.6, 0.6), LAMP, B.neon())
	-- окна: тёмные; клиент зажигает их (атрибут OnColor). Подоконник — вторая деталь
	local function window(x, y, face, sill, zOff)
		local wcf
		if face == "front" then
			wcf = cf * CFrame.new(x, y, -d / 2 - 0.06 - (zOff or 0))
		else
			wcf = cf * CFrame.new(x, y, d / 2 + 0.06) * CFrame.Angles(0, math.pi, 0)
		end
		local p = B.block(windows, wcf, Vector3.new(1.6, 2.2, 0.2), WINDOW_OFF, B.deco({ Shadow = false, Name = "Window", Reflectance = 0.08 }))
		p:SetAttribute("OnColor", rng:pick(WINDOW_ON))
		if sill then
			B.block(m, wcf * CFrame.new(0, -1.25, -0.2), Vector3.new(2.2, 0.3, 0.6), shade, B.deco({ Shadow = false }))
		end
		return wcf
	end
	local perFloor = math.clamp(math.floor((w - 1.5) / 3.4), 2, 3)
	for f = 0, floors - 1 do
		local y = base + f * fh + 2.9
		if f == 0 then
			for side = -1, 1, 2 do
				local x = doorX + side * (w / 4 + 0.7)
				if math.abs(x) < w / 2 - 1.3 then
					local wcf = window(x, y, "front", true)
					-- перемычка над окнами первого этажа и ставни у части окон
					B.block(m, wcf * CFrame.new(0, 1.35, -0.1), Vector3.new(2.2, 0.35, 0.4), shade, B.deco({ Shadow = false }))
					if rng:chance(0.3) then
						for s = -1, 1, 2 do
							B.block(m, wcf * CFrame.new(s * 1.1, 0, -0.08), Vector3.new(0.5, 2.2, 0.15), style.awning or B.shade(facade, 0.6), B.deco({ Shadow = false }))
						end
					end
				end
			end
		else
			for k = 1, perFloor do
				local x = -w / 2 + w * (k - 0.5) / perFloor
				if not (style.bay and f == 1 and k == 1) then
					window(x, y, "front", true)
				end
			end
			-- окно на задней стене (её видно с мостов и островов) — тоже зажигается кварталом
			if rng:chance(0.85) then
				window(rng:range(-w / 4, w / 4), y, "back", false)
			end
		end
	end
	-- эркер у каждого 4-го дома
	if style.bay then
		local bx = -w / 2 + w * 0.5 / perFloor
		local bcf = cf * CFrame.new(bx, base + fh + 2.6, -d / 2 - 0.7)
		B.block(m, bcf, Vector3.new(3.5, 4, 1.4), B.tint(facade, 0.3), B.deco({ Shadow = false }))
		B.block(m, bcf * CFrame.new(0, 2.15, -0.1), Vector3.new(3.9, 0.3, 1.8), shade, B.deco({ Shadow = false }))
		window(bx, base + fh + 2.9, "front", false, 1.4)
	end
	-- крыша
	local top = base + H
	local roofCol = style.roofColor
	if style.roof == "gable" then
		local rh = (d / 2) * rng:range(0.5, 0.65)
		local depth = d / 2 + 0.9
		B.wedge(m, cf * CFrame.new(0, top + rh / 2, -depth / 2 + 0.0), Vector3.new(w + 1.2, rh, depth), roofCol, B.deco({ Shadow = true }))
		B.wedge(m, cf * CFrame.new(0, top + rh / 2, depth / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(w + 1.2, rh, depth), B.shade(roofCol, 1), B.deco({ Shadow = true }))
		-- медный конёк и громоотвод — главный мотив города
		B.block(m, cf * CFrame.new(0, top + rh + 0.1, 0), Vector3.new(w + 1.4, 0.45, 0.6), COPPER, B.deco({ Material = M.Metal, Shadow = false }))
		local rx = rng:range(-w / 3, w / 3)
		local rodBase = (cf * CFrame.new(rx, top + rh + 0.3, 0)).Position
		B.cylY(m, rodBase + Vector3.new(0, 1.5, 0), 3, 0.18, COPPER, B.deco({ Material = M.Metal, Shadow = false }))
		B.gem(m, rodBase + Vector3.new(0, 3.2, 0), 0.45, rng:range(0, 1), ENERGY, B.neon())
		-- труба с шапкой
		local cx = if rx > 0 then rng:range(-w / 3, -1) else rng:range(1, w / 3)
		B.block(m, cf * CFrame.new(cx, top + rh * 0.5 + 0.75, d / 6), Vector3.new(1.3, rh + 1.5, 1.3), rgb(150, 86, 72), B.deco({ Shadow = false }))
		B.block(m, cf * CFrame.new(cx, top + rh + 1.6, d / 6), Vector3.new(1.7, 0.35, 1.7), TRIM, B.deco({ Shadow = false }))
	elseif style.roof == "tent" then
		local rh = math.min(w, d) * 0.42
		B.pyramid4(m, (cf * CFrame.new(0, top, 0)).Position, math.max(w, d) + 1.2, rh, B.yawOf(cf.LookVector), roofCol, B.deco({ Shadow = true }))
		local tip = (cf * CFrame.new(0, top + rh, 0)).Position
		B.cylY(m, tip + Vector3.new(0, 1.3, 0), 2.8, 0.18, COPPER, B.deco({ Material = M.Metal, Shadow = false }))
		B.gem(m, tip + Vector3.new(0, 2.9, 0), 0.45, 0.3, ENERGY, B.neon())
	else
		-- плоская крыша с парапетом и баком на опорах
		B.block(m, cf * CFrame.new(0, top + 0.35, 0), Vector3.new(w + 0.6, 0.7, d + 0.6), shade, B.deco({ Shadow = false }))
		local tp = (cf * CFrame.new(rng:range(-w / 4, w / 4), top + 2.3, rng:range(0, d / 4))).Position
		B.cylY(m, tp, 2.6, 2.4, rgb(134, 98, 72), B.deco({ Shadow = false }))
		B.block(m, CFrame.new(tp + Vector3.new(0, 1.45, 0)) * CFrame.Angles(0, math.rad(30), 0), Vector3.new(2.7, 0.35, 2.7), COPPER, B.deco({ Material = M.Metal, Shadow = false }))
		B.cylY(m, tp + Vector3.new(0, 2.6, 0), 2.2, 0.16, COPPER, B.deco({ Material = M.Metal, Shadow = false }))
		B.gem(m, tp + Vector3.new(0, 3.9, 0), 0.45, 0.3, ENERGY, B.neon())
	end
	return { cf = cf, w = w, d = d, H = H + base, model = m }
end

-- Квартал: ряд домов по дуге от a0 до a1 (градусы), фасады к башне. Возвращает список домов с углами
local function district(parent, windowsFolder, k, a0, a1, rOuter, depthMin, depthMax, rng)
	local m = B.model(parent, "Houses_" .. k)
	local facade0 = FACADES[k]
	local a = a0
	local idx = 0
	local list = {}
	local spans = {}
	-- сначала разложим дома по дуге, чтобы знать крайние (у них крыша-шатёр)
	while true do
		local w = rng:range(9, 12.5)
		local d = rng:range(depthMin, depthMax)
		local rc = rOuter - d / 2
		local span = math.deg((w + rng:range(1.4, 2.6)) / rc)
		if a + span > a1 + 0.5 then
			break
		end
		table.insert(spans, { a = a, span = span, w = w, d = d, rc = rc })
		a += span
	end
	for n, s in spans do
		idx += 1
		local mid = s.a + s.span / 2
		local pos = hubPoint(mid, s.rc)
		local floors = if rng:chance(0.45) then 3 else 2
		if idx % 3 == 2 then
			floors = 3
		end
		local corner = n == 1 or n == #spans
		local roof = if corner then "tent" elseif rng:chance(0.3) then "flat" else "gable"
		local h, sat, val = facade0:ToHSV()
		local facade = Color3.fromHSV(h, sat, math.clamp(val * rng:range(0.97, 1.03), 0, 1))
		local hs = house(m, windowsFolder, pos, s.w, s.d, floors, facade, rng, {
			roof = roof,
			roofColor = B.vary(if (k + n) % 3 == 0 then ROOF_SLATE else ROOF_RED, rng, 0.02),
			awning = if rng:chance(0.55) then rng:pick(AWNINGS) else nil,
			bay = idx % 4 == 0 and floors >= 2,
		})
		hs.angle = mid
		table.insert(list, hs)
	end
	return m, list
end

----------------------------------------------------------------------
-- Табло: рама «Отделка», экран Night800, лента-заголовок как в окнах UI;
-- метка Board_<name> с SurfaceGui "Gui" → TextLabel "Title" и Frame "Content" (строки заполняет сервер)
----------------------------------------------------------------------
local function infoBoard(parent, markers, name, title, pos, accent, rng)
	local m = B.model(parent, "Board_" .. name .. "_Frame")
	local cf = faceCenter(pos)
	local W_, H_, lift = 15, 8.6, 3
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * (W_ / 2 + 0.5), (lift + H_ + 1) / 2, 0.4) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.9, lift + H_ + 1, 0.9), TRIM, { Shadow = true })
	end
	B.block(m, cf * CFrame.new(0, lift + H_ / 2, 0.4), Vector3.new(W_ + 1.2, H_ + 1.2, 0.8), TRIM, { Shadow = true })
	B.block(m, cf * CFrame.new(0, lift + H_ / 2, 0), Vector3.new(W_, H_, 0.1), rgb(30, 28, 66), B.deco({ Shadow = false, Name = "Screen" }))
	-- карниз и неоновое подчёркивание снизу (не рамка)
	B.block(m, cf * CFrame.new(0, lift + H_ + 1.25, 0.4), Vector3.new(W_ + 2.2, 0.6, 1.3), B.shade(TRIM, 0.6), B.deco())
	B.block(m, cf * CFrame.new(0, lift - 0.35, -0.05), Vector3.new(W_ * 0.8, 0.2, 0.1), accent, B.neon())
	B.gem(m, (cf * CFrame.new(0, lift + H_ + 2.1, 0.4)).Position, 0.9, 0.3, accent, B.neon())
	-- метка с интерфейсом (невидимая деталь прямо перед экраном)
	local marker = B.marker(markers, "Board_" .. name, cf * CFrame.new(0, lift + H_ / 2, -0.12), Vector3.new(W_, H_, 0.1))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.MaxDistance = 250
	gui.ResetOnSpawn = false
	gui.Parent = marker
	-- лента-заголовок: Ink, полоска акцента снизу, наклон −2°
	local ribbon = Instance.new("Frame")
	ribbon.Name = "TitleRibbon"
	ribbon.BackgroundColor3 = B.INK
	ribbon.BorderSizePixel = 0
	ribbon.Size = UDim2.fromScale(0.86, 0.17)
	ribbon.Position = UDim2.fromScale(0.05, 0.015)
	ribbon.Rotation = -2
	ribbon.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = ribbon
	local strip = Instance.new("Frame")
	strip.Name = "Accent"
	strip.BackgroundColor3 = accent
	strip.BorderSizePixel = 0
	strip.AnchorPoint = roblox.Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0.03, 1)
	strip.Size = UDim2.new(0.94, 0, 0, 6)
	strip.Parent = ribbon
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(0.8, 0.13)
	t.Position = UDim2.fromScale(0.08, 0.025)
	t.Rotation = -2
	t.FontFace = B.FontDisplay
	t.Text = B.upper(title)
	t.TextColor3 = B.CREAM
	t.TextScaled = true
	t.ZIndex = 2
	t.Parent = gui
	B.stroke(t, 3)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(0.94, 0.78)
	content.Position = UDim2.fromScale(0.03, 0.2)
	content.Parent = gui
	local _ = rng
	return marker
end

----------------------------------------------------------------------
-- Киоски
----------------------------------------------------------------------
local function apron(parent, pos, r, color)
	B.cylY(parent, pos + Vector3.new(0, 0.02, 0), 0.12, r * 2, color, B.deco({ Shadow = false, Name = "Apron" }))
end

-- Магазин: прилавок, полки с банками и громоотводами, полосатый навес, вывеска
local function shopKiosk(parent, pos, rng)
	local m = B.model(parent, "Kiosk_Shop")
	local cf = faceCenter(pos)
	local wood = rgb(166, 114, 72)
	local yellow, blue = rgb(255, 204, 70), rgb(60, 110, 220)
	-- прилавок
	B.block(m, cf * CFrame.new(0, 1.6, 0), Vector3.new(10, 3.2, 2.4), wood, { Material = M.WoodPlanks, Shadow = true })
	B.block(m, cf * CFrame.new(0, 3.35, -0.1), Vector3.new(10.6, 0.3, 2.9), B.tint(wood, 0.8), B.deco())
	B.block(m, cf * CFrame.new(0, 2.2, -1.25), Vector3.new(8, 0.22, 0.1), yellow, B.neon())
	-- задняя стенка с полками
	B.block(m, cf * CFrame.new(0, 4.2, 4.2), Vector3.new(11, 8.4, 0.8), B.shade(wood, 0.7), { Material = M.WoodPlanks, Shadow = true })
	for _, y in { 3.6, 6 } do
		B.block(m, cf * CFrame.new(0, y, 3.4), Vector3.new(10, 0.25, 1.2), B.tint(wood, 0.8), B.deco())
	end
	-- товары: банки (стекло + неоновое ядро) и громоотводы с гранёными наконечниками
	local jarColors = { rgb(110, 200, 255), rgb(190, 120, 255), rgb(80, 255, 150), rgb(255, 210, 60) }
	for k = 1, 4 do
		local p = (cf * CFrame.new(-3.6 + (k - 1) * 2.4, 4.45, 3.3)).Position
		B.cylY(m, p, 1.5, 1.1, rgb(200, 230, 255), B.deco({ Material = M.Glass, Transparency = 0.5 }))
		B.cylY(m, p, 1.2, 0.75, jarColors[k], B.neon())
		B.cylY(m, p + Vector3.new(0, 0.85, 0), 0.25, 1.2, TRIM, B.deco({ Material = M.Metal }))
	end
	for k = 1, 3 do
		local base = (cf * CFrame.new(-2.5 + (k - 1) * 2.5, 6.15, 3.4)).Position
		B.block(m, CFrame.new(base + Vector3.new(0, 0.95, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(0.24, 1.9, 0.24), ({ COPPER, rgb(200, 206, 216), rgb(240, 196, 70) })[k], B.deco({ Material = M.Metal }))
		B.gem(m, base + Vector3.new(0, 2.1, 0), 0.45, k, ENERGY, B.neon())
	end
	-- стойки и полосатый навес (клинья)
	for _, sx in { -5.4, 5.4 } do
		for _, sz in { -1.4, 4.2 } do
			B.block(m, cf * CFrame.new(sx, 4.4, sz), Vector3.new(0.5, 8.8, 0.5), TRIM, {})
		end
	end
	local stripes = 6
	for k = 0, stripes - 1 do
		local x = -6 + (k + 0.5) * 12 / stripes
		B.wedge(m, cf * CFrame.new(x, 9.2, 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(12 / stripes, 1.6, 7.6), if k % 2 == 0 then yellow else blue, B.deco({ Material = M.Fabric, Shadow = true }))
		B.block(m, cf * CFrame.new(x, 8.15, -3.2), Vector3.new(12 / stripes, 0.5, 0.15), if k % 2 == 0 then blue else yellow, B.deco({ Material = M.Fabric }))
	end
	-- вывеска над навесом
	B.sign(m, cf * CFrame.new(0, 11.6, 4.1), 10, 2.6, { { Text = "Магазин" } }, { Underline = yellow })
	local glow = B.block(m, cf * CFrame.new(0, 7.6, 1.5), Vector3.new(1, 1, 1), LAMP, B.deco({ Transparency = 1 }))
	B.light(glow, LAMP, 18, 1)
	-- ящики и бочка рядом
	P.crate(m, (cf * CFrame.new(-7, 0, 1)).Position, rng)
	P.crate(m, (cf * CFrame.new(-7.4, 0, 3.2)).Position, rng)
	P.barrel(m, (cf * CFrame.new(7, 0, 2)).Position, rng)
	return m
end

-- Инкубаторий: шестигранная площадка, 3 стойки с коконами, стеклянная арка-оранжерея, вывеска
local function hatcheryKiosk(parent, markers, pos, rng, ctx)
	local Pets, Models = ctx.Pets, ctx.Models
	local m = B.model(parent, "Kiosk_Hatchery")
	local cf = faceCenter(pos)
	local green = rgb(90, 200, 110)
	B.hexPlate(m, pos + Vector3.new(0, 0.3, 0), 9.4, 0.6, B.yawOf(cf.LookVector), 0, nil, rgb(206, 200, 214), {})
	B.hexPlate(m, pos + Vector3.new(0, 0.24, 0), 9.8, 0.5, B.yawOf(cf.LookVector), 0, nil, green, B.neon())
	-- оранжерея: дуга из стоек и стекло позади стоек (два стекла, крупные стёкла запрещены)
	local metal = rgb(226, 228, 240)
	local arcPts = {}
	for k = 0, 6 do
		local a = math.pi * k / 6
		table.insert(arcPts, cf * Vector3.new(math.cos(a) * 8, 0.6 + math.sin(a) * 9, 4.5))
	end
	for k = 1, #arcPts - 1 do
		B.bar(m, arcPts[k], arcPts[k + 1], 0.5, 0.5, metal, B.deco({ Material = M.Metal }))
	end
	for _, x in { -8, 8 } do
		B.bar(m, cf * Vector3.new(x, 0.6, 4.5), cf * Vector3.new(x, 0.6, 1), 0.5, 0.5, metal, B.deco({ Material = M.Metal }))
	end
	for s = -1, 1, 2 do
		B.block(m, cf * CFrame.new(s * 3.9, 4.6, 4.6), Vector3.new(7.6, 8, 0.2), rgb(190, 240, 210), B.deco({ Material = M.Glass, Transparency = 0.55 }))
	end
	B.sign(m, cf * CFrame.new(0, 11.2, 4.4), 10.5, 2.5, { { Text = "Коконы" } }, { Underline = green })
	-- стойки
	for k, id in Pets.CocoonOrder do
		local def = Pets.Cocoons[id]
		local x = (k - 2) * 5
		local z = if k == 2 then 0.8 else 0
		local base = cf * CFrame.new(x, 0, z)
		B.hexPrism(m, (base * CFrame.new(0, 1.8, 0)).Position, 1.5, 2.4, B.yawOf(cf.LookVector), rgb(226, 222, 232), { Shadow = true })
		B.hexPlate(m, (base * CFrame.new(0, 3.1, 0)).Position, 1.85, 0.3, B.yawOf(cf.LookVector), 0, nil, TRIM, B.deco({ Material = M.Metal }))
		local ringP = B.hexPlate(m, (base * CFrame.new(0, 3.15, 0)).Position, 1.65, 0.3, B.yawOf(cf.LookVector) + math.rad(30), 0, nil, def.Color, B.neon())
		B.light(ringP[1], def.Color, 10, 0.8)
		local top = base * CFrame.new(0, 3.3, 0)
		-- витринный кокон (статичный, якорный)
		local cm = Models.cocoon(id)
		ctx.place(cm, top, m)
		B.marker(markers, "Cocoon_" .. id, top)
		-- табличка с названием и ценой
		local plaque = B.block(m, base * CFrame.new(0, 1.6, -1.55) * CFrame.Angles(-0.25, 0, 0), Vector3.new(2.6, 1.4, 0.2), B.SIGN, B.deco({ Name = "Plaque" }))
		B.text(plaque, {
			{ Text = string.gsub(def.Name, " кокон", ""), Font = B.FontDisplayFlat, Size = 1, Rotation = 0 },
			{ Text = tostring(def.Cost) .. " 💎", Font = B.FontNumber, Color = rgb(186, 242, 255), Size = 0.9 },
		}, { Face = Enum.NormalId.Front, PixelsPerStud = 60 })
	end
	local _ = rng
	return m
end

-- Галерея: 12 пьедесталов дугой вокруг стойки с вывеской
local function galleryKiosk(parent, markers, pos, rng)
	local m = B.model(parent, "Kiosk_Gallery")
	local cf = faceCenter(pos)
	B.cylY(m, pos + Vector3.new(0, 0.03, 0), 0.14, 34, rgb(206, 200, 214), B.deco({ Shadow = false, Name = "Floor" }))
	B.cylY(m, pos + Vector3.new(0, 0.05, 0), 0.14, 30, rgb(150, 140, 180), B.deco({ Shadow = false, Name = "FloorInlay" }))
	B.cylY(m, pos + Vector3.new(0, 0.07, 0), 0.14, 27, rgb(218, 212, 224), B.deco({ Shadow = false, Name = "FloorCenter" }))
	-- стойка-пюпитр с вывеской
	B.block(m, cf * CFrame.new(0, 1.2, 0), Vector3.new(2.6, 2.4, 1.6), TRIM, {})
	local lect = B.block(m, cf * CFrame.new(0, 2.7, -0.2) * CFrame.Angles(-0.5, 0, 0), Vector3.new(3.2, 0.25, 2.2), B.SIGN, B.deco({ Name = "Lectern" }))
	B.text(lect, { { Text = "Галерея", Color = rgb(255, 226, 140) }, { Text = "фульгуритов" } }, { Face = Enum.NormalId.Top, PixelsPerStud = 60 })
	local back = -B.flat(cf.LookVector) -- от башни
	local right = Vector3.new(-back.Z, 0, back.X)
	for j = 1, 12 do
		local phi = math.rad(-105 + (j - 1) * 210 / 11)
		local dir = back * math.cos(phi) + right * math.sin(phi)
		local p = pos + dir * 13
		local pcf = B.facing(p, -dir)
		local stone = B.vary(rgb(228, 224, 234), rng, 0.015)
		B.block(m, pcf * CFrame.new(0, 0.3, 0), Vector3.new(3, 0.6, 3), TRIM, {})
		B.block(m, pcf * CFrame.new(0, 1.9, 0), Vector3.new(2.1, 2.6, 2.1), stone, { Shadow = true })
		B.block(m, pcf * CFrame.new(0, 3.4, 0), Vector3.new(2.8, 0.4, 2.8), B.shade(TRIM, 0.3), B.deco())
		B.block(m, pcf * CFrame.new(0, 2.6, -1.08), Vector3.new(1.5, 0.2, 0.1), rgb(255, 210, 120), B.neon())
		-- метка: центр верхней грани пьедестала, лицом к центру галереи
		B.marker(markers, "Pedestal_" .. j, pcf * CFrame.new(0, 3.6, 0))
	end
	return m
end

-- Генератор перезапуска: ступенчатая шестигранная площадка, барабан с неоном, кольцо лопаток, 4 пилона, вывеска
local function rebirthKiosk(parent, pos, rng)
	local m = B.model(parent, "Kiosk_Rebirth")
	local cf = faceCenter(pos)
	local glow = rgb(255, 90, 160)
	local dark = rgb(50, 46, 70)
	B.hexPlate(m, pos + Vector3.new(0, 0.35, 0), 8.6, 0.7, 0, 0, nil, rgb(74, 70, 96), {})
	B.hexPlate(m, pos + Vector3.new(0, 1.0, 0), 6.4, 0.6, math.rad(30), 0, nil, rgb(96, 92, 120), {})
	B.hexPlate(m, pos + Vector3.new(0, 0.95, 0), 6.6, 0.6, math.rad(30), 0, nil, glow, B.neon())
	-- барабан генератора
	B.hexPrism(m, pos + Vector3.new(0, 4.3, 0), 3.3, 6, 0, dark, { Shadow = true, Material = M.Metal })
	for _, y in { 2.4, 6.2 } do
		B.hexPlate(m, pos + Vector3.new(0, y, 0), 3.5, 0.4, 0, 0, nil, glow, B.neon())
	end
	B.hexPlate(m, pos + Vector3.new(0, 7.6, 0), 3.9, 0.6, math.rad(30), 0, nil, B.tint(dark, 0.6), B.deco({ Material = M.Metal }))
	local core = B.gem(m, pos + Vector3.new(0, 9.6, 0), 2.8, 0.3, glow, B.neon())
	B.light(core, glow, 24, 1.6)
	-- лопатки вокруг
	for k = 0, 9 do
		local a = k / 10 * TAU
		local p = pos + Vector3.new(math.cos(a) * 4.8, 9.6 + math.sin(a * 2) * 0.4, math.sin(a) * 4.8)
		B.block(m, B.facing(p, Vector3.new(-math.sin(a), 0, math.cos(a))), Vector3.new(0.4, 0.4, 2.6), rgb(200, 180, 224), B.deco({ Material = M.Metal }))
	end
	-- пилоны с гранёными навершиями
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = pos + Vector3.new(math.cos(a) * 6.3, 1.3, math.sin(a) * 6.3)
		B.block(m, CFrame.new(p + Vector3.new(0, 3, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(1.2, 6, 1.2), dark, { Material = M.Metal, Shadow = true })
		B.gem(m, p + Vector3.new(0, 6.7, 0), 0.9, a, glow, B.neon())
	end
	B.sign(m, cf * CFrame.new(0, 13.4, 0), 11, 3, { { Text = "Перезапуск" }, { Text = "генератора" } }, { Underline = glow })
	local _ = rng
	return m
end

-- Ежедневные награды: большой сундук с золотом, монеты, календарь-вывеска
local function dailyKiosk(parent, pos, rng)
	local m = B.model(parent, "Kiosk_Daily")
	local cf = faceCenter(pos)
	local wood = rgb(150, 92, 56)
	local gold = rgb(255, 200, 70)
	B.hexPlate(m, pos + Vector3.new(0, 0.3, 0), 7.6, 0.6, B.yawOf(cf.LookVector), 0, nil, rgb(176, 156, 130), {})
	local c = cf * CFrame.new(0, 0.6, 0)
	B.block(m, c * CFrame.new(0, 1.7, 0), Vector3.new(6.4, 3.4, 4), wood, { Material = M.WoodPlanks, Shadow = true })
	-- крышка: два ската-клина (гранёная, не полуцилиндр)
	B.wedge(m, c * CFrame.new(0, 4.0, -1.0), Vector3.new(6.5, 1.2, 2.05), B.tint(wood, 0.4), B.deco({ Material = M.WoodPlanks, Shadow = true }))
	B.wedge(m, c * CFrame.new(0, 4.0, 1.0) * CFrame.Angles(0, math.pi, 0), Vector3.new(6.5, 1.2, 2.05), B.shade(wood, 0.6), B.deco({ Material = M.WoodPlanks, Shadow = true }))
	-- золотые оковки
	for _, x in { -2.6, 2.6 } do
		B.block(m, c * CFrame.new(x, 1.7, 0), Vector3.new(0.6, 3.5, 4.1), gold, B.deco({ Material = M.Metal }))
	end
	B.block(m, c * CFrame.new(0, 3.42, -2.02), Vector3.new(6.42, 0.16, 0.1), gold, B.neon())
	B.block(m, c * CFrame.new(0, 2.9, -2.1), Vector3.new(1.1, 1.3, 0.3), gold, B.deco({ Material = M.Metal }))
	B.block(m, c * CFrame.new(0, 2.8, -2.27), Vector3.new(0.25, 0.5, 0.05), rgb(40, 30, 20), B.deco())
	local shine = B.block(m, c * CFrame.new(0, 4, -1), Vector3.new(1, 1, 1), gold, B.deco({ Transparency = 1 }))
	B.light(shine, gold, 16, 1.2)
	-- монеты
	for k = 1, 8 do
		local p = (cf * CFrame.new(rng:range(-5, 5), 0.68 + (k % 3) * 0.2, rng:range(-3.5, -1.5))).Position
		local coin = B.cylY(m, p, 0.2, 1, gold, B.deco({ Material = M.Metal }))
		coin.CFrame = coin.CFrame * CFrame.Angles(rng:range(-0.2, 0.2), 0, rng:range(-0.3, 0.3))
	end
	-- вывеска-календарь на стойках
	for _, x in { -5.5, 5.5 } do
		B.block(m, cf * CFrame.new(x, 5, 3.5), Vector3.new(0.6, 10, 0.6), TRIM, {})
	end
	B.sign(m, cf * CFrame.new(0, 9, 3.5), 10.5, 3, { { Text = "Награды" }, { Text = "каждый день" } }, { Underline = gold })
	for d = 0, 6 do
		B.block(m, cf * CFrame.new(-4.5 + d * 1.5, 6.6, 3.45) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.9, 0.9, 0.3), if d == 6 then gold else rgb(70, 80, 130), if d == 6 then B.neon() else B.deco())
	end
	return m
end

----------------------------------------------------------------------
-- Гирлянды над улицами: провод-Beam между домами по обе стороны дороги и неоновые бусины тёплых цветов
----------------------------------------------------------------------
local function garland(parent, a, aPart, b, bPart, rng)
	local f = B.wire(aPart, a, bPart, b, TRIM, 0.12, 2.6)
	local len = (b - a).Magnitude
	local n = math.clamp(math.floor(len / 3.4), 3, 9)
	for k = 1, n - 1 do
		local p = f(k / n) - Vector3.new(0, 0.25, 0)
		B.gem(parent, p, 0.5, rng:range(0, 1), WINDOW_ON[(k % #WINDOW_ON) + 1], B.neon({ Name = "Bulb" }))
	end
end

----------------------------------------------------------------------
-- Хаб целиком
----------------------------------------------------------------------
function Hub.build(ctx, parent)
	local Config, Zones = ctx.Config, ctx.Zones
	local rng = B.rng(4242)
	local R = Config.Hub.Radius
	local hub = B.model(parent, "Hub")
	local decor = B.model(hub, "Decor")
	local city = B.folder(ctx.Root, "City")

	local openings = {}
	for _, g in Zones.Geo do
		table.insert(openings, g.Dir)
	end
	Island.body(hub, {
		name = "Ground",
		center = Zones.HubCenter,
		radius = R,
		seed = 77,
		segments = 30,
		base = 1.8,
		amp = 5,
		ampExact = true,
		top = COBBLE,
		topMaterial = M.Cobblestone,
		dirt = rgb(140, 104, 82),
		rock = rgb(124, 118, 142),
		depth = 76,
		openings = openings,
		openHalfDeg = 7,
		drips = 0,
		stalactites = 5,
		energy = ENERGY,
		walls = { radius = R + 0.8, height = 18, segments = 40 },
		wallParent = ctx.Walls,
		hang = function(m, p, out, r)
			-- кабели и фонарики под краем площади
			local q = p + out * 1.5 - Vector3.new(0, r:range(3, 6), 0)
			B.bar(m, p, q, 0.25, 0.25, rgb(40, 38, 54), B.deco({ Material = M.Metal }))
			B.gem(m, q, 0.8, r:range(0, 1), LAMP, B.neon())
		end,
		hangCount = 10,
	})

	-- площадь: светлый центр, кольцо подстанции (радиус Zones.HubSellRadius)
	local O = Zones.HubCenter
	B.cylY(decor, O + Vector3.new(0, 0, 0), 0.12, 68, B.mix(COBBLE, COBBLE_SHADE, 0.35), B.deco({ Material = M.Cobblestone, Shadow = false, Name = "PlazaRing" }))
	B.cylY(decor, O + Vector3.new(0, 0.06, 0), 0.12, 42, COBBLE_LIGHT, B.deco({ Shadow = false, Name = "PlazaCenter" }))
	B.ring(decor, O + Vector3.new(0, -0.02, 0), Zones.HubSellRadius, 1.4, 0.26, 24, ENERGY, B.neon({ Name = "SellRing" }))
	B.ring(decor, O + Vector3.new(0, -0.02, 0), Zones.HubSellRadius + 1.3, 0.5, 0.22, 20, TRIM, B.deco({ Material = M.Metal, Name = "SellRingRim" }))
	B.ring(decor, O + Vector3.new(0, -0.02, 0), Zones.HubSellRadius - 1.3, 0.5, 0.22, 18, TRIM, B.deco({ Material = M.Metal, Name = "SellRingRim" }))

	local coils, top = teslaTower(hub, ctx, rng)
	for k, p in coils do
		B.marker(ctx.Markers, "Tower_Coil_" .. k, CFrame.new(p))
	end
	B.marker(ctx.Markers, "Tower_Top", CFrame.new(top))

	-- дороги к мостам (чуть выше площади, без коллизий) с бордюрами и медной зигзаг-инкрустацией от башни
	for _, g in Zones.Geo do
		local a = g.Dir
		local right = Vector3.new(-a.Z, 0, a.X)
		local p0 = a * 34
		local p1 = a * (R + 1.4)
		B.bar(decor, p0 + Vector3.new(0, 0.05, 0), p1 + Vector3.new(0, 0.05, 0), Config.BridgeWidth, 0.1, rgb(176, 160, 150), B.deco({ Shadow = false, Name = "Road" }))
		for side = -1, 1, 2 do
			B.bar(decor, p0 + right * side * (Config.BridgeWidth / 2 + 0.4) + Vector3.new(0, 0.1, 0), p1 + right * side * (Config.BridgeWidth / 2 + 0.4) + Vector3.new(0, 0.1, 0), 0.8, 0.2, COBBLE_SHADE, B.deco({ Shadow = false, Name = "Curb" }))
		end
		B.zigzag(decor, a * 22 + Vector3.new(0, 0.16, 0), a * (R - 2) + Vector3.new(0, 0.16, 0), 4, 0.8, B.tint(COPPER, 0.6), B.deco({ Shadow = false, Name = "Inlay", Reflectance = 0.15 }), Vector3.yAxis, 0.05)
		-- фонари вдоль дороги
		for _, d in { 46, 84 } do
			for side = -1, 1, 2 do
				P.lamp(decor, a * d + right * side * (Config.BridgeWidth / 2 + 2.2), rng, LAMP, 9, TRIM)
			end
		end
	end

	-- кварталы (6 папок окон City.District_1..6)
	local sectors = {
		{ 12, 60, 94.5, 9, 12 },
		{ 84, 132, 94.5, 9, 12 },
		{ 152, 174, 95, 7.5, 8.5 },
		{ 186, 208, 95, 7.5, 8.5 },
		{ 228, 276, 94.5, 9, 12 },
		{ 300, 348, 94.5, 9, 12 },
	}
	local houses = B.model(hub, "Houses")
	local allHouses = {}
	for k, s in ipairs(sectors) do
		local windows = B.folder(city, "District_" .. k)
		local _, list = district(houses, windows, k, s[1], s[2], s[3], s[4], s[5], rng)
		for _, h in list do
			table.insert(allHouses, h)
		end
	end
	-- гирлянды: через каждую дорогу между ближайшими домами по обе стороны, у карниза
	local lights = B.model(decor, "Garlands")
	for _, g in Zones.Geo do
		local roadA = (math.deg(math.atan2(g.Dir.X, -g.Dir.Z)) + 360) % 360
		local left, right = nil, nil
		for _, h in allHouses do
			local diff = ((h.angle - roadA + 540) % 360) - 180
			if diff < 0 and (not left or diff > left[2]) then
				left = { h, diff }
			elseif diff > 0 and (not right or diff < right[2]) then
				right = { h, diff }
			end
		end
		if left and right then
			local hl, hr = left[1], right[1]
			-- передний угол боковой стены, обращённой к дороге
			local function corner(h, sign)
				local y = math.min(hl.H, hr.H) - 1.2
				return (h.cf * CFrame.new(sign * h.w / 2, y, -h.d / 2 + 0.8)).Position
			end
			-- у дома слева от дороги к дороге смотрит его правая (+X) сторона? определим по расстоянию
			local function nearSide(h, other)
				local pa = (h.cf * CFrame.new(h.w / 2, 0, 0)).Position
				local pb = (h.cf * CFrame.new(-h.w / 2, 0, 0)).Position
				return if (pa - other.cf.Position).Magnitude < (pb - other.cf.Position).Magnitude then 1 else -1
			end
			local a = corner(hl, nearSide(hl, hr))
			local b = corner(hr, nearSide(hr, hl))
			garland(lights, a, hl.model:FindFirstChildWhichIsA("BasePart"), b, hr.model:FindFirstChildWhichIsA("BasePart"), rng)
		end
	end

	-- киоски (метки Kiosk_* — в точках Zones.Hub.*)
	local kiosks = B.model(hub, "Kiosks")
	local H = Zones.Hub
	for _, k in { { "Shop", H.Shop }, { "Hatchery", H.Hatchery }, { "Rebirth", H.Rebirth }, { "Daily", H.Daily } } do
		apron(decor, k[2], 11, B.mix(COBBLE, COBBLE_LIGHT, 0.5))
	end
	shopKiosk(kiosks, H.Shop, rng)
	hatcheryKiosk(kiosks, ctx.Markers, H.Hatchery, rng, ctx)
	galleryKiosk(kiosks, ctx.Markers, H.Gallery, rng)
	rebirthKiosk(kiosks, H.Rebirth, rng)
	dailyKiosk(kiosks, H.Daily, rng)
	for _, k in { "Shop", "Hatchery", "Gallery", "Rebirth", "Daily" } do
		B.marker(ctx.Markers, "Kiosk_" .. k, faceCenter(H[k] + Vector3.new(0, 3, 0)))
	end

	-- табло
	local boards = B.model(hub, "Boards")
	infoBoard(boards, ctx.Markers, "Leaders", "Лучшие ловцы", H.BoardLeaders, rgb(255, 210, 60), rng)
	infoBoard(boards, ctx.Markers, "Forecast", "Прогноз бури", H.BoardForecast, ENERGY, rng)
	infoBoard(boards, ctx.Markers, "Hall", "Зал славы", hubPoint(180, 88), rgb(255, 112, 190), rng)

	-- скамейки и клумбы вокруг внутреннего круга (между дорогами), тополя в кадках у киосков
	local pal = { trunk = DOOR, leafA = rgb(78, 158, 70), leafB = rgb(122, 186, 72), flowers = { rgb(255, 120, 160), rgb(255, 214, 90), rgb(250, 248, 255), rgb(196, 146, 255) }, stone = COBBLE }
	for k = 0, 4 do
		local base = k * 72 + 36
		for _, off in { -19, 19 } do
			local a = base + off + rng:range(-2, 2)
			local p = hubPoint(a, 38)
			P.bench(decor, p, -B.flat(p), rng)
		end
		for _, off in { -27, 27 } do
			local a = base + off
			pal.yaw = math.rad(-a)
			P.planter(decor, hubPoint(a, 39), rng, pal, 3.6)
		end
		for _, off in { if k % 2 == 0 then -12 else 12 } do
			local a = base + off
			local p = hubPoint(a, 70)
			B.block(decor, CFrame.new(p + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, math.rad(-a + 45), 0), Vector3.new(2.6, 1.8, 2.6), COBBLE_SHADE, {})
			P.poplar(decor, p + Vector3.new(0, 1.6, 0), rng, pal, 0.62)
		end
	end

	-- спавн хаба: SpawnLocation (на случай, если персонаж появится до телепорта)
	local sp = Instance.new("SpawnLocation")
	sp.Name = "HubSpawn"
	sp.Anchored = true
	sp.Size = Vector3.new(6, 0.2, 6)
	sp.CFrame = CFrame.new(Zones.Hub.Spawn.X, 0.02, Zones.Hub.Spawn.Z)
	sp.Transparency = 1
	sp.CanCollide = false
	sp.CanQuery = false
	sp.CanTouch = false
	sp.Neutral = true
	sp.Duration = 0
	sp.Enabled = true
	sp.Parent = hub
	B.count += 1
	local _ = W

	return hub
end

return Hub
