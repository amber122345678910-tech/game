--!strict
-- AdminService (P85): the owner's admin tools, so everything can be tested ALONE (phone or PC).
-- Admin = StyleLabService.IsAllowed(player) (Studio, place creator, group owner rank 255, private-server owner)
--         OR player.UserId listed in Config.Admins. When Style Lab is open to everyone (Config.StyleLab.AllowEveryone)
--         or disabled, the same ownership rules are checked here instead: admin actions write saved data.
-- Player attributes written here: Admin (bool, on join + whenever the "StyleLab" attribute changes, e.g. after the
--   async group-rank check), AdminGod / AdminNoCooldowns (bool), AdminSpeed (1..3), AdminSolo (bool, server-wide)
--   and AdminOpen (counter bumped by the chat command "/admin" -> Hud/AdminButton opens Screens/Admin).
-- RequestService action "Admin", data = { action = string, ... } (a bare action string works too). Every payload
--   goes through AdminService.Validate (strict schema: required fields, types, integer ranges, kit/map ids, NO
--   unknown keys). Non-admins get Notify "admin.err.denied" and nothing happens. Every accepted action is
--   logged "[Admin] <name> (<userId>) <action> k=v ...". Results are Notify toasts: "admin.ok.*" (Success)
--   or "admin.err.*" (Warning, sent by RequestService). Text args are localised in the player's language.
--
-- Actions (fields; * = required)
--  MATCH    StartNow {side* "Human"|"Monster", kitId?, mapId?, bots? 0..8}  alone: aborts a running match,
--             waits for the lobby, then starts a practice round at once with you on that side/kit and bots on
--             the other side (bots = human bots 1..8 when you are the monster [runtime override of
--             Config.Practice.BotHumans for that start], human allies 0..5 when you are a human);
--             with other players online: forces map + role preference and skips straight into the round
--           SetMinPlayers {n* 1|2}  1 = "solo rounds": RoundService has no 1-player normal round, so while
--             you are alone a practice round vs bots starts by itself SOLO_DELAY s after each return to the lobby
--           SkipPhase   FinalPhase   Collapse   EndRound {winner? "Humans"|"Monster"}   SetMap {mapId*}
--           AddBot {team* "Humans"|"Monster", kitId?} (in front of you; in a match ClearBots removes only these)
--           ClearBots   SpawnDummy {count? 1..5}
--  ME       BecomeKit {kitId*}  equips it (session; Sanitize drops an unowned equip on the next load) and respawns
--             you in place in the lobby; in a practice round the practice restarts with that kit (its role
--             decides the side); in a real match it applies next round
--           God {on*} (Invulnerable + Determined, refreshed every second)   Heal (revives when downed)   FullUlt
--           ResetCooldowns   NoCooldowns {on*} (cooldowns cleared after every cast, AbilityService.Casted)
--           Speed {mult* 1..3} (Hasted status)   TeleportLobby (in a practice round: stop it)   TeleportArena
--  PROGRESS AddGold {n* 1..1e6}   AddLevels {n* 1..100}   UnlockAll (every kit + skin)
--           ResetProfile {confirm* = true} (fresh profile; Settings + Created are kept)
--  TEST     BoxNearest (you must be a monster kit)   DamageMe {n* 1..1000} (True damage, God suspended for the
--           hit)   AddKR {n* 1..100}   GiveDodges0 (exhausts your own monster, else the round monster, else
--           the nearest monster)
--
-- API
--   AdminService.IsAdmin(player) -> boolean
--   AdminService.Validate(data) -> (cmd?, errKey?)        pure: cmd = { action, ...normalised fields }
--   AdminService.Handle(player, data) -> (ok, errKey?, args?)   the request handler (tests, chat)
--   AdminService.Actions() -> {string}                    every action name, sorted
--   AdminService.BotsFor(side, n?) -> number?             bots clamp used by StartNow (pure)
--   AdminService.SoloDelay                                seconds before a solo round starts
-- Chat: "/admin" (TextChatCommand in TextChatService.AdminCommands) bumps AdminOpen for an admin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Registry = require(Shared:WaitForChild("Maps"):WaitForChild("Registry")) :: any
local Progression = Shared:WaitForChild("Progression")
local ProfileSchema = require(Progression:WaitForChild("ProfileSchema")) :: any
local Levels = require(Progression:WaitForChild("Levels")) :: any

local AdminService = {}
AdminService.Priority = 85

local SOLO_DELAY = 10 -- seconds in the lobby before a solo round starts
AdminService.SoloDelay = SOLO_DELAY
local REFRESH = 1 -- God / Speed status refresh period (also the solo tick)
local STATUS_TIME = 2.5 -- duration of every refreshed status (outlives one missed refresh)
local WAIT_IDLE = 20 -- max seconds to wait for the round loop (abort -> lobby / intermission)
local BOX_RANGE = 300
local SERVICE_NAMES = {
	"StyleLabService",
	"RequestService",
	"RoundService",
	"BotService",
	"CharacterService",
	"StatusService",
	"AbilityService",
	"DamageService",
	"DataService",
	"MapService",
	"MovementService",
	"VerdictBoxService",
	"QueueService",
}

