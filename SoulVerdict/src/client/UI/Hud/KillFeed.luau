--!strict
-- Hud/KillFeed: top-right event feed — kills, downs, revives, SAVE stars lit, Surge, Second Wind, players
-- leaving. Names are drawn in their kit colour with the ability icon between them; entries expire after
-- 7 s (newest on top, max 5; 3 on phones).
--   KillFeed.Create(theme, deps) -> { Root, Push(entry), Update(snapshot), Tick(now), Clear(), Destroy }
--   entry = FeedEntry (Hud/Mock.luau): { Kind, A?, AColor?, B?, BColor?, Icon?, Text?, Time }
-- Live entries come from RoundEvents (Kill / Downed / Revived / SaveLit / Surge / SecondWind / PlayerLeft),
-- converted by Hud/init.luau; previews render snapshot.Feed.
local Style = require(script.Parent.Style)

local KillFeed = {}

local LIFETIME = 7

function KillFeed.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "KillFeed")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local maxEntries = if phone then 3 else 5
	local rowH = if phone then 24 else 32
	local list = Style.Frame({
		Name = "List",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, if phone then -10 else -20, 0, if phone then 8 else 18),
		Size = UDim2.fromOffset(if phone then 290 else 460, (rowH + 6) * maxEntries),
		Parent = root,
	})
	local layoutObj = Instance.new("UIListLayout")
	layoutObj.SortOrder = Enum.SortOrder.LayoutOrder
	layoutObj.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layoutObj.Padding = UDim.new(0, 6)
	layoutObj.Parent = list

	type Row = { Frame: Frame, Time: number }
	local rows: { Row } = {}
	local order = 0
	local textSize = if phone then (if battle then 8 else 11) else (if battle then 10 else 14)

	local function nameText(parent: Instance, text: string, color: Color3?, layoutOrder: number)
		Style.Text(skin, {
			Name = "Name",
			Text = if battle then Style.Upper(skin, text) else text,
			Upper = false,
			Role = if battle then "Label" else "Title",
			TextSize = textSize,
			Color = color or C.Text,
			AutoX = true,
			Stroke = false,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = layoutOrder,
			Parent = parent,
		})
	end

	local function iconOf(parent: Instance, name: string, color: Color3, layoutOrder: number)
		local holder = Style.Frame({ Name = "Icon", Size = UDim2.fromOffset(rowH - 10, rowH - 10), LayoutOrder = layoutOrder, Parent = parent })
		local icon = Style.Icon(name, color, UDim2.fromScale(1, 1))
		icon.Parent = holder
	end

	local function push(entry: { [string]: any })
		order -= 1
		local box = Style.Box(skin, {
			Name = "Entry",
			Size = UDim2.fromOffset(0, rowH),
			Stroke = if battle then 2 else 1,
			Transparency = if battle then 0.1 else 0.35,
			Sheen = false,
			Corner = UDim.new(0, 8),
			LayoutOrder = order,
		})
		box.AutomaticSize = Enum.AutomaticSize.X
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = box
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Padding = UDim.new(0, 8)
		row.Parent = box
		local kind = entry.Kind
		if kind == "Kill" or kind == "Downed" or kind == "Revived" then
			if entry.A and entry.A ~= "" then
				nameText(box, entry.A, entry.AColor, 1)
				iconOf(box, entry.Icon or (if kind == "Revived" then "Heart" else "Skull"), if kind == "Revived" then C.Good else (entry.AColor or C.Text), 2)
				nameText(box, entry.B or "?", entry.BColor, 3)
			else
				iconOf(box, entry.Icon or "Skull", C.Muted, 1)
				nameText(box, entry.Text or (entry.B or "?"), entry.BColor, 2)
			end
			if kind == "Kill" then
				local holder = Style.Frame({ Name = "Shattered", Size = UDim2.fromOffset(rowH - 12, rowH - 12), LayoutOrder = 4, Parent = box })
				local heart = Style.Heart(entry.BColor or C.SoulRed, rowH - 12, "Broken")
				heart.Parent = holder
			elseif kind == "Downed" then
				nameText(box, Style.Upper(skin, Style.L("hud.downed.title")), C.Warn, 4)
			end
		elseif kind == "Save" then
			iconOf(box, "Star", C.Gold, 1)
			nameText(box, Style.L("hud.feed.save", entry.A or "?", entry.B or "?"), C.Gold, 2)
		elseif kind == "Surge" then
			iconOf(box, "Star", C.Gold, 1)
			nameText(box, Style.L("hud.feed.surge"), C.Gold, 2)
		elseif kind == "SecondWind" then
			iconOf(box, "Heart", Color3.fromRGB(120, 255, 200), 1)
			nameText(box, Style.L("hud.feed.secondWind", entry.A or "?"), Color3.fromRGB(120, 255, 200), 2)
		else
			if entry.Icon then
				iconOf(box, entry.Icon, C.Dim, 1)
			end
			nameText(box, entry.Text or "", C.Dim, 2)
		end
		box.Parent = list
		table.insert(rows, 1, { Frame = box, Time = entry.Time or 0 })
		while #rows > maxEntries do
			local old = table.remove(rows) :: Row
			old.Frame:Destroy()
		end
		if Style.Live() then
			local scaleObj = Instance.new("UIScale")
			scaleObj.Scale = 1.15
			scaleObj.Parent = box
			Style.Tween(scaleObj, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end

	local function clear()
		for _, r in rows do
			r.Frame:Destroy()
		end
		table.clear(rows)
	end

	local function tick(now: number)
		for i = #rows, 1, -1 do
			if now - rows[i].Time > LIFETIME then
				rows[i].Frame:Destroy()
				table.remove(rows, i)
			end
		end
	end

	local function update(s: { [string]: any })
		if not Style.Live() and s.Feed then
			clear()
			for _, entry in s.Feed do
				push(entry)
			end
		end
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Push = push,
		Update = update,
		Tick = tick,
		Clear = clear,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return KillFeed
