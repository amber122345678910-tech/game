-- STYLE 4: "VHS" — an old camcorder tape of Morty sleeping. Pixel on-screen display, scanlines, tracking noise.
local Game = script.Parent.Parent
local UI = require(Game.UI)
local Config = require(Game.Config)

local Style = {}
Style.Name = "VHS"
Style.Music = "MusicNight"
Style.MenuBlur = 2

Style.Camera = {
	From = { Pos = Vector3.new(9.2, 7.9, 7.2), Look = Vector3.new(-7.0, 2.2, -5.2) },
	To = { Pos = Vector3.new(9.2, 7.9, 7.2), Look = Vector3.new(-2.0, 2.4, -7.2) },
	Duration = 16,
	FOV = 74,
	Sway = 0.5,
	Shake = 0.004,
}

local rgb = Color3.fromRGB
local WHITE = rgb(246, 246, 246)
local CYAN = rgb(90, 230, 255)
local FONT = Enum.Font.Arcade

local NAMES = {
	Play = "PLAY",
	Resume = "PLAY",
	Settings = "SETUP",
	Credits = "CREDITS",
	Quit = "EJECT",
	["Main Menu"] = "STOP",
	Back = "RETURN",
	Yes = "YES",
	No = "NO",
}

local function osd(parent: Instance, props): TextLabel
	-- text with a hard black drop shadow, like a real VCR on-screen display
	local shadowProps = table.clone(props)
	shadowProps.Name = "Shadow"
	shadowProps.TextColor3 = Color3.new(0, 0, 0)
	shadowProps.Position = UDim2.fromOffset(4, 4)
	shadowProps.Size = UDim2.fromScale(1, 1)
	shadowProps.ZIndex = 1
	shadowProps.Parent = nil
	local holder = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = props.Position,
		Size = props.Size,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Parent = parent,
	})
	shadowProps.AnchorPoint = nil
	shadowProps.LayoutOrder = nil
	local s = UI.label(shadowProps)
	s.Parent = holder
	local mainProps = table.clone(props)
	mainProps.Position = UDim2.fromOffset(0, 0)
	mainProps.Size = UDim2.fromScale(1, 1)
	mainProps.AnchorPoint = nil
	mainProps.LayoutOrder = nil
	mainProps.ZIndex = 2
	mainProps.Parent = holder
	local m = UI.label(mainProps)
	return m
end

