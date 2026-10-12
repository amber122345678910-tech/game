--!strict
-- Настройки: ползунки яркости/музыки/эффектов (мышь и палец), переключатели покачивания камеры,
-- зерна плёнки и подсказок, язык EN/RU. Изменения сразу идут в ClientState.setSetting,
-- при закрытии — ClientState.saveSettings(). Шестерёнка в правом верхнем углу видна всегда.
-- Смена языка: Locale.setLanguage + SettingsChanged, по которому остальные модули перерисовывают подписи.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local SettingsUI = {}

local DESIGN_W, DESIGN_H = 640, 470
local ROW_H = 56
local GEAR_MOUSE, GEAR_TOUCH = 44, 64

local modal: UIKit.Modal
local gearButton: TextButton
local rowsHolder: ScrollingFrame
local refreshers: { () -> () } = {}
local dirty = false

local function normalizeLang(code: any): string
	return if type(code) == "string" and string.sub(string.lower(code), 1, 2) == "ru" then "ru" else "en"
end

local function numberSetting(key: string, default: number): number
	local v = ClientState.Settings[key]
	return if type(v) == "number" then math.clamp(v, 0, 1) else default
end

local function boolSetting(key: string, default: boolean): boolean
	local v = ClientState.Settings[key]
	return if type(v) == "boolean" then v else default
end

-- Эффективное состояние подсказок: явная настройка, иначе — только для новичка.
local function tipsEnabled(): boolean
	local v = ClientState.Settings.ShowTips
	if type(v) == "boolean" then
		return v
	end
	return ClientState.Profile.NightsSurvived == 0
end

local function setSetting(key: string, value: any)
	dirty = true
	ClientState.setSetting(key, value)
end

