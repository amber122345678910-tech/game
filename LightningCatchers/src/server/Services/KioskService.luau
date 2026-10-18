--!strict
-- Киоски хаба: ProximityPrompt на метках карты (Map.Markers.Kiosk_* и стойки коконов Cocoon_*).
-- У каждой подсказки атрибут Window — какое окно открыть. Окно открывает сам клиент
-- (Controllers/EventFX слушает ProximityPromptService.PromptTriggered), сервер ничего не решает и не хранит.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Pets = require(Shared:WaitForChild("Pets"))

local KioskService = {}

KioskService.PromptName = "KioskPrompt"

local ACTIVATION_DISTANCE = 10
local MAP_WAIT = 30 -- сколько ждать карту, если её ещё нет

type KioskDef = { Marker: string, Window: string, Action: string, Object: string }

local function definitions(): { KioskDef }
	local list: { KioskDef } = {
		{ Marker = "Kiosk_Shop", Window = "Shop", Action = "Магазин", Object = "Улучшения и острова" },
		{ Marker = "Kiosk_Hatchery", Window = "Pets:cocoons", Action = "Коконы", Object = "Питомцы-искрята" },
		{ Marker = "Kiosk_Gallery", Window = "Collection", Action = "Коллекция", Object = "Фульгуриты и Молниедекс" },
		{ Marker = "Kiosk_Rebirth", Window = "Rebirth", Action = "Перезапуск", Object = "Генератор" },
		{ Marker = "Kiosk_Daily", Window = "Daily", Action = "Награды", Object = "Календарь и задания" },
	}
	for _, id in Pets.CocoonOrder do
		local c = Pets.Cocoons[id]
		if c then
			table.insert(list, {
				Marker = "Cocoon_" .. id,
				Window = "Pets:cocoons",
				Action = "Вылупить",
				Object = string.format("%s · %s 💎", c.Name, Format.short(c.Cost)),
			})
		end
	end
	return list
end

local function addPrompt(marker: Instance, def: KioskDef)
	local existing = marker:FindFirstChild(KioskService.PromptName)
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = KioskService.PromptName
	prompt.ActionText = def.Action
	prompt.ObjectText = def.Object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("Window", def.Window)
	prompt.Parent = marker
end

local function setup(markers: Instance)
	for _, def in definitions() do
		local marker = markers:FindFirstChild(def.Marker)
		if marker and marker:IsA("BasePart") then
			addPrompt(marker, def)
		else
			warn("[KioskService] нет метки " .. def.Marker)
		end
	end
end

function KioskService.start()
	local map = Workspace:FindFirstChild("Map")
	local markers = if map then map:FindFirstChild("Markers") else nil
	if markers then
		setup(markers)
		return
	end
	-- карта ещё не загрузилась (или её нет — например, в тестах): подождать в фоне
	task.spawn(function()
		local m = Workspace:WaitForChild("Map", MAP_WAIT)
		local mk = if m then m:WaitForChild("Markers", MAP_WAIT) else nil
		if mk then
			setup(mk)
		end
	end)
end

return KioskService