function Style.Build(ctx)
	local api = {}
	local t0 = os.clock()

	local fx = UI.full(ctx.Full, "VHSFx")
	-- scanlines
	local lines = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = fx })
	for i = 0, 300 do
		UI.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, i / 300),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 20,
			Parent = lines,
		})
	end
	local tracking = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1.2),
		Size = UDim2.new(1, 0, 0.05, 0),
		ZIndex = 21,
		Parent = fx,
	}, { UI.gradient(nil, { 1, 0.3, 0.7, 0.2, 1 }, 90) })
	local tint = UI.new("Frame", {
		BackgroundColor3 = rgb(30, 10, 60),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 19,
		Parent = fx,
	})
	local edge = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 18,
		Parent = fx,
	}, { UI.gradient(nil, { 0.2, 1, 1, 0.2 }, 0) })
	edge.BackgroundTransparency = 0.3

	local content = UI.new("CanvasGroup", {
		Name = "VHSContent",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Parent = ctx.Canvas,
	})
	local playLabel = osd(content, {
		Text = "PLAY >",
		Font = FONT,
		TextSize = 34,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(110, 80),
		Size = UDim2.fromOffset(400, 40),
	})
	osd(content, {
		Text = "SP",
		Font = FONT,
		TextSize = 34,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -110, 0, 80),
		Size = UDim2.fromOffset(300, 40),
	})
	local dateLabel = osd(content, {
		Text = string.upper(os.date("%b. %d %Y") :: string),
		Font = FONT,
		TextSize = 28,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 110, 1, -80),
		Size = UDim2.fromOffset(600, 34),
	})
	local timeLabel = osd(content, {
		Text = "AM 3:14:00",
		Font = FONT,
		TextSize = 28,
		TextColor3 = WHITE,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 110, 1, -124),
		Size = UDim2.fromOffset(600, 34),
	})
	local counter = osd(content, {
		Text = "0:00:00",
		Font = FONT,
		TextSize = 28,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -110, 1, -80),
		Size = UDim2.fromOffset(400, 34),
	})
	local _ = dateLabel

	-- title with fake colour bleeding
	local titleY = 190
	for i, c in { rgb(255, 40, 80), rgb(40, 220, 255) } do
		UI.label({
			Text = Config.Title,
			Font = FONT,
			TextSize = 58,
			TextColor3 = c,
			TextTransparency = 0.45,
			Position = UDim2.fromOffset(110 + (if i == 1 then -4 else 4), titleY),
			Size = UDim2.fromOffset(1200, 70),
			Parent = content,
		})
	end
	osd(content, {
		Text = Config.Title,
		Font = FONT,
		TextSize = 58,
		TextColor3 = WHITE,
		Position = UDim2.fromOffset(110, titleY),
		Size = UDim2.fromOffset(1200, 70),
	})
	osd(content, {
		Text = "TAPE 03 - " .. Config.Subtitle,
		Font = FONT,
		TextSize = 22,
		TextColor3 = CYAN,
		Position = UDim2.fromOffset(114, titleY + 82),
		Size = UDim2.fromOffset(1200, 30),
	})

	local pages = UI.new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(110, 360),
		Size = UDim2.fromOffset(820, 560),
		Parent = content,
	})

	api.Theme = {
		Font = FONT,
		Text = WHITE,
		TextDim = rgb(176, 176, 190),
		Accent = CYAN,
		RowHeight = 40,
		LabelSize = 20,
		Width = 780,
		ValueWidth = 120,
		Uppercase = true,
		Textual = true,
	}

	function api.NewPage(name: string)
		return UI.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = pages,
		}, { UI.list(8) })
	end

	function api.MakeButton(parent: Instance, text: string, order: number, kind: string)
		local name = NAMES[text] or string.upper(text)
		local button = UI.new("TextButton", {
			Name = text,
			AutoButtonColor = false,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Size = UDim2.fromOffset(460, if kind == "primary" then 58 else 50),
			LayoutOrder = order,
			Parent = parent,
		})
		local label = osd(button, {
			Text = "  " .. name,
			Font = FONT,
			TextSize = if kind == "primary" then 38 else 30,
			TextColor3 = WHITE,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
		})
		local shadow = label.Parent and label.Parent:FindFirstChild("Shadow") :: TextLabel?
		local function setHover(on: boolean)
			button.BackgroundTransparency = if on then 0 else 1
			label.TextColor3 = if on then Color3.new(0, 0, 0) else WHITE
			label.Text = (if on then "> " else "  ") .. name
			if shadow then
				shadow.Visible = not on
				shadow.Text = label.Text
			end
		end
		return button, setHover
	end

	function api.MakeHeading(parent: Instance, text: string, order: number)
		local holderLabel = osd(parent, {
			Text = string.upper(if text == "Settings" then "SETUP" else text),
			Font = FONT,
			TextSize = 36,
			TextColor3 = CYAN,
			Size = UDim2.fromOffset(780, 56),
			LayoutOrder = order,
		})
		return holderLabel.Parent
	end

	function api.MakeText(parent: Instance, text: string, order: number)
		local l = osd(parent, {
			Text = string.upper(text),
			Font = FONT,
			TextSize = 16,
			TextColor3 = WHITE,
			TextWrapped = true,
			Size = UDim2.fromOffset(780, 40),
			LayoutOrder = order,
		})
		return l.Parent
	end

	function api.ShowPage(page: Frame, old: Frame?, instant: boolean?)
		if old then
			old.Visible = false
		end
		page.Visible = true
		if not instant then
			tracking.Position = UDim2.fromScale(0, -0.05)
			UI.tween(tracking, 0.35, { Position = UDim2.fromScale(0, 1.1) }, Enum.EasingStyle.Linear)
		end
	end

	function api.Intro()
		UI.tween(content, 0.15, { GroupTransparency = 0 }, nil, nil, 0.2)
	end

	function api.Outro(done: () -> ())
		playLabel.Text = "STOP"
		UI.tween(content, 0.2, { GroupTransparency = 1 }, nil, nil, 0.35)
		task.delay(0.6, done)
	end

	local nextTrack = 2
	function api.Update(_dt: number)
		local t = os.clock() - t0
		local secs = 14 * 60 + math.floor(t)
		timeLabel.Text = string.format("AM 3:%02d:%02d", (secs // 60) % 60, secs % 60)
		counter.Text = string.format("0:%02d:%02d", (math.floor(t) // 60) % 60, math.floor(t) % 60)
		playLabel.TextTransparency = if math.floor(t * 1.5) % 2 == 0 then 0 else 0.15
		if t > nextTrack then
			nextTrack = t + 3 + math.random() * 5
			tracking.Position = UDim2.fromScale(0, -0.05)
			UI.tween(tracking, 0.9 + math.random() * 0.6, { Position = UDim2.fromScale(0, 1.1) }, Enum.EasingStyle.Linear)
		end
		content.Position = UDim2.fromOffset(if math.random() < 0.03 then math.random(-4, 4) else 0, 0)
		tint.BackgroundTransparency = 0.85 + math.random() * 0.03
	end

	function api.Destroy()
		fx:Destroy()
		content:Destroy()
	end

	return api
end

return Style
