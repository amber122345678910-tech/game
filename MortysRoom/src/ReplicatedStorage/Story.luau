--[[
	THE STORY (12 chapters). Every line is written in Russian and English.
	  1  Good morning   - wake up, take the phone, go downstairs
	  2  Breakfast      - Beth: "put the phone away!" -> choice -> the phone explodes
	  3  Rick's garage  - Rick rebuilt Morty, but Rick is glitching
	  4  Flight         - saucer out of the garage, warp, planet B137, landing
	  5  Planet B137    - Rick tries to ditch Morty, something knocks him down, the curse
	  6  The Titan      - old village, radar, Titan Speakerman 2.0 vs the entity, knock-back, drag
	  7..12 live in StoryCurve: the bunker plan, the Curve Bell, Evil Morty, the hunt,
	        the Alliance, the camera base, home (+ a scene after the credits)
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local Game = script.Parent
local UI = require(Game.UI)
local Lang = require(Game.Lang)
local Audio = require(Game.Audio)
local Graphics = require(Game.Graphics)
local Fx = require(Game.Fx)
local Director = require(Game.Director)
local Dialogue = require(Game.Dialogue)
local Puppet = require(Game.Puppet)
local Scenes = require(Game.Scenes)
local StoryCurve = require(Game.StoryCurve)

local Story = {}
local rgb = Color3.fromRGB
local CANCEL = "__story_cancel__"

local api: any = nil
local R: { [string]: any } = {}
local P: { [string]: any } = {}
local init: { [string]: any } = {}
local runId = 0
local loops: { Instance } = {}

----------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------
local function camera(): Camera
	return workspace.CurrentCamera
end

local function makeCtx(id: number)
	local c = {}
	function c.alive(): boolean
		return id == runId
	end
	function c.check()
		if id ~= runId then
			error(CANCEL, 0)
		end
	end
	function c.wait(t: number)
		task.wait(t)
		c.check()
	end
	function c.say(who: string, line: any, opts: any?)
		c.check()
		Dialogue.say(who, line, opts)
		c.check()
	end
	function c.waitUntil(fn: () -> boolean, timeout: number?): boolean
		local t0 = os.clock()
		while not fn() do
			task.wait(0.05)
			c.check()
			if timeout and os.clock() - t0 > timeout then
				return false
			end
		end
		return true
	end
	function c.interact(id2: string): Instance
		local done: Instance? = nil
		local old = api.handlers[id2]
		api.handlers[id2] = function(model)
			done = model
		end
		local ok = pcall(c.waitUntil, function()
			return done ~= nil
		end)
		api.handlers[id2] = old
		if not ok then
			error(CANCEL, 0)
		end
		return done :: Instance
	end
	return c
end

local function loopSound(key: string, parent: Instance?): Sound?
	local s = Audio.make(key, parent)
	if s then
		s:Play()
		table.insert(loops, s)
	end
	return s
end

local function stopLoop(s: Sound?, fade: number?)
	if s then
		Audio.fadeOut(s, fade or 0.6, true)
		local i = table.find(loops, s)
		if i then
			table.remove(loops, i)
		end
	end
end

local function play3D(key: string, pos: Vector3, pitch: number?)
	local holder = Fx.part({ Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos) })
	local s = Audio.make(key, holder)
	if s then
		s.PlaybackSpeed = pitch or 1
		s:Play()
	end
	task.delay(12, function()
		holder:Destroy()
	end)
end

local function eyeFromHead(headCF: CFrame): CFrame
	local p = (headCF * CFrame.new(0, 0.05, -0.55)).Position
	return CFrame.lookAt(p, p + headCF.LookVector, headCF.UpVector)
end

local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

local function setParts(model: Instance, props: { [string]: any })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			for k, val in props do
				(d :: any)[k] = val
			end
		end
	end
end

local function emitters(model: Instance, name: string?, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") and (name == nil or d.Name == name) then
			d.Enabled = on
		end
	end
end

-- rotate a set of parts around a hinge
local function hingeRotate(parts: { [BasePart]: CFrame }, hinge: Vector3, rot: CFrame)
	local H = CFrame.new(hinge)
	local M = H * rot * H:Inverse()
	for part, cf in parts do
		part.CFrame = M * cf
	end
end

local function animate(duration: number, fn: (number) -> (), easeKind: string?)
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		fn(Director.ease(a, easeKind))
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

----------------------------------------------------------------------------
-- Morty's phone in first person (local part in front of the camera)
----------------------------------------------------------------------------
local VM = { part = nil :: BasePart?, mode = "hidden", heat = 0, t = 0, offset = CFrame.new(0, -3, -2) }
do
	local function build()
		local p = Instance.new("Part")
		p.Name = "PhoneViewmodel"
		p.Size = Vector3.new(0.42, 0.82, 0.05)
		p.Color = rgb(24, 24, 28)
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 500
		sg.LightInfluence = 0
		sg.Brightness = 1.4
		sg.ClipsDescendants = true
		sg.Parent = p
		local bg = UI.new("Frame", { Name = "Bg", BackgroundColor3 = rgb(12, 8, 36), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = sg }, { UI.gradient({ rgb(40, 16, 90), rgb(8, 40, 70) }, nil, 90) })
		local _ = bg
		for i = 1, 14 do
			UI.new("Frame", {
				Name = "Star",
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(math.random(), math.random()),
				Size = UDim2.fromOffset(3, 3),
				Parent = sg,
			})
			local _ = i
		end
		UI.label({ Name = "Title", Text = "GALAXY RAID III", Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = rgb(255, 220, 80), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromScale(0, 0.04), Size = UDim2.fromScale(1, 0.08), Parent = sg })
		UI.new("Frame", { Name = "Boss", BackgroundColor3 = rgb(220, 50, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(90, 70), Parent = sg }, { UI.corner(20) })
		UI.new("Frame", { Name = "Ship", BackgroundColor3 = rgb(110, 230, 255), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.78), Size = UDim2.fromOffset(34, 40), Rotation = 45, Parent = sg }, { UI.corner(6) })
		UI.new("Frame", { Name = "Laser", BackgroundColor3 = rgb(255, 255, 160), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(0, 4, 0.36, 0), Parent = sg })
		UI.label({ Name = "Hud", Text = "FPS 12   CPU 71°C", Font = Enum.Font.RobotoMono, TextSize = 18, TextColor3 = rgb(200, 255, 200), Position = UDim2.fromScale(0.04, 0.9), Size = UDim2.fromScale(0.92, 0.06), Parent = sg })
		local warn = UI.new("Frame", { Name = "Warn", BackgroundColor3 = rgb(200, 20, 20), BackgroundTransparency = 0.15, Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.9, 0.2), Parent = sg }, { UI.corner(10) })
		UI.label({ Name = "Text", Text = "", Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = warn })
		VM.part = p
		VM.gui = sg
	end
	function VM.setMode(m: string)
		if not VM.part then
			build()
		end
		VM.mode = m
		if m ~= "hidden" and VM.part then
			(VM.part :: BasePart).Parent = camera()
		end
	end
	function VM.setHeat(h: number)
		VM.heat = h
	end
	function VM.position(): Vector3
		return if VM.part then (VM.part :: BasePart).Position else camera().CFrame.Position
	end
	local targets = {
		hand = CFrame.new(1.0, -0.95, -2.1) * CFrame.Angles(math.rad(-12), math.rad(-22), math.rad(-6)),
		table = CFrame.new(0.12, -0.72, -1.5) * CFrame.Angles(math.rad(-28), math.rad(-4), 0),
		pocket = CFrame.new(0.85, -2.6, -1.4) * CFrame.Angles(math.rad(-60), 0, 0),
		hidden = CFrame.new(0.85, -3.2, -1.4),
	}
	RunService:BindToRenderStep("PhoneViewmodel", Enum.RenderPriority.Camera.Value + 20, function(dt)
		local p = VM.part
		if not p then
			return
		end
		VM.t += dt
		local target = targets[VM.mode] or targets.hidden
		VM.offset = VM.offset:Lerp(target, 1 - math.exp(-dt * 8))
		local bob = CFrame.new(math.sin(VM.t * 1.3) * 0.01, math.sin(VM.t * 2.1) * 0.012, 0)
		p.CFrame = camera().CFrame * VM.offset * bob
		if VM.mode == "hidden" and (VM.offset.Position - targets.hidden.Position).Magnitude < 0.05 then
			p.Parent = nil
			return
		end
		-- screen animation
		local sg = VM.gui
		local boss = sg:FindFirstChild("Boss") :: Frame
		boss.Position = UDim2.fromScale(0.5 + math.sin(VM.t * 1.7) * 0.28, 0.3 + math.sin(VM.t * 2.9) * 0.04)
		local ship = sg:FindFirstChild("Ship") :: Frame
		ship.Position = UDim2.fromScale(0.5 + math.sin(VM.t * 1.1 + 1) * 0.3, 0.78)
		local laser = sg:FindFirstChild("Laser") :: Frame
		laser.Position = UDim2.fromScale(ship.Position.X.Scale, 0.72)
		laser.Visible = math.floor(VM.t * 8) % 2 == 0
		local temp = 71 + VM.heat * 29
		local hud = sg:FindFirstChild("Hud") :: TextLabel
		hud.Text = string.format("FPS %d   CPU %d°C", math.max(1, 12 - math.floor(VM.heat * 10)), math.floor(temp))
		hud.TextColor3 = if VM.heat > 0.5 then rgb(255, 120, 120) else rgb(200, 255, 200)
		local warn = sg:FindFirstChild("Warn") :: Frame
		warn.Visible = VM.heat > 0.6 and math.floor(VM.t * 5) % 2 == 0
		local wt = warn:FindFirstChild("Text") :: TextLabel
		wt.Text = Lang.t("phone.hot") .. " " .. math.floor(temp) .. "°C"
		if VM.heat > 0.3 then
			p.CFrame = p.CFrame * CFrame.new((math.random() - 0.5) * 0.01 * VM.heat, (math.random() - 0.5) * 0.01 * VM.heat, 0)
		end
	end)
end

----------------------------------------------------------------------------
-- Rick's radar (prop in his hand + big screen overlay)
----------------------------------------------------------------------------
local Radar = { gui = nil :: ScreenGui?, prop = nil :: BasePart?, on = false }
do
	local function build()
		local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
		local g = UI.new("ScreenGui", { Name = "Radar", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 35, Enabled = false, Parent = pg })
		local canvas = UI.canvas(g)
		local panel = UI.new("CanvasGroup", {
			Name = "Panel",
			BackgroundColor3 = rgb(6, 16, 10),
			BackgroundTransparency = 0.15,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -90, 0.42, 0),
			Size = UDim2.fromOffset(470, 600),
			GroupTransparency = 1,
			Parent = canvas,
		}, { UI.corner(24), UI.stroke(3, rgb(110, 255, 140), 0.3, true) })
		UI.label({ Text = "", Name = "Title", Font = Enum.Font.RobotoMono, TextSize = 26, TextColor3 = rgb(140, 255, 160), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 34), Parent = panel })
		local scope = UI.new("Frame", { Name = "Scope", BackgroundColor3 = rgb(10, 40, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(330, 330), ClipsDescendants = false, Parent = panel }, { UI.round(), UI.stroke(2, rgb(110, 255, 140), 0.2, true) })
		for i, s in { 0.66, 0.33 } do
			UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(s, s), Parent = scope }, { UI.round(), UI.stroke(1.5, rgb(110, 255, 140), 0.5, true) })
			local _ = i
		end
		UI.new("Frame", { BackgroundColor3 = rgb(110, 255, 140), BackgroundTransparency = 0.6, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1), Parent = scope })
		UI.new("Frame", { BackgroundColor3 = rgb(110, 255, 140), BackgroundTransparency = 0.6, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, 0), Parent = scope })
		local sweep = UI.new("Frame", { Name = "Sweep", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Parent = scope })
		UI.new("Frame", { BackgroundColor3 = rgb(140, 255, 160), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.5, 0, 0, 3), Parent = sweep }, { UI.gradient(nil, { 0, 0.6 }, 0) })
		UI.new("Frame", { Name = "Blip", BackgroundColor3 = rgb(255, 50, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.78, 0.22), Size = UDim2.fromOffset(22, 22), Parent = scope }, { UI.round() })
		UI.label({ Name = "Line1", Text = "", Font = Enum.Font.RobotoMono, TextSize = 24, TextColor3 = rgb(140, 255, 160), Position = UDim2.fromOffset(34, 420), Size = UDim2.new(1, -68, 0, 30), Parent = panel })
		UI.label({ Name = "Line2", Text = "", Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = rgb(255, 60, 50), Position = UDim2.fromOffset(34, 452), Size = UDim2.new(1, -68, 0, 40), Parent = panel })
		UI.label({ Name = "Line3", Text = "", Font = Enum.Font.RobotoMono, TextSize = 24, TextColor3 = rgb(140, 255, 160), Position = UDim2.fromOffset(34, 500), Size = UDim2.new(1, -68, 0, 30), Parent = panel })
		UI.label({ Name = "Line4", Text = "", Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = rgb(255, 220, 60), Position = UDim2.fromOffset(34, 532), Size = UDim2.new(1, -68, 0, 40), Parent = panel })
		Radar.gui = g
		Radar.panel = panel
		Radar.sweep = sweep
		Radar.blip = scope:FindFirstChild("Blip")
	end
	-- lines = { title, line1, line2, line3, line4 } (Lang keys); nil = the threat screen
	function Radar.setLines(lines: { any }?)
		if not Radar.gui then
			build()
		end
		local l = lines or { "radar.title", "radar.threat", "radar.max", "radar.eta", "radar.days" }
		local panel = Radar.panel
		panel:FindFirstChild("Title").Text = Lang.t(l[1])
		panel:FindFirstChild("Line1").Text = Lang.t(l[2])
		panel:FindFirstChild("Line2").Text = Lang.t(l[3])
		panel:FindFirstChild("Line3").Text = Lang.t(l[4])
		panel:FindFirstChild("Line4").Text = Lang.t(l[5])
	end
	-- where the red dot is on the scope (0..1, 0..1)
	function Radar.setBlip(x: number, y: number, visible: boolean?)
		if not Radar.gui then
			build()
		end
		Radar.blip.Position = UDim2.fromScale(x, y)
		Radar.blip.Visible = visible ~= false
	end
	function Radar.show(on: boolean, lines: { any }?)
		if not Radar.gui then
			build()
		end
		Radar.on = on
		local g = Radar.gui :: ScreenGui
		local panel = Radar.panel
		if on then
			g.Enabled = true
			Radar.setLines(lines)
			panel.Position = UDim2.new(1, -60, 0.42, 0)
			UI.tween(panel, 0.5, { GroupTransparency = 0, Position = UDim2.new(1, -90, 0.42, 0) }, Enum.EasingStyle.Back)
		else
			UI.tween(panel, 0.3, { GroupTransparency = 1 })
			task.delay(0.35, function()
				if not Radar.on then
					g.Enabled = false
				end
			end)
		end
	end
	local pingT = 0
	RunService.RenderStepped:Connect(function(dt)
		if Radar.on and Radar.sweep then
			Radar.sweep.Rotation = (Radar.sweep.Rotation + dt * 180) % 360
			Radar.blip.BackgroundTransparency = if math.floor(os.clock() * 3) % 2 == 0 then 0 else 0.6
			pingT += dt
			if pingT > 1 then
				pingT = 0
				Audio.play("RadarPing")
			end
		end
		local prop = Radar.prop
		if prop and P.rick then
			local arm = P.rick.model:FindFirstChild("Right Arm") :: BasePart?
			if arm then
				prop.CFrame = arm.CFrame * CFrame.new(-0.2, -1.25, -0.35) * CFrame.Angles(math.rad(-90), 0, 0)
			end
		end
	end)
	function Radar.holdProp(on: boolean)
		if on and not Radar.prop then
			local p = Fx.part({ Size = Vector3.new(1.1, 0.22, 0.8), Color = rgb(70, 74, 80), Material = Enum.Material.Metal })
			local screen = Instance.new("Part")
			screen.Size = Vector3.new(0.7, 0.05, 0.55)
			screen.Color = rgb(110, 255, 140)
			screen.Material = Enum.Material.Neon
			screen.Anchored = false
			screen.CanCollide = false
			screen.Massless = true
			screen.CFrame = p.CFrame * CFrame.new(0, 0.12, 0)
			local w = Instance.new("WeldConstraint")
			w.Part0 = p
			w.Part1 = screen
			w.Parent = screen
			screen.Parent = p
			Radar.prop = p
		elseif not on and Radar.prop then
			(Radar.prop :: BasePart):Destroy()
			Radar.prop = nil
		end
	end
