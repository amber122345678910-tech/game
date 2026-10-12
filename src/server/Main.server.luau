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
local TeamService = require(Services:WaitForChild("TeamService"))

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

print(string.format("[BunkerSimulator] версия %s: под землёй %d слоёв", require(Shared:WaitForChild("Config")).Version, Grid.SURFACE))

PlotService.init()
BuildService.init()
ShopService.init()
StormService.init()
TutorialService.init()
TeamService.init()

-- Когда данные игрока загружены — выдаём участок и строим сохранённый бункер.
local function setupPlot(player: Player, layout: string): boolean
	local plot = PlotService.assign(player)
	if not plot then
		return false
	end
	local entries, dug = Grid.deserialize(layout)
	PlotService.evacuate(plot)
	PlotService.resetTerrain(plot, dug)
	if #entries > 0 then
		PlotService.loadEntries(plot, entries)
	end
	-- сохраняем то, что реально загрузилось (на случай отброшенных блоков)
	BuildService.saveLayout(player)
	return true
end

DataService.Loaded:Connect(function(player, data)
	if player.Parent ~= Players then
		return
	end
	if not setupPlot(player, data.Layout) then
		Remotes.Notify:FireClient(player, "Все участки заняты — участок выдадим, как только кто-нибудь выйдет.", "error")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	StormService.abort(player)
	BuildService.saveLayout(player)
	PlotService.release(player)
	-- участок освободился: отдаём его первому, кто остался без участка
	task.defer(function()
		for _, other in Players:GetPlayers() do
			local data = DataService.get(other)
			if other ~= player and data and not PlotService.getPlot(other) then
				if setupPlot(other, data.Layout) then
					Remotes.Notify:FireClient(other, "Тебе выдан участок! Нажми 📍, чтобы дойти до него.", "success")
				end
				break
			end
		end
	end)
end)

-- DataService подключается к PlayerAdded последним, чтобы все обработчики выше уже были готовы.
DataService.init()
