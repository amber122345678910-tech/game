--!strict
-- Строительство: обработка запросов клиента (поставить / убрать / очистить) с проверками.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local BuildService = {}

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: Bucket } = {}

-- Ограничение частоты действий (token bucket): защита от спама запросами.
local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = Config.Build.BurstActions, last = now }
		buckets[player] = b
	end
	b.tokens = math.min(Config.Build.BurstActions, b.tokens + (now - b.last) * Config.Build.MaxActionsPerSecond)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function isInt(v: any): boolean
	return typeof(v) == "number" and v == v and v == math.floor(v) and math.abs(v) < 1000
end

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, text, kind)
end

-- Сохраняем раскладку в профиль сразу (дёшево), чтобы при выходе ничего не потерялось.
function BuildService.saveLayout(player: Player)
	local plot = PlotService.getPlot(player)
	if plot and plot.Session == nil then
		DataService.setLayout(player, PlotService.serialize(plot))
	end
end

local function getBuildablePlot(player: Player): PlotService.Plot?
	local plot = PlotService.getPlot(player)
	if not plot or not DataService.get(player) then
		return nil
	end
	if plot.Session ~= nil then
		notify(player, "Во время шторма строить нельзя!", "error")
		return nil
	end
	return plot
end

local function onPlace(player: Player, blockId: any, x: any, y: any, z: any, rot: any)
	if not allow(player) then
		return
	end
	if typeof(blockId) ~= "string" or #blockId > 32 or not isInt(x) or not isInt(y) or not isInt(z) then
		return
	end
	local def = Config.getBlock(blockId)
	if not def then
		return
	end
	local plot = getBuildablePlot(player)
	if not plot then
		return
	end
	if DataService.getBlockCount(player, def.Id) < 1 then
		notify(player, "Нет блоков «" .. def.Name .. "». Купи их в магазине!", "error")
		return
	end
	local ok, reason = PlotService.canPlace(plot, def, x, y, z)
	if not ok then
		notify(player, reason or "Здесь нельзя строить", "error")
		return
	end
	-- Защита от строительства "издалека" (игрок должен быть рядом с участком)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local cellPos = PlotService.cellWorldPosition(plot, x, y, z)
		if (cellPos - root.Position).Magnitude > Config.Build.MaxPlaceDistance then
			notify(player, "Подойди ближе к своему участку", "error")
			return
		end
	else
		return
	end
	if BuildService.isOccupiedByCharacter(plot, x, y, z, def.HeightCells) then
		notify(player, "Здесь стоит игрок", "error")
		return
	end
	if not DataService.takeBlocks(player, def.Id, 1) then
		return
	end
	local finalRot = Grid.normalizeRot(rot)
	if def.IsDoor then
		-- дверь сама разворачивается вдоль стены
		finalRot = Grid.autoDoorRot(plot.Cells, x, y, z, finalRot)
	end
	local rec = PlotService.place(plot, def.Id, x, y, z, finalRot)
	if not rec then
		DataService.addBlocks(player, def.Id, 1) -- вернуть блок
		return
	end
	BuildService.saveLayout(player)
end

-- Не даём замуровать персонажа внутри блока.
function BuildService.isOccupiedByCharacter(plot: PlotService.Plot, x: number, y: number, z: number, heightCells: number): boolean
	local lx, _, lz = Grid.cellCenterLocal(x, y, z)
	local bottom = y * Grid.CELL
	local top = (y + heightCells) * Grid.CELL
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = PlotService.toLocal(plot, root.Position)
			if math.abs(p.X - lx) < 2.9 and math.abs(p.Z - lz) < 2.9 and p.Y - 3 < top and p.Y + 2 > bottom then
				return true
			end
		end
	end
	return false
end

local function onRemove(player: Player, x: any, y: any, z: any)
	if not allow(player) then
		return
	end
	if not isInt(x) or not isInt(y) or not isInt(z) then
		return
	end
	local plot = getBuildablePlot(player)
	if not plot then
		return
	end
	local rec = PlotService.remove(plot, x, y, z)
	if rec then
		DataService.addBlocks(player, rec.id, 1)
		BuildService.saveLayout(player)
	end
end

local function onClear(player: Player)
	if not allow(player) then
		return
	end
	local plot = getBuildablePlot(player)
	if not plot then
		return
	end
	local counts = PlotService.clear(plot)
	local total = 0
	for id, n in counts do
		DataService.addBlocks(player, id, n)
		total += n
	end
	BuildService.saveLayout(player)
	if total > 0 then
		notify(player, string.format("Постройка разобрана: %d блоков вернулось в инвентарь", total), "info")
	end
end

-- Заменить постройку раскладкой (готовый бункер). Блоки берутся из инвентаря.
-- Текущая постройка возвращается в инвентарь. Возвращает число поставленных блоков.
function BuildService.replaceWithLayout(player: Player, entries: { Grid.Entry }): number
	local plot = PlotService.getPlot(player)
	if not plot or plot.Session ~= nil then
		return 0
	end
	local counts = PlotService.clear(plot)
	for id, n in counts do
		DataService.addBlocks(player, id, n)
	end
	local placed = 0
	for _, e in entries do
		local def = Config.getBlock(e.id)
		-- раскладка готового бункера доверенная: опору не проверяем (порядок блоков не важен)
		if def and PlotService.canPlace(plot, def, e.x, e.y, e.z, true) and DataService.takeBlocks(player, def.Id, 1) then
			if PlotService.place(plot, def.Id, e.x, e.y, e.z, e.rot, true) then
				placed += 1
			else
				DataService.addBlocks(player, def.Id, 1)
			end
		end
	end
	BuildService.saveLayout(player)
	return placed
end

function BuildService.init()
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlace)
	Remotes.RemoveBlock.OnServerEvent:Connect(onRemove)
	Remotes.ClearPlot.OnServerEvent:Connect(onClear)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return BuildService
