--!strict
-- EmoteService (P62): the server side of emotes. Registers the Request action "Emote" with RequestService
-- (data: clip name | {clip} | "" / {clip = ""} = stop) and drives the character attribute "Emote" (clip name, "" =
-- none) that AnimController plays on every client (Emote_* / Victory loop until cleared, Taunt / Wink are one-shots).
--   Validation: the clip is in Config.Emote.Common or Config.Emote.Family[RigFamily]; the character is alive and up;
--   in the lobby (Team "Lobby") always allowed, in a match only while not combat-locked (Stunned, Boxed, Rooted,
--   Silenced statuses, Blocking); at most one accepted request per Config.Emote.Cooldown per player.
--   Ends ("" again): horizontal movement faster than Config.Emote.MoveSpeed or leaving the ground, a cast
--   (AbilityService.Casted), blocking / getting downed / combat-locked, or after the clip (one-shots: its Length from
--   Shared/Anim/Clips/<RigFamily>; loops: Config.Emote.MaxLoopTime). Switching emotes clears the attribute first and
--   sets the new clip a moment later, so clients never blend two emotes.
--
-- API
--   EmoteService.Play(model, clip) -> (boolean, string?)   same validation as the request (no cooldown); err key
--   EmoteService.Stop(model)                                EmoteService.Active(model) -> string?
-- Pure helpers (Lune-tested)
--   EmoteService.Allowed(family?) -> {string}               clip names for a RigFamily (Common + family extras)
--   EmoteService.ParseClip(data) -> string?                 request payload -> clip ("" = stop), nil = malformed
--   EmoteService.Validate(info, clip, now) -> (boolean, string?)   info = { Family, Team, Up, Locked, LastAt }
--   EmoteService.EndReason(info, endsAt, now) -> string?    info = { Up, Locked, Speed, Airborne }
--   EmoteService.Duration(family, clip) -> number           seconds the attribute stays set

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared") :: any
local Config = require(Shared.Config) :: any

local EmoteService = {}
EmoteService.Priority = 62

local ATTRIBUTE = "Emote"
local LOCKING = { "Stunned", "Boxed", "Rooted", "Silenced" }
local SWITCH_GAP = 0.12 -- "" first, then the new clip (two replication frames: no blended emotes)
local ONE_SHOT_PAD = 0.1
local TICK = 0.1
local AIRBORNE_SPEED = 6 -- studs/s of vertical root speed = jumping / falling

type Active = { Clip: string, EndsAt: number, Player: Player? }

local active: { [Model]: Active } = {}
local lastAccepted: { [Player]: number } = {}
local switchToken: { [Model]: number } = {}

local Validation: any = nil
local StatusService: any = nil
local AbilityService: any = nil

local function cfg(): any
	return Config.Emote or {}
end

local function now(): number
	if Validation and type(Validation.Now) == "function" then
		return Validation.Now()
	end
	return os.clock()
end

---------------------------------------------------------------------------------------------------
-- Pure helpers

function EmoteService.Allowed(family: string?): { string }
	local c = cfg()
	local out: { string } = {}
	for _, clip in c.Common or {} do
		table.insert(out, clip)
	end
	local extras = if type(family) == "string" and type(c.Family) == "table" then c.Family[family] else nil
	for _, clip in extras or {} do
		if not table.find(out, clip) then
			table.insert(out, clip)
		end
	end
	return out
end

function EmoteService.ParseClip(data: any): string?
	local v = data
	if type(data) == "table" then
		v = data.clip or data.Clip or data.emote
	end
	if type(v) ~= "string" or #v > 32 then
		return nil
	end
	return v
end

