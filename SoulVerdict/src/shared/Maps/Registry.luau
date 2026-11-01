--!strict
-- Maps/Registry: metadata of every map + lazy, failure-tolerant access to the map modules. Lune-safe.
-- Map modules live next to this file (Maps/<Id>.luau) and return a Types.MapDef ({Id, Name, Desc,
-- Preset, FinalPreset, Music, Build}) or just a Build function. Modules written later by other agents
-- are picked up automatically; a missing or broken module never errors here (it is reported as
-- unavailable and Playable() falls back to the built-in TestArena).
--
-- API
--   Registry.List() -> {MapMeta}          every known map (arenas, lobby, test arena), in menu order
--   Registry.Info(id) -> MapMeta?         metadata only — never requires the map module (cheap, client-safe)
--   Registry.Get(id) -> MapDef?           full definition with Build (nil if the module is missing/broken)
--   Registry.IsAvailable(id) -> boolean   the module exists and loads
--   Registry.Playable() -> {string}       available arena maps (not lobby/test); {"TestArena"} if none
--   Registry.LobbyId() -> string          "Lobby" when that module is available, else "TestArena"
--   Registry.ArenaOrigin: Vector3         where MapService places round maps (lobby stays at LobbyOrigin)
--   Registry.LobbyOrigin: Vector3
-- MapMeta = { Id, Name: Localized, Desc: Localized, Preset, FinalPreset, Music, Kind: "Arena"|"Lobby"|"Test",
--             Order: number, Available: boolean }

local Types = require(script.Parent.Parent.Types)

type Localized = Types.Localized
type MapDef = Types.MapDef
type MapInfo = Types.MapInfo

export type MapKind = "Arena" | "Lobby" | "Test"

export type MapMeta = {
	Id: string,
	Name: Localized,
	Desc: Localized,
	Preset: string,
	FinalPreset: string,
	Music: string,
	Kind: MapKind,
	Order: number,
	Available: boolean,
}

local Registry = {}

-- Round maps are built far from the lobby so both can exist at the same time.
Registry.ArenaOrigin = Vector3.new(0, 0, 2000)
Registry.LobbyOrigin = Vector3.new(0, 0, 0)

type StaticMeta = {
	Id: string,
	Name: Localized,
	Desc: Localized,
	Preset: string,
	FinalPreset: string,
	Music: string,
	Kind: MapKind,
}

-- Defaults; a map module's own fields (Name/Desc/Preset/FinalPreset/Music) override these.
local STATIC: { StaticMeta } = {
	{
		Id = "HallOfVerdicts",
		Kind = "Arena",
		Name = { en = "Hall of Verdicts", ru = "Зал Приговоров" },
		Desc = {
			en = "A golden corridor of pillars where the last light of day passes judgement.",
			ru = "Золотой коридор колонн, где последний свет дня выносит приговор.",
		},
		Preset = "GoldenHall",
		FinalPreset = "GoldenHallFinal",
		Music = "Map_HallOfVerdicts",
	},
	{
		Id = "SnowdinCrossroads",
		Kind = "Arena",
		Name = { en = "Snowdin Crossroads", ru = "Перекрёсток Сноудина" },
		Desc = {
			en = "A sleepy snow town square at night. Warm windows, cold verdicts.",
			ru = "Сонная заснеженная площадь ночью. Тёплые окна, холодные приговоры.",
		},
		Preset = "SnowNight",
		FinalPreset = "SnowNightFinal",
		Music = "Map_SnowdinCrossroads",
	},
	{
		Id = "WaterfallGrotto",
		Kind = "Arena",
		Name = { en = "Waterfall Grotto", ru = "Грот Водопадов" },
		Desc = {
			en = "Glowing crystals and echo flowers in a cavern that remembers every word.",
			ru = "Светящиеся кристаллы и эхо-цветы в пещере, что помнит каждое слово.",
		},
		Preset = "WaterfallGlow",
		FinalPreset = "WaterfallGlowFinal",
		Music = "Map_WaterfallGrotto",
	},
	{
		Id = "VoidRift",
		Kind = "Arena",
		Name = { en = "Void Rift", ru = "Разлом Пустоты" },
		Desc = {
			en = "Broken platforms drifting between timelines. Mind the edges.",
			ru = "Обломки платформ, дрейфующие между временными линиями. Осторожно с краями.",
		},
		Preset = "VoidAbyss",
		FinalPreset = "VoidAbyssFinal",
		Music = "Map_VoidRift",
	},
	{
		Id = "CoreReactor",
		Kind = "Arena",
		Name = { en = "Core Reactor", ru = "Реактор Ядра" },
		Desc = {
			en = "Catwalks over a roaring heart of magma and machinery.",
			ru = "Мостки над ревущим сердцем из магмы и машин.",
		},
		Preset = "CoreInferno",
		FinalPreset = "CoreInfernoFinal",
		Music = "Map_CoreReactor",
	},
	{
		Id = "Lobby",
		Kind = "Lobby",
		Name = { en = "The Lobby", ru = "Лобби" },
		Desc = {
			en = "Wait for the next trial, train on dummies and change your SOUL.",
			ru = "Жди следующего суда, тренируйся на манекенах и меняй свою ДУШУ.",
		},
		Preset = "Lobby",
		FinalPreset = "Lobby",
		Music = "Lobby",
	},
	{
		Id = "TestArena",
		Kind = "Test",
		Name = { en = "Test Arena", ru = "Тестовая арена" },
		Desc = {
			en = "A floating golden ring for trials and testing.",
			ru = "Парящее золотое кольцо для испытаний и тестов.",
		},
		Preset = "GoldenHall",
		FinalPreset = "GoldenHallFinal",
		Music = "Map_HallOfVerdicts",
	},
}

