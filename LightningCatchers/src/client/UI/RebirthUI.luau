--!strict
-- Перезапуск генератора: что получишь (множитель ×A → ×B), что нужно, что сбросится и что останется.
-- Кнопка с подтверждением "Точно?" и праздник после успеха.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local RebirthUI = {}

local W, H = 780, 560
local CONFIRM_TIME = 3
local CONFETTI = 28
local CONFETTI_COLORS = { Theme.Volt, Theme.Electric, Theme.Pink, Theme.Green, Theme.Purple, Theme.Orange }

local win: UIKit.Window
local multLabel: TextLabel
local multScale: UIScale
local zoneReq: TextLabel
local voltsReq: TextLabel
local voltsBar: UIKit.Bar
local bonusLabel: TextLabel
local countLabel: TextLabel -- число перезапусков в заголовке
local rebirthButton: TextButton
local confirmUntil = 0
local busy = false
local confetti: { Frame } = {}
local celebrateLabel: TextLabel
local celebrateScale: UIScale

local function multText(m: number): string
	return string.format("×%.1f", m)
end

local function refresh()
	local d = ClientState.get()
	if not d or not win.isOpen() then
		return
	end
	local r = d.Rebirths
	multLabel.Text = string.format("Множитель %s → %s", multText(Economy.rebirthMult(r)), multText(Economy.rebirthMult(r + 1)))
	countLabel.Text = tostring(r)

	local needZone = Config.Rebirth.RequiredZone
	local zoneOk = d.Zone >= needZone
	zoneReq.Text = string.format("%s Открыть остров %d «%s»", if zoneOk then "✅" else "❌", needZone, Config.Zones[needZone].Name)
	zoneReq.TextColor3 = if zoneOk then Theme.Green else Theme.Miss

	local cost = Economy.rebirthCost(r)
	local voltsOk = d.Volts >= cost
	voltsReq.Text = string.format("%s Накопить ⚡ %s", if voltsOk then "✅" else "❌", Format.short(cost))
	voltsReq.TextColor3 = if voltsOk then Theme.Green else Theme.Miss
	voltsBar.set(d.Volts / cost, string.format("%s / %s", Format.short(math.min(d.Volts, cost)), Format.short(cost)))
	voltsBar.setColor(if voltsOk then Theme.Green else Theme.Volt)

	local extraSlot = table.find(Config.Rebirth.PetSlotsAt, r + 1) ~= nil
	bonusLabel.Visible = extraSlot
	bonusLabel.Text = "🎁 Бонус: +1 место для питомца!"

	if os.clock() < confirmUntil then
		return
	end
	if Economy.canRebirth(d) then
		UIKit.setButtonText(rebirthButton, "♻ ПЕРЕЗАПУСК")
		UIKit.setButtonColor(rebirthButton, Theme.Red)
	else
		UIKit.setButtonText(rebirthButton, "♻ Пока рано")
		UIKit.setButtonColor(rebirthButton, Theme.GrayDark)
	end
end

