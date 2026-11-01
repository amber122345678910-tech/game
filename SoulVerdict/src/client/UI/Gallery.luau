--!strict
-- Gallery: a screen that showcases every UIKit component and every icon in the current theme, so the owner
-- can compare themes (Style Lab) and so tools/lune/dump_gui.luau can render previews offline.
--
--   Gallery.Create(theme, deps) -> { Root, Destroy, DefaultSelection, SetPage(page) }
--   deps (all optional): Layout (UIRoot layout; default desktop 1600x900 canvas),
--                        Page: "All" | "Controls" | "Data" | "Icons" | "Overlay"
--                              (default "All" on desktop canvases, "Controls" when Layout.Compact)
--                        Hud: HudStyle id for the HUD preview strip ("Battle" default)
--                        OnClose: () -> ()   (runtime: back button / Q,E theme switching is done by the caller)
-- Pages: All (desktop overview), Controls, Data, Icons (with names), Overlay (modal, toasts, tooltip,
-- countdown, viewport, HUD styles).

local Themes = require(script.Parent.Themes)
local UIKit = require(script.Parent.UIKit)
local Icons = require(script.Parent.Icons)
local Motion = require(script.Parent.Motion)

type Theme = Themes.Theme

local Gallery = {}

local SharedCache: any = nil
local function shared(): any
	if SharedCache == nil then
		SharedCache = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	end
	return SharedCache
end

local function Strings(): any
	return require(shared():WaitForChild("Strings")) :: any
end

local function Kits(): any
	return require(shared():WaitForChild("Kits")) :: any
end

local function L(key: string, ...: any): string
	return Strings().L(key, ...)
end

local function pick(tbl: any): string
	return Strings().Pick(tbl)
end

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in props do
		if k ~= "Parent" then
			(f :: any)[k] = v
		end
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

-- sections ----------------------------------------------------------------------------------------
local function buttonsPanel(theme: Theme, size: UDim2, position: UDim2?, compact: boolean, buttonHeight: number?): (GuiObject, GuiObject?)
	local panel = UIKit.Panel(theme, {
		Name = "Buttons",
		Title = L("ui.gallery.buttons"),
		Size = size,
		Position = position,
		Layout = "Vertical",
		Gap = if compact then 7 else 10,
	})
	local h = buttonHeight or (if compact then math.max(theme.Button.Height - 10, 44) else theme.Button.Height)
	local first = UIKit.Button(theme, { Text = L("ui.sample.play"), Icon = "Play", Variant = "Primary", Height = h, State = "Hover", LayoutOrder = 1, Hint = if compact then nil else "Return" })
	first.Root.Parent = panel.Content
	local specs = {
		{ L("ui.sample.loadout"), "Swords", "Secondary", nil },
		{ L("ui.sample.quests"), "Quests", "Ghost", nil },
		{ L("ui.sample.leave"), "Close", "Danger", nil },
		{ L("ui.sample.ranked"), "Lock", "Secondary", "Disabled" },
	}
	local buttons: { GuiObject } = { first.Root }
	for i, s in specs do
		local b = UIKit.Button(theme, { Text = s[1], Icon = s[2], Variant = s[3], Height = h, State = s[4], Disabled = s[4] == "Disabled", LayoutOrder = i + 1 })
		b.Root.Parent = panel.Content
		table.insert(buttons, b.Root)
	end
	local row = frame({ Name = "IconRow", Size = UDim2.new(1, 0, 0, h), LayoutOrder = 10, Parent = panel.Content })
	UIKit.ListLayout(row, { Horizontal = true, Gap = 12, VAlign = Enum.VerticalAlignment.Center })
	for i, iconName in { "Settings", "Music", "Shop", "Info", "Close" } do
		local b = UIKit.Button(theme, { Variant = "Icon", Icon = iconName, Height = h - 4, LayoutOrder = i, State = if i == 3 then "Selected" else nil })
		b.Root.Parent = row
	end
	UIKit.LinkSelection(buttons, "Vertical")
	return panel.Root, first.Root
end

