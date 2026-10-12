--!strict
-- Магазин Рэя (гараж): вкладки по категориям, строки предметов с ценой и количеством,
-- покупка через Remotes.BuyItem (RemoteFunction), продажа яблок через Remotes.SellApples.
-- Открывается по FXEvent("OpenShop"), закрывается крестиком, затемнением, меню Roblox (Esc)
-- и автоматически при переходе в Alert/Night (ночью магазин закрыт).

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

local ShopUI = {}

local DESIGN_W, DESIGN_H = 880, 470
local SIDE_W = 270
local ROW_H = 72

type Row = {
	Def: Config.ItemDef,
	Frame: Frame,
	Name: TextLabel,
	Desc: TextLabel,
	Owned: TextLabel,
	Buy: TextButton,
}

local TABS: { Config.ItemCategory } = { "Defense", "Offense", "Utility", "Farm" }

local modal: UIKit.Modal
local tabButtons: { [string]: TextButton } = {}
local list: ScrollingFrame
local rows: { Row } = {}
local currentTab: Config.ItemCategory = "Defense"
local busy = false

local sellButton: TextButton
local cashLabel: TextLabel
local applesLabel: TextLabel
local treesLabel: TextLabel

----------------------------------------------------------------------
-- Цены и количество
----------------------------------------------------------------------
local function priceMult(): number
	return Config.getDifficulty(ClientState.Snapshot.Difficulty).PriceMult
end

