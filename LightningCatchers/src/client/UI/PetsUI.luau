--!strict
-- Питомцы: мои (сетка с 3D-превью, надеть/снять/удалить, "Надеть лучших"), коконы (шансы, гарантия)
-- и анимация вылупления на весь экран: кокон дрожит всё быстрее, светится цветом редкости, лопается.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Pets = require(Shared:WaitForChild("Pets"))
local Format = require(Shared:WaitForChild("Format"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Juice = require(script.Parent.Parent.Controllers.Juice)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local PetsUI = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local CELL = Vector2.new(124, 152)
local GRID_W = 556
local SPIN_SPEED = 0.8 -- рад/с, вращение превью
local MAX_BUILDS_PER_STEP = 2 -- сколько превью строить за кадр (без рывков)
local HATCH_WOBBLE = 2.1

local win: UIKit.Window
local shardsLabel: TextLabel

----------------------------------------------------------------------
-- Модели для превью
----------------------------------------------------------------------
local function buildModel(make: () -> Model): Model?
	local ok, model = pcall(make)
	if ok and typeof(model) == "Instance" and model:IsA("Model") then
		return model
	end
	return nil
end

local function petRank(kind: string): number
	local def = Pets.Kinds[kind]
	return if def then Pets.Rarities[def.Rarity].Rank else 0
end

local function rarityOf(kind: string): { Name: string, Color: Color3, Rank: number }
	local def = Pets.Kinds[kind]
	return if def then Pets.Rarities[def.Rarity] else Pets.Rarities.common
end

----------------------------------------------------------------------
-- Вкладка "Мои"
----------------------------------------------------------------------
type PetCard = {
	id: number,
	kind: string,
	button: TextButton,
	vp: ViewportFrame,
	camera: Camera,
	model: Model?,
	center: Vector3,
	dist: number,
	check: Frame,
	stroke: UIStroke,
	phase: number,
}

local grid: ScrollingFrame
local emptyHint: Frame
local slotsLabel: TextLabel
local countLabel: TextLabel
local petCards: { [number]: PetCard } = {}
local selectedId: number? = nil
local busy = false

-- панель выбранного питомца
local detail: Frame
local detailVp: ViewportFrame
local detailCam: Camera
local detailModel: Model? = nil
local detailCenter = Vector3.zero
local detailDist = 8
local detailKind = ""
local detailName: TextLabel
local detailRarity: TextLabel
local detailBonus: TextLabel
local detailHint: TextLabel
local equipButton: TextButton
local deleteButton: TextButton

local function slots(d: PlayerData.Data): number
	return Economy.petSlots(d.Rebirths)
end

local function isEquipped(d: PlayerData.Data, id: number): boolean
	return table.find(d.Equipped, id) ~= nil
end

local function ensureCardModel(c: PetCard)
	if c.model then
		return
	end
	local model = buildModel(function()
		return Models.pet(c.kind)
	end)
	if not model then
		return
	end
	model.Parent = c.vp
	c.model = model
	c.center, c.dist = UIKit.frameModel(model, c.camera.FieldOfView, 0.78)
	UIKit.orbit(c.camera, c.center, c.dist, c.phase, 0.25)
end

local function selectPet(id: number?)
	selectedId = id
	for cid, c in petCards do
		if cid == id then
			c.stroke.Color = WHITE
			c.stroke.Thickness = 4.5
		else
			c.stroke.Color = rarityOf(c.kind).Color
			c.stroke.Thickness = 3
		end
	end
	local d = ClientState.get()
	local kind = if d and id then PlayerData.petKind(d, id) else nil
	if not kind or not d or not id then
		detailHint.Visible = true
		detailName.Visible = false
		detailRarity.Visible = false
		detailBonus.Visible = false
		equipButton.Visible = false
		deleteButton.Visible = false
		if detailModel then
			detailModel:Destroy()
			detailModel = nil
			detailKind = ""
		end
		return
	end
	local rar = rarityOf(kind)
	detailHint.Visible = false
	detailName.Visible = true
	detailRarity.Visible = true
	detailBonus.Visible = true
	equipButton.Visible = true
	deleteButton.Visible = true
	detailName.Text = Pets.Kinds[kind].Name
	detailName.TextColor3 = rar.Color
	detailRarity.Text = rar.Name
	detailRarity.TextColor3 = rar.Color
	detailBonus.Text = Pets.bonusText(kind)
	if isEquipped(d, id) then
		UIKit.setButtonText(equipButton, "Снять")
		UIKit.setButtonColor(equipButton, Theme.Gray)
	else
		UIKit.setButtonText(equipButton, "Надеть")
		UIKit.setButtonColor(equipButton, Theme.Green)
	end
	if kind ~= detailKind then
		if detailModel then
			detailModel:Destroy()
			detailModel = nil
		end
		detailKind = kind
		local model = buildModel(function()
			return Models.pet(kind)
		end)
		if model then
			model.Parent = detailVp
			detailModel = model
			detailCenter, detailDist = UIKit.frameModel(model, detailCam.FieldOfView, 0.72)
		end
	end
end

local function makePetCard(id: number, kind: string): PetCard
	local rar = rarityOf(kind)
	local def = Pets.Kinds[kind]
	local button = UIKit.new("TextButton", {
		Name = "Pet" .. id,
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		Parent = grid,
	}) :: TextButton
	UIKit.corner(button, Theme.CornerSmall)
	local stroke = UIKit.stroke(button, 3, rar.Color)
	UIKit.gradient(button, rar.Color:Lerp(Theme.Card, 0.55), Theme.PanelDark)
	local vp, camera = UIKit.viewport({
		Name = "Preview",
		Size = UDim2.new(1, -8, 0, 94),
		Position = UDim2.fromOffset(4, 4),
		Parent = button,
	})
	UIKit.label({
		Name = "Name",
		Text = if def then def.Name else kind,
		Size = UDim2.new(1, -8, 0, 24),
		Position = UDim2.fromOffset(4, 98),
		TextColor3 = rar.Color:Lerp(WHITE, 0.35),
		MaxTextSize = 22,
		Parent = button,
	})
	UIKit.label({
		Name = "Bonus",
		Text = Pets.bonusText(kind),
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 124),
		FontFace = Theme.FontBold,
		TextColor3 = Theme.TextDim,
		MaxTextSize = 17,
		Parent = button,
	})
	local check = UIKit.new("Frame", {
		Name = "Equipped",
		Size = UDim2.fromOffset(32, 32),
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
		MaxTextSize = 24,
		ZIndex = 5,
		Parent = check,
	})
	local card: PetCard = {
		id = id,
		kind = kind,
		button = button,
		vp = vp,
		camera = camera,
		model = nil,
		center = Vector3.zero,
		dist = 8,
		check = check,
		stroke = stroke,
		phase = (id * 1.7) % (math.pi * 2),
	}
	button.Activated:Connect(function()
		UIKit.playClick()
		selectPet(id)
	end)
	return card
end

local function refreshMine(d: PlayerData.Data)
	local n = slots(d)
	slotsLabel.Text = string.format("Надето: %d/%d", #d.Equipped, n)
	countLabel.Text = string.format("Всего: %d/%d", #d.Pets, Pets.MaxInventory)
	local present: { [number]: boolean } = {}
	local list: { PlayerData.PetRecord } = table.clone(d.Pets)
	table.sort(list, function(a: PlayerData.PetRecord, b: PlayerData.PetRecord): boolean
		local ea, eb = isEquipped(d, a.Id), isEquipped(d, b.Id)
		if ea ~= eb then
			return ea
		end
		local ra, rb = petRank(a.Kind), petRank(b.Kind)
		if ra ~= rb then
			return ra > rb
		end
		local va = Pets.Kinds[a.Kind] and Pets.Kinds[a.Kind].Value or 0
		local vb = Pets.Kinds[b.Kind] and Pets.Kinds[b.Kind].Value or 0
		if va ~= vb then
			return va > vb
		end
		return a.Id < b.Id
	end)
	for i, p in list do
		present[p.Id] = true
		local c = petCards[p.Id]
		if not c then
			c = makePetCard(p.Id, p.Kind)
			petCards[p.Id] = c
		end
		c.button.LayoutOrder = i
		c.check.Visible = isEquipped(d, p.Id)
	end
	for id, c in petCards do
		if not present[id] then
			c.button:Destroy()
			petCards[id] = nil
		end
	end
	emptyHint.Visible = #d.Pets == 0
	if selectedId and not present[selectedId] then
		selectedId = nil
	end
	if not selectedId and list[1] then
		selectedId = list[1].Id
	end
	selectPet(selectedId)
end

local function buildMine(page: Frame)
	-- верхняя строка: места, количество, "Надеть лучших"
	local top = UIKit.new("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundTransparency = 1,
		Parent = page,
	}) :: Frame
	slotsLabel = UIKit.label({
		Name = "Slots",
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
	UIKit.button({
		Name = "EquipBest",
		Text = "Надеть лучших",
		Icon = "⭐",
		Color = Theme.Purple,
		Size = UDim2.fromOffset(290, 60),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		TextSize = 26,
		Parent = top,
	}, function()
		local d = ClientState.get()
		if busy or not d then
			return
		end
		if #d.Pets == 0 then
			Sounds.play("Error")
			ClientState.Toast:Fire("Сначала вылупи питомца!", "info")
			return
		end
		busy = true
		local ok = ClientState.request(Net.Actions.EquipBest, nil)
		busy = false
		if ok then
			Sounds.play("PowerUp")
		else
			Sounds.play("Error")
		end
	end)

	grid = UIKit.scroll({
		Name = "Grid",
		Size = UDim2.new(0, GRID_W, 1, -70),
		Position = UDim2.fromOffset(0, 70),
		Parent = page,
	})
	UIKit.grid(grid, CELL, 10).HorizontalAlignment = Enum.HorizontalAlignment.Left
	UIKit.padding(grid, 4, 4)

	emptyHint = UIKit.new("Frame", {
		Name = "Empty",
		Size = UDim2.new(0, GRID_W, 1, -70),
		Position = UDim2.fromOffset(0, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = page,
	}) :: Frame
	UIKit.label({
		Text = "Пока нет питомцев.\nВылупи их из кокона!",
		Size = UDim2.new(1, -40, 0, 100),
		Position = UDim2.new(0.5, 0, 0.32, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 30,
		Parent = emptyHint,
	})
	UIKit.button({
		Text = "К коконам",
		Icon = "🥚",
		Color = Theme.Green,
		Size = UDim2.fromOffset(260, 66),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.68, 0),
		Parent = emptyHint,
	}, function()
		win.setTab("cocoons")
	end)

	-- панель выбранного
	detail = UIKit.card({
		Name = "Detail",
		Size = UDim2.new(1, -(GRID_W + 12), 1, -70),
		Position = UDim2.fromOffset(GRID_W + 12, 70),
		Parent = page,
	})
	detailVp, detailCam = UIKit.viewport({
		Name = "Preview",
		Size = UDim2.new(1, -16, 0, 136),
		Position = UDim2.fromOffset(8, 6),
		Parent = detail,
	})
	detailName = UIKit.label({
		Name = "Name",
		Text = "",
		Size = UDim2.new(1, -16, 0, 32),
		Position = UDim2.fromOffset(8, 144),
		MaxTextSize = 32,
		Parent = detail,
	})
	detailRarity = UIKit.label({
		Name = "Rarity",
		Text = "",
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 176),
		FontFace = Theme.FontBold,
		MaxTextSize = 22,
		Parent = detail,
	})
	detailBonus = UIKit.label({
		Name = "Bonus",
		Text = "",
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 200),
		TextColor3 = Theme.Volt,
		MaxTextSize = 24,
		Parent = detail,
	})
	detailHint = UIKit.label({
		Name = "Hint",
		Text = "Нажми на питомца",
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 170),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 26,
		Parent = detail,
	})
	equipButton = UIKit.button({
		Name = "Equip",
		Text = "Надеть",
		Color = Theme.Green,
		Size = UDim2.new(1, -96, 0, 62),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		TextSize = 28,
		Parent = detail,
	}, function()
		local d = ClientState.get()
		local id = selectedId
		if busy or not d or not id then
			return
		end
		local equipped = isEquipped(d, id)
		if not equipped and #d.Equipped >= slots(d) then
			Sounds.play("Error")
			ClientState.Toast:Fire("Все места заняты — сними кого-нибудь", "bad")
			return
		end
		busy = true
		local ok = ClientState.request(if equipped then Net.Actions.UnequipPet else Net.Actions.EquipPet, id)
		busy = false
		if not ok then
			Sounds.play("Error")
		elseif not equipped then
			Sounds.play("PowerUp")
		end
	end)
	deleteButton = UIKit.button({
		Name = "Delete",
		Text = "🗑",
		Color = Theme.Red,
		Size = UDim2.fromOffset(66, 62),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		TextSize = 30,
		Parent = detail,
	}, function()
		local d = ClientState.get()
		local id = selectedId
		if busy or not d or not id then
			return
		end
		local kind = PlayerData.petKind(d, id)
		if not kind then
			return
		end
		-- кого именно отпускаем: редкость, бонус и надет ли он сейчас — чтобы не удалить лучшего по ошибке
		local lines = {
			string.format("Отпустить питомца «%s»?", Pets.Kinds[kind].Name),
			rarityOf(kind).Name .. " · " .. Pets.bonusText(kind),
		}
		if isEquipped(d, id) then
			table.insert(lines, "⚠ Он сейчас надет!")
		end
		table.insert(lines, "Вернуть его будет нельзя.")
		win.confirm(table.concat(lines, "\n"), "Удалить", function()
			busy = true
			local ok = ClientState.request(Net.Actions.DeletePet, id)
			busy = false
			if not ok then
				Sounds.play("Error")
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Вкладка "Коконы"
----------------------------------------------------------------------
type CocoonCard = {
	id: string,
	req: TextLabel,
	pity: TextLabel,
	button: TextButton,
	vp: ViewportFrame,
	camera: Camera,
	model: Model?,
	center: Vector3,
	dist: number,
}
local cocoonCards: { CocoonCard } = {}
local hatchCocoon: (id: string) -> ()

local function buildCocoons(page: Frame)
	local scroller = UIKit.scroll({
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		Parent = page,
	})
	UIKit.list(scroller, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	UIKit.padding(scroller, 2, 4)
	for i, id in Pets.CocoonOrder do
		local def = Pets.Cocoons[id]
		local chances = Pets.chances(id)
		local rows = #chances
		local h = 248 + rows * 19
		local card = UIKit.card({
			Name = id,
			Size = UDim2.fromOffset(268, h),
			LayoutOrder = i,
			Parent = scroller,
		})
		UIKit.tintCard(card, def.Color:Lerp(Theme.Card, 0.6), Theme.PanelDark)
		UIKit.label({
			Name = "Title",
			Text = def.Name,
			Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.fromOffset(8, 6),
			MaxTextSize = 26,
			Parent = card,
		})
		local vp, camera = UIKit.viewport({
			Name = "Preview",
			Size = UDim2.new(1, -16, 0, 76),
			Position = UDim2.fromOffset(8, 34),
			Parent = card,
		})
		local req = UIKit.label({
			Name = "Req",
			Text = "",
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.fromOffset(8, 112),
			MaxTextSize = 17,
			Parent = card,
		})
		local list = UIKit.new("Frame", {
			Name = "Odds",
			Size = UDim2.new(1, -20, 0, rows * 19),
			Position = UDim2.fromOffset(10, 136),
			BackgroundColor3 = Theme.PanelDark,
			BackgroundTransparency = 0.4,
			Parent = card,
		}) :: Frame
		UIKit.corner(list, 8)
		for r, e in chances do
			local rar = rarityOf(e.kind)
			local kdef = Pets.Kinds[e.kind]
			UIKit.label({
				Name = "Kind" .. r,
				Text = (if kdef then kdef.Name else e.kind) .. " · " .. rar.Name,
				Size = UDim2.new(0.74, -6, 0, 18),
				Position = UDim2.fromOffset(6, (r - 1) * 19),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = rar.Color,
				FontFace = Theme.FontBold,
				MaxTextSize = 17,
				Parent = list,
			})
			UIKit.label({
				Name = "Chance" .. r,
				Text = Format.percent(e.chance),
				Size = UDim2.new(0.26, -6, 0, 18),
				Position = UDim2.new(0.74, 0, 0, (r - 1) * 19),
				TextXAlignment = Enum.TextXAlignment.Right,
				MaxTextSize = 17,
				Parent = list,
			})
		end
		local pity = UIKit.label({
			Name = "Pity",
			Text = "",
			Size = UDim2.new(1, -16, 0, 34),
			Position = UDim2.fromOffset(8, 140 + rows * 19),
			TextColor3 = Pets.Rarities.legendary.Color,
			FontFace = Theme.FontBold,
			MaxTextSize = 16,
			Parent = card,
		})
		local button = UIKit.button({
			Name = "Hatch",
			Text = "Вылупить 💎" .. Format.short(def.Cost),
			Color = Theme.Green,
			Size = UDim2.new(1, -20, 0, 62),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			TextSize = 24,
			Parent = card,
		}, function()
			hatchCocoon(id)
		end)
		table.insert(cocoonCards, {
			id = id,
			req = req,
			pity = pity,
			button = button,
			vp = vp,
			camera = camera,
			model = nil,
			center = Vector3.zero,
			dist = 8,
		})
	end
end

local function refreshCocoons(d: PlayerData.Data)
	for _, c in cocoonCards do
		local def = Pets.Cocoons[c.id]
		local zoneName = Config.Zones[def.Zone].Name
		local unlocked = d.Zone >= def.Zone
		if unlocked then
			c.req.Text = "Остров: " .. zoneName
			c.req.TextColor3 = Theme.TextDim
		else
			c.req.Text = "🔒 Нужен остров «" .. zoneName .. "»"
			c.req.TextColor3 = Theme.Miss
		end
		-- как в Pets.roll: гарантирован кокон, на котором pity + 1 >= PityAt
		local pity = d.Pity[c.id] or 0
		local left = math.max(1, def.PityAt - pity)
		c.pity.Text = if left <= 1
			then "Следующий кокон — точно легендарный!"
			else string.format("Легендарный точно выпадет за %d %s", left, Format.plural(left, "кокон", "кокона", "коконов"))
		local affordable = unlocked and d.Shards >= def.Cost and #d.Pets < Pets.MaxInventory
		UIKit.setButtonColor(c.button, if affordable then Theme.Green else Theme.Gray)
		if not c.model then
			local model = buildModel(function()
				return Models.cocoon(c.id)
			end)
			if model then
				model.Parent = c.vp
				c.model = model
				c.center, c.dist = UIKit.frameModel(model, c.camera.FieldOfView, 0.8)
				UIKit.orbit(c.camera, c.center, c.dist, 0, 0.2)
			end
		end
	end
end

----------------------------------------------------------------------
-- Анимация вылупления
----------------------------------------------------------------------
local hatchGui: ScreenGui
local hatchBg: TextButton
local hatchContent: Frame
local hatchVp: ViewportFrame
local hatchCam: Camera
local hatchGlow: { Frame } = {}
local hatchRays: Frame
local hatchRaysTween: Tween? = nil
local hatchName: TextLabel
local hatchRarity: TextLabel
local hatchBonus: TextLabel
local hatchHint: TextLabel
local hatchState = "idle" -- idle | wobble | reveal
local hatchModel: Model? = nil
local hatchConn: RBXScriptConnection? = nil

local function buildHatch()
	hatchGui = UIKit.new("ScreenGui", {
		Name = "Hatch",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 40,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	hatchBg = UIKit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 8, 22),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Parent = hatchGui,
	}) :: TextButton
	hatchContent = UIKit.new("Frame", {
		Name = "Content",
		Size = UDim2.fromOffset(720, 640),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = hatchGui,
	}) :: Frame
	UIKit.autoScale(hatchContent, "modal", 720, 640)

	-- лучи за питомцем
	hatchRays = UIKit.new("Frame", {
		Name = "Rays",
		Size = UDim2.fromOffset(900, 900),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 250),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hatchContent,
	}) :: Frame
	for i = 0, 5 do
		local bar = UIKit.new("Frame", {
			Name = "Ray" .. i,
			Size = UDim2.new(0, 70, 1, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = i * 30,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.55,
			Parent = hatchRays,
		}) :: Frame
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})
	end
	-- свечение цвета редкости (подсказка до вскрытия)
	for i, s in { 480, 380, 290 } do
		local ring = UIKit.new("Frame", {
			Name = "Glow" .. i,
			Size = UDim2.fromOffset(s, s),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 250),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			Parent = hatchContent,
		}) :: Frame
		UIKit.round(ring)
		UIKit.new("UIScale", { Scale = 1, Parent = ring })
		table.insert(hatchGlow, ring)
	end
	hatchVp, hatchCam = UIKit.viewport({
		Name = "Preview",
		Size = UDim2.fromOffset(440, 440),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 250),
		Ambient = Color3.fromRGB(170, 175, 210),
		Parent = hatchContent,
	})
	hatchName = UIKit.label({
		Name = "Name",
		Text = "",
		Size = UDim2.fromOffset(680, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 470),
		MaxTextSize = 60,
		Visible = false,
		Parent = hatchContent,
	})
	hatchRarity = UIKit.label({
		Name = "Rarity",
		Text = "",
		Size = UDim2.fromOffset(600, 36),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 532),
		MaxTextSize = 34,
		Visible = false,
		Parent = hatchContent,
	})
	hatchBonus = UIKit.label({
		Name = "Bonus",
		Text = "",
		Size = UDim2.fromOffset(600, 32),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 568),
		TextColor3 = Theme.Volt,
		MaxTextSize = 30,
		Visible = false,
		Parent = hatchContent,
	})
	hatchHint = UIKit.label({
		Name = "Hint",
		Text = "Нажми, чтобы продолжить",
		Size = UDim2.fromOffset(600, 28),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 606),
		TextColor3 = Theme.TextDim,
		MaxTextSize = 24,
		Visible = false,
		Parent = hatchContent,
	})

	hatchBg.Activated:Connect(function()
		if hatchState ~= "reveal" then
			return
		end
		hatchState = "idle"
		local conn = hatchConn
		hatchConn = nil
		if conn then
			conn:Disconnect()
		end
		local rt = hatchRaysTween
		hatchRaysTween = nil
		if rt then
			rt:Cancel()
		end
		UIKit.tween(hatchBg, 0.2, { BackgroundTransparency = 1 })
		local scale = hatchContent:FindFirstChildOfClass("UIScale")
		if scale then
			UIKit.popOut(hatchContent, scale, function()
				if hatchState == "idle" then
					hatchGui.Enabled = false
					hatchContent.Visible = true
					if hatchModel then
						hatchModel:Destroy()
						hatchModel = nil
					end
				end
			end)
		else
			hatchGui.Enabled = false
		end
	end)
