--!strict
-- Hud/MobileControls: touch controls (only when InputController.Device() == "Touch"): a big attack button in the
-- bottom-right corner with the kit's abilities on two arcs around it (cooldown wipes, ult ring + READY glow,
-- dash charges, block guard, hold charge, disabled tint — the same slot visuals as Hud/AbilityBar), a jump
-- button and a camera-lock toggle. Every button is a TextButton wired with InputController.BindTouchButton.
-- Placed inside the HUD layer (ScreenInsets = DeviceSafeInsets) with extra margins for thumbs.
--   MobileControls.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), SetActive(on), Destroy }
--   MobileControls.Positions(role, canvas) -> {[action] = {X, Y, Size}}   (pure; tests / tuning)
local Style = require(script.Parent.Style)
local AbilityBar = require(script.Parent.AbilityBar)

local MobileControls = {}

type Spot = { Action: string, R: number, A: number, D: number }

local HUMAN: { Spot } = {
	{ Action = "M1", R = 0, A = 0, D = 104 },
	{ Action = "Q", R = 118, A = 182, D = 64 },
	{ Action = "E", R = 118, A = 148, D = 64 },
	{ Action = "F", R = 118, A = 114, D = 64 },
	{ Action = "Shift", R = 118, A = 80, D = 64 },
	{ Action = "R", R = 206, A = 132, D = 76 },
	{ Action = "Jump", R = 206, A = 180, D = 62 },
}
local MONSTER: { Spot } = {
	{ Action = "M1", R = 0, A = 0, D = 104 },
	{ Action = "Q", R = 120, A = 184, D = 62 },
	{ Action = "E", R = 120, A = 151, D = 62 },
	{ Action = "R", R = 120, A = 118, D = 62 },
	{ Action = "T", R = 120, A = 85, D = 62 },
	{ Action = "Shift", R = 212, A = 166, D = 62 },
	{ Action = "F", R = 212, A = 136, D = 66 },
	{ Action = "G", R = 212, A = 104, D = 76 },
	{ Action = "Jump", R = 212, A = 192, D = 60 },
}

function MobileControls.Positions(role: string, canvas: Vector2): { [string]: { X: number, Y: number, Size: number } }
	local spots = if role == "Monster" then MONSTER else HUMAN
	local ax, ay = canvas.X - 34 - 52, canvas.Y - 28 - 52
	local out = {}
	for _, spot in spots do
		local a = math.rad(spot.A)
		out[spot.Action] = { X = ax + spot.R * math.cos(a), Y = ay - spot.R * math.sin(a), Size = spot.D }
	end
	return out
end

function MobileControls.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "MobileControls")
	local C = skin.C
	local battle = skin.Battle
	local d = if type(deps) == "table" then deps else {}
	local canvas: Vector2 = layout.Canvas
	local cluster = Style.Frame({ Name = "Cluster", Size = UDim2.fromScale(1, 1), Parent = root })
	local unbinds: { () -> () } = {}
	local slots: { any } = {}
	local kitShown = ""
	local snap: { [string]: any }? = nil

	local function bind(action: string, button: GuiButton)
		local input = d.Input
		if d.Live and type(input) == "table" and type(input.BindTouchButton) == "function" then
			local ok, unbind = pcall(input.BindTouchButton, action, button)
			if ok and type(unbind) == "function" then
				table.insert(unbinds, unbind)
			end
		end
	end

	local function plainButton(name: string, icon: string, size: number, x: number, y: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = if battle then 0 else 0.25
		b.BackgroundColor3 = if battle then Style.BLACK else Color3.fromRGB(12, 14, 22)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(size, size)
		Style.Corner(b, UDim.new(0.5, 0))
		Style.Stroke(b, if battle then C.Accent else Style.WHITE, if battle then 3 else 2, if battle then 0 else 0.55)
		local glyph = Style.Icon(icon, if battle then C.Accent else Style.WHITE, math.floor(size * 0.46))
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Parent = b
		b.Parent = cluster
		return b
	end

	local function clearBindings()
		for _, unbind in unbinds do
			pcall(unbind)
		end
		table.clear(unbinds)
	end

	local function build(kitId: string, role: string)
		kitShown = kitId
		clearBindings()
		cluster:ClearAllChildren()
		table.clear(slots)
		local pos = MobileControls.Positions(role, canvas)
		for _, info in Style.Slots(kitId) do
			local spot = pos[info.Action]
			if spot then
				local slot = AbilityBar.BuildSlot(skin, info, spot.Size, { Round = true, Button = true, Phone = true })
				slot.Root.AnchorPoint = Vector2.new(0.5, 0.5)
				slot.Root.Position = UDim2.fromOffset(spot.X, spot.Y)
				slot.Root.Parent = cluster
				bind(info.Action, slot.Root :: any)
				table.insert(slots, slot)
			end
		end
		local jump = pos.Jump
		if jump then
			bind("Jump", plainButton("Jump", "ArrowUp", jump.Size, jump.X, jump.Y))
		end
		bind("CameraLock", plainButton("CameraLock", "Target", 46, canvas.X - 40, math.floor(canvas.Y * 0.27)))
	end

	local function tick(now: number)
		local s = snap
		if not s or not s.Me then
			return
		end
		for _, slot in slots do
			slot.Set(AbilityBar.SlotState(slot.Info, s, now))
		end
	end

	local function update(s: { [string]: any })
		snap = s
		local me = s.Me
		cluster.Visible = me ~= nil
		if not me then
			return
		end
		if me.KitId ~= kitShown then
			local kit = Style.Kit(me.KitId)
			build(me.KitId, if kit and kit.Role == "Monster" then "Monster" else "Human")
		end
		tick(s.Now or 0)
	end

	local initial = Style.Initial(deps, "Touch")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Tick = tick,
		SetActive = function(on: boolean)
			if not on then
				clearBindings()
				kitShown = ""
			elseif snap then
				update(snap)
			end
		end,
		Destroy = function()
			clearBindings()
			root:Destroy()
		end,
	}
end

return MobileControls
