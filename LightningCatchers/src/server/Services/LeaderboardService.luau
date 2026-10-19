--!strict
-- Таблицы и табло:
--  * leaderstats (список игроков Roblox): NumberValue «Вольты» и IntValue «Перезапуски» (обновление с троттлингом);
--  * глобальная таблица лучших по TotalVolts (OrderedDataStore): запись раз в WRITE_EVERY с на игрока,
--    чтение топа раз в READ_EVERY с — всё в pcall с повторами; без доступа к API (Studio) — топ этого сервера;
--    из Studio и тестовых игроков (UserId ≤ 0) в глобальную таблицу не пишем никогда;
--  * табло в хабе (Map.Markers.Board_*: SurfaceGui "Gui" → Frame "Content"): «Лучшие ловцы»,
--    «Зал Славы» (последние поймавшие Радужную/Чёрную молнию на сервере), «Прогноз» (обратный отсчёт событий);
--  * FriendCount — сколько друзей игрока на сервере (Player:IsFriendsWithAsync в pcall, кэш по паре;
--    неудачные проверки повторяются в фоне раз в Config.Server.FriendRetryEvery с).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)

local LeaderboardService = {}

local STORE_NAME = "TotalVolts_v1"
local WRITE_EVERY = 180 -- запись игрока в глобальную таблицу (с)
local READ_EVERY = 180 -- чтение топа (с)
local LOCAL_EVERY = 10 -- топ сервера (когда глобальной таблицы нет)
local WRITE_TICK = 10
local TOP_N = 10
local HALL_SIZE = 8
local STATS_THROTTLE = 0.5
local RETRIES = 3
local FRIEND_RETRIES = 3
local MAX_SCORE = 9e18 -- OrderedDataStore хранит 64-битные целые
local NAME_FALLBACK = "Ловец"

local BOARD_FONT = Font.fromEnum(Enum.Font.BuilderSansBold)
local BOARD_FONT_HEAVY = Font.fromEnum(Enum.Font.BuilderSansExtraBold)
local WHITE = Color3.new(1, 1, 1)
local DIM = Color3.fromRGB(176, 186, 220)
local STROKE = Color3.fromRGB(10, 12, 26)
local MEDALS = { Color3.fromRGB(255, 214, 80), Color3.fromRGB(220, 226, 240), Color3.fromRGB(235, 160, 100) }

type Entry = { UserId: number, Name: string, Score: number }
type Board = { Gui: SurfaceGui, Content: Frame, Rows: { TextLabel }, Footer: TextLabel? }

local store: OrderedDataStore? = nil
local storeDisabled = false
local globalTop: { Entry }? = nil
local nameCache: { [number]: string } = {}
local lastWritten: { [Player]: number } = {}
local lastWriteAt: { [Player]: number } = {}
local statsPending: { [Player]: boolean } = {}
local friendCache: { [string]: boolean } = {}
-- пары, которые не удалось проверить (сбой API): повторяем в фоне
type PendingPair = { A: Player, B: Player, Tries: number }
local friendPending: { [string]: PendingPair } = {}
local hall: { { Name: string, Kind: string } } = {}

local leadersBoard: Board? = nil
local hallBoard: Board? = nil
local forecastBoard: Board? = nil

----------------------------------------------------------------------
-- DataStore
----------------------------------------------------------------------

local function isFatal(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "must publish", 1, true) ~= nil
		or string.find(lower, "not allowed", 1, true) ~= nil
end

