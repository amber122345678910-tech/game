--!nocheck
-- Человек в стиле Roblox R15 (блочное тело, «роблоксовская» голова-цилиндр), объёмное лицо
-- с открывающимся ртом, причёска из примитивов, майка, шорты, кроссовки, солнцезащитные очки на суставе Glasses.
-- Использование: require("./Human")(opts) — opts описаны ниже (DEFAULTS).

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Rig = require("../lib/Rig")

local function v(x, y, z)
	return Vector3.new(x, y, z)
end
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local DEFAULTS = {
	skin = rgb(234, 192, 160),
	top = rgb(246, 246, 244), -- майка
	topStyle = "tank", -- "tank" | "crop"
	bottom = rgb(28, 28, 32), -- шорты/штаны
	bottomStripe = nil, -- Color3: лампасы
	bottomLong = false, -- длинные штаны
	shoes = rgb(240, 240, 240),
	shoeAccent = nil,
	hair = rgb(60, 42, 30),
	hairStyle = "short", -- "short" | "bob" | "curly"
	beard = nil, -- Color3 щетины
	eyes = rgb(40, 32, 28),
	lips = rgb(196, 120, 110),
	glasses = "aviator", -- "aviator" | "round" | nil
	glassesFrame = rgb(196, 160, 82),
	glassesLens = rgb(36, 54, 46),
	glassesLensTransparency = 0,
	height = 1.0, -- масштаб по высоте (1 = обычный R15)
	build = 1.0, -- ширина плеч/корпуса
	female = false,
}

