--!strict
-- UIKit: themed, pure GUI builders. Every builder takes (theme, props) and returns either an Instance or a
-- handle table { Root, ..., Destroy }. Nothing is parented unless props.Parent is given (set LAST).
-- Lune-safe: no services at require time; events/animations go through Motion (no-ops offline);
-- Strings (for the language-aware font choice and a few generic labels) is required lazily.
--
-- Common props (all optional) on every builder: Name, Size, Position, AnchorPoint, LayoutOrder, ZIndex,
-- Visible, Parent. Sizes/offsets are in design px of the UIRoot scaled canvas (see UIRoot.ComputeScale).
--
-- Text & layout helpers
--   UIKit.Font(theme, role) -> Font                  language-aware (Themes.Font + Strings.Language())
--   UIKit.Upper(text) -> string                      UTF-8 uppercase incl. Cyrillic
--   UIKit.Label(theme, props) -> TextLabel           props: Text, Role("Body"|"Title"|"Heading"|"Subtitle"|"Caption"|
--                                                    "Small"|"Number"|"Mono"|"Display"|"Button"), TextSize, Color, Tone
--                                                    ("Text"|"Dim"|"Muted"|"Accent"|"Accent2"|"Danger"|"Success"|"Gold"|...),
--                                                    XAlign, YAlign, Wrap, AutoSize("X"|"Y"|"XY"), RichText, Upper,
--                                                    Dialogue (prefix "* " in Classic), Stroke{Color,Thickness,Transparency},
--                                                    Scaled (TextScaled + MaxTextSize), Truncate, LineHeight, Transparency
--   UIKit.Title(theme, props) -> { Root, Label, Set(text), Destroy }      big layered title (glow/gradient/stroke/slant)
--   UIKit.Divider(theme, props) -> Frame             props: Vertical, Thickness, Ornament(true), Color
--   UIKit.Backdrop(theme, props) -> Frame            full-screen themed background (gradient + decor)
--   UIKit.ListLayout(parent, props) / UIKit.Padding(parent, l, t, r, b)
--   UIKit.LinkSelection({GuiObject}, "Vertical"|"Horizontal", wrap?)    gamepad NextSelection chain
-- Containers
--   UIKit.Panel(theme, props) -> { Root, Body, Content, Header?, SetTitle(text), Destroy }
--       props: Variant("Default"|"Alt"|"Inset"|"Glass"|"Accent"|"Dialogue"), Title, TitleIcon, Padding,
--       Shadow, Ornaments, Layout("Vertical"|"Horizontal"), Gap, Align, AutoSize("Y"), Clip
--   UIKit.List(theme, props) -> { Root: ScrollingFrame, Content, Add(inst), Clear(), Destroy }
--       props: Gap, Inset, Horizontal, ScrollBar(true)
--   UIKit.Grid(theme, props) -> { Root, Content, Add, Clear, Destroy }   props: CellSize, CellPadding, Scroll, Inset
--   UIKit.Modal(theme, props) -> { Root, Panel, Content, Close(), Destroy }
--       props: Title, PanelSize, OnClose, Buttons {{Text, Variant, Icon, OnActivated}}, Dim(0.35)
--   UIKit.Tooltip(theme, props) -> Frame             props: Title, Text, Tags, Stats {{Label, Value}}, Width
--   UIKit.Toast(theme, props) -> { Root, Destroy }   props: Text, Kind("Info"|"Success"|"Warning"|"Danger"|"Reward"), Icon, Width
-- Controls
--   UIKit.Button(theme, props) -> { Root: TextButton, Label, SetText, SetState, SetSelected, SetDisabled, Destroy }
--       props: Text, Icon, Variant("Primary"|"Secondary"|"Ghost"|"Danger"|"Icon"), Width, Height, Disabled,
--       Selected, State("Normal"|"Hover"|"Pressed"|"Disabled"|"Selected" - preview override), OnActivated,
--       Hint (key name -> KeyHint at the right), Align("Left"|"Center")
--   UIKit.Toggle(theme, props) -> { Root, Set(bool), Get(), Destroy }       props: Label, Value, OnChanged, State
--   UIKit.Slider(theme, props) -> { Root, Set(v), Get(), Destroy }          props: Label, Value, Min, Max, Step,
--       Format(fn), OnChanged, State
--   UIKit.Cycle(theme, props) -> { Root, Set(i), Get(), Value(), Destroy }  props: Label, Options{{Id,Text}}|{string},
--       Index, OnChanged, Dots(true), State
--   UIKit.Dropdown(theme, props) -> { Root, Set(i), Get(), Open(), Close(), Destroy }  props as Cycle + Open
--   UIKit.Tabs(theme, props) -> { Root, Select(id), Selected(), Destroy }   props: Items{{Id,Text,Icon}}, Selected, OnChanged
-- Display
--   UIKit.Icon(name, color, size?, accent?) -> Frame (Icons.Create)
--   UIKit.Heart(color, size?, shine?) -> Frame      pixel-art SOUL heart (11x10 grid)
--   UIKit.Cursor(theme, size?) -> Frame             theme focus cursor (Heart|Diamond|Chevron|Fang)
--   UIKit.Bar(theme, props) -> { Root, Set(value, max?, secondary?), SetColor(c), Destroy }
--       props: Value, Max, Secondary (KR), Kind("HP"|"Guard"|"Ult"|"Exp"|"Dodge"|"Monster"|"Custom"), Color,
--       BackColor, SecondaryColor, Label, ShowValue, Format(fn(v,max)->string), Segments (pips), Ghost,
--       Hud (HudStyle: render with HUD tokens), Height
--   UIKit.Card(theme, props) -> { Root, Portrait, SetSelected, SetLocked, Destroy }
--       props: Name, Title, Tags, Color, Icon, Role, Difficulty, Locked, Selected, Price, Rarity, OnActivated, State
--   UIKit.Badge(theme, props) -> Frame               props: Text, Color, Icon, Style("Solid"|"Outline"|"Soft")
--   UIKit.KeyHint(theme, props) -> Frame             props: Key, Label, Device("Keyboard"|"Gamepad"|"Mouse"|"Touch"), Height
--   UIKit.StatRow(theme, props) -> Frame             props: Label, Value, Icon, Color, Fill (0..1 mini bar)
--   UIKit.Countdown(theme, props) -> { Root, Set(seconds), Destroy }   props: Seconds, Format("Clock"|"Seconds"), Urgent(10), Label
--   UIKit.Viewport(theme, props) -> { Root, Viewport, Camera, SetModel(model?), Destroy }
--       props: Model, CameraCFrame, FieldOfView, Color (backdrop tint), LightDirection, Ambient

local Themes = require(script.Parent.Themes)
local Icons = require(script.Parent.Icons)
local Motion = require(script.Parent.Motion)

type Theme = Themes.Theme
type HudStyle = Themes.HudStyle
type Props = { [string]: any }

export type PanelHandle = { Root: Frame, Body: Frame, Content: Frame, Header: Frame?, SetTitle: (string) -> (), Destroy: () -> () }
export type ButtonHandle = {
	Root: TextButton,
	Label: TextLabel,
	SetText: (string) -> (),
	SetState: (string) -> (),
	SetSelected: (boolean) -> (),
	SetDisabled: (boolean) -> (),
	Destroy: () -> (),
}
export type BarHandle = { Root: Frame, Set: (number, number?, number?) -> (), SetColor: (Color3) -> (), Destroy: () -> () }

local UIKit = {}

-- lazy Strings ------------------------------------------------------------------------------------
local StringsModule: any = nil
local function Strings(): any
	if StringsModule == nil then
		local ok, result = pcall(function()
			local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
			return require((shared :: any):WaitForChild("Strings")) :: any
		end)
		StringsModule = if ok then result else false
	end
	return if StringsModule then StringsModule else nil
end

local function L(key: string, ...: any): string
	local s = Strings()
	return if s then s.L(key, ...) else key
end

local function language(): string
	local s = Strings()
	return if s then s.Language() else "en"
end

-- generic helpers ---------------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function make(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function frame(props: Props?): Frame
	local f = make("Frame", props)
	f.BorderSizePixel = 0
	if props == nil or props.BackgroundTransparency == nil then
		f.BackgroundTransparency = 1
	end
	return f
end

local function corner(parent: Instance, radius: UDim?)
	if radius and (radius.Scale > 0 or radius.Offset > 0) then
		make("UICorner", { CornerRadius = radius, Parent = parent })
	end
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?, join: Enum.LineJoinMode?): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = join or Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function textStroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function gradient(parent: Instance, color: ColorSequence?, transparency: NumberSequence?, rotation: number?): UIGradient
	local g = make("UIGradient", { Rotation = rotation or 0 })
	if color then
		g.Color = color
	end
	if transparency then
		g.Transparency = transparency
	end
	g.Parent = parent
	return g
end

local function seq2(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
end

local function nseq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function applyBase(inst: GuiObject, props: Props)
	if props.Name then
		inst.Name = props.Name
	end
	if props.Size then
		inst.Size = props.Size
	end
	if props.Position then
		inst.Position = props.Position
	end
	if props.AnchorPoint then
		inst.AnchorPoint = props.AnchorPoint
	end
	if props.LayoutOrder then
		inst.LayoutOrder = props.LayoutOrder
	end
	if props.ZIndex then
		inst.ZIndex = props.ZIndex
	end
	if props.Visible ~= nil then
		inst.Visible = props.Visible
	end
end

local function finish<T>(inst: T, props: Props): T
	if props.Parent then
		(inst :: any).Parent = props.Parent
	end
	return inst
end

function UIKit.Padding(parent: Instance, left: number, top: number?, right: number?, bottom: number?): UIPadding
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingTop = UDim.new(0, top or left),
		PaddingRight = UDim.new(0, right or left),
		PaddingBottom = UDim.new(0, bottom or top or left),
		Parent = parent,
	})
end

function UIKit.ListLayout(parent: Instance, props: Props?): UIListLayout
	local p = props or {}
	return make("UIListLayout", {
		FillDirection = if p.Horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, p.Gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = p.HAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = p.VAlign or Enum.VerticalAlignment.Top,
		Wraps = p.Wraps or false,
		Parent = parent,
	})
end

