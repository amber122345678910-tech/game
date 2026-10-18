--!nocheck
-- Хаб «Электроград»: брусчатая площадь, Тесла-башня с катушками, кольцо подстанции,
-- 6 кварталов домов с окнами (зажигаются клиентом), киоски, табло, фонари, скамейки, клумбы.
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Island = require("./island")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance
local UDim2 = roblox.UDim2
local M = Enum.Material
local rgb = B.rgb

local Hub = {}

local ACCENT = rgb(120, 210, 255) -- электрический голубой (акцент хаба)
local LAMP = rgb(255, 210, 150)
local STONE_DARK = rgb(96, 92, 104)

local function hubPoint(angleDeg: number, dist: number, y: number?)
	return B.dir(angleDeg) * dist + Vector3.new(0, y or 0, 0)
end

-- Поворот «лицом к центру» (LookVector к башне)
local function faceCenter(pos)
	return B.facing(pos, -B.flat(pos))
end

----------------------------------------------------------------------
-- Тесла-башня
----------------------------------------------------------------------
local function teslaTower(parent, ctx, rng)
	local m = B.model(parent, "TeslaTower")
	local metal = rgb(70, 74, 88)
	local steel = rgb(176, 182, 196)
	local copper = rgb(198, 112, 64)
	local O = Vector3.zero
	-- основание: плита, ступень, неоновый обод
	B.cylY(m, O + Vector3.new(0, 0.8, 0), 1.6, 16, rgb(82, 84, 98), { Material = M.Concrete, Shadow = true })
	B.cylY(m, O + Vector3.new(0, 1.35, 0), 0.2, 16.5, ACCENT, B.neon())
	B.cylY(m, O + Vector3.new(0, 2.3, 0), 1.4, 12, rgb(100, 102, 116), { Material = M.DiamondPlate, Shadow = true })
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
		B.rod(m, leg(s[1], s[2], 3), leg(s[1], s[2], 61), 1, metal, { Material = M.Metal, Shadow = true, Collide = false, Query = false })
		B.block(m, CFrame.new(leg(s[1], s[2], 3) + Vector3.new(0, 0.3, 0)), Vector3.new(2, 0.8, 2), rgb(60, 62, 72), B.deco({ Material = M.Metal }))
	end
	for li = 2, #levels do
		for c = 1, 4 do
			local a, b = corners[c], corners[c % 4 + 1]
			B.rod(m, leg(a[1], a[2], levels[li]), leg(b[1], b[2], levels[li]), 0.45, B.shade(metal, 0.1), B.deco({ Material = M.Metal }))
			B.rod(m, leg(a[1], a[2], levels[li - 1]), leg(b[1], b[2], levels[li]), 0.3, B.shade(metal, 0.2), B.deco({ Material = M.Metal }))
		end
	end
	-- катушки (Tower_Coil_1..4): медные барабаны с неоновыми обмотками
	local coilY = { 11, 24, 37, 50 }
	local coilD = { 7.2, 6.4, 5.6, 4.8 }
	local coils = {}
	for k = 1, 4 do
		local y = coilY[k]
		local d = coilD[k]
		B.cylY(m, Vector3.new(0, y, 0), 4.2, d, B.vary(copper, rng, 0.02), B.deco({ Material = M.Metal, Shadow = true }))
		for q = -1, 1 do
			B.cylY(m, Vector3.new(0, y + q * 1.2, 0), 0.32, d + 0.25, ACCENT, B.neon())
		end
		B.cylY(m, Vector3.new(0, y + 2.35, 0), 0.5, d + 1, rgb(54, 56, 66), B.deco({ Material = M.Metal }))
		B.cylY(m, Vector3.new(0, y - 2.35, 0), 0.5, d + 1, rgb(54, 56, 66), B.deco({ Material = M.Metal }))
		-- белые керамические изоляторы над катушкой
		for r = 0, 1 do
			B.cylY(m, Vector3.new(0, y + 3.1 + r * 0.7, 0), 0.4, d * 0.55 - r * 0.4, rgb(232, 226, 214), B.deco({ Material = M.SmoothPlastic }))
		end
		coils[k] = Vector3.new(0, y, 0)
	end
	-- верх: площадка, тороид из шаров, сфера с неоновым поясом, шпиль
	B.cylY(m, Vector3.new(0, 61.5, 0), 1, 7.5, rgb(60, 62, 72), B.deco({ Material = M.Metal }))
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		B.ball(m, Vector3.new(math.cos(a) * 4.3, 63.2, math.sin(a) * 4.3), 2.6, steel, B.deco({ Material = M.Metal }))
	end
	local topY = 67.5
	B.ball(m, Vector3.new(0, topY, 0), 7, steel, B.deco({ Material = M.Metal, Shadow = true }))
	local band = B.cylY(m, Vector3.new(0, topY, 0), 0.5, 7.15, ACCENT, B.neon())
	B.light(band, ACCENT, 50, 2.2)
	B.rod(m, Vector3.new(0, topY + 3, 0), Vector3.new(0, topY + 10, 0), 0.4, steel, B.deco({ Material = M.Metal }))
	B.ball(m, Vector3.new(0, topY + 10.4, 0), 1.2, ACCENT, B.neon())
	-- неоновые пояса решётки
	for _, y in { 17, 45 } do
		local corner = {}
		for c = 1, 4 do
			corner[c] = leg(corners[c][1], corners[c][2], y) + Vector3.new(0, 0.6, 0)
		end
		for c = 1, 4 do
			B.rod(m, corner[c], corner[c % 4 + 1], 0.35, ACCENT, B.neon())
		end
	end
	local baseLight = B.block(m, CFrame.new(0, 5, 0), Vector3.new(1, 1, 1), ACCENT, B.deco({ Transparency = 1, Shadow = false }))
	B.light(baseLight, ACCENT, 26, 1.2)
	return coils, Vector3.new(0, topY, 0)
