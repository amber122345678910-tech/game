--!strict
-- Hud/RoundHud: the local player's own state.
--   Battle: the Undertale stats row above the ability bar ("NAME LV 12   HP [yellow/red bar] KR 72 / 110", HP
--   bar length grows with MaxHP, numbers turn magenta while KR > 0) + a resource row (GUARD bar, DASH pips,
--   ULT meter / DODGES squares + EXHAUSTED for the monster).
--   Modern: a glass player card bottom-left (SOUL avatar with an ult ring, gradient HP with KR overlay + damage
--   trail, guard / dash / dodges, ULT READY chip).
--   Both: status chips (Status_* attributes, remaining time), SECOND WIND / SURGE banners with timers, low-HP
--   vignette, and the DOWNED overlay (cracked SOUL, "hold on" hint, bleed-out bar, team revives left).
--   RoundHud.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
-- Data: snapshot.Me (Unit), TeamRevives, Now (Hud/Mock.luau contract).
local Style = require(script.Parent.Style)

local RoundHud = {}

local BLUE_SOUL = Color3.fromRGB(0, 60, 255)

local function list(parent: Instance, horizontal: boolean, gap: number, align: string?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	if align == "Center" then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	elseif align == "Right" then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
	l.Parent = parent
	return l
end

function RoundHud.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "RoundHud")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local touch = false
	local snap: { [string]: any }? = nil

	-- shared overlays -------------------------------------------------------------------------------
	local lowHp =
		Style.Vignette({ Name = "LowHp", Color = C.Danger, Strength = 0.4, Depth = 0.16, ZIndex = 1, Parent = root })
	lowHp.Visible = false

	-- downed overlay
	local downed =
		Style.Frame({ Name = "Downed", Size = UDim2.fromScale(1, 1), ZIndex = 20, Visible = false, Parent = root })
	Style.Vignette({
		Name = "Vignette",
		Color = Color3.fromRGB(200, 0, 0),
		Strength = 0.75,
		Depth = 0.3,
		ZIndex = 20,
		Parent = downed,
	})
	Style.Frame({
		Name = "Dim",
		BackgroundTransparency = 0.72,
		BackgroundColor3 = Style.BLACK,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = downed,
	})
	local dGroup = Style.Frame({
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if phone then 0.42 else 0.47),
		Size = UDim2.fromOffset(if phone then 420 else 560, if phone then 190 else 236),
		ZIndex = 21,
		Parent = downed,
	})
	local dHeartHolder = Style.Frame({
		Name = "HeartHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(72, 66),
		ZIndex = 21,
		Parent = dGroup,
	})
	local dTitle = Style.Text(skin, {
		Name = "Title",
		Text = Style.L("hud.downed.title"),
		Role = "Title",
		TextSize = if phone then 22 else (if battle then 30 else 38),
		Color = C.Danger,
		X = "Center",
		Position = UDim2.fromOffset(0, if phone then 62 else 76),
		Size = UDim2.new(1, 0, 0, if phone then 26 else 40),
		ZIndex = 21,
		Parent = dGroup,
	})
	dTitle.TextColor3 = C.Danger
	Style.Text(skin, {
		Name = "Hint",
		Text = (if battle then "* " else "") .. Style.L("hud.downed.hint"),
		Role = "Body",
		TextSize = if phone then 11 else (if battle then 13 else 17),
		Upper = false,
		X = "Center",
		Position = UDim2.fromOffset(0, if phone then 92 else 122),
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 21,
		Parent = dGroup,
	})
	local bleed = Style.Frame({
		Name = "Bleed",
		BackgroundTransparency = 0,
		BackgroundColor3 = if battle then Style.BLACK else Color3.fromRGB(30, 8, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if phone then 122 else 158),
		Size = UDim2.fromOffset(if phone then 260 else 340, if battle then 14 else 10),
		ZIndex = 21,
		Parent = dGroup,
	})
	if battle then
		Style.Stroke(bleed, Style.WHITE, 2, 0, true)
	else
		Style.Corner(bleed, UDim.new(0.5, 0))
	end
	local bleedFill = Style.Frame({
		Name = "Fill",
		BackgroundTransparency = 0,
		BackgroundColor3 = C.Danger,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 21,
		Parent = bleed,
	})
	if not battle then
		Style.Corner(bleedFill, UDim.new(0.5, 0))
	end
	local bleedText = Style.Text(skin, {
		Name = "BleedText",
		Text = "",
		TextSize = if phone then 10 else skin.Size.Small + 1,
		Upper = false,
		X = "Center",
		Position = UDim2.fromOffset(0, if phone then 142 else 182),
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 21,
		Parent = dGroup,
	})
	local revText = Style.Text(skin, {
		Name = "Revives",
		Text = "",
		TextSize = if phone then 10 else skin.Size.Small + 1,
		Upper = false,
		Color = C.Dim,
		X = "Center",
		Position = UDim2.fromOffset(0, if phone then 162 else 206),
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 21,
		Parent = dGroup,
	})
	local dHeartKit = ""

	-- the stats block --------------------------------------------------------------------------------
	local block = Style.Frame({ Name = "Block", Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root })
	local statusRow: Frame
	local bannerCol: Frame
	local soulHolder: Frame
	local nameLabel: TextLabel
	local lvLabel: TextLabel
	local titleLabel: TextLabel? = nil
	local hpBar: any = nil
	local hpHolder: Frame
	local guardBar: any = nil
	local guardGroup: Frame
	local dashPips: any
	local dashGroup: Frame
	local dodgePips: any
	local dodgeGroup: Frame
	local exhaustLabel: TextLabel
	local ultBar: any = nil
	local ultText: TextLabel
	local ultGroup: Frame
	local ultRing: any = nil
	local readyChip: Frame? = nil
	local shieldLabel: TextLabel
	local lastShape = ""
	local lastSoul = ""

	local function smallLabel(parent: Instance, text: string, order: number): TextLabel
		return Style.Text(skin, {
			Name = "Label",
			Text = text,
			TextSize = if phone then 8 else (if battle then 10 else 12),
			Color = if battle then C.Text else C.Dim,
			AutoX = true,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = order,
			ZIndex = 3,
			Parent = parent,
		})
	end

	local function miniBar(parent: Instance, kind: string, width: number, order: number): any
		return Style.Bar(skin, {
			Name = kind,
			Kind = kind,
			Value = 0,
			Max = 1,
			Height = if battle then 10 else 8,
			Size = UDim2.fromOffset(width, if battle then 12 else 10),
			LayoutOrder = order,
			ZIndex = 3,
			Parent = parent,
		})
	end

	-- Builds the block for (shape = "Battle"|"Modern") x (monster?) x (hp width). Rebuilt only when the shape changes.
	local function build(monster: boolean, hpWidth: number)
		block:ClearAllChildren()
		hpBar, guardBar, ultBar, ultRing, readyChip, titleLabel = nil, nil, nil, nil, nil, nil
		local resourceRow: Frame
		local compact = phone and touch -- phones: stats move to the top-left, thumbs own the bottom corners
		if battle then
			-- UT stats row, centred above the ability bar (compact: two left-aligned rows top-left)
			local abilityTop = if phone then 86 else 112
			local row1Y = -(abilityTop + 46)
			local row1 = Style.Frame({
				Name = "Row1",
				AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0.5, 1),
				Position = if compact then UDim2.fromOffset(10, 8) else UDim2.new(0.5, 0, 1, row1Y + 26),
				Size = if compact then UDim2.fromOffset(320, 22) else UDim2.new(1, 0, 0, 26),
				ZIndex = 3,
				Parent = block,
			})
			list(row1, true, if compact then 6 else 10, if compact then nil else "Center")
			soulHolder = Style.Frame({
				Name = "Soul",
				Size = UDim2.fromOffset(if compact then 14 else 18, if compact then 14 else 18),
				LayoutOrder = 1,
				ZIndex = 3,
				Parent = row1,
			})
			nameLabel = Style.Text(skin, {
				Name = "Name",
				Text = "",
				Role = "Title",
				TextSize = if phone then 12 else 16,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 2,
				ZIndex = 3,
				Visible = not compact,
				Parent = row1,
			})
			lvLabel = Style.Text(skin, {
				Name = "LV",
				Text = "",
				Role = "Title",
				TextSize = if phone then 12 else 16,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 3,
				ZIndex = 3,
				Visible = not compact,
				Parent = row1,
			})
			Style.Frame({
				Name = "Spacer",
				Size = UDim2.fromOffset(if compact then 0 else (if phone then 6 else 18), 1),
				LayoutOrder = 4,
				Parent = row1,
			})
			local valueWidth = (if monster then 11 else 9) * (if compact then 9 else (if phone then 11 else 13)) + 8
			local labelWidth = if compact then 20 else (if phone then 26 else 34)
			local barWidth = if compact then (if monster then 110 else 120) else hpWidth
			hpHolder = Style.Frame({
				Name = "HPHolder",
				Size = UDim2.fromOffset(
					labelWidth + 6 + barWidth + (if compact then 26 else 36) + valueWidth + 8,
					if compact then 20 else 24
				),
				LayoutOrder = 5,
				ZIndex = 3,
				Parent = row1,
			})
			hpBar = Style.Bar(skin, {
				Name = "HP",
				Kind = "HP",
				Label = Style.L("stat.hp"),
				LabelWidth = labelWidth,
				ValueWidth = valueWidth,
				Value = 1,
				Max = 1,
				Secondary = if monster then nil else 0,
				ShowValue = true,
				Format = function(v: number, m: number): string
					return Style.FormatHp(skin, v, m)
				end,
				Height = if compact then 12 else (if phone then 16 else 20),
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = hpHolder,
			})
			if compact then
				for _, d in hpHolder:GetDescendants() do
					if d:IsA("TextLabel") then
						d.TextSize = 9
					end
				end
			end
			resourceRow = Style.Frame({
				Name = "Row2",
				AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0.5, 1),
				Position = if compact then UDim2.fromOffset(10, 34) else UDim2.new(0.5, 0, 1, row1Y + 26 + 22),
				Size = if compact then UDim2.fromOffset(320, 14) else UDim2.new(1, 0, 0, 16),
				ZIndex = 3,
				Parent = block,
			})
			list(resourceRow, true, if compact then 8 else 10, if compact then nil else "Center")
			statusRow = Style.Frame({
				Name = "Statuses",
				AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0.5, 1),
				Position = if compact then UDim2.fromOffset(10, 56) else UDim2.new(0.5, 0, 1, row1Y - 12),
				Size = if compact then UDim2.fromOffset(320, 28) else UDim2.new(1, 0, 0, 34),
				ZIndex = 3,
				Parent = block,
			})
			list(statusRow, true, 8, if compact then nil else "Center")
			bannerCol = Style.Frame({
				Name = "Banners",
				AnchorPoint = if compact then Vector2.new(1, 0) else Vector2.new(0.5, 1),
				Position = if compact then UDim2.new(1, -10, 0, 104) else UDim2.new(0.5, 0, 1, row1Y - 56),
				Size = UDim2.new(0, if compact then 230 else 360, 0, 70),
				ZIndex = 3,
				Parent = block,
			})
		else
			-- Modern player card, bottom-left (compact: top-left)
			local cardW = if phone then 300 else 440
			local cardH = if phone then 84 else 118
			local margin = if phone then 10 else 24
			local card = Style.Box(skin, {
				Name = "Card",
				AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0, 1),
				Position = if compact then UDim2.fromOffset(margin, 8) else UDim2.new(0, margin, 1, -margin),
				Size = UDim2.fromOffset(cardW, cardH),
				ZIndex = 2,
				Parent = block,
			})
			local av = if phone then 56 else 80
			local avatar = Style.Frame({
				Name = "Avatar",
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(20, 22, 34),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, if phone then 10 else 16, 0.5, 0),
				Size = UDim2.fromOffset(av, av),
				ZIndex = 3,
				Parent = card,
			})
			Style.Corner(avatar, UDim.new(0.5, 0))
			ultRing = Style.Radial({
				Name = "UltRing",
				Mode = "Filled",
				Color = C.Ult,
				Circle = true,
				ZIndex = 3,
				Parent = avatar,
			})
			local inner = Style.Frame({
				Name = "Inner",
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(14, 16, 26),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -8, 1, -8),
				ZIndex = 4,
				Parent = avatar,
			})
			Style.Corner(inner, UDim.new(0.5, 0))
			soulHolder = Style.Frame({
				Name = "Soul",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(av * 0.5, av * 0.5),
				ZIndex = 5,
				Parent = inner,
			})
			local chip = Style.Frame({
				Name = "Ready",
				BackgroundTransparency = 0,
				BackgroundColor3 = C.UltFull,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.fromOffset(av + 6, if phone then 15 else 18),
				ZIndex = 6,
				Visible = false,
				Parent = avatar,
			})
			Style.Corner(chip, UDim.new(0.5, 0))
			Style.Text(skin, {
				Name = "Text",
				Text = Style.L("hud.ready"),
				TextSize = if phone then 9 else 11,
				Color = Style.BLACK,
				X = "Center",
				Stroke = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 6,
				Parent = chip,
			})
			readyChip = chip
			local x0 = av + (if phone then 20 else 30)
			local rightW = cardW - x0 - (if phone then 10 else 18)
			local line1 = Style.Frame({
				Name = "Line1",
				Position = UDim2.fromOffset(x0, if phone then 8 else 12),
				Size = UDim2.fromOffset(rightW, if phone then 16 else 22),
				ZIndex = 3,
				Parent = card,
			})
			list(line1, true, if phone then 6 else 8)
			nameLabel = Style.Text(skin, {
				Name = "Name",
				Text = "",
				Role = "Title",
				TextSize = if phone then 13 else 19,
				Upper = false,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 1,
				ZIndex = 3,
				Parent = line1,
			})
			lvLabel = Style.Text(skin, {
				Name = "LV",
				Text = "",
				TextSize = if phone then 10 else 13,
				Color = C.Dim,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 2,
				ZIndex = 3,
				Parent = line1,
			})
			titleLabel = Style.Text(skin, {
				Name = "Title",
				Text = "",
				TextSize = if phone then 9 else 12,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 3,
				ZIndex = 3,
				Visible = not phone,
				Parent = line1,
			})
			hpHolder = Style.Frame({
				Name = "HPHolder",
				Position = UDim2.fromOffset(x0, if phone then 29 else 42),
				Size = UDim2.fromOffset(rightW, if phone then 18 else 22),
				ZIndex = 3,
				Parent = card,
			})
			hpBar = Style.Bar(skin, {
				Name = "HP",
				Kind = if monster then "Monster" else "HP",
				Value = 1,
				Max = 1,
				Secondary = if monster then nil else 0,
				ShowValue = true,
				ValueWidth = if phone then 66 else 86,
				Height = if phone then 12 else 16,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = hpHolder,
			})
			resourceRow = Style.Frame({
				Name = "Row2",
				Position = UDim2.fromOffset(x0, if phone then 56 else 78),
				Size = UDim2.fromOffset(rightW, if phone then 16 else 20),
				ZIndex = 3,
				Parent = card,
			})
			list(resourceRow, true, if phone then 7 else 12)
			statusRow = Style.Frame({
				Name = "Statuses",
				AnchorPoint = if compact then Vector2.new(0, 0) else Vector2.new(0, 1),
				Position = if compact then UDim2.new(0, 0, 1, 8) else UDim2.new(0, 0, 0, -10),
				Size = UDim2.new(1, 0, 0, if phone then 28 else 34),
				ZIndex = 3,
				Parent = card,
			})
			list(statusRow, true, 8)
			bannerCol = Style.Frame({
				Name = "Banners",
				AnchorPoint = if compact then Vector2.new(1, 0) else Vector2.new(0, 1),
				Position = if compact then UDim2.new(1, -10, 0, 104) else UDim2.new(0, 0, 0, -54),
				Size = UDim2.new(0, if compact then 230 else cardW, 0, 70),
				ZIndex = 3,
				Parent = if compact then block else card,
			})
		end
		local bl = list(bannerCol, false, 6, if phone and touch then "Right" elseif battle then "Center" else nil)
		bl.VerticalAlignment = if phone and touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
		-- resources
		guardGroup = Style.Frame({
			Name = "Guard",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			ZIndex = 3,
			Parent = resourceRow,
		})
		list(guardGroup, true, 6)
		smallLabel(guardGroup, Style.L("stat.guard"), 1)
		guardBar = miniBar(guardGroup, "Guard", if phone then 54 else (if battle then 110 else 100), 2)
		dashGroup = Style.Frame({
			Name = "Dash",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			ZIndex = 3,
			Parent = resourceRow,
		})
		list(dashGroup, true, 6)
		smallLabel(dashGroup, Style.L("hud.dash"), 1)
		dashPips = Style.Pips(skin, {
			Name = "Pips",
			Max = 2,
			Value = 2,
			PipSize = if phone then Vector2.new(11, 11) else Vector2.new(14, 14),
			Gap = 3,
			Color = C.Guard,
			Empty = C.DodgeEmpty,
			Shape = "Diamond",
			LayoutOrder = 2,
			ZIndex = 3,
			Parent = dashGroup,
		})
		dodgeGroup = Style.Frame({
			Name = "Dodges",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
			ZIndex = 3,
			Parent = resourceRow,
		})
		list(dodgeGroup, true, 6)
		smallLabel(dodgeGroup, Style.L("stat.dodges"), 1)
		dodgePips = Style.Pips(skin, {
			Name = "Pips",
			Max = 6,
			Value = 6,
			PipSize = if battle then Vector2.new(16, 10) else Vector2.new(18, 7),
			Gap = 3,
			Color = C.Dodge,
			Empty = C.DodgeEmpty,
			LayoutOrder = 2,
			ZIndex = 3,
			Parent = dodgeGroup,
		})
		exhaustLabel = Style.Text(skin, {
			Name = "Exhausted",
			Text = "",
			TextSize = if battle then 10 else 12,
			Color = C.Warn,
			AutoX = true,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 3,
			ZIndex = 3,
			Parent = dodgeGroup,
		})
		ultGroup = Style.Frame({
			Name = "Ult",
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 3,
			ZIndex = 3,
			Parent = resourceRow,
		})
		list(ultGroup, true, 6)
		smallLabel(ultGroup, Style.L("stat.ult"), 1)
		if battle then
			ultBar = miniBar(ultGroup, "Ult", if phone then 54 else 110, 2)
		end
		ultText = Style.Text(skin, {
			Name = "Pct",
			Text = "",
			Role = "Number",
			TextSize = if battle then 10 else 13,
			AutoX = true,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 3,
			ZIndex = 3,
			Parent = ultGroup,
		})
		shieldLabel = Style.Text(skin, {
			Name = "Shield",
			Text = "",
			TextSize = if battle then 10 else 12,
			Color = C.Gold,
			AutoX = true,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 4,
			ZIndex = 3,
			Parent = resourceRow,
		})
		guardGroup.Visible = not monster
		dashGroup.Visible = not monster
		dodgeGroup.Visible = monster
	end

	-- status chips & banners (rebuilt when the set of active statuses changes) ----------------------------
	local chipKey = ""
	local chipTimers: { { Name: string, Text: TextLabel, Radial: any, Total: number } } = {}
	local totals: { [string]: number } = {}
	local function buildChips(me: any, now: number)
		local names = {}
		for name, endsAt in me.Statuses or {} do
			if endsAt > now and not Style.HIDDEN_STATUS[name] and name ~= "SecondWind" and name ~= "Surge" then
				table.insert(names, name)
			end
		end
		table.sort(names, function(a, b)
			return Style.StatusInfo(a).Order < Style.StatusInfo(b).Order
		end)
		local key = table.concat(names, ",")
		if key == chipKey then
			return
		end
		chipKey = key
		for _, child in statusRow:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(chipTimers)
		local size = if phone then 26 else 32
		for i, name in names do
			local info = Style.StatusInfo(name)
			local chip = Style.Box(skin, {
				Name = name,
				Size = UDim2.fromOffset(size, size),
				Border = if info.Buff then nil else C.Danger,
				Stroke = if battle then 2 else 1.5,
				Corner = UDim.new(0, 8),
				Sheen = false,
				LayoutOrder = i,
				ZIndex = 3,
			})
			local icon = Style.Icon(info.Icon, info.Color, size - 10)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.ZIndex = 3
			icon.Parent = chip
			local radial = nil
			if not battle then
				radial = Style.Radial({
					Name = "Time",
					Mode = "Remaining",
					Color = Style.BLACK,
					Transparency = 0.45,
					Corner = UDim.new(0, 8),
					ZIndex = 4,
					Parent = chip,
				})
			end
			local t = Style.Text(skin, {
				Name = "Seconds",
				Text = "",
				Role = "Number",
				TextSize = if battle then 8 else 11,
				X = "Right",
				Y = "Bottom",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 3, 1, 4),
				Size = UDim2.fromOffset(size, 12),
				ZIndex = 5,
				Parent = chip,
			})
			chip.Parent = statusRow
			totals[name] = math.max(totals[name] or 0, (me.Statuses[name] or now) - now)
			table.insert(chipTimers, { Name = name, Text = t, Radial = radial, Total = totals[name] })
		end
	end

	local bannerKey = ""
	local banners: { { Name: string, Fill: Frame, Text: TextLabel, Total: number } } = {}
	local function buildBanners(me: any, now: number)
		local names = {}
		for _, name in { "SecondWind", "Surge" } do
			if (me.Statuses or {})[name] and me.Statuses[name] > now then
				table.insert(names, name)
			end
		end
		local key = table.concat(names, ",")
		if key == bannerKey then
			return
		end
		bannerKey = key
		for _, child in bannerCol:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(banners)
		for i, name in names do
			local color = if name == "Surge" then C.Gold else Color3.fromRGB(120, 255, 200)
			local b = Style.Box(skin, {
				Name = name,
				Size = UDim2.fromOffset(if phone then 220 else 300, if phone then 24 else 30),
				Border = color,
				Stroke = if battle then 2 else 1.5,
				Sheen = false,
				LayoutOrder = i,
				ZIndex = 3,
			})
			local icon = Style.Icon(if name == "Surge" then "Star" else "Heart", color, if phone then 16 else 20)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 8, 0.5, -2)
			icon.ZIndex = 3
			icon.Parent = b
			local t = Style.Text(skin, {
				Name = "Text",
				Text = "",
				TextSize = if phone then 10 else (if battle then 11 else 14),
				Color = color,
				Position = UDim2.fromOffset(if phone then 30 else 36, 0),
				Size = UDim2.new(1, -44, 1, -4),
				ZIndex = 3,
				Parent = b,
			})
			local track = Style.Frame({
				Name = "Track",
				BackgroundTransparency = 0.6,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.new(1, 0, 0, 3),
				ZIndex = 3,
				Parent = b,
			})
			local fill = Style.Frame({
				Name = "Fill",
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = track,
			})
			b.Parent = bannerCol
			local total = if name == "Surge"
				then ((Style.Config() or {}).Objectives or {}).SurgeDuration or 20
				else ((Style.Config() or {}).Human or {}).SecondWindDuration or 12
			table.insert(banners, { Name = name, Fill = fill, Text = t, Total = total })
		end
	end

	local function tick(now: number)
		local s = snap
		local me = if s then s.Me else nil
		if not s or not me then
			return
		end
		buildChips(me, now)
		for _, chip in chipTimers do
			local left = math.max(0, (me.Statuses[chip.Name] or now) - now)
			Style.SetText(chip.Text, if left > 0 then Style.FormatCd(left) else "")
			if chip.Radial then
				chip.Radial.Set(if chip.Total > 0 then 1 - left / chip.Total else 0)
			end
		end
		buildBanners(me, now)
		for _, banner in banners do
			local left = math.max(0, (me.Statuses[banner.Name] or now) - now)
			Style.SetText(
				banner.Text,
				Style.Upper(skin, Style.L(if banner.Name == "Surge" then "hud.surgeShort" else "hud.secondWind"))
					.. "  "
					.. Style.FormatCd(left)
			)
			banner.Fill.Size = UDim2.fromScale(math.clamp(left / banner.Total, 0, 1), 1)
		end
		if me.Downed then
			local left = math.max(0, (me.DownedEndsAt or now) - now)
			local total = ((Style.Config() or {}).Human or {}).DownedTime or 15
			bleedFill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
			Style.SetText(bleedText, Style.L("hud.downed.bleed", math.ceil(left)))
		end
		if dodgeGroup.Visible then
			local exhausted = (me.ExhaustedUntil or 0) > now
			dodgePips.Root.Visible = not exhausted
			exhaustLabel.Visible = exhausted
			if exhausted then
				Style.SetText(
					exhaustLabel,
					Style.Upper(skin, Style.L("hud.exhaustedFor", Style.FormatCd(me.ExhaustedUntil - now)))
				)
			end
		end
	end

	local function update(s: { [string]: any })
		snap = s
		local me = s.Me
		touch = s.Device == "Touch"
		root.Visible = me ~= nil
		if not me then
			return
		end
		local kit = Style.Kit(me.KitId)
		local monster = me.Team == "Monster" or (kit ~= nil and kit.Role == "Monster")
		local hpWidth = if monster
			then (if phone then 170 else 250)
			else math.clamp(math.floor((me.MaxHP or 100) * (if phone then 1.3 else 1.9)), 120, 290)
		local shape = string.format("%s|%s|%d|%s", tostring(monster), skin.Id, hpWidth, tostring(touch))
		if shape ~= lastShape then
			lastShape = shape
			chipKey, bannerKey = "~", "~"
			build(monster, hpWidth)
		end
		local soulColor = if me.SoulMode == "Blue" then BLUE_SOUL else (if kit then kit.Color else C.SoulRed)
		local soulKey = shape .. tostring(soulColor)
		if soulKey ~= lastSoul then
			lastSoul = soulKey
			soulHolder:ClearAllChildren()
		end
		if #soulHolder:GetChildren() == 0 then
			if monster then
				local skull = Style.Icon("Skull", soulColor, UDim2.fromScale(1, 1))
				skull.Parent = soulHolder
			else
				local heart =
					Style.Heart(soulColor, if battle then 18 else math.floor(soulHolder.Size.X.Offset), "Whole")
				heart.Parent = soulHolder
			end
		end
		Style.SetText(nameLabel, if battle then Style.Upper(skin, tostring(me.Name)) else tostring(me.Name))
		Style.SetText(lvLabel, Style.Upper(skin, Style.L("hud.lv", me.Level or 1)))
		if titleLabel then
			Style.SetText(
				titleLabel,
				Style.Upper(skin, if me.Title ~= "" then me.Title elseif kit then Style.Pick(kit.Title) else "")
			)
			titleLabel.TextColor3 = if kit then kit.Color else C.Dim
		end
		local hp = if me.Downed then 0 else (me.HP or 0)
		hpBar.Set(hp, math.max(1, me.MaxHP or 1), if monster then nil else math.min(me.KR or 0, hp))
		if guardBar then
			guardBar.Set(me.Guard or 0, math.max(1, me.MaxGuard or 100))
		end
		dashPips.Set(
			(me.Dash or 0) + (if (me.Dash or 0) < (me.DashMax or 2) then (me.DashNext or 0) else 0),
			me.DashMax or 2
		)
		dodgePips.Set(me.Dodges or 0, me.MaxDodges or 0)
		local ult = math.clamp(me.Ult or 0, 0, 100)
		if ultBar then
			ultBar.Set(ult, 100)
			ultBar.SetColor(if ult >= 100 then C.UltFull else C.Ult)
		end
		if ultRing then
			ultRing.Set(ult / 100)
		end
		if readyChip then
			readyChip.Visible = ult >= 100
		end
		Style.SetText(
			ultText,
			if ult >= 100 then Style.Upper(skin, Style.L("hud.ready")) else string.format("%d%%", math.floor(ult))
		)
		ultText.TextColor3 = if ult >= 100 then C.UltFull else C.Text
		Style.SetText(
			shieldLabel,
			if (me.Shield or 0) > 0 then Style.Upper(skin, Style.L("hud.shield", math.floor(me.Shield))) else ""
		)
		shieldLabel.Visible = (me.Shield or 0) > 0
		-- overlays
		lowHp.Visible = not me.Downed
			and not me.Dead
			and (me.HP or 0) / math.max(1, me.MaxHP or 1) < 0.3
			and (me.HP or 0) > 0
		downed.Visible = me.Downed == true and not me.Dead
		block.Visible = not me.Dead
		if me.Downed then
			if dHeartKit ~= me.KitId then
				dHeartKit = me.KitId
				dHeartHolder:ClearAllChildren()
				local heart = Style.Heart(if kit then kit.Color else C.SoulRed, if phone then 52 else 72, "Cracked")
				heart.Parent = dHeartHolder
			end
			local revives = s.TeamRevives or 0
			Style.SetText(
				revText,
				if revives > 0 then Style.L("hud.downed.revives", revives) else Style.L("hud.downed.noRevives")
			)
			revText.TextColor3 = if revives > 0 then C.Dim else C.Danger
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

return RoundHud