local function controlsPanel(theme: Theme, size: UDim2, position: UDim2?, compact: boolean, showHints: boolean): GuiObject
	local panel = UIKit.Panel(theme, {
		Name = "Controls",
		Title = L("ui.gallery.controls"),
		Size = size,
		Position = position,
		Layout = "Vertical",
		Gap = if compact then 4 else 6,
	})
	local rowH = if compact then 34 else 35
	local themeOptions = {}
	for _, t in Themes.List() do
		table.insert(themeOptions, { Id = t.Id, Text = pick(t.Name) })
	end
	UIKit.Toggle(theme, { Label = L("ui.sample.damageNumbers"), Value = true, Height = rowH, LayoutOrder = 1, State = "Hover", Parent = panel.Content })
	UIKit.Toggle(theme, { Label = L("ui.sample.shake"), Value = false, Height = rowH, LayoutOrder = 2, Parent = panel.Content })
	UIKit.Slider(theme, { Label = L("ui.sample.music"), Value = 0.65, Height = rowH, LayoutOrder = 3, Parent = panel.Content })
	UIKit.Cycle(theme, {
		Label = L("ui.menuTheme"),
		Options = themeOptions,
		Index = table.find(Themes.Ids, theme.Id) or 1,
		Height = rowH + 4,
		LayoutOrder = 4,
		Parent = panel.Content,
	})
	if not compact then
		UIKit.Dropdown(theme, {
			Label = L("ui.language"),
			Options = { { Id = "en", Text = L("ui.lang.en") }, { Id = "ru", Text = L("ui.lang.ru") } },
			Index = if Strings().Language() == "ru" then 2 else 1,
			Height = rowH,
			LayoutOrder = 5,
			Parent = panel.Content,
		})
	end
	if not showHints then
		return panel.Root
	end
	local hints = frame({ Name = "Hints", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 6, Parent = panel.Content })
	UIKit.ListLayout(hints, { Horizontal = true, Gap = 14, VAlign = Enum.VerticalAlignment.Center })
	UIKit.KeyHint(theme, { Key = "E", Label = L("ui.select"), Height = 26, LayoutOrder = 1, Parent = hints })
	UIKit.KeyHint(theme, { Key = "Shift", Height = 26, LayoutOrder = 2, Parent = hints })
	UIKit.KeyHint(theme, { Key = "M1", Height = 26, LayoutOrder = 3, Parent = hints })
	UIKit.KeyHint(theme, { Key = "ButtonA", Height = 26, LayoutOrder = 4, Parent = hints })
	UIKit.KeyHint(theme, { Key = "ButtonR2", Label = L("ui.back"), Height = 26, LayoutOrder = 5, Parent = hints })
	return panel.Root
end

local function cardsPanel(theme: Theme, size: UDim2, position: UDim2?, cardSize: Vector2): GuiObject
	local panel = UIKit.Panel(theme, {
		Name = "Cards",
		Title = L("ui.gallery.kits"),
		Size = size,
		Position = position,
		Layout = "Horizontal",
		Gap = 12,
	})
	local kits = Kits()
	local entries = {
		{ id = "ClassicSans", selected = true },
		{ id = "Determination", hover = false },
		{ id = "FellSans", locked = true },
	}
	for i, e in entries do
		local kit = kits.Get(e.id)
		if kit then
			local tags = {}
			local m1 = kits.AbilityBySlot(e.id, "Q")
			if m1 and m1.Tags then
				for j, tag in m1.Tags do
					if j <= 2 then
						table.insert(tags, L("tag." .. tag))
					end
				end
			end
			UIKit.Card(theme, {
				Name = pick(kit.Name),
				Title = pick(kit.Title),
				Color = kit.Color,
				Icon = if m1 then m1.Icon else "Heart",
				Role = L(if kit.Role == "Monster" then "role.monster" else "role.human"),
				RoleMonster = kit.Role == "Monster",
				Difficulty = kit.Difficulty,
				Tags = tags,
				Selected = e.selected,
				Locked = e.locked,
				Price = if e.locked then kit.Unlock.Gold else nil,
				Size = UDim2.fromOffset(cardSize.X, cardSize.Y),
				LayoutOrder = i,
				Parent = panel.Content,
			})
		end
	end
	return panel.Root
