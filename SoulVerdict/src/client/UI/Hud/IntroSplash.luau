--!strict
-- Hud/IntroSplash: the VS screen shown during the Intro phase (RoundEvent "Intro"): the monster portrait (a
-- ViewportFrame with the kit rig built by Rigs/RigBuilder; offline previews draw a vector skull instead), kit
-- name + title in the kit colour vs the human team cards (SOUL heart, name, class, LV), the map name, the
-- Harmony bonus and a 3-2-1 countdown to the fight.
--   IntroSplash.Create(theme, deps) -> { Root, Play(data, source?), Update(snapshot), Tick(now), Destroy }
--   Play(data): RoundEvent "Intro" payload {mapId, monster = {userId, kitId, name, model, isBot}, humans = {...},
--               harmony, practice}; `source` (Hud/Data) turns models into Units (LV, skin).
-- Previews use snapshot.Intro = { MapId, Monster: Unit, Humans: {Unit}, Count }.
local Style = require(script.Parent.Style)
local UIKit = require(script.Parent.Parent.UIKit)
local Motion = require(script.Parent.Parent.Motion)

local IntroSplash = {}

local function mapName(mapId: string?): string
	local registry = Style.Require("Maps", "Registry")
	if mapId and registry then
		local ok, info = pcall(registry.Info, mapId)
		if ok and info then
			return Style.Pick(info.Name)
		end
	end
	return mapId or ""
end

