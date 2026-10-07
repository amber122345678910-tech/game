--!strict
-- Режим строительства (как в Build a Boat): призрак блока на сетке, установка и удаление.
-- ПК: ЛКМ — поставить (можно вести мышью), R — повернуть, X — удаление, B/Q — выход.
-- Телефон: тап — выбрать клетку (призрак), второй тап по той же клетке или кнопка «Поставить» — установить.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local player = Players.LocalPlayer

local BuildController = {}

local RAY_DISTANCE = 450
local TAP_SLOP = 18
local TAP_TIME = 0.35

local BLOCK_ICONS: { [string]: string } = {
	wood = "🪵",
	glass = "🪟",
	stone = "🪨",
	metal = "🔩",
	concrete = "🧱",
	steel = "⚙",
	titan = "💎",
	door_wood = "🚪",
	door_iron = "🚪",
	door_blast = "🛡",
}

type Target = {
	x: number,
	y: number,
	z: number,
	valid: boolean,
	reason: string?,
	part: BasePart?, -- для удаления
	hitCell: number?, -- клетка блока, в который попал луч (если это блок)
}

-- состояние
local active = false
local plot: Model? = nil
local origin = CFrame.new()
local selected: string? = nil
local rot = 0
local deleteMode = false
local target: Target? = nil
local touchTarget: Target? = nil -- выбранная тапом клетка (телефон)
local mouseHeld = false
local lastPlacedKey = ""
-- протяжка: только в слое первой установки и не "через" только что поставленные блоки
local dragY: number? = nil
local dragPlaced: { [number]: boolean } = {}
local lastReasonTime = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- зеркало занятых клеток моего участка: индекс клетки -> деталь
local occupied: { [number]: BasePart } = {}
local blockConns: { RBXScriptConnection } = {}

-- визуал
local ghost: Part
local ghostBox: SelectionBox
local deleteBox: SelectionBox
local gridGui: SurfaceGui? = nil

-- интерфейс
local gui: ScreenGui
local bottom: Frame
local hotbar: ScrollingFrame
local infoLabel: TextLabel
local hintLabel: TextLabel
local actions: Frame
local placeButton: TextButton
local deleteButton: TextButton
local confirmClear: Frame
local slots: { [string]: TextButton } = {}

----------------------------------------------------------------------
-- Зеркало блоков
----------------------------------------------------------------------
local function cellsOf(part: BasePart): { number }
	local cell = part:GetAttribute("Cell")
	local id = part:GetAttribute("BlockId")
	if typeof(cell) ~= "number" then
		return {}
	end
	local def = Config.getBlock(id)
	local height = if def then def.HeightCells else 1
	local x, y, z = Grid.coords(cell)
	return Grid.footprint(x, y, z, height)
end

local function trackBlock(child: Instance)
	if child:IsA("BasePart") then
		for _, c in cellsOf(child) do
			occupied[c] = child
		end
	end
end

local function untrackBlock(child: Instance)
	if child:IsA("BasePart") then
		for _, c in cellsOf(child) do
			if occupied[c] == child then
				occupied[c] = nil
			end
		end
	end
end

local function bindPlot(model: Model)
	for _, c in blockConns do
		c:Disconnect()
	end
	table.clear(blockConns)
	table.clear(occupied)
	local blocks = model:WaitForChild("Blocks", 10)
	if not blocks then
		return
	end
	for _, child in blocks:GetChildren() do
		trackBlock(child)
	end
	table.insert(
		blockConns,
		blocks.ChildAdded:Connect(function(child)
			trackBlock(child)
			if active and child:IsA("BasePart") then
				Sounds.playAt("Place", child.Position, 0.8)
			end
		end)
	)
	table.insert(
		blockConns,
		blocks.ChildRemoved:Connect(function(child)
			untrackBlock(child)
			if active and child:IsA("BasePart") then
				Sounds.playAt("Place", child.Position, 0.5)
			end
		end)
	)
	local buildArea = model:FindFirstChild("BuildArea")
	local list: { Instance } = { blocks }
	if buildArea then
		table.insert(list, buildArea)
	end
	rayParams.FilterDescendantsInstances = list