type Field = { Kind: string, Required: boolean?, Min: number?, Max: number?, Values: { string }? }
type AdminState = { God: boolean, NoCooldowns: boolean, Speed: number }

local S: { [string]: any } = {} -- services (resolved in Init; tests inject mocks with _SetServices)
local states: { [Player]: AdminState } = {}
local extras: { [Model]: boolean } = {} -- bots spawned by AddBot
local solo = { On = false, Owner = nil :: Player?, Side = "Human", Bots = nil :: number?, Since = 0, Announced = false }
local deniedLogged: { [Player]: number } = {}
local groupOwners: { [any]: boolean } = {}
local launchToken = 0
local savedBotHumans: number? = nil -- Config.Practice.BotHumans while an admin practice start overrides it
local overrideToken = 0

-- Schema (pure) ----------------------------------------------------------------------------------------------

local function enum(values: { string }, required: boolean?): Field
	return { Kind = "enum", Values = values, Required = required }
end
local function int(min: number, max: number, required: boolean?): Field
	return { Kind = "int", Min = min, Max = max, Required = required }
end
local function num(min: number, max: number, required: boolean?): Field
	return { Kind = "number", Min = min, Max = max, Required = required }
end
local function bool(required: boolean?): Field
	return { Kind = "bool", Required = required }
end
local function kit(required: boolean?): Field
	return { Kind = "kit", Required = required }
end
local function map(required: boolean?): Field
	return { Kind = "map", Required = required }
end

local SIDES = { "Human", "Monster" }
local TEAMS = { "Humans", "Monster" }

local SCHEMA: { [string]: { [string]: Field } } = {
	-- MATCH
	StartNow = { side = enum(SIDES, true), kitId = kit(), mapId = map(), bots = int(0, 8) },
	SetMinPlayers = { n = int(1, 2, true) },
	SkipPhase = {},
	FinalPhase = {},
	Collapse = {},
	EndRound = { winner = enum(TEAMS) },
	SetMap = { mapId = map(true) },
	AddBot = { team = enum(TEAMS, true), kitId = kit() },
	ClearBots = {},
	SpawnDummy = { count = int(1, 5) },
	-- ME
	BecomeKit = { kitId = kit(true) },
	God = { on = bool(true) },
	Heal = {},
	FullUlt = {},
	ResetCooldowns = {},
	NoCooldowns = { on = bool(true) },
	Speed = { mult = num(1, 3, true) },
	TeleportLobby = {},
	TeleportArena = {},
	-- PROGRESS
	AddGold = { n = int(1, 1000000, true) },
	AddLevels = { n = int(1, 100, true) },
	UnlockAll = {},
	ResetProfile = { confirm = { Kind = "true", Required = true } },
	-- TEST
	BoxNearest = {},
	DamageMe = { n = int(1, 1000, true) },
	AddKR = { n = int(1, 100, true) },
	GiveDodges0 = {},
}

local function isId(v: any, maxLen: number): boolean
	return type(v) == "string" and #v > 0 and #v <= maxLen and string.match(v, "^[%w_]+$") ~= nil
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- (ok, normalised value)
local function checkField(field: Field, v: any): (boolean, any)
	local kind = field.Kind
	if kind == "enum" then
		return type(v) == "string" and table.find(field.Values :: { string }, v) ~= nil, v
	elseif kind == "int" then
		local ok = finite(v) and math.floor(v) == v and v >= (field.Min :: number) and v <= (field.Max :: number)
		return ok, v
	elseif kind == "number" then
		if not finite(v) or v < (field.Min :: number) or v > (field.Max :: number) then
			return false, nil
		end
		return true, math.floor(v * 20 + 0.5) / 20
	elseif kind == "bool" then
		return type(v) == "boolean", v
	elseif kind == "true" then
		return v == true, v
	elseif kind == "kit" then
		return isId(v, 40) and Kits.Get(v) ~= nil, v
	elseif kind == "map" then
		if not isId(v, 64) then
			return false, nil
		end
		local meta = Registry.Info(v)
		return meta ~= nil and meta.Kind ~= "Lobby" and meta.Available ~= false, v
	end
	return false, nil
end

local function roleOfTeam(team: string): string
	return if team == "Monster" then "Monster" else "Human"
end

-- Strict validation of a client payload. Returns the normalised command or (nil, "admin.err.bad").
function AdminService.Validate(data: any): (any?, string?)
	if type(data) == "string" then
		data = { action = data }
	end
	if type(data) ~= "table" then
		return nil, "admin.err.bad"
	end
	local action = data.action
	local schema = if type(action) == "string" then SCHEMA[action] else nil
	if schema == nil then
		return nil, "admin.err.bad"
	end
	for key in data do
		if key ~= "action" and (type(key) ~= "string" or schema[key] == nil) then
			return nil, "admin.err.bad" -- unknown field
		end
	end
	local cmd: { [string]: any } = { action = action }
	for key, field in schema do
		local value = data[key]
		if value == nil then
			if field.Required then
				return nil, "admin.err.bad"
			end
		else
			local ok, norm = checkField(field, value)
			if not ok then
				return nil, "admin.err.bad"
			end
			cmd[key] = norm
		end
	end
	-- cross-field rules: the kit must belong to the chosen side / team
	if cmd.kitId ~= nil then
		local role = if action == "StartNow" then cmd.side elseif action == "AddBot" then roleOfTeam(cmd.team) else nil
		if role ~= nil and Kits.Get(cmd.kitId).Role ~= role then
			return nil, "admin.err.bad"
		end
	end
	return cmd, nil
