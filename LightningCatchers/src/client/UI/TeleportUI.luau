--!strict
-- Острова: быстрый перелёт в хаб и на открытые острова; закрытые показывают цену.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local TeleportUI = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CARD = Vector2.new(268, 196)

type Card = {
	zone: number,
	frame: Frame,
	status: TextLabel,
	button: TextButton,
	lock: TextLabel,
}

local win: UIKit.Window
local voltsLabel: TextLabel
local cards: { Card } = {}
local busy = false

local function zoneName(z: number): string
	return if z == 0 then Config.Hub.Name else Config.Zones[z].Name
end

local function zoneAccent(z: number): Color3
	return if z == 0 then Theme.Volt else Config.Zones[z].Accent
end

local function teleport(z: number)
	busy = true
	local ok = ClientState.request(Net.Actions.Teleport, z)
	busy = false
	if ok then
		Juice.flash(Theme.Electric, 0.35)
		win.close()
	else
		Sounds.play("Error")
	end
end

local function unlock(z: number, card: Card)
	local d = ClientState.get()
	if not d then
		return
	end
	local cost = Economy.zoneCost(z)
	if d.Volts < cost then
		Sounds.play("Error")
		ClientState.Toast:Fire("Не хватает ⚡ " .. Format.short(cost - d.Volts), "bad")
		return
	end
	busy = true
	local ok = ClientState.request(Net.Actions.UnlockZone, z)
	busy = false
	if ok then
		Sounds.play("Purchase")
		local scale = card.frame:FindFirstChildOfClass("UIScale")
		if scale then
			UIKit.bump(scale, 0.08)
		end
	else
		Sounds.play("Error")
	end
end

local function makeCard(parent: Instance, z: number): Card
	local accent = zoneAccent(z)
	local frame = UIKit.card({
		Name = "Zone" .. z,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		LayoutOrder = z,
		Parent = parent,
	})
	UIKit.new("UIScale", { Scale = 1, Parent = frame })
	UIKit.tintCard(frame, Theme.CardHover:Lerp(accent, 0.25), Theme.PanelDark)
	-- значок острова
	local circle = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.fromOffset(12, 12),
		BackgroundColor3 = WHITE,
		Parent = frame,
	}) :: Frame
	UIKit.round(circle)
	UIKit.stroke(circle, 3, Theme.Stroke)
	UIKit.gradient(circle, accent:Lerp(WHITE, 0.3), accent:Lerp(BLACK, 0.3))
	UIKit.label({
		Name = "Glyph",
		Text = if z == 0 then "🏙" else tostring(z),
		Size = UDim2.fromScale(0.66, 0.66),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 40,
		NoStroke = z == 0,
		Parent = circle,
	})
	UIKit.label({
		Name = "Name",
		Text = zoneName(z),
		Size = UDim2.new(1, -96, 0, 60),
		Position = UDim2.fromOffset(86, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 28,
		Parent = frame,
	})
	local status = UIKit.label({
		Name = "Status",
		Text = "",
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 84),
		MaxTextSize = 22,
		Parent = frame,
	})
	local lock = UIKit.label({
		Name = "Lock",
		Text = "🔒",
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		MaxTextSize = 30,
		NoStroke = true,
		Visible = false,
		Parent = frame,
	})
	local card: Card
	local button = UIKit.button({
		Name = "Action",
		Text = "",
		Color = Theme.Electric,
		Size = UDim2.new(1, -24, 0, 66),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		TextSize = 26,
		Parent = frame,
	}, function()
		local d = ClientState.get()
		if busy or not d then
			return
		end
		local here = ClientState.zone()
		if z == here then
			ClientState.Toast:Fire("Ты уже здесь!", "info")
			return
		end
		if z == 0 or z <= d.Zone then
			teleport(z)
		elseif z == d.Zone + 1 then
			unlock(z, card)
		else
			Sounds.play("Error")
			ClientState.Toast:Fire("Сначала открой «" .. Config.Zones[z - 1].Name .. "»", "info")
		end
	end)
	card = { zone = z, frame = frame, status = status, button = button, lock = lock }
	return card
end

local function refreshCard(c: Card, d: PlayerData.Data, here: number)
	local z = c.zone
	local open = z == 0 or z <= d.Zone
	c.lock.Visible = not open
	if z == here then
		c.status.Text = "📍 Ты здесь"
		c.status.TextColor3 = Theme.Good
		UIKit.setButtonText(c.button, "Ты здесь")
		UIKit.setButtonColor(c.button, Theme.GrayDark)
	elseif open then
		c.status.Text = if z == 0 then "Магазин, питомцы, награды" else "✔ Открыт"
		c.status.TextColor3 = if z == 0 then Theme.TextDim else Theme.Green
		UIKit.setButtonText(c.button, "🌀 Лететь")
		UIKit.setButtonColor(c.button, Theme.Electric, Theme.ElectricDark)
	elseif z == d.Zone + 1 then
		local cost = Economy.zoneCost(z)
		c.status.Text = "Цена: ⚡ " .. Format.short(cost)
		c.status.TextColor3 = Theme.Volt
		UIKit.setButtonText(c.button, "Открыть за ⚡" .. Format.short(cost))
		UIKit.setButtonColor(c.button, if d.Volts >= cost then Theme.Green else Theme.Gray)
	else
		c.status.Text = "Сначала открой предыдущий"
		c.status.TextColor3 = Theme.TextDim
		UIKit.setButtonText(c.button, "⚡ " .. Format.short(Economy.zoneCost(z)))
		UIKit.setButtonColor(c.button, Theme.GrayDark)
	end
end

local function refresh()
	local d = ClientState.get()
	if not d or not win.isOpen() then
		return
	end
	voltsLabel.Text = Format.short(d.Volts)
	local here = ClientState.zone()
	for _, c in cards do
		refreshCard(c, d, here)
	end
end

function TeleportUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Teleport",
		Title = "Острова",
		Icon = "🌀",
		Width = 880,
		Height = 540,
		Accent = Theme.PurpleDark,
		OnOpen = function()
			refresh()
			ClientState.WindowOpened:Fire("Teleport")
		end,
		OnClose = function()
			ClientState.WindowClosed:Fire("Teleport")
		end,
	})
	voltsLabel = UIKit.headerCounter(win, "⚡", Theme.Volt)
	local holder = UIKit.new("Frame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = win.Body,
	}) :: Frame
	local layout = UIKit.grid(holder, CARD, 14)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	table.insert(cards, makeCard(holder, 0)) -- хаб
	for z = 1, #Config.Zones do
		table.insert(cards, makeCard(holder, z))
	end

	ClientState.Changed:Connect(refresh)
	ClientState.ZoneChanged:Connect(function()
		refresh()
	end)
	ClientState.OpenWindow:Connect(function(name: string)
		local base = UIKit.parseWindowName(name)
		if base == "Teleport" then
			win.open()
		end
	end)
end

function TeleportUI.open()
	if win then
		win.open()
	end
end

return TeleportUI