end

----------------------------------------------------------------------------
-- world state helpers
----------------------------------------------------------------------------
local doorOpen = false
local function setDoor(open: boolean, instant: boolean?)
	doorOpen = open
	R.doorModel:SetAttribute("Open", open)
	local hinge = R.doorLeaf:GetAttribute("Hinge") or Vector3.new(5.13, 3.4, 8.39)
	local from = if open then 0 else math.rad(100)
	local to = if open then math.rad(100) else 0
	if instant then
		hingeRotate(init.door, hinge, CFrame.Angles(0, to, 0))
		return
	end
	play3D("Click", hinge, 0.6)
	task.spawn(animate, 0.8, function(a)
		hingeRotate(init.door, hinge, CFrame.Angles(0, from + (to - from) * a, 0))
	end)
end

local function setGarageDoor(open: boolean, instant: boolean?)
	local hinge = R.garageDoor:GetAttribute("Hinge") or Vector3.new(-19.8, -1.05, -21)
	local to = if open then math.rad(85) else 0
	if instant then
		hingeRotate(init.garageDoor, hinge, CFrame.Angles(0, 0, to))
		return
	end
	play3D("GarageDoor", hinge)
	animate(1.8, function(a)
		hingeRotate(init.garageDoor, hinge, CFrame.Angles(0, 0, to * a))
	end)
end

local function setPhoneOnNightstand(visible: boolean)
	for _, d in R.phone:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if visible then 0 else 1
			d.CanQuery = visible
		end
	end
end

local function familyAtBreakfast()
	for name, poseName in { Beth = "sitEat", Jerry = "sitRead", Summer = "sitPhone" } do
		local p = P[string.lower(name)]
		local seat = R.seats:FindFirstChild(name)
		if p and seat then
			p:place(seat.CFrame)
			p:pose(poseName, 8)
			p:lookAt(nil)
			p.gesture = 1
		end
	end
end

local function saucerThrust(on: boolean)
	emitters(R.saucer, "Thrust", on)
end

local function saucerTo(cf: CFrame)
	R.saucer:PivotTo(cf)
end

-- fly the saucer to `target` over `duration`, with a little wobble. Yields.
local function fly(target: CFrame, duration: number, easeKind: string?, wobble: number?)
	local from = R.saucer:GetPivot()
	local w = wobble or 0.04
	local t0 = os.clock()
	animate(duration, function(a)
		local t = os.clock() - t0
		local cf = from:Lerp(target, a) * CFrame.Angles(math.sin(t * 2.3) * w, 0, math.sin(t * 1.7) * w)
		saucerTo(cf)
	end, easeKind)
end

local function seatRickInSaucer()
	local rick = P.rick
	rick.follow = function()
		return R.saucerSpots.SeatRick.CFrame
	end
	rick:pose("pilot", 10)
	rick:lookAt(nil)
end

local function mortySaucerEye(): CFrame
	return R.saucerSpots.EyeMorty.CFrame * CFrame.Angles(math.rad(-10), 0, 0)
end

local function ensureDesert(c)
	c.waitUntil(function()
		return workspace:GetAttribute("DesertReady") == true
	end, 30)
	-- make sure the terrain has reached us
	c.waitUntil(function()
		local hit = workspace:Raycast(Vector3.new(6000, 50, 0), Vector3.new(0, -100, 0))
		return hit ~= nil
	end, 20)
end

-- character: make sure it exists, then put it somewhere hidden / frozen for a cutscene
local function holdCharacterAt(c, cf: CFrame)
	if not api.root() then
		api.spawn()
		c.check()
	end
	api.hideCharacter(true)
	local r = api.root()
	if r and r.Anchored and not r:GetAttribute("ClientFrozen") then
		-- still held by the server after spawning
		api.release(cf)
	else
		api.teleport(cf)
	end
	c.check()
	api.freeze(true)
end

local function giveControl(c, cf: CFrame, look: CFrame?)
	if not api.root() then
		api.spawn()
		c.check()
	end
	local r = api.root()
	if r and r.Anchored and not r:GetAttribute("ClientFrozen") then
		-- still held by the server after spawning
		api.release(cf)
	else
		api.freeze(false)
		api.teleport(cf)
	end
	c.check()
	api.hideCharacter(false)
	api.gameplay(true, look or (CFrame.new(cf.Position + Vector3.new(0, 1.5, 0)) * cf.Rotation))
end

----------------------------------------------------------------------------
-- CHAPTER 1: Good morning
----------------------------------------------------------------------------
local CH = {}

