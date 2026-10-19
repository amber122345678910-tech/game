--!strict
-- Уведомления (docs/STYLE.md §8.4): короткие тосты под банкой — ленты Ink с наклоном −2°, полосой акцента
-- и значком слева (до 3 сразу, исчезают сами) — и большие баннеры на весь сервер (редкая поимка, событие):
-- наклонная лента через экран со словами Montserrat Black Italic.
-- Свои праздники: открыт новый остров (баннер, фанфары, вспышка); при входе на остров — его название.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Loc = require(Shared:WaitForChild("Loc"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local HUD = require(script.Parent.HUD)

local Notifications = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local TOAST_W = 470
local TOAST_H = 52
local TOAST_GAP = 8
local MAX_TOASTS = 3
local TOAST_LIFE = 2.5
local TOAST_PHONE_SCALE = 1.3 -- на телефоне HUD мельче (до ×0.5) — тосты крупнее, чтобы читались
local BANNER_TIME = 4
local BANNER_H = 112
local MAX_BANNER_QUEUE = 3
local TITLE_TIME = 2.2 -- название острова при входе
local TITLE_FADE = 0.4

local KINDS = {
	info = { Color = Theme.Spark, Glyph = "bolt" },
	good = { Color = Theme.Go, Glyph = "check" },
	bad = { Color = Theme.Danger, Glyph = "cross" },
	rare = { Color = Theme.Violet, Glyph = "diamond" },
} :: { [string]: { Color: Color3, Glyph: string } }

local SHIMMER_KINDS = {
	rare = true,
	epic = true,
	legendary = true,
	mythic = true,
	rainbow = true,
	perun = true,
} :: { [string]: boolean }

----------------------------------------------------------------------
-- Тосты
----------------------------------------------------------------------
type Toast = {
	frame: Frame,
	scale: UIScale,
	grad: UIGradient,
	badge: Frame,
	glyphs: { [string]: Frame },
	label: TextLabel,
	stroke: UIStroke,
	text: string,
	expires: number,
	token: number,
}

local gui: ScreenGui
local toastRoot: Frame
local toastStack: Frame -- внутри toastRoot: свой масштаб для телефона
local toastStackScale: UIScale
local active: { Toast } = {}
local pool: { Toast } = {}
local tokenCounter = 0

local function makeToast(): Toast
	local frame = UIKit.new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(TOAST_W, TOAST_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Rotation = -2,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = toastStack,
	}) :: Frame
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = frame }) :: UIScale
	local shadow = UIKit.new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(10, 4),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.35,
		Parent = frame,
	})
	UIKit.corner(shadow, Theme.CornerSmall)
	-- лента Ink: полоса акцента слева (градиентом — повторяет скругление)
	local ribbon = UIKit.new("Frame", {
		Name = "Ribbon",
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundColor3 = WHITE,
		Parent = frame,
	}) :: Frame
	UIKit.corner(ribbon, Theme.CornerSmall)
	local stroke = UIKit.stroke(ribbon, 2.5, Theme.Ink)
	local grad = UIKit.new("UIGradient", { Rotation = 0, Parent = ribbon }) :: UIGradient
	local badge = UIKit.iconBadge(frame, "", Theme.Spark, TOAST_H - 12, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		ZIndex = 2,
	})
	local glyphs: { [string]: Frame } = {}
	for kind, def in KINDS do
		glyphs[kind] = UIKit.glyph(badge, def.Glyph, {
			Name = "Glyph_" .. kind,
			Size = UDim2.fromScale(0.6, 0.6),
			Stroke = 2,
			ZIndex = 2,
			Visible = false,
		})
	end
	local label = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -(TOAST_H + 22), 1, -12),
		Position = UDim2.new(0, TOAST_H + 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		ZIndex = 2,
		Parent = frame,
	})
	return {
		frame = frame,
		scale = scale,
		grad = grad,
		badge = badge,
		glyphs = glyphs,
		label = label,
		stroke = stroke,
		text = "",
		expires = 0,
		token = 0,
	}
end

local function layoutToasts()
	for i, t in active do
		local y = (i - 1) * (TOAST_H + TOAST_GAP)
		UIKit.tween(t.frame, 0.22, { Position = UDim2.new(0.5, 0, 0, y) }, Enum.EasingStyle.Back)
	end
end

