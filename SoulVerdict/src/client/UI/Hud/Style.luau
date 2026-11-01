--!strict
-- Hud/Style: the shared look of every HUD piece (skin tokens + small GUI primitives) and shared helpers
-- (strings, kits, formatting). Lune-safe: no services at require time; Strings/Kits/Config are required
-- lazily from ReplicatedStorage.Shared and every builder works offline (tools/lune/dump_gui.luau).
--
--   Style.Resolve(theme, hud?) -> Skin          hud: HudStyle | "Battle" | "Modern" | nil (ThemeService.HudStyle())
--       Skin = { Theme, Hud, Id, Battle, C (colours), Font(role), Size (text sizes), Corner, BoxStroke, FillT, Upper }
--   Style.Frame(props) -> Frame                 transparent frame; props are Instance properties (+ Parent last)
--   Style.Box(skin, props) -> Frame             Battle: black fill + white miter border; Modern: rounded glass
--       props: Name, Size, Position, AnchorPoint, ZIndex, LayoutOrder, Visible, Parent, Fill, Transparency,
--              Border (Color3), Stroke (thickness), Corner (UDim), Sheen (Modern top highlight, default true)
--   Style.Text(skin, props) -> TextLabel        props: Text, Role("Label"|"Number"|"Title"|"Body"), TextSize, Color,
--       X/Y ("Left"|"Center"|"Right" / "Top"|"Center"|"Bottom"), Upper (default skin.Upper), Stroke (false = none),
--       Scaled (TextScaled, TextSize = max), Wrap, Rich, AutoX, + Name/Size/Position/AnchorPoint/ZIndex/LayoutOrder/Parent
--   Style.Bar(skin, props) -> { Root, Set(v, max?, kr?), SetColor(c), Destroy }   UIKit.Bar + white flash on loss
--   Style.Radial(props) -> { Root, Set(fraction) }  clockwise radial wipe built from two clipped UIGradients
--       props: Color, Transparency, Mode ("Remaining": covers the last `fraction` of the turn | "Filled": covers
--       the first `fraction`), Circle (round mask), ZIndex, Name, Parent
--   Style.Pips(skin, props) -> { Root, Set(value, max) }   props: Max, PipSize(Vector2), Gap, Color, Empty,
--       Shape ("Square"|"Round"|"Diamond"|"Bullet"), + Name/Position/AnchorPoint/ZIndex/Parent
--   Style.KeyCap(skin, text, height, props?) -> Frame   keyboard/gamepad hint chip ("M1" draws a mouse)
--   Style.Heart(color, size, variant?) -> Frame  pixel SOUL; variant "Whole" | "Cracked" | "Broken"
--   Style.Vignette(props) -> Frame               screen-edge gradients; props: Color, Strength, Depth, ZIndex, Name
--   Style.Glow(props) -> Frame                   layered soft halo (put it behind the element, same parent)
--   Style.Icon(name, color, size) -> Frame       Icons.Create with a safe fallback icon
--   Style.L(key, ...) / Style.Pick(localized) / Style.Language()
--   Style.Kits() / Style.Kit(id) / Style.Config() / Style.KitColor(id)
--   Style.Slots(kitId) -> { SlotInfo }           ability-bar order incl. built-ins (Block, Dash, VerdictBox)
--   Style.FormatClock(s) "m:ss" / Style.FormatCd(s) "12" | "4.2" / Style.StatusInfo(name) -> { Icon, Color, Buff }
--   Style.Tween(inst, time, props) / Style.Flash(inst, prop, from, to, time)   Motion wrappers (no-op offline)
local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)

type Theme = Themes.Theme
type HudStyle = Themes.HudStyle

export type Skin = {
	Theme: Theme,
	Hud: HudStyle,
	Id: string,
	Battle: boolean,
	C: { [string]: Color3 },
	Font: (role: string) -> Font,
	Size: { [string]: number },
	Corner: UDim,
	SmallCorner: UDim,
	BoxStroke: number,
	FillT: number,
	Upper: boolean,
}

export type SlotInfo = {
	Slot: string, -- data slot ("M1","Q",...,"F","Shift")
	Action: string, -- InputController action name
	Id: string, -- ability id, or "Block" / "Dash" / "VerdictBox"
	Icon: string,
	Name: string,
	Cooldown: number,
	Ult: boolean,
	Hold: number?, -- Hold.MaxTime
	Combo: number?,
	Ammo: number?,
	BuiltIn: boolean,
}

