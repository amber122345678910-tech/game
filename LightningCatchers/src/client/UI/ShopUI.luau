--!strict
-- Магазин: улучшения (5 дорожек), острова (открыть следующий), Тесла-дрон.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local TeleportUI = require(script.Parent.TeleportUI)

local ShopUI = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CARD_W = 824

local KIND_NAMES = {
	double = "двойные удары",
	fork = "молнии-вилки",
	fake = "молнии-обманки",
	runner = "бегущие кольца",
} :: { [string]: string }

local win: UIKit.Window
local voltsLabel: TextLabel

----------------------------------------------------------------------
-- Общие помощники
----------------------------------------------------------------------
local function iconCircle(parent: Instance, text: string, color: Color3, size: number, pos: UDim2): Frame
	local circle = UIKit.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		Position = pos,
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = WHITE,
		Parent = parent,
	}) :: Frame
	UIKit.round(circle)
	UIKit.stroke(circle, 3, Theme.Stroke)
	UIKit.gradient(circle, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.3))
	UIKit.label({
		Name = "Glyph",
		Text = text,
		Size = UDim2.fromScale(0.66, 0.66),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = math.floor(size * 0.6),
		NoStroke = true,
		Parent = circle,
	})
	return circle
end

-- Покупка: звук, пружинка карточки и вспышка обводки
local function pulseCard(card: Frame)
	local scale = card:FindFirstChildOfClass("UIScale")
	if scale then
		UIKit.bump(scale, 0.06)
	end
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Volt
		stroke.Thickness = 5
		UIKit.tween(stroke, 0.5, { Thickness = 2.5, Color = Theme.Stroke })
	end
end

local function notEnough(cost: number)
	local d = ClientState.get()
	local have = if d then d.Volts else 0
	Sounds.play("Error")
	ClientState.Toast:Fire("Не хватает ⚡ " .. Format.short(math.max(0, cost - have)), "bad")
end

----------------------------------------------------------------------
-- Улучшения
----------------------------------------------------------------------
type UpgradeCard = {
	id: Config.UpgradeId,
	frame: Frame,
	level: TextLabel,
	effect: TextLabel,
	bar: UIKit.Bar,
	button: TextButton,
	busy: boolean,
}
local upgradeCards: { UpgradeCard } = {}

