--!strict
-- STRETCH-POP · Клиентские мультяшные эффекты.
-- Все эффекты — локальные детали в workspace.StretchPopLocalFX, анимируются одним циклом RenderStepped
-- (без TweenService и без соединения на каждый эффект). Есть бюджет обломков для слабых ПК.
--   SmashBurst  — Squash & Stretch пробитой стены: сжатие вдоль удара → взрыв на куски с «попом»
--   WallWobble  — стена выдержала: желейное колебание на пружине
--   RebirthWave — фронт трансформации, идущий по полосе синхронно с серверным временем
--   PopIn/PopOut — появление/исчезновение деталей при мутации локации

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Spring = require(Shared.Math.Spring)
local PhysicsConfig = require(Shared.Config.PhysicsConfig)
local LevelConfig = require(Shared.Config.LevelConfig)

type Effect = (dt: number, now: number) -> boolean

type HiddenRecord = {
	Part: BasePart,
	LocalTransparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
}

local MAX_DEBRIS = 160
local MAX_PROXIES = 140
local SQUASH_TIME = 0.07
local DEBRIS_GROUP = PhysicsConfig.CollisionGroups.Debris
local WHITE = Color3.new(1, 1, 1)

local KineticVFX = {}

local folder: Folder? = nil
local effects: { Effect } = {}
local liveDebris = 0
local liveProxies = 0
local wobbling: { [BasePart]: boolean } = {}
local rng = Random.new()
local connection: RBXScriptConnection? = nil

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "StretchPopLocalFX"
	created.Parent = workspace
	folder = created
	return created
end

local function addEffect(effect: Effect)
	table.insert(effects, effect)
end

