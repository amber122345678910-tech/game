--!strict
-- Точка входа клиента: запускает интерфейс и контроллеры.

local StarterGui = game:GetService("StarterGui")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local UIKit = require(UI:WaitForChild("UIKit"))
local HUD = require(UI:WaitForChild("HUD"))
local ShopUI = require(UI:WaitForChild("ShopUI"))
local ResultsUI = require(UI:WaitForChild("ResultsUI"))
local TutorialUI = require(UI:WaitForChild("TutorialUI"))
local Sounds = require(Controllers:WaitForChild("Sounds"))
local BuildController = require(Controllers:WaitForChild("BuildController"))
local StormFX = require(Controllers:WaitForChild("StormFX"))
local Waypoint = require(Controllers:WaitForChild("Waypoint"))
local DoorController = require(Controllers:WaitForChild("DoorController"))

-- Инструментов в игре нет — прячем рюкзак.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

-- Камера всегда следует за персонажем (на случай, если что-то её сбило) и без смещения тряски.
local Players = game:GetService("Players")
local function onCharacter(character: Model)
	local hum = character:WaitForChild("Humanoid", 10)
	local camera = workspace.CurrentCamera
	if hum and hum:IsA("Humanoid") and camera then
		hum.CameraOffset = Vector3.zero
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = hum
	end
end
Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
if Players.LocalPlayer.Character then
	task.spawn(onCharacter, Players.LocalPlayer.Character)
end

-- Маленькая метка версии в углу экрана
do
	local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
	local gui = UIKit.new("ScreenGui", {
		Name = "VersionTag",
		ResetOnSpawn = false,
		DisplayOrder = -1,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	UIKit.label({
		Text = "v" .. Config.Version,
		Size = UDim2.fromOffset(60, 16),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.5,
		MaxTextSize = 14,
		Parent = gui,
	})
end

Sounds.preload()
UIKit.setClickSound(Sounds.get("Click"))

local function safeInit(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(string.format("[Client] %s failed to init: %s", name, tostring(err)))
	end
end

safeInit("HUD", HUD.init)
safeInit("ShopUI", ShopUI.init)
safeInit("ResultsUI", ResultsUI.init)
safeInit("BuildController", BuildController.init)
safeInit("StormFX", StormFX.init)
safeInit("DoorController", DoorController.init)
safeInit("Waypoint", Waypoint.init)
safeInit("TutorialUI", TutorialUI.init)

-- Звуки событий
ClientState.Notified:Connect(function(_, kind)
	if kind == "error" then
		Sounds.playUI("Error")
	elseif kind == "success" then
		Sounds.playUI("Success")
	elseif kind == "purchase" then
		Sounds.playUI("Purchase")
	end
end)
