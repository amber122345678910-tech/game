--!strict
-- Обучение: короткие шаги с подсказкой-пузырём и прыгающей стрелкой на нужную кнопку.
-- После завершения включается стрелка к бункеру (Waypoint).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local TutorialUI = {}

type Step = {
	Text: string,
	Target: (() -> string?)?,
	Button: string?,
	Done: (() -> boolean)?,
	SkipIf: (() -> boolean)?,
}

local gui: ScreenGui
local bubble: Frame
local bubbleText: TextLabel
local nextButton: TextButton
local stepLabel: TextLabel
local arrow: TextLabel

local buttonPressed = false
local skipped = false
local running = false
local completedLocally = false

local function starterClaimed(): boolean
	local data = ClientState.Data
	return data ~= nil and data.StarterClaimed
end

local STEPS: { Step } = {
	{
		Text = "Добро пожаловать в «Симулятор Бункера»! 🌩\nСкоро на тебя обрушится шторм: сначала град, потом кислотный дождь. Построй бункер, чтобы выжить!",
		Button = "Поехали!",
	},
	{
		Text = "Открой магазин 🛒 — там продаются блоки и готовые бункеры.",
		Target = function()
			return "ShopButton"
		end,
		Done = function()
			return ClientState.ShopOpen
		end,
		SkipIf = starterClaimed,
	},
	{
		Text = "Открой вкладку «Бункеры» 🏠",
		Target = function()
			if not ClientState.ShopOpen then
				return "ShopButton"
			end
			return "TabBunkers"
		end,
		Done = function()
			return ClientState.ShopOpen and ClientState.ShopTab == "Bunkers"
		end,
		SkipIf = starterClaimed,
	},
	{
		Text = "Забери бесплатную «Стартовую хижину» 🎁 — она сразу построится на твоём участке!",
		Target = function()
			if not ClientState.ShopOpen then
				return "ShopButton"
			elseif ClientState.ShopTab ~= "Bunkers" then
				return "TabBunkers"
			end
			return "StarterBuy"
		end,
		Done = starterClaimed,
		SkipIf = starterClaimed,
	},
	{
		Text = "Отлично! Твой бункер построен. Закрой магазин.",
		Target = function()
			return "ShopClose"
		end,
		Done = function()
			return not ClientState.ShopOpen
		end,
	},
	{
		Text = "Кнопка «Строить» 🔨 — ставь и убирай блоки, улучшай бункер.\nМеталл крепок против града, но кислота его разъедает! Двери сдерживают кислоту по-разному.",
		Target = function()
			return "BuildButton"
		end,
		Button = "Понятно",
	},
	{
		Text = "Теперь иди к своему бункеру по стрелке ➜, зайди внутрь и нажми «Начать шторм»!",
		Button = "Вперёд!",
	},
}

local function isShown(obj: GuiObject?): boolean
	local current: Instance? = obj
	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("ScreenGui") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

local currentTarget: (() -> string?)? = nil

-- Позиционирование пузыря и стрелки возле цели (в пикселях экрана).
local function layout()
	local s = UIKit.currentHudScale()
	local bw, bh = math.floor(470 * s), math.floor(170 * s)
	bubble.Size = UDim2.fromOffset(bw, bh)
	local arrowSize = math.floor(64 * s)
	arrow.Size = UDim2.fromOffset(arrowSize, arrowSize)
	local screen = gui.AbsoluteSize
	local targetName = if currentTarget then currentTarget() else nil
	local target = if targetName then ClientState.Elements[targetName] else nil
	if not target or not isShown(target) then
		arrow.Visible = false
		bubble.AnchorPoint = Vector2.new(0.5, 1)
		bubble.Position = UDim2.new(0.5, 0, 1, -math.floor(24 * s))
		return
	end
	arrow.Visible = true
	-- в координатах своего ScreenGui (одинаково работает при любых отступах экрана)
	local pos = target.AbsolutePosition - gui.AbsolutePosition
	local size = target.AbsoluteSize
	local center = pos + size / 2
	local bob = math.sin(os.clock() * 6) * 8 * s
	local gap = math.floor(10 * s)
	if center.X < screen.X * 0.3 then
		-- цель слева: стрелка справа от цели, пузырь ещё правее
		arrow.Text = "◀"
		arrow.AnchorPoint = Vector2.new(0, 0.5)
		arrow.Position = UDim2.fromOffset(pos.X + size.X + gap + bob, center.Y)
		bubble.AnchorPoint = Vector2.new(0, 0.5)
		local bx = pos.X + size.X + gap + arrowSize + gap
		local by = math.clamp(center.Y, bh / 2 + 4, screen.Y - bh / 2 - 4)
		bubble.Position = UDim2.fromOffset(bx, by)
	elseif center.Y < screen.Y * 0.5 then
		-- цель сверху: стрелка под целью, пузырь ниже
		arrow.Text = "▲"
		arrow.AnchorPoint = Vector2.new(0.5, 0)
		arrow.Position = UDim2.fromOffset(center.X, pos.Y + size.Y + gap + bob)
		bubble.AnchorPoint = Vector2.new(0.5, 0)
		local bx = math.clamp(center.X, bw / 2 + 4, screen.X - bw / 2 - 4)
		bubble.Position = UDim2.fromOffset(bx, pos.Y + size.Y + gap + arrowSize + gap)
	else
		-- цель снизу: стрелка над целью, пузырь выше
		arrow.Text = "▼"
		arrow.AnchorPoint = Vector2.new(0.5, 1)
		arrow.Position = UDim2.fromOffset(center.X, pos.Y - gap + bob)
		bubble.AnchorPoint = Vector2.new(0.5, 1)
		local bx = math.clamp(center.X, bw / 2 + 4, screen.X - bw / 2 - 4)
		bubble.Position = UDim2.fromOffset(bx, math.max(pos.Y - gap - arrowSize - gap, bh + 4))
	end