function UIKit.LinkSelection(items: { GuiObject }, direction: string?, wrap: boolean?)
	local horizontal = direction == "Horizontal"
	for i, item in items do
		local nextItem = items[i + 1] or (if wrap then items[1] else nil)
		local prevItem = items[i - 1] or (if wrap then items[#items] else nil)
		-- (nil is the default; Ref properties are only assigned when set, which also keeps Lune happy)
		if horizontal then
			if nextItem then
				item.NextSelectionRight = nextItem
			end
			if prevItem then
				item.NextSelectionLeft = prevItem
			end
		else
			if nextItem then
				item.NextSelectionDown = nextItem
			end
			if prevItem then
				item.NextSelectionUp = prevItem
			end
		end
	end
end

-- text --------------------------------------------------------------------------------------------
local CYR_UPPER: { [number]: number } = {}
for cp = 0x0430, 0x044F do
	CYR_UPPER[cp] = cp - 0x20
end
for cp = 0x0450, 0x045F do
	CYR_UPPER[cp] = cp - 0x50
end

function UIKit.Upper(text: string): string
	local out = table.create(#text)
	for _, cp in utf8.codes(text) do
		if cp >= 97 and cp <= 122 then
			table.insert(out, string.char(cp - 32))
		else
			table.insert(out, utf8.char(CYR_UPPER[cp] or cp))
		end
	end
	return table.concat(out)
end

function UIKit.Font(theme: Theme, role: string): Font
	return Themes.Font(theme, role :: any, language())
end

local ROLE_FONT: { [string]: string } = {
	Body = "Body",
	Small = "Body",
	Title = "Title",
	Heading = "Heading",
	Subtitle = "Subtitle",
	Caption = "Caption",
	Number = "Number",
	Mono = "Mono",
	Display = "Display",
	Button = "Button",
}

local ROLE_SIZE: { [string]: string } = {
	Body = "Body",
	Small = "Small",
	Title = "Title",
	Heading = "Heading",
	Subtitle = "Subtitle",
	Caption = "Caption",
	Number = "Number",
	Mono = "Body",
	Display = "Hero",
	Button = "Button",
}

local function toneColor(theme: Theme, tone: any): Color3
	if typeof(tone) == "Color3" then
		return tone
	end
	local c = theme.Colors
	if tone == "Dim" then
		return c.TextDim
	elseif tone == "Muted" then
		return c.TextMuted
	elseif tone == "Inverse" then
		return c.TextInverse
	elseif type(tone) == "string" and (c :: any)[tone] then
		return (c :: any)[tone]
	end
	return c.Text
end

function UIKit.Label(theme: Theme, props: Props): TextLabel
	local role: string = props.Role or "Body"
	local size: number = props.TextSize or (theme.TextSize :: any)[ROLE_SIZE[role] or "Body"] or theme.TextSize.Body
	local text: string = props.Text or ""
	if props.Dialogue and theme.DialoguePrefix ~= "" then
		text = theme.DialoguePrefix .. text
	end
	if props.Upper then
		text = UIKit.Upper(text)
	end
	local label: TextLabel = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = text,
		FontFace = UIKit.Font(theme, ROLE_FONT[role] or "Body"),
		TextSize = size,
		TextColor3 = toneColor(theme, props.Color or props.Tone),
		TextTransparency = props.Transparency or 0,
		TextXAlignment = Enum.TextXAlignment[props.XAlign or "Left"],
		TextYAlignment = Enum.TextYAlignment[props.YAlign or "Center"],
		TextWrapped = props.Wrap == true,
		RichText = props.RichText == true,
		LineHeight = props.LineHeight or (if props.Wrap then theme.LineHeight else 1),
		Size = UDim2.new(1, 0, 0, math.ceil(size * 1.25)),
	})
	if props.Truncate then
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if props.AutoSize then
		label.AutomaticSize = Enum.AutomaticSize[props.AutoSize]
		if props.AutoSize == "X" or props.AutoSize == "XY" then
			label.Size = UDim2.new(0, 0, 0, math.ceil(size * 1.25))
		end
		if props.AutoSize == "Y" and props.Size == nil then
			label.Size = UDim2.new(1, 0, 0, 0)
		end
	end
	if props.Scaled then
		label.TextScaled = true
		make("UITextSizeConstraint", { MaxTextSize = math.floor(props.MaxTextSize or size), MinTextSize = math.floor(props.MinTextSize or 6), Parent = label })
	end
	if props.Stroke then
		textStroke(label, props.Stroke.Color or BLACK, props.Stroke.Thickness or 1, props.Stroke.Transparency)
	end
	applyBase(label, props)
	return finish(label, props)
end

-- small shapes ------------------------------------------------------------------------------------
function UIKit.Icon(name: string, color: Color3, size: (number | UDim2)?, accent: Color3?): Frame
	return Icons.Create(name, color, size, accent)
end

local HEART_ROWS = {
	{ { 2, 4 }, { 6, 8 } },
	{ { 1, 9 } },
	{ { 0, 10 } },
	{ { 0, 10 } },
	{ { 0, 10 } },
	{ { 1, 9 } },
	{ { 2, 8 } },
	{ { 3, 7 } },
	{ { 4, 6 } },
	{ { 5, 5 } },
}

function UIKit.Heart(color: Color3?, size: (number | UDim2)?, shine: boolean?): Frame
	local root = frame({ Name = "Heart", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	if typeof(size) == "number" then
		root.Size = UDim2.fromOffset(size :: number, math.round((size :: number) * 10 / 11))
	elseif typeof(size) == "UDim2" then
		root.Size = size :: UDim2
	else
		root.Size = UDim2.fromScale(1, 1)
	end
	make("UIAspectRatioConstraint", { AspectRatio = 11 / 10, Parent = root })
	local c = color or Color3.fromRGB(255, 0, 0)
	for row, runs in HEART_ROWS do
		for _, run in runs do
			frame({
				Name = "Px",
				BackgroundTransparency = 0,
				BackgroundColor3 = c,
				Position = UDim2.fromScale(run[1] / 11, (row - 1) / 10),
				Size = UDim2.fromScale((run[2] - run[1] + 1) / 11, 1 / 10 + 0.012),
				Parent = root,
			})
		end
	end
	if shine then
		frame({
			Name = "Shine",
			BackgroundTransparency = 0.15,
			BackgroundColor3 = WHITE,
			Position = UDim2.fromScale(2 / 11, 2 / 10),
			Size = UDim2.fromScale(1 / 11, 1 / 10),
			ZIndex = 2,
			Parent = root,
		})
	end
	return root
end

-- right triangle inside a px box; k = corner holding the right angle ("TL"|"TR"|"BL"|"BR")
local function wedge(color: Color3, w: number, h: number, k: string, transparency: number?): Frame
	local clip = frame({ Name = "Wedge", Size = UDim2.fromOffset(w, h), ClipsDescendants = true })
	local len = math.sqrt(w * w + h * h)
	local thick = 2 * w * h / len
	local nx, ny, angle
	if k == "BL" then
		nx, ny, angle = -h / len, w / len, math.deg(math.atan2(h, w))
	elseif k == "TR" then
		nx, ny, angle = h / len, -w / len, math.deg(math.atan2(h, w))
	elseif k == "TL" then
		nx, ny, angle = -h / len, -w / len, math.deg(math.atan2(-h, w))
	else
		nx, ny, angle = h / len, w / len, math.deg(math.atan2(-h, w))
	end
	frame({
		Name = "F",
		BackgroundTransparency = transparency or 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(w / 2 + nx * thick / 2, h / 2 + ny * thick / 2),
		Size = UDim2.fromOffset(len * 1.6, thick),
		Rotation = angle,
		Parent = clip,
	})
	return clip
end

-- slanted parallelogram fill inside a clip container of height h (px); returns (clip, fill)
local function blade(h: number, slant: number, color: Color3, transparency: number?): (Frame, Frame)
	local clip = frame({ Name = "Blade", Size = UDim2.fromScale(1, 1), ClipsDescendants = true })
	local rad = math.rad(slant)
	local fill = frame({
		Name = "Fill",
		BackgroundTransparency = transparency or 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(math.cos(rad), -h * math.sin(rad), 3, 0),
		Rotation = slant,
		Parent = clip,
	})
	return clip, fill
end

local function diamond(color: Color3, size: number, transparency: number?): Frame
	return frame({
		Name = "Diamond",
		BackgroundTransparency = transparency or 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
	})
end

function UIKit.Cursor(theme: Theme, size: number?): Frame
	local s = size or theme.Cursor.Size
	local style = theme.Cursor.Style
	local color = theme.Cursor.Color
	if style == "Heart" then
		local h = UIKit.Heart(color, s)
		h.Name = "Cursor"
		return h
	end
	local root = frame({ Name = "Cursor", Size = UDim2.fromOffset(s, s), AnchorPoint = Vector2.new(0.5, 0.5) })
	if style == "Diamond" then
		local outer = diamond(color, s * 0.72)
		outer.Position = UDim2.fromScale(0.5, 0.5)
		gradient(outer, theme.Gradients.Stroke, nil, 45)
		outer.Parent = root
		local inner = diamond(theme.Colors.PanelInset, s * 0.3)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.ZIndex = 2
		inner.Parent = root
	elseif style == "Chevron" then
		local icon = Icons.Create("ChevronRight", color, UDim2.fromScale(1, 1))
		icon.Parent = root
		local glow = frame({
			Name = "Glow",
			BackgroundTransparency = 0.8,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.5, 1.5),
			ZIndex = 0,
			Parent = root,
		})
		corner(glow, UDim.new(0.5, 0))
	else -- Fang
		local icon = Icons.Create("Fang", color, UDim2.fromScale(1, 1))
		icon.Parent = root
	end
	return root
end

-- dividers & backdrop -------------------------------------------------------------------------------
function UIKit.Divider(theme: Theme, props: Props): Frame
	local vertical = props.Vertical == true
	local thickness: number = props.Thickness or (if theme.Id == "Classic" then 2 else 1)
	local color: Color3 = props.Color or (if theme.Id == "Classic" then theme.Colors.StrokeDim else theme.Colors.Stroke)
	local root = frame({
		Name = "Divider",
		Size = if vertical then UDim2.new(0, 12, 1, 0) else UDim2.new(1, 0, 0, 12),
	})
	local line = frame({
		Name = "Line",
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if vertical then UDim2.new(0, thickness, 1, 0) else UDim2.new(1, 0, 0, thickness),
		Parent = root,
	})
	if theme.Id ~= "Classic" then
		gradient(line, nil, nseq({ { 0, 1 }, { 0.25, 0.2 }, { 0.5, 0 }, { 0.75, 0.2 }, { 1, 1 } }), if vertical then 90 else 0)
	end
	if props.Ornament ~= false then
		if theme.Id == "Royal" then
			local d = diamond(theme.Colors.Stroke, 8)
			d.Position = UDim2.fromScale(0.5, 0.5)
			d.ZIndex = 2
			d.Parent = root
		elseif theme.Id == "Void" then
			local node = frame({
				Name = "Node",
				BackgroundTransparency = 0,
				BackgroundColor3 = theme.Colors.Accent,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(5, 5),
				ZIndex = 2,
				Parent = root,
			})
			corner(node, UDim.new(0.5, 0))
		elseif theme.Id == "Fell" then
			frame({
				Name = "Slash",
				BackgroundTransparency = 0,
				BackgroundColor3 = theme.Colors.Accent2,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(3, 14),
				Rotation = if vertical then 70 else 24,
				ZIndex = 2,
				Parent = root,
			})
		end
	end
	applyBase(root, props)
	return finish(root, props)
end

function UIKit.Backdrop(theme: Theme, props: Props?): Frame
	local p = props or {}
	local c = theme.Colors
	local root = frame({
		Name = "Backdrop",
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	})
	gradient(root, theme.Gradients.Backdrop, nil, 90)
	if theme.Id == "Classic" then
		-- faint pixel starfield
		local stars = { { 0.08, 0.12 }, { 0.22, 0.31 }, { 0.37, 0.08 }, { 0.55, 0.2 }, { 0.71, 0.09 }, { 0.86, 0.27 }, { 0.93, 0.62 }, { 0.12, 0.74 }, { 0.3, 0.9 }, { 0.64, 0.84 }, { 0.8, 0.95 }, { 0.47, 0.6 } }
		for i, s in stars do
			frame({
				Name = "Star",
				BackgroundTransparency = if i % 3 == 0 then 0.35 else 0.7,
				BackgroundColor3 = WHITE,
				Position = UDim2.fromScale(s[1], s[2]),
				Size = UDim2.fromOffset(3, 3),
				Parent = root,
			})
		end
	elseif theme.Id == "Royal" then
		-- slanted window light beams + floor glow
		for i, x in { 0.12, 0.34, 0.58, 0.8 } do
			local beam = frame({
				Name = "Beam",
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(255, 214, 140),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, 0.45),
				Size = UDim2.new(0, 120 + i * 10, 1.6, 0),
				Rotation = 24,
				Parent = root,
			})
			gradient(beam, nil, nseq({ { 0, 1 }, { 0.3, 0.93 }, { 0.6, 0.955 }, { 1, 1 } }), 90)
		end
		local floor = frame({
			Name = "Glow",
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(255, 200, 120),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1, 0.4),
			Parent = root,
		})
		gradient(floor, nil, nseq({ { 0, 1 }, { 1, 0.86 } }), 90)
	elseif theme.Id == "Void" then
		-- grid + glow orbs + star dust
		for i = 1, 11 do
			frame({
				Name = "GridV",
				BackgroundTransparency = 0.94,
				BackgroundColor3 = c.Accent,
				Position = UDim2.fromScale(i / 12, 0),
				Size = UDim2.new(0, 1, 1, 0),
				Parent = root,
			})
		end
		for i = 1, 6 do
			frame({
				Name = "GridH",
				BackgroundTransparency = 0.94,
				BackgroundColor3 = c.Accent,
				Position = UDim2.fromScale(0, i / 7),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = root,
			})
		end
		for _, orb in { { 0.18, 0.2, 520, c.Accent2 }, { 0.85, 0.78, 640, c.Accent }, { 0.6, 0.1, 380, c.Accent3 } } do
			for k = 1, 3 do
				local o = frame({
					Name = "Orb",
					BackgroundTransparency = 0.94 + k * 0.015,
					BackgroundColor3 = orb[4],
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(orb[1], orb[2]),
					Size = UDim2.fromOffset(orb[3] * (0.45 + k * 0.28), orb[3] * (0.45 + k * 0.28)),
					Parent = root,
				})
				corner(o, UDim.new(0.5, 0))
			end
		end
	elseif theme.Id == "Fell" then
		-- vignette + claw slashes
		local vignette = frame({
			Name = "Vignette",
			BackgroundTransparency = 0,
			BackgroundColor3 = c.Backdrop2,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		gradient(vignette, nil, nseq({ { 0, 0.35 }, { 0.3, 1 }, { 0.7, 1 }, { 1, 0.35 } }), 0)
		for i = 0, 2 do
			frame({
				Name = "Slash",
				BackgroundTransparency = 0.86,
				BackgroundColor3 = c.Accent,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.86 + i * 0.03, 0.2 + i * 0.04),
				Size = UDim2.new(0, 10 - i * 2, 0.55, 0),
				Rotation = 28,
				Parent = root,
			})
		end
	end
	applyBase(root, p)
	return finish(root, p)
end

-- panels ------------------------------------------------------------------------------------------
local HEADER_HEIGHT: { [string]: number } = { Classic = 34, Royal = 52, Void = 40, Fell = 46 }

local function panelColors(theme: Theme, variant: string): (Color3, Color3, number, number)
	local c = theme.Colors
	if variant == "Alt" then
		return c.PanelAlt, c.StrokeAlt, theme.StrokeThickness, theme.PanelTransparency
	elseif variant == "Inset" then
		return c.PanelInset, c.StrokeDim, theme.StrokeThin, math.min(theme.PanelTransparency + 0.1, 1)
	elseif variant == "Glass" then
		return c.Panel, c.Stroke, theme.StrokeThin, math.max(theme.PanelTransparency, 0.35)
	elseif variant == "Accent" then
		return c.Panel:Lerp(c.Accent, 0.16), c.Accent, theme.StrokeThickness, theme.PanelTransparency
	end
	return c.Panel, c.Stroke, theme.StrokeThickness, theme.PanelTransparency
end

local function addShadow(theme: Theme, root: Frame, cornerRadius: UDim)
	local sh = theme.Shadow
	if not sh.Enabled then
		return
	end
	if sh.Hard then
		local s = frame({
			Name = "Shadow",
			BackgroundTransparency = sh.Transparency,
			BackgroundColor3 = sh.Color,
			Position = UDim2.fromOffset(sh.Offset.X, sh.Offset.Y),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
			Parent = root,
		})
		corner(s, cornerRadius)
		return
	end
	for k = 1, sh.Layers do
		local spread = sh.Spread * k / sh.Layers
		local s = frame({
			Name = "Shadow",
			BackgroundTransparency = 1 - (1 - sh.Transparency) / (sh.Layers + 1) * (sh.Layers + 1 - k) * 0.55,
			BackgroundColor3 = sh.Color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, sh.Offset.Y * k / sh.Layers),
			Size = UDim2.new(1, spread * 2, 1, spread * 2),
			ZIndex = 0,
			Parent = root,
		})
		corner(s, UDim.new(cornerRadius.Scale, cornerRadius.Offset + spread))
	end
end

local function addGlow(theme: Theme, root: Frame, cornerRadius: UDim, color: Color3?, strength: number?)
	if not theme.Glow.Enabled then
		return
	end
	local size = theme.Glow.Size
	for k = 1, 2 do
		local g = frame({
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, size * k, 1, size * k),
			ZIndex = 0,
			Parent = root,
		})
		corner(g, UDim.new(cornerRadius.Scale, cornerRadius.Offset + size * k / 2))
		stroke(g, color or theme.Glow.Color, size * k / 2, math.min(1, theme.Glow.Transparency + (k - 1) * 0.06 - (strength or 0)), theme.LineJoin)
	end
end

local function royalCorners(theme: Theme, parent: Frame)
	for _, pos in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local d = diamond(theme.Colors.Stroke, 11)
		d.Position = UDim2.fromScale(pos[1], pos[2])
		d.ZIndex = 4
		gradient(d, theme.Gradients.Stroke, nil, 0)
		d.Parent = parent
		local dot = diamond(theme.Colors.PanelInset, 4)
		dot.Position = UDim2.fromScale(pos[1], pos[2])
		dot.ZIndex = 5
		dot.Parent = parent
	end
end

local function voidBrackets(theme: Theme, parent: Frame)
	local c = theme.Colors.Accent
	local arm, t, off = 22, 2, -5
	local specs = {
		{ UDim2.new(0, off, 0, off), UDim2.fromOffset(arm, t) },
		{ UDim2.new(0, off, 0, off), UDim2.fromOffset(t, arm) },
		{ UDim2.new(1, -arm - off, 1, -t - off), UDim2.fromOffset(arm, t) },
		{ UDim2.new(1, -t - off, 1, -arm - off), UDim2.fromOffset(t, arm) },
	}
	for _, s in specs do
		frame({
			Name = "Bracket",
			BackgroundTransparency = 0,
			BackgroundColor3 = c,
			Position = s[1],
			Size = s[2],
			ZIndex = 4,
			Parent = parent,
		})
	end
end

local function fellAccents(theme: Theme, parent: Frame)
	local c = theme.Colors
	-- crimson blade tab along the top-left border with a slanted end
	frame({
		Name = "Tab",
		BackgroundTransparency = 0,
		BackgroundColor3 = c.Accent,
		Position = UDim2.fromOffset(-2, -2),
		Size = UDim2.new(0.3, 0, 0, 6),
		ZIndex = 4,
		Parent = parent,
	})
	local w = wedge(c.Accent, 10, 6, "TL")
	w.Position = UDim2.new(0.3, -2, 0, -2)
	w.ZIndex = 4
	w.Parent = parent
	-- gold tooth hanging from the top border
	local tooth = Icons.Create("Fang", c.Accent2, UDim2.fromOffset(12, 14))
	tooth.AnchorPoint = Vector2.new(0.5, 0)
	tooth.Position = UDim2.new(1, -34, 0, 0)
	tooth.ZIndex = 4
	tooth.Parent = parent
	-- claw scratches bottom-right
	for i = 0, 2 do
		frame({
			Name = "Scratch",
			BackgroundTransparency = 0.55,
			BackgroundColor3 = c.Accent,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -22 + i * 6, 1, -16),
			Size = UDim2.fromOffset(2, 16),
			Rotation = 30,
			ZIndex = 4,
			Parent = parent,
		})
	end
end

