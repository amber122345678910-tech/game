--!strict
-- Лобби: готовность (READY/CANCEL), счётчик готовых и обратный отсчёт, выбор сложности голосованием,
-- профиль (уровень, титул, Амбер, опыт), окна перков, рекордов и «как играть», кнопка настроек.
-- Для зашедших в середине матча — текст MatchInProgress и управление спектатором.
-- Виден в фазах Lobby/Countdown или в матче при статусе Lobby/Spectating (не участвовал в этом матче).

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local LobbyUI = {}

local BTN_MOUSE, BTN_TOUCH = 48, 72
local READY_MOUSE, READY_TOUCH = 72, 96
local DIFF_W = 250

type PerkRow = {
	Def: Config.PerkDef,
	Name: TextLabel,
	Desc: TextLabel,
	Level: TextLabel,
	Buy: TextButton,
}

type DiffCard = {
	Def: Config.DifficultyDef,
	Button: TextButton,
	Name: TextLabel,
	Desc: TextLabel,
	Votes: TextLabel,
	Stroke: UIStroke,
}

local gui: ScreenGui
local modalGui: ScreenGui

-- панели лобби
local phaseText: TextLabel
local readyText: TextLabel
local titleLabel: TextLabel
local levelLabel: TextLabel
local amberLabel: TextLabel
local xpFill: Frame
local xpLabel: TextLabel
local menuButtons: { [string]: TextButton } = {}
local diffColumn: Frame
local diffCards: { DiffCard } = {}
local readyButton: TextButton
local lateJoin: Frame
local lateText: TextLabel
local spectateLabel: TextLabel
local spectatePrev: TextButton
local spectateNext: TextButton
local lobbyRoot: { GuiObject } = {}

-- окна
local perksModal: UIKit.Modal
local perkRows: { PerkRow } = {}
local perkBalance: TextLabel
local perkBusy = false
local recordsModal: UIKit.Modal
local recordsList: Frame
local recordRows: { { Name: string, Nights: number } } = {}
local howToModal: UIKit.Modal
local howToText: TextLabel
local howToButton: TextButton
local howToShown = false

local isReady = false
local myVote: string? = nil
local lastPhase = ""
local participated = false
local spectateName = ""
local spectateBound = false

----------------------------------------------------------------------
-- Помощники
----------------------------------------------------------------------
local function isPhone(): boolean
	return UIKit.currentHudScale() < 0.6
end

local function spectateCall(fnName: string)
	local spectate = UIKit.controller("Spectate")
	if spectate and type(spectate[fnName]) == "function" then
		pcall(spectate[fnName])
	end
end

local function openSettings()
	local module = script.Parent:FindFirstChild("SettingsUI")
	if module and module:IsA("ModuleScript") then
		local ok, settings = pcall(require, module)
		if ok and type(settings) == "table" and type(settings.open) == "function" then
			settings.open()
		end
	end
end

local function xpProgress(profile: ClientState.ProfileSnapshot): (number, number)
	local level = math.max(0, math.floor(profile.Level))
	local base = Config.xpForLevel(level)
	local next = Config.xpForLevel(level + 1)
	return math.max(0, math.floor(profile.Xp) - base), math.max(1, next - base)
end

----------------------------------------------------------------------
-- Построение панелей лобби
----------------------------------------------------------------------
local function buildPhasePanel()
	local panel = UIKit.panel({
		Name = "Phase",
		Size = UDim2.fromOffset(420, 70),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	UIKit.thinStroke(panel, Theme.GrayDark, 0.2)
	UIKit.autoScale(panel, "hud")
	table.insert(lobbyRoot, panel)
	phaseText = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -24, 0, 32),
		Position = UDim2.fromOffset(12, 8),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 22,
		NoStroke = true,
		Parent = panel,
	})
	readyText = UIKit.label({
		Name = "Ready",
		Text = "",
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 42),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = panel,
	})
end

