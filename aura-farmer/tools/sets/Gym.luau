--!nocheck
-- Декорация «Спортзал с фиолетовым неоном» (план S10).
--
-- Локальные координаты декорации: пол Y=0, +Y вверх. Конь сидит на скамье в (0,0,0) лицом в −Z,
-- камера обычно в −Z (z≈−6…−12) и смотрит в +Z. ВНИМАНИЕ: при взгляде камеры в +Z мир +X — СЛЕВА в кадре.
--
-- Контракт (AGENTS.md → Gym):
--   * зал x∈[−20,20], z∈[−26,…], пол Y=0 (тёмная резина), потолок Y=12 (дерево, узкие рейки),
--     диагональные неоновые трубки фиолет/маджента/оранж под потолком + трековые споты;
--   * скамья под конём: центр (0,0,0.4), длинная ось по Z, длина 3.6, ширина 1.1, верх сиденья Y=1.55
--     (модель "HorseBench", деталь "SeatTop" — верхняя плоскость сиденья);
--   * две гантельные стойки ближе к камере (z≈+1.5…+6.4): +X — x∈[4.2,15.5], −X — x∈[−2.6,−14],
--     внешние концы чуть ближе к камере (поворот ±10°), лёгкие гантели у внутренних концов;
--   * перегородка с зеркалом на z=8 (+X, слева в кадре) и перегородка с колонной/принтами на z=10.8 (−X);
--     между ними коридор |x|<7 вглубь до z=36 (силовая рама, кроссовер, стойка блинов);
--   * за зеркалом — «зазеркалье» (x∈[8,20], z∈[8,18]): отражённая стойка, потолок, стена — зеркало
--     полупрозрачное и «показывает отражение»;
--   * статисты стоят перед стойками: z≈−1…+2.5 (на полу ничего нет).

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
	floor = hex("08080b"),
	floorSeam = hex("040405"),
	ceilingBack = hex("0c0a0c"),
	woods = { hex("6f5345"), hex("735749"), hex("6b4f42"), hex("77594a"), hex("705446") },
	steel = hex("1e1e23"),
	steelDark = hex("141418"),
	chrome = hex("c4c8d0"),
	chromeDull = hex("7d8089"),
	rubber = hex("131419"),
	rubberCap = hex("2e2e35"),
	leather = hex("0e0d10"),
	neonPurple = hex("5c34ff"),
	neonViolet = hex("5430ff"),
	neonMagenta = hex("cf5cff"),
	neonOrange = hex("ff6a24"),
	neonYellow = hex("ffc94d"),
	lamp = hex("fff0d8"),
	mirror = hex("e2dcee"),
	mirrorDark = hex("2c2833"),
	frame = hex("101014"),
}

local LIGHT_WARM = Color3.fromRGB(255, 222, 186)
local LIGHT_AMBER = Color3.fromRGB(255, 186, 120)
local LIGHT_PURPLE = Color3.fromRGB(196, 108, 246)
local LIGHT_MAGENTA = Color3.fromRGB(232, 96, 255)
local LIGHT_ORANGE = Color3.fromRGB(255, 120, 50)
local LIGHT_WASH = Color3.fromRGB(248, 178, 212)

