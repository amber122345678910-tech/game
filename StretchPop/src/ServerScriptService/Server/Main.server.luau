--!strict
-- STRETCH-POP · Точка входа сервера. Порядок важен:
-- данные → мир/валидация → хаб Sky Plaza → прогрессия, гача и табло → ретрансляция визуала.

local Players = game:GetService("Players")

-- Персонаж появляется только после загрузки профиля и постройки полосы (см. KineticLevelAndRebirthService)
Players.CharacterAutoLoads = false

local Server = script.Parent
local PlayerDataService = require(Server.Services.PlayerDataService)
local KineticLevelAndRebirthService = require(Server.Services.KineticLevelAndRebirthService)
local ProgressionService = require(Server.Services.ProgressionService)
local StretchReplicationService = require(Server.Services.StretchReplicationService)
local LeaderboardService = require(Server.Services.LeaderboardService)
local LobbyBuilder = require(Server.Level.LobbyBuilder)

PlayerDataService.Init()
KineticLevelAndRebirthService.Init()

-- Хаб строится до первых игроков: полосы причаливают мостами к его краю
local lobby = LobbyBuilder.Build(KineticLevelAndRebirthService.GetWorldFolder())
KineticLevelAndRebirthService.LaneChanged:Connect(function(slot: number, owner: Player?)
	LobbyBuilder.SetSlotOwner(lobby, slot, if owner then (owner.DisplayName ~= "" and owner.DisplayName or owner.Name) else nil)
end)
for _, player in Players:GetPlayers() do
	local slot = KineticLevelAndRebirthService.GetLaneSlot(player)
	if slot then
		LobbyBuilder.SetSlotOwner(lobby, slot, player.DisplayName ~= "" and player.DisplayName or player.Name)
	end
end

ProgressionService.Init()
ProgressionService.BindCapsuleMachines(lobby.Machines)
LeaderboardService.Init(lobby)
StretchReplicationService.Init()
