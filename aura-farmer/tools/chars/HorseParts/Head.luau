--!nocheck
-- Голова коня: череп, морда, ноздри, глаза, уши, хохолок, брови, рот (зубы, дёсны, губы, язык), шея.
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local V = Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")

local Head = {}

-- Зубная дуга (вид сверху): эллипс с центром z0, полуоси ax (по X) и az (по Z); phi в градусах (0 — центр спереди).
local function arch(ax, az, z0, phi)
	local p = rad(phi)
	local x = ax * math.sin(p)
	local z = z0 - az * math.cos(p)
	local n = V(math.sin(p) / ax, 0, -math.cos(p) / az).Unit -- наружная нормаль
	return x, z, n
end

-- CFrame детали на дуге: «лицо» (-Z) смотрит наружу по нормали.
local function archCF(pos, n, tiltX)
	local back = -n
	local up = V(0, 1, 0)
	local right = up:Cross(back).Unit
	local cf = CFrame.fromMatrix(pos, right, up, back)
	if tiltX then
		cf = cf * CFrame.Angles(rad(tiltX), 0, 0)
	end
	return cf
end

-- линия смыкания зубов: поднимается к уголкам рта (улыбка)
local BITE_Y = 5.735
local function biteY(phi)
	local k = math.abs(phi) / 100
	return BITE_Y + 0.07 * k * k
end

