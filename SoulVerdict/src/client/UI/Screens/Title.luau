--!strict
-- Screens/Title: the title screen shown on join (SPEC §10). The live 3D lobby (camera "Menu" mode, set by
-- UIController) is the background; this screen only adds a tasteful vignette (bled under the top bar / notch
-- strips, Common.Bleed), the animated logo ("SOUL VERDICT" + beating SOUL heart + "an UNDERTALE fan game"), the main
-- menu with the heart cursor, a player card (LV / EXP / G / monster chance), the round status, a dialogue line
-- describing the focused option (desktop) and the fan-game disclaimer. While it is open the lobby HUD is hidden
-- (UIController -> Hud.SetMenu), so nothing else competes for the screen.
--
--   Title.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnShow }
--   Title.Items(allow) -> {Item}     menu entries in order; allow = { Practice, StyleLab, Admin: boolean } (pure)
--   Title.PhoneMetrics(canvas, rows) -> { Margin, Logo, PlayW, PlayH, BtnH, CellW, Gap, GridW, GridH, Bottom, Scroll }
--       the phone layout numbers (pure; tests check the rects do not overlap at phone sizes)
--   deps: UI (UIController: Open(name), Close(), Play(), Practice()), State, Input, Layout (+ offline mocks: Profile,
--         Round, Attrs { StyleLab = true, Admin = true }, StyleLab = true, PlayerName)
-- Menu: PLAY (closes the menus -> lobby), PRACTICE (only while waiting for players: a round vs bots right away),
-- LOADOUT, SHOP, QUESTS, PROFILE, SETTINGS, STYLE LAB / ADMIN (only when the Player attribute of that name is true;
-- they appear live when the server grants them).
-- Phones (layout.Phone): logo top-left, player card + status top-right, PLAY / PRACTICE bottom-left (thumb), the
-- other entries in a 2-column grid bottom-right (scrolls if it ever outgrows the space), one-line disclaimer.

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Title = {}

local L = Common.L
local frame = Common.Frame

type Item = { Id: string, Text: string, Icon: string, Desc: string, Primary: boolean?, Gate: string? }

local function btnHeightFor(theme: Theme, phone: boolean): number
	return if phone then 40 else math.max(theme.Button.Height, 52)
end

local ALL_ITEMS: { { any } } = {
	-- id, text key, icon, description key, gate
	{ "Play", "scr.title.play", "Play", "scr.title.desc.play" },
	{ "Practice", "mobile.title.practice", "Swords", "mobile.title.desc.practice", "Practice" },
	{ "Loadout", "scr.title.loadout", "Swords", "scr.title.desc.loadout" },
	{ "Shop", "scr.title.shop", "Shop", "scr.title.desc.shop" },
	{ "Quests", "scr.title.quests", "Quests", "scr.title.desc.quests" },
	{ "Profile", "scr.title.profile", "Profile", "scr.title.desc.profile" },
	{ "Settings", "scr.title.settings", "Settings", "scr.title.desc.settings" },
	{ "StyleLab", "scr.title.stylelab", "Palette", "scr.title.desc.stylelab", "StyleLab" },
	{ "Admin", "mobile.title.admin", "Crown", "mobile.title.desc.admin", "Admin" },
}

-- every entry (gated ones included; `allow` only marks which gated entries start visible)
function Title.Items(allow: { [string]: boolean }?): { Item }
	local out: { Item } = {}
	for _, row in ALL_ITEMS do
		local gate = row[5]
		if gate == nil or allow == nil or allow[gate] then
			table.insert(out, {
				Id = row[1],
				Text = L(row[2]),
				Icon = row[3],
				Desc = L(row[4]),
				Primary = row[1] == "Play",
				Gate = gate,
			})
		end
	end
	return out
end

