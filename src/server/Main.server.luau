--!strict
-- Точка входа сервера: порядок инициализации важен (World → Data → Player → House → Apples → Inmates → Items → Round).

local Services = script.Parent:WaitForChild("Services")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local World = require(Services:WaitForChild("World"))
local DataService = require(Services:WaitForChild("DataService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))
local HouseService = require(Services:WaitForChild("HouseService"))
local AppleService = require(Services:WaitForChild("AppleService"))
local InmateService = require(Services:WaitForChild("InmateService"))
local ItemService = require(Services:WaitForChild("ItemService"))
local RoundService = require(Services:WaitForChild("RoundService"))

print(string.format("[AmberAlert] server v%s", Config.Version))

World.init()
PlayerService.init()
HouseService.init()
AppleService.init()
InmateService.init()
ItemService.init()
RoundService.init()
-- DataService подключается к PlayerAdded последним: к этому моменту все обработчики готовы
DataService.init()