CH[1] = function(c, _fresh: boolean)
	api.state("story")
	Director.start()
	local face = api.headCore.CFrame
	Audio.play("Whoosh")
	Director.move(CFrame.lookAt(face.Position + face.LookVector * 2.4 + Vector3.new(0.9, 0.5, 0.9), face.Position), 2.0, "smooth", 50)
	c.check()
	Fx.fade(1, 0.6, true)
	api.snore(false)
	api.setSleeping(false)
	api.lids(0, 0)
	task.spawn(api.spawn)
	api.hideCharacter(true)
	Scenes.apply("Morning", true)
	setPhoneOnNightstand(true)
	setDoor(false, true)
	Fx.black(0)
	api.setAlarm(true)
	Fx.title("ch.1")
	c.check()
	local eye = eyeFromHead(face)
	api.lie(eye, { blink = true, closedTime = 0.3, allowOnly = { AlarmClock = true } })
	c.check()
	api.waitGetUp(if api.isTouch then "hint.lying.touch" else "hint.lying")
	c.check()
	-- get up: sit on the edge of the bed, then stand
	Audio.play("Cloth")
	task.delay(0.5, Audio.play, "GetUp")
	local sitPos = Vector3.new(-6.95, 4.55, -4.9)
	Director.move(CFrame.lookAt(sitPos, sitPos + Vector3.new(1, -0.28, 0.35)), 1.4)
	c.wait(0.15)
	local wp = api.wakePoint.CFrame
	local standPos = wp.Position + Vector3.new(0, 1.5, 0)
	local standCF = CFrame.lookAt(standPos, standPos + wp.LookVector * 10 + Vector3.new(0, -0.8, 0))
	Director.move(standCF, 1.1)
	c.waitUntil(function()
		return api.root() ~= nil
	end, 10)
	api.release(wp)
	api.hideCharacter(false)
	api.gameplay(true, standCF)
	c.check()

	-- the phone
	local phoneTaken = false
	api.handlers.Door = function()
		if not phoneTaken then
			Audio.play("Click", 0.7)
			api.say({ ru = "Морти: Стоп... а телефон?", en = "Morty: Wait... where's my phone?" })
		else
			setDoor(not doorOpen)
		end
	end
	api.objective("obj.phone")
	api.prompt(if api.isTouch then "hint.walk.touch" else "hint.walk")
	task.delay(7, function()
		if c.alive() then
			api.prompt(nil)
		end
	end)
	c.interact("Phone")
	phoneTaken = true
	setPhoneOnNightstand(false)
	Audio.play("Click", 1.3)
	VM.setMode("hand")
	api.objective(nil)
	c.say("MortyThought", { ru = "Так... ещё один уровень Galaxy Raid перед завтраком.", en = "Okay... one more level of Galaxy Raid before breakfast." }, { auto = true })
	Dialogue.hide()
	c.wait(0.4)
	c.say("Beth", { ru = "(снизу) МОРТИ! Завтрак на столе!", en = "(from downstairs) MORTY! Breakfast is ready!" }, { auto = 2 })
	Dialogue.hide()
	api.objective("obj.kitchen")
	local chairPos = R.seats:FindFirstChild("Morty").Position
	c.waitUntil(function()
		local r = api.root()
		return r ~= nil and (r.Position - chairPos).Magnitude < 9
	end)
	api.objective("obj.sit")
	c.interact("SitDown")
	api.objective(nil)
end

----------------------------------------------------------------------------
-- CHAPTER 2: Breakfast
----------------------------------------------------------------------------
local function kitchenBlast(c, eye: CFrame, blastPos: Vector3, beepSound: Sound?)
	Fx.flash(Color3.new(1, 1, 1), 1, 0.03, 1.4)
	Fx.explosion(blastPos, 0.5, { sound = "ExplosionSmall", debris = 18, debrisColors = { rgb(30, 30, 34), rgb(200, 200, 210), rgb(110, 230, 255) } })
	play3D("Electric", blastPos)
	stopLoop(beepSound, 0.05)
	VM.setMode("hidden")
	VM.setHeat(0)
	for _, name in { "beth", "jerry", "summer" } do
		P[name]:pose("sitShocked", 18)
		P[name]:lookAt(blastPos)
		P[name].talking = false
	end
	Director.freeLook(false)
	Director.shake(2.4, 1.6, 16)
	Fx.muffle(true)
	Audio.play("Tinnitus")
	Director.move(eye * CFrame.new(0.3, 0.4, 1.4) * CFrame.Angles(math.rad(38), math.rad(12), math.rad(28)), 0.45, "out")
	c.wait(0.3)
	Director.move(eye * CFrame.new(0.6, -1.8, 2.6) * CFrame.Angles(math.rad(70), math.rad(20), math.rad(80)), 0.9, "in")
	Audio.play("Thud")
	Director.shake(1.2, 0.5)
	Fx.glitch(0.6, 0.35)
	Fx.fade(1, 1.4, true)
	Audio.music(nil, 1)
	c.wait(1.2)
	Fx.muffle(false)
end

CH[2] = function(c, fresh: boolean)
	api.state("story")
	api.gameplay(false)
	local seat = R.seats:FindFirstChild("Morty").CFrame
	local eye = seat * CFrame.new(0, 1.95, -0.3) * CFrame.Angles(math.rad(-12), 0, 0)
	if fresh then
		Fx.black(1)
		api.setSleeping(false)
		Scenes.apply("Morning", true)
		setPhoneOnNightstand(false)
		setDoor(true, true)
	end
	holdCharacterAt(c, seat * CFrame.new(1.8, 0, 0))
	familyAtBreakfast()
	Director.start()
	if fresh then
		Director.cut(eye, 72)
		Fx.fade(0, 1)
	else
		Director.move(eye, 1.2, "smooth", 72)
	end
	Audio.play("Cloth", 0.9)
	Director.freeLook(true, { yaw = 1.3, pitchUp = 0.5, pitchDown = 0.8 })
	VM.setMode("table")
	VM.setHeat(0.2)
	Audio.music("MusicBreakfast", 2)
	local clinking = true
	task.spawn(function()
		while clinking and c.alive() do
			task.wait(1.5 + math.random() * 2.5)
			if clinking then
				Audio.play("Clink", 0.8 + math.random() * 0.6)
			end
		end
	end)
	Fx.title("ch.2")
	c.check()
	local beth, jerry, summer = P.beth, P.jerry, P.summer
	jerry:lookAt(eye.Position)
	c.say("Jerry", { ru = "Доброе утро, сынок! Знаешь, какой сегодня день? День... э-э... отличных дел!", en = "Morning, son! You know what today is? It's a day for... uh... great things!" })
	jerry:lookAt(nil)
	c.say("Summer", { ru = "Пап, никто не спрашивал.", en = "Dad, nobody asked." })
	VM.setHeat(0.35)
	c.say("MortyThought", { ru = "Ещё чуть-чуть... босс почти побеждён...", en = "Almost there... the boss is almost dead..." })
	-- Beth notices the phone
	beth:lookAt(eye.Position)
	c.wait(0.6)
	beth:pose("sitPoint", 14)
	Director.shake(0.6, 0.4)
	Audio.play("Thud", 1.4)
	c.say("Beth", { ru = "МОРТИ!! Ты уже везде со своим телефоном ходишь! Мне это надоело! Убирай сейчас же!", en = "MORTY!! You take that phone everywhere! I'm sick of it! Put it away right now!" })
	summer:lookAt(eye.Position)
	c.say("Summer", { ru = "Ха. Попался.", en = "Ha. Busted." }, { auto = 1.2 })
	Dialogue.hide()
	Director.freeLook(false)
	local pick = Dialogue.choice({
		{ ru = "Убрать телефон", en = "Put the phone away" },
		{ ru = "Не убирать", en = "Keep playing" },
	})
	c.check()
	Director.freeLook(true)
	local beep: Sound? = nil
	local blastPos: Vector3
	if pick == 1 then
		c.say("Morty", { ru = "Ладно, ладно... всё, убрал.", en = "Okay, okay... it's away." }, { auto = true })
		VM.setMode("pocket")
		Audio.play("Cloth", 1.2)
		beth:pose("sitEat", 8)
		beth:lookAt(nil)
		summer:lookAt(nil)
		c.say("Beth", { ru = "Спасибо, милый. Ешь, пока не остыло.", en = "Thank you, sweetie. Eat before it gets cold." }, { auto = true })
		c.say("Jerry", { ru = "Кстати, я тут подумал заняться... гончарным делом.", en = "By the way, I've been thinking of taking up... pottery." }, { auto = true })
		c.say("Summer", { ru = "Не надо.", en = "Don't." }, { auto = 1.1 })
		Dialogue.hide()
		local function pocket(): Vector3
			return (camera().CFrame * CFrame.new(0.6, -2.2, -0.6)).Position
		end
		beep = loopSound("OverheatBeep", camera())
		c.wait(1.6)
		c.say("MortyThought", { ru = "Чего это так греется в кармане?..", en = "Why is my pocket getting so hot..." }, { auto = true })
		local smoking = true
		task.spawn(function()
			while smoking and c.alive() do
				Fx.smoke(pocket(), 0.5, 4, rgb(90, 90, 96), 2)
				task.wait(0.25)
			end
		end)
		if beep then
			beep.PlaybackSpeed = 1.3
		end
		jerry:lookAt(eye.Position + Vector3.new(0, -1.5, 0))
		c.say("Jerry", { ru = "Кто-то жарит бекон?", en = "Is someone frying bacon?" }, { auto = true })
		if beep then
			beep.PlaybackSpeed = 1.7
		end
		c.say("Morty", { ru = "Ой... я же не закрыл игру!", en = "Oh no... I didn't close the game!" }, { auto = 1.0 })
		smoking = false
		Dialogue.hide()
		blastPos = pocket()
	else
		c.say("Morty", { ru = "Мам, ну ещё минуточку! Тут босс!", en = "Mom, just one more minute! It's a boss fight!" }, { auto = true })
		c.say("Beth", { ru = "Морти Смит!!", en = "Morty Smith!!" }, { auto = 1.2 })
		beep = loopSound("OverheatBeep", camera())
		local heating = true
		task.spawn(function()
			local h = 0.35
			while heating and c.alive() do
				h = math.min(1, h + 0.04)
				VM.setHeat(h)
				if h > 0.55 then
					Fx.smoke(VM.position(), 0.4, 3, rgb(90, 90, 96), 1.6)
				end
				if beep then
					beep.PlaybackSpeed = 1 + h
				end
				task.wait(0.2)
			end
		end)
		c.wait(1.4)
		jerry:lookAt(VM.position())
		c.say("Jerry", { ru = "Сынок... он что, дымится?", en = "Son... is that thing smoking?" }, { auto = true })
		summer:lookAt(VM.position())
		c.say("Morty", { ru = "Э-э-э... мам?..", en = "Uh... Mom?.." }, { auto = 1.0 })
		heating = false
		Dialogue.hide()
		blastPos = VM.position()
	end
	clinking = false
	kitchenBlast(c, eye, blastPos, beep)
