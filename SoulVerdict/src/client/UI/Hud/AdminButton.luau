--!strict
-- Hud/AdminButton: the small crown "ADMIN" pill that opens the admin panel (deps.UI.Open("Admin"), Screens/Admin).
-- Shown only while Players.LocalPlayer:GetAttribute("Admin") == true (set by AdminService; changes are followed
-- live). The server bumps the "AdminOpen" attribute for the chat command "/admin": that opens the panel too.
-- Placement: top-left, just BELOW the Roblox top-bar buttons (they draw over IgnoreGuiInset layers), so it never sits
-- under them on phones or PCs. The bar's bottom comes from GuiService.TopbarInset at runtime (58 pt fallback) and is
-- converted into this layer's design px, so it stays right if the layer's insets change. Touch target >= 44 pt.
-- The HUD owner can move it: deps.AdminButtonPosition (UDim2) [+ deps.AdminButtonAnchor (Vector2)] or
-- handle.SetPosition(position, anchor?) (a fixed position stops the automatic top-bar placement).
--   AdminButton.Create(theme, deps) -> { Root, Button, Update(snapshot), SetPosition(pos, anchor?), Destroy }   (no Tick:
--       nothing per frame; Update(snapshot) only re-checks the Admin attribute)
--   AdminButton.Footprint(layout, topbarBottomPt?) -> (Vector2 topLeft, Vector2 size)   default rect in design px (pure)
--   deps: UI (UIController: Open), Layout, Hud / Skin (HUD style)   (+ offline: Attrs = { Admin = true })
local Style = require(script.Parent.Style)

local AdminButton = {}

local TOPBAR_FALLBACK = 58 -- pt: height of the Roblox top bar (GuiService:GetGuiInset().Y)
local GAP_BELOW = 6

local function scaleOf(layout: any): number
	local s = if type(layout) == "table" then layout.Scale else nil
	return if type(s) == "number" and s > 0 then s else 1
end

-- Default rect (design px of the HUD layer) for a given top-bar bottom (points).
function AdminButton.Footprint(layout: any, topbarBottomPt: number?): (Vector2, Vector2)
	local scale = scaleOf(layout)
	local phone = type(layout) == "table" and layout.Phone == true
	local h = math.max(if phone then 44 else 36, math.ceil(44 / scale))
	local w = math.floor(h * 2.55)
	local x = if phone then 10 else 16
	local y = math.ceil((topbarBottomPt or TOPBAR_FALLBACK) / scale) + GAP_BELOW
	return Vector2.new(x, y), Vector2.new(w, h)
end

local function localPlayer(): any
	local ok, player = pcall(function()
		return game:GetService("Players").LocalPlayer
	end)
	return if ok and typeof(player) == "Instance" then player else nil
end

function AdminButton.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "AdminButton")
	local d = if type(deps) == "table" then deps else {}
	local C = skin.C
	local battle = skin.Battle
	local pos, size = AdminButton.Footprint(layout)
	local connections: { RBXScriptConnection } = {}
	local fixed = typeof(d.AdminButtonPosition) == "UDim2"

	local pill = Style.Box(skin, {
		Name = "Pill",
		Border = C.Gold,
		Stroke = if battle then 3 else 1.5,
		Corner = if battle then nil else UDim.new(0.5, 0),
		Position = if fixed then d.AdminButtonPosition else UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		Parent = root,
	})
	if fixed and typeof(d.AdminButtonAnchor) == "Vector2" then
		pill.AnchorPoint = d.AdminButtonAnchor
	end
	local iconSize = math.floor(size.Y * 0.56)
	local crown = Style.Icon("Crown", C.Gold, iconSize)
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.Position = UDim2.new(0, math.floor(size.Y * 0.55), 0.5, 0)
	crown.Parent = pill
	local labelX = math.floor(size.Y * 0.55 + iconSize * 0.5 + 6)
	local label = Style.Text(skin, {
		Name = "Label",
		Text = Style.L("admin.button"),
		Role = "Label",
		TextSize = math.max(skin.Size.Label, math.floor(size.Y * 0.34)),
		Color = C.Gold,
		Position = UDim2.fromOffset(labelX, 0),
		Parent = pill,
	})
	label.Size = UDim2.new(1, -(labelX + 8), 1, 0)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = label.TextSize
	constraint.MinTextSize = 8
	constraint.Parent = label

	-- the whole pill is the hit area
	local button = Instance.new("TextButton")
	button.Name = "Hit"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 5
	button.Parent = pill

	local function open()
		local ui = d.UI
		if ui and type(ui.Open) == "function" then
			pcall(ui.Open, "Admin")
		end
	end

	local player = localPlayer()
	local function isAdmin(): boolean
		if type(d.Attrs) == "table" and d.Attrs.Admin ~= nil then
			return d.Attrs.Admin == true
		end
		return player ~= nil and player:GetAttribute("Admin") == true
	end
	local function refresh()
		pill.Visible = isAdmin()
	end
	refresh()

	-- keep the pill just under the Roblox top bar (TopbarInset is in screen points; this layer is UIScale'd)
	local function place()
		if fixed then
			return
		end
		local bottomPt = TOPBAR_FALLBACK
		local okInset, inset = pcall(function()
			return game:GetService("GuiService").TopbarInset
		end)
		if okInset and typeof(inset) == "Rect" and inset.Max.Y > 0 then
			bottomPt = inset.Max.Y
		end
		local okPos, absolute = pcall(function()
			return root.AbsolutePosition
		end)
		-- points; > 0 when the layer already starts below the bar (e.g. CoreUISafeInsets)
		local layerTop = if okPos and typeof(absolute) == "Vector2" then absolute.Y else 0
		local p = AdminButton.Footprint(layout, math.max(0, bottomPt - layerTop))
		pill.Position = UDim2.fromOffset(p.X, p.Y)
	end
	place()

	if player then
		table.insert(
			connections,
			button.Activated:Connect(function()
				if isAdmin() then
					open()
				end
			end)
		)
		table.insert(connections, player:GetAttributeChangedSignal("Admin"):Connect(refresh))
		local seen = player:GetAttribute("AdminOpen")
		table.insert(
			connections,
			player:GetAttributeChangedSignal("AdminOpen"):Connect(function()
				local value = player:GetAttribute("AdminOpen")
				if value ~= seen then
					seen = value
					if isAdmin() then
						open()
					end
				end
			end)
		)
		pcall(function()
			local GuiService = game:GetService("GuiService")
			table.insert(connections, GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place))
		end)
		table.insert(connections, root:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
	end

	return {
		Root = root,
		Button = button,
		Update = function(_snapshot: any)
			refresh()
		end,
		SetPosition = function(position: UDim2, anchor: Vector2?)
			fixed = true
			pill.Position = position
			if anchor then
				pill.AnchorPoint = anchor
			end
		end,
		Destroy = function()
			for _, conn in connections do
				conn:Disconnect()
			end
			table.clear(connections)
			root:Destroy()
		end,
	}
end

AdminButton.TopbarFallback = TOPBAR_FALLBACK

return AdminButton
