--!strict
-- Hud/TopStrip: the timer / phase strip at the top centre: SAVE stars lit, phase + time left, humans alive.
--   TopStrip.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
-- Data: Phase, EndsAt, Practice, SavesLit/SavesTotal, HumansAlive/HumansTotal, FinalPhase (snapshot, Hud/Mock).
local Style = require(script.Parent.Style)

local TopStrip = {}

local PHASE_COLOR = { Collapse = "Danger", Ending = "Gold", Intro = "Accent" }

function TopStrip.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "TopStrip")
	local C = skin.C
	local phone = layout.Phone
	local W = if phone then 372 else 476
	local H = if phone then 44 else 54
	local box = Style.Box(skin, {
		Name = "Strip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if phone then 8 else 14),
		Size = UDim2.fromOffset(W, H),
		Corner = if skin.Battle then nil else UDim.new(0.5, 0),
		Parent = root,
	})
	local cells = { 0.31, 0.38, 0.31 }
	local x = 0
	local cellFrames: { Frame } = {}
	for i, w in cells do
		local cell = Style.Frame({ Name = "Cell" .. i, Position = UDim2.fromScale(x, 0), Size = UDim2.fromScale(w, 1), Parent = box })
		table.insert(cellFrames, cell)
		x += w
		if i < #cells then
			Style.Frame({
				Name = "Divider" .. i,
				BackgroundTransparency = if skin.Battle then 0 else 0.8,
				BackgroundColor3 = C.Box,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.5),
				Size = if skin.Battle then UDim2.new(0, 3, 1, 0) else UDim2.new(0, 1, 0.6, 0),
				Parent = box,
			})
		end
	end
	local small = if phone then skin.Size.Small - 1 else skin.Size.Small
	local function caption(parent: Frame, text: string): TextLabel
		return Style.Text(skin, {
			Name = "Caption",
			Text = text,
			TextSize = small,
			Color = C.Dim,
			X = "Center",
			Stroke = false,
			Position = UDim2.fromOffset(0, if phone then 4 else 6),
			Size = UDim2.new(1, 0, 0, small + 2),
			Parent = parent,
		})
	end
	-- saves
	caption(cellFrames[1], Style.L("hud.saves"))
	local stars = Style.Frame({
		Name = "Stars",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if phone then -5 else -7),
		Size = UDim2.fromOffset(90, if phone then 18 else 22),
		Parent = cellFrames[1],
	})
	local starIcons: { Frame } = {}
	local starState = ""
	-- timer
	local phaseLabel = caption(cellFrames[2], "")
	local timer = Style.Text(skin, {
		Name = "Time",
		Text = "0:00",
		Role = "Number",
		TextSize = if phone then 18 else (if skin.Battle then 22 else 26),
		X = "Center",
		Stroke = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if phone then -3 else -5),
		Size = UDim2.new(1, 0, 0, if phone then 22 else 28),
		Parent = cellFrames[2],
	})
	-- alive
	caption(cellFrames[3], Style.L("hud.alive"))
	local aliveRow = Style.Frame({
		Name = "AliveRow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if phone then -4 else -6),
		Size = UDim2.fromOffset(100, if phone then 18 else 22),
		Parent = cellFrames[3],
	})
	local heart = Style.Heart(C.SoulRed, if phone then 14 else 17, "Whole")
	heart.AnchorPoint = Vector2.new(0, 0.5)
	heart.Position = UDim2.new(0, 14, 0.5, 0)
	heart.Parent = aliveRow
	local alive = Style.Text(skin, {
		Name = "Alive",
		Text = "0/0",
		Role = "Number",
		TextSize = if phone then 14 else 17,
		Stroke = false,
		Position = UDim2.fromOffset(if phone then 34 else 38, 0),
		Size = UDim2.new(1, -38, 1, 0),
		Parent = aliveRow,
	})

	local snap: { [string]: any }? = nil

	local function buildStars(total: number, lit: number)
		local key = total .. ":" .. lit
		if key == starState then
			return
		end
		starState = key
		for _, s in starIcons do
			s:Destroy()
		end
		table.clear(starIcons)
		local size = if phone then 18 else 22
		local gap = 6
		local width = total * size + (total - 1) * gap
		stars.Size = UDim2.fromOffset(width, size)
		for i = 1, total do
			local isLit = i <= lit
			local icon = Style.Icon("Star", if isLit then C.Gold else C.Muted, size)
			icon.Name = "Star" .. i
			icon.AnchorPoint = Vector2.new(0, 0)
			icon.Position = UDim2.fromOffset((i - 1) * (size + gap), 0)
			icon.Parent = stars
			table.insert(starIcons, icon)
		end
	end

	local function tick(now: number)
		local s = snap
		if not s then
			return
		end
		local left = math.max(0, (s.EndsAt or 0) - now)
		Style.SetText(timer, if (s.EndsAt or 0) > 0 then Style.FormatClock(left) else "--:--")
		local urgent = left <= 10 and (s.Phase == "Round" or s.Phase == "Collapse") and (s.EndsAt or 0) > 0
		timer.TextColor3 = if urgent or s.Phase == "Collapse" then C.Danger else C.Text
	end

	local function update(s: { [string]: any })
		snap = s
		buildStars(math.max(1, s.SavesTotal or 3), s.SavesLit or 0)
		local phase = s.Phase or "Round"
		local text = Style.L("round.phase." .. phase)
		if s.Practice and phase == "Round" then
			text = Style.L("hud.practice")
		end
		Style.SetText(phaseLabel, Style.Upper(skin, text))
		local tone = PHASE_COLOR[phase]
		phaseLabel.TextColor3 = if tone then C[tone] else C.Dim
		Style.SetText(alive, string.format("%d/%d", s.HumansAlive or 0, s.HumansTotal or 0))
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

return TopStrip
