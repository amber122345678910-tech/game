--!strict
-- Screens/Admin: the owner's admin panel, mobile first (SPEC §10 screen contract). A right-side panel (the world
-- stays visible on the left and the panel never sits under the Roblox top-bar buttons) with four tabs, touch
-- targets of at least 44 pt (TAP = 44 / UI scale design px) and an in-panel result line: server Notify toasts are
-- mirrored there because the HUD's own toasts are drawn under the menu layer.
--   MATCH    your side (Human / Monster), kit cards, map chips, bots stepper -> sticky START NOW
--            (Admin {action = "StartNow", side, kitId, mapId?, bots}); round control (SkipPhase, FinalPhase, Collapse,
--            EndRound {winner}, SetMap {mapId}); bots (AddBot {team}, SpawnDummy, ClearBots); solo rounds toggle
--            (SetMinPlayers {n = 1 | 2})
--   ME       quick actions (Heal, FullUlt, ResetCooldowns, TeleportLobby, TeleportArena), God / NoCooldowns
--            toggles, Speed x1..x3, kit cards -> BecomeKit {kitId}
--   PROGRESS AddGold {n}, AddLevels {n}, UnlockAll, ResetProfile {confirm = true} behind a confirm step
--   TEST     MUSIC (client only, no server request): preview buttons for the monster themes (Theme_<kit>,
--            Theme_<kit>_Final), Lobby, VerdictBox, FinalPhase and CollapsePhase -> deps.Sound.PreviewMusic(key) (sticky), Stop ->
--            PreviewMusic(nil) (automatic music again), and a live line from deps.Sound.NowPlaying(): track key
--            (-> the Audio entry that supplies it), the id in use (#n of the entry's candidates) and its check status;
--            then BoxNearest, DamageMe {n}, AddKR {n}, GiveDodges0
-- Requests go through Common.Request(deps, "Admin", data) (StateController.Request, else Net "Request"); the
-- server (AdminService) validates everything again. Toggle states mirror the LocalPlayer attributes AdminGod /
-- AdminNoCooldowns / AdminSpeed / AdminSolo and update live. Panel choices (tab, side, kits, map, bots, last result)
-- live in module state, so theme / language rebuilds keep them.
--
--   Admin.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnAction(action) -> boolean, Select(tabId) }
--   deps: UI (UIController: Back), State (Request, Notify, Profile, ProfileChanged, Round, LocalCharacter,
--         CharacterChanged), Sound (SoundController: PreviewMusic, NowPlaying), Layout  (+ offline: Tab =
--         "Match"|"Me"|"Progress"|"Test", Attrs {AdminGod = true, ...}, Profile, Round, PlayerCount,
--         Feedback = {Text, Kind})
--   Admin.Tabs = {"Match", "Me", "Progress", "Test"}      Admin.State() -> the module state (tests)

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Admin = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

local TABS = { "Match", "Me", "Progress", "Test" }
Admin.Tabs = TABS
local TAB_KEY: { [string]: string } = {
	Match = "admin.tab.match",
	Me = "admin.tab.me",
	Progress = "admin.tab.progress",
	Test = "admin.tab.test",
}
local SPEEDS = { 1, 1.5, 2, 3 }
local FEEDBACK_TIME = 5
local RESET_ARM_TIME = 6
-- TEST -> MUSIC: SoundController.Status values -> string key + theme colour name
local MUSIC_STATUS: { [string]: { Key: string, Tone: string } } = {
	ok = { Key = "admin.music.st.ok", Tone = "Success" },
	pending = { Key = "admin.music.st.pending", Tone = "Warning" },
	dead = { Key = "admin.music.st.dead", Tone = "Danger" },
	empty = { Key = "admin.music.st.empty", Tone = "TextDim" },
}
local MUSIC_TRACKS = { -- shared tracks next to the monster themes: { key, label, icon }
	{ "Lobby", "admin.music.lobby", "Music" },
	{ "VerdictBox", "admin.music.box", "Box" },
	{ "FinalPhase", "admin.music.finalPhase", "Flame" },
	{ "CollapsePhase", "admin.music.collapse", "Target" },
}

-- panel state survives screen rebuilds (theme / language switches rebuild every screen)
local state = {
	Tab = "Match",
	Side = "Human",
	Kit = {} :: { [string]: string },
	Map = "",
	Bots = {} :: { [string]: number },
	ResetArmedUntil = 0,
	Feedback = nil :: { Text: string, Kind: string, At: number }?,
}

function Admin.State(): any
	return state
end

local function luminance(color: Color3): number
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

local function sortedKits(kits: any, role: string): { any }
	local list: { any } = {}
	if kits then
		for _, kit in kits.ForRole(role) do
			table.insert(list, kit)
		end
	end
	table.sort(list, function(a: any, b: any): boolean
		return (a.Order or 0) < (b.Order or 0)
	end)
	return list
end

local function mapList(): { any }
	local out: { any } = {}
	local registry = Common.Module({ "Maps", "Registry" })
	if registry then
		local ok, list = pcall(registry.List)
		if ok and type(list) == "table" then
			for _, meta in list do
				if meta.Kind ~= "Lobby" and meta.Available ~= false then
					table.insert(out, meta)
				end
			end
		end
	end
	return out
end

-- a signature colour per map from its graphics preset (fog / ambient), for the chip strip
local function mapColor(meta: any, fallback: Color3): Color3
	local presets = Common.Module({ "Graphics", "Presets" })
	if presets == nil or type(meta) ~= "table" then
		return fallback
	end
	local ok, preset = pcall(presets.Get, meta.Preset)
	if not ok or type(preset) ~= "table" then
		return fallback
	end
	local candidates = {
		preset.Atmosphere and preset.Atmosphere.Decay,
		preset.Lighting and preset.Lighting.ColorShift_Top,
		preset.Lighting and preset.Lighting.OutdoorAmbient,
	}
	for _, color in candidates do
		if typeof(color) == "Color3" and luminance(color) > 0.08 then
			local h, s, v = color:ToHSV()
			return Color3.fromHSV(h, math.clamp(s * 1.15, 0, 1), math.max(v, 0.75))
		end
	end
	return fallback
end

