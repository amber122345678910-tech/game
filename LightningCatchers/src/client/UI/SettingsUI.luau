--!strict
-- Настройки: язык, музыка, звуки, мягкие вспышки, тряска камеры, задержка касания (с автоподстройкой).
-- Меняется сразу у игрока, на сервер уходит полный набор настроек (с небольшой задержкой).
-- Язык (Settings.Lang) применяется после перезахода: окна строят тексты один раз при старте (Main.client).
-- Единственный владелец включения музыки/звуков (Sounds.setMusicEnabled / setSfxEnabled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Loc = require(Shared:WaitForChild("Loc"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local SettingsUI = {}

local WHITE = Color3.new(1, 1, 1)
local W, H = 660, 680
local ROW_W = 612
local OFFSET_STEP = 10 -- мс
local SAVE_DELAY = 0.6
local LANG_W = 232 -- ширина выбора языка

type Settings = { Music: boolean, Sfx: boolean, SoftFlash: boolean, Shake: boolean, Offset: number, Lang: string }
type Toggle = { key: string, button: TextButton, knob: Frame, label: TextLabel, grad: UIGradient }
type LangOption = { lang: Loc.Lang, label: TextLabel }

local ROW_ACCENTS = {
	Music = Theme.Pink,
	Sfx = Theme.Spark,
	SoftFlash = Theme.Volt,
	Shake = Theme.Orange,
} :: { [string]: Color3 }

-- Варианты языка подписаны каждый на своём языке и не переводятся
local LANGS: { { lang: Loc.Lang, text: string } } = {
	{ lang = "en", text = "English" }, -- noloc
	{ lang = "ru", text = "Русский" }, -- noloc
}

local win: UIKit.Window
local settings: Settings = { Music = true, Sfx = true, SoftFlash = true, Shake = true, Offset = 0, Lang = "" }
local toggles: { Toggle } = {}
local offsetLabel: TextLabel
local langPill: Frame
local langOptions: { LangOption } = {}
local langChoice: Loc.Lang? = nil -- язык, выбранный в этой сессии (nil — показываем текущий, Loc.lang())
local saveToken = 0
local pendingSave = false
local appliedOnce = false

local function maxOffset(): number
	return math.floor(Config.Catch.MaxCalibration * 1000 + 0.5)
end

local function copySettings(s: Settings): Settings
	return { Music = s.Music, Sfx = s.Sfx, SoftFlash = s.SoftFlash, Shake = s.Shake, Offset = s.Offset, Lang = s.Lang }
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
		return Loc.t("+%d мс", ms)
	end
	return Loc.t("%d мс", ms)
end

local function refreshControls()
	for _, t in toggles do
		local on = (settings :: any)[t.key] == true
		UIKit.tween(t.knob, 0.15, { Position = if on then UDim2.new(1, -5, 0.5, -2) else UDim2.new(0, 5, 0.5, -2), AnchorPoint = if on then Vector2.new(1, 0.5) else Vector2.new(0, 0.5) })
		t.grad.Color = if on
			then ColorSequence.new(Theme.Go:Lerp(Theme.GoHi, 0.4), Theme.GoLo)
			else ColorSequence.new(Theme.Well, Theme.Well)
		t.label.Text = if on then Loc.t("ВКЛ") else Loc.t("ВЫКЛ")
		t.label.TextColor3 = if on then Theme.Cream else Theme.TextDim
		t.label.Position = if on then UDim2.new(0, 14, 0.5, 0) else UDim2.new(1, -14, 0.5, 0)
		t.label.AnchorPoint = if on then Vector2.new(0, 0.5) else Vector2.new(1, 0.5)
		local s = t.label:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = on
		end
	end
	offsetLabel.Text = offsetText(settings.Offset)
	-- язык: плашка Go под выбранным вариантом
	local lang = langChoice or Loc.lang()
	for i, o in langOptions do
		local on = o.lang == lang
		if on then
			UIKit.tween(langPill, 0.15, { Position = UDim2.new((i - 1) * 0.5, if i == 1 then 5 else 2, 0.5, -2) })
		end
		o.label.TextColor3 = if on then Theme.Cream else Theme.TextDim
		local s = o.label:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = on
		end
	end
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
local function rowFrame(parent: Instance, order: number, icon: string, text: string, accent: Color3): Frame
	local row = UIKit.card({
		Name = "Row" .. order,
		Size = UDim2.fromOffset(ROW_W, 72),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.iconBadge(row, icon, accent, 46, {
		Name = "Icon",
		Position = UDim2.new(0, 36, 0.5, 0),
	})
	UIKit.label({
		Name = "Title",
		Text = text,
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -320, 1, -16),
		Position = UDim2.new(0, 70, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = row,
	})
	return row
end

-- Переключатель (§8.4: меньше пилюль): трек-колодец со скруглением 10, квадратная ручка Cream, ВКЛ/ВЫКЛ
local function toggleRow(parent: Instance, order: number, key: string, icon: string, text: string)
	local row = rowFrame(parent, order, icon, text, ROW_ACCENTS[key] or Theme.Slate)
	local button = UIKit.new("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(150, 54),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}) :: TextButton
	UIKit.corner(button, 10)
	UIKit.stroke(button, 2.5, Theme.Ink)
	local grad = UIKit.gradient(button, Theme.Go, Theme.GoLo)
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(52, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, -2),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	UIKit.corner(knob, 8)
	UIKit.stroke(knob, 2.5, Theme.Ink)
	UIKit.gradient(knob, Theme.Cream, Theme.TextDim)
	local label = UIKit.label({
		Name = "State",
		Text = Loc.t("ВКЛ"),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(76, 32),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = 20,
		NoStroke = false,
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

-- Язык сохраняется в настройках и включится после перезахода — подсказка сразу на обоих языках
local function chooseLang(lang: Loc.Lang)
	if lang == (langChoice or Loc.lang()) then
		return
	end
	UIKit.playClick()
	langChoice = lang
	settings.Lang = lang
	refreshControls()
	applyLocal()
	scheduleSave()
	if lang ~= Loc.lang() then
		ClientState.Toast:Fire("Язык сменится после перезахода\nLanguage changes after rejoin", "info") -- noloc
	end
end

-- Выбор языка: колодец, как у переключателя, и квадратная плашка Go под выбранным вариантом
local function langRow(parent: Instance, order: number)
	local row = rowFrame(parent, order, "🌐", Loc.t("Язык"), Theme.Go)
	local track = UIKit.new("Frame", {
		Name = "Lang",
		Size = UDim2.fromOffset(LANG_W, 54),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		BackgroundColor3 = Theme.Well,
		Parent = row,
	}) :: Frame
	UIKit.corner(track, 10)
	UIKit.stroke(track, 2.5, Theme.Ink)
	langPill = UIKit.new("Frame", {
		Name = "Pill",
		Size = UDim2.new(0.5, -7, 0, 40),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, -2),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = track,
	}) :: Frame
	UIKit.corner(langPill, 8)
	UIKit.stroke(langPill, 2.5, Theme.Ink)
	UIKit.gradient(langPill, Theme.Go:Lerp(Theme.GoHi, 0.4), Theme.GoLo)
	for i, opt in LANGS do
		local button = UIKit.new("TextButton", {
			Name = "Lang_" .. opt.lang,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale((i - 1) * 0.5, 0),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 3,
			Parent = track,
		}) :: TextButton
		local label = UIKit.label({
			Name = "Text",
			Text = opt.text,
			FontFace = Theme.FontBodyHeavy,
			Size = UDim2.new(1, -16, 0, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, -2),
			MaxTextSize = 20,
			NoStroke = false,
			ZIndex = 3,
			Parent = button,
		})
		button.Activated:Connect(function()
			chooseLang(opt.lang)
		end)
		table.insert(langOptions, { lang = opt.lang, label = label })
	end
end

local function offsetRow(parent: Instance, order: number)
	local row = rowFrame(parent, order, "⏱", Loc.t("Задержка касания"), Theme.Violet)
	local minus = UIKit.button({
		Name = "Minus",
		Text = "",
		Icon = "#minus",
		Color = Theme.Spark,
		Size = UDim2.fromOffset(62, 60),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -198, 0.5, 0),
		Parent = row,
	}, function()
		setOffset(settings.Offset - OFFSET_STEP)
	end)
	offsetLabel = UIKit.label({
		Name = "Value",
		Text = offsetText(0),
		FontFace = Theme.FontNumber,
		Size = UDim2.fromOffset(110, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -82, 0.5, 0),
		MaxTextSize = 30,
		NoStroke = false,
		Parent = row,
	})
	UIKit.gradientText(offsetLabel, Theme.VoltHi, Theme.Volt)
	local plus = UIKit.button({
		Name = "Plus",
		Text = "",
		Icon = "#plus",
		Color = Theme.Spark,
		Size = UDim2.fromOffset(62, 60),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Parent = row,
	}, function()
		setOffset(settings.Offset + OFFSET_STEP)
	end)
	-- глифы «−» и «+» по центру кнопок
	for _, b in { minus, plus } do
		local face = b:FindFirstChild("Face")
		local g = face and face:FindFirstChild("IconGlyph")
		if g and g:IsA("Frame") then
			g.Position = UDim2.fromScale(0.5, 0.5)
			g.Size = UDim2.fromScale(0.5, 0.5)
		end
	end
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
		ClientState.Toast:Fire(Loc.t("Сначала поймай несколько молний!"), "info")
		return
	end
	local m = maxOffset()
	local ms = math.clamp(math.floor(-avg * 1000 / OFFSET_STEP + 0.5) * OFFSET_STEP, -m, m)
	setOffset(ms)
	Sounds.play("PowerUp")
	ClientState.Toast:Fire(Loc.t("Задержка: %s", offsetText(settings.Offset)), "good")
end

local function build()
	local list = UIKit.new("Frame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = win.Body,
	}) :: Frame
	UIKit.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	langRow(list, 0)
	toggleRow(list, 1, "Music", "🎵", Loc.t("Музыка"))
	toggleRow(list, 2, "Sfx", "🔊", Loc.t("Звуки"))
	toggleRow(list, 3, "SoftFlash", "✨", Loc.t("Мягкие вспышки"))
	toggleRow(list, 4, "Shake", "📳", Loc.t("Тряска камеры"))
	offsetRow(list, 5)
	local auto = UIKit.button({
		Name = "Auto",
		Text = Loc.t("Подстроить автоматически"),
		Icon = "#bolt",
		Color = Theme.Violet,
		Size = UDim2.fromOffset(ROW_W, 64),
		LayoutOrder = 6,
		TextSize = 24,
		Parent = list,
	}, autoCalibrate)
	UIKit.setButtonStyle(auto, "plain")
	UIKit.setButtonText(auto, Loc.t("Подстроить автоматически"))
	UIKit.label({
		Name = "Hint",
		Text = Loc.t("Не выходит ИДЕАЛЬНО? Поймай пару молний и нажми «Подстроить»."),
		Size = UDim2.fromOffset(ROW_W, 26),
		LayoutOrder = 7,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
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
	local changed = s.Music ~= settings.Music or s.Sfx ~= settings.Sfx or s.SoftFlash ~= settings.SoftFlash or s.Shake ~= settings.Shake or s.Offset ~= settings.Offset or s.Lang ~= settings.Lang
	if not changed and appliedOnce then
		return
	end
	appliedOnce = true
	settings = copySettings(s)
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
		Title = Loc.t("Настройки"),
		Icon = "⚙",
		Width = W,
		Height = H,
		Accent = Theme.Slate,
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