end

local function barsPanel(theme: Theme, size: UDim2, position: UDim2?, compact: boolean): GuiObject
	local panel = UIKit.Panel(theme, {
		Name = "Bars",
		Title = L("ui.gallery.bars"),
		Size = size,
		Position = position,
		Layout = "Vertical",
		Gap = if compact then 5 else 7,
	})
	local barH = 24
	local lw = if theme.Id == "Classic" then 76 else 64
	UIKit.Bar(theme, { Kind = "HP", Label = L("stat.hp"), LabelWidth = lw, Value = 72, Max = 92, Secondary = 14, ShowValue = true, Ghost = true, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, barH), Parent = panel.Content })
	UIKit.Bar(theme, { Kind = "Guard", Label = L("stat.guard"), LabelWidth = lw, Value = 64, Max = 100, ShowValue = true, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, barH), Parent = panel.Content })
	UIKit.Bar(theme, {
		Kind = "Dodge",
		Label = L("stat.dodges"),
		LabelWidth = lw,
		Value = 5.4,
		Max = 8,
		Segments = 8,
		ShowValue = true,
		Format = function(v: number, m: number): string
			return string.format("%d / %d", math.floor(v), m)
		end,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, barH),
		Parent = panel.Content,
	})
	UIKit.Bar(theme, {
		Kind = "Ult",
		Label = L("stat.ult"),
		LabelWidth = lw,
		Value = 86,
		Max = 100,
		ShowValue = true,
		Format = function(v: number): string
			return string.format("%d%%", math.floor(v))
		end,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, barH),
		Parent = panel.Content,
	})
	if not compact then
		UIKit.Divider(theme, { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 10), Parent = panel.Content })
	end
	local stats = frame({ Name = "Stats", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 6, Parent = panel.Content })
	UIKit.StatRow(theme, { Label = L("ui.sample.wins"), Value = 128, Icon = "Trophy", Color = theme.Colors.Gold, Size = UDim2.new(0.48, 0, 1, 0), Parent = stats })
	UIKit.StatRow(theme, { Label = L("ui.sample.chance"), Value = "18%", Icon = "Skull", Fill = 0.18, Size = UDim2.new(0.48, 0, 1, 0), Position = UDim2.fromScale(0.52, 0), Parent = stats })
	local badges = frame({ Name = "Badges", Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 7, Parent = panel.Content })
	UIKit.ListLayout(badges, { Horizontal = true, Gap = 6 })
	UIKit.Badge(theme, { Text = L("tag.KR"), Color = theme.Colors.KR, Style = "Solid", LayoutOrder = 1, Parent = badges })
	UIKit.Badge(theme, { Text = L("tag.Beam"), Icon = "Blaster", Color = "Accent", LayoutOrder = 2, Parent = badges })
	UIKit.Badge(theme, { Text = L("tag.Mobility"), Icon = "Dash", Color = "Info", Style = "Outline", LayoutOrder = 3, Parent = badges })
	UIKit.Badge(theme, { Text = L("common.level", 7), Color = theme.Colors.Gold, LayoutOrder = 4, Parent = badges })
	return panel.Root
end

local function dialoguePanel(theme: Theme, size: UDim2, position: UDim2?): GuiObject
	local panel = UIKit.Panel(theme, { Name = "Dialogue", Variant = "Dialogue", Size = size, Position = position, Padding = 20 })
	local text = UIKit.Label(theme, {
		Text = L("ui.sample.dialogue"),
		Role = "Body",
		Dialogue = true,
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.new(1, -150, 1, 0),
		LineHeight = theme.LineHeight,
	})
	text.Parent = panel.Content
	Motion.Typewriter(text, text.Text, { Interval = theme.Motion.TypeInterval, Sound = theme.Sounds.Type })
	local countdown = UIKit.Countdown(theme, {
		Seconds = 9,
		Format = "Clock",
		Label = L("ui.sample.round"),
		TextSize = theme.TextSize.Title,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(140, 54),
	})
	countdown.Root.Parent = panel.Content
	return panel.Root
