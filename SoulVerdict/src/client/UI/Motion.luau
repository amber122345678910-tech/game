--!strict
-- Motion: UI animation + event helpers. Lune-safe: every function is a safe no-op until Motion.Enable()
-- is called (UIRoot.Init does that at runtime). While disabled, tweens apply their END values
-- immediately, so offline previews (tools/lune/dump_gui.luau) show the final, settled state.
--
-- Lifecycle
--   Motion.Enable()                          runtime only: grabs TweenService/RunService/UserInputService/GuiService
--   Motion.IsLive() -> boolean
--   Motion.SetSoundPlayer(fn(key: string))   UIRoot wires SoundController here; Motion.Sound(key) plays through it
-- Tweens
--   Motion.Spec(theme, kind) -> TweenSpec    kind: "Hover"|"Press"|"Pop"|"Slide"|"Fade"
--   Motion.Tween(inst, spec, props) -> Tween?  spec = { Time, Style?, Direction?, Delay?, Repeat?, Reverses? }
--   Motion.Set(inst, props)
-- Events (runtime only; return nil offline)
--   Motion.On(inst, eventName, fn) -> RBXScriptConnection?
--   Motion.Hover(gui, onEnter, onLeave)      mouse hover + gamepad selection
--   Motion.Press(gui, onDown, onUp)
--   Motion.BindDrag(gui, onAlpha(ax, ay), onEnd?)   pointer drag across gui (sliders)
--   Motion.OnSize(gui, fn(absSize: Vector2))
-- Transitions
--   Motion.PopIn(gui, theme) / Motion.PopOut(gui, theme, destroy?)
--   Motion.SlideIn(gui, theme, from, distance?) / Motion.SlideOut(gui, theme, to, distance?, destroy?)
--   Motion.FadeIn(group, theme) / Motion.FadeOut(group, theme, destroy?)   (CanvasGroup or plain GuiObject)
--   Motion.Shake(gui, intensity?, duration?)   respects GuiService.ReducedMotionEnabled
-- Text
--   Motion.Typewriter(label, text, opts?) -> TypeHandle { Skip(), Cancel(), IsDone() }
--      opts: { Interval?, PunctuationPause?, Sound?: string, SoundEvery?: number, OnDone?: () -> () }
--   Motion.CountUp(label, from, to, duration?, format?: (number) -> string)
-- Loops (return a stop function; also stopped by Motion.StopAll(gui) or when gui is destroyed)
--   Motion.Loop(gui, fn(dt, elapsed)) / Motion.Pulse(gui, propsA, propsB, period)
--   Motion.Sweep(gradient, period, from?, to?)  animates UIGradient.Offset.X from -> to
--   Motion.Spin(gui, degreesPerSecond)
--   Motion.StopAll(gui)

local Motion = {}

export type TweenSpec = {
	Time: number,
	Style: Enum.EasingStyle?,
	Direction: Enum.EasingDirection?,
	Delay: number?,
	Repeat: number?,
	Reverses: boolean?,
}

export type TypeHandle = {
	Skip: () -> (),
	Cancel: () -> (),
	IsDone: () -> boolean,
}

local live = false
local TweenService: any = nil
local RunService: any = nil
local UserInputService: any = nil
local GuiService: any = nil
local soundPlayer: ((string) -> ())? = nil

-- per-instance cleanups for loops/connections
local cleanups: { [Instance]: { () -> () } } = setmetatable({}, { __mode = "k" }) :: any

