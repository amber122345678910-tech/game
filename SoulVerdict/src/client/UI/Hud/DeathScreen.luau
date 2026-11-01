--!strict
-- Hud/DeathScreen: the local human's SOUL shatters — dark overlay, the pixel heart split in two with flying
-- shards, "YOUR SOUL SHATTERED", a "* Stay determined..." style line, who judged you, and the countdown to
-- spectating (Hud/init.luau shows it for ~3.6 s after the local character's Dead attribute flips).
--   DeathScreen.Create(theme, deps) -> { Root, Update(snapshot), Tick(now), Destroy }
-- Data: snapshot.Dead, DeathAt, Killer, Me.KitId (heart colour).
local Style = require(script.Parent.Style)
local Motion = require(script.Parent.Parent.Motion)

local DeathScreen = {}

local SHOW_TIME = 3.6
local LINES = { "hud.death.line1", "hud.death.line2", "hud.death.line3" }
local SHARDS = { { -1.2, -0.6 }, { 1.3, -0.4 }, { -0.9, 0.9 }, { 1.0, 1.1 }, { -1.6, 0.3 }, { 1.7, 0.2 } }

function DeathScreen.Create(theme: any, deps: any): any
	local skin, layout, root = Style.Context(theme, deps, "DeathScreen")
	local C = skin.C
	local battle = skin.Battle
	local phone = layout.Phone
	local k = if phone then 0.62 else 1
	Style.Frame({ Name = "Dim", BackgroundTransparency = if battle then 0.12 else 0.25, BackgroundColor3 = Style.BLACK, Size = UDim2.fromScale(1, 1), Parent = root })
	Style.Vignette({ Name = "Vignette", Color = Color3.fromRGB(120, 0, 0), Strength = 0.7, Depth = 0.3, Parent = root })
	local heartHolder = Style.Frame({
		Name = "Heart",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(math.floor(120 * k), math.floor(110 * k)),
		Parent = root,
	})
	local shards = Style.Frame({ Name = "Shards", Size = UDim2.fromScale(1, 1), Parent = heartHolder })
	local title = Style.Text(skin, {
		Name = "Title",
		Text = Style.L("hud.death.title"),
		Role = "Title",
		TextSize = math.floor((if battle then 32 else 46) * k),
		Color = C.Danger,
		X = "Center",
		Stroke = if battle then 3 else 2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, math.floor(96 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(54 * k)),
		Parent = root,
	})
	title.TextColor3 = C.Danger
	local line = Style.Text(skin, {
		Name = "Line",
		Text = "",
		Role = "Body",
		TextSize = math.floor((if battle then 15 else 20) * k),
		Upper = false,
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, math.floor(160 * k)),
		Size = UDim2.new(1, 0, 0, math.floor(28 * k)),
		Parent = root,
	})
	local by = Style.Text(skin, {
		Name = "By",
		Text = "",
		TextSize = math.floor((if battle then 11 else 14) * k),
		Color = C.Dim,
		Upper = false,
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, math.floor(204 * k)),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = root,
	})
	local countdown = Style.Text(skin, {
		Name = "Countdown",
		Text = "",
		TextSize = math.floor((if battle then 11 else 14) * k),
		Color = C.Dim,
		Upper = false,
		X = "Center",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -math.floor(60 * k)),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = root,
	})
	local deathAt: number? = nil
	local shown: number? = nil

	local function drawHeart(color: Color3, animate: boolean)
		for _, child in heartHolder:GetChildren() do
			if child ~= shards then
				child:Destroy()
			end
		end
		shards:ClearAllChildren()
		local heart = Style.Heart(color, math.floor(110 * k), "Broken")
		heart.Parent = heartHolder
		local px = math.max(4, math.floor(10 * k))
		for i, off in SHARDS do
			local shard = Style.Frame({
				Name = "Shard" .. i,
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.floor(off[1] * 40 * k), 0.5, math.floor(off[2] * 40 * k)),
				Size = UDim2.fromOffset(px, px),
				Parent = shards,
			})
			if animate then
				shard.Position = UDim2.fromScale(0.5, 0.5)
				Motion.Tween(shard, { Time = 0.9, Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out, Delay = 0.35 }, {
					Position = UDim2.new(0.5, math.floor(off[1] * 90 * k), 0.5, math.floor(off[2] * 90 * k + 40 * k)),
					BackgroundTransparency = 1,
				})
			end
		end
	end

	local function tick(now: number)
		if deathAt then
			local left = math.max(0, deathAt + SHOW_TIME - now)
			Style.SetText(countdown, Style.L("hud.death.spectate", math.max(1, math.ceil(left))))
		end
	end

	local function update(s: { [string]: any })
		local at = s.DeathAt
		deathAt = at
		if at and shown ~= at then
			shown = at
			local kit = if s.Me then Style.Kit(s.Me.KitId) else nil
			drawHeart(if kit then kit.Color else C.SoulRed, Style.Live())
			local seed = math.floor(at * 10) % #LINES + 1
			local text = Style.L(LINES[seed])
			if Style.Live() then
				line.Text = ""
				Motion.Typewriter(line, text, { Interval = 0.045 })
			else
				line.Text = text
			end
		end
		by.Visible = s.Killer ~= nil
		if s.Killer then
			Style.SetText(by, Style.L("hud.death.by", s.Killer))
		end
		tick(s.Now or 0)
	end

	local initial = Style.Initial(deps, "Dead")
	if initial then
		update(initial)
	end
	return {
		Root = root,
		Update = update,
		Tick = tick,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return DeathScreen
