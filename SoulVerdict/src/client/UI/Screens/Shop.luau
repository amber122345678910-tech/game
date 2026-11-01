--!strict
-- Screens/Shop: spend earned G (no Robux anywhere, SPEC §1.6).
--   * Daily rotation: profile.ShopToday (server data; any of the shapes below), else Progression/Shop
--     (Today/DailyItems/Rotation(day)), else a deterministic local pick of Config.Shop.DailySkins skins for the
--     UTC day (no discounts in that fallback). One item is FEATURED (bigger tile, discount badge when the data
--     carries one). Countdown to the next UTC day.
--   * All skins by kit: kit rail (owned counts) + skin tiles with rarity colours, OWNED / EQUIPPED states,
--     mastery locks, kit unlock tile for locked kits. G balance in the header.
-- ShopToday shapes accepted: { Day?, Items = {Item} } | {Item};  Item = "kitId:skinId" |
--   { KitId|Kit|kitId, SkinId|Skin|skinId, Price?|price?, Discount?|discount? (percent), Featured?|featured? }
--
--   Shop.Create(theme, deps) -> { Root, Destroy, DefaultSelection, OnAction(action) }
--   deps: State, UI, Layout (+ offline: Profile, Kit = rail selection, Tab = "Daily"|"All" on phones, Now)
-- Requests: Buy {kind="Skin", kitId, skinId} | {kind="Kit", kitId}; EquipSkin {kitId, skinId}.

local Themes = require(script.Parent.Parent.Themes)
local UIKit = require(script.Parent.Parent.UIKit)
local Icons = require(script.Parent.Parent.Icons)
local Motion = require(script.Parent.Parent.Motion)
local Common = require(script.Parent.Common)

type Theme = Themes.Theme

local Shop = {}

local L = Common.L
local pick = Common.Pick
local frame = Common.Frame

type Offer = { kit: any, skin: any, price: number, base: number, discount: number, featured: boolean }

-- daily rotation ----------------------------------------------------------------------------------------
local function toOffer(kits: any, item: any): Offer?
	local kitId, skinId, price, discount, featured
	if type(item) == "string" then
		kitId, skinId = string.match(item, "^([^:]+):(.+)$")
	elseif type(item) == "table" then
		kitId = item.KitId or item.Kit or item.kitId or item.kit
		skinId = item.SkinId or item.Skin or item.skinId or item.skin
		price = item.Price or item.price
		discount = item.Discount or item.discount
		featured = item.Featured or item.featured
	end
	if type(kitId) ~= "string" or type(skinId) ~= "string" then
		return nil
	end
	local kit = kits.Get(kitId)
	local skin = kit and kits.Skin(kitId, skinId)
	if kit == nil or skin == nil then
		return nil
	end
	local base = skin.Price or 0
	local pct = tonumber(discount) or 0
	local final = tonumber(price) or math.floor(base * (1 - pct / 100) + 0.5)
	if pct == 0 and base > 0 and final < base then
		pct = math.floor((1 - final / base) * 100 + 0.5)
	end
	return { kit = kit, skin = skin, price = final, base = base, discount = pct, featured = featured == true }
end

