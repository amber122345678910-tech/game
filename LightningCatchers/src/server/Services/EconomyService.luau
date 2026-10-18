--!strict
-- Банка и Вольты:
--  * addCharge — заряд за поимку с перегрузкой (Config.Zones[z].Overcharge, риск Strikes.overchargeRisk);
--  * сдача на подстанциях (проверка позиции раз в Config.Server.SellTick) и Тесла-дроном;
--  * множитель Вольт, доход в минуту (data.IncomeRate), атрибут JarFill;
--  * покупки через Request: BuyUpgrade, UnlockZone, BuyDrone, ToggleDrone, Rebirth, Teleport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Signal = require(Shared:WaitForChild("Signal"))
local Strikes = require(Shared:WaitForChild("Strikes"))
local Zones = require(Shared:WaitForChild("Zones"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local RequestService = require(script.Parent.RequestService)

type Data = PlayerData.Data

local EconomyService = {}

-- (игрок, Вольт получено, заполнение банки 0..1.5 на момент сдачи)
EconomyService.Sold = Signal.new() :: Signal.Signal<Player, number, number>
-- (игрок, что куплено, новое значение): "Rod"/"Jar"/"Boots"/"Magnet"/"Insulation" -> уровень,
-- "Zone" -> номер острова, "Drone" -> 1, "Rebirth" -> число перезапусков
EconomyService.Purchased = Signal.new() :: Signal.Signal<Player, string, number>

local NO_VOLTS = "Не хватает Вольт"
local LOADING = "Данные ещё загружаются"

type State = {
	LastSell: number, -- os.clock последней сдачи
	LastCatch: number, -- os.clock последнего заряда (для дрона на островах с перегрузкой)
	DroneBusy: boolean,
	DroneToken: number,
	Earned: number, -- Вольт с продаж в текущем окне дохода
	Active: boolean, -- был на острове в текущем окне
	WindowStart: number,
	LastFullNotify: number,
}

type Pad = { Pos: Vector3, Reach: number }

local states: { [Player]: State } = {}
local pads: { Pad } = {}
local cityBoostProvider: (() -> boolean)? = nil
local notifyRemote: RemoteEvent? = nil
local effectRemote: RemoteEvent? = nil
local bannerRemote: RemoteEvent? = nil

----------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------

local function notify(player: Player, text: string, kind: string)
	local r = notifyRemote
	if r then
		r:FireClient(player, text, kind)
	end
end

local function effect(player: Player, msg: Net.EffectMsg)
	local r = effectRemote
	if r then
		r:FireClient(player, msg)
	end
end

local function upgradeLevel(d: Data, id: Config.UpgradeId): number
	local v = (d.Upgrades :: any)[id]
	return if typeof(v) == "number" then v else 0
end

local function setUpgradeLevel(d: Data, id: Config.UpgradeId, level: number)
	(d.Upgrades :: any)[id] = level
end

local function capacityOf(d: Data): number
	return Economy.jarCapacity(d.Upgrades.Jar)
end

local function setJarFill(player: Player, charge: number, capacity: number)
	local fill = if capacity > 0 then math.clamp(charge / capacity, 0, Config.Overcharge.MaxFill) else 0
	player:SetAttribute(Net.PlayerAttrs.JarFill, math.floor(fill * 1000 + 0.5) / 1000)
end

local function refreshJarFill(player: Player)
	local d = DataService.get(player)
	if d then
		setJarFill(player, d.Charge, capacityOf(d))
	end
end

local function droneActive(d: Data): boolean
	return d.Drone and d.DroneOn
end

local function zoneAllowsOvercharge(zone: number): boolean
	local def = if zone >= 1 and zone <= #Config.Zones then Config.Zones[zone] else nil
	return def ~= nil and def.Overcharge
end

----------------------------------------------------------------------
-- Состояние игроков
----------------------------------------------------------------------

local function ensureState(player: Player): State?
	local st = states[player]
	if st then
		return st
	end
	if player.Parent ~= Players or not DataService.get(player) then
		return nil
	end
	local clock = os.clock()
	st = {
		LastSell = -math.huge,
		LastCatch = clock,
		DroneBusy = false,
		DroneToken = 0,
		Earned = 0,
		Active = false,
		WindowStart = clock,
		LastFullNotify = -math.huge,
	}
	states[player] = st
	refreshJarFill(player)
	return st
end

----------------------------------------------------------------------
-- Банка
----------------------------------------------------------------------

function EconomyService.capacity(player: Player): number
	local d = DataService.get(player)
	return if d then capacityOf(d) else Economy.jarCapacity(0)
end

function EconomyService.charge(player: Player): number
	local d = DataService.get(player)
	return if d then d.Charge else 0
end

-- Заполнение банки (1 = полная, до Config.Overcharge.MaxFill с перегрузкой)
function EconomyService.fill(player: Player): number
	local d = DataService.get(player)
	if not d then
		return 0
	end
	return d.Charge / capacityOf(d)
end

-- Добавить заряд за поимку на острове zone.
-- Возвращает (поместилось, лопнула ли банка, сколько потеряно: не влезло + сгорело при "лопнула").
-- safe = true — без риска лопнуть (бонус, который игрок не "ловил" сам, например цепная молния).
function EconomyService.addCharge(player: Player, amount: number, zone: number, safe: boolean?): (number, boolean, number)
	local d = DataService.get(player)
	local st = ensureState(player)
	if not d or not st or not ServerLogic.isFinite(amount) or amount <= 0 then
		return 0, false, 0
	end
	local capacity = capacityOf(d)
	local allowOver = zoneAllowsOvercharge(zone)
	local insulation = d.Upgrades.Insulation
	local before = d.Charge
	local r = ServerLogic.addToJar(before, amount, capacity, allowOver, Config.Overcharge.MaxFill, function(fill: number): number
		return if safe then 0 else Strikes.overchargeRisk(fill, insulation)
	end, math.random(), Config.Overcharge.BurstKeep)

	local stored = DataService.update(player, function(data)
		data.Charge = r.After
	end)
	if not stored then
		return 0, false, 0 -- игрок уже выходит
	end
	st.LastCatch = os.clock()
	setJarFill(player, r.After, capacity)

	-- напоминание сдать банку (дрон сам справится — тогда молчим)
	local clamped = amount - r.Added > 1e-9
	local becameFull = not allowOver and before < capacity and r.After >= capacity
	if (becameFull or clamped) and not droneActive(d) then
		local clock = os.clock()
		if becameFull or clock - st.LastFullNotify >= Config.Server.JarFullNotifyEvery then
			st.LastFullNotify = clock
			notify(player, "Банка полна! Сдай заряд ⚡", "info")
		end
	end
	return r.Added, r.Burst, r.Lost
end

-- Множитель Вольт при сдаче (перезапуски, питомцы, фульгуриты, Молниедекс, друзья, город, бусты)
function EconomyService.multiplierFor(player: Player): number
	local d = DataService.get(player)
	if not d then
		return 1
	end
	local friendsAttr = player:GetAttribute(Net.PlayerAttrs.FriendCount)
	local friends = if typeof(friendsAttr) == "number" then friendsAttr else 0
	local city = false
	local provider = cityBoostProvider
	if provider then
		local ok, result = pcall(provider)
		city = ok and result == true
	end
	return Economy.multiplier(d, { friends = friends, cityBoost = city, now = os.time() })
end

-- CityService сообщает, сияет ли город (×2 Вольт всем)
function EconomyService.setCityBoostProvider(fn: (() -> boolean)?)
	cityBoostProvider = fn
end

-- Сдать банку. source: "pad" (подстанция) или "drone". pos — где (для эффекта у клиента).
function EconomyService.sell(player: Player, source: string?, pos: Vector3?): number
	local d = DataService.get(player)
	local st = ensureState(player)
	if not d or not st or d.Charge <= 0 then
		return 0
	end
	local capacity = capacityOf(d)
	local charge = d.Charge
	local fill = math.min(charge / capacity, Config.Overcharge.MaxFill)
	local volts = Economy.sellValue(charge, capacity, EconomyService.multiplierFor(player))
	local ok = DataService.update(player, function(data)
		data.Charge = 0
		data.Volts += volts
		data.TotalVolts += volts
		data.Stats.Sells += 1
	end)
	if not ok then
		return 0
	end
	st.LastSell = os.clock()
	st.Earned += volts
	setJarFill(player, 0, capacity)
	local isDrone = source == "drone"
	effect(player, {
		Kind = if isDrone then "drone" else "sell",
		Text = if isDrone then "sold" else nil,
		Value = volts,
		UserId = player.UserId,
		Pos = pos,
	})
	EconomyService.Sold:Fire(player, volts, fill)
	return volts
end

-- Начислить Вольты (награды). Учитываются в TotalVolts, но не в доходе в минуту.
function EconomyService.grantVolts(player: Player, amount: number, reason: string?): number
	if not ServerLogic.isFinite(amount) or amount <= 0 then
		return 0
	end
	local volts = math.floor(amount + 0.5)
	if volts <= 0 then
		return 0
	end
	local ok = DataService.update(player, function(d)
		d.Volts += volts
		d.TotalVolts += volts
	end)
	return if ok then volts else 0
end

-- Начислить осколки (дробное количество округляется)
function EconomyService.grantShards(player: Player, amount: number): number
	if not ServerLogic.isFinite(amount) or amount <= 0 then
		return 0
	end
	local shards = math.floor(amount + 0.5)
	if shards <= 0 then
		return 0
	end
	local ok = DataService.update(player, function(d)
		d.Shards += shards
	end)
	return if ok then shards else 0
end

----------------------------------------------------------------------
-- Подстанции, дрон, доход
----------------------------------------------------------------------

local function collectPads()
	table.clear(pads)
	local map = Workspace:FindFirstChild("Map")
	local markers = if map then map:FindFirstChild("Markers") else nil
	-- SellPad_0 — кольцо вокруг Тесла-башни в хабе, SellPad_1..5 — подстанции островов.
	-- Если меток на карте нет — берём те же точки из Zones (по ним карта и строится).
	local function add(name: string, fallback: Vector3, radius: number)
		local marker = if markers then markers:FindFirstChild(name) else nil
		local pos = if marker and marker:IsA("BasePart") then marker.Position else fallback
		table.insert(pads, { Pos = pos, Reach = radius + Config.Server.SellPadSlack })
	end
	add("SellPad_0", Zones.Hub.Tower, Zones.HubSellRadius)
	for n, geo in Zones.Geo do
		add("SellPad_" .. n, geo.SellPad, Zones.SellPadRadius)
	end
end

local function padNear(pos: Vector3): Pad?
	for _, pad in pads do
		if ServerLogic.inRing(pos, pad.Pos, pad.Reach, Config.Server.SellPadHeight) then
			return pad
		end
	end
	return nil
end

-- Дрон сдаёт банку, когда она полная: сразу на островах без перегрузки,
-- а там, где перегрузка разрешена, — если игрок DroneIdle секунд ничего не ловил
-- (значит, он не перегружает банку нарочно) или банка уже на пределе перегрузки.
-- Банка «улетает» на TripTime: пока дрон в пути, новый заряд в полную банку не влезает
-- (как в симуляции баланса).
local function droneCheck(player: Player, st: State, d: Data)
	if not droneActive(d) or st.DroneBusy then
		return
	end
	local capacity = capacityOf(d)
	if d.Charge < capacity then
		return
	end
	if zoneAllowsOvercharge(PlayerService.getZone(player)) then
		local atLimit = d.Charge >= capacity * Config.Overcharge.MaxFill - 1e-6
		if not atLimit and os.clock() - st.LastCatch < Config.Server.DroneIdle then
			return
		end
	end
	st.DroneBusy = true
	st.DroneToken += 1
	local token = st.DroneToken
	effect(player, { Kind = "drone", Text = "depart", Value = Config.Drone.TripTime, UserId = player.UserId })
	task.delay(Config.Drone.TripTime, function()
		if states[player] ~= st or st.DroneToken ~= token then
			return
		end
		st.DroneBusy = false
		local data = DataService.get(player)
		if not data or not data.Drone then
			return
		end
		if EconomyService.sell(player, "drone", nil) <= 0 then
			-- банку успели сдать сами: дрон вернулся пустым (клиенту — чтобы закончить анимацию)
			effect(player, { Kind = "drone", Text = "sold", Value = 0, UserId = player.UserId })
		end
	end)
end

local function updateIncome(player: Player, st: State)
	local area = PlayerService.getArea(player)
	if area ~= nil and area >= 1 then
		st.Active = true
	end
	local clock = os.clock()
	if clock - st.WindowStart < Config.Server.IncomeWindow then
		return
	end
	local earned = st.Earned
	if earned > 0 or st.Active then
		DataService.update(player, function(d)
			d.IncomeRate = Economy.updateIncomeRate(d.IncomeRate, earned)
		end)
	end
	st.Earned = 0
	st.Active = false
	st.WindowStart = clock
end

local function tickPlayer(player: Player, st: State)
	local d = DataService.get(player)
	if not d then
		return
	end
	if d.Charge > 0 and os.clock() - st.LastSell >= Config.Server.SellCooldown then
		local root = PlayerService.getRoot(player)
		local pad = if root then padNear(root.Position) else nil
		if pad then
			EconomyService.sell(player, "pad", pad.Pos)
		end
	end
	droneCheck(player, st, d)
	updateIncome(player, st)
end

----------------------------------------------------------------------
-- Покупки (Request)
----------------------------------------------------------------------

local function buyUpgrade(player: Player, payload: any): (boolean, any)
	local def: Config.UpgradeDef? = if typeof(payload) == "string" then (Config.Upgrades :: any)[payload] else nil
	if not def then
		return false, "Неизвестное улучшение"
	end
	local id = def.Id
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	local level = upgradeLevel(d, id)
	local cost = Economy.upgradeCost(id, level)
	if not cost then
		return false, "Уже максимальный уровень"
	end
	if d.Volts < cost then
		return false, NO_VOLTS
	end
	local newLevel = level + 1
	DataService.update(player, function(data)
		data.Volts -= cost
		setUpgradeLevel(data, id, newLevel)
	end)
	PlayerService.refreshStats(player) -- скорость, RodTier
	refreshJarFill(player) -- вместимость могла вырасти
	effect(player, { Kind = "levelUp", Text = id, Value = newLevel, UserId = player.UserId })
	EconomyService.Purchased:Fire(player, id, newLevel)
	return true, newLevel
end

local function unlockZone(player: Player, payload: any): (boolean, any)
	if not ServerLogic.isInteger(payload) or payload < 1 or payload > #Config.Zones then
		return false, "Нет такого острова"
	end
	local zone: number = payload
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if zone <= d.Zone then
		return false, "Остров уже открыт"
	end
	if zone ~= d.Zone + 1 then
		return false, "Сначала открой предыдущий остров"
	end
	local cost = Economy.zoneCost(zone)
	if d.Volts < cost then
		return false, NO_VOLTS
	end
	DataService.update(player, function(data)
		data.Volts -= cost
		data.Zone = zone
	end)
	effect(player, { Kind = "zoneUnlocked", Zone = zone, UserId = player.UserId, Text = Config.Zones[zone].Name })
	EconomyService.Purchased:Fire(player, "Zone", zone)
	return true, zone
end

local function buyDrone(player: Player, _payload: any): (boolean, any)
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if d.Drone then
		return false, "Дрон уже куплен"
	end
	if d.Zone < Config.Drone.FromZone then
		return false, string.format("Дрон откроется с острова «%s»", Config.Zones[Config.Drone.FromZone].Name)
	end
	if d.Volts < Config.Drone.Cost then
		return false, NO_VOLTS
	end
	DataService.update(player, function(data)
		data.Volts -= Config.Drone.Cost
		data.Drone = true
		data.DroneOn = true
	end)
	effect(player, { Kind = "levelUp", Text = "Drone", Value = 1, UserId = player.UserId })
	EconomyService.Purchased:Fire(player, "Drone", 1)
	return true, true
end

local function toggleDrone(player: Player, payload: any): (boolean, any)
	if typeof(payload) ~= "boolean" then
		return false, "Ошибка, попробуй ещё раз"
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not d.Drone then
		return false, "Сначала купи дрон"
	end
	local on: boolean = payload
	DataService.update(player, function(data)
		data.DroneOn = on
	end)
	return true, on
end

local function rebirth(player: Player, _payload: any): (boolean, any)
	local d = DataService.get(player)
	local st = ensureState(player)
	if not d or not st then
		return false, LOADING
	end
	if d.Zone < Config.Rebirth.RequiredZone then
		return false, string.format("Сначала открой остров «%s»", Config.Zones[Config.Rebirth.RequiredZone].Name)
	end
	if not Economy.canRebirth(d) then
		return false, string.format("Нужно %s ⚡", Format.short(Economy.rebirthCost(d.Rebirths)))
	end
	local rebirths = d.Rebirths + 1
	DataService.update(player, function(data)
		-- сбрасываем прогресс забега; питомцы, фульгуриты, Молниедекс, осколки и рекорды остаются
		data.Volts = 0
		data.Charge = 0
		for id in Config.Upgrades do
			setUpgradeLevel(data, id, 0)
		end
		data.Zone = 1
		data.LastZone = 1
		data.Drone = false
		data.DroneOn = true
		data.Rebirths = rebirths
	end)
	-- дрон в пути больше не прилетит
	st.DroneToken += 1
	st.DroneBusy = false
	setJarFill(player, 0, capacityOf(d))
	PlayerService.refreshStats(player)
	PlayerService.teleport(player, 1)
	local mult = string.sub(Format.mult(Economy.rebirthMult(rebirths)), 2)
	local banner = bannerRemote
	if banner then
		banner:FireAllClients(string.format("♻ Генератор перезапущен! %s теперь ×%s", player.DisplayName, mult), "rare", Config.Colors.gold.Color)
	end
	effect(player, { Kind = "rebirth", Value = rebirths, UserId = player.UserId })
	EconomyService.Purchased:Fire(player, "Rebirth", rebirths)
	return true, rebirths
end

local function teleport(player: Player, payload: any): (boolean, any)
	local ok, err = PlayerService.teleport(player, payload)
	if not ok then
		return false, err
	end
	return true, payload
end

----------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------

function EconomyService.start()
	notifyRemote = Net.event("Notify")
	effectRemote = Net.event("Effect")
	bannerRemote = Net.event("Banner")
	collectPads()

	RequestService.handle(Net.Actions.BuyUpgrade, buyUpgrade)
	RequestService.handle(Net.Actions.UnlockZone, unlockZone)
	RequestService.handle(Net.Actions.BuyDrone, buyDrone)
	RequestService.handle(Net.Actions.ToggleDrone, toggleDrone)
	RequestService.handle(Net.Actions.Rebirth, rebirth)
	RequestService.handle(Net.Actions.Teleport, teleport)

	DataService.Loaded:Connect(function(player)
		ensureState(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		ensureState(player) -- данные могли загрузиться раньше этого обработчика
	end)
	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		if st then
			st.DroneToken += 1
		end
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		ensureState(player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Server.SellTick)
			for player, st in states do
				local ok, err = pcall(tickPlayer, player, st)
				if not ok then
					warn("[EconomyService] " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return EconomyService
