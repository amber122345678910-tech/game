--!strict
-- FxController (client controller, Priority 30): every piece of combat feedback on this client.
--   * Net "AbilityFx"  -> cast clip on the caster (unless predicted locally) + client kit Effects[ability](fx, packet)
--                         (src/client/Kits/<KitId>.luau, SPEC §9.1); built-in Dash / Teleport visuals.
--   * Net "Hazard" / "HazardEnd" -> HazardVisuals.Spawn / End.
--   * Net "DamageFx"   -> hit sparks + flash (colour rule / kit colour), damage numbers, MISS (grey) for dodges with
--                         the monster's lazy side-step afterimage, parry flash + clank, guard-break shatter, heals,
--                         local-victim screen effects (red vignette, shake, kick), hit-stop on attacker and victim,
--                         flinch clips; kit hook OnDamageFx(fx, packet) for the TARGET's kit.
--   * KR ticks         -> small purple numbers for HP drained by KR (health drops not explained by a DamageFx).
--   * Deaths           -> monster: freeze, then dust-away from top to bottom; human: SOUL appears at the Chest,
--                         cracks (SoulBroken halves) and shatters into shards (Undertale timing). Downed humans carry
--                         a cracked SOUL; revives burst it back. Triggered by the Dead attribute or RoundEvent "Kill".
--   * Status visuals   -> stun stars, block shimmer, blue SOUL heart (SoulMode "Blue"), exhausted sweat; local
--                         screen states (KR purple edges, low-HP heartbeat, blue edges).
--
-- API
--   FxController.Context(character?) -> FxContext       (SPEC §9.1; cached per character)
--   FxController.Kit(kitId) -> client kit module?       (lazy require of Kits/<kitId>, pcall)
--   FxController.MarkPredicted(castId, abilityId?)      FxController.WasPredicted(castId) -> boolean
--   FxController.Predict(abilityId, payload) -> boolean (local character's kit Predict)
--   FxController.Indicator(abilityId) -> indicator?     (local character's kit Indicator)
--   FxController.CastClip(ability, combo?) -> string?   (PURE: "Slash1" + combo 3 -> "Slash3")
--   FxController.PlayCastClip(character, ability, combo?)   FxController.PlayDash(character, dir, predicted?)
--   FxController.Shake(intensity, duration)  .ShakeAt(pos, intensity, duration, radius?)  .Kick(fov, duration)
--   FxController.Flash(color, alpha, duration)  .Sound(name, at?, opts?)  .HitStop(model, duration)
--   FxController.EyeGlow(character, side, color?, on)   FxController.Death(model)
--   FxController.LocalCharacter() -> Model?
--   Signals: FxController.DamageFx (packet), FxController.AbilityFx (packet), FxController.Died (model)
-- FxContext fields: Character, IsLocal, Kit, Packet, Predicted, State (per-character table), Trove (per-character,
--   cleaned on despawn), Now(), Anim (AnimController proxy: Play/Stop/HitStop/SetAim never error), VFX (VFX/Lib),
--   Hazards (HazardVisuals), Screen (VFX/ScreenFX), Numbers (VFX/DamageNumbers), Shake, ShakeAt, Kick, Flash,
--   Sound, Debris, Delay, Attachment(character, name), Part(character, name), Root(model), EyeGlow, Color(rule),
--   KitColor(model), LocalCharacter(), IsEnemy(model), HitStop(model, d), Highlight(model, color, duration),
--   Combat() -> CombatController?
-- Client kits may also export OnDamageFx(fx, packet) (called for packets whose TARGET uses that kit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove")) :: any
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any

local ClientRoot = script.Parent.Parent
local VFX = ClientRoot:WaitForChild("VFX")
local Lib = require(VFX:WaitForChild("Lib")) :: any
local ScreenFX = require(VFX:WaitForChild("ScreenFX")) :: any
local DamageNumbers = require(VFX:WaitForChild("DamageNumbers")) :: any

local FxController = {}
FxController.Priority = 30
FxController.DamageFx = Signal.new()
FxController.AbilityFx = Signal.new()
FxController.Died = Signal.new()

type Map = { [string]: any }

---------------------------------------------------------------------------------------------------
-- Lazy controllers

local cache: { [string]: any } = {}
local function controller(name: string): any?
	local c = cache[name]
	if c ~= nil then
		return c or nil
	end
	local m = script.Parent:FindFirstChild(name)
	local result: any = false
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then
			result = r
		end
	end
	cache[name] = result
	if result == false then
		task.delay(5, function()
			if cache[name] == false then
				cache[name] = nil
			end
		end)
	end
	return result or nil
end

local function call(name: string, fn: string, ...: any): any
	local c = controller(name)
	if c and type(c[fn]) == "function" then
		local ok, r = pcall(c[fn], ...)
		if ok then
			return r
		end
		warn(("[FxController] %s.%s failed: %s"):format(name, fn, tostring(r)))
	end
	return nil
end

local function hazards(): any?
	return controller("HazardVisuals")
end

---------------------------------------------------------------------------------------------------
-- Basic helpers

function FxController.LocalCharacter(): Model?
	local lp = Players.LocalPlayer
	return if lp then lp.Character else nil
end

local function rootOf(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	local p = model.PrimaryPart
	return p
end

local function attachment(model: Model?, name: string): Attachment?
	if model == nil then
		return nil
	end
	local a = model:FindFirstChild(name, true)
	if a and a:IsA("Attachment") then
		return a
	end
	return nil
end

local function partOf(model: Model?, name: string): BasePart?
	if model == nil then
		return nil
	end
	local p = model:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function humanoidOf(model: Model?): Humanoid?
	if model == nil then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

local function chestPos(model: Model): Vector3?
	local a = attachment(model, "Chest")
	if a then
		return a.WorldPosition
	end
	local t = partOf(model, "UpperTorso")
	if t then
		return t.Position
	end
	local r = rootOf(model)
	return if r then r.Position + Vector3.new(0, 0.6, 0) else nil
end

local function headPos(model: Model): Vector3?
	local h = partOf(model, "Head")
	if h then
		return h.Position + Vector3.new(0, h.Size.Y * 0.6, 0)
	end
	local r = rootOf(model)
	return if r then r.Position + Vector3.new(0, 2.5, 0) else nil
end

local function teamOf(model: Model?): string
	if model == nil then
		return ""
	end
	local t = model:GetAttribute("Team")
	return if type(t) == "string" then t else ""
end

local function isMonster(model: Model?): boolean
	return teamOf(model) == "Monster" or (model ~= nil and model:GetAttribute("RigFamily") == "Skeleton")
end

local function statusActive(model: Model, name: string): boolean
	local v = model:GetAttribute("Status_" .. name)
	return type(v) == "number" and v > Lib.Now()
end

function FxController.Shake(intensity: number, duration: number)
	call("CameraController", "Shake", intensity, duration)
end

function FxController.Kick(fovDelta: number, duration: number)
	call("CameraController", "Kick", fovDelta, duration)
end

function FxController.ShakeAt(pos: Vector3, intensity: number, duration: number, radius: number?)
	local r = radius or 30
	local lc = FxController.LocalCharacter()
	local root = rootOf(lc)
	local v = if root then root.Position else nil
	if v == nil then
		local cam = game:GetService("Workspace").CurrentCamera
		v = if cam then cam.CFrame.Position else nil
	end
	if v == nil then
		return
	end
	local d = (v - pos).Magnitude
	if d < r then
		FxController.Shake(intensity * (1 - d / r), duration)
	end
end

function FxController.Flash(color: Color3, alpha: number, duration: number)
	ScreenFX.Flash(color, alpha, duration)
end

function FxController.Sound(name: string, at: any?, opts: any?): any
	return call("SoundController", "Play", name, at, opts)
end

function FxController.HitStop(model: Model?, duration: number)
	if model == nil or duration <= 0 then
		return
	end
	call("AnimController", "HitStop", model, duration)
end

-- AnimController proxy that never errors (AnimController may still be missing while it is being written).
local NULL_TRACK = {
	Stop = function(_fade: number?) end,
	Ended = Signal.new(),
}
local AnimProxy = {}
function AnimProxy.Play(character: Model, clip: string, opts: any?): any
	local r = call("AnimController", "Play", character, clip, opts)
	return r or NULL_TRACK
end
function AnimProxy.Stop(character: Model, clip: string, fade: number?)
	call("AnimController", "Stop", character, clip, fade)
end
function AnimProxy.HitStop(character: Model, duration: number)
	call("AnimController", "HitStop", character, duration)
end
function AnimProxy.SetAim(character: Model, point: Vector3?)
	call("AnimController", "SetAim", character, point)
end
FxController.Anim = AnimProxy

-- Highlights are expensive and capped (SPEC §14): at most MAX_HIGHLIGHTS FX highlights at once.
local MAX_HIGHLIGHTS = 10
local liveHighlights = 0
local function highlight(model: Model, color: Color3, duration: number, opts: Map?): Highlight?
	if liveHighlights >= MAX_HIGHLIGHTS or model.Parent == nil then
		return nil
	end
	local o = opts or {}
	local h = Instance.new("Highlight")
	h.Name = "SV_FxHighlight"
	h.Adornee = model
	h.FillColor = color
	h.FillTransparency = o.Fill or 0.55
	h.OutlineColor = o.Outline or color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = Lib.Folder()
	liveHighlights += 1
	local start = o.Fill or 0.55
	Lib.Animate(duration, function(a)
		local k = if a < 0.6 then 0 else (a - 0.6) / 0.4
		h.FillTransparency = start + (1 - start) * k
		h.OutlineTransparency = k
		return nil
	end, function()
		liveHighlights -= 1
		h:Destroy()
	end)
	return h
end

---------------------------------------------------------------------------------------------------
-- Client kits

local kitModules: { [string]: any } = {}
function FxController.Kit(kitId: string?): any?
	if type(kitId) ~= "string" or kitId == "" then
		return nil
	end
	local m = kitModules[kitId]
	if m ~= nil then
		return m or nil
	end
	local folder = ClientRoot:FindFirstChild("Kits")
	local mod = folder and folder:FindFirstChild(kitId)
	local result: any = false
	if mod and mod:IsA("ModuleScript") then
		local ok, r = pcall(require, mod)
		if ok and type(r) == "table" then
			result = r
		else
			warn("[FxController] client kit " .. kitId .. " failed to load: " .. tostring(r))
		end
	end
	kitModules[kitId] = result
	return result or nil
end

---------------------------------------------------------------------------------------------------
-- Eye glow (Sans attack eye)

local eyeHandles: { [Model]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

function FxController.EyeGlow(character: Model?, side: string, color: Color3?, on: boolean)
	if character == nil then
		return
	end
	local sides = if side == "Both" then { "Left", "Right" } else { side }
	local per = eyeHandles[character]
	if per == nil then
		per = {}
		eyeHandles[character] = per
	end
	for _, s in sides do
		local key = s .. (if color then "|" .. color:ToHex() else "")
		local h = per[s]
		if h and h.Key ~= key then
			h.Handle:Destroy()
			per[s] = nil
			h = nil
		end
		if on then
			if h == nil then
				local att = attachment(character, s .. "Eye")
				if att then
					local pupil = partOf(character, s .. "Pupil")
					local colors = if color then { color, color:Lerp(Color3.new(1, 1, 1), 0.35) } else nil
					local handle = Lib.EyeFlame(att, { Pupil = pupil, Colors = colors })
					h = { Handle = handle, Key = key }
					per[s] = h
				end
			end
			if h then
				h.Handle:SetEnabled(true)
			end
		elseif h then
			h.Handle:SetEnabled(false)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- FxContext

local contexts: { [any]: Map } = setmetatable({}, { __mode = "k" }) :: any
local troves: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any
local NO_CHAR = {}

local function troveFor(model: Model?): any
	if model == nil then
		return Trove.new()
	end
	local t = troves[model]
	if t == nil then
		t = Trove.new()
		troves[model] = t
	end
	return t
end

function FxController.Context(character: Model?): Map
	local key = character or NO_CHAR
	local fx = contexts[key]
	if fx == nil then
		local kitId = if character then character:GetAttribute("KitId") else nil
		fx = {
			Character = character,
			Kit = if type(kitId) == "string" then Kits.Get(kitId) else nil,
			Packet = nil,
			Predicted = false,
			State = {},
			Trove = troveFor(character),
			Now = Lib.Now,
			Anim = AnimProxy,
			VFX = Lib,
			Screen = ScreenFX,
			Numbers = DamageNumbers,
			Shake = FxController.Shake,
			ShakeAt = FxController.ShakeAt,
			Kick = FxController.Kick,
			Flash = FxController.Flash,
			Sound = FxController.Sound,
			Debris = Lib.Debris,
			Delay = function(seconds: number, fn: () -> ())
				task.delay(seconds, function()
					local ok, err = pcall(fn)
					if not ok then
						warn("[FxController] fx.Delay callback failed: " .. tostring(err))
					end
				end)
			end,
			Attachment = attachment,
			Part = partOf,
			Root = rootOf,
			Chest = chestPos,
			EyeGlow = FxController.EyeGlow,
			Color = Lib.Color,
			KitColor = Lib.KitColor,
			LocalCharacter = FxController.LocalCharacter,
			IsEnemy = function(model: Model?): boolean
				local lc = FxController.LocalCharacter()
				if lc == nil or model == nil then
					return false
				end
				local ok, r = pcall(Teams.AreEnemies, lc, model)
				return ok and r == true
			end,
			HitStop = FxController.HitStop,
			Highlight = highlight,
			Combat = function(): any?
				return controller("CombatController")
			end,
		}
		contexts[key] = fx
	end
	fx.Hazards = hazards()
	fx.IsLocal = character ~= nil and character == FxController.LocalCharacter()
	fx.Predicted = false
	fx.Packet = nil
	return fx
end

---------------------------------------------------------------------------------------------------
-- Prediction bookkeeping

local predicted: { [number]: { Ability: string?, T: number } } = {}
local lastLocalDash = -math.huge

function FxController.MarkPredicted(castId: number, abilityId: string?)
	if type(castId) ~= "number" or castId == 0 then
		return
	end
	predicted[castId] = { Ability = abilityId, T = os.clock() }
	-- forget old entries
	for id, e in predicted do
		if os.clock() - e.T > 6 then
			predicted[id] = nil
		end
	end
end

function FxController.WasPredicted(castId: number): boolean
	return predicted[castId] ~= nil
end

function FxController.Predict(abilityId: string, payload: Map): boolean
	local char = FxController.LocalCharacter()
	if char == nil then
		return false
	end
	local kit = FxController.Kit(char:GetAttribute("KitId") :: any)
	local fn = kit and kit.Predict and kit.Predict[abilityId]
	if type(fn) ~= "function" then
		return false
	end
	local fx = FxController.Context(char)
	fx.Predicted = true
	task.spawn(function()
		local ok, err = pcall(fn, fx, payload)
		if not ok then
			warn("[FxController] Predict " .. abilityId .. " failed: " .. tostring(err))
		end
	end)
	return true
end

function FxController.Indicator(abilityId: string): any?
	local char = FxController.LocalCharacter()
	if char == nil then
		return nil
	end
	local kit = FxController.Kit(char:GetAttribute("KitId") :: any)
	local fn = kit and kit.Indicator and kit.Indicator[abilityId]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, ind = pcall(fn, FxController.Context(char))
	if ok and type(ind) == "table" then
		return ind
	end
	if not ok then
		warn("[FxController] Indicator " .. abilityId .. " failed: " .. tostring(ind))
	end
	return nil
end

-- PURE: clip for a cast, cycling Slash/Punch/Kick variants through the combo.
function FxController.CastClip(ability: Map?, combo: number?): string?
	if ability == nil or type(ability.Clip) ~= "string" then
		return nil
	end
	local clip: string = ability.Clip
	local c = combo or 1
	if c > 1 then
		local base, n = string.match(clip, "^(%a+)(%d)$")
		if base and n and (base == "Slash" or base == "Punch" or base == "Kick") then
			local maxN = if base == "Kick" then 3 else 4
			local idx = ((tonumber(n) :: number) - 1 + c - 1) % maxN + 1
			return base .. tostring(idx)
		end
	end
	return clip
end

function FxController.PlayCastClip(character: Model, ability: Map?, combo: number?)
	local clip = FxController.CastClip(ability, combo)
	if clip then
		AnimProxy.Play(character, clip, { FadeIn = 0.06 })
	end
end

---------------------------------------------------------------------------------------------------
-- Built-in ability visuals

function FxController.PlayDash(character: Model, dir: Vector3?, isPrediction: boolean?)
	if character == FxController.LocalCharacter() then
		if isPrediction then
			lastLocalDash = os.clock()
		elseif os.clock() - lastLocalDash < 0.5 then
			return -- already shown by the local prediction
		end
	end
	local root = rootOf(character)
	if root == nil then
		return
	end
	local color = Lib.KitColor(character) or Lib.Colors.White
	Lib.Afterimage(character, color, 0.32, { Transparency = 0.45, MaxParts = 18 })
	task.delay(0.07, function()
		if character.Parent then
			Lib.Afterimage(character, color, 0.28, { Transparency = 0.6, MaxParts = 14 })
		end
	end)
	local feet = root.Position - Vector3.new(0, 2.6, 0)
	Lib.Dust(feet, 1.2, nil, 6)
	local d = if dir and dir.Magnitude > 1e-3 then dir.Unit else root.CFrame.LookVector
	Lib.Emit("Mote", root.Position, 6, { Color = color, Dir = -d })
	FxController.Sound("Dash", root)
end

local function genericTeleport(packet: Map)
	local data = packet.data or {}
	local caster: Model = packet.caster
	local color = Lib.KitColor(caster) or Lib.Colors.Cyan
	if typeof(data.from) == "Vector3" then
		Lib.Flash(data.from, color, 3, 0.2)
		Lib.Emit("Mote", data.from, 10, { Color = color })
	end
	if typeof(data.to) == "Vector3" then
		Lib.Flash(data.to, color, 3.5, 0.25)
		Lib.EmitRing(data.to - Vector3.new(0, 2.6, 0), 3, color, 0.3)
	end
	FxController.Sound("Teleport", if typeof(data.to) == "Vector3" then data.to else nil)
end

---------------------------------------------------------------------------------------------------
-- AbilityFx dispatch

local function onAbilityFx(packet: Map)
	if type(packet) ~= "table" then
		return
	end
	local caster = packet.caster
	if typeof(caster) ~= "Instance" or not caster:IsA("Model") then
		return
	end
	local char: Model = caster
	local localChar = FxController.LocalCharacter()
	local castId = if type(packet.castId) == "number" then packet.castId else 0
	local wasPredicted = char == localChar and castId ~= 0 and predicted[castId] ~= nil
	local kitId: string = if type(packet.kit) == "string" then packet.kit else (char:GetAttribute("KitId") or "") :: any
	local abilityId: string = if type(packet.ability) == "string" then packet.ability else ""
	local phase: string = if type(packet.phase) == "string" then packet.phase else ""
	local data: Map = if type(packet.data) == "table" then packet.data else {}

	if phase == "Start" then
		if abilityId == "Dash" then
			FxController.PlayDash(char, packet.dir)
		elseif abilityId == "VerdictBox" then
			if not wasPredicted then
				AnimProxy.Play(char, "Point", { FadeIn = 0.05 })
			end
			local target = data.target
			local pos = if typeof(target) == "Instance" and target:IsA("Model") then chestPos(target) else nil
			if pos then
				Lib.EmitBurst(pos, 6, Color3.new(1, 1, 1), 0.3)
				Lib.Ring(CFrame.new(pos), 3.5, Color3.new(1, 1, 1), 0.35, 0.16)
			end
		elseif not wasPredicted then
			local ability = Kits.Ability(kitId, abilityId)
			if ability then
				FxController.PlayCastClip(char, ability, data.combo)
			end
		end
	end

	local kit = FxController.Kit(kitId)
	local fn = kit and kit.Effects and kit.Effects[abilityId]
	if type(fn) == "function" then
		local fx = FxController.Context(char)
		fx.Predicted = wasPredicted
		fx.Packet = packet
		task.spawn(function()
			local ok, err = pcall(fn, fx, packet)
			if not ok then
				warn(("[FxController] %s.Effects.%s(%s) failed: %s"):format(kitId, abilityId, phase, tostring(err)))
			end
		end)
	elseif phase == "Teleport" then
		genericTeleport(packet)
	end
	FxController.AbilityFx:Fire(packet)
end

---------------------------------------------------------------------------------------------------
-- DamageFx

local HIT_COLORS = {
	Beam = Color3.fromRGB(220, 250, 255),
	Melee = Color3.fromRGB(255, 255, 255),
	Projectile = Color3.fromRGB(255, 245, 220),
	Area = Color3.fromRGB(255, 255, 255),
	True = Color3.fromRGB(255, 80, 80),
	Box = Color3.fromRGB(255, 60, 60),
}

-- PURE-ish: colour of the sparks for a hit (colour rule > human attacker's SOUL colour > kind).
function FxController.HitColor(packet: Map): Color3
	local rule = packet.color
	if type(rule) == "string" and rule ~= "" and rule ~= "White" then
		return Lib.Color(rule)
	end
	local attacker = packet.attacker
	if typeof(attacker) == "Instance" and attacker:IsA("Model") and teamOf(attacker) ~= "Monster" then
		local c = Lib.KitColor(attacker)
		if c then
			return c
		end
	end
	return HIT_COLORS[packet.kind] or Lib.Colors.White
end

type KRState = {
	Credit: number,
	CreditT: number,
	Pending: number,
	PendingT: number,
	Acc: number,
	LastFlush: number,
	LastHP: number,
}
local krStates: { [Model]: KRState } = setmetatable({}, { __mode = "k" }) :: any

local function krState(model: Model): KRState
	local s = krStates[model]
	if s == nil then
		local hum = humanoidOf(model)
		s = {
			Credit = 0,
			CreditT = 0,
			Pending = 0,
			PendingT = 0,
			Acc = 0,
			LastFlush = 0,
			LastHP = if hum then hum.Health else 0,
		}
		krStates[model] = s
	end
	return s
end

local function krCredit(packet: Map)
	local target = packet.target
	local amount = packet.amount
	if
		typeof(target) ~= "Instance"
		or type(amount) ~= "number"
		or amount <= 0
		or packet.kind == "Heal"
		or packet.kind == "DodgeDrain"
	then
		return
	end
	local s = krStates[target]
	if s == nil then
		return
	end
	local now = os.clock()
	-- the health drop may already have arrived (counted as pending): consume it first
	if s.Pending > 0 and now - s.PendingT < 0.5 then
		local use = math.min(s.Pending, amount)
		s.Pending -= use
		amount -= use
	end
	if amount > 0 then
		s.Credit += amount
		s.CreditT = now
	end
end

local function onHealthChanged(model: Model, hp: number)
	local s = krState(model)
	local delta = s.LastHP - hp
	s.LastHP = hp
	if delta <= 0 then
		return
	end
	local now = os.clock()
	if s.Credit > 0 then
		local use = math.min(s.Credit, delta)
		s.Credit -= use
		delta -= use
	end
	if delta > 0.01 then
		s.Pending += delta
		s.PendingT = now
	end
end

local function krTick()
	local now = os.clock()
	for model, s in krStates do
		if s.Credit > 0 and now - s.CreditT > 0.6 then
			s.Credit = 0
		end
		if s.Pending > 0 and now - s.PendingT > 0.2 then
			local kr = model:GetAttribute("KR")
			if type(kr) == "number" and kr > 0 then
				s.Acc += s.Pending
			end
			s.Pending = 0
		end
		if s.Acc >= 0.5 and now - s.LastFlush > 0.45 then
			s.LastFlush = now
			local pos = headPos(model)
			if pos then
				DamageNumbers.KRTick(model, s.Acc, pos)
				Lib.Emit("Mote", pos - Vector3.new(0, 1, 0), 2, { Color = Lib.Colors.KR })
				if model == FxController.LocalCharacter() then
					FxController.Sound("KR", nil, { Force2D = true, Volume = 0.5 })
				end
			end
			s.Acc = 0
		end
	end
end

local function flinch(target: Model, packet: Map)
	if target:GetAttribute("Dead") == true or target:GetAttribute("Downed") == true or packet.blocked then
		return
	end
	local amount = packet.amount or 0
	if isMonster(target) then
		local exhausted = target:GetAttribute("Exhausted")
		if amount >= 15 or (type(exhausted) == "number" and exhausted > Lib.Now()) then
			AnimProxy.Play(target, "Hit", { FadeIn = 0.03 })
		end
	else
		AnimProxy.Play(target, "Hit", { FadeIn = 0.03 })
	end
end

local function onDamageFx(packet: Map)
	if type(packet) ~= "table" then
		return
	end
	local target = packet.target
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	local pos: Vector3 = if typeof(packet.pos) == "Vector3" then packet.pos else (chestPos(target) or Vector3.zero)
	local attacker: Model? = if typeof(packet.attacker) == "Instance" and packet.attacker:IsA("Model")
		then packet.attacker
		else nil
	local localChar = FxController.LocalCharacter()
	local isVictim = target == localChar
	local isAttacker = attacker ~= nil and attacker == localChar
	local kind: string = if type(packet.kind) == "string" then packet.kind else "Melee"
	local amount: number = if type(packet.amount) == "number" then packet.amount else 0

	DamageNumbers.Show(packet, { Local = localChar })
	krCredit(packet)

	local aRoot = rootOf(attacker)
	local dir: Vector3? = nil
	if aRoot then
		local d = pos - aRoot.Position
		if d.Magnitude > 0.1 then
			dir = d.Unit
		end
	end

	if kind == "Heal" then
		Lib.Emit("Heal", pos, 10, { Color = Lib.Colors.Green })
		Lib.EmitBurst(pos, 3, Lib.Colors.Green, 0.3)
		if isVictim then
			ScreenFX.Pulse("Heal", math.clamp(amount / 20, 0.4, 1))
		end
	elseif kind == "DodgeDrain" then
		Lib.Emit("Mote", pos, 8, { Color = Color3.fromRGB(154, 216, 255) })
	elseif packet.dodged or packet.negated then
		-- MISS: lazy side-step (Undertale: slide ~0.4 s, hold, return); the ghost marks where the hit went
		if packet.dodged then
			Lib.Afterimage(target, Lib.Colors.Grey, 0.35, { Transparency = 0.5, MaxParts = 20 })
			AnimProxy.Play(target, "Dodge", { FadeIn = 0.04 })
			FxController.Sound("Dodge", target:FindFirstChild("HumanoidRootPart"))
		end
		Lib.Emit("Mote", pos, 4, { Color = Lib.Colors.Grey })
	elseif packet.parried then
		local gold = Lib.Colors.Gold
		Lib.Flash(pos, Color3.fromRGB(255, 250, 220), 4.5, 0.2)
		Lib.Sparks(pos, if dir then -dir else nil, gold, 18, 34)
		Lib.Ring(CFrame.new(pos) * CFrame.Angles(math.pi / 2, 0, 0), 3.2, gold, 0.25, 0.14)
		FxController.Sound("Parry", pos)
		AnimProxy.Play(target, "Parry", { FadeIn = 0.03 })
		FxController.HitStop(target, 0.12)
		if attacker then
			FxController.HitStop(attacker, 0.12)
		end
		if isVictim or isAttacker then
			ScreenFX.Pulse("Parry")
			FxController.Shake(0.25, 0.18)
			FxController.Kick(-4, 0.2)
		end
	else
		local color = FxController.HitColor(packet)
		local heavy = amount >= 14 or packet.killed == true or packet.downed == true
		local n = math.clamp(math.floor(amount * 0.8), 6, 20)
		if amount > 0 then
			Lib.Sparks(pos, dir, color, n, if heavy then 32 else 24)
			Lib.Flash(pos, color, if heavy then 3.6 else 2.4, if heavy then 0.22 else 0.15)
			if type(packet.kr) == "number" and packet.kr > 0 then
				Lib.Emit("Mote", pos, math.clamp(math.floor(packet.kr), 2, 8), { Color = Lib.Colors.KR })
			end
		end
		if packet.blocked then
			local guard = Color3.fromRGB(150, 205, 255)
			Lib.Sparks(pos, if dir then -dir else nil, guard, 10, 26)
			Lib.EmitBurst(pos, 3.4, guard, 0.18)
			FxController.Sound("Block", pos)
		else
			FxController.Sound(if packet.crit then "Crit" elseif heavy then "HitHeavy" else "Hit", pos)
		end
		if packet.guardBreak then
			Lib.Shatter(
				CFrame.new(pos),
				4,
				Color3.fromRGB(150, 205, 255),
				10,
				{ Speed = 16, Material = Enum.Material.Glass }
			)
			Lib.Text(
				pos + Vector3.new(0, 1.5, 0),
				Strings.L("fx.guardBreak"),
				Lib.Colors.Orange,
				{ Kind = "Alert", Scale = 1.15 }
			)
			FxController.Sound("GuardBreak", pos)
			if isVictim then
				ScreenFX.Pulse("GuardBreak")
			end
		end
		if type(packet.absorbed) == "number" and packet.absorbed > 0 then
			Lib.EmitBurst(pos, 4, Color3.fromRGB(127, 232, 255), 0.25)
			FxController.Sound("Shield", pos)
		end
		if packet.killed then
			FxController.Sound("Kill", pos)
		end
		if amount > 0 then
			flinch(target, packet)
			if kind == "Melee" then
				local stop = if heavy
					then (Config.Combat.HitStopHeavy or 0.12)
					else (Config.Combat.HitStopMelee or 0.06)
				FxController.HitStop(target, stop)
				if attacker then
					FxController.HitStop(attacker, stop)
				end
			elseif heavy then
				FxController.HitStop(target, Config.Combat.HitStopMelee or 0.06)
			end
		end
		if isVictim and amount > 0 then
			local hum = humanoidOf(target)
			local maxHp = if hum and hum.MaxHealth > 0 then hum.MaxHealth else 100
			local k = math.clamp(amount / maxHp * 5, 0.25, 1.2)
			ScreenFX.Pulse(if heavy then "Heavy" else "Hit", k)
			FxController.Shake(0.12 + 0.35 * k, if heavy then 0.35 else 0.2)
			FxController.Sound("Hurt", nil, { Force2D = true })
			if type(packet.kr) == "number" and packet.kr > 0 then
				ScreenFX.Pulse("KR", math.clamp(packet.kr / 8, 0.3, 1))
			end
		elseif isAttacker and amount > 0 then
			FxController.Kick(if heavy then -3 else -1.2, 0.12)
			if heavy then
				FxController.Shake(0.12, 0.12)
			end
			FxController.Sound("HitConfirm", nil, { Volume = 0.6 })
		end
	end

	-- kit reaction hook for the target's kit (e.g. Sans lazy dodge flourish, Determination afterimage counter)
	local targetKit = FxController.Kit(target:GetAttribute("KitId") :: any)
	local hook = targetKit and targetKit.OnDamageFx
	if type(hook) == "function" then
		local fx = FxController.Context(target)
		fx.Packet = packet
		task.spawn(function()
			local ok, err = pcall(hook, fx, packet)
			if not ok then
				warn("[FxController] OnDamageFx failed: " .. tostring(err))
			end
		end)
	end
	FxController.DamageFx:Fire(packet)
end

---------------------------------------------------------------------------------------------------
-- Deaths (dust / SOUL shatter), downed SOUL, revive burst

local deathPlayed: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function visibleParts(model: Model): { BasePart }
	local out: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if
			d:IsA("BasePart")
			and d.Name ~= "HumanoidRootPart"
			and d.Transparency < 0.95
			and d.LocalTransparencyModifier < 0.95
		then
			table.insert(out, d)
		end
	end
	return out
end

local function dustAway(model: Model)
	local parts = visibleParts(model)
	if #parts == 0 then
		return
	end
	local tops: { number } = table.create(#parts)
	local topY, botY = -math.huge, math.huge
	for i, p in parts do
		local half = p.Size.Magnitude * 0.5
		tops[i] = p.Position.Y + half * 0.6
		topY = math.max(topY, tops[i])
		botY = math.min(botY, p.Position.Y - half * 0.6)
	end
	local chest = chestPos(model) or parts[1].Position
	-- the beat before the dust: freeze + white flash (Undertale enemy death)
	Lib.Flash(chest, Color3.new(1, 1, 1), 5, 0.3)
	FxController.HitStop(model, 0.45)
	FxController.Sound("Hit", chest)
	local dusted: { number } = table.create(#parts, -1)
	local FREEZE, SWEEP, FADE = 0.45, 1.4, 0.3
	local dustColor = Color3.fromRGB(225, 225, 232)
	local sounded = false
	Lib.Animate(FREEZE + SWEEP + FADE + 0.1, function(_a, _dt, elapsed)
		if elapsed < FREEZE then
			return nil
		end
		if not sounded then
			sounded = true
			FxController.Sound("Dust", chest)
		end
		local k = math.clamp((elapsed - FREEZE) / SWEEP, 0, 1)
		local sweepY = topY - (topY - botY + 0.5) * k
		for i, p in parts do
			if dusted[i] < 0 then
				if tops[i] >= sweepY then
					dusted[i] = elapsed
					if p.Parent then
						local s = p.Size
						local bursts = math.clamp(math.floor(s.X * s.Y * s.Z * 2) + 1, 1, 4)
						for _ = 1, bursts do
							local off = Vector3.new(
								Lib.Rand(-0.5, 0.5) * s.X,
								Lib.Rand(-0.5, 0.5) * s.Y,
								Lib.Rand(-0.5, 0.5) * s.Z
							)
							Lib.Emit("SoulDust", (p.CFrame * CFrame.new(off)).Position, 2, { Color = dustColor })
						end
					end
				end
			elseif p.Parent then
				p.LocalTransparencyModifier = math.clamp((elapsed - dusted[i]) / FADE, 0, 1)
			end
		end
		return nil
	end)
end

local function soulShatter(model: Model)
	local start = chestPos(model)
	if start == nil then
		return
	end
	local pos: Vector3 = start
	local color = Lib.KitColor(model) or Lib.Colors.Red
	local isLocal = model == FxController.LocalCharacter()
	local folder = Lib.Folder()
	local soul = Lib.Soul(color, 1.3)
	soul.Parent = folder
	local primary = soul.PrimaryPart or soul:FindFirstChildWhichIsA("BasePart", true)
	local light = if primary then Lib.Light(primary, color, 3, 12) else nil
	local broken: Model? = nil
	Lib.Flash(pos, color, 3, 0.2)
	FxController.Sound("SoulAppear", pos)
	if isLocal then
		ScreenFX.Pulse("Death")
	end
	local body = visibleParts(model)
	local CRACK, SHATTER = 0.75, 1.5
	local cracked = false
	local function faceCamera(): CFrame
		local cam = game:GetService("Workspace").CurrentCamera
		local look = if cam then (cam.CFrame.Position - pos) else Vector3.new(0, 0, 1)
		return Lib.LookAlong(pos, Vector3.new(look.X, 0, look.Z).Unit)
	end
	Lib.Animate(SHATTER + 0.05, function(_a, _dt, elapsed)
		pos = start + Vector3.new(0, math.min(0.6, elapsed * 0.8), 0)
		local cf = faceCamera()
		-- body fades while the SOUL takes over
		local fade = math.clamp(elapsed / 0.6, 0, 1) * 0.7 + (if elapsed > SHATTER - 0.1 then 0.3 else 0)
		for _, p in body do
			if p.Parent then
				p.LocalTransparencyModifier = fade
			end
		end
		if not cracked and elapsed >= CRACK then
			cracked = true
			soul:Destroy()
			local b = Lib.SoulBroken(color, 1.3)
			b.Parent = folder
			broken = b
			Lib.Flash(pos, Color3.new(1, 1, 1), 1.6, 0.12)
			FxController.Sound("SoulCrack", pos)
			if isLocal then
				FxController.Shake(0.2, 0.15)
			end
		end
		if cracked then
			local b = broken
			if b then
				b:PivotTo(cf)
				local l = b:FindFirstChild("LeftHalf")
				local r = b:FindFirstChild("RightHalf")
				local gap = 0.06 + math.min(0.08, (elapsed - CRACK) * 0.1)
				if l and l:IsA("Model") then
					l:PivotTo(cf * CFrame.new(-gap, 0, 0) * CFrame.Angles(0, 0, math.rad(6)))
				end
				if r and r:IsA("Model") then
					r:PivotTo(cf * CFrame.new(gap, 0, 0) * CFrame.Angles(0, 0, math.rad(-6)))
				end
			end
		elseif soul.Parent then
			soul:PivotTo(cf)
		end
		if light then
			light.Brightness = 3 + math.sin(elapsed * 14) * 0.5
		end
		return nil
	end, function()
		if soul.Parent then
			soul:Destroy()
		end
		if broken then
			broken:Destroy()
		end
		local cfNow = faceCamera()
		local shards = Lib.SoulShards(color, 1.3, 7)
		Lib.Shatter(cfNow, 2.2, color, 8, { Speed = 13, Gravity = 42, Duration = 1.3, Parts = shards })
		Lib.EmitBurst(pos, 4, color, 0.25)
		FxController.Sound("SoulShatter", pos)
		if isLocal then
			ScreenFX.Flash(color, 0.3, 0.3)
			FxController.Shake(0.3, 0.25)
		end
		for _, p in body do
			if p.Parent then
				p.LocalTransparencyModifier = 1
			end
		end
	end)
end

function FxController.Death(model: Model)
	if deathPlayed[model] then
		return
	end
	deathPlayed[model] = true
	FxController.Died:Fire(model)
	local team = teamOf(model)
	if isMonster(model) or team == "Dummy" then
		dustAway(model)
	else
		soulShatter(model)
	end
end

---------------------------------------------------------------------------------------------------
-- Per-character status visuals (stun stars, block shimmer, blue SOUL, sweat, downed SOUL)

type Status = {
	Model: Model,
	Stars: { BasePart }?,
	Shield: BasePart?,
	Blue: Model?,
	Downed: Model?,
	Sweat: ParticleEmitter?,
	Next: number,
}

local statuses: { [Model]: Status } = setmetatable({}, { __mode = "k" }) :: any
local statusList: { Status } = {}
local statusConn: any = nil
local STAR_COLOR = Color3.fromRGB(255, 236, 120)

local function clearStatus(st: Status)
	if st.Stars then
		for _, s in st.Stars do
			Lib.Release(s)
		end
		st.Stars = nil
	end
	if st.Shield then
		Lib.Release(st.Shield)
		st.Shield = nil
	end
	if st.Blue then
		st.Blue:Destroy()
		st.Blue = nil
	end
	if st.Downed then
		st.Downed:Destroy()
		st.Downed = nil
	end
	if st.Sweat then
		st.Sweat:Destroy()
		st.Sweat = nil
	end
end

local function statusStep()
	local now = os.clock()
	local W = game:GetService("Workspace")
	local cam = W.CurrentCamera
	local i = 1
	while i <= #statusList do
		local st = statusList[i]
		local m = st.Model
		if m.Parent == nil then
			clearStatus(st)
			statuses[m] = nil
			local n = #statusList
			statusList[i] = statusList[n]
			statusList[n] = nil
		else
			-- attribute polling at ~10 Hz (Status_* values are end times, they expire silently)
			if now >= st.Next then
				st.Next = now + 0.1
				local dead = m:GetAttribute("Dead") == true
				local stunned = not dead and statusActive(m, "Stunned") and m:GetAttribute("Downed") ~= true
				if stunned and st.Stars == nil then
					FxController.Sound("Stun", rootOf(m))
					st.Stars = {}
					for k = 1, 3 do
						(st.Stars :: any)[k] =
							Lib.Part("Ball", Vector3.one * 0.32, CFrame.new(), STAR_COLOR, Enum.Material.Neon, 0)
					end
				elseif not stunned and st.Stars then
					for _, s in st.Stars do
						Lib.Release(s)
					end
					st.Stars = nil
				end
				local blocking = not dead and m:GetAttribute("Blocking") == true
				if blocking and st.Shield == nil then
					st.Shield = Lib.Part(
						"Cylinder",
						Vector3.new(0.12, 4.6, 4.6),
						CFrame.new(),
						Color3.fromRGB(130, 200, 255),
						Enum.Material.ForceField,
						0.1
					)
				elseif not blocking and st.Shield then
					Lib.Release(st.Shield)
					st.Shield = nil
				end
				local blue = not dead and m:GetAttribute("SoulMode") == "Blue"
				if blue and st.Blue == nil then
					local b = Lib.Soul(Color3.fromRGB(0, 60, 255), 0.75)
					b.Parent = Lib.Folder()
					st.Blue = b
				elseif not blue and st.Blue then
					st.Blue:Destroy()
					st.Blue = nil
				end
				local downed = not dead and m:GetAttribute("Downed") == true
				if downed and st.Downed == nil then
					local b = Lib.SoulBroken(Lib.KitColor(m) or Lib.Colors.Red, 0.8)
					b.Parent = Lib.Folder()
					st.Downed = b
				elseif not downed and st.Downed then
					st.Downed:Destroy()
					st.Downed = nil
				end
				local ex = m:GetAttribute("Exhausted")
				local exhausted = not dead
					and ((type(ex) == "number" and ex > Lib.Now()) or statusActive(m, "Exhausted"))
				if exhausted and st.Sweat == nil then
					FxController.Sound("Exhausted", rootOf(m))
					local head = attachment(m, "HeadTop") or attachment(m, "LeftEye")
					if head then
						st.Sweat = Lib.Emitter(
							"Sweat",
							head,
							{ Color = Color3.fromRGB(150, 210, 255), Rate = 7 * Lib.ParticleScale() }
						)
					end
				elseif not exhausted and st.Sweat then
					st.Sweat:Destroy()
					st.Sweat = nil
				end
			end
			-- per-frame placement
			local root = rootOf(m)
			if root then
				local rcf = root.CFrame
				local stars = st.Stars
				if stars then
					local hp = headPos(m) or (rcf.Position + Vector3.new(0, 3, 0))
					for k, s in stars do
						local a = now * 4 + k * (math.pi * 2 / 3)
						s.CFrame = CFrame.new(
							hp + Vector3.new(math.cos(a) * 0.9, 0.35 + math.sin(now * 6 + k) * 0.1, math.sin(a) * 0.9)
						)
					end
				end
				if st.Shield then
					st.Shield.CFrame = rcf * CFrame.new(0, 0.4, -1.7) * CFrame.Angles(0, math.pi / 2, 0)
				end
				local cpos = chestPos(m)
				if cpos and (st.Blue or st.Downed) then
					local look = if cam then (cam.CFrame.Position - cpos) else rcf.LookVector
					local flat = Vector3.new(look.X, 0, look.Z)
					local cf = Lib.LookAlong(
						cpos + Vector3.new(0, math.sin(now * 3) * 0.08, 0),
						if flat.Magnitude > 1e-3 then flat else rcf.LookVector
					)
					if st.Blue then
						st.Blue:PivotTo(cf * CFrame.new(0, 0, -0.6))
					end
					if st.Downed then
						st.Downed:PivotTo(cf * CFrame.new(0, 0.8, -0.6))
					end
				end
			end
			i += 1
		end
	end
	if #statusList == 0 and statusConn then
		statusConn:Disconnect()
		statusConn = nil
	end
end

local function trackStatus(model: Model)
	if statuses[model] then
		return
	end
	local st: Status = { Model = model, Next = 0 }
	statuses[model] = st
	table.insert(statusList, st)
	if statusConn == nil then
		statusConn = RunService.PreRender:Connect(statusStep)
	end
end

local function reviveBurst(model: Model)
	local pos = chestPos(model)
	if pos == nil then
		return
	end
	local color = Lib.KitColor(model) or Lib.Colors.Red
	Lib.Flash(pos, color, 4, 0.3)
	Lib.EmitRing(pos - Vector3.new(0, 2.5, 0), 4, Lib.Colors.Green, 0.4)
	Lib.Emit("Heal", pos, 16, { Color = Lib.Colors.Green })
	FxController.Sound("Revive", pos)
end

---------------------------------------------------------------------------------------------------
-- Character tracking

local tracked: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function untrack(model: Model)
	tracked[model] = nil
	local t = troves[model]
	if t then
		t:Clean()
		troves[model] = nil
	end
	local eyes = eyeHandles[model]
	if eyes then
		for _, h in eyes do
			h.Handle:Destroy()
		end
		eyeHandles[model] = nil
	end
	contexts[model] = nil
end

local function onLocalAttributes(model: Model, trove: any)
	local function kr()
		local v = model:GetAttribute("KR")
		ScreenFX.SetKR(if type(v) == "number" then v / (Config.KR.Max or 40) else 0)
	end
	local function blue()
		local on = model:GetAttribute("SoulMode") == "Blue"
		ScreenFX.SetBlue(on)
	end
	trove:Connect(model:GetAttributeChangedSignal("KR"), kr)
	trove:Connect(model:GetAttributeChangedSignal("SoulMode"), function()
		local wasBlue = model:GetAttribute("SoulMode") == "Blue"
		blue()
		if wasBlue then
			ScreenFX.Pulse("Blue")
		end
	end)
	kr()
	blue()
	local hum = humanoidOf(model)
	if hum then
		local h: Humanoid = hum
		local function hp()
			ScreenFX.SetLowHealth(if h.MaxHealth > 0 then h.Health / h.MaxHealth else 1)
		end
		trove:Connect(h.HealthChanged, hp)
		hp()
	end
	trove:Add(function()
		ScreenFX.SetKR(0)
		ScreenFX.SetBlue(false)
		ScreenFX.SetLowHealth(1)
	end)
end

local function track(model: Model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	tracked[model] = true
	local trove = troveFor(model)
	trackStatus(model)
	-- KR tick bookkeeping (humans carry KR)
	local hum = humanoidOf(model)
	if hum then
		local h: Humanoid = hum
		krState(model).LastHP = h.Health
		trove:Connect(h.HealthChanged, function(hp: number)
			onHealthChanged(model, hp)
		end)
	end
	-- death / downed / revive
	trove:Connect(model:GetAttributeChangedSignal("Dead"), function()
		if model:GetAttribute("Dead") == true then
			FxController.Death(model)
		end
	end)
	local wasDowned = model:GetAttribute("Downed") == true
	trove:Connect(model:GetAttributeChangedSignal("Downed"), function()
		local downed = model:GetAttribute("Downed") == true
		if wasDowned and not downed and model:GetAttribute("Dead") ~= true then
			reviveBurst(model)
		elseif downed and not wasDowned then
			local pos = chestPos(model)
			if pos then
				Lib.Flash(pos, Lib.KitColor(model) or Lib.Colors.Red, 2.5, 0.2)
				FxController.Sound("Downed", pos)
			end
		end
		wasDowned = downed
	end)
	if model == FxController.LocalCharacter() then
		onLocalAttributes(model, trove)
	end
	-- kit passives
	local kitId = model:GetAttribute("KitId")
	local kit = FxController.Kit(kitId :: any)
	if kit and type(kit.OnCharacter) == "function" then
		local fx = FxController.Context(model)
		task.spawn(function()
			local ok, err = pcall(kit.OnCharacter, fx, model)
			if not ok then
				warn("[FxController] OnCharacter " .. tostring(kitId) .. " failed: " .. tostring(err))
			end
		end)
	end
	trove:Connect(model.AncestryChanged, function(_, parent)
		if parent == nil then
			untrack(model)
		end
	end)
	if model:GetAttribute("Dead") == true then
		deathPlayed[model] = true -- already dead when we first saw it: no replay
	end
end

local function watchPlayer(player: Player)
	if player.Character then
		task.defer(track, player.Character)
	end
	player.CharacterAdded:Connect(function(c)
		task.defer(track, c)
	end)
end

local function watchBots(folder: Instance)
	for _, c in folder:GetChildren() do
		if c:IsA("Model") then
			task.defer(track, c)
		end
	end
	folder.ChildAdded:Connect(function(c)
		if c:IsA("Model") then
			task.defer(track, c)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Round events

local function onRoundEvent(name: string, data: any)
	if type(data) ~= "table" then
		return
	end
	if name == "Kill" then
		local victim = data.victim
		if typeof(victim) == "Instance" and victim:IsA("Model") then
			FxController.Death(victim)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

function FxController.Init()
	-- settings: damage numbers on/off (Config.Defaults.DamageNumbers)
	local d = Config.Defaults and Config.Defaults.DamageNumbers
	if d == false then
		DamageNumbers.SetEnabled(false)
	end
end

local function listen(name: string, fn: (...any) -> ())
	task.spawn(function()
		local ok, err = pcall(Net.Client.On, name, function(...)
			local ok2, err2 = pcall(fn, ...)
			if not ok2 then
				warn(("[FxController] %s handler failed: %s"):format(name, tostring(err2)))
			end
		end)
		if not ok then
			warn("[FxController] cannot listen to " .. name .. ": " .. tostring(err))
		end
	end)
end

function FxController.Start()
	listen("AbilityFx", onAbilityFx)
	listen("DamageFx", onDamageFx)
	listen("Hazard", function(packet)
		local hv = hazards()
		if hv then
			hv.Spawn(packet)
		end
	end)
	listen("HazardEnd", function(id)
		local hv = hazards()
		if hv and type(id) == "number" then
			hv.End(id)
		end
	end)
	listen("RoundEvent", onRoundEvent)

	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	local W = game:GetService("Workspace")
	local bots = W:FindFirstChild("Bots")
	if bots then
		watchBots(bots)
	end
	W.ChildAdded:Connect(function(c)
		if c.Name == "Bots" and c:IsA("Folder") then
			watchBots(c)
		end
	end)

	-- profile setting for damage numbers (StateController, when present)
	local state = controller("StateController")
	if state and state.ProfileChanged then
		local function apply(profile: any)
			local s = if type(profile) == "table" then profile.Settings else nil
			if type(s) == "table" and s.DamageNumbers ~= nil then
				DamageNumbers.SetEnabled(s.DamageNumbers ~= false)
			end
		end
		pcall(function()
			state.ProfileChanged:Connect(apply)
			if type(state.Profile) == "function" then
				apply(state.Profile())
			end
		end)
	end

	-- KR tick numbers (10 Hz)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(krTick)
			if not ok then
				warn("[FxController] KR tick failed: " .. tostring(err))
			end
		end
	end)
end

return FxController
