--!strict
-- Hud/LobbyHud: everything on screen in the lobby (menu theme, UIKit components):
--   * phase banner + timer (Waiting: players needed + practice hint; Intermission: countdown to the pick;
--     a trial in progress for lobby players during a round),
--   * map vote cards (RoundState VoteOptions + RoundEvent "MapVote" counts; a click sends Request "Vote")
--     with a mini landscape painted from the map's graphics preset, vote bar, YOUR VOTE / LEADING badges,
--   * monster-chance list (Player attributes MonsterChance / RolePreference / RoundsSinceMonster pity),
--   * PRACTICE / LOADOUT / SHOP / QUESTS quick buttons (deps.UI.Open(name); PRACTICE -> deps.UI.Practice() or
--     Request "StartPractice" {side = "Human"}),
--   * the monster announcement (RoundEvent "MonsterChosen") as a centre banner.
--   Phones (layout.Phone): everything stays in the top band and the left column so the thumbstick (bottom-left) and
--   the touch cluster (bottom-right + camera-lock / emote column on the right edge) stay free: a compact banner, a
--   big PRACTICE call-to-action while waiting for players, LOADOUT / SHOP / QUESTS / MENU (re-opens the Title: touch
--   has no Menu key), a short monster-chance list and a vote panel left of the right-edge buttons.
--   LobbyHud.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), ShowChosen({Name, KitId, IsLocal}), Destroy }
--   LobbyHud.PhoneRects(canvas, top?) -> {[name] = {X, Y, W, H}}   the phone layout boxes (pure; tests check overlaps)
--       top = where the left column starts (under RoundHud's compact stats on touch phones, LobbyHud.PhoneTop)
--   LobbyHud.PhoneTop(touch, battle) -> number
local Style = require(script.Parent.Style)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)

local LobbyHud = {}

local CHOSEN_TIME = 4.5

local function presetColors(mapId: string): (Color3, Color3, Color3, boolean)
	local Presets = Style.Require("Graphics", "Presets")
	local sky, horizon, ground = Color3.fromRGB(40, 50, 90), Color3.fromRGB(200, 150, 120), Color3.fromRGB(30, 26, 30)
	local night = false
	if Presets then
		local ok, id = pcall(Presets.ForMap, mapId)
		local preset = if ok and id then Presets.Get(id) else nil
		if preset then
			local light = preset.Lighting or {}
			local atmo = preset.Atmosphere or {}
			horizon = atmo.Color or light.ColorShift_Top or horizon
			sky = (light.OutdoorAmbient or sky):Lerp(Color3.new(0, 0, 0), 0.35)
			ground = (light.Ambient or ground):Lerp(atmo.Decay or ground, 0.4)
			local clock = light.ClockTime or 14
			night = clock < 6 or clock > 19
			if night then
				sky = sky:Lerp(Color3.fromRGB(10, 12, 30), 0.5)
			end
		end
	end
	return sky, horizon, ground, night
end

local function mapMeta(mapId: string): any
	local registry = Style.Require("Maps", "Registry")
	if registry then
		local ok, info = pcall(registry.Info, mapId)
		if ok then
			return info
		end
	end
	return nil
end

