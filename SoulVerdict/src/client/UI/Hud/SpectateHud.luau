--!strict
-- Hud/SpectateHud: shown while the local player spectates (dead or late joiner): who is being watched (SOUL
-- heart in the class colour, name, class + LV, live HP bar with KR), PREV / NEXT hints (InputController
-- KeyLabel; touch arrows call deps.Spectate.Prev/Next when the SpectateController provides them) and a
-- "* Cheer them on" line.
--   SpectateHud.Create(theme, deps) -> { Root, Update(snapshot), Destroy }
-- Data: snapshot.Spectating (Unit; live: deps.Spectate.Target() or Hud handle SetSpectateTarget(model)).
local Style = require(script.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)

local SpectateHud = {}

function SpectateHud.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "SpectateHud")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local d = if type(deps) == "table" then deps else {}
	local W = if phone then 420 else 560
	local H = if phone then 76 else 96
	local panel = Style.Box(skin, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if phone then -12 else -28),
		Size = UDim2.fromOffset(W, H),
		Stroke = if battle then 4 else nil,
		Parent = root,
	})
	Style.Text(skin, {
		Name = "Caption",
		Text = Style.L("hud.spec.title"),
		TextSize = if phone then 9 else skin.Size.Small,
		Color = C.Dim,
		X = "Center",
		Stroke = false,
		Position = UDim2.fromOffset(0, if phone then 6 else 9),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = panel,
	})
	local center = Style.Frame({ Name = "Target", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, if phone then 22 else 28), Size = UDim2.new(1, -200, 0, if phone then 20 else 26), Parent = panel })
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 10)
	row.Parent = center
	local heartHolder = Style.Frame({ Name = "Soul", Size = UDim2.fromOffset(20, 18), LayoutOrder = 1, Parent = center })
	local nameLabel = Style.Text(skin, { Name = "Name", Text = "", Role = "Title", TextSize = if phone then 13 else (if battle then 16 else 20), Upper = false, AutoX = true, Size = UDim2.new(0, 0, 1, 0), Stroke = false, LayoutOrder = 2, Parent = center })
	local classLabel = Style.Text(skin, { Name = "Class", Text = "", TextSize = if phone then 9 else (if battle then 10 else 13), AutoX = true, Size = UDim2.new(0, 0, 1, 0), Stroke = false, LayoutOrder = 3, Parent = center })
	local bar = Style.Bar(skin, {
		Name = "HP",
		Kind = "HP",
		Value = 1,
		Max = 1,
		Secondary = 0,
		Height = if phone then 7 else 9,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if phone then -10 else -14),
		Size = UDim2.fromOffset(if phone then 200 else 280, if phone then 9 else 11),
		Parent = panel,
	})
	local function hint(action: string, label: string, right: boolean)
		local holder = Style.Frame({
			Name = if right then "Next" else "Prev",
			AnchorPoint = Vector2.new(if right then 1 else 0, 0.5),
			Position = UDim2.new(if right then 1 else 0, if right then -14 else 14, 0.5, 6),
			Size = UDim2.fromOffset(90, 26),
			Parent = panel,
		})
		local cap = Style.KeyCap(skin, Style.KeyLabel(d, action), if phone then 18 else 22)
		cap.AnchorPoint = Vector2.new(if right then 1 else 0, 0.5)
		cap.Position = UDim2.fromScale(if right then 1 else 0, 0.5)
		cap.Parent = holder
		Style.Text(skin, {
			Name = "Label",
			Text = label,
			TextSize = if phone then 8 else (if battle then 9 else 12),
			Color = C.Dim,
			X = if right then "Right" else "Left",
			Stroke = false,
			AnchorPoint = Vector2.new(if right then 1 else 0, 0.5),
			Position = UDim2.new(if right then 1 else 0, if right then -32 else 32, 0.5, 0),
			Size = UDim2.new(1, -32, 1, 0),
			Parent = holder,
		})
		if d.Live and d.Spectate then
			local button = Instance.new("TextButton")
			button.Name = "Hit"
			button.Text = ""
			button.BackgroundTransparency = 1
			button.Size = UDim2.fromScale(1, 1)
			button.Parent = holder
			Motion.On(button, "Activated", function()
				local fn = d.Spectate[if right then "Next" else "Prev"]
				if type(fn) == "function" then
					pcall(fn)
				end
			end)
		end
	end
	hint("Q", Style.L("hud.spec.prev"), false)
	hint("E", Style.L("hud.spec.next"), true)
	local line = Style.Text(skin, {
		Name = "Line",
		Text = Style.L("hud.spec.line"),
		Role = "Body",
		TextSize = if phone then 10 else (if battle then 12 else 15),
		Upper = false,
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.new(1, 120, 0, 20),
		Parent = panel,
	})
	local heartKey = ""

	local function update(s: { [string]: any })
		local u = s.Spectating
		center.Visible = u ~= nil
		bar.Root.Visible = u ~= nil
		Style.SetText(line, Style.L(if u then "hud.spec.line" else "hud.spec.none"))
		if not u then
			return
		end
		local kit = Style.Kit(u.KitId)
		local color = if kit then kit.Color else C.SoulRed
		local key = tostring(color) .. tostring(u.Downed)
		if key ~= heartKey then
			heartKey = key
			heartHolder:ClearAllChildren()
			local heart = Style.Heart(color, 20, if u.Downed then "Cracked" else "Whole")
			heart.Parent = heartHolder
		end
		Style.SetText(nameLabel, if battle then Style.Upper(skin, tostring(u.Name)) else tostring(u.Name))
		Style.SetText(classLabel, Style.Upper(skin, (if kit then Style.Pick(kit.Name) .. "  " else "") .. Style.L("hud.lv", u.Level or 1)))
		classLabel.TextColor3 = color
		bar.Set(if u.Downed then 0 else (u.HP or 0), math.max(1, u.MaxHP or 1), math.min(u.KR or 0, u.HP or 0))
	end

	local initial = Style.Initial(deps, "Spectate")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return SpectateHud
