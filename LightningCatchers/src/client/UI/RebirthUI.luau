--!strict
-- Перезапуск генератора: что получишь (множитель ×A → ×B), что нужно, что сбросится и что останется.
-- Кнопка с подтверждением "Точно?" (второе нажатие засчитывается не раньше CONFIRM_GUARD — двойной тап
-- не сбросит прогресс случайно) и праздник после успеха.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))
local Loc = require(Shared:WaitForChild("Loc"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local RebirthUI = {}

local W, H = 780, 560
local CONFIRM_TIME = 3 -- сколько секунд ждём второе нажатие
local CONFIRM_GUARD = 0.8 -- первые столько секунд после «Точно?» нажатия не считаются
local CONFETTI = 28
local CONFETTI_COLORS = { Theme.Volt, Theme.Spark, Theme.Pink, Theme.Go, Theme.Violet, Theme.Orange }

local win: UIKit.Window
local multLabel: TextLabel
local multScale: UIScale
local zoneReq: UIKit.Status
local voltsReq: UIKit.Status
local voltsBar: UIKit.Bar
local bonusLabel: TextLabel
local countLabel: TextLabel -- число перезапусков в заголовке
local rebirthButton: TextButton
local confirmUntil = 0
local confirmFrom = 0 -- раньше этого (os.clock) второе нажатие игнорируется
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
	multLabel.Text = string.format("%s  ›  %s", multText(Economy.rebirthMult(r)), multText(Economy.rebirthMult(r + 1)))
	countLabel.Text = tostring(r)

	local needZone = Config.Rebirth.RequiredZone
	local zoneOk = d.Zone >= needZone
	zoneReq.set(if zoneOk then "check" else "cross", Loc.t("Открыть остров %d «%s»", needZone, Config.Zones[needZone].Name), if zoneOk then Theme.GoHi else Theme.DangerHi)

	local cost = Economy.rebirthCost(r)
	local voltsOk = d.Volts >= cost
	voltsReq.set(if voltsOk then "check" else "cross", Loc.t("Накопить ⚡ %s", Format.short(cost)), if voltsOk then Theme.GoHi else Theme.DangerHi)
	voltsBar.set(d.Volts / cost, string.format("%s / %s", Format.short(math.min(d.Volts, cost)), Format.short(cost)))
	voltsBar.setColor(if voltsOk then Theme.Go else Theme.Volt)

	local extraSlot = table.find(Config.Rebirth.PetSlotsAt, r + 1) ~= nil
	bonusLabel.Visible = extraSlot
	bonusLabel.Text = Loc.t("Бонус: +1 место для питомца!")

	if os.clock() < confirmUntil then
		return
	end
	if Economy.canRebirth(d) then
		UIKit.setButtonText(rebirthButton, Loc.t("Перезапуск"))
		UIKit.setButtonVariant(rebirthButton, "Danger")
	else
		UIKit.setButtonText(rebirthButton, Loc.t("Пока рано"))
		UIKit.setButtonVariant(rebirthButton, "Disabled")
	end
end

local function buildConfetti()
	for i = 1, CONFETTI do
		local f = UIKit.new("Frame", {
			Name = "Confetti" .. i,
			Size = if i % 3 == 0 then UDim2.fromOffset(18, 18) else UDim2.fromOffset(12, 24),
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
		FontFace = Theme.FontDisplay,
		Size = UDim2.fromOffset(W - 60, 130),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Rotation = -4,
		MaxTextSize = 56,
		NoStroke = false,
		Visible = false,
		ZIndex = 31,
		Parent = win.Root,
	})
	local cs = celebrateLabel:FindFirstChildOfClass("UIStroke")
	if cs then
		cs.Thickness = 5
	end
	UIKit.italicPad(celebrateLabel, 16)
	UIKit.gradientText(celebrateLabel, Color3.fromRGB(255, 255, 240), Theme.Volt, Theme.VoltLo)
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
	celebrateLabel.Text = Loc.t("ГЕНЕРАТОР ПЕРЕЗАПУЩЕН!\nВОЛЬТЫ %s", multText(newMult))
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
			ClientState.Toast:Fire(Loc.t("Сначала открой остров «%s»", Config.Zones[Config.Rebirth.RequiredZone].Name), "info")
		else
			ClientState.Toast:Fire(Loc.t("Не хватает ⚡ %s", Format.short(Economy.rebirthCost(d.Rebirths) - d.Volts)), "bad")
		end
		return
	end
	-- первое нажатие — подтверждение
	local now = os.clock()
	if now > confirmUntil then
		confirmFrom = now + CONFIRM_GUARD
		confirmUntil = confirmFrom + CONFIRM_TIME
		UIKit.setButtonText(rebirthButton, Loc.t("Точно? Жми ещё раз!"))
		-- пока второе нажатие не засчитывается, кнопка серая; потом — оранжевая с пружинкой
		UIKit.setButtonVariant(rebirthButton, "Disabled")
		task.delay(CONFIRM_GUARD, function()
			if os.clock() < confirmUntil and not busy then
				UIKit.setButtonVariant(rebirthButton, "Orange")
				local scale = rebirthButton:FindFirstChildOfClass("UIScale")
				if scale then
					UIKit.bump(scale, 0.1)
				end
			end
		end)
		task.delay(CONFIRM_GUARD + CONFIRM_TIME + 0.05, function()
			if os.clock() >= confirmUntil then
				refresh()
			end
		end)
		return
	end
	-- двойной тап: второе касание слишком рано — не считаем
	if now < confirmFrom then
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
		Text = Loc.t("Начни заново — и получай больше Вольт навсегда!"),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 0),
		MaxTextSize = 24,
		Parent = body,
	})
	UIKit.label({
		Name = "Line2",
		Text = Loc.t("Питомцы, фульгуриты, Тесла-дрон и Молниедекс остаются с тобой."),
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 32),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 19,
		Parent = body,
	})

	-- главное: множитель (D3 Oswald с градиентом Volt) и тег «МНОЖИТЕЛЬ ВОЛЬТ»
	local multCard = UIKit.card({
		Name = "Mult",
		Size = UDim2.new(1, -20, 0, 80),
		Position = UDim2.fromOffset(10, 64),
		Parent = body,
	})
	UIKit.tintCard(multCard, Theme.Night700:Lerp(Theme.Volt, 0.16), Theme.Night800, Theme.Volt)
	local tag, tagText = UIKit.tag({
		Name = "Tag",
		Size = UDim2.fromOffset(196, 26),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Rotation = -3,
		Parent = multCard,
	}, Loc.t("Множитель вольт"), 15)
	tag.ZIndex = 2
	tagText.TextColor3 = Theme.Volt
	multLabel = UIKit.label({
		Name = "Text",
		Text = "",
		FontFace = Theme.FontNumber,
		Size = UDim2.new(1, -250, 1, -10),
		Position = UDim2.new(0, 230, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		MaxTextSize = 52,
		NoStroke = false,
		Parent = multCard,
	})
	local ms = multLabel:FindFirstChildOfClass("UIStroke")
	if ms then
		ms.Thickness = 3
	end
	UIKit.gradientText(multLabel, Theme.VoltHi, Theme.Volt)
	multScale = UIKit.new("UIScale", { Scale = 1, Parent = multLabel }) :: UIScale

	-- что нужно
	local req = UIKit.card({
		Name = "Requirements",
		Size = UDim2.new(1, -20, 0, 110),
		Position = UDim2.fromOffset(10, 154),
		Parent = body,
	})
	local _rt, rtText = UIKit.tag({
		Name = "Title",
		Size = UDim2.fromOffset(120, 24),
		Position = UDim2.fromOffset(14, 8),
		Parent = req,
	}, Loc.t("Что нужно"), 14)
	rtText.TextColor3 = Theme.TextDim
	zoneReq = UIKit.status(req, UDim2.new(1, -28, 0, 26), UDim2.fromOffset(14, 40), 21)
	voltsReq = UIKit.status(req, UDim2.new(0.42, -14, 0, 26), UDim2.fromOffset(14, 74), 21)
	voltsBar = UIKit.bar({
		Name = "VoltsBar",
		Size = UDim2.new(0.58, -30, 0, 28),
		Position = UDim2.new(0.42, 4, 0, 73),
		Color = Theme.Volt,
		TextSize = 17,
		Parent = req,
	})

	-- что сбросится / что останется
	local function listCard(name: string, title: string, color: Color3, text: string, x: number)
		local c = UIKit.card({
			Name = name,
			Size = UDim2.new(0.5, -15, 0, 86),
			Position = UDim2.new(x, if x == 0 then 10 else 5, 0, 272),
			Parent = body,
		})
		UIKit.tintCard(c, Theme.Night700:Lerp(color, 0.12), Theme.Night800, color)
		local _tf, tl = UIKit.tag({
			Name = "Title",
			Size = UDim2.fromOffset(130, 24),
			Position = UDim2.fromOffset(10, 10),
			Parent = c,
		}, title, 14)
		tl.TextColor3 = color
		UIKit.label({
			Name = "Text",
			Text = text,
			Size = UDim2.new(1, -20, 0, 48),
			Position = UDim2.fromOffset(12, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxTextSize = 17,
			Parent = c,
		})
	end
	-- как в EconomyService.rebirth: доход в минуту тоже с нуля (награды «N минут дохода» — от минимума)
	listCard("Reset", Loc.t("Сбросится"), Theme.DangerHi, Loc.t("• Вольты и банка\n• улучшения и острова\n• доход в минуту"), 0)
	listCard("Keep", Loc.t("Останется"), Theme.GoHi, Loc.t("• питомцы и фульгуриты\n• осколки и Молниедекс\n• Тесла-дрон"), 0.5)

	bonusLabel = UIKit.label({
		Name = "Bonus",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 362),
		TextColor3 = Theme.Pink,
		MaxTextSize = 20,
		Visible = false,
		Parent = body,
	})

	rebirthButton = UIKit.button({
		Name = "Rebirth",
		Text = Loc.t("Перезапуск"),
		Color = Theme.Danger,
		Size = UDim2.fromOffset(380, 68),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 2),
		TextSize = 30,
		Parent = body,
	}, onRebirthPressed)
end

function RebirthUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Rebirth",
		Title = Loc.t("Перезапуск"),
		Icon = "♻",
		Width = W,
		Height = H,
		Accent = Theme.Orange,
		OnOpen = function()
			confirmUntil = 0
			confirmFrom = 0
			refresh()
			UIKit.bump(multScale, 0.12)
			ClientState.WindowOpened:Fire("Rebirth")
		end,
		OnClose = function()
			confirmUntil = 0
			ClientState.WindowClosed:Fire("Rebirth")
		end,
	})
	countLabel = UIKit.headerCounter(win, "♻", Theme.Orange, 110)
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