local function step(dt: number)
	local now = os.clock()
	local index = 1
	while index <= #effects do
		local ok, alive = pcall(effects[index], dt, now)
		if not ok then
			warn("[StretchPop.VFX] effect error: " .. tostring(alive))
		end
		if ok and alive then
			index += 1
		else
			effects[index] = effects[#effects]
			effects[#effects] = nil
		end
	end
end

local function fxPart(
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number
): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = getFolder()
	return part
end

local function shapeOf(part: BasePart): Enum.PartType
	if part:IsA("Part") then
		return part.Shape
	end
	return Enum.PartType.Block
end

-- Локальная ось детали, ближе всего совпадающая с направлением (для сжатия вдоль удара)
local function dominantAxis(cframe: CFrame, direction: Vector3): Vector3
	local localDirection = cframe:VectorToObjectSpace(direction)
	local ax, ay, az = math.abs(localDirection.X), math.abs(localDirection.Y), math.abs(localDirection.Z)
	if az >= ax and az >= ay then
		return Vector3.zAxis
	elseif ax >= ay then
		return Vector3.xAxis
	end
	return Vector3.yAxis
end

-- Кадр с осью X вдоль direction (ось цилиндра Roblox = X)
local function axisFrame(position: Vector3, direction: Vector3): CFrame
	local x = if direction.Magnitude > 1e-5 then direction.Unit else Vector3.yAxis
	local helper = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local z = x:Cross(helper).Unit
	local y = z:Cross(x)
	return CFrame.fromMatrix(position, x, y, z)
end

local function emitSparkles(position: Vector3, color: Color3, count: number, speed: number)
	local holder = fxPart(Enum.PartType.Block, Vector3.one * 0.2, CFrame.new(position), color, Enum.Material.Neon, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(color, WHITE)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Drag = 3
	emitter.Parent = holder
	emitter:Emit(count)
	local born = os.clock()
	addEffect(function(_, now)
		if now - born > 1.4 then
			holder:Destroy()
			return false
		end
		return true
	end)
end

-- ── Публичное API ───────────────────────────────────────────────────────────

function KineticVFX.Init()
	getFolder()
	if connection == nil then
		connection = RunService.RenderStepped:Connect(step)
	end
end

function KineticVFX.GetFolder(): Folder
	return getFolder()
end

function KineticVFX.Snapshot(part: BasePart): Types.SmashSnapshot
	local kind = part:GetAttribute("ObstacleKind")
	return {
		CFrame = part.CFrame,
		Size = part.Size,
		Color = part.Color,
		Material = part.Material,
		Kind = if typeof(kind) == "string" then kind else "Wall",
	}
end

-- Предсказанное пробитие: деталь мгновенно исчезает и перестаёт быть препятствием ТОЛЬКО у этого
-- клиента. Если сервер отклонит удар — возвращённая функция всё восстановит.
function KineticVFX.PredictHide(part: BasePart): () -> ()
	local records: { HiddenRecord } = {}
	local function hide(target: BasePart)
		table.insert(records, {
			Part = target,
			LocalTransparency = target.LocalTransparencyModifier,
			CanCollide = target.CanCollide,
			CanQuery = target.CanQuery,
		})
		target.LocalTransparencyModifier = 1
		target.CanCollide = false
		target.CanQuery = false
	end
	hide(part)
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("BasePart") then
			hide(descendant)
		end
	end
	return function()
		for _, record in records do
			local target = record.Part
			if target.Parent then
				target.LocalTransparencyModifier = record.LocalTransparency
				target.CanCollide = record.CanCollide
				target.CanQuery = record.CanQuery
			end
		end
	end
end

function KineticVFX.ImpactRing(point: Vector3, normal: Vector3, radius: number, color: Color3)
	if liveProxies >= MAX_PROXIES then
		return
	end
	liveProxies += 1
	local ring = fxPart(Enum.PartType.Cylinder, Vector3.new(0.25, 1, 1), axisFrame(point + normal * 0.15, normal), color, Enum.Material.Neon, 0.15)
	local born = os.clock()
	local duration = 0.32
	addEffect(function(_, now)
		local t = (now - born) / duration
		if t >= 1 then
			ring:Destroy()
			liveProxies -= 1
			return false
		end
		local eased = 1 - (1 - t) ^ 3
		local diameter = 1 + radius * 2 * eased
		ring.Size = Vector3.new(0.25, diameter, diameter)
		ring.Transparency = 0.15 + 0.85 * t
		return true
	end)
end

local function puffs(point: Vector3, direction: Vector3, count: number, color: Color3)
	for _ = 1, count do
		if liveProxies >= MAX_PROXIES then
			return
		end
		liveProxies += 1
		local drift = (direction * 0.4 + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 1), rng:NextNumber(-1, 1))).Unit
			* rng:NextNumber(6, 14)
		local puff = fxPart(Enum.PartType.Ball, Vector3.one, CFrame.new(point), color, Enum.Material.SmoothPlastic, 0.2)
		local born = os.clock()
		local life = rng:NextNumber(0.35, 0.55)
		local maxSize = rng:NextNumber(3, 5.5)
		addEffect(function(_, now)
			local t = (now - born) / life
			if t >= 1 then
				puff:Destroy()
				liveProxies -= 1
				return false
			end
			local eased = 1 - (1 - t) ^ 2
			puff.Size = Vector3.one * (1 + (maxSize - 1) * eased)
			puff.CFrame = CFrame.new(point + drift * eased)
			puff.Transparency = 0.2 + 0.8 * t
			return true
		end)
	end
end

local function spawnChunks(snapshot: Types.SmashSnapshot, impactPoint: Vector3, velocity: Vector3, direction: Vector3)
	local budget = math.min(MAX_DEBRIS - liveDebris, 14)
	if budget <= 0 then
		return
	end
	local size = snapshot.Size
	local target = math.max(size.X, size.Y, size.Z) / 3.4
	local counts = {
		math.clamp(math.floor(size.X / target + 0.5), 1, 4),
		math.clamp(math.floor(size.Y / target + 0.5), 1, 4),
		math.clamp(math.floor(size.Z / target + 0.5), 1, 4),
	}
	while counts[1] * counts[2] * counts[3] > budget do
		local largest = 1
		for axis = 2, 3 do
			if counts[axis] > counts[largest] then
				largest = axis
			end
		end
		counts[largest] -= 1
	end
	local chunkSize = Vector3.new(size.X / counts[1], size.Y / counts[2], size.Z / counts[3])
	for ix = 1, counts[1] do
		for iy = 1, counts[2] do
			for iz = 1, counts[3] do
				local offset = Vector3.new(
					(ix - 0.5) / counts[1] - 0.5,
					(iy - 0.5) / counts[2] - 0.5,
					(iz - 0.5) / counts[3] - 0.5
				) * size
				local chunkCFrame = snapshot.CFrame * CFrame.new(offset)
				local chunk = Instance.new("Part")
				chunk.Size = chunkSize * 0.94
				chunk.CFrame = chunkCFrame
				chunk.Color = snapshot.Color:Lerp(WHITE, rng:NextNumber(0, 0.2))
				chunk.Material = snapshot.Material
				chunk.TopSurface = Enum.SurfaceType.Smooth
				chunk.BottomSurface = Enum.SurfaceType.Smooth
				chunk.CanQuery = false
				chunk.CanTouch = false
				chunk.CastShadow = false
				chunk.CollisionGroup = DEBRIS_GROUP
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Brick
				mesh.Scale = Vector3.one * 1.3
				mesh.Parent = chunk
				chunk.Parent = getFolder()

				local away = chunkCFrame.Position - impactPoint
				local outward = if away.Magnitude > 1e-3 then away.Unit else direction
				chunk.AssemblyLinearVelocity = velocity * rng:NextNumber(0.35, 0.75)
					+ outward * rng:NextNumber(18, 42)
					+ Vector3.yAxis * rng:NextNumber(8, 28)
				chunk.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
				liveDebris += 1

				local born = os.clock()
				local life = rng:NextNumber(1.3, 2)
				local pop = Spring.Number.new(1.3, 4.5, 0.35)
				pop.Target = 1
				addEffect(function(dt, now)
					local age = now - born
					if age >= life or chunk.Parent == nil then
						chunk:Destroy()
						liveDebris -= 1
						return false
					end
					local scale = pop:Update(dt)
					local fadeStart = life - 0.35
					if age > fadeStart then
						scale *= math.max(1 - (age - fadeStart) / 0.35, 0.02)
					end
					mesh.Scale = Vector3.one * scale
					return true
				end)
			end
		end
	end
end

local function coinFountain(point: Vector3, count: number)
	for _ = 1, count do
		if liveDebris >= MAX_DEBRIS then
			return
		end
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.3, 1.3, 1.3)
		coin.CFrame = CFrame.new(point) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(90))
		coin.Color = Color3.fromRGB(255, 214, 64)
		coin.Material = Enum.Material.Neon
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.CollisionGroup = DEBRIS_GROUP
		coin.Parent = getFolder()
		coin.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-22, 22), rng:NextNumber(38, 70), rng:NextNumber(-22, 22))
		coin.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-20, 20), rng:NextNumber(-20, 20), rng:NextNumber(-20, 20))
		liveDebris += 1
		local born = os.clock()
		local life = rng:NextNumber(1.2, 1.8)
		addEffect(function(_, now)
			if now - born >= life or coin.Parent == nil then
				coin:Destroy()
				liveDebris -= 1
				return false
			end
			return true
		end)
	end