local DEFAULT_SPECS: { [string]: TweenSpec } = {
	Hover = { Time = 0.15, Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
	Press = { Time = 0.08, Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
	Pop = { Time = 0.25, Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out },
	Slide = { Time = 0.3, Style = Enum.EasingStyle.Quart, Direction = Enum.EasingDirection.Out },
	Fade = { Time = 0.2, Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
}

function Motion.Enable()
	if live then
		return
	end
	TweenService = game:GetService("TweenService")
	RunService = game:GetService("RunService")
	UserInputService = game:GetService("UserInputService")
	GuiService = game:GetService("GuiService")
	live = true
end

function Motion.IsLive(): boolean
	return live
end

function Motion.SetSoundPlayer(fn: ((string) -> ())?)
	soundPlayer = fn
end

function Motion.Sound(key: string?)
	if live and key and soundPlayer then
		task.spawn(soundPlayer, key)
	end
end

local function reducedMotion(): boolean
	if not live or not GuiService then
		return false
	end
	local ok, value = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

function Motion.Spec(theme: any, kind: string): TweenSpec
	local motion = theme and theme.Motion
	local spec = motion and motion[kind]
	if type(spec) == "table" then
		return spec :: TweenSpec
	end
	return DEFAULT_SPECS[kind] or DEFAULT_SPECS.Hover
end

function Motion.Set(inst: Instance, props: { [string]: any })
	for key, value in props do
		(inst :: any)[key] = value
	end
end

function Motion.Tween(inst: Instance, spec: TweenSpec, props: { [string]: any }): any
	if not live then
		Motion.Set(inst, props)
		return nil
	end
	local info = TweenInfo.new(
		spec.Time,
		spec.Style or Enum.EasingStyle.Quad,
		spec.Direction or Enum.EasingDirection.Out,
		spec.Repeat or 0,
		spec.Reverses or false,
		spec.Delay or 0
	)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

-- cleanup registry ---------------------------------------------------------------------------------
local function track(inst: Instance, fn: () -> ())
	local list = cleanups[inst]
	if not list then
		list = {}
		cleanups[inst] = list
		if live then
			local conn: any
			conn = (inst :: any).Destroying:Connect(function()
				conn:Disconnect()
				Motion.StopAll(inst)
			end)
		end
	end
	table.insert(list, fn)
end

function Motion.StopAll(inst: Instance)
	local list = cleanups[inst]
	if not list then
		return
	end
	cleanups[inst] = nil
	for _, fn in list do
		pcall(fn)
	end
end

-- events -----------------------------------------------------------------------------------------
function Motion.On(inst: Instance, eventName: string, fn: (...any) -> ()): any
	if not live then
		return nil
	end
	local ok, signal = pcall(function()
		return (inst :: any)[eventName]
	end)
	if not ok or signal == nil then
		return nil
	end
	local conn = signal:Connect(fn)
	track(inst, function()
		conn:Disconnect()
	end)
	return conn
end

function Motion.Hover(gui: GuiObject, onEnter: () -> (), onLeave: () -> ())
	if not live then
		return
	end
	local hovered, selected = false, false
	local function update(nextHovered: boolean, nextSelected: boolean)
		local before = hovered or selected
		hovered, selected = nextHovered, nextSelected
		local after = hovered or selected
		if after and not before then
			onEnter()
		elseif before and not after then
			onLeave()
		end
	end
	Motion.On(gui, "MouseEnter", function()
		update(true, selected)
	end)
	Motion.On(gui, "MouseLeave", function()
		update(false, selected)
	end)
	Motion.On(gui, "SelectionGained", function()
		update(hovered, true)
	end)
	Motion.On(gui, "SelectionLost", function()
		update(hovered, false)
	end)
end

function Motion.Press(gui: GuiObject, onDown: () -> (), onUp: () -> ())
	if not live then
		return
	end
	local down = false
	Motion.On(gui, "InputBegan", function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
			or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA) then
			down = true
			onDown()
		end
	end)
	Motion.On(gui, "InputEnded", function(input: InputObject)
		if down then
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1 then
				down = false
				onUp()
			end
		end
	end)
	Motion.On(gui, "MouseLeave", function()
		if down then
			down = false
			onUp()
		end
	end)
end

function Motion.OnSize(gui: GuiObject, fn: (Vector2) -> ())
	if not live then
		return
	end
	local ok, signal = pcall(function()
		return gui:GetPropertyChangedSignal("AbsoluteSize")
	end)
	if ok and signal then
		local conn = signal:Connect(function()
			fn(gui.AbsoluteSize)
		end)
		track(gui, function()
			conn:Disconnect()
		end)
		task.defer(fn, gui.AbsoluteSize)
	end
end

function Motion.BindDrag(gui: GuiObject, onAlpha: (number, number) -> (), onEnd: (() -> ())?)
	if not live then
		return
	end
	local dragging = false
	local function apply(position: Vector3 | Vector2)
		local abs = gui.AbsolutePosition
		local size = gui.AbsoluteSize
		local ax = if size.X > 0 then math.clamp((position.X - abs.X) / size.X, 0, 1) else 0
		local ay = if size.Y > 0 then math.clamp((position.Y - abs.Y) / size.Y, 0, 1) else 0
		onAlpha(ax, ay)
	end
	Motion.On(gui, "InputBegan", function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			apply(input.Position)
		end
	end)
	local moveConn = UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging then
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
				apply(input.Position)
			end
		end
	end)
	local endConn = UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging then
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging = false
				if onEnd then
					onEnd()
				end
			end
		end
	end)
	track(gui, function()
		moveConn:Disconnect()
		endConn:Disconnect()
	end)
