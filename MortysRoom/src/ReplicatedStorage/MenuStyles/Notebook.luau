-- STYLE 5: "Notebook" — a page torn from Morty's school notebook, taped over the screen. Handwriting and doodles.
local Game = script.Parent.Parent
local UI = require(Game.UI)
local Config = require(Game.Config)

local Style = {}
Style.Name = "Notebook"
Style.Music = "MusicLofi"

local HEAD = Vector3.new(-8.15, 3.29, -6.65)
Style.Camera = {
	From = { Pos = Vector3.new(3.6, 4.7, 0.2), Look = HEAD, Yaw = -15 },
	To = { Pos = Vector3.new(2.6, 4.5, -1.2), Look = HEAD, Yaw = -15 },
	Duration = 26,
	FOV = 48,
	Focus = HEAD,
	Sway = 0.2,
}

local rgb = Color3.fromRGB
local PAPER = rgb(252, 250, 242)
local INK = rgb(34, 34, 52)
local BLUE_INK = rgb(46, 66, 160)
local RED_INK = rgb(205, 52, 52)
local LINE = rgb(164, 194, 232)
local W, H = 620, 900

local function splitTitle(title: string): string
	-- "RICK AND MORTY" -> "Rick & Morty"
	local words = {}
	for _, w in string.split(string.lower(title), " ") do
		if w == "and" then
			table.insert(words, "&")
		else
			table.insert(words, string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2))
		end
	end
	return table.concat(words, " ")
end