local function getStore(): OrderedDataStore?
	if storeDisabled then
		return nil
	end
	if store then
		return store
	end
	local ok, result = pcall(function(): OrderedDataStore
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok and result then
		store = result
		return result
	end
	storeDisabled = true
	warn("[LeaderboardService] OrderedDataStore недоступен, глобальной таблицы не будет: " .. tostring(result))
	return nil
end

-- Вызов DataStore с повторами. false — не получилось (или доступа нет совсем).
local function withRetries(label: string, fn: () -> ()): boolean
	for attempt = 1, RETRIES do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		local message = tostring(err)
		if isFatal(message) then
			if not storeDisabled then
				storeDisabled = true
				warn("[LeaderboardService] Глобальная таблица выключена (нет доступа к DataStore): " .. message)
			end
			return false
		end
		if attempt < RETRIES then
			task.wait(2 ^ attempt)
		else
			warn(string.format("[LeaderboardService] DataStore %s не удалось: %s", label, message))
		end
	end
	return false
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.Name
		return player.Name
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and typeof(result) == "string" then
		nameCache[userId] = result
		return result
	end
	return NAME_FALLBACK
end

-- Писать ли игрока в глобальную таблицу: только настоящие игроки на настоящем сервере
local function canWriteGlobal(player: Player): boolean
	return not RunService:IsStudio() and player.UserId > 0 and DataService.isPersistent(player)
end

local function writeScore(player: Player)
	local d = DataService.get(player)
	if not d or not canWriteGlobal(player) then
		return -- Studio, тестовый игрок или без сохранений — в таблицу не пишем
	end
	local score = math.clamp(math.floor(d.TotalVolts), 0, MAX_SCORE)
	if lastWritten[player] == score then
		return
	end
	local ds = getStore()
	if not ds then
		return
	end
	lastWriteAt[player] = os.clock()
	local key = tostring(player.UserId)
	if withRetries("SetAsync", function()
		ds:SetAsync(key, score)
	end) then
		lastWritten[player] = score
	end
end

local function readTop()
	local ds = getStore()
	if not ds then
		return
	end
	local entries: { Entry } = {}
	local ok = withRetries("GetSortedAsync", function()
		local pages = ds:GetSortedAsync(false, TOP_N)
		table.clear(entries)
		for _, item in pages:GetCurrentPage() do
			local id = tonumber(item.key)
			local value = item.value
			if id and id > 0 and typeof(value) == "number" then
				table.insert(entries, { UserId = id, Name = "", Score = value })
			end
		end
	end)
	if not ok then
		return
	end
	for _, e in entries do
		e.Name = nameOf(e.UserId)
	end
	globalTop = entries
end

-- Есть ли на сервере игрок с настоящими сохранениями (иначе DataStore недоступен — Studio без API)
local function anyPersistent(): boolean
	for _, p in Players:GetPlayers() do
		if DataService.isPersistent(p) then
			return true
		end
	end
	return false
end

-- Топ этого сервера (если глобальной таблицы нет)
local function localTop(): { Entry }
	local list: { Entry } = {}
	for _, p in Players:GetPlayers() do
		local d = DataService.get(p)
		if d then
			table.insert(list, { UserId = p.UserId, Name = p.Name, Score = d.TotalVolts })
		end
	end
	table.sort(list, function(a: Entry, b: Entry): boolean
		return a.Score > b.Score
	end)
	while #list > TOP_N do
		table.remove(list)
	end
	return list
end

----------------------------------------------------------------------
-- Табло
----------------------------------------------------------------------

local function markers(): Instance?
	local map = Workspace:FindFirstChild("Map")
	return if map then map:FindFirstChild("Markers") else nil
end

local function newText(parent: Instance, name: string, pos: UDim2, size: UDim2, align: Enum.TextXAlignment, font: Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.FontFace = font
	l.Text = ""
	l.TextColor3 = WHITE
	l.TextScaled = true
	l.TextXAlignment = align
	l.TextStrokeColor3 = STROKE
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = l
	return l
end

-- Найти (или создать) SurfaceGui табло и разложить строки: cols × rows (+ строка-подпись внизу)
local function setupBoard(name: string, title: string, cols: number, rows: number, footer: boolean): Board?
	local folder = markers()
	local marker = if folder then folder:FindFirstChild(name) else nil
	if not marker or not marker:IsA("BasePart") then
		return nil
	end
	local guiInst = marker:FindFirstChild("Gui")
	local gui: SurfaceGui
	if guiInst and guiInst:IsA("SurfaceGui") then
		gui = guiInst
	else
		-- на карте нет готового интерфейса — свой SurfaceGui на передней грани метки
		gui = Instance.new("SurfaceGui")
		gui.Name = "Gui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.MaxDistance = 250
		gui.Parent = marker
	end
	if not gui:FindFirstChild("Title") then
		local t = newText(gui, "Title", UDim2.fromScale(0, 0.01), UDim2.fromScale(1, 0.17), Enum.TextXAlignment.Center, BOARD_FONT_HEAVY)
		t.Text = title
	end
	local contentInst = gui:FindFirstChild("Content")
	local content: Frame
	if contentInst and contentInst:IsA("Frame") then
		content = contentInst
	else
		content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.Size = UDim2.fromScale(0.94, 0.78)
		content.Position = UDim2.fromScale(0.03, 0.2)
		content.Parent = gui
	end
	for _, c in content:GetChildren() do
		c:Destroy()
	end
	local listH = if footer then 0.86 else 1
	local list: { TextLabel } = {}
	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local l = newText(
				content,
				string.format("Row_%d", col * rows + row + 1),
				UDim2.fromScale(col / cols, row * listH / rows),
				UDim2.fromScale(1 / cols, listH / rows),
				Enum.TextXAlignment.Left,
				BOARD_FONT
			)
			table.insert(list, l)
		end
	end
	local foot: TextLabel? = nil
	if footer then
		local f = newText(content, "Footer", UDim2.fromScale(0, listH), UDim2.fromScale(1, 1 - listH), Enum.TextXAlignment.Center, BOARD_FONT)
		f.TextColor3 = DIM
		foot = f
	end
	return { Gui = gui, Content = content, Rows = list, Footer = foot }
end

local function setRow(l: TextLabel, text: string, color: Color3?)
	if l.Text ~= text then
		l.Text = text
	end
	local c = color or WHITE
	if l.TextColor3 ~= c then
		l.TextColor3 = c
	end
end

local function renderLeaders()
	local board = leadersBoard
	if not board then
		return
	end
	local top = globalTop
	local isGlobal = top ~= nil and #top > 0
	local list: { Entry } = if top and isGlobal then top else localTop()
	for i, l in board.Rows do
		local e = list[i]
		if e then
			setRow(l, string.format("%d. %s — %s ⚡", i, e.Name, Format.short(e.Score)), MEDALS[i])
		else
			setRow(l, if i == 1 then "Пока пусто — лови молнии!" else "", DIM)
		end
	end
	local foot = board.Footer
	if foot then
		setRow(foot, if isGlobal then "лучшие во всей игре" else "лучшие на этом сервере", DIM)
	end
end

local function renderHall()
	local board = hallBoard
	if not board then
		return
	end
	for i, l in board.Rows do
		local e = hall[i]
		if e then
			local icon = if e.Kind == "perun" then "☠" else "🌈"
			setRow(l, icon .. " " .. e.Name, if e.Kind == "perun" then Config.Colors.gold.Color else Config.Colors.rainbow.Color)
		else
			setRow(l, if i == 1 and #hall == 0 then "Поймай Радужную молнию!" else "", DIM)
		end
	end
	local foot = board.Footer
	if foot then
		setRow(foot, "ловцы Радужной и Чёрной молнии на этом сервере", DIM)
	end
end

local FORECAST = {
	{ Event = "supercell", Attr = "NextSupercell", Name = "⚡ Суперячейка", Color = Color3.fromRGB(90, 230, 120) },
	{ Event = "ball", Attr = "NextBall", Name = "🔮 Шаровая молния", Color = Color3.fromRGB(255, 170, 80) },
	{ Event = "rainbow", Attr = "NextRainbow", Name = "🌈 Радужная молния", Color = Color3.fromRGB(255, 140, 220) },
}

local function attrNumber(gs: Instance, name: string): number
	local v = gs:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

local function renderForecast()
	local board = forecastBoard
	local gs = ReplicatedStorage:FindFirstChild("GameState")
	if not board or not gs then
		return
	end
	local t = Workspace:GetServerTimeNow()
	local ev = gs:GetAttribute("Event")
	for i, f in FORECAST do
		local l = board.Rows[i]
		if l then
			if ev == f.Event then
				local ends = attrNumber(gs, "EventEnds")
				setRow(l, string.format("%s — СЕЙЧАС! %s", f.Name, if ends > t then Format.time(ends - t) else ""), f.Color)
			else
				local at = attrNumber(gs, f.Attr)
				setRow(l, string.format("%s — через %s", f.Name, if at > t then Format.time(at - t) else "…"), WHITE)
			end
		end
	end
	local cityRow = board.Rows[#FORECAST + 1]
	if cityRow then
		local boost = attrNumber(gs, "CityBoostUntil")
		if boost > t then
			setRow(cityRow, "🏙 Электроград сияет! " .. Format.time(boost - t), Color3.fromRGB(255, 220, 70))
		else
			setRow(cityRow, string.format("🏙 Электроград — %d/%d", math.floor(attrNumber(gs, "CityPoints")), math.floor(attrNumber(gs, "CityTarget"))), DIM)
		end
	end
end

----------------------------------------------------------------------
-- leaderstats
----------------------------------------------------------------------

local function applyStats(player: Player)
	statsPending[player] = nil
	local d = DataService.get(player)
	if not d or player.Parent ~= Players then
		return
	end
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "leaderstats"
		local volts = Instance.new("NumberValue")
		volts.Name = "Вольты"
		volts.Parent = f
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Перезапуски"
		rebirths.Parent = f
		f.Parent = player
		folder = f
	end
	local volts = (folder :: Instance):FindFirstChild("Вольты")
	if volts and volts:IsA("NumberValue") then
		local v = math.floor(d.Volts)
		if volts.Value ~= v then
			volts.Value = v
		end
	end
	local rebirths = (folder :: Instance):FindFirstChild("Перезапуски")
	if rebirths and rebirths:IsA("IntValue") and rebirths.Value ~= d.Rebirths then
		rebirths.Value = d.Rebirths
	end
end

local function scheduleStats(player: Player)
	if statsPending[player] then
		return
	end
	statsPending[player] = true
	task.delay(STATS_THROTTLE, applyStats, player)
end

----------------------------------------------------------------------
-- Друзья на сервере
----------------------------------------------------------------------

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

-- Один запрос «друзья ли»: true/false или nil (не удалось)
local function askFriends(a: Player, b: Player): boolean?
	local ok, result = pcall(function(): boolean
		return a:IsFriendsWithAsync(b.UserId)
	end)
	if ok then
		return result == true
	end
	return nil
end

local function checkPair(a: Player, b: Player)
	local key = pairKey(a.UserId, b.UserId)
	if friendCache[key] ~= nil then
		return
	end
	for attempt = 1, FRIEND_RETRIES do
		if a.Parent ~= Players or b.Parent ~= Players then
			return
		end
		local result = askFriends(a, b)
		if result ~= nil then
			friendCache[key] = result
			friendPending[key] = nil
			return
		end
		task.wait(attempt)
	end
	-- API не отвечает (часто при старте сервера): проверим ещё раз позже, в фоне
	if not friendPending[key] then
		friendPending[key] = { A = a, B = b, Tries = 0 }
	end
end

local function recountFriends(leaving: Player?)
	local list = Players:GetPlayers()
	for _, p in list do
		if p ~= leaving then
			local n = 0
			for _, q in list do
				if q ~= p and q ~= leaving and friendCache[pairKey(p.UserId, q.UserId)] then
					n += 1
				end
			end
			if p:GetAttribute(Net.PlayerAttrs.FriendCount) ~= n then
				p:SetAttribute(Net.PlayerAttrs.FriendCount, n)
			end
		end
	end
end

-- Фоновый повтор неудачных проверок дружбы
local function retryFriends()
	local changed = false
	-- копия: запросы ждут ответа, а новые пары могут добавиться в это время
	for key, pair in table.clone(friendPending) do
		if pair.A.Parent ~= Players or pair.B.Parent ~= Players or friendCache[key] ~= nil then
			friendPending[key] = nil
		else
			local result = askFriends(pair.A, pair.B)
			pair.Tries += 1
			if result ~= nil then
				friendCache[key] = result
				friendPending[key] = nil
				changed = changed or result
			elseif pair.Tries >= Config.Server.FriendLateTries then
				friendPending[key] = nil -- сдаёмся: без бонуса за эту пару в этой сессии
			end
		end
	end
	if changed then
		recountFriends(nil)
	end
end

local function onJoin(player: Player)
	if player:GetAttribute(Net.PlayerAttrs.FriendCount) == nil then
		player:SetAttribute(Net.PlayerAttrs.FriendCount, 0)
	end
	task.spawn(function()
		for _, other in Players:GetPlayers() do
			if other ~= player then
				checkPair(player, other)
			end
		end
		recountFriends(nil)
	end)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Добавить имя в Зал Славы (kind: "rainbow" | "perun"); новые — сверху
function LeaderboardService.addHall(name: string, kind: string)
	table.insert(hall, 1, { Name = name, Kind = kind })
	while #hall > HALL_SIZE do
		table.remove(hall)
	end
	renderHall()
end

function LeaderboardService.hall(): { { Name: string, Kind: string } }
	return table.clone(hall)
end

----------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------

function LeaderboardService.start()
	DataService.Loaded:Connect(function(player)
		applyStats(player)
	end)
	DataService.Changed:Connect(scheduleStats)
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		statsPending[player] = nil
		recountFriends(player)
		task.spawn(function()
			writeScore(player) -- последний результат (данные ещё в памяти DataService, пока идёт сохранение)
			lastWritten[player] = nil
			lastWriteAt[player] = nil
		end)
	end)
	for _, player in Players:GetPlayers() do
		onJoin(player)
		if DataService.get(player) then
			applyStats(player)
		end
	end

	EventService.HallEntry:Connect(function(player, kind)
		LeaderboardService.addHall(player.DisplayName, kind)
	end)

	-- табло (если на карте есть метки)
	leadersBoard = setupBoard("Board_Leaders", "🏆 Лучшие ловцы", 2, TOP_N // 2, true)
	hallBoard = setupBoard("Board_Hall", "🌈 Зал Славы", 2, HALL_SIZE // 2, true)
	forecastBoard = setupBoard("Board_Forecast", "Прогноз погоды", 1, #FORECAST + 1, false)
	renderLeaders()
	renderHall()

	-- прогноз: раз в секунду (меняется только текст)
	task.spawn(function()
		while true do
			local ok, err = pcall(renderForecast)
			if not ok then
				warn("[LeaderboardService] прогноз: " .. tostring(err))
			end
			task.wait(1)
		end
	end)

	-- повтор неудачных проверок дружбы
	task.spawn(function()
		while true do
			task.wait(Config.Server.FriendRetryEvery)
			local ok, err = pcall(retryFriends)
			if not ok then
				warn("[LeaderboardService] друзья: " .. tostring(err))
			end
		end
	end)

	-- запись игроков в глобальную таблицу (каждый не чаще раза в WRITE_EVERY с)
	task.spawn(function()
		while true do
			task.wait(WRITE_TICK)
			for _, player in Players:GetPlayers() do
				local last = lastWriteAt[player]
				if (last == nil or os.clock() - last >= WRITE_EVERY) and canWriteGlobal(player) then
					writeScore(player)
					lastWriteAt[player] = os.clock()
				end
			end
		end
	end)

	-- чтение топа
	task.spawn(function()
		local lastRead = -math.huge
		while true do
			if os.clock() - lastRead >= READ_EVERY and not storeDisabled and anyPersistent() then
				lastRead = os.clock()
				readTop()
			end
			local ok, err = pcall(renderLeaders)
			if not ok then
				warn("[LeaderboardService] таблица: " .. tostring(err))
			end
			task.wait(LOCAL_EVERY)
		end
	end)
end

return LeaderboardService
