--!strict
-- VFX/DamageNumbers: world-space damage / heal / MISS popups (BillboardGui, Arcade font, pop + arc + fade),
-- coloured by kind, merged for rapid ticks and stacked per target so they never overlap.
--
-- API
--   DamageNumbers.Style(packet, viewer?) -> Style?        PURE: how a DamageFx packet is shown (nil = nothing)
--        viewer = { Local: Model? (local character), Team: string? (local team) }
--        Style = { Kind, Text, Color, Stroke, Scale, Merge: boolean, Amount: number }
--   DamageNumbers.STYLES                                  Kind -> { Color, Stroke, Scale, Merge, Prefix?, Suffix? }
--        Kinds: Damage (dealt to others, Undertale red), Taken (dealt to the viewer), Heal, Miss, Parry,
--        Blocked, Crit, KR (purple tick), Absorbed, Dodge (dodge drain), Alert (GUARD BREAK / COUNTER ...)
--   DamageNumbers.Format(amount) -> string                PURE: "7", "12", "0.5"
--   DamageNumbers.Show(packet, viewer?)                    style + popup at packet.pos (merging per target)
--   DamageNumbers.Popup(pos, text, color, opts?)           free text; opts { Scale, Stroke, Kind, Target, Life,
--                                                          Rise, Amount, Merge }
--   DamageNumbers.KRTick(target, amount, pos)              small purple KR drain number (merged per target)
--   DamageNumbers.SetEnabled(on) / Enabled()               (Settings "DamageNumbers")
--   DamageNumbers.Clear()
-- Text comes from Shared/Strings (KitText: fx.miss, fx.parry, fx.dodgeDrain ...).
-- One PreRender loop animates every live number; entries are pooled (anchor part + BillboardGui).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings")) :: any

local DamageNumbers = {}

