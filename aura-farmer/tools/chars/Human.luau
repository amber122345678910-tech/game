--!nocheck
-- Человек в стиле Roblox: блочное R15-тело с мягкими фасками (скруглённые рёбра), кисти с пальцами,
-- «динамическая» лепная голова (череп + лицо + челюсть + щёки из эллипсоидов), глаза (белок/радужка/зрачок/блики)
-- на суставах взгляда, верхние/нижние веки (моргание, прищур, «смеющиеся» глаза), брови на суставах, нос,
-- губы, рот на суставе Jaw (открывается в «О» и в смех с зубами). Одежда и причёски собираются из примитивов
-- по опциям (см. DEFAULTS). Использование: require("./Human")(opts).
--
-- КОНТРАКТ ДЛЯ АНИМАТОРОВ
--   Пальцы: R15 + Right/Left Index1/2, Middle1/2, Ring1/2, Pinky1/2, Thumb1/2 (rHand/lHand в ключах; по умолчанию "relaxed").
--   Доп. суставы головы: Jaw (нижняя челюсть, губа, подбородок, щетина), Mouth (полость рта и верхние зубы),
--     UpperLip (верхняя губа + усы), RightMouth/LeftMouth (уголки рта), RightCheek/LeftCheek (щёки),
--     RightBrow/LeftBrow, RightLid/LeftLid (верхние веки), RightLowerLid/LeftLowerLid, RightEye/LeftEye (взгляд),
--     Glasses (если есть очки).
--   Центр головы (поза покоя): y = neckY + 0.74·height (neckY = 4.05·height), переносица очков — (0, y, f = 0.675).
--   Лицевые каналы (face = {...}):
--     jaw 0..1 (рот открыт), smile 0..1 (улыбка: уголки вверх/в стороны, щёки вверх, «смеющиеся» глаза),
--     oh 0..1 (губы в «О»), brows -1..1 (обе брови вверх+/вниз-), browR/browL, frown 0..1 (сведённые брови),
--     blink 0..1, squint 0..1, lookX -1..1 (взгляд вправо от персонажа +), lookY -1..1 (вверх +).
--     «Ах!» (awe):  face = { jaw = 0.7, oh = 1, brows = 1 };  смех: face = { jaw = 0.8, smile = 1, squint = 0.3 }.
--   Очки: joints = { Glasses = { x, y, f, rx, ry, rz } } — смещение от позы покоя (на носу) в осях головы;
--     «спустить на кончик носа»: { y = -0.13, f = 0.05, rx = -13 }. opts.glassesOn = "RightHand"/"LeftHand" — очки в руке.

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
	beard = nil, -- Color3 короткой бороды-щетины (челюсть, подбородок, усы)
	nose = 1.0, -- масштаб носа
	-- волосы
	hair = rgb(60, 42, 30),
	hairStyle = "quiff", -- "quiff" | "shag" | "curls" | "bun" | "crop" | "bob" | nil
	hairHighlight = nil, -- светлые пряди у лица (shag)
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
	glasses = nil, -- "aviator" | "hex" | "rect"
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
		hipY = 2.05 * h,
		kneeY = 1.04 * h,
		ankleY = 0.26 * h,
		footLen = (if fem then 0.92 else 1.02) * bw,
		footFwd = (if fem then 0.6 else 0.66) * bw,
		footW = 0.8,
		pelvisY = 2.25 * h,
		waistY = 2.45 * h,
		neckY = 4.05 * h,
		shoulderX = tw / 2 + aw / 2 + 0.02,
		shoulderY = 3.86 * h,
		upperArm = 1.06 * h,
		lowerArm = 0.98 * h,
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
		part(bone, cf, v(sx, sy, sz - 2 * r), color, mat, name)
		part(bone, cf, v(sx - 2 * r, sy - 0.024, sz), color, mat, name)
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
	local waistTop = yW + (if cropped then 0.1 else 0.2) * h -- верх пояса низа
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
		rboxY("UpperTorso", 0, hem, yN + 0.014, 0, math.max(tw, hipW) + pad, D, rT, topC, "Fabric", "Shirt")
		local fz = -D / 2
		ell("UpperTorso", at(0, yN + 0.004, fz - 0.008), v(0.5 * bw, 0.18, 0.024), skin, "SmoothPlastic", "Neckline")
		ell("UpperTorso", at(0, yN + 0.012, fz - 0.004), v(0.6 * bw, 0.26, 0.026), topC:Lerp(BLACK, 0.12), "SmoothPlastic", "Collar")
		part("UpperTorso", at(0, yN + 0.016, 0.04), v(0.5 * bw, 0.02, td * 0.62), skin, "SmoothPlastic", "NeckTop")
	elseif topStyle == "tank" or topStyle == "crop" then
		-- so — наружный край бретели, si — внутренний (полуширина выреза), ya — низ проймы
		local so, si, ya, scoopF, scoopB, hem
		local ah = o.armhole
		if cropped then
			so, si, ya, scoopF, scoopB = 0.4 * bw, 0.25 * bw, yN - (0.5 + 0.2 * ah) * h, 0.075, 0.1
			hem = chestBot - 0.03
		elseif fem then
			so, si, ya, scoopF, scoopB = 0.52 * bw, 0.31 * bw, yN - (0.55 + 0.35 * ah) * h, o.scoop * 0.85 * h, 0.22 * h
			hem = waistTop - 0.06 -- заправлена в пояс
		else
			so, si, ya, scoopF, scoopB = 0.6 * bw, 0.35 * bw, yN - (0.62 + 0.45 * ah) * h, o.scoop * h, 0.26 * h
			hem = yW - 0.14 -- навыпуск поверх шорт
		end
		local W = (if fem then tw else math.max(tw, hipW)) + pad
		local Dt = if fem then D else D + 0.02
		local rS = 0.17 * bw
		-- нижняя оболочка: от подола до проймы
		rboxY("UpperTorso", 0, hem, ya + 0.016, 0, W, Dt, rS, topC, "Fabric", "Shirt")
		if cropped then
			-- кант по низу
			rboxY("UpperTorso", 0, hem - 0.006, hem + 0.05, 0, W + 0.014, Dt + 0.014, rS + 0.007, topC:Lerp(BLACK, 0.06), "Fabric", "Hem")
		end
		-- верх: перёд и спина до линии выреза, бретели, проймы (две ступени клиньев — плавная дуга)
		local yS_f, yS_b = yN - scoopF, yN - scoopB
		local dUf = math.min(scoopF * 0.7, si * 0.85)
		local dUb = math.min(scoopB * 0.7, si * 0.85)
		local cYf, cYb = yS_f + dUf, yS_b + dUb -- центры «U»-выреза
		local top = yN + 0.014
		part("UpperTorso", at(0, (ya + cYf) / 2, -Dt / 4), v(2 * so, cYf - ya, Dt / 2), topC, "Fabric", "ShirtFront")
		part("UpperTorso", at(0, (ya + cYb) / 2, Dt / 4), v(2 * so, cYb - ya, Dt / 2), topC, "Fabric", "ShirtBack")
		local strapBot = math.min(cYf, cYb) - 0.02
		local edge = W / 2 - rS
		local xm = so + (edge - so) * 0.22
		local ym = ya + (top - ya) * 0.42
		for _, s in { 1, -1 } do
			part("UpperTorso", at(s * (si + so) / 2, (strapBot + top) / 2, 0), v(so - si, top - strapBot, Dt), topC, "Fabric", "Strap")
			part("UpperTorso", at(s * (so + xm) / 2, (ya + ym) / 2, 0), v(xm - so, ym - ya, Dt), topC, "Fabric", "Armhole")
			slopeXY("UpperTorso", s, so, xm, ym, top, 0, Dt, topC, "Fabric", "Armhole")
			slopeXY("UpperTorso", s, xm, edge, ya, ym, 0, Dt, topC, "Fabric", "Armhole")
		end
		-- «U»-вырез: кожа поверх полотна (нижняя половина эллипса), выше центра полотна нет
		-- кожа выреза: эллипс (видна нижняя половина — дуга «U») + пластина выше центра, вровень с полотном
		local plT = (Dt - td) / 2 + 0.01
		for _, zs in { -1, 1 } do
			local cY = if zs < 0 then cYf else cYb
			local dU = if zs < 0 then dUf else dUb
			ell("UpperTorso", at(0, cY, zs * (Dt / 2 + 0.01)), v(2 * si - 0.012, 2 * dU, 0.016), skin, "SmoothPlastic", "Scoop")
			part("UpperTorso", at(0, (cY + yN + 0.006) / 2, zs * (Dt / 2 + 0.004 - plT / 2)), v(2 * si - 0.004, yN + 0.006 - cY, plT), skin, "SmoothPlastic", "ScoopPlate")
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
					part("UpperTorso", at(x, (hem + 0.05 + yt) / 2, -Dt / 2 - 0.007), v(0.016, yt - hem - 0.05, 0.012), topC:Lerp(BLACK, 0.05), "Fabric", "Rib")
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
		bustOut = 0.07
		local fz0 = if covered then -D / 2 else -td / 2
		ell("UpperTorso", at(0, bustY, fz0 + 0.07), v(tw * 0.8, semi * 2, 0.28), bc, "SmoothPlastic", "Bust")
		for _, s in { 1, -1 } do
			ell("UpperTorso", at(s * tw * 0.16, bustY - 0.025, fz0 + 0.07), v(tw * 0.4, semi * 1.8, 0.29), bc, "SmoothPlastic", "Bust")
		end
	end

	-- ===== Таз и низ =====
	local botC = o.bottom
	local bstyle = o.bottomStyle
	rboxY("LowerTorso", 0, yH - 0.22, waistTop - 0.03, 0, hipW, td * 0.98, rT, botC, "Fabric", "Pelvis")
	-- пояс
	local bandC = if bstyle == "track" then botC:Lerp(BLACK, 0.3) else botC:Lerp(BLACK, 0.12)
	rboxY("LowerTorso", 0, waistTop - 0.15, waistTop + 0.012, 0, hipW + 0.034, td * 0.98 + 0.034, rT + 0.017, bandC, "Fabric", "Waistband")
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
		part("LowerTorso", at(0.06, yH + 0.05, fzb + 0.02), v(0.012, 0.36, 0.02), o.stitch or bandC:Lerp(WHITE, 0.3), "Fabric", "Fly")
	end
	-- «сиденье»: заполняет зазор у тазобедренных при сгибе ног (спрятано в штанинах стоя)
	local sleeveW = if bstyle == "baggy" then lw + 0.2 elseif bstyle == "track" then lw + 0.14 elseif bstyle == "leggings" then lw + 0.02 else lw + 0.08
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
		rboxY(LL, x, aY - 0.04, kY + sw * 0.45, 0, sw, sw, 0.18, skin, "SmoothPlastic", "Shin")
		ell(LL, at(x, kY - 0.38 * h, 0.08), v(sw * 0.86, 0.5 * h, sw * 0.5), skin, "SmoothPlastic", "Calf")
		-- колено
		ell(LL, at(x, kY, -0.01), v(sw + 0.04, 0.42, sw + 0.06), skin, "SmoothPlastic", "Knee")
		-- штанина
		local hem
		if bstyle == "baggy" then
			hem = kY - 0.42 * h
		elseif bstyle == "track" then
			hem = kY + 0.3 * h
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
				rboxY(LL, cx, hem - 0.03, hem + 0.07, 0, lowW + 0.024, lowW + 0.024, 0.22, botC:Lerp(BLACK, 0.1), "Fabric", "Hem")
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
				for i = -1, 1 do
					part(UL, at(outX, (hemTop + sleeveTop) / 2, i * 0.085), v(0.02, sleeveTop - hemTop, 0.042), o.stripe, "Fabric", "Stripe")
					part("LowerTorso", at(s * (hipW / 2 + 0.008), (yH - 0.1 + waistTop - 0.15) / 2, i * 0.085), v(0.02, waistTop - 0.15 - yH + 0.1, 0.042), o.stripe, "Fabric", "Stripe")
				end
				-- маленький логотип-трилистник
				ell(UL, at(cx - s * 0.12, hemTop + 0.14, -(sleeveW / 2 + 0.008)), v(0.09, 0.07, 0.016), o.stripe, "SmoothPlastic", "Logo")
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
				-- принт: крупные красные розы с листьями на штанинах
				local leaf = rgb(46, 92, 58)
				local function rose(bone, cf, d)
					ell(bone, cf, v(d, d * 0.92, 0.036), o.roses, "Fabric", "Rose")
					ell(bone, cf * at(0.0, d * 0.06, -0.008), v(d * 0.6, d * 0.52, 0.03), o.roses:Lerp(BLACK, 0.38), "Fabric", "RoseHeart")
					ell(bone, cf * at(-d * 0.12, d * 0.14, -0.014) * ang(0, 0, 30), v(d * 0.36, d * 0.14, 0.024), o.roses:Lerp(WHITE, 0.18), "Fabric", "RosePetal")
					ell(bone, cf * at(d * 0.16, -d * 0.12, -0.014) * ang(0, 0, -40), v(d * 0.3, d * 0.12, 0.024), o.roses:Lerp(BLACK, 0.2), "Fabric", "RosePetal")
					ell(bone, cf * at(d * 0.44, -d * 0.52, 0.004) * ang(0, 0, 38), v(d * 0.62, d * 0.24, 0.03), leaf, "Fabric", "Leaf")
					ell(bone, cf * at(-d * 0.5, -d * 0.4, 0.004) * ang(0, 0, -30), v(d * 0.5, d * 0.2, 0.03), leaf:Lerp(BLACK, 0.15), "Fabric", "Leaf")
				end
				local outX = cx + s * (sleeveW / 2 + 0.004)
				local frontZ = -(sleeveW / 2 + 0.004)
				local function onSide(bone, y, fz2, d, ww)
					rose(bone, CFrame.fromMatrix(v(cx + s * ((ww or sleeveW) / 2 + 0.004), y, fz2 * (ww or sleeveW)), v(0, 0, s), v(0, 1, 0)), d)
				end
				local function onFront(bone, fx2, y, d, ww)
					rose(bone, CFrame.fromMatrix(v(cx + s * fx2 * (ww or sleeveW), y, -((ww or sleeveW) / 2 + 0.004)), v(1, 0, 0), v(0, 1, 0)), d)
				end
				local _ = outX
				local _2 = frontZ
				onSide(UL, yH - 0.25, -0.1, 0.27)
				onSide(UL, kY + 0.3, 0.18, 0.22)
				onFront(UL, 0.16, kY + 0.42, 0.22)
				onFront(UL, -0.14, yH - 0.08, 0.17)
				if bstyle == "baggy" then
					local lowW = sleeveW - 0.04
					onSide(LL, kY - 0.3, 0.05, 0.24, lowW)
					onFront(LL, -0.1, hem + 0.24, 0.18, lowW)
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
			-- подошва: скруглённая, носок приподнят
			rbox(FT, at(x, 0.065, midZ + 0.03), v(footW + 0.06, 0.13, fl - 0.1), 0.26, sole, "Rubber", "Sole")
			ell(FT, at(x, 0.075, toeZ + 0.16), v(footW + 0.06, 0.15, 0.4), sole, "Rubber", "SoleToe")
			ell(FT, at(x, 0.075, heelZ - 0.1), v(footW + 0.05, 0.15, 0.3), sole, "Rubber", "SoleHeel")
			-- верх: колодка сужается к носку
			rbox(FT, at(x, 0.24, midZ + 0.1), v(footW, 0.28, fl - 0.34), 0.24, shoe, "Fabric", "Upper")
			ell(FT, at(x, 0.17, toeZ + 0.22), v(footW - 0.02, 0.24, 0.5), shoe, "Fabric", "ToeBox")
			ell(FT, at(x, 0.16, toeZ + 0.12), v(footW - 0.1, 0.14, 0.18), shoe:Lerp(WHITE, 0.08), "Fabric", "ToeCap")
			ell(FT, at(x, 0.33, heelZ - 0.2), v(footW + 0.02, 0.44, 0.42), shoe, "Fabric", "Heel")
			ell(FT, at(x, 0.42, heelZ - 0.06), v(0.16, 0.2, 0.1), acc or shoe:Lerp(BLACK, 0.15), "SmoothPlastic", "HeelTab")
			-- язычок, проём и шнурки
			local tongueCF = at(x, 0.36, midZ - 0.04) * ang(-16, 0, 0)
			part(FT, tongueCF, v(footW * 0.48, 0.07, 0.46), shoe:Lerp(WHITE, 0.12), "Fabric", "Tongue")
			ell(FT, at(x, 0.48, heelZ - 0.32), v(sw * 0.98, 0.08, sw * 0.98), shoe:Lerp(BLACK, 0.35), "SmoothPlastic", "Collar")
			for i = 0, 3 do
				part(FT, tongueCF * at(0, 0.05, -0.17 + i * 0.1) * ang(0, (i % 2 * 2 - 1) * 10, 0), v(footW * 0.52, 0.03, 0.036), acc and WHITE or shoe:Lerp(WHITE, 0.7), "Fabric", "Lace")
			end
			if acc then
				-- полоса-«формстрип» по бокам: широкая дуга от пятки к шнуровке
				for _, ss in { 1, -1 } do
					local px = x + ss * (footW / 2 + 0.004)
					local cf = CFrame.fromMatrix(v(px, 0.22, midZ + 0.04), v(0, 0, -1), v(0, 1, 0)) * ang(0, 0, -16)
					part(FT, cf, v(fl * 0.62, 0.075, 0.016), acc, "Leather", "Formstrip")
				end
			end
			-- носок
			if o.socks then
				rboxY(LL, x, aY + 0.02, aY + 0.44, 0, sw + 0.03, sw + 0.03, 0.19, o.socks, "Fabric", "Sock")
				rboxY(LL, x, aY + 0.36, aY + 0.46, 0, sw + 0.05, sw + 0.05, 0.2, o.socks:Lerp(BLACK, 0.04), "Fabric", "SockCuff")
			end
			ell(FT, at(x, 0.4, 0.04), v(sw * 0.92, 0.36, sw * 0.92), o.socks or skin, "SmoothPlastic", "Ankle")
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
		rboxY(UA, x, eY, sY - 0.1, 0, aw * 0.94, aw * 0.94, aw * 0.3, skin, "SmoothPlastic", "UpperArm")
		ell(UA, at(x, sY - 0.08, 0), v(aw * 1.04, 0.62 * h, aw * 1.02), skin, "SmoothPlastic", "Deltoid")
		ell(UA, at(x, sY, 0), v(aw, 0.36 * h, aw), skin, "SmoothPlastic", "ShoulderCap")
		if topStyle == "tee" then
			rboxY(UA, x, sY - 0.55 * h, sY - 0.045, 0, aw + 0.09, aw + 0.09, aw * 0.3 + 0.045, o.top, "Fabric", "Sleeve")
			ell(UA, at(x, sY + 0.005, 0), v(aw + 0.08, 0.4 * h, aw + 0.08), o.top, "SmoothPlastic", "SleeveCap")
			ell(UA, at(x, sY - 0.08, 0), v(aw * 1.04 + 0.06, 0.62 * h, aw * 1.02 + 0.06), o.top, "SmoothPlastic", "SleeveDelt")
		end
		-- локоть + предплечье
		ell(LA, at(x, eY - 0.02, 0.02), v(aw * 0.9, 0.5, aw * 0.9), skin, "SmoothPlastic", "Elbow")
		rboxY(LA, x, wY + 0.04, eY - 0.05, 0, fx, fz, fx * 0.36, skin, "SmoothPlastic", "Forearm")
		ell(LA, at(x, eY - 0.3, -0.02), v(fx * 1.08, 0.5, fz * 1.04), skin, "SmoothPlastic", "ForearmMuscle")
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
	local hc = yN + 0.74 * h -- центр головы
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
	-- передняя точка поверхности головы вдоль луча (x, y, -∞) -> +Z (в осях головы)
	local function surfZ(x, y)
		local best = 0
		for _, e in surf do
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
	cylY("Head", Hc(0, -0.66, 0.06), 0.76, neckD, skin, "SmoothPlastic", "Neck")
	ell("Head", Hc(0, -0.4, 0.1), v(neckD * 0.98, 0.5, neckD * 0.98), skin, "SmoothPlastic", "NeckTop")
	if not fem then
		ell("Head", Hc(0, -0.62, -neckD * 0.36), v(0.1, 0.12, 0.1), skin, "SmoothPlastic", "AdamsApple")
	end
	-- череп, лицо, надбровье, «муфта» под носом
	local cran = if fem then v(1.04, 1.16, 1.14) else v(1.06, 1.2, 1.18)
	local headHW = cran.X / 2 -- полуширина черепа
	sk("Head", v(0, 0.1, 0.06), cran, skin, "Cranium")
	sk("Head", v(0, -0.0, -0.3), if fem then v(0.88, 0.98, 0.58) else v(0.92, 1.0, 0.6), skin, "Face")
	sk("Head", v(0, 0.17, -0.42), v(0.76, 0.2, 0.36), skin, "BrowRidge")
	if fem then
		sk("Head", v(0, -0.235, -0.415), v(0.38, 0.2, 0.34), skin, "Muzzle")
	else
		sk("Head", v(0, -0.235, -0.43), v(0.42, 0.22, 0.36), skin, "Muzzle")
	end
	-- нижняя челюсть на суставе Jaw
	local jawPivot = H(0, -0.22, 0.18)
	rig:joint("Jaw", "Head", jawPivot, jawPivot, v(0.1, 0.1, 0.1))
	local jawS = if fem then v(0.68, 0.5, 0.9) else v(0.78, 0.52, 0.96)
	local jawC = v(0, -0.34, -0.14)
	local jawR = v(-16, 0, 0) -- наклон: угол челюсти у уха выше, подбородок ниже
	local chinS = if fem then v(0.28, 0.25, 0.3) else v(0.34, 0.28, 0.34)
	local chinC = if fem then v(0, -0.5, -0.37) else v(0, -0.52, -0.37)
	sk("Jaw", jawC, jawS, skin, "JawSkin", jawR)
	sk("Jaw", chinC, chinS, skin, "Chin")
	-- щёки на суставах (поднимаются при улыбке)
	local cheekC = skin:Lerp(rosyC, if fem then 0.25 else 0.35)
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local cj = side .. "Cheek"
		local cc = if fem then v(s * 0.215, -0.12, -0.335) else v(s * 0.22, -0.13, -0.36)
		rig:joint(cj, "Head", H(cc.X, cc.Y, cc.Z), H(cc.X, cc.Y, cc.Z), v(0.05, 0.05, 0.05))
		sk(cj, cc, if fem then v(0.32, 0.27, 0.4) else v(0.34, 0.3, 0.44), cheekC, "Cheek")
	end
	-- уши
	for _, s in { 1, -1 } do
		local ec = Hc(s * (headHW + 0.02), -0.04, 0.09) * ang(0, s * -14, s * -5)
		local earC = skin:Lerp(rosyC, 0.5)
		ell("Head", ec, v(0.13, 0.31, 0.21), earC, "SmoothPlastic", "Ear")
		ell("Head", ec * at(s * 0.04, 0.02, -0.004), v(0.05, 0.2, 0.12), skinDeep, "SmoothPlastic", "EarInner")
		ell("Head", ec * at(s * 0.045, 0.025, 0.02), v(0.04, 0.22, 0.06), earC, "SmoothPlastic", "EarRim")
		ell("Head", ec * at(s * 0.01, -0.13, -0.01), v(0.09, 0.1, 0.1), earC, "SmoothPlastic", "EarLobe")
	end

	-- ----- глаза -----
	local eyeY = 0.0
	local eyeX = if fem then 0.205 else 0.2
	local eyeW, eyeH, eyeD = (if fem then 0.215 else 0.195), (if fem then 0.178 else 0.15), 0.1
	local lashC = rgb(34, 22, 20)
	local eyeCFs = {}
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local ex = s * eyeX
		local eyeCF = onFace(ex, eyeY, 0) * at(0, 0, eyeD / 2 - 0.03)
		eyeCFs[side] = eyeCF
		ell("Head", eyeCF, v(eyeW, eyeH, eyeD), rgb(246, 242, 236), "SmoothPlastic", "EyeWhite")
		-- взгляд: радужка-«колпачок», зрачок, два блика
		local eyeJ = side .. "Eye"
		rig:joint(eyeJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		local irisD = eyeH * (if fem then 0.86 else 0.82)
		local irisC = o.eyes
		ell(eyeJ, eyeCF * at(0, 0, -eyeD / 2 + 0.018), v(irisD, irisD, 0.05), irisC:Lerp(BLACK, 0.55), "SmoothPlastic", "IrisRing")
		ell(eyeJ, eyeCF * at(0, 0, -eyeD / 2 + 0.014), v(irisD * 0.84, irisD * 0.84, 0.05), irisC, "SmoothPlastic", "Iris")
		ell(eyeJ, eyeCF * at(0, -irisD * 0.12, -eyeD / 2 + 0.0105), v(irisD * 0.5, irisD * 0.36, 0.05), irisC:Lerp(WHITE, 0.25), "SmoothPlastic", "IrisLight")
		ell(eyeJ, eyeCF * at(0, 0, -eyeD / 2 + 0.008), v(irisD * 0.44, irisD * 0.44, 0.05), rgb(10, 8, 8), "SmoothPlastic", "Pupil")
		ell(eyeJ, eyeCF * at(irisD * 0.2, irisD * 0.2, -eyeD / 2 - 0.004), v(irisD * 0.24, irisD * 0.24, 0.03), WHITE, "SmoothPlastic", "Glint")
		ell(eyeJ, eyeCF * at(-irisD * 0.18, -irisD * 0.2, -eyeD / 2 - 0.002), v(irisD * 0.1, irisD * 0.1, 0.03), WHITE, "SmoothPlastic", "Glint")
		-- верхнее веко (кожа) + линия ресниц; моргание — сдвиг вниз
		local lidJ = side .. "Lid"
		rig:joint(lidJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		local lidY = if fem then 1.0 else 0.88
		ell(lidJ, eyeCF * at(0, eyeH * lidY, 0.0) * ang(18, 0, 0), v(eyeW + 0.04, eyeH * 1.22, eyeD + 0.024), skin, "SmoothPlastic", "Lid")
		local lashT = if o.lashes then 0.03 else 0.022
		local lashY = eyeH * (lidY - 0.6)
		ell(lidJ, eyeCF * at(0, lashY, -0.002), v(eyeW * 1.04, lashT, eyeD * 1.06), lashC, "SmoothPlastic", "LashLine")
		if o.lashes then
			ell(lidJ, eyeCF * at(s * eyeW * 0.5, lashY + 0.004, -0.004) * ang(0, 0, s * 24), v(0.07, 0.024, eyeD * 0.9), lashC, "SmoothPlastic", "LashFlick")
		end
		-- нижнее веко (поднимается при улыбке/прищуре — «смеющиеся» глаза)
		local llJ = side .. "LowerLid"
		rig:joint(llJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		ell(llJ, eyeCF * at(0, -eyeH * 0.86, -0.003), v(eyeW + 0.04, eyeH * 0.95, eyeD + 0.026), skin, "SmoothPlastic", "LowerLid")
		ell(llJ, eyeCF * at(0, -eyeH * 0.42, -0.004), v(eyeW * 0.8, 0.014, eyeD * 0.96), skin:Lerp(lashC, 0.25), "SmoothPlastic", "LowerLash")
	end

	-- ----- брови -----
	local browC = o.brows or o.hair:Lerp(BLACK, 0.35)
	local bt = o.browThick
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local by = eyeY + eyeH * 0.5 + (if fem then 0.115 else 0.08)
		local bj = side .. "Brow"
		local pivot = onFace(s * (eyeX + 0.005), by, 0.01).Position
		rig:joint(bj, "Head", pivot, pivot, v(0.05, 0.05, 0.05))
		-- три сегмента: толстое начало у переносицы, дуга, тонкий хвост
		ell(bj, onFace(s * (eyeX - 0.075), by - 0.002, 0.02, -s * 6), v(0.12, 0.064 * bt, 0.06), browC, "SmoothPlastic", "Brow")
		ell(bj, onFace(s * (eyeX + 0.005), by + 0.012, 0.02, -s * 4), v(0.14, 0.056 * bt, 0.06), browC, "SmoothPlastic", "Brow")
		ell(bj, onFace(s * (eyeX + 0.088), by - 0.004, 0.016, -s * 22), v(0.12, 0.04 * bt, 0.055), browC, "SmoothPlastic", "Brow")
	end

	-- ----- нос -----
	local ns = o.nose
	local noseC = skin:Lerp(rosyC, 0.45)
	ell("Head", onFace(0, -0.03, 0.006), v(0.1 * ns, 0.3 * ns, 0.1 * ns), skin, "SmoothPlastic", "NoseBridge")
	ell("Head", onFace(0, -0.1, 0.022 * ns), v(0.12 * ns, 0.16 * ns, 0.1 * ns), skin, "SmoothPlastic", "NoseBridge")
	local tipZ = surfZ(0, -0.155) - 0.05 * ns
	ell("Head", Hc(0, -0.155 * ns, tipZ), v(0.15 * ns, 0.13 * ns, 0.13 * ns), noseC, "SmoothPlastic", "NoseTip")
	for _, s in { 1, -1 } do
		ell("Head", Hc(s * 0.062 * ns, -0.178 * ns, tipZ + 0.035), v(0.08 * ns, 0.075 * ns, 0.08 * ns), noseC, "SmoothPlastic", "NoseWing")
		ell("Head", Hc(s * 0.032 * ns, -0.205 * ns, tipZ + 0.012), v(0.042 * ns, 0.022, 0.05 * ns), skinDeep:Lerp(BLACK, 0.3), "SmoothPlastic", "Nostril")
	end

	-- ----- рот -----
	-- Полость рта и верхние зубы на суставе Mouth: в покое утоплены за поверхность лица (не видны),
	-- канал jaw выдвигает их вперёд, нижняя губа, зубы, язык и подбородок (сустав Jaw) опускаются.
	local my = -0.355 -- линия смыкания губ
	local mz = surfZ(0, my)
	local mouthDark = rgb(66, 20, 26)
	local lipC = skin:Lerp(o.lips, if fem then 0.78 else 0.55)
	local teethC = rgb(250, 247, 238)
	local mPivot = H(0, my, -0.5)
	rig:joint("Mouth", "Head", mPivot, mPivot, v(0.05, 0.05, 0.05))
	ell("Mouth", Hc(0, my - 0.06, mz + 0.105), v(0.44, 0.27, 0.16), mouthDark, "SmoothPlastic", "MouthInside")
	ell("Mouth", Hc(0, my - 0.018, mz + 0.05), v(0.27, 0.085, 0.06), teethC, "SmoothPlastic", "UpperTeeth")
	-- верхняя губа (с «луком Купидона»)
	local ulPivot = H(0, my + 0.04, mz)
	rig:joint("UpperLip", "Head", ulPivot, ulPivot, v(0.05, 0.05, 0.05))
	local lipW = if fem then 0.25 else 0.27
	ell("UpperLip", Hc(0, my + 0.017, mz - 0.008), v(lipW, 0.044, 0.05), lipC, "SmoothPlastic", "UpperLip")
	for _, s in { 1, -1 } do
		ell("UpperLip", Hc(s * 0.045, my + 0.028, mz - 0.009) * ang(0, 0, s * -12), v(0.11, 0.036, 0.044), lipC, "SmoothPlastic", "UpperLipBow")
	end
	ell("UpperLip", Hc(0, my + 0.072, surfZ(0, my + 0.072) + 0.008), v(0.06, 0.07, 0.03), skinShade:Lerp(skin, 0.4), "SmoothPlastic", "Philtrum")
	-- нижняя челюсть: губа, зубы, язык
	ell("Jaw", Hc(0, my - 0.03, mz + 0.03), v(0.21, 0.05, 0.05), teethC:Lerp(rgb(220, 210, 190), 0.3), "SmoothPlastic", "LowerTeeth")
	ell("Jaw", Hc(0, my - 0.095, mz + 0.085), v(0.22, 0.09, 0.16), rgb(196, 92, 100), "SmoothPlastic", "Tongue")
	ell("Jaw", Hc(0, my - 0.028, mz - 0.008), v(lipW - 0.04, if fem then 0.068 else 0.062, 0.058), lipC:Lerp(WHITE, 0.04), "SmoothPlastic", "LowerLip")
	ell("Jaw", Hc(0, my - 0.075, mz + 0.004), v(0.16, 0.04, 0.04), skinShade:Lerp(skin, 0.3), "SmoothPlastic", "LipShadow")
	-- уголки рта (+ складка)
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local mj = side .. "Mouth"
		local cx = s * 0.135
		local mp = H(cx, my, surfZ(cx, my))
		rig:joint(mj, "Head", mp, mp, v(0.05, 0.05, 0.05))
		ell(mj, Hc(cx, my + 0.0, surfZ(cx, my) - 0.005) * ang(0, -s * 18, 0), v(0.06, 0.05, 0.05), lipC:Lerp(skinShade, 0.3), "SmoothPlastic", "LipCorner")
		ell(mj, Hc(s * 0.155, my + 0.012, surfZ(s * 0.155, my) - 0.004) * ang(0, -s * 22, s * 40), v(0.045, 0.016, 0.04), skinDeep, "SmoothPlastic", "CornerCrease")
	end

	-- ----- борода-щетина -----
	-- Короткая густая щетина, облегающая лицо: оболочки на 0.015–0.03 больше кожи, всё на суставе Jaw
	-- (открывается вместе со ртом). Щёки — оболочка «лица», сдвинутая вниз: её верхняя граница
	-- проходит под скулами (яблоки щёк остаются кожей) и поднимается к бакенбардам.
	if o.beard then
		local bC = o.beard:Lerp(skin, 0.12)
		local bSoft = o.beard:Lerp(skin, 0.32)
		ell("Jaw", Hc(jawC.X, jawC.Y - 0.01, jawC.Z) * ang(jawR.X, 0, 0), jawS + v(0.034, 0.034, 0.034), bC, "SmoothPlastic", "BeardJaw")
		ell("Jaw", Hc(chinC.X, chinC.Y - 0.006, chinC.Z - 0.004), chinS + v(0.04, 0.04, 0.04), bC, "SmoothPlastic", "BeardChin")
		ell("Jaw", Hc(0, -0.2, -0.27), v(0.96, 0.84, 0.63), bSoft, "SmoothPlastic", "BeardCheeks")
		for _, s in { 1, -1 } do
			-- бакенбарды: от висков к щетине на щеках
			ell("Head", Hc(s * (headHW - 0.01), -0.0, 0.0) * ang(0, s * -12, 0), v(0.1, 0.36, 0.2), bSoft:Lerp(o.hair, 0.25), "SmoothPlastic", "Sideburn")
			-- усы: от середины к уголкам рта
			ell("UpperLip", Hc(s * 0.07, my + 0.062, surfZ(s * 0.07, my + 0.062) - 0.008) * ang(0, -s * 10, s * -12), v(0.17, 0.07, 0.05), bC, "SmoothPlastic", "Moustache")
			ell("UpperLip", Hc(s * 0.15, my + 0.02, surfZ(s * 0.15, my + 0.02) - 0.004) * ang(0, -s * 22, s * -62), v(0.1, 0.05, 0.05), bC, "SmoothPlastic", "Moustache")
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
	local function lock(a, b, w, t, color, name, out)
		local dir = b - a
		local Y = dir.Unit
		local ov = out or ((a + b) / 2 - HC0).Unit
		local Z = ov - Y * ov:Dot(Y)
		if Z.Magnitude < 1e-3 then
			Z = v(0, 0, -1)
		end
		Z = Z.Unit
		local X = Y:Cross(Z)
		return ell("Head", CFrame.fromMatrix((a + b) / 2, X, Y, Z), v(w, dir.Magnitude + w * 0.3, t), color, "SmoothPlastic", name)
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
		local fade = hairC:Lerp(skin, 0.38)
		local sideC = hairC:Lerp(skin, 0.08)
		local hi = shade(hairC, 0.1)
		local lo = shade(hairC, -0.3)
		-- короткие виски и затылок («фейд»: снизу светлее), граница волос — у верха ушей;
		-- оболочки сдвинуты назад: линия роста волос на лбу дугой, виски с залысинами
		ell("Head", Hc(0, 0.06, 0.15), v(cran.X + 0.05, cran.Y - 0.1, cran.Z - 0.06), fade, "SmoothPlastic", "HairFade")
		ell("Head", Hc(0, 0.2, 0.11), v(cran.X + 0.07, cran.Y - 0.28, cran.Z), sideC, "SmoothPlastic", "HairSides")
		-- объём сверху (уже головы — без «шляпки») и приподнятый кок надо лбом
		ell("Head", Hc(0, 0.5, 0.1), v(cran.X - 0.02, 0.6, cran.Z - 0.04), hairC, "SmoothPlastic", "HairTop")
		ell("Head", Hc(0.03, 0.62, -0.17) * ang(26, 0, -4), v(cran.X - 0.2, 0.36, 0.6), hairC, "SmoothPlastic", "Quiff")
		-- пряди: от лба вверх-назад к макушке (лёгкая фактура)
		for i, x in { -0.27, -0.14, -0.01, 0.12, 0.24 } do
			local a = H(x * 0.92, 0.7 - math.abs(x) * 0.25, -0.32 + math.abs(x) * 0.1)
			local m = H(x * 1.02, 0.8 - math.abs(x) * 0.3, -0.02)
			local b = H(x * 0.96, 0.7 - math.abs(x) * 0.3, 0.34)
			local c = if i % 2 == 0 then hi else lo:Lerp(hairC, 0.5)
			lock(a, m, 0.15, 0.07, c, "QuiffLock")
			lock(m, b, 0.16, 0.07, c, "QuiffLock")
		end
	elseif style == "crop" then
		local fade = hairC:Lerp(skin, 0.3)
		ell("Head", Hc(0, 0.03, 0.15), cran + v(0.035, -0.12, -0.08), fade, "SmoothPlastic", "HairFade")
		ell("Head", Hc(0, 0.22, 0.1), cran + v(0.06, -0.22, -0.02), hairC:Lerp(skin, 0.08), "SmoothPlastic", "HairSides")
		ell("Head", Hc(0, 0.46, 0.04), v(1.14, 0.6, 1.16), hairC, "SmoothPlastic", "HairTop")
		ell("Head", Hc(0.06, 0.5, -0.4) * ang(-8, 0, -8), v(0.74, 0.22, 0.3), hairC, "SmoothPlastic", "Fringe")
	elseif style == "shag" or style == "bob" then
		-- «шэг»: светлая макушка и густая чёлка до бровей с прядками по краю, «шторки» у лица,
		-- каштановая масса по бокам и сзади до подбородка, кончики отогнуты наружу; bob — без флипов
		local hl = o.hairHighlight or shade(hairC, 0.35)
		local dark = shade(hairC, -0.3)
		local mid = hairC:Lerp(hl, 0.45)
		-- масса по бокам и сзади (лицо «вырезано» выступающей кожей), подслой темнее
		ell("Head", Hc(0, -0.06, 0.13), v(cran.X + 0.18, 1.12, cran.Z + 0.12), hairC, "SmoothPlastic", "HairMass")
		ell("Head", Hc(0, -0.34, 0.2), v(cran.X + 0.1, 0.62, cran.Z - 0.02), dark, "SmoothPlastic", "HairUnder")
		-- макушка
		ell("Head", Hc(0, 0.4, 0.07), v(cran.X + 0.12, 0.76, cran.Z + 0.1), mid, "SmoothPlastic", "HairCap")
		ell("Head", Hc(0, 0.5, 0.0) * ang(-6, 0, 0), v(cran.X - 0.04, 0.52, cran.Z - 0.06), hl:Lerp(mid, 0.35), "SmoothPlastic", "HairCrown")
		-- чёлка: плотная, до бровей, + прядки по краю
		local browTop = eyeY + eyeH * 0.5 + 0.13
		ell("Head", Hc(0, browTop + 0.16, surfZ(0, browTop + 0.1) + 0.03) * ang(22, 0, 0), v(0.86, 0.4, 0.22), hl, "SmoothPlastic", "Bangs")
		for i = -3, 3 do
			local x = i * 0.11
			local y = browTop + 0.05 + math.abs(i) * 0.014 + (if i % 2 == 0 then 0 else 0.02)
			ell("Head", Hc(x, y, surfZ(x, y) - 0.055) * ang(14, 0, -x * 30), v(0.15, 0.2, 0.075), if i % 2 == 0 then hl else mid, "SmoothPlastic", "BangTip")
		end
		for _, s in { 1, -1 } do
			-- «шторки»: от края чёлки к скулам, пряди у лица
			ell("Head", Hc(s * 0.38, 0.16, -0.38) * ang(14, s * -32, s * 12), v(0.22, 0.6, 0.14), hl, "SmoothPlastic", "Curtain")
			lock(H(s * 0.43, 0.1, -0.33), H(s * 0.45, -0.42, -0.3), 0.16, 0.08, hl, "FaceFrame", v(s * 0.7, 0, -1).Unit)
			lock(H(s * 0.49, 0.06, -0.2), H(s * 0.56, -0.56, -0.18), 0.2, 0.08, mid, "FaceFrame", v(s, 0, -0.5).Unit)
		end
		-- кончики вокруг низа: отогнуты наружу и вверх
		for j = 0, 11 do
			local ph = 58 + j * (244 / 11)
			local p = rad(ph)
			local r = 0.58 + (j % 2) * 0.03
			local y = -0.58 + (j % 3) * 0.035
			local pos = H(math.sin(p) * r, y, 0.12 - math.cos(p) * r * 0.9)
			local out = v(math.sin(p), 0, -math.cos(p))
			local Y = (out * (if style == "bob" then 0.2 else 0.75) + v(0, if style == "bob" then -1 else 0.66, 0)).Unit
			local X = Y:Cross(out).Unit
			local Z = X:Cross(Y)
			ell("Head", CFrame.fromMatrix(pos, X, Y, Z), v(0.26, 0.3, 0.08), if j % 3 == 0 then dark elseif j % 3 == 1 then hairC else mid, "SmoothPlastic", "Flick")
		end
		-- фактура: широкие плоские пряди по бокам и сзади
		for j, ph in { 72, 100, 128, 156, 204, 232, 260, 288 } do
			local p = rad(ph)
			local top = H(math.sin(p) * 0.56, 0.34, 0.1 - math.cos(p) * 0.6)
			local bot = H(math.sin(p) * 0.66, -0.48, 0.12 - math.cos(p) * 0.64)
			lock(top, bot, 0.26, 0.07, if j % 3 == 0 then hl elseif j % 3 == 1 then mid else hairC, "Strand")
		end
	elseif style == "curls" then
		-- густые короткие кудри: объём сверху и у висков, кудри падают на лоб, затылок короче
		local mat = "Plastic"
		ell("Head", Hc(0, 0.4, 0.06), v(cran.X + 0.14, 0.94, cran.Z + 0.12), hairC, "SmoothPlastic", "HairBase")
		ell("Head", Hc(0, 0.02, 0.2), v(cran.X + 0.1, 0.9, cran.Z - 0.12), hairC, "SmoothPlastic", "HairBack")
		local k = 0
		local c1, c2, c3 = shade(hairC, 0.12), hairC, shade(hairC, -0.22)
		local function jit(i)
			return ((i * 37) % 11) / 10 - 0.5 -- псевдослучайно -0.5..0.5
		end
		local function curl(p, d)
			k += 1
			local m = (k * 7) % 5
			local c = if m == 0 then c1 elseif m <= 2 then c2 else c3
			local out = (p - HC0).Unit
			p += out * jit(k) * 0.06
			ball("Head", p, d, c, mat, "Curl")
			if k % 3 == 0 then
				-- завиток: колечко поверх
				ball("Head", p + out * d * 0.38 + v(0, d * 0.1, 0), d * 0.52, shade(c, 0.08), mat, "Curl")
			end
		end
		-- купол: кольца по широте (сверху выше — объём)
		local rings = { { 84, 3 }, { 70, 9 }, { 56, 13 }, { 42, 16 }, { 28, 19 }, { 14, 20 }, { 0, 21 }, { -14, 20 }, { -28, 18 } }
		for ri, rg in rings do
			local lat = rad(rg[1])
			local yy = 0.34 + 0.58 * math.sin(lat)
			for j = 0, rg[2] - 1 do
				local th = (j + (ri % 2) * 0.5) / rg[2] * math.pi * 2
				local fc = math.cos(th)
				local isFace = (fc > 0.62 and yy < 0.46) or (fc > 0.25 and yy < 0.1)
				if not isFace then
					local rr = math.cos(lat) * (0.6 + (if fc < 0 then 0.02 else 0.0))
					local x = math.sin(th) * rr * 1.04
					local z = -fc * rr + 0.07
					curl(H(x, yy + ((j * 5) % 3 - 1) * 0.02, z), 0.16 + ((j * 7 + ri * 3) % 5) * 0.012)
				end
			end
		end
		-- ряд у ушей (прикрывает верх уха)
		for j = 0, 15 do
			local th = rad(72 + j * (216 / 15))
			curl(H(math.sin(th) * 0.6, -0.06 - (j % 2) * 0.05, -math.cos(th) * 0.64 + 0.08), 0.16)
		end
		-- нижний ряд за ушами и на затылке (короче)
		local n = 14
		for j = 0, n - 1 do
			local th = rad(96 + j * (168 / (n - 1)))
			local x = math.sin(th) * 0.58
			local z = -math.cos(th) * 0.62 + 0.08
			curl(H(x, -0.22 - (j % 2) * 0.04, z), 0.15)
		end
		-- кудри, падающие на лоб (асимметрично)
		for i, p in { { -0.32, 0.42, -0.46 }, { -0.16, 0.45, -0.52 }, { 0.02, 0.44, -0.55 }, { 0.19, 0.4, -0.52 }, { -0.08, 0.36, -0.57 }, { 0.33, 0.33, -0.45 }, { -0.4, 0.3, -0.4 }, { 0.12, 0.34, -0.57 }, { -0.22, 0.34, -0.53 }, { 0.26, 0.3, -0.5 } } do
			ball("Head", H(p[1], p[2], p[3]), 0.13 + (i % 3) * 0.025, if i % 2 == 0 then c2 else c1, mat, "FringeCurl")
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
				-- стекло: блоки-«полосы» из настоящего стекла (SpecialMesh не показывает материал)
				local rows = { { 0.085, 0.31 }, { 0.04, 0.35 }, { -0.02, 0.35 }, { -0.075, 0.31 }, { -0.12, 0.23 } }
				for _, rw in rows do
					part("Glasses", c1 * at(s * 0.012, rw[1], 0), v(rw[2], 0.062, 0.016), lens, "Glass", "Lens", { reflectance = 0.25, transparency = lensT })
				end
				ell("Glasses", c1 * at(s * 0.01, -0.02, 0.004), v(0.355, 0.255, 0.018), lens, "SmoothPlastic", "LensBack", { reflectance = 0.3 })
				loop(c1, s, pts, 0.017, -0.003)
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
			ball("Glasses", gcf * v(s * 0.075, -0.07, 0.04), 0.04, rgb(230, 230, 228), "Glass", "NosePad")
		end
		-- мостик (у авиаторов двойной)
		stick("Glasses", gcf * v(-0.085, 0.03, -0.005), gcf * v(0.085, 0.03, -0.005), 0.026, frame, fmat, "Bridge")
		if kind == "aviator" then
			stick("Glasses", gcf * v(-0.12, 0.095, 0.0), gcf * v(0.12, 0.095, 0.0), 0.022, frame, fmat, "TopBar")
		end
	end

	-- ===== Лицевые каналы =====
	local blinkK = (if fem then 1.0 else 0.88) - 0.61 + 0.53 -- веко от покоя до низа глаза
	rig.face = {
		jaw = { { joint = "Jaw", rot = v(-16, 0, 0), pos = v(0, -0.015, 0) }, { joint = "Mouth", pos = v(0, -0.012, -0.036) } },
		smile = {
			{ joint = "RightMouth", pos = v(0.04, 0.045, -0.012), rot = v(0, 0, 12) },
			{ joint = "LeftMouth", pos = v(-0.04, 0.045, -0.012), rot = v(0, 0, -12) },
			{ joint = "RightCheek", pos = v(0.01, 0.035, -0.016) },
			{ joint = "LeftCheek", pos = v(-0.01, 0.035, -0.016) },
			{ joint = "UpperLip", pos = v(0, 0.018, -0.004) },
			{ joint = "Mouth", pos = v(0, 0.01, -0.016) },
			{ joint = "RightLid", pos = v(0, -eyeH * 0.1, 0) },
			{ joint = "LeftLid", pos = v(0, -eyeH * 0.1, 0) },
			{ joint = "RightLowerLid", pos = v(0, eyeH * 0.3, -0.012) },
			{ joint = "LeftLowerLid", pos = v(0, eyeH * 0.3, -0.012) },
		},
		oh = {
			{ joint = "RightMouth", pos = v(-0.04, 0.0, -0.02) },
			{ joint = "LeftMouth", pos = v(0.04, 0.0, -0.02) },
			{ joint = "UpperLip", pos = v(0, 0.02, -0.012) },
			{ joint = "Jaw", pos = v(0, 0, -0.01) },
		},
		brows = { { joint = "RightBrow", pos = v(0, 0.06, 0), rot = v(0, 0, -4) }, { joint = "LeftBrow", pos = v(0, 0.06, 0), rot = v(0, 0, 4) } },
		browR = { { joint = "RightBrow", pos = v(0, 0.06, 0), rot = v(0, 0, -4) } },
		browL = { { joint = "LeftBrow", pos = v(0, 0.06, 0), rot = v(0, 0, 4) } },
		frown = { { joint = "RightBrow", pos = v(-0.012, -0.025, 0), rot = v(0, 0, 12) }, { joint = "LeftBrow", pos = v(0.012, -0.025, 0), rot = v(0, 0, -12) } },
		blink = { { joint = "RightLid", pos = v(0, -eyeH * blinkK, 0) }, { joint = "LeftLid", pos = v(0, -eyeH * blinkK, 0) } },
		squint = {
			{ joint = "RightLid", pos = v(0, -eyeH * 0.3, 0) },
			{ joint = "LeftLid", pos = v(0, -eyeH * 0.3, 0) },
			{ joint = "RightLowerLid", pos = v(0, eyeH * 0.22, -0.01) },
			{ joint = "LeftLowerLid", pos = v(0, eyeH * 0.22, -0.01) },
		},
		lookX = { { joint = "RightEye", rot = v(0, -22, 0) }, { joint = "LeftEye", rot = v(0, -22, 0) } },
		lookY = { { joint = "RightEye", rot = v(18, 0, 0) }, { joint = "LeftEye", rot = v(18, 0, 0) } },
	}

	return rig
end
