--!strict
-- Награды: календарь на 7 дней (приз 7-го дня виден сразу), задания дня и ввод кода.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Pets = require(Shared:WaitForChild("Pets"))
local Quests = require(Shared:WaitForChild("Quests"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local DailyUI = {}

local WHITE = Color3.new(1, 1, 1)
local TILE = Vector2.new(112, 118)
local BIG_TILE = Vector2.new(150, 246)
local LEFT_W = 520
local RIGHT_X = 536

type DayTile = {
	day: number,
	frame: Frame,
	scale: UIScale,
	stroke: UIStroke,
	check: Frame,
	dayLabel: TextLabel,
	glowTween: Tween?,
}

type QuestRow = {
	frame: Frame,
	text: TextLabel,
	bar: UIKit.Bar,
	reward: TextLabel,
	button: TextButton,
	done: Frame,
}

local win: UIKit.Window
local tiles: { DayTile } = {}
local claimButton: TextButton
local streakLabel: TextLabel
local questRows: { QuestRow } = {}
local codeBox: TextBox
local busy = false

-- приз 7-го дня (питомец) крутится в превью
local bigVp: ViewportFrame? = nil
local bigCam: Camera? = nil
local bigCenter = Vector3.zero
local bigDist = 8
local spinConn: RBXScriptConnection? = nil

----------------------------------------------------------------------
-- Календарь
----------------------------------------------------------------------
-- (можно забрать сегодня, номер дня для подсветки, сколько дней уже отмечено)
-- День — по серверному времени (как DailyService), а не по часам устройства: они могут врать
local function serverNow(): number
	return math.floor(ClientState.now())
end

local function dailyState(d: PlayerData.Data): (boolean, number, number)
	local today = Quests.dayNumber(serverNow())
	local claimable = today > d.Daily.LastDay
	local streak = math.clamp(d.Daily.Streak, 0, #Config.DailyRewards)
	if claimable then
		-- один пропущенный день прощается, больше — серия начинается заново
		local broken = d.Daily.LastDay > 0 and today - d.Daily.LastDay > 2
		if broken or streak >= #Config.DailyRewards then
			return true, 1, 0
		end
		return true, streak + 1, streak
	end
	return false, math.max(1, streak), streak
end

local function rewardLines(r: { Kind: string, Amount: number?, Shards: number?, Cocoon: string?, Pet: string? }, d: PlayerData.Data?): (string, string)
	if r.Kind == "volts" then
		local volts = if d then Economy.incomeMinutes(d, r.Amount or 0) else 0
		local second = if r.Shards then "💎 " .. Format.short(r.Shards) else ""
		return "⚡ " .. Format.short(volts), second
	elseif r.Kind == "shards" then
		return "💎 " .. Format.short(r.Amount or 0), ""
	elseif r.Kind == "cocoon" then
		local c = r.Cocoon and Pets.Cocoons[r.Cocoon]
		return "🥚", if c then c.Name else "Кокон"
	elseif r.Kind == "boost" then
		return "×2 ⚡", string.format("%d мин", r.Amount or 0)
	elseif r.Kind == "pet" then
		local p = r.Pet and Pets.Kinds[r.Pet]
		return "🐾", if p then p.Name else "Питомец"
	end
	return "🎁", ""
end

local function makeTile(parent: Instance, day: number, size: Vector2, pos: UDim2): DayTile
	local big = day == #Config.DailyRewards
	local frame = UIKit.card({
		Name = "Day" .. day,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = pos,
		Parent = parent,
	})
	if big then
		UIKit.tintCard(frame, Theme.Night700:Lerp(Theme.Volt, 0.2), Theme.Night800, Theme.Volt)
	end
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = frame }) :: UIScale
	local dayLabel = UIKit.label({
		Name = "Day",
		Text = "ДЕНЬ " .. day,
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.fromOffset(10, if big then 10 else 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if big then Theme.Volt else Theme.TextDim,
		MaxTextSize = 17,
		Parent = frame,
	})
	local check = UIKit.checkBadge(frame, 30, {
		Name = "Check",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
	})
	return { day = day, frame = frame, scale = scale, stroke = stroke, check = check, dayLabel = dayLabel, glowTween = nil }
end

local function fillSmallTile(t: DayTile)
	local r = Config.DailyRewards[t.day]
	local a, b = rewardLines(r, nil)
	local main = UIKit.label({
		Name = "Main",
		Text = a,
		FontFace = Theme.FontNumber,
		Size = UDim2.new(1, -12, 0, 40),
		Position = UDim2.fromOffset(6, 32),
		TextColor3 = if r.Kind == "volts" then Theme.Volt else Theme.Cream,
		MaxTextSize = 30,
		NoStroke = false,
		Parent = t.frame,
	})
	if r.Kind == "volts" then
		UIKit.gradientText(main, Theme.VoltHi, Theme.Volt)
	end
	UIKit.label({
		Name = "Second",
		Text = b,
		FontFace = if r.Kind == "volts" then Theme.FontNumber else Theme.FontBodyHeavy,
		Size = UDim2.new(1, -12, 0, 34),
		Position = UDim2.fromOffset(6, 74),
		TextColor3 = if r.Kind == "volts" then Theme.Shard else Theme.TextDim,
		MaxTextSize = if r.Kind == "volts" then 22 else 17,
		Parent = t.frame,
	})
end

local function fillBigTile(t: DayTile)
	local r = Config.DailyRewards[t.day]
	local petKind = if r.Kind == "pet" then r.Pet else nil
	if petKind and Pets.Kinds[petKind] then
		local def = Pets.Kinds[petKind]
		local rar = Pets.Rarities[def.Rarity]
		local _well, vp, cam = UIKit.previewWell({
			Size = UDim2.new(1, -16, 0, 120),
			Position = UDim2.fromOffset(8, 36),
			Parent = t.frame,
		})
		local ok, model = pcall(function()
			return Models.pet(petKind)
		end)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			model.Parent = vp
			bigCenter, bigDist = UIKit.frameModel(model, cam.FieldOfView, 0.7)
			UIKit.orbit(cam, bigCenter, bigDist, 0, 0.2)
			bigVp, bigCam = vp, cam
		end
		UIKit.label({
			Name = "Name",
			Text = def.Name,
			FontFace = Theme.FontDisplayFlat,
			Size = UDim2.new(1, -10, 0, 28),
			Position = UDim2.fromOffset(5, 160),
			TextColor3 = rar.Color:Lerp(WHITE, 0.35),
			MaxTextSize = 22,
			Parent = t.frame,
		})
		local tag, tagText = UIKit.tag({
			Name = "Rarity",
			Size = UDim2.new(1, -24, 0, 22),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 190),
			Rotation = -2,
			BackgroundColor3 = rar.Color,
			Parent = t.frame,
		}, rar.Name, 13)
		tag.ZIndex = 1
		tagText.TextColor3 = Theme.Ink
		UIKit.label({
			Name = "Bonus",
			Text = Pets.bonusText(petKind),
			FontFace = Theme.FontBodyHeavy,
			Size = UDim2.new(1, -12, 0, 20),
			Position = UDim2.fromOffset(6, 218),
			TextColor3 = Theme.Volt,
			MaxTextSize = 15,
			Parent = t.frame,
		})
	else
		local a, b = rewardLines(r, nil)
		UIKit.label({
			Name = "Main",
			Text = a,
			FontFace = Theme.FontNumber,
			Size = UDim2.new(1, -10, 0, 80),
			Position = UDim2.fromOffset(5, 60),
			MaxTextSize = 56,
			NoStroke = false,
			Parent = t.frame,
		})
		UIKit.label({
			Name = "Second",
			Text = b,
			FontFace = Theme.FontBodyHeavy,
			Size = UDim2.new(1, -10, 0, 40),
			Position = UDim2.fromOffset(5, 150),
			MaxTextSize = 24,
			Parent = t.frame,
		})
	end
end

local function setTileGlow(t: DayTile, on: boolean)
	if on and not t.glowTween then
		t.stroke.Color = Theme.Volt
		t.stroke.Thickness = 4
		t.stroke.Transparency = 0
		local tw = TweenService:Create(t.stroke, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
		tw:Play()
		t.glowTween = tw
	elseif not on and t.glowTween then
		local tw = t.glowTween
		if tw then
			tw:Cancel()
		end
		t.glowTween = nil
		t.stroke.Color = Theme.LineLight
		t.stroke.Thickness = 1.5
		t.stroke.Transparency = 0.7
	end
end

local function refreshCalendar(d: PlayerData.Data)
	local claimable, current, done = dailyState(d)
	for _, t in tiles do
		local r = Config.DailyRewards[t.day]
		if t.day ~= #Config.DailyRewards and r.Kind == "volts" then
			-- сумма Вольт зависит от текущего дохода
			local main = t.frame:FindFirstChild("Main")
			if main and main:IsA("TextLabel") then
				main.Text = (rewardLines(r, d))
			end
		end
		local claimed = t.day <= done
		t.check.Visible = claimed
		-- забранные дни чуть темнее
		t.frame.BackgroundTransparency = if claimed and not (t.day == current and not claimable) then 0.35 else 0
		local highlight = t.day == current
		setTileGlow(t, highlight and claimable)
		if highlight and claimable then
			t.dayLabel.Text = "СЕГОДНЯ!"
			t.dayLabel.TextColor3 = Theme.Volt
		elseif highlight and claimed then
			t.dayLabel.Text = "СЕГОДНЯ"
			t.dayLabel.TextColor3 = Theme.GoHi
		else
			t.dayLabel.Text = "ДЕНЬ " .. t.day
			t.dayLabel.TextColor3 = if t.day == #Config.DailyRewards then Theme.Volt else Theme.TextDim
		end
	end
	local streak = math.max(done, if claimable then 0 else d.Daily.Streak)
	streakLabel.Text = string.format("Серия: %d %s", streak, Format.plural(streak, "день", "дня", "дней"))
	if claimable then
		UIKit.setButtonStyle(claimButton, "verb")
		UIKit.setButtonText(claimButton, "Забрать")
		UIKit.setButtonVariant(claimButton, "Go")
	else
		local left = 86400 - (serverNow() % 86400)
		UIKit.setButtonStyle(claimButton, "plain")
		UIKit.setButtonText(claimButton, "Ещё через " .. Format.time(left))
		UIKit.setButtonVariant(claimButton, "Disabled")
	end
end

local function buildCalendar(body: Frame)
	UIKit.label({
		Name = "CalTitle",
		Text = "Заходи каждый день — подарок!",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(LEFT_W, 32),
		Position = UDim2.fromOffset(0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = body,
	})
	local cal = UIKit.new("Frame", {
		Name = "Calendar",
		Size = UDim2.fromOffset(LEFT_W, BIG_TILE.Y),
		Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		Parent = body,
	}) :: Frame
	local n = #Config.DailyRewards
	for day = 1, n - 1 do
		local col = (day - 1) % 3
		local row = (day - 1) // 3
		local t = makeTile(cal, day, TILE, UDim2.fromOffset(col * (TILE.X + 10), row * (TILE.Y + 10)))
		fillSmallTile(t)
		table.insert(tiles, t)
	end
	local big = makeTile(cal, n, BIG_TILE, UDim2.fromOffset(3 * (TILE.X + 10) + 6, 0))
	fillBigTile(big)
	table.insert(tiles, big)

	claimButton = UIKit.button({
		Name = "Claim",
		Text = "Забрать",
		Color = Theme.Go,
		Size = UDim2.fromOffset(300, 72),
		Position = UDim2.fromOffset(0, 40 + BIG_TILE.Y + 14),
		TextSize = 32,
		Parent = body,
	}, function()
		local d = ClientState.get()
		if busy or not d then
			return
		end
		local claimable, current = dailyState(d)
		if not claimable then
			Sounds.play("Error")
			ClientState.Toast:Fire("Сегодняшний подарок уже получен — приходи завтра!", "info")
			return
		end
		busy = true
		local ok, result = ClientState.request(Net.Actions.ClaimDaily, nil)
		busy = false
		if ok then
			Sounds.play("Purchase")
			Sounds.play("Coins")
			Juice.flash(Theme.Gold, 0.3)
			local t = tiles[current]
			if t then
				UIKit.bump(t.scale, 0.2)
			end
			if typeof(result) == "string" and result ~= "" then
				ClientState.Toast:Fire(result, "good")
			end
		else
			Sounds.play("Error")
		end
	end)
	streakLabel = UIKit.label({
		Name = "Streak",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(LEFT_W - 316, 40),
		Position = UDim2.fromOffset(316, 40 + BIG_TILE.Y + 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Orange,
		MaxTextSize = 24,
		Parent = body,
	})
	UIKit.label({
		Name = "Freeze",
		Text = "Пропущен один день? Серия не сгорит!",
		Size = UDim2.fromOffset(LEFT_W, 24),
		Position = UDim2.fromOffset(0, 40 + BIG_TILE.Y + 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
		Parent = body,
	})
end

----------------------------------------------------------------------
-- Задания дня
----------------------------------------------------------------------
local function questText(q: { Id: string, Target: number }): string
	local def = Quests.def(q.Id)
	if not def then
		return q.Id
	end
	local ok, text = pcall(Quests.text, def, q.Target)
	return if ok then text else def.Text
end

local function refreshQuests(d: PlayerData.Data)
	for i, row in questRows do
		local q = d.Quests.List[i]
		if not q then
			row.frame.Visible = false
			continue
		end
		row.frame.Visible = true
		local def = Quests.def(q.Id)
		row.text.Text = questText(q)
		local progress = math.min(q.Progress, q.Target)
		local complete = q.Progress >= q.Target
		row.bar.set(progress / math.max(1, q.Target), string.format("%d/%d", progress, q.Target))
		row.bar.setColor(if complete then Theme.Go else Theme.Spark)
		if def then
			-- сколько Вольт — как посчитает сервер: минуты дохода от текущего дохода в минуту
			row.reward.Text = string.format("💎 %s + ⚡ %s", Format.short(def.Shards), Format.short(Economy.incomeMinutes(d, def.Minutes)))
		else
			row.reward.Text = ""
		end
		if q.Claimed then
			row.button.Visible = false
			row.done.Visible = true
		else
			row.done.Visible = false
			row.button.Visible = true
			UIKit.setButtonVariant(row.button, if complete then "Go" else "Disabled")
			UIKit.setButtonText(row.button, "Забрать")
		end
	end
end

local function buildQuests(body: Frame)
	local w = 848 - RIGHT_X
	UIKit.label({
		Name = "QuestTitle",
		Text = "Задания дня",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(w, 32),
		Position = UDim2.fromOffset(RIGHT_X, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Parent = body,
	})
	for i = 1, 3 do
		local frame = UIKit.card({
			Name = "Quest" .. i,
			Size = UDim2.fromOffset(w, 90),
			Position = UDim2.fromOffset(RIGHT_X, 40 + (i - 1) * 98),
			Parent = body,
		})
		local text = UIKit.label({
			Name = "Text",
			Text = "",
			FontFace = Theme.FontBodyHeavy,
			Size = UDim2.new(1, -118, 0, 28),
			Position = UDim2.fromOffset(12, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 19,
			Parent = frame,
		})
		local bar = UIKit.bar({
			Name = "Progress",
			Size = UDim2.new(1, -134, 0, 22),
			Position = UDim2.fromOffset(12, 36),
			Color = Theme.Spark,
			TextSize = 15,
			Parent = frame,
		})
		local reward = UIKit.label({
			Name = "Reward",
			Text = "",
			Size = UDim2.new(1, -118, 0, 22),
			Position = UDim2.fromOffset(12, 62),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Shard,
			MaxTextSize = 16,
			Parent = frame,
		})
		local button = UIKit.button({
			Name = "Claim",
			Text = "Забрать",
			Color = Theme.Go,
			Size = UDim2.fromOffset(100, 64),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			TextSize = 22,
			Parent = frame,
		}, function()
			local d = ClientState.get()
			if busy or not d then
				return
			end
			local q = d.Quests.List[i]
			if not q or q.Claimed then
				return
			end
			if q.Progress < q.Target then
				Sounds.play("Error")
				ClientState.Toast:Fire(string.format("Ещё не выполнено: осталось %d", math.max(0, q.Target - q.Progress)), "info")
				return
			end
			busy = true
			local ok, result = ClientState.request(Net.Actions.ClaimQuest, i)
			busy = false
			if ok then
				Sounds.play("Coins")
				Sounds.play("PowerUp")
				-- сервер отвечает текстом награды («+1.2K ⚡ и +50 💎»)
				local reward = if typeof(result) == "string" and result ~= "" and result ~= "✅" then result else nil
				ClientState.Toast:Fire(if reward then "Награда: " .. reward else "Награда получена!", "good")
				local scale = frame:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = frame }) :: UIScale
				UIKit.bump(scale, 0.06)
			else
				Sounds.play("Error")
			end
		end)
		local done = UIKit.checkBadge(frame, 50, {
			Name = "Done",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -34, 0.5, 0),
		})
		table.insert(questRows, { frame = frame, text = text, bar = bar, reward = reward, button = button, done = done })
	end
end

----------------------------------------------------------------------
-- Коды
----------------------------------------------------------------------
local function redeem()
	local text = string.gsub(codeBox.Text, "^%s*(.-)%s*$", "%1")
	if text == "" then
		Sounds.play("Error")
		ClientState.Toast:Fire("Введи код", "info")
		return
	end
	if busy then
		return
	end
	busy = true
	local ok, result = ClientState.request(Net.Actions.RedeemCode, text)
	busy = false
	if ok then
		Sounds.play("PowerUp")
		codeBox.Text = ""
		ClientState.Toast:Fire(if typeof(result) == "string" and result ~= "" then result else "Код сработал!", "good")
	else
		Sounds.play("Error")
	end
end

local function buildCode(body: Frame)
	local w = 848 - RIGHT_X
	local y = 40 + 3 * 98 + 4
	local frame = UIKit.card({
		Name = "Code",
		Size = UDim2.fromOffset(w, 84),
		Position = UDim2.fromOffset(RIGHT_X, y),
		Parent = body,
	})
	UIKit.tintCard(frame, Theme.Night700:Lerp(Theme.Violet, 0.2), Theme.Night800, Theme.Violet)
	codeBox = UIKit.new("TextBox", {
		Name = "Input",
		Size = UDim2.new(1, -128, 0, 58),
		Position = UDim2.new(0, 12, 0.5, 2),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Well,
		Text = "",
		PlaceholderText = "Ввести код",
		PlaceholderColor3 = Theme.TextDim,
		TextColor3 = Theme.Cream,
		FontFace = Theme.FontBody,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = frame,
	}) :: TextBox
	UIKit.corner(codeBox, 8)
	UIKit.stroke(codeBox, 2, Theme.LineLight, 0.55)
	UIKit.padding(codeBox, 12, 10)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 10, Parent = codeBox })
	codeBox.FocusLost:Connect(function(enter: boolean)
		if enter then
			redeem()
		end
	end)
	UIKit.button({
		Name = "Redeem",
		Text = "ОК",
		Color = Theme.Violet,
		Size = UDim2.fromOffset(100, 64),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		TextSize = 28,
		Parent = frame,
	}, redeem)
end

----------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------
local function refresh()
	local d = ClientState.get()
	if not d or not win.isOpen() then
		return
	end
	refreshCalendar(d)
	refreshQuests(d)
end

function DailyUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Daily",
		Title = "Награды",
		Icon = "🎁",
		Width = 880,
		Height = 560,
		Accent = Theme.Go,
		OnOpen = function()
			refresh()
			local vp, cam = bigVp, bigCam
			if vp and cam and not spinConn then
				local yaw = 0
				spinConn = RunService.Heartbeat:Connect(function(dt: number)
					yaw += dt * 0.9
					UIKit.orbit(cam, bigCenter, bigDist, yaw, 0.2)
				end)
			end
			ClientState.WindowOpened:Fire("Daily")
		end,
		OnClose = function()
			local c = spinConn
			spinConn = nil
			if c then
				c:Disconnect()
			end
			ClientState.WindowClosed:Fire("Daily")
		end,
	})
	buildCalendar(win.Body)
	buildQuests(win.Body)
	buildCode(win.Body)

	ClientState.Changed:Connect(function(_d: PlayerData.Data)
		refresh()
	end)
	-- обратный отсчёт до следующей награды
	task.spawn(function()
		while win.Gui.Parent do
			if win.isOpen() then
				refresh()
			end
			task.wait(1)
		end
	end)
	ClientState.OpenWindow:Connect(function(name: string)
		local base = UIKit.parseWindowName(name)
		if base == "Daily" or base == "Quests" or base == "Rewards" then
			win.open()
		end
	end)
end

function DailyUI.open()
	if win then
		win.open()
	end
end

-- Можно ли сейчас что-то забрать (для значков)
function DailyUI.hasClaimable(): boolean
	local d = ClientState.get()
	if not d then
		return false
	end
	if (dailyState(d)) then
		return true
	end
	for _, q in d.Quests.List do
		if q.Progress >= q.Target and not q.Claimed then
			return true
		end
	end
	return false
end

return DailyUI
