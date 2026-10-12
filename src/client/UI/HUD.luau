--!strict
-- HUD матча: часы и ночь (верх-центр), наличные/яблоки (верх-право), статус и правила пациентов (верх-лево),
-- хотбар с фонариком и батареей (низ-центр), выносливость, кнопка «пропустить оповещение»,
-- дыхание в укрытии, оверлеи «повален» и «забран» (со спектатором).
-- Виден только в матче при статусе Alive/Downed/Hiding; в лобби и на итогах скрыт.
-- Низ-лево (джойстик) и низ-право (кнопки действий контроллеров) на сенсорных экранах не занимаем.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local HUD = {}

local SLOT_MOUSE, SLOT_TOUCH = 64, 96
local BTN_MOUSE, BTN_TOUCH = 48, 92
local SLOT_GAP = 8
local DOCK_MARGIN = 10
local GEAR_SPACE_MOUSE, GEAR_SPACE_TOUCH = 56, 76 -- место под шестерёнку настроек справа

local gui: ScreenGui -- панели HUD (с учётом верхней панели Roblox)
local fxGui: ScreenGui -- полноэкранная красная виньетка «повален»
local takenGui: ScreenGui -- оверлей «забран» + спектатор

-- верх
local clockLabel: TextLabel
local nightLabel: TextLabel
local phaseLabel: TextLabel
local phaseFill: Frame
local cashPanel: Frame
local cashLabel: TextLabel
local applesLabel: TextLabel
local treesLabel: TextLabel
local aliveLabel: TextLabel
local crouchPill: Frame
local crouchLabel: TextLabel
local ruleLabels: { TextLabel } = {}

-- низ
local hotbar: Frame
local slots: { TextButton } = {}
local slotNames: { TextLabel } = {}
local slotCounts: { TextLabel } = {}
local slotStrokes: { UIStroke } = {}
local flashSlot: TextButton
local flashStroke: UIStroke
local flashName: TextLabel
local batteryFill: Frame
local staminaGroup: CanvasGroup
local staminaFill: Frame
local staminaShown = false
local skipButton: TextButton
local skipVoted = false

-- укрытие
local hidePanel: Frame
local breathTitle: TextLabel
local breathFill: Frame
local breathStroke: UIStroke
local breathLow = false
local holdHint: TextLabel
local leaveHint: TextLabel

-- повален
local vignette: { Frame } = {}
local downedLabel: TextLabel
local downedTimer: TextLabel
local downedUntil = 0

-- забран / спектатор
local takenTitle: TextLabel
local takenHint: TextLabel
local spectateLabel: TextLabel
local spectatePrev: TextButton
local spectateNext: TextButton
local spectateName = ""
local spectateBound = false
local participated = false -- был ли игрок живым в этом матче (статус Spectating = «забран насовсем»)

----------------------------------------------------------------------
-- Помощники
----------------------------------------------------------------------
local function shortItemName(id: string): string
	local name = Locale.item(id)
	local stripped = string.gsub(name, "%s*%b()", "") -- «Planks (x3)» → «Planks»
	return stripped
end

local function countText(slot: Remotes.InventorySlot, def: Config.ItemDef): string
	if def.Kind == "Weapon" and def.Charges > 0 then
		return string.format("%d/%d", math.floor(slot.Charges or 0), def.Charges)
	end
	local count = slot.Count or 1
	if count > 1 then
		return string.format("x%d", math.floor(count))
	end
	return ""
end

