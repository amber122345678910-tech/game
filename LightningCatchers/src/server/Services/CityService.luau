--!strict
-- Электроград — общая цель сервера:
--  * каждая сдача банки (EconomyService.Sold) добавляет очки = заполнение банки (от 0.2 до 1.5);
--  * цель = PointsBase + PointsPerPlayer × игроков; кварталы горят по доле: CityLit = ⌊очки / цель × Districts⌋;
--  * шкала полна → «Город сияет»: ×CityBoost Вольт всем на CityBoostDuration с, все кварталы горят,
--    баннер и Effect cityLit всем; очки начинаются заново (во время сияния шкала не копится);
--  * после сияния город гаснет по одному кварталу за DecayDelay / Districts с, пока не совпадёт с новыми очками.
-- Атрибуты GameState: CityPoints, CityTarget, CityLit, CityBoostUntil. API: boostActive().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))

local EconomyService = require(script.Parent.EconomyService)

local CityService = {}

-- () — город засиял
CityService.Lit = Signal.new() :: Signal.Signal<>

local TICK = 0.5
local MIN_POINTS = 0.2 -- очки за сдачу почти пустой банки
local C = Config.City

local gameState: Instance? = nil
local bannerRemote: RemoteEvent? = nil
local effectRemote: RemoteEvent? = nil
local notifyRemote: RemoteEvent? = nil

local points = 0
local boostUntil = 0
local lit = 0 -- сколько кварталов горит сейчас
local nextDecay = 0 -- когда погасить следующий квартал
local boosting = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setAttr(name: string, value: any)
	local gs = gameState
	if gs and gs:GetAttribute(name) ~= value then
		gs:SetAttribute(name, value)
	end
end

local function target(): number
	return C.PointsBase + C.PointsPerPlayer * #Players:GetPlayers()
end

-- Сколько кварталов должно гореть по очкам
local function litByPoints(): number
	return math.clamp(math.floor(points / target() * C.Districts), 0, C.Districts)
end

local function publish()
	setAttr("CityPoints", math.floor(points * 100 + 0.5) / 100)
	setAttr("CityTarget", target())
	setAttr("CityLit", lit)
	setAttr("CityBoostUntil", boostUntil)
end

function CityService.boostActive(): boolean
	return now() < boostUntil
end

local function startBoost()
	local t = now()
	boosting = true
	boostUntil = t + Config.Multipliers.CityBoostDuration
	points = 0
	lit = C.Districts
	publish()
	local minutes = math.floor(Config.Multipliers.CityBoostDuration / 60 + 0.5)
	local banner = bannerRemote
	if banner then
		banner:FireAllClients(
			string.format("🏙 ЭЛЕКТРОГРАД СИЯЕТ! %s Вольт на %d %s", "×" .. string.sub(Format.mult(Config.Multipliers.CityBoost), 2), minutes, Format.plural(minutes, "минуту", "минуты", "минут")),
			"city"
		)
	end
	local fx = effectRemote
	if fx then
		local msg: Net.EffectMsg = { Kind = "cityLit", Value = boostUntil }
		fx:FireAllClients(msg)
	end
	CityService.Lit:Fire()
end

-- Шкала заполнилась?
local function checkFull()
	if not boosting and points >= target() then
		startBoost()
	end
end

local function onSold(_player: Player, _volts: number, fill: number)
	if boosting then
		return -- во время сияния шкала не копится: цикл начнётся заново после него
	end
	local add = if typeof(fill) == "number" and fill == fill then math.clamp(fill, MIN_POINTS, Config.Overcharge.MaxFill) else MIN_POINTS
	points += add
	lit = math.max(lit, litByPoints())
	checkFull()
	publish()
end

local function tick()
	local t = now()
	if boosting and t >= boostUntil then
		boosting = false
		nextDecay = t + C.DecayDelay / C.Districts
		local notify = notifyRemote
		if notify then
			notify:FireAllClients("🏙 Электроград гаснет — сдавайте банки, чтобы зажечь снова!", "info")
		end
	end
	if not boosting then
		local want = litByPoints()
		if lit > want then
			-- гаснет по одному кварталу
			if t >= nextDecay then
				lit -= 1
				nextDecay = t + C.DecayDelay / C.Districts
			end
		elseif lit < want then
			lit = want
		end
		checkFull() -- игроки ушли — цель могла стать меньше очков
	end
	publish()
end

function CityService.start()
	gameState = ReplicatedStorage:FindFirstChild("GameState") or Net.gameState()
	bannerRemote = Net.event("Banner")
	effectRemote = Net.event("Effect")
	notifyRemote = Net.event("Notify")

	EconomyService.setCityBoostProvider(CityService.boostActive)
	EconomyService.Sold:Connect(onSold)
	Players.PlayerAdded:Connect(function()
		publish()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(publish) -- игрок ещё в списке во время PlayerRemoving
	end)
	publish()

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[CityService] " .. tostring(err))
			end
		end
	end)
end

return CityService
