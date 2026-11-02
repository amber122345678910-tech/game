--!strict
-- CombatController (client controller, Priority 35): ability input -> local checks -> prediction -> Net "Cast"
-- (SPEC §7.2, §20). Also Block (humans, F hold -> Net "Block"), Dash (humans, Shift -> MovementController.PredictDash
-- + Net "Dash"), the monster's Verdict Box (F -> pseudo-cast "VerdictBox" with a soft-selected target) and the HUD
-- state: cooldowns, hold charge, M1 combo, ammo/reload mirror (kits whose M1 has Numbers.Ammo, e.g. Justice).
--
-- Input (InputController.Action): action name == kit slot ("M1","Q","E","R","T","G","Shift"; ult = G for monsters,
-- R for humans, straight from kit data). Casting rules by AbilityDef (CombatController.CastMode, pure):
--   Hold = {MaxTime}          charge 0..1 while held (kit Indicator or a generic one), cast on release
--   QuickCast setting ON (default, Config.Defaults.QuickCast): everything else casts on press; M1 repeats while held
--   QuickCast OFF ("hold to aim"): Direction / Ground / Target / Ally abilities (and Self ones whose kit defines an
--     Indicator) show the kit Indicator - else a generic one: direction arrow lane, ground circle, target ring -
--     while held and cast on release. M1 and Self abilities without an indicator still cast on press.
--   Escape / right-click / a forced release (Roblox menu, focus loss: InputController.Cancelled) cancels a held aim
--   or charge without casting.
-- Soft targets never include Invisible enemies (attribute Invisible / active Status_Invisible).
-- Payload (pure, BuildPayload): Direction -> camera aim point clamped to Range; Ground -> ground under the clamped
-- point; Target/Ally -> soft target nearest to the aim ray (SelectTarget, within Range and an aim cone; Ally falls
-- back to self); Self -> own position. castId increments per cast (dashes take one too: MovementController plays
-- the Dash clip at once and AnimController skips the server echo of that castId).
-- Prediction: local cooldown (rolled back when the server answers "Cooldown" with an earlier end, or when no answer
-- arrives), cast clip via FxController.PlayCastClip (combo variant) + FxController.MarkPredicted + kit Predict.
-- Suppressed while: InputController.CombatEnabled() is false, Dead, Downed, Stunned, Boxed (status or SoulMode),
-- Silenced (all but M1), RoundState Phase "Intro". Charges / aims are cancelled when that happens.
--
-- API
--   CombatController.Cooldowns() -> {[abilityId]: endsAt}      CombatController.CooldownLeft(abilityId) -> number
--   CombatController.CooldownChanged: Signal(abilityId, endsAt)
--   CombatController.Charge() -> (abilityId?, number 0..1)      ChargeChanged: Signal(abilityId?, charge)
--   CombatController.ComboIndex() -> (index, abilityId?)         ComboChanged: Signal(abilityId, index)
--   CombatController.Ammo() -> (ammo?, max?, reloading, reloadEndsAt)   AmmoChanged: Signal(ammo, max, reloading)
--   CombatController.Kit() -> KitDef?   AbilityForSlot(slot) -> AbilityDef?   IsReady(abilityId) -> boolean
--   CombatController.IsSuppressed(ability?) -> (boolean, reason?)
--   CombatController.TryCast(abilityId) -> boolean               (HUD/touch: press + release)
--   CombatController.Casted: Signal(abilityId, payload)          Feedback: Signal(kind, abilityId?)
--        kinds: "Cooldown" | "NoTarget" | "NoUlt" | "Suppressed" | "NoAmmo" | "NoCharges" | "Rejected"
-- Pure helpers (Lune-tested): BuildPayload(ability, ctx) -> CastPayload,
--   SelectTarget(rayOrigin, rayDir, from, candidates {{Model, Pos}}, maxRange, maxAngleDeg) -> Model?,
--   ChargeOf(heldSeconds, maxTime) -> 0..1, AmmoAbility(kit) -> AbilityDef?, FlatDir(v, fallback) -> Vector3,
--   CastMode(ability, quickCast, hasKitIndicator) -> "Charge"|"Aim"|"Press", IsHidden(model, now) -> boolean

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal")) :: any
local Teams = require(Shared:WaitForChild("Combat"):WaitForChild("Teams")) :: any
local DamageMath = require(Shared:WaitForChild("Combat"):WaitForChild("DamageMath")) :: any

local VFX = script.Parent.Parent:WaitForChild("VFX")
local Lib = require(VFX:WaitForChild("Lib")) :: any

local CombatController = {}
CombatController.Priority = 35
CombatController.CooldownChanged = Signal.new()
CombatController.ChargeChanged = Signal.new()
CombatController.ComboChanged = Signal.new()
CombatController.AmmoChanged = Signal.new()
CombatController.Casted = Signal.new()
CombatController.Feedback = Signal.new()
CombatController.QuickCast = true -- StateController setting "QuickCast" (Config.Defaults.QuickCast)

type Map = { [string]: any }

local VERDICT_ID = "VerdictBox"
local PENDING_TIMEOUT = 1.6
local TARGET_CONE = 22 -- degrees around the aim ray for soft targeting
local PARK = CFrame.new(0, 25000, 0)

---------------------------------------------------------------------------------------------------
-- Pure helpers