end

----------------------------------------------------------------------
-- Дома с окнами
----------------------------------------------------------------------
local FACADES = {
	{ rgb(236, 214, 178), rgb(226, 186, 150), rgb(240, 226, 196) }, -- тёплые
	{ rgb(170, 214, 196), rgb(150, 196, 190), rgb(196, 226, 206) }, -- мятные
	{ rgb(196, 180, 226), rgb(176, 164, 214), rgb(214, 200, 236) }, -- лавандовые
	{ rgb(232, 178, 176), rgb(222, 160, 160), rgb(240, 200, 190) }, -- розовые
	{ rgb(164, 192, 228), rgb(146, 176, 220), rgb(186, 208, 236) }, -- голубые
	{ rgb(236, 210, 140), rgb(226, 190, 120), rgb(240, 222, 170) }, -- охра
}
local ROOFS = { rgb(170, 78, 60), rgb(70, 80, 108), rgb(56, 116, 118), rgb(106, 68, 54), rgb(120, 60, 90) }
local WINDOW_OFF = rgb(48, 54, 72)
local WINDOW_ON = { rgb(255, 214, 140), rgb(255, 190, 110), rgb(190, 225, 255), rgb(255, 236, 180), rgb(255, 170, 200) }

local function house(parent, windows, pos, w, d, floors, facade, rng, style)
	local m = B.model(parent, "House")
	local cf = faceCenter(pos) -- −Z (вперёд) смотрит к башне
	local fh = 5.4
	local H = floors * fh
	local trim = B.shade(facade, 0.25)
	B.block(m, cf * CFrame.new(0, 0.4, 0), Vector3.new(w + 0.5, 0.8, d + 0.5), STONE_DARK, { Material = M.Cobblestone })
	B.block(m, cf * CFrame.new(0, 0.8 + H / 2, 0), Vector3.new(w, H, d), facade, { Material = M.SmoothPlastic, Shadow = true })
	-- карнизы между этажами (только фасад)
	for f = 1, floors - 1 do
		B.block(m, cf * CFrame.new(0, 0.8 + f * fh, -d / 2 - 0.15), Vector3.new(w + 0.3, 0.35, 0.5), trim, B.deco({ Shadow = false }))
	end
	-- угловые пилястры
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * (w / 2 - 0.15), 0.8 + H / 2, -d / 2 - 0.12), Vector3.new(0.7, H, 0.4), trim, B.deco({ Shadow = false }))
	end
	-- дверь, ступенька, фонарик над дверью
	local doorX = if w > 11 then rng:range(-1.5, 1.5) else 0
	B.block(m, cf * CFrame.new(doorX, 0.8 + 1.9, -d / 2 - 0.08), Vector3.new(2.2, 3.8, 0.3), B.vary(rgb(110, 72, 50), rng, 0.05), B.deco({ Material = M.Wood }))
	B.block(m, cf * CFrame.new(doorX, 0.25, -d / 2 - 0.9), Vector3.new(3, 0.5, 1.4), STONE_DARK, { Material = M.Slate })
	B.block(m, cf * CFrame.new(doorX, 0.8 + 4.4, -d / 2 - 0.3), Vector3.new(0.6, 0.6, 0.6), LAMP, B.neon())
	if style.awning then
		B.wedge(m, cf * CFrame.new(doorX, 0.8 + 4.9, -d / 2 - 1.1) * CFrame.Angles(0, math.pi, 0), Vector3.new(3.6, 0.9, 2), style.awning, B.deco({ Material = M.Fabric }))
	end
	-- окна: тёмные; клиент зажигает их (атрибут OnColor)
	local function window(x, y, z, face)
		local wcf
		if face == "front" then
			wcf = cf * CFrame.new(x, y, -d / 2 - 0.06)
		elseif face == "back" then
			wcf = cf * CFrame.new(x, y, d / 2 + 0.06) * CFrame.Angles(0, math.pi, 0)
		else
			wcf = cf * CFrame.new(face * (w / 2 + 0.06), y, z) * CFrame.Angles(0, math.pi / 2, 0)
		end
		local p = B.block(windows, wcf, Vector3.new(1.7, 2.3, 0.2), WINDOW_OFF, B.deco({ Material = M.SmoothPlastic, Shadow = false, Name = "Window" }))
		p:SetAttribute("OnColor", rng:pick(WINDOW_ON))
		return p
	end
	local perFloor = math.max(2, math.floor((w - 1.5) / 3.3))
	for f = 0, floors - 1 do
		local y = 0.8 + f * fh + 2.9
		if f == 0 then
			for side = -1, 1, 2 do
				local x = doorX + side * (w / 4 + 0.6)
				if math.abs(x) < w / 2 - 1.2 then
					window(x, y, 0, "front")
				end
			end
		else
			for k = 1, perFloor do
				local x = -w / 2 + w * (k - 0.5) / perFloor
				window(x, y, 0, "front")
			end
		end
	end
	if style.sideWindows then
		window(0, 0.8 + (floors - 1) * fh + 2.9, -d / 4, style.sideWindows)
	end
	-- окна на задней стене (её видно с мостов и островов) — тоже зажигаются кварталом
	for f = 1, floors - 1 do
		local y = 0.8 + f * fh + 2.9
		for k = 1, 2 do
			if rng:chance(0.8) then
				window(-w / 2 + w * (k - 0.5) / 2 + rng:range(-0.4, 0.4), y, 0, "back")
			end
		end
	end
	-- крыша
	local top = 0.8 + H
	if style.roof == "gable" then
		local rh = rng:range(2.6, 3.6)
		local col = style.roofColor
		B.wedge(m, cf * CFrame.new(0, top + rh / 2, -d / 4 - 0.25), Vector3.new(w + 0.9, rh, d / 2 + 0.5), col, B.deco({ Material = M.Slate, Shadow = true }))
		B.wedge(m, cf * CFrame.new(0, top + rh / 2, d / 4 + 0.25) * CFrame.Angles(0, math.pi, 0), Vector3.new(w + 0.9, rh, d / 2 + 0.5), B.shade(col, 0.15), B.deco({ Material = M.Slate, Shadow = true }))
		if rng:chance(0.6) then
			local cx = rng:range(-w / 3, w / 3)
			B.block(m, cf * CFrame.new(cx, top + rh * 0.7, d / 6), Vector3.new(1.2, rh + 1, 1.2), rgb(120, 90, 80), B.deco({ Material = M.Brick }))
		end
	else
		-- плоская крыша с парапетом и «начинкой»
		B.block(m, cf * CFrame.new(0, top + 0.3, 0), Vector3.new(w + 0.4, 0.6, d + 0.4), trim, B.deco({ Shadow = false }))
		if rng:chance(0.5) then
			local tp = (cf * CFrame.new(rng:range(-w / 4, w / 4), top + 2.2, rng:range(0, d / 4))).Position
			B.cylY(m, tp, 2.6, 2.4, rgb(120, 92, 70), B.deco({ Material = M.WoodPlanks }))
			B.cylY(m, tp + Vector3.new(0, 1.5, 0), 0.4, 2.7, rgb(70, 60, 56), B.deco({ Material = M.Metal }))
		else
			local ap = (cf * CFrame.new(rng:range(-w / 3, w / 3), top, rng:range(-d / 4, d / 4))).Position
			B.rod(m, ap, ap + Vector3.new(0, 5, 0), 0.2, rgb(150, 150, 160), B.deco({ Material = M.Metal }))
			B.ball(m, ap + Vector3.new(0, 5.2, 0), 0.5, rgb(255, 70, 70), B.neon())
			B.block(m, cf * CFrame.new(rng:range(-w / 4, w / 4), top + 1, rng:range(-d / 4, d / 4)), Vector3.new(2, 1.4, 1.6), rgb(150, 156, 166), B.deco({ Material = M.Metal }))
		end
	end
	return m