-- Детерминированный псевдослучай (сборка всегда одинакова).
local seed = 20261019
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local ROOM_W = 20 -- полуширина зала
local Z_FRONT = -26
local CEIL = 12
local Z_BAY = 8 -- перегородка с зеркалом (+X, слева в кадре S10)
local BAY_T = 0.3 -- её толщина (тонкая — у проёма зеркала нет заметного «тоннеля»)
local Z_BAY_R = 10.8 -- перегородка справа в кадре (−X): глубже, чтобы фиолетовая трубка шла перед ней
local Z_MIRROR = Z_BAY + 10 -- дальняя стена «зазеркалья»
local ANNEX_W = 7 -- полуширина коридора
local ANNEX_Z = 36 -- дальняя стена коридора
local HORSE_Z = -1.25 -- таз коня в S10 (HZ) — сюда целятся ключевой/контровой/заполняющий
local RACK_Z = 3.5 -- центр гантельных стоек по глубине
local MIR_X0, MIR_X1, MIR_Y0, MIR_Y1 = 14.3, 19.8, 0.55, 11.3 -- проём зеркала в перегородке

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
	-- Стена-параллелепипед по границам.
	local function slab(x0, x1, y0, y1, z0, z1, name, color, material)
		return box(V((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), V(x1 - x0, y1 - y0, z1 - z0), color or C.wall, material or "Plaster", nil, { name = name })
	end

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
	-- пол (верх Y=0) под залом, «зазеркальем» и коридором — сплошная тёмная резина
	box(V(0, -0.5, zMid), V(2 * W + 2, 1, zLen + 2), C.floor, "Rubber", nil, { name = "Floor" })
	-- швы резиновых плит — только у входа (в кадре S10 пол без рисунка)
	local SEAM_Z = -9
	for z = Z_FRONT + 4, SEAM_Z, 4 do
		box(V(0, 0.011, z), V(2 * W - 0.2, 0.022, 0.08), C.floorSeam, "Rubber", nil, { name = "FloorSeam", castShadow = false })
	end
	for x = -W + 4, W - 4, 4 do
		box(V(x, 0.005, (Z_FRONT + SEAM_Z) / 2), V(0.08, 0.01, SEAM_Z - Z_FRONT - 0.2), C.floorSeam, "Rubber", nil, { name = "FloorSeam", castShadow = false })
	end
	-- стены зала
	local wallH = CEIL + 0.3
	slab(W, W + 1, 0, wallH, Z_FRONT - 1, Z_MIRROR + 1, "WallLeftPlusX")
	slab(-W - 1, -W, 0, wallH, Z_FRONT - 1, Z_BAY_R + 1, "WallRightMinusX")
	slab(-W, W, 0, wallH, Z_FRONT - 1, Z_FRONT, "WallFront")
	-- перегородка +X с проёмом под зеркало
	local zb0, zb1 = Z_BAY, Z_BAY + BAY_T
	slab(ANNEX_W, MIR_X0, 0, wallH, zb0, zb1, "WallBay")
	slab(MIR_X1, W, 0, wallH, zb0, zb1, "WallBay")
	slab(MIR_X0, MIR_X1, MIR_Y1, wallH, zb0, zb1, "WallBay")
	slab(MIR_X0, MIR_X1, 0, MIR_Y0, zb0, zb1, "WallBay")
	-- перегородка −X
	slab(-W, -ANNEX_W, 0, wallH, Z_BAY_R, Z_BAY_R + 1, "WallBayR")
	-- стены коридора и его дальняя стена
	slab(ANNEX_W, ANNEX_W + 1, 0, wallH, zb1, ANNEX_Z, "WallAnnex")
	slab(-ANNEX_W - 1, -ANNEX_W, 0, wallH, Z_BAY_R + 1, ANNEX_Z, "WallAnnex")
	slab(-ANNEX_W - 1, ANNEX_W + 1, 0, wallH, ANNEX_Z, ANNEX_Z + 1, "WallAnnexFar")
	-- дальняя стена «зазеркалья»
	slab(ANNEX_W + 1, W, 0, wallH, Z_MIRROR, Z_MIRROR + 1, "MirrorRoomWall")
	-- пилястры по краям коридора
	box(V(ANNEX_W + 0.25, wallH / 2, Z_BAY - 0.2), V(1.1, wallH, 0.44), C.wallShade, "Plaster", nil, { name = "OpeningPilaster" })
	box(V(-ANNEX_W - 0.25, wallH / 2, Z_BAY_R - 0.2), V(1.1, wallH, 0.44), C.wallShade, "Plaster", nil, { name = "OpeningPilaster" })
	-- плинтусы
	local SK_H, SK_T = 0.38, 0.07
	local function skirt(x0, x1, z0, z1)
		slab(x0, x1, 0, SK_H, z0, z1, "Skirting", C.skirting, "SmoothPlastic")
	end
	skirt(W - SK_T, W, Z_FRONT, Z_MIRROR)
	skirt(-W, -W + SK_T, Z_FRONT, Z_BAY_R)
	skirt(-W + 0.1, W - 0.1, Z_FRONT, Z_FRONT + SK_T)
	skirt(ANNEX_W + 0.82, W - 0.1, Z_BAY - SK_T, Z_BAY)
	skirt(-W + 0.1, -ANNEX_W - 0.82, Z_BAY_R - SK_T, Z_BAY_R)
	skirt(ANNEX_W - SK_T, ANNEX_W, zb1, ANNEX_Z - 0.1)
	skirt(-ANNEX_W, -ANNEX_W + SK_T, Z_BAY_R + 1, ANNEX_Z - 0.1)
	skirt(-ANNEX_W + 0.1, ANNEX_W - 0.1, ANNEX_Z - SK_T, ANNEX_Z)
	skirt(ANNEX_W + 1.1, W - 0.1, Z_MIRROR - SK_T, Z_MIRROR)

	---------------------------------------------------------------- 2. Потолок: чёрная подложка + узкие деревянные рейки
	group("Ceiling")
	box(V(0, CEIL + 0.6, zMid), V(2 * W + 2, 0.8, zLen + 2), C.ceilingBack, "SmoothPlastic", nil, { name = "CeilingBacking" })
	do
		local plankW, gap = 0.46, 0.05
		local z = Z_FRONT + 0.3
		while z + plankW <= ANNEX_Z - 0.3 do
			local zc = z + plankW / 2
			-- границы ряда: зал / «зазеркалье» слева в кадре / коридор
			local xMax = if zc < Z_MIRROR - 0.3 then W - 0.3 else ANNEX_W - 0.3
			local xMin = if zc < Z_BAY_R - 0.3 then -W + 0.3 else -ANNEX_W + 0.3
			local near = zc < -10 -- у входа (вне кадра S10) доски длиннее — экономия деталей
			local x = xMin
			local first = true
			while x < xMax - 0.01 do
				local segLen = if near then 13 + rnd() * 6 else 6 + rnd() * 4
				if first then
					segLen = 1 + rnd() * 6
					first = false
				end
				if xMax - (x + segLen) < 2.5 then
					segLen = xMax - x
				end
				local col = C.woods[1 + math.floor(rnd() * #C.woods)]
				local dy = math.floor(rnd() * 3) * 0.006 -- рейки не идеально в одной плоскости
				local x1 = x + segLen
				local inner0 = if x > xMin + 0.01 then 0.025 else 0
				local inner1 = if x1 < xMax - 0.01 then 0.025 else 0
				local len = (x1 - inner1) - (x + inner0)
				box(V((x + inner0 + x1 - inner1) / 2, CEIL + 0.09 + dy, zc), V(len, 0.18, plankW), col, "Wood", nil, { name = "CeilingPlank" })
				x = x1
			end
			z += plankW + gap
		end
	end

	---------------------------------------------------------------- 3. Неон под потолком
	group("Neon")
	local NEON_Y = CEIL - 0.42
	local function neon(a, b, color, lightColor, opts)
		opts = opts or {}
		local d = opts.d or 0.15
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
			B:light(holder, "SurfaceLight", { Face = "Bottom", Color = lightColor, Brightness = opts.down or 1.3, Range = opts.range or 12, Angle = 150, Shadows = false })
			B:light(holder, "SurfaceLight", { Face = "Top", Color = lightColor, Brightness = opts.up or 0.85, Range = 5, Angle = 170, Shadows = false })
		end
		return tube
	end
	local Y = NEON_Y
	-- главный зигзаг (как в клипе): вершина в устье коридора, лучи к ближним углам зала, оранжевый — вглубь
	local apex = V(-1.25, Y, 13.2)
	neon(V(19.2, Y, -6.45), apex, C.neonPurple, LIGHT_PURPLE, { down = 1.05 })
	neon(V(-19.2, Y, 3.43), apex, C.neonViolet, LIGHT_PURPLE, { down = 1.2, up = 0.6 })
	neon(apex, V(-6.6, Y, 20.1), C.neonOrange, LIGHT_ORANGE, { down = 1.2 })
	-- ближняя часть зала (видна, когда камера смотрит вверх/назад)
	neon(V(19.2, Y, -7.6), V(-19.2, Y, -21.5), C.neonMagenta, LIGHT_MAGENTA, { down = 1.2 })
	neon(V(-19.2, Y, 3.2), V(-6, Y, -9), C.neonMagenta, LIGHT_MAGENTA, { down = 0.9, range = 10 })
	-- жёлтая наклонная полоса на перегородке слева от зеркала (в клипе u≈0.19–0.26)
	rod(V(10.95, CEIL - 0.06, Z_BAY - 0.1), V(8.8, 6.4, Z_BAY - 0.1), 0.14, C.neonYellow, "Neon", { name = "NeonAccent", castShadow = false, canQuery = false })
	emitter(V(9.9, 9.2, Z_BAY - 0.35), V(9.9, 9.2, 0), "SurfaceLight", { Color = Color3.fromRGB(255, 200, 90), Brightness = 1.4, Range = 8, Angle = 170 })

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
	local TRACK_Y = CEIL - 0.6
	local yb = TRACK_Y - 0.045
	-- прямоугольная рама трека за конём (в клипе — над его головой, u≈0.46–0.74, v≈0.04–0.09)
	local x0, x1, z0, z1 = -6.6, 2.2, 5.7, 7.5
	do
		local c00, c10, c11, c01 = V(x0, TRACK_Y, z0), V(x1, TRACK_Y, z0), V(x1, TRACK_Y, z1), V(x0, TRACK_Y, z1)
		trackRail(c00 - V(0.07, 0, 0), c10 + V(0.07, 0, 0), CEIL)
		trackRail(c01 - V(0.07, 0, 0), c11 + V(0.07, 0, 0), CEIL)
		trackRail(c00 + V(0, 0, 0.07), c01 - V(0, 0, 0.07), nil)
		trackRail(c10 + V(0, 0, 0.07), c11 - V(0, 0, 0.07), nil)
		-- передний рельс: контровой на коня (с тенями), статисты
		spot(V(0.6, yb, z0), V(0, 4.6, HORSE_Z + 0.1), { Brightness = 3.2, Range = 20, Angle = 40, Shadows = true, Color = Color3.fromRGB(255, 205, 235) })
		spot(V(-2.2, yb, z0), V(-0.4, 1.8, HORSE_Z + 1.4), { Brightness = 1.2, Range = 16, Angle = 50 })
		spot(V(-5.0, yb, z0), V(-4.5, 3.4, -0.3), { Brightness = 2.0, Range = 20, Angle = 45, Color = Color3.fromRGB(255, 232, 220) })
		-- задний рельс: статистка у стойки, сами стойки
		spot(V(1.2, yb, z1), V(4.1, 3.4, -0.9), { Brightness = 2.0, Range = 20, Angle = 45, Color = Color3.fromRGB(255, 232, 220) })
		spot(V(-1.5, yb, z1), V(9.5, 2.0, RACK_Z - 0.6), { Brightness = 1.7, Range = 22, Angle = 50, Color = Color3.fromRGB(205, 195, 255) })
		spot(V(-4.5, yb, z1), V(-8.5, 2.0, RACK_Z - 0.6), { Brightness = 1.7, Range = 22, Angle = 50, Color = Color3.fromRGB(205, 195, 255) })
	end
	-- линия трека от угла рамы по диагонали вглубь коридора (в клипе уходит вправо-вниз от рамы)
	do
		local a, b = V(x0, TRACK_Y, z1 + 0.07), V(-2.4, TRACK_Y, 34.5)
		trackRail(a, b, CEIL)
		local function on(t)
			local p = a:Lerp(b, t)
			return V(p.X, yb, p.Z)
		end
		spot(on(0.07), V(-6.0, 2.5, 9.5), nil)
		spot(on(0.2), V(-2, 0.5, 18), { Brightness = 1.4, Range = 22, Angle = 60, Color = LIGHT_AMBER })
		spot(on(0.36), V(-3, 2, 24), nil)
		spot(on(0.52), V(2.5, 3.5, 27), { Brightness = 1.5, Range = 22, Angle = 60, Color = LIGHT_AMBER })
		spot(on(0.8), V(0, 4.5, ANNEX_Z), { Brightness = 0.9, Range = 22, Angle = 70, Color = LIGHT_AMBER })
	end
	-- передний трек (поперёк зала над камерой): ключевой и заполняющий на коня
	do
		local z = -5.5
		trackRail(V(-8, TRACK_Y, z), V(8, TRACK_Y, z), CEIL)
		spot(V(2.2, yb, z), V(0, 4.4, HORSE_Z - 0.5), { Brightness = 3.6, Range = 26, Angle = 42, Shadows = true, Color = LIGHT_WARM })
		spot(V(-3.0, yb, z), V(-0.3, 3.4, HORSE_Z - 0.2), { Brightness = 1.4, Range = 24, Angle = 60, Color = Color3.fromRGB(210, 170, 255) })
		spot(V(6.0, yb, z), V(6, 3, -4), nil)
		spot(V(-6.0, yb, z), V(-6, 3, -4), nil)
	end
	-- задний трек у входа (для общих планов)
	do
		local z = -17
		trackRail(V(-10, TRACK_Y, z), V(10, TRACK_Y, z), CEIL)
		spot(V(-6, yb, z), V(-6, 0, -12), { Brightness = 1.4, Range = 20, Angle = 70 })
		spot(V(6, yb, z), V(6, 0, -12), { Brightness = 1.4, Range = 20, Angle = 70 })
	end
	-- фиолетовый контур (как неон в клипе на ушах, гриве, рукаве): сзади-слева в кадре
	emitter(V(3.4, 7.8, 3.2), V(0.4, 4.4, HORSE_Z - 0.3), "SpotLight", { Color = Color3.fromRGB(156, 132, 255), Brightness = 2.4, Range = 14, Angle = 35, Shadows = false })
	-- встроенные даунлайты (чёрное кольцо + светящаяся линза)
	local function downlight(x, z, props)
		cylX(CFrame.new(x, CEIL - 0.03, z) * CFrame.Angles(0, 0, math.pi / 2), 0.06, 0.78, C.steelDark, "SmoothPlastic", { name = "DownlightRing", castShadow = false })
		cylX(CFrame.new(x, CEIL - 0.075, z) * CFrame.Angles(0, 0, math.pi / 2), 0.05, 0.44, C.lamp, "Neon", { name = "DownlightLens", castShadow = false, canQuery = false })
		if props then
			local p = table.clone(props)
			p.Color = p.Color or LIGHT_WARM
			emitter(V(x, CEIL - 0.25, z), V(x, 0, z), "SpotLight", p)
		end
	end
	downlight(-0.2, HORSE_Z + 0.1, { Brightness = 1.5, Range = 18, Angle = 70, Shadows = true })
	downlight(12, -3, { Brightness = 0.9, Range = 18, Angle = 80 })
	downlight(-12, -3, { Brightness = 0.9, Range = 18, Angle = 80 })
	downlight(12, -14, nil)
	downlight(-12, -14, nil)
	downlight(0, 27, { Brightness = 0.7, Range = 16, Angle = 80, Color = LIGHT_AMBER })
	-- мягкая тёпло-сиреневая заливка стен (скрытые споты у потолка, «карниз»)
	for _, wspec in {
		{ V(17.5, CEIL - 0.6, 3), V(19.9, 3, 4), 1.1 },
		{ V(-17.5, CEIL - 0.6, 5), V(-19.9, 3, 8), 1.1 },
		{ V(17.5, CEIL - 0.6, -12), V(19.9, 3, -12), 1.1 },
		{ V(-17.5, CEIL - 0.6, -12), V(-19.9, 3, -12), 1.1 },
		-- перегородки близко к спотам — слабее, иначе белое пятно
		{ V(11.5, CEIL - 0.6, Z_BAY - 6), V(11.5, 3, Z_BAY), 0.45 },
		{ V(-13, CEIL - 0.6, Z_BAY_R - 6), V(-13, 5, Z_BAY_R), 1.3 },
	} do
		emitter(wspec[1], wspec[2], "SpotLight", { Brightness = wspec[3], Range = 18, Angle = 110, Color = LIGHT_WASH })
	end
	-- «зазеркалье» темнее и фиолетовее стены (как зеркало в клипе)
	emitter(V(16.5, CEIL - 0.8, 12), V(19.9, 4, 14.5), "SpotLight", { Brightness = 0.9, Range = 12, Angle = 100, Color = LIGHT_PURPLE })
	-- общая слабая фиолетовая заливка в центре зала
	emitter(V(0, 9, -2), nil, "PointLight", { Brightness = 0.35, Range = 14, Color = LIGHT_PURPLE })
	-- «отражённый» свет под потолком (в Roblox нет переотражений — без него дерево чёрное)
	for _, p in { V(-10, 10.4, -1), V(10, 10.4, -1), V(-10, 10.4, 7), V(8, 10.4, 1.5), V(0, 10.4, -13), V(0, 10.6, -4), V(15, 10.4, 13) } do
		emitter(p, nil, "PointLight", { Brightness = if p.X < -5 then 0.28 else 0.4, Range = 8, Color = Color3.fromRGB(215, 190, 215) })
	end
	-- ровная тёплая подсветка деревянного потолка над рамой трека и вдоль коридора (широкие споты вверх)
	for _, z in { 6.5, 12, 17.5, 23, 28.5, 33 } do
		emitter(V(-0.5, 8.6, z), V(-0.5, CEIL, z), "SpotLight", { Brightness = 0.6, Range = 9, Angle = 120, Color = Color3.fromRGB(232, 192, 176) })
	end
	-- то же над стойками по бокам (там потолок в клипе подсвечен неоном — розовато)
	for _, sp in { { 6.5, 2.0, 0.55 }, { 4.5, 6.4, 0.5 } } do
		emitter(V(sp[1], 8.6, sp[2]), V(sp[1], CEIL, sp[2]), "SpotLight", { Brightness = sp[3], Range = 9, Angle = 120, Color = Color3.fromRGB(226, 172, 212) })
	end

	---------------------------------------------------------------- 5. Скамьи
	local ROT_Z = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра (локальная X детали) -> локальная −Z
	-- Подушка со скруглёнными краями: cf — центр (X — ширина, Z — длина), высота h.
	local function pad(cf, wdt, len, h, color, name)
		local r = h / 2
		local e = h - 0.024 -- кромка на 0.012 ниже плоскости верха/низа — без z-fighting по касательной
		boxCF(cf, V(wdt - h, h, len - h), color, "Leather", { name = name or "Pad" })
		for s = -1, 1, 2 do
			cylX(cf * CFrame.new(s * (wdt / 2 - r), 0, 0) * ROT_Z, len - h, e, color, "Leather", { name = "PadEdge" })
			cylX(cf * CFrame.new(0, 0, s * (len / 2 - r)), wdt - h, e, color, "Leather", { name = "PadEdge" })
			for s2 = -1, 1, 2 do
				P({ cf = cf * CFrame.new(s * (wdt / 2 - r), 0, s2 * (len / 2 - r)), size = V(e, e, e), shape = "Ball", color = color, material = "Leather", name = "PadCorner" })
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
			boxCF(cf * CFrame.new(s * 0.715, 0.18, zR), V(0.08, 0.26, 0.28), C.rubber, "Rubber", { name = "FootCap" })
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
	-- плоская и наклонная скамьи ближе к камере по бокам (вне кадра S10, видны на общих планах)
	local flatCF = CFrame.new(13.4, 0, -4.2) * CFrame.Angles(0, rad(8), 0)
	bench(flatCF, { incline = 0 })
	bench(CFrame.new(-12.8, 0, -4.6) * CFrame.Angles(0, rad(-12), 0), { incline = 32 })
	-- наклонная скамья за правой (−X) стойкой: спинка почти вертикальна и видна над гантелями
	bench(CFrame.new(-10.6, 0, 8.3) * CFrame.Angles(0, rad(-8), 0), { incline = 72 })

	---------------------------------------------------------------- 6. Гантельные стойки
	group("DumbbellRacks")
	local LABEL = hex("4a4752")
	-- размеры гантели по весу: диаметр «блина» d и толщина w
	local function dbSize(kg)
		local t = math.clamp((kg - 2.5) / 47.5, 0, 1)
		return 0.54 + 0.6 * t, 0.26 + 0.36 * t
	end
	-- detail = false — упрощённая гантель для «зазеркалья» (только головы и гриф)
	local function dumbbell(cf, kg, detail)
		local d, w = dbSize(kg)
		local grip = 0.9
		local bev = if detail ~= false then 0.05 else 0 -- наружная «фаска»: ступенька меньшего диаметра на торце
		for s = -1, 1, 2 do
			cylX(cf * CFrame.new(0, 0, s * (grip / 2 + (w - bev) / 2)) * ROT_Z, w - bev, d, C.rubber, "Rubber", { name = "DumbbellHead" })
			if detail ~= false then
				cylX(cf * CFrame.new(0, 0, s * (grip / 2 + w - bev / 2)) * ROT_Z, bev, d - 0.09, C.rubber, "Rubber", { name = "DumbbellHeadBevel" })
				cylX(cf * CFrame.new(0, 0, s * (grip / 2 - 0.035)) * ROT_Z, 0.07, 0.25, C.chromeDull, "Metal", { name = "DumbbellCollar" })
			end
		end
		cylX(cf * ROT_Z, grip + 0.06, 0.15, C.chromeDull, "Metal", { name = "DumbbellHandle" })
		if detail ~= false then
			-- тёмное хромированное кольцо-торец с едва заметной цифрой (в клипе головы читаются как чёрная резина)
			local cap = cylX(cf * CFrame.new(0, 0, -(grip / 2 + w) - 0.005) * ROT_Z, 0.03, d * 0.58, C.rubberCap, "Metal", { name = "DumbbellCap" })
			local txt = if kg % 1 == 0 then string.format("%d", kg) else string.format("%.1f", kg)
			label(cap, "Right", txt, LABEL, 0.62, 0.3)
		end
		return d
	end
	local TILT = -14
	local TAN_TILT = math.tan(rad(-TILT))
	local TRAYS = { { y = 0.74, z = -0.92 }, { y = 2.26, z = 0.86 } } -- нижний (передний) и верхний (задний) лотки
	local TRAY_D = 1.9
	-- Стойка: xIn — внутренний конец (лёгкие гантели), xOut — внешний (тяжёлые), центр по глубине zc,
	-- yawDeg — поворот вокруг Y; tiers — { {kg...}, {kg...} } (нижний, верхний); missing — {[ярус] = номер пары}.
	-- mir = { z = плоскость зеркала, xMin = строить только то, что видно в зеркале } — отражённая копия.
	local function rack(xIn, xOut, zc, yawDeg, tiers, missing, mir)
		local L = math.abs(xOut - xIn)
		local xm = (xIn + xOut) / 2
		local s = if xOut > xIn then 1 else -1 -- шаг от внутреннего конца к внешнему (локальная X = мировая X без поворота)
		local yaw = rad(yawDeg)
		local rcf, mx
		if mir then
			-- отражение относительно плоскости z = mir.z: поворот на π−yaw и зеркальный X
			rcf = CFrame.new(xm, 0, 2 * mir.z - zc) * CFrame.Angles(0, math.pi - yaw, 0)
			mx = -1
		else
			rcf = CFrame.new(xm, 0, zc) * CFrame.Angles(0, yaw, 0)
			mx = 1
		end
		local function vis(lx)
			return not (mir and mir.xMin) or (xm + lx * math.cos(yaw)) >= mir.xMin
		end
		local trayCFs = {}
		for i, t in TRAYS do
			trayCFs[i] = rcf * CFrame.new(0, t.y, t.z) * CFrame.Angles(rad(TILT), 0, 0)
		end
		for ti, tcf in trayCFs do
			boxCF(tcf * CFrame.new(0, -0.025, 0), V(L, 0.05, TRAY_D), C.steelDark, "Metal", { name = "RackTray" })
			boxCF(tcf * CFrame.new(0, 0.05, -TRAY_D / 2 - 0.03), V(L, 0.2, 0.06), C.steel, "Metal", { name = "RackLip" })
			boxCF(tcf * CFrame.new(0, 0.03, TRAY_D / 2 + 0.03), V(L, 0.16, 0.06), C.steel, "Metal", { name = "RackLip" })
			-- гантели парами, от лёгких к тяжёлым
			local list = tiers[ti]
			local startX = -s * (L / 2 - 0.3)
			local x = startX
			for pi, kg in list do
				local d = dbSize(kg)
				local pairW = 2 * d + 0.07
				if math.abs(x + s * pairW - startX) > L - 0.6 then
					break
				end
				local skip = missing and missing[ti] == pi
				for k = 0, 1 do
					local cx = x + s * (d / 2 + k * (d + 0.07))
					if not skip and vis(cx) then
						dumbbell(tcf * CFrame.new(mx * cx, d / 2 + 0.002, 0), kg, mir == nil)
					end
				end
				x += s * (pairW + 0.2)
			end
		end
		-- боковые рамы: лыжа, ноги до кронштейнов лотков, кронштейны
		local function armBottom(t, lz)
			return t.y - 0.21 * math.cos(rad(TILT)) + (lz - t.z) * TAN_TILT
		end
		local frames = { { x = -L / 2 + 0.22, mid = true }, { x = L / 2 - 0.22, mid = true } }
		if L > 7 then
			table.insert(frames, { x = 0, mid = false }) -- у средней рамы нет средней ноги (там стоят гантели)
		end
		local lowT, upT = TRAYS[1], TRAYS[2]
		local legs = {
			{ z = lowT.z - 0.8, top = armBottom(lowT, lowT.z - 0.8) + 0.06 },
			{ z = -0.07, top = armBottom(upT, -0.07) + 0.06, mid = true },
			{ z = upT.z + 0.84, top = armBottom(upT, upT.z + 0.84) + 0.06 },
		}
		for _, fr in frames do
			if vis(fr.x) then
				local X = mx * fr.x
				boxCF(rcf * CFrame.new(X, 0.06, -0.03), V(0.16, 0.12, 3.95), C.steel, "Metal", { name = "RackFoot" })
				for sz = -1, 1, 2 do
					boxCF(rcf * CFrame.new(X, 0.065, -0.03 + sz * 2.0), V(0.18, 0.13, 0.08), C.rubber, "Rubber", { name = "RackFootCap" })
				end
				for _, lg in legs do
					if fr.mid or not lg.mid then
						boxCF(rcf * CFrame.new(X, (0.1 + lg.top) / 2, lg.z), V(0.15, lg.top - 0.1, 0.15), C.steel, "Metal", { name = "RackLeg" })
					end
				end
				for _, tcf in trayCFs do
					boxCF(tcf * CFrame.new(X, -0.13, 0), V(0.14, 0.16, TRAY_D + 0.1), C.steel, "Metal", { name = "RackArm" })
				end
			end
		end
	end
	local RACK_PLUS = {
		{ 2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20 },
		{ 20, 22.5, 25, 27.5, 30, 32.5 },
	}
	local RACK_MINUS = {
		{ 22.5, 25, 27.5, 30, 32.5, 35 },
		{ 35, 37.5, 40, 42.5, 45, 50 },
	}
	-- +X (слева в кадре): лёгкие у внутреннего конца, внешний конец повёрнут к камере
	rack(4.2, 15.5, RACK_Z, 10, RACK_PLUS, { [2] = 3 })
	-- −X (справа в кадре): тяжёлые
	rack(-2.6, -14.0, RACK_Z, -10, RACK_MINUS, { [1] = 2 })
	-- отражение +X стойки в зеркале (только то, что видно через проём)
	rack(4.2, 15.5, RACK_Z, 10, RACK_PLUS, { [2] = 3 }, { z = Z_BAY, xMin = 12.6 })

	---------------------------------------------------------------- 7. Стены: зеркало, рамы, доска, колонна, колонка
	group("WallDecor")
	-- Зеркало: полупрозрачное стекло в хромированной раме; за ним — «зазеркалье» (отражённая комната).
	local function mirrorFrame(xa, xb, ya, yb2, z, ft, fd)
		local w, h = xb - xa, yb2 - ya
		local cx, cy = (xa + xb) / 2, (ya + yb2) / 2
		box(V(cx, yb2 + ft / 2, z - fd / 2), V(w + 2 * ft, ft, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		box(V(cx, ya - ft / 2, z - fd / 2), V(w + 2 * ft, ft, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		box(V(xa - ft / 2, cy, z - fd / 2), V(ft, h, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		box(V(xb + ft / 2, cy, z - fd / 2), V(ft, h, fd), C.chrome, "Metal", nil, { name = "MirrorFrame" })
	end
	do
		local w, h = MIR_X1 - MIR_X0, MIR_Y1 - MIR_Y0
		box(V((MIR_X0 + MIR_X1) / 2, (MIR_Y0 + MIR_Y1) / 2, Z_BAY - 0.03), V(w, h, 0.04), C.mirror, "Glass", nil, {
			name = "Mirror",
			transparency = 0.88,
			castShadow = false,
		})
		mirrorFrame(MIR_X0, MIR_X1, MIR_Y0, MIR_Y1, Z_BAY, 0.08, 0.1)
	end
	-- полка вдоль перегородки слева от зеркала (в клипе светлая линия на v≈0.63)
	box(V((ANNEX_W + 0.8 + MIR_X0 - 0.1) / 2, 1.25, Z_BAY - 0.11), V(MIR_X0 - 0.1 - ANNEX_W - 0.8, 0.08, 0.22), C.wallShade, "SmoothPlastic", nil, { name = "WallLedge" })
	-- розетка с вилкой и свисающим проводом (мелочь из кадра)
	box(V(12.9, 3.6, Z_BAY - 0.03), V(0.32, 0.32, 0.06), hex("e8e6ea"), "SmoothPlastic", nil, { name = "Socket" })
	box(V(12.9, 3.6, Z_BAY - 0.09), V(0.12, 0.16, 0.08), C.frame, "SmoothPlastic", nil, { name = "Plug" })
	rod(V(12.9, 3.5, Z_BAY - 0.1), V(13.05, 1.3, Z_BAY - 0.08), 0.03, C.frame, "SmoothPlastic", { name = "PlugCable", castShadow = false })
	-- зеркало на боковой стене +X (длинное, у камеры)
	do
		local x = W
		box(V(x - 0.03, 5.2, -2), V(0.04, 6.6, 16), C.mirror, "Glass", nil, { name = "SideMirror", reflectance = 0.07 })
		for _, zz in { -10.04, 6.04 } do
			box(V(x - 0.05, 5.2, zz), V(0.1, 6.74, 0.07), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		end
		for _, yy in { 1.865, 8.535 } do
			box(V(x - 0.05, yy, -2), V(0.1, 0.07, 16.15), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		end
	end
	-- отражение бокового зеркала в «зазеркалье» (перспективные линии рамы делают отражение читаемым)
	do
		local x, za, zb2 = W, 2 * Z_BAY - 6.04, Z_MIRROR
		box(V(x - 0.03, 5.2, (za + zb2) / 2), V(0.04, 6.6, zb2 - za), C.mirror, "Glass", nil, { name = "SideMirror", reflectance = 0.07 })
		box(V(x - 0.05, 5.2, za), V(0.1, 6.74, 0.07), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		for _, yy in { 1.865, 8.535 } do
			box(V(x - 0.05, yy, (za + zb2) / 2 - 0.035), V(0.1, 0.07, zb2 - za + 0.07), C.chrome, "Metal", nil, { name = "MirrorFrame" })
		end
	end
	-- колонна справа в кадре (−X) у перегородки
	local ZR = Z_BAY_R
	box(V(-17.6, wallH / 2, ZR - 0.3), V(1.3, wallH, 0.62), C.wallShade, "Plaster", nil, { name = "Column" })
	-- вертикальная труба-кабель-канал у колонны (как в клипе)
	rod(V(-16.75, 0.02, ZR - 0.14), V(-16.75, CEIL, ZR - 0.14), 0.16, C.wall, "SmoothPlastic", { name = "Conduit" })
	for _, y in { 2.5, 6.5, 10.5 } do
		box(V(-16.75, y, ZR - 0.1), V(0.26, 0.08, 0.2), C.wallShade, "Metal", nil, { name = "ConduitClamp" })
	end
	-- рамы с принтами
	local function frame(cx, cy, w, h, z, art, artMat)
		local ft = 0.08
		box(V(cx, cy, z - 0.02), V(w, h, 0.04), art, artMat or "SmoothPlastic", nil, { name = "Print" })
		box(V(cx, cy + h / 2 + ft / 2, z - 0.05), V(w + 2 * ft, ft, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
		box(V(cx, cy - h / 2 - ft / 2, z - 0.05), V(w + 2 * ft, ft, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
		box(V(cx - w / 2 - ft / 2, cy, z - 0.05), V(ft, h, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
		box(V(cx + w / 2 + ft / 2, cy, z - 0.05), V(ft, h, 0.1), C.frame, "SmoothPlastic", nil, { name = "PictureFrame" })
	end
	-- высокий узкий принт у коридора (в клипе u≈0.79–0.81)
	frame(-10.6, 6.7, 0.95, 2.6, ZR, hex("2a2630"))
	-- принт с силуэтом гантели над тёмной панелью
	frame(-15.1, 7.7, 1.9, 1.5, ZR, hex("2c2431"))
	do
		local z = ZR - 0.05
		box(V(-15.1, 7.7, z), V(1.1, 0.08, 0.02), hex("9d8cab"), "SmoothPlastic", nil, { name = "PrintArt", castShadow = false })
		for s = -1, 1, 2 do
			box(V(-15.1 + s * 0.52, 7.7, z), V(0.12, 0.62, 0.02), hex("9d8cab"), "SmoothPlastic", nil, { name = "PrintArt", castShadow = false })
			box(V(-15.1 + s * 0.38, 7.7, z), V(0.1, 0.42, 0.02), hex("9d8cab"), "SmoothPlastic", nil, { name = "PrintArt", castShadow = false })
		end
	end
	-- тёмное зеркало-панель низко на стене (в клипе тёмный прямоугольник над стойкой справа)
	do
		local xa, xb, ya, yb2 = -16.5, -13.5, 1.3, 5.1
		box(V((xa + xb) / 2, (ya + yb2) / 2, ZR - 0.03), V(xb - xa, yb2 - ya, 0.04), C.mirrorDark, "Glass", nil, { name = "MirrorDark", reflectance = 0.12 })
		mirrorFrame(xa, xb, ya, yb2, ZR, 0.07, 0.09)
		box(V((xa + xb) / 2 + 0.05, 1.12, ZR - 0.11), V(xb - xa + 0.3, 0.08, 0.22), C.wallShade, "SmoothPlastic", nil, { name = "WallLedge" })
	end
	-- высокая чёрная доска со скруглённым верхом, прислонённая к стене (как в клипе), с вертикальной надписью
	do
		local hgt, wdt, th = 6.2, 0.8, 0.12
		local lean = rad(6)
		local base = V(-12.0, 0, ZR - 0.75)
		local bcf = CFrame.new(base) * CFrame.Angles(lean, 0, 0) -- верх отклонён к стене (+Z)
		local board = boxCF(bcf * CFrame.new(0, (hgt - wdt / 2) / 2, 0), V(wdt, hgt - wdt / 2, th), hex("141217"), "SmoothPlastic", { name = "LeaningBoard" })
		cylX(bcf * CFrame.new(0, hgt - wdt / 2, 0) * ROT_Z, th, wdt, hex("141217"), "SmoothPlastic", { name = "LeaningBoardTop" })
		local g = label(board, "Front", "AURA FARMER", Color3.fromRGB(225, 220, 230), 0.9, 0.12)
		local t = g:FindFirstChildWhichIsA("TextLabel")
		t.Size = roblox.UDim2.fromScale(4.6, 0.16)
		t.Rotation = -90
	end
	-- напольная колонка: низ кадра слева, у ног рыжей статистки, развёрнута к камере
	do
		local cf = CFrame.new(7.0, 0, -1.2) * CFrame.Angles(0, rad(40), 0)
		local hgt, bw, bd = 1.2, 0.95, 0.8
		boxCF(cf * CFrame.new(0, 0.05 + hgt / 2, 0), V(bw, hgt, bd), hex("0d0d10"), "SmoothPlastic", { name = "Speaker" })
		for s = -1, 1, 2 do
			boxCF(cf * CFrame.new(s * 0.36, 0.025, 0), V(0.14, 0.05, 0.7), C.rubber, "Rubber", { name = "SpeakerFoot" })
		end
		local face = cf * CFrame.new(0, 0.05, -bd / 2)
		local function driver(y, d)
			local ccf = face * CFrame.new(0, y, 0) * ROT_Z
			-- ось цилиндра — наружу из передней панели (+X детали = «вперёд» колонки)
			cylX(ccf * CFrame.new(0.02, 0, 0), 0.06, d, hex("2a2a31"), "SmoothPlastic", { name = "SpeakerRing" })
			cylX(ccf * CFrame.new(0.035, 0, 0), 0.04, d * 0.8, hex("060607"), "Fabric", { name = "SpeakerCone" })
			P({ cf = ccf * CFrame.new(0.05, 0, 0), size = V(0.1, d * 0.32, d * 0.32), mesh = "Sphere", color = hex("24242a"), material = "SmoothPlastic", name = "SpeakerDustCap" })
		end
		driver(0.45, 0.62)
		driver(0.95, 0.24)
		local led = boxCF(face * CFrame.new(0.33, 1.1, -0.012), V(0.04, 0.04, 0.03), Color3.fromRGB(150, 24, 24), "Neon", { name = "SpeakerLed", castShadow = false })
		led.CanQuery = false
	end
	-- гири вдоль боковой стены +X
	do
		local kgs = { 8, 12, 16, 16, 20, 24, 24, 28, 32 }
		local z = -13.5
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

	---------------------------------------------------------------- 8. Коридор: силовая рама, кроссовер, блины
	group("Annex")
	-- деревянный помост под рамой
	box(V(4.0, 0.06, 23.0), V(4.8, 0.12, 7.6), hex("6e5038"), "WoodPlanks", nil, { name = "Platform" })
	for s = -1, 1, 2 do
		box(V(4.0 + s * 1.97, 0.08, 23.0), V(0.94, 0.12, 7.64), hex("1a191e"), "Rubber", nil, { name = "PlatformRubber" })
	end
	-- силовая рама: стойки 0.28, гриф вдоль Z
	do
		local xs, zs = { 2.4, 5.7 }, { 21.0, 25.0 }
		local Ht = 8.2
		for _, x in xs do
			for _, z in zs do
				box(V(x, 0.12 + Ht / 2, z), V(0.28, Ht, 0.28), C.steel, "Metal", nil, { name = "RackUpright" })
			end
			box(V(x, 0.18, 23.0), V(0.24, 0.12, 4.2), C.steel, "Metal", nil, { name = "RackBase" })
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
				box(V(x, 4.19, z), V(0.26, 8.38, 0.26), C.steel, "Metal", nil, { name = "CrossoverUpright" })
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
	-- большая картина на дальней стене коридора (тёплое пятно в глубине кадра)
	frame(0, 9.6, 4.2, 1.5, ANNEX_Z, hex("b98a5a"), "SmoothPlastic")
	-- тёплые бра на дальней стене
	for s = -1, 1, 2 do
		local x = s * 2.9
		cylX(CFrame.new(x, 6.2, ANNEX_Z - 0.1) * ROT_Z, 0.2, 0.5, C.frame, "SmoothPlastic", { name = "Sconce", castShadow = false })
		emitter(V(x, 6.4, ANNEX_Z - 0.35), V(x, 12, ANNEX_Z - 0.6), "SpotLight", { Brightness = 0.9, Range = 9, Angle = 90, Color = LIGHT_AMBER })
		emitter(V(x, 6.0, ANNEX_Z - 0.35), V(x, 0, ANNEX_Z - 0.6), "SpotLight", { Brightness = 0.7, Range = 9, Angle = 90, Color = LIGHT_AMBER })
	end

	---------------------------------------------------------------- 9. Мелочи: вход, вывеска, вещи на полу, потолочные колонки
	group("Props")
	-- входная двустворчатая дверь в передней стене (видна только на обратных ракурсах)
	do
		local z = Z_FRONT
		local dw, dh = 2.0, 7.4
		box(V(0, dh / 2 + 0.1, z + 0.06), V(2 * dw + 0.5, dh + 0.4, 0.12), C.frame, "Metal", nil, { name = "DoorFrame" })
		for s2 = -1, 1, 2 do
			box(V(s2 * (dw / 2 + 0.03), dh / 2 + 0.05, z + 0.15), V(dw - 0.04, dh - 0.1, 0.1), hex("26242b"), "Metal", nil, { name = "Door" })
			box(V(s2 * (dw / 2 + 0.03), dh * 0.62, z + 0.205), V(dw - 0.6, dh * 0.42, 0.02), hex("3a3446"), "Glass", nil, { name = "DoorGlass", reflectance = 0.15 })
			rod(V(s2 * 0.25, 3.3, z + 0.32), V(s2 * (dw - 0.2), 3.3, z + 0.32), 0.08, C.chrome, "Metal", { name = "PushBar" })
		end
		local sign = box(V(0, dh + 1.0, z + 0.1), V(1.4, 0.5, 0.12), Color3.fromRGB(40, 220, 110), "Neon", nil, { name = "ExitSign", castShadow = false })
		label(sign, "Back", "EXIT", Color3.fromRGB(245, 255, 248), 0.9, 0.8)
		-- огнетушитель
		local ex = V(-4.2, 0, z + 0.4)
		rod(ex + V(0, 0.15, 0), ex + V(0, 1.55, 0), 0.42, Color3.fromRGB(190, 20, 24), "SmoothPlastic", { name = "Extinguisher" })
		ball(ex + V(0, 1.6, 0), 0.4, Color3.fromRGB(190, 20, 24), "SmoothPlastic", { name = "Extinguisher" })
		rod(ex + V(0, 1.75, 0), ex + V(0, 1.95, 0), 0.12, C.frame, "Metal", { name = "ExtinguisherValve" })
	end
	-- неоновая вывеска на боковой стене −X (лирика плана)
	do
		local x = -W + 0.06
		local panel = box(V(x, 7.6, -4.0), V(0.1, 2.0, 7.4), hex("0a090c"), "SmoothPlastic", nil, { name = "SignPanel" })
		local g = label(panel, "Right", "no stress", Color3.fromRGB(255, 110, 230), 0.94, 0.86)
		g.LightInfluence = 0
		local t = g:FindFirstChildWhichIsA("TextLabel")
		t.FontFace = roblox.Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold)
		emitter(V(x + 1.2, 7.6, -4.0), V(0, 7.6, -4.0), "PointLight", { Brightness = 0.8, Range = 9, Color = Color3.fromRGB(255, 90, 220) })
		-- трубка-подчёркивание
		rod(V(x + 0.12, 6.45, -6.8), V(x + 0.12, 6.45, -1.2), 0.09, C.neonMagenta, "Neon", { name = "NeonAccent", castShadow = false, canQuery = false })
	end
	-- потолочные колонки по углам
	for _, pp in { V(-18.6, 0, -24.4), V(18.6, 0, -24.4), V(-18.6, 0, Z_BAY_R - 0.7), V(18.6, 0, Z_BAY - 0.7) } do
		local at = V(pp.X, CEIL - 0.75, pp.Z)
		local cf = look(at, V(pp.X * 0.4, 4, pp.Z * 0.4 - 4))
		boxCF(cf, V(0.75, 1.1, 0.7), hex("101013"), "SmoothPlastic", { name = "WallSpeaker" })
		boxCF(cf * CFrame.new(0, 0, -0.36), V(0.62, 0.95, 0.03), hex("1c1c21"), "Fabric", { name = "WallSpeakerGrille" })
		boxCF(CFrame.new(pp.X, CEIL - 0.1, pp.Z), V(0.12, 0.2, 0.12), C.frame, "Metal", { name = "WallSpeakerMount" })
	end
	-- вещи на полу (вне зон статистов и стоек): полотенце, бутылка, ролик, коврик, гантели
	do
		-- полотенце на плоской скамье (+X)
		boxCF(flatCF * CFrame.new(0, 1.565, 0.55), V(1.16, 0.03, 0.7), hex("d9d2e6"), "Fabric", { name = "Towel" })
		for s2 = -1, 1, 2 do
			boxCF(flatCF * CFrame.new(s2 * 0.6, 1.35, 0.55) * CFrame.Angles(0, 0, rad(s2 * 8)), V(0.03, 0.42, 0.7), hex("d9d2e6"), "Fabric", { name = "Towel" })
		end
		-- шейкер у наклонной скамьи за −X стойкой
		local sp = V(-9.0, 0, 7.3)
		rod(sp + V(0, 0.005, 0), sp + V(0, 0.62, 0), 0.32, hex("1b1b20"), "SmoothPlastic", { name = "Shaker" })
		rod(sp + V(0, 0.62, 0), sp + V(0, 0.78, 0), 0.33, Color3.fromRGB(150, 70, 255), "SmoothPlastic", { name = "ShakerLid" })
		-- пенный ролик и свёрнутый коврик за +X стойкой (перед перегородкой)
		rod(V(16.4, 0.29, 7.0), V(18.2, 0.29, 7.25), 0.56, hex("2a2338"), "Fabric", { name = "FoamRoller" })
		rod(V(8.6, 0.31, 7.0), V(10.8, 0.31, 7.0), 0.62, hex("3b2a52"), "Rubber", { name = "YogaMat" })
		rod(V(8.58, 0.31, 7.0), V(8.6, 0.31, 7.0), 0.3, hex("241a33"), "Rubber", { name = "YogaMatCore" })
		-- пара гантелей на полу у плоской скамьи (как будто только что положили)
		local dcf = CFrame.new(11.2, 0, -1.8) * CFrame.Angles(0, rad(70), 0)
		local d1 = dbSize(17.5)
		dumbbell(dcf * CFrame.new(-0.45, d1 / 2, 0), 17.5)
		dumbbell(dcf * CFrame.new(0.45, d1 / 2, 0.1) * CFrame.Angles(0, rad(-12), 0), 17.5)
	end
end
