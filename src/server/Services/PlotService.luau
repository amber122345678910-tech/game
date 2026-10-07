--!strict
-- Участки игроков: выдача участка, блоки на сетке, урон блокам, зоны (на участке / в бункере).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StormSim = require(Shared:WaitForChild("StormSim"))

export type BlockRecord = StormSim.Block

export type Plot = {
	Id: number,
	Model: Model,
	Origin: CFrame,
	Owner: Player?,
	Cells: { [number]: BlockRecord }, -- индекс клетки -> блок (дверь занимает 2 клетки)
	Records: { BlockRecord },
	BlocksFolder: Folder,
	StormFolder: Folder,
	SignLabels: { TextLabel },
	Session: any?, -- активный шторм (StormService)
	InteriorCache: { [number]: boolean }?,
	Version: number, -- увеличивается при любом изменении блоков
}

local PlotService = {}

local CELL = Grid.CELL
local PIT = Config.Plot.PitHalfSize

local plots: { Plot } = {}
local playerPlots: { [Player]: Plot } = {}
local scheduleBunkerCheck: (plot: Plot) -> ()

local HAIL_TINT = Color3.fromRGB(45, 45, 50)
local ACID_TINT = Color3.fromRGB(95, 160, 35)

local function setSign(plot: Plot, text: string)
	for _, labelObj in plot.SignLabels do
		labelObj.Text = text
	end
end

local function updateOwnerAttributes(plot: Plot)
	local owner = plot.Owner
	plot.Model:SetAttribute("OwnerId", if owner then owner.UserId else 0)
	plot.Model:SetAttribute("OwnerName", if owner then owner.DisplayName else "")
	if owner then
		setSign(plot, "Бункер: " .. owner.DisplayName)
	else
		setSign(plot, "Свободный участок")
	end
end

function PlotService.init()
	local folder = workspace:WaitForChild("Plots")
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local id = child:GetAttribute("PlotId")
			local origin = child:GetAttribute("Origin")
			if typeof(id) == "number" and typeof(origin) == "CFrame" then
				local blocks = child:FindFirstChild("Blocks")
				local storm = child:FindFirstChild("Storm")
				local blocksFolder: Folder
				if blocks and blocks:IsA("Folder") then
					blocksFolder = blocks
				else
					blocksFolder = Instance.new("Folder")
					blocksFolder.Name = "Blocks"
					blocksFolder.Parent = child
				end
				local stormFolder: Folder
				if storm and storm:IsA("Folder") then
					stormFolder = storm
				else
					stormFolder = Instance.new("Folder")
					stormFolder.Name = "Storm"
					stormFolder.Parent = child
				end
				local labels: { TextLabel } = {}
				local sign = child:FindFirstChild("Sign")
				if sign then
					for _, d in sign:GetDescendants() do
						if d:IsA("TextLabel") then
							table.insert(labels, d)
						end
					end
				end
				local plot: Plot = {
					Id = id,
					Model = child,
					Origin = origin,
					Owner = nil,
					Cells = {},
					Records = {},
					BlocksFolder = blocksFolder,
					StormFolder = stormFolder,
					SignLabels = labels,
					Session = nil,
					InteriorCache = nil,
					Version = 0,
				}
				table.insert(plots, plot)
				updateOwnerAttributes(plot)
				child:SetAttribute("Phase", "")
			else
				warn("[PlotService] Plot model without PlotId/Origin attributes: " .. child:GetFullName())
			end
		end
	end
	table.sort(plots, function(a: Plot, b: Plot)
		return a.Id < b.Id
	end)

	-- Отслеживание зон игроков (5 раз в секунду).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0
		for player, plot in playerPlots do
			PlotService.updatePlayerZone(player, plot)
		end
	end)
end

function PlotService.getPlots(): { Plot }
	return plots
end

function PlotService.getPlot(player: Player): Plot?
	return playerPlots[player]
end

function PlotService.getPlotById(id: number): Plot?
	for _, plot in plots do
		if plot.Id == id then
			return plot
		end
	end
	return nil
end

