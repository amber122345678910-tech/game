--!strict
-- Экран результатов шторма.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local ResultsUI = {}

local DESIGN_W, DESIGN_H = 620, 520

local window: Frame
local windowScale: UIScale
local overlay: Frame
local title: TextLabel
local lines: { TextLabel } = {}
local tipLabel: TextLabel

local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function tipFor(result: Remotes.StormResult): string
	if result.Reason == "left" then
		return "Совет: не уходи со своего участка во время шторма."
	end
	if result.Survived then
		if result.BunkerPercent < 40 then
			return "Бункер еле выстоял! Купи блоки прочнее в магазине."
		end
		return "Следующий шторм будет сильнее — укрепи бункер!"
	end
	local params = Config.stormParams(result.Level)
	return string.format(
		"Совет: на этом уровне кислоты до %.1f ст. Нужна дверь, которая держит больше, и закрытая крыша.",
		params.PoolMax
	)
end

local function show(result: Remotes.StormResult)
	if result.Survived then
		title.Text = "🎉 ТЫ ВЫЖИЛ!"
		title.TextColor3 = Theme.Green
	elseif result.Reason == "left" then
		title.Text = "🏃 ТЫ УШЁЛ С УЧАСТКА"
		title.TextColor3 = Theme.Orange
	else
		title.Text = "💀 БУНКЕР НЕ СПАС"
		title.TextColor3 = Theme.Red
	end
	local texts = {
		"🌩 Уровень шторма: " .. result.Level,
		"🧱 Бункер уцелел: " .. result.BunkerPercent .. "%",
		"⏱ Продержался: " .. formatTime(result.Duration),
		"💰 Награда: +" .. UIKit.formatNumber(result.Reward),
		if result.Survived then "⬆ Новый уровень: " .. result.NewLevel else "🔁 Попробуй ещё раз!",
	}
	for i, label in lines do
		label.Text = texts[i] or ""
	end
	tipLabel.Text = tipFor(result)
	if ClientState.ShopOpen then
		ClientState.setShopOpen(false)
	end
	if ClientState.BuildMode then
		ClientState.setBuildMode(false)
	end
	ClientState.ModalOpen = true
	overlay.Visible = true
	Sounds.playUI(if result.Survived then "Success" else "Error")
	UIKit.popIn(window, windowScale)
end

local function hide()
	window.Visible = false
	overlay.Visible = false
	ClientState.ModalOpen = false
end

function ResultsUI.init()
	local gui = UIKit.new("ScreenGui", {
		Name = "BunkerResults",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 8,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	overlay = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		Active = true,
		Visible = false,
		Parent = gui,
	}) :: Frame
	window = UIKit.panel({
		Name = "Results",
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	windowScale = UIKit.autoScale(window, "modal", DESIGN_W, DESIGN_H)
	UIKit.gradient(window, Theme.PanelLight, Theme.Panel)
	title = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -40, 0, 64),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 48,
		Parent = window,
	})
	local list = UIKit.new("Frame", {
		Size = UDim2.new(1, -60, 0, 240),
		Position = UDim2.new(0.5, 0, 0, 92),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = window,
	})
	UIKit.list(list, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	for i = 1, 5 do
		table.insert(
			lines,
			UIKit.label({
				Text = "",
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if i == 4 then Theme.Yellow else Theme.Text,
				MaxTextSize = 30,
				LayoutOrder = i,
				Parent = list,
			})
		)
	end
	tipLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -60, 0, 60),
		Position = UDim2.new(0.5, 0, 0, 340),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		FontFace = Theme.FontBold,
		MaxTextSize = 20,
		Parent = window,
	})
	UIKit.button({
		Text = "Продолжить",
		Color = Theme.Green,
		Size = UDim2.fromOffset(300, 70),
		Position = UDim2.new(0.5, 0, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 32,
		Parent = window,
	}, hide)

	Remotes.StormResult.OnClientEvent:Connect(function(result: Remotes.StormResult)
		if typeof(result) == "table" then
			show(result)
		end
	end)
end

return ResultsUI
