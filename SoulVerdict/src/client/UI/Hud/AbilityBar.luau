--!strict
-- Hud/AbilityBar: one slot per ability in kit order (Style.Slots: humans M1 Q E F(Block) Shift(Dash) R(ult);
-- monsters M1 Q E R T Shift F(Verdict Box) G(ult)) with icon, key hint (InputController.KeyLabel), cooldown wipe
-- + seconds, Hold charge fill, ult meter / READY glow (Battle: the red SOUL replaces the icon like a selected
-- UT button), M1 combo pips, Justice ammo pips + reload, dash charges, block guard, disabled tint while
-- Stunned / Silenced.
--   AbilityBar.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
--   AbilityBar.BuildSlot(skin, info: SlotInfo, size, opts?) -> SlotHandle   (also used by MobileControls)
--       opts: { Round: boolean?, Button: boolean? (root is a TextButton), Key: string?, Name: boolean?, Phone: boolean? }
--       SlotHandle = { Root: GuiObject, Box: GuiObject, Info, Set(state) }
--   AbilityBar.SlotState(info, snapshot, now) -> state      shared state maths
-- Data: snapshot.Me (KitId, Ult, Dash/DashMax/DashNext, Guard/MaxGuard, Blocking, Statuses), Cooldowns
-- ({[abilityId] = endsAt}), Charge {Id, Value}, Combo, Ammo {Count, Max, ReloadEndsAt}.
local Style = require(script.Parent.Style)

local AbilityBar = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function AbilityBar.SlotState(info: any, s: { [string]: any }, now: number): { [string]: any }
	local me = s.Me or {}
	local statuses = me.Statuses or {}
	local stunned = (statuses.Stunned or 0) > now or (statuses.Boxed or 0) > now or me.Downed == true or me.Dead == true
	local silenced = (statuses.Silenced or 0) > now
	local state: { [string]: any } = { Remaining = 0, Cooldown = info.Cooldown or 0, Disabled = false }
	local endsAt = (s.Cooldowns or {})[info.Id] or 0
	state.Remaining = math.max(0, endsAt - now)
	if info.Id == "Dash" then
		local charges = me.Dash or 0
		local maxCharges = me.DashMax or 2
		state.Charges = charges
		state.ChargesMax = maxCharges
		state.ChargeNext = me.DashNext or 0
		if charges < 1 then
			local recharge = info.Cooldown or 2.8
			state.Remaining = math.max(state.Remaining, recharge * (1 - (me.DashNext or 0)))
			state.Cooldown = recharge
		else
			state.Remaining = 0
		end
	elseif info.Id == "Block" then
		state.Guard = clamp01((me.Guard or 0) / math.max(1, me.MaxGuard or 100))
		state.Active = me.Blocking == true
	end
	if info.Ult then
		state.Ult = math.clamp(me.Ult or 0, 0, 100)
		state.UltReady = state.Ult >= 100 and state.Remaining <= 0.05
	end
	if info.Combo and info.Combo > 1 then
		state.Combo = math.clamp(s.Combo or 0, 0, info.Combo)
		state.ComboMax = info.Combo
	end
	if info.Ammo and s.Ammo then
		state.Ammo = s.Ammo.Count or 0
		state.AmmoMax = s.Ammo.Max or info.Ammo
		local reloadEnds = s.Ammo.ReloadEndsAt or 0
		if reloadEnds > now then
			state.Reloading = true
			state.Remaining = math.max(state.Remaining, reloadEnds - now)
		end
	end
	if s.Charge and s.Charge.Id == info.Id then
		state.Charge = clamp01(s.Charge.Value or 0)
		state.Active = true
	end
	state.Disabled = stunned or (silenced and info.Slot ~= "M1")
	state.DisabledReason = if stunned then "Stunned" elseif silenced then "Silenced" else nil
	return state
end