function IntroSplash.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "IntroSplash")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local live = type(deps) == "table" and deps.Live == true
	local k = if phone then 0.56 else 1 -- size factor

	local backdrop = Style.Frame({
		Name = "Backdrop",
		BackgroundTransparency = if battle then 0.03 else 0,
		BackgroundColor3 = if battle then Style.BLACK else Style.WHITE,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local backGrad: UIGradient? = nil
	if not battle then
		backGrad = Style.Gradient(backdrop, Style.CSeq(Color3.fromRGB(8, 10, 22), Color3.fromRGB(6, 6, 12)), nil, 0)
	end
	-- diagonal monster-colour slash (Modern) / white rule (Battle)
	local slash = Style.Frame({
		Name = "Slash",
		BackgroundTransparency = if battle then 1 else 0.25,
		BackgroundColor3 = Style.WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.27, 0.5),
		Size = UDim2.new(0.62, 0, 1.6, 0),
		Rotation = 14,
		Parent = root,
	})
	local slashGrad = Style.Gradient(
		slash,
		Style.CSeq(Style.WHITE, Style.WHITE),
		Style.Seq({ { 0, 0.15 }, { 0.75, 0.55 }, { 1, 1 } }),
		0
	)

	local mapLabel = Style.Text(skin, {
		Name = "Map",
		Text = "",
		Role = "Title",
		TextSize = math.floor((if battle then 18 else 22) * (if phone then 0.8 else 1)),
		Upper = true,
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, math.floor(34 * k)),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = root,
	})

	-- monster card -----------------------------------------------------------------------------------------
	local mW, mH = math.floor(500 * k), math.floor(560 * k)
	local monsterBox = Style.Box(skin, {
		Name = "Monster",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, -math.floor(110 * k) - mW, 0.5, math.floor(10 * k)),
		Size = UDim2.fromOffset(mW, mH),
		Stroke = if battle then 5 else nil,
		Transparency = if battle then 0 else 0.35,
		Parent = root,
	})
	local portrait = Style.Frame({
		Name = "Portrait",
		Position = UDim2.fromOffset(math.floor(14 * k), math.floor(14 * k)),
		Size = UDim2.new(1, -math.floor(28 * k), 0, math.floor(352 * k)),
		ClipsDescendants = true,
		Parent = monsterBox,
	})
	local monsterKitLabel = Style.Text(skin, {
		Name = "KitName",
		Text = "",
		Role = "Title",
		TextSize = math.floor((if battle then 38 else 52) * k),
		X = "Center",
		Position = UDim2.fromOffset(0, math.floor(378 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(56 * k)),
		Parent = monsterBox,
	})
	local monsterTitle = Style.Text(skin, {
		Name = "Title",
		Text = "",
		TextSize = math.floor((if battle then 16 else 20) * k),
		X = "Center",
		Position = UDim2.fromOffset(0, math.floor(440 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(26 * k)),
		Parent = monsterBox,
	})
	local monsterPlayer = Style.Text(skin, {
		Name = "Player",
		Text = "",
		TextSize = math.floor((if battle then 11 else 14) * k),
		Color = C.Dim,
		X = "Center",
		Position = UDim2.fromOffset(0, math.floor(486 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(20 * k)),
		Parent = monsterBox,
	})
	Style.Text(skin, {
		Name = "Role",
		Text = Style.L("hud.intro.monster"),
		TextSize = math.floor(skin.Size.Small * (if phone then 0.9 else 1)),
		Color = C.Dim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 0, -8),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = monsterBox,
	})

	-- VS ---------------------------------------------------------------------------------------------------
	local vs = Style.Frame({
		Name = "VS",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.floor(150 * k), math.floor(150 * k)),
		Parent = root,
	})
	if not battle then
		local diamond = Style.Frame({
			Name = "Diamond",
			BackgroundTransparency = 0.1,
			BackgroundColor3 = Color3.fromRGB(14, 16, 28),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.68, 0.68),
			Rotation = 45,
			Parent = vs,
		})
		Style.Corner(diamond, UDim.new(0, 10))
		Style.Stroke(diamond, C.Accent, 3, 0)
	end
	Style.Text(skin, {
		Name = "Text",
		Text = Style.L("hud.intro.vs"),
		Role = "Title",
		TextSize = math.floor((if battle then 56 else 50) * k),
		X = "Center",
		Stroke = if battle then 4 else 2,
		Size = UDim2.fromScale(1, 1),
		Parent = vs,
	})
	local vsHeart = Style.Heart(C.SoulRed, math.floor(30 * k), "Whole")
	vsHeart.Position = UDim2.new(0.5, 0, 1, math.floor(12 * k))
	vsHeart.Parent = vs

	-- human cards ------------------------------------------------------------------------------------------
	local hX = math.floor(110 * k)
	local humansCol = Style.Frame({
		Name = "Humans",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, hX, 0.5, math.floor(10 * k)),
		Size = UDim2.fromOffset(math.floor(520 * k), mH),
		Parent = root,
	})
	Style.Text(skin, {
		Name = "Role",
		Text = Style.L("hud.intro.humans"),
		TextSize = math.floor(skin.Size.Small * (if phone then 0.9 else 1)),
		Color = C.Dim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 0, -8),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = humansCol,
	})
	local cards = Style.Frame({ Name = "Cards", Size = UDim2.fromScale(1, 1), Parent = humansCol })
	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Padding = UDim.new(0, math.floor(14 * k))
	cardList.Parent = cards
	local harmonyLabel = Style.Text(skin, {
		Name = "Harmony",
		Text = "",
		TextSize = math.floor((if battle then 11 else 14) * k),
		Color = C.Good,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1000,
		Parent = cards,
	})

	-- countdown --------------------------------------------------------------------------------------------
	local count = Style.Box(skin, {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -math.floor(26 * k)),
		Size = UDim2.fromOffset(math.floor(250 * k), math.floor(82 * k)),
		Stroke = if battle then 4 else nil,
		Corner = UDim.new(0.5, 0),
		Parent = root,
	})
	Style.Text(skin, {
		Name = "Ready",
		Text = Style.L("hud.intro.ready"),
		TextSize = math.floor((if battle then 11 else 13) * k),
		Color = C.Dim,
		X = "Center",
		Stroke = false,
		Position = UDim2.fromOffset(0, math.floor(8 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(16 * k)),
		Parent = count,
	})
	local countNumber = Style.Text(skin, {
		Name = "Number",
		Text = "3",
		Role = "Number",
		TextSize = math.floor((if battle then 36 else 44) * k),
		Color = C.Gold,
		X = "Center",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -math.floor(6 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(48 * k)),
		Parent = count,
	})

	local viewport: any = nil
	local endsAt = 0
	local lastCount = -1

	local function portraitFallback(kitColor: Color3)
		Style.Glow({
			Name = "Glow",
			Color = kitColor,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(math.floor(170 * k), math.floor(170 * k)),
			Spread = math.floor(60 * k),
			Strength = 0.55,
			Corner = UDim.new(0.5, 0),
			Parent = portrait,
		})
		local skull = Style.Icon("Skull", kitColor:Lerp(Style.WHITE, 0.1), math.floor(230 * k))
		skull.AnchorPoint = Vector2.new(0.5, 0.5)
		skull.Position = UDim2.fromScale(0.5, 0.52)
		skull.Parent = portrait
	end

	local function setPortrait(kitId: string, skinId: string?, kitColor: Color3)
		portrait:ClearAllChildren()
		viewport = nil
		local ground = Style.Frame({
			Name = "Ground",
			BackgroundTransparency = 0.55,
			BackgroundColor3 = kitColor,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.94),
			Size = UDim2.fromScale(0.62, 0.07),
			Parent = portrait,
		})
		Style.Corner(ground, UDim.new(0.5, 0))
		if not live then
			portraitFallback(kitColor)
			return
		end
		local ok = pcall(function()
			local kit = Style.Kit(kitId)
			local RigBuilder = Style.Require("Rigs", "RigBuilder")
			local model: Model = RigBuilder.Build(kit.Rig, { Skin = skinId })
			local cf, size = model:GetBoundingBox()
			local h = size.Y
			local target = cf.Position + Vector3.new(0, h * 0.18, 0)
			local eye = target + Vector3.new(h * 0.18, h * 0.06, -h * 1.45)
			viewport = UIKit.Viewport(theme, {
				Name = "Viewport",
				Color = kitColor,
				FieldOfView = 34,
				CameraCFrame = CFrame.lookAt(eye, target),
				LightDirection = Vector3.new(-0.4, -0.7, 0.6),
				Size = UDim2.fromScale(1, 1),
			})
			viewport.Root.BackgroundTransparency = 1
			viewport.SetModel(model)
			viewport.Root.Parent = portrait
		end)
		if not ok then
			portraitFallback(kitColor)
		end
	end

	local function render(intro: { [string]: any })
		local monster = intro.Monster or {}
		local kit = Style.Kit(monster.KitId)
		local kitColor = if kit then kit.Color else C.Monster
		Style.SetText(mapLabel, (if battle then "* " else "") .. Style.Upper(skin, mapName(intro.MapId)))
		Style.SetText(
			monsterKitLabel,
			Style.Upper(skin, if kit then Style.Pick(kit.Name) else tostring(monster.Name or "?"))
		)
		Style.SetText(monsterTitle, Style.Upper(skin, if kit then Style.Pick(kit.Title) else ""))
		monsterTitle.TextColor3 = kitColor
		local who = tostring(monster.Name or "?")
		Style.SetText(monsterPlayer, Style.Upper(skin, who .. "  ·  " .. Style.L("hud.lv", monster.Level or 1)))
		slash.BackgroundColor3 = kitColor
		slashGrad.Color = Style.CSeq(kitColor, kitColor:Lerp(Style.BLACK, 0.6))
		if backGrad then
			backGrad.Color = Style.CSeq(kitColor:Lerp(Style.BLACK, 0.82), Color3.fromRGB(6, 6, 12))
		end
		setPortrait(monster.KitId or "", monster.SkinId, kitColor)
		for _, child in cards:GetChildren() do
			if child:IsA("GuiObject") and child ~= harmonyLabel then
				child:Destroy()
			end
		end
		local humans = intro.Humans or {}
		local cardH = math.floor((if #humans > 4 then 72 else 92) * k)
		local harmonySet: { [string]: boolean } = {}
		for i, u in humans do
			local hk = Style.Kit(u.KitId)
			local color = if hk then hk.Color else C.SoulRed
			harmonySet[u.KitId or "?"] = true
			local card = Style.Box(skin, {
				Name = "Card" .. i,
				Size = UDim2.new(1, 0, 0, cardH),
				Stroke = if battle then 3 else nil,
				Transparency = if battle then 0 else 0.3,
				LayoutOrder = i,
				Parent = cards,
			})
			if not battle then
				local strip = Style.Frame({
					Name = "Strip",
					BackgroundTransparency = 0,
					BackgroundColor3 = color,
					Size = UDim2.new(0, 5, 1, -16),
					Position = UDim2.fromOffset(0, 8),
					Parent = card,
				})
				Style.Corner(strip, UDim.new(0.5, 0))
			end
			local heart = Style.Heart(color, math.floor(cardH * 0.46), "Whole")
			heart.AnchorPoint = Vector2.new(0.5, 0.5)
			heart.Position = UDim2.new(0, math.floor(cardH * 0.5), 0.5, 0)
			heart.Parent = card
			Style.Text(skin, {
				Name = "Name",
				Text = if battle then Style.Upper(skin, tostring(u.Name)) else tostring(u.Name),
				Upper = false,
				Role = "Title",
				TextSize = math.floor((if battle then 16 else 22) * k),
				Scaled = true,
				Position = UDim2.new(0, cardH, 0, math.floor(cardH * 0.16)),
				Size = UDim2.new(1, -cardH - math.floor(90 * k), 0, math.floor(cardH * 0.36)),
				Parent = card,
			})
			Style.Text(skin, {
				Name = "Class",
				Text = (if hk then Style.Pick(hk.Name) .. "  ·  " .. Style.Pick(hk.Title) else ""),
				TextSize = math.floor((if battle then 10 else 14) * k),
				Color = color,
				Position = UDim2.new(0, cardH, 0, math.floor(cardH * 0.56)),
				Size = UDim2.new(1, -cardH - math.floor(90 * k), 0, math.floor(cardH * 0.28)),
				Parent = card,
			})
			Style.Text(skin, {
				Name = "LV",
				Text = Style.L("hud.lv", u.Level or 1) .. (if u.IsBot then "  " .. Style.L("hud.bot") else ""),
				TextSize = math.floor((if battle then 11 else 14) * k),
				Color = C.Dim,
				X = "Right",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -math.floor(16 * k), 0.5, 0),
				Size = UDim2.fromOffset(math.floor(90 * k), 20),
				Parent = card,
			})
			if Style.Live() then
				card.Position = UDim2.fromOffset(math.floor(60 * k), 0)
				Motion.Tween(card, {
					Time = 0.45,
					Style = Enum.EasingStyle.Quart,
					Direction = Enum.EasingDirection.Out,
					Delay = 0.12 * i,
				}, { Position = UDim2.fromOffset(0, 0) })
			end
		end
		local classes = 0
		for _ in harmonySet do
			classes += 1
		end
		local config = Style.Config()
		local per = if config then config.Human.HarmonyPerClass else 0.04
		local cap = if config then config.Human.HarmonyMax else 0.2
		local bonus = intro.Harmony or math.min(cap, per * math.max(0, classes - 1))
		if bonus > 1 then
			bonus -= 1
		end
		harmonyLabel.Visible = bonus > 0.001
		Style.SetText(harmonyLabel, Style.L("hud.intro.harmony", math.floor(bonus * 100 + 0.5)))
		if Style.Live() then
			monsterBox.Position =
				UDim2.new(0.5, -math.floor(110 * k) - mW - math.floor(80 * k), 0.5, math.floor(10 * k))
			Motion.Tween(
				monsterBox,
				{ Time = 0.55, Style = Enum.EasingStyle.Quart, Direction = Enum.EasingDirection.Out },
				{ Position = UDim2.new(0.5, -math.floor(110 * k) - mW, 0.5, math.floor(10 * k)) }
			)
		end
	end

	local function tick(now: number)
		if endsAt <= 0 then
			return
		end
		local left = math.max(0, endsAt - now)
		local n = math.ceil(left - 0.05)
		if n ~= lastCount then
			lastCount = n
			Style.SetText(countNumber, if n > 3 then Style.FormatClock(left) else tostring(math.max(1, n)))
			if Style.Live() and n <= 3 then
				countNumber.TextSize = math.floor((if battle then 50 else 60) * k)
				Motion.Tween(
					countNumber,
					{ Time = 0.3, Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out },
					{ TextSize = math.floor((if battle then 36 else 44) * k) }
				)
			end
		end
	end

	local function play(data: any, source: any?)
		data = if type(data) == "table" then data else {}
		local function toUnit(info: any): any
			if type(info) ~= "table" then
				return {}
			end
			local u = if source and info.model then source:UnitOf(info.model) else nil
			return u or { Name = info.name, KitId = info.kitId, Level = 1, IsBot = info.isBot }
		end
		local humans = {}
		for _, h in data.humans or {} do
			table.insert(humans, toUnit(h))
		end
		render({ MapId = data.mapId, Monster = toUnit(data.monster), Humans = humans, Harmony = data.harmony })
	end

	local function update(s: { [string]: any })
		endsAt = s.EndsAt or 0
		if s.Intro then
			render(s.Intro)
		end
		tick(s.Now or 0)
	end

	local initial = Style.Initial(deps, "Intro")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Play = play,
		Update = update,
		Tick = tick,
		Destroy = function()
			if viewport then
				pcall(viewport.Destroy)
			end
			root:Destroy()
		end,
	}
end

return IntroSplash