local Style = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Style.WHITE = WHITE
Style.BLACK = BLACK
Style.UT_ORANGE = rgb(255, 127, 39)
Style.UT_YELLOW = rgb(255, 255, 0)
Style.UT_RED = rgb(255, 0, 0)
Style.UT_MAGENTA = rgb(255, 0, 255)

-- lazy shared modules -------------------------------------------------------------------------------
local cache: { [string]: any } = {}
local function shared(name: string): any
	local hit = cache[name]
	if hit ~= nil then
		return if hit == false then nil else hit
	end
	local ok, result = pcall(function()
		local folder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		return require((folder :: any):WaitForChild(name)) :: any
	end)
	cache[name] = if ok then result else false
	return if ok then result else nil
end

function Style.Strings(): any
	return shared("Strings")
end
function Style.Kits(): any
	return shared("Kits")
end
function Style.Config(): any
	return shared("Config")
end
function Style.Shared(name: string): any
	return shared(name)
end

-- Nested shared module, e.g. Style.Require("Maps", "Registry"); nil when missing or broken (cached).
function Style.Require(...: string): any
	local path = table.concat({ ... }, "/")
	local hit = cache[path]
	if hit ~= nil then
		return if hit == false then nil else hit
	end
	local names = { ... }
	local ok, result = pcall(function()
		local node: any = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		for _, n in names do
			node = node:WaitForChild(n, 5)
		end
		return require(node) :: any
	end)
	cache[path] = if ok then result else false
	return if ok then result else nil
end

function Style.L(key: string, ...: any): string
	local s = shared("Strings")
	if s then
		local ok, text = pcall(s.L, key, ...)
		if ok and type(text) == "string" then
			return text
		end
	end
	return key
end

function Style.Pick(tbl: any): string
	if type(tbl) == "string" then
		return tbl
	end
	if type(tbl) ~= "table" then
		return ""
	end
	local s = shared("Strings")
	if s then
		return s.Pick(tbl)
	end
	return tbl.en or ""
end

function Style.Language(): string
	local s = shared("Strings")
	return if s then s.Language() else "en"
end

function Style.Kit(kitId: string?): any
	if type(kitId) ~= "string" or kitId == "" then
		return nil
	end
	local kits = shared("Kits")
	return if kits then kits.Get(kitId) else nil
end

function Style.KitColor(kitId: string?, fallback: Color3?): Color3
	local kit = Style.Kit(kitId)
	return if kit then kit.Color else (fallback or WHITE)
end

-- skin ---------------------------------------------------------------------------------------------
local function currentHud(): HudStyle
	local ok, style = pcall(function()
		local ThemeService = require(script.Parent.Parent.ThemeService) :: any
		return ThemeService.HudStyle()
	end)
	if ok and type(style) == "table" then
		return style :: HudStyle
	end
	return Themes.GetHud(nil)
end

function Style.Resolve(theme: Theme, hud: any?): Skin
	local style: HudStyle
	if type(hud) == "table" then
		style = hud :: HudStyle
	elseif type(hud) == "string" then
		style = Themes.GetHud(hud)
	else
		style = currentHud()
	end
	local battle = style.Id == "Battle"
	local hc = style.Colors
	local tc = theme.Colors
	local lang = Style.Language()
	local C: { [string]: Color3 } = {
		Text = hc.Text,
		Dim = hc.TextDim,
		Box = hc.Box,
		Fill = hc.BoxFill,
		HP = hc.HP,
		HPBack = hc.HPBack,
		KR = hc.KR,
		KRText = hc.KRText,
		Guard = hc.Guard,
		GuardBack = hc.GuardBack,
		Dodge = hc.Dodge,
		DodgeEmpty = hc.DodgeEmpty,
		Ult = hc.Ult,
		UltFull = hc.UltFull,
		Monster = hc.Monster,
		Danger = hc.Danger,
		Shadow = hc.Shadow,
		Accent = if battle then Style.UT_ORANGE else tc.Accent,
		Select = if battle then Style.UT_YELLOW else tc.Accent:Lerp(WHITE, 0.25),
		Gold = if battle then Style.UT_YELLOW else rgb(255, 214, 92),
		Good = if battle then rgb(0, 255, 0) else rgb(92, 230, 140),
		Warn = if battle then Style.UT_ORANGE else rgb(255, 170, 60),
		Muted = if battle then rgb(128, 128, 128) else rgb(120, 128, 150),
		SoulRed = Style.UT_RED,
	}
	return {
		Theme = theme,
		Hud = style,
		Id = style.Id,
		Battle = battle,
		C = C,
		Font = function(role: string): Font
			return Themes.HudFont(style, (if role == "Number" or role == "Title" or role == "Body" then role else "Label") :: any, lang)
		end,
		Size = {
			Label = style.TextSize.Label,
			Number = style.TextSize.Number,
			Title = style.TextSize.Title,
			Small = style.TextSize.Small,
			Big = style.TextSize.Big,
		},
		Corner = style.Box.Corner,
		SmallCorner = if battle then UDim.new(0, 0) else UDim.new(0, 6),
		BoxStroke = style.Box.StrokeThickness,
		FillT = style.Box.FillTransparency,
		Upper = style.Uppercase,
	}
