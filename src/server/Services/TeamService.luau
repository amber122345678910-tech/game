--!strict
-- Игра с другом: приглашение в свой бункер. Гость строит в бункере хозяина и выживает
-- в его шторме вместе с ним (награду получает каждый). Свой участок у гостя остаётся.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StormService = require(script.Parent.StormService)

local TeamService = {}

local INVITE_TTL = 60 -- секунд действует приглашение
local MAX_MEMBERS = 3 -- гостей в одном бункере

-- invites[гость][UserId хозяина] = время приглашения
local invites: { [Player]: { [number]: number } } = {}
local lastInvite: { [Player]: number } = {}

local function notify(player: Player, text: string, kind: string)
	Remotes.Notify:FireClient(player, text, kind)
end

local function countMembers(plot: PlotService.Plot): number
	local n = 0
	for _ in plot.Members do
		n += 1
	end
	return n
end

local function teleportToPlot(player: Player, plot: PlotService.Plot)
	local character = player.Character
	if character and not StormService.isActive(player) then
		character:PivotTo(plot.Origin * CFrame.new(0, 4, -29))
	end
end

-- Отпустить гостей бункера: они возвращаются на свой участок (иначе остались бы
-- запертыми за закрытой для них дверью чужого бункера).
local function releaseMembers(plot: PlotService.Plot, message: string)
	for member in plot.Members do
		PlotService.removeGuest(member)
		local own = PlotService.getPlot(member)
		if own then
			teleportToPlot(member, own)
		end
		notify(member, message, "info")
	end
end

local function onInvite(host: Player, targetUserId: any)
	if typeof(targetUserId) ~= "number" then
		return
	end
	if os.clock() - (lastInvite[host] or 0) < 1 then
		return
	end
	lastInvite[host] = os.clock()
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == host then
		return
	end
	local plot = PlotService.getPlot(host)
	if not plot then
		notify(host, "У тебя нет участка", "error")
		return
	end
	if PlotService.getHostPlot(host) then
		notify(host, "Ты сейчас в бункере друга. Сначала вернись к себе.", "error")
		return
	end
	if plot.Members[target] then
		notify(host, target.DisplayName .. " уже играет в твоём бункере", "info")
		return
	end
	if countMembers(plot) >= MAX_MEMBERS then
		notify(host, "В бункере уже максимум друзей", "error")
		return
	end
	local list = invites[target]
	if not list then
		list = {}
		invites[target] = list
	end
	list[host.UserId] = os.clock()
	Remotes.TeamInviteReceived:FireClient(target, host.UserId, host.DisplayName)
	notify(host, "Приглашение отправлено: " .. target.DisplayName, "success")
end

local function onRespond(guest: Player, hostUserId: any, accept: any)
	if typeof(hostUserId) ~= "number" or typeof(accept) ~= "boolean" then
		return
	end
	local list = invites[guest]
	local sentAt = list and list[hostUserId]
	if not list or not sentAt then
		return
	end
	list[hostUserId] = nil
	local host = Players:GetPlayerByUserId(hostUserId)
	if not host then
		notify(guest, "Этот игрок уже вышел из игры", "error")
		return
	end
	if not accept then
		notify(host, guest.DisplayName .. " отказался(ась) от приглашения", "info")
		return
	end
	if os.clock() - sentAt > INVITE_TTL then
		notify(guest, "Приглашение устарело — попроси позвать ещё раз", "error")
		return
	end
	if not DataService.get(guest) then
		notify(guest, "Данные ещё загружаются — попробуй через пару секунд", "error")
		list[hostUserId] = sentAt -- приглашение остаётся в силе: показываем его снова
		Remotes.TeamInviteReceived:FireClient(guest, hostUserId, host.DisplayName)
		return
	end
	local own = PlotService.getPlot(guest)
	if StormService.isActive(guest) or (own and own.Session ~= nil) then
		notify(guest, "Дождись конца шторма на своём участке", "error")
		return
	end
	local currentHost = PlotService.getHostPlot(guest)
	if currentHost and currentHost.Session ~= nil then
		notify(guest, "Дождись конца шторма у друга", "error")
		return
	end
	local plot = PlotService.getPlot(host)
	if not plot or PlotService.getHostPlot(host) then
		notify(guest, "Сейчас нельзя присоединиться", "error")
		return
	end
	if plot.Session ~= nil then
		notify(guest, "У друга идёт шторм — прими приглашение после него", "error")
		list[hostUserId] = sentAt
		Remotes.TeamInviteReceived:FireClient(guest, hostUserId, host.DisplayName)
		return
	end
	if countMembers(plot) >= MAX_MEMBERS then
		notify(guest, "В этом бункере уже максимум друзей", "error")
		return
	end
	-- если у самого гостя были гости — они возвращаются к себе
	if own then
		releaseMembers(own, guest.DisplayName .. " ушёл(ла) в другой бункер — ты снова на своём участке.")
	end
	PlotService.addGuest(plot, guest)
	teleportToPlot(guest, plot)
	notify(guest, "👥 Ты в бункере игрока " .. host.DisplayName .. "! Стройте вместе, шторм запускает хозяин.", "success")
	notify(host, "👥 " .. guest.DisplayName .. " теперь в твоём бункере!", "success")
end

local function onLeave(player: Player)
	local hostPlot = PlotService.getHostPlot(player)
	if hostPlot then
		if StormService.isActive(player) or hostPlot.Session ~= nil then
			notify(player, "Нельзя уйти во время шторма", "error")
			return
		end
		PlotService.removeGuest(player)
		local own = PlotService.getPlot(player)
		if own then
			teleportToPlot(player, own)
		end
		notify(player, "Ты вернулся(ась) на свой участок", "info")
		if hostPlot.Owner then
			notify(hostPlot.Owner, player.DisplayName .. " ушёл(ла) из твоего бункера", "info")
		end
		return
	end
	-- хозяин распускает команду
	local plot = PlotService.getPlot(player)
	if not plot or next(plot.Members) == nil then
		return
	end
	if plot.Session ~= nil then
		notify(player, "Нельзя распустить команду во время шторма", "error")
		return
	end
	releaseMembers(plot, player.DisplayName .. " распустил(а) команду — ты снова на своём участке.")
	notify(player, "Команда распущена", "info")
end

function TeamService.init()
	Remotes.TeamInvite.OnServerEvent:Connect(onInvite)
	Remotes.TeamRespond.OnServerEvent:Connect(onRespond)
	Remotes.TeamLeave.OnServerEvent:Connect(onLeave)
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		lastInvite[player] = nil
	end)
end

return TeamService
