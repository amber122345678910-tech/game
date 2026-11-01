--!strict
-- Screens/Results: the round-end card (SPEC §1.1 Ending, §4.2 RoundEnd/Rewards).
--   * winner banner (Strings "round.result.<Winner>.<Reason>" + ".sub"), VICTORY / DEFEAT for you, practice tag,
--     an Undertale-style flavour line (typewriter), the MVP,
--   * per-player stat table (monster first, then humans by damage; YOU / MVP / fallen markers),
--   * rewards: EXP and G count up, breakdown lines ("prog.reward.*"), EXP bar of the new level, LV UP flourish,
--     kit mastery step, new unlocks ("title:", "skin:", "trail:", "achievement:", "kit:" ids), quest progress,
--   * CONTINUE + auto-close countdown back into the lobby.
--
--   Results.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnShow, SetRewards(packet) }
--   deps: Result (RoundEnd payload {winner, reason, stats, mvpUserId, practice, mapId}), Rewards (packet or nil
--         until it arrives), AutoClose (seconds, default 14), UI (Close), State, Layout, UserId
--         (+ offline: samples when Result/Rewards are absent)

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Results = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

type Column = { Key: string, Header: string, Width: number, Get: (any) -> string }

local function unlockText(id: string): string
	local kind, rest = string.match(id, "^(%a+):(.+)$")
	if kind == nil or rest == nil then
		return id
	end
	local kits = Common.Kits()
	if kind == "title" then
		local t = if Common.Has("prog.title." .. rest) then L("prog.title." .. rest) else rest
		return L("prog.unlock.title", t)
	elseif kind == "achievement" then
		local t = if Common.Has("prog.ach." .. rest) then L("prog.ach." .. rest) else rest
		return L("prog.unlock.achievement", t)
	elseif kind == "skin" then
		local kitId, skinId = string.match(rest, "^([^:]+):(.+)$")
		local skin = kits and kitId and skinId and kits.Skin(kitId, skinId)
		local kit = kits and kitId and kits.Get(kitId)
		local text = if skin then pick(skin.Name) .. (if kit then " (" .. pick(kit.Name) .. ")" else "") else rest
		return L("prog.unlock.skin", text)
	elseif kind == "trail" then
		local trailKind = string.match(rest, ":(%a+)$") or rest
		return L("prog.unlock.trail", if Common.Has("prog.trail." .. trailKind) then L("prog.trail." .. trailKind) else trailKind)
	elseif kind == "kit" then
		local kit = kits and kits.Get(rest)
		return L("prog.unlock.kit", if kit then pick(kit.Name) else rest)
	end
	return id
end