end

function AdminService.Actions(): { string }
	local out = {}
	for name in SCHEMA do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

-- StartNow bots: monster side -> human bots 1..8 (nil = Config default); human side -> allies 0..5.
function AdminService.BotsFor(side: string, n: number?): number?
	if type(n) ~= "number" or n ~= n then
		return nil
	end
	if side == "Monster" then
		return math.clamp(math.floor(n), 1, 8)
	end
	return math.clamp(math.floor(n), 0, 5)
end

-- Helpers ----------------------------------------------------------------------------------------------------

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

-- pcall-wrapped service call -> (called ok, result)
local function call(service: any, method: string, ...: any): (boolean, any)
	if type(service) ~= "table" or type(service[method]) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(service[method], ...)
	if not ok then
		warn(("[AdminService] %s failed: %s"):format(method, tostring(result)))
	end
	return ok, result
end

local function yes(service: any, method: string, ...: any): boolean
	local ok, result = call(service, method, ...)
	return ok and result == true
end

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent ~= nil then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

local function textFor(player: Player, localized: any): string
	local RS = S.RequestService
	if RS and type(RS.TextFor) == "function" then
		local ok, s = pcall(RS.TextFor, player, localized)
		if ok and type(s) == "string" and s ~= "" then
			return s
		end
	end
	if type(localized) == "table" then
		return localized.en or ""
	end
	return tostring(localized)
end

local function kitName(player: Player, kitId: any): string
	local def = if type(kitId) == "string" then Kits.Get(kitId) else nil
	return if def then textFor(player, def.Name) else tostring(kitId)
end

local function mapName(player: Player, mapId: string?): string
	if mapId == nil then
		return textFor(player, "admin.map.random")
	end
	local meta = Registry.Info(mapId)
	return if meta then textFor(player, meta.Name) else mapId
end

local function phase(): string
	local ok, p = call(S.RoundService, "Phase")
	return if ok and type(p) == "string" then p else "Waiting"
end

local function inMatch(): boolean
	return yes(S.RoundService, "InMatch")
end

local function alone(): boolean
	return #Players:GetPlayers() < Config.Round.MinPlayers
end

local function ownModel(player: Player): Model?
	local ok, model = call(S.CharacterService, "GetModel", player)
	if ok and typeof(model) == "Instance" then
		return model
	end
	local character = (player :: any).Character
	return if typeof(character) == "Instance" then character else nil
end

local function rootOf(model: Model?): BasePart?
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- (model, humanoid, root) of the player's living character, else nil
local function aliveModel(player: Player): (Model?, Humanoid?, BasePart?)
	local model = ownModel(player)
	if model == nil or model:GetAttribute("Dead") == true then
		return nil, nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = rootOf(model)
	if humanoid == nil or root == nil then
		return nil, nil, nil
	end
	return model, humanoid, root
end

local function liftOf(model: Model): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = rootOf(model)
	if humanoid and root then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

-- ground point under the character, keeping its yaw
local function groundOf(model: Model): CFrame?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	return CFrame.new(root.Position - Vector3.new(0, liftOf(model), 0)) * root.CFrame.Rotation
end

-- ground CFrame `distance` studs in front of the character, facing back at it
local function inFront(model: Model, distance: number, side: number): CFrame?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local ground = root.Position - Vector3.new(0, liftOf(model), 0)
	local pos = ground + look * distance + right * side
	return CFrame.lookAt(pos, Vector3.new(ground.X, pos.Y, ground.Z))
end

local function displayName(model: Model): string
	local name = model:GetAttribute("DisplayName")
	return if type(name) == "string" and name ~= "" then name else model.Name
end

local function isRoundCharacter(model: Model?): boolean
	return model ~= nil and yes(S.RoundService, "IsRoundCharacter", model)
end

local function stateOf(player: Player): AdminState
	local st = states[player]
	if st == nil then
		st = { God = false, NoCooldowns = false, Speed = 1 }
		states[player] = st
	end
	return st
end

local function update(player: Player, fn: (any) -> ()): boolean
	return yes(S.DataService, "Update", player, fn)
end

local function equip(player: Player, role: string, kitId: string): boolean
	if S.DataService == nil then
		player:SetAttribute(if role == "Monster" then "EquippedMonster" else "EquippedHuman", kitId)
		return true
	end
	return update(player, function(p: any)
		if type(p.Equipped) ~= "table" then
			p.Equipped = {}
		end
		p.Equipped[role] = kitId
	end)
end

local function equippedKit(player: Player, role: string): string
	local ok, id = call(S.CharacterService, "EquippedKit", player, role)
	if ok and type(id) == "string" then
		return id
	end
	return if role == "Monster" then Kits.DefaultMonster else Kits.DefaultHuman
end