-- info = { Family: string?, Team: string?, Up: boolean, Locked: boolean, LastAt: number? }
function EmoteService.Validate(info: { [string]: any }, clip: string, t: number): (boolean, string?)
	if clip == "" then
		return true, nil -- stopping is always fine
	end
	if not table.find(EmoteService.Allowed(info.Family), clip) then
		return false, "badClip"
	end
	if info.Up ~= true then
		return false, "down"
	end
	if info.Team ~= "Lobby" and info.Locked == true then
		return false, "busy"
	end
	local last = info.LastAt
	if type(last) == "number" and t - last < (cfg().Cooldown or 1.2) then
		return false, "cooldown"
	end
	return true, nil
end

-- info = { Up: boolean, Locked: boolean, Speed: number (horizontal studs/s), Airborne: boolean }
function EmoteService.EndReason(info: { [string]: any }, endsAt: number, t: number): string?
	if info.Up ~= true then
		return "down"
	end
	if info.Locked == true then
		return "locked"
	end
	if type(info.Speed) == "number" and info.Speed > (cfg().MoveSpeed or 2.5) then
		return "moved"
	end
	if info.Airborne == true then
		return "jumped"
	end
	if t >= endsAt then
		return "finished"
	end
	return nil
end

local clipLibs: { [string]: any } = {}

local function clipLib(family: string): any?
	local lib = clipLibs[family]
	if lib == nil then
		lib = false
		local anim = Shared:FindFirstChild("Anim")
		local clips = anim and anim:FindFirstChild("Clips")
		local m = clips and clips:FindFirstChild(family)
		if m and m:IsA("ModuleScript") then
			local ok, r = pcall(require, m)
			if ok and type(r) == "table" then
				lib = r
			end
		end
		clipLibs[family] = lib
	end
	return lib or nil
end

function EmoteService.Duration(family: string?, clip: string): number
	local c = cfg()
	local loop = c.MaxLoopTime or 30
	local lib = clipLib(if type(family) == "string" then family else "Human")
	local def = if lib then lib[clip] else nil
	if type(def) == "table" then
		if def.Loop == true then
			return loop
		end
		if type(def.Length) == "number" and def.Length > 0 then
			return def.Length + ONE_SHOT_PAD
		end
	end
	return if string.sub(clip, 1, 6) == "Emote_" or clip == "Victory" then loop else 2
end

---------------------------------------------------------------------------------------------------
-- Model state

local function familyOf(model: Model): string
	local f = model:GetAttribute("RigFamily")
	return if type(f) == "string" and f ~= "" then f else "Human"
end

local function teamOf(model: Model): string
	if Validation and type(Validation.Team) == "function" then
		return Validation.Team(model)
	end
	local t = model:GetAttribute("Team")
	return if type(t) == "string" then t else ""
end

local function isUp(model: Model): boolean
	if Validation and type(Validation.IsUp) == "function" then
		return Validation.IsUp(model) == true
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model:GetAttribute("Downed") ~= true and model:GetAttribute("Dead") ~= true
end

local function isLocked(model: Model): boolean
	if model:GetAttribute("Blocking") == true then
		return true
	end
	if StatusService and type(StatusService.Has) == "function" then
		for _, name in LOCKING do
			if StatusService.Has(model, name) then
				return true
			end
		end
	end
	return false
end

-- (horizontal speed, airborne) from the replicated root velocity (the owner client simulates player characters,
-- so server-side humanoid floor state is not trusted; a jump / fall shows up as vertical speed)
local function motionOf(model: Model): (number, boolean)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local v = root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude, math.abs(v.Y) > AIRBORNE_SPEED
	end
	return 0, false
end

function EmoteService.Active(model: Model): string?
	local a = active[model]
	return if a then a.Clip else nil
end

function EmoteService.Stop(model: Model)
	switchToken[model] = (switchToken[model] or 0) + 1
	active[model] = nil
	if model:GetAttribute(ATTRIBUTE) ~= nil and model:GetAttribute(ATTRIBUTE) ~= "" then
		model:SetAttribute(ATTRIBUTE, "")
	end
end