local function buildHeader(theme: Theme, root: Frame, title: string, icon: string?): (Frame, TextLabel)
	local c = theme.Colors
	local id = theme.Id
	local hh = HEADER_HEIGHT[id] or 40
	local header = frame({ Name = "Header", Size = UDim2.new(1, 0, 0, hh), ZIndex = 6 })
	local label: TextLabel
	if id == "Classic" then
		-- legend sitting on the top border
		local text = UIKit.Upper(title)
		label = UIKit.Label(theme, { Text = text, Role = "Heading", AutoSize = "X", Color = c.Text })
		label.BackgroundTransparency = 0
		label.BackgroundColor3 = c.Panel
		label.Position = UDim2.fromOffset(18, -math.floor(theme.TextSize.Heading / 2) - 4)
		label.Size = UDim2.new(0, 0, 0, theme.TextSize.Heading + 8)
		UIKit.Padding(label, 8, 0, 8, 0)
		label.ZIndex = 3
		label.Parent = header
		if icon then
			local ic = Icons.Create(icon, c.Accent, 18)
			ic.AnchorPoint = Vector2.new(1, 0.5)
			ic.Position = UDim2.new(1, -16, 0, 2)
			ic.Parent = header
		end
	elseif id == "Royal" then
		label = UIKit.Label(theme, {
			Text = UIKit.Upper(title),
			Role = "Heading",
			XAlign = "Center",
			AutoSize = "X",
			Color = WHITE,
			Position = UDim2.new(0.5, 0, 0, 14),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 3,
		})
		gradient(label, theme.Gradients.Title, nil, 90)
		textStroke(label, Color3.fromRGB(46, 30, 8), 1.2, 0.2)
		label.Parent = header
		-- flourish lines with diamonds
		for side = -1, 1, 2 do
			local line = frame({
				Name = "Flourish",
				BackgroundTransparency = 0,
				BackgroundColor3 = c.Stroke,
				AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
				Position = UDim2.new(0.5, side * 0, 0, 14 + theme.TextSize.Heading / 2 + 3),
				Size = UDim2.new(0.32, 0, 0, 1),
				ZIndex = 2,
				Parent = header,
			})
			gradient(line, nil, nseq({ { 0, if side < 0 then 1 else 0.85 }, { 0.5, 0.15 }, { 1, if side < 0 then 0.85 else 1 } }), 0)
		end
		-- stained-glass band under the title
		local band = frame({
			Name = "Stained",
			Position = UDim2.new(0, 22, 0, hh - 8),
			Size = UDim2.new(1, -44, 0, 4),
			ZIndex = 2,
			Parent = header,
		})
		local colors = theme.Gradients.Stained or { c.Accent }
		local n = #colors * 2
		for i = 0, n - 1 do
			frame({
				Name = "Glass",
				BackgroundTransparency = 0.25,
				BackgroundColor3 = colors[(i % #colors) + 1],
				Position = UDim2.new(i / n, 1, 0, 0),
				Size = UDim2.new(1 / n, -2, 1, 0),
				Parent = band,
			})
		end
		gradient(band, nil, nseq({ { 0, 1 }, { 0.15, 0 }, { 0.85, 0 }, { 1, 1 } }), 0)
	elseif id == "Void" then
		local bullet = frame({
			Name = "Bullet",
			BackgroundTransparency = 0,
			BackgroundColor3 = c.Accent,
			Position = UDim2.fromOffset(18, 16),
			Size = UDim2.fromOffset(7, 7),
			Rotation = 45,
			ZIndex = 3,
			Parent = header,
		})
		gradient(bullet, theme.Gradients.Accent, nil, 0)
		label = UIKit.Label(theme, {
			Text = UIKit.Upper(title),
			Role = "Heading",
			AutoSize = "X",
			Color = c.Accent,
			Position = UDim2.fromOffset(34, 9),
			Size = UDim2.new(0, 0, 0, 22),
			ZIndex = 3,
		})
		label.Parent = header
		local line = frame({
			Name = "Rule",
			BackgroundTransparency = 0,
			BackgroundColor3 = c.Accent,
			Position = UDim2.new(0, 18, 0, hh - 6),
			Size = UDim2.new(1, -36, 0, 1),
			ZIndex = 2,
			Parent = header,
		})
		gradient(line, nil, nseq({ { 0, 0.1 }, { 0.6, 0.75 }, { 1, 1 } }), 0)
		local code = UIKit.Label(theme, {
			Text = "//" .. string.format("%02d", (#title * 7) % 97),
			Role = "Mono",
			TextSize = theme.TextSize.Caption,
			Color = c.TextMuted,
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 12),
			Size = UDim2.fromOffset(60, 16),
			ZIndex = 3,
		})
		code.Parent = header
	else -- Fell
		local plate = frame({
			Name = "Plate",
			Position = UDim2.fromOffset(-10, 8),
			Size = UDim2.new(0, 0, 0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 3,
			Parent = header,
		})
		local clip, fill = blade(34, theme.Slant, c.Accent)
		clip.ZIndex = 1
		gradient(fill, theme.Gradients.Accent, nil, 90 - theme.Slant)
		clip.Parent = plate
		label = UIKit.Label(theme, {
			Text = UIKit.Upper(title),
			Role = "Heading",
			AutoSize = "X",
			Color = c.TextInverse,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 2,
		})
		UIKit.Padding(label, 22, 0, 26, 0)
		label.Parent = plate
		local tooth = Icons.Create("Fang", c.Accent2, UDim2.fromOffset(10, 12))
		tooth.AnchorPoint = Vector2.new(0, 0)
		tooth.Position = UDim2.new(1, -24, 1, -2)
		tooth.ZIndex = 4
		tooth.Parent = plate
	end
	header.Parent = root
	return header, label
end

function UIKit.Panel(theme: Theme, props: Props): PanelHandle
	local variant: string = props.Variant or "Default"
	local fill, strokeColor, thickness, transparency = panelColors(theme, variant)
	local radius = if variant == "Inset" and theme.CornerRadius.Offset > 0
		then UDim.new(0, math.max(theme.CornerRadius.Offset - 4, 2))
		else theme.CornerRadius
	local root = frame({ Name = props.Name or "Panel", Size = UDim2.fromOffset(320, 200) })
	local decorated = variant ~= "Inset"
	if props.Shadow ~= false and decorated then
		addShadow(theme, root, radius)
	end
	if decorated and props.Glow ~= false then
		addGlow(theme, root, radius)
	end
	local body = frame({
		Name = "Body",
		BackgroundTransparency = transparency,
		BackgroundColor3 = fill,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		ClipsDescendants = props.Clip == true,
		Parent = root,
	})
	corner(body, radius)
	if theme.Gradients.PanelFill or theme.Gradients.PanelTransparency then
		gradient(body, theme.Gradients.PanelFill, theme.Gradients.PanelTransparency, 90)
	end
	if thickness > 0 then
		local s = stroke(body, strokeColor, thickness, if variant == "Inset" and theme.Id == "Void" then 0.5 else 0, theme.LineJoin)
		if theme.Gradients.Stroke and variant ~= "Inset" then
			local g = gradient(s, theme.Gradients.Stroke, theme.Gradients.StrokeTransparency, theme.Gradients.StrokeRotation)
			if theme.Id == "Void" then
				Motion.Sweep(g, 3.2)
			end
		end
	end
	-- theme decorations inside the body
	if decorated then
		if theme.Id == "Royal" then
			local inner = frame({
				Name = "InnerLine",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -12, 1, -12),
				ZIndex = 2,
				Parent = body,
			})
			corner(inner, UDim.new(0, math.max(radius.Offset - 3, 0)))
			stroke(inner, theme.Colors.StrokeAlt, 1, 0.78)
		elseif theme.Id == "Void" then
			local shine = frame({
				Name = "Shine",
				BackgroundTransparency = 0,
				BackgroundColor3 = WHITE,
				Position = UDim2.new(0, radius.Offset, 0, 1),
				Size = UDim2.new(1, -radius.Offset * 2, 0, 1),
				ZIndex = 2,
				Parent = body,
			})
			gradient(shine, nil, theme.Gradients.Glass, 0)
		end
	end
	if decorated and props.Ornaments ~= false then
		if theme.Ornament == "Corners" then
			royalCorners(theme, root)
		elseif theme.Ornament == "Brackets" then
			voidBrackets(theme, root)
		elseif theme.Ornament == "Fangs" then
			fellAccents(theme, root)
		end
	end
	local pad: number = props.Padding or (if theme.Id == "Classic" then 18 else 16)
	local header: Frame? = nil
	local headerLabel: TextLabel? = nil
	local top = pad
	if props.Title then
		header, headerLabel = buildHeader(theme, root, props.Title, props.TitleIcon)
		top = (HEADER_HEIGHT[theme.Id] or 40) + (if theme.Id == "Classic" then 8 else 6)
	end
	local content = frame({
		Name = "Content",
		Position = UDim2.fromOffset(pad, top),
		Size = UDim2.new(1, -pad * 2, 1, -top - pad),
		ZIndex = 8,
		Parent = root,
	})
	if props.Layout then
		UIKit.ListLayout(content, {
			Horizontal = props.Layout == "Horizontal",
			Gap = props.Gap or 10,
			HAlign = props.HAlign,
			VAlign = props.VAlign,
		})
	end
	if props.AutoSize == "Y" then
		root.AutomaticSize = Enum.AutomaticSize.Y
		content.AutomaticSize = Enum.AutomaticSize.Y
		content.Size = UDim2.new(1, -pad * 2, 0, 0)
		local spacer = frame({ Name = "Spacer", Size = UDim2.new(1, 0, 0, pad), LayoutOrder = 1e6 })
		spacer.Parent = content
	end
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Body = body,
		Content = content,
		Header = header,
		SetTitle = function(text: string)
			if headerLabel then
				headerLabel.Text = UIKit.Upper(text)
			end
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- buttons -----------------------------------------------------------------------------------------
type ButtonParts = {
	theme: Theme,
	variant: string,
	root: TextButton,
	label: TextLabel,
	fill: Frame?,
	fillStroke: UIStroke?,
	fillGradient: UIGradient?,
	glow: Frame?,
	shadow: Frame?,
	icon: Frame?,
	iconName: string?,
	cursor: Frame?,
	heart: Frame?,
	underline: Frame?,
	state: string,
}

local function buttonPalette(theme: Theme, variant: string, state: string): { [string]: any }
	local c = theme.Colors
	local hot = state == "Hover" or state == "Pressed" or state == "Selected"
	local disabled = state == "Disabled"
	local id = theme.Id
	local out: { [string]: any } = {}
	if id == "Classic" then
		local base = if variant == "Primary" then c.Accent
			elseif variant == "Danger" then c.Danger
			else c.Text
		out.stroke = if disabled then c.Disabled elseif hot and variant ~= "Ghost" then c.Hover else base
		out.strokeT = if variant == "Ghost" then 1 else 0
		out.text = if disabled then c.Disabled elseif hot and variant ~= "Ghost" then c.Hover else base
		out.fill = c.Panel
		out.fillT = if variant == "Ghost" then 1 else 0
		out.cursor = hot and not disabled
		out.icon = out.text
	elseif id == "Royal" then
		if variant == "Primary" then
			out.fill, out.fillT = WHITE, 0
			out.fillSeq = theme.Gradients.Accent
			out.text = c.TextInverse
			out.stroke, out.strokeT = Color3.fromRGB(255, 240, 190), if hot then 0 else 0.3
			out.bright = hot
		elseif variant == "Danger" then
			out.fill, out.fillT = c.Accent3, 0
			out.fillSeq = seq2(Color3.fromRGB(255, 170, 180), Color3.fromRGB(150, 150, 150))
			out.text = c.Text
			out.stroke, out.strokeT = c.Stroke, if hot then 0 else 0.25
		elseif variant == "Ghost" then
			out.fill, out.fillT = c.Panel, 1
			out.text = if hot then c.Hover else c.Text
			out.stroke, out.strokeT = c.Stroke, 1
			out.underline = hot
		else
			out.fill, out.fillT = if hot then c.PanelAlt:Lerp(c.Accent, 0.12) else c.PanelAlt, 0
			out.fillSeq = theme.Gradients.PanelFill
			out.text = if hot then c.Hover else c.Text
			out.stroke, out.strokeT = c.Stroke, if hot then 0 else 0.15
		end
		if disabled then
			out.fill, out.fillSeq, out.text, out.stroke, out.strokeT = c.PanelInset, nil, c.Disabled, c.StrokeDim, 0.3
		end
		out.cursor = hot and not disabled
		out.icon = out.text
	elseif id == "Void" then
		if variant == "Primary" then
			out.fill, out.fillT = WHITE, if hot then 0 else 0.08
			out.fillSeq = theme.Gradients.Accent
			out.text = c.TextInverse
			out.stroke, out.strokeT = Color3.fromRGB(190, 250, 255), if hot then 0 else 0.4
			out.glow = if hot then 0.2 else 0.1
		elseif variant == "Danger" then
			out.fill, out.fillT = c.Danger, if hot then 0.7 else 0.82
			out.text = if hot then WHITE else c.Danger
			out.stroke, out.strokeT = c.Danger, if hot then 0 else 0.25
			out.glow = if hot then 0.12 else nil
			out.glowColor = c.Danger
		elseif variant == "Ghost" then
			out.fill, out.fillT = c.Accent, if hot then 0.9 else 1
			out.text = if hot then c.Accent else c.TextDim
			out.stroke, out.strokeT = c.Accent, 1
			out.underline = hot
		else
			out.fill, out.fillT = if hot then c.PanelAlt:Lerp(c.Accent, 0.22) else c.Panel, if hot then 0.3 else 0.42
			out.text = if hot then WHITE else c.Text
			out.stroke, out.strokeT = c.Stroke, if hot then 0 else 0.45
			out.glow = if hot then 0.12 else nil
		end
		if disabled then
			out.fill, out.fillSeq, out.fillT, out.text, out.stroke, out.strokeT, out.glow = c.PanelInset, nil, 0.5, c.Disabled, c.StrokeDim, 0.5, nil
		end
		out.cursor = hot and not disabled
		out.icon = out.text
	else -- Fell
		if variant == "Primary" then
			out.fill, out.fillT = WHITE, 0
			out.fillSeq = theme.Gradients.Accent
			out.text = c.TextInverse
			out.stroke, out.strokeT = if hot then c.Accent2 else c.StrokeAlt, if hot then 0 else 0.35
		elseif variant == "Danger" then
			out.fill, out.fillT = c.Accent2, 0
			out.fillSeq = seq2(Color3.fromRGB(255, 236, 160), Color3.fromRGB(190, 120, 20))
			out.text = Color3.fromRGB(40, 6, 10)
			out.stroke, out.strokeT = c.Accent, if hot then 0 else 0.4
		elseif variant == "Ghost" then
			out.fill, out.fillT = c.Panel, 1
			out.text = if hot then c.Text else c.TextDim
			out.stroke, out.strokeT = c.Accent, 1
			out.underline = hot
		else
			out.fill, out.fillT = if hot then c.PanelAlt:Lerp(c.Accent, 0.35) else c.PanelAlt, 0
			out.text = c.Text
			out.stroke, out.strokeT = if hot then c.StrokeAlt else c.Stroke, 0
		end
		if disabled then
			out.fill, out.fillSeq, out.text, out.stroke, out.strokeT = c.PanelInset, nil, c.Disabled, c.StrokeDim, 0
		end
		out.cursor = hot and not disabled
		out.icon = if variant == "Primary" and not disabled then c.TextInverse else out.text
		out.shadow = state ~= "Pressed" and not disabled and variant ~= "Ghost"
	end
	return out
end

local function applyButtonState(parts: ButtonParts, state: string, animate: boolean)
	parts.state = state
	local theme = parts.theme
	local pal = buttonPalette(theme, parts.variant, state)
	local spec = Motion.Spec(theme, "Hover")
	local function set(inst: Instance?, props: { [string]: any })
		if inst == nil then
			return
		end
		if animate then
			Motion.Tween(inst, spec, props)
		else
			Motion.Set(inst, props)
		end
	end
	set(parts.label, { TextColor3 = pal.text })
	if parts.fill then
		set(parts.fill, { BackgroundColor3 = pal.fill, BackgroundTransparency = pal.fillT or 0 })
		if parts.fillGradient then
			parts.fillGradient.Enabled = pal.fillSeq ~= nil
			if pal.fillSeq then
				parts.fillGradient.Color = pal.fillSeq
			end
			if pal.bright then
				parts.fillGradient.Offset = Vector2.new(0, -0.18)
			else
				parts.fillGradient.Offset = Vector2.new(0, 0)
			end
		end
	end
	if parts.fillStroke then
		set(parts.fillStroke, { Color = pal.stroke, Transparency = pal.strokeT or 0 })
	end
	if parts.glow then
		parts.glow.Visible = pal.glow ~= nil
		for _, s in parts.glow:GetDescendants() do
			if s:IsA("UIStroke") then
				s.Color = pal.glowColor or theme.Glow.Color
				set(s, { Transparency = 1 - (1 - theme.Glow.Transparency) * (1 + (pal.glow or 0) * 6) })
			end
		end
	end
	if parts.icon and parts.iconName then
		-- icons are rebuilt on colour change (cheap; only on state change)
		local old = parts.icon
		local newIcon = Icons.Create(parts.iconName, pal.icon or pal.text, old.Size)
		newIcon.AnchorPoint = old.AnchorPoint
		newIcon.Position = old.Position
		newIcon.ZIndex = old.ZIndex
		newIcon.Visible = old.Visible
		newIcon.Parent = old.Parent
		old:Destroy()
		parts.icon = newIcon
	end
	if parts.heart then
		parts.heart.Visible = pal.cursor == true
		if parts.icon and theme.Id == "Classic" then
			parts.icon.Visible = not pal.cursor
		end
	end
	if parts.cursor then
		parts.cursor.Visible = pal.cursor == true
	end
	if parts.underline then
		parts.underline.Visible = pal.underline == true
	end
	if parts.shadow then
		parts.shadow.Visible = pal.shadow ~= false
	end
	if theme.Id == "Fell" and parts.fill then
		local pressed = state == "Pressed"
		local holder = parts.fill.Parent
		if holder and holder:IsA("GuiObject") then
			holder.Position = if pressed then UDim2.fromOffset(3, 3) else UDim2.fromOffset(0, 0)
		end
	end
end

function UIKit.Button(theme: Theme, props: Props): ButtonHandle
	local variant: string = props.Variant or "Secondary"
	local id = theme.Id
	local c = theme.Colors
	local height: number = props.Height or theme.Button.Height
	local isIcon = variant == "Icon"
	local root: TextButton = make("TextButton", {
		Name = props.Name or ("Button_" .. tostring(props.Text or props.Icon or variant)),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
		Size = if isIcon then UDim2.fromOffset(height, height)
			elseif props.Width then UDim2.fromOffset(props.Width, height)
			else UDim2.new(1, 0, 0, height),
	})
	root.SelectionImageObject = frame({ Name = "NoSelectionBox" })
	local parts: ButtonParts = {
		theme = theme,
		variant = if isIcon then "Secondary" else variant,
		root = root,
		label = nil :: any,
		state = "Normal",
	}
	local radius = if isIcon and id == "Void" then UDim.new(0.5, 0) else theme.ButtonCorner
	-- background layers
	if id == "Fell" then
		local shadowHolder = frame({ Name = "Shadow", Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(5, 5), ZIndex = 0, Parent = root })
		local _, sfill = blade(height, theme.Slant, Color3.fromRGB(0, 0, 0), 0.25)
		;(sfill.Parent :: Frame).Parent = shadowHolder
		parts.shadow = shadowHolder
		local holder = frame({ Name = "Face", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
		local clip, fill = blade(height, if isIcon then theme.Slant * 0.6 else theme.Slant, c.PanelAlt)
		clip.Parent = holder
		parts.fill = fill
		parts.fillStroke = stroke(fill, c.Stroke, 2, 0, Enum.LineJoinMode.Miter)
		parts.fillGradient = gradient(fill, nil, nil, 90 - theme.Slant)
		parts.fillGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.36, WHITE),
			ColorSequenceKeypoint.new(0.64, Color3.fromRGB(150, 150, 150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
		})
	else
		if id == "Void" then
			local glow = frame({
				Name = "GlowHolder",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = if isIcon then UDim2.new(1, -6, 1, -6) else UDim2.fromScale(1, 1),
				ZIndex = 0,
				Parent = root,
			})
			addGlow(theme, glow, radius)
			parts.glow = glow
		end
		local fill = frame({
			Name = "Fill",
			BackgroundTransparency = 0,
			BackgroundColor3 = c.Panel,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = root,
		})
		corner(fill, radius)
		parts.fill = fill
		local thick = if id == "Classic" then 3 elseif id == "Void" then 1.5 else 2
		parts.fillStroke = stroke(fill, c.Stroke, thick, 0, theme.LineJoin)
		if id == "Royal" then
			parts.fillGradient = gradient(fill, nil, nil, 90)
			local inner = frame({
				Name = "Inner",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -8, 1, -8),
				ZIndex = 2,
				Parent = fill,
			})
			corner(inner, UDim.new(0, math.max(radius.Offset - 2, 0)))
			stroke(inner, c.StrokeAlt, 1, if variant == "Ghost" then 1 else 0.82)
			if not isIcon and variant ~= "Ghost" then
				for _, x in { 0, 1 } do
					local d = diamond(c.Stroke, 7)
					d.Position = UDim2.new(x, if x == 0 then 1 else -1, 0.5, 0)
					d.ZIndex = 3
					d.Parent = root
				end
			end
		elseif id == "Void" then
			parts.fillGradient = gradient(fill, nil, nil, 0)
			local shine = frame({
				Name = "Shine",
				BackgroundTransparency = 0,
				BackgroundColor3 = WHITE,
				Position = UDim2.new(0, 8, 0, 1),
				Size = UDim2.new(1, -16, 0, 1),
				ZIndex = 2,
				Parent = fill,
			})
			gradient(shine, nil, theme.Gradients.Glass, 0)
		end
	end
	-- content: icon, label, cursor
	local padX = theme.Button.PaddingX
	local iconSize = math.floor(height * theme.Button.IconSize)
	local align: string = props.Align or (if isIcon then "Center" else theme.Button.Align)
	local labelInsetLeft = padX
	if id == "Classic" and not isIcon then
		-- icon slot (the SOUL replaces the icon while selected, like the battle menu)
		local slotX = padX + iconSize / 2
		labelInsetLeft = padX + iconSize + 12
		if props.Icon and variant ~= "Ghost" then
			local icon = Icons.Create(props.Icon, c.Accent, iconSize)
			icon.Position = UDim2.new(0, slotX, 0.5, 0)
			icon.ZIndex = 4
			icon.Parent = root
			parts.icon = icon
			parts.iconName = props.Icon
		end
		local heart = UIKit.Heart(c.SoulRed, math.floor(iconSize * 0.86))
		heart.Position = UDim2.new(0, slotX, 0.5, 0)
		heart.ZIndex = 5
		heart.Visible = false
		heart.Parent = root
		parts.heart = heart
		align = "Left"
	elseif props.Icon then
		local icon = Icons.Create(props.Icon, c.Text, iconSize)
		icon.ZIndex = 4
		if isIcon then
			icon.Position = UDim2.fromScale(0.5, 0.5)
		elseif align == "Center" then
			icon.Position = UDim2.new(0, padX + iconSize / 2, 0.5, 0)
		else
			icon.Position = UDim2.new(0, padX + iconSize / 2, 0.5, 0)
			labelInsetLeft = padX + iconSize + 10
		end
		icon.Parent = root
		parts.icon = icon
		parts.iconName = props.Icon
	end
	local text: string = props.Text or ""
	if theme.Uppercase and variant ~= "Ghost" then
		text = UIKit.Upper(text)
	elseif variant == "Ghost" and id == "Classic" then
		text = theme.DialoguePrefix .. text
	end
	local label = UIKit.Label(theme, {
		Text = text,
		Role = "Button",
		XAlign = align,
		Color = c.Text,
		Size = UDim2.new(1, -(labelInsetLeft + padX), 1, 0),
		Position = UDim2.fromOffset(labelInsetLeft, 0),
		ZIndex = 4,
	})
	label.Visible = not isIcon
	if align == "Center" then
		label.Size = UDim2.new(1, -padX * 2 - (if props.Icon then iconSize + 10 else 0) * 2, 1, 0)
		label.Position = UDim2.fromScale(0.5, 0)
		label.AnchorPoint = Vector2.new(0.5, 0)
	end
	label.Parent = root
	parts.label = label
	if id ~= "Classic" then
		local cursor = UIKit.Cursor(theme)
		cursor.Position = UDim2.new(0, -theme.Cursor.Size / 2 - 8, 0.5, 0)
		cursor.ZIndex = 6
		cursor.Visible = false
		cursor.Parent = root
		parts.cursor = cursor
		if variant == "Ghost" then
			local underline = frame({
				Name = "Underline",
				BackgroundTransparency = 0,
				BackgroundColor3 = if id == "Fell" then c.Accent else c.Stroke,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(0.6, 0, 0, if id == "Fell" then 3 else 1),
				ZIndex = 3,
				Visible = false,
				Parent = root,
			})
			if id ~= "Fell" then
				gradient(underline, nil, nseq({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }), 0)
			end
			parts.underline = underline
		end
	end
	if props.Hint then
		local hint = UIKit.KeyHint(theme, { Key = props.Hint, Height = math.floor(height * 0.5) })
		hint.AnchorPoint = Vector2.new(1, 0.5)
		hint.Position = UDim2.new(1, -padX, 0.5, 0)
		hint.ZIndex = 5
		hint.Parent = root
	end
	-- state
	local disabled = props.Disabled == true
	local selected = props.Selected == true
	local function baseState(): string
		if disabled then
			return "Disabled"
		elseif selected then
			return "Selected"
		end
		return "Normal"
	end
	applyButtonState(parts, props.State or baseState(), false)
	-- interaction (runtime only)
	local hovering = false
	Motion.Hover(root, function()
		hovering = true
		if not disabled then
			Motion.Sound(theme.Sounds.Hover)
			applyButtonState(parts, "Hover", true)
		end
	end, function()
		hovering = false
		applyButtonState(parts, baseState(), true)
	end)
	Motion.Press(root, function()
		if not disabled then
			applyButtonState(parts, "Pressed", true)
		end
	end, function()
		applyButtonState(parts, if hovering then "Hover" else baseState(), true)
	end)
	Motion.On(root, "Activated", function()
		if disabled then
			Motion.Sound(theme.Sounds.Error)
			Motion.Shake(root, 4, 0.18)
			return
		end
		Motion.Sound(theme.Sounds.Select)
		if props.OnActivated then
			props.OnActivated()
		end
	end)
	applyBase(root, props)
	if isIcon and props.Size == nil then
		root.Size = UDim2.fromOffset(height, height)
	end
	finish(root, props)
	return {
		Root = root,
		Label = label,
		SetText = function(newText: string)
			local t = newText
			if theme.Uppercase and variant ~= "Ghost" then
				t = UIKit.Upper(t)
			elseif variant == "Ghost" and id == "Classic" then
				t = theme.DialoguePrefix .. t
			end
			label.Text = t
		end,
		SetState = function(state: string)
			applyButtonState(parts, state, true)
		end,
		SetSelected = function(value: boolean)
			selected = value
			applyButtonState(parts, if hovering then "Hover" else baseState(), true)
		end,
		SetDisabled = function(value: boolean)
			disabled = value
			root.Selectable = not value
			applyButtonState(parts, baseState(), true)
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- key hints & badges --------------------------------------------------------------------------------
local GAMEPAD_GLYPHS: { [string]: { text: string, color: Color3?, shape: string } } = {
	ButtonA = { text = "A", color = Color3.fromRGB(96, 200, 90), shape = "Circle" },
	ButtonB = { text = "B", color = Color3.fromRGB(230, 70, 70), shape = "Circle" },
	ButtonX = { text = "X", color = Color3.fromRGB(70, 140, 240), shape = "Circle" },
	ButtonY = { text = "Y", color = Color3.fromRGB(240, 200, 60), shape = "Circle" },
	ButtonL1 = { text = "LB", shape = "Pill" },
	ButtonR1 = { text = "RB", shape = "Pill" },
	ButtonL2 = { text = "LT", shape = "Pill" },
	ButtonR2 = { text = "RT", shape = "Pill" },
	ButtonL3 = { text = "LS", shape = "Circle" },
	ButtonR3 = { text = "RS", shape = "Circle" },
	ButtonStart = { text = "≡", shape = "Circle" },
	ButtonSelect = { text = "⧉", shape = "Circle" },
	DPadUp = { text = "▲", shape = "Pad" },
	DPadDown = { text = "▼", shape = "Pad" },
	DPadLeft = { text = "◀", shape = "Pad" },
	DPadRight = { text = "▶", shape = "Pad" },
}

local KEY_ALIASES: { [string]: string } = {
	L1 = "ButtonL1",
	R1 = "ButtonR1",
	L2 = "ButtonL2",
	R2 = "ButtonR2",
	A = "ButtonA",
	B = "ButtonB",
	X = "ButtonX",
	Y = "ButtonY",
	LeftShift = "Shift",
	LeftControl = "Ctrl",
	Return = "Enter",
}

function UIKit.KeyHint(theme: Theme, props: Props): Frame
	local c = theme.Colors
	local h: number = props.Height or 28
	local key: string = props.Key or "?"
	local device: string = props.Device or (if GAMEPAD_GLYPHS[KEY_ALIASES[key] or key] and (string.sub(key, 1, 6) == "Button" or string.sub(key, 1, 4) == "DPad" or props.Device == "Gamepad") then "Gamepad" else "Keyboard")
	local root = frame({ Name = "KeyHint_" .. key, Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X })
	UIKit.ListLayout(root, { Horizontal = true, Gap = 8, VAlign = Enum.VerticalAlignment.Center })
	local cap: Frame
	if key == "M1" or key == "M2" or device == "Mouse" then
		cap = frame({ Name = "Cap", Size = UDim2.fromOffset(h, h), LayoutOrder = 1 })
		local icon = Icons.Create("Mouse", c.TextDim, UDim2.fromScale(0.86, 0.86), if key == "M2" then c.Accent else c.Accent)
		icon.Parent = cap
		if key == "M2" then
			icon.Rotation = 0
		end
	elseif device == "Gamepad" then
		local glyph = GAMEPAD_GLYPHS[KEY_ALIASES[key] or key] or { text = key, shape = "Circle" }
		local w = if glyph.shape == "Pill" then math.floor(h * 1.5) else h
		cap = frame({
			Name = "Cap",
			BackgroundTransparency = 0,
			BackgroundColor3 = if theme.Id == "Classic" then BLACK else Color3.fromRGB(26, 28, 36),
			Size = UDim2.fromOffset(w, h),
			LayoutOrder = 1,
		})
		corner(cap, if glyph.shape == "Pad" then UDim.new(0, 4) else UDim.new(0.5, 0))
		stroke(cap, glyph.color or c.TextDim, if theme.Id == "Classic" then 2 else 1.5)
		local t = UIKit.Label(theme, {
			Text = glyph.text,
			Role = "Caption",
			TextSize = math.floor(h * 0.5),
			Color = glyph.color or c.Text,
			XAlign = "Center",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
		})
		t.FontFace = UIKit.Font(theme, "Number")
		t.Parent = cap
	else
		local text = KEY_ALIASES[key] or key
		cap = frame({
			Name = "Cap",
			BackgroundTransparency = 0,
			BackgroundColor3 = if theme.Id == "Classic" then BLACK else c.PanelAlt,
			Size = UDim2.fromOffset(h, h),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
		})
		corner(cap, theme.SmallCorner)
		stroke(cap, if theme.Id == "Classic" then WHITE else c.StrokeDim, if theme.Id == "Classic" then 2 else 1, 0, theme.LineJoin)
		if theme.Id ~= "Classic" then
			-- 3D keycap lip
			local lip = frame({
				Name = "Lip",
				BackgroundTransparency = 0,
				BackgroundColor3 = BLACK,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 3),
				Parent = cap,
			})
			lip.BackgroundTransparency = 0.55
			corner(lip, theme.SmallCorner)
		end
		local t = UIKit.Label(theme, {
			Text = UIKit.Upper(text),
			Role = "Caption",
			TextSize = math.floor(h * (if #text > 1 then 0.42 else 0.5)),
			Color = c.Text,
			XAlign = "Center",
			AutoSize = "X",
			Size = UDim2.new(0, 0, 1, -2),
			ZIndex = 2,
		})
		t.FontFace = UIKit.Font(theme, if theme.Id == "Classic" then "Caption" else "Mono")
		UIKit.Padding(t, math.floor(h * 0.3), 0, math.floor(h * 0.3), 0)
		t.Parent = cap
	end
	cap.Parent = root
	if props.Label then
		local label = UIKit.Label(theme, {
			Text = props.Label,
			Role = "Caption",
			TextSize = props.TextSize or theme.TextSize.Small,
			Tone = "Dim",
			AutoSize = "X",
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 2,
		})
		label.Parent = root
	end
	applyBase(root, props)
	if props.Size then
		root.AutomaticSize = Enum.AutomaticSize.None
	end
	return finish(root, props)
end

function UIKit.Badge(theme: Theme, props: Props): Frame
	local c = theme.Colors
	local color: Color3 = if typeof(props.Color) == "Color3" then props.Color else toneColor(theme, props.Color or "Accent")
	local style: string = props.Style or "Soft"
	local h: number = props.Height or 24
	local root = frame({
		Name = "Badge",
		BackgroundTransparency = if style == "Solid" then 0 elseif style == "Soft" then 0.8 else 1,
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(0, h),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	corner(root, if theme.Id == "Void" then UDim.new(0.5, 0) else theme.SmallCorner)
	if style ~= "Solid" then
		stroke(root, color, if theme.Id == "Classic" then 2 else 1, if style == "Soft" then 0.35 else 0, theme.LineJoin)
	end
	UIKit.ListLayout(root, { Horizontal = true, Gap = 5, VAlign = Enum.VerticalAlignment.Center })
	UIKit.Padding(root, math.floor(h * 0.4), 0, math.floor(h * 0.4), 0)
	if props.Icon then
		local icon = Icons.Create(props.Icon, if style == "Solid" then c.TextInverse else color, math.floor(h * 0.62))
		icon.LayoutOrder = 1
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Parent = root
	end
	local label = UIKit.Label(theme, {
		Text = UIKit.Upper(props.Text or ""),
		Role = "Caption",
		TextSize = props.TextSize or (if theme.Id == "Classic" then 9 else theme.TextSize.Caption),
		Color = if style == "Solid" then c.TextInverse else color:Lerp(WHITE, 0.25),
		AutoSize = "X",
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
	})
	label.Parent = root
	applyBase(root, props)
	return finish(root, props)
end

-- titles ------------------------------------------------------------------------------------------
function UIKit.Title(theme: Theme, props: Props): { Root: Frame, Label: TextLabel, Set: (string) -> (), Destroy: () -> () }
	local c = theme.Colors
	local role: string = props.Role or "Title"
	local size: number = props.TextSize or (if role == "Display" then theme.TextSize.Hero else theme.TextSize.Title)
	local text: string = UIKit.Upper(props.Text or "")
	local align: string = props.XAlign or "Left"
	local root = frame({ Name = props.Name or "Title", Size = UDim2.new(1, 0, 0, math.ceil(size * 1.3)) })
	local layers: { TextLabel } = {}
	local function layer(name: string, color: Color3, offset: Vector2, z: number, transparency: number?): TextLabel
		local l = UIKit.Label(theme, {
			Text = text,
			Role = role,
			TextSize = size,
			Color = color,
			XAlign = align,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(offset.X, offset.Y),
			ZIndex = z,
			Transparency = transparency,
			Scaled = true,
			MaxTextSize = size,
		})
		l.Name = name
		l.Parent = root
		table.insert(layers, l)
		return l
	end
	local main: TextLabel
	if theme.Id == "Classic" then
		layer("Shadow", Color3.fromRGB(48, 48, 48), Vector2.new(theme.Pixel, theme.Pixel), 1)
		main = layer("Main", c.Text, Vector2.zero, 2)
	elseif theme.Id == "Royal" then
		local glow = layer("Glow", c.Glow, Vector2.new(0, 2), 1, 0.55)
		textStroke(glow, c.Glow, 5, 0.86)
		main = layer("Main", WHITE, Vector2.zero, 2)
		gradient(main, theme.Gradients.Title, nil, 90)
		textStroke(main, Color3.fromRGB(52, 34, 8), 2, 0.1)
	elseif theme.Id == "Void" then
		local glow = layer("Glow", c.Accent, Vector2.zero, 1, 0.5)
		textStroke(glow, c.Accent, 7, 0.82)
		main = layer("Main", WHITE, Vector2.zero, 2)
		gradient(main, theme.Gradients.Title, nil, 90)
		textStroke(main, c.Accent, 1, 0.55)
		if props.Glow ~= false then
			Motion.Pulse(glow, { TextTransparency = 0.5 }, { TextTransparency = 0.25 }, theme.Motion.PulsePeriod)
		end
	else -- Fell
		layer("Shadow", BLACK, Vector2.new(5, 5), 1, 0.1)
		local split = layer("Split", c.Accent, Vector2.new(-3, 0), 2, 0.15)
		split.Name = "Chromatic"
		main = layer("Main", WHITE, Vector2.zero, 3)
		gradient(main, theme.Gradients.Title, nil, 90)
		textStroke(main, BLACK, 2.5, 0)
		root.Rotation = props.Rotation or -2
	end
	if props.Subtitle then
		local sub = UIKit.Label(theme, {
			Text = props.Subtitle,
			Role = "Subtitle",
			Tone = if theme.Id == "Royal" then "Accent" else "Dim",
			XAlign = align,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, 0, 1, 2),
			Size = UDim2.new(1, 0, 0, theme.TextSize.Subtitle + 6),
			ZIndex = 4,
		})
		sub.Name = "Subtitle"
		sub.Parent = root
	end
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Label = main,
		Set = function(newText: string)
			local t = UIKit.Upper(newText)
			for _, l in layers do
				l.Text = t
			end
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- bars --------------------------------------------------------------------------------------------
local function barColors(theme: Theme, hud: HudStyle?, kind: string): (Color3, Color3, ColorSequence?)
	if hud then
		local hc = hud.Colors
		local g = hud.Gradients
		if kind == "Guard" then
			return hc.Guard, hc.GuardBack, g.Guard
		elseif kind == "Ult" then
			return hc.Ult, hc.HPBack:Lerp(BLACK, 0.5), g.Ult
		elseif kind == "Monster" then
			return hc.Monster, hc.HPBack, g.Monster
		elseif kind == "Dodge" then
			return hc.Dodge, hc.DodgeEmpty, nil
		end
		return hc.HP, hc.HPBack, g.HP
	end
	local c = theme.Colors
	if kind == "Guard" then
		return c.Guard, c.PanelInset, nil
	elseif kind == "Ult" then
		return c.Ult, c.PanelInset, nil
	elseif kind == "Exp" then
		return c.Exp, c.PanelInset, nil
	elseif kind == "Dodge" then
		return c.Dodge, c.PanelInset, nil
	elseif kind == "Custom" then
		return c.Accent, c.PanelInset, nil
	end
	return c.HP, c.HPBack, nil
end

function UIKit.Bar(theme: Theme, props: Props): BarHandle
	local hud: HudStyle? = props.Hud
	local kind: string = props.Kind or "HP"
	local battle = (hud ~= nil and hud.Id == "Battle") or (hud == nil and theme.Id == "Classic")
	local fillColor, backColor, fillSeq = barColors(theme, hud, kind)
	fillColor = props.Color or fillColor
	backColor = props.BackColor or backColor
	local krColor: Color3 = props.SecondaryColor or (if hud then hud.Colors.KR else theme.Colors.KR)
	local height: number = props.Height or (if hud then hud.Bar.Height else 14)
	local labelFont = if hud then Themes.HudFont(hud, "Label", language()) else UIKit.Font(theme, "Caption")
	local numberFont = if hud then Themes.HudFont(hud, "Number", language()) else UIKit.Font(theme, "Number")
	local textSize: number = if hud then hud.TextSize.Label else theme.TextSize.Caption
	local numberSize: number = if hud then hud.TextSize.Number else theme.TextSize.Small
	local textColor: Color3 = if hud then hud.Colors.Text else theme.Colors.Text
	local corner_: UDim = if hud then hud.Bar.Corner elseif battle then UDim.new(0, 0) else UDim.new(0, math.min(4, height / 2))
	local root = frame({ Name = props.Name or ("Bar_" .. kind), Size = UDim2.new(1, 0, 0, math.max(height, textSize + 6)) })
	local left = 0
	local right = 0
	if props.Label then
		local chars = utf8.len(props.Label) or #props.Label
		local labelWidth: number = props.LabelWidth
			or math.max(if battle then textSize * 2 + 10 else 48, math.ceil(chars * textSize * (if battle then 1 else 0.62)) + 8)
		local lab = make("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Text = UIKit.Upper(props.Label),
			FontFace = labelFont,
			TextSize = textSize,
			TextColor3 = if hud then hud.Colors.TextDim:Lerp(textColor, 0.5) else theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0, labelWidth, 1, 0),
			ZIndex = 3,
			Parent = root,
		})
		if battle then
			lab.TextColor3 = textColor
		end
		left = labelWidth + 6
	end
	local valueLabel: TextLabel? = nil
	local krTag: TextLabel? = nil
	if props.ShowValue then
		local valueWidth: number = props.ValueWidth or (numberSize * 6 + 8)
		valueLabel = make("TextLabel", {
			Name = "Value",
			BackgroundTransparency = 1,
			Text = "",
			FontFace = numberFont,
			TextSize = numberSize,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, valueWidth, 1, 0),
			ZIndex = 3,
			Parent = root,
		})
		right = valueWidth + 8
		if battle and props.Secondary ~= nil then
			krTag = make("TextLabel", {
				Name = "KR",
				BackgroundTransparency = 1,
				Text = "KR",
				FontFace = labelFont,
				TextSize = textSize,
				TextColor3 = krColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -right, 0, 0),
				Size = UDim2.new(0, textSize * 2 + 4, 1, 0),
				ZIndex = 3,
				Parent = root,
			})
			right += textSize * 2 + 10
		end
	end
	local track = frame({
		Name = "Track",
		BackgroundTransparency = if hud then hud.Bar.BackTransparency else 0,
		BackgroundColor3 = backColor,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, 0),
		Size = UDim2.new(1, -(left + right), 0, height),
		ZIndex = 1,
		Parent = root,
	})
	corner(track, corner_)
	if hud and hud.Bar.StrokeThickness > 0 then
		stroke(track, hud.Bar.StrokeColor, hud.Bar.StrokeThickness, hud.Bar.StrokeTransparency)
	elseif not hud and not battle then
		stroke(track, theme.Colors.StrokeDim, 1, if theme.Id == "Void" then 0.4 else 0)
	end
	local segments: number? = props.Segments
	local pips: { Frame } = {}
	local fill: Frame? = nil
	local ghost: Frame? = nil
	local secondary: Frame? = nil
	if segments and segments > 0 then
		track.BackgroundTransparency = 1
		local gap: number = if hud then hud.Bar.SegmentGap else 4
		for i = 1, segments do
			local pip = frame({
				Name = "Pip" .. i,
				BackgroundTransparency = 0,
				BackgroundColor3 = backColor,
				Position = UDim2.new((i - 1) / segments, if i == 1 then 0 else gap / 2, 0, 0),
				Size = UDim2.new(1 / segments, -(if i == 1 or i == segments then gap / 2 else gap), 1, 0),
				ZIndex = 2,
				Parent = track,
			})
			corner(pip, if battle then UDim.new(0, 0) else corner_)
			local inner = frame({
				Name = "Fill",
				BackgroundTransparency = 0,
				BackgroundColor3 = fillColor,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
				Parent = pip,
			})
			corner(inner, if battle then UDim.new(0, 0) else corner_)
			if theme.Id == "Royal" and not hud then
				local d = diamond(fillColor, 1)
				d.Parent = nil
			end
			table.insert(pips, pip)
		end
	else
		if props.Ghost or (hud and hud.Bar.Ghost) then
			ghost = frame({
				Name = "Ghost",
				BackgroundTransparency = 0.25,
				BackgroundColor3 = if hud then hud.Colors.Ghost else WHITE,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 1,
				Parent = track,
			})
			corner(ghost, corner_)
		end
		fill = frame({
			Name = "Fill",
			BackgroundTransparency = 0,
			BackgroundColor3 = if fillSeq then WHITE else fillColor,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = track,
		})
		corner(fill, corner_)
		if fillSeq then
			gradient(fill, fillSeq, nil, 0)
		elseif not battle and theme.Gradients.Bar and not hud then
			gradient(fill, theme.Gradients.Bar, nil, 90)
		end
		if props.Secondary ~= nil then
			secondary = frame({
				Name = "KR",
				BackgroundTransparency = 0,
				BackgroundColor3 = krColor,
				Size = UDim2.fromScale(0, 1),
				ZIndex = 3,
				Parent = track,
			})
			corner(secondary, if battle then UDim.new(0, 0) else UDim.new(0, 0))
		end
		if (hud and hud.Bar.Shine) or (not hud and not battle) then
			local shine = frame({
				Name = "Shine",
				BackgroundTransparency = 0.78,
				BackgroundColor3 = WHITE,
				Position = UDim2.fromOffset(2, 1),
				Size = UDim2.new(1, -4, 0.38, 0),
				ZIndex = 4,
				Parent = track,
			})
			corner(shine, corner_)
		end
	end
	local value: number = props.Value or 1
	local max: number = props.Max or 1
	local sec: number = props.Secondary or 0
	local fmt = props.Format or function(v: number, m: number): string
		return string.format("%d / %d", math.floor(v + 0.5), math.floor(m + 0.5))
	end
	local function render(animate: boolean)
		local m = math.max(max, 1e-6)
		local v = math.clamp(value, 0, m)
		local s = math.clamp(sec, 0, v)
		if #pips > 0 then
			for i, pip in pips do
				local f = pip:FindFirstChild("Fill") :: Frame?
				if f then
					local amount = math.clamp(v - (i - 1), 0, 1)
					f.Size = UDim2.fromScale(amount, 1)
					f.Visible = amount > 0
				end
			end
		else
			local main = (v - s) / m
			if fill then
				if animate then
					Motion.Tween(fill, Motion.Spec(theme, "Hover"), { Size = UDim2.fromScale(main, 1) })
				else
					fill.Size = UDim2.fromScale(main, 1)
				end
				fill.Visible = main > 0.001
			end
			if secondary then
				secondary.Position = UDim2.fromScale(main, 0)
				secondary.Size = UDim2.fromScale(s / m, 1)
				secondary.Visible = s > 0
			end
			if ghost then
				local target = UDim2.fromScale(v / m, 1)
				if animate and Motion.IsLive() then
					Motion.Tween(ghost, { Time = 0.6, Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out, Delay = 0.35 }, { Size = target })
				else
					ghost.Size = target
				end
			end
		end
		if valueLabel then
			valueLabel.Text = fmt(v, m)
			valueLabel.TextColor3 = if s > 0 and battle then krColor
				elseif s > 0 and hud then hud.Colors.KRText
				else textColor
		end
		if krTag then
			krTag.Visible = true
		end
	end
	render(false)
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Set = function(newValue: number, newMax: number?, newSecondary: number?)
			value = newValue
			if newMax then
				max = newMax
			end
			if newSecondary then
				sec = newSecondary
			end
			render(true)
		end,
		SetColor = function(color: Color3)
			if fill then
				fill.BackgroundColor3 = color
			end
			for _, pip in pips do
				local f = pip:FindFirstChild("Fill") :: Frame?
				if f then
					f.BackgroundColor3 = color
				end
			end
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- rows & small displays -----------------------------------------------------------------------------
function UIKit.StatRow(theme: Theme, props: Props): Frame
	local c = theme.Colors
	local h: number = props.Height or 30
	local root = frame({ Name = "Stat_" .. tostring(props.Label), Size = UDim2.new(1, 0, 0, h) })
	local x = 0
	if props.Icon then
		local icon = Icons.Create(props.Icon, props.Color or c.Accent, math.floor(h * 0.68))
		icon.Position = UDim2.new(0, math.floor(h * 0.34), 0.5, 0)
		icon.Parent = root
		x = h + 2
	end
	local valueWidth: number = props.ValueWidth or 64
	local label = UIKit.Label(theme, {
		Text = props.Label or "",
		Role = "Body",
		TextSize = props.TextSize or theme.TextSize.Small,
		Tone = "Dim",
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x - valueWidth - 4, 1, 0),
		Truncate = true,
	})
	label.Parent = root
	local value = UIKit.Label(theme, {
		Text = tostring(props.Value or ""),
		Role = "Number",
		TextSize = props.ValueSize or theme.TextSize.Small + 2,
		Color = props.ValueColor or c.Text,
		XAlign = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, valueWidth, 1, 0),
	})
	value.Parent = root
	if props.Fill then
		local track = frame({
			Name = "Mini",
			BackgroundTransparency = 0,
			BackgroundColor3 = c.PanelInset,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, x, 1, 0),
			Size = UDim2.new(1, -x, 0, 3),
			Parent = root,
		})
		corner(track, UDim.new(0.5, 0))
		local f = frame({
			Name = "Fill",
			BackgroundTransparency = 0,
			BackgroundColor3 = props.Color or c.Accent,
			Size = UDim2.fromScale(math.clamp(props.Fill, 0, 1), 1),
			Parent = track,
		})
		corner(f, UDim.new(0.5, 0))
	else
		-- dotted leader
		local leader = frame({
			Name = "Leader",
			BackgroundTransparency = if theme.Id == "Classic" then 0.6 else 0.8,
			BackgroundColor3 = c.TextMuted,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, x, 1, -2),
			Size = UDim2.new(1, -x, 0, 1),
			Parent = root,
		})
		if theme.Id ~= "Classic" then
			gradient(leader, nil, nseq({ { 0, 1 }, { 0.3, 0.2 }, { 1, 0.2 } }), 0)
		end
	end
	applyBase(root, props)
	return finish(root, props)
