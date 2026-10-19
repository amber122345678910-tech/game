--!nocheck
-- Декорация «Спортзал с фиолетовым неоном» (план S10).
--
-- Локальные координаты декорации: пол Y=0, +Y вверх. Конь сидит на скамье в (0,0,0) лицом в −Z,
-- камера обычно в −Z (z≈−6…−12) и смотрит в +Z. ВНИМАНИЕ: при взгляде камеры в +Z мир +X — СЛЕВА в кадре.
--
-- Контракт (AGENTS.md → Gym):
--   * зал x∈[−20,20], z∈[−26,16], пол Y=0 (тёмная резина), потолок Y=12 (тёмное дерево, рейки),
--     диагональные неоновые трубки фиолет/маджента/оранж под потолком + трековые споты;
--   * скамья под конём: центр (0,0,0.4), длинная ось по Z, длина 3.6, ширина 1.1, верх сиденья Y=1.55
--     (модель "HorseBench", деталь "SeatTop" — верхняя плоскость сиденья);
--   * стойки с гантелями у задней стены (z≈10.5…13.6), зеркала на стене;
--   * места статистов x≈−6…−3 и x≈+3…+7, z≈+3…+8 — свободны (на полу ничего нет).
--   Дополнительно: в задней стене проём x∈[−7,7] в глубокую нишу до z=36 (силовая рама, кроссовер,
--   стойка блинов) — даёт перспективу «коридора», как в клипе. Ниша не мешает постановке.

local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local V = Vector3.new
local rad = math.rad

local function hex(s: string)
	return Color3.fromRGB(tonumber(string.sub(s, 1, 2), 16), tonumber(string.sub(s, 3, 4), 16), tonumber(string.sub(s, 5, 6), 16))
end

-- Палитра (подобрана по кадрам S10; стены белые — сиреневыми их делает свет).
local C = {
	wall = hex("ebe6ef"),
	wallShade = hex("ddd6e4"),
	skirting = hex("1a181e"),
	floor = hex("16151a"),
	floorSeam = hex("0b0b0e"),
	ceilingBack = hex("0c0a0c"),
	woods = { hex("5a3c2c"), hex("634331"), hex("53372a"), hex("6a4834"), hex("5e4030"), hex("4f3528") },
	steel = hex("1e1e23"),
	steelDark = hex("141418"),
	chrome = hex("c4c8d0"),
	rubber = hex("131419"),
	rubberCap = hex("26272e"),
	leather = hex("17151a"),
	neonPurple = hex("a057ff"),
	neonViolet = hex("8c5cff"),
	neonMagenta = hex("e255ff"),
	neonOrange = hex("ff6a24"),
	neonYellow = hex("ffc94d"),
	lamp = hex("fff0d8"),
	mirror = hex("a59fb4"),
	frame = hex("101014"),
}

local LIGHT_WARM = Color3.fromRGB(255, 222, 186)
local LIGHT_AMBER = Color3.fromRGB(255, 186, 120)
local LIGHT_PURPLE = Color3.fromRGB(176, 92, 255)
local LIGHT_MAGENTA = Color3.fromRGB(232, 96, 255)
local LIGHT_ORANGE = Color3.fromRGB(255, 120, 50)

-- Детерминированный псевдослучай (сборка всегда одинакова).
local seed = 20261019
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local ROOM_W = 20 -- полуширина зала
local Z_FRONT, Z_BACK = -26, 16
local CEIL = 12
local ANNEX_W = 7 -- полуширина проёма/ниши
local ANNEX_Z = 36 -- дальняя стена ниши

