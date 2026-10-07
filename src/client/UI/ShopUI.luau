--!strict
-- Магазин: блоки, двери и готовые бункеры (с 3D-превью через ViewportFrame).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Prefabs = require(Shared:WaitForChild("Prefabs"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local ShopUI = {}

local DESIGN_W, DESIGN_H = 960, 620

local gui: ScreenGui
local overlay: TextButton
local window: Frame
local windowScale: UIScale
local content: ScrollingFrame
local coinsLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local confirmFrame: Frame
local currentTab = "Blocks"
local pendingConfirm: (() -> ())? = nil
local cardUpdaters: { () -> () } = {}
local pending = false

local TABS = {
	{ Id = "Blocks", Text = "🧱 Блоки" },
	{ Id = "Doors", Text = "🚪 Двери" },
	{ Id = "Bunkers", Text = "🏠 Бункеры" },
}

local function acidText(def: Config.BlockDef): (string, Color3)
	if def.AcidMult <= 0 then
		return "☣ Кислота: не действует", Theme.Acid
	elseif def.AcidMult >= 1.5 then
		return string.format("☣ Разъедается ×%.1f", def.AcidMult), Theme.Red
	elseif def.AcidMult >= 0.9 then
		return string.format("☣ Кислота ×%.1f", def.AcidMult), Theme.Orange
	end
	return string.format("☣ Стойкий ×%.2f", def.AcidMult), Theme.Acid
end

----------------------------------------------------------------------
-- Превью
----------------------------------------------------------------------
local function makeViewport(parent: Instance, size: UDim2, position: UDim2): (ViewportFrame, Camera)
	-- фон с градиентом отдельно: UIGradient на ViewportFrame затемнил бы и сам 3D-превью
	local bg = UIKit.new("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}) :: Frame
	UIKit.corner(bg, 10)
	UIKit.gradient(bg, Color3.fromRGB(110, 125, 160), Color3.fromRGB(50, 56, 74))
	local vp = UIKit.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -2, -1),
		Parent = bg,
	}) :: ViewportFrame
	local camera = UIKit.new("Camera", { FieldOfView = 40, Parent = vp }) :: Camera
	vp.CurrentCamera = camera
	return vp, camera
end

local function previewPart(def: Config.BlockDef): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = def.Material
	p.Color = def.Color
	p.Transparency = def.Transparency
	p.Reflectance = def.Reflectance
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if def.IsDoor then
		p.Size = Vector3.new(4, 8, 1)
	else
		p.Size = Vector3.new(4, 4, 4)
	end
	return p
end

local function blockPreview(parent: Instance, def: Config.BlockDef)
	local vp, camera = makeViewport(parent, UDim2.new(1, -16, 0, 110), UDim2.new(0.5, 0, 0, 40))
	local p = previewPart(def)
	p.CFrame = CFrame.Angles(0, math.rad(35), 0)
	p.Parent = vp
	local dist = if def.IsDoor then 15 else 10
	camera.CFrame = CFrame.lookAt(Vector3.new(dist * 0.6, dist * 0.45, dist * 0.75), Vector3.zero)
end

local function prefabPreview(parent: Instance, prefabId: string)
	local vp, camera = makeViewport(parent, UDim2.new(1, -16, 0, 150), UDim2.new(0.5, 0, 0, 40))
	local layout = Prefabs.layout(prefabId)
	local model = Instance.new("Model")
	local minX, maxX, minZ, maxZ, maxY = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, e in layout do
		minX = math.min(minX, e.x)
		maxX = math.max(maxX, e.x)
		minZ = math.min(minZ, e.z)
		maxZ = math.max(maxZ, e.z)
		maxY = math.max(maxY, e.y)
	end
	local cx, cz = (minX + maxX + 1) / 2, (minZ + maxZ + 1) / 2
	for _, e in layout do
		local def = Config.Blocks[e.id]
		local p = previewPart(def)
		local h = def.HeightCells
		-- в превью z=0 (перед) смотрит на камеру
		p.CFrame = CFrame.new((e.x + 0.5 - cx) * 4, (e.y + h / 2) * 4, (cz - (e.z + 0.5)) * 4)
		p.Parent = model
	end
	model.Parent = vp
	local span = math.max(maxX - minX + 1, maxZ - minZ + 1, maxY + 1) * 4
	local dist = span * 1.9
	camera.CFrame = CFrame.lookAt(Vector3.new(dist * 0.55, dist * 0.55, dist * 0.8), Vector3.new(0, (maxY + 1) * 2, 0))
