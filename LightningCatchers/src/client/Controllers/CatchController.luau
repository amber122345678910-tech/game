--!strict
-- Нажатие «⚡ ЛОВИ»: кнопка на экране (HUD), на ПК — E и левая кнопка мыши (мимо интерфейса), на геймпаде — R2/R1
-- (X остаётся подсказкам ProximityPrompt). Пробел не ловит — это всегда прыжок.
-- Выбирает кольцо, отправляет нажатие серверу и сразу (без ожидания ответа) оценивает его сам:
-- звук и надпись появляются мгновенно, ответ сервера потом уточняет комбо (и поправляет надпись, если не засчитал).
-- Стоял в кольце и не нажал: на островах со штрафами «ШАРАХНУЛО» показываем сами, как только закрылось окно
-- нажатия (сервер потом только подтверждает); на первом острове — подсказка «Жми ⚡ в момент удара!».

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strikes = require(Shared:WaitForChild("Strikes"))
local Net = require(Shared:WaitForChild("Net"))

local ClientState = require(script.Parent.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)
local Juice = require(script.Parent.Juice)
local StrikeController = require(script.Parent.StrikeController)
local CharacterFX = require(script.Parent.CharacterFX)
local Theme = require(script.Parent.Parent.UI.Theme)

local CatchController = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- Константы ввода и звука
----------------------------------------------------------------------
local DEBOUNCE = 0.08 -- не чаще одного нажатия за столько секунд
local NO_TARGET_COOLDOWN = 1.5 -- подсказка «Встань в круг!» не чаще
local EARLY_COOLDOWN = 0.6
-- нажатие раньше удара больше чем на столько секунд — случайное (кольцо только появилось):
-- удар не тратим, подсказываем «Рано!». Пауза «Обманки» ближе к удару — там ранний тап честно промах.
local EARLY_IGNORE = 1.0
local HINT_COOLDOWN = 6 -- подсказка «Жми ⚡ в момент удара!» (первый остров) не чаще
local ERROR_SAMPLES = 10 -- для автоподстройки задержки
local MIN_SAMPLES = 3
-- лесенка звука: пентатоника на одну октаву (выше звук становится визгливым), дальше идёт по кругу,
-- а сверху добавляется тихая искорка — чем длиннее серия, тем она громче
local LADDER = { 0, 2, 4, 7, 9, 12 }
local MILESTONES = { 10, 25, 50, 100 }
local ACTION_NAME = "LightningCatch"
local KEEP_KEYS = 10 -- столько секунд помним, какие удары уже нажаты или решены сервером

type Pending = { tap: number, raw: number, hit: number, grade: string, color: string }
-- откуда нажатие: кнопка на экране, клавиша (E, R2/R1) или левая кнопка мыши
type Source = "button" | "key" | "mouse"

local catchEvent: RemoteEvent? = nil
local lastPress = 0
local lastNoTarget = 0
local lastEarly = 0
local lastHint = -math.huge
local pending: { [string]: Pending } = {} -- "id:hit" -> отправленное нажатие
local handled: { [string]: number } = {} -- "id:hit" -> os.clock(): нажатие отправлено, прогноз сделан или сервер ответил
local zapPredicted: { [string]: boolean } = {} -- "id:hit" -> показали «ШАРАХНУЛО» до ответа сервера
local zappedRings: { [number]: number } = {} -- id кольца -> os.clock(): оно уже ударило током (как и сервер, второй раз не бьёт)
local pendingCount = 0
local errors: { number } = {} -- последние ошибки нажатий (с): нажатие без поправки − удар
local serverCombo = 0
local predictedCombo = 0
local lastResultCombo = 0
local shownPrompts: { [ProximityPrompt]: boolean } = {} -- подсказки «Нажми E» рядом (киоски, барьеры)

local function key(id: number, hit: number): string
	return tostring(id) .. ":" .. tostring(hit)
end

local function comboAttr(): number
	local c = player:GetAttribute(Net.PlayerAttrs.Combo)
	return if typeof(c) == "number" then c else 0
end

