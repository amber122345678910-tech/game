-- Tiny UI toolkit shared by all menu styles.
local TweenService = game:GetService("TweenService")

local UI = {}

UI.DESIGN_HEIGHT = 1080

function UI.new(class: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	local parent = nil
	if props then
		for k, val in props do
			if k == "Parent" then
				parent = val
			else
				(inst :: any)[k] = val
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

function UI.corner(radius: number | UDim): UICorner
	return UI.new("UICorner", { CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius :: number) })
end

function UI.round(): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function UI.stroke(thickness: number, color: Color3, transparency: number?, border: boolean?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness,
		Color = color,
		Transparency = transparency or 0,
		ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function UI.padding(l: number, t: number?, r: number?, b: number?): UIPadding
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingTop = UDim.new(0, t or l),
		PaddingRight = UDim.new(0, r or l),
		PaddingBottom = UDim.new(0, b or t or l),
	})
end

function UI.list(padding: number, horizontal: boolean?, halign: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, padding),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.gradient(colors: { Color3 }?, transparency: { number }?, rotation: number?): UIGradient
	local g = UI.new("UIGradient", { Rotation = rotation or 0 })
	if colors then
		local kps = {}
		for i, c in colors do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
		end
		g.Color = ColorSequence.new(kps)
	end
	if transparency then
		local kps = {}
		for i, tr in transparency do
			table.insert(kps, NumberSequenceKeypoint.new((i - 1) / math.max(#transparency - 1, 1), tr))
		end
		g.Transparency = NumberSequence.new(kps)
	end
	return g
end

-- "PLAY" -> "P L A Y" (cheap letter spacing)
function UI.spaced(text: string, gap: string?): string
	local out = {}
	for _, cp in utf8.codes(text) do
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out, gap or " ")
end

function UI.full(parent: Instance, name: string, z: number?): Frame
	return UI.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or 1,
		Parent = parent,
	})
end

-- A canvas that is always 1080 "design pixels" tall (bigger on phones),
-- so offsets look the same on every screen.
function UI.canvas(parent: Instance): (Frame, UIScale)
	local canvas = UI.new("Frame", { Name = "Canvas", BackgroundTransparency = 1, Parent = parent })
	local scale = UI.new("UIScale", { Parent = canvas })
	local camera = workspace.CurrentCamera
	local function update()
		local vp = camera.ViewportSize
		local design = UI.DESIGN_HEIGHT
		if vp.Y < 600 then
			design = 820
		end
		local s = math.max(vp.Y / design, 0.2)
		-- very narrow screens: make sure ~1000 design px fit horizontally
		if vp.X / s < 1000 then
			s = vp.X / 1000
		end
		scale.Scale = s
		canvas.Size = UDim2.fromOffset(vp.X / s, vp.Y / s)
	end
	update()
	local conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	canvas.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return canvas, scale
end

function UI.label(props: { [string]: any }, children: { Instance }?): TextLabel
	local base = {
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
	}
	for k, val in props do
		base[k] = val
	end
	return UI.new("TextLabel", base, children)
end

return UI