end

-- generic builders ------------------------------------------------------------------------------------
function Style.Frame(props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(f :: any)[key] = value
			end
		end
	end
	if parent then
		f.Parent = parent
	end
	return f
end

function Style.Corner(parent: Instance, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 8)
	c.Parent = parent
	return c
end

function Style.Stroke(parent: Instance, color: Color3, thickness: number, transparency: number?, miter: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.LineJoinMode = if miter then Enum.LineJoinMode.Miter else Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Style.Gradient(parent: Instance, color: ColorSequence?, transparency: NumberSequence?, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	if color then
		g.Color = color
	end
	if transparency then
		g.Transparency = transparency
	end
	g.Rotation = rotation or 0
	g.Parent = parent
	return g
end

function Style.Seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

function Style.CSeq(a: Color3, b: Color3, mid: Color3?): ColorSequence
	if mid then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, a),
			ColorSequenceKeypoint.new(0.5, mid),
			ColorSequenceKeypoint.new(1, b),
		})
	end
	return ColorSequence.new(a, b)
end

local function applyCommon(inst: GuiObject, props: { [string]: any })
	for _, key in { "Name", "Size", "Position", "AnchorPoint", "ZIndex", "LayoutOrder", "Visible", "Rotation" } do
		if props[key] ~= nil then
			(inst :: any)[key] = props[key]
		end
	end
end

function Style.Box(skin: Skin, props: { [string]: any }): Frame
	local f = Style.Frame({ Name = "Box" })
	f.BackgroundTransparency = if props.Transparency ~= nil then props.Transparency else skin.FillT
	f.BackgroundColor3 = props.Fill or skin.C.Fill
	applyCommon(f, props)
	if skin.Battle then
		Style.Stroke(f, props.Border or skin.C.Box, props.Stroke or skin.BoxStroke, 0, true)
	else
		Style.Corner(f, props.Corner or skin.Corner)
		Style.Stroke(f, props.Border or WHITE, props.Stroke or 1.5, if props.Border then 0.35 else 0.8)
		Style.Gradient(f, Style.CSeq(WHITE, rgb(170, 176, 196)), nil, 90)
		if props.Sheen ~= false then
			local sheen = Style.Frame({
				Name = "Sheen",
				BackgroundTransparency = 0,
				BackgroundColor3 = WHITE,
				Size = UDim2.new(1, 0, 0.5, 0),
				ZIndex = f.ZIndex,
				Parent = f,
			})
			Style.Corner(sheen, props.Corner or skin.Corner)
			Style.Gradient(sheen, nil, Style.Seq({ { 0, 0.9 }, { 1, 1 } }), 90)
		end
	end
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