local function buildUpgrades(page: Frame)
	local scroller = UIKit.scroll({
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		Parent = page,
	})
	UIKit.list(scroller, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 2, 4)
	for i, id in Config.UpgradeOrder do
		local def = Config.Upgrades[id]
		local card = UIKit.card({
			Name = id,
			Size = UDim2.fromOffset(CARD_W, 118),
			LayoutOrder = i,
			Parent = scroller,
		})
		UIKit.new("UIScale", { Scale = 1, Parent = card })
		iconCircle(card, def.Icon, Theme.Electric, 82, UDim2.new(0, 14, 0.5, 0))
		UIKit.label({
			Name = "Name",
			Text = def.Name,
			Size = UDim2.fromOffset(330, 34),
			Position = UDim2.fromOffset(110, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 30,
			Parent = card,
		})
		local level = UIKit.label({
			Name = "Level",
			Text = "",
			Size = UDim2.fromOffset(150, 30),
			Position = UDim2.fromOffset(440, 10),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Volt,
			MaxTextSize = 24,
			Parent = card,
		})
		local effect = UIKit.label({
			Name = "Effect",
			Text = "",
			Size = UDim2.fromOffset(480, 28),
			Position = UDim2.fromOffset(110, 44),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Good,
			MaxTextSize = 24,
			Parent = card,
		})
		UIKit.label({
			Name = "Desc",
			Text = def.Desc,
			Size = UDim2.fromOffset(480, 22),
			Position = UDim2.fromOffset(110, 72),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			FontFace = Theme.FontBold,
			MaxTextSize = 19,
			NoStroke = true,
			Parent = card,
		})
		local bar = UIKit.bar({
			Name = "Progress",
			Size = UDim2.fromOffset(480, 12),
			Position = UDim2.fromOffset(110, 98),
			Color = Theme.Electric,
			Parent = card,
		})
		local entry: UpgradeCard
		local button = UIKit.button({
			Name = "Buy",
			Text = "",
			Color = Theme.Green,
			Size = UDim2.fromOffset(200, 74),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			TextSize = 30,
			Parent = card,
		}, function()
			local d = ClientState.get()
			if not d or entry.busy then
				return
			end
			local lvl = (d.Upgrades :: any)[id] :: number
			local cost = Economy.upgradeCost(id, lvl)
			if not cost then
				Sounds.play("Error")
				ClientState.Toast:Fire("Уже максимум!", "info")
				return
			end
			if d.Volts < cost then
				notEnough(cost)
				return
			end
			entry.busy = true
			local ok = ClientState.request(Net.Actions.BuyUpgrade, id)
			entry.busy = false
			if ok then
				Sounds.play("PowerUp")
				pulseCard(card)
			else
				Sounds.play("Error")
			end
		end)
		entry = { id = id, frame = card, level = level, effect = effect, bar = bar, button = button, busy = false }
		table.insert(upgradeCards, entry)
	end
end

local function refreshUpgrades(d: PlayerData.Data)
	for _, c in upgradeCards do
		local def = Config.Upgrades[c.id]
		local lvl = (d.Upgrades :: any)[c.id] :: number
		local cost = Economy.upgradeCost(c.id, lvl)
		c.level.Text = string.format("ур. %d/%d", lvl, def.MaxLevel)
		c.bar.set(lvl / def.MaxLevel)
		if cost then
			c.effect.Text = Economy.effectText(c.id, lvl) .. "  →  " .. Economy.effectText(c.id, lvl + 1)
			UIKit.setButtonText(c.button, "⚡ " .. Format.short(cost))
			if d.Volts >= cost then
				UIKit.setButtonColor(c.button, Theme.Green)
			else
				UIKit.setButtonColor(c.button, Theme.Gray)
			end
		else
			c.effect.Text = Economy.effectText(c.id, lvl)
			UIKit.setButtonText(c.button, "МАКС")
			UIKit.setButtonColor(c.button, Theme.Gold)
		end
	end
end

----------------------------------------------------------------------
-- Острова
----------------------------------------------------------------------
type IslandCard = {
	zone: number,
	frame: Frame,
	status: TextLabel,
	button: TextButton,
	busy: boolean,
}
local islandCards: { IslandCard } = {}

local function zoneInfo(i: number): string
	local z = Config.Zones[i]
	local parts = { string.format("⚡ заряд ×%s", Format.short(z.BaseCharge / Config.Zones[1].BaseCharge)) }
	for id, k in Config.Kinds do
		if k.FromZone == i and KIND_NAMES[id] then
			table.insert(parts, "новое: " .. KIND_NAMES[id])
		end
	end
	if z.Overcharge and (i == 1 or not Config.Zones[i - 1].Overcharge) then
		table.insert(parts, "перегрузка банки")
	end
	return table.concat(parts, " • ")
end

local function buildIslands(page: Frame)
	local scroller = UIKit.scroll({
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		Parent = page,
	})
	UIKit.list(scroller, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 2, 4)
	for i, z in Config.Zones do
		local card = UIKit.card({
			Name = "Zone" .. i,
			Size = UDim2.fromOffset(CARD_W, 104),
			LayoutOrder = i,
			Parent = scroller,
		})
		UIKit.new("UIScale", { Scale = 1, Parent = card })
		UIKit.tintCard(card, Theme.CardHover:Lerp(z.Accent, 0.18), Theme.Card)
		iconCircle(card, tostring(i), z.Accent, 76, UDim2.new(0, 14, 0.5, 0))
		UIKit.label({
			Name = "Name",
			Text = z.Name,
			Size = UDim2.fromOffset(420, 36),
			Position = UDim2.fromOffset(104, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 30,
			Parent = card,
		})
		UIKit.label({
			Name = "Info",
			Text = zoneInfo(i),
			Size = UDim2.fromOffset(480, 24),
			Position = UDim2.fromOffset(104, 46),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			FontFace = Theme.FontBold,
			MaxTextSize = 20,
			NoStroke = true,
			Parent = card,
		})
		local status = UIKit.label({
			Name = "Status",
			Text = "",
			Size = UDim2.fromOffset(480, 26),
			Position = UDim2.fromOffset(104, 72),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 22,
			Parent = card,
		})
		local entry: IslandCard
		local button = UIKit.button({
			Name = "Action",
			Text = "",
			Color = Theme.Green,
			Size = UDim2.fromOffset(220, 72),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			TextSize = 26,
			Parent = card,
		}, function()
			local d = ClientState.get()
			if not d or entry.busy then
				return
			end
			if i <= d.Zone and ClientState.zone() == i then
				ClientState.Toast:Fire("Ты уже здесь!", "info")
				return
			end
			if i <= d.Zone then
				-- уже открыт: полететь туда
				-- общая с окном «Острова» пауза телепорта
				if TeleportUI.cooldownLeft() > 0 then
					TeleportUI.request(i) -- покажет, сколько ждать
					return
				end
				entry.busy = true
				local ok = TeleportUI.request(i)
				entry.busy = false
				if ok then
					win.close()
				else
					Sounds.play("Error")
				end
				return
			end
			if i > d.Zone + 1 then
				Sounds.play("Error")
				ClientState.Toast:Fire("Сначала открой «" .. Config.Zones[i - 1].Name .. "»", "info")
				return
			end
			local cost = Economy.zoneCost(i)
			if d.Volts < cost then
				notEnough(cost)
				return
			end
			entry.busy = true
			local ok = ClientState.request(Net.Actions.UnlockZone, i)
			entry.busy = false
			if ok then
				Sounds.play("Purchase")
				pulseCard(card)
			else
				Sounds.play("Error")
			end
		end)
		entry = { zone = i, frame = card, status = status, button = button, busy = false }
		table.insert(islandCards, entry)
	end
end

local function refreshIslands(d: PlayerData.Data)
	local here = ClientState.zone()
	for _, c in islandCards do
		local i = c.zone
		if i <= d.Zone and here == i then
			c.status.Text = "✔ Открыт — ты здесь"
			c.status.TextColor3 = Theme.Green
			UIKit.setButtonText(c.button, "📍 Ты здесь")
			UIKit.setButtonColor(c.button, Theme.GrayDark)
		elseif i <= d.Zone then
			c.status.Text = "✔ Открыт"
			c.status.TextColor3 = Theme.Green
			UIKit.setButtonText(c.button, "🌀 Лететь")
			UIKit.setButtonColor(c.button, Theme.Electric, Theme.ElectricDark)
		elseif i == d.Zone + 1 then
			local cost = Economy.zoneCost(i)
			c.status.Text = "Цена: ⚡ " .. Format.short(cost)
			c.status.TextColor3 = Theme.Volt
			UIKit.setButtonText(c.button, "Открыть за ⚡" .. Format.short(cost))
			UIKit.setButtonColor(c.button, if d.Volts >= cost then Theme.Green else Theme.Gray)
		else
			c.status.Text = "🔒 Закрыт — сначала открой предыдущий"
			c.status.TextColor3 = Theme.TextDim
			UIKit.setButtonText(c.button, "🔒 Закрыт")
			UIKit.setButtonColor(c.button, Theme.GrayDark)
		end
	end
end

----------------------------------------------------------------------
-- Тесла-дрон
----------------------------------------------------------------------
local droneStatus: TextLabel
local droneButton: TextButton
local droneCard: Frame
local droneBusy = false

local function buildDrone(page: Frame)
	droneCard = UIKit.card({
		Name = "Drone",
		Size = UDim2.fromOffset(620, 360),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = page,
	})
	UIKit.new("UIScale", { Scale = 1, Parent = droneCard })
	local icon = iconCircle(droneCard, "🤖", Theme.Electric, 116, UDim2.new(0.5, -58, 0, 78))
	icon.AnchorPoint = Vector2.new(0, 0.5)
	UIKit.label({
		Name = "Name",
		Text = Config.Drone.Name,
		Size = UDim2.fromOffset(560, 40),
		Position = UDim2.new(0.5, 0, 0, 142),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 38,
		Parent = droneCard,
	})
	UIKit.label({
		Name = "Desc",
		Text = Config.Drone.Desc,
		Size = UDim2.fromOffset(560, 28),
		Position = UDim2.new(0.5, 0, 0, 184),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 24,
		Parent = droneCard,
	})
	droneStatus = UIKit.label({
		Name = "Status",
		Text = "",
		Size = UDim2.fromOffset(560, 28),
		Position = UDim2.new(0.5, 0, 0, 218),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 24,
		Parent = droneCard,
	})
	droneButton = UIKit.button({
		Name = "Action",
		Text = "",
		Color = Theme.Green,
		Size = UDim2.fromOffset(300, 74),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		TextSize = 30,
		Parent = droneCard,
	}, function()
		local d = ClientState.get()
		if not d or droneBusy then
			return
		end
		if d.Drone then
			droneBusy = true
			local ok = ClientState.request(Net.Actions.ToggleDrone, not d.DroneOn)
			droneBusy = false
			if not ok then
				Sounds.play("Error")
			end
			return
		end
		if d.Zone < Config.Drone.FromZone then
			Sounds.play("Error")
			ClientState.Toast:Fire("Сначала открой «" .. Config.Zones[Config.Drone.FromZone].Name .. "»", "info")
			return
		end
		if d.Volts < Config.Drone.Cost then
			notEnough(Config.Drone.Cost)
			return
		end
		droneBusy = true
		local ok = ClientState.request(Net.Actions.BuyDrone, nil)
		droneBusy = false
		if ok then
			Sounds.play("Purchase")
			pulseCard(droneCard)
		else
			Sounds.play("Error")
		end
	end)
end

local function refreshDrone(d: PlayerData.Data)
	if d.Drone then
		if d.DroneOn then
			droneStatus.Text = "✔ Дрон работает"
			droneStatus.TextColor3 = Theme.Green
			UIKit.setButtonText(droneButton, "Выключить")
			UIKit.setButtonColor(droneButton, Theme.Gray)
		else
			droneStatus.Text = "Дрон отдыхает"
			droneStatus.TextColor3 = Theme.TextDim
			UIKit.setButtonText(droneButton, "Включить")
			UIKit.setButtonColor(droneButton, Theme.Green)
		end
	elseif d.Zone < Config.Drone.FromZone then
		droneStatus.Text = "🔒 Нужен остров «" .. Config.Zones[Config.Drone.FromZone].Name .. "»"
		droneStatus.TextColor3 = Theme.TextDim
		UIKit.setButtonText(droneButton, "⚡ " .. Format.short(Config.Drone.Cost))
		UIKit.setButtonColor(droneButton, Theme.GrayDark)
	else
		droneStatus.Text = "Цена: ⚡ " .. Format.short(Config.Drone.Cost)
		droneStatus.TextColor3 = Theme.Volt
		UIKit.setButtonText(droneButton, "Купить за ⚡" .. Format.short(Config.Drone.Cost))
		UIKit.setButtonColor(droneButton, if d.Volts >= Config.Drone.Cost then Theme.Green else Theme.Gray)
	end
end

----------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------
local function refreshBadges(d: PlayerData.Data)
	local upg = false
	for _, id in Config.UpgradeOrder do
		local cost = Economy.upgradeCost(id, (d.Upgrades :: any)[id] :: number)
		if cost and d.Volts >= cost then
			upg = true
			break
		end
	end
	win.setTabBadge("upgrades", upg)
	local nz = d.Zone + 1
	win.setTabBadge("islands", Config.Zones[nz] ~= nil and d.Volts >= Economy.zoneCost(nz))
	win.setTabBadge("drone", not d.Drone and d.Zone >= Config.Drone.FromZone and d.Volts >= Config.Drone.Cost)
end

local function refresh()
	local d = ClientState.get()
	if not d or not win.isOpen() then
		return
	end
	voltsLabel.Text = Format.short(d.Volts)
	refreshBadges(d)
	local tab = win.tab()
	if tab == "upgrades" then
		refreshUpgrades(d)
	elseif tab == "islands" then
		refreshIslands(d)
	elseif tab == "drone" then
		refreshDrone(d)
	end
end

function ShopUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Shop",
		Title = "Магазин",
		Icon = "🛒",
		Width = 880,
		Height = 560,
		Accent = Theme.GreenDark,
		Tabs = {
			{ Id = "upgrades", Text = "⚡ Улучшения" },
			{ Id = "islands", Text = "🏝 Острова" },
			{ Id = "drone", Text = "🤖 Дрон" },
		},
		OnOpen = function()
			refresh()
			ClientState.WindowOpened:Fire("Shop")
		end,
		OnClose = function()
			ClientState.WindowClosed:Fire("Shop")
		end,
		OnTab = function()
			refresh()
		end,
	})
	voltsLabel = UIKit.headerCounter(win, "⚡", Theme.Volt)
	buildUpgrades(win.Pages.upgrades)
	buildIslands(win.Pages.islands)
	buildDrone(win.Pages.drone)

	ClientState.Changed:Connect(refresh)
	ClientState.OpenWindow:Connect(function(name: string)
		local base, tab = UIKit.parseWindowName(name)
		if base == "Shop" then
			win.open(tab)
		elseif base == "Upgrades" then
			win.open("upgrades")
		elseif base == "Islands" or base == "Zones" then
			win.open("islands")
		elseif base == "Drone" then
			win.open("drone")
		end
	end)
end

function ShopUI.open(tab: string?)
	if win then
		win.open(tab)
	end
end

return ShopUI
