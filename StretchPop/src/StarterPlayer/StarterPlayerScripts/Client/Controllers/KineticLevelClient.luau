--!strict
-- STRETCH-POP · Клиентская сторона KineticLevelAndRebirthService.
-- • Пробития других игроков → те же Squash & Stretch-эффекты (свои уже показаны предсказанием).
-- • Волна перерождения: фронт + поп-анимация деталей, которые сервер снимает/ставит при проходе фронта.
-- • Вердикт Гонга: празднование или «пшик»; в Studio — подсказка, чего не хватило.
-- • Локальный цветовой оттенок мира по тиру своей полосы.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local LevelConfig = require(Shared.Config.LevelConfig)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local KineticVFX = require(Client.Effects.KineticVFX)

local SMASH_RENDER_DISTANCE = 700
local WAVE_RENDER_DISTANCE = 1600
local CELEBRATION_COLOR = Color3.fromRGB(255, 214, 64)

local GONG_REASONS: { [string]: string } = {
	too_slow = "мало скорости",
	combo_too_low = "мало комбо (отскоки шаром / пробития)",
	speed_unverified = "сервер не подтвердил скорость",
	combo_unverified = "сервер не подтвердил комбо",
	too_far = "сервер не увидел тебя у Гонга",
	cooldown = "Гонг ещё звенит, подожди",
	wave_in_progress = "волна ещё идёт",
	not_your_lane = "это Гонг чужой полосы",
	lane_changed = "полоса уже перестроилась",
	no_gong = "Гонг ещё не появился",
}

type ActiveWave = {
	Connections: { RBXScriptConnection },
}

local KineticLevelClient = {}

local player = Players.LocalPlayer
local waves: { [number]: ActiveWave } = {}
local tint: ColorCorrectionEffect? = nil
local started = false

local function laneModel(slot: number): Model?
	local world = workspace:FindFirstChild("StretchPopWorld")
	local lanes = if world then world:FindFirstChild("Lanes") else nil
	local lane = if lanes then lanes:FindFirstChild("Lane_" .. slot) else nil
	if lane and lane:IsA("Model") then
		return lane
	end
	return nil
end

local function ownGong(): BasePart?
	local slot = player:GetAttribute("LaneSlot")
	if typeof(slot) ~= "number" then
		return nil
	end
	local lane = laneModel(slot)
	local mutable = if lane then lane:FindFirstChild("Mutable") else nil
	local gong = if mutable then mutable:FindFirstChild("GongDisc") else nil
	if gong and gong:IsA("BasePart") then
		return gong
	end
	return nil
end

local function cameraDistance(position: Vector3): number
	local camera = workspace.CurrentCamera
	if camera == nil then
		return math.huge
	end
	return (camera.CFrame.Position - position).Magnitude
end

local function isLanePiece(instance: Instance): boolean
	local parent = instance.Parent
	return instance:IsA("BasePart") and parent ~= nil and (parent.Name == "Mutable" or parent.Name == "Obstacles")
end

local function applyTint(tier: number)
	local effect = tint
	if effect == nil then
		return
	end
	local theme = LevelConfig.GetTheme(tier)
	TweenService:Create(effect, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { TintColor = theme.Tint }):Play()
end

local function stopWave(slot: number)
	local wave = waves[slot]
	if wave == nil then
		return
	end
	for _, connection in wave.Connections do
		connection:Disconnect()
	end
	waves[slot] = nil
end

local function onRebirthWave(info: Types.RebirthWaveInfo)
	local isMine = info.OwnerUserId == player.UserId
	if not isMine and cameraDistance(info.LaneOrigin.Position) > WAVE_RENDER_DISTANCE then
		return
	end
	KineticVFX.RebirthWave(info)
	local lane = laneModel(info.Slot)
	if lane == nil then
		return
	end
	stopWave(info.Slot)
	local wave: ActiveWave = { Connections = {} }
	waves[info.Slot] = wave
	table.insert(
		wave.Connections,
		lane.DescendantAdded:Connect(function(descendant: Instance)
			if isLanePiece(descendant) then
				KineticVFX.PopIn(descendant :: BasePart)
			end
		end)
	)
	table.insert(
		wave.Connections,
		lane.DescendantRemoving:Connect(function(descendant: Instance)
			if isLanePiece(descendant) then
				KineticVFX.PopOut(descendant :: BasePart)
			end
		end)
	)
	local untilStart = math.max(info.StartServerTime - workspace:GetServerTimeNow(), 0)
	local duration = (info.EndZ - info.OriginZ) / info.Speed
	task.delay(untilStart + duration + 1.5, function()
		if waves[info.Slot] == wave then
			stopWave(info.Slot)
		end
	end)
end

local function onObstacleSmashed(
	smasherUserId: number,
	_slot: number,
	_obstacleId: string,
	snapshot: Types.SmashSnapshot,
	point: Vector3,
	velocity: Vector3
)
	if smasherUserId == player.UserId then
		return -- уже показано предсказанием
	end
	if cameraDistance(point) <= SMASH_RENDER_DISTANCE then
		KineticVFX.SmashBurst(snapshot, point, velocity)
	end
end

local function onGongResult(accepted: boolean, reason: string, needSpeed: number, needCombo: number, speed: number, combo: number)
	KineticVFX.GongVerdict(ownGong(), accepted, CELEBRATION_COLOR)
	if RunService:IsStudio() then
		if accepted then
			print(string.format("[StretchPop] REBIRTH! Скорость %d, комбо %d — локация перерождается", math.floor(speed), combo))
		else
			print(
				string.format(
					"[StretchPop] Гонг не засчитан: %s (скорость %d / %d, комбо %d / %d)",
					GONG_REASONS[reason] or reason,
					math.floor(speed),
					math.floor(needSpeed),
					combo,
					needCombo
				)
			)
		end
	end
end

function KineticLevelClient.Start()
	if started then
		return
	end
	started = true

	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "StretchPopTierTint"
	effect.TintColor = Color3.new(1, 1, 1)
	effect.Parent = Lighting
	tint = effect
	local tier = player:GetAttribute("LocationTier")
	applyTint(if typeof(tier) == "number" then tier else 0)
	player:GetAttributeChangedSignal("LocationTier"):Connect(function()
		local value = player:GetAttribute("LocationTier")
		applyTint(if typeof(value) == "number" then value else 0)
	end)

	Net.ObstacleSmashed.OnClientEvent:Connect(onObstacleSmashed)
	Net.RebirthWave.OnClientEvent:Connect(onRebirthWave)
	Net.GongResult.OnClientEvent:Connect(onGongResult)
end

return KineticLevelClient
