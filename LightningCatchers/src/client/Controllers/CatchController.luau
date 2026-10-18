--!strict
-- Нажатие «⚡ ЛОВИ»: кнопка на экране (HUD), на ПК — E, Пробел (только когда стоишь в кольце) и левая кнопка мыши.
-- Выбирает кольцо, отправляет нажатие серверу и сразу (без ожидания ответа) оценивает его сам:
-- звук и надпись появляются мгновенно, ответ сервера потом уточняет комбо.

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
local ERROR_SAMPLES = 10 -- для автоподстройки задержки
local MIN_SAMPLES = 3
local PENTATONIC = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24 }
local MILESTONES = { 10, 25, 50, 100 }
local ACTION_NAME = "LightningCatch"

type Pending = { tap: number, raw: number, hit: number, grade: string }

local catchEvent: RemoteEvent? = nil
local lastPress = 0
local lastNoTarget = 0
local lastEarly = 0
local pending: { [string]: Pending } = {} -- "id:hit" -> отправленное нажатие
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

local function tapTime(): number
	return ClientState.now() + offsetSeconds()
end

local function playGradeSound(grade: string, combo: number)
	if grade == "perfect" then
		Sounds.play("PerfectZap")
		local step = PENTATONIC[math.clamp(combo, 1, #PENTATONIC)]
		Sounds.play("Ding", Sounds.ladderPitch(step, 24))
	elseif grade == "good" then
		local step = PENTATONIC[math.clamp(combo, 1, #PENTATONIC)]
		Sounds.play("Ding", Sounds.ladderPitch(step, 24) * 0.75, 0.8)
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
		if prompt.Parent and prompt.Enabled and prompt.KeyboardKeyCode == keyCode then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Нажатие
----------------------------------------------------------------------
local function press()
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
	local id, hit = StrikeController.targetFor(root.Position, tap)
	if not id or not hit then
		if clock - lastNoTarget >= NO_TARGET_COOLDOWN then
			lastNoTarget = clock
			if ClientState.zone() == 0 then
				ClientState.Toast:Fire("Молнии бьют на островах!", "info")
			else
				ClientState.Toast:Fire("Встань в круг!", "info")
			end
			Sounds.play("Error", 1, 0.5)
		end
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
	local k = key(id, hit)
	if not pending[k] then
		pendingCount += 1
	end
	pending[k] = { tap = tap, raw = tap - offset - hitT, hit = hitT, grade = grade }

	if grade == "perfect" then
		predictedCombo += 1
	elseif grade == "miss" then
		predictedCombo = 0
	end
	local info = StrikeController.info(id)
	local color: string = if info then info.Color else "blue"
	ClientState.LocalGrade:Fire(grade, color, predictedCombo)
	playGradeSound(grade, math.max(1, predictedCombo))
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
	press()
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

	ClientState.CatchPressed:Connect(press)
	ClientState.StrikeResolved:Connect(onResolved)
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

	-- Клавиатура и геймпад. Пробел ловит, только если рядом есть кольцо, иначе — обычный прыжок.
	ContextActionService:BindActionAtPriority(
		ACTION_NAME,
		function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			if input.KeyCode ~= Enum.KeyCode.Space and promptUsesKey(input.KeyCode) then
				return Enum.ContextActionResult.Pass
			end
			if input.KeyCode == Enum.KeyCode.Space then
				local root = localRoot()
				if not root then
					return Enum.ContextActionResult.Pass
				end
				local id = StrikeController.targetFor(root.Position, tapTime())
				if not id then
					return Enum.ContextActionResult.Pass
				end
			end
			press()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.E,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonR2
	)

	-- Левая кнопка мыши — только мимо интерфейса
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		press()
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
