--!strict
-- Hud/EmoteWheel: radial emote menu. B / D-pad down (InputController action "Emote") toggles it; on touch devices a
-- round toggle button sits on the right edge under the camera-lock button. Slots (slot 1 at the top, clockwise):
-- Config.Emote.Common + Config.Emote.Family[<kit Family>] - Wave, Shrug, Sit, Laugh, Taunt, Cheer (+ Wink for the
-- skeleton family). Pick with the mouse (hover + click), the number keys 1-9, the right stick or D-pad left/right
-- (then the Emote key again to play), or a tap; Esc / right-click (InputController.Cancelled), B / Backspace
-- ("Back"), the Emote key with nothing highlighted, or a click / tap outside close it. Picking sends Request
-- "Emote" {clip}; EmoteService (server) validates it and sets the character attribute "Emote" that AnimController
-- plays. While open the input context "EmoteWheel" suppresses combat input and frees the mouse cursor (the Emote key
-- itself stays live so it can close the wheel).
--   EmoteWheel.Create(theme, deps) -> { Root, Update(snapshot), SetActive(on), Open(), Close(), IsOpen(), Pick(i),
--       Destroy }     deps (HUD deps): Live, Input, State, Sound, Layout, Skin/Hud; deps.Open = true builds it open
--       (previews), deps.Family overrides the slot family.
-- Pure (Lune-tested): EmoteWheel.Options(family?) -> {{Clip, Label, Icon}},
--   EmoteWheel.SlotPosition(i, n, radius) -> Vector2 (GUI offset from the centre, +Y down),
--   EmoteWheel.SlotAt(dir: Vector2 (+Y down), n, deadZone?) -> index?, EmoteWheel.Size(layout) -> number (diameter)
local Style = require(script.Parent.Style)

local EmoteWheel = {}

local TAU = math.pi * 2
local ICONS: { [string]: string } = {
	Emote_Wave = "Wave",
	Emote_Shrug = "Info",
	Emote_Sit = "Moon",
	Emote_Laugh = "Sparkle",
	Taunt = "Fist",
	Victory = "Trophy",
	Wink = "Eye",
}
local NUMBER_KEYS = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
local FALLBACK_COMMON = { "Emote_Wave", "Emote_Shrug", "Emote_Sit", "Emote_Laugh" }

---------------------------------------------------------------------------------------------------
-- Pure helpers

function EmoteWheel.Options(family: string?): { { Clip: string, Label: string, Icon: string } }
	local config = Style.Config()
	local e = if config and type(config.Emote) == "table" then config.Emote else {}
	local clips: { string } = {}
	for _, clip in e.Common or FALLBACK_COMMON do
		table.insert(clips, clip)
	end
	local extras = if type(family) == "string" and type(e.Family) == "table" then e.Family[family] else nil
	for _, clip in extras or {} do
		if not table.find(clips, clip) then
			table.insert(clips, clip)
		end
	end
	local out = {}
	for _, clip in clips do
		table.insert(out, { Clip = clip, Label = Style.L("hud.emote." .. clip), Icon = ICONS[clip] or "Star" })
	end
	return out
end

-- Slot i of n (1 = top, clockwise) as an offset from the wheel centre in GUI space (+Y down).
function EmoteWheel.SlotPosition(i: number, n: number, radius: number): Vector2
	local a = (i - 1) / math.max(1, n) * TAU
	return Vector2.new(math.sin(a) * radius, -math.cos(a) * radius)
end

-- The slot a direction points at (GUI space, +Y down: a stick pushed up is (0, -1)); nil inside the dead zone.
function EmoteWheel.SlotAt(dir: Vector2, n: number, deadZone: number?): number?
	if n <= 0 or dir.Magnitude < (deadZone or 0.35) then
		return nil
	end
	local a = math.atan2(dir.X, -dir.Y) -- 0 = up, clockwise positive
	if a < 0 then
		a += TAU
	end
	return (math.floor(a / (TAU / n) + 0.5) % n) + 1
