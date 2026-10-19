--!nocheck
-- Голова коня: череп, морда, ноздри, глаза, уши, хохолок, брови, рот (зубы, дёсны, губы, язык), шея.
-- Морда проектируется «ровно» (смотрит в -Z) и затем наклоняется носом вниз на PITCH вокруг точки Q.
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local V = Vector3.new
local rad = math.rad

local P = require("./Palette")

local Head = {}

Head.PITCH = -16
Head.Q = V(0, 6.3, -0.1)
Head.LIFT = V(0, 0.06, 0)
Head.XF = CFrame.new(Head.Q + Head.LIFT) * CFrame.Angles(rad(Head.PITCH), 0, 0) * CFrame.new(-Head.Q)

-- Опоры доп. суставов в «ровной» системе (в HorseSkeleton.EXTRA записаны эти же точки после XF).
Head.PIVOTS = {
	Jaw = V(0, 5.74, -0.22),
	UpperLip = V(0, 5.92, -1.0),
	Glasses = V(0, 6.22, -0.78),
	RightBrow = V(0.3, 6.46, -0.68),
	LeftBrow = V(-0.3, 6.46, -0.68),
	RightEar = V(0.36, 6.62, 0.1),
	LeftEar = V(-0.36, 6.62, 0.1),
	Mane = V(0, 6.7, 0.0),
}

-- Зубная дуга (вид сверху): эллипс с центром z0, полуоси ax (X) и az (Z); phi в градусах (0 — центр спереди).
local function arch(ax, az, z0, phi)
	local p = rad(phi)
	local x = ax * math.sin(p)
	local z = z0 - az * math.cos(p)
	local n = V(math.sin(p) / ax, 0, -math.cos(p) / az).Unit -- наружная нормаль
	return x, z, n
end
Head.arch = arch

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
local BITE_Y = 5.74
local function biteY(phi)
	local k = math.abs(phi) / 100
	return BITE_Y + 0.08 * k * k
end
Head.biteY = biteY

local Z0 = -1.05 -- центр зубной дуги

