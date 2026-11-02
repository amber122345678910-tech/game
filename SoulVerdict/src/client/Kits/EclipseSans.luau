--!strict
-- Client kit: Eclipse Sans — "The Void Wanderer" (SPEC §9.1). Visuals for every AbilityFx phase the server kit
-- (src/server/Kits/EclipseSans.luau) broadcasts. Beams, orbs, star rain and void fire are hazards drawn by
-- HazardVisuals from their own packets (telegraphs in the colour rule, visual = hitbox); this module adds the
-- rifts, props and screen work around them and registers three hazard visuals:
--   "EclipseStar"      (Rain)  Props.StarBone comets falling on a slant into their marked impact circles
--   "EclipseWell"      (Orb)   Props.VoidOrb black star facing the camera + the IMPLOSION ring (the real hitbox,
--                              filling up as the implosion nears; the server disables the generic telegraph)
--   "EclipseVoidFire"  (Zone)  navy/violet/cyan void flames with dark smoke and rising star sparks
-- Visual identity: deep navy / violet / cyan, starfield motes, rift rings, eerie silence-then-burst timing.
--
--   VoidLash      Start/Predict: dark whip arcs (two sweeps, then a straight crack at full reach); Lash: impact
--   RiftBlaster   Start/Predict: ring eye flares; Rift {pos, dir, delay}: a Props.Rift tears open beside the target,
--                 drinks in light (silence) while the void-wolf skull emerges, bursts when it fires, then seals.
--                 Indicator: the beam lane across the aim point + the ghost rift on the same side the server picks
--   GravityWell   Start/Predict: hand charge; Throw {from, to, time}: the black star arcs to its landing point;
--                 Fizzle {pos}. Indicator: pull ring + implosion ring
--   Starfall      Start/Predict: hand raised, eye; Starfall {center, radius, ...}: a sky rift opens above the area
--                 for the whole rain. Indicator: area ring
--   RiftTrap      Trap {id, pos, radius, reveal, arm, lifetime}: a flat rift that sinks into the ground (seen by all
--                 while it arms), then visible to the monster side only — humans see it inside RevealDistance
--                 (TrapVisibility); Spring {id, pos, victim, to}: eruption + exit rift + root ring; Collapse {id}.
--                 Indicator: trap ring + reveal-distance ring
--   VoidStep      Predict/Enter {from, to}: entry portal + void streak; Teleport {from, to}: exit portal, local blink.
--                 Indicator: destination portal ghost + range ring. Invisibility: OnCharacter hides his parts
--                 (enemies: fully, himself: ghosted) while the Invisible attribute is set (framework gap: nothing
--                 else hides an invisible character's parts)
--   TotalEclipse  Start: the light drains toward him (silence); Eclipse {duration, vision}: burst + an eclipsed sun
--                 overhead; HUMAN viewers: GraphicsController.PushTimed("EclipseUlt", "EclipseDark", ...), a held
--                 vision vignette, a VisionRadius light around their own character and a subtitle; the caster: tint
--                 + subtitle. End (or the Status_TotalEclipse attribute vanishing): the light returns.
-- OnCharacter: starfield motes, the Void Karma ring at his feet (AuraRadius; VisionRadius during the eclipse),
--   ult-drain motes + popup for a local human inside it, invisibility, FinalForm eye. OnDamageFx: dodge blink.
-- Pure helpers (Lune-tested): Kit.TrapVisibility(ownerSide, distance, reveal) -> 0..1,
--   Kit.RiftSide(ground, casterPos, offset, clearFn) -> (riftPos, beamDir)  (mirror of the server placement)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kits = require(Shared:WaitForChild("Kits")) :: any
local DamageMath = require(Shared:WaitForChild("Combat"):WaitForChild("DamageMath")) :: any
local HazardDefs = require(Shared:WaitForChild("Combat"):WaitForChild("HazardDefs")) :: any
local Strings = require(Shared:WaitForChild("Strings")) :: any

local ClientRoot = script.Parent.Parent
local Lib = require(ClientRoot:WaitForChild("VFX"):WaitForChild("Lib")) :: any
local HazardVisuals = require(ClientRoot:WaitForChild("Controllers"):WaitForChild("HazardVisuals")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local KIT_ID = "EclipseSans"
local LookAlong = HazardDefs.LookAlong

local VOID = Color3.fromRGB(6, 3, 14)
local NAVY = Color3.fromRGB(18, 20, 58)
local VIOLET = Color3.fromRGB(139, 61, 255)
local LILAC = Color3.fromRGB(190, 150, 255)
local CYAN = Color3.fromRGB(120, 235, 255)
local STARLIGHT = Color3.fromRGB(236, 242, 255)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PARK = CFrame.new(0, 1e5, 0)

local CHEST = 2.6 -- same constants as the server placement
local RIFT_LIFT = 0.9

---------------------------------------------------------------------------------------------------
-- Small helpers

local function numbers(abilityId: string): Map
	local a = Kits.Ability(KIT_ID, abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function flat(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		local g = Vector3.new(fallback.X, 0, fallback.Z)
		return if g.Magnitude > 1e-3 then g.Unit else Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

local function easeOutBack(x: number): number
	local c1, c3 = 1.70158, 2.70158
	local y = clamp01(x) - 1
	return 1 + c3 * y * y * y + c1 * y * y
end

local function rootCF(fx: any, character: Model?): CFrame?
	local r = fx.Root(character or fx.Character)
	return if r then r.CFrame else nil
end

local function feetOf(model: Model?): Vector3?
	if model == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local h = (if hum then hum.HipHeight else 2) + root.Size.Y * 0.5
	return root.Position - Vector3.new(0, h, 0)
end

-- Skin-aware tints (Solar / Aurora palettes recolour the void, never the telegraphs).
local function palette(character: Model?): { Void: Color3, Glow: Color3, Eye: Color3 }
	local p = { Void = VIOLET, Glow = LILAC, Eye = CYAN }
	if character then
		local skinId = character:GetAttribute("SkinId")
		if type(skinId) == "string" and skinId ~= "Default" then
			local skin = Kits.Skin(KIT_ID, skinId)
			local pal = skin and skin.Palette
			if pal then
				if typeof(pal.Void) == "Color3" then
					p.Void = pal.Void
					p.Glow = pal.Void:Lerp(WHITE, 0.35)
				end
				if typeof(pal.EyeGlow) == "Color3" then
					p.Eye = pal.EyeGlow
				end
			end
		end
	end
	return p
end

local function controller(name: string): any?
	local folder = ClientRoot:FindFirstChild("Controllers")
	local m = folder and folder:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, r = pcall(require, m)
		if ok and type(r) == "table" then
			return r
		end
	end
	return nil
end

local function localCharacter(): Model?
	local lp = Players.LocalPlayer
	return if lp then lp.Character else nil
end

local function localRoot(): BasePart?
	local c = localCharacter()
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- The local viewer's side: "Monster" | "Humans" | "" (spectators / lobby are treated like humans by callers).
local function localTeam(): string
	local c = localCharacter()
	local team = c and c:GetAttribute("Team")
	if type(team) == "string" and team ~= "" then
		return team
	end
	local lp = Players.LocalPlayer
	local role = lp and lp:GetAttribute("Role")
	if role == "Monster" then
		return "Monster"
	elseif role == "Human" then
		return "Humans"
	end
	return ""
end

local function viewerPos(): Vector3?
	local r = localRoot()
	if r then
		return r.Position
	end
	local cam = game:GetService("Workspace").CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

local function cameraPos(): Vector3
	local cam = game:GetService("Workspace").CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.new(0, 50, 50)
end

local function eyeFor(fx: any, seconds: number)
	local char = fx.Character
	local pal = palette(char)
	fx.EyeGlow(char, "Left", pal.Eye, true)
	fx.Delay(seconds, function()
		if char and (char:GetAttribute("FinalForm") == true or fx.State.Eclipsed) then
			return
		end
		fx.EyeGlow(char, "Left", pal.Eye, false)
	end)
end

local function handPos(fx: any): Vector3?
	local hand = fx.Part(fx.Character, "RightHand")
	if hand then
		return hand.Position
	end
	local cf = rootCF(fx)
	return if cf then (cf * CFrame.new(1, 0.5, -1)).Position else nil
end

local function popup(pos: Vector3, key: string, color: Color3, ...: any)
	pcall(Lib.Text, pos, Strings.L(key, ...), color, { Scale = 0.9 })
end

---------------------------------------------------------------------------------------------------
-- Pure helpers (mirrors of the server rules; Lune-tested)

-- How visible a rift trap is to the local viewer (0 = invisible .. 1 = fully shown).
function Kit.TrapVisibility(ownerSide: boolean, distance: number, reveal: number): number
	if ownerSide then
		return 1
	end
	if reveal <= 0 or distance >= reveal then
		return 0
	end
	return 0.8 * clamp01((reveal - distance) / (reveal * 0.6))
end

-- Rift Blaster placement (server rule): beside the aim point on the caster's right unless the left has more room.
-- clearFn(origin, dir, maxDist) -> free distance (walls); returns (riftPos, beamDir).
function Kit.RiftSide(
	ground: Vector3,
	casterPos: Vector3,
	offset: number,
	clearFn: (Vector3, Vector3, number) -> number
): (Vector3, Vector3)
	local fwd = flat(ground - casterPos, Vector3.new(0, 0, -1))
	local right = fwd:Cross(Vector3.yAxis).Unit
	local chest = ground + Vector3.new(0, CHEST, 0)
	local off = math.max(4, offset)
	local bestSide, bestClear = 1, -1
	for _, s in { 1, -1 } do
		local clear = clearFn(chest, right * s, off)
		if clear > bestClear + 0.5 then
			bestSide, bestClear = s, clear
		end
	end
	local pos = chest + right * (bestSide * math.max(4, bestClear)) + Vector3.new(0, RIFT_LIFT, 0)
	local d = chest - pos
	return pos, (if d.Magnitude > 1e-3 then d.Unit else -right * bestSide)
end

local function clientClear(origin: Vector3, dir: Vector3, maxDist: number): number
	local W = game:GetService("Workspace")
	local hit = W:Raycast(origin, dir.Unit * maxDist, Lib.RaycastParams())
	if hit then
		return math.max(0, (hit.Position - origin).Magnitude - 1.5)
	end
	return maxDist
end

---------------------------------------------------------------------------------------------------
-- Prop helpers: pooled rifts, model alpha

local partCache: { [Model]: { BasePart } } = setmetatable({}, { __mode = "k" }) :: any

local function partsOf(m: Model): { BasePart }
	local list = partCache[m]
	if list == nil then
		list = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		partCache[m] = list
	end
	return list
end

local function glowLight(m: Model): PointLight?
	local primary = m.PrimaryPart
	local l = primary and primary:FindFirstChild("Glow")
	return if l and l:IsA("PointLight") then l else nil
end

-- 1 = as authored, 0 = invisible (LocalTransparencyModifier keeps the authored transparency).
local function setAlpha(m: Model, alpha: number)
	local mod = 1 - clamp01(alpha)
	for _, p in partsOf(m) do
		p.LocalTransparencyModifier = mod
	end
	local l = glowLight(m)
	if l then
		l.Enabled = alpha > 0.05
	end
end

local riftPool: { [string]: { Model } } = {}

local function acquireRift(color: Color3, radius: number): Model?
	local Rift = Lib.Prop("Rift")
	if Rift == nil then
		return nil
	end
	local r = math.max(0.5, math.floor(radius * 4 + 0.5) / 4)
	local key = color:ToHex() .. "|" .. tostring(r)
	local pool = riftPool[key]
	while pool and #pool > 0 do
		local m = table.remove(pool) :: Model
		if m.Parent ~= nil then
			setAlpha(m, 1)
			return m
		end
	end
	local ok, built = pcall(Rift.Build, color, r)
	if not ok or built == nil then
		return nil
	end
	local m: Model = built
	Lib.PrepModel(m)
	m:SetAttribute("PoolKey", key)
	m:PivotTo(PARK)
	m.Parent = Lib.Folder()
	return m
end

local function releaseRift(m: Model?)
	if m == nil or m.Parent == nil then
		return
	end
	setAlpha(m, 0)
	m:PivotTo(PARK)
	local key = m:GetAttribute("PoolKey")
	if type(key) ~= "string" then
		m:Destroy()
		return
	end
	local pool = riftPool[key]
	if pool == nil then
		pool = {}
		riftPool[key] = pool
	end
	if #pool < 6 then
		table.insert(pool, m)
	else
		m:Destroy()
	end
end

local function setOpen(m: Model, alpha: number)
	local Rift = Lib.Prop("Rift")
	if Rift then
		Rift.SetOpen(m, math.max(0.02, alpha))
	end
end

-- A rift that tears open (openTime, Back overshoot), holds, then seals (closeTime). opts.OnFrame(elapsed, model).
-- Returns the model (or nil when props are unavailable: a ring flash stands in).
local function riftEvent(
	cf: CFrame,
	color: Color3,
	radius: number,
	openTime: number,
	hold: number,
	closeTime: number,
	opts: Map?
): Model?
	local o = opts or {}
	local m = acquireRift(color, radius)
	if m == nil then
		Lib.Ring(cf, radius, color, openTime + 0.2, 0.25)
		return nil
	end
	local model: Model = m
	model:PivotTo(cf)
	setOpen(model, 0.02)
	local last = -1
	Lib.Animate(openTime + hold + closeTime, function(_a, _dt, e)
		if model.Parent == nil then
			return true
		end
		local open: number
		if e < openTime then
			open = easeOutBack(e / math.max(0.01, openTime))
		elseif e < openTime + hold then
			open = 1
		else
			open = 1 - clamp01((e - openTime - hold) / math.max(0.01, closeTime)) ^ 2
		end
		if math.abs(open - last) > 0.01 then
			last = open
			setOpen(model, open)
		end
		local cb = o.OnFrame
		if cb then
			cb(e, model)
		end
		return nil
	end, function()
		releaseRift(model)
	end)
	Lib.EmitRing(cf.Position, radius * 1.3, color, 0.35, { Axis = cf.LookVector, Brightness = 2 })
	return model
end

---------------------------------------------------------------------------------------------------
-- Void Lash (M1)

local function whipSwing(fx: any, combo: number)
	local cf = rootCF(fx)
	if cf == nil then
		return
	end
	local N = numbers("VoidLash")
	local reach = (N.Range or 9) * 0.92
	local pal = palette(fx.Character)
	local last = combo >= 3
	fx.Delay(0.08, function()
		local now = rootCF(fx) or cf
		local base = now * CFrame.new(0, 0.55, 0)
		if not last then
			local from, to = if combo == 1 then 78 else -78, if combo == 1 then -62 else 62
			local tilt = if combo == 1 then CFrame.identity else CFrame.Angles(0, 0, math.rad(-14))
			-- dark core lash + a violet afterglow a beat behind it
			Lib.Slash(base * tilt, {
				Radius = reach,
				From = from,
				To = to,
				Width = 0.42,
				Color = pal.Void,
				Core = NAVY,
				Duration = 0.2,
				Thickness = 0.1,
			})
			fx.Delay(0.04, function()
				Lib.Slash(base * tilt * CFrame.new(0, 0.12, 0), {
					Radius = reach * 0.97,
					From = from,
					To = to,
					Width = 0.22,
					Color = pal.Glow,
					Core = STARLIGHT,
					Duration = 0.16,
				})
			end)
			for i = 1, 4 do
				local a = math.rad(from + (to - from) * (i / 5))
				local p = (base * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -reach)).Position
				Lib.Emit("Star", p, 1, { Color = STARLIGHT, Speed = { 0.5, 2 } })
			end
		else
			-- the crack: a straight lash snapping out to full reach after a held breath
			local hand = handPos(fx) or (now * CFrame.new(1, 0.5, -1)).Position
			local tip = (now * CFrame.new(0, -0.2, -reach)).Position
			fx.Delay(0.05, function()
				Lib.Beam(hand, tip, 0.5, pal.Void, 0.22)
				Lib.Line(hand, tip, STARLIGHT, 0.12, 0.16)
				Lib.EmitBurst(tip, 3.2, pal.Glow, 0.22)
				Lib.Emit("Star", tip, 6, { Color = CYAN, Speed = { 3, 8 } })
			end)
		end
		fx.Sound(if last then "Slash" else "Whoosh", fx.Root(fx.Character), { Pitch = if last then 0.8 else 1.1 })
	end)
end

Effects.VoidLash = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			whipSwing(fx, data.combo or 1)
		end
	elseif packet.phase == "Lash" and (data.hits or 0) > 0 then
		local cf = rootCF(fx)
		if cf then
			local pal = palette(fx.Character)
			local reach = if type(data.reach) == "number" then data.reach else 9
			local tip = (cf * CFrame.new(0, 0, -reach * 0.75)).Position
			Lib.EmitRing(tip, if data.last then 3.4 else 2.2, pal.Void, 0.28, { Axis = cf.LookVector })
			Lib.Emit("Spark", tip, if data.last then 12 else 6, { Color = Lib.Colors.Purple, Dir = cf.LookVector })
			if data.last then
				Lib.Flash(tip, pal.Glow, 3, 0.15)
			end
		end
	end
end

Predict.VoidLash = function(fx: any, _payload: Map)
	local idx = 1
	local combat = fx.Combat()
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	whipSwing(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Rift Blaster (Q)

Effects.RiftBlaster = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			eyeFor(fx, 1.6)
		end
	elseif packet.phase == "Rift" and typeof(data.pos) == "Vector3" and typeof(data.dir) == "Vector3" then
		local pal = palette(fx.Character)
		local pos: Vector3 = data.pos
		local dir: Vector3 = data.dir
		local delay = if type(data.delay) == "number" then data.delay else 1.1
		local beamTime = if type(data.beamTime) == "number" then data.beamTime else 0.5
		local width = if type(data.width) == "number" then data.width else 5
		local radius = math.max(3, width * 0.85)
		local cf = LookAlong(pos, dir)
		local burst = false
		local lastSuck = 0
		riftEvent(cf, pal.Void, radius, 0.28, delay + beamTime - 0.28 + 0.15, 0.3, {
			OnFrame = function(e: number, model: Model)
				-- silence: the tear drinks light in, the glow dims as the charge builds
				local l = glowLight(model)
				if e < delay then
					if e - lastSuck > 0.07 then
						lastSuck = e
						local a = math.random() * math.pi * 2
						local p = (cf * CFrame.new(math.cos(a) * radius * 2.2, math.sin(a) * radius * 2.6, -1.5)).Position
						Lib.Emit("Mote", p, 1, { Color = pal.Glow, Dir = pos - p, Speed = { 6, 9 }, Life = { 0.3, 0.4 } })
					end
					if l then
						l.Brightness = 2 * (1 - 0.7 * clamp01(e / delay))
					end
				elseif not burst then
					burst = true
					if l then
						l.Brightness = 6
					end
					Lib.EmitBurst(pos, width * 2.4, pal.Glow, 0.3)
					Lib.EmitBurst(pos, width * 1.2, WHITE, 0.18)
					Lib.EmitRing(pos + dir * 2, width * 1.6, CYAN, 0.35, { Axis = dir, Brightness = 4 })
					Lib.Emit("Star", pos, 10, { Color = STARLIGHT, Dir = dir, Speed = { 12, 26 } })
					fx.ShakeAt(pos, 0.45, 0.3, 40)
				elseif l then
					l.Brightness = math.max(1, l.Brightness - 0.25)
				end
			end,
		})
		fx.Sound("Portal", pos)
		fx.Delay(math.max(0, delay - 0.45), function()
			fx.Sound("BlasterCharge", pos, { Volume = 0.8 })
		end)
	end
end

Predict.RiftBlaster = function(fx: any, _payload: Map)
	eyeFor(fx, 1.6)
end

Indicator.RiftBlaster = function(fx: any): Map?
	local N = numbers("RiftBlaster")
	local width = N.Width or 5
	local length = math.min(N.Length or 60, 48)
	local lane = Lib.Lane(CFrame.new(), length, width, WHITE, { Fill = 0.86, Edge = 0.14, Height = 0.12 })
	local ghost = Lib.Part("Ball", Vector3.new(2.2, 4.6, 0.25), PARK, VIOLET, Enum.Material.Neon, 0.55)
	local target = Lib.GroundCircle(Vector3.zero, 1.4, WHITE, { Rim = 0.18, Fill = 0.8, Height = 0.14 })
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local r = fx.Root(fx.Character)
		if r == nil then
			return
		end
		local pos, dir = Kit.RiftSide(aim, r.Position, N.Offset or 13, clientClear)
		local flatDir = flat(dir, Vector3.new(1, 0, 0))
		lane:SetCFrame(LookAlong(Vector3.new(pos.X, aim.Y, pos.Z), flatDir))
		ghost.CFrame = LookAlong(pos, dir)
		ghost.Transparency = 0.45 + 0.15 * math.sin(os.clock() * 7)
		target:SetCenter(aim)
	end
	function handle.Destroy(_self: any)
		lane:Destroy()
		target:Destroy()
		Lib.Release(ghost)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Gravity Well (E)

local function throwOrb(fx: any, from: Vector3, to: Vector3, time: number)
	local VoidOrb = Lib.Prop("VoidOrb")
	local pal = palette(fx.Character)
	local model: Model? = nil
	if VoidOrb then
		local ok, m = pcall(VoidOrb.Build, 0.55, pal.Void)
		if ok and m then
			model = m
			Lib.PrepModel(m)
			m:PivotTo(CFrame.new(from))
			m.Parent = Lib.Folder()
		end
	end
	local apex = 2 + (to - from).Magnitude * 0.16
	local lastEmit = 0
	Lib.Animate(time, function(a, _dt, e)
		local p = from:Lerp(to, a) + Vector3.new(0, apex * 4 * a * (1 - a), 0)
		if model and model.Parent then
			model:PivotTo(LookAlong(p, cameraPos() - p) * CFrame.Angles(0, 0, e * 9))
		end
		if e - lastEmit > 0.03 then
			lastEmit = e
			Lib.Emit("Mote", p, 1, { Color = pal.Glow, Speed = { 0.2, 1 } })
			Lib.Emit("Star", p, 1, { Color = STARLIGHT, Speed = { 0.2, 1 } })
		end
		return nil
	end, function()
		if model then
			model:Destroy()
		end
		Lib.EmitBurst(to, 4, pal.Void, 0.25)
		Lib.EmitRing(to, 3, pal.Glow, 0.3)
	end)
end

Effects.GravityWell = function(fx: any, packet: Map)
	local data = packet.data or {}
	local phase = packet.phase
	if phase == "Start" then
		if not fx.Predicted then
			local p = handPos(fx)
			if p then
				Lib.EmitBurst(p, 2.4, palette(fx.Character).Void, 0.35)
			end
		end
	elseif phase == "Throw" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
		local time = if type(data.time) == "number" then data.time else 0.4
		throwOrb(fx, data.from, data.to, math.clamp(time, 0.05, 1.5))
		fx.Sound("Whoosh", data.from, { Pitch = 0.7 })
	elseif phase == "Land" and typeof(data.pos) == "Vector3" then
		fx.Sound("Portal", data.pos, { Pitch = 0.6 })
	elseif phase == "Fizzle" and typeof(data.pos) == "Vector3" then
		Lib.EmitBurst(data.pos, 2.5, LILAC, 0.2)
		Lib.Emit("Mote", data.pos, 8, { Color = LILAC })
	end
end

Predict.GravityWell = function(fx: any, _payload: Map)
	local p = handPos(fx)
	if p then
		Lib.EmitBurst(p, 2.4, palette(fx.Character).Void, 0.35)
	end
end

Indicator.GravityWell = function(_fx: any): Map?
	local N = numbers("GravityWell")
	local radius = N.Radius or 14
	local implode = math.min(N.ImplodeRadius or radius * 0.6, radius)
	local pull = Lib.GroundCircle(Vector3.zero, radius, VIOLET, { Rim = 0.16, Fill = 0.93, Height = 0.12 })
	local core = Lib.GroundCircle(Vector3.zero, implode, WHITE, { Rim = 0.22, Fill = 0.85, Height = 0.16 })
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		pull:SetCenter(aim)
		core:SetCenter(aim)
		pull:SetTransparency(0.35 + 0.15 * math.sin(os.clock() * 5), 0.93)
	end
	function handle.Destroy(_self: any)
		pull:Destroy()
		core:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Starfall (R)

Effects.Starfall = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			eyeFor(fx, 1.4)
			local p = handPos(fx)
			if p then
				Lib.Emit("Star", p, 8, { Color = STARLIGHT, Dir = Vector3.yAxis, Speed = { 8, 16 } })
			end
		end
	elseif packet.phase == "Starfall" and typeof(data.center) == "Vector3" then
		local pal = palette(fx.Character)
		local center: Vector3 = data.center
		local radius = if type(data.radius) == "number" then data.radius else 14
		local delay = if type(data.delay) == "number" then data.delay else 0.9
		local count = if type(data.count) == "number" then data.count else 10
		local interval = if type(data.interval) == "number" then data.interval else 0.15
		local height = if type(data.fallHeight) == "number" then data.fallHeight else 42
		local total = delay + (count - 1) * interval
		-- a rift in the sky, lying face-down above the area, pours the stars out
		local sky = CFrame.new(center + Vector3.new(0, height, 0)) * CFrame.Angles(math.pi / 2, 0, 0)
		riftEvent(sky, pal.Void, math.max(4, radius * 0.5), 0.45, math.max(0.2, total - 0.25), 0.5)
		local area = Lib.GroundCircle(center, radius, pal.Void, { Rim = 0.2, Fill = 0.96, Height = 0.1 })
		Lib.Animate(total + 0.6, function(_a, _dt, e)
			local fade = clamp01((e - total) / 0.6)
			area:SetTransparency(0.55 + 0.2 * math.sin(e * 5) + 0.45 * fade, 0.96)
			return nil
		end, function()
			area:Destroy()
		end)
		fx.Sound("Portal", center + Vector3.new(0, height * 0.5, 0), { Pitch = 1.2 })
	end
end

Predict.Starfall = function(fx: any, _payload: Map)
	eyeFor(fx, 1.4)
	local p = handPos(fx)
	if p then
		Lib.Emit("Star", p, 8, { Color = STARLIGHT, Dir = Vector3.yAxis, Speed = { 8, 16 } })
	end
end

Indicator.Starfall = function(_fx: any): Map?
	local N = numbers("Starfall")
	local radius = N.Radius or 14
	local area = Lib.GroundCircle(Vector3.zero, radius, WHITE, { Rim = 0.22, Fill = 0.9, Height = 0.14 })
	local inner = Lib.GroundCircle(Vector3.zero, N.ImpactRadius or 3.5, VIOLET, { Rim = 0.16, Fill = 0.8, Height = 0.16 })
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		area:SetCenter(aim)
		inner:SetCenter(aim)
	end
	function handle.Destroy(_self: any)
		area:Destroy()
		inner:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Rift Trap (T)

type TrapVisual = {
	Id: number,
	Owner: Model,
	Pos: Vector3,
	Radius: number,
	Reveal: number,
	ArmEnd: number,
	Model: Model?,
	Ring: any,
	Alpha: number,
	Dead: boolean,
}

local trapVisuals: { [number]: TrapVisual } = {}

local function ownerSide(owner: Model): boolean
	local lc = localCharacter()
	if lc == owner then
		return true
	end
	local team = owner:GetAttribute("Team")
	return type(team) == "string" and team ~= "" and localTeam() == team
end

local function removeTrap(id: number, erupt: boolean)
	local tv = trapVisuals[id]
	if tv == nil then
		return
	end
	trapVisuals[id] = nil
	tv.Dead = true
	local m = tv.Model
	local ring = tv.Ring
	local start = tv.Alpha
	Lib.Animate(if erupt then 0.25 else 0.4, function(a)
		if m and m.Parent then
			setOpen(m, (1 - a) * (if erupt then 1.25 else 1))
			setAlpha(m, start * (1 - a))
		end
		ring:SetTransparency(1 - 0.6 * start * (1 - a), 1)
		return nil
	end, function()
		releaseRift(m)
		ring:Destroy()
	end)
end

local function placeTrap(fx: any, data: Map)
	local id = data.id
	if type(id) ~= "number" or typeof(data.pos) ~= "Vector3" then
		return
	end
	removeTrap(id, false)
	local owner: Model = fx.Character
	local pal = palette(owner)
	local pos: Vector3 = data.pos
	local radius = if type(data.radius) == "number" then data.radius else 3.5
	local reveal = if type(data.reveal) == "number" then data.reveal else 10
	local arm = if type(data.arm) == "number" then data.arm else 0.75
	local lifetime = if type(data.lifetime) == "number" then data.lifetime else 45
	local m = acquireRift(pal.Void, radius * 0.87)
	if m then
		m:PivotTo(CFrame.new(pos + Vector3.new(0, 0.14, 0)) * CFrame.Angles(-math.pi / 2, 0, 0))
		setOpen(m, 0.05)
	end
	local ring = Lib.GroundCircle(pos, radius, pal.Void, { Rim = 0.2, Fill = 0.9, Height = 0.12 })
	local tv: TrapVisual = {
		Id = id,
		Owner = owner,
		Pos = pos,
		Radius = radius,
		Reveal = reveal,
		ArmEnd = os.clock() + arm,
		Model = m,
		Ring = ring,
		Alpha = 1,
		Dead = false,
	}
	trapVisuals[id] = tv
	Lib.EmitRing(pos + Vector3.new(0, 0.2, 0), radius * 1.4, pal.Glow, 0.4)
	Lib.Emit("Star", pos, 8, { Color = STARLIGHT, Dir = -Vector3.yAxis, Speed = { 2, 5 } })
	local placed = os.clock()
	local lastOpen = -1
	Lib.Animate(lifetime + arm + 2, function(_a, _dt, e)
		if tv.Dead then
			return true
		end
		if owner.Parent == nil then
			removeTrap(id, false)
			return true
		end
		-- the tear opens as it is placed, then settles half-shut into the ground
		local open = if e < 0.25 then easeOutBack(e / 0.25) else 1 - 0.45 * clamp01((e - 0.25) / 0.5)
		if m and math.abs(open - lastOpen) > 0.01 then
			lastOpen = open
			setOpen(m, open)
		end
		local vp = viewerPos()
		local dist = if vp then Vector3.new(vp.X - pos.X, 0, vp.Z - pos.Z).Magnitude else math.huge
		local side = ownerSide(owner)
		local alpha = Kit.TrapVisibility(side, dist, reveal)
		if side then
			alpha = 0.75 -- his own traps read clearly without hiding the floor
		end
		-- everyone sees it sink in while it arms (fair warning for anyone watching)
		local placing = 1 - clamp01((os.clock() - placed) / math.max(0.2, arm + 0.3))
		alpha = math.max(alpha, placing)
		if not side and alpha > 0 then
			alpha *= 0.85 + 0.15 * math.sin(e * 6)
		end
		if math.abs(alpha - tv.Alpha) > 0.02 then
			tv.Alpha = alpha
			if m then
				setAlpha(m, alpha)
			end
		end
		ring:SetTransparency(1 - 0.75 * alpha * (0.8 + 0.2 * math.sin(e * 3)), 1 - 0.12 * alpha)
		return nil
	end, function()
		if not tv.Dead then
			removeTrap(id, false)
		end
	end)
	if fx.IsLocal then
		local count = 0
		for _, other in trapVisuals do
			if other.Owner == owner then
				count += 1
			end
		end
		popup(pos + Vector3.new(0, 2.5, 0), "eclipse.trap.placed", pal.Glow, count, numbers("RiftTrap").MaxTraps or 2)
	end
end

local function springTrap(fx: any, data: Map)
	local pal = palette(fx.Character)
	local id = data.id
	local pos: Vector3? = if typeof(data.pos) == "Vector3" then data.pos else nil
	if type(id) == "number" then
		removeTrap(id, true)
	end
	if pos then
		Lib.EmitBurst(pos + Vector3.new(0, 1.5, 0), 7, pal.Void, 0.3)
		Lib.EmitBurst(pos + Vector3.new(0, 1.5, 0), 3.5, WHITE, 0.15)
		Lib.EmitRing(pos + Vector3.new(0, 0.3, 0), 5, pal.Glow, 0.35)
		Lib.Emit("Star", pos, 14, { Color = STARLIGHT, Dir = Vector3.yAxis, Speed = { 8, 18 } })
		fx.Sound("Portal", pos, { Pitch = 1.3 })
	end
	local victim: Model? = if typeof(data.victim) == "Instance" and data.victim:IsA("Model") then data.victim else nil
	local to: Vector3? = if typeof(data.to) == "Vector3" then data.to else nil
	if to then
		-- exit tear facing Eclipse, the victim tumbles out of it
		local caster = fx.Root(fx.Character)
		local look = if caster then flat(caster.Position - to, Vector3.zAxis) else Vector3.zAxis
		riftEvent(LookAlong(to - look * 0.8, look), pal.Void, 3, 0.12, 0.25, 0.3)
		if pos then
			Lib.Beam(pos + Vector3.new(0, 1, 0), to, 0.35, pal.Glow, 0.3)
		end
		popup(to + Vector3.new(0, 3.2, 0), "eclipse.trap.sprung", pal.Glow)
	end
	if victim then
		local rootTime = numbers("RiftTrap").Root or 1
		local feet = feetOf(victim)
		if feet then
			local ring = Lib.GroundCircle(feet, 1.8, pal.Void, { Rim = 0.3, Fill = 0.8, Height = 0.2 })
			Lib.Animate(rootTime, function(a, _dt, e)
				local f = feetOf(victim)
				if f then
					ring:SetCenter(f)
				end
				ring:SetTransparency(0.15 + 0.25 * math.sin(e * 14) + 0.6 * a * a, 0.8)
				return nil
			end, function()
				ring:Destroy()
			end)
		end
		if victim == localCharacter() then
			fx.Screen.Flash(pal.Void, 0.45, 0.25)
			fx.Shake(0.4, 0.3)
		end
	end
end

Effects.RiftTrap = function(fx: any, packet: Map)
	local data = packet.data or {}
	local phase = packet.phase
	if phase == "Start" then
		if not fx.Predicted then
			local p = handPos(fx)
			if p then
				Lib.EmitBurst(p, 2, palette(fx.Character).Void, 0.3)
			end
		end
	elseif phase == "Trap" then
		placeTrap(fx, data)
	elseif phase == "Spring" then
		springTrap(fx, data)
	elseif phase == "Collapse" and type(data.id) == "number" then
		removeTrap(data.id, false)
	end
end

Predict.RiftTrap = function(fx: any, _payload: Map)
	local p = handPos(fx)
	if p then
		Lib.EmitBurst(p, 2, palette(fx.Character).Void, 0.3)
	end
end

Indicator.RiftTrap = function(_fx: any): Map?
	local N = numbers("RiftTrap")
	local trap = Lib.GroundCircle(Vector3.zero, N.Radius or 3.5, VIOLET, { Rim = 0.24, Fill = 0.8, Height = 0.16 })
	local reveal = Lib.GroundCircle(
		Vector3.zero,
		N.RevealDistance or 10,
		LILAC,
		{ Rim = 0.08, Fill = 1, Height = 0.08, Shadow = false }
	)
	reveal:SetTransparency(0.75, 1)
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		trap:SetCenter(aim)
		reveal:SetCenter(aim)
	end
	function handle.Destroy(_self: any)
		trap:Destroy()
		reveal:Destroy()
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Void Step (Shift)

local function portalAt(fx: any, feet: Vector3, look: Vector3, hold: number)
	local pal = palette(fx.Character)
	local center = feet + Vector3.new(0, 2.9, 0)
	riftEvent(LookAlong(center, look), pal.Void, 2.6, 0.12, hold, 0.25)
	Lib.Emit("Star", center, 8, { Color = STARLIGHT, Speed = { 1, 4 } })
end

Effects.VoidStep = function(fx: any, packet: Map)
	local data = packet.data or {}
	local char = fx.Character
	local pal = palette(char)
	if packet.phase == "Enter" and typeof(data.from) == "Vector3" then
		local from: Vector3 = data.from
		local to: Vector3 = if typeof(data.to) == "Vector3" then data.to else from
		local look = flat(to - from, (rootCF(fx) or CFrame.identity).LookVector)
		if not fx.Predicted then
			portalAt(fx, from - Vector3.new(0, 2.9, 0), look, 0.2)
		end
		Lib.Afterimage(char, pal.Void, 0.4, { Transparency = 0.4, MaxParts = 22 })
		-- the path through the void: a short trail of starlight toward the exit
		for i = 1, 5 do
			local p = from:Lerp(to, i / 6) + Vector3.new(0, math.sin(i) * 0.6, 0)
			fx.Delay(i * 0.02, function()
				Lib.Emit("Star", p, 2, { Color = if i % 2 == 0 then CYAN else STARLIGHT, Speed = { 0.5, 2 } })
			end)
		end
		fx.Sound("Teleport", from, { Pitch = 0.85 })
	elseif packet.phase == "Teleport" and typeof(data.to) == "Vector3" then
		local to: Vector3 = data.to
		local from: Vector3 = if typeof(data.from) == "Vector3" then data.from else to
		local look = flat(to - from, (rootCF(fx) or CFrame.identity).LookVector)
		portalAt(fx, to - Vector3.new(0, 2.9, 0), -look, 0.3)
		Lib.EmitBurst(to, 3.5, pal.Glow, 0.25)
		Lib.EmitRing(to - Vector3.new(0, 2.7, 0), 2.6, pal.Void, 0.3)
		if fx.IsLocal then
			fx.Screen.Flash(BLACK, 0.4, 0.12) -- the blink of passing through
		end
	end
end

Predict.VoidStep = function(fx: any, payload: Map)
	local cf = rootCF(fx)
	if cf == nil then
		return
	end
	local aim = if typeof(payload.aim) == "Vector3" then payload.aim else cf.Position + cf.LookVector * 10
	portalAt(fx, cf.Position - Vector3.new(0, 2.9, 0), flat(aim - cf.Position, cf.LookVector), 0.2)
end

Indicator.VoidStep = function(fx: any): Map?
	local N = numbers("VoidStep")
	local dist = N.Distance or 35
	local marker = Lib.GroundCircle(Vector3.zero, 1.8, VIOLET, { Rim = 0.22, Fill = 0.75, Height = 0.18 })
	local range = Lib.GroundCircle(Vector3.zero, dist, LILAC, { Rim = 0.1, Fill = 1, Height = 0.08, Shadow = false })
	range:SetTransparency(0.8, 1)
	local ghost = Lib.Part("Ball", Vector3.new(2.4, 5, 0.25), PARK, VIOLET, Enum.Material.Neon, 0.6)
	local handle = {}
	function handle.Update(_self: any, aim: Vector3, _charge: number)
		local r = fx.Root(fx.Character)
		if r == nil then
			return
		end
		local dest = DamageMath.ClampAim(r.Position, aim, dist)
		local g = Lib.Ground(dest + Vector3.new(0, 2, 0), 30) or dest
		marker:SetCenter(g)
		range:SetCenter(r.Position - Vector3.new(0, 2.8, 0))
		ghost.CFrame = LookAlong(g + Vector3.new(0, 2.9, 0), flat(g - r.Position, r.CFrame.LookVector))
		ghost.Transparency = 0.5 + 0.15 * math.sin(os.clock() * 6)
	end
	function handle.Destroy(_self: any)
		marker:Destroy()
		range:Destroy()
		Lib.Release(ghost)
	end
	return handle
end

---------------------------------------------------------------------------------------------------
-- Total Eclipse (G): darkness for humans

local darkness: Map = { Token = 0, Gui = nil, Light = nil, Frames = nil }

local function subtitle(gui: ScreenGui, text: string, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "Subtitle"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.8)
	label.Size = UDim2.fromScale(0.6, 0.06)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = BLACK
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.MaxVisibleGraphemes = 0
	label.ZIndex = 5
	label.Parent = gui
	local n = utf8.len(text) or #text
	Lib.Animate(3.2, function(_a, _dt, e)
		if label.Parent == nil then
			return true
		end
		label.MaxVisibleGraphemes = math.floor(n * clamp01(e / 0.9))
		local fade = clamp01((e - 2.4) / 0.8)
		label.TextTransparency = fade
		label.TextStrokeTransparency = 0.3 + 0.7 * fade
		return nil
	end, function()
		label:Destroy()
	end)
end

local function visionGui(): ScreenGui?
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SV_EclipseVision"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- four soft edges: black at the border fading toward the middle (overlapping corners read as a round vignette)
	local frames = {}
	local specs = {
		{ Vector2.new(0, 0), UDim2.fromScale(1, 0.42), 90 },
		{ Vector2.new(0, 1), UDim2.fromScale(1, 0.42), -90 },
		{ Vector2.new(0, 0), UDim2.fromScale(0.36, 1), 0 },
		{ Vector2.new(1, 0), UDim2.fromScale(0.36, 1), 180 },
	}
	for i, s in specs do
		local f = Instance.new("Frame")
		f.Name = "Edge" .. i
		f.AnchorPoint = s[1]
		f.Position = UDim2.fromScale(s[1].X, s[1].Y)
		f.Size = s[2]
		f.BackgroundColor3 = Color3.fromRGB(1, 1, 6)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Rotation = s[3]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = gui
		table.insert(frames, f)
	end
	gui.Parent = pg
	darkness.Frames = frames
	return gui
end

local function stopDarkness(fadeTime: number)
	darkness.Token += 1
	local gfx = controller("GraphicsController")
	if gfx and type(gfx.PopOverride) == "function" then
		pcall(gfx.PopOverride, "EclipseUlt", fadeTime)
	end
	local light: PointLight? = darkness.Light
	darkness.Light = nil
	local gui: ScreenGui? = darkness.Gui
	local frames: { Frame }? = darkness.Frames
	darkness.Gui = nil
	darkness.Frames = nil
	local startB = if light then light.Brightness else 0
	Lib.Animate(fadeTime, function(a)
		if frames then
			for _, f in frames do
				f.BackgroundTransparency = a
			end
		end
		if light and light.Parent then
			light.Brightness = startB * (1 - a)
		end
		return nil
	end, function()
		if gui then
			gui:Destroy()
		end
		if light then
			light:Destroy()
		end
	end)
end

local function startDarkness(duration: number, vision: number)
	stopDarkness(0.05)
	darkness.Token += 1
	local token = darkness.Token
	local gfx = controller("GraphicsController")
	if gfx and type(gfx.PushTimed) == "function" then
		local prio = if type(gfx.PRIORITY) == "table" then gfx.PRIORITY.Gameplay else 100
		pcall(gfx.PushTimed, "EclipseUlt", "EclipseDark", duration, prio, 0.35, 1.2)
	end
	local gui = visionGui()
	darkness.Gui = gui
	-- your own SOUL is the only light left: everything beyond VisionRadius sinks into the dark
	local root = localRoot()
	if root then
		local light = Instance.new("PointLight")
		light.Name = "SV_EclipseVision"
		light.Color = Color3.fromRGB(190, 200, 255)
		light.Brightness = 0
		light.Range = math.clamp(vision, 8, 60)
		light.Shadows = false
		light.Parent = root
		darkness.Light = light
	end
	if gui then
		subtitle(gui, Strings.L("eclipse.dark.human"), STARLIGHT)
	end
	Lib.Animate(duration, function(_a, _dt, e)
		if darkness.Token ~= token then
			return true
		end
		local k = clamp01(e / 0.4)
		local frames: { Frame }? = darkness.Frames
		if frames then
			local breathe = 0.04 * math.sin(e * 1.7)
			for _, f in frames do
				f.BackgroundTransparency = 1 - k * (0.92 + breathe)
			end
		end
		local light: PointLight? = darkness.Light
		if light then
			light.Brightness = 1.1 * k
		end
		return nil
	end, function()
		if darkness.Token == token then
			stopDarkness(1.2)
		end
	end)
end

-- The eclipsed sun: a black disc ringed by a cracked white-cyan corona high above the caster.
local function eclipsedSun(fx: any, duration: number)
	local cf = rootCF(fx)
	if cf == nil then
		return
	end
	local pal = palette(fx.Character)
	local center = cf.Position + Vector3.new(0, 34, 0)
	local VoidOrb = Lib.Prop("VoidOrb")
	local model: Model? = nil
	if VoidOrb then
		local ok, m = pcall(VoidOrb.Build, 6, pal.Void)
		if ok and m then
			model = m
			Lib.PrepModel(m)
			m:PivotTo(LookAlong(center, cameraPos() - center))
			m.Parent = Lib.Folder()
		end
	end
	Lib.Animate(duration, function(a, _dt, e)
		if model and model.Parent then
			local grow = easeOutBack(clamp01(e / 0.6))
			local fade = clamp01((a - 0.9) / 0.1)
			model:PivotTo(
				LookAlong(center - Vector3.new(0, 12 * (1 - grow), 0), cameraPos() - center) * CFrame.Angles(0, 0, e * 0.15)
			)
			setAlpha(model, 1 - fade)
		end
		return nil
	end, function()
		if model then
			model:Destroy()
		end
	end)
end

local function eclipseAura(fx: any, on: boolean)
	local char = fx.Character
	local pal = palette(char)
	fx.State.Eclipsed = on
	fx.EyeGlow(char, "Left", pal.Eye, on or char:GetAttribute("FinalForm") == true)
	local root = fx.Root(char)
	local old: ParticleEmitter? = fx.State.EclipseEmitter
	if old then
		old.Enabled = false
		Lib.Debris(old, 2)
		fx.State.EclipseEmitter = nil
	end
	if on and root then
		local e = Lib.Emitter("Mote", root, {
			Color = pal.Glow,
			Texture = Lib.Textures.Spark,
			Rate = 14 * Lib.ParticleScale(),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180),
			Size = Lib.NS(0, 0.1, 0.5, 0.35, 1, 0),
			LightEmission = 1,
			Shape = Enum.ParticleEmitterShape.Sphere,
		})
		fx.State.EclipseEmitter = e
	end
end

local function endEclipse(fx: any)
	if fx.State.Eclipsed then
		eclipseAura(fx, false)
	end
	if fx.State.Darkened then
		fx.State.Darkened = false
		stopDarkness(1.2)
	end
end

Effects.TotalEclipse = function(fx: any, packet: Map)
	local data = packet.data or {}
	local char = fx.Character
	local pal = palette(char)
	if packet.phase == "Start" then
		-- silence: light drains toward him, the world holds its breath
		if not fx.Predicted then
			eyeFor(fx, 1)
		end
		local cf = rootCF(fx)
		if cf then
			for i = 0, 7 do
				fx.Delay(i * 0.09, function()
					local a = i * 0.9
					local p = cf.Position + Vector3.new(math.cos(a) * 9, 1 + (i % 3), math.sin(a) * 9)
					Lib.Emit("Mote", p, 3, { Color = pal.Glow, Dir = cf.Position - p, Speed = { 8, 12 }, Life = { 0.5, 0.7 } })
				end)
			end
		end
		fx.Screen.Desaturate(0.35, 0.9)
		fx.Sound("BadTime", fx.Root(char), { Pitch = 0.8 })
	elseif packet.phase == "Eclipse" then
		local duration = if type(data.duration) == "number" then data.duration else 8
		local vision = if type(data.vision) == "number" then data.vision else 26
		local cf = rootCF(fx)
		if cf then
			Lib.EmitBurst(cf.Position, 18, pal.Void, 0.5)
			Lib.EmitBurst(cf.Position, 8, WHITE, 0.2)
			Lib.Shockwave(cf.Position - Vector3.new(0, 2.8, 0), vision, pal.Void, 0.7, { Dust = false })
			Lib.Emit("Star", cf.Position, 24, { Color = STARLIGHT, Speed = { 10, 28 } })
			fx.ShakeAt(cf.Position, 0.6, 0.5, 60)
		end
		eclipsedSun(fx, duration)
		eclipseAura(fx, true)
		local team = localTeam()
		if fx.IsLocal then
			fx.Screen.Tint(pal.Void, 0.35, 1.2, 0.4)
			local lp = Players.LocalPlayer
			local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
			if pg then
				local gui = Instance.new("ScreenGui")
				gui.Name = "SV_EclipseSubtitle"
				gui.IgnoreGuiInset = true
				gui.ResetOnSpawn = false
				gui.Parent = pg
				subtitle(gui, Strings.L("eclipse.dark.self"), pal.Glow)
				Lib.Debris(gui, 3.5)
			end
		elseif team ~= "Monster" and team ~= "" then
			fx.State.Darkened = true
			startDarkness(duration, vision)
		end
		-- the light returns early if Eclipse falls (his TotalEclipse status disappears)
		local conn: any = nil
		conn = char:GetAttributeChangedSignal("Status_TotalEclipse"):Connect(function()
			local v = char:GetAttribute("Status_TotalEclipse")
			if type(v) ~= "number" or v <= Lib.Now() then
				if conn then
					conn:Disconnect()
				end
				endEclipse(fx)
			end
		end)
		fx.Delay(duration + 0.5, function()
			if conn then
				conn:Disconnect()
			end
			endEclipse(fx)
		end)
	elseif packet.phase == "End" then
		endEclipse(fx)
		local cf = rootCF(fx)
		if cf then
			Lib.EmitBurst(cf.Position, 10, STARLIGHT, 0.4)
		end
	end
end

Predict.TotalEclipse = function(fx: any, _payload: Map)
	eyeFor(fx, 1)
end

---------------------------------------------------------------------------------------------------
-- Registered hazard visuals

-- Starfall drop: a StarBone comet on a slant, nose first into its (marked) impact point.
HazardVisuals.RegisterVisual("EclipseStar", function(ctx: Map)
	local p: Map = ctx.Params
	local owner = ctx.Packet and ctx.Packet.owner
	local pal = palette(if typeof(owner) == "Instance" then owner else nil)
	local StarBone = Lib.Prop("StarBone")
	local model: Model? = nil
	if StarBone then
		local ok, m = pcall(StarBone.Build, 1, pal.Void)
		if ok and m then
			model = m
			Lib.PrepModel(m)
			m:PivotTo(PARK)
			m.Parent = Lib.Folder()
		end
	end
	local drop: Map? = nil
	local slant = Vector3.new(0.45, 0, 0.2)
	local impacted = false
	local lastEmit = 0
	local v: Map = {}
	function v.Update(_s: any, cf: CFrame, t: number, _dt: number)
		if drop == nil then
			local best, bestD = nil, math.huge
			for _, d in HazardDefs.RainDrops(p) do
				local dd = Vector3.new(d.Position.X - cf.Position.X, 0, d.Position.Z - cf.Position.Z).Magnitude
				if dd < bestD then
					best, bestD = d, dd
				end
			end
			drop = best
			local c = p.center
			if best and typeof(c) == "Vector3" then
				-- every star falls away from the sky rift's centre
				slant = flat(best.Position - c, Vector3.new(1, 0, 0.4)) * 0.45
			end
		end
		local d: Map? = drop
		if d == nil then
			return
		end
		local state, height = HazardVisuals.RainFall(p, d, t)
		local ground: Vector3 = d.Position
		if state == "Fall" then
			local pos = ground + Vector3.new(0, height + 0.6, 0) - slant * height
			local dir = (Vector3.new(0, -1, 0) + slant).Unit
			if model then
				model:PivotTo(LookAlong(pos, dir))
			end
			if t - lastEmit > 0.03 then
				lastEmit = t
				Lib.Emit("Star", pos, 1, { Color = if math.random() < 0.5 then CYAN else STARLIGHT, Speed = { 0.3, 1.5 } })
			end
		else
			if not impacted then
				impacted = true
				Lib.EmitBurst(ground + Vector3.new(0, 1, 0), 5, pal.Void, 0.25)
				Lib.EmitBurst(ground + Vector3.new(0, 0.8, 0), 2.5, WHITE, 0.12)
				Lib.Emit("Star", ground, 6, { Color = CYAN, Dir = Vector3.yAxis, Speed = { 6, 14 } })
			end
			if model then
				-- buried nose-first, the tail flickers out
				local sink = math.max(0, (t - d.ImpactTime) * 2.5)
				local dir = (Vector3.new(0, -1, 0) + slant).Unit
				model:PivotTo(LookAlong(ground + Vector3.new(0, 0.3 - sink, 0), dir))
				setAlpha(model, 1 - clamp01((t - d.ImpactTime) / 0.35))
			end
		end
	end
	function v.Destroy(_s: any)
		if model then
			model:Destroy()
		end
	end
	return v :: any
end)

-- Gravity Well: the black star (facing the camera) + the implosion ring, which is the real hitbox.
HazardVisuals.RegisterVisual("EclipseWell", function(ctx: Map)
	local p: Map = ctx.Params
	local owner = ctx.Packet and ctx.Packet.owner
	local pal = palette(if typeof(owner) == "Instance" then owner else nil)
	local center: Vector3 = if typeof(p.center) == "Vector3" then p.center else Vector3.zero
	local delay = if type(p.delay) == "number" then p.delay else 0.3
	local duration = if type(p.duration) == "number" then p.duration else 2.5
	local implodeTime = if type(p.implodeTime) == "number" then p.implodeTime else 0.15
	local implodeRadius = if type(p.implodeRadius) == "number" then p.implodeRadius else 8
	local at = delay + duration
	local VoidOrb = Lib.Prop("VoidOrb")
	local model: Model? = nil
	if VoidOrb then
		local ok, m = pcall(VoidOrb.Build, 1.6, pal.Void)
		if ok and m then
			model = m
			Lib.PrepModel(m)
			m:PivotTo(CFrame.new(center))
			m.Parent = Lib.Folder()
		end
	end
	local ground = Lib.Ground(center + Vector3.new(0, 1, 0), 20) or (center - Vector3.new(0, 2.4, 0))
	local ring = Lib.GroundCircle(ground, implodeRadius, WHITE, { Rim = 0.3, Fill = 0.86, Height = 0.18 })
	ring:SetFill(0)
	local lastPulse = -1
	local lastStar = 0
	local v: Map = {}
	function v.Update(_s: any, _cf: CFrame, t: number, _dt: number)
		local progress = clamp01((t - delay) / math.max(0.05, duration))
		if model and model.Parent then
			local scale = if t < delay then easeOutBack(clamp01(t / math.max(0.05, delay))) else 1
			if t >= at then
				scale = 1 - clamp01((t - at) / math.max(0.05, implodeTime))
			end
			local cam = cameraPos()
			local cf = LookAlong(center, cam - center) * CFrame.Angles(0, 0, t * 0.8)
			model:PivotTo(cf)
			setAlpha(model, math.max(0, scale))
			if VoidOrb and t - lastPulse > 0.05 then
				lastPulse = t
				VoidOrb.SetPulse(model, progress * progress)
			end
		end
		-- implosion telegraph: rim from the landing, fill reaching the rim as it implodes, blink near the end
		if t < at then
			local blink = progress > 0.7 and math.floor(t * 10) % 2 == 0
			ring:SetFill(progress, 0.55)
			ring:SetTransparency(if blink then 0.6 else 0.12, 0.86)
		else
			ring:SetTransparency(1, 1)
		end
		if t >= delay and t < at and t - lastStar > 0.06 then
			lastStar = t
			local a = math.random() * math.pi * 2
			local r = implodeRadius * (1.2 + math.random() * 0.6)
			local s = ground + Vector3.new(math.cos(a) * r, 0.6 + math.random() * 2.5, math.sin(a) * r)
			Lib.Emit("Star", s, 1, { Color = STARLIGHT, Dir = center - s, Speed = { 8, 12 }, Life = { 0.5, 0.6 } })
		end
	end
	function v.Destroy(_s: any)
		if model then
			model:Destroy()
		end
		ring:Destroy()
	end
	return v :: any
end)

-- Void fire left by his attacks during the eclipse: cold flames with a black heart and rising star sparks.
HazardVisuals.RegisterVisual("EclipseVoidFire", function(ctx: Map)
	local p: Map = ctx.Params
	local owner = ctx.Packet and ctx.Packet.owner
	local pal = palette(if typeof(owner) == "Instance" then owner else nil)
	local center: Vector3 = if typeof(p.center) == "Vector3" then p.center else Vector3.zero
	local radius = if type(p.radius) == "number" then p.radius else 4.5
	local delay = if type(p.delay) == "number" then p.delay else 0.3
	local duration = if type(p.duration) == "number" then p.duration else 3.5
	local host =
		Lib.Part("Block", Vector3.new(radius * 1.5, 0.2, radius * 1.5), CFrame.new(center + Vector3.new(0, 0.2, 0)), VOID, Enum.Material.SmoothPlastic, 1)
	local scale = Lib.ParticleScale()
	local area = radius * radius
	local flames = Lib.Emitter("Ember", host, {
		Color = pal.Void,
		Texture = Lib.Textures.Fire,
		Rate = math.floor(area * 1.6 * scale),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(2, 4.5),
		SpreadAngle = Vector2.new(8, 8),
		Size = Lib.NS(0, 1.1, 0.5, 1.5, 1, 0),
		Transparency = Lib.NS(0, 0.25, 0.7, 0.55, 1, 1),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
	})
	flames.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CYAN),
		ColorSequenceKeypoint.new(0.35, pal.Void),
		ColorSequenceKeypoint.new(1, NAVY),
	})
	local smoke = Lib.Emitter("Smoke", host, {
		Color = VOID,
		Texture = Lib.Textures.DarkSmoke,
		Rate = math.floor(area * 0.5 * scale),
		Lifetime = NumberRange.new(0.9, 1.4),
		Speed = NumberRange.new(1.5, 3),
		Size = Lib.NS(0, 1.2, 1, 2.6),
		Transparency = Lib.NS(0, 0.5, 1, 1),
		LightEmission = 0,
		LightInfluence = 0,
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
	})
	local sparks = Lib.Emitter("Star", host, {
		Color = STARLIGHT,
		Rate = math.floor(area * 0.35 * scale),
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(3, 6),
		Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Top,
	})
	local v: Map = {}
	function v.Update(_s: any, _cf: CFrame, t: number, _dt: number)
		local on = t >= delay and t <= delay + duration
		flames.Enabled = on
		smoke.Enabled = on
		sparks.Enabled = on
	end
	function v.Destroy(_s: any)
		flames.Enabled = false
		smoke.Enabled = false
		sparks.Enabled = false
		-- let the last flames finish, then hand the host back
		task.delay(1.5, function()
			flames:Destroy()
			smoke:Destroy()
			sparks:Destroy()
			Lib.Release(host)
		end)
	end
	return v :: any
end)