return function(B)
	local cur = B.model
	local function group(name)
		cur = B:folder(name)
		return cur
	end

	---------------------------------------------------------------- помощники
	local function P(spec)
		spec.parent = spec.parent or cur
		return B:part(spec)
	end
	local function box(pos, size, color, material, rot, extra)
		local spec = { pos = pos, size = size, color = color, material = material, rot = rot }
		for k, v in extra or {} do
			spec[k] = v
		end
		return P(spec)
	end
	local function boxCF(cf, size, color, material, extra)
		local spec = { cf = cf, size = size, color = color, material = material }
		for k, v in extra or {} do
			spec[k] = v
		end
		return P(spec)
	end
	-- Цилиндр, ось которого — локальная X данного CFrame.
	local function cylX(cf, len, d, color, material, extra)
		local spec = { cf = cf, size = V(len, d, d), color = color, material = material, shape = "Cylinder" }
		for k, v in extra or {} do
			spec[k] = v
		end
		return P(spec)
	end
	local function ball(pos, d, color, material, extra)
		local spec = { pos = pos, size = V(d, d, d), color = color, material = material, shape = "Ball" }
		for k, v in extra or {} do
			spec[k] = v
		end
		return P(spec)
	end
	-- CFrame «из a смотрит на b» (CFrame.lookAt в Lune неверен — собираем через fromMatrix).
	local function look(a, b)
		local f = (b - a).Unit
		local r = f:Cross(V(0, 1, 0))
		if r.Magnitude < 0.05 then
			r = f:Cross(V(0, 0, 1))
		end
		r = r.Unit
		local u = r:Cross(f)
		return CFrame.fromMatrix(a, r, u, -f)
	end
	-- Цилиндр от точки a до точки b.
	local function rod(a, b, d, color, material, extra)
		local len = (b - a).Magnitude
		local cf = look((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
		return cylX(cf, len, d, color, material, extra)
	end
	-- Брусок от a до b (сечение w по горизонтали × h по вертикали).
	local function bar(a, b, w, h, color, material, extra)
		local len = (b - a).Magnitude
		return boxCF(look((a + b) / 2, b), V(w, h, len), color, material, extra)
	end
	local NOSHADOW = { castShadow = false }
	local GLOW = { castShadow = false, canQuery = false }

	-- Невидимый излучатель света в точке pos, направленный на target (Face = Front).
	local function emitter(pos, target, kind, props)
		local e = boxCF(look(pos, target or (pos + V(0, -1, 0))), V(0.2, 0.2, 0.2), C.frame, "SmoothPlastic", {
			name = "LightEmitter",
			transparency = 1,
			castShadow = false,
			canQuery = false,
		})
		local p = table.clone(props)
		if kind ~= "PointLight" then
			p.Face = p.Face or "Front"
		end
		B:light(e, kind, p)
		return e
	end

	-- Надпись на грани детали: маленькая метка по центру (доля size от грани).
	local function label(part, face, text, color, sx, sy)
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId[face]
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 120
		g.LightInfluence = 1
		g.Parent = part
		local t = Instance.new("TextLabel")
		t.AnchorPoint = roblox.Vector2.new(0.5, 0.5)
		t.Position = roblox.UDim2.fromScale(0.5, 0.5)
		t.Size = roblox.UDim2.fromScale(sx or 0.8, sy or 0.4)
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = color
		t.FontFace = roblox.Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
		t.Parent = g
		return g
	end

	---------------------------------------------------------------- 1. Коробка зала
	group("Shell")
	local W = ROOM_W
	local zMid = (Z_FRONT + ANNEX_Z) / 2
	local zLen = ANNEX_Z - Z_FRONT
	-- пол (верх Y=0) под залом и нишей
	box(V(0, -0.5, zMid), V(2 * W + 2, 1, zLen + 2), C.floor, "Rubber", nil, { name = "Floor" })
	-- швы резиновых плит 4×4 (тонкие тёмные полосы поверх пола)
	for z = Z_FRONT + 4, Z_BACK - 1, 4 do
		box(V(0, 0.006, z), V(2 * W - 0.2, 0.012, 0.05), C.floorSeam, "Rubber", nil, { name = "FloorSeam", castShadow = false })
	end
	for x = -W + 4, W - 4, 4 do
		box(V(x, 0.005, (Z_FRONT + Z_BACK) / 2), V(0.05, 0.01, Z_BACK - Z_FRONT - 0.2), C.floorSeam, "Rubber", nil, { name = "FloorSeam", castShadow = false })
	end
	-- стены зала
	local wallH = CEIL + 0.3
	box(V(W + 0.5, wallH / 2, (Z_FRONT + Z_BACK) / 2), V(1, wallH, Z_BACK - Z_FRONT + 2), C.wall, "Plaster", nil, { name = "WallLeftPlusX" })
	box(V(-W - 0.5, wallH / 2, (Z_FRONT + Z_BACK) / 2), V(1, wallH, Z_BACK - Z_FRONT + 2), C.wall, "Plaster", nil, { name = "WallRightMinusX" })
	box(V(0, wallH / 2, Z_FRONT - 0.5), V(2 * W, wallH, 1), C.wall, "Plaster", nil, { name = "WallFront" })
	-- задняя стена: два сегмента по бокам проёма
	local segLen = W - ANNEX_W
	for s = -1, 1, 2 do
		box(V(s * (ANNEX_W + segLen / 2), wallH / 2, Z_BACK + 0.5), V(segLen, wallH, 1), C.wall, "Plaster", nil, { name = "WallBack" })
		-- стены ниши
		box(V(s * (ANNEX_W + 0.5), wallH / 2, (Z_BACK + 1 + ANNEX_Z + 1) / 2), V(1, wallH, ANNEX_Z - Z_BACK), C.wall, "Plaster", nil, { name = "WallAnnex" })
		-- пилястры по краям проёма
		box(V(s * (ANNEX_W + 0.25), wallH / 2, Z_BACK - 0.22), V(1.1, wallH, 0.44), C.wallShade, "Plaster", nil, { name = "OpeningPilaster" })
	end
	box(V(0, wallH / 2, ANNEX_Z + 0.5), V(2 * ANNEX_W + 2, wallH, 1), C.wall, "Plaster", nil, { name = "WallAnnexFar" })
	-- плинтусы
	local SK_H, SK_T = 0.38, 0.07
	box(V(W - SK_T / 2, SK_H / 2, (Z_FRONT + Z_BACK) / 2), V(SK_T, SK_H, Z_BACK - Z_FRONT), C.skirting, "SmoothPlastic", nil, { name = "Skirting" })
	box(V(-W + SK_T / 2, SK_H / 2, (Z_FRONT + Z_BACK) / 2), V(SK_T, SK_H, Z_BACK - Z_FRONT), C.skirting, "SmoothPlastic", nil, { name = "Skirting" })
	box(V(0, SK_H / 2, Z_FRONT + SK_T / 2), V(2 * W - 0.2, SK_H, SK_T), C.skirting, "SmoothPlastic", nil, { name = "Skirting" })
	for s = -1, 1, 2 do
		box(V(s * (ANNEX_W + 0.8 + (segLen - 0.8) / 2), SK_H / 2, Z_BACK - SK_T / 2), V(segLen - 0.8 - 0.1, SK_H, SK_T), C.skirting, "SmoothPlastic", nil, { name = "Skirting" })
		box(V(s * (ANNEX_W - SK_T / 2), SK_H / 2, (Z_BACK + ANNEX_Z) / 2 + 0.5), V(SK_T, SK_H, ANNEX_Z - Z_BACK - 1.1), C.skirting, "SmoothPlastic", nil, { name = "Skirting" })
	end
	box(V(0, SK_H / 2, ANNEX_Z - SK_T / 2), V(2 * ANNEX_W - 0.2, SK_H, SK_T), C.skirting, "SmoothPlastic", nil, { name = "Skirting" })

	---------------------------------------------------------------- 2. Потолок: чёрная подложка + деревянные рейки
	group("Ceiling")
	box(V(0, CEIL + 0.6, zMid), V(2 * W + 2, 0.8, zLen + 2), C.ceilingBack, "SmoothPlastic", nil, { name = "CeilingBacking" })
	do
		local plankW, gap = 1.05, 0.08
		local z = Z_FRONT + 0.3
		local i = 0
		while z + plankW <= ANNEX_Z - 0.3 do
			i += 1
			local zc = z + plankW / 2
			local inAnnex = zc > Z_BACK + 0.5
			local half = if inAnnex then ANNEX_W - 0.3 else W - 0.3
			local col = C.woods[1 + math.floor(rnd() * #C.woods)]
			-- лёгкий разброс высоты (0…0.015) — рейки не идеально в одной плоскости
			local dy = math.floor(rnd() * 3) * 0.006
			box(V(0, CEIL + 0.09 + dy, zc), V(2 * half, 0.18, plankW), col, "Wood", nil, { name = "CeilingPlank" })
			z += plankW + gap
		end
	end

	---------------------------------------------------------------- 3. Неон под потолком
	group("Neon")
	local NEON_Y = CEIL - 0.42
	local function neon(a, b, color, lightColor, opts)
		opts = opts or {}
		local d = opts.d or 0.13
		local tube = rod(a, b, d, color, "Neon", { name = "NeonTube", castShadow = false, canQuery = false })
		-- держатели: тонкие тросы к потолку + клипсы
		local len = (b - a).Magnitude
		local n = math.max(2, math.floor(len / 7) + 1)
		for k = 0, n - 1 do
			local t = (k + 0.5) / n
			local p = a:Lerp(b, t)
			if opts.hang ~= false then
				rod(p + V(0, d / 2, 0), V(p.X, CEIL - 0.005, p.Z), 0.025, C.steelDark, "Metal", { name = "NeonWire", castShadow = false })
			end
			rod(p - (b - a).Unit * 0.06, p + (b - a).Unit * 0.06, d + 0.05, C.steelDark, "SmoothPlastic", { name = "NeonClip", castShadow = false })
		end
		-- свет: протяжённый SurfaceLight вниз и вверх (подсветка дерева вокруг трубки)
		if lightColor then
			local holder = bar(a, b, 0.05, 0.05, color, "SmoothPlastic", { name = "NeonLight", transparency = 1, castShadow = false, canQuery = false })
			B:light(holder, "SurfaceLight", { Face = "Bottom", Color = lightColor, Brightness = opts.down or 1.6, Range = opts.range or 16, Angle = 150, Shadows = false })
			B:light(holder, "SurfaceLight", { Face = "Top", Color = lightColor, Brightness = opts.up or 1.2, Range = 5, Angle = 170, Shadows = false })
		end
		return tube
	end
	local Y = NEON_Y
	-- главный зигзаг (как в клипе): от ближнего +X угла к центру глубины, от −X к той же вершине, оттуда оранжевый в нишу
	local apex = V(-1.2, Y, 19.5)
	neon(V(19.2, Y, -7.5), apex, C.neonPurple, LIGHT_PURPLE, { down = 1.8 })
	neon(V(-19.2, Y, 3.5), apex, C.neonViolet, LIGHT_PURPLE, { down = 1.6 })
	neon(apex, V(-6.3, Y, 33.5), C.neonOrange, LIGHT_ORANGE, { down = 1.4, range = 14 })
	-- ближняя часть зала (видна, когда камера смотрит вверх/назад)
	neon(V(19.2, Y, -7.5), V(-19.2, Y, -21.5), C.neonMagenta, LIGHT_MAGENTA, { down = 1.4 })
	neon(V(-19.2, Y, 3.5), V(-6, Y, -9), C.neonMagenta, LIGHT_MAGENTA, { down = 1.0, range = 12 })
	-- жёлтая вертикальная полоса на зеркальной стене (+X, слева в кадре)
	rod(V(13.25, CEIL - 0.25, Z_BACK - 0.12), V(12.75, 7.2, Z_BACK - 0.12), 0.1, C.neonYellow, "Neon", { name = "NeonAccent", castShadow = false, canQuery = false })
	do
		local h = bar(V(13.25, CEIL - 0.3, Z_BACK - 0.3), V(12.75, 7.2, Z_BACK - 0.3), 0.05, 0.05, C.neonYellow, "SmoothPlastic", { name = "NeonLight", transparency = 1, castShadow = false, canQuery = false })
		B:light(h, "SurfaceLight", { Face = "Front", Color = Color3.fromRGB(255, 200, 90), Brightness = 0.8, Range = 6, Angle = 160 })
	end

	---------------------------------------------------------------- 4. Свет: треки со спотами, встроенные даунлайты
	group("Lights")
	local function trackRail(a, b, hangY)
		-- рельс трека (чёрный профиль) на тросах
		bar(a, b, 0.14, 0.09, C.steelDark, "SmoothPlastic", { name = "TrackRail", castShadow = false })
		if hangY then
			for _, t in { 0.08, 0.92 } do
				local p = a:Lerp(b, t)
				rod(p + V(0, 0.045, 0), V(p.X, hangY, p.Z), 0.025, C.steelDark, "Metal", { name = "TrackWire", castShadow = false })
			end
		end
	end
	-- Спот на треке: base — точка на нижней грани рельса.
	local function spot(base, target, props)
		boxCF(CFrame.new(base - V(0, 0.07, 0)), V(0.16, 0.13, 0.3), C.steelDark, "SmoothPlastic", { name = "SpotAdapter", castShadow = false })
		local pivot = base - V(0, 0.42, 0)
		rod(base - V(0, 0.12, 0), pivot, 0.06, C.steelDark, "Metal", { name = "SpotStem", castShadow = false })
		local dir = (target - pivot).Unit
		rod(pivot - dir * 0.16, pivot + dir * 0.38, 0.3, C.steelDark, "SmoothPlastic", { name = "SpotHead", castShadow = false })
		rod(pivot - dir * 0.2, pivot - dir * 0.15, 0.22, C.steelDark, "SmoothPlastic", { name = "SpotCap", castShadow = false })
		rod(pivot + dir * 0.33, pivot + dir * 0.4, 0.23, C.lamp, "Neon", { name = "SpotLens", castShadow = false, canQuery = false })
		if props then
			local p = table.clone(props)
			p.Color = p.Color or LIGHT_WARM
			p.Brightness = p.Brightness or 2.5
			p.Range = p.Range or 22
			p.Angle = p.Angle or 45
			emitter(pivot + dir * 0.55, target, "SpotLight", p)
		end
	end
	local TRACK_Y = CEIL - 0.75
	-- прямоугольная рама трека над конём/за ним (видна в кадре S10 над головой коня)
	do
		local x0, x1, z0, z1 = -5.2, 3.2, 5.5, 13.5
		local c00, c10, c11, c01 = V(x0, TRACK_Y, z0), V(x1, TRACK_Y, z0), V(x1, TRACK_Y, z1), V(x0, TRACK_Y, z1)
		trackRail(c00 - V(0.07, 0, 0), c10 + V(0.07, 0, 0), CEIL)
		trackRail(c01 - V(0.07, 0, 0), c11 + V(0.07, 0, 0), CEIL)
		trackRail(c00 + V(0, 0, 0.07), c01 - V(0, 0, 0.07), nil)
		trackRail(c10 + V(0, 0, 0.07), c11 - V(0, 0, 0.07), nil)
		local yb = TRACK_Y - 0.045
		-- контровой свет на коня (сзади-сверху) — с тенями
		spot(V(-1.0, yb, z0), V(0, 4.6, 0.6), { Brightness = 3.2, Range = 20, Angle = 40, Shadows = true, Color = Color3.fromRGB(255, 205, 235) })
		spot(V(2.0, yb, z0), V(0.8, 2.0, 1.0), { Brightness = 1.6, Range = 18, Angle = 50 })
		-- статисты слева/справа в кадре
		spot(V(x1, yb, 9.5), V(5.5, 3.2, 5.5), { Brightness = 2.2, Range = 20, Angle = 55 })
		spot(V(x0, yb, 9.5), V(-5.5, 3.2, 5.5), { Brightness = 2.2, Range = 20, Angle = 55 })
		-- стойки
		spot(V(-2.5, yb, z1), V(-11, 2.4, 12.6), { Brightness = 2.0, Range = 22, Angle = 50 })
		spot(V(0.8, yb, z1), V(10, 2.4, 12.6), { Brightness = 2.0, Range = 22, Angle = 50 })
	end
	-- линия трека в нишу (уходит вдаль «вправо» в кадре)
	do
		local a, b = V(-4.6, TRACK_Y, 15.0), V(-4.6, TRACK_Y, 34.5)
		trackRail(a, b, CEIL)
		local yb = TRACK_Y - 0.045
		spot(V(-4.6, yb, 19), V(-2, 0.5, 23), { Brightness = 2.2, Range = 22, Angle = 60, Color = LIGHT_AMBER })
		spot(V(-4.6, yb, 25), V(2.5, 3.5, 29), { Brightness = 2.4, Range = 22, Angle = 60, Color = LIGHT_AMBER })
		spot(V(-4.6, yb, 31), V(0, 4.5, ANNEX_Z), { Brightness = 3.0, Range = 22, Angle = 70, Color = LIGHT_AMBER })
	end
	-- передний трек (поперёк зала над камерой): ключевой и заполняющий на коня
	do
		local z = -5.5
		trackRail(V(-8, TRACK_Y, z), V(8, TRACK_Y, z), CEIL)
		local yb = TRACK_Y - 0.045
		spot(V(2.2, yb, z), V(0, 4.8, 0), { Brightness = 3.6, Range = 26, Angle = 42, Shadows = true, Color = LIGHT_WARM })
		spot(V(-3.0, yb, z), V(-0.3, 3.2, 0.4), { Brightness = 1.4, Range = 24, Angle = 60, Color = Color3.fromRGB(210, 170, 255) })
		spot(V(6.0, yb, z), V(6, 0, 4), { Brightness = 1.2, Range = 22, Angle = 60 })
		spot(V(-6.0, yb, z), V(-6, 0, 4), { Brightness = 1.2, Range = 22, Angle = 60 })
	end
	-- задний трек у входа (для общих планов)
	do
		local z = -17
		trackRail(V(-10, TRACK_Y, z), V(10, TRACK_Y, z), CEIL)
		local yb = TRACK_Y - 0.045
		spot(V(-6, yb, z), V(-6, 0, -12), { Brightness = 1.4, Range = 20, Angle = 70 })
		spot(V(6, yb, z), V(6, 0, -12), { Brightness = 1.4, Range = 20, Angle = 70 })
	end
	-- встроенные даунлайты (чёрное кольцо + светящаяся линза)
	local function downlight(x, z, props)
		cylX(CFrame.new(x, CEIL - 0.03, z) * CFrame.Angles(0, 0, math.pi / 2), 0.06, 0.78, C.steelDark, "SmoothPlastic", { name = "DownlightRing", castShadow = false })
		cylX(CFrame.new(x, CEIL - 0.065, z) * CFrame.Angles(0, 0, math.pi / 2), 0.02, 0.44, C.lamp, "Neon", { name = "DownlightLens", castShadow = false, canQuery = false })
		if props then
			local p = table.clone(props)
			p.Color = p.Color or LIGHT_WARM
			emitter(V(x, CEIL - 0.25, z), V(x, 0, z), "SpotLight", p)
		end
	end
	downlight(-1.0, 3.2, { Brightness = 1.6, Range = 18, Angle = 70 })
	downlight(12, -2, { Brightness = 1.2, Range = 18, Angle = 80 })
	downlight(-12, -2, { Brightness = 1.2, Range = 18, Angle = 80 })
	downlight(12, -14, nil)
	downlight(-12, -14, nil)
	downlight(0, 27, { Brightness = 1.4, Range = 16, Angle = 80, Color = LIGHT_AMBER })
	-- мягкая сиреневая заливка стен (скрытые споты у потолка, «карниз»)
	for _, wspec in {
		{ V(17.5, CEIL - 0.6, 6), V(19.9, 3, 9) },
		{ V(-17.5, CEIL - 0.6, 6), V(-19.9, 3, 9) },
		{ V(17.5, CEIL - 0.6, -12), V(19.9, 3, -12) },
		{ V(-17.5, CEIL - 0.6, -12), V(-19.9, 3, -12) },
		{ V(13, CEIL - 0.6, 12.5), V(13, 4, 16) },
		{ V(-13, CEIL - 0.6, 12.5), V(-13, 4, 16) },
	} do
		emitter(wspec[1], wspec[2], "SpotLight", { Brightness = 1.6, Range = 18, Angle = 100, Color = LIGHT_MAGENTA })
	end
	-- общая слабая фиолетовая заливка в центре зала
	emitter(V(0, 9, -2), nil, "PointLight", { Brightness = 0.6, Range = 26, Color = LIGHT_PURPLE })
	-- «отражённый» тёплый свет под потолком (в Roblox нет переотражений — без него дерево чёрное)
	for _, p in { V(-10, 10.4, -1), V(10, 10.4, -1), V(-10, 10.4, 9), V(10, 10.4, 9), V(0, 10.4, -13), V(0, 10.4, 21) } do
		emitter(p, nil, "PointLight", { Brightness = 0.55, Range = 10, Color = Color3.fromRGB(255, 196, 160) })
	end

	---------------------------------------------------------------- 5. Скамьи
	local ROT_Z = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра (локальная X детали) -> локальная −Z
	-- Подушка со скруглёнными краями: cf — центр (X — ширина, Z — длина), высота h.
	local function pad(cf, wdt, len, h, color, name)
		local r = h / 2
		boxCF(cf, V(wdt - h, h, len - h), color, "Leather", { name = name or "Pad" })
		for s = -1, 1, 2 do
			cylX(cf * CFrame.new(s * (wdt / 2 - r), 0, 0) * ROT_Z, len - h, h, color, "Leather", { name = "PadEdge" })
			cylX(cf * CFrame.new(0, 0, s * (len / 2 - r)), wdt - h, h, color, "Leather", { name = "PadEdge" })
			for s2 = -1, 1, 2 do
				P({ cf = cf * CFrame.new(s * (wdt / 2 - r), 0, s2 * (len / 2 - r)), size = V(h, h, h), shape = "Ball", color = color, material = "Leather", name = "PadCorner" })
			end
		end
	end
	-- Скамья (регулируемая, как в клипе). cf — центр на полу, длинная ось — локальная Z, «перед» — −Z.
	-- incline — угол спинки (0 = горизонтально).
	local function bench(cf, opts)
		opts = opts or {}
		local L = opts.length or 3.6
		local Wd = opts.width or 1.1
		local top = opts.seatTop or 1.55
		local incline = opts.incline or 0
		local seatLen = 1.22
		local gap = 0.06
		local backLen = L - seatLen - gap
		local padH = 0.3
		local padY = top - padH / 2
		local zSeat = -L / 2 + seatLen / 2
		-- сиденье
		local seatCF = cf * CFrame.new(0, padY, zSeat)
		pad(seatCF, Wd, seatLen, padH, C.leather, "SeatPad")
		boxCF(seatCF * CFrame.new(0, -padH / 2 - 0.035, 0), V(Wd - 0.24, 0.07, seatLen - 0.16), C.steelDark, "Metal", { name = "PadBoard" })
		-- спинка (шарнир у переднего края)
		local hingeZ = -L / 2 + seatLen + gap
		local hinge = cf * CFrame.new(0, padY, hingeZ) * CFrame.Angles(-rad(incline), 0, 0)
		local backCF = hinge * CFrame.new(0, 0, backLen / 2)
		pad(backCF, Wd, backLen, padH, C.leather, "BackPad")
		boxCF(backCF * CFrame.new(0, -padH / 2 - 0.035, 0), V(Wd - 0.24, 0.07, backLen - 0.16), C.steelDark, "Metal", { name = "PadBoard" })
		-- рама
		local yS0, yS1 = 0.3, 0.52 -- хребет
		boxCF(cf * CFrame.new(0, (yS0 + yS1) / 2, 0.05), V(0.3, yS1 - yS0, L - 0.55), C.steel, "Metal", { name = "BenchSpine" })
		local zF, zR = -L / 2 + 0.32, L / 2 - 0.3
		boxCF(cf * CFrame.new(0, 0.18, zF), V(1.5, 0.24, 0.26), C.steel, "Metal", { name = "BenchFoot" })
		boxCF(cf * CFrame.new(0, 0.18, zR), V(1.36, 0.24, 0.26), C.steel, "Metal", { name = "BenchFoot" })
		for s = -1, 1, 2 do
			-- резиновые колпачки и колёса
			boxCF(cf * CFrame.new(s * 0.79, 0.18, zR), V(0.08, 0.26, 0.28), C.rubber, "Rubber", { name = "FootCap" })
			cylX(cf * CFrame.new(s * 0.82, 0.155, zF), 0.12, 0.31, C.rubber, "Rubber", { name = "Wheel" })
			cylX(cf * CFrame.new(s * 0.82, 0.155, zF), 0.13, 0.12, C.chrome, "Metal", { name = "WheelHub" })
			-- опорные «пятки» под задней ногой
			cylX(cf * CFrame.new(s * 0.6, 0.03, zR) * CFrame.Angles(0, 0, math.pi / 2), 0.06, 0.22, C.rubber, "Rubber", { name = "FootPad" })
		end
		-- стойки
		local seatBottom = top - padH - 0.07
		boxCF(cf * CFrame.new(0, (yS1 + seatBottom) / 2, zSeat + 0.1), V(0.22, seatBottom - yS1, 0.22), C.steel, "Metal", { name = "SeatPost" })
		-- поп-пин на стойке сиденья
		cylX(cf * CFrame.new(0.2, yS1 + 0.3, zSeat + 0.1), 0.2, 0.07, C.chrome, "Metal", { name = "PopPin" })
		ball(cf * CFrame.new(0.32, yS1 + 0.3, zSeat + 0.1).Position, 0.13, C.rubber, "Rubber", { name = "PopPinKnob" })
		-- опора спинки: стойка-«лестница» по диагонали + подкос к подушке
		local ladA = cf * CFrame.new(0, yS1 + 0.02, hingeZ + 0.05)
		local ladB = cf * CFrame.new(0, yS1 + 0.42, zR - 0.15)
		bar(ladA.Position, ladB.Position, 0.16, 0.08, C.steelDark, "Metal", { name = "Ladder" })
		for k = 1, 4 do
			local p = ladA.Position:Lerp(ladB.Position, k / 5) + (cf.UpVector * 0.06)
			boxCF(look(p, p + (ladB.Position - ladA.Position)), V(0.16, 0.05, 0.06), C.steelDark, "Metal", { name = "LadderTooth" })
		end
		local under = (backCF * CFrame.new(0, -padH / 2 - 0.07, backLen * 0.1)).Position
		local strutBase = ladA.Position:Lerp(ladB.Position, if incline > 0 then 0.25 else 0.85)
		bar(strutBase, under, 0.14, 0.14, C.steel, "Metal", { name = "BackStrut" })
		-- ручка для перекатывания
		local hA = (cf * CFrame.new(0, 0.3, zR + 0.12)).Position
		local hB = (cf * CFrame.new(0, 0.62, zR + 0.55)).Position
		bar(hA, hB, 0.12, 0.12, C.steel, "Metal", { name = "BenchHandle" })
		rod(hB, (cf * CFrame.new(0, 0.7, zR + 0.68)).Position, 0.16, C.rubber, "Rubber", { name = "HandleGrip" })
	end

	group("HorseBench")
	bench(CFrame.new(0, 0, 0.4), { length = 3.6, width = 1.1, seatTop = 1.55 })
	-- метка плоскости сиденья для постановки (невидимая)
	box(V(0, 1.55 - 0.005, -0.85), V(0.6, 0.01, 0.6), C.leather, "SmoothPlastic", nil, { name = "SeatTop", transparency = 1, castShadow = false, canQuery = false })

	group("Benches")
	bench(CFrame.new(12.6, 0, 1.0) * CFrame.Angles(0, rad(8), 0), { incline = 0 })
	bench(CFrame.new(-12.4, 0, 0.4) * CFrame.Angles(0, rad(-12), 0), { incline = 32 })
	-- наклонная скамья у задней стены за правой (−X) стойкой: спинка почти вертикальна и видна над гантелями
	bench(CFrame.new(-13.2, 0, 14.75) * CFrame.Angles(0, rad(90), 0), { incline = 72 })

	---------------------------------------------------------------- 6. Гантельные стойки
	group("DumbbellRacks")
	local WHITE = Color3.fromRGB(235, 235, 240)
	local function dumbbell(cf, kg)
		local t = math.clamp((kg - 2.5) / 47.5, 0, 1)
		local d = 0.5 + 0.56 * t
		local w = 0.24 + 0.36 * t
		local grip = 0.9
		local zh = grip / 2 + w / 2
		for s = -1, 1, 2 do
			cylX(cf * CFrame.new(0, 0, s * zh) * ROT_Z, w, d, C.rubber, "Rubber", { name = "DumbbellHead" })
			cylX(cf * CFrame.new(0, 0, s * (grip / 2 - 0.035)) * ROT_Z, 0.07, 0.25, C.chrome, "Metal", { name = "DumbbellCollar" })
		end
		cylX(cf * ROT_Z, grip + 0.06, 0.15, C.chrome, "Metal", { name = "DumbbellHandle" })
		local cap = cylX(cf * CFrame.new(0, 0, -(grip / 2 + w) - 0.005) * ROT_Z, 0.03, d * 0.58, C.rubberCap, "SmoothPlastic", { name = "DumbbellCap" })
		local txt = if kg % 1 == 0 then string.format("%d", kg) else string.format("%.1f", kg)
		label(cap, "Right", txt, WHITE, 0.9, 0.42)
		return d
	end
	local TILT = -14
	-- Стойка: xa..xb (inner — сторона, где лёгкие гантели), центр по глубине zc; tiers — { {kg...}, {kg...} } (нижний, верхний)
	local function rack(xa, xb, zc, innerAtA, tiers, missing)
		local L = math.abs(xb - xa)
		local xm = (xa + xb) / 2
		local rcf = CFrame.new(xm, 0, zc)
		local trayDepth = 1.9
		local trayCFs = {
			rcf * CFrame.new(0, 1.18, -0.72) * CFrame.Angles(rad(TILT), 0, 0),
			rcf * CFrame.new(0, 2.42, 0.78) * CFrame.Angles(rad(TILT), 0, 0),
		}
		for ti, tcf in trayCFs do
			boxCF(tcf * CFrame.new(0, -0.025, 0), V(L, 0.05, trayDepth), C.steelDark, "Metal", { name = "RackTray" })
			boxCF(tcf * CFrame.new(0, 0.05, -trayDepth / 2 - 0.03), V(L, 0.2, 0.06), C.steel, "Metal", { name = "RackLip" })
			boxCF(tcf * CFrame.new(0, 0.03, trayDepth / 2 + 0.03), V(L, 0.16, 0.06), C.steel, "Metal", { name = "RackLip" })
			-- гантели парами, от лёгких к тяжёлым
			local list = tiers[ti]
			local dir = if innerAtA then 1 else -1
			local startX = (if innerAtA then -L / 2 else L / 2) + dir * 0.3
			local x = startX
			for pi, kg in list do
				local t = math.clamp((kg - 2.5) / 47.5, 0, 1)
				local d = 0.5 + 0.56 * t
				local pairW = 2 * d + 0.07
				if math.abs(x + dir * pairW - startX) > L - 0.5 then
					break
				end
				local skip = missing and missing[ti] == pi
				for k = 0, 1 do
					local cx = x + dir * (d / 2 + k * (d + 0.07))
					if not skip then
						dumbbell(tcf * CFrame.new(cx, d / 2 + 0.002, 0), kg)
					end
				end
				x += dir * (pairW + 0.2)
			end
		end
		-- рамы
		local frames = { -L / 2 + 0.22, L / 2 - 0.22 }
		if L > 7 then
			table.insert(frames, 0)
		end
		for _, fx in frames do
			boxCF(rcf * CFrame.new(fx, 0.06, 0.05), V(0.16, 0.12, 3.5), C.steel, "Metal", { name = "RackFoot" })
			for s = -1, 1, 2 do
				boxCF(rcf * CFrame.new(fx, 0.06, 0.05 + s * 1.79), V(0.18, 0.13, 0.08), C.rubber, "Rubber", { name = "RackFootCap" })
			end
			-- ноги
			local legs = { { -1.55, 0.93 }, { 0.12, 2.14 }, { 1.62, 2.55 } }
			for _, lg in legs do
				boxCF(rcf * CFrame.new(fx, (0.12 + lg[2]) / 2, lg[1]), V(0.15, lg[2] - 0.12, 0.15), C.steel, "Metal", { name = "RackLeg" })
			end
			-- кронштейны лотков
			for _, tcf in trayCFs do
				boxCF(tcf * CFrame.new(fx, -0.13, 0), V(0.14, 0.16, trayDepth + 0.1), C.steel, "Metal", { name = "RackArm" })
			end
		end
	end
	-- +X (слева в кадре): лёгкие, у проёма
	rack(7.7, 19.5, 12.0, true, {
		{ 2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20 },
		{ 20, 22.5, 25, 27.5, 30, 32.5 },
	}, { [2] = 3 })
	-- −X (справа в кадре): тяжёлые
	rack(-7.7, -19.5, 12.0, true, {
		{ 22.5, 25, 27.5, 30, 32.5, 35 },
		{ 35, 37.5, 40, 42.5, 45, 50 },
	}, { [1] = 2 })

	---------------------------------------------------------------- 7. Стены: зеркала, рамы, доска, колонна, колонка
	group("WallDecor")
	-- зеркала на задней стене слева в кадре (+X)
	local function mirror(x0, x1, y0, y1, z)
		local w, h = x1 - x0, y1 - y0
		local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
		box(V(cx, cy, z - 0.03), V(w, h, 0.06), C.mirror, "Glass", nil, { name = "Mirror", reflectance = 0.22 })
		local ft, fd = 0.07, 0.1
		box(V(cx, y1 + ft / 2, z - fd / 2), V(w + 2 * ft, ft, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		box(V(cx, y0 - ft / 2, z - fd / 2), V(w + 2 * ft, ft, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		box(V(x0 - ft / 2, cy, z - fd / 2), V(ft, h, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		box(V(x1 + ft / 2, cy, z - fd / 2), V(ft, h, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
	end
	mirror(7.95, 12.45, 1.9, 9.4, Z_BACK)
	mirror(13.55, 19.75, 1.9, 9.4, Z_BACK)
	-- полка под зеркалами
	box(V(13.85, 1.78, Z_BACK - 0.11), V(11.8, 0.1, 0.22), C.wallShade, "SmoothPlastic", nil, { name = "MirrorLedge" })
	-- зеркало на боковой стене +X (длинное)
	do
		local x = W
		box(V(x - 0.03, 5.2, -2), V(0.06, 6.6, 16), C.mirror, "Glass", nil, { name = "Mirror", reflectance = 0.22 })
		for _, zz in { -10.04, 6.04 } do
			box(V(x - 0.05, 5.2, zz), V(0.1, 6.74, 0.07), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		end
		for _, yy in { 1.865, 8.535 } do
			box(V(x - 0.05, yy, -2), V(0.1, 0.07, 16.15), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		end
	end
	-- колонна справа в кадре (−X) у задней стены
	box(V(-17.3, wallH / 2, Z_BACK - 0.3), V(1.3, wallH, 0.6), C.wallShade, "Plaster", nil, { name = "Column" })
	-- рамы с принтами
	local function frame(cx, cy, w, h, z, art, artMat)
		local ft = 0.08
		box(V(cx, cy, z - 0.02), V(w, h, 0.04), art, artMat or "SmoothPlastic", nil, { name = "Print" })
		box(V(cx, cy + h / 2 + ft / 2, z - 0.05), V(w + 2 * ft, ft, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
		box(V(cx, cy - h / 2 - ft / 2, z - 0.05), V(w + 2 * ft, ft, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
		box(V(cx - w / 2 - ft / 2, cy, z - 0.05), V(ft, h, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
		box(V(cx + w / 2 + ft / 2, cy, z - 0.05), V(ft, h, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
	end
	frame(-14.4, 6.6, 1.0, 3.2, Z_BACK, hex("2a2630"))
	frame(-10.6, 7.2, 1.9, 2.5, Z_BACK, hex("3a2d3e"))
	do -- принт: силуэт гантели на тёмном
		local z = Z_BACK - 0.05
		box(V(-10.6, 7.2, z), V(1.1, 0.08, 0.02), hex("c9b6d6"), "SmoothPlastic", nil, { name = "PrintArt", castShadow = false })
		for s = -1, 1, 2 do
			box(V(-10.6 + s * 0.52, 7.2, z), V(0.12, 0.62, 0.02), hex("c9b6d6"), "SmoothPlastic", nil, { name = "PrintArt", castShadow = false })
			box(V(-10.6 + s * 0.38, 7.2, z), V(0.1, 0.42, 0.02), hex("c9b6d6"), "SmoothPlastic", nil, { name = "PrintArt", castShadow = false })
		end
	end
	-- высокая чёрная доска со скруглённым верхом, прислонённая к стене (как в клипе), с вертикальной надписью
	do
		local hgt, wdt, th = 4.7, 0.78, 0.12
		local lean = rad(7)
		local base = V(-15.75, 0, Z_BACK - 0.68)
		local bcf = CFrame.new(base) * CFrame.Angles(lean, 0, 0) -- верх отклонён к стене (+Z)
		local board = boxCF(bcf * CFrame.new(0, (hgt - wdt / 2) / 2, 0), V(wdt, hgt - wdt / 2, th), hex("141217"), "SmoothPlastic", { name = "LeaningBoard" })
		cylX(bcf * CFrame.new(0, hgt - wdt / 2, 0) * ROT_Z, th, wdt, hex("141217"), "SmoothPlastic", { name = "LeaningBoardTop" })
		local g = label(board, "Front", "AURA FARMER", Color3.fromRGB(225, 220, 230), 0.9, 0.12)
		local t = g:FindFirstChildWhichIsA("TextLabel")
		t.Size = roblox.UDim2.fromScale(3.6, 0.16)
		t.Rotation = -90
	end
	-- розетка с вилкой на зеркальной стороне (мелочь из кадра)
	box(V(16.9, 1.25, Z_BACK - 0.03), V(0.32, 0.32, 0.06), hex("e8e6ea"), "SmoothPlastic", nil, { name = "Socket" })
	box(V(16.9, 1.25, Z_BACK - 0.09), V(0.12, 0.16, 0.08), C.frame, "SmoothPlastic", nil, { name = "Plug" })
	-- напольная колонка (слева в кадре, у ног статиста)
	do
		local cf = CFrame.new(10.9, 0, 6.6) * CFrame.Angles(0, rad(28), 0)
		local hgt = 1.95
		boxCF(cf * CFrame.new(0, 0.06 + hgt / 2, 0), V(1.3, hgt, 1.05), hex("0d0d10"), "SmoothPlastic", { name = "Speaker" })
		for s = -1, 1, 2 do
			boxCF(cf * CFrame.new(s * 0.5, 0.03, 0), V(0.18, 0.06, 0.9), C.rubber, "Rubber", { name = "SpeakerFoot" })
		end
		local face = cf * CFrame.new(0, 0, -0.525)
		local function driver(y, d, depth)
			local ccf = face * CFrame.new(0, y, 0) * ROT_Z
			cylX(ccf * CFrame.new(-0.02, 0, 0), 0.06, d, hex("1d1d22"), "SmoothPlastic", { name = "SpeakerRing" })
			cylX(ccf * CFrame.new(-0.03, 0, 0), 0.04, d * 0.84, hex("060607"), "Fabric", { name = "SpeakerCone" })
			P({ cf = ccf * CFrame.new(-0.02 + depth, 0, 0), size = V(0.12, d * 0.3, d * 0.3), shape = "Ball", color = hex("202026"), material = "SmoothPlastic", name = "SpeakerDustCap" })
		end
		driver(0.75, 0.95, 0.0)
		driver(1.6, 0.36, 0.0)
		boxCF(face * CFrame.new(0, 0.2, -0.015), V(0.7, 0.1, 0.04), hex("030304"), "SmoothPlastic", { name = "SpeakerPort" })
		local led = boxCF(face * CFrame.new(0.45, 1.88, -0.012), V(0.05, 0.05, 0.03), Color3.fromRGB(80, 160, 255), "Neon", { name = "SpeakerLed", castShadow = false })
		led.CanQuery = false
	end
	-- гири вдоль боковой стены +X
	do
		local kgs = { 8, 12, 16, 16, 20, 24, 24, 28, 32 }
		local z = -11.5
		for _, kg in kgs do
			local d = 0.62 + kg * 0.011
			local x = W - 0.9
			ball(V(x, d / 2 + 0.02, z), d, C.rubber, "SmoothPlastic", { name = "Kettlebell", reflectance = 0.04 })
			cylX(CFrame.new(x, 0.04, z) * CFrame.Angles(0, 0, math.pi / 2), 0.08, d * 0.62, C.rubber, "SmoothPlastic", { name = "KettlebellBase" })
			local hy = d + 0.02 + d * 0.32
			local hw = d * 0.3
			rod(V(x, d * 0.82, z - hw), V(x, hy, z - hw * 0.9), 0.12, C.rubber, "SmoothPlastic", { name = "KettlebellHandle" })
			rod(V(x, d * 0.82, z + hw), V(x, hy, z + hw * 0.9), 0.12, C.rubber, "SmoothPlastic", { name = "KettlebellHandle" })
			rod(V(x, hy, z - hw * 0.9 - 0.06), V(x, hy, z + hw * 0.9 + 0.06), 0.12, C.rubber, "SmoothPlastic", { name = "KettlebellHandle" })
			z += d + 0.35
		end
	end

	---------------------------------------------------------------- 8. Ниша за проёмом: силовая рама, кроссовер, блины
	group("Annex")
	-- деревянный помост под рамой
	box(V(4.0, 0.06, 23.0), V(4.8, 0.12, 7.6), hex("6e5038"), "WoodPlanks", nil, { name = "Platform" })
	for s = -1, 1, 2 do
		box(V(4.0 + s * 1.95, 0.065, 23.0), V(0.9, 0.12, 7.6), hex("1a191e"), "Rubber", nil, { name = "PlatformRubber" })
	end
	-- силовая рама: стойки 0.28, гриф вдоль Z
	do
		local xs, zs = { 2.4, 5.7 }, { 21.0, 25.0 }
		local Ht = 8.2
		for _, x in xs do
			for _, z in zs do
				box(V(x, 0.12 + Ht / 2, z), V(0.28, Ht, 0.28), C.steel, "Metal", nil, { name = "RackUpright" })
			end
			box(V(x, 0.18, 23.0), V(0.28, 0.12, 4.28), C.steel, "Metal", nil, { name = "RackBase" })
			box(V(x, Ht + 0.12 - 0.15, 23.0), V(0.28, 0.24, 3.72), C.steel, "Metal", nil, { name = "RackTop" })
		end
		for _, z in zs do
			box(V(4.05, Ht + 0.12 - 0.15, z), V(3.02, 0.24, 0.28), C.steel, "Metal", nil, { name = "RackTop" })
			box(V(4.05, 0.18, z), V(3.02, 0.12, 0.28), C.steel, "Metal", nil, { name = "RackBase" })
			-- страховочные упоры
			box(V(4.05, 2.4, z), V(3.6, 0.16, 0.16), C.steelDark, "Metal", nil, { name = "SafetyArm" })
			-- J-крюки
			box(V(2.15, 4.35, z), V(0.24, 0.22, 0.2), C.steelDark, "Metal", nil, { name = "JHook" })
		end
		rod(V(2.2, Ht - 0.35, 20.6), V(2.2, Ht - 0.35, 25.4), 0.12, C.chrome, "Metal", { name = "PullupBar" })
		-- гриф с блинами
		local bx, by = 2.12, 4.58
		rod(V(bx, by, 19.6), V(bx, by, 26.4), 0.1, C.chrome, "Metal", { name = "Barbell" })
		for s = -1, 1, 2 do
			local zc = 23.0 + s * 2.55
			rod(V(bx, by, zc - 0.7), V(bx, by, zc + 0.7), 0.17, C.chrome, "Metal", { name = "BarbellSleeve" })
			local zz = 23.0 + s * 2.05
			for _, pl in { { 1.5, 0.24 }, { 1.5, 0.24 }, { 1.0, 0.15 } } do
				local zc2 = zz + s * pl[2] / 2
				rod(V(bx, by, zc2 - pl[2] / 2 + 0.005), V(bx, by, zc2 + pl[2] / 2 - 0.005), pl[1], C.rubber, "Rubber", { name = "Plate" })
				zz += s * (pl[2] + 0.02)
			end
			rod(V(bx, by, zz + s * 0.02), V(bx, by, zz + s * 0.14), 0.24, C.steelDark, "Metal", { name = "Clip" })
		end
	end
	-- стойка с блинами
	do
		local x, z = -4.6, 20.5
		box(V(x, 0.06, z), V(1.3, 0.12, 1.3), C.steel, "Metal", nil, { name = "PlateTreeBase" })
		box(V(x, 2.1, z), V(0.2, 4.0, 0.2), C.steel, "Metal", nil, { name = "PlateTreePost" })
		for _, pg in { { 0.85, 1, 1.5 }, { 0.85, -1, 1.5 }, { 2.15, 1, 1.1 }, { 2.15, -1, 1.1 }, { 3.3, 1, 0.8 }, { 3.3, -1, 0.8 } } do
			local y, s, d = pg[1], pg[2], pg[3]
			rod(V(x + s * 0.1, y, z), V(x + s * 0.65, y + 0.06, z), 0.1, C.chrome, "Metal", { name = "PlateTreePeg" })
			for k = 0, 1 do
				local px = x + s * (0.2 + 0.03 + k * 0.17)
				rod(V(px, y, z), V(px + s * 0.15, y, z), d, C.rubber, "Rubber", { name = "Plate" })
			end
		end
	end
	-- кроссовер у дальней стены
	do
		local zF, zB = 33.9, 35.6
		for s = -1, 1, 2 do
			local x = s * 4.9
			for _, z in { zF, zB } do
				box(V(x, 4.3, z), V(0.26, 8.6, 0.26), C.steel, "Metal", nil, { name = "CrossoverUpright" })
			end
			box(V(x, 8.5, (zF + zB) / 2), V(0.26, 0.24, zB - zF + 0.26), C.steel, "Metal", nil, { name = "CrossoverTop" })
			box(V(x, 0.12, (zF + zB) / 2), V(0.8, 0.24, zB - zF + 0.4), C.steel, "Metal", nil, { name = "CrossoverBase" })
			-- стек грузов
			for k = 0, 11 do
				box(V(x, 0.3 + k * 0.215, (zF + zB) / 2), V(0.66, 0.19, 0.95), C.steelDark, "Metal", nil, { name = "WeightPlate" })
			end
			box(V(x, 3.0, (zF + zB) / 2 - 0.5), V(0.5, 0.05, 0.03), Color3.fromRGB(230, 230, 235), "SmoothPlastic", nil, { name = "StackStripe", castShadow = false })
			for _, dz in { -0.28, 0.28 } do
				rod(V(x, 0.25, (zF + zB) / 2 + dz), V(x, 7.6, (zF + zB) / 2 + dz), 0.07, C.chrome, "Metal", { name = "GuideRod" })
			end
			-- кожух стека
			box(V(x - s * 0.36, 4.0, (zF + zB) / 2), V(0.06, 7.2, zB - zF - 0.2), C.steel, "Metal", nil, { name = "StackShroud" })
			-- блок и трос с рукоятью
			local px = x - s * 0.55
			cylX(CFrame.new(px, 7.6, zF - 0.1), 0.12, 0.42, C.steelDark, "Metal", { name = "Pulley" })
			rod(V(px, 7.4, zF - 0.1), V(px - s * 0.3, 4.2, zF - 0.4), 0.04, C.frame, "SmoothPlastic", { name = "Cable", castShadow = false })
			rod(V(px - s * 0.42, 4.05, zF - 0.42), V(px - s * 0.18, 4.05, zF - 0.38), 0.11, C.rubber, "Rubber", { name = "Handle" })
		end
		box(V(0, 8.5, zF), V(9.54, 0.26, 0.26), C.steel, "Metal", nil, { name = "CrossoverBeam" })
		rod(V(-2.4, 7.95, zF - 0.45), V(2.4, 7.95, zF - 0.45), 0.12, C.chrome, "Metal", { name = "PullupBar" })
		for s = -1, 1, 2 do
			box(V(s * 2.4, 8.22, zF - 0.24), V(0.16, 0.52, 0.5), C.steel, "Metal", nil, { name = "PullupBracket" })
		end
	end
	-- большая картина на дальней стене ниши (тёплое пятно в глубине кадра)
	frame(0, 9.6, 4.2, 1.5, ANNEX_Z, hex("b98a5a"), "SmoothPlastic")
	-- тёплые бра на дальней стене
	for s = -1, 1, 2 do
		local x = s * 2.9
		cylX(CFrame.new(x, 6.2, ANNEX_Z - 0.1) * ROT_Z, 0.2, 0.5, C.frame, "SmoothPlastic", { name = "Sconce", castShadow = false })
		emitter(V(x, 6.4, ANNEX_Z - 0.35), V(x, 12, ANNEX_Z - 0.6), "SpotLight", { Brightness = 1.6, Range = 10, Angle = 90, Color = LIGHT_AMBER })
		emitter(V(x, 6.0, ANNEX_Z - 0.35), V(x, 0, ANNEX_Z - 0.6), "SpotLight", { Brightness = 1.4, Range = 10, Angle = 90, Color = LIGHT_AMBER })
	end
end
