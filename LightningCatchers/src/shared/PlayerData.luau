--!strict
-- Схема данных игрока: значения по умолчанию, проверка сохранённых данных (миграции),
-- подготовка к сохранению. Один источник правды для сервера, клиента и тестов.

local Config = require(script.Parent.Config)
local Pets = require(script.Parent.Pets)

export type PetRecord = { Id: number, Kind: string }
export type FulgRecord = { Id: number, Seed: number, Color: Config.ColorId, Mut: string?, Serial: number, Zone: number }
export type QuestState = { Id: string, Target: number, Progress: number, Claimed: boolean }

export type Data = {
	Version: number,
	Volts: number,
	Shards: number,
	Charge: number,
	TotalVolts: number, -- заработано за всё время (для таблицы лидеров)
	Upgrades: { Rod: number, Jar: number, Boots: number, Insulation: number, Magnet: number },
	Drone: boolean,
	DroneOn: boolean,
	Zone: number, -- открыты острова 1..Zone
	LastZone: number, -- где был при выходе (0 = хаб)
	Rebirths: number,
	Pets: { PetRecord },
	NextPetId: number,
	Equipped: { number },
	Pity: { [string]: number },
	Fulgs: { FulgRecord },
	NextFulgId: number,
	EquippedFulgs: { number },
	Index: { [string]: boolean }, -- "зона:цвет" => поймана
	Stats: {
		Catches: number,
		Perfects: number,
		BestCombo: number,
		Sells: number,
		Hatched: number,
		Golds: number,
		Rainbows: number,
		Blacks: number,
		PlaySeconds: number,
	},
	Daily: { Streak: number, LastDay: number },
	Quests: { Day: number, List: { QuestState } },
	Boosts: { Volts2x: number }, -- до какого os.time() действует
	LastOnline: number,
	IncomeRate: number, -- Вольт в минуту активной игры (сглаженное)
	Settings: { Music: boolean, Sfx: boolean, SoftFlash: boolean, Shake: boolean, Offset: number },
	Codes: { [string]: boolean },
	Tutorial: { [string]: boolean },
	Welcome: number, -- накопленный офлайн-доход, ещё не забранный
}

local PlayerData = {}

function PlayerData.default(): Data
	return {
		Version = Config.DataVersion,
		Volts = 0,
		Shards = 0,
		Charge = 0,
		TotalVolts = 0,
		Upgrades = { Rod = 0, Jar = 0, Boots = 0, Insulation = 0, Magnet = 0 },
		Drone = false,
		DroneOn = true,
		Zone = 1,
		LastZone = 1,
		Rebirths = 0,
		Pets = {},
		NextPetId = 1,
		Equipped = {},
		Pity = {},
		Fulgs = {},
		NextFulgId = 1,
		EquippedFulgs = {},
		Index = {},
		Stats = { Catches = 0, Perfects = 0, BestCombo = 0, Sells = 0, Hatched = 0, Golds = 0, Rainbows = 0, Blacks = 0, PlaySeconds = 0 },
		Daily = { Streak = 0, LastDay = 0 },
		Quests = { Day = 0, List = {} },
		Boosts = { Volts2x = 0 },
		LastOnline = 0,
		IncomeRate = 0,
		Settings = { Music = true, Sfx = true, SoftFlash = true, Shake = true, Offset = 0 },
		Codes = {},
		Tutorial = {},
		Welcome = 0,
	}
end