end

local function iconsPanel(theme: Theme, size: UDim2, position: UDim2?, cell: number, gap: number, showNames: boolean): GuiObject
	local panel = UIKit.Panel(theme, { Name = "Icons", Title = L("ui.gallery.icons"), Size = size, Position = position })
	local grid = UIKit.Grid(theme, {
		CellSize = UDim2.fromOffset(cell, if showNames then cell + 14 else cell),
		CellPadding = UDim2.fromOffset(gap, gap),
		HAlign = Enum.HorizontalAlignment.Center,
	})
	grid.Root.Parent = panel.Content
	local kitIcons: { [string]: boolean } = {}
	for _, n in Kits().IconNames do
		kitIcons[n] = true
	end
	local names = Icons.Names()
	table.sort(names, function(a, b)
		if (kitIcons[a] == true) ~= (kitIcons[b] == true) then
			return kitIcons[a] == true
		end
		return a < b
	end)
	local c = theme.Colors
	for i, name in names do
		local slot = frame({
			Name = "Slot_" .. name,
			BackgroundTransparency = if theme.Id == "Void" then 0.55 else 0,
			BackgroundColor3 = c.PanelInset,
			LayoutOrder = i,
		})
		local radius = if theme.Id == "Void" then UDim.new(0, 8) else theme.SmallCorner
		if radius.Offset > 0 then
			local uc = Instance.new("UICorner")
			uc.CornerRadius = radius
			uc.Parent = slot
		end
		local st = Instance.new("UIStroke")
		st.Color = if kitIcons[name] then c.StrokeDim else c.StrokeDim
		st.Thickness = 1
		st.Transparency = if theme.Id == "Classic" then 0.2 else 0.5
		st.LineJoinMode = theme.LineJoin
		st.Parent = slot
		local color = if kitIcons[name] then c.Accent else c.Text
		local accent = if kitIcons[name] then c.Accent2 else c.Accent
		local icon = Icons.Create(name, color, UDim2.fromOffset(math.floor(cell * 0.66), math.floor(cell * 0.66)), accent)
		icon.Position = UDim2.new(0.5, 0, 0, cell / 2)
		icon.Parent = slot
		if showNames then
			local label = UIKit.Label(theme, {
				Text = name,
				Role = "Caption",
				TextSize = if theme.Id == "Classic" then 6 else 9,
				Tone = "Dim",
				XAlign = "Center",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.new(1, -2, 0, 12),
				Scaled = true,
				MaxTextSize = if theme.Id == "Classic" then 6 else 10,
			})
			label.Parent = slot
		end
		grid.Add(slot)
	end
	return panel.Root
end

local function hudPreview(theme: Theme, hudId: string, size: UDim2, position: UDim2?): GuiObject
	local hud = Themes.GetHud(hudId)
	local battle = hud.Id == "Battle"
	local box = frame({
		Name = "Hud_" .. hud.Id,
		BackgroundTransparency = hud.Box.FillTransparency,
		BackgroundColor3 = hud.Colors.BoxFill,
		Size = size,
		Position = position or UDim2.new(),
	})
	local uc = Instance.new("UICorner")
	uc.CornerRadius = hud.Box.Corner
	uc.Parent = box
	local st = Instance.new("UIStroke")
	st.Color = hud.Colors.Box
	st.Thickness = hud.Box.StrokeThickness
	st.Transparency = if battle then 0 else 0.8
	st.LineJoinMode = if battle then Enum.LineJoinMode.Miter else Enum.LineJoinMode.Round
	st.Parent = box
	local content = frame({ Name = "Content", Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 1, -24), Parent = box })
	UIKit.ListLayout(content, { Gap = 8 })
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Text = UIKit.Upper(L("ui.gallery.hud", pick(hud.Name)))
	title.FontFace = Themes.HudFont(hud, "Title", Strings().Language())
	title.TextSize = hud.TextSize.Small + 2
	title.TextColor3 = hud.Colors.TextDim
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, hud.TextSize.Small + 6)
	title.LayoutOrder = 0
	title.Parent = content
	UIKit.Bar(theme, { Hud = hud, Kind = "HP", Label = "HP", Value = 72, Max = 92, Secondary = 14, ShowValue = true, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, hud.Bar.Height + 4), Parent = content })
	UIKit.Bar(theme, { Hud = hud, Kind = "Guard", Label = L("stat.guard"), Value = 70, Max = 100, LayoutOrder = 2, LabelWidth = if battle then 74 else 56, Size = UDim2.new(1, 0, 0, hud.Bar.Height), Parent = content })
	UIKit.Bar(theme, { Hud = hud, Kind = "Dodge", Label = L("stat.dodges"), Value = 4.5, Max = 6, Segments = 6, LayoutOrder = 3, LabelWidth = if battle then 74 else 56, Size = UDim2.new(1, 0, 0, hud.Bar.Height), Parent = content })
	UIKit.Bar(theme, { Hud = hud, Kind = "Ult", Label = L("stat.ult"), Value = 100, Max = 100, LayoutOrder = 4, LabelWidth = if battle then 74 else 56, Size = UDim2.new(1, 0, 0, hud.Bar.Height), Parent = content })
	return box
