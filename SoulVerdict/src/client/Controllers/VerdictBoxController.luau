--!strict
-- VerdictBoxController (client, SPEC §11 / §20, Priority 40): the Verdict Box on every client.
--   Net "BoxStart" {boxId, victim, monster, seed, patternSet, duration, t0, damagePerHit, krPerHit, box?, bot?}
--     -> the timeline is rebuilt locally (VerdictBox/Patterns, deterministic from seed + set + duration).
--   VICTIM (the local character): pushes InputController context "Box" (combat suppressed; SoundController switches
--     to the "VerdictBox" music), opens a full-screen overlay (ScreenGui "VerdictBox", DisplayOrder 25) drawn by
--     UI/VerdictBoxView ("Overlay"): fade to black, the typed opening line, the battle box, HP / KR line, hints.
--     The SOUL is simulated by VerdictBox/Sim on its fixed tick, kept in step with the server clock (t = now - t0):
--     input = WASD / arrows / left stick / D-pad (Shift, X or gamepad B = slow), jump = Space / W / Up / gamepad A
--     (blue soul); touch: drag anywhere on the left half to steer (relative virtual stick), JUMP button at the right.
--     New hits -> Net "BoxReport"(boxId, hits, false) immediately (+ red flash, shake, "-5" / "+3 KR" numbers);
--     soul position -> Net "BoxSoul"(boxId, x, y) at 15 Hz; at the end BoxReport(boxId, 0, true).
--   WATCHERS: a SurfaceGui (Face from the Screen part's SurfaceFace attribute, PixelsPerStud) on the 3D box's
--     "Screen" part draws the same timeline ("Mirror" view) with the relayed soul (Net "BoxSoul" (boxId, x, y, hits),
--     rendered 0.12 s in the past and interpolated; Sim.AutoSoul when no relay arrives, e.g. bot victims); the box is
--     turned (locally, yaw only) toward the camera so everyone can read it; ~30 Hz, paused beyond 260 studs.
--   Net "BoxEnd" (boxId, {hits, survived, reason}) -> verdict banner ("INNOCENT" / "GUILTY" / "DISMISSED"), then the
--     overlay fades back (context popped). A box whose BoxEnd never arrives closes itself 2 s after its duration.
--
-- API
--   VerdictBoxController.IsInBox() -> boolean          the local player is inside a Verdict Box right now
--   VerdictBoxController.ActiveBoxes() -> {number}
--   VerdictBoxController.Changed: Signal(inBox: boolean)
--   VerdictBoxController.Started: Signal(boxId, isVictim) ; Ended: Signal(boxId, result)
-- Pure helpers (Lune-tested): Interpolate(samples, t) -> (x?, y?), TouchVector(origin, pos, radius) -> (x, y),
--   KeyAxes(isDown: (Enum.KeyCode) -> boolean) -> (x, y, jump, slow), VerdictKind(result) -> string

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Strings = require(Shared:WaitForChild("Strings"))
local Config = require(Shared:WaitForChild("Config")) :: any
local Net = require(Shared:WaitForChild("Net")) :: any
local Kits = require(Shared:WaitForChild("Kits")) :: any
local VerdictBoxFolder = Shared:WaitForChild("VerdictBox")
local Sim = require(VerdictBoxFolder:WaitForChild("Sim")) :: any
local Patterns = require(VerdictBoxFolder:WaitForChild("Patterns")) :: any

local VerdictBoxController = {}
VerdictBoxController.Priority = 40
VerdictBoxController.Changed = Signal.new()
VerdictBoxController.Started = Signal.new()
VerdictBoxController.Ended = Signal.new()

local TUNING = {
	SoulRate = 1 / 15, -- BoxSoul send interval
	RelayDelay = 0.12, -- watchers render the relayed soul this far in the past
	RelayStale = 0.45, -- no relay for this long -> Sim.AutoSoul
	MirrorRate = 1 / 30,
	MirrorMaxDistance = 260,
	FadeIn = 0.25,
	FadeOut = 0.35,
	VerdictHold = 1.1,
	SafetyClose = 2,
	TouchRadius = 56, -- px of drag for full speed
	TouchDeadzone = 0.12,
	StickDeadzone = 0.2,
	DisplayOrder = 25,
}
VerdictBoxController.Tuning = TUNING

---------------------------------------------------------------------------------------------------
-- lazy deps

local controllerCache: { [string]: any } = {}
local function controller(name: string): any?
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local module = script.Parent and script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			controllerCache[name] = result
			return result
		end
	end
	controllerCache[name] = false
	return nil
end

local function call(name: string, fn: string, ...: any): any
	local module = controller(name)
	if module and type(module[fn]) == "function" then
		local ok, result = pcall(module[fn], ...)
		if ok then
			return result
		end
	end
	return nil
end

local viewModule: any = nil
local function View(): any
	if viewModule == nil then
		local ui = script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("UI")
		local mod = ui and ui:FindFirstChild("VerdictBoxView")
		viewModule = if mod then require(mod :: ModuleScript) else false
	end
	return if viewModule then viewModule else nil
end

local function sound(name: string, at: any?, opts: { [string]: any }?)
	call("SoundController", "Play", name, at, opts)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------------------------------
-- pure helpers

-- samples: array of {t, x, y} sorted by t. Linear interpolation (clamped to the ends). nil when empty.
function VerdictBoxController.Interpolate(samples: { { number } }, t: number): (number?, number?)
	local n = #samples
	if n == 0 then
		return nil, nil
	end
	if t <= samples[1][1] then
		return samples[1][2], samples[1][3]
	end
	for i = n, 2, -1 do
		local a = samples[i - 1]
		if t >= a[1] then
			local b = samples[i]
			if t >= b[1] then
				return b[2], b[3]
			end
			local k = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
			return a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
		end
	end
	return samples[n][2], samples[n][3]
end

-- Relative virtual stick: drag vector from the touch origin, full speed at `radius` px, deadzone.
function VerdictBoxController.TouchVector(origin: Vector2, pos: Vector2, radius: number): (number, number)
	local d = pos - origin
	local m = d.Magnitude / math.max(radius, 1)
	if m < TUNING.TouchDeadzone then
		return 0, 0
	end
	local k = math.min(m, 1) / math.max(m, 1e-6) / math.max(radius, 1)
	return d.X * k, d.Y * k
end

-- Keyboard axes from an IsKeyDown-like predicate.
function VerdictBoxController.KeyAxes(isDown: (Enum.KeyCode) -> boolean): (number, number, boolean, boolean)
	local K = Enum.KeyCode
	local x, y = 0, 0
	if isDown(K.A) or isDown(K.Left) then
		x -= 1
	end
	if isDown(K.D) or isDown(K.Right) then
		x += 1
	end
	if isDown(K.W) or isDown(K.Up) then
		y -= 1
	end
	if isDown(K.S) or isDown(K.Down) then
		y += 1
	end
	local jump = isDown(K.Space)
	local slow = isDown(K.LeftShift) or isDown(K.RightShift) or isDown(K.X)
	return x, y, jump, slow
end

function VerdictBoxController.VerdictKind(result: any): string
	if type(result) ~= "table" then
		return "Dismissed"
	end
	if result.reason == "Cancelled" or result.reason == "VictimGone" then
		return "Dismissed"
	end
	return if result.survived == true then "Innocent" else "Guilty"
end

---------------------------------------------------------------------------------------------------
-- state

type Sample = { number }

type Box = {
	id: number,
	packet: { [string]: any },
	timeline: any,
	t0: number,
	duration: number,
	isVictim: boolean,
	view: any,
	gui: Instance?,
	sim: any?,
	eventIndex: number,
	lastSoulSend: number,
	finishedSent: boolean,
	closing: boolean,
	closeAt: number,
	fadeOutStart: number,
	samples: { Sample },
	lastRelay: number,
	relayHits: number,
	shownHits: number,
	blinkUntil: number,
	model: Model?,
	screen: BasePart?,
	lastMirror: number,
	yaw: number?,
	hintUntil: number,
	hintsShown: { [string]: boolean },
	blasterPhase: { [number]: string },
	stabPhase: { [number]: string },
	typed: number,
	trove: { any },
}

local boxes: { [number]: Box } = {}
local victimBox: Box? = nil
local renderConn: RBXScriptConnection? = nil

-- input state (victim)
local stick = Vector2.zero
local touchVec = Vector2.zero
local touchJump = false
local padTouch: InputObject? = nil
local padOrigin = Vector2.zero
local inputConns: { RBXScriptConnection } = {}

local function localPlayer(): Player?
	return Players.LocalPlayer
end

local function localCharacter(): Model?
	local m = call("StateController", "LocalCharacter")
	if typeof(m) == "Instance" and m:IsA("Model") then
		return m
	end
	local lp = localPlayer()
	return if lp then lp.Character else nil
end

local function isLocalVictim(victim: any): boolean
	if typeof(victim) ~= "Instance" then
		return false
	end
	if victim == localCharacter() then
		return true
	end
	local lp = localPlayer()
	return lp ~= nil and victim:GetAttribute("OwnerUserId") == lp.UserId and lp.UserId ~= 0
end

function VerdictBoxController.IsInBox(): boolean
	return victimBox ~= nil and not (victimBox :: Box).closing
end

function VerdictBoxController.ActiveBoxes(): { number }
	local out = {}
	for id in boxes do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

local function displayName(model: Model?): string
	if model == nil then
		return "?"
	end
	local uid = model:GetAttribute("OwnerUserId")
	if type(uid) == "number" and uid ~= 0 then
		local p = Players:GetPlayerByUserId(uid)
		if p then
			return p.DisplayName
		end
	end
	return model.Name
end

local function monsterTitle(monster: any): string
	if typeof(monster) == "Instance" then
		local kit = Kits.Get(monster:GetAttribute("KitId"))
		if kit then
			local title = kit.Title or kit.Name
			if title then
				return string.upper(Strings.Pick(title))
			end
		end
	end
	return Strings.L("vb.title")
end

---------------------------------------------------------------------------------------------------
-- input (victim)

local function readInput(box: Box): { [string]: any }
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local x, y, jump, slow = 0, 0, false, false
	if not typing then
		x, y, jump, slow = VerdictBoxController.KeyAxes(function(key: Enum.KeyCode): boolean
			return UserInputService:IsKeyDown(key)
		end)
	end
	local pad = Enum.UserInputType.Gamepad1
	if UserInputService:GetGamepadConnected(pad) then
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.DPadLeft) then
			x -= 1
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.DPadRight) then
			x += 1
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.DPadUp) then
			y -= 1
		end
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.DPadDown) then
			y += 1
		end
		jump = jump or UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonA)
		slow = slow or UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonB)
		x += stick.X
		y += stick.Y
	end
	x += touchVec.X
	y += touchVec.Y
	jump = jump or touchJump
	local _ = box
	return { x = math.clamp(x, -1, 1), y = math.clamp(y, -1, 1), jump = jump, slow = slow }
