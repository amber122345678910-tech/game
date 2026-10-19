--!strict
-- Удержание:
--  * ежедневный календарь (Config.DailyRewards): забрать можно раз в день (день — Quests.dayNumber, UTC);
--    серия растёт, если пропущено не больше одного дня («заморозка»), после 7-го дня — снова с 1-го;
--  * 3 задания в день (Quests.forDay): прогресс от поимок, сдач, вылуплений, собранных осколков; награда —
--    осколки + минуты дохода; выполненные, но не забранные к смене дня награды зачисляются сами;
--    общие кольца событий не идут в задания на цвет (фиолетовые/золотые), сдача почти пустой банки — в «Сдай банку»;
--  * коды (Config.Codes): регистр и пробелы не важны (кириллица переводится в верхний регистр через Loc.upper —
--    string.upper её не умеет), каждый код — один раз; английский код с AliasOf делит отметку с русским;
--  * офлайн-доход (Welcome) и настройки игрока (SetSettings);
--  * перед каждым сохранением: LastOnline и время в игре (Stats.PlaySeconds).
-- Тексты для игрока (ответы запросов, Notify) — Loc.msg: клиент рисует их на своём языке (Loc.render).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Format"))
local Loc = require(Shared:WaitForChild("Loc"))
local Net = require(Shared:WaitForChild("Net"))
local Pets = require(Shared:WaitForChild("Pets"))
local PlayerData = require(Shared:WaitForChild("PlayerData"))
local Quests = require(Shared:WaitForChild("Quests"))

local ServerLogic = require(script.Parent.Parent.Lib.ServerLogic)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PetService = require(script.Parent.PetService)
local RequestService = require(script.Parent.RequestService)
local StrikeService = require(script.Parent.StrikeService)

type Data = PlayerData.Data
type QuestState = PlayerData.QuestState

local DailyService = {}

local LOADING = Loc.msg("Данные ещё загружаются")
local PET_FULL = Loc.msg("Нет места для питомца — удали лишних в «Питомцах»")
local DAY_CHECK_EVERY = 30 -- как часто проверять смену дня у игроков онлайн
local FORGIVEN_DAYS = 2 -- день == прошлый + 1 или + 2 (один пропуск прощается)
local MAX_CODE_BYTES = 64
local RARE_ORDER = Config.Colors.purple.Order -- «фиолетовые или реже»

local notifyRemote: RemoteEvent? = nil
local playMarks: { [Player]: number } = {} -- os.clock, с которого ещё не учтено время в игре

local function notify(player: Player, text: Loc.Msg | string, kind: string)
	local r = notifyRemote
	if r then
		r:FireClient(player, text, kind)
	end
end

local function today(): number
	return Quests.dayNumber(os.time())
end

----------------------------------------------------------------------
-- Награды (общие для календаря, заданий и кодов)
----------------------------------------------------------------------

local function grantBoost(player: Player, minutes: number)
	DataService.update(player, function(d)
		d.Boosts.Volts2x = math.max(os.time(), d.Boosts.Volts2x) + minutes * 60
	end)
end

-- «+X ⚡ и +Y 💎» (nil — ничего не выдано)
local function voltsAndShardsText(volts: number, shards: number): Loc.Msg?
	if volts > 0 and shards > 0 then
		return Loc.msg("+%s ⚡ и +%s 💎", Format.short(volts), Format.short(shards))
	elseif volts > 0 then
		return Loc.msg("+%s ⚡", Format.short(volts))
	elseif shards > 0 then
		return Loc.msg("+%s 💎", Format.short(shards))
	end
	return nil
end

-- Имена кокона и питомца — исходники из Pets: клиент переводит их как аргументы
local function cocoonText(cocoonId: string, kind: string): Loc.Msg
	local c = Pets.Cocoons[cocoonId]
	local p = Pets.Kinds[kind]
	return Loc.msg("🥚 %s: %s!", if c then c.Name else Loc.msg("Кокон"), if p then p.Name else kind)
end

----------------------------------------------------------------------
-- Календарь
----------------------------------------------------------------------