local function localRotation(kits: any, day: number, count: number): { Offer }
	local pool: { { any } } = {}
	for _, kit in kits.All() do
		for _, skin in kit.Skins do
			if (skin.Price or 0) > 0 and skin.Mastery == nil then
				table.insert(pool, { kit, skin })
			end
		end
	end
	local out: { Offer } = {}
	local seed = (day * 1103515245 + 12345) % 2147483648
	for _ = 1, math.min(count, #pool) do
		seed = (seed * 1103515245 + 12345) % 2147483648
		local idx = (seed % #pool) + 1
		local entry = table.remove(pool, idx) :: { any }
		table.insert(out, { kit = entry[1], skin = entry[2], price = entry[2].Price, base = entry[2].Price, discount = 0, featured = false })
	end
	return out
end

local function dailyOffers(deps: any, profile: any, kits: any): { Offer }
	local config = Common.Config()
	local count = (config and config.Shop and config.Shop.DailySkins) or 4
	local day = math.floor(Common.Now(deps) / 86400)
	local raw: any = profile and profile.ShopToday
	if raw == nil then
		local ok, result = Common.Call(Common.Progression("Shop"), { "Today", "DailyItems", "Rotation", "Daily" }, day)
		if ok then
			raw = result
		end
	end
	local offers: { Offer } = {}
	if type(raw) == "table" then
		local items = raw.Items or raw.items or raw
		if type(items) == "table" then
			for _, item in items do
				local o = toOffer(kits, item)
				if o then
					table.insert(offers, o)
				end
			end
		end
	end
	if #offers == 0 then
		offers = localRotation(kits, day, count)
	end
	local anyFeatured = false
	for _, o in offers do
		anyFeatured = anyFeatured or o.featured
	end
	if not anyFeatured and offers[1] then
		-- the best deal (or the priciest item) is featured
		local best = offers[1]
		for _, o in offers do
			if o.discount > best.discount or (o.discount == best.discount and o.base > best.base) then
				best = o
			end
		end
		best.featured = true
	end
	table.sort(offers, function(a, b)
		if a.featured ~= b.featured then
			return a.featured
		end
		return a.base > b.base
	end)
	return offers
end

function Shop.Create(theme: Theme, deps: any): any
	local d = deps or {}
	local c = theme.Colors
	local kits = Common.Kits()
	local screen = Common.Screen(theme, d, {
		Name = "Shop",
		Title = L("scr.shop.title"),
		Subtitle = L("scr.shop.subtitle"),
		Icon = "Shop",
	})
	local root, body, bag = screen.Root, screen.Body, screen.Bag
	local phone = screen.Phone
	local canvas = screen.Canvas
	local bodyW = canvas.X - screen.Margin * 2
	local bodyH = body.Size.Y.Offset + canvas.Y * body.Size.Y.Scale
	local profile = Common.Profile(d)
	local selectedKit: string = d.Kit or Common.EquippedKit(profile, "Monster") or "ClassicSans"
	local phoneTab: string = d.Tab or "Daily"
	local modal: any = nil
	local pendingSkin: { [string]: string } = {}
	local defaultSel: GuiObject? = nil

	local function closeModal()
		if modal then
			modal.Destroy()
			modal = nil
		end
	end

	local function notice(titleText: string, text: string)
		closeModal()
		modal = UIKit.Modal(theme, {
			Title = titleText,
			PanelSize = UDim2.fromOffset(if phone then 500 else 580, if phone then 220 else 250),
			ZIndex = 60,
			OnClose = closeModal,
			Buttons = { { Text = L("common.ok"), Variant = "Primary", Width = 160, OnActivated = closeModal } },
		})
		UIKit.Label(theme, { Text = text, Role = "Body", Dialogue = true, Wrap = true, YAlign = "Top", Size = UDim2.fromScale(1, 1), Parent = modal.Content })
		modal.Root.Parent = root
	end

	local function buy(kit: any, skin: any?, price: number)
		local gold = profile and profile.Gold or 0
		local name = if skin then pick(skin.Name) else pick(kit.Name)
		if gold < price then
			notice(L("scr.shop.confirmTitle", name), L("scr.shop.notEnough", Common.Num(price - gold)))
			return
		end
		closeModal()
		local text = if skin then L("scr.shop.confirmText", Common.Num(price), pick(skin.Name), pick(kit.Name)) else L("scr.shop.confirmKit", Common.Num(price), pick(kit.Name))
		modal = UIKit.Modal(theme, {
			Title = L("scr.shop.confirmTitle", name),
			PanelSize = UDim2.fromOffset(if phone then 520 else 620, if phone then 230 else 270),
			ZIndex = 60,
			OnClose = closeModal,
			Buttons = {
				{ Text = L("scr.back"), Variant = "Ghost", Width = 160, OnActivated = closeModal },
				{
					Text = L("scr.shop.buy"),
					Variant = "Primary",
					Icon = "Gold",
					Width = 220,
					OnActivated = function()
						closeModal()
						if skin then
							Common.Request(d, "Buy", { kind = "Skin", kitId = kit.Id, skinId = skin.Id })
						else
							Common.Request(d, "Buy", { kind = "Kit", kitId = kit.Id })
						end
					end,
				},
			},
		})
		UIKit.Label(theme, { Text = text, Role = "Body", Dialogue = true, Wrap = true, YAlign = "Top", Size = UDim2.fromScale(1, 1), Parent = modal.Content })
		modal.Root.Parent = root
	end

	-- one skin tile ------------------------------------------------------------------------------------
	local function skinTile(kit: any, skin: any, size: Vector2, opts: { [string]: any }): Frame
		local featured = opts.Featured == true
		local price: number = opts.Price or skin.Price or 0
		local base: number = opts.Base or skin.Price or 0
		local discount: number = opts.Discount or 0
		local rarity = Themes.Rarity(theme, skin.Rarity or "Common")
		local colors = Common.SkinColors(kit, skin)
		local owned = Common.SkinOwned(profile, kit, skin)
		local kitOwned = Common.KitOwned(profile, kit)
		local equipped = kitOwned and (pendingSkin[kit.Id] or Common.EquippedSkin(profile, kit)) == skin.Id
		local tile = Common.Well(theme, {
			Name = "Skin_" .. kit.Id .. "_" .. skin.Id,
			Size = UDim2.fromOffset(size.X, size.Y),
			StrokeColor = rarity,
			StrokeTransparency = if theme.Id == "Classic" then 0 else (if skin.Rarity == "Common" then 0.55 else 0.1),
			LayoutOrder = opts.LayoutOrder or 0,
		})
		tile.BackgroundColor3 = c.Panel
		local pad = if phone then 8 else 12
		local showH = math.floor(size.Y * (if featured then 0.62 else 0.56))
		-- showcase: palette gradient + emblem painted in the skin's colours
		local show = frame({
			Name = "Showcase",
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Position = UDim2.fromOffset(pad, pad),
			Size = UDim2.new(1, -pad * 2, 0, showH - pad),
			ClipsDescendants = true,
			Parent = tile,
		})
		Common.Corner(show, if theme.Id == "Void" then UDim.new(0, 10) elseif theme.Id == "Royal" then UDim.new(0, 6) else theme.SmallCorner)
		local showTop = if (0.2126 * colors[1].R + 0.7152 * colors[1].G + 0.0722 * colors[1].B) < 0.18 then colors[2] else colors[1]
		Common.Gradient(show, ColorSequence.new({
			ColorSequenceKeypoint.new(0, showTop:Lerp(c.PanelInset, 0.35)),
			ColorSequenceKeypoint.new(0.65, showTop:Lerp(c.PanelInset, 0.72)),
			ColorSequenceKeypoint.new(1, c.PanelInset),
		}), nil, 90)
		-- rarity glow rings
		for k = 1, 2 do
			local ring = frame({
				Name = "Glow",
				BackgroundTransparency = 0.86 + k * 0.04,
				BackgroundColor3 = if skin.Rarity == "Common" then colors[2] else rarity,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.42 + k * 0.22, 0.42 + k * 0.22),
				Parent = show,
			})
			local ar = Instance.new("UIAspectRatioConstraint")
			ar.AspectRatio = 1
			ar.Parent = ring
			Common.Corner(ring, UDim.new(0.5, 0))
		end
		-- keep dark palettes readable: lift the emblem and the glow toward white
		local lum = 0.2126 * colors[1].R + 0.7152 * colors[1].G + 0.0722 * colors[1].B
		local emblemColor = colors[1]:Lerp(Color3.new(1, 1, 1), if lum < 0.22 then 0.42 else 0.1)
		local emblem = Icons.Create(Common.KitIcon(kit), emblemColor, UDim2.fromScale(if featured then 0.62 else 0.58, if featured then 0.62 else 0.58), colors[2])
		emblem.Position = UDim2.fromScale(0.5, 0.48)
		emblem.Parent = show
		-- palette dots
		local dots = frame({ Name = "Palette", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(70, 14), Parent = show })
		local dl = UIKit.ListLayout(dots, { Horizontal = true, Gap = 6, HAlign = Enum.HorizontalAlignment.Center })
		dl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for i, col in colors do
			local dot = frame({ Name = "Dot", BackgroundTransparency = 0, BackgroundColor3 = col, Size = UDim2.fromOffset(12, 12), LayoutOrder = i, Parent = dots })
			Common.Corner(dot, if theme.Id == "Classic" or theme.Id == "Fell" then UDim.new(0, 0) else UDim.new(0.5, 0))
			Common.Stroke(dot, Color3.new(0, 0, 0), 1, 0.4)
		end
		-- rarity + discount badges
		local rb = UIKit.Badge(theme, { Text = L("scr.rarity." .. (skin.Rarity or "Common")), Color = rarity, Style = "Solid", Height = 18, TextSize = if theme.Id == "Classic" then 7 else 10 })
		rb.Position = UDim2.fromOffset(6, 6)
		rb.ZIndex = 3
		rb.Parent = show
		if discount > 0 and not owned then
			local db = UIKit.Badge(theme, { Text = L("scr.shop.discount", discount), Color = c.Danger, Style = "Solid", Height = if featured then 26 else 20, TextSize = if theme.Id == "Classic" then 9 else (if featured then 15 else 12) })
			db.AnchorPoint = Vector2.new(1, 0)
			db.Position = UDim2.new(1, -6, 0, 6)
			db.ZIndex = 3
			db.Parent = show
		end
		if featured then
			local fb = UIKit.Badge(theme, { Text = L("scr.shop.featured"), Icon = "Star", Color = c.Gold, Style = "Soft", Height = 22, TextSize = if theme.Id == "Classic" then 8 else 12 })
			fb.Position = UDim2.fromOffset(6, 30)
			fb.ZIndex = 3
			fb.Parent = show
		end
		-- info
		local infoY = showH + (if phone then 4 else 8)
		UIKit.Label(theme, {
			Name = "SkinName",
			Text = pick(skin.Name),
			Role = "Heading",
			TextSize = if theme.Id == "Classic" then (if featured then 13 else 10) else (if featured then 20 else 16),
			Position = UDim2.fromOffset(pad, infoY),
			Size = UDim2.new(1, -pad * 2, 0, if featured then 26 else 20),
			Scaled = true,
			MaxTextSize = if theme.Id == "Classic" then (if featured then 13 else 10) else (if featured then 20 else 16),
			Parent = tile,
		})
		UIKit.Label(theme, {
			Name = "KitName",
			Text = pick(kit.Name) .. "  ·  " .. pick(kit.Title),
			Role = "Caption",
			TextSize = if theme.Id == "Classic" then 8 else 12,
			Color = kit.Color:Lerp(c.Text, 0.35),
			Position = UDim2.fromOffset(pad, infoY + (if featured then 28 else 22)),
			Size = UDim2.new(1, -pad * 2, 0, 16),
			Truncate = true,
			Parent = tile,
		})
		-- action
		local text: string
		local variant = "Primary"
		local icon: string? = "Gold"
		local disabled = false
		local action: (() -> ())? = nil
		if equipped then
			text, variant, icon, disabled = L("scr.shop.equipped"), "Secondary", "Check", true
		elseif owned then
			text, variant, icon = L("scr.shop.equip"), "Secondary", "Check"
			action = function()
				pendingSkin[kit.Id] = skin.Id
				Common.Request(d, "EquipSkin", { kitId = kit.Id, skinId = skin.Id })
				opts.Refresh()
			end
		elseif skin.Mastery then
			text, variant, icon, disabled = L("scr.shop.masteryLock", skin.Mastery), "Secondary", "Crown", true
		elseif not kitOwned then
			text, variant, icon, disabled = L("scr.shop.needKit"), "Secondary", "Lock", true
		else
			text = L("common.gold", Common.Num(price))
			action = function()
				buy(kit, skin, price)
			end
		end
		local bh = if phone then 32 elseif featured then 46 else 38
		local btn = UIKit.Button(theme, {
			Name = "Action",
			Text = text,
			Icon = icon,
			Variant = variant,
			Disabled = disabled,
			Height = bh,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -pad),
			OnActivated = action,
		})
		btn.Root.Size = UDim2.new(1, -pad * 2, 0, bh)
		btn.Root.Parent = tile
		if discount > 0 and not owned and base > price then
			-- struck-through original price above the button
			UIKit.Label(theme, {
				Name = "WasPrice",
				Text = "<s>" .. L("common.gold", Common.Num(base)) .. "</s>",
				RichText = true,
				Role = "Number",
				TextSize = if theme.Id == "Classic" then 9 else 14,
				Tone = "Muted",
				XAlign = "Right",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -pad, 1, -pad - bh - 4),
				Size = UDim2.fromOffset(140, 18),
				Parent = tile,
			})
		end
		if defaultSel == nil and not disabled then
			defaultSel = btn.Root
		end
		return tile
	end

	-- sections -----------------------------------------------------------------------------------------
	local dailyHolder = frame({ Name = "DailyHolder", Size = UDim2.new(1, 0, 0, 0), Parent = body })
	local allHolder = frame({ Name = "AllHolder", Size = UDim2.new(1, 0, 0, 0), Parent = body })
	local refresh: () -> ()

	local function buildDaily(parent: Frame, w: number, h: number)
		parent:ClearAllChildren()
		local panel = UIKit.Panel(theme, { Name = "Daily", Title = L("scr.shop.daily"), TitleIcon = "Clock", Size = UDim2.fromOffset(w, h), Padding = if phone then 10 else 16 })
		panel.Root.Parent = parent
		-- countdown to the next UTC day (top right of the panel)
		local now = Common.Now(d)
		local left = 86400 - (now % 86400)
		local cd = UIKit.Label(theme, {
			Name = "Resets",
			Text = L("scr.shop.resets", Common.Clock(left)),
			Role = "Caption",
			Tone = "Dim",
			XAlign = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, if theme.Id == "Royal" then 16 else 10),
			Size = UDim2.fromOffset(320, 20),
			ZIndex = 10,
			Parent = panel.Root,
		})
		bag.Add(Motion.Loop(cd, function()
			cd.Text = L("scr.shop.resets", Common.Clock(86400 - (Common.Now(d) % 86400)))
		end))
		local offers = if kits then dailyOffers(d, profile, kits) else {}
		if #offers == 0 then
			Common.Empty(theme, L("scr.shop.empty"), { Parent = panel.Content })
			return
		end
		local contentW = w - (if phone then 20 else 32)
		local contentH = h - (if theme.Id == "Royal" then 58 elseif theme.Id == "Classic" then 42 else 46) - (if phone then 10 else 16)
		local gap = if phone then 10 else 16
		local row = frame({ Name = "Row", Size = UDim2.fromScale(1, 1), Parent = panel.Content })
		UIKit.ListLayout(row, { Horizontal = true, Gap = gap, VAlign = Enum.VerticalAlignment.Top })
		local n = #offers
		local unit = (contentW - gap * n) / (n + 1) -- featured = 2 units
		for i, o in offers do
			local tw = math.floor(if o.featured and not phone then unit * 2 else unit)
			if phone then
				tw = math.floor((contentW - gap * (n - 1)) / n)
			end
			skinTile(o.kit, o.skin, Vector2.new(tw, contentH), {
				Featured = o.featured and not phone,
				Price = o.price,
				Base = o.base,
				Discount = o.discount,
				LayoutOrder = i,
				Refresh = function()
					refresh()
				end,
			}).Parent = row
		end
	end

	local function buildAll(parent: Frame, w: number, h: number)
		parent:ClearAllChildren()
		local railW = if phone then 210 else 270
		local gap = screen.Gap
		local rail = UIKit.Panel(theme, { Name = "KitRail", Size = UDim2.fromOffset(railW, h), Padding = if phone then 8 else 12, Ornaments = false })
		rail.Root.Parent = parent
		local list = UIKit.List(theme, { Gap = if phone then 4 else 6 })
		list.Root.Size = UDim2.fromScale(1, 1)
		list.Root.Parent = rail.Content
		local kitList = if kits then kits.All() else {}
		for i, kit in kitList do
			local ownedCount, total = 0, 0
			for _, skin in kit.Skins do
				total += 1
				if Common.SkinOwned(profile, kit, skin) then
					ownedCount += 1
				end
			end
			local isSel = kit.Id == selectedKit
			local b = Instance.new("TextButton")
			b.Name = "Kit_" .. kit.Id
			b.Text = ""
			b.AutoButtonColor = false
			b.BackgroundTransparency = 1
			b.Size = UDim2.new(1, -6, 0, if phone then 34 else 40)
			b.LayoutOrder = i
			local well = Common.Well(theme, {
				Size = UDim2.fromScale(1, 1),
				Color = if isSel then kit.Color:Lerp(c.PanelInset, 0.7) else c.PanelInset,
				StrokeColor = if isSel then kit.Color else c.StrokeDim,
				StrokeTransparency = if isSel then 0 else 0.6,
			})
			well.Parent = b
			local ic = Icons.Create(Common.KitIcon(kit), kit.Color, if phone then 22 else 26, kit.Color:Lerp(Color3.new(1, 1, 1), 0.7))
			ic.Position = UDim2.new(0, if phone then 18 else 22, 0.5, 0)
			ic.Parent = well
			UIKit.Label(theme, {
				Text = pick(kit.Name),
				Role = "Body",
				TextSize = if theme.Id == "Classic" then (if phone then 8 else 10) else (if phone then 13 else 16),
				Color = if isSel then c.Text else c.TextDim,
				Position = UDim2.fromOffset(if phone then 36 else 44, 0),
				Size = UDim2.new(1, -(if phone then 36 else 44) - 46, 1, 0),
				Truncate = true,
				Parent = well,
			})
			UIKit.Label(theme, {
				Text = string.format("%d/%d", ownedCount, total),
				Role = "Number",
				TextSize = if theme.Id == "Classic" then 8 else 13,
				Color = if ownedCount == total then c.Success else c.TextMuted,
				XAlign = "Right",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0, 40, 1, 0),
				Parent = well,
			})
			local kitId = kit.Id
			Motion.On(b, "Activated", function()
				selectedKit = kitId
				buildAll(parent, w, h)
			end)
			list.Add(b)
		end
		-- skins of the selected kit
		local kit = kits and kits.Get(selectedKit)
		local gridW = w - railW - gap
		local panel = UIKit.Panel(theme, {
			Name = "AllSkins",
			Title = if kit then L("scr.shop.all") .. "  ·  " .. pick(kit.Name) else L("scr.shop.all"),
			Size = UDim2.fromOffset(gridW, h),
			Position = UDim2.fromOffset(railW + gap, 0),
			Padding = if phone then 10 else 16,
		})
		panel.Root.Parent = parent
		if kit == nil then
			return
		end
		local contentH = h - (if theme.Id == "Royal" then 58 elseif theme.Id == "Classic" then 42 else 46) - (if phone then 10 else 16)
		local tileW = if phone then 170 else 214
		local grid = UIKit.Grid(theme, { CellSize = UDim2.fromOffset(tileW, contentH - 6), CellPadding = UDim2.fromOffset(14, 10), Scroll = true })
		grid.Root.Size = UDim2.fromScale(1, 1)
		grid.Root.Parent = panel.Content
		local order = 0
		if not Common.KitOwned(profile, kit) then
			-- kit unlock tile
			order += 1
			local tile = Common.Well(theme, { Name = "KitUnlock", Size = UDim2.fromOffset(tileW, contentH - 6), StrokeColor = kit.Color, StrokeTransparency = 0.1, LayoutOrder = order })
			tile.BackgroundColor3 = kit.Color:Lerp(c.Panel, 0.82)
			local ic = Icons.Create(Common.KitIcon(kit), kit.Color, UDim2.fromScale(0.5, 0.5), kit.Color:Lerp(Color3.new(1, 1, 1), 0.7))
			ic.Position = UDim2.fromScale(0.5, 0.3)
			ic.Parent = tile
			UIKit.Badge(theme, { Text = L("scr.shop.kitUnlock"), Icon = "Lock", Color = kit.Color, Style = "Solid", Height = 20, TextSize = if theme.Id == "Classic" then 7 else 11, Position = UDim2.fromOffset(10, 10), Parent = tile })
			UIKit.Label(theme, { Text = pick(kit.Name), Role = "Heading", TextSize = if theme.Id == "Classic" then 11 else 18, XAlign = "Center", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.58, 0), Size = UDim2.new(1, -16, 0, 22), Scaled = true, MaxTextSize = if theme.Id == "Classic" then 11 else 18, Parent = tile })
			UIKit.Label(theme, { Text = pick(kit.Title), Role = "Caption", Tone = "Dim", XAlign = "Center", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.58, 24), Size = UDim2.new(1, -16, 0, 16), Parent = tile })
			local level = profile and profile.Level or 1
			local needLv = kit.Unlock.Level or 0
			local b = UIKit.Button(theme, {
				Text = if needLv > level then L("common.requiresLevel", needLv) else L("common.gold", Common.Num(kit.Unlock.Gold)),
				Icon = if needLv > level then "Lock" else "Gold",
				Variant = if needLv > level then "Secondary" else "Primary",
				Disabled = needLv > level,
				Height = if phone then 32 else 38,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -12),
				OnActivated = function()
					buy(kit, nil, kit.Unlock.Gold)
				end,
			})
			b.Root.Size = UDim2.new(1, -24, 0, if phone then 32 else 38)
			b.Root.Parent = tile
			grid.Add(tile)
		end
		for _, skin in kit.Skins do
			order += 1
			grid.Add(skinTile(kit, skin, Vector2.new(tileW, contentH - 6), {
				LayoutOrder = order,
				Refresh = function()
					buildAll(parent, w, h)
				end,
			}))
		end
	end

	local tabs: any = nil
	refresh = function()
		defaultSel = nil
		if phone then
			local tabsH = 34
			dailyHolder.Position = UDim2.fromOffset(0, tabsH + 8)
			allHolder.Position = UDim2.fromOffset(0, tabsH + 8)
			local h = bodyH - tabsH - 8
			dailyHolder.Size = UDim2.new(1, 0, 0, h)
			allHolder.Size = UDim2.new(1, 0, 0, h)
			dailyHolder.Visible = phoneTab == "Daily"
			allHolder.Visible = phoneTab == "All"
			if phoneTab == "Daily" then
				buildDaily(dailyHolder, bodyW, h)
			else
				buildAll(allHolder, bodyW, h)
			end
		else
			local dailyH = math.floor(bodyH * 0.5)
			dailyHolder.Size = UDim2.new(1, 0, 0, dailyH)
			allHolder.Position = UDim2.fromOffset(0, dailyH + screen.Gap)
			allHolder.Size = UDim2.new(1, 0, 0, bodyH - dailyH - screen.Gap)
			buildDaily(dailyHolder, bodyW, dailyH)
			buildAll(allHolder, bodyW, bodyH - dailyH - screen.Gap)
		end
	end
	if phone then
		tabs = UIKit.Tabs(theme, {
			Items = { { Id = "Daily", Text = L("scr.shop.daily") }, { Id = "All", Text = L("scr.shop.all") } },
			Selected = phoneTab,
			Height = 34,
			Size = UDim2.fromOffset(460, 34),
			OnChanged = function(id: string)
				phoneTab = id
				refresh()
			end,
		})
		tabs.Root.Parent = body
	end
	refresh()

	local state = d.State
	if state and state.ProfileChanged then
		bag.Connect(state.ProfileChanged, function(p: any)
			profile = p or Common.Profile(d)
			table.clear(pendingSkin)
			refresh()
		end)
	end

	return {
		Root = root,
		DefaultSelection = defaultSel or screen.Back,
		OnAction = function(action: string): boolean
			if modal then
				if action == "Back" then
					closeModal()
					return true
				end
				return false
			end
			if (action == "PrevTab" or action == "NextTab") and phone and tabs then
				phoneTab = if phoneTab == "Daily" then "All" else "Daily"
				tabs.Select(phoneTab)
				refresh()
				return true
			elseif action == "PrevTab" or action == "NextTab" then
				local list = if kits then kits.All() else {}
				local idx = 1
				for i, k in list do
					if k.Id == selectedKit then
						idx = i
					end
				end
				local step = if action == "NextTab" then 1 else -1
				local nextKit = list[((idx - 1 + step) % math.max(#list, 1)) + 1]
				if nextKit then
					selectedKit = nextKit.Id
					refresh()
				end
				return true
			end
			return false
		end,
		Destroy = function()
			closeModal()
			screen.Destroy()
		end,
	}
end

return Shop