----------------------------------------------------------------------
-- Строки
----------------------------------------------------------------------
local function makeRow(order: number, labelKey: string): (Frame, TextLabel)
	local row = UIKit.new("Frame", {
		Name = labelKey,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = Theme.Card,
		BackgroundTransparency = 0.5,
		LayoutOrder = order,
		Parent = rowsHolder,
	}) :: Frame
	UIKit.corner(row, 6)
	local label = UIKit.label({
		Name = "Label",
		Text = "",
		Size = UDim2.new(0.38, -12, 1, -8),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		MaxTextSize = 18,
		NoStroke = true,
		Parent = row,
	})
	table.insert(refreshers, function()
		UIKit.setText(label, Locale.t(labelKey))
	end)
	return row, label
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function slider(order: number, key: string, labelKey: string, default: number)
	local row = makeRow(order, labelKey)
	local holder, fill = UIKit.bar({
		Name = "Track",
		Size = UDim2.new(0.44, 0, 0, 12),
		Position = UDim2.new(0.4, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = row,
	}, Theme.Amber)
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Text,
		ZIndex = 2,
		Parent = holder,
	}) :: Frame
	UIKit.corner(knob, 11)
	UIKit.new("UIStroke", { Thickness = 1, Color = Theme.PanelStroke, Parent = knob })
	local valueLabel = UIKit.label({
		Name = "Value",
		Text = "",
		Size = UDim2.new(0.12, 0, 1, -8),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		NoStroke = true,
		Parent = row,
	})
	-- зона захвата выше и шире полоски — удобно пальцем
	local grab = UIKit.new("TextButton", {
		Name = "Grab",
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0.37, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
		Parent = row,
	}) :: TextButton

	local value = numberSetting(key, default)
	local dragging = false
	local lastSent = 0

	local function render()
		UIKit.setBar(fill, value)
		fill.Visible = true
		knob.Position = UDim2.fromScale(value, 0.5)
		UIKit.setText(valueLabel, string.format("%d%%", math.floor(value * 100 + 0.5)))
	end

	local function apply(final: boolean)
		local now = os.clock()
		if final or now - lastSent > 0.08 then
			lastSent = now
			setSetting(key, value)
		end
	end

	local function setFromX(x: number, final: boolean)
		local width = math.max(1, holder.AbsoluteSize.X)
		value = math.clamp((x - holder.AbsolutePosition.X) / width, 0, 1)
		render()
		apply(final)
	end

	grab.InputBegan:Connect(function(input: InputObject)
		if isPointer(input) then
			dragging = true
			setFromX(input.Position.X, false)
		end
	end)
	grab.InputEnded:Connect(function(input: InputObject)
		if isPointer(input) and dragging then
			dragging = false
			setFromX(input.Position.X, true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and isPointer(input) then
			dragging = false
			setFromX(input.Position.X, true)
		end
	end)

	table.insert(refreshers, function()
		if not dragging then
			value = numberSetting(key, default)
		end
		render()
	end)
	render()
end

local function toggle(order: number, labelKey: string, read: () -> boolean, write: (boolean) -> ())
	local row = makeRow(order, labelKey)
	local button = UIKit.button({
		Name = "Toggle",
		Text = "",
		Size = UDim2.fromOffset(140, ROW_H - 10),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 18,
		Parent = row,
	}, function()
		write(not read())
	end)
	local function render()
		local on = read()
		UIKit.setButtonText(button, Locale.t(if on then "On" else "Off"))
		UIKit.styleDark(button, if on then Theme.Amber else Theme.TextDim, if on then Theme.Card else Theme.PanelLight)
	end
	table.insert(refreshers, render)
	render()
end

local function languageRow(order: number)
	local row = makeRow(order, "Set_Language")
	local button = UIKit.button({
		Name = "Language",
		Text = "",
		Size = UDim2.fromOffset(180, ROW_H - 10),
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 18,
		Parent = row,
	}, function()
		local next = if Locale.getLanguage() == "ru" then "en" else "ru"
		Locale.setLanguage(next)
		setSetting("Language", next)
	end)
	UIKit.styleDark(button, Theme.Amber)
	table.insert(refreshers, function()
		UIKit.setButtonText(button, Locale.t(if Locale.getLanguage() == "ru" then "Lang_Ru" else "Lang_En"))
	end)
end

----------------------------------------------------------------------
-- Построение
----------------------------------------------------------------------
local function build()
	local gearGui = UIKit.new("ScreenGui", {
		Name = "SettingsGear",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 12,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	-- кнопка уже несёт свой UIScale (пружинка), поэтому масштаб HUD вешаем на держатель
	local gearHolder = UIKit.new("Frame", {
		Name = "GearHolder",
		Size = UDim2.fromOffset(GEAR_TOUCH, GEAR_TOUCH),
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = gearGui,
	}) :: Frame
	UIKit.autoScale(gearHolder, "hud")
	gearButton = UIKit.button({
		Name = "Gear",
		Text = "⚙",
		Size = UDim2.fromOffset(GEAR_MOUSE, GEAR_MOUSE),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
		Parent = gearHolder,
	}, function()
		SettingsUI.open()
	end)
	UIKit.styleDark(gearButton, Theme.TextDim)
	gearButton.BackgroundTransparency = 0.2

	local gui = UIKit.new("ScreenGui", {
		Name = "SettingsUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 60,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	modal = UIKit.modal({
		Name = "Settings",
		Width = DESIGN_W,
		Height = DESIGN_H,
		Parent = gui,
		OnClose = function()
			if dirty then
				dirty = false
				ClientState.saveSettings()
			end
		end,
	})
	rowsHolder = UIKit.new("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Gray,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = modal.Body,
	}) :: ScrollingFrame
	UIKit.list(rowsHolder, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	slider(1, "Brightness", "Set_Brightness", 0.5)
	slider(2, "Music", "Set_Music", 0.8)
	slider(3, "Sfx", "Set_Sfx", 1)
	toggle(4, "Set_HeadBob", function()
		return boolSetting("HeadBob", true)
	end, function(on)
		setSetting("HeadBob", on)
	end)
	toggle(5, "Set_Vhs", function()
		return boolSetting("Vhs", true)
	end, function(on)
		setSetting("Vhs", on)
	end)
	toggle(6, "Set_Tips", tipsEnabled, function(on)
		setSetting("ShowTips", on)
	end)
	languageRow(7)
end

local function relayout()
	local size = UIKit.touchPx(GEAR_MOUSE, GEAR_TOUCH)
	gearButton.Size = UDim2.fromOffset(size, size)
end

local function refreshAll()
	modal.Title.Text = Locale.t("Settings")
	for _, fn in refreshers do
		fn()
	end
end

----------------------------------------------------------------------
-- Публичное
----------------------------------------------------------------------
function SettingsUI.open()
	if modal.IsOpen then
		return
	end
	refreshAll()
	modal:Open()
	gearButton.Visible = false
end

function SettingsUI.close()
	modal:Hide()
end

function SettingsUI.init()
	build()
	relayout()
	UIKit.onLayoutChanged(relayout)
	refreshAll()

	local baseOnClose = modal.OnClose
	modal.OnClose = function()
		gearButton.Visible = true
		if baseOnClose then
			baseOnClose()
		end
	end

	ClientState.SettingsChanged:Connect(function(settings: { [string]: any })
		-- Язык из сохранённого профиля (или из другого источника): применяем и даём модулям перерисоваться.
		local saved = settings.Language
		if saved ~= nil and normalizeLang(saved) ~= Locale.getLanguage() then
			Locale.setLanguage(normalizeLang(saved))
			ClientState.SettingsChanged:Fire(ClientState.Settings)
			return
		end
		refreshAll()
	end)
	ClientState.ProfileChanged:Connect(refreshAll)
	GuiService.MenuOpened:Connect(function()
		modal:Hide()
	end)
end

return SettingsUI
