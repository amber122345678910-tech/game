--!strict
-- Питомцы-искрята на сервере:
--  * Request: Hatch (кокон за осколки: остров, цена, место в инвентаре, гарантия легендарного через Pity),
--    EquipPet / UnequipPet (слоты Economy.petSlots), DeletePet, EquipBest;
--  * атрибут игрока Pets — виды надетых питомцев через запятую по порядку (по нему все клиенты рисуют питомцев);
--  * стартовый питомец (Pets.StarterPet) — подарок после первой сдачи банки;
--  * баннер на весь сервер за легендарного и мифического, сигнал Hatched (для заданий дня);
--  * API для наград: grantPet (питомец в подарок), hatchFree (бесплатный кокон).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Net = require(Shared:WaitForChild("Net"))
local Pets = require(Shared:WaitForChild("Pets"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Signal = require(Shared:WaitForChild("Signal"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local RequestService = require(script.Parent.RequestService)

type Data = PlayerData.Data
type PetRecord = PlayerData.PetRecord

local PetService = {}

-- (игрок, вид питомца) — питомец вылупился из кокона (купленного или из награды)
PetService.Hatched = Signal.new() :: Signal.Signal<Player, string>

local LOADING = "Данные ещё загружаются"
local NO_PET = "Нет такого питомца"
local NO_COCOON = "Нет такого кокона"
local FULL_TEXT = "Нет места — удали лишних питомцев"
local BANNER_RANK = 4 -- с какого ранга редкости (Pets.Rarities[].Rank) баннер на весь сервер: легендарный+
local STARTER_DELAY = 1.5 -- подарок появляется после анимации сдачи банки (монеты летят в счётчик)

local notifyRemote: RemoteEvent? = nil
local bannerRemote: RemoteEvent? = nil
local effectRemote: RemoteEvent? = nil

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

local function rank(kind: string): number
	local def = Pets.Kinds[kind]
	return if def then Pets.Rarities[def.Rarity].Rank else 0
end

local function findPet(d: Data, id: number): PetRecord?
	for _, p in d.Pets do
		if p.Id == id then
			return p
		end
	end
	return nil
end

local function hasRoom(d: Data): boolean
	return #d.Pets < Pets.MaxInventory
end

local function freeSlot(d: Data): boolean
	return #d.Equipped < Economy.petSlots(d.Rebirths)
end

local attrSigs: { [Player]: string } = {}

-- Атрибут Pets = виды надетых питомцев через запятую (ставится, только если изменился).
-- Вызывается на каждый DataService.Changed, поэтому сначала дешёвая проверка «надетые/инвентарь те же».
local function syncAttr(player: Player)
	local d = DataService.get(player)
	if not d or player.Parent ~= Players then
		return
	end
	local sig = table.concat(d.Equipped, ",") .. "|" .. d.NextPetId .. "|" .. #d.Pets
	if attrSigs[player] == sig and player:GetAttribute(Net.PlayerAttrs.Pets) ~= nil then
		return
	end
	attrSigs[player] = sig
	local text = table.concat(PlayerData.equippedKinds(d), ",")
	if player:GetAttribute(Net.PlayerAttrs.Pets) ~= text then
		player:SetAttribute(Net.PlayerAttrs.Pets, text)
	end
end

-- Новая запись питомца (вызывать внутри DataService.update)
local function addRecord(d: Data, kind: string, equip: boolean): PetRecord
	local rec: PetRecord = { Id = d.NextPetId, Kind = kind }
	d.NextPetId += 1
	table.insert(d.Pets, rec)
	if equip and freeSlot(d) then
		table.insert(d.Equipped, rec.Id)
	end
	return rec
end

-- Баннер на весь сервер за легендарного и лучше
local function announce(player: Player, kind: string)
	local def = Pets.Kinds[kind]
	local r = bannerRemote
	if not def or not r then
		return
	end
	local rarity = Pets.Rarities[def.Rarity]
	if rarity.Rank < BANNER_RANK then
		return
	end
	r:FireAllClients(string.format("🐾 %s питомец «%s»! Хозяин: %s", rarity.Name, def.Name, player.DisplayName), def.Rarity, rarity.Color)
end

-- Вылупить питомца из кокона: списать cost осколков, Pity, статистика, баннер, сигнал.
-- Проверки острова и цены — у вызывающего. nil — нет места или данные не загружены.
local function hatchInto(player: Player, cocoon: Pets.CocoonDef, cost: number): PetRecord?
	local d = DataService.get(player)
	if not d or not hasRoom(d) or d.Shards < cost then
		return nil
	end
	local kind, pity = Pets.roll(cocoon.Id, math.random(), d.Pity[cocoon.Id] or 0)
	local rec: PetRecord? = nil
	DataService.update(player, function(data)
		data.Shards -= cost
		data.Pity[cocoon.Id] = pity
		data.Stats.Hatched += 1
		-- свободный слот — сразу надеть (новичку не нужно искать кнопку)
		rec = addRecord(data, kind, true)
	end)
	if not rec then
		return nil
	end
	syncAttr(player)
	announce(player, kind)
	PetService.Hatched:Fire(player, kind)
	return rec
end

----------------------------------------------------------------------
-- Публичное API (награды)
----------------------------------------------------------------------

-- Есть ли место в инвентаре питомцев
function PetService.hasRoom(player: Player): boolean
	local d = DataService.get(player)
	return d ~= nil and hasRoom(d)
end

-- Подарить питомца (награда календаря и т.п.). equip ~= false — надеть, если есть свободный слот.
-- nil — нет такого вида, нет места или данные не загружены.
function PetService.grantPet(player: Player, kind: string, equip: boolean?): PetRecord?
	if typeof(kind) ~= "string" or not Pets.Kinds[kind] then
		return nil
	end
	local d = DataService.get(player)
	if not d or not hasRoom(d) then
		return nil
	end
	local rec: PetRecord? = nil
	DataService.update(player, function(data)
		rec = addRecord(data, kind, equip ~= false)
	end)
	if rec then
		syncAttr(player)
		announce(player, kind)
	end
	return rec
end

-- Бесплатный кокон (награда календаря, код): вылупляется как купленный (Pity, статистика, задания),
-- клиент получает Effect "hatch" для показа подарка. nil — нет места или нет такого кокона.
function PetService.hatchFree(player: Player, cocoonId: string): PetRecord?
	local cocoon = if typeof(cocoonId) == "string" then Pets.Cocoons[cocoonId] else nil
	if not cocoon then
		return nil
	end
	local rec = hatchInto(player, cocoon, 0)
	if rec then
		effect(player, { Kind = "hatch", Text = rec.Kind, Value = rec.Id, UserId = player.UserId })
	end
	return rec
end

----------------------------------------------------------------------
-- Стартовый питомец: подарок после первой сдачи банки
----------------------------------------------------------------------

local function checkStarter(player: Player)
	local d = DataService.get(player)
	if not d or d.Tutorial.pet == true or d.Stats.Sells < 1 then
		return
	end
	if #d.Pets > 0 then
		-- питомцы уже есть (например, вылупил до первой сдачи) — подарок не нужен
		DataService.update(player, function(data)
			data.Tutorial.pet = true
		end)
		return
	end
	local kind = Pets.StarterPet
	local rec: PetRecord? = nil
	DataService.update(player, function(data)
		data.Tutorial.pet = true
		rec = addRecord(data, kind, true)
	end)
	local granted = rec
	if not granted then
		return
	end
	syncAttr(player)
	effect(player, { Kind = "hatch", Text = kind, Value = granted.Id, UserId = player.UserId })
	notify(player, "🎁 Подарок: " .. Pets.Kinds[kind].Name .. "!", "good")
end

----------------------------------------------------------------------
-- Request
----------------------------------------------------------------------

local function petId(payload: any): number?
	if ServerLogic.isInteger(payload) then
		return payload
	end
	return nil
end

local function hatch(player: Player, payload: any): (boolean, any)
	local cocoon: Pets.CocoonDef? = if typeof(payload) == "string" then Pets.Cocoons[payload] else nil
	if not cocoon then
		return false, NO_COCOON
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if d.Zone < cocoon.Zone then
		return false, string.format("Сначала открой остров «%s»", Config.Zones[cocoon.Zone].Name)
	end
	if not hasRoom(d) then
		return false, FULL_TEXT
	end
	if d.Shards < cocoon.Cost then
		return false, "Не хватает 💎 Осколков"
	end
	local rec = hatchInto(player, cocoon, cocoon.Cost)
	if not rec then
		return false, RequestService.ErrorText
	end
	return true, { Kind = rec.Kind, Id = rec.Id }
end

local function equipPet(player: Player, payload: any): (boolean, any)
	local id = petId(payload)
	if not id then
		return false, NO_PET
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not findPet(d, id) then
		return false, NO_PET
	end
	if table.find(d.Equipped, id) then
		return false, "Этот питомец уже надет"
	end
	local slots = Economy.petSlots(d.Rebirths)
	if #d.Equipped >= slots then
		return false, string.format("Все слоты заняты (%d) — сними другого питомца", slots)
	end
	DataService.update(player, function(data)
		table.insert(data.Equipped, id)
	end)
	syncAttr(player)
	return true, id
end

local function unequipPet(player: Player, payload: any): (boolean, any)
	local id = petId(payload)
	if not id then
		return false, NO_PET
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not table.find(d.Equipped, id) then
		return false, "Этот питомец не надет"
	end
	DataService.update(player, function(data)
		local i = table.find(data.Equipped, id)
		if i then
			table.remove(data.Equipped, i)
		end
	end)
	syncAttr(player)
	return true, id
end

local function deletePet(player: Player, payload: any): (boolean, any)
	local id = petId(payload)
	if not id then
		return false, NO_PET
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if not findPet(d, id) then
		return false, NO_PET
	end
	DataService.update(player, function(data)
		-- сначала снять, потом удалить
		local e = table.find(data.Equipped, id)
		if e then
			table.remove(data.Equipped, e)
		end
		for i, p in data.Pets do
			if p.Id == id then
				table.remove(data.Pets, i)
				break
			end
		end
	end)
	syncAttr(player)
	return true, id
end

-- Самое большое значение бонуса каждого вида среди всех питомцев (чтобы сравнивать мс окна с долями)
local KIND_MAX: { [string]: number } = {}
for _, def in Pets.Kinds do
	KIND_MAX[def.Bonus] = math.max(KIND_MAX[def.Bonus] or 0, def.Value)
end

-- Польза питомца: бонус Вольт множит весь доход — он всегда впереди и сравнивается по величине;
-- остальные виды — по доле от лучшего питомца своего вида (0..1)
local function petScore(kind: string): number
	local def = Pets.Kinds[kind]
	if not def then
		return -1
	end
	if def.Bonus == "volts" then
		return 10 + def.Value
	end
	local top = KIND_MAX[def.Bonus] or 0
	return if top > 0 then def.Value / top else 0
end

-- Лучшие питомцы: больше польза (см. petScore); при равной — выше редкость, потом раньше получен
local function better(a: PetRecord, b: PetRecord): boolean
	local sa, sb = petScore(a.Kind), petScore(b.Kind)
	if sa ~= sb then
		return sa > sb
	end
	local ra, rb = rank(a.Kind), rank(b.Kind)
	if ra ~= rb then
		return ra > rb
	end
	return a.Id < b.Id
end

local function equipBest(player: Player, _payload: any): (boolean, any)
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if #d.Pets == 0 then
		return false, "У тебя пока нет питомцев"
	end
	local list = table.clone(d.Pets)
	table.sort(list, better)
	local slots = Economy.petSlots(d.Rebirths)
	local ids: { number } = {}
	for i = 1, math.min(slots, #list) do
		table.insert(ids, list[i].Id)
	end
	DataService.update(player, function(data)
		data.Equipped = ids
	end)
	syncAttr(player)
	return true, #ids
end

----------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------

function PetService.start()
	notifyRemote = Net.event("Notify")
	bannerRemote = Net.event("Banner")
	effectRemote = Net.event("Effect")

	RequestService.handle(Net.Actions.Hatch, hatch)
	RequestService.handle(Net.Actions.EquipPet, equipPet)
	RequestService.handle(Net.Actions.UnequipPet, unequipPet)
	RequestService.handle(Net.Actions.DeletePet, deletePet)
	RequestService.handle(Net.Actions.EquipBest, equipBest)

	DataService.Loaded:Connect(function(player)
		syncAttr(player)
		checkStarter(player) -- сдал банку в прошлый раз, но вышел до подарка
	end)
	-- данные могли поменяться где угодно (перезапуск, сохранение, другие сервисы) — атрибут держим в синхроне
	DataService.Changed:Connect(syncAttr)
	Players.PlayerRemoving:Connect(function(player)
		attrSigs[player] = nil
	end)
	EconomyService.Sold:Connect(function(player)
		local d = DataService.get(player)
		if d and d.Tutorial.pet ~= true then
			task.delay(STARTER_DELAY, checkStarter, player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			syncAttr(player)
			checkStarter(player)
		end
	end
end

return PetService
