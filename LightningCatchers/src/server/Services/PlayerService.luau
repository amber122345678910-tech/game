--!strict
-- Персонаж игрока и всё, что с ним связано на сервере:
--  * появление на последнем острове (новичок — на Грозовом Лугу), лицом к центру острова;
--    персонаж появляется только после загрузки данных (CharacterAutoLoads = false),
--    после смерти — через Players.RespawnTime;
--  * скорость от Сапог-скороходов, громоотвод в руке (Tool), банка на спине, табличка над головой;
--  * слежение за зоной раз в Config.Server.ZoneTick: атрибут Zone, data.LastZone, сигнал ZoneChanged;
--  * барьеры закрытых островов (отбрасываем назад к барьеру), возврат при падении ниже Config.VoidY;
--  * «Шарахнуло» (оглушение) и телепорт.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))
local Zones = require(Shared:WaitForChild("Zones"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)
local DataService = require(script.Parent.DataService)

-- Общие строители моделей (src/shared/Models.luau): громоотвод по уровню и банка.
-- Если модуля нет или он упал — свои простые модели ниже, чтобы игрок всё равно появился снаряжённым.
local SharedModels: any = nil
do
	local module = Shared:FindFirstChild("Models")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and typeof(result) == "table" then
			SharedModels = result
		else
			warn("[PlayerService] Models не загрузился, громоотвод и банка — упрощённые: " .. tostring(result))
		end
	end
end

local PlayerService = {}

-- (игрок, новая зона, прошлая зона): 0 = хаб, 1..5 = острова. Мосты зону не меняют.
PlayerService.ZoneChanged = Signal.new() :: Signal.Signal<Player, number, number>
-- (игрок, персонаж) — персонаж появился на своём месте и снаряжён
PlayerService.Spawned = Signal.new() :: Signal.Signal<Player, Model>
-- (игрок) — персонаж погиб
PlayerService.Died = Signal.new() :: Signal.Signal<Player>

-- Имена, которые ищет клиент (CharacterFX)
PlayerService.RodName = "Громоотвод" -- Tool с неоновым "Tip" и атрибутом Tier
PlayerService.JarName = "Jar" -- Model в персонаже с неоновым "Core" (внутри — выключенный PointLight)
PlayerService.NametagName = "Nametag" -- BillboardGui в голове: Title, PlayerName, Series

local CLOSED_TEXT = "Остров закрыт — открой его в магазине"

type State = {
	Loaded: boolean,
	Zone: number, -- последняя зона (как атрибут Zone)
	Area: number?, -- где игрок прямо сейчас: 0..5, nil — мост или пустота
	Character: Model?,
	Humanoid: Humanoid?,
	Root: BasePart?,
	Nametag: BillboardGui?,
	Stunned: boolean,
	StunToken: number,
	LastGateNotify: number,
	RespawnFor: Model?, -- для какого персонажа уже запланировано появление
	Conns: { RBXScriptConnection }, -- подписки текущего персонажа
}

local states: { [Player]: State } = {}
local notifyRemote: RemoteEvent? = nil

-- Оформление (только вид, на игру не влияет)
local COPPER = Color3.fromRGB(196, 120, 66)
local COPPER_DARK = Color3.fromRGB(132, 74, 40)
local RUBBER = Color3.fromRGB(38, 34, 46)
local GLASS = Color3.fromRGB(196, 228, 255)
local TAG_NAME = Color3.fromRGB(255, 255, 255)
local TAG_TITLE = Color3.fromRGB(255, 214, 90)
local TAG_SERIES = Color3.fromRGB(130, 214, 255)
local TAG_STROKE = Color3.fromRGB(10, 12, 26)
local TAG_FONT = Font.fromEnum(Enum.Font.BuilderSansExtraBold) -- с кириллицей

----------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------

local function notify(player: Player, text: string, kind: string)
	local r = notifyRemote
	if r then
		r:FireClient(player, text, kind)
	end
end

local function isValidZone(zone: number): boolean
	return zone >= 0 and zone <= #Config.Zones and zone == math.floor(zone)
end

-- Зона, куда можно поставить игрока: не закрытая и существующая
local function safeZone(zone: number?, unlocked: number): number
	if zone == nil or not isValidZone(zone) or zone > unlocked then
		return 1
	end
	return zone
end

local function zoneCenter(zone: number): Vector3
	if zone == 0 then
		return Zones.HubCenter
	end
	return Zones.Geo[zone].Center
end

-- Точка появления на зоне, лицом к её центру
local function spawnCFrame(zone: number): CFrame
	local pos = Zones.spawnFor(zone)
	local center = zoneCenter(zone)
	local target = Vector3.new(center.X, pos.Y, center.Z)
	if (target - pos).Magnitude < 0.1 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, target)