function Head.build(g, opts)
	local rig = g.rig

	-- ===== Шея (кость Head, вращается вокруг Neck y=4.95) =====
	g:ellSeg("Head", V(0, 4.78, 0.1), V(0, 5.95, -0.02), 0.86, 0.92, P.fur, "Carpet", V(0, 0, -1))
	g:ellSeg("Head", V(0, 5.0, -0.18), V(0, 5.6, -0.42), 0.6, 0.5, P.furGrey, "Carpet", V(0, 0, -1)) -- горло
	g:ellSeg("Head", V(0, 5.2, 0.32), V(0, 6.35, 0.22), 0.6, 0.5, P.fur, "Carpet", V(0, 0, -1)) -- загривок

	-- ===== Череп =====
	g:ell("Head", V(0, 6.33, -0.02), V(0.98, 0.9, 1.12), P.fur, "Carpet")
	g:ell("Head", V(0, 6.27, -0.5), V(0.86, 0.66, 0.62), P.furWarm, "Carpet") -- лоб
	-- переносица (длинная, светлее)
	g:ellSeg("Head", V(0, 6.25, -0.45), V(0, 6.02, -1.5), 0.5, 0.42, P.furWarm, "Carpet")
	-- боковые плоскости морды (седоватые)
	for _, s in { 1, -1 } do
		g:ellSeg("Head", V(s * 0.2, 6.12, -0.42), V(s * 0.17, 5.98, -1.35), 0.42, 0.52, P.furGrey, "Carpet", V(s * 0.3, 1, 0))
		-- скула/щека под глазом
		g:ell("Head", V(s * 0.3, 6.0, -0.45), V(0.42, 0.55, 0.7), P.furGrey, "Carpet", V(10, 0, 0))
		-- ганаши (большие щёки сзади-снизу)
		g:ell("Head", V(s * 0.24, 5.66, -0.2), V(0.56, 0.8, 0.95), P.furGrey, "Carpet", V(-12, 0, 0))
	end
	g:ell("Head", V(0, 5.56, -0.12), V(0.62, 0.62, 0.8), P.furGrey, "Carpet") -- подчелюстное пространство

	-- ===== Морда и нос =====
	g:ell("Head", V(0, 6.07, -1.3), V(0.82, 0.48, 0.72), P.muzzle, "Carpet")
	g:ell("Head", V(0, 6.08, -1.5), V(0.78, 0.46, 0.4), P.nose, "SmoothPlastic")
	for _, s in { 1, -1 } do
		-- доли ноздрей
		g:ell("Head", V(s * 0.17, 6.1, -1.62), V(0.3, 0.32, 0.24), P.nose, "SmoothPlastic", V(0, 0, s * -12))
		-- ноздри (запятые)
		g:ell("Head", V(s * 0.19, 6.08, -1.735), V(0.11, 0.19, 0.04), P.nostril, "SmoothPlastic", V(-10, 0, s * -18))
		g:ell("Head", V(s * 0.15, 6.0, -1.72), V(0.07, 0.07, 0.04), P.nostril, "SmoothPlastic", V(-25, 0, 0))
		-- крылья ноздрей сверху (складка)
		g:ellSeg("Head", V(s * 0.06, 6.22, -1.68), V(s * 0.3, 6.14, -1.58), 0.07, 0.06, P.nose, "SmoothPlastic")
	end
	g:ellSeg("Head", V(0, 6.2, -1.7), V(0, 5.98, -1.74), 0.07, 0.05, P.nose, "SmoothPlastic") -- перегородка

	-- ===== Рот: верхняя часть (Head) =====
	-- нёбо/тёмная полость
	g:ell("Head", V(0, 5.8, -1.05), V(0.56, 0.22, 0.85), P.mouthIn, "SmoothPlastic")
	-- верхние дёсны
	local gumPts = {}
	for phi = -96, 96, 16 do
		local x, z = arch(0.315, 0.49, -1.05, phi)
		table.insert(gumPts, V(x, biteY(phi) + 0.145, z))
	end
	for i = 1, #gumPts - 1 do
		g:ellSeg("Head", gumPts[i], gumPts[i + 1], 0.075, 0.1, P.gum, "SmoothPlastic")
	end
	-- верхние зубы (крупные, «человеческие»)
	local upper = {
		{ 6, 0.118, 0.158 },
		{ 18.5, 0.104, 0.142 },
		{ 31, 0.096, 0.134 },
		{ 44, 0.09, 0.118 },
		{ 58, 0.086, 0.106 },
		{ 73, 0.08, 0.096 },
		{ 88, 0.074, 0.086 },
	}
	for _, t in upper do
		for _, s in { 1, -1 } do
			local phi = s * t[1]
			local x, z, n = arch(0.30, 0.48, -1.05, phi)
			local yb = biteY(phi)
			local h = t[3]
			g:rbox("Head", archCF(V(x, yb + h / 2, z), n, -4), V(t[2], h, 0.075), P.tooth, "SmoothPlastic")
		end
	end

	-- ===== Нижняя челюсть (Jaw) =====
	g:ellSeg("Jaw", V(0, 5.5, -0.25), V(0, 5.5, -1.42), 0.66, 0.42, P.furGrey, "Carpet")
	g:ell("Jaw", V(0, 5.42, -1.2), V(0.62, 0.5, 0.52), P.muzzle, "Carpet") -- подбородок
	g:ell("Jaw", V(0, 5.38, -0.75), V(0.6, 0.42, 0.8), P.muzzle, "Carpet")
	-- полость и язык
	g:ell("Jaw", V(0, 5.62, -1.0), V(0.52, 0.18, 0.8), P.mouthIn, "SmoothPlastic")
	g:ell("Jaw", V(0, 5.66, -1.12), V(0.4, 0.12, 0.6), P.tongue, "SmoothPlastic")
	-- нижние дёсны
	local lgum = {}
	for phi = -92, 92, 23 do
		local x, z = arch(0.285, 0.455, -1.05, phi)
		table.insert(lgum, V(x, biteY(phi) - 0.13, z))
	end
	for i = 1, #lgum - 1 do
		g:ellSeg("Jaw", lgum[i], lgum[i + 1], 0.07, 0.08, P.gum, "SmoothPlastic")
	end
	-- нижние зубы
	local lower = {
		{ 5.5, 0.098, 0.12 },
		{ 16.5, 0.092, 0.115 },
		{ 28, 0.088, 0.11 },
		{ 40, 0.084, 0.102 },
		{ 53, 0.08, 0.094 },
		{ 67, 0.076, 0.086 },
		{ 82, 0.07, 0.078 },
	}
	for _, t in lower do
		for _, s in { 1, -1 } do
			local phi = s * t[1]
			local x, z, n = arch(0.275, 0.445, -1.05, phi)
			local yb = biteY(phi) - 0.006
			local h = t[3]
			g:rbox("Jaw", archCF(V(x, yb - h / 2, z), n, 4), V(t[2], h, 0.07), P.tooth, "SmoothPlastic")
		end
	end
	-- нижняя губа (толстая, персиковая) по дуге
	local llip = {}
	for phi = -104, 104, 13 do
		local x, z = arch(0.335, 0.52, -1.05, phi)
		local k = math.abs(phi) / 104
		table.insert(llip, V(x, biteY(phi) - 0.15 + 0.06 * k * k, z))
	end
	for i = 1, #llip - 1 do
		g:ellSeg("Jaw", llip[i], llip[i + 1], 0.11, 0.1, P.lip, "SmoothPlastic")
	end

	-- ===== Верхняя губа (UpperLip) =====
	local ulip = {}
	for phi = -104, 104, 13 do
		local x, z = arch(0.345, 0.535, -1.05, phi)
		local k = math.abs(phi) / 104
		table.insert(ulip, V(x, biteY(phi) + 0.17 - 0.07 * k * k, z))
	end
	for i = 1, #ulip - 1 do
		g:ellSeg("UpperLip", ulip[i], ulip[i + 1], 0.12, 0.1, P.lip, "SmoothPlastic")
	end
	-- шерсть над губой (тёмная) — переход к носу
	for i = 2, #ulip - 2, 2 do
		local p = ulip[i]
		g:ell("UpperLip", p + V(0, 0.07, 0) + (p - V(0, p.Y, -1.05)).Unit * -0.02, V(0.2, 0.12, 0.2), P.muzzle, "Carpet")
	end

	-- ===== Глаза =====
	for _, s in { 1, -1 } do
		local side = if s == 1 then "Right" else "Left"
		local c = V(s * 0.34, 6.2, -0.6)
		local look = V(s * 0.42, 0.02, -1).Unit
		local cf = CFrame.lookAt(c, c + look)
		g:ell("Head", cf, V(0.21, 0.17, 0.16), P.eyeWhite, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, -0.005, -0.07), V(0.115, 0.115, 0.04), P.iris, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, -0.005, -0.082), V(0.06, 0.07, 0.02), P.pupil, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0.02, 0.02, -0.088), V(0.025, 0.025, 0.01), P.tooth, "SmoothPlastic") -- блик
		-- веки: верхнее прикрыто наполовину (расслабленный «крутой» взгляд)
		g:ell("Head", cf * CFrame.new(0, 0.045, -0.005) * CFrame.Angles(rad(-8), 0, 0), V(0.235, 0.1, 0.185), P.fur, "Carpet")
		g:ell("Head", cf * CFrame.new(0, -0.07, 0.0), V(0.23, 0.07, 0.17), P.furGrey, "Carpet")
		-- надбровная дуга
		g:ellSeg("Head", V(s * 0.16, 6.36, -0.66), V(s * 0.47, 6.33, -0.48), 0.14, 0.12, P.furWarm, "Carpet")
		-- брови (на суставах бровей)
		g:ellSeg(side .. "Brow", V(s * 0.12, 6.47, -0.7), V(s * 0.46, 6.47, -0.56), 0.075, 0.06, P.furDark, "Carpet", V(0, 1, 0))
		_ = side
	end

	-- ===== Уши =====
	for _, s in { 1, -1 } do
		local ear = if s == 1 then "RightEar" else "LeftEar"
		local base = V(s * 0.36, 6.6, 0.12)
		local tip = V(s * 0.5, 7.22, 0.06)
		g:ellSeg(ear, base + V(0, -0.05, 0), tip, 0.28, 0.2, P.fur, "Carpet", V(0, 0, -1))
		g:ellSeg(ear, base:Lerp(tip, 0.45), tip + V(s * 0.01, 0.05, -0.01), 0.17, 0.12, P.fur, "Carpet", V(0, 0, -1))
		-- внутренняя сторона (смотрит вперёд)
		g:ellSeg(ear, base + V(0, 0.06, -0.075), base:Lerp(tip, 0.88) + V(0, 0, -0.045), 0.16, 0.06, P.earIn, "Carpet", V(0, 0, -1))
	end

	-- ===== Хохолок (чёрные «иглы» между ушами) =====
	local spikes = {
		{ V(0, 6.7, 0.1), V(0.02, 7.2, -0.22), 0.22 },
		{ V(0.08, 6.72, 0.0), V(0.16, 7.12, -0.32), 0.18 },
		{ V(-0.08, 6.72, 0.0), V(-0.15, 7.13, -0.3), 0.18 },
		{ V(0, 6.72, -0.12), V(0.0, 7.0, -0.48), 0.18 },
		{ V(0.14, 6.68, 0.12), V(0.24, 7.05, -0.05), 0.15 },
		{ V(-0.14, 6.68, 0.12), V(-0.25, 7.04, -0.06), 0.15 },
		{ V(0, 6.66, 0.25), V(0.03, 7.08, 0.12), 0.17 },
		{ V(0.06, 6.7, -0.2), V(0.1, 6.92, -0.56), 0.13 },
		{ V(-0.06, 6.7, -0.2), V(-0.1, 6.9, -0.55), 0.13 },
	}
	for _, sp in spikes do
		g:ellSeg("Mane", sp[1], sp[2], sp[3], sp[3] * 0.8, P.mane, "Carpet")
	end
	g:ell("Mane", V(0, 6.72, 0.0), V(0.36, 0.2, 0.5), P.mane, "Carpet")
	-- короткая грива по затылку
	g:ellSeg("Head", V(0, 6.68, 0.25), V(0, 6.1, 0.62), 0.16, 0.18, P.mane, "Carpet")
end

return Head