end

local function finish()
	running = false
	completedLocally = true
	gui.Enabled = false
	ClientState.TutorialActive = false
	ClientState.TutorialChanged:Fire(false)
	Remotes.TutorialDone:FireServer()
end

local function run()
	if running then
		return
	end
	running = true
	skipped = false
	ClientState.TutorialActive = true
	ClientState.TutorialChanged:Fire(true)
	gui.Enabled = true
	local total = #STEPS
	for index, step in STEPS do
		if skipped then
			break
		end
		if step.SkipIf and step.SkipIf() then
			continue
		end
		bubbleText.Text = step.Text
		stepLabel.Text = string.format("%d/%d", index, total)
		currentTarget = step.Target
		nextButton.Visible = step.Button ~= nil
		if step.Button then
			UIKit.setButtonText(nextButton, step.Button)
		end
		buttonPressed = false
		while not skipped do
			if step.Button and buttonPressed then
				break
			end
			if step.Done and step.Done() then
				break
			end
			task.wait(0.15)
		end
	end
	currentTarget = nil
	finish()
end

function TutorialUI.init()
	gui = UIKit.new("ScreenGui", {
		Name = "BunkerTutorial",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	bubble = UIKit.panel({
		Name = "Bubble",
		Size = UDim2.fromOffset(470, 170),
		BackgroundColor3 = Theme.PanelLight,
		Parent = gui,
	})
	local stroke = bubble:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Yellow
	end
	bubbleText = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -24, 0.62, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = Theme.FontBold,
		MaxTextSize = 24,
		Parent = bubble,
	})
	stepLabel = UIKit.label({
		Name = "Step",
		Text = "",
		Size = UDim2.new(0.2, 0, 0.2, 0),
		Position = UDim2.new(0, 12, 1, -8),
		AnchorPoint = Vector2.new(0, 1),
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		Parent = bubble,
	})
	nextButton = UIKit.button({
		Name = "Next",
		Text = "Далее",
		Color = Theme.Green,
		Size = UDim2.new(0.38, 0, 0.26, 0),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 24,
		Parent = bubble,
	}, function()
		buttonPressed = true
	end)
	UIKit.button({
		Name = "Skip",
		Text = "Пропустить",
		Color = Theme.GrayDark,
		Size = UDim2.new(0.26, 0, 0.2, 0),
		Position = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 16,
		Parent = bubble,
	}, function()
		skipped = true
	end)
	arrow = UIKit.label({
		Name = "Arrow",
		Text = "▼",
		Size = UDim2.fromOffset(64, 64),
		TextColor3 = Theme.Yellow,
		MaxTextSize = 64,
		Visible = false,
		Parent = gui,
	})

	RunService.PreRender:Connect(function()
		if gui.Enabled then
			layout()
		end
	end)

	local function check(data: Remotes.DataSnapshot)
		if not data.TutorialDone and not running and not completedLocally then
			task.spawn(run)
		end
	end
	ClientState.DataChanged:Connect(check)
	if ClientState.Data then
		check(ClientState.Data)
	end
end

function TutorialUI.isRunning(): boolean
	return running
end

return TutorialUI