-- phone layout numbers for a canvas and a number of grid rows
function Title.PhoneMetrics(canvas: Vector2, rows: number): { [string]: any }
	local margin = if canvas.X < 1000 then 16 else 22
	local bottom = canvas.Y - 40 -- above the disclaimer
	local btnH = 40
	local gap = 10
	local cellW = math.clamp(math.floor((canvas.X - margin * 2 - 300 - 40) / 2 - 6), 170, 214)
	local gridW = cellW * 2 + 12
	local top = 132 -- under the player card + status chip (top right)
	local needH = rows * btnH + math.max(rows - 1, 0) * gap
	local gridH = math.min(needH, bottom - top)
	return {
		Margin = margin,
		Logo = if canvas.Y < 470 then 26 else 30,
		PlayW = 300,
		PlayH = 54,
		PracticeH = 42,
		BtnH = btnH,
		CellW = cellW,
		Gap = gap,
		GridW = gridW,
		GridH = gridH,
		NeedH = needH,
		Bottom = bottom,
		Scroll = needH > bottom - top,
	}
end

-- vignette over the live world (left side darker for the menu, bottom for the disclaimer); bled to the screen edges
local function vignette(theme: Theme, root: Frame, phone: boolean, layout: any)
	local c = theme.Colors
	local base = if theme.Id == "Classic" then Color3.new(0, 0, 0) else c.Background
	local holder = frame({ Name = "Vignette", Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = root })
	Common.Bleed(holder, layout)
	local left = frame({
		Name = "VignetteLeft",
		BackgroundTransparency = 0,
		BackgroundColor3 = base,
		Size = UDim2.fromScale(if phone then 0.62 else 0.58, 1),
		ZIndex = 0,
		Parent = holder,
	})
	Common.Gradient(
		left,
		nil,
		Common.NSeq({ { 0, if phone then 0.25 else 0.08 }, { 0.45, if phone then 0.55 else 0.42 }, { 1, 1 } }),
		0
	)
	local bottom = frame({
		Name = "VignetteBottom",
		BackgroundTransparency = 0,
		BackgroundColor3 = base,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, if phone then 0.5 else 0.34),
		ZIndex = 0,
		Parent = holder,
	})
	Common.Gradient(
		bottom,
		nil,
		Common.NSeq({ { 0, 1 }, { 0.6, if phone then 0.45 else 0.55 }, { 1, if phone then 0.15 else 0.2 } }),
		90
	)
	local top = frame({
		Name = "VignetteTop",
		BackgroundTransparency = 0,
		BackgroundColor3 = base,
		Size = UDim2.fromScale(1, if phone then 0.34 else 0.2),
		ZIndex = 0,
		Parent = holder,
	})
	Common.Gradient(top, nil, Common.NSeq({ { 0, 0.35 }, { 1, 1 } }), 90)
	local right = frame({
		Name = "VignetteRight",
		BackgroundTransparency = 0,
		BackgroundColor3 = base,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(if phone then 0.5 else 0.22, 1),
		ZIndex = 0,
		Parent = holder,
	})
	Common.Gradient(right, nil, Common.NSeq({ { 0, 1 }, { 1, if phone then 0.35 else 0.45 } }), 0)
	-- theme tint: a whisper of the accent light rising from the floor
	if theme.Id ~= "Classic" then
		local tint = frame({
			Name = "Tint",
			BackgroundTransparency = 0,
			BackgroundColor3 = if theme.Id == "Fell" then c.Accent else c.Glow,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0.5),
			ZIndex = 0,
			Parent = holder,
		})
		Common.Gradient(tint, nil, Common.NSeq({ { 0, 1 }, { 1, if theme.Id == "Void" then 0.9 else 0.93 } }), 90)
	end
end

