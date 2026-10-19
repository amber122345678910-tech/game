--!nocheck
-- Руки (рукава пиджака, меховые кисти с 4 пальцами и большим), украшения (часы, перстни),
-- ноги (расклёшенные джинсы), обувь.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
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

		-- ===== Рукав =====
		g:ball(UA, V(sx, S.shoulderY - 0.02, 0), 0.66, P.suit, "SmoothPlastic")
		g:ellSeg(UA, V(sx, S.shoulderY + 0.12, 0), V(sx, elbowY - 0.12, 0.01), 0.6, 0.62, P.suit, "SmoothPlastic", V(0, 0, -1))
		g:ball(UA, V(sx, elbowY, 0.01), 0.53, P.suit, "SmoothPlastic")
		g:ellSeg(LA, V(sx, elbowY + 0.12, 0.01), V(sx, wristY + 0.14, 0), 0.54, 0.56, P.suit, "SmoothPlastic", V(0, 0, -1))
		-- манжета: чёткий срез + тёмная «глубина» рукава
		g:cylSeg(LA, V(sx, wristY + 0.36, 0), V(sx, wristY + 0.13, 0), 0.52, P.suit, "SmoothPlastic")
		g:cylSeg(LA, V(sx, wristY + 0.14, 0), V(sx, wristY + 0.125, 0), 0.44, P.suitDark, "SmoothPlastic")
		-- мех предплечья, торчащий из манжеты
		g:ellSeg(LA, V(sx, wristY + 0.4, 0), V(sx, wristY - 0.04, 0), 0.36, 0.42, P.furHand, "Carpet", V(0, 0, -1))

		-- ===== Кисть =====
		g:ell(HD, V(sx, wristY - 0.02, 0), V(0.4, 0.4, 0.48), P.furHand, "Carpet") -- запястье (шарнир)
		g:ell(HD, V(sx, wristY - 0.24, 0.0), V(0.36, 0.6, 0.68), P.furHand, "Carpet") -- ладонь
		g:ell(HD, V(sx + s * 0.04, wristY - 0.26, 0.02), V(0.3, 0.52, 0.64), P.furHand, "Carpet") -- тыльная сторона
		g:ell(HD, V(sx, baseY + 0.04, 0.0), V(0.32, 0.2, 0.68), P.furHand, "Carpet") -- ряд костяшек
		g:ell(HD, V(sx - s * 0.05, wristY - 0.2, -0.24), V(0.24, 0.36, 0.24), P.furHand, "Carpet") -- подушка большого пальца
		local zs = { Index = -0.36, Middle = -0.12, Ring = 0.12, Pinky = 0.34 }
		for _, f in { "Index", "Middle", "Ring", "Pinky" } do
			local z = zs[f] * S.handW
			local k = if f == "Pinky" then 0.8 elseif f == "Middle" then 1.08 else 1
			local l1, l2 = S.fingerLen1 * k, S.fingerLen2 * k
			local w = if f == "Pinky" then 0.155 else 0.178
			local b1, b2 = side .. f .. "1", side .. f .. "2"
			g:ball(HD, V(sx, baseY + 0.01, z), w * 1.02, P.furHand, "Carpet")
			g:ellSeg(b1, V(sx, baseY + 0.04, z), V(sx, baseY - l1 - 0.03, z), w, w, P.furHand, "Carpet", V(0, 0, -1))
			g:ball(b1, V(sx, baseY - l1, z), w * 0.94, P.furHand, "Carpet")
			g:ellSeg(b2, V(sx, baseY - l1 + 0.03, z), V(sx, baseY - l1 - l2 - 0.02, z), w * 0.92, w * 0.92, P.furHand, "Carpet", V(0, 0, -1))
			-- подушечка пальца (темнее, со стороны ладони)
			g:ell(b2, V(sx - s * 0.04, baseY - l1 - l2 * 0.6, z), V(0.08, 0.14, 0.12), P.furDark, "Carpet")
		end
		-- большой палец
		local tz = -0.5 * S.handW
		local ty = wristY - S.handLen * 0.35
		g:ellSeg(side .. "Thumb1", V(sx, ty + 0.05, tz), V(sx, ty - S.thumbLen1 - 0.03, tz), 0.2, 0.2, P.furHand, "Carpet", V(1, 0, 0))
		g:ball(side .. "Thumb1", V(sx, ty - S.thumbLen1, tz), 0.18, P.furHand, "Carpet")
		g:ellSeg(side .. "Thumb2", V(sx, ty - S.thumbLen1 + 0.03, tz), V(sx, ty - S.thumbLen1 - S.thumbLen2 - 0.02, tz), 0.17, 0.17, P.furHand, "Carpet", V(1, 0, 0))

		-- ===== Украшения =====
		local midZ = zs.Middle * S.handW
		local ringY = baseY - S.fingerLen1 * 1.08 * 0.45
		if side == "Right" then
			-- тяжёлый золотой перстень-печатка с ониксом на среднем пальце
			local b = side .. "Middle1"
			g:cylSeg(b, V(sx, ringY + 0.03, midZ), V(sx, ringY - 0.03, midZ), 0.205, P.gold, "Foil")
			g:cylSeg(b, V(sx + s * 0.06, ringY, midZ), V(sx + s * 0.125, ringY, midZ), 0.17, P.gold, "Foil")
			g:cylSeg(b, V(sx + s * 0.12, ringY, midZ), V(sx + s * 0.132, ringY, midZ), 0.13, P.onyx, "SmoothPlastic", { reflectance = 0.25 })
		else
			-- розовое золото: печатка-монета на среднем, тонкое кольцо на безымянном
			local b = side .. "Middle1"
			g:cylSeg(b, V(sx, ringY + 0.028, midZ), V(sx, ringY - 0.028, midZ), 0.2, P.roseGold, "Foil")
			g:cylSeg(b, V(sx + s * 0.06, ringY, midZ), V(sx + s * 0.12, ringY, midZ), 0.17, P.roseGold, "Foil")
			g:cylSeg(b, V(sx + s * 0.118, ringY, midZ), V(sx + s * 0.128, ringY, midZ), 0.13, P.roseGold:Lerp(P.tooth, 0.2), "Foil")
			local rz = zs.Ring * S.handW
			g:cylSeg(side .. "Ring1", V(sx, ringY + 0.015, rz), V(sx, ringY - 0.015, rz), 0.195, P.gold, "Foil")
			-- золотые часы на левом запястье
			local wy = wristY + 0.08
			g:cylSeg(LA, V(sx, wy + 0.06, 0), V(sx, wy - 0.06, 0), 0.43, P.watch, "Metal")
			g:cylSeg(LA, V(sx, wy + 0.022, 0), V(sx, wy - 0.022, 0), 0.445, P.gold, "Foil")
			-- циферблат с безелем (снаружи запястья)
			g:cylSeg(LA, V(sx - 0.17, wy, 0), V(sx - 0.235, wy, 0), 0.22, P.gold, "Foil")
			g:cylSeg(LA, V(sx - 0.23, wy, 0), V(sx - 0.24, wy, 0), 0.17, P.champagne, "SmoothPlastic")
			g:box(LA, V(sx - 0.243, wy + 0.025, 0), V(0.005, 0.06, 0.012), P.goldDeep, "SmoothPlastic")
			g:box(LA, V(sx - 0.243, wy, 0.018), V(0.005, 0.012, 0.04), P.goldDeep, "SmoothPlastic")
		end
	end

	-- ===== Ноги =====
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local hx = s * S.hipX
		local UL, LL, FT = side .. "UpperLeg", side .. "LowerLeg", side .. "Foot"
		g:ball(UL, V(hx, S.hipY, 0.02), 0.84, P.jeans, "Fabric")
		g:ellSeg(UL, V(hx, S.hipY + 0.15, 0.02), V(hx, S.kneeY - 0.12, 0.0), 0.8, 0.82, P.jeans, "Fabric", V(0, 0, -1))
		g:ball(UL, V(hx, S.kneeY, 0.0), 0.64, P.jeans, "Fabric")
		g:ellSeg(LL, V(hx, S.kneeY + 0.14, 0.0), V(hx, 0.5, 0.0), 0.62, 0.64, P.jeans, "Fabric", V(0, 0, -1))
		-- клёш
		g:ell(LL, V(hx, 0.62, -0.02), V(0.8, 0.9, 0.84), P.jeans, "Fabric")
		g:cylSeg(LL, V(hx, 0.42, -0.03), V(hx, 0.13, -0.03), 0.9, P.jeans, "Fabric")
		g:cylSeg(LL, V(hx, 0.135, -0.03), V(hx, 0.12, -0.03), 0.8, P.jeansDark, "Fabric")
		-- боковой шов
		g:ellSeg(LL, V(hx + s * 0.3, 1.2, 0.0), V(hx + s * 0.44, 0.15, -0.03), 0.03, 0.03, P.jeansDark, "Fabric")

		-- ===== Обувь (чёрные кожаные, каблук) =====
		g:rbox(FT, V(hx, 0.035, -0.2), V(0.5, 0.07, 1.2), P.sole, "Rubber")
		g:box(FT, V(hx, 0.09, 0.28), V(0.4, 0.18, 0.26), P.sole, "Rubber")
		g:ell(FT, V(hx, 0.22, -0.08), V(0.48, 0.38, 0.92), P.shoe, "Leather", nil, { reflectance = 0.08 })
		g:ell(FT, V(hx, 0.15, -0.52), V(0.44, 0.24, 0.6), P.shoe, "Leather", nil, { reflectance = 0.08 })
		g:ellSeg(FT, V(hx, 0.15, 0.1), V(hx, 0.6, 0.05), 0.44, 0.48, P.shoe, "Leather", V(0, 0, -1))
	end
end

return Limbs