end

local function disconnectInput()
	for _, c in inputConns do
		c:Disconnect()
	end
	table.clear(inputConns)
	stick = Vector2.zero
	touchVec = Vector2.zero
	touchJump = false
	padTouch = nil
end

local function connectInput(gui: ScreenGui)
	disconnectInput()
	table.insert(
		inputConns,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local p = Vector2.new(input.Position.X, -input.Position.Y)
				stick = if p.Magnitude < TUNING.StickDeadzone then Vector2.zero else p
			elseif padTouch ~= nil and input == padTouch then
				local tx, ty = VerdictBoxController.TouchVector(
					padOrigin,
					Vector2.new(input.Position.X, input.Position.Y),
					TUNING.TouchRadius
				)
				touchVec = Vector2.new(tx, ty)
			end
		end)
	)
	table.insert(
		inputConns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if padTouch ~= nil and input == padTouch then
				padTouch = nil
				touchVec = Vector2.zero
			end
		end)
	)
	-- touch controls (always built; shown for touch devices)
	local device = call("InputController", "Device")
	local touch = device == "Touch" or UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local padArea = Instance.new("TextButton")
	padArea.Name = "SteerPad"
	padArea.Text = ""
	padArea.AutoButtonColor = false
	padArea.BackgroundTransparency = 1
	padArea.Size = UDim2.fromScale(0.55, 1)
	padArea.ZIndex = 40
	padArea.Visible = touch
	local ring = Instance.new("Frame")
	ring.Name = "Stick"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(TUNING.TouchRadius * 2, TUNING.TouchRadius * 2)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = 41
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.new(1, 1, 1)
	ringStroke.Transparency = 0.6
	ringStroke.Thickness = 2
	ringStroke.Parent = ring
	ring.Parent = padArea
	padArea.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and padTouch == nil then
			padTouch = input
			padOrigin = Vector2.new(input.Position.X, input.Position.Y)
			ring.Position = UDim2.fromOffset(padOrigin.X - padArea.AbsolutePosition.X, padOrigin.Y - padArea.AbsolutePosition.Y)
			ring.Visible = true
		end
	end)
	table.insert(
		inputConns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch and padTouch == nil then
				ring.Visible = false
			end
		end)
	)
	padArea.Parent = gui

	local jumpButton = Instance.new("TextButton")
	jumpButton.Name = "Jump"
	jumpButton.AnchorPoint = Vector2.new(1, 1)
	jumpButton.Position = UDim2.new(1, -28, 1, -34)
	jumpButton.Size = UDim2.fromOffset(118, 118)
	jumpButton.BackgroundColor3 = Color3.new(0, 0, 0)
	jumpButton.BackgroundTransparency = 0.35
	jumpButton.AutoButtonColor = false
	jumpButton.Text = Strings.L("vb.jump")
	jumpButton.TextColor3 = Color3.new(1, 1, 1)
	jumpButton.FontFace = Font.new("rbxasset://fonts/families/PressStart2P.json")
	jumpButton.TextSize = 16
	jumpButton.ZIndex = 42
	jumpButton.Visible = touch
	local jc = Instance.new("UICorner")
	jc.CornerRadius = UDim.new(0.5, 0)
	jc.Parent = jumpButton
	local js = Instance.new("UIStroke")
	js.Color = Sim.Palette.SoulBlue
	js.Thickness = 3
	js.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	js.Parent = jumpButton
	jumpButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touchJump = true
		end
	end)
	jumpButton.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touchJump = false
		end
	end)
	jumpButton.Parent = gui
