--!nocheck
-- Человек в стиле Roblox: блочное R15-тело с мягкими фасками (скруглённые рёбра), кисти с пальцами,
-- «динамическая» лепная голова (череп + лицо + челюсть + щёки из эллипсоидов), глаза-«миндаль» (белок, крупная
-- радужка, зрачок, блики, линия ресниц) на суставах взгляда, верхние веки (моргание) и нижние веки (улыбка —
-- глаза-дуги «◠»), брови на суставах, нос, губы. Рот — настоящий проём: при раскрытии челюсти за губами видна
-- тёмная полость, верхние зубы и язык (смех — широкая «D»: полоса верхних зубов, нижняя губа дугой; «О» — овал).
-- Щетина облегает лицо: «оболочки» кожи (копии эллипсоидов лица/черепа/челюсти, выступающие на 0..0.02 по одну
-- сторону плоскости) — чистая диагональ от бакенбарды к уголку рта в два тона; усы — тонкий слой. Одежда и причёски
-- собираются из примитивов по опциям (см. DEFAULTS). Использование: require("./Human")(opts).
--
-- КОНТРАКТ ДЛЯ АНИМАТОРОВ
--   Пальцы: R15 + Right/Left Index1/2, Middle1/2, Ring1/2, Pinky1/2, Thumb1/2 (rHand/lHand в ключах; по умолчанию "relaxed").
--   Доп. суставы головы: Jaw (нижняя челюсть, середина нижней губы, зубы, язык, подбородок), Mouth (полость рта и
--     верхние зубы), UpperLip (середина верхней губы + усы), RightMouth/LeftMouth (уголки: края верхней губы),
--     RightLowerLip/LeftLowerLip (края нижней губы; дети головы, опора — в уголке рта), RightCornerSkin/
--     LeftCornerSkin (кожа у уголков; дети LowerLip), RightCheek/LeftCheek (щёки), RightBrow/LeftBrow,
--     RightLid/LeftLid (верхние веки), RightLowerLid/LeftLowerLid, RightEye/LeftEye (взгляд), Glasses (если есть очки).
--   Пропорции (·height): ankleY 0.28, kneeY 1.28, hipY 2.45, pelvisY 2.65, waistY 2.9, shoulderY 4.42, neckY 4.62,
--     плечо 1.22, предплечье 1.1 (≈4.7 головы ростом). Центр головы (поза покоя): y = neckY + 0.92·height
--     (= 5.54·height), переносица очков — (0, y, f = 0.675). Удобно: rig.headCenter (Vector3, char space) и
--     rig.glassesHome (опора сустава Glasses на носу).
--   Лицевые каналы (face = {...}):
--     jaw 0..1 (рот открыт), smile 0..1 (улыбка-оскал с верхними зубами: уголки вверх/в стороны, щёки вверх,
--     нижние веки вверх — глаза-дуги), oh 0..1 (губы в «О»), brows -1..1 (обе брови вверх+/вниз-), browR/browL,
--     frown 0..1 (сведённые брови), blink 0..1, squint 0..1, lookX -1..1 (взгляд вправо от персонажа +),
--     lookY -1..1 (вверх +).
--     «Ах!» (awe):  face = { jaw = 0.7, oh = 1, brows = 1 };  смех: face = { jaw = 0.4..0.8, smile = 1, squint = 0.3 }
--     (глаза-серпы «◠» — от smile+squint; blink поверх smile закрывает глаза полностью: для смеха blink = 0).
--     smile без jaw — улыбка с полоской верхних зубов и нижней губой дугой «◡».
--   Очки: joints = { Glasses = { x, y, f, rx, ry, rz } } — смещение от позы покоя (на носу) в осях головы;
--     «спустить на кончик носа»: { y = -0.13, f = 0.05, rx = -13 }. opts.glassesOn = "RightHand"/"LeftHand" — очки в руке.
--     Формы оправ: glasses = "aviator" | "round" | "hex" | "rect".

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local CFrame = roblox.CFrame
local Rig = require("../lib/Rig")

local rad = math.rad
local function v(x, y, z)
	return Vector3.new(x, y, z)
