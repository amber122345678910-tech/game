--!strict
-- Фульгуриты на сервере:
--  * tryDrop — шанс фульгурита при ИДЕАЛЬНОЙ поимке (ставится в StrikeService.dropHook):
--    Fulgurite.rollDrop с удачей питомцев; grant — гарантированный фульгурит (Радужная, Перун).
--    Номер = data.NextFulgId, seed = Prng.hash(UserId, номер), мутация Fulgurite.rollMutation.
--    Коллекция полна: обычный фульгурит не выпадает, а гарантированный освобождает себе место —
--    самый простой ненадетый разбивается в осколки (все надеты — кладём сверх лимита);
--  * Request: EquipFulg / UnequipFulg (до Fulgurite.MaxEquipped), DeleteFulg (разбить → осколки по редкости);
--  * Галерея в хабе: каждому игроку на сервере — свой пьедестал (Map.Markers.Pedestal_N), на нём лучший
--    надетый (или лучший из всех) фульгурит и табличка «Имя / редкость · №000123». Перестраивается,
--    когда меняется набор фульгуритов, и очищается, когда игрок уходит.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Fulgurite = require(Shared:WaitForChild("Fulgurite"))
local Models = require(Shared:WaitForChild("Models"))
local Net = require(Shared:WaitForChild("Net"))
local Pets = require(Shared:WaitForChild("Pets"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Prng = require(Shared:WaitForChild("Prng"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RequestService = require(script.Parent.RequestService)
local StrikeService = require(script.Parent.StrikeService)

type Data = PlayerData.Data
type FulgRecord = PlayerData.FulgRecord

local FulguriteService = {}

local LOADING = "Данные ещё загружаются"
local NO_FULG = "Нет такого фульгурита"

-- Осколки за разбитый фульгурит по редкости (умножаются на ShardValue острова, где он найден).
-- Таблица общая с клиентом: окно «Разбить» показывает ту же сумму
local SHATTER_SHARDS = Fulgurite.ShatterShards

local NOTIFY_RARE_RANK = 4 -- легендарный+ — тост «редкий»
local BANNER_RANK = 5 -- мифический — баннер на весь сервер

-- Витрина галереи (только вид). Пьедесталы стоят дугой через ~4.3 стада — витрины и таблички уже этого.
local DISPLAY_HEIGHT = 5 -- целевая высота фульгурита на пьедестале (4–6 стадов)
local DISPLAY_MIN_HEIGHT = 4
local DISPLAY_MAX_FOOTPRINT = 3.2 -- шире не раздуваем: не залезать на соседний пьедестал
local DISPLAY_MAX_PARTS = 48 -- витрин до 12 и их видят все телефоны: без узелков и не больше стольких деталей
local DISPLAY_LIGHT_RANK = 4 -- своё свечение только у легендарных и мифических
local LABEL_GAP = 1.6 -- табличка над верхушкой
local LABEL_STAGGER = 1.3 -- у чётных пьедесталов табличка выше, чтобы соседние не налезали
local LABEL_SIZE = UDim2.fromScale(4, 1.5) -- в стадах
local LABEL_DISTANCE = 40
local LABEL_FONT = Font.fromEnum(Enum.Font.BuilderSansExtraBold)
local LABEL_STROKE = Color3.fromRGB(10, 12, 26)
local DIM_TEXT = Color3.fromRGB(176, 186, 220)

local notifyRemote: RemoteEvent? = nil
local bannerRemote: RemoteEvent? = nil

-- Пьедесталы галереи
type Pedestal = {
	Index: number,
	Marker: BasePart,
	Owner: Player?,
	Display: Model?,
	Key: string, -- какой фульгурит сейчас стоит (чтобы не перестраивать зря)
}

local pedestals: { Pedestal } = {}
local byPlayer: { [Player]: Pedestal } = {}
local signatures: { [Player]: string } = {}
local fullNotified: { [Player]: boolean } = {}
local galleryFolder: Folder? = nil

----------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------

local function notify(player: Player, text: string, kind: string)
	local r = notifyRemote
	if r then
		r:FireClient(player, text, kind)
	end
end

local function serialText(serial: number): string
	return string.format("№%06d", serial)
end

local function specOf(f: FulgRecord): Fulgurite.Spec
	return Fulgurite.generate(f.Seed, f.Color, f.Mut :: any)
end

local function isColor(v: any): boolean
	return typeof(v) == "string" and (Config.Colors :: any)[v] ~= nil
end

-- Облегчённая копия для витрины: без стеклянных узелков на стыках, не больше DISPLAY_MAX_PARTS деталей
local function displaySpec(spec: Fulgurite.Spec): Fulgurite.Spec
	local parts: { Fulgurite.PartSpec } = {}
	for _, ps in spec.Parts do
		if not (ps.Kind == "glass" and ps.Shape == "Ball") then
			table.insert(parts, ps)
			if #parts >= DISPLAY_MAX_PARTS then
				break
			end
		end
	end
	local copy = table.clone(spec)
	copy.Parts = parts
	return copy
end

----------------------------------------------------------------------
-- Галерея
----------------------------------------------------------------------

-- Лучший надетый фульгурит, а если надетых нет — лучший из всех (бонус растёт с редкостью)
local function bestRecord(d: Data): FulgRecord?
	local best: FulgRecord? = nil
	local bestScore = -1
	local function consider(f: FulgRecord)
		local score = Economy.fulgRecordBonus(f)
		local cur = best
		if score > bestScore or (score == bestScore and cur ~= nil and f.Serial < cur.Serial) then
			best = f
			bestScore = score
		end
	end
	for _, id in d.EquippedFulgs do
		local f = PlayerData.findFulg(d, id)
		if f then
			consider(f)
		end
	end
	if best then
		return best
	end
	for _, f in d.Fulgs do
		consider(f)
	end
	return best
end

local function clearDisplay(ped: Pedestal)
	local old = ped.Display
	if old then
		old:Destroy()
	end
	ped.Display = nil
	ped.Key = ""
end

local function newLabel(parent: Instance, name: string, text: string, color: Color3, y: number, h: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, h)
	l.Position = UDim2.fromScale(0, y)
	l.FontFace = LABEL_FONT
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.TextStrokeColor3 = LABEL_STROKE
	l.TextStrokeTransparency = 0.15
	l.Parent = parent
	return l
end

-- Построить витрину: фульгурит на пьедестале + табличка над ним
local function buildDisplay(ped: Pedestal, player: Player, f: FulgRecord?)
	clearDisplay(ped)
	local folder = galleryFolder
	if not folder then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "Display_" .. ped.Index
	holder:SetAttribute("UserId", player.UserId)
	local top = ped.Marker.CFrame -- центр верхней грани, лицом к центру галереи
	local height = 0
	local line2 = "пока без фульгурита"
	local line2Color = DIM_TEXT
	if f then
		local spec = specOf(f)
		local mut: Fulgurite.MutId? = f.Mut :: any
		local glass = Fulgurite.glassColor(f.Color, mut)
		local model = Models.fulgurite(displaySpec(spec), glass)
		Models.setAnchored(model, true)
		local _, size = model:GetBoundingBox()
		if size.Y > 0 then
			local footprint = math.max(size.X, size.Z, 1e-3)
			local k = DISPLAY_HEIGHT / size.Y
			k = math.max(k, DISPLAY_MIN_HEIGHT / size.Y)
			k = math.min(k, DISPLAY_MAX_FOOTPRINT / footprint) -- ширина важнее высоты: соседи рядом
			model:ScaleTo(k)
			height = size.Y * k
		end
		model:PivotTo(top)
		model.Parent = holder
		local root = model.PrimaryPart
		local rank = Pets.Rarities[spec.Rarity].Rank
		if root and rank >= DISPLAY_LIGHT_RANK then
			-- мягкое свечение витрины (без теней) — только у самых редких
			local light = Instance.new("PointLight")
			light.Color = glass
			light.Range = 3 + rank * 1.2
			light.Brightness = 0.6 + rank * 0.3
			light.Shadows = false
			light.Parent = root
		end
		local rarity = Pets.Rarities[spec.Rarity]
		line2 = rarity.Name .. " · " .. serialText(f.Serial)
		line2Color = rarity.Color
	end

	-- табличка: невидимая деталь над верхушкой с BillboardGui
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	local stagger = if ped.Index % 2 == 0 then LABEL_STAGGER else 0
	anchor.CFrame = top + Vector3.new(0, height + LABEL_GAP + stagger, 0)
	anchor.Parent = holder
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = LABEL_SIZE
	gui.LightInfluence = 0
	gui.MaxDistance = LABEL_DISTANCE
	gui.ResetOnSpawn = false
	gui.Parent = anchor
	newLabel(gui, "PlayerName", player.DisplayName, Color3.new(1, 1, 1), 0, 0.55)
	newLabel(gui, "Info", line2, line2Color, 0.55, 0.45)

	holder.Parent = folder
	ped.Display = holder
end

-- Перестроить пьедестал игрока, если сменился лучший фульгурит
local function refreshPedestal(player: Player)
	local ped = byPlayer[player]
	local d = DataService.get(player)
	if not ped or not d then
		return
	end
	local f = bestRecord(d)
	local key = if f then string.format("%d:%d:%s:%s", f.Id, f.Seed, f.Color, f.Mut or "") else "none"
	if key == ped.Key and ped.Display then
		return
	end
	local ok, err = pcall(buildDisplay, ped, player, f)
	if not ok then
		warn("[FulguriteService] витрина " .. player.Name .. ": " .. tostring(err))
		return
	end
	ped.Key = key
end

-- Подпись набора фульгуритов: дешёвая проверка «что-то поменялось» на каждом DataService.Changed
local function signature(d: Data): string
	return d.NextFulgId .. ":" .. #d.Fulgs .. ":" .. table.concat(d.EquippedFulgs, ",")
end

local function assignPedestal(player: Player)
	if byPlayer[player] or #pedestals == 0 or player.Parent ~= Players then
		return
	end
	for _, ped in pedestals do
		if ped.Owner == nil then
			ped.Owner = player
			byPlayer[player] = ped
			local d = DataService.get(player)
			signatures[player] = if d then signature(d) else ""
			refreshPedestal(player)
			return
		end
	end
end

local function releasePedestal(player: Player)
	local ped = byPlayer[player]
	byPlayer[player] = nil
	signatures[player] = nil
	if ped then
		ped.Owner = nil
		clearDisplay(ped)
		-- освободилось место: отдать его тому, кому пьедестала не хватило (когда ушедший уже вышел)
		task.defer(function()
			for _, p in Players:GetPlayers() do
				if p ~= player and not byPlayer[p] and DataService.get(p) then
					assignPedestal(p)
				end
			end
		end)
	end
end

local function findPedestals()
	local map = Workspace:FindFirstChild("Map")
	local markers = if map then map:FindFirstChild("Markers") else nil
	if not map or not markers then
		return
	end
	local i = 1
	while true do
		local m = markers:FindFirstChild("Pedestal_" .. i)
		if not m then
			break
		end
		if m:IsA("BasePart") then
			table.insert(pedestals, { Index = i, Marker = m, Owner = nil, Display = nil, Key = "" })
		end
		i += 1
	end
	if #pedestals > 0 then
		local folder = Instance.new("Folder")
		folder.Name = "GalleryDisplays"
		folder.Parent = map
		galleryFolder = folder
	end
end

----------------------------------------------------------------------
-- Выпадение
----------------------------------------------------------------------

-- Разбить фульгурит в осколки (по редкости × ценность осколков острова, где он найден). Возвращает осколки.
local function shatter(player: Player, f: FulgRecord): number
	local spec = specOf(f)
	local zone = math.clamp(f.Zone, 1, #Config.Zones)
	local shards = (SHATTER_SHARDS[spec.Rarity] or 0) * Config.Zones[zone].ShardValue
	local id = f.Id
	local ok = DataService.update(player, function(data)
		local e = table.find(data.EquippedFulgs, id)
		if e then
			table.remove(data.EquippedFulgs, e)
		end
		for i, rec in data.Fulgs do
			if rec.Id == id then
				table.remove(data.Fulgs, i)
				break
			end
		end
	end)
	if not ok then
		return 0
	end
	fullNotified[player] = nil
	return EconomyService.grantShards(player, shards)
end

-- Коллекция полна, а фульгурит гарантированный: разбить самый простой ненадетый
-- (при равной редкости — самый новый, старые номера ценнее). Все надеты — ничего не трогаем.
local function makeRoom(player: Player, d: Data)
	local worst: FulgRecord? = nil
	local worstBonus = math.huge
	for _, f in d.Fulgs do
		if not table.find(d.EquippedFulgs, f.Id) then
			local bonus = Economy.fulgRecordBonus(f)
			local cur = worst
			if bonus < worstBonus or (bonus == worstBonus and cur ~= nil and f.Serial > cur.Serial) then
				worst = f
				worstBonus = bonus
			end
		end
	end
	local f = worst
	if not f then
		return
	end
	local title = Fulgurite.title(specOf(f), f.Mut :: any)
	local shards = shatter(player, f)
	notify(player, string.format("Коллекция полна: %s %s разбит, +%d 💎 — место для нового!", title, serialText(f.Serial), shards), "info")
end

-- Гарантированный фульгурит (без броска шанса): Радужная молния, Перун.
-- Возвращает запись или nil (коллекция полна и фульгурит обычный, данные не загружены, неверный цвет).
function FulguriteService.grant(player: Player, color: Config.ColorId, zone: number, tag: string?): FulgRecord?
	local d = DataService.get(player)
	if not d or not isColor(color) then
		return nil
	end
	if #d.Fulgs >= Fulgurite.MaxInventory then
		local guaranteed = tag == "rainbow" or tag == "perun" or Config.Colors[color].FulgChance >= 1
		if not guaranteed then
			if not fullNotified[player] then
				fullNotified[player] = true
				notify(player, "Коллекция фульгуритов полна — разбей лишние в «Коллекции»", "bad")
			end
			return nil
		end
		makeRoom(player, d)
	end
	fullNotified[player] = nil
	local z = if ServerLogic.isInteger(zone) then math.clamp(zone, 1, #Config.Zones) else 1
	local serial = d.NextFulgId
	local seed = Prng.hash(player.UserId, serial)
	local mut = Fulgurite.rollMutation(z, math.random(), color)
	local rec: FulgRecord = { Id = serial, Seed = seed, Color = color, Mut = mut, Serial = serial, Zone = z }
	local spec = Fulgurite.generate(seed, color, mut)
	local stored = DataService.update(player, function(data)
		data.NextFulgId = math.max(data.NextFulgId, serial) + 1
		table.insert(data.Fulgs, rec)
		-- свободное место — сразу надеть (бонус и пьедестал без лишних кнопок)
		if #data.EquippedFulgs < Fulgurite.MaxEquipped then
			table.insert(data.EquippedFulgs, rec.Id)
		end
	end)
	if not stored then
		return nil
	end
	local rarity = Pets.Rarities[spec.Rarity]
	local title = Fulgurite.title(spec, mut)
	notify(player, string.format("🔮 %s %s — %s!", title, serialText(serial), rarity.Name), if rarity.Rank >= NOTIFY_RARE_RANK then "rare" else "good")
	-- у Радужной и Перуна свои баннеры (EventService) — второй не нужен
	local banner = bannerRemote
	local eventDrop = tag == "rainbow" or tag == "perun"
	if banner and rarity.Rank >= BANNER_RANK and not eventDrop then
		banner:FireAllClients(string.format("🔮 %s нашёл: %s %s!", player.DisplayName, title, serialText(serial)), spec.Rarity, rarity.Color)
	end
	return rec
end

-- Шанс фульгурита при ИДЕАЛЬНОЙ поимке (StrikeService.dropHook; радужная и чёрная — при любой поимке, шанс 100%).
-- Возвращает Id нового фульгурита.
function FulguriteService.tryDrop(player: Player, color: Config.ColorId, zone: number, tag: string?): number?
	local d = DataService.get(player)
	if not d or not isColor(color) then
		return nil
	end
	local luck = Economy.petBonuses(d).luck
	if not Fulgurite.rollDrop(color, math.random(), luck) then
		return nil
	end
	local rec = FulguriteService.grant(player, color, zone, tag)
	return if rec then rec.Id else nil
end

----------------------------------------------------------------------
-- Request
----------------------------------------------------------------------

local function fulgId(payload: any): number?
	if ServerLogic.isInteger(payload) then
		return payload
	end
	return nil
end

local function equipFulg(player: Player, payload: any): (boolean, any)
	local id = fulgId(payload)
	if not id then
		return false, NO_FULG
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not PlayerData.findFulg(d, id) then
		return false, NO_FULG
	end
	if table.find(d.EquippedFulgs, id) then
		return false, "Этот фульгурит уже надет"
	end
	if #d.EquippedFulgs >= Fulgurite.MaxEquipped then
		return false, string.format("Можно надеть только %d — сними другой", Fulgurite.MaxEquipped)
	end
	DataService.update(player, function(data)
		table.insert(data.EquippedFulgs, id)
	end)
	return true, id
end

local function unequipFulg(player: Player, payload: any): (boolean, any)
	local id = fulgId(payload)
	if not id then
		return false, NO_FULG
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not table.find(d.EquippedFulgs, id) then
		return false, "Этот фульгурит не надет"
	end
	DataService.update(player, function(data)
		local i = table.find(data.EquippedFulgs, id)
		if i then
			table.remove(data.EquippedFulgs, i)
		end
	end)
	return true, id
end

local function deleteFulg(player: Player, payload: any): (boolean, any)
	local id = fulgId(payload)
	if not id then
		return false, NO_FULG
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	local f = PlayerData.findFulg(d, id)
	if not f then
		return false, NO_FULG
	end
	return true, shatter(player, f)
end

----------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------

function FulguriteService.start()
	notifyRemote = Net.event("Notify")
	bannerRemote = Net.event("Banner")

	StrikeService.dropHook = FulguriteService.tryDrop

	RequestService.handle(Net.Actions.EquipFulg, equipFulg)
	RequestService.handle(Net.Actions.UnequipFulg, unequipFulg)
	RequestService.handle(Net.Actions.DeleteFulg, deleteFulg)

	findPedestals()

	DataService.Loaded:Connect(assignPedestal)
	DataService.Changed:Connect(function(player)
		local ped = byPlayer[player]
		local d = DataService.get(player)
		if not ped or not d then
			return
		end
		local sig = signature(d)
		if sig ~= signatures[player] then
			signatures[player] = sig
			refreshPedestal(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		releasePedestal(player)
		fullNotified[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			assignPedestal(player)
		end
	end
end

return FulguriteService
