-- Settings widgets (slider / toggle / choice). Each menu style passes a theme:
-- { Font, Text, TextDim, Accent, Track, TrackTransparency, Knob, KnobStroke, RowHeight,
--   LabelSize, Width, ValueWidth, Uppercase, Textual, Corner, Sound(kind) }
local UserInputService = game:GetService("UserInputService")
local UI = require(script.Parent.UI)

local Widgets = {}

local function caption(theme, s: string): string
	return if theme.Uppercase then string.upper(s) else s
end

local function sound(theme, kind: string)
	if theme.Sound then
		theme.Sound(kind)
	end
end

local function makeRow(parent: Instance, theme, text: string, order: number)
	local row = UI.new("Frame", {
		Name = text,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(theme.Width, theme.RowHeight),
		LayoutOrder = order,
		Parent = parent,
	})
	local lbl = UI.label({
		Name = "Label",
		Font = theme.Font,
		Text = caption(theme, text),
		TextColor3 = theme.TextDim,
		TextSize = theme.LabelSize,
		Size = UDim2.fromScale(0.42, 1),
		Parent = row,
	})
	local right = UI.new("Frame", {
		Name = "Control",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.42, 0),
		Size = UDim2.fromScale(0.58, 1),
		Parent = row,
	})
	row.MouseEnter:Connect(function()
		lbl.TextColor3 = theme.Text
		sound(theme, "hover")
	end)
	row.MouseLeave:Connect(function()
		lbl.TextColor3 = theme.TextDim
	end)
	return row, right, lbl
end

local function textButton(theme, props)
	local base = {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Font = theme.Font,
		TextColor3 = theme.Text,
		TextSize = theme.LabelSize,
		Text = "",
	}
	for k, val in props do
		base[k] = val
	end
	return UI.new("TextButton", base)
end

function Widgets.Slider(parent: Instance, theme, opts)
	local row, right = makeRow(parent, theme, opts.Label, opts.Order or 0)
	local valueWidth = theme.ValueWidth or 70
	local value = opts.Value
	local minV, maxV = opts.Min, opts.Max
	local step = opts.Step or 0.05

	local function snap(x: number): number
		local s = math.floor((x - minV) / step + 0.5) * step + minV
		return math.clamp(s, minV, maxV)
	end

	local valueText = UI.label({
		Font = theme.Font,
		TextColor3 = theme.Text,
		TextSize = theme.LabelSize - 2,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, valueWidth, 1, 0),
		Parent = right,
	})

	local render: (number) -> ()
	if theme.Textual then
		local bar = textButton(theme, {
			TextColor3 = theme.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -valueWidth, 1, 0),
			Parent = right,
		})
		render = function(v)
			local n = math.floor((v - minV) / (maxV - minV) * 10 + 0.5)
			bar.Text = "< " .. string.rep("|", n) .. string.rep(".", 10 - n) .. " >"
		end
		bar.Activated:Connect(function(input)
			local x = if input then input.Position.X else bar.AbsolutePosition.X + bar.AbsoluteSize.X
			local mid = bar.AbsolutePosition.X + bar.AbsoluteSize.X / 2
			local delta = (maxV - minV) / 10
			value = snap(value + (if x < mid then -delta else delta))
			render(value)
			valueText.Text = if opts.Format then opts.Format(value) else tostring(value)
			sound(theme, "tick")
			if opts.OnChanged then
				opts.OnChanged(value)
			end
		end)
	else
		local track = textButton(theme, {
			BackgroundTransparency = theme.TrackTransparency or 0.7,
			BackgroundColor3 = theme.Track,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, -(valueWidth + 18), 0, theme.TrackHeight or 6),
			Parent = right,
		})
		if theme.Corner then
			UI.corner(theme.Corner).Parent = track
		end
		local fill = UI.new("Frame", {
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.5, 1),
			Parent = track,
		})
		if theme.Corner then
			UI.corner(theme.Corner).Parent = fill
		end
		local ks = theme.KnobSize or 18
		local knob = UI.new("Frame", {
			BackgroundColor3 = theme.Knob or theme.Accent,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(ks, ks),
			ZIndex = 2,
			Parent = track,
		})
		if theme.KnobShape ~= "square" then
			UI.round().Parent = knob
		end
		if theme.KnobStroke then
			UI.stroke(theme.KnobStrokeThickness or 2, theme.KnobStroke, 0, true).Parent = knob
		end
		-- big invisible hit area so it is easy to grab
		local hit = textButton(theme, {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, math.max(theme.RowHeight - 8, 24)),
			ZIndex = 3,
			Parent = track,
		})
		render = function(v)
			local a = (v - minV) / (maxV - minV)
			fill.Size = UDim2.fromScale(a, 1)
			knob.Position = UDim2.fromScale(a, 0.5)
		end
		local dragging = false
		local function fromX(x: number)
			local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			local old = value
			value = snap(minV + a * (maxV - minV))
			if value ~= old then
				render(value)
				valueText.Text = if opts.Format then opts.Format(value) else tostring(value)
				sound(theme, "tick")
				if opts.OnChanged then
					opts.OnChanged(value)
				end
			end
		end
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				fromX(input.Position.X)
			end
		end)
		local c1 = UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				fromX(input.Position.X)
			end
		end)
		local c2 = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		row.Destroying:Connect(function()
			c1:Disconnect()
			c2:Disconnect()
		end)
	end
	value = snap(value)
	render(value)
	valueText.Text = if opts.Format then opts.Format(value) else tostring(value)
	return row