local ALIGN_X = { Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local ALIGN_Y = { Top = Enum.TextYAlignment.Top, Center = Enum.TextYAlignment.Center, Bottom = Enum.TextYAlignment.Bottom }

function Style.Text(skin: Skin, props: { [string]: any }): TextLabel
	local role: string = props.Role or "Label"
	local size: number = props.TextSize or skin.Size[role] or skin.Size.Label
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.FontFace = skin.Font(role)
	t.TextSize = size
	local text = tostring(props.Text or "")
	local upper = if props.Upper ~= nil then props.Upper else skin.Upper
	t.Text = if upper then UIKit.Upper(text) else text
	t.TextColor3 = props.Color or skin.C.Text
	t.TextXAlignment = ALIGN_X[props.X or "Left"] or Enum.TextXAlignment.Left
	t.TextYAlignment = ALIGN_Y[props.Y or "Center"] or Enum.TextYAlignment.Center
	t.TextWrapped = props.Wrap == true
	t.RichText = props.Rich == true
	if props.Transparency then
		t.TextTransparency = props.Transparency
	end
	t.Size = UDim2.new(1, 0, 0, size + 4)
	if props.AutoX then
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.new(0, 0, 0, size + 4)
	end
	applyCommon(t, props)
	if props.Scaled then
		t.TextScaled = true
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = math.max(1, math.floor(size))
		c.MinTextSize = math.max(1, math.min(props.MinSize or 6, math.floor(size)))
		c.Parent = t
	end
	if props.Stroke ~= false then
		local s = Instance.new("UIStroke")
		s.Color = if typeof(props.StrokeColor) == "Color3" then props.StrokeColor else BLACK
		s.Thickness = if type(props.Stroke) == "number" then props.Stroke elseif skin.Battle then 2 else 1.5
		s.Transparency = if skin.Battle then 0 else 0.35
		s.LineJoinMode = if skin.Battle then Enum.LineJoinMode.Miter else Enum.LineJoinMode.Round
		s.Parent = t
	end
	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

function Style.SetText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

function Style.Upper(skin: Skin, text: string): string
	return if skin.Upper then UIKit.Upper(text) else text
end

-- Re-colours a UIKit.Bar fill with a gradient (Modern) or a flat colour (Battle).
function Style.TintBar(skin: Skin, barRoot: Instance, color: Color3, color2: Color3?)
	local track = barRoot:FindFirstChild("Track")
	local fill = if track then track:FindFirstChild("Fill") else nil
	if not fill or not fill:IsA("Frame") then
		return
	end
	local g = fill:FindFirstChildOfClass("UIGradient")
	if skin.Battle then
		fill.BackgroundColor3 = color
		if g then
			g:Destroy()
		end
		return
	end
	fill.BackgroundColor3 = WHITE
	if not g then
		g = Instance.new("UIGradient")
		g.Parent = fill
	end
	(g :: UIGradient).Color = if color2 then Style.CSeq(color, color2) else Style.CSeq(color:Lerp(BLACK, 0.3), color:Lerp(WHITE, 0.35));
	(g :: UIGradient).Rotation = 0
end

function Style.Icon(name: string?, color: Color3, size: (number | UDim2)?): Frame
	local iconName = if name and Icons.Has(name) then name else "Star"
	return Icons.Create(iconName, color, size)
end

-- bars ------------------------------------------------------------------------------------------------
function Style.Bar(skin: Skin, props: { [string]: any }): { Root: Frame, Set: (number, number?, number?) -> (), SetColor: (Color3) -> (), Destroy: () -> () }
	local p = table.clone(props)
	p.Hud = skin.Hud
	local bar = UIKit.Bar(skin.Theme, p)
	local track = bar.Root:FindFirstChild("Track") :: Frame?
	local flash: Frame? = nil
	if track and not props.Segments then
		flash = Style.Frame({
			Name = "Flash",
			BackgroundTransparency = 1,
			BackgroundColor3 = WHITE,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = track,
		})
		Style.Corner(flash :: Frame, skin.Hud.Bar.Corner)
	end
	local last: number = props.Value or 0
	return {
		Root = bar.Root,
		Set = function(v: number, max: number?, kr: number?)
			if flash and v < last - 0.5 then
				flash.BackgroundTransparency = 0.35
				Motion.Tween(flash, { Time = 0.35, Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out }, { BackgroundTransparency = 1 })
			end
			last = v
			bar.Set(v, max, kr)
		end,
		SetColor = bar.SetColor,
		Destroy = bar.Destroy,
	}
end

local SEQ_CW = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(0.502, 0),
	NumberSequenceKeypoint.new(1, 0),
})
local SEQ_CCW = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.498, 0),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- Radial wipe. The parent should be square. Each half is a clipping frame holding a full-size fill whose
-- UIGradient has a hard transparency edge through the centre; rotating the gradient sweeps that edge.
function Style.Radial(props: { [string]: any }): { Root: Frame, Set: (number) -> () }
	local z: number = props.ZIndex or 1
	local root = Style.Frame({ Name = props.Name or "Radial", Size = UDim2.fromScale(1, 1), ZIndex = z })
	local mode: string = props.Mode or "Remaining"
	local function half(right: boolean): (Frame, UIGradient)
		local clip = Style.Frame({
			Name = if right then "Right" else "Left",
			Position = UDim2.fromScale(if right then 0.5 else 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			ClipsDescendants = true,
			ZIndex = z,
			Parent = root,
		})
		local fill = Style.Frame({
			Name = "Fill",
			BackgroundTransparency = props.Transparency or 0,
			BackgroundColor3 = props.Color or BLACK,
			Position = UDim2.fromScale(if right then -1 else 0, 0),
			Size = UDim2.fromScale(2, 1),
			ZIndex = z,
			Parent = clip,
		})
		if props.Circle then
			Style.Corner(fill, UDim.new(0.5, 0))
		elseif props.Corner then
			Style.Corner(fill, props.Corner)
		end
		local g = Style.Gradient(fill, nil, if mode == "Remaining" then SEQ_CW else SEQ_CCW, 0)
		return clip, g
	end
	local rightClip, rightGrad = half(true)
	local leftClip, leftGrad = half(false)
	local function set(fraction: number)
		local f = math.clamp(fraction, 0, 1)
		if f <= 0.001 then
			rightClip.Visible = false
			leftClip.Visible = false
			return
		end
		if mode == "Remaining" then
			local a = (1 - f) * 360
			rightClip.Visible = a < 180
			rightGrad.Rotation = a
			leftClip.Visible = true
			leftGrad.Rotation = math.max(a, 180)
		else
			local b = f * 360
			rightClip.Visible = true
			rightGrad.Rotation = math.min(b, 180)
			leftClip.Visible = b > 180
			leftGrad.Rotation = b
		end
	end
	set(props.Value or 0)
	if props.Parent then
		root.Parent = props.Parent
	end
	return { Root = root, Set = set }
end

-- pips (dash charges, dodges, combo, ammo) -------------------------------------------------------------
function Style.Pips(skin: Skin, props: { [string]: any }): { Root: Frame, Set: (number, number?) -> () }
	local pipSize: Vector2 = props.PipSize or Vector2.new(12, 12)
	local gap: number = props.Gap or 4
	local shape: string = props.Shape or (if skin.Battle then "Square" else "Round")
	local color: Color3 = props.Color or skin.C.Text
	local empty: Color3 = props.Empty or skin.C.DodgeEmpty
	local z: number = props.ZIndex or 1
	local root = Style.Frame({ Name = props.Name or "Pips", ZIndex = z })
	applyCommon(root, props)
	local pips: { Frame } = {}
	local fills: { Frame } = {}
	local max = 0
	local function build(n: number)
		for _, pip in pips do
			pip:Destroy()
		end
		table.clear(pips)
		table.clear(fills)
		max = n
		root.Size = UDim2.fromOffset(math.max(0, n * pipSize.X + (n - 1) * gap), pipSize.Y)
		for i = 1, n do
			local pip = Style.Frame({
				Name = "Pip" .. i,
				BackgroundTransparency = 0,
				BackgroundColor3 = empty,
				Position = UDim2.fromOffset((i - 1) * (pipSize.X + gap), 0),
				Size = UDim2.fromOffset(pipSize.X, pipSize.Y),
				ZIndex = z,
				Parent = root,
			})
			local fill = Style.Frame({
				Name = "Fill",
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				Size = UDim2.fromScale(1, 1),
				ZIndex = z,
				Parent = pip,
			})
			if shape == "Diamond" then
				pip.Rotation = 45
				pip.Size = UDim2.fromOffset(pipSize.X * 0.72, pipSize.Y * 0.72)
				pip.Position = UDim2.fromOffset((i - 1) * (pipSize.X + gap) + pipSize.X * 0.14, pipSize.Y * 0.14)
				if not skin.Battle then
					Style.Corner(pip, UDim.new(0, 2))
					Style.Corner(fill, UDim.new(0, 2))
				end
			elseif shape == "Round" then
				Style.Corner(pip, UDim.new(0.5, 0))
				Style.Corner(fill, UDim.new(0.5, 0))
			elseif shape == "Bullet" then
				Style.Corner(pip, UDim.new(0.5, 0))
				Style.Corner(fill, UDim.new(0.5, 0))
				Style.Frame({
					Name = "Tip",
					BackgroundTransparency = 0.35,
					BackgroundColor3 = WHITE,
					Position = UDim2.fromScale(0.2, 0.08),
					Size = UDim2.fromScale(0.6, 0.22),
					ZIndex = z,
					Parent = fill,
				})
			end
			if skin.Battle and shape ~= "Diamond" then
				Style.Stroke(pip, BLACK, 1, 0.2, true)
			end
			table.insert(pips, pip)
			table.insert(fills, fill)
		end
	end
	local function set(value: number, newMax: number?)
		local n = math.max(0, math.floor((newMax or max) + 0.5))
		if n ~= max or #pips ~= n then
			build(n)
		end
		for i, fill in fills do
			local amount = math.clamp(value - (i - 1), 0, 1)
			if amount >= 0.999 then
				fill.Visible = true
				fill.BackgroundTransparency = 0
				fill.Size = UDim2.fromScale(1, 1)
			elseif amount > 0 then
				fill.Visible = true
				fill.BackgroundTransparency = 0.45
				if shape == "Bullet" then
					fill.Size = UDim2.fromScale(1, amount)
					fill.Position = UDim2.fromScale(0, 1 - amount)
				else
					fill.Size = UDim2.fromScale(amount, 1)
				end
			else
				fill.Visible = false
			end
		end
	end
	set(props.Value or 0, props.Max or 0)
	if props.Parent then
		root.Parent = props.Parent
	end
	return { Root = root, Set = set }
end

-- key caps ----------------------------------------------------------------------------------------------
local MOUSE_KEYS = { M1 = true, LMB = true, MouseButton1 = true, MB1 = true }

function Style.KeyCap(skin: Skin, text: string, height: number, props: { [string]: any }?): Frame
	local h = height
	local label = if MOUSE_KEYS[text] then "" else text
	local chars = utf8.len(label) or #label
	local w = math.max(h, math.ceil(chars * h * (if skin.Battle then 0.5 else 0.42) + h * 0.5))
	local cap = Style.Frame({
		Name = "Key",
		BackgroundTransparency = if skin.Battle then 0 else 0.15,
		BackgroundColor3 = if skin.Battle then BLACK else rgb(16, 18, 28),
		Size = UDim2.fromOffset(w, h),
	})
	if skin.Battle then
		Style.Stroke(cap, WHITE, math.max(1, math.floor(h / 10)), 0, true)
	else
		Style.Corner(cap, UDim.new(0, math.floor(h * 0.28)))
		Style.Stroke(cap, WHITE, 1, 0.55)
	end
	if MOUSE_KEYS[text] then
		local icon = Icons.Create("Mouse", skin.C.Text, math.floor(h * 0.8))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = cap
	else
		Style.Text(skin, {
			Name = "Label",
			Text = label,
			Role = "Label",
			TextSize = math.max(6, math.floor(h * (if skin.Battle then 0.5 else 0.6))),
			X = "Center",
			Stroke = false,
			Size = UDim2.fromScale(1, 1),
			Parent = cap,
		})
	end
	if props then
		applyCommon(cap, props)
		if props.Parent then
			cap.Parent = props.Parent
		end
	end
	return cap
end

-- pixel SOUL hearts ---------------------------------------------------------------------------------------
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
local CRACK = { 5, 5, 4, 5, 6, 5, 4, 5, 5, 5 } -- zig-zag crack column per row

function Style.Heart(color: Color3, size: number, variant: string?): Frame
	local kind = variant or "Whole"
	local root = Style.Frame({
		Name = "Soul",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, math.round(size * 10 / 11)),
	})
	local function px(x0: number, x1: number, row: number, dx: number, dy: number)
		if x1 < x0 then
			return
		end
		Style.Frame({
			Name = "Px",
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			Position = UDim2.fromScale((x0 + dx) / 11, (row - 1 + dy) / 10),
			Size = UDim2.fromScale((x1 - x0 + 1) / 11, 1 / 10 + 0.012),
			Parent = root,
		})
	end
	for row, runs in HEART_ROWS do
		local c = CRACK[row]
		for _, run in runs do
			if kind == "Whole" then
				px(run[1], run[2], row, 0, 0)
			else
				local spread = if kind == "Broken" then 0.9 else 0
				px(run[1], math.min(run[2], c - 1), row, -spread, 0)
				px(math.max(run[1], c + 1), run[2], row, spread, if kind == "Broken" then 0.35 else 0)
			end
		end
	end
	return root