end

---------------------------------------------------------------------------------------------------
-- open / close

local function deviceKey(base: string): string
	local device = call("InputController", "Device")
	if device == "Touch" then
		return base .. ".touch"
	elseif device == "Gamepad" and base == "vb.hint.jump" then
		return base .. ".pad"
	end
	return base
end

local function destroyBox(box: Box)
	boxes[box.id] = nil
	if box.view then
		pcall(function()
			box.view:Destroy()
		end)
	end
	if box.gui then
		box.gui:Destroy()
	end
	if box.isVictim and victimBox == box then
		victimBox = nil
		disconnectInput()
		call("InputController", "PopContext", "Box")
		VerdictBoxController.Changed:Fire(false)
	end
	if next(boxes) == nil and renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function beginClose(box: Box, result: any?)
	if box.closing then
		return
	end
	box.closing = true
	local t = now()
	local kind = VerdictBoxController.VerdictKind(result)
	local hits = if type(result) == "table" and type(result.hits) == "number" then result.hits else box.shownHits
	if box.view then
		local sub = if box.isVictim then Strings.L("vb.verdict." .. kind .. ".sub", hits) else nil
		box.view:SetVerdict(kind, sub)
	end
	if box.isVictim then
		sound(if kind == "Innocent" then "SaveLit" else "BoxClose", nil, { Force2D = true })
		box.fadeOutStart = t + TUNING.VerdictHold
		box.closeAt = box.fadeOutStart + TUNING.FadeOut
	else
		box.fadeOutStart = t + 0.9
		box.closeAt = t + 0.9
	end
	VerdictBoxController.Ended:Fire(box.id, result)
