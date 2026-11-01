--!strict
-- Screens/Quests: quests (3 per 12-hour window, claim / reroll once), the login streak and the achievements
-- grid with their title rewards (SPEC §1.6).
--   Quest data: profile.Quests = { Window, List = {QuestState {Id, Progress, Goal, Claimed}}, Rerolled }.
--   Definitions (name/desc/icon/reward) come from Shared/Progression/Quests when it exists (Get/Def/GetDef(id),
--   Defs[id] or ById[id]); otherwise Strings "quest.<Id>" / "quest.<Id>.desc", otherwise the id itself.
--   Achievements: Shared/Progression/Achievements (All/List() or Defs/List table) + profile.Achievements.
--
--   Quests.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnAction(action) }
--   deps: State, UI, Layout (+ offline: Profile, Now, Tab = "Quests"|"Achievements" on phones)
-- Requests: ClaimQuest {index, questId}, RerollQuest {index, questId}.

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Quests = {}

local L = Common.L
local frame = Common.Frame

-- definitions (Shared/Progression: Quests templates + "prog.quest.<Id>", Achievements + "prog.ach.<id>") ---------
local QUEST_ICONS: { [string]: string } = {
	DealDamage = "Sword", HumanDamage = "Sword", BigRound = "Sword", Parries = "Shield", ParryRound = "Shield",
	Saves = "Star", Revives = "Heart", TeamPlayer = "Users", Healing = "Food", HealerRound = "Food",
	ForceDodges = "Dash", BoxSurvivor = "Box", BeMvp = "Crown", EarnExp = "Exp", PracticeRound = "Target",
	PlayRounds = "Flag", WinRounds = "Trophy", HumanWin = "Trophy", MonsterWin = "Trophy", HumanSurvive = "Soul",
	SurviveCollapse = "Clock", DefeatMonster = "Swords", FinalBlow = "Swords", MonsterPlay = "Skull",
	MonsterKills = "Skull", MonsterDowns = "Skull",
}
local GROUP_ICONS: { [string]: string } = {
	Trials = "Flag", Victory = "Trophy", Combat = "Swords", Support = "Heart", Box = "Box", Growth = "Exp",
	Collection = "Star", Feats = "Crown",
}

type QuestInfo = { Name: string, Sub: string, Icon: string, Exp: number?, Gold: number? }

local function questInfo(state: any, index: number, profile: any): QuestInfo
	local id = tostring(state.Id)
	local goal = tonumber(state.Goal) or 1
	local module = Common.Progression("Quests")
	local okT, template = Common.Call(module, { "Get" }, id)
	local t = if okT and type(template) == "table" then template else nil
	local key = "prog.quest." .. id
	local name = if Common.Has(key) then L(key, Common.Num(goal), Common.Num(t and t.Param or 0)) else id
	local parts = {}
	if t and type(t.Role) == "string" and t.Role ~= "Any" then
		table.insert(parts, L("role." .. string.lower(t.Role)))
	end
	if t and type(t.Difficulty) == "number" then
		table.insert(parts, L("difficulty." .. tostring(t.Difficulty)))
	end
	local icon = QUEST_ICONS[id] or (if t and t.Role == "Monster" then "Skull" elseif t and t.Role == "Human" then "Heart" else "Quests")
	local exp, gold = nil, nil
	local meta = profile and profile.Meta
	local r = meta and type(meta.QuestRewards) == "table" and meta.QuestRewards[index]
	if type(r) == "table" then
		exp, gold = tonumber(r.exp or r.Exp), tonumber(r.gold or r.Gold)
	elseif module and type(module.RewardFor) == "function" then
		local ok, e, g = pcall(module.RewardFor, state)
		if ok then
			exp, gold = tonumber(e), tonumber(g)
		end
	end
	return { Name = name, Sub = table.concat(parts, "  ·  "), Icon = if Icons.Has(icon) then icon else "Quests", Exp = exp, Gold = gold }
end

type AchInfo = { Id: string, Name: string, Desc: string, Icon: string, Rarity: string, Title: string?, Hidden: boolean, Value: number, Goal: number }