end

-- Пробитие: сжатие стены вдоль удара (squash) → разлёт кусков с «попом» (stretch/overshoot)
function KineticVFX.SmashBurst(snapshot: Types.SmashSnapshot, impactPoint: Vector3, impactVelocity: Vector3)
	local speed = impactVelocity.Magnitude
	local direction = if speed > 1e-3 then impactVelocity / speed else -snapshot.CFrame.LookVector
	local axis = dominantAxis(snapshot.CFrame, direction)
	local size = snapshot.Size
	local proxy = fxPart(Enum.PartType.Block, size, snapshot.CFrame, snapshot.Color, snapshot.Material, 0)
	liveProxies += 1
	local born = os.clock()
	addEffect(function(_, now)
		local t = (now - born) / SQUASH_TIME
		if t >= 1 then
			proxy:Destroy()
			liveProxies -= 1
			spawnChunks(snapshot, impactPoint, impactVelocity, direction)
			return false
		end
		local phase = math.sin(t * math.pi * 0.5)
		local squash = 1 - 0.45 * phase
		local bulge = 1 + 0.2 * phase
		proxy.Size = size * (axis * squash + (Vector3.one - axis) * bulge)
		proxy.CFrame = snapshot.CFrame + direction * (0.6 * phase)
		return true
	end)
	KineticVFX.ImpactRing(impactPoint, -direction, math.clamp(math.max(size.X, size.Y) * 0.45, 6, 22), WHITE)
	puffs(impactPoint, direction, 5, Color3.fromRGB(255, 250, 240))
	if snapshot.Kind == "Chest" then
		coinFountain(impactPoint + Vector3.yAxis * 2, 12)
		emitSparkles(impactPoint, Color3.fromRGB(255, 220, 80), 30, 26)
	end