local function buildConfetti()
	for i = 1, CONFETTI do
		local f = UIKit.new("Frame", {
			Name = "Confetti" .. i,
			Size = UDim2.fromOffset(14, 22),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = CONFETTI_COLORS[(i - 1) % #CONFETTI_COLORS + 1],
			Visible = false,
			ZIndex = 30,
			Parent = win.Root,
		}) :: Frame
		UIKit.corner(f, 4)
		table.insert(confetti, f)
	end
	celebrateLabel = UIKit.label({
		Name = "Celebrate",
		Text = "",
		Size = UDim2.fromOffset(W - 60, 100),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		TextColor3 = Theme.Volt,
		MaxTextSize = 60,
		Visible = false,
		ZIndex = 31,
		Parent = win.Root,
	})
	celebrateScale = UIKit.new("UIScale", { Scale = 1, Parent = celebrateLabel }) :: UIScale
end

local function celebrate(newMult: number)
	Sounds.play("LevelUp")
	Sounds.play("Victory")
	Juice.flash(Theme.Gold, 0.55)
	Juice.shake(0.3)
	for _, f in confetti do
		f.Visible = true
		f.Position = UDim2.fromScale(0.5, 0.55)
		f.Rotation = math.random(0, 360)
		f.BackgroundTransparency = 0
		local angle = math.random() * math.pi * 2
		local dist = 0.25 + math.random() * 0.35
		local target = UDim2.fromScale(0.5 + math.cos(angle) * dist, 0.5 + math.sin(angle) * dist * 0.9 + 0.1)
		UIKit.tween(f, 0.9, { Position = target, Rotation = f.Rotation + math.random(-360, 360) }, Enum.EasingStyle.Quart)
		task.delay(0.6, function()
			UIKit.tween(f, 0.5, { BackgroundTransparency = 1 })
		end)
	end
	celebrateLabel.Text = "Генератор перезапущен!\nВольты " .. multText(newMult)
	celebrateLabel.Visible = true
	celebrateScale.Scale = 0.3
	UIKit.tween(celebrateScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		celebrateLabel.Visible = false
		for _, f in confetti do
			f.Visible = false
		end
		if win.isOpen() then
			win.close()
		end
	end)
end

local function onRebirthPressed()
	local d = ClientState.get()
	if busy or not d then
		return
	end
	if not Economy.canRebirth(d) then
		Sounds.play("Error")
		if d.Zone < Config.Rebirth.RequiredZone then
			ClientState.Toast:Fire("Сначала открой остров «" .. Config.Zones[Config.Rebirth.RequiredZone].Name .. "»", "info")
		else
			ClientState.Toast:Fire("Не хватает ⚡ " .. Format.short(Economy.rebirthCost(d.Rebirths) - d.Volts), "bad")
		end
		return
	end
	-- первое нажатие — подтверждение
	if os.clock() > confirmUntil then
		confirmUntil = os.clock() + CONFIRM_TIME
		UIKit.setButtonText(rebirthButton, "Точно? Жми ещё раз!")
		UIKit.setButtonColor(rebirthButton, Theme.Orange)
		local scale = rebirthButton:FindFirstChildOfClass("UIScale")
		if scale then
			UIKit.bump(scale, 0.1)
		end
		task.delay(CONFIRM_TIME + 0.05, function()
			if os.clock() >= confirmUntil then
				refresh()
			end
		end)
		return
	end
	confirmUntil = 0
	busy = true
	local before = d.Rebirths
	local ok = ClientState.request(Net.Actions.Rebirth, nil)
	busy = false
	if ok then
		celebrate(Economy.rebirthMult(before + 1))
	else
		Sounds.play("Error")
		refresh()
	end
end

local function build()
	local body = win.Body
	-- две короткие строки
	UIKit.label({
		Name = "Line1",
		Text = "Начни заново — и получай больше Вольт навсегда!",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 0),
		MaxTextSize = 26,
		Parent = body,
	})
	UIKit.label({
		Name = "Line2",
		Text = "Питомцы, фульгуриты и Молниедекс остаются с тобой.",
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.fromOffset(10, 32),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 22,
		Parent = body,
	})

	-- главное: множитель
	local multCard = UIKit.card({
		Name = "Mult",
		Size = UDim2.new(1, -20, 0, 76),
		Position = UDim2.fromOffset(10, 64),
		Parent = body,
	})
	UIKit.tintCard(multCard, Theme.GoldDark, Theme.PanelDark)
	multLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -30, 1, -12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = Theme.Volt,
		MaxTextSize = 46,
		Parent = multCard,
	})
	multScale = UIKit.new("UIScale", { Scale = 1, Parent = multLabel }) :: UIScale

	-- что нужно
	local req = UIKit.card({
		Name = "Requirements",
		Size = UDim2.new(1, -20, 0, 112),
		Position = UDim2.fromOffset(10, 150),
		Parent = body,
	})
	UIKit.label({
		Name = "Title",
		Text = "Что нужно:",
		Size = UDim2.fromOffset(200, 26),
		Position = UDim2.fromOffset(14, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = req,
	})
	zoneReq = UIKit.label({
		Name = "Zone",
		Text = "",
		Size = UDim2.new(1, -28, 0, 26),
		Position = UDim2.fromOffset(14, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = req,
	})
	voltsReq = UIKit.label({
		Name = "Volts",
		Text = "",
		Size = UDim2.new(0.42, -14, 0, 26),
		Position = UDim2.fromOffset(14, 70),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = req,
	})
	voltsBar = UIKit.bar({
		Name = "VoltsBar",
		Size = UDim2.new(0.58, -20, 0, 28),
		Position = UDim2.new(0.42, 4, 0, 69),
		Color = Theme.Volt,
		TextSize = 18,
		Parent = req,
	})

	-- что сбросится / что останется
	local function listCard(name: string, title: string, color: Color3, text: string, x: number)
		local c = UIKit.card({
			Name = name,
			Size = UDim2.new(0.5, -15, 0, 88),
			Position = UDim2.new(x, if x == 0 then 10 else 5, 0, 270),
			Parent = body,
		})
		UIKit.label({
			Name = "Title",
			Text = title,
			Size = UDim2.new(1, -20, 0, 26),
			Position = UDim2.fromOffset(10, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			MaxTextSize = 22,
			Parent = c,
		})
		UIKit.label({
			Name = "Text",
			Text = text,
			Size = UDim2.new(1, -20, 0, 56),
			Position = UDim2.fromOffset(10, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Theme.FontBold,
			MaxTextSize = 20,
			Parent = c,
		})
	end
	listCard("Reset", "Сбросится:", Theme.Miss, "⚡ Вольты и банка\n🔱 улучшения и 🏝 острова", 0)
	listCard("Keep", "Останется:", Theme.Green, "🐾 питомцы, 🔮 фульгуриты\n💎 осколки, 📖 Молниедекс", 0.5)

	bonusLabel = UIKit.label({
		Name = "Bonus",
		Text = "",
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 361),
		TextColor3 = Theme.Pink,
		MaxTextSize = 22,
		Visible = false,
		Parent = body,
	})

	rebirthButton = UIKit.button({
		Name = "Rebirth",
		Text = "♻ ПЕРЕЗАПУСК",
		Color = Theme.Red,
		Size = UDim2.fromOffset(380, 72),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		TextSize = 32,
		Parent = body,
	}, onRebirthPressed)
end

function RebirthUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Rebirth",
		Title = "Перезапуск генератора",
		Icon = "♻",
		Width = W,
		Height = H,
		Accent = Theme.RedDark,
		OnOpen = function()
			confirmUntil = 0
			refresh()
			UIKit.bump(multScale, 0.12)
			ClientState.WindowOpened:Fire("Rebirth")
		end,
		OnClose = function()
			confirmUntil = 0
			ClientState.WindowClosed:Fire("Rebirth")
		end,
	})
	countLabel = UIKit.headerCounter(win, "♻", Theme.Orange, 120)
	build()
	buildConfetti()

	ClientState.Changed:Connect(function(_d: PlayerData.Data)
		refresh()
	end)
	ClientState.OpenWindow:Connect(function(name: string)
		local base = UIKit.parseWindowName(name)
		if base == "Rebirth" then
			win.open()
		end
	end)
end

function RebirthUI.open()
	if win then
		win.open()
	end
end

return RebirthUI