end

local function soulView(box: Box, t: number, x: number, y: number, blink: boolean): { [string]: any }
	local m = Sim.ModeAt(box.timeline, t)
	return { x = x, y = y, mode = m.mode, gravity = m.gravity, blink = blink, visible = true }
end

local function hudView(box: Box): { [string]: any }?
	local character = box.packet.victim
	if typeof(character) ~= "Instance" then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local lp = localPlayer()
	local level = if lp then lp:GetAttribute("Level") else nil
	local kr = character:GetAttribute("KR")
	return {
		name = if lp then lp.DisplayName else character.Name,
		lv = if type(level) == "number" then level else 1,
		hp = if hum then hum.Health else 0,
		maxHp = if hum then hum.MaxHealth else 100,
		kr = if type(kr) == "number" then kr else 0,
	}
end

-- victim: sounds / hints that follow the timeline
local function timelineCues(box: Box, t: number)
	local tl = box.timeline
	-- typewriter blips
	if t < tl.introEnd then
		local total = utf8.len(box.view.lineText or "") or 0
		local typed = Sim.IntroChars(tl, t, total)
		if typed > box.typed then
			box.typed = typed
			if typed % 2 == 0 then
				sound("SansTextBlip", nil, { Force2D = true })
			end
		end
	end
	local pose = box.view.pose
	for _, b in tl.bullets do
		if t >= b.t0 and t <= b.t1 then
			if b.kind == "Blaster" then
				local p = Sim.Pose(b, t, pose)
				if p and box.blasterPhase[b.id] ~= p.phase then
					box.blasterPhase[b.id] = p.phase
					if p.phase == "Charge" then
						sound("BlasterCharge", nil, { Force2D = true, Volume = 0.6 })
					elseif p.phase == "Fire" then
						sound("BlasterFire", nil, { Force2D = true, Volume = 0.8 })
					end
				end
			elseif b.kind == "Stab" then
				local p = Sim.Pose(b, t, pose)
				if p and box.stabPhase[b.id] ~= p.phase then
					box.stabPhase[b.id] = p.phase
					if p.phase == "Rise" then
						sound("BoneRise", nil, { Force2D = true })
					end
				end
			end
			if (b.color == "Blue" or b.color == "Orange") and not box.hintsShown[b.color] and b.t0 + 0.15 <= t then
				box.hintsShown[b.color] = true
				box.view:SetHint(Strings.L(if b.color == "Blue" then "vb.hint.blue" else "vb.hint.orange"))
				box.hintUntil = t + 1.4
			end
		end
	end
	local m = Sim.ModeAt(tl, t)
	if m.mode == "Blue" and not box.hintsShown.Jump then
		box.hintsShown.Jump = true
		box.view:SetHint(Strings.L(deviceKey("vb.hint.jump")))
		box.hintUntil = t + 1.8
	elseif m.mode == "Red" and not box.hintsShown.Move then
		box.hintsShown.Move = true
		box.view:SetHint(Strings.L(deviceKey("vb.hint.move")))
		box.hintUntil = t + 1.5
	end
	if box.hintUntil > 0 and t > box.hintUntil then
		box.hintUntil = 0
		box.view:SetHint(nil)
	end