local function releaseToast(t: Toast)
	local i = table.find(active, t)
	if i then
		table.remove(active, i)
	end
	t.token = -1
	local tw = UIKit.tween(t.scale, 0.15, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tw.Completed:Once(function()
		if t.token == -1 then
			t.frame.Visible = false
			table.insert(pool, t)
		end
	end)
	layoutToasts()
end

local function showToast(text: string, kind: string)
	-- тот же текст уже на экране — продлить и подпрыгнуть, а не дублировать
	for _, t in active do
		if t.text == text then
			t.expires = os.clock() + TOAST_LIFE
			UIKit.bump(t.scale, 0.1)
			return
		end
	end
	local def = KINDS[kind] or KINDS.info
	local t = table.remove(pool) or makeToast()
	tokenCounter += 1
	t.token = tokenCounter
	t.text = text
	t.expires = os.clock() + TOAST_LIFE
	t.label.Text = text
	local k = if KINDS[kind] then kind else "info"
	for gk, g in t.glyphs do
		g.Visible = gk == k
	end
	UIKit.setIconBadge(t.badge, nil, def.Color)
	local tones = UIKit.tones(def.Color)
	t.grad.Color = UIKit.seq({
		{ 0, tones.Base },
		{ 0.035, tones.Base },
		{ 0.045, Theme.Night700:Lerp(tones.Lo, 0.4) },
		{ 1, Theme.Ink:Lerp(tones.Lo, 0.15) },
	})
	t.stroke.Color = if kind == "rare" then Theme.Volt else Theme.Ink
	t.frame.Position = UDim2.new(0.5, 0, 0, 0)
	t.frame.Visible = true
	t.scale.Scale = 0.4
	UIKit.tween(t.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	table.insert(active, 1, t)
	while #active > MAX_TOASTS do
		releaseToast(active[#active])
	end
	layoutToasts()
	if kind == "bad" then
		Sounds.play("Error")
	elseif kind == "rare" then
		Sounds.play("Notify")
	end
	local token = t.token
	task.spawn(function()
		while t.token == token do
			local left = t.expires - os.clock()
			if left <= 0 then
				releaseToast(t)
				return
			end
			task.wait(math.min(left, 0.5))
		end
	end)
end

-- Подсказка обучения висит там же, под верхним блоком HUD: пока она есть, тосты встают под неё
local hintLaneBottom: number? = nil -- нижний край полосы подсказки (экранные точки) или nil
local placeTween: Tween? = nil

-- Тосты висят под верхним блоком HUD (Вольты и банка) и под подсказкой обучения
local function placeToasts(smooth: boolean?)
	if not toastRoot then
		return
	end
	local y = 150
	local anchor = HUD.toastAnchor()
	if anchor then
		y = anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y - gui.AbsolutePosition.Y + 4
	end
	local lane = hintLaneBottom
	if lane then
		y = math.max(y, lane - gui.AbsolutePosition.Y + 4)
	end
	local pos = UDim2.new(0.5, 0, 0, math.floor(y))
	local tw = placeTween
	if tw then
		tw:Cancel()
		placeTween = nil
	end
	if smooth then
		placeTween = UIKit.tween(toastRoot, 0.2, { Position = pos })
	else
		toastRoot.Position = pos
	end
end

----------------------------------------------------------------------
-- Баннеры
----------------------------------------------------------------------
local bannerGui: ScreenGui
local band: Frame
local bandShadow: Frame
local bandGrad: UIGradient
local bandChevrons: { Frame } = {}
local bannerGradText: UIGradient
local shine: Frame
local shineGrad: UIGradient
local bannerContent: Frame
local bannerScale: UIScale
local bannerLabel: TextLabel
local bannerTextScale: UIScale
local bannerQueue: { { text: string, kind: string, color: Color3?, sound: string? } } = {}
local bannerBusy = false
local shimmerTween: Tween? = nil

local function baseScaleOf(s: UIScale): number
	return (s:GetAttribute("BaseScale") :: number?) or s.Scale
end

local function bannerColor(kind: string, color: Color3?): Color3
	if color then
		return color
	end
	if kind == "legendary" then
		return Theme.Gold
	elseif kind == "mythic" or kind == "rainbow" then
		return Theme.Rainbow
	elseif kind == "perun" then
		return Theme.VioletLo
	elseif kind == "rare" or kind == "epic" then
		return Theme.Violet
	elseif kind == "event" then
		return Theme.Supercell
	elseif kind == "city" then
		return Theme.Volt
	end
	return Theme.Spark
end

local function buildBanner()
	bannerGui = UIKit.new("ScreenGui", {
		Name = "Banner",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 31,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	-- наклонная лента шире экрана (края уходят за границы), тень снизу, полосы акцента сверху и снизу
	bandShadow = UIKit.new("Frame", {
		Name = "BandShadow",
		Size = UDim2.new(1.2, 0, 0, BANNER_H),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.7, 0.24),
		Rotation = -2,
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.4,
		Visible = false,
		Parent = bannerGui,
	}) :: Frame
	band = UIKit.new("Frame", {
		Name = "Band",
		Size = UDim2.new(1.2, 0, 0, BANNER_H),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.7, 0.24),
		Rotation = -2,
		BackgroundColor3 = WHITE,
		Visible = false,
		ZIndex = 2,
		Parent = bannerGui,
	}) :: Frame
	UIKit.stroke(band, 3, Theme.Ink)
	bandGrad = UIKit.new("UIGradient", { Rotation = 90, Parent = band }) :: UIGradient
	-- блик, пробегающий по редким баннерам
	shine = UIKit.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 3,
		Parent = band,
	}) :: Frame
	shineGrad = UIKit.new("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = shine,
	}) :: UIGradient

	bannerContent = UIKit.new("Frame", {
		Name = "Content",
		Size = UDim2.fromOffset(1100, BANNER_H),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = band,
	}) :: Frame
	bannerScale = UIKit.autoScale(bannerContent, "hud", 1280, 720)
	-- шевроны-«молнии» по краям надписи
	for i, side in { -1, 1 } do
		for j = 0, 1 do
			local g = UIKit.glyph(bannerContent, "chevronRight", {
				Name = "Chevron" .. i .. j,
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(0.5, side * (500 - j * 30), 0.5, 0),
				Rotation = if side < 0 then 0 else 180,
				Color = Theme.Volt,
				Stroke = 2,
				ZIndex = 5,
			})
			table.insert(bandChevrons, g)
		end
	end
	bannerLabel = UIKit.label({
		Name = "Text",
		Text = "",
		FontFace = Theme.FontDisplay,
		Size = UDim2.new(1, -170, 1, -26),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 52,
		NoStroke = false,
		ZIndex = 6,
		Parent = bannerContent,
	})
	local stroke = bannerLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3.5
	end
	UIKit.italicPad(bannerLabel, 10)
	bannerGradText = UIKit.gradientText(bannerLabel, Theme.Cream, Theme.Cream)
	bannerTextScale = UIKit.new("UIScale", { Scale = 1, Parent = bannerLabel }) :: UIScale
end

local function playNextBanner()
	if bannerBusy then
		return
	end
	local item = table.remove(bannerQueue, 1)
	if not item then
		return
	end
	bannerBusy = true
	local color = bannerColor(item.kind, item.color)
	local shimmer = SHIMMER_KINDS[item.kind] == true
	local t = UIKit.tones(color)
	local stripe = if shimmer then Theme.Volt else t.Base
	bandGrad.Color = UIKit.seq({
		{ 0, stripe },
		{ 0.07, stripe },
		{ 0.08, t.Lo:Lerp(Theme.Ink, 0.35) },
		{ 0.5, Theme.Night800 },
		{ 0.92, Theme.Ink },
		{ 0.93, stripe },
		{ 1, stripe },
	})
	for _, g in bandChevrons do
		UIKit.setGlyphColor(g, stripe)
	end
	bannerGradText.Color = ColorSequence.new(Theme.Cream, t.Hi:Lerp(Theme.Cream, 0.3))
	bannerLabel.Text = item.text
	local h = math.floor(BANNER_H * baseScaleOf(bannerScale))
	band.Size = UDim2.new(1.2, 0, 0, h)
	bandShadow.Size = band.Size
	-- под верхним блоком HUD (на телефоне он занимает бóльшую долю высоты)
	local y = if UIKit.isPhone() then 0.43 else 0.36
	band.Position = UDim2.fromScale(-0.7, y)
	bandShadow.Position = UDim2.new(-0.7, 0, y, 8)
	band.Visible = true
	bandShadow.Visible = true
	bannerTextScale.Scale = 0.6
	UIKit.tween(band, 0.4, { Position = UDim2.fromScale(0.5, y) }, Enum.EasingStyle.Back)
	UIKit.tween(bandShadow, 0.4, { Position = UDim2.new(0.5, 0, y, 8) }, Enum.EasingStyle.Back)
	UIKit.tween(bannerTextScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	Sounds.play(item.sound or "Notify")
	if shimmer then
		shine.Visible = true
		shineGrad.Offset = Vector2.new(-1, 0)
		shimmerTween = TweenService:Create(
			shineGrad,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.25),
			{ Offset = Vector2.new(1, 0) }
		)
		local tw = shimmerTween
		if tw then
			tw:Play()
		end
	else
		shine.Visible = false
	end
	task.delay(BANNER_TIME - 0.4, function()
		UIKit.tween(bandShadow, 0.35, { Position = UDim2.new(1.7, 0, y, 8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tw = UIKit.tween(band, 0.35, { Position = UDim2.fromScale(1.7, y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw.Completed:Once(function()
			band.Visible = false
			bandShadow.Visible = false
			local st = shimmerTween
			if st then
				st:Cancel()
				shimmerTween = nil
			end
			shine.Visible = false
			bannerBusy = false
			playNextBanner()
		end)
	end)
end

local function showBanner(text: string, kind: string, color: Color3?, sound: string?)
	if #bannerQueue >= MAX_BANNER_QUEUE then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, { text = text, kind = kind, color = color, sound = sound })
	playNextBanner()
end

----------------------------------------------------------------------
-- Название острова при входе (короткая надпись под персонажем)
----------------------------------------------------------------------
local titleRoot: Frame
local titleName: TextLabel
local titleShadow: TextLabel
local titleGrad: UIGradient
local titleTag: Frame
local titleSub: TextLabel
local titleScale: UIScale
local titleToken = 0

local function buildTitle()
	titleRoot = UIKit.new("Frame", {
		Name = "ZoneTitle",
		Size = UDim2.fromOffset(780, 130),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Rotation = -3,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = bannerGui,
	}) :: Frame
	UIKit.autoScale(titleRoot, "hud", 1280, 720)
	local word = UIKit.new("Frame", {
		Name = "Word",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = titleRoot,
	}) :: Frame
	titleScale = UIKit.new("UIScale", { Scale = 1, Parent = word }) :: UIScale
	-- тег «ОСТРОВ 2» и название D1-стилем: градиент акцента острова, обводка, жёсткая тень
	titleTag, titleSub = UIKit.tag({
		Name = "Sub",
		Size = UDim2.fromOffset(150, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 3,
		Parent = word,
	}, Loc.t("Остров %d", 1), 19)
	titleName = UIKit.label({
		Name = "Name",
		Text = "",
		FontFace = Theme.FontDisplay,
		Size = UDim2.new(1, 0, 0, 90),
		Position = UDim2.fromOffset(0, 34),
		MaxTextSize = 72,
		NoStroke = false,
		ZIndex = 2,
		Parent = word,
	})
	local stroke = titleName:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
	end
	UIKit.italicPad(titleName, 16)
	titleGrad = UIKit.gradientText(titleName, Theme.Cream, Theme.Volt)
	titleShadow = UIKit.textShadow(titleName, 6)
end

local function fadeTitle(target: number, time: number)
	for _, l in { titleName, titleSub } do
		UIKit.tween(l, time, { TextTransparency = target })
		local stroke = l:FindFirstChildOfClass("UIStroke")
		if stroke then
			UIKit.tween(stroke, time, { Transparency = target })
		end
	end
	local ss = titleShadow:FindFirstChildOfClass("UIStroke")
	if ss then
		UIKit.tween(ss, time, { Transparency = target })
	end
	UIKit.tween(titleTag, time, { BackgroundTransparency = target })
	local ts = titleTag:FindFirstChildOfClass("UIStroke")
	if ts then
		UIKit.tween(ts, time, { Transparency = target })
	end
end

local function showTitle(zone: number)
	local name = Loc.t(Config.Hub.Name)
	local sub = Loc.t("zone::Город")
	local color = Theme.Volt
	if zone >= 1 and zone <= #Config.Zones then
		local def = Config.Zones[zone]
		name = Loc.t(def.Name)
		sub = Loc.t("Остров %d", zone)
		color = def.Accent
	elseif zone ~= 0 then
		return
	end
	titleToken += 1
	local token = titleToken
	titleName.Text = UIKit.upper(name)
	local t = UIKit.tones(color)
	titleGrad.Color = UIKit.seq({ { 0, Theme.Cream }, { 0.45, t.Hi }, { 1, t.Base } })
	titleSub.Text = UIKit.upper(sub)
	titleTag.Size = UDim2.fromOffset(math.max(120, (utf8.len(sub) or #sub) * 15 + 30), 30)
	fadeTitle(1, 0)
	titleRoot.Visible = true
	titleScale.Scale = 0.7
	UIKit.tween(titleScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	fadeTitle(0, TITLE_FADE)
	task.delay(TITLE_TIME, function()
		if token ~= titleToken then
			return
		end
		fadeTitle(1, TITLE_FADE)
		task.delay(TITLE_FADE + 0.05, function()
			if token == titleToken then
				titleRoot.Visible = false
			end
		end)
	end)
end

-- Свой новый остров: баннер с фанфарами, вспышка цветом острова и подсказка, как туда попасть
local function onZoneUnlocked(zone: number)
	local def = Config.Zones[zone]
	if not def then
		return
	end
	showBanner(Loc.t("Открыт остров %d: %s!", zone, def.Name), "rare", def.Accent, "LevelUp")
	Juice.flash(def.Accent, 0.3)
	showToast(Loc.t("Жми «Лететь» в окне «Острова» — и ты там!"), "good")
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
function Notifications.start()
	if gui then
		return
	end
	gui = UIKit.new("ScreenGui", {
		Name = "Toasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 30,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	toastRoot = UIKit.new("Frame", {
		Name = "Stack",
		Size = UDim2.fromOffset(TOAST_W, MAX_TOASTS * (TOAST_H + TOAST_GAP)),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(toastRoot, "hud", 1280, 720)
	toastStack = UIKit.new("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundTransparency = 1,
		Parent = toastRoot,
	}) :: Frame
	toastStackScale = UIKit.new("UIScale", { Scale = 1, Parent = toastStack }) :: UIScale
	local function fitPhone()
		toastStackScale.Scale = if UIKit.isPhone() then TOAST_PHONE_SCALE else 1
	end
	fitPhone()
	UIKit.onInputTypeChanged(fitPhone)
	toastRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPhone)
	for _ = 1, MAX_TOASTS + 1 do
		table.insert(pool, makeToast())
	end

	-- привязка к HUD (если HUD ещё не запущен — подождать его)
	task.spawn(function()
		for _ = 1, 40 do
			local anchor = HUD.toastAnchor()
			if anchor then
				anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeToasts)
				anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeToasts)
				placeToasts()
				return
			end
			placeToasts()
			task.wait(0.5)
		end
	end)

	buildBanner()
	buildTitle()

	ClientState.ZoneChanged:Connect(function(zone: number)
		showTitle(zone)
	end)
	ClientState.Effect:Connect(function(msg: Net.EffectMsg)
		local m = msg :: any
		if m.Kind == "zoneUnlocked" and typeof(m.Zone) == "number" and (m.UserId == nil or m.UserId == player.UserId) then
			onZoneUnlocked(m.Zone)
		end
	end)

	-- текст тоста и баннера — строка-исходник, уже переведённая строка или Loc.Msg от сервера:
	-- Loc.render рисует его на языке игрока (готовую строку оставляет как есть)
	ClientState.Toast:Connect(function(text: any, kind: any)
		if typeof(text) == "string" or typeof(text) == "table" then
			local s = Loc.render(text)
			if s ~= "" then
				showToast(s, if typeof(kind) == "string" then kind else "info")
			end
		end
	end)

	task.spawn(function()
		Net.event("Banner").OnClientEvent:Connect(function(text: any, kind: any, color: any)
			if typeof(text) == "string" or typeof(text) == "table" then
				local s = Loc.render(text)
				if s ~= "" then
					showBanner(s, if typeof(kind) == "string" then kind else "info", if typeof(color) == "Color3" then color else nil)
				end
			end
		end)
	end)
end

-- Обучение: подсказка заняла полосу под верхним блоком HUD до экранной высоты bottom (nil — освободила)
function Notifications.setHintLane(bottom: number?)
	local b = if bottom then math.floor(bottom) else nil
	if b == hintLaneBottom then
		return
	end
	hintLaneBottom = b
	placeToasts(true)
end

-- Показать баннер локально (например, своё событие); sound — вместо обычного звука баннера.
-- text — строка (исходник или уже Loc.t) или Loc.Msg
function Notifications.banner(text: string | Loc.Msg, kind: string?, color: Color3?, sound: string?)
	local s = Loc.render(text)
	if s ~= "" then
		showBanner(s, kind or "info", color, sound)
	end
end

-- Показать тост (то же, что ClientState.Toast:Fire): text — строка (исходник или уже Loc.t) или Loc.Msg
function Notifications.toast(text: string | Loc.Msg, kind: string?)
	local s = Loc.render(text)
	if s ~= "" and gui then
		showToast(s, kind or "info")
	end
end

return Notifications