function CombatController.FlatDir(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		local g = Vector3.new(fallback.X, 0, fallback.Z)
		return if g.Magnitude > 1e-3 then g.Unit else Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function CombatController.ChargeOf(held: number, maxTime: number): number
	if maxTime <= 0 then
		return 1
	end
	return math.clamp(held / maxTime, 0, 1)
end

local AIMED = { Direction = true, Ground = true, Target = true, Ally = true }

-- How pressing an ability behaves: "Charge" (Hold: charge while held, cast on release), "Aim" (indicator while
-- held, cast on release) or "Press" (cast at once).
function CombatController.CastMode(ability: Map, quickCast: boolean, hasKitIndicator: boolean?): string
	if type(ability.Hold) == "table" then
		return "Charge"
	end
	if quickCast or ability.Slot == "M1" then
		return "Press"
	end
	if AIMED[ability.Aim] or hasKitIndicator == true then
		return "Aim"
	end
	return "Press"
end

-- Invisible characters (Patience stealth, Eclipse VoidStep): the attribute, or a Status_Invisible end time ahead.
function CombatController.IsHidden(model: Instance, t: number): boolean
	if model:GetAttribute("Invisible") == true then
		return true
	end
	local endsAt = model:GetAttribute("Status_Invisible")
	return type(endsAt) == "number" and endsAt > t
end

-- The M1 ability whose Numbers carry Ammo (ammo/reload mirror), if any.
function CombatController.AmmoAbility(kit: Map?): Map?
	if kit == nil or type(kit.Abilities) ~= "table" then
		return nil
	end
	for _, a in kit.Abilities do
		if a.Slot == "M1" and type(a.Numbers) == "table" and type(a.Numbers.Ammo) == "number" then
			return a
		end
	end
	return nil
end

-- Soft target: the candidate closest (in angle) to the aim ray, within maxRange of `from` and maxAngleDeg of the ray.
function CombatController.SelectTarget(
	rayOrigin: Vector3,
	rayDir: Vector3,
	from: Vector3,
	candidates: { { Model: Model, Pos: Vector3 } },
	maxRange: number,
	maxAngleDeg: number
): Model?
	local dir = if rayDir.Magnitude > 1e-6 then rayDir.Unit else Vector3.new(0, 0, -1)
	local cosMax = math.cos(math.rad(maxAngleDeg))
	local best: Model? = nil
	local bestScore = math.huge
	for _, c in candidates do
		local d = (c.Pos - from).Magnitude
		if d <= maxRange then
			local to = c.Pos - rayOrigin
			local len = to.Magnitude
			if len > 1e-3 then
				local cos = to:Dot(dir) / len
				if cos >= cosMax then
					-- angle first, then a mild preference for closer targets
					local score = (1 - cos) + d / math.max(1, maxRange) * 0.02
					if score < bestScore then
						bestScore = score
						best = c.Model
					end
				end
			end
		end
	end
	return best
end

-- ctx = { Root: Vector3, Look: Vector3, Aim: Vector3, Ground: ((Vector3) -> Vector3?)?, Target: Model?,
--         TargetPos: Vector3?, Charge: number?, CastId: number }
function CombatController.BuildPayload(ability: Map, ctx: Map): Map
	local root: Vector3 = ctx.Root
	local look = CombatController.FlatDir(ctx.Look or Vector3.new(0, 0, -1), Vector3.new(0, 0, -1))
	local range: number = if type(ability.Range) == "number" then ability.Range else Config.Combat.MaxAimRange
	local mode = ability.Aim
	local aim: Vector3 = ctx.Aim or (root + look * math.min(range, 40))
	local dir: Vector3
	local target: Model? = nil
	if mode == "Self" then
		aim = root
		dir = look
	elseif mode == "Ground" then
		local flat = Vector3.new(aim.X - root.X, 0, aim.Z - root.Z)
		if flat.Magnitude > range then
			flat = flat.Unit * range
			aim = Vector3.new(root.X + flat.X, aim.Y, root.Z + flat.Z)
		end
		local g = if ctx.Ground then ctx.Ground(aim) else nil
		if g then
			aim = g
		end
		dir = CombatController.FlatDir(aim - root, look)
	elseif mode == "Target" or mode == "Ally" then
		target = ctx.Target
		if target and typeof(ctx.TargetPos) == "Vector3" then
			aim = ctx.TargetPos
		else
			aim = DamageMath.ClampAim(root, aim, range)
		end
		local d = aim - root
		dir = if d.Magnitude > 0.5 then d.Unit else look
	else -- Direction
		aim = DamageMath.ClampAim(root, aim, range)
		local d = aim - root
		if Vector3.new(d.X, 0, d.Z).Magnitude < 1 then
			dir = look
		else
			dir = d.Unit
		end
	end
	return {
		aim = aim,
		dir = dir,
		charge = if type(ability.Hold) == "table" then math.clamp(ctx.Charge or 0, 0, 1) else nil,
		target = target,
		castId = ctx.CastId or 0,
	}
end

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
		warn(("[CombatController] %s.%s failed: %s"):format(name, fn, tostring(r)))
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- State

type Pending = { Ability: string, T: number, Prev: number, Predicted: number, Clip: string? }

local cooldowns: { [string]: number } = {}
local pending: { [number]: Pending } = {}
local castCounter = 0
local charging: Map? = nil -- { Ability, Start, Indicator, Charge }
local aiming: Map? = nil -- { Ability, Start, Indicator, Target }
local combo = { Index = 0, Last = -math.huge, Ability = nil :: string? }
local ammo = { Ammo = nil :: number?, Max = nil :: number?, ReloadEnds = 0, Ability = nil :: Map? }
local blockHeld = false
local blockSent = false
local lastBlockSend = -math.huge
local lastDash = -math.huge
local m1Held = false
local character: Model? = nil
local charTrove: { RBXScriptConnection } = {}

local function now(): number
	return Lib.Now()
end

local function localChar(): Model?
	local lp = Players.LocalPlayer
	return if lp then lp.Character else nil
end

local function rootOf(model: Model?): BasePart?
	if model == nil then
		return nil
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function statusActive(model: Model, name: string): boolean
	local v = model:GetAttribute("Status_" .. name)
	return type(v) == "number" and v > now()
end

function CombatController.Kit(): Map?
	local c = localChar()
	local id = c and c:GetAttribute("KitId")
	return if type(id) == "string" then Kits.Get(id) else nil
end

function CombatController.AbilityForSlot(slot: string): Map?
	local kit = CombatController.Kit()
	if kit == nil then
		return nil
	end
	return Kits.AbilityBySlot(kit.Id, slot)
end

local function isMonster(): boolean
	local c = localChar()
	return c ~= nil and Teams.TeamOf(c) == "Monster"
end

function CombatController.Cooldowns(): { [string]: number }
	return cooldowns
end

function CombatController.CooldownLeft(abilityId: string): number
	return math.max(0, (cooldowns[abilityId] or 0) - now())
end

function CombatController.IsReady(abilityId: string): boolean
	return CombatController.CooldownLeft(abilityId) <= 0.05
end

function CombatController.Charge(): (string?, number)
	local c = charging
	if c then
		return c.Ability.Id, c.Charge or 0
	end
	return nil, 0
end

function CombatController.ComboIndex(): (number, string?)
	local kit = CombatController.Kit()
	local ability = if combo.Ability and kit then Kits.Ability(kit.Id, combo.Ability) else nil
	local window = if ability
			and ability.Numbers
			and type(ability.Numbers.ComboWindow) == "number"
		then ability.Numbers.ComboWindow
		else Config.Combat.ComboResetTime
	if now() - combo.Last > window then
		return 0, combo.Ability
	end
	return combo.Index, combo.Ability
end

function CombatController.Ammo(): (number?, number?, boolean, number)
	return ammo.Ammo, ammo.Max, ammo.ReloadEnds > 0, ammo.ReloadEnds
end

local function setCooldown(abilityId: string, endsAt: number)
	cooldowns[abilityId] = endsAt
	CombatController.CooldownChanged:Fire(abilityId, endsAt)
end

local function feedback(kind: string, abilityId: string?)
	CombatController.Feedback:Fire(kind, abilityId)
	if kind == "Cooldown" or kind == "NoUlt" or kind == "NoAmmo" or kind == "NoCharges" or kind == "NoTarget" then
		call("SoundController", "Play", "Denied", nil, { Volume = 0.5 })
	end
end

function CombatController.IsSuppressed(ability: Map?): (boolean, string?)
	local input = controller("InputController")
	if input and type(input.CombatEnabled) == "function" then
		local ok, on = pcall(input.CombatEnabled)
		if ok and on == false then
			return true, "Context"
		end
	end
	local c = localChar()
	if c == nil or rootOf(c) == nil then
		return true, "NoCharacter"
	end
	if c:GetAttribute("Dead") == true then
		return true, "Dead"
	end
	if c:GetAttribute("Downed") == true then
		return true, "Downed"
	end
	if statusActive(c, "Stunned") then
		return true, "Stunned"
	end
	if statusActive(c, "Boxed") or c:GetAttribute("SoulMode") == "Boxed" then
		return true, "Boxed"
	end
	if ability and ability.Slot ~= "M1" and statusActive(c, "Silenced") then
		return true, "Silenced"
	end
	local rs = ReplicatedStorage:FindFirstChild("RoundState")
	if rs and rs:GetAttribute("Phase") == "Intro" then
		return true, "Intro"
	end
	return false, nil
end

---------------------------------------------------------------------------------------------------
-- Aim

local function aimRay(): (Vector3, Vector3)
	local cam = controller("CameraController")
	if cam and type(cam.AimRay) == "function" then
		local ok, o, d = pcall(cam.AimRay)
		if ok and typeof(o) == "Vector3" and typeof(d) == "Vector3" then
			return o, d
		end
	end
	local camera = game:GetService("Workspace").CurrentCamera
	if camera then
		local vp = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		return ray.Origin, ray.Direction
	end
	return Vector3.zero, Vector3.new(0, 0, -1)
end

local function aimPoint(maxDist: number): Vector3
	local cam = controller("CameraController")
	if cam and type(cam.AimPoint) == "function" then
		local ok, p = pcall(cam.AimPoint, maxDist)
		if ok and typeof(p) == "Vector3" then
			return p
		end
	end
	local o, d = aimRay()
	local W = game:GetService("Workspace")
	local hit = W:Raycast(o, d.Unit * maxDist, Lib.RaycastParams())
	return if hit then hit.Position else o + d.Unit * maxDist
end

local function groundAt(p: Vector3): Vector3?
	return Lib.Ground(p + Vector3.new(0, 3, 0), 64)
end

-- Living candidates for Target (enemies) / Ally (allies incl. self) abilities. Invisible enemies are never offered.
local function candidates(enemies: boolean): { { Model: Model, Pos: Vector3 } }
	local me = localChar()
	local out = {}
	local t = now()
	for _, m in Lib.Characters() do
		if m:GetAttribute("Dead") ~= true and m.Parent ~= nil then
			local ok = if enemies then Teams.AreEnemies(me, m) else Teams.AreAllies(me, m)
			if ok and enemies and CombatController.IsHidden(m, t) then
				ok = false
			end
			if ok and (enemies == false or m:GetAttribute("Downed") ~= true) then
				local r = rootOf(m)
				if r then
					table.insert(out, { Model = m, Pos = r.Position })
				end
			end
		end
	end
	return out
end

local function softTarget(ability: Map, enemies: boolean): Model?
	local me = localChar()
	local root = rootOf(me)
	if root == nil then
		return nil
	end
	local range = (if type(ability.Range) == "number" then ability.Range else 40) + 2
	local o, d = aimRay()
	local t = CombatController.SelectTarget(o, d, root.Position, candidates(enemies), range, TARGET_CONE)
	if t == nil and not enemies then
		return me
	end
	return t
end

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local W = game:GetService("Workspace")
	local hit = W:Raycast(from, to - from, Lib.RaycastParams())
	return hit == nil
end

---------------------------------------------------------------------------------------------------
-- Indicators (kit Indicator[abilityId] via FxController, else generic per aim mode)

local function genericIndicator(ability: Map): Map?
	local mode = ability.Aim
	local white = Lib.Colors.White
	if mode == "Ground" then
		local radius = if ability.Numbers and type(ability.Numbers.Radius) == "number"
			then ability.Numbers.Radius
			else 2.5
		local circle = Lib.GroundCircle(Vector3.zero, radius, white, { Rim = 0.18, Fill = 0.85, Height = 0.16 })
		return {
			Update = function(_self: any, aim: Vector3, _charge: number)
				circle:SetCenter(aim)
			end,
			Destroy = function(_self: any)
				circle:Destroy()
			end,
		}
	elseif mode == "Target" or mode == "Ally" then
		local color = if mode == "Target" then Lib.Colors.Red else Lib.Colors.Green
		local ring = Lib.GroundCircle(Vector3.zero, 2.4, color, { Rim = 0.22, Fill = 0.8, Height = 0.16 })
		ring:SetVisible(false)
		return {
			Update = function(_self: any, _aim: Vector3, _charge: number, target: Model?)
				local r = rootOf(target)
				if r then
					ring:SetVisible(true)
					ring:SetCenter(r.Position - Vector3.new(0, 2.8, 0))
				else
					ring:SetVisible(false)
				end
			end,
			Destroy = function(_self: any)
				ring:Destroy()
			end,
		}
	elseif mode == "Direction" or mode == "Self" then
		-- direction arrow: a lane along the flat aim with a chevron head (Self: a short facing arrow)
		local len = if mode == "Self"
			then 6
			else math.min(if type(ability.Range) == "number" then ability.Range else 30, 60)
		local lane = Lib.Lane(CFrame.new(), len, 1.2, white, { Fill = 0.85, Edge = 0.12, Height = 0.12 })
		local headL = Lib.Part("Block", Vector3.new(0.34, 0.14, 3), PARK, white, Enum.Material.Neon, 0.15)
		local headR = Lib.Part("Block", Vector3.new(0.34, 0.14, 3), PARK, white, Enum.Material.Neon, 0.15)
		return {
			Update = function(_self: any, aim: Vector3, charge: number)
				local root = rootOf(localChar())
				if root then
					local feet = root.Position - Vector3.new(0, 2.8, 0)
					local dir = CombatController.FlatDir(aim - root.Position, root.CFrame.LookVector)
					local base = Lib.LookAlong(feet, dir)
					lane:SetCFrame(base)
					lane:SetFill(if mode == "Self" then 1 else charge)
					local tip = base * CFrame.new(0, 0.12, -len - 0.6)
					local pulse = 0.15 + 0.12 * math.sin(os.clock() * 8)
					for side, part in { [-1] = headL, [1] = headR } do
						-- each half of the chevron leans back from the tip at 40 degrees
						part.CFrame = tip * CFrame.Angles(0, side * math.rad(40), 0) * CFrame.new(0, 0, 1.4)
						part.Transparency = pulse
					end
				end
			end,
			Destroy = function(_self: any)
				lane:Destroy()
				Lib.Release(headL)
				Lib.Release(headR)
			end,
		}
	end
	return nil
end

local function hasKitIndicator(ability: Map): boolean
	local fx = controller("FxController")
	local char = localChar()
	if fx == nil or char == nil or type(fx.Kit) ~= "function" then
		return false
	end
	local ok, kit = pcall(fx.Kit, char:GetAttribute("KitId"))
	return ok and type(kit) == "table" and type(kit.Indicator) == "table" and type(kit.Indicator[ability.Id]) == "function"
end

local function makeIndicator(ability: Map): Map?
	local fx = controller("FxController")
	if fx and type(fx.Indicator) == "function" then
		local ok, ind = pcall(fx.Indicator, ability.Id)
		if ok and type(ind) == "table" then
			return ind
		end
	end
	return genericIndicator(ability)
end

local function destroyIndicator(ind: Map?)
	if ind and type(ind.Destroy) == "function" then
		pcall(ind.Destroy, ind)
	end
end

local function cancelCharge()
	local c = charging
	if c then
		charging = nil
		destroyIndicator(c.Indicator)
		CombatController.ChargeChanged:Fire(nil, 0)
		call("MovementController", "Facing", false, "CombatCharge")
	end
end

local function cancelAim()
	local a = aiming
	if a then
		aiming = nil
		destroyIndicator(a.Indicator)
	end
end

---------------------------------------------------------------------------------------------------
-- Casting

local function nextCastId(): number
	castCounter += 1
	if castCounter > 2 ^ 30 then
		castCounter = 1
	end
	return castCounter
end

local function cast(ability: Map, charge: number?, forcedTarget: Model?): boolean
	local suppressedNow = CombatController.IsSuppressed(ability)
	if suppressedNow then
		feedback("Suppressed", ability.Id)
		return false
	end
	local char = localChar() :: Model
	local root = rootOf(char) :: BasePart
	local id: string = ability.Id
	if not CombatController.IsReady(id) then
		feedback("Cooldown", id)
		return false
	end
	if ability.Ult then
		local ult = char:GetAttribute("Ult")
		if type(ult) ~= "number" or ult < 100 - 1e-6 then
			feedback("NoUlt", id)
			return false
		end
	end
	local usesAmmo = ammo.Ability ~= nil and ammo.Ability.Id == id
	if usesAmmo and (ammo.Ammo or 1) <= 0 then
		feedback("NoAmmo", id)
		return false
	end
	local target: Model? = forcedTarget
	if ability.Aim == "Target" then
		target = target or softTarget(ability, true)
		if target == nil then
			feedback("NoTarget", id)
			return false
		end
	elseif ability.Aim == "Ally" then
		target = target or softTarget(ability, false)
	end
	local range = if type(ability.Range) == "number" then ability.Range else Config.Combat.MaxAimRange
	local castId = nextCastId()
	local targetRoot = rootOf(target)
	local payload = CombatController.BuildPayload(ability, {
		Root = root.Position,
		Look = root.CFrame.LookVector,
		Aim = aimPoint(math.min(range + 20, Config.Combat.MaxAimRange)),
		Ground = groundAt,
		Target = target,
		TargetPos = if targetRoot then targetRoot.Position else nil,
		Charge = charge,
		CastId = castId,
	})
	-- local cooldown + pending prediction
	local prev = cooldowns[id] or 0
	local predictedEnd = now() + (ability.Cooldown or 0)
	setCooldown(id, predictedEnd)
	-- combo
	local comboIndex = 1
	if type(ability.Combo) == "number" and ability.Combo > 1 then
		local window = if type(ability.Numbers.ComboWindow) == "number"
			then ability.Numbers.ComboWindow
			else Config.Combat.ComboResetTime
		local prevIndex = if combo.Ability == id then combo.Index else 0
		comboIndex = DamageMath.NextComboIndex(prevIndex, combo.Last, now(), window, ability.Combo)
		combo.Index = comboIndex
		combo.Last = now()
		combo.Ability = id
		CombatController.ComboChanged:Fire(id, comboIndex)
	end
	if usesAmmo then
		local a = (ammo.Ammo or ammo.Max or 1) - 1
		ammo.Ammo = a
		if a <= 0 then
			local reload = if type(ability.Numbers.Reload) == "number" then ability.Numbers.Reload else 1.5
			ammo.ReloadEnds = now() + reload
		end
		CombatController.AmmoChanged:Fire(ammo.Ammo, ammo.Max, ammo.ReloadEnds > 0)
	end
	-- prediction: face the cast, cast clip, kit Predict
	call("MovementController", "FaceFor", 0.6)
	local fx = controller("FxController")
	local clip: string? = nil
	if fx then
		pcall(fx.MarkPredicted, castId, id)
		local okClip, c = pcall(fx.CastClip, ability, comboIndex)
		clip = if okClip then c else nil
		-- PlayCastClip returns the clip it really played (AnimController kit overrides): stop that one on rollback
		local okPlay, played = pcall(fx.PlayCastClip, char, ability, comboIndex)
		if okPlay and type(played) == "string" then
			clip = played
		end
		pcall(fx.Predict, id, payload)
	end
	pending[castId] = { Ability = id, T = os.clock(), Prev = prev, Predicted = predictedEnd, Clip = clip }
	Net.Client.Fire("Cast", id, payload)
	CombatController.Casted:Fire(id, payload)
	return true
end

local function castVerdict(): boolean
	local suppressedNow = CombatController.IsSuppressed({ Slot = "F" })
	if suppressedNow then
		feedback("Suppressed", VERDICT_ID)
		return false
	end
	if not CombatController.IsReady(VERDICT_ID) then
		feedback("Cooldown", VERDICT_ID)
		return false
	end
	local char = localChar() :: Model
	local root = rootOf(char) :: BasePart
	local cfg = Config.VerdictBox
	local o, d = aimRay()
	local look = CombatController.FlatDir(d, root.CFrame.LookVector)
	local list = {}
	for _, c in candidates(true) do
		-- humans only, in the cone along the aim, with line of sight (server re-checks all of it)
		if Teams.TeamOf(c.Model) == "Humans" and c.Model:GetAttribute("SoulMode") ~= "Boxed" then
			local to = CombatController.FlatDir(c.Pos - root.Position, look)
			if to:Dot(look) >= (cfg.ConeDot or 0.82) - 0.05 and hasLineOfSight(root.Position, c.Pos) then
				table.insert(list, c)
			end
		end
	end
	local target = CombatController.SelectTarget(o, d, root.Position, list, (cfg.Range or 28) + 2, 45)
	if target == nil then
		feedback("NoTarget", VERDICT_ID)
		return false
	end
	local tRoot = rootOf(target) :: BasePart
	local castId = nextCastId()
	local payload = {
		aim = tRoot.Position,
		dir = CombatController.FlatDir(tRoot.Position - root.Position, look),
		target = target,
		castId = castId,
	}
	local prev = cooldowns[VERDICT_ID] or 0
	local predictedEnd = now() + (cfg.Cooldown or 40)
	setCooldown(VERDICT_ID, predictedEnd)
	local fx = controller("FxController")
	local clip = "Point"
	local played = false
	if fx then
		pcall(fx.MarkPredicted, castId, VERDICT_ID)
		-- same clip other clients play for this cast (AnimController: family "Verdict" clip, else "Point")
		local okPlay, name = pcall(fx.PlayCastClip, char, { Id = VERDICT_ID }, nil)
		if okPlay and type(name) == "string" then
			clip = name
			played = true
		end
	end
	if not played then
		call("AnimController", "Play", char, "Point", { FadeIn = 0.05 })
	end
	call("MovementController", "FaceFor", 0.8)
	pending[castId] = { Ability = VERDICT_ID, T = os.clock(), Prev = prev, Predicted = predictedEnd, Clip = clip }
	Net.Client.Fire("Cast", VERDICT_ID, payload)
	CombatController.Casted:Fire(VERDICT_ID, payload)
	return true
end

local function rollback(p: Pending, castId: number)
	pending[castId] = nil
	local char = localChar()
	if char and p.Clip then
		call("AnimController", "Stop", char, p.Clip, 0.12)
	end
	if combo.Ability == p.Ability and combo.Index > 0 then
		combo.Index -= 1
		CombatController.ComboChanged:Fire(p.Ability, combo.Index)
	end
	if ammo.Ability and ammo.Ability.Id == p.Ability and ammo.Ammo and ammo.Max then
		ammo.Ammo = math.min(ammo.Max, ammo.Ammo + 1)
		if ammo.Ammo > 0 then
			ammo.ReloadEnds = 0
		end
		CombatController.AmmoChanged:Fire(ammo.Ammo, ammo.Max, ammo.ReloadEnds > 0)
	end
	feedback("Rejected", p.Ability)
end

local function onServerCooldown(abilityId: any, endsAt: any)
	if type(abilityId) ~= "string" or type(endsAt) ~= "number" then
		return
	end
	local t = now()
	for castId, p in pending do
		if p.Ability == abilityId then
			if endsAt < t + 0.05 and p.Predicted > t + 0.25 then
				rollback(p, castId) -- the server refused this cast
			else
				pending[castId] = nil
			end
		end
	end
	setCooldown(abilityId, endsAt)
end

---------------------------------------------------------------------------------------------------
-- Block / Dash (humans)

local function sendBlock(on: boolean)
	blockSent = on
	lastBlockSend = os.clock()
	Net.Client.Fire("Block", on)
end

local function dash()
	if CombatController.IsSuppressed(nil) then
		feedback("Suppressed", "Dash")
		return
	end
	local char = localChar() :: Model
	if statusActive(char, "Rooted") then
		feedback("Suppressed", "Dash")
		return
	end
	local charges = char:GetAttribute("DashCharges")
	if type(charges) == "number" and charges < 1 then
		feedback("NoCharges", "Dash")
		return
	end
	if os.clock() - lastDash < 0.22 then
		return
	end
	lastDash = os.clock()
	local root = rootOf(char) :: BasePart
	local hum = char:FindFirstChildOfClass("Humanoid")
	local move = if hum then hum.MoveDirection else Vector3.zero
	local dir: Vector3
	if Vector3.new(move.X, 0, move.Z).Magnitude > 0.1 then
		dir = CombatController.FlatDir(move, root.CFrame.LookVector)
	else
		local _, d = aimRay()
		dir = CombatController.FlatDir(d, root.CFrame.LookVector)
	end
	-- the dash gets a castId: MovementController plays our Dash clip now and AnimController skips the echo
	local castId = nextCastId()
	call("MovementController", "PredictDash", dir, castId)
	local fx = controller("FxController")
	if fx and type(fx.PlayDash) == "function" then
		pcall(fx.PlayDash, char, dir, true)
	end
	Net.Client.Fire("Dash", dir, castId)
	CombatController.Casted:Fire("Dash", { dir = dir, castId = castId })
end

---------------------------------------------------------------------------------------------------
-- Input

local SLOTS = { M1 = true, Q = true, E = true, R = true, T = true, G = true, Shift = true }

local function beginAbility(ability: Map)
	local supp = CombatController.IsSuppressed(ability)
	if supp then
		feedback("Suppressed", ability.Id)
		return
	end
	local id = ability.Id
	-- pressing something else drops an unfinished aim / charge (no cast)
	if charging and charging.Ability.Id ~= id then
		cancelCharge()
	end
	if aiming and aiming.Ability.Id ~= id then
		cancelAim()
	end
	local castMode = CombatController.CastMode(
		ability,
		CombatController.QuickCast,
		not CombatController.QuickCast and hasKitIndicator(ability)
	)
	if castMode ~= "Press" then
		if not CombatController.IsReady(id) then
			feedback("Cooldown", id)
			return
		end
		if ability.Ult then
			local ult = (localChar() :: Model):GetAttribute("Ult")
			if type(ult) ~= "number" or ult < 100 - 1e-6 then
				feedback("NoUlt", id)
				return
			end
		end
		if castMode == "Charge" then
			charging = { Ability = ability, Start = os.clock(), Indicator = makeIndicator(ability), Charge = 0 }
			call("MovementController", "Facing", true, "CombatCharge")
		else
			aiming = { Ability = ability, Start = os.clock(), Indicator = makeIndicator(ability), Target = nil }
		end
		return
	end
	cast(ability)
	if ability.Slot == "M1" then
		m1Held = true
	end
end

local function endAbility(ability: Map)
	local id = ability.Id
	local c = charging
	if c and c.Ability.Id == id then
		charging = nil
		local charge = CombatController.ChargeOf(os.clock() - c.Start, ability.Hold.MaxTime)
		destroyIndicator(c.Indicator)
		CombatController.ChargeChanged:Fire(nil, 0)
		call("MovementController", "Facing", false, "CombatCharge")
		cast(ability, charge)
		return
	end
	local a = aiming
	if a and a.Ability.Id == id then
		aiming = nil
		destroyIndicator(a.Indicator)
		cast(ability, nil, a.Target)
		return
	end
	if ability.Slot == "M1" then
		m1Held = false
	end
end

local function onAction(action: string, state: string, _input: any)
	if action == "F" then
		if isMonster() then
			if state == "Begin" then
				castVerdict()
			end
		else
			if state == "Begin" then
				if CombatController.IsSuppressed(nil) then
					return
				end
				blockHeld = true
				sendBlock(true)
				local root = rootOf(localChar())
				if root then
					Lib.EmitBurst(
						(root.CFrame * CFrame.new(0, 0.5, -1.6)).Position,
						3.2,
						Color3.fromRGB(150, 210, 255),
						0.18
					)
				end
			elseif state == "End" then
				blockHeld = false
				if blockSent then
					sendBlock(false)
				end
			end
		end
		return
	end
	if action == "Shift" and not isMonster() then
		if state == "Begin" then
			dash()
		end
		return
	end
	if not SLOTS[action] then
		return
	end
	local ability = CombatController.AbilityForSlot(action)
	if ability == nil then
		return
	end
	if state == "Begin" then
		beginAbility(ability)
	elseif state == "End" then
		endAbility(ability)
	end
end

function CombatController.TryCast(abilityId: string): boolean
	if abilityId == VERDICT_ID then
		return castVerdict()
	end
	local kit = CombatController.Kit()
	local ability = if kit then Kits.Ability(kit.Id, abilityId) else nil
	if ability == nil then
		return false
	end
	local charge = if type(ability.Hold) == "table" then 1 else nil
	return cast(ability, charge)
end

---------------------------------------------------------------------------------------------------
-- Per-frame upkeep: charge + indicators, M1 repeat, block re-assert, reload, prediction timeouts

local lastChargeSent = -1

local function step()
	local supp = CombatController.IsSuppressed(nil)
	local c = charging
	if c then
		if supp then
			cancelCharge()
		else
			local ability = c.Ability
			local charge = CombatController.ChargeOf(os.clock() - c.Start, ability.Hold.MaxTime)
			c.Charge = charge
			if math.abs(charge - lastChargeSent) > 0.01 then
				lastChargeSent = charge
				CombatController.ChargeChanged:Fire(ability.Id, charge)
			end
			local range = if type(ability.Range) == "number" then ability.Range else 60
			local aim = aimPoint(range)
			local ind = c.Indicator
			if ind and type(ind.Update) == "function" then
				pcall(ind.Update, ind, aim, charge, nil)
			end
			local char = localChar()
			if char then
				call("AnimController", "SetAim", char, aim)
			end
		end
	end
	local a = aiming
	if a then
		if supp then
			cancelAim()
		else
			local ability = a.Ability
			local range = if type(ability.Range) == "number" then ability.Range else 60
			local aim = aimPoint(range + 20)
			local root = rootOf(localChar())
			local shown = aim
			if ability.Aim == "Ground" and root then
				local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
				if flat.Magnitude > range then
					flat = flat.Unit * range
					shown = Vector3.new(root.Position.X + flat.X, aim.Y, root.Position.Z + flat.Z)
				end
				shown = groundAt(shown) or shown
			elseif ability.Aim == "Target" then
				a.Target = softTarget(ability, true)
			elseif ability.Aim == "Ally" then
				a.Target = softTarget(ability, false)
			end
			local ind = a.Indicator
			if ind and type(ind.Update) == "function" then
				pcall(ind.Update, ind, shown, 0, a.Target)
			end
		end
	end
	-- M1 repeat while held (combo keeps going)
	if m1Held and not supp and charging == nil and aiming == nil then
		local input = controller("InputController")
		local held = true
		if input and type(input.IsDown) == "function" then
			local ok, d = pcall(input.IsDown, "M1")
			held = ok and d == true
		end
		if not held then
			m1Held = false
		else
			local ability = CombatController.AbilityForSlot("M1")
			if ability and CombatController.IsReady(ability.Id) and (ammo.Ability == nil or (ammo.Ammo or 1) > 0) then
				cast(ability)
			end
		end
	end
	-- block: release when suppressed, re-assert after dash / stun ends while F is still held
	local char = localChar()
	if blockSent and supp then
		sendBlock(false)
	elseif
		blockHeld
		and not supp
		and char
		and char:GetAttribute("Blocking") ~= true
		and os.clock() - lastBlockSend > 0.5
	then
		sendBlock(true)
	end
	-- reload mirror
	if ammo.ReloadEnds > 0 and now() >= ammo.ReloadEnds then
		ammo.ReloadEnds = 0
		ammo.Ammo = ammo.Max
		CombatController.AmmoChanged:Fire(ammo.Ammo, ammo.Max, false)
	end
	-- predictions the server never answered (rate limit, lost character): give the cooldown back
	local clock = os.clock()
	for castId, p in pending do
		if clock - p.T > PENDING_TIMEOUT then
			if (cooldowns[p.Ability] or 0) == p.Predicted then
				setCooldown(p.Ability, p.Prev)
			end
			rollback(p, castId)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Character lifecycle

local function resetForCharacter(model: Model?)
	for _, conn in charTrove do
		conn:Disconnect()
	end
	table.clear(charTrove)
	cancelCharge()
	cancelAim()
	table.clear(pending)
	for id in cooldowns do
		cooldowns[id] = nil
		CombatController.CooldownChanged:Fire(id, 0)
	end
	combo.Index, combo.Last, combo.Ability = 0, -math.huge, nil
	blockHeld, blockSent, m1Held = false, false, false
	character = model
	local kit = CombatController.Kit()
	local a = CombatController.AmmoAbility(kit)
	ammo.Ability = a
	if a then
		ammo.Max = a.Numbers.Ammo
		ammo.Ammo = a.Numbers.Ammo
	else
		ammo.Max = nil
		ammo.Ammo = nil
	end
	ammo.ReloadEnds = 0
	CombatController.AmmoChanged:Fire(ammo.Ammo, ammo.Max, false)
	if model then
		-- the server may mirror ammo as attributes ("Ammo", "ReloadEndsAt"): prefer them when present
		local function syncAmmo()
			local v = model:GetAttribute("Ammo")
			if type(v) == "number" then
				ammo.Ammo = v
				local r = model:GetAttribute("ReloadEndsAt")
				ammo.ReloadEnds = if type(r) == "number" and r > now() then r else 0
				CombatController.AmmoChanged:Fire(ammo.Ammo, ammo.Max, ammo.ReloadEnds > 0)
			end
		end
		table.insert(charTrove, model:GetAttributeChangedSignal("Ammo"):Connect(syncAmmo))
		table.insert(
			charTrove,
			model:GetAttributeChangedSignal("KitId"):Connect(function()
				resetForCharacter(model)
			end)
		)
		syncAmmo()
	end
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

function CombatController.Init() end

function CombatController.Start()
	local input = controller("InputController")
	if input and input.Action then
		input.Action:Connect(function(action: string, state: string, inp: any)
			local ok, err = pcall(onAction, action, state, inp)
			if not ok then
				warn("[CombatController] input failed: " .. tostring(err))
			end
		end)
		if input.Cancelled then
			-- Escape / right-click / forced release: drop a held aim or charge without casting
			input.Cancelled:Connect(function()
				if aiming or charging then
					cancelAim()
					cancelCharge()
					call("SoundController", "Play", "UiBack", nil, { Volume = 0.4 })
				end
			end)
		end
	else
		warn("[CombatController] InputController missing: combat input disabled")
	end
	task.spawn(function()
		local ok, err = pcall(Net.Client.On, "Cooldown", onServerCooldown)
		if not ok then
			warn("[CombatController] cannot listen to Cooldown: " .. tostring(err))
		end
	end)
	-- authoritative combo index from the server's Start packet of our own casts
	local fx = controller("FxController")
	if fx and fx.AbilityFx then
		fx.AbilityFx:Connect(function(packet: Map)
			if packet.phase == "Start" and packet.caster == localChar() and type(packet.data) == "table" then
				local c = packet.data.combo
				if type(c) == "number" and packet.ability == combo.Ability and c ~= combo.Index then
					combo.Index = c
					CombatController.ComboChanged:Fire(packet.ability, c)
				end
			end
		end)
	end
	local state = controller("StateController")
	if state and type(state.Setting) == "function" then
		local ok, v = pcall(state.Setting, "QuickCast", true)
		CombatController.QuickCast = not ok or v ~= false
		if state.SettingChanged then
			state.SettingChanged:Connect(function(key: string, value: any)
				if key == "QuickCast" then
					CombatController.QuickCast = value ~= false
					cancelAim() -- an aim begun under the old rule must not wait for a release
				end
			end)
		end
	end
	local lp = Players.LocalPlayer
	if lp then
		lp.CharacterAdded:Connect(function(c)
			task.defer(resetForCharacter, c)
		end)
		if lp.Character then
			resetForCharacter(lp.Character)
		end
	end
	RunService.PreRender:Connect(function()
		if character ~= localChar() then
			resetForCharacter(localChar())
		end
		local ok, err = pcall(step)
		if not ok then
			warn("[CombatController] step failed: " .. tostring(err))
		end
	end)
end

return CombatController