-- Номер дня серии, который игрок получит сегодня (та же логика, что в DailyUI)
local function nextStreak(d: Data, day: number): number
	local last = d.Daily.LastDay
	local keep = last > 0 and day - last >= 1 and day - last <= FORGIVEN_DAYS
	if keep and d.Daily.Streak < #Config.DailyRewards then
		return d.Daily.Streak + 1
	end
	return 1
end

local function claimDaily(player: Player, _payload: any): (boolean, any)
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	local day = today()
	if day <= d.Daily.LastDay then
		return false, Loc.msg("Сегодня уже забрал — приходи завтра!")
	end
	local streak = nextStreak(d, day)
	local r = Config.DailyRewards[streak]
	if not r then
		return false, RequestService.ErrorText
	end
	if (r.Kind == "cocoon" or r.Kind == "pet") and not PetService.hasRoom(player) then
		return false, PET_FULL
	end
	-- сначала отметить день (повторный запрос уже не пройдёт), потом выдать
	DataService.update(player, function(data)
		data.Daily.LastDay = day
		data.Daily.Streak = streak
	end)
	local text: Loc.Msg | string
	if r.Kind == "volts" then
		local volts = EconomyService.grantVolts(player, Economy.incomeMinutes(d, r.Amount or 0), "daily")
		local shards = EconomyService.grantShards(player, r.Shards or 0)
		text = voltsAndShardsText(volts, shards) or ""
	elseif r.Kind == "shards" then
		text = voltsAndShardsText(0, EconomyService.grantShards(player, r.Amount or 0)) or ""
	elseif r.Kind == "cocoon" then
		local id = r.Cocoon or "meadow"
		local rec = PetService.hatchFree(player, id)
		text = if rec then cocoonText(id, rec.Kind) else Loc.msg("🥚 Кокон")
	elseif r.Kind == "boost" then
		local minutes = r.Amount or 0
		grantBoost(player, minutes)
		text = Loc.msg("×2 Вольт на %d мин!", minutes)
	elseif r.Kind == "pet" then
		local kind = r.Pet or Pets.StarterPet
		local rec = PetService.grantPet(player, kind, true)
		local def = Pets.Kinds[kind]
		text = if rec and def then Loc.msg("🐾 Новый питомец: %s!", def.Name) else Loc.msg("🐾 Питомец")
	else
		text = "🎁"
	end
	return true, Loc.msg("День %d: %s", streak, text)
end

----------------------------------------------------------------------
-- Задания дня
----------------------------------------------------------------------

-- Выдать награду за выполненное задание (q уже отмечено как полученное). Текст «+X ⚡ и +Y 💎» (nil — нечего)
local function grantQuestReward(player: Player, d: Data, q: QuestState): Loc.Msg?
	local def = Quests.def(q.Id)
	if not def then
		return nil
	end
	local volts = EconomyService.grantVolts(player, Economy.incomeMinutes(d, def.Minutes), "quest")
	local shards = EconomyService.grantShards(player, def.Shards)
	return voltsAndShardsText(volts, shards)
end