local function priceOf(def: Config.ItemDef): number
	local known = ClientState.Snapshot.Prices[def.Id]
	if type(known) == "number" then
		return math.floor(known)
	end
	local owned = ClientState.Snapshot.Upgrades[def.Id] or 0
	local base = def.Price
	if def.Id == "AppleTree" then
		local tiers = Config.Economy.TreePrices
		base = tiers[math.clamp(owned + 1, 1, #tiers)]
	end
	return math.floor((base + def.PriceStep * owned) * priceMult())
end

local function inventoryCount(itemId: string): number
	local total = 0
	for _, slot in ClientState.Inventory do
		if slot and slot.ItemId == itemId then
			total += slot.Count or 1
		end
	end
	return total
end

local function sellEstimate(): (number, number)
	local apples = math.floor(ClientState.Snapshot.Apples)
	local level = ClientState.Profile.Perks.Scavenger or 0
	local bonus = Config.perkValue("Scavenger", level)
	local value = math.floor(apples * Config.Economy.AppleValue * priceMult() * (1 + bonus))
	return apples, value
end

----------------------------------------------------------------------
-- Покупка / продажа
----------------------------------------------------------------------
local function refresh()
	local snap = ClientState.Snapshot
	local cash = math.floor(snap.Cash)
	UIKit.setText(cashLabel, Locale.t("Cash", cash))
	UIKit.setText(applesLabel, Locale.t("Apples", math.floor(snap.Apples)))
	UIKit.setText(treesLabel, Locale.t("TreesCount", math.floor(snap.Trees)))
	local apples, value = sellEstimate()
	UIKit.setButtonText(sellButton, Locale.t("SellApples", apples, value))
	UIKit.setButtonEnabled(sellButton, apples > 0 and not busy)

	for _, row in rows do
		local def = row.Def
		row.Frame.Visible = def.Category == currentTab
		if not row.Frame.Visible then
			continue
		end
		UIKit.setText(row.Name, Locale.item(def.Id))
		UIKit.setText(row.Desc, Locale.itemDesc(def.Id))
		local price = priceOf(def)
		local maxed = false
		if def.Kind == "Upgrade" then
			local owned = math.floor(snap.Upgrades[def.Id] or 0)
			if def.MaxOwned > 0 then
				maxed = owned >= def.MaxOwned
				UIKit.setText(row.Owned, if maxed then Locale.t("PerkMax") else string.format("%d / %d", owned, def.MaxOwned))
			else
				UIKit.setText(row.Owned, if owned > 0 then Locale.t("Owned", owned) else "")
			end
		else
			local count = inventoryCount(def.Id)
			UIKit.setText(row.Owned, if count > 0 then Locale.t("Owned", count) else "")
		end
		if maxed then
			UIKit.setButtonText(row.Buy, Locale.t("PerkMax"))
			UIKit.styleDark(row.Buy, Theme.Gray)
			UIKit.setButtonEnabled(row.Buy, false)
		else
			UIKit.setButtonText(row.Buy, Locale.t("Buy") .. " · " .. Locale.t("Cash", price))
			UIKit.styleDark(row.Buy, if cash >= price then Theme.Cash else Theme.TextDim)
			UIKit.setButtonEnabled(row.Buy, not busy)
		end
	end
	for id, button in tabButtons do
		local active = id == currentTab
		UIKit.styleDark(button, if active then Theme.Amber else Theme.TextDim, if active then Theme.Card else Theme.PanelLight)
		UIKit.setButtonText(button, Locale.t("Cat_" .. id))
	end
end

local function buy(def: Config.ItemDef)
	if busy then
		return
	end
	busy = true
	refresh()
	local ok, success, message = pcall(function()
		return Remotes.BuyItem:InvokeServer(def.Id)
	end)
	busy = false
	if not modal.IsOpen then
		return
	end
	refresh()
	if not ok then
		ClientState.Notified:Fire("N_CantNow", "error")
		return
	end
	local key = if type(message) == "string" then message else (if success == true then "N_Bought" else "N_CantNow")
	ClientState.Notified:Fire(key, if success == true then "success" else "error", { def.Id })
end

local function sell()
	local apples = sellEstimate()
	if apples <= 0 or busy then
		return
	end
	Remotes.SellApples:FireServer()
end

----------------------------------------------------------------------
-- Построение
----------------------------------------------------------------------
local function makeRow(def: Config.ItemDef, order: number): Row
	local frame = UIKit.new("Frame", {
		Name = def.Id,
		Size = UDim2.new(1, -8, 0, ROW_H),
		BackgroundColor3 = Theme.Card,
		BackgroundTransparency = 0.35,
		LayoutOrder = order,
		Visible = false,
		Parent = list,
	}) :: Frame
	UIKit.corner(frame, 6)
	UIKit.new("UIStroke", { Thickness = 1, Color = Theme.GrayDark, Transparency = 0.4, Parent = frame })
	UIKit.new("Frame", {
		Name = "Swatch",
		Size = UDim2.new(0, 4, 1, -16),
		Position = UDim2.new(0, 6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = def.Color,
		BackgroundTransparency = 0.2,
		Parent = frame,
	})
	UIKit.corner(frame:FindFirstChild("Swatch") :: Instance, 2)
	local name = UIKit.label({
		Name = "Name",
		Text = "",
		Size = UDim2.new(1, -220, 0, 26),
		Position = UDim2.fromOffset(18, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = frame,
	})
	local desc = UIKit.label({
		Name = "Desc",
		Text = "",
		Size = UDim2.new(1, -220, 0, 32),
		Position = UDim2.fromOffset(18, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		NoStroke = true,
		Parent = frame,
	})
	local owned = UIKit.label({
		Name = "Owned",
		Text = "",
		Size = UDim2.fromOffset(160, 18),
		Position = UDim2.new(1, -176, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 13,
		NoStroke = true,
		Parent = frame,
	})
	local buyButton = UIKit.button({
		Name = "Buy",
		Text = "",
		Size = UDim2.fromOffset(160, ROW_H - 12),
		Position = UDim2.new(1, -6, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 18,
		Parent = frame,
	}, function()
		buy(def)
	end)
	UIKit.styleDark(buyButton, Theme.Cash)
	return { Def = def, Frame = frame, Name = name, Desc = desc, Owned = owned, Buy = buyButton }
end

local function build()
	local gui = UIKit.new("ScreenGui", {
		Name = "ShopUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 40,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	modal = UIKit.modal({
		Name = "Shop",
		Width = DESIGN_W,
		Height = DESIGN_H,
		Parent = gui,
	})
	local body = modal.Body

	-- вкладки
	local tabs = UIKit.new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -SIDE_W - 12, 0, 46),
		BackgroundTransparency = 1,
		Parent = body,
	}) :: Frame
	UIKit.list(tabs, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	for i, id in TABS do
		local button = UIKit.button({
			Name = id,
			Text = "",
			Size = UDim2.new(0.25, -6, 1, 0),
			LayoutOrder = i,
			TextSize = 18,
			Parent = tabs,
		}, function()
			currentTab = id
			list.CanvasPosition = Vector2.zero
			refresh()
		end)
		UIKit.styleDark(button, Theme.TextDim)
		tabButtons[id] = button
	end

	-- список предметов
	list = UIKit.new("ScrollingFrame", {
		Name = "Items",
		Size = UDim2.new(1, -SIDE_W - 12, 1, -54),
		Position = UDim2.fromOffset(0, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Gray,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = body,
	}) :: ScrollingFrame
	UIKit.list(list, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	for i, def in Config.itemList() do
		table.insert(rows, makeRow(def, i))
	end

	-- правая колонка: продажа яблок и касса отряда
	local side = UIKit.new("Frame", {
		Name = "Side",
		Size = UDim2.new(0, SIDE_W, 1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.3,
		Parent = body,
	}) :: Frame
	UIKit.corner(side, 6)
	UIKit.new("UIStroke", { Thickness = 1, Color = Theme.GrayDark, Transparency = 0.4, Parent = side })
	cashLabel = UIKit.label({
		Name = "Cash",
		Text = "$0",
		Size = UDim2.new(1, -24, 0, 44),
		Position = UDim2.fromOffset(12, 10),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Cash,
		MaxTextSize = 34,
		NoStroke = true,
		Parent = side,
	})
	applesLabel = UIKit.label({
		Name = "Apples",
		Text = "",
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(12, 60),
		FontFace = Theme.FontBold,
		MaxTextSize = 18,
		NoStroke = true,
		Parent = side,
	})
	treesLabel = UIKit.label({
		Name = "Trees",
		Text = "",
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 86),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		NoStroke = true,
		Parent = side,
	})
	sellButton = UIKit.button({
		Name = "Sell",
		Text = "",
		Size = UDim2.new(1, -24, 0, 92),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 22,
		Parent = side,
	}, sell)
	UIKit.styleDark(sellButton, Theme.Amber, Theme.AmberDark:Lerp(Color3.new(0, 0, 0), 0.55))
	UIKit.thinStroke(sellButton, Theme.Amber, 0.1, 2)
	UIKit.label({
		Name = "Hint",
		Text = "",
		Size = UDim2.new(1, -24, 0, 60),
		Position = UDim2.new(0.5, 0, 0, 222),
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		NoStroke = true,
		Parent = side,
	})
end

----------------------------------------------------------------------
-- Открытие / закрытие
----------------------------------------------------------------------
local function relabel()
	modal.Title.Text = Locale.t("ShopTitle")
	local hint = modal.Body:FindFirstChild("Side") and (modal.Body:FindFirstChild("Side") :: Instance):FindFirstChild("Hint")
	if hint and hint:IsA("TextLabel") then
		hint.Text = Locale.t("Tip_Shop")
	end
	refresh()
end

function ShopUI.open()
	if modal.IsOpen then
		return
	end
	if ClientState.isNight() then
		ClientState.Notified:Fire("N_ShopClosed", "error")
		return
	end
	relabel()
	list.CanvasPosition = Vector2.zero
	modal:Open()
end

function ShopUI.close()
	modal:Hide()
end

function ShopUI.isOpen(): boolean
	return modal.IsOpen
end

function ShopUI.init()
	build()
	relabel()

	ClientState.FXEvent:Connect(function(kind: string, _params: { [string]: any }?)
		if kind == "OpenShop" then
			ShopUI.open()
		end
	end)
	ClientState.StateChanged:Connect(function(snap: ClientState.StateSnapshot)
		if not modal.IsOpen then
			return
		end
		if snap.Phase == "Alert" or snap.Phase == "Night" or not ClientState.inMatch() then
			modal:Hide()
		else
			refresh()
		end
	end)
	ClientState.InventoryChanged:Connect(function()
		if modal.IsOpen then
			refresh()
		end
	end)
	ClientState.ProfileChanged:Connect(function()
		if modal.IsOpen then
			refresh()
		end
	end)
	ClientState.SettingsChanged:Connect(relabel)
	GuiService.MenuOpened:Connect(function()
		modal:Hide()
	end)
end

return ShopUI