end

-- Стена устояла: локальное желе-колебание (настоящая деталь скрыта, качается копия)
function KineticVFX.WallWobble(part: BasePart, impactDirection: Vector3, strength01: number)
	if wobbling[part] or liveProxies >= MAX_PROXIES then
		return
	end
	wobbling[part] = true
	liveProxies += 1
	local size = part.Size
	local cframe = part.CFrame
	local axis = dominantAxis(cframe, impactDirection)
	local previousModifier = part.LocalTransparencyModifier
	part.LocalTransparencyModifier = 1
	local proxy = fxPart(shapeOf(part), size, cframe, part.Color, part.Material, part.Transparency)
	local jelly = Spring.Number.new(0, 4.5, 0.22)
	jelly:Impulse(-3.2 * (0.35 + math.clamp(strength01, 0, 1)))
	local born = os.clock()
	addEffect(function(dt, now)
		local displacement = jelly:Update(dt)
		local finished = now - born > 0.9 or part.Parent == nil
		if finished then
			proxy:Destroy()
			liveProxies -= 1
			wobbling[part] = nil
			if part.Parent then
				part.LocalTransparencyModifier = previousModifier
			end
			return false
		end
		local along = 1 + displacement * 0.55
		local across = 1 - displacement * 0.22
		proxy.Size = size * (axis * along + (Vector3.one - axis) * across)
		return true
	end)
end

function KineticVFX.LaunchBurst(point: Vector3, direction: Vector3, color: Color3)
	KineticVFX.ImpactRing(point, -direction, 7, color)
	puffs(point - direction * 2, -direction, 4, WHITE)
end

-- Мгновенная реакция Гонга на удар (до ответа сервера)
function KineticVFX.GongStrike(gong: BasePart, point: Vector3, impactVelocity: Vector3)
	KineticVFX.WallWobble(gong, impactVelocity, 1)
	KineticVFX.ImpactRing(point, gong.CFrame.RightVector * -1, 26, Color3.fromRGB(255, 240, 180))
	puffs(point, -impactVelocity.Unit, 6, WHITE)
end

-- Вердикт сервера: успех — звёздный взрыв цвета нового тира, провал — серый «пшик»
function KineticVFX.GongVerdict(gong: BasePart?, success: boolean, color: Color3)
	if gong == nil or gong.Parent == nil then
		return
	end
	local center = gong.Position
	if success then
		emitSparkles(center, color, 80, 70)
		for i = 1, 3 do
			task.delay(0.08 * i, function()
				KineticVFX.ImpactRing(center, -gong.CFrame.RightVector, 30 + i * 14, color)
			end)
		end
	else
		puffs(center + Vector3.yAxis * 2, Vector3.yAxis, 6, Color3.fromRGB(150, 150, 160))
		KineticVFX.ImpactRing(center, -gong.CFrame.RightVector, 14, Color3.fromRGB(255, 90, 90))
	end