local function achievements(profile: any): { AchInfo }
	local module = Common.Progression("Achievements")
	local ok, list = Common.Call(module, { "List", "All" })
	local out: { AchInfo } = {}
	if ok and type(list) == "table" then
		for _, a in list do
			local id = tostring(a.Id)
			local goal = tonumber(a.Goal) or 1
			local value = 0
			if profile and module and type(module.Progress) == "function" then
				local okP, v, g = pcall(module.Progress, profile, id)
				if okP then
					value, goal = tonumber(v) or 0, tonumber(g) or goal
				end
			end
			local titleKey = "prog.title." .. tostring(a.Title or id)
			table.insert(out, {
				Id = id,
				Name = if Common.Has("prog.ach." .. id) then L("prog.ach." .. id) else id,
				Desc = if Common.Has("prog.ach." .. id .. ".desc") then L("prog.ach." .. id .. ".desc", Common.Num(goal)) else "",
				Icon = GROUP_ICONS[a.Group or ""] or "Trophy",
				Rarity = a.Rarity or "Common",
				Title = if a.Title and Common.Has(titleKey) then L(titleKey) else nil,
				Hidden = a.Hidden == true,
				Value = value,
				Goal = goal,
			})
		end
		return out
	end
	-- module missing: show what the profile has unlocked
	if profile and type(profile.Achievements) == "table" then
		for id, on in profile.Achievements do
			if on then
				table.insert(out, { Id = tostring(id), Name = tostring(id), Desc = "", Icon = "Trophy", Rarity = "Common", Title = nil, Hidden = false, Value = 1, Goal = 1 })
			end
		end
	end
	return out
end

