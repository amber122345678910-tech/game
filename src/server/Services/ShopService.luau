--!strict
-- Магазин: покупка блоков и готовых бункеров (RemoteFunction Purchase).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Prefabs = require(Shared:WaitForChild("Prefabs"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local BuildService = require(script.Parent.BuildService)

local ShopService = {}

local lastPurchase: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}

local function buyBlock(player: Player, id: any, amount: any): (boolean, string)
	local def = Config.getBlock(id)
	if not def then
		return false, "Неизвестный товар"
	end
	if typeof(amount) ~= "number" or amount ~= amount or amount ~= math.floor(amount) then
		return false, "Неверное количество"
	end
	if amount < 1 or amount > Config.Economy.MaxBuyAmount then
		return false, "Неверное количество"
	end
	local cost = def.Price * amount
	if not DataService.trySpend(player, cost) then
		return false, "Не хватает монет!"
	end
	DataService.addBlocks(player, def.Id, amount)
	return true, "Куплено: " .. def.Name .. " ×" .. tostring(amount)
end

local function buyPrefab(player: Player, id: any): (boolean, string)
	local def = Prefabs.get(id)
	if not def then
		return false, "Неизвестный бункер"
	end
	local data = DataService.get(player)
	local plot = PlotService.getPlot(player)
	if not data or not plot then
		return false, "Данные ещё загружаются"
	end
	if plot.Session ~= nil then
		return false, "Во время шторма покупать бункеры нельзя"
	end
	if def.Free and data.StarterClaimed then
		return false, "Стартовая хижина уже получена"
	end
	local price = Prefabs.price(def.Id)
	if not DataService.trySpend(player, price) then
		return false, "Не хватает монет!"
	end
	if def.Free then
		data.StarterClaimed = true
	end
	-- Добавляем блоки бункера в инвентарь и сразу строим из них.
	for blockId, count in Prefabs.blockCounts(def.Id) do
		DataService.addBlocks(player, blockId, count)
	end
	BuildService.replaceWithLayout(player, Prefabs.layout(def.Id))
	DataService.replicate(player)
	-- если игрок оказался внутри стены нового бункера — переносим его к входу
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and root and root:IsA("BasePart") then
		local lp = PlotService.toLocal(plot, root.Position)
		local cx, cy, cz = Grid.localToCell(lp.X, lp.Y - 1.5, lp.Z)
		local stuck = false
		for dy = 0, 1 do
			if Grid.inBounds(cx, cy + dy, cz) and plot.Cells[Grid.index(cx, cy + dy, cz)] then
				stuck = true
			end
		end
		if stuck then
			character:PivotTo(plot.Origin * CFrame.new(0, 4, -29))
		end
	end
	return true, "Бункер «" .. def.Name .. "» построен на твоём участке!"
end

local function onPurchase(player: Player, kind: any, id: any, amount: any): (boolean, string)
	local now = os.clock()
	if busy[player] or now - (lastPurchase[player] or 0) < 0.15 then
		return false, "Слишком быстро"
	end
	if not DataService.get(player) then
		return false, "Данные ещё загружаются"
	end
	lastPurchase[player] = now
	busy[player] = true
	local ok, okResult, message = pcall(function(): (boolean, string)
		if kind == "block" then
			return buyBlock(player, id, amount)
		elseif kind == "prefab" then
			return buyPrefab(player, id)
		end
		return false, "Неизвестный тип покупки"
	end)
	busy[player] = nil
	if not ok then
		warn("[ShopService] Purchase error: " .. tostring(okResult))
		return false, "Ошибка покупки"
	end
	return okResult, message
end

function ShopService.init()
	Remotes.Purchase.OnServerInvoke = onPurchase
	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
		busy[player] = nil
	end)
end

return ShopService