local function nearest(model: Model, accept: (Model) -> boolean, range: number): Model?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local ok, all = call(S.CharacterService, "GetAll", nil)
	if not ok or type(all) ~= "table" then
		return nil
	end
	local best: Model? = nil
	local bestDist = range
	for _, other in all do
		if other ~= model and other:GetAttribute("Dead") ~= true and accept(other) then
			local r = rootOf(other)
			if r then
				local dist = (r.Position - root.Position).Magnitude
				if dist < bestDist then
					best, bestDist = other, dist
				end
			end
		end
	end
	return best
end

local function kitRole(model: Model): string?
	local ok, def = call(S.CharacterService, "GetKit", model)
	return if ok and type(def) == "table" then def.Role else nil
end

-- statuses ---------------------------------------------------------------------------------------------------

local function applyGod(model: Model)
	call(S.StatusService, "Apply", model, "Invulnerable", STATUS_TIME)
	call(S.StatusService, "Apply", model, "Determined", STATUS_TIME)
end

local function removeGod(model: Model)
	call(S.StatusService, "Remove", model, "Invulnerable")
	call(S.StatusService, "Remove", model, "Determined")
end

local function applySpeed(model: Model, mult: number)
	if mult > 1.001 then
		call(S.StatusService, "Apply", model, "Hasted", STATUS_TIME, { mult = mult })
	else
		call(S.StatusService, "Remove", model, "Hasted")
	end
end

local function applyState(player: Player, model: Model)
	local st = states[player]
	if st == nil or model:GetAttribute("Dead") == true then
		return
	end
	if st.God then
		applyGod(model)
	end
	if st.Speed > 1.001 then
		applySpeed(model, st.Speed)
	end
end

-- practice starts --------------------------------------------------------------------------------------------

local function restoreBotHumans()
	if savedBotHumans ~= nil then
		Config.Practice.BotHumans = savedBotHumans
		savedBotHumans = nil
	end
end

-- RoundService reads Config.Practice.BotHumans while it sets up a monster-side practice: override it for this start
-- only (restored on RoundStarted, a failed start or a timeout).
local function overrideBotHumans(n: number?)
	if n == nil then
		return
	end
	if savedBotHumans == nil then
		savedBotHumans = Config.Practice.BotHumans
	end
	Config.Practice.BotHumans = n
	overrideToken += 1
	local token = overrideToken
	task.delay(WAIT_IDLE + 10, function()
		if token == overrideToken then
			restoreBotHumans()
		end
	end)
end

local function waitUntil(token: number, done: () -> boolean): boolean
	local t0 = os.clock()
	while not done() do
		if token ~= launchToken or os.clock() - t0 > WAIT_IDLE then
			return false
		end
		task.wait(0.2)
	end
	return token == launchToken
end

-- Alone on the server: (abort the match ->) wait for the lobby -> practice round with these settings.
local function launchPractice(player: Player, side: string, bots: number?, mapId: string?)
	launchToken += 1
	local token = launchToken
	solo.Since = os.clock() + WAIT_IDLE -- keep the solo timer away while this start is pending
	task.spawn(function()
		local R = S.RoundService
		if R == nil then
			return
		end
		if inMatch() then
			call(R, "Abort")
		end
		local idle = waitUntil(token, function()
			return not inMatch() and phase() == "Waiting"
		end)
		if token ~= launchToken or player.Parent == nil then
			return
		end
		if not idle then
			notify(player, "admin.err.busy", nil, "Warning")
			return
		end
		if mapId then
			call(R, "ForceNextMap", mapId)
		end
		if side == "Monster" then
			overrideBotHumans(bots)
		end
		local okCall, ok, err = pcall(R.StartPractice, player, side, if side == "Human" then bots else nil)
		if not okCall or ok ~= true then
			restoreBotHumans()
			notify(player, if okCall and type(err) == "string" then err else "admin.err.failed", nil, "Warning")
			solo.Since = os.clock()
		else
			solo.Since = os.clock() + 5 -- the request is picked up within a tick: no solo countdown meanwhile
		end
	end)
end

-- Other players online: normal round now (map forced, role preference), skipping the intermission.
local function launchMulti(player: Player, cmd: any)
	local R = S.RoundService
	if cmd.mapId then
		call(R, "ForceNextMap", cmd.mapId)
	end
	call(S.QueueService, "SetPreference", player, cmd.side)
	launchToken += 1
	local token = launchToken
	task.spawn(function()
		if inMatch() then
			call(R, "Abort")
		end
		if waitUntil(token, function()
			return phase() == "Intermission"
		end) then
			call(R, "SkipPhase")
		end
	end)
end

local function setSoloAttribute()
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Admin") == true then
			p:SetAttribute("AdminSolo", solo.On)
		end
	end
end

-- Handlers: (ok, key?, args?) — success key = Notify toast, failure key = error toast ------------------------

local H: { [string]: (Player, any) -> (boolean, string?, { any }?) } = {}