end

local function stepVictim(box: Box, wall: number)
	local t = wall - box.t0
	local view = box.view
	local sim = box.sim
	if not box.closing and sim then
		local cfg = Config.VerdictBox
		local gained = Sim.AdvanceTo(sim, math.min(t, box.duration), readInput(box))
		-- events: hits, slams, mode changes
		local events = sim.events
		for i = box.eventIndex + 1, #events do
			local e = events[i]
			if e.kind == "Hit" then
				view:Hit(e.t, box.packet.damagePerHit or cfg.DamagePerHit, box.packet.krPerHit or cfg.KRPerHit)
				sound("Hurt", nil, { Force2D = true })
			elseif e.kind == "Slam" then
				view:Pulse(e.t, Sim.Palette.Blue)
				sound("Slam", nil, { Force2D = true, Volume = 0.6 })
			elseif e.kind == "Mode" and e.color == "Blue" then
				view:Pulse(e.t, Sim.Palette.SoulBlue)
				sound("SoulGrab", nil, { Force2D = true })
			elseif e.kind == "Jump" then
				sound("Jump", nil, { Force2D = true, Volume = 0.4 })
			end
		end
		box.eventIndex = #events
		if gained > 0 then
			Net.Client.Fire("BoxReport", box.id, gained, false)
		end
		if wall - box.lastSoulSend >= TUNING.SoulRate and sim.soul.active then
			box.lastSoulSend = wall
			Net.Client.Fire("BoxSoul", box.id, math.round(sim.soul.x * 10) / 10, math.round(sim.soul.y * 10) / 10)
		end
		timelineCues(box, t)
		if t >= box.duration and not box.finishedSent then
			box.finishedSent = true
			Net.Client.Fire("BoxReport", box.id, 0, true)
		end
	end
	-- fade in / out
	local fade = 1 - math.clamp((wall - box.t0) / TUNING.FadeIn, 0, 1)
	if box.closing then
		fade = math.max(fade, math.clamp((wall - box.fadeOutStart) / TUNING.FadeOut, 0, 1))
	end
	view:SetFade(fade)
	local gui = box.gui
	if gui and gui:IsA("ScreenGui") then
		view:SetSize(gui.AbsoluteSize)
	end
	local soul = if sim then sim.soul else nil
	local sv = if soul and soul.active
		then soulView(box, t, soul.x, soul.y, sim.t < soul.iframesUntil)
		else nil
	view:Render(math.min(t, box.duration + 0.5), sv, hudView(box))
