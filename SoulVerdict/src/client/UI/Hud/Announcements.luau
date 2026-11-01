--!strict
-- Hud/Announcements: big centred Undertale-style call-outs — FIGHT!, FINAL PHASE, DETERMINATION SURGE,
-- SECOND WIND, COLLAPSE, SAVE n/3, EXHAUSTED! — a huge title with a coloured glow/underline and a typed
-- "* ..." line. Live: pops in (UIScale overshoot), holds ~2.6 s, fades; queued one at a time.
--   Announcements.Create(theme, deps) -> { Root, Show(kind, data?), Update(snapshot), Tick(now), Destroy }
--   kind: "Fight" | "FinalPhase" | "Surge" | "SecondWind" | "Collapse" | "SaveLit" | "Exhausted" | "Custom"
--   data: { Monster: boolean? (local player is the monster), Self: boolean?, Name: string?, Lit: number?,
--           Total: number?, Title: string?, Line: string?, Color: Color3? }
-- Previews render snapshot.Announcement = { Kind, ... }.
local Style = require(script.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)

local Announcements = {}

local HOLD = 2.6

type Spec = { Title: string, Line: string, Color: Color3, Icon: string? }

local function spec(skin: any, kind: string, data: { [string]: any }): Spec
	local C = skin.C
	if kind == "FinalPhase" then
		return {
			Title = Style.L("round.hud.final"),
			Line = Style.L(if data.Monster then "hud.ann.final.monster" else "hud.ann.final.line"),
			Color = C.Danger,
			Icon = "Eye",
		}
	elseif kind == "Surge" then
		return { Title = Style.L("hud.surge"), Line = Style.L(if data.Monster then "hud.ann.surge.monster" else "hud.ann.surge.line"), Color = C.Gold, Icon = "Star" }
	elseif kind == "SecondWind" then
		return {
			Title = Style.L("hud.secondWind"),
			Line = if data.Self then Style.L("hud.ann.secondWind.self") else Style.L("hud.ann.secondWind.line", data.Name or "?"),
			Color = Color3.fromRGB(120, 255, 200),
			Icon = "Heart",
		}
	elseif kind == "Collapse" then
		return { Title = Style.L("hud.ann.collapse"), Line = Style.L("hud.ann.collapse.line"), Color = Color3.fromRGB(170, 90, 255), Icon = "Eclipse" }
	elseif kind == "SaveLit" then
		return { Title = Style.L("hud.ann.saveLit", data.Lit or 1, data.Total or 3), Line = Style.L("hud.ann.saveLit.line"), Color = C.Gold, Icon = "Star" }
	elseif kind == "Exhausted" then
		return { Title = Style.L("hud.ann.exhausted"), Line = "", Color = C.Warn, Icon = "Moon" }
	elseif kind == "Fight" then
		return { Title = Style.L("hud.ann.fight"), Line = Style.L(if data.Monster then "hud.ann.fight.monster" else "hud.ann.fight.line"), Color = C.Gold, Icon = nil }
	end
	return { Title = data.Title or "", Line = data.Line or "", Color = data.Color or C.Text, Icon = nil }
end

