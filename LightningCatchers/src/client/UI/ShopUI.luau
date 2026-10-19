--!strict
-- Магазин: улучшения (5 дорожек), острова (открыть следующий), Тесла-дрон.
-- Вид — «электро-наклейка» (docs/STYLE.md §8): карточки с иконкой-значком, названия Montserrat,
-- описания Nunito, цены Oswald на кнопке, знаки состояния нарисованы (без ✔ 🔒 в тексте).

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
-- Покупка: звук, пружинка карточки и вспышка обводки
local function pulseCard(card: Frame)
	local scale = card:FindFirstChildOfClass("UIScale")
	if scale then
		UIKit.bump(scale, 0.06)
	end
	UIKit.flashCard(card)
end

local function notEnough(cost: number)
	local d = ClientState.get()
	local have = if d then d.Volts else 0
	Sounds.play("Error")
	ClientState.Toast:Fire("Не хватает ⚡ " .. Format.short(math.max(0, cost - have)), "bad")
end

-- Кнопка с ценой: хватает — Go, не хватает — Slate и цена цветом DangerHi (§8.4)
local function priceButton(button: TextButton, verb: string?, cost: number, have: number)
	UIKit.setButtonPrice(button, verb, "⚡ " .. Format.short(cost))
	if have >= cost then
		UIKit.setButtonVariant(button, "Go")
	else
		UIKit.setButtonVariant(button, "Slate")
		local price = UIKit.buttonPart(button, "Price")
		if price then
			price.TextColor3 = Theme.DangerHi
		end
	end
end

-- «заряд ×4.60» и «заряд ×4.90» → «заряд ×4.60  ›  ×4.90» (общее первое слово не повторяем)
local function effectStep(now: string, nextText: string): string
	local w1, rest1 = string.match(now, "^(%S+)%s+(.+)$")
	local w2, rest2 = string.match(nextText, "^(%S+)%s+(.+)$")
	if w1 and w2 and w1 == w2 and rest1 and rest2 then
		return w1 .. " " .. rest1 .. "  ›  " .. rest2
	end
	return now .. "  ›  " .. nextText
end