-- a tiny painted landscape of the map (sky, sun/moon, horizon glow, pillars, floor)
local function mapArt(mapId: string, size: Vector2, corner: UDim): Frame
	local sky, horizon, ground, night = presetColors(mapId)
	local art = Style.Frame({
		Name = "Art",
		BackgroundTransparency = 0,
		BackgroundColor3 = Style.WHITE,
		Size = UDim2.fromOffset(size.X, size.Y),
		ClipsDescendants = true,
	})
	Style.Corner(art, corner)
	Style.Gradient(
		art,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, sky),
			ColorSequenceKeypoint.new(0.62, horizon),
			ColorSequenceKeypoint.new(0.64, ground:Lerp(horizon, 0.3)),
			ColorSequenceKeypoint.new(1, ground),
		}),
		nil,
		90
	)
	local orb = Style.Frame({
		Name = if night then "Moon" else "Sun",
		BackgroundTransparency = 0.05,
		BackgroundColor3 = if night then Color3.fromRGB(230, 236, 255) else horizon:Lerp(Style.WHITE, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.68, 0.36),
		Size = UDim2.fromOffset(size.Y * 0.2, size.Y * 0.2),
		Parent = art,
	})
	Style.Corner(orb, UDim.new(0.5, 0))
	Style.Glow({
		Name = "OrbGlow",
		Color = orb.BackgroundColor3,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = orb.Position,
		Size = orb.Size,
		Spread = size.Y * 0.14,
		Strength = 0.5,
		Corner = UDim.new(0.5, 0),
		Parent = art,
	})
	for i, p in { { 0.12, 0.5, 0.08 }, { 0.3, 0.42, 0.05 }, { 0.86, 0.55, 0.07 } } do
		Style.Frame({
			Name = "Pillar" .. i,
			BackgroundTransparency = 0,
			BackgroundColor3 = ground:Lerp(Color3.new(0, 0, 0), 0.45),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(p[1], 0.66),
			Size = UDim2.fromScale(p[3], p[2]),
			Parent = art,
		})
	end
	if night then
		for i, st in { { 0.2, 0.15 }, { 0.42, 0.08 }, { 0.55, 0.24 }, { 0.9, 0.12 } } do
			Style.Frame({
				Name = "Star" .. i,
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Style.WHITE,
				Position = UDim2.fromScale(st[1], st[2]),
				Size = UDim2.fromOffset(2, 2),
				Parent = art,
			})
		end
	end
	return art
end

-- On touch phones RoundHud's compact stats own the top-left corner: Battle rows end at y ~50, the Modern card at ~92.
function LobbyHud.PhoneTop(touch: boolean, battle: boolean): number
	if not touch then
		return 10
	end
	return if battle then 58 else 100
end

-- Phone layout boxes in design px.
function LobbyHud.PhoneRects(
	canvas: Vector2,
	top: number?
): { [string]: { X: number, Y: number, W: number, H: number } }
	local margin = 12
	local colW = 300
	local top = top or 10
	local practiceH = 46
	local cellH = 36
	local buttonsY = top + practiceH + 8
	local buttonsH = cellH * 2 + 8
	-- one-line "your monster chance" strip; everything ends well above the thumbstick corner
	local chanceY = buttonsY + buttonsH + 10
	-- right edge: camera-lock / emote column (MobileControls / EmoteWheel at canvas.X - 40, 46 wide); the vote
	-- panel ends above the touch cluster's top button (~canvas.Y - 270)
	local rightCol = canvas.X - 72
	local bannerW = math.min(440, rightCol - (margin + colW + 16) - 12)
	local bannerX = math.max(math.floor(canvas.X / 2 - bannerW / 2), margin + colW + 16)
	local voteW = 300
	return {
		Practice = { X = margin, Y = top, W = colW, H = practiceH },
		Buttons = { X = margin, Y = buttonsY, W = colW, H = buttonsH },
		Chances = { X = margin, Y = chanceY, W = colW, H = 34 },
		Banner = { X = bannerX, Y = 8, W = bannerW, H = 62 },
		Vote = { X = rightCol - 8 - voteW, Y = 76, W = voteW, H = math.min(124, canvas.Y - 276 - 76) },
	}
end