local function buildProfile()
	local column = UIKit.new("Frame", {
		Name = "Left",
		Size = UDim2.fromOffset(320, 260),
		Position = UDim2.new(0, 12, 0, 8),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(column, "hud")
	UIKit.list(column, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	table.insert(lobbyRoot, column)

	local profile = UIKit.panel({
		Name = "Profile",
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 0.2,
		LayoutOrder = 1,
		Parent = column,
	})
	UIKit.thinStroke(profile, Theme.GrayDark, 0.2)
	titleLabel = UIKit.label({
		Name = "Title",
		Text = "",
		Size = UDim2.new(0.6, 0, 0, 26),
		Position = UDim2.fromOffset(12, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = profile,
	})
	levelLabel = UIKit.label({
		Name = "Level",
		Text = "",
		Size = UDim2.new(0.4, -12, 0, 26),
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = profile,
	})
	amberLabel = UIKit.label({
		Name = "Amber",
		Text = "",
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = profile,
	})
	local _, fill = UIKit.bar({
		Name = "Xp",
		Size = UDim2.new(1, -24, 0, 6),
		Position = UDim2.new(0.5, 0, 1, -26),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = profile,
	}, Theme.Amber)
	xpFill = fill
	xpLabel = UIKit.label({
		Name = "XpText",
		Text = "",
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 12,
		NoStroke = true,
		Parent = profile,
	})

	local rowHolder = UIKit.new("Frame", {
		Name = "Menu",
		Size = UDim2.new(1, 0, 0, BTN_MOUSE),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = column,
	}) :: Frame
	UIKit.list(rowHolder, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
	local defs: { { string } } = {
		{ "Perks", "Perks" },
		{ "Records", "Records" },
		{ "Help", "?" },
		{ "Settings", "⚙" },
	}
	for i, d in defs do
		local id = d[1]
		local button = UIKit.button({
			Name = id,
			Text = d[2],
			Size = UDim2.new(0.25, -5, 1, 0),
			LayoutOrder = i,
			TextSize = 18,
			Parent = rowHolder,
		}, function()
			if id == "Perks" then
				LobbyUI.openPerks()
			elseif id == "Records" then
				LobbyUI.openRecords()
			elseif id == "Help" then
				LobbyUI.openHowToPlay()
			else
				openSettings()
			end
		end)
		UIKit.styleDark(button, Theme.Amber)
		menuButtons[id] = button
	end
end

local function buildDifficulty()
	diffColumn = UIKit.new("Frame", {
		Name = "Difficulty",
		Size = UDim2.fromOffset(DIFF_W, 400),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(diffColumn, "hud")
	UIKit.list(diffColumn, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)
	table.insert(lobbyRoot, diffColumn)
	local header = UIKit.label({
		Name = "Header",
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 16,
		LayoutOrder = 0,
		Parent = diffColumn,
	})
	header:SetAttribute("Role", "DiffHeader")
	for i, def in Config.difficultyList() do
		local button = UIKit.new("TextButton", {
			Name = def.Id,
			Size = UDim2.new(1, 0, 0, 78),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.2,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			Parent = diffColumn,
		}) :: TextButton
		UIKit.corner(button, 6)
		local stroke = UIKit.new("UIStroke", { Thickness = 1, Color = Theme.GrayDark, Transparency = 0.3, Parent = button }) :: UIStroke
		UIKit.new("Frame", {
			Name = "Swatch",
			Size = UDim2.new(0, 4, 1, -14),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = def.Color,
			Parent = button,
		})
		local name = UIKit.label({
			Name = "Name",
			Text = "",
			Size = UDim2.new(0.6, 0, 0, 24),
			Position = UDim2.fromOffset(18, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.FontBold,
			TextColor3 = def.Color,
			MaxTextSize = 18,
			NoStroke = true,
			Parent = button,
		})
		local votes = UIKit.label({
			Name = "Votes",
			Text = "",
			Size = UDim2.new(0.4, -12, 0, 24),
			Position = UDim2.new(1, -10, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.FontMono,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 13,
			NoStroke = true,
			Parent = button,
		})
		local desc = UIKit.label({
			Name = "Desc",
			Text = "",
			Size = UDim2.new(1, -28, 0, 42),
			Position = UDim2.fromOffset(18, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Theme.FontBody,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 13,
			NoStroke = true,
			Parent = button,
		})
		button.Activated:Connect(function()
			UIKit.playClick()
			myVote = def.Id
			Remotes.VoteDifficulty:FireServer(def.Id)
			LobbyUI.refresh()
		end)
		table.insert(diffCards, { Def = def, Button = button, Name = name, Desc = desc, Votes = votes, Stroke = stroke })
	end
end

local function buildReady()
	readyButton = UIKit.button({
		Name = "Ready",
		Text = "",
		Size = UDim2.fromOffset(320, READY_MOUSE),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 30,
		Parent = gui,
	}, function()
		isReady = not isReady
		Remotes.Ready:FireServer(isReady)
		LobbyUI.refresh()
	end)
	UIKit.autoScale(readyButton, "hud")
	table.insert(lobbyRoot, readyButton)
end

local function buildLateJoin()
	lateJoin = UIKit.panel({
		Name = "LateJoin",
		Size = UDim2.fromOffset(560, 150),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	})
	UIKit.thinStroke(lateJoin, Theme.GrayDark, 0.2)
	UIKit.autoScale(lateJoin, "hud")
	lateText = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.fromOffset(12, 10),
		FontFace = Theme.FontBody,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = lateJoin,
	})
	spectatePrev = UIKit.button({
		Name = "Prev",
		Text = "◀",
		Size = UDim2.fromOffset(BTN_MOUSE + 16, BTN_MOUSE),
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 24,
		Parent = lateJoin,
	}, function()
		spectateCall("prev")
	end)
	UIKit.styleDark(spectatePrev, Theme.Amber)
	spectateNext = UIKit.button({
		Name = "Next",
		Text = "▶",
		Size = UDim2.fromOffset(BTN_MOUSE + 16, BTN_MOUSE),
		Position = UDim2.new(1, -12, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 24,
		Parent = lateJoin,
	}, function()
		spectateCall("next")
	end)
	UIKit.styleDark(spectateNext, Theme.Amber)
	spectateLabel = UIKit.label({
		Name = "Target",
		Text = "",
		Size = UDim2.new(1, -200, 0, 40),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		FontFace = Theme.FontBold,
		MaxTextSize = 18,
		NoStroke = true,
		Parent = lateJoin,
	})
end

----------------------------------------------------------------------
-- Окна: перки, рекорды, как играть
----------------------------------------------------------------------
local function buildPerks()
	perksModal = UIKit.modal({ Name = "Perks", Width = 760, Height = 470, Parent = modalGui })
	perkBalance = UIKit.label({
		Name = "Balance",
		Text = "",
		Size = UDim2.fromOffset(220, 30),
		Position = UDim2.new(1, -80, 0, 18),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = perksModal.Window,
	})
	local scroll = UIKit.new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Gray,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = perksModal.Body,
	}) :: ScrollingFrame
	UIKit.list(scroll, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	for i, def in Config.perkList() do
		local row = UIKit.new("Frame", {
			Name = def.Id,
			Size = UDim2.new(1, -8, 0, 68),
			BackgroundColor3 = Theme.Card,
			BackgroundTransparency = 0.35,
			LayoutOrder = i,
			Parent = scroll,
		}) :: Frame
		UIKit.corner(row, 6)
		UIKit.new("UIStroke", { Thickness = 1, Color = Theme.GrayDark, Transparency = 0.4, Parent = row })
		UIKit.new("Frame", {
			Name = "Swatch",
			Size = UDim2.new(0, 4, 1, -16),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = def.Color,
			Parent = row,
		})
		local name = UIKit.label({
			Name = "Name",
			Text = "",
			Size = UDim2.new(1, -260, 0, 26),
			Position = UDim2.fromOffset(18, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.FontBold,
			TextColor3 = def.Color,
			MaxTextSize = 20,
			NoStroke = true,
			Parent = row,
		})
		local desc = UIKit.label({
			Name = "Desc",
			Text = "",
			Size = UDim2.new(1, -260, 0, 28),
			Position = UDim2.fromOffset(18, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Theme.FontBody,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 14,
			NoStroke = true,
			Parent = row,
		})
		local level = UIKit.label({
			Name = "Level",
			Text = "",
			Size = UDim2.fromOffset(120, 18),
			Position = UDim2.new(1, -236, 0, 4),
			AnchorPoint = Vector2.new(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.FontMono,
			TextColor3 = Theme.Amber,
			MaxTextSize = 13,
			NoStroke = true,
			Parent = row,
		})
		local buyButton = UIKit.button({
			Name = "Buy",
			Text = "",
			Size = UDim2.fromOffset(220, 56),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 17,
			Parent = row,
		}, function()
			LobbyUI.buyPerk(def.Id)
		end)
		UIKit.styleDark(buyButton, Theme.Amber)
		table.insert(perkRows, { Def = def, Name = name, Desc = desc, Level = level, Buy = buyButton })
	end
end

local function buildRecords()
	recordsModal = UIKit.modal({ Name = "Records", Width = 560, Height = 470, Parent = modalGui })
	local scroll = UIKit.new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Gray,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = recordsModal.Body,
	}) :: ScrollingFrame
	UIKit.list(scroll, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	recordsList = scroll
end

local function buildHowTo()
	howToModal = UIKit.modal({ Name = "HowToPlay", Width = 720, Height = 440, Parent = modalGui })
	howToText = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, 0, 1, -90),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Theme.FontBody,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = howToModal.Body,
	})
	howToButton = UIKit.button({
		Name = "Ok",
		Text = "",
		Size = UDim2.fromOffset(240, 68),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 24,
		Parent = howToModal.Body,
	}, function()
		howToModal:Hide()
	end)
	UIKit.styleDark(howToButton, Theme.Amber)
end

----------------------------------------------------------------------
-- Обновление
----------------------------------------------------------------------
local function refreshRecords()
	for _, child in recordsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if #recordRows == 0 then
		UIKit.label({
			Name = "Empty",
			Text = Locale.t("NoRecords"),
			Size = UDim2.new(1, -8, 0, 40),
			FontFace = Theme.FontBody,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 18,
			NoStroke = true,
			Parent = recordsList,
		})
		return
	end
	for i, row in recordRows do
		local line = UIKit.new("Frame", {
			Name = "Row" .. i,
			Size = UDim2.new(1, -8, 0, 40),
			BackgroundColor3 = Theme.Card,
			BackgroundTransparency = if i % 2 == 0 then 0.6 else 0.35,
			LayoutOrder = i,
			Parent = recordsList,
		}) :: Frame
		UIKit.corner(line, 4)
		UIKit.label({
			Name = "Name",
			Text = string.format("%d.  %s", i, tostring(row.Name)),
			Size = UDim2.new(0.7, -12, 1, -8),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.FontBold,
			TextColor3 = if i <= 3 then Theme.Amber else Theme.Text,
			MaxTextSize = 18,
			NoStroke = true,
			Parent = line,
		})
		UIKit.label({
			Name = "Nights",
			Text = Locale.t("RecordNights", math.floor(tonumber(row.Nights) or 0)),
			Size = UDim2.new(0.3, -12, 1, -8),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.FontMono,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 16,
			NoStroke = true,
			Parent = line,
		})
	end
end

local function refreshPerks()
	local profile = ClientState.Profile
	UIKit.setText(perkBalance, Locale.t("Amber", math.floor(profile.Amber)))
	for _, row in perkRows do
		local def = row.Def
		local level = math.floor(profile.Perks[def.Id] or 0)
		local max = #def.Costs
		UIKit.setText(row.Name, Locale.perk(def.Id))
		UIKit.setText(row.Desc, Locale.t("PerkDesc_" .. def.Id))
		UIKit.setText(row.Level, Locale.t("PerkLevel", level, max))
		if level >= max then
			UIKit.setButtonText(row.Buy, Locale.t("PerkMax"))
			UIKit.styleDark(row.Buy, Theme.Gray)
			UIKit.setButtonEnabled(row.Buy, false)
		else
			local cost = def.Costs[level + 1]
			UIKit.setButtonText(row.Buy, Locale.t("PerkBuy", cost))
			UIKit.styleDark(row.Buy, if profile.Amber >= cost then Theme.Amber else Theme.TextDim)
			UIKit.setButtonEnabled(row.Buy, not perkBusy)
		end
	end
end

local function refreshProfile()
	local profile = ClientState.Profile
	UIKit.setText(titleLabel, tostring(profile.Title))
	UIKit.setText(levelLabel, Locale.t("Level", math.floor(profile.Level)))
	UIKit.setText(amberLabel, Locale.t("Amber", math.floor(profile.Amber)))
	local cur, need = xpProgress(profile)
	UIKit.setBar(xpFill, cur / need)
	UIKit.setText(xpLabel, Locale.t("XpProgress", cur, need))
end

local function refreshDifficulty(snap: ClientState.StateSnapshot)
	local phone = isPhone()
	local header = diffColumn:FindFirstChild("Header")
	if header and header:IsA("TextLabel") then
		header.Text = Locale.t("Difficulty")
	end
	for _, card in diffCards do
		local def = card.Def
		local votes = math.floor(snap.Votes[def.Id] or 0)
		local chosen = snap.Difficulty == def.Id
		local prefix = if myVote == def.Id then "▸ " else ""
		UIKit.setText(card.Name, prefix .. Locale.t("Diff_" .. def.Id))
		UIKit.setText(card.Desc, Locale.t("DiffDesc_" .. def.Id))
		UIKit.setText(card.Votes, Locale.t("Votes", votes))
		card.Desc.Visible = not phone
		card.Button.Size = UDim2.new(1, 0, 0, if phone then UIKit.touchPx(44, 64) else 78)
		card.Stroke.Color = if chosen then def.Color else Theme.GrayDark
		card.Stroke.Thickness = if chosen then 2 else 1
		card.Stroke.Transparency = if chosen then 0 else 0.3
		card.Button.BackgroundTransparency = if chosen then 0.05 else 0.2
	end
end

local function refreshReady(snap: ClientState.StateSnapshot)
	if snap.Phase == "Countdown" then
		UIKit.setText(phaseText, Locale.t("PhaseCountdown", math.max(0, math.ceil(ClientState.phaseRemaining()))))
	else
		UIKit.setText(phaseText, Locale.t("PhaseLobby"))
	end
	UIKit.setText(readyText, Locale.t("ReadyCount", math.floor(snap.Ready), math.floor(snap.Players)))
	UIKit.setButtonText(readyButton, Locale.t(if isReady then "NotReady" else "Ready"))
	UIKit.styleDark(readyButton, if isReady then Theme.TextDim else Theme.Green, if isReady then Theme.PanelLight else Theme.GreenDark:Lerp(Color3.new(0, 0, 0), 0.6))
	UIKit.thinStroke(readyButton, if isReady then Theme.Gray else Theme.Green, 0.1, 2)
end

local function refreshSpectate()
	UIKit.setText(spectateLabel, Locale.t("Spectating", if spectateName ~= "" then spectateName else "—"))
end

local function bindSpectate()
	if spectateBound then
		return
	end
	local spectate = UIKit.controller("Spectate")
	if not spectate then
		return
	end
	spectateBound = true
	local signal = spectate.TargetChanged
	if type(signal) == "table" and type(signal.Connect) == "function" then
		signal:Connect(function(name: any)
			spectateName = if name ~= nil then tostring(name) else ""
			refreshSpectate()
		end)
	end
	local hasControls = type(spectate.next) == "function"
	spectatePrev.Visible = hasControls
	spectateNext.Visible = hasControls
end

local function refreshVisibility()
	local snap = ClientState.Snapshot
	local status = ClientState.Status
	local inLobbyPhase = snap.Phase == "Lobby" or snap.Phase == "Countdown"
	local inMatch = ClientState.inMatch()
	if inMatch and (status == "Alive" or status == "Downed" or status == "Hiding") then
		participated = true
	end
	local late = inMatch and (status == "Lobby" or (status == "Spectating" and not participated))
	gui.Enabled = inLobbyPhase or late
	for _, obj in lobbyRoot do
		obj.Visible = inLobbyPhase
	end
	lateJoin.Visible = late
	if late then
		bindSpectate()
		UIKit.setText(lateText, Locale.t("MatchInProgress"))
		refreshSpectate()
	end
	if not gui.Enabled then
		perksModal:Hide()
		recordsModal:Hide()
		howToModal:Hide()
	end
end

local function relayout()
	local btn = UIKit.touchPx(BTN_MOUSE, BTN_TOUCH)
	local menu = menuButtons.Perks and menuButtons.Perks.Parent
	if menu and menu:IsA("Frame") then
		menu.Size = UDim2.new(1, 0, 0, btn)
	end
	readyButton.Size = UDim2.fromOffset(320, UIKit.touchPx(READY_MOUSE, READY_TOUCH))
	spectatePrev.Size = UDim2.fromOffset(btn + 16, btn)
	spectateNext.Size = UDim2.fromOffset(btn + 16, btn)
	refreshDifficulty(ClientState.Snapshot)
end

function LobbyUI.refresh()
	local snap = ClientState.Snapshot
	refreshReady(snap)
	refreshDifficulty(snap)
	refreshProfile()
	refreshVisibility()
	if perksModal.IsOpen then
		refreshPerks()
	end
end

local function relabel()
	perksModal.Title.Text = Locale.t("Perks")
	recordsModal.Title.Text = Locale.t("Records")
	howToModal.Title.Text = Locale.t("HowToPlayTitle")
	UIKit.setText(howToText, Locale.t("HowToPlay"))
	UIKit.setButtonText(howToButton, Locale.t("Ok"))
	UIKit.setButtonText(menuButtons.Perks, Locale.t("Perks"))
	UIKit.setButtonText(menuButtons.Records, Locale.t("Records"))
	refreshPerks()
	refreshRecords()
	LobbyUI.refresh()
end

----------------------------------------------------------------------
-- Публичное
----------------------------------------------------------------------
function LobbyUI.openPerks()
	refreshPerks()
	perksModal:Open()
end

function LobbyUI.openRecords()
	refreshRecords()
	recordsModal:Open()
end

function LobbyUI.openHowToPlay()
	UIKit.setText(howToText, Locale.t("HowToPlay"))
	howToModal:Open()
end

function LobbyUI.buyPerk(perkId: string)
	if perkBusy then
		return
	end
	perkBusy = true
	refreshPerks()
	local ok, success, message = pcall(function()
		return Remotes.BuyPerk:InvokeServer(perkId)
	end)
	perkBusy = false
	refreshPerks()
	if not ok then
		ClientState.Notified:Fire("N_CantNow", "error")
		return
	end
	local key = if type(message) == "string" then message else (if success == true then "N_PerkBought" else "N_NotEnoughAmber")
	ClientState.Notified:Fire(key, if success == true then "success" else "error", { perkId })
end

function LobbyUI.init()
	gui = UIKit.new("ScreenGui", {
		Name = "LobbyUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 40,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	modalGui = UIKit.new("ScreenGui", {
		Name = "LobbyModals",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 41,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	buildPhasePanel()
	buildProfile()
	buildDifficulty()
	buildReady()
	buildLateJoin()
	buildPerks()
	buildRecords()
	buildHowTo()
	relayout()
	UIKit.onLayoutChanged(relayout)
	relabel()

	ClientState.StateChanged:Connect(function(snap: ClientState.StateSnapshot)
		if snap.Phase ~= lastPhase then
			if snap.Phase == "Lobby" and lastPhase ~= "Countdown" then
				isReady = false -- новое лобби: готовность сброшена
				myVote = nil
			end
			if snap.Phase == "Lobby" or snap.Phase == "Results" then
				participated = false
			end
			lastPhase = snap.Phase
		end
		LobbyUI.refresh()
	end)
	ClientState.StatusChanged:Connect(function()
		refreshVisibility()
	end)
	ClientState.ProfileChanged:Connect(function(profile: ClientState.ProfileSnapshot)
		refreshProfile()
		refreshPerks()
		-- Новичку один раз за сессию показываем «как играть»
		local phase = ClientState.Snapshot.Phase
		if not howToShown and profile.NightsSurvived == 0 and (phase == "Lobby" or phase == "Countdown") then
			howToShown = true
			task.delay(1, LobbyUI.openHowToPlay)
		end
	end)
	ClientState.LeaderboardChanged:Connect(function(rows: { { Name: string, Nights: number } })
		recordRows = rows
		if recordsModal.IsOpen then
			refreshRecords()
		end
	end)
	ClientState.FXEvent:Connect(function(kind: string, _params: { [string]: any }?)
		if kind == "OpenPerks" and gui.Enabled then
			LobbyUI.openPerks()
		end
	end)
	ClientState.SettingsChanged:Connect(relabel)
	GuiService.MenuOpened:Connect(function()
		perksModal:Hide()
		recordsModal:Hide()
		howToModal:Hide()
	end)

	-- обратный отсчёт
	task.spawn(function()
		while true do
			task.wait(0.25)
			if gui.Enabled and ClientState.Snapshot.Phase == "Countdown" then
				refreshReady(ClientState.Snapshot)
			end
		end
	end)
end

return LobbyUI