end

function UIKit.Countdown(theme: Theme, props: Props): { Root: Frame, Set: (number) -> (), Destroy: () -> () }
	local c = theme.Colors
	local size: number = props.TextSize or theme.TextSize.Title
	local root = frame({ Name = "Countdown", Size = UDim2.fromOffset(size * 4, size * 1.6) })
	local label = UIKit.Label(theme, {
		Text = "",
		Role = "Number",
		TextSize = size,
		XAlign = props.XAlign or "Center",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	label.Parent = root
	if theme.Id == "Royal" then
		label.TextColor3 = WHITE
		gradient(label, theme.Gradients.Title, nil, 90)
		textStroke(label, Color3.fromRGB(52, 34, 8), 1.5, 0.2)
	end
	local glowStroke: UIStroke? = nil
	if theme.Id == "Void" then
		glowStroke = textStroke(label, c.Accent, 3, 0.75)
	elseif theme.Id == "Fell" then
		textStroke(label, BLACK, 2, 0)
	end
	local caption: TextLabel? = nil
	if props.Label then
		caption = UIKit.Label(theme, {
			Text = UIKit.Upper(props.Label),
			Role = "Caption",
			Tone = "Dim",
			XAlign = props.XAlign or "Center",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.new(1, 0, 0, theme.TextSize.Caption + 4),
		})
		;(caption :: TextLabel).Parent = root
	end
	local urgent: number = props.Urgent or 10
	local format: string = props.Format or "Clock"
	local pulseStop: (() -> ())? = nil
	local function set(seconds: number)
		local s = math.max(0, math.ceil(seconds))
		if format == "Clock" then
			label.Text = string.format("%d:%02d", s // 60, s % 60)
		else
			label.Text = tostring(s)
		end
		local isUrgent = s <= urgent
		label.TextColor3 = if isUrgent then c.Danger elseif theme.Id == "Royal" then WHITE else c.Text
		if glowStroke then
			glowStroke.Color = if isUrgent then c.Danger else c.Accent
			glowStroke.Transparency = if isUrgent then 0.8 else 0.75
		end
		if isUrgent and pulseStop == nil and Motion.IsLive() then
			pulseStop = Motion.Pulse(label, { TextTransparency = 0 }, { TextTransparency = 0.35 }, 0.5)
		elseif not isUrgent and pulseStop then
			pulseStop()
			pulseStop = nil
			label.TextTransparency = 0
		end
	end
	set(props.Seconds or 0)
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Set = set,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- toggles, sliders, selectors ----------------------------------------------------------------------
local function rowShell(theme: Theme, props: Props, defaultHeight: number): (TextButton, TextLabel?, Frame)
	local h: number = props.Height or defaultHeight
	local root: TextButton = make("TextButton", {
		Name = props.Name or ("Row_" .. tostring(props.Label)),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
		Size = UDim2.new(1, 0, 0, h),
	})
	root.SelectionImageObject = frame({ Name = "NoSelectionBox" })
	local label: TextLabel? = nil
	local controlWidth: number = props.ControlWidth or 0.5
	local inset = if theme.Id == "Classic" then 26 else 0
	if props.Label then
		label = UIKit.Label(theme, {
			Text = props.Label,
			Role = "Body",
			Position = UDim2.fromOffset(inset, 0),
			Size = UDim2.new(1 - controlWidth, -8 - inset, 1, 0),
			Truncate = true,
		})
		;(label :: TextLabel).Parent = root
	end
	local control = frame({
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = if props.Label then UDim2.new(controlWidth, 0, 1, 0) else UDim2.fromScale(1, 1),
		Parent = root,
	})
	-- focus cursor
	local cursor = UIKit.Cursor(theme, if theme.Cursor.Style == "Heart" then 16 else nil)
	cursor.Position = if theme.Id == "Classic" then UDim2.new(0, 9, 0.5, 0) else UDim2.new(0, -theme.Cursor.Size / 2 - 6, 0.5, 0)
	cursor.Visible = props.State == "Hover"
	cursor.ZIndex = 6
	cursor.Parent = root
	Motion.Hover(root, function()
		cursor.Visible = true
		Motion.Sound(theme.Sounds.Hover)
	end, function()
		cursor.Visible = false
	end)
	return root, label, control
end

function UIKit.Toggle(theme: Theme, props: Props): { Root: TextButton, Set: (boolean) -> (), Get: () -> boolean, Destroy: () -> () }
	local c = theme.Colors
	local root, _, control = rowShell(theme, props, 40)
	local value = props.Value == true
	local id = theme.Id
	local w, h = 58, 26
	local holder = frame({ Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(w, h), Parent = control })
	local track = frame({ Name = "Track", BackgroundTransparency = 0, BackgroundColor3 = c.PanelInset, Size = UDim2.fromScale(1, 1), Parent = holder })
	local knob = frame({ Name = "Knob", BackgroundTransparency = 0, BackgroundColor3 = c.Text, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Parent = holder })
	local stateText: TextLabel? = nil
	local trackStroke: UIStroke
	if id == "Classic" then
		holder.Size = UDim2.fromOffset(26, 26)
		trackStroke = stroke(track, c.Stroke, 3, 0, Enum.LineJoinMode.Miter)
		knob.Size = UDim2.fromOffset(12, 12)
		knob.Position = UDim2.fromScale(0.5, 0.5)
		stateText = UIKit.Label(theme, {
			Text = "",
			Role = "Button",
			TextSize = theme.TextSize.Small,
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -40, 0.5, 0),
			Size = UDim2.fromOffset(80, 20),
		})
		;(stateText :: TextLabel).Parent = control
	elseif id == "Fell" then
		trackStroke = stroke(track, c.Stroke, 2, 0, Enum.LineJoinMode.Miter)
		knob.Size = UDim2.fromOffset(16, 16)
		knob.Rotation = 45
		stroke(knob, c.Accent2, 1.5, 0, Enum.LineJoinMode.Miter)
	else
		corner(track, UDim.new(0.5, 0))
		corner(knob, UDim.new(0.5, 0))
		trackStroke = stroke(track, if id == "Royal" then c.Stroke else c.Stroke, 1.5, if id == "Void" then 0.35 else 0)
		knob.Size = UDim2.fromOffset(h - 8, h - 8)
		if id == "Royal" then
			knob.BackgroundColor3 = WHITE
			gradient(knob, theme.Gradients.Accent, nil, 90)
		end
	end
	local function render(animate: boolean)
		local spec = Motion.Spec(theme, "Hover")
		local props2: { [string]: any }
		if id == "Classic" then
			knob.Visible = value
			knob.BackgroundColor3 = c.Selected
			if stateText then
				stateText.Text = UIKit.Upper(L(if value then "common.on" else "common.off"))
				stateText.TextColor3 = if value then c.Selected else c.TextDim
			end
			return
		end
		local x = if value then 1 else 0
		props2 = { Position = UDim2.new(x, if value then -h / 2 else h / 2, 0.5, 0) }
		if animate then
			Motion.Tween(knob, spec, props2)
		else
			Motion.Set(knob, props2)
		end
		track.BackgroundColor3 = if value then c.Accent:Lerp(c.PanelInset, if id == "Void" then 0.55 else 0.35) else c.PanelInset
		trackStroke.Color = if value then c.Accent else c.StrokeDim
		if id == "Void" then
			knob.BackgroundColor3 = if value then WHITE else c.TextDim
		elseif id == "Fell" then
			knob.BackgroundColor3 = if value then c.Accent else c.TextMuted
		end
	end
	render(false)
	Motion.On(root, "Activated", function()
		value = not value
		Motion.Sound(theme.Sounds.Toggle)
		render(true)
		if props.OnChanged then
			props.OnChanged(value)
		end
	end)
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Set = function(v: boolean)
			value = v
			render(true)
		end,
		Get = function()
			return value
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

function UIKit.Slider(theme: Theme, props: Props): { Root: TextButton, Set: (number) -> (), Get: () -> number, Destroy: () -> () }
	local c = theme.Colors
	local id = theme.Id
	local root, _, control = rowShell(theme, props, 40)
	local min: number = props.Min or 0
	local max: number = props.Max or 1
	local step: number? = props.Step
	local value: number = math.clamp(props.Value or min, min, max)
	local fmt = props.Format or function(v: number): string
		if max - min <= 1 then
			return tostring(math.round(v * 100)) .. "%"
		end
		return tostring(math.round(v))
	end
	local valueText = UIKit.Label(theme, {
		Text = "",
		Role = "Number",
		TextSize = theme.TextSize.Small,
		XAlign = "Right",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(52, 20),
		Tone = "Dim",
	})
	valueText.Parent = control
	local trackH = if id == "Classic" then 10 elseif id == "Void" then 4 else 6
	local area = frame({ Name = "Area", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.new(1, -72, 1, 0), Parent = control })
	local track = frame({
		Name = "Track",
		BackgroundTransparency = 0,
		BackgroundColor3 = if id == "Classic" then c.Danger else c.PanelInset,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, trackH),
		Parent = area,
	})
	local fill = frame({ Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = c.Accent, Size = UDim2.fromScale(0, 1), ZIndex = 2, Parent = track })
	if id == "Classic" then
		fill.BackgroundColor3 = c.HP
	else
		corner(track, UDim.new(0.5, 0))
		corner(fill, UDim.new(0.5, 0))
		stroke(track, c.StrokeDim, 1, if id == "Void" then 0.3 else 0)
		if id == "Royal" or id == "Fell" or id == "Void" then
			fill.BackgroundColor3 = WHITE
			gradient(fill, theme.Gradients.Accent, nil, if id == "Void" then 0 else 90)
		end
	end
	local knob: Frame
	if id == "Classic" then
		knob = UIKit.Heart(c.SoulRed, 20)
	elseif id == "Royal" then
		knob = frame({ Name = "Knob", Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5) })
		local d = diamond(WHITE, 14)
		d.Position = UDim2.fromScale(0.5, 0.5)
		gradient(d, theme.Gradients.Accent, nil, 45)
		stroke(d, Color3.fromRGB(60, 40, 10), 1, 0.3)
		d.Parent = knob
		local dot = diamond(c.PanelInset, 5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.ZIndex = 2
		dot.Parent = knob
	elseif id == "Void" then
		knob = frame({ Name = "Knob", BackgroundTransparency = 0, BackgroundColor3 = WHITE, Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5) })
		corner(knob, UDim.new(0.5, 0))
		stroke(knob, c.Accent, 3, 0.55)
	else
		knob = frame({ Name = "Knob", BackgroundTransparency = 0, BackgroundColor3 = c.Accent, Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45 })
		stroke(knob, c.Accent2, 1.5, 0, Enum.LineJoinMode.Miter)
	end
	knob.ZIndex = 4
	knob.Parent = area
	local function render()
		local alpha = if max > min then (value - min) / (max - min) else 0
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueText.Text = fmt(value)
	end
	local function setValue(v: number, notify: boolean)
		local nv = math.clamp(v, min, max)
		if step and step > 0 then
			nv = min + math.round((nv - min) / step) * step
		end
		if nv ~= value then
			value = nv
			render()
			if notify and props.OnChanged then
				props.OnChanged(value)
			end
		end
	end
	render()
	Motion.BindDrag(area, function(ax: number)
		setValue(min + (max - min) * ax, true)
	end)
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Set = function(v: number)
			setValue(v, false)
			render()
		end,
		Get = function()
			return value
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

