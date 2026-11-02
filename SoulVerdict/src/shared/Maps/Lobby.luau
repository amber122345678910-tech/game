--!strict
-- Maps/Lobby: "Last Star Haven" — the cozy floating hub every player sees behind the title screen. [Lune-safe]
-- A grassy sky island at golden afternoon (preset Lobby). In the middle, a fountain holds the giant
-- floating SAVE star (players spawn around it). The seven human SOUL podiums circle the plaza; the three
-- monster "Judges" stand on a dark stage to the north. East: leaderboards. South-east: the daily shop
-- booth. South-west: the quest board. South: the practice portal and the patch-notes scroll. West: the
-- training grounds with dummy spots. Lamps, benches, blossom trees, flower beds, floating lanterns.
-- Built around the origin (grass top y = 0); MapService keeps it at Registry.LobbyOrigin.
--
-- API (Types.MapDef): Lobby.Id/Name/Desc/Preset/FinalPreset/Music, Lobby.Build(seed?) -> MapInfo
--   MapInfo.HumanSpawns = lobby spawn points (CharacterService), MapInfo.DummySpawns = training dummies
--   (BotService). No SAVE points.
-- Markers (Model.Markers, invisible parts; LobbyController + other clients look them up by name):
--   LobbySpawn_<i> (12), DummySpot_<i> (5), Podium_<kitId> (10, CFrame = statue feet, facing out),
--   Board_Wins / Board_Level (SurfaceGui "Leaderboard": Title + Rows/Row<i>/{Rank,Name,Value}),
--   ShopBooth / QuestBoard / PracticePortal (ProximityPrompt "Prompt", attribute Action = "Shop" |
--   "Quests" | "Practice"), PatchNotes (SurfaceGui), MenuCamera (title-screen camera CFrame),
--   CenterStar (the floating star's centre), Center, KillFloor.
-- Model "Decor/Plaza/CenterStar" (PrimaryPart "Core") and Decor/Sky lanterns are animated by LobbyController.

local Types = require(script.Parent.Parent.Types)
local MapKit = require(script.Parent.MapKit)

type MapInfo = Types.MapInfo

local Lobby = {}

Lobby.Id = "Lobby"
Lobby.Name = { en = "Last Star Haven", ru = "Приют Последней Звезды" }
Lobby.Desc = {
	en = "A cozy haven around the last SAVE star. Rest, train and choose your SOUL before the next trial.",
	ru = "Уютный приют у последней звезды СОХРАНЕНИЯ. Отдохни, потренируйся и выбери ДУШУ перед новым судом.",
}
Lobby.Preset = "Lobby"
Lobby.FinalPreset = "Lobby"
Lobby.Music = "Lobby"

local V = Vector3.new
local M = Enum.Material

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- The seven SOUL podiums sit every 360/7 deg starting at SoulPhase; every destination lies on a GAP
-- angle between two podiums so the paths never cross a statue.
local GAP = 360 / 7
local L = {
	IslandR = 76,
	PlazaR = 24,
	SpawnR = 17,
	SoulR = 31,
	SoulPhase = 270 - GAP / 2 - 3 * GAP, -- = 38.57: the north (270) is a gap
	StageZ = -58,
	KillY = -60,
	BoardsAngle = 270 - GAP / 2 + 2 * GAP, -- 12.86
	ShopAngle = 270 - GAP / 2 + 3 * GAP, -- 64.29
	PortalAngle = 270 - GAP / 2 + 4 * GAP, -- 115.71
	QuestAngle = 270 - GAP / 2 + 5 * GAP, -- 167.14
	TrainingAngle = 270 - GAP / 2 + 6 * GAP, -- 218.57
	NotesAngle = 270 + GAP, -- 321.43
	ShopSeat = { Z = 0.6, Top = 3.36 }, -- the shopkeeper's stool seat (booth-local: z behind the counter, y = seat top)
}
Lobby.Layout = L

local C = {
	Grass = rgb(120, 170, 88),
	GrassDark = rgb(96, 146, 72),
	Stone = rgb(238, 228, 206),
	StoneMid = rgb(214, 200, 174),
	StoneDark = rgb(150, 136, 118),
	Cobble = rgb(200, 184, 156),
	Gold = rgb(224, 178, 82),
	GoldDark = rgb(156, 112, 46),
	Wood = rgb(152, 106, 68),
	WoodDark = rgb(102, 70, 44),
	Rock = rgb(132, 116, 100),
	RockDark = rgb(96, 84, 74),
	Slate = rgb(52, 48, 66),
	SlateDark = rgb(34, 31, 44),
	Water = rgb(120, 196, 236),
	Star = rgb(255, 214, 96),
	StarCore = rgb(255, 246, 214),
	Lamp = rgb(255, 186, 110),
	Navy = rgb(26, 32, 60),
	Parchment = rgb(242, 228, 192),
	Cork = rgb(176, 130, 84),
	Portal = rgb(124, 92, 255),
	PortalCore = rgb(186, 236, 255),
}

-- Kit registry (Lune-safe data); a missing/broken registry only removes the podium statues' names.
local function kitList(): { any }
	local shared: any = script.Parent.Parent
	local module = shared:FindFirstChild("Kits")
	if module then
		local ok, kits = pcall(require, module)
		if ok and type(kits) == "table" and type((kits :: any).All) == "function" then
			local okAll, list = pcall((kits :: any).All)
			if okAll and type(list) == "table" then
				return list
			end
		end
	end
	return {}
end

-- Maps/Shopkeeper (the sleepy Sans NPC); a missing/broken module only removes the shopkeeper.
local function shopkeeperModule(): any
	local module = (script.Parent :: any):FindFirstChild("Shopkeeper")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type((result :: any).Build) == "function" then
			return result
		end
	end
	return nil
end

local function pick(loc: any): string
	if type(loc) == "table" then
		return loc.en or ""
	end
	return tostring(loc or "")
end

local function polar(r: number, deg: number, y: number?): Vector3
	local a = math.rad(deg)
	return V(math.cos(a) * r, y or 0, math.sin(a) * r)
end

-- Sections -------------------------------------------------------------------------------------------------

local function buildIsland(B: MapKit.Builder)
	B:Group("Island")
	B:Disc("Geometry", "Grass", V(0, -3, 0), L.IslandR * 2, 6, C.Grass, M.Grass, { Shadow = false })
	B:Disc("Decor", "GrassEdge", V(0, -1.7, 0), L.IslandR * 2 + 1.2, 2.6, C.GrassDark, M.Grass, { Shadow = false })
	-- stepped rock underside
	local tiers = { { 148, 8, -9 }, { 124, 10, -17 }, { 96, 12, -27 }, { 64, 12, -38 }, { 34, 12, -49 }, { 12, 10, -58 } }
	for i, t in tiers do
		B:Disc("Decor", "Underside" .. i, V(0, t[3], 0), t[1], t[2], if i % 2 == 0 then C.RockDark else C.Rock, M.Slate)
	end
	-- glowing crystals hanging under the island
	for i = 0, 5 do
		local p = polar(18 + (i % 2) * 10, i * 60 + 15, -36 - (i % 3) * 6)
		B:Cone("Decor", "HangingCrystal" .. i, p, -9 - (i % 3) * 3, 1.6, 5, rgb(140, 220, 255), M.Neon, { Transparency = 0.2, Shadow = false })
	end
	-- low stone parapet + invisible boundary
	B:Ring("Geometry", "Parapet", V(0, 0.8, 0), L.IslandR - 1.2, 1.4, 1.6, 40, C.StoneMid, M.Limestone)
	B:Ring("Decor", "ParapetCap", V(0, 1.7, 0), L.IslandR - 1.2, 1.8, 0.25, 40, C.Gold, M.Metal, { Shadow = false })
	local prev = B:Group("Boundary")
	B:Ring("Geometry", "Boundary", V(0, 12, 0), L.IslandR + 0.5, 1, 24, 32, C.Stone, M.SmoothPlastic, {
		Transparency = 1,
		Shadow = false,
		Query = false,
	})
	B:Group(prev)
	-- floating islets drifting around the haven
	local rng = B.Rng
	for i = 0, 4 do
		local p = polar(rng:Number(98, 118), i * 72 + rng:Number(-12, 12), rng:Number(-14, 10))
		local r = rng:Number(7, 11)
		B:Disc("Decor", "Islet" .. i, p, r * 2, 2.5, C.Grass, M.Grass)
		B:Cone("Decor", "IsletRock" .. i, p - V(0, 1.25, 0), -r * 1.6, r, 6, C.Rock, M.Slate, { Shadow = false })
		B:Tree("IsletTree" .. i, p + V(0, 1.25, 0), rng:Number(9, 13), { Leaf = rgb(150, 190, 96), Blossom = rgb(255, 188, 214) })
	end
	B:Group(nil)
end

local function buildPlaza(B: MapKit.Builder): { Light }
	B:Group("Plaza")
	local lights: { Light } = {}
	B:Disc("Decor", "Pavement", V(0, 0.04, 0), L.PlazaR * 2, 0.1, C.Stone, M.Limestone, { Shadow = false })
	B:Ring("Decor", "PlazaRim", V(0, 0.1, 0), L.PlazaR - 0.4, 0.8, 0.1, 48, C.Gold, M.Metal, { Shadow = false })
	B:Ring("Decor", "PlazaInner", V(0, 0.1, 0), 13, 0.5, 0.1, 36, C.StoneDark, M.Limestone, { Shadow = false })
	for k = 0, 7 do
		local a = k * 45 + 22.5
		local mid = polar(18.5, a, 0.1)
		B:Deco("Block", "Spoke", V(0.35, 0.1, 10.5), MapKit.Facing(mid, V(0, 0.1, 0)), C.Gold, M.Metal, { Shadow = false })
	end
	-- fountain: basin, water, rim, pedestal
	B:Disc("Geometry", "Basin", V(0, 0.6, 0), 15, 1.2, C.StoneMid, M.Limestone)
	B:Disc("Decor", "Water", V(0, 1.22, 0), 13.2, 0.1, C.Water, M.Glass, { Transparency = 0.25, Shadow = false, Reflectance = 0.25 } :: any)
	B:Ring("Decor", "Rim", V(0, 1.5, 0), 7.1, 0.9, 0.7, 28, C.Stone, M.Limestone)
	B:Ring("Decor", "RimGold", V(0, 1.9, 0), 7.1, 1.0, 0.12, 28, C.Gold, M.Metal, { Shadow = false })
	B:Disc("Geometry", "Pedestal", V(0, 2.6, 0), 3.2, 4, C.Stone, M.Marble)
	B:Disc("Decor", "PedestalCap", V(0, 4.7, 0), 4.2, 0.4, C.Gold, M.Metal)
	B:Disc("Decor", "PedestalBand", V(0, 2.2, 0), 3.5, 0.3, C.Gold, M.Metal, { Shadow = false })
	-- the floating SAVE star (its own Model so the client can spin/bob it)
	local starModel = Instance.new("Model")
	starModel.Name = "CenterStar"
	local center = V(0, 9.5, 0)
	local core = B:Deco("Ball", "Core", V(1.8, 1.8, 1.8), CFrame.new(center), C.StarCore, M.Neon, { Shadow = false, Parent = starModel })
	B:Star("Decor", "Star", CFrame.new(center), 3.6, 1.5, 1.1, C.Star, M.Neon, { Shadow = false, Parent = starModel })
	B:ArcRing("Decor", "Halo", CFrame.new(center) * CFrame.Angles(math.rad(90), 0, 0), 5.2, 0, 360, 24, 0.18, 0.18, C.Star, M.Neon, {
		Shadow = false,
		Transparency = 0.35,
		Parent = starModel,
	})
	B:Particles(core, "Sparkles", { Rate = 6, Size = 0.9, Color = C.Star })
	starModel.PrimaryPart = core
	starModel.Parent = B:_folder("Decor")
	table.insert(lights, B:Light("Point", center, { Name = "StarLight", Brightness = 2.2, Range = 34, Color = rgb(255, 214, 140), Shadows = true }))
	B:Marker("StarAnchor", CFrame.new(center))
	-- lamp posts and benches around the plaza
	for k = 0, 7 do
		local a = k * 45 + 22.5
		local l = B:Lamp("PlazaLamp" .. k, polar(L.PlazaR + 2, a), {
			Style = "Post",
			Height = 9,
			Metal = rgb(60, 52, 48),
			Glow = rgb(255, 214, 150),
			LightColor = C.Lamp,
			Brightness = 1.3,
			Range = 18,
		})
		if l then
			table.insert(lights, l)
		end
		local benchPos = polar(L.PlazaR + 2.5, a + 22.5)
		if k % 2 == 1 then
			local cf = MapKit.Facing(benchPos, V(0, 0, 0))
			B:Solid("Block", "BenchSeat", V(6, 0.4, 2), cf * CFrame.new(0, 1.6, 0), C.Wood, M.WoodPlanks)
			B:Solid("Block", "BenchBack", V(6, 1.6, 0.3), cf * CFrame.new(0, 2.6, 0.95) * CFrame.Angles(math.rad(-10), 0, 0), C.Wood, M.WoodPlanks)
			for _, sx in { -2.6, 2.6 } do
				B:Deco("Block", "BenchLeg", V(0.4, 1.5, 1.8), cf * CFrame.new(sx, 0.75, 0), rgb(60, 52, 48), M.Metal)
			end
		end
	end
	B:Group(nil)
	return lights
end

local function buildSpawns(B: MapKit.Builder): { CFrame }
	local spawns: { CFrame } = {}
	for i = 1, 12 do
		local p = polar(L.SpawnR, (i - 1) * 30 + 15)
		table.insert(spawns, B:SpawnPoint("Lobby", i, MapKit.Facing(p, V(0, 0, 0))))
	end
	return spawns
end

-- One kit podium; returns its light (if any).
local function podium(B: MapKit.Builder, kit: any, base: Vector3, facing: Vector3, monster: boolean): Light?
	local id = tostring(kit.Id)
	local color: Color3 = if typeof(kit.Color) == "Color3" then kit.Color else C.Gold
	local frame = MapKit.Facing(base, base + facing)
	local stone = if monster then C.Slate else C.Stone
	local trim = if monster then C.GoldDark else C.Gold
	B:Solid("Block", "Plinth_" .. id, V(6.4, 0.6, 6.4), frame * CFrame.new(0, 0.3, 0), if monster then C.SlateDark else C.StoneMid, if monster then M.Slate else M.Limestone)
	B:Disc("Geometry", "Pedestal_" .. id, base + V(0, 1.7, 0), 4.6, 2.2, stone, M.Marble)
	B:Disc("Decor", "PedestalCap_" .. id, base + V(0, 2.9, 0), 5.2, 0.3, trim, M.Metal)
	B:Disc("Decor", "SoulBand_" .. id, base + V(0, 1.45, 0), 4.75, 0.35, color, M.Neon, { Shadow = false })
	-- name plate: slanted plaque in front of the pedestal
	local plate = B:Deco("Block", "Plate_" .. id, V(4.4, 1.5, 0.25), frame * CFrame.new(0, 1.1, -3.4) * CFrame.Angles(math.rad(35), 0, 0), if monster then C.SlateDark else C.WoodDark, M.Wood)
	B:Deco("Block", "PlateStand_" .. id, V(0.4, 1, 0.4), frame * CFrame.new(0, 0.45, -3.2), trim, M.Metal)
	B:Text(plate, Enum.NormalId.Front, {
		Text = pick(kit.Name),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.35),
		Font = "Merriweather",
		Pixels = 70,
		Height = 0.62,
		Stroke = true,
		Attributes = { KitId = id, KitField = "Name" },
	})
	local marker = B:Marker("Podium_" .. id, frame + V(0, 3.05, 0), { Group = "Podiums", Attributes = { KitId = id, Role = if monster then "Monster" else "Human" } })
	local _ = marker
	return B:Light("Point", base + V(0, 7.5, 0) + facing.Unit * 2.5, {
		Name = "PodiumLight_" .. id,
		Brightness = 0.9,
		Range = 11,
		Color = color:Lerp(Color3.new(1, 1, 1), 0.55),
	})
