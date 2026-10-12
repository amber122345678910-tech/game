--!strict
-- Точка входа клиента: состояние → звук → контроллеры → интерфейс. Каждый модуль стартует в pcall,
-- чтобы ошибка одного не ломала остальные.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local UIKit = require(UI:WaitForChild("UIKit"))
local Sounds = require(Controllers:WaitForChild("Sounds"))

ClientState.init()

-- Инструментов нет, рюкзак и здоровье прячем; чат оставляем.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

Sounds.preload()
UIKit.setClickSound(Sounds.get("UiClick"))

local function safeInit(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(string.format("[Client] %s failed to init: %s", name, tostring(err)))
	end
end

local function initModule(folder: Instance, name: string)
	local module = folder:FindFirstChild(name)
	if not module then
		warn("[Client] module missing: " .. name)
		return
	end
	safeInit(name, function()
		local m = (require :: any)(module)
		if type(m) == "table" and type(m.init) == "function" then
			local init: () -> () = m.init
			init()
		end
	end)
end

-- Порядок важен: сначала контроллеры (камера, движение, эффекты), затем интерфейс.
for _, name in { "Camera", "Movement", "Flashlight", "Footsteps", "Interaction", "Hiding", "Spectate", "FX", "Ambience" } do
	initModule(Controllers, name)
end
for _, name in { "Notifications", "HUD", "AlertUI", "ShopUI", "LobbyUI", "ResultsUI", "SettingsUI", "Tips" } do
	initModule(UI, name)
end

-- Маленькая метка версии в углу экрана
do
	local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
	local gui = UIKit.new("ScreenGui", {
		Name = "VersionTag",
		ResetOnSpawn = false,
		DisplayOrder = -1,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	UIKit.label({
		Text = "v" .. Config.Version,
		Size = UDim2.fromOffset(60, 16),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.6,
		MaxTextSize = 14,
		Parent = gui,
	})
end
