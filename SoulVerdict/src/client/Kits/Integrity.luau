--!strict
-- Client kit: Integrity (blue SOUL) — "The Dancer" (SPEC §9.1). Visuals for every AbilityFx phase of
-- src/server/Kits/Integrity.luau:
--   BalletKicks  Start {combo}: blue crescents (1 low sweep, 2 high développé, 3 full fouetté circle + stars),
--                predicted locally; Strike {last, hits}: finisher burst
--   GrandJete    Start: plié ring; Leap {from, to, time, radius}: landing circle filling up, ribbon trails on both feet,
--                the jeté silhouette at the apex; Land {center, radius}: blue kick shockwave + stars + shake.
--                Indicator: landing circle + flowing arc (Bravery.LeapIndicator)
--   Pirouette    Spin {duration, radius, ticks}: looping Spin clip, two counter-rotating tutu blade rings, a
--                ForceField column (projectiles slide off), floor ring, a blue sweep on every tick;
--                Tick {index, hits}: hit flash; Deflect {pos}: bone shards + "DEFLECT"
--   Encore       Start: stage spotlight on the dancer for the whole routine; Dash {from, to, time} (x3): blue / pink
--                streaks and afterimages, rising pitch; Bow {pos, radius}: gold + blue burst, petals, "BRAVO!", bow clip
-- OnCharacter: Grace — a blue pirouette flourish under the feet on every double jump (local: MovementController
-- signal; other clients: a mid-air vertical-velocity jump heuristic); faint blue SOUL heart at the Chest while
-- UltActiveUntil is in the future (helper shared with the Patience client kit).
-- OnDamageFx: blue deflect sparks when a hit is negated by Pirouette.
-- Kit.IsDoubleJump(prevVY, vy, jumpPower) -> boolean   PURE: the remote double-jump heuristic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any

local PatienceKit = require(script.Parent:WaitForChild("Patience")) :: any
local BraveryKit = require(script.Parent:WaitForChild("Bravery")) :: any

type Map = { [string]: any }

local Kit = {}
local Effects: { [string]: (any, Map) -> () } = {}
local Predict: { [string]: (any, Map) -> () } = {}
local Indicator: { [string]: (any) -> Map? } = {}
Kit.Effects = Effects
Kit.Predict = Predict
Kit.Indicator = Indicator

local BLUE = Color3.fromRGB(0, 60, 255)
local AZURE = Color3.fromRGB(80, 140, 255)
local PALE = Color3.fromRGB(205, 225, 255)
local PINK = Color3.fromRGB(255, 160, 205)
local GOLD = Color3.fromRGB(255, 214, 92)
local WHITE = Color3.new(1, 1, 1)
local PARK = CFrame.new(0, 25000, 0)
local NEON = Enum.Material.Neon
local UP = Vector3.yAxis
local TAU = math.pi * 2
local CYL_UP = CFrame.Angles(0, 0, math.pi / 2)
local ROUTINE_TIME = 1.75 -- windup + 3 dashes + bow (server timing) for the spotlight

local function numbers(abilityId: string): Map
	local a = Kits.Ability("Integrity", abilityId)
	return if a and a.Numbers then a.Numbers else {}
end

local function rootCF(fx: any): CFrame?
	local r = fx.Root(fx.Character)
	return if r then r.CFrame else nil
end

local workspaceRef: any = nil
local function bulkMove(parts: { BasePart }, cfs: { CFrame })
	if workspaceRef == nil then
		workspaceRef = game:GetService("Workspace")
	end
	workspaceRef:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function Kit.IsDoubleJump(prevVY: number, vy: number, jumpPower: number): boolean
	-- a jump that starts while already moving vertically (in the air) — a ground jump starts from ~0
	return vy > jumpPower * 0.75 and vy - prevVY > 25 and math.abs(prevVY) > 4
end

---------------------------------------------------------------------------------------------------
-- Ballet Kicks (M1)

