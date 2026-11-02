-- Dialogue box with typewriter text, speaker tags, glitch effect for Rick, and choices.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local UI = require(script.Parent.UI)
local Lang = require(script.Parent.Lang)
local Audio = require(script.Parent.Audio)

local Dialogue = {}

local rgb = Color3.fromRGB
local SPEAKERS = {
	Rick = { color = rgb(110, 222, 245), pitch = 0.78 },
	Morty = { color = rgb(250, 222, 70), pitch = 1.3 },
	MortyThought = { color = rgb(250, 222, 70), pitch = 1.3, italic = true },
	Beth = { color = rgb(244, 112, 136), pitch = 1.12 },
	Jerry = { color = rgb(136, 204, 104), pitch = 0.95 },
	Summer = { color = rgb(255, 150, 92), pitch = 1.4 },
	Unknown = { color = rgb(200, 120, 255), pitch = 0.6 },
}

local gui: ScreenGui? = nil
local panel, tag, tagLabel, body, ghostA, ghostB, arrow, choiceHolder
local advanceSignal = Instance.new("BindableEvent")
local busy = false
local onSpeaker: ((string?) -> ())? = nil

local function build()
	if gui then
		return
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = UI.new("ScreenGui", {
		Name = "Dialogue",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = pg,
	})
	gui = g
	local canvas = UI.canvas(g)
	panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -48),
		Size = UDim2.fromOffset(1240, 170),
		BackgroundColor3 = rgb(8, 9, 14),
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = canvas,
	}, { UI.corner(18), UI.stroke(1.5, Color3.new(1, 1, 1), 0.85, true) })
	UI.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	}, { UI.corner(18), UI.gradient(nil, { 1, 0.6 }, 90) })
	tag = UI.new("Frame", {
		Name = "Tag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.fromOffset(200, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = rgb(250, 222, 70),
		Parent = panel,
	}, { UI.corner(10), UI.padding(16, 0, 16, 0) })
	tagLabel = UI.label({
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = rgb(16, 16, 20),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = tag,
	})
	local function textLabel(name: string, color: Color3, transparency: number, z: number)
		return UI.label({
			Name = name,
			Font = Enum.Font.GothamMedium,
			TextSize = 30,
			TextColor3 = color,
			TextTransparency = transparency,
			TextWrapped = true,
			RichText = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(40, 38),
			Size = UDim2.new(1, -80, 1, -56),
			ZIndex = z,
			Parent = panel,
		})
	end
	ghostA = textLabel("GhostA", rgb(255, 40, 90), 1, 2)
	ghostB = textLabel("GhostB", rgb(40, 230, 255), 1, 2)
	body = textLabel("Body", Color3.new(1, 1, 1), 0, 3)
	arrow = UI.label({
		Text = "▼",
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -14),
		Size = UDim2.fromOffset(40, 24),
		Parent = panel,
	})
	choiceHolder = UI.new("Frame", {
		Name = "Choices",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -240),
		Size = UDim2.fromOffset(1240, 90),
		Visible = false,
		Parent = canvas,
	}, { UI.list(24, true, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
end

local function isAdvanceInput(input: InputObject): boolean
	local t = input.UserInputType
	local k = input.KeyCode
	return t == Enum.UserInputType.MouseButton1
		or t == Enum.UserInputType.Touch
		or k == Enum.KeyCode.Space
		or k == Enum.KeyCode.E
		or k == Enum.KeyCode.Return
		or k == Enum.KeyCode.ButtonA
end

UserInputService.InputBegan:Connect(function(input, processed)
	if busy and isAdvanceInput(input) and not (processed and input.UserInputType == Enum.UserInputType.Touch) then
		advanceSignal:Fire()
	end
end)

local GLITCH_CHARS = { "█", "▓", "▒", "░", "#", "%", "&", "@", "Ж", "Ψ", "¤", "§" }
local function corrupt(text: string, amount: number): string
	local out = {}
	for _, cp in utf8.codes(text) do
		local ch = utf8.char(cp)
		if ch ~= " " and math.random() < amount then
			table.insert(out, GLITCH_CHARS[math.random(1, #GLITCH_CHARS)])
		else
			table.insert(out, ch)
		end
	end
	return table.concat(out)
end

function Dialogue.setSpeakerCallback(fn: ((string?) -> ())?)
	onSpeaker = fn
end

--[[
	Show a line and wait. opts:
	  auto     = seconds to wait after the text is fully shown, then continue on its own (true = automatic time)
	  glitch   = 0..1 how broken the text looks (Rick)
	  noWait   = return immediately (the box stays until the next line or hide())
]]
function Dialogue.say(speaker: string, line: any, opts: { [string]: any }?)
	build()
	local o = opts or {}
	local info = SPEAKERS[speaker] or SPEAKERS.Unknown
	local text = Lang.t(line)
	if info.italic then
		text = "<i>" .. text .. "</i>"
	end
	panel.Visible = true
	tag.BackgroundColor3 = info.color
	tagLabel.Text = Lang.t("who." .. speaker)
	body.Text = text
	ghostA.Text = text
	ghostB.Text = text
	body.MaxVisibleGraphemes = 0
	arrow.TextTransparency = 1
	if onSpeaker then
		onSpeaker(speaker)
	end
	local glitch = o.glitch or 0
	local total = utf8.len(body.ContentText) or #text
	local shown = 0
	local skip = false
	busy = true
	local conn = advanceSignal.Event:Connect(function()
		skip = true
	end)
	local cps = o.speed or 38
	local blip = 0
	-- typewriter
	while shown < total and not skip do
		local dt = RunService.RenderStepped:Wait()
		local before = math.floor(shown)
		shown = math.min(total, shown + dt * cps)
		body.MaxVisibleGraphemes = math.floor(shown)
		if math.floor(shown) ~= before then
			blip += 1
			if blip % 3 == 0 then
				Audio.play("UITick", info.pitch * (0.92 + math.random() * 0.16))
			end
		end
		if glitch > 0 then
			local g = math.random() < glitch * 0.35
			body.Text = if g then corrupt(text, glitch * 0.4) else text
			ghostA.TextTransparency = if g then 0.45 else 1
			ghostB.TextTransparency = if g then 0.45 else 1
			ghostA.Position = UDim2.fromOffset(40 + math.random(-5, 5), 38 + math.random(-2, 2))
			ghostB.Position = UDim2.fromOffset(40 + math.random(-5, 5), 38 + math.random(-2, 2))
			ghostA.MaxVisibleGraphemes = math.floor(shown)
			ghostB.MaxVisibleGraphemes = math.floor(shown)
			panel.Position = UDim2.new(0.5, if g then math.random(-6, 6) else 0, 1, -48)
		end
	end
	conn:Disconnect()
	body.Text = text
	body.MaxVisibleGraphemes = -1
	ghostA.TextTransparency = 1
	ghostB.TextTransparency = 1
	panel.Position = UDim2.new(0.5, 0, 1, -48)
	if onSpeaker then
		onSpeaker(nil)
	end
	if o.noWait then
		busy = false
		return
	end
	-- wait for the player (or auto continue)
	task.wait(0.12)
	arrow.TextTransparency = 0.3
	local done = false
	local conn2 = advanceSignal.Event:Connect(function()
		done = true
	end)
	local autoTime = if o.auto == true then 1.2 + total * 0.035 elseif type(o.auto) == "number" then o.auto else nil
	local t0 = os.clock()
	local lastGlitch = 0
	while not done do
		local dt = RunService.RenderStepped:Wait()
		arrow.Position = UDim2.new(1, -24, 1, -14 + math.sin(os.clock() * 6) * 3)
		if autoTime and os.clock() - t0 > autoTime then
			break
		end
		if glitch > 0 then
			lastGlitch += dt
			if lastGlitch > 0.08 then
				lastGlitch = 0
				local g = math.random() < glitch * 0.12
				body.Text = if g then corrupt(text, glitch * 0.3) else text
				ghostA.TextTransparency = if g then 0.5 else 1
				ghostB.TextTransparency = if g then 0.5 else 1
			end
		end
	end
	conn2:Disconnect()
	body.Text = text
	ghostA.TextTransparency = 1
	ghostB.TextTransparency = 1
	arrow.TextTransparency = 1
	busy = false
end

function Dialogue.hide()
	if panel then
		panel.Visible = false
	end
	busy = false
end

-- Show buttons, return the index of the picked option.
function Dialogue.choice(options: { any }): number
	build()
	for _, c in choiceHolder:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	choiceHolder.Visible = true
	local picked = 0
	local unlock = UI.new("TextButton", { Name = "Unlock", Modal = true, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = gui })
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local buttons = {}
	for i, opt in options do
		local b = UI.new("TextButton", {
			Name = "Choice" .. i,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = rgb(16, 18, 26),
			BackgroundTransparency = 0.1,
			Size = UDim2.fromOffset(470, 84),
			LayoutOrder = i,
			Parent = choiceHolder,
		}, { UI.corner(16), UI.stroke(2, rgb(250, 222, 70), 0.3, true) })
		UI.label({
			Text = tostring(i),
			Font = Enum.Font.GothamBlack,
			TextSize = 26,
			TextColor3 = rgb(16, 16, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = rgb(250, 222, 70),
			Position = UDim2.fromOffset(18, 21),
			Size = UDim2.fromOffset(42, 42),
			Parent = b,
		}, { UI.corner(10) })
		UI.label({
			Text = Lang.t(opt),
			Font = Enum.Font.GothamBold,
			TextSize = 28,
			TextColor3 = Color3.new(1, 1, 1),
			TextWrapped = true,
			Position = UDim2.fromOffset(78, 0),
			Size = UDim2.new(1, -96, 1, 0),
			Parent = b,
		})
		local scale = UI.new("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			Audio.play("UIHover")
			UI.tween(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
			UI.tween(b, 0.15, { BackgroundColor3 = rgb(40, 44, 60) })
		end)
		b.MouseLeave:Connect(function()
			UI.tween(scale, 0.15, { Scale = 1 })
			UI.tween(b, 0.15, { BackgroundColor3 = rgb(16, 18, 26) })
		end)
		b.Activated:Connect(function()
			if picked == 0 then
				picked = i
			end
		end)
		scale.Scale = 0
		UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, nil, 0.08 * i)
		table.insert(buttons, b)
	end
	local keyConn = UserInputService.InputBegan:Connect(function(input)
		local map = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.DPadLeft] = 1, [Enum.KeyCode.DPadRight] = 2 }
		local n = map[input.KeyCode]
		if n and n <= #options and picked == 0 then
			picked = n
		end
	end)
	while picked == 0 do
		RunService.RenderStepped:Wait()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	keyConn:Disconnect()
	Audio.play("UIClick")
	local chosen = buttons[picked]
	UI.tween(chosen, 0.12, { BackgroundColor3 = rgb(250, 222, 70) })
	task.wait(0.25)
	choiceHolder.Visible = false
	unlock:Destroy()
	UserInputService.MouseIconEnabled = false
	return picked
end

return Dialogue