end

function Widgets.Toggle(parent: Instance, theme, opts)
	local row, right = makeRow(parent, theme, opts.Label, opts.Order or 0)
	local value = opts.Value == true
	local render: () -> ()
	local button
	if theme.Textual then
		button = textButton(theme, {
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 1),
			Parent = right,
		})
		render = function()
			button.Text = if value then "[ ON  ]" else "[ OFF ]"
			button.TextColor3 = if value then theme.Accent else theme.TextDim
		end
	else
		button = textButton(theme, {
			BackgroundTransparency = theme.TrackTransparency or 0.7,
			BackgroundColor3 = theme.Track,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(58, 30),
			Parent = right,
		})
		UI.round().Parent = button
		if theme.KnobStroke then
			UI.stroke(theme.KnobStrokeThickness or 2, theme.KnobStroke, 0, true).Parent = button
		end
		local knob = UI.new("Frame", {
			BackgroundColor3 = theme.Knob or Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			Parent = button,
		})
		UI.round().Parent = knob
		local state = UI.label({
			Font = theme.Font,
			TextColor3 = theme.Text,
			TextSize = theme.LabelSize - 4,
			Position = UDim2.new(0, 72, 0, 0),
			Size = UDim2.new(0, 80, 1, 0),
			Parent = right,
		})
		render = function()
			UI.tween(knob, 0.18, { Position = if value then UDim2.new(1, -26, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) }, Enum.EasingStyle.Back)
			UI.tween(button, 0.18, {
				BackgroundColor3 = if value then theme.Accent else theme.Track,
				BackgroundTransparency = if value then 0 else (theme.TrackTransparency or 0.7),
			})
			state.Text = caption(theme, if value then "On" else "Off")
		end
	end
	button.Activated:Connect(function()
		value = not value
		render()
		sound(theme, "click")
		if opts.OnChanged then
			opts.OnChanged(value)
		end
	end)
	render()
	return row
end

function Widgets.Choice(parent: Instance, theme, opts)
	local row, right = makeRow(parent, theme, opts.Label, opts.Order or 0)
	local options = opts.Options
	local index = table.find(options, opts.Value) or 1
	local arrowW = 36
	local left = textButton(theme, {
		Text = if theme.Textual then "<" else "‹",
		TextColor3 = theme.Accent,
		TextSize = theme.LabelSize + 4,
		Size = UDim2.new(0, arrowW, 1, 0),
		Parent = right,
	})
	local rightBtn = textButton(theme, {
		Text = if theme.Textual then ">" else "›",
		TextColor3 = theme.Accent,
		TextSize = theme.LabelSize + 4,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, arrowW, 1, 0),
		Parent = right,
	})
	local valueLabel = UI.label({
		Font = theme.Font,
		TextColor3 = theme.Text,
		TextSize = theme.LabelSize - 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, arrowW, 0, 0),
		Size = UDim2.new(1, -arrowW * 2, 1, 0),
		Parent = right,
	})
	local function render()
		valueLabel.Text = caption(theme, options[index])
	end
	local function shift(d: number)
		index = (index - 1 + d) % #options + 1
		render()
		sound(theme, "click")
		if opts.OnChanged then
			opts.OnChanged(options[index])
		end
	end
	left.Activated:Connect(function()
		shift(-1)
	end)
	rightBtn.Activated:Connect(function()
		shift(1)
	end)
	render()
	return row, function(v)
		index = table.find(options, v) or index
		render()
	end
end

return Widgets