end

----------------------------------------------------------------------------
-- CHAPTER 3: Rick's garage
----------------------------------------------------------------------------
local RICK_NONSENSE = {
	{ ru = "Шлёп-шлёп... зюзюбрики.", en = "Wubba lubba... flarp." },
	{ ru = "Я вижу звуки, Морти. Они фиолетовые.", en = "I can see sounds, Morty. They're purple." },
	{ ru = "Кто-нибудь заказывал пиццу с... болтами?", en = "Did anyone order a pizza with... bolts?" },
	{ ru = "Морти, у меня в ухе кто-то ремонт делает.", en = "Morty, somebody's renovating my ear." },
}

CH[3] = function(c, _fresh: boolean)
	api.state("story")
	api.gameplay(false)
	Fx.black(1)
	Director.start()
	local stand = R.garageSpots.MortyStand.CFrame
	holdCharacterAt(c, stand)
	VM.setMode("hidden")
	api.setAlarm(false)
	Scenes.apply("Garage", true)
	setGarageDoor(false, true)
	saucerTo(init.saucer)
	local rick = P.rick
	rick.follow = nil
	rick:place(R.garageSpots.RickByTable.CFrame)
	rick:pose("lean", 8)
	rick.glitch = 0.35
	local head = R.garageSpots.MortyHead.CFrame
	rick:lookAt(head.Position)
	local bubbles = loopSound("Bubbles", R.lab:FindFirstChild("Vat"):FindFirstChild("Goo"))
	local _ = bubbles
	api.lids(0, 0)
	Fx.title("ch.3")
	c.check()
	Fx.black(0)
	api.lie(eyeFromHead(head), { blink = true, closedTime = 0.5, interact = false, yaw = 1.5 })
	c.check()
	c.say("Rick", { ru = "Морти! Морти, ты меня слышишь? *бульк*", en = "Morty! Morty, can you hear me? *burp*" }, { glitch = 0.2 })
	Audio.play("Burp", 0.9)
	c.say("Rick", { ru = "Ты взорвался, Морти. Твой телефон взорвался. Прямо за завтраком.", en = "You exploded, Morty. Your phone exploded. Right at breakfast." }, { glitch = 0.35 })
	c.say("Rick", { ru = "Пришлось собрать тебя по к-к-кусочкам. Девяносто ш-ш-шесть процентов тебя. Остальное... не спрашивай.", en = "Had to put you back together p-p-piece by piece. Ninety-s-s-six percent of you. The rest... don't ask." }, { glitch = 0.6 })
	c.say("Morty", { ru = "Рик... с тобой всё нормально? Ты какой-то... мерцаешь.", en = "Rick... are you okay? You're kind of... flickering." })
	rick.glitch = 1
	Fx.glitch(1.2, 0.7)
	Audio.play("Glitch3")
	c.say("Rick", { ru = "Я в полном порядке, Морти. Я огурчик. Я ТОСТЕР. Я... ОШИБКА: РИК_НЕ_НАЙДЕН.", en = "I'm totally fine, Morty. I'm a pickle. I'm a TOASTER. I'm... ERROR: RICK_NOT_FOUND." }, { glitch = 1 })
	rick.glitch = 0.35
	c.say("Rick", { ru = "...Короче, неважно. Вставай, хватит валяться!", en = "...Anyway, never mind. Get up, quit lying around!" }, { glitch = 0.2 })
	Dialogue.hide()
	api.waitGetUp(if api.isTouch then "hint.lying.touch" else "hint.lying.simple")
	c.check()
	Audio.play("Cloth")
	task.delay(0.4, Audio.play, "GetUp")
	local sitPos = Vector3.new(-39.4, -3.25, -20.8)
	Director.move(CFrame.lookAt(sitPos, sitPos + Vector3.new(1, -0.25, 0.1)), 1.3)
	local standEye = CFrame.new(stand.Position + Vector3.new(0, 1.5, 0)) * stand.Rotation
	Director.move(standEye, 1.0)
	rick:pose("stand", 8)
	giveControl(c, stand, standEye)
	-- Rick keeps looking at Morty
	local watching = true
	task.spawn(function()
		while watching and c.alive() do
			rick:lookAt(camera().CFrame.Position)
			task.wait(0.1)
		end
	end)
	c.say("Rick", { ru = "Слушай сюда. Нас ждёт очередное приключение! Планета B137.", en = "Listen up. Another adventure awaits! Planet B137." }, { auto = true, glitch = 0.25 })
	c.say("Rick", { ru = "Пустыня, оранжевое небо и никаких телефонов. Тебе понравится.", en = "Desert, orange sky and no phones. You'll love it." }, { auto = true, glitch = 0.25 })
	c.say("Rick", { ru = "Сколько пальцев я показываю? Неправильно. Их у меня одиннадцать.", en = "How many fingers am I holding up? Wrong. I have eleven." }, { auto = true, glitch = 0.7 })
	c.say("Rick", { ru = "Садись в тарелку!", en = "Get in the saucer!" }, { auto = 1.5, glitch = 0.2 })
	Dialogue.hide()
	api.objective("obj.saucer")
	watching = false
	-- Rick climbs into the pilot seat
	local seatPos = R.saucerSpots.SeatRick.Position
	local side = Vector3.new(seatPos.X - 4.6, rick.root.Position.Y, seatPos.Z)
	rick:walkTo(side, 7)
	c.check()
	local from = rick.root.CFrame
	animate(0.6, function(a)
		rick.root.CFrame = from:Lerp(R.saucerSpots.SeatRick.CFrame, a) * CFrame.new(0, math.sin(a * math.pi) * 1.5, 0)
	end)
	seatRickInSaucer()
	-- while we wait, Rick talks nonsense
	local waiting = true
	task.spawn(function()
		local i = 0
		while waiting and c.alive() do
			task.wait(9)
			if waiting then
				i = i % #RICK_NONSENSE + 1
				rick.glitch = 0.9
				Audio.play("Glitch1")
				api.say({ ru = "Рик: " .. RICK_NONSENSE[i].ru, en = "Rick: " .. RICK_NONSENSE[i].en }, 3)
				task.wait(0.6)
				rick.glitch = 0.3
			end
		end
	end)
	c.interact("Saucer")
	waiting = false
	api.objective(nil)
end

----------------------------------------------------------------------------
-- CHAPTER 4: Flight to B137
----------------------------------------------------------------------------
CH[4] = function(c, fresh: boolean)
	api.state("story")
	api.gameplay(false)
	Fx.fade(1, 0.35, true)
	if fresh then
		Scenes.apply("Garage", true)
		saucerTo(init.saucer)
		setGarageDoor(false, true)
		P.rick.glitch = 0.3
	end
	holdCharacterAt(c, R.garageSpots.MortyStand.CFrame)
	seatRickInSaucer()
	Director.start()
	Director.track(mortySaucerEye)
	Director.freeLook(true, { yaw = 1.7, pitchUp = 0.9, pitchDown = 0.9 })
	Director.fov(72)
	Fx.fade(0, 0.6)
	local hum = loopSound("UfoHum", R.saucer.PrimaryPart)
	saucerThrust(true)
	task.spawn(Fx.title, "ch.4")
	c.say("Rick", { ru = "Пристегнись, Морти. А, тут нет ремней. Ну держись тогда.", en = "Buckle up, Morty. Oh wait, no seatbelts. Just hold on then." }, { auto = true, glitch = 0.2 })
	Dialogue.hide()
	setGarageDoor(true)
	c.check()
	Audio.music("MusicFlight", 2)
	local p0 = init.saucer
	fly(p0 * CFrame.new(0, 3, 0), 1.6, "smooth", 0.03)
	Audio.play("Takeoff")
	fly(CFrame.lookAt(Vector3.new(-12, -5.5, -21), Vector3.new(20, -4, -21)), 2.6, "in", 0.02)
	Scenes.apply("Sky")
	fly(CFrame.lookAt(Vector3.new(16, 34, -56), Vector3.new(40, 110, -130)), 3.6, "linear", 0.03)
	c.say("Morty", { ru = "Ух ты... наш дом отсюда такой маленький!", en = "Whoa... our house looks so tiny from up here!" }, { auto = 1.6, noWait = false })
	Dialogue.hide()
	fly(CFrame.lookAt(Vector3.new(46, 170, -160), Vector3.new(70, 300, -260)), 2.6, "linear", 0.02)
	-- warp
	Fx.speedLines(true, 1.6)
	Director.fov(115, 1.2)
	Audio.play("Warp")
	Director.shake(0.6, 1.4, 20)
	fly(CFrame.lookAt(Vector3.new(70, 300, -260), Vector3.new(100, 500, -400)), 1.2, "in", 0.01)
	Fx.flash(Color3.new(1, 1, 1), 1, 0.08, 0.7)
	c.wait(0.08)
	Scenes.apply("Space", true)
	local S = Vector3.new(-9000, 3000, 0)
	saucerTo(CFrame.lookAt(S, S + Vector3.new(0, -0.05, -1)))
	Director.fov(72, 0.8)
	Fx.speedLines(false)
	-- cruise towards the planet
	local cruising = true
	task.spawn(function()
		local from = R.saucer:GetPivot()
		local to = CFrame.lookAt(S + Vector3.new(0, -300, -2700), S + Vector3.new(0, -360, -3700))
		local t0 = os.clock()
		while cruising and c.alive() do
			local a = math.clamp((os.clock() - t0) / 18, 0, 1)
			local t = os.clock() - t0
			saucerTo(from:Lerp(to, a) * CFrame.Angles(math.sin(t * 0.9) * 0.02, 0, math.sin(t * 0.7) * 0.03))
			RunService.RenderStepped:Wait()
		end
	end)
	c.wait(1.5)
	c.say("Rick", { ru = "Вот она. B137. Местные называют её... никак. Тут нет местных. Наверное.", en = "There she is. B137. The locals call it... nothing. There are no locals. Probably." }, { auto = true, glitch = 0.2 })
	P.rick.glitch = 1
	Fx.glitch(1.4, 0.8)
	Audio.play("Glitch2")
	Director.shake(0.8, 1.2)
	c.say("Rick", { ru = "B137... B137... Б-Б-Б-Б-Б—", en = "B137... B137... B-B-B-B-B—" }, { auto = 1.0, glitch = 1 })
	c.say("Morty", { ru = "Рик?!", en = "Rick?!" }, { auto = 0.8 })
	P.rick.glitch = 0.3
	c.say("Rick", { ru = "Всё нормально! Помехи. Космические. Наверное. *бульк*", en = "Everything's fine! Interference. Space interference. Probably. *burp*" }, { auto = true, glitch = 0.3 })
	Audio.play("Burp", 0.85)
	Dialogue.hide()
	c.wait(3)
	-- re-entry
	local reentry = loopSound("Reentry", camera())
	Fx.heat(0.6, 2.5)
	Director.shake(1.4, 4.5, 18)
	c.say("Morty", { ru = "Рик, мы горим!", en = "Rick, we're on fire!" }, { auto = 1.2 })
	c.say("Rick", { ru = "Это называется «вход в атмосферу», Морти!", en = "It's called atmospheric entry, Morty!" }, { auto = 1.2 })
	Dialogue.hide()
	c.wait(1.2)
	Fx.flash(rgb(255, 170, 90), 1, 0.25, 1.0)
	c.wait(0.25)
	cruising = false
	stopLoop(reentry, 1)
	ensureDesert(c)
	Scenes.apply("Desert", true)
	Fx.heat(0, 1.5)
	-- land
	local land = R.spots.Landing.CFrame
	local startPos = (land * CFrame.new(-120, 230, 260)).Position
	saucerTo(CFrame.lookAt(startPos, land.Position + Vector3.new(0, 30, 0)))
	fly(CFrame.lookAt((land * CFrame.new(0, 26, 0)).Position, (land * CFrame.new(0, 26, -10)).Position), 5, "out", 0.03)
	fly(land, 2.4, "out", 0.015)
	Fx.dust(land.Position, 14, 70)
	Director.shake(0.9, 0.7)
	Audio.play("Thud", 0.7)
	saucerThrust(false)
	stopLoop(hum, 2)
	Audio.music(nil, 3)
