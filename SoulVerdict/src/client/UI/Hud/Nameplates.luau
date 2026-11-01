--!strict
-- Hud/Nameplates: BillboardGuis above every other character — name, LV + title, SOUL heart in the class
-- colour (humans), a mini HP bar with KR for teammates (DOWN timer while downed), a skull (crown in the final
-- phase) marker in the kit colour above the monster. Enemies get a shorter MaxDistance, are not AlwaysOnTop
-- (no wall-hacks) and are hidden while their Invisible attribute is set (Patience stealth).
--   Nameplates.Create(theme, deps) -> { Root, Update(snapshot), Destroy }
--       live (deps.Live): billboards are parented to deps.BillboardParent (PlayerGui) in a "SV_Nameplates"
--       folder; offline: a row of sample plates is drawn on Root for previews.
--   Nameplates.BuildPlate(skin, unit, viewerTeam) -> { Root: Frame, Set(unit, viewerTeam, now) }
-- Data: snapshot.Humans, Monster, Others (lobby bodies), Me (viewer team), Now.
local Style = require(script.Parent.Style)

local Nameplates = {}

local PLATE = Vector2.new(230, 76)

local function isTeammate(unit: any, viewerTeam: string): boolean
	if viewerTeam == "Spectator" or viewerTeam == "Lobby" then
		return unit.Team ~= "Monster"
	end
	return unit.Team == viewerTeam
end

function Nameplates.BuildPlate(skin: any, unit: any, viewerTeam: string): any
	local C = skin.C
	local battle = skin.Battle
	local root = Style.Frame({ Name = "Plate", Size = UDim2.fromOffset(PLATE.X, PLATE.Y) })
	local marker = Style.Frame({
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		Parent = root,
	})
	local nameRow = Style.Frame({
		Name = "NameRow",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = root,
	})
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 6)
	l.Parent = nameRow
	local heartHolder =
		Style.Frame({ Name = "Soul", Size = UDim2.fromOffset(15, 14), LayoutOrder = 1, Parent = nameRow })
	local name = Style.Text(skin, {
		Name = "Name",
		Text = "",
		Upper = false,
		Role = if battle then "Label" else "Title",
		TextSize = if battle then 12 else 16,
		AutoX = true,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		Parent = nameRow,
	})
	local sub = Style.Text(skin, {
		Name = "Sub",
		Text = "",
		Upper = false,
		TextSize = if battle then 8 else 11,
		Color = C.Dim,
		X = "Center",
		Position = UDim2.fromOffset(0, 43),
		Size = UDim2.new(1, 0, 0, 12),
		Parent = root,
	})
	local bar = Style.Bar(skin, {
		Name = "HP",
		Kind = "HP",
		Value = 1,
		Max = 1,
		Secondary = 0,
		Height = 6,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(120, 7),
		Parent = root,
	})
	local down = Style.Text(skin, {
		Name = "Down",
		Text = "",
		TextSize = if battle then 9 else 12,
		Color = C.Danger,
		X = "Center",
		Position = UDim2.fromOffset(0, 57),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = root,
	})
	local key = ""
	local function set(u: any, viewer: string, now: number)
		local kit = Style.Kit(u.KitId)
		local color = if kit then kit.Color else C.SoulRed
		local monster = u.Team == "Monster"
		local mate = isTeammate(u, viewer)
		local k =
			string.format("%s|%s|%s|%s", tostring(color), tostring(monster), tostring(u.Downed), tostring(u.FinalForm))
		if k ~= key then
			key = k
			marker:ClearAllChildren()
			heartHolder:ClearAllChildren()
			if monster then
				local icon = Style.Icon(if u.FinalForm then "Crown" else "Skull", color, UDim2.fromScale(1, 1))
				icon.Parent = marker
			else
				local heart = Style.Heart(color, 15, if u.Downed then "Cracked" else "Whole")
				heart.Parent = heartHolder
			end
		end
		marker.Visible = monster
		heartHolder.Visible = not monster
		Style.SetText(name, if battle then Style.Upper(skin, tostring(u.Name)) else tostring(u.Name))
		name.TextColor3 = if monster
			then color:Lerp(Style.WHITE, 0.35)
			elseif mate then Style.WHITE
			else Color3.fromRGB(255, 170, 170)
		local subText = Style.L("hud.lv", u.Level or 1)
		if u.Title and u.Title ~= "" then
			subText ..= "  ·  " .. u.Title
		elseif kit then
			subText ..= "  ·  " .. Style.Pick(kit.Title)
		end
		Style.SetText(sub, if battle then Style.Upper(skin, subText) else subText)
		local showBar = mate and not monster and not u.Downed
		bar.Root.Visible = showBar
		if showBar then
			bar.Set(u.HP or 0, math.max(1, u.MaxHP or 1), math.min(u.KR or 0, u.HP or 0))
		end
		down.Visible = u.Downed == true
		if u.Downed then
			Style.SetText(
				down,
				Style.Upper(skin, Style.L("hud.team.down", math.max(0, math.ceil((u.DownedEndsAt or now) - now))))
			)
		end
	end
	set(unit, viewerTeam, 0)
	return { Root = root, Set = set }