-- logo: beating SOUL emblem + two-line wordmark + subtitle ----------------------------------------------
local function logo(theme: Theme, parent: Frame, size: number, phone: boolean): Frame
	local c = theme.Colors
	local emblem = math.floor(size * 1.55)
	local block = frame({
		Name = "Logo",
		Size = UDim2.fromOffset(emblem + size * 6.2, math.floor(size * 2.55) + 30),
		Parent = parent,
	})
	-- emblem: rings + heart
	local holder = frame({
		Name = "Emblem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(emblem / 2, math.floor(size * 1.18)),
		Size = UDim2.fromOffset(emblem, emblem),
		Parent = block,
	})
	local ringColor = if theme.Id == "Classic"
		then c.SoulRed
		elseif theme.Id == "Royal" then c.Accent
		elseif theme.Id == "Void" then c.Accent
		else c.Accent
	for k = 1, 3 do
		local ring = frame({
			Name = "Ring" .. k,
			BackgroundTransparency = if theme.Id == "Classic" then 1 else 0.9 + k * 0.025,
			BackgroundColor3 = ringColor,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62 + k * 0.2, 0.62 + k * 0.2),
			Parent = holder,
		})
		Common.Corner(ring, if theme.Id == "Classic" or theme.Id == "Fell" then UDim.new(0, 0) else UDim.new(0.5, 0))
		if theme.Id == "Fell" then
			ring.Rotation = 45
			ring.Size = UDim2.fromScale(0.46 + k * 0.16, 0.46 + k * 0.16)
		end
		local s =
			Common.Stroke(ring, ringColor, if theme.Id == "Classic" then 3 else 1.5, 0.35 + k * 0.17, theme.LineJoin)
		if theme.Id == "Royal" and theme.Gradients.Stroke then
			Common.Gradient(s, theme.Gradients.Stroke, nil, 45)
		end
		if k == 2 then
			Motion.Pulse(
				ring,
				{ BackgroundTransparency = ring.BackgroundTransparency },
				{ BackgroundTransparency = math.max(ring.BackgroundTransparency - 0.06, 0) },
				theme.Motion.PulsePeriod * 1.4
			)
		end
	end
	local heartHolder = frame({
		Name = "HeartHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.56, 0.56),
		Parent = holder,
	})
	local heart = UIKit.Heart(c.SoulRed, UDim2.fromScale(1, 1), true)
	heart.Parent = heartHolder
	local beat = Instance.new("UIScale")
	beat.Name = "Beat"
	beat.Scale = 1
	beat.Parent = heartHolder
	Motion.Pulse(beat, { Scale = 1 }, { Scale = 1.09 }, 0.9)
	-- wordmark
	local x = emblem + math.floor(size * 0.45)
	local lineH = math.ceil(size * (if theme.Id == "Fell" then 0.98 else 1.08))
	local soul = UIKit.Title(theme, {
		Name = "Soul",
		Text = "SOUL",
		Role = "Display",
		TextSize = size,
		Size = UDim2.fromOffset(math.floor(size * 6), lineH),
		Position = UDim2.fromOffset(x, math.floor(size * 0.05)),
	})
	soul.Root.Parent = block
	local verdict = UIKit.Title(theme, {
		Name = "Verdict",
		Text = "VERDICT",
		Role = "Display",
		TextSize = size,
		Size = UDim2.fromOffset(math.floor(size * 6), lineH),
		Position = UDim2.fromOffset(x, math.floor(size * 0.05) + lineH),
	})
	verdict.Root.Parent = block
	if theme.Id == "Fell" then
		soul.Root.Rotation = -2
		verdict.Root.Rotation = -2
	end
	local sub = UIKit.Label(theme, {
		Name = "Subtitle",
		Text = L("game.subtitle"),
		Role = "Subtitle",
		TextSize = if phone then math.max(theme.TextSize.Small - 1, 9) else theme.TextSize.Subtitle,
		Color = if theme.Id == "Royal" then c.Accent elseif theme.Id == "Classic" then c.TextDim else c.TextDim,
		Position = UDim2.fromOffset(x + 2, math.floor(size * 0.05) + lineH * 2 + (if phone then 2 else 6)),
		Size = UDim2.fromOffset(math.floor(size * 6), theme.TextSize.Subtitle + 6),
		Parent = block,
	})
	if theme.Id == "Classic" then
		sub.Text = "* " .. sub.Text
	end
	return block
end