return function(opts)
	local o = table.clone(DEFAULTS)
	for k, val in opts or {} do
		o[k] = val
	end
	local h = o.height
	local w = o.build
	local rig = Rig.new("Human", {
		hipX = 0.5 * w,
		hipY = 2.05 * h,
		kneeY = 1.02 * h,
		ankleY = 0.22 * h,
		footLen = 1.05,
		footFwd = 0.7,
		pelvisY = 2.25 * h,
		waistY = 2.45 * h,
		neckY = 4.05 * h,
		shoulderX = 1.5 * w,
		shoulderY = 3.88 * h,
		upperArm = 1.08 * h,
		lowerArm = 1.0 * h,
		handLen = 0.38 * h,
		handW = 0.9,
		torsoW = 2.0 * w,
		torsoD = 1.0,
		headH = 1.25,
	})
	local P = rig.P
	local skin = o.skin

	-- ===== Туловище =====
	local tw, td = 2.0 * w, 1.0
	local utH = P.neckY - P.waistY
	local utY = (P.neckY + P.waistY) / 2
	local topH = if o.topStyle == "crop" then utH * 0.62 else utH
	local topY = P.neckY - topH / 2
	rig:box("UpperTorso", v(0, topY, 0), v(tw, topH, td), o.top, "Fabric", nil, { name = "Top" })
	if o.topStyle == "crop" then
		-- голый живот под укороченной майкой
		rig:box("UpperTorso", v(0, P.waistY + (utH - topH) / 2, 0), v(tw * 0.94, utH - topH + 0.02, td * 0.94), skin, "SmoothPlastic", nil, { name = "Belly" })
	end
	-- вырез майки и плечи (кожа)
	rig:box("UpperTorso", v(0, P.neckY - 0.16, -td / 2 - 0.005), v(tw * 0.42, 0.34, 0.02), skin, "SmoothPlastic", nil, { name = "Neckline" })
	for _, s in { 1, -1 } do
		rig:box("UpperTorso", v(s * (tw / 2 - 0.22), P.neckY - 0.18, 0), v(0.46, 0.38, td + 0.01), skin, "SmoothPlastic", nil, { name = "ShoulderSkin" })
	end
	if o.female then
		rig:ellipsoid("UpperTorso", v(0, utY + 0.32, -td / 2 + 0.02), v(tw * 0.78, 0.62, 0.36), o.top, "Fabric", nil, { name = "Chest" })
	end
	-- шея
	rig:cyl("UpperTorso", v(0, P.neckY + 0.1, 0.04), 0.34, 0.62, skin, "SmoothPlastic", "Y", nil, { name = "Neck" })

	local ltH = (P.waistY - P.hipY) + 0.3
	rig:box("LowerTorso", v(0, (P.waistY + P.hipY) / 2 - 0.05, 0), v(tw, ltH, td), o.bottom, "Fabric", nil, { name = "Shorts" })

	-- ===== Руки =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local x = s * P.shoulderX
		local eY = P.shoulderY - P.upperArm
		local wY = eY - P.lowerArm
		rig:box(side .. "UpperArm", v(x, P.shoulderY - P.upperArm / 2 + 0.08, 0), v(0.96, P.upperArm + 0.16, 0.96), skin, "SmoothPlastic", nil, { name = "Arm" })
		rig:box(side .. "LowerArm", v(x, eY - P.lowerArm / 2 + 0.02, 0), v(0.92, P.lowerArm + 0.04, 0.92), skin, "SmoothPlastic", nil, { name = "Forearm" })
		rig:box(side .. "Hand", v(x, wY - P.handLen / 2, 0), v(0.88, P.handLen, 0.88), skin, "SmoothPlastic", nil, { name = "Hand" })
	end

	-- ===== Ноги =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local x = s * P.hipX
		local ul = P.hipY - P.kneeY
		local ll = P.kneeY - P.ankleY
		local shortsLen = if o.bottomLong then ul + 0.05 else ul * 0.72
		rig:box(side .. "UpperLeg", v(x, P.hipY - shortsLen / 2 + 0.05, 0), v(1.0, shortsLen + 0.1, 1.0), o.bottom, "Fabric", nil, { name = "ShortsLeg" })
		if not o.bottomLong then
			rig:box(side .. "UpperLeg", v(x, P.kneeY + (ul - shortsLen) / 2, 0), v(0.92, ul - shortsLen + 0.06, 0.92), skin, "SmoothPlastic", nil, { name = "Thigh" })
		end
		if o.bottomStripe then
			rig:box(side .. "UpperLeg", v(x + s * 0.505, P.hipY - shortsLen / 2 + 0.05, 0), v(0.02, shortsLen + 0.1, 0.16), o.bottomStripe, "Fabric", nil, { name = "Stripe" })
		end
		rig:box(side .. "LowerLeg", v(x, P.ankleY + ll / 2 + 0.05, 0), v(0.9, ll + 0.1, 0.9), if o.bottomLong then o.bottom else skin, if o.bottomLong then "Fabric" else "SmoothPlastic", nil, { name = "Shin" })
		-- кроссовок
		local heelZ = P.footLen - P.footFwd
		local midZ = (heelZ - P.footFwd) / 2
		rig:box(side .. "Foot", v(x, 0.16, midZ), v(0.86, 0.32, P.footLen), o.shoes, "Leather", nil, { name = "Shoe" })
		rig:box(side .. "Foot", v(x, 0.04, midZ), v(0.9, 0.08, P.footLen + 0.04), o.shoeAccent or rgb(250, 250, 250), "Rubber", nil, { name = "Sole" })
	end

	-- ===== Голова =====
	local hc = P.neckY + 0.66 -- центр головы
	local hr = 0.62 -- радиус «цилиндра» головы
	rig:cyl("Head", v(0, hc, 0), 0.78, hr * 2, skin, "SmoothPlastic", "Y", nil, { name = "HeadCyl" })
	rig:ellipsoid("Head", v(0, hc + 0.36, 0), v(hr * 2, 0.5, hr * 2), skin, "SmoothPlastic", nil, { name = "HeadTop" })
	rig:ellipsoid("Head", v(0, hc - 0.36, 0), v(hr * 2, 0.46, hr * 2), skin, "SmoothPlastic", nil, { name = "HeadBottom" })
	-- уши
	for _, s in { 1, -1 } do
		rig:ellipsoid("Head", v(s * (hr + 0.02), hc - 0.02, 0.05), v(0.12, 0.3, 0.2), skin, "SmoothPlastic", nil, { name = "Ear" })
	end
	-- нос
	rig:ellipsoid("Head", v(0, hc - 0.05, -hr - 0.03), v(0.17, 0.24, 0.16), skin, "SmoothPlastic", nil, { name = "Nose" })
	-- глаза (белок + радужка), веки
	for _, s in { 1, -1 } do
		rig:ellipsoid("Head", v(s * 0.22, hc + 0.1, -hr + 0.05), v(0.2, 0.17, 0.12), rgb(250, 250, 248), "SmoothPlastic", nil, { name = "EyeWhite" })
		rig:ellipsoid("Head", v(s * 0.22, hc + 0.1, -hr + 0.005), v(0.1, 0.12, 0.06), o.eyes, "SmoothPlastic", nil, { name = "Iris" })
	end
	-- брови на суставах
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local pos = v(s * 0.22, hc + 0.27, -hr + 0.02)
		rig:joint(side .. "Brow", "Head", pos, pos, v(0.1, 0.1, 0.1))
		rig:box(side .. "Brow", pos, v(0.26, 0.06, 0.06), o.hair:Lerp(rgb(0, 0, 0), 0.3), "SmoothPlastic", v(0, 0, s * -6), { name = "Brow" })
	end
	-- рот: тёмная полость на суставе Jaw выдвигается вперёд/вниз при открывании
	local mouthPivot = v(0, hc - 0.28, -hr + 0.12)
	rig:joint("Jaw", "Head", mouthPivot, mouthPivot, v(0.2, 0.1, 0.1))
	rig:ellipsoid("Jaw", v(0, hc - 0.28, -hr + 0.075), v(0.36, 0.2, 0.12), rgb(70, 24, 28), "SmoothPlastic", nil, { name = "MouthInside" })
	rig:ellipsoid("Jaw", v(0, hc - 0.335, -hr + 0.07), v(0.26, 0.05, 0.1), rgb(250, 250, 246), "SmoothPlastic", nil, { name = "LowerTeeth" })
	rig:ellipsoid("Head", v(0, hc - 0.235, -hr + 0.065), v(0.28, 0.06, 0.08), rgb(252, 252, 248), "SmoothPlastic", nil, { name = "UpperTeeth" })
	rig:ellipsoid("Head", v(0, hc - 0.215, -hr + 0.03), v(0.36, 0.05, 0.06), o.lips, "SmoothPlastic", nil, { name = "UpperLip" })
	rig.face = {
		jaw = { { joint = "Jaw", pos = v(0, -0.07, -0.07) } },
		brows = { { joint = "RightBrow", pos = v(0, 0.07, 0) }, { joint = "LeftBrow", pos = v(0, 0.07, 0) } },
		browR = { { joint = "RightBrow", pos = v(0, 0.07, 0) } },
		browL = { { joint = "LeftBrow", pos = v(0, 0.07, 0) } },
	}
	if o.beard then
		rig:ellipsoid("Head", v(0, hc - 0.32, -0.05), v(hr * 2.04, 0.5, hr * 2.02), o.beard, "SmoothPlastic", nil, { name = "Stubble", transparency = 0.35 })
	end

	-- ===== Причёска =====
	local hair = o.hair
	if o.hairStyle == "short" then
		rig:ellipsoid("Head", v(0, hc + 0.42, 0.04), v(hr * 2.08, 0.6, hr * 2.1), hair, "SmoothPlastic", nil, { name = "HairCap" })
		rig:ellipsoid("Head", v(0, hc + 0.62, -0.18), v(0.95, 0.42, 0.8), hair, "SmoothPlastic", v(-15, 0, 0), { name = "Quiff" })
		for _, s in { 1, -1 } do
			rig:ellipsoid("Head", v(s * (hr - 0.02), hc + 0.18, 0.12), v(0.18, 0.5, 0.95), hair, "SmoothPlastic", nil, { name = "HairSide" })
		end
		rig:ellipsoid("Head", v(0, hc + 0.1, hr - 0.05), v(1.1, 0.8, 0.3), hair, "SmoothPlastic", nil, { name = "HairBack" })
	elseif o.hairStyle == "bob" then
		rig:ellipsoid("Head", v(0, hc + 0.36, 0.06), v(hr * 2.3, 0.78, hr * 2.25), hair, "SmoothPlastic", nil, { name = "HairCap" })
		rig:ellipsoid("Head", v(0, hc + 0.36, -hr + 0.02), v(1.1, 0.34, 0.24), hair, "SmoothPlastic", v(10, 0, 0), { name = "Bangs" })
		for _, s in { 1, -1 } do
			rig:ellipsoid("Head", v(s * (hr + 0.06), hc - 0.12, 0.05), v(0.3, 1.0, 1.2), hair, "SmoothPlastic", nil, { name = "HairSide" })
		end
		rig:ellipsoid("Head", v(0, hc - 0.05, hr - 0.02), v(1.35, 1.05, 0.42), hair, "SmoothPlastic", nil, { name = "HairBack" })
	elseif o.hairStyle == "curly" then
		local n = 0
		for ring = 0, 2 do
			local y = hc + 0.5 - ring * 0.3
			local r = hr + 0.08 + ring * 0.03
			local count = 10 - ring
			for i = 0, count - 1 do
				local a = (i / count) * math.pi * 2
				local z = math.cos(a) * r
				-- лоб открыт: не ставим кудри спереди внизу
				if not (ring >= 1 and z < -r * 0.55) then
					n += 1
					rig:ball("Head", v(math.sin(a) * r, y, z + 0.06), 0.46 - ring * 0.04, hair:Lerp(rgb(0, 0, 0), (n % 3) * 0.06), "SmoothPlastic", { name = "Curl" })
				end
			end
		end
		rig:ellipsoid("Head", v(0, hc + 0.62, 0.05), v(1.4, 0.55, 1.4), hair, "SmoothPlastic", nil, { name = "CurlTop" })
	end

	-- ===== Очки на суставе Glasses (можно снимать/опускать) =====
	if o.glasses then
		local gp = v(0, hc + 0.1, -hr - 0.06)
		rig:joint("Glasses", "Head", gp, gp, v(0.2, 0.1, 0.1))
		for _, s in { 1, -1 } do
			local lens = if o.glasses == "round" then v(0.34, 0.3, 0.05) else v(0.4, 0.32, 0.05)
			rig:ellipsoid("Glasses", v(s * 0.24, hc + 0.08, -hr - 0.07), lens, o.glassesLens, "Glass", nil, {
				name = "Lens",
				transparency = o.glassesLensTransparency,
				reflectance = 0.15,
			})
			rig:ellipsoid("Glasses", v(s * 0.24, hc + 0.08, -hr - 0.065), lens + v(0.05, 0.05, -0.02), o.glassesFrame, "Metal", nil, { name = "Rim" })
			rig:box("Glasses", v(s * (hr + 0.02), hc + 0.14, -hr * 0.4), v(0.03, 0.03, hr * 1.2), o.glassesFrame, "Metal", nil, { name = "Temple" })
		end
		rig:box("Glasses", v(0, hc + 0.18, -hr - 0.075), v(0.22, 0.03, 0.03), o.glassesFrame, "Metal", nil, { name = "Bridge" })
	end

	return rig
end