end

local function buildSoulRing(B: MapKit.Builder, kits: { any }): { Light }
	B:Group("SoulPodiums")
	local lights: { Light } = {}
	local humans: { any } = {}
	for _, kit in kits do
		if kit.Role == "Human" then
			table.insert(humans, kit)
		end
	end
	local n = math.max(1, #humans)
	for k, kit in humans do
		local a = L.SoulPhase + (k - 1) * 360 / n
		local base = polar(L.SoulR, a)
		-- statues look outward-ish towards the plaza ring walkers: face the centre
		local l = podium(B, kit, base, V(0, 0, 0) - base, false)
		if l then
			table.insert(lights, l)
		end
	end
	B:Group(nil)
	return lights
end

local function buildJudgesStage(B: MapKit.Builder, kits: { any }): { Light }
	B:Group("JudgesStage")
	local lights: { Light } = {}
	local c = V(0, 0, L.StageZ)
	B:Disc("Geometry", "StageStep", c + V(0, 0.3, 0), 36, 0.6, C.StoneDark, M.Slate)
	B:Disc("Geometry", "Stage", c + V(0, 0.6, 0), 33, 1.2, C.Slate, M.Slate)
	B:Ring("Decor", "StageRim", c + V(0, 1.22, 0), 16.3, 0.6, 0.06, 36, C.Gold, M.Metal, { Shadow = false })
	-- curved backdrop of tall dark slabs with neon seams
	for i = 0, 6 do
		local a = 200 + i * (140 / 6)
		local p = c + polar(17.5, a)
		local cf = MapKit.Facing(p, c)
		B:Solid("Block", "Backdrop", V(7.4, 16, 1.2), cf * CFrame.new(0, 8, 0), C.SlateDark, M.Slate)
		B:Deco("Block", "BackdropTrim", V(7.6, 0.6, 1.5), cf * CFrame.new(0, 16, 0), C.Gold, M.Metal, { Shadow = false })
		if i < 6 then
			local seam = c + polar(17.3, a + 140 / 12)
			B:Deco("Block", "Seam", V(0.25, 14, 0.4), MapKit.Facing(seam, c) * CFrame.new(0, 8, 0), rgb(120, 100, 255), M.Neon, { Shadow = false, Transparency = 0.2 })
		end
	end
	local monsters: { any } = {}
	for _, kit in kits do
		if kit.Role == "Monster" then
			table.insert(monsters, kit)
		end
	end
	local slots = { V(-9, 1.2, L.StageZ + 1.5), V(0, 1.2, L.StageZ - 2), V(9, 1.2, L.StageZ + 1.5) }
	-- middle slot for the first monster (The Judge), sides for the others
	local order = { 2, 1, 3 }
	for i, kit in monsters do
		local slot = slots[order[i] or i]
		if slot then
			local l = podium(B, kit, slot, V(0, 0, 1), true)
			if l then
				table.insert(lights, l)
			end
			local bannerCF = MapKit.Facing(c + polar(16.6, 270 + (slot.X / 9) * 26, 15), c + V(0, 15, 0))
			B:Banner("JudgeBanner", bannerCF, 4.5, 11, {
				Color = (kit.Color :: Color3):Lerp(Color3.new(0, 0, 0), 0.35),
				Trim = C.Gold,
				Emblem = "Delta",
				EmblemColor = rgb(255, 220, 140),
			})
		end
	end
	local sign = B:Deco("Block", "StageSign", V(14, 2.2, 0.5), MapKit.Facing(c + polar(16.8, 270, 18.2), c + V(0, 18.2, 0)), C.SlateDark, M.Slate)
	B:Text(sign, Enum.NormalId.Front, { Key = "maps.lobby.stage.sign", Color = C.Star, Font = "GrenzeGotisch", Pixels = 60, Glow = true })
	B:Group(nil)
	return lights
end

local function leaderboard(B: MapKit.Builder, name: string, titleKey: string, center: Vector3)
	local frame = MapKit.Facing(center, V(0, center.Y, 0))
	B:Solid("Block", name .. "_Base", V(15, 0.8, 4), frame * CFrame.new(0, 0.4, 0.6), C.StoneMid, M.Limestone)
	for _, sx in { -6.6, 6.6 } do
		B:Solid("Block", name .. "_Post", V(0.9, 13, 0.9), frame * CFrame.new(sx, 6.5, 0.6), C.WoodDark, M.Wood)
	end
	B:Solid("Block", name .. "_Frame", V(13.6, 10.2, 0.8), frame * CFrame.new(0, 7.6, 0.6), C.WoodDark, M.Wood)
	B:Deco("Block", name .. "_Panel", V(12.4, 9, 0.2), frame * CFrame.new(0, 7.6, 0.15), C.Navy, M.SmoothPlastic, { Shadow = false })
	B:Deco("Block", name .. "_Rim", V(12.8, 0.25, 0.3), frame * CFrame.new(0, 12.2, 0.1), C.Gold, M.Metal, { Shadow = false })
	-- little gable roof + star finial
	local roofY = 13.2
	local a = (frame * CFrame.new(-7.4, roofY, 0.6)).Position
	local b = (frame * CFrame.new(7.4, roofY, 0.6)).Position
	local top = (frame * CFrame.new(0, roofY + 2.6, 0.6)).Position
	B:Triangle("Decor", name .. "_Gable", a, b, top, 1.4, C.Wood, M.WoodPlanks)
	B:Star("Decor", name .. "_Finial", frame * CFrame.new(0, roofY + 3.6, 0.6), 0.9, 0.38, 0.25, C.Gold, M.Metal)
	-- the screen: invisible marker carrying the SurfaceGui the client fills
	local screen = B:Marker(name, frame * CFrame.new(0, 7.6, 0.0), { Size = V(12.4, 9, 0.1), Group = "Boards" })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.ClipsDescendants = true
	local font = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.14)
	title.Position = UDim2.fromScale(0.05, 0.03)
	title.TextScaled = true
	title.FontFace = font
	title.TextColor3 = C.Star
	title.Text = MapKit.L(titleKey)
	title:SetAttribute("TextKey", titleKey)
	title.Parent = gui
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(0.9, 0.76)
	rows.Position = UDim2.fromScale(0.05, 0.2)
	rows.Parent = gui
	for i = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = if i % 2 == 0 then 0.94 else 1
		row.BorderSizePixel = 0
		row.Size = UDim2.fromScale(1, 0.1)
		row.Position = UDim2.fromScale(0, (i - 1) * 0.1)
		row.LayoutOrder = i
		row.Parent = rows
		local function cell(cellName: string, x: number, w: number, align: Enum.TextXAlignment, text: string, color: Color3)
			local t = Instance.new("TextLabel")
			t.Name = cellName
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(w, 0.86)
			t.Position = UDim2.fromScale(x, 0.07)
			t.TextScaled = true
			t.FontFace = font
			t.TextXAlignment = align
			t.TextColor3 = color
			t.Text = text
			t.Parent = row
		end
		local rankColor = if i == 1 then rgb(255, 214, 96) elseif i == 2 then rgb(220, 224, 236) elseif i == 3 then rgb(230, 160, 100) else rgb(200, 200, 214)
		cell("Rank", 0, 0.1, Enum.TextXAlignment.Left, tostring(i), rankColor)
		cell("Name", 0.12, 0.6, Enum.TextXAlignment.Left, if i == 1 then MapKit.L("maps.lobby.board.loading") else MapKit.L("maps.lobby.board.empty"), rgb(240, 236, 226))
		cell("Value", 0.72, 0.28, Enum.TextXAlignment.Right, "", rgb(255, 230, 160))
	end
	gui.Parent = screen
