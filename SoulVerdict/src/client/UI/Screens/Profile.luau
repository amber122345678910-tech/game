--!strict
-- Screens/Profile: who you are in the hall (SPEC §1.6).
--   * player card: 3D rig of the equipped human kit (Common.RigView), name, equipped title (title selector ->
--     Request SetTitle {title}), LV + EXP bar, G, monster chance, win rate,
--   * record: lifetime stats (profile.Stats),
--   * kit mastery: level 1..10 per kit with progress (Shared/Progression/Mastery when present),
--   * leaderboards: StateController.Leaderboards() -> { Wins = {{name, value}}, Level = {...} } (Wins / Level tabs).
--
--   Profile.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnAction(action) }
--   deps: State, UI, Layout (+ offline: Profile, Leaderboards, Board = "Wins"|"Level", Tab (phones:
--         "Card"|"Mastery"|"Boards"), PlayerName)

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Profile = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

local STATS: { { string } } = {
	{ "Rounds", "Flag" },
	{ "Wins", "Trophy" },
	{ "MonsterWins", "Skull" },
	{ "HumanWins", "Heart" },
	{ "Kills", "Swords" },
	{ "Downs", "Fist" },
	{ "Damage", "Sword" },
	{ "Healing", "Food" },
	{ "Parries", "Shield" },
	{ "Dodges", "Dash" },
	{ "Saves", "Star" },
	{ "Revives", "Soul" },
	{ "BoxesSurvived", "Box" },
	{ "MVPs", "Crown" },
}

-- title helpers (Shared/Progression/Titles when present)
local function titleText(id: string): string
	if id == "" then
		return L("scr.profile.noTitle")
	end
	local titles = Common.Progression("Titles")
	local ok, t = Common.Call(titles, { "Text" }, id)
	if ok and type(t) == "table" then
		return pick(t)
	end
	if Common.Has("prog.title." .. id) then
		return L("prog.title." .. id)
	end
	return id
end

local function titleColor(theme: Theme, id: string): Color3
	local titles = Common.Progression("Titles")
	local ok, col = Common.Call(titles, { "Color" }, id)
	if ok and typeof(col) == "Color3" then
		return col
	end
	return theme.Colors.Accent
end

local function ownedTitles(profile: any): { string }
	local out: { string } = {}
	if profile and type(profile.Titles) == "table" then
		for id, on in profile.Titles do
			if on and type(id) == "string" then
				table.insert(out, id)
			end
		end
	end
	local titles = Common.Progression("Titles")
	local order: { [string]: number } = {}
	local ok, all = Common.Call(titles, { "All" })
	if ok and type(all) == "table" then
		for i, t in all do
			order[t.Id] = i
		end
	end
	table.sort(out, function(a, b)
		return (order[a] or 1e6) < (order[b] or 1e6) or ((order[a] or 1e6) == (order[b] or 1e6) and a < b)
	end)
	return out
end

local function masteryOf(exp: number): (number, number, boolean)
	return Common.Mastery(exp)
end

