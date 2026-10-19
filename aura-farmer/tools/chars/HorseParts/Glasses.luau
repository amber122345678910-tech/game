--!nocheck
-- Золотые очки-авиаторы на суставе Glasses: каплевидные линзы (одна деталь-эллипсоид на линзу,
-- верх «срезан» прямой брау-планкой), тонкая оправа по контуру, двойная перемычка, дужки до ушей.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")
local Head = require("./Head")

local Glasses = {}

-- Геометрия линзы (правая; u — наружу, v — вверх) относительно центра оправы.
local LENS_C = { 0.012, -0.022 } -- центр эллипса
local LENS_A, LENS_B = 0.238, 0.188 -- полуоси
local LENS_ROT = -17 -- наклон большой оси (наружу-вниз): каплевидный силуэт
local BAR_V = 0.15 -- высота брау-планки (верх линзы)

local function lensPt(t)
	-- точка эллипса по углу t (градусы) в координатах оправы (правая линза)
	local c, s = math.cos(rad(t)), math.sin(rad(t))
	local x, y = LENS_A * c, LENS_B * s
	local r = rad(LENS_ROT)
	return LENS_C[1] + x * math.cos(r) - y * math.sin(r), LENS_C[2] + x * math.sin(r) + y * math.cos(r)
end

function Glasses.build(g, opts)
	local lensColor = if opts.glasses == "yellow" then P.lensYellow else P.lensAmber
	local frameD = 0.024
	local cy, cz = 6.22, -0.8
	g.xf = Head.XF
	local frames = {}
	for _, s in { 1, -1 } do
		-- плоскость оправы: разворот наружу (обтекание лица) и лёгкий наклон
		local frame = CFrame.new(V(s * 0.3, cy, cz)) * CFrame.Angles(0, rad(-s * 14), 0) * CFrame.Angles(rad(-6), 0, 0)
		frames[s] = frame
		-- линза: один эллипсоид (без швов), верхняя «шапка» спрятана за планкой
		local lcf = frame * CFrame.new(s * LENS_C[1], LENS_C[2], 0) * CFrame.Angles(0, 0, rad(s * LENS_ROT))
		g:ell("Glasses", lcf, V(LENS_A * 2, LENS_B * 2, 0.014), lensColor, "Glass", nil, { transparency = 0.3, castShadow = false, name = "Lens" })
		-- оправа по нижней дуге (от планки до планки)
		local pts = {}
		local t0, t1 = 22, 162 -- углы, где эллипс пересекает планку (подобраны под BAR_V)
		for i = 0, 14 do
			local t = t1 + (360 + t0 - t1) * i / 14
			local u, v = lensPt(t)
			table.insert(pts, frame * V(s * u, math.min(v, BAR_V), -0.004))
		end
		g:caps("Glasses", pts, frameD, P.frame, "Metal")
	end
	local function fp(s, u, v)
		return frames[s] * V(s * u, v, -0.004)
	end
	-- брау-планка: от внешнего края одной линзы до другой (прямая, двойная толщина)
	g:caps("Glasses", { fp(1, 0.23, BAR_V - 0.004), fp(1, -0.2, BAR_V + 0.004), fp(-1, -0.2, BAR_V + 0.004), fp(-1, 0.23, BAR_V - 0.004) }, 0.034, P.frame, "Metal")
	-- нижний мост-дуга между линзами
	local a, b = fp(1, -0.205, 0.06), fp(-1, -0.205, 0.06)
	local m = a:Lerp(b, 0.5) + V(0, 0.045, -0.015)
	g:caps("Glasses", { a, m, b }, frameD * 0.9, P.frame, "Metal")
	-- носоупоры
	for _, s in { 1, -1 } do
		local p = fp(s, -0.17, -0.06) + V(-s * 0.03, 0, 0.04)
		g:ell("Glasses", p, V(0.04, 0.07, 0.03), P.frame, "Metal")
	end
	-- дужки: от внешнего верхнего угла назад к ушам
	for _, s in { 1, -1 } do
		local hinge = fp(s, 0.245, BAR_V - 0.01)
		local mid = V(s * 0.5, 6.3, -0.5)
		local back = V(s * 0.49, 6.31, -0.02)
		g:box("Glasses", Geo.axisX((hinge + mid) / 2, mid - hinge), V((mid - hinge).Magnitude + 0.02, 0.032, 0.02), P.frame, "Metal")
		g:cylSeg("Glasses", mid, back, 0.02, P.frame, "Metal")
		g:ball("Glasses", hinge, 0.036, P.frame, "Metal")
	end
	g.xf = nil
end

return Glasses