end

local function stepWatcher(box: Box, wall: number, camera: Camera?)
	local screen = box.screen
	if screen == nil or screen.Parent == nil then
		if not box.closing then
			beginClose(box, nil)
		end
		return
	end
	if camera and (camera.CFrame.Position - screen.Position).Magnitude > TUNING.MirrorMaxDistance then
		return
	end
	if wall - box.lastMirror < TUNING.MirrorRate then
		return
	end
	box.lastMirror = wall
	local t = wall - box.t0
	-- relayed soul (rendered slightly in the past), AutoSoul fallback
	local rt = t - TUNING.RelayDelay
	local x, y
	if wall - box.lastRelay <= TUNING.RelayStale and #box.samples > 0 then
		x, y = VerdictBoxController.Interpolate(box.samples, rt)
	end
	if x == nil or y == nil then
		x, y = Sim.AutoSoul(box.timeline, t)
	end
	local cx, cy = Sim.Clamp(box.timeline, t, x :: number, y :: number)
	if box.relayHits > box.shownHits then
		box.shownHits = box.relayHits
		box.blinkUntil = t + (Config.VerdictBox.MinHitInterval or 0.45)
		box.view:Hit(t, box.packet.damagePerHit, box.packet.krPerHit)
	end
	box.view:Render(math.min(t, box.duration + 0.5), soulView(box, t, cx, cy, t < box.blinkUntil))
	-- face the camera (local yaw only; the server never moves the box)
	local model = box.model
	if camera and model and model.Parent then
		local pivot = model:GetPivot()
		local to = camera.CFrame.Position - pivot.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		if flat.Magnitude > 0.5 then
			local want = math.atan2(-flat.X, -flat.Z) + math.pi
			local cur = box.yaw or want
			local diff = (want - cur + math.pi) % (2 * math.pi) - math.pi
			cur += diff * 0.25
			box.yaw = cur
			if math.abs(diff) > 0.004 then
				model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, cur, 0))
			end
		end
	end
end

local function onRender()
	local wall = now()
	local camera = workspace.CurrentCamera
	for _, box in boxes do
		if box.closing and wall >= box.closeAt then
			destroyBox(box)
		elseif not box.closing and wall > box.t0 + box.duration + TUNING.SafetyClose then
			beginClose(box, nil)
		else
			local ok, err = pcall(if box.isVictim then stepVictim else stepWatcher, box, wall, camera)
			if not ok then
				warn("[VerdictBoxController] box " .. box.id .. " step failed: " .. tostring(err))
				beginClose(box, nil)
			end
		end
	end
end

local function ensureLoop()
	if renderConn == nil then
		renderConn = RunService.PreRender:Connect(onRender)
	end
end

local function newBox(packet: { [string]: any }, isVictim: boolean): Box
	local duration = if type(packet.duration) == "number" then packet.duration else Config.VerdictBox.Duration
	local timeline = Patterns.Build(packet.patternSet, packet.seed, duration)
	return {
		id = packet.boxId,
		packet = packet,
		timeline = timeline,
		t0 = packet.t0,
		duration = duration,
		isVictim = isVictim,
		view = nil,
		gui = nil,
		sim = nil,
		eventIndex = 0,
		lastSoulSend = 0,
		finishedSent = false,
		closing = false,
		closeAt = math.huge,
		fadeOutStart = math.huge,
		samples = {},
		lastRelay = -math.huge,
		relayHits = 0,
		shownHits = 0,
		blinkUntil = 0,
		model = nil,
		screen = nil,
		lastMirror = 0,
		yaw = nil,
		hintUntil = 0,
		hintsShown = {},
		blasterPhase = {},
		stabPhase = {},
		typed = 0,
		trove = {},
	}
end