-- player card (top right) -------------------------------------------------------------------------------
local function playerCard(theme: Theme, deps: any, parent: Frame, phone: boolean): Frame
	local c = theme.Colors
	local profile = Common.Profile(deps)
	local card = frame({
		Name = "PlayerCard",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(if phone then 300 else 420, if phone then 74 else 104),
		Parent = parent,
	})
	local name = UIKit.Label(theme, {
		Name = "Name",
		Text = L("scr.title.welcome", Common.PlayerName(deps)),
		Role = "Heading",
		TextSize = if phone then theme.TextSize.Body else theme.TextSize.Heading,
		XAlign = "Right",
		Truncate = true,
		Size = UDim2.new(1, 0, 0, if phone then 22 else 30),
		Parent = card,
	})
	name.TextColor3 = c.Text
	local row = frame({
		Name = "Row",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, if phone then 26 else 38),
		Size = UDim2.new(1, 0, 0, if phone then 30 else 38),
		Parent = card,
	})
	local cur = Common.Currency(
		theme,
		profile,
		{
			Height = if phone then 30 else 38,
			Compact = phone,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
		}
	)
	cur.Parent = row
	local chance = Common.PlayerAttr(deps, "MonsterChance", 0)
	local chanceText = L("scr.title.chance", math.floor((tonumber(chance) or 0) * 100 + 0.5))
	if profile == nil and not Common.IsPreview(deps) then
		chanceText = L("scr.loadingProfile")
	end
	UIKit.Label(theme, {
		Name = "Chance",
		Text = chanceText,
		Role = "Caption",
		Tone = "Dim",
		XAlign = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, if phone then 58 else 82),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = card,
	})
	return card
end

-- round status chip (phase + countdown + players) ---------------------------------------------------------
local function statusChip(theme: Theme, deps: any, parent: Frame, bag: any, small: boolean?): Frame
	local round = Common.Round(deps)
	local phase = tostring(round.Phase or "Waiting")
	local function text(): string
		local r = Common.Round(deps)
		local p = tostring(r.Phase or "Waiting")
		local ends = tonumber(r.PhaseEndsAt) or 0
		local left = ends - Common.Now(deps)
		local players = 6
		if not Common.IsPreview(deps) then
			local ok, list = pcall(function()
				return game:GetService("Players"):GetPlayers()
			end)
			players = if ok then #list else 1
		end
		local phaseText = L("round.phase." .. p)
		local timer = if left > 0 and p ~= "Waiting" then "  " .. Common.Clock(left) else ""
		return phaseText .. timer .. "   ·   " .. L("scr.title.players", players)
	end
	local chip = Common.Chip(theme, {
		Name = "Status",
		Icon = if phase == "Round" or phase == "Collapse" then "Swords" else "Clock",
		Text = text(),
		Color = if phase == "Round" or phase == "Collapse" then theme.Colors.Danger else theme.Colors.Accent,
		Height = if small then 28 else 34,
		Role = "Caption",
		TextSize = if theme.Id == "Classic" then (if small then 8 else 11) else (if small then 12 else 15),
		Parent = parent,
	})
	-- live update (runtime only)
	local label = chip:FindFirstChild("Text") :: TextLabel?
	local acc = 0
	bag.Add(Motion.Loop(chip, function(dt: number)
		acc += dt
		if acc >= 0.5 and label then
			acc = 0
			label.Text = text()
		end
	end))
	return chip
end

