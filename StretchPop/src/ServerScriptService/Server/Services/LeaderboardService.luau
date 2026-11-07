--!strict
-- STRETCH-POP · LeaderboardService (сервер)
-- Три табло на Подиуме чемпионов: ТОП СКОРОСТИ, ТОП КОМБО, ТОП РЕБЁРТОВ.
--
-- Источник данных — подтверждённые сервером рекорды профиля (скорость засчитывается только
-- из проверенных пробитий и ударов в гонг, поэтому накрутить её нельзя).
--   • «Живые» значения игроков на сервере обновляют табло почти сразу (дебаунс 2 с).
--   • Глобальный рейтинг — OrderedDataStore: запись max(старое, новое) раз в 90 с и при выходе,
--     чтение топ-10 раз в 60 с. Все вызовы в pcall; при недоступности DataStore (Studio без
--     доступа к API, сбой сервиса) табло работает в режиме «рейтинг сервера».
-- Топ-3 по скорости стоят на подиуме: табличка с ником и рекордом + статуя аватара
-- (Players:CreateHumanoidModelFromUserId, если доступно).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local PlayerDataService = require(Server.Services.PlayerDataService)
local LobbyBuilder = require(Server.Level.LobbyBuilder)

type BoardKind = LobbyBuilder.BoardKind

export type Entry = {
	UserId: number,
	Name: string,
	Value: number,
}

type RowGui = {
	Frame: Frame,
	Rank: TextLabel,
	Badge: Frame,
	Name: TextLabel,
	Value: TextLabel,
}

type Board = {
	Kind: BoardKind,
	Title: string,
	Unit: string,
	Accent: Color3,
	StoreName: string,
	Store: OrderedDataStore?,
	Global: { Entry },
	Written: { [number]: number },
	Rows: { RowGui },
	Footer: TextLabel?,
	Top: { Entry },
}

local BOARD_SIZE = 10
local READ_INTERVAL = 60
local WRITE_INTERVAL = 90
local LIVE_DEBOUNCE = 2
local STORE_VERSION = "v1"

local RGB = Color3.fromRGB
local INK = RGB(28, 32, 56)
local CREAM = RGB(248, 250, 255)
local CARD = RGB(232, 240, 255)
local UNDERLAY = RGB(195, 206, 230)
local MEDALS = { RGB(255, 196, 40), RGB(206, 218, 236), RGB(214, 132, 72) }
local FONT = Enum.Font.FredokaOne

local LeaderboardService = {}

local boards: { Board } = {}
local boardByKind: { [BoardKind]: Board } = {}
local nameCache: { [number]: string } = {}
local lobby: LobbyBuilder.LobbyHandles? = nil
local podiumFolder: Folder? = nil
local podiumUsers: { number } = {}
local podiumGeneration = 0
local liveDue = 0
local initialized = false

local function valueOf(kind: BoardKind, profile: Types.PlayerProfile): number
	if kind == "Speed" then
		return math.floor(profile.Records.TopSpeed + 0.5)
	elseif kind == "Combo" then
		return math.floor(profile.Records.LongestCombo)
	end
	return math.floor(profile.TotalRebirths)
end

local function formatValue(board: Board, value: number): string
	return string.format("%d %s", value, board.Unit)
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName ~= "" and player.DisplayName or player.Name
		return nameCache[userId]
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and typeof(result) == "string" then result else "Игрок " .. userId
	nameCache[userId] = name
	return name
end

-- ── Отрисовка табло ─────────────────────────────────────────────────────────

local function corner(parent: Instance, radius: number)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, radius)
	ui.Parent = parent
end

local function stroke(parent: Instance, thickness: number, color: Color3)
	local ui = Instance.new("UIStroke")
	ui.Thickness = thickness
	ui.Color = color
	ui.LineJoinMode = Enum.LineJoinMode.Round
	ui.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ui.Parent = parent
end

local function textStroke(label: TextLabel, thickness: number)
	local ui = Instance.new("UIStroke")
	ui.Thickness = thickness
	ui.Color = INK
	ui.LineJoinMode = Enum.LineJoinMode.Round
	ui.Parent = label
end

local function label(parent: Instance, name: string, text: string, color: Color3, alignment: Enum.TextXAlignment): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Font = FONT
	item.Text = text
	item.TextColor3 = color
	item.TextScaled = true
	item.TextXAlignment = alignment
	item.Parent = parent
	return item
