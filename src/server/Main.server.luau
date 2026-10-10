--!strict
-- Точка входа сервера: запускает все сервисы и связывает жизненный цикл игрока.

local Players = game:GetService("Players")

local Services = script.Parent:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local PlotService = require(Services:WaitForChild("PlotService"))
local BuildService = require(Services:WaitForChild("BuildService"))
local ShopService = require(Services:WaitForChild("ShopService"))
local StormService = require(Services:WaitForChild("StormService"))
local TutorialService = require(Services:WaitForChild("TutorialService"))

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

PlotService.init()
BuildService.init()
ShopService.init()
StormService.init()
TutorialService.init()

-- Когда данные игрока загружены — выдаём участок и строим сохранённый бункер.
DataService.Loaded:Connect(function(player, data)
	if player.Parent ~= Players then
		return
	end
	local plot = PlotService.assign(player)
	if not plot then
		Remotes.Notify:FireClient(player, "Все участки заняты! Попробуй другой сервер.", "error")
		return
	end
	local entries, dug = Grid.deserialize(data.Layout)
	PlotService.resetTerrain(plot, dug)
	if #entries > 0 then
		PlotService.loadEntries(plot, entries)
	end
	-- сохраняем то, что реально загрузилось (на случай отброшенных блоков)
	BuildService.saveLayout(player)
end)

Players.PlayerRemoving:Connect(function(player)
	StormService.abort(player)
	BuildService.saveLayout(player)
	PlotService.release(player)
end)

-- DataService подключается к PlayerAdded последним, чтобы все обработчики выше уже были готовы.
DataService.init()
