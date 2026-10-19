--!nocheck
-- Золотые очки-авиаторы: каплевидные линзы (точный многоугольник из клиньев), тонкая оправа,
-- двойная перемычка, дужки до ушей. Всё на суставе Glasses.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")

local Glasses = {}

-- Каплевидная линза (правая, u наружу), центр в (0,0).
local LENS = {
	{ -0.205, 0.14 },
	{ -0.12, 0.163 },
	{ -0.02, 0.172 },
	{ 0.09, 0.168 },
	{ 0.175, 0.15 },
	{ 0.222, 0.105 },
	{ 0.238, 0.035 },
	{ 0.228, -0.04 },
	{ 0.196, -0.105 },
	{ 0.145, -0.158 },
	{ 0.08, -0.19 },
	{ 0.012, -0.2 },
	{ -0.05, -0.188 },
	{ -0.1, -0.155 },
	{ -0.15, -0.095 },
	{ -0.188, -0.02 },
	{ -0.208, 0.07 },
}

function Glasses.build(g, opts)
	local lensColor = if opts.glasses == "yellow" then P.lensYellow else P.lensAmber
	local frameD = 0.024
	local cy, cz = 6.2, -0.8
	for _, s in { 1, -1 } do
		-- плоскость линзы: центр, разворот наружу (обтекание лица) и лёгкий наклон
		local center = V(s * 0.3, cy, cz)
		local frame = CFrame.new(center) * CFrame.Angles(0, rad(-s * 14), 0) * CFrame.Angles(rad(-6), 0, 0)
		local pts = {}
		for _, p in LENS do
			table.insert(pts, { s * p[1], p[2] })
		end
		g:poly("Glasses", frame, pts, 0.012, lensColor, "Glass", 0, { transparency = 0.32, castShadow = false })
		g:outline("Glasses", frame, pts, frameD, P.frame, "Metal", 0.0)
		-- лёгкий блик на линзе (тонкая белая дуга сверху)
		-- (в Roblox стекло и так даёт отражения; оставляем чистым)
	end
	-- двойная перемычка: верхняя прямая планка и нижний мост-дуга
	local function lensPt(s, u, v)
		local frame = CFrame.new(V(s * 0.3, cy, cz)) * CFrame.Angles(0, rad(-s * 14), 0) * CFrame.Angles(rad(-6), 0, 0)
		return frame * V(s * u, v, 0)
	end
	local topR, topL = lensPt(1, -0.13, 0.172), lensPt(-1, -0.13, 0.172)
	g:cylSeg("Glasses", topR, topL, frameD, P.frame, "Metal")
	-- верхняя планка продолжается к внешним краям (брау-бар)
	g:cylSeg("Glasses", lensPt(1, -0.13, 0.172), lensPt(1, 0.17, 0.162), frameD * 0.9, P.frame, "Metal")
	g:cylSeg("Glasses", lensPt(-1, -0.13, 0.172), lensPt(-1, 0.17, 0.162), frameD * 0.9, P.frame, "Metal")
	-- нижний мост: дуга из 3 сегментов
	local a = lensPt(1, -0.205, 0.08)
	local b = lensPt(-1, -0.205, 0.08)
	local m1 = a:Lerp(b, 0.3) + V(0, 0.035, -0.012)
	local m2 = a:Lerp(b, 0.7) + V(0, 0.035, -0.012)
	g:cylSeg("Glasses", a, m1, frameD * 0.9, P.frame, "Metal")
	g:cylSeg("Glasses", m1, m2, frameD * 0.9, P.frame, "Metal")
	g:cylSeg("Glasses", m2, b, frameD * 0.9, P.frame, "Metal")
	-- носоупоры
	for _, s in { 1, -1 } do
		local p = lensPt(s, -0.17, -0.05) + V(-s * 0.03, 0, 0.04)
		g:ell("Glasses", p, V(0.04, 0.07, 0.03), P.frame, "Metal")
		g:cylSeg("Glasses", lensPt(s, -0.19, 0.0), p, 0.012, P.frame, "Metal")
	end
	-- дужки: от внешнего верхнего угла назад к ушам
	for _, s in { 1, -1 } do
		local hinge = lensPt(s, 0.232, 0.08)
		local mid = V(s * 0.5, 6.29, -0.5)
		local back = V(s * 0.49, 6.3, -0.02)
		g:box("Glasses", Geo.axisX((hinge + mid) / 2, mid - hinge), V((mid - hinge).Magnitude + 0.02, 0.03, 0.02), P.frame, "Metal")
		g:cylSeg("Glasses", mid, back, 0.02, P.frame, "Metal")
		g:ball("Glasses", hinge, 0.034, P.frame, "Metal")
	end
end

return Glasses