export type Style = {
	Kind: string,
	Text: string,
	Color: Color3,
	Stroke: Color3,
	Scale: number,
	Merge: boolean,
	Amount: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

DamageNumbers.STYLES = {
	Damage = { Color = rgb(255, 46, 46), Stroke = rgb(40, 0, 0), Scale = 1, Merge = true },
	Taken = { Color = rgb(255, 255, 255), Stroke = rgb(150, 0, 0), Scale = 1, Merge = true },
	Heal = { Color = rgb(76, 255, 106), Stroke = rgb(8, 70, 20), Scale = 0.95, Merge = true, Prefix = "+" },
	Miss = { Color = rgb(191, 191, 191), Stroke = rgb(0, 0, 0), Scale = 0.95, Merge = false },
	Parry = { Color = rgb(255, 213, 74), Stroke = rgb(90, 58, 0), Scale = 1.15, Merge = false },
	Blocked = { Color = rgb(169, 196, 232), Stroke = rgb(20, 32, 52), Scale = 0.85, Merge = true },
	Crit = { Color = rgb(255, 228, 92), Stroke = rgb(122, 58, 0), Scale = 1.35, Merge = false, Suffix = "!" },
	KR = { Color = rgb(213, 53, 217), Stroke = rgb(36, 0, 44), Scale = 0.62, Merge = true },
	Absorbed = { Color = rgb(127, 232, 255), Stroke = rgb(8, 48, 58), Scale = 0.8, Merge = true },
	Dodge = { Color = rgb(154, 216, 255), Stroke = rgb(10, 32, 51), Scale = 0.8, Merge = false },
	Alert = { Color = rgb(255, 154, 60), Stroke = rgb(74, 26, 0), Scale = 1.1, Merge = false },
}

local enabled = true

function DamageNumbers.SetEnabled(on: boolean)
	enabled = on
	if not on then
		DamageNumbers.Clear()
	end
end

function DamageNumbers.Enabled(): boolean
	return enabled
end

function DamageNumbers.Format(amount: number): string
	if amount ~= amount then
		return "0"
	end
	local a = math.abs(amount)
	if a < 1 and a > 0 then
		return string.format("%.1f", a)
	end
	return tostring(math.floor(a + 0.5))
end

local function make(kind: string, text: string, amount: number): Style
	local s = (DamageNumbers.STYLES :: any)[kind]
	return {
		Kind = kind,
		Text = (s.Prefix or "") .. text .. (s.Suffix or ""),
		Color = s.Color,
		Stroke = s.Stroke,
		Scale = s.Scale,
		Merge = s.Merge,
		Amount = amount,
	}
end

-- PURE: the styling decision for a DamageFx packet.
function DamageNumbers.Style(packet: { [string]: any }, viewer: { [string]: any }?): Style?
	if type(packet) ~= "table" then
		return nil
	end
	local amount = if type(packet.amount) == "number" then packet.amount else 0
	local kind = packet.kind
	if kind == "Heal" then
		if amount < 0.5 then
			return nil
		end
		return make("Heal", DamageNumbers.Format(amount), amount)
	elseif kind == "DodgeDrain" then
		return make("Dodge", Strings.L("fx.dodgeDrain", DamageNumbers.Format(amount)), amount)
	end
	if packet.dodged or packet.negated then
		return make("Miss", Strings.L("fx.miss"), 0)
	end
	if packet.parried then
		return make("Parry", Strings.L("fx.parry"), 0)
	end
	if amount <= 0 then
		local absorbed = packet.absorbed
		if type(absorbed) == "number" and absorbed > 0 then
			return make("Absorbed", "(" .. DamageNumbers.Format(absorbed) .. ")", absorbed)
		end
		return nil
	end
	if packet.crit then
		return make("Crit", DamageNumbers.Format(amount), amount)
	end
	if packet.blocked then
		return make("Blocked", DamageNumbers.Format(amount), amount)
	end
	local v = viewer or {}
	if v.Local ~= nil and packet.target == v.Local then
		return make("Taken", DamageNumbers.Format(amount), amount)
	end
	return make("Damage", DamageNumbers.Format(amount), amount)
end

---------------------------------------------------------------------------------------------------
-- Runtime

local FONT = Font.new("rbxasset://fonts/families/PressStart2P.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local MAX_LIVE = 40

type Entry = {
	Host: BasePart,
	Gui: BillboardGui,
	Label: TextLabel,
	Stroke: UIStroke,
	UScale: UIScale,
	T0: number,
	Life: number,
	Rise: number,
	Drift: number,
	Scale: number,
	Kind: string,
	Target: any,
	Amount: number,
	Prefix: string,
	Suffix: string,
	Slot: number,
	Live: boolean,
}

local free: { Entry } = {}
local live: { Entry } = {}
local conn: any = nil
local slotCounter: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

local function folder(): Instance?
	local ok, f = pcall(function()
		local client = script.Parent
		local Lib = require(client:WaitForChild("Lib")) :: any
		return Lib.Folder()
	end)
	return if ok then f else nil
end

local function newEntry(): Entry?
	local parent = folder()
	if parent == nil then
		return nil
	end
	local anchor = Instance.new("Part")
	anchor.Name = "FXNumber"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Number"
	gui.Size = UDim2.new(3.4, 46, 1.25, 18)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ClipsDescendants = false
	gui.Adornee = anchor
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 1
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = label
	local uscale = Instance.new("UIScale")
	uscale.Scale = 1
	uscale.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	anchor.CFrame = CFrame.new(0, 25000, 0)
	anchor.Parent = parent
	return {
		Host = anchor,
		Gui = gui,
		Label = label,
		Stroke = stroke,
		UScale = uscale,
		T0 = 0,
		Life = 1,
		Rise = 2,
		Drift = 0,
		Scale = 1,
		Kind = "",
		Target = nil,
		Amount = 0,
		Prefix = "",
		Suffix = "",
		Slot = 0,
		Live = false,
	}
end

local function recycle(e: Entry)
	e.Live = false
	e.Gui.Enabled = false
	e.Target = nil
	e.Host.CFrame = CFrame.new(0, 25000, 0)
	if e.Host.Parent ~= nil then
		table.insert(free, e)
	end
end

local function update()
	local now = os.clock()
	local i = 1
	while i <= #live do
		local e = live[i]
		local age = now - e.T0
		local a = age / e.Life
		if a >= 1 or e.Host.Parent == nil then
			local n = #live
			live[i] = live[n]
			live[n] = nil
			recycle(e)
		else
			-- pop: 0 -> 1.3 -> 1 (first 0.2 s)
			local pop: number
			if age < 0.07 then
				pop = 1.3 * (age / 0.07)
			elseif age < 0.2 then
				pop = 1.3 - 0.3 * ((age - 0.07) / 0.13)
			else
				pop = 1
			end
			e.UScale.Scale = math.max(0.01, pop)
			-- arc: quick rise, slow settle, sideways drift
			local r = math.min(1, a * 1.7)
			local y = e.Rise * (1 - (1 - r) * (1 - r)) + e.Slot * 0.85
			e.Gui.StudsOffsetWorldSpace = Vector3.new(e.Drift * a, y, 0)
			local fade = if a > 0.68 then (a - 0.68) / 0.32 else 0
			e.Label.TextTransparency = fade
			e.Stroke.Transparency = fade
			i += 1
		end
	end
	if #live == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function acquire(): Entry?
	local n = #free
	local e: Entry? = nil
	if n > 0 then
		e = free[n]
		free[n] = nil
	elseif #live >= MAX_LIVE then
		-- recycle the oldest
		local oldest, idx = math.huge, 0
		for i, l in live do
			if l.T0 < oldest then
				oldest = l.T0
				idx = i
			end
		end
		if idx > 0 then
			e = table.remove(live, idx)
		end
	else
		e = newEntry()
	end
	return e
end

local function spawnText(pos: Vector3, text: string, color: Color3, stroke: Color3, scale: number, opts: { [string]: any })
	if not enabled then
		return
	end
	local e = acquire()
	if e == nil then
		return
	end
	local target = opts.Target
	local slot = 0
	if target ~= nil then
		local c = (slotCounter[target] or 0) % 4
		slotCounter[target] = c + 1
		slot = c
	end
	e.Live = true
	e.T0 = os.clock()
	e.Life = opts.Life or (if scale >= 1.2 then 1.15 else 0.95)
	e.Rise = opts.Rise or (1.6 + 0.6 * scale)
	e.Drift = (if slot % 2 == 0 then 1 else -1) * (0.35 + 0.25 * slot)
	e.Scale = scale
	e.Kind = opts.Kind or ""
	e.Target = target
	e.Amount = opts.Amount or 0
	e.Prefix = opts.Prefix or ""
	e.Suffix = opts.Suffix or ""
	e.Slot = slot
	e.Gui.Size = UDim2.new(3.4 * scale, math.floor(46 * scale), 1.25 * scale, math.floor(18 * scale))
	e.Label.Text = text
	e.Label.TextColor3 = color
	e.Label.TextTransparency = 0
	e.Stroke.Color = stroke
	e.Stroke.Transparency = 0
	e.Stroke.Thickness = if scale < 0.8 then 1.5 else 2.5
	e.UScale.Scale = 0.01
	e.Gui.StudsOffsetWorldSpace = Vector3.zero
	e.Host.CFrame = CFrame.new(pos)
	e.Gui.Enabled = true
	table.insert(live, e)
	if conn == nil then
		conn = RunService.PreRender:Connect(update)
	end
end

-- Adds to a young number of the same kind on the same target instead of spawning a new one.
local function tryMerge(target: any, kind: string, amount: number): boolean
	if target == nil then
		return false
	end
	local now = os.clock()
	for _, e in live do
		if e.Target == target and e.Kind == kind and now - e.T0 < 0.35 then
			e.Amount += amount
			e.Label.Text = e.Prefix .. DamageNumbers.Format(e.Amount) .. e.Suffix
			e.T0 = now - 0.03 -- re-pop
			return true
		end
	end
	return false
end

function DamageNumbers.Popup(pos: Vector3, text: string, color: Color3, opts: { [string]: any }?)
	local o = opts or {}
	local kind = o.Kind or "Alert"
	local style = (DamageNumbers.STYLES :: any)[kind] or DamageNumbers.STYLES.Alert
	if o.Merge and o.Amount and tryMerge(o.Target, kind, o.Amount) then
		return
	end
	spawnText(pos, text, color, o.Stroke or style.Stroke, o.Scale or style.Scale, o)
end

function DamageNumbers.Show(packet: { [string]: any }, viewer: { [string]: any }?)
	if not enabled then
		return
	end
	local style = DamageNumbers.Style(packet, viewer)
	if style == nil then
		return
	end
	local pos = packet.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	local target = packet.target
	if style.Merge and tryMerge(target, style.Kind, style.Amount) then
		return
	end
	local def = (DamageNumbers.STYLES :: any)[style.Kind]
	spawnText(pos, style.Text, style.Color, style.Stroke, style.Scale, {
		Target = target,
		Kind = style.Kind,
		Amount = style.Amount,
		Prefix = def.Prefix,
		Suffix = def.Suffix,
	})
end

function DamageNumbers.KRTick(target: any, amount: number, pos: Vector3)
	if not enabled or amount <= 0 then
		return
	end
	if tryMerge(target, "KR", amount) then
		return
	end
	local s = DamageNumbers.STYLES.KR
	spawnText(pos, DamageNumbers.Format(amount), s.Color, s.Stroke, s.Scale, {
		Target = target,
		Kind = "KR",
		Amount = amount,
		Life = 0.8,
		Rise = 1.2,
	})
end

function DamageNumbers.Clear()
	for i = #live, 1, -1 do
		recycle(live[i])
		live[i] = nil
	end
end

return DamageNumbers
