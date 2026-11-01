--!strict
-- LoginService (P70): daily login streak (SPEC §1.6, genre idea 17) and the UTC day clock.
-- When a profile loads — and at every UTC midnight for players who stay online — the streak advances
-- (Rewards.LoginStreak: +1 for consecutive days; after missed days it decays softly by Rewards.STREAK_DECAY per
-- missed day instead of resetting) and pays Rewards.StreakGold(streak) G (bigger every 7th day).
-- Notify "prog.notify.streak" / "prog.notify.streakSoft" {day, gold} (style "Reward"); a brand-new player also
-- gets "prog.notify.welcome". First-win-of-day state lives in Profile.Login.FirstWinDay (RewardService sets it,
-- the view exposes Meta.FirstWinAvailable).
--
-- API: Today() -> number (UTC day index), FirstWinAvailable(player) -> boolean, Process(player) -> boolean
-- (advance + pay if a new day; idempotent within a day). No requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net")) :: any
local Rewards = require(Shared:WaitForChild("Progression"):WaitForChild("Rewards")) :: any

local LoginService = {}
LoginService.Priority = 70

local CHECK_INTERVAL = 30

local DataService: any = nil

local function tryService(name: string): any
	local module = (script.Parent :: Instance):FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function notify(player: Player, key: string, args: { any }?, style: string?)
	if player.Parent then
		pcall(Net.Server.Fire, "Notify", player, key, args, style)
	end
end

function LoginService.Today(): number
	return Rewards.Day(os.time())
end

function LoginService.FirstWinAvailable(player: Player): boolean
	local profile = if DataService then DataService.Get(player) else nil
	return profile ~= nil and Rewards.FirstWinAvailable(profile, LoginService.Today())
end

function LoginService.Process(player: Player): boolean
	if DataService == nil then
		return false
	end
	local profile = DataService.Get(player)
	if profile == nil then
		return false
	end
	local today = LoginService.Today()
	if profile.Login.LastDay == today then
		return false
	end
	local paid: number? = nil
	local streak = 0
	local soft = false
	local first = false
	DataService.Update(player, function(p: any)
		local login = p.Login
		local newStreak, isNew = Rewards.LoginStreak(login.LastDay, login.Streak, today)
		if not isNew then
			return
		end
		first = login.LastDay <= 0
		soft = not first and today - login.LastDay > 1
		login.LastDay = today
		login.Streak = newStreak
		login.Best = math.max(login.Best or 0, newStreak)
		p.Stats.LoginDays = (p.Stats.LoginDays or 0) + 1
		local gold = Rewards.StreakGold(newStreak)
		Rewards.Grant(p, 0, gold)
		paid = gold
		streak = newStreak
	end)
	if paid == nil then
		return false
	end
	if first then
		notify(player, "prog.notify.welcome", { player.DisplayName }, "Info")
	end
	notify(player, if soft then "prog.notify.streakSoft" else "prog.notify.streak", { streak, paid }, "Reward")
	return true
end

function LoginService.Init()
	DataService = tryService("DataService")
end

function LoginService.Start()
	if DataService == nil then
		return
	end
	DataService.Loaded:Connect(function(player: Player)
		-- let the client finish mounting its UI so the toast is seen
		task.delay(4, function()
			if player.Parent then
				LoginService.Process(player)
			end
		end)
	end)
	task.spawn(function()
		local lastDay = LoginService.Today()
		while true do
			task.wait(CHECK_INTERVAL)
			local today = LoginService.Today()
			if today ~= lastDay then
				lastDay = today
				for _, player in Players:GetPlayers() do
					task.spawn(function()
						local ok, err = pcall(LoginService.Process, player)
						if not ok then
							warn("[LoginService] " .. tostring(err))
						end
					end)
				end
			end
		end
	end)
end

return LoginService