function Profile.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local kits = Common.Kits()
	local screen = Common.Screen(theme, d, {
		Name = "Profile",
		Title = L("scr.profile.title"),
		Subtitle = L("scr.profile.subtitle"),
		Icon = "Profile",
	})
	local root, body, bag = screen.Root, screen.Body, screen.Bag
	local phone = screen.Phone
	local canvas = screen.Canvas
	local bodyW = canvas.X - screen.Margin * 2
	local bodyH = body.Size.Y.Offset + canvas.Y * body.Size.Y.Scale
	local gap = screen.Gap
	local profile = Common.Profile(d)
	local board: string = d.Board or "Wins"
	local phoneTab: string = d.Tab or "Card"
	local rigView: any = nil
	local refresh: () -> ()

	local holder = frame({ Name = "Holder", Position = UDim2.fromOffset(0, if phone then 42 else 0), Size = UDim2.new(1, 0, 1, if phone then -42 else 0), Parent = body })

	local function panelTop(): number
		return if theme.Id == "Royal" then 58 elseif theme.Id == "Classic" then 42 else 46
	end

	-- player card ----------------------------------------------------------------------------------------
	local function buildCard(parent: Frame, x: number, w: number, h: number)
		local panel = UIKit.Panel(theme, { Name = "Card", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, 0), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		local content = panel.Content
		local innerW = w - (if phone then 20 else 32)
		local level = profile and profile.Level or 1
		local exp = profile and profile.Exp or 0
		local need = Common.ExpToNext(level)
		local humanKit = Common.EquippedKit(profile, "Human") or "Determination"
		local kit = kits and kits.Get(humanKit)
		local viewH = if phone then math.floor(h * 0.5) else math.max(h - 32 - 262, 200)
		if rigView then
			rigView.Destroy()
		end
		rigView = Common.RigView(theme, {
			Kit = humanKit,
			Skin = if kit then Common.EquippedSkin(profile, kit) else nil,
			Style = Common.Setting(d, "RigStyle"),
			Styler = Common.Styler(d),
			Size = if phone then UDim2.fromOffset(math.floor(innerW * 0.42), h - 20) else UDim2.new(1, 0, 0, viewH),
		})
		rigView.Root.Parent = content
		local infoX = if phone then math.floor(innerW * 0.42) + 12 else 0
		local infoY = if phone then 0 else viewH + 12
		local infoW = if phone then innerW - infoX else innerW
		local info = frame({ Name = "Info", Position = UDim2.fromOffset(infoX, infoY), Size = UDim2.new(0, infoW, 1, -infoY), Parent = content })
		UIKit.ListLayout(info, { Gap = if phone then 6 else 10 })
		UIKit.Label(theme, {
			Name = "PlayerName",
			Text = Common.PlayerName(d),
			Role = "Heading",
			TextSize = if theme.Id == "Classic" then 16 else (if phone then 20 else 26),
			Size = UDim2.new(1, 0, 0, if phone then 24 else 32),
			Truncate = true,
			LayoutOrder = 1,
			Parent = info,
		})
		local current = (profile and profile.Equipped and profile.Equipped.Title) or ""
		UIKit.Label(theme, {
			Name = "TitleText",
			Text = "« " .. titleText(current) .. " »",
			Role = "Subtitle",
			TextSize = if theme.Id == "Classic" then 10 else (if phone then 13 else 16),
			Color = if current == "" then c.TextMuted else titleColor(theme, current),
			Size = UDim2.new(1, 0, 0, if phone then 16 else 22),
			Truncate = true,
			LayoutOrder = 2,
			Parent = info,
		})
		UIKit.Bar(theme, {
			Name = "Exp",
			Kind = "Exp",
			Label = L("common.level", level),
			LabelWidth = if theme.Id == "Classic" then 76 else 62,
			Value = exp,
			Max = need,
			ShowValue = true,
			Format = function(v: number, m: number): string
				return Common.Num(v) .. " / " .. Common.Num(m)
			end,
			Size = UDim2.new(1, 0, 0, if phone then 20 else 24),
			LayoutOrder = 3,
			Parent = info,
		})
		-- title selector
		local owned = ownedTitles(profile)
		local options = { { Id = "", Text = L("scr.profile.noTitle") } }
		local index = 1
		for i, id in owned do
			table.insert(options, { Id = id, Text = titleText(id) })
			if id == current then
				index = i + 1
			end
		end
		UIKit.Dropdown(theme, {
			Name = "TitleSelect",
			Label = L("scr.profile.titleSel"),
			Options = options,
			Index = index,
			Height = if phone then 32 else 38,
			LayoutOrder = 4,
			Parent = info,
			OnChanged = function(i: number)
				local opt = options[i]
				if opt then
					Common.Request(d, "SetTitle", { title = opt.Id })
				end
			end,
		})
		-- chips
		local stats = (profile and profile.Stats) or {}
		local rounds = tonumber(stats.Rounds) or 0
		local wins = tonumber(stats.Wins) or 0
		local chips = frame({ Name = "Chips", Size = UDim2.new(1, 0, 0, if phone then 28 else 32), LayoutOrder = 5, Parent = info })
		UIKit.ListLayout(chips, { Horizontal = true, Gap = 8, VAlign = Enum.VerticalAlignment.Center })
		local chance = tonumber(Common.PlayerAttr(d, "MonsterChance", 0)) or 0
		local ch = if phone then 26 else 30
		local ts = if theme.Id == "Classic" then 8 else (if phone then 11 else 13)
		Common.Chip(theme, { Icon = "Trophy", Text = L("scr.profile.winRate") .. " " .. tostring(if rounds > 0 then math.floor(wins / rounds * 100 + 0.5) else 0) .. "%", Color = c.Gold, Height = ch, Role = "Caption", TextSize = ts, LayoutOrder = 1, Parent = chips })
		Common.Chip(theme, { Icon = "Skull", Text = tostring(math.floor(chance * 100 + 0.5)) .. "%", Color = c.Danger, Height = ch, Role = "Caption", TextSize = ts, LayoutOrder = 2, Parent = chips })
		if profile == nil then
			Common.Empty(theme, L("scr.loadingProfile"), { Parent = content })
		end
	end

	-- record -----------------------------------------------------------------------------------------------
	local function buildRecord(parent: Frame, x: number, y: number, w: number, h: number)
		local panel = UIKit.Panel(theme, { Name = "Record", Title = L("scr.profile.stats"), TitleIcon = "Trophy", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		local stats = (profile and profile.Stats) or {}
		local cols = 2
		local innerW = w - (if phone then 20 else 32)
		local rows = math.ceil(#STATS / cols)
		local contentH = h - panelTop() - (if phone then 10 else 16)
		local rowH = math.max(math.min(math.floor((contentH - (rows - 1) * 4) / rows), 34), 20)
		local grid = UIKit.Grid(theme, { CellSize = UDim2.fromOffset(math.floor((innerW - 18) / cols), rowH), CellPadding = UDim2.fromOffset(18, 4), Scroll = rows * (rowH + 4) > contentH })
		grid.Root.Size = UDim2.fromScale(1, 1)
		grid.Root.Parent = panel.Content
		for i, s in STATS do
			local v = tonumber(stats[s[1]]) or 0
			local row = UIKit.StatRow(theme, {
				Label = L("scr.profile.stat." .. s[1]),
				Value = Common.Num(v),
				Icon = s[2],
				Color = if s[1] == "MonsterWins" or s[1] == "Kills" then c.Danger elseif s[1] == "Wins" or s[1] == "MVPs" then c.Gold else c.Accent,
				Height = rowH,
				ValueWidth = 90,
			})
			row.LayoutOrder = i
			grid.Add(row)
		end
	end

	-- mastery ---------------------------------------------------------------------------------------------
	local function buildMastery(parent: Frame, x: number, y: number, w: number, h: number)
		local panel = UIKit.Panel(theme, { Name = "Mastery", Title = L("scr.profile.mastery"), TitleIcon = "Crown", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		local list = if kits then kits.All() else {}
		local contentH = h - panelTop() - (if phone then 10 else 16)
		local rowH = math.max(math.min(math.floor((contentH - (#list - 1) * 4) / math.max(#list, 1)), 34), 22)
		local scroll = UIKit.List(theme, { Gap = 4 })
		scroll.Root.Size = UDim2.fromScale(1, 1)
		scroll.Root.Parent = panel.Content
		local mastery = (profile and profile.Mastery) or {}
		for i, kit in list do
			local exp = tonumber(mastery[kit.Id]) or 0
			local lv, frac, isMax = masteryOf(exp)
			local row = frame({ Name = "M_" .. kit.Id, Size = UDim2.new(1, -8, 0, rowH), LayoutOrder = i })
			local ic = Icons.Create(Common.KitIcon(kit), kit.Color, rowH - 6, kit.Color:Lerp(Color3.new(1, 1, 1), 0.7))
			ic.Position = UDim2.new(0, (rowH - 6) / 2, 0.5, 0)
			ic.Parent = row
			UIKit.Label(theme, {
				Text = pick(kit.Name),
				Role = "Body",
				TextSize = if theme.Id == "Classic" then 9 else (if phone then 13 else 15),
				Color = if exp > 0 then c.Text else c.TextMuted,
				Position = UDim2.fromOffset(rowH + 2, 0),
				Size = UDim2.new(0.36, -rowH, 1, 0),
				Truncate = true,
				Parent = row,
			})
			local badge = UIKit.Badge(theme, {
				Text = if isMax then L("scr.profile.masteryMax") else L("scr.profile.masteryLv", lv),
				Color = if isMax then c.Gold elseif lv >= 5 then c.Accent2 else c.TextDim,
				Style = if isMax then "Solid" else "Soft",
				Height = math.min(rowH - 8, 20),
				TextSize = if theme.Id == "Classic" then 7 else 11,
			})
			badge.AnchorPoint = Vector2.new(0, 0.5)
			badge.Position = UDim2.new(0.36, 4, 0.5, 0)
			badge.Parent = row
			local track = frame({ Name = "Track", BackgroundTransparency = 0, BackgroundColor3 = c.PanelInset, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.48, 0, 0, if theme.Id == "Classic" then 10 else 8), Parent = row })
			Common.Corner(track, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			Common.Stroke(track, c.StrokeDim, 1, 0.5)
			local fill = frame({ Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = if isMax then c.Gold else kit.Color, Size = UDim2.fromScale(math.clamp(if isMax then 1 else frac, 0, 1), 1), Parent = track })
			Common.Corner(fill, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			scroll.Add(row)
		end
	end

	-- leaderboards ----------------------------------------------------------------------------------------
	local function buildBoards(parent: Frame, x: number, w: number, h: number)
		local panel = UIKit.Panel(theme, { Name = "Boards", Title = L("scr.profile.leaderboards"), TitleIcon = "Trophy", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, 0), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		local data: any = d.Leaderboards
		if data == nil then
			local state = d.State
			if state and type(state.Leaderboards) == "function" then
				local ok, result = pcall(state.Leaderboards)
				data = if ok then result else nil
			elseif Common.IsPreview(d) then
				data = Common.SampleLeaderboards()
			end
		end
		local boardTabs = UIKit.Tabs(theme, {
			Items = { { Id = "Wins", Text = L("scr.profile.lb.Wins"), Icon = "Trophy" }, { Id = "Level", Text = L("scr.profile.lb.Level"), Icon = "Exp" } },
			Selected = board,
			Height = if phone then 32 else 40,
			Size = UDim2.new(1, 0, 0, if phone then 32 else 40),
			OnChanged = function(id: string)
				board = id
				refresh()
			end,
		})
		boardTabs.Root.Parent = panel.Content
		local entries = if type(data) == "table" and type(data[board]) == "table" then data[board] else {}
		local listTop = (if phone then 32 else 40) + 10
		if #entries == 0 then
			Common.Empty(theme, L("scr.profile.lb.empty"), { Position = UDim2.fromOffset(0, listTop), Size = UDim2.new(1, 0, 1, -listTop), Parent = panel.Content })
			return
		end
		local list = UIKit.List(theme, { Gap = if phone then 4 else 6 })
		list.Root.Position = UDim2.fromOffset(0, listTop)
		list.Root.Size = UDim2.new(1, 0, 1, -listTop)
		list.Root.Parent = panel.Content
		local me = Common.PlayerName(d)
		local medal = { c.Gold, Color3.fromRGB(200, 210, 225), Color3.fromRGB(214, 140, 80) }
		local rowH = if phone then 30 else 40
		for i, e in entries do
			local name = tostring(e.name or e.Name or "?")
			local value = tonumber(e.value or e.Value) or 0
			local mine = name == me
			local row = Common.Well(theme, {
				Name = "Rank" .. i,
				Size = UDim2.new(1, -8, 0, rowH),
				LayoutOrder = i,
				Color = if mine then c.Accent:Lerp(c.PanelInset, 0.8) else c.PanelInset,
				StrokeColor = if mine then c.Accent elseif i <= 3 then medal[i] else c.StrokeDim,
				StrokeTransparency = if mine or i <= 3 then 0.2 else nil,
			})
			local rank = UIKit.Label(theme, {
				Text = tostring(i),
				Role = "Number",
				TextSize = if theme.Id == "Classic" then 11 else (if phone then 14 else 18),
				Color = if i <= 3 then medal[i] else c.TextMuted,
				XAlign = "Center",
				Size = UDim2.new(0, rowH, 1, 0),
				Parent = row,
			})
			if i <= 3 then
				rank.Text = ""
				local crown = Icons.Create(if i == 1 then "Crown" else "Trophy", medal[i], rowH - 14)
				crown.Position = UDim2.new(0, rowH / 2, 0.5, 0)
				crown.Parent = row
			end
			UIKit.Label(theme, {
				Text = name,
				Role = "Body",
				TextSize = if theme.Id == "Classic" then 9 else (if phone then 13 else 16),
				Color = if mine then c.Accent else c.Text,
				Position = UDim2.fromOffset(rowH + 4, 0),
				Size = UDim2.new(1, -rowH - 120, 1, 0),
				Truncate = true,
				Parent = row,
			})
			UIKit.Label(theme, {
				Text = if board == "Level" then L("common.level", Common.Num(value)) else Common.Num(value),
				Role = "Number",
				TextSize = if theme.Id == "Classic" then 10 else (if phone then 14 else 17),
				Color = if i <= 3 then medal[i] else c.TextDim,
				XAlign = "Right",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0, 110, 1, 0),
				Parent = row,
			})
			list.Add(row)
		end
	end

	local tabs: any = nil
	refresh = function()
		holder:ClearAllChildren()
		rigView = nil
		local h = if phone then bodyH - 42 else bodyH
		if phone then
			if phoneTab == "Card" then
				local cardW = math.floor(bodyW * 0.48)
				buildCard(holder, 0, cardW, h)
				buildRecord(holder, cardW + gap, 0, bodyW - cardW - gap, h)
			elseif phoneTab == "Mastery" then
				buildMastery(holder, 0, 0, bodyW, h)
			else
				buildBoards(holder, 0, bodyW, h)
			end
		else
			local cardW = 400
			local boardsW = 470
			local midW = bodyW - cardW - boardsW - gap * 2
			local recordH = math.floor(h * 0.47)
			buildCard(holder, 0, cardW, h)
			buildRecord(holder, cardW + gap, 0, midW, recordH)
			buildMastery(holder, cardW + gap, recordH + gap, midW, h - recordH - gap)
			buildBoards(holder, cardW + midW + gap * 2, boardsW, h)
		end
	end
	if phone then
		tabs = UIKit.Tabs(theme, {
			Items = { { Id = "Card", Text = L("scr.profile.title") }, { Id = "Mastery", Text = L("scr.profile.mastery") }, { Id = "Boards", Text = L("scr.profile.leaderboards") } },
			Selected = phoneTab,
			Height = 34,
			Size = UDim2.fromOffset(620, 34),
			OnChanged = function(id: string)
				phoneTab = id
				refresh()
			end,
		})
		tabs.Root.Parent = body
	end
	refresh()

	local state = d.State
	if state and state.ProfileChanged then
		bag.Connect(state.ProfileChanged, function(p: any)
			profile = p or Common.Profile(d)
			refresh()
		end)
	end

	return {
		Root = root,
		DefaultSelection = screen.Back,
		OnAction = function(action: string): boolean
			if action == "PrevTab" or action == "NextTab" then
				if phone and tabs then
					local order = { "Card", "Mastery", "Boards" }
					local idx = table.find(order, phoneTab) or 1
					idx = ((idx - 1 + (if action == "NextTab" then 1 else -1)) % #order) + 1
					phoneTab = order[idx]
					tabs.Select(phoneTab)
				else
					board = if board == "Wins" then "Level" else "Wins"
				end
				refresh()
				return true
			end
			return false
		end,
		Destroy = function()
			if rigView then
				rigView.Destroy()
			end
			screen.Destroy()
		end,
	}
end

return Profile
