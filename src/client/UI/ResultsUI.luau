--!strict
-- Итоги забега: победа/поражение, ночей пережито, Амбер и опыт, выжившие, обратный отсчёт до лобби.
-- Показывается по ClientState.ResultReceived, прячется при переходе в Lobby/Countdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local ResultsUI = {}

local DESIGN_W, DESIGN_H = 640, 440

local modal: UIKit.Modal
local subtitle: TextLabel
local lines: { TextLabel } = {}
local countdown: TextLabel
local current: Remotes.ResultSummary? = nil

local function render(summary: Remotes.ResultSummary)
	modal.Title.Text = Locale.t(if summary.Won then "ResultWin" else "ResultLose")
	modal.Title.TextColor3 = if summary.Won then Theme.Amber else Theme.Red
	local rule = modal.Window:FindFirstChild("Rule")
	if rule and rule:IsA("Frame") then
		rule.BackgroundColor3 = modal.Title.TextColor3
	end
	UIKit.setText(subtitle, Locale.t("Diff_" .. tostring(summary.Difficulty)))
	local survivors = summary.Survivors or {}
	local names = if #survivors > 0 then table.concat(survivors, ", ") else Locale.t("ResultNone")
	local texts = {
		Locale.t("ResultNights", math.floor(summary.Night), math.floor(summary.Nights)),
		Locale.t("ResultAmber", math.floor(summary.AmberEarned)),
		Locale.t("ResultXp", math.floor(summary.XpEarned)),
		Locale.t("ResultSurvivors", names),
	}
	for i, label in lines do
		UIKit.setText(label, texts[i] or "")
	end
end

local function show(summary: Remotes.ResultSummary)
	current = summary
	render(summary)
	UIKit.setText(countdown, "")
	modal:Open()
	UIKit.playUI(if summary.Won then "Success" else "Fail")
end

function ResultsUI.init()
	local gui = UIKit.new("ScreenGui", {
		Name = "ResultsUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	modal = UIKit.modal({ Name = "Results", Width = DESIGN_W, Height = DESIGN_H, Parent = gui, NoClose = true })
	modal.Title.Size = UDim2.new(1, -40, 0, 40)
	modal.Title.FontFace = Theme.FontMono
	modal.Title.TextXAlignment = Enum.TextXAlignment.Center
	modal.Title.Position = UDim2.fromOffset(20, 12)

	subtitle = UIKit.label({
		Name = "Difficulty",
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = modal.Body,
	})
	local list = UIKit.new("Frame", {
		Name = "Lines",
		Size = UDim2.new(1, -40, 0, 200),
		Position = UDim2.new(0.5, 0, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = modal.Body,
	}) :: Frame
	UIKit.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	for i = 1, 4 do
		table.insert(
			lines,
			UIKit.label({
				Name = "Line" .. i,
				Text = "",
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = if i == 2 then Theme.FontBold else Theme.FontBody,
				TextColor3 = if i == 2 then Theme.Amber else Theme.Text,
				MaxTextSize = 24,
				LayoutOrder = i,
				NoStroke = true,
				Parent = list,
			})
		)
	end
	countdown = UIKit.label({
		Name = "Countdown",
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 18,
		NoStroke = true,
		Parent = modal.Body,
	})

	ClientState.ResultReceived:Connect(show)
	ClientState.StateChanged:Connect(function(snap: ClientState.StateSnapshot)
		if modal.IsOpen and (snap.Phase == "Lobby" or snap.Phase == "Countdown") then
			modal:Hide()
			current = nil
		end
	end)
	ClientState.SettingsChanged:Connect(function()
		local summary = current
		if summary and modal.IsOpen then
			render(summary)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			if modal.IsOpen then
				UIKit.setText(countdown, Locale.t("BackToLobby", math.max(0, math.ceil(ClientState.phaseRemaining()))))
			end
		end
	end)
end

return ResultsUI