end

-- vignette & glow ---------------------------------------------------------------------------------------
function Style.Vignette(props: { [string]: any }): Frame
	local color: Color3 = props.Color or rgb(255, 0, 0)
	local strength: number = props.Strength or 0.6
	local depth: number = props.Depth or 0.2
	local z: number = props.ZIndex or 1
	local root = Style.Frame({ Name = props.Name or "Vignette", Size = UDim2.fromScale(1, 1), ZIndex = z })
	local seq = Style.Seq({ { 0, 1 - strength }, { 1, 1 } })
	local edges = {
		{ "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, depth), 90 },
		{ "Bottom", UDim2.fromScale(0, 1 - depth), UDim2.fromScale(1, depth), 270 },
		{ "Left", UDim2.fromScale(0, 0), UDim2.fromScale(depth * 0.6, 1), 0 },
		{ "Right", UDim2.fromScale(1 - depth * 0.6, 0), UDim2.fromScale(depth * 0.6, 1), 180 },
	}
	for _, e in edges do
		local f = Style.Frame({
			Name = e[1],
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			Position = e[2],
			Size = e[3],
			ZIndex = z,
			Parent = root,
		})
		Style.Gradient(f, nil, seq, e[4])
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- A soft halo: three nested rounded frames of falling opacity (no images). Same parent as the target,
-- lower ZIndex; props: Color, Size (UDim2 of the target), Position, AnchorPoint, Spread, Corner, Strength.
function Style.Glow(props: { [string]: any }): Frame
	local spread: number = props.Spread or 10
	local color: Color3 = props.Color or WHITE
	local strength: number = props.Strength or 1
	local root = Style.Frame({ Name = props.Name or "Glow", ZIndex = props.ZIndex or 1 })
	applyCommon(root, props)
	for i = 3, 1, -1 do
		local grow = spread * i / 3
		local layer = Style.Frame({
			Name = "Layer" .. i,
			BackgroundTransparency = 1 - (0.16 + 0.1 * (3 - i)) * strength,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, grow * 2, 1, grow * 2),
			ZIndex = props.ZIndex or 1,
			Parent = root,
		})
		Style.Corner(layer, props.Corner or UDim.new(0, math.floor(grow + 6)))
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- motion helpers (no-ops offline: Motion applies end values immediately) ------------------------------
function Style.Tween(inst: Instance, time: number, props: { [string]: any }, easing: Enum.EasingStyle?)
	Motion.Tween(inst, { Time = time, Style = easing or Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out }, props)
