-- STYLE 2: "Cartoon" — loud and bouncy, like the show. Chunky outlined buttons, swirling portal behind the logo.
local Game = script.Parent.Parent
local UI = require(Game.UI)
local Config = require(Game.Config)

local Style = {}
Style.Name = "Cartoon"
Style.Music = "MusicLofi"

Style.Camera = {
	From = { Pos = Vector3.new(0.6, 6.4, 7.2), Look = Vector3.new(-7.4, 2.6, -5.2), Yaw = 17 },
	To = { Pos = Vector3.new(2.4, 6.0, 7.0), Look = Vector3.new(-7.4, 2.6, -5.2), Yaw = 17 },
	Duration = 22,
	FOV = 60,
	Sway = 0.35,
}

local rgb = Color3.fromRGB
local INK = rgb(44, 28, 16)
local CREAM = rgb(252, 246, 226)
local FILLS = {
	primary = rgb(151, 206, 76),
	normal = rgb(92, 198, 224),
	danger = rgb(240, 120, 96),
	back = rgb(246, 222, 80),
}
local TILTS = { -2.5, 1.8, -1.2, 2.2, -1.8 }

local function splitTitle(title: string): (string, string)
	local words = string.split(title, " ")
	if #words < 2 then
		return "", title
	end
	local last = table.remove(words) :: string
	return table.concat(words, " "), last
end