local function localRoot(): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Поправка задержки касания из настроек (секунды)
local function offsetSeconds(): number
	local d = ClientState.data
	local offset = if d then d.Settings.Offset else 0
	local maxOffset = Config.Catch.MaxCalibration * 1000
	return math.clamp(offset, -maxOffset, maxOffset) / 1000
end

local function playGradeSound(grade: string, combo: number)
	if grade == "perfect" or grade == "good" then
		local c = math.max(1, combo)
		local step = LADDER[(c - 1) % #LADDER + 1]
		local laps = (c - 1) // #LADDER -- сколько раз лесенка прошла октаву
		local pitch = Sounds.ladderPitch(step, 12)
		if grade == "perfect" then
			Sounds.play("PerfectZap")
			Sounds.play("Ding", pitch)
		else
			Sounds.play("Ding", pitch * 0.75, 0.8)
		end
		if laps > 0 then
			Sounds.play("Shard", pitch, 0.2 + 0.1 * math.min(laps, 3))
		end
	else
		Sounds.play("Miss")
	end
end

-- Подсказка над головой (мгновенно, без окон)
local function hint(text: string, color: Color3?)
	local root = localRoot()
	if root then
		Juice.popup(root.Position + Vector3.new(0, 3.5, 0), text, color or Theme.Text, false)
	end
end

-- Видна ли сейчас подсказка ProximityPrompt на эту клавишу (тогда клавиша — её)
local function promptUsesKey(keyCode: Enum.KeyCode): boolean
	for prompt in shownPrompts do
		if prompt.Parent and prompt.Enabled and (prompt.KeyboardKeyCode == keyCode or prompt.GamepadKeyCode == keyCode) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Нажатие
----------------------------------------------------------------------

-- Нажал, а ловить нечего. ЛКМ по миру — тихо (это часто просто клик); в кольце, где всё уже поймано
-- или окно закрылось (двойное нажатие после ИДЕАЛЬНО), — тоже тихо, без «Встань в круг!».
local function noTarget(source: Source, inside: boolean, clock: number)
	if source == "mouse" or inside or clock - lastNoTarget < NO_TARGET_COOLDOWN then
		return
	end
	lastNoTarget = clock
	if ClientState.zone() == 0 then
		ClientState.Toast:Fire("Молнии бьют на островах!", "info")
	else
		ClientState.Toast:Fire("Встань в круг!", "info")
	end
	Sounds.play("Error", 1, 0.5)
end

local function press(source: Source)
	local clock = os.clock()
	if clock - lastPress < DEBOUNCE then
		return
	end
	lastPress = clock
	local root = localRoot()
	if not root then
		return
	end
	local offset = offsetSeconds()
	local tap = ClientState.now() + offset
	local id, hit, inside = StrikeController.targetFor(root.Position, tap)
	if not id or not hit then
		noTarget(source, inside, clock)
		return
	end
	local hitT = StrikeController.hitTime(id, hit)
	if not hitT then
		return
	end
	local perfect, good = ClientState.windows()
	if hitT - tap > math.max(EARLY_IGNORE, good + 0.2) then
		-- слишком рано: удар не тратим, подсказываем
		if clock - lastEarly >= EARLY_COOLDOWN then
			lastEarly = clock
			hint("Рано! Жди кольцо", Theme.TextDim)
		end
		return
	end
	local ev = catchEvent
	if not ev then
		return
	end
	ev:FireServer(id, hit, tap)

	local grade = Strikes.judge(tap - hitT, perfect, good)
	StrikeController.markJudged(id, hit, grade)
	local info = StrikeController.info(id)
	local color: string = if info then info.Color else "blue"
	local k = key(id, hit)
	handled[k] = clock
	if not pending[k] then
		pendingCount += 1
	end
	pending[k] = { tap = tap, raw = tap - offset - hitT, hit = hitT, grade = grade, color = color }

	if grade == "perfect" then
		predictedCombo += 1
	elseif grade == "miss" then
		predictedCombo = 0
	end
	ClientState.LocalGrade:Fire(grade, color, predictedCombo)
	playGradeSound(grade, math.max(1, predictedCombo))
end

----------------------------------------------------------------------
-- Стоял в кольце и не нажал
----------------------------------------------------------------------

-- «ШАРАХНУЛО» сразу у себя: надпись, сажа, искры, звук. Сервер потом присылает zap — это лишь подтверждение.
local function predictZap(id: number, hit: number, colorId: string)
	local k = key(id, hit)
	handled[k] = os.clock()
	zapPredicted[k] = true
	zappedRings[id] = os.clock()
	StrikeController.markJudged(id, hit, "zap") -- позднее нажатие на этот удар уже не отправляем
	ClientState.markPredicted(id, hit, "zap")
	predictedCombo = 0
	ClientState.LocalGrade:Fire("zap", colorId, 0)
	CharacterFX.predictZap(Config.Catch.ZapVisual)
end

-- Удар пришёл, а игрок стоит в кольце и не нажимал (StrikeController.UntappedHit).
-- Нажать ещё можно (окно ХОРОШО после удара), поэтому решаем, когда оно закроется.
local function onUntappedHit(id: number, hit: number, colorId: string, zone: number)
	if zone < 1 or zone > #Config.Zones then
		return
	end
	local hitT = StrikeController.hitTime(id, hit)
	if not hitT then
		return
	end
	local k = key(id, hit)
	local _, good = ClientState.windows()
	local wait = hitT + good - offsetSeconds() - ClientState.now()
	task.delay(math.max(0, wait), function()
		if handled[k] or ClientState.zone() ~= zone or not localRoot() then
			return -- нажал поздно, сервер уже ответил или ушёл с острова
		end
		if Config.Zones[zone].Penalties then
			if zappedRings[id] then
				handled[k] = os.clock() -- двойное/вилка: одно кольцо оглушает один раз, дальше — просто промах
			else
				predictZap(id, hit, colorId)
			end
		else
			handled[k] = os.clock()
			local clock = os.clock()
			if clock - lastHint >= HINT_COOLDOWN then
				lastHint = clock
				ClientState.Toast:Fire("Жми ⚡ в момент удара!", "info")
			end
		end
	end)
end

----------------------------------------------------------------------
-- Ответы сервера: комбо, ошибки для автоподстройки, вехи комбо
----------------------------------------------------------------------
local function onResolved(msg: Net.StrikeResultMsg)
	local m = msg :: any
	if typeof(m) ~= "table" or typeof(m.Id) ~= "number" or typeof(m.Hit) ~= "number" then
		return
	end
	local k = key(msg.Id, msg.Hit)
	handled[k] = os.clock()
	if msg.Grade == "zap" then
		zappedRings[msg.Id] = os.clock()
	end
	local p = pending[k]
	if p then
		pending[k] = nil
		pendingCount = math.max(0, pendingCount - 1)
		if msg.Grade == "perfect" or msg.Grade == "good" then
			table.insert(errors, p.raw)
			while #errors > ERROR_SAMPLES do
				table.remove(errors, 1)
			end
		end
		-- сервер решил иначе, чем показал клиент: поправить надпись (zap и burst HUD покажет сам)
		local caughtLocal = p.grade == "perfect" or p.grade == "good"
		if caughtLocal and (msg.Grade == "miss" or msg.Grade == "ground") then
			ClientState.LocalGrade:Fire("miss", p.color, 0)
			Sounds.play("Miss")
		elseif not caughtLocal and (msg.Grade == "perfect" or msg.Grade == "good") then
			local combo = if typeof(m.Combo) == "number" then m.Combo else 0
			ClientState.LocalGrade:Fire(msg.Grade, p.color, combo)
			playGradeSound(msg.Grade, math.max(1, combo))
		end
	end
	if zapPredicted[k] then
		zapPredicted[k] = nil
		if msg.Grade ~= "zap" then
			-- прогноз не подтвердился (сервер видел игрока вне кольца): снять сажу и искры
			CharacterFX.cancelPredictedZap()
		end
	end
	if typeof(m.Combo) == "number" then
		local combo: number = m.Combo
		-- вехи комбо: особая вспышка и надпись
		for _, mark in MILESTONES do
			if combo >= mark and lastResultCombo < mark then
				local d = ClientState.data
				local soft = d == nil or d.Settings.SoftFlash
				Juice.flash(Theme.Perfect, if soft then 0.18 else 0.35)
				Sounds.play("PowerUp")
				ClientState.Toast:Fire("Комбо " .. tostring(mark) .. "! Ты молния! ⚡", "rare")
			end
		end
		lastResultCombo = combo
		serverCombo = combo
		if pendingCount == 0 then
			predictedCombo = combo
		end
	end
end

-- Устаревшие нажатия без ответа (сервер не ответил) не должны вечно влиять на прогноз комбо
local function prunePending()
	local clock = os.clock()
	for k, at in handled do
		if clock - at > KEEP_KEYS then
			handled[k] = nil
			zapPredicted[k] = nil
		end
	end
	for id, at in zappedRings do
		if clock - at > KEEP_KEYS then
			zappedRings[id] = nil
		end
	end
	local now = ClientState.now()
	local stale: { string }? = nil
	for k, p in pending do
		if now - p.hit > Config.Catch.MaxTapAge + Config.Catch.LatencyGrace then
			stale = stale or {}
			table.insert(stale :: { string }, k)
		end
	end
	if stale then
		for _, k in stale do
			pending[k] = nil
		end
		pendingCount = 0
		for _ in pending do
			pendingCount += 1
		end
		if pendingCount == 0 then
			predictedCombo = serverCombo
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Средняя ошибка последних удачных нажатий (секунды, «нажатие − удар» БЕЗ поправки из настроек).
-- > 0 — игрок (или его экран) жмёт поздно. Нужная поправка (мс) = −averageError() × 1000.
-- nil, если удачных нажатий пока меньше трёх.
function CatchController.averageError(): number?
	if #errors < MIN_SAMPLES then
		return nil
	end
	local sum = 0
	for _, e in errors do
		sum += e
	end
	return sum / #errors
end

-- Сколько нажатий в выборке автоподстройки
function CatchController.errorSamples(): number
	return #errors
end

-- Сбросить выборку (после смены поправки в настройках)
function CatchController.resetErrors()
	table.clear(errors)
end

-- Текущее комбо с учётом ещё не подтверждённых нажатий
function CatchController.combo(): number
	return predictedCombo
end

-- Нажать «ЛОВИ» из кода (например, из другой кнопки)
function CatchController.press()
	press("button")
end

----------------------------------------------------------------------
-- Запуск
----------------------------------------------------------------------
local started = false
function CatchController.start()
	if started then
		return
	end
	started = true
	serverCombo = comboAttr()
	predictedCombo = serverCombo
	lastResultCombo = serverCombo
	task.spawn(function()
		catchEvent = Net.event("Catch")
	end)

	ClientState.CatchPressed:Connect(function()
		press("button")
	end)
	ClientState.StrikeResolved:Connect(onResolved)
	StrikeController.UntappedHit:Connect(onUntappedHit)
	player:GetAttributeChangedSignal(Net.PlayerAttrs.Combo):Connect(function()
		serverCombo = comboAttr()
		if pendingCount == 0 then
			predictedCombo = serverCombo
		end
		if serverCombo < lastResultCombo then
			lastResultCombo = serverCombo -- комбо сгорело по времени
		end
	end)
	ClientState.ZoneChanged:Connect(function()
		table.clear(pending)
		pendingCount = 0
		predictedCombo = comboAttr()
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = nil
	end)

	-- Клавиатура (E) и геймпад (R2, R1). Пробел и X не трогаем: прыжок и подсказки ProximityPrompt.
	ContextActionService:BindActionAtPriority(
		ACTION_NAME,
		function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			-- в хабе ловить нечего: клавиша остаётся киоскам; рядом подсказка на эту клавишу — она её
			if ClientState.zone() == 0 or promptUsesKey(input.KeyCode) then
				return Enum.ContextActionResult.Pass
			end
			press("key")
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonR1
	)

	-- Левая кнопка мыши — только мимо интерфейса
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		press("mouse")
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			prunePending()
			for prompt in shownPrompts do
				if not prompt.Parent then
					shownPrompts[prompt] = nil
				end
			end
		end
	end)
end

return CatchController