local function normalizeOptions(options: { any }?): { { Id: string, Text: string } }
	local out = {}
	for i, opt in options or {} do
		if type(opt) == "string" then
			table.insert(out, { Id = opt, Text = opt })
		else
			table.insert(out, { Id = tostring(opt.Id or i), Text = tostring(opt.Text or opt.Id or i) })
		end
	end
	return out
end

local function arrowButton(theme: Theme, iconName: string, size: number): TextButton
	local c = theme.Colors
	local b: TextButton = make("TextButton", {
		Name = iconName,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = if theme.Id == "Classic" then 1 else 0,
		BackgroundColor3 = c.PanelAlt,
		BorderSizePixel = 0,
		Selectable = false,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	if theme.Id ~= "Classic" then
		corner(b, if theme.Id == "Void" then UDim.new(0.5, 0) else theme.SmallCorner)
		stroke(b, c.StrokeDim, 1, 0, theme.LineJoin)
	end
	local icon = Icons.Create(iconName, if theme.Id == "Classic" then c.Text else c.Accent, math.floor(size * 0.5))
	icon.Parent = b
	return b
end

function UIKit.Cycle(theme: Theme, props: Props): { Root: TextButton, Set: (number) -> (), Get: () -> number, Value: () -> { Id: string, Text: string }, Destroy: () -> () }
	local c = theme.Colors
	local root, _, control = rowShell(theme, props, 40)
	local options = normalizeOptions(props.Options)
	local index: number = math.clamp(props.Index or 1, 1, math.max(#options, 1))
	local arrow = 28
	local left = arrowButton(theme, "ChevronLeft", arrow)
	left.Position = UDim2.new(0, arrow / 2, 0.5, -3)
	left.Parent = control
	local right = arrowButton(theme, "ChevronRight", arrow)
	right.Position = UDim2.new(1, -arrow / 2, 0.5, -3)
	right.Parent = control
	local valueLabel = UIKit.Label(theme, {
		Text = "",
		Role = "Button",
		TextSize = theme.TextSize.Small + (if theme.Id == "Classic" then 0 else 1),
		XAlign = "Center",
		Color = if theme.Id == "Classic" then c.Text else c.Accent:Lerp(WHITE, 0.35),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -3),
		Size = UDim2.new(1, -(arrow * 2 + 12), 1, -8),
		Truncate = true,
	})
	valueLabel.Parent = control
	local dots = frame({
		Name = "Dots",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, -(arrow * 2 + 12), 0, 4),
		Parent = control,
	})
	UIKit.ListLayout(dots, { Horizontal = true, Gap = 4, HAlign = Enum.HorizontalAlignment.Center })
	local dotFrames: { Frame } = {}
	if props.Dots ~= false and #options <= 12 then
		for i = 1, #options do
			local d = frame({ Name = "Dot", BackgroundTransparency = 0, BackgroundColor3 = c.StrokeDim, Size = UDim2.fromOffset(if theme.Id == "Classic" then 4 else 10, 3), LayoutOrder = i, Parent = dots })
			if theme.Id == "Void" then
				corner(d, UDim.new(0.5, 0))
			end
			table.insert(dotFrames, d)
		end
	end
	local function render()
		local opt = options[index]
		valueLabel.Text = if opt then UIKit.Upper(opt.Text) else "-"
		for i, d in dotFrames do
			d.BackgroundColor3 = if i == index then c.Accent else c.StrokeDim
		end
	end
	local function step(delta: number)
		if #options == 0 then
			return
		end
		index = ((index - 1 + delta) % #options) + 1
		Motion.Sound(theme.Sounds.Toggle)
		render()
		if props.OnChanged then
			props.OnChanged(options[index], index)
		end
	end
	render()
	Motion.On(left, "Activated", function()
		step(-1)
	end)
	Motion.On(right, "Activated", function()
		step(1)
	end)
	Motion.On(root, "Activated", function()
		step(1)
	end)
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Set = function(i: number)
			index = math.clamp(i, 1, math.max(#options, 1))
			render()
		end,
		Get = function()
			return index
		end,
		Value = function()
			return options[index]
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

function UIKit.Dropdown(theme: Theme, props: Props): { Root: TextButton, Set: (number) -> (), Get: () -> number, Open: () -> (), Close: () -> (), Destroy: () -> () }
	local c = theme.Colors
	local root, _, control = rowShell(theme, props, 40)
	local options = normalizeOptions(props.Options)
	local index: number = math.clamp(props.Index or 1, 1, math.max(#options, 1))
	local box = frame({
		Name = "Box",
		BackgroundTransparency = if theme.Id == "Void" then 0.35 else 0,
		BackgroundColor3 = if theme.Id == "Classic" then BLACK else c.PanelInset,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = control,
	})
	corner(box, theme.SmallCorner)
	stroke(box, if theme.Id == "Classic" then WHITE else c.StrokeDim, if theme.Id == "Classic" then 2 else 1, 0, theme.LineJoin)
	local valueLabel = UIKit.Label(theme, {
		Text = "",
		Role = "Body",
		TextSize = theme.TextSize.Small,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Truncate = true,
	})
	valueLabel.Parent = box
	local chevron = Icons.Create("ChevronDown", if theme.Id == "Classic" then c.Text else c.Accent, 14)
	chevron.Position = UDim2.new(1, -16, 0.5, 0)
	chevron.Parent = box
	local list = frame({
		Name = "Options",
		BackgroundTransparency = if theme.Id == "Void" then 0.15 else 0,
		BackgroundColor3 = if theme.Id == "Classic" then BLACK else c.PanelAlt,
		Position = UDim2.new(0, 0, 1, 4),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 20,
		Visible = props.Open == true,
		Parent = box,
	})
	corner(list, theme.SmallCorner)
	stroke(list, if theme.Id == "Classic" then WHITE else c.Stroke, if theme.Id == "Classic" then 2 else 1, 0, theme.LineJoin)
	UIKit.ListLayout(list, { Gap = 0 })
	UIKit.Padding(list, 4)
	local rows: { TextButton } = {}
	local function render()
		local opt = options[index]
		valueLabel.Text = if opt then opt.Text else "-"
		for i, row in rows do
			local t = row:FindFirstChild("Label") :: TextLabel?
			if t then
				t.TextColor3 = if i == index then c.Accent else c.Text
			end
			row.BackgroundTransparency = if i == index then 0.85 else 1
		end
	end
	for i, opt in options do
		local row: TextButton = make("TextButton", {
			Name = "Option" .. i,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BackgroundColor3 = c.Accent,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = i,
			ZIndex = 21,
			Parent = list,
		})
		local t = UIKit.Label(theme, { Text = opt.Text, Role = "Body", TextSize = theme.TextSize.Small, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), ZIndex = 22 })
		t.Parent = row
		table.insert(rows, row)
		Motion.On(row, "Activated", function()
			index = i
			list.Visible = false
			render()
			if props.OnChanged then
				props.OnChanged(options[index], index)
			end
		end)
	end
	render()
	Motion.On(root, "Activated", function()
		list.Visible = not list.Visible
		Motion.Sound(theme.Sounds.Open)
	end)
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Set = function(i: number)
			index = math.clamp(i, 1, math.max(#options, 1))
			render()
		end,
		Get = function()
			return index
		end,
		Open = function()
			list.Visible = true
		end,
		Close = function()
			list.Visible = false
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- tabs --------------------------------------------------------------------------------------------
function UIKit.Tabs(theme: Theme, props: Props): { Root: Frame, Select: (string) -> (), Selected: () -> string, Destroy: () -> () }
	local c = theme.Colors
	local id = theme.Id
	local items: { { [string]: any } } = props.Items or {}
	local h: number = props.Height or 44
	local selectedId: string = props.Selected or (items[1] and items[1].Id) or ""
	local root = frame({ Name = "Tabs", Size = UDim2.new(1, 0, 0, h) })
	local row = frame({ Name = "Row", Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root })
	local layout = UIKit.ListLayout(row, { Horizontal = true, Gap = if id == "Void" then 4 else (if id == "Fell" then 6 else 2), VAlign = Enum.VerticalAlignment.Center })
	layout.HorizontalFlex = Enum.UIFlexAlignment.Fill
	if id == "Classic" then
		frame({ Name = "Base", BackgroundTransparency = 0, BackgroundColor3 = c.Stroke, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), Parent = root })
	elseif id == "Royal" then
		local base = frame({ Name = "Base", BackgroundTransparency = 0, BackgroundColor3 = c.Stroke, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), Parent = root })
		gradient(base, nil, nseq({ { 0, 1 }, { 0.1, 0.5 }, { 0.9, 0.5 }, { 1, 1 } }), 0)
	elseif id == "Void" then
		local bg = frame({ Name = "Track", BackgroundTransparency = 0.45, BackgroundColor3 = c.PanelInset, Size = UDim2.fromScale(1, 1), Parent = root })
		corner(bg, UDim.new(0.5, 0))
		stroke(bg, c.StrokeDim, 1, 0.2)
		UIKit.Padding(row, 4)
	end
	local tabs: { [string]: { root: TextButton, label: TextLabel, bar: Frame?, fill: Frame?, cursor: Frame?, icon: Frame?, iconName: string? } } = {}
	local function render()
		for tabId, t in tabs do
			local on = tabId == selectedId
			if id == "Classic" then
				t.label.TextColor3 = if on then c.Selected else c.Text
				if t.cursor then
					t.cursor.Visible = on
				end
			elseif id == "Royal" then
				t.label.TextColor3 = if on then c.Hover else c.TextDim
				if t.bar then
					t.bar.Visible = on
				end
			elseif id == "Void" then
				if t.fill then
					t.fill.Visible = on
				end
				t.label.TextColor3 = if on then c.TextInverse else c.TextDim
			else
				if t.fill then
					t.fill.BackgroundColor3 = if on then c.Accent else c.PanelAlt
				end
				t.label.TextColor3 = if on then c.Text else c.TextDim
			end
		end
	end
	for i, item in items do
		local tab: TextButton = make("TextButton", {
			Name = "Tab_" .. tostring(item.Id),
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Selectable = true,
			Size = UDim2.new(0, 60, 1, 0),
			LayoutOrder = i,
			Parent = row,
		})
		tab.SelectionImageObject = frame({ Name = "NoSelectionBox" })
		local entry: { root: TextButton, label: TextLabel, bar: Frame?, fill: Frame?, cursor: Frame?, icon: Frame?, iconName: string? } = { root = tab, label = nil :: any }
		if id == "Void" then
			local fill = frame({ Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), Parent = tab })
			corner(fill, UDim.new(0.5, 0))
			gradient(fill, theme.Gradients.Accent, nil, 0)
			entry.fill = fill
		elseif id == "Fell" then
			local clip, fill = blade(h, theme.Slant, c.PanelAlt)
			clip.Parent = tab
			stroke(fill, c.StrokeDim, 1, 0, Enum.LineJoinMode.Miter)
			entry.fill = fill
		elseif id == "Royal" then
			local bar = frame({ Name = "Bar", BackgroundTransparency = 0, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.7, 0, 0, 3), ZIndex = 3, Parent = tab })
			gradient(bar, theme.Gradients.Accent, nil, 0)
			entry.bar = bar
		end
		local text = UIKit.Upper(tostring(item.Text or item.Id))
		local label = UIKit.Label(theme, {
			Text = text,
			Role = "Button",
			TextSize = if id == "Classic" then theme.TextSize.Small + 1 else theme.TextSize.Button - 3,
			XAlign = "Center",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		})
		label.Parent = tab
		if id == "Classic" then
			local heart = UIKit.Heart(c.SoulRed, 14)
			heart.AnchorPoint = Vector2.new(1, 0.5)
			heart.Position = UDim2.new(0.5, -(#text * (theme.TextSize.Small + 1)) / 2 - 8, 0.5, 0)
			heart.Visible = false
			heart.Parent = tab
			entry.cursor = heart
		end
		entry.label = label
		tabs[tostring(item.Id)] = entry
		Motion.On(tab, "Activated", function()
			if selectedId ~= tostring(item.Id) then
				selectedId = tostring(item.Id)
				Motion.Sound(theme.Sounds.Toggle)
				render()
				if props.OnChanged then
					props.OnChanged(selectedId)
				end
			end
		end)
	end
	render()
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Select = function(tabId: string)
			selectedId = tabId
			render()
		end,
		Selected = function()
			return selectedId
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- scrolling containers -----------------------------------------------------------------------------
local function scrolling(theme: Theme, props: Props): ScrollingFrame
	local c = theme.Colors
	local sf: ScrollingFrame = make("ScrollingFrame", {
		Name = props.Name or "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = if props.Horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
		ScrollingDirection = if props.Horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y,
		ScrollBarThickness = if props.ScrollBar == false then 0 else (if theme.Id == "Classic" then 6 else 4),
		ScrollBarImageColor3 = if theme.Id == "Classic" then WHITE else c.Accent,
		ScrollBarImageTransparency = if theme.Id == "Classic" then 0 else 0.3,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Selectable = false,
	})
	return sf
end

function UIKit.List(theme: Theme, props: Props): { Root: ScrollingFrame, Content: ScrollingFrame, Add: (Instance) -> (), Clear: () -> (), Destroy: () -> () }
	local sf = scrolling(theme, props)
	UIKit.ListLayout(sf, { Horizontal = props.Horizontal, Gap = props.Gap or 8, HAlign = props.HAlign })
	local inset: number = props.Inset or 4
	UIKit.Padding(sf, inset, inset, inset + (if props.ScrollBar == false then 0 else 6), inset)
	local count = 0
	applyBase(sf, props)
	finish(sf, props)
	return {
		Root = sf,
		Content = sf,
		Add = function(inst: Instance)
			count += 1
			if inst:IsA("GuiObject") and inst.LayoutOrder == 0 then
				inst.LayoutOrder = count
			end
			inst.Parent = sf
		end,
		Clear = function()
			for _, child in sf:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			count = 0
		end,
		Destroy = function()
			sf:Destroy()
		end,
	}
end

function UIKit.Grid(theme: Theme, props: Props): { Root: GuiObject, Content: GuiObject, Add: (Instance) -> (), Clear: () -> (), Destroy: () -> () }
	local container: GuiObject = if props.Scroll then scrolling(theme, props) else frame({ Name = props.Name or "Grid", Size = UDim2.fromScale(1, 1) })
	make("UIGridLayout", {
		CellSize = props.CellSize or UDim2.fromOffset(64, 64),
		CellPadding = props.CellPadding or UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = props.HAlign or Enum.HorizontalAlignment.Left,
		FillDirectionMaxCells = props.MaxColumns or 0,
		Parent = container,
	})
	if props.Inset then
		UIKit.Padding(container, props.Inset)
	end
	local count = 0
	applyBase(container, props)
	finish(container, props)
	return {
		Root = container,
		Content = container,
		Add = function(inst: Instance)
			count += 1
			if inst:IsA("GuiObject") and inst.LayoutOrder == 0 then
				inst.LayoutOrder = count
			end
			inst.Parent = container
		end,
		Clear = function()
			for _, child in container:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			count = 0
		end,
		Destroy = function()
			container:Destroy()
		end,
	}
end

-- cards -------------------------------------------------------------------------------------------
function UIKit.Card(theme: Theme, props: Props): { Root: TextButton, Portrait: Frame, SetSelected: (boolean) -> (), SetLocked: (boolean) -> (), Destroy: () -> () }
	local c = theme.Colors
	local id = theme.Id
	local kitColor: Color3 = props.Color or c.Accent
	local root: TextButton = make("TextButton", {
		Name = "Card_" .. tostring(props.Name),
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
		Size = UDim2.fromOffset(190, 280),
	})
	root.SelectionImageObject = frame({ Name = "NoSelectionBox" })
	local panel = UIKit.Panel(theme, { Size = UDim2.fromScale(1, 1), Padding = 10, Ornaments = id ~= "Royal", Variant = "Default" })
	panel.Root.ZIndex = 1
	panel.Root.Parent = root
	-- portrait well
	local portrait = frame({
		Name = "Portrait",
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 0.56, 0),
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = panel.Content,
	})
	corner(portrait, if id == "Void" then UDim.new(0, 10) else theme.SmallCorner)
	gradient(portrait, ColorSequence.new({
		ColorSequenceKeypoint.new(0, kitColor:Lerp(c.PanelInset, if id == "Classic" then 0.7 else 0.45)),
		ColorSequenceKeypoint.new(1, c.PanelInset),
	}), nil, 90)
	if id == "Classic" then
		stroke(portrait, c.StrokeDim, 2, 0, Enum.LineJoinMode.Miter)
	else
		stroke(portrait, kitColor, 1, 0.5)
	end
	-- radial-ish glow behind the emblem
	for k = 1, 3 do
		local g = frame({
			Name = "Halo",
			BackgroundTransparency = 0.82 + k * 0.04,
			BackgroundColor3 = kitColor,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.3 + k * 0.18, 0.3 + k * 0.18),
			ZIndex = 1,
			Parent = portrait,
		})
		make("UIAspectRatioConstraint", { AspectRatio = 1, Parent = g })
		corner(g, UDim.new(0.5, 0))
	end
	local emblem = Icons.Create(props.Icon or "Heart", kitColor:Lerp(WHITE, 0.15), UDim2.fromScale(0.62, 0.62), kitColor:Lerp(WHITE, 0.7))
	emblem.Position = UDim2.fromScale(0.5, 0.52)
	emblem.ZIndex = 2
	emblem.Parent = portrait
	if props.Role then
		local roleBadge = UIKit.Badge(theme, {
			Text = props.Role,
			Color = if props.Role == "Monster" or props.RoleMonster then c.Danger else kitColor,
			Style = "Solid",
			Height = 18,
			TextSize = if id == "Classic" then 8 else 11,
			Position = UDim2.fromOffset(6, 6),
			ZIndex = 3,
		})
		roleBadge.Parent = portrait
	end
	-- difficulty pips
	if props.Difficulty then
		local pips = frame({ Name = "Difficulty", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 8), Size = UDim2.fromOffset(46, 12), ZIndex = 3, Parent = portrait })
		UIKit.ListLayout(pips, { Horizontal = true, Gap = 3, HAlign = Enum.HorizontalAlignment.Right })
		for i = 1, 3 do
			local on = i <= props.Difficulty
			local p: Frame
			if id == "Classic" then
				p = UIKit.Heart(if on then c.SoulRed else c.StrokeDim, 12)
				p.AnchorPoint = Vector2.new(0, 0)
				p.Position = UDim2.fromScale(0, 0)
			else
				p = frame({ Name = "Pip", BackgroundTransparency = if on then 0 else 0.4, BackgroundColor3 = if on then c.Accent2 else c.StrokeDim, Size = UDim2.fromOffset(9, 9), Rotation = if id == "Void" then 0 else 45 })
				if id == "Void" then
					corner(p, UDim.new(0.5, 0))
				end
			end
			p.LayoutOrder = i
			p.Parent = pips
		end
	end
	-- name & title
	local info = frame({ Name = "Info", Position = UDim2.new(0, 0, 0.56, 8), Size = UDim2.new(1, 0, 0.44, -8), Parent = panel.Content })
	UIKit.ListLayout(info, { Gap = 2 })
	local nameLabel = UIKit.Label(theme, {
		Text = UIKit.Upper(props.Name or ""),
		Role = "Heading",
		TextSize = if id == "Classic" then 14 else theme.TextSize.Heading - 2,
		Size = UDim2.new(1, 0, 0, if id == "Classic" then 20 else theme.TextSize.Heading + 4),
		LayoutOrder = 1,
		Scaled = true,
		MaxTextSize = if id == "Classic" then 14 else theme.TextSize.Heading - 2,
	})
	if id == "Royal" then
		nameLabel.TextColor3 = WHITE
		gradient(nameLabel, theme.Gradients.Title, nil, 90)
	end
	nameLabel.Parent = info
	if props.Title then
		local titleLabel = UIKit.Label(theme, {
			Text = props.Title,
			Role = "Subtitle",
			TextSize = if id == "Classic" then 9 else theme.TextSize.Small,
			Color = kitColor:Lerp(c.Text, 0.35),
			Size = UDim2.new(1, 0, 0, if id == "Classic" then 14 else theme.TextSize.Small + 4),
			LayoutOrder = 2,
			Truncate = true,
		})
		titleLabel.Parent = info
	end
	if props.Tags and #props.Tags > 0 then
		local tags = frame({ Name = "Tags", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3 })
		UIKit.ListLayout(tags, { Horizontal = true, Gap = 4, Wraps = true })
		for i, tag in props.Tags do
			local b = UIKit.Badge(theme, { Text = tag, Color = if tag == "KR" then c.KR else c.TextDim, Height = 18, TextSize = if id == "Classic" then 7 else 10, LayoutOrder = i })
			b.Parent = tags
		end
		tags.Parent = info
	end
	-- footer: price / lock
	local footer = frame({ Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 22), Parent = panel.Content })
	local priceLabel: TextLabel? = nil
	if props.Price then
		local coin = Icons.Create("Gold", c.Gold, 16)
		coin.AnchorPoint = Vector2.new(0, 0.5)
		coin.Position = UDim2.fromScale(0, 0.5)
		coin.Parent = footer
		priceLabel = UIKit.Label(theme, {
			Text = L("common.gold", props.Price),
			Role = "Number",
			TextSize = theme.TextSize.Small,
			Color = c.Gold,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -22, 1, 0),
		})
		;(priceLabel :: TextLabel).Parent = footer
	end
	-- lock veil
	local veil = frame({
		Name = "Lock",
		BackgroundTransparency = 0.35,
		BackgroundColor3 = c.Overlay,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Visible = props.Locked == true,
		Parent = root,
	})
	corner(veil, theme.CornerRadius)
	local lockIcon = Icons.Create("Lock", c.TextDim, 34)
	lockIcon.Position = UDim2.fromScale(0.5, 0.36)
	lockIcon.ZIndex = 21
	lockIcon.Parent = veil
	local lockText = UIKit.Label(theme, {
		Text = UIKit.Upper(L("common.locked")),
		Role = "Caption",
		Tone = "Dim",
		XAlign = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = 21,
	})
	lockText.Parent = veil
	-- selection frame
	local select = frame({
		Name = "Selected",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		ZIndex = 22,
		Visible = props.Selected == true,
		Parent = root,
	})
	corner(select, UDim.new(theme.CornerRadius.Scale, theme.CornerRadius.Offset + 4))
	local selStroke = stroke(select, if id == "Classic" then c.Selected else c.Accent, if id == "Classic" then 3 else 2, 0, theme.LineJoin)
	if id == "Royal" then
		gradient(selStroke, theme.Gradients.Stroke, nil, 35)
	end
	local cursor = UIKit.Cursor(theme)
	cursor.AnchorPoint = Vector2.new(0.5, 1)
	cursor.Position = UDim2.new(0.5, 0, 0, -6)
	cursor.Rotation = if theme.Cursor.Style == "Chevron" then 90 else 0
	cursor.ZIndex = 23
	cursor.Parent = select
	if theme.Cursor.Style == "Chevron" then
		cursor:ClearAllChildren()
		local down = Icons.Create("ChevronDown", theme.Cursor.Color, UDim2.fromScale(1, 1))
		down.Parent = cursor
		cursor.Rotation = 0
	end
	local hovering = false
	Motion.Hover(root, function()
		hovering = true
		select.Visible = true
		Motion.Sound(theme.Sounds.Hover)
	end, function()
		hovering = false
		select.Visible = props.Selected == true
	end)
	Motion.On(root, "Activated", function()
		if props.OnActivated then
			Motion.Sound(theme.Sounds.Select)
			props.OnActivated()
		end
	end)
	if props.State == "Hover" then
		select.Visible = true
	end
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Portrait = portrait,
		SetSelected = function(v: boolean)
			props.Selected = v
			select.Visible = v or hovering
		end,
		SetLocked = function(v: boolean)
			veil.Visible = v
		end,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- viewport ----------------------------------------------------------------------------------------
function UIKit.Viewport(theme: Theme, props: Props): { Root: Frame, Viewport: ViewportFrame, Camera: Camera, SetModel: (Model?) -> (), Destroy: () -> () }
	local c = theme.Colors
	local tint: Color3 = props.Color or c.Accent
	local root = frame({ Name = props.Name or "Avatar", BackgroundTransparency = 0, BackgroundColor3 = WHITE, Size = UDim2.fromOffset(240, 240), ClipsDescendants = true })
	corner(root, theme.CornerRadius)
	gradient(root, ColorSequence.new({
		ColorSequenceKeypoint.new(0, tint:Lerp(c.PanelInset, 0.55)),
		ColorSequenceKeypoint.new(1, c.PanelInset),
	}), nil, 90)
	local floor = frame({
		Name = "FloorGlow",
		BackgroundTransparency = 0.7,
		BackgroundColor3 = tint,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.7, 0.1),
		ZIndex = 1,
		Parent = root,
	})
	corner(floor, UDim.new(0.5, 0))
	local vpf: ViewportFrame = make("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Ambient = props.Ambient or Color3.fromRGB(150, 150, 165),
		LightColor = props.LightColor or Color3.fromRGB(255, 244, 230),
		LightDirection = props.LightDirection or Vector3.new(-0.6, -1, -0.4),
		ZIndex = 2,
		Parent = root,
	})
	local camera: Camera = make("Camera", {
		Name = "Camera",
		FieldOfView = props.FieldOfView or 32,
		CFrame = props.CameraCFrame or CFrame.lookAt(Vector3.new(0, 3.2, 11), Vector3.new(0, 2.6, 0)),
	})
	camera.Parent = vpf
	pcall(function()
		vpf.CurrentCamera = camera
	end)
	local current: Model? = nil
	local function setModel(model: Model?)
		if current then
			current:Destroy()
			current = nil
		end
		if model then
			local world = vpf:FindFirstChildOfClass("WorldModel")
			model.Parent = world or vpf
			current = model
		end
	end
	if props.Model then
		setModel(props.Model)
	end
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Viewport = vpf,
		Camera = camera,
		SetModel = setModel,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