end

----------------------------------------------------------------------
-- Вычисление цели
----------------------------------------------------------------------
local function hasSupport(x: number, y: number, z: number, height: number): boolean
	if y == 0 then
		return true
	end
	for dy = 0, height - 1 do
		for _, d in Grid.NEIGHBORS do
			local nx, ny, nz = x + d[1], y + dy + d[2], z + d[3]
			if Grid.inBounds(nx, ny, nz) and occupied[Grid.index(nx, ny, nz)] then
				return true
			end
		end
	end
	return false
end

local function computeTarget(ray: Ray): Target?
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_DISTANCE, rayParams)
	if not result then
		return nil
	end
	if deleteMode then
		local inst = result.Instance
		local cell = inst:GetAttribute("Cell")
		if inst:IsA("BasePart") and typeof(cell) == "number" then
			local x, y, z = Grid.coords(cell)
			return { x = x, y = y, z = z, valid = true, part = inst }
		end
		return nil
	end
	local id = selected
	if not id then
		return nil
	end
	local def = Config.Blocks[id]
	local hitCellAttr = result.Instance:GetAttribute("Cell")
	local hitCell = if typeof(hitCellAttr) == "number" then hitCellAttr else nil
	local p = origin:PointToObjectSpace(result.Position + result.Normal * (Grid.CELL * 0.5))
	local x, y, z = Grid.localToCell(p.X, p.Y, p.Z)
	if not Grid.inBounds(x, math.max(y, 0), z) then
		return nil
	end
	y = math.max(y, 0)
	local t: Target = { x = x, y = y, z = z, valid = true, hitCell = hitCell }
	if not Grid.inBounds(x, y + def.HeightCells - 1, z) then
		t.valid = false
		t.reason = "Слишком высоко"
	else
		for _, c in Grid.footprint(x, y, z, def.HeightCells) do
			if occupied[c] then
				t.valid = false
				t.reason = "Клетка занята"
				break
			end
		end
	end
	if t.valid and not hasSupport(x, y, z, def.HeightCells) then
		t.valid = false
		t.reason = "Нужна опора"
	end
	if t.valid and ClientState.blockCount(id) < 1 then
		t.valid = false
		t.reason = "Нет блоков — купи в магазине"
	end
	return t
end

local function blockCFrame(x: number, y: number, z: number, height: number, r: number): CFrame
	local lx, _, lz = Grid.cellCenterLocal(x, y, z)
	return origin * CFrame.new(lx, (y + height / 2) * Grid.CELL, lz) * CFrame.Angles(0, r * math.pi / 2, 0)
end

local function targetKey(t: Target?): string
	if not t then
		return ""
	end
	return string.format("%d,%d,%d", t.x, t.y, t.z)
end

local function showTarget(t: Target?)
	if deleteMode then
		ghost.Transparency = 1
		ghostBox.Visible = false
		deleteBox.Adornee = if t then t.part else nil
		deleteBox.Visible = t ~= nil
		return
	end
	deleteBox.Visible = false
	local id = selected
	if not t or not id then
		ghost.Transparency = 1
		ghostBox.Visible = false
		return
	end
	local def = Config.Blocks[id]
	ghost.Size = if def.IsDoor then Vector3.new(Grid.CELL, Grid.CELL * 2, 1) else Vector3.new(Grid.CELL, Grid.CELL, Grid.CELL)
	ghost.CFrame = blockCFrame(t.x, t.y, t.z, def.HeightCells, rot)
	local color = if t.valid then Theme.Green else Theme.Red
	ghost.Color = color
	ghost.Transparency = 0.5
	ghostBox.Color3 = color
	ghostBox.Visible = true
end

----------------------------------------------------------------------
-- Действия
----------------------------------------------------------------------
local function notifyReason(reason: string?)
	if reason and os.clock() - lastReasonTime > 1.2 then
		lastReasonTime = os.clock()
		ClientState.notify(reason, "error")
	end
end