function Title.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local layout = Common.Layout(d)
	local phone = layout.Phone == true
	local canvas: Vector2 = layout.Canvas
	local bag = Common.Bag()

	local root = frame({ Name = "Title", Size = UDim2.fromScale(1, 1) })
	if Common.IsPreview(d) then
		-- offline stand-in for the live 3D lobby so previews read like the real thing
		local stand = UIKit.Backdrop(theme, { Name = "PreviewWorld", Parent = root })
		stand.ZIndex = 0
		Common.Bleed(stand, layout)
	end
	vignette(theme, root, phone, layout)
	-- everything interactive sits above the vignette (ZIndex 2; Sibling ZIndexBehavior)
	local content = frame({ Name = "Content", Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root })

	-- which gated entries start visible
	local function phaseNow(): string
		return tostring(Common.Round(d).Phase or "Waiting")
	end
	local allow = {
		Practice = phaseNow() == "Waiting",
		StyleLab = Common.PlayerAttr(d, "StyleLab", false) == true or d.StyleLab == true,
		Admin = Common.PlayerAttr(d, "Admin", false) == true or d.Admin == true,
	}
	local list = Title.Items(nil)
	local rows = 0
	do
		local gridItems = 0
		for _, item in list do
			if item.Id ~= "Play" and item.Id ~= "Practice" and (item.Gate == nil or allow[item.Gate]) then
				gridItems += 1
			end
		end
		rows = math.ceil(gridItems / 2)
	end
	local pm = Title.PhoneMetrics(canvas, rows)
	local margin = if phone then pm.Margin else 72

	-- logo
	local logoSize = if phone
		then pm.Logo + (if theme.Id == "Fell" then 6 elseif theme.Id == "Royal" then 2 else 0)
		elseif theme.Id == "Classic" then 60
		elseif theme.Id == "Royal" then 74
		elseif theme.Id == "Void" then 62
		else 84
	local logoBlock = logo(theme, content, logoSize, phone)
	logoBlock.Position = UDim2.fromOffset(margin - (if phone then 2 else 12), if phone then 10 else 64)

	local btnH = btnHeightFor(theme, phone)
	local gap = if phone then 8 else 10
	local menuW = if phone then pm.PlayW else 400
	local menu: GuiObject
	local grid: GuiObject? = nil
	if phone then
		-- left column, bottom-up: status chip, PRACTICE, PLAY (thumb reach); hidden entries collapse the list
		menu = frame({
			Name = "Menu",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset(margin, pm.Bottom),
			Size = UDim2.fromOffset(menuW, pm.Bottom - 120),
			Parent = content,
		})
		local ml = UIKit.ListLayout(menu, { Gap = gap })
		ml.VerticalAlignment = Enum.VerticalAlignment.Bottom
		-- right: the other entries in a 2-column grid (a ScrollingFrame if it ever outgrows the space)
		local gridHolder: GuiObject
		if pm.Scroll then
			local sf = Instance.new("ScrollingFrame")
			sf.Name = "Grid"
			sf.BackgroundTransparency = 1
			sf.BorderSizePixel = 0
			sf.ScrollingDirection = Enum.ScrollingDirection.Y
			sf.ScrollBarThickness = 4
			sf.CanvasSize = UDim2.fromOffset(0, pm.NeedH)
			sf.AnchorPoint = Vector2.new(1, 1)
			sf.Position = UDim2.new(1, -margin, 0, pm.Bottom)
			sf.Size = UDim2.fromOffset(pm.GridW + 8, pm.GridH)
			sf.Parent = content
			gridHolder = sf
		else
			gridHolder = frame({
				Name = "Grid",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -margin, 0, pm.Bottom),
				Size = UDim2.fromOffset(pm.GridW, pm.GridH),
				Parent = content,
			})
		end
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(pm.CellW, pm.BtnH)
		gl.CellPadding = UDim2.fromOffset(12, pm.Gap)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		gl.VerticalAlignment = if pm.Scroll then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
		gl.Parent = gridHolder
		grid = gridHolder
	else
		-- one column under the logo; buttons shrink to fit every entry (gated ones included) above the
		-- disclaimer, and the list scrolls on very short canvases (ultra-wide windows)
		local menuTop = 64 + math.floor(logoSize * 2.55) + 48
		local avail = canvas.Y - menuTop - 70
		local n = #list
		local fitH = math.floor((avail - 10 - gap * (n - 1)) / n)
		btnH = math.clamp(fitH, 40, btnH)
		if fitH < 40 then
			local sf = Instance.new("ScrollingFrame")
			sf.Name = "Menu"
			sf.BackgroundTransparency = 1
			sf.BorderSizePixel = 0
			sf.ScrollingDirection = Enum.ScrollingDirection.Y
			sf.ScrollBarThickness = 4
			sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
			sf.CanvasSize = UDim2.new()
			sf.Position = UDim2.fromOffset(margin + 34, menuTop)
			sf.Size = UDim2.fromOffset(menuW + 12, avail)
			sf.Parent = content
			menu = sf
		else
			menu = frame({
				Name = "Menu",
				Position = UDim2.fromOffset(margin + 34, menuTop),
				Size = UDim2.fromOffset(menuW, avail),
				Parent = content,
			})
		end
		UIKit.ListLayout(menu, { Gap = gap })
	end
	local desc: TextLabel? = nil
	local typer: any = nil
	local buttons: { GuiObject } = {}
	local gated: { [string]: GuiObject } = {}
	local defaultSel: GuiObject? = nil

	local function describe(text: string)
		if desc == nil then
			return
		end
		if typer then
			typer.Cancel()
		end
		desc.Text = (if theme.Id == "Classic" then theme.DialoguePrefix else "") .. text
		typer = Motion.Typewriter(
			desc,
			desc.Text,
			{ Interval = theme.Motion.TypeInterval * 0.6, Sound = theme.Sounds.Type, SoundEvery = 3 }
		)
	end

	local function activate(id: string)
		local ui = d.UI
		if ui == nil then
			return
		end
		if id == "Play" then
			if type(ui.Play) == "function" then
				ui.Play()
			elseif type(ui.Close) == "function" then
				ui.Close()
			end
		elseif id == "Practice" then
			if type(ui.Practice) == "function" then
				ui.Practice() -- no side: the chooser asks "as Sans or as a human"
			else
				Common.Request(d, "StartPractice", { side = "Human" })
				if type(ui.Close) == "function" then
					ui.Close()
				end
			end
		elseif type(ui.Open) == "function" then
			ui.Open(id)
		end
	end

	local touch = Common.Device(d) == "Touch"
	for i, item in list do
		local isPlay = item.Primary == true
		local inColumn = isPlay or item.Id == "Practice"
		local height = if isPlay and phone
			then pm.PlayH
			elseif isPlay then btnH + 10
			elseif item.Id == "Practice" and phone then pm.PracticeH
			else btnH
		local btn = UIKit.Button(theme, {
			Name = "Menu_" .. item.Id,
			Text = item.Text,
			Icon = item.Icon,
			Variant = if isPlay then "Primary" else "Secondary",
			Height = height,
			Width = if phone and inColumn then menuW elseif phone then nil else menuW,
			Hint = if isPlay
					and not phone
					and not touch
				then (if Common.Device(d) == "Gamepad" then "ButtonA" else "Enter")
				else nil,
			State = if isPlay and Common.IsPreview(d) then "Hover" else nil,
			-- phones: PLAY is the last (lowest) row of the bottom-aligned column, PRACTICE right above it
			LayoutOrder = if phone and isPlay then 30 elseif phone and item.Id == "Practice" then 20 else i,
			OnActivated = function()
				activate(item.Id)
			end,
		})
		if phone and not inColumn and grid then
			btn.Root.Size = UDim2.fromOffset(pm.CellW, pm.BtnH)
			btn.Root.Parent = grid
		else
			btn.Root.Parent = menu
		end
		if item.Gate then
			gated[item.Gate] = btn.Root
			btn.Root.Visible = allow[item.Gate] == true
		end
		table.insert(buttons, btn.Root)
		if isPlay then
			defaultSel = btn.Root
		end
		Motion.Hover(btn.Root, function()
			describe(item.Desc)
		end, function() end)
	end
	UIKit.LinkSelection(buttons, "Vertical")

	-- player card + status (top right)
	local card = playerCard(theme, d, content, phone)
	card.Position = UDim2.new(1, -margin, 0, if phone then 8 else 54)
	local statusHolder = frame({
		Name = "StatusHolder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -margin, 0, if phone then 90 else 176),
		Size = UDim2.fromOffset(if phone then 420 else 600, 34),
		Parent = content,
	})
	local sl = UIKit.ListLayout(statusHolder, { Horizontal = true, HAlign = Enum.HorizontalAlignment.Right })
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusChip(theme, d, statusHolder, bag, phone)

	-- dialogue line describing the focused option (desktop)
	if not phone then
		local box = UIKit.Panel(theme, {
			Name = "Describe",
			Variant = "Dialogue",
			Padding = 18,
			Shadow = false,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -margin, 1, -70),
			Size = UDim2.fromOffset(math.min(620, canvas.X * 0.4), 78),
		})
		box.Root.Parent = content
		local label = UIKit.Label(theme, {
			Name = "Text",
			Text = "",
			Role = "Body",
			Wrap = true,
			YAlign = "Top",
			Size = UDim2.fromScale(1, 1),
			LineHeight = theme.LineHeight,
			Parent = box.Content,
		})
		desc = label
		label.Text = (if theme.Id == "Classic" then theme.DialoguePrefix else "") .. list[1].Desc
	end

	-- disclaimer + version
	local footY = if phone then -6 else -18
	UIKit.Label(theme, {
		Name = "Disclaimer",
		Text = L("game.disclaimer"),
		Role = "Caption",
		TextSize = if phone then (if theme.Id == "Classic" then 8 else 11) elseif theme.Id == "Classic" then 8 else 12,
		Tone = "Muted",
		Wrap = true,
		XAlign = "Left",
		YAlign = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, margin, 1, footY),
		Size = UDim2.new(
			0,
			math.floor(if phone then canvas.X - margin * 2 else canvas.X * 0.56),
			0,
			if phone then 22 else 34
		),
		Parent = content,
	})
	local config = Common.Config()
	UIKit.Label(theme, {
		Name = "Version",
		Text = L("scr.title.version", if config and config.Version then tostring(config.Version) else "0.1"),
		Role = "Caption",
		TextSize = if theme.Id == "Classic" then 8 else 12,
		Tone = "Muted",
		XAlign = "Right",
		YAlign = "Bottom",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -margin, 1, footY),
		Size = UDim2.fromOffset(120, 18),
		Visible = not phone,
		Parent = content,
	})

	-- live: Style Lab / Admin permission can arrive after the screen was built; PRACTICE only while waiting
	local player = Common.LocalPlayer()
	if player then
		for _, gate in { "StyleLab", "Admin" } do
			bag.Connect(player:GetAttributeChangedSignal(gate), function()
				local button = gated[gate]
				if button then
					button.Visible = player:GetAttribute(gate) == true
				end
			end)
		end
	end
	local practiceAcc = 0
	bag.Add(Motion.Loop(root, function(dt: number)
		practiceAcc += dt
		local button = gated.Practice
		if button and practiceAcc >= 0.5 then
			practiceAcc = 0
			local show = phaseNow() == "Waiting"
			if button.Visible ~= show then
				button.Visible = show
			end
		end
	end))
	local state = d.State
	if state and state.ProfileChanged then
		bag.Connect(state.ProfileChanged, function()
			local old = content:FindFirstChild("PlayerCard")
			if old then
				old:Destroy()
			end
			local fresh = playerCard(theme, d, content, phone)
			fresh.Position = UDim2.new(1, -margin, 0, if phone then 8 else 54)
		end)
	end

	local function onShow()
		-- staggered entrance
		for i, b in buttons do
			if b.Visible then
				task.delay(0.035 * i, function()
					if b.Parent then
						Motion.SlideIn(b, theme, "Left", 26)
					end
				end)
			end
		end
		Motion.FadeIn(logoBlock, theme)
	end

	return {
		Root = root,
		DefaultSelection = defaultSel,
		OnShow = onShow,
		Destroy = function()
			if typer then
				typer.Cancel()
			end
			bag.Clean()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

return Title
