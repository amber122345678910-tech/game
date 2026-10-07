--!strict
-- Обучение: сервер только запоминает, что игрок прошёл туториал.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)

local TutorialService = {}

function TutorialService.init()
	Remotes.TutorialDone.OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if data and not data.TutorialDone then
			data.TutorialDone = true
			DataService.replicate(player)
		end
	end)
end

return TutorialService
