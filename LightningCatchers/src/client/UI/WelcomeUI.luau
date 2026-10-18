--!strict
-- "С возвращением!": пока игрока не было, Тесла-башня копила Вольты. Кнопка "Забрать" —
-- и молнии-монетки летят в счётчик Вольт.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local HUD = require(script.Parent.HUD)

local WelcomeUI = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local W, H = 620, 440
local COINS = 14
local OPEN_DELAY = 1.5

local win: UIKit.Window
local amountLabel: TextLabel
local amountScale: UIScale
local claimButton: TextButton
local claimed = false
local busy = false
local shown = false

-- слой для летящих монеток (над окнами)
local flyGui: ScreenGui
local layer: Frame
local coins: { TextLabel } = {}

local function buildFly()
	flyGui = UIKit.new("ScreenGui", {
		Name = "CoinFly",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 45,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	layer = UIKit.new("Frame", {
		Name = "Layer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = flyGui,
	}) :: Frame
	for i = 1, COINS do
		local coin = UIKit.label({
			Name = "Coin" .. i,
			Text = "⚡",
			Size = UDim2.fromOffset(44, 44),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextColor3 = Theme.Volt,
			MaxTextSize = 40,
			NoStroke = true,
			Visible = false,
			Parent = layer,
		})
		table.insert(coins, coin)
	end
end

local function centerOf(obj: GuiObject): Vector2
	local p = obj.AbsolutePosition + obj.AbsoluteSize / 2
	return p - layer.AbsolutePosition
end

-- Монетки разлетаются от кнопки и по очереди прилетают в счётчик Вольт
local function flyCoins(from: GuiObject)
	local target = HUD.voltsTarget()
	local a = centerOf(from)
	local b = if target then centerOf(target) else Vector2.new(layer.AbsoluteSize.X / 2, 30)
	for i, coin in coins do
		local burst = a + Vector2.new(math.random(-120, 120), math.random(-90, 50))
		coin.Position = UDim2.fromOffset(a.X, a.Y)
		coin.Rotation = math.random(-30, 30)
		coin.TextTransparency = 0
		coin.Visible = true
		UIKit.tween(coin, 0.28, { Position = UDim2.fromOffset(burst.X, burst.Y) }, Enum.EasingStyle.Quad)
		task.delay(0.3 + i * 0.05, function()
			local tw = UIKit.tween(coin, 0.45, { Position = UDim2.fromOffset(b.X, b.Y), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw.Completed:Once(function()
				coin.Visible = false
				Sounds.play("Coins")
				HUD.bumpVolts()
			end)
		end)
	end
end

local function claim()
	if claimed or busy then
		return
	end
	busy = true
	local ok, result = ClientState.request(Net.Actions.ClaimWelcome, nil)
	busy = false
	if not ok then
		Sounds.play("Error")
		return
	end
	claimed = true
	Sounds.play("Purchase")
	Juice.flash(Theme.Volt, 0.25)
	flyCoins(claimButton)
	if typeof(result) == "number" and result > 0 then
		ClientState.Toast:Fire("+" .. Format.short(result) .. " ⚡", "good")
	end
	if win.isOpen() then
		task.delay(0.25, function()
			win.close()
		end)
	end
end

local function build()
	local body = win.Body
	local icon = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(96, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		BackgroundColor3 = WHITE,
		Parent = body,
	}) :: Frame
	UIKit.round(icon)
	UIKit.stroke(icon, 3, Theme.Stroke)
	UIKit.gradient(icon, Theme.Volt:Lerp(WHITE, 0.3), Theme.Orange:Lerp(BLACK, 0.2))
	UIKit.label({
		Name = "Glyph",
		Text = "⚡",
		Size = UDim2.fromScale(0.66, 0.66),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 60,
		NoStroke = true,
		Parent = icon,
	})
	UIKit.label({
		Name = "Text",
		Text = "Пока тебя не было, станция накопила",
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.fromOffset(10, 108),
		MaxTextSize = 28,
		Parent = body,
	})
	amountLabel = UIKit.label({
		Name = "Amount",
		Text = "+0 ⚡",
		Size = UDim2.new(1, -40, 0, 70),
		Position = UDim2.fromOffset(20, 142),
		TextColor3 = Theme.Volt,
		FontFace = Theme.Font,
		MaxTextSize = 66,
		Parent = body,
	})
	amountScale = UIKit.new("UIScale", { Scale = 1, Parent = amountLabel }) :: UIScale
	claimButton = UIKit.button({
		Name = "Claim",
		Text = "Забрать",
		Icon = "🎁",
		Color = Theme.Green,
		Size = UDim2.fromOffset(320, 78),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		TextSize = 36,
		Parent = body,
	}, claim)
end

local function show(d: PlayerData.Data)
	if shown or d.Welcome <= 0 then
		return
	end
	shown = true
	task.delay(OPEN_DELAY, function()
		local data = ClientState.get()
		local amount = if data then data.Welcome else d.Welcome
		if amount <= 0 then
			return
		end
		amountLabel.Text = "+" .. Format.short(amount) .. " ⚡"
		win.open()
		amountScale.Scale = 0.4
		UIKit.tween(amountScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		Sounds.play("Notify")
	end)
end

function WelcomeUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Welcome",
		Title = "С возвращением!",
		Icon = "👋",
		Width = W,
		Height = H,
		Accent = Theme.ElectricDark,
		DisplayOrder = 22,
		OnOpen = function()
			ClientState.WindowOpened:Fire("Welcome")
		end,
		OnClose = function()
			ClientState.WindowClosed:Fire("Welcome")
			-- закрыл крестиком — накопленное всё равно забираем, чтобы не пропало
			if not claimed then
				task.spawn(claim)
			end
		end,
	})
	build()
	buildFly()

	-- только по первому снимку данных в этой сессии
	local d = ClientState.get()
	if d then
		show(d)
	else
		ClientState.Changed:Once(function(data: PlayerData.Data)
			show(data)
		end)
	end
end

return WelcomeUI