local function num(v: any, fallback: number, lo: number, hi: number): number
	if typeof(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return fallback
	end
	return math.clamp(v, lo, hi)
end

local function int(v: any, fallback: number, lo: number, hi: number): number
	return math.floor(num(v, fallback, lo, hi))
end

local function bool(v: any, fallback: boolean): boolean
	if typeof(v) == "boolean" then
		return v
	end
	return fallback
end

local BIG = 1e300

-- Привести сохранённые данные к актуальной схеме (защита от мусора и старых версий)
function PlayerData.reconcile(raw: any): Data
	local d = PlayerData.default()
	if typeof(raw) ~= "table" then
		return d
	end
	d.Volts = num(raw.Volts, 0, 0, BIG)
	d.Shards = num(raw.Shards, 0, 0, BIG)
	d.Charge = num(raw.Charge, 0, 0, BIG)
	d.TotalVolts = num(raw.TotalVolts, 0, 0, BIG)
	if typeof(raw.Upgrades) == "table" then
		for id, defn in Config.Upgrades do
			(d.Upgrades :: any)[id] = int(raw.Upgrades[id], 0, 0, defn.MaxLevel)
		end
	end
	d.Drone = bool(raw.Drone, false)
	d.DroneOn = bool(raw.DroneOn, true)
	d.Zone = int(raw.Zone, 1, 1, #Config.Zones)
	d.LastZone = int(raw.LastZone, 1, 0, d.Zone)
	d.Rebirths = int(raw.Rebirths, 0, 0, 1000)

	local petIds: { [number]: boolean } = {}
	if typeof(raw.Pets) == "table" then
		for _, p in raw.Pets do
			if typeof(p) == "table" and typeof(p.Kind) == "string" and Pets.Kinds[p.Kind] and typeof(p.Id) == "number" then
				if not petIds[p.Id] and #d.Pets < Pets.MaxInventory then
					petIds[p.Id] = true
					table.insert(d.Pets, { Id = math.floor(p.Id), Kind = p.Kind })
				end
			end
		end
	end
	local maxPetId = 0
	for id in petIds do
		maxPetId = math.max(maxPetId, id)
	end
	d.NextPetId = math.max(int(raw.NextPetId, 1, 1, 1e12), maxPetId + 1)
	if typeof(raw.Equipped) == "table" then
		for _, id in raw.Equipped do
			if typeof(id) == "number" and petIds[id] and not table.find(d.Equipped, id) then
				table.insert(d.Equipped, id)
			end
		end
	end
	if typeof(raw.Pity) == "table" then
		for id in Pets.Cocoons do
			d.Pity[id] = int(raw.Pity[id], 0, 0, 1000)
		end
	end

	local fulgIds: { [number]: boolean } = {}
	if typeof(raw.Fulgs) == "table" then
		for _, f in raw.Fulgs do
			if
				typeof(f) == "table"
				and typeof(f.Id) == "number"
				and typeof(f.Seed) == "number"
				and typeof(f.Color) == "string"
				and Config.Colors[f.Color :: any]
				and not fulgIds[f.Id]
				and #d.Fulgs < 100
			then
				fulgIds[f.Id] = true
				local mut: string? = if typeof(f.Mut) == "string" then f.Mut else nil
				table.insert(d.Fulgs, {
					Id = math.floor(f.Id),
					Seed = math.floor(f.Seed) % 4294967296,
					Color = f.Color :: any,
					Mut = mut,
					Serial = int(f.Serial, 0, 0, 1e12),
					Zone = int(f.Zone, 1, 1, #Config.Zones),
				})
			end
		end
	end
	local maxFulgId = 0
	for id in fulgIds do
		maxFulgId = math.max(maxFulgId, id)
	end
	d.NextFulgId = math.max(int(raw.NextFulgId, 1, 1, 1e12), maxFulgId + 1)
	if typeof(raw.EquippedFulgs) == "table" then
		for _, id in raw.EquippedFulgs do
			if typeof(id) == "number" and fulgIds[id] and not table.find(d.EquippedFulgs, id) and #d.EquippedFulgs < 3 then
				table.insert(d.EquippedFulgs, id)
			end
		end
	end
	if typeof(raw.Index) == "table" then
		for k, v in raw.Index do
			if typeof(k) == "string" and v == true then
				d.Index[k] = true
			end
		end
	end
	if typeof(raw.Stats) == "table" then
		local stats = d.Stats :: any
		for _, k in { "Catches", "Perfects", "BestCombo", "Sells", "Hatched", "Golds", "Rainbows", "Blacks", "PlaySeconds" } do
			stats[k] = num(raw.Stats[k], 0, 0, BIG)
		end
	end
	if typeof(raw.Daily) == "table" then
		d.Daily.Streak = int(raw.Daily.Streak, 0, 0, 7)
		d.Daily.LastDay = int(raw.Daily.LastDay, 0, 0, 1e9)
	end
	if typeof(raw.Quests) == "table" and typeof(raw.Quests.List) == "table" then
		d.Quests.Day = int(raw.Quests.Day, 0, 0, 1e9)
		for _, q in raw.Quests.List do
			if typeof(q) == "table" and typeof(q.Id) == "string" then
				table.insert(d.Quests.List, {
					Id = q.Id,
					Target = int(q.Target, 1, 1, 1e9),
					Progress = int(q.Progress, 0, 0, 1e9),
					Claimed = bool(q.Claimed, false),
				})
			end
		end
	end
	if typeof(raw.Boosts) == "table" then
		d.Boosts.Volts2x = num(raw.Boosts.Volts2x, 0, 0, 1e12)
	end
	d.LastOnline = num(raw.LastOnline, 0, 0, 1e12)
	d.IncomeRate = num(raw.IncomeRate, 0, 0, BIG)
	if typeof(raw.Settings) == "table" then
		local s = raw.Settings
		d.Settings.Music = bool(s.Music, true)
		d.Settings.Sfx = bool(s.Sfx, true)
		d.Settings.SoftFlash = bool(s.SoftFlash, true)
		d.Settings.Shake = bool(s.Shake, true)
		d.Settings.Offset = int(s.Offset, 0, -150, 150)
	end
	if typeof(raw.Codes) == "table" then
		for k, v in raw.Codes do
			if typeof(k) == "string" and v == true then
				d.Codes[k] = true
			end
		end
	end
	if typeof(raw.Tutorial) == "table" then
		for k, v in raw.Tutorial do
			if typeof(k) == "string" and v == true then
				d.Tutorial[k] = true
			end
		end
	end
	d.Welcome = num(raw.Welcome, 0, 0, BIG)
	return d
end

-- Копия для сохранения (DataStore принимает обычные таблицы без nil-дыр в массивах)
function PlayerData.serialize(d: Data): any
	local copy = table.clone(d) :: any
	copy.Upgrades = table.clone(d.Upgrades)
	copy.Pets = {}
	for i, p in d.Pets do
		copy.Pets[i] = { Id = p.Id, Kind = p.Kind }
	end
	copy.Equipped = table.clone(d.Equipped)
	copy.Pity = table.clone(d.Pity)
	copy.Fulgs = {}
	for i, f in d.Fulgs do
		copy.Fulgs[i] = { Id = f.Id, Seed = f.Seed, Color = f.Color, Mut = f.Mut, Serial = f.Serial, Zone = f.Zone }
	end
	copy.EquippedFulgs = table.clone(d.EquippedFulgs)
	copy.Index = table.clone(d.Index)
	copy.Stats = table.clone(d.Stats)
	copy.Daily = table.clone(d.Daily)
	copy.Quests = { Day = d.Quests.Day, List = {} }
	for i, q in d.Quests.List do
		copy.Quests.List[i] = table.clone(q)
	end
	copy.Boosts = table.clone(d.Boosts)
	copy.Settings = table.clone(d.Settings)
	copy.Codes = table.clone(d.Codes)
	copy.Tutorial = table.clone(d.Tutorial)
	copy.Version = Config.DataVersion
	return copy
end

-- Начало сессии: начислить офлайн-доход в Welcome (забирается кнопкой на экране "С возвращением")
function PlayerData.onSessionStart(d: Data, now: number)
	if d.LastOnline > 0 then
		local away = math.clamp(now - d.LastOnline, 0, Config.Offline.MaxSeconds)
		if away >= Config.Offline.MinSeconds and d.IncomeRate > 0 then
			d.Welcome += math.floor(d.IncomeRate * (away / 60) * Config.Offline.Share)
		end
	end
	d.LastOnline = now
end

-- Вид питомца по Id записи
function PlayerData.petKind(d: Data, id: number): string?
	for _, p in d.Pets do
		if p.Id == id then
			return p.Kind
		end
	end
	return nil
end

function PlayerData.equippedKinds(d: Data): { string }
	local out = {}
	for _, id in d.Equipped do
		local kind = PlayerData.petKind(d, id)
		if kind then
			table.insert(out, kind)
		end
	end
	return out
end

function PlayerData.findFulg(d: Data, id: number): FulgRecord?
	for _, f in d.Fulgs do
		if f.Id == id then
			return f
		end
	end
	return nil
end

return PlayerData