function Announcements.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "Announcements")
	local battle = skin.Battle
	local phone = layout.Phone
	local group = Style.Frame({
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if phone then 0.36 else 0.33),
		Size = UDim2.fromOffset(if phone then 640 else 1000, if phone then 110 else 170),
		Visible = false,
		Parent = root,
	})
	local scaleObj = Instance.new("UIScale")
	scaleObj.Parent = group
	local titleSize = if phone then 26 else (if battle then 46 else 62)
	local glow = Style.Glow({
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, titleSize * 0.62),
		Size = UDim2.fromOffset(if phone then 360 else 620, titleSize * 0.6),
		Spread = if phone then 18 else 30,
		Strength = 0.55,
		Corner = UDim.new(0.5, 0),
		Parent = group,
	})
	local iconHolder = Style.Frame({ Name = "Icon", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(titleSize * 0.8, titleSize * 0.8), Parent = group })
	local title = Style.Text(skin, {
		Name = "Title",
		Text = "",
		Role = "Title",
		TextSize = titleSize,
		X = "Center",
		Stroke = if battle then 4 else 2.5,
		Size = UDim2.new(1, 0, 0, titleSize + 8),
		ZIndex = 3,
		Parent = group,
	})
	local titleGradient: UIGradient? = nil
	if not battle then
		titleGradient = Style.Gradient(title, nil, nil, 90)
	end
	local underline = Style.Frame({
		Name = "Underline",
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, titleSize + 14),
		Size = UDim2.fromOffset(if phone then 220 else 380, if battle then 4 else 3),
		ZIndex = 3,
		Parent = group,
	})
	if not battle then
		Style.Gradient(underline, nil, Style.Seq({ { 0, 1 }, { 0.5, 0 }, { 1, 1 } }), 0)
	end
	local line = Style.Text(skin, {
		Name = "Line",
		Text = "",
		Role = "Body",
		TextSize = if phone then 11 else (if battle then 15 else 20),
		Upper = false,
		X = "Center",
		Position = UDim2.fromOffset(0, titleSize + 30),
		Size = UDim2.new(1, 0, 0, if phone then 18 else 26),
		ZIndex = 3,
		Parent = group,
	})

	local queue: { { Kind: string, Data: any } } = {}
	local showingUntil = 0
	local clock = 0
	local typer: any = nil

	local function render(kind: string, data: { [string]: any })
		local sp = spec(skin, kind, data)
		group.Visible = true
		Style.SetText(title, Style.Upper(skin, sp.Title))
		title.TextColor3 = Style.WHITE
		local stroke = title:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if battle then sp.Color else sp.Color:Lerp(Style.BLACK, 0.55)
			stroke.Transparency = 0
		end
		if titleGradient then
			titleGradient.Color = Style.CSeq(Style.WHITE, sp.Color:Lerp(Style.WHITE, 0.15))
		end
		underline.BackgroundColor3 = sp.Color
		for _, layer in glow:GetChildren() do
			if layer:IsA("Frame") then
				layer.BackgroundColor3 = sp.Color
			end
		end
		glow.Visible = not battle
		iconHolder:ClearAllChildren()
		if sp.Icon then
			local icon = Style.Icon(sp.Icon, sp.Color, UDim2.fromScale(1, 1))
			icon.Parent = iconHolder
		end
		local text = sp.Line
		line.Visible = text ~= ""
		if typer then
			typer.Cancel()
			typer = nil
		end
		if Style.Live() and text ~= "" then
			line.Text = ""
			typer = Motion.Typewriter(line, text, { Interval = 0.028 })
			scaleObj.Scale = 1.35
			Motion.Tween(scaleObj, { Time = 0.35, Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out }, { Scale = 1 })
		else
			line.Text = text
		end
		title.TextTransparency = 0
		line.TextTransparency = 0
	end

	local function show(kind: string, data: { [string]: any }?)
		table.insert(queue, { Kind = kind, Data = data or {} })
	end

	local function tick(now: number)
		clock = now
		if group.Visible and showingUntil > 0 and now >= showingUntil then
			showingUntil = 0
			if Style.Live() then
				Motion.Tween(title, { Time = 0.4 }, { TextTransparency = 1 })
				Motion.Tween(line, { Time = 0.4 }, { TextTransparency = 1 })
				task.delay(0.42, function()
					if showingUntil == 0 then
						group.Visible = false
					end
				end)
			else
				group.Visible = false
			end
		end
		if showingUntil == 0 and #queue > 0 then
			local nextItem = table.remove(queue, 1) :: { Kind: string, Data: any }
			render(nextItem.Kind, nextItem.Data)
			showingUntil = clock + HOLD
		end
	end

	local function update(s: { [string]: any })
		clock = s.Now or clock
		if not Style.Live() then
			local a = s.Announcement
			if a then
				render(a.Kind, { Monster = s.Role == "Monster", Self = true, Name = if s.Me then s.Me.Name else nil, Lit = s.SavesLit, Total = s.SavesTotal })
			else
				group.Visible = false
			end
		end
	end

	local initial = Style.Initial(deps, "HumanRound")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Show = show,
		Update = update,
		Tick = tick,
		Destroy = function()
			if typer then
				typer.Cancel()
			end
			root:Destroy()
		end,
	}
end

return Announcements
