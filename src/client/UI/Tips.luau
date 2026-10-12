--!strict
-- Обучающие подсказки: одна строка над хотбаром в первом матче новичка (Profile.NightsSurvived == 0,
-- либо явно включено в настройках ShowTips). День 1 по времени: яблоки → продажа → магазин;
-- оповещение: Tip_Alert; ночь: Tip_Night; в укрытии: Tip_Breath. После второй ночи подсказок нет.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local Tips = {}

local SLOT_MOUSE, SLOT_TOUCH = 64, 96 -- как в HUD
local DOCK_MARGIN = 10
local ABOVE_MOUSE, ABOVE_TOUCH = 140, 170 -- над хотбаром, выносливостью и кнопкой «пропустить»

local holder: Frame
local group: CanvasGroup
local label: TextLabel
local currentKey: string? = nil
local switching = 0

local function enabled(): boolean
	local v = ClientState.Settings.ShowTips
	if type(v) == "boolean" then
		return v
	end
	return ClientState.Profile.NightsSurvived == 0
end

local function desiredTip(): string?
	if not enabled() or not ClientState.inMatch() then
		return nil
	end
	local snap = ClientState.Snapshot
	local night = math.max(1, math.floor(snap.Night))
	if night > 2 then
		return nil
	end
	local status = ClientState.Status
	if status == "Hiding" then
		return "Tip_Breath"
	end
	if status ~= "Alive" then
		return nil
	end
	if snap.Phase == "Day" then
		if night > 1 then
			return nil
		end
		local elapsed = math.max(0, snap.PhaseLength - ClientState.phaseRemaining())
		if elapsed < 20 then
			return "Tip_Apples"
		elseif elapsed < 40 then
			return "Tip_Sell"
		end
		return "Tip_Shop"
	elseif snap.Phase == "Alert" then
		return "Tip_Alert"
	elseif snap.Phase == "Night" then
		return "Tip_Night"
	end
	return nil
end

local function switchTo(key: string?)
	currentKey = key
	switching += 1
	local my = switching
	task.spawn(function()
		if group.GroupTransparency < 1 then
			UIKit.tween(group, 0.25, { GroupTransparency = 1 })
			task.wait(0.25)
		end
		if my ~= switching then
			return
		end
		if key then
			label.Text = Locale.t(key)
			holder.Visible = true
			UIKit.tween(group, 0.3, { GroupTransparency = 0 })
		else
			holder.Visible = false
		end
	end)
end

local function relayout()
	local slot = UIKit.touchPx(SLOT_MOUSE, SLOT_TOUCH)
	holder.Position = UDim2.new(0.5, 0, 1, -UIKit.hudPx(DOCK_MARGIN + slot + UIKit.touchPx(ABOVE_MOUSE, ABOVE_TOUCH)))
end

function Tips.init()
	local gui = UIKit.new("ScreenGui", {
		Name = "Tips",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 15,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	holder = UIKit.new("Frame", {
		Name = "Tip",
		Size = UDim2.fromOffset(640, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(holder, "hud")
	group = UIKit.new("CanvasGroup", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.3,
		GroupTransparency = 1,
		Parent = holder,
	}) :: CanvasGroup
	UIKit.corner(group, 22)
	UIKit.new("UIStroke", { Thickness = 1, Color = Theme.Amber, Transparency = 0.5, Parent = group })
	UIKit.label({
		Name = "Mark",
		Text = "!",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = group,
	})
	label = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -60, 1, -8),
		Position = UDim2.new(0, 44, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		MaxTextSize = 17,
		NoStroke = true,
		Parent = group,
	})
	relayout()
	UIKit.onLayoutChanged(relayout)

	ClientState.SettingsChanged:Connect(function()
		local key = currentKey
		if key and holder.Visible then
			label.Text = Locale.t(key)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.4)
			local key = desiredTip()
			if key ~= currentKey then
				switchTo(key)
			end
		end
	end)
end

return Tips