end

local function setGlow(color: Color3, strength: number)
	for i, ring in hatchGlow do
		ring.BackgroundColor3 = color
		ring.BackgroundTransparency = 1 - strength * (0.12 + 0.1 * i)
	end
end

local function revealPet(kind: string)
	local rar = rarityOf(kind)
	local def = Pets.Kinds[kind]
	if hatchModel then
		hatchModel:Destroy()
		hatchModel = nil
	end
	local model = buildModel(function()
		return Models.pet(kind)
	end)
	local center, dist = Vector3.zero, 8
	if model then
		model.Parent = hatchVp
		hatchModel = model
		center, dist = UIKit.frameModel(model, hatchCam.FieldOfView, 0.62)
	end
	-- вспышка (через Juice: «Мягкие вспышки» её приглушают) и показ
	if rar.Rank >= 3 then
		Juice.flash(rar.Color:Lerp(WHITE, 0.35), 0.9)
	else
		Juice.flash(rar.Color:Lerp(WHITE, 0.6), 0.75)
	end
	setGlow(rar.Color, 1)
	hatchRays.Visible = true
	for _, ray in hatchRays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = rar.Color:Lerp(WHITE, 0.4)
		end
	end
	hatchRays.Rotation = 0
	hatchRaysTween = TweenService:Create(hatchRays, TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	local rt = hatchRaysTween
	if rt then
		rt:Play()
	end
	hatchName.Text = if def then def.Name else kind
	hatchName.TextColor3 = rar.Color:Lerp(WHITE, 0.25)
	hatchRarity.Text = rar.Name
	hatchRarity.TextColor3 = rar.Color
	hatchBonus.Text = Pets.bonusText(kind)
	for _, l in { hatchName, hatchRarity, hatchBonus } do
		l.Visible = true
		local s = l:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = l }) :: UIScale
		s.Scale = 0.3
		UIKit.tween(s, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	if rar.Rank >= 3 then
		Sounds.play("RareReveal")
	else
		Sounds.play("Ding", 1.2)
	end
	Sounds.play("Coins")
	-- питомец кружится
	local yaw = 0
	local conn = hatchConn
	if conn then
		conn:Disconnect()
	end
	hatchConn = RunService.Heartbeat:Connect(function(dt: number)
		yaw += dt * 1.6
		UIKit.orbit(hatchCam, center, dist, yaw, 0.18)
	end)
	task.delay(0.7, function()
		if hatchState == "reveal" then
			hatchHint.Visible = true
		end
	end)
end

hatchCocoon = function(id: string)
	local d = ClientState.get()
	local def = Pets.Cocoons[id]
	if not d or not def or hatchState ~= "idle" then
		return
	end
	if d.Zone < def.Zone then
		Sounds.play("Error")
		ClientState.Toast:Fire("Сначала открой «" .. Config.Zones[def.Zone].Name .. "»", "info")
		return
	end
	if #d.Pets >= Pets.MaxInventory then
		Sounds.play("Error")
		ClientState.Toast:Fire("Нет места — удали лишних питомцев", "bad")
		return
	end
	if d.Shards < def.Cost then
		Sounds.play("Error")
		ClientState.Toast:Fire("Не хватает 💎 " .. Format.short(def.Cost - d.Shards), "bad")
		return
	end

	hatchState = "wobble"
	-- запрос к серверу идёт параллельно с дрожанием
	local done = false
	local okResult = false
	local result: any = nil
	task.spawn(function()
		okResult, result = ClientState.request(Net.Actions.Hatch, id)
		done = true
	end)

	-- подготовить экран
	for _, l in { hatchName, hatchRarity, hatchBonus, hatchHint } do
		l.Visible = false
	end
	hatchRays.Visible = false
	setGlow(WHITE, 0)
	if hatchModel then
		hatchModel:Destroy()
		hatchModel = nil
	end
	local model = buildModel(function()
		return Models.cocoon(id)
	end)
	local pivot0 = CFrame.identity
	local bottom = Vector3.zero
	if model then
		model.Parent = hatchVp
		hatchModel = model
		local center, dist = UIKit.frameModel(model, hatchCam.FieldOfView, 0.75)
		UIKit.orbit(hatchCam, center, dist, 0, 0.12)
		local cf, size = model:GetBoundingBox()
		pivot0 = model:GetPivot()
		bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
	end
	hatchGui.Enabled = true
	hatchBg.BackgroundTransparency = 1
	UIKit.tween(hatchBg, 0.25, { BackgroundTransparency = 0.12 })
	local scale = hatchContent:FindFirstChildOfClass("UIScale")
	if scale then
		UIKit.popIn(hatchContent, scale)
	end
	Sounds.play("Purchase")
	Sounds.play("HatchWobble")

	local t = 0
	local phase = 0
	local soundAgain = false
	local glowColor: Color3? = nil
	local finished = false
	local conn = hatchConn
	if conn then
		conn:Disconnect()
	end
	hatchConn = RunService.Heartbeat:Connect(function(dt: number)
		if finished then
			return
		end
		t += dt
		local k = math.clamp(t / HATCH_WOBBLE, 0, 1)
		phase += dt * (8 + 34 * k * k)
		local angle = math.sin(phase) * math.rad(4 + 12 * k)
		local m = hatchModel
		if m and m.Parent then
			m:PivotTo(CFrame.new(bottom) * CFrame.Angles(0, 0, angle) * CFrame.new(-bottom) * pivot0)
		end
		if not soundAgain and t > HATCH_WOBBLE * 0.5 then
			soundAgain = true
			Sounds.play("HatchWobble", 1.15)
		end
		-- подсказка цветом редкости результата
		if done and okResult and typeof(result) == "table" and typeof(result.Kind) == "string" then
			if not glowColor then
				glowColor = rarityOf(result.Kind).Color
			end
			local g = glowColor
			if g and t > 0.9 then
				local pulse = 0.75 + 0.25 * math.sin(t * 14)
				setGlow(g, math.clamp((t - 0.9) / 1.0, 0, 1) * pulse)
				for i, ring in hatchGlow do
					local s = ring:FindFirstChildOfClass("UIScale")
					if s then
						s.Scale = 1 + 0.06 * math.sin(t * 10 + i)
					end
				end
			end
		end
		if done and not okResult then
			-- сервер отказал (тост уже показан) — закрыть
			finished = true
			hatchState = "idle"
			hatchGui.Enabled = false
			local c = hatchConn
			hatchConn = nil
			if c then
				c:Disconnect()
			end
			return
		end
		if t >= HATCH_WOBBLE and done and glowColor then
			finished = true
			hatchState = "reveal"
			revealPet((result :: any).Kind :: string)
		elseif t > 10 then
			-- нет ответа слишком долго
			finished = true
			hatchState = "idle"
			hatchGui.Enabled = false
			local c = hatchConn
			hatchConn = nil
			if c then
				c:Disconnect()
			end
		end
	end)
end

----------------------------------------------------------------------
-- Вращение превью (~30 раз в секунду): крутятся только выбранная карточка и большое превью,
-- остальные карточки стоят под своим углом — каждый сдвиг камеры перерисовывает ViewportFrame
----------------------------------------------------------------------
local spinAccum = 0
local spinClock = 0
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
	local tab = win.tab()
	if tab == "mine" then
		local builds = 0
		for cid, c in petCards do
			if isVisibleIn(c.button, grid) then
				if not c.model and builds < MAX_BUILDS_PER_STEP then
					builds += 1
					ensureCardModel(c)
				end
				if c.model and cid == selectedId then
					c.phase += step * SPIN_SPEED
					UIKit.orbit(c.camera, c.center, c.dist, c.phase, 0.25)
				end
			end
		end
		if detailModel then
			UIKit.orbit(detailCam, detailCenter, detailDist, spinClock * SPIN_SPEED * 1.3, 0.2)
		end
	elseif tab == "cocoons" then
		for i, c in cocoonCards do
			if c.model then
				UIKit.orbit(c.camera, c.center, c.dist, spinClock * 0.6 + i, 0.2)
			end
		end
	end
end

----------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------
local spinConn: RBXScriptConnection? = nil

local function refresh()
	local d = ClientState.get()
	if not d or not win.isOpen() then
		return
	end
	shardsLabel.Text = Format.short(d.Shards)
	local tab = win.tab()
	if tab == "mine" then
		refreshMine(d)
	elseif tab == "cocoons" then
		refreshCocoons(d)
	end
	local canHatch = false
	if #d.Pets < Pets.MaxInventory then
		for _, id in Pets.CocoonOrder do
			local c = Pets.Cocoons[id]
			if d.Zone >= c.Zone and d.Shards >= c.Cost then
				canHatch = true
				break
			end
		end
	end
	win.setTabBadge("cocoons", canHatch)
	win.setTabBadge("mine", #d.Equipped < math.min(slots(d), #d.Pets))
end

function PetsUI.start()
	if win then
		return
	end
	win = UIKit.window({
		Name = "Pets",
		Title = "Питомцы",
		Icon = "🐾",
		Width = 880,
		Height = 560,
		Accent = Color3.fromRGB(200, 70, 150),
		Tabs = {
			{ Id = "mine", Text = "🐾 Мои" },
			{ Id = "cocoons", Text = "🥚 Коконы" },
		},
		OnOpen = function()
			refresh()
			if not spinConn then
				spinConn = RunService.Heartbeat:Connect(spinStep)
			end
			ClientState.WindowOpened:Fire("Pets")
		end,
		OnClose = function()
			local c = spinConn
			spinConn = nil
			if c then
				c:Disconnect()
			end
			ClientState.WindowClosed:Fire("Pets")
		end,
		OnTab = function()
			refresh()
		end,
	})
	shardsLabel = UIKit.headerCounter(win, "💎", Theme.Shard)
	buildMine(win.Pages.mine)
	buildCocoons(win.Pages.cocoons)
	buildHatch()

	ClientState.Changed:Connect(refresh)
	ClientState.OpenWindow:Connect(function(name: string)
		local base, tab = UIKit.parseWindowName(name)
		if base == "Pets" then
			win.open(tab)
		elseif base == "Hatchery" or base == "Cocoons" then
			win.open("cocoons")
		end
	end)
end

function PetsUI.open(tab: string?)
	if win then
		win.open(tab)
	end
end

return PetsUI
