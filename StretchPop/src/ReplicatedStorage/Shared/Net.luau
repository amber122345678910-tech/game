--!strict
-- STRETCH-POP · Сетевые события. Сами RemoteEvent лежат в ReplicatedStorage.StretchPopNet
-- (создаются в place-файле через default.project.json, поэтому гонок «remote ещё не создан» нет).
--
-- Клиент → Сервер
--   SmashRequest(obstacleId: string, impactVelocity: Vector3, impactPoint: Vector3, impactSpeed: number, combo: number)
--   GongStrike(laneSlot: number, impactVelocity: Vector3, impactSpeed: number, combo: number)
--   ArmVisual(side: "Left"|"Right"|"Ball", active: boolean, point: Vector3?)
--   UpgradeStat(stat: StatName)                          — купить следующий уровень стата
--   GloveAction(action: "Buy"|"Equip", gloveId: string)  — купить / надеть перчатку
--   ProfileSync()                                         — запросить свежий снимок профиля
-- Сервер → Клиент
--   SmashResult(obstacleId: string, accepted: boolean, loot: number, reason: string?)
--   ObstacleSmashed(smasherUserId: number, slot: number, obstacleId: string, snapshot: SmashSnapshot, point: Vector3, velocity: Vector3)
--   GongResult(accepted: boolean, reason: string, needSpeed: number, needCombo: number, speed: number, combo: number)
--   RebirthWave(info: RebirthWaveInfo)
--   ControllerReset(target: CFrame?)
--   PeerArmVisual(player: Player, side: string, active: boolean, point: Vector3?)
--   UpgradeStat(stat: string, accepted: boolean, reason: string, level: number, coins: number)
--   GloveAction(action: string, gloveId: string, accepted: boolean, reason: string)
--   ProfileSync(snapshot: ProfileSnapshot)                — купленные перчатки, рекорды, прогресс локаций

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("StretchPopNet")

local function remote(name: string): RemoteEvent
	local instance = folder:WaitForChild(name)
	if instance:IsA("RemoteEvent") then
		return instance
	end
	error("StretchPopNet." .. name .. " must be a RemoteEvent")
end

local Net = {
	SmashRequest = remote("SmashRequest"),
	SmashResult = remote("SmashResult"),
	ObstacleSmashed = remote("ObstacleSmashed"),
	GongStrike = remote("GongStrike"),
	GongResult = remote("GongResult"),
	RebirthWave = remote("RebirthWave"),
	ControllerReset = remote("ControllerReset"),
	ArmVisual = remote("ArmVisual"),
	PeerArmVisual = remote("PeerArmVisual"),
	UpgradeStat = remote("UpgradeStat"),
	GloveAction = remote("GloveAction"),
	ProfileSync = remote("ProfileSync"),
}

return Net