end

-- Квартал: ряд домов по дуге от a0 до a1 (градусы), фасады к башне
local function district(parent, windowsFolder, k, a0, a1, rOuter, depthMin, depthMax, rng)
	local m = B.model(parent, "Houses_" .. k)
	local pal = FACADES[k]
	local a = a0
	local idx = 0
	while true do
		local w = rng:range(9, 12.5)
		local d = rng:range(depthMin, depthMax)
		local rc = rOuter - d / 2
		local span = math.deg((w + rng:range(1.4, 2.6)) / rc)
		if a + span > a1 + 0.5 then
			break
		end
		idx += 1
		local mid = a + span / 2
		local pos = hubPoint(mid, rc)
		local floors = if rng:chance(0.45) then 3 else 2
		if idx % 3 == 2 then
			floors = 3
		end
		house(m, windowsFolder, pos, w, d, floors, B.vary(rng:pick(pal), rng, 0.03), rng, {
			roof = if rng:chance(0.6) then "gable" else "flat",
			roofColor = B.vary(rng:pick(ROOFS), rng, 0.03),
			awning = if rng:chance(0.4) then rng:pick({ rgb(220, 70, 70), rgb(60, 120, 220), rgb(240, 190, 60), rgb(70, 170, 110) }) else nil,
			sideWindows = nil,
		})
		a += span
	end
	return m
end

----------------------------------------------------------------------
-- Таблички, табло
----------------------------------------------------------------------
local function signBoard(parent, cf, w, h, lines, color, opts, frameColor)
	local board = B.block(parent, cf, Vector3.new(w, h, 0.5), color or rgb(34, 36, 52), B.deco({ Material = M.SmoothPlastic, Shadow = false, Name = "Sign" }))
	B.text(board, lines, opts or { Face = Enum.NormalId.Front, PixelsPerStud = 30 })
	-- неоновая рамка (деталь чуть больше таблички, позади неё)
	if frameColor then
		B.block(parent, cf * CFrame.new(0, 0, 0.12), Vector3.new(w + 0.5, h + 0.5, 0.3), frameColor, B.neon())
	end
	return board
end