local function kick(fx: any, combo: number)
	fx.Delay(0.08, function()
		local cf = rootCF(fx)
		if cf == nil then
			return
		end
		local Lib = fx.VFX
		local i = ((combo - 1) % 3) + 1
		if i == 1 then
			Lib.Slash(
				cf * CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.rad(-12)),
				{ Radius = 3.4, From = 85, To = -55, Width = 0.6, Color = BLUE, Core = PALE, Duration = 0.2 }
			)
		elseif i == 2 then
			Lib.Slash(
				cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(62)),
				{ Radius = 3.6, From = -70, To = 70, Width = 0.6, Color = BLUE, Core = PALE, Duration = 0.2 }
			)
		else
			Lib.Slash(cf * CFrame.new(0, -0.4, 0), {
				Radius = 4.4,
				From = -170,
				To = 170,
				Width = 0.9,
				Color = BLUE,
				Core = WHITE,
				Duration = 0.28,
				Segments = 18,
			})
			Lib.EmitRing(cf.Position - Vector3.new(0, 2.6, 0), 3.4, AZURE, 0.3)
			Lib.Emit("Star", cf.Position, 6, { Color = PALE, Speed = { 4, 10 } })
		end
		local foot = fx.Part(fx.Character, "RightFoot")
		if foot then
			Lib.Emit("Star", foot.Position, 2, { Color = PALE })
		end
		fx.Sound("Kick", fx.Root(fx.Character), { Pitch = 1.05 + 0.06 * i })
	end)
end

Effects.BalletKicks = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Start" then
		if not fx.Predicted then
			kick(fx, data.combo or 1)
		end
	elseif packet.phase == "Strike" and data.last and (data.hits or 0) > 0 then
		local cf = rootCF(fx)
		if cf then
			local front = (cf * CFrame.new(0, 0.3, -3.4)).Position
			fx.VFX.EmitBurst(front, 3.4, AZURE, 0.2)
			fx.VFX.EmitRing(front, 2.4, PALE, 0.22, { Axis = cf.LookVector })
			fx.HitStop(fx.Character, 0.06)
		end
	end
end

Predict.BalletKicks = function(fx: any, _payload: Map)
	local idx = 1
	local combat = fx.Combat()
	if combat and type(combat.ComboIndex) == "function" then
		local ok, i = pcall(combat.ComboIndex)
		if ok and type(i) == "number" and i > 0 then
			idx = i
		end
	end
	kick(fx, idx)
end

---------------------------------------------------------------------------------------------------
-- Grand Jete (Q)

local function plie(fx: any)
	local r = fx.Root(fx.Character)
	if r then
		local feet = r.Position - Vector3.new(0, 2.7, 0)
		fx.VFX.EmitRing(feet + UP * 0.2, 2.2, AZURE, 0.25)
		fx.VFX.Emit("Star", feet + UP * 0.4, 4, { Color = PALE })
	end
end