-- Задания на сегодня (новый день — новые задания). Выполненные, но не забранные — зачисляются сами.
local function ensureQuests(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local day = today()
	if d.Quests.Day == day then
		return
	end
	local done: { QuestState } = {}
	for _, q in d.Quests.List do
		if not q.Claimed and q.Progress >= q.Target then
			table.insert(done, q)
		end
	end
	local list = Quests.forDay(day, player.UserId, d.Zone)
	local ok = DataService.update(player, function(data)
		for _, q in done do
			q.Claimed = true
		end
		data.Quests = { Day = day, List = list }
	end)
	if not ok then
		return
	end
	for _, q in done do
		local text = grantQuestReward(player, d, q)
		if text then
			notify(player, Loc.msg("✅ Награда за прошлое задание зачислена: %s", text), "good")
		end
	end
end

-- Продвинуть задания с событием event: сумма (amount) или максимум (для Max-заданий)
local function bump(player: Player, event: string, amount: number)
	local d = DataService.get(player)
	if not d or amount <= 0 then
		return
	end
	if d.Quests.Day ~= today() then
		ensureQuests(player)
	end
	local changes: { { q: QuestState, value: number } } = {}
	for _, q in d.Quests.List do
		local def = Quests.def(q.Id)
		if def and def.Event == event and not q.Claimed and q.Progress < q.Target then
			local raw = if def.Max then math.max(q.Progress, amount) else q.Progress + amount
			local value = math.min(q.Target, math.floor(raw))
			if value ~= q.Progress then
				table.insert(changes, { q = q, value = value })
			end
		end
	end
	if #changes == 0 then
		return
	end
	DataService.update(player, function()
		for _, c in changes do
			c.q.Progress = c.value
		end
	end)
	for _, c in changes do
		if c.value >= c.q.Target then
			notify(player, Loc.msg("✅ Задание выполнено! Забери награду в «Наградах»"), "good")
		end
	end
end

local function claimQuest(player: Player, payload: any): (boolean, any)
	if not ServerLogic.isInteger(payload) then
		return false, Loc.msg("Нет такого задания")
	end
	local index: number = payload
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if d.Quests.Day ~= today() then
		ensureQuests(player) -- выполненные вчерашние награды зачислит сама
		return false, Loc.msg("Наступил новый день — задания обновились")
	end
	local q = d.Quests.List[index]
	if not q then
		return false, Loc.msg("Нет такого задания")
	end
	if q.Claimed then
		return false, Loc.msg("Награда уже получена")
	end
	if q.Progress < q.Target then
		return false, Loc.msg("Ещё не выполнено: осталось %d", q.Target - q.Progress)
	end
	DataService.update(player, function()
		q.Claimed = true
	end)
	-- ответ: сообщение с наградой или "✅" (клиент сравнивает с ним: награды нет)
	local text = grantQuestReward(player, d, q)
	return true, if text then text else "✅"
end

----------------------------------------------------------------------
-- Коды
----------------------------------------------------------------------

-- Верхний регистр с кириллицей (а–я → А–Я, ё → Ё) и латиницей. nil — не UTF-8 (utf8.codes падает).
local function upperUtf8(s: string): string?
	local ok, out = pcall(Loc.upper, s)
	return if ok then out else nil
end

-- Нормализовать введённый код: без пробелов, верхний регистр
function DailyService.normalizeCode(text: string): string?
	local trimmed = string.gsub(text, "%s+", "")
	if trimmed == "" or #trimmed > MAX_CODE_BYTES then
		return nil
	end
	return upperUtf8(trimmed)
end

local function redeemCode(player: Player, payload: any): (boolean, any)
	if typeof(payload) ~= "string" or #payload > MAX_CODE_BYTES * 2 then
		return false, Loc.msg("Неверный код")
	end
	local key = DailyService.normalizeCode(payload)
	local code = if key then Config.Codes[key] else nil
	if not key or not code then
		return false, Loc.msg("Неверный код")
	end
	-- английский код (AliasOf) и русский — одна награда: отметка «использован» общая
	local mark = code.AliasOf or key
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	if d.Codes[mark] then
		return false, Loc.msg("Этот код уже использован")
	end
	if code.Kind == "cocoon" and not PetService.hasRoom(player) then
		return false, PET_FULL
	end
	DataService.update(player, function(data)
		data.Codes[mark] = true
	end)
	if code.Kind == "shards" then
		local reward = voltsAndShardsText(0, EconomyService.grantShards(player, code.Amount or 0))
		return true, if reward then Loc.msg("Код сработал! %s", reward) else Loc.msg("Код сработал!")
	elseif code.Kind == "boost" then
		local minutes = code.Amount or 0
		grantBoost(player, minutes)
		return true, Loc.msg("Код сработал! ×2 Вольт на %d мин", minutes)
	elseif code.Kind == "cocoon" then
		local id = code.Cocoon or "meadow"
		local rec = PetService.hatchFree(player, id)
		return true, Loc.msg("Код сработал! %s", if rec then cocoonText(id, rec.Kind) else "🥚")
	end
	return true, Loc.msg("Код сработал!")
end

----------------------------------------------------------------------
-- Офлайн-доход и настройки
----------------------------------------------------------------------

local function claimWelcome(player: Player, _payload: any): (boolean, any)
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	local amount = d.Welcome
	if amount <= 0 then
		return false, Loc.msg("Уже забрано")
	end
	DataService.update(player, function(data)
		data.Welcome = 0
	end)
	return true, EconomyService.grantVolts(player, amount, "welcome")
end

local function setSettings(player: Player, payload: any): (boolean, any)
	if typeof(payload) ~= "table" then
		return false, RequestService.ErrorText
	end
	local d = DataService.get(player)
	if not d then
		return false, LOADING
	end
	local s = d.Settings
	local function flag(v: any, old: boolean): boolean
		return if typeof(v) == "boolean" then v else old
	end
	local limit = math.floor(Config.Catch.MaxCalibration * 1000 + 0.5)
	local offset = s.Offset
	if ServerLogic.isFinite(payload.Offset) then
		offset = math.clamp(math.floor(payload.Offset + 0.5), -limit, limit)
	end
	local new = {
		Music = flag(payload.Music, s.Music),
		Sfx = flag(payload.Sfx, s.Sfx),
		SoftFlash = flag(payload.SoftFlash, s.SoftFlash),
		Shake = flag(payload.Shake, s.Shake),
		Offset = offset,
		-- язык: "en" | "ru", пустая строка — по локали Roblox; без поля — прежний
		Lang = if payload.Lang == "en" or payload.Lang == "ru" or payload.Lang == "" then payload.Lang else s.Lang,
	}
	DataService.update(player, function(data)
		data.Settings = new
	end)
	return true, table.clone(new)
end

----------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------

-- Время в игре и момент выхода — перед каждым сохранением (и последним при выходе)
local function beforeSave(player: Player, d: Data)
	d.LastOnline = os.time()
	local mark = playMarks[player]
	if mark then
		local elapsed = math.floor(os.clock() - mark)
		if elapsed > 0 then
			d.Stats.PlaySeconds += elapsed
			playMarks[player] = mark + elapsed
		end
	end
end

function DailyService.start()
	notifyRemote = Net.event("Notify")

	RequestService.handle(Net.Actions.ClaimDaily, claimDaily)
	RequestService.handle(Net.Actions.ClaimQuest, claimQuest)
	RequestService.handle(Net.Actions.RedeemCode, redeemCode)
	RequestService.handle(Net.Actions.ClaimWelcome, claimWelcome)
	if not RequestService.has(Net.Actions.SetSettings) then
		RequestService.handle(Net.Actions.SetSettings, setSettings)
	end

	DataService.addBeforeSave(beforeSave)
	DataService.Loaded:Connect(function(player)
		playMarks[player] = os.clock()
		ensureQuests(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- последнее сохранение (с beforeSave) запускается тем же событием — отметку убираем позже
		task.delay(DAY_CHECK_EVERY, function()
			if player.Parent ~= Players then
				playMarks[player] = nil
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			playMarks[player] = playMarks[player] or os.clock()
			ensureQuests(player)
		end
	end

	-- прогресс заданий
	StrikeService.CatchResolved:Connect(function(player, info)
		local caught = info.grade == "perfect" or info.grade == "good"
		if not caught then
			return
		end
		bump(player, "catch", 1)
		if info.grade == "perfect" then
			bump(player, "perfect", 1)
		end
		bump(player, "combo", info.combo)
		if info.shared then
			return -- общие кольца событий (шаровая, радужная) не идут в задания на цвет
		end
		local def = Config.Colors[info.color]
		if def and def.Order >= RARE_ORDER then
			bump(player, "rare", 1)
		end
		if info.color == "gold" then
			bump(player, "gold", 1)
		end
	end)
	EconomyService.Sold:Connect(function(player, _volts, fill)
		if typeof(fill) == "number" and fill >= Config.City.MinFill then
			bump(player, "sell", 1)
		end
	end)
	PetService.Hatched:Connect(function(player)
		bump(player, "hatch", 1)
	end)
	StrikeService.ShardCollected:Connect(function(player, amount)
		bump(player, "shards", amount)
	end)

	-- смена дня у тех, кто играет через полночь
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(ensureQuests, player)
				if not ok then
					warn("[DailyService] задания " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return DailyService