function Head.build(g, opts)
	-- ===== Шея (кость Head, вращается вокруг Neck y=4.95); без наклона морды =====
	g.xf = nil
	g:ellSeg("Head", V(0, 4.7, 0.12), V(0, 5.95, 0.02), 0.88, 0.94, P.fur, "Carpet", V(0, 0, -1))
	g:ellSeg("Head", V(0, 4.85, -0.12), V(0, 5.5, -0.32), 0.62, 0.52, P.fur, "Carpet", V(0, 0, -1)) -- горло
	g:ellSeg("Head", V(0, 5.0, 0.3), V(0, 6.3, 0.24), 0.62, 0.52, P.fur, "Carpet", V(0, 0, -1)) -- загривок

	g.xf = Head.XF
	-- ===== Череп =====
	g:ell("Head", V(0, 6.34, -0.02), V(0.98, 0.92, 1.1), P.fur, "Carpet")
	g:ell("Head", V(0, 6.34, -0.42), V(0.84, 0.64, 0.66), P.furWarm, "Carpet") -- лоб
	-- переносица (длинная, светлее)
	g:ellSeg("Head", V(0, 6.3, -0.42), V(0, 6.1, -1.62), 0.56, 0.42, P.furWarm, "Carpet")
	for _, s in { 1, -1 } do
		-- боковые плоскости морды (седоватые), низ — по линии верхней губы
		g:ellSeg("Head", V(s * 0.17, 6.16, -0.4), V(s * 0.15, 6.08, -1.5), 0.42, 0.46, P.furGrey, "Carpet", V(s * 0.25, 1, 0))
		-- скула под глазом
		g:ell("Head", V(s * 0.29, 6.04, -0.48), V(0.4, 0.46, 0.66), P.furGrey, "Carpet", V(8, 0, 0))
		-- ганаши (большие щёки сзади-снизу)
		g:ell("Head", V(s * 0.25, 5.7, -0.26), V(0.52, 0.8, 0.9), P.fur, "Carpet", V(-10, 0, 0))
		-- переход от щеки к уголку рта
		g:ellSeg("Head", V(s * 0.27, 5.92, -0.55), V(s * 0.3, 5.9, -0.92), 0.26, 0.24, P.furGrey, "Carpet")
	end
	g:ell("Head", V(0, 5.58, -0.12), V(0.66, 0.6, 0.8), P.fur, "Carpet") -- межчелюстное пространство

	-- ===== Морда и нос =====
	g:ell("Head", V(0, 6.05, -1.43), V(0.76, 0.44, 0.62), P.muzzle, "Carpet")
	g:ell("Head", V(0, 6.07, -1.55), V(0.68, 0.42, 0.4), P.nose, "Carpet")
	for _, s in { 1, -1 } do
		-- ноздри: тёмные «запятые» на переднем торце, верх сходится к центру
		local c = V(s * 0.155, 6.09, -1.735)
		g:ell("Head", CFrame.new(c) * CFrame.Angles(rad(-12), rad(s * 18), rad(s * -22)), V(0.12, 0.2, 0.07), P.nostril, "SmoothPlastic")
	end

	-- ===== Рот: верхняя часть (Head) =====
	g:ell("Head", V(0, 5.79, -1.02), V(0.56, 0.24, 0.86), P.mouthIn, "SmoothPlastic") -- полость
	-- верхние дёсны
	local gum = {}
	for phi = -90, 90, 15 do
		local x, z = arch(0.305, 0.485, Z0, phi)
		table.insert(gum, V(x, biteY(phi) + 0.14, z))
	end
	g:caps("Head", gum, 0.08, P.gum, "SmoothPlastic")
	-- верхние зубы (крупные, «человеческие»)
	local upper = {
		{ 6.2, 0.12, 0.16 },
		{ 18.8, 0.106, 0.146 },
		{ 31.5, 0.098, 0.136 },
		{ 44.5, 0.092, 0.122 },
		{ 58, 0.088, 0.108 },
		{ 72, 0.082, 0.096 },
		{ 86, 0.075, 0.086 },
	}
	for _, t in upper do
		for _, s in { 1, -1 } do
			local phi = s * t[1]
			local x, z, n = arch(0.3, 0.48, Z0, phi)
			local h = t[3]
			g:rbox("Head", archCF(V(x, biteY(phi) + h / 2 - 0.003, z), n, -3), V(t[2], h, 0.075), P.tooth, "SmoothPlastic")
		end
	end

	-- ===== Нижняя челюсть (Jaw) =====
	g:ellSeg("Jaw", V(0, 5.42, -0.3), V(0, 5.42, -1.36), 0.62, 0.4, P.fur, "Carpet")
	g:ell("Jaw", V(0, 5.43, -1.22), V(0.6, 0.42, 0.5), P.muzzle, "Carpet") -- подбородок
	g:ell("Jaw", V(0, 5.33, -1.0), V(0.5, 0.36, 0.6), P.muzzle, "Carpet")
	for _, s in { 1, -1 } do
		g:ellSeg("Jaw", V(s * 0.2, 5.5, -0.5), V(s * 0.2, 5.5, -1.2), 0.24, 0.26, P.furGrey, "Carpet")
	end
	-- полость и язык
	g:ell("Jaw", V(0, 5.6, -1.0), V(0.5, 0.16, 0.82), P.mouthIn, "SmoothPlastic")
	g:ell("Jaw", V(0, 5.64, -1.1), V(0.38, 0.12, 0.62), P.tongue, "SmoothPlastic")
	-- нижние дёсны
	local lgum = {}
	for phi = -86, 86, 21.5 do
		local x, z = arch(0.282, 0.452, Z0, phi)
		table.insert(lgum, V(x, biteY(phi) - 0.125, z))
	end
	g:caps("Jaw", lgum, 0.075, P.gum, "SmoothPlastic")
	-- нижние зубы
	local lower = {
		{ 5.6, 0.1, 0.12 },
		{ 16.8, 0.094, 0.115 },
		{ 28.3, 0.09, 0.11 },
		{ 40.5, 0.086, 0.102 },
		{ 53.5, 0.082, 0.094 },
		{ 67.5, 0.077, 0.086 },
		{ 82, 0.07, 0.078 },
	}
	for _, t in lower do
		for _, s in { 1, -1 } do
			local phi = s * t[1]
			local x, z, n = arch(0.275, 0.445, Z0, phi)
			local h = t[3]
			g:rbox("Jaw", archCF(V(x, biteY(phi) - 0.006 - h / 2, z), n, 3), V(t[2], h, 0.07), P.tooth, "SmoothPlastic")
		end
	end
	-- нижняя губа (толстая, персиковая)
	local llip = {}
	for phi = -100, 100, 12.5 do
		local x, z = arch(0.33, 0.51, Z0, phi)
		local k = math.abs(phi) / 100
		table.insert(llip, V(x, biteY(phi) - 0.15 + 0.07 * k * k, z))
	end
	g:caps("Jaw", llip, function(i)
		local k = math.abs(i - (#llip + 1) / 2) / ((#llip - 1) / 2)
		return 0.11 - 0.03 * k
	end, P.lip, "SmoothPlastic")

	-- ===== Верхняя губа (UpperLip) =====
	local ulip = {}
	for phi = -100, 100, 12.5 do
		local x, z = arch(0.34, 0.53, Z0, phi)
		local k = math.abs(phi) / 100
		table.insert(ulip, V(x, biteY(phi) + 0.165 - 0.075 * k * k, z))
	end
	g:caps("UpperLip", ulip, function(i)
		local k = math.abs(i - (#ulip + 1) / 2) / ((#ulip - 1) / 2)
		return 0.1 - 0.025 * k
	end, P.lip, "SmoothPlastic")
	-- тёмная шерсть над губой (переход к носу)
	local uf = {}
	for phi = -96, 96, 16 do
		local x, z = arch(0.33, 0.5, Z0, phi)
		local k = math.abs(phi) / 100
		table.insert(uf, V(x, biteY(phi) + 0.24 - 0.06 * k * k, z + 0.015))
	end
	g:caps("UpperLip", uf, 0.12, P.muzzle, "Carpet")

	-- ===== Глаза =====
	for _, s in { 1, -1 } do
		local side = if s == 1 then "Right" else "Left"
		local c = V(s * 0.335, 6.21, -0.6)
		local look = V(s * 0.45, 0.0, -1).Unit
		local cf = CFrame.lookAt(c, c + look)
		g:ell("Head", cf, V(0.2, 0.16, 0.14), P.eyeWhite, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, -0.01, -0.062), V(0.11, 0.11, 0.03), P.iris, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0, -0.01, -0.072), V(0.055, 0.07, 0.016), P.pupil, "SmoothPlastic")
		g:ell("Head", cf * CFrame.new(0.018, 0.012, -0.078), V(0.022, 0.022, 0.008), P.tooth, "SmoothPlastic") -- блик
		-- веки: верхнее прикрыто наполовину (расслабленный «крутой» взгляд)
		g:ell("Head", cf * CFrame.new(0, 0.04, 0.0) * CFrame.Angles(rad(-6), 0, 0), V(0.23, 0.1, 0.17), P.fur, "Carpet")
		g:ell("Head", cf * CFrame.new(0, -0.066, 0.005), V(0.22, 0.07, 0.15), P.furGrey, "Carpet")
		-- надбровная дуга
		g:ellSeg("Head", V(s * 0.14, 6.37, -0.66), V(s * 0.46, 6.34, -0.48), 0.13, 0.12, P.furWarm, "Carpet")
		-- брови (на суставах бровей)
		g:ellSeg(side .. "Brow", V(s * 0.12, 6.48, -0.69), V(s * 0.45, 6.47, -0.55), 0.075, 0.06, P.furDark, "Carpet", V(0, 1, 0))
	end

	-- ===== Уши =====
	for _, s in { 1, -1 } do
		local ear = if s == 1 then "RightEar" else "LeftEar"
		local base = V(s * 0.36, 6.58, 0.1)
		local tip = V(s * 0.5, 7.24, 0.04)
		g:ellSeg(ear, base + V(0, -0.04, 0), tip, 0.28, 0.2, P.fur, "Carpet", V(0, 0, -1))
		g:ellSeg(ear, base:Lerp(tip, 0.45), tip + V(s * 0.01, 0.05, -0.01), 0.16, 0.11, P.fur, "Carpet", V(0, 0, -1))
		-- внутренняя сторона (смотрит вперёд)
		g:ellSeg(ear, base + V(0, 0.08, -0.07), base:Lerp(tip, 0.86) + V(0, 0, -0.045), 0.15, 0.06, P.earIn, "Carpet", V(0, 0, -1))
	end

	-- ===== Хохолок (чёрные «иглы» между ушами) =====
	local spikes = {
		{ V(0, 6.7, 0.1), V(0.02, 7.16, -0.2), 0.2 },
		{ V(0.08, 6.72, 0.0), V(0.15, 7.08, -0.3), 0.17 },
		{ V(-0.08, 6.72, 0.0), V(-0.14, 7.09, -0.28), 0.17 },
		{ V(0, 6.72, -0.12), V(0.0, 6.98, -0.45), 0.17 },
		{ V(0.13, 6.68, 0.12), V(0.22, 7.0, -0.04), 0.14 },
		{ V(-0.13, 6.68, 0.12), V(-0.23, 6.99, -0.05), 0.14 },
		{ V(0, 6.66, 0.25), V(0.03, 7.04, 0.12), 0.16 },
	}
	for _, sp in spikes do
		g:ellSeg("Mane", sp[1], sp[2], sp[3], sp[3] * 0.8, P.mane, "Carpet")
	end
	g:ell("Mane", V(0, 6.72, 0.0), V(0.34, 0.18, 0.5), P.mane, "Carpet")
	-- короткая грива по затылку
	g:ellSeg("Head", V(0, 6.68, 0.25), V(0, 6.1, 0.6), 0.16, 0.18, P.mane, "Carpet")
	g.xf = nil
end

return Head