end

local function buildBoards(B: MapKit.Builder): { Light }
	B:Group("Leaderboards")
	leaderboard(B, "Board_Wins", "maps.lobby.board.wins", polar(55, L.BoardsAngle - 8.5))
	leaderboard(B, "Board_Level", "maps.lobby.board.level", polar(55, L.BoardsAngle + 8.5))
	local l = B:Lamp("BoardLamp", polar(51, L.BoardsAngle), {
		Style = "Post",
		Height = 10,
		Metal = rgb(60, 52, 48),
		LightColor = C.Lamp,
		Brightness = 1.4,
		Range = 20,
	})
	B:Group(nil)
	return if l then { l } else {}
end

-- Sleepy Sans behind the counter (Maps/Shopkeeper), perched on a tall stool and slumped over the counter top.
-- The rig is built into the map frozen (anchored ghost parts, no Humanoid); ShopkeeperController animates it.
local function buildShopkeeper(B: MapKit.Builder, frame: CFrame)
	local seat = L.ShopSeat
	local floorY = 0.5
	-- tall wooden bar stool: round seat, four splayed legs, a brass foot ring
	B:Disc("Decor", "StoolSeat", (frame * CFrame.new(0, seat.Top - 0.14, seat.Z)).Position, 1.7, 0.28, C.WoodDark, M.Wood)
	B:Disc("Decor", "StoolSeatTrim", (frame * CFrame.new(0, seat.Top - 0.31, seat.Z)).Position, 1.45, 0.08, C.GoldDark, M.Metal, { Shadow = false })
	for k = 0, 3 do
		local a = math.rad(45 + k * 90)
		local top = frame * CFrame.new(math.cos(a) * 0.5, seat.Top - 0.3, seat.Z + math.sin(a) * 0.5)
		local foot = frame * CFrame.new(math.cos(a) * 0.78, floorY, seat.Z + math.sin(a) * 0.78)
		local mid = (top.Position + foot.Position) / 2
		local length = (top.Position - foot.Position).Magnitude
		B:Deco("Block", "StoolLeg", V(0.16, 0.16, length), MapKit.LookAt(mid, top.Position), C.WoodDark, M.Wood, { Shadow = false })
	end
	B:Ring("Decor", "StoolRing", (frame * CFrame.new(0, floorY + 1.15, seat.Z)).Position, 0.66, 0.1, 0.1, 8, C.Gold, M.Metal, { Shadow = false })
	local Shopkeeper = shopkeeperModule()
	if Shopkeeper == nil then
		return
	end
	local ok, npc = pcall(Shopkeeper.Build, frame * CFrame.new(0, seat.Top, seat.Z))
	if not ok or typeof(npc) ~= "Instance" then
		B.Model:SetAttribute("ShopkeeperError", tostring(npc))
		return
	end
	npc.Parent = B:_folder("Decor")
	local count = npc:GetAttribute("PartCount")
	B.PartCount += if type(count) == "number" then count else 0
