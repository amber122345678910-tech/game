--!strict
-- Hud/Objectives: SAVE star markers (screen-space marker above each star with a progress ring, distance and
-- channel % / CONTESTED; clamped to the screen edge with an arrow when off-screen; lit stars shrink to a gold
-- check) and the Collapse ring warning (edge vignette + "GET BACK INSIDE THE RING!" + ring radius).
--   Objectives.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
-- Data: snapshot.Saves (from star Models tagged "SaveStar" in workspace.Objectives: Index, Progress, Lit,
-- Contested, Channelers, Radius; Position from the model pivot — see ObjectiveService header), Collapse
-- {Radius, Center, Distance, Outside}. Live markers are projected every frame with workspace.CurrentCamera;
-- previews use Save.Screen (0..1 scale coordinates, outside 0..1 = off-screen).
local Style = require(script.Parent.Style)

local Objectives = {}

local EDGE = 64

function Objectives.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "Objectives")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local canvas: Vector2 = layout.Canvas
	local scale: number = layout.Scale or 1
	local live = type(deps) == "table" and deps.Live == true

	-- collapse warning
	local warn = Style.Frame({ Name = "Collapse", Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })
	Style.Vignette({
		Name = "Vignette",
		Color = Color3.fromRGB(150, 40, 255),
		Strength = 0.7,
		Depth = 0.22,
		Parent = warn,
	})
	local warnBox = Style.Box(skin, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if phone then 0.56 else 0.6),
		Size = UDim2.fromOffset(if phone then 360 else 520, if phone then 46 else 60),
		Border = C.Danger,
		Stroke = if battle then 3 else 2,
		Parent = warn,
	})
	Style.Text(skin, {
		Name = "Title",
		Text = Style.L("hud.collapse.warn"),
		Role = "Title",
		TextSize = if phone then 12 else (if battle then 16 else 20),
		Color = C.Danger,
		X = "Center",
		Position = UDim2.fromOffset(0, if phone then 5 else 7),
		Size = UDim2.new(1, 0, 0, if phone then 18 else 24),
		Parent = warnBox,
	})
	local ringText = Style.Text(skin, {
		Name = "Ring",
		Text = "",
		TextSize = if phone then 9 else skin.Size.Small + 1,
		Color = C.Dim,
		X = "Center",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -5),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = warnBox,
	})

	type Marker = {
		Root: Frame,
		Ring: any,
		RingFill: Frame?,
		StarHolder: Frame,
		Label: TextLabel,
		Sub: TextLabel,
		Arrow: Frame,
		ArrowKey: string,
		StarKey: string,
	}
	local markers: { Marker } = {}
	local snap: { [string]: any }? = nil
	local touch = false

	local size = if phone then 38 else 48
	local function newMarker(i: number): Marker
		local m = Style.Frame({
			Name = "Save" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			Parent = root,
		})
		local disc = Style.Frame({
			Name = "Disc",
			BackgroundTransparency = if battle then 0 else 0.3,
			BackgroundColor3 = Style.BLACK,
			Size = UDim2.fromScale(1, 1),
			Parent = m,
		})
		Style.Corner(disc, UDim.new(0.5, 0))
		local ring = Style.Radial({ Name = "Progress", Mode = "Filled", Color = C.Gold, Circle = true, Parent = disc })
		local inner = Style.Frame({
			Name = "Inner",
			BackgroundTransparency = 0,
			BackgroundColor3 = if battle then Style.BLACK else Color3.fromRGB(14, 16, 26),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 1, -8),
			Parent = disc,
		})
		Style.Corner(inner, UDim.new(0.5, 0))
		if battle then
			Style.Stroke(disc, Style.WHITE, 2, 0)
		end
		local starHolder = Style.Frame({
			Name = "Star",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size * 0.5, size * 0.5),
			Parent = inner,
		})
		local label = Style.Text(skin, {
			Name = "Label",
			Text = "",
			TextSize = if phone then 9 else (if battle then 10 else 13),
			X = "Center",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 4),
			Size = UDim2.fromOffset(140, 14),
			Parent = m,
		})
		local sub = Style.Text(skin, {
			Name = "Sub",
			Text = "",
			Role = "Number",
			TextSize = if phone then 8 else (if battle then 9 else 12),
			Color = C.Dim,
			X = "Center",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, if phone then 16 else 20),
			Size = UDim2.fromOffset(140, 12),
			Parent = m,
		})
		local arrow = Style.Frame({
			Name = "Arrow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size * 0.5, size * 0.5),
			Visible = false,
			Parent = m,
		})
		return {
			Root = m,
			Ring = ring,
			StarHolder = starHolder,
			Label = label,
			Sub = sub,
			Arrow = arrow,
			ArrowKey = "",
			StarKey = "",
		}
	end

	-- place a marker at canvas position (x, y); offscreen markers are clamped with an outward arrow
	local function place(mk: Marker, x: number, y: number, behind: boolean)
		local cx, cy = canvas.X / 2, canvas.Y / 2
		local px, py = x, y
		if behind then
			px, py = cx - (x - cx) * 1000, cy - (y - cy) * 1000
		end
		local off = behind or px < EDGE or px > canvas.X - EDGE or py < EDGE + 40 or py > canvas.Y - EDGE - 60
		local dir = ""
		if off then
			local dx, dy = px - cx, py - cy
			local kx = if dx ~= 0 then (canvas.X / 2 - EDGE) / math.abs(dx) else math.huge
			local ky = if dy ~= 0 then (canvas.Y / 2 - EDGE - 50) / math.abs(dy) else math.huge
			local k = math.min(kx, ky, 1)
			px, py = cx + dx * k, cy + dy * k
			if kx < ky then
				dir = if dx > 0 then "ArrowRight" else "ArrowLeft"
			else
				dir = if dy > 0 then "ArrowDown" else "ArrowUp"
			end
		end
		if touch and px > canvas.X - 340 and py > canvas.Y - 300 then
			py = canvas.Y - 300 -- keep clear of the touch button cluster
		end
		mk.Root.Position = UDim2.fromOffset(px, py)
		mk.Arrow.Visible = off
		if off and mk.ArrowKey ~= dir then
			mk.ArrowKey = dir
			mk.Arrow:ClearAllChildren()
			local icon = Style.Icon(if dir == "ArrowRight" then "Arrow" else dir, C.Gold, UDim2.fromScale(1, 1))
			icon.Parent = mk.Arrow
			local offset = size * 0.82
			mk.Arrow.Position = if dir == "ArrowRight"
				then UDim2.new(0.5, offset, 0.5, 0)
				elseif dir == "ArrowLeft" then UDim2.new(0.5, -offset, 0.5, 0)
				elseif dir == "ArrowDown" then UDim2.new(0.5, 0, 0.5, offset)
				else UDim2.new(0.5, 0, 0.5, -offset)
		end
	end

	local function tick(_now: number)
		local s = snap
		if not s then
			return
		end
		local cam: Camera? = nil
		if live then
			local ok, c = pcall(function()
				return workspace.CurrentCamera
			end)
			cam = if ok then c else nil
		end
		for i, save in s.Saves or {} do
			local mk = markers[i]
			if mk then
				if cam and typeof(save.Position) == "Vector3" then
					local vp, _onScreen = cam:WorldToViewportPoint(save.Position + Vector3.new(0, 3, 0))
					place(mk, vp.X / scale, vp.Y / scale, vp.Z < 0)
				elseif typeof(save.Screen) == "Vector2" then
					place(mk, save.Screen.X * canvas.X, save.Screen.Y * canvas.Y, false)
				end
			end
		end
	end

	local function update(s: { [string]: any })
		snap = s
		touch = s.Device == "Touch"
		local saves = s.Saves or {}
		while #markers < #saves do
			table.insert(markers, newMarker(#markers + 1))
		end
		while #markers > #saves do
			local mk = table.remove(markers) :: Marker
			mk.Root:Destroy()
		end
		for i, save in saves do
			local mk = markers[i]
			local lit = save.Lit == true
			local starKey = if lit then "lit" elseif save.Contested then "contested" else "idle"
			if starKey ~= mk.StarKey then
				mk.StarKey = starKey
				mk.StarHolder:ClearAllChildren()
				local icon = Style.Icon(
					if lit then "Check" else "Star",
					if lit then C.Gold elseif save.Contested then C.Danger else Style.WHITE,
					UDim2.fromScale(1, 1)
				)
				icon.Parent = mk.StarHolder
			end
			mk.Ring.Set(if lit then 1 else math.clamp(save.Progress or 0, 0, 1))
			mk.Root.Size = UDim2.fromOffset(if lit then size * 0.72 else size, if lit then size * 0.72 else size)
			Style.SetText(mk.Label, Style.Upper(skin, Style.L("hud.obj.save", save.Index or i)))
			mk.Label.TextColor3 = if lit then C.Gold else C.Text
			local sub
			if lit then
				sub = Style.Upper(skin, Style.L("hud.obj.lit"))
			elseif save.Contested then
				sub = Style.Upper(skin, Style.L("round.save.contested"))
			else
				local parts = {}
				if (save.Progress or 0) > 0 then
					table.insert(parts, Style.L("hud.obj.channel", math.floor((save.Progress or 0) * 100)))
				end
				if save.Distance then
					table.insert(parts, Style.L("hud.obj.distance", math.floor(save.Distance)))
				end
				sub = table.concat(parts, " · ")
			end
			Style.SetText(mk.Sub, sub)
			mk.Sub.TextColor3 = if save.Contested and not lit then C.Danger elseif lit then C.Gold else C.Dim
		end
		local collapse = s.Collapse
		warn.Visible = collapse ~= nil and collapse.Outside == true
		if collapse then
			Style.SetText(
				ringText,
				Style.Upper(skin, Style.L("hud.collapse.radius", math.floor(collapse.Radius or 0)))
					.. "  ·  "
					.. Style.L("hud.obj.distance", math.floor(collapse.Distance or 0))
			)
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

return Objectives