end

----------------------------------------------------------------------
-- Покупка
----------------------------------------------------------------------
local function purchase(kind: string, id: string, amount: number, button: TextButton?)
	if pending then
		return
	end
	pending = true
	if button then
		button.Active = false
	end
	local ok, success, message = pcall(function()
		return Remotes.Purchase:InvokeServer(kind, id, amount)
	end)
	pending = false
	if button then
		button.Active = true
	end
	if not ok then
		ClientState.notify("Ошибка связи с сервером", "error")
		return
	end
	ClientState.notify(if typeof(message) == "string" then message else "", if success == true then "purchase" else "error")
end

local function showConfirm(text: string, onYes: () -> ())
	local label = confirmFrame:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	pendingConfirm = onYes
	confirmFrame.Visible = true
end

----------------------------------------------------------------------
-- Карточки
----------------------------------------------------------------------
local function cardBase(order: number, w: number, h: number): Frame
	local card = UIKit.new("Frame", {
		Name = "Card",
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Theme.Card,
		LayoutOrder = order,
	}) :: Frame
	UIKit.corner(card, 12)
	UIKit.stroke(card, 3, Theme.PanelStroke)
	return card
end

local function blockCard(def: Config.BlockDef): Frame
	local card = cardBase(def.Order, 214, 318)
	UIKit.label({
		Text = def.Name,
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 22,
		Parent = card,
	})
	blockPreview(card, def)
	local info = UIKit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 74),
		Position = UDim2.new(0.5, 0, 0, 156),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = card,
	})
	UIKit.list(info, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.label({
		Text = "❤ Прочность: " .. def.HP,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		LayoutOrder = 1,
		Parent = info,
	})
	local acid, acidColor = acidText(def)
	UIKit.label({
		Text = acid,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = acidColor,
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = info,
	})
	if def.IsDoor then
		UIKit.label({
			Text = string.format("🚪 Держит кислоту: %g ст.", def.Seal),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Yellow,
			MaxTextSize = 18,
			LayoutOrder = 3,
			Parent = info,
		})
	else
		UIKit.label({
			Text = def.Description,
			Size = UDim2.new(1, 0, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextDim,
			FontFace = Theme.FontBody,
			MaxTextSize = 14,
			LayoutOrder = 3,
			NoStroke = true,
			Parent = info,
		})
	end
	local owned = UIKit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 232),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
		Parent = card,
	})
	local buy1 = UIKit.button({
		Text = "💰" .. def.Price,
		Color = Theme.Green,
		Size = UDim2.new(0.5, -12, 0, 48),
		Position = UDim2.new(0, 8, 1, -8),
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 22,
		Parent = card,
	})
	buy1.Activated:Connect(function()
		purchase("block", def.Id, 1, buy1)
	end)
	local buy10 = UIKit.button({
		Text = "×10 💰" .. UIKit.formatNumber(def.Price * 10),
		Color = Theme.Blue,
		Size = UDim2.new(0.5, -12, 0, 48),
		Position = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 20,
		Parent = card,
	})
	buy10.Activated:Connect(function()
		purchase("block", def.Id, 10, buy10)
	end)
	table.insert(cardUpdaters, function()
		owned.Text = "У тебя: " .. ClientState.blockCount(def.Id)
		local coins = if ClientState.Data then ClientState.Data.Coins else 0
		UIKit.setButtonColor(buy1, if coins >= def.Price then Theme.Green else Theme.GrayDark)
		UIKit.setButtonColor(buy10, if coins >= def.Price * 10 then Theme.Blue else Theme.GrayDark)
	end)
	return card
end

