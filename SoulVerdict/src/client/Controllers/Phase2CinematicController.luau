--!strict
-- Phase2CinematicController (client, Priority 66): the owner's Phase 2 transformation scenes. RoundService.StartCinematic
-- freezes the round (everyone Rooted + Silenced + Invulnerable, attacks cleared, timer paused) and sets RoundState
-- CinematicKit / CinematicCause / CinematicEndsAt; every round participant (and spectator) plays the kit's scene:
--   ClassicSans  smug close-up -> a SOUL's knife slash -> black screen "MISS" (he barely dodged) -> his eye flickers
--                blue / yellow while he shakes to the Phase 2 music -> white flash + screen stretch -> the fight goes on
--   FellSans     close-up -> BAM, the hit lands: he falls, blood on his belly, tired, no music -> two lines ("so this is
--                it?" / "not wasting my life on some little bug") -> he stands up, angry red eye -> flash + stretch
--   LastBreathSans  like Fell without blood: the hit cracks him, two last-breath lines, the eye ignites cyan
--   EclipseSans  only a short animation: purple eye pulse, dark vignette, rising shake -> flash + stretch
-- The HUD hides under letterbox bars; the camera uses CameraController's Intro path, then Follow again.
--
-- API
--   Phase2CinematicController.Timeline(kitId) -> { {t, name} }   pure: the scene's cues (tests)
--   Phase2CinematicController.Playing() -> boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any

local Phase2CinematicController = {}
Phase2CinematicController.Priority = 66

local CYAN = Color3.fromRGB(80, 220, 255)
local YELLOW = Color3.fromRGB(255, 230, 70)
local RED = Color3.fromRGB(255, 40, 50)
local PURPLE = Color3.fromRGB(170, 90, 255)

local TIMELINES: { [string]: { { number | string } } } = {
	ClassicSans = {
		{ 0.0, "Begin" }, { 0.0, "Silence" }, { 0.0, "Smug" }, { 0.9, "Slash" }, { 1.0, "Black" }, { 1.0, "Miss" },
		{ 2.2, "Unblack" }, { 2.2, "Music" }, { 2.3, "Flicker" }, { 2.3, "Shake" }, { 5.5, "Flash" }, { 6.2, "End" },
	},
	FellSans = {
		{ 0.0, "Begin" }, { 0.0, "Silence" }, { 0.0, "Smug" }, { 0.8, "Bam" }, { 0.9, "Fall" }, { 0.9, "Blood" },
		{ 1.6, "Tired" }, { 2.3, "Line1" }, { 4.6, "Line2" }, { 6.9, "Rise" }, { 6.9, "Angry" }, { 7.8, "Flash" },
		{ 7.8, "Music" }, { 9.0, "End" },
	},
	LastBreathSans = {
		{ 0.0, "Begin" }, { 0.0, "Silence" }, { 0.0, "Smug" }, { 0.8, "Bam" }, { 0.9, "Fall" }, { 1.6, "Tired" },
		{ 2.2, "Line1" }, { 4.4, "Line2" }, { 6.5, "Rise" }, { 6.5, "Ignite" }, { 7.3, "Flash" }, { 7.3, "Music" },
		{ 8.4, "End" },
	},
	LastBreathSans3 = {
		{ 0.0, "Begin" }, { 0.0, "Silence" }, { 0.0, "Smug" }, { 0.7, "Bam" }, { 0.8, "Fall" }, { 1.5, "Tired" },
		{ 2.0, "Line1" }, { 4.2, "Line2" }, { 6.3, "Rise" }, { 6.3, "Ignite" }, { 7.1, "Flash" }, { 7.1, "Music" },
		{ 8.2, "End" },
	},
	EclipseSans = {
		{ 0.0, "Begin" }, { 0.0, "Smug" }, { 0.2, "Pulse" }, { 0.2, "Vignette" }, { 1.2, "Shake" }, { 3.0, "Flash" },
		{ 3.8, "End" },
	},
}

local LINES: { [string]: { string } } = {
	FellSans = { "p2.fell.line1", "p2.fell.line2" },
	LastBreathSans = { "p2.lb.line1", "p2.lb.line2" },
	LastBreathSans3 = { "p3.lb.line1", "p3.lb.line2" },
}

function Phase2CinematicController.Timeline(kitId: string?): { { number | string } }
	return TIMELINES[kitId or ""] or TIMELINES.EclipseSans
end

local cache: { [string]: any } = {}
local function controller(name: string): any?
	if cache[name] ~= nil then
		return if cache[name] == false then nil else cache[name]
	end
	local module = script.Parent and script.Parent:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			cache[name] = result
			return result
		end
	end
	cache[name] = false
	return nil
end

local function call(name: string, method: string, ...: any): any
	local c = controller(name)
	if c and type(c[method]) == "function" then
		local ok, result = pcall(c[method], ...)
		if ok then
			return result
		end
	end
	return nil
end

local playing = false
local token = 0

function Phase2CinematicController.Playing(): boolean
	return playing
end

local function findMonster(): Model?
	for _, m in workspace:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Team") == "Monster" and m:FindFirstChildOfClass("Humanoid") then
			return m
		end
	end
	return nil
end

local function isLobbyViewer(): boolean
	local State = controller("StateController")
	if State and type(State.Role) == "function" then
		local ok, role = pcall(State.Role)
		return ok and role == "Lobby"
	end
	return false
end

-- overlay -----------------------------------------------------------------------------------------------
local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

local function buildOverlay(): any
	local gui = Instance.new("ScreenGui")
	gui.Name = "Phase2Cinematic"
	gui.IgnoreGuiInset = true
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	gui.DisplayOrder = 950
	gui.ResetOnSpawn = false
	local top = frame({ Name = "BarTop", BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 0), Parent = gui })
	local bottom = frame({ Name = "BarBottom", BackgroundColor3 = Color3.new(0, 0, 0), AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 0), Parent = gui })
	local black = frame({ Name = "Black", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local vignette = frame({ Name = "Vignette", BackgroundColor3 = Color3.fromRGB(20, 0, 40), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local white = frame({ Name = "White", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = gui })
	local slash = frame({ Name = "Slash", BackgroundColor3 = RED, Visible = false, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.4, 0, 0, 10), Rotation = -28, ZIndex = 4, Parent = gui })
	local miss = Instance.new("TextLabel")
	miss.Name = "Miss"
	miss.BackgroundTransparency = 1
	miss.Font = Enum.Font.Arcade
	miss.Text = "MISS"
	miss.TextColor3 = Color3.fromRGB(200, 200, 200)
	miss.TextScaled = true
	miss.AnchorPoint = Vector2.new(0.5, 0.5)
	miss.Position = UDim2.fromScale(0.5, 0.42)
	miss.Size = UDim2.fromScale(0.36, 0.14)
	miss.Visible = false
	miss.ZIndex = 6
	miss.Parent = gui
	local box = frame({ Name = "Dialogue", BackgroundColor3 = Color3.new(0, 0, 0), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0.7, 0, 0.2, 0), Visible = false, ZIndex = 7, Parent = gui })
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Parent = box
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Arcade
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Position = UDim2.new(0, 16, 0, 12)
	text.Size = UDim2.new(1, -32, 1, -24)
	text.Text = ""
	text.ZIndex = 8
	text.Parent = box
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = 30
	size.Parent = text
	return { Gui = gui, Top = top, Bottom = bottom, Black = black, Vignette = vignette, White = white, Slash = slash,
		Miss = miss, Box = box, Text = text }
end

-- the scene --------------------------------------------------------------------------------------------------
local function play(kitId: string, endsAt: number)
	token += 1
	local my = token
	local monster = findMonster()
	local now = workspace:GetServerTimeNow()
	local duration = math.clamp(endsAt - now, 0.5, 12)
	local timeline = Phase2CinematicController.Timeline(kitId)
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	playing = true
	local ui = buildOverlay()
	ui.Gui.Parent = playerGui
	call("UIController", "SetVisible", false)
	local started = os.clock()
	local fired: { [number]: boolean } = {}
	local typing: any = nil
	local flicker = false
	local pulse = false
	local blood: { BasePart } = {}
	local lineIndex = 0

	-- camera: a slow push-in on the monster's face
	if monster then
		local root = monster:FindFirstChild("HumanoidRootPart") :: BasePart?
		local head = monster:FindFirstChild("Head") :: BasePart?
		if root then
			local focus = (if head then head.Position else root.Position + Vector3.new(0, 3, 0))
			local look = root.CFrame.LookVector
			local a = CFrame.lookAt(focus + look * 10 + Vector3.new(0, 1.2, 0), focus)
			local b = CFrame.lookAt(focus + look * 6.5 + Vector3.new(0.8, 0.4, 0), focus)
			call("CameraController", "PlayIntro", { a, b }, duration, { Center = focus, Radius = 10 })
		end
	end

	local function say(key: string)
		ui.Box.Visible = true
		typing = { Text = Strings.L(key), Shown = 0, Next = os.clock() }
	end

	local function cue(name: string)
		if name == "Silence" then
			call("SoundController", "SetMusicOverride", "Silence", 0.3)
		elseif name == "Music" then
			call("SoundController", "SetMusicOverride", nil, 0.4)
		elseif name == "Smug" and monster then
			call("AnimController", "Play", monster, "IdleMenace", { Looped = true })
		elseif name == "Slash" then
			ui.Slash.Visible = true
			call("SoundController", "Play", "Slash", nil, { Force2D = true })
			task.delay(0.12, function()
				ui.Slash.Visible = false
			end)
		elseif name == "Black" then
			ui.Black.BackgroundTransparency = 0
			if monster then
				call("AnimController", "Play", monster, "Dodge")
			end
		elseif name == "Miss" then
			ui.Miss.Visible = true
			call("SoundController", "Play", "Miss", nil, { Force2D = true })
		elseif name == "Unblack" then
			ui.Miss.Visible = false
			ui.Black.BackgroundTransparency = 0.001
		elseif name == "Flicker" then
			flicker = true
		elseif name == "Shake" then
			call("FxController", "Shake", if kitId == "EclipseSans" then 0.35 else 0.5, 3)
		elseif name == "Bam" then
			ui.White.BackgroundTransparency = 0
			ui.Slash.Visible = true
			call("SoundController", "Play", "HitHeavy", nil, { Force2D = true })
			call("FxController", "Shake", 1.3, 0.45)
			task.delay(0.1, function()
				ui.Slash.Visible = false
			end)
		elseif name == "Fall" and monster then
			call("AnimController", "Stop", monster, "IdleMenace", 0.1)
			call("AnimController", "Play", monster, "Downed")
		elseif name == "Blood" and monster then
			local torso = monster:FindFirstChild("UpperTorso") or monster:FindFirstChild("Torso")
			if torso and torso:IsA("BasePart") then
				for i, spec in { { 0.9, 0.7, 0, 0 }, { 0.22, 0.5, 0.22, -0.5 }, { 0.16, 0.36, -0.28, -0.55 } } do
					local p = Instance.new("Part")
					p.Name = "Phase2Wound" .. i
					p.Anchored = false
					p.CanCollide = false
					p.CanQuery = false
					p.CanTouch = false
					p.Massless = true
					p.CastShadow = false
					p.Color = Color3.fromRGB(150, 0, 10)
					p.Material = Enum.Material.SmoothPlastic
					p.Size = Vector3.new(spec[1], spec[2], 0.06)
					p.CFrame = torso.CFrame * CFrame.new(spec[3], -0.25 + spec[4], -torso.Size.Z / 2 - 0.25)
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = torso
					weld.Part1 = p
					weld.Parent = p
					p.Parent = monster
					table.insert(blood, p)
				end
			end
		elseif name == "Tired" and monster then
			call("FxController", "EyeGlow", monster, "Left", nil, false)
			call("FxController", "EyeGlow", monster, "Right", nil, false)
		elseif name == "Line1" or name == "Line2" then
			lineIndex = if name == "Line1" then 1 else 2
			local keys = LINES[kitId]
			if keys and keys[lineIndex] then
				say(keys[lineIndex])
			end
		elseif name == "Rise" and monster then
			ui.Box.Visible = false
			call("AnimController", "Stop", monster, "Downed", 0.15)
			call("AnimController", "Play", monster, "IdleMenace", { Looped = true })
		elseif name == "Angry" and monster then
			call("FxController", "EyeGlow", monster, "Left", RED, true)
			call("FxController", "EyeGlow", monster, "Right", RED, true)
			call("FxController", "Shake", 0.7, 0.6)
		elseif name == "Ignite" and monster then
			call("FxController", "EyeGlow", monster, "Left", CYAN, true)
			call("FxController", "Shake", 0.7, 0.6)
		elseif name == "Pulse" then
			pulse = true
		elseif name == "Vignette" then
			ui.Vignette.BackgroundTransparency = 0.55
		elseif name == "Flash" then
			flicker, pulse = false, false
			ui.Box.Visible = false
			ui.Vignette.BackgroundTransparency = 1
			ui.White.BackgroundTransparency = 0
			call("CameraController", "Kick", 38, 0.55) -- the screen "stretches"
			call("SoundController", "Play", "FinalPhaseStinger", nil, { Force2D = true })
			if monster then
				call("FxController", "EyeGlow", monster, "Left", if kitId == "FellSans" then RED elseif kitId == "EclipseSans" then PURPLE else CYAN, true)
			end
		end
	end

	local conn: RBXScriptConnection? = nil
	local function finish()
		if my ~= token or not playing then
			return
		end
		playing = false
		if conn then
			conn:Disconnect()
		end
		ui.Gui:Destroy()
		call("UIController", "SetVisible", true)
		call("SoundController", "SetMusicOverride", nil, 0.5)
		call("CameraController", "SetMode", "Follow", { Blend = 0.4 })
		if monster then
			call("AnimController", "Stop", monster, "IdleMenace", 0.3)
			call("AnimController", "Stop", monster, "Downed", 0.3)
		end
	end

	conn = RunService.PreRender:Connect(function(dt: number)
		if my ~= token then
			return
		end
		local t = os.clock() - started
		for i, c in timeline do
			if not fired[i] and t >= (c[1] :: number) then
				fired[i] = true
				if c[2] == "End" then
					finish()
					return
				elseif c[2] == "Begin" then
					-- letterbox bars slide in below
				else
					local ok, err = pcall(cue, c[2] :: string)
					if not ok then
						warn("[Phase2Cinematic] " .. tostring(c[2]) .. ": " .. tostring(err))
					end
				end
			end
		end
		-- letterbox bars
		local bar = math.clamp(t / 0.35, 0, 1) * 0.11
		ui.Top.Size = UDim2.new(1, 0, bar, 0)
		ui.Bottom.Size = UDim2.new(1, 0, bar, 0)
		-- fades
		if ui.White.BackgroundTransparency < 1 then
			ui.White.BackgroundTransparency = math.min(1, ui.White.BackgroundTransparency + dt * 2.6)
		end
		if ui.Black.BackgroundTransparency > 0 and ui.Black.BackgroundTransparency < 1 then
			ui.Black.BackgroundTransparency = math.min(1, ui.Black.BackgroundTransparency + dt * 3.2)
		end
		if flicker and monster then
			local blue = math.floor(t / 0.12) % 2 == 0
			call("FxController", "EyeGlow", monster, "Left", if blue then CYAN else YELLOW, true)
		end
		if pulse and monster then
			call("FxController", "EyeGlow", monster, "Left", PURPLE, math.floor(t / 0.2) % 2 == 0)
		end
		if typing then
			local now2 = os.clock()
			local total = utf8.len(typing.Text) or #typing.Text
			while typing.Shown < total and now2 >= typing.Next do
				typing.Shown += 1
				typing.Next += 0.045
				local cut = utf8.offset(typing.Text, typing.Shown + 1)
				ui.Text.Text = "* " .. (if cut then string.sub(typing.Text, 1, cut - 1) else typing.Text)
				if typing.Shown % 2 == 1 then
					call("SoundController", "Play", "SansTextBlip", nil, { Force2D = true, Pitch = if kitId == "FellSans" then 0.85 else 1 })
				end
			end
		end
		if t > duration + 1 then
			finish()
		end
	end)
end

function Phase2CinematicController.Init() end

function Phase2CinematicController.Start()
	local roundState = ReplicatedStorage:FindFirstChild("RoundState") or ReplicatedStorage:WaitForChild("RoundState", 30)
	if roundState == nil then
		return
	end
	roundState:GetAttributeChangedSignal("CinematicKit"):Connect(function()
		local kit = roundState:GetAttribute("CinematicKit")
		if type(kit) == "string" and kit ~= "" and not isLobbyViewer() then
			local endsAt = roundState:GetAttribute("CinematicEndsAt")
			play(kit, if type(endsAt) == "number" then endsAt else workspace:GetServerTimeNow() + 5)
		end
	end)
end

return Phase2CinematicController