-- Название (D5: Montserrat Black прямой), описание (B1/B2: Nunito)
local function nameLabel(parent: Instance, text: string, size: UDim2, pos: UDim2, maxSize: number): TextLabel
	return UIKit.label({
		Name = "Name",
		Text = text,
		FontFace = Theme.FontDisplayFlat,
		Size = size,
		Position = pos,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = maxSize,
		Parent = parent,
	})
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
	UIKit.list(scroller, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 4, 6)
	for i, id in Config.UpgradeOrder do
		local def = Config.Upgrades[id]
		local card = UIKit.card({
			Name = id,
			Size = UDim2.fromOffset(CARD_W - 8, 118),
			LayoutOrder = i,
			Parent = scroller,
		})
		UIKit.new("UIScale", { Scale = 1, Parent = card })
		UIKit.iconBadge(card, def.Icon, Theme.Spark, 78, {
			Name = "Icon",
			Position = UDim2.new(0, 56, 0.5, 0),
		})
		nameLabel(card, def.Name, UDim2.fromOffset(340, 32), UDim2.fromOffset(114, 10), 26)
		local tag, level = UIKit.tag({
			Name = "Level",
			Size = UDim2.fromOffset(104, 26),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(594, 12),
			Parent = card,
		}, "ур. 0/0", 15)
		tag.Rotation = -2
		level.TextColor3 = Theme.Volt
		local effect = UIKit.label({
			Name = "Effect",
			Text = "",
			FontFace = Theme.FontBodyHeavy,
			Size = UDim2.fromOffset(480, 26),
			Position = UDim2.fromOffset(114, 44),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.SparkHi,
			MaxTextSize = 21,
			Parent = card,
		})
		UIKit.label({
			Name = "Desc",
			Text = def.Desc,
			Size = UDim2.fromOffset(480, 22),
			Position = UDim2.fromOffset(114, 70),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 17,
			Parent = card,
		})
		local bar = UIKit.bar({
			Name = "Progress",
			Size = UDim2.fromOffset(470, 12),
			Position = UDim2.fromOffset(114, 96),
			Color = Theme.Spark,
			Parent = card,
		})
		local entry: UpgradeCard
		local button = UIKit.button({
			Name = "Buy",
			Text = "",
			Color = Theme.Go,
			Size = UDim2.fromOffset(196, 76),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			TextSize = 22,
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
		c.level.Text = string.format("УР. %d/%d", lvl, def.MaxLevel)
		c.bar.set(lvl / def.MaxLevel)
		if cost then
			c.effect.Text = effectStep(Economy.effectText(c.id, lvl), Economy.effectText(c.id, lvl + 1))
			priceButton(c.button, "Купить", cost, d.Volts)
		else
			c.effect.Text = Economy.effectText(c.id, lvl)
			UIKit.setButtonText(c.button, "Макс")
			UIKit.setButtonVariant(c.button, "Disabled")
		end
	end
end

----------------------------------------------------------------------
-- Острова
----------------------------------------------------------------------
type IslandCard = {
	zone: number,
	frame: Frame,
	status: UIKit.Status,
	button: TextButton,
	busy: boolean,
}
local islandCards: { IslandCard } = {}

local function zoneInfo(i: number): string
	local z = Config.Zones[i]
	local parts = { string.format("заряд ×%s", Format.short(z.BaseCharge / Config.Zones[1].BaseCharge)) }
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
	UIKit.list(scroller, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 4, 6)
	for i, z in Config.Zones do
		local card = UIKit.card({
			Name = "Zone" .. i,
			Size = UDim2.fromOffset(CARD_W - 8, 106),
			LayoutOrder = i,
			Parent = scroller,
		})
		UIKit.new("UIScale", { Scale = 1, Parent = card })
		UIKit.tintCard(card, Theme.Night700:Lerp(z.Accent, 0.14), Theme.Night800, z.Accent)
		UIKit.numberBadge(card, tostring(i), z.Accent, 72, {
			Name = "Icon",
			Position = UDim2.new(0, 54, 0.5, 2),
		})
		nameLabel(card, z.Name, UDim2.fromOffset(420, 32), UDim2.fromOffset(108, 12), 26)
		UIKit.label({
			Name = "Info",
			Text = zoneInfo(i),
			Size = UDim2.fromOffset(470, 22),
			Position = UDim2.fromOffset(108, 46),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 18,
			Parent = card,
		})
		local status = UIKit.status(card, UDim2.fromOffset(470, 24), UDim2.fromOffset(108, 72), 19)
		local entry: IslandCard
		local button = UIKit.button({
			Name = "Action",
			Text = "",
			Color = Theme.Go,
			Size = UDim2.fromOffset(216, 74),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 2),
			TextSize = 22,
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
			c.status.set("pin", "Открыт — ты здесь", Theme.GoHi)
			UIKit.setButtonText(c.button, "Ты здесь")
			UIKit.setButtonVariant(c.button, "Disabled")
		elseif i <= d.Zone then
			c.status.set("check", "Открыт", Theme.GoHi)
			UIKit.setButtonText(c.button, "Лететь")
			UIKit.setButtonVariant(c.button, "Spark")
		elseif i == d.Zone + 1 then
			local cost = Economy.zoneCost(i)
			c.status.set("bolt", "Можно открыть", Theme.Volt)
			priceButton(c.button, "Открыть", cost, d.Volts)
		else
			c.status.set("lock", "Закрыт — сначала открой предыдущий", Theme.TextDim)
			UIKit.setButtonPrice(c.button, "Закрыт", "⚡ " .. Format.short(Economy.zoneCost(i)))
			UIKit.setButtonVariant(c.button, "Disabled")
		end
	end
end

----------------------------------------------------------------------
-- Тесла-дрон
----------------------------------------------------------------------
local droneStatus: UIKit.Status
local droneButton: TextButton
local droneCard: Frame
local droneBusy = false

local function buildDrone(page: Frame)
	droneCard = UIKit.card({
		Name = "Drone",
		Size = UDim2.fromOffset(640, 360),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = page,
	})
	UIKit.tintCard(droneCard, Theme.Night700:Lerp(Theme.Spark, 0.12), Theme.Night800, Theme.Spark)
	UIKit.new("UIScale", { Scale = 1, Parent = droneCard })
	UIKit.iconBadge(droneCard, "🤖", Theme.Spark, 112, {
		Name = "Icon",
		Position = UDim2.new(0.5, 0, 0, 80),
	})
	local name = UIKit.label({
		Name = "Name",
		Text = UIKit.upper(Config.Drone.Name),
		FontFace = Theme.FontDisplay,
		Size = UDim2.fromOffset(560, 40),
		Position = UDim2.new(0.5, 0, 0, 144),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 34,
		NoStroke = false,
		Parent = droneCard,
	})
	UIKit.italicPad(name, 10)
	UIKit.label({
		Name = "Desc",
		Text = Config.Drone.Desc,
		Size = UDim2.fromOffset(560, 28),
		Position = UDim2.new(0.5, 0, 0, 188),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 21,
		Parent = droneCard,
	})
	droneStatus = UIKit.status(droneCard, UDim2.fromOffset(360, 28), UDim2.new(0.5, -150, 0, 222), 21)
	droneButton = UIKit.button({
		Name = "Action",
		Text = "",
		Color = Theme.Go,
		Size = UDim2.fromOffset(300, 76),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		TextSize = 26,
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
			droneStatus.set("check", "Дрон работает", Theme.GoHi)
			UIKit.setButtonText(droneButton, "Выключить")
			UIKit.setButtonVariant(droneButton, "Slate")
		else
			droneStatus.set("minus", "Дрон отдыхает", Theme.TextDim)
			UIKit.setButtonText(droneButton, "Включить")
			UIKit.setButtonVariant(droneButton, "Go")
		end
	elseif d.Zone < Config.Drone.FromZone then
		droneStatus.set("lock", "Нужен остров «" .. Config.Zones[Config.Drone.FromZone].Name .. "»", Theme.TextDim)
		UIKit.setButtonPrice(droneButton, "Купить", "⚡ " .. Format.short(Config.Drone.Cost))
		UIKit.setButtonVariant(droneButton, "Disabled")
	else
		droneStatus.set("bolt", "Можно купить", Theme.Volt)
		priceButton(droneButton, "Купить", Config.Drone.Cost, d.Volts)
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
		Accent = Theme.Volt,
		Tabs = {
			{ Id = "upgrades", Text = "Улучшения" },
			{ Id = "islands", Text = "Острова" },
			{ Id = "drone", Text = "Дрон" },
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