local function act(t: Target?)
	if not t then
		return
	end
	if deleteMode then
		Remotes.RemoveBlock:FireServer(t.x, t.y, t.z)
		return
	end
	local id = selected
	if not id then
		return
	end
	if not t.valid then
		notifyReason(t.reason)
		return
	end
	Remotes.PlaceBlock:FireServer(id, t.x, t.y, t.z, rot)
	-- оптимистично помечаем клетки, чтобы протяжка мышью не слала дубли
	lastPlacedKey = targetKey(t)
	dragPlaced[Grid.index(t.x, t.y, t.z)] = true
end

local function setDeleteMode(on: boolean)
	deleteMode = on
	touchTarget = nil
	UIKit.setButtonColor(deleteButton, if on then Theme.Red else Theme.GrayDark)
	UIKit.setButtonText(deleteButton, if on then "🗑 Удаление: ВКЛ" else "🗑 Удаление")
	UIKit.setButtonText(placeButton, if on then "✖ Убрать" else "✔ Поставить")
	UIKit.setButtonColor(placeButton, if on then Theme.Red else Theme.Green)
end

local function rotate()
	rot = (rot + 1) % 4
	target = nil -- перерисовать
end

----------------------------------------------------------------------
-- Интерфейс
----------------------------------------------------------------------
local function refreshInfo()
	local id = selected
	if deleteMode then
		infoLabel.Text = "🗑 Режим удаления: блоки возвращаются в инвентарь"
	elseif id then
		local def = Config.Blocks[id]
		infoLabel.Text = string.format("%s %s  •  ❤ %d  •  У тебя: %d", BLOCK_ICONS[id] or "", def.Name, def.HP, ClientState.blockCount(id))
	else
		infoLabel.Text = "Купи блоки в магазине 🛒"
	end
end

local function refreshSlots()
	for id, slot in slots do
		local count = ClientState.blockCount(id)
		local countLabel = slot:FindFirstChild("Count")
		if countLabel and countLabel:IsA("TextLabel") then
			countLabel.Text = tostring(count)
			countLabel.TextColor3 = if count > 0 then Theme.Text else Theme.Red
		end
		local stroke = slot:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == selected then Theme.Yellow else Theme.PanelStroke
			stroke.Thickness = if id == selected then 4 else 3
		end
	end
	refreshInfo()
end

local function select(id: string)
	selected = id
	if deleteMode then
		setDeleteMode(false)
	end
	target = nil
	touchTarget = nil
	refreshSlots()
end

