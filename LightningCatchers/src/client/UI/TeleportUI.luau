--!strict
-- Острова: быстрый перелёт в хаб и на открытые острова; закрытые показывают цену.
-- Телепорт заряжается Config.Server.TeleportCooldown секунд (сервер проверяет сам) — кнопки показывают отсчёт;
-- ShopUI летает через TeleportUI.request, чтобы пауза была общей.

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

local CARD = Vector2.new(268, 196)

type Card = {
	zone: number,
	frame: Frame,
	status: UIKit.Status,
	button: TextButton,
	lock: Frame,
}

local win: UIKit.Window
local voltsLabel: TextLabel
local cards: { Card } = {}
local busy = false
local lastTeleport = -math.huge -- os.clock последнего удачного телепорта

-- Сколько секунд ещё заряжается телепорт (у сервера пауза отсчитывается чуть раньше — не опережаем его)
function TeleportUI.cooldownLeft(): number
	return math.max(0, Config.Server.TeleportCooldown - (os.clock() - lastTeleport))
end

-- Запрос телепорта с общей паузой (TeleportUI и вкладка «Острова» в магазине). true — полетели
function TeleportUI.request(z: number): boolean
	local left = TeleportUI.cooldownLeft()
	if left > 0 then
		Sounds.play("Error")
		ClientState.Toast:Fire(string.format("Телепорт заряжается: ещё %d с", math.ceil(left)), "info")
		return false
	end
	local ok = ClientState.request(Net.Actions.Teleport, z)
	if ok then
		lastTeleport = os.clock()
	end
	return ok
end

local function zoneName(z: number): string
	return if z == 0 then Config.Hub.Name else Config.Zones[z].Name
end

local function zoneAccent(z: number): Color3
	return if z == 0 then Theme.Volt else Config.Zones[z].Accent
end

local function teleport(z: number)
	if TeleportUI.cooldownLeft() > 0 then
		TeleportUI.request(z) -- покажет, сколько ждать
		return
	end
	busy = true
	local ok = TeleportUI.request(z)
	busy = false
	if ok then
		Juice.flash(Theme.Spark, 0.35)
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
	UIKit.tintCard(frame, Theme.Night700:Lerp(accent, 0.16), Theme.Night800, accent)
	-- значок острова: номер (Montserrat Black Italic) или город
	if z == 0 then
		UIKit.iconBadge(frame, "🏙", accent, 62, { Name = "Icon", Position = UDim2.fromOffset(44, 50) })
	else
		UIKit.numberBadge(frame, tostring(z), accent, 62, { Name = "Icon", Position = UDim2.fromOffset(44, 50) })
	end
	UIKit.label({
		Name = "Name",
		Text = zoneName(z),
		FontFace = Theme.FontDisplayFlat,
		Size = UDim2.new(1, -100, 0, 58),
		Position = UDim2.fromOffset(86, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 23,
		Parent = frame,
	})
	local status = UIKit.status(frame, UDim2.new(1, -28, 0, 24), UDim2.fromOffset(14, 88), 18)
	local lock = UIKit.glyph(frame, "lock", {
		Name = "Lock",
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 14),
		Color = Theme.TextDim,
		Stroke = 2,
		Visible = false,
	})
	local card: Card
	local button = UIKit.button({
		Name = "Action",
		Text = "",
		Color = Theme.Spark,
		Size = UDim2.new(1, -24, 0, 68),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		TextSize = 22,
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
		c.status.set("pin", "Ты здесь", Theme.SparkHi)
		UIKit.setButtonText(c.button, "Ты здесь")
		UIKit.setButtonVariant(c.button, "Disabled")
	elseif open then
		if z == 0 then
			c.status.set(nil, "Магазин, питомцы, награды", Theme.TextDim)
		else
			c.status.set("check", "Открыт", Theme.GoHi)
		end
		local cooldown = TeleportUI.cooldownLeft()
		if cooldown > 0 then
			UIKit.setButtonText(c.button, string.format("Ещё %d с", math.ceil(cooldown)))
			UIKit.setButtonVariant(c.button, "Disabled")
		else
			UIKit.setButtonText(c.button, "Лететь")
			UIKit.setButtonVariant(c.button, "Spark")
		end
	elseif z == d.Zone + 1 then
		local cost = Economy.zoneCost(z)
		c.status.set("bolt", "Можно открыть", Theme.Volt)
		UIKit.setButtonPrice(c.button, "Открыть", "⚡ " .. Format.short(cost))
		if d.Volts >= cost then
			UIKit.setButtonVariant(c.button, "Go")
		else
			UIKit.setButtonVariant(c.button, "Slate")
			local price = UIKit.buttonPart(c.button, "Price")
			if price then
				price.TextColor3 = Theme.DangerHi
			end
		end
	else
		c.status.set(nil, "Сначала открой предыдущий", Theme.TextDim)
		UIKit.setButtonPrice(c.button, "Закрыт", "⚡ " .. Format.short(Economy.zoneCost(z)))
		UIKit.setButtonVariant(c.button, "Disabled")
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
		Accent = Theme.Violet,
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
	-- отсчёт паузы телепорта на кнопках (и последнее обновление, когда пауза кончилась)
	task.spawn(function()
		local wasCooling = false
		while win.Gui.Parent do
			local cooling = TeleportUI.cooldownLeft() > 0
			if win.isOpen() and (cooling or wasCooling) then
				refresh()
			end
			wasCooling = cooling
			task.wait(0.5)
		end
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