end

-- Фронт волны перерождения: светящаяся стена + искры, позиция считается по серверному времени,
-- поэтому у всех игроков волна в одном и том же месте полосы.
function KineticVFX.RebirthWave(info: Types.RebirthWaveInfo)
	local theme = LevelConfig.GetTheme(info.Tier)
	local origin = info.LaneOrigin
	local planeSize = Vector3.new(info.LaneWidth + 60, 110, 3)
	local plane = fxPart(Enum.PartType.Block, planeSize, origin * CFrame.new(0, 40, info.OriginZ), theme.Wave, Enum.Material.Neon, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 140
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(theme.Wave, WHITE)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(8, 26)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = plane
	local fadeStarted: number? = nil
	addEffect(function(_, now)
		local elapsed = workspace:GetServerTimeNow() - info.StartServerTime
		if elapsed < 0 then
			return true
		end
		local z = info.OriginZ + info.Speed * elapsed
		if z >= info.EndZ then
			emitter.Enabled = false
			local started = fadeStarted
			if started == nil then
				started = now
				fadeStarted = now
			end
			local t = (now - started) / 0.6
			if t >= 1 then
				plane:Destroy()
				return false
			end
			plane.Transparency = 0.45 + 0.55 * t
			return true
		end
		emitter.Enabled = true
		plane.CFrame = origin * CFrame.new(0, 40, z)
		plane.Transparency = 0.5 + 0.12 * math.sin(now * 18)
		return true
	end)
	local gongPoint = origin:PointToWorldSpace(Vector3.new(0, 24, info.OriginZ + 32))
	task.delay(math.max(info.StartServerTime - workspace:GetServerTimeNow(), 0), function()
		KineticVFX.ImpactRing(gongPoint, Vector3.zAxis, 60, theme.Wave)
		emitSparkles(gongPoint, theme.Wave, 60, 60)
	end)
end

-- Появление детали после мутации: деталь скрыта, «выпрыгивает» копия на недодемпфированной пружине
function KineticVFX.PopIn(part: BasePart)
	if part.Transparency >= 1 or liveProxies >= MAX_PROXIES then
		return
	end
	liveProxies += 1
	local size = part.Size
	local previousModifier = part.LocalTransparencyModifier
	part.LocalTransparencyModifier = 1
	local proxy = fxPart(shapeOf(part), size * 0.05, part.CFrame, part.Color, part.Material, part.Transparency)
	local pop = Spring.Number.new(0.05, 2.6, 0.42)
	pop.Target = 1
	local born = os.clock()
	addEffect(function(dt, now)
		local scale = pop:Update(dt)
		if part.Parent == nil or now - born > 0.85 then
			proxy:Destroy()
			liveProxies -= 1
			if part.Parent then
				part.LocalTransparencyModifier = previousModifier
			end
			return false
		end
		proxy.Size = size * math.max(scale, 0.05)
		proxy.CFrame = part.CFrame
		return true
	end)
end

-- Исчезновение детали (вызывается до удаления): копия раздувается и схлопывается
function KineticVFX.PopOut(part: BasePart)
	if part.Transparency >= 1 or liveProxies >= MAX_PROXIES then
		return
	end
	liveProxies += 1
	local size = part.Size
	local proxy = fxPart(shapeOf(part), size, part.CFrame, part.Color, part.Material, part.Transparency)
	local born = os.clock()
	addEffect(function(_, now)
		local t = (now - born) / 0.28
		if t >= 1 then
			proxy:Destroy()
			liveProxies -= 1
			return false
		end
		local scale = if t < 0.3 then 1 + 0.25 * (t / 0.3) else 1.25 * (1 - (t - 0.3) / 0.7)
		proxy.Size = size * math.max(scale, 0.02)
		return true
	end)
end

return KineticVFX
