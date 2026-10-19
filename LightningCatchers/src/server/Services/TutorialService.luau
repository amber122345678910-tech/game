--!strict
-- Обучение: клиент (Controllers/Tutorial) сообщает о пройденных шагах — сервер запоминает флаги
-- в data.Tutorial, чтобы подсказки не повторялись в следующих сессиях. Принимаются только известные шаги.
-- (Стартовый питомец «Искорка» выдаётся в PetService после первой сдачи банки.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loc = require(Shared:WaitForChild("Loc"))
local Net = require(Shared:WaitForChild("Net"))

local DataService = require(script.Parent.DataService)
local RequestService = require(script.Parent.RequestService)

local TutorialService = {}

-- Шаги, которые может отметить клиент
TutorialService.Steps = {
	catch = true,
	sell = true,
	shop = true,
	pet = true,
	zone2 = true,
	overcharge = true,
} :: { [string]: boolean }

local function tutorialStep(player: Player, payload: any): (boolean, any)
	if typeof(payload) ~= "string" or not TutorialService.Steps[payload] then
		return false, Loc.msg("Неизвестный шаг обучения")
	end
	local step: string = payload
	local d = DataService.get(player)
	if not d then
		return false, Loc.msg("Данные ещё загружаются")
	end
	if d.Tutorial[step] ~= true then
		DataService.update(player, function(data)
			data.Tutorial[step] = true
		end)
	end
	return true, step
end

-- Пройден ли шаг (для других сервисов)
function TutorialService.done(player: Player, step: string): boolean
	local d = DataService.get(player)
	return d ~= nil and d.Tutorial[step] == true
end

function TutorialService.start()
	RequestService.handle(Net.Actions.TutorialStep, tutorialStep)
end

return TutorialService