local function makeVignette(parent: Instance, color: Color3): { Frame }
	local frames: { Frame } = {}
	local edges = {
		{ UDim2.new(1, 0, 0.25, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.25, 0), UDim2.fromScale(0, 0.75), 270 },
		{ UDim2.new(0.2, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.2, 0, 1, 0), UDim2.fromScale(0.8, 0), 180 },
	}
	for _, e in edges do
		local f = UIKit.new("Frame", {
			Name = "Vignette",
			Size = e[1],
			Position = e[2],
			BackgroundColor3 = color,
			BackgroundTransparency = 0.5,
			Parent = parent,
		}) :: Frame
		UIKit.new("UIGradient", {
			Rotation = e[3],
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
		table.insert(frames, f)
	end
	return frames
end

local function makeSlot(parent: Instance, keyHint: string, name: string): (TextButton, TextLabel, TextLabel, UIStroke)
	local slot = UIKit.new("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(SLOT_MOUSE, SLOT_MOUSE),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.35,
		Text = "",
		AutoButtonColor = false,
		Parent = parent,
	}) :: TextButton
	UIKit.corner(slot, 6)
	local stroke = UIKit.new("UIStroke", { Thickness = 1, Color = Theme.GrayDark, Transparency = 0.3, Parent = slot }) :: UIStroke
	UIKit.label({
		Name = "Key",
		Text = keyHint,
		Size = UDim2.new(0.4, 0, 0.24, 0),
		Position = UDim2.new(0, 5, 0, 3),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 12,
		NoStroke = true,
		Parent = slot,
	})
	local itemName = UIKit.label({
		Name = "ItemName",
		Text = "",
		Size = UDim2.new(1, -8, 0.44, 0),
		Position = UDim2.new(0.5, 0, 0.52, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = Theme.FontBold,
		MaxTextSize = 15,
		NoStroke = true,
		Parent = slot,
	})
	local count = UIKit.label({
		Name = "Count",
		Text = "",
		Size = UDim2.new(0.6, 0, 0.24, 0),
		Position = UDim2.new(1, -5, 1, -3),
		AnchorPoint = Vector2.new(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 13,
		NoStroke = true,
		Parent = slot,
	})
	return slot, itemName, count, stroke
end

----------------------------------------------------------------------
-- Построение
----------------------------------------------------------------------
local function buildTop()
	-- часы, ночь, фаза
	local clockPanel = UIKit.panel({
		Name = "Clock",
		Size = UDim2.fromOffset(300, 74),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	UIKit.thinStroke(clockPanel, Theme.GrayDark, 0.2)
	UIKit.autoScale(clockPanel, "hud")
	clockLabel = UIKit.label({
		Name = "Time",
		Text = "7:00 AM",
		Size = UDim2.new(0.5, -10, 0, 34),
		Position = UDim2.fromOffset(12, 7),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 30,
		NoStroke = true,
		Parent = clockPanel,
	})
	nightLabel = UIKit.label({
		Name = "Night",
		Text = "",
		Size = UDim2.new(0.5, -10, 0, 34),
		Position = UDim2.new(1, -12, 0, 7),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontBold,
		MaxTextSize = 20,
		NoStroke = true,
		Parent = clockPanel,
	})
	phaseLabel = UIKit.label({
		Name = "Phase",
		Text = "",
		Size = UDim2.new(1, -24, 0, 18),
		Position = UDim2.new(0.5, 0, 0, 42),
		AnchorPoint = Vector2.new(0.5, 0),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		NoStroke = true,
		Parent = clockPanel,
	})
	local _, fill = UIKit.bar({
		Name = "PhaseBar",
		Size = UDim2.new(1, -20, 0, 3),
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = clockPanel,
	}, Theme.Amber)
	phaseFill = fill

	-- наличные, яблоки, деревья
	cashPanel = UIKit.panel({
		Name = "Cash",
		Size = UDim2.fromOffset(190, 74),
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	UIKit.thinStroke(cashPanel, Theme.GrayDark, 0.2)
	UIKit.autoScale(cashPanel, "hud")
	cashLabel = UIKit.label({
		Name = "Cash",
		Text = "$0",
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Cash,
		MaxTextSize = 26,
		NoStroke = true,
		Parent = cashPanel,
	})
	applesLabel = UIKit.label({
		Name = "Apples",
		Text = "",
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontBold,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = cashPanel,
	})
	treesLabel = UIKit.label({
		Name = "Trees",
		Text = "",
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.fromOffset(12, 55),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 13,
		NoStroke = true,
		Parent = cashPanel,
	})

	-- статус слева: живые, присед, правила пациентов
	local column = UIKit.new("Frame", {
		Name = "Status",
		Size = UDim2.fromOffset(380, 240),
		Position = UDim2.new(0, 12, 0, 8),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(column, "hud")
	UIKit.list(column, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	aliveLabel = UIKit.label({
		Name = "Alive",
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 16,
		LayoutOrder = 1,
		Parent = column,
	})
	crouchPill = UIKit.new("Frame", {
		Name = "Crouch",
		Size = UDim2.fromOffset(130, 30),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.25,
		LayoutOrder = 2,
		Visible = false,
		Parent = column,
	}) :: Frame
	UIKit.corner(crouchPill, 15)
	UIKit.new("UIStroke", { Thickness = 1, Color = Theme.Amber, Transparency = 0.4, Parent = crouchPill })
	crouchLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 16,
		NoStroke = true,
		Parent = crouchPill,
	})
	for i = 1, 3 do
		local rule = UIKit.label({
			Name = "Rule" .. i,
			Text = "",
			Size = UDim2.new(1, 0, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			FontFace = Theme.FontBody,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 14,
			LayoutOrder = 2 + i,
			Visible = false,
			Parent = column,
		})
		table.insert(ruleLabels, rule)
	end
end

local function buildDock()
	local dock = UIKit.new("Frame", {
		Name = "Dock",
		Size = UDim2.fromOffset(620, 300),
		Position = UDim2.new(0.5, 0, 1, -DOCK_MARGIN),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(dock, "hud")

	hotbar = UIKit.new("Frame", {
		Name = "Hotbar",
		Size = UDim2.fromOffset(400, SLOT_MOUSE),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = dock,
	}) :: Frame
	for i = 1, Config.InventorySlots do
		local slot, name, count, stroke = makeSlot(hotbar, tostring(i), "Slot" .. i)
		slots[i] = slot
		slotNames[i] = name
		slotCounts[i] = count
		slotStrokes[i] = stroke
		slot.Activated:Connect(function()
			UIKit.playClick()
			ClientState.selectSlot(i)
		end)
	end
	local fslot, fname, _, fstroke = makeSlot(hotbar, "F", "Flashlight")
	flashSlot, flashName, flashStroke = fslot, fname, fstroke
	local _, bfill = UIKit.bar({
		Name = "Battery",
		Size = UDim2.new(1, -10, 0, 4),
		Position = UDim2.new(0.5, 0, 1, -5),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = flashSlot,
	}, Theme.Amber)
	batteryFill = bfill
	flashSlot.Activated:Connect(function()
		if ClientState.Status == "Alive" then
			UIKit.playClick()
			ClientState.setFlashlight(not ClientState.FlashlightOn)
		end
	end)

	-- выносливость: появляется только когда тратится
	staminaGroup = UIKit.new("CanvasGroup", {
		Name = "Stamina",
		Size = UDim2.fromOffset(260, 10),
		Position = UDim2.new(0.5, 0, 1, -(SLOT_MOUSE + 12)),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = dock,
	}) :: CanvasGroup
	local _, sfill = UIKit.bar({
		Name = "StaminaBar",
		Size = UDim2.fromScale(1, 1),
		Parent = staminaGroup,
	}, Theme.Amber)
	staminaFill = sfill

	-- пропустить оповещение (голосование)
	skipButton = UIKit.button({
		Name = "SkipAlert",
		Text = "",
		Size = UDim2.fromOffset(340, BTN_MOUSE),
		Position = UDim2.new(0.5, 0, 1, -(SLOT_MOUSE + 30)),
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 20,
		Parent = dock,
	}, function()
		if skipVoted then
			return
		end
		skipVoted = true
		Remotes.VoteSkipAlert:FireServer()
		UIKit.setButtonEnabled(skipButton, false)
	end)
	UIKit.styleDark(skipButton, Theme.Amber)
	skipButton.Visible = false
end

local function buildHiding()
	hidePanel = UIKit.new("Frame", {
		Name = "Hiding",
		Size = UDim2.fromOffset(440, 120),
		Position = UDim2.new(0.5, 0, 0.66, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}) :: Frame
	UIKit.autoScale(hidePanel, "hud")
	breathTitle = UIKit.label({
		Name = "Title",
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.Amber,
		MaxTextSize = 18,
		Parent = hidePanel,
	})
	local holder, bfill = UIKit.bar({
		Name = "Breath",
		Size = UDim2.fromOffset(320, 14),
		Position = UDim2.new(0.5, 0, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = hidePanel,
	}, Theme.Amber)
	breathFill = bfill
	breathStroke = holder:FindFirstChildOfClass("UIStroke") :: UIStroke
	holdHint = UIKit.label({
		Name = "Hold",
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 54),
		FontFace = Theme.FontBold,
		MaxTextSize = 16,
		Parent = hidePanel,
	})
	leaveHint = UIKit.label({
		Name = "Leave",
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 82),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		Parent = hidePanel,
	})
end

local function buildDowned()
	fxGui = UIKit.new("ScreenGui", {
		Name = "HUDDowned",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	vignette = makeVignette(fxGui, Theme.Red)
	local panel = UIKit.new("Frame", {
		Name = "Downed",
		Size = UDim2.fromOffset(560, 130),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = fxGui,
	}) :: Frame
	UIKit.autoScale(panel, "hud")
	downedLabel = UIKit.label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = Theme.Red,
		MaxTextSize = 26,
		Parent = panel,
	})
	downedTimer = UIKit.label({
		Name = "Timer",
		Text = "",
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, 46),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Amber,
		MaxTextSize = 56,
		Parent = panel,
	})
end

local function spectateCall(fnName: string)
	local spectate = UIKit.controller("Spectate")
	if spectate and type(spectate[fnName]) == "function" then
		pcall(spectate[fnName])
	end
end

local function buildTaken()
	takenGui = UIKit.new("ScreenGui", {
		Name = "HUDTaken",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 25,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	UIKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = takenGui,
	})
	makeVignette(takenGui, Color3.new(0, 0, 0))
	local panel = UIKit.new("Frame", {
		Name = "Taken",
		Size = UDim2.fromOffset(720, 160),
		Position = UDim2.new(0.5, 0, 0.14, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = takenGui,
	}) :: Frame
	UIKit.autoScale(panel, "hud")
	takenTitle = UIKit.label({
		Name = "Title",
		Text = "",
		Size = UDim2.new(1, 0, 0, 84),
		FontFace = Theme.FontMono,
		TextColor3 = Theme.Red,
		MaxTextSize = 64,
		Parent = panel,
	})
	takenHint = UIKit.label({
		Name = "Hint",
		Text = "",
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 92),
		FontFace = Theme.FontBody,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 18,
		Parent = panel,
	})

	local bar = UIKit.new("Frame", {
		Name = "Spectate",
		Size = UDim2.fromOffset(520, 100),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = takenGui,
	}) :: Frame
	UIKit.autoScale(bar, "hud")
	spectatePrev = UIKit.button({
		Name = "Prev",
		Text = "◀",
		Size = UDim2.fromOffset(BTN_MOUSE + 16, BTN_MOUSE),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextSize = 24,
		Parent = bar,
	}, function()
		spectateCall("prev")
	end)
	UIKit.styleDark(spectatePrev, Theme.Amber)
	spectateNext = UIKit.button({
		Name = "Next",
		Text = "▶",
		Size = UDim2.fromOffset(BTN_MOUSE + 16, BTN_MOUSE),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		TextSize = 24,
		Parent = bar,
	}, function()
		spectateCall("next")
	end)
	UIKit.styleDark(spectateNext, Theme.Amber)
	spectateLabel = UIKit.label({
		Name = "Target",
		Text = "",
		Size = UDim2.new(1, -240, 0, 40),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		FontFace = Theme.FontBold,
		MaxTextSize = 18,
		Parent = bar,
	})
end

----------------------------------------------------------------------
-- Обновление
----------------------------------------------------------------------
local function relayout()
	local slotSize = UIKit.touchPx(SLOT_MOUSE, SLOT_TOUCH)
	local width = Config.InventorySlots * (slotSize + SLOT_GAP) + 12 + slotSize
	hotbar.Size = UDim2.fromOffset(width, slotSize)
	for i, slot in slots do
		slot.Size = UDim2.fromOffset(slotSize, slotSize)
		slot.Position = UDim2.fromOffset((i - 1) * (slotSize + SLOT_GAP), 0)
	end
	flashSlot.Size = UDim2.fromOffset(slotSize, slotSize)
	flashSlot.Position = UDim2.fromOffset(width - slotSize, 0)
	-- подсказки клавиш не нужны на сенсорном экране
	local touch = UIKit.isTouch()
	for _, slot in slots do
		local key = slot:FindFirstChild("Key")
		if key and key:IsA("TextLabel") then
			key.Visible = not touch
		end
	end
	local flashKey = flashSlot:FindFirstChild("Key")
	if flashKey and flashKey:IsA("TextLabel") then
		flashKey.Visible = not touch
	end
	staminaGroup.Position = UDim2.new(0.5, 0, 1, -(slotSize + 12))
	local btn = UIKit.touchPx(BTN_MOUSE, BTN_TOUCH)
	skipButton.Size = UDim2.fromOffset(340, btn)
	skipButton.Position = UDim2.new(0.5, 0, 1, -(slotSize + 30))
	spectatePrev.Size = UDim2.fromOffset(btn + 16, btn)
	spectateNext.Size = UDim2.fromOffset(btn + 16, btn)
	cashPanel.Position = UDim2.new(1, -12 - UIKit.hudPx(UIKit.touchPx(GEAR_SPACE_MOUSE, GEAR_SPACE_TOUCH)), 0, 8)
end

local function refreshTop(snap: ClientState.StateSnapshot)
	local phase = snap.Phase
	if phase == "Day" then
		UIKit.setText(nightLabel, Locale.t("Day", math.max(1, math.floor(snap.Night))))
	else
		UIKit.setText(nightLabel, Locale.t("Night", math.floor(snap.Night), math.floor(snap.Nights)))
	end
	UIKit.setText(phaseLabel, Locale.t("Phase" .. phase))
	phaseFill.BackgroundColor3 = if phase == "Night" or phase == "Alert" then Theme.Red else Theme.Amber
	UIKit.setText(cashLabel, Locale.t("Cash", math.floor(snap.Cash)))
	UIKit.setText(applesLabel, Locale.t("Apples", math.floor(snap.Apples)))
	UIKit.setText(treesLabel, Locale.t("TreesCount", math.floor(snap.Trees)))
	UIKit.setText(aliveLabel, Locale.t("Alive", math.floor(snap.Alive), math.floor(snap.Players)))
end

local function refreshRules(snap: ClientState.StateSnapshot)
	local showRules = snap.Phase == "Night"
	for i, label in ruleLabels do
		local id = snap.Inmates[i]
		if showRules and id then
			UIKit.setText(label, Locale.inmateName(id) .. " — " .. Locale.inmateRule(id))
			label.Visible = true
		else
			label.Visible = false
		end
	end
end

local function refreshSkip(snap: ClientState.StateSnapshot)
	local alert = snap.Phase == "Alert"
	skipButton.Visible = alert
	if alert then
		UIKit.setButtonText(skipButton, Locale.t("SkipVotes", math.floor(snap.SkipVotes), math.floor(snap.Players)))
		UIKit.setButtonEnabled(skipButton, not skipVoted)
	end
end

local function refreshSlots()
	for i = 1, Config.InventorySlots do
		local slot = ClientState.Inventory[i]
		local def = if slot then Config.getItem(slot.ItemId) else nil
		if slot and def then
			UIKit.setText(slotNames[i], shortItemName(slot.ItemId))
			UIKit.setText(slotCounts[i], countText(slot, def))
			slotNames[i].TextColor3 = Theme.Text
		else
			UIKit.setText(slotNames[i], "")
			UIKit.setText(slotCounts[i], "")
		end
		local selected = i == ClientState.SelectedSlot
		slotStrokes[i].Color = if selected then Theme.Amber else Theme.GrayDark
		slotStrokes[i].Thickness = if selected then 2 else 1
		slotStrokes[i].Transparency = if selected then 0 else 0.3
		slots[i].BackgroundTransparency = if selected then 0.1 else 0.35
	end
end

local function refreshFlashlight()
	local on = ClientState.FlashlightOn
	UIKit.setText(flashName, Locale.t("Flashlight"))
	flashName.TextColor3 = if on then Theme.Amber else Theme.Text
	flashStroke.Color = if on then Theme.Amber else Theme.GrayDark
	flashStroke.Transparency = if on then 0 else 0.3
	flashSlot.BackgroundTransparency = if on then 0.1 else 0.35
end

local function refreshBattery()
	local max = math.max(1, Config.Flashlight.Battery)
	UIKit.setBar(batteryFill, ClientState.Battery / max)
	batteryFill.BackgroundColor3 = if ClientState.Battery <= Config.Flashlight.LowBattery then Theme.Red else Theme.Amber
end

local function refreshStamina()
	local movement = UIKit.controller("Movement")
	local max = Config.Movement.StaminaMax
	local value = if movement and type(movement.Stamina) == "number" then movement.Stamina else max
	UIKit.setBar(staminaFill, value / max)
	staminaFill.BackgroundColor3 = if value < max * 0.15 then Theme.Red else Theme.Amber
	local show = value < max - 0.5
	if show ~= staminaShown then
		staminaShown = show
		UIKit.tween(staminaGroup, 0.25, { GroupTransparency = if show then 0 else 1 })
	end
end

local function refreshBreath(value: number)
	local frac = value / math.max(1, Config.Hiding.BreathMax)
	UIKit.setBar(breathFill, frac)
	local low = frac < 0.3
	breathFill.BackgroundColor3 = if low then Theme.Red else Theme.Amber
	if low ~= breathLow then
		breathLow = low
		if not low then
			breathStroke.Color = Theme.GrayDark
			breathStroke.Thickness = 1
			breathStroke.Transparency = 0.35
		end
	end
end

local function refreshHidingText()
	local touch = UIKit.isTouch()
	UIKit.setText(breathTitle, Locale.t("BreathLabel"))
	UIKit.setText(holdHint, Locale.t(if touch then "HoldBreathHintTouch" else "HoldBreathHint"))
	UIKit.setText(leaveHint, Locale.t(if touch then "LeaveHideHintTouch" else "LeaveHideHint"))
end

local function refreshSpectate()
	UIKit.setText(spectateLabel, Locale.t("Spectating", if spectateName ~= "" then spectateName else "—"))
end

local function refreshTaken()
	local diff = Config.getDifficulty(ClientState.Snapshot.Difficulty)
	UIKit.setText(takenTitle, Locale.t("Taken"))
	UIKit.setText(takenHint, Locale.t(if diff.ReturnTakenAtDawn then "TakenHint" else "TakenHintPermanent"))
	refreshSpectate()
end

local function bindSpectate()
	if spectateBound then
		return
	end
	local spectate = UIKit.controller("Spectate")
	if not spectate then
		return
	end
	spectateBound = true
	local signal = spectate.TargetChanged
	if type(signal) == "table" and type(signal.Connect) == "function" then
		signal:Connect(function(name: any)
			spectateName = if name ~= nil then tostring(name) else ""
			refreshSpectate()
		end)
	end
	local hasControls = type(spectate.next) == "function"
	spectatePrev.Visible = hasControls
	spectateNext.Visible = hasControls
end

local function refreshVisibility()
	local status = ClientState.Status
	local inMatch = ClientState.inMatch()
	local playing = status == "Alive" or status == "Downed" or status == "Hiding"
	if inMatch and playing then
		participated = true
	end
	gui.Enabled = inMatch and playing
	fxGui.Enabled = inMatch and status == "Downed"
	local taken = inMatch and (status == "Taken" or (status == "Spectating" and participated))
	if taken then
		bindSpectate()
		refreshTaken()
	end
	takenGui.Enabled = taken
	hidePanel.Visible = status == "Hiding"
	crouchPill.Visible = ClientState.Crouching and status == "Alive"
end

local function relabel()
	UIKit.setText(crouchLabel, "▼ " .. Locale.t("Crouch"))
	UIKit.setText(downedLabel, Locale.t("Downed"))
	refreshHidingText()
	refreshTop(ClientState.Snapshot)
	refreshRules(ClientState.Snapshot)
	refreshSkip(ClientState.Snapshot)
	refreshSlots()
	refreshFlashlight()
	refreshTaken()
end

----------------------------------------------------------------------
-- Инициализация
----------------------------------------------------------------------
function HUD.init()
	gui = UIKit.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	buildTop()
	buildDock()
	buildHiding()
	buildDowned()
	buildTaken()
	relayout()
	UIKit.onLayoutChanged(function()
		relayout()
		refreshHidingText()
	end)
	relabel()
	refreshBattery()
	refreshVisibility()

	ClientState.StateChanged:Connect(function(snap: ClientState.StateSnapshot)
		if snap.Phase == "Lobby" or snap.Phase == "Countdown" or snap.Phase == "Results" then
			participated = false
		end
		if snap.Phase ~= "Alert" then
			skipVoted = false
		end
		refreshTop(snap)
		refreshRules(snap)
		refreshSkip(snap)
		refreshVisibility()
	end)
	ClientState.StatusChanged:Connect(function(status: string, _hideId: string?)
		if status == "Downed" then
			downedUntil = os.clock() + Config.Downed.Duration
		end
		if status == "Hiding" then
			refreshBreath(ClientState.Breath)
		end
		refreshVisibility()
	end)
	ClientState.InventoryChanged:Connect(function()
		refreshSlots()
		refreshBattery()
	end)
	ClientState.SelectedChanged:Connect(refreshSlots)
	ClientState.FlashlightChanged:Connect(refreshFlashlight)
	ClientState.CrouchChanged:Connect(refreshVisibility)
	ClientState.BreathChanged:Connect(refreshBreath)
	ClientState.SettingsChanged:Connect(relabel)

	-- Выносливость: сигнал контроллера (если он есть) плюс опрос раз в 0.1 с ниже.
	local movement = UIKit.controller("Movement")
	local staminaSignal: any = if movement then movement.StaminaChanged else nil
	if type(staminaSignal) == "table" and type(staminaSignal.Connect) == "function" then
		(staminaSignal :: any):Connect(refreshStamina)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		if fxGui.Enabled then
			local a = 0.45 + 0.15 * math.sin(now * 3)
			for _, f in vignette do
				f.BackgroundTransparency = a
			end
		end
		if not gui.Enabled then
			return
		end
		local snap = ClientState.Snapshot
		UIKit.setBar(phaseFill, 1 - ClientState.phaseRemaining() / math.max(1, snap.PhaseLength))
		if hidePanel.Visible and breathLow then
			breathStroke.Color = Theme.Red
			breathStroke.Thickness = 2
			breathStroke.Transparency = 0.2 + 0.5 * (0.5 + 0.5 * math.sin(now * 8))
		end
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		UIKit.setText(clockLabel, ClientState.clockText())
		refreshBattery()
		refreshStamina()
		if fxGui.Enabled then
			UIKit.setText(downedTimer, Locale.t("DownedTimer", math.max(0, math.ceil(downedUntil - now))))
		end
	end)
end

-- Высота хотбара в пикселях макета (для модулей, которые встают над ним: подсказки).
function HUD.slotSize(): number
	return UIKit.touchPx(SLOT_MOUSE, SLOT_TOUCH)
end

return HUD