local function buildSlot(id: string, order: number): TextButton
	local def = Config.Blocks[id]
	local slot = UIKit.new("TextButton", {
		Name = id,
		Size = UDim2.fromOffset(84, 92),
		BackgroundColor3 = def.Color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}) :: TextButton
	UIKit.corner(slot, 10)
	UIKit.stroke(slot, 3, Theme.PanelStroke)
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
		Rotation = 90,
		Parent = slot,
	})
	UIKit.label({
		Text = BLOCK_ICONS[id] or "■",
		Size = UDim2.new(1, 0, 0.55, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 36,
		NoStroke = true,
		Parent = slot,
	})
	UIKit.label({
		Name = "Count",
		Text = "0",
		Size = UDim2.new(1, -8, 0.35, 0),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		MaxTextSize = 24,
		Parent = slot,
	})
	slot.Activated:Connect(function()
		UIKit.playClick()
		if ClientState.blockCount(id) < 1 then
			ClientState.notify("Нет блоков «" .. def.Name .. "». Купи их в магазине!", "warning")
		end
		select(id)
	end)
	return slot
end

local function buildUI()
	gui = UIKit.new("ScreenGui", {
		Name = "BunkerBuild",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	-- нижняя панель: информация + хотбар
	bottom = UIKit.new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(640, 170),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(bottom, "hud")
	infoLabel = UIKit.label({
		Name = "Info",
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 22,
		Parent = bottom,
	})
	local bar = UIKit.panel({
		Name = "HotbarPanel",
		Size = UDim2.new(1, 0, 0, 112),
		Position = UDim2.new(0.5, 0, 0, 34),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.2,
		Parent = bottom,
	})
	hotbar = UIKit.new("ScrollingFrame", {
		Name = "Hotbar",
		Size = UDim2.new(1, -16, 1, -10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = bar,
	}) :: ScrollingFrame
	UIKit.list(hotbar, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = hotbar })
	for i, id in Config.BlockOrder do
		local slot = buildSlot(id, i)
		slot.Parent = hotbar
		slots[id] = slot
	end
	hintLabel = UIKit.label({
		Name = "Hint",
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
		Parent = bottom,
	})

	-- кнопки действий справа
	actions = UIKit.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.42, 0),
		Size = UDim2.fromOffset(210, 330),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(actions, "hud")
	UIKit.list(actions, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right)
	placeButton = UIKit.button({
		Name = "Place",
		Text = "✔ Поставить",
		Color = Theme.Green,
		Size = UDim2.fromOffset(210, 64),
		LayoutOrder = 1,
		TextSize = 26,
		Parent = actions,
	}, function()
		act(touchTarget)
		touchTarget = nil
	end)
	UIKit.button({
		Name = "Rotate",
		Text = "🔄 Повернуть",
		Color = Theme.Blue,
		Size = UDim2.fromOffset(210, 56),
		LayoutOrder = 2,
		TextSize = 24,
		Parent = actions,
	}, rotate)
	deleteButton = UIKit.button({
		Name = "Delete",
		Text = "🗑 Удаление",
		Color = Theme.GrayDark,
		Size = UDim2.fromOffset(210, 56),
		LayoutOrder = 3,
		TextSize = 24,
		Parent = actions,
	}, function()
		setDeleteMode(not deleteMode)
		refreshInfo()
	end)
	UIKit.button({
		Name = "Clear",
		Text = "🧹 Разобрать всё",
		Color = Theme.Orange,
		Size = UDim2.fromOffset(210, 56),
		LayoutOrder = 4,
		TextSize = 22,
		Parent = actions,
	}, function()
		confirmClear.Visible = true
	end)
	UIKit.button({
		Name = "Exit",
		Text = "✖ Выйти",
		Color = Theme.Red,
		Size = UDim2.fromOffset(210, 56),
		LayoutOrder = 5,
		TextSize = 24,
		Parent = actions,
	}, function()
		ClientState.setBuildMode(false)
	end)

	confirmClear = UIKit.panel({
		Name = "ConfirmClear",
		Size = UDim2.fromOffset(520, 210),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.PanelLight,
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(confirmClear, "hud")
	UIKit.label({
		Text = "Разобрать весь бункер? Все блоки вернутся в инвентарь.",
		Size = UDim2.new(1, -40, 0, 100),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 26,
		Parent = confirmClear,
	})
	UIKit.button({
		Text = "Разобрать",
		Color = Theme.Orange,
		Size = UDim2.fromOffset(220, 62),
		Position = UDim2.new(0.5, -10, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Parent = confirmClear,
	}, function()
		confirmClear.Visible = false
		Remotes.ClearPlot:FireServer()
	end)
	UIKit.button({
		Text = "Отмена",
		Color = Theme.GrayDark,
		Size = UDim2.fromOffset(220, 62),
		Position = UDim2.new(0.5, 10, 1, -16),
		AnchorPoint = Vector2.new(0, 1),
		Parent = confirmClear,
	}, function()
		confirmClear.Visible = false
	end)
end

local function refreshInputHints()
	local touch = ClientState.isTouch()
	placeButton.Visible = touch
	-- на телефоне хотбар уже и правее, чтобы не перекрывать зону джойстика слева
	bottom.Size = UDim2.fromOffset(if touch then 430 else 640, 170)
	bottom.Position = UDim2.new(if touch then 0.6 else 0.5, 0, 1, -10)
	if touch then
		hintLabel.Text = "Тап — выбрать клетку • второй тап или «Поставить» — поставить"
	else
		hintLabel.Text = "ЛКМ — поставить (можно вести) • R — повернуть • X — удаление • B — выйти"
	end
end

----------------------------------------------------------------------
-- Сетка на полу участка (только в режиме строительства)
----------------------------------------------------------------------
local function showGrid(model: Model)
	local area = model:FindFirstChild("BuildArea")
	if not area or not area:IsA("BasePart") then
		return
	end
	local surface = UIKit.new("SurfaceGui", {
		Name = "BuildGrid",
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 10,
		LightInfluence = 0,
		Adornee = area,
		Parent = area,
	}) :: SurfaceGui
	local cellsX = Grid.W
	local cellsZ = Grid.D
	for i = 0, cellsX do
		UIKit.new("Frame", {
			Size = UDim2.new(0, 2, 1, 0),
			Position = UDim2.new(i / cellsX, -1, 0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = surface,
		})
	end
	for i = 0, cellsZ do
		UIKit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.new(0, 0, i / cellsZ, -1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = surface,
		})
	end
	gridGui = surface
end

----------------------------------------------------------------------
-- Вход / выход
----------------------------------------------------------------------
local function onAction(actionName: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if actionName == "BuildRotate" then
		rotate()
	elseif actionName == "BuildDelete" then
		setDeleteMode(not deleteMode)
		refreshInfo()
	elseif actionName == "BuildExit" then
		ClientState.setBuildMode(false)
	end
	return Enum.ContextActionResult.Sink
end

local function enter()
	local model = ClientState.getPlotModel()
	if not model or ClientState.inStorm() then
		ClientState.setBuildMode(false)
		return
	end
	local o = ClientState.getOrigin(model)
	if not o then
		ClientState.setBuildMode(false)
		return
	end
	if ClientState.ShopOpen then
		ClientState.setShopOpen(false)
	end
	plot = model
	origin = o
	bindPlot(model)
	active = true
	target = nil
	touchTarget = nil
	setDeleteMode(false)
	-- выбираем первый блок, который есть в инвентаре
	if not selected or ClientState.blockCount(selected) < 1 then
		selected = nil
		for _, id in Config.BlockOrder do
			if ClientState.blockCount(id) > 0 then
				selected = id
				break
			end
		end
		selected = selected or Config.BlockOrder[1]
	end
	refreshSlots()
	refreshInputHints()
	gui.Enabled = true
	showGrid(model)
	ContextActionService:BindAction("BuildRotate", onAction, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("BuildDelete", onAction, false, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("BuildExit", onAction, false, Enum.KeyCode.Q)
	if not ClientState.isTouch() then
		ClientState.notify("Режим строительства: ЛКМ — поставить, R — повернуть, X — удаление", "info")
	end
end

local function exit()
	active = false
	mouseHeld = false
	target = nil
	touchTarget = nil
	gui.Enabled = false
	confirmClear.Visible = false
	ghost.Transparency = 1
	ghostBox.Visible = false
	deleteBox.Visible = false
	deleteBox.Adornee = nil
	if gridGui then
		gridGui:Destroy()
		gridGui = nil
	end
	ContextActionService:UnbindAction("BuildRotate")
	ContextActionService:UnbindAction("BuildDelete")
	ContextActionService:UnbindAction("BuildExit")
end

----------------------------------------------------------------------
-- Ввод
----------------------------------------------------------------------
type TouchInfo = { start: Vector3, t0: number, moved: boolean }
local touches: { [InputObject]: TouchInfo } = {}

local function touchCount(): number
	local n = 0
	for _ in touches do
		n += 1
	end
	return n
end

local function onTap(position: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- координаты InputObject уже учитывают отступ интерфейса -> ScreenPointToRay
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local t = computeTarget(ray)
	if not t then
		touchTarget = nil
		showTarget(nil)
		return
	end
	if touchTarget and targetKey(touchTarget) == targetKey(t) then
		act(t) -- второй тап по той же клетке
		touchTarget = nil
		showTarget(nil)
		return
	end
	touchTarget = t
	showTarget(t)
	if not t.valid then
		notifyReason(t.reason)
	end
end

local function bindInput()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = true
			lastPlacedKey = ""
			table.clear(dragPlaced)
			dragY = if target and not deleteMode then target.y else nil
			act(target)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = { start = input.Position, t0 = os.clock(), moved = false }
			if touchCount() > 1 then
				-- щипок/поворот камеры двумя пальцами — отменяем тапы
				for _, info in touches do
					info.moved = true
				end
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local info = touches[input]
		if info and (input.Position - info.start).Magnitude > TAP_SLOP then
			info.moved = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = false
			dragY = nil
			table.clear(dragPlaced)
			return
		end
		local info = touches[input]
		if info then
			touches[input] = nil
			if active and not info.moved and os.clock() - info.t0 < TAP_TIME then
				onTap(input.Position)
			end
		end
	end)
end

local function renderStep()
	if not active then
		return
	end
	if ClientState.isTouch() then
		-- на телефоне призрак показывает выбранную тапом клетку
		if touchTarget and not deleteMode and selected then
			-- пересчитать валидность (инвентарь/занятость могли измениться)
			local def = Config.Blocks[selected]
			local stillFree = true
			for _, c in Grid.footprint(touchTarget.x, touchTarget.y, touchTarget.z, def.HeightCells) do
				if occupied[c] then
					stillFree = false
				end
			end
			if not stillFree then
				touchTarget = nil
			end
		end
		showTarget(touchTarget)
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local t = computeTarget(ray)
	local key = targetKey(t)
	local changed = key ~= targetKey(target) or (t ~= nil and target ~= nil and t.valid ~= target.valid) or (t == nil) ~= (target == nil)
	target = t
	if changed then
		showTarget(t)
	end
	-- протяжка (только установка): ведём мышью с зажатой кнопкой — ставим в новые клетки
	-- того же слоя; лучи, попавшие в блоки этой же протяжки, игнорируем (иначе блоки
	-- "росли" бы в сторону камеры). Удаление — только кликом.
	if
		mouseHeld
		and not deleteMode
		and t
		and t.valid
		and key ~= lastPlacedKey
		and (dragY == nil or t.y == dragY)
		and not (t.hitCell and dragPlaced[t.hitCell])
	then
		if dragY == nil then
			dragY = t.y
		end
		act(t)
		lastPlacedKey = key
	end
end

function BuildController.init()
	ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.CastShadow = false
	ghost.Material = Enum.Material.SmoothPlastic
	ghost.Transparency = 1
	ghost.Size = Vector3.new(4, 4, 4)
	local fx = workspace:FindFirstChild("ClientFX")
	if not fx then
		fx = Instance.new("Folder")
		fx.Name = "ClientFX"
		fx.Parent = workspace
	end
	ghost.Parent = fx
	ghostBox = UIKit.new("SelectionBox", {
		Adornee = ghost,
		LineThickness = 0.06,
		Color3 = Theme.Green,
		SurfaceTransparency = 1,
		Visible = false,
		Parent = ghost,
	}) :: SelectionBox
	deleteBox = UIKit.new("SelectionBox", {
		LineThickness = 0.08,
		Color3 = Theme.Red,
		SurfaceColor3 = Theme.Red,
		SurfaceTransparency = 0.7,
		Visible = false,
		Parent = ghost,
	}) :: SelectionBox

	buildUI()
	bindInput()

	ClientState.BuildModeChanged:Connect(function(on)
		if on then
			enter()
		else
			exit()
		end
	end)
	ClientState.DataChanged:Connect(function()
		if active then
			refreshSlots()
		end
	end)
	ClientState.InputChanged:Connect(function()
		if active then
			refreshInputHints()
			touchTarget = nil
			target = nil
		end
	end)
	player:GetAttributeChangedSignal("InStorm"):Connect(function()
		if ClientState.inStorm() and ClientState.BuildMode then
			ClientState.setBuildMode(false)
		end
	end)
	player:GetAttributeChangedSignal("PlotId"):Connect(function()
		local model = ClientState.getPlotModel()
		if model then
			bindPlot(model)
		end
	end)

	-- B — включить/выключить строительство (всегда доступно)
	ContextActionService:BindAction("ToggleBuild", function(_, state)
		if state == Enum.UserInputState.Begin then
			if ClientState.inStorm() then
				ClientState.notify("Во время шторма строить нельзя!", "error")
			elseif not ClientState.ModalOpen then
				ClientState.setBuildMode(not ClientState.BuildMode)
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B)

	RunService:BindToRenderStep("BunkerBuildGhost", Enum.RenderPriority.Camera.Value + 1, renderStep)
	local _ = plot
end

return BuildController
