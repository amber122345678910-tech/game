-- STYLE 3: "Monitor" — the menu lives on Morty's old CRT computer. Green terminal text, scanlines, CRT power-on.
local Game = script.Parent.Parent
local UI = require(Game.UI)
local Config = require(Game.Config)

local Style = {}
Style.Name = "Monitor"
Style.Music = "MusicSynth"

local SCREEN = Vector3.new(8.09, 3.72, -3.8)
Style.Camera = {
	From = { Pos = Vector3.new(5.85, 4.1, -2.5), Look = SCREEN },
	To = { Pos = Vector3.new(6.1, 4.25, -3.15), Look = SCREEN },
	Duration = 18,
	FOV = 44,
	Focus = SCREEN,
	Sway = 0.08,
}

local rgb = Color3.fromRGB
local GREEN = rgb(120, 255, 150)
local GREEN_DIM = rgb(60, 170, 92)
local BG = rgb(6, 14, 10)

function Style.Build(ctx)
	local api = {}
	local t0 = os.clock()
	local house = workspace:WaitForChild("MortysHouse")
	local monitor = house:WaitForChild("Monitor")
	local screen = monitor:WaitForChild("Screen") :: BasePart
	local saver = screen:FindFirstChild("ScreenSaver") :: SurfaceGui?
	if saver then
		saver.Enabled = false
	end

	local sg = UI.new("SurfaceGui", {
		Name = "MonitorMenu",
		Adornee = screen,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 260,
		LightInfluence = 0,
		Brightness = 1.8,
		ClipsDescendants = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = ctx.Gui.Parent,
	})

	local tube = UI.new("Frame", {
		Name = "Tube",
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.004),
		ClipsDescendants = true,
		Parent = sg,
	}, { UI.gradient({ rgb(14, 30, 20), BG }, nil, 90) })

	-- header bar
	local header = UI.new("Frame", {
		BackgroundColor3 = GREEN,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = tube,
	})
	UI.label({
		Text = " MORTY-OS 2.3",
		Font = Enum.Font.RobotoMono,
		TextSize = 17,
		TextColor3 = BG,
		Size = UDim2.fromScale(0.6, 1),
		Parent = header,
	})
	local clockLabel = UI.label({
		Text = "03:14",
		Font = Enum.Font.RobotoMono,
		TextSize = 17,
		TextColor3 = BG,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.fromScale(0.4, 1),
		Parent = header,
	})

	local titleBlock = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 36),
		Size = UDim2.new(1, -44, 0, 70),
		Parent = tube,
	})
	local title = UI.label({
		Text = Config.Title,
		Font = Enum.Font.Arcade,
		TextSize = 30,
		TextColor3 = GREEN,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = titleBlock,
	})
	UI.stroke(2, GREEN, 0.85).Parent = title
	local prompt = UI.label({
		Text = "> wake_up_morty.exe",
		Font = Enum.Font.RobotoMono,
		TextSize = 17,
		TextColor3 = GREEN_DIM,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = titleBlock,
	})

	local pages = UI.new("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 112),
		Size = UDim2.new(1, -44, 1, -120),
		Parent = tube,
	})

	-- scanlines + flicker on top of everything
	local lines = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = tube })
	for y = 0, 400, 4 do
		UI.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 2),
			ZIndex = 50,
			Parent = lines,
		})
	end
	local flicker = UI.new("Frame", {
		BackgroundColor3 = GREEN,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 51,
		Parent = tube,
	})
	local vignette = UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 49,
		Parent = tube,
	}, { UI.gradient(nil, { 0.35, 1, 1, 0.35 }, 0) })
	vignette.BackgroundTransparency = 0.2

	-- hint on the real screen
	local hint = UI.label({
		Text = "CLICK THE SCREEN",
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(400, 24),
		Parent = ctx.Canvas,
	})

	api.Theme = {
		Font = Enum.Font.RobotoMono,
		Text = GREEN,
		TextDim = GREEN_DIM,
		Accent = GREEN,
		RowHeight = 25,
		LabelSize = 16,
		Width = 446,
		ValueWidth = 70,
		Uppercase = true,
		Textual = true,
	}

	function api.NewPage(name: string)
		return UI.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = pages,
		}, { UI.list(2) })
	end

	function api.MakeButton(parent: Instance, text: string, order: number, kind: string)
		local button = UI.new("TextButton", {
			Name = text,
			AutoButtonColor = false,
			BackgroundColor3 = GREEN,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Size = UDim2.fromOffset(300, if kind == "primary" then 36 else 30),
			LayoutOrder = order,
			Parent = parent,
		})
		local label = UI.label({
			Text = "  " .. string.upper(text),
			Font = Enum.Font.RobotoMono,
			TextSize = if kind == "primary" then 24 else 20,
			TextColor3 = GREEN,
			Size = UDim2.fromScale(1, 1),
			Parent = button,
		})
		local function setHover(on: boolean)
			button.BackgroundTransparency = if on then 0 else 1
			label.TextColor3 = if on then BG else GREEN
			label.Text = (if on then "> " else "  ") .. string.upper(text)
		end
		return button, setHover
	end

	function api.MakeHeading(parent: Instance, text: string, order: number)
		return UI.label({
			Text = "== " .. string.upper(text) .. " ==",
			Font = Enum.Font.RobotoMono,
			TextSize = 20,
			TextColor3 = GREEN,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.MakeText(parent: Instance, text: string, order: number)
		return UI.label({
			Text = "- " .. text,
			Font = Enum.Font.RobotoMono,
			TextSize = 14,
			TextColor3 = GREEN_DIM,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
			Parent = parent,
		})
	end

	function api.ShowPage(page: Frame, old: Frame?, _instant: boolean?)
		if old then
			old.Visible = false
		end
		page.Visible = true
		local isMain = page.Name == "Main"
		titleBlock.Visible = isMain
		pages.Position = UDim2.fromOffset(22, if isMain then 112 else 34)
		pages.Size = UDim2.new(1, -44, 1, if isMain then -120 else -40)
		flicker.BackgroundTransparency = 0.7
		UI.tween(flicker, 0.25, { BackgroundTransparency = 1 })
	end

	function api.Intro()
		UI.tween(tube, 0.18, { Size = UDim2.fromScale(1, 0.02) }, Enum.EasingStyle.Quad)
		task.delay(0.2, function()
			UI.tween(tube, 0.4, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
		end)
		flicker.BackgroundTransparency = 0.2
		UI.tween(flicker, 0.9, { BackgroundTransparency = 1 }, nil, nil, 0.3)
		UI.tween(hint, 0.8, { TextTransparency = 0.4 }, nil, nil, 1.5)
	end

	function api.Outro(done: () -> ())
		UI.tween(hint, 0.3, { TextTransparency = 1 })
		UI.tween(tube, 0.18, { Size = UDim2.fromScale(1, 0.01) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			UI.tween(tube, 0.15, { Size = UDim2.fromScale(0.01, 0.01) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		task.delay(0.4, done)
	end

	local blink = 0
	function api.Update(dt: number)
		blink += dt
		local on = math.floor(blink * 2) % 2 == 0
		prompt.Text = "> wake_up_morty.exe" .. (if on then "_" else " ")
		if math.random() < 0.02 then
			flicker.BackgroundTransparency = 0.94
			UI.tween(flicker, 0.12, { BackgroundTransparency = 1 })
		end
		local t = os.clock() - t0
		clockLabel.Text = string.format("03:%02d", 14 + math.floor(t / 60) % 45)
	end

	function api.Destroy()
		sg:Destroy()
		hint:Destroy()
		if saver then
			saver.Enabled = true
		end
	end

	return api
end

return Style