end

function Style.Live(): boolean
	return Motion.IsLive()
end

-- formatting --------------------------------------------------------------------------------------------
function Style.FormatClock(seconds: number): string
	local s = math.max(0, math.ceil(seconds - 0.001))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Style.FormatCd(seconds: number): string
	if seconds >= 9.95 then
		return tostring(math.ceil(seconds - 0.001))
	end
	return string.format("%.1f", math.max(0, seconds))
end

function Style.FormatHp(skin: Skin, hp: number, max: number): string
	local h = math.max(0, math.floor(hp + 0.5))
	local m = math.max(0, math.floor(max + 0.5))
	if skin.Battle then
		return string.format("%02d / %02d", h, m)
	end
	return string.format("%d / %d", h, m)
end

-- statuses -----------------------------------------------------------------------------------------------
local STATUS: { [string]: { Icon: string, Color: Color3, Buff: boolean, Order: number } } = {
	Stunned = { Icon = "Sparkle", Color = rgb(255, 230, 90), Buff = false, Order = 1 },
	Silenced = { Icon = "Lock", Color = rgb(190, 150, 255), Buff = false, Order = 2 },
	Rooted = { Icon = "Chain", Color = rgb(190, 190, 200), Buff = false, Order = 3 },
	Slowed = { Icon = "Shoe", Color = rgb(110, 170, 255), Buff = false, Order = 4 },
	Blue = { Icon = "BlueSoul", Color = rgb(0, 120, 255), Buff = false, Order = 5 },
	Marked = { Icon = "Target", Color = rgb(255, 80, 80), Buff = false, Order = 6 },
	Exhausted = { Icon = "Moon", Color = rgb(255, 170, 60), Buff = false, Order = 7 },
	Boxed = { Icon = "Box", Color = WHITE, Buff = false, Order = 8 },
	Rage = { Icon = "Rage", Color = rgb(255, 60, 60), Buff = true, Order = 10 },
	DamageUp = { Icon = "Swords", Color = rgb(255, 150, 60), Buff = true, Order = 11 },
	DamageDown = { Icon = "Shield", Color = rgb(110, 230, 150), Buff = true, Order = 12 },
	Shielded = { Icon = "Shield", Color = rgb(255, 214, 92), Buff = true, Order = 13 },
	Hasted = { Icon = "Dash", Color = rgb(90, 230, 255), Buff = true, Order = 14 },
	Invulnerable = { Icon = "Shield", Color = WHITE, Buff = true, Order = 15 },
	Invisible = { Icon = "Stealth", Color = rgb(120, 230, 230), Buff = true, Order = 16 },
	SecondWind = { Icon = "Heart", Color = rgb(255, 255, 255), Buff = true, Order = 17 },
	Surge = { Icon = "Star", Color = rgb(255, 214, 92), Buff = true, Order = 18 },
	Undodgeable = { Icon = "Eye", Color = rgb(255, 120, 120), Buff = true, Order = 19 },
	Determined = { Icon = "Heart", Color = rgb(255, 40, 40), Buff = true, Order = 20 },
	StealthStrike = { Icon = "Knife", Color = rgb(120, 230, 230), Buff = true, Order = 21 },
	KRBoost = { Icon = "Skull", Color = rgb(255, 0, 255), Buff = true, Order = 22 },
}
-- statuses that never get an icon (too short-lived or shown elsewhere)
Style.HIDDEN_STATUS = { IFrames = true }

