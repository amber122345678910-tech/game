--!strict
-- Всплывающие уведомления (тосты) под часами. Источник — ClientState.Notified(key, kind, args):
-- текст = Locale.t(key, args...), виды info | success | error | warning. Живут 3.5 с, не больше четырёх.
-- Аргументы-идентификаторы (предмет, перк, пациент) переводятся здесь, имена игроков идут как есть.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Inmates = require(Shared:WaitForChild("Inmates"))
local Locale = require(Shared:WaitForChild("Locale"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local Notifications = {}

local LIFETIME = 3.5
local MAX_TOASTS = 4
local DESIGN_W = 520
local TOP_OFFSET = 92 -- под панелью часов (пиксели макета HUD)

local holder: Frame
local order = 0
local lastKey = ""
local lastAt = 0

local KIND_COLORS: { [string]: Color3 } = {
	info = Theme.TextDim,
	success = Theme.Green,
	error = Theme.Red,
	warning = Theme.Amber,
}

local function localizeArg(value: any): any
	if type(value) == "string" then
		if Config.Items[value] then
			return Locale.item(value)
		elseif Config.Perks[value] then
			return Locale.perk(value)
		elseif Inmates.ById[value] then
			return Locale.inmateName(value)
		end
	elseif type(value) == "number" and value % 1 ~= 0 then
		return math.floor(value) -- %d не принимает дробные числа
	end
	return value
end

local function format(key: string, args: { any }?): string
	local list: { any } = {}
	if args then
		for i, v in args do
			list[i] = localizeArg(v)
		end
	end
	return Locale.t(key, table.unpack(list, 1, #list))
end

local function prune()
	local toasts: { Frame } = {}
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		table.sort(toasts, function(a: Frame, b: Frame)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #toasts - MAX_TOASTS do
			toasts[i]:Destroy()
		end
	end
end

local function show(key: string, kind: string, args: { any }?)
	local now = os.clock()
	if key == lastKey and now - lastAt < 0.5 then
		return -- дубль (например, сервер и магазин сообщили одно и то же)
	end
	lastKey, lastAt = key, now
	local color = KIND_COLORS[kind] or KIND_COLORS.info
	order += 1
	local toast = UIKit.new("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = holder,
	}) :: Frame
	UIKit.corner(toast, 4)
	local stroke = UIKit.new("UIStroke", { Thickness = 1, Color = color, Transparency = 1, Parent = toast }) :: UIStroke
	local accent = UIKit.new("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 4, 1, -10),
		Position = UDim2.new(0, 5, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		Parent = toast,
	}) :: Frame
	UIKit.corner(accent, 2)
	local label = UIKit.label({
		Name = "Text",
		Text = format(key, args),
		Size = UDim2.new(1, -30, 1, -10),
		Position = UDim2.new(0, 18, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		TextTransparency = 1,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = toast,
	})
	UIKit.tween(toast, 0.2, { BackgroundTransparency = 0.12 })
	UIKit.tween(stroke, 0.2, { Transparency = 0.45 })
	UIKit.tween(accent, 0.2, { BackgroundTransparency = 0 })
	UIKit.tween(label, 0.2, { TextTransparency = 0 })
	prune()

	if kind == "success" then
		UIKit.playUI(if key == "N_Sold" then "Coin" else "Success")
	elseif kind == "error" then
		UIKit.playUI("Fail")
	elseif kind == "warning" then
		UIKit.playUI("Notify")
	end

	task.delay(LIFETIME, function()
		if not toast.Parent then
			return
		end
		UIKit.tween(toast, 0.35, { BackgroundTransparency = 1 })
		UIKit.tween(stroke, 0.35, { Transparency = 1 })
		UIKit.tween(accent, 0.35, { BackgroundTransparency = 1 })
		UIKit.tween(label, 0.35, { TextTransparency = 1 })
		task.wait(0.4)
		toast:Destroy()
	end)
end

local function relayout()
	holder.Position = UDim2.new(0.5, 0, 0, UIKit.hudPx(TOP_OFFSET))
end

function Notifications.init()
	local gui = UIKit.new("ScreenGui", {
		Name = "Notifications",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	holder = UIKit.new("Frame", {
		Name = "Toasts",
		Size = UDim2.fromOffset(DESIGN_W, 260),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(holder, "hud")
	UIKit.list(holder, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	relayout()
	UIKit.onLayoutChanged(relayout)

	ClientState.Notified:Connect(show)
end

-- Локальное уведомление (ключ Locale) из других модулей.
function Notifications.show(key: string, kind: string, args: { any }?)
	show(key, kind, args)
end

return Notifications
