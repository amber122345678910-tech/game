--!nocheck
-- Небо (docs/STYLE.md §6.2–6.5): угловатый грозовой потолок с наковальней над каждым островом
-- (Map.Clouds.Clouds_1..5, из него бьют молнии), стена Ока Бури из наклонённых «башен»,
-- мягкое светлое море облаков с плоским дном далеко внизу и далёкие парящие скалы для глубины.
-- Опасное наверху — острое и тёмное, безопасное внизу — мягкое и светлое. Шаров в грозе нет.
local roblox = require("@lune/roblox")
local B = require("../lib/builder")
local P = require("../lib/props")
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local rgb = B.rgb

local Sky = {}

local W = B.W
local TAU = math.pi * 2

-- Тучи по зонам (STYLE §3.2): ядро (низ), брюхо, кромка, бок башни, верх (наковальня)
local STORM = {
	{ core = rgb(52, 52, 77), belly = rgb(70, 76, 100), rim = rgb(106, 112, 148), side = rgb(85, 90, 121), top = rgb(128, 132, 166) },
	{ core = rgb(63, 52, 69), belly = rgb(86, 70, 90), rim = rgb(115, 109, 142), side = rgb(96, 86, 114), top = rgb(136, 129, 162) },
	{ core = rgb(52, 65, 74), belly = rgb(70, 90, 96), rim = rgb(106, 120, 146), side = rgb(85, 100, 118), top = rgb(128, 138, 164) },
	{ core = rgb(64, 59, 86), belly = rgb(80, 80, 112), rim = rgb(112, 114, 154), side = rgb(92, 93, 129), top = rgb(133, 134, 171) },
	{ core = rgb(39, 32, 62), belly = rgb(60, 44, 80), rim = rgb(100, 94, 137), side = rgb(78, 68, 107), top = rgb(124, 118, 157) },
}
-- Море облаков: плита, барабан, купол, блик купола
local SEA = { slab = rgb(123, 122, 172), drum = rgb(136, 138, 189), dome = rgb(150, 156, 206), glint = rgb(172, 171, 228) }

local function cloudOpts(name)
	return B.deco({ Shadow = false, Name = name or "Cloud" })
end

