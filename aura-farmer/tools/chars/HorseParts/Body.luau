--!nocheck
-- Торс: пиджак (широкие лацканы), рубашка в горох с огромным воротником, мех в вырезе,
-- кубинская цепь, ремень из крокодиловой кожи с пряжкой «A», таз в джинсах, эмиттеры.
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local V = roblox.Vector3.new
local rad = math.rad

local Geo = require("./Geo")
local P = require("./Palette")

local Body = {}

-- Плоскость с нормалью n (лицо смотрит по n), u ≈ вправо, v ≈ вверх.
local function planeFrame(origin, n)
	local z = -n.Unit
	local x = V(0, 1, 0):Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(origin, x, y, z)
end
Body.planeFrame = planeFrame

-- Пряжка «A» (Futura Bold): трапеции между прямыми; H — высота, W — ширина, e — сужение контура внутрь.
local function aPieces(H, W, e)
	e = e or 0
	local ia = 0.64 * H -- вершина внутреннего треугольника
	local ib = 0.2 * W -- внутренний край ноги у основания
	local cb, ct = 0.18 * H, 0.37 * H
	local dxo = e / math.cos(math.atan((W / 2) / H))
	local dxi = e / math.cos(math.atan(ib / ia))
	local function oL(y)
		return -W / 2 * (1 - y / H) + dxo
	end
	local function oR(y)
		return W / 2 * (1 - y / H) - dxo
	end
	local function iL(y)
		return -ib * (1 - y / ia) - dxi
	end
	local function iR(y)
		return ib * (1 - y / ia) + dxi
	end
	local Hn = H * (1 - 2 * dxo / W)
	local ian = ia * (1 + dxi / ib)
	return {
		{ e, cb + e, oL, iL },
		{ e, cb + e, iR, oR },
		{ cb + e, ct - e, oL, oR },
		{ ct - e, ian, oL, iL },
		{ ct - e, ian, iR, oR },
		{ ian, Hn, oL, oR },
	}
end

local function buildA(g, bone, frame, H, W, thick, color, mat, zoff, extra, e)
	for _, pc in aPieces(H, W, e) do
		local v0, v1, L, R = pc[1], pc[2], pc[3], pc[4]
		g:trap(bone, frame, v0, v1, L(v0), L(v1), R(v0), R(v1), thick, color, mat, zoff, extra)
	end
end
Body.buildA = buildA

