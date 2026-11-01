--!strict
-- RequestService (P6): the single router for Net "Request" (action: string, data: any) (SPEC §4, §17).
-- Every request is shape-checked (action name, payload size/depth), rate-limited per player (token bucket +
-- a minimum gap per action) and dispatched to the registered handler inside pcall. A handler returns
-- (ok: boolean, errKey: string?, errArgs: {any}?); on failure the player gets Notify(errKey, errArgs, "Warning").
-- Handlers send their own success toasts. Unknown actions are ignored (logged once in Studio).
--
-- API (SPEC §17)
--   Register(action, handler(player, data) -> (boolean, string?, {any}?))   a later registration of the same
--                                                     action replaces a built-in one silently (e.g. QueueService's
--                                                     "SetRolePref"); replacing another service's handler warns
--   Has(action) -> boolean
--   Dispatch(player, action, data) -> (boolean, string?)   same path as the remote (tests / server tools)
--   Parse.* (pure payload parsers, unit-tested): KitId(data), Skin(data), Title(data), Trail(data),
--          Setting(data) -> (key, value)?, QuestIndex(data)
-- Built-in actions (payloads accept bare values or tables, lowerCamel or PascalCase keys):
--   EquipKit    "kitId" | {kitId}                       equips into the kit's role slot (Human/Monster)
--   EquipSkin   {kitId, skinId}                         "Default" = default look
--   EquipTrail  "trailId" | {trailId | trail}           mastery trail, "" = none
--   Buy         {kind = "Kit"|"Skin", kitId, skinId?}   -> ShopService.Buy (G, LV, daily-shop discount)
--   ClaimQuest  index | {index} | {id}                  -> QuestService.Claim
--   RerollQuest index | {index}                         -> QuestService.Reroll (once per 12 h window)
--   SetSetting  {key, value}                            whitelist + type/range check (ProfileSchema.Settings)
--   SetRolePref "Either"|"Monster"|"Human" | {pref}     (QueueService replaces this with its own handler)
--   SetTitle    "titleId" | {titleId | title}           "" = no title
-- Other services register: Vote, StartPractice (RoundService), TryKit (CharacterService), StyleLab.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Progression = Shared:WaitForChild("Progression")
local ProfileSchema = require(Progression:WaitForChild("ProfileSchema")) :: any
local Titles = require(Progression:WaitForChild("Titles")) :: any

local RequestService = {}
RequestService.Priority = 6

type Handler = (Player, any) -> (boolean, string?, { any }?)
type Entry = { Handler: Handler, BuiltIn: boolean, Owner: string }
type Bucket = { Tokens: number, At: number, Last: { [string]: number }, WarnedAt: number }

local BUCKET_SIZE = 12
local REFILL_PER_SECOND = 5
local DEFAULT_GAP = 0.15
local ACTION_GAP: { [string]: number } = {
	SetSetting = 0.03, -- sliders
	Buy = 0.5,
	ClaimQuest = 0.25,
	RerollQuest = 1,
	Vote = 0.25,
	StartPractice = 1,
	StyleLab = 0.2,
}
local MAX_ACTION_LEN = 32
local MAX_STRING = 200
local MAX_KEYS = 16
local MAX_DEPTH = 3
local RATE_WARN_GAP = 3

local handlers: { [string]: Entry } = {}
local buckets: { [Player]: Bucket } = {}
local unknownLogged: { [string]: boolean } = {}
local registering = "?" -- name of the built-in block while it registers

local DataService: any = nil
local ShopService: any = nil
local QuestService: any = nil
local QueueService: any = nil
local CharacterService: any = nil

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

-- Localised text for Notify args in the PLAYER's language (Strings is global; swap, format, restore).
local function textFor(player: Player, localized: any): string
	local lang = "en"
	if DataService and type(DataService.LanguageOf) == "function" then
		local ok, value = pcall(DataService.LanguageOf, player)
		if ok and (value == "en" or value == "ru") then
			lang = value
		end
	end
	if type(localized) == "string" then
		local prev = Strings.Language()
		Strings.SetLanguage(lang)
		local s = Strings.L(localized)
		Strings.SetLanguage(prev)
		return s
	elseif type(localized) == "table" then
		local s = localized[lang]
		return if type(s) == "string" and s ~= "" then s else (localized.en or "")
	end
	return ""
