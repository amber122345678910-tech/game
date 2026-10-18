--!strict
-- Уведомления: короткие тосты под банкой (до 3 сразу, исчезают сами) и большие баннеры
-- на весь сервер (редкая поимка, событие) — лента через верхнюю треть экрана.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local HUD = require(script.Parent.HUD)

local Notifications = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local TOAST_W = 470
local TOAST_H = 52
local TOAST_GAP = 6
local MAX_TOASTS = 3
local TOAST_LIFE = 2.5
local BANNER_TIME = 4
local BANNER_H = 112
local MAX_BANNER_QUEUE = 3

local KINDS = {
	info = { Color = Theme.ElectricDark, Icon = "💬" },
	good = { Color = Theme.GreenDark, Icon = "✅" },
	bad = { Color = Theme.RedDark, Icon = "⛔" },
	rare = { Color = Theme.PurpleDark, Icon = "✨" },
} :: { [string]: { Color: Color3, Icon: string } }

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
	icon: TextLabel,
	label: TextLabel,
	stroke: UIStroke,
	text: string,
	expires: number,
	token: number,
}

local gui: ScreenGui
local toastRoot: Frame
local active: { Toast } = {}
local pool: { Toast } = {}
local tokenCounter = 0

local function makeToast(): Toast
	local frame = UIKit.new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(TOAST_W, TOAST_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = WHITE,
		Visible = false,
		Parent = toastRoot,
	}) :: Frame
	UIKit.round(frame)
	local stroke = UIKit.stroke(frame, 3, Theme.Stroke)
	local grad = UIKit.gradient(frame, WHITE, WHITE)
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = frame }) :: UIScale
	local icon = UIKit.label({
		Name = "Icon",
		Text = "",
		Size = UDim2.fromOffset(TOAST_H - 12, TOAST_H - 12),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		MaxTextSize = 30,
		NoStroke = true,
		Parent = frame,
	})
	local label = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -(TOAST_H + 18), 1, -10),
		Position = UDim2.new(0, TOAST_H + 2, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = frame,
	})
	return {
		frame = frame,
		scale = scale,
		grad = grad,
		icon = icon,
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
	t.icon.Text = def.Icon
	t.grad.Color = ColorSequence.new(def.Color:Lerp(WHITE, 0.25), def.Color:Lerp(BLACK, 0.2))
	t.stroke.Color = if kind == "rare" then Theme.Volt else Theme.Stroke
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

-- Тосты висят под верхним блоком HUD (Вольты и банка)
local function placeToasts()
	local anchor = HUD.toastAnchor()
	if not anchor then
		toastRoot.Position = UDim2.new(0.5, 0, 0, 150)
		return
	end
	local bottom = anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y - gui.AbsolutePosition.Y
	toastRoot.Position = UDim2.new(0.5, 0, 0, math.floor(bottom + 4))
end

----------------------------------------------------------------------
-- Баннеры
----------------------------------------------------------------------
local bannerGui: ScreenGui
local band: Frame
local bandGrad: UIGradient
local bandLines: { Frame } = {}
local shine: Frame
local shineGrad: UIGradient
local bannerContent: Frame
local bannerScale: UIScale
local bannerLabel: TextLabel
local bannerTextScale: UIScale
local bannerQueue: { { text: string, kind: string, color: Color3? } } = {}
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
		return Color3.fromRGB(90, 50, 140)
	elseif kind == "rare" or kind == "epic" then
		return Theme.Purple
	elseif kind == "event" then
		return Theme.Supercell
	elseif kind == "city" then
		return Theme.Volt
	end
	return Theme.Electric
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
	band = UIKit.new("Frame", {
		Name = "Band",
		Size = UDim2.new(1, 0, 0, BANNER_H),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(-1, 0.24),
		BackgroundColor3 = WHITE,
		Visible = false,
		Parent = bannerGui,
	}) :: Frame
	bandGrad = UIKit.new("UIGradient", {
		Color = ColorSequence.new(Theme.Electric),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.12),
			NumberSequenceKeypoint.new(0.82, 0.12),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = band,
	}) :: UIGradient
	for i = 1, 2 do
		local line = UIKit.new("Frame", {
			Name = "Line" .. i,
			Size = UDim2.new(1, 0, 0, 4),
			AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1),
			Position = UDim2.fromScale(0, if i == 1 then 0 else 1),
			BackgroundColor3 = Theme.Volt,
			ZIndex = 2,
			Parent = band,
		}) :: Frame
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0),
				NumberSequenceKeypoint.new(0.8, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = line,
		})
		table.insert(bandLines, line)
	end
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
			NumberSequenceKeypoint.new(0.5, 0.55),
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
	bannerLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -40, 1, -20),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 58,
		ZIndex = 5,
		Parent = bannerContent,
	})
	local stroke = bannerLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3.5
	end
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
	bandGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(BLACK, 0.55)),
		ColorSequenceKeypoint.new(0.5, color:Lerp(BLACK, 0.15)),
		ColorSequenceKeypoint.new(1, color:Lerp(BLACK, 0.55)),
	})
	for _, line in bandLines do
		line.BackgroundColor3 = if shimmer then Theme.Volt else color:Lerp(WHITE, 0.4)
	end
	bannerLabel.Text = item.text
	band.Size = UDim2.new(1, 0, 0, math.floor(BANNER_H * baseScaleOf(bannerScale)))
	-- под верхним блоком HUD (на телефоне он занимает бóльшую долю высоты)
	local y = if UIKit.isPhone() then 0.43 else 0.36
	band.Position = UDim2.fromScale(-1, y)
	band.Visible = true
	bannerTextScale.Scale = 0.6
	UIKit.tween(band, 0.4, { Position = UDim2.fromScale(0, y) }, Enum.EasingStyle.Back)
	UIKit.tween(bannerTextScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	Sounds.play("Notify")
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
		local tw = UIKit.tween(band, 0.35, { Position = UDim2.fromScale(1, y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw.Completed:Once(function()
			band.Visible = false
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

local function showBanner(text: string, kind: string, color: Color3?)
	if #bannerQueue >= MAX_BANNER_QUEUE then
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, { text = text, kind = kind, color = color })
	playNextBanner()
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

	ClientState.Toast:Connect(function(text: string, kind: string)
		if typeof(text) == "string" and text ~= "" then
			showToast(text, if typeof(kind) == "string" then kind else "info")
		end
	end)

	task.spawn(function()
		Net.event("Banner").OnClientEvent:Connect(function(text: any, kind: any, color: any)
			if typeof(text) == "string" and text ~= "" then
				showBanner(text, if typeof(kind) == "string" then kind else "info", if typeof(color) == "Color3" then color else nil)
			end
		end)
	end)
end

-- Показать баннер локально (например, своё событие)
function Notifications.banner(text: string, kind: string?, color: Color3?)
	showBanner(text, kind or "info", color)
end

return Notifications