end

local function buildShop(B: MapKit.Builder): { Light }
	B:Group("ShopBooth")
	local base = polar(52, L.ShopAngle)
	local frame = MapKit.Facing(base, V(0, 0, 0))
	B:Solid("Block", "ShopFloor", V(12, 0.5, 9), frame * CFrame.new(0, 0.25, 1.5), C.Wood, M.WoodPlanks)
	B:Solid("Block", "Counter", V(10, 3.2, 2.2), frame * CFrame.new(0, 2.1, -1.6), C.Wood, M.WoodPlanks)
	B:Deco("Block", "CounterTop", V(10.6, 0.35, 2.8), frame * CFrame.new(0, 3.85, -1.6), C.WoodDark, M.Wood)
	B:Deco("Block", "CounterPanel", V(9, 2, 0.15), frame * CFrame.new(0, 2.2, -2.75), rgb(196, 64, 70), M.Fabric, { Shadow = false })
	for _, sx in { -5.4, 5.4 } do
		for _, sz in { -2.6, 5.2 } do
			B:Solid("Block", "ShopPost", V(0.6, 10, 0.6), frame * CFrame.new(sx, 5, sz), C.WoodDark, M.Wood)
		end
	end
	-- back shelves with goods
	B:Solid("Block", "Shelf", V(10, 6, 1.4), frame * CFrame.new(0, 3.5, 5), C.WoodDark, M.Wood)
	local goods = { rgb(255, 80, 90), rgb(90, 200, 255), rgb(255, 200, 70), rgb(140, 230, 120), rgb(200, 120, 255), rgb(255, 150, 60) }
	local rng = B.Rng
	for row = 0, 1 do
		B:Deco("Block", "ShelfBoard", V(9.6, 0.25, 1.6), frame * CFrame.new(0, 3.2 + row * 2.2, 4.3), C.Wood, M.Wood, { Shadow = false })
		for k = 0, 5 do
			local x = -4 + k * 1.6
			local color = goods[(k + row * 2) % #goods + 1]
			if (k + row) % 3 == 0 then
				B:Heart("Decor", "Good", frame * CFrame.new(x, 4.1 + row * 2.2, 4.2) * CFrame.Angles(0, math.pi, 0), 0.7, 0.3, color, M.Neon, { Shadow = false })
			else
				B:Deco("Cylinder", "Jar", V(1.1, 0.9, 0.9), frame * CFrame.new(x, 3.9 + row * 2.2, 4.3) * CFrame.Angles(0, 0, math.rad(90)), color, M.Glass, { Transparency = 0.25, Shadow = false })
				B:Deco("Cylinder", "JarLid", V(0.25, 0.95, 0.95), frame * CFrame.new(x, 4.5 + row * 2.2, 4.3) * CFrame.Angles(0, 0, math.rad(90)), C.WoodDark, M.Wood, { Shadow = false })
			end
		end
	end
	-- striped awning sloping towards the customers
	local stripes = 8
	for k = 0, stripes - 1 do
		local x = -6 + (k + 0.5) * 12 / stripes
		local color = if k % 2 == 0 then rgb(214, 62, 72) else rgb(250, 240, 222)
		B:Deco("Block", "Awning", V(12 / stripes + 0.02, 0.2, 9.6), frame * CFrame.new(x, 10.2, 1.2) * CFrame.Angles(math.rad(-14), 0, 0), color, M.Fabric)
		-- scalloped edge
		B:Deco("Cylinder", "AwningScallop", V(0.2, 12 / stripes, 12 / stripes), frame * CFrame.new(x, 9.0, -3.5) * CFrame.Angles(0, math.rad(90), 0), color, M.Fabric, { Shadow = false })
	end
	local sign = B:Deco("Block", "ShopSign", V(8, 1.8, 0.4), frame * CFrame.new(0, 11.9, -2.2), C.WoodDark, M.Wood)
	B:Text(sign, Enum.NormalId.Front, { Key = "maps.lobby.shop.sign", Color = rgb(255, 222, 140), Font = "Merriweather", Pixels = 60, Glow = true })
	local l = B:Lamp("ShopLantern", (frame * CFrame.new(4.2, 9.2, -3.2)).Position, {
		Style = "Lantern",
		Drop = 1.2,
		Size = 0.9,
		LightColor = C.Lamp,
		Brightness = 1.4,
		Range = 16,
	})
	local marker = B:Marker("ShopBooth", frame * CFrame.new(0, 3, -3.2), { Size = V(8, 4, 1), Attributes = { Action = "Shop" } })
	B:Prompt(marker, { Action = "Shop", ActionKey = "maps.lobby.shop.action", ObjectKey = "maps.lobby.shop.object", Distance = 11 })
	buildShopkeeper(B, frame)
	local _ = rng
	B:Group(nil)
	return if l then { l } else {}
end

local function buildQuestBoard(B: MapKit.Builder): { Light }
	B:Group("QuestBoard")
	local base = polar(50, L.QuestAngle)
	local frame = MapKit.Facing(base, V(0, 0, 0))
	for _, sx in { -5, 5 } do
		B:Solid("Block", "QuestPost", V(0.8, 9, 0.8), frame * CFrame.new(sx, 4.5, 0), C.WoodDark, M.Wood)
	end
	B:Solid("Block", "QuestFrame", V(10.6, 6.6, 0.7), frame * CFrame.new(0, 5.4, 0), C.WoodDark, M.Wood)
	B:Deco("Block", "Cork", V(9.6, 5.6, 0.2), frame * CFrame.new(0, 5.4, -0.4), C.Cork, M.Fabric, { Shadow = false })
	local roofA = (frame * CFrame.new(-6.2, 8.9, 0)).Position
	local roofB = (frame * CFrame.new(6.2, 8.9, 0)).Position
	local roofT = (frame * CFrame.new(0, 10.6, 0)).Position
	B:Triangle("Decor", "QuestGable", roofA, roofB, roofT, 1.6, rgb(170, 70, 60), M.RoofShingles)
	-- pinned notes
	local rng = B.Rng
	local paper = { rgb(250, 244, 226), rgb(255, 236, 170), rgb(255, 214, 220), rgb(214, 236, 255) }
	for row = 0, 1 do
		for col = 0, 3 do
			local x = -3.6 + col * 2.4 + rng:Number(-0.3, 0.3)
			local y = 4.2 + row * 2.4 + rng:Number(-0.25, 0.25)
			local note = frame * CFrame.new(x, y, -0.55) * CFrame.Angles(0, 0, math.rad(rng:Number(-9, 9)))
			B:Deco("Block", "Note", V(1.7, 2, 0.06), note, paper[rng:Integer(1, #paper)], M.SmoothPlastic, { Shadow = false })
			B:Deco("Ball", "Pin", V(0.28, 0.28, 0.28), note * CFrame.new(0, 0.75, -0.08), rgb(220, 40, 50), M.SmoothPlastic, { Shadow = false })
			for line = 0, 2 do
				B:Deco("Block", "Ink", V(1.1 - line * 0.2, 0.08, 0.02), note * CFrame.new(-0.05, 0.2 - line * 0.4, -0.04), rgb(90, 80, 110), M.SmoothPlastic, { Shadow = false })
			end
		end
	end
	local sign = B:Deco("Block", "QuestSign", V(7.4, 1.4, 0.3), frame * CFrame.new(0, 1.6, -0.45), C.Wood, M.WoodPlanks)
	B:Text(sign, Enum.NormalId.Front, { Key = "maps.lobby.quests.sign", Color = rgb(60, 36, 20), Font = "Merriweather", Pixels = 60 })
	local l = B:Lamp("QuestLamp", (frame * CFrame.new(6.6, 0, -1.4)).Position, {
		Style = "Post",
		Height = 8,
		Metal = rgb(60, 52, 48),
		LightColor = C.Lamp,
		Brightness = 1.3,
		Range = 16,
	})
	local marker = B:Marker("QuestBoard", frame * CFrame.new(0, 5.4, -0.7), { Size = V(9.6, 5.6, 0.2), Attributes = { Action = "Quests" } })
	B:Prompt(marker, { Action = "Quests", ActionKey = "maps.lobby.quests.action", ObjectKey = "maps.lobby.quests.object", Distance = 11 })
	B:Group(nil)
	return if l then { l } else {}
end

local function buildPortal(B: MapKit.Builder): { Light }
	B:Group("PracticePortal")
	local lights: { Light } = {}
	local base = polar(60, L.PortalAngle)
	local frame = MapKit.Facing(base, V(0, 0, 0)) -- faces the plaza
	B:Solid("Block", "PortalDais", V(18, 1, 8), frame * CFrame.new(0, 0.5, 0.5), C.StoneMid, M.Limestone)
	B:Solid("Block", "PortalStep", V(14, 0.5, 2), frame * CFrame.new(0, 0.25, -4.4), C.Stone, M.Limestone)
	local ringCF = frame * CFrame.new(0, 9, 0.5)
	B:ArcRing("Geometry", "PortalRing", ringCF, 7.6, 0, 360, 28, 1.8, 2.2, C.StoneMid, M.Limestone)
	B:ArcRing("Decor", "PortalGold", ringCF * CFrame.new(0, 0, -1.15), 6.55, 0, 360, 28, 0.35, 0.3, C.Gold, M.Metal, { Shadow = false })
	B:Star("Decor", "PortalKey", ringCF * CFrame.new(0, 8.7, -1.2), 1.1, 0.46, 0.3, C.Star, M.Neon, { Shadow = false })
	-- swirling surface (layered discs facing the plaza; the client spins them)
	local swirl = Instance.new("Model")
	swirl.Name = "PortalSwirl"
	local colors = { C.Portal, rgb(90, 140, 255), C.PortalCore }
	local disc: BasePart? = nil
	for i, color in colors do
		local d = 12.6 - (i - 1) * 3.6
		local part = B:Part("Decor", "Cylinder", "Swirl" .. i, V(0.1, d, d), ringCF * CFrame.new(0, 0, -0.2 * i) * CFrame.Angles(0, math.rad(90), 0), color, M.Neon, {
			Shadow = false,
			Transparency = 0.15 + i * 0.1,
			Parent = swirl,
		})
		if i == 1 then
			disc = part
		end
	end
	for k = 0, 5 do
		local a = math.rad(k * 60)
		B:Deco("Block", "SwirlArm" .. k, V(0.5, 4.6, 0.12), ringCF * CFrame.new(math.cos(a) * 3, math.sin(a) * 3, -0.75) * CFrame.Angles(0, 0, a + math.rad(30)), rgb(220, 240, 255), M.Neon, {
			Shadow = false,
			Transparency = 0.35,
			Parent = swirl,
		})
	end
	if disc then
		swirl.PrimaryPart = disc
		B:Particles(disc, "Sparkles", { Rate = 8, Color = rgb(200, 220, 255), Size = 0.7 })
	end
	swirl.Parent = B:_folder("Decor")
	table.insert(lights, B:Light("Point", (ringCF * CFrame.new(0, 0, -3)).Position, { Name = "PortalLight", Brightness = 1.8, Range = 24, Color = rgb(150, 130, 255) }))
	-- obelisks with braziers
	for _, sx in { -10.5, 10.5 } do
		local p = (frame * CFrame.new(sx, 0, 0.5)).Position
		B:Solid("Block", "Obelisk", V(2.2, 8, 2.2), CFrame.new(p + V(0, 5, 0)), C.StoneMid, M.Limestone)
		B:Cone("Decor", "ObeliskTip", p + V(0, 9, 0), 2.4, 1.55, 4, C.Gold, M.Metal, { Phase = 45 })
	end
	local sign = B:Deco("Block", "PortalSign", V(9, 1.8, 0.5), ringCF * CFrame.new(0, 10.6, 0), C.StoneMid, M.Limestone)
	B:Text(sign, Enum.NormalId.Front, { Key = "maps.lobby.portal.sign", Color = rgb(120, 96, 220), Font = "Merriweather", Pixels = 60 })
	local marker = B:Marker("PracticePortal", ringCF * CFrame.new(0, -3, -1.4), { Size = V(8, 8, 1), Attributes = { Action = "Practice" } })
	B:Prompt(marker, { Action = "Practice", ActionKey = "maps.lobby.portal.action", ObjectKey = "maps.lobby.portal.object", Distance = 12, Hold = 0.4 })
	-- patch-notes scroll (north-east lookout)
	local nbase = polar(48, L.NotesAngle)
	local nframe = MapKit.Facing(nbase, V(0, 0, 0))
	for _, sx in { -3.4, 3.4 } do
		B:Solid("Block", "NotesPost", V(0.6, 11, 0.6), nframe * CFrame.new(sx, 5.5, 0.3), C.WoodDark, M.Wood)
	end
	B:Deco("Block", "NotesPaper", V(6.4, 8.4, 0.15), nframe * CFrame.new(0, 6, 0), C.Parchment, M.Fabric)
	for _, y in { 1.6, 10.4 } do
		B:Deco("Cylinder", "NotesRoll", V(7.4, 0.8, 0.8), nframe * CFrame.new(0, y, 0), C.WoodDark, M.Wood)
	end
	local notes = B:Marker("PatchNotes", nframe * CFrame.new(0, 6, -0.12), { Size = V(6.2, 8.2, 0.05) })
	B:Text(notes, Enum.NormalId.Front, { Key = "maps.lobby.notes.title", Color = rgb(150, 40, 40), Font = "Merriweather", Pixels = 50, Height = 0.12, Width = 0.9 }).Name = "Title"
	local body = B:Text(notes, Enum.NormalId.Front, { Key = "maps.lobby.notes.body", Color = rgb(60, 44, 30), Font = "Merriweather", Pixels = 50, Height = 0.78, Width = 0.88 })
	body.Name = "Body"
	local bodyLabel = body:FindFirstChild("Label") :: TextLabel?
	if bodyLabel then
		bodyLabel.Position = UDim2.fromScale(0.5, 0.56)
		bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
		bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	end
	local titleGui = notes:FindFirstChild("Title")
	local titleLabel = titleGui and titleGui:FindFirstChild("Label") :: TextLabel?
	if titleLabel then
		titleLabel.Position = UDim2.fromScale(0.5, 0.09)
	end
	B:Group(nil)
	return lights
end

local function buildTraining(B: MapKit.Builder): ({ CFrame }, { Light })
	B:Group("Training")
	-- yard frame: origin at the yard centre, LookVector (-Z) towards the plaza; the entrance is the -Z side
	local center = polar(54, L.TrainingAngle)
	local yard = MapKit.Facing(center, V(0, 0, 0))
	local function at(x: number, z: number): Vector3
		return (yard * CFrame.new(x, 0, z)).Position
	end
	B:Deco("Block", "Yard", V(22, 0.12, 30), yard * CFrame.new(0, -0.01, 0), rgb(222, 196, 150), M.Sand, { Shadow = false })
	B:Fence("YardFence", { at(-11, -15), at(-11, 15), at(11, 15), at(11, -15) }, { Color = C.Wood, Height = 3 })
	B:Fence("YardFenceL", { at(-11, -15), at(-4.5, -15) }, { Color = C.Wood, Height = 3 })
	B:Fence("YardFenceR", { at(4.5, -15), at(11, -15) }, { Color = C.Wood, Height = 3 })
	-- entrance arch with the sign
	for _, sx in { -4.5, 4.5 } do
		B:Solid("Block", "ArchPost", V(1, 9, 1), yard * CFrame.new(sx, 4.5, -15), C.WoodDark, M.Wood)
	end
	B:Solid("Block", "ArchBeam", V(11, 1, 1.2), yard * CFrame.new(0, 9.2, -15), C.WoodDark, M.Wood)
	local sign = B:Deco("Block", "TrainingSign", V(10, 1.8, 0.4), yard * CFrame.new(0, 8, -15.5), C.Wood, M.WoodPlanks)
	B:Text(sign, Enum.NormalId.Front, { Key = "maps.lobby.training.sign", Color = rgb(60, 36, 20), Font = "Merriweather", Pixels = 50 })
	-- dummy spots: a row across the yard, facing the entrance
	local spots: { CFrame } = {}
	for i = 1, 5 do
		local p = at(-8 + (i - 1) * 4, 4)
		local cf = MapKit.Facing(p, at(-8 + (i - 1) * 4, -10))
		B:Disc("Decor", "DummyPad" .. i, p + V(0, 0.1, 0), 3.4, 0.12, C.WoodDark, M.WoodPlanks, { Shadow = false })
		B:Ring("Decor", "DummyPadRing" .. i, p + V(0, 0.18, 0), 1.6, 0.25, 0.06, 12, C.Gold, M.Metal, { Shadow = false })
		B:Marker("DummySpot_" .. i, cf + V(0, 0.5, 0), { Group = "DummySpots", Attributes = { Index = i } })
		table.insert(spots, cf)
	end
	-- targets on the back fence, a bone rack and hay
	for i = 0, 2 do
		local t = yard * CFrame.new(-6 + i * 6, 3.2, 14.6) -- faces the entrance (-Z)
		for r, color in { rgb(250, 244, 226), rgb(220, 50, 60), rgb(250, 244, 226), rgb(220, 50, 60) } do
			local d = 3.4 - (r - 1) * 0.8
			B:Part("Decor", "Cylinder", "Target", V(0.15, d, d), t * CFrame.new(0, 0, -0.1 * r) * CFrame.Angles(0, math.rad(90), 0), color, M.Fabric, { Shadow = false })
		end
	end
	B:Solid("Block", "Rack", V(5, 3, 1), yard * CFrame.new(-8, 1.5, 12.5), C.WoodDark, M.Wood)
	for k = 0, 2 do
		B:Bones("RackBone" .. k, yard * CFrame.new(-9.5 + k * 1.5, 2.6, 11.8) * CFrame.Angles(0, 0, math.rad(80)), { Length = 3.2, Thickness = 0.28 })
	end
	for _, xz in { { 8, 11 }, { -8, -11 } } do
		B:Deco("Ellipsoid", "Hay", V(3.4, 2.6, 2.4), yard * CFrame.new(xz[1], 1.1, xz[2]), rgb(226, 190, 100), M.Fabric)
	end
	local lights: { Light } = {}
	local l = B:Lamp("YardLamp", at(7.5, -12.5), { Style = "Post", Height = 9, Metal = rgb(60, 52, 48), LightColor = C.Lamp, Brightness = 1.3, Range = 22 })
	if l then
		table.insert(lights, l)
	end
	B:Group(nil)
	return spots, lights
end

local function buildPathsAndGardens(B: MapKit.Builder)
	B:Group("Paths")
	local function path(a: Vector3, b: Vector3, width: number)
		local delta = b - a
		local mid = (a + b) / 2
		B:Deco("Block", "Path", V(width, 0.1, delta.Magnitude), MapKit.Facing(V(mid.X, 0.045, mid.Z), V(b.X, 0.045, b.Z)), C.Cobble, M.Cobblestone, { Shadow = false })
	end
	path(polar(L.PlazaR - 1, L.ShopAngle), polar(47, L.ShopAngle), 6)
	path(polar(L.PlazaR - 1, L.QuestAngle), polar(46, L.QuestAngle), 6)
	path(polar(L.PlazaR - 1, L.PortalAngle), polar(54, L.PortalAngle), 7)
	path(polar(L.PlazaR - 1, L.TrainingAngle), polar(39, L.TrainingAngle), 7)
	path(polar(L.PlazaR - 1, L.BoardsAngle), polar(51, L.BoardsAngle), 7)
	path(polar(L.PlazaR - 1, 270), V(0, 0, L.StageZ + 17), 7)
	path(polar(L.PlazaR - 1, L.NotesAngle), polar(44, L.NotesAngle), 5)
	B:Group("Gardens")
	local rng = B.Rng
	-- blossom trees around the rim (skipping the paths)
	local angles = {}
	for k = 0, 6 do
		table.insert(angles, L.SoulPhase + k * GAP + (if k % 2 == 0 then 6 else -6))
	end
	for _, extra in { 236, 330, 345 } do
		table.insert(angles, extra)
	end
	for i, a in angles do
		local r = rng:Number(60, 66)
		B:Tree("Tree" .. i, polar(r, a), rng:Number(12, 16), {
			Leaf = if i % 3 == 0 then rgb(150, 190, 96) else rgb(112, 168, 84),
			Blossom = if i % 2 == 0 then rgb(255, 186, 214) else rgb(255, 236, 160),
			Blobs = 4,
		})
	end
	-- flower beds
	local flowerColors = { rgb(255, 120, 150), rgb(255, 214, 90), rgb(170, 140, 255), rgb(255, 250, 240), rgb(255, 150, 80) }
	for i = 1, 7 do
		local a = L.SoulPhase + (i - 1) * GAP
		local center = polar(42, a)
		B:Disc("Decor", "Bed" .. i, center + V(0, 0.15, 0), 6.5, 0.3, rgb(110, 78, 56), M.Ground, { Shadow = false })
		B:Ring("Decor", "BedRim" .. i, center + V(0, 0.3, 0), 3.3, 0.4, 0.5, 14, C.StoneMid, M.Limestone, { Shadow = false })
		for k = 1, 9 do
			local fx, fz = rng:InCircle(2.5)
			local p = center + V(fx, 0.75, fz)
			B:Deco("Ball", "Flower", V(0.7, 0.7, 0.7), CFrame.new(p), flowerColors[rng:Integer(1, #flowerColors)], M.SmoothPlastic, { Shadow = false })
			B:Deco("Ball", "Leaf", V(0.9, 0.5, 0.9), CFrame.new(p - V(0, 0.35, 0)), C.GrassDark, M.Grass, { Shadow = false })
		end
	end
	-- low hedges curving behind the SOUL podiums (between the destinations)
	for k = 0, 6 do
		local a = L.SoulPhase + k * GAP
		for j = -1, 1 do
			local p = polar(47.5, a + j * 7)
			B:Deco("Ellipsoid", "Hedge", V(6.5, 3, 3.4), MapKit.Facing(p, V(0, 0, 0)) * CFrame.new(0, 1.2, 0), if j == 0 then C.GrassDark else rgb(104, 152, 76), M.LeafyGrass)
		end
	end
	-- mossy rocks near the rim
	for i = 1, 8 do
		local a = rng:Number(0, 360)
		local r = rng:Number(66, 71)
		B:Rock("Rock" .. i, polar(r, a), rng:Number(2.2, 4.2), { Color = rgb(150, 140, 126), Material = M.Slate, Collide = false })
	end
	-- lily pond with a tiny arched bridge
	local pond = polar(60, 300)
	B:Disc("Decor", "Pond", pond + V(0, 0.06, 0), 16, 0.1, rgb(90, 170, 210), M.Glass, { Transparency = 0.15, Shadow = false, Reflectance = 0.3 })
	B:Ring("Decor", "PondRim", pond + V(0, 0.2, 0), 8.2, 1.2, 0.4, 20, C.StoneMid, M.Limestone, { Shadow = false })
	for i = 1, 5 do
		local lx, lz = rng:InCircle(5.5)
		B:Disc("Decor", "LilyPad", pond + V(lx, 0.13, lz), rng:Number(1.2, 2), 0.06, rgb(96, 168, 80), M.SmoothPlastic, { Shadow = false })
		if i % 2 == 1 then
			B:Deco("Ball", "Lily", V(0.6, 0.6, 0.6), CFrame.new(pond + V(lx, 0.4, lz)), rgb(255, 196, 220), M.SmoothPlastic, { Shadow = false })
		end
	end
	-- SOUL pennants on poles along the portal path
	local soulColors = { rgb(255, 30, 40), rgb(66, 252, 255), rgb(252, 166, 0), rgb(0, 60, 255), rgb(213, 53, 217), rgb(0, 192, 0), rgb(255, 255, 0) }
	for i, color in soulColors do
		local side = if i % 2 == 0 then -1 else 1
		local along = polar(L.PlazaR + 5 + (i - 1) * 4, L.PortalAngle)
		local perp = polar(1, L.PortalAngle + 90)
		local p = along + perp * (side * 5.2)
		B:Solid("Cylinder", "PennantPole", V(9, 0.3, 0.3), CFrame.new(p + V(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(70, 60, 54), M.Metal)
		local flag = CFrame.new(p + V(0, 8.6, 0)) * CFrame.Angles(0, -math.pi / 2, 0) -- flies with the wind (+X)
		B:Triangle("Decor", "Pennant", flag * V(0, 0.6, 0), flag * V(0, -1.2, 0), flag * V(0, -0.3, -2.6), 0.08, color, M.Fabric)
	end
	B:Group(nil)
end

local function buildSky(B: MapKit.Builder)
	B:Group("Sky")
	local rng = B.Rng
	for i = 1, 14 do
		local p = polar(rng:Number(10, 44), rng:Number(0, 360), rng:Number(16, 30))
		local color = if i % 3 == 0 then rgb(255, 170, 190) else rgb(255, 190, 110)
		local lantern = B:Deco("Ellipsoid", "SkyLantern" .. i, V(1.4, 1.9, 1.4), CFrame.new(p), color, M.Neon, { Shadow = false, Transparency = 0.1 })
		lantern:SetAttribute("Bob", rng:Number(0, 6.28))
		B:Deco("Cylinder", "SkyLanternCap" .. i, V(0.25, 1.1, 1.1), CFrame.new(p + V(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(120, 70, 50), M.Wood, { Shadow = false })
	end
	B:Group(nil)
end

-- MapInfo -------------------------------------------------------------------------------------------------

function Lobby.Build(seed: number?): MapInfo
	local B = MapKit.new("Lobby", { Seed = seed or 1 })
	local kits = kitList()
	buildIsland(B)
	local lights = 0
	lights += #buildPlaza(B)
	local spawns = buildSpawns(B)
	lights += #buildSoulRing(B, kits)
	lights += #buildJudgesStage(B, kits)
	lights += #buildBoards(B)
	lights += #buildShop(B)
	lights += #buildQuestBoard(B)
	lights += #buildPortal(B)
	local dummySpots, trainingLights = buildTraining(B)
	lights += #trainingLights
	buildPathsAndGardens(B)
	buildSky(B)
	local center = V(0, 0, 0)
	local monsterSpawn = B:SpawnPoint("Monster", 1, MapKit.Facing(V(0, 1.2, L.StageZ + 9), V(0, 1.2, 0)))
	B:Marker("Center", CFrame.new(center + V(0, 0.5, 0)))
	B:Marker("MenuCamera", MapKit.LookAt(V(8, 12, 46), V(-2, 7.5, -8)))
	B:KillFloor(L.KillY, 400)
	local _ = lights
	B:Finish(Lobby.Id)
	return {
		Id = Lobby.Id,
		Model = B.Model,
		HumanSpawns = spawns,
		MonsterSpawn = monsterSpawn,
		SavePoints = {},
		Center = center,
		Radius = L.IslandR - 2,
		KillY = L.KillY,
		IntroPath = {
			MapKit.LookAt(V(0, 34, 86), V(0, 6, 0)),
			MapKit.LookAt(V(62, 22, 18), V(0, 8, 0)),
			MapKit.LookAt(V(16, 14, -36), V(0, 6, L.StageZ)),
			MapKit.LookAt(V(-44, 16, 20), V(0, 8, 0)),
		},
		Preset = Lobby.Preset,
		FinalPreset = Lobby.FinalPreset,
		Music = Lobby.Music,
		DummySpawns = dummySpots,
	}
end

return Lobby
