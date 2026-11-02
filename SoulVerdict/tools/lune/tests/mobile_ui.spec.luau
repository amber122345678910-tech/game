--!nocheck
-- Phone menu / HUD pass: UIRoot layout math (usable area under the Roblox top bar + notches, phone detection,
-- bleed, rebuild criterion that used to keep a stale portrait layout), the menu exclusivity rules (Hud.Visible
-- with an open menu, Hud.SetMenu on a mounted HUD), the Title's phone layout (absolute button rects resolved from
-- Scale/Offset + list/grid layouts: inside the canvas, no overlaps with each other, the logo, the player card, the
-- status chip or the disclaimer) and the LobbyHud phone boxes vs the touch controls.
local HUD = "src/client/UI/Hud"

-- device emulations: full viewport, CoreUISafeInsets insets (top bar 58 + notches / home indicator)
local DEVICES = {
	{ Name = "860x400 notch", W = 860, H = 400, L = 36, T = 58, R = 36, B = 0 },
	{ Name = "812x375 iPhone", W = 812, H = 375, L = 44, T = 58, R = 44, B = 21 },
	{ Name = "740x360 plain", W = 740, H = 360, L = 0, T = 58, R = 0, B = 0 },
	{ Name = "844x390 plain", W = 844, H = 390, L = 0, T = 58, R = 0, B = 0 },
}

local function setup(Loader)
	Loader.isServer = false
	Loader.quietWarnings = true
	local Strings = Loader.require("ReplicatedStorage.Shared.Strings")
	Strings.SetLanguage("en")
	local Themes = Loader.requirePath("src/client/UI/Themes")
	local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
	return Themes, UIRoot, Loader.roblox
end

local function layoutFor(UIRoot, roblox, d)
	local usable = roblox.Vector2.new(d.W - d.L - d.R, d.H - d.T - d.B)
	return UIRoot.ComputeLayout(usable, { Left = d.L, Top = d.T, Right = d.R, Bottom = d.B })
end

-- client-side suite: put the loader flags back even when a test fails (test hygiene)
local function restoringFlags(tests)
	for name, fn in tests do
		tests[name] = function(T, Loader)
			local isServer, quiet = Loader.isServer, Loader.quietWarnings
			local ok, err = pcall(fn, T, Loader)
			Loader.isServer, Loader.quietWarnings = isServer, quiet
			if not ok then
				error(err, 0)
			end
		end
	end
	return tests
end

-- absolute rects (design px) ---------------------------------------------------------------------------------
local function place(parent, gui)
	local size, pos, ap = gui.Size, gui.Position, gui.AnchorPoint
	local w = size.X.Scale * parent.w + size.X.Offset
	local h = size.Y.Scale * parent.h + size.Y.Offset
	return {
		x = parent.x + pos.X.Scale * parent.w + pos.X.Offset - ap.X * w,
		y = parent.y + pos.Y.Scale * parent.h + pos.Y.Offset - ap.Y * h,
		w = w,
		h = h,
	}
end

local function sortedVisible(gui)
	local kids = {}
	for i, c in gui:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(kids, { c, i })
		end
	end
	table.sort(kids, function(a, b)
		if a[1].LayoutOrder ~= b[1].LayoutOrder then
			return a[1].LayoutOrder < b[1].LayoutOrder
		end
		return a[2] < b[2]
	end)
	local out = {}
	for _, k in kids do
		table.insert(out, k[1])
	end
	return out
end

local function align(name, free)
	if name == "Center" then
		return free / 2
	elseif name == "Right" or name == "Bottom" then
		return free
	end
	return 0
end

