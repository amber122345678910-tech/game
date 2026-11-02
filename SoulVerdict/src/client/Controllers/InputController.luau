--!strict
-- InputController (client, SPEC §20, Priority 5): one action vocabulary for keyboard/mouse, gamepad and touch.
-- Listens to UserInputService (never ContextActionService, so it never sinks input: default jumping/walking keep
-- working) and turns keys into actions with Begin/End states. Rebinding-ready: every mapping is data
-- (InputController.Bindings), reverse maps are rebuilt by SetBinding.
--
-- Actions: "M1","Q","E","R","T","F","G","Shift","Jump","Menu","Emote","CameraLock","Interact","Back","Confirm",
--          "Prev","Next" (Prev/Next = spectator cycling, never suppressed).
-- Input map (default):
--   action      keyboard/mouse          gamepad (Monster layout)        gamepad (Human layout)
--   M1          LMB                     RT                              RT
--   Q / E       Q / E                   X / Y                           X / Y
--   R           R                       B                               LT+RT (ultimate)
--   T           T                       D-pad up                        D-pad up
--   F           F (Verdict / Block)     LB (hold)                       LB (hold)
--   G           G (monster ultimate)    LT+RT                           -
--   Shift       Shift                   RB, LS                          B, RB, LS (dash)
--   Jump        Space (passthrough)     A (passthrough)                 A          | touch: JumpRequest
--   Menu        M, Tab                  View, Start                     View, Start
--   Emote       B                       D-pad down                      D-pad down
--   CameraLock  Ctrl, Alt               RS (click)                      RS
--   Interact    G (hint only: ProximityPrompts own the key; revive prompt = G / D-pad right)
--   Back        Backspace               B                               B
--   Confirm     Enter                   A                               A
--   Prev / Next Q / E                   D-pad left/right, X/Y, LB/RB    same
--   Touch: HUD buttons call BindTouchButton(action, button); camera drag/pinch is CameraController's.
-- Gamepad layout = local character's Team attribute ("Monster" -> Monster layout, anything else -> Human).
-- Ult chord: the ult fires when the SECOND of LT/RT goes down (RT first -> its M1 is ended first).
--
-- Filtering: input typed into a TextBox / the chat bar (ChatInputBarConfiguration.IsFocused) is ignored; other
-- gameProcessed input is ignored too, except the keys in InputController.Passthrough (Space, Tab, A, B: the default
-- PlayerModule / CoreGui bind them through ContextActionService, which marks them processed). End events are
-- always delivered (no stuck keys); focus loss / the Roblox menu release everything.
-- Contexts: PushContext/PopContext (counted). Contexts in SuppressingContexts ("Menu","Box","Dead","Photo",
-- "Cinematic","EmoteWheel") suppress CombatActions and release held ones; while the emote wheel is the ONLY
-- suppressing context its own key ("Emote") stays live so the same key closes it.
-- Cancel: Escape / right mouse button (even when the CoreGui processed the key) fire Cancelled("Escape" |
-- "MouseButton2"); ReleaseAll (Roblox menu, focus loss, gamepad disconnect) fires Cancelled("Release") BEFORE the
-- forced End events, so held aims / charges can cancel instead of firing (CombatController, Hud/EmoteWheel).
--
-- API
--   InputController.Action: Signal(action, state: "Begin"|"End", input: InputObject?)
--   InputController.Cancelled: Signal(source: "Escape"|"MouseButton2"|"Release")
--   InputController.On(action, fn(state, input?)) -> Connection         per-action convenience
--   InputController.IsDown(action) -> boolean
--   InputController.Device() -> "KeyboardMouse"|"Gamepad"|"Touch" ; DeviceChanged: Signal(device)
--   InputController.PushContext(name) / PopContext(name) ; HasContext(name) -> boolean ; ContextChanged: Signal(name, active)
--   InputController.CombatEnabled() -> boolean
--   InputController.KeyLabel(action, device?) -> string    "Q", "LMB", "LT+RT", "Shift"... ("" for touch)
--   InputController.KeyImage(action) -> string?           gamepad glyph (UserInputService:GetImageForKeyCode)
--   InputController.ActionName(action) -> string          localized ("Verdict Box" for a monster's F, ...)
--   InputController.BindTouchButton(action, button: GuiButton) -> () -> ()   returns unbind
--   InputController.Simulate(action, state)               programmatic Begin/End (HUD widgets, tests, tutorials)
--   InputController.Layout() -> "Monster"|"Human" ; IsTyping() -> boolean ; ReleaseAll()
--   InputController.SetBinding(device, layout?, action, tokens) ; BindingFor(action, device?, layout?) -> {string}
--   Pure (Lune-tested): ActionsForKey(device, layout, token) -> {string}, UltAction(team) -> "G"|"R",
--     LayoutForTeam(team) -> "Monster"|"Human", Bindings, Actions, CombatActions, SuppressingContexts, CHORD

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local Strings = require(Shared:WaitForChild("Strings"))

local InputController = {}
InputController.Priority = 5

export type Device = "KeyboardMouse" | "Gamepad" | "Touch"
export type Layout = "Monster" | "Human"
export type State = "Begin" | "End"

InputController.Action = Signal.new()
InputController.Cancelled = Signal.new()
InputController.DeviceChanged = Signal.new()
InputController.ContextChanged = Signal.new()

InputController.CHORD = "L2+R2"

InputController.Actions = {
	"M1",
	"Q",
	"E",
	"R",
	"T",
	"F",
	"G",
	"Shift",
	"Jump",
	"Menu",
	"Emote",
	"CameraLock",
	"Interact",
	"Back",
	"Confirm",
	"Prev",
	"Next",
}

-- suppressed by SuppressingContexts
InputController.CombatActions = {
	M1 = true,
	Q = true,
	E = true,
	R = true,
	T = true,
	F = true,
	G = true,
	Shift = true,
	Emote = true,
	Interact = true,
}

-- bound only for KeyLabel hints, never emitted from keys (ProximityPrompts own these keys)
InputController.HintOnly = { Interact = true }

InputController.SuppressingContexts =
	{ Menu = true, Box = true, Dead = true, Photo = true, Cinematic = true, EmoteWheel = true }

-- keys that fire Cancelled when pressed
InputController.CancelKeys = { Escape = true, MouseButton2 = true }

-- keys accepted even when gameProcessed (bound by default scripts through ContextActionService)
InputController.Passthrough = { Space = true, Tab = true, ButtonA = true, ButtonB = true }

local CHORD = InputController.CHORD

local function commonPad(): { [string]: { string } }
	return {
		M1 = { "ButtonR2" },
		Q = { "ButtonX" },
		E = { "ButtonY" },
		T = { "DPadUp" },
		F = { "ButtonL1" },
		Jump = { "ButtonA" },
		Menu = { "ButtonSelect" }, -- ButtonStart is reserved: it also opens the Roblox system menu
		Emote = { "DPadDown" },
		CameraLock = { "ButtonR3" },
		Interact = { "DPadRight" },
		Back = { "ButtonB" },
		Confirm = { "ButtonA" },
		Prev = { "DPadLeft", "ButtonX", "ButtonL1" },
		Next = { "DPadRight", "ButtonY", "ButtonR1" },
	}
end

local monsterPad = commonPad()
monsterPad.R = { "ButtonB" }
monsterPad.G = { CHORD }
monsterPad.Shift = { "ButtonR1", "ButtonL3" }

local humanPad = commonPad()
humanPad.R = { CHORD }
humanPad.G = {}
humanPad.Shift = { "ButtonB", "ButtonR1", "ButtonL3" }

InputController.Bindings = {
	KeyboardMouse = {
		M1 = { "MouseButton1" },
		Q = { "Q" },
		E = { "E" },
		R = { "R" },
		T = { "T" },
		F = { "F" },
		G = { "G" },
		Shift = { "LeftShift", "RightShift" },
		Jump = { "Space" },
		Menu = { "M" }, -- not Tab: Tab also toggles the Roblox player list
		Emote = { "B" },
		CameraLock = { "LeftControl", "LeftAlt", "RightControl" },
		Interact = { "G" },
		Back = { "Backspace" },
		Confirm = { "Return", "KeypadEnter" },
		Prev = { "Q" },
		Next = { "E" },
	} :: { [string]: { string } },
	Gamepad = {
		Monster = monsterPad,
		Human = humanPad,
	},
}

------------------------------------------------------------------------------------------------- pure

type ReverseMap = { [string]: { string } }

local EMPTY: { string } = table.freeze({})

local function buildReverse(map: { [string]: { string } }): ReverseMap
	local out: ReverseMap = {}
	-- deterministic order: follow InputController.Actions
	for _, action in InputController.Actions do
		if InputController.HintOnly[action] then
			continue
		end
		local tokens = map[action]
		if tokens then
			for _, token in tokens do
				local list = out[token]
				if list == nil then
					list = {}
					out[token] = list
				end
				if not table.find(list, action) then
					table.insert(list, action)
				end
			end
		end
	end
	return out
end

local reverse: { KeyboardMouse: ReverseMap, Monster: ReverseMap, Human: ReverseMap } = {
	KeyboardMouse = {},
	Monster = {},
	Human = {},
}

local function rebuild()
	reverse.KeyboardMouse = buildReverse(InputController.Bindings.KeyboardMouse)
	reverse.Monster = buildReverse(InputController.Bindings.Gamepad.Monster)
	reverse.Human = buildReverse(InputController.Bindings.Gamepad.Human)
end
rebuild()

function InputController.LayoutForTeam(team: string?): Layout
	return if team == "Monster" then "Monster" else "Human"
end

function InputController.UltAction(team: string?): string
	return if team == "Monster" then "G" else "R"
end

-- Actions a key produces (device "KeyboardMouse" ignores layout). Never allocates.
function InputController.ActionsForKey(device: string, layout: string?, token: string): { string }
	if device == "Gamepad" then
		local map = if layout == "Monster" then reverse.Monster else reverse.Human
		return map[token] or EMPTY
	elseif device == "KeyboardMouse" then
		return reverse.KeyboardMouse[token] or EMPTY
	end
	return EMPTY
end

function InputController.BindingFor(action: string, device: string?, layout: string?): { string }
	local dev = device or "KeyboardMouse"
	if dev == "Gamepad" then
		local pad = if layout == "Monster"
			then InputController.Bindings.Gamepad.Monster
			else InputController.Bindings.Gamepad.Human
		return pad[action] or EMPTY
	elseif dev == "KeyboardMouse" then
		return InputController.Bindings.KeyboardMouse[action] or EMPTY
	end
	return EMPTY
end

function InputController.SetBinding(device: string, layout: string?, action: string, tokens: { string })
	if device == "Gamepad" then
		local layouts = if layout then { layout } else { "Monster", "Human" }
		for _, l in layouts do
			local pad = (InputController.Bindings.Gamepad :: any)[l]
			if pad then
				pad[action] = table.clone(tokens)
			end
		end
	elseif device == "KeyboardMouse" then
		InputController.Bindings.KeyboardMouse[action] = table.clone(tokens)
	end
	rebuild()
end

-- The emote wheel suppresses combat but keeps its own toggle key alive when it is the only suppressing context.
local function wheelKeepsKey(action: string, suppressing: number, contexts: { [string]: number }): boolean
	return action == "Emote" and suppressing == 1 and (contexts.EmoteWheel or 0) > 0
end

function InputController.IsSuppressedBy(action: string, contexts: { [string]: number }): boolean
	if not InputController.CombatActions[action] then
		return false
	end
	local suppressing = 0
	for name, count in contexts do
		if count > 0 and InputController.SuppressingContexts[name] then
			suppressing += 1
		end
	end
	return suppressing > 0 and not wheelKeepsKey(action, suppressing, contexts)
end

------------------------------------------------------------------------------------------------ state

local device: Device = "KeyboardMouse"
local contexts: { [string]: number } = {}
local suppressCount = 0
local heldSources: { [string]: { [any]: boolean } } = {}
local heldCount: { [string]: number } = {}
local pressedBy: { [string]: { string } } = {} -- key token -> actions it began (for the matching End)
local perAction: { [string]: any } = {}
local chatBar: Instance? = nil
local started = false

-- gamepad trigger chord
local l2Down, r2Down = false, false
local chordAction: string? = nil
local touchJumpToken = 0

-------------------------------------------------------------------------------------------- lazy deps

local controllerCache: { [string]: any } = {}
local function controller(name: string): any?
	local cached = controllerCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local folder = script.Parent
	local module = folder and folder:FindFirstChild(name)
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

local function localTeam(): string?
	local State = controller("StateController")
	local character: Instance? = nil
	if State and type(State.LocalCharacter) == "function" then
		local ok, model = pcall(State.LocalCharacter)
		if ok then
			character = model
		end
	end
	if character == nil then
		local player = Players.LocalPlayer
		character = if player then player.Character else nil
	end
	if character then
		local team = character:GetAttribute("Team")
		if type(team) == "string" and team ~= "" then
			return team
		end
	end
	local player = Players.LocalPlayer
	if player and player:GetAttribute("Role") == "Monster" then
		return "Monster"
	end
	return nil
end

function InputController.Layout(): Layout
	return InputController.LayoutForTeam(localTeam())
end

----------------------------------------------------------------------------------------- core events

local function fire(action: string, state: State, input: InputObject?)
	InputController.Action:Fire(action, state, input)
	local signal = perAction[action]
	if signal then
		signal:Fire(state, input)
	end
end

local function suppressed(action: string): boolean
	return suppressCount > 0
		and InputController.CombatActions[action] == true
		and not wheelKeepsKey(action, suppressCount, contexts)
end

local function beginAction(action: string, source: any, input: InputObject?): boolean
	if suppressed(action) then
		return false
	end
	local set = heldSources[action]
	if set == nil then
		set = {}
		heldSources[action] = set
	end
	if set[source] then
		return false
	end
	set[source] = true
	local count = (heldCount[action] or 0) + 1
	heldCount[action] = count
	if count == 1 then
		fire(action, "Begin", input)
	end
	return true
end

local function endAction(action: string, source: any, input: InputObject?)
	local set = heldSources[action]
	if set == nil or not set[source] then
		return
	end
	set[source] = nil
	local count = (heldCount[action] or 1) - 1
	if count <= 0 then
		heldCount[action] = 0
		fire(action, "End", input)
	else
		heldCount[action] = count
	end
end

local function forceEnd(action: string)
	local set = heldSources[action]
	if set then
		table.clear(set)
	end
	if (heldCount[action] or 0) > 0 then
		heldCount[action] = 0
		fire(action, "End", nil)
	end
end

local function releaseCombat()
	for action in InputController.CombatActions do
		forceEnd(action)
	end
	chordAction = nil
end

function InputController.ReleaseAll()
	-- held aims / charges cancel first (their forced End must not fire them)
	InputController.Cancelled:Fire("Release")
	for _, action in InputController.Actions do
		forceEnd(action)
	end
	table.clear(pressedBy)
	chordAction = nil
	l2Down, r2Down = false, false
end

function InputController.IsTyping(): boolean
	if UserInputService:GetFocusedTextBox() ~= nil then
		return true
	end
	local bar = chatBar
	if bar ~= nil then
		local ok, focused = pcall(function()
			return (bar :: any).IsFocused
		end)
		if ok and focused == true then
			return true
		end
	end
	return false
end

local function isGamepadType(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function setDevice(newDevice: Device)
	if newDevice ~= device then
		device = newDevice
		InputController.DeviceChanged:Fire(newDevice)
	end
end

-- gamepad triggers: RT = M1, LT+RT = ult (whichever trigger goes down second completes the chord)
local function onTrigger(token: string, down: boolean, input: InputObject?)
	if token == "ButtonR2" then
		r2Down = down
	else
		l2Down = down
	end
	if down then
		if l2Down and r2Down then
			if chordAction == nil then
				endAction("M1", "ButtonR2", input)
				local ult = InputController.UltAction(localTeam())
				if beginAction(ult, "Chord", input) then
					chordAction = ult
				end
			end
		elseif token == "ButtonR2" then
			beginAction("M1", "ButtonR2", input)
		end
	else
		if chordAction ~= nil then
			endAction(chordAction, "Chord", input)
			chordAction = nil
		end
		if token == "ButtonR2" then
			endAction("M1", "ButtonR2", input)
		end
	end
end

local function tokenOf(input: InputObject): (string?, Device?)
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Keyboard then
		return input.KeyCode.Name, "KeyboardMouse"
	elseif
		inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
	then
		return inputType.Name, "KeyboardMouse"
	elseif isGamepadType(inputType) then
		return input.KeyCode.Name, "Gamepad"
	end
	return nil, nil
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	local token, inputDevice = tokenOf(input)
	if token == nil or inputDevice == nil then
		return
	end
	if InputController.CancelKeys[token] then
		InputController.Cancelled:Fire(token)
	end
	if InputController.IsTyping() or GuiService.MenuIsOpen then
		return
	end
	if gameProcessed and not InputController.Passthrough[token] then
		return
	end
	if inputDevice == "Gamepad" and (token == "ButtonR2" or token == "ButtonL2") then
		onTrigger(token, true, input)
		return
	end
	local layout = if inputDevice == "Gamepad" then InputController.Layout() else nil
	local actions = InputController.ActionsForKey(inputDevice, layout, token)
	if #actions == 0 then
		return
	end
	pressedBy[token] = actions
	for _, action in actions do
		beginAction(action, token, input)
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	local token, inputDevice = tokenOf(input)
	if token == nil then
		return
	end
	if inputDevice == "Gamepad" and (token == "ButtonR2" or token == "ButtonL2") then
		onTrigger(token, false, input)
		return
	end
	local actions = pressedBy[token]
	if actions == nil then
		return
	end
	pressedBy[token] = nil
	for _, action in actions do
		endAction(action, token, input)
	end
end

------------------------------------------------------------------------------------------- device

local function deviceFromPreferred(): Device?
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(value) == "EnumItem" then
		local name = (value :: EnumItem).Name
		if name == "Touch" then
			return "Touch"
		elseif name == "Gamepad" or name == "MicroGamepad" then
			return "Gamepad"
		end
		return "KeyboardMouse"
	end
	return nil
end

local function deviceFromInputType(inputType: Enum.UserInputType): Device?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif isGamepadType(inputType) then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "KeyboardMouse"
	end
	return nil
end

local function initialDevice(): Device
	local preferred = deviceFromPreferred()
	if preferred then
		return preferred
	end
	local okLast, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if okLast then
		local fromLast = deviceFromInputType(last)
		if fromLast then
			return fromLast
		end
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

------------------------------------------------------------------------------------------------ API

function InputController.On(action: string, fn: (State, InputObject?) -> ()): any
	local signal = perAction[action]
	if signal == nil then
		signal = Signal.new()
		perAction[action] = signal
	end
	return signal:Connect(fn)
end

function InputController.IsDown(action: string): boolean
	return (heldCount[action] or 0) > 0
end

function InputController.Device(): Device
	return device
end

function InputController.PushContext(name: string)
	local count = (contexts[name] or 0) + 1
	contexts[name] = count
	if count == 1 then
		if InputController.SuppressingContexts[name] then
			suppressCount += 1
			if suppressCount == 1 then
				releaseCombat()
			end
		end
		InputController.ContextChanged:Fire(name, true)
	end
end

function InputController.PopContext(name: string)
	local count = contexts[name]
	if count == nil then
		return
	end
	count -= 1
	if count <= 0 then
		contexts[name] = nil
		if InputController.SuppressingContexts[name] then
			suppressCount = math.max(0, suppressCount - 1)
		end
		InputController.ContextChanged:Fire(name, false)
	else
		contexts[name] = count
	end
end

function InputController.HasContext(name: string): boolean
	return (contexts[name] or 0) > 0
end

function InputController.Contexts(): { [string]: number }
	return table.clone(contexts)
end

function InputController.CombatEnabled(): boolean
	return suppressCount == 0
end

function InputController.Simulate(action: string, state: State)
	if state == "Begin" then
		beginAction(action, "Simulate", nil)
	else
		endAction(action, "Simulate", nil)
	end
end

local function keyLabelForToken(token: string, dev: string): string
	if token == CHORD then
		return Strings.L(
			"controls.chord",
			keyLabelForToken("ButtonL2", "Gamepad"),
			keyLabelForToken("ButtonR2", "Gamepad")
		)
	end
	if dev == "Gamepad" then
		local key = "controls.pad." .. token
		return if Strings.Has(key) then Strings.L(key) else token
	end
	local key = "controls.key." .. token
	if Strings.Has(key) then
		return Strings.L(key)
	end
	-- letters / digits: follow the user's keyboard layout (AZERTY shows "A" for KeyCode.Q)
	local ok, text = pcall(function()
		return UserInputService:GetStringForKeyCode((Enum.KeyCode :: any)[token])
	end)
	if ok and type(text) == "string" and text ~= "" and #text <= 3 then
		return string.upper(text)
	end
	return token
end

function InputController.KeyLabel(action: string, deviceOverride: string?): string
	local dev = deviceOverride or device
	if dev == "Touch" then
		return ""
	end
	local tokens = InputController.BindingFor(action, dev, InputController.Layout())
	local token = tokens[1]
	if token == nil then
		return ""
	end
	return keyLabelForToken(token, dev)
end

function InputController.KeyImage(action: string): string?
	local tokens = InputController.BindingFor(action, "Gamepad", InputController.Layout())
	local token = tokens[1]
	if token == nil then
		return nil
	end
	if token == CHORD then
		token = "ButtonR2"
	end
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode((Enum.KeyCode :: any)[token])
	end)
	if ok and image ~= nil then
		local text = tostring(image)
		if text ~= "" then
			return text
		end
	end
	return nil
end

function InputController.ActionName(action: string): string
	local layoutKey = "controls.action." .. action .. "." .. string.lower(InputController.Layout())
	if Strings.Has(layoutKey) then
		return Strings.L(layoutKey)
	end
	return Strings.L("controls.action." .. action)
end

function InputController.BindTouchButton(action: string, button: GuiButton): () -> ()
	local trove = Trove.new()
	local activeInput: InputObject? = nil
	local function release(input: InputObject?)
		if activeInput ~= nil then
			activeInput = nil
			endAction(action, button, input)
		end
	end
	trove:Connect(button.InputBegan, function(input: InputObject)
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.Touch and inputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if input.UserInputState ~= Enum.UserInputState.Begin or activeInput ~= nil then
			return
		end
		if beginAction(action, button, input) then
			activeInput = input
		end
	end)
	local function onEnded(input: InputObject)
		local current = activeInput
		if current == nil then
			return
		end
		-- touches keep one InputObject for their whole life; a mouse click may end on a different object
		local sameMouse = current.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if input == current or sameMouse then
			release(input)
		end
	end
	trove:Connect(button.InputEnded, onEnded)
	trove:Connect(UserInputService.InputEnded, onEnded)
	trove:Connect(button.Destroying, function()
		release(nil)
	end)
	trove:Add(function()
		release(nil)
	end)
	return function()
		trove:Destroy()
	end
end

---------------------------------------------------------------------------------------------- lifecycle

function InputController.Init()
	device = initialDevice()
end

local function hookChatBar()
	local function check(child: Instance)
		if child:IsA("ChatInputBarConfiguration") then
			chatBar = child
		end
	end
	local ok = pcall(function()
		for _, child in TextChatService:GetChildren() do
			check(child)
		end
		TextChatService.ChildAdded:Connect(check)
	end)
	if not ok then
		chatBar = nil
	end
end

function InputController.Start()
	if started then
		return
	end
	started = true
	hookChatBar()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- touch jump button / any jump request on touch devices -> "Jump" (keyboard/gamepad use their keys)
	UserInputService.JumpRequest:Connect(function()
		if device ~= "Touch" or InputController.IsTyping() then
			return
		end
		touchJumpToken += 1
		local token = touchJumpToken
		beginAction("Jump", "JumpRequest", nil)
		-- JumpRequest can fire several times per tap: merge bursts, but keep fast double taps apart
		task.delay(0.08, function()
			if touchJumpToken == token then
				endAction("Jump", "JumpRequest", nil)
			end
		end)
	end)

	UserInputService.WindowFocusReleased:Connect(InputController.ReleaseAll)
	pcall(function()
		GuiService.MenuOpened:Connect(InputController.ReleaseAll)
	end)

	local preferredOk = pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			local preferred = deviceFromPreferred()
			if preferred then
				setDevice(preferred)
			end
		end)
	end)
	if not preferredOk or deviceFromPreferred() == nil then
		UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			local fromType = deviceFromInputType(inputType)
			if fromType then
				setDevice(fromType)
			end
		end)
	end
	-- a gamepad disconnecting mid-press must not leave triggers held
	UserInputService.GamepadDisconnected:Connect(function()
		InputController.ReleaseAll()
	end)
end

return InputController
