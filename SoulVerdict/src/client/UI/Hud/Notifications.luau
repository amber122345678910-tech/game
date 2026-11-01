--!strict
-- Hud/Notifications: themed toasts (UIKit.Toast) on the right side for StateController.Notify(key, args, style)
-- and HUD-generated messages. Max 3 visible, 4.5 s each (newest on top).
--   Notifications.Create(theme, deps) -> { Root, Push(text, kind?, icon?, duration?), Notify(key, args?, style?),
--                                         Update(snapshot), Tick(now), Clear(), Destroy }
--   kind: "Info" | "Success" | "Warning" | "Danger" | "Reward" (Notify's style is mapped onto these)
local Style = require(script.Parent.Style)
local UIKit = require(script.Parent.Parent.UIKit)

local Notifications = {}

local STYLE_KIND = {
	info = "Info",
	success = "Success",
	good = "Success",
	warning = "Warning",
	warn = "Warning",
	error = "Danger",
	danger = "Danger",
	bad = "Danger",
	reward = "Reward",
	gold = "Reward",
}

function Notifications.Create(theme: any, deps: any): any
	local _skin, layout, root = Style.Context(theme, deps, "Notifications")
	local phone = layout.Phone
	local width = if phone then 270 else 350
	-- desktop: bottom-right corner (free in every HUD layout); phone: top centre under the timer strip
	local holder = Style.Frame({
		Name = "Toasts",
		AnchorPoint = if phone then Vector2.new(0.5, 0) else Vector2.new(1, 1),
		Position = if phone then UDim2.new(0.5, 0, 0, 132) else UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(width, 400),
		Parent = root,
	})
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = if phone then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Right
	l.VerticalAlignment = if phone then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	l.Padding = UDim.new(0, 8)
	l.Parent = holder
	type Item = { Root: GuiObject, Expires: number }
	local items: { Item } = {}
	local order = 0
	local clock = 0

	local function push(text: string, kind: string?, icon: string?, duration: number?)
		order += if phone then -1 else 1
		local toast =
			UIKit.Toast(theme, { Text = text, Kind = kind or "Info", Icon = icon, Width = width, LayoutOrder = order })
		toast.Root.Parent = holder
		local d = duration or 4.5
		table.insert(items, 1, { Root = toast.Root, Expires = if clock > 0 then clock + d else -d })
		while #items > 3 do
			local old = table.remove(items) :: Item
			old.Root:Destroy()
		end
	end

	local function notify(key: string, args: { any }?, style: string?)
		local text = Style.L(key, table.unpack(args or {}))
		local kind = if type(style) == "string" then (STYLE_KIND[string.lower(style)] or "Info") else "Info"
		push(text, kind, nil, nil)
	end

	local function clear()
		for _, item in items do
			item.Root:Destroy()
		end
		table.clear(items)
	end

	local function tick(now: number)
		clock = now
		for i = #items, 1, -1 do
			if items[i].Expires < 0 then
				items[i].Expires = now - items[i].Expires
			end
			if now > items[i].Expires then
				items[i].Root:Destroy()
				table.remove(items, i)
			end
		end
	end

	local function update(s: { [string]: any })
		clock = s.Now or clock
		if not Style.Live() and s.Toasts then
			clear()
			for _, t in s.Toasts do
				push(t.Text, t.Kind, t.Icon, 1e9)
			end
		end
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Push = push,
		Notify = notify,
		Update = update,
		Tick = tick,
		Clear = clear,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return Notifications