H.StartNow = function(player: Player, cmd: any)
	local side: string = cmd.side
	if cmd.kitId and not equip(player, side, cmd.kitId) then
		return false, "admin.err.notReady"
	end
	local kitId = cmd.kitId or equippedKit(player, side)
	solo.Side = side
	solo.Bots = cmd.bots
	local args = { kitName(player, kitId), textFor(player, "admin.side." .. side), mapName(player, cmd.mapId) }
	if not alone() then
		launchMulti(player, cmd)
		return true, "admin.ok.startMulti"
	end
	launchPractice(player, side, AdminService.BotsFor(side, cmd.bots), cmd.mapId)
	return true, "admin.ok.start", args
end

H.SetMinPlayers = function(player: Player, cmd: any)
	solo.On = cmd.n == 1
	solo.Owner = if solo.On then player else nil
	solo.Since = os.clock()
	solo.Announced = false
	setSoloAttribute()
	if solo.On then
		return true, "admin.ok.soloOn", { SOLO_DELAY }
	end
	return true, "admin.ok.soloOff"
end

H.SkipPhase = function(_player: Player, _cmd: any)
	if phase() == "Waiting" then
		return false, "admin.err.nothingToSkip"
	end
	call(S.RoundService, "SkipPhase")
	return true, "admin.ok.skip"
end

H.FinalPhase = function(_player: Player, _cmd: any)
	if yes(S.RoundService, "TriggerFinalPhase") then
		return true, "admin.ok.final"
	end
	return false, "admin.err.noFight"
end

H.Collapse = function(_player: Player, _cmd: any)
	if yes(S.RoundService, "ForceCollapse") then
		return true, "admin.ok.collapse"
	end
	return false, "admin.err.noFight"
end

H.EndRound = function(player: Player, cmd: any)
	local winner = cmd.winner or "Humans"
	if yes(S.RoundService, "EndRound", winner, "Aborted") then
		return true,
			"admin.ok.end",
			{ textFor(player, if winner == "Monster" then "admin.side.Monster" else "admin.humans") }
	end
	return false, "admin.err.noRound"
end

H.SetMap = function(player: Player, cmd: any)
	if yes(S.RoundService, "ForceNextMap", cmd.mapId) then
		return true, "admin.ok.map", { mapName(player, cmd.mapId) }
	end
	return false, "admin.err.map"
end

H.AddBot = function(player: Player, cmd: any)
	local model = aliveModel(player)
	local spot = if model then inFront(model, 14, 0) else nil
	local opts = {
		Spawns = if spot then { spot } else nil,
		Team = cmd.team,
		KitIds = if cmd.kitId then { cmd.kitId } else nil,
	}
	local ok, bots = call(S.BotService, "SpawnPracticeBots", roleOfTeam(cmd.team), 1, opts)
	local bot = if ok and type(bots) == "table" then bots[1] else nil
	if bot == nil then
		return false, "admin.err.failed"
	end
	extras[bot] = true
	return true, "admin.ok.bot", { kitName(player, bot:GetAttribute("KitId")) }
end

H.ClearBots = function(_player: Player, _cmd: any)
	local count = 0
	if inMatch() then
		-- the match's own bots stay (removing them would end the round): only the AddBot extras go
		for model in extras do
			if model.Parent ~= nil then
				call(S.CharacterService, "Despawn", model)
				count += 1
			end
		end
	else
		local ok, list = call(S.BotService, "Bots")
		count = if ok and type(list) == "table" then #list else 0
		call(S.BotService, "Clear")
	end
	table.clear(extras)
	return true, "admin.ok.clearBots", { count }
end