end

local function overlayPage(theme: Theme, parent: Frame, canvas: Vector2, compact: boolean, hudId: string)
	local c = theme.Colors
	local kits = Kits()
	-- tooltip (left)
	local blaster = kits.Ability("ClassicSans", "GasterBlaster")
	local tags = {}
	if blaster and blaster.Tags then
		for _, t in blaster.Tags do
			table.insert(tags, L("tag." .. t))
		end
	end
	UIKit.Tooltip(theme, {
		Title = if blaster then pick(blaster.Name) else "Gaster Blaster",
		Icon = "Blaster",
		Tags = tags,
		Text = if blaster then pick(blaster.Desc) else "",
		Stats = {
			{ Label = L("stat.cooldown", if blaster then blaster.Cooldown else 9), Value = "", Icon = "Clock" },
		},
		Width = if compact then 290 else 340,
		Position = UDim2.fromOffset(if compact then 24 else 60, if compact then 20 else 40),
		Parent = parent,
	})
	-- countdown (top centre)
	UIKit.Countdown(theme, {
		Seconds = 74,
		Label = L("ui.sample.round"),
		TextSize = theme.TextSize.Title + 8,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if compact then 26 else 40),
		Size = UDim2.fromOffset(220, 70),
		Parent = parent,
	})
	-- toasts (top right)
	local toasts = frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, if compact then -20 else -40, 0, if compact then 20 else 40),
		Size = UDim2.fromOffset(if compact then 300 else 380, 300),
		Parent = parent,
	})
	UIKit.ListLayout(toasts, { Gap = 10, HAlign = Enum.HorizontalAlignment.Right })
	UIKit.Toast(theme, { Text = L("ui.sample.toast"), Kind = "Reward", Width = if compact then 300 else 380, LayoutOrder = 1, Parent = toasts })
	UIKit.Toast(theme, { Text = L("ui.sample.toastLevel"), Kind = "Success", Width = if compact then 300 else 380, LayoutOrder = 2, Parent = toasts })
	-- avatar viewport (bottom left)
	if not compact then
		local kit = kits.Get("Determination")
		UIKit.Viewport(theme, {
			Color = if kit then kit.Color else c.Accent,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 60, 1, -40),
			Size = UDim2.fromOffset(260, 300),
			Parent = parent,
		})
		hudPreview(theme, "Battle", UDim2.fromOffset(420, 190), UDim2.new(1, -480, 1, -230)).Parent = parent
		hudPreview(theme, "Modern", UDim2.fromOffset(420, 190), UDim2.new(1, -480, 1, -460)).Parent = parent
	end
	-- modal (centre)
	local fell = kits.Get("FellSans")
	local modal = UIKit.Modal(theme, {
		Title = L("ui.sample.unlockTitle"),
		PanelSize = UDim2.fromOffset(if compact then 520 else 600, if compact then 250 else 300),
		Dim = 0.5,
		Buttons = {
			{ Text = L("common.back"), Variant = "Ghost", Width = if compact then 150 else 170 },
			{ Text = L("common.buy"), Variant = "Primary", Icon = "Gold", Width = if compact then 170 else 200, State = "Hover" },
		},
		ZIndex = 5,
	})
	modal.Root.BackgroundTransparency = 1
	local body = UIKit.Label(theme, {
		Text = L("ui.sample.unlockText", if fell then fell.Unlock.Gold else 0, if fell then pick(fell.Name) else "?"),
		Role = "Body",
		Dialogue = true,
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.fromScale(1, 1),
	})
	body.Parent = modal.Content
	modal.Root.Parent = parent