end

----------------------------------------------------------------------------
-- CHAPTER 5: Planet B137
----------------------------------------------------------------------------
local function crashSite(): CFrame
	local o = R.spots.Landing.Position
	return CFrame.new(o + Vector3.new(14, -0.6, -6)) * CFrame.Angles(math.rad(14), math.rad(70), math.rad(-11))
end

CH[5] = function(c, fresh: boolean)
	api.state("story")
	api.gameplay(false)
	if fresh then
		Fx.black(1)
		ensureDesert(c)
		Scenes.apply("Desert", true)
		saucerTo(R.spots.Landing.CFrame)
		P.rick.glitch = 0.3
		holdCharacterAt(c, R.spots.MortyExit.CFrame)
		seatRickInSaucer()
		Director.start()
		Director.track(mortySaucerEye)
		Fx.fade(0, 0.8)
	end
	Audio.music("MusicEerie", 3)
	task.spawn(Fx.title, "ch.5")
	c.say("Rick", { ru = "Приехали. Выходи, Морти, разомни ноги.", en = "We're here. Out you go, Morty. Stretch your legs." }, { auto = true, glitch = 0.2 })
	Dialogue.hide()
	Fx.fade(1, 0.35, true)
	local exitCF = R.spots.MortyExit.CFrame
	Director.stop()
	giveControl(c, exitCF)
	Fx.fade(0, 0.5)
	api.objective("obj.look")
	local r = api.root()
	local startPos = if r then r.Position else exitCF.Position
	c.waitUntil(function()
		local rr = api.root()
		return rr ~= nil and (rr.Position - startPos).Magnitude > 7
	end, 5)
	api.objective(nil)

	-- Rick ditches Morty
	api.gameplay(false)
	api.freeze(true)
	local eyePos = camera().CFrame.Position
	local lookAtPos = R.saucer:GetPivot().Position + Vector3.new(0, 3, 0)
	local focus = camera().CFrame.Position + camera().CFrame.LookVector * 10
	Director.start()
	Director.track(function(dt)
		focus = focus:Lerp(lookAtPos, math.min(1, dt * 4))
		return CFrame.lookAt(eyePos, focus)
	end)
	c.say("Rick", { ru = "Прощай, Морти! Так будет лучше!", en = "Goodbye, Morty! It's for the best!" }, { auto = 1.2, glitch = 0.2 })
	Dialogue.hide()
	local hum = loopSound("UfoHum", R.saucer.PrimaryPart)
	saucerThrust(true)
	Audio.play("Takeoff")
	local land = R.spots.Landing.CFrame
	local tracking = true
	task.spawn(function()
		while tracking and c.alive() do
			lookAtPos = R.saucer:GetPivot().Position + Vector3.new(0, 2, 0)
			RunService.RenderStepped:Wait()
		end
	end)
	fly(land * CFrame.new(0, 12, 0), 1.2, "out", 0.03)
	local hitPos = (land * CFrame.new(46, 30, -78)).Position
	fly(CFrame.lookAt(hitPos, hitPos + (hitPos - land.Position).Unit), 1.8, "in", 0.02)
	-- something unseen hits the saucer (its hand): a dark blur + shock
	local hand = R.hand
	local from = CFrame.lookAt(hitPos + Vector3.new(-60, 30, 30), hitPos) * CFrame.Angles(0, 0, math.rad(80))
	local to = CFrame.lookAt(hitPos + Vector3.new(40, -10, -20), hitPos + Vector3.new(80, -10, -40)) * CFrame.Angles(0, 0, math.rad(80))
	setParts(hand, { Transparency = 0.55 })
	task.spawn(function()
		animate(0.3, function(a)
			hand:PivotTo(from:Lerp(to, a))
		end, "in")
		setParts(hand, { Transparency = 1 })
	end)
	c.wait(0.18)
	play3D("MetalCrash", hitPos)
	Audio.play("Boom", 0.8)
	Fx.shockwave(hitPos, 26, 0.45, rgb(30, 20, 30))
	Fx.sparks(hitPos, 60)
	Director.shake(1.6, 0.8)
	stopLoop(hum, 0.3)
	saucerThrust(false)
	-- tumble down next to Morty
	local site = crashSite()
	local start = R.saucer:GetPivot()
	local spinAxis = CFrame.Angles(0, 0, 0)
	local t0 = os.clock()
	animate(1.6, function(a)
		local t = os.clock() - t0
		local pos = bezier(start.Position, start.Position:Lerp(site.Position, 0.5) + Vector3.new(0, 16, 0), site.Position + Vector3.new(0, 1.2, 0), a)
		spinAxis = CFrame.Angles(t * 7, t * 3, t * 5)
		saucerTo(CFrame.new(pos) * spinAxis)
	end, "in")
	tracking = false
	saucerTo(site)
	Fx.explosion(site.Position + Vector3.new(0, 1, 0), 1.2, { sound = "MetalCrash", debris = 22, debrisColors = { rgb(150, 155, 160), rgb(90, 96, 104), rgb(214, 146, 88) } })
	Fx.dust(site.Position, 22, 120)
	Director.shake(2.6, 1.4)
	emitters(R.saucer, "CrashSmoke", true)
	for _, d in R.saucer:GetDescendants() do
		if d:IsA("Fire") then
			d.Enabled = true
		end
	end
	lookAtPos = site.Position + Vector3.new(0, 2, 0)
	c.wait(1.6)
	-- Rick crawls out of the wreck
	local rick = P.rick
	rick.follow = nil
	local rickSeat = R.saucerSpots.SeatRick.CFrame
	local toward = (eyePos - site.Position) * Vector3.new(1, 0, 1)
	local crawlPos = site.Position + toward.Unit * 6 + Vector3.new(0, 3.36 - site.Position.Y + site.Position.Y, 0)
	crawlPos = Vector3.new(crawlPos.X, 3.36, crawlPos.Z)
	rick:place(rickSeat)
	rick:pose("crawl", 6)
	local crawlFrom = rick.root.CFrame
	local crawlTo = CFrame.lookAt(crawlPos, Vector3.new(eyePos.X, 3.36, eyePos.Z))
	animate(1.4, function(a)
		rick.root.CFrame = crawlFrom:Lerp(crawlTo, a)
		lookAtPos = rick.root.Position + Vector3.new(0, 1, 0)
	end)
	rick:pose("cough", 8)
	rick.glitch = 0.45
	c.say("Rick", { ru = "Кха-кха! Всё хорошо! Всё под контролем! Я так и задумал!", en = "Cough, cough! Everything's fine! Totally under control! That was the plan!" }, { glitch = 0.3 })
	rick:pose("stand", 6)
	rick:lookAt(eyePos)
	lookAtPos = rick.root.Position + Vector3.new(0, 2.2, 0)
	c.say("Morty", { ru = "Рик! Почему ты пытался меня бросить?!", en = "Rick! Why did you try to ditch me?!" })
	c.say("Rick", { ru = "Морти... за мной охотится проклятие. Проклятие неудачи.", en = "Morty... something's hunting me. A curse. A curse of bad luck." }, { glitch = 0.25 })
	c.say("Rick", { ru = "Я хотел увести его подальше от тебя. Освободить тебя, Морти. Не получилось.", en = "I wanted to lead it away from you. Set you free, Morty. Didn't work." }, { glitch = 0.25 })
	c.say("Morty", { ru = "А что тебя сбило?! Там же ничего не было!", en = "So what knocked you down?! There was nothing there!" })
	Fx.glitch(0.5, 0.4)
	c.say("Rick", { ru = "Это была ЕГО рука, Морти. Оно хотело добить меня... а потом вернуться за тобой.", en = "That was ITS hand, Morty. It wanted to finish me off... and then come back for you." }, { glitch = 0.5 })
	c.say("Rick", { ru = "Пошли. Тарелке конец, а стоять на месте — плохая идея.", en = "Come on. The saucer's toast, and standing still is a bad idea." }, { glitch = 0.2 })
	Dialogue.hide()
	-- walk with Rick to the old houses
	local look = camera().CFrame
	Director.stop()
	api.freeze(false)
	api.gameplay(true, look)
	api.objective("obj.follow")
	local reached = 0
	task.spawn(function()
		for i = 1, 5 do
			local m = R.spots:FindFirstChild("Path" .. i)
			if not m or not c.alive() then
				break
			end
			while c.alive() do
				local rr = api.root()
				if not rr or (rr.Position - rick.root.Position).Magnitude < 22 then
					break
				end
				rick:lookAt(rr.Position)
				task.wait(0.2)
			end
			rick:lookAt(nil)
			rick:walkTo(m.Position, 7.5)
			reached = i
		end
	end)
	c.waitUntil(function()
		return reached >= 2
	end)
	c.say("Morty", { ru = "Рик, а как выглядит это проклятие?", en = "Rick, what does this curse even look like?" }, { auto = true })
	c.say("Rick", { ru = "Не знаю, Морти. Никто его не видел и не остался... ну, целым.", en = "Don't know, Morty. Nobody's seen it and stayed... you know, in one piece." }, { auto = true, glitch = 0.2 })
	Dialogue.hide()
	c.waitUntil(function()
		return reached >= 3
	end)
	c.say("Rick", { ru = "А ещё у меня в голове кто-то поёт. Тихо так. Про унитазы.", en = "Also, someone's singing in my head. Real quiet. About toilets." }, { auto = true, glitch = 0.5 })
	c.say("Morty", { ru = "Чего?..", en = "What?.." }, { auto = 1 })
	Dialogue.hide()
	c.waitUntil(function()
		return reached >= 4
	end)
	c.say("Morty", { ru = "Рик, смотри! Дома! Какие-то древние...", en = "Rick, look! Houses! They look ancient..." }, { auto = true })
	Dialogue.hide()
	c.waitUntil(function()
		return reached >= 5
	end)
	api.objective(nil)