local staticById: { [string]: StaticMeta } = {}
local orderById: { [string]: number } = {}
for i, meta in STATIC do
	staticById[meta.Id] = meta
	orderById[meta.Id] = i
end

-- Module cache: id -> MapDef | false (false = missing or broken; never retried)
local defCache: { [string]: MapDef | false } = {}

local function isLocalized(v: any): boolean
	return type(v) == "table" and type(v.en) == "string"
end

local function nonEmptyString(v: any, fallback: string): string
	return if type(v) == "string" and v ~= "" then v else fallback
end

local function loadDef(id: string): MapDef?
	local cached = defCache[id]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local meta = staticById[id]
	local container: any = script.Parent
	local module = container:FindFirstChild(id)
	if module == nil or id == "Registry" or id == "MapKit" then
		defCache[id] = false
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(("[Maps.Registry] map module %s failed to load: %s"):format(id, tostring(result)))
		defCache[id] = false
		return nil
	end
	local raw: any = result
	local build: any = nil
	if type(raw) == "function" then
		build = raw
		raw = {}
	elseif type(raw) == "table" then
		build = raw.Build
	end
	if type(build) ~= "function" then
		warn(("[Maps.Registry] map module %s has no Build function"):format(id))
		defCache[id] = false
		return nil
	end
	local fallbackName: Localized = if meta then meta.Name else { en = id, ru = id }
	local fallbackDesc: Localized = if meta then meta.Desc else { en = "", ru = "" }
	local def: MapDef = {
		Id = id,
		Name = if isLocalized(raw.Name) then raw.Name else fallbackName,
		Desc = if isLocalized(raw.Desc) then raw.Desc else fallbackDesc,
		Preset = nonEmptyString(raw.Preset, if meta then meta.Preset else "GoldenHall"),
		FinalPreset = nonEmptyString(raw.FinalPreset, if meta then meta.FinalPreset else "GoldenHallFinal"),
		Music = nonEmptyString(raw.Music, if meta then meta.Music else ""),
		Build = build,
	}
	defCache[id] = def
	return def
end

local function moduleExists(id: string): boolean
	if id == "Registry" or id == "MapKit" then
		return false
	end
	local container: any = script.Parent
	return container:FindFirstChild(id) ~= nil
end

local function toMeta(meta: StaticMeta): MapMeta
	return {
		Id = meta.Id,
		Name = meta.Name,
		Desc = meta.Desc,
		Preset = meta.Preset,
		FinalPreset = meta.FinalPreset,
		Music = meta.Music,
		Kind = meta.Kind,
		Order = orderById[meta.Id] or 99,
		Available = moduleExists(meta.Id),
	}
end

function Registry.List(): { MapMeta }
	local out: { MapMeta } = {}
	for _, meta in STATIC do
		table.insert(out, toMeta(meta))
	end
	return out
end

function Registry.Info(id: string): MapMeta?
	local meta = staticById[id]
	if meta then
		return toMeta(meta)
	end
	return nil
end

function Registry.Get(id: string): MapDef?
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return loadDef(id)
end

function Registry.IsAvailable(id: string): boolean
	return Registry.Get(id) ~= nil
end

function Registry.Playable(): { string }
	local out: { string } = {}
	for _, meta in STATIC do
		if meta.Kind == "Arena" and moduleExists(meta.Id) and loadDef(meta.Id) ~= nil then
			table.insert(out, meta.Id)
		end
	end
	if #out == 0 then
		table.insert(out, "TestArena")
	end
	return out
end

function Registry.LobbyId(): string
	if moduleExists("Lobby") and loadDef("Lobby") ~= nil then
		return "Lobby"
	end
	return "TestArena"
end

-- Test hook: forget cached module results (e.g. after the Lune loader rescans the tree).
function Registry._resetCache()
	table.clear(defCache)
end

return Registry
