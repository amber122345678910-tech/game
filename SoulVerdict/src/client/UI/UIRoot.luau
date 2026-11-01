--!strict
-- UIRoot: owns the player's ScreenGuis (Menu, Hud, Overlay, Toast, Cursor), a menu screen stack, modals,
-- toasts, the menu blur, gamepad focus and the responsive scale. Lune-safe at require time; everything
-- that touches the engine starts in UIRoot.Init(playerGui).
--
-- Pure (usable offline, e.g. tools/lune/dump_gui.luau):
--   UIRoot.ComputeLayout(viewport: Vector2) -> Layout   { Viewport, Scale, Canvas, Compact, Phone }
--       design canvas is ~1600x900 on desktop (1920x1080 -> scale 1.2, 1366x768 -> 0.853);
--       phones get a larger relative scale (844x390 -> 0.8125, canvas ~1039x480)
--   UIRoot.CreateLayer(name, displayOrder, layout) -> (ScreenGui, Frame root, UIScale)
--       ScreenGui: ResetOnSpawn=false, IgnoreGuiInset=true, ScreenInsets=DeviceSafeInsets, ZIndexBehavior=Sibling;
--       root Frame is sized 1/scale so children live in design px.
-- Runtime:
--   UIRoot.Init(playerGui, opts?)        opts: { PlaySound: (key) -> ()?, Deps: table? (merged into every screen's deps) }
--   UIRoot.Layer(name) -> Frame          "Menu" | "Hud" | "Overlay" | "Toast" | "Cursor"
--   UIRoot.Layout() -> Layout
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

export type Layout = { Viewport: Vector2, Scale: number, Canvas: Vector2, Compact: boolean, Phone: boolean }
export type ScreenHandle = {
	Root: GuiObject,
	Destroy: () -> (),
	DefaultSelection: GuiObject?,
	OnShow: (() -> ())?,
	OnHide: (() -> ())?,
}
export type ScreenModule = { Create: (Theme, any) -> ScreenHandle }

type Entry = { module: ScreenModule, deps: any, handle: ScreenHandle?, layer: string, kind: "Screen" | "Modal" | "Hud", id: string? }

local UIRoot = {}

UIRoot.DesignSize = Vector2.new(1600, 900)
UIRoot.DisplayOrder = { Hud = 5, Menu = 10, Overlay = 30, Toast = 40, Cursor = 50 }
UIRoot.LayerNames = { "Hud", "Menu", "Overlay", "Toast", "Cursor" }

-- pure helpers ------------------------------------------------------------------------------------
function UIRoot.ComputeLayout(viewport: Vector2): Layout
	local w = math.max(viewport.X, 1)
	local h = math.max(viewport.Y, 1)
	local phone = h < 560 or w < 900
	local scale
	if phone then
		scale = math.clamp(h / 480, 0.62, 1)
	else
		scale = math.clamp(math.min(w / UIRoot.DesignSize.X, h / UIRoot.DesignSize.Y), 0.6, 2.5)
	end
	local canvas = Vector2.new(w / scale, h / scale)
	return {
		Viewport = Vector2.new(w, h),
		Scale = scale,
		Canvas = canvas,
		Compact = canvas.Y < 760,
		Phone = phone,
	}
end

function UIRoot.CreateLayer(name: string, displayOrder: number, layout: Layout): (ScreenGui, Frame, UIScale)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SV_" .. name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
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

local function depsFor(entry: Entry): any
	local deps: { [string]: any } = {}
	for k, v in baseDeps do
		deps[k] = v
	end
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
	local camera = workspace.CurrentCamera
	currentLayout = UIRoot.ComputeLayout(if camera then camera.ViewportSize else Vector2.new(1920, 1080))
	for _, name in UIRoot.LayerNames do
		local gui, root, scale = UIRoot.CreateLayer(name, UIRoot.DisplayOrder[name], currentLayout)
		gui.Parent = playerGui
		layers[name] = { gui = gui, root = root, scale = scale }
	end
	-- toast column (top-right)
	local holder = Instance.new("Frame")
	holder.Name = "Toasts"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -24, 0, 24)
	holder.Size = UDim2.fromOffset(380, 600)
	UIKit.ListLayout(holder, { Gap = 10, HAlign = Enum.HorizontalAlignment.Right })
	holder.Parent = layers.Toast.root
	toastHolder = holder
	-- responsive scale
	local function onViewport()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local nextLayout = UIRoot.ComputeLayout(cam.ViewportSize)
		local categoryChanged = nextLayout.Phone ~= currentLayout.Phone or nextLayout.Compact ~= currentLayout.Compact
		currentLayout = nextLayout
		for _, layer in layers do
			layer.scale.Scale = nextLayout.Scale
			layer.root.Size = UDim2.fromScale(1 / nextLayout.Scale, 1 / nextLayout.Scale)
		end
		if categoryChanged then
			UIRoot.Rebuild()
		end
	end
	local function bindCamera(cam: Camera?)
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewport)
			onViewport()
		end
	end
	bindCamera(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(workspace.CurrentCamera)
		updateBlur()
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