-- out[gui] = rect for every GuiObject under `gui`; UIListLayout / UIGridLayout place their children
local function resolve(gui, rect, out)
	out[gui] = rect
	local list = gui:FindFirstChildOfClass("UIListLayout")
	local grid = gui:FindFirstChildOfClass("UIGridLayout")
	if list then
		local kids = sortedVisible(gui)
		local horizontal = list.FillDirection.Name == "Horizontal"
		local pad = list.Padding.Scale * (if horizontal then rect.w else rect.h) + list.Padding.Offset
		local rects, total = {}, 0
		for _, c in kids do
			local r = place({ x = 0, y = 0, w = rect.w, h = rect.h }, c)
			table.insert(rects, r)
			total += if horizontal then r.w else r.h
		end
		total += pad * math.max(#kids - 1, 0)
		local cursor = if horizontal
			then align(list.HorizontalAlignment.Name, rect.w - total)
			else align(list.VerticalAlignment.Name, rect.h - total)
		for i, c in kids do
			local r = rects[i]
			local x, y
			if horizontal then
				x, y = cursor, align(list.VerticalAlignment.Name, rect.h - r.h)
				cursor += r.w + pad
			else
				x, y = align(list.HorizontalAlignment.Name, rect.w - r.w), cursor
				cursor += r.h + pad
			end
			resolve(c, { x = rect.x + x, y = rect.y + y, w = r.w, h = r.h }, out)
		end
	elseif grid then
		local kids = sortedVisible(gui)
		local cw = grid.CellSize.X.Scale * rect.w + grid.CellSize.X.Offset
		local ch = grid.CellSize.Y.Scale * rect.h + grid.CellSize.Y.Offset
		local px = grid.CellPadding.X.Scale * rect.w + grid.CellPadding.X.Offset
		local py = grid.CellPadding.Y.Scale * rect.h + grid.CellPadding.Y.Offset
		local cols = math.max(1, math.floor((rect.w + px) / (cw + px)))
		cols = math.min(cols, math.max(#kids, 1))
		local rows = math.ceil(#kids / cols)
		local bw, bh = cols * cw + (cols - 1) * px, rows * ch + math.max(rows - 1, 0) * py
		local ox = align(grid.HorizontalAlignment.Name, rect.w - bw)
		local oy = align(grid.VerticalAlignment.Name, rect.h - bh)
		for i, c in kids do
			local col, row = (i - 1) % cols, (i - 1) // cols
			resolve(c, { x = rect.x + ox + col * (cw + px), y = rect.y + oy + row * (ch + py), w = cw, h = ch }, out)
		end
	else
		for _, c in gui:GetChildren() do
			if c:IsA("GuiObject") then
				resolve(c, place(rect, c), out)
			end
		end
	end
	return out
end

local function shown(gui, stop)
	local node = gui
	while node and node ~= stop do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

local function overlap(a, b, slack)
	local s = slack or 0
	return a.x < b.x + b.w - s and b.x < a.x + a.w - s and a.y < b.y + b.h - s and b.y < a.y + a.h - s
end

local function inside(r, canvas, slack)
	local s = slack or 0
	return r.x >= -s and r.y >= -s and r.x + r.w <= canvas.X + s and r.y + r.h <= canvas.Y + s
end

local function fmt(r)
	return ("(%d,%d %dx%d)"):format(r.x, r.y, r.w, r.h)
end

local function titleDeps(layout, phase)
	return {
		Layout = layout,
		State = {
			Round = function()
				return { Phase = phase or "Waiting", PhaseEndsAt = 0 }
			end,
			Now = function()
				return 1000
			end,
		},
		UI = {},
		Profile = false,
		PlayerName = "Itadori",
		Attrs = { Admin = true, StyleLab = true, MonsterChance = 1 },
		Device = "Touch",
	}
end

return restoringFlags({
	layoutUsesTheUsableAreaUnderTheTopBar = function(T, Loader)
		local _, UIRoot, roblox = setup(Loader)
		local V2 = roblox.Vector2.new
		-- unchanged reference points (other suites rely on them)
		local desk = UIRoot.ComputeLayout(V2(1920, 1080))
		T.near(desk.Scale, 1.2, 1e-3, "1080p scale")
		T.ok(not desk.Phone and not desk.Compact and not desk.Portrait, "1080p desktop")
		local phone = UIRoot.ComputeLayout(V2(844, 390))
		T.ok(phone.Phone and phone.Compact, "844x390 phone")
		-- the owner's phone: 860x400 with 36-pt camera-hole insets + the 58-pt top bar
		local l = layoutFor(UIRoot, roblox, DEVICES[1])
		T.ok(l.Phone and l.Compact, "usable 788x342 is a phone")
		T.near(l.Scale, 342 / 480, 1e-3, "fits 480 design px vertically")
		T.near(l.Canvas.Y, 480, 0.5, "canvas height")
		T.near(l.Canvas.X, 788 / l.Scale, 0.5, "canvas width = usable width")
		T.near(l.Bleed.Top, 58 / l.Scale, 1e-3, "bleed up to the screen top")
		T.near(l.Bleed.Left, 36 / l.Scale, 1e-3, "bleed into the notch strip")
		-- iPhone: the clamp keeps text readable; the canvas stays a hair under 480
		local ip = layoutFor(UIRoot, roblox, DEVICES[2])
		T.near(ip.Scale, 0.62, 1e-6, "scale floor")
		T.ok(ip.Canvas.Y > 470 and ip.Canvas.Y < 480, "iPhone canvas height " .. ip.Canvas.Y)
		-- a 1080p window loses the top bar but stays desktop
		local d2 = UIRoot.ComputeLayout(V2(1920, 1022), { Left = 0, Top = 58, Right = 0, Bottom = 0 })
		T.ok(not d2.Phone and d2.Canvas.Y >= 899, "1080p minus the top bar stays a 900-px desktop canvas")
		-- portrait (transient: the app boots portrait, the game runs landscape)
		local p = UIRoot.ComputeLayout(V2(354, 745))
		T.ok(p.Portrait and p.Phone, "portrait detected")
		T.near(p.Canvas.X, 820, 1, "portrait fits ~820 design px across")
		-- safe insets split
		local s = UIRoot.SafeInsets(V2(860, 400), V2(788, 342), 58)
		T.ok(s.Left == 36 and s.Right == 36 and s.Top == 58 and s.Bottom == 0, "notch + top bar split")
		local s2 = UIRoot.SafeInsets(V2(812, 375), V2(724, 296), 58)
		T.ok(s2.Top == 58 and s2.Bottom == 21 and s2.Left == 44, "home indicator at the bottom")
		local s3 = UIRoot.SafeInsets(V2(800, 600), V2(800, 600), 58)
		T.ok(s3.Top == 0 and s3.Bottom == 0, "no top bar -> no inset")
	end,

	staleLayoutIsRebuilt = function(T, Loader)
		local _, UIRoot, roblox = setup(Loader)
		local V2 = roblox.Vector2.new
		-- the bug: UI built while the phone was still portrait, then the phone rotated. The old rebuild test only
		-- compared the Phone / Compact flags, which are identical here -> the Title kept its portrait offsets
		-- (buttons below the screen) and the HUD its portrait canvas (camera-lock in the middle of the menu).
		local portrait = UIRoot.ComputeLayout(V2(354, 745))
		local landscape = UIRoot.ComputeLayout(V2(780, 302))
		T.ok(portrait.Phone == landscape.Phone, "same Phone flag")
		T.ok(not UIRoot.SameLayout(portrait, landscape), "rotation needs a rebuild")
		T.ok(UIRoot.SameLayout(landscape, UIRoot.ComputeLayout(V2(780.4, 302.2))), "sub-pixel jitter does not")
		T.ok(not UIRoot.SameLayout(landscape, UIRoot.ComputeLayout(V2(780, 360))), "top bar shown/hidden does")
		T.ok(UIRoot.SameLayout(nil, nil) and not UIRoot.SameLayout(landscape, nil), "nil handling")
		-- LayoutChanged is a connectable signal
		local conn = UIRoot.LayoutChanged:Connect(function() end)
		T.ok(conn.Connected and type(conn.Disconnect) == "function", "Connect")
		conn.Disconnect()
		T.ok(not conn.Connected, "Disconnect")
	end,

	layersUseCoreUiInsets = function(T, Loader)
		local _, UIRoot, roblox = setup(Loader)
		local Enum, Instance, UDim2 = roblox.Enum, roblox.Instance, roblox.UDim2
		local layout = layoutFor(UIRoot, roblox, DEVICES[1])
		local gui, root, scale = UIRoot.CreateLayer("Menu", 10, layout, Enum.ScreenInsets.CoreUISafeInsets)
		T.eq(gui.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets, "below the Roblox top bar")
		T.eq(gui.IgnoreGuiInset, false, "IgnoreGuiInset=true would downgrade to DeviceSafeInsets")
		T.eq(gui.ClipToDeviceSafeArea, false, "backdrops may bleed into notch strips")
		T.near(scale.Scale, layout.Scale, 1e-6, "design scale")
		T.near(root.Size.X.Scale, 1 / layout.Scale, 1e-6, "root in design px")
		local preview = UIRoot.CreateLayer("Preview", 10, layout)
		T.eq(preview.IgnoreGuiInset, true, "offline previews keep the full-bleed root")
		-- Common.Bleed stretches a full-screen background over the insets
		local Common = Loader.requirePath("src/client/UI/Screens/Common")
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		Common.Bleed(bg, layout)
		T.ok(bg.Position.Y.Offset <= -layout.Bleed.Top, "bleed covers the top bar")
		T.ok(bg.Size.X.Offset >= layout.Bleed.Left + layout.Bleed.Right, "bleed covers both notch strips")
	end,

	menuExclusivityRules = function(T, Loader)
		setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local Mock = Loader.requirePath(HUD .. "/Mock")
		T.ok(Hud.MenuHidesHud("Title") and Hud.MenuHidesHud("Admin") and Hud.MenuHidesHud("Settings"), "menus own the screen")
		T.ok(not Hud.MenuHidesHud("StyleLab"), "Style Lab previews the HUD live")
		T.ok(not Hud.MenuHidesHud(nil) and not Hud.MenuHidesHud(""), "no menu")
		-- lobby on a phone, local body (camera-lock / emote / abilities apply)
		local s = Mock.Scenario("LobbyWaiting")
		s.Device = "Touch"
		s.Me = Mock.Unit("Determination", "Itadori", { IsLocal = true })
		for _, name in { "LobbyHud", "MobileControls", "EmoteWheel", "RoundHud", "AdminButton" } do
			T.ok(Hud.Visible(name, s), name .. " visible in the lobby with no menu")
		end
		s.Menu = "Title"
		for _, entry in Hud.PIECES do
			local expect = entry.Name == "Nameplates"
			T.eq(Hud.Visible(entry.Name, s), expect, entry.Name .. " under the Title")
		end
		T.ok(not Hud.Visible("AdminButton", s), "admin button under the Title")
		s.Menu = "StyleLab"
		T.ok(Hud.Visible("LobbyHud", s) and Hud.Visible("RoundHud", s), "HUD stays under Style Lab")
		T.ok(
			not Hud.Visible("MobileControls", s) and not Hud.Visible("EmoteWheel", s) and not Hud.Visible("AdminButton", s),
			"touch controls never sit under a menu"
		)
		-- in a round: Settings over the fight hides everything but nameplates
		local r = Mock.Scenario("Touch")
		r.Menu = "Settings"
		T.ok(not Hud.Visible("RoundHud", r) and not Hud.Visible("MobileControls", r) and not Hud.Visible("TopStrip", r), "round HUD under Settings")
		r.Menu = nil
		T.ok(Hud.Visible("MobileControls", r) and Hud.Visible("TopStrip", r), "back after closing")
		-- touch controls only where they apply
		local intro = Mock.Scenario("Intro")
		intro.Device = "Touch"
		T.ok(not Hud.Visible("MobileControls", intro), "no touch controls during the intro")
		local spec = Mock.Scenario("Spectate")
		spec.Device = "Touch"
		T.ok(not Hud.Visible("MobileControls", spec), "no touch controls while spectating")
		-- the offline composite honours the menu too
		local Themes = Loader.requirePath("src/client/UI/Themes")
		local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
		local snap = Mock.Scenario("LobbyWaiting")
		snap.Device = "Touch"
		snap.Me = Mock.Unit("Determination", "Itadori", { IsLocal = true })
		snap.Menu = "Title"
		local h = Hud.Create(Themes.Get("Classic"), {
			Snapshot = snap,
			Layout = UIRoot.ComputeLayout(Loader.roblox.Vector2.new(844, 332)),
			Backdrop = false,
		})
		T.ok(h.Pieces.LobbyHud == nil and h.Pieces.MobileControls == nil, "composite: no lobby HUD under the Title")
		h.Destroy()
	end,

	mountedHudFollowsTheMenu = function(T, Loader)
		local _, UIRoot, roblox = setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local layout = UIRoot.ComputeLayout(roblox.Vector2.new(844, 332))
		local frame = roblox.Instance.new("Frame")
		local h = Hud.Mount(frame, { Layout = layout, State = {}, Input = {}, Combat = {}, UI = {} })
		T.ok(type(h.SetMenu) == "function", "HudHandle.SetMenu")
		local lobby = h.Pieces.LobbyHud
		if T.ok(lobby ~= nil, "LobbyHud mounted") then
			local before = lobby.Root.Visible
			h.SetMenu("Title")
			T.ok(not lobby.Root.Visible, "hidden while the Title is open")
			h.SetMenu(nil)
			T.eq(lobby.Root.Visible, before, "back when the menu closes")
			h.SetMenu("StyleLab")
			T.eq(lobby.Root.Visible, before, "Style Lab keeps it")
			h.SetMenu(nil)
		end
		h.Destroy()
	end,

	titleFitsPhonesWithoutOverlaps = function(T, Loader)
		local Themes, UIRoot, roblox = setup(Loader)
		local Title = Loader.requirePath("src/client/UI/Screens/Title")
		for _, d in DEVICES do
			local layout = layoutFor(UIRoot, roblox, d)
			for _, themeId in { "Classic", "Royal", "Void", "Fell" } do
				local label = d.Name .. " " .. themeId
				local handle = Title.Create(Themes.Get(themeId), titleDeps(layout, "Waiting"))
				local canvas = layout.Canvas
				local rects = resolve(handle.Root, { x = 0, y = 0, w = canvas.X, h = canvas.Y }, {})
				local buttons, named = {}, {}
				for gui, r in rects do
					if shown(gui, handle.Root) then
						if string.sub(gui.Name, 1, 5) == "Menu_" and gui:IsA("GuiButton") then
							table.insert(buttons, { gui.Name, r })
						elseif gui.Name == "Logo" or gui.Name == "PlayerCard" or gui.Name == "StatusHolder" or gui.Name == "Disclaimer" then
							named[gui.Name] = r
						end
					end
				end
				-- PLAY, PRACTICE (waiting), LOADOUT, SHOP, QUESTS, PROFILE, SETTINGS, STYLE LAB, ADMIN
				T.eq(#buttons, 9, label .. ": every entry is on screen")
				for _, b in buttons do
					T.ok(inside(b[2], canvas, 0.5), label .. ": " .. b[1] .. " inside the canvas " .. fmt(b[2]))
					T.ok(b[2].h >= 38, label .. ": " .. b[1] .. " is a thumb-sized target")
					for name, r in named do
						T.ok(not overlap(b[2], r, 0.5), label .. ": " .. b[1] .. " overlaps " .. name .. " " .. fmt(b[2]) .. " " .. fmt(r))
					end
				end
				for i = 1, #buttons do
					for j = i + 1, #buttons do
						T.ok(not overlap(buttons[i][2], buttons[j][2], 0.5), label .. ": " .. buttons[i][1] .. " overlaps " .. buttons[j][1])
					end
				end
				T.ok(named.Logo and named.PlayerCard and named.Disclaimer, label .. ": logo, card, disclaimer")
				if named.Logo and named.PlayerCard then
					T.ok(not overlap(named.Logo, named.PlayerCard), label .. ": logo vs player card")
					T.ok(inside(named.Logo, canvas) and inside(named.PlayerCard, canvas), label .. ": header inside")
				end
				handle.Destroy()
			end
		end
		-- outside the waiting phase PRACTICE is gone and the column collapses
		local layout = layoutFor(UIRoot, roblox, DEVICES[1])
		local handle = Title.Create(Themes.Get("Classic"), titleDeps(layout, "Round"))
		local practice = handle.Root:FindFirstChild("Menu_Practice", true)
		T.ok(practice and not practice.Visible, "PRACTICE hidden during a round")
		handle.Destroy()
		-- gated entries stay hidden without the attributes
		local deps = titleDeps(layout, "Waiting")
		deps.Attrs = { MonsterChance = 0.2 }
		local h2 = Title.Create(Themes.Get("Classic"), deps)
		local admin = h2.Root:FindFirstChild("Menu_Admin", true)
		local lab = h2.Root:FindFirstChild("Menu_StyleLab", true)
		T.ok(admin and not admin.Visible and lab and not lab.Visible, "ADMIN / STYLE LAB need their attributes")
		h2.Destroy()
	end,

	titleDesktopFitsAboveTheDisclaimer = function(T, Loader)
		local Themes, UIRoot, roblox = setup(Loader)
		local Title = Loader.requirePath("src/client/UI/Screens/Title")
		for _, size in { { 1920, 1022 }, { 1366, 710 }, { 2560, 1022 } } do
			local layout = UIRoot.ComputeLayout(roblox.Vector2.new(size[1], size[2]))
			local handle = Title.Create(Themes.Get("Classic"), titleDeps(layout, "Waiting"))
			local canvas = layout.Canvas
			local rects = resolve(handle.Root, { x = 0, y = 0, w = canvas.X, h = canvas.Y }, {})
			local label = size[1] .. "x" .. size[2]
			-- (Lune hands out a new userdata per Instance access: look rects up by iterating, not by key)
			local disc, menuRect, scrolling = nil, nil, false
			local buttons = {}
			for gui, r in rects do
				if gui.Name == "Disclaimer" then
					disc = r
				elseif gui.Name == "Menu" then
					menuRect, scrolling = r, gui:IsA("ScrollingFrame")
				elseif string.sub(gui.Name, 1, 5) == "Menu_" and gui:IsA("GuiButton") and shown(gui, handle.Root) then
					table.insert(buttons, { gui.Name, r })
				end
			end
			if T.ok(disc ~= nil and menuRect ~= nil, label .. ": disclaimer + menu") then
				if scrolling then
					T.ok(menuRect.y + menuRect.h <= disc.y + 1, label .. ": scrolling menu above the disclaimer")
				else
					T.eq(#buttons, 9, label .. ": every entry")
					for _, b in buttons do
						T.ok(b[2].y + b[2].h <= disc.y + 1, label .. ": " .. b[1] .. " above the disclaimer " .. fmt(b[2]))
					end
				end
			end
			handle.Destroy()
		end
	end,

	lobbyHudPhoneBoxesClearTheTouchControls = function(T, Loader)
		local Themes, UIRoot, roblox = setup(Loader)
		local LobbyHud = Loader.requirePath(HUD .. "/LobbyHud")
		local MobileControls = Loader.requirePath(HUD .. "/MobileControls")
		for _, d in DEVICES do
			local layout = layoutFor(UIRoot, roblox, d)
			local canvas = layout.Canvas
			for _, battle in { true, false } do
				local label = d.Name .. (if battle then " Battle" else " Modern")
				local rects = LobbyHud.PhoneRects(canvas, LobbyHud.PhoneTop(true, battle))
				local boxes = {}
				for name, r in rects do
					local box = { x = r.X, y = r.Y, w = r.W, h = r.H }
					boxes[name] = box
					T.ok(inside(box, canvas), label .. ": " .. name .. " inside " .. fmt(box))
				end
				-- the RoundHud compact stats own the top-left corner on touch phones
				local stats = { x = 0, y = 0, w = 330, h = if battle then 50 else 92 }
				-- the touch controls: ability cluster (lobby bodies always use the equipped HUMAN kit), camera lock +
				-- emote toggle on the right edge
				local controls = {}
				for action, p in MobileControls.Positions("Human", canvas) do
					controls[action] = { x = p.X - p.Size / 2, y = p.Y - p.Size / 2, w = p.Size, h = p.Size }
				end
				controls.CameraLock = { x = canvas.X - 63, y = math.floor(canvas.Y * 0.27) - 23, w = 46, h = 46 }
				controls.Emote = { x = canvas.X - 63, y = math.floor(canvas.Y * 0.27) + 35, w = 46, h = 46 }
				local names = {}
				for name in boxes do
					table.insert(names, name)
				end
				for i, a in names do
					T.ok(not overlap(boxes[a], stats), label .. ": " .. a .. " under the stats")
					for j = i + 1, #names do
						local b = names[j]
						-- Practice hides outside Waiting, Vote only shows in Intermission: they may never overlap anyway
						T.ok(not overlap(boxes[a], boxes[b]), label .. ": " .. a .. " overlaps " .. b)
					end
					for cname, c in controls do
						T.ok(not overlap(boxes[a], c), label .. ": " .. a .. " covers the touch control " .. cname)
					end
				end
				-- the left column stays out of the thumbstick corner
				T.ok(boxes.Chances.y + boxes.Chances.h <= canvas.Y * 0.62, label .. ": chance strip above the thumbstick zone")
			end
			-- builds at phone size with the practice call-to-action
			local s = Loader.requirePath(HUD .. "/Mock").Scenario("LobbyWaiting")
			s.Device = "Touch"
			local h = LobbyHud.Create(Themes.Get("Classic"), { Layout = layout, Snapshot = s, Hud = "Battle" })
			local cta = h.Root:FindFirstChild("PracticeCta")
			T.ok(cta and cta.Visible and cta:FindFirstChild("Practice"), d.Name .. ": PRACTICE call-to-action while waiting")
			local menuButton = h.Root:FindFirstChild("Title", true)
			T.ok(menuButton ~= nil, d.Name .. ": MENU button (touch has no Menu key)")
			s.Phase = "Intermission"
			h.Update(s)
			T.ok(not cta.Visible, d.Name .. ": no call-to-action outside Waiting")
			h.Destroy()
		end
	end,

	hudBackdropsBleedAndAdminSpot = function(T, Loader)
		local Themes, UIRoot, roblox = setup(Loader)
		local Hud = Loader.requirePath(HUD)
		local Mock = Loader.requirePath(HUD .. "/Mock")
		local layout = layoutFor(UIRoot, roblox, DEVICES[1])
		-- intro backdrop and death dim reach the screen edges; centred content does not move
		local intro = Mock.Scenario("Intro")
		local h = Hud.Create(Themes.Get("Classic"), { Snapshot = intro, Layout = layout, Backdrop = false, Pieces = { "IntroSplash" } })
		local splash = h.Pieces.IntroSplash
		if T.ok(splash ~= nil, "IntroSplash built") then
			local backdrop = splash.Root:FindFirstChild("Backdrop")
			T.ok(backdrop and backdrop.Position.Y.Offset <= -layout.Bleed.Top, "intro backdrop covers the top-bar strip")
			T.ok(backdrop and backdrop.Size.X.Offset >= layout.Bleed.Left + layout.Bleed.Right, "and the notch strips")
		end
		h.Destroy()
		local dead = Mock.Scenario("Dead")
		local h2 = Hud.Create(Themes.Get("Classic"), { Snapshot = dead, Layout = layout, Backdrop = false, Pieces = { "DeathScreen" } })
		local death = h2.Pieces.DeathScreen
		if T.ok(death ~= nil, "DeathScreen built") then
			local dim = death.Root:FindFirstChild("Dim")
			T.ok(dim and dim.Position.Y.Offset < 0, "death dim bled")
			local heart = death.Root:FindFirstChild("Heart")
			T.ok(heart and heart.Position.Y.Offset == 0, "content untouched")
		end
		h2.Destroy()
		-- no insets (desktop previews) -> nothing changes
		local plain = UIRoot.ComputeLayout(roblox.Vector2.new(1920, 1080))
		local frame = roblox.Instance.new("Frame")
		local bd = roblox.Instance.new("Frame")
		bd.Name = "Backdrop"
		bd.Size = roblox.UDim2.fromScale(1, 1)
		bd.Parent = frame
		Hud.BleedBackdrops(frame, plain)
		T.eq(bd.Position, roblox.UDim2.new(), "no bleed without insets")
		-- the admin pill sits in the top-bar strip, right of the core buttons
		local pos, anchor = Hud.AdminButtonSpot(layout, 190)
		if T.ok(pos ~= nil and anchor ~= nil, "spot inside the strip") then
			T.ok(pos.Y.Offset < 0 and pos.Y.Offset > -layout.Bleed.Top, "vertically inside the top bar")
			T.ok(pos.X.Offset * layout.Scale + 36 >= 190, "right of the Roblox buttons")
			T.eq(anchor.Y, 0.5, "centred on the strip")
		end
		T.eq(Hud.AdminButtonSpot(plain, nil), nil, "no strip -> the button's own placement")
	end,

	practiceIsWired = function(T, Loader)
		setup(Loader)
		local LobbyHud = Loader.requirePath(HUD .. "/LobbyHud")
		local Themes = Loader.requirePath("src/client/UI/Themes")
		local UIRoot = Loader.requirePath("src/client/UI/UIRoot")
		local requests = {}
		local s = Loader.requirePath(HUD .. "/Mock").Scenario("LobbyWaiting")
		local h = LobbyHud.Create(Themes.Get("Classic"), {
			Layout = UIRoot.ComputeLayout(Loader.roblox.Vector2.new(1920, 1080)),
			Snapshot = s,
			UI = {
				Open = function()
					return nil -- "Practice" is not a screen: the old handler stopped here and nothing happened
				end,
			},
			State = {
				Request = function(action, data)
					table.insert(requests, { action, data })
				end,
			},
		})
		T.ok(h.Root:FindFirstChild("Practice", true) ~= nil, "desktop practice button")
		h.Destroy()
		-- the request path is exercised through the handler the button uses (Motion events are offline no-ops)
		local UIController = Loader.requirePath("src/client/Controllers/UIController")
		T.ok(type(UIController.Practice) == "function", "UIController.Practice")
		local _ = requests
	end,
})
