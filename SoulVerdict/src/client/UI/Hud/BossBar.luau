--!strict
-- Hud/BossBar: the monster's bar for everyone (top centre, under the timer strip): kit name + title in the kit
-- colour, big HP bar with damage flash, dodges pips / EXHAUSTED countdown, FINAL PHASE red flare, and (for
-- Perseverance "Studious" players) the monster's ability cooldowns.
--   BossBar.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
-- Data: snapshot.Monster (Unit: KitId, Name, Level, HP/MaxHP, Dodges/MaxDodges, ExhaustedUntil, FinalForm,
-- Cooldowns = the monster model's Cooldown_<abilityId> attributes written by AbilityService), FinalPhase, Studious.
local Style = require(script.Parent.Style)

local BossBar = {}

local STUDIOUS_ORDER = { "Q", "E", "R", "T", "Shift", "F", "G" }

function BossBar.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "BossBar")
	local C = skin.C
	local phone = layout.Phone
	local W = if phone then 370 else 720
	local barH = if phone then 14 else (if skin.Battle then 22 else 18)
	local top = if phone then 58 else (if skin.Battle then 80 else 88)
	local holder = Style.Frame({
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top),
		Size = UDim2.fromOffset(W, if phone then 58 else 78),
		Parent = root,
	})
	if not skin.Battle then
		Style.Box(skin, {
			Name = "Glass",
			Position = UDim2.fromOffset(-16, -10),
			Size = UDim2.new(1, 32, 1, 16),
			Transparency = 0.45,
			ZIndex = 1,
			Parent = holder,
		})
	end
	local headerH = if phone then 18 else 26
	local header = Style.Frame({ Name = "Header", Size = UDim2.new(1, 0, 0, headerH), ZIndex = 3, Parent = holder })
	local left = Style.Frame({ Name = "Left", Size = UDim2.new(0.75, 0, 1, 0), ZIndex = 3, Parent = header })
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, if phone then 6 else 10)
	list.Parent = left
	local skullHolder = Style.Frame({ Name = "SkullHolder", Size = UDim2.fromOffset(headerH, headerH), LayoutOrder = 1, ZIndex = 3, Parent = left })
	local nameLabel = Style.Text(skin, {
		Name = "KitName",
		Text = "",
		Role = "Title",
		TextSize = if phone then 13 else (if skin.Battle then 18 else 22),
		AutoX = true,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = left,
	})
	local titleLabel = Style.Text(skin, {
		Name = "KitTitle",
		Text = "",
		TextSize = if phone then 9 else (if skin.Battle then 11 else 14),
		AutoX = true,
		Size = UDim2.new(0, 0, 1, if skin.Battle then 4 else 2),
		Y = "Center",
		LayoutOrder = 3,
		ZIndex = 3,
		Parent = left,
	})
	local rightLabel = Style.Text(skin, {
		Name = "Right",
		Text = "",
		TextSize = if phone then 9 else skin.Size.Small,
		Color = C.Dim,
		X = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		ZIndex = 3,
		Parent = header,
	})
	local finalTag = Style.Box(skin, {
		Name = "FinalTag",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(if phone then 96 else 150, headerH - 2),
		Fill = C.Danger,
		Transparency = 0,
		Border = C.Danger,
		Stroke = 2,
		Sheen = false,
		ZIndex = 4,
		Parent = header,
	})
	Style.Text(skin, {
		Name = "Label",
		Text = Style.L("hud.final"),
		TextSize = if phone then 9 else skin.Size.Small + 1,
		X = "Center",
		Stroke = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = finalTag,
	})

	-- bar + flare
	local barTop = headerH + (if phone then 4 else 6)
	local flare = Style.Glow({
		Name = "Flare",
		Color = C.Danger,
		Position = UDim2.fromOffset(0, barTop),
		Size = UDim2.new(1, 0, 0, barH),
		Spread = if phone then 8 else 14,
		Strength = 1.2,
		ZIndex = 1,
		Parent = holder,
	})
	local frameBox = Style.Frame({
		Name = "BarFrame",
		BackgroundTransparency = 0,
		BackgroundColor3 = Style.BLACK,
		Position = UDim2.fromOffset(-3, barTop - 3),
		Size = UDim2.new(1, 6, 0, barH + 6),
		ZIndex = 2,
		Parent = holder,
	})
	local frameStroke: UIStroke
	if skin.Battle then
		frameStroke = Style.Stroke(frameBox, C.Box, 2, 0, true)
	else
		frameBox.BackgroundTransparency = 0.5
		Style.Corner(frameBox, UDim.new(0.5, 0))
		frameStroke = Style.Stroke(frameBox, Style.WHITE, 1, 0.8)
	end
	local bar = Style.Bar(skin, {
		Name = "HP",
		Kind = "Monster",
		Value = 1,
		Max = 1,
		Height = barH,
		Position = UDim2.fromOffset(0, barTop),
		Size = UDim2.new(1, 0, 0, barH),
		ZIndex = 3,
		Parent = holder,
	})
	-- bottom row: dodges (left) + HP numbers (right)
	local rowY = barTop + barH + (if phone then 5 else 8)
	local rowH = if phone then 12 else 16
	local row = Style.Frame({ Name = "Row", Position = UDim2.fromOffset(0, rowY), Size = UDim2.new(1, 0, 0, rowH), ZIndex = 3, Parent = holder })
	local dodgeLabel = Style.Text(skin, {
		Name = "DodgeLabel",
		Text = Style.L("stat.dodges"),
		TextSize = if phone then 8 else skin.Size.Small,
		Color = C.Dim,
		AutoX = true,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 3,
		Parent = row,
	})
	local pips = Style.Pips(skin, {
		Name = "Dodges",
		Max = 6,
		Value = 6,
		PipSize = if phone then Vector2.new(16, 7) else (if skin.Battle then Vector2.new(24, 11) else Vector2.new(26, 8)),
		Gap = if phone then 3 else 5,
		Color = C.Dodge,
		Empty = C.DodgeEmpty,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, if phone then 72 else (if skin.Battle then 104 else 78), 0.5, 0),
		ZIndex = 3,
		Parent = row,
	})
	local exhaust = Style.Frame({
		Name = "Exhaust",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, if phone then 72 else (if skin.Battle then 104 else 78), 0.5, 0),
		Size = UDim2.fromOffset(260, rowH + 4),
		ZIndex = 3,
		Visible = false,
		Parent = row,
	})
	local moon = Style.Icon("Moon", C.Warn, rowH + 4)
	moon.Parent = exhaust
	local exhaustText = Style.Text(skin, {
		Name = "Text",
		Text = "",
		TextSize = if phone then 9 else skin.Size.Small + 1,
		Color = C.Warn,
		Position = UDim2.fromOffset(rowH + 10, 0),
		Size = UDim2.new(1, -(rowH + 10), 1, 0),
		ZIndex = 3,
		Parent = exhaust,
	})
	local hpText = Style.Text(skin, {
		Name = "HPText",
		Text = "",
		Role = "Number",
		TextSize = if phone then 10 else skin.Size.Number,
		X = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		ZIndex = 3,
		Parent = row,
	})

	-- Studious: the monster's cooldowns
	local studY = rowY + rowH + (if phone then 6 else 10)
	local studious = Style.Frame({ Name = "Studious", Position = UDim2.fromOffset(0, studY), Size = UDim2.new(1, 0, 0, if phone then 26 else 36), Visible = false, ZIndex = 3, Parent = holder })
	local studCells: { { Id: string, Overlay: Frame, Text: TextLabel } } = {}
	local studKit = ""

	local snap: { [string]: any }? = nil
	local kitShown = ""

	local function buildStudious(kitId: string)
		if kitId == studKit then
			return
		end
		studKit = kitId
		for _, child in studious:GetChildren() do
			child:Destroy()
		end
		table.clear(studCells)
		local size = if phone then 24 else 34
		local label = Style.Frame({ Name = "Label", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = studious })
		local book = Style.Icon("Book", Style.KitColor("Perseverance"), size - 6)
		book.AnchorPoint = Vector2.new(0, 0.5)
		book.Position = UDim2.fromScale(0, 0.5)
		book.Parent = label
		local slots = Style.Slots(kitId)
		local x = size + 4
		for _, slotName in STUDIOUS_ORDER do
			for _, info in slots do
				if info.Slot == slotName then
					local cell = Style.Box(skin, {
						Name = "Cd_" .. info.Id,
						Position = UDim2.fromOffset(x, (studious.Size.Y.Offset - size) / 2),
						Size = UDim2.fromOffset(size, size),
						Stroke = if skin.Battle then 2 else 1,
						Border = if info.Ult then C.UltFull else nil,
						Sheen = false,
						ZIndex = 3,
						Parent = studious,
					})
					local icon = Style.Icon(info.Icon, Style.WHITE, size - 8)
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Position = UDim2.fromScale(0.5, 0.5)
					icon.Parent = cell
					local overlay = Style.Frame({
						Name = "Overlay",
						BackgroundTransparency = 0.12,
						BackgroundColor3 = Style.BLACK,
						Size = UDim2.fromScale(1, 1),
						ZIndex = 4,
						Visible = false,
						Parent = cell,
					})
					if not skin.Battle then
						Style.Corner(overlay, skin.Corner)
					end
					local t = Style.Text(skin, {
						Name = "Seconds",
						Text = "",
						Role = "Number",
						TextSize = if phone then 10 else (if skin.Battle then 12 else 15),
						X = "Center",
						Size = UDim2.fromScale(1, 1),
						ZIndex = 5,
						Parent = overlay,
					})
					table.insert(studCells, { Id = info.Id, Overlay = overlay, Text = t })
					x += size + 5
				end
			end
		end
	end

	local function tick(now: number)
		local s = snap
		local m = if s then s.Monster else nil
		if not s or not m then
			return
		end
		local exhausted = (m.ExhaustedUntil or 0) > now
		exhaust.Visible = exhausted
		pips.Root.Visible = not exhausted
		if exhausted then
			Style.SetText(exhaustText, Style.Upper(skin, Style.L("hud.exhaustedFor", Style.FormatCd(m.ExhaustedUntil - now))))
		end
		if studious.Visible and m.Cooldowns then
			for _, cell in studCells do
				local endsAt = m.Cooldowns[cell.Id] or 0
				local left = endsAt - now
				cell.Overlay.Visible = left > 0.05
				if left > 0.05 then
					Style.SetText(cell.Text, Style.FormatCd(left))
				end
			end
		end
	end

	local function update(s: { [string]: any })
		snap = s
		local m = s.Monster
		holder.Visible = m ~= nil
		if not m then
			return
		end
		local kit = Style.Kit(m.KitId)
		local kitColor = if kit then kit.Color else C.Monster
		if kitShown ~= m.KitId then
			kitShown = m.KitId
			for _, child in skullHolder:GetChildren() do
				child:Destroy()
			end
			local skull = Style.Icon("Skull", kitColor, headerH)
			skull.Parent = skullHolder
			Style.SetText(nameLabel, Style.Upper(skin, if kit then Style.Pick(kit.Name) else tostring(m.Name)))
			Style.SetText(titleLabel, Style.Upper(skin, if kit then Style.Pick(kit.Title) else ""))
			titleLabel.TextColor3 = kitColor
		end
		local final = s.FinalPhase == true or m.FinalForm == true
		finalTag.Visible = final
		rightLabel.Visible = not final
		Style.SetText(rightLabel, Style.Upper(skin, tostring(m.Name) .. "  " .. Style.L("hud.lv", m.Level or 1)))
		flare.Visible = final
		frameStroke.Color = if final then C.Danger elseif skin.Battle then C.Box else Style.WHITE
		frameStroke.Transparency = if final then 0 elseif skin.Battle then 0 else 0.8
		if skin.Battle then
			Style.TintBar(skin, bar.Root, if final then Style.UT_YELLOW else C.Monster)
		else
			if final then
				Style.TintBar(skin, bar.Root, Color3.fromRGB(255, 30, 60), Color3.fromRGB(255, 160, 40))
			else
				Style.TintBar(skin, bar.Root, kitColor)
			end
		end
		bar.Set(m.HP or 0, math.max(1, m.MaxHP or 1))
		Style.SetText(hpText, Style.FormatHp(skin, m.HP or 0, m.MaxHP or 0))
		pips.Set(m.Dodges or 0, m.MaxDodges or 0)
		dodgeLabel.Visible = (m.MaxDodges or 0) > 0
		local showStudious = s.Studious == true and m.Cooldowns ~= nil
		studious.Visible = showStudious
		if showStudious then
			buildStudious(m.KitId)
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

return BossBar