end

----------------------------------------------------------------------------
-- CHAPTER 6: The Titan
----------------------------------------------------------------------------
local TITAN_POSES = {
	stand = {},
	fly = {
		ShoulderL = CFrame.Angles(-0.35, 0, -0.3),
		ShoulderR = CFrame.Angles(-0.35, 0, 0.3),
		HipL = CFrame.Angles(-0.2, 0, 0),
		HipR = CFrame.Angles(-0.1, 0, 0),
		KneeL = CFrame.Angles(-0.5, 0, 0),
		KneeR = CFrame.Angles(-0.3, 0, 0),
		Waist = CFrame.Angles(-0.3, 0, 0),
	},
	land = {
		HipL = CFrame.Angles(0.9, 0, -0.12),
		HipR = CFrame.Angles(0.9, 0, 0.12),
		KneeL = CFrame.Angles(-1.5, 0, 0),
		KneeR = CFrame.Angles(-1.5, 0, 0),
		AnkleL = CFrame.Angles(0.6, 0, 0),
		AnkleR = CFrame.Angles(0.6, 0, 0),
		Waist = CFrame.Angles(-0.4, 0, 0),
		ShoulderL = CFrame.Angles(0.3, 0, -0.6),
		ShoulderR = CFrame.Angles(0.3, 0, 0.6),
		Neck = CFrame.Angles(0.25, 0, 0),
	},
	aim = {
		ShoulderR = CFrame.Angles(1.5, 0, 0.12),
		ElbowR = CFrame.Angles(0.08, 0, 0),
		ShoulderL = CFrame.Angles(0.35, 0, -0.35),
		Waist = CFrame.Angles(-0.08, -0.25, 0),
		HipL = CFrame.Angles(0.3, 0, -0.08),
		HipR = CFrame.Angles(-0.2, 0, 0.08),
		KneeL = CFrame.Angles(-0.4, 0, 0),
	},
	pods = {
		ShoulderL = CFrame.Angles(0.5, 0, -0.5),
		ShoulderR = CFrame.Angles(0.5, 0, 0.5),
		Waist = CFrame.Angles(0.12, 0, 0),
		Neck = CFrame.Angles(-0.15, 0, 0),
	},
	hit = {
		Waist = CFrame.Angles(0.4, 0.25, 0),
		ShoulderL = CFrame.Angles(-0.7, 0, -0.7),
		ShoulderR = CFrame.Angles(-0.5, 0, 0.8),
		Neck = CFrame.Angles(0.35, 0, 0),
		KneeL = CFrame.Angles(-0.3, 0, 0),
	},
	charge = {
		ShoulderL = CFrame.Angles(0.15, 0, -1.2),
		ShoulderR = CFrame.Angles(0.15, 0, 1.2),
		ElbowL = CFrame.Angles(0.6, 0, 0),
		ElbowR = CFrame.Angles(0.6, 0, 0),
		Waist = CFrame.Angles(0.2, 0, 0),
		Neck = CFrame.Angles(0.25, 0, 0),
		HipL = CFrame.Angles(0.25, 0, -0.18),
		HipR = CFrame.Angles(-0.25, 0, 0.18),
		KneeL = CFrame.Angles(-0.4, 0, 0),
		KneeR = CFrame.Angles(-0.2, 0, 0),
	},
	fire = {
		ShoulderL = CFrame.Angles(0.6, 0, -0.9),
		ShoulderR = CFrame.Angles(0.6, 0, 0.9),
		Waist = CFrame.Angles(-0.2, 0, 0),
		Neck = CFrame.Angles(-0.1, 0, 0),
		HipL = CFrame.Angles(0.35, 0, -0.18),
		HipR = CFrame.Angles(-0.35, 0, 0.18),
		KneeL = CFrame.Angles(-0.5, 0, 0),
	},
}

local ENTITY_POSES = {
	idle = {},
	raise = {
		ShoulderL = CFrame.Angles(2.4, 0, -0.4),
		ShoulderR = CFrame.Angles(2.4, 0, 0.4),
		ElbowL = CFrame.Angles(0.5, 0, 0),
		ElbowR = CFrame.Angles(0.5, 0, 0),
		Neck = CFrame.Angles(-0.3, 0, 0),
	},
	swing = {
		ShoulderR = CFrame.Angles(1.3, 0, 1.0),
		ElbowR = CFrame.Angles(0.8, 0, 0),
		ShoulderL = CFrame.Angles(0.4, 0, -0.5),
		Waist = CFrame.Angles(-0.25, 0.5, 0),
	},
	hit = {
		Waist = CFrame.Angles(0.35, -0.2, 0),
		Neck = CFrame.Angles(-0.45, 0, 0),
		ShoulderL = CFrame.Angles(0.9, 0, -0.9),
		ShoulderR = CFrame.Angles(0.9, 0, 0.9),
	},
}

local function titanPart(name: string): BasePart?
	return R.titanModel:FindFirstChild(name, true) :: BasePart?
end

local function titanJets(on: boolean)
	emitters(R.titanModel, "Jet", on)
	for _, d in R.titanModel:GetDescendants() do
		if d:IsA("PointLight") and d.Name == "JetLight" then
			d.Brightness = if on then 4 else 0
		end
	end
end

local function entityCloud(on: boolean)
	emitters(R.entityModel, "BlackCloud", on)
end

local function bigBlackSmoke(pos: Vector3, scale: number)
	Fx.smoke(pos, 6 * scale, 18, rgb(12, 10, 14), 6)
end