-- overlays ----------------------------------------------------------------------------------------
function UIKit.Tooltip(theme: Theme, props: Props): Frame
	local c = theme.Colors
	local width: number = props.Width or 300
	local panel = UIKit.Panel(theme, {
		Name = "Tooltip",
		Size = UDim2.fromOffset(width, 0),
		Padding = 12,
		Variant = if theme.Id == "Void" then "Glass" else "Alt",
		Ornaments = false,
		Layout = "Vertical",
		Gap = 6,
		AutoSize = "Y",
	})
	if props.Title then
		local row = frame({ Name = "TitleRow", Size = UDim2.new(1, 0, 0, theme.TextSize.Heading + 6), LayoutOrder = 1, Parent = panel.Content })
		local x = 0
		if props.Icon then
			local icon = Icons.Create(props.Icon, props.IconColor or c.Accent, theme.TextSize.Heading + 4)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.fromScale(0, 0.5)
			icon.Parent = row
			x = theme.TextSize.Heading + 12
		end
		local t = UIKit.Label(theme, { Text = UIKit.Upper(props.Title), Role = "Heading", TextSize = theme.TextSize.Heading - 4, Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x, 1, 0), Color = if theme.Id == "Royal" then c.Hover else c.Text })
		t.Parent = row
	end
	if props.Tags then
		local tags = frame({ Name = "Tags", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, Parent = panel.Content })
		UIKit.ListLayout(tags, { Horizontal = true, Gap = 4 })
		for i, tag in props.Tags do
			local b = UIKit.Badge(theme, { Text = tag, Color = if tag == "KR" then c.KR else c.Accent, Height = 18, TextSize = if theme.Id == "Classic" then 7 else 10, LayoutOrder = i })
			b.Parent = tags
		end
	end
	if props.Text then
		local body = UIKit.Label(theme, {
			Text = props.Text,
			Role = "Body",
			TextSize = theme.TextSize.Small,
			Tone = "Dim",
			Wrap = true,
			AutoSize = "Y",
			LayoutOrder = 3,
		})
		body.Parent = panel.Content
	end
	if props.Stats then
		for i, stat in props.Stats do
			local r = UIKit.StatRow(theme, { Label = stat.Label, Value = stat.Value, Icon = stat.Icon, Height = 24, LayoutOrder = 10 + i })
			r.Parent = panel.Content
		end
	end
	applyBase(panel.Root, props)
	if props.Size == nil then
		panel.Root.Size = UDim2.fromOffset(width, 0)
	end
	return finish(panel.Root, props)
