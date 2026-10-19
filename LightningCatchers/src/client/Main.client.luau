--!strict
-- Точка входа клиента: подключение к серверу, контроллеры (звук, «сочность», мир, кольца, нажатия,
-- персонажи, питомцы), окна интерфейса и обучение. Каждый модуль запускается отдельно и в pcall:
-- ошибка или ожидание в одном не останавливает остальные.

local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

-- Main — LocalScript в папке Client, рядом с ClientState, Controllers и UI
local Client = script.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local Controllers = Client:WaitForChild("Controllers")
local UIFolder = Client:WaitForChild("UI")

local Sounds = require(Controllers:WaitForChild("Sounds"))
local UIKit = require(UIFolder:WaitForChild("UIKit"))

-- require модуля, найденного по имени во время игры (его тип заранее неизвестен)
local requireAny = require :: (Instance) -> any

-- Окна интерфейса (их пишет UI): каждый — ModuleScript в UI с функцией start()
local UI_MODULES = {
	"HUD",
	"Notifications",
	"ShopUI",
	"PetsUI",
	"CollectionUI",
	"TeleportUI",
	"RebirthUI",
	"DailyUI",
	"SettingsUI",
	"WelcomeUI",
}

-- Свой инвентарь Roblox не нужен: громоотвод всегда в руках
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

-- Запустить модуль: require + start() в своём потоке и в pcall
local function startModule(label: string, module: Instance)
	task.spawn(function()
		local ok, err = pcall(function()
			local m = requireAny(module)
			local start: any = if typeof(m) == "table" then m.start else nil
			if typeof(start) == "function" then
				(start :: () -> ())()
			end
		end)
		if not ok then
			warn(string.format("[Client] %s не запустился: %s", label, tostring(err)))
		end
	end)
end

ClientState.start()

-- Язык (src/shared/Loc.luau): настройка игрока, а если её нет — локаль Roblox. Выбирается до запуска модулей:
-- окна строят тексты один раз при старте. Данные ждём недолго — без них язык берётся по локали
do
	local Loc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loc"))
	local t0 = os.clock()
	while not ClientState.data and os.clock() - t0 < 6 do
		task.wait(0.05)
	end
	local d = ClientState.data
	Loc.setLang(Loc.pick(if d then d.Settings.Lang else nil, Loc.localeId()))
end

-- Прогрев шрифтов (docs/STYLE.md §8.3.5): Montserrat Black Italic и Nunito 700/800 — облачные начертания,
-- качаются при первом использовании. Невидимые лейблы со всеми пятью начертаниями до показа HUD и окон,
-- чтобы первая оценка и заголовки не мелькнули запасным шрифтом
task.spawn(function()
	local ok, err = pcall(function()
		local Fonts = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Fonts"))
		local warm = Instance.new("ScreenGui")
		warm.Name = "FontWarmup"
		warm.ResetOnSpawn = false
		warm.Enabled = true
		warm.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local probes: { Instance } = {}
		for _, face in Fonts.All do
			local l = Instance.new("TextLabel")
			l.FontFace = face
			l.Text = "ЛОВЦЫ МОЛНИЙ Ёё LIGHTNING CATCHERS ×0123456789" -- noloc
			l.BackgroundTransparency = 1
			l.TextTransparency = 1
			l.Size = UDim2.fromOffset(4, 4)
			l.Parent = warm
			table.insert(probes, l)
		end
		ContentProvider:PreloadAsync(probes)
		task.delay(5, function()
			warm:Destroy()
		end)
	end)
	if not ok then
		warn("[Client] прогрев шрифтов: " .. tostring(err))
	end
end)

-- Звуки: клик для всех кнопок интерфейса. Музыку и звуки включает/выключает только SettingsUI:
-- он знает о ещё не сохранённых переключениях и не даёт старому снимку с сервера их откатить
UIKit.setClickHandler(function()
	Sounds.play("Click")
end)

-- Juice создаёт свои объекты при загрузке модуля
startModule("Juice", Controllers:WaitForChild("Juice"))

-- EventFX: шаровая молния, радужный луч, подарки и окна киосков хаба (ProximityPrompt → OpenWindow)
for _, name in { "WorldFX", "WorldText", "StrikeController", "CatchController", "CharacterFX", "PetsFX", "EventFX" } do
	startModule(name, Controllers:WaitForChild(name))
end

for _, name in UI_MODULES do
	local module = UIFolder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		startModule(name, module)
	end
end

startModule("Tutorial", Controllers:WaitForChild("Tutorial"))
