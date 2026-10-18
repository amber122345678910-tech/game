--!strict
-- Точка входа клиента: подключение к серверу, контроллеры (звук, «сочность», мир, кольца, нажатия,
-- персонажи, питомцы), окна интерфейса и обучение. Каждый модуль запускается отдельно и в pcall:
-- ошибка или ожидание в одном не останавливает остальные.

local StarterGui = game:GetService("StarterGui")

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

-- Звуки: клик для всех кнопок интерфейса и настройки музыки/звуков из данных игрока
UIKit.setClickHandler(function()
	Sounds.play("Click")
end)
local function applySettings(data: any)
	if typeof(data) ~= "table" or typeof(data.Settings) ~= "table" then
		return
	end
	Sounds.setMusicEnabled(data.Settings.Music ~= false)
	Sounds.setSfxEnabled(data.Settings.Sfx ~= false)
end
ClientState.Changed:Connect(applySettings)
applySettings(ClientState.data)

-- Juice создаёт свои объекты при загрузке модуля
startModule("Juice", Controllers:WaitForChild("Juice"))

-- EventFX: шаровая молния, радужный луч, подарки и окна киосков хаба (ProximityPrompt → OpenWindow)
for _, name in { "WorldFX", "StrikeController", "CatchController", "CharacterFX", "PetsFX", "EventFX" } do
	startModule(name, Controllers:WaitForChild(name))
end

for _, name in UI_MODULES do
	local module = UIFolder:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		startModule(name, module)
	end
end

startModule("Tutorial", Controllers:WaitForChild("Tutorial"))
