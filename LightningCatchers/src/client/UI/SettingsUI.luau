--!strict
-- Настройки: музыка, звуки, мягкие вспышки, тряска камеры, задержка касания (с автоподстройкой).
-- Меняется сразу у игрока, на сервер уходит полный набор настроек (с небольшой задержкой).
-- Единственный владелец включения музыки/звуков (Sounds.setMusicEnabled / setSfxEnabled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local SettingsUI = {}

local WHITE = Color3.new(1, 1, 1)
local W, H = 660, 600
local ROW_W = 612
local OFFSET_STEP = 10 -- мс
local SAVE_DELAY = 0.6

type Settings = { Music: boolean, Sfx: boolean, SoftFlash: boolean, Shake: boolean, Offset: number }
type Toggle = { key: string, button: TextButton, knob: Frame, label: TextLabel, grad: UIGradient }

local win: UIKit.Window
local settings: Settings = { Music = true, Sfx = true, SoftFlash = true, Shake = true, Offset = 0 }
local toggles: { Toggle } = {}
local offsetLabel: TextLabel
local saveToken = 0
local pendingSave = false
local appliedOnce = false

local function maxOffset(): number
	return math.floor(Config.Catch.MaxCalibration * 1000 + 0.5)
end

local function copySettings(s: Settings): Settings
	return { Music = s.Music, Sfx = s.Sfx, SoftFlash = s.SoftFlash, Shake = s.Shake, Offset = s.Offset }
end

-- Звук включается/выключается сразу; остальные настройки читают контроллеры из данных
local function applyLocal()
	Sounds.setMusicEnabled(settings.Music)
	Sounds.setSfxEnabled(settings.Sfx)
	local d = ClientState.get()
	if d then
		d.Settings = copySettings(settings)
	end
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	pendingSave = true
	task.delay(SAVE_DELAY, function()
		if token ~= saveToken then
			return
		end
		local ok = ClientState.request(Net.Actions.SetSettings, copySettings(settings))
		if token == saveToken then
			pendingSave = false
		end
		if not ok then
			Sounds.play("Error")
		end
	end)
end

local function offsetText(ms: number): string
	if ms > 0 then
		return string.format("+%d мс", ms)
	end
	return string.format("%d мс", ms)
end

local function refreshControls()
	for _, t in toggles do
		local on = (settings :: any)[t.key] == true
		UIKit.tween(t.knob, 0.15, { Position = if on then UDim2.new(1, -4, 0.5, 0) else UDim2.new(0, 4, 0.5, 0), AnchorPoint = if on then Vector2.new(1, 0.5) else Vector2.new(0, 0.5) })
		t.grad.Color = if on
			then ColorSequence.new(Theme.Green:Lerp(WHITE, 0.2), Theme.GreenDark)
			else ColorSequence.new(Theme.Gray, Theme.GrayDark)
		t.label.Text = if on then "ВКЛ" else "ВЫКЛ"
		t.label.Position = if on then UDim2.new(0, 14, 0.5, 0) else UDim2.new(1, -14, 0.5, 0)
		t.label.AnchorPoint = if on then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
	end
	offsetLabel.Text = offsetText(settings.Offset)
end

local function setOffset(ms: number)
	local m = maxOffset()
	settings.Offset = math.clamp(math.floor(ms / OFFSET_STEP + 0.5) * OFFSET_STEP, -m, m)
	refreshControls()
	applyLocal()
	scheduleSave()
end

----------------------------------------------------------------------
-- Строки
----------------------------------------------------------------------
local function rowFrame(parent: Instance, order: number, icon: string, text: string): Frame
	local row = UIKit.card({
		Name = "Row" .. order,
		Size = UDim2.fromOffset(ROW_W, 72),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.label({
		Name = "Title",
		Text = icon .. "  " .. text,
		Size = UDim2.new(1, -260, 1, -12),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = row,
	})
	return row
end

local function toggleRow(parent: Instance, order: number, key: string, icon: string, text: string)
	local row = rowFrame(parent, order, icon, text)
	local button = UIKit.new("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(150, 58),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}) :: TextButton
	UIKit.round(button)
	UIKit.stroke(button, 3, Theme.Stroke)
	local grad = UIKit.gradient(button, Theme.Green, Theme.GreenDark)
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(50, 50),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	UIKit.round(knob)
	UIKit.stroke(knob, 2.5, Theme.Stroke)
	local label = UIKit.label({
		Name = "State",
		Text = "ВКЛ",
		Size = UDim2.fromOffset(80, 36),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 24,
		ZIndex = 2,
		Parent = button,
	})
	button.Activated:Connect(function()
		UIKit.playClick()
		local s = settings :: any
		s[key] = not (s[key] == true)
		refreshControls()
		applyLocal()
		scheduleSave()
	end)
	table.insert(toggles, { key = key, button = button, knob = knob, label = label, grad = grad })
end

local function offsetRow(parent: Instance, order: number)
	local row = rowFrame(parent, order, "⏱", "Задержка касания")
	UIKit.button({
		Name = "Minus",
		Text = "−",
		Color = Theme.Electric,
		Size = UDim2.fromOffset(64, 62),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -198, 0.5, 0),
		TextSize = 36,
		Parent = row,
	}, function()
		setOffset(settings.Offset - OFFSET_STEP)
	end)
	offsetLabel = UIKit.label({
		Name = "Value",
		Text = "0 мс",
		Size = UDim2.fromOffset(110, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -82, 0.5, 0),
		TextColor3 = Theme.Volt,
		MaxTextSize = 28,
		Parent = row,
	})
	UIKit.button({
		Name = "Plus",
		Text = "+",
		Color = Theme.Electric,
		Size = UDim2.fromOffset(64, 62),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		TextSize = 36,
		Parent = row,
	}, function()
		setOffset(settings.Offset + OFFSET_STEP)
	end)
end

-- Автоподстройка: средняя ошибка последних нажатий из CatchController (если он умеет)
local function autoCalibrate()
	local controllers = script.Parent.Parent:FindFirstChild("Controllers")
	local mod = if controllers then controllers:FindFirstChild("CatchController") else nil
	local avg: any = nil
	if mod and mod:IsA("ModuleScript") then
		local ok, cc = pcall((require :: any), mod)
		if ok and typeof(cc) == "table" and typeof(cc.averageError) == "function" then
			local ok2, v = pcall(cc.averageError)
			if ok2 then
				avg = v
			end
		end
	end
	if typeof(avg) ~= "number" or avg ~= avg then
		Sounds.play("Error")
		ClientState.Toast:Fire("Сначала поймай несколько молний!", "info")
		return
	end
	local m = maxOffset()
	local ms = math.clamp(math.floor(-avg * 1000 / OFFSET_STEP + 0.5) * OFFSET_STEP, -m, m)
	setOffset(ms)
	Sounds.play("PowerUp")
	ClientState.Toast:Fire("Задержка: " .. offsetText(settings.Offset), "good")
end

local function build()
	local list = UIKit.new("Frame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = win.Body,
	}) :: Frame
	UIKit.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	toggleRow(list, 1, "Music", "🎵", "Музыка")
	toggleRow(list, 2, "Sfx", "🔊", "Звуки")
	toggleRow(list, 3, "SoftFlash", "✨", "Мягкие вспышки")
	toggleRow(list, 4, "Shake", "📳", "Тряска камеры")
	offsetRow(list, 5)
	UIKit.button({
		Name = "Auto",
		Text = "Подстроить автоматически",
		Icon = "🎯",
		Color = Theme.Purple,
		Size = UDim2.fromOffset(ROW_W, 64),
		LayoutOrder = 6,
		TextSize = 26,
		Parent = list,
	}, autoCalibrate)
	UIKit.label({
		Name = "Hint",
		Text = "Не выходит ИДЕАЛЬНО? Поймай пару молний и нажми «Подстроить».",
		Size = UDim2.fromOffset(ROW_W, 26),
		LayoutOrder = 7,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 19,
		Parent = list,
	})
end

-- Подхватить настройки из данных сервера (если игрок сейчас ничего не меняет).
-- Пока переключение не сохранено, свежий снимок с сервера ещё со старыми настройками: оставляем свои
-- (и в зеркале данных — их читают тряска, вспышки и поправка задержки).
local function syncFromData(d: PlayerData.Data)
	if pendingSave then
		d.Settings = copySettings(settings)
		return
	end
	local s = d.Settings
	local changed = s.Music ~= settings.Music or s.Sfx ~= settings.Sfx or s.SoftFlash ~= settings.SoftFlash or s.Shake ~= settings.Shake or s.Offset ~= settings.Offset
	if not changed and appliedOnce then
		return
	end
	appliedOnce = true
	settings = { Music = s.Music, Sfx = s.Sfx, SoftFlash = s.SoftFlash, Shake = s.Shake, Offset = s.Offset }
	Sounds.setMusicEnabled(settings.Music)
	Sounds.setSfxEnabled(settings.Sfx)
	if win.isOpen() then
		refreshControls()
	end
end

function SettingsUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Settings",
		Title = "Настройки",
		Icon = "⚙",
		Width = W,
		Height = H,
		Accent = Theme.GrayDark,
		OnOpen = function()
			local d = ClientState.get()
			if d then
				syncFromData(d)
			end
			refreshControls()
			ClientState.WindowOpened:Fire("Settings")
		end,
		OnClose = function()
			ClientState.WindowClosed:Fire("Settings")
		end,
	})
	build()
	refreshControls()

	ClientState.Changed:Connect(syncFromData)
	local d = ClientState.get()
	if d then
		syncFromData(d)
	end
	ClientState.OpenWindow:Connect(function(name: string)
		local base = UIKit.parseWindowName(name)
		if base == "Settings" then
			win.open()
		end
	end)
end

function SettingsUI.open()
	if win then
		win.open()
	end
end

return SettingsUI