function Results.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local kits = Common.Kits()
	local layout = Common.Layout(d)
	local phone = layout.Phone == true
	local canvas: Vector2 = layout.Canvas
	local preview = Common.IsPreview(d)
	local result: any = d.Result or (if preview then Common.SampleResult() else {})
	local rewards: any = d.Rewards
	if rewards == nil and preview and d.Result == nil then
		rewards = Common.SampleRewards()
	end
	local bag = Common.Bag()
	local me = Common.UserId(d)
	local margin = if phone then 16 else 40

	local root = frame({ Name = "Results", Size = UDim2.fromScale(1, 1) })
	if preview then
		local world = UIKit.Backdrop(theme, { Name = "PreviewWorld", Parent = root })
		world.ZIndex = 0
	end
	local dim = frame({ Name = "Dim", BackgroundTransparency = 0.25, BackgroundColor3 = c.Overlay, Size = UDim2.fromScale(1, 1), Parent = root })
	Common.Gradient(dim, nil, Common.NSeq({ { 0, 0.05 }, { 0.35, 0.3 }, { 1, 0.1 } }), 90)

	-- who won ----------------------------------------------------------------------------------------
	local winner = tostring(result.winner or "")
	local reason = tostring(result.reason or "")
	local stats: { any } = if type(result.stats) == "table" then result.stats else {}
	local myRow: any = nil
	for _, row in stats do
		if row.userId == me then
			myRow = row
		end
	end
	local myTeam = if myRow then (if myRow.team == "Monster" then "Monster" else "Humans") else nil
	local won = myTeam ~= nil and myTeam == winner
	local key = "round.result." .. winner .. "." .. reason
	local titleText = if Common.Has(key) then L(key) else (if winner == "" then L("round.result.draw") else winner)
	local subText = if Common.Has(key .. ".sub") then L(key .. ".sub") else ""
	local accent = if winner == "Monster" then c.Danger elseif winner == "Humans" then c.SoulRed:Lerp(c.Gold, 0.5) else c.TextDim

	-- banner
	local bannerY = if phone then 10 else 34
	local ribbonH = if phone then 26 else 34
	local ribbon = frame({ Name = "Ribbon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, bannerY), Size = UDim2.fromOffset(if phone then 260 else 360, ribbonH), Parent = root })
	if myTeam then
		local rb = frame({ Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = if won then c.Success else c.Danger, Size = UDim2.fromScale(1, 1), Parent = ribbon })
		Common.Corner(rb, Common.ChipCorner(theme))
		if theme.Id == "Fell" then
			rb.Rotation = -2
		end
		UIKit.Label(theme, {
			Text = UIKit.Upper(L(if won then "round.result.victory" else "round.result.defeat")),
			Role = "Heading",
			TextSize = if theme.Id == "Classic" then (if phone then 12 else 16) else (if phone then 16 else 22),
			Color = c.TextInverse,
			XAlign = "Center",
			Size = UDim2.fromScale(1, 1),
			Parent = rb,
		})
	end
	local titleSize = if phone then math.floor(theme.TextSize.Title * 0.9) else math.floor(theme.TextSize.Title * 1.35)
	local title = UIKit.Title(theme, {
		Name = "Banner",
		Text = titleText,
		Role = "Display",
		TextSize = titleSize,
		XAlign = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, bannerY + ribbonH + (if phone then 4 else 10)),
		Size = UDim2.new(1, -margin * 2, 0, math.ceil(titleSize * 1.2)),
	})
	title.Root.Parent = root
	local y = bannerY + ribbonH + (if phone then 4 else 10) + math.ceil(titleSize * 1.2) + 4
	local sub = UIKit.Label(theme, {
		Name = "Sub",
		Text = subText,
		Role = "Subtitle",
		Color = accent:Lerp(c.Text, 0.4),
		XAlign = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -margin * 2, 0, theme.TextSize.Subtitle + 8),
		Parent = root,
	})
	sub.Visible = subText ~= ""
	y += theme.TextSize.Subtitle + 12
	-- flavour line + MVP + practice chips
	local chips = frame({ Name = "Chips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.new(1, -margin * 2, 0, if phone then 26 else 32), Parent = root })
	local cl = UIKit.ListLayout(chips, { Horizontal = true, Gap = 12, HAlign = Enum.HorizontalAlignment.Center, VAlign = Enum.VerticalAlignment.Center })
	cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local mvpRow: any = nil
	for _, row in stats do
		if row.userId == result.mvpUserId then
			mvpRow = row
		end
	end
	if mvpRow then
		local mk = kits and kits.Get(mvpRow.kitId)
		Common.Chip(theme, {
			Icon = "Crown",
			Text = L("scr.results.mvp") .. "   " .. tostring(mvpRow.name) .. (if mk then "  ·  " .. pick(mk.Name) else ""),
			Color = c.Gold,
			Height = if phone then 26 else 32,
			Role = "Caption",
			TextSize = if theme.Id == "Classic" then 9 else (if phone then 12 else 15),
			LayoutOrder = 1,
			Parent = chips,
		})
	end
	if result.practice then
		Common.Chip(theme, { Icon = "Target", Text = L("round.practice.ended"), Color = c.Info, Height = if phone then 26 else 32, Role = "Caption", TextSize = if theme.Id == "Classic" then 9 else 14, LayoutOrder = 2, Parent = chips })
	end
	y += (if phone then 30 else 40)
	local flavourKey = if winner == "Humans" then "scr.results.flavor.Humans" elseif winner == "Monster" then "scr.results.flavor.Monster" else "scr.results.flavor.Draw"
	local flavour: TextLabel? = nil
	if not phone then
		flavour = UIKit.Label(theme, {
			Name = "Flavour",
			Text = (if theme.DialoguePrefix ~= "" then theme.DialoguePrefix else "") .. L(flavourKey),
			Role = "Body",
			Tone = "Dim",
			XAlign = "Center",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.new(1, -margin * 2, 0, theme.TextSize.Body + 8),
			Parent = root,
		})
		y += theme.TextSize.Body + 20
	end

	-- main row ---------------------------------------------------------------------------------------
	local footH = if phone then 40 else 60
	local mainH = canvas.Y - y - footH - (if phone then 10 else 28)
	local gap = if phone then 10 else 22
	local totalW = canvas.X - margin * 2
	local rewardsW = if phone then math.floor(totalW * 0.4) else 520
	local tableW = totalW - rewardsW - gap
	local main = frame({ Name = "Main", Position = UDim2.fromOffset(margin, y), Size = UDim2.fromOffset(totalW, mainH), Parent = root })

	-- stat table
	local tablePanel = UIKit.Panel(theme, { Name = "Table", Size = UDim2.fromOffset(tableW, mainH), Padding = if phone then 8 else 16 })
	tablePanel.Root.Parent = main
	local columns: { Column } = {
		{ Key = "damage", Header = L("scr.results.col.damage"), Width = 76, Get = function(r: any): string
			return Common.Short(tonumber(r.damage) or 0)
		end },
		{ Key = "healing", Header = L("scr.results.col.healing"), Width = 70, Get = function(r: any): string
			return Common.Short(tonumber(r.healing) or 0)
		end },
		{ Key = "kills", Header = L("scr.results.col.kills"), Width = 64, Get = function(r: any): string
			return tostring(r.kills or 0) .. "/" .. tostring(r.downs or 0)
		end },
		{ Key = "parries", Header = L("scr.results.col.parries"), Width = 66, Get = function(r: any): string
			return tostring(r.parries or 0)
		end },
		{ Key = "dodges", Header = L("scr.results.col.dodges"), Width = 66, Get = function(r: any): string
			return tostring(r.dodgesForced or 0)
		end },
		{ Key = "saves", Header = L("scr.results.col.saves"), Width = 56, Get = function(r: any): string
			return tostring(r.saves or 0)
		end },
		{ Key = "revives", Header = L("scr.results.col.revives"), Width = 66, Get = function(r: any): string
			return tostring(r.revives or 0)
		end },
	}
	if phone then
		columns = { columns[1], columns[3], columns[6] }
	end
	local colScale = if theme.Id == "Classic" then 1.2 else 1
	local colsW = 0
	for _, col in columns do
		col.Width = math.floor(col.Width * colScale)
		colsW += col.Width
	end
	local headerRowH = if phone then 20 else 26
	local headerRow = frame({ Name = "HeaderRow", Size = UDim2.new(1, 0, 0, headerRowH), Parent = tablePanel.Content })
	UIKit.Label(theme, { Text = UIKit.Upper(L("scr.results.col.player")), Role = "Caption", Tone = "Muted", Position = UDim2.fromOffset(if phone then 34 else 52, 0), Size = UDim2.new(1, -colsW - 52, 1, 0), Parent = headerRow })
	local x = 0
	for i = #columns, 1, -1 do
		local col = columns[i]
		UIKit.Label(theme, { Text = col.Header, Role = "Caption", Tone = "Muted", XAlign = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -x - 6, 0, 0), Size = UDim2.fromOffset(col.Width - 6, headerRowH), Parent = headerRow })
		x += col.Width
	end
	local sorted = table.clone(stats)
	table.sort(sorted, function(a, b)
		if (a.team == "Monster") ~= (b.team == "Monster") then
			return a.team == "Monster"
		end
		return (tonumber(a.damage) or 0) > (tonumber(b.damage) or 0)
	end)
	local list = UIKit.List(theme, { Gap = if phone then 4 else 6 })
	list.Root.Position = UDim2.fromOffset(0, headerRowH + 4)
	list.Root.Size = UDim2.new(1, 0, 1, -headerRowH - 4)
	list.Root.Parent = tablePanel.Content
	local rowH = if phone then 32 else 48
	for i, row in sorted do
		local kit = kits and kits.Get(row.kitId)
		local isMe = row.userId == me
		local isMvp = row.userId == result.mvpUserId
		local monster = row.team == "Monster"
		local teamColor = if monster then c.Danger else (if kit then kit.Color else c.Accent)
		local r = Common.Well(theme, {
			Name = "Row_" .. tostring(row.name),
			Size = UDim2.new(1, -8, 0, rowH),
			LayoutOrder = i,
			Color = if isMe then c.Accent:Lerp(c.PanelInset, 0.82) elseif monster then c.Danger:Lerp(c.PanelInset, 0.85) else c.PanelInset,
			StrokeColor = if isMe then c.Accent elseif isMvp then c.Gold else c.StrokeDim,
			StrokeTransparency = if isMe or isMvp then 0.1 else nil,
		})
		local stripe = frame({ Name = "Stripe", BackgroundTransparency = 0, BackgroundColor3 = teamColor, Size = UDim2.new(0, 4, 1, -8), Position = UDim2.fromOffset(4, 4), Parent = r })
		Common.Corner(stripe, UDim.new(0.5, 0))
		local icon = Icons.Create(if kit then Common.KitIcon(kit) else "Soul", if row.survived == false then c.TextMuted else teamColor, rowH - 14, if kit then kit.Color:Lerp(Color3.new(1, 1, 1), 0.7) else nil)
		icon.Position = UDim2.new(0, 12 + (rowH - 14) / 2, 0.5, 0)
		icon.Parent = r
		local nameX = 12 + rowH - 6
		local nameRow = frame({ Name = "NameRow", Position = UDim2.fromOffset(nameX, 0), Size = UDim2.new(1, -nameX - colsW - 8, 1, 0), Parent = r })
		local nl = UIKit.ListLayout(nameRow, { Horizontal = true, Gap = 6, VAlign = Enum.VerticalAlignment.Center })
		nl.Wraps = false
		UIKit.Label(theme, {
			Text = tostring(row.name),
			Role = "Body",
			TextSize = if theme.Id == "Classic" then (if phone then 8 else 11) else (if phone then 13 else 17),
			Color = if row.survived == false then c.TextMuted elseif isMe then c.Accent else c.Text,
			AutoSize = "X",
			LayoutOrder = 1,
			Parent = nameRow,
		}).Size = UDim2.new(0, 0, 1, 0)
		local bh = if phone then 15 else 18
		local bts = if theme.Id == "Classic" then 6 else 10
		if isMe then
			UIKit.Badge(theme, { Text = L("scr.results.you"), Color = c.Accent, Style = "Solid", Height = bh, TextSize = bts, LayoutOrder = 2, Parent = nameRow })
		end
		if isMvp then
			UIKit.Badge(theme, { Text = L("scr.results.mvp"), Icon = "Crown", Color = c.Gold, Style = "Solid", Height = bh, TextSize = bts, LayoutOrder = 3, Parent = nameRow })
		end
		if not phone then
			UIKit.Badge(theme, {
				Text = if row.survived == false then L("scr.results.fallen") else L("scr.results.survived"),
				Color = if row.survived == false then c.TextMuted else c.Success,
				Style = "Outline",
				Height = bh,
				TextSize = bts,
				LayoutOrder = 4,
				Parent = nameRow,
			})
		end
		local cx = 0
		for ci = #columns, 1, -1 do
			local col = columns[ci]
			UIKit.Label(theme, {
				Text = col.Get(row),
				Role = "Number",
				TextSize = if theme.Id == "Classic" then (if phone then 8 else 11) else (if phone then 13 else 17),
				Color = if col.Key == "damage" then c.Text else c.TextDim,
				XAlign = "Right",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -cx - 8, 0, 0),
				Size = UDim2.new(0, col.Width - 6, 1, 0),
				Parent = r,
			})
			cx += col.Width
		end
		list.Add(r)
	end
	if #sorted == 0 then
		Common.Empty(theme, L("scr.results.flavor.Draw"), { Parent = tablePanel.Content })
	end

	-- rewards panel ----------------------------------------------------------------------------------
	local rewardsPanel = UIKit.Panel(theme, { Name = "Rewards", Title = L("scr.results.rewards"), TitleIcon = "Gold", Size = UDim2.fromOffset(rewardsW, mainH), Position = UDim2.fromOffset(tableW + gap, 0), Padding = if phone then 8 else 16 })
	rewardsPanel.Root.Parent = main
	local rewardsHolder = frame({ Name = "Holder", Size = UDim2.fromScale(1, 1), Parent = rewardsPanel.Content })
	local counters: { () -> () } = {}

	local function buildRewards()
		rewardsHolder:ClearAllChildren()
		table.clear(counters)
		if rewards == nil then
			Common.Empty(theme, L("scr.results.counting"), { Parent = rewardsHolder })
			return
		end
		local col = frame({ Name = "Col", Size = UDim2.fromScale(1, 1), Parent = rewardsHolder })
		UIKit.ListLayout(col, { Gap = if phone then 6 else 10 })
		-- big counters
		local bigH = if phone then 34 else 52
		local big = frame({ Name = "Big", Size = UDim2.new(1, 0, 0, bigH), LayoutOrder = 1, Parent = col })
		local bl = UIKit.ListLayout(big, { Horizontal = true, Gap = 12 })
		bl.HorizontalFlex = Enum.UIFlexAlignment.Fill
		local function counter(icon: string, color: Color3, value: number, suffix: string, order: number)
			local well = Common.Well(theme, { Name = "Counter", Size = UDim2.new(0, 100, 1, 0), LayoutOrder = order, StrokeColor = color, StrokeTransparency = 0.3 })
			well.Parent = big
			local ic = Icons.Create(icon, color, bigH - (if phone then 12 else 20))
			ic.Position = UDim2.new(0, bigH / 2 + 2, 0.5, 0)
			ic.Parent = well
			local label = UIKit.Label(theme, {
				Text = "+" .. Common.Num(value) .. " " .. suffix,
				Role = "Number",
				TextSize = if theme.Id == "Classic" then (if phone then 11 else 16) else (if phone then 16 else 26),
				Color = color,
				XAlign = "Right",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(1, -bigH - 8, 1, 0),
				Parent = well,
			})
			table.insert(counters, function()
				Motion.CountUp(label, 0, value, 1.1, function(v: number): string
					return "+" .. Common.Num(v) .. " " .. suffix
				end)
			end)
		end
		counter("Exp", c.Exp, tonumber(rewards.exp) or 0, L("scr.results.exp"), 1)
		counter("Gold", c.Gold, tonumber(rewards.gold) or 0, L("scr.results.gold"), 2)
		-- level bar (+ LV UP flourish)
		local level = tonumber(rewards.level or rewards.newLevel) or (Common.Profile(d) and Common.Profile(d).Level) or 1
		local need = tonumber(rewards.expToNext) or Common.ExpToNext(level)
		local into = tonumber(rewards.expInto) or 0
		if rewards.levelUp then
			local flourish = frame({ Name = "LevelUp", BackgroundTransparency = 0, BackgroundColor3 = c.Gold:Lerp(c.PanelInset, 0.8), Size = UDim2.new(1, 0, 0, if phone then 30 else 44), LayoutOrder = 2, Parent = col })
			Common.Corner(flourish, Common.ChipCorner(theme))
			Common.Stroke(flourish, c.Gold, if theme.Id == "Classic" then 2 else 1.5, 0, theme.LineJoin)
			for k, xs in { 0.06, 0.94 } do
				local sp = Icons.Create("Sparkle", c.Gold, if phone then 16 else 24)
				sp.Position = UDim2.fromScale(xs, 0.5)
				sp.Parent = flourish
				Motion.Spin(sp, if k == 1 then 40 else -40)
			end
			UIKit.Label(theme, {
				Text = L("scr.results.levelUp") .. "   " .. L("scr.results.reached", level),
				Role = "Heading",
				TextSize = if theme.Id == "Classic" then (if phone then 9 else 12) else (if phone then 13 else 18),
				Color = c.Gold,
				XAlign = "Center",
				Size = UDim2.fromScale(1, 1),
				Parent = flourish,
			})
			Motion.Pulse(flourish, { BackgroundTransparency = 0 }, { BackgroundTransparency = 0.35 }, theme.Motion.PulsePeriod)
		end
		local bar = UIKit.Bar(theme, {
			Name = "Exp",
			Kind = "Exp",
			Label = L("common.level", level),
			LabelWidth = if theme.Id == "Classic" then 76 else 62,
			Value = into,
			Max = math.max(need, 1),
			ShowValue = not phone,
			Format = function(v: number, m: number): string
				return Common.Num(v) .. " / " .. Common.Num(m)
			end,
			Size = UDim2.new(1, 0, 0, if phone then 18 else 24),
			LayoutOrder = 3,
			Parent = col,
		})
		bar.Root.LayoutOrder = 3
		-- breakdown
		if type(rewards.items) == "table" and not phone then
			for i, item in rewards.items do
				if i > 6 then
					break
				end
				local line = frame({ Name = "Item", Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 10 + i, Parent = col })
				local k = tostring(item.key or "")
				UIKit.Label(theme, {
					Text = if Common.Has(k) then L(k, Common.Num(tonumber(item.count) or 0)) else k,
					Role = "Small",
					Tone = "Dim",
					Size = UDim2.new(0.62, 0, 1, 0),
					Truncate = true,
					Parent = line,
				})
				local parts = {}
				if (tonumber(item.exp) or 0) > 0 then
					table.insert(parts, "+" .. Common.Num(item.exp) .. " EXP")
				end
				if (tonumber(item.gold) or 0) > 0 then
					table.insert(parts, "+" .. Common.Num(item.gold) .. " G")
				end
				UIKit.Label(theme, {
					Text = table.concat(parts, "  "),
					Role = "Number",
					TextSize = if theme.Id == "Classic" then 9 else 14,
					Tone = "Muted",
					XAlign = "Right",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0.38, 0, 1, 0),
					Parent = line,
				})
			end
		end
		-- mastery step
		local m = rewards.mastery
		if type(m) == "table" and kits then
			local kit = kits.Get(tostring(m.kitId))
			if kit then
				local line = frame({ Name = "Mastery", Size = UDim2.new(1, 0, 0, if phone then 22 else 28), LayoutOrder = 30, Parent = col })
				local ic = Icons.Create(Common.KitIcon(kit), kit.Color, if phone then 18 else 24)
				ic.Position = UDim2.new(0, if phone then 9 else 12, 0.5, 0)
				ic.Parent = line
				local from, to = tonumber(m.from) or 1, tonumber(m.to) or 1
				UIKit.Label(theme, {
					Text = pick(kit.Name) .. "   " .. L("scr.profile.masteryLv", from) .. (if to > from then "  →  " .. L("scr.profile.masteryLv", to) else ""),
					Role = "Small",
					Color = if to > from then c.Accent2 else c.TextDim,
					Position = UDim2.fromOffset(if phone then 24 else 32, 0),
					Size = UDim2.new(0.55, 0, 1, 0),
					Truncate = true,
					Parent = line,
				})
				local need2 = tonumber(m.need) or 0
				local track = frame({ Name = "Track", BackgroundTransparency = 0, BackgroundColor3 = c.PanelInset, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.38, 0, 0, 8), Parent = line })
				Common.Corner(track, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
				local fill = frame({ Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = kit.Color, Size = UDim2.fromScale(if need2 <= 0 then 1 else math.clamp((tonumber(m.into) or 0) / need2, 0.02, 1), 1), Parent = track })
				Common.Corner(fill, if theme.Id == "Classic" then UDim.new(0, 0) else UDim.new(0.5, 0))
			end
		end
		-- unlocks
		if type(rewards.unlocked) == "table" and #rewards.unlocked > 0 then
			UIKit.Label(theme, { Text = UIKit.Upper(L("scr.results.unlocks")), Role = "Caption", Tone = "Accent", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 40, Parent = col })
			local wrap = frame({ Name = "Unlocks", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 41, Parent = col })
			UIKit.ListLayout(wrap, { Horizontal = true, Gap = 6, Wraps = true })
			local seen: { [string]: boolean } = {}
			for i, id in rewards.unlocked do
				local text = unlockText(tostring(id))
				if not seen[text] and i <= 8 then
					seen[text] = true
					local kind = string.match(tostring(id), "^(%a+):") or ""
					UIKit.Badge(theme, {
						Text = text,
						Icon = if kind == "title" then "Crown" elseif kind == "skin" then "Palette" elseif kind == "trail" then "Sparkle" elseif kind == "achievement" then "Trophy" else "Star",
						Color = if kind == "skin" then c.Accent2 elseif kind == "achievement" then c.Gold else c.Accent,
						Style = "Soft",
						Height = if phone then 18 else 22,
						TextSize = if theme.Id == "Classic" then 7 else 11,
						LayoutOrder = i,
						Parent = wrap,
					})
				end
			end
		end
		-- quest progress
		if type(rewards.questProgress) == "table" and not phone then
			for i, q in rewards.questProgress do
				if i > 3 then
					break
				end
				local qk = tostring(q.key or ("prog.quest." .. tostring(q.id)))
				local goal = tonumber(q.goal) or 1
				local text = if Common.Has(qk) then L(qk, Common.Num(goal), Common.Num(tonumber(q.param) or 0)) else tostring(q.id)
				local line = frame({ Name = "Quest", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 50 + i, Parent = col })
				local ic = Icons.Create(if q.completed then "Check" else "Quests", if q.completed then c.Success else c.TextDim, 16)
				ic.Position = UDim2.new(0, 8, 0.5, 0)
				ic.Parent = line
				UIKit.Label(theme, { Text = text, Role = "Small", Tone = if q.completed then "Success" else "Dim", Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -96, 1, 0), Truncate = true, Parent = line })
				UIKit.Label(theme, { Text = Common.Num(tonumber(q.progress) or 0) .. "/" .. Common.Num(goal), Role = "Number", TextSize = if theme.Id == "Classic" then 8 else 13, Tone = "Muted", XAlign = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 90, 1, 0), Parent = line })
			end
		end
	end
	buildRewards()

	-- footer: continue + auto close ----------------------------------------------------------------------
	local autoClose = tonumber(d.AutoClose) or 14
	local foot = frame({ Name = "Footer", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, if phone then -8 else -22), Size = UDim2.new(1, -margin * 2, 0, footH), Parent = root })
	local countdown = UIKit.Label(theme, {
		Name = "AutoClose",
		Text = L("scr.results.autoClose", autoClose),
		Role = "Caption",
		Tone = "Muted",
		XAlign = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(if phone then 200 else 300), 0.5, 0),
		Size = UDim2.fromOffset(400, 20),
		Parent = foot,
	})
	local function close()
		local ui = d.UI
		if ui and type(ui.Close) == "function" then
			ui.Close("Results")
		elseif d.UIRoot then
			d.UIRoot.Pop()
		end
	end
	local continue = UIKit.Button(theme, {
		Name = "Continue",
		Text = L("scr.results.continue"),
		Icon = "Play",
		Variant = "Primary",
		Height = if phone then 38 else 52,
		Width = if phone then 180 else 270,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Hint = if phone then nil else (if Common.Device(d) == "Gamepad" then "ButtonA" else "Enter"),
		OnActivated = close,
	})
	continue.Root.Parent = foot

	local started = false
	local function onShow()
		if started then
			return
		end
		started = true
		Motion.PopIn(title.Root, theme)
		if flavour then
			Motion.Typewriter(flavour, flavour.Text, { Interval = theme.Motion.TypeInterval, Sound = theme.Sounds.Type, SoundEvery = 2 })
		end
		for _, run in counters do
			run()
		end
		local left = autoClose
		local acc = 0
		bag.Add(Motion.Loop(countdown, function(dt: number)
			acc += dt
			if acc >= 1 then
				acc -= 1
				left -= 1
				countdown.Text = L("scr.results.autoClose", math.max(left, 0))
				if left <= 0 then
					close()
				end
			end
		end))
	end

	return {
		Root = root,
		DefaultSelection = continue.Root,
		OnShow = onShow,
		SetRewards = function(packet: any)
			rewards = packet
			buildRewards()
			if started then
				for _, run in counters do
					run()
				end
			end
		end,
		Destroy = function()
			bag.Clean()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

return Results