function AbilityBar.BuildSlot(skin: any, info: any, size: number, opts: { [string]: any }?): any
	local o = opts or {}
	local C = skin.C
	local battle = skin.Battle
	local round = o.Round == true
	local isUlt = info.Ult == true
	local nameH = if o.Name then (if battle then 20 else 26) else 0
	local container: GuiObject
	if o.Button then
		local b = Instance.new("TextButton")
		b.Name = "Slot_" .. info.Slot
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Size = UDim2.fromOffset(size, size + nameH)
		container = b
	else
		container = Style.Frame({ Name = "Slot_" .. info.Slot, Size = UDim2.fromOffset(size, size + nameH) })
	end
	local corner = if round then UDim.new(0.5, 0) elseif battle then UDim.new(0, 0) else UDim.new(0, math.floor(size * 0.22))
	local glow = Style.Glow({
		Name = "ReadyGlow",
		Color = C.UltFull,
		Size = UDim2.fromOffset(size, size),
		Spread = math.floor(size * 0.18),
		Corner = if round then UDim.new(0.5, 0) elseif battle then UDim.new(0, 0) else UDim.new(0, math.floor(size * 0.3)),
		Strength = 1.3,
		ZIndex = 1,
		Parent = container,
	})
	glow.Visible = false
	local box = Style.Frame({
		Name = "Box",
		BackgroundTransparency = if battle then 0 else 0.2,
		BackgroundColor3 = if battle then Style.BLACK else Color3.fromRGB(12, 14, 22),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 2,
		Parent = container,
	})
	Style.Corner(box, corner)
	local stroke = Style.Stroke(box, C.Accent, if battle then 3 else 2, 0, battle and not round)
	if not battle then
		Style.Gradient(box, Style.CSeq(Color3.fromRGB(70, 76, 100), Color3.fromRGB(18, 20, 30)), nil, 90)
	end
	-- ult charge fill (rises from the bottom)
	local ultFill: Frame? = nil
	local ultRing: any = nil
	if isUlt then
		if round or not battle then
			ultRing = Style.Radial({ Name = "UltRing", Mode = "Filled", Color = C.Ult, Transparency = 0.15, Circle = round, Corner = corner, ZIndex = 2, Parent = box })
			local inner = Style.Frame({
				Name = "Inner",
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(12, 14, 22),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -math.max(6, math.floor(size * 0.12)), 1, -math.max(6, math.floor(size * 0.12))),
				ZIndex = 3,
				Parent = box,
			})
			Style.Corner(inner, if round then UDim.new(0.5, 0) else UDim.new(0, math.max(0, corner.Offset - 4)))
		else
			ultFill = Style.Frame({
				Name = "UltFill",
				BackgroundTransparency = 0.3,
				BackgroundColor3 = C.Ult,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0),
				ZIndex = 3,
				Parent = box,
			})
		end
	end
	local iconSize = math.floor(size * (if round then 0.5 else 0.56))
	local iconHolder = Style.Frame({
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if o.Name or round then 0.5 else 0.46),
		Size = UDim2.fromOffset(iconSize, iconSize),
		ZIndex = 4,
		Parent = box,
	})
	local icon: Frame? = nil
	local function setIcon(color: Color3)
		if icon then
			icon:Destroy()
		end
		local newIcon = Style.Icon(info.Icon, color, iconSize)
		newIcon.Name = "Icon"
		newIcon.ZIndex = 4
		newIcon.Parent = iconHolder
		icon = newIcon
	end
	local soul = Style.Heart(C.SoulRed, math.floor(size * 0.46), "Whole")
	soul.ZIndex = 4
	soul.Visible = false
	soul.Parent = box
	-- cooldown overlay
	local wipe: Frame? = nil
	local radial: any = nil
	if battle and not round then
		wipe = Style.Frame({
			Name = "Wipe",
			BackgroundTransparency = 0.25,
			BackgroundColor3 = Style.BLACK,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 5,
			Parent = box,
		})
	else
		radial = Style.Radial({ Name = "Wipe", Mode = "Remaining", Color = Style.BLACK, Transparency = 0.3, Circle = round, Corner = corner, ZIndex = 5, Parent = box })
	end
	local seconds = Style.Text(skin, {
		Name = "Seconds",
		Text = "",
		Role = "Number",
		TextSize = math.floor(size * (if battle then 0.26 else 0.32)),
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.5),
		ZIndex = 7,
		Parent = box,
	})
	-- bottom indicator strip (combo / ammo / dash charges / guard / hold charge)
	local stripH = math.max(4, math.floor(size * 0.09))
	local pips = Style.Pips(skin, {
		Name = "Pips",
		Max = 0,
		PipSize = Vector2.new(math.max(4, math.floor(size * 0.1)), stripH),
		Gap = 3,
		Color = C.Gold,
		Empty = Color3.fromRGB(70, 70, 80),
		Shape = if info.Ammo then "Bullet" elseif battle then "Square" else "Round",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -math.floor(size * 0.08)),
		ZIndex = 6,
		Parent = box,
	})
	if info.Ammo then
		pips.Root.Size = UDim2.fromOffset(0, math.floor(size * 0.2))
	end
	local meter = Style.Frame({
		Name = "Meter",
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(40, 40, 48),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -math.floor(size * 0.08)),
		Size = UDim2.new(0.72, 0, 0, stripH),
		ZIndex = 6,
		Visible = false,
		Parent = box,
	})
	local meterFill = Style.Frame({ Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = C.Guard, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = meter })
	if not battle then
		Style.Corner(meter, UDim.new(0.5, 0))
		Style.Corner(meterFill, UDim.new(0.5, 0))
	end
	local lock = Style.Icon("Lock", Color3.fromRGB(220, 220, 230), math.floor(size * 0.3))
	lock.Name = "Lock"
	lock.AnchorPoint = Vector2.new(1, 0)
	lock.Position = UDim2.new(1, -3, 0, 3)
	lock.ZIndex = 8
	lock.Visible = false
	lock.Parent = box
	-- key cap
	if o.Key and o.Key ~= "" then
		local capH = math.max(14, math.floor(size * (if battle then 0.3 else 0.28)))
		local cap = Style.KeyCap(skin, o.Key, capH)
		cap.Name = "KeyCap"
		cap.ZIndex = 9
		cap.Position = if battle then UDim2.fromOffset(-6, -6) else UDim2.fromOffset(-4, -4)
		for _, d in cap:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 9
			end
		end
		cap.Parent = container
	end
	local nameLabel: TextLabel? = nil
	if o.Name then
		nameLabel = Style.Text(skin, {
			Name = "Name",
			Text = info.Name,
			TextSize = if battle then 8 else 11,
			Color = C.Dim,
			X = "Center",
			Y = "Top",
			Wrap = true,
			Scaled = true,
			MinSize = 6,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 10, 0, nameH - 3),
			ZIndex = 2,
			Parent = container,
		})
	end

	local lastKey = ""
	local function set(state: { [string]: any })
		local remaining: number = state.Remaining or 0
		local cd: number = math.max(0.01, state.Cooldown or 0.01)
		local onCd = remaining > 0.05
		local ready = state.UltReady == true
		local disabled = state.Disabled == true
		local active = state.Active == true
		-- colours
		local border: Color3
		local iconColor: Color3
		if disabled then
			border, iconColor = C.Muted, C.Muted
		elseif ready then
			border, iconColor = C.UltFull, C.UltFull
		elseif active then
			border, iconColor = C.Select, C.Select
		elseif isUlt and not onCd then
			border = if battle then C.Ult else Style.WHITE
			iconColor = if battle then Style.WHITE else C.Ult:Lerp(Style.WHITE, 0.4)
		elseif onCd then
			border = if battle then C.Muted else Style.WHITE
			iconColor = C.Muted
		else
			border = if battle then C.Accent else Style.WHITE
			iconColor = if battle then C.Accent else Style.WHITE
		end
		local key = string.format("%s|%s|%s", tostring(border), tostring(iconColor), tostring(ready))
		if key ~= lastKey then
			lastKey = key
			stroke.Color = border
			stroke.Transparency = if battle or ready or active or disabled then 0 elseif onCd then 0.85 else 0.55
			setIcon(iconColor)
		end
		glow.Visible = ready
		soul.Visible = ready and battle
		iconHolder.Visible = not (ready and battle)
		-- cooldown wipe
		local frac = if onCd then math.clamp(remaining / cd, 0, 1) else 0
		if wipe then
			wipe.Size = UDim2.fromScale(1, frac)
			wipe.Visible = onCd
		elseif radial then
			radial.Set(frac)
		end
		-- ult meter
		if isUlt then
			local ult = (state.Ult or 0) / 100
			if ultFill then
				ultFill.Size = UDim2.fromScale(1, if ready then 1 else ult)
				ultFill.BackgroundColor3 = if ready then C.UltFull else C.Ult
			elseif ultRing then
				ultRing.Set(if ready then 1 else ult)
			end
		end
		-- text
		local text = ""
		if onCd then
			text = Style.FormatCd(remaining)
		elseif isUlt and not ready then
			text = string.format("%d%%", math.floor(state.Ult or 0))
		end
		Style.SetText(seconds, text)
		seconds.TextSize = math.floor(size * (if isUlt and not onCd then 0.22 else (if battle then 0.26 else 0.32)))
		-- indicator strip
		local showMeter = false
		if state.Charge then
			showMeter = true
			meterFill.BackgroundColor3 = C.Select
			meterFill.Size = UDim2.fromScale(state.Charge, 1)
		elseif state.Guard and not onCd then
			showMeter = true
			meterFill.BackgroundColor3 = C.Guard
			meterFill.Size = UDim2.fromScale(state.Guard, 1)
		end
		meter.Visible = showMeter
		if state.Ammo then
			pips.Root.Visible = not showMeter
			pips.Set(state.Ammo, state.AmmoMax)
		elseif state.Charges then
			pips.Root.Visible = not showMeter
			pips.Set(state.Charges + (state.ChargeNext or 0) * (if state.Charges < state.ChargesMax then 1 else 0), state.ChargesMax)
		elseif state.Combo then
			pips.Root.Visible = not showMeter
			pips.Set(state.Combo, state.ComboMax)
		else
			pips.Root.Visible = false
		end
		lock.Visible = disabled
		if nameLabel then
			if ready then
				Style.SetText(nameLabel, Style.Upper(skin, Style.L("hud.ready")))
				nameLabel.TextColor3 = C.UltFull
			elseif state.Reloading then
				Style.SetText(nameLabel, Style.Upper(skin, Style.L("hud.slot.reload")))
				nameLabel.TextColor3 = C.Warn
			else
				Style.SetText(nameLabel, Style.Upper(skin, info.Name))
				nameLabel.TextColor3 = if disabled then C.Muted else C.Dim
			end
		end
	end
	return { Root = container, Box = box, Info = info, Set = set }