H.SpawnDummy = function(player: Player, cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	local count = cmd.count or 1
	local frames: { CFrame } = {}
	for i = 1, count do
		local spot = inFront(model, 12, (i - (count + 1) / 2) * 5)
		if spot then
			table.insert(frames, spot)
		end
	end
	local ok, spawned = call(S.BotService, "SpawnDummies", frames, { Temporary = true })
	if not ok or type(spawned) ~= "table" or #spawned == 0 then
		return false, "admin.err.failed"
	end
	return true, "admin.ok.dummy", { #spawned }
end

H.BecomeKit = function(player: Player, cmd: any)
	local def = Kits.Get(cmd.kitId)
	local role: string = def.Role
	local name = kitName(player, cmd.kitId)
	if not equip(player, role, cmd.kitId) then
		return false, "admin.err.notReady"
	end
	local model = ownModel(player)
	if isRoundCharacter(model) then
		if yes(S.RoundService, "IsPractice") and alone() then
			solo.Side = role
			local okMap, mapId = call(S.MapService, "CurrentId")
			launchPractice(player, role, AdminService.BotsFor(role, solo.Bots), if okMap then mapId else nil)
			return true, "admin.ok.kitRestart", { name }
		end
		return true, "admin.ok.kitNext", { name }
	end
	local at = if model and model:GetAttribute("Dead") ~= true then groundOf(model) else nil
	local ok, spawned = call(S.CharacterService, "SpawnLobby", player, cmd.kitId, at)
	if not ok or spawned == nil then
		return false, "admin.err.failed"
	end
	applyState(player, spawned)
	return true, "admin.ok.kit", { name }
end

H.God = function(player: Player, cmd: any)
	stateOf(player).God = cmd.on
	player:SetAttribute("AdminGod", cmd.on)
	local model = aliveModel(player)
	if model then
		if cmd.on then
			applyGod(model)
		else
			removeGod(model)
		end
	end
	return true, if cmd.on then "admin.ok.godOn" else "admin.ok.godOff"
end

H.Heal = function(player: Player, _cmd: any)
	local model, humanoid = aliveModel(player)
	if model == nil or humanoid == nil then
		return false, "admin.err.noCharacter"
	end
	if model:GetAttribute("Downed") == true then
		call(S.CharacterService, "Revive", model, nil)
	end
	if not call(S.DamageService, "SetHealth", model, humanoid.MaxHealth) then
		humanoid.Health = humanoid.MaxHealth
	end
	if not call(S.DamageService, "CleanseKR", model, nil) then
		model:SetAttribute("KR", 0)
	end
	return true, "admin.ok.heal"
end

H.FullUlt = function(player: Player, _cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	model:SetAttribute("Ult", 100)
	return true, "admin.ok.ult"
end

H.ResetCooldowns = function(player: Player, _cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	call(S.AbilityService, "ResetCooldowns", model)
	return true, "admin.ok.cooldowns"
end

H.NoCooldowns = function(player: Player, cmd: any)
	stateOf(player).NoCooldowns = cmd.on
	player:SetAttribute("AdminNoCooldowns", cmd.on)
	local model = aliveModel(player)
	if model and cmd.on then
		call(S.AbilityService, "ResetCooldowns", model)
	end
	return true, if cmd.on then "admin.ok.noCdOn" else "admin.ok.noCdOff"
end

H.Speed = function(player: Player, cmd: any)
	local mult: number = cmd.mult
	stateOf(player).Speed = mult
	player:SetAttribute("AdminSpeed", mult)
	local model = aliveModel(player)
	if model then
		applySpeed(model, mult)
	end
	return true, "admin.ok.speed", { mult }
end

H.TeleportLobby = function(player: Player, _cmd: any)
	local model = aliveModel(player)
	if model and isRoundCharacter(model) then
		if yes(S.RoundService, "IsPractice") and alone() then
			call(S.RoundService, "Abort")
			return true, "admin.ok.leaveMatch"
		end
		return false, "admin.err.inMatch"
	end
	local okLobby, info = call(S.MapService, "Lobby")
	local spawns = if okLobby and type(info) == "table" then info.HumanSpawns else nil
	if model and type(spawns) == "table" and #spawns > 0 then
		local cf: CFrame = spawns[math.random(1, #spawns)]
		call(S.MovementService, "Teleport", model, cf + Vector3.new(0, liftOf(model), 0))
		return true, "admin.ok.tpLobby"
	end
	local ok, spawned = call(S.CharacterService, "SpawnLobby", player)
	if ok and spawned then
		applyState(player, spawned)
		return true, "admin.ok.tpLobby"
	end
	return false, "admin.err.failed"
end

H.TeleportArena = function(player: Player, _cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	local ok, info = call(S.MapService, "Current")
	if not ok or type(info) ~= "table" then
		return false, "admin.err.noArena"
	end
	local spawns = info.HumanSpawns
	local cf: CFrame = if type(spawns) == "table" and spawns[1] then spawns[1] else CFrame.new(info.Center)
	call(S.MovementService, "Teleport", model, cf + Vector3.new(0, liftOf(model), 0))
	return true, "admin.ok.tpArena"
end

H.AddGold = function(player: Player, cmd: any)
	local total = 0
	local ok = update(player, function(p: any)
		p.Gold = math.clamp((tonumber(p.Gold) or 0) + cmd.n, 0, ProfileSchema.MaxGold)
		total = p.Gold
	end)
	if not ok then
		return false, "admin.err.notReady"
	end
	return true, "admin.ok.gold", { cmd.n, total }
end

H.AddLevels = function(player: Player, cmd: any)
	local level = 1
	local ok = update(player, function(p: any)
		p.Level, p.Exp = Levels.Clamp((tonumber(p.Level) or 1) + cmd.n, 0)
		level = p.Level
	end)
	if not ok then
		return false, "admin.err.notReady"
	end
	return true, "admin.ok.levels", { level }
end

H.UnlockAll = function(player: Player, _cmd: any)
	local kits, skins = 0, 0
	local ok = update(player, function(p: any)
		if type(p.Unlocked) ~= "table" then
			p.Unlocked = {}
		end
		for _, def in Kits.All() do
			p.Unlocked[def.Id] = true
			kits += 1
			for _, skin in def.Skins do
				p.Unlocked[def.Id .. ":" .. skin.Id] = true
				skins += 1
			end
		end
	end)
	if not ok then
		return false, "admin.err.notReady"
	end
	return true, "admin.ok.unlockAll", { kits, skins }
end

H.ResetProfile = function(player: Player, _cmd: any)
	local ok = update(player, function(p: any)
		local settings = if type(p.Settings) == "table" then p.Settings else {}
		local created = p.Created
		local fresh = ProfileSchema.Default()
		table.clear(p)
		for key, value in fresh do
			p[key] = value
		end
		p.Settings = settings
		p.Created = created or 0
	end)
	if not ok then
		return false, "admin.err.notReady"
	end
	return true, "admin.ok.reset"
end

H.BoxNearest = function(player: Player, _cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	if kitRole(model) ~= "Monster" then
		return false, "admin.err.notMonster"
	end
	local target = nearest(model, function(other: Model): boolean
		return other:GetAttribute("Team") ~= "Monster" and not yes(S.VerdictBoxService, "IsBoxed", other)
	end, BOX_RANGE)
	if target == nil then
		return false, "admin.err.noTarget"
	end
	if not yes(S.VerdictBoxService, "Start", model, target) then
		return false, "admin.err.failed"
	end
	return true, "admin.ok.box", { displayName(target) }
end

H.DamageMe = function(player: Player, cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	local god = stateOf(player).God
	if god then
		removeGod(model) -- the test hit must land
	end
	local ok, result =
		call(S.DamageService, "Apply", { Target = model, Amount = cmd.n, Kind = "True", Ability = "Admin" })
	if god then
		applyGod(model)
	end
	if not ok then
		return false, "admin.err.failed"
	end
	local applied = if type(result) == "table" and type(result.Applied) == "number" then result.Applied else cmd.n
	return true, "admin.ok.damage", { math.floor(applied + 0.5) }
end

H.AddKR = function(player: Player, cmd: any)
	local model = aliveModel(player)
	if model == nil then
		return false, "admin.err.noCharacter"
	end
	if not call(S.DamageService, "AddKR", model, cmd.n) then
		return false, "admin.err.failed"
	end
	return true, "admin.ok.kr", { cmd.n }
end

H.GiveDodges0 = function(player: Player, _cmd: any)
	local model = aliveModel(player)
	local target: Model? = nil
	if model and kitRole(model) == "Monster" then
		target = model
	else
		local ok, monster = call(S.RoundService, "GetMonster")
		if ok and typeof(monster) == "Instance" and monster:GetAttribute("Dead") ~= true then
			target = monster
		elseif model then
			target = nearest(model, function(other: Model): boolean
				return other:GetAttribute("Team") == "Monster"
			end, 1000)
		end
	end
	if target == nil then
		return false, "admin.err.noTarget"
	end
	local dodges = tonumber(target:GetAttribute("Dodges")) or 0
	local okDrain, drained = call(S.DamageService, "DrainDodges", target, math.max(dodges, 1), model)
	if not okDrain or drained == 0 then
		call(S.StatusService, "Apply", target, "Exhausted", Config.Monster.ExhaustTime)
	end
	return true, "admin.ok.exhaust", { displayName(target) }
end

-- Request entry point ----------------------------------------------------------------------------------------

-- Studio, the user who owns the place, the private-server owner, or the group owner (rank 255, cached at join).
local function isOwner(player: any): boolean
	local okStudio, studio = pcall(function()
		return RunService:IsStudio()
	end)
	if okStudio and studio == true then
		return true
	end
	local ok, owner = pcall(function(): boolean
		if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
			return true
		end
		return game.PrivateServerId ~= ""
			and game.PrivateServerOwnerId ~= 0
			and game.PrivateServerOwnerId == player.UserId
	end)
	return (ok and owner == true) or groupOwners[player] == true
end

function AdminService.IsAdmin(player: any): boolean
	if player == nil then
		return false
	end
	local userId = player.UserId
	if type(userId) == "number" and type(Config.Admins) == "table" then
		for _, id in Config.Admins do
			if tonumber(id) == userId then
				return true
			end
		end
	end
	-- Style Lab's owner check, unless Style Lab is open to everyone / switched off in this build: admin rights write
	-- SAVED data (gold, unlocks), so they then fall back to the same ownership rules checked here directly
	local labConfig = if type(Config.StyleLab) == "table" then Config.StyleLab else {}
	local lab = S.StyleLabService
	if
		labConfig.AllowEveryone ~= true
		and labConfig.Enabled ~= false
		and type(lab) == "table"
		and type(lab.IsAllowed) == "function"
	then
		local ok, allowed = pcall(lab.IsAllowed, player)
		return ok and allowed == true
	end
	return isOwner(player)
end

local function summary(cmd: { [string]: any }): string
	local keys = {}
	for key in cmd do
		if key ~= "action" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		table.insert(parts, key .. "=" .. tostring(cmd[key]))
	end
	return table.concat(parts, " ")
end

function AdminService.Handle(player: Player, data: any): (boolean, string?, { any }?)
	if not AdminService.IsAdmin(player) then
		local now = os.clock()
		if (deniedLogged[player] or -math.huge) < now - 30 then -- one log line per player per 30 s (spam-proof)
			deniedLogged[player] = now
			print(("[Admin] DENIED %s (%s)"):format(tostring(player.Name), tostring(player.UserId)))
		end
		return false, "admin.err.denied"
	end
	local cmd, err = AdminService.Validate(data)
	if cmd == nil then
		return false, err or "admin.err.bad"
	end
	local action: string = cmd.action
	print(("[Admin] %s (%s) %s %s"):format(player.Name, tostring(player.UserId), action, summary(cmd)))
	local okCall, ok, key, args = pcall(H[action], player, cmd)
	if not okCall then
		warn(("[AdminService] %s failed: %s"):format(action, tostring(ok)))
		return false, "admin.err.failed"
	end
	if ok == true then
		if type(key) == "string" then
			notify(player, key, args, "Success")
		end
		return true, nil, nil
	end
	return false, if type(key) == "string" then key else "admin.err.failed", args
end

-- Lifecycle --------------------------------------------------------------------------------------------------

local function refresh(player: Player)
	local admin = AdminService.IsAdmin(player)
	player:SetAttribute("Admin", admin)
	if admin then
		player:SetAttribute("AdminSolo", solo.On)
	end
end

local function onPlayerAdded(player: Player)
	refresh(player)
	player:GetAttributeChangedSignal("StyleLab"):Connect(function()
		refresh(player)
	end)
	if game.CreatorType == Enum.CreatorType.Group then
		task.spawn(function()
			local ok, groups = pcall(function()
				return game:GetService("GroupService"):GetGroupsAsync(player.UserId)
			end)
			if ok and type(groups) == "table" then
				for _, g in groups do
					if type(g) == "table" and g.Id == game.CreatorId and type(g.Rank) == "number" and g.Rank >= 255 then
						groupOwners[player] = true
					end
				end
			end
			if groupOwners[player] and player.Parent then
				refresh(player)
			end
		end)
	end
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
	deniedLogged[player] = nil
	groupOwners[player] = nil
	if solo.Owner == player then
		solo.Owner = nil
		for _, p in Players:GetPlayers() do
			if p ~= player and p:GetAttribute("Admin") == true then
				solo.Owner = p
				break
			end
		end
		if solo.Owner == nil then
			solo.On = false
		end
	end
end

local function soloTick()
	local owner = solo.Owner
	if not solo.On or owner == nil or owner.Parent == nil then
		return
	end
	if phase() ~= "Waiting" or inMatch() or not alone() then
		solo.Since = math.max(solo.Since, os.clock())
		solo.Announced = false
		return
	end
	local waited = os.clock() - solo.Since
	if waited < 0 then
		return
	end
	if not solo.Announced then
		solo.Announced = true
		notify(owner, "admin.solo.soon", { math.max(1, math.ceil(SOLO_DELAY - waited)) }, "Info")
	end
	if waited >= SOLO_DELAY then
		solo.Announced = false
		launchPractice(owner, solo.Side, AdminService.BotsFor(solo.Side, solo.Bots), nil)
	end
end

local function refreshLoop()
	while true do
		task.wait(REFRESH)
		for player in states do
			if player.Parent == nil then
				states[player] = nil
			else
				local model = ownModel(player)
				if model then
					pcall(applyState, player, model)
				end
			end
		end
		local ok, err = pcall(soloTick)
		if not ok then
			warn("[AdminService] solo tick: " .. tostring(err))
		end
	end
end

local function connect(service: any, signalName: string, fn: (...any) -> ())
	local signal = if type(service) == "table" then service[signalName] else nil
	if type(signal) == "table" and type(signal.Connect) == "function" then
		pcall(function()
			signal:Connect(fn)
		end)
	end
end

local function setupChatCommand()
	local TextChatService = game:GetService("TextChatService")
	local folder = Instance.new("Folder")
	folder.Name = "AdminCommands"
	local command = Instance.new("TextChatCommand")
	command.Name = "SV_admin"
	command.PrimaryAlias = "/admin"
	command.AutocompleteVisible = false
	command.Triggered:Connect(function(source: TextSource, _text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player == nil then
			return
		end
		if not AdminService.IsAdmin(player) then
			notify(player, "admin.err.denied", nil, "Warning")
			return
		end
		local n = player:GetAttribute("AdminOpen")
		player:SetAttribute("AdminOpen", (if type(n) == "number" then n else 0) + 1)
	end)
	command.Parent = folder
	folder.Parent = TextChatService
end

-- Tests: inject service mocks (merged into the resolved services; nil values are ignored).
function AdminService._SetServices(services: { [string]: any })
	for name, service in services do
		S[name] = service
	end
end

function AdminService.Init()
	for _, name in SERVICE_NAMES do
		if S[name] == nil then
			S[name] = tryService(name)
		end
	end
	local RS = S.RequestService
	if RS and type(RS.Register) == "function" then
		local ok, err = pcall(RS.Register, "Admin", AdminService.Handle)
		if not ok then
			warn("[AdminService] registration failed: " .. tostring(err))
		end
	end
end

function AdminService.Start()
	connect(S.CharacterService, "Spawned", function(model: Model, player: Player?)
		if player and states[player] then
			pcall(applyState, player, model)
		end
	end)
	connect(S.AbilityService, "Casted", function(model: Model, _abilityId: string)
		local ok, player = call(S.CharacterService, "GetPlayer", model)
		if ok and player and states[player] and states[player].NoCooldowns then
			task.defer(function()
				call(S.AbilityService, "ResetCooldowns", model)
			end)
		end
	end)
	connect(S.RoundService, "RoundStarted", function()
		restoreBotHumans()
	end)
	local okChat, chatErr = pcall(setupChatCommand)
	if not okChat then
		warn("[AdminService] /admin chat command unavailable: " .. tostring(chatErr))
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	task.spawn(refreshLoop)
end

return AdminService