-- Табло: стойки, рама, экран; метка Board_<name> с SurfaceGui "Gui" → Frame "Content" (заполняет сервер)
local function infoBoard(parent, markers, name, title, pos, accent, rng)
	local m = B.model(parent, "Board_" .. name .. "_Frame")
	local cf = faceCenter(pos)
	local metal = rgb(52, 56, 70)
	local W, H, lift = 15, 8.6, 3
	for side = -1, 1, 2 do
		B.block(m, cf * CFrame.new(side * (W / 2 + 0.5), (lift + H + 1) / 2, 0.4), Vector3.new(0.9, lift + H + 1, 0.9), metal, { Material = M.Metal, Shadow = true })
	end
	B.block(m, cf * CFrame.new(0, lift + H / 2, 0.4), Vector3.new(W + 1.2, H + 1.2, 0.8), metal, { Material = M.Metal, Shadow = true })
	B.block(m, cf * CFrame.new(0, lift + H / 2, 0), Vector3.new(W, H, 0.1), rgb(18, 22, 38), B.deco({ Shadow = false, Name = "Screen" }))
	B.block(m, cf * CFrame.new(0, lift + H + 0.75, 0.1), Vector3.new(W + 1.2, 0.3, 0.3), accent, B.neon())
	B.block(m, cf * CFrame.new(0, lift - 0.75, 0.1), Vector3.new(W + 1.2, 0.3, 0.3), accent, B.neon())
	B.block(m, cf * CFrame.new(0, lift + H + 1.4, 0.4), Vector3.new(W * 0.6, 0.9, 0.6), metal, B.deco({ Material = M.Metal }))
	-- метка с интерфейсом (невидимая деталь прямо перед экраном)
	local marker = B.marker(markers, "Board_" .. name, cf * CFrame.new(0, lift + H / 2, -0.12), Vector3.new(W, H, 0.1))
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
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.17)
	t.Position = UDim2.fromScale(0, 0.01)
	t.FontFace = B.FontHeavy
	t.Text = title
	t.TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.35)
	t.TextScaled = true
	t.Parent = gui
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(0.94, 0.78)
	content.Position = UDim2.fromScale(0.03, 0.2)
	content.Parent = gui
	return marker
end

----------------------------------------------------------------------
-- Киоски
----------------------------------------------------------------------
local function apron(parent, pos, r, color)
	B.cylY(parent, pos + Vector3.new(0, 0.02, 0), 0.12, r * 2, color, B.deco({ Material = M.Brick, Shadow = false, Name = "Apron" }))
end

