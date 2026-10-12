--!strict
-- Взаимодействие с предметами и миром: выбор слота (1–4, колесо мыши, бамперы геймпада), применение
-- предмета (ЛКМ / R2 / кнопка «Use»: оружие — CFrame камеры, ловушки — точка пола по лучу с призраком-превью,
-- расходники — без цели), выброс (Backspace / X / кнопка), выход из укрытия (короткое нажатие E / A),
-- проверка «смотрю на Still One» (LookingAt) и раскладка сенсорных кнопок (показываются только в матче).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Locale = require(Shared:WaitForChild("Locale"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Interaction = {}

local ACTION_USE = "Use"
local ACTION_DROP = "Drop"
local ACTION_LEAVE_TAP = "LeaveHidingTap" -- короткое нажатие E / A в укрытии
local ACTION_LEAVE_BUTTON = "LeaveHiding" -- сенсорная кнопка в укрытии

local PLACE_RANGE = 8
local LOOK_INTERVAL = 0.15
local LOOK_RANGE = 80
local LOOK_COS = math.cos(math.rad(50))
local TAP_SECONDS = 0.25
local GHOST_VALID = Color3.fromRGB(90, 220, 130)
local GHOST_INVALID = Color3.fromRGB(220, 80, 80)

-- Раскладка сенсорных кнопок (доли ContextButtonFrame — справа внизу, стик слева не задевают)
local TOUCH_LAYOUT: { [string]: UDim2 } = {
	Use = UDim2.new(0.05, 0, 0.3, 0),
	Flashlight = UDim2.new(0.5, 0, 0.3, 0),
	Sprint = UDim2.new(0.05, 0, 0.62, 0),
	Crouch = UDim2.new(0.5, 0, 0.62, 0),
	Drop = UDim2.new(0.5, 0, 0.0, 0),
}

local player = Players.LocalPlayer
local ghost: PVInstance? = nil
local ghostItemId = ""
local ghostValid = false
local lookTimer = 0
local looking: { [string]: boolean } = {}
local leavePressedAt = 0
local leaveBound = false
local touchVisible: boolean? = nil

local function status(): string
	return ClientState.Status
end

local function selectedDef(): (Config.ItemDef?, number, ClientState.InventorySlot?)
	local slot = ClientState.SelectedSlot
	local item = ClientState.Inventory[slot]
	if not item then
		return nil, slot, nil
	end
	return Config.getItem(item.ItemId), slot, item
end

----------------------------------------------------------------------
-- Лучи
----------------------------------------------------------------------

local function raycastParams(extra: { Instance }?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local list: { Instance } = {}
	local char = player.Character
	if char then
		table.insert(list, char)
	end
	local fx = workspace:FindFirstChild("ClientFX")
	if fx then
		table.insert(list, fx)
	end
	local g = ghost
	if g then
		table.insert(list, g)
	end
	if extra then
		for _, inst in extra do
			table.insert(list, inst)
		end
	end
	params.FilterDescendantsInstances = list
	return params
end

local function floorFrame(point: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(point, point + flat.Unit)
end

-- Точка пола по лучу из камеры (до PLACE_RANGE стадов). nil — пола нет.
local function floorHit(): CFrame?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local origin = cam.CFrame.Position
	local look = cam.CFrame.LookVector
	local inmates = workspace:FindFirstChild("Inmates")
	local params = raycastParams(if inmates then { inmates } else nil)
	local hit = workspace:Raycast(origin, look * PLACE_RANGE, params)
	if hit then
		if hit.Normal.Y > 0.7 then
			return floorFrame(hit.Position, look)
		end
		-- упёрлись в стену/мебель: пробуем пол чуть ближе к себе
		local back = hit.Position - look * 1.5
		local down = workspace:Raycast(back, Vector3.new(0, -7, 0), params)
		if down and down.Normal.Y > 0.7 then
			return floorFrame(down.Position, look)
		end
		return nil
	end
	local ahead = origin + look * PLACE_RANGE
	local down = workspace:Raycast(ahead, Vector3.new(0, -9, 0), params)
	if down and down.Normal.Y > 0.7 then
		return floorFrame(down.Position, look)
	end
	return nil
end

----------------------------------------------------------------------
-- Призрак-превью ловушки
----------------------------------------------------------------------

local function destroyGhost()
	local g = ghost
	ghost = nil
	ghostItemId = ""
	if g then
		g:Destroy()
	end
end

local function tintGhost(valid: boolean)
	local g = ghost
	if not g or ghostValid == valid then
		return
	end
	ghostValid = valid
	local color = if valid then GHOST_VALID else GHOST_INVALID
	for _, d in g:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = color
		end
	end
	if g:IsA("BasePart") then
		g.Color = color
	end
end

local function makeGhost(itemId: string): PVInstance?
	local house = workspace:FindFirstChild("House")
	local templates = if house then house:FindFirstChild("Templates") else nil
	local source = if templates then templates:FindFirstChild(itemId) else nil
	if not source or not source:IsA("PVInstance") then
		return nil
	end
	local clone = source:Clone()
	clone.Name = "Ghost_" .. itemId
	local function prepare(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 0.55
	end
	if clone:IsA("BasePart") then
		prepare(clone)
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			prepare(d)
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	clone.Parent = Sounds.fxFolder()
	return clone
end

local function wantsGhost(): string?
	if status() ~= "Alive" then
		return nil
	end
	local def = selectedDef()
	if def and def.Kind == "Placeable" and (def.Id == "BearTrap" or def.Id == "GlueTrap") then
		return def.Id
	end
	return nil
end

local function updateGhost()
	local itemId = wantsGhost()
	if not itemId then
		if ghost then
			destroyGhost()
		end
		return
	end
	if not ghost or ghostItemId ~= itemId then
		destroyGhost()
		ghost = makeGhost(itemId)
		ghostItemId = itemId
		ghostValid = true
		tintGhost(false)
	end
	local g = ghost
	if not g then
		return
	end
	local cf = floorHit()
	if cf then
		g:PivotTo(cf)
		tintGhost(true)
	else
		local cam = workspace.CurrentCamera
		if cam then
			g:PivotTo(floorFrame(cam.CFrame.Position + cam.CFrame.LookVector * 4 - Vector3.new(0, 2, 0), cam.CFrame.LookVector))
		end
		tintGhost(false)
	end
end

----------------------------------------------------------------------
-- Применение и выброс
----------------------------------------------------------------------

local function useSelected()
	if status() ~= "Alive" then
		return
	end
	local def, slot, item = selectedDef()
	if not def or not item then
		return
	end
	local cam = workspace.CurrentCamera
	if def.Kind == "Weapon" then
		if cam then
			Remotes.UseItem:FireServer(slot, cam.CFrame)
		end
	elseif def.Kind == "Placeable" then
		if def.Id == "Planks" then
			return -- доски ставятся через промпт окна
		end
		local cf = floorHit()
		if cf then
			Remotes.UseItem:FireServer(slot, cf)
		else
			Sounds.playUI("Fail", 0.5)
		end
	else
		-- Batteries, Defibrillator, Shells
		Remotes.UseItem:FireServer(slot, nil)
	end
end

local function dropSelected()
	if status() ~= "Alive" then
		return
	end
	local _, slot, item = selectedDef()
	if item then
		Remotes.DropItem:FireServer(slot)
	end
end

-- R2 и сенсорная кнопка; ЛКМ обрабатывается в onInputBegan, где известен gameProcessed
local function onUse(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		useSelected()
	end
	return Enum.ContextActionResult.Sink
end

local function onDrop(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		dropSelected()
	end
	return Enum.ContextActionResult.Pass
end

----------------------------------------------------------------------
-- Выход из укрытия
----------------------------------------------------------------------

local function requestUnhide()
	if status() == "Hiding" then
		Remotes.Interact:FireServer("Unhide", "")
	end
end

local function onLeaveTap(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		leavePressedAt = os.clock()
	elseif state == Enum.UserInputState.End then
		if leavePressedAt > 0 and os.clock() - leavePressedAt < TAP_SECONDS then
			requestUnhide()
		end
		leavePressedAt = 0
	elseif state == Enum.UserInputState.Cancel then
		leavePressedAt = 0
	end
	-- удержание той же клавиши — задержка дыхания (модуль Hiding), поэтому пропускаем дальше
	return Enum.ContextActionResult.Pass
end

local function onLeaveButton(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		requestUnhide()
	end
	return Enum.ContextActionResult.Sink
end

local function setLeaveBound(on: boolean)
	if leaveBound == on then
		return
	end
	leaveBound = on
	if on then
		ContextActionService:BindAction(ACTION_LEAVE_TAP, onLeaveTap, false, Enum.KeyCode.E, Enum.KeyCode.ButtonA)
		ContextActionService:BindAction(ACTION_LEAVE_BUTTON, onLeaveButton, true)
		ContextActionService:SetTitle(ACTION_LEAVE_BUTTON, Locale.t("Close"))
		ContextActionService:SetPosition(ACTION_LEAVE_BUTTON, UDim2.new(0.5, 0, 0.62, 0))
	else
		ContextActionService:UnbindAction(ACTION_LEAVE_TAP)
		ContextActionService:UnbindAction(ACTION_LEAVE_BUTTON)
		leavePressedAt = 0
	end
end

----------------------------------------------------------------------
-- Выбор слота
----------------------------------------------------------------------

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local function cycleSlot(delta: number)
	local n = Config.InventorySlots
	local next = ((ClientState.SelectedSlot - 1 + delta) % n + n) % n + 1
	ClientState.selectSlot(next)
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		useSelected()
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			ClientState.selectSlot(slot)
		end
	elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
		if input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycleSlot(1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycleSlot(-1)
		end
	end
end

local function onInputChanged(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	if status() ~= "Alive" then
		return
	end
	if input.Position.Z > 0 then
		cycleSlot(-1)
	elseif input.Position.Z < 0 then
		cycleSlot(1)
	end
end

----------------------------------------------------------------------
-- «Смотрю на Still One»
----------------------------------------------------------------------

local function sendLooking(id: string, value: boolean)
	if looking[id] ~= value then
		looking[id] = value
		Remotes.LookingAt:FireServer(id, value)
	end
end

local function isOccluded(from: Vector3, to: Vector3, model: Model): boolean
	local params = raycastParams({ model })
	local origin = from
	-- прозрачные части (стекло) считаем просматриваемыми: до 3 перебросов
	for _ = 1, 3 do
		local hit = workspace:Raycast(origin, to - origin, params)
		if not hit then
			return false
		end
		local part = hit.Instance
		if part.Transparency >= 0.5 then
			params:AddToFilter(part)
			origin = hit.Position
		else
			return true
		end
	end
	return true
end

local function updateLooking()
	local s = status()
	local cam = workspace.CurrentCamera
	local inmates = workspace:FindFirstChild("Inmates")
	local active = (s == "Alive" or s == "Hiding") and cam ~= nil and inmates ~= nil
	local seen: { [string]: boolean } = {}
	if active and cam and inmates then
		local camPos = cam.CFrame.Position
		local look = cam.CFrame.LookVector
		for _, model in inmates:GetChildren() do
			if not model:IsA("Model") or model:GetAttribute("Kind") ~= "StillOne" then
				continue
			end
			local idAttr = model:GetAttribute("InmateId")
			local id = if typeof(idAttr) == "string" then idAttr else model.Name
			seen[id] = true
			local head = model:FindFirstChild("Head")
			local target = if head and head:IsA("BasePart") then head else model:FindFirstChild("HumanoidRootPart")
			if not target or not target:IsA("BasePart") then
				sendLooking(id, false)
				continue
			end
			local dir = target.Position - camPos
			local dist = dir.Magnitude
			local inView = dist > 0.01 and dist <= LOOK_RANGE and look:Dot(dir / dist) > LOOK_COS
			local isLooking = inView and not isOccluded(camPos, target.Position, model)
			sendLooking(id, isLooking)
		end
	end
	for id, value in looking do
		if value and not seen[id] then
			sendLooking(id, false)
		end
	end
	for id in looking do
		if not seen[id] then
			looking[id] = nil
		end
	end
end

----------------------------------------------------------------------
-- Сенсорные кнопки
----------------------------------------------------------------------

local function setButtonVisible(name: string, visible: boolean)
	local ok, button = pcall(function()
		return ContextActionService:GetButton(name)
	end)
	if ok and button then
		button.Visible = visible
	end
end

local function refreshTouchButtons()
	if not UserInputService.TouchEnabled then
		return
	end
	local inMatch = ClientState.inMatch() and status() == "Alive"
	if touchVisible == inMatch then
		return
	end
	touchVisible = inMatch
	task.spawn(function()
		for name in TOUCH_LAYOUT do
			setButtonVisible(name, inMatch)
		end
	end)
end

local function layoutTouchButtons()
	for name, position in TOUCH_LAYOUT do
		pcall(function()
			ContextActionService:SetPosition(name, position)
		end)
	end
end

----------------------------------------------------------------------

function Interaction.init()
	ContextActionService:BindAction(ACTION_USE, onUse, true, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle(ACTION_USE, Locale.t("Interact"))
	ContextActionService:BindAction(ACTION_DROP, onDrop, true, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ACTION_DROP, Locale.t("Drop"))
	layoutTouchButtons()

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)

	ClientState.SelectedChanged:Connect(function()
		updateGhost()
	end)
	ClientState.InventoryChanged:Connect(function()
		updateGhost()
	end)
	ClientState.StatusChanged:Connect(function(newStatus: string)
		setLeaveBound(newStatus == "Hiding")
		updateGhost()
		refreshTouchButtons()
	end)
	ClientState.StateChanged:Connect(function()
		refreshTouchButtons()
	end)
	player.CharacterAdded:Connect(function()
		for id in looking do
			looking[id] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		if ghost then
			updateGhost()
		end
		lookTimer += dt
		if lookTimer >= LOOK_INTERVAL then
			lookTimer = 0
			updateLooking()
		end
	end)

	refreshTouchButtons()
end

return Interaction
