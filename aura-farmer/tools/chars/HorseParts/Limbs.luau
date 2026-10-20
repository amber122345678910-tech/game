--!nocheck
-- Руки (рукава пиджака, меховые кисти с 4 пальцами и большим), украшения (часы, перстни),
-- ноги (расклёшенные джинсы), обувь.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")

local Limbs = {}

function Limbs.build(g, opts)
	local rig = g.rig
	local S = rig.P
	local elbowY = S.shoulderY - S.upperArm -- 3.40
	local wristY = elbowY - S.lowerArm -- 2.22
	local baseY = wristY - S.handLen -- 1.72

	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local sx = s * S.shoulderX
		local UA, LA, HD = side .. "UpperArm", side .. "LowerArm", side .. "Hand"

		-- ===== Рукав: атласный, «головка» рукава с валиком у подплечника, сужение к манжете =====
		local SAT = { reflectance = 0.04 }
		-- корень рукава (шар вокруг плечевого сустава — без щелей при подъёме руки)
		g:ell(UA, V(sx, S.shoulderY - 0.15, 0.06), V(0.62, 0.62, 0.68), P.suit, "SmoothPlastic")
		-- верхний рукав: прямой цилиндр (крой рукава, без «надутого шара»)
		g:cylSeg(UA, V(sx, S.shoulderY - 0.06, 0.06), V(sx, elbowY, 0.05), 0.6, P.suit, "SmoothPlastic", { reflectance = 0.04, name = "Sleeve" })
		-- локоть: шар чуть меньше рукава (без перетяжки при сгибе)
		g:ball(LA, V(sx, elbowY, 0.05), 0.58, P.suit, "SmoothPlastic", { reflectance = 0.04 })
		-- предплечье: цилиндр, сужается к манжете (вторая ступень)
		g:cylSeg(LA, V(sx, elbowY, 0.05), V(sx, wristY + 0.36, 0.02), 0.56, P.suit, "SmoothPlastic", { reflectance = 0.04, name = "Sleeve" })
		g:ball(LA, V(sx, wristY + 0.36, 0.02), 0.53, P.suit, "SmoothPlastic", { reflectance = 0.04 })
		-- манжета: чёткий срез (настоящий цилиндр), кант и тёмная «глубина» рукава
		g:cylSeg(LA, V(sx, wristY + 0.36, 0), V(sx, wristY + 0.12, 0), 0.5, P.suit, "SmoothPlastic", SAT)
		g:cylSeg(LA, V(sx, wristY + 0.155, 0), V(sx, wristY + 0.115, 0), 0.52, P.suit:Lerp(P.suitLight, 0.3), "SmoothPlastic", SAT)
		g:cylSeg(LA, V(sx, wristY + 0.125, 0), V(sx, wristY + 0.105, 0), 0.44, P.suitDeep, "SmoothPlastic")
		-- пуговицы на манжете (сзади-снаружи)
		for k = 0, 1 do
			local yy = wristY + 0.2 + k * 0.1
			g:cylSeg(LA, V(sx + s * 0.12, yy, 0.23), V(sx + s * 0.135, yy, 0.25), 0.055, P.suitDark, "SmoothPlastic")
		end
		-- мех предплечья, торчащий из манжеты
		g:ellSeg(LA, V(sx, wristY + 0.3, 0), V(sx, wristY - 0.06, 0), 0.38, 0.44, P.furHand, "SmoothPlastic", V(0, 0, -1))
		for k, a in { 0, 1, 2, 3, 4 } do
			local th = rad(a * 72 + 20)
			local d = V(math.cos(th) * s, 0, math.sin(th))
			g:ellSeg(LA, V(sx, wristY + 0.08, 0) + d * 0.12, V(sx, wristY - 0.02, 0) + d * 0.22, 0.13, 0.1, if k % 2 == 0 then P.handLight else P.furHand, "SmoothPlastic", d, { castShadow = false })
		end

		-- ===== Кисть: крупная меховая «лапа» — 4 толстых пальца и большой, костяшки, мех разных тонов =====
		-- (поза покоя: ладонь к бедру (−s·X), тыльная сторона наружу (+s·X), пальцы вниз, указательный спереди)
		local fur = P.furHand
		local light, dark = P.handLight, P.handDark
		local NOSH = { castShadow = false }
		g:ell(HD, V(sx, wristY - 0.02, 0), V(0.4, 0.42, 0.5), fur, "SmoothPlastic") -- запястье (шарнир)
		g:ell(HD, V(sx - s * 0.06, wristY - 0.27, 0.0), V(0.26, 0.52, 0.6), dark, "SmoothPlastic") -- ладонь
		g:ell(HD, V(sx + s * 0.04, wristY - 0.27, 0.01), V(0.3, 0.6, 0.7), fur, "SmoothPlastic", nil, { name = "HandBack" }) -- тыльная сторона
		g:ell(HD, V(sx + s * 0.075, wristY - 0.26, 0.02), V(0.2, 0.44, 0.5), fur:Lerp(light, 0.5), "SmoothPlastic", nil, NOSH) -- светлый мех на тыле
		g:ell(HD, V(sx - s * 0.07, wristY - 0.2, -0.21), V(0.24, 0.38, 0.26), dark:Lerp(fur, 0.4), "SmoothPlastic") -- подушка большого пальца
		-- пряди по краям кисти (силуэт «лохматый»)
		for k, t in { { 0.05, -0.12, 0.3 }, { 0.02, -0.3, 0.33 }, { 0.08, -0.05, -0.27 } } do
			local base = V(sx + s * t[1], wristY + t[2], t[3])
			local d = V(s * 0.2, -0.6, if t[3] > 0 then 0.6 else -0.6)
			g:ellSeg(HD, base, base + d.Unit * 0.14, 0.1, 0.08, if k % 2 == 0 then light else fur, "SmoothPlastic", nil, NOSH)
		end
		local zs = { Index = -0.36, Middle = -0.12, Ring = 0.12, Pinky = 0.34 }
		for fi, f in { "Index", "Middle", "Ring", "Pinky" } do
			local z = zs[f] * S.handW
			local k = if f == "Pinky" then 0.8 elseif f == "Middle" then 1.08 else 1
			local l1, l2 = S.fingerLen1 * k, S.fingerLen2 * k
			local w = if f == "Pinky" then 0.135 else 0.155 -- ширина поперёк ряда
			local t = w * 0.95 -- толщина (ладонь — тыл)
			local b1, b2 = side .. f .. "1", side .. f .. "2"
			local tone = if fi % 2 == 0 then fur else fur:Lerp(light, 0.25)
			-- основание пальца и костяшка (выпуклость на тыльной стороне)
			g:ell(HD, V(sx, baseY + 0.02, z), V(t * 0.95, w * 1.1, w * 1.02), tone, "SmoothPlastic")
			g:ell(HD, V(sx + s * 0.06, baseY + 0.03, z), V(0.1, 0.15, w * 0.9), fur:Lerp(light, 0.25), "SmoothPlastic", nil, { name = "Knuckle" })
			-- основная фаланга (концы заходят за суставы — без «перетяжек»)
			g:ellSeg(b1, V(sx, baseY + 0.09, z), V(sx, baseY - l1 - 0.09, z), t, w, tone, "SmoothPlastic", V(0, 0, -1))
			-- средний сустав: шар чуть тоньше пальца (виден только на сгибе)
			g:ell(b1, V(sx + s * 0.01, baseY - l1, z), V(t * 0.8, w * 0.8, w * 0.8), tone:Lerp(light, 0.2), "SmoothPlastic")
			-- концевая фаланга с подушечкой
			g:ellSeg(b2, V(sx, baseY - l1 + 0.08, z), V(sx, baseY - l1 - l2 - 0.035, z), t * 0.95, w * 0.95, tone, "SmoothPlastic", V(0, 0, -1))
			g:ell(b2, V(sx - s * 0.035, baseY - l1 - l2 * 0.62, z), V(t * 0.62, l2 * 0.7, w * 0.82), dark, "SmoothPlastic", nil, NOSH)
		end
		-- светлые пряди поперёк ряда костяшек (ломают «сосисочный» силуэт)
		for k, z in { -0.15, 0.1 } do
			local base = V(sx + s * 0.1, baseY + 0.07, z * S.handW)
			g:ellSeg(HD, base + V(0, 0.02, -0.06), base + V(s * 0.03, -0.03, 0.08), 0.1, 0.06, light, "SmoothPlastic", V(s, 0, 0), NOSH)
		end
		-- большой палец
		local tz = -0.5 * S.handW
		local ty = wristY - S.handLen * 0.35
		g:ellSeg(side .. "Thumb1", V(sx, ty + 0.08, tz), V(sx, ty - S.thumbLen1 - 0.05, tz), 0.21, 0.22, fur, "SmoothPlastic", V(1, 0, 0))
		g:ell(side .. "Thumb1", V(sx, ty - S.thumbLen1, tz), V(0.19, 0.19, 0.2), fur:Lerp(light, 0.3), "SmoothPlastic")
		g:ellSeg(side .. "Thumb2", V(sx, ty - S.thumbLen1 + 0.05, tz), V(sx, ty - S.thumbLen1 - S.thumbLen2 - 0.035, tz), 0.19, 0.2, fur, "SmoothPlastic", V(1, 0, 0))
		g:ell(side .. "Thumb2", V(sx - s * 0.04, ty - S.thumbLen1 - S.thumbLen2 * 0.6, tz), V(0.12, 0.14, 0.15), dark, "SmoothPlastic", nil, NOSH)

		-- ===== Украшения =====
		local midZ = zs.Middle * S.handW
		local ringY = baseY - S.fingerLen1 * 1.08 * 0.45
		if side == "Right" then
			-- тяжёлый золотой перстень-печатка с плоской серой печаткой на среднем пальце
			local b = side .. "Middle1"
			g:cylSeg(b, V(sx, ringY + 0.035, midZ), V(sx, ringY - 0.035, midZ), 0.215, P.gold, "Foil", { name = "Ring" })
			g:cylSeg(b, V(sx + s * 0.05, ringY, midZ), V(sx + s * 0.13, ringY, midZ), 0.175, P.gold, "Foil", { name = "Ring" })
			-- плоская светло-серая печатка (как в S02), на золотом столике
			g:cylSeg(b, V(sx + s * 0.124, ringY, midZ), V(sx + s * 0.142, ringY, midZ), 0.145, Color3.fromHex("A8A399"), "Metal", { name = "Onyx" })
		else
			-- розовое золото: печатка-монета на среднем, тонкое кольцо на безымянном
			local b = side .. "Middle1"
			g:cylSeg(b, V(sx, ringY + 0.03, midZ), V(sx, ringY - 0.03, midZ), 0.21, P.roseGold, "Foil", { name = "Ring" })
			g:cylSeg(b, V(sx + s * 0.05, ringY, midZ), V(sx + s * 0.125, ringY, midZ), 0.175, P.roseGold, "Foil", { name = "Ring" })
			g:cylSeg(b, V(sx + s * 0.122, ringY, midZ), V(sx + s * 0.134, ringY, midZ), 0.145, P.roseGold:Lerp(P.goldDeep, 0.25), "Metal")
			local rz = zs.Ring * S.handW
			g:cylSeg(side .. "Ring1", V(sx, ringY + 0.015, rz), V(sx, ringY - 0.015, rz), 0.195, P.gold, "Foil")
			-- золотые часы на левом запястье: браслет из звеньев (полированные/сатиновые), корпус, рифлёный безель
			local wy = wristY + 0.06
			local R = 0.215
			for k = 0, 15 do
				local th = rad(k * 360 / 16)
				local d = V(math.cos(th), 0, math.sin(th))
				local pos = V(sx, wy, 0) + d * R
				local cf = CFrame.fromMatrix(pos, V(-d.Z, 0, d.X), V(0, 1, 0), d)
				local mid = k % 2 == 0
				g:box(LA, cf, V(0.095, if mid then 0.14 else 0.13, 0.05), if mid then P.gold else P.watch, if mid then "Foil" else "Metal", nil, { name = "Watch" })
			end
			-- корпус и циферблат снаружи запястья (−X у левой руки)
			local o = V(sx - R - 0.01, wy, 0)
			g:cylSeg(LA, o + V(0.02, 0, 0), o + V(-0.05, 0, 0), 0.2, P.gold, "Foil", { name = "Watch" })
			g:cylSeg(LA, o + V(-0.048, 0, 0), o + V(-0.068, 0, 0), 0.19, P.watch, "Metal")
			g:cylSeg(LA, o + V(-0.066, 0, 0), o + V(-0.073, 0, 0), 0.13, P.watchFace, "SmoothPlastic", { name = "WatchFace" })
			g:box(LA, o + V(-0.076, 0.022, 0), V(0.006, 0.054, 0.012), P.goldDeep, "SmoothPlastic")
			g:box(LA, o + V(-0.077, 0.0, 0.016), V(0.006, 0.012, 0.036), P.goldDeep, "SmoothPlastic")
		end
	end

	-- ===== Ноги =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local hx = s * S.hipX
		local UL, LL, FT = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
		local hip = V(hx, S.hipY, 0.02)
		local knee = V(hx, S.kneeY, 0)
		local J = P.jeans
		-- бедро: шар тазобедренного сустава + прямая «труба» джинсов (Fabric — фактура денима)
		g:ball(UL, hip + V(0, 0.02, 0), 0.74, J, "Fabric")
		g:cylSeg(UL, hip + V(0, 0.02, 0.01), knee, 0.7, J, "Fabric", { name = "Thigh" })
		g:ball(UL, knee, 0.66, J, "Fabric")
		-- голень: прямая труба, затем клёш — частые ступени цилиндров (уступы ~0.012, читаются как плавный конус)
		g:cylSeg(LL, knee, V(hx, 0.86, -0.01), 0.64, J, "Fabric")
		local steps = { { 0.88, 0.7, 0.665 }, { 0.72, 0.58, 0.69 }, { 0.6, 0.48, 0.715 }, { 0.5, 0.39, 0.74 }, { 0.41, 0.32, 0.765 }, { 0.34, 0.25, 0.79 } }
		for _, st in steps do
			g:cylSeg(LL, V(hx, st[1], -0.012), V(hx, st[2], -0.025), st[3], J, "Fabric")
		end
		-- подол: подшивка (чуть темнее) и тёмная внутренность штанины
		g:cylSeg(LL, V(hx, 0.27, -0.025), V(hx, 0.24, -0.025), 0.81, P.jeansDark, "Fabric")
		g:cylSeg(LL, V(hx, 0.255, -0.025), V(hx, 0.235, -0.025), 0.7, P.jeansDark:Lerp(P.shoe, 0.6), "Fabric")

		-- ===== Обувь: чёрные кожаные остроносые ботинки на каблуке =====
		local SH = { reflectance = 0.08 }
		g:rbox(FT, V(hx, 0.035, -0.3), V(0.4, 0.07, 1.3), P.sole, "Rubber")
		g:box(FT, V(hx, 0.1, 0.25), V(0.36, 0.2, 0.26), P.sole, "Rubber") -- каблук
		g:ell(FT, V(hx, 0.2, -0.04), V(0.44, 0.36, 0.8), P.shoe, "SmoothPlastic", nil, SH)
		g:ellSeg(FT, V(hx, 0.17, -0.2), V(hx, 0.085, -1.04), 0.32, 0.16, P.shoe, "SmoothPlastic", nil, SH) -- острый нос (торчит из-под клёша)
		g:ellSeg(FT, V(hx, 0.17, -0.5), V(hx, 0.13, -0.86), 0.16, 0.05, P.shoeHi, "SmoothPlastic", nil, { castShadow = false }) -- блик
		g:ellSeg(FT, V(hx, 0.12, 0.1), V(hx, 0.6, 0.04), 0.42, 0.46, P.shoe, "SmoothPlastic", V(0, 0, -1), SH) -- голенище
	end
end

return Limbs