end

function Nameplates.Create(theme: any, deps: any): any
	local skin, _layout, root = Style.Context(theme, deps, "Nameplates")
	local d = if type(deps) == "table" then deps else {}
	local live = d.Live == true
	local folder: Folder? = nil
	if live and d.BillboardParent then
		local f = Instance.new("Folder")
		f.Name = "SV_Nameplates"
		f.Parent = d.BillboardParent
		folder = f
	end
	type Entry = { Gui: BillboardGui, Plate: any, Model: Model }
	local entries: { [Model]: Entry } = {}

	local function units(s: { [string]: any }): { any }
		local out = {}
		for _, u in s.Humans or {} do
			table.insert(out, u)
		end
		if s.Monster then
			table.insert(out, s.Monster)
		end
		for _, u in s.Others or {} do
			table.insert(out, u)
		end
		return out
	end

	local function updateLive(s: { [string]: any })
		if not folder then
			return
		end
		local viewer = if s.Me and not s.Me.Dead
			then s.Me.Team
			else (if s.Role == "Spectator" then "Spectator" else "Lobby")
		local seen: { [Model]: boolean } = {}
		for _, u in units(s) do
			local model = u.Model
			if model and not u.IsLocal and not u.Dead and model.Parent then
				seen[model] = true
				local entry = entries[model]
				if entry == nil then
					local adornee = model:FindFirstChild("Head") or model.PrimaryPart
					if adornee then
						local gui = Instance.new("BillboardGui")
						gui.Name = "Plate_" .. model.Name
						gui.Size = UDim2.fromOffset(PLATE.X, PLATE.Y)
						gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
						gui.LightInfluence = 0
						gui.ResetOnSpawn = false
						gui.ClipsDescendants = false
						gui.Adornee = adornee :: any
						local plate = Nameplates.BuildPlate(skin, u, viewer)
						plate.Root.Parent = gui
						gui.Parent = folder
						entry = { Gui = gui, Plate = plate, Model = model }
						entries[model] = entry
						local humanoid = model:FindFirstChildOfClass("Humanoid")
						if humanoid then
							pcall(function()
								humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
							end)
						end
					end
				end
				if entry then
					local mate = isTeammate(u, viewer)
					entry.Gui.AlwaysOnTop = mate
					entry.Gui.MaxDistance = if mate then 260 else 90
					entry.Gui.Enabled = not (u.Invisible and not mate)
					entry.Plate.Set(u, viewer, s.Now or 0)
				end
			end
		end
		for model, entry in entries do
			if not seen[model] then
				entry.Gui:Destroy()
				entries[model] = nil
			end
		end
	end

	local function updatePreview(s: { [string]: any })
		root:ClearAllChildren()
		local row = Style.Frame({
			Name = "Row",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(4 * (PLATE.X + 40) - 40, PLATE.Y),
			Parent = root,
		})
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, 40)
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = row
		local viewer = if s.Me then s.Me.Team else "Humans"
		local samples = {}
		for _, u in s.Humans or {} do
			if not u.IsLocal and #samples < 3 then
				table.insert(samples, u)
			end
		end
		if s.Monster then
			table.insert(samples, s.Monster)
		end
		for i, u in samples do
			local plate = Nameplates.BuildPlate(skin, u, viewer)
			plate.Set(u, viewer, s.Now or 0)
			plate.Root.LayoutOrder = i
			plate.Root.Parent = row
		end
	end

	local function update(s: { [string]: any })
		if live then
			updateLive(s)
		else
			updatePreview(s)
		end
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Destroy = function()
			for _, entry in entries do
				entry.Gui:Destroy()
			end
			table.clear(entries)
			if folder then
				folder:Destroy()
			end
			root:Destroy()
		end,
	}
end

return Nameplates