local function begin(model: Model, clip: string, player: Player?)
	local family = familyOf(model)
	local token = (switchToken[model] or 0) + 1
	switchToken[model] = token
	local function apply()
		if switchToken[model] ~= token or model.Parent == nil then
			return
		end
		active[model] = { Clip = clip, EndsAt = now() + EmoteService.Duration(family, clip), Player = player }
		model:SetAttribute(ATTRIBUTE, clip)
	end
	local current = model:GetAttribute(ATTRIBUTE)
	if type(current) == "string" and current ~= "" then
		active[model] = nil
		model:SetAttribute(ATTRIBUTE, "")
		task.delay(SWITCH_GAP, apply)
	else
		apply()
	end
end

-- Validation without the per-player cooldown (bots, tools). Returns (ok, reason?).
function EmoteService.Play(model: Model, clip: string): (boolean, string?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false, "badModel"
	end
	local ok, reason = EmoteService.Validate({
		Family = familyOf(model),
		Team = teamOf(model),
		Up = isUp(model),
		Locked = isLocked(model),
	}, clip, now())
	if not ok then
		return false, reason
	end
	if clip == "" then
		EmoteService.Stop(model)
	else
		begin(model, clip, Players:GetPlayerFromCharacter(model))
	end
	return true, nil
end

local ERROR_KEYS = { badClip = "prog.err.badRequest", down = "hud.emote.busy", busy = "hud.emote.busy" }

local function onRequest(player: Player, data: any): (boolean, string?, { any }?)
	local clip = EmoteService.ParseClip(data)
	if clip == nil then
		return false, "prog.err.badRequest"
	end
	local model = player.Character
	if model == nil or model.Parent == nil then
		return false, nil
	end
	local t = now()
	local ok, reason = EmoteService.Validate({
		Family = familyOf(model),
		Team = teamOf(model),
		Up = isUp(model),
		Locked = isLocked(model),
		LastAt = if clip ~= "" then lastAccepted[player] else nil,
	}, clip, t)
	if not ok then
		return false, if reason then ERROR_KEYS[reason] else nil -- cooldown: silent
	end
	if clip == "" then
		EmoteService.Stop(model)
	else
		lastAccepted[player] = t
		begin(model, clip, player)
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- Upkeep

local acc = 0
local function step(dt: number)
	acc += dt
	if acc < TICK then
		return
	end
	acc = 0
	local t = now()
	for model, a in active do
		if model.Parent == nil then
			active[model] = nil
			switchToken[model] = nil
			continue
		end
		local speed, airborne = motionOf(model)
		local reason = EmoteService.EndReason({
			Up = isUp(model),
			Locked = isLocked(model),
			Speed = speed,
			Airborne = airborne,
		}, a.EndsAt, t)
		if reason then
			EmoteService.Stop(model)
		end
	end
end

function EmoteService.Init()
	local combat = script.Parent.Parent:FindFirstChild("Combat")
	local v = combat and combat:FindFirstChild("Validation")
	if v and v:IsA("ModuleScript") then
		local ok, r = pcall(require, v)
		if ok then
			Validation = r
		end
	end
	local function service(name: string): any
		local m = script.Parent:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local ok, r = pcall(require, m)
			if ok and type(r) == "table" then
				return r
			end
		end
		return nil
	end
	StatusService = service("StatusService")
	AbilityService = service("AbilityService")
	local RequestService = service("RequestService")
	if RequestService and type(RequestService.Register) == "function" then
		local ok, err = pcall(RequestService.Register, "Emote", onRequest)
		if not ok then
			warn("[EmoteService] Emote registration failed: " .. tostring(err))
		end
	end
end

function EmoteService.Start()
	if AbilityService and AbilityService.Casted and type(AbilityService.Casted.Connect) == "function" then
		AbilityService.Casted:Connect(function(model: Model)
			if active[model] then
				EmoteService.Stop(model)
			end
		end)
	end
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAccepted[player] = nil
	end)
end

return EmoteService