end

local function aliveHumanoid(st: State): Humanoid?
	local h = st.Humanoid
	if h and h.Parent and h.Health > 0 then
		return h
	end
	return nil
end

local function moveCharacter(st: State, cf: CFrame)
	local character = st.Character
	local root = st.Root
	if not character or not root then
		return
	end
	character:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Сменить текущую зону игрока (атрибут, data.LastZone, сигнал)
local function setZone(player: Player, st: State, zone: number)
	if st.Zone == zone then
		return
	end
	local old = st.Zone
	st.Zone = zone
	player:SetAttribute(Net.PlayerAttrs.Zone, zone)
	DataService.update(player, function(d)
		if zone <= d.Zone then
			d.LastZone = zone
		end
	end)
	PlayerService.ZoneChanged:Fire(player, zone, old)
end

----------------------------------------------------------------------
-- Модели: громоотвод, банка, табличка
----------------------------------------------------------------------

local function makePart(name: string, shape: Enum.PartType, size: Vector3, material: Enum.Material, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Material = material
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	return p
end

-- Жёстко прикрепить part1 к part0 со смещением c0 (в системе part0)
local function weld(part0: BasePart, part1: BasePart, c0: CFrame, name: string?): Weld
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.C1 = CFrame.identity
	w.Parent = part1
	return w
end

-- Цвет наконечника по уровню громоотвода (каждые 6 уровней — следующий цвет молнии)
local function tipColor(tier: number): Color3
	local id = Config.ColorOrder[math.clamp(tier + 1, 1, #Config.ColorOrder)]
	return Config.Colors[id].Color
end

local function rodTier(rodLevel: number): number
	return math.floor(rodLevel / 6)
end

-- Запасной громоотвод: медный стержень (ось X детали) с неоновым шаром на конце.
-- Хват держит стержень вертикально: ось X рукояти совпадает с "вверх" хвата.
local function simpleRod(tier: number): Tool
	local tool = Instance.new("Tool")
	tool.Name = PlayerService.RodName
	tool.ToolTip = "Громоотвод"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.Grip = CFrame.fromMatrix(Vector3.new(-1.4, 0, 0), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0))

	local handle = makePart("Handle", Enum.PartType.Cylinder, Vector3.new(4.5, 0.35, 0.35), Enum.Material.Metal, COPPER)
	handle.Reflectance = 0.1
	handle.Parent = tool

	local grip = makePart("Grip", Enum.PartType.Cylinder, Vector3.new(1.1, 0.44, 0.44), Enum.Material.Fabric, RUBBER)
	weld(handle, grip, CFrame.new(-1.4, 0, 0))
	grip.Parent = tool

	for i, x in { 1.25, 1.6 } do
		local coil = makePart("Coil" .. i, Enum.PartType.Cylinder, Vector3.new(0.14, 0.62, 0.62), Enum.Material.Metal, COPPER_DARK)
		weld(handle, coil, CFrame.new(x, 0, 0))
		coil.Parent = tool
	end

	local tip = makePart("Tip", Enum.PartType.Ball, Vector3.new(0.72, 0.72, 0.72), Enum.Material.Neon, tipColor(tier))
	weld(handle, tip, CFrame.new(2.45, 0, 0))
	tip.Parent = tool

	local spike = makePart("Spike", Enum.PartType.Cylinder, Vector3.new(0.9, 0.12, 0.12), Enum.Material.Metal, COPPER)
	weld(handle, spike, CFrame.new(2.9, 0, 0))
	spike.Parent = tool

	tool:SetAttribute("Tier", tier)
	return tool
end

-- Запасная банка: стекло + медные крышки + неоновое ядро "Core" (клиент масштабирует по JarFill).
-- Ось цилиндров — X деталей, поэтому при креплении модель поворачивается осью X вверх.
local function simpleJar(): (Model, BasePart, CFrame)
	local model = Instance.new("Model")
	model.Name = PlayerService.JarName

	-- ось цилиндров — X детали; при креплении к спине X смотрит вверх
	local glass = makePart("Glass", Enum.PartType.Cylinder, Vector3.new(2, 1.4, 1.4), Enum.Material.Glass, GLASS)
	glass.Transparency = 0.5
	glass.Parent = model
	model.PrimaryPart = glass

	local capTop = makePart("CapTop", Enum.PartType.Cylinder, Vector3.new(0.26, 1.52, 1.52), Enum.Material.Metal, COPPER)
	weld(glass, capTop, CFrame.new(1.08, 0, 0))
	capTop.Parent = model

	local capBottom = makePart("CapBottom", Enum.PartType.Cylinder, Vector3.new(0.26, 1.52, 1.52), Enum.Material.Metal, COPPER)
	weld(glass, capBottom, CFrame.new(-1.08, 0, 0))
	capBottom.Parent = model

	local terminal = makePart("Terminal", Enum.PartType.Ball, Vector3.new(0.38, 0.38, 0.38), Enum.Material.Metal, COPPER_DARK)
	weld(glass, terminal, CFrame.new(1.3, 0, 0))
	terminal.Parent = model

	local core = makePart("Core", Enum.PartType.Cylinder, Vector3.new(1.7, 1.12, 1.12), Enum.Material.Neon, Config.Colors.blue.Color)
	core.Transparency = 0.1
	weld(glass, core, CFrame.identity, "CoreWeld")
	core.Parent = model

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Enabled = false -- включает клиент
	light.Color = Config.Colors.blue.Color
	light.Range = 10
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = core

	return model, glass, CFrame.Angles(0, 0, math.pi / 2)
end

-- Громоотвод нужного уровня: общий из Models или запасной
local function buildRod(tier: number): Tool
	if SharedModels then
		local ok, tool = pcall(SharedModels.rod, tier)
		if ok and typeof(tool) == "Instance" and tool:IsA("Tool") and tool:FindFirstChild("Handle") then
			tool.Name = PlayerService.RodName
			tool.ManualActivationOnly = true
			tool.CanBeDropped = false
			tool.RequiresHandle = true
			tool:SetAttribute("Tier", tier)
			return tool
		end
		warn("[PlayerService] Models.rod: " .. tostring(tool))
	end
	return simpleRod(tier)
end

-- Банка: (модель, деталь для крепления, поворот модели относительно спины)
local function buildJar(): (Model, BasePart, CFrame)
	if SharedModels then
		local ok, jar = pcall(SharedModels.jar)
		if ok and typeof(jar) == "Instance" and jar:IsA("Model") and jar.PrimaryPart and jar:FindFirstChild("Core") then
			jar.Name = PlayerService.JarName
			-- у общей банки ось уже вертикальная, а ремень (+Z модели) должен смотреть к спине
			return jar, jar.PrimaryPart :: BasePart, CFrame.Angles(0, math.pi, 0)
		end
		warn("[PlayerService] Models.jar: " .. tostring(jar))
	end
	return simpleJar()
end

local function makeLabel(name: string, order: number, height: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.FontFace = TAG_FONT
	label.TextSize = height
	label.TextColor3 = color
	label.TextStrokeColor3 = TAG_STROKE
	label.TextStrokeTransparency = 0.3
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	return label
end

local function buildNametag(player: Player): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = PlayerService.NametagName
	gui.Size = UDim2.fromOffset(220, 64)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = Config.Server.NametagDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.PlayerToHideFrom = player -- свою табличку не видишь

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = gui

	makeLabel("Title", 1, 16, TAG_TITLE).Parent = gui
	local name = makeLabel("PlayerName", 2, 24, TAG_NAME)
	name.Text = player.DisplayName
	name.Parent = gui
	makeLabel("Series", 3, 16, TAG_SERIES).Parent = gui
	return gui
end

local function updateNametag(player: Player, st: State)
	local gui = st.Nametag
	if not gui then
		return
	end
	local title = gui:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		local text = player:GetAttribute(Net.PlayerAttrs.Title)
		local s = if typeof(text) == "string" then text else ""
		title.Text = s
		title.Visible = s ~= ""
	end
	local series = gui:FindFirstChild("Series")
	if series and series:IsA("TextLabel") then
		local best = player:GetAttribute(Net.PlayerAttrs.BestCombo)
		local n = if typeof(best) == "number" then math.floor(best) else 0
		series.Text = "Серия: " .. tostring(n)
		series.Visible = n > 0
	end
end

----------------------------------------------------------------------
-- Скорость и показатели
----------------------------------------------------------------------

local function applyWalkSpeed(player: Player, st: State)
	local humanoid = st.Humanoid
	local d = DataService.get(player)
	if not humanoid or not d then
		return
	end
	humanoid.WalkSpeed = if st.Stunned then 0 else Economy.walkSpeed(d.Upgrades.Boots)
end

local function findRod(player: Player, st: State): Tool?
	local character = st.Character
	local inChar = character and character:FindFirstChild(PlayerService.RodName)
	if inChar and inChar:IsA("Tool") then
		return inChar
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local inPack = backpack and backpack:FindFirstChild(PlayerService.RodName)
	if inPack and inPack:IsA("Tool") then
		return inPack
	end
	return nil
end

local giveRod: (player: Player, st: State, character: Model, humanoid: Humanoid) -> ()

-- Обновить скорость, атрибуты и вид после покупки, перезапуска или загрузки
function PlayerService.refreshStats(player: Player)
	local st = states[player]
	local d = DataService.get(player)
	if not st or not d then
		return
	end
	local tier = rodTier(d.Upgrades.Rod)
	player:SetAttribute(Net.PlayerAttrs.Rebirths, d.Rebirths)
	player:SetAttribute(Net.PlayerAttrs.BestCombo, d.Stats.BestCombo)
	player:SetAttribute(Net.PlayerAttrs.RodTier, tier)
	applyWalkSpeed(player, st)
	-- новый уровень громоотвода — новая модель в руке
	local rod = findRod(player, st)
	local character = st.Character
	local humanoid = aliveHumanoid(st)
	if rod and rod:GetAttribute("Tier") ~= tier and character and humanoid then
		giveRod(player, st, character, humanoid)
	end
	updateNametag(player, st)
end

----------------------------------------------------------------------
-- Персонаж
----------------------------------------------------------------------

local function disconnectCharacter(st: State)
	for _, c in st.Conns do
		c:Disconnect()
	end
	table.clear(st.Conns)
end

local function loadCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		warn("[PlayerService] LoadCharacter " .. player.Name .. ": " .. tostring(err))
	end
end

-- Появиться заново через RespawnTime (один раз на персонажа)
local function scheduleRespawn(player: Player, st: State, character: Model)
	if st.RespawnFor == character then
		return
	end
	st.RespawnFor = character
	task.delay(Players.RespawnTime, function()
		if states[player] ~= st or player.Parent ~= Players then
			return
		end
		local current = player.Character
		if current == nil or current == character then
			loadCharacter(player)
		end
	end)
end

function giveRod(player: Player, st: State, character: Model, humanoid: Humanoid)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if player.Character ~= character or aliveHumanoid(st) ~= humanoid then
		return
	end
	local d = DataService.get(player)
	local tier = if d then rodTier(d.Upgrades.Rod) else 0
	-- убрать старые копии (повторная настройка того же персонажа)
	local old = findRod(player, st)
	while old do
		old:Destroy()
		old = findRod(player, st)
	end
	local rod = buildRod(tier)
	rod.Parent = if backpack then backpack else st.Character
	humanoid:EquipTool(rod)
	-- громоотвод всегда в руке: если его убрали в рюкзак — достать снова
	table.insert(
		st.Conns,
		rod.AncestryChanged:Connect(function()
			local parent = rod.Parent
			if parent and parent:IsA("Backpack") and aliveHumanoid(st) == humanoid then
				task.defer(function()
					if rod.Parent == parent and aliveHumanoid(st) == humanoid then
						humanoid:EquipTool(rod)
					end
				end)
			end
		end)
	)
end

local function attachJar(character: Model)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild(PlayerService.JarName)
	if old then
		old:Destroy()
	end
	local jar, anchor, turn = buildJar()
	-- за спиной (+Z торса), ось банки вертикально
	local _, size = jar:GetBoundingBox()
	local depth = math.min(size.X, size.Z)
	local back = torso.Size.Z / 2 + depth / 2 + 0.05
	weld(torso, anchor, CFrame.new(0, 0.1, back) * turn, "JarWeld")
	jar.Parent = character
end

local function attachNametag(player: Player, st: State, character: Model)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild(PlayerService.NametagName)
	if old then
		old:Destroy()
	end
	local gui = buildNametag(player)
	gui.Adornee = head
	gui.Parent = head
	st.Nametag = gui
	updateNametag(player, st)
end

local function onCharacterAdded(player: Player, character: Model)
	local st = states[player]
	if not st then
		return
	end
	disconnectCharacter(st)
	st.Character = character
	st.Humanoid = nil
	st.Root = nil
	st.Nametag = nil
	st.Stunned = false
	st.StunToken += 1

	local humanoidInst = character:WaitForChild("Humanoid", 10)
	local rootInst = character:WaitForChild("HumanoidRootPart", 10)
	if player.Character ~= character or states[player] ~= st then
		return
	end
	if not humanoidInst or not humanoidInst:IsA("Humanoid") or not rootInst or not rootInst:IsA("BasePart") then
		warn("[PlayerService] у персонажа нет Humanoid/HumanoidRootPart: " .. player.Name)
		return
	end
	local humanoid: Humanoid = humanoidInst
	local root: BasePart = rootInst
	st.Humanoid = humanoid
	st.Root = root

	-- место появления: последний открытый остров (или хаб), новичок — остров 1
	local d = DataService.get(player)
	local zone = safeZone(if d then d.LastZone else 1, if d then d.Zone else 1)
	moveCharacter(st, spawnCFrame(zone))
	setZone(player, st, zone)
	st.Area = zone

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	applyWalkSpeed(player, st)
	attachJar(character)
	attachNametag(player, st, character)

	table.insert(
		st.Conns,
		humanoid.Died:Connect(function()
			PlayerService.Died:Fire(player)
			scheduleRespawn(player, st, character)
		end)
	)
	table.insert(
		st.Conns,
		character.AncestryChanged:Connect(function()
			-- персонажа убрали без смерти (например, удалили скриптом) — вернуть игрока
			if not character:IsDescendantOf(Workspace) and player.Character == character then
				scheduleRespawn(player, st, character)
			end
		end)
	)
	-- громоотвод последним: ожидание рюкзака может уступить кадр
	giveRod(player, st, character, humanoid)
	if player.Character == character and states[player] == st then
		PlayerService.Spawned:Fire(player, character)
	end
end

----------------------------------------------------------------------
-- Зоны, барьеры, падение
----------------------------------------------------------------------

-- Если игрок зашёл за барьер закрытого острова (или уже на нём) — номер этого острова
local function lockedZoneAt(pos: Vector3, area: number?, unlocked: number): number?
	if area ~= nil and area > unlocked then
		return area
	end
	if area ~= nil then
		return nil
	end
	local halfWidth = Config.BridgeWidth / 2 + Config.Server.GateSideSlack
	for z = unlocked + 1, #Config.Zones do
		local g = Zones.Geo[z]
		local along, side, length = ServerLogic.bridgeCoords(pos, g.BridgeStart, g.BridgeEnd)
		if side <= halfWidth and along <= length + Config.Zones[z].Radius then
			local gateAlong = ServerLogic.bridgeCoords(g.Gate, g.BridgeStart, g.BridgeEnd)
			if along >= gateAlong then
				return z
			end
		end
	end
	return nil
end

-- Отбросить игрока на мост перед барьером острова zone
local function pushBack(player: Player, st: State, zone: number)
	local g = Zones.Geo[zone]
	local gateAlong = ServerLogic.bridgeCoords(g.Gate, g.BridgeStart, g.BridgeEnd)
	local point = ServerLogic.bridgePoint(g.BridgeStart, g.BridgeEnd, gateAlong - Config.Server.GatePushBack)
	local pos = point + Vector3.new(0, 3, 0)
	moveCharacter(st, CFrame.lookAt(pos, pos + g.ToHub))
	local clock = os.clock()
	if clock - st.LastGateNotify >= Config.Server.GateNotifyEvery then
		st.LastGateNotify = clock
		notify(player, CLOSED_TEXT, "bad")
	end
end

local function track(player: Player, st: State)
	local root = st.Root
	local d = DataService.get(player)
	if not st.Loaded or not d or not root or not root.Parent or not aliveHumanoid(st) then
		return
	end
	local pos = root.Position
	if pos.Y < Config.VoidY then
		-- упал с острова: мягко вернуть на точку появления последней зоны
		local zone = safeZone(st.Zone, d.Zone)
		moveCharacter(st, spawnCFrame(zone))
		setZone(player, st, zone)
		st.Area = zone
		return
	end
	local area = Zones.zoneAt(pos)
	local locked = lockedZoneAt(pos, area, d.Zone)
	if locked then
		pushBack(player, st, locked)
		st.Area = nil
		return
	end
	st.Area = area
	if area ~= nil and area ~= st.Zone then
		setZone(player, st, area)
	end
end

----------------------------------------------------------------------
-- Публичное API
----------------------------------------------------------------------

-- Последняя зона игрока: 0 = хаб, 1..5 = остров (на мосту — та, откуда пришёл)
function PlayerService.getZone(player: Player): number
	local st = states[player]
	return if st then st.Zone else 0
end

-- Где игрок прямо сейчас: 0..5 или nil (мост, пустота, нет персонажа)
function PlayerService.getArea(player: Player): number?
	local st = states[player]
	return if st then st.Area else nil
end

-- HumanoidRootPart живого персонажа
function PlayerService.getRoot(player: Player): BasePart?
	local st = states[player]
	if not st then
		return nil
	end
	local root = st.Root
	if root and root.Parent and aliveHumanoid(st) then
		return root
	end
	return nil
end

function PlayerService.getHumanoid(player: Player): Humanoid?
	local st = states[player]
	return if st then aliveHumanoid(st) else nil
end

-- «Шарахнуло»: сажа/искры у клиентов (атрибут ZappedUntil) и оглушение на stun секунд
function PlayerService.zap(player: Player, stun: number)
	local st = states[player]
	if not st then
		return
	end
	player:SetAttribute(Net.PlayerAttrs.ZappedUntil, Workspace:GetServerTimeNow() + Config.Catch.ZapVisual)
	if not ServerLogic.isFinite(stun) or stun <= 0 then
		return
	end
	st.StunToken += 1
	local token = st.StunToken
	st.Stunned = true
	applyWalkSpeed(player, st)
	task.delay(stun, function()
		if states[player] ~= st or st.StunToken ~= token then
			return
		end
		st.Stunned = false
		applyWalkSpeed(player, st)
	end)
end

-- Перенести игрока на точку появления зоны (0 = хаб). Только на открытые острова.
function PlayerService.teleport(player: Player, zone: any): (boolean, string?)
	if not ServerLogic.isInteger(zone) or not isValidZone(zone) then
		return false, "Нет такого острова"
	end
	local st = states[player]
	local d = DataService.get(player)
	if not st or not d then
		return false, "Данные ещё загружаются"
	end
	if zone > d.Zone then
		return false, CLOSED_TEXT
	end
	if not aliveHumanoid(st) or not st.Root then
		return false, "Подожди, пока появится персонаж"
	end
	moveCharacter(st, spawnCFrame(zone))
	setZone(player, st, zone)
	st.Area = zone
	return true, nil
end

----------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------

local function newState(): State
	return {
		Loaded = false,
		Zone = 1,
		Area = nil,
		Character = nil,
		Humanoid = nil,
		Root = nil,
		Nametag = nil,
		Stunned = false,
		StunToken = 0,
		LastGateNotify = 0,
		RespawnFor = nil,
		Conns = {},
	}
end

local function onPlayerAdded(player: Player)
	if states[player] then
		return
	end
	local st = newState()
	states[player] = st
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:GetAttributeChangedSignal(Net.PlayerAttrs.Title):Connect(function()
		updateNametag(player, st)
	end)
	player:GetAttributeChangedSignal(Net.PlayerAttrs.BestCombo):Connect(function()
		updateNametag(player, st)
	end)
end

local onLoaded: (player: Player) -> ()

-- Игрок вошёл: состояние + (если данные уже загрузились раньше нас) сразу появление
local function onPlayerJoined(player: Player)
	onPlayerAdded(player)
	if DataService.get(player) then
		task.spawn(onLoaded, player)
	end
end

function onLoaded(player: Player)
	local st = states[player]
	local d = DataService.get(player)
	if not st or not d or st.Loaded then
		return
	end
	st.Loaded = true
	st.Zone = safeZone(d.LastZone, d.Zone)
	player:SetAttribute(Net.PlayerAttrs.Zone, st.Zone)
	player:SetAttribute(Net.PlayerAttrs.Combo, 0)
	player:SetAttribute(Net.PlayerAttrs.ZappedUntil, 0)
	PlayerService.refreshStats(player)
	local character = player.Character
	if character then
		-- персонаж появился раньше загрузки (Studio): настроить заново уже с данными
		task.spawn(onCharacterAdded, player, character)
	else
		loadCharacter(player)
	end
end

local function onPlayerRemoving(player: Player)
	local st = states[player]
	if st then
		disconnectCharacter(st)
		st.StunToken += 1
	end
	states[player] = nil
end

function PlayerService.start()
	notifyRemote = Net.event("Notify")
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(onPlayerJoined)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.Loaded:Connect(function(player)
		onLoaded(player)
	end)
	for _, player in Players:GetPlayers() do
		onPlayerJoined(player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Server.ZoneTick)
			for player, st in states do
				local ok, err = pcall(track, player, st)
				if not ok then
					warn("[PlayerService] зона " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return PlayerService