local function prefabCard(def: Prefabs.PrefabDef): Frame
	local card = cardBase(def.Order, 286, 400)
	UIKit.label({
		Text = def.Name,
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 24,
		Parent = card,
	})
	prefabPreview(card, def.Id)
	local info = UIKit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 120),
		Position = UDim2.new(0.5, 0, 0, 196),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = card,
	})
	UIKit.list(info, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.label({
		Text = def.Description,
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		FontFace = Theme.FontBody,
		MaxTextSize = 15,
		NoStroke = true,
		LayoutOrder = 1,
		Parent = info,
	})
	UIKit.label({
		Text = "❤ Прочность: " .. UIKit.formatNumber(Prefabs.totalHP(def.Id)),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = info,
	})
	local door = Config.Blocks[def.Door]
	UIKit.label({
		Text = string.format("🚪 %s (держит %g ст.)", door.Name, door.Seal),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Yellow,
		MaxTextSize = 16,
		LayoutOrder = 3,
		Parent = info,
	})
	local wall = Config.Blocks[def.Wall]
	UIKit.label({
		Text = "🧱 Стены: " .. wall.Name,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		LayoutOrder = 4,
		Parent = info,
	})
	local price = Prefabs.price(def.Id)
	local buy = UIKit.button({
		Name = "Buy",
		Text = if def.Free then "🎁 БЕСПЛАТНО" else "💰 " .. UIKit.formatNumber(price),
		Color = if def.Free then Theme.Purple else Theme.Green,
		Size = UDim2.new(1, -16, 0, 56),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 26,
		Parent = card,
	})
	if def.Free then
		ClientState.Elements.StarterBuy = buy
	end
	buy.Activated:Connect(function()
		local data = ClientState.Data
		if def.Free and data and data.StarterClaimed then
			ClientState.notify("Стартовая хижина уже получена", "info")
			return
		end
		local plot = ClientState.getPlotModel()
		local blocks = plot and plot:FindFirstChild("Blocks")
		local hasBuild = blocks ~= nil and #blocks:GetChildren() > 0
		if hasBuild and not ClientState.TutorialActive then
			showConfirm("Текущая постройка будет разобрана, а её блоки вернутся в инвентарь. Построить «" .. def.Name .. "»?", function()
				purchase("prefab", def.Id, 1, buy)
			end)
		else
			purchase("prefab", def.Id, 1, buy)
		end
	end)
	table.insert(cardUpdaters, function()
		local data = ClientState.Data
		local coins = if data then data.Coins else 0
		if def.Free then
			local claimed = data ~= nil and data.StarterClaimed
			UIKit.setButtonText(buy, if claimed then "✓ Получено" else "🎁 БЕСПЛАТНО")
			UIKit.setButtonColor(buy, if claimed then Theme.GrayDark else Theme.Purple)
		else
			UIKit.setButtonColor(buy, if coins >= price then Theme.Green else Theme.GrayDark)
		end
	end)
	return card
end

----------------------------------------------------------------------
-- Вкладки
----------------------------------------------------------------------
local function refreshCards()
	for _, fn in cardUpdaters do
		fn()
	end
	local data = ClientState.Data
	coinsLabel.Text = "💰 " .. UIKit.formatNumber(if data then data.Coins else 0)
end

local function showTab(tab: string)
	currentTab = tab
	ClientState.ShopTab = tab
	table.clear(cardUpdaters)
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	ClientState.Elements.StarterBuy = nil
	local grid = content:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.CellSize = if tab == "Bunkers" then UDim2.fromOffset(286, 400) else UDim2.fromOffset(214, 318)
	end
	if tab == "Bunkers" then
		for _, def in Prefabs.List do
			prefabCard(def).Parent = content
		end
	else
		for _, id in Config.BlockOrder do
			local def = Config.Blocks[id]
			if def.Category == tab then
				blockCard(def).Parent = content
			end
		end
	end
	for id, button in tabButtons do
		UIKit.setButtonColor(button, if id == tab then Theme.Yellow else Theme.GrayDark)
	end
	content.CanvasPosition = Vector2.zero
	refreshCards()
	ClientState.ShopTabChanged:Fire(tab)
end

local function setOpen(open: boolean)
	if open then
		if ClientState.ModalOpen and not window.Visible then
			-- другое окно уже открыто: магазин не открываем и флаг чужого окна не трогаем
			ClientState.ShopOpen = false
			return
		end
		if ClientState.BuildMode then
			ClientState.setBuildMode(false)
		end
		ClientState.ModalOpen = true
		overlay.Visible = true
		-- на телефоне прячем джойстик, пока открыт магазин
		if ClientState.isTouch() then
			pcall(function()
				GuiService.TouchControlsEnabled = false
			end)
		end
		showTab(currentTab)
		UIKit.popIn(window, windowScale)
	else
		local wasOpen = window.Visible
		window.Visible = false
		overlay.Visible = false
		confirmFrame.Visible = false
		pendingConfirm = nil
		if wasOpen then
			ClientState.ModalOpen = false
			pcall(function()
				GuiService.TouchControlsEnabled = true
			end)
		end
		-- освобождаем превью
		table.clear(cardUpdaters)
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
end

function ShopUI.init()
	gui = UIKit.new("ScreenGui", {
		Name = "BunkerShop",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	overlay = UIKit.new("TextButton", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = gui,
	}) :: TextButton
	overlay.Activated:Connect(function()
		ClientState.setShopOpen(false)
	end)

	window = UIKit.panel({
		Name = "Window",
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	windowScale = UIKit.autoScale(window, "modal", DESIGN_W, DESIGN_H)
	UIKit.gradient(window, Theme.PanelLight, Theme.Panel)

	UIKit.label({
		Text = "🛒 МАГАЗИН",
		Size = UDim2.fromOffset(300, 46),
		Position = UDim2.fromOffset(20, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Yellow,
		MaxTextSize = 40,
		Parent = window,
	})
	coinsLabel = UIKit.label({
		Text = "💰 0",
		Size = UDim2.fromOffset(260, 40),
		Position = UDim2.new(1, -90, 0, 16),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Yellow,
		MaxTextSize = 32,
		Parent = window,
	})
	local close = UIKit.button({
		Name = "Close",
		Text = "✕",
		Color = Theme.Red,
		Size = UDim2.fromOffset(60, 60),
		Position = UDim2.new(1, -12, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 34,
		Parent = window,
	}, function()
		ClientState.setShopOpen(false)
	end)
	ClientState.Elements.ShopClose = close

	local tabs = UIKit.new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -40, 0, 54),
		Position = UDim2.fromOffset(20, 76),
		BackgroundTransparency = 1,
		Parent = window,
	})
	UIKit.list(tabs, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
	for i, tab in TABS do
		local b = UIKit.button({
			Name = tab.Id,
			Text = tab.Text,
			Color = Theme.GrayDark,
			Size = UDim2.fromOffset(200, 50),
			LayoutOrder = i,
			TextSize = 24,
			Parent = tabs,
		}, function()
			showTab(tab.Id)
		end)
		tabButtons[tab.Id] = b
		ClientState.Elements["Tab" .. tab.Id] = b
	end

	content = UIKit.new("ScrollingFrame", {
		Name = "Content",
		Size = UDim2.new(1, -40, 1, -156),
		Position = UDim2.fromOffset(20, 140),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Gray,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = window,
	}) :: ScrollingFrame
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(214, 318),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = content,
	})
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = content,
	})

	-- Окно подтверждения
	confirmFrame = UIKit.panel({
		Name = "Confirm",
		Size = UDim2.fromOffset(560, 230),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		ZIndex = 20,
		Parent = window,
	})
	UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -40, 0, 120),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 24,
		ZIndex = 21,
		Parent = confirmFrame,
	})
	UIKit.button({
		Name = "Yes",
		Text = "Да, построить",
		Color = Theme.Green,
		Size = UDim2.fromOffset(230, 60),
		Position = UDim2.new(0.5, -10, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 21,
		Parent = confirmFrame,
	}, function()
		local callback = pendingConfirm
		pendingConfirm = nil
		confirmFrame.Visible = false
		if callback then
			callback()
		end
	end)
	UIKit.button({
		Name = "No",
		Text = "Отмена",
		Color = Theme.Red,
		Size = UDim2.fromOffset(230, 60),
		Position = UDim2.new(0.5, 10, 1, -16),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 21,
		Parent = confirmFrame,
	}, function()
		pendingConfirm = nil
		confirmFrame.Visible = false
	end)

	ClientState.ShopToggled:Connect(setOpen)
	ClientState.ShopTabRequested:Connect(function(tab)
		if window.Visible then
			showTab(tab)
		else
			currentTab = tab
		end
	end)
	ClientState.DataChanged:Connect(function()
		if window.Visible then
			refreshCards()
		end
	end)

	-- Киоск магазина в лобби
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "ShopPrompt" then
			ClientState.setShopOpen(true)
		end
	end)
end

return ShopUI
