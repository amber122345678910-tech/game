--!strict
-- Экономика отряда и предметы: наличные, инвентарь каждого игрока, магазин (цены растут за покупку),
-- использование (ловушки, оружие, батарейки, дефибриллятор), выброс и подбор, апгрейды дома и фермы.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local World = require(script.Parent:WaitForChild("World"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local HouseService = require(script.Parent:WaitForChild("HouseService"))
local AppleService = require(script.Parent:WaitForChild("AppleService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ServerSounds = require(script.Parent:WaitForChild("ServerSounds"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local InmateService = require(script.Parent:WaitForChild("InmateService"))

local ItemService = {}

export type Slot = Remotes.InventorySlot

ItemService.Cash = 0
ItemService.Upgrades = {} :: { [string]: number } -- itemId → сколько раз куплено (для Upgrade и роста цен)
ItemService.Purchases = {} :: { [string]: number } -- itemId → число покупок (рост цены)
ItemService.Changed = Signal.new() :: Signal.Signal<>
ItemService.ShopOpen = true -- RoundService выставляет по фазе
ItemService.Difficulty = Config.getDifficulty(nil)

local inventories: { [Player]: { Slot? } } = {}
local worldItems: Folder? = nil
local trapsFolder: Folder? = nil

local function inventory(player: Player): { Slot? }
	local inv = inventories[player]
	if not inv then
		inv = {}
		inventories[player] = inv
	end
	return inv
end

local function replicate(player: Player)
	Remotes.Inventory:FireClient(player, inventory(player), PlayerService.battery(player))
end

function ItemService.replicate(player: Player)
	replicate(player)
end

function ItemService.price(itemId: string): number
	local def = Config.getItem(itemId)
	if not def then
		return 0
	end
	local base = def.Price
	if itemId == "AppleTree" then
		local owned = ItemService.Upgrades.AppleTree or 0
		base = Config.Economy.TreePrices[math.min(owned + 1, #Config.Economy.TreePrices)]
	end
	local step = def.PriceStep * (ItemService.Purchases[itemId] or 0)
	return math.floor((base + step) * ItemService.Difficulty.PriceMult + 0.5)
end

function ItemService.prices(): { [string]: number }
	local out = {}
	for id in Config.Items do
		out[id] = ItemService.price(id)
	end
	return out
end

function ItemService.addCash(amount: number)
	ItemService.Cash = math.max(0, ItemService.Cash + math.floor(amount))
	ItemService.Changed:Fire()
end

local function slotsOf(player: Player): { Slot? }
	return inventory(player)
end

-- Добавить предмет в инвентарь (стак по Stack). Возвращает false, если нет места.
function ItemService.give(player: Player, itemId: string, count: number, charges: number?): boolean
	local def = Config.getItem(itemId)
	if not def then
		return false
	end
	local inv = slotsOf(player)
	local left = count
	-- в существующий стак
	for i = 1, Config.InventorySlots do
		local s = inv[i]
		if s and s.ItemId == itemId and s.Count < def.Stack and left > 0 then
			local add = math.min(def.Stack - s.Count, left)
			s.Count += add
			left -= add
		end
	end
	-- в пустые слоты
	for i = 1, Config.InventorySlots do
		if left <= 0 then
			break
		end
		if not inv[i] then
			local add = math.min(def.Stack, left)
			inv[i] = { ItemId = itemId, Count = add, Charges = charges or def.Charges }
			left -= add
		end
	end
	replicate(player)
	return left <= 0
end

function ItemService.count(player: Player, itemId: string): number
	local n = 0
	for _, s in slotsOf(player) do
		if s and s.ItemId == itemId then
			n += s.Count
		end
	end
	return n
end

function ItemService.take(player: Player, itemId: string, count: number): boolean
	if ItemService.count(player, itemId) < count then
		return false
	end
	local inv = slotsOf(player)
	local left = count
	for i = Config.InventorySlots, 1, -1 do
		local s = inv[i]
		if s and s.ItemId == itemId and left > 0 then
			local sub = math.min(s.Count, left)
			s.Count -= sub
			left -= sub
			if s.Count <= 0 then
				inv[i] = nil
			end
		end
	end
	replicate(player)
	return true
end

function ItemService.clear(player: Player)
	inventories[player] = {}
	replicate(player)
end

----------------------------------------------------------------------
-- Магазин
----------------------------------------------------------------------
local function notify(player: Player, key: string, kind: string, args: { any }?)
	Remotes.Notify:FireClient(player, key, kind, args)
end

function ItemService.buy(player: Player, itemId: string): (boolean, string)
	local record = PlayerService.get(player)
	local def = Config.getItem(itemId)
	if not record or not def or record.Status ~= "Alive" then
		return false, "N_CantNow"
	end
	if not ItemService.ShopOpen then
		return false, "N_ShopClosed"
	end
	local price = ItemService.price(itemId)
	if ItemService.Cash < price then
		return false, "N_NotEnoughCash"
	end
	if def.Kind == "Upgrade" then
		local owned = ItemService.Upgrades[itemId] or 0
		if def.MaxOwned > 0 and owned >= def.MaxOwned then
			return false, "N_MaxOwned"
		end
		local applied = ItemService.applyUpgrade(itemId)
		if not applied then
			return false, "N_MaxOwned"
		end
		ItemService.Upgrades[itemId] = owned + 1
	elseif def.Kind == "Ammo" then
		-- патроны кладём в дробовик, если он есть, иначе в слот
		local shotgun: Slot? = nil
		for _, s in slotsOf(player) do
			if s and s.ItemId == "Shotgun" then
				shotgun = s
			end
		end
		if shotgun then
			if shotgun.Charges >= 5 then
				return false, "N_MaxOwned"
			end
			shotgun.Charges = math.min(5, shotgun.Charges + def.GiveCount)
			replicate(player)
		elseif not ItemService.give(player, itemId, def.GiveCount) then
			return false, "N_InventoryFull"
		end
	else
		if ItemService.count(player, itemId) + def.GiveCount > def.Stack * Config.InventorySlots then
			return false, "N_InventoryFull"
		end
		if not ItemService.give(player, itemId, def.GiveCount) then
			-- вернуть то, что успели положить
			ItemService.take(player, itemId, def.GiveCount)
			return false, "N_InventoryFull"
		end
	end
	ItemService.Cash -= price
	ItemService.Purchases[itemId] = (ItemService.Purchases[itemId] or 0) + 1
	ItemService.Changed:Fire()
	local root = PlayerService.rootPart(player)
	if root then
		ServerSounds.playOn("Coin", root, 0.5, 1, 30)
	end
	return true, "N_Bought"
end

function ItemService.applyUpgrade(itemId: string): boolean
	if itemId == "AppleTree" then
		return AppleService.plantTree()
	elseif itemId == "Sprinkler" then
		AppleService.setSprinklers((ItemService.Upgrades.Sprinkler or 0) + 1)
		return true
	elseif itemId == "Rake" then
		AppleService.setRake(true)
		return true
	elseif itemId == "MotionLight" then
		HouseService.setMotionLights(true)
		return true
	elseif itemId == "Candles" then
		HouseService.setCandles(true)
		return true
	end
	return false
end

local function sellApples(player: Player)
	local record = PlayerService.get(player)
	if not record or record.Status ~= "Alive" then
		return
	end
	if not ItemService.ShopOpen then
		notify(player, "N_ShopClosed", "warning")
		return
	end
	local shop = World.houseChild("Shop")
	local root = PlayerService.rootPart(player)
	if shop and shop:IsA("Model") and root then
		local counter = shop:FindFirstChild("Counter")
		if counter and counter:IsA("BasePart") and (counter.Position - root.Position).Magnitude > 16 then
			notify(player, "N_TooFar", "warning")
			return
		end
	end
	local n = AppleService.takeAll()
	if n <= 0 then
		notify(player, "N_NoApples", "warning")
		return
	end
	local bonus = 1 + DataService.perkValue(player, "Scavenger")
	local cash = math.floor(n * Config.Economy.AppleValue * ItemService.Difficulty.PriceMult * bonus + 0.5)
	ItemService.addCash(cash)
	notify(player, "N_Sold", "success", { n, cash })
	if root then
		ServerSounds.playOn("Coin", root, 0.7, 1, 30)
	end
end

----------------------------------------------------------------------
-- Использование предметов
----------------------------------------------------------------------
local function folderWorld(): Folder
	local f = worldItems
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "WorldItems"
	nf.Parent = workspace
	worldItems = nf
	return nf
end

local function folderTraps(): Folder
	local f = trapsFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "Traps"
	nf.Parent = workspace
	trapsFolder = nf
	return nf
end

local function template(name: string): Instance?
	local t = World.houseFolder("Templates")
	return if t then t:FindFirstChild(name) else nil
end

local function placeTrap(player: Player, itemId: string, aim: CFrame): boolean
	local def = Config.getItem(itemId)
	local root = PlayerService.rootPart(player)
	if not def or not root then
		return false
	end
	if (aim.Position - root.Position).Magnitude > 10 then
		notify(player, "N_TooFar", "warning")
		return false
	end
	-- проверяем пол под точкой
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folderTraps(), folderWorld() }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(aim.Position + Vector3.new(0, 2, 0), Vector3.new(0, -5, 0), params)
	if not hit then
		notify(player, "N_CantNow", "warning")
		return false
	end
	local tpl = template(itemId)
	local trap: Instance
	if tpl then
		trap = tpl:Clone()
	else
		local p = Instance.new("Part")
		p.Size = Vector3.new(2.5, 0.3, 2.5)
		p.Color = def.Color
		trap = p
	end
	trap.Name = itemId
	if trap:IsA("Model") then
		trap:PivotTo(CFrame.new(hit.Position + Vector3.new(0, 0.2, 0)))
	elseif trap:IsA("BasePart") then
		trap.CFrame = CFrame.new(hit.Position + Vector3.new(0, trap.Size.Y / 2, 0))
	end
	for _, d in trap:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	if trap:IsA("BasePart") then
		trap.Anchored = true
		trap.CanCollide = false
		trap.CanQuery = false
		trap.CanTouch = false
	end
	trap:SetAttribute("ItemId", itemId)
	trap:SetAttribute("Owner", player.UserId)
	trap.Parent = folderTraps()
	InmateService.registerTrap(trap, itemId)
	local pos = if trap:IsA("Model") then trap:GetPivot().Position elseif trap:IsA("BasePart") then trap.Position else hit.Position
	ServerSounds.playAt("TrapSnap", pos, 0.4, 0.9, 40)
	return true
end

-- Клиент присылает CFrame камеры; направление берём от неё, но старт — от головы персонажа на сервере.
local function useWeapon(player: Player, slot: Slot, def: Config.ItemDef, aim: CFrame): boolean
	local eye = PlayerService.eyePosition(player)
	local root = PlayerService.rootPart(player)
	if not eye or not root then
		return false
	end
	if slot.Charges <= 0 then
		notify(player, "N_NoCharges", "warning")
		return false
	end
	local dir = aim.LookVector
	-- защита от подделки направления: не дальше 100° от взгляда персонажа
	local rootLook = root.CFrame.LookVector
	if rootLook:Dot(dir) < -0.2 then
		dir = rootLook
	end
	slot.Charges -= 1
	local itemId = def.Id
	if itemId == "Shotgun" then
		ServerSounds.playOn("Shotgun", root, 1, 1, 200)
		NoiseService.emit(root.Position, "Shot", player)
		InmateService.hitRay(eye, dir, def.Range, def.Damage, def.Stun, 18, player)
	elseif itemId == "StunGun" then
		ServerSounds.playOn("StunZap", root, 0.8, 1, 60)
		NoiseService.emit(root.Position, "Switch", player, 12)
		InmateService.hitRay(eye, dir, def.Range, 0, def.Stun, 0, player)
	elseif itemId == "PepperSpray" then
		ServerSounds.playOn("Spray", root, 0.8, 1, 40)
		InmateService.hitCone(eye, dir, def.Range, 0.6, 0, def.Stun, true, player)
	end
	if slot.Charges <= 0 and def.Id ~= "Shotgun" then
		-- одноразовое/разряженное исчезает (шокер тоже)
		ItemService.take(player, itemId, 1)
	else
		replicate(player)
	end
	return true
end

local function useItem(player: Player, slotIndex: number, aim: CFrame?)
	local record = PlayerService.get(player)
	if not record or record.Status ~= "Alive" then
		return
	end
	local inv = slotsOf(player)
	local slot = inv[slotIndex]
	if not slot then
		return
	end
	local def = Config.getItem(slot.ItemId)
	if not def then
		inv[slotIndex] = nil
		replicate(player)
		return
	end
	if def.Kind == "Placeable" then
		if def.Id == "Planks" then
			return -- доски ставятся через промпт окна
		end
		if aim and placeTrap(player, def.Id, aim) then
			ItemService.take(player, def.Id, 1)
		end
	elseif def.Kind == "Weapon" then
		if aim then
			useWeapon(player, slot, def, aim)
		end
	elseif def.Kind == "Consumable" then
		if def.Id == "Batteries" then
			if PlayerService.battery(player) >= Config.Flashlight.Battery - 1 then
				notify(player, "N_CantNow", "warning")
				return
			end
			PlayerService.setBattery(player, Config.Flashlight.Battery)
			ItemService.take(player, def.Id, 1)
			local root = PlayerService.rootPart(player)
			if root then
				ServerSounds.playOn("Pickup", root, 0.5, 1.2, 20)
			end
		elseif def.Id == "Defibrillator" then
			local root = PlayerService.rootPart(player)
			if not root then
				return
			end
			local target: Player? = nil
			local bestDist = Config.Downed.DefibrillatorRange
			for _, other in Players:GetPlayers() do
				local rec = PlayerService.get(other)
				local oroot = PlayerService.rootPart(other)
				if rec and rec.Status == "Downed" and oroot then
					local d = (oroot.Position - root.Position).Magnitude
					if d < bestDist then
						target = other
						bestDist = d
					end
				end
			end
			if not target then
				notify(player, "N_TooFar", "warning")
				return
			end
			ItemService.take(player, def.Id, 1)
			ServerSounds.playOn("StunZap", root, 0.9, 1.3, 50)
			PlayerService.revive(target, player)
		end
	elseif def.Kind == "Ammo" then
		-- вручную зарядить дробовик
		for _, s in inv do
			if s and s.ItemId == "Shotgun" and s.Charges < 5 then
				s.Charges = math.min(5, s.Charges + slot.Count)
				ItemService.take(player, "Shells", slot.Count)
				return
			end
		end
	end
end

----------------------------------------------------------------------
-- Выброс и подбор
----------------------------------------------------------------------
local function dropItem(player: Player, slotIndex: number)
	local record = PlayerService.get(player)
	local root = PlayerService.rootPart(player)
	if not record or record.Status ~= "Alive" or not root then
		return
	end
	local inv = slotsOf(player)
	local slot = inv[slotIndex]
	if not slot then
		return
	end
	local def = Config.getItem(slot.ItemId)
	inv[slotIndex] = nil
	replicate(player)
	local p = Instance.new("Part")
	p.Name = "Drop_" .. slot.ItemId
	p.Size = Vector3.new(1.4, 0.6, 1.4)
	p.Color = if def then def.Color else Color3.fromRGB(200, 200, 200)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	-- на пол перед игроком
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, folderWorld(), folderTraps() }
	local origin = root.Position + root.CFrame.LookVector * 2.5
	local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), params)
	p.CFrame = CFrame.new(if hit then hit.Position + Vector3.new(0, 0.4, 0) else origin)
	p:SetAttribute("ItemId", slot.ItemId)
	p:SetAttribute("Count", slot.Count)
	p:SetAttribute("Charges", slot.Charges)
	p:SetAttribute("WorldItem", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Take"
	prompt.ObjectText = slot.ItemId
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	p.Parent = folderWorld()
	NoiseService.emit(p.Position, "Switch", player, 8)
end

local function pickup(part: BasePart, player: Player)
	local record = PlayerService.get(player)
	if not record or record.Status ~= "Alive" then
		return
	end
	local itemId = part:GetAttribute("ItemId") :: string?
	local count = (part:GetAttribute("Count") :: number?) or 1
	local charges = (part:GetAttribute("Charges") :: number?) or 0
	if not itemId or not Config.getItem(itemId) then
		part:Destroy()
		return
	end
	local root = PlayerService.rootPart(player)
	if not root or (root.Position - part.Position).Magnitude > 12 then
		return
	end
	if not ItemService.give(player, itemId, count, charges) then
		notify(player, "N_InventoryFull", "warning")
		-- give мог положить часть; упрощённо — не трогаем
		return
	end
	part:Destroy()
	ServerSounds.playOn("Pickup", root, 0.5, 1, 20)
end

-- Собиратель крадёт ловушку/предмет с пола
function ItemService.stealNear(position: Vector3, radius: number): boolean
	for _, p in folderTraps():GetChildren() do
		local pos = if p:IsA("Model") then p:GetPivot().Position elseif p:IsA("BasePart") then p.Position else nil
		if pos and (pos - position).Magnitude <= radius then
			InmateService.unregisterTrap(p)
			p:Destroy()
			return true
		end
	end
	for _, p in folderWorld():GetChildren() do
		if p:IsA("BasePart") and (p.Position - position).Magnitude <= radius then
			p:Destroy()
			return true
		end
	end
	return false
end

function ItemService.nearestLoot(position: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDist = math.huge
	for _, p in folderTraps():GetChildren() do
		local pos = if p:IsA("Model") then p:GetPivot().Position elseif p:IsA("BasePart") then p.Position else nil
		if pos then
			local d = (pos - position).Magnitude
			if d < bestDist then
				best = pos
				bestDist = d
			end
		end
	end
	local apple = AppleService.nearestApple(position)
	if apple then
		local d = (apple.Position - position).Magnitude
		if d < bestDist then
			best = apple.Position
		end
	end
	return best
end

----------------------------------------------------------------------
-- Матч
----------------------------------------------------------------------
function ItemService.resetMatch(difficulty: Config.DifficultyDef)
	ItemService.Difficulty = difficulty
	ItemService.Cash = if RunService:IsStudio() then Config.Economy.StudioStartingCash else Config.Economy.StartingCash
	ItemService.Upgrades = {}
	ItemService.Purchases = {}
	for _, p in Players:GetPlayers() do
		inventories[p] = {}
	end
	folderTraps():ClearAllChildren()
	folderWorld():ClearAllChildren()
	-- стартовые перки
	local lucky = 0
	for _, p in Players:GetPlayers() do
		lucky = math.max(lucky, DataService.perkValue(p, "LuckyStart"))
		local traps = DataService.perkValue(p, "Trapper")
		if traps > 0 then
			ItemService.give(p, "BearTrap", traps)
		end
		replicate(p)
	end
	ItemService.Cash += lucky
	ItemService.Changed:Fire()
end

function ItemService.init()
	Remotes.BuyItem.OnServerInvoke = function(player: Player, itemId: any): (boolean, string)
		if typeof(itemId) ~= "string" then
			return false, "N_CantNow"
		end
		local ok, msg = ItemService.buy(player, itemId)
		if ok then
			Remotes.Notify:FireClient(player, msg, "success", { itemId })
		end
		return ok, msg
	end
	Remotes.SellApples.OnServerEvent:Connect(sellApples)
	Remotes.UseItem.OnServerEvent:Connect(function(player, slotIndex, aim)
		if typeof(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > Config.InventorySlots then
			return
		end
		if aim ~= nil and typeof(aim) ~= "CFrame" then
			return
		end
		useItem(player, math.floor(slotIndex), aim)
	end)
	Remotes.DropItem.OnServerEvent:Connect(function(player, slotIndex)
		if typeof(slotIndex) == "number" and slotIndex >= 1 and slotIndex <= Config.InventorySlots then
			dropItem(player, math.floor(slotIndex))
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local part = prompt.Parent
		if prompt.Name == "PickupPrompt" and part and part:IsA("BasePart") and part:GetAttribute("WorldItem") then
			pickup(part, player)
		end
	end)
	HouseService.WindowBoardRequested:Connect(function(player, windowId)
		if ItemService.count(player, "Planks") <= 0 then
			notify(player, "N_NeedPlanks", "warning")
			return
		end
		if HouseService.addBoard(windowId, player) then
			ItemService.take(player, "Planks", 1)
		end
	end)
	HouseService.ShopRequested:Connect(function(player)
		if not ItemService.ShopOpen then
			notify(player, "N_ShopClosed", "warning")
			return
		end
		Remotes.FX:FireClient(player, "OpenShop", nil)
	end)
	PlayerService.BatteryChanged:Connect(function(player)
		replicate(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		inventories[player] = {}
	end)
end

return ItemService
