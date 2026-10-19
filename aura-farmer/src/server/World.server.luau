--!strict
-- Сервер: строит Terrain из объёмов TerrainVolumes в декорациях и отдаёт анимации клиенту.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TerrainBuilder = require(script.Parent:WaitForChild("TerrainBuilder"))

-- 1) Анимации: Animation Editor хранит их в ServerStorage.RBX_ANIMSAVES — копируем для клиента.
local out = Instance.new("Folder")
out.Name = "AuraFarmerAnims"
local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
if saves then
	for _, holder in saves:GetChildren() do
		local copy = Instance.new("Folder")
		copy.Name = holder.Name
		for _, kfs in holder:GetChildren() do
			if kfs:IsA("KeyframeSequence") then
				kfs:Clone().Parent = copy
			end
		end
		copy.Parent = out
	end
end
out.Parent = ReplicatedStorage

-- 2) Terrain (если ещё не построен в редакторе).
local world = workspace:WaitForChild("AuraFarmer")
TerrainBuilder.build(world)
workspace:SetAttribute("AuraTerrainReady", true)

-- Готово: клиент ждёт этот атрибут (после копирования всего содержимого).
out:SetAttribute("Ready", true)