end

-- page assembly -------------------------------------------------------------------------------------
local function buildPage(theme: Theme, page: string, holder: Frame, canvas: Vector2, compact: boolean, hudId: string): GuiObject?
	local W, H = canvas.X, canvas.Y
	local margin = if compact then 22 else 36
	local top = 0
	local availW = W - margin * 2
	local availH = holder.Size.Y.Offset
	local default: GuiObject? = nil
	if page == "All" then
		local gap = 24
		local colA = 430
		local colC = 452
		local colB = availW - colA - colC - gap * 2
		local panelA1 = 424
		local buttons, first = buttonsPanel(theme, UDim2.fromOffset(colA, panelA1), UDim2.fromOffset(margin, top), false, 48)
		buttons.Parent = holder
		default = first
		controlsPanel(theme, UDim2.fromOffset(colA, availH - panelA1 - gap), UDim2.fromOffset(margin, top + panelA1 + gap), false, false).Parent = holder
		local bx = margin + colA + gap
		local cardsH = 334
		local barsH = 262
		cardsPanel(theme, UDim2.fromOffset(colB, cardsH), UDim2.fromOffset(bx, top), Vector2.new(math.floor((colB - 32 - 24) / 3), cardsH - 76)).Parent = holder
		barsPanel(theme, UDim2.fromOffset(colB, barsH), UDim2.fromOffset(bx, top + cardsH + gap), false).Parent = holder
		dialoguePanel(theme, UDim2.fromOffset(colB, availH - cardsH - barsH - gap * 2), UDim2.fromOffset(bx, top + cardsH + barsH + gap * 2)).Parent = holder
		iconsPanel(theme, UDim2.fromOffset(colC, availH), UDim2.fromOffset(bx + colB + gap, top), 48, 8, false).Parent = holder
	elseif page == "Controls" then
		local gap = 18
		local half = math.floor((availW - gap) / 2)
		local p, first = buttonsPanel(theme, UDim2.fromOffset(half, availH), UDim2.fromOffset(margin, top), compact)
		p.Parent = holder
		default = first
		controlsPanel(theme, UDim2.fromOffset(availW - half - gap, availH), UDim2.fromOffset(margin + half + gap, top), compact, true).Parent = holder
	elseif page == "Data" then
		local gap = 18
		local left = math.floor(availW * 0.54)
		local cardW = math.floor((left - 32 - 24) / 3)
		cardsPanel(theme, UDim2.fromOffset(left, availH), UDim2.fromOffset(margin, top), Vector2.new(cardW, availH - 76)).Parent = holder
		barsPanel(theme, UDim2.fromOffset(availW - left - gap, availH), UDim2.fromOffset(margin + left + gap, top), compact).Parent = holder
	elseif page == "Icons" then
		local cell = if compact then 52 else 64
		iconsPanel(theme, UDim2.fromOffset(availW, availH), UDim2.fromOffset(margin, top), cell, if compact then 6 else 10, true).Parent = holder
	elseif page == "Overlay" then
		overlayPage(theme, holder, Vector2.new(W, availH), compact, hudId)
	end
	return default
end