function Admin.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local layout = Common.Layout(d)
	local phone = layout.Phone == true
	local canvas: Vector2 = layout.Canvas
	local uiScale: number = if type(layout.Scale) == "number" and layout.Scale > 0 then layout.Scale else 1
	local TAP = math.max(if phone then 50 else 44, math.ceil(44 / uiScale)) -- >= 44 pt on screen
	local GAP = if phone then 6 else 8
	local classic = theme.Id == "Classic"
	local bag = Common.Bag()
	local kits = Common.Kits()
	local config = Common.Config()
	local preview = Common.IsPreview(d)
	if type(d.Tab) == "string" and TAB_KEY[d.Tab] then
		state.Tab = d.Tab
	end
	if type(d.Feedback) == "table" then
		state.Feedback =
			{ Text = tostring(d.Feedback.Text), Kind = tostring(d.Feedback.Kind or "Success"), At = os.clock() }
	end
	local botDefault: number = if config and config.Practice then config.Practice.BotHumans else 3
	state.Bots.Monster = state.Bots.Monster or botDefault
	state.Bots.Human = state.Bots.Human or math.max(0, botDefault - 1)

	local textSize = if classic
		then theme.TextSize.Small + (if phone then 0 else 1)
		else theme.TextSize.Small + (if phone then 0 else 2)
	local thin = if classic then 2 else 1
	local thick = if classic then 3 else 2

	local function send(data: { [string]: any })
		Common.Request(d, "Admin", data)
	end

	-- root, shade, panel -----------------------------------------------------------------------------------
	local root = frame({ Name = "Admin", Size = UDim2.fromScale(1, 1) })
	local margin = if phone then 8 else 24
	local panelW = if phone
		then math.floor(math.clamp(canvas.X * 0.6, 520, canvas.X - margin * 2))
		else math.min(660, math.floor(canvas.X - margin * 2))
	local shade = frame({
		Name = "Shade",
		BackgroundTransparency = 0,
		BackgroundColor3 = c.Background,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, panelW + margin * 2 + 160, 1, 0),
		Parent = root,
	})
	Common.Gradient(shade, nil, Common.NSeq({ { 0, 1 }, { 0.25, 0.62 }, { 1, 0.3 } }), 0)
	if preview then
		local world = UIKit.Backdrop(theme, { Name = "PreviewWorld" })
		world.ZIndex = 0
		world.Parent = root
		shade.ZIndex = 1
	end
	local pad = if phone then 8 else 16
	local panel = UIKit.Panel(theme, {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -margin, 0, margin),
		Size = UDim2.new(0, panelW, 1, -margin * 2),
		Padding = pad,
	})
	panel.Root.ZIndex = 2
	panel.Root.Parent = root
	local content = panel.Content
	local contentW = panelW - pad * 2
	local contentH = canvas.Y - margin * 2 - pad * 2
	local function cellWidth(cols: number): number
		return math.floor((contentW - 10 - GAP * (cols - 1)) / cols)
	end
	-- rough glyph width / font size per theme (keeps the longest word of a card name on one line)
	local lang = (function(): string
		local strings = Common.Strings()
		local ok, value = pcall(function()
			return strings.Language()
		end)
		return if ok and type(value) == "string" then value else "en"
	end)()
	local glyph = if classic
		then (if lang == "ru" then 0.72 else 1.0)
		elseif theme.Id == "Void" then 0.8
		elseif theme.Id == "Fell" then 0.52
		else 0.62

	local function close()
		local ui = d.UI
		if ui and type(ui.Back) == "function" then
			ui.Back()
		elseif ui and type(ui.Close) == "function" then
			ui.Close("Admin")
		end
	end

	-- header: crown + (phone: tabs | desktop: title) + close ----------------------------------------------------
	local head = frame({ Name = "Head", Size = UDim2.new(1, 0, 0, TAP), Parent = content })
	local crown = frame({
		Name = "Crown",
		BackgroundTransparency = if theme.Id == "Void" then 0.35 else 0,
		BackgroundColor3 = c.PanelInset,
		Size = UDim2.fromOffset(TAP, TAP),
		Parent = head,
	})
	Common.Corner(crown, if theme.Id == "Void" then UDim.new(0.5, 0) else theme.SmallCorner)
	local crownStroke = Common.Stroke(crown, c.Gold, thick, 0, theme.LineJoin)
	if theme.Gradients.Stroke then
		Common.Gradient(crownStroke, theme.Gradients.Stroke, nil, 45)
	end
	local crownIcon = Icons.Create("Crown", c.Gold, UDim2.fromScale(0.62, 0.62), c.Accent2)
	crownIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	crownIcon.Position = UDim2.fromScale(0.5, 0.5)
	crownIcon.Parent = crown
	local closeBtn = UIKit.Button(theme, {
		Name = "Close",
		Variant = "Icon",
		Icon = "Close",
		Height = TAP,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		OnActivated = close,
	})
	closeBtn.Root.Parent = head

	local selectTab: (string) -> ()
	local tabItems = {}
	for _, id in TABS do
		table.insert(tabItems, { Id = id, Text = L(TAB_KEY[id]) })
	end
	local tabs = UIKit.Tabs(theme, {
		Items = tabItems,
		Selected = state.Tab,
		Height = TAP,
		OnChanged = function(id: string)
			selectTab(id)
		end,
	})
	local listTop: number
	if phone then
		tabs.Root.Position = UDim2.fromOffset(TAP + GAP, 0)
		tabs.Root.Size = UDim2.new(1, -(TAP + GAP) * 2, 0, TAP)
		tabs.Root.Parent = head
		listTop = TAP + GAP
	else
		local title = UIKit.Title(theme, {
			Text = L("admin.title"),
			Role = "Title",
			TextSize = math.floor(theme.TextSize.Title * 0.82),
			Subtitle = L("admin.subtitle"),
			Size = UDim2.new(1, -(TAP * 2 + 32), 0, math.ceil(theme.TextSize.Title * 0.82 * 1.2)),
			Position = UDim2.fromOffset(TAP + 16, 0),
			Glow = false,
		})
		title.Root.Parent = head
		tabs.Root.Position = UDim2.fromOffset(0, TAP + GAP + 4)
		tabs.Root.Size = UDim2.new(1, 0, 0, TAP)
		tabs.Root.Parent = content
		listTop = TAP * 2 + GAP * 2 + 4
	end

	-- status line (bottom) + sticky START NOW (MATCH) -------------------------------------------------------
	local statusH = if phone then 22 else 28
	local status = frame({
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, statusH),
		Parent = content,
	})
	local statusTop = frame({
		Name = "Rule",
		BackgroundTransparency = if classic then 0 else 0.5,
		BackgroundColor3 = c.StrokeDim,
		Size = UDim2.new(1, 0, 0, if classic then 2 else 1),
		Parent = status,
	})
	statusTop.ZIndex = 2
	local statusIconHolder = frame({
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 1),
		Size = UDim2.fromOffset(statusH - 6, statusH - 6),
		Parent = status,
	})
	local statusText = UIKit.Label(theme, {
		Name = "Text",
		Text = "",
		Role = "Mono",
		TextSize = if classic then (if phone then 8 else 9) else (if phone then 12 else 14),
		Tone = "Dim",
		Truncate = true,
		Position = UDim2.new(0, statusH, 0, 1),
		Size = UDim2.new(1, -statusH, 1, -1),
		Parent = status,
	})
	local statusIconName = ""
	local function setStatusIcon(name: string, color: Color3)
		if name ~= statusIconName then
			statusIconName = name
			for _, child in statusIconHolder:GetChildren() do
				child:Destroy()
			end
			local icon = Icons.Create(name, color, UDim2.fromScale(1, 1))
			icon.Parent = statusIconHolder
		end
	end

	local startBtn = UIKit.Button(theme, {
		Name = "StartNow",
		Text = L("admin.startNow"),
		Icon = "Play",
		Variant = "Primary",
		Height = TAP,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(statusH + GAP)),
		OnActivated = function()
			local side = state.Side
			local data: { [string]: any } = { action = "StartNow", side = side, bots = state.Bots[side] }
			if state.Kit[side] then
				data.kitId = state.Kit[side]
			end
			if state.Map ~= "" then
				data.mapId = state.Map
			end
			send(data)
		end,
	})
	startBtn.Root.Size = UDim2.new(1, 0, 0, TAP)
	startBtn.Root.Parent = content

	local function infoLine(): string
		local round = Common.Round(d)
		local ph = tostring(round.Phase or "Waiting")
		local phaseText = if Common.Has("round.phase." .. ph) then L("round.phase." .. ph) else ph
		local count = d.PlayerCount
		if type(count) ~= "number" then
			local ok, n = pcall(function()
				return #game:GetService("Players"):GetPlayers()
			end)
			count = if ok and type(n) == "number" and n > 0 then n else 1
		end
		local role = tostring(Common.PlayerAttr(d, "Role", "Lobby"))
		local roleText = if Common.Has("admin.role." .. role) then L("admin.role." .. role) else role
		return L("admin.status", phaseText, count, roleText)
	end

	local KIND_COLOR: { [string]: Color3 } = {
		Success = c.Success,
		Warning = c.Warning,
		Danger = c.Danger,
		Info = c.Info,
		Pending = c.TextDim,
	}
	local KIND_ICON: { [string]: string } =
		{ Success = "Check", Warning = "Info", Danger = "Close", Info = "Info", Pending = "Clock" }
	local function renderStatus()
		local fb = state.Feedback
		if fb and os.clock() - fb.At < FEEDBACK_TIME then
			local color = KIND_COLOR[fb.Kind] or c.Text
			statusText.Text = fb.Text
			statusText.TextColor3 = color
			setStatusIcon(KIND_ICON[fb.Kind] or "Info", color)
		else
			statusText.Text = infoLine()
			statusText.TextColor3 = c.TextDim
			setStatusIcon("Info", c.TextMuted)
		end
	end
	renderStatus()
	local acc = 0
	bag.Add(Motion.Loop(statusText, function(dt: number)
		acc += dt
		if acc > 0.5 then
			acc = 0
			renderStatus()
		end
	end))
	local state_ = d.State
	if state_ and state_.Notify then
		bag.Connect(state_.Notify, function(key: any, args: any, style: any)
			if type(key) ~= "string" then
				return
			end
			local text = if type(args) == "table" then L(key, table.unpack(args)) else L(key)
			local kind = tostring(style or "Info")
			local lower = string.lower(kind)
			kind = if lower == "success" or lower == "good"
				then "Success"
				elseif lower == "warning" or lower == "warn" then "Warning"
				elseif lower == "danger" or lower == "error" or lower == "bad" then "Danger"
				else "Info"
			state.Feedback = { Text = text, Kind = kind, At = os.clock() }
			renderStatus()
		end)
	end

	-- pages ---------------------------------------------------------------------------------------------------
	local pagesH = contentH - listTop - statusH - GAP
	local pages: { [string]: any } = {}
	local builders: { [string]: (any) -> () } = {}
	-- per page: refresh toggles / selections from attributes (replaced when a page is rebuilt)
	local syncersByPage: { [string]: { () -> () } } = {}
	local syncers: { () -> () } = {} -- the list of the page being built
	local first: GuiObject? = nil

	local function pageFor(id: string): any
		local page = pages[id]
		if page == nil then
			page = UIKit.List(theme, { Name = "Page_" .. id, Gap = GAP })
			page.Root.Position = UDim2.fromOffset(0, listTop)
			page.Root.Visible = false
			page.Root.Parent = content
			pages[id] = page
		end
		return page
	end

	local orderCounter = 0
	local function nextOrder(): number
		orderCounter += 1
		return orderCounter
	end

	local function section(page: any, key: string, icon: string)
		local h = if phone then 24 else 30
		local row = frame({ Name = "Section_" .. key, Size = UDim2.new(1, -10, 0, h), LayoutOrder = nextOrder() })
		local ic = UIKit.Icon(icon, c.Accent, if phone then 15 else 18)
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 0, 0.5, -1)
		ic.Parent = row
		UIKit.Label(theme, {
			Text = UIKit.Upper(L(key)),
			Role = "Caption",
			Tone = "Accent",
			Truncate = true,
			Position = UDim2.fromOffset(if phone then 22 else 26, 0),
			Size = UDim2.new(1, -(if phone then 22 else 26), 1, -3),
			Parent = row,
		})
		UIKit.Divider(theme, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			Parent = row,
		})
		page.Add(row)
	end

	local function caption(page: any, text: string, wrapLines: number?)
		local lines = wrapLines or 1
		local size = if classic then (if phone then 8 else 9) else (if phone then 12 else 14)
		UIKit.Label(theme, {
			Name = "Caption",
			Text = text,
			Role = "Caption",
			Tone = "Dim",
			TextSize = size,
			Wrap = lines > 1,
			Truncate = lines == 1,
			Size = UDim2.new(1, -10, 0, math.ceil(size * 1.45) * lines + 2),
			LayoutOrder = nextOrder(),
			Parent = page.Content,
		})
	end

	-- a grid container of `count` cells in `cols` columns (cells are TAP tall)
	local function grid(page: any, cols: number, count: number, cellH: number?): Frame
		local h = cellH or TAP
		local rows = math.max(1, math.ceil(count / cols))
		local g = frame({
			Name = "Grid",
			Size = UDim2.new(1, -10, 0, rows * h + (rows - 1) * GAP),
			LayoutOrder = nextOrder(),
		})
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.new(1 / cols, -math.ceil(GAP * (cols - 1) / cols), 0, h)
		gl.CellPadding = UDim2.fromOffset(GAP, GAP)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = g
		page.Add(g)
		return g
	end

	-- button labels shrink to fit their cell (long Russian labels, narrow phone grids)
	local compactSize = if classic then (if phone then 11 else 13) else theme.TextSize.Button - (if phone then 4 else 2)
	local function fit(label: TextLabel, size: number)
		label.TextSize = size
		label.TextScaled = true
		local con = Instance.new("UITextSizeConstraint")
		con.MaxTextSize = size
		con.MinTextSize = 7
		con.Parent = label
	end

	local function button(parent: Instance, props: { [string]: any }, order: number): any
		local b = UIKit.Button(theme, {
			Name = props.Name,
			Text = props.Text,
			Icon = props.Icon,
			Variant = props.Variant or "Secondary",
			Height = props.Height or TAP,
			Selected = props.Selected,
			Disabled = props.Disabled,
			LayoutOrder = order,
			OnActivated = props.OnActivated,
		})
		fit(b.Label, props.TextSize or compactSize)
		b.Root.Parent = parent
		first = first or b.Root
		return b
	end

	local function wide(page: any, props: { [string]: any }): any
		props.TextSize = props.TextSize
			or (if classic then (if phone then 13 else 15) else theme.TextSize.Button - (if phone then 2 else 0))
		local b = button(page.Content, props, nextOrder())
		b.Root.Size = UDim2.new(1, -10, 0, props.Height or TAP)
		return b
	end

	-- a selectable card: colour tile + icon (kits) or a colour strip (maps) + name; Classic marks the pick with the SOUL
	local function card(parent: Instance, opts: { [string]: any }): (boolean) -> ()
		local h: number = opts.Height or TAP
		local selectedNow = opts.Selected == true
		local hovering = false
		local btn = Instance.new("TextButton")
		btn.Name = opts.Name or "Card"
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.BackgroundTransparency = if theme.Id == "Void" then 0.3 else 0
		btn.BackgroundColor3 = c.PanelAlt
		btn.Size = UDim2.new(1, 0, 0, h)
		btn.LayoutOrder = opts.Order or 0
		btn.Selectable = true
		btn.SelectionImageObject = frame({ Name = "NoSelectionBox" })
		Common.Corner(btn, if theme.Id == "Void" then UDim.new(0, 10) else theme.SmallCorner)
		local stroke = Common.Stroke(btn, c.StrokeDim, thin, 0, theme.LineJoin)
		local x = 10
		local tileCorner: UDim2? = nil -- the pick mark sits on the tile's corner when there is a tile
		if typeof(opts.Color) == "Color3" then
			local color: Color3 = opts.Color
			local tileSize = h - 16
			local tile = frame({
				Name = "Tile",
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.fromOffset(tileSize, tileSize),
				Parent = btn,
			})
			Common.Corner(tile, if classic or theme.Id == "Fell" then UDim.new(0, 0) else UDim.new(0, 6))
			Common.Stroke(tile, Color3.new(0, 0, 0), if classic then 2 else 1, 0.35)
			Common.Gradient(tile, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)), nil, 90)
			if opts.Icon then
				local iconColor = if luminance(color) > 0.6 then Color3.fromRGB(16, 16, 16) else Color3.new(1, 1, 1)
				local icon = Icons.Create(opts.Icon, iconColor, UDim2.fromScale(0.64, 0.64))
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.fromScale(0.5, 0.5)
				icon.Parent = tile
			end
			x = 8 + tileSize + 9
			tileCorner = UDim2.fromOffset(9, math.floor((h - tileSize) / 2) + 1) -- top-left: clear of the name
		elseif typeof(opts.Strip) == "Color3" then
			local strip = frame({
				Name = "Strip",
				BackgroundTransparency = 0,
				BackgroundColor3 = opts.Strip,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.new(0, if classic then 6 else 5, 1, -16),
				Parent = btn,
			})
			Common.Corner(strip, if classic then UDim.new(0, 0) else UDim.new(0.5, 0))
			x = 20
		end
		local markW = if tileCorner then 0 else 18
		local text: string = opts.Text
		local size = textSize
		if type(opts.Width) == "number" then
			local longest = 1
			for word in string.gmatch(text, "%S+") do
				longest = math.max(longest, utf8.len(word) or #word)
			end
			local labelW = opts.Width - x - markW - 6
			size = math.max(7, math.min(textSize, math.floor(labelW / (longest * glyph))))
		end
		local label = UIKit.Label(theme, {
			Name = "Name",
			Text = if theme.Uppercase then UIKit.Upper(text) else text,
			Role = "Button",
			TextSize = size,
			Wrap = string.find(text, " ", 1, true) ~= nil, -- one long word shrinks instead of breaking mid-word
			Scaled = true,
			MaxTextSize = size,
			MinTextSize = 7,
			Position = UDim2.fromOffset(x, 3),
			Size = UDim2.new(1, -(x + markW + 6), 1, -6),
			Parent = btn,
		})
		local glyphMark: Frame = if classic then UIKit.Heart(c.SoulRed, 13) else Icons.Create("Check", c.Selected, 15)
		local mark: Frame = glyphMark
		if tileCorner then
			-- a small badge on the tile corner (readable on any kit colour)
			mark = frame({
				Name = "Badge",
				BackgroundTransparency = 0,
				BackgroundColor3 = c.Panel,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = tileCorner,
				Size = UDim2.fromOffset(19, 19),
				ZIndex = 4,
			})
			Common.Corner(mark, if classic or theme.Id == "Fell" then UDim.new(0, 0) else UDim.new(0.5, 0))
			Common.Stroke(mark, c.Selected, if classic then 2 else 1.5, 0, theme.LineJoin)
			glyphMark.AnchorPoint = Vector2.new(0.5, 0.5)
			glyphMark.Position = UDim2.fromScale(0.5, 0.5)
			glyphMark.Size = UDim2.fromOffset(13, 13)
			glyphMark.ZIndex = 5
			glyphMark.Parent = mark
		else
			mark.AnchorPoint = Vector2.new(1, 0.5)
			mark.Position = UDim2.new(1, -7, 0.5, 0)
		end
		mark.Parent = btn
		local function paint()
			stroke.Color = if selectedNow then c.Selected elseif hovering then c.Hover else c.StrokeDim
			stroke.Thickness = if selectedNow then thick else thin
			label.TextColor3 = if selectedNow then c.Selected elseif hovering then c.Hover else c.Text
			btn.BackgroundColor3 = if selectedNow then c.PanelInset else c.PanelAlt
			mark.Visible = selectedNow
		end
		paint()
		Motion.Hover(btn, function()
			hovering = true
			paint()
			Motion.Sound(theme.Sounds.Hover)
		end, function()
			hovering = false
			paint()
		end)
		Motion.On(btn, "Activated", function()
			Motion.Sound(theme.Sounds.Select)
			if opts.OnActivated then
				opts.OnActivated()
			end
		end)
		btn.Parent = parent
		first = first or btn
		return function(v: boolean)
			selectedNow = v
			paint()
		end
	end

	-- one-of-N row of buttons (sides, speed)
	local function segmented(
		page: any,
		labelText: string?,
		options: { { Id: string, Text: string, Icon: string? } },
		current: string,
		onPick: (string) -> ()
	): (string) -> ()
		local row = frame({ Name = "Segmented", Size = UDim2.new(1, -10, 0, TAP), LayoutOrder = nextOrder() })
		local x = 0
		if labelText then
			local lw = if phone then 120 else 150
			UIKit.Label(
				theme,
				{ Text = labelText, Role = "Body", Truncate = true, Size = UDim2.new(0, lw - 8, 1, 0), Parent = row }
			)
			x = lw
		end
		local holder =
			frame({ Name = "Options", Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x, 1, 0), Parent = row })
		local hl = UIKit.ListLayout(holder, { Horizontal = true, Gap = GAP })
		hl.HorizontalFlex = Enum.UIFlexAlignment.Fill
		local handles: { [string]: any } = {}
		for i, o in options do
			local b = button(holder, {
				Name = "Opt_" .. o.Id,
				Text = o.Text,
				Icon = o.Icon,
				Selected = o.Id == current,
				OnActivated = function()
					for id, h in handles do
						h.SetSelected(id == o.Id)
					end
					onPick(o.Id)
				end,
			}, i)
			b.Root.Size = UDim2.new(0, 60, 1, 0)
			handles[o.Id] = b
		end
		page.Add(row)
		return function(id: string)
			for oid, h in handles do
				h.SetSelected(oid == id)
			end
		end
	end

	local function toggle(page: any, key: string, value: boolean, onChanged: (boolean) -> ()): any
		local t = UIKit.Toggle(theme, {
			Name = "Toggle_" .. key,
			Label = L(key),
			Value = value,
			Height = TAP,
			OnChanged = onChanged,
			LayoutOrder = nextOrder(),
		})
		t.Root.Size = UDim2.new(1, -10, 0, TAP)
		page.Add(t.Root)
		first = first or t.Root
		return t
	end

	local function stepper(
		page: any,
		labelText: string,
		value: number,
		min: number,
		max: number,
		onChanged: (number) -> ()
	)
		local row = frame({ Name = "Stepper", Size = UDim2.new(1, -10, 0, TAP), LayoutOrder = nextOrder() })
		UIKit.Label(theme, {
			Text = labelText,
			Role = "Body",
			Truncate = true,
			Size = UDim2.new(1, -(TAP * 2 + 90), 1, 0),
			Parent = row,
		})
		local current = value
		local valueLabel = UIKit.Label(theme, {
			Name = "Value",
			Text = tostring(current),
			Role = "Number",
			XAlign = "Center",
			Tone = "Accent",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(TAP + GAP), 0, 0),
			Size = UDim2.new(0, 90 - GAP * 2, 1, 0),
			Parent = row,
		})
		local minus: any, plus: any
		local function refresh()
			valueLabel.Text = tostring(current)
			minus.SetDisabled(current <= min)
			plus.SetDisabled(current >= max)
		end
		minus = UIKit.Button(theme, {
			Name = "Minus",
			Variant = "Icon",
			Icon = "Minus",
			Height = TAP,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(TAP + 90), 0, 0),
			Parent = row,
			OnActivated = function()
				if current > min then
					current -= 1
					onChanged(current)
					refresh()
				end
			end,
		})
		plus = UIKit.Button(theme, {
			Name = "Plus",
			Variant = "Icon",
			Icon = "Plus",
			Height = TAP,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Parent = row,
			OnActivated = function()
				if current < max then
					current += 1
					onChanged(current)
					refresh()
				end
			end,
		})
		refresh()
		page.Add(row)
	end

	local function attr(name: string, default: any): any
		return Common.PlayerAttr(d, name, default)
	end

	local function equippedKit(role: string): string?
		local profile = Common.Profile(d)
		return Common.EquippedKit(profile, role)
	end

	local function build(id: string, page: any)
		orderCounter = 0
		syncers = {}
		syncersByPage[id] = syncers
		builders[id](page)
	end

	local function rebuild(id: string)
		local page = pages[id]
		if page then
			page.Clear()
			build(id, page)
		end
	end

	-- MATCH ---------------------------------------------------------------------------------------------------
	local nextMapBtn: any = nil
	builders.Match = function(page: any)
		local side = state.Side
		if not phone then
			section(page, "admin.sec.start", "Play") -- phones: the sticky START NOW says it (saves a row)
		end
		segmented(
			page,
			nil,
			{
				{ Id = "Human", Text = L("admin.side.Human"), Icon = "Heart" },
				{ Id = "Monster", Text = L("admin.side.Monster"), Icon = "Skull" },
			},
			side,
			function(id: string)
				if id ~= state.Side then
					state.Side = id
					task.defer(rebuild, "Match")
				end
			end
		)
		caption(page, UIKit.Upper(L("admin.kit")))
		local roleKits = sortedKits(kits, side)
		local chosen = state.Kit[side] or equippedKit(side) or (if roleKits[1] then roleKits[1].Id else nil)
		local kitGrid = grid(page, 3, #roleKits)
		local kitW = cellWidth(3)
		local setters: { [string]: (boolean) -> () } = {}
		for i, kit in roleKits do
			setters[kit.Id] = card(kitGrid, {
				Name = "Kit_" .. kit.Id,
				Text = pick(kit.Name),
				Color = kit.Color,
				Icon = Common.KitIcon(kit),
				Width = kitW,
				Selected = kit.Id == chosen,
				Order = i,
				OnActivated = function()
					state.Kit[side] = kit.Id
					for id, set in setters do
						set(id == kit.Id)
					end
				end,
			})
		end
		caption(page, UIKit.Upper(L("admin.map")))
		local maps = mapList()
		local mapGrid = grid(page, 3, #maps + 1)
		local mapW = cellWidth(3)
		local mapSetters: { [string]: (boolean) -> () } = {}
		local function pickMap(id: string)
			state.Map = id
			for mid, set in mapSetters do
				set(mid == id)
			end
			if nextMapBtn then
				nextMapBtn.SetDisabled(id == "")
			end
		end
		mapSetters[""] = card(mapGrid, {
			Name = "Map_Random",
			Text = L("admin.map.random"),
			Strip = c.TextMuted,
			Width = mapW,
			Selected = state.Map == "",
			Order = 0,
			OnActivated = function()
				pickMap("")
			end,
		})
		for i, meta in maps do
			mapSetters[meta.Id] = card(mapGrid, {
				Name = "Map_" .. meta.Id,
				Text = pick(meta.Name),
				Strip = mapColor(meta, c.Accent),
				Width = mapW,
				Selected = state.Map == meta.Id,
				Order = i,
				OnActivated = function()
					pickMap(meta.Id)
				end,
			})
		end
		if side == "Monster" then
			stepper(page, L("admin.bots.humans"), state.Bots.Monster, 1, 8, function(n: number)
				state.Bots.Monster = n
			end)
		else
			stepper(page, L("admin.bots.allies"), state.Bots.Human, 0, 5, function(n: number)
				state.Bots.Human = n
			end)
		end

		section(page, "admin.sec.round", "Flag")
		local roundGrid = grid(page, 3, 6)
		local roundActions = {
			{ "admin.skip", "Rewind", { action = "SkipPhase" } },
			{ "admin.final", "Eye", { action = "FinalPhase" } },
			{ "admin.phase3", "Skull", { action = "Phase3" } },
			{ "admin.collapse", "Target", { action = "Collapse" } },
			{ "admin.endHumans", "Heart", { action = "EndRound", winner = "Humans" } },
			{ "admin.endMonster", "Skull", { action = "EndRound", winner = "Monster" } },
		}
		for i, a in roundActions do
			local data = a[3]
			button(roundGrid, {
				Text = L(a[1]),
				Icon = a[2],
				OnActivated = function()
					send(data)
				end,
			}, i)
		end
		nextMapBtn = button(roundGrid, {
			Name = "NextMap",
			Text = L("admin.setMap"),
			Icon = "Map",
			Disabled = state.Map == "",
			OnActivated = function()
				if state.Map ~= "" then
					send({ action = "SetMap", mapId = state.Map })
				end
			end,
		}, 6)

		section(page, "admin.sec.bots", "Users")
		local botGrid = grid(page, 2, 4)
		button(botGrid, {
			Text = L("admin.addHuman"),
			Icon = "Heart",
			OnActivated = function()
				send({ action = "AddBot", team = "Humans" })
			end,
		}, 1)
		button(botGrid, {
			Text = L("admin.addMonster"),
			Icon = "Skull",
			OnActivated = function()
				send({ action = "AddBot", team = "Monster" })
			end,
		}, 2)
		button(botGrid, {
			Text = L("admin.dummy"),
			Icon = "Target",
			OnActivated = function()
				send({ action = "SpawnDummy", count = 1 })
			end,
		}, 3)
		button(botGrid, {
			Text = L("admin.clearBots"),
			Icon = "Close",
			Variant = "Ghost",
			OnActivated = function()
				send({ action = "ClearBots" })
			end,
		}, 4)

		local soloToggle = toggle(page, "admin.solo", attr("AdminSolo", false) == true, function(on: boolean)
			send({ action = "SetMinPlayers", n = if on then 1 else 2 })
		end)
		table.insert(syncers, function()
			soloToggle.Set(attr("AdminSolo", false) == true)
		end)
		caption(page, L("admin.solo.hint"), 2)
	end

	-- ME ------------------------------------------------------------------------------------------------------
	local function wornKit(): string?
		local s = d.State
		if s and type(s.LocalCharacter) == "function" then
			local ok, model = pcall(s.LocalCharacter)
			if ok and typeof(model) == "Instance" then
				local id = model:GetAttribute("KitId")
				return if type(id) == "string" then id else nil
			end
		end
		return if type(d.WornKit) == "string" then d.WornKit else nil
	end

	builders.Me = function(page: any)
		section(page, "admin.sec.quick", "Bolt")
		local quick = {
			{ "admin.heal", "Heart", { action = "Heal" } },
			{ "admin.ult", "Bolt", { action = "FullUlt" } },
			{ "admin.cooldowns", "Clock", { action = "ResetCooldowns" } },
			{ "admin.tpLobby", "Portal", { action = "TeleportLobby" } },
			{ "admin.tpArena", "Teleport", { action = "TeleportArena" } },
		}
		local quickGrid = grid(page, 3, #quick)
		for i, a in quick do
			local data = a[3]
			button(quickGrid, {
				Text = L(a[1]),
				Icon = a[2],
				OnActivated = function()
					send(data)
				end,
			}, i)
		end

		section(page, "admin.sec.cheats", "Shield")
		local god = toggle(page, "admin.god", attr("AdminGod", false) == true, function(on: boolean)
			send({ action = "God", on = on })
		end)
		local noCd = toggle(page, "admin.noCd", attr("AdminNoCooldowns", false) == true, function(on: boolean)
			send({ action = "NoCooldowns", on = on })
		end)
		local speedOptions = {}
		for _, mult in SPEEDS do
			table.insert(speedOptions, { Id = tostring(mult), Text = "x" .. tostring(mult) })
		end
		local speedNow = tonumber(attr("AdminSpeed", 1)) or 1
		caption(page, UIKit.Upper(L("admin.speed")))
		local setSpeed = segmented(page, nil, speedOptions, tostring(speedNow), function(id: string)
			send({ action = "Speed", mult = tonumber(id) or 1 })
		end)
		table.insert(syncers, function()
			god.Set(attr("AdminGod", false) == true)
			noCd.Set(attr("AdminNoCooldowns", false) == true)
			setSpeed(tostring(tonumber(attr("AdminSpeed", 1)) or 1))
		end)

		section(page, "admin.sec.become", "Soul")
		local worn = wornKit()
		local setters: { [string]: (boolean) -> () } = {}
		for _, role in { "Monster", "Human" } do
			caption(page, UIKit.Upper(L(if role == "Monster" then "admin.monsters" else "admin.humans")))
			local list = sortedKits(kits, role)
			local g = grid(page, 3, #list)
			for i, kit in list do
				setters[kit.Id] = card(g, {
					Name = "Become_" .. kit.Id,
					Text = pick(kit.Name),
					Color = kit.Color,
					Icon = Common.KitIcon(kit),
					Width = cellWidth(3),
					Selected = kit.Id == worn,
					Order = i,
					OnActivated = function()
						send({ action = "BecomeKit", kitId = kit.Id })
					end,
				})
			end
		end
		table.insert(syncers, function()
			local now = wornKit()
			for id, set in setters do
				set(id == now)
			end
		end)
	end

	-- PROGRESS ------------------------------------------------------------------------------------------------
	builders.Progress = function(page: any)
		local profileLabel = UIKit.Label(theme, {
			Name = "ProfileLine",
			Text = "",
			Role = "Body",
			Tone = "Gold",
			Truncate = true,
			Size = UDim2.new(1, -10, 0, if phone then 26 else 32),
			LayoutOrder = nextOrder(),
			Parent = page.Content,
		})
		local function profileText(): string
			local profile = Common.Profile(d)
			if type(profile) ~= "table" then
				return "…"
			end
			local owned, total = 0, 0
			if kits then
				for _, kit in kits.All() do
					total += 1
					if Common.KitOwned(profile, kit) then
						owned += 1
					end
				end
			end
			return L("admin.profileLine", profile.Level or 1, Common.Num(profile.Gold or 0), owned, total)
		end
		profileLabel.Text = profileText()
		table.insert(syncers, function()
			profileLabel.Text = profileText()
		end)

		section(page, "admin.sec.gold", "Gold")
		local goldGrid = grid(page, 3, 3)
		for i, n in { 100, 1000, 10000 } do
			button(goldGrid, {
				Text = "+" .. Common.Num(n) .. " G",
				Icon = "Gold",
				OnActivated = function()
					send({ action = "AddGold", n = n })
				end,
			}, i)
		end
		section(page, "admin.sec.levels", "Star")
		local levelGrid = grid(page, 3, 3)
		for i, n in { 1, 5, 10 } do
			button(levelGrid, {
				Text = "+" .. n .. " LV",
				Icon = "Exp",
				OnActivated = function()
					send({ action = "AddLevels", n = n })
				end,
			}, i)
		end
		section(page, "admin.sec.unlock", "Lock")
		wide(page, {
			Name = "UnlockAll",
			Text = L("admin.unlockAll"),
			Icon = "Sparkle",
			Variant = "Primary",
			OnActivated = function()
				send({ action = "UnlockAll" })
			end,
		})

		section(page, "admin.sec.danger", "Skull")
		local armed = os.clock() < state.ResetArmedUntil
		local resetRow = frame({ Name = "ResetRow", Size = UDim2.new(1, -10, 0, TAP), LayoutOrder = nextOrder() })
		local confirmRow =
			frame({ Name = "ConfirmRow", Size = UDim2.new(1, -10, 0, TAP * 2 + GAP), LayoutOrder = nextOrder() })
		local function setArmed(on: boolean)
			armed = on
			state.ResetArmedUntil = if on then os.clock() + RESET_ARM_TIME else 0
			resetRow.Visible = not on
			confirmRow.Visible = on
		end
		local resetBtn = UIKit.Button(theme, {
			Name = "Reset",
			Text = L("admin.reset"),
			Icon = "Refresh",
			Variant = "Danger",
			Height = TAP,
			OnActivated = function()
				setArmed(true)
				task.delay(RESET_ARM_TIME, function()
					if armed and os.clock() >= state.ResetArmedUntil - 0.05 and confirmRow.Parent then
						setArmed(false)
					end
				end)
			end,
		})
		resetBtn.Root.Size = UDim2.fromScale(1, 1)
		resetBtn.Root.Parent = resetRow
		UIKit.Label(theme, {
			Name = "Question",
			Text = L("admin.reset.confirm"),
			Role = "Body",
			Tone = "Danger",
			Truncate = true,
			Size = UDim2.new(1, 0, 0, TAP),
			Parent = confirmRow,
		})
		local buttons = frame({
			Name = "Buttons",
			Position = UDim2.fromOffset(0, TAP + GAP),
			Size = UDim2.new(1, 0, 0, TAP),
			Parent = confirmRow,
		})
		local bl = UIKit.ListLayout(buttons, { Horizontal = true, Gap = GAP })
		bl.HorizontalFlex = Enum.UIFlexAlignment.Fill
		local yesBtn = button(buttons, {
			Name = "ConfirmReset",
			Text = L("admin.reset.yes"),
			Icon = "Check",
			Variant = "Danger",
			OnActivated = function()
				setArmed(false)
				send({ action = "ResetProfile", confirm = true })
			end,
		}, 1)
		yesBtn.Root.Size = UDim2.new(0, 60, 1, 0)
		local cancelBtn = button(buttons, {
			Name = "CancelReset",
			Text = L("admin.cancel"),
			Icon = "Close",
			OnActivated = function()
				setArmed(false)
			end,
		}, 2)
		cancelBtn.Root.Size = UDim2.new(0, 60, 1, 0)
		page.Add(resetRow)
		page.Add(confirmRow)
		resetRow.Visible = not armed
		confirmRow.Visible = armed
	end

	-- TEST ----------------------------------------------------------------------------------------------------
	-- MUSIC: preview any track on this client and see which id plays (SoundController checks every id itself)
	local function musicInfo(): { [string]: any }?
		local sound = d.Sound
		if type(sound) ~= "table" or type(sound.NowPlaying) ~= "function" then
			return nil
		end
		local ok, info = pcall(sound.NowPlaying)
		return if ok and type(info) == "table" then info else nil
	end

	local function musicBuild(page: any)
		section(page, "admin.sec.music", "Music")
		local lineSize = if classic then (if phone then 9 else 10) else (if phone then 13 else 15)
		local lineH = math.ceil(lineSize * 1.4) + 2
		local statusLine = UIKit.Label(theme, {
			Name = "MusicNow",
			Text = "",
			Role = "Mono",
			TextSize = lineSize,
			Truncate = true,
			Size = UDim2.new(1, -10, 0, lineH),
			LayoutOrder = nextOrder(),
			Parent = page.Content,
		})
		local idLine = UIKit.Label(theme, {
			Name = "MusicId",
			Text = "",
			Role = "Mono",
			Tone = "Dim",
			TextSize = lineSize,
			Truncate = true,
			Size = UDim2.new(1, -10, 0, lineH),
			LayoutOrder = nextOrder(),
			Parent = page.Content,
		})
		local handles: { [string]: any } = {}
		local selectedKey: string? = nil
		local function render()
			local info = musicInfo()
			local active: string? = nil
			if info == nil then
				statusLine.Text = L("admin.music.off")
				statusLine.TextColor3 = c.TextDim
				idLine.Text = ""
			else
				local mode = L(if info.Preview then "admin.music.preview" else "admin.music.auto")
				local key = info.Key
				if type(key) ~= "string" then
					statusLine.Text = L("admin.music.line", mode, L("admin.music.none"), "-")
					statusLine.TextColor3 = c.TextDim
					idLine.Text = ""
				else
					local entry = info.Entry
					local keyText = if type(entry) == "string" and entry ~= key then key .. " -> " .. entry else key
					local st = MUSIC_STATUS[tostring(info.Status)] or MUSIC_STATUS.empty
					statusLine.Text = L("admin.music.line", mode, keyText, L(st.Key))
					statusLine.TextColor3 = (c :: any)[st.Tone] or c.Text
					idLine.Text = if type(info.Id) == "string"
						then L("admin.music.idLine", info.Id, tostring(info.Index or "?"), tostring(info.Count or 0))
						else L("admin.music.noId")
					active = if info.Preview then key else nil
				end
			end
			if active ~= selectedKey then
				selectedKey = active
				for key, h in handles do
					h.SetSelected(key == active)
				end
			end
		end
		local function preview(key: string?)
			local sound = d.Sound
			if type(sound) == "table" and type(sound.PreviewMusic) == "function" then
				local ok, err = pcall(sound.PreviewMusic, key)
				if not ok then
					warn("[Admin] music preview: " .. tostring(err))
				end
			end
			render()
		end
		-- monster themes: normal + final for every monster kit that has a Theme_<kit> entry
		local audio = Common.Module({ "Audio" })
		local themed: { any } = {}
		for _, kit in sortedKits(kits, "Monster") do
			if audio == nil or type(audio.MonsterTheme) ~= "function" or audio.MonsterTheme(kit.Id) ~= nil then
				table.insert(themed, kit)
			end
		end
		if #themed > 0 then
			local themeGrid = grid(page, 2, #themed * 2)
			for i, kit in themed do
				local name = pick(kit.Name)
				local icon = Common.KitIcon(kit)
				for j, final in { false, true } do
					local key = "Theme_" .. kit.Id .. (if final then "_Final" else "")
					handles[key] = button(themeGrid, {
						Name = "Music_" .. key,
						Text = if final then L("admin.music.final", name) else name,
						Icon = if final then "Flame" else icon,
						OnActivated = function()
							preview(key)
						end,
					}, (i - 1) * 2 + j)
				end
			end
		end
		local trackGrid = grid(page, 3, #MUSIC_TRACKS)
		for i, track in MUSIC_TRACKS do
			local key = track[1]
			handles[key] = button(trackGrid, {
				Name = "Music_" .. key,
				Text = L(track[2]),
				Icon = track[3],
				OnActivated = function()
					preview(key)
				end,
			}, i)
		end
		wide(page, {
			Name = "MusicStop",
			Text = L("admin.music.stop"),
			Icon = "Close",
			OnActivated = function()
				preview(nil)
			end,
		})
		caption(page, L("admin.music.hint"), 3)
		render()
		local acc = 0
		bag.Add(Motion.Loop(statusLine, function(dt: number)
			acc += dt
			if acc > 0.5 then
				acc = 0
				render()
			end
		end))
	end

	builders.Test = function(page: any)
		musicBuild(page)
		section(page, "admin.sec.box", "Box")
		wide(page, {
			Name = "BoxNearest",
			Text = L("admin.boxNearest"),
			Icon = "Box",
			Variant = "Primary",
			OnActivated = function()
				send({ action = "BoxNearest" })
			end,
		})
		caption(page, L("admin.box.hint"), 2)
		section(page, "admin.sec.damage", "Knife")
		local dmgGrid = grid(page, 2, 4)
		for i, n in { 10, 50, 100, 500 } do
			button(dmgGrid, {
				Text = "-" .. n .. " HP",
				Icon = "Knife",
				OnActivated = function()
					send({ action = "DamageMe", n = n })
				end,
			}, i)
		end
		section(page, "admin.sec.kr", "Flame")
		local krGrid = grid(page, 3, 3)
		for i, n in { 5, 20, 50 } do
			button(krGrid, {
				Text = "+" .. n .. " KR",
				Icon = "Flame",
				OnActivated = function()
					send({ action = "AddKR", n = n })
				end,
			}, i)
		end
		section(page, "admin.sec.monster", "Skull")
		wide(page, {
			Name = "Exhaust",
			Text = L("admin.exhaust"),
			Icon = "Shoe",
			OnActivated = function()
				send({ action = "GiveDodges0" })
			end,
		})
	end

	-- tab switching ---------------------------------------------------------------------------------------------
	selectTab = function(id: string)
		if TAB_KEY[id] == nil then
			return
		end
		state.Tab = id
		local page = pageFor(id)
		if #page.Root:GetChildren() <= 2 then -- only the layout + padding: build it now
			build(id, page)
		end
		for pid, p in pages do
			p.Root.Visible = pid == id
		end
		local matchTab = id == "Match"
		startBtn.Root.Visible = matchTab
		page.Root.Size = UDim2.new(1, 0, 0, pagesH - (if matchTab then TAP + GAP else 0))
		if tabs.Selected() ~= id then
			tabs.Select(id)
		end
	end
	selectTab(state.Tab)

	-- live sync: toggles from attributes, the profile line, the worn kit
	local function syncAll()
		for _, list in syncersByPage do
			for _, fn in list do
				pcall(fn)
			end
		end
	end
	local player = Common.LocalPlayer()
	if player and not preview then
		for _, name in { "AdminGod", "AdminNoCooldowns", "AdminSpeed", "AdminSolo", "Role" } do
			bag.Connect(player:GetAttributeChangedSignal(name), syncAll)
		end
	end
	if state_ then
		bag.Connect(state_.ProfileChanged, syncAll)
		bag.Connect(state_.CharacterChanged, function()
			task.delay(0.3, syncAll)
		end)
	end

	return {
		Root = root,
		DefaultSelection = first or closeBtn.Root,
		Select = selectTab,
		OnAction = function(action: string): boolean
			if action == "PrevTab" or action == "NextTab" then
				local idx = table.find(TABS, state.Tab) or 1
				idx = ((idx - 1 + (if action == "NextTab" then 1 else -1)) % #TABS) + 1
				selectTab(TABS[idx])
				return true
			end
			return false
		end,
		Destroy = function()
			bag.Clean()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

return Admin
