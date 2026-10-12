--!strict
-- Пациенты на ночь: выбор, спавн тел, тик ИИ (10 Гц), режиссёр напряжения, ловушки, попадания оружия,
-- шум → ИИ, «смотрят ли на Неподвижного», события для клиентов, уход на рассвете.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Inmates = require(Shared:WaitForChild("Inmates"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))

local World = require(script.Parent:WaitForChild("World"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))
local AppleService = require(script.Parent:WaitForChild("AppleService"))
local NoiseService = require(script.Parent:WaitForChild("NoiseService"))
local ServerSounds = require(script.Parent:WaitForChild("ServerSounds"))
local InmateAI = require(script.Parent:WaitForChild("InmateAI"))

local InmateService = {}

InmateService.Active = {} :: { InmateAI.Inmate }
InmateService.Defeated = Signal.new() :: Signal.Signal<string>
InmateService.Event = Signal.new() :: Signal.Signal<string, string, Vector3>
-- Заполняет ItemService (кража Собирателем)
InmateService.lootAt = function(_pos: Vector3): Vector3?
	return nil
end :: (Vector3) -> Vector3?
InmateService.stealAt = function(_pos: Vector3): boolean
	return false
end :: (Vector3) -> boolean

type Trap = { Instance: Instance, ItemId: string, Position: Vector3, Armed: boolean }
local traps: { Trap } = {}
local rng = Random.new()
local running = false
local difficulty = Config.getDifficulty(nil)

-- Режиссёр
local directorPhase = "BuildUp" -- BuildUp | Sustain | PeakFade | Relax
local directorUntil = 0
local bossNight = false

local function onEvent(kind: string, inmate: InmateAI.Inmate, position: Vector3)
	InmateService.Event:Fire(kind, inmate.Id, position)
	if kind == "Defeated" then
		InmateService.Defeated:Fire(inmate.Id)
	end
	if kind ~= "Steal" and kind ~= "Drop" then
		Remotes.InmateEvent:FireAllClients(kind, inmate.Id, position)
	end
end