function Style.StatusInfo(name: string): { Icon: string, Color: Color3, Buff: boolean, Order: number }
	return STATUS[name] or { Icon = "Info", Color = rgb(200, 200, 200), Buff = false, Order = 50 }
end

-- ability-bar slots ---------------------------------------------------------------------------------------
local HUMAN_ORDER = { "M1", "Q", "E", "F", "Shift", "R" }
local MONSTER_ORDER = { "M1", "Q", "E", "R", "T", "Shift", "F", "G" }

function Style.Slots(kitId: string?): { SlotInfo }
	local kit = Style.Kit(kitId)
	local out: { SlotInfo } = {}
	if not kit then
		return out
	end
	local monster = kit.Role == "Monster"
	local config = Style.Config()
	for _, slot in (if monster then MONSTER_ORDER else HUMAN_ORDER) do
		local ability = nil
		for _, a in kit.Abilities do
			if a.Slot == slot then
				ability = a
				break
			end
		end
		if ability then
			table.insert(out, {
				Slot = slot,
				Action = slot,
				Id = ability.Id,
				Icon = ability.Icon,
				Name = Style.Pick(ability.Name),
				Cooldown = ability.Cooldown,
				Ult = ability.Ult == true,
				Hold = if ability.Hold then ability.Hold.MaxTime else nil,
				Combo = ability.Combo,
				Ammo = if ability.Numbers and type(ability.Numbers.Ammo) == "number" then ability.Numbers.Ammo else nil,
				BuiltIn = false,
			})
		elseif slot == "F" and monster then
			table.insert(out, {
				Slot = "F",
				Action = "F",
				Id = "VerdictBox",
				Icon = "Box",
				Name = Style.L("hud.slot.verdict"),
				Cooldown = if config then config.VerdictBox.Cooldown else 40,
				Ult = false,
				BuiltIn = true,
			})
		elseif slot == "F" then
			table.insert(out, { Slot = "F", Action = "F", Id = "Block", Icon = "Shield", Name = Style.L("hud.slot.block"), Cooldown = 0, Ult = false, BuiltIn = true })
		elseif slot == "Shift" and not monster then
			table.insert(out, {
				Slot = "Shift",
				Action = "Shift",
				Id = "Dash",
				Icon = "Dash",
				Name = Style.L("hud.slot.dash"),
				Cooldown = if config then config.Human.DashRecharge else 2.8,
				Ult = false,
				BuiltIn = true,
			})
		end
	end
	return out