-- Магазин: прилавок, полки с банками и громоотводами, полосатый навес, вывеска
local function shopKiosk(parent, pos, rng, Models)
	local m = B.model(parent, "Kiosk_Shop")
	local cf = faceCenter(pos)
	local wood = rgb(160, 110, 70)
	local yellow, blue = rgb(255, 200, 70), rgb(60, 110, 220)
	-- прилавок
	B.block(m, cf * CFrame.new(0, 1.6, 0), Vector3.new(10, 3.2, 2.4), wood, { Material = M.WoodPlanks, Shadow = true })
	B.block(m, cf * CFrame.new(0, 3.3, -0.1), Vector3.new(10.6, 0.3, 2.9), rgb(196, 150, 100), B.deco({ Material = M.Wood }))
	B.block(m, cf * CFrame.new(0, 2.2, -1.25), Vector3.new(9.4, 0.25, 0.1), yellow, B.neon())
	-- задняя стенка с полками
	B.block(m, cf * CFrame.new(0, 4.2, 4.2), Vector3.new(11, 8.4, 0.8), B.shade(wood, 0.2), { Material = M.WoodPlanks, Shadow = true })
	for _, y in { 3.6, 6 } do
		B.block(m, cf * CFrame.new(0, y, 3.4), Vector3.new(10, 0.25, 1.2), rgb(196, 150, 100), B.deco({ Material = M.Wood }))
	end
	-- товары: банки (стекло + неоновое ядро) и громоотводы
	local jarColors = { rgb(110, 200, 255), rgb(190, 120, 255), rgb(80, 255, 150), rgb(255, 210, 60) }
	for k = 1, 4 do
		local p = (cf * CFrame.new(-3.6 + (k - 1) * 2.4, 4.45, 3.3)).Position
		B.cylY(m, p, 1.5, 1.1, rgb(200, 230, 255), B.deco({ Material = M.Glass, Transparency = 0.5 }))
		B.cylY(m, p, 1.2, 0.75, jarColors[k], B.neon())
		B.cylY(m, p + Vector3.new(0, 0.85, 0), 0.25, 1.2, rgb(120, 126, 140), B.deco({ Material = M.Metal }))
	end
	for k = 1, 3 do
		local base = (cf * CFrame.new(-2.5 + (k - 1) * 2.5, 6.15, 3.4)).Position
		B.rod(m, base, base + Vector3.new(0, 1.9, 0), 0.22, ({ rgb(196, 112, 66), rgb(200, 206, 216), rgb(240, 196, 70) })[k], B.deco({ Material = M.Metal }))
		B.ball(m, base + Vector3.new(0, 2.05, 0), 0.4, ACCENT, B.neon())
	end
	-- стойки и полосатый навес (клинья)
	for _, sx in { -5.4, 5.4 } do
		for _, sz in { -1.4, 4.2 } do
			B.cylY(m, (cf * CFrame.new(sx, 4.4, sz)).Position, 8.8, 0.45, rgb(80, 60, 50), { Material = M.Wood })
		end
	end
	local stripes = 6
	for k = 0, stripes - 1 do
		local x = -6 + (k + 0.5) * 12 / stripes
		B.wedge(m, cf * CFrame.new(x, 9.2, 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(12 / stripes, 1.6, 7.6), if k % 2 == 0 then yellow else blue, B.deco({ Material = M.Fabric, Shadow = true }))
		B.block(m, cf * CFrame.new(x, 8.15, -3.2), Vector3.new(12 / stripes, 0.5, 0.15), if k % 2 == 0 then blue else yellow, B.deco({ Material = M.Fabric }))
	end
	-- вывеска над навесом
	local sign = signBoard(m, cf * CFrame.new(0, 11.4, 4.1), 11, 2.8, { { Text = "⚡ МАГАЗИН", Color = rgb(255, 230, 120) } })
	B.block(m, cf * CFrame.new(0, 11.4, 4.45), Vector3.new(11.6, 3.4, 0.2), yellow, B.neon())
	local glow = B.block(m, cf * CFrame.new(0, 7.6, 1.5), Vector3.new(1, 1, 1), LAMP, B.deco({ Transparency = 1 }))
	B.light(glow, LAMP, 18, 1)
	-- ящики и бочка рядом
	P.crate(m, (cf * CFrame.new(-7, 0, 1)).Position, rng)
	P.crate(m, (cf * CFrame.new(-7.4, 0, 3.2)).Position, rng)
	P.barrel(m, (cf * CFrame.new(7, 0, 2)).Position, rng)
	local _ = sign
	return m
end

-- Инкубаторий: круглая площадка, 3 стойки с коконами, стеклянная арка-оранжерея, вывеска
local function hatcheryKiosk(parent, markers, pos, rng, ctx)
	local Pets, Models = ctx.Pets, ctx.Models
	local m = B.model(parent, "Kiosk_Hatchery")
	local cf = faceCenter(pos)
	B.cylY(m, pos + Vector3.new(0, 0.3, 0), 0.6, 17, rgb(200, 196, 188), { Material = M.Marble })
	B.cylY(m, pos + Vector3.new(0, 0.24, 0), 0.5, 17.5, rgb(90, 200, 110), B.neon())
	-- оранжерея: дуга из стоек и стекло позади стоек
	local metal = rgb(230, 232, 240)
	local arcPts = {}
	for k = 0, 6 do
		local a = math.pi * k / 6
		table.insert(arcPts, cf * Vector3.new(math.cos(a) * 8, 0.6 + math.sin(a) * 9, 4.5))
	end
	for k = 1, #arcPts - 1 do
		B.rod(m, arcPts[k], arcPts[k + 1], 0.5, metal, B.deco({ Material = M.Metal }))
	end
	for _, x in { -8, 8 } do
		B.rod(m, cf * Vector3.new(x, 0.6, 4.5), cf * Vector3.new(x, 0.6, 1), 0.5, metal, B.deco({ Material = M.Metal }))
	end
	B.block(m, cf * CFrame.new(0, 4.8, 4.6), Vector3.new(15.5, 8.4, 0.2), rgb(190, 240, 210), B.deco({ Material = M.Glass, Transparency = 0.55 }))
	local sign = signBoard(m, cf * CFrame.new(0, 11.2, 4.4), 12, 2.6, { { Text = "🥚 КОКОНЫ", Color = rgb(190, 255, 200) } }, nil, nil, rgb(90, 200, 110))
	local _ = sign
	-- стойки
	for k, id in Pets.CocoonOrder do
		local def = Pets.Cocoons[id]
		local x = (k - 2) * 5
		local z = if k == 2 then 0.8 else 0
		local base = cf * CFrame.new(x, 0, z)
		B.cylY(m, (base * CFrame.new(0, 1.8, 0)).Position, 2.4, 2.8, rgb(230, 226, 220), { Material = M.Marble, Shadow = true })
		B.cylY(m, (base * CFrame.new(0, 3.1, 0)).Position, 0.3, 3.4, rgb(70, 70, 84), B.deco({ Material = M.Metal }))
		local ringP = B.cylY(m, (base * CFrame.new(0, 3.15, 0)).Position, 0.3, 3.0, def.Color, B.neon())
		B.light(ringP, def.Color, 10, 0.8)
		local top = base * CFrame.new(0, 3.3, 0)
		-- витринный кокон (статичный, якорный)
		ctx.place(Models.cocoon(id), top, m)
		B.marker(markers, "Cocoon_" .. id, top)
		-- табличка с названием и ценой
		local plaque = B.block(m, base * CFrame.new(0, 1.6, -1.55) * CFrame.Angles(-0.25, 0, 0), Vector3.new(2.6, 1.4, 0.2), rgb(36, 38, 54), B.deco({ Name = "Plaque" }))
		B.text(plaque, {
			{ Text = string.gsub(def.Name, " кокон", ""), Color = def.Color:Lerp(Color3.new(1, 1, 1), 0.4), Size = 1 },
			{ Text = tostring(def.Cost) .. " 💎", Color = rgb(200, 235, 255), Size = 0.9 },
		}, { Face = Enum.NormalId.Front, PixelsPerStud = 50 })
	end
	return m
end

-- Галерея: 12 пьедесталов дугой вокруг стойки с вывеской
local function galleryKiosk(parent, markers, pos, rng)
	local m = B.model(parent, "Kiosk_Gallery")
	local cf = faceCenter(pos)
	B.cylY(m, pos + Vector3.new(0, 0.03, 0), 0.14, 34, rgb(206, 200, 192), B.deco({ Material = M.Marble, Shadow = false, Name = "Floor" }))
	B.cylY(m, pos + Vector3.new(0, 0.05, 0), 0.14, 30, rgb(150, 140, 170), B.deco({ Material = M.Marble, Shadow = false, Name = "FloorInlay" }))
	B.cylY(m, pos + Vector3.new(0, 0.07, 0), 0.14, 27, rgb(214, 208, 200), B.deco({ Material = M.Marble, Shadow = false, Name = "FloorCenter" }))
	-- стойка-пюпитр с вывеской
	B.block(m, cf * CFrame.new(0, 1.2, 0), Vector3.new(2.6, 2.4, 1.6), rgb(70, 64, 90), { Material = M.Marble })
	local lect = B.block(m, cf * CFrame.new(0, 2.7, -0.2) * CFrame.Angles(-0.5, 0, 0), Vector3.new(3.2, 0.25, 2.2), rgb(40, 36, 56), B.deco({ Name = "Lectern" }))
	B.text(lect, { { Text = "ГАЛЕРЕЯ", Color = rgb(255, 225, 140), Size = 1 }, { Text = "фульгуритов", Color = rgb(220, 210, 255), Size = 0.7 } }, { Face = Enum.NormalId.Top, PixelsPerStud = 60 })
	local back = -B.flat(cf.LookVector) -- от башни
	local right = Vector3.new(-back.Z, 0, back.X)
	for j = 1, 12 do
		local phi = math.rad(-105 + (j - 1) * 210 / 11)
		local dir = back * math.cos(phi) + right * math.sin(phi)
		local p = pos + dir * 13
		local pcf = B.facing(p, -dir)
		local marble = B.vary(rgb(232, 228, 222), rng, 0.02)
		B.block(m, pcf * CFrame.new(0, 0.3, 0), Vector3.new(3, 0.6, 3), rgb(96, 90, 110), { Material = M.Marble })
		B.block(m, pcf * CFrame.new(0, 1.9, 0), Vector3.new(2.1, 2.6, 2.1), marble, { Material = M.Marble, Shadow = true })
		B.block(m, pcf * CFrame.new(0, 3.4, 0), Vector3.new(2.8, 0.4, 2.8), rgb(70, 64, 90), B.deco({ Material = M.Marble }))
		B.block(m, pcf * CFrame.new(0, 2.6, -1.08), Vector3.new(1.5, 0.2, 0.1), rgb(255, 210, 120), B.neon())
		-- метка: центр верхней грани пьедестала, лицом к центру галереи
		B.marker(markers, "Pedestal_" .. j, pcf * CFrame.new(0, 3.6, 0))
	end
	return m
end

-- Генератор перезапуска: ступенчатая площадка, барабан с неоном, кольца, 4 пилона, вывеска
local function rebirthKiosk(parent, pos, rng)
	local m = B.model(parent, "Kiosk_Rebirth")
	local cf = faceCenter(pos)
	local glow = rgb(255, 90, 160)
	local dark = rgb(50, 46, 62)
	B.cylY(m, pos + Vector3.new(0, 0.35, 0), 0.7, 16, rgb(70, 66, 84), { Material = M.Slate })
	B.cylY(m, pos + Vector3.new(0, 1.0, 0), 0.6, 12, rgb(90, 86, 104), { Material = M.Slate })
	B.cylY(m, pos + Vector3.new(0, 0.95, 0), 0.6, 12.4, glow, B.neon())
	-- барабан генератора
	B.cylY(m, pos + Vector3.new(0, 4.3, 0), 6, 6, dark, { Material = M.Metal, Shadow = true })
	for _, y in { 2.4, 4.3, 6.2 } do
		B.cylY(m, pos + Vector3.new(0, y, 0), 0.4, 6.2, glow, B.neon())
	end
	B.cylY(m, pos + Vector3.new(0, 7.6, 0), 0.6, 7, rgb(80, 76, 96), B.deco({ Material = M.Metal }))
	local core = B.ball(m, pos + Vector3.new(0, 9.3, 0), 3.6, glow, B.neon())
	B.light(core, glow, 24, 1.6)
	-- кольца вокруг
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		local p = pos + Vector3.new(math.cos(a) * 4.8, 9.3 + math.sin(a * 2) * 0.4, math.sin(a) * 4.8)
		B.block(m, B.facing(p, Vector3.new(-math.sin(a), 0, math.cos(a))), Vector3.new(0.4, 0.4, 2.6), rgb(200, 180, 220), B.deco({ Material = M.Metal }))
	end
	-- пилоны
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = pos + Vector3.new(math.cos(a) * 6.3, 1.3, math.sin(a) * 6.3)
		B.block(m, CFrame.new(p + Vector3.new(0, 3, 0)) * CFrame.Angles(0, -a, 0), Vector3.new(1.2, 6, 1.2), dark, { Material = M.Metal, Shadow = true })
		B.ball(m, p + Vector3.new(0, 6.6, 0), 1.1, glow, B.neon())
	end
	signBoard(m, cf * CFrame.new(0, 13.4, 0), 12, 3.2, { { Text = "ПЕРЕЗАПУСК", Color = rgb(255, 180, 220), Size = 1 }, { Text = "генератора", Color = rgb(230, 220, 255), Size = 0.6 } }, nil, nil, glow)
	B.rod(m, pos + Vector3.new(-4, 11, 0), pos + Vector3.new(-4, 15, 0) + cf.LookVector * 0, 0.3, dark, B.deco({ Material = M.Metal }))
	return m
end

-- Ежедневные награды: большой сундук с золотом, монеты, календарь-вывеска
local function dailyKiosk(parent, pos, rng)
	local m = B.model(parent, "Kiosk_Daily")
	local cf = faceCenter(pos)
	local wood = rgb(140, 86, 52)
	local gold = rgb(255, 200, 70)
	B.cylY(m, pos + Vector3.new(0, 0.3, 0), 0.6, 14, rgb(170, 150, 120), { Material = M.Brick })
	local c = cf * CFrame.new(0, 0.6, 0)
	B.block(m, c * CFrame.new(0, 1.7, 0), Vector3.new(6.4, 3.4, 4), wood, { Material = M.WoodPlanks, Shadow = true })
	-- крышка-полуцилиндр
	B.cyl(m, c * CFrame.new(0, 3.4, 0), 6.4, 4, B.shade(wood, 0.05), B.deco({ Material = M.WoodPlanks, Shadow = true }))
	-- золотые оковки
	for _, x in { -2.6, 2.6 } do
		B.block(m, c * CFrame.new(x, 1.7, 0), Vector3.new(0.6, 3.5, 4.1), gold, B.deco({ Material = M.Metal }))
		B.cyl(m, c * CFrame.new(x, 3.4, 0), 0.6, 4.12, gold, B.deco({ Material = M.Metal }))
	end
	B.block(m, c * CFrame.new(0, 3.35, -2.0), Vector3.new(6.42, 0.18, 0.1), gold, B.neon())
	B.block(m, c * CFrame.new(0, 2.9, -2.1), Vector3.new(1.1, 1.3, 0.3), gold, B.deco({ Material = M.Metal }))
	B.block(m, c * CFrame.new(0, 2.8, -2.27), Vector3.new(0.25, 0.5, 0.05), rgb(40, 30, 20), B.deco())
	local shine = B.block(m, c * CFrame.new(0, 4, -1), Vector3.new(1, 1, 1), gold, B.deco({ Transparency = 1 }))
	B.light(shine, gold, 16, 1.2)
	-- монеты
	for k = 1, 9 do
		local p = (cf * CFrame.new(rng:range(-5, 5), 0.68 + (k % 3) * 0.2, rng:range(-3.5, -1.5))).Position
		local coin = B.cylY(m, p, 0.2, 1, gold, B.deco({ Material = M.Metal }))
		coin.CFrame = coin.CFrame * CFrame.Angles(rng:range(-0.2, 0.2), 0, rng:range(-0.3, 0.3))
	end
	-- вывеска-календарь на стойках
	for _, x in { -5.5, 5.5 } do
		B.block(m, cf * CFrame.new(x, 5, 3.5), Vector3.new(0.6, 10, 0.6), rgb(90, 60, 44), { Material = M.Wood })
	end
	signBoard(m, cf * CFrame.new(0, 9, 3.5), 11.5, 3, { { Text = "🎁 НАГРАДЫ", Color = rgb(255, 225, 120), Size = 1 }, { Text = "каждый день", Color = rgb(230, 230, 255), Size = 0.6 } }, nil, nil, gold)
	for d = 0, 6 do
		local cell = B.block(m, cf * CFrame.new(-4.5 + d * 1.5, 6.6, 3.45), Vector3.new(1.2, 1.2, 0.3), if d == 6 then gold else rgb(70, 80, 120), if d == 6 then B.neon() else B.deco())
		local _ = cell
	end
	return m
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
		segments = 38,
		base = 1.8,
		amp = 4,
		top = rgb(146, 140, 134),
		topMaterial = M.Cobblestone,
		dirt = rgb(132, 104, 80),
		rock = rgb(124, 120, 134),
		rock2 = rgb(142, 128, 124),
		depth = 76,
		openings = openings,
		openHalfDeg = 7,
		drips = 0,
		stalactites = 6,
		walls = { radius = R + 0.8, height = 18, segments = 40 },
		wallParent = ctx.Walls,
		hang = function(m, p, out, r)
			-- кабели и фонарики под краем площади
			local q = p + out * 1.5 - Vector3.new(0, r:range(3, 6), 0)
			B.rod(m, p, q, 0.25, rgb(40, 40, 48), B.deco({ Material = M.Metal }))
			B.ball(m, q, 0.7, LAMP, B.neon())
		end,
		hangCount = 12,
	})

	-- площадь: внутренний круг, светлый центр, кольцо подстанции (радиус Zones.HubSellRadius)
	local O = Zones.HubCenter
	B.cylY(decor, O + Vector3.new(0, 0, 0), 0.12, 68, rgb(112, 106, 116), B.deco({ Material = M.Slate, Shadow = false, Name = "PlazaRing" }))
	B.cylY(decor, O + Vector3.new(0, 0.06, 0), 0.12, 42, rgb(196, 190, 182), B.deco({ Material = M.Marble, Shadow = false, Name = "PlazaCenter" }))
	B.ring(decor, O + Vector3.new(0, -0.02, 0), Zones.HubSellRadius, 1.4, 0.26, 32, ACCENT, B.neon({ Name = "SellRing" }))
	B.ring(decor, O + Vector3.new(0, -0.02, 0), Zones.HubSellRadius + 1.3, 0.5, 0.22, 28, rgb(60, 62, 76), B.deco({ Material = M.Metal, Name = "SellRingRim" }))
	B.ring(decor, O + Vector3.new(0, -0.02, 0), Zones.HubSellRadius - 1.3, 0.5, 0.22, 24, rgb(60, 62, 76), B.deco({ Material = M.Metal, Name = "SellRingRim" }))
	-- лучи-инкрустации от кольца к краю круга
	for k = 0, 9 do
		local a = k * 36 + 18
		local p0 = hubPoint(a, 21.5, 0.035)
		local p1 = hubPoint(a, 33.5, 0.035)
		B.bar(decor, p0, p1, 0.8, 0.1, rgb(84, 80, 96), B.deco({ Material = M.Slate, Shadow = false }))
	end

	local coils, top = teslaTower(hub, ctx, rng)
	for k, p in coils do
		B.marker(ctx.Markers, "Tower_Coil_" .. k, CFrame.new(p))
	end
	B.marker(ctx.Markers, "Tower_Top", CFrame.new(top))

	-- дороги к мостам (чуть выше площади, без коллизий) с бордюрами
	for _, g in Zones.Geo do
		local a = g.Dir
		local right = Vector3.new(-a.Z, 0, a.X)
		local p0 = a * 34
		local p1 = a * (R + 1.4)
		B.bar(decor, p0 + Vector3.new(0, 0.05, 0), p1 + Vector3.new(0, 0.05, 0), Config.BridgeWidth, 0.1, rgb(176, 160, 136), B.deco({ Material = M.Pavement, Shadow = false, Name = "Road" }))
		for side = -1, 1, 2 do
			B.bar(decor, p0 + right * side * (Config.BridgeWidth / 2 + 0.4) + Vector3.new(0, 0.1, 0), p1 + right * side * (Config.BridgeWidth / 2 + 0.4) + Vector3.new(0, 0.1, 0), 0.8, 0.2, rgb(104, 100, 108), B.deco({ Material = M.Concrete, Shadow = false, Name = "Curb" }))
		end
		-- фонари вдоль дороги
		for _, d in { 46, 84 } do
			for side = -1, 1, 2 do
				P.lamp(decor, a * d + right * side * (Config.BridgeWidth / 2 + 2.2), rng, LAMP, 9)
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
	for k, s in ipairs(sectors) do
		local windows = B.folder(city, "District_" .. k)
		district(houses, windows, k, s[1], s[2], s[3], s[4], s[5], rng)
	end

	-- киоски (метки Kiosk_* — в точках Zones.Hub.*)
	local kiosks = B.model(hub, "Kiosks")
	local H = Zones.Hub
	for _, k in { { "Shop", H.Shop }, { "Hatchery", H.Hatchery }, { "Rebirth", H.Rebirth }, { "Daily", H.Daily } } do
		apron(decor, k[2], 11, rgb(150, 136, 120))
	end
	shopKiosk(kiosks, H.Shop, rng, ctx.Models)
	hatcheryKiosk(kiosks, ctx.Markers, H.Hatchery, rng, ctx)
	galleryKiosk(kiosks, ctx.Markers, H.Gallery, rng)
	rebirthKiosk(kiosks, H.Rebirth, rng)
	dailyKiosk(kiosks, H.Daily, rng)
	for _, k in { "Shop", "Hatchery", "Gallery", "Rebirth", "Daily" } do
		B.marker(ctx.Markers, "Kiosk_" .. k, faceCenter(H[k] + Vector3.new(0, 3, 0)))
	end

	-- табло
	local boards = B.model(hub, "Boards")
	infoBoard(boards, ctx.Markers, "Leaders", "🏆 ЛУЧШИЕ ЛОВЦЫ", H.BoardLeaders, rgb(255, 200, 70), rng)
	infoBoard(boards, ctx.Markers, "Forecast", "⛈ ПРОГНОЗ БУРИ", H.BoardForecast, ACCENT, rng)
	infoBoard(boards, ctx.Markers, "Hall", "🌈 ЗАЛ СЛАВЫ", hubPoint(180, 88), rgb(255, 140, 220), rng)

	-- скамейки и клумбы вокруг внутреннего круга (между дорогами)
	local pal = { leaves = { rgb(66, 146, 62), rgb(88, 166, 68), rgb(116, 184, 78) }, flowers = { rgb(255, 120, 160), rgb(255, 214, 90), rgb(250, 248, 255), rgb(196, 146, 255) }, stone = rgb(170, 160, 150) }
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
		-- деревца в кадках у киосков
		for _, off in { -12, 12 } do
			local a = base + off
			local p = hubPoint(a, 70)
			B.cylY(decor, p + Vector3.new(0, 0.9, 0), 1.8, 3, rgb(150, 120, 100), { Material = M.Concrete })
			P.tree(decor, p + Vector3.new(0, 1.6, 0), rng, { leaves = pal.leaves }, 0.6)
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

	return hub
end

return Hub
