--!strict
-- STRETCH-POP · Точка входа сервера. Порядок важен: данные → мир/валидация → ретрансляция визуала.

local Players = game:GetService("Players")

-- Персонаж появляется только после загрузки профиля и постройки полосы (см. KineticLevelAndRebirthService)
Players.CharacterAutoLoads = false

local Server = script.Parent
local PlayerDataService = require(Server.Services.PlayerDataService)
local KineticLevelAndRebirthService = require(Server.Services.KineticLevelAndRebirthService)
local StretchReplicationService = require(Server.Services.StretchReplicationService)

PlayerDataService.Init()
KineticLevelAndRebirthService.Init()
StretchReplicationService.Init()