end

local function buildBoardGui(board: Board, screen: BasePart)
	local existing = screen:FindFirstChild("LeaderboardGui")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 26
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.Parent = screen

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = CREAM
	body.Size = UDim2.fromScale(1, 1)
	body.BorderSizePixel = 0
	body.Parent = gui

	-- шапка: цветная плашка с подложкой, наклон −1°
	local headerShadow = Instance.new("Frame")
	headerShadow.Name = "HeaderShadow"
	headerShadow.BackgroundColor3 = UNDERLAY
	headerShadow.Position = UDim2.new(0.04, 0, 0.025, 8)
	headerShadow.Size = UDim2.fromScale(0.92, 0.13)
	headerShadow.Rotation = -1
	headerShadow.Parent = body
	corner(headerShadow, 18)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = board.Accent
	header.Position = UDim2.fromScale(0.04, 0.025)
	header.Size = UDim2.fromScale(0.92, 0.13)
	header.Rotation = -1
	header.Parent = body
	corner(header, 18)
	stroke(header, 5, INK)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.6
	shine.Position = UDim2.fromScale(0.05, 0.12)
	shine.Size = UDim2.fromScale(0.9, 0.18)
	shine.Parent = header
	corner(shine, 8)
	local title = label(header, "Title", board.Title, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	title.Size = UDim2.fromScale(0.92, 0.78)
	title.Position = UDim2.fromScale(0.04, 0.11)
	textStroke(title, 4)

	local rows: { RowGui } = {}
	for rank = 1, BOARD_SIZE do
		local top = 0.185 + (rank - 1) * 0.074
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. rank
		frame.BackgroundColor3 = if rank <= 3 then MEDALS[rank]:Lerp(CARD, 0.72) else CARD
		frame.Position = UDim2.fromScale(0.05, top)
		frame.Size = UDim2.fromScale(0.9, 0.064)
		frame.Parent = body
		corner(frame, 12)
		stroke(frame, 3, INK)

		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.BackgroundColor3 = if rank <= 3 then MEDALS[rank] else UNDERLAY
		badge.Position = UDim2.fromScale(0.015, 0.1)
		badge.Size = UDim2.fromScale(0.11, 0.8)
		badge.Parent = frame
		corner(badge, 100)
		stroke(badge, 3, INK)
		local rankLabel = label(badge, "Rank", tostring(rank), Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
		rankLabel.Size = UDim2.fromScale(1, 1)
		textStroke(rankLabel, 2.5)

		local nameLabel = label(frame, "Name", "—", INK, Enum.TextXAlignment.Left)
		nameLabel.Position = UDim2.fromScale(0.16, 0.12)
		nameLabel.Size = UDim2.fromScale(0.5, 0.76)
		local valueLabel = label(frame, "Value", "", board.Accent:Lerp(INK, 0.35), Enum.TextXAlignment.Right)
		valueLabel.Position = UDim2.fromScale(0.64, 0.12)
		valueLabel.Size = UDim2.fromScale(0.33, 0.76)
		table.insert(rows, { Frame = frame, Rank = rankLabel, Badge = badge, Name = nameLabel, Value = valueLabel })
	end
	board.Rows = rows

	local footer = label(body, "Footer", "", INK:Lerp(CREAM, 0.4), Enum.TextXAlignment.Center)
	footer.Position = UDim2.fromScale(0.05, 0.93)
	footer.Size = UDim2.fromScale(0.9, 0.05)
	board.Footer = footer
end

local function renderBoard(board: Board)
	for index, row in board.Rows do
		local entry = board.Top[index]
		row.Name.Text = if entry then entry.Name else "—"
		row.Value.Text = if entry then formatValue(board, entry.Value) else ""
		row.Frame.BackgroundTransparency = if entry then 0 else 0.35
	end
	local footer = board.Footer
	if footer then
		footer.Text = if board.Store then "ГЛОБАЛЬНЫЙ РЕЙТИНГ • обновление раз в минуту" else "РЕЙТИНГ СЕРВЕРА • глобальный недоступен"
	end
end

-- ── Подиум ──────────────────────────────────────────────────────────────────

local function makeStatue(userId: number, top: CFrame, parent: Instance, generation: number)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		return
	end
	if generation ~= podiumGeneration then
		result:Destroy() -- состав подиума успел смениться, пока грузился аватар
		return
	end
	local statue = result
	statue.Name = "Statue_" .. userId
	for _, descendant in statue:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	pcall(function()
		statue:ScaleTo(1.35)
	end)
	statue:PivotTo(top)
	-- ставим ступнями на ступень: сдвиг по нижней грани габарита
	local boxCFrame, boxSize = statue:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y * 0.5
	statue:PivotTo(top + Vector3.new(0, top.Position.Y - bottom, 0))
	statue.Parent = parent
end

local function makeNameplate(place: number, entry: Entry, top: CFrame, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "Nameplate" .. place
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = top + Vector3.new(0, 11, 0)
	anchor.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Plate"
	billboard.Size = UDim2.fromScale(11, 3.6)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	billboard.Parent = anchor
	local plate = Instance.new("Frame")
	plate.BackgroundColor3 = MEDALS[place] or CARD
	plate.Size = UDim2.fromScale(1, 1)
	plate.Parent = billboard
	corner(plate, 14)
	stroke(plate, 3, INK)
	local nameLabel = label(plate, "Name", string.format("#%d  %s", place, entry.Name), Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	nameLabel.Size = UDim2.fromScale(0.92, 0.56)
	nameLabel.Position = UDim2.fromScale(0.04, 0.05)
	textStroke(nameLabel, 2.5)
	local valueLabel = label(plate, "Value", string.format("%d st/s", entry.Value), INK, Enum.TextXAlignment.Center)
	valueLabel.Size = UDim2.fromScale(0.92, 0.36)
	valueLabel.Position = UDim2.fromScale(0.04, 0.6)
end

local function refreshPodium()
	local handles = lobby
	local folder = podiumFolder
	local speedBoard = boardByKind.Speed
	if handles == nil or folder == nil or speedBoard == nil then
		return
	end
	local users: { number } = {}
	for index = 1, 3 do
		local entry = speedBoard.Top[index]
		if entry then
			table.insert(users, entry.UserId)
		end
	end
	local same = #users == #podiumUsers
	if same then
		for index, userId in users do
			if podiumUsers[index] ~= userId then
				same = false
			end
		end
	end
	-- таблички (значения) обновляем всегда, статуи пересоздаём, только если сменился состав
	if not same then
		podiumGeneration += 1
	end
	for _, child in folder:GetChildren() do
		if child.Name:sub(1, 9) == "Nameplate" or not same then
			child:Destroy()
		end
	end
	for place = 1, 3 do
		local entry = speedBoard.Top[place]
		local top = handles.PodiumTops[place]
		if entry and top then
			makeNameplate(place, entry, top, folder)
			if not same then
				task.spawn(makeStatue, entry.UserId, top, folder, podiumGeneration)
			end
		end
	end
	podiumUsers = users
end

-- ── Данные ──────────────────────────────────────────────────────────────────

local function liveEntries(kind: BoardKind): { [number]: Entry }
	local result: { [number]: Entry } = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService.Get(player)
		if profile then
			local value = valueOf(kind, profile)
			if value > 0 then
				result[player.UserId] = {
					UserId = player.UserId,
					Name = player.DisplayName ~= "" and player.DisplayName or player.Name,
					Value = value,
				}
			end
		end
	end
	return result
end

local function rebuildTop(board: Board)
	local merged: { [number]: Entry } = {}
	for _, entry in board.Global do
		merged[entry.UserId] = entry
	end
	for userId, entry in liveEntries(board.Kind) do
		local existing = merged[userId]
		if existing == nil or entry.Value >= existing.Value then
			merged[userId] = entry
		end
	end
	local list: { Entry } = {}
	for _, entry in merged do
		table.insert(list, entry)
	end
	table.sort(list, function(a: Entry, b: Entry): boolean
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	local top: { Entry } = {}
	for index = 1, math.min(BOARD_SIZE, #list) do
		top[index] = list[index]
	end
	board.Top = top
end

local function renderAll()
	for _, board in boards do
		rebuildTop(board)
		renderBoard(board)
	end
	refreshPodium()
end

local function readGlobal(board: Board)
	local store = board.Store
	if store == nil then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, BOARD_SIZE)
	end)
	if not ok or typeof(pages) ~= "Instance" then
		return
	end
	local okPage, page = pcall(function()
		return (pages :: DataStorePages):GetCurrentPage()
	end)
	if not okPage or typeof(page) ~= "table" then
		return
	end
	local entries: { Entry } = {}
	for _, item in page :: { any } do
		local userId = tonumber(item.key)
		local value = tonumber(item.value)
		if userId and value and userId > 0 then
			table.insert(entries, { UserId = userId, Name = nameFor(userId), Value = math.floor(value) })
		end
	end
	board.Global = entries
end

local function writePlayer(player: Player)
	local profile = PlayerDataService.Get(player)
	if profile == nil then
		return
	end
	for _, board in boards do
		local store = board.Store
		local value = valueOf(board.Kind, profile)
		if store and value > (board.Written[player.UserId] or 0) then
			local ok = pcall(function()
				store:UpdateAsync(tostring(player.UserId), function(old: unknown): number
					local previous = if typeof(old) == "number" then old else 0
					return math.max(previous, value)
				end)
			end)
			if ok then
				board.Written[player.UserId] = value
			end
		end
	end
end

local function openStores()
	if PlayerDataService.IsOffline() then
		return
	end
	for _, board in boards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.StoreName)
		end)
		if ok and typeof(store) == "Instance" and store:IsA("OrderedDataStore") then
			board.Store = store
		end
	end
end

-- ── Публичное API ───────────────────────────────────────────────────────────

function LeaderboardService.GetTop(kind: BoardKind): { Entry }
	local board = boardByKind[kind]
	return if board then table.clone(board.Top) else {}
end

-- Немедленно перечитать живые значения (тесты/события сервера)
function LeaderboardService.RefreshLive()
	renderAll()
end

function LeaderboardService.Init(handles: LobbyBuilder.LobbyHandles)
	if initialized then
		return
	end
	initialized = true
	lobby = handles

	local definitions: { { Kind: BoardKind, Title: string, Unit: string, Accent: Color3, Store: string } } = {
		{ Kind = "Speed", Title = "ТОП СКОРОСТИ", Unit = "st/s", Accent = RGB(66, 136, 255), Store = "StretchPop_TopSpeed_" .. STORE_VERSION },
		{ Kind = "Combo", Title = "ТОП КОМБО", Unit = "x", Accent = RGB(255, 90, 150), Store = "StretchPop_TopCombo_" .. STORE_VERSION },
		{ Kind = "Rebirths", Title = "ТОП РЕБЁРТОВ", Unit = "★", Accent = RGB(255, 176, 30), Store = "StretchPop_Rebirths_" .. STORE_VERSION },
	}
	for _, definition in definitions do
		local board: Board = {
			Kind = definition.Kind,
			Title = definition.Title,
			Unit = definition.Unit,
			Accent = definition.Accent,
			StoreName = definition.Store,
			Store = nil,
			Global = {},
			Written = {},
			Rows = {},
			Footer = nil,
			Top = {},
		}
		local screen = handles.Boards[definition.Kind]
		if screen then
			buildBoardGui(board, screen)
		end
		table.insert(boards, board)
		boardByKind[definition.Kind] = board
	end

	local folder = Instance.new("Folder")
	folder.Name = "PodiumChampions"
	folder.Parent = handles.Model
	podiumFolder = folder

	openStores()
	renderAll()

	PlayerDataService.ProfileChanged:Connect(function()
		liveDue = os.clock() + LIVE_DEBOUNCE
	end)
	PlayerDataService.ProfileLoaded:Connect(function()
		liveDue = os.clock() + LIVE_DEBOUNCE
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(writePlayer, player)
		liveDue = os.clock() + LIVE_DEBOUNCE
	end)

	-- живое обновление (дешёвое, без DataStore)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if liveDue > 0 and os.clock() >= liveDue then
				liveDue = 0
				renderAll()
			end
		end
	end)

	-- глобальный цикл: запись рекордов и чтение топ-10
	task.spawn(function()
		local nextWrite = os.clock() + WRITE_INTERVAL
		while true do
			for _, board in boards do
				readGlobal(board)
			end
			renderAll()
			task.wait(READ_INTERVAL)
			if os.clock() >= nextWrite then
				nextWrite = os.clock() + WRITE_INTERVAL
				for _, player in Players:GetPlayers() do
					writePlayer(player)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			writePlayer(player)
		end
	end)
end

return LeaderboardService
