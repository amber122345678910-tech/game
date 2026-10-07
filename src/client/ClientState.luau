--!strict
-- Общее состояние клиента и сигналы между модулями интерфейса и контроллерами.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local UIKit = require(script.Parent:WaitForChild("UI"):WaitForChild("UIKit"))

local player = Players.LocalPlayer

local ClientState = {}

ClientState.Data = nil :: Remotes.DataSnapshot?
ClientState.DataChanged = Signal.new() :: Signal.Signal<Remotes.DataSnapshot>

ClientState.ShopOpen = false
ClientState.ShopToggled = Signal.new() :: Signal.Signal<boolean>
ClientState.ShopTabRequested = Signal.new() :: Signal.Signal<string>

ClientState.BuildMode = false
ClientState.BuildModeChanged = Signal.new() :: Signal.Signal<boolean>

ClientState.TutorialActive = false
ClientState.TutorialChanged = Signal.new() :: Signal.Signal<boolean>

-- Локальные уведомления (тосты): text, kind ("info" | "success" | "error" | "warning")
ClientState.Notified = Signal.new() :: Signal.Signal<string, string>

-- Модальные окна (магазин, результаты) — чтобы не открывать два сразу
ClientState.ModalOpen = false

-- Текущая вкладка магазина ("Blocks" | "Doors" | "Bunkers")
ClientState.ShopTab = "Blocks"
ClientState.ShopTabChanged = Signal.new() :: Signal.Signal<string>

-- Показать стрелку к бункеру
ClientState.WaypointRequested = Signal.new() :: Signal.Signal<>

-- Элементы интерфейса, на которые может указывать обучение (по имени)
ClientState.Elements = {} :: { [string]: GuiObject }

-- Изменился тип ввода (тач / клавиатура / геймпад)
ClientState.InputChanged = Signal.new() :: Signal.Signal<boolean>

function ClientState.notify(text: string, kind: string?)
	ClientState.Notified:Fire(text, kind or "info")
end

function ClientState.isTouch(): boolean
	return UIKit.isTouch()
end

function ClientState.setShopOpen(open: boolean)
	if ClientState.ShopOpen == open then
		return
	end
	ClientState.ShopOpen = open
	ClientState.ShopToggled:Fire(open)
end

function ClientState.setBuildMode(on: boolean)
	if ClientState.BuildMode == on then
		return
	end
	ClientState.BuildMode = on
	ClientState.BuildModeChanged:Fire(on)
end

function ClientState.getPlotModel(): Model?
	local plotId = player:GetAttribute("PlotId")
	if typeof(plotId) ~= "number" then
		return nil
	end
	local folder = workspace:FindFirstChild("Plots")
	if not folder then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("PlotId") == plotId then
			return child
		end
	end
	return nil
end

function ClientState.getPlotById(plotId: number): Model?
	local folder = workspace:FindFirstChild("Plots")
	if not folder then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("PlotId") == plotId then
			return child
		end
	end
	return nil
end

function ClientState.getOrigin(plot: Model): CFrame?
	local origin = plot:GetAttribute("Origin")
	if typeof(origin) == "CFrame" then
		return origin
	end
	return nil
end

-- Идёт ли шторм на моём участке.
function ClientState.inStorm(): boolean
	return player:GetAttribute("InStorm") == true
end

function ClientState.blockCount(id: string): number
	local data = ClientState.Data
	if not data then
		return 0
	end
	return data.Inventory[id] or 0
end

Remotes.DataUpdated.OnClientEvent:Connect(function(snapshot: Remotes.DataSnapshot)
	ClientState.Data = snapshot
	ClientState.DataChanged:Fire(snapshot)
end)

Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string)
	if typeof(text) == "string" then
		ClientState.notify(text, if typeof(kind) == "string" then kind else "info")
	end
end)

UIKit.onInputTypeChanged(function()
	ClientState.InputChanged:Fire(ClientState.isTouch())
end)

return ClientState