function LobbyHud.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "LobbyHud")
	local d = if type(deps) == "table" then deps else {}
	local c = theme.Colors
	local phone = layout.Phone
	local margin = if phone then 12 else 28
	local top = if phone then 96 else 150
	local initialSnap = Style.Initial(deps, "Lobby")
	local touch = (initialSnap and initialSnap.Device == "Touch") or d.Device == "Touch"
	local pr = LobbyHud.PhoneRects(layout.Canvas, LobbyHud.PhoneTop(touch, skin.Battle))
	local function place(gui: GuiObject, r: { X: number, Y: number, W: number, H: number })
		gui.AnchorPoint = Vector2.new(0, 0)
		gui.Position = UDim2.fromOffset(r.X, r.Y)
		gui.Size = UDim2.fromOffset(r.W, r.H)
	end

	-- banner ------------------------------------------------------------------------------------------------
	local bannerW = if phone then pr.Banner.W else 660
	local banner = UIKit.Panel(theme, {
		Name = "Banner",
		Variant = "Default",
		Padding = if phone then 8 else 16,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(bannerW, 108),
		Parent = root,
	})
	if phone then
		place(banner.Root, pr.Banner)
	end
	local timerW = if phone then 120 else 150
	local phaseLabel = UIKit.Label(theme, {
		Name = "Phase",
		Text = "",
		Role = "Heading",
		TextSize = if phone then math.floor(theme.TextSize.Heading * 0.66) else theme.TextSize.Heading,
		Upper = true,
		Truncate = phone,
		Size = UDim2.new(1, -timerW, 0, if phone then 22 else 36),
		Parent = banner.Content,
	})
	local timer = UIKit.Label(theme, {
		Name = "Timer",
		Text = "",
		Role = "Number",
		TextSize = if phone then 22 else 38,
		Tone = "Accent",
		XAlign = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, timerW, 0, if phone then 22 else 36),
		Parent = banner.Content,
	})
	local subLine = UIKit.Label(theme, {
		Name = "Line",
		Text = "",
		Role = "Body",
		TextSize = if phone then math.max(theme.TextSize.Caption - 1, 9) else theme.TextSize.Small,
		Tone = "Dim",
		Dialogue = theme.Id == "Classic",
		Truncate = phone,
		Wrap = not phone,
		YAlign = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		-- under the phase / timer row, full width (it used to stop 150 px short and still overflow the panel)
		Size = UDim2.new(1, 0, 0, if phone then 16 else 36),
		Parent = banner.Content,
	})

	-- quick buttons -----------------------------------------------------------------------------------------
	local function open(name: string)
		local ui = d.UI
		if name == "Practice" then
			-- (UI.Open("Practice") is not a screen: it returned nil without error and the tap did nothing)
			if type(ui) == "table" and type(ui.Practice) == "function" then
				pcall(ui.Practice, "Human")
			elseif type(d.State) == "table" and type(d.State.Request) == "function" then
				pcall(d.State.Request, "StartPractice", { side = "Human" })
			end
			return
		end
		if type(ui) == "table" and type(ui.Open) == "function" then
			pcall(ui.Open, name)
		end
	end
	local practiceButton: any = nil
	local practiceHolder: Frame? = nil
	local buttons = Style.Frame({
		Name = "Buttons",
		Position = UDim2.fromOffset(margin, top),
		Size = UDim2.fromOffset(330, 232),
		Parent = root,
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = if phone then UDim2.fromOffset(146, 36) else UDim2.fromOffset(330, 50)
	grid.CellPadding = if phone then UDim2.fromOffset(8, 8) else UDim2.fromOffset(0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = buttons
	local entries = if phone
		then {
			{ "Loadout", "Soul", "lobby.btn.loadout" },
			{ "Shop", "Shop", "lobby.btn.shop" },
			{ "Quests", "Quests", "lobby.btn.quests" },
			{ "Title", "Settings", "mobile.lobby.menu" },
		}
		else {
			{ "Practice", "Swords", "lobby.btn.practice" },
			{ "Loadout", "Soul", "lobby.btn.loadout" },
			{ "Shop", "Shop", "lobby.btn.shop" },
			{ "Quests", "Quests", "lobby.btn.quests" },
		}
	if phone then
		place(buttons, pr.Buttons)
		-- the call-to-action: one big PRACTICE button while waiting for players
		local holder = Style.Frame({ Name = "PracticeCta", Parent = root })
		place(holder, pr.Practice)
		local cta = UIKit.Button(theme, {
			Name = "Practice",
			Text = Style.L("lobby.btn.practice"),
			Icon = "Swords",
			Variant = "Primary",
			Height = pr.Practice.H,
			Width = pr.Practice.W,
			OnActivated = function()
				open("Practice")
			end,
			Parent = holder,
		})
		UIKit.Label(theme, {
			Name = "Sub",
			Text = Style.L("mobile.lobby.practice.sub"),
			Role = "Caption",
			TextSize = math.max(theme.TextSize.Caption - 1, 9),
			Tone = "Dim",
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(90, 16),
			ZIndex = 5,
			Parent = cta.Root,
		})
		practiceButton = cta
		practiceHolder = holder
	end
	for i, b in entries do
		local text = Style.L(b[3])
		local button = UIKit.Button(theme, {
			Name = b[1],
			Text = text,
			Icon = b[2],
			Variant = "Secondary",
			Height = if phone then 36 else 50,
			LayoutOrder = i,
			OnActivated = function()
				open(b[1])
			end,
			Parent = buttons,
		})
		if phone then
			-- PressStart2P / display fonts are wide: keep the 146-px cells readable
			button.Label.TextSize = math.min(button.Label.TextSize, if theme.Id == "Classic" then 11 else 15)
		end
		if b[1] == "Practice" then
			practiceButton = button
		end
	end

	-- monster chances ---------------------------------------------------------------------------------------
	-- phones: one compact strip with YOUR chance (a titled list would eat the thumbstick corner)
	local chanceTop = top + 246
	local chanceHeight = if phone then pr.Chances.H else math.min(330, layout.Canvas.Y - chanceTop - 190)
	local chancePanel = UIKit.Panel(theme, {
		Name = "Chances",
		Title = if phone then nil else Style.L("lobby.chance.title"),
		TitleIcon = if phone then nil else "Skull",
		Padding = if phone then 6 else 14,
		Position = UDim2.fromOffset(margin, chanceTop),
		Size = UDim2.fromOffset(330, chanceHeight),
		Parent = root,
	})
	local chanceRows = Style.Frame({ Name = "Rows", Size = UDim2.new(1, 0, 1, -24), Parent = chancePanel.Content })
	local chanceValue: TextLabel? = nil
	if phone then
		place(chancePanel.Root, pr.Chances)
		chanceRows.Visible = false
		local icon = Style.Icon("Skull", c.Danger, 16)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 2, 0.5, 0)
		icon.Parent = chancePanel.Content
		UIKit.Label(theme, {
			Name = "Caption",
			Text = Style.L("lobby.chance.title"),
			Role = "Caption",
			TextSize = math.max(theme.TextSize.Caption - 1, 9),
			Tone = "Dim",
			Upper = true,
			Truncate = true,
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -24 - 96, 1, 0),
			Parent = chancePanel.Content,
		})
		chanceValue = UIKit.Label(theme, {
			Name = "Value",
			Text = "",
			Role = "Number",
			TextSize = if theme.Id == "Classic" then 12 else 16,
			Tone = "Accent",
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 96, 1, 0),
			Parent = chancePanel.Content,
		})
	end
	UIKit.Label(theme, {
		Name = "Hint",
		Text = Style.L("lobby.chance.hint"),
		Role = "Caption",
		TextSize = theme.TextSize.Caption,
		Tone = "Muted",
		Wrap = true,
		Visible = not phone,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = chancePanel.Content,
	})

	-- vote ----------------------------------------------------------------------------------------------------
	-- phones: a compact panel between the banner and the touch cluster (left of the camera-lock / emote column)
	local voteW = if phone then pr.Vote.W else 400
	local cardH = if phone then 28 else 112
	local votePanel = UIKit.Panel(theme, {
		Name = "Vote",
		Title = if phone then nil else Style.L("lobby.vote.title"),
		TitleIcon = if phone then nil else "Map",
		Padding = if phone then 6 else 14,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -margin, 0, top),
		Size = UDim2.fromOffset(voteW, 60 + 3 * (cardH + 10) + 6),
		Parent = root,
	})
	local voteList: Frame
	if phone then
		place(votePanel.Root, pr.Vote)
		local headerIcon = Style.Icon("Map", c.Accent, 14)
		headerIcon.AnchorPoint = Vector2.new(0, 0.5)
		headerIcon.Position = UDim2.new(0, 2, 0, 8)
		headerIcon.Parent = votePanel.Content
		UIKit.Label(theme, {
			Name = "Header",
			Text = Style.L("lobby.vote.title"),
			Role = "Caption",
			TextSize = math.max(theme.TextSize.Caption - 1, 9),
			Tone = "Dim",
			Upper = true,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -22, 0, 16),
			Parent = votePanel.Content,
		})
		voteList = Style.Frame({
			Name = "Cards",
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 1, -20),
			Parent = votePanel.Content,
		})
	else
		voteList = Style.Frame({ Name = "Cards", Size = UDim2.fromScale(1, 1), Parent = votePanel.Content })
	end
	local vl = Instance.new("UIListLayout")
	vl.SortOrder = Enum.SortOrder.LayoutOrder
	vl.Padding = UDim.new(0, if phone then 4 else 10)
	vl.Parent = voteList

	-- chosen banner ---------------------------------------------------------------------------------------
	local chosen = UIKit.Panel(theme, {
		Name = "Chosen",
		Variant = "Default",
		Padding = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(if phone then 500 else 700, if phone then 170 else 232),
		Parent = root,
	})
	chosen.Root.Visible = false
	chosen.Root.ZIndex = 20
	local chosenIcon = Style.Frame({
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(if phone then 90 else 130, if phone then 90 else 130),
		Parent = chosen.Content,
	})
	local chosenText = Style.Frame({
		Name = "Text",
		Position = UDim2.fromOffset(if phone then 108 else 156, 0),
		Size = UDim2.new(1, if phone then -108 else -156, 1, 0),
		Parent = chosen.Content,
	})
	UIKit.Label(theme, {
		Name = "Header",
		Text = Style.L("lobby.chosen.title"),
		Role = "Caption",
		Tone = "Dim",
		Upper = true,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = chosenText,
	})
	local chosenKit = UIKit.Label(theme, {
		Name = "Kit",
		Text = "",
		Role = "Display",
		TextSize = if phone then 30 else 46,
		Upper = true,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, if phone then 38 else 58),
		Parent = chosenText,
	})
	local chosenTitle = UIKit.Label(theme, {
		Name = "Title",
		Text = "",
		Role = "Subtitle",
		Upper = true,
		Position = UDim2.fromOffset(0, if phone then 66 else 88),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = chosenText,
	})
	local chosenLine = UIKit.Label(theme, {
		Name = "Line",
		Text = "",
		Role = "Body",
		TextSize = if phone then theme.TextSize.Caption else theme.TextSize.Small,
		Wrap = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = chosenText,
	})
	local chosenUntil = 0
	local clock = 0

	local snap: { [string]: any }? = nil
	local voteKey = ""
	local chanceKey = ""
	type Card = {
		Id: string,
		Root: TextButton,
		Bar: Frame,
		Count: TextLabel,
		Mine: Frame,
		Lead: Frame,
		Stroke: UIStroke?,
	}
	local cards: { Card } = {}

	local function vote(mapId: string)
		if type(d.State) == "table" and type(d.State.Request) == "function" then
			pcall(d.State.Request, "Vote", mapId)
		end
		if type(d.OnVote) == "function" then
			pcall(d.OnVote, mapId)
		end
		if snap then
			snap.MyVote = mapId
			for _, card in cards do
				card.Mine.Visible = card.Id == mapId
			end
		end
	end

	local function buildCards(options: { string })
		for _, card in cards do
			card.Root:Destroy()
		end
		table.clear(cards)
		for i, mapId in options do
			local meta = mapMeta(mapId)
			local button = Instance.new("TextButton")
			button.Name = "Map_" .. mapId
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = c.PanelAlt
			button.BackgroundTransparency = if theme.Id == "Void" then 0.35 else 0
			button.BorderSizePixel = 0
			button.Size = UDim2.new(1, 0, 0, cardH)
			button.LayoutOrder = i
			Style.Corner(button, theme.CornerRadius)
			local stroke = Style.Stroke(
				button,
				c.StrokeDim,
				if theme.Id == "Classic" then 2 else 1,
				0,
				theme.Id == "Classic" or theme.Id == "Fell"
			)
			local artW = if phone then 40 else 150
			local art = mapArt(
				mapId,
				Vector2.new(artW, cardH - (if phone then 8 else 12)),
				UDim.new(0, math.max(0, theme.CornerRadius.Offset - 4))
			)
			art.Position = UDim2.fromOffset(if phone then 4 else 6, if phone then 4 else 6)
			art.Parent = button
			local x0 = artW + (if phone then 10 else 18)
			UIKit.Label(theme, {
				Name = "Name",
				Text = if meta then Style.Pick(meta.Name) else mapId,
				Role = "Heading",
				TextSize = if phone then math.max(theme.TextSize.Caption - 1, 9) else theme.TextSize.Small,
				Upper = true,
				Truncate = true,
				Position = UDim2.fromOffset(x0, if phone then 3 else 9),
				Size = UDim2.new(1, -x0 - (if phone then 40 else 10), 0, if phone then 13 else 22),
				Parent = button,
			})
			if not phone and meta then
				UIKit.Label(theme, {
					Name = "Desc",
					Text = Style.Pick(meta.Desc),
					Role = "Caption",
					Tone = "Dim",
					Wrap = true,
					Truncate = true,
					YAlign = "Top",
					Position = UDim2.fromOffset(x0, 36),
					Size = UDim2.new(1, -x0 - 10, 0, 34),
					Parent = button,
				})
			end
			local track = Style.Frame({
				Name = "Track",
				BackgroundTransparency = 0,
				BackgroundColor3 = c.PanelInset,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, x0, 1, if phone then -5 else -14),
				Size = UDim2.new(1, -x0 - (if phone then 40 else 96), 0, if phone then 4 else 8),
				Parent = button,
			})
			Style.Corner(track, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			local bar = Style.Frame({
				Name = "Fill",
				BackgroundTransparency = 0,
				BackgroundColor3 = c.Accent,
				Size = UDim2.fromScale(0, 1),
				Parent = track,
			})
			Style.Corner(bar, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			local count = UIKit.Label(theme, {
				Name = "Count",
				Text = "",
				Role = if phone then "Number" else "Caption",
				TextSize = if phone then 12 else nil,
				XAlign = "Right",
				AnchorPoint = if phone then Vector2.new(1, 0.5) else Vector2.new(1, 1),
				Position = if phone then UDim2.new(1, -6, 0.5, 0) else UDim2.new(1, -10, 1, -8),
				Size = UDim2.fromOffset(if phone then 32 else 84, 20),
				Parent = button,
			})
			-- (phones: no badges - the accent stroke marks YOUR vote, the count says who leads)
			local mine = UIKit.Badge(theme, {
				Text = Style.L("lobby.vote.mine"),
				Color = c.Accent,
				Style = "Solid",
				Icon = "Check",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -12),
				Height = 22,
				Visible = not phone,
				Parent = button,
			})
			local lead = UIKit.Badge(theme, {
				Text = Style.L("lobby.vote.leading"),
				Color = c.Gold,
				Style = "Solid",
				Icon = "Crown",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.fromOffset(12, 12),
				Height = 22,
				Visible = not phone,
				Parent = button,
			})
			lead.ZIndex = 3
			Motion.On(button, "Activated", function()
				vote(mapId)
			end)
			button.Parent = voteList
			table.insert(
				cards,
				{ Id = mapId, Root = button, Bar = bar, Count = count, Mine = mine, Lead = lead, Stroke = stroke }
			)
		end
	end

	local function buildChances(list: { any })
		chanceRows:ClearAllChildren()
		local rowH = if phone then 22 else 28
		local maxRows = math.max(1, math.floor((chanceHeight - (if phone then 48 else 96)) / rowH))
		if #list == 0 then
			UIKit.Label(theme, {
				Name = "Empty",
				Text = Style.L("lobby.chance.empty"),
				Role = "Caption",
				Tone = "Dim",
				Size = UDim2.new(1, 0, 0, rowH),
				Parent = chanceRows,
			})
			return
		end
		for i, entry in list do
			if i > maxRows then
				break
			end
			local row = Style.Frame({
				Name = "Row" .. i,
				Position = UDim2.fromOffset(0, (i - 1) * rowH),
				Size = UDim2.new(1, 0, 0, rowH),
				Parent = chanceRows,
			})
			if entry.IsLocal then
				local cursor = UIKit.Cursor(theme, if phone then 12 else 14)
				cursor.AnchorPoint = Vector2.new(0, 0.5)
				cursor.Position = UDim2.new(0, 0, 0.5, 0)
				cursor.Parent = row
			end
			local nameText = entry.Name .. (if entry.IsLocal then "  (" .. Style.L("lobby.chance.you") .. ")" else "")
			UIKit.Label(theme, {
				Name = "Name",
				Text = nameText,
				Role = "Body",
				TextSize = if phone then theme.TextSize.Caption else theme.TextSize.Small,
				Tone = if entry.IsLocal then "Accent" else "Text",
				Scaled = true,
				Position = UDim2.fromOffset(if phone then 18 else 22, 0),
				Size = UDim2.new(1, -(if phone then 18 else 22) - 120, 1, -6),
				Parent = row,
			})
			local pct = math.floor((entry.Chance or 0) * 100 + 0.5)
			local track = Style.Frame({
				Name = "Track",
				BackgroundTransparency = 0,
				BackgroundColor3 = c.PanelInset,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -46, 0.5, -2),
				Size = UDim2.fromOffset(70, 6),
				Parent = row,
			})
			Style.Corner(track, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			local fill = Style.Frame({
				Name = "Fill",
				BackgroundTransparency = 0,
				BackgroundColor3 = if entry.Pity then c.Gold elseif entry.Pref == "Monster" then c.Danger else c.Accent,
				Size = UDim2.fromScale(math.clamp(entry.Chance or 0, 0, 1), 1),
				Parent = track,
			})
			Style.Corner(fill, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			UIKit.Label(theme, {
				Name = "Pct",
				Text = if entry.Pref == "Human" then "—" else pct .. "%",
				Role = "Number",
				TextSize = if phone then theme.TextSize.Caption else theme.TextSize.Small,
				XAlign = "Right",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 44, 1, -6),
				Parent = row,
			})
			Style.Frame({
				Name = "Rule",
				BackgroundTransparency = 0.85,
				BackgroundColor3 = c.Text,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = row,
			})
		end
	end

	local function showChosen(info: { [string]: any })
		local kit = Style.Kit(info.KitId)
		local color = if kit then kit.Color else c.Accent
		chosenIcon:ClearAllChildren()
		Style.Glow({
			Name = "Glow",
			Color = color,
			Size = UDim2.fromScale(1, 1),
			Spread = 18,
			Strength = 0.45,
			Corner = UDim.new(0.5, 0),
			Parent = chosenIcon,
		})
		local icon = Icons.Create("Skull", color, UDim2.fromScale(1, 1))
		icon.Parent = chosenIcon
		chosenKit.Text = UIKit.Upper(if kit then Style.Pick(kit.Name) else tostring(info.KitId))
		chosenKit.TextColor3 = color
		chosenTitle.Text = UIKit.Upper(if kit then Style.Pick(kit.Title) else "")
		chosenLine.Text = if info.IsLocal
			then Style.L("lobby.chosen.you")
			else Style.L("lobby.chosen.line", info.Name or "?", if kit then Style.Pick(kit.Name) else "?")
		chosen.Root.Visible = true
		chosenUntil = if Style.Live() then clock + CHOSEN_TIME else math.huge
	end

	local function tick(now: number)
		clock = now
		local s = snap
		if not s then
			return
		end
		local left = math.max(0, (s.EndsAt or 0) - now)
		if s.Phase == "Intermission" then
			timer.Text = Style.FormatClock(left)
			subLine.Text = Style.L("lobby.intermission.line", math.ceil(left))
		end
		if chosen.Root.Visible and now > chosenUntil then
			chosen.Root.Visible = false
		end
	end

	local function update(s: { [string]: any })
		snap = s
		clock = s.Now or clock
		local phase = s.Phase or "Waiting"
		local waiting = phase == "Waiting"
		local inRound = not (waiting or phase == "Intermission")
		phaseLabel.Text = UIKit.Upper(Style.L("round.phase." .. (if inRound then "Round" else phase)))
		if waiting then
			timer.Text = Style.L("lobby.waiting.players", s.PlayerCount or 1, s.MinPlayers or 2)
			timer.TextSize = if phone then 12 else 18
			subLine.Text = Style.L(if phone then "mobile.lobby.waiting.short" else "lobby.waiting.line")
		elseif inRound then
			timer.Text = if (s.EndsAt or 0) > 0 then Style.FormatClock((s.EndsAt or 0) - (s.Now or 0)) else ""
			timer.TextSize = if phone then 26 else 38
			subLine.Text = Style.L(if phase == "Intro" then "lobby.intro.line" else "lobby.round.line")
		else
			timer.TextSize = if phone then 26 else 38
		end
		if practiceButton then
			practiceButton.SetSelected(waiting)
		end
		if practiceHolder then
			-- phones: the call-to-action only while waiting; the column slides up when it is gone
			practiceHolder.Visible = waiting
			local shift = if waiting then 0 else -(pr.Practice.H + 8)
			buttons.Position = UDim2.fromOffset(pr.Buttons.X, pr.Buttons.Y + shift)
			chancePanel.Root.Position = UDim2.fromOffset(pr.Chances.X, pr.Chances.Y + shift)
		end
		-- votes
		local options = s.VoteOptions or {}
		votePanel.Root.Visible = phase == "Intermission" and #options > 0
		local key = table.concat(options, ",")
		if key ~= voteKey then
			voteKey = key
			buildCards(options)
		end
		local total, best = 0, 0
		for _, id in options do
			local n = (s.Votes or {})[id] or 0
			total += n
			best = math.max(best, n)
		end
		for _, card in cards do
			local n = (s.Votes or {})[card.Id] or 0
			card.Bar.Size = UDim2.fromScale(if total > 0 then n / total else 0, 1)
			card.Count.Text = if phone
				then tostring(n)
				else UIKit.Upper(if n == 1 then Style.L("lobby.vote.one") else Style.L("lobby.vote.votes", n))
			card.Mine.Visible = not phone and s.MyVote == card.Id
			card.Lead.Visible = not phone and n > 0 and n == best
			if card.Stroke then
				card.Stroke.Color = if s.MyVote == card.Id then c.Accent else c.StrokeDim
				card.Stroke.Thickness = if s.MyVote == card.Id
					then (if theme.Id == "Classic" then 3 else 2)
					else (if theme.Id == "Classic" then 2 else 1)
			end
		end
		-- chances
		local parts = {}
		for _, entry in s.Chances or {} do
			table.insert(
				parts,
				string.format(
					"%s:%.3f:%s:%s",
					entry.Name,
					entry.Chance or 0,
					tostring(entry.Pref),
					tostring(entry.Pity)
				)
			)
		end
		local ck = table.concat(parts, "|")
		if ck ~= chanceKey then
			chanceKey = ck
			if chanceValue then
				local mine: any = nil
				for _, entry in s.Chances or {} do
					if entry.IsLocal then
						mine = entry
					end
				end
				chanceValue.Text = if mine == nil or mine.Pref == "Human"
					then "—"
					else UIKit.Upper(Style.L("lobby.chance.you")) .. " " .. math.floor(
						(mine.Chance or 0) * 100 + 0.5
					) .. "%"
			else
				buildChances(s.Chances or {})
			end
		end
		if s.Chosen then
			showChosen(s.Chosen)
		end
		tick(s.Now or 0)
	end

	local initial = Style.Initial(deps, "Lobby")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Tick = tick,
		ShowChosen = showChosen,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return LobbyHud