CH[6] = function(c, fresh: boolean)
	api.state("story")
	local rick = P.rick
	local V = R.village
	local mv = R.spots.MortyVillage.CFrame
	if fresh then
		Fx.black(1)
		ensureDesert(c)
		Scenes.apply("Desert", true)
		saucerTo(crashSite())
		emitters(R.saucer, "CrashSmoke", true)
		rick.follow = nil
		rick:place(R.spots.Path5.CFrame)
		rick:pose("stand")
		rick.glitch = 0.3
		holdCharacterAt(c, mv)
		Fx.fade(0, 1)
	end
	api.gameplay(false)
	api.freeze(true)
	api.hideCharacter(true)
	local eye = CFrame.new(mv.Position + Vector3.new(0, 1.92, 0)) * mv.Rotation
	Director.start()
	Director.move(eye, 1.4, "smooth", 70)
	Audio.music("MusicDread", 3)
	local rickSpot = mv.Position + mv.RightVector * 3.2 + mv.LookVector * 0.8
	task.spawn(function()
		rick:walkTo(Vector3.new(rickSpot.X, 3.36, rickSpot.Z), 6, mv.Position + mv.LookVector * 40)
	end)
	Fx.title("ch.6")
	c.check()
	Director.freeLook(true, { yaw = 1.3, pitchUp = 0.9, pitchDown = 0.5 })
	c.say("Rick", { ru = "Тут кто-то живёт, Морти. Дым из трубы. И следы свежие.", en = "Somebody lives here, Morty. Smoke from the chimney. Fresh footprints." }, { glitch = 0.15 })
	-- a shadow passes the lit window
	local houseA = V:FindFirstChild("HouseA")
	local win = houseA and houseA:FindFirstChild("Window2") :: BasePart?
	local shadow = V:FindFirstChild("WindowShadow") :: BasePart?
	if win and shadow then
		Director.freeLook(false)
		local winPos = win.Position
		Director.track(function()
			return CFrame.lookAt(eye.Position, winPos)
		end)
		c.wait(1.0)
		shadow.Transparency = 0
		animate(1.3, function(a)
			shadow.CFrame = win.CFrame * CFrame.new(-1.1 + 2.2 * a, -0.1, -0.35)
		end, "linear")
		shadow.Transparency = 1
		c.say("Morty", { ru = "Там кто-то был в окне!", en = "Someone was in that window!" })
		c.say("Rick", { ru = "Не до них сейчас.", en = "No time for them now." }, { glitch = 0.1 })
	end
	-- radar
	Director.track(function()
		return CFrame.lookAt(eye.Position, rick.root.Position + Vector3.new(0, 1.2, 0))
	end)
	rick:lookAt(nil)
	rick:pose("holdRadar", 8)
	Radar.holdProp(true)
	Audio.play("Servo", 1.6)
	c.wait(0.8)
	Radar.show(true)
	c.say("Rick", { ru = "Так... Угроза — максимальная. Прибудет через пять дней.", en = "Okay... Threat level: maximum. Arrival in five days." }, { glitch = 0.2 })
	c.say("Rick", { ru = "Пять дней, Морти. Нам нужно развиться и построить бункер, чтобы выжить.", en = "Five days, Morty. We have to level up and build a bunker to survive." }, { glitch = 0.2 })
	c.say("Morty", { ru = "Бункер?! Из чего, из песка?!", en = "A bunker?! Out of what, sand?!" })
	Dialogue.hide()
	Radar.show(false)
	Radar.holdProp(false)
	rick:pose("stand", 8)

	-- the sound... and Titan Speakerman 2.0
	Audio.music(nil, 1.5)
	local theme = Audio.make("TitanTheme", SoundService)
	if theme then
		theme:Play()
		table.insert(loops, theme)
	end
	Director.shake(0.35, 3.5, 6)
	c.wait(1.2)
	rick:lookAt(eye.Position + Vector3.new(0, 30, 0))
	c.say("Rick", { ru = "Морти... ты это слышишь?", en = "Morty... do you hear that?" }, { auto = 1.4 })
	Dialogue.hide()

	local titan = P.titan
	local landing = R.spots.TitanLanding.CFrame
	local entityHome = R.spots.EntityHome.CFrame
	local faceEntity = CFrame.lookAt(landing.Position, Vector3.new(entityHome.Position.X, 0, entityHome.Position.Z))
	local standRoot = faceEntity * CFrame.new(0, 30.4, 0)
	local left = -mv.RightVector
	local p0 = landing.Position + left * 170 + Vector3.new(0, 320, 0) - mv.LookVector * 40
	local p1 = landing.Position + left * 50 + Vector3.new(0, 170, 0)
	local p2 = standRoot.Position
	titan:pose(TITAN_POSES.fly, 6)
	titan:snap()
	titan.root.CFrame = CFrame.lookAt(p0, p1)
	titanJets(true)
	local thruster = Audio.make("Thruster", titan.root)
	if thruster then
		thruster:Play()
		table.insert(loops, thruster)
	end
	Director.track(function()
		return CFrame.lookAt(eye.Position, titan.root.Position + Vector3.new(0, 10, 0))
	end)
	Director.fov(62, 2)
	local prev = p0
	animate(5.2, function(a)
		local pos = bezier(p0, p1, p2 + Vector3.new(0, 12, 0), a)
		local dir = pos - prev
		prev = pos
		local look = if dir.Magnitude > 0.01 then dir.Unit else faceEntity.LookVector
		local flat = Vector3.new(look.X, look.Y * 0.4, look.Z)
		titan.root.CFrame = CFrame.lookAt(pos, pos + flat):Lerp(CFrame.new(pos) * faceEntity.Rotation, math.clamp((a - 0.75) * 4, 0, 1))
		if a > 0.82 then
			titan:pose(TITAN_POSES.land, 10)
		end
	end, "out")
	-- touchdown
	titanJets(false)
	stopLoop(thruster, 0.4)
	local crouch = faceEntity * CFrame.new(0, 30.4 - 7.2, 0)
	animate(0.25, function(a)
		titan.root.CFrame = (standRoot * CFrame.new(0, 12, 0)):Lerp(crouch, a)
	end, "in")
	play3D("RobotStomp", landing.Position)
	Audio.play("Boom", 0.9)
	Fx.dust(landing.Position, 34, 160)
	Fx.shockwave(landing.Position + Vector3.new(0, 2, 0), 46, 0.7, rgb(255, 210, 160))
	Director.shake(2.6, 1.4, 14)
	c.wait(1.0)
	play3D("Servo", titan.root.Position)
	titan:pose(TITAN_POSES.stand, 4)
	animate(1.4, function(a)
		titan.root.CFrame = crouch:Lerp(standRoot, a)
	end)
	play3D("RobotVoice", titan.root.Position + Vector3.new(0, 30, 0), 0.9)
	c.say("MortyThought", { ru = "Это... Титан Спикермен?!", en = "Is that... Titan Speakerman?!" }, { auto = 1.6 })
	Dialogue.hide()

	-- the black cloud and the entity
	Scenes.apply("DesertDark")
	local entity = P.entity
	entity:pose(ENTITY_POSES.idle, 3)
	entity.extra = function(t, _dt)
		local out = {
			Waist = CFrame.Angles(math.sin(t * 0.6) * 0.06, math.sin(t * 0.4) * 0.1, 0),
			ShoulderL = CFrame.Angles(math.sin(t * 0.9) * 0.15, 0, -0.1),
			ShoulderR = CFrame.Angles(math.sin(t * 0.8 + 1) * 0.15, 0, 0.1),
		}
		for ti = 1, 6 do
			for k = 1, 5 do
				out["T" .. ti .. "_" .. k] = CFrame.Angles(math.sin(t * 1.3 + ti + k * 0.6) * 0.28, 0, math.cos(t * 1.1 + ti * 2 + k * 0.5) * 0.22)
			end
		end
		return out
	end
	local below = entityHome * CFrame.new(0, -175, 0)
	entity.root.CFrame = below
	entityCloud(true)
	c.wait(1.2)
	Director.track(function()
		return CFrame.lookAt(eye.Position, entity.root.Position + Vector3.new(0, 70, 0))
	end)
	Director.fov(55, 3)
	play3D("RoarDeep", entityHome.Position, 0.6)
	Director.shake(1.0, 5, 6)
	animate(5, function(a)
		entity.root.CFrame = below:Lerp(entityHome, a)
	end, "out")
	play3D("Roar", entityHome.Position + Vector3.new(0, 100, 0), 0.7)
	c.say("Morty", { ru = "Что... ЭТО?!", en = "What... IS THAT?!" }, { auto = 1.2 })
	rick:lookAt(eye.Position)
	c.say("Rick", { ru = "Не смотри на него, Морти!", en = "Don't look at it, Morty!" }, { auto = 1.2, glitch = 0.4 })
	Dialogue.hide()

	-- FIGHT ------------------------------------------------------------------
	local chest = (R.entityModel:FindFirstChild("Chest", true) :: BasePart)
	Director.track(function()
		local mid = titan.root.Position:Lerp(entity.root.Position + Vector3.new(0, 60, 0), 0.45)
		return CFrame.lookAt(eye.Position, mid)
	end)
	Director.fov(62, 1)
	-- 1) sonic cannon volley
	titan.smooth = 14
	titan:pose(TITAN_POSES.aim)
	play3D("Charge", titan.root.Position)
	c.wait(0.8)
	local muzzle = titanPart("Muzzle")
	for i = 1, 5 do
		if muzzle then
			local origin = CFrame.lookAt(muzzle.Position, chest.Position)
			Fx.sonicRing(origin, (chest.Position - muzzle.Position).Magnitude, 0.45, 9, rgb(255, 90, 50))
			play3D("SonicBoom", muzzle.Position, 1 + i * 0.05)
		end
		Director.shake(0.5, 0.3)
		c.wait(0.45)
		local hitPos = chest.Position + Vector3.new(math.random(-12, 12), math.random(-10, 10), -16)
		Fx.explosion(hitPos, 3, { sound = "Explosion", smokeColor = rgb(14, 12, 16), waveColor = rgb(255, 120, 80) })
		entity:pose(ENTITY_POSES.hit, 10)
		c.wait(0.2)
	end
	entity:pose(ENTITY_POSES.idle, 4)
	play3D("Roar", chest.Position, 0.8)
	-- 2) the entity strikes back
	entity.smooth = 6
	entity:pose(ENTITY_POSES.swing)
	c.wait(0.7)
	titan:pose(TITAN_POSES.hit)
	local knock = standRoot * CFrame.new(0, 0, 14)
	task.spawn(animate, 0.4, function(a)
		titan.root.CFrame = standRoot:Lerp(knock, a)
	end, "out")
	Fx.sparks(titan.root.Position + Vector3.new(0, 14, 0), 80, rgb(255, 170, 120))
	Fx.explosion(titan.root.Position + Vector3.new(0, 14, 6), 2, { sound = "MetalCrash", smokeColor = rgb(14, 12, 16) })
	Director.shake(1.4, 0.8)
	c.wait(1.0)
	entity:pose(ENTITY_POSES.idle, 4)
	titan:pose(TITAN_POSES.stand, 6)
	task.spawn(animate, 0.8, function(a)
		titan.root.CFrame = knock:Lerp(standRoot, a)
	end)
	c.wait(0.9)
	-- 3) shoulder speakers
	titan:pose(TITAN_POSES.pods, 10)
	c.wait(0.4)
	for i = 1, 3 do
		for _, podName in { "PodL", "PodR" } do
			local pod = titanPart(podName)
			if pod then
				Fx.sonicRing(CFrame.lookAt(pod.Position, chest.Position), (chest.Position - pod.Position).Magnitude, 0.5, 11, rgb(255, 90, 50))
			end
		end
		play3D("SonicBoom", titan.root.Position + Vector3.new(0, 30, 0), 0.8)
		Director.shake(0.6, 0.3)
		c.wait(0.5)
		Fx.explosion(chest.Position + Vector3.new(math.random(-14, 14), math.random(-8, 14), -14), 3.5, { sound = "Explosion", smokeColor = rgb(14, 12, 16), waveColor = rgb(255, 120, 80) })
		bigBlackSmoke(chest.Position, 2)
		local _ = i
	end
	-- 4) the entity rises up and roars
	entity:pose(ENTITY_POSES.raise, 5)
	play3D("RoarDeep", chest.Position, 0.5)
	Director.shake(1.2, 2)
	c.wait(1.6)
	-- 5) core charge
	titan:pose(TITAN_POSES.charge, 6)
	local core = titanPart("Core")
	local coreLight = core and core:FindFirstChildOfClass("PointLight")
	local coreSize = if core then core.Size else Vector3.one
	play3D("ChargeLong", titan.root.Position, 0.9)
	animate(2.4, function(a)
		if coreLight then
			coreLight.Brightness = 2 + a * 14
			coreLight.Range = 40 + a * 20
		end
		if core then
			core.Size = coreSize * (1 + a * 0.5)
		end
		if math.random() < 0.3 and core then
			Fx.sparks(core.Position, 6, rgb(255, 170, 120))
		end
		Director.roll(math.sin(os.clock() * 30) * 0.004 * a)
	end, "in")
	Director.roll(0)
	-- 6) FIRE
	titan:pose(TITAN_POSES.fire, 12)
	play3D("Laser", titan.root.Position + Vector3.new(0, 20, 0))
	Fx.flash(rgb(255, 170, 140), 0.6, 0.05, 0.5)
	local beam = Fx.beam(if core then core.Position else titan.root.Position, chest.Position, 9, rgb(255, 80, 40))
	local firing = true
	task.spawn(function()
		while firing do
			beam.Set(if core then core.Position else titan.root.Position, chest.Position)
			Fx.sparks(chest.Position, 4, rgb(255, 170, 120))
			RunService.RenderStepped:Wait()
		end
		beam.Destroy()
	end)
	Director.shake(1.8, 1.6, 20)
	c.wait(1.4)
	firing = false
	Fx.explosion(chest.Position, 9, { sound = "ExplosionBig", smokeColor = rgb(10, 8, 12), waveColor = rgb(255, 230, 200), debris = 30 })
	bigBlackSmoke(chest.Position, 4)
	Fx.shockwave(chest.Position, 420, 1.4, rgb(255, 230, 200))
	Fx.dust(eye.Position - Vector3.new(0, 4, 0) + mv.LookVector * 60, 60, 160)
	if coreLight then
		coreLight.Brightness = 2
		coreLight.Range = 40
	end
	if core then
		core.Size = coreSize
	end
	entity:pose(ENTITY_POSES.hit, 8)
	c.wait(1.0)

	-- KNOCK-BACK (camera glitch like a Cameraman) ---------------------------
	Fx.flash(Color3.new(1, 1, 1), 1, 0.03, 1.2)
	Fx.glitch(4.5, 1)
	local static = loopSound("StaticLoop", camera())
	Fx.muffle(true)
	Audio.play("Tinnitus")
	Audio.play("BodyWhoosh")
	Director.freeLook(false)
	local back = -mv.LookVector
	local flyTo = CFrame.lookAt(eye.Position + back * 16 + Vector3.new(0, 5, 0), eye.Position + mv.LookVector * 30) * CFrame.Angles(0.6, 0.4, 1.6)
	local current = camera().CFrame
	Director.cut(current)
	Director.move(flyTo, 0.7, "out")
	c.check()
	local lyingPos = Vector3.new(eye.Position.X, 1.0, eye.Position.Z) + back * 22
	local lyingCF = CFrame.lookAt(lyingPos, lyingPos + mv.LookVector * 30 + Vector3.new(0, 14, 0)) * CFrame.Angles(0, 0, math.rad(78))
	Director.move(lyingCF, 0.35, "in")
	Audio.play("Thud")
	Fx.dust(lyingPos, 6, 30)
	Director.shake(1.6, 0.6)
	local blur = Lighting:FindFirstChild("Blur") :: BlurEffect?
	if blur then
		blur.Size = 12
		blur.Enabled = true
	end
	c.wait(1.8)
	-- Rick runs in and grabs Morty's hand
	local hatch = R.hatch
	setParts(hatch, { Transparency = 0, CanCollide = true })
	rick.follow = nil
	rick:pose("stand", 10)
	local rickNear = lyingPos + mv.LookVector * 3 + mv.RightVector * 1.5
	task.spawn(function()
		rick:walkTo(Vector3.new(rickNear.X, 3.36, rickNear.Z), 22, lyingPos)
	end)
	c.wait(1.4)
	rick:lookAt(lyingPos)
	c.say("Rick", { ru = "Морти! Вставай! Хватай меня за руку!", en = "Morty! Get up! Grab my hand!" }, { auto = 1.4, glitch = 0.35 })
	Dialogue.hide()
	stopLoop(static, 0.6)
	-- the drag to the bunker
	local hatchPos = (hatch:FindFirstChild("Lid") :: BasePart).Position
	rick:lookAt(nil)
	rick:pose("drag", 8)
	local dragging = true
	task.spawn(function()
		rick:walkTo(Vector3.new(hatchPos.X, 3.36, hatchPos.Z) + (Vector3.new(rickNear.X, 0, rickNear.Z) - Vector3.new(hatchPos.X, 0, hatchPos.Z)).Unit * 2, 6.5)
		dragging = false
	end)
	Director.track(function()
		local rr = rick.root.CFrame
		local behind = rr.Position - rr.LookVector * 3.4
		local camPos = Vector3.new(behind.X, 1.25 + math.abs(math.sin(os.clock() * 6)) * 0.25, behind.Z)
		return CFrame.lookAt(camPos, rr.Position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.sin(os.clock() * 3) * 0.08)
	end)
	if blur then
		task.spawn(function()
			animate(2, function(a)
				blur.Size = 12 - a * 8
			end)
		end)
	end
	task.spawn(function()
		while dragging and c.alive() do
			local rr = rick.root.CFrame
			local p = rr.Position + rr.LookVector * -(30 + math.random() * 40) + rr.RightVector * (math.random() - 0.5) * 60
			Fx.explosion(Vector3.new(p.X, 2, p.Z), 2 + math.random() * 2.5, { sound = "Explosion", smokeColor = rgb(14, 12, 16) })
			Director.shake(0.7, 0.4)
			task.wait(0.55 + math.random() * 0.4)
		end
	end)
	c.waitUntil(function()
		return not dragging
	end, 12)
	dragging = false
	Fx.fade(1, 0.4, true)
	if blur then
		blur.Enabled = false
		blur.Size = 0
	end
	Fx.stopGlitch()
	stopLoop(theme, 2)
	entityCloud(false)
