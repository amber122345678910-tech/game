--!strict
-- UIRoot: owns the player's ScreenGuis (Menu, Hud, Overlay, Toast, Cursor), a menu screen stack, modals,
-- toasts, the menu blur, gamepad focus and the responsive scale. Lune-safe at require time; everything
-- that touches the engine starts in UIRoot.Init(playerGui).
--
-- Insets: every layer is a ScreenGui with ScreenInsets = CoreUISafeInsets (IgnoreGuiInset = false: with true the
-- engine downgrades CoreUISafeInsets to DeviceSafeInsets), so nothing we draw sits under the Roblox top bar
-- (Roblox / menu / chat buttons, 58 px) or a notch. The layout is computed from the layer's own AbsoluteSize
-- (the usable rect), never from the camera viewport. Full-bleed backgrounds reach the real screen edges through
-- Layout.Bleed (ClipToDeviceSafeArea = false; see Screens/Common.Bleed).
--
-- Pure (usable offline, e.g. tools/lune/dump_gui.luau, tools/preview/gui/composite.luau):
--   UIRoot.ComputeLayout(usable: Vector2, safe: Insets?) -> Layout
--       { Viewport (= usable px), Scale, Canvas (design px), Compact, Phone, Portrait, Bleed (design px) }
--       design canvas is ~1600x900 on desktop (1920x1080 -> scale 1.2, 1366x768 -> 0.853);
--       phones fit 480 design px vertically (844x390 -> 0.8125, canvas ~1039x480; never below 0.62);
--       a portrait viewport (transient: the game runs landscape) fits ~820 design px across.
--       safe = distance in px from the usable rect to the screen edges (Layout.Bleed = safe / Scale).
--   UIRoot.SafeInsets(full: Vector2, usable: Vector2, topbar: number) -> Insets   splits full - usable into
--       the top bar (top), an even left/right split and the rest at the bottom (home indicator)
--   UIRoot.SameLayout(a, b) -> boolean      true when a rebuild is not needed (same flags, ~same canvas/scale)
--   UIRoot.CreateLayer(name, displayOrder, layout, insets: Enum.ScreenInsets?) -> (ScreenGui, Frame root, UIScale)
--       ScreenGui: ResetOnSpawn=false, ZIndexBehavior=Sibling, ClipToDeviceSafeArea=false; `insets` given (runtime:
--       CoreUISafeInsets) -> IgnoreGuiInset=false + those insets; nil (offline previews) -> IgnoreGuiInset=true,
--       DeviceSafeInsets. The root Frame is sized 1/scale so children live in design px.
-- Runtime:
--   UIRoot.Init(playerGui, opts?)        opts: { PlaySound: (key) -> ()?, Deps: table? (merged into every screen's deps) }
--   UIRoot.Layer(name) -> Frame          "Menu" | "Hud" | "Overlay" | "Toast" | "Cursor"
--   UIRoot.Layout() -> Layout
--   UIRoot.LayoutChanged:Connect(fn(layout, previous)) -> { Disconnect }   fired when the usable area changes enough
--       to need a rebuild (phone rotation, window resize, top bar shown/hidden); every screen is rebuilt first
--   UIRoot.Push(screenModule, deps?) -> ScreenHandle        hides the previous top screen
--   UIRoot.Pop() -> boolean
--   UIRoot.Replace(screenModule, deps?) -> ScreenHandle
--   UIRoot.Modal(screenModule, deps?) -> ScreenHandle       Overlay layer, previous screens stay visible
--   UIRoot.Clear()                                          pops every screen and modal
--   UIRoot.Top() -> ScreenHandle?
--   UIRoot.MountHud(id, screenModule, deps?) -> ScreenHandle / UIRoot.UnmountHud(id)
--   UIRoot.Rebuild()                                        re-creates every screen/HUD (theme or language change)
--   UIRoot.Toast(text, kind?, icon?, duration?)
--   UIRoot.Focus(gui?)                                      GuiService.SelectedObject when a gamepad is in use
-- Screen module contract (SPEC §10): Create(theme, deps) -> { Root: GuiObject, Destroy: () -> (),
--   DefaultSelection: GuiObject?, OnShow: (() -> ())?, OnHide: (() -> ())? }. deps.Layout is always provided.

local Themes = require(script.Parent.Themes)
local ThemeService = require(script.Parent.ThemeService)
local Motion = require(script.Parent.Motion)
local UIKit = require(script.Parent.UIKit)

type Theme = Themes.Theme

export type Insets = { Left: number, Top: number, Right: number, Bottom: number }
export type Layout = {
	Viewport: Vector2,
	Scale: number,
	Canvas: Vector2,
	Compact: boolean,
	Phone: boolean,
	Portrait: boolean,
	Bleed: Insets,
}
export type ScreenHandle = {
	Root: GuiObject,
	Destroy: () -> (),
	DefaultSelection: GuiObject?,
	OnShow: (() -> ())?,
	OnHide: (() -> ())?,
}
export type ScreenModule = { Create: (Theme, any) -> ScreenHandle }

type Entry = {
	module: ScreenModule,
	deps: any,
	handle: ScreenHandle?,
	layer: string,
	kind: "Screen" | "Modal" | "Hud",
	id: string?,
}

local UIRoot = {}

UIRoot.DesignSize = Vector2.new(1600, 900)
UIRoot.PhoneHeight = 480 -- design px a landscape phone fits vertically
UIRoot.TopbarHeight = 58 -- Roblox top bar (fallback when GuiService.TopbarInset is not available)
UIRoot.DisplayOrder = { Hud = 5, Menu = 10, Overlay = 30, Toast = 40, Cursor = 50 }
UIRoot.LayerNames = { "Hud", "Menu", "Overlay", "Toast", "Cursor" }
UIRoot.RebuildDelay = 0.2 -- s: a rotation / window drag reports several sizes; rebuild once it settles

-- pure helpers ------------------------------------------------------------------------------------
local NO_INSETS: Insets = { Left = 0, Top = 0, Right = 0, Bottom = 0 }

function UIRoot.ComputeLayout(viewport: Vector2, safe: Insets?): Layout
	local w = math.max(viewport.X, 1)
	local h = math.max(viewport.Y, 1)
	local portrait = h > w * 1.05
	local phone = h < 560 or w < 900
	local scale
	if portrait then
		scale = math.clamp(w / 820, 0.4, 1)
	elseif phone then
		scale = math.clamp(h / UIRoot.PhoneHeight, 0.62, 1)
	else
		scale = math.clamp(math.min(w / UIRoot.DesignSize.X, h / UIRoot.DesignSize.Y), 0.6, 2.5)
	end
	local canvas = Vector2.new(w / scale, h / scale)
	local s = safe or NO_INSETS
	return {
		Viewport = Vector2.new(w, h),
		Scale = scale,
		Canvas = canvas,
		Compact = canvas.Y < 760,
		Phone = phone,
		Portrait = portrait,
		Bleed = {
			Left = math.max(s.Left, 0) / scale,
			Top = math.max(s.Top, 0) / scale,
			Right = math.max(s.Right, 0) / scale,
			Bottom = math.max(s.Bottom, 0) / scale,
		},
	}
end

-- full = the whole screen (camera viewport), usable = the CoreUISafeInsets rect: the top bar takes the top,
-- notches split evenly left/right, whatever is left goes to the bottom (home indicator).
function UIRoot.SafeInsets(full: Vector2, usable: Vector2, topbar: number): Insets
	local dx = math.max(full.X - usable.X, 0)
	local dy = math.max(full.Y - usable.Y, 0)
	local top = math.min(math.max(topbar, 0), dy)
	return { Left = dx / 2, Top = top, Right = dx / 2, Bottom = dy - top }
end

function UIRoot.SameLayout(a: Layout?, b: Layout?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.Phone == b.Phone
		and a.Compact == b.Compact
		and (a.Portrait == true) == (b.Portrait == true)
		and math.abs(a.Scale - b.Scale) < 0.005
		and math.abs(a.Canvas.X - b.Canvas.X) < 2
		and math.abs(a.Canvas.Y - b.Canvas.Y) < 2
end

function UIRoot.CreateLayer(
	name: string,
	displayOrder: number,
	layout: Layout,
	insets: Enum.ScreenInsets?
): (ScreenGui, Frame, UIScale)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SV_" .. name
	gui.ResetOnSpawn = false
	if insets then
		gui.IgnoreGuiInset = false -- true would turn CoreUISafeInsets into DeviceSafeInsets (under the top bar)
		gui.ScreenInsets = insets
	else
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end
	gui.ClipToDeviceSafeArea = false -- full-bleed backdrops may extend into notch strips (content stays in Root)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1 / layout.Scale, 1 / layout.Scale)
	local scale = Instance.new("UIScale")
	scale.Name = "DesignScale"
	scale.Scale = layout.Scale
	scale.Parent = root
	root.Parent = gui
	return gui, root, scale
end

-- tiny signal (Util/Signal lives in ReplicatedStorage; UIRoot stays Lune-safe without it)
type Listener = { fn: (Layout, Layout) -> (), connected: boolean }
local layoutListeners: { Listener } = {}
UIRoot.LayoutChanged = {
	Connect = function(_self: any, fn: (Layout, Layout) -> ()): { Disconnect: () -> (), Connected: boolean }
		local entry: Listener = { fn = fn, connected = true }
		table.insert(layoutListeners, entry)
		local conn = { Connected = true }
		function conn.Disconnect()
			entry.connected = false
			conn.Connected = false
			local i = table.find(layoutListeners, entry)
			if i then
				table.remove(layoutListeners, i)
			end
		end
		return conn :: any
	end,
}

local function fireLayoutChanged(layout: Layout, previous: Layout)
	for _, entry in table.clone(layoutListeners) do
		if entry.connected then
			local ok, err = pcall(entry.fn, layout, previous)
			if not ok then
				warn("[UIRoot] LayoutChanged listener failed: " .. tostring(err))
			end
		end
	end
end

-- runtime state -------------------------------------------------------------------------------------
local initialized = false
local playerGuiRef: Instance? = nil
local layers: { [string]: { gui: ScreenGui, root: Frame, scale: UIScale } } = {}
local currentLayout: Layout = UIRoot.ComputeLayout(Vector2.new(1920, 1080))
local stack: { Entry } = {}
local huds: { [string]: Entry } = {}
local baseDeps: { [string]: any } = {}
local blur: BlurEffect? = nil
local toastHolder: Frame? = nil
local GuiService: any = nil
local UserInputService: any = nil
local builtLayout: Layout = currentLayout -- the layout the current screens were built with
local rebuildToken = 0

local function topbarHeight(): number
	if GuiService then
		local ok, rect = pcall(function()
			return GuiService.TopbarInset
		end)
		if ok and typeof(rect) == "Rect" and rect.Height > 0 then
			return rect.Height
		end
	end
	return UIRoot.TopbarHeight
end

-- the layout of the usable (CoreUISafeInsets) area, measured on the Menu layer
local function measureLayout(): Layout
	local camera = workspace.CurrentCamera
	local full = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local menu = layers.Menu
	local usable = if menu then menu.gui.AbsoluteSize else Vector2.zero
	if usable.X < 2 or usable.Y < 2 then
		usable = Vector2.new(full.X, math.max(full.Y - topbarHeight(), 1))
	end
	return UIRoot.ComputeLayout(usable, UIRoot.SafeInsets(full, usable, topbarHeight()))
end

local function depsFor(entry: Entry): any
	local deps: { [string]: any } = table.clone(baseDeps)
	if type(entry.deps) == "table" then
		for k, v in entry.deps do
			deps[k] = v
		end
	end
	deps.Layout = currentLayout
	deps.UIRoot = UIRoot
	return deps
end

local function gamepadActive(): boolean
	if not UserInputService then
		return false
	end
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4
end

function UIRoot.Focus(gui: GuiObject?)
	if GuiService and gamepadActive() then
		GuiService.SelectedObject = gui
	end
end

local function updateBlur()
	if not initialized then
		return
	end
	local theme = ThemeService.Current()
	local anyMenu = false
	for _, entry in stack do
		if entry.handle then
			anyMenu = true
			break
		end
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if blur == nil or blur.Parent ~= camera then
		local b = Instance.new("BlurEffect")
		b.Name = "SV_MenuBlur"
		b.Size = 0
		b.Parent = camera
		blur = b
	end
	local target = if anyMenu then theme.Blur else 0
	Motion.Tween(blur :: BlurEffect, Motion.Spec(theme, "Fade"), { Size = target })
end

local function build(entry: Entry)
	local layer = layers[entry.layer]
	if not layer then
		return
	end
	local theme = ThemeService.Current()
	local ok, handleOrErr = pcall(entry.module.Create, theme, depsFor(entry))
	if not ok then
		warn("[UIRoot] screen Create failed: " .. tostring(handleOrErr))
		return
	end
	local handle = handleOrErr :: ScreenHandle
	entry.handle = handle
	handle.Root.Parent = layer.root
end

local function destroyEntry(entry: Entry)
	local handle = entry.handle
	entry.handle = nil
	if handle then
		local ok, err = pcall(handle.Destroy)
		if not ok then
			warn("[UIRoot] screen Destroy failed: " .. tostring(err))
			pcall(function()
				handle.Root:Destroy()
			end)
		end
	end
end

local function topScreen(): Entry?
	for i = #stack, 1, -1 do
		if stack[i].kind == "Screen" then
			return stack[i]
		end
	end
	return nil
end

local function showTop()
	local top = stack[#stack]
	if top and top.handle then
		top.handle.Root.Visible = true
		if top.handle.OnShow then
			task.spawn(top.handle.OnShow)
		end
		UIRoot.Focus(top.handle.DefaultSelection)
	elseif GuiService then
		UIRoot.Focus(nil)
	end
	updateBlur()
end

-- public runtime API --------------------------------------------------------------------------------
function UIRoot.Init(playerGui: Instance, opts: { [string]: any }?)
	if initialized then
		return
	end
	initialized = true
	playerGuiRef = playerGui
	local options = opts or {}
	Motion.Enable()
	if options.PlaySound then
		Motion.SetSoundPlayer(options.PlaySound)
	end
	if type(options.Deps) == "table" then
		baseDeps = options.Deps
	end
	GuiService = game:GetService("GuiService")
	UserInputService = game:GetService("UserInputService")
	-- the usable area is only known once a layer is parented: start from the viewport minus the top bar
	local camera = workspace.CurrentCamera
	local viewport0 = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	currentLayout = UIRoot.ComputeLayout(Vector2.new(viewport0.X, math.max(viewport0.Y - UIRoot.TopbarHeight, 1)))
	for _, name in UIRoot.LayerNames do
		local gui, root, scale =
			UIRoot.CreateLayer(name, UIRoot.DisplayOrder[name], currentLayout, Enum.ScreenInsets.CoreUISafeInsets)
		gui.Parent = playerGui
		layers[name] = { gui = gui, root = root, scale = scale }
	end
	currentLayout = measureLayout()
	builtLayout = currentLayout
	for _, layer in layers do
		layer.scale.Scale = currentLayout.Scale
		layer.root.Size = UDim2.fromScale(1 / currentLayout.Scale, 1 / currentLayout.Scale)
	end
	-- toast column (top-right, under the top bar thanks to the layer insets)
	local holder = Instance.new("Frame")
	holder.Name = "Toasts"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -16, 0, 12)
	holder.Size = UDim2.fromOffset(380, 600)
	UIKit.ListLayout(holder, { Gap = 10, HAlign = Enum.HorizontalAlignment.Right })
	holder.Parent = layers.Toast.root
	toastHolder = holder
	-- responsive layout: the scale follows at once; screens built for the old canvas are rebuilt once the size
	-- settles (a phone that boots in portrait and then rotates used to keep a stale portrait layout)
	local function onResize()
		local nextLayout = measureLayout()
		local previous = currentLayout
		currentLayout = nextLayout
		for _, layer in layers do
			layer.scale.Scale = nextLayout.Scale
			layer.root.Size = UDim2.fromScale(1 / nextLayout.Scale, 1 / nextLayout.Scale)
		end
		if not UIRoot.SameLayout(previous, nextLayout) and not UIRoot.SameLayout(builtLayout, nextLayout) then
			rebuildToken += 1
			local token = rebuildToken
			task.delay(UIRoot.RebuildDelay, function()
				if token ~= rebuildToken or UIRoot.SameLayout(builtLayout, currentLayout) then
					return
				end
				local old = builtLayout
				UIRoot.Rebuild()
				fireLayoutChanged(currentLayout, old)
			end)
		end
	end
	layers.Menu.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize)
	local cameraConn: RBXScriptConnection? = nil
	local function bindCamera(cam: Camera?)
		if cameraConn then
			cameraConn:Disconnect()
			cameraConn = nil
		end
		if cam then
			cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onResize)
			onResize()
		end
	end
	bindCamera(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(workspace.CurrentCamera)
		updateBlur()
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(onResize)
	end)
	-- rebuild on theme / HUD style change
	ThemeService.Changed:Connect(function()
		UIRoot.Rebuild()
	end)
	ThemeService.HudChanged:Connect(function()
		for _, entry in huds do
			destroyEntry(entry)
			build(entry)
		end
	end)
	-- gamepad: re-focus the top screen when a gamepad becomes the active input
	UserInputService.LastInputTypeChanged:Connect(function()
		local top = stack[#stack]
		if top and top.handle and gamepadActive() and GuiService.SelectedObject == nil then
			UIRoot.Focus(top.handle.DefaultSelection)
		end
	end)
end

function UIRoot.IsInitialized(): boolean
	return initialized
end

function UIRoot.Layer(name: string): Frame
	local layer = layers[name]
	assert(layer, "UIRoot: unknown layer or UIRoot.Init not called: " .. tostring(name))
	return layer.root
end

function UIRoot.Layout(): Layout
	return currentLayout
end

function UIRoot.Push(module: ScreenModule, deps: any?): ScreenHandle?
	local previous = stack[#stack]
	if previous and previous.handle and previous.kind == "Screen" then
		previous.handle.Root.Visible = false
		if previous.handle.OnHide then
			task.spawn(previous.handle.OnHide)
		end
	end
	local entry: Entry = { module = module, deps = deps, handle = nil, layer = "Menu", kind = "Screen" }
	table.insert(stack, entry)
	build(entry)
	if entry.handle then
		Motion.SlideIn(entry.handle.Root, ThemeService.Current(), "Right", 40)
	end
	showTop()
	return entry.handle
end

function UIRoot.Modal(module: ScreenModule, deps: any?): ScreenHandle?
	local entry: Entry = { module = module, deps = deps, handle = nil, layer = "Overlay", kind = "Modal" }
	table.insert(stack, entry)
	build(entry)
	if entry.handle then
		Motion.PopIn(entry.handle.Root, ThemeService.Current())
		Motion.Sound(ThemeService.Current().Sounds.Open)
	end
	showTop()
	return entry.handle
end

function UIRoot.Pop(): boolean
	local entry = table.remove(stack)
	if not entry then
		return false
	end
	Motion.Sound(ThemeService.Current().Sounds.Back)
	destroyEntry(entry)
	showTop()
	return true
end

function UIRoot.Replace(module: ScreenModule, deps: any?): ScreenHandle?
	local top = stack[#stack]
	if top then
		table.remove(stack)
		destroyEntry(top)
	end
	return UIRoot.Push(module, deps)
end

function UIRoot.Clear()
	while #stack > 0 do
		local entry = table.remove(stack) :: Entry
		destroyEntry(entry)
	end
	updateBlur()
	if GuiService then
		UIRoot.Focus(nil)
	end
end

function UIRoot.Top(): ScreenHandle?
	local top = stack[#stack]
	return if top then top.handle else nil
end

function UIRoot.TopScreen(): ScreenHandle?
	local entry = topScreen()
	return if entry then entry.handle else nil
end

function UIRoot.Depth(): number
	return #stack
end

function UIRoot.MountHud(id: string, module: ScreenModule, deps: any?): ScreenHandle?
	UIRoot.UnmountHud(id)
	local entry: Entry = { module = module, deps = deps, handle = nil, layer = "Hud", kind = "Hud", id = id }
	huds[id] = entry
	build(entry)
	return entry.handle
end

function UIRoot.UnmountHud(id: string)
	local entry = huds[id]
	if entry then
		huds[id] = nil
		destroyEntry(entry)
	end
end

function UIRoot.Rebuild()
	if not initialized then
		return
	end
	builtLayout = currentLayout
	for _, entry in huds do
		destroyEntry(entry)
		build(entry)
	end
	for i, entry in stack do
		destroyEntry(entry)
		build(entry)
		if entry.handle and i < #stack and entry.kind == "Screen" then
			-- only the top-most screen is visible; modals keep their screens visible underneath
			local above = stack[i + 1]
			if above and above.kind == "Screen" then
				entry.handle.Root.Visible = false
			end
		end
	end
	showTop()
end

function UIRoot.Toast(text: string, kind: string?, icon: string?, duration: number?)
	if not toastHolder then
		return
	end
	local theme = ThemeService.Current()
	local toast = UIKit.Toast(theme, { Text = text, Kind = kind or "Info", Icon = icon, Width = 360 })
	toast.Root.LayoutOrder = math.floor(os.clock() * 1000) % 1000000
	toast.Root.Parent = toastHolder
	Motion.SlideIn(toast.Root, theme, "Right", 60)
	Motion.Sound(if kind == "Reward" then theme.Sounds.Reward else theme.Sounds.Open)
	task.delay(duration or 4, function()
		if toast.Root.Parent then
			Motion.SlideOut(toast.Root, theme, "Right", 80, true)
		end
	end)
end

function UIRoot.PlayerGui(): Instance?
	return playerGuiRef
end

return UIRoot
