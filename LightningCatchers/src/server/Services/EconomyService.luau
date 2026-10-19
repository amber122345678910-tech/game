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
local Loc = require(Shared:WaitForChild("Loc"))
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

local NO_VOLTS = Loc.msg("Не хватает Вольт")
local LOADING = Loc.msg("Данные ещё загружаются")

type State = {
	LastSell: number, -- os.clock последней сдачи
	DroneBusy: boolean,
	DroneToken: number,
	Cargo: number, -- заряд, который дрон везёт на подстанцию (банка в это время пуста)
	CargoCap: number, -- вместимость банки в момент вылета (для перегрузочной части)
	Earned: number, -- Вольт с продаж в текущем окне дохода
	Active: boolean, -- был на острове в текущем окне
	WindowStart: number,
	LastFullNotify: number,
	LastTeleport: number, -- os.clock последнего телепорта по запросу
}

type Pad = { Pos: Vector3, Reach: number }
-- груз дрона: заряд и вместимость банки в момент вылета
type Cargo = { Charge: number, Cap: number }

local states: { [Player]: State } = {}
-- груз дрона игрока, который вышел, пока дрон летел: дрон сдаст его при последнем сохранении
local orphanCargo: { [Player]: { Cargo } } = {}
local pads: { Pad } = {}
local cityBoostProvider: (() -> boolean)? = nil
local notifyRemote: RemoteEvent? = nil
local effectRemote: RemoteEvent? = nil
local bannerRemote: RemoteEvent? = nil

----------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------

local function notify(player: Player, text: Loc.Msg | string, kind: string)
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

-- Тот же эффект — другим игрокам на этом острове поблизости (видят, как кто-то сдаёт банку)
local NEARBY_EFFECT_RADIUS = 160
local function effectNearby(player: Player, msg: Net.EffectMsg)
	local r = effectRemote
	local zone = player:GetAttribute("Zone")
	local root = PlayerService.getRoot(player)
	if not r or not root or typeof(zone) ~= "number" then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("Zone") == zone then
			local otherRoot = PlayerService.getRoot(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= NEARBY_EFFECT_RADIUS then
				r:FireClient(other, msg)
			end
		end
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
		DroneBusy = false,
		DroneToken = 0,
		Cargo = 0,
		CargoCap = 0,
		Earned = 0,
		Active = false,
		WindowStart = clock,
		LastFullNotify = -math.huge,
		LastTeleport = -math.huge,
	}
	states[player] = st
	-- заряд из старых сохранений не больше полной перегрузки (иначе банка «на 200%» и лишние Вольты)
	local d = DataService.get(player)
	if d then
		local maxCharge = Economy.maxCharge(capacityOf(d), true)
		if d.Charge > maxCharge then
			DataService.update(player, function(data)
				data.Charge = maxCharge
			end)
		end
	end
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
-- С включённым дроном банка не перегружается: дрон забирает её ровно полной
-- (хочешь перегружать — выключи дрон).
function EconomyService.addCharge(player: Player, amount: number, zone: number, safe: boolean?): (number, boolean, number)
	local d = DataService.get(player)
	local st = ensureState(player)
	if not d or not st or not ServerLogic.isFinite(amount) or amount <= 0 then
		return 0, false, 0
	end
	local capacity = capacityOf(d)
	local allowOver = zoneAllowsOvercharge(zone) and not droneActive(d)
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
	setJarFill(player, r.After, capacity)

	-- напоминание сдать банку (дрон сам справится — тогда молчим)
	local clamped = amount - r.Added > 1e-9
	local becameFull = not allowOver and before < capacity and r.After >= capacity
	if (becameFull or clamped) and not droneActive(d) then
		local clock = os.clock()
		if becameFull or clock - st.LastFullNotify >= Config.Server.JarFullNotifyEvery then
			st.LastFullNotify = clock
			notify(player, Loc.msg("Банка полна! Сдай заряд ⚡"), "info")
		end
	end
	return r.Added, r.Burst, r.Lost
end

-- Множитель Вольт при сдаче (перезапуски, питомцы, фульгуриты, Молниедекс, друзья, город, бусты)
local function multiplierOf(player: Player, d: Data): number
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