function PlotService.assign(player: Player): Plot?
	local existing = playerPlots[player]
	if existing then
		return existing
	end
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			playerPlots[player] = plot
			player:SetAttribute("PlotId", plot.Id)
			updateOwnerAttributes(plot)
			return plot
		end
	end
	return nil
end

function PlotService.release(player: Player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	playerPlots[player] = nil
	PlotService.clear(plot)
	plot.Owner = nil
	updateOwnerAttributes(plot)
end

-- CFrame блока в мире (центр детали).
function PlotService.blockCFrame(plot: Plot, x: number, y: number, z: number, rot: number, heightCells: number): CFrame
	local lx, _, lz = Grid.cellCenterLocal(x, y, z)
	local ly = (y + heightCells / 2) * CELL
	return plot.Origin * CFrame.new(lx, ly, lz) * CFrame.Angles(0, rot * math.pi / 2, 0)
end

function PlotService.cellWorldPosition(plot: Plot, x: number, y: number, z: number): Vector3
	local lx, ly, lz = Grid.cellCenterLocal(x, y, z)
	return (plot.Origin:PointToWorldSpace(Vector3.new(lx, ly, lz)))
end

function PlotService.toLocal(plot: Plot, worldPos: Vector3): Vector3
	return (plot.Origin:PointToObjectSpace(worldPos))
end

function PlotService.toWorld(plot: Plot, localPos: Vector3): Vector3
	return (plot.Origin:PointToWorldSpace(localPos))
end

function PlotService.isInZone(plot: Plot, worldPos: Vector3): boolean
	local p = plot.Origin:PointToObjectSpace(worldPos)
	local half = PIT + Config.Plot.ZoneMargin
	return math.abs(p.X) <= half and math.abs(p.Z) <= half and p.Y >= -3 and p.Y <= Config.Plot.ZoneTop
end

-- Проверка возможности поставить блок (без учёта инвентаря и шторма).
-- skipSupport: для доверенных раскладок (готовые бункеры, сохранения, восстановление после шторма)
-- проверку опоры пропускаем — иначе результат зависел бы от порядка установки блоков.
function PlotService.canPlace(
	plot: Plot,
	def: Config.BlockDef,
	x: number,
	y: number,
	z: number,
	skipSupport: boolean?
): (boolean, string?)
	local top = y + def.HeightCells - 1
	if not Grid.inBounds(x, y, z) or not Grid.inBounds(x, top, z) then
		return false, "Здесь нельзя строить"
	end
	for _, cell in Grid.footprint(x, y, z, def.HeightCells) do
		if plot.Cells[cell] then
			return false, "Клетка занята"
		end
	end
	-- Опора: на полу или рядом с другим блоком (без "висящих в воздухе" блоков).
	if y > 0 and not skipSupport then
		local supported = false
		for dy = 0, def.HeightCells - 1 do
			for _, d in Grid.NEIGHBORS do
				local nx, ny, nz = x + d[1], y + dy + d[2], z + d[3]
				if Grid.inBounds(nx, ny, nz) and plot.Cells[Grid.index(nx, ny, nz)] then
					supported = true
					break
				end
			end
			if supported then
				break
			end
		end
		if not supported then
			return false, "Нужна опора: ставь на пол или рядом с блоком"
		end
	end
	return true, nil
end

-- Атрибут HasBunker (есть ли замкнутый бункер) пересчитываем один раз после серии изменений.
local bunkerCheckQueued: { [Plot]: boolean } = {}
scheduleBunkerCheck = function(plot: Plot)
	if bunkerCheckQueued[plot] then
		return
	end
	bunkerCheckQueued[plot] = true
	task.defer(function()
		bunkerCheckQueued[plot] = nil
		if plot.Session == nil then
			PlotService.getInterior(plot)
		end
	end)
end

local function createPart(plot: Plot, rec: BlockRecord): BasePart
	local def = rec.def
	local p = Instance.new("Part")
	p.Name = def.Id
	p.Anchored = true
	p.CanTouch = false
	p.CanQuery = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = def.Material
	p.Color = def.Color
	p.Transparency = def.Transparency
	p.Reflectance = def.Reflectance
	if def.IsDoor then
		p.Size = Vector3.new(CELL, CELL * def.HeightCells, 1)
	else
		p.Size = Vector3.new(CELL, CELL, CELL)
	end
	p.CFrame = PlotService.blockCFrame(plot, rec.x, rec.y, rec.z, rec.rot, def.HeightCells)
	p:SetAttribute("BlockId", def.Id)
	p:SetAttribute("Cell", Grid.index(rec.x, rec.y, rec.z))
	p:SetAttribute("PlotId", plot.Id)
	if def.IsDoor then
		p:SetAttribute("IsDoor", true)
		-- ручка (только визуал)
		for _, side in { -1, 1 } do
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Anchored = true
			handle.CanCollide = false
			handle.CanQuery = false
			handle.CanTouch = false
			handle.CastShadow = false
			handle.Size = Vector3.new(0.3, 1.2, 0.3)
			handle.Color = Color3.fromRGB(230, 200, 90)
			handle.Material = Enum.Material.Metal
			handle.CFrame = p.CFrame * CFrame.new(CELL * 0.32, -0.2, side * 0.65)
			handle.Parent = p
		end
	end
	p.Parent = plot.BlocksFolder
	return p
end

-- Ставит блок без проверок инвентаря. Возвращает запись или nil.
function PlotService.place(
	plot: Plot,
	blockId: string,
	x: number,
	y: number,
	z: number,
	rot: number,
	skipSupport: boolean?
): BlockRecord?
	local def = Config.getBlock(blockId)
	if not def then
		return nil
	end
	local ok = PlotService.canPlace(plot, def, x, y, z, skipSupport)
	if not ok then
		return nil
	end
	local rec: BlockRecord = {
		id = def.Id,
		def = def,
		x = x,
		y = y,
		z = z,
		rot = Grid.normalizeRot(rot),
		hp = def.HP,
		maxHp = def.HP,
		cells = Grid.footprint(x, y, z, def.HeightCells),
		part = nil :: any,
		tintBucket = 4,
		alive = true,
	}
	rec.part = createPart(plot, rec)
	for _, cell in rec.cells do
		plot.Cells[cell] = rec
	end
	table.insert(plot.Records, rec)
	plot.Version += 1
	plot.InteriorCache = nil
	scheduleBunkerCheck(plot)
	return rec
end

local function detach(plot: Plot, rec: BlockRecord)
	rec.alive = false
	for _, cell in rec.cells do
		if plot.Cells[cell] == rec then
			plot.Cells[cell] = nil
		end
	end
	local i = table.find(plot.Records, rec)
	if i then
		-- порядок записей не важен: быстрое удаление
		local last = #plot.Records
		plot.Records[i] = plot.Records[last]
		plot.Records[last] = nil
	end
	plot.Version += 1
	plot.InteriorCache = nil
	scheduleBunkerCheck(plot)
	rec.part:Destroy()
end

-- Убирает блок в клетке (любой из клеток двери). Возвращает удалённую запись.
function PlotService.remove(plot: Plot, x: number, y: number, z: number): BlockRecord?
	if not Grid.inBounds(x, y, z) then
		return nil
	end
	local rec = plot.Cells[Grid.index(x, y, z)]
	if not rec then
		return nil
	end
	detach(plot, rec)
	return rec
end

-- Убирает все блоки. Возвращает количество убранных блоков по типам.
function PlotService.clear(plot: Plot): { [string]: number }
	local counts: { [string]: number } = {}
	for _, rec in plot.Records do
		rec.alive = false
		counts[rec.id] = (counts[rec.id] or 0) + 1
		rec.part:Destroy()
	end
	table.clear(plot.Records)
	table.clear(plot.Cells)
	plot.BlocksFolder:ClearAllChildren()
	plot.Version += 1
	plot.InteriorCache = nil
	scheduleBunkerCheck(plot)
	return counts
end

function PlotService.getEntries(plot: Plot): { Grid.Entry }
	local entries: { Grid.Entry } = {}
	for _, rec in plot.Records do
		table.insert(entries, { id = rec.id, x = rec.x, y = rec.y, z = rec.z, rot = rec.rot })
	end
	-- снизу вверх, чтобы при загрузке у блоков была опора
	table.sort(entries, function(a: Grid.Entry, b: Grid.Entry)
		if a.y ~= b.y then
			return a.y < b.y
		end
		return Grid.index(a.x, a.y, a.z) < Grid.index(b.x, b.y, b.z)
	end)
	return entries
end

function PlotService.serialize(plot: Plot): string
	return Grid.serialize(PlotService.getEntries(plot))
end

-- Загружает доверенную раскладку (без инвентаря и без проверки опоры).
function PlotService.loadEntries(plot: Plot, entries: { Grid.Entry }): number
	local placed = 0
	for _, e in entries do
		if PlotService.place(plot, e.id, e.x, e.y, e.z, e.rot, true) then
			placed += 1
		end
	end
	return placed
end

-- Урон блоку. Возвращает true, если блок разрушен.
function PlotService.damage(plot: Plot, rec: BlockRecord, amount: number, kind: "hail" | "acid"): boolean
	if not rec.alive or amount <= 0 then
		return false
	end
	rec.hp -= amount
	if rec.hp <= 0 then
		local pos = rec.part.Position
		local color = rec.def.Color
		detach(plot, rec)
		Remotes.BlockBroken:FireAllClients(plot.Id, pos, color)
		return true
	end
	-- перекрашиваем ступенчато (4 стадии), чтобы не слать изменение свойства на каждый удар
	local frac = rec.hp / rec.maxHp
	local bucket = math.floor(frac * 4)
	if bucket ~= rec.tintBucket then
		rec.tintBucket = bucket
		local tint = if kind == "acid" then ACID_TINT else HAIL_TINT
		rec.part.Color = rec.def.Color:Lerp(tint, (1 - frac) * 0.65)
	end
	return false
end

function PlotService.getInterior(plot: Plot): { [number]: boolean }
	local cache = plot.InteriorCache
	if cache then
		return cache
	end
	local interior = Grid.computeInterior(plot.Cells)
	plot.InteriorCache = interior
	-- клиенту: есть ли на участке замкнутый бункер (для кнопки СТАРТ)
	local hasBunker = next(interior) ~= nil
	if plot.Model:GetAttribute("HasBunker") ~= hasBunker then
		plot.Model:SetAttribute("HasBunker", hasBunker)
	end
	return interior
end

-- Клетка, в которой находится тело игрока (по корню персонажа), или nil.
function PlotService.playerCell(plot: Plot, player: Player): (number?, Vector3?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, nil
	end
	local lp = plot.Origin:PointToObjectSpace(root.Position)
	-- корень R15 примерно в 3 стадах над полом: берём точку чуть ниже корня
	local cx, cy, cz = Grid.localToCell(lp.X, lp.Y - 1.5, lp.Z)
	if Grid.inBounds(cx, cy, cz) then
		return Grid.index(cx, cy, cz), lp
	end
	return nil, lp
end

function PlotService.updatePlayerZone(player: Player, plot: Plot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inZone = false
	local inBunker = false
	if root and root:IsA("BasePart") then
		inZone = PlotService.isInZone(plot, root.Position)
		if inZone then
			local cell = PlotService.playerCell(plot, player)
			if cell then
				local interior = if plot.Session and plot.Session.Interior
					then plot.Session.Interior :: { [number]: boolean }
					else PlotService.getInterior(plot)
				inBunker = interior[cell] == true
			end
		end
	end
	if player:GetAttribute("InPlotZone") ~= inZone then
		player:SetAttribute("InPlotZone", inZone)
	end
	if player:GetAttribute("InBunker") ~= inBunker then
		player:SetAttribute("InBunker", inBunker)
	end
end

function PlotService.totalHP(plot: Plot): (number, number)
	local hp, maxHp = 0, 0
	for _, rec in plot.Records do
		hp += math.max(rec.hp, 0)
		maxHp += rec.maxHp
	end
	return hp, maxHp
end

return PlotService