end
RequestService.TextFor = textFor

-- Payload sanity ----------------------------------------------------------------------------------------

local function payloadOk(v: any, depth: number): boolean
	local t = typeof(v)
	if t == "nil" or t == "boolean" then
		return true
	elseif t == "number" then
		return v == v and v > -1e9 and v < 1e9
	elseif t == "string" then
		return #v <= MAX_STRING
	elseif t == "table" then
		if depth >= MAX_DEPTH then
			return false
		end
		local n = 0
		for key, value in v do
			n += 1
			if n > MAX_KEYS then
				return false
			end
			local kt = type(key)
			if (kt ~= "string" and kt ~= "number") or (kt == "string" and #key > 32) then
				return false
			end
			if not payloadOk(value, depth + 1) then
				return false
			end
		end
		return true
	end
	return false -- Instances, Vector3 etc. are never needed by menu requests
end
RequestService.PayloadOk = function(v: any): boolean
	return payloadOk(v, 0)
end

-- Pure parsers ----------------------------------------------------------------------------------------------

local function idString(v: any): string?
	if type(v) == "string" and #v <= 40 and (v == "" or string.match(v, "^[%w_:]+$") ~= nil) then
		return v
	end
	return nil
end

local function field(data: any, ...: string): any
	if type(data) ~= "table" then
		return nil
	end
	for _, name in { ... } do
		local v = data[name]
		if v ~= nil then
			return v
		end
	end
	return nil
end

local Parse = {}
RequestService.Parse = Parse

function Parse.KitId(data: any): string?
	local v = if type(data) == "table" then field(data, "kitId", "KitId", "id") else data
	local id = idString(v)
	return if id and id ~= "" then id else nil
end

function Parse.Skin(data: any): (string?, string?)
	local kitId = idString(field(data, "kitId", "KitId"))
	local skinId = idString(field(data, "skinId", "SkinId"))
	if kitId and skinId and kitId ~= "" and skinId ~= "" then
		return kitId, skinId
	end
	return nil, nil
end

function Parse.Title(data: any): string?
	local v = if type(data) == "table" then field(data, "titleId", "TitleId", "title", "Title", "id") else data
	if v == nil then
		return ""
	end
	return idString(v)
end

function Parse.Trail(data: any): string?
	local v = if type(data) == "table" then field(data, "trailId", "TrailId", "trail", "Trail", "id") else data
	if v == nil then
		return ""
	end
	return idString(v)
end

function Parse.Setting(data: any): (string?, any)
	local key = field(data, "key", "Key", "setting")
	if type(key) ~= "string" or #key > 32 then
		return nil, nil
	end
	return key, field(data, "value", "Value")
end

-- Returns (index?, questId?) — the client may name a quest by list index or by template id.
function Parse.QuestIndex(data: any): (number?, string?)
	local v = if type(data) == "table" then field(data, "index", "Index") else data
	if type(v) == "number" and v == v and v >= 1 and v <= 8 and math.floor(v) == v then
		return v, nil
	end
	local id = field(data, "id", "Id", "questId")
	if type(id) == "string" and #id <= 40 then
		return nil, id
	end
	return nil, nil
end

-- Registration / dispatch ---------------------------------------------------------------------------------

function RequestService.Register(action: string, handler: Handler)
	assert(
		type(action) == "string" and #action > 0 and #action <= MAX_ACTION_LEN,
		"RequestService.Register: bad action"
	)
	assert(type(handler) == "function", "RequestService.Register: handler must be a function")
	local builtIn = registering ~= "?"
	local existing = handlers[action]
	if existing and builtIn and not existing.BuiltIn then
		return -- a service registered this action before the built-ins: keep the service's handler
	end
	if existing and not existing.BuiltIn and not builtIn then
		warn(("[RequestService] action %q registered twice; the newer handler wins"):format(action))
	end
	handlers[action] = { Handler = handler, BuiltIn = builtIn, Owner = if builtIn then registering else "service" }
end

function RequestService.Has(action: string): boolean
	return handlers[action] ~= nil
end

local function allow(player: Player, action: string): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if bucket == nil then
		bucket = { Tokens = BUCKET_SIZE, At = now, Last = {}, WarnedAt = 0 }
		buckets[player] = bucket
	end
	bucket.Tokens = math.min(BUCKET_SIZE, bucket.Tokens + (now - bucket.At) * REFILL_PER_SECOND)
	bucket.At = now
	local gap = ACTION_GAP[action] or DEFAULT_GAP
	local last = bucket.Last[action]
	if bucket.Tokens < 1 or (last ~= nil and now - last < gap) then
		if now - bucket.WarnedAt > RATE_WARN_GAP then
			bucket.WarnedAt = now
			notify(player, "prog.err.rateLimited", nil, "Warning")
		end
		return false
	end
	bucket.Tokens -= 1
	bucket.Last[action] = now
	return true
end

function RequestService.Dispatch(player: Player, action: any, data: any): (boolean, string?)
	if type(action) ~= "string" or #action == 0 or #action > MAX_ACTION_LEN then
		return false, "prog.err.badRequest"
	end
	local entry = handlers[action]
	if entry == nil then
		if RunService:IsStudio() and not unknownLogged[action] then
			unknownLogged[action] = true
			warn("[RequestService] no handler for action " .. action)
		end
		return false, nil
	end
	if not payloadOk(data, 0) then
		notify(player, "prog.err.badRequest", nil, "Warning")
		return false, "prog.err.badRequest"
	end
	if not allow(player, action) then
		return false, "prog.err.rateLimited"
	end
	local ok, success, errKey, errArgs = pcall(entry.Handler, player, data)
	if not ok then
		warn(("[RequestService] %s handler error: %s"):format(action, tostring(success)))
		return false, nil
	end
	if success ~= true and type(errKey) == "string" then
		notify(player, errKey, if type(errArgs) == "table" then errArgs else nil, "Warning")
	end
	return success == true, if type(errKey) == "string" then errKey else nil
end

-- Built-in handlers ---------------------------------------------------------------------------------------------

local function update(player: Player, fn: (any) -> ()): boolean
	return DataService ~= nil and DataService.Update(player, fn) == true
end

local function profileOf(player: Player): any
	if DataService == nil then
		return nil
	end
	return DataService.Get(player)
end

local function onEquipKit(player: Player, data: any): (boolean, string?, { any }?)
	local kitId = Parse.KitId(data)
	if kitId == nil then
		return false, "prog.err.badRequest"
	end
	local profile = profileOf(player)
	if profile == nil then
		return false, "prog.err.notReady"
	end
	local ok, errKey, role = ProfileSchema.CanEquipKit(profile, kitId)
	if not ok then
		return false, errKey
	end
	update(player, function(p)
		p.Equipped[role] = kitId
	end)
	local kit = Kits.Get(kitId)
	notify(player, "prog.notify.equipped", { textFor(player, kit.Name) }, "Info")
	return true
end

local function onEquipSkin(player: Player, data: any): (boolean, string?, { any }?)
	local kitId, skinId = Parse.Skin(data)
	if kitId == nil or skinId == nil then
		return false, "prog.err.badRequest"
	end
	local profile = profileOf(player)
	if profile == nil then
		return false, "prog.err.notReady"
	end
	local ok, errKey = ProfileSchema.CanEquipSkin(profile, kitId, skinId)
	if not ok then
		return false, errKey
	end
	update(player, function(p)
		p.Equipped.Skins[kitId] = if skinId == "Default" then nil else skinId
	end)
	-- the lobby body shows the equipped human kit: rebuild it with the new look
	if
		CharacterService
		and type(CharacterService.RefreshLobby) == "function"
		and player:GetAttribute("Role") == "Lobby"
	then
		task.defer(function()
			pcall(CharacterService.RefreshLobby, player)
		end)
	end
	local skin = Kits.Skin(kitId, skinId)
	notify(player, "prog.notify.equipped", { textFor(player, skin.Name) }, "Info")
	return true
end

local function onEquipTrail(player: Player, data: any): (boolean, string?, { any }?)
	local trailId = Parse.Trail(data)
	if trailId == nil then
		return false, "prog.err.badRequest"
	end
	local profile = profileOf(player)
	if profile == nil then
		return false, "prog.err.notReady"
	end
	local ok, errKey = ProfileSchema.CanEquipTrail(profile, trailId)
	if not ok then
		return false, errKey
	end
	update(player, function(p)
		p.Equipped.Trail = trailId
	end)
	if trailId == "" then
		notify(player, "prog.notify.trailCleared", nil, "Info")
	else
		local kind = string.match(trailId, ":(%w+)$") or "Soul"
		notify(player, "prog.notify.trailSet", { textFor(player, "prog.trail." .. kind) }, "Info")
	end
	return true
end

local function onSetTitle(player: Player, data: any): (boolean, string?, { any }?)
	local titleId = Parse.Title(data)
	if titleId == nil then
		return false, "prog.err.badRequest"
	end
	local profile = profileOf(player)
	if profile == nil then
		return false, "prog.err.notReady"
	end
	local ok, errKey = ProfileSchema.CanSetTitle(profile, titleId)
	if not ok then
		return false, errKey
	end
	update(player, function(p)
		p.Equipped.Title = titleId
	end)
	if titleId == "" then
		notify(player, "prog.notify.titleCleared", nil, "Info")
	else
		notify(player, "prog.notify.titleSet", { textFor(player, Titles.Text(titleId)) }, "Info")
	end
	return true
end

local function onSetSetting(player: Player, data: any): (boolean, string?, { any }?)
	local key, value = Parse.Setting(data)
	if key == nil then
		return false, "prog.err.badRequest"
	end
	if profileOf(player) == nil then
		return false, "prog.err.notReady"
	end
	local ok, clean, errKey = ProfileSchema.ValidateSetting(key, value)
	if not ok then
		return false, errKey
	end
	local default = ProfileSchema.Settings()[key].Default
	update(player, function(p)
		p.Settings[key] = if clean == default then nil else clean
	end)
	return true
end

local function onSetRolePref(player: Player, data: any): (boolean, string?, { any }?)
	local pref = ProfileSchema.ParseRolePref(data)
	if pref == nil then
		return false, "prog.err.rolePref"
	end
	if QueueService and type(QueueService.SetPreference) == "function" then
		local ok, result = pcall(QueueService.SetPreference, player, pref)
		if ok and result then
			return true
		end
	end
	if not update(player, function(p)
		p.RolePreference = pref
	end) then
		return false, "prog.err.notReady"
	end
	player:SetAttribute("RolePreference", pref)
	return true
end

local function onBuy(player: Player, data: any): (boolean, string?, { any }?)
	if ShopService and type(ShopService.Buy) == "function" then
		return ShopService.Buy(player, data)
	end
	return false, "prog.err.notReady"
end

local function onClaimQuest(player: Player, data: any): (boolean, string?, { any }?)
	local index, questId = Parse.QuestIndex(data)
	if index == nil and questId == nil then
		return false, "prog.err.badRequest"
	end
	if QuestService and type(QuestService.Claim) == "function" then
		return QuestService.Claim(player, index, questId)
	end
	return false, "prog.err.notReady"
end

local function onRerollQuest(player: Player, data: any): (boolean, string?, { any }?)
	local index, questId = Parse.QuestIndex(data)
	if index == nil and questId == nil then
		return false, "prog.err.badRequest"
	end
	if QuestService and type(QuestService.Reroll) == "function" then
		return QuestService.Reroll(player, index, questId)
	end
	return false, "prog.err.notReady"
end

-- Lifecycle --------------------------------------------------------------------------------------------------

function RequestService.Init()
	DataService = tryService("DataService")
	ShopService = tryService("ShopService")
	QuestService = tryService("QuestService")
	QueueService = tryService("QueueService")
	CharacterService = tryService("CharacterService")
	registering = "RequestService"
	RequestService.Register("EquipKit", onEquipKit)
	RequestService.Register("EquipSkin", onEquipSkin)
	RequestService.Register("EquipTrail", onEquipTrail)
	RequestService.Register("SetTitle", onSetTitle)
	RequestService.Register("SetSetting", onSetSetting)
	RequestService.Register("SetRolePref", onSetRolePref)
	RequestService.Register("Buy", onBuy)
	RequestService.Register("ClaimQuest", onClaimQuest)
	RequestService.Register("RerollQuest", onRerollQuest)
	registering = "?"
end

function RequestService.Start()
	Net.Server.On("Request", function(player: Player, action: any, data: any)
		RequestService.Dispatch(player, action, data)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
end

return RequestService
