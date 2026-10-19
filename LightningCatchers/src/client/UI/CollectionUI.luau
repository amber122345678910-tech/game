--!strict
-- Коллекция: фульгуриты (3D-превью строятся лениво и кэшируются, надеть/снять/разбить)
-- и Молниедекс (острова × цвета + Радужная и Чёрная, бонус за полную строку).
-- Знаки цветов молний (● ◆ ▲ ★ ✦ ✺ ☯) нарисованы примитивами: в шрифтах игры их нет (docs/STYLE.md §8.5).

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
local Loc = require(Shared:WaitForChild("Loc"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local CollectionUI = {}

local WHITE = Color3.new(1, 1, 1)

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
	return Loc.t("№%06d", f.Serial)
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
local detailRarityTag: Frame
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
		UIKit.selectCard(c.button, cid == id)
	end
	local d = ClientState.get()
	local f = if d and id then PlayerData.findFulg(d, id) else nil
	local show = f ~= nil
	detailHint.Visible = not show
	for _, l in { detailTitle, detailSerial, detailRarityTag, detailBonus, detailZone } :: { GuiObject } do
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
	detailTitle.TextColor3 = rar.Color:Lerp(WHITE, 0.35)
	detailSerial.Text = serialText(f)
	detailRarity.Text = UIKit.upper(Loc.t(rar.Name))
	detailRarityTag.BackgroundColor3 = rar.Color
	detailBonus.Text = bonusText(spec)
	local zdef = Config.Zones[f.Zone]
	detailZone.Text = if zdef then Loc.t("Найден: %s", zdef.Name) else ""
	if isEquipped(d, id) then
		UIKit.setButtonText(equipButton, Loc.t("Снять"))
		UIKit.setButtonVariant(equipButton, "Slate")
	else
		UIKit.setButtonText(equipButton, Loc.t("Надеть"))
		UIKit.setButtonVariant(equipButton, if #d.EquippedFulgs >= Fulgurite.MaxEquipped then "Disabled" else "Go")
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
	UIKit.stroke(button, 1.5, Theme.LineLight, 0.7)
	UIKit.new("UIGradient", { Name = "CardGrad", Rotation = 90, Parent = button })
	UIKit.rarityCard(button, rar.Color)
	local _well, vp, camera = UIKit.previewWell({
		Size = UDim2.new(1, -12, 0, 80),
		Position = UDim2.fromOffset(6, 10),
		Parent = button,
	})
	-- на карточке коротко: форма и мутация (полное название — в панели справа)
	local mut = mutOf(f)
	UIKit.label({
		Name = "Shape",
		Text = Loc.t("«%s»", spec.ShapeName),
		FontFace = Theme.FontDisplayFlat,
		Size = UDim2.new(1, -10, 0, 22),
		Position = UDim2.fromOffset(5, 92),
		TextColor3 = rar.Color:Lerp(WHITE, 0.4),
		MaxTextSize = 18,
		Parent = button,
	})
	UIKit.label({
		Name = "Kind",
		Text = UIKit.upper(Loc.t(if mut then Fulgurite.Mutations[mut].Name else rar.Name)),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -10, 0, 16),
		Position = UDim2.fromOffset(5, 114),
		TextColor3 = if mut then Fulgurite.Mutations[mut].Color:Lerp(WHITE, 0.25) else rar.Color,
		MaxTextSize = 13,
		Parent = button,
	})
	UIKit.label({
		Name = "Serial",
		Text = serialText(f),
		Size = UDim2.new(0.55, -4, 0, 18),
		Position = UDim2.fromOffset(5, 131),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 14,
		Parent = button,
	})
	UIKit.label({
		Name = "Bonus",
		Text = bonusText(spec),
		FontFace = Theme.FontNumber,
		Size = UDim2.new(0.45, -6, 0, 18),
		Position = UDim2.new(0.55, 0, 0, 131),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Volt,
		MaxTextSize = 16,
		Parent = button,
	})
	local check = UIKit.checkBadge(button, 28, { Name = "Equipped", Position = UDim2.fromOffset(2, 4) })
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
	equippedLabel.Text = Loc.t("Надето: %d/%d", #d.EquippedFulgs, Fulgurite.MaxEquipped)
	countLabel.Text = Loc.t("Всего: %d/%d", #d.Fulgs, Fulgurite.MaxInventory)
	totalLabel.Text = Loc.t("Бонус: +%d%% ⚡", math.floor(Economy.fulgBonus(d) * 100 + 0.5))
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
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(220, 34),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SparkHi,
		MaxTextSize = 26,
		Parent = top,
	})
	countLabel = UIKit.label({
		Name = "Count",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.fromOffset(220, 34),
		Position = UDim2.new(0, 230, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 22,
		Parent = top,
	})
	totalLabel = UIKit.label({
		Name = "Total",
		Text = "",
		FontFace = Theme.FontNumber,
		Size = UDim2.fromOffset(300, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 30,
		NoStroke = false,
		Parent = top,
	})
	UIKit.gradientText(totalLabel, Theme.VoltHi, Theme.Volt)

	grid = UIKit.scroll({
		Name = "Grid",
		Size = UDim2.new(0, GRID_W, 1, -58),
		Position = UDim2.fromOffset(0, 58),
		Parent = page,
	})
	UIKit.grid(grid, CELL, 10).HorizontalAlignment = Enum.HorizontalAlignment.Left
	UIKit.padding(grid, 6, 6)
	emptyHint = UIKit.label({
		Name = "Empty",
		Text = Loc.t("Лови молнии на ИДЕАЛЬНО —\nиногда они оставляют стеклянный фульгурит!"),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(0, GRID_W - 40, 0, 110),
		Position = UDim2.new(0, GRID_W / 2, 0.45, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 26,
		Visible = false,
		Parent = page,
	})

	local detail = UIKit.card({
		Name = "Detail",
		Size = UDim2.new(1, -(GRID_W + 14), 1, -60),
		Position = UDim2.fromOffset(GRID_W + 14, 58),
		Parent = page,
	})
	local _dw: Frame
	_dw, detailVp, detailCam = UIKit.previewWell({
		Size = UDim2.new(1, -16, 0, 118),
		Position = UDim2.fromOffset(8, 8),
		Parent = detail,
	})
	detailTitle = UIKit.label({
		Name = "Title",
		Text = "",
		FontFace = Theme.FontDisplayFlat,
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.fromOffset(8, 130),
		MaxTextSize = 20,
		Parent = detail,
	})
	detailSerial = UIKit.label({
		Name = "Serial",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(0.5, -8, 0, 22),
		Position = UDim2.fromOffset(8, 174),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
		Parent = detail,
	})
	detailRarityTag, detailRarity = UIKit.tag({
		Name = "Rarity",
		Size = UDim2.fromOffset(128, 24),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 172),
		Rotation = -2,
		Parent = detail,
	}, "", 14)
	detailRarity.TextColor3 = Theme.Ink
	detailBonus = UIKit.label({
		Name = "Bonus",
		Text = "",
		FontFace = Theme.FontNumber,
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 200),
		MaxTextSize = 28,
		NoStroke = false,
		Parent = detail,
	})
	UIKit.gradientText(detailBonus, Theme.VoltHi, Theme.Volt)
	detailZone = UIKit.label({
		Name = "Zone",
		Text = "",
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 232),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
		Parent = detail,
	})
	detailHint = UIKit.label({
		Name = "Hint",
		Text = Loc.t("Нажми на фульгурит"),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 190),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 24,
		Parent = detail,
	})
	equipButton = UIKit.button({
		Name = "Equip",
		Text = Loc.t("Надеть"),
		Color = Theme.Go,
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
			ClientState.Toast:Fire(Loc.t("Надеть можно только %d — сними один", Fulgurite.MaxEquipped), "bad")
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
		Text = Loc.t("Разбить"),
		Color = Theme.Danger,
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
			Loc.t("Разбить фульгурит «%s» %s?", spec.ShapeName, serialText(f)),
			(if mut then Loc.t(Fulgurite.Mutations[mut].Name) .. " · " else "") .. Loc.t(Pets.Rarities[spec.Rarity].Name) .. " · " .. bonusText(spec),
		}
		if isEquipped(d, id) then
			table.insert(lines, Loc.t("Он сейчас надет!"))
		end
		table.insert(lines, Loc.t("Получишь 💎 %s, а он исчезнет навсегда.", Format.short(Fulgurite.shatterValue(spec.Rarity, f.Zone))))
		win.confirm(table.concat(lines, "\n"), Loc.t("Разбить"), function()
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
type Cell = { frame: Frame, grad: UIGradient, glyph: Frame, unknown: TextLabel, name: TextLabel, stroke: UIStroke }
type Row = { cells: { [string]: Cell }, progress: TextLabel, reward: UIKit.Status }
local rows: { Row } = {}
local specialCells: { [string]: Cell } = {}
local indexTotal: TextLabel

local function makeCell(parent: Instance, order: number, size: Vector2, color: Config.ColorId): Cell
	local def = Config.Colors[color]
	local frame = UIKit.new("Frame", {
		Name = "Cell" .. order,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	UIKit.corner(frame, 8)
	local stroke = UIKit.stroke(frame, 2, Theme.Ink)
	local grad = UIKit.gradient(frame, Theme.Night700, Theme.Night900)
	-- знак цвета нарисован: ● ◆ ▲ ★ ✦ ✺ ☯ (Чёрная Перуна — молния в тёмном круге)
	local glyph = UIKit.glyph(frame, UIKit.colorGlyphKind(color), {
		Name = "Icon",
		Size = UDim2.fromScale(0.42, 0.42),
		Position = UDim2.fromScale(0.5, 0.36),
		Color = if color == "black" then Theme.Ink else Theme.Cream,
		Stroke = 2,
		Visible = false,
	})
	local unknown = UIKit.label({
		Name = "Unknown",
		Text = "?",
		FontFace = Theme.FontDisplay,
		Size = UDim2.new(1, -6, 0.56, 0),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = Theme.Slate,
		MaxTextSize = 30,
		Parent = frame,
	})
	local name = UIKit.label({
		Name = "Name",
		Text = Loc.t(def.Name),
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(1, -6, 0.3, 0),
		Position = UDim2.fromScale(0.5, 0.82),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 14,
		Parent = frame,
	})
	return { frame = frame, grad = grad, glyph = glyph, unknown = unknown, name = name, stroke = stroke }
end

local function setCell(cell: Cell, color: Config.ColorId, caught: boolean)
	local def = Config.Colors[color]
	cell.glyph.Visible = caught
	cell.unknown.Visible = not caught
	cell.name.Text = Loc.t(def.Name)
	if caught then
		local c = def.Color
		if color == "black" then
			cell.grad.Color = ColorSequence.new(Color3.fromRGB(90, 60, 130), Color3.fromRGB(20, 10, 30))
			cell.stroke.Color = Theme.Gold
		elseif color == "rainbow" then
			cell.grad.Color = UIKit.seq({
				{ 0, Color3.fromRGB(255, 110, 110) },
				{ 0.33, Color3.fromRGB(255, 220, 90) },
				{ 0.66, Color3.fromRGB(110, 230, 160) },
				{ 1, Color3.fromRGB(150, 120, 255) },
			})
			cell.stroke.Color = Theme.Cream
		else
			cell.grad.Color = ColorSequence.new(c:Lerp(WHITE, 0.2), c:Lerp(Theme.Ink, 0.45))
			cell.stroke.Color = Theme.Ink
		end
		cell.name.TextColor3 = Theme.Cream
		local s = cell.name:FindFirstChildOfClass("UIStroke") or UIKit.textStroke(cell.name, 1.5)
		s.Enabled = true
	else
		cell.grad.Color = ColorSequence.new(Theme.Well, Theme.Well)
		cell.name.TextColor3 = Theme.Slate
		cell.stroke.Color = Theme.Ink
		local s = cell.name:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = false
		end
	end
end

local function buildIndex(page: Frame)
	indexTotal = UIKit.label({
		Name = "Total",
		Text = "",
		FontFace = Theme.FontBodyHeavy,
		Size = UDim2.new(0.4, -8, 0, 34),
		Position = UDim2.fromOffset(4, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Volt,
		MaxTextSize = 26,
		Parent = page,
	})
	UIKit.label({
		Name = "Hint",
		Text = Loc.t("Собери весь остров — Вольты навсегда +10%!"),
		Size = UDim2.new(0.6, 0, 0, 30),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 19,
		Parent = page,
	})
	local scroller = UIKit.scroll({
		Name = "Rows",
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		Parent = page,
	})
	UIKit.list(scroller, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 4, 4)
	local cellSize = Vector2.new(92, 60)
	local function rowFrame(order: number, title: string, accent: Color3): Frame
		local row = UIKit.new("Frame", {
			Name = "Row" .. order,
			Size = UDim2.fromOffset(816, 70),
			BackgroundColor3 = WHITE,
			LayoutOrder = order,
			Parent = scroller,
		}) :: Frame
		UIKit.corner(row, Theme.CornerSmall)
		UIKit.stroke(row, 1.5, Theme.LineLight, 0.7)
		-- полоса акцента острова слева (градиентом — повторяет скругление)
		UIKit.new("UIGradient", {
			Rotation = 0,
			Color = UIKit.seq({
				{ 0, accent },
				{ 0.008, accent },
				{ 0.012, Theme.Night700:Lerp(accent, 0.12) },
				{ 1, Theme.Night800 },
			}),
			Parent = row,
		})
		UIKit.label({
			Name = "Title",
			Text = title,
			FontFace = Theme.FontDisplayFlat,
			Size = UDim2.fromOffset(166, 46),
			Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = accent:Lerp(WHITE, 0.45),
			MaxTextSize = 20,
			Parent = row,
		})
		local cellsFrame = UIKit.new("Frame", {
			Name = "Cells",
			Size = UDim2.fromOffset(5 * cellSize.X + 4 * 6, cellSize.Y),
			Position = UDim2.new(0, 190, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Parent = row,
		}) :: Frame
		UIKit.list(cellsFrame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left)
		return row
	end
	for z, zdef in Config.Zones do
		local row = rowFrame(z, Loc.t(zdef.Name), zdef.Accent)
		local cellsFrame = row:FindFirstChild("Cells") :: Frame
		local cellMap: { [string]: Cell } = {}
		for i, c in Config.NormalColors do
			cellMap[c] = makeCell(cellsFrame, i, cellSize, c)
		end
		local progress = UIKit.label({
			Name = "Progress",
			Text = "0/5",
			FontFace = Theme.FontNumber,
			Size = UDim2.fromOffset(64, 30),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 6),
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxTextSize = 26,
			Parent = row,
		})
		local reward = UIKit.status(row, UDim2.fromOffset(104, 22), UDim2.new(1, -116, 1, -28), 17)
		table.insert(rows, { cells = cellMap, progress = progress, reward = reward })
	end
	local special = rowFrame(#Config.Zones + 1, Loc.t("Особые"), Theme.Rainbow)
	local cellsFrame = special:FindFirstChild("Cells") :: Frame
	for i, c in SPECIAL do
		specialCells[c] = makeCell(cellsFrame, i, cellSize, c)
	end
	UIKit.label({
		Name = "Note",
		Text = Loc.t("Радужная — на событии, Чёрная — на Оке Бури"),
		Size = UDim2.fromOffset(300, 40),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
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
		row.progress.TextColor3 = if full then Theme.GoHi else Theme.Cream
		row.reward.set(if full then "check" else nil, "+10% ⚡", if full then Theme.GoHi else Theme.TextDim)
	end
	for _, c in SPECIAL do
		local caught = hasSpecial(d, c)
		if caught then
			total += 1
		end
		setCell(specialCells[c], c, caught)
	end
	indexTotal.Text = Loc.t("Поймано: %d/%d", total, max)
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
		Title = Loc.t("Коллекция"),
		Icon = "🔮",
		Width = 880,
		Height = 560,
		Accent = Theme.Spark,
		Tabs = {
			{ Id = "fulgs", Text = Loc.t("Фульгуриты") },
			{ Id = "index", Text = Loc.t("Молниедекс") },
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