function Style.Build(ctx)
	local api = {}
	local tick0 = os.clock()

	local content = UI.new("Frame", {
		Name = "CartoonContent",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = ctx.Canvas,
	})

	-- logo + portal ---------------------------------------------------------------
	local logo = UI.new("Frame", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(70, 40),
		Size = UDim2.fromOffset(760, 330),
		Rotation = -4,
		Parent = content,
	})
	local logoScale = UI.new("UIScale", { Scale = 0, Parent = logo })

	local portal = UI.new("Frame", {
		Name = "Portal",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(330, 175),
		Size = UDim2.fromOffset(600, 380),
		Parent = logo,
	})
	local ringColors = {
		{ rgb(34, 110, 30), rgb(80, 170, 40) },
		{ rgb(90, 180, 40), rgb(160, 225, 80) },
		{ rgb(160, 225, 80), rgb(220, 250, 160) },
		{ rgb(225, 252, 190), rgb(250, 255, 235) },
	}
	local ringGradients = {}
	for i, cols in ringColors do
		local f = 1 - (i - 1) * 0.2
		local ring = UI.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(f, f),
			Parent = portal,
		}, { UI.round() })
		local g = UI.gradient({ cols[1], cols[2], cols[1], cols[2], cols[1] }, nil, i * 40)
		g.Parent = ring
		table.insert(ringGradients, g)
		if i == 1 then
			UI.stroke(10, rgb(120, 230, 60), 0.55, true).Parent = ring
		end
	end

	local line1, line2 = splitTitle(Config.Title)
	local function logoText(text: string, y: number, size: number)
		local shadow = UI.label({
			Text = text,
			Font = Enum.Font.LuckiestGuy,
			TextSize = size,
			TextColor3 = rgb(70, 40, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(9, y + 10),
			Size = UDim2.new(1, 0, 0, size + 10),
			Parent = logo,
		})
		UI.stroke(7, rgb(70, 40, 20)).Parent = shadow
		local main = UI.label({
			Text = text,
			Font = Enum.Font.LuckiestGuy,
			TextSize = size,
			TextColor3 = rgb(86, 204, 228),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, size + 10),
			Parent = logo,
		})
		UI.stroke(7, rgb(206, 238, 80)).Parent = main
		return main
	end
	logoText(line1, 40, 92)
	logoText(line2, 120, 150)

	local tag = UI.new("Frame", {
		Name = "Tag",
		BackgroundColor3 = rgb(246, 222, 80),
		Position = UDim2.fromOffset(250, 290),
		Size = UDim2.fromOffset(340, 58),
		Rotation = 7,
		Parent = logo,
	}, { UI.corner(14), UI.stroke(4, INK, 0, true) })
	UI.label({
		Text = Config.Subtitle .. "!",
		Font = Enum.Font.LuckiestGuy,
		TextSize = 32,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = tag,
	})

	local pages = UI.new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(120, 420),
		Size = UDim2.fromOffset(760, 640),
		Parent = content,
	})

	api.Theme = {
		Font = Enum.Font.FredokaOne,
		Text = INK,
		TextDim = rgb(120, 92, 64),
		Accent = rgb(120, 190, 60),
		Track = INK,
		TrackTransparency = 0.82,
		TrackHeight = 10,
		Knob = Color3.new(1, 1, 1),
		KnobStroke = INK,
		KnobStrokeThickness = 3,
		KnobSize = 24,
		Corner = 5,
		RowHeight = 44,
		LabelSize = 25,
		Width = 640,
		ValueWidth = 80,
		Uppercase = false,
	}

	local mainScales = {}

	function api.NewPage(name: string)
		if name == "Main" then
			local page = UI.new("Frame", {
				Name = name,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = pages,
			}, { UI.list(14) })
			return page
		end
		-- other pages live on a cream card
		local holder = UI.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(720, 640),
			Visible = false,
			Parent = pages,
		})
		UI.new("Frame", {
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		}, { UI.corner(30) })
		local card = UI.new("Frame", {
			Name = "Card",
			BackgroundColor3 = CREAM,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		}, { UI.corner(30), UI.stroke(5, INK, 0, true), UI.padding(36, 22, 36, 22), UI.list(4) })
		holder:SetAttribute("Card", true)
		local scale = UI.new("UIScale", { Parent = holder })
		holder:SetAttribute("HasScale", true)
		return card, scale
	end

	function api.MakeButton(parent: Instance, text: string, order: number, kind: string)
		local big = kind == "primary"
		local h = if big then 100 elseif kind == "back" then 70 else 84
		local holder = UI.new("Frame", {
			Name = text,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(if kind == "back" then 260 else 400, h + 8),
			LayoutOrder = order,
			Rotation = TILTS[(order % #TILTS) + 1],
			Parent = parent,
		})
		local scale = UI.new("UIScale", { Parent = holder })
		if parent.Name == "Main" then
			scale.Scale = 0
			table.insert(mainScales, scale)
		end
		UI.new("Frame", {
			BackgroundColor3 = INK,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 1, -8),
			Parent = holder,
		}, { UI.corner(26) })
		local face = UI.new("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = FILLS[kind] or FILLS.normal,
			Text = "",
			Size = UDim2.new(1, 0, 1, -8),
			Parent = holder,
		}, { UI.corner(26), UI.stroke(4, INK, 0, true) })
		UI.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(22, 10),
			Size = UDim2.new(0.45, 0, 0, 8),
			Parent = face,
		}, { UI.round() })
		UI.label({
			Text = string.upper(text),
			Font = Enum.Font.LuckiestGuy,
			TextSize = if big then 54 elseif kind == "back" then 34 else 42,
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromScale(1, 1),
			Parent = face,
		})
		local baseRot = holder.Rotation
		local function setHover(on: boolean)
			UI.tween(face, 0.22, { Position = UDim2.fromOffset(0, if on then -5 else 0) }, Enum.EasingStyle.Back)
			UI.tween(holder, 0.22, { Rotation = if on then 0 else baseRot }, Enum.EasingStyle.Back)
			UI.tween(scale, 0.22, { Scale = if on then 1.06 else 1 }, Enum.EasingStyle.Back)
		end
		face.MouseButton1Down:Connect(function()
			UI.tween(face, 0.08, { Position = UDim2.fromOffset(0, 6) })
		end)
		face.MouseButton1Up:Connect(function()
			UI.tween(face, 0.15, { Position = UDim2.fromOffset(0, -5) }, Enum.EasingStyle.Back)
		end)
		return face, setHover
	end

	function api.MakeHeading(parent: Instance, text: string, order: number)
		return UI.label({
			Text = string.upper(text),
			Font = Enum.Font.LuckiestGuy,
			TextSize = 52,
			TextColor3 = INK,
			Size = UDim2.fromOffset(640, 70),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.MakeText(parent: Instance, text: string, order: number)
		return UI.label({
			Text = text,
			Font = Enum.Font.FredokaOne,
			TextSize = 24,
			TextColor3 = rgb(90, 66, 44),
			TextWrapped = true,
			Size = UDim2.fromOffset(640, 40),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.ShowPage(page: Frame, old: Frame?, instant: boolean?)
		local function holderOf(p: Instance): GuiObject
			return (if p.Name == "Card" then p.Parent else p) :: GuiObject
		end
		if old then
			holderOf(old).Visible = false
		end
		local h = holderOf(page)
		h.Visible = true
		page.Visible = true
		local scale = h:FindFirstChildOfClass("UIScale")
		if scale and not instant then
			scale.Scale = 0.6
			UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		if page.Name == "Main" and not instant then
			for _, s in mainScales do
				s.Scale = 1
			end
		end
	end

	function api.Intro()
		UI.tween(logoScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back, nil, 0.2)
		for i, s in mainScales do
			UI.tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, nil, 0.5 + i * 0.09)
		end
	end

	function api.Outro(done: () -> ())
		for i, s in mainScales do
			UI.tween(s, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In, (i - 1) * 0.05)
		end
		UI.tween(logo, 0.6, { Position = UDim2.fromOffset(70, -420), Rotation = -14 }, Enum.EasingStyle.Back, Enum.EasingDirection.In, 0.15)
		task.delay(0.8, done)
	end

	function api.Update(_dt: number)
		local t = os.clock() - tick0
		for i, g in ringGradients do
			g.Rotation = (i * 40 + t * (40 + i * 25) * (if i % 2 == 0 then -1 else 1)) % 360
		end
		portal.Rotation = math.sin(t * 0.7) * 4
		portal.Size = UDim2.fromOffset(600 + math.sin(t * 2.1) * 14, 380 + math.cos(t * 1.7) * 10)
		logo.Position = UDim2.fromOffset(70, 40 + math.sin(t * 1.6) * 6)
	end

	function api.Destroy()
		content:Destroy()
	end

	return api
end

return Style