---------------------------------------------------------------------------------------------------
-- Passives

-- Hides (enemies) or ghosts (himself) every visible piece of the character while Invisible is set.
local function applyInvisible(fx: any, character: Model, on: boolean)
	local restore: { [Instance]: boolean } = fx.State.InvisibleRestore or {}
	fx.State.InvisibleRestore = restore
	local isSelf = character == localCharacter()
	local mod = if on then (if isSelf then 0.72 else 1) else 0
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = mod
		elseif not isSelf and (d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")) then
			local inst: any = d
			if on then
				if inst.Enabled then
					restore[d] = true
					inst.Enabled = false
				end
			elseif restore[d] then
				inst.Enabled = true
			end
		end
	end
	if not on then
		table.clear(restore)
	end
end

function Kit.OnCharacter(fx: any, character: Model)
	local trove = fx.Trove
	local pal = palette(character)
	local root = fx.Root(character)
	-- the night inside his hoodie leaks out: slow starfield motes
	if root then
		local e = Lib.Emitter("Mote", root, {
			Color = pal.Glow,
			Texture = Lib.Textures.Spark,
			Rate = 4 * Lib.ParticleScale(),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(0.2, 0.8),
			SpreadAngle = Vector2.new(180, 180),
			Size = Lib.NS(0, 0.06, 0.5, 0.2, 1, 0),
			LightEmission = 1,
			Shape = Enum.ParticleEmitterShape.Box,
		})
		trove:Add(e)
	end
	-- FinalForm: the ring eye blazes for the rest of the round
	local function finalForm()
		local on = character:GetAttribute("FinalForm") == true
		fx.EyeGlow(character, "Left", pal.Eye, on or fx.State.Eclipsed == true)
	end
	trove:Connect(character:GetAttributeChangedSignal("FinalForm"), finalForm)
	if character:GetAttribute("FinalForm") == true then
		finalForm()
	end
	-- invisibility (Void Step)
	trove:Connect(character:GetAttributeChangedSignal("Invisible"), function()
		applyInvisible(fx, character, character:GetAttribute("Invisible") == true)
	end)
	if character:GetAttribute("Invisible") == true then
		applyInvisible(fx, character, true)
	end
	-- Void Karma: the ring of darkness at his feet (ult drains inside it), drain feedback for a local human
	local N = numbers("TotalEclipse")
	local aura = N.AuraRadius or 10
	local dark = N.VisionRadius or 26
	local ring = Lib.GroundCircle(Vector3.zero, aura, NAVY, { Rim = 0.3, Fill = 0.9, Height = 0.1 })
	trove:Add(function()
		ring:Destroy()
	end)
	local radius = aura
	local lastMote, lastPopup = 0, -math.huge
	trove:Connect(RunService.PreRender, function(dt: number)
		local feet = feetOf(character)
		local alive = character:GetAttribute("Dead") ~= true
		if feet == nil or not alive then
			ring:SetVisible(false)
			return
		end
		local eclipseEnds = character:GetAttribute("Status_TotalEclipse")
		local eclipsed = type(eclipseEnds) == "number" and eclipseEnds > Lib.Now()
		local want = if eclipsed then dark else aura
		radius += (want - radius) * math.min(1, dt * 4)
		ring:SetVisible(character:GetAttribute("Invisible") ~= true)
		ring:SetCenter(feet)
		ring:SetRadius(radius)
		local t = os.clock()
		ring:SetTransparency(0.55 + 0.12 * math.sin(t * 2), if eclipsed then 0.9 else 0.94)
		local lc = localCharacter()
		if lc and lc ~= character and lc:GetAttribute("Team") == "Humans" then
			local lr = lc:FindFirstChild("HumanoidRootPart")
			local ult = lc:GetAttribute("Ult")
			if
				lr
				and lr:IsA("BasePart")
				and type(ult) == "number"
				and ult > 0
				and (lr.Position - (feet + Vector3.new(0, 2.8, 0))).Magnitude <= radius
			then
				if t - lastMote > 0.14 then
					lastMote = t
					local from = lr.Position + Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5)
					local to = feet + Vector3.new(0, 3, 0)
					Lib.Emit("Mote", from, 1, { Color = Lib.Colors.KR, Dir = to - from, Speed = { 8, 12 } })
				end
				if t - lastPopup > 8 then
					lastPopup = t
					popup(lr.Position + Vector3.new(0, 3.5, 0), "eclipse.drain", Lib.Colors.KR)
				end
			end
		end
	end)
	-- the eclipse aura ends with him
	trove:Add(function()
		endEclipse(fx)
	end)
end

-- Lazy dodge flourish on top of FxController's grey MISS ghost: he blinks through a tiny rift.
function Kit.OnDamageFx(fx: any, packet: Map)
	if not packet.dodged then
		return
	end
	local cf = rootCF(fx)
	if cf then
		local pal = palette(fx.Character)
		local side = (cf * CFrame.new(1.6, 0, 0)).Position
		Lib.EmitRing(side, 2.2, pal.Void, 0.25, { Axis = cf.RightVector })
		Lib.Emit("Star", side, 5, { Color = STARLIGHT, Speed = { 1, 4 } })
	end
end

return Kit