end

-- transitions --------------------------------------------------------------------------------------
local function ensureScale(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("MotionScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MotionScale"
	scale.Scale = 1
	scale.Parent = gui
	return scale
end

function Motion.PopIn(gui: GuiObject, theme: any)
	if not live then
		return
	end
	local scale = ensureScale(gui)
	local spec = Motion.Spec(theme, "Pop")
	scale.Scale = if theme and theme.Motion and theme.Motion.Style == "Snappy" then 0.92 else 0.82
	Motion.Tween(scale, spec, { Scale = 1 })
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 1
		Motion.Tween(gui, Motion.Spec(theme, "Fade"), { GroupTransparency = 0 })
	end
end

function Motion.PopOut(gui: GuiObject, theme: any, destroy: boolean?)
	if not live then
		if destroy then
			gui:Destroy()
		end
		return
	end
	local scale = ensureScale(gui)
	local spec = Motion.Spec(theme, "Fade")
	local tween = Motion.Tween(scale, spec, { Scale = 0.9 })
	if gui:IsA("CanvasGroup") then
		Motion.Tween(gui, spec, { GroupTransparency = 1 })
	end
	if destroy then
		if tween then
			tween.Completed:Once(function()
				gui:Destroy()
			end)
		else
			gui:Destroy()
		end
	end
end

local function offsetFor(direction: string, distance: number): UDim2
	if direction == "Left" then
		return UDim2.fromOffset(-distance, 0)
	elseif direction == "Right" then
		return UDim2.fromOffset(distance, 0)
	elseif direction == "Top" then
		return UDim2.fromOffset(0, -distance)
	end
	return UDim2.fromOffset(0, distance)
end

function Motion.SlideIn(gui: GuiObject, theme: any, from: string, distance: number?)
	if not live then
		return
	end
	local target = gui.Position
	gui.Position = target + offsetFor(from, distance or 60)
	Motion.Tween(gui, Motion.Spec(theme, "Slide"), { Position = target })
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 1
		Motion.Tween(gui, Motion.Spec(theme, "Fade"), { GroupTransparency = 0 })
	end
end

function Motion.SlideOut(gui: GuiObject, theme: any, to: string, distance: number?, destroy: boolean?)
	if not live then
		if destroy then
			gui:Destroy()
		end
		return
	end
	local tween = Motion.Tween(gui, Motion.Spec(theme, "Slide"), { Position = gui.Position + offsetFor(to, distance or 60) })
	if gui:IsA("CanvasGroup") then
		Motion.Tween(gui, Motion.Spec(theme, "Fade"), { GroupTransparency = 1 })
	end
	if destroy and tween then
		tween.Completed:Once(function()
			gui:Destroy()
		end)
	end
end

function Motion.FadeIn(gui: GuiObject, theme: any)
	if not live then
		return
	end
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 1
		Motion.Tween(gui, Motion.Spec(theme, "Fade"), { GroupTransparency = 0 })
	else
		local target = gui.BackgroundTransparency
		gui.BackgroundTransparency = 1
		Motion.Tween(gui, Motion.Spec(theme, "Fade"), { BackgroundTransparency = target })
	end
end

function Motion.FadeOut(gui: GuiObject, theme: any, destroy: boolean?)
	if not live then
		if destroy then
			gui:Destroy()
		end
		return
	end
	local props = if gui:IsA("CanvasGroup") then { GroupTransparency = 1 } else { BackgroundTransparency = 1 }
	local tween = Motion.Tween(gui, Motion.Spec(theme, "Fade"), props)
	if destroy and tween then
		tween.Completed:Once(function()
			gui:Destroy()
		end)
	end
end

-- loops --------------------------------------------------------------------------------------------
function Motion.Loop(gui: Instance, fn: (number, number) -> ()): () -> ()
	if not live then
		return function() end
	end
	local elapsed = 0
	local conn = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		fn(dt, elapsed)
	end)
	local stopped = false
	local function stop()
		if not stopped then
			stopped = true
			conn:Disconnect()
		end
	end
	track(gui, stop)
	return stop
end

function Motion.Shake(gui: GuiObject, intensity: number?, duration: number?)
	if not live or reducedMotion() then
		return
	end
	local origin = gui.Position
	local power = intensity or 6
	local length = duration or 0.25
	local stop: () -> ()
	stop = Motion.Loop(gui, function(_dt, t)
		if t >= length then
			gui.Position = origin
			stop()
			return
		end
		local falloff = 1 - t / length
		local dx = (math.noise(t * 40, 1.7) * 2) * power * falloff
		local dy = (math.noise(2.3, t * 40) * 2) * power * falloff
		gui.Position = origin + UDim2.fromOffset(math.round(dx), math.round(dy))
	end)
end

function Motion.Pulse(gui: Instance, propsA: { [string]: any }, propsB: { [string]: any }, period: number?): () -> ()
	if not live then
		Motion.Set(gui, propsA)
		return function() end
	end
	Motion.Set(gui, propsA)
	local half = (period or 1.6) / 2
	local tween = Motion.Tween(gui, {
		Time = half,
		Style = Enum.EasingStyle.Sine,
		Direction = Enum.EasingDirection.InOut,
		Repeat = -1,
		Reverses = true,
	}, propsB)
	local function stop()
		if tween then
			tween:Cancel()
		end
	end
	track(gui, stop)
	return stop
end

function Motion.Sweep(gradient: UIGradient, period: number?, from: number?, to: number?): () -> ()
	local a, b = from or -1, to or 1
	if not live then
		return function() end
	end
	local length = period or 2.5
	return Motion.Loop(gradient, function(_dt, t)
		local alpha = (t % length) / length
		gradient.Offset = Vector2.new(a + (b - a) * alpha, gradient.Offset.Y)
	end)
end

function Motion.Spin(gui: GuiObject, degreesPerSecond: number): () -> ()
	if not live then
		return function() end
	end
	return Motion.Loop(gui, function(dt)
		gui.Rotation = (gui.Rotation + degreesPerSecond * dt) % 360
	end)
end

-- text ---------------------------------------------------------------------------------------------
local PUNCTUATION = { ["."] = true, [","] = true, ["!"] = true, ["?"] = true, [":"] = true, [";"] = true }

function Motion.Typewriter(label: TextLabel, text: string, opts: { [string]: any }?): TypeHandle
	local options = opts or {}
	label.Text = text
	local done = false
	if not live then
		label.MaxVisibleGraphemes = -1
		done = true
		return {
			Skip = function() end,
			Cancel = function() end,
			IsDone = function()
				return true
			end,
		}
	end
	local interval: number = options.Interval or 0.03
	local pause: number = options.PunctuationPause or 0.15
	local sound: string? = options.Sound
	local every: number = options.SoundEvery or 2
	local graphemes: { string } = {}
	for _, codepoint in utf8.codes(text) do
		table.insert(graphemes, utf8.char(codepoint))
	end
	local cancelled = false
	label.MaxVisibleGraphemes = 0
	local function finish()
		if not done then
			done = true
			label.MaxVisibleGraphemes = -1
			if options.OnDone then
				task.spawn(options.OnDone)
			end
		end
	end
	task.spawn(function()
		-- RichText tags are invisible graphemes for MaxVisibleGraphemes, so counting codepoints of the
		-- raw text slightly over-waits on rich text; acceptable for dialogue lines.
		local shown = 0
		for i, char in graphemes do
			if cancelled or done then
				return
			end
			shown += 1
			label.MaxVisibleGraphemes = shown
			if sound and char ~= " " and (i % every == 1 or every <= 1) then
				Motion.Sound(sound)
			end
			task.wait(if PUNCTUATION[char] then pause else interval)
		end
		finish()
	end)
	return {
		Skip = function()
			finish()
		end,
		Cancel = function()
			cancelled = true
		end,
		IsDone = function()
			return done
		end,
	}
end

function Motion.CountUp(label: TextLabel, from: number, to: number, duration: number?, format: ((number) -> string)?)
	local fmt = format or function(n: number): string
		return tostring(math.round(n))
	end
	if not live then
		label.Text = fmt(to)
		return
	end
	local length = duration or 0.8
	label.Text = fmt(from)
	local stop: () -> ()
	stop = Motion.Loop(label, function(_dt, t)
		local alpha = math.min(t / length, 1)
		local eased = 1 - (1 - alpha) ^ 3
		label.Text = fmt(from + (to - from) * eased)
		if alpha >= 1 then
			stop()
		end
	end)
end

return Motion