function EconomyService.multiplierFor(player: Player): number
	local d = DataService.get(player)
	if not d then
		return 1
	end
	return multiplierOf(player, d)
end

-- CityService сообщает, сияет ли город (×2 Вольт всем)
function EconomyService.setCityBoostProvider(fn: (() -> boolean)?)
	cityBoostProvider = fn
end

-- Вольты за заряд charge из банки вместимостью capacity (перегрузочная часть дороже).
-- Подстанция берёт заряд из банки; дрон (isDrone) сдаёт свой груз и банку не трогает.
local function payout(player: Player, st: State, charge: number, capacity: number, isDrone: boolean, pos: Vector3?): number
	if charge <= 0 or capacity <= 0 then
		return 0
	end
	local fill = math.min(charge / capacity, Config.Overcharge.MaxFill)
	local volts = Economy.sellValue(charge, capacity, EconomyService.multiplierFor(player))
	local ok = DataService.update(player, function(data)
		if not isDrone then
			data.Charge = 0
		end
		data.Volts += volts
		data.TotalVolts += volts
		data.Stats.Sells += 1
	end)
	if not ok then
		return 0
	end
	st.LastSell = os.clock()
	st.Earned += volts
	if not isDrone then
		setJarFill(player, 0, capacity)
	end
	local sellMsg: Net.EffectMsg = {
		Kind = if isDrone then "drone" else "sell",
		Text = if isDrone then "sold" else nil,
		Value = volts,
		UserId = player.UserId,
		Pos = pos,
	}
	effect(player, sellMsg)
	if not isDrone then
		effectNearby(player, sellMsg)
	end
	EconomyService.Sold:Fire(player, volts, fill)
	return volts
end

-- Сдать банку на подстанции. pos — где (для эффекта у клиента).
function EconomyService.sell(player: Player, _source: string?, pos: Vector3?): number
	local d = DataService.get(player)
	local st = ensureState(player)
	if not d or not st or d.Charge <= 0 then
		return 0
	end
	return payout(player, st, d.Charge, capacityOf(d), false, pos)
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

-- Дрон на любом острове: как только банка полная, сразу забирает весь заряд с собой
-- (банка пустеет — можно ловить дальше без риска), через TripTime сдаёт груз по тем же правилам,
-- что и подстанция. Перегрузочная часть бывает, только если банку перегрузили с выключенным дроном.
local function droneCheck(player: Player, st: State, d: Data)
	if not droneActive(d) or st.DroneBusy then
		return
	end
	local capacity = capacityOf(d)
	local cargo = d.Charge
	if cargo < capacity then
		return
	end
	local taken = DataService.update(player, function(data)
		data.Charge = 0
	end)
	if not taken then
		return
	end
	setJarFill(player, 0, capacity)
	st.DroneBusy = true
	st.Cargo = cargo
	st.CargoCap = capacity
	st.DroneToken += 1
	local token = st.DroneToken
	effect(player, { Kind = "drone", Text = "depart", Value = Config.Drone.TripTime, UserId = player.UserId })
	task.delay(Config.Drone.TripTime, function()
		if states[player] ~= st or st.DroneToken ~= token then
			return
		end
		local carried, cap = st.Cargo, st.CargoCap
		st.DroneBusy = false
		st.Cargo = 0
		if payout(player, st, carried, cap, true, nil) <= 0 then
			-- груз не сдался (данные уже не пишутся): клиенту — чтобы закончить анимацию
			effect(player, { Kind = "drone", Text = "sold", Value = 0, UserId = player.UserId })
		end
	end)
end