end

local TOAST_KIND: { [string]: { tone: string, icon: string } } = {
	Info = { tone = "Info", icon = "Info" },
	Success = { tone = "Success", icon = "Check" },
	Warning = { tone = "Warning", icon = "Bolt" },
	Danger = { tone = "Danger", icon = "Close" },
	Reward = { tone = "Gold", icon = "Gold" },
}

function UIKit.Toast(theme: Theme, props: Props): { Root: Frame, Destroy: () -> () }
	local c = theme.Colors
	local kind = TOAST_KIND[props.Kind or "Info"] or TOAST_KIND.Info
	local color = toneColor(theme, kind.tone)
	local width: number = props.Width or 360
	local panel = UIKit.Panel(theme, {
		Name = "Toast",
		Size = UDim2.fromOffset(width, 0),
		Padding = 10,
		Variant = if theme.Id == "Void" then "Glass" else "Default",
		Ornaments = false,
		Shadow = true,
		AutoSize = "Y",
	})
	local stripe = frame({
		Name = "Stripe",
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Size = UDim2.new(0, if theme.Id == "Classic" then 6 else 4, 1, 0),
		ZIndex = 3,
		Parent = panel.Body,
	})
	corner(stripe, theme.CornerRadius)
	local row = frame({ Name = "Row", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = panel.Content })
	local icon = Icons.Create(props.Icon or kind.icon, color, 26)
	icon.AnchorPoint = Vector2.new(0, 0)
	icon.Position = UDim2.fromOffset(4, 2)
	icon.Parent = row
	local text = UIKit.Label(theme, {
		Text = props.Text or "",
		Role = "Body",
		TextSize = theme.TextSize.Small,
		Dialogue = theme.Id == "Classic",
		Wrap = true,
		AutoSize = "Y",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -40, 0, 0),
		Color = c.Text,
	})
	text.Parent = row
	applyBase(panel.Root, props)
	if props.Size == nil then
		panel.Root.Size = UDim2.fromOffset(width, 0)
	end
	finish(panel.Root, props)
	return { Root = panel.Root, Destroy = panel.Destroy }