----------------------------------------------------------------------
-- Спавн
----------------------------------------------------------------------
local function spawnBody(def: Inmates.InmateDef, index: number, position: Vector3)
	local inmate = InmateAI.new(def, index, position, difficulty, rng, onEvent)
	-- Веспер появляется сразу в комнате
	if def.Kind == "Sentinel" then
		local spots = World.VesperSpots
		if #spots > 0 then
			local spot = spots[rng:NextInteger(1, #spots)]
			inmate.Model:PivotTo(CFrame.new(spot.Position + Vector3.new(0, 3 * def.Look.Scale.Y, 0)))
			inmate.RoomNameSentinel = spot.Room
			inmate:setState("Sentinel")
			inmate.EntryStage = 2
		end
	end
	table.insert(InmateService.Active, inmate)
	return inmate
end

function InmateService.spawnForNight(night: number, ids: { string }, diff: Config.DifficultyDef)
	difficulty = diff
	InmateService.clear()
	running = true
	bossNight = false
	directorPhase = "BuildUp"
	directorUntil = 0
	for _, id in ids do
		local def = Inmates.get(id)
		if def then
			if def.Kind == "Boss" then
				bossNight = true
			end
			for b = 1, def.Bodies do
				local pos = World.randomInmateSpawn(rng)
				if b > 1 then
					pos += Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
				end
				spawnBody(def, b, pos)
			end
		end
	end
	-- Твины: каждый идёт к своему входу (разные)
end

function InmateService.retreatAll()
	running = false
	for _, inmate in InmateService.Active do
		inmate:retreat()
	end
end

-- Убрать всех пациентов (ловушки остаются до конца матча)
function InmateService.clear()
	running = false
	for _, inmate in InmateService.Active do
		inmate:despawn()
	end
	table.clear(InmateService.Active)
	local folder = workspace:FindFirstChild("Inmates")
	if folder then
		folder:ClearAllChildren()
	end
end

-- Убрать ловушки (новый матч)
function InmateService.clearTraps()
	for _, t in traps do
		if t.Instance.Parent then
			t.Instance:Destroy()
		end
	end
	table.clear(traps)
end

function InmateService.activeIds(): { string }
	local list = {}
	for _, inmate in InmateService.Active do
		if not inmate.Despawned and not table.find(list, inmate.Id) then
			table.insert(list, inmate.Id)
		end
	end
	return list
end

function InmateService.anyActive(): boolean
	for _, inmate in InmateService.Active do
		if not inmate.Despawned then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Ловушки
----------------------------------------------------------------------
function InmateService.registerTrap(inst: Instance, itemId: string)
	local pos = if inst:IsA("Model") then inst:GetPivot().Position elseif inst:IsA("BasePart") then inst.Position else Vector3.zero
	table.insert(traps, { Instance = inst, ItemId = itemId, Position = pos, Armed = true })
end

function InmateService.unregisterTrap(inst: Instance)
	for i, t in traps do
		if t.Instance == inst then
			table.remove(traps, i)
			return
		end
	end
end

local function checkTraps(inmate: InmateAI.Inmate)
	if inmate.State == "Enter" or inmate.State == "Retreat" or inmate.Def.Kind == "Sentinel" then
		return
	end
	local pos = inmate:position()
	for i = #traps, 1, -1 do
		local t = traps[i]
		if not t.Instance.Parent then
			table.remove(traps, i)
		elseif t.Armed and (t.Position - pos).Magnitude < 2.6 then
			local def = Config.getItem(t.ItemId)
			t.Armed = false
			table.remove(traps, i)
			ServerSounds.playAt("TrapSnap", t.Position, 1, 1, 120)
			NoiseService.emit(t.Position, "Trap")
			if def then
				if def.Stun > 0 then
					inmate:stun(def.Stun, false)
				end
				if def.Damage > 0 then
					inmate:damage(def.Damage, 0, nil)
				end
				if def.Slow > 0 then
					inmate.SlowUntil = os.clock() + def.SlowTime
				end
			end
			t.Instance:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- Оружие
----------------------------------------------------------------------
local weaponParams = RaycastParams.new()
weaponParams.FilterType = Enum.RaycastFilterType.Exclude

local function inmateFromPart(part: Instance?): InmateAI.Inmate?
	if not part then
		return nil
	end
	for _, inmate in InmateService.Active do
		if not inmate.Despawned and part:IsDescendantOf(inmate.Model) then
			return inmate
		end
	end
	return nil
end

-- Луч (дробовик, шокер): попадает в первого пациента на линии
function InmateService.hitRay(origin: Vector3, direction: Vector3, range: number, damage: number, stun: number, knockback: number, by: Player?): boolean
	local exclude: { Instance } = {}
	if by and by.Character then
		table.insert(exclude, by.Character)
	end
	local traps = workspace:FindFirstChild("Traps")
	if traps then
		table.insert(exclude, traps)
	end
	weaponParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(origin, direction.Unit * range, weaponParams)
	local inmate = if hit then inmateFromPart(hit.Instance) else nil
	if not inmate then
		-- широкий конус для дробовика: ближайший пациент в 15°
		local best: InmateAI.Inmate? = nil
		local bestDist = range
		for _, cand in InmateService.Active do
			if not cand.Despawned then
				local to = cand:position() - origin
				local d = to.Magnitude
				if d < bestDist and to.Unit:Dot(direction.Unit) > 0.966 then
					local blocked = cand:canSeePoint(origin, exclude) == false
					if not blocked then
						best = cand
						bestDist = d
					end
				end
			end
		end
		inmate = best
	end
	if not inmate then
		return false
	end
	if stun > 0 then
		inmate:stun(stun, false)
	end
	if damage > 0 then
		inmate:damage(damage, knockback, origin)
	end
	return true
end

-- Конус (перцовка): все пациенты в конусе
function InmateService.hitCone(origin: Vector3, direction: Vector3, range: number, cosHalf: number, damage: number, stun: number, forget: boolean, _by: Player?): boolean
	local any = false
	for _, inmate in InmateService.Active do
		if not inmate.Despawned then
			local to = inmate:position() - origin
			if to.Magnitude <= range and to.Unit:Dot(direction.Unit) >= cosHalf then
				any = true
				if stun > 0 then
					inmate:stun(stun, forget)
				end
				if damage > 0 then
					inmate:damage(damage, 0, origin)
				end
			end
		end
	end
	return any
end

----------------------------------------------------------------------
-- Запросы от PlayerService
----------------------------------------------------------------------
local function nearestLethalDistance(position: Vector3): number
	local best = math.huge
	for _, inmate in InmateService.Active do
		local state: InmateAI.State = inmate.State
		if not inmate.Despawned and inmate.Lethal and state ~= "Retreat" then
			best = math.min(best, (inmate:position() - position).Magnitude)
		end
	end
	return best
end

local function isWatched(player: Player): boolean
	for _, inmate in InmateService.Active do
		if not inmate.Despawned and inmate.Def.OpensHiding and inmate:canSeePlayer(player) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- Режиссёр
----------------------------------------------------------------------
local function updateDirector(dt: number)
	local t = os.clock()
	local maxI = PlayerService.maxIntensity()
	local relax = false
	if bossNight then
		directorPhase = "BuildUp"
	elseif directorPhase == "BuildUp" then
		if maxI > Config.Director.PeakThreshold then
			directorPhase = "Sustain"
			directorUntil = t + Config.Director.SustainSeconds
		end
	elseif directorPhase == "Sustain" then
		if t >= directorUntil then
			directorPhase = "PeakFade"
			directorUntil = t + 6
			-- "за кулисы": дать цели дальнюю комнату (без телепорта)
			for _, inmate in InmateService.Active do
				local state: InmateAI.State = inmate.State
				if not inmate.Despawned and state ~= "Chase" and inmate.Def.Kind ~= "Sentinel" and inmate.Def.Kind ~= "StillOne" then
					local wp = World.randomWaypoint(rng, World.roomNameAt(inmate:position()))
					if wp then
						inmate:setState("Roam")
						inmate.Goal = wp.Position
					end
				end
			end
		end
	elseif directorPhase == "PeakFade" then
		if t >= directorUntil then
			directorPhase = "Relax"
			directorUntil = t + rng:NextNumber(Config.Director.RelaxMin, Config.Director.RelaxMax)
		end
	elseif directorPhase == "Relax" then
		relax = true
		if t >= directorUntil then
			directorPhase = "BuildUp"
		end
	end
	-- Подсказка "общая зона отряда": центр масс живых игроков
	local sum = Vector3.zero
	local n = 0
	for _, player in Players:GetPlayers() do
		local rec = PlayerService.get(player)
		local root = PlayerService.rootPart(player)
		if rec and rec.InHouse and rec.Status == "Alive" and root then
			sum += root.Position
			n += 1
		end
	end
	local hint = if n > 0 then sum / n else nil
	for _, inmate in InmateService.Active do
		inmate.Relax = relax
		if hint and (not inmate.Hint or os.clock() > inmate.HintUntil) then
			inmate.Hint = hint
			inmate.HintUntil = os.clock() + 12
		end
		-- интенсивность по близости
		if inmate.Lethal and not inmate.Despawned then
			for _, player in Players:GetPlayers() do
				local root = PlayerService.rootPart(player)
				local rec = PlayerService.get(player)
				if root and rec and rec.InHouse and PlayerService.isAlive(rec) and (root.Position - inmate:position()).Magnitude < Config.Director.NearDistance then
					PlayerService.addIntensity(player, Config.Director.Near * dt)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Тик
----------------------------------------------------------------------
local ctx = {
	lootAt = function(pos: Vector3): Vector3?
		return InmateService.lootAt(pos)
	end,
	steal = function(pos: Vector3): boolean
		if AppleService.stealNear(pos, 4) then
			return true
		end
		return InmateService.stealAt(pos)
	end,
}

local function tick(dt: number)
	if #InmateService.Active == 0 then
		return
	end
	if running then
		updateDirector(dt)
	end
	for i = #InmateService.Active, 1, -1 do
		local inmate = InmateService.Active[i]
		if inmate.Despawned then
			table.remove(InmateService.Active, i)
		else
			local ok, err = pcall(function()
				inmate:update(dt, ctx)
				checkTraps(inmate)
			end)
			if not ok then
				warn("[Inmates] update failed: " .. tostring(err))
			end
		end
	end
end

function InmateService.init()
	PlayerService.nearestLethalDistance = nearestLethalDistance
	PlayerService.isWatched = isWatched
	NoiseService.Emitted:Connect(function(noise)
		for _, inmate in InmateService.Active do
			inmate:onNoise(noise)
		end
	end)
	Remotes.LookingAt.OnServerEvent:Connect(function(player, inmateId, looking)
		if typeof(inmateId) ~= "string" or typeof(looking) ~= "boolean" then
			return
		end
		local rec = PlayerService.get(player)
		if not rec or not PlayerService.isAlive(rec) then
			looking = false
		end
		for _, inmate in InmateService.Active do
			if inmate.Id == inmateId and inmate.Def.Kind == "StillOne" then
				if looking then
					-- проверка: персонаж смотрит примерно в сторону пациента и есть видимость
					local root = PlayerService.rootPart(player)
					local eye = PlayerService.eyePosition(player)
					if root and eye then
						local to = inmate.Head.Position - eye
						if to.Magnitude < 90 and root.CFrame.LookVector:Dot(to.Unit) > 0.3 and inmate:canSeePoint(eye, { player.Character :: Instance }) then
							inmate.LookedAtBy[player.UserId] = true
						end
					end
				else
					inmate.LookedAtBy[player.UserId] = nil
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, inmate in InmateService.Active do
			inmate.LookedAtBy[player.UserId] = nil
		end
	end)
	-- Игрок спрятался на глазах у пациента → тот идёт проверять
	PlayerService.Hid:Connect(function(player, hideId, watched)
		if not watched then
			return
		end
		for _, inmate in InmateService.Active do
			if not inmate.Despawned and inmate.Def.OpensHiding and inmate:canSeePlayer(player) == false then
				if inmate.Target == player or (inmate:position() - (PlayerService.rootPart(player) and (PlayerService.rootPart(player) :: BasePart).Position or inmate:position())).Magnitude < 30 then
					inmate:goCheckHidingSpot(hideId, Config.Hiding.SearchChanceSeen)
				end
			end
		end
	end)
	-- Неподвижный: по таймауту сбрасываем "смотрят", если игрок пропал
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			local step = acc
			acc = 0
			tick(step)
		end
	end)
end

return InmateService