end

-- piece scaffolding ----------------------------------------------------------------------------------------
export type Layout = { Canvas: Vector2, Phone: boolean, Compact: boolean, Scale: number }

-- Common start of every piece's Create(theme, deps): skin (deps.Skin or resolved from deps.Hud), layout
-- (deps.Layout or a 1600x900 desktop canvas) and a full-canvas transparent root frame.
function Style.Context(theme: Theme, deps: any, name: string): (Skin, Layout, Frame)
	local d = if type(deps) == "table" then deps else {}
	local skin: Skin = d.Skin or Style.Resolve(theme, d.Hud)
	local layout: Layout = d.Layout or { Canvas = Vector2.new(1600, 900), Phone = false, Compact = false, Scale = 1 }
	local root = Style.Frame({ Name = name, Size = UDim2.fromScale(1, 1) })
	return skin, layout, root
end

-- The snapshot a piece renders right after Create: deps.Snapshot, else the mock scenario deps.Scenario.
function Style.Initial(deps: any, default: string): { [string]: any }?
	local d = if type(deps) == "table" then deps else {}
	if d.Snapshot ~= nil then
		return d.Snapshot
	end
	if d.Live then
		return nil
	end
	local Mock = require(script.Parent.Mock) :: any
	return Mock.Scenario(d.Scenario or default)
end

-- default key labels when InputController is absent (previews / early boot)
local DEFAULT_KEYS = { M1 = "M1", Q = "Q", E = "E", R = "R", T = "T", F = "F", G = "G", Shift = "SHIFT", Jump = "SPACE", CameraLock = "CTRL" }
function Style.KeyLabel(deps: any, action: string): string
	local input = if type(deps) == "table" then deps.Input else nil
	if type(input) == "table" and type(input.KeyLabel) == "function" then
		local ok, label = pcall(input.KeyLabel, action)
		if ok and type(label) == "string" and label ~= "" then
			return label
		end
	end
	return DEFAULT_KEYS[action] or action
end

return Style