end

function UIKit.Modal(theme: Theme, props: Props): { Root: Frame, Panel: PanelHandle, Content: Frame, Close: () -> (), Destroy: () -> () }
	local c = theme.Colors
	local root = frame({
		Name = props.Name or "Modal",
		BackgroundTransparency = props.Dim or (if theme.Id == "Void" then 0.45 else 0.3),
		BackgroundColor3 = c.Overlay,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		ZIndex = 50,
	})
	local panel = UIKit.Panel(theme, {
		Name = "Window",
		Title = props.Title,
		TitleIcon = props.TitleIcon,
		Size = props.PanelSize or UDim2.fromOffset(560, 360),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
		Padding = props.Padding,
	})
	make("UISizeConstraint", { MaxSize = Vector2.new(math.huge, math.huge), MinSize = Vector2.new(260, 160), Parent = panel.Root })
	panel.Root.Parent = root
	local function close()
		Motion.Sound(theme.Sounds.Close)
		if props.OnClose then
			props.OnClose()
		end
	end
	local closeButton = UIKit.Button(theme, {
		Name = "Close",
		Variant = "Icon",
		Icon = "Close",
		Height = 36,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		ZIndex = 30,
		OnActivated = close,
	})
	closeButton.Root.Parent = panel.Root
	local content = panel.Content
	if props.Buttons and #props.Buttons > 0 then
		local bar = frame({
			Name = "Actions",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, theme.Button.Height),
			Parent = panel.Content,
		})
		local layout = UIKit.ListLayout(bar, { Horizontal = true, Gap = 16, HAlign = Enum.HorizontalAlignment.Right, VAlign = Enum.VerticalAlignment.Center })
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		for i, spec in props.Buttons do
			local b = UIKit.Button(theme, { Text = spec.Text, Variant = spec.Variant or "Secondary", Icon = spec.Icon, Width = spec.Width or 180, LayoutOrder = i, OnActivated = spec.OnActivated, State = spec.State })
			b.Root.Parent = bar
		end
		content = frame({ Name = "Body", Size = UDim2.new(1, 0, 1, -(theme.Button.Height + 12)), Parent = panel.Content })
	end
	applyBase(root, props)
	finish(root, props)
	return {
		Root = root,
		Panel = panel,
		Content = content,
		Close = close,
		Destroy = function()
			Motion.StopAll(root)
			root:Destroy()
		end,
	}
end

return UIKit