function Style.Build(ctx)
	local api = {}

	local content = UI.new("Frame", {
		Name = "NotebookContent",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = ctx.Canvas,
	})

	local sheetHolder = UI.new("Frame", {
		Name = "Sheet",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -120 + 900, 0.5, 0),
		Size = UDim2.fromOffset(W, H),
		Rotation = 9,
		Parent = content,
	})
	UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 18),
		Size = UDim2.fromScale(1, 1),
		Parent = sheetHolder,
	}, { UI.corner(6) })
	local sheet = UI.new("Frame", {
		Name = "Paper",
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = sheetHolder,
	}, { UI.corner(6), UI.gradient({ rgb(255, 255, 255), rgb(240, 236, 224) }, nil, 70) })

	for y = 150, H - 30, 46 do
		UI.new("Frame", {
			BackgroundColor3 = LINE,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 2),
			Parent = sheet,
		})
	end
	UI.new("Frame", {
		BackgroundColor3 = rgb(232, 128, 128),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(84, 0),
		Size = UDim2.new(0, 2, 1, 0),
		Parent = sheet,
	})
	for y = 60, H - 40, 76 do
		UI.new("Frame", {
			BackgroundColor3 = rgb(40, 36, 44),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(26, y),
			Size = UDim2.fromOffset(22, 22),
			Parent = sheet,
		}, { UI.round() })
	end
	UI.new("Frame", {
		Name = "Tape",
		BackgroundColor3 = rgb(236, 222, 168),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(190, 50),
		Rotation = -5,
		Parent = sheetHolder,
	})

	-- title + doodles
	local title = UI.label({
		Text = splitTitle(Config.Title),
		Font = Enum.Font.PermanentMarker,
		TextSize = 66,
		TextColor3 = INK,
		Position = UDim2.fromOffset(104, 34),
		Size = UDim2.fromOffset(500, 80),
		Rotation = -2,
		Parent = sheet,
	})
	UI.new("Frame", {
		BackgroundColor3 = RED_INK,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(110, 112),
		Size = UDim2.fromOffset(380, 4),
		Rotation = -1.5,
		Parent = sheet,
	}, { UI.round() })
	UI.new("Frame", {
		BackgroundColor3 = RED_INK,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(130, 120),
		Size = UDim2.fromOffset(330, 3),
		Rotation = 0.8,
		Parent = sheet,
	}, { UI.round() })
	local subtitle = UI.label({
		Text = string.lower(Config.Subtitle) .. "!!",
		Font = Enum.Font.PatrickHand,
		TextSize = 38,
		TextColor3 = BLUE_INK,
		Position = UDim2.fromOffset(112, 140),
		Size = UDim2.fromOffset(460, 44),
		Rotation = -2,
		Parent = sheet,
	})
	local _ = title
	local _s = subtitle
	-- portal doodle
	local doodle = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(470, 200),
		Size = UDim2.fromOffset(110, 140),
		Rotation = 12,
		Parent = sheet,
	})
	for i, s in { 1, 0.72, 0.46, 0.22 } do
		UI.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + (i - 1) * 0.02, 0.5),
			Size = UDim2.fromScale(s, s),
			Parent = doodle,
		}, { UI.round(), UI.stroke(3, rgb(70, 160, 60), 0.05 * i, true) })
	end
	UI.label({
		Text = "z z Z",
		Font = Enum.Font.PatrickHand,
		TextSize = 34,
		TextColor3 = BLUE_INK,
		Position = UDim2.fromOffset(480, 760),
		Size = UDim2.fromOffset(120, 40),
		Rotation = -10,
		Parent = sheet,
	})

	local pages = UI.new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(110, 252),
		Size = UDim2.fromOffset(460, 620),
		Parent = sheet,
	})

	api.Theme = {
		Font = Enum.Font.PatrickHand,
		Text = INK,
		TextDim = rgb(96, 96, 128),
		Accent = RED_INK,
		Track = INK,
		TrackTransparency = 0.7,
		TrackHeight = 3,
		Knob = PAPER,
		KnobStroke = INK,
		KnobStrokeThickness = 2,
		KnobSize = 20,
		Corner = 2,
		RowHeight = 46,
		LabelSize = 30,
		Width = 450,
		ValueWidth = 72,
		Uppercase = false,
	}

	function api.NewPage(name: string)
		return UI.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = pages,
		}, { UI.list(if name == "Main" then 10 else 0) })
	end

	local tilt = { -1.5, 1, -0.5, 1.5, -1 }
	function api.MakeButton(parent: Instance, text: string, order: number, kind: string)
		local big = kind == "primary"
		local button = UI.new("TextButton", {
			Name = text,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromOffset(400, if big then 84 else 66),
			LayoutOrder = order,
			Rotation = tilt[(order % #tilt) + 1],
			Parent = parent,
		})
		local label = UI.label({
			Text = string.lower(text),
			Font = Enum.Font.PatrickHand,
			TextSize = if big then 66 elseif kind == "back" then 40 else 52,
			TextColor3 = if kind == "danger" then rgb(120, 40, 40) else INK,
			Position = UDim2.fromOffset(44, 0),
			Size = UDim2.new(1, -44, 1, 0),
			Parent = button,
		})
		local arrow = UI.label({
			Text = "→",
			Font = Enum.Font.PatrickHand,
			TextSize = 44,
			TextColor3 = RED_INK,
			TextTransparency = 1,
			Position = UDim2.fromOffset(-6, 0),
			Size = UDim2.fromOffset(40, 66),
			Parent = button,
		})
		local circle = UI.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 44 + label.TextBounds.X / 2, 0.5, 0),
			Size = UDim2.fromOffset(0, 0),
			Rotation = -4,
			Parent = button,
		}, { UI.round(), UI.stroke(3, RED_INK, 0, true) })
		local function setHover(on: boolean)
			local w = label.TextBounds.X + 46
			circle.Position = UDim2.new(0, 44 + label.TextBounds.X / 2, 0.5, 2)
			UI.tween(circle, 0.25, { Size = if on then UDim2.fromOffset(w, label.TextBounds.Y + 6) else UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
			UI.tween(arrow, 0.2, { TextTransparency = if on then 0 else 1, Position = UDim2.fromOffset(if on then 0 else -16, 0) })
			UI.tween(label, 0.2, { Position = UDim2.fromOffset(if on then 52 else 44, 0) })
		end
		return button, setHover
	end

	function api.MakeHeading(parent: Instance, text: string, order: number)
		return UI.label({
			Text = text,
			Font = Enum.Font.PermanentMarker,
			TextSize = 46,
			TextColor3 = INK,
			Size = UDim2.fromOffset(450, 62),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.MakeText(parent: Instance, text: string, order: number)
		return UI.label({
			Text = text,
			Font = Enum.Font.PatrickHand,
			TextSize = 28,
			TextColor3 = BLUE_INK,
			TextWrapped = true,
			Size = UDim2.fromOffset(450, 92),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.ShowPage(page: Frame, old: Frame?, instant: boolean?)
		if old then
			old.Visible = false
		end
		page.Visible = true
		if not instant then
			sheetHolder.Rotation = 2.8
			UI.tween(sheetHolder, 0.35, { Rotation = 2 }, Enum.EasingStyle.Back)
		end
	end

	function api.Intro()
		UI.tween(sheetHolder, 0.8, { Position = UDim2.new(1, -120, 0.5, 0), Rotation = 2 }, Enum.EasingStyle.Back, nil, 0.3)
	end

	function api.Outro(done: () -> ())
		UI.tween(sheetHolder, 0.6, { Position = UDim2.new(1, -120 + 1000, 0.5, 80), Rotation = 18 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.65, done)
	end

	function api.Destroy()
		content:Destroy()
	end

	return api
end

return Style