end

function AbilityBar.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "AbilityBar")
	local C = skin.C
	local phone = layout.Phone
	local battle = skin.Battle
	local size = if phone then 50 else (if battle then 64 else 62)
	local ultSize = if battle then size else size + 12
	local gap = if phone then 10 else 14
	local nameH = if battle then 20 else 26
	local bottom = if phone then 10 else 12
	local bar = Style.Frame({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -bottom),
		Size = UDim2.fromOffset(100, ultSize + nameH),
		Parent = root,
	})
	local chip = Style.Box(skin, {
		Name = "Disabled",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.fromOffset(170, 26),
		Border = C.Danger,
		Stroke = 2,
		Sheen = false,
		Visible = false,
		Parent = bar,
	})
	local chipText = Style.Text(skin, { Name = "Text", Text = "", TextSize = skin.Size.Small + 1, Color = C.Danger, X = "Center", Stroke = false, Size = UDim2.fromScale(1, 1), Parent = chip })
	local slots: { any } = {}
	local kitShown = ""
	local snap: { [string]: any }? = nil

	local function build(kitId: string)
		kitShown = kitId
		for _, slot in slots do
			slot.Root:Destroy()
		end
		table.clear(slots)
		local infos = Style.Slots(kitId)
		local x = 0
		for _, info in infos do
			local s = if info.Ult then ultSize else size
			local slot = AbilityBar.BuildSlot(skin, info, s, { Round = info.Ult and not battle, Key = Style.KeyLabel(deps, info.Action), Name = true })
			slot.Root.Position = UDim2.fromOffset(x, ultSize - s)
			slot.Root.Parent = bar
			table.insert(slots, slot)
			x += s + gap
			if (info.Slot == "E" and not (infos[1] and Style.Kit(kitId) and Style.Kit(kitId).Role == "Monster")) or info.Slot == "T" then
				x += math.floor(gap * 0.8) -- small group gap before the built-ins
			end
		end
		bar.Size = UDim2.fromOffset(math.max(0, x - gap), ultSize + nameH)
	end

	local function tick(now: number)
		local s = snap
		if not s or not s.Me then
			return
		end
		local reason: string? = nil
		for _, slot in slots do
			local state = AbilityBar.SlotState(slot.Info, s, now)
			slot.Set(state)
			if state.Disabled and state.DisabledReason then
				reason = state.DisabledReason
			end
		end
		chip.Visible = reason ~= nil
		if reason then
			Style.SetText(chipText, Style.Upper(skin, Style.L(if reason == "Stunned" then "hud.slot.stunned" else "hud.slot.silenced")))
		end
	end

	local function update(s: { [string]: any })
		snap = s
		local me = s.Me
		bar.Visible = me ~= nil
		if not me then
			return
		end
		if me.KitId ~= kitShown then
			build(me.KitId)
		end
		tick(s.Now or 0)
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Tick = tick,
		Rebind = function()
			kitShown = ""
			if snap then
				update(snap)
			end
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return AbilityBar