end

----------------------------------------------------------------------------
-- public
----------------------------------------------------------------------------
function Story.init(a)
	api = a
	local house = api.house
	R.house = house
	R.seats = house:WaitForChild("Seats")
	R.phone = house:WaitForChild("Phone")
	R.doorModel = house:WaitForChild("Door")
	R.doorLeaf = R.doorModel:WaitForChild("Leaf")
	R.cast = workspace:WaitForChild("Cast")
	R.lab = workspace:WaitForChild("RickLab")
	R.garageSpots = R.lab:WaitForChild("GarageSpots")
	R.garage = workspace:WaitForChild("RickGarage")
	R.garageDoor = R.garage:WaitForChild("GarageDoor")
	R.saucer = workspace:WaitForChild("Saucer")
	R.saucerSpots = R.saucer:WaitForChild("Spots")
	R.planet = workspace:WaitForChild("Planet")
	R.spots = R.planet:WaitForChild("PlanetSpots")
	R.village = R.planet:WaitForChild("Village")
	R.bunker = R.planet:WaitForChild("Bunker")
	R.bunkerSpots = R.bunker:WaitForChild("BunkerSpots")
	R.hatch = R.bunker:WaitForChild("Hatch")
	R.bunkerRoom = R.bunker:WaitForChild("BunkerRoom")
	R.fight = R.planet:WaitForChild("Fight")
	R.titanModel = R.fight:WaitForChild("TitanSpeakerman")
	R.entityModel = R.fight:WaitForChild("Entity")
	R.hand = R.fight:WaitForChild("CurseHand")

	P.beth = Puppet.new(R.cast:WaitForChild("Beth"), "R6")
	P.jerry = Puppet.new(R.cast:WaitForChild("Jerry"), "R6")
	P.summer = Puppet.new(R.cast:WaitForChild("Summer"), "R6")
	P.rick = Puppet.new(R.cast:WaitForChild("Rick"), "R6")
	P.titan = Puppet.new(R.titanModel, "Rig")
	P.entity = Puppet.new(R.entityModel, "Rig")

	init.saucer = R.saucer:GetPivot()
	init.rick = P.rick.root.CFrame
	init.titan = P.titan.root.CFrame
	init.entity = P.entity.root.CFrame
	init.hand = R.hand:GetPivot()
	init.door = {}
	for _, d in R.doorLeaf:GetDescendants() do
		if d:IsA("BasePart") then
			init.door[d] = d.CFrame
		end
	end
	init.garageDoor = {}
	for _, d in R.garageDoor:GetDescendants() do
		if d:IsA("BasePart") then
			init.garageDoor[d] = d.CFrame
		end
	end
	familyAtBreakfast()
	P.rick:pose("stand")

	-- chapters 7-12 get the same tools
	StoryCurve.init({
		CH = CH,
		R = R,
		P = P,
		init = init,
		loops = loops,
		api = function()
			return api
		end,
		camera = camera,
		loopSound = loopSound,
		stopLoop = stopLoop,
		play3D = play3D,
		eyeFromHead = eyeFromHead,
		bezier = bezier,
		setParts = setParts,
		emitters = emitters,
		hingeRotate = hingeRotate,
		animate = animate,
		VM = VM,
		Radar = Radar,
		setDoor = setDoor,
		setGarageDoor = setGarageDoor,
		setPhoneOnNightstand = setPhoneOnNightstand,
		saucerTo = saucerTo,
		saucerThrust = saucerThrust,
		ensureDesert = ensureDesert,
		holdCharacterAt = holdCharacterAt,
		giveControl = giveControl,
		TITAN_POSES = TITAN_POSES,
		ENTITY_POSES = ENTITY_POSES,
		titanPart = titanPart,
		titanJets = titanJets,
		entityCloud = entityCloud,
		bigBlackSmoke = bigBlackSmoke,
	})

	-- puppets talk when their line is on screen
	Dialogue.setSpeakerCallback(function(who)
		for name, p in { Rick = P.rick, Beth = P.beth, Jerry = P.jerry, Summer = P.summer } do
			p.talking = (who == name)
		end
		StoryCurve.onSpeaker(who)
	end)
end

function Story.run(a, chapter: number)
	api = a
	runId += 1
	local id = runId
	local c = makeCtx(id)
	task.spawn(function()
		local ok, err = pcall(function()
			for ch = chapter, #CH do
				c.check()
				CH[ch](c, ch == chapter)
			end
		end)
		if not ok and err ~= CANCEL then
			warn("Story error:", err)
			-- don't leave the player stuck: go back to the menu
			if id == runId then
				Fx.fade(1, 0.5, true)
				api.toMenu()
			end
		end
	end)
end

function Story.stop()
	runId += 1
end

function Story.reset(_a)
	Director.stop()
	Dialogue.hide()
	Fx.clear()
	Fx.stopGlitch()
	Fx.speedLines(false)
	Fx.heat(0, 0)
	Fx.letterbox(false, 0)
	Fx.muffle(false)
	VM.setMode("hidden")
	VM.setHeat(0)
	Radar.show(false)
	Radar.holdProp(false)
	for _, s in loops do
		if s and s.Parent then
			s:Destroy()
		end
	end
	table.clear(loops)
	Audio.music(nil, 0.5)
	local blur = Lighting:FindFirstChild("Blur") :: BlurEffect?
	if blur then
		blur.Enabled = false
		blur.Size = 0
	end
	setPhoneOnNightstand(true)
	setDoor(false, true)
	setGarageDoor(false, true)
	saucerTo(init.saucer)
	saucerThrust(false)
	emitters(R.saucer, "CrashSmoke", false)
	for _, d in R.saucer:GetDescendants() do
		if d:IsA("Fire") then
			d.Enabled = false
		end
	end
	local rick = P.rick
	rick.follow = nil
	rick:place(init.rick)
	rick:pose("stand")
	rick.glitch = 0
	rick:lookAt(nil)
	rick:visible(true)
	familyAtBreakfast()
	P.titan.root.CFrame = init.titan
	P.titan:pose(TITAN_POSES.stand)
	titanJets(false)
	P.entity.root.CFrame = init.entity
	P.entity.extra = nil
	entityCloud(false)
	R.hand:PivotTo(init.hand)
	setParts(R.hand, { Transparency = 1 })
	setParts(R.hatch, { Transparency = 1, CanCollide = false })
	local shadow = R.village:FindFirstChild("WindowShadow") :: BasePart?
	if shadow then
		shadow.Transparency = 1
	end
	for _, lightName in { "KitchenSun", "KitchenLight", "BunkerEmergency", "SurgeryLight" } do
		Graphics.SetLight(lightName, false)
	end
	Scenes.setSpaceVisible(false)
	StoryCurve.reset()
	api.hideCharacter(true)
end

return Story