function Gallery.Create(theme: Theme, deps: any?): { Root: Frame, Destroy: () -> (), DefaultSelection: GuiObject?, SetPage: (string) -> () }
	local d = deps or {}
	local layout = d.Layout or { Canvas = Vector2.new(1600, 900), Compact = false, Phone = false, Scale = 1 }
	local canvas: Vector2 = layout.Canvas
	local compact: boolean = layout.Compact == true
	local page: string = d.Page or (if compact then "Controls" else "All")
	local hudId: string = d.Hud or "Battle"
	local c = theme.Colors

	local root = frame({ Name = "Gallery", Size = UDim2.fromScale(1, 1) })
	UIKit.Backdrop(theme, { Parent = root })

	-- header
	local margin = if compact then 22 else 36
	local headerH = if compact then 62 else 96
	local header = frame({ Name = "Header", Position = UDim2.fromOffset(margin, if compact then 8 else 18), Size = UDim2.new(1, -margin * 2, 0, headerH), ZIndex = 5, Parent = root })
	local title = UIKit.Title(theme, {
		Text = L("ui.gallery.title"),
		Role = "Title",
		TextSize = if compact then math.floor(theme.TextSize.Title * 0.8) else theme.TextSize.Title,
		Subtitle = if compact then nil else L("ui.gallery.subtitle", pick(theme.Name)),
		Size = UDim2.new(0, if compact then 380 else 640, 0, if compact then math.ceil(theme.TextSize.Title * 1.05) else math.ceil(theme.TextSize.Title * 1.3)),
		Position = UDim2.fromOffset(0, if compact then 4 else 0),
	})
	title.Root.Parent = header
	if compact then
		local themeBadge = UIKit.Badge(theme, { Text = pick(theme.Name), Color = c.Accent, Style = "Solid", Height = 22, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -2) })
		themeBadge.Parent = header
	end
	local pages = {
		{ Id = "All", Text = L("ui.gallery.page.all") },
		{ Id = "Controls", Text = L("ui.gallery.page.controls") },
		{ Id = "Data", Text = L("ui.gallery.page.data") },
		{ Id = "Icons", Text = L("ui.gallery.page.icons") },
		{ Id = "Overlay", Text = L("ui.gallery.page.overlay") },
	}
	if compact then
		table.remove(pages, 1)
	end
	local tabsWidth = if compact then 560 else 640
	local holder: Frame? = nil
	local defaultSelection: GuiObject? = nil
	local setPage: (string) -> ()
	local tabs = UIKit.Tabs(theme, {
		Items = pages,
		Selected = page,
		Height = if compact then 38 else 44,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, if compact then 6 else 4),
		Size = UDim2.fromOffset(tabsWidth, if compact then 38 else 44),
		OnChanged = function(id: string)
			setPage(id)
		end,
	})
	tabs.Root.Parent = header
	local hints = frame({
		Name = "Hints",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, if compact then -2 else -8),
		Size = UDim2.fromOffset(tabsWidth, 26),
		Parent = header,
	})
	if not compact then
		local hl = UIKit.ListLayout(hints, { Horizontal = true, Gap = 10, HAlign = Enum.HorizontalAlignment.Right, VAlign = Enum.VerticalAlignment.Center })
		hl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		UIKit.KeyHint(theme, { Key = "Q", Height = 24, LayoutOrder = 1, Parent = hints })
		UIKit.KeyHint(theme, { Key = "E", Label = L("ui.gallery.switch"), Height = 24, LayoutOrder = 2, Parent = hints })
		UIKit.KeyHint(theme, { Key = "ButtonB", Label = L("ui.back"), Height = 24, LayoutOrder = 3, Parent = hints })
	end

	local bodyTop = headerH + (if compact then 14 else 34)
	local bodyBottom = if compact then 14 else 28
	setPage = function(id: string)
		if holder then
			holder:Destroy()
		end
		page = id
		local newHolder = frame({
			Name = "Page_" .. id,
			Position = UDim2.fromOffset(0, bodyTop),
			Size = UDim2.new(1, 0, 0, canvas.Y - bodyTop - bodyBottom),
			ZIndex = 4,
			Parent = root,
		})
		holder = newHolder
		defaultSelection = buildPage(theme, id, newHolder, canvas, compact, hudId)
		tabs.Select(id)
	end
	setPage(page)

	return {
		Root = root,
		DefaultSelection = defaultSelection,
		SetPage = setPage,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

return Gallery