local function emitter(part, name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rotation = roblox.NumberRange.new(0, 360)
	e.RotSpeed = roblox.NumberRange.new(-120, 120)
	e.SpreadAngle = roblox.Vector2.new(180, 180)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = true
	e.ZOffset = 0.6
	e.Enabled = false
	for k, v in props do
		e[k] = v
	end
	e.Parent = part
	return e
end
Body.emitter = emitter

local function seq(points)
	local kps = {}
	for _, p in points do
		table.insert(kps, roblox.NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return roblox.NumberSequence.new(kps)
end
Body.seq = seq

function Body.build(g, opts)
	local rig = g.rig

	-- ===== Пиджак: спина, бока, грудь (UpperTorso) =====
	g:ell("UpperTorso", V(0, 4.0, 0.12), V(2.3, 2.0, 1.18), P.suit, "SmoothPlastic")
	for _, s in { 1, -1 } do
		g:ell("UpperTorso", V(s * 0.5, 3.98, -0.02), V(1.36, 2.2, 1.2), P.suit, "SmoothPlastic")
		-- плечевые накладки (мост к рукаву)
		g:ell("UpperTorso", V(s * 1.0, 4.58, 0.03), V(1.0, 0.56, 1.08), P.suit, "SmoothPlastic", V(0, 0, s * -12))
		-- трапеция (скат к шее)
		g:ell("UpperTorso", V(s * 0.55, 4.72, 0.12), V(0.9, 0.5, 0.9), P.suit, "SmoothPlastic", V(0, 0, s * -18))
	end
	g:ell("UpperTorso", V(0, 3.3, 0.12), V(2.1, 1.2, 1.12), P.suit, "SmoothPlastic")

	-- ===== Рубашка (основа) и мех в вырезе =====
	g:ell("UpperTorso", V(0, 3.82, -0.18), V(1.4, 2.2, 1.0), P.shirt, "Fabric")
	g:ell("UpperTorso", V(0, 4.5, -0.42), V(0.66, 1.05, 0.62), P.chestFur, "Carpet")
	g:ell("UpperTorso", V(0, 4.78, -0.25), V(0.8, 0.5, 0.7), P.chestFur, "Carpet")
	for _, s in { 1, -1 } do
		-- края планки рубашки образуют V
		g:ell("UpperTorso", V(s * 0.36, 4.25, -0.5), V(0.46, 1.5, 0.36), P.shirt, "Fabric", V(0, s * 10, s * 16))
	end

	-- ===== Лацканы пиджака (плоские панели) =====
	for _, s in { 1, -1 } do
		local frame = planeFrame(V(s * 0.56, 4.1, -0.66), V(s * 0.28, 0.14, -1))
		local pts = { { -0.2, 0.75 }, { 0.1, 0.72 }, { 0.44, 0.52 }, { 0.32, 0.18 }, { -0.33, -0.72 } }
		for _, p in pts do
			p[1] *= s
		end
		g:poly("UpperTorso", frame, pts, 0.05, P.suitLight, "SmoothPlastic", 0)
		-- закатанная кромка лацкана
		local edge = { pts[3], pts[4], pts[5] }
		for i = 1, #edge - 1 do
			local a = frame * V(edge[i][1], edge[i][2], -0.01)
			local b = frame * V(edge[i + 1][1], edge[i + 1][2], -0.01)
			g:ellSeg("UpperTorso", a, b, 0.07, 0.07, P.suitLight, "SmoothPlastic")
		end
	end

	-- ===== Огромный воротник рубашки (поверх лацканов) =====
	for _, s in { 1, -1 } do
		local frame = planeFrame(V(s * 0.55, 4.45, -0.71), V(s * 0.3, 0.2, -1))
		local pts = { { -0.34, 0.5 }, { -0.05, 0.6 }, { 0.3, 0.25 }, { 0.54, -0.4 }, { 0.15, -0.15 }, { -0.3, 0.3 } }
		for _, p in pts do
			p[1] *= s
		end
		g:poly("UpperTorso", frame, pts, 0.04, P.shirt, "Fabric", 0)
		-- кромка воротника
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			g:ellSeg("UpperTorso", frame * V(a[1], a[2], 0), frame * V(b[1], b[2], 0), 0.045, 0.045, P.shirtDark, "Fabric")
		end
		-- горошек на воротнике
		local dots = { { 0.0, 0.42 }, { 0.12, 0.2 }, { -0.14, 0.32 }, { 0.3, 0.02 }, { 0.15, -0.02 }, { 0.42, -0.25 }, { -0.03, 0.12 }, { 0.26, 0.2 } }
		for _, d in dots do
			local p = frame * CFrame.new(s * d[1], d[2], -0.024) * CFrame.Angles(0, 0, rad(s * 25))
			g:ell("UpperTorso", p, V(0.055, 0.075, 0.012), P.dot, "SmoothPlastic")
		end
	end
	-- стойка воротника вокруг шеи сзади
	local back = {}
	for i = 0, 8 do
		local a = rad(-100 + i * 25)
		table.insert(back, V(0.5 * math.sin(a), 4.98, 0.1 + 0.52 * math.cos(a)))
	end
	for i = 1, #back - 1 do
		g:ellSeg("UpperTorso", back[i], back[i + 1], 0.12, 0.26, P.shirt, "Fabric")
	end

	-- горошек на видимой части рубашки
	for _, d in { { 0.18, 3.75 }, { -0.2, 3.62 }, { 0.05, 3.45 }, { -0.08, 3.85 }, { 0.25, 3.35 }, { -0.25, 3.3 }, { 0.12, 3.2 }, { -0.1, 3.18 }, { 0.3, 3.95 }, { -0.32, 4.02 } } do
		local x, y = d[1], d[2]
		-- точка на поверхности эллипсоида рубашки
		local cx, cy, cz, rx, ry, rz = 0, 3.82, -0.18, 0.7, 1.1, 0.5
		local t = 1 - ((x - cx) / rx) ^ 2 - ((y - cy) / ry) ^ 2
		if t > 0 then
			local z = cz - rz * math.sqrt(t)
			local n = V((x - cx) / rx ^ 2, (y - cy) / ry ^ 2, (z - cz) / rz ^ 2).Unit
			g:ell("UpperTorso", CFrame.lookAt(V(x, y, z), V(x, y, z) + n) * CFrame.Angles(0, 0, rad(30)), V(0.05, 0.07, 0.03), P.dot, "SmoothPlastic")
		end
	end

	-- ===== Кубинская цепь =====
	local N = 40
	local function chainPt(th)
		local c = math.cos(th)
		local front = math.max(0, c)
		local x = 0.6 * math.sin(th)
		local z = 0.12 - (0.6 + 0.18 * front) * c
		local y = 4.9 - 0.42 * front ^ 1.6
		return V(x, y, z)
	end
	for i = 0, N - 1 do
		local th = (i + 0.5) / N * 2 * math.pi
		local p = chainPt(th)
		local tng = (chainPt(th + 0.01) - chainPt(th - 0.01)).Unit
		local out = V(p.X, 0, p.Z - 0.12).Unit
		if math.cos(th) > 0.3 then
			out = (out + V(0, 0.45, -0.3)).Unit -- спереди цепь лежит на груди
		end
		local bin = tng:Cross(out).Unit
		local nrm = bin:Cross(tng).Unit
		local base = CFrame.fromMatrix(p, tng, bin, -nrm)
		g:rbox("UpperTorso", base * CFrame.Angles(0, 0, rad(38)), V(0.19, 0.085, 0.05), P.gold, "Foil")
		g:rbox("UpperTorso", base * CFrame.new(0.045, 0, 0.014) * CFrame.Angles(0, 0, rad(-38)), V(0.15, 0.065, 0.04), P.goldDeep, "Foil")
	end
	-- эмиттер блеска цепи
	local chainHost = g:box("UpperTorso", V(0, 4.55, -0.72), V(1.1, 0.35, 0.3), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "ChainSparkleHost" })
	chainHost.CanQuery = false
	emitter(chainHost, "ChainSparkles", {
		Rate = 14,
		Lifetime = roblox.NumberRange.new(0.25, 0.5),
		Speed = roblox.NumberRange.new(0),
		Size = seq({ { 0, 0 }, { 0.35, 0.28 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 244, 200), Color3.fromRGB(255, 205, 90)),
		Transparency = seq({ { 0, 0 }, { 1, 0.2 } }),
	})

	-- ===== Таз в джинсах (LowerTorso) =====
	g:ell("LowerTorso", V(0, 2.72, 0.04), V(2.0, 1.25, 1.24), P.jeans, "Fabric")
	g:ell("LowerTorso", V(0, 2.32, 0.0), V(0.9, 0.6, 0.9), P.jeans, "Fabric")
	-- ширинка: шов
	g:ellSeg("LowerTorso", V(0.05, 2.86, -0.6), V(0.03, 2.4, -0.52), 0.035, 0.02, P.jeansDark, "Fabric")

	-- пиджак ниже талии: спина, бока, полы
	g:ell("LowerTorso", V(0, 2.75, 0.16), V(2.18, 1.3, 1.16), P.suit, "SmoothPlastic")
	for _, s in { 1, -1 } do
		g:ell("LowerTorso", V(s * 0.86, 2.78, -0.12), V(0.72, 1.32, 1.0), P.suit, "SmoothPlastic", V(0, 0, s * 4))
	end

	-- ===== Ремень (крокодил) =====
	local belt = {}
	local NB = 28
	local by = 2.96
	for i = 0, NB do
		local a = i / NB * 2 * math.pi
		table.insert(belt, V(1.02 * math.sin(a), by, 0.04 - 0.655 * math.cos(a)))
	end
	for i = 1, NB do
		local a, b = belt[i], belt[i + 1]
		local mid = (a + b) / 2
		local d = b - a
		local cf = Geo.axisX(mid, d)
		g:box("LowerTorso", cf, V(d.Magnitude + 0.02, 0.24, 0.05), P.belt, "Leather")
	end
	-- чешуя крокодила спереди (2 ряда скруглённых плиток)
	for i = -6, 6 do
		for row = 0, 1 do
			local a = (i + (row * 0.5)) * 0.11
			local x = 1.04 * math.sin(a)
			local z = 0.04 - 0.675 * math.cos(a)
			local nrm = V(math.sin(a) / 1.04, 0, -math.cos(a) / 0.675).Unit
			local y = by + (if row == 0 then 0.055 else -0.055)
			local cf = CFrame.lookAt(V(x, y, z), V(x, y, z) + nrm)
			local shade = if (i + row) % 3 == 0 then P.croc else P.belt:Lerp(P.croc, 0.6)
			g:rbox("LowerTorso", cf, V(0.1, 0.085, 0.02), shade, "Leather")
		end
	end
	-- шлёвки
	for _, x in { -0.62, 0.62 } do
		local a = math.asin(x / 1.04)
		local z = 0.04 - 0.69 * math.cos(a)
		local nrm = V(math.sin(a), 0, -math.cos(a)).Unit
		g:box("LowerTorso", CFrame.lookAt(V(x, by, z), V(x, by, z) + nrm), V(0.07, 0.32, 0.03), P.jeansDark, "Fabric")
	end

	-- ===== Пряжка «A» =====
	local AH, AW = 0.62, 0.52
	local aFrame = CFrame.new(0, by - 0.24, -0.7)
	-- полированный кант (задняя, чуть бо́льшая пластина)
	buildA(g, "LowerTorso", aFrame, AH, AW, 0.06, P.buckleSide, "Foil", 0.0, nil, 0)
	-- сатиновое лицо (суженный контур, выступает вперёд)
	buildA(g, "LowerTorso", aFrame, AH, AW, 0.03, P.champagne, "Metal", -0.022, nil, 0.016)
	local apex = aFrame * V(0, AH, -0.04)
	local flare = g:ball("LowerTorso", apex, 0.16, Color3.new(1, 1, 1), "Neon", { transparency = 1, castShadow = false, name = "BuckleFlare" })
	flare.CanQuery = false
	local glintHost = g:box("LowerTorso", apex, V(0.06, 0.06, 0.06), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "BuckleGlintHost" })
	glintHost.CanQuery = false
	emitter(glintHost, "BuckleGlint", {
		Rate = 4,
		Lifetime = roblox.NumberRange.new(0.3, 0.45),
		Speed = roblox.NumberRange.new(0),
		Size = seq({ { 0, 0 }, { 0.3, 0.9 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 250, 225)),
		RotSpeed = roblox.NumberRange.new(-40, 40),
		ZOffset = 1.5,
	})

	-- ===== Аура (трон) =====
	local auraHost = g:box("UpperTorso", V(0, 3.6, 0), V(3.4, 5.6, 2.2), Color3.new(1, 1, 1), "SmoothPlastic", nil, { transparency = 1, castShadow = false, name = "AuraHost" })
	auraHost.CanQuery = false
	emitter(auraHost, "AuraSparkles", {
		Enabled = opts.sparkles == true,
		Rate = 26,
		Lifetime = roblox.NumberRange.new(0.8, 1.6),
		Speed = roblox.NumberRange.new(0.2, 0.6),
		Acceleration = V(0, 0.6, 0),
		Drag = 1,
		Size = seq({ { 0, 0 }, { 0.25, 0.22 }, { 1, 0 } }),
		Color = roblox.ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 190, 70)),
		Transparency = seq({ { 0, 0.1 }, { 1, 0.6 } }),
		LockedToPart = false,
	})
end

return Body
