--!strict
-- «Играть с другом»: окно со списком игроков на сервере (позвать в свой бункер)
-- и всплывающее приглашение (принять / отказаться).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local TeamUI = {}

local DESIGN_W, DESIGN_H = 460, 440
local INVITE_SHOW_TIME = 30

local gui: ScreenGui
local window: Frame
local listFrame: ScrollingFrame
local emptyLabel: TextLabel
local leaveButton: TextButton
local inviteFrame: Frame
local inviteLabel: TextLabel
local inviteFrom: number? = nil
local inviteToken = 0

local function refreshList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			count += 1
			local row = UIKit.new("Frame", {
				Name = "Row",
				Size = UDim2.new(1, -8, 0, 56),
				BackgroundColor3 = Theme.PanelLight,
				LayoutOrder = count,
				Parent = listFrame,
			}) :: Frame
			UIKit.corner(row, 8)
			UIKit.label({
				Text = other.DisplayName,
				Size = UDim2.new(0.58, -12, 1, -12),
				Position = UDim2.new(0, 12, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				Parent = row,
			})
			local userId = other.UserId
			UIKit.button({
				Text = "Позвать",
				Color = Theme.Green,
				Size = UDim2.new(0.38, 0, 1, -12),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 22,
				Parent = row,
			}, function()
				Remotes.TeamInvite:FireServer(userId)
			end)
		end
	end
	emptyLabel.Visible = count == 0
	leaveButton.Visible = ClientState.isGuest()
end

local function setOpen(open: boolean)
	window.Visible = open
	if open then
		refreshList()
	end
end

local function hideInvite()
	inviteFrom = nil
	inviteFrame.Visible = false
end

local function respond(accept: boolean)
	local from = inviteFrom
	hideInvite()
	if from then
		Remotes.TeamRespond:FireServer(from, accept)
	end
end

function TeamUI.init()
	gui = UIKit.new("ScreenGui", {
		Name = "TeamUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	-- окно со списком игроков
	window = UIKit.panel({
		Name = "Team",
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(window, "modal", DESIGN_W, DESIGN_H)
	UIKit.gradient(window, Theme.PanelLight, Theme.Panel)
	UIKit.label({
		Text = "👥 Играть с другом",
		Size = UDim2.new(1, -80, 0, 48),
		Position = UDim2.new(0, 16, 0, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 36,
		Parent = window,
	})
	UIKit.label({
		Text = "Позови игрока в свой бункер: вы строите вместе и выживаете в одном шторме. Награду получает каждый.",
		Size = UDim2.new(1, -32, 0, 52),
		Position = UDim2.new(0, 16, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		MaxTextSize = 18,
		Parent = window,
	})
	UIKit.button({
		Text = "✖",
		Color = Theme.Red,
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(1, -12, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 26,
		Parent = window,
	}, function()
		setOpen(false)
	end)
	listFrame = UIKit.new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -32, 1, -200),
		Position = UDim2.new(0, 16, 0, 120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = window,
	}) :: ScrollingFrame
	UIKit.list(listFrame, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	emptyLabel = UIKit.label({
		Text = "На сервере больше никого нет.\nВ Studio: вкладка Test → Clients and Servers → 2 игрока.",
		Size = UDim2.new(1, -32, 0, 80),
		Position = UDim2.new(0, 16, 0, 140),
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		MaxTextSize = 18,
		Visible = false,
		Parent = window,
	})
	leaveButton = UIKit.button({
		Text = "🏠 Вернуться к себе",
		Color = Theme.Orange,
		Size = UDim2.new(1, -32, 0, 56),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 24,
		Parent = window,
	}, function()
		Remotes.TeamLeave:FireServer()
		setOpen(false)
	end)

	-- всплывающее приглашение
	inviteFrame = UIKit.panel({
		Name = "Invite",
		Size = UDim2.fromOffset(420, 150),
		Position = UDim2.new(0.5, 0, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(inviteFrame, "hud")
	inviteLabel = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -24, 0, 64),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		TextWrapped = true,
		MaxTextSize = 24,
		Parent = inviteFrame,
	})
	UIKit.button({
		Text = "✔ Принять",
		Color = Theme.Green,
		Size = UDim2.new(0.5, -18, 0, 54),
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 24,
		Parent = inviteFrame,
	}, function()
		respond(true)
	end)
	UIKit.button({
		Text = "✖ Нет",
		Color = Theme.Gray,
		Size = UDim2.new(0.5, -18, 0, 54),
		Position = UDim2.new(1, -12, 1, -12),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 24,
		Parent = inviteFrame,
	}, function()
		respond(false)
	end)

	ClientState.TeamRequested:Connect(function()
		setOpen(not window.Visible)
	end)
	Players.PlayerAdded:Connect(function()
		if window.Visible then
			refreshList()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if window.Visible then
			task.defer(refreshList)
		end
	end)
	player:GetAttributeChangedSignal("IsGuest"):Connect(function()
		if window.Visible then
			refreshList()
		end
	end)
	Remotes.TeamInviteReceived.OnClientEvent:Connect(function(fromUserId: any, fromName: any)
		if typeof(fromUserId) ~= "number" or typeof(fromName) ~= "string" then
			return
		end
		inviteFrom = fromUserId
		inviteLabel.Text = "👥 " .. fromName .. " зовёт тебя в свой бункер!"
		inviteFrame.Visible = true
		inviteToken += 1
		local token = inviteToken
		task.delay(INVITE_SHOW_TIME, function()
			if token == inviteToken then
				hideInvite()
			end
		end)
	end)
end

return TeamUI