-- Последнее сохранение игрока, который вышел, пока дрон летел: дрон сдаёт груз сразу, по тем же правилам,
-- что и при прилёте (Вольты, а не обратно в банку — иначе банка переполнится сверх перегрузки)
local function returnCargo(player: Player, d: Data, final: boolean)
	if not final then
		return
	end
	local st = states[player]
	local list = orphanCargo[player] or {}
	orphanCargo[player] = nil
	if st and st.Cargo > 0 then
		table.insert(list, { Charge = st.Cargo, Cap = st.CargoCap })
		st.Cargo = 0
		st.DroneBusy = false
		st.DroneToken += 1
	end
	if #list == 0 then
		return
	end
	local mult = multiplierOf(player, d)
	for _, cargo in list do
		local cap = if cargo.Cap > 0 then cargo.Cap else capacityOf(d)
		local volts = Economy.sellValue(cargo.Charge, cap, mult)
		d.Volts += volts
		d.TotalVolts += volts
	end
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
		return false, Loc.msg("Неизвестное улучшение")
	end
	local id = def.Id
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	local level = upgradeLevel(d, id)
	local cost = Economy.upgradeCost(id, level)
	if not cost then
		return false, Loc.msg("Уже максимальный уровень")
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
		return false, Loc.msg("Нет такого острова")
	end
	local zone: number = payload
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if zone <= d.Zone then
		return false, Loc.msg("Остров уже открыт")
	end
	if zone ~= d.Zone + 1 then
		return false, Loc.msg("Сначала открой предыдущий остров")
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
		return false, Loc.msg("Дрон уже куплен")
	end
	if d.Zone < Config.Drone.FromZone then
		return false, Loc.msg("Дрон откроется с острова «%s»", Config.Zones[Config.Drone.FromZone].Name)
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
		return false, RequestService.ErrorText
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not d.Drone then
		return false, Loc.msg("Сначала купи дрон")
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
		return false, Loc.msg("Сначала открой остров «%s»", Config.Zones[Config.Rebirth.RequiredZone].Name)
	end
	if not Economy.canRebirth(d) then
		return false, Loc.msg("Нужно %s ⚡", Format.short(Economy.rebirthCost(d.Rebirths)))
	end
	local rebirths = d.Rebirths + 1
	DataService.update(player, function(data)
		-- сбрасываем прогресс забега; питомцы, фульгуриты, Молниедекс, осколки, рекорды и Тесла-дрон остаются.
		-- Доход в минуту — тоже с нуля: награды «N минут дохода» считаются от минимума, пока не начнёшь сдавать банки
		data.Volts = 0
		data.Charge = 0
		for id in Config.Upgrades do
			setUpgradeLevel(data, id, 0)
		end
		data.Zone = 1
		data.LastZone = 1
		data.IncomeRate = 0
		data.Rebirths = rebirths
	end)
	-- дрон в пути больше не прилетит (его груз сгорает вместе с Вольтами), окно дохода — заново
	st.DroneToken += 1
	st.DroneBusy = false
	st.Cargo = 0
	st.Earned = 0
	st.Active = false
	st.WindowStart = os.clock()
	setJarFill(player, 0, capacityOf(d))
	PlayerService.refreshStats(player)
	PlayerService.teleport(player, 1)
	local mult = string.sub(Format.mult(Economy.rebirthMult(rebirths)), 2)
	local banner = bannerRemote
	if banner then
		banner:FireAllClients(Loc.msg("♻ Генератор перезапущен! %s теперь ×%s", player.DisplayName, mult), "rare", Config.Colors.gold.Color)
	end
	effect(player, { Kind = "rebirth", Value = rebirths, UserId = player.UserId })
	EconomyService.Purchased:Fire(player, "Rebirth", rebirths)
	return true, rebirths
end

local function teleport(player: Player, payload: any): (boolean, any)
	local st = ensureState(player)
	if not st then
		return false, LOADING
	end
	-- уже стоишь там (на мосту или в пустоте — можно)
	if ServerLogic.isInteger(payload) and payload == PlayerService.getArea(player) then
		return false, if payload == 0 then Loc.msg("Ты уже в городе") else Loc.msg("Ты уже на этом острове")
	end
	local left = Config.Server.TeleportCooldown - (os.clock() - st.LastTeleport)
	if left > 0 then
		return false, Loc.msg("Телепорт заряжается: ещё %d с", math.ceil(left))
	end
	local ok, err = PlayerService.teleport(player, payload)
	if not ok then
		return false, err
	end
	st.LastTeleport = os.clock()
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

	DataService.addBeforeSave(returnCargo)
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
			if st.Cargo > 0 then
				-- последнее сохранение могло ещё не начаться: груз сдаст returnCargo
				local list = orphanCargo[player] or {}
				table.insert(list, { Charge = st.Cargo, Cap = st.CargoCap })
				orphanCargo[player] = list
				st.Cargo = 0
				task.delay(60, function()
					orphanCargo[player] = nil
				end)
			end
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
