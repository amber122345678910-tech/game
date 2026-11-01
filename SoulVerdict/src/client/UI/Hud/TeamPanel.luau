--!strict
-- Hud/TeamPanel: the human team at a glance (left side): SOUL heart in the class colour (cracked while downed,
-- shattered when fallen), name + LV, mini HP bar with KR, downed bleed-out timer, team revives left and the
-- Harmony bonus.
--   TeamPanel.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
-- Data: snapshot.Humans {Unit}, HumansAlive/HumansTotal, TeamRevives, Harmony (RoundState attribute).
local Style = require(script.Parent.Style)

local TeamPanel = {}

function TeamPanel.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "TeamPanel")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local W = if phone then 196 else 270
	local rowH = if phone then 26 else 36
	local headerH = if phone then 22 else 30
	local panel = Style.Box(skin, {
		Name = "Panel",
		Position = UDim2.fromOffset(if phone then 10 else 20, if phone then 60 else 170),
		Size = UDim2.fromOffset(W, headerH + 8),
		Stroke = if battle then 3 else nil,
		Transparency = if battle then 0.15 else 0.4,
		Parent = root,
	})
	local header = Style.Frame({
		Name = "Header",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, headerH),
		ZIndex = 2,
		Parent = panel,
	})
	local title = Style.Text(skin, {
		Name = "Title",
		Text = Style.L("hud.team.title"),
		TextSize = if phone then 9 else skin.Size.Small + 1,
		Color = C.Dim,
		Stroke = false,
		Size = UDim2.fromScale(0.5, 1),
		ZIndex = 2,
		Parent = header,
	})
	local revives = Style.Frame({
		Name = "Revives",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.5, 1),
		ZIndex = 2,
		Parent = header,
	})
	local revHeart = Style.Heart(C.Good, if phone then 11 else 14, "Whole")
	revHeart.AnchorPoint = Vector2.new(1, 0.5)
	revHeart.Position = UDim2.new(1, if phone then -26 else -34, 0.5, 0)
	revHeart.Parent = revives
	local revText = Style.Text(skin, {
		Name = "Count",
		Text = "",
		Role = "Number",
		TextSize = if phone then 10 else 13,
		X = "Right",
		Stroke = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = revives,
	})
	local rows = Style.Frame({
		Name = "Rows",
		Position = UDim2.fromOffset(10, headerH + 4),
		Size = UDim2.new(1, -20, 0, 0),
		ZIndex = 2,
		Parent = panel,
	})
	local harmony = Style.Text(skin, {
		Name = "Harmony",
		Text = "",
		TextSize = if phone then 8 else skin.Size.Small,
		Color = C.Good,
		Stroke = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, 14),
		ZIndex = 2,
		Parent = panel,
	})

	type Row = { Frame: Frame, Heart: Frame, HeartKey: string, Name: TextLabel, Status: TextLabel, Bar: any, Unit: any }
	local rowList: { Row } = {}
	local rosterKey = ""

	local function buildRows(humans: { any })
		for _, r in rowList do
			r.Frame:Destroy()
		end
		table.clear(rowList)
		for i, u in humans do
			local f = Style.Frame({
				Name = "Row" .. i,
				Position = UDim2.fromOffset(0, (i - 1) * rowH),
				Size = UDim2.new(1, 0, 0, rowH),
				ZIndex = 2,
				Parent = rows,
			})
			if u.IsLocal then
				local hl = Style.Frame({
					Name = "Highlight",
					BackgroundTransparency = if battle then 0.82 else 0.88,
					BackgroundColor3 = Style.WHITE,
					Position = UDim2.fromOffset(-6, 1),
					Size = UDim2.new(1, 12, 1, -2),
					ZIndex = 2,
					Parent = f,
				})
				if not battle then
					Style.Corner(hl, UDim.new(0, 6))
				end
			end
			local heartHolder = Style.Frame({
				Name = "Soul",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(if phone then 14 else 18, if phone then 13 else 16),
				ZIndex = 3,
				Parent = f,
			})
			local nameLabel = Style.Text(skin, {
				Name = "Name",
				Text = if battle then Style.Upper(skin, tostring(u.Name)) else tostring(u.Name),
				Upper = false,
				TextSize = if phone then 9 else (if battle then 10 else 14),
				Role = if battle then "Label" else "Title",
				Scaled = true,
				MinSize = 6,
				Stroke = false,
				Position = UDim2.fromOffset(if phone then 20 else 26, 2),
				Size = UDim2.new(1, -(if phone then 20 else 26) - (if phone then 52 else 70), 0, rowH * 0.5),
				ZIndex = 3,
				Parent = f,
			})
			if u.IsBot then
				nameLabel.Text = nameLabel.Text .. " [" .. Style.L("hud.bot") .. "]"
			end
			local status = Style.Text(skin, {
				Name = "Status",
				Text = "",
				TextSize = if phone then 8 else (if battle then 9 else 12),
				X = "Right",
				Stroke = false,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 2),
				Size = UDim2.new(0, if phone then 52 else 70, 0, rowH * 0.5),
				ZIndex = 3,
				Parent = f,
			})
			local bar = Style.Bar(skin, {
				Name = "HP",
				Kind = "HP",
				Value = 1,
				Max = 1,
				Secondary = 0,
				Height = if phone then 4 else 6,
				Position = UDim2.new(0, if phone then 20 else 26, 1, -(if phone then 9 else 12)),
				Size = UDim2.new(1, -(if phone then 20 else 26), 0, if phone then 5 else 7),
				ZIndex = 3,
				Parent = f,
			})
			table.insert(rowList, {
				Frame = f,
				Heart = heartHolder,
				HeartKey = "",
				Name = nameLabel,
				Status = status,
				Bar = bar,
				Unit = u,
			})
		end
		local h = #humans * rowH
		rows.Size = UDim2.new(1, -20, 0, h)
		panel.Size = UDim2.fromOffset(W, headerH + 8 + h + 22)
	end

	local function tick(now: number)
		for _, r in rowList do
			local u = r.Unit
			if u.Downed and not u.Dead then
				Style.SetText(
					r.Status,
					Style.Upper(skin, Style.L("hud.team.down", math.max(0, math.ceil((u.DownedEndsAt or now) - now))))
				)
			end
		end
	end

	local function update(s: { [string]: any })
		local humans = s.Humans or {}
		local keyParts = {}
		for _, u in humans do
			table.insert(keyParts, tostring(u.Name))
		end
		local key = table.concat(keyParts, "|")
		if key ~= rosterKey then
			rosterKey = key
			buildRows(humans)
		end
		for i, r in rowList do
			local u = humans[i]
			r.Unit = u
			local kit = Style.Kit(u.KitId)
			local color = if kit then kit.Color else C.SoulRed
			local variant = if u.Dead then "Broken" elseif u.Downed then "Cracked" else "Whole"
			local heartKey = variant .. tostring(color)
			if heartKey ~= r.HeartKey then
				r.HeartKey = heartKey
				r.Heart:ClearAllChildren()
				local heart = Style.Heart(if u.Dead then C.Muted else color, if phone then 14 else 18, variant)
				heart.Parent = r.Heart
			end
			r.Bar.Root.Visible = not u.Dead
			r.Bar.Set(if u.Downed then 0 else (u.HP or 0), math.max(1, u.MaxHP or 1), math.min(u.KR or 0, u.HP or 0))
			r.Name.TextColor3 = if u.Dead then C.Muted else C.Text
			if u.Dead then
				Style.SetText(r.Status, Style.Upper(skin, Style.L("hud.team.fallen")))
				r.Status.TextColor3 = C.Muted
			elseif u.Downed then
				r.Status.TextColor3 = C.Danger
			else
				Style.SetText(
					r.Status,
					if u.IsLocal
						then Style.Upper(skin, Style.L("hud.you"))
						else Style.Upper(skin, Style.L("hud.lv", u.Level or 1))
				)
				r.Status.TextColor3 = if u.IsLocal then C.Gold else C.Dim
			end
		end
		local rev = s.TeamRevives or 0
		Style.SetText(revText, tostring(rev))
		revText.TextColor3 = if rev > 0 then C.Text else C.Danger
		Style.SetText(
			title,
			Style.Upper(skin, Style.L("hud.team.title"))
				.. "  "
				.. string.format("%d/%d", s.HumansAlive or 0, s.HumansTotal or #humans)
		)
		local bonus = math.floor(((s.Harmony or 1) - 1) * 100 + 0.5)
		harmony.Visible = bonus > 0
		Style.SetText(harmony, Style.Upper(skin, Style.L("hud.team.harmony", bonus)))
		panel.Visible = #humans > 0
		if phone then
			panel.Position = UDim2.fromOffset(10, if s.Device == "Touch" then 140 else 60)
		end
		tick(s.Now or 0)
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Tick = tick,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return TeamPanel
