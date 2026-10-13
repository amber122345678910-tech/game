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
-- Кто поставил блок: гость получает обратно свои блоки, а блоки хозяина возвращаются хозяину.
-- Ключ — клетка и тип блока, а не запись: после шторма restoreLayout создаёт новые записи.
type PlacedEntry = { userId: number, id: string }
type PlotPlaced = { owner: Player?, cells: { [number]: PlacedEntry } }
local placedBy: { [PlotService.Plot]: PlotPlaced } = {}

local function placedCells(plot: PlotService.Plot): { [number]: PlacedEntry }
	local t = placedBy[plot]
	-- у участка новый хозяин (или тот же после перезахода) — старые отметки недействительны
	if not t or t.owner ~= plot.Owner then
		t = { owner = plot.Owner, cells = {} }
		placedBy[plot] = t
	end
	return t.cells
end
local refundNoted: { [Player]: number } = {}
local ladderHinted: { [Player]: boolean } = {}

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

-- Записать раскладку в профиль сейчас.
local layoutDirty: { [Player]: boolean } = {}
function BuildService.saveLayout(player: Player)
	layoutDirty[player] = nil
	local plot = PlotService.getPlot(player)
	if not plot then
		return
	end
	local session = plot.Session
	if session ~= nil then
		-- во время шторма блоки ломаются: сохраняем раскладку до шторма
		DataService.setLayout(player, Grid.serialize(session.Snapshot, PlotService.getDug(plot)))
	else
		DataService.setLayout(player, PlotService.serialize(plot))
	end
end

-- Отложенная запись раскладки: серия правок -> одна сериализация. Перед любым сохранением
-- DataService вызывает хук ниже, так что последние правки не теряются.
local function markLayoutDirty(player: Player)
	if layoutDirty[player] then
		return
	end
	layoutDirty[player] = true
	task.delay(Config.Build.SaveDebounce, function()
		if layoutDirty[player] and player.Parent == Players then
			BuildService.saveLayout(player)
		end
	end)
end

-- Участок, где игрок строит: свой или друга (если он гость в чужом бункере).
local function getBuildablePlot(player: Player): PlotService.Plot?
	local plot = PlotService.getActivePlot(player)
	if not plot or not DataService.get(player) then
		return nil
	end
	if plot.Session ~= nil then
		notify(player, "Во время шторма строить нельзя!", "error")
		return nil
	end
	return plot
end

-- Ограничитель частоты проверяется в обработчике события (см. init).
local function onPlace(player: Player, blockId: any, x: any, y: any, z: any, rot: any)
	if typeof(blockId) ~= "string" or #blockId > 32 or not isInt(x) or not isInt(y) or not isInt(z) then
		return
	end
	local def = Config.getBuildableBlock(blockId)
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
	placedCells(plot)[Grid.index(rec.x, rec.y, rec.z)] = { userId = player.UserId, id = rec.id }
	-- сохраняется раскладка хозяина участка (гость строит в чужом бункере)
	markLayoutDirty(plot.Owner or player)
end

-- Не даём замуровать персонажа внутри блока.
function BuildService.isOccupiedByCharacter(plot: PlotService.Plot, x: number, y: number, z: number, heightCells: number): boolean
	local lx, _, lz = Grid.cellCenterLocal(x, y, z)
	local bottom = Grid.layerBottom(y)
	local top = Grid.layerBottom(y + heightCells)
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
		-- выкопанная земля в инвентарь не попадает
		-- блок из чужого бункера возвращается хозяину участка (гость не может «растащить» бункер),
		-- а свой блок гость получает обратно
		local cells = placedCells(plot)
		local key = Grid.index(rec.x, rec.y, rec.z)
		local entry = cells[key]
		cells[key] = nil
		local ownBlock = entry ~= nil and entry.id == rec.id and entry.userId == player.UserId
		if not rec.def.Indestructible then
			local owner = plot.Owner
			local refundTo = if owner and owner ~= player and not ownBlock then owner else player
			DataService.addBlocks(refundTo, rec.id, 1)
			if refundTo ~= player and os.clock() - (refundNoted[player] or 0) > 15 then
				refundNoted[player] = os.clock()
				notify(player, "Блоки хозяина бункера возвращаются к нему в инвентарь", "info")
			end
		end
		markLayoutDirty(plot.Owner or player)
		-- копнул глубже 2 слоёв: подсказываем про лестницу (из такой ямы не выпрыгнуть)
		if rec.def.Indestructible and rec.y <= Grid.SURFACE - 2 and not ladderHinted[player] then
			ladderHinted[player] = true
			notify(player, "Глубоко копаешь! Из ямы глубже 2 блоков не выпрыгнуть — поставь 🪜 лестницу (подходи к ней сбоку).", "info")
		end
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
	if plot.Owner ~= player then
		notify(player, "Разобрать весь бункер может только его хозяин", "error")
		return
	end
	local counts = PlotService.clear(plot)
	placedBy[plot] = nil
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
	placedBy[plot] = nil
	for id, n in counts do
		DataService.addBlocks(player, id, n)
	end
	local placed = 0
	for _, e in entries do
		local def = Config.getBuildableBlock(e.id)
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
	Remotes.PlaceBlock.OnServerEvent:Connect(function(player: Player, blockId: any, x: any, y: any, z: any, rot: any, seq: any)
		local passed = allow(player)
		if passed then
			onPlace(player, blockId, x, y, z, rot)
		end
		-- отвечаем на каждый запрос (и на отказ тоже), иначе клиент считал бы блок потраченным;
		-- отклонённые ограничителем подтверждаются с задержкой (защита от спама снимками)
		if typeof(seq) == "number" and seq == seq and seq == math.floor(seq) and seq > 0 and seq < 2 ^ 31 then
			DataService.ackPlace(player, seq, passed)
		end
	end)
	Remotes.RemoveBlock.OnServerEvent:Connect(onRemove)
	Remotes.ClearPlot.OnServerEvent:Connect(onClear)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		refundNoted[player] = nil
		ladderHinted[player] = nil
	end)
	DataService.addPreSaveHook(function(player)
		if layoutDirty[player] then
			BuildService.saveLayout(player)
		end
		layoutDirty[player] = nil
	end)
end

return BuildService
