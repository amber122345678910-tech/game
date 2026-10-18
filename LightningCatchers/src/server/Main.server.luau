--!strict
-- Точка входа сервера: создаёт ReplicatedStorage.GameState (общее состояние для клиентов)
-- и запускает сервисы по порядку из docs/ARCHITECTURE.md.
-- Сервисы, которых ещё нет в папке Services, пропускаются; ошибка одного сервиса не мешает остальным.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

-- Порядок важен: сервисы подписываются на сигналы тех, кто запущен раньше.
-- SyncService — сразу после данных, RequestService (роутер) — последним.
local ORDER = {
	"DataService",
	"SyncService",
	"PlayerService",
	"EconomyService",
	"StrikeService",
	"PetService",
	"FulguriteService",
	"EventService",
	"CityService",
	"DailyService",
	"LeaderboardService",
	"TutorialService",
	"RequestService",
}

-- Атрибуты GameState по умолчанию (их обновляют EventService и CityService)
local function createGameState()
	local existing = ReplicatedStorage:FindFirstChild("GameState")
	local folder: Instance = if existing then existing else Instance.new("Folder")
	folder.Name = "GameState"
	local defaults: { [string]: any } = {
		CityPoints = 0,
		CityTarget = Config.City.PointsBase,
		CityLit = 0,
		CityBoostUntil = 0,
		Event = "",
		EventEnds = 0,
		NextSupercell = 0,
		NextBall = 0,
		NextRainbow = 0,
		BallZone = 0,
		BallHp = 0,
		BallMaxHp = 0,
		BallFrom = Vector3.zero,
		BallTo = Vector3.zero,
		BallStart = 0,
		BallEnd = 0,
	}
	for name, value in defaults do
		if folder:GetAttribute(name) == nil then
			folder:SetAttribute(name, value)
		end
	end
	-- атрибуты выставлены до появления папки у клиентов
	folder.Parent = ReplicatedStorage
end

local Services = script.Parent:WaitForChild("Services")

local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function startService(name: string)
	local module = Services:FindFirstChild(name)
	if not module then
		return -- ещё не написан
	end
	if not module:IsA("ModuleScript") then
		warn("[Main] " .. name .. " — не ModuleScript, пропускаю")
		return
	end
	local okRequire, service = pcall(require, module)
	if not okRequire then
		warn("[Main] не удалось загрузить " .. name .. ": " .. tostring(service))
		return
	end
	if typeof(service) ~= "table" or typeof(service.start) ~= "function" then
		warn("[Main] у " .. name .. " нет start()")
		return
	end
	local ok, err = xpcall(service.start, traceback)
	if not ok then
		warn("[Main] " .. name .. ".start(): " .. tostring(err))
	end
end

createGameState()
for _, name in ORDER do
	startService(name)
end
