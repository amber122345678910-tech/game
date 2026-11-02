-- STYLE 1: "Cinematic" — quiet, film-like. Letterbox bars, thin type, slow push-in on sleeping Morty.
local Game = script.Parent.Parent
local UI = require(Game.UI)
local Config = require(Game.Config)

local Style = {}
Style.Name = "Cinematic"
Style.Music = "MusicDreamy"

local HEAD = Vector3.new(-8.15, 3.29, -6.65)
Style.Camera = {
	From = { Pos = Vector3.new(-3.4, 5.1, 0.9), Look = HEAD, Yaw = 13 },
	To = { Pos = Vector3.new(-4.9, 4.6, -2.4), Look = HEAD, Yaw = 13 },
	Duration = 30,
	FOV = 40,
	Focus = HEAD,
	Sway = 0.18,
}

local WHITE = Color3.fromRGB(238, 240, 246)
local DIM = Color3.fromRGB(150, 156, 172)
local ACCENT = Color3.fromRGB(151, 206, 76)
local LEFT = 150

function Style.Build(ctx)
	local api = {}

	local root = UI.full(ctx.Full, "Cinematic")
	local shade = UI.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.68, 1),
		Parent = root,
	}, { UI.gradient(nil, { 0.25, 0.55, 1 }, 0) })
	local topShade = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0.3),
		Parent = root,
	}, { UI.gradient(nil, { 0.5, 1 }, 90) })
	local barTop = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		ZIndex = 10,
		Parent = root,
	})
	local barBottom = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 10,
		Parent = root,
	})

	local content = UI.new("CanvasGroup", {
		Name = "CinematicContent",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Parent = ctx.Canvas,
	})

	UI.label({
		Text = UI.spaced(Config.Title),
		Font = Enum.Font.GothamMedium,
		TextSize = 20,
		TextColor3 = DIM,
		Position = UDim2.fromOffset(LEFT + 2, 236),
		Size = UDim2.fromOffset(900, 26),
		Parent = content,
	})
	UI.label({
		Text = Config.Subtitle,
		Font = Enum.Font.Oswald,
		TextSize = 104,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(LEFT - 4, 262),
		Size = UDim2.fromOffset(1000, 120),
		Parent = content,
	})
	local rule = UI.new("Frame", {
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(LEFT, 392),
		Size = UDim2.fromOffset(0, 3),
		Parent = content,
	})

	local pages = UI.new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(LEFT, 440),
		Size = UDim2.fromOffset(760, 600),
		Parent = content,
	})

	UI.label({
		Text = Config.Version,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = DIM,
		TextTransparency = 0.3,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, LEFT, 1, -120),
		Size = UDim2.fromOffset(200, 20),
		Parent = content,
	})
	UI.label({
		Text = "↑ ↓  NAVIGATE      ENTER  SELECT",
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = DIM,
		TextTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -LEFT, 1, -120),
		Size = UDim2.fromOffset(500, 20),
		Parent = content,
	})

	api.Theme = {
		Font = Enum.Font.GothamMedium,
		Text = WHITE,
		TextDim = DIM,
		Accent = ACCENT,
		Track = WHITE,
		TrackTransparency = 0.8,
		TrackHeight = 3,
		Knob = WHITE,
		KnobSize = 14,
		Corner = 2,
		RowHeight = 46,
		LabelSize = 21,
		Width = 700,
		ValueWidth = 90,
		Uppercase = true,
	}

	function api.NewPage(name: string)
		local page = UI.new("CanvasGroup", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = pages,
		}, { UI.list(4) })
		return page
	end

	function api.MakeButton(parent: Instance, text: string, order: number, kind: string)
		local big = kind == "primary"
		local button = UI.new("TextButton", {
			Name = text,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromOffset(560, if big then 70 else 56),
			LayoutOrder = order,
			Parent = parent,
		})
		local bar = UI.new("Frame", {
			BackgroundColor3 = ACCENT,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(0, 2),
			Parent = button,
		})
		local label = UI.label({
			Text = string.upper(text),
			Font = Enum.Font.GothamMedium,
			TextSize = if big then 42 elseif kind == "back" then 24 else 30,
			TextColor3 = WHITE,
			TextTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			Parent = button,
		})
		local function setHover(on: boolean)
			UI.tween(bar, 0.28, { Size = UDim2.fromOffset(if on then 36 else 0, 2) }, Enum.EasingStyle.Quint)
			UI.tween(label, 0.28, {
				Position = UDim2.fromOffset(if on then 52 else 0, 0),
				TextTransparency = if on then 0 else 0.45,
				TextColor3 = if on and kind == "danger" then Color3.fromRGB(255, 140, 120) else WHITE,
			}, Enum.EasingStyle.Quint)
		end
		return button, setHover
	end

	function api.MakeHeading(parent: Instance, text: string, order: number)
		return UI.label({
			Text = string.upper(text),
			Font = Enum.Font.Oswald,
			TextSize = 48,
			TextColor3 = WHITE,
			Size = UDim2.fromOffset(700, 64),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.MakeText(parent: Instance, text: string, order: number)
		return UI.label({
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 22,
			TextColor3 = DIM,
			TextWrapped = true,
			Size = UDim2.fromOffset(680, 36),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.ShowPage(page: CanvasGroup, old: CanvasGroup?, instant: boolean?)
		if old then
			if instant then
				old.Visible = false
			else
				UI.tween(old, 0.18, { GroupTransparency = 1 })
				task.delay(0.18, function()
					old.Visible = false
				end)
			end
		end
		page.Visible = true
		if instant then
			page.GroupTransparency = 0
			page.Position = UDim2.fromOffset(0, 0)
		else
			page.GroupTransparency = 1
			page.Position = UDim2.fromOffset(-24, 0)
			UI.tween(page, 0.45, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint, nil, 0.12)
		end
	end

	function api.Intro()
		UI.tween(barTop, 1.4, { Size = UDim2.fromScale(1, 0.085) }, Enum.EasingStyle.Quint)
		UI.tween(barBottom, 1.4, { Size = UDim2.fromScale(1, 0.085) }, Enum.EasingStyle.Quint)
		content.Position = UDim2.fromOffset(-30, 0)
		UI.tween(content, 1.6, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint, nil, 0.4)
		UI.tween(rule, 1.2, { Size = UDim2.fromOffset(72, 3) }, Enum.EasingStyle.Quint, nil, 1.0)
	end

	function api.Outro(done: () -> ())
		UI.tween(content, 0.7, { GroupTransparency = 1, Position = UDim2.fromOffset(-30, 0) }, Enum.EasingStyle.Quint)
		UI.tween(shade, 1.2, { BackgroundTransparency = 1 })
		UI.tween(topShade, 1.2, { BackgroundTransparency = 1 })
		UI.tween(barTop, 1.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint, nil, 0.3)
		UI.tween(barBottom, 1.4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quint, nil, 0.3)
		task.delay(0.75, done)
	end

	function api.Destroy()
		root:Destroy()
		content:Destroy()
	end

	return api
end

return Style