end
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function ang(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end
local function at(x, y, z)
	return CFrame.new(x, y, z)
end
local BLACK = rgb(0, 0, 0)
local WHITE = rgb(255, 255, 255)

local DEFAULTS = {
	-- тело
	height = 1.0,
	build = 1.0,
	female = false,
	skin = rgb(226, 166, 132),
	rosy = 0.3, -- «загар»/румянец на щеках, носу, ушах (0..1)
	-- лицо
	eyes = rgb(80, 64, 50), -- радужка
	lips = rgb(186, 106, 98),
	brows = nil, -- цвет бровей (по умолчанию темнее волос)
	browThick = 1.0,
	lashes = false, -- выразительные ресницы (женские)
	beard = nil, -- Color3 короткой бороды-щетины (челюсть, подбородок, щёки, усы)
	beardAmount = 0.52, -- густота щетины 0..1
	nose = 1.0, -- масштаб носа
	-- волосы
	hair = rgb(60, 42, 30),
	hairStyle = "quiff", -- "quiff" | "shag" | "curls" | "bun" | "crop" | "bob" | nil
	hairHighlight = nil, -- светлые пряди у лица (shag)
	hairCrown = nil, -- цвет макушки и чёлки (shag; двухтон)
	-- одежда
	top = rgb(242, 241, 237),
	topStyle = "tank", -- "tank" (майка) | "crop" (кроп-топ с высоким вырезом) | "tee" (футболка) | nil
	scoop = 0.5, -- глубина выреза майки спереди
	armhole = 0.5, -- глубина пройм майки (0 — узкие, 1 — до пояса)
	bottom = rgb(30, 32, 40),
	bottomStyle = "shorts", -- "shorts" | "baggy" (широкие до середины икры) | "track" (спортивные с лампасами) | "leggings"
	stripe = nil, -- Color3 лампасов (track)
	stitch = nil, -- Color3 контрастной строчки
	roses = nil, -- Color3 принта-роз (baggy)
	shoes = "sneakers", -- "sneakers" | "barefoot"
	shoeColor = rgb(242, 242, 240),
	shoeAccent = nil, -- полоса на боку кроссовка
	sole = rgb(246, 246, 244),
	socks = nil, -- Color3 носков
	-- аксессуары
	necklaces = nil, -- { { kind = "cord"|"chain"|"beads", color, len = 0..1, pendant = "coin"|"drop"|nil, choker = bool, thin = bool } }
	earrings = nil, -- "hoop" | "stud"
	earringColor = rgb(214, 214, 220),
	bracelets = nil, -- { right = { Color3, ... }, left = { ... } }
	watch = nil, -- "left" | "right": металлический браслет-часы
	rings = nil, -- Color3 колец
	glasses = nil, -- "aviator" | "round" | "hex" | "rect"
	glassesFrame = rgb(204, 168, 92),
	glassesLens = rgb(30, 52, 40),
	glassesLensTransparency = 0,
	glassesOn = "Head", -- "Head" | "RightHand" | "LeftHand"
}

return function(opts)
	local o = table.clone(DEFAULTS)
	for k, val in opts or {} do
		o[k] = val
	end
	local h = o.height
	local bw = o.build
	local fem = o.female

	-- ===== Габариты тела =====
	local tw = (o.torsoW or (if fem then 1.74 else 2.0)) * bw -- ширина груди
	local td = (o.torsoD or (if fem then 0.9 else 0.98)) * bw
	local aw = (o.armW or (if fem then 0.54 else 0.64)) * bw -- плечо (квадрат)
	local fx = aw * 0.84 -- предплечье: толщина по X
	local fz = aw * 0.9 -- предплечье: ширина по Z
	local lw = (o.legW or (if fem then 0.74 else 0.8)) * bw -- бедро
	local sw = lw * 0.84 -- голень
	local hipX = (if fem then 0.4 else 0.44) * bw
	local pt = (if fem then 0.27 else 0.31) * bw -- толщина ладони
	local pw = (if fem then 0.52 else 0.58) * bw -- ширина ладони
	local fd = (if fem then 0.12 else 0.135) * bw -- толщина пальца

	local rig = Rig.new("Human", {
		hipX = hipX,
		hipY = 2.45 * h,
		kneeY = 1.28 * h,
		ankleY = 0.28 * h,
		footLen = (if fem then 0.92 else 1.02) * bw,
		footFwd = (if fem then 0.6 else 0.66) * bw,
		footW = 0.8,
		pelvisY = 2.65 * h,
		waistY = 2.9 * h,
		neckY = 4.62 * h,
		shoulderX = tw / 2 + aw / 2 + 0.02,
		shoulderY = 4.42 * h,
		upperArm = 1.22 * h,
		lowerArm = 1.1 * h,
		handLen = 0.36 * h * bw,
		handW = pw * 1.06,
		torsoW = tw,
		torsoD = td,
		headH = 1.35,
		fingers = true,
		fingerLen1 = 0.2 * h * bw,
		fingerLen2 = 0.18 * h * bw,
		thumbLen1 = 0.17 * h * bw,
		thumbLen2 = 0.15 * h * bw,
	})
	rig.defaultHand = "relaxed"
	local P = rig.P
	local skin = o.skin
	local rosyC = skin:Lerp(rgb(222, 98, 88), o.rosy)
	local skinShade = skin:Lerp(rgb(150, 70, 60), 0.18)
	local skinDeep = skin:Lerp(rgb(110, 48, 42), 0.3)

	-- ===== Примитивы =====
	local function part(bone, cf, size, color, mat, name, extra)
		local spec = { cf = cf, size = size, color = color, material = mat or "SmoothPlastic", name = name }
		for k, val in extra or {} do
			spec[k] = val
		end
		return rig:part(bone, spec)
	end
	local function ell(bone, cf, size, color, mat, name, extra)
		local spec = { cf = cf, size = size, color = color, material = mat or "SmoothPlastic", name = name, mesh = "Sphere" }
		for k, val in extra or {} do
			spec[k] = val
		end
		return rig:part(bone, spec)
	end
	local function ball(bone, pos, d, color, mat, name)
		return rig:part(bone, { cf = CFrame.new(pos), size = v(d, d, d), color = color, material = mat or "SmoothPlastic", name = name, shape = "Ball" })
	end
	-- цилиндр с осью Y
	local function cylY(bone, cf, len, d, color, mat, name)
		return rig:part(bone, { cf = cf * ang(0, 0, 90), size = v(len, d, d), color = color, material = mat or "SmoothPlastic", name = name, shape = "Cylinder" })
	end
	-- цилиндр (палочка) от точки a до b
	local function stick(bone, a, b, d, color, mat, name)
		local dir = b - a
		local len = dir.Magnitude
		local X = dir.Unit
		local up = if math.abs(X.Y) > 0.95 then v(1, 0, 0) else v(0, 1, 0)
		local Y = (up - X * up:Dot(X)).Unit
		local cf = CFrame.fromMatrix((a + b) / 2, X, Y)
		return rig:part(bone, { cf = cf, size = v(len, d, d), color = color, material = mat or "SmoothPlastic", name = name, shape = "Cylinder" })
	end
	-- блок со скруглёнными рёбрами, параллельными локальной оси Y (6 деталей)
	local function rbox(bone, cf, size, r, color, mat, name)
		local sx, sy, sz = size.X, size.Y, size.Z
		r = math.min(r, sx / 2 - 0.005, sz / 2 - 0.005)
		-- внутренние грани блоков чуть утоплены (−0.012): у «вложенных» rbox (пояс поверх таза и т.п.) они не совпадают
		part(bone, cf, v(sx, sy, sz - 2 * r - 0.012), color, mat, name)
		part(bone, cf, v(sx - 2 * r - 0.012, sy - 0.024, sz), color, mat, name)
		for _, cx in { -1, 1 } do
			for _, cz in { -1, 1 } do
				rig:part(bone, {
					cf = cf * at(cx * (sx / 2 - r), 0, cz * (sz / 2 - r)) * ang(0, 0, 90),
					size = v(sy - 0.05, 2 * r, 2 * r),
					color = color,
					material = mat or "SmoothPlastic",
					name = name,
					shape = "Cylinder",
				})
			end
		end
	end
	-- вертикальный rbox от y0 до y1
	local function rboxY(bone, x, y0, y1, z, w, d, r, color, mat, name)
		rbox(bone, at(x, (y0 + y1) / 2, z), v(w, y1 - y0, d), r, color, mat, name)
	end
	-- сужение: n ступеней rbox от (w0, d0) внизу до (w1, d1) вверху
	local function taperY(bone, y0, y1, w0, w1, d0, d1, r, color, mat, name, n)
		for i = 0, n - 1 do
			local u = (i + 0.5) / n
			local ya = y0 + (y1 - y0) * i / n
			local yb = y0 + (y1 - y0) * (i + 1) / n
			rboxY(bone, 0, ya, yb + (if i < n - 1 then 0.012 else 0), 0, w0 + (w1 - w0) * u, d0 + (d1 - d0) * u, r, color, mat, name)
		end
	end
	-- «клин» во фронтальной плоскости (на всю глубину d): закрывает треугольник с прямым углом в (x0, y0),
	-- катетами до x1 и до y1; скос от (x0, y1) к (x1, y0). Сделан повёрнутым блоком (грань — по скосу,
	-- толщина внутрь), лишнее уходит под соседние детали. s — сторона (+1 правая, -1 левая).
	local function slopeXY(bone, s, x0, x1, y0, y1, z, d, color, mat, name)
		local dx, dy = x1 - x0, y1 - y0
		local L = math.sqrt(dx * dx + dy * dy)
		local u = v(s * dx / L, -dy / L, 0)
		local n = v(-s * dy / L, -dx / L, 0)
		local t = dx * dy / L + 0.01
		local mid = v(s * (x0 + x1) / 2, (y0 + y1) / 2, z)
		return part(bone, CFrame.fromMatrix(mid + n * (t / 2), u, n), v(L, t, d), color, mat, name)
	end

	-- ===== Туловище (кожа) =====
	local yW, yN, yH = P.waistY, P.neckY, P.hipY
	local topC = o.top
	local topStyle = o.topStyle
	local chestBot = yW + (yN - yW) * (if fem then 0.52 else 0.36) -- низ грудной клетки
	local waistW = if fem then tw * 0.84 else tw * 0.92
	local hipW = if fem then tw * 0.97 else tw * 0.95
	local cropped = topStyle == "crop"
	local pad = 0.032
	-- верх пояса низа (под майкой/футболкой — ниже: при наклоне корпуса пояс не протыкает ткань)
	local waistTop = yW + (if cropped then 0.1 elseif topStyle then 0.0 else 0.2) * h
	local halfW = tw / 2
	local rT = 0.2 * bw
	rboxY("UpperTorso", 0, chestBot, yN, 0, tw, td, rT, skin, "SmoothPlastic", "Chest")
	rboxY("UpperTorso", 0, yW - 0.2, chestBot + 0.02, 0, waistW, td * 0.92, rT, skin, "SmoothPlastic", "Waist")
	if cropped or not topStyle then
		ell("UpperTorso", at(0, yW + 0.34 * h, -td * 0.45 - 0.006), v(0.06, 0.085, 0.04), skinShade:Lerp(BLACK, 0.3), "SmoothPlastic", "Navel")
		-- лёгкий рельеф живота
		ell("UpperTorso", at(0, yW + 0.52 * h, -td * 0.45 + 0.012), v(waistW * 0.5, 0.5 * h, 0.06), skin, "SmoothPlastic", "Belly")
	end
	-- основание шеи (трапеция) — под вырезом
	ell("UpperTorso", at(0, yN + 0.01, 0.04), v(0.66 * bw, 0.16, td * 0.6), skin, "SmoothPlastic", "NeckBase")
	-- ключицы (видны в вырезе)
	for _, s in { 1, -1 } do
		ell("UpperTorso", at(s * 0.3 * bw, yN - 0.06, -td / 2 + 0.012) * ang(0, 0, s * -12), v(0.42 * bw, 0.06, 0.04), skin, "SmoothPlastic", "Clavicle")
	end

	-- ===== Верх одежды =====
	local D = td + pad -- глубина оболочки верха
	local bustY, bustOut = 0, 0
	if topStyle == "tee" then
		-- футболка: оболочка до плеч, круглый вырез, рукава (см. руки)
		local hem = yW - 0.12
		rboxY("UpperTorso", 0, hem, yN + 0.026, 0, math.max(tw, hipW) + pad, D, rT + pad / 2, topC, "Fabric", "Shirt")
		local fz = -D / 2
		ell("UpperTorso", at(0, yN + 0.004, fz - 0.008), v(0.5 * bw, 0.18, 0.024), skin, "SmoothPlastic", "Neckline")
		ell("UpperTorso", at(0, yN + 0.012, fz - 0.004), v(0.6 * bw, 0.26, 0.026), topC:Lerp(BLACK, 0.12), "SmoothPlastic", "Collar")
		part("UpperTorso", at(0, yN + 0.028, 0.04), v(0.5 * bw, 0.02, td * 0.62), skin, "SmoothPlastic", "NeckTop")
	elseif topStyle == "tank" or topStyle == "crop" then
		-- so — наружный край бретели, si — внутренний (полуширина выреза), ya — низ проймы
		local so, si, ya, scoopF, scoopB, hem
		local ah = o.armhole
		if cropped then
			so, si, ya, scoopF, scoopB = 0.4 * bw, 0.25 * bw, yN - (0.5 + 0.2 * ah) * h, 0.075, 0.1
			hem = chestBot - 0.1
		elseif fem then
			so, si, ya, scoopF, scoopB = 0.52 * bw, 0.31 * bw, yN - (0.55 + 0.35 * ah) * h, o.scoop * 0.85 * h, 0.22 * h
			hem = yW - 0.06 -- навыпуск поверх пояса
		else
			so, si, ya, scoopF, scoopB = 0.6 * bw, 0.35 * bw, yN - (0.62 + 0.45 * ah) * h, o.scoop * h, 0.26 * h
			hem = yW - 0.14 -- навыпуск поверх шорт
		end
		local W = (if fem and cropped then tw else math.max(tw, hipW + 0.07)) + pad
		local Dt = if fem and cropped then D else D + 0.05
		local rS = 0.17 * bw
		-- нижняя оболочка: от подола до проймы. У майки низ (подол до waistY+0.15) — на LowerTorso (едет с бёдрами
		-- при наклоне/посадке), чуть шире верха; выше — на UpperTorso, с нахлёстом внутрь пояска.
		local bandTop = yW + 0.15
		if cropped then
			rboxY("UpperTorso", 0, hem, ya + 0.016, 0, W, Dt, rS, topC, "Fabric", "Shirt")
			-- кант по низу (вровень с телом топа, не «юбкой»)
			rboxY("UpperTorso", 0, hem - 0.045, hem + 0.065, 0, W + 0.012, Dt + 0.012, rS + 0.006, topC:Lerp(BLACK, 0.06), "Fabric", "Hem")
		else
			rboxY("LowerTorso", 0, hem, bandTop, 0, W + 0.012, Dt + 0.012, rS + 0.006, topC, "Fabric", "ShirtLow")
			rboxY("UpperTorso", 0, yW + 0.04, ya + 0.016, 0, W, Dt, rS, topC, "Fabric", "Shirt")
		end
		-- верх: перёд и спина до линии выреза, бретели, проймы (две ступени клиньев — плавная дуга)
		local yS_f, yS_b = yN - scoopF, yN - scoopB
		local dUf = math.min(scoopF * 0.7, si * 0.85)
		local dUb = math.min(scoopB * 0.7, si * 0.85)
		local cYf, cYb = yS_f + dUf, yS_b + dUb -- центры «U»-выреза
		local top = yN + 0.014
		local strapBot = math.min(cYf, cYb) - 0.02
		-- перёд и спина до низа выреза; «U» — из полотна: полосы по бокам выреза + клинья по дуге (как проймы),
		-- в вырезе просто видна кожа груди (клинья чуть утоплены: без совпадающих граней)
		for _, zs in { -1, 1 } do
			local cY = if zs < 0 then cYf else cYb
			local dU = if zs < 0 then dUf else dUb
			local yS = cY - dU
			local zc, dz = zs * Dt / 4, Dt / 2
			part("UpperTorso", at(0, (ya + yS) / 2, zc), v(2 * so, yS - ya, dz), topC, "Fabric", if zs < 0 then "ShirtFront" else "ShirtBack")
			local pts = { v(0, yS, 0), v(si * 0.574, cY - dU * 0.819, 0), v(si * 0.906, cY - dU * 0.423, 0), v(si, cY, 0) }
			for _, sx in { 1, -1 } do
				-- полосы под дугой (стыкуются без нахлёста)
				part("UpperTorso", at(sx * (pts[2].X + so) / 2, (yS + pts[2].Y) / 2, zc), v(so - pts[2].X, pts[2].Y - yS, dz), topC, "Fabric", "ScoopEdge")
				part("UpperTorso", at(sx * (pts[3].X + so) / 2, (pts[2].Y + pts[3].Y) / 2, zc), v(so - pts[3].X, pts[3].Y - pts[2].Y, dz), topC, "Fabric", "ScoopEdge")
				if strapBot > pts[3].Y + 0.005 then
					part("UpperTorso", at(sx * (si + so) / 2, (pts[3].Y + strapBot) / 2, zc), v(so - si, strapBot - pts[3].Y, dz), topC, "Fabric", "ScoopEdge")
				end
				for k = 1, 3 do
					local a, b = pts[k], pts[k + 1]
					-- прямой угол снаружи-снизу (b.X, a.Y): в «зеркальных» координатах (−x), чтобы катеты были положительны
					slopeXY("UpperTorso", -sx, -b.X, -a.X, a.Y, b.Y, zs * (Dt / 4 - 0.003), Dt / 2 - 0.006, topC, "Fabric", "ScoopEdge")
				end
			end
		end
		local edge = W / 2
		local xm = so + (edge - so) * 0.22
		local ym = ya + (top - ya) * 0.42
		for _, s in { 1, -1 } do
			part("UpperTorso", at(s * (si + so) / 2, (strapBot + top) / 2, 0), v(so - si, top - strapBot, Dt), topC, "Fabric", "Strap")
			part("UpperTorso", at(s * (so + xm) / 2, (ya + ym) / 2, 0), v(xm - so, ym - ya, Dt), topC, "Fabric", "Armhole")
			slopeXY("UpperTorso", s, so, xm, ym, top, 0, Dt, topC, "Fabric", "Armhole")
			slopeXY("UpperTorso", s, xm, edge, ya, ym, 0, Dt, topC, "Fabric", "Armhole")
		end
		if not fem then
			-- рубчик майки: тонкие вертикальные рёбра на переде (до выреза / бретелей / проймы)
			for i = -7, 7 do
				local x = i * 0.125 * bw
				if math.abs(x) < W / 2 - rS - 0.03 then
					local yt
					if math.abs(x) < si - 0.02 then
						yt = cYf - dUf * math.sqrt(1 - (x / si) ^ 2) - 0.03
					elseif math.abs(x) < so - 0.02 then
						yt = top - 0.04
					else
						yt = ya - 0.02
					end
					-- верх рубчика — на UpperTorso, низ — на поясе ShirtLow (LowerTorso)
					part("UpperTorso", at(x, (bandTop + yt) / 2, -Dt / 2 - 0.007), v(0.016, yt - bandTop, 0.012), topC:Lerp(BLACK, 0.05), "Fabric", "Rib")
					part("LowerTorso", at(x, (hem + 0.05 + bandTop) / 2, -(Dt + 0.012) / 2 - 0.007), v(0.016, bandTop - hem - 0.05, 0.012), topC:Lerp(BLACK, 0.05), "Fabric", "Rib")
				end
			end
		end
	end
	if fem then
		-- грудь: мягкий объём под тканью
		local covered = topStyle ~= nil
		local bc = if covered then topC else skin
		local semi = 0.2 * h
		bustY = chestBot + (yN - chestBot) * (if cropped then 0.42 else 0.36)
		if cropped then
			bustY = math.max(bustY, chestBot + semi * 0.9)
		end
		bustOut = 0.03
		local fz0 = if covered then -D / 2 else -td / 2
		-- один мягкий объём (без «мультяшных» полусфер и «полки»): выступ ~0.025 над тканью
		ell("UpperTorso", at(0, bustY, fz0 + 0.055), v(tw * 0.84, semi * 2.1, 0.16), bc, "SmoothPlastic", "Bust")
	end

	-- ===== Таз и низ =====
	local botC = o.bottom
	local bstyle = o.bottomStyle
	rboxY("LowerTorso", 0, yH - 0.22, waistTop - 0.03, 0, hipW, td * 0.98, rT, botC, "Fabric", "Pelvis")
	-- пояс
	local bandC = if bstyle == "track" then botC:Lerp(BLACK, 0.3) else botC:Lerp(BLACK, 0.12)
	rboxY("LowerTorso", 0, waistTop - 0.096, waistTop + 0.012, 0, hipW + 0.034, td * 0.98 + 0.034, rT + 0.017, bandC, "Fabric", "Waistband")
	if bstyle == "track" then
		-- шнурок-завязка
		for _, s in { 1, -1 } do
			stick("LowerTorso", v(s * 0.05, waistTop - 0.05, -(td * 0.98 + 0.034) / 2 - 0.01), v(s * 0.08, waistTop - 0.22, -(td * 0.98 + 0.034) / 2 - 0.02), 0.022, o.stripe or WHITE, "Fabric", "Drawstring")
		end
	elseif bstyle == "baggy" then
		-- пуговица и шлёвки «джинсов»
		local fzb = -(td * 0.98 + 0.034) / 2
		part("LowerTorso", at(0, waistTop - 0.07, fzb - 0.01) * ang(0, 90, 0), v(0.02, 0.06, 0.06), rgb(150, 150, 156), "Metal", "Button", { shape = "Cylinder" })
		for _, x in { -0.55, -0.25, 0.25, 0.55 } do
			part("LowerTorso", at(x * bw, waistTop - 0.07, fzb - 0.01), v(0.04, 0.16, 0.02), bandC:Lerp(BLACK, 0.2), "Fabric", "BeltLoop")
		end
		-- ширинка
		part("LowerTorso", at(0.06, yH + 0.05, fzb + 0.004), v(0.012, 0.36, 0.02), o.stitch or bandC:Lerp(WHITE, 0.3), "Fabric", "Fly")
	end
	-- «сиденье»: заполняет зазор у тазобедренных при сгибе ног (спрятано в штанинах стоя)
	local sleeveW = if bstyle == "baggy" then lw + 0.2 elseif bstyle == "track" then lw + 0.24 elseif bstyle == "leggings" then lw + 0.02 else lw + 0.08
	local seatW = 2 * hipX + lw - 0.06
	rboxY("LowerTorso", 0, yH - 0.42, yH + 0.05, 0.0, seatW, lw - 0.06, 0.16, botC, "Fabric", "Seat")

	-- ===== Ноги =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local x = s * hipX
		local UL, LL, FT = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
		local kY, aY = P.kneeY, P.ankleY
		-- бедро (кожа) и голень
		rboxY(UL, x, kY, yH + 0.1, 0, lw, lw, 0.2, skin, "SmoothPlastic", "Thigh")
		rboxY(LL, x, aY - 0.04, kY + sw * 0.36, 0, sw, sw, 0.18, skin, "SmoothPlastic", "Shin")
		ell(LL, at(x, kY - 0.38 * h, 0.08), v(sw * 0.86, 0.5 * h, sw * 0.5), skin, "SmoothPlastic", "Calf")
		-- колено
		ell(LL, at(x, kY, -0.01), v(sw + 0.04, 0.42, sw + 0.06), skin, "SmoothPlastic", "Knee")
		-- штанина
		local hem
		if bstyle == "baggy" then
			hem = kY - 0.06 * h -- чуть ниже колена
		elseif bstyle == "track" then
			hem = kY + 0.48 * h -- до середины бедра
		elseif bstyle == "leggings" then
			hem = aY + 0.12
		else
			hem = kY + 0.18 * h
		end
		if bstyle == "leggings" then
			rboxY(UL, x, kY - 0.035, yH + 0.16, 0, lw + 0.03, lw + 0.03, 0.21, botC, "Fabric", "Legging")
			rboxY(LL, x, hem, kY + sw * 0.4 - 0.02, 0, sw + 0.03, sw + 0.03, 0.19, botC, "Fabric", "LeggingLow")
			ell(LL, at(x, kY, -0.01), v(sw + 0.08, 0.44, sw + 0.1), botC, "Fabric", "KneeCloth")
			ell(LL, at(x, kY - 0.38 * h, 0.08), v(sw * 0.86 + 0.03, 0.5 * h + 0.02, sw * 0.5 + 0.03), botC, "Fabric", "CalfCloth")
		else
			local sleeveTop = yH + 0.2
			local cx = x + s * (if bstyle == "baggy" then 0.04 else 0.02)
			local ulHem = if bstyle == "baggy" then kY - 0.04 else hem
			rboxY(UL, cx, ulHem, sleeveTop, 0, sleeveW, sleeveW, 0.22, botC, "Fabric", "ShortsLeg")
			local hemTop = hem + 0.07
			if bstyle == "baggy" then
				-- низ широкой штанины на голени + колено (не даёт щели при сгибе)
				local lowW = sleeveW - 0.04
				rboxY(LL, cx, hem, kY + 0.1, 0, lowW, lowW, 0.21, botC, "Fabric", "PantLow")
				ell(LL, at(cx, kY - 0.02, 0.0), v(lowW + 0.02, 0.5, lowW + 0.02), botC, "Fabric", "KneeCloth")
				rboxY(LL, cx, hem - 0.03, hem + 0.07, 0, lowW + 0.04, lowW + 0.04, 0.23, botC:Lerp(BLACK, 0.1), "Fabric", "Hem")
				if o.stitch then
					-- двойная строчка по низу
					for _, dy in { 0.1, 0.14 } do
						for _, ss in { -1, 1 } do
							part(LL, at(cx, hem + dy, ss * (lowW / 2 + 0.006)), v(lowW - 0.34, 0.012, 0.012), o.stitch, "Fabric", "Stitch")
							part(LL, at(cx + ss * (lowW / 2 + 0.006), hem + dy, 0), v(0.012, 0.012, lowW - 0.34), o.stitch, "Fabric", "Stitch")
						end
					end
				end
			else
				rboxY(UL, cx, hem - 0.035, hemTop, 0, sleeveW + 0.026, sleeveW + 0.026, 0.23, if bstyle == "track" then botC:Lerp(BLACK, 0.25) else botC:Lerp(BLACK, 0.1), "Fabric", "Hem")
			end
			if bstyle == "track" and o.stripe then
				-- три лампаса по боковому шву (бедро) и на поясе
				local outX = cx + s * (sleeveW / 2 + 0.007)
				-- лампасы огибают скруглённое ребро штанины спереди-сбоку (видны и анфас, и в профиль)
				local rr = 0.22
				local cc = v(cx + s * (sleeveW / 2 - rr), 0, -(sleeveW / 2 - rr))
				for _, th in { 8, 34, 60 } do
					local n = v(s * math.cos(rad(th)), 0, -math.sin(rad(th)))
					local pos = cc + n * (rr + 0.009)
					part(UL, CFrame.fromMatrix(v(pos.X, (hemTop + sleeveTop) / 2, pos.Z), n, v(0, 1, 0)), v(0.018, sleeveTop - hemTop, 0.042), o.stripe, "Fabric", "Stripe")
				end
				for i = -1, 1 do
					local z = i * 0.085 - 0.07
					part("LowerTorso", at(s * (hipW / 2 + 0.008), (yH - 0.1 + waistTop - 0.15) / 2, z), v(0.02, waistTop - 0.15 - yH + 0.1, 0.042), o.stripe, "Fabric", "Stripe")
				end
				-- маленький логотип на левой штанине
				if s < 0 then
					ell(UL, at(cx + 0.1, hemTop + 0.12, -(sleeveW / 2 + 0.006)), v(0.06, 0.05, 0.012), o.stripe, "SmoothPlastic", "Logo")
				end
			end
			if o.stitch and bstyle ~= "baggy" then
				local fz2 = -(sleeveW / 2 + 0.006)
				part(UL, at(cx, hemTop + 0.03, fz2), v(sleeveW - 0.3, 0.014, 0.012), o.stitch, "Fabric", "Stitch")
			end
			if o.stitch and bstyle == "baggy" then
				-- строчка по переду и боковому шву бедра
				local fz2 = -(sleeveW / 2 + 0.006)
				part(UL, at(cx + s * (sleeveW / 2 - 0.12), (kY + yH) / 2, fz2), v(0.012, yH - kY - 0.1, 0.012), o.stitch, "Fabric", "Stitch")
				part(UL, at(cx + s * (sleeveW / 2 + 0.006), (kY + yH) / 2, 0.04), v(0.012, yH - kY - 0.1, 0.012), o.stitch, "Fabric", "Stitch")
				-- карман
				part(UL, at(cx + s * 0.08, yH - 0.08, fz2) * ang(0, 0, s * 35), v(0.012, 0.34, 0.012), o.stitch, "Fabric", "Stitch")
			end
			if o.roses then
				-- принт: крупные красные розы с листьями, разбросаны по-разному на правой и левой штанине
				local leaf = rgb(46, 92, 58)
				local function rose(bone, cf, d, lr)
					lr = lr or 0
					ell(bone, cf, v(d, d * 0.92, 0.036), o.roses, "Fabric", "Rose")
					ell(bone, cf * at(0.0, d * 0.06, -0.008), v(d * 0.6, d * 0.52, 0.03), o.roses:Lerp(BLACK, 0.38), "Fabric", "RoseHeart")
					ell(bone, cf * at(-d * 0.12, d * 0.14, -0.014) * ang(0, 0, 30), v(d * 0.36, d * 0.14, 0.024), o.roses:Lerp(WHITE, 0.18), "Fabric", "RosePetal")
					ell(bone, cf * at(d * 0.16, -d * 0.12, -0.014) * ang(0, 0, -40), v(d * 0.3, d * 0.12, 0.024), o.roses:Lerp(BLACK, 0.2), "Fabric", "RosePetal")
					ell(bone, cf * ang(0, 0, lr) * at(d * 0.44, -d * 0.52, 0.004) * ang(0, 0, 38), v(d * 0.62, d * 0.24, 0.03), leaf, "Fabric", "Leaf")
					ell(bone, cf * ang(0, 0, lr) * at(-d * 0.5, -d * 0.4, 0.004) * ang(0, 0, -30), v(d * 0.5, d * 0.2, 0.03), leaf:Lerp(BLACK, 0.15), "Fabric", "Leaf")
				end
				local function onSide(bone, y, fz2, d, lr)
					rose(bone, CFrame.fromMatrix(v(cx + s * (sleeveW / 2 + 0.004), y, fz2 * sleeveW), v(0, 0, s), v(0, 1, 0)), d, lr)
				end
				local function onFront(bone, fx2, y, d, lr)
					rose(bone, CFrame.fromMatrix(v(cx + s * fx2 * sleeveW, y, -(sleeveW / 2 + 0.004)), v(1, 0, 0), v(0, 1, 0)), d, lr)
				end
				local bot = (if bstyle == "baggy" then kY - 0.04 else hem) + 0.16
				if s > 0 then
					onSide(UL, yH - 0.25, -0.1, 0.27)
					onSide(UL, bot + 0.12, 0.2, 0.3, 15)
					onFront(UL, 0.21, kY + 0.54, 0.26)
					onFront(UL, -0.14, yH - 0.08, 0.17)
				else
					onSide(UL, yH - 0.36, 0.12, 0.25, 25)
					onSide(UL, bot + 0.04, -0.16, 0.22, -20)
					onFront(UL, 0.04, kY + 0.36, 0.2, 25)
				end
			end
		end
		-- стопа
		local heelZ = P.footLen - P.footFwd
		local toeZ = -P.footFwd
		local fl = P.footLen
		local midZ = (heelZ + toeZ) / 2
		local footW = math.max(if fem then 0.58 else 0.66, sw + 0.02)
		if o.shoes == "barefoot" then
			rbox(FT, at(x, 0.1, midZ + 0.06), v(footW * 0.92, 0.2, fl - 0.2), 0.18, skin, "SmoothPlastic", "Foot")
			ell(FT, at(x, 0.17, heelZ - 0.22), v(footW * 0.86, 0.34, 0.46), skin, "SmoothPlastic", "Heel")
			ell(FT, at(x, 0.2, midZ - 0.04), v(footW * 0.86, 0.3, fl * 0.72), skin, "SmoothPlastic", "Instep")
			ell(FT, at(x, 0.09, toeZ + 0.2), v(footW * 0.96, 0.18, 0.34), skin, "SmoothPlastic", "Ball")
			-- пальцы
			for i = 0, 4 do
				local tx = x - s * (-footW / 2 + 0.09 + i * (footW - 0.16) / 4)
				local dd = if i == 0 then 0.15 else 0.115 - i * 0.008
				ball(FT, v(tx, 0.07, toeZ + 0.09 + i * 0.022), dd, skin, "SmoothPlastic", "Toe")
				ball(FT, v(tx, 0.085, toeZ + 0.08 + i * 0.022), dd * 0.55, rgb(232, 196, 190):Lerp(skin, 0.4), "SmoothPlastic", "Nail")
			end
			ell(FT, at(x, 0.32, 0.0), v(sw * 0.9, 0.4, sw * 0.9), skin, "SmoothPlastic", "Ankle")
		else
			local shoe = o.shoeColor
			local acc = o.shoeAccent
			local sole = o.sole
			-- подошва: низкая, скруглённая, носок чуть приподнят
			rbox(FT, at(x, 0.055, midZ + 0.02), v(footW + 0.04, 0.11, fl - 0.06), 0.24, sole, "Rubber", "Sole")
			ell(FT, at(x, 0.07, toeZ + 0.14), v(footW + 0.04, 0.13, 0.3), sole, "Rubber", "SoleToe")
			-- верх: колодка, низкий скруглённый носок, задник
			rbox(FT, at(x, 0.2, midZ + 0.1), v(footW, 0.2, fl - 0.36), 0.22, shoe, "Fabric", "Upper")
			ell(FT, at(x, 0.15, toeZ + 0.26), v(footW - 0.02, 0.17, 0.52), shoe, "Fabric", "ToeBox")
			ell(FT, at(x, 0.26, heelZ - 0.17), v(footW + 0.01, 0.34, 0.36), shoe, "Fabric", "Heel")
			ell(FT, at(x, 0.36, heelZ - 0.05), v(0.14, 0.16, 0.08), acc or shoe:Lerp(BLACK, 0.15), "SmoothPlastic", "HeelTab")
			-- язычок, проём и шнурки
			local tongueCF = at(x, 0.3, midZ - 0.06) * ang(-22, 0, 0)
			part(FT, tongueCF, v(footW * 0.46, 0.06, 0.44), shoe:Lerp(WHITE, 0.1), "Fabric", "Tongue")
			ell(FT, at(x, 0.4, heelZ - 0.3), v(sw * 0.98, 0.07, sw * 0.98), shoe:Lerp(BLACK, 0.35), "SmoothPlastic", "Collar")
			for i = 0, 3 do
				part(FT, tongueCF * at(0, 0.045, -0.16 + i * 0.1) * ang(0, (i % 2 * 2 - 1) * 10, 0), v(footW * 0.5, 0.026, 0.034), if acc then WHITE else shoe:Lerp(WHITE, 0.7), "Fabric", "Lace")
			end
			if acc then
				-- полоса-«формстрип» по бокам: дуга от пятки вниз-вперёд к носку
				for _, ss in { 1, -1 } do
					local px = x + ss * (footW / 2 + 0.004)
					local cf = CFrame.fromMatrix(v(px, 0.19, midZ + 0.06), v(0, 0, -1), v(0, 1, 0)) * ang(0, 0, -14)
					part(FT, cf, v(fl * 0.6, 0.06, 0.014), acc, "Leather", "Formstrip")
				end
			end
			-- носок
			if o.socks then
				-- короткие носки до щиколотки (crew): тонкий слой поверх голени + манжета
				rboxY(LL, x, aY + 0.02, aY + 0.22, 0, sw + 0.02, sw + 0.02, 0.19, o.socks, "Fabric", "Sock")
				rboxY(LL, x, aY + 0.16, aY + 0.24, 0, sw + 0.05, sw + 0.05, 0.205, o.socks:Lerp(BLACK, 0.04), "Fabric", "SockCuff")
				ell(FT, at(x, aY + 0.06, 0.04), v(sw * 0.92, 0.34, sw * 0.92), o.socks, "SmoothPlastic", "Ankle")
			else
				ell(FT, at(x, 0.4, 0.04), v(sw * 0.92, 0.36, sw * 0.92), skin, "SmoothPlastic", "Ankle")
			end
		end
	end

	-- ===== Руки =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local x = s * P.shoulderX
		local UA, LA, HD = side .. "UpperArm", side .. "LowerArm", side .. "Hand"
		local sY = P.shoulderY
		local eY = sY - P.upperArm
		local wY = eY - P.lowerArm
		-- плечо (дельта шире бицепса)
		rboxY(UA, x, eY, sY - 0.1, 0, aw * 0.86, aw * 0.88, aw * 0.3, skin, "SmoothPlastic", "UpperArm")
		-- бицепс: мягкий объём спереди (рука не «труба»)
		ell(UA, at(x, sY - 0.5 * h, -0.03), v(aw * 0.92, 0.62 * h, aw * 0.94), skin, "SmoothPlastic", "Biceps")
		ell(UA, at(x, sY - 0.12, 0), v(aw * 0.9, 0.56 * h, aw * 0.9), skin, "SmoothPlastic", "Deltoid")
		ell(UA, at(x, sY - 0.02, 0), v(aw * 0.88, 0.22 * h, aw * 0.88), skin, "SmoothPlastic", "ShoulderCap")
		if topStyle == "tee" then
			rboxY(UA, x, sY - 0.55 * h, sY - 0.045, 0, aw + 0.09, aw + 0.09, aw * 0.3 + 0.045, o.top, "Fabric", "Sleeve")
			ell(UA, at(x, sY - 0.015, 0), v(aw * 0.94 + 0.06, 0.36 * h, aw * 0.94 + 0.06), o.top, "SmoothPlastic", "SleeveCap")
			ell(UA, at(x, sY - 0.12, 0), v(aw + 0.06, 0.6 * h, aw * 0.99 + 0.06), o.top, "SmoothPlastic", "SleeveDelt")
		end
		-- локоть + предплечье
		ell(LA, at(x, eY - 0.02, 0.02), v(aw * 0.9, 0.5, aw * 0.9), skin, "SmoothPlastic", "Elbow")
		-- предплечье сужается к запястью: тонкий rbox (запястье) + мышечный объём у локтя
		rboxY(LA, x, wY + 0.04, eY - 0.05, 0, fx * 0.74, fz * 0.76, fx * 0.3, skin, "SmoothPlastic", "Forearm")
		ell(LA, at(x, eY - 0.34 * h, -0.015), v(fx * 1.02, 0.8 * h, fz * 1.0), skin, "SmoothPlastic", "ForearmMuscle")
		-- запястье и ладонь
		ell(HD, at(x, wY - 0.02, 0), v(pt + 0.1, 0.3, pw * 0.92), skin, "SmoothPlastic", "Wrist")
		local hl = P.handLen
		rbox(HD, at(x, wY - hl / 2 - 0.01, 0), v(pt, hl + 0.04, pw), pt * 0.42, skin, "SmoothPlastic", "Palm")
		-- подушечка большого пальца (со стороны ладони)
		ell(HD, at(x - s * pt * 0.22, wY - hl * 0.45, -pw * 0.24), v(pt * 0.8, hl * 0.8, pw * 0.42), skin, "SmoothPlastic", "Thenar")
		-- пальцы: капсулы + ногти
		for _, f in { "Index", "Middle", "Ring", "Pinky", "Thumb" } do
			local b1, b2 = side .. f .. "1", side .. f .. "2"
			local p1 = rig:pivotOf(b1)
			local p2 = rig:pivotOf(b2)
			local len2 = if f == "Thumb" then P.thumbLen2 else P.fingerLen2 * (if f == "Pinky" then 0.8 elseif f == "Middle" then 1.08 else 1)
			local d = fd * (if f == "Thumb" then 1.12 elseif f == "Pinky" then 0.88 else 1)
			local tip = p2 - v(0, len2 - d * 0.5, 0)
			ball(b1, p1, d * 1.04, skin, "SmoothPlastic", "Knuckle")
			stick(b1, p1, p2, d, skin, "SmoothPlastic", "Finger")
			ball(b2, p2, d * 0.98, skin, "SmoothPlastic", "FingerJoint")
			stick(b2, p2, tip, d * 0.94, skin, "SmoothPlastic", "Finger")
			ball(b2, tip, d * 0.94, skin, "SmoothPlastic", "Fingertip")
			if f ~= "Thumb" then
				-- ноготь на тыльной стороне (+X у правой руки)
				ell(b2, at(tip.X + s * d * 0.36, tip.Y + d * 0.12, tip.Z), v(d * 0.34, d * 0.8, d * 0.72), rgb(238, 200, 192):Lerp(skin, 0.45), "SmoothPlastic", "Nail")
			end
			if o.rings and (f == "Middle" or f == "Index") and side == "Right" then
				stick(b1, p1 - v(0, (p1 - p2).Magnitude * 0.5 - 0.016, 0), p1 - v(0, (p1 - p2).Magnitude * 0.5 + 0.016, 0), d + 0.022, o.rings, "Metal", "Ring")
			end
		end
		-- браслеты
		local list = o.bracelets and o.bracelets[string.lower(side)]
		if list then
			for i, col in list do
				local by = wY + 0.12 + (i - 1) * 0.075
				rboxY(LA, x, by - 0.028, by + 0.028, 0, fx + 0.06, fz + 0.06, fx * 0.4, col, if col.R + col.G + col.B > 1.5 then "Metal" else "SmoothPlastic", "Bracelet")
			end
		end
		if o.watch == string.lower(side) then
			-- металлический браслет-часы из звеньев
			local by = wY + 0.14
			rboxY(LA, x, by - 0.05, by + 0.05, 0, fx + 0.07, fz + 0.07, fx * 0.42, rgb(196, 198, 204), "Metal", "Watch")
			for i = -2, 2 do
				part(LA, at(x + s * (fx / 2 + 0.04), by, i * 0.07), v(0.012, 0.11, 0.02), rgb(150, 152, 160), "Metal", "WatchLink")
			end
		end
	end

	-- ===== Голова =====
	local hc = yN + 0.92 * h -- центр головы (длинная шея: подбородок заметно выше выреза майки)
	local R = 0.6
	local function H(x, y, z)
		return v(x, hc + y, z)
	end
	local function Hc(x, y, z)
		return CFrame.new(x, hc + y, z)
	end
	-- Кожа головы — набор эллипсоидов; их передняя поверхность (surfZ) нужна для посадки черт лица.
	local surf = {}
	-- rot — градусы (X, Y, Z) или nil
	local function sk(bone, c, size, color, name, rot)
		local cf = CFrame.new(c) * (if rot then ang(rot.X, rot.Y, rot.Z) else CFrame.new())
		table.insert(surf, { cf = cf, inv = cf:Inverse(), a = size.X / 2, b = size.Y / 2, d = size.Z / 2 })
		return ell(bone, Hc(0, 0, 0) * cf, size, color or skin, "SmoothPlastic", name)
	end
	-- передняя точка поверхности набора эллипсоидов вдоль луча (x, y, -∞) -> +Z (в осях головы)
	local function frontZ(list, x, y)
		local best = 0
		for _, e in list do
			local o0 = e.inv * v(x, y, -3)
			local d0 = e.inv:VectorToWorldSpace(v(0, 0, 1))
			local ox, oy, oz = o0.X / e.a, o0.Y / e.b, o0.Z / e.d
			local dx, dy, dz = d0.X / e.a, d0.Y / e.b, d0.Z / e.d
			local A = dx * dx + dy * dy + dz * dz
			local B = 2 * (ox * dx + oy * dy + oz * dz)
			local C = ox * ox + oy * oy + oz * oz - 1
			local disc = B * B - 4 * A * C
			if disc > 0 then
				local t = (-B - math.sqrt(disc)) / (2 * A)
				local z = -3 + t
				if z < best then
					best = z
				end
			end
		end
		return best
	end
	local function surfZ(x, y)
		return frontZ(surf, x, y)
	end
	local function normal(x, y)
		local e = 0.01
		local zx = (surfZ(x + e, y) - surfZ(x - e, y)) / (2 * e)
		local zy = (surfZ(x, y + e) - surfZ(x, y - e)) / (2 * e)
		return v(zx, zy, -1).Unit
	end
	-- CFrame на поверхности лица: локальная -Z — наружу, Y — примерно вверх; off — отступ наружу
	local function onFace(x, y, off, roll)
		local n = normal(x, y)
		local p = H(x, y, surfZ(x, y)) + n * (off or 0)
		local Z = -n
		local X = v(0, 1, 0):Cross(Z).Unit
		local Y = Z:Cross(X)
		return CFrame.fromMatrix(p, X, Y, Z) * ang(0, 0, roll or 0)
	end

	-- шея
	local neckD = (if fem then 0.38 else 0.46) * bw
	cylY("Head", Hc(0, -0.75, 0.06), 0.96, neckD, skin, "SmoothPlastic", "Neck")
	ell("Head", Hc(0, -0.4, 0.1), v(neckD * 0.98, 0.5, neckD * 0.98), skin, "SmoothPlastic", "NeckTop")
	if not fem then
		ell("Head", Hc(0, -0.62, -neckD * 0.36), v(0.1, 0.12, 0.1), skin, "SmoothPlastic", "AdamsApple")
	end
	-- череп, лицо, надбровье, «муфта» под носом
	-- Лицо у всех одной «глубинной» схемы (слои рта подобраны по глубине), у девушек уже по X.
	local fx = if fem then 0.94 else 1.0
	local cran = if fem then v(1.04, 1.17, 1.16) else v(1.06, 1.2, 1.18)
	local headHW = cran.X / 2 -- полуширина черепа
	sk("Head", v(0, 0.1, 0.06), cran, skin, "Cranium")
	sk("Head", v(0, -0.0, -0.3), v(0.92 * fx, 1.0, 0.6), skin, "Face")
	if not fem then
		-- надбровная кость (мягкий объём, не «полоса» через лоб)
		sk("Head", v(0, 0.17, -0.42), v(0.76, 0.14, 0.3), skin, "BrowRidge")
	end
	local beardOn = o.beard ~= nil
	-- щетина: не отдельный объём, а цвет кожи нижней части лица (облегает челюсть), чуть темнее у подбородка
	local bAmt = o.beardAmount or 0.52 -- густота щетины (0..1): смешение цвета кожи с цветом бороды
	local stub = if beardOn then skin:Lerp(o.beard, bAmt) else skin
	local stubD = if beardOn then skin:Lerp(o.beard, bAmt + 0.1) else skin
	-- «муфта» над верхней губой (у бородатых — зона усов)
	local muzzleSpec = sk("Head", v(0, -0.25, -0.43), v(0.42 * fx, 0.26, 0.36), if beardOn then stub:Lerp(stubD, 0.5) else skin, "Muzzle")
	local _ = muzzleSpec
	-- нижняя челюсть на суставе Jaw
	local jawPivot = H(0, -0.22, 0.18)
	rig:joint("Jaw", "Head", jawPivot, jawPivot, v(0.1, 0.1, 0.1))
	local jawS = v(0.78 * (if fem then 0.88 else 1), 0.44, if fem then 0.99 else 1.02)
	-- верх-перёд челюсти уходит назад (над линией рта лицо — «муфта» на голове): при открытом рте
	-- в проёме видна полость, а не кожа челюсти
	local jawC = v(0, -0.4, -0.1)
	local jawR = v(-10, 0, 0) -- наклон: угол челюсти у уха выше, подбородок ниже
	local chinS = if fem then v(0.25, 0.18, 0.3) else v(0.34, 0.22, 0.34)
	local chinC = if fem then v(0, -0.49, -0.425) else v(0, -0.49, -0.37)
	sk("Jaw", jawC, jawS, if beardOn then skin else stub, "JawSkin", jawR)
	sk("Jaw", chinC, chinS, stubD, "Chin")
	-- низ челюсти — одна гладкая поверхность JawSkin (подбородок Chin целиком внутри неё: без «второго подбородка»)
	-- щёки на суставах (поднимаются при улыбке): цвет кожи с лёгким румянцем
	local cheekC = skin:Lerp(rosyC, if fem then 0.1 else 0.08)
	local cheekParts = {}
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local cj = side .. "Cheek"
		-- в покое «яблочко» щеки утоплено в лицо (не видно), улыбка выдвигает его вперёд-вверх
		local cc = v(s * 0.22 * fx, -0.15, -0.345)
		rig:joint(cj, "Head", H(cc.X, cc.Y, cc.Z), H(cc.X, cc.Y, cc.Z), v(0.05, 0.05, 0.05))
		local apple = ell(cj, Hc(cc.X, cc.Y, cc.Z + 0.06), v(0.42 * fx, 0.34, 0.42), if beardOn then stub else cheekC, "SmoothPlastic", "Cheek")
		cheekParts[side] = apple
	end
	-- Щетина на щеках: «оболочка» эллипсоида кожи — его копия, сдвинутая вдоль нормали плоскости линии бороды и
	-- чуть уменьшенная так, что выступает из кожи (на 0..0.02) только по одну сторону плоскости n·p > k
	-- (p — от центра головы). Граница — плоское сечение головы: одна чистая диагональ. Два тона: светлая кромка
	-- (граница выше на 0.035, сдвиг m) и густая щетина (сдвиг 2m) — край мягкий.
	if beardOn then
		local function shell(bone, cf, size, n, k, m, color, name)
			local S = size / 2
			local nl = cf:VectorToObjectSpace(n)
			local w = v(S.X * nl.X, S.Y * nl.Y, S.Z * nl.Z)
			local L = w.Magnitude
			local cu = (k - n:Dot(cf.Position)) / L
			local wh = w / L
			local scale = math.sqrt(1 - 2 * m * cu + m * m)
			return ell(bone, Hc(0, 0, 0) * cf * CFrame.new(S.X * wh.X * m, S.Y * wh.Y * m, S.Z * wh.Z * m), size * scale, color, "SmoothPlastic", name)
		end
		local soft = skin:Lerp(stub, 0.45)
		local kB = o.beardLine or 0.39 -- уровень линии бороды (больше — ниже)
		local mB = 0.2
		for _, s in { 1, -1 } do
			-- плоскость через низ бакенбарды перед ухом (±0.47, −0.1, −0.02) и точку над уголком рта
			-- (±0.17, −0.28, −0.5); наклонена вниз-наружу (затылок и скула под глазом — вне бороды)
			local n = v(s * 0.668, -0.73, -0.144).Unit
			-- для черепа плоскость сильнее наклонена вперёд: за ухом и на затылке щетины нет
			-- (обе плоскости проходят через низ бакенбарды A = (±0.47, −0.1, −0.02))
			local nc = v(s * 0.577, -0.631, -0.519).Unit
			local A = v(s * 0.47, -0.1, -0.02)
			local kc = nc:Dot(A) + (kB - n:Dot(A))
			for _, e in { { CFrame.new(0, 0, -0.3), v(0.92 * fx, 1.0, 0.6), n, kB }, { CFrame.new(0, 0.1, 0.06), cran, nc, kc } } do
				shell("Head", e[1], e[2], e[3], e[4] - 0.035, mB, soft, "BeardShell2")
				shell("Head", e[1], e[2], e[3], e[4] - 0.0175, 2 * mB, stub, "BeardShell")
			end
			-- челюсть: щетина спереди и снизу, за ухом — кожа (плоскость поперёк, наклонена вниз)
			if s > 0 then
				local jcf = CFrame.new(jawC) * ang(jawR.X, jawR.Y, jawR.Z)
				local nj = v(0, -0.3, -0.95).Unit
				-- (сдвиг мал: граница за ухом, а спереди оболочка не должна утолщать подбородок)
				shell("Jaw", jcf, jawS, nj, -0.02, 0.016, soft, "BeardShell2")
				shell("Jaw", jcf, jawS, nj, 0.0, 0.032, stub, "BeardShell")
			end
		end
	end

	-- уши
	for _, s in { 1, -1 } do
		local ec = Hc(s * (headHW + 0.02), -0.04, 0.09) * ang(0, s * -14, s * -5)
		local earC = skin:Lerp(rosyC, 0.4)
		ell("Head", ec, v(0.13, 0.31, 0.21), earC, "SmoothPlastic", "Ear")
		ell("Head", ec * at(s * 0.04, 0.02, -0.004), v(0.05, 0.2, 0.12), skinDeep, "SmoothPlastic", "EarInner")
		ell("Head", ec * at(s * 0.045, 0.025, 0.02), v(0.04, 0.22, 0.06), earC, "SmoothPlastic", "EarRim")
		ell("Head", ec * at(s * 0.01, -0.13, -0.01), v(0.09, 0.1, 0.1), earC, "SmoothPlastic", "EarLobe")
	end

	-- ----- глаза -----
	-- Белок-«миндаль» с тёмной линией ресниц по верху (обод позади белка, смещён вверх), крупная радужка
	-- под верхним веком. Верхнее веко — тонкая «шторка» над глазом (моргание — вниз), нижнее веко
	-- в покое утоплено под белок; улыбка поднимает его вперёд-вверх: видимая часть глаза — дуга «◠».
	local eyeY = 0.0
	local eyeX = if fem then 0.212 else 0.205
	-- у парня глаза уже и глубже (прищур под тяжёлыми прямыми бровями), у девушек — крупнее
	local eyeW, eyeH, eyeD = (if fem then 0.236 else 0.2), (if fem then 0.176 else 0.125), 0.1
	local lashC = rgb(30, 20, 18)
	local LL_REST, LL_OUT = 0.1, 0.086 -- нижнее веко: глубина в покое и ход вперёд при улыбке
	local whiteC = rgb(248, 244, 238)
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local ex = s * eyeX
		-- лёгкий наклон: внешний уголок чуть выше (у девушек заметнее)
		local eyeCF = onFace(ex, eyeY, 0, s * (if fem then 5 else 3)) * at(0, 0, eyeD / 2 - 0.016)
		ell("Head", eyeCF, v(eyeW, eyeH, eyeD), whiteC, "SmoothPlastic", "EyeWhite")
		-- линия ресниц: обод позади белка, смещён вверх (снизу почти не виден)
		local rimT = if o.lashes then 0.04 else 0.03
		ell("Head", eyeCF * at(0, rimT / 2, 0.006), v(eyeW + rimT * 0.8, eyeH + rimT, eyeD * 0.94), lashC, "SmoothPlastic", "LashRim")
		if o.lashes then
			-- «стрелка» ресниц у внешнего уголка
			ell("Head", eyeCF * at(s * eyeW * 0.46, eyeH * 0.3, 0.008) * ang(0, 0, s * 24), v(0.09, 0.03, eyeD * 0.8), lashC, "SmoothPlastic", "LashFlick")
		end
		-- взгляд: радужка, зрачок, блики
		local eyeJ = side .. "Eye"
		rig:joint(eyeJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		local irisD = eyeH * (if fem then 0.84 else 0.86)
		local irisC = o.eyes
		local iy = eyeH * 0.03
		local fz = -eyeD / 2
		ell(eyeJ, eyeCF * at(0, iy, fz + 0.018), v(irisD, irisD, 0.05), irisC:Lerp(BLACK, 0.6), "SmoothPlastic", "IrisRing")
		ell(eyeJ, eyeCF * at(0, iy, fz + 0.0145), v(irisD * 0.86, irisD * 0.86, 0.05), irisC, "SmoothPlastic", "Iris")
		ell(eyeJ, eyeCF * at(0, iy - irisD * 0.14, fz + 0.011), v(irisD * 0.56, irisD * 0.38, 0.05), irisC:Lerp(WHITE, 0.28), "SmoothPlastic", "IrisLight")
		ell(eyeJ, eyeCF * at(0, iy, fz + 0.0085), v(irisD * 0.46, irisD * 0.46, 0.05), rgb(12, 8, 8), "SmoothPlastic", "Pupil")
		ell(eyeJ, eyeCF * at(-irisD * 0.2, iy + irisD * 0.2, fz + 0.002), v(irisD * 0.26, irisD * 0.26, 0.02), WHITE, "SmoothPlastic", "Glint")
		ell(eyeJ, eyeCF * at(irisD * 0.2, iy - irisD * 0.18, fz + 0.003), v(irisD * 0.1, irisD * 0.1, 0.02), WHITE, "SmoothPlastic", "Glint")
		-- верхнее веко: «шторка» над глазом, нижний край — по верху линии ресниц
		local lidJ = side .. "Lid"
		rig:joint(lidJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		local lidH = eyeH * 1.05
		local lidBot = eyeH / 2 + rimT * 0.75
		ell(lidJ, eyeCF * at(0, lidBot + lidH / 2, fz + 0.07), v(eyeW + 0.05, lidH, 0.05), skin, "SmoothPlastic", "Lid")
		-- ресницы по краю века: видны при моргании и прищуре (в покое совпадают с линией ресниц)
		ell(lidJ, eyeCF * at(0, lidBot + 0.008, fz + 0.074), v(eyeW * 1.04, rimT * 0.8, 0.03), lashC, "SmoothPlastic", "LashLine")
		-- нижнее веко: в покое утоплено под белок
		local llJ = side .. "LowerLid"
		rig:joint(llJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		-- широкое веко: его верхний край — плоская дуга; поднятое (улыбка) оставляет от глаза серп «◠».
		-- В покое утоплено в лицо (LL_REST глубже белка), улыбка выдвигает его вперёд на LL_OUT.
		local llH = eyeH * 0.9
		ell(llJ, eyeCF * at(0, -eyeH / 2 - llH / 2 + 0.012, fz + LL_REST) * ang(-14, 0, 0), v(eyeW + 0.03, llH, 0.05), skin:Lerp(rosyC, 0.08), "SmoothPlastic", "LowerLid")
		-- нижняя линия ресниц (неподвижна; при улыбке её закрывает поднятое веко)
		ell("Head", eyeCF * at(0, -eyeH / 2 + 0.006, fz + 0.012), v(eyeW * 0.8, 0.014, 0.02), lashC:Lerp(skin, 0.25), "SmoothPlastic", "LowerLash")
	end

	-- ----- брови -----
	local browC = o.brows or o.hair:Lerp(BLACK, 0.35)
	local bt = o.browThick
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local by = eyeY + eyeH * 0.5 + (if fem then 0.11 else 0.05)
		local bj = side .. "Brow"
		local pivot = onFace(s * (eyeX + 0.005), by, 0.01).Position
		rig:joint(bj, "Head", pivot, pivot, v(0.05, 0.05, 0.05))
		if fem then
			-- три сегмента: толстое начало у переносицы, дуга, тонкий хвост
			ell(bj, onFace(s * (eyeX - 0.07), by - 0.002, -0.01, -s * 4), v(0.13, 0.062 * bt, 0.05), browC, "SmoothPlastic", "Brow")
			ell(bj, onFace(s * (eyeX + 0.0), by + 0.012, -0.01, -s * 8), v(0.15, 0.056 * bt, 0.05), browC, "SmoothPlastic", "Brow")
			ell(bj, onFace(s * (eyeX + 0.075), by + 0.0, -0.011, -s * 20), v(0.13, 0.042 * bt, 0.05), browC, "SmoothPlastic", "Brow")
		else
			-- густые прямые брови: два длинных перекрывающихся сегмента, плоско по лбу
			ell(bj, onFace(s * (eyeX - 0.04), by, -0.008, -s * 2), v(0.2, 0.06 * bt, 0.03), browC, "SmoothPlastic", "Brow")
			ell(bj, onFace(s * (eyeX + 0.06), by + 0.004, -0.008, -s * 9), v(0.18, 0.05 * bt, 0.03), browC, "SmoothPlastic", "Brow")
		end
	end

	-- ----- нос -----
	local ns = o.nose
	local noseC = skin:Lerp(rosyC, if fem then 0.2 else 0.35)
	ell("Head", onFace(0, -0.03, 0.006), v(0.1 * ns, 0.3 * ns, 0.1 * ns), skin, "SmoothPlastic", "NoseBridge")
	ell("Head", onFace(0, -0.1, 0.022 * ns), v(0.12 * ns, 0.16 * ns, 0.1 * ns), skin:Lerp(noseC, 0.5), "SmoothPlastic", "NoseBridge")
	local tipZ = surfZ(0, -0.155) - 0.05 * ns
	ell("Head", Hc(0, -0.155 * ns, tipZ), v(0.15 * ns, 0.13 * ns, 0.13 * ns), noseC, "SmoothPlastic", "NoseTip")
	for _, s in { 1, -1 } do
		ell("Head", Hc(s * 0.058 * ns, -0.176 * ns, tipZ + 0.036), v(0.075 * ns, 0.068 * ns, 0.075 * ns), noseC, "SmoothPlastic", "NoseWing")
		ell("Head", Hc(s * 0.032 * ns, -0.205 * ns, tipZ + 0.012), v(0.042 * ns, 0.022, 0.05 * ns), skinDeep:Lerp(BLACK, 0.3), "SmoothPlastic", "Nostril")
	end

	-- ----- рот -----
	-- Рот — настоящий проём: позади губ тёмная полость и верхние зубы (сустав Mouth на голове).
	-- Нижняя губа — «полумесяц» на Jaw (середина + края, приподнятые к уголкам; в покое концы спрятаны за
	-- краями верхней губы). Середина верхней губы — UpperLip, края верхней губы и кожа у уголков — на уголках
	-- RightMouth/LeftMouth; края нижней губы — RightLowerLip/LeftLowerLip (дети Jaw, улыбка поднимает их к уголкам).
	-- jaw опускает челюсть, smile поднимает и разводит уголки (верхняя губа — «улыбкой»), oh сводит уголки
	-- и выгибает верхнюю губу аркой («О»).
	local my = -0.355 -- линия смыкания губ
	local mz = surfZ(0, my)
	local mw = if fem then 0.88 else 1.0 -- ширина рта (и всей «механики» рта по X — слои глубины одинаковы)
	local cw = 0.135 * mw -- уголок рта (x)
	local mouthDark = rgb(74, 24, 30)
	local lipC = skin:Lerp(o.lips, if fem then 0.8 else 0.5)
	local lipLo = lipC:Lerp(WHITE, 0.05)
	local teethC = rgb(250, 248, 240)
	local mPivot = H(0, my, -0.5)
	rig:joint("Mouth", "Head", mPivot, mPivot, v(0.05, 0.05, 0.05))
	-- полость: передняя поверхность — между кожей челюсти (позади) и губами (впереди)
	local cavC, cavS = v(0, my - 0.065, -0.488), v(0.32 * mw, 0.32, 0.124)
	local function cavFront(x, y)
		local dx, dy = x / (cavS.X / 2), (y - cavC.Y) / (cavS.Y / 2)
		return cavC.Z - cavS.Z / 2 * math.sqrt(math.max(0, 1 - dx * dx - dy * dy))
	end
	-- низ полости наклонён вперёд (перед опустившейся кожей челюсти), верх — позади зубов
	ell("Mouth", Hc(cavC.X, cavC.Y, cavC.Z) * ang(5, 0, 0), cavS, mouthDark, "SmoothPlastic", "MouthInside")
	-- верхние зубы: верх спрятан за губой, видна нижняя половина — дуга «∪» во всю ширину проёма
	ell("Mouth", Hc(0, my + 0.008, -0.462), v(0.34 * mw, 0.1, 0.22), teethC, "SmoothPlastic", "UpperTeeth")
	-- нижняя челюсть: зубы, язык, нижняя губа-«полумесяц»
	ell("Jaw", Hc(0, my - 0.04, -0.452), v(0.2 * mw, 0.05, 0.2), teethC:Lerp(rgb(226, 214, 196), 0.3), "SmoothPlastic", "LowerTeeth")
	ell("Jaw", Hc(0, my - 0.075, -0.452), v(0.22 * mw, 0.1, 0.2), rgb(190, 86, 96), "SmoothPlastic", "Tongue")
	-- «дно» рта: тёмная накладка за нижней губой поверх верха кожи челюсти (при раскрытии челюсть
	-- поворачивается верхом к зрителю — без накладки между губой и полостью виднелась бы полоса кожи)
	ell("Jaw", Hc(0, my - 0.036, -0.512), v(0.24 * mw, 0.07, 0.1), mouthDark, "SmoothPlastic", "MouthFloor")
	ell("Jaw", Hc(0, my - 0.031, surfZ(0, my - 0.031) - 0.01), v(0.15 * mw, if fem then 0.068 else 0.062, 0.06), lipLo, "SmoothPlastic", "LowerLip")
	-- средние участки нижней губы (на челюсти, концы чуть вверх): скругляют дугу «◡» между серединой и краями
	for _, s in { 1, -1 } do
		local xm = s * 0.07 * mw
		ell("Jaw", Hc(xm, my - 0.027, surfZ(xm, my - 0.027) - 0.007) * ang(0, -s * 8, s * 12), v(0.1 * mw, if fem then 0.058 else 0.054, 0.05), lipLo, "SmoothPlastic", "LowerLipMid")
	end
	-- края нижней губы — на своих суставах RightLowerLip/LeftLowerLip (дети головы, опора — в уголке рта, как у
	-- RightMouth/LeftMouth): jaw поворачивает их внутренним концом вниз вслед за серединой губы (проём — «D»: верх —
	-- линия верхней губы, низ — дуга нижней), smile/oh двигают их вместе с уголками. Ниже края губы — кожа у уголка
	-- RightCornerSkin/LeftCornerSkin (дети LowerLip, глубже губ и впереди полости): закрывает проём снаружи дуги.
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local cx = s * cw
		local lj = side .. "LowerLip"
		local lp = H(cx, my, surfZ(cx, my))
		rig:joint(lj, "Head", lp, lp, v(0.05, 0.05, 0.05))
		local x0 = s * (cw - 0.068 * mw)
		ell(lj, Hc(x0, my - 0.022, surfZ(x0, my - 0.022) - 0.004) * ang(0, -s * 12, s * 7), v(0.15 * mw, 0.048, 0.046), lipLo, "SmoothPlastic", "LowerLipSide")
		local csj = side .. "CornerSkin"
		rig:joint(csj, lj, lp, lp, v(0.05, 0.05, 0.05))
		ell(csj, Hc(s * (cw - 0.03 * mw), my - 0.08, -0.505) * ang(0, -s * 18, s * 8), v(0.24 * mw, 0.13, 0.04), stub, "SmoothPlastic", "CornerSkin")
	end
	-- середина верхней губы (с «луком Купидона»), шов губ и желобок
	local ulPivot = H(0, my + 0.04, mz)
	rig:joint("UpperLip", "Head", ulPivot, ulPivot, v(0.05, 0.05, 0.05))
	ell("UpperLip", Hc(0, my + 0.017, surfZ(0, my + 0.017) - 0.01), v(0.19 * mw, 0.044, 0.054), lipC, "SmoothPlastic", "UpperLip")
	for _, s in { 1, -1 } do
		ell("UpperLip", Hc(s * 0.036 * mw, my + 0.028, surfZ(s * 0.036, my + 0.028) - 0.006) * ang(0, 0, s * -14), v(0.09 * mw, 0.03, 0.04), lipC, "SmoothPlastic", "UpperLipBow")
	end
	ell("UpperLip", Hc(0, my - 0.002, mz - 0.028), v(0.17 * mw, 0.01, 0.03), mouthDark, "SmoothPlastic", "LipSeam")
	ell("UpperLip", Hc(0, my + 0.07, surfZ(0, my + 0.07) + 0.012), v(0.07, 0.08, 0.03), skinShade:Lerp(skin, 0.6), "SmoothPlastic", "Philtrum")
	-- уголки: края верхней губы, кожа снаружи уголка (закрывает полость при раскрытом рте), складка
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local cx = s * cw
		local mp = H(cx, my, surfZ(cx, my))
		local mj = side .. "Mouth"
		rig:joint(mj, "Head", mp, mp, v(0.05, 0.05, 0.05))
		local ex = s * (cw - 0.055 * mw)
		ell(mj, Hc(ex, my + 0.014, surfZ(ex, my + 0.014) - 0.014) * ang(0, -s * 14, -s * 9), v(0.11 * mw, 0.034, 0.046), lipC, "SmoothPlastic", "UpperLipSide")
		-- щека сбоку от рта (неподвижна; у края проёма уходит за полость — край проёма не шире ±0.16)
		-- сбоку от рта (неподвижно; форма подобрана по глубине: у края проёма уходит за полость, проём не шире ±0.13)
		sk("Head", v(s * 0.1626 * mw, -0.3104, -0.2102), v(0.4335 * mw, 0.38, 0.704), stub, "MouthSide", v(-23.6, s * 9.39, -s * 1.18))
		ell(mj, onFace(cx + s * 0.012, my + 0.004, -0.003) * ang(0, 0, s * 60), v(0.04, 0.011, 0.02), skinShade:Lerp(skin, 0.3), "SmoothPlastic", "CornerCrease")
	end

	-- ----- борода-щетина -----
	-- Короткая густая борода облегает лицо: челюсть, подбородок и низ челюсти — цвета щетины целиком (см. выше),
	-- на щеках — «оболочки» кожи (beardShell), граница — одна чистая диагональ от бакенбарды к уголку рта
	-- в два тона (светлая кромка выше), усы — тонкий тёмный слой над губой, бакенбарды — тонко по черепу.
	if beardOn then
		local must = stubD:Lerp(o.beard, 0.25)
		for _, s in { 1, -1 } do
			-- бакенбарда: тонкий слой по поверхности черепа перед ухом (соединяет причёску и щетину)
			ell("Head", Hc(s * 0.508, -0.02, -0.04) * ang(0, s * -16, s * 4), v(0.05, 0.44, 0.16), stub:Lerp(o.hair, 0.4), "SmoothPlastic", "Sideburn")
			-- усы: от середины к уголкам рта (плоско, в цвет бороды, темнее щёк)
			ell("UpperLip", Hc(s * 0.062, my + 0.062, surfZ(s * 0.062, my + 0.062) - 0.004) * ang(0, -s * 10, s * -10), v(0.17, 0.05, 0.016), must, "SmoothPlastic", "Moustache")
			ell(if s > 0 then "RightMouth" else "LeftMouth", Hc(s * (cw - 0.01), my + 0.036, surfZ(s * (cw - 0.01), my + 0.036) - 0.003) * ang(0, -s * 18, s * -30), v(0.09, 0.036, 0.014), must, "SmoothPlastic", "Moustache")
		end
	end

	-- ===== Причёски =====
	local hairC = o.hair
	local style = o.hairStyle
	local function shade(c, k)
		return if k >= 0 then c:Lerp(WHITE, k) else c:Lerp(BLACK, -k)
	end
	local HC0 = H(0, 0.1, 0.06) -- центр черепа
	-- прядь-эллипсоид от a до b шириной w и толщиной t, плоской стороной к голове
	local function lock(a, b, w, t, color, name, out, ext)
		local dir = b - a
		local Y = dir.Unit
		local ov = out or ((a + b) / 2 - HC0).Unit
		local Z = ov - Y * ov:Dot(Y)
		if Z.Magnitude < 1e-3 then
			Z = v(0, 0, -1)
		end
		Z = Z.Unit
		local X = Y:Cross(Z)
		return ell("Head", CFrame.fromMatrix((a + b) / 2, X, Y, Z), v(w, dir.Magnitude + (ext or w * 0.3), t), color, "SmoothPlastic", name)
	end
	-- точка на «оболочке» причёски: phi — градусы вокруг головы (0 — лицо, +90 — правое ухо), y — высота (от центра головы)
	local function hp(phi, y, rx, rz, cy, push)
		local p = rad(phi)
		local b = 0.68
		local dy = (y - (cy or 0.1)) / b
		local r = if dy > 0 then math.sqrt(math.max(0, 1 - dy * dy)) else math.max(0.86, math.sqrt(math.max(0, 1 - dy * dy)))
		r += push or 0
		return H(math.sin(p) * rx * r, y, 0.06 - math.cos(p) * rz * r)
	end
	if style == "quiff" then
		-- зачёс назад (помпадур): короткие тёмные виски и затылок — тонкая «оболочка» по черепу выше и позади уха
		-- (перед ухом — бакенбарда, на висках — залысины), объём сверху несёт основа «Quiff»; поверх — 4 широкие
		-- плоские пряди от линии роста вверх-вперёд к вершине кока и назад к макушке (почти без перепада тона).
		local fade = hairC:Lerp(skin, 0.14)
		local sideC = hairC:Lerp(skin, 0.05)
		ell("Head", Hc(0, 0.08, 0.24) * ang(12, 0, 0), v(cran.X + 0.02, cran.Y - 0.3, cran.Z - 0.3), fade, "SmoothPlastic", "HairFade")
		ell("Head", Hc(0, 0.14, 0.2), v(cran.X + 0.02, cran.Y - 0.2, cran.Z - 0.01), sideC, "SmoothPlastic", "HairSides")
		ell("Head", Hc(0, 0.42, 0.08), v(cran.X - 0.06, 0.62, cran.Z), hairC, "SmoothPlastic", "HairTop")
		-- объём кока надо лбом (основа под прядями)
		ell("Head", Hc(0, 0.64, -0.2) * ang(-20, 0, 0), v(cran.X - 0.18, 0.5, 0.74), shade(hairC, -0.02), "SmoothPlastic", "Quiff")
		-- пряди: x — смещение от пробора, rise — высота кока; крайние пряди отступают назад (залысины)
		for i, q in { { -0.25, 0.07 }, { -0.085, 0.17 }, { 0.085, 0.17 }, { 0.25, 0.07 } } do
			local x, rise = q[1], q[2]
			local ax = math.abs(x)
			local p0 = H(x * 0.95, 0.46 - ax * 0.12, -0.45 + ax * 0.3) -- линия роста
			local p1 = H(x * 1.05, 0.66 + rise, -0.38 + ax * 0.16) -- вершина кока
			local p2 = H(x * 1.06, 0.66 + rise * 0.5 - ax * 0.15, 0.02)
			local p3 = H(x * 0.95, 0.5 - ax * 0.3, 0.44)
			local c = if i % 2 == 0 then shade(hairC, 0.02) else hairC
			local w = 0.44 + rise * 0.3
			lock(p0, p1, w, 0.08, c, "QuiffLock", v(x * 0.4, 0.2, -1).Unit, 0.03)
			lock(p1, p2, w + 0.02, 0.08, c, "QuiffLock", v(x * 0.6, 1, -0.3).Unit, 0.06)
			lock(p2, p3, w - 0.02, 0.08, shade(c, -0.02), "QuiffLock", v(x * 0.8, 1, 0.4).Unit, 0.06)
		end
	elseif style == "crop" then
		local fade = hairC:Lerp(skin, 0.3)
		ell("Head", Hc(0, 0.03, 0.15), cran + v(0.035, -0.12, -0.08), fade, "SmoothPlastic", "HairFade")
		ell("Head", Hc(0, 0.22, 0.1), cran + v(0.06, -0.22, -0.02), hairC:Lerp(skin, 0.08), "SmoothPlastic", "HairSides")
		ell("Head", Hc(0, 0.46, 0.04), v(1.14, 0.6, 1.16), hairC, "SmoothPlastic", "HairTop")
		ell("Head", Hc(0.06, 0.5, -0.4) * ang(-8, 0, -8), v(0.74, 0.22, 0.3), hairC, "SmoothPlastic", "Fringe")
	elseif style == "shag" or style == "bob" then
		-- «шэг» до плеч: каштановая масса крупными прядями (без «шлема»), густая чёлка до бровей из
		-- нескольких широких прядей, «шторки» у лица; светлые пряди (hairHighlight) — у лица справа и на
		-- концах; кончики отогнуты наружу (bob — внутрь)
		local hl = o.hairHighlight or shade(hairC, 0.35)
		-- двухтон (как в S07): макушка и чёлка пепельно-светлые, длина — темнее
		local crownC = o.hairCrown or hairC
		local dark = shade(hairC, -0.3)
		local mid = hairC:Lerp(hl, 0.3)
		local warm = hairC:Lerp(rgb(150, 92, 60), 0.35)
		local hsurf = {}
		local function hk(c, size, color, name, rot)
			local cf = CFrame.new(c) * (if rot then ang(rot.X, rot.Y, rot.Z) else CFrame.new())
			table.insert(hsurf, { cf = cf, inv = cf:Inverse(), a = size.X / 2, b = size.Y / 2, d = size.Z / 2 })
			return ell("Head", Hc(0, 0, 0) * cf, size, color, "SmoothPlastic", name)
		end
		local function hairZ(x, y)
			return math.min(frontZ(hsurf, x, y), surfZ(x, y))
		end
		local function hc0z(x, y)
			return surfZ(x, y)
		end
		-- точка на оболочке причёски: phi — градусы вокруг головы (0 — лицо, +90 — правое ухо)
		local function sp(phi, y, k)
			local p = rad(phi)
			local dy = (y - 0.12) / (0.66 + k)
			local r = if dy > 0 then math.sqrt(math.max(0, 1 - dy * dy)) else 1 - 0.08 * math.min(1, -dy)
			return H(math.sin(p) * (0.57 + k) * r, y, 0.08 - math.cos(p) * (0.62 + k) * r)
		end
		-- основа: масса по бокам и сзади, тёмный подслой на затылке, «шапка» сверху
		hk(v(0, -0.08, 0.14), v(cran.X + 0.14, 1.14, cran.Z + 0.1), hairC, "HairMass")
		-- изнанка «занавеса» (видна с нижних ракурсов): тёмная масса до низа прядей
		ell("Head", Hc(0, -0.38, 0.3), v(cran.X - 0.04, 0.66, 0.8), shade(hairC, -0.35), "SmoothPlastic", "HairUnder")
		hk(v(0, 0.16, 0.08), v(cran.X + 0.1, 1.17, cran.Z + 0.1), hairC:Lerp(crownC, 0.55), "HairCap")
		-- пряди макушки: несколько широких прядей от темени (лёгкая фактура, без «колбасок»)
		local crown = H(0.04, 0.74, 0.16)
		for i, phi in { -105, -60, 60, 105 } do
			local b2 = sp(phi, 0.42, 0.035)
			local c = if i % 2 == 0 then shade(hairC, 0.04) else shade(hairC, -0.04)
			lock(crown:Lerp(b2, 0.12), b2, 0.4, 0.08, crownC:Lerp(c, 0.25), "TopLock")
		end
		-- слои по бокам и сзади: широкие пряди от висков до низа, перекрываются
		for i, phi in { 66, 94, 122, 152, 180, -152, -122, -94, -66 } do
			local s = if phi >= 0 then 1 else -1
			local c = if i % 2 == 0 then shade(hairC, 0.05) else hairC
			if s > 0 and phi < 80 then
				c = hl:Lerp(hairC, 0.6) -- светлая прядь справа у лица
			end
			lock(sp(phi, 0.3, 0.03), sp(phi - s * 3, -0.36, 0.04), if math.abs(phi) < 80 then 0.24 else 0.3, 0.08, c, "SideLock")
		end
		-- низ: «юбка» из широких концов, отогнутых наружу (bob — подвёрнуты внутрь)
		local flip = if style == "bob" then -0.5 else 1
		local nEnd = 16
		for j = 0, nEnd - 1 do
			local phi = 74 + j * (212 / (nEnd - 1)) + (((j * 53) % 7) - 3) * 2 -- ±6° разброс
			local s = if phi <= 180 then 1 else -1
			local len = -0.5 - ((j * 37) % 5) * 0.055
			-- пряди почти вровень с массой (видны мягкими гребнями), концы отогнуты наружу
			local a2 = sp(phi, 0.0, 0.025)
			local b2 = sp(phi, len, 0.05 + 0.06 * flip)
			local c = hairC:Lerp(hl, if j % 3 == 0 then 0.12 else 0.05)
			if phi < 80 then
				c = hl:Lerp(hairC, 0.6)
			end
			lock(a2, b2, 0.34, 0.07, c, "End")
		end
		-- чёлка: четыре широкие пряди до бровей, концы неровные; одна — светлая
		local browTop = eyeY + eyeH * 0.5 + 0.125
		-- основа чёлки: плоские накладки цвета волос вровень со лбом (между прядями не просвечивает кожа)
		for _, x in { -0.25, 0, 0.25 } do
			ell("Head", onFace(x, browTop + 0.14, -0.008, x * -20), v(0.34, 0.28, 0.03), shade(crownC, -0.12), "SmoothPlastic", "FringeBase")
		end
		-- пряди чёлки: от линии роста к бровям, перекрываются, концы неровные; одна — светлая
		for i, x in { -0.33, -0.22, -0.11, 0.0, 0.11, 0.22, 0.33 } do
			local yb = browTop + (if i % 2 == 0 then 0.0 else 0.03) + math.abs(x) * 0.12
			local a2 = H(x * 0.6, 0.62, hairZ(x * 0.6, 0.62) + 0.01)
			local my2 = (0.62 + yb) / 2 + 0.04
			local m2 = H(x * 0.88, my2, hc0z(x * 0.88, my2) - 0.04)
			local b2 = H(x, yb, hc0z(x, yb + 0.05) - 0.026)
			local c = if i == 6 then hl:Lerp(crownC, 0.3) elseif i % 2 == 0 then shade(crownC, 0.04) else crownC
			lock(a2, m2, 0.2, 0.09, c, "Bang", v(0, 0.5, -1).Unit)
			lock(m2, b2, 0.18, 0.07, c, "Bang", v(0, 0.12, -1).Unit)
		end
		for _, s in { 1, -1 } do
			-- «шторки» у лица: от края чёлки к скулам и ниже (справа — светлая)
			local c = if s > 0 then hl:Lerp(hairC, 0.6) else shade(hairC, 0.06)
			lock(H(s * 0.39, 0.42, -0.34), H(s * 0.45, -0.38, -0.33), 0.2, 0.09, c, "Curtain", v(s * 0.75, 0.1, -1).Unit)
		end
	elseif style == "curls" then
		-- пышная копна кудрей (≈1.4 ширины головы): тёмная основа (просветы читаются как волосы) + завитки-«запятые»
		-- разного размера, пропорций и наклона (точки Фибоначчи по оболочке), кудри закрывают верх ушей и
		-- спускаются к затылку, у лба и над ушами — свисающие завитки и колечки
		local base = shade(hairC, -0.24)
		ell("Head", Hc(0, 0.22, 0.24), v(cran.X + 0.28, cran.Y + 0.02, cran.Z + 0.08), base, "SmoothPlastic", "HairBase")
		ell("Head", Hc(0, -0.08, 0.26), v(cran.X + 0.22, 0.8, cran.Z - 0.06), base, "SmoothPlastic", "HairBack")
		local function rnd(i, k)
			local x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
			return x - math.floor(x)
		end
		local C0 = H(0, 0.2, 0.1)
		local function curl(i, p, d, sz, c)
			-- завиток: вытянутая вдоль «потока» (вниз по голове, ±35°) прядь + колечко на конце
			local up = if math.abs(d.Y) > 0.95 then v(1, 0, 0) else v(0, 1, 0)
			local X = up:Cross(d).Unit
			local Y = d:Cross(X)
			local cf = CFrame.fromMatrix(p, X, Y, d) * ang(0, 0, (rnd(i, 3) - 0.5) * 80)
			local ax = 0.6 + 0.8 * rnd(i, 7) -- разброс пропорций
			ell("Head", cf, v(sz * 0.8 * ax, sz * 1.25, sz * 0.55), c, "SmoothPlastic", "Curl")
			ell("Head", cf * at((rnd(i, 6) - 0.5) * sz * 0.4, -sz * 0.52, -sz * 0.08), v(sz * 0.62, sz * 0.5, sz * 0.5), shade(c, 0.04), "SmoothPlastic", "Curl")
		end
		local n = 150
		for i = 0, n - 1 do
			local yN = 1 - (i + 0.5) / n * 2
			local r = math.sqrt(1 - yN * yN)
			local th = i * 2.39996
			local d = v(math.sin(th) * r, yN, -math.cos(th) * r)
			local fr = -d.Z
			local skip = (fr > 0.62 and d.Y < 0.15) or (fr > 0.35 and d.Y < -0.3) or d.Y < -0.8
			if not skip then
				-- оболочка: широкая по бокам и сзади, над лбом — ближе к голове
				local R = v(0.76, if d.Y > 0 then 0.74 else 0.8, if d.Z < 0 then 0.64 else 0.8)
				local p = C0 + v(d.X * R.X, d.Y * R.Y, d.Z * R.Z) * (0.97 + 0.08 * rnd(i, 1))
				local sz = 0.12 + 0.17 * rnd(i, 2)
				local lit = math.clamp(d.Y, 0, 1) * 0.05
				local c = if rnd(i, 4) < 0.35 then shade(hairC, -0.1 + lit) else shade(hairC, lit + 0.04 * rnd(i, 5))
				curl(i, p, d, sz, c)
			end
		end
		-- завитки, падающие на лоб (асимметрично, больше на правую сторону)
		for i, q in { { -0.3, 0.38, -0.5 }, { -0.14, 0.4, -0.55 }, { 0.03, 0.39, -0.56 }, { 0.2, 0.36, -0.54 }, { 0.35, 0.3, -0.47 }, { 0.11, 0.31, -0.57 }, { -0.06, 0.32, -0.57 } } do
			local p = H(q[1], q[2], q[3])
			local d = v(q[1] * 0.8, 0.25, -1).Unit
			curl(200 + i, p, d, 0.17 + (i % 3) * 0.03, shade(hairC, 0.04 * (i % 2)))
		end
		-- кудри у висков и щёк (рамка лица): закрывают гладкую основу сбоку от лица
		for _, sx in { 1, -1 } do
			for k = 0, 6 do
				local yy = 0.3 - k * 0.09
				local zz = -0.3 + 0.05 * k + 0.05 * rnd(k + (sx > 0 and 0 or 20), 11)
				local xx = sx * (0.5 + 0.03 * k + 0.04 * rnd(k, 12))
				local d = v(sx * 0.75, -0.25, -0.6).Unit
				curl(400 + k + (if sx > 0 then 0 else 10), H(xx, yy, zz), d, 0.15 + 0.07 * rnd(k, 13 + sx), shade(hairC, -0.06 + 0.08 * rnd(k, 14)))
			end
		end
		-- свисающие колечки над ушами и на затылке
		for k = 0, 7 do
			local phi = rad(62 + k * (236 / 7))
			local p = H(math.sin(phi) * 0.62, -0.3 - 0.06 * rnd(k, 9), 0.12 - math.cos(phi) * 0.6)
			local d = v(math.sin(phi) * 0.4, -1, -math.cos(phi) * 0.4).Unit
			curl(300 + k, p, d, 0.17 + 0.06 * rnd(k, 8), shade(hairC, -0.04 + 0.06 * rnd(k, 10)))
		end
	elseif style == "bun" then
		ell("Head", Hc(0, 0.36, 0.06), v(1.2, 0.86, 1.24), hairC, "SmoothPlastic", "HairTop")
		ell("Head", Hc(0, 0.06, 0.16), cran + v(0.05, -0.3, -0.04), hairC, "SmoothPlastic", "HairSides")
		ell("Head", Hc(0, 0.52, -0.38) * ang(20, 0, 0), v(0.9, 0.26, 0.36), shade(hairC, 0.08), "SmoothPlastic", "HairFront")
		ball("Head", H(0, 0.56, 0.6), 0.44, shade(hairC, -0.08), "SmoothPlastic", "Bun")
		ell("Head", Hc(0, 0.5, 0.44) * ang(40, 0, 0), v(0.3, 0.1, 0.3), rgb(30, 30, 34), "SmoothPlastic", "HairTie")
		for _, s in { 1, -1 } do
			lock(H(s * 0.44, 0.3, -0.38), H(s * 0.5, -0.2, -0.3), 0.07, 0.05, hairC, "LooseStrand", v(s * 0.5, 0, -1).Unit)
		end
	end

	-- ===== Серьги =====
	if o.earrings then
		for _, s in { 1, -1 } do
			local lobe = H(s * (headHW + 0.045), -0.19, 0.08)
			if o.earrings == "hoop" then
				local r0 = o.hoopR or 0.1
				local c = lobe + v(s * 0.01, -r0 + 0.02, 0)
				local nseg = 12
				for i = 0, nseg - 1 do
					local a0 = (i / nseg) * math.pi * 2
					local a1 = ((i + 1) / nseg) * math.pi * 2
					local p0 = c + v(0, math.cos(a0) * r0, math.sin(a0) * r0)
					local p1 = c + v(0, math.cos(a1) * r0, math.sin(a1) * r0)
					stick("Head", p0, p1, 0.022, o.earringColor, "Metal", "Hoop")
				end
			else
				ball("Head", lobe + v(s * 0.012, -0.0, -0.01), 0.055, o.earringColor, "Metal", "Stud")
			end
		end
	end

	-- ===== Цепочки и шнурки на шее =====
	if o.necklaces then
		local frontZ = -(td + (if topStyle and topStyle ~= "crop" then pad else 0)) / 2
		if cropped then
			frontZ = -D / 2
		end
		local function bulge(y)
			-- выступ груди (у девушек) на высоте y
			if not fem then
				return 0
			end
			local dy = (y - bustY) / (0.22 * h)
			if math.abs(dy) >= 1 then
				return 0
			end
			return math.max(0, bustOut * math.sqrt(1 - dy * dy) - 0.01)
		end
		for idx, nk in o.necklaces do
			local col = nk.color or rgb(220, 220, 225)
			local mat = if nk.kind == "chain" then "Metal" else "SmoothPlastic"
			local d = if nk.thin then 0.02 elseif nk.kind == "cord" then 0.03 else 0.022
			if nk.choker then
				-- чокер вокруг шеи (на голове — шея принадлежит Head); kind = "beads" — бусины
				local nr = neckD / 2 + 0.014
				local c = H(0, -0.56, 0.06)
				local nseg = 14
				for i = 0, nseg - 1 do
					local a0 = (i / nseg) * math.pi * 2
					local a1 = ((i + 1) / nseg) * math.pi * 2
					local p0 = c + v(math.sin(a0) * nr, -0.02 * math.cos(a0), -math.cos(a0) * nr)
					local p1 = c + v(math.sin(a1) * nr, -0.02 * math.cos(a1), -math.cos(a1) * nr)
					if nk.kind == "beads" then
						local bc = if i % 3 == 0 then (nk.accent or col) else col
						ball("Head", p0, 0.048, bc, "SmoothPlastic", "Bead")
					else
						stick("Head", p0, p1, d, col, mat, "Choker")
					end
				end
				if nk.pendant then
					ball("Head", c + v(0, -0.07, -nr - 0.02), 0.06, nk.pendantColor or col, "Metal", "Charm")
				end
			else
				local len = (nk.len or 0.5) * h
				local lift = (idx - 1) * 0.015
				local pts = {}
				local function zf(y, extra)
					return frontZ - 0.03 - bulge(y) - (extra or 0)
				end
				local yLow = yN - len
				local pathL = {
					v(0, yN + 0.1 + lift, 0.3),
					v(0.26, yN + 0.12 + lift, 0.14),
					v(0.31, yN + 0.08 + lift, -0.12),
					v(0.29, yN + 0.0, zf(yN)),
					v(0.22, yN - len * 0.35, zf(yN - len * 0.35)),
					v(0.12, yN - len * 0.75, zf(yN - len * 0.75)),
					v(0, yLow, zf(yLow)),
				}
				for i = #pathL, 1, -1 do
					local p = pathL[i]
					table.insert(pts, v(-p.X, p.Y, p.Z))
				end
				for i = 2, #pathL do
					table.insert(pts, pathL[i])
				end
				for i = 1, #pts - 1 do
					stick("UpperTorso", pts[i], pts[i + 1], d, col, mat, "Necklace")
				end
				for i = 2, #pts - 1 do
					if pts[i].Z < -0.2 then
						ball("UpperTorso", pts[i], d * 1.02, col, mat, "NecklaceJoint")
					end
				end
				if nk.pendant == "coin" then
					part("UpperTorso", CFrame.new(v(0, yLow - 0.065, zf(yLow - 0.065, 0.005))) * ang(0, 90, 0), v(0.025, 0.13, 0.13), nk.pendantColor or col, "Metal", "Pendant", { shape = "Cylinder" })
				elseif nk.pendant == "drop" then
					ball("UpperTorso", v(0, yLow - 0.05, zf(yLow - 0.05, 0.01)), 0.07, nk.pendantColor or col, "Metal", "Pendant")
				elseif nk.pendant == "cross" then
					part("UpperTorso", CFrame.new(v(0, yLow - 0.07, zf(yLow - 0.07, 0.005))), v(0.03, 0.12, 0.02), nk.pendantColor or col, "Metal", "Pendant")
					part("UpperTorso", CFrame.new(v(0, yLow - 0.05, zf(yLow - 0.05, 0.005))), v(0.08, 0.03, 0.02), nk.pendantColor or col, "Metal", "Pendant")
				end
			end
		end
	end

	-- ===== Солнцезащитные очки на суставе Glasses =====
	if o.glasses then
		local gHome = H(0, 0.0, -R - 0.075) -- переносица
		local gcf
		local gBone = o.glassesOn or "Head"
		if gBone == "Head" then
			gcf = CFrame.new(gHome)
		else
			-- в руке: дужка зажата между большим и указательным, стёкла смотрят вперёд, очки висят к центру тела
			local s = if gBone == "RightHand" then 1 else -1
			local wY = P.shoulderY - P.upperArm - P.lowerArm
			local pinch = v(s * (P.shoulderX - 0.05), wY - P.handLen - 0.12, -pw * 0.5 - 0.06)
			gcf = CFrame.new(pinch) * CFrame.new(-s * 0.45, -0.06, 0)
		end
		rig:joint("Glasses", gBone, gcf.Position, gcf.Position, v(0.1, 0.06, 0.06))
		local frame = o.glassesFrame
		local lens = o.glassesLens
		local lensT = o.glassesLensTransparency
		local kind = o.glasses
		local metalFrame = kind == "aviator"
		local fmat = if metalFrame then "Metal" else "SmoothPlastic"
		local function L(x, y, z)
			return gcf * CFrame.new(x, y, z)
		end
		local templeX = 0.42
		-- хорда многоугольника pts на высоте y: (xmin, xmax) (локально, x — наружу от носа)
		local function chord(pts, y)
			local lo, hi = math.huge, -math.huge
			for i = 1, #pts do
				local a, b = pts[i], pts[i % #pts + 1]
				if (a[2] - y) * (b[2] - y) <= 0 and a[2] ~= b[2] then
					local x = a[1] + (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2])
					lo, hi = math.min(lo, x), math.max(hi, x)
				end
			end
			return lo, hi
		end
		-- стекло: ряды-полосы из настоящего стекла (SpecialMesh не показывает материал), впритык друг к другу;
		-- ширина ряда — наименьшая хорда оправы по высоте ряда минус зазор (углы не вылезают за ободок)
		local function lensRows(cf, s, pts, y0, y1, n, gap, extra)
			local hgt = (y1 - y0) / n
			for k = 0, n - 1 do
				local ya, yb = y0 + k * hgt, y0 + (k + 1) * hgt
				local lo, hi = -math.huge, math.huge
				for _, yy in { ya, (ya + yb) / 2, yb } do
					local l, r = chord(pts, yy)
					lo, hi = math.max(lo, l), math.min(hi, r)
				end
				local w = hi - lo - gap
				if w > 0.03 then
					part("Glasses", cf * at(s * (lo + hi) / 2, (ya + yb) / 2, 0), v(w, hgt, 0.016), lens, "Glass", "Lens", extra)
				end
			end
		end
		-- контур оправы: палочки по точкам (локально: x — наружу от носа, y — вверх)
		local function loop(cf, s, pts, d, z)
			for i = 1, #pts do
				local p0, p1 = pts[i], pts[i % #pts + 1]
				local a0 = cf * v(s * p0[1], p0[2], z)
				local a1 = cf * v(s * p1[1], p1[2], z)
				local dir = (a1 - a0).Unit
				stick("Glasses", a0 - dir * d * 0.35, a1 + dir * d * 0.35, d, frame, fmat, "Rim")
			end
		end
		for _, s in { 1, -1 } do
			local lx = s * 0.235
			local yawL = -s * 9
			local c1 = L(lx, 0.0, 0.0) * ang(0, yawL, 0)
			if kind == "aviator" then
				-- «капля»: широкий верх, низ провисает ближе к виску, к носу сужается
				local pts = {
					{ -0.165, 0.085 }, { -0.09, 0.105 }, { 0.0, 0.11 }, { 0.09, 0.108 }, { 0.165, 0.09 }, { 0.185, 0.04 }, { 0.186, -0.02 },
					{ 0.166, -0.08 }, { 0.122, -0.13 }, { 0.05, -0.158 }, { -0.02, -0.156 }, { -0.08, -0.13 }, { -0.13, -0.07 }, { -0.16, 0.0 },
				}
				lensRows(c1, s, pts, -0.15, 0.104, 5, 0.02, { reflectance = 0.25, transparency = lensT })
				ell("Glasses", c1 * at(s * 0.01, -0.022, 0.006), v(0.33, 0.235, 0.014), lens, "SmoothPlastic", "LensBack", { reflectance = 0.3 })
				loop(c1, s, pts, 0.017, -0.003)
			elseif kind == "round" then
				-- овальные линзы (круглые «ретро»), тонкая оправа
				local pts = {}
				for k = 0, 21 do
					local t = k / 22 * math.pi * 2
					table.insert(pts, { 0.17 * math.cos(t), 0.13 * math.sin(t) })
				end
				lensRows(c1, s, pts, -0.11, 0.11, 5, 0.012, { reflectance = 0.2, transparency = lensT })
				ell("Glasses", c1 * at(0, 0, 0.006), v(0.32, 0.24, 0.014), lens, "SmoothPlastic", "LensBack", { transparency = math.min(0.6, lensT) })
				loop(c1, s, pts, 0.024, 0)
				templeX = 0.41
			elseif kind == "hex" then
				-- «геометрическая» восьмиугольная оправа
				local pts = { { -0.17, 0.04 }, { -0.13, 0.1 }, { 0.13, 0.1 }, { 0.17, 0.04 }, { 0.17, -0.04 }, { 0.13, -0.1 }, { -0.13, -0.1 }, { -0.17, -0.04 } }
				part("Glasses", c1, v(0.3, 0.17, 0.02), lens, "Glass", "Lens", { transparency = lensT, reflectance = 0.2 })
				loop(c1, s, pts, 0.034, 0)
				templeX = 0.41
			else -- rect
				local pts = { { -0.165, 0.075 }, { 0.165, 0.075 }, { 0.165, -0.085 }, { -0.165, -0.085 } }
				part("Glasses", c1 * at(0, -0.005, 0), v(0.31, 0.14, 0.02), lens, "Glass", "Lens", { transparency = lensT, reflectance = 0.2 })
				loop(c1, s, pts, 0.032, 0)
				templeX = 0.41
			end
			-- дужки до ушей
			local hinge = gcf * v(s * templeX, 0.05, 0.03)
			local ear = gcf * v(s * (headHW + 0.04), 0.04, 0.72)
			stick("Glasses", hinge, ear, 0.026, frame, fmat, "Temple")
			stick("Glasses", ear, gcf * v(s * (headHW + 0.02), -0.07, 0.8), 0.026, frame, fmat, "TempleTip")
			-- носоупоры
			ball("Glasses", gcf * v(s * 0.075, -0.07, 0.04), 0.022, frame, fmat, "NosePad")
		end
		-- мостик (у авиаторов двойной)
		stick("Glasses", gcf * v(-0.085, 0.03, -0.005), gcf * v(0.085, 0.03, -0.005), 0.026, frame, fmat, "Bridge")
		if kind == "aviator" then
			stick("Glasses", gcf * v(-0.12, 0.095, 0.0), gcf * v(0.12, 0.095, 0.0), 0.022, frame, fmat, "TopBar")
		end
	end

	-- ===== Контрольные точки для аниматоров =====
	rig.headCenter = H(0, 0, 0)
	rig.glassesHome = H(0, 0.0, -R - 0.075)

	-- ===== Лицевые каналы =====
	local rimT = if o.lashes then 0.04 else 0.03
	local blinkD = eyeH + rimT * 0.75 -- веко от покоя до низа глаза
	local function pair(jr, jl, pos, rot)
		local out = { joint = jr, pos = pos, rot = rot }
		local m = { joint = jl, pos = if pos then v(-pos.X, pos.Y, pos.Z) else nil, rot = if rot then v(rot.X, -rot.Y, -rot.Z) else nil }
		return out, m
	end
	local function list(...)
		local t = {}
		for _, e in { ... } do
			table.insert(t, e)
		end
		return t
	end
	local function both(jr, jl, pos, rot)
		return pair(jr, jl, pos, rot)
	end
	local sr1, sl1 = both("RightMouth", "LeftMouth", v(0.045, 0.045, -0.02), v(0, 0, 12))
	local sr2, sl2 = both("RightLowerLip", "LeftLowerLip", v(0.045, 0.045, -0.02), v(0, 0, 26))
	-- при раскрытии челюсти внутренние концы нижней губы опускаются вслед за серединой (уголки на месте)
	-- (и уходят назад за кожу: при широко раскрытом рте видны только середина губы и кожа у уголков)
	local jr2, jl2 = both("RightLowerLip", "LeftLowerLip", v(0, -0.012, 0.11), v(0, 0, 36))
	local jr3, jl3 = both("RightCornerSkin", "LeftCornerSkin", v(0, 0, -0.126), nil)
	-- щёки при улыбке поднимаются и выходят вперёд (у бородатых — почти не выходят: щетина скрывает щёку,
	-- а выпуклое «яблочко» в щетине читается как тёмный шар)
	local sr3, sl3 = both("RightCheek", "LeftCheek", if beardOn then v(0.008, 0.03, -0.03) else v(0.012, 0.045, -0.056), nil)
	-- кожа у уголков при улыбке не выходит вперёд вместе с краем губы (иначе вздувается поверх щеки)
	local sr4, sl4 = both("RightCornerSkin", "LeftCornerSkin", v(0, 0, 0.03), nil)
	local or1, ol1 = both("RightMouth", "LeftMouth", v(-0.035 * mw, -0.02, -0.01), v(0, 0, -14))
	local or2, ol2 = both("RightLowerLip", "LeftLowerLip", v(-0.035 * mw, -0.02, 0), v(0, 0, -10))
	-- кожа у уголков при «О» расходится вниз-наружу: проём — овал до самой нижней губы
	local or3, ol3 = both("RightCornerSkin", "LeftCornerSkin", v(0.04, -0.03, 0), v(0, 0, -12))
	rig.face = {
		jaw = list({ joint = "Jaw", rot = v(-9.5, 0, 0), pos = v(0, -0.012, -0.05) }, { joint = "Mouth", pos = v(0, -0.006, -0.004) }, jr2, jl2, jr3, jl3),
		smile = list(
			sr1, sl1, sr2, sl2, sr3, sl3, sr4, sl4,
			{ joint = "UpperLip", pos = v(0, 0.026, -0.006) },
			{ joint = "Jaw", pos = v(0, 0, -0.01) },
			{ joint = "RightLid", pos = v(0, eyeH * 0.22, 0.02) },
			{ joint = "LeftLid", pos = v(0, eyeH * 0.22, 0.02) },
			{ joint = "RightLowerLid", pos = v(0, eyeH * 0.4, -LL_OUT) },
			{ joint = "LeftLowerLid", pos = v(0, eyeH * 0.4, -LL_OUT) }
		),
		oh = list(or1, ol1, or2, ol2, or3, ol3, { joint = "UpperLip", pos = v(0, 0.04, -0.016) }, { joint = "Jaw", rot = v(-4, 0, 0), pos = v(0, 0, -0.026) }, { joint = "Mouth", pos = v(0, 0.035, 0.006) }),
		brows = { { joint = "RightBrow", pos = v(0, 0.06, 0), rot = v(0, 0, -4) }, { joint = "LeftBrow", pos = v(0, 0.06, 0), rot = v(0, 0, 4) } },
		browR = { { joint = "RightBrow", pos = v(0, 0.06, 0), rot = v(0, 0, -4) } },
		browL = { { joint = "LeftBrow", pos = v(0, 0.06, 0), rot = v(0, 0, 4) } },
		frown = { { joint = "RightBrow", pos = v(-0.012, -0.025, 0), rot = v(0, 0, 12) }, { joint = "LeftBrow", pos = v(0.012, -0.025, 0), rot = v(0, 0, -12) } },
		blink = { { joint = "RightLid", pos = v(0, -blinkD, -0.074) }, { joint = "LeftLid", pos = v(0, -blinkD, -0.074) } },
		squint = {
			{ joint = "RightLid", pos = v(0, -eyeH * 0.14, -0.06) },
			{ joint = "LeftLid", pos = v(0, -eyeH * 0.14, -0.06) },
			{ joint = "RightLowerLid", pos = v(0, eyeH * 0.2, -LL_OUT * 0.5) },
			{ joint = "LeftLowerLid", pos = v(0, eyeH * 0.2, -LL_OUT * 0.5) },
		},
		lookX = { { joint = "RightEye", rot = v(0, -22, 0) }, { joint = "LeftEye", rot = v(0, -22, 0) } },
		lookY = { { joint = "RightEye", rot = v(18, 0, 0) }, { joint = "LeftEye", rot = v(18, 0, 0) } },
	}

	return rig
end