-- ribbon-like trails on both feet for `duration` s (client-side attachments on the character's feet)
local function footTrails(fx: any, character: Model, duration: number)
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = fx.Part(character, name)
		if foot and typeof(foot) == "Instance" and foot:IsA("BasePart") then
			local a0 = Instance.new("Attachment")
			a0.Name = "SV_JeteTrail0"
			a0.Position = Vector3.new(0, 0.25, 0)
			a0.Parent = foot
			local a1 = Instance.new("Attachment")
			a1.Name = "SV_JeteTrail1"
			a1.Position = Vector3.new(0, -0.25, 0)
			a1.Parent = foot
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(AZURE, PINK)
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			trail.Lifetime = 0.35
			trail.LightEmission = 1
			trail.LightInfluence = 0
			trail.FaceCamera = true
			trail.Parent = foot
			fx.Debris(trail, duration)
			fx.Debris(a0, duration + 0.4)
			fx.Debris(a1, duration + 0.4)
		end
	end
end

Effects.GrandJete = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Start" then
		if not fx.Predicted then
			plie(fx)
		end
	elseif packet.phase == "Leap" and typeof(data.to) == "Vector3" then
		local time = if type(data.time) == "number" then data.time else 0.6
		local radius = if type(data.radius) == "number" then data.radius else 7
		local circle = Lib.GroundCircle(data.to, radius, AZURE, { Rim = 0.25, Fill = 0.85, Height = 0.18 })
		circle:SetFill(0)
		Lib.Animate(time, function(a)
			circle:SetFill(a)
			return nil
		end, function()
			circle:Destroy()
		end)
		if char then
			footTrails(fx, char, time + 0.25)
			fx.Delay(time * 0.45, function()
				if char.Parent then
					Lib.Afterimage(char, AZURE, 0.5, { Transparency = 0.45, MaxParts = 22 })
				end
			end)
		end
		if typeof(data.from) == "Vector3" then
			Lib.EmitRing(data.from - Vector3.new(0, 2.6, 0), 2.2, PALE, 0.3)
			fx.Sound("Whoosh", data.from, { Pitch = 1.2 })
		end
	elseif packet.phase == "Land" and typeof(data.center) == "Vector3" then
		local c: Vector3 = data.center
		local radius = if type(data.radius) == "number" then data.radius else 7
		Lib.Shockwave(c, radius, AZURE, 0.45, { Dust = true })
		Lib.Ring(CFrame.new(c + UP * 0.3), radius, BLUE, 0.4, 0.25)
		Lib.EmitBurst(c + UP, 4, AZURE, 0.25)
		Lib.Emit("Star", c + UP, 14, { Color = PALE, Speed = { 6, 16 } })
		fx.Sound("Kick", c, { Pitch = 0.85 })
		fx.Sound("SlamLand", c, { Pitch = 1.3, Volume = 0.6 })
		fx.ShakeAt(c, 0.3, 0.25, 30)
	end
end

Predict.GrandJete = function(fx: any, _payload: Map)
	plie(fx)
end

Indicator.GrandJete = function(fx: any): Map?
	return BraveryKit.LeapIndicator(fx, AZURE, numbers("GrandJete").Radius or 7, 8)
end

---------------------------------------------------------------------------------------------------
-- Pirouette (E)

local function spin(fx: any, duration: number, radius: number, ticks: number)
	local char = fx.Character
	local Lib = fx.VFX
	local r0 = fx.Root(char)
	if char == nil or r0 == nil then
		return
	end
	local track = fx.Anim.Play(char, "Spin", { Loop = true, Speed = 1.7, FadeIn = 0.05 })
	fx.Delay(duration, function()
		track.Stop(0.15)
	end)
	local BLADES = 8
	local parts: { BasePart } = {}
	for i = 1, BLADES do
		table.insert(parts, Lib.Part("Block", Vector3.new(0.14, 0.5, 1.3), PARK, if i % 2 == 0 then AZURE else BLUE, NEON, 0.15))
	end
	local shell = Lib.Part("Cylinder", Vector3.new(4.8, 5.4, 5.4), PARK, AZURE, Enum.Material.ForceField, 0)
	table.insert(parts, shell)
	local floor = Lib.GroundCircle(r0.Position - Vector3.new(0, 2.8, 0), radius, AZURE, { Rim = 0.16, Fill = 0.9, Height = 0.14 })
	local cfs: { CFrame } = table.create(#parts)
	local interval = duration / math.max(1, ticks)
	local nextTick = 1
	fx.Sound("Whoosh", r0, { Pitch = 1.3 })
	Lib.Animate(duration, function(_a, _dt, elapsed)
		local r = fx.Root(char)
		if r == nil or char.Parent == nil then
			return true
		end
		local pos = r.Position
		local turn = elapsed * 14
		for i = 1, BLADES do
			local layer = if i <= BLADES / 2 then 1 else -1
			local ang = turn * layer + (i / (BLADES / 2)) * TAU
			cfs[i] = CFrame.new(pos + Vector3.new(0, if layer == 1 then -0.4 else -1.3, 0))
				* CFrame.Angles(0, ang, 0)
				* CFrame.new(0, 0, -2.3)
				* CFrame.Angles(0, 0, math.rad(20 * layer))
		end
		cfs[BLADES + 1] = CFrame.new(pos + Vector3.new(0, -0.3, 0)) * CYL_UP
		bulkMove(parts, cfs)
		local fade = math.clamp((elapsed - (duration - 0.15)) / 0.15, 0, 1)
		for i = 1, BLADES do
			parts[i].Transparency = 0.15 + 0.85 * fade
		end
		shell.Transparency = fade
		floor:SetCenter(pos - Vector3.new(0, 2.8, 0))
		floor:SetTransparency(0.25 + 0.75 * fade, 0.9 + 0.1 * fade)
		-- visual ticks, timed like the server's (tick k at (k - 0.5) x interval)
		while nextTick <= ticks and elapsed >= (nextTick - 0.5) * interval do
			Lib.Slash(CFrame.new(pos - Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, -turn, 0), {
				Radius = radius * 0.8,
				From = -175,
				To = 175,
				Width = 0.45,
				Color = AZURE,
				Core = PALE,
				Duration = 0.16,
				Segments = 16,
				Sparks = false,
			})
			fx.Sound("Whoosh", r, { Pitch = 1.4 + 0.08 * nextTick, Volume = 0.5 })
			nextTick += 1
		end
		return nil
	end, function()
		for _, p in parts do
			Lib.Release(p)
		end
		floor:Destroy()
	end)
end

local function deflectBurst(fx: any, pos: Vector3, label: boolean)
	local Lib = fx.VFX
	Lib.Sparks(pos, nil, PALE, 10, 26)
	Lib.EmitBurst(pos, 2.4, AZURE, 0.18)
	if label then
		Lib.Shatter(CFrame.new(pos), 0.5, WHITE, 6, { Speed = 18 })
		Lib.Text(pos + UP * 1.5, Strings.L("fx.integrity.deflect"), AZURE, { Kind = "Alert", Scale = 0.75 })
	end
	fx.Sound("Parry", pos, { Pitch = 1.3, Volume = 0.6 })
end

Effects.Pirouette = function(fx: any, packet: Map)
	local data = packet.data or {}
	if packet.phase == "Spin" then
		spin(
			fx,
			if type(data.duration) == "number" then data.duration else 1.2,
			if type(data.radius) == "number" then data.radius else 6,
			if type(data.ticks) == "number" then data.ticks else 4
		)
	elseif packet.phase == "Tick" and (data.hits or 0) > 0 then
		local r = fx.Root(fx.Character)
		if r then
			fx.VFX.EmitRing(r.Position - Vector3.new(0, 1, 0), 4.5, PALE, 0.15, { Start = 0.6 })
		end
	elseif packet.phase == "Deflect" and typeof(data.pos) == "Vector3" then
		deflectBurst(fx, data.pos, true)
	end
end

function Kit.OnDamageFx(fx: any, packet: Map)
	if packet.negated == "Pirouette" and typeof(packet.pos) == "Vector3" then
		deflectBurst(fx, packet.pos, false)
	end
end

---------------------------------------------------------------------------------------------------
-- Encore (R, ultimate)

local function spotlight(fx: any, duration: number)
	local char = fx.Character
	local Lib = fx.VFX
	local r0 = fx.Root(char)
	if r0 == nil then
		return
	end
	local beam = Lib.Part("Cylinder", Vector3.new(36, 6.5, 6.5), PARK, PALE, NEON, 1)
	local disc = Lib.GroundCircle(r0.Position - Vector3.new(0, 2.8, 0), 3.4, PALE, { Rim = 0.25, Fill = 0.55, Height = 0.12, Shadow = false })
	local light = Lib.Light(beam, PALE, 2, 16)
	fx.Sound("Ding", r0, { Pitch = 1.5 })
	Lib.Animate(duration, function(a, _dt, elapsed)
		local r = fx.Root(char)
		if r == nil then
			return true
		end
		local feet = r.Position - Vector3.new(0, 2.8, 0)
		beam.CFrame = CFrame.new(feet + Vector3.new(0, 18, 0)) * CYL_UP
		disc:SetCenter(feet)
		local appear = math.min(1, elapsed / 0.2)
		local fade = math.clamp((a - 0.8) / 0.2, 0, 1)
		local k = appear * (1 - fade)
		beam.Transparency = 1 - 0.12 * k
		disc:SetTransparency(1 - 0.85 * k, 1 - 0.45 * k)
		if light then
			light.Brightness = 2 * k
		end
		return nil
	end, function()
		if light then
			light:Destroy()
		end
		Lib.Release(beam)
		disc:Destroy()
	end)
end

Effects.Encore = function(fx: any, packet: Map)
	local data = packet.data or {}
	local Lib = fx.VFX
	local char = fx.Character
	if packet.phase == "Start" then
		fx.State.EncoreIndex = 0
		if not fx.Predicted then
			spotlight(fx, ROUTINE_TIME)
		end
	elseif packet.phase == "Dash" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
		local idx = (fx.State.EncoreIndex or 0) + 1
		fx.State.EncoreIndex = idx
		local from: Vector3, to: Vector3 = data.from, data.to
		local time = if type(data.time) == "number" then data.time else 0.2
		local color = if idx % 2 == 0 then PINK else AZURE
		Lib.Beam(from + UP * 0.4, to + UP * 0.4, 0.55, BLUE, time + 0.3)
		Lib.Line(from + UP * 0.4, to + UP * 0.4, PALE, 0.12, time + 0.2)
		for k = 1, 2 do
			fx.Delay(time * k / 2.5, function()
				if char and char.Parent then
					Lib.Afterimage(char, color, 0.35, { Transparency = 0.4 + 0.1 * k, MaxParts = 18 })
				end
			end)
		end
		Lib.Emit("Star", from:Lerp(to, 0.5) + UP * 0.5, 6, { Color = PALE, Speed = { 2, 8 } })
		fx.Sound("Dash", from, { Pitch = 1 + 0.12 * idx })
		if fx.IsLocal then
			fx.Kick(5, time)
		end
	elseif packet.phase == "Bow" and typeof(data.pos) == "Vector3" then
		local pos: Vector3 = data.pos
		local radius = if type(data.radius) == "number" then data.radius else 9
		local feet = pos - Vector3.new(0, 2.8, 0)
		Lib.Shockwave(feet, radius, AZURE, 0.5, { Dust = false })
		Lib.Ring(CFrame.new(feet + UP * 0.3), radius, GOLD, 0.45, 0.22)
		Lib.Flash(pos, PALE, 7, 0.3)
		Lib.Emit("Star", pos + UP, 28, { Color = GOLD, Speed = { 8, 20 } })
		Lib.Emit("Mote", pos + UP * 4, 24, { Color = PINK, Speed = { 2, 7 } })
		Lib.Text(pos + UP * 3.5, Strings.L("fx.integrity.bravo"), GOLD, { Kind = "Alert", Scale = 1.3 })
		fx.Sound("Surge", pos, { Pitch = 1.2, Volume = 0.8 })
		fx.Sound("Ding", pos, { Pitch = 1.8 })
		if char then
			fx.Anim.Play(char, "Taunt", { FadeIn = 0.08, Speed = 1.6 })
		end
		fx.ShakeAt(pos, 0.35, 0.3, 30)
		if fx.IsLocal then
			fx.Screen.Pulse("Ult")
		end
		fx.State.EncoreIndex = 0
	end
end

Predict.Encore = function(fx: any, _payload: Map)
	spotlight(fx, ROUTINE_TIME)
end

---------------------------------------------------------------------------------------------------
-- Passive visuals: Grace (double jump) + ult heart

local function graceFlourish(fx: any, character: Model)
	local Lib = fx.VFX
	local r = fx.Root(character)
	if r == nil then
		return
	end
	local feet = r.Position - Vector3.new(0, 2.6, 0)
	Lib.EmitRing(feet, 2.8, AZURE, 0.32, { Start = 0.2 })
	Lib.Slash(CFrame.new(feet + UP * 0.6) * CFrame.Angles(0, (os.clock() * 3) % TAU, 0), {
		Radius = 1.7,
		From = -160,
		To = 160,
		Width = 0.32,
		Color = AZURE,
		Core = PALE,
		Duration = 0.24,
		Segments = 14,
		Sparks = false,
	})
	Lib.Emit("Star", feet + UP * 0.5, 5, { Color = PALE, Speed = { 2, 6 } })
	Lib.Afterimage(character, AZURE, 0.25, { Transparency = 0.6, MaxParts = 14 })
end
Kit.GraceFlourish = graceFlourish

function Kit.OnCharacter(fx: any, character: Model)
	-- local player: MovementController reports its own double jumps
	local movement: any = nil
	local controllers = script.Parent.Parent:FindFirstChild("Controllers")
	local module = controllers and controllers:FindFirstChild("MovementController")
	if module and module:IsA("ModuleScript") then
		local ok, m = pcall(require, module)
		movement = if ok then m else nil
	end
	if movement and movement.DoubleJumped then
		fx.Trove:Connect(movement.DoubleJumped, function(model: Model)
			if model == character then
				graceFlourish(fx, character)
			end
		end)
	end
	-- everyone else: a mid-air jump in vertical velocity
	local kit = Kits.Get("Integrity")
	local jumpPower = if kit and type(kit.Stats.JumpPower) == "number" then kit.Stats.JumpPower else 54
	local prevVY = 0
	local lastFlourish = 0
	fx.Trove:Connect(RunService.Heartbeat, function()
		if character == fx.LocalCharacter() or character.Parent == nil then
			return
		end
		local r = fx.Root(character)
		if r == nil then
			return
		end
		local vy = r.AssemblyLinearVelocity.Y
		if Kit.IsDoubleJump(prevVY, vy, jumpPower) and os.clock() - lastFlourish > 0.3 then
			lastFlourish = os.clock()
			graceFlourish(fx, character)
		end
		prevVY = vy
	end)
	local function ult()
		PatienceKit.UltHeart(fx, character, BLUE)
	end
	fx.Trove:Connect(character:GetAttributeChangedSignal("UltActiveUntil"), ult)
	ult()
end

return Kit