end

-- Wheel diameter in HUD canvas px (bigger share of the screen on phones: thumb-sized slots).
function EmoteWheel.Size(layout: any): number
	local canvas: Vector2 = layout.Canvas
	if layout.Phone then
		return math.floor(canvas.Y * 0.8)
	end
	return math.floor(math.clamp(canvas.Y * 0.6, 300, 560))
end

---------------------------------------------------------------------------------------------------

local function service(name: string): any
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	return if ok then s else nil
end

function EmoteWheel.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "EmoteWheel")
	local C = skin.C
	local battle = skin.Battle
	local d = if type(deps) == "table" then deps else {}
	local live = d.Live == true
	local canvas: Vector2 = layout.Canvas
	local phone = layout.Phone == true
	local D = EmoteWheel.Size(layout)
	local slotSize = math.floor(D * 0.23)
	local ringRadius = math.floor(D * 0.37)
	local hubSize = math.floor(D * (if skin.Battle then 0.27 else 0.34)) -- square battle hub must clear the slots
	local accent = if battle then Style.UT_YELLOW else (C.Accent or Style.WHITE)

	local isOpen = false
	local active = true
	local destroyed = false
	local contextPushed = false
	local family: string? = if type(d.Family) == "string" then d.Family else nil
	local device: string = "KeyboardMouse"
	local options: { { Clip: string, Label: string, Icon: string } } = {}
	type Slot = {
		Root: GuiObject,
		Scale: UIScale,
		Label: TextLabel,
		Stroke: UIStroke?,
		StrokeColor: Color3,
		StrokeT: number,
	}
	local slots: { Slot } = {}
	local highlighted: number? = nil
	local conns: { any } = {}
	local pick: (index: number) -> () -- defined below; slot buttons call it

	-- dim backdrop: a click / tap outside the slots closes the wheel
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Style.BLACK
	dim.BackgroundTransparency = 0.55
	dim.Size = UDim2.fromScale(1, 1)
	dim.Visible = false
	dim.ZIndex = 1
	dim.Parent = root
	Style.Vignette({ Name = "Edge", Color = Style.BLACK, Strength = 0.6, ZIndex = 1 }).Parent = dim

	local wheel = Style.Frame({
		Name = "Wheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(D, D),
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	local wheelScale = Instance.new("UIScale")
	wheelScale.Parent = wheel

	-- ring behind the slots: a round glass disc (Modern); the battle style keeps plain boxes on black
	if not battle then
		local disc = Style.Box(skin, {
			Name = "Disc",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(ringRadius * 2 + slotSize, ringRadius * 2 + slotSize),
			Corner = UDim.new(0.5, 0),
			Transparency = 0.45,
			Sheen = false,
			ZIndex = 2,
			Parent = wheel,
		})
		local _ = disc
	end

	-- hub: title + the highlighted emote
	local hub = Style.Box(skin, {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(hubSize, hubSize),
		Corner = UDim.new(0.5, 0),
		Transparency = if battle then 0 else 0.25,
		Sheen = false, -- a half-height sheen pokes out of a round box
		ZIndex = 3,
		Parent = wheel,
	})
	local hubTitle = Style.Text(skin, {
		Name = "Title",
		Text = Style.L("hud.emote.title"),
		TextSize = if battle then 10 else 12,
		Color = C.Dim,
		X = "Center",
		Stroke = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -math.floor(hubSize * 0.17)),
		Size = UDim2.new(1, -12, 0, 16),
		ZIndex = 4,
		Parent = hub,
	})
	local hubName = Style.Text(skin, {
		Name = "Current",
		Text = "",
		Role = "Title",
		TextSize = if phone then 16 else (if battle then 18 else 22),
		Color = accent,
		X = "Center",
		Scaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, math.floor(hubSize * 0.06)),
		Size = UDim2.new(1, -14, 0, 26),
		ZIndex = 4,
		Parent = hub,
	})
	local hint = Style.Text(skin, {
		Name = "Hint",
		Text = "",
		TextSize = if phone then 11 else 13,
		Color = C.Text,
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, if phone then 2 else 14),
		Size = UDim2.new(0, D + 160, 0, 18),
		ZIndex = 4,
		Parent = wheel,
	})
	local _ = hubTitle

	-- touch toggle under the camera-lock button (MobileControls: canvas.X - 40, canvas.Y * 0.27)
	local toggle = Instance.new("TextButton")
	toggle.Name = "EmoteToggle"
	toggle.Text = ""
	toggle.AutoButtonColor = false
	toggle.BorderSizePixel = 0
	toggle.BackgroundColor3 = if battle then Style.BLACK else (C.Fill or Style.BLACK)
	toggle.BackgroundTransparency = if battle then 0 else 0.25
	toggle.AnchorPoint = Vector2.new(0.5, 0.5)
	toggle.Position = UDim2.fromOffset(canvas.X - 40, math.floor(canvas.Y * 0.27) + 58)
	toggle.Size = UDim2.fromOffset(46, 46)
	toggle.Visible = false
	toggle.ZIndex = 2
	toggle.Parent = root
	if battle then
		Style.Stroke(toggle, Style.WHITE, 2, 0, true)
	else
		Style.Corner(toggle, UDim.new(0.5, 0))
		Style.Stroke(toggle, Style.WHITE, 1.5, 0.5)
	end
	local toggleIcon = Style.Icon("Wave", Style.WHITE, 24)
	toggleIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	toggleIcon.Position = UDim2.fromScale(0.5, 0.42)
	toggleIcon.ZIndex = 3
	toggleIcon.Parent = toggle
	Style.Text(skin, {
		Name = "Label",
		Text = Style.L("hud.emote.button"),
		TextSize = 8,
		X = "Center",
		Stroke = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 10),
		ZIndex = 3,
		Parent = toggle,
	})

	---------------------------------------------------------------------------------------------
	-- behaviour

	local function input(): any?
		local i = d.Input
		return if live and type(i) == "table" then i else nil
	end

	local function sound(name: string)
		local s = d.Sound
		if live and type(s) == "table" and type(s.Play) == "function" then
			pcall(s.Play, name, nil, { Volume = 0.6 })
		end
	end

	local function setContext(on: boolean)
		local i = input()
		if i == nil or on == contextPushed then
			return
		end
		contextPushed = on
		pcall(if on then i.PushContext else i.PopContext, "EmoteWheel")
	end

	local function setHighlight(index: number?)
		if index ~= nil and (index < 1 or index > #slots) then
			index = nil
		end
		if index == highlighted then
			return
		end
		local old = if highlighted then slots[highlighted] else nil
		if old then
			old.Scale.Scale = 1
			old.Label.TextColor3 = C.Text
			if old.Stroke then
				old.Stroke.Color = old.StrokeColor
				old.Stroke.Transparency = old.StrokeT
			end
		end
		highlighted = index
		local slot = if index then slots[index] else nil
		if slot and index then
			Style.Tween(slot.Scale, 0.08, { Scale = 1.1 })
			slot.Label.TextColor3 = accent
			if slot.Stroke then
				slot.Stroke.Color = accent
				slot.Stroke.Transparency = 0
			end
			Style.SetText(hubName, Style.Upper(skin, options[index].Label))
			if isOpen then
				sound("UiHover")
			end
		else
			Style.SetText(hubName, "")
		end
	end

	local function buildSlots()
		for _, s in slots do
			s.Root:Destroy()
		end
		table.clear(slots)
		highlighted = nil
		options = EmoteWheel.Options(family)
		local n = #options
		for i, option in options do
			local p = EmoteWheel.SlotPosition(i, n, ringRadius)
			local button = Instance.new("TextButton")
			button.Name = "Slot" .. i
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundTransparency = 1
			button.BorderSizePixel = 0
			button.AnchorPoint = Vector2.new(0.5, 0.5)
			button.Position = UDim2.new(0.5, p.X, 0.5, p.Y)
			button.Size = UDim2.fromOffset(slotSize, slotSize)
			button.ZIndex = 5
			local scale = Instance.new("UIScale")
			scale.Parent = button
			local box = Style.Box(skin, {
				Name = "Face",
				Size = UDim2.fromScale(1, 1),
				Corner = UDim.new(0.5, 0),
				Transparency = if battle then 0 else 0.15,
				Sheen = false,
				ZIndex = 5,
				Parent = button,
			})
			local stroke = box:FindFirstChildOfClass("UIStroke")
			local iconSize = math.floor(slotSize * 0.42)
			local icon = Style.Icon(option.Icon, Style.WHITE, iconSize)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.4)
			icon.ZIndex = 6
			icon.Parent = button
			local label = Style.Text(skin, {
				Name = "Label",
				Text = option.Label,
				TextSize = if phone then 11 else (if battle then 11 else 13),
				X = "Center",
				Scaled = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.78),
				Size = UDim2.new(0.86, 0, 0, if phone then 13 else 16),
				ZIndex = 6,
				Parent = button,
			})
			if not phone and i <= #NUMBER_KEYS then
				local key = Style.KeyCap(skin, tostring(i), 18)
				key.AnchorPoint = Vector2.new(0.5, 0.5)
				key.Position = UDim2.new(0.5, 0, 0, 2)
				key.ZIndex = 7
				key.Parent = button
			end
			button.Parent = wheel
			local index = i
			if live then
				table.insert(
					conns,
					button.MouseEnter:Connect(function()
						setHighlight(index)
					end)
				)
				table.insert(
					conns,
					button.Activated:Connect(function()
						pick(index)
					end)
				)
			end
			table.insert(slots, {
				Root = button,
				Scale = scale,
				Label = label,
				Stroke = stroke,
				StrokeColor = if stroke then stroke.Color else Style.WHITE,
				StrokeT = if stroke then stroke.Transparency else 0,
			})
		end
	end

	local function updateHint()
		local i = input()
		local key = "B"
		if i and type(i.KeyLabel) == "function" then
			local ok, label = pcall(i.KeyLabel, "Emote", device)
			if ok and type(label) == "string" and label ~= "" then
				key = label
			end
		end
		local text = if device == "Touch"
			then Style.L("hud.emote.hint.Touch")
			elseif device == "Gamepad" then Style.L("hud.emote.hint.Gamepad", key)
			else Style.L("hud.emote.hint.KeyboardMouse", math.min(#options, #NUMBER_KEYS), key)
		Style.SetText(hint, Style.Upper(skin, text))
	end

	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		setHighlight(nil)
		wheel.Visible = false
		dim.Visible = false
		setContext(false)
	end

	local function open()
		if isOpen or destroyed or not active then
			return
		end
		isOpen = true
		buildSlots()
		updateHint()
		wheel.Visible = true
		dim.Visible = true
		wheelScale.Scale = 0.86
		Style.Tween(wheelScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
		setContext(true)
		sound("UiOpen")
	end

	local function send(clip: string)
		local state = d.State
		if type(state) == "table" and type(state.Request) == "function" then
			pcall(state.Request, "Emote", { clip = clip })
			return
		end
		pcall(function()
			local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
			local Net = require(Shared:WaitForChild("Net")) :: any
			Net.Client.Fire("Request", "Emote", { clip = clip })
		end)
	end

	pick = function(index: number)
		local option = options[index]
		if not isOpen or option == nil then
			return
		end
		if live then
			send(option.Clip)
		end
		sound("UiConfirm")
		close()
	end

	local function onEmoteKey()
		if not isOpen then
			open()
		elseif device == "Gamepad" and highlighted then
			pick(highlighted :: number)
		else
			close()
		end
	end

	local function rotate(step: number)
		if not isOpen or #slots == 0 then
			return
		end
		local current = highlighted or (if step > 0 then 0 else 1)
		setHighlight(((current - 1 + step) % #slots) + 1)
	end

	-- live wiring ---------------------------------------------------------------------------------
	local i = input()
	if i then
		if type(i.On) == "function" then
			local function on(action: string, fn: () -> ())
				local ok, conn = pcall(i.On, action, function(state: string)
					if state == "Begin" and active and not destroyed then
						fn()
					end
				end)
				if ok and conn then
					table.insert(conns, conn)
				end
			end
			on("Emote", onEmoteKey)
			on("Back", close)
			on("Prev", function()
				rotate(-1)
			end)
			on("Next", function()
				rotate(1)
			end)
		end
		if i.Cancelled and type(i.Cancelled.Connect) == "function" then
			table.insert(conns, i.Cancelled:Connect(close))
		end
		if i.ContextChanged and type(i.ContextChanged.Connect) == "function" then
			-- a menu / the Verdict Box / death taking over input closes the wheel
			table.insert(
				conns,
				i.ContextChanged:Connect(function(name: string, on: boolean)
					local suppressing = type(i.SuppressingContexts) == "table" and i.SuppressingContexts[name]
					if on and name ~= "EmoteWheel" and suppressing then
						close()
					end
				end)
			)
		end
	end
	if live then
		table.insert(
			conns,
			dim.Activated:Connect(function()
				close()
			end)
		)
		table.insert(
			conns,
			toggle.Activated:Connect(function()
				if isOpen then
					close()
				else
					open()
				end
			end)
		)
		local UserInputService = service("UserInputService")
		if UserInputService then
			table.insert(
				conns,
				UserInputService.InputBegan:Connect(function(inputObject: InputObject)
					if not isOpen or inputObject.UserInputType ~= Enum.UserInputType.Keyboard then
						return
					end
					local n = table.find(NUMBER_KEYS, inputObject.KeyCode.Name)
					if n and n <= #slots then
						setHighlight(n)
						pick(n)
					end
				end)
			)
			table.insert(
				conns,
				UserInputService.InputChanged:Connect(function(inputObject: InputObject)
					if isOpen and inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
						local p = inputObject.Position
						local n = EmoteWheel.SlotAt(Vector2.new(p.X, -p.Y), #slots, 0.5)
						if n then
							setHighlight(n)
						end
					end
				end)
			)
		end
	end

	---------------------------------------------------------------------------------------------
	-- snapshot

	local function update(s: { [string]: any })
		local me = s.Me
		local newDevice = if type(s.Device) == "string" then s.Device else device
		local i2 = input()
		if i2 and type(i2.Device) == "function" then
			local ok, dev = pcall(i2.Device)
			if ok and type(dev) == "string" then
				newDevice = dev
			end
		end
		if newDevice ~= device then
			device = newDevice
			if isOpen then
				updateHint()
			end
		end
		if type(d.Family) ~= "string" then
			local kit = if me then Style.Kit(me.KitId) else nil
			local newFamily = if kit and type(kit.Family) == "string" then kit.Family else nil
			if newFamily ~= family then
				family = newFamily
				if isOpen then
					buildSlots()
				end
			end
		end
		local alive = me ~= nil and me.Dead ~= true and s.Dead ~= true
		if not alive then
			close()
		end
		toggle.Visible = device == "Touch" and alive
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	if d.Open == true then
		open()
		setHighlight(1)
	end

	return {
		Root = root,
		Update = update,
		Open = open,
		Close = close,
		IsOpen = function(): boolean
			return isOpen
		end,
		Pick = pick,
		SetActive = function(on: boolean)
			active = on
			if not on then
				close()
			end
		end,
		Destroy = function()
			if destroyed then
				return
			end
			close()
			destroyed = true
			for _, conn in conns do
				pcall(function()
					conn:Disconnect()
				end)
			end
			table.clear(conns)
			root:Destroy()
		end,
	}
end

return EmoteWheel
