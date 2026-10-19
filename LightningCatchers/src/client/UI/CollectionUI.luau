--!strict
-- Коллекция: фульгуриты (3D-превью строятся лениво и кэшируются, надеть/снять/разбить)
-- и Молниедекс (острова × цвета + Радужная и Чёрная, бонус за полную строку).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Pets = require(Shared:WaitForChild("Pets"))
local Fulgurite = require(Shared:WaitForChild("Fulgurite"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local CollectionUI = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local CELL = Vector2.new(124, 152)
local GRID_W = 556
local SPIN_SPEED = 0.6
local MODEL_RELEASE = 8 -- превью карточки, которую столько секунд не видно (прокрутили), удаляется — построится снова
local SPECIAL = { "rainbow", "black" } :: { Config.ColorId }

local win: UIKit.Window
local shardsLabel: TextLabel
local busy = false

----------------------------------------------------------------------
-- Спецификации фульгуритов (чистая функция от seed — кэш навсегда)
----------------------------------------------------------------------
local specCache: { [string]: Fulgurite.Spec } = {}

local function keyOf(f: PlayerData.FulgRecord): string
	return f.Seed .. ":" .. f.Color .. ":" .. (f.Mut or "")
end

local function specOf(f: PlayerData.FulgRecord): Fulgurite.Spec
	local key = keyOf(f)
	local spec = specCache[key]
	if not spec then
		spec = Fulgurite.generate(f.Seed, f.Color, f.Mut :: any)
		specCache[key] = spec
	end
	return spec
end

local function mutOf(f: PlayerData.FulgRecord): Fulgurite.MutId?
	local m = f.Mut
	if m and Fulgurite.Mutations[m :: any] then
		return m :: any
	end
	return nil
end

local function serialText(f: PlayerData.FulgRecord): string
	return string.format("№%06d", f.Serial)
end

local function bonusText(spec: Fulgurite.Spec): string
	return string.format("+%d%% ⚡", math.floor(spec.Bonus * 100 + 0.5))
end

local function buildFulgModel(f: PlayerData.FulgRecord): Model?
	local ok, model = pcall(function()
		return Models.fulgurite(specOf(f), Fulgurite.glassColor(f.Color, mutOf(f)))
	end)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	return nil
end

----------------------------------------------------------------------
-- Вкладка "Фульгуриты"
----------------------------------------------------------------------
type FulgCard = {
	id: number,
	record: PlayerData.FulgRecord,
	button: TextButton,
	vp: ViewportFrame,
	camera: Camera,
	model: Model?,
	center: Vector3,
	dist: number,
	check: Frame,
	stroke: UIStroke,
	phase: number,
	seenAt: number, -- os.clock, когда карточка последний раз была видна
}

local grid: ScrollingFrame
local emptyHint: TextLabel
local equippedLabel: TextLabel
local countLabel: TextLabel
local totalLabel: TextLabel
local cards: { [number]: FulgCard } = {}
local selectedId: number? = nil

local detailVp: ViewportFrame
local detailCam: Camera
local detailModel: Model? = nil
local detailKey = ""
local detailCenter = Vector3.zero
local detailDist = 8
local detailTitle: TextLabel
local detailSerial: TextLabel
local detailRarity: TextLabel
local detailBonus: TextLabel
local detailZone: TextLabel
local detailHint: TextLabel
local equipButton: TextButton
local breakButton: TextButton

local function isEquipped(d: PlayerData.Data, id: number): boolean
	return table.find(d.EquippedFulgs, id) ~= nil
end

local function rankOf(spec: Fulgurite.Spec): number
	return Pets.Rarities[spec.Rarity].Rank
end

local function selectFulg(id: number?)
	selectedId = id
	for cid, c in cards do
		if cid == id then
			c.stroke.Color = WHITE
			c.stroke.Thickness = 4.5
		else
			c.stroke.Color = Pets.Rarities[specOf(c.record).Rarity].Color
			c.stroke.Thickness = 3
		end
	end
	local d = ClientState.get()
	local f = if d and id then PlayerData.findFulg(d, id) else nil
	local show = f ~= nil
	detailHint.Visible = not show
	for _, l in { detailTitle, detailSerial, detailRarity, detailBonus, detailZone } do
		l.Visible = show
	end
	equipButton.Visible = show
	breakButton.Visible = show
	if not f or not d or not id then
		if detailModel then
			detailModel:Destroy()
			detailModel = nil
			detailKey = ""
		end
		return
	end
	local spec = specOf(f)
	local rar = Pets.Rarities[spec.Rarity]
	detailTitle.Text = Fulgurite.title(spec, mutOf(f))
	detailTitle.TextColor3 = rar.Color:Lerp(WHITE, 0.3)
	detailSerial.Text = serialText(f)
	detailRarity.Text = rar.Name
	detailRarity.TextColor3 = rar.Color
	detailBonus.Text = bonusText(spec)
	local zdef = Config.Zones[f.Zone]
	detailZone.Text = if zdef then "Найден: " .. zdef.Name else ""
	if isEquipped(d, id) then
		UIKit.setButtonText(equipButton, "Снять")
		UIKit.setButtonColor(equipButton, Theme.Gray)
	else
		UIKit.setButtonText(equipButton, "Надеть")
		UIKit.setButtonColor(equipButton, if #d.EquippedFulgs >= Fulgurite.MaxEquipped then Theme.GrayDark else Theme.Green)
	end
	local key = keyOf(f)
	if key ~= detailKey then
		if detailModel then
			detailModel:Destroy()
			detailModel = nil
		end
		detailKey = key
		local model = buildFulgModel(f)
		if model then
			model.Parent = detailVp
			detailModel = model
			detailCenter, detailDist = UIKit.frameModel(model, detailCam.FieldOfView, 0.7)
		end
	end
end

local function makeCard(f: PlayerData.FulgRecord): FulgCard
	local spec = specOf(f)
	local rar = Pets.Rarities[spec.Rarity]
	local button = UIKit.new("TextButton", {
		Name = "Fulg" .. f.Id,
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		Parent = grid,
	}) :: TextButton
	UIKit.corner(button, Theme.CornerSmall)
	local stroke = UIKit.stroke(button, 3, rar.Color)
	UIKit.gradient(button, rar.Color:Lerp(Theme.Card, 0.6), Theme.PanelDark)
	local vp, camera = UIKit.viewport({
		Name = "Preview",
		Size = UDim2.new(1, -8, 0, 86),
		Position = UDim2.fromOffset(4, 4),
		Parent = button,
	})
	-- на карточке коротко: форма и мутация (полное название — в панели справа)
	local mut = mutOf(f)
	UIKit.label({
		Name = "Shape",
		Text = "«" .. spec.ShapeName .. "»",
		Size = UDim2.new(1, -8, 0, 24),
		Position = UDim2.fromOffset(4, 90),
		TextColor3 = rar.Color:Lerp(WHITE, 0.35),
		MaxTextSize = 21,
		Parent = button,
	})
	UIKit.label({
		Name = "Kind",
		Text = if mut then Fulgurite.Mutations[mut].Name else rar.Name,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 113),
		TextColor3 = if mut then Fulgurite.Mutations[mut].Color:Lerp(WHITE, 0.2) else rar.Color,
		FontFace = Theme.FontBold,
		MaxTextSize = 15,
		Parent = button,
	})
	UIKit.label({
		Name = "Serial",
		Text = serialText(f),
		Size = UDim2.new(0.55, -4, 0, 18),
		Position = UDim2.fromOffset(4, 131),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 15,
		Parent = button,
	})
	UIKit.label({
		Name = "Bonus",
		Text = bonusText(spec),
		Size = UDim2.new(0.45, -4, 0, 18),
		Position = UDim2.new(0.55, 0, 0, 131),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Volt,
		MaxTextSize = 16,
		Parent = button,
	})
	local check = UIKit.new("Frame", {
		Name = "Equipped",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Theme.Green,
		Visible = false,
		ZIndex = 4,
		Parent = button,
	}) :: Frame
	UIKit.round(check)
	UIKit.stroke(check, 2, Theme.Stroke)
	UIKit.label({
		Text = "✔",
		Size = UDim2.fromScale(0.75, 0.75),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 22,
		ZIndex = 5,
		Parent = check,
	})
	local card: FulgCard = {
		id = f.Id,
		record = f,
		button = button,
		vp = vp,
		camera = camera,
		model = nil,
		center = Vector3.zero,
		dist = 8,
		check = check,
		stroke = stroke,
		phase = (f.Id * 2.3) % (math.pi * 2),
		seenAt = os.clock(),
	}
	button.Activated:Connect(function()
		UIKit.playClick()
		selectFulg(f.Id)
	end)
	return card
end

local function ensureModel(c: FulgCard)
	if c.model then
		return
	end
	local model = buildFulgModel(c.record)
	if not model then
		return
	end
	model.Parent = c.vp
	c.model = model
	c.center, c.dist = UIKit.frameModel(model, c.camera.FieldOfView, 0.72)
	UIKit.orbit(c.camera, c.center, c.dist, c.phase, 0.3)
end

local function refreshFulgs(d: PlayerData.Data)
	equippedLabel.Text = string.format("Надето: %d/%d", #d.EquippedFulgs, Fulgurite.MaxEquipped)
	countLabel.Text = string.format("Всего: %d/%d", #d.Fulgs, Fulgurite.MaxInventory)
	totalLabel.Text = "Бонус: +" .. math.floor(Economy.fulgBonus(d) * 100 + 0.5) .. "% ⚡"
	local list: { PlayerData.FulgRecord } = table.clone(d.Fulgs)
	table.sort(list, function(a: PlayerData.FulgRecord, b: PlayerData.FulgRecord): boolean
		local ea, eb = isEquipped(d, a.Id), isEquipped(d, b.Id)
		if ea ~= eb then
			return ea
		end
		local sa, sb = specOf(a), specOf(b)
		local ra, rb = rankOf(sa), rankOf(sb)
		if ra ~= rb then
			return ra > rb
		end
		if sa.Bonus ~= sb.Bonus then
			return sa.Bonus > sb.Bonus
		end
		return a.Serial < b.Serial
	end)
	local present: { [number]: boolean } = {}
	for i, f in list do
		present[f.Id] = true
		local c = cards[f.Id]
		if c and keyOf(c.record) ~= keyOf(f) then
			c.button:Destroy()
			cards[f.Id] = nil
			c = nil
		end
		if not c then
			c = makeCard(f)
			cards[f.Id] = c
		end
		local card = c :: FulgCard
		card.record = f
		card.button.LayoutOrder = i
		card.check.Visible = isEquipped(d, f.Id)
	end
	for id, c in cards do
		if not present[id] then
			c.button:Destroy()
			cards[id] = nil
		end
	end
	emptyHint.Visible = #d.Fulgs == 0
	if selectedId and not present[selectedId] then
		selectedId = nil
	end
	if not selectedId and list[1] then
		selectedId = list[1].Id
	end
	selectFulg(selectedId)
end

local function buildFulgs(page: Frame)
	local top = UIKit.new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = page,
	}) :: Frame
	equippedLabel = UIKit.label({
		Name = "Equipped",
		Text = "",
		Size = UDim2.fromOffset(220, 40),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Good,
		MaxTextSize = 28,
		Parent = top,
	})
	countLabel = UIKit.label({
		Name = "Count",
		Text = "",
		Size = UDim2.fromOffset(220, 40),
		Position = UDim2.new(0, 230, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 24,
		Parent = top,
	})
	totalLabel = UIKit.label({
		Name = "Total",
		Text = "",
		Size = UDim2.fromOffset(300, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Volt,
		MaxTextSize = 28,
		Parent = top,
	})

	grid = UIKit.scroll({
		Name = "Grid",
		Size = UDim2.new(0, GRID_W, 1, -58),
		Position = UDim2.fromOffset(0, 58),
		Parent = page,
	})
	UIKit.grid(grid, CELL, 10).HorizontalAlignment = Enum.HorizontalAlignment.Left
	UIKit.padding(grid, 4, 4)
	emptyHint = UIKit.label({
		Name = "Empty",
		Text = "Лови молнии на ИДЕАЛЬНО —\nиногда они оставляют стеклянный фульгурит!",
		Size = UDim2.new(0, GRID_W - 40, 0, 110),
		Position = UDim2.new(0, GRID_W / 2, 0.45, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 28,
		Visible = false,
		Parent = page,
	})

	local detail = UIKit.card({
		Name = "Detail",
		Size = UDim2.new(1, -(GRID_W + 12), 1, -58),
		Position = UDim2.fromOffset(GRID_W + 12, 58),
		Parent = page,
	})
	detailVp, detailCam = UIKit.viewport({
		Name = "Preview",
		Size = UDim2.new(1, -16, 0, 120),
		Position = UDim2.fromOffset(8, 6),
		Parent = detail,
	})
	detailTitle = UIKit.label({
		Name = "Title",
		Text = "",
		Size = UDim2.new(1, -16, 0, 42),
		Position = UDim2.fromOffset(8, 128),
		MaxTextSize = 23,
		Parent = detail,
	})
	detailSerial = UIKit.label({
		Name = "Serial",
		Text = "",
		Size = UDim2.new(0.5, -8, 0, 22),
		Position = UDim2.fromOffset(8, 172),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 20,
		Parent = detail,
	})
	detailRarity = UIKit.label({
		Name = "Rarity",
		Text = "",
		Size = UDim2.new(0.5, -8, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 172),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 20,
		Parent = detail,
	})
	detailBonus = UIKit.label({
		Name = "Bonus",
		Text = "",
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.fromOffset(8, 196),
		TextColor3 = Theme.Volt,
		MaxTextSize = 26,
		Parent = detail,
	})
	detailZone = UIKit.label({
		Name = "Zone",
		Text = "",
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 226),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 18,
		Parent = detail,
	})
	detailHint = UIKit.label({
		Name = "Hint",
		Text = "Нажми на фульгурит",
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 190),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 24,
		Parent = detail,
	})
	equipButton = UIKit.button({
		Name = "Equip",
		Text = "Надеть",
		Color = Theme.Green,
		Size = UDim2.new(0.5, -14, 0, 62),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		TextSize = 26,
		Parent = detail,
	}, function()
		local d = ClientState.get()
		local id = selectedId
		if busy or not d or not id then
			return
		end
		local equipped = isEquipped(d, id)
		if not equipped and #d.EquippedFulgs >= Fulgurite.MaxEquipped then
			Sounds.play("Error")
			ClientState.Toast:Fire("Надеть можно только " .. Fulgurite.MaxEquipped .. " — сними один", "bad")
			return
		end
		busy = true
		local ok = ClientState.request(if equipped then Net.Actions.UnequipFulg else Net.Actions.EquipFulg, id)
		busy = false
		if not ok then
			Sounds.play("Error")
		elseif not equipped then
			Sounds.play("Fulgurite")
		end
	end)
	breakButton = UIKit.button({
		Name = "Break",
		Text = "💎 Разбить",
		Color = Theme.Red,
		Size = UDim2.new(0.5, -14, 0, 62),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		TextSize = 24,
		Parent = detail,
	}, function()
		local d = ClientState.get()
		local id = selectedId
		if busy or not d or not id then
			return
		end
		local f = PlayerData.findFulg(d, id)
		if not f then
			return
		end
		-- что именно разбиваем и сколько получим (как посчитает сервер) — разбитый не вернуть
		local spec = specOf(f)
		local mut = mutOf(f)
		local lines = {
			string.format("Разбить фульгурит «%s» %s?", spec.ShapeName, serialText(f)),
			(if mut then Fulgurite.Mutations[mut].Name .. " · " else "") .. Pets.Rarities[spec.Rarity].Name .. " · " .. bonusText(spec),
		}
		if isEquipped(d, id) then
			table.insert(lines, "⚠ Он сейчас надет!")
		end
		table.insert(lines, string.format("Получишь 💎 %s, а он исчезнет навсегда.", Format.short(Fulgurite.shatterValue(spec.Rarity, f.Zone))))
		win.confirm(table.concat(lines, "\n"), "Разбить", function()
			busy = true
			local ok, result = ClientState.request(Net.Actions.DeleteFulg, id)
			busy = false
			if ok then
				Sounds.play("Shard")
				if typeof(result) == "number" and result > 0 then
					ClientState.Toast:Fire("+" .. Format.short(result) .. " 💎", "good")
				end
			else
				Sounds.play("Error")
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Вкладка "Молниедекс"
----------------------------------------------------------------------
type Cell = { frame: Frame, grad: UIGradient, icon: TextLabel, name: TextLabel, stroke: UIStroke }
type Row = { cells: { [string]: Cell }, progress: TextLabel, reward: TextLabel }
local rows: { Row } = {}
local specialCells: { [string]: Cell } = {}
local indexTotal: TextLabel

local function makeCell(parent: Instance, order: number, size: Vector2): Cell
	local frame = UIKit.new("Frame", {
		Name = "Cell" .. order,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	UIKit.corner(frame, 10)
	local stroke = UIKit.stroke(frame, 2.5, Theme.Stroke)
	local grad = UIKit.gradient(frame, Theme.PanelLight, Theme.PanelDark)
	local icon = UIKit.label({
		Name = "Icon",
		Text = "?",
		Size = UDim2.new(1, -6, 0.6, 0),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 34,
		Parent = frame,
	})
	local name = UIKit.label({
		Name = "Name",
		Text = "",
		Size = UDim2.new(1, -6, 0.3, 0),
		Position = UDim2.fromScale(0.5, 0.82),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 15,
		Parent = frame,
	})
	return { frame = frame, grad = grad, icon = icon, name = name, stroke = stroke }
end

local function setCell(cell: Cell, color: Config.ColorId, caught: boolean)
	local def = Config.Colors[color]
	if caught then
		local c = def.Color
		if color == "black" then
			cell.grad.Color = ColorSequence.new(Color3.fromRGB(90, 60, 130), Color3.fromRGB(20, 10, 30))
			cell.icon.TextColor3 = Theme.Gold
			cell.stroke.Color = Theme.Gold
		elseif color == "rainbow" then
			cell.grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 90)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(110, 230, 160)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 120, 255)),
			})
			cell.icon.TextColor3 = WHITE
			cell.stroke.Color = WHITE
		else
			cell.grad.Color = ColorSequence.new(c:Lerp(WHITE, 0.25), c:Lerp(BLACK, 0.35))
			cell.icon.TextColor3 = WHITE
			cell.stroke.Color = Theme.Stroke
		end
		cell.icon.Text = def.Icon
		cell.name.Text = def.Name
		cell.name.TextColor3 = WHITE
	else
		cell.grad.Color = ColorSequence.new(Theme.PanelLight, Theme.PanelDark)
		cell.icon.Text = "?"
		cell.icon.TextColor3 = Theme.GrayDark
		cell.name.Text = def.Name
		cell.name.TextColor3 = Theme.GrayDark
		cell.stroke.Color = Theme.Stroke
	end
end

local function buildIndex(page: Frame)
	indexTotal = UIKit.label({
		Name = "Total",
		Text = "",
		Size = UDim2.new(1, -8, 0, 34),
		Position = UDim2.fromOffset(4, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Volt,
		MaxTextSize = 28,
		Parent = page,
	})
	UIKit.label({
		Name = "Hint",
		Text = "Собери весь остров — Вольты навсегда +10%!",
		Size = UDim2.new(0.6, 0, 0, 30),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 20,
		Parent = page,
	})
	local scroller = UIKit.scroll({
		Name = "Rows",
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		Parent = page,
	})
	UIKit.list(scroller, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 2, 2)
	local cellSize = Vector2.new(92, 60)
	local function rowFrame(order: number, title: string, accent: Color3): Frame
		local row = UIKit.new("Frame", {
			Name = "Row" .. order,
			Size = UDim2.fromOffset(826, 66),
			BackgroundColor3 = WHITE,
			LayoutOrder = order,
			Parent = scroller,
		}) :: Frame
		UIKit.corner(row, Theme.CornerSmall)
		UIKit.stroke(row, 2, Theme.Stroke)
		UIKit.gradient(row, Theme.Card:Lerp(accent, 0.15), Theme.PanelDark)
		UIKit.label({
			Name = "Title",
			Text = title,
			Size = UDim2.fromOffset(170, 50),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = accent:Lerp(WHITE, 0.4),
			MaxTextSize = 22,
			Parent = row,
		})
		local cellsFrame = UIKit.new("Frame", {
			Name = "Cells",
			Size = UDim2.fromOffset(5 * cellSize.X + 4 * 6, cellSize.Y),
			Position = UDim2.new(0, 186, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Parent = row,
		}) :: Frame
		UIKit.list(cellsFrame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
		return row
	end
	for z, zdef in Config.Zones do
		local row = rowFrame(z, zdef.Name, zdef.Accent)
		local cellsFrame = row:FindFirstChild("Cells") :: Frame
		local cellMap: { [string]: Cell } = {}
		for i, c in Config.NormalColors do
			cellMap[c] = makeCell(cellsFrame, i, cellSize)
		end
		local progress = UIKit.label({
			Name = "Progress",
			Text = "0/5",
			Size = UDim2.fromOffset(60, 30),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxTextSize = 24,
			Parent = row,
		})
		local reward = UIKit.label({
			Name = "Reward",
			Text = "+10% ⚡",
			Size = UDim2.fromOffset(110, 24),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -6),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.TextDim,
			MaxTextSize = 20,
			Parent = row,
		})
		table.insert(rows, { cells = cellMap, progress = progress, reward = reward })
	end
	local special = rowFrame(#Config.Zones + 1, "✨ Особые", Theme.Rainbow)
	local cellsFrame = special:FindFirstChild("Cells") :: Frame
	for i, c in SPECIAL do
		specialCells[c] = makeCell(cellsFrame, i, cellSize)
	end
	UIKit.label({
		Name = "Note",
		Text = "Радужная — на событии, Чёрная — на Оке Бури",
		Size = UDim2.fromOffset(300, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 18,
		Parent = special,
	})
end

local function hasSpecial(d: PlayerData.Data, color: string): boolean
	if d.Index[color] then
		return true
	end
	local suffix = ":" .. color
	for k in d.Index do
		if string.sub(k, -#suffix) == suffix then
			return true
		end
	end
	return false
end

local function refreshIndex(d: PlayerData.Data)
	local total = 0
	local max = #Config.Zones * #Config.NormalColors + #SPECIAL
	for z, row in rows do
		local n = 0
		for _, c in Config.NormalColors do
			local caught = d.Index[z .. ":" .. c] == true
			if caught then
				n += 1
			end
			setCell(row.cells[c], c, caught)
		end
		total += n
		row.progress.Text = string.format("%d/%d", n, #Config.NormalColors)
		local full = n >= #Config.NormalColors
		row.progress.TextColor3 = if full then Theme.Green else WHITE
		row.reward.Text = if full then "✔ +10% ⚡" else "+10% ⚡"
		row.reward.TextColor3 = if full then Theme.Green else Theme.TextDim
	end
	for _, c in SPECIAL do
		local caught = hasSpecial(d, c)
		if caught then
			total += 1
		end
		setCell(specialCells[c], c, caught)
	end
	indexTotal.Text = string.format("📖 Поймано: %d/%d", total, max)
end

----------------------------------------------------------------------
-- Превью: крутятся только выбранная карточка и большое превью (каждый сдвиг камеры перерисовывает
-- ViewportFrame), остальные стоят под своим углом; модели давно не видных карточек удаляются
----------------------------------------------------------------------
local spinAccum = 0
local spinClock = 0
local spinConn: RBXScriptConnection? = nil

local function isVisibleIn(child: GuiObject, frame: GuiObject): boolean
	local cy, ch = child.AbsolutePosition.Y, child.AbsoluteSize.Y
	local fy, fh = frame.AbsolutePosition.Y, frame.AbsoluteSize.Y
	return cy + ch > fy and cy < fy + fh
end

local function spinStep(dt: number)
	spinAccum += dt
	if spinAccum < 1 / 30 then
		return
	end
	local step = spinAccum
	spinAccum = 0
	spinClock += step
	if win.tab() ~= "fulgs" then
		return
	end
	-- фульгурит — до 90 деталей: строим не больше одного превью за шаг
	local built = false
	local clock = os.clock()
	for cid, c in cards do
		if isVisibleIn(c.button, grid) then
			c.seenAt = clock
			if not c.model and not built then
				built = true
				ensureModel(c)
			end
			if c.model and cid == selectedId then
				c.phase += step * SPIN_SPEED
				UIKit.orbit(c.camera, c.center, c.dist, c.phase, 0.3)
			end
		elseif c.model and clock - c.seenAt > MODEL_RELEASE then
			local model = c.model
			c.model = nil
			if model then
				model:Destroy()
			end
		end
	end
	if detailModel then
		UIKit.orbit(detailCam, detailCenter, detailDist, spinClock * 0.8, 0.25)
	end
end

----------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------
local function refresh()
	local d = ClientState.get()
	if not d or not win.isOpen() then
		return
	end
	shardsLabel.Text = Format.short(d.Shards)
	local tab = win.tab()
	if tab == "fulgs" then
		refreshFulgs(d)
	elseif tab == "index" then
		refreshIndex(d)
	end
	win.setTabBadge("fulgs", #d.EquippedFulgs < math.min(Fulgurite.MaxEquipped, #d.Fulgs))
end

function CollectionUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Collection",
		Title = "Коллекция",
		Icon = "💎",
		Width = 880,
		Height = 560,
		Accent = Theme.ElectricDark,
		Tabs = {
			{ Id = "fulgs", Text = "🔮 Фульгуриты" },
			{ Id = "index", Text = "📖 Молниедекс" },
		},
		OnOpen = function()
			refresh()
			if not spinConn then
				spinConn = RunService.Heartbeat:Connect(spinStep)
			end
			ClientState.WindowOpened:Fire("Collection")
		end,
		OnClose = function()
			local c = spinConn
			spinConn = nil
			if c then
				c:Disconnect()
			end
			ClientState.WindowClosed:Fire("Collection")
		end,
		OnTab = function()
			refresh()
		end,
	})
	shardsLabel = UIKit.headerCounter(win, "💎", Theme.Shard)
	buildFulgs(win.Pages.fulgs)
	buildIndex(win.Pages.index)

	ClientState.Changed:Connect(refresh)
	ClientState.OpenWindow:Connect(function(name: string)
		local base, tab = UIKit.parseWindowName(name)
		if base == "Collection" then
			win.open(tab)
		elseif base == "Gallery" or base == "Fulgurites" then
			win.open("fulgs")
		elseif base == "Index" then
			win.open("index")
		end
	end)
end

function CollectionUI.open(tab: string?)
	if win then
		win.open(tab)
	end
end

return CollectionUI