-- Грозовой потолок над островом (рецепт R-STORM-CEIL, ≤ 60 деталей)
local function ceiling(ctx, i, folder)
	local Config, Zones = ctx.Config, ctx.Zones
	local z = Config.Zones[i]
	local g = Zones.Geo[i]
	local col = STORM[i]
	local rng = B.rng(7000 + i * 31)
	local H = z.GroundY + Config.CloudHeight
	local Rz = z.Radius * 1.12
	local m = B.model(folder, "Clouds_" .. i)
	local center = B.marker(m, "Center", CFrame.new(g.Center.X, H, g.Center.Z), Vector3.new(4, 4, 4))
	m.PrimaryPart = center
	m:SetAttribute("Height", H)
	local C = Vector3.new(g.Center.X, H, g.Center.Z)
	local a0 = rng:range(0, TAU)
	local off0 = Vector3.new(math.cos(a0), 0, math.sin(a0))
	local away = -g.ToHub -- башня и наковальня смещены от хаба: из хаба виден силуэт

	-- светлеющая кромка: клубы и кромка светлее ядра (снизу видны ступени тона)
	local rimCol = B.tint(col.rim, 0.35)
	-- плиты-ступени снизу вверх: ядро → брюхо → кромка → верх (разные развороты, рваный край)
	B.hexPlate(m, C + off0 * Rz * 0.1 + Vector3.new(0, 3, 0), Rz * 0.42, 6, rng:range(0, 1), 0, nil, col.core, cloudOpts())
	B.hexPlate(m, C - off0 * rng:range(8, 12) + Vector3.new(0, 3 + 3, 0), Rz * 0.72, 6, rng:range(0, 1), 1, rng, col.belly, cloudOpts())
	B.hexPlate(m, C + Vector3.new(0, 7 + 4, 0), Rz * 1.0, 8, rng:range(0, 1), 1, rng, col.rim, cloudOpts())
	B.hexPlate(m, C + away * Rz * 0.08 + Vector3.new(0, 13 + 3, 0), Rz * 0.82, 6, rng:range(0, 1), 0.6, rng, col.top, cloudOpts())

	-- клубы по кромке: 3 больших, 6 средних, 7 малых; поддеты под край плит и свисают наружу-вниз
	-- (рваный свисающий край), соседние перекрываются; порядок перемешан
	local kinds = {}
	for _ = 1, 3 do
		table.insert(kinds, { rng:range(28, 34), rng:range(11, 14), rng:range(16, 20) })
	end
	for _ = 1, 6 do
		table.insert(kinds, { rng:range(20, 26), rng:range(8, 10), rng:range(12, 16) })
	end
	for _ = 1, 7 do
		table.insert(kinds, { rng:range(14, 18), rng:range(6, 8), rng:range(10, 12) })
	end
	rng:shuffle(kinds)
	local n = #kinds
	for k, sz in kinds do
		local a = (k - 1 + rng:range(-0.25, 0.25)) / n * TAU
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = Rz * rng:range(0.74, 0.9)
		local topY = rng:range(6, 10) -- верх клуба внутри брюха и кромки
		local pos = C + out * r + Vector3.new(0, topY - sz[2] / 2, 0)
		-- наклон «наружу-вниз»: внешний край свисает
		local cf = B.facing(pos, out) * CFrame.Angles(-math.rad(rng:range(15, 30)), 0, math.rad(rng:range(-10, 10)))
		local c = if k % 2 == 0 then rimCol else B.tint(col.belly, 0.2)
		B.block(m, cf, Vector3.new(sz[1], sz[2], sz[3]), B.vary(c, rng, 0.015), cloudOpts())
	end

	-- свесы: гранёные «капли» всех размеров, утоплены на 60% в низ ядра и брюха
	for k = 1, rng:int(4, 6) do
		local S = 8 + (k - 1) * 1.3 + rng:range(0, 0.8)
		local p = C + rng:disc(Rz * 0.5) + Vector3.new(0, 3 + S * 0.25, 0)
		B.gem(m, p, S, rng:range(0, TAU), col.core, cloudOpts())
	end

	-- клубы сверху: неровный горб над кромкой (силуэт сбоку и из хаба не плоский)
	for k = 1, 6 do
		local a = a0 + k / 6 * TAU + rng:range(-0.3, 0.3)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = Rz * rng:range(0.4, 0.68)
		local sz = Vector3.new(rng:range(22, 32), rng:range(8, 14), rng:range(18, 26))
		local pos = C + out * r + Vector3.new(0, 19 + sz.Y * 0.3, 0)
		B.tiltBox(m, pos, sz, math.rad(rng:range(-14, 14)), rng:range(0, TAU), math.rad(rng:range(-14, 14)), B.vary(if k % 2 == 0 then B.tint(col.top, 0.3) else col.top, rng, 0.015), cloudOpts())
	end

	-- башня кучево-дождевого облака и наковальня, вытянутая по ветру
	local tb = C + away * Rz * 0.22 + Vector3.new(0, 19, 0)
	local ty = rng:range(0, 1)
	B.hexPrism(m, tb + Vector3.new(0, 10, 0), 22, 20, ty, col.side, cloudOpts())
	B.hexPrism(m, tb + W * 3 + Vector3.new(0, 28, 0), 16, 16, ty + math.rad(20), B.tint(col.side, 0.25), cloudOpts())
	local anvil = tb + W * 12 + Vector3.new(0, 38.5, 0)
	B.hexPlate(m, anvil, 45, 5, rng:range(0, 1), 0.8, rng, col.top, cloudOpts())
	local perp = Vector3.new(-W.Z, 0, W.X)
	for k = -1, 1 do
		local p = anvil + W * (38 + rng:range(-3, 4)) + perp * k * 16 + Vector3.new(0, -1.2, 0)
		local cf = B.facing(p, W) * CFrame.Angles(math.rad(-10), 0, 0)
		B.block(m, cf, Vector3.new(24, 4, 14), B.vary(col.top, rng, 0.015), cloudOpts())
	end

	-- Око Бури: «стена глаза» — кольцо из 18 наклонённых внутрь «башен»-занавесей, соседние перекрываются
	-- (два радиуса вперемешку дают глубину), 3 высокие, 6 средних, 9 низких; в сторону хаба проём ±28°;
	-- верх уходит под кромку потолка, низы рваные, у части — гранёная «капля»
	if i == 5 then
		local wall = B.model(m, "Wall")
		local heights = {}
		for _ = 1, 3 do
			table.insert(heights, "tall")
		end
		for _ = 1, 6 do
			table.insert(heights, "mid")
		end
		for _ = 1, 9 do
			table.insert(heights, "low")
		end
		rng:shuffle(heights)
		local hubA = math.atan2(g.ToHub.Z, g.ToHub.X)
		local gap = math.rad(28)
		local arc = TAU - gap * 2
		for k, kind in heights do
			local a = hubA + gap + (k - 0.5 + rng:range(-0.2, 0.2)) / #heights * arc
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local h = if kind == "tall" then rng:range(78, 88) elseif kind == "mid" then rng:range(64, 74) else rng:range(50, 60)
			local r = z.Radius + (if k % 2 == 0 then rng:range(12, 15) else rng:range(19, 23))
			local w = (arc / #heights) * r * rng:range(1.25, 1.45)
			local d = rng:range(14, 20)
			local top = H + rng:range(6, 10)
			local pos = g.Center + out * r
			pos = Vector3.new(pos.X, top - h / 2, pos.Z)
			local tilt = math.rad(rng:range(8, 15))
			-- наклон внутрь: верх к центру острова
			local cf = B.facing(pos, -out) * CFrame.Angles(-tilt, 0, math.rad(rng:range(-4, 4)))
			local c = B.vary(if k % 3 == 0 then col.belly else col.side, rng, 0.02)
			B.block(wall, cf, Vector3.new(w, h, d), c, cloudOpts())
			if kind ~= "low" then
				B.hexPlate(wall, (cf * CFrame.new(0, h / 2 + 1.5, 0)).Position, rng:range(12, 16), 3, rng:range(0, 1), 1, rng, rimCol, cloudOpts())
			else
				B.block(wall, cf * CFrame.new(0, h / 2 + 1.2, 0) * CFrame.Angles(0, rng:range(-0.2, 0.2), math.rad(rng:range(-8, 8))), Vector3.new(w + 6, 3, d + 4), rimCol, cloudOpts())
			end
			if k % 2 == 1 then
				B.gem(wall, (cf * CFrame.new(rng:range(-w * 0.25, w * 0.25), -h / 2, 0)).Position, rng:range(8, 12), rng:range(0, TAU), B.shade(c, 0.4), cloudOpts())
			end
		end
	end
	return m
end

-- Море облаков (рецепт R-SEA): ступени плоских светлых полей с угловатым краем и купола с плоским дном
local function sea(ctx, folder, rng)
	local Config, Zones = ctx.Config, ctx.Zones
	local m = B.model(folder, "Sea")
	local seaTop = Config.VoidY - 95
	-- глубокий слой под всем морем: в просветах между полями не видно пустоты
	B.hexPlate(m, Vector3.new(0, seaTop - 34, 0), 760, 10, 0.2, 0, nil, B.shade(SEA.slab, 0.12), cloudOpts("CloudField"))
	-- поля: 8 больших плит и 4 «барабанных» поверх, не по кругу
	for k = 1, 8 do
		local a = (k + rng:range(-0.35, 0.35)) / 8 * TAU
		local d = rng:range(180, 470)
		local p = Vector3.new(math.cos(a) * d, seaTop - 12 - 5, math.sin(a) * d)
		B.hexPlate(m, p + Vector3.new(0, rng:range(-1.5, 1.5), 0), rng:range(130, 200), 12, rng:range(0, 1), 1, rng, B.vary(SEA.slab, rng, 0.015), cloudOpts("CloudField"))
	end
	for k = 1, 4 do
		local a = (k + rng:range(-0.4, 0.4)) / 4 * TAU + 0.5
		local d = rng:range(240, 420)
		local p = Vector3.new(math.cos(a) * d, seaTop - 4 - 5, math.sin(a) * d)
		B.hexPlate(m, p, rng:range(80, 120), 10, rng:range(0, 1), 1, rng, SEA.drum, cloudOpts("CloudField"))
	end
	-- купола: 22 группы. Плотнее в кольце островов (250–600 от хаба), реже дальше; не под самими островами
	local function tooClose(p, r)
		if B.flat(p).Magnitude < 120 + r then
			return true
		end
		for i, g in Zones.Geo do
			if (B.flat(p) - B.flat(g.Center)).Magnitude < Config.Zones[i].Radius * 0.75 + r * 0.5 then
				return true
			end
		end
		return false
	end
	local groups = {}
	local tries = 0
	while #groups < 24 and tries < 900 do
		tries += 1
		local ring = if #groups < 17 then rng:range(250, 600) else rng:range(600, 900)
		local a = rng:range(0, TAU)
		local p = Vector3.new(math.cos(a) * ring, 0, math.sin(a) * ring)
		local D = rng:range(60, 90)
		local ok = not tooClose(p, D)
		for _, q in groups do
			if (q[1] - p).Magnitude < (q[2] + D) * 0.75 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(groups, { p, D })
		end
	end
	-- 5 самых больших получают купол-блик
	local order = {}
	for k in groups do
		table.insert(order, k)
	end
	table.sort(order, function(a, b)
		return groups[a][2] > groups[b][2]
	end)
	local glint = {}
	for k = 1, math.min(5, #order) do
		glint[order[k]] = true
	end
	local base = seaTop - 12.5 -- плоские донья куполов лежат на полях
	for k, grp in groups do
		local p, D = grp[1], grp[2]
		local y = base + rng:range(-1.5, 0.5)
		B.lobe(m, Vector3.new(p.X, y, p.Z), D, D / 2 + 0.2, SEA.drum, if glint[k] then SEA.glint else SEA.dome, cloudOpts())
		local a = rng:range(0, TAU)
		local D2 = rng:range(35, 50)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p2 = p + dir * (D / 2 + D2 / 2) * rng:range(0.5, 0.7)
		B.lobe(m, Vector3.new(p2.X, y + 0.1, p2.Z), D2, D2 / 2 + 0.2, B.shade(SEA.drum, 0.15), SEA.dome, cloudOpts())
		if k % 2 == 0 then
			local D3 = rng:range(18, 26)
			local a3 = a + rng:sign() * rng:range(1.6, 2.4)
			local p3 = p + Vector3.new(math.cos(a3), 0, math.sin(a3)) * (D / 2 + D3 / 2) * rng:range(0.55, 0.75)
			B.lobe(m, Vector3.new(p3.X, y + 0.2, p3.Z), D3, D3 / 2 + 0.2, B.shade(SEA.drum, 0.25), B.tint(SEA.dome, 0.15), cloudOpts())
		end
	end
	return m
end

-- Далёкая парящая скала (рецепт R-FAR-ROCK, ≤ 9 деталей): плита земли, два гранёных камня снизу, иногда тополёк
local function farRock(parent, center, r, rng, pal)
	local m = B.model(parent, "FarRock")
	local yaw = rng:range(0, TAU)
	B.hexPlate(m, center - Vector3.new(0, 1, 0), r, 2, yaw, 1, rng, B.vary(pal.top, rng, 0.03), cloudOpts("FarRock"))
	B.gem(m, center - Vector3.new(0, 2 + r * 0.32, 0), r * 0.9, yaw + 0.4, B.shade(pal.rock, 1), cloudOpts("FarRock"))
	B.gem(m, center + Vector3.new(rng:range(-0.2, 0.2) * r, -(2 + r * 0.95), rng:range(-0.2, 0.2) * r) + W * r * 0.12, r * 0.55, yaw + 1.1, B.shade(pal.rock, 1.6), cloudOpts("FarRock"))
	if rng:chance(0.5) and r > 8 then
		local tp = center + Vector3.new(rng:range(-0.35, 0.35) * r, 0, rng:range(-0.35, 0.35) * r)
		B.block(m, CFrame.new(tp + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3, 6, 3), B.vary(pal.leaf, rng, 0.03), cloudOpts("FarRock"))
		B.pyramid4(m, tp + Vector3.new(0, 7, 0), 3, 2.6, math.rad(45), B.tint(pal.leaf, 1), cloudOpts("FarRock"))
	end
	return m
end

function Sky.build(ctx)
	local Config = ctx.Config
	local folder = B.folder(ctx.Root, "Clouds")
	for i = 1, #Config.Zones do
		ceiling(ctx, i, folder)
	end
	local rng = B.rng(31337)
	-- море облаков внизу (ниже Config.VoidY — туда не долететь)
	sea(ctx, folder, rng)
	-- далёкие парящие скалы: без текстур (на расстоянии это шум)
	local far = B.model(folder, "FarRocks")
	local pals = {
		{ top = rgb(96, 170, 74), rock = rgb(150, 100, 66), leaf = rgb(122, 186, 72) },
		{ top = rgb(232, 238, 252), rock = rgb(140, 156, 196), leaf = rgb(52, 120, 104) },
		{ top = rgb(232, 198, 140), rock = rgb(206, 160, 108), leaf = rgb(84, 150, 96) },
	}
	for k = 1, 7 do
		local a = (k / 7) * TAU + rng:range(-0.25, 0.25)
		local dist = rng:range(440, 640)
		local pos = Vector3.new(math.cos(a) * dist, rng:range(-40, 70), math.sin(a) * dist)
		farRock(far, pos, rng:range(8, 18), rng, pals[(k % #pals) + 1])
	end
	local _ = P
end

return Sky