local function openOverlay(box: Box)
	local ViewMod = View()
	local lp = localPlayer()
	if ViewMod == nil or lp == nil then
		return
	end
	local playerGui = lp:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VerdictBox"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = TUNING.DisplayOrder
	local view = ViewMod.new(gui, box.timeline, { Mode = "Overlay", Title = monsterTitle(box.packet.monster) })
	view.Root.Active = true -- swallow clicks / touches meant for the world
	box.view = view
	box.gui = gui
	box.sim = Sim.new(box.timeline, { hitInterval = Config.VerdictBox.MinHitInterval })
	connectInput(gui)
	gui.Parent = playerGui
	victimBox = box
	call("InputController", "PushContext", "Box")
	sound("BoxOpen", nil, { Force2D = true })
	VerdictBoxController.Changed:Fire(true)
end

local function findBoxModel(packet: { [string]: any }): Model?
	local m = packet.box
	if typeof(m) == "Instance" and m:IsA("Model") then
		return m
	end
	local folder = workspace:FindFirstChild("VerdictBoxes")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("BoxId") == packet.boxId then
				return child
			end
		end
	end
	return nil
end

local function openMirror(box: Box)
	local ViewMod = View()
	local lp = localPlayer()
	if ViewMod == nil or lp == nil then
		return
	end
	local playerGui = lp:FindFirstChildOfClass("PlayerGui")
	local model = findBoxModel(box.packet)
	if playerGui == nil or model == nil then
		return
	end
	local screen = model:FindFirstChild("Screen", true)
	if screen == nil or not screen:IsA("BasePart") then
		return
	end
	local face = screen:GetAttribute("SurfaceFace")
	local pps = screen:GetAttribute("PixelsPerStud")
	local size = screen:GetAttribute("ScreenSize")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "VerdictBoxMirror"
	gui.Adornee = screen
	gui.Face = if type(face) == "string" and (Enum.NormalId :: any)[face] then (Enum.NormalId :: any)[face] else Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = if type(pps) == "number" then pps else 48
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	local px = if typeof(size) == "Vector2" then (size :: Vector2) * gui.PixelsPerStud else Vector2.new(312, 312)
	local view = ViewMod.new(gui, box.timeline, { Mode = "Mirror", Size = px, Name = displayName(box.packet.victim) })
	box.view = view
	box.gui = gui
	box.model = model
	box.screen = screen
	gui.Parent = playerGui
	sound("BoxOpen", screen)
end

local function onBoxStart(packet: any)
	if type(packet) ~= "table" or type(packet.boxId) ~= "number" or type(packet.t0) ~= "number" then
		return
	end
	if boxes[packet.boxId] then
		return
	end
	local isVictim = isLocalVictim(packet.victim)
	local box = newBox(packet, isVictim)
	boxes[box.id] = box
	local ok, err = pcall(if isVictim then openOverlay else openMirror, box)
	if not ok then
		warn("[VerdictBoxController] open failed: " .. tostring(err))
	end
	if box.view == nil and not isVictim then
		-- the 3D box may replicate a moment later: retry briefly
		task.delay(0.3, function()
			if boxes[box.id] == box and box.view == nil and not box.closing then
				pcall(openMirror, box)
			end
		end)
	end
	if box.view == nil and isVictim then
		boxes[box.id] = nil
		return
	end
	ensureLoop()
	VerdictBoxController.Started:Fire(box.id, isVictim)
end

local function onBoxSoul(boxId: any, x: any, y: any, hits: any)
	if type(boxId) ~= "number" then
		return
	end
	local box = boxes[boxId]
	if box == nil or box.isVictim then
		return
	end
	if type(hits) == "number" and hits > box.relayHits then
		box.relayHits = hits
	end
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then
		return
	end
	local wall = now()
	box.lastRelay = wall
	local samples = box.samples
	table.insert(samples, { wall - box.t0, x, y })
	while #samples > 8 do
		table.remove(samples, 1)
	end
end

local function onBoxEnd(boxId: any, result: any)
	if type(boxId) ~= "number" then
		return
	end
	local box = boxes[boxId]
	if box == nil then
		return
	end
	if type(result) == "table" and type(result.hits) == "number" then
		box.relayHits = math.max(box.relayHits, result.hits)
	end
	beginClose(box, result)
end

function VerdictBoxController.Init() end

function VerdictBoxController.Start()
	Net.Client.On("BoxStart", onBoxStart)
	Net.Client.On("BoxSoul", onBoxSoul)
	Net.Client.On("BoxEnd", onBoxEnd)
end

return VerdictBoxController
