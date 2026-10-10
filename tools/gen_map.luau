--!nocheck
-- Генератор карты (Lune): создаёт src/map/Map.rbxmx и src/map/Plots.rbxmx.
-- Запуск из корня репозитория: lune run tools/gen_map.luau
-- ВАЖНО: в Lune CFrame.lookAt работает неверно вдоль оси Z, поэтому используем CFrame.fromMatrix.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Loader = require("./lib/loader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local Font = roblox.Font

local Config = Loader.load("src/shared/Config")

local PIT = Config.Plot.PitHalfSize -- 32
local DEPTH = Config.Plot.PitDepth -- 14
local GRID_HALF = Config.Grid.Width * Config.Grid.CellSize / 2 -- 24

local COLORS = {
	Grass = Color3.fromRGB(96, 168, 74),
	GrassDark = Color3.fromRGB(78, 140, 60),
	Plaza = Color3.fromRGB(205, 200, 188),
	PlazaTrim = Color3.fromRGB(150, 146, 138),
	Path = Color3.fromRGB(184, 176, 160),
	PitWall = Color3.fromRGB(122, 124, 128),
	PitFloor = Color3.fromRGB(92, 94, 98),
	BuildArea = Color3.fromRGB(110, 82, 56),
	Hazard = Color3.fromRGB(245, 196, 40),
	HazardDark = Color3.fromRGB(40, 40, 44),
	Ramp = Color3.fromRGB(150, 150, 154),
	Trunk = Color3.fromRGB(105, 72, 46),
	Leaves = Color3.fromRGB(70, 150, 70),
	Leaves2 = Color3.fromRGB(96, 170, 64),
	Rock = Color3.fromRGB(128, 128, 132),
	Wood = Color3.fromRGB(160, 110, 70),
	Roof = Color3.fromRGB(200, 70, 60),
	Sign = Color3.fromRGB(40, 44, 52),
	Lamp = Color3.fromRGB(255, 226, 160),
}

-- Детерминированный ГПСЧ (LCG), чтобы карта не менялась между сборками.
local seed = 1337
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function randRange(a: number, b: number): number
	return a + (b - a) * rand()
end

local function part(props: { [string]: any }, parent: Instance?): Instance
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" then
			p[k] = v
		end
	end
	if parent then
		p.Parent = parent
	end
	return p
end

-- Неколлизионная декоративная деталь (без запросов и касаний — дешевле для физики).
local function deco(props: { [string]: any }, parent: Instance?): Instance
	props.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	props.CanQuery = false
	props.CanTouch = false
	return part(props, parent)
end

local function box(cf, size: Vector3, color, material, parent, name: string?)
	return part({
		Name = name or "Part",
		CFrame = cf,
		Size = size,
		Color = color,
		Material = material,
		CanTouch = false,
	}, parent)
end

local function label(parentPart: Instance, face, text: string, textColor, bgColor, pixelsPerStud: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0.2
	gui.Parent = parentPart
	local tl = Instance.new("TextLabel")
	tl.Name = "Label"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = bgColor or Color3.fromRGB(0, 0, 0)
	tl.BackgroundTransparency = if bgColor then 0 else 1
	tl.TextColor3 = textColor
	tl.TextScaled = true
	tl.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
	tl.Text = text
	tl.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim2.fromScale(0.04, 0).X
	pad.PaddingRight = UDim2.fromScale(0.04, 0).X
	pad.PaddingTop = UDim2.fromScale(0, 0.08).Y
	pad.PaddingBottom = UDim2.fromScale(0, 0.08).Y
	pad.Parent = tl
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Parent = tl
	return gui, tl
end

----------------------------------------------------------------------
-- Расположение участков
----------------------------------------------------------------------
local PLOT_X = { -165, -55, 55, 165 }
local PLOT_Z = 130
local plotFrames = {}
do
	local id = 0
	-- Северный ряд (z < 0) смотрит на +Z (к лобби), южный ряд (z > 0) — на -Z.
	for _, row in { { z = -PLOT_Z, right = Vector3.new(-1, 0, 0) }, { z = PLOT_Z, right = Vector3.new(1, 0, 0) } } do
		for _, x in PLOT_X do
			id += 1
			local pos = Vector3.new(x, -DEPTH, row.z)
			plotFrames[id] = CFrame.fromMatrix(pos, row.right, Vector3.new(0, 1, 0))
		end
	end
end

----------------------------------------------------------------------
-- Map: земля, лобби, дорожки, магазин, деревья
----------------------------------------------------------------------
local map = Instance.new("Folder")
map.Name = "Map"

local WORLD_X = 250
local WORLD_Z = 215

-- Земля = прямоугольник мира минус отверстия котлованов.
do
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = map
	local holes = {}
	for _, cf in plotFrames do
		local p = cf.Position
		-- дыра по внешней грани стен котлована: внутренняя грань стены не совпадает с землёй
		table.insert(holes, { x0 = p.X - PIT - 2, x1 = p.X + PIT + 2, z0 = p.Z - PIT - 2, z1 = p.Z + PIT + 2 })
	end
	local xs = { -WORLD_X, WORLD_X }
	local zs = { -WORLD_Z, WORLD_Z }
	for _, h in holes do
		table.insert(xs, h.x0)
		table.insert(xs, h.x1)
		table.insert(zs, h.z0)
		table.insert(zs, h.z1)
	end
	local function uniqSort(t)
		table.sort(t)
		local out = {}
		for _, v in t do
			if out[#out] ~= v then
				table.insert(out, v)
			end
		end
		return out
	end
	xs = uniqSort(xs)
	zs = uniqSort(zs)
	local function isHole(cx: number, cz: number): boolean
		for _, h in holes do
			if cx > h.x0 and cx < h.x1 and cz > h.z0 and cz < h.z1 then
				return true
			end
		end
		return false
	end
	local count = 0
	for zi = 1, #zs - 1 do
		local z0, z1 = zs[zi], zs[zi + 1]
		local runStart = nil
		for xi = 1, #xs do
			local solid = false
			if xi < #xs then
				solid = not isHole((xs[xi] + xs[xi + 1]) / 2, (z0 + z1) / 2)
			end
			if solid and runStart == nil then
				runStart = xs[xi]
			elseif not solid and runStart ~= nil then
				local x0, x1 = runStart, xs[xi]
				count += 1
				part({
					Name = "Ground",
					Size = Vector3.new(x1 - x0, 4, z1 - z0),
					CFrame = CFrame.new((x0 + x1) / 2, -2, (z0 + z1) / 2),
					Color = COLORS.Grass,
					Material = Enum.Material.Grass,
					CanTouch = false,
				}, ground)
				runStart = nil
			end
		end
	end
	-- Невидимые стены по краям мира
	local h = 60
	for _, w in {
		{ CFrame.new(0, h / 2, -WORLD_Z - 1), Vector3.new(WORLD_X * 2, h, 2) },
		{ CFrame.new(0, h / 2, WORLD_Z + 1), Vector3.new(WORLD_X * 2, h, 2) },
		{ CFrame.new(-WORLD_X - 1, h / 2, 0), Vector3.new(2, h, WORLD_Z * 2) },
		{ CFrame.new(WORLD_X + 1, h / 2, 0), Vector3.new(2, h, WORLD_Z * 2) },
	} do
		part({
			Name = "Boundary",
			CFrame = w[1],
			Size = w[2],
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
		}, ground)
	end
	-- Под землёй — подложка, чтобы снизу не было видно пустоты из котлованов
	part({
		Name = "Underlay",
		Size = Vector3.new(WORLD_X * 2, 2, WORLD_Z * 2),
		CFrame = CFrame.new(0, -DEPTH - 6, 0),
		Color = Color3.fromRGB(70, 60, 50),
		Material = Enum.Material.Ground,
		CanQuery = false,
		CanTouch = false,
	}, ground)
end

-- Лобби
local lobby = Instance.new("Folder")
lobby.Name = "Lobby"
lobby.Parent = map
do
	deco({
		Name = "Plaza",
		Size = Vector3.new(150, 0.2, 110),
		CFrame = CFrame.new(0, 0.05, 0),
		Color = COLORS.Plaza,
		Material = Enum.Material.Pavement,
		CanCollide = true,
	}, lobby)
	-- Бордюр площади
	for _, b in {
		{ Vector3.new(0, 0.2, -55), Vector3.new(150, 0.4, 1.5) },
		{ Vector3.new(0, 0.2, 55), Vector3.new(150, 0.4, 1.5) },
		{ Vector3.new(-75, 0.2, 0), Vector3.new(1.5, 0.4, 110) },
		{ Vector3.new(75, 0.2, 0), Vector3.new(1.5, 0.4, 110) },
	} do
		deco({
			Name = "PlazaTrim",
			Size = b[2],
			CFrame = CFrame.new(b[1]),
			Color = COLORS.PlazaTrim,
			Material = Enum.Material.Slate,
			CanCollide = true,
		}, lobby)
	end

	local spawn = part({
		ClassName = "SpawnLocation",
		Name = "LobbySpawn",
		Size = Vector3.new(14, 1, 14),
		CFrame = CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(90, 170, 255),
		Material = Enum.Material.SmoothPlastic,
		CanTouch = true,
	}, lobby)
	spawn.Duration = 0
	spawn.Neutral = true

	-- Фонтан-пьедестал с табличкой
	deco({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 22, 22),
		CFrame = CFrame.new(0, 0.6, 22) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.PlazaTrim,
		Material = Enum.Material.Slate,
		CanCollide = true,
	}, lobby)

	-- Магазин (киоск) с ProximityPrompt
	local shop = Instance.new("Model")
	shop.Name = "Shop"
	shop.Parent = lobby
	local sx, sz = -42, -8
	box(CFrame.new(sx, 2, sz), Vector3.new(16, 4, 5), COLORS.Wood, Enum.Material.WoodPlanks, shop, "Counter")
	box(CFrame.new(sx, 4.15, sz), Vector3.new(16.6, 0.3, 5.6), Color3.fromRGB(230, 230, 230), Enum.Material.Marble, shop, "CounterTop")
	for _, px in { -7.5, 7.5 } do
		box(CFrame.new(sx + px, 6, sz - 2), Vector3.new(0.8, 12, 0.8), COLORS.Wood, Enum.Material.Wood, shop, "Post")
		box(CFrame.new(sx + px, 6, sz + 6), Vector3.new(0.8, 12, 0.8), COLORS.Wood, Enum.Material.Wood, shop, "Post")
	end
	box(CFrame.new(sx, 12.4, sz + 2) * CFrame.Angles(math.rad(-12), 0, 0), Vector3.new(18, 0.6, 11), COLORS.Roof, Enum.Material.SmoothPlastic, shop, "Roof")
	local signPart = box(CFrame.new(sx, 9.5, sz - 2.6), Vector3.new(12, 3, 0.4), COLORS.Sign, Enum.Material.SmoothPlastic, shop, "Sign")
	label(signPart, Enum.NormalId.Front, "🛒 МАГАЗИН", Color3.fromRGB(255, 220, 90))
	-- В Roblox лицевая сторона Front = -Z. Магазин стоит лицом к спавну (+X), поворачиваем модель.
	local promptPart = deco({
		Name = "ShopPromptPart",
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(sx, 3, sz - 3.5),
		Transparency = 1,
	}, shop)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Открыть магазин"
	prompt.ObjectText = "Магазин"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
	-- Разворачиваем весь магазин лицом к центру (поворот на 90° вокруг его центра)
	local pivot = CFrame.new(sx, 0, sz)
	local rot = CFrame.Angles(0, math.rad(-90), 0)
	for _, d in shop:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = pivot * rot * pivot:Inverse() * d.CFrame
		end
	end

	-- Информационная доска
	local board = Instance.new("Model")
	board.Name = "InfoBoard"
	board.Parent = lobby
	local bx, bz = 42, -8
	for _, px in { -7, 7 } do
		box(CFrame.new(bx + px, 5, bz), Vector3.new(0.8, 10, 0.8), COLORS.Wood, Enum.Material.Wood, board, "Post")
	end
	local boardPart = box(CFrame.new(bx, 7, bz), Vector3.new(16, 8, 0.5), COLORS.Sign, Enum.Material.SmoothPlastic, board, "Board")
	label(
		boardPart,
		Enum.NormalId.Front,
		"🏗 Строй бункер\n🌨 Пережди град\n☣ Выживи в кислотном дожде\n💰 Получай монеты и улучшайся!",
		Color3.fromRGB(255, 255, 255),
		nil,
		30
	)
	local pivot2 = CFrame.new(bx, 0, bz)
	local rot2 = CFrame.Angles(0, math.rad(90), 0)
	for _, d in board:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = pivot2 * rot2 * pivot2:Inverse() * d.CFrame
		end
	end

	-- Фонари на площади
	for _, lp in { Vector3.new(-60, 0, -45), Vector3.new(60, 0, -45), Vector3.new(-60, 0, 45), Vector3.new(60, 0, 45) } do
		deco({
			Name = "LampPost",
			Size = Vector3.new(0.6, 12, 0.6),
			CFrame = CFrame.new(lp + Vector3.new(0, 6, 0)),
			Color = COLORS.HazardDark,
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, lobby)
		local bulb = deco({
			Name = "LampBulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(lp + Vector3.new(0, 12.5, 0)),
			Color = COLORS.Lamp,
			Material = Enum.Material.Neon,
		}, lobby)
		local light = Instance.new("PointLight")
		light.Range = 24
		light.Brightness = 1.2
		light.Color = COLORS.Lamp
		light.Shadows = false
		light.Parent = bulb
	end
end

----------------------------------------------------------------------
-- Plots: котлованы
----------------------------------------------------------------------
local plots = Instance.new("Folder")
plots.Name = "Plots"

local function L(cf, x: number, y: number, z: number)
	return cf * CFrame.new(x, y, z)
end

for id, cf in plotFrames do
	local model = Instance.new("Model")
	model.Name = "Plot" .. id
	model:SetAttribute("PlotId", id)
	model:SetAttribute("Origin", cf)
	model.Parent = plots

	local origin = deco({
		Name = "Origin",
		Size = Vector3.new(1, 1, 1),
		CFrame = cf,
		Transparency = 1,
	}, model)
	model.PrimaryPart = origin

	local env = Instance.new("Folder")
	env.Name = "Environment"
	env.Parent = model

	-- Пол котлована вокруг сетки (толстые плиты: заодно стены подземной части сетки)
	local under = Config.Grid.Underground * Config.Grid.CellSize -- 32
	local slabH = under + 2
	local margin = PIT - GRID_HALF
	local mid = (PIT + GRID_HALF) / 2
	box(L(cf, 0, -slabH / 2, -mid), Vector3.new(PIT * 2, slabH, margin), COLORS.PitFloor, Enum.Material.Concrete, env, "Floor")
	box(L(cf, 0, -slabH / 2, mid), Vector3.new(PIT * 2, slabH, margin), COLORS.PitFloor, Enum.Material.Concrete, env, "Floor")
	box(L(cf, -mid, -slabH / 2, 0), Vector3.new(margin, slabH, GRID_HALF * 2), COLORS.PitFloor, Enum.Material.Concrete, env, "Floor")
	box(L(cf, mid, -slabH / 2, 0), Vector3.new(margin, slabH, GRID_HALF * 2), COLORS.PitFloor, Enum.Material.Concrete, env, "Floor")
	-- дно подземной части сетки (коренная порода: глубже копать нельзя, но на ней можно строить)
	box(L(cf, 0, -under - 1, 0), Vector3.new(GRID_HALF * 2, 2, GRID_HALF * 2), Color3.fromRGB(45, 42, 48), Enum.Material.Basalt, env, "Bedrock")
	-- Земля в зоне строительства: в игре её заменяет сервер (по клетке, чтобы можно было копать),
	-- а этот блок нужен только для вида карты в редакторе.
	part({
		Name = "TerrainPreview",
		Size = Vector3.new(GRID_HALF * 2, under, GRID_HALF * 2),
		CFrame = L(cf, 0, -under / 2, 0),
		Color = COLORS.BuildArea,
		Material = Enum.Material.Ground,
		CanCollide = true,
		CanTouch = false,
		CanQuery = false,
	}, model)
	-- Стены котлована (верх чуть ниже земли, чтобы не было мерцания)
	local wallH = DEPTH
	local wy = wallH / 2
	box(L(cf, 0, wy, -PIT - 1), Vector3.new(PIT * 2 + 4, wallH, 2), COLORS.PitWall, Enum.Material.Concrete, env, "Wall")
	box(L(cf, 0, wy, PIT + 1), Vector3.new(PIT * 2 + 4, wallH, 2), COLORS.PitWall, Enum.Material.Concrete, env, "Wall")
	box(L(cf, -PIT - 1, wy, 0), Vector3.new(2, wallH, PIT * 2), COLORS.PitWall, Enum.Material.Concrete, env, "Wall")
	box(L(cf, PIT + 1, wy, 0), Vector3.new(2, wallH, PIT * 2), COLORS.PitWall, Enum.Material.Concrete, env, "Wall")

	-- Предупреждающая окантовка по краю котлована (чуть выше земли)
	local stripeY = DEPTH + 0.06
	for _, s in {
		{ 0, -PIT - 1, Vector3.new(PIT * 2 + 4, 0.12, 2) },
		{ 0, PIT + 1, Vector3.new(PIT * 2 + 4, 0.12, 2) },
		{ -PIT - 1, 0, Vector3.new(2, 0.12, PIT * 2) },
		{ PIT + 1, 0, Vector3.new(2, 0.12, PIT * 2) },
	} do
		deco({
			Name = "Rim",
			Size = s[3],
			CFrame = L(cf, s[1], stripeY, s[2]),
			Color = COLORS.Hazard,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		}, env)
	end

	-- Пандус вдоль передней стены: высокий конец у левого переднего угла (x = -PIT), низкий у x = -4.
	do
		local run = PIT - 4 -- 28
		local rise = DEPTH
		local length = math.sqrt(run * run + rise * rise)
		local angle = math.atan2(rise, run)
		local cx = -(PIT + 4) / 2 -- -18
		local cz = -PIT + 4 -- -28 (полоса z ∈ [-32, -24])
		local slab = L(cf, cx, rise / 2, cz) * CFrame.Angles(0, 0, -angle)
		part({
			Name = "Ramp",
			Size = Vector3.new(length + 1, 1, 8),
			CFrame = slab * CFrame.new(0, -0.5, 0),
			Color = COLORS.Ramp,
			Material = Enum.Material.DiamondPlate,
			CanTouch = false,
		}, env)
		-- Перила со стороны зоны строительства
		part({
			Name = "Railing",
			Size = Vector3.new(length, 0.4, 0.4),
			CFrame = slab * CFrame.new(0, 3, 3.8),
			Color = COLORS.Hazard,
			Material = Enum.Material.Metal,
			CanTouch = false,
		}, env)
		for i = 0, 3 do
			local t = (i + 0.5) / 4
			local px = -PIT + run * t
			local py = rise * (1 - t)
			deco({
				Name = "RailPost",
				Size = Vector3.new(0.3, 3, 0.3),
				CFrame = L(cf, px, py + 1.5, -PIT + 7.8),
				Color = COLORS.HazardDark,
				Material = Enum.Material.Metal,
				CanCollide = true,
			}, env)
		end
	end

	-- Фонари по углам котлована (освещают бункер во время шторма)
	for _, c in { { -PIT + 2, -PIT + 10 }, { PIT - 2, -PIT + 2 }, { -PIT + 2, PIT - 2 }, { PIT - 2, PIT - 2 } } do
		deco({
			Name = "PitLampPost",
			Size = Vector3.new(0.5, 9, 0.5),
			CFrame = L(cf, c[1], 4.5, c[2]),
			Color = COLORS.HazardDark,
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, env)
		local bulb = deco({
			Name = "PitLamp",
			Size = Vector3.new(1.4, 0.8, 1.4),
			CFrame = L(cf, c[1], 9.2, c[2]),
			Color = COLORS.Lamp,
			Material = Enum.Material.Neon,
		}, env)
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 0.9
		light.Color = COLORS.Lamp
		light.Shadows = false
		light.Parent = bulb
	end

	-- Табличка владельца на земле перед котлованом
	do
		local signCf = L(cf, 8, DEPTH, -PIT - 6)
		for _, px in { -6.5, 6.5 } do
			deco({
				Name = "SignPost",
				Size = Vector3.new(0.6, 7, 0.6),
				CFrame = signCf * CFrame.new(px, 3.5, 0),
				Color = COLORS.Wood,
				Material = Enum.Material.Wood,
				CanCollide = true,
			}, model)
		end
		local sign = part({
			Name = "Sign",
			Size = Vector3.new(14, 4, 0.5),
			CFrame = signCf * CFrame.new(0, 6, 0),
			Color = COLORS.Sign,
			Material = Enum.Material.SmoothPlastic,
			CanTouch = false,
		}, model)
		-- Лицевая сторона таблички (Front = -Z локально) смотрит в сторону лобби.
		label(sign, Enum.NormalId.Front, "Свободный участок", Color3.fromRGB(255, 255, 255))
		label(sign, Enum.NormalId.Back, "Свободный участок", Color3.fromRGB(255, 255, 255))
	end

	local blocks = Instance.new("Folder")
	blocks.Name = "Blocks"
	blocks.Parent = model
	local storm = Instance.new("Folder")
	storm.Name = "Storm"
	storm.Parent = model
end

----------------------------------------------------------------------
-- Дорожки от площади к участкам и деревья
----------------------------------------------------------------------
do
	local paths = Instance.new("Folder")
	paths.Name = "Paths"
	paths.Parent = map
	for _, cf in plotFrames do
		-- точка входа на пандус (верх пандуса) на уровне земли
		local entry = (cf * CFrame.new(-PIT + 3, DEPTH, -PIT - 4)).Position
		local zEdge = if entry.Z < 0 then -55 else 55
		local z0, z1 = math.min(zEdge, entry.Z), math.max(zEdge, entry.Z)
		local zMid = (z0 + z1) / 2
		local len = z1 - z0
		deco({
			Name = "Path",
			Size = Vector3.new(8, 0.16, len),
			CFrame = CFrame.new(entry.X, 0.04, zMid),
			Color = COLORS.Path,
			Material = Enum.Material.Pavement,
			CanCollide = true,
		}, paths)
		-- соединение вдоль площади, если дорожка вне её ширины
		if math.abs(entry.X) > 75 then
			local x0, x1 = math.min(entry.X, 0), math.max(entry.X, 0)
			x0 = math.max(x0, -math.abs(entry.X))
			local sx0 = if entry.X < 0 then entry.X - 4 else 75
			local sx1 = if entry.X < 0 then -75 else entry.X + 4
			deco({
				Name = "Path",
				Size = Vector3.new(sx1 - sx0, 0.16, 8),
				CFrame = CFrame.new((sx0 + sx1) / 2, 0.04, zEdge + (if zEdge < 0 then -4 else 4)),
				Color = COLORS.Path,
				Material = Enum.Material.Pavement,
				CanCollide = true,
			}, paths)
			local _ = x1
		end
	end

	local nature = Instance.new("Folder")
	nature.Name = "Nature"
	nature.Parent = map

	local blocked = {}
	for _, cf in plotFrames do
		local p = cf.Position
		table.insert(blocked, { x0 = p.X - PIT - 12, x1 = p.X + PIT + 12, z0 = p.Z - PIT - 14, z1 = p.Z + PIT + 12 })
	end
	table.insert(blocked, { x0 = -85, x1 = 85, z0 = -65, z1 = 65 })
	local function free(x: number, z: number): boolean
		for _, b in blocked do
			if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 then
				return false
			end
		end
		-- не ставим деревья на дорожки
		for _, cf in plotFrames do
			local entry = (cf * CFrame.new(-PIT + 3, DEPTH, -PIT - 4)).Position
			if math.abs(x - entry.X) < 9 and math.abs(z) < math.abs(entry.Z) + 4 then
				return false
			end
		end
		return true
	end

	local placed = 0
	local attempts = 0
	while placed < 34 and attempts < 2000 do
		attempts += 1
		local x = randRange(-WORLD_X + 8, WORLD_X - 8)
		local z = randRange(-WORLD_Z + 8, WORLD_Z - 8)
		if free(x, z) then
			placed += 1
			local tree = Instance.new("Model")
			tree.Name = "Tree"
			tree.Parent = nature
			local h = randRange(9, 15)
			part({
				Name = "Trunk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(h, 1.6, 1.6),
				CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
				Color = COLORS.Trunk,
				Material = Enum.Material.Wood,
				CanTouch = false,
				CanQuery = false,
			}, tree)
			local r = randRange(7, 11)
			deco({
				Name = "Leaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(r, r, r),
				CFrame = CFrame.new(x, h + r * 0.3, z),
				Color = if rand() > 0.5 then COLORS.Leaves else COLORS.Leaves2,
				Material = Enum.Material.Grass,
				CastShadow = true,
			}, tree)
			local r2 = r * 0.7
			deco({
				Name = "Leaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(r2, r2, r2),
				CFrame = CFrame.new(x + randRange(-2, 2), h + r * 0.75, z + randRange(-2, 2)),
				Color = COLORS.Leaves2,
				Material = Enum.Material.Grass,
			}, tree)
		end
	end

	-- Камни
	local rocks = 0
	attempts = 0
	while rocks < 18 and attempts < 2000 do
		attempts += 1
		local x = randRange(-WORLD_X + 6, WORLD_X - 6)
		local z = randRange(-WORLD_Z + 6, WORLD_Z - 6)
		if free(x, z) then
			rocks += 1
			local s = randRange(2.5, 5.5)
			part({
				Name = "Rock",
				Size = Vector3.new(s * randRange(1, 1.6), s * 0.7, s),
				CFrame = CFrame.new(x, s * 0.25, z) * CFrame.Angles(randRange(-0.3, 0.3), randRange(0, math.pi), randRange(-0.3, 0.3)),
				Color = COLORS.Rock,
				Material = Enum.Material.Slate,
				CanTouch = false,
			}, nature)
		end
	end
end

fs.writeFile("src/map/Map.rbxmx", roblox.serializeModel({ map }, true))
fs.writeFile("src/map/Plots.rbxmx", roblox.serializeModel({ plots }, true))

local function countParts(root): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
print(string.format("Map: %d parts, Plots: %d parts (%d plots)", countParts(map), countParts(plots), #plotFrames))
