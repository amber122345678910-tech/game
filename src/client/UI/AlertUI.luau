--!strict
-- Оповещение 21:00: баннер «телефона» сверху (вибрация 2–1–1 с дважды, PhoneBuzz, AlertTone один раз)
-- и EAS-карточка по центру: чёрная, моноширинный шрифт, текст печатается по буквам (40 зн/с),
-- затем правило и подпись. Первые две ночи правило дополнительно показывается крупно 4 с (онбординг).
-- Скрывается, когда фаза перестаёт быть Alert (конец или пропуск голосованием). Фоном тихая TV-статика.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Inmates = require(Shared:WaitForChild("Inmates"))
local Locale = require(Shared:WaitForChild("Locale"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local AlertUI = {}

local CHARS_PER_SECOND = 40
local BANNER_W = 520
local BANNER_TOP = 12
local CARD_W, CARD_H = 900, 310
local STATIC_VOLUME = 0.12

local gui: ScreenGui
local banner: Frame
local bannerHeader: TextLabel
local bannerTime: TextLabel
local bannerLines: Frame
local card: Frame
local cardScale: UIScale
local cardHeader: TextLabel
local cardBody: TextLabel
local cardRule: TextLabel
local cardFooter: TextLabel
local bigRule: TextLabel

local token = 0 -- номер показа: старые корутины завершаются сами
local shownAt = 0
local currentIds: { string } = {}
local staticSound: Sound? = nil

----------------------------------------------------------------------
-- Звук
----------------------------------------------------------------------
local function stopStatic()
	local s = staticSound
	staticSound = nil
	if s then
		s:Stop()
		s:Destroy()
	end
end

local function startStatic()
	stopStatic()
	local sounds = UIKit.controller("Sounds")
	if sounds and type(sounds.get) == "function" then
		local ok, source = pcall(sounds.get, "TvStatic")
		if ok and typeof(source) == "Instance" and source:IsA("Sound") then
			local clone = source:Clone()
			clone.Name = "TvStaticLoop"
			clone.Looped = true
			clone.Volume = STATIC_VOLUME
			clone.Parent = gui
			clone:Play()
			staticSound = clone
			return
		end
	end
	UIKit.playUI("TvStatic")
end

----------------------------------------------------------------------
-- Построение
----------------------------------------------------------------------
local function buildBanner()
	banner = UIKit.panel({
		Name = "Banner",
		Size = UDim2.fromOffset(BANNER_W, 120),
		Position = UDim2.new(0.5, 0, 0, -200),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	UIKit.thinStroke(banner, Theme.Amber, 0.35, 1)
	UIKit.autoScale(banner, "hud")
	UIKit.label({
		Name = "Icon",
		Text = "⚠",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(14, 10),
		TextColor3 = Theme.Red,
		MaxTextSize = 26,
		NoStroke = true,
		Parent = banner,
	})
	bannerHeader = UIKit.label({
		Name = "Header",
		Text = "",
		Size = UDim2.new(1, -170, 0, 34),
		Position = UDim2.fromOffset(52, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = banner,
	})
	bannerTime = UIKit.label({
		Name = "Time",
		Text = "",
		Size = UDim2.fromOffset(100, 34),
		Position = UDim2.new(1, -14, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = banner,
	})
	UIKit.new("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, -28, 0, 1),
		Position = UDim2.new(0.5, 0, 0, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Amber,
		BackgroundTransparency = 0.7,
		Parent = banner,
	})
	bannerLines = UIKit.new("Frame", {
		Name = "Lines",
		Size = UDim2.new(1, -28, 1, -62),
		Position = UDim2.fromOffset(14, 58),
		BackgroundTransparency = 1,
		Parent = banner,
	}) :: Frame
	UIKit.list(bannerLines, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
end

local function buildCard()
	card = UIKit.new("Frame", {
		Name = "EAS",
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Position = UDim2.new(0.5, 0, 0.44, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.04,
		Active = true,
		Visible = false,
		Parent = gui,
	}) :: Frame
	UIKit.corner(card, 2)
	UIKit.new("UIStroke", { Thickness = 2, Color = Theme.Red, Transparency = 0.35, Parent = card })
	cardScale = UIKit.autoScale(card, "modal", CARD_W, CARD_H)
	local band = UIKit.new("Frame", {
		Name = "Band",
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = Theme.RedDark,
		Parent = card,
	}) :: Frame
	cardHeader = UIKit.label({
		Name = "Header",
		Text = "",
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Text,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = band,
	})
	cardBody = UIKit.label({
		Name = "Body",
		Text = "",
		Size = UDim2.new(1, -40, 0, 150),
		Position = UDim2.fromOffset(20, 66),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Theme.FontMono,
		TextScaled = false,
		TextSize = 18,
		NoStroke = true,
		Parent = card,
	})
	cardRule = UIKit.label({
		Name = "Rule",
		Text = "",
		Size = UDim2.new(1, -40, 0, 48),
		Position = UDim2.fromOffset(20, 222),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 18,
		NoStroke = true,
		Parent = card,
	})
	cardFooter = UIKit.label({
		Name = "Footer",
		Text = "",
		Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		NoStroke = true,
		Parent = card,
	})

	local holder = UIKit.new("Frame", {
		Name = "BigRule",
		Size = UDim2.fromOffset(900, 100),
		Position = UDim2.new(0.5, 0, 0.8, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(holder, "hud")
	bigRule = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 34,
		Visible = false,
		Parent = holder,
	})
end

----------------------------------------------------------------------
-- Показ
----------------------------------------------------------------------
local function fillBannerLines(ids: { string })
	for _, child in bannerLines:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, id in ids do
		local def = Inmates.get(id)
		local number = if def then def.Number else "???"
		UIKit.label({
			Name = "Patient" .. i,
			Text = Locale.t("AlertPatient", number, Locale.inmateName(id)),
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.FontMono,
			TextColor3 = Theme.Text,
			MaxTextSize = 17,
			LayoutOrder = i * 2 - 1,
			NoStroke = true,
			Parent = bannerLines,
		})
		UIKit.label({
			Name = "Rule" .. i,
			Text = Locale.inmateRule(id),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.FontBody,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 15,
			LayoutOrder = i * 2,
			NoStroke = true,
			Parent = bannerLines,
		})
	end
	banner.Size = UDim2.fromOffset(BANNER_W, 66 + 50 * math.max(1, #ids))
end

-- Вибрация: 2 с – 1 с – 1 с, дважды; дрожим позицией баннера и играем PhoneBuzz на каждом импульсе.
local function buzz(my: number)
	task.wait(0.45) -- дождаться выезда баннера
	for _ = 1, 2 do
		for _, duration in { 2, 1, 1 } do
			if my ~= token then
				return
			end
			UIKit.playUI("PhoneBuzz")
			local t0 = os.clock()
			while os.clock() - t0 < duration and my == token do
				local dx = (math.random() - 0.5) * 6
				local dy = (math.random() - 0.5) * 4
				banner.Position = UDim2.new(0.5, dx, 0, BANNER_TOP + dy)
				task.wait(0.03)
			end
			banner.Position = UDim2.new(0.5, 0, 0, BANNER_TOP)
			task.wait(0.35)
		end
		task.wait(0.8)
	end
end

local function typewriter(my: number, rules: string)
	local total = utf8.len(cardBody.Text) or #cardBody.Text
	cardBody.MaxVisibleGraphemes = 0
	local t0 = os.clock()
	local shown = 0
	while shown < total and my == token do
		shown = math.min(total, math.floor((os.clock() - t0) * CHARS_PER_SECOND))
		cardBody.MaxVisibleGraphemes = shown
		task.wait()
	end
	if my ~= token then
		return
	end
	cardBody.MaxVisibleGraphemes = -1
	-- Онбординг: первые две ночи правило крупно на 4 с
	if ClientState.Snapshot.Night <= 2 then
		bigRule.Text = rules
		bigRule.TextTransparency = 0
		bigRule.Visible = true
		task.wait(4)
		if my ~= token then
			return
		end
		UIKit.tween(bigRule, 0.5, { TextTransparency = 1 })
		task.wait(0.5)
		if my == token then
			bigRule.Visible = false
		end
	end
end

local function relabelStatic()
	UIKit.setText(bannerHeader, Locale.t("AlertHeader"))
	UIKit.setText(cardFooter, Locale.t("AlertFooter"))
end

local function fillCard(ids: { string })
	local header = Locale.t("AlertEas")
	if #ids > 1 then
		header ..= "\n" .. Locale.t("AlertTwo")
	end
	cardHeader.Text = header
	local alerts: { string } = {}
	local rules: { string } = {}
	for _, id in ids do
		table.insert(alerts, Locale.inmateAlert(id))
		table.insert(rules, Locale.inmateRule(id))
	end
	cardBody.Text = table.concat(alerts, "\n\n")
	cardRule.Text = Locale.t("AlertRule") .. ": " .. table.concat(rules, " / ")
	relabelStatic()
	return table.concat(rules, "\n")
end

local function show(ids: { string })
	if #ids == 0 then
		return
	end
	token += 1
	local my = token
	currentIds = table.clone(ids)
	shownAt = os.clock()
	gui.Enabled = true

	-- баннер
	fillBannerLines(ids)
	UIKit.setText(bannerTime, ClientState.clockText())
	banner.Position = UDim2.new(0.5, 0, 0, -banner.Size.Y.Offset - 40)
	banner.Visible = true
	UIKit.tween(banner, 0.4, { Position = UDim2.new(0.5, 0, 0, BANNER_TOP) }, Enum.EasingStyle.Quart)
	UIKit.playUI("AlertTone")
	task.spawn(buzz, my)

	-- карточка EAS
	local rules = fillCard(ids)
	bigRule.Visible = false
	UIKit.popIn(card, cardScale)
	startStatic()
	task.spawn(typewriter, my, rules)
end

local function hide()
	if not gui.Enabled then
		return
	end
	token += 1
	stopStatic()
	bigRule.Visible = false
	card.Visible = false
	UIKit.tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -banner.Size.Y.Offset - 40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.32, function()
		if card.Visible == false then
			banner.Visible = false
			gui.Enabled = false
		end
	end)
end

----------------------------------------------------------------------
-- Инициализация
----------------------------------------------------------------------
function AlertUI.init()
	gui = UIKit.new("ScreenGui", {
		Name = "AlertUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 30,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	buildBanner()
	buildCard()
	relabelStatic()

	ClientState.AlertReceived:Connect(show)
	ClientState.StateChanged:Connect(function(snap: ClientState.StateSnapshot)
		-- Прячем, когда фаза Alert закончилась (или пропущена); небольшой запас на порядок событий.
		if gui.Enabled and snap.Phase ~= "Alert" and os.clock() - shownAt > 0.5 then
			hide()
		end
	end)
	ClientState.SettingsChanged:Connect(function()
		relabelStatic()
		if gui.Enabled and #currentIds > 0 then
			fillBannerLines(currentIds)
			-- текст карточки на другом языке: показываем целиком, без повторной печати
			fillCard(currentIds)
			cardBody.MaxVisibleGraphemes = -1
		end
	end)
end

function AlertUI.hide()
	hide()
end

return AlertUI
