--!nocheck
-- Человек в стиле Roblox: блочное R15-тело с мягкими фасками (скруглённые рёбра), кисти с пальцами,
-- «динамическая» голова: глаза (белок/радужка/зрачок/блик) на суставах взгляда, веки (моргание),
-- брови на суставах, нос, губы, рот на суставе Jaw (открывается в «О» и в смех), уголки рта.
-- Одежда и причёски собираются из примитивов по опциям (см. DEFAULTS). Использование: require("./Human")(opts).
--
-- КОНТРАКТ ДЛЯ АНИМАТОРОВ
--   Пальцы: R15 + Right/Left Index1/2, Middle1/2, Ring1/2, Pinky1/2, Thumb1/2 (rHand/lHand в ключах; по умолчанию "relaxed").
--   Доп. суставы головы: Jaw, UpperLip, RightMouth/LeftMouth (уголки рта), RightBrow/LeftBrow,
--     RightLid/LeftLid (верхние веки), RightEye/LeftEye (взгляд), Glasses (если есть очки).
--   Лицевые каналы (face = {...}):
--     jaw 0..1 (рот открыт), smile 0..1 (улыбка: уголки вверх/в стороны, щёки, прищур), oh 0..1 (губы в «О»),
--     brows -1..1 (обе брови вверх+/вниз-), browR/browL, frown 0..1 (сведённые брови), blink 0..1, squint 0..1,
--     lookX -1..1 (взгляд вправо от персонажа +), lookY -1..1 (вверх +).
--     «Ах!» (awe):  face = { jaw = 0.7, oh = 1, brows = 1 };  смех: face = { jaw = 0.8, smile = 1, squint = 0.3 }.
--   Очки: joints = { Glasses = { x, y, f, rx, ry, rz } } — смещение от позы покоя (на носу) в осях головы;
--     «спустить на кончик носа»: { y = -0.09, f = 0.03, rx = 6 }. opts.glassesOn = "RightHand"/"LeftHand" — очки в руке.

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
	skin = rgb(230, 182, 158),
	-- лицо
	eyes = rgb(80, 64, 50), -- радужка
	lips = rgb(186, 106, 98),
	brows = nil, -- цвет бровей (по умолчанию темнее волос)
	browThick = 1.0,
	lashes = false, -- выразительные ресницы (женские)
	beard = nil, -- Color3 щетины (нижняя часть лица + усы)
	nose = 1.0, -- масштаб носа
	blush = nil, -- Color3 румянца
	-- волосы
	hair = rgb(60, 42, 30),
	hairStyle = "quiff", -- "quiff" | "shag" | "curls" | "bun" | "crop" | nil
	hairHighlight = nil, -- светлые пряди у лица (shag)
	-- одежда
	top = rgb(242, 241, 237),
	topStyle = "tank", -- "tank" (майка, глубокие проймы) | "crop" (кроп-топ с высоким вырезом) | "tee" (футболка)
	scoop = 0.5, -- глубина выреза майки
	bottom = rgb(30, 32, 40),
	bottomStyle = "shorts", -- "shorts" | "baggy" (широкие до колена) | "track" (спортивные с лампасами) | "leggings"
	stripe = nil, -- Color3 лампасов (track)
	stitch = nil, -- Color3 контрастной строчки
	roses = nil, -- Color3 принта-роз (baggy)
	shoes = "sneakers", -- "sneakers" | "barefoot"
	shoeColor = rgb(242, 242, 240),
	shoeAccent = nil, -- полоса на боку кроссовка
	sole = rgb(246, 246, 244),
	socks = nil, -- Color3 носков
	-- аксессуары
	necklaces = nil, -- { { kind = "cord"|"chain", color, len = 0..1, pendant = "coin"|"drop"|nil, choker = bool } }
	earrings = nil, -- "hoop" | "stud"
	earringColor = rgb(214, 214, 220),
	bracelets = nil, -- { right = { Color3, ... }, left = { ... } }
	rings = nil, -- Color3 колец
	glasses = nil, -- "aviator" | "hex" | "rect"
	glassesFrame = rgb(204, 168, 92),
	glassesLens = rgb(30, 52, 40),
	glassesLensTransparency = 0.05,
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
	local tw = (o.torsoW or (if fem then 1.78 else 2.02)) * bw -- ширина груди
	local td = (o.torsoD or (if fem then 0.92 else 1.0)) * bw
	local aw = (o.armW or (if fem then 0.72 else 0.9)) * bw -- плечо (квадрат)
	local fx = aw * 0.8 -- предплечье: толщина по X
	local fz = aw * 0.86 -- предплечье: ширина по Z
	local lw = (o.legW or (if fem then 0.84 else 0.94)) * bw -- бедро
	local sw = lw * 0.86 -- голень
	local hipX = (if fem then 0.45 else 0.49) * bw
	local pt = (if fem then 0.27 else 0.31) * bw -- толщина ладони
	local pw = (if fem then 0.54 else 0.62) * bw -- ширина ладони
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
		fingerLen1 = 0.19 * h * bw,
		fingerLen2 = 0.17 * h * bw,
		thumbLen1 = 0.17 * h * bw,
		thumbLen2 = 0.15 * h * bw,
	})
	rig.defaultHand = "relaxed"
	local P = rig.P
	local skin = o.skin
	local skinShade = skin:Lerp(rgb(150, 70, 60), 0.18)

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
		part(bone, cf, v(sx - 2 * r, sy - 0.02, sz), color, mat, name)
		for _, cx in { -1, 1 } do
			for _, cz in { -1, 1 } do
				rig:part(bone, {
					cf = cf * at(cx * (sx / 2 - r), 0, cz * (sz / 2 - r)) * ang(0, 0, 90),
					size = v(sy - 0.04, 2 * r, 2 * r),
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

	-- ===== Туловище =====
	local yW, yN, yH = P.waistY, P.neckY, P.hipY
	local topC = o.top
	local topStyle = o.topStyle
	local chestBot = yW + (yN - yW) * (if fem then 0.5 else 0.38) -- низ грудной клетки (у девушек — талия уже)
	local waistW = if fem then tw * 0.88 else tw * 0.97
	local hipW = if fem then tw * 0.98 else tw * 0.97
	local cropped = topStyle == "crop"
	local shirtPad = 0.03
	-- грудь
	local chestColor = if topStyle then topC else skin
	local chestTop = yN + (if topStyle then 0.0 else 0.0)
	rboxY("UpperTorso", 0, chestBot, chestTop, 0, tw + (if topStyle then shirtPad else 0), td + (if topStyle then shirtPad else 0), 0.2 * bw, chestColor, if topStyle then "Fabric" else "SmoothPlastic", "Chest")
	-- талия/живот
	local waistBottom = yW - 0.18
	if cropped or not topStyle then
		rboxY("UpperTorso", 0, waistBottom, chestBot + 0.04, 0.0, waistW, td * 0.94, 0.2 * bw, skin, "SmoothPlastic", "Belly")
		-- пупок
		ell("UpperTorso", at(0, yW + 0.42 * h, -td * 0.47 - 0.012), v(0.07, 0.09, 0.04), skinShade:Lerp(BLACK, 0.25), "SmoothPlastic", "Navel")
	else
		local hem = yW - 0.1
		rboxY("UpperTorso", 0, hem, chestBot + 0.04, 0.0, math.max(waistW + shirtPad, hipW + 0.075), math.max(td * 0.96 + shirtPad, td * 0.98 + 0.075), 0.2 * bw, topC, "Fabric", "ShirtWaist")
	end
	if fem then
		-- грудь под майкой
		local bustY = chestBot + (yN - chestBot) * 0.36
		ell("UpperTorso", at(0, bustY, -td / 2 + 0.04), v(tw * 0.8, 0.5 * h, 0.3), chestColor, if topStyle then "Fabric" else "SmoothPlastic", "Bust")
	end

	-- кожа поверх майки: плечи (проймы), основание шеи, вырез
	if topStyle == "tank" or topStyle == "crop" then
		local so = if topStyle == "crop" then 0.4 * bw else (if fem then 0.62 else 0.74) * bw -- внешний край бретели у шеи
		local si = if topStyle == "crop" then 0.26 * bw else (if fem then 0.4 else 0.46) * bw -- внутренний край бретели
		local ya = yN - (if topStyle == "crop" then 0.82 else (if fem then 0.74 else 0.88)) * h -- низ проймы
		local halfW = (tw + shirtPad) / 2
		local depth = td + shirtPad + 0.025
		for _, s in { 1, -1 } do
			-- клин проймы: прямой угол сверху-снаружи, гипотенуза от (so, yN) к (halfW, ya)
			local wx = halfW + 0.012 - so
			local wy = yN - ya
			-- Wedge: профиль в YZ (высокая сторона +Z); поворот по Y ставит профиль в плоскость XY
			-- Для s=1 нужен прямой угол в (+X,+Y): локальный Z -> +X, локальный Y -> -Y (переворот).
			local cf = CFrame.fromMatrix(v(s * (so + wx / 2), (yN + ya) / 2 + 0.006, 0), v(0, 0, s), v(0, -1, 0))
			part("UpperTorso", cf, v(depth, wy + 0.012, wx), skin, "SmoothPlastic", "Armhole", { shape = "Wedge" })
		end
		-- кожа сверху между бретелями
		part("UpperTorso", at(0, yN + 0.011, 0), v(si * 2, 0.02, depth), skin, "SmoothPlastic", "NeckTop")
		-- вырез спереди и сзади (половинка эллипсоида свисает с верхнего ребра)
		local scoop = if topStyle == "crop" then 0.12 else o.scoop * h
		ell("UpperTorso", at(0, yN, -(td + shirtPad) / 2 + 0.01), v(si * 2, scoop * 2, 0.1), skin, "SmoothPlastic", "NecklineF")
		ell("UpperTorso", at(0, yN, (td + shirtPad) / 2 - 0.01), v(si * 2, (if topStyle == "crop" then 0.18 else 0.4) * h, 0.1), skin, "SmoothPlastic", "NecklineB")
	end
	-- основание шеи (трапеция)
	ell("UpperTorso", at(0, yN + 0.02, 0.04), v(0.86 * bw, 0.2, 0.62 * bw), skin, "SmoothPlastic", "NeckBase")

	-- ===== Таз и низ =====
	local botC = o.bottom
	local bstyle = o.bottomStyle
	local waistTop = yW + (if cropped then 0.16 else 0.24) * h
	rboxY("LowerTorso", 0, yH - 0.22, waistTop, 0, hipW, td * 0.98, 0.2 * bw, botC, "Fabric", "Pelvis")
	-- пояс
	local bandC = if bstyle == "track" then botC:Lerp(BLACK, 0.25) else botC:Lerp(BLACK, 0.12)
	rboxY("LowerTorso", 0, waistTop - 0.16, waistTop + 0.01, 0, hipW + 0.03, td * 0.98 + 0.03, 0.21 * bw, bandC, "Fabric", "Waistband")
	-- «сиденье»: заполняет зазор у тазобедренных при сгибе ног (спрятано в штанинах стоя)
	local sleeveW = if bstyle == "baggy" then lw + 0.16 else (if bstyle == "leggings" then lw + 0.02 else lw + 0.07)
	local seatW = 2 * hipX + sleeveW - 0.08
	rboxY("LowerTorso", 0, yH - 0.42, yH + 0.05, 0.0, seatW, sleeveW - 0.06, 0.16, botC, "Fabric", "Seat")

	-- ===== Ноги =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local x = s * hipX
		local UL, LL, FT = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
		local kY, aY = P.kneeY, P.ankleY
		-- бедро (кожа) и голень
		rboxY(UL, x, kY, yH + 0.1, 0, lw, lw, 0.2, skin, "SmoothPlastic", "Thigh")
		rboxY(LL, x, aY - 0.04, kY + sw * 0.45, 0, sw, sw, 0.18, skin, "SmoothPlastic", "Shin")
		-- колено
		ell(LL, at(x, kY, -0.01), v(sw + 0.04, 0.42, sw + 0.06), skin, "SmoothPlastic", "Knee")
		-- штанина
		local hem
		if bstyle == "baggy" then
			hem = kY - 0.22 * h
		elseif bstyle == "track" then
			hem = kY + 0.42 * h
		elseif bstyle == "leggings" then
			hem = aY + 0.12
		else
			hem = kY + 0.18 * h
		end
		if bstyle == "leggings" then
			rboxY(UL, x, kY - 0.02, yH + 0.16, 0, lw + 0.03, lw + 0.03, 0.21, botC, "Fabric", "Legging")
			rboxY(LL, x, hem, kY + sw * 0.4, 0, sw + 0.03, sw + 0.03, 0.19, botC, "Fabric", "LeggingLow")
			ell(LL, at(x, kY, -0.01), v(sw + 0.08, 0.44, sw + 0.1), botC, "Fabric", "KneeCloth")
		else
			local sleeveTop = yH + 0.2
			local cx = x + s * (if bstyle == "baggy" then 0.03 else 0.0)
			rboxY(UL, cx, hem, sleeveTop, 0, sleeveW, sleeveW, 0.22, botC, "Fabric", "ShortsLeg")
			-- подгиб/кант
			rboxY(UL, cx, hem - 0.005, hem + 0.07, 0, sleeveW + 0.025, sleeveW + 0.025, 0.23, if bstyle == "track" then botC:Lerp(BLACK, 0.2) else botC:Lerp(BLACK, 0.1), "Fabric", "Hem")
			if bstyle == "track" and o.stripe then
				-- три лампаса по боковому шву
				local outX = cx + s * (sleeveW / 2 + 0.006)
				for i = -1, 1 do
					part(UL, at(outX, (hem + 0.07 + sleeveTop) / 2, i * 0.09), v(0.02, sleeveTop - hem - 0.07, 0.045), o.stripe, "Fabric", "Stripe")
					part("LowerTorso", at(s * (hipW / 2 + 0.006), (yH + waistTop - 0.16) / 2, i * 0.09), v(0.02, waistTop - 0.16 - yH, 0.045), o.stripe, "Fabric", "Stripe")
				end
			end
			if o.stitch then
				-- контрастная строчка: над подгибом и по переду
				local fz = -(sleeveW / 2 + 0.006)
				part(UL, at(cx, hem + 0.1, fz), v(sleeveW - 0.3, 0.014, 0.012), o.stitch, "Fabric", "Stitch")
				part(UL, at(cx + s * (sleeveW / 2 - 0.12), (hem + 0.1 + yH) / 2, fz), v(0.014, yH - hem - 0.1, 0.012), o.stitch, "Fabric", "Stitch")
			end
			if o.roses then
				-- принт: крупные красные розы с листьями на внешней стороне штанины
				local outX = cx + s * (sleeveW / 2)
				local spots = { { 0.55, -0.12, 0.2 }, { 0.2, 0.18, 0.16 }, { 0.82, 0.25, 0.14 } }
				for i, sp in spots do
					local yy = hem + (yH - hem) * sp[1]
					local zz = sp[2] * sleeveW
					local d = sp[3]
					local rose = o.roses
					ell(UL, at(outX + s * 0.004, yy, zz), v(0.05, d, d * 1.1), rose, "Fabric", "Rose")
					ell(UL, at(outX + s * 0.016, yy + 0.01, zz - 0.01), v(0.03, d * 0.5, d * 0.55), rose:Lerp(BLACK, 0.35), "Fabric", "RoseHeart")
					ell(UL, at(outX + s * 0.004, yy - d * 0.6, zz + d * 0.45 * (if i % 2 == 0 then 1 else -1)), v(0.04, d * 0.45, d * 0.8), rgb(46, 92, 58), "Fabric", "Leaf", { rot = nil })
				end
				-- роза спереди
				ell(UL, at(cx - s * 0.12, hem + 0.35, -(sleeveW / 2) - 0.004), v(0.16, 0.15, 0.05), o.roses, "Fabric", "Rose")
			end
		end
		-- стопа
		local heelZ = P.footLen - P.footFwd
		local toeZ = -P.footFwd
		local fl = P.footLen
		local midZ = (heelZ + toeZ) / 2
		local footW = if fem then 0.62 else 0.7
		if o.shoes == "barefoot" then
			rbox(FT, at(x, 0.12, midZ + 0.04), v(footW, 0.24, fl - 0.12), 0.2, skin, "SmoothPlastic", "Foot")
			ell(FT, at(x, 0.2, heelZ - 0.25), v(footW * 0.92, 0.36, 0.5), skin, "SmoothPlastic", "Heel")
			ell(FT, at(x, 0.22, midZ - 0.05), v(footW * 0.9, 0.3, fl * 0.7), skin, "SmoothPlastic", "Instep")
			-- пальцы
			for i = 0, 4 do
				local tx = x + s * (-footW / 2 + 0.1 + i * (footW - 0.18) / 4)
				local dd = if i == 0 then 0.17 else 0.13 - i * 0.008
				ball(FT, v(tx, 0.08, toeZ + 0.1 + (if i == 0 then 0 else i * 0.015)), dd, skin, "SmoothPlastic", "Toe")
			end
			ell(FT, at(x, 0.32, 0.0), v(sw * 0.9, 0.4, sw * 0.9), skin, "SmoothPlastic", "Ankle")
		else
			local shoe = o.shoeColor
			-- подошва
			rbox(FT, at(x, 0.06, midZ), v(footW + 0.06, 0.12, fl + 0.04), 0.26, o.sole, "Rubber", "Sole")
			ell(FT, at(x, 0.075, toeZ + 0.12), v(footW + 0.06, 0.15, 0.36), o.sole, "Rubber", "SoleToe")
			-- верх
			rbox(FT, at(x, 0.27, midZ + 0.06), v(footW, 0.32, fl - 0.1), 0.24, shoe, "Leather", "Upper")
			ell(FT, at(x, 0.15, toeZ + 0.18), v(footW - 0.01, 0.26, 0.5), shoe, "Leather", "ToeCap")
			ell(FT, at(x, 0.34, heelZ - 0.22), v(footW + 0.02, 0.5, 0.48), shoe, "Leather", "Heel")
			-- язычок и шнурки
			part(FT, at(x, 0.43, midZ - 0.05) * ang(-18, 0, 0), v(footW * 0.5, 0.06, 0.42), shoe:Lerp(WHITE, 0.15), "Fabric", "Tongue")
			for i = 0, 2 do
				part(FT, at(x, 0.44 - i * 0.05, midZ - 0.04 - i * 0.1) * ang(-18, 0, 0), v(footW * 0.46, 0.03, 0.04), o.shoeAccent or shoe:Lerp(WHITE, 0.6), "Fabric", "Lace")
			end
			if o.shoeAccent then
				-- полоса-«формстрип» на внешней и внутренней стороне
				for _, ss in { 1, -1 } do
					local px = x + ss * (footW / 2 + 0.006)
					part(FT, at(px, 0.24, midZ + 0.02) * ang(-22, 0, 0), v(0.02, 0.07, fl * 0.62), o.shoeAccent, "Leather", "Formstrip")
				end
			end
			-- носок
			if o.socks then
				rboxY(LL, x, aY + 0.02, aY + 0.42, 0, sw + 0.03, sw + 0.03, 0.19, o.socks, "Fabric", "Sock")
			end
			ell(FT, at(x, 0.36, 0.02), v(sw * 0.94, 0.36, sw * 0.94), o.socks or skin, if o.socks then "Fabric" else "SmoothPlastic", "Ankle")
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
		-- плечо
		rboxY(UA, x, eY, sY, 0, aw, aw, aw * 0.3, skin, "SmoothPlastic", "UpperArm")
		ell(UA, at(x, sY, 0), v(aw, 0.36 * h, aw), skin, "SmoothPlastic", "ShoulderCap")
		-- локоть + предплечье
		ell(LA, at(x, eY - 0.02, 0.02), v(aw * 0.94, 0.5, aw * 0.94), skin, "SmoothPlastic", "Elbow")
		rboxY(LA, x, wY + 0.04, eY - 0.05, 0, fx, fz, fx * 0.36, skin, "SmoothPlastic", "Forearm")
		-- запястье и ладонь
		ell(HD, at(x, wY - 0.02, 0), v(pt + 0.1, 0.3, pw * 0.92), skin, "SmoothPlastic", "Wrist")
		local hl = P.handLen
		rbox(HD, at(x, wY - hl / 2 - 0.01, 0), v(pt, hl + 0.04, pw), pt * 0.42, skin, "SmoothPlastic", "Palm")
		-- подушечка большого пальца (со стороны ладони)
		ell(HD, at(x - s * pt * 0.22, wY - hl * 0.45, -pw * 0.24), v(pt * 0.8, hl * 0.8, pw * 0.42), skin, "SmoothPlastic", "Thenar")
		-- пальцы: капсулы
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
			if o.rings and (f == "Middle" or f == "Index") and side == "Right" then
				stick(b1, p1 - v(0, (p1 - p2).Magnitude * 0.55 - 0.02, 0), p1 - v(0, (p1 - p2).Magnitude * 0.55 + 0.02, 0), d + 0.03, o.rings, "Metal", "Ring")
			end
		end
		-- браслеты
		local list = o.bracelets and o.bracelets[string.lower(side)]
		if list then
			for i, col in list do
				local by = wY + 0.12 + (i - 1) * 0.075
				rboxY(LA, x, by - 0.03, by + 0.03, 0, fx + 0.06, fz + 0.06, fx * 0.4, col, if col.R + col.G + col.B > 1.5 then "Metal" else "SmoothPlastic", "Bracelet")
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
	-- шея
	cylY("Head", Hc(0, -0.62, 0.05), 0.72, (if fem then 0.46 else 0.56) * bw, skin, "SmoothPlastic", "Neck")
	-- череп: цилиндр + купол + низ (по мотивам классической головы Roblox)
	cylY("Head", Hc(0, -0.04, 0), 0.74, R * 2, skin, "SmoothPlastic", "HeadCyl")
	ell("Head", Hc(0, 0.33, 0.0), v(R * 2, 0.62, R * 2), skin, "SmoothPlastic", "HeadTop")
	ell("Head", Hc(0, -0.41, 0.0), v(R * 2, 0.46, R * 2), skin, "SmoothPlastic", "HeadBottom")
	-- уши
	for _, s in { 1, -1 } do
		ell("Head", Hc(s * (R - 0.01), -0.04, 0.07) * ang(0, s * -10, 0), v(0.12, 0.28, 0.19), skin, "SmoothPlastic", "Ear")
		ell("Head", Hc(s * (R + 0.035), -0.03, 0.06) * ang(0, s * -10, 0), v(0.03, 0.17, 0.1), skinShade, "SmoothPlastic", "EarInner")
	end

	-- ----- глаза -----
	local eyeY = 0.02
	local eyeX = if fem then 0.215 else 0.21
	local eyeW, eyeH, eyeD = (if fem then 0.21 else 0.2), (if fem then 0.17 else 0.15), 0.1
	local faceZ = function(x)
		return -math.sqrt(R * R - x * x)
	end
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local ex = s * eyeX
		local yaw = -s * math.deg(math.asin(eyeX / R))
		local ez = faceZ(eyeX) + eyeD / 2 - 0.035
		local eyeCF = Hc(ex, eyeY, ez) * ang(0, yaw, 0)
		ell("Head", eyeCF, v(eyeW, eyeH, eyeD), rgb(248, 246, 242), "SmoothPlastic", "EyeWhite")
		-- взгляд
		local eyeJ = side .. "Eye"
		rig:joint(eyeJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		local irisC = o.eyes
		ell(eyeJ, eyeCF * at(0, 0, -eyeD / 2 + 0.008), v(eyeH * 0.74, eyeH * 0.78, 0.03), irisC:Lerp(BLACK, 0.45), "SmoothPlastic", "IrisRing")
		ell(eyeJ, eyeCF * at(0, 0, -eyeD / 2 + 0.006), v(eyeH * 0.6, eyeH * 0.64, 0.03), irisC, "SmoothPlastic", "Iris")
		ell(eyeJ, eyeCF * at(0, 0, -eyeD / 2 + 0.002), v(eyeH * 0.3, eyeH * 0.32, 0.03), rgb(12, 10, 10), "SmoothPlastic", "Pupil")
		ball(eyeJ, (eyeCF * at(0.024, 0.026, -eyeD / 2 - 0.006)).Position, 0.03, WHITE, "SmoothPlastic", "Glint")
		-- верхнее веко (моргание — сдвиг вниз)
		local lidJ = side .. "Lid"
		rig:joint(lidJ, "Head", eyeCF.Position, eyeCF.Position, v(0.05, 0.05, 0.05))
		local lidUp = eyeH * 0.8
		ell(lidJ, eyeCF * at(0, lidUp, -0.004), v(eyeW + 0.025, eyeH + 0.03, eyeD + 0.02), skin, "SmoothPlastic", "Lid")
		local lashT = if o.lashes then 0.03 else 0.02
		ell(lidJ, eyeCF * at(0, eyeH * 0.36, -eyeD / 2 + 0.012) * ang(0, 0, 0), v(eyeW * 0.98, lashT, 0.04), rgb(30, 20, 18), "SmoothPlastic", "LashLine")
		if o.lashes then
			ell(lidJ, eyeCF * at(s * eyeW * 0.45, eyeH * 0.36, -eyeD / 2 + 0.02) * ang(0, 0, s * 28), v(0.08, 0.026, 0.03), rgb(30, 20, 18), "SmoothPlastic", "LashFlick")
		end
	end

	-- ----- брови -----
	local browC = o.brows or o.hair:Lerp(BLACK, 0.35)
	local bt = o.browThick
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local bx = s * (eyeX + 0.01)
		local by = eyeY + eyeH / 2 + 0.105
		local yaw = -s * math.deg(math.asin((eyeX + 0.01) / R))
		local bz = faceZ(eyeX + 0.01)
		local browCF = Hc(bx, by, bz) * ang(0, yaw, 0)
		local bj = side .. "Brow"
		rig:joint(bj, "Head", browCF.Position, browCF.Position, v(0.05, 0.05, 0.05))
		ell(bj, browCF * at(-s * 0.04, 0.0, -0.005) * ang(0, 0, s * 4), v(0.17, 0.068 * bt, 0.05), browC, "SmoothPlastic", "Brow")
		ell(bj, browCF * at(s * 0.065, -0.01, 0.0) * ang(0, 0, -s * 14), v(0.15, 0.05 * bt, 0.045), browC, "SmoothPlastic", "Brow")
	end

	-- ----- нос -----
	local ns = o.nose
	ell("Head", Hc(0, -0.07, -R + 0.01), v(0.12 * ns, 0.27 * ns, 0.13 * ns), skin, "SmoothPlastic", "NoseBridge")
	ell("Head", Hc(0, -0.155 * ns + 0.0, -R - 0.045 * ns), v(0.14 * ns, 0.12 * ns, 0.12 * ns), skin, "SmoothPlastic", "NoseTip")
	for _, s in { 1, -1 } do
		ell("Head", Hc(s * 0.06 * ns, -0.175 * ns, -R - 0.005), v(0.085 * ns, 0.075 * ns, 0.08 * ns), skin, "SmoothPlastic", "NoseWing")
	end

	-- ----- рот -----
	local my = -0.34 -- линия рта
	local mouthDark = rgb(64, 20, 24)
	local lipC = o.lips
	local lowFace = o.beard or skin
	ell("Head", Hc(0, my - 0.03, -R + 0.065), v(0.4, 0.34, 0.17), mouthDark, "SmoothPlastic", "MouthInside")
	ell("Head", Hc(0, my + 0.03, -R + 0.005), v(0.26, 0.075, 0.07), rgb(250, 248, 240), "SmoothPlastic", "UpperTeeth")
	-- верхняя губа
	local ulPivot = H(0, my + 0.06, -R)
	rig:joint("UpperLip", "Head", ulPivot, ulPivot, v(0.05, 0.05, 0.05))
	ell("UpperLip", Hc(0, my + 0.035, -R - 0.012), v(0.29, 0.07, 0.075), lipC, "SmoothPlastic", "UpperLip")
	if o.beard then
		ell("UpperLip", Hc(0, my + 0.1, -R - 0.006), v(0.36, 0.09, 0.08), o.beard, "SmoothPlastic", "Moustache")
	end
	-- нижняя челюсть
	local jawPivot = H(0, -0.26, 0.18)
	rig:joint("Jaw", "Head", jawPivot, jawPivot, v(0.1, 0.1, 0.1))
	ell("Jaw", Hc(0, my - 0.1, -R + 0.06), v(0.26, 0.08, 0.14), rgb(176, 78, 84), "SmoothPlastic", "Tongue")
	ell("Jaw", Hc(0, my - 0.03, -R + 0.008), v(0.22, 0.05, 0.05), rgb(244, 242, 234), "SmoothPlastic", "LowerTeeth")
	ell("Jaw", Hc(0, my - 0.016, -R - 0.012), v(0.27, 0.08, 0.075), lipC:Lerp(WHITE, 0.04), "SmoothPlastic", "LowerLip")
	ell("Jaw", Hc(0, my - 0.15, -R + 0.17), v(0.6, 0.36, 0.42), lowFace, "SmoothPlastic", "Chin")
	-- уголки рта (+ щёки)
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local mx = s * 0.17
		local mj = side .. "Mouth"
		local mp = H(mx, my, faceZ(0.17))
		rig:joint(mj, "Head", mp, mp, v(0.05, 0.05, 0.05))
		ell(mj, Hc(s * 0.195, my + 0.0, faceZ(0.195) + 0.01) * ang(0, -s * 18, 0), v(0.13, 0.18, 0.1), lowFace, "SmoothPlastic", "MouthCorner")
		ell(mj, Hc(s * 0.27, my + 0.2, faceZ(0.27) + 0.04) * ang(0, -s * 26, 0), v(0.2, 0.15, 0.1), skin, "SmoothPlastic", "Cheek")
	end

	-- щетина: «сдвинутая вперёд оболочка» на щеках/челюсти (сзади утоплена в голову)
	if o.beard then
		cylY("Head", Hc(0, -0.27, -0.05), 0.28, R * 2 + 0.025, o.beard, "SmoothPlastic", "BeardCyl")
		ell("Head", Hc(0, -0.41, -0.05), v(R * 2 + 0.03, 0.5, R * 2 + 0.03), o.beard, "SmoothPlastic", "BeardBottom")
	end

	-- ===== Причёски =====
	local hairC = o.hair
	local style = o.hairStyle
	local function shade(c, k)
		return if k >= 0 then c:Lerp(WHITE, k) else c:Lerp(BLACK, -k)
	end
	if style == "quiff" then
		local fade = hairC:Lerp(skin, 0.18)
		-- короткие бока и затылок
		cylY("Head", Hc(0, 0.1, 0.05), 0.5, R * 2 + 0.04, fade, "SmoothPlastic", "HairSides")
		ell("Head", Hc(0, -0.16, 0.24), v(1.02, 0.46, 0.8), fade, "SmoothPlastic", "HairNape")
		-- верх
		ell("Head", Hc(0, 0.4, 0.04), v(R * 2 + 0.07, 0.8, R * 2 + 0.09), hairC, "SmoothPlastic", "HairTop")
		-- кок (зачёс вверх-назад)
		ell("Head", Hc(0, 0.62, -0.22) * ang(18, 0, 0), v(1.0, 0.38, 0.74), hairC, "SmoothPlastic", "Quiff")
		ell("Head", Hc(0.05, 0.7, 0.02) * ang(8, 0, 0), v(0.98, 0.34, 0.86), shade(hairC, 0.04), "SmoothPlastic", "Quiff")
		ell("Head", Hc(-0.18, 0.66, -0.32) * ang(26, 0, 10), v(0.5, 0.26, 0.42), shade(hairC, -0.1), "SmoothPlastic", "QuiffWave")
		-- виски и бакенбарды
		for _, s in { 1, -1 } do
			ell("Head", Hc(s * 0.585, 0.06, -0.14) * ang(0, s * -20, 0), v(0.1, 0.42, 0.2), fade, "SmoothPlastic", "Sideburn")
		end
	elseif style == "crop" then
		local fade = hairC:Lerp(skin, 0.12)
		cylY("Head", Hc(0, 0.1, 0.05), 0.5, R * 2 + 0.04, fade, "SmoothPlastic", "HairSides")
		ell("Head", Hc(0, -0.16, 0.24), v(1.02, 0.46, 0.8), fade, "SmoothPlastic", "HairNape")
		ell("Head", Hc(0, 0.4, 0.03), v(R * 2 + 0.08, 0.84, R * 2 + 0.1), hairC, "SmoothPlastic", "HairTop")
		ell("Head", Hc(0.1, 0.44, -0.5) * ang(-10, 0, -8), v(0.7, 0.2, 0.3), hairC, "SmoothPlastic", "Fringe")
	elseif style == "shag" then
		local hl = o.hairHighlight or shade(hairC, 0.35)
		local dark = shade(hairC, -0.18)
		-- объём сверху
		ell("Head", Hc(0, 0.38, 0.06), v(R * 2 + 0.12, 0.9, R * 2 + 0.14), hairC, "SmoothPlastic", "HairTop")
		-- затылок до шеи
		ell("Head", Hc(0, -0.08, 0.3), v(1.34, 1.24, 0.82), dark, "SmoothPlastic", "HairBack")
		for _, s in { 1, -1 } do
			-- пряди по бокам лица
			ell("Head", Hc(s * 0.5, -0.08, 0.1) * ang(0, 0, s * -4), v(0.44, 1.12, 1.02), hairC, "SmoothPlastic", "HairSide")
			-- кончики «наружу»
			ell("Head", Hc(s * 0.66, -0.56, 0.08) * ang(0, 0, s * 38), v(0.26, 0.42, 0.78), hairC, "SmoothPlastic", "Flick")
			ell("Head", Hc(s * 0.46, -0.66, 0.36) * ang(0, 0, s * 30), v(0.26, 0.4, 0.5), dark, "SmoothPlastic", "Flick")
			-- шторка-чёлка от пробора к вискам
			ell("Head", Hc(s * 0.27, 0.36, -0.5) * ang(0, -s * 22, s * 30), v(0.5, 0.26, 0.24), hairC, "SmoothPlastic", "Bang")
			ell("Head", Hc(s * 0.42, 0.14, -0.42) * ang(0, -s * 38, s * 12), v(0.2, 0.46, 0.2), hairC, "SmoothPlastic", "BangSide")
			-- осветлённые пряди у лица
			ell("Head", Hc(s * 0.34, 0.08, -0.5) * ang(0, -s * 30, s * 8), v(0.1, 0.62, 0.1), hl, "SmoothPlastic", "Highlight")
		end
		-- лёгкие пряди на лбу
		for i, xx in { -0.1, 0.04, 0.14 } do
			ell("Head", Hc(xx, 0.3, -0.6) * ang(-8, 0, -xx * 60), v(0.09, 0.3, 0.07), if i == 2 then hl else hairC, "SmoothPlastic", "Wisp")
		end
	elseif style == "curls" then
		ell("Head", Hc(0, 0.38, 0.08), v(R * 2 + 0.08, 0.86, R * 2 + 0.12), hairC, "SmoothPlastic", "HairBase")
		ell("Head", Hc(0, -0.05, 0.26), v(1.26, 0.9, 0.84), hairC, "SmoothPlastic", "HairBack")
		-- кудри: точки на эллипсоиде (спираль Фибоначчи), лицо открыто
		local n = 64
		local golden = math.pi * (3 - math.sqrt(5))
		local k = 0
		for i = 0, n - 1 do
			local yy = 1 - (i / (n - 1)) * 1.6 -- от макушки вниз
			local rr = math.sqrt(math.max(0, 1 - yy * yy))
			local th = i * golden
			local px, pz = math.cos(th) * rr, math.sin(th) * rr
			local ly = 0.32 + yy * 0.5
			local x = px * 0.68
			local z = pz * 0.7 + 0.08
			local isFace = z < -0.3 and ly < 0.28
			if not isFace and ly > -0.42 then
				k += 1
				local d = 0.22 + ((i * 37) % 11) / 100
				local c = if k % 3 == 0 then shade(hairC, 0.07) elseif k % 3 == 1 then hairC else shade(hairC, -0.25)
				ball("Head", H(x, ly, z), d, c, "SmoothPlastic", "Curl")
			end
		end
		-- кудри, падающие на лоб
		for i, p in { { -0.28, 0.36, -0.56 }, { -0.08, 0.42, -0.6 }, { 0.14, 0.38, -0.6 }, { 0.32, 0.32, -0.52 }, { 0.02, 0.3, -0.62 } } do
			ball("Head", H(p[1], p[2], p[3]), 0.18 + (i % 2) * 0.04, if i % 2 == 0 then hairC else shade(hairC, 0.06), "SmoothPlastic", "FringeCurl")
		end
	elseif style == "bun" then
		ell("Head", Hc(0, 0.36, 0.05), v(R * 2 + 0.05, 0.86, R * 2 + 0.07), hairC, "SmoothPlastic", "HairTop")
		cylY("Head", Hc(0, 0.08, 0.06), 0.44, R * 2 + 0.03, hairC, "SmoothPlastic", "HairSides")
		ball("Head", H(0, 0.48, 0.58), 0.46, shade(hairC, -0.08), "SmoothPlastic", "Bun")
		ell("Head", Hc(0, 0.42, 0.42) * ang(40, 0, 0), v(0.3, 0.1, 0.3), rgb(30, 30, 34), "SmoothPlastic", "HairTie")
		for _, s in { 1, -1 } do
			ell("Head", Hc(s * 0.5, 0.06, -0.3) * ang(0, -s * 40, s * 6), v(0.08, 0.5, 0.08), hairC, "SmoothPlastic", "LooseStrand")
		end
	end

	-- ===== Серьги =====
	if o.earrings then
		for _, s in { 1, -1 } do
			local lobe = H(s * (R + 0.01), -0.17, 0.06)
			if o.earrings == "hoop" then
				local r0 = 0.1
				local c = lobe + v(s * 0.02, -r0, 0)
				local nseg = 10
				for i = 0, nseg - 1 do
					local a0 = (i / nseg) * math.pi * 2
					local a1 = ((i + 1) / nseg) * math.pi * 2
					local p0 = c + v(0, math.cos(a0) * r0, math.sin(a0) * r0)
					local p1 = c + v(0, math.cos(a1) * r0, math.sin(a1) * r0)
					stick("Head", p0, p1, 0.022, o.earringColor, "Metal", "Hoop")
				end
			else
				ball("Head", lobe + v(s * 0.01, -0.02, 0), 0.05, o.earringColor, "Metal", "Stud")
			end
		end
	end

	-- ===== Цепочки и шнурки на шее =====
	if o.necklaces then
		local frontZ = -(td + (if topStyle then shirtPad else 0)) / 2
		local bustY = chestBot + (yN - chestBot) * 0.36
		local function bulge(y)
			-- выступ груди (у девушек) на высоте y
			if not fem then
				return 0
			end
			local dy = (y - bustY) / (0.25 * h)
			if math.abs(dy) >= 1 then
				return 0
			end
			return math.max(0, -0.04 + 0.15 * math.sqrt(1 - dy * dy))
		end
		for idx, nk in o.necklaces do
			local col = nk.color or rgb(220, 220, 225)
			local mat = if nk.kind == "cord" then "SmoothPlastic" else "Metal"
			local d = if nk.kind == "cord" then 0.03 else 0.022
			if nk.choker then
				-- чокер вокруг шеи (на голове — шея принадлежит Head)
				local nr = (if fem then 0.23 else 0.28) * bw + 0.012
				local c = v(0, yN + 0.22, 0.05)
				local nseg = 12
				for i = 0, nseg - 1 do
					local a0 = (i / nseg) * math.pi * 2
					local a1 = ((i + 1) / nseg) * math.pi * 2
					local p0 = c + v(math.sin(a0) * nr, 0, -math.cos(a0) * nr)
					local p1 = c + v(math.sin(a1) * nr, 0, -math.cos(a1) * nr)
					stick("Head", p0, p1, d, col, mat, "Choker")
				end
				if nk.pendant then
					ball("Head", c + v(0, -0.06, -nr - 0.02), 0.06, nk.pendantColor or col, "Metal", "Charm")
				end
			else
				local len = (nk.len or 0.5) * h
				local lift = (idx - 1) * 0.015
				local pts = {}
				local function zf(y, extra)
					return frontZ - 0.035 - bulge(y) - (extra or 0)
				end
				local yLow = yN - len
				local pathL = {
					v(0, yN + 0.1 + lift, 0.3),
					v(0.28, yN + 0.12 + lift, 0.14),
					v(0.34, yN + 0.09 + lift, -0.12),
					v(0.31, yN + 0.0, zf(yN)),
					v(0.24, yN - len * 0.35, zf(yN - len * 0.35)),
					v(0.13, yN - len * 0.75, zf(yN - len * 0.75)),
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
					part("UpperTorso", CFrame.new(v(0, yLow - 0.065, zf(yLow - 0.065, 0.005))) * ang(0, 90, 0), v(0.025, 0.12, 0.12), nk.pendantColor or col, "Metal", "Pendant", { shape = "Cylinder" })
				elseif nk.pendant == "drop" then
					ell("UpperTorso", CFrame.new(v(0, yLow - 0.05, zf(yLow - 0.05, 0.01))), v(0.06, 0.1, 0.04), nk.pendantColor or col, "Metal", "Pendant")
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
		local templeX
		for _, s in { 1, -1 } do
			local lx = s * 0.235
			local yawL = -s * 9
			if kind == "aviator" then
				-- «капля»: широкий верх, нижний край уходит наружу-вниз
				local c1 = L(lx, 0.0, 0.0) * ang(0, yawL, 0)
				local c2 = L(lx + s * 0.025, -0.07, 0.0) * ang(0, yawL, s * -18)
				ell("Glasses", c1, v(0.35, 0.25, 0.03), lens, "Glass", "Lens", { transparency = lensT, reflectance = 0.25 })
				ell("Glasses", c2, v(0.29, 0.2, 0.03), lens, "Glass", "Lens", { transparency = lensT, reflectance = 0.25 })
				ell("Glasses", c1 * at(0, 0, 0.012), v(0.385, 0.285, 0.02), frame, fmat, "Rim")
				ell("Glasses", c2 * at(0, 0, 0.012), v(0.325, 0.235, 0.02), frame, fmat, "Rim")
				templeX = 0.42
			elseif kind == "hex" then
				local c1 = L(lx, -0.005, 0.0) * ang(0, yawL, 0)
				-- шестиугольник: прямоугольник + два ромба по бокам (клинья)
				part("Glasses", c1, v(0.18, 0.21, 0.025), lens, "Glass", "Lens", { transparency = lensT, reflectance = 0.2 })
				for _, ss in { 1, -1 } do
					for _, sy in { 1, -1 } do
						local wcf = c1 * at(ss * 0.135, sy * 0.0525, 0) * CFrame.fromMatrix(Vector3.zero, v(0, 0, 1), v(0, -sy, 0)) * ang(0, if ss * sy > 0 then 0 else 180, 0)
						part("Glasses", wcf, v(0.025, 0.105, 0.09), lens, "Glass", "Lens", { shape = "Wedge", transparency = lensT, reflectance = 0.2 })
					end
				end
				ell("Glasses", c1 * at(0, 0, 0.014), v(0.4, 0.25, 0.02), frame, fmat, "Rim")
				templeX = 0.42
			else -- rect
				local c1 = L(lx, -0.01, 0.0) * ang(0, yawL, 0)
				part("Glasses", c1, v(0.32, 0.15, 0.024), lens, "Glass", "Lens", { transparency = lensT, reflectance = 0.2 })
				part("Glasses", c1 * at(0, 0, 0.014), v(0.35, 0.18, 0.02), frame, fmat, "Rim")
				templeX = 0.42
			end
			-- дужки до ушей
			local hinge = gcf * v(s * templeX, 0.05, 0.03)
			local ear = gcf * v(s * (R + 0.05), 0.04, 0.72)
			stick("Glasses", hinge, ear, 0.026, frame, fmat, "Temple")
			stick("Glasses", ear, gcf * v(s * (R + 0.035), -0.07, 0.8), 0.026, frame, fmat, "TempleTip")
			-- носоупоры
			ball("Glasses", gcf * v(s * 0.075, -0.07, 0.04), 0.04, rgb(230, 230, 228), "Glass", "NosePad")
		end
		-- мостик (у авиаторов двойной)
		stick("Glasses", gcf * v(-0.085, 0.03, -0.005), gcf * v(0.085, 0.03, -0.005), 0.026, frame, fmat, "Bridge")
		if kind == "aviator" then
			stick("Glasses", gcf * v(-0.12, 0.095, 0.0), gcf * v(0.12, 0.095, 0.0), 0.022, frame, fmat, "TopBar")
		end
	end

	rig.face = {
		jaw = { { joint = "Jaw", rot = v(-16, 0, 0), pos = v(0, -0.015, 0) } },
		smile = {
			{ joint = "RightMouth", pos = v(0.04, 0.045, -0.005), rot = v(0, 0, 14) },
			{ joint = "LeftMouth", pos = v(-0.04, 0.045, -0.005), rot = v(0, 0, -14) },
			{ joint = "UpperLip", pos = v(0, 0.018, 0) },
			{ joint = "RightLid", pos = v(0, -0.02, 0) },
			{ joint = "LeftLid", pos = v(0, -0.02, 0) },
		},
		oh = {
			{ joint = "RightMouth", pos = v(-0.03, 0.0, -0.012) },
			{ joint = "LeftMouth", pos = v(0.03, 0.0, -0.012) },
			{ joint = "UpperLip", pos = v(0, 0.025, -0.01) },
		},
		brows = { { joint = "RightBrow", pos = v(0, 0.06, 0), rot = v(0, 0, -4) }, { joint = "LeftBrow", pos = v(0, 0.06, 0), rot = v(0, 0, 4) } },
		browR = { { joint = "RightBrow", pos = v(0, 0.06, 0), rot = v(0, 0, -4) } },
		browL = { { joint = "LeftBrow", pos = v(0, 0.06, 0), rot = v(0, 0, 4) } },
		frown = { { joint = "RightBrow", pos = v(-0.01, -0.025, 0), rot = v(0, 0, 12) }, { joint = "LeftBrow", pos = v(0.01, -0.025, 0), rot = v(0, 0, -12) } },
		blink = { { joint = "RightLid", pos = v(0, -eyeH * 0.8, 0) }, { joint = "LeftLid", pos = v(0, -eyeH * 0.8, 0) } },
		squint = { { joint = "RightLid", pos = v(0, -eyeH * 0.3, 0) }, { joint = "LeftLid", pos = v(0, -eyeH * 0.3, 0) } },
		lookX = { { joint = "RightEye", rot = v(0, -22, 0) }, { joint = "LeftEye", rot = v(0, -22, 0) } },
		lookY = { { joint = "RightEye", rot = v(18, 0, 0) }, { joint = "LeftEye", rot = v(18, 0, 0) } },
	}

	return rig
end