function Quests.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local screen = Common.Screen(theme, d, {
		Name = "Quests",
		Title = L("scr.quests.title"),
		Subtitle = L("scr.quests.subtitle"),
		Icon = "Quests",
	})
	local root, body, bag = screen.Root, screen.Body, screen.Bag
	local phone = screen.Phone
	local canvas = screen.Canvas
	local bodyW = canvas.X - screen.Margin * 2
	local bodyH = body.Size.Y.Offset + canvas.Y * body.Size.Y.Scale
	local profile = Common.Profile(d)
	local phoneTab: string = d.Tab or "Quests"
	local claimedLocal: { [number]: boolean } = {}
	local rerolledLocal = false
	local defaultSel: GuiObject? = nil
	local gap = screen.Gap

	local leftW = if phone then bodyW else math.floor(bodyW * 0.56)
	local rightW = bodyW - leftW - gap
	local questsH = if phone then bodyH - 42 else math.floor(bodyH * 0.6)
	local streakH = bodyH - questsH - gap

	local holder = frame({ Name = "Holder", Position = UDim2.fromOffset(0, if phone then 42 else 0), Size = UDim2.new(1, 0, 1, if phone then -42 else 0), Parent = body })
	local refresh: () -> ()

	-- quests panel -------------------------------------------------------------------------------------
	local function buildQuests(parent: Frame, w: number, h: number)
		local panel = UIKit.Panel(theme, { Name = "QuestPanel", Title = L("scr.quests.daily"), TitleIcon = "Quests", Size = UDim2.fromOffset(w, h), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		local config = Common.Config()
		local hours = (config and config.Quests and config.Quests.WindowHours) or 12
		local windowLen = hours * 3600
		local function leftText(): string
			local now = Common.Now(d)
			return L("scr.quests.window", Common.Clock(windowLen - (now % windowLen)))
		end
		local timer = UIKit.Label(theme, {
			Name = "Window",
			Text = leftText(),
			Role = "Caption",
			Tone = "Dim",
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, if theme.Id == "Royal" then 16 else 10),
			Size = UDim2.fromOffset(300, 20),
			ZIndex = 10,
			Parent = panel.Root,
		})
		bag.Add(Motion.Loop(timer, function()
			timer.Text = leftText()
		end))
		local q = profile and profile.Quests
		local list = if q and type(q.List) == "table" then q.List else {}
		if #list == 0 then
			Common.Empty(theme, if profile == nil then L("scr.loadingProfile") else L("scr.quests.empty"), { Parent = panel.Content })
			return
		end
		local rerolled = rerolledLocal or (q and q.Rerolled == true)
		local headerH = if theme.Id == "Royal" then 58 elseif theme.Id == "Classic" then 42 else 46
		local contentH = h - headerH - (if phone then 10 else 16)
		local rowGap = if phone then 8 else 12
		local rowH = math.floor((contentH - rowGap * (#list - 1)) / math.max(#list, 1))
		rowH = math.min(rowH, if phone then 96 else 132)
		local col = frame({ Name = "Rows", Size = UDim2.fromScale(1, 1), Parent = panel.Content })
		UIKit.ListLayout(col, { Gap = rowGap })
		for i, state in list do
			local id = tostring(state.Id)
			local goal = tonumber(state.Goal) or 1
			local progress = math.min(tonumber(state.Progress) or 0, goal)
			local claimed = state.Claimed == true or claimedLocal[i] == true
			local done = progress >= goal
			local info = questInfo(state, i, profile)
			local name, desc, icon = info.Name, info.Sub, info.Icon
			local row = Common.Well(theme, {
				Name = "Quest_" .. id,
				Size = UDim2.new(1, 0, 0, rowH),
				LayoutOrder = i,
				StrokeColor = if done and not claimed then c.Success else c.StrokeDim,
				StrokeTransparency = if done and not claimed then 0 else nil,
			})
			row.Parent = col
			local pad = if phone then 8 else 14
			local iconSize = rowH - pad * 2
			iconSize = math.min(iconSize, if phone then 56 else 76)
			local tile = frame({
				Name = "Icon",
				BackgroundTransparency = 0,
				BackgroundColor3 = (if claimed then c.StrokeDim elseif done then c.Success else c.Accent):Lerp(c.PanelInset, 0.78),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, pad, 0.5, 0),
				Size = UDim2.fromOffset(iconSize, iconSize),
				Parent = row,
			})
			Common.Corner(tile, if theme.Id == "Void" then UDim.new(0.5, 0) elseif theme.Id == "Royal" then UDim.new(0, 8) else theme.SmallCorner)
			Common.Stroke(tile, if claimed then c.StrokeDim elseif done then c.Success else c.Accent, if theme.Id == "Classic" then 2 else 1.5, 0.2, theme.LineJoin)
			local ic = Icons.Create(icon, if claimed then c.TextMuted elseif done then c.Success else c.Accent, UDim2.fromScale(0.58, 0.58), c.Accent2)
			ic.Parent = tile
			local x = pad + iconSize + (if phone then 10 else 16)
			local actionW = if phone then 120 else 170
			local textW = w - (if phone then 20 else 32) - x - actionW - pad * 2
			UIKit.Label(theme, {
				Name = "Name",
				Text = name,
				Role = "Heading",
				TextSize = if theme.Id == "Classic" then (if phone then 10 else 13) else (if phone then 15 else 20),
				Color = if claimed then c.TextMuted else c.Text,
				Position = UDim2.fromOffset(x, pad - 2),
				Size = UDim2.fromOffset(textW, if phone then 18 else 26),
				Truncate = true,
				Parent = row,
			})
			UIKit.Label(theme, {
				Name = "Desc",
				Text = desc,
				Role = "Small",
				Tone = "Dim",
				Position = UDim2.fromOffset(x, pad + (if phone then 18 else 26)),
				Size = UDim2.fromOffset(textW, if phone then 16 else 22),
				Truncate = true,
				Parent = row,
			})
			UIKit.Bar(theme, {
				Name = "Progress",
				Kind = "Exp",
				Value = progress,
				Max = goal,
				ShowValue = true,
				Format = function(v: number, m: number): string
					return L("scr.quests.progress", Common.Num(v), Common.Num(m))
				end,
				Color = if claimed then c.StrokeDim elseif done then c.Success else c.Accent,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, x, 1, -pad - (if phone then 0 else 22)),
				Size = UDim2.fromOffset(textW, if phone then 16 else 20),
				Parent = row,
			})
			-- rewards line
			if (info.Gold or info.Exp) and not phone then
				local rl = frame({ Name = "Rewards", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, x, 1, -pad + 2), Size = UDim2.fromOffset(textW, 18), Parent = row })
				UIKit.ListLayout(rl, { Horizontal = true, Gap = 12, VAlign = Enum.VerticalAlignment.Center })
				if info.Gold and info.Gold > 0 then
					UIKit.Badge(theme, { Text = "+" .. Common.Num(info.Gold) .. " G", Icon = "Gold", Color = c.Gold, Style = "Soft", Height = 18, TextSize = if theme.Id == "Classic" then 7 else 11, LayoutOrder = 1, Parent = rl })
				end
				if info.Exp and info.Exp > 0 then
					UIKit.Badge(theme, { Text = "+" .. Common.Num(info.Exp) .. " EXP", Icon = "Exp", Color = c.Exp, Style = "Soft", Height = 18, TextSize = if theme.Id == "Classic" then 7 else 11, LayoutOrder = 2, Parent = rl })
				end
			end
			-- action column
			local act = frame({ Name = "Action", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -pad, 0.5, 0), Size = UDim2.fromOffset(actionW, rowH - pad * 2), Parent = row })
			local al = UIKit.ListLayout(act, { Gap = 6, HAlign = Enum.HorizontalAlignment.Right, VAlign = Enum.VerticalAlignment.Center })
			al.HorizontalAlignment = Enum.HorizontalAlignment.Right
			local bh = if phone then 32 else 42
			local index = i
			if claimed then
				UIKit.Button(theme, { Text = L("scr.quests.claimed"), Icon = "Check", Variant = "Secondary", Disabled = true, Height = bh, Width = actionW, LayoutOrder = 1, Parent = act })
			elseif done then
				local b = UIKit.Button(theme, {
					Text = L("scr.quests.claim"),
					Icon = "Gold",
					Variant = "Primary",
					Height = bh,
					Width = actionW,
					LayoutOrder = 1,
					Parent = act,
					OnActivated = function()
						claimedLocal[index] = true
						Common.Request(d, "ClaimQuest", { index = index, questId = id })
						refresh()
					end,
				})
				defaultSel = defaultSel or b.Root
			else
				local b = UIKit.Button(theme, {
					Text = if rerolled then L("scr.quests.rerollUsed") else L("scr.quests.reroll"),
					Icon = "Refresh",
					Variant = "Ghost",
					Disabled = rerolled,
					Height = bh,
					Width = actionW,
					LayoutOrder = 2,
					Parent = act,
					OnActivated = function()
						rerolledLocal = true
						Common.Request(d, "RerollQuest", { index = index, questId = id })
						refresh()
					end,
				})
				if not rerolled then
					defaultSel = defaultSel or b.Root
				end
			end
		end
	end

	-- login streak --------------------------------------------------------------------------------------
	local function buildStreak(parent: Frame, w: number, h: number)
		local panel = UIKit.Panel(theme, { Name = "Streak", Title = L("scr.quests.streak"), TitleIcon = "Heart", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(0, questsH + gap), Padding = 16 })
		panel.Root.Parent = parent
		local streak = (profile and profile.Login and tonumber(profile.Login.Streak)) or 0
		local filled = if streak <= 0 then 0 else ((streak - 1) % 7) + 1
		local headerH = if theme.Id == "Royal" then 58 elseif theme.Id == "Classic" then 42 else 46
		local contentH = h - headerH - 16
		local daysH = math.min(contentH - 52, 118)
		local row = frame({ Name = "Days", Size = UDim2.new(1, 0, 0, daysH), Parent = panel.Content })
		local rl = UIKit.ListLayout(row, { Horizontal = true, Gap = 10, HAlign = Enum.HorizontalAlignment.Center, VAlign = Enum.VerticalAlignment.Center })
		rl.HorizontalFlex = Enum.UIFlexAlignment.Fill
		for day = 1, 7 do
			local on = day <= filled
			local today = day == filled
			local tile = Common.Well(theme, {
				Name = "Day" .. day,
				Size = UDim2.new(0, 60, 1, 0),
				LayoutOrder = day,
				Color = if on then c.SoulRed:Lerp(c.PanelInset, 0.82) else c.PanelInset,
				StrokeColor = if today then c.Accent elseif on then c.SoulRed else c.StrokeDim,
				StrokeTransparency = if today or on then 0 else nil,
			})
			tile.Parent = row
			local glyph: Frame
			if day == 7 then
				glyph = Icons.Create("Star", if on then c.Gold else c.StrokeDim, UDim2.fromScale(0.5, 0.5))
			else
				glyph = UIKit.Heart(if on then c.SoulRed else c.StrokeDim, UDim2.fromScale(0.42, 0.38), on)
			end
			glyph.Position = UDim2.fromScale(0.5, 0.42)
			glyph.Parent = tile
			UIKit.Label(theme, {
				Text = L("scr.quests.day", day),
				Role = "Caption",
				TextSize = if theme.Id == "Classic" then 7 else 12,
				Color = if on then c.Text else c.TextMuted,
				XAlign = "Center",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -4, 0, 16),
				Parent = tile,
			})
		end
		-- today / tomorrow rewards + hint
		local meta = profile and profile.Meta
		local info = frame({ Name = "Info", Position = UDim2.fromOffset(0, daysH + 12), Size = UDim2.new(1, 0, 0, math.max(contentH - daysH - 12, 24)), Parent = panel.Content })
		local chips = frame({ Name = "Chips", Size = UDim2.new(0.42, 0, 0, 30), Parent = info })
		UIKit.ListLayout(chips, { Horizontal = true, Gap = 10, VAlign = Enum.VerticalAlignment.Center })
		Common.Chip(theme, { Icon = "Heart", Text = L("scr.quests.streakDays", streak), Color = c.SoulRed, Height = 30, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 13, LayoutOrder = 1, Parent = chips })
		if meta and tonumber(meta.NextStreakGold) then
			Common.Chip(theme, { Icon = "Gold", Text = "+" .. Common.Num(meta.NextStreakGold) .. " G", Color = c.Gold, Height = 30, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 13, LayoutOrder = 2, Parent = chips })
		end
		UIKit.Label(theme, {
			Name = "Hint",
			Text = L("scr.quests.streakHint"),
			Role = "Small",
			Tone = "Dim",
			Dialogue = theme.Id == "Classic",
			Wrap = true,
			YAlign = "Top",
			Scaled = true,
			MaxTextSize = if theme.Id == "Classic" then 9 else theme.TextSize.Small,
			MinTextSize = 7,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.56, 0, 1, 0),
			Parent = info,
		})
	end

	-- achievements ---------------------------------------------------------------------------------------
	local function buildAchievements(parent: Frame, x: number, w: number, h: number)
		local defs = achievements(profile)
		local unlocked = (profile and profile.Achievements) or {}
		local count = 0
		for _, a in defs do
			if unlocked[a.Id] then
				count += 1
			end
		end
		local panel = UIKit.Panel(theme, { Name = "Achievements", Title = L("scr.quests.achievements"), TitleIcon = "Trophy", Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, 0), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		UIKit.Label(theme, {
			Name = "Count",
			Text = L("scr.quests.unlockedCount", count, #defs),
			Role = "Caption",
			Tone = "Dim",
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, if theme.Id == "Royal" then 16 else 10),
			Size = UDim2.fromOffset(220, 20),
			ZIndex = 10,
			Parent = panel.Root,
		})
		if #defs == 0 then
			Common.Empty(theme, if profile == nil then L("scr.loadingProfile") else L("scr.quests.hiddenDesc"), { Parent = panel.Content })
			return
		end
		-- unlocked first (rarest first), then the closest to completion
		table.sort(defs, function(a, b)
			local ua, ub = unlocked[a.Id] == true, unlocked[b.Id] == true
			if ua ~= ub then
				return ua
			end
			local fa, fb = a.Value / math.max(a.Goal, 1), b.Value / math.max(b.Goal, 1)
			if fa ~= fb then
				return fa > fb
			end
			return a.Id < b.Id
		end)
		local contentW = w - (if phone then 20 else 32)
		local cols = if phone then 3 else 2
		local cellW = math.floor((contentW - 12 * (cols - 1) - 8) / cols)
		local cellH = if phone then 92 else 100
		local grid = UIKit.Grid(theme, { CellSize = UDim2.fromOffset(cellW, cellH), CellPadding = UDim2.fromOffset(12, 10), Scroll = true })
		grid.Root.Size = UDim2.fromScale(1, 1)
		grid.Root.Parent = panel.Content
		for i, a in defs do
			local on = unlocked[a.Id] == true
			local hidden = a.Hidden and not on
			local rarity = Themes.Rarity(theme, a.Rarity)
			local tile = Common.Well(theme, {
				Name = "Ach_" .. a.Id,
				Size = UDim2.fromOffset(cellW, cellH),
				LayoutOrder = i,
				Color = if on then rarity:Lerp(c.PanelInset, 0.86) else c.PanelInset,
				StrokeColor = if on then rarity else c.StrokeDim,
				StrokeTransparency = if on then 0.15 else nil,
			})
			local s = math.min(cellH - 28, 58)
			local medal = frame({ Name = "Medal", BackgroundTransparency = 0, BackgroundColor3 = if on then rarity:Lerp(c.Panel, 0.6) else c.Panel, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(s, s), Parent = tile })
			Common.Corner(medal, if theme.Id == "Classic" or theme.Id == "Fell" then UDim.new(0, 0) else UDim.new(0.5, 0))
			if theme.Id == "Fell" then
				medal.Rotation = 45
				medal.Size = UDim2.fromOffset(s * 0.8, s * 0.8)
				medal.Position = UDim2.new(0, 12 + s * 0.1, 0.5, 0)
			end
			Common.Stroke(medal, if on then rarity else c.StrokeDim, if theme.Id == "Classic" then 2 else 1.5, 0, theme.LineJoin)
			local icon = Icons.Create(if hidden then "Lock" else a.Icon, if on then rarity:Lerp(Color3.new(1, 1, 1), 0.35) else c.TextMuted, UDim2.fromScale(0.56, 0.56))
			if theme.Id == "Fell" then
				icon.Rotation = -45
			end
			icon.Parent = medal
			local tx = 12 + s + 12
			UIKit.Label(theme, {
				Text = if hidden then L("scr.quests.hidden") else a.Name,
				Role = "Heading",
				TextSize = if theme.Id == "Classic" then (if phone then 8 else 10) else (if phone then 13 else 16),
				Color = if on then c.Text else c.TextDim,
				Position = UDim2.fromOffset(tx, 10),
				Size = UDim2.new(1, -tx - 8, 0, 20),
				Truncate = true,
				Parent = tile,
			})
			local bottomH = if on then (if a.Title then 24 else 8) else 22
			UIKit.Label(theme, {
				Text = if hidden then L("scr.quests.hiddenDesc") else a.Desc,
				Role = "Small",
				Tone = "Muted",
				Wrap = true,
				YAlign = "Top",
				Scaled = true,
				MaxTextSize = if theme.Id == "Classic" then 8 else 13,
				MinTextSize = 6,
				Position = UDim2.fromOffset(tx, 32),
				Size = UDim2.new(1, -tx - 8, 0, cellH - 32 - bottomH - 4),
				Parent = tile,
			})
			if on and a.Title then
				local badge = UIKit.Badge(theme, { Text = L("scr.quests.titleReward", a.Title), Icon = "Crown", Color = rarity, Style = "Soft", Height = 18, TextSize = if theme.Id == "Classic" then 6 else 10 })
				badge.AnchorPoint = Vector2.new(0, 1)
				badge.Position = UDim2.new(0, tx, 1, -6)
				badge.Parent = tile
			elseif not on and not hidden then
				UIKit.Bar(theme, {
					Name = "Progress",
					Kind = "Custom",
					Value = math.min(a.Value, a.Goal),
					Max = math.max(a.Goal, 1),
					ShowValue = true,
					Format = function(v: number, m: number): string
						return Common.Short(v) .. " / " .. Common.Short(m)
					end,
					Color = rarity,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, tx, 1, -8),
					Size = UDim2.new(1, -tx - 10, 0, 14),
					Parent = tile,
				})
			end
			grid.Add(tile)
		end
	end

	local tabs: any = nil
	refresh = function()
		holder:ClearAllChildren()
		defaultSel = nil
		if phone then
			if phoneTab == "Quests" then
				buildQuests(holder, bodyW, bodyH - 42)
			else
				buildAchievements(holder, 0, bodyW, bodyH - 42)
			end
		else
			local left = frame({ Name = "Left", Size = UDim2.fromOffset(leftW, bodyH), Parent = holder })
			buildQuests(left, leftW, questsH)
			buildStreak(left, leftW, streakH)
			buildAchievements(holder, leftW + gap, rightW, bodyH)
		end
	end
	if phone then
		tabs = UIKit.Tabs(theme, {
			Items = { { Id = "Quests", Text = L("scr.quests.daily") }, { Id = "Achievements", Text = L("scr.quests.achievements") } },
			Selected = phoneTab,
			Height = 34,
			Size = UDim2.fromOffset(520, 34),
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
			table.clear(claimedLocal)
			rerolledLocal = false
			refresh()
		end)
	end

	return {
		Root = root,
		DefaultSelection = defaultSel or screen.Back,
		OnAction = function(action: string): boolean
			if (action == "PrevTab" or action == "NextTab") and phone and tabs then
				phoneTab = if phoneTab == "Quests" then "Achievements" else "Quests"
				tabs.Select(phoneTab)
				refresh()
				return true
			end
			return false
		end,
		Destroy = function()
			screen.Destroy()
		end,
	}
end

return Quests
